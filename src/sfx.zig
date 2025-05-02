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

const MUSIC_PATHS = [_][*:0]const u8{
    "resources/music/fast.mp3",
    "resources/music/grievous.mp3",
    "resources/music/level0.mp3",
    "resources/music/lieu.mp3",
    "resources/music/newbit.mp3",
    "resources/music/wonder.mp3",
};

const SOUND_PATHS = [_][*:0]const u8{
    "resources/sfx/deny.mp3",
    "resources/sfx/clack.mp3",
    "resources/sfx/click.mp3",
    "resources/sfx/clear.mp3",
    "resources/sfx/level.mp3",
    "resources/sfx/woosh.mp3",
    "resources/sfx/win.mp3",
    "resources/sfx/gameover.mp3",
};

var songs: [MUSIC_PATHS.len]ray.Music = undefined;
var songindex: usize = 0;

pub fn process(queue: *events.EventQueue) void {
    for (queue.items()) |rec| {
        switch (rec.event) {
            .Error => playSound(.error_sound),
            .Clear => playSound(.clear),
            .Win => playSound(.win),
            .LevelUp => |_| {
                playSound(.level);
                nextMusic();
            },
            .GameOver => playSound(.gameover),
            .Reset => resetMusic(),
            .MoveLeft => playSound(.click),
            .MoveRight => playSound(.click),
            .MoveDown => playSound(.click),
            .Rotate, .RotateCCW => playSound(.woosh),
            .HardDropEffect => |_| playSound(.woosh),
            .SwapPiece => playSound(.click),
            .Pause => playSound(.click),
            .Kick => playSound(.clack),
            .PieceLocked => |_| playSound(.clack),
            .MuteAudio => mute(),
            .NextMusic => nextMusic(),
            else => {},
        }
    }
}

/// Reset music to first level
pub fn resetMusic() void {
    ray.StopMusicStream(songs[songindex]);
    songindex = 0;
    playMusic();
}

pub fn init() !void {
    std.debug.print("init audio\n", .{});
    ray.InitAudioDevice();

    if (ray.IsAudioDeviceReady() and target.os.tag != .linux) {
        // Initialize sound banks
        for (SOUND_PATHS, 0..) |file, i| {
            sounds[i].base = ray.LoadSound(file);

            // Create aliases for concurrent playback
            for (0..MAX_INSTANCES) |j| {
                sounds[i].instances[j] = ray.LoadSoundAlias(sounds[i].base);
            }
            sounds[i].current = 0;
        }

        // Load music
        for (MUSIC_PATHS, 0..) |path, i| {
            songs[i] = ray.LoadMusicStream(path);
        }
    }
    playMusic();
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

pub fn playMusic() void {
    ray.SetMusicVolume(songs[songindex], musicvolume);
    ray.PlayMusicStream(songs[songindex]);
}

pub fn nextMusic() void {
    ray.StopMusicStream(songs[songindex]);
    songindex = (songindex + 1) % MUSIC_PATHS.len;
    playMusic();
}

pub fn mute() void {
    musicvolume = if (musicvolume > 0.0) 0.0 else 0.15;
    updateMusic();
}

pub fn randomMusic() void {
    ray.StopMusicStream(songs[songindex]);
    songindex = game.state.rng.random().intRangeAtMost(usize, 0, MUSIC_PATHS.len - 1);
    playMusic();
}

pub fn updateMusic() void {
    ray.SetMusicVolume(songs[songindex], musicvolume);
    ray.UpdateMusicStream(songs[songindex]);
}
