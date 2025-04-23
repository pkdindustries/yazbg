pub const ray = @import("raylib.zig");
const std = @import("std");
const builtin = @import("builtin");
const target = builtin.target;
const game = @import("game.zig");
const events = @import("events.zig");

var errsound = ray.Sound{};
var clacksound = ray.Sound{};
var clicksound = ray.Sound{};
var clearsound = ray.Sound{};
var levelupsound = ray.Sound{};
var wooshsound = ray.Sound{};
var winsound = ray.Sound{};
var gameover = ray.Sound{};
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
            .Error => playerror(),
            .Clear => playclear(),
            .Win => playwin(),
            .LevelUp => |_| {
                // level up jingle and switch to the next track
                playlevel();
                nextmusic();
            },
            .GameOver => playgameover(),
            .Reset => reset(),
            .MoveLeft => playclick(),
            .MoveRight => playclick(),
            .MoveDown => playclick(),
            .Rotate => playclick(),
            .HardDrop => {
                playclack();
                playwoosh();
            },
            .SwapPiece => playclick(),
            .Pause => playclick(),
            .Kick => playclack(),
            else => {},
        }
    }
}

/// Reset music to first level
pub fn reset() void {
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
        errsound = ray.LoadSound("resources/sfx/deny.mp3");
        clacksound = ray.LoadSound("resources/sfx/clack.mp3");
        clicksound = ray.LoadSound("resources/sfx/click.mp3");
        clearsound = ray.LoadSound("resources/sfx/clear.mp3");
        levelupsound = ray.LoadSound("resources/sfx/level.mp3");
        wooshsound = ray.LoadSound("resources/sfx/woosh.mp3");
        winsound = ray.LoadSound("resources/sfx/win.mp3");
        gameover = ray.LoadSound("resources/sfx/gameover.mp3");

        // load musc into songs
        for (music, 0..) |m, i| {
            songs[i] = ray.LoadMusicStream(m);
        }
    }
    playmusic();
}

pub fn deinit() void {
    std.debug.print("deinit sfx\n", .{});
    ray.UnloadSound(errsound);
    ray.UnloadSound(clacksound);
    ray.UnloadSound(clicksound);
    ray.UnloadSound(clearsound);
    ray.UnloadSound(levelupsound);
    ray.UnloadSound(wooshsound);
    ray.UnloadSound(winsound);
    for (songs) |s| {
        ray.UnloadMusicStream(s);
    }
    ray.CloseAudioDevice();
}

pub fn playwin() void {
    ray.PlaySound(winsound);
}

pub fn playwoosh() void {
    ray.PlaySound(wooshsound);
}

pub fn playlevel() void {
    ray.PlaySound(levelupsound);
}
pub fn playerror() void {
    ray.PlaySound(errsound);
}

pub fn playclack() void {
    ray.PlaySound(clacksound);
}

pub fn playclick() void {
    ray.PlaySound(clicksound);
}

pub fn playclear() void {
    ray.PlaySound(clearsound);
}

pub fn playgameover() void {
    ray.PlaySound(gameover);
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
