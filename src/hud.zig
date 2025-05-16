const std = @import("std");
const events = @import("events.zig");
const ray = @import("raylib.zig");
const shapes = @import("pieces.zig");

// Lightweight, event‑driven heads‑up display state.  The renderer queries the
// current values once per frame.  All writes happen exclusively through the
// event stream so we never reach into the core `game.state` from the UI.
pub const Hud = struct {
    score: i32 = 0,
    lines: i32 = 0,
    level: i32 = 0,
    paused: bool = false,
    gameover: bool = false,

    // Reset to an initial, empty state (e.g. after the player restarted the
    // game).
    fn reset(self: *Hud) void {
        self.* = Hud{};
    }
};

// Single global HUD instance – cheap and convenient.
pub var state: Hud = .{};

// Inspect all queued events and update the HUD accordingly.  Must be called
// exactly once per frame after game logic has queued its events and before
// the renderer reads the HUD values.
pub fn process(queue: *events.EventQueue) void {
    for (queue.items()) |rec| {
        switch (rec.event) {
            // -----------------------------------------------------------------
            // Gameplay progression
            // -----------------------------------------------------------------
            .Clear => |raw_lines| {
                const lines: i32 = @intCast(raw_lines);
                state.lines += lines;
            },
            .LevelUp => |_| {
                std.debug.print("process level up\n", .{});
                state.level += 1;
            },
            .ScoreUpdate => |points| {
                state.score += points;
            },

            // -----------------------------------------------------------------
            // Run state
            // -----------------------------------------------------------------
            .Pause => state.paused = !state.paused,
            .Reset => state.reset(),
            .GameOver => state.gameover = true,
            else => {},
        }
    }
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

pub const DrawContext = struct {
    gridoffsetx: i32,
    gridoffsety: i32,
    cellsize: i32,
    cellpadding: i32,
    font: ray.Font,
    og_width: i32,
    og_height: i32,
    next_piece: ?shapes.tetramino = null,
    held_piece: ?shapes.tetramino = null,
};

var textbuf: [1000]u8 = undefined;

// Render the HUD (score, next & held pieces, pause/game‑over overlays).
// Should be called while drawing to the off‑screen game texture, after the
// playfield has been rendered.
pub fn draw(ctx: DrawContext) void {
    // Consistent line spacing for multiline text blocks
    ray.SetTextLineSpacing(1.0);

    const bordercolor = ray.Color{ .r = 0, .g = 0, .b = 255, .a = 20 };

    // Sidebar backgrounds
    ray.DrawRectangle(0, 0, 140, ctx.og_height, bordercolor);
    ray.DrawRectangle(ctx.og_width - 135, 0, 135, ctx.og_height, bordercolor);

    // Vertical separator lines
    ray.DrawLineEx(ray.Vector2{ .x = 140.0, .y = 0.0 }, ray.Vector2{ .x = 140.0, .y = @floatFromInt(ctx.og_height) }, 3, ray.RED);
    ray.DrawLineEx(ray.Vector2{ .x = @floatFromInt(ctx.og_width - 135), .y = 0 }, ray.Vector2{ .x = @floatFromInt(ctx.og_width - 135), .y = @floatFromInt(ctx.og_height) }, 3, ray.RED);

    // Score / lines / level block ------------------------------------------------
    if (std.fmt.bufPrintZ(&textbuf, "score\n{}\n\nlines\n{}\n\nlevel\n{}", .{ state.score, state.lines, state.level })) |score_txt| {
        var color = ray.GREEN;
        if (true) {
            scramblefx(score_txt, 10);
            color = ray.RED;
        }
        ray.DrawTextEx(ctx.font, score_txt, ray.Vector2{ .x = 10, .y = 590 }, 20, 0, color);
    } else |err| {
        std.debug.print("HUD: score bufPrintZ error: {}\n", .{err});
    }

    // Preview of next piece ------------------------------------------------------
    ray.DrawTextEx(ctx.font, "NEXT", ray.Vector2{ .x = 520, .y = 30 }, 40, 2, ray.GRAY);
    if (ctx.next_piece) |np| {
        piece(&ctx, ctx.og_width - 250, 35, np.shape[0], np.color);
    }

    // Held piece -----------------------------------------------------------------
    ray.DrawTextEx(ctx.font, "HELD", ray.Vector2{ .x = 23, .y = 30 }, 40, 2, ray.GRAY);
    if (ctx.held_piece) |hp| {
        piece(&ctx, 35 - ctx.gridoffsetx, 35, hp.shape[0], hp.color);
    }

    // Pause overlay --------------------------------------------------------------
    if (state.paused) {
        ray.DrawRectangle(0, 0, ctx.og_width, ctx.og_height, ray.Color{ .r = 0, .g = 0, .b = 0, .a = 100 });

        if (std.fmt.bufPrintZ(&textbuf, "PAUSED", .{})) |paused_txt| {
            scramblefx(paused_txt, 10);
            ray.DrawTextEx(ctx.font, paused_txt, ray.Vector2{ .x = 210, .y = 300 }, 60, 3, ray.ORANGE);
            ray.DrawText("press p to unpause", 220, 350, 20, ray.RED);
        } else |err| {
            std.debug.print("HUD: paused bufPrintZ error: {}\n", .{err});
        }
    }

    // Game‑over overlay ----------------------------------------------------------
    if (state.gameover) {
        ray.DrawRectangle(0, 0, ctx.og_width, ctx.og_height, ray.Color{ .r = 10, .g = 0, .b = 0, .a = 200 });

        if (std.fmt.bufPrintZ(&textbuf, "GAME OVER", .{})) |over_txt| {
            scramblefx(over_txt, 1);
            ray.DrawTextEx(ctx.font, over_txt, ray.Vector2{ .x = 165, .y = 290 }, 70, 3, ray.RED);
            ray.DrawText("r to restart", 255, 350, 20, ray.WHITE);
            ray.DrawText("esc to exit", 255, 375, 20, ray.WHITE);
        } else |err| {
            std.debug.print("HUD: game‑over bufPrintZ error: {}\n", .{err});
        }
    }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn piece(ctx: *const DrawContext, x: i32, y: i32, shape: [4][4]bool, color: [4]u8) void {
    for (shape, 0..) |row, i| {
        for (row, 0..) |cell, j| {
            if (cell) {
                const xs: i32 = @as(i32, @intCast(i)) * ctx.cellsize;
                const ys: i32 = @as(i32, @intCast(j)) * ctx.cellsize;
                roundedfillbox(ctx, x + xs, y + ys, color);
            }
        }
    }
}

fn roundedfillbox(ctx: *const DrawContext, x: i32, y: i32, color: [4]u8) void {
    ray.DrawRectangleRounded(ray.Rectangle{
        .x = @floatFromInt(ctx.gridoffsetx + x),
        .y = @floatFromInt(ctx.gridoffsety + y),
        .width = @floatFromInt(ctx.cellsize - 2 * ctx.cellpadding),
        .height = @floatFromInt(ctx.cellsize - 2 * ctx.cellpadding),
    }, 0.4, 20, ray.Color{ .r = color[0], .g = color[1], .b = color[2], .a = color[3] });
}

const scrambles = "!@#$%^&*+-=<>?/\\|~`";

fn scramblefx(s: []u8, intensity: i32) void {
    for (s) |*c| {
        // generate a random byte using crypto‑secure RNG available everywhere
        var idx_buf: [1]u8 = undefined;
        std.crypto.random.bytes(&idx_buf);
        const idx = idx_buf[0] % scrambles.len;
        const n = scrambles[idx];

        if (c.* == '\n' or c.* == ' ') continue;

        var chance_buf: [1]u8 = undefined;
        std.crypto.random.bytes(&chance_buf);
        const roll: u8 = chance_buf[0] % 101; // 0‑100

        if (roll > 100 - intensity) {
            c.* = n;
        }
    }
}
