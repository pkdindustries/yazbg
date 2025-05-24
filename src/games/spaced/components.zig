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
// Spaceship Components
// ---------------------------------------------------------------------------

pub const Spaceship = struct {
    // Ship physics
    max_speed: f32 = 200.0,
    acceleration: f32 = 300.0,
    deceleration: f32 = 150.0,
    turn_speed: f32 = 3.0, // radians per second
    
    // Current state
    thrust: f32 = 0.0, // 0.0 to 1.0 thrust level
    target_rotation: f32 = 0.0, // desired facing direction in radians
    angular_velocity: f32 = 0.0, // current turn rate
    
    // Visual effects
    thrust_particles: bool = false,
    banking_angle: f32 = 0.0, // visual banking during turns
};

pub const ThrustEffect = struct {
    intensity: f32 = 0.0, // 0.0 to 1.0
    pulse_time: f32 = 0.0, // for pulsing effects
    particle_spawn_timer: f32 = 0.0,
};

// Control input for spaceships (can be from player keyboard or AI)
pub const ControlInput = struct {
    turn_input: f32 = 0.0, // -1.0 = turn left, 0.0 = no turn, 1.0 = turn right
    thrust_input: f32 = 0.0, // 0.0 = no thrust, 1.0 = full thrust
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