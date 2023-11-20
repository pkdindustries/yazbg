const std = @import("std");
const ray = @import("raylib.zig");
const game = @import("game.zig");
const sys = @import("system.zig");
const gfx = @import("gfx.zig");

pub fn main() !void {
    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT | ray.FLAG_VSYNC_HINT | ray.FLAG_WINDOW_ALWAYS_RUN);
    ray.InitWindow(gfx.windowwidth, gfx.windowheight, "yazbg");
    ray.SetTraceLogLevel(ray.LOG_WARNING);
    ray.SetTargetFPS(120);

    try sys.init();
    defer sys.deinit();

    try gfx.init();
    defer gfx.deinit();

    sys.playmusic();
    game.reset();
    while (!ray.WindowShouldClose()) {
        // fill music buffer
        sys.updatemusic(game.state.paused);
        // tick
        tick();
        // draw the frame
        gfx.frame();
        // handle input
        switch (ray.GetKeyPressed()) {
            ray.KEY_P => game.pause(),
            ray.KEY_R => game.reset(),
            ray.KEY_SPACE => drop(),
            ray.KEY_LEFT => move(game.left, sys.playclick, sys.playerror),
            ray.KEY_RIGHT => move(game.right, sys.playclick, sys.playerror),
            ray.KEY_DOWN => move(game.down, sys.playclick, drop),
            ray.KEY_UP => move(game.rotate, sys.playclick, sys.playerror),
            ray.KEY_C => move(game.swappiece, sys.playwoosh, sys.playerror),
            ray.KEY_B => gfx.randombackground(),
            else => {},
        }
    }
}

fn tick() void {
    if (game.tickable()) {
        move(game.down, sys.playclick, drop);
    }
}

fn drop() void {
    if (game.frozen()) return;

    sys.playwoosh();
    sys.playclack();

    const lines: i32 = game.harddrop();
    progression(lines);
    game.nextpiece();
}

fn progression(lines: i32) void {
    if (lines < 1) return;
    game.state.score += 1000 * lines * lines;
    if (lines >= 1) sys.playclear();
    if (lines > 3) sys.playwin();
    if (@rem(game.state.lines, 3) == 0) {
        std.debug.print("level up\n", .{});
        gfx.randombackground();
        sys.playlevel();
        sys.nextmusic();
        game.state.level += 1;
        game.state.score += 1000 * game.state.level;
        game.state.dropinterval -= 0.15;
        if (game.state.dropinterval <= 0.2) {
            game.state.dropinterval = 0.2;
        }
        // fixme: controllability at high levels
        // feels much better with no animation
        if (game.state.dropinterval <= 0.4) {
            game.state.pieceslider.duration = 10;
            game.state.lineclearer.duration = 100;
        }
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
