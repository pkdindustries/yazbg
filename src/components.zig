const ecs = @import("ecs");

// rendering and general positioning (pixel coordinates)
pub const Position = struct { x: f32, y: f32 }; // Replaces anim_state.position [cite: 464]

// visual representation (color, scale)
pub const Sprite = struct { rgba: [4]u8, size: f32 }; // Replaces anim_state.color, scale[cite: 464], CellData.color [cite: 482]

// Tag for temporary flash/fade effects
pub const Flash = struct {
    ttl_ms: i64,
    expires_at_ms: i64,
};

// --- Components for later steps (define now for clarity) ---

// For static blocks settled on the grid
pub const GridPos = struct { x: i32, y: i32 }; // Logical grid coordinates (replaces CellLayer indexing [cite: 476])
pub const BlockTag = struct {}; // Marker for settled blocks

// For the active player piece
pub const PieceKind = struct { shape: *const [4][4][4]bool, color: [4]u8 }; // From game.state.piece.current [cite: 128]
pub const Rotation = struct { index: u2 }; // From game.state.piece.r [cite: 129]
pub const ActivePieceTag = struct {}; // Marker for the single active piece entity
