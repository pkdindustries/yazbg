// engine root module - exports all engine components

pub const raylib = @import("raylib.zig");
pub const gfx = @import("gfx.zig");
pub const sfx = @import("sfx.zig");
pub const ecs = @import("ecs.zig");
pub const components = @import("components.zig");
pub const events = @import("events.zig");
pub const textures = @import("textures.zig");
pub const shaders = @import("shaders.zig");
pub const debug_layer = @import("debug.zig");

// Systems
pub const systems = struct {
    pub const anim = @import("systems/anim.zig");
    pub const collision = @import("systems/collision.zig");
};
