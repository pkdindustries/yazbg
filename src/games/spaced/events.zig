// events.zig - Spaced-specific event types
const std = @import("std");
const engine = @import("engine");
const engine_events = engine.events;
const ray = engine.raylib;

// ---------------------------------------------------------------------------
// Spaced Event Types
// ---------------------------------------------------------------------------

pub const Event = union(enum) {
    // Player events
    PlayerMoved: struct { x: f32, y: f32 },
    PlayerDamaged: struct { damage: f32, source_entity: u32 },
    PlayerDied,
    PlayerHealed: struct { amount: f32 },
    
    // Enemy events  
    EnemySpawned: struct { x: f32, y: f32, enemy_type: EnemyType },
    EnemyDied: struct { entity: u32, x: f32, y: f32 },
    EnemyDamaged: struct { entity: u32, damage: f32 },
    
    // Combat events
    BulletFired: struct { x: f32, y: f32, direction_x: f32, direction_y: f32 },
    BulletHit: struct { bullet: u32, target: u32, x: f32, y: f32 },
    
    // Game events
    GameOver,
    LevelUp: struct { new_level: u32 },
    ScoreChanged: struct { new_score: i32 },
    
    // Debug
    Debug,
};

pub const EnemyType = enum {
    basic_drone,
    fast_scout,
    heavy_tank,
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
    // One-shot keys - direct implementation for now
    if (ray.IsKeyPressed(ray.KEY_ESCAPE)) {
        _ = push(.GameOver, .Input);
    }
    if (ray.IsKeyPressed(ray.KEY_L)) {
        _ = push(.Debug, .Input);
    }
}