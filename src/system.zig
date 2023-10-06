const std = @import("std");
const ray = @import("raylib.zig");

var errs = ray.Sound{};
var clacks = ray.Sound{};
var clicks = ray.Sound{};
var clears = ray.Sound{};
var level = ray.Sound{};
var musics = ray.Music{};
var woosh = ray.Sound{};
var hit = ray.Sound{};
var win = ray.Sound{};

pub var rng = std.rand.DefaultPrng.init(0);

pub fn init() !void {
    // const dir = try std.fs.cwd().openIterableDir("sfx", .{});
    // var iterator = dir.iterate();
    // var allocator = std.heap.page_allocator;
    // var map = std.StringHashMap(ray.Sound).init(allocator);
    // _ = map;

    // while (try iterator.next()) |path| {
    //     std.debug.print("{s} ", .{path.name});
    //     //var sound = ray.LoadSound(path.name.ptr);
    //     // try map.put(path.name, sound);
    // }
    // std.debug.print("\n", .{});

    // audio
    std.debug.print("init audio\n", .{});
    ray.InitAudioDevice();
    if (ray.IsAudioDeviceReady()) {
        errs = ray.LoadSound("sfx/deny.mp3");
        clacks = ray.LoadSound("sfx/clack.mp3");
        clicks = ray.LoadSound("sfx/click.mp3");
        clears = ray.LoadSound("sfx/clear.mp3");
        level = ray.LoadSound("sfx/level.mp3");
        woosh = ray.LoadSound("sfx/woosh.mp3");
        hit = ray.LoadSound("sfx/hit.mp3");
        win = ray.LoadSound("sfx/win.mp3");
        musics = ray.LoadMusicStream("sfx/music2.mp3");
        playmusic();
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
    ray.StopMusicStream(musics);
    ray.UnloadSound(errs);
    ray.UnloadSound(clacks);
    ray.UnloadSound(clicks);
    ray.UnloadSound(clears);
    ray.UnloadSound(level);
    ray.UnloadSound(woosh);
    ray.UnloadSound(hit);
    ray.UnloadSound(win);
    ray.UnloadMusicStream(musics);
    ray.CloseAudioDevice();
}

pub fn playSoundByName(name: []const u8) void {
    _ = name;
}

pub fn playwin() void {
    ray.PlaySound(win);
}

pub fn playhit() void {
    ray.PlaySound(hit);
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
    ray.SetMusicVolume(musics, 0.05);
    ray.PlayMusicStream(musics);
}

pub fn update() void {
    ray.UpdateMusicStream(musics);
}
