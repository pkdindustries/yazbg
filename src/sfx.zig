pub const ray = @import("raylib.zig");
const std = @import("std");
const builtin = @import("builtin");
const target = builtin.target;
const game = @import("game.zig");
const events = @import("events.zig");

const MAX_SOUNDS = 8;
const MAX_INSTANCES = 10;

const SoundType = enum {
    error_sound,
    clack,
    click,
    clear,
    level,
    woosh,
    win,
    gameover,
};

const SoundBank = struct {
    base: ray.Sound,
    instances: [MAX_INSTANCES]ray.Sound,
    current: usize = 0,
};

var sounds: [MAX_SOUNDS]SoundBank = undefined;
var soundvolume: f32 = 0.5;
var musicvolume: f32 = 0.15;

var music: [3][*:0]const u8 = .{
    "resources/music/level0.mp3",
    "resources/music/level1.mp3",
    "resources/music/newbit.mp3",
};
var songs: [3]ray.Music = undefined;
var songindex: usize = 0;

// -----------------------------------------------------------------------------
// Event handling
// -----------------------------------------------------------------------------

/// Consume all queued events and translate them into concrete audio calls.
pub fn process(queue: *events.EventQueue) void {
    for (queue.items()) |rec| {
        // debug: print event, source, and timestamp
        switch (rec.event) {
            .Error => playSound(.error_sound),
            .Clear => playSound(.clear),
            .Win => playSound(.win),
            .LevelUp => |_| {
                // level up jingle and switch to the next track
                playSound(.level);
                nextmusic();
            },
            .GameOver => playSound(.gameover),
            .Reset => resetmusic(),
            .MoveLeft => playSound(.click),
            .MoveRight => playSound(.click),
            .MoveDown => playSound(.click),
            .Rotate => playSound(.woosh),
            .HardDrop => playSound(.woosh),
            .SwapPiece => playSound(.click),
            .Pause => playSound(.click),
            .Kick => playSound(.clack),
            .Lock => playSound(.clack),
            else => {},
        }
    }
}

/// Reset music to first level
pub fn resetmusic() void {
    std.debug.print("resetting music\n", .{});
    ray.StopMusicStream(songs[songindex]);
    songindex = 0;
    playmusic();
}

pub fn init() !void {
    // audio
    std.debug.print("init audio\n", .{});
    ray.InitAudioDevice();
    if (ray.IsAudioDeviceReady() and target.os.tag != .linux) {
        // Load base sounds
        const sound_files = [_][*:0]const u8{
            "resources/sfx/deny.mp3",
            "resources/sfx/clack.mp3",
            "resources/sfx/click.mp3",
            "resources/sfx/clear.mp3",
            "resources/sfx/level.mp3",
            "resources/sfx/woosh.mp3",
            "resources/sfx/win.mp3",
            "resources/sfx/gameover.mp3",
        };

        // Initialize sound banks
        for (sound_files, 0..) |file, i| {
            sounds[i].base = ray.LoadSound(file);

            // Create aliases for concurrent playback
            for (0..MAX_INSTANCES) |j| {
                sounds[i].instances[j] = ray.LoadSoundAlias(sounds[i].base);
            }
            sounds[i].current = 0;
        }

        // load music into songs
        for (music, 0..) |m, i| {
            songs[i] = ray.LoadMusicStream(m);
        }
    }
    playmusic();
}

pub fn deinit() void {
    std.debug.print("deinit sfx\n", .{});

    // Unload all sound instances and their base sounds
    for (&sounds) |*bank| {
        // Unload aliases first
        for (bank.instances) |instance| {
            ray.UnloadSoundAlias(instance);
        }
        // Then unload base sound
        ray.UnloadSound(bank.base);
    }

    // Unload music
    for (songs) |s| {
        ray.UnloadMusicStream(s);
    }
    ray.CloseAudioDevice();
}

fn playSound(sound_type: SoundType) void {
    const index = @intFromEnum(sound_type);
    var bank = &sounds[index];

    // Play the current sound instance
    ray.PlaySound(bank.instances[bank.current]);

    // Move to the next instance for the next playback
    bank.current = (bank.current + 1) % MAX_INSTANCES;
}

pub fn playmusic() void {
    ray.SetMusicVolume(songs[songindex], musicvolume);
    ray.PlayMusicStream(songs[songindex]);
}

pub fn nextmusic() void {
    ray.StopMusicStream(songs[songindex]);
    songindex = songindex + 1;
    if (songindex >= music.len) {
        songindex = 0;
    }
    playmusic();
}

// toggle mute
pub fn mute() void {
    if (musicvolume > 0.0) {
        musicvolume = 0.0;
    } else {
        musicvolume = 0.15;
    }
    updatemusic();
}
pub fn randommusic() void {
    ray.StopMusicStream(songs[songindex]);
    songindex = game.state.rng.random().intRangeAtMost(usize, 0, music.len - 1);
    playmusic();
}

pub fn updatemusic() void {
    ray.SetMusicVolume(songs[songindex], musicvolume);
    ray.UpdateMusicStream(songs[songindex]);
}
