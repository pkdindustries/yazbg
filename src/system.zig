pub const ray = @import("raylib.zig");
const std = @import("std");

var errs = ray.Sound{};
var clacks = ray.Sound{};
var clicks = ray.Sound{};
var clears = ray.Sound{};
var level = ray.Sound{};
var songs = std.ArrayList(ray.Music).init(std.heap.page_allocator);
var woosh = ray.Sound{};
var win = ray.Sound{};

pub var rng = std.rand.DefaultPrng.init(0);
pub var songindex: usize = 0;

pub fn init() !void {
    // audio
    std.debug.print("init audio\n", .{});
    ray.InitAudioDevice();
    if (ray.IsAudioDeviceReady()) {
        errs = ray.LoadSound("resources/sfx/deny.mp3");
        clacks = ray.LoadSound("resources/sfx/clack.mp3");
        clicks = ray.LoadSound("resources/sfx/click.mp3");
        clears = ray.LoadSound("resources/sfx/clear.mp3");
        level = ray.LoadSound("resources/sfx/level.mp3");
        woosh = ray.LoadSound("resources/sfx/woosh.mp3");
        win = ray.LoadSound("resources/sfx/win.mp3");
        try songs.append(ray.LoadMusicStream("resources/music/level0.mp3"));
        try songs.append(ray.LoadMusicStream("resrouces/music/level1.mp3"));
    }

    // rng
    std.debug.print("init rng\n", .{});
    rng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.os.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
}

pub fn deinit() void {
    std.debug.print("deinit audio\n", .{});
    ray.StopMusicStream(songs.items[songindex]);
    ray.UnloadSound(errs);
    ray.UnloadSound(clacks);
    ray.UnloadSound(clicks);
    ray.UnloadSound(clears);
    ray.UnloadSound(level);
    ray.UnloadSound(woosh);
    ray.UnloadSound(win);
    ray.UnloadMusicStream(songs.items[songindex]);
    ray.CloseAudioDevice();
}

pub fn playwin() void {
    ray.PlaySound(win);
}

pub fn playwoosh() void {
    ray.PlaySound(woosh);
}

pub fn playlevel() void {
    ray.PlaySound(level);
}
pub fn playerror() void {
    ray.PlaySound(errs);
}

pub fn playclack() void {
    ray.PlaySound(clacks);
}

pub fn playclick() void {
    ray.PlaySound(clicks);
}

pub fn playclear() void {
    ray.PlaySound(clears);
}

pub fn playmusic() void {
    ray.SetMusicVolume(songs.items[songindex], 0.05);
    ray.PlayMusicStream(songs.items[songindex]);
}

pub fn updatemusic() void {
    ray.UpdateMusicStream(songs.items[songindex]);
}
