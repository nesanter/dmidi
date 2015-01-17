import std.stdio;
import std.conv;

int main(string[] args) {
    MidiData data;

    if (args.length > 1) {
        data = MidiData.parse_midi_from_file(File(args[1]));
        data.dump();
    }
    return 0;
}

class MidiException : Exception {
    this(string msg) {
        super(msg);
    }
}

enum MidiChunkType {
    HEADER,
    TRACK,
    UNKNOWN
}

class MidiReadQueue {
    enum buffer_size = 1024;

    private File f;

    private ubyte[] buffer;
    private ulong index;
    private ulong length;

    private ulong accumulator;
    private ulong accumulator_base;

    this(File f) {
        buffer.length = buffer_size;
        this.f = f;
        advance();
    }

    void reset_amount_read() {
        accumulator_base = accumulator + index;
    }

    @property ulong amount_read() {
        return (accumulator + index) - accumulator_base;
    }

    @property bool empty() {
        return (length == 0);
    }

    private void advance() {
        if (!f.eof) {
            accumulator += length;

            ubyte[] slice = f.rawRead(buffer);
            length = slice.length;
            index = 0;

            if (length < 0) {
                throw new MidiException("Error reading file");
            }
        } else {
            length = 0;
        }
    }

    ubyte[] read_bytes(ulong n) {
        if (index + n < length) {
            ubyte[] tmp = buffer[index .. index + n];
            index += n;
            return tmp;
        } else {
            ubyte[] tmp = buffer[index .. length];
            n -= (length - index);
            advance();
            if (n <= length) {
                tmp = tmp ~ buffer[index .. index + n];
                index += n;
                return tmp;
            } else {
                throw new MidiException("Unexpected end of file");
            }
        }
    }

    T read_raw(T)() {
        ubyte[] bytes = read_bytes(T.sizeof);

        return *cast(T*)bytes.ptr;
    }

    T read(T)() {
        ubyte[] bytes = read_bytes(T.sizeof);
        ubyte[] reversed = bytes.reverse;

        return *cast(T*)(reversed.ptr);
    }

    MidiChunkType read_chunk_type() {
        ubyte[] type = read_bytes(4);

        if (type[0] == 'M' && type[1] == 'T') {
            if (type[2] == 'h' && type[3] == 'd') {
                return MidiChunkType.HEADER;
            } else if (type[2] == 'r' && type[3] == 'k') {
                return MidiChunkType.TRACK;
            }
        }

        return MidiChunkType.UNKNOWN;
    }

    uint read_variable() {
        ubyte[] bytes = read_bytes(1);
        while (bytes[$-1] & 128) {
            bytes ~= read_bytes(1);
        }

        uint x = 0;
        foreach_reverse (b; bytes) {
            x = (x << 7) | b;
        }

        return x;
    }

    void skip(ulong n) {
        while (n > 0) {
            if ((n + index) > length) {
                n = (n + index) - length;
                advance();
                if (length == 0)
                    throw new MidiException("unexpected end of file");
            } else {
                index = n;
                return;
            }
        }
    }
}

class MidiData {
    static MidiData parse_midi_from_file(File f) {
        auto queue = new MidiReadQueue(f);
        auto data = new MidiData(queue);
        return data;
    }

    MidiHeader header;
    MidiTrack[] tracks;

    this(MidiReadQueue queue) {
        while (!queue.empty) {
            MidiChunkType chunk_type = queue.read_chunk_type();
            uint length = queue.read!uint();

            final switch (chunk_type) {
                case MidiChunkType.HEADER:
                    if (header !is null) {
                        stderr.writeln("Warning: overwriting previous header");
                    }
                    header = new MidiHeader(queue, length);
                    break;
                case MidiChunkType.TRACK:
                    tracks ~= new MidiTrack(queue, length);
                    break;
                case MidiChunkType.UNKNOWN:
                    queue.skip(length);
                    break;
            }
        }
    }

    void dump() {
        writeln(header);
        foreach (track; tracks) {
            writeln(track);
            track.dump();
        }
    }
}

class MidiHeader {
    enum DivisionType {
        PER_QUARTER,
        PER_FRAME
    }
    ushort format;
    ushort tracks;
    DivisionType division_type;
    ushort ticks_per_quarter;
    ushort frames_per_second;
    ushort ticks_per_frame;

    this(MidiReadQueue queue, uint length) {
        format = queue.read!ushort();
        tracks = queue.read!ushort();
        ushort division = queue.read!ushort();
        if (division & 0x8000) {
            division_type = DivisionType.PER_FRAME;
            frames_per_second = (division & 0x7F00) >> 8;
            ticks_per_frame = (division & 0x00FF);
        } else {
            division_type = DivisionType.PER_QUARTER;
            ticks_per_quarter = division;
        }

        if (length - 6 > 0)
            queue.skip(length - 6);
    }

    override string toString() {
        if (division_type == DivisionType.PER_QUARTER) {
            return "Chunk:Header(format = " ~ to!string(format) ~ ", tracks = " ~
                to!string(tracks) ~ ", ticks_per_quarter = " ~
                to!string(ticks_per_quarter) ~ ")";
        } else {
            return "Chunk:Header(format = " ~ to!string(format) ~ ", tracks = " ~
                to!string(tracks) ~ ", frames_per_second = " ~
                to!string(frames_per_second) ~ ", ticks_per_frame = " ~
                to!string(ticks_per_frame) ~ ")";
        }
    }
}

class MidiTrack {
    MidiEvent[] events;

    this(MidiReadQueue queue, uint length) {
        queue.reset_amount_read();

        while (queue.amount_read < (length - 1)) {
            MidiEvent e = MidiEvent.parse(queue);
            events ~= e;
        }
    }

    void dump() {
        foreach (e; events) {
            writeln(e);
        }
    }

    override string toString() {
        return "Chunk:Track(n_events = " ~ to!string(events.length) ~ ")";
    }
}

abstract class MidiEvent {
    uint delta_time;

    //        enum MidiEvent function(MidiReadQueue,ubyte)[ubyte] event_ctors = [
    //            &Midi

    @property string name();

    static MidiEvent parse(MidiReadQueue queue) {
        uint t = queue.read_variable();
        ubyte type = queue.read!ubyte();

        if ((type & 0xF0) == 0xF0) {
            if ((type & 0x0F) == 0x0F) {
                return MidiMetaEvent.parse(queue, t);
            } else if ((type & 0x0F) == 0x00) {
                return MidiSysExEvent.parse(queue, type, t);
            } else {
                throw new MidiException("Unhandle event type");
            }
        } else {
            return MidiChannelEvent.parse(queue, type, t);
        }
    }
}

abstract class MidiChannelEvent : MidiEvent {

    ubyte channel;
    ubyte param1;
    ubyte param2;

    static MidiChannelEvent parse(MidiReadQueue queue, ubyte type, uint t) {
        ubyte p1 = queue.read!ubyte();
        ubyte p2 = queue.read!ubyte();

        switch (type & 0xF0) {
            case 0x80: return new MidiNoteOffEvent(type & 0xF, p1, p2, t);
            case 0x90: return new MidiNoteOnEvent(type & 0xF, p1, p2, t);
            case 0xA0: return new MidiNoteAftertouchEvent(type & 0xF, p1, p2, t);
            case 0xB0: return new MidiControllerEvent(type & 0xF, p1, p2, t);
            case 0xC0: return new MidiProgramChangeEvent(type & 0xF, p1, p2, t);
            case 0xD0: return new MidiChannelAftertouchEvent(type & 0xF, p1, p2, t);
            case 0xE0: return new MidiPitchBendEvent(type & 0xF, p1, p2, t);
            default: throw new MidiException("Unexpected channel event type ("~to!string(type & 0xF0)~")");
        }
    }

    this(ubyte channel, ubyte param1, ubyte param2, uint t) {
        this.channel = channel;
        this.param1 = param1;
        this.param2 = param2;
        this.delta_time = t;
    }

    override string toString() {
        return "Event:Channel:"~name~"<@"~to!string(delta_time)~">("~
            to!string(channel)~", "~to!string(param1)~", "~to!string(param2)~")";
    }
}

class MidiNoteOffEvent : MidiChannelEvent {
    override @property string name() { return "NoteOff"; }

    this(ubyte channel, ubyte param1, ubyte param2, uint t) {
        super(channel, param1, param2, t);
    }
}
class MidiNoteOnEvent : MidiChannelEvent {
    override @property string name() { return "NoteOn"; };

    this(ubyte channel, ubyte param1, ubyte param2, uint t) {
        super(channel, param1, param2, t);
    }
}
class MidiNoteAftertouchEvent : MidiChannelEvent {
    override @property string name() { return "NoteAftertouch"; }

    this(ubyte channel, ubyte param1, ubyte param2, uint t) {
        super(channel, param1, param2, t);
    }
}
class MidiControllerEvent : MidiChannelEvent {
    override @property string name() { return "Controller"; }

    this(ubyte channel, ubyte param1, ubyte param2, uint t) {
        super(channel, param1, param2, t);
    }
}
class MidiProgramChangeEvent : MidiChannelEvent {
    override @property string name() { return "ProgramChange"; }

    this(ubyte channel, ubyte param1, ubyte param2, uint t) {
        super(channel, param1, param2, t);
    }
}
class MidiChannelAftertouchEvent : MidiChannelEvent {
    override @property string name() { return "ChannelAftertouch"; }

    this(ubyte channel, ubyte param1, ubyte param2, uint t) {
        super(channel, param1, param2, t);
    }
}
class MidiPitchBendEvent : MidiChannelEvent {
    override @property string name() { return "PitchBend"; }

    this(ubyte channel, ubyte param1, ubyte param2, uint t) {
        super(channel, param1, param2, t);
    }
}

abstract class MidiMetaEvent : MidiEvent {

    static MidiMetaEvent parse(MidiReadQueue queue, uint t) {
        ubyte type = queue.read!ubyte();
        uint l = queue.read_variable();

        switch (type) {
            case 0x00: return new MidiSequenceNumberEvent(queue, l, t);
            case 0x01: return new MidiTextEvent(queue, l, t);
            case 0x02: return new MidiCopyrightNoticeEvent(queue, l, t);
            case 0x03: return new MidiSequenceNameEvent(queue, l, t);
            case 0x04: return new MidiInstrumentNameEvent(queue, l, t);
            case 0x05: return new MidiLyricsEvent(queue, l, t);
            case 0x06: return new MidiMarkerEvent(queue, l, t);
            case 0x07: return new MidiCuePointEvent(queue, l, t);
            case 0x20: return new MidiChannelPrefixEvent(queue, l, t);
            case 0x2F: return new MidiEndOfTrackEvent(queue, l, t);
            case 0x51: return new MidiSetTempoEvent(queue, l, t);
            case 0x54: return new MidiSMPTEOffsetEvent(queue, l, t);
            case 0x58: return new MidiTimeSignatureEvent(queue, l, t);
            case 0xFF: return new MidiKeySignatureEvent(queue, l, t);
            case 0x75: return new MidiSequencerSpecificEvent(queue, l, t);
            default: throw new MidiException("Unexpected meta event type");
        }
    }

    this(uint t) {
        delta_time = t;
    }
}

class MidiSequenceNumberEvent : MidiMetaEvent {
    ushort number;

    override @property string name() { return "SequenceNumber"; }

    this(MidiReadQueue queue, uint l, uint t) {
        this.number = queue.read_raw!ushort();
        super(t);
    }

    override string toString() {
        return "Event:Meta:"~name~"<@"~to!string(delta_time)~">("~to!string(number)~")";
    }
}

abstract class MidiMetaASCIIEvent : MidiMetaEvent {
    string text;

    this(MidiReadQueue queue, uint l, uint t) {
        ubyte[] raw = queue.read_bytes(l);
        this.text = std.conv.text(cast(char[])raw);
        super(t);
    }

    override string toString() {
        return "Event:Meta:"~name~"<@"~to!string(delta_time)~">("~text~")";
    }
}

class MidiTextEvent : MidiMetaASCIIEvent {

    override @property string name() { return "Text"; }

    this(MidiReadQueue queue, uint l, uint t) {
        super(queue, l, t);
    }
}

class MidiCopyrightNoticeEvent : MidiMetaASCIIEvent {

    override @property string name() { return "CopyrightNotice"; }

    this(MidiReadQueue queue, uint l, uint t) {
        super(queue, l, t);
    }
}

class MidiSequenceNameEvent : MidiMetaASCIIEvent {

    override @property string name() { return "SequenceName"; }

    this(MidiReadQueue queue, uint l, uint t) {
        super(queue, l, t);
    }
}

class MidiInstrumentNameEvent : MidiMetaASCIIEvent {

    override @property string name() { return "InstrumentName"; }

    this(MidiReadQueue queue, uint l, uint t) {
        super(queue, l, t);
    }
}

class MidiLyricsEvent : MidiMetaASCIIEvent {

    override @property string name() { return "Lyrics"; }

    this(MidiReadQueue queue, uint l, uint t) {
        super(queue, l, t);
    }
}

class MidiMarkerEvent : MidiMetaASCIIEvent {

    override @property string name() { return "Marker"; }

    this(MidiReadQueue queue, uint l, uint t) {
        super(queue, l, t);
    }
}

class MidiCuePointEvent : MidiMetaASCIIEvent {

    override @property string name() { return "CuePoint"; }

    this(MidiReadQueue queue, uint l, uint t) {
        super(queue, l, t);
    }
}

class MidiChannelPrefixEvent : MidiMetaEvent {

    override @property string name() { return "ChannelPrefix"; }

    ubyte channel;

    this(MidiReadQueue queue, uint l, uint t) {
        this.channel = queue.read!ubyte();
        super(t);
    }

    override string toString() {
        return "Event:Meta:"~name~"<@"~to!string(delta_time)~">("~to!string(channel)~")";
    }
}

class MidiEndOfTrackEvent : MidiMetaEvent {

    override @property string name() { return "EndOfTrack"; }

    this(MidiReadQueue queue, uint l, uint t) {
        super(t);
    }

    override string toString() {
        return "Event:Meta:"~name~"<@>"~to!string(delta_time)~">()";
    }

}

class MidiSetTempoEvent : MidiMetaEvent {

    override @property string name() { return "SetTempo"; }

    uint microseconds_per_quarter;

    this(MidiReadQueue queue, uint l, uint t) {
        ubyte[] raw = queue.read_bytes(3);
        ubyte[] rev = [0];

        foreach_reverse (b; raw) {
            rev ~= b;
        }

        microseconds_per_quarter = *cast(uint*)rev.ptr;

        super(t);
    }

    override string toString() {
        return "Event:Meta:"~name~"<@"~to!string(delta_time)~">("~to!string(microseconds_per_quarter)~")";
    }

}

class MidiSMPTEOffsetEvent : MidiMetaEvent {

    override @property string name() { return "SMPTEOffset"; }

    ubyte frame_rate,
          hours,
          minutes,
          seconds,
          frames,
          subframes;

    this(MidiReadQueue queue, uint l, uint t) {
        ubyte h = queue.read!ubyte();

        frame_rate = (h & 0xC0) >> 6;
        hours = (h & 0x20);

        this.minutes = queue.read!ubyte();
        this.seconds = queue.read!ubyte();
        this.frames = queue.read!ubyte();
        this.subframes = queue.read!ubyte();

        super(t);
    }

    override string toString() {
        return "Event:Meta:"~name~"<@"~to!string(delta_time)~">("~to!string(frame_rate)~", "~
            to!string(hours)~", "~to!string(minutes)~", "~
            to!string(seconds)~", "~to!string(frames)~", "~
            to!string(subframes)~")";
    }
}

class MidiTimeSignatureEvent : MidiMetaEvent {

    override @property string name() { return "TimeSignature"; }

    ubyte numerator,
          denominator,
          metronome,
          thirtyseconds;

    this(MidiReadQueue queue, uint l, uint t) {
        this.numerator = queue.read!ubyte();
        this.denominator = queue.read!ubyte();
        this.metronome = queue.read!ubyte();
        this.thirtyseconds = queue.read!ubyte();
        
        super(t);
    }

    override string toString() {
        return "Event:Meta:"~name~"<@"~to!string(delta_time)~">("~to!string(numerator)~"/"~
            to!string(denominator)~", "~to!string(metronome)~", "~
            to!string(thirtyseconds)~")";
    }
}

class MidiKeySignatureEvent : MidiMetaEvent {

    override @property string name() { return "KeySignature"; }

    ubyte key,
          scale;

    this(MidiReadQueue queue, uint l, uint t) {
        this.key = queue.read!ubyte();
        this.scale = queue.read!ubyte();
        
        super(t);
    }

    override string toString() {
        return "Event:Meta:"~name~"<@"~to!string(delta_time)~">("~to!string(key)~", "~to!string(scale)~")";
    }
}

class MidiSequencerSpecificEvent : MidiMetaEvent {

    override @property string name() { return "SequencerSpecific"; }

    ubyte[] data;

    this(MidiReadQueue queue, uint l, uint t) {
        this.data = queue.read_bytes(l);
        super(t);
    }

    override string toString() {
        return "Event:Meta:"~name~"<@"~to!string(delta_time)~">("~to!string(data)~")";
    }
}

abstract class MidiSysExEvent : MidiEvent {

    static MidiSysExEvent parse(MidiReadQueue queue, ubyte type, uint t) {
        uint length = queue.read_variable();

        return new MidiUnimplementedSysExEvent(type, t);
    }

    this(uint t) {
        delta_time = t;
    }
}

class MidiUnimplementedSysExEvent : MidiSysExEvent {

    override @property string name() { return "Unimplemented"; }

    ubyte type;

    this(ubyte type, uint t) {
        this.type = type;
        
        super(t);
    }

    override string toString() {
        return "Event:SysEx:"~name~"<@"~to!string(delta_time)~">("~to!string(type)~")";
    }
}
