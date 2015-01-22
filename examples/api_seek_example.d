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

    if (args.length > 2) {
        ulong n;
        try {
            n = to!ulong(args[2]);
        } catch (ConvException e) {
            stderr.writeln("Unexpected value ", args[2], " for starting note");
            return 1;
        }

        try {
            writeln("Seeking to note ", n);
            Sequencer.seek(n);
        } catch (MidiException e) {
            stderr.writeln("Starting note does not exist in file");
            return 1;
        }
    }

    writeln("Press enter when ready");
    readln();

    Sequencer.play();

    Sequencer.wait();

    Sequencer.deactivate();

    return 0;
}
