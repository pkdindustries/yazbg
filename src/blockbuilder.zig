const std = @import("std");

// External modules -----------------------------------------------------------

const ray = @import("raylib.zig");
const ecs = @import("ecs.zig");
const ecsroot = @import("ecs");
const components = @import("components.zig");
const gfx = @import("gfx.zig");
const textures = @import("textures.zig");

pub const Color = textures.Color;
pub const UV = textures.UV;
pub const AtlasEntry = textures.AtlasEntry;

// -----------------------------------
// Attach a shared block texture (looked up or generated on demand via the
// global texture atlas) to an existing entity.
pub fn addBlockTextureWithAtlas(entity: ecsroot.Entity, color: Color) !void {
    const entry = try getOrCreateBlockTexture(color);

    ecs.replace(components.Texture, entity, components.Texture{
        .texture = entry.tex,
        .uv = entry.uv,
        .created = false, // Shared atlas – not owned by this entity.
    });
}

// Generic low-level helper: spawn a block at (x,y) tinted `rgba` and tagged
// with `Tag` (PieceBlockTag, GhostBlockTag, …).
fn spawnBlock(x: f32, y: f32, rgba: Color, comptime Tag: type) !ecsroot.Entity {
    const e = ecs.createEntity();

    ecs.replace(components.Position, e, components.Position{ .x = x, .y = y });
    ecs.replace(components.Sprite, e, components.Sprite{ .rgba = rgba, .size = 1.0 });

    try addBlockTextureWithAtlas(e, rgba);
    ecs.replace(Tag, e, Tag{});

    return e;
}

// ---------------------------------------------------------------------------
// Public helpers used by other systems
// ---------------------------------------------------------------------------

// Spawn a textured block without adding any marker tag.  Still used by the
// HUD preview system that adds its own specialised tags afterwards.
pub fn createBlockTextureWithAtlas(
    x: f32,
    y: f32,
    color: Color,
    scale: f32,
    rotation: f32,
) !ecsroot.Entity {
    const e = ecs.createEntity();

    ecs.replace(components.Position, e, components.Position{ .x = x, .y = y });
    ecs.replace(components.Sprite, e, components.Sprite{ .rgba = color, .size = scale, .rotation = rotation });
    try addBlockTextureWithAtlas(e, color);

    return e;
}

// Build a tetramino shape either as active piece or ghost.
fn buildPieceEntities(
    x: i32,
    y: i32,
    shape: [4][4]bool,
    color: Color,
    is_ghost: bool,
) void {
    const cs: i32 = gfx.window.cellsize;

    for (shape, 0..) |row, col_idx| {
        for (row, 0..) |cell, row_idx| {
            if (!cell) continue;

            const px: f32 = @floatFromInt(x + @as(i32, @intCast(col_idx)) * cs);
            const py: f32 = @floatFromInt(y + @as(i32, @intCast(row_idx)) * cs);

            if (is_ghost) {
                _ = spawnBlock(px, py, color, components.GhostBlockTag) catch {};
            } else {
                _ = spawnBlock(px, py, color, components.PieceBlockTag) catch {};
            }
        }
    }
}

pub inline fn createPlayerPiece(x: i32, y: i32, shape: [4][4]bool, color: Color) void {
    buildPieceEntities(x, y, shape, color, false);
}

pub inline fn createGhostPiece(x: i32, y: i32, shape: [4][4]bool, color: Color) void {
    var ghost = color;
    ghost[3] = 150; // Semi-transparent
    buildPieceEntities(x, y, shape, ghost, true);
}

// ---------------------------------------------------------------------------
// Clearing helpers – keep tiny & generic
// ---------------------------------------------------------------------------

inline fn destroyWithTag(comptime Tag: type) void {
    var view = ecs.getWorld().view(.{Tag}, .{});
    var it = view.entityIterator();
    while (it.next()) |e| ecs.destroyEntity(e);
}

pub fn clearAllPlayerBlocks() void {
    destroyWithTag(components.PieceBlockTag);
    destroyWithTag(components.GhostBlockTag);
}

// Flashing block (row-clear effect) – unchanged except for internal helper
// reuse.
pub fn createFlashingBlock(x: f32, y: f32, color: Color) !ecsroot.Entity {
    const e = try createBlockTextureWithAtlas(x, y, color, 1.0, 0.0);

    ecs.replace(components.Animation, e, components.Animation{
        .animate_scale = true,
        .start_scale = 1.0,
        .target_scale = 1.3,
        .start_time = std.time.milliTimestamp(),
        .duration = 500,
        .easing = .ease_in_out,
        .loop = true,
        .ping_pong = true,
        .remove_when_done = false,
    });

    return e;
}

// ---------------------------------------------------------------------------
// Texture-atlas integration (unchanged from original implementation)
// ---------------------------------------------------------------------------

// Return an existing atlas entry or create it by rendering the block shape
// into an empty atlas tile.
pub fn getOrCreateBlockTexture(color: Color) !AtlasEntry {
    var buf: [64]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "block_{d}_{d}_{d}_{d}", .{ color[0], color[1], color[2], color[3] }) catch {
        return error.KeyFormatError;
    };

    // Fast path – already cached.
    if (textures.getEntry(key)) |entry| {
        return entry;
    } else |err| {
        if (err != error.EntryNotFound) return err;
    }

    // Need to create – duplicate the key to heap memory because the atlas owns
    // the string for the duration of the program.
    const heap_key = try std.heap.c_allocator.dupe(u8, key);

    var colour_copy = color; // draw fn expects pointer
    return textures.createEntry(heap_key, drawBlockIntoTile, &colour_copy);
}

// Draw a single rounded rectangle into the atlas tile – identical visual
// output to the previous implementation so no one notices the refactor.
pub fn drawBlockIntoTile(
    page_tex: *const ray.RenderTexture2D,
    tile_x: i32,
    tile_y: i32,
    tile_size: i32,
    _: []const u8,
    context: ?*const anyopaque,
) void {
    const padding: f32 = @as(f32, @floatFromInt(gfx.window.cellpadding)) * 2.0;
    const block_size = @as(f32, @floatFromInt(tile_size)) - padding * 2.0;

    const rect = ray.Rectangle{
        .x = @as(f32, @floatFromInt(tile_x)) + padding,
        .y = @as(f32, @floatFromInt(tile_y)) + padding,
        .width = block_size,
        .height = block_size,
    };

    const clr_ptr = @as(*const Color, @ptrCast(context.?));
    const ray_color = gfx.toRayColor(clr_ptr.*);

    ray.BeginTextureMode(page_tex.*);
    ray.DrawRectangleRounded(rect, 0.4, 20, ray_color);
    ray.EndTextureMode();
}
