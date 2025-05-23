// common.zig - Shared imports and aliases for all game files
pub const std = @import("std");
pub const engine = @import("engine");
pub const game_components = @import("components.zig");
pub const game_constants = @import("game_constants.zig");
pub const events = @import("events.zig");

// Unified component namespace
pub const components = struct {
    pub usingnamespace engine.components;
    pub usingnamespace game_components;
};

// Engine module aliases
pub const ecs = engine.ecs;
pub const gfx = engine.gfx;
pub const sfx = engine.sfx;
pub const ray = engine.raylib;
pub const textures = engine.textures;
pub const shaders = engine.shaders;
pub const animsys = engine.systems.anim;
pub const collisionsys = engine.systems.collision;