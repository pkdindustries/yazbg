const std = @import("std");
const ray = @import("raylib.zig");
const game = @import("game.zig");
const sfx = @import("sfx.zig");
const gfx = @import("gfx.zig");
const events = @import("events.zig");

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

        // fill music buffer & process audio events
        sfx.updatemusic();
        sfx.process(&events.queue);
        // tick
        if (game.dropready()) {
            if (!game.down()) {
                harddrop();
            } else {
                events.push(.Click);
            }
        }

        // handle input
        switch (ray.GetKeyPressed()) {
            ray.KEY_P => game.pause(),
            ray.KEY_R => game.reset(),
            ray.KEY_SPACE => harddrop(),
            ray.KEY_LEFT => if (game.left()) events.push(.Click) else events.push(.Error),
            ray.KEY_RIGHT => if (game.right()) events.push(.Click) else events.push(.Error),
            ray.KEY_DOWN => if (game.down()) events.push(.Click) else harddrop(),
            ray.KEY_UP => if (game.rotate()) events.push(.Click) else events.push(.Error),
            ray.KEY_C => if (game.swappiece()) events.push(.Woosh) else events.push(.Error),
            ray.KEY_B => gfx.nextbackground(),
            ray.KEY_M => sfx.mute(),
            ray.KEY_N => sfx.nextmusic(),
            ray.KEY_L => checkleak(),
            else => {},
        }

        const gamelogic_elapsed = timer.lap();

        // draw the frame
        gfx.frame();

        // performance stats
        const frametime_elapsed = timer.lap();
        const total_elapsed = gamelogic_elapsed + frametime_elapsed;
        if (gamelogic_elapsed > 5 * MS or frametime_elapsed > 10 * MS) {
            std.debug.print("frame {}ms, game {}ms, total {}ms, raytime {d:.2}\n", .{ frametime_elapsed / MS, gamelogic_elapsed / MS, total_elapsed / MS, ray.GetFrameTime() * MS / 1000 });
        }
    }
}

fn harddrop() void {
    if (game.frozen()) return;

    // Sound effects
    events.push(.Woosh);
    events.push(.Clack);

    const lines: i32 = game.harddrop();
    progression(lines);
    game.nextpiece();
}

fn progression(lines: i32) void {
    if (lines < 1) return;
    game.state.progression.score += 1000 * lines * lines;
    game.state.progression.cleared += lines;
    events.push(.{ .Clear = @as(u8, @intCast(lines)) });
    if (lines > 3) events.push(.Win);
    if (game.state.progression.clearedthislevel > 6) {
        std.debug.print("level up\n", .{});
        gfx.nextbackground();
        sfx.nextmusic();
        events.push(.LevelUp);
        game.state.progression.level += 1;
        game.state.progression.score += 1000 * game.state.progression.level;
        game.state.progression.dropinterval_ms -= 150;
        game.state.progression.clearedthislevel = 0;
        if (game.state.progression.dropinterval_ms <= 100) {
            game.state.progression.dropinterval_ms = 100;
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
