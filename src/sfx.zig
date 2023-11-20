pub const ray = @import("raylib.zig");
const std = @import("std");
const builtin = @import("builtin");
const rnd = @import("random.zig");

var errsound = ray.Sound{};
var clacksound = ray.Sound{};
var clicksound = ray.Sound{};
var clearsound = ray.Sound{};
var levelupsound = ray.Sound{};
var wooshsound = ray.Sound{};
var winsound = ray.Sound{};
var songs = std.ArrayList(ray.Music).init(std.heap.page_allocator);
var songindex: usize = 0;

pub fn init() !void {
    // audio
    std.debug.print("init audio\n", .{});
    ray.InitAudioDevice();
    if (ray.IsAudioDeviceReady()) {
        errsound = ray.LoadSound("resources/sfx/deny.mp3");
        clacksound = ray.LoadSound("resources/sfx/clack.mp3");
        clicksound = ray.LoadSound("resources/sfx/click.mp3");
        clearsound = ray.LoadSound("resources/sfx/clear.mp3");
        levelupsound = ray.LoadSound("resources/sfx/level.mp3");
        wooshsound = ray.LoadSound("resources/sfx/woosh.mp3");
        winsound = ray.LoadSound("resources/sfx/win.mp3");
        try songs.append(ray.LoadMusicStream("resources/music/level0.mp3"));
        try songs.append(ray.LoadMusicStream("resources/music/level1.mp3"));
    }
}

pub fn deinit() void {
    std.debug.print("deinit audio\n", .{});
    ray.StopMusicStream(songs.items[songindex]);
    ray.UnloadSound(errsound);
    ray.UnloadSound(clacksound);
    ray.UnloadSound(clicksound);
    ray.UnloadSound(clearsound);
    ray.UnloadSound(levelupsound);
    ray.UnloadSound(wooshsound);
    ray.UnloadSound(winsound);
    for (songs.items) |song| {
        ray.UnloadMusicStream(song);
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

pub fn playmusic() void {
    ray.SetMusicVolume(songs.items[songindex], 0.05);
    ray.PlayMusicStream(songs.items[songindex]);
}

pub fn nextmusic() void {
    ray.StopMusicStream(songs.items[songindex]);
    songindex += 1;
    if (songindex >= songs.items.len) {
        songindex = 0;
    }
    ray.PlayMusicStream(songs.items[songindex]);
}

pub fn randommusic() void {
    ray.StopMusicStream(songs.items[songindex]);
    songindex = rnd.ng.intRangeAtMost(usize, 0, songs.items.len - 1);
    ray.PlayMusicStream(songs.items[songindex]);
}

pub fn updatemusic(mute: bool) void {
    if (mute) {
        ray.SetMusicVolume(songs.items[songindex], 0.00);
    } else {
        ray.SetMusicVolume(songs.items[songindex], 0.05);
    }
    ray.UpdateMusicStream(songs.items[songindex]);
}
