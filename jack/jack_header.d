/**
 * JACK Bindings
 *
 * Authors: Noah Santer, nesanter@knox.edu
 */

module jack.header;

import std.stdio;

alias uint jack_nframes_t;
alias float jack_default_audio_sample_t;
alias ubyte jack_midi_data_t;

alias extern (C) int function(jack_nframes_t, void* arg) JackProcessCallback;
alias extern (C) void function(void* arg) JackShutdownCallback;

struct jack_client_t;
struct jack_port_t;
struct jack_midi_event_t;

enum JackOptions {
    JackNullOption = 0x0,
    JackNoStartServer = 0x1,
    JackUseExactName = 0x2,
    JackServerName = 0x4,
    JackLoadName = 0x8,
    JackLoadInit = 0x10,
    JackSessionID = 0x20
}

enum JackStatus {
    JackFailure = 0x1,
    JackInvalidOption = 0x2,
    JackNameNotUnique = 0x4,
    JackServerStarted = 0x8,
    JackServerFailed = 0x10,
    JackServerError = 0x20,
    JackNoSuchClient = 0x40,
    JackLoadFailure = 0x80,
    JackInitFailure = 0x100,
    JackShmFailure = 0x200,
    JackVersionError = 0x400,
    JackBackendError = 0x800,
    JackClientZombie = 0x1000
}

enum JackPortFlags {
    JackPortIsInput = 0x1,
    JackPortIsOutput = 0x2,
    JackPortIsPhysical = 0x4,
    JackPortCanMonitor = 0x8,
    JackPortIsTerminal = 0x10
}

enum JACK_DEFAULT_AUDIO_TYPE = "32 bit float mono audio";
enum JACK_DEFAULT_MIDI_TYPE = "8 bit raw midi";

alias JackStatus jack_status_t;
alias JackOptions jack_options_t;

extern (C) {
    void* jack_port_get_buffer(jack_port_t*, jack_nframes_t);
    jack_client_t* jack_client_open(const char* client_name, jack_options_t options, jack_status_t* status, ...);
    int jack_set_process_callback(jack_client_t* client, JackProcessCallback process_callback, void* arg);
    void jack_on_shutdown(jack_client_t* client, JackShutdownCallback f, void* arg);
    jack_port_t* jack_port_register(jack_client_t* client, const char* port_name, const char* port_type, ulong flags, ulong buffer_size);
    int jack_activate(jack_client_t* client);
    const(char)** jack_get_ports(jack_client_t*, const char* port_name_pattern, const char* type_name_parttern, ulong flags);
    int jack_connect(jack_client_t*, const char* source_port, const char* destination_port);
    int jack_client_close(jack_client_t* client);
    jack_nframes_t jack_get_sample_rate(jack_client_t*);
    const(char)* jack_port_name(const jack_port_t* port);

    void jack_midi_clear_buffer(void* port_buffer);
    int jack_midi_event_get(jack_midi_event_t* event, void* port_buffer, uint event_index);
    jack_midi_data_t* jack_midi_event_reserve(void* port_buffer, jack_nframes_t time, size_t data_size);

    jack_nframes_t jack_get_buffer_size(jack_client_t*);
}

