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
    events.push(.{ .DropInterval = progression.dropinterval_ms }, events.Source.Level);
}

/// Handles progression-related events and updates local progression state.
pub fn process(queue: *events.EventQueue) void {
    for (queue.items()) |rec| {
        // debug: print event, source, and timestamp
        switch (rec.event) {
            .Reset => handleReset(),
            .Clear => |lines| handleClear(lines),
            else => {},
        }
    }
}

fn handleClear(lines: u8) void {
    std.debug.print("clearing {d} lines\n", .{lines});
    const cleared = @as(i32, lines);
    // Score: 1000 * (lines^2)
    const line_score = 1000 * cleared * cleared;
    progression.score += line_score;
    // Send score update event
    events.push(.{ .ScoreUpdate = line_score }, events.Source.Level);

    progression.cleared += cleared;
    // Tetris bonus
    if (cleared > 3) {
        // Defer follow‑up events so that they are visible in the next frame.
        events.pushDeferred(.Win, events.Source.Level);
    }
    // Level up
    progression.clearedthislevel += cleared;
    if (progression.clearedthislevel > 6) {
        progression.level += 1;

        const level_bonus = 1000 * progression.level;
        progression.score += level_bonus;
        // Send score update for level bonus
        events.push(.{ .ScoreUpdate = level_bonus }, events.Source.Level);

        progression.dropinterval_ms -= 150;
        progression.clearedthislevel = 0;
        if (progression.dropinterval_ms <= 100) {
            progression.dropinterval_ms = 100;
        }

        events.pushDeferred(.{ .LevelUp = @as(u8, @intCast(progression.level)) }, events.Source.Level);
        events.pushDeferred(.{ .DropInterval = progression.dropinterval_ms }, events.Source.Level);
    }
}
