const std = @import("std");
const ecs = @import("ecs");
const ray = @import("raylib.zig");

// rendering and general positioning (pixel coordinates)
pub const Position = struct { x: f32, y: f32 }; // Replaces anim_state.position [cite: 464]

// visual representation (color, scale, rotation)
pub const Sprite = struct { rgba: [4]u8, size: f32, rotation: f32 = 0.0 }; // Replaces anim_state.color, scale[cite: 464], CellData.color [cite: 482]

// texture to use for rendering instead of a simple rectangle
/// A shared render texture that can be drawn by many entities.
///
/// We only store a *pointer* to the RenderTexture2D in the component instead
/// of the full struct.  The struct itself is owned either by the texture cache
/// in `blocktextures.zig` or by a texture that was explicitly created for a
/// single sprite using `rendersys.createSpriteTexture`.  Using a pointer keeps
/// the component size small (one machine word + a flag) and avoids copying the
/// fairly large RenderTexture2D value around for every entity, which showed up
/// as a significant CPU-side cost when tens of thousands of entities each had
/// their own SpriteTexture component.
pub const SpriteTexture = struct {
    /// Pointer to the shared render texture.
    texture: *const ray.RenderTexture2D,

    /// Whether this entity exclusively owns the texture (and therefore is
    /// responsible for freeing it).  Textures coming from the cache return
    /// `false` here; those created via `createSpriteTexture` return `true`.
    created: bool = false,
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

    // Whether to restore the animated properties to their start values when the
    // animation finishes (useful for one-shot flash effects where the property
    // should return to its original value).
    revert_when_done: bool = false,
};

// --- Components for later steps (define now for clarity) ---

// For static blocks settled on the grid
pub const GridPos = struct { x: i32, y: i32 }; // Logical grid coordinates (replaces CellLayer indexing [cite: 476])
pub const BlockTag = struct {}; // Marker for settled blocks

// For the active player piece
pub const PieceKind = struct { shape: *const [4][4][4]bool, color: [4]u8 }; // From game.state.piece.current [cite: 128]
pub const Rotation = struct { index: u2 }; // From game.state.piece.r [cite: 129]
pub const ActivePieceTag = struct {}; // Marker for the single active piece entity
