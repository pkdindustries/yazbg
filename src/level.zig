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

    pub fn reset(self: *Progression) void {
        self.score = 0;
        self.level = 0;
        self.cleared = 0;
        self.clearedthislevel = 0;
        self.dropinterval_ms = 2_000;
    }

    pub fn clear(self: *Progression, lines: u8) void {
        std.debug.print("clearing {d} lines\n", .{lines});
        const cleared = @as(i32, lines);
        // Score: 1000 * (lines^2)
        const line_score = 1000 * cleared * cleared;
        self.score += line_score;
        // Send score update event
        events.push(.{ .ScoreUpdate = line_score }, events.Source.Level);

        self.cleared += cleared;
        // Tetris bonus
        if (cleared > 3) {
            // Defer follow‑up events so that they are visible in the next frame.
            events.pushDeferred(.Win, events.Source.Level);
        }
        // Level up
        self.clearedthislevel += cleared;
        if (self.clearedthislevel > 6) {
            self.level += 1;

            const level_bonus = 1000 * self.level;
            self.score += level_bonus;
            // Send score update for level bonus
            events.push(.{ .ScoreUpdate = level_bonus }, events.Source.Level);

            self.dropinterval_ms -= 150;
            self.clearedthislevel = 0;
            if (self.dropinterval_ms <= 100) {
                self.dropinterval_ms = 100;
            }

            events.push(.{ .LevelUp = @as(u8, @intCast(self.level)) }, events.Source.Level);
            events.push(.NextBackground, events.Source.Level);
        }
    }
};
