const std = @import("std");
const builtin = @import("builtin");

// Position and color data for cell events
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
    // New drop interval in milliseconds; emitted by level progression logic when reset or level up
    DropInterval: i64,
    // Score update event; emitted by level progression logic when score changes
    ScoreUpdate: i32,
    GameOver,

    // Gameplay lifecycle events (pure game‑logic → graphics/audio/UI)
    Spawn, // a new   piece appeared
    // Emitted when a piece is locked onto the grid with block positions and colors
    PieceLocked: struct {
        blocks: [4]CellDataPos,
        count: usize,
    },
    // Emitted when a line is being cleared
    LineClearing: struct {
        y: usize,
    },
    // Emitted when rows are shifted down after clearing
    RowsShiftedDown: struct {
        start_y: usize,
        count: usize,
    },
    // Emitted when the grid is reset
    GridReset,
    Hold, // player used the hold feature
    Kick, // piece was kicked (rotated) into the grid
    AutoDrop, // automatic dropping of piece based on timing
    // Emitted when player piece position or rotation changes, including ghost position
    PlayerPositionUpdated: struct {
        x: i32, // Current grid x position
        y: i32, // Current grid y position
        rotation: u32, // Current rotation index
        ghost_y: i32, // Calculated landing position
        piece_index: u32, // Index of the current piece
        next_piece_index: u32, // Index of the next piece
        hold_piece_index: u32, // Index of the held piece
    },

    // input events
    MoveLeft,
    MoveRight,
    MoveDown,
    Rotate,
    RotateCCW,
    HardDropEffect,
    HardDrop,
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
    // timestamp when the event was enqueued.
    time_ms: i64,
    source: Source,
    event: Event,
};

pub const EventQueue = struct {
    list: std.BoundedArray(TimestampedEvent, 512),

    pub fn init() EventQueue {
        return EventQueue{ .list = try std.BoundedArray(TimestampedEvent, 512).init(512) };
    }

    pub fn push(self: *EventQueue, e: Event, source: Source) void {
        const time_ms = std.time.milliTimestamp();
        const item = TimestampedEvent{ .time_ms = time_ms, .source = source, .event = e };
        _ = self.list.append(item) catch unreachable;
    }

    pub fn items(self: *EventQueue) []const TimestampedEvent {
        return self.list.constSlice();
    }

    pub fn clear(self: *EventQueue) void {
        self.list.clear();
    }
};

//   * `queue`        – events that are going to be processed in the *current*
//                       frame.

pub var queue = EventQueue.init();

pub inline fn push(e: Event, s: Source) void {
    queue.push(e, s);
}
