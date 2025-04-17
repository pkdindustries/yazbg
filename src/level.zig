const std = @import("std");
const events = @import("events.zig");
const game = @import("game.zig");

/// Handles progression-related events and updates game.state.progression.
pub fn process(queue: *events.EventQueue) void {
    // Process all existing events for progression before audio/graphics.
    for (queue.items()) |e| {
        switch (e) {
            .Clear => |lines| handleClear(lines),
            else => {},
        }
    }
}

fn handleClear(lines: u8) void {
    const cleared = @as(i32, lines);
    // Score: 1000 * (lines^2)
    game.state.progression.score += 1000 * cleared * cleared;
    game.state.progression.cleared += cleared;
    // Tetris bonus
    if (cleared > 3) {
        events.push(.Win);
    }
    // Level up
    game.state.progression.clearedthislevel += cleared;
    if (game.state.progression.clearedthislevel > 6) {
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