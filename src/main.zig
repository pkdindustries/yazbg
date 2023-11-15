const std = @import("std");
const ray = @import("raylib.zig");
const pieces = @import("pieces.zig");
const game = @import("game.zig");
const sys = @import("system.zig");
const gfx = @import("gfx.zig");

pub fn main() !void {
    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT | ray.FLAG_VSYNC_HINT | ray.FLAG_WINDOW_ALWAYS_RUN);
    ray.InitWindow(gfx.width, gfx.height, "yazbg");
    ray.SetTraceLogLevel(ray.LOG_WARNING);

    try sys.init();
    defer sys.deinit();

    game.reset();

    while (!ray.WindowShouldClose()) {
        // fill music and draw the frame
        sys.updatemusic();
        gfx.frame();

        switch (ray.GetKeyPressed()) {
            ray.KEY_P => game.pause(),
            ray.KEY_R => game.reset(),
            ray.KEY_LEFT => move(game.left, sys.playclick, sys.playerror),
            ray.KEY_RIGHT => move(game.right, sys.playclick, sys.playerror),
            ray.KEY_DOWN => move(game.down, sys.playclick, drop),
            ray.KEY_UP => move(game.rotate, sys.playclick, sys.playerror),
            ray.KEY_SPACE => drop(),
            ray.KEY_C => move(game.swappiece, sys.playwoosh, sys.playerror),
            else => {},
        }

        // game ticker
        if (game.tickable()) {
            std.debug.print("tick\n", .{});
            move(game.down, sys.playclick, drop);
            continue;
        }
    }
}

fn drop() void {
    if (game.frozen())
        return;

    sys.playwoosh();
    sys.playclack();

    var lines: i32 = game.drop();
    if (lines > 0) {
        progression(lines);
    }
    game.nextpiece();
}

fn progression(lines: i32) void {
    sys.playclear();
    game.state.score += 1000 * lines * lines;
    if (@rem(game.state.lines, 3) == 0) {
        std.debug.print("level up\n", .{});
        sys.playlevel();
        game.state.level += 1;
        game.state.score += 1000 * game.state.level;
        game.state.dropinterval -= 0.15;
        if (game.state.dropinterval < 0.2) {
            game.state.dropinterval = 0.2;
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
