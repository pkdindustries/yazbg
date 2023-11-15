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

    game.init();

    while (!ray.WindowShouldClose()) {

        // fill music and draw the frame
        sys.updatemusic();
        gfx.frame();

        // user events
        if (ray.IsKeyPressed(ray.KEY_R)) {
            game.init();
            continue;
        }
        // pause
        if (ray.IsKeyPressed(ray.KEY_P)) {
            game.pause();
            continue;
        }

        if (game.frozen()) {
            continue;
        }

        // game ticker
        if (ray.GetTime() - game.state.lastmove >= game.state.dropinterval) {
            std.debug.print("tick\n", .{});
            move(game.down, sys.playclick, drop);
            continue;
        }

        // left
        if (ray.IsKeyPressed(ray.KEY_LEFT)) {
            move(game.left, sys.playclick, sys.playerror);
        }

        // right
        if (ray.IsKeyPressed(ray.KEY_RIGHT)) {
            move(game.right, sys.playclick, sys.playerror);
        }

        // soft drop
        if (ray.IsKeyPressed(ray.KEY_DOWN)) {
            move(game.down, sys.playclick, drop);
        }

        // rotate
        if (ray.IsKeyPressed(ray.KEY_UP)) {
            move(game.rotate, sys.playclick, sys.playerror);
        }

        // hard drop
        if (ray.IsKeyPressed(ray.KEY_SPACE)) {
            drop();
        }

        // swap piece
        if (ray.IsKeyPressed(ray.KEY_C)) {
            swap();
        }
    }
}

fn swap() void {
    if (game.swappiece()) {
        sys.playwoosh();
    } else {
        sys.playerror();
    }
}

fn drop() void {
    std.debug.print("drop\n", .{});
    sys.playwoosh();
    sys.playclack();
    if (game.drop()) {
        sys.playclear();
    }
    game.nextpiece();
}

// move the piece, if it can't move, call failback
fn move(comptime movefn: fn () bool, comptime ok: fn () void, comptime fail: fn () void) void {
    if (movefn()) {
        ok();
    } else {
        fail();
    }
}
