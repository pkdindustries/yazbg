const std = @import("std");
const ray = @import("raylib.zig");
const game = @import("game.zig");
const sfx = @import("sfx.zig");
const gfx = @import("gfx.zig");
const events = @import("events.zig");
const level = @import("level.zig");

const MS = 1_000_000;
pub fn main() !void {
    var timer = try std.time.Timer.start();

    try game.init();
    defer game.deinit();

    try sfx.init();
    defer sfx.deinit();

    try gfx.init();
    defer gfx.deinit();

    std.debug.print("system init {}ms\n", .{timer.lap() / MS});

    printkeys();

    while (!ray.WindowShouldClose()) {
        // Update game clock for this frame
        const now_ms: i64 = @as(i64, @intCast(std.time.milliTimestamp()));
        game.tick(now_ms);
        sfx.updatemusic();
        if (game.dropready()) {
            if (!game.down()) {
                game.harddrop();
            }
        }

        // handle input
        switch (ray.GetKeyPressed()) {
            ray.KEY_P => game.pause(),
            ray.KEY_R => game.reset(),
            ray.KEY_SPACE => game.harddrop(),
            ray.KEY_LEFT => game.left(),
            ray.KEY_RIGHT => game.right(),
            ray.KEY_DOWN => if (!game.down()) game.harddrop(),
            ray.KEY_UP => game.rotate(),
            ray.KEY_C => game.swappiece(),
            ray.KEY_B => gfx.nextbackground(),
            ray.KEY_M => sfx.mute(),
            ray.KEY_N => sfx.nextmusic(),
            ray.KEY_L => checkleak(),
            else => {},
        }

        const gamelogic_elapsed = timer.lap();

        // queued events after all gameplay code
        level.process(&events.queue);
        sfx.process(&events.queue);
        gfx.process(&events.queue);
        events.queue.clear();

        // draw the frame
        gfx.frame();

        // performance stats
        const frametime_elapsed = timer.lap();
        const total_elapsed = gamelogic_elapsed + frametime_elapsed;
        if (gamelogic_elapsed > 1 * MS or frametime_elapsed > 10 * MS) {
            std.debug.print("frame {}ms, game {}ms, total {}ms, raytime {d:.2}\n", .{ frametime_elapsed / MS, gamelogic_elapsed / MS, total_elapsed / MS, ray.GetFrameTime() * MS / 1000 });
        }
    }
}

fn checkleak() void {
    const leaks = game.state.alloc.detectLeaks();
    if (!leaks) {
        std.debug.print("no leaks\n", .{});
    }
}
fn printkeys() void {
    std.debug.print("keys:\n", .{});
    std.debug.print("  left/right: move\n", .{});
    std.debug.print("  up: rotate\n", .{});
    std.debug.print("  down: drop\n", .{});
    std.debug.print("  space: hard drop\n", .{});
    std.debug.print("  c: swap piece\n", .{});
    std.debug.print("  b: next background\n", .{});
    std.debug.print("  m: mute\n", .{});
    std.debug.print("  n: next music\n", .{});
    std.debug.print("  p: pause\n", .{});
    std.debug.print("  r: reset\n", .{});
}
