// games/blocks/components.zig - Tetris-specific components
const std = @import("std");
const ecs = @import("ecs");

// ---------------------------------------------------------------------------
// Grid Components
// ---------------------------------------------------------------------------

// For static blocks settled on the grid
pub const GridPos = struct { x: i32, y: i32 }; // Logical grid coordinates
pub const BlockTag = struct {}; // Marker for settled blocks

// ---------------------------------------------------------------------------
// Active Piece Components  
// ---------------------------------------------------------------------------

// For the active player piece
pub const PieceKind = struct { shape: *const [4][4][4]bool, color: [4]u8 };
pub const Rotation = struct { index: u2 };
pub const ActivePieceTag = struct {}; // Marker for the single active piece entity
pub const PieceBlockTag = struct {}; // Marker for blocks belonging to active piece
pub const GhostBlockTag = struct {}; // Marker for blocks belonging to ghost preview

// Player piece state - stored with the active piece entity
pub const PlayerPieceState = struct {
    x: i32, // logical grid x position
    y: i32, // logical grid y position
    prev_x: i32 = 0, // previous x position for animation
    prev_y: i32 = 0, // previous y position for animation
    prev_ghost_y: i32 = 0, // previous ghost y for animation
    rotation: u32, // current rotation index
    ghost_y: i32, // calculated landing position
    piece_index: u32, // current piece type index
    has_piece: bool = true, // whether this entity has an active piece
};

// ---------------------------------------------------------------------------
// HUD Preview Components
// ---------------------------------------------------------------------------

// HUD preview tags
pub const NextPreviewTag = struct {}; // blocks belonging to the "next" piece preview
pub const HoldPreviewTag = struct {}; // blocks belonging to the "held" piece preview
pub const AnimatingToHoldTag = struct {}; // blocks being animated to the hold position
pub const AnimatingFromHoldTag = struct {}; // blocks being animated from hold position to spawn

// Per-block cell indices (used by preview system for animations)
pub const PreviewCell = struct { col: i32, row: i32 };