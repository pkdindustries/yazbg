const std = @import("std");

// Live HUD previews for "next" and "held" pieces implemented using regular
// ECS entities.  Each individual block is a tiny sprite entity tagged with one
// of the marker components below so we can query and animate them later
// without keeping any external lists.

const ecs = @import("../ecs.zig");
const ecsroot = @import("ecs");
const components = @import("../components.zig");
const gfx = @import("../gfx.zig");
const pieces = @import("../pieces.zig");
const blocks = @import("../blockbuilder.zig");
const playersys = @import("player.zig");

// ---------------------------------------------------------------------------
// Additional components used only by this system
// ---------------------------------------------------------------------------

// Tag components for easy filtering.
const NextPreviewTag = components.NextPreviewTag;
const HoldPreviewTag = components.HoldPreviewTag;

// Alias to the globally defined component so we don't have to spell out the
// fully-qualified name each time.
const PreviewCell = components.PreviewCell;

// ---------------------------------------------------------------------------
// Fixed HUD coordinates in the original 640×760 render target – the main game
// is rendered into this off-screen buffer and later scaled to the actual
// window size so these values remain static.
// ---------------------------------------------------------------------------

inline fn holdAnchorX() i32 {
    // 35 pixels from the left edge.
    return 35;
}

// ---------------------------------------------------------------------------
// Public helper to clear all existing preview entities – used on full game
// reset so the HUD does not show stale held/next blocks.
// ---------------------------------------------------------------------------

pub fn reset() void {
    clearTag(HoldPreviewTag);
    clearTag(NextPreviewTag);
    clearTag(components.AnimatingToHoldTag);
    clearTag(components.AnimatingFromHoldTag);
}

inline fn holdAnchorY() i32 {
    // 35 pixels below the top + the grid offset (70).
    return gfx.DEFAULT_GRID_OFFSET_Y + 35;
}

inline fn nextAnchorX() i32 {
    // Mirrors the old immediate-draw HUD implementation.
    return gfx.Window.OGWIDTH - 250 + gfx.DEFAULT_GRID_OFFSET_X; // 640 – 250 + 165 = 555
}

inline fn nextAnchorY() i32 {
    return gfx.DEFAULT_GRID_OFFSET_Y + 35;
}

// Spawn location (top-left corner of a freshly spawned piece).
inline fn spawnX() i32 {
    return gfx.DEFAULT_GRID_OFFSET_X + 4 * gfx.DEFAULT_CELL_SIZE;
}

inline fn spawnY() i32 {
    return gfx.DEFAULT_GRID_OFFSET_Y;
}

// Convenience alias.
const CellSize = @TypeOf(gfx.DEFAULT_CELL_SIZE);

// ---------------------------------------------------------------------------
// Public API – invoked from the central event dispatcher (gfx.process)
// ---------------------------------------------------------------------------

// Called when the "Spawn" game event fires.  `next_piece` is the piece that was
// just put into the preview queue by the game logic.
pub fn spawn(next_piece: ?pieces.tetramino) void {
    animateNextPreviewToSpawn();

    // Re-populate the sidebar with a preview of the new upcoming piece.
    if (next_piece) |np| {
        buildNextPreview(np);
    } else {
        clearTag(NextPreviewTag);
    }
}

// Called when the "Hold" game event fires.  `held_piece` is the piece now
// residing in the hold slot.
pub fn hold(held_piece: ?pieces.tetramino) void {
    // First, animate the held piece (if any) to the current player position
    animateHeldToCurrentPiece();

    // Next, animate current piece blocks to the hold position
    animateCurrentPieceToHeld();

    // Clear existing hold preview blocks
    clearTag(HoldPreviewTag);

    // Create new hold preview blocks for the held piece
    if (held_piece) |hp| {
        buildHoldPreview(hp);
    }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

// Animate the held piece preview blocks from the hold position to the current player position.
// This creates visual continuity when swapping pieces.
fn animateHeldToCurrentPiece() void {
    const world = ecs.getWorld();

    // First, clean up any existing animations from hold position to prevent overlapping
    // animations when swapping rapidly
    clearTag(components.AnimatingFromHoldTag);

    // Get player entity and position
    // Use the last stored player-piece origin from the player system – this
    // corresponds to the position of the piece that is about to move into the
    // hold slot.
    const last_origin = playersys.lastOriginPixels();
    const player_pos_x: f32 = last_origin[0];
    const player_pos_y: f32 = last_origin[1];

    // Now animate the hold preview blocks
    var view = world.view(.{ HoldPreviewTag, components.Position, components.PreviewCell, components.Sprite }, .{});
    var it = view.entityIterator();

    const now = std.time.milliTimestamp();
    const cs = gfx.DEFAULT_CELL_SIZE;

    while (it.next()) |ent| {
        const pos = view.get(components.Position, ent);
        const cell = view.get(components.PreviewCell, ent);
        const sprite = view.get(components.Sprite, ent);

        // Calculate target position offset by cell coordinates from current player position
        const tgt_x: f32 = player_pos_x + @as(f32, @floatFromInt(cell.col * cs));
        const tgt_y: f32 = player_pos_y + @as(f32, @floatFromInt(cell.row * cs));

        const anim = components.Animation{
            .animate_position = true,
            .start_pos = .{ pos.x, pos.y },
            .target_pos = .{ tgt_x, tgt_y },
            .animate_scale = true,
            .start_scale = sprite.size,
            .target_scale = 1.0, // Grow to normal size as it goes to the spawn position
            .animate_alpha = true,
            .start_alpha = 20, // Start invisible
            .target_alpha = 150, // Fade in as it goes to the spawn position
            .start_time = now,
            .duration = 120,
            .easing = .ease_out,
            .remove_when_done = true,
            .destroy_entity_when_done = true,
        };

        ecs.replace(components.Animation, ent, anim);

        // Remove the hold preview tag and add the animating tag
        world.remove(HoldPreviewTag, ent);
        world.add(ent, components.AnimatingFromHoldTag{});
    }
}

// Animate the current piece blocks (PieceBlockTag) to the hold position and mark
// them for destruction once the animation ends.
fn animateCurrentPieceToHeld() void {
    const world = ecs.getWorld();

    // First, clean up any existing animations to hold position to prevent overlapping
    // animations when swapping rapidly
    clearTag(components.AnimatingToHoldTag);

    // Now animate the current piece blocks
    var view = world.view(.{ components.PieceBlockTag, components.Position, components.Sprite }, .{});
    var it = view.entityIterator();

    const now = std.time.milliTimestamp();

    while (it.next()) |ent| {
        const pos = view.get(components.Position, ent);
        const sprite = view.get(components.Sprite, ent);

        // Calculate rough position in the hold area
        // We don't have exact cell positions since these are free-moving piece blocks,
        // so we just animate them toward the general hold area
        const tgt_x: f32 = @floatFromInt(holdAnchorX() + 35); // Add offset to center in hold area
        const tgt_y: f32 = @floatFromInt(holdAnchorY() + 35); // Add offset to center in hold area

        const anim = components.Animation{
            .animate_position = true,
            .start_pos = .{ pos.x, pos.y },
            .target_pos = .{ tgt_x, tgt_y },
            .animate_scale = true,
            .start_scale = sprite.size,
            .target_scale = 1, // Shrink as it goes to the hold position
            .animate_alpha = true,
            .start_alpha = 20, // Start invisible
            .target_alpha = 150, // Fade
            .start_time = now,
            .duration = 70,
            .easing = .ease_out,
            .remove_when_done = true,
            .destroy_entity_when_done = true,
        };

        ecs.replace(components.Animation, ent, anim);

        // Remove the piece-specific tag and add the animating tag
        world.remove(components.PieceBlockTag, ent);
        world.add(ent, components.AnimatingToHoldTag{});
    }
}

fn clearTag(comptime Tag: type) void {
    const world = ecs.getWorld();
    var view = world.view(.{Tag}, .{});
    var it = view.entityIterator();
    while (it.next()) |ent| {
        world.destroy(ent);
    }
}

// Build a set of preview block entities for `t` anchored at (`ax`, `ay`) and
// labelled with `Tag`.
fn buildPreview(
    t: pieces.tetramino,
    ax: i32,
    ay: i32,
    comptime Tag: type,
) void {
    const cs = gfx.DEFAULT_CELL_SIZE;

    const shape = t.shape[0]; // rotation 0 is fine for the preview
    const color = t.color;

    const world = ecs.getWorld();

    for (shape, 0..) |row, col_idx| {
        for (row, 0..) |cell, row_idx| {
            if (!cell) continue;

            const px = ax + (@as(i32, @intCast(col_idx)) * cs);
            const py = ay + (@as(i32, @intCast(row_idx)) * cs);

            const ent = blocks.createBlockTextureWithAtlas(
                @floatFromInt(px),
                @floatFromInt(py),
                color,
                1.0,
                0.0,
            ) catch {
                continue; // Allocation failed – skip this block
            };

            // Tag & store cell indices for later animation.
            world.add(ent, Tag{});
            world.add(ent, PreviewCell{ .col = @intCast(col_idx), .row = @intCast(row_idx) });
        }
    }
}

// Build the "next" piece preview so that it slides in from the right side of
// the screen into the fixed preview slot.
inline fn buildNextPreview(t: pieces.tetramino) void {
    // Remove any lingering preview blocks first.
    clearTag(NextPreviewTag);

    const cs = gfx.DEFAULT_CELL_SIZE;
    const ax = nextAnchorX();
    const ay = nextAnchorY();

    const shape = t.shape[0];
    const color = t.color;

    const world = ecs.getWorld();

    // Offset that positions the starting x-coordinate well outside the 640 px
    // render target so the blocks enter the screen visibly.
    const off_x = gfx.Window.OGWIDTH + cs * 2; // ≈ one block outside the edge

    const now = std.time.milliTimestamp();

    for (shape, 0..) |row, col_idx| {
        for (row, 0..) |cell, row_idx| {
            if (!cell) continue;

            const final_x = ax + (@as(i32, @intCast(col_idx)) * cs);
            const final_y = ay + (@as(i32, @intCast(row_idx)) * cs);

            // Starting position shifted off-screen to the right.
            const start_x: i32 = off_x + (@as(i32, @intCast(col_idx)) * cs);

            const ent = blocks.createBlockTextureWithAtlas(
                @floatFromInt(start_x),
                @floatFromInt(final_y),
                color,
                1.0,
                0.0,
            ) catch {
                continue;
            };

            // Attach slide-in animation.
            ecs.replace(components.Animation, ent, components.Animation{
                .animate_position = true,
                .start_pos = .{ @floatFromInt(start_x), @floatFromInt(final_y) },
                .target_pos = .{ @floatFromInt(final_x), @floatFromInt(final_y) },
                .animate_alpha = true,
                .start_alpha = 20,
                .target_alpha = color[3],
                .start_time = now,
                .duration = 120,
                .easing = .ease_out,
                .remove_when_done = true, // keep Sprite & Position, drop Animation
            });

            // Tag for later queries.
            world.add(ent, NextPreviewTag{});
            world.add(ent, PreviewCell{ .col = @intCast(col_idx), .row = @intCast(row_idx) });
        }
    }
}

inline fn buildHoldPreview(t: pieces.tetramino) void {
    clearTag(HoldPreviewTag);
    buildPreview(t, holdAnchorX(), holdAnchorY(), HoldPreviewTag);
}

// Animate all blocks tagged as NextPreviewTag into the spawn position and mark
// them for destruction once the animation ends.
fn animateNextPreviewToSpawn() void {
    const world = ecs.getWorld();
    var view = world.view(.{ NextPreviewTag, PreviewCell, components.Position }, .{});
    var it = view.entityIterator();

    const cs = gfx.DEFAULT_CELL_SIZE;
    const now = std.time.milliTimestamp();

    while (it.next()) |ent| {
        const cell = view.get(PreviewCell, ent);
        const pos = view.get(components.Position, ent);
        const tgt_x: f32 = @floatFromInt(spawnX() + cell.col * cs);
        const tgt_y: f32 = @floatFromInt(spawnY() + cell.row * cs);

        const anim = components.Animation{
            .animate_position = true,
            .start_pos = .{ pos.x, pos.y }, // current position will be used as start
            .target_pos = .{ tgt_x, tgt_y },
            .start_time = now,
            .animate_alpha = true,
            .start_alpha = 20, // Start invisible
            .target_alpha = 150, // Fade
            .duration = 120,
            .easing = .ease_out,
            .remove_when_done = true,
            .destroy_entity_when_done = true,
        };

        ecs.replace(components.Animation, ent, anim);

        // Remove the preview-specific tags so the animation components are the
        // only remaining ones – clean separation of concerns.
        world.remove(NextPreviewTag, ent);
        world.remove(PreviewCell, ent);
    }
}
