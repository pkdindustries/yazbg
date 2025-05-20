// Simplified player rendering system.

const std = @import("std");
const ecs = @import("../ecs.zig");
const ecsroot = @import("ecs");
const components = @import("../components.zig");
const gfx = @import("../gfx.zig");
const pieces = @import("../pieces.zig");
const blocks = @import("../blockbuilder.zig");

inline fn cellSize() i32 {
    return gfx.window.cellsize;
}

fn getPieceBlocks() @TypeOf(ecs.getPieceBlocksView().entityIterator()) {
    var view = ecs.getPieceBlocksView();
    return view.entityIterator();
}

var last_piece_x: i32 = 0;
var last_piece_y: i32 = 0;
var last_rotation: u32 = 0;
var last_piece_index: u32 = 0;
var last_ghost_y: i32 = 0;

fn getGhostBlocks() @TypeOf(ecs.getGhostBlocksView().entityIterator()) {
    var view = ecs.getGhostBlocksView();
    return view.entityIterator();
}

pub fn init() void {
    //std.debug.print("player init\n", .{});
}

pub fn deinit() void {
    // Ensure we don't leak transient entities when the program shuts down.
    blocks.clearAllPlayerBlocks();
}

// Rebuild the active piece and its ghost at the supplied logical coordinates.
pub fn updatePlayerPosition(
    x: i32,
    y: i32,
    rotation: u32,
    ghost_y: i32,
    piece_index: u32,
) void {
    // 1. Translate logical grid coordinates to pixel coordinates (top-left
    //    corner of the piece in the off-screen 640×760 render target).
    const cs = cellSize();
    const origin_x = gfx.window.gridoffsetx + x * cs;
    const origin_y = gfx.window.gridoffsety + y * cs;

    // 2. Retrieve shape & colour of the piece to draw.
    const t = pieces.tetraminos[piece_index];
    const shape = t.shape[rotation];
    const colour = t.color;

    // 3. Destroy previously created blocks and rebuild the new configuration.
    blocks.clearAllPlayerBlocks();

    blocks.createPlayerPiece(origin_x, origin_y, shape, colour);

    // Ghost – same shape & colour but semi-transparent at landing Y.
    const ghost_origin_y = gfx.window.gridoffsety + ghost_y * cs;
    blocks.createGhostPiece(origin_x, ghost_origin_y, shape, colour);

    // Persist values for the hard-drop effect.
    last_piece_x = x;
    last_piece_y = y;
    last_rotation = rotation;
    last_piece_index = piece_index;
    last_ghost_y = ghost_y;
}

// Recreate the current piece and its ghost from the previously stored state.
// Used by the Hold event after the animation system stole the piece blocks.
pub fn redraw() void {
    updatePlayerPosition(last_piece_x, last_piece_y, last_rotation, last_ghost_y, last_piece_index);
}

// Provide the pixel-space origin (top-left) of the most recently stored piece.
pub fn lastOriginPixels() [2]f32 {
    const x_px = gfx.window.gridoffsetx + last_piece_x * cellSize();
    const y_px = gfx.window.gridoffsety + last_piece_y * cellSize();
    return .{ @floatFromInt(x_px), @floatFromInt(y_px) };
}

// Called once per frame from gfx.frame – no work is required anymore but we
// keep the stub to avoid touching unrelated code.
pub fn update() void {}

// hard-drop animation that collects current piece & ghost blocks, then
// spawns ephemeral entities that animate from the piece position to the ghost
// landing position.

pub fn harddrop() void {
    var piece_list = std.ArrayList(ecsroot.Entity).init(std.heap.wasm_allocator);
    defer piece_list.deinit();

    {
        var it = getPieceBlocks();
        while (it.next()) |e| {
            piece_list.append(e) catch {};
        }
    }

    if (piece_list.items.len == 0) return;

    const now = std.time.milliTimestamp();

    // The logical spawn row (y = 0) in pixel space.
    const spawn_origin_y = @as(f32, @floatFromInt(gfx.window.gridoffsety));

    // For every piece block currently on the board, create a transient clone
    // that starts at the spawn row and travels to its final resting place.
    for (piece_list.items) |p_ent| {
        const p_pos = ecs.get(components.Position, p_ent) orelse continue;

        // Compute the block's row offset inside the piece so we can position
        // the starting y correctly (row offset * cellSize).
        const pixel_y_i32: i32 = @as(i32, @intFromFloat(p_pos.y));
        const row_offset_pixels: i32 = @mod(pixel_y_i32 - gfx.window.gridoffsety, cellSize());
        const row_offset: f32 = @floatFromInt(row_offset_pixels);
        const start_y = spawn_origin_y + row_offset;

        var colour: [4]u8 = [_]u8{ 255, 255, 255, 255 };
        if (ecs.get(components.Sprite, p_ent)) |spr| {
            colour = spr.rgba;
        }

        const e = ecs.getWorld().create();
        ecs.getWorld().add(e, components.Position{ .x = p_pos.x, .y = start_y });
        ecs.getWorld().add(e, components.Sprite{ .rgba = colour, .size = 1.0 });
        _ = blocks.addBlockTextureWithAtlas(e, colour) catch {};

        ecs.getWorld().add(e, components.Animation{
            .animate_position = true,
            .start_pos = .{ p_pos.x, start_y },
            .target_pos = .{ p_pos.x, p_pos.y },
            .start_time = now,
            .duration = 100,
            .easing = .ease_in,
            .remove_when_done = true,
            .destroy_entity_when_done = true,
        });
    }
}
