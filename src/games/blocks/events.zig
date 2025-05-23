// games/blocks/events.zig - Tetris-specific event types
const std = @import("std");
const engine = @import("engine");
const engine_events = engine.events;
const ray = engine.raylib;

// ---------------------------------------------------------------------------
// Tetris Event Types
// ---------------------------------------------------------------------------

pub const Event = union(enum) {
    // Input-driven movement
    MoveLeft,
    MoveRight,
    MoveDown,
    AutoDrop, // Triggered by drop timer
    Rotate,
    RotateCCW,
    HardDrop,
    SwapPiece,
    Hold,
    
    // Game state
    Clear: u8, // payload = number of lines
    LevelUp: u8, // payload = new level number
    SpeedUp,
    ScoreUpdate: i32, // payload = points to add
    Spawn, // A new piece spawned
    PieceLocked: struct {
        blocks: [4]struct { x: i32, y: i32, color: [4]u8 },
        count: usize,
    },
    LineClearing: struct { y: i32 }, // payload = row being cleared
    RowsShiftedDown: struct { start_y: i32, count: i32 }, // rows shifted after line clear
    GridReset,
    Win,
    Lose,
    GameOver,
    
    // Meta/UI
    Pause,
    Reset,
    NextMusic,
    NextBackground,
    MuteAudio,
    Debug,
    ToggleDebugLayer,
    
    // Animation/feedback
    Error, // Invalid move attempted
    Kick, // Wall kick successful
    
    // Effects
    HardDropEffect,
    PlayerPositionUpdated: struct {
        x: i32,
        y: i32,
        rotation: u32,
        ghost_y: i32,
        piece_index: u32,
        next_piece_index: u32,
        hold_piece_index: u32,
    },
};

// ---------------------------------------------------------------------------
// Event System Instance
// ---------------------------------------------------------------------------

pub const EventSystem = engine_events.EventSystem(Event);
pub const EventQueue = engine_events.EventQueue(Event);
pub const Source = EventQueue.Source;

// Convenience functions that forward to the global instance
pub const init = EventSystem.init;
pub const deinit = EventSystem.deinit;
pub const push = EventSystem.push;
pub const clear = EventSystem.clear;
pub const items = EventSystem.items;
pub const queue = EventSystem.queue;

// ---------------------------------------------------------------------------
// Input Handling
// ---------------------------------------------------------------------------

pub fn processInputs() void {
    // One-shot keys
    const oneshot_keys = .{
        .{ ray.KEY_UP, Event.Rotate },
        .{ ray.KEY_Z, Event.RotateCCW },
        .{ ray.KEY_SPACE, Event.HardDrop },
        .{ ray.KEY_C, Event.SwapPiece },
        .{ ray.KEY_B, Event.NextBackground },
        .{ ray.KEY_P, Event.Pause },
        .{ ray.KEY_R, Event.Reset },
        .{ ray.KEY_M, Event.MuteAudio },
        .{ ray.KEY_N, Event.NextMusic },
    };

    const q = queue();
    q.processInputMappings(oneshot_keys, ray.IsKeyPressed) catch {};
}