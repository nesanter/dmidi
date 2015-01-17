import std.stdio;
import std.string;
import std.math;

import midi;

extern (C) {
    struct fluid_settings_t;
    struct fluid_synth_t;
    struct fluid_player_t;
    struct fluid_audio_driver_t;
    struct fluid_sequencer_t;
    struct fluid_event_t;
    struct fluid_midi_router_t;
    struct fluid_midi_event_t;
    struct fluid_midi_router_rule_t;
    
    alias void function(uint, fluid_event_t *, fluid_sequencer_t *, void *) fluid_event_callback_t;
    alias int function(void *data, fluid_midi_event_t *event) handle_midi_event_func_t;

    fluid_settings_t *new_fluid_settings();
    fluid_synth_t *new_fluid_synth(fluid_settings_t *settings);
    fluid_player_t *new_fluid_player(fluid_synth_t *synth);
    fluid_audio_driver_t *new_fluid_audio_driver(fluid_settings_t *settings, fluid_synth_t *synth);
    fluid_sequencer_t *new_fluid_sequencer2(int use_system_timer);
    fluid_event_t *new_fluid_event();
    fluid_midi_router_t *new_fluid_midi_router(fluid_settings_t *settings, handle_midi_event_func_t handler, void *event_handler_data);

    short fluid_sequencer_register_fluidsynth(fluid_sequencer_t *seq, fluid_synth_t *synth);
    short fluid_sequencer_register_client(fluid_sequencer_t *seq, const char *name, fluid_event_callback_t callback, void *data);
    uint fluid_sequencer_get_tick(fluid_sequencer_t *seq);

    int fluid_synth_sfload(fluid_synth_t *synth, const char *filename, int reset_presets);
    void fluid_synth_set_midi_router(fluid_synth_t *synth, fluid_midi_router_t *router);

    int fluid_player_add(fluid_player_t *player, const char *filename);
    int fluid_player_play(fluid_player_t *player);
    int fluid_player_join(fluid_player_t *player);

    int fluid_settings_setstr(fluid_settings_t *settings, const char *name, const char *str);

    void fluid_event_set_source(fluid_event_t *evt, short src);
    void fluid_event_set_dest(fluid_event_t *evt, short dest);
    void fluid_event_note(fluid_event_t *evt, int channel, short key, short vel, uint duration);
    void fluid_event_noteon(fluid_event_t *evt, int channel, short key, short vel);
    void fluid_event_noteoff(fluid_event_t *evt, int channel, short key);
    void fluid_event_timer(fluid_event_t *evt, void *data);

    int fluid_sequencer_send_at(fluid_sequencer_t *seq, fluid_event_t *evt, uint time, int absolute);

    int fluid_midi_router_handle_midi_event(void *data, fluid_midi_event_t *event);

    fluid_midi_router_rule_t *new_fluid_midi_router_rule();
    int fluid_midi_router_add_rule(fluid_midi_router_t *router, fluid_midi_router_rule_t *rule, int type);
    int fluid_midi_router_clear_rules(fluid_midi_router_t *router);

    void delete_fluid_settings(fluid_settings_t *settings);
    void delete_fluid_synth(fluid_synth_t *synth);
    void delete_fluid_player(fluid_player_t *player);
    void delete_fluid_audio_driver(fluid_audio_driver_t *driver);
    void delete_fluid_sequencer(fluid_sequencer_t *seq);
    void delete_fluid_event(fluid_event_t *evt);
    void delete_fluid_midi_router(fluid_midi_router_t *handler);
}

interface FluidSequenceable {
    void sequence(Fluid fl);
}

class Fluid {
    fluid_settings_t* settings;
    fluid_synth_t* synth;
    fluid_audio_driver_t* adriver;
    fluid_sequencer_t* sequencer;
    fluid_midi_router_t *router;

    short synth_seq_id, cb_seq_id;

    uint acc_scaled_delta_time;
    real acc_real_time;
    uint base_tick;

    enum ticks_per_second = 1000;
    uint tempo = 500000; //microseconds per quarter note

    real scale; //fluid ticks per delta time
                //scale * delta_time = delta_ticks

    this(string soundfont) {
        settings = new_fluid_settings();
        fluid_settings_setstr(settings, "audio.driver", "alsa");

        synth = new_fluid_synth(settings);

        adriver = new_fluid_audio_driver(settings, synth);

        sequencer = new_fluid_sequencer2(0);

//        router = new_fluid_midi_router(settings, &router_handler, null);

//        fluid_synth_set_midi_router(synth, router);

//        fluid_midi_router_clear_rules(router);

//        fluid_midi_router_rule_t *rule = new_fluid_midi_router_rule();
//        fluid_midi_router_add_rule(router, rule, 1);

        synth_seq_id = fluid_sequencer_register_fluidsynth(sequencer, synth);
        cb_seq_id = fluid_sequencer_register_client(sequencer, "me", &sequencer_callback, null);
        
        base_tick = fluid_sequencer_get_tick(sequencer);

        int res = fluid_synth_sfload(synth, toStringz(soundfont), 1);

        if (res) {
            stderr.writeln("error loading soundfont");
        }
    }

    bool init_timing(MidiHeader h) {
        if (h.division_type == MidiHeader.DivisionType.PER_FRAME) {
            stderr.writeln("Header time division of type PER_FRAME is unsupported.");
            return false;
        }

        scale = (cast(real)h.ticks_per_quarter / (cast(real)tempo / 1000)) / (cast(real)ticks_per_second / 1000);

        return true;
    }

    void change_tempo(uint new_tempo) {
        scale = scale * (tempo / new_tempo);
    }

    void reset() {
        acc_scaled_delta_time = 0;
        acc_real_time = 0;
    }

    extern (C) static void sequencer_callback(uint time, fluid_event_t* event, fluid_sequencer_t* sequencer, void* data) {
        writeln("callback!");
    }

    /*
    extern (C) static int router_handler(void *data, fluid_midi_event_t *event) {
        writeln("handler");
//        return fluid_midi_router_handle_midi_event(data, event);
        return 0;
    }
    */

    int calc_time(uint delta_time) {
        real t = cast(real)delta_time * scale;
        acc_real_time += t;
        acc_scaled_delta_time += delta_time * tempo;

        return cast(int)lrint(acc_real_time);
    }

    fluid_event_t* create_event(bool callback) {
        fluid_event_t* evt = new_fluid_event();
        fluid_event_set_source(evt, -1);
        fluid_event_set_dest(evt, callback ? cb_seq_id : synth_seq_id);

        return evt;
    }

    void send(fluid_event_t* evt, uint delta_time) {
        fluid_sequencer_send_at(sequencer, evt, calc_time(delta_time) + base_tick, 1);
    }

    /*
    void noteon(int channel, short key, uint date) {
        fluid_event_t* evt = new_fluid_event();
        fluid_event_set_source(evt, -1);
        fluid_event_set_dest(evt, synth_seq_id);
        fluid_event_noteon(evt, channel, key, 127);

        fluid_event_t* evt2 = new_fluid_event();
        fluid_event_set_source(evt2, -1);
        fluid_event_set_dest(evt2, cb_seq_id);

        fluid_event_timer(evt2, null);

        int res = fluid_sequencer_send_at(sequencer, evt, date, 1);
        int res2 = fluid_sequencer_send_at(sequencer, evt2, date, 1);

        delete_fluid_event(evt);
        delete_fluid_event(evt2);
    }
    */
}
