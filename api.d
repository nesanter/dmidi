/**
 * MIDI+JACK Frontend API
 *
 * Authors: Noah Santer, nesanter@knox.edu
 */

module midi.api;

version (PRINT_OUTGOING_EVENTS) {
    pragma(msg, "Warning: PRINT_OUTGOING_EVENTS conflicts with the realtime nature of JACK");
}
import std.stdio;
import std.string;
import core.atomic;

import midi.parser;
import jack.header;

class JackException : Exception {
    this(string msg) {
        super(msg);
    }
}

/**
 * Sequencer provides an abstract interface to the MIDI and JACK
 * libraries.
 */
abstract class Sequencer {
    protected {
        __gshared static bool playing;
        __gshared static MidiEventBuffer evbuf;
        __gshared static jack_client_t* client;
        __gshared static jack_port_t* output_port;
        __gshared static ulong position;

        static bool lock() {
            return cas(&lock_playing, false, true);
        }

        static void unlock() {
            lock_playing = false;
        }
    }

    private {
        static shared bool lock_playing;
    }

    public {
        /**
         * Play the loaded MIDI data
         */
        static void play() {
            while (!lock()) {}
            playing = true;
            unlock();
        }

        /**
         * Pause playback
         */
        static void pause() {
            while (!lock()) {}
            playing = false;
            unlock();
        }

        /**
         * Rewind the data to the beginning
         */
        static void rewind() {
            while (!lock()) {}
            evbuf.rewind();
            unlock();
        }

        /**
         * Load MIDI data for playback
         */
        static void load(MidiData data) {
            while (!lock()) {}
            evbuf = MidiEventBuffer.create(data, [1]);
            if (client)
                evbuf.sample_rate = jack_get_sample_rate(client);
            unlock();
        }

        /**
         * Activate the JACK subsystem
         */
        static void activate(string appname = "dmidi") {
           client = jack_client_open(toStringz(appname), JackOptions.JackNullOption, null);

           if (client is null) {
               throw new JackException("jack_client_open() failed");
           }
           
           if (evbuf)
               evbuf.sample_rate = jack_get_sample_rate(client);

           jack_set_process_callback(client, &jack_process, null);

           output_port = jack_port_register(client, "out", JACK_DEFAULT_MIDI_TYPE, JackPortFlags.JackPortIsOutput, 0);

           if (output_port is null) {
               throw new JackException("jack_port_register() failed");
           }

           if (jack_activate(client)) {
               throw new JackException("jack_activate() failed");
           }
        }

        /**
         * Deactivate the JACK subsystem
         */
        static void deactivate() {
            jack_client_close(client);
        }

        /**
         * Wait for playback to end
         */
        static void wait() {
            while (playing) {}
        }

        /**
         * The index of the last note played
         */
        static @property ulong note_index() {
            return position;
        }

        /**
         * Seek to a specific note index
         */
        static void seek(ulong note) {
            while (!lock()) {}

            evbuf.rewind();

            auto fn = (MidiEvent ev) { return (ev.type == 0x90 && (cast(MidiNoteOnEvent)ev).param2 > 0); };

            evbuf.skip(note, fn, true);

            position = note;

            unlock();
        }
    }
}

private {
    extern (C) int jack_process(jack_nframes_t n_frames, void* arg) {
        if (Sequencer.lock()) {
            if (Sequencer.playing && Sequencer.evbuf !is null) {
                void* port_buf = jack_port_get_buffer(Sequencer.output_port, n_frames);
                jack_midi_clear_buffer(port_buf);

                Sequencer.evbuf.advance(n_frames);

                while (true) {
                    auto ev = Sequencer.evbuf.pop_next();
                    
                    if (ev) {
                        if (ev.type == 0x90) {
                            Sequencer.position++;
                        }

                        version (PRINT_OUTGOING_EVENTS) {
                            writeln(ev, " (offset = ", Sequencer.evbuf.offset);
                        }

                        ubyte* buf = cast(ubyte*)jack_midi_event_reserve(port_buf, Sequencer.evbuf.offset, ev.size);

                        if (buf) {
                            ev.buffer(buf);
                        } else {
                            writeln("oops");
                            break;
                        }
                    } else {
                        break;
                    }
                }
            }

            if (Sequencer.evbuf.empty) {
                Sequencer.playing = false;
            }
            Sequencer.unlock();
        }

        return 0;
    }
}
