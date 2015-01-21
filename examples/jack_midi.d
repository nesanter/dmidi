import std.stdio;

import midi;
import jack.header;

__gshared jack_client_t* client;
__gshared jack_port_t* output_port;
__gshared MidiEventBuffer evbuf;

extern (C) int process(jack_nframes_t nframes, void* arg) {

    void* port_buf = jack_port_get_buffer(output_port, nframes);
    jack_midi_clear_buffer(port_buf);

    evbuf.advance(nframes);

    while (true) {
        auto ev = evbuf.pop_next();
        if (ev) {
            version (VERBOSE) {
                writeln("ev = ", ev, "; offset = ", evbuf.offset);
            }
            ubyte* buf = cast(ubyte*)jack_midi_event_reserve(port_buf, evbuf.offset, ev.size);
            if (buf) {
                ev.buffer(buf);
            } else {
                break;
            }
        } else {
            break;
        }
    }

    if (evbuf.empty) {
        evbuf.rewind();
    }

    return 0;
}

int main(string[] args) {

    if (args.length == 1) {
        stderr.writeln("bad args");
        return 1;
    }
    
    string fname;
    bool dump = false;
    if (args[1] == "-d") {
        dump = true;
        fname = args[2];
    } else {
        fname = args[1];
    }

    auto mdata = MidiData.parse_midi_from_file(File(fname));
    if (dump) {
        mdata.dump();
        return 0;
    }
    evbuf = MidiEventBuffer.create(mdata, [1]);

    client = jack_client_open("test_midi", JackOptions.JackNullOption, null);

    if (client is null) {
        stderr.writeln("jack_client_open() failed");
        return 1;
    }

    evbuf.sample_rate = jack_get_sample_rate(client);

    jack_set_process_callback(client, &process, null);

    output_port = jack_port_register(client, "out", JACK_DEFAULT_MIDI_TYPE, JackPortFlags.JackPortIsOutput, 0);

    if (output_port is null) {
        stderr.writeln("no ports available");
        return 1;
    }

    if (jack_activate(client)) {
        stderr.writeln("cannot activate");
        return 1;
    }

    writeln("(press enter to stop)");
    readln();

    jack_client_close(client);

    return 0;
}
