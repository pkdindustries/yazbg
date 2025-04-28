const std = @import("std");
const ray = @import("raylib.zig");
const game = @import("game.zig");
const sfx = @import("sfx.zig");
const gfx = @import("gfx.zig");
const hud = @import("hud.zig");
const events = @import("events.zig");
const level = @import("level.zig");

const MS = 1_000_000;
pub fn main() !void {
    var timer = try std.time.Timer.start();
    ray.SetTraceLogLevel(ray.LOG_WARNING);

    try game.init(std.heap.c_allocator);
    defer game.deinit();

    try sfx.init();
    defer sfx.deinit();

    try gfx.init();
    defer gfx.deinit();

    std.debug.print("system init {}ms\n", .{timer.lap() / MS});

    printkeys();

    while (!ray.WindowShouldClose()) {
        // start‑of‑frame housekeeping
        // anything that was defered
        events.flushDeferred();
        // update clock
        game.tick(std.time.milliTimestamp());
        // keep music fed
        sfx.updateMusic();

        switch (ray.GetKeyPressed()) {
            ray.KEY_P => events.push(.Pause, events.Source.Input),
            ray.KEY_R => events.push(.Reset, events.Source.Input),
            ray.KEY_SPACE => events.push(.HardDrop, events.Source.Input),
            ray.KEY_LEFT => events.push(.MoveLeft, events.Source.Input),
            ray.KEY_RIGHT => events.push(.MoveRight, events.Source.Input),
            ray.KEY_DOWN => events.push(.MoveDown, events.Source.Input),
            ray.KEY_UP => events.push(.Rotate, events.Source.Input),
            ray.KEY_Z => events.push(.RotateCCW, events.Source.Input),
            ray.KEY_C => events.push(.SwapPiece, events.Source.Input),
            ray.KEY_B => events.push(.NextBackground, events.Source.Input),
            ray.KEY_M => events.push(.MuteAudio, events.Source.Input),
            ray.KEY_N => events.push(.NextMusic, events.Source.Input),
            ray.KEY_L => events.push(.Debug, events.Source.Input),
            else => {},
        }

        // Check if it's time for automatic piece drop
        if (game.dropready()) {
            events.push(.AutoDrop, events.Source.Game);
        }

        // queued events
        game.process(&events.queue);
        level.process(&events.queue);
        sfx.process(&events.queue);
        hud.process(&events.queue);
        gfx.process(&events.queue);
        events.queue.clear();
        const gamelogic_elapsed = timer.lap();

        // draw the frame
        gfx.frame();

        // performance stats
        const frametime_elapsed = timer.lap();
        const total_elapsed = gamelogic_elapsed + frametime_elapsed;
        if (gamelogic_elapsed > 2 * MS or frametime_elapsed > 20 * MS) {
            std.debug.print("frame {}ms, game {}ms, total {}ms\n", .{ frametime_elapsed / MS, gamelogic_elapsed / MS, total_elapsed / MS });
        }
    }
}

fn printkeys() void {
    std.debug.print("keys:\n", .{});
    std.debug.print("  left/right: move\n", .{});
    std.debug.print("  up: rotate counter-clockwise\n", .{});
    std.debug.print("  z: rotate clockwise\n", .{});
    std.debug.print("  down: drop\n", .{});
    std.debug.print("  space: hard drop\n", .{});
    std.debug.print("  c: swap piece\n", .{});
    std.debug.print("  b: next background\n", .{});
    std.debug.print("  m: mute\n", .{});
    std.debug.print("  n: next music\n", .{});
    std.debug.print("  p: pause\n", .{});
    std.debug.print("  r: reset\n", .{});
}
