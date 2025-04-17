const std = @import("std");
const events = @import("events.zig");
// Progression state moved here from game.state
pub const Progression = struct {
    score: i32 = 0,
    level: i32 = 0,
    // total lines cleared
    cleared: i32 = 0,
    // lines cleared since last level up
    clearedthislevel: i32 = 0,
    // time between automatic drops (in milliseconds)
    dropinterval_ms: i64 = 2_000,
};

/// Progression state for the current session.
pub var progression: Progression = .{};

fn handleReset() void {
    progression = .{};
    // inform subscribers of reset drop interval
    events.push(.{ .DropInterval = progression.dropinterval_ms });
}

/// Handles progression-related events and updates local progression state.
pub fn process(queue: *events.EventQueue) void {
    for (queue.items()) |e| {
        switch (e) {
            .Reset => handleReset(),
            .Clear => |lines| handleClear(lines),
            else => {},
        }
    }
}

fn handleClear(lines: u8) void {
    const cleared = @as(i32, lines);
    // Score: 1000 * (lines^2)
    progression.score += 1000 * cleared * cleared;
    progression.cleared += cleared;
    // Tetris bonus
    if (cleared > 3) {
        events.push(.Win);
    }
    // Level up
    progression.clearedthislevel += cleared;
    if (progression.clearedthislevel > 6) {
        progression.level += 1;

        progression.score += 1000 * progression.level;
        progression.dropinterval_ms -= 150;
        progression.clearedthislevel = 0;
        if (progression.dropinterval_ms <= 100) {
            progression.dropinterval_ms = 100;
        }

        events.push(.{ .LevelUp = @as(u8, @intCast(progression.level)) });
        events.push(.{ .DropInterval = progression.dropinterval_ms });
    }
}
