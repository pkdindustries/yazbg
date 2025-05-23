// components.zig - Spaced-specific components
const std = @import("std");

// ---------------------------------------------------------------------------
// Player Components
// ---------------------------------------------------------------------------

pub const Player = struct {}; // Marker component for the player
pub const Health = struct { 
    current: f32, 
    max: f32,
    
    pub fn isDead(self: @This()) bool {
        return self.current <= 0.0;
    }
    
    pub fn getPercent(self: @This()) f32 {
        return self.current / self.max;
    }
};

// ---------------------------------------------------------------------------
// Enemy Components  
// ---------------------------------------------------------------------------

pub const Enemy = struct {
    damage: f32 = 10.0,
    speed: f32 = 50.0,
    collision_cooldown: f32 = 0.0, // Time before AI can chase again after collision
};

// ---------------------------------------------------------------------------
// Combat Components
// ---------------------------------------------------------------------------

pub const Damage = struct { 
    amount: f32,
    source: Entity = 0, // entity that caused the damage
};

// Use engine Entity type
const Entity = @import("ecs").Entity;