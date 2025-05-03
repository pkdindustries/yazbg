const std = @import("std");
const builtin = @import("builtin");

/// Position and color data for cell events
pub const CellDataPos = struct {
    x: usize,
    y: usize,
    color: [4]u8,
};

// All side‑effects that the pure game logic might request.
// Renderer/audio layer subscribes and performs real work.
pub const Event = union(enum) {
    // Sound effects
    Error,
    Clear: u8, // payload = number of lines
    Win,
    LevelUp: u8,
    /// New drop interval in milliseconds; emitted by level progression logic when reset or level up
    DropInterval: i64,
    /// Score update event; emitted by level progression logic when score changes
    ScoreUpdate: i32,
    GameOver,

    // Gameplay lifecycle events (pure game‑logic → graphics/audio/UI)
    Spawn, // a new active piece appeared
    /// Emitted when a piece is locked onto the grid with block positions and colors
    PieceLocked: struct {
        blocks: [4]CellDataPos,
        count: usize,
    },
    /// Emitted when a line is being cleared
    LineClearing: struct {
        y: usize,
    },
    /// Emitted when rows are shifted down after clearing
    RowsShiftedDown: struct {
        start_y: usize,
        count: usize,
    },
    /// Emitted when the grid is reset
    GridReset,
    Hold, // player used the hold feature
    Kick, // piece was kicked (rotated) into the grid
    AutoDrop, // automatic dropping of piece based on timing
    /// Emitted when player piece position or rotation changes, including ghost position
    PlayerPositionUpdated: struct {
        x: i32, // Current grid x position
        y: i32, // Current grid y position
        rotation: u32, // Current rotation index
        ghost_y: i32, // Calculated landing position
        piece_index: u32, // Index of the current piece
    },
    // Input events
    MoveLeft,
    MoveRight,
    MoveDown,
    Rotate,
    RotateCCW,
    HardDropEffect,
    HardDrop, // player hard-dropped the piece
    SwapPiece,
    Pause,
    Reset,
    NextBackground,
    MuteAudio,
    NextMusic,
    Debug,
};

pub const Source = enum {
    Input,
    Game,
    Level,
};

pub const TimestampedEvent = struct {
    /// timestamp when the event was enqueued.
    time_ms: i64,
    source: Source,
    event: Event,
};

/// Very small fixed‑size queue – enough for one frame.
pub const EventQueue = struct {
    const MAX = 1024; // live a little
    events: [MAX]TimestampedEvent = undefined,
    len: usize = 0,

    pub fn push(self: *EventQueue, e: Event, source: Source) void {
        if (self.len < MAX) {
            const time_ms = std.time.milliTimestamp();
            self.events[self.len] = TimestampedEvent{
                .time_ms = time_ms,
                .source = source,
                .event = e,
            };
            self.len += 1;

            if (builtin.mode == .Debug) {
                std.debug.print("{any}\n", .{self.events[self.len - 1]});
            }
        } else {
            // Silently drop when overflow – should never happen in this game.
            std.debug.print("EventQueue overflow – dropping event {any} (source={any})\n", .{ e, source });
        }
    }

    pub fn items(self: *EventQueue) []const TimestampedEvent {
        return self.events[0..self.len];
    }

    pub fn clear(self: *EventQueue) void {
        self.len = 0;
    }
};

//   * `queue`        – events that are going to be processed in the *current*
//                       frame.
//   * `deferred`     – events that were raised *during* event processing and
//                       therefore need to be delivered in the *next* frame.
pub var queue: EventQueue = .{};

pub var deferred: EventQueue = .{};

pub inline fn push(e: Event, s: Source) void {
    queue.push(e, s);
}

// will be processed on the *next* frame*.
pub inline fn pushDeferred(e: Event, s: Source) void {
    deferred.push(e, s);
}

// move all deferred events into the main queue
pub fn flushDeferred() void {
    for (deferred.items()) |rec| {
        queue.push(rec.event, rec.source);
    }
    deferred.clear();
}
