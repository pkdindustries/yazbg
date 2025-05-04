const std = @import("std");
const ecs = @import("ecs");
const ray = @import("raylib.zig");

// rendering and general positioning (pixel coordinates)
pub const Position = struct { x: f32, y: f32 }; // Replaces anim_state.position [cite: 464]

// visual representation (color, scale, rotation)
pub const Sprite = struct { rgba: [4]u8, size: f32, rotation: f32 = 0.0 }; // Replaces anim_state.color, scale[cite: 464], CellData.color [cite: 482]

// texture
pub const Texture = struct {
    /// Pointer to the shared render texture.
    texture: *const ray.RenderTexture2D,
    uv: [4]f32 = .{ 0.0, 0.0, 1.0, 1.0 },
    created: bool = false,
};

// shader
pub const Shader = struct {
    /// Pointer to the shared shader.
    shader: *const ray.Shader,
    /// Whether this component owns the shader (responsible for unloading)
    created: bool = false,
    /// HashMap of uniform name to value
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
};

pub const UniformType = enum {
    float,
    vec2,
    vec3,
    vec4,
};

pub const ShaderUniform = union(UniformType) {
    float: f32,
    vec2: [2]f32,
    vec3: [3]f32,
    vec4: [4]f32,
};

// Tag for temporary flash/fade effects
pub const Flash = struct {
    ttl_ms: i64,
    expires_at_ms: i64,
};

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

// --- Components for later steps (define now for clarity) ---

// For static blocks settled on the grid
pub const GridPos = struct { x: i32, y: i32 }; // Logical grid coordinates (replaces CellLayer indexing [cite: 476])
pub const BlockTag = struct {}; // Marker for settled blocks

// For the active player piece
pub const PieceKind = struct { shape: *const [4][4][4]bool, color: [4]u8 }; // From game.state.piece.current [cite: 128]
pub const Rotation = struct { index: u2 }; // From game.state.piece.r [cite: 129]
pub const ActivePieceTag = struct {}; // Marker for the single active piece entity
pub const PieceBlockTag = struct {}; // Marker for blocks belonging to active piece
pub const GhostBlockTag = struct {}; // Marker for blocks belonging to ghost preview
