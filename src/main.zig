const std = @import("std");
const ray = @import("raylib.zig");
const game = @import("game.zig");
const sfx = @import("sfx.zig");
const gfx = @import("gfx.zig");
const rnd = @import("random.zig");

const MS = 1_000_000;
pub fn main() !void {
    var timer = try std.time.Timer.start();

    try rnd.init();
    defer rnd.deinit();

    try sfx.init();
    defer sfx.deinit();

    try gfx.init();
    defer gfx.deinit();

    try game.init();
    defer game.deinit();

    std.debug.print("system init {}ms\n", .{timer.lap() / MS});

    printkeys();

    while (!ray.WindowShouldClose()) {
        // fill music buffer
        sfx.updatemusic();
        // tick
        if (game.dropready()) {
            move(game.down, sfx.playclick, harddrop);
        }
        // handle input
        switch (ray.GetKeyPressed()) {
            ray.KEY_P => game.pause(),
            ray.KEY_R => game.reset(),
            ray.KEY_SPACE => harddrop(),
            ray.KEY_LEFT => move(game.left, sfx.playclick, sfx.playerror),
            ray.KEY_RIGHT => move(game.right, sfx.playclick, sfx.playerror),
            ray.KEY_DOWN => move(game.down, sfx.playclick, harddrop),
            ray.KEY_UP => move(game.rotate, sfx.playclick, sfx.playerror),
            ray.KEY_C => move(game.swappiece, sfx.playwoosh, sfx.playerror),
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

    sfx.playwoosh();
    sfx.playclack();

    const lines: i32 = game.harddrop();
    progression(lines);
    game.nextpiece();
}

fn progression(lines: i32) void {
    if (lines < 1) return;
    game.state.progression.score += 1000 * lines * lines;
    game.state.progression.cleared += lines;
    sfx.playclear();
    if (lines > 3) sfx.playwin();
    if (game.state.progression.clearedperlevel > 6) {
        std.debug.print("level up\n", .{});
        gfx.nextbackground();
        sfx.nextmusic();
        sfx.playlevel();
        game.state.progression.level += 1;
        game.state.progression.score += 1000 * game.state.progression.level;
        game.state.progression.dropinterval -= 0.15;
        if (game.state.progression.dropinterval <= 0.1) {
            game.state.progression.dropinterval = 0.1;
        }
        // fixme: controllability at high levels
        // feels much better with no animation
        if (game.state.progression.dropinterval <= 0.3) {
            game.state.piece.slider.duration = 50;
        }
        game.state.progression.clearedperlevel = 0;
    }
}

// move the piece, if it can't move, call failback
fn move(comptime movefn: fn () bool, comptime ok: fn () void, comptime fail: fn () void) void {
    if (game.frozen())
        return;
    if (movefn()) {
        ok();
    } else {
        fail();
    }
}

fn checkleak() void {
    const leaks = game.state.gpallocator.detectLeaks();
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
