const std = @import("std");

// All side‑effects that the pure game logic might request.
// Renderer/audio layer subscribes and performs real work.
pub const Event = union(enum) {
    // Sound effects
    Click,
    Error,
    Woosh,
    Clack,
    Clear: u8, // payload = number of lines
    Win,
    LevelUp,
    GameOver,
};

/// Very small fixed‑size queue – enough for one frame.
pub const EventQueue = struct {
    const MAX = 64;
    events: [MAX]Event = undefined,
    len: usize = 0,

    pub fn push(self: *EventQueue, e: Event) void {
        if (self.len < MAX) {
            self.events[self.len] = e;
            self.len += 1;
        } else {
            // Silently drop when overflow – should never happen in this game.
            std.debug.print("EventQueue overflow – dropping event {any}\n", .{e});
        }
    }

    pub fn items(self: *EventQueue) []const Event {
        return self.events[0..self.len];
    }

    pub fn clear(self: *EventQueue) void {
        self.len = 0;
    }
};

// -----------------------------------------------------------------------------
// A single global queue that every part of the program can push to.  The engine
// (renderer / audio) drains it every frame.  This keeps an explicit boundary
// between the pure, platform‑agnostic game logic and the subsystems that cause
// side‑effects such as playing sounds.
// -----------------------------------------------------------------------------

pub var queue: EventQueue = .{};

/// Convenience helper so callers do not have to take the address of the global
/// queue.
pub inline fn push(e: Event) void {
    queue.push(e);
}

