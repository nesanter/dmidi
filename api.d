/**
 * MIDI+JACK Frontend API
 *
 * Authors: Noah Santer, nesanter@knox.edu
 */

module midi.api;

import std.string;
import core.atomic;

import midi.parser;
import jack.header;

class JackException : Exception {
    this(string msg) {
        super(msg);
    }
}

abstract class Sequencer {
    protected {
        __gshared static bool playing;
        __gshared static MidiEventBuffer evbuf;
        __gshared jack_client_t* client;
        __gshared static jack_port_t* output_port;

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
        static void play() {
            while (!lock()) {}
            playing = true;
            unlock();
        }

        static void pause() {
            while (!lock()) {}
            playing = false;
            unlock();
        }

        static void rewind() {
            while (!lock()) {}
            evbuf.rewind();
            unlock();
        }

        static void load(MidiData data) {
            while (!lock()) {}
            evbuf = MidiEventBuffer.create(data, [1]);
            if (client)
                evbuf.sample_rate = jack_get_sample_rate(client);
            unlock();
        }

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

        static void deactivate() {
            jack_client_close(client);
        }

        static void wait() {
            while (playing) {}
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
                        ubyte* buf = cast(ubyte*)jack_midi_event_reserve(port_buf, Sequencer.evbuf.offset, ev.size);

                        if (buf) {
                            ev.buffer(buf);
                        } else {
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
