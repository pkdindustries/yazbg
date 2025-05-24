// engine/components.zig - Generic reusable components for any game
const std = @import("std");
const ecs = @import("ecs");
const ray = @import("raylib.zig");

// ---------------------------------------------------------------------------
// Core Components
// ---------------------------------------------------------------------------

// Rendering and general positioning (pixel coordinates)
pub const Position = struct { x: f32, y: f32 };

// Visual representation (color, scale, rotation)
pub const Sprite = struct {
    rgba: [4]u8,
    size: f32, // Scale factor or absolute size depending on game
    rotation: f32 = 0.0, // Rotation in normalized units (0.0-1.0 = 0-360 degrees)
};

// Texture reference with UV coordinates
pub const Texture = struct {
    // Pointer to the shared render texture
    texture: *const ray.RenderTexture2D,
    uv: [4]f32 = .{ 0.0, 0.0, 1.0, 1.0 },
    created: bool = false,
};

// ---------------------------------------------------------------------------
// Shader System
// ---------------------------------------------------------------------------

pub const UniformType = enum {
    float,
    vec2,
    vec3,
    vec4,
    texture,
};

pub const ShaderUniform = union(UniformType) {
    float: f32,
    vec2: [2]f32,
    vec3: [3]f32,
    vec4: [4]f32,
    texture: *const ray.Texture2D,
};

pub const Shader = struct {
    // Pointer to the shared shader
    shader: *const ray.Shader,
    // Whether this component owns the shader (responsible for unloading)
    created: bool = false,
    // HashMap of uniform name to value
    uniforms: std.StringHashMap(ShaderUniform),

    pub fn init(allocator: std.mem.Allocator) Shader {
        return .{
            .shader = undefined,
            .created = false,
            .uniforms = std.StringHashMap(ShaderUniform).init(allocator),
        };
    }

    pub fn deinit(self: *Shader) void {
        self.uniforms.deinit();
        if (self.created) {
            ray.UnloadShader(self.shader.*);
        }
    }

    pub fn setFloat(self: *Shader, name: []const u8, value: f32) !void {
        try self.uniforms.put(name, ShaderUniform{ .float = value });
    }

    pub fn setVec2(self: *Shader, name: []const u8, value: [2]f32) !void {
        try self.uniforms.put(name, ShaderUniform{ .vec2 = value });
    }

    pub fn setVec3(self: *Shader, name: []const u8, value: [3]f32) !void {
        try self.uniforms.put(name, ShaderUniform{ .vec3 = value });
    }

    pub fn setVec4(self: *Shader, name: []const u8, value: [4]f32) !void {
        try self.uniforms.put(name, ShaderUniform{ .vec4 = value });
    }

    pub fn setTexture(self: *Shader, name: []const u8, texture: *const ray.Texture2D) !void {
        try self.uniforms.put(name, ShaderUniform{ .texture = texture });
    }
};

// ---------------------------------------------------------------------------
// Animation System
// ---------------------------------------------------------------------------

pub const easing_types = enum {
    linear,
    ease_in,
    ease_out,
    ease_in_out,
};

// Generic animation component for any property animations
pub const Animation = struct {
    // Animation type flags - which properties to animate
    animate_position: bool = false,
    animate_alpha: bool = false,
    animate_scale: bool = false,
    animate_color: bool = false,
    animate_rotation: bool = false,

    // Position animation (if animate_position=true)
    start_pos: ?[2]f32 = null,
    target_pos: ?[2]f32 = null,

    // Alpha animation (if animate_alpha=true)
    start_alpha: ?u8 = null,
    target_alpha: ?u8 = null,

    // Scale animation (if animate_scale=true)
    start_scale: ?f32 = null,
    target_scale: ?f32 = null,

    // Color animation (if animate_color=true)
    start_color: ?[3]u8 = null, // RGB only (no alpha)
    target_color: ?[3]u8 = null, // RGB only (no alpha)

    // Rotation animation (if animate_rotation=true)
    start_rotation: ?f32 = null,
    target_rotation: ?f32 = null,

    // Timing
    start_time: i64, // when animation started (milliseconds)
    duration: i64, // animation duration (milliseconds)
    delay: i64 = 0, // delay before starting animation (milliseconds)

    // Easing function to use
    easing: easing_types = .ease_out,

    // Callback when complete
    remove_when_done: bool = true, // whether to remove this component when animation completes

    // Whether to destroy the entire entity when animation completes
    destroy_entity_when_done: bool = false,

    // Whether to restore the animated properties to their start values when the
    // animation finishes (useful for one-shot flash effects where the property
    // should return to its original value).
    revert_when_done: bool = false,

    // Callback function to execute when animation completes
    on_complete: ?*const fn (entity: ecs.Entity) void = null,
};

// ---------------------------------------------------------------------------
// Effects
// ---------------------------------------------------------------------------

// Tag for temporary flash/fade effects
pub const Flash = struct {
    ttl_ms: i64,
    expires_at_ms: i64,
};

// ---------------------------------------------------------------------------
// Physics/Movement
// ---------------------------------------------------------------------------

// Velocity for moving entities
pub const Velocity = struct { x: f32 = 0.0, y: f32 = 0.0 };

// Collision detection shape
pub const Collider = struct {
    shape: union(enum) {
        rectangle: ray.Rectangle,
        circle: struct { radius: f32 },
    },
    layer: u8 = 0, // collision layers (player=1, enemy=2, projectile=4, etc)
    is_trigger: bool = false, // just detect, don't block movement
};

// Gravity component - add to entities that should be affected by gravity
pub const Gravity = struct {
    x: f32 = 0,
    y: f32 = 500.0, // default gravity for platformers, set to 0 for top-down
};

// Collision state for visual feedback
pub const CollisionState = struct {
    in_collision: bool = false,
    collision_timer: f32 = 0.0, // time since last collision
    flash_duration: f32 = 0.3, // how long to flash in seconds
};

// ---------------------------------------------------------------------------
// Debug System
// ---------------------------------------------------------------------------

// Global debug state
pub const DebugState = struct {
    enabled: bool = false,
    show_entity_count: bool = true,
    show_fps: bool = true,
    show_component_info: bool = true,
    show_entity_bounds: bool = true,
    show_grid: bool = false,
    overlay_opacity: u8 = 128,
};
