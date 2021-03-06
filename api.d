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
import core.thread;

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
        static ThreadGroup cb_threads;
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
            position = 0;
            unlock();
        }

        /**
         * Load MIDI data for playback. If tracks is given,
         * load only those in the array.
         */
        static void load(MidiData data, ulong[] tracks = []) {
            while (!lock()) {}
            evbuf = MidiEventBuffer.create(data, tracks);
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
         * Wait for playback to end.  If a callback is given,
         * call it with the value of note_index whenever
         * a note is played (more or less.)  If block is false,
         * another thread will be created to run the callback
         * and the call to wait() will not block.  An optional
         * function to be called when playback stops can be given.
         */
        static void wait() {
            while (playing) {}
        }

        /// ditto
        static void wait(void function(ulong) callback,
                         bool block = true,
                         void function() finish_callback = null) {
            auto dg = () {
                ulong pold = 0;
                while (playing) {
                    while (pold < position) {
                        callback(pold++);
                    }
                }
                while (pold < position) {
                    callback(pold++);
                }
                if (finish_callback)
                    finish_callback();
            };

            if (block) {
                dg();
            } else {
                cb_threads.create(dg);
            }
        }

        /**
         * Wait for all callback threads to complete.
         */
        static void join_callbacks() {
            cb_threads.joinAll();
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
            void* port_buf = jack_port_get_buffer(Sequencer.output_port, n_frames);
            jack_midi_clear_buffer(port_buf);

            if (Sequencer.playing && Sequencer.evbuf !is null) {

                Sequencer.evbuf.advance(n_frames);

                while (true) {
                    auto ev = Sequencer.evbuf.pop_next();
                    
                    if (ev) {
                        if (ev.type == 0x90 && (cast(MidiNoteOnEvent)ev).param2 > 0) {
                            Sequencer.position++;
                        }

                        if (ev.type == 0xFF) {
                            auto mev = cast(MidiMetaEvent)ev;
                            if (mev.subtype == 0x51) {
                                Sequencer.evbuf.tempo = (cast(MidiSetTempoEvent)mev).microseconds_per_quarter;
                            }
                        }

                        version (PRINT_OUTGOING_EVENTS) {
                            stderr.writeln(ev, " (offset = ", Sequencer.evbuf.offset, ")");
                        }

                        ubyte* buf = cast(ubyte*)jack_midi_event_reserve(port_buf, Sequencer.evbuf.offset, ev.size);

                        if (buf) {
                            ev.buffer(buf);
                        } else {
                            version (WARN_CANNOT_BUFFER) {
                                stderr.writeln("Warning: failed to reserve space in JACK buffer for outgoing event");
                            }
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
