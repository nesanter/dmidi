import std.stdio;
import std.exception;
import std.conv;

import midi.parser;
import midi.api;


int main(string[] args) {
    if (args.length == 1) {
        stderr.writeln("Syntax: ",args[0]," midi_file [start_note]");
        return 1;
    }

    File f;
    try {
        f = File(args[1]);
    } catch (ErrnoException e) {
        stderr.writeln("Unable to open file ",args[1]);
        return 1;
    }

    MidiData data;

    try {
        data = MidiData.parse_midi_from_file(f);
    } catch (MidiException e) {
        stderr.writeln("Unable to parse MIDI data");
        return 1;
    }

    try {
        Sequencer.activate();
    } catch (JackException e) {
        stderr.writeln("Unable to activate Jack");
        return 1;
    }

    Sequencer.load(data);

    writeln("Press enter when ready");
    readln();

    Sequencer.play();

    auto cb = (ulong note) {
        writeln("note #",note);
    };

    Sequencer.wait(cb);

    Sequencer.deactivate();

    return 0;
}
