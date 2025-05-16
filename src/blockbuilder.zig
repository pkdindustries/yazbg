const std = @import("std");

const ray = @import("raylib.zig");
const ecs = @import("ecs.zig");
const ecsroot = @import("ecs");
const components = @import("components.zig");
const gfx = @import("gfx.zig");
const textures = @import("textures.zig");
const pieces = @import("pieces.zig");

// type aliases
pub const Color = textures.Color;
pub const UV = textures.UV;
pub const AtlasEntry = textures.AtlasEntry;

// helper to convert color to string key for texture lookup
fn colorToKey(allocator: std.mem.Allocator, color: Color) ![]u8 {
    return try std.fmt.allocPrint(allocator, "block_{d}_{d}_{d}_{d}", .{ color[0], color[1], color[2], color[3] });
}

//-----------------------------------------------------------------------------
// texture handling functions
//-----------------------------------------------------------------------------

// get an existing block texture or create a new one if it doesn't exist
pub fn getOrCreateBlockTexture(color: Color) !AtlasEntry {
    const alloc = std.heap.c_allocator;

    // First, format the key into a small stack buffer (fast path).
    var buffer: [64]u8 = undefined;
    const tmp_key = std.fmt.bufPrint(&buffer, "block_{d}_{d}_{d}_{d}", .{ color[0], color[1], color[2], color[3] }) catch |err| {
        std.debug.print("Failed to format color key: {}", .{err});
        return error.KeyFormatError;
    };

    // If an entry already exists, we can immediately return it – no allocation
    // needed in this case because the map owns its own (heap-allocated) key.
    const entry_try = textures.getEntry(tmp_key);
    if (entry_try) |existing| {
        return existing;
    } else |err| {
        // Only continue when the entry was not found. Propagate any other error
        // back to the caller.
        switch (err) {
            error.EntryNotFound => {},
            else => return err,
        }
    }

    // Otherwise we need to create a new atlas entry. The hash-map stores a
    // reference to the provided key slice, so we must ensure that the memory
    // for the key lives for the duration of the program.  Allocate a copy of
    // the formatted key on the heap and pass that to the textures module.
    const heap_key = try alloc.dupe(u8, tmp_key);

    // Draw-time needs access to the block colour, but only during the call, so
    // a stack copy is sufficient.
    var color_copy = color;
    return try textures.createEntry(heap_key, drawBlockIntoTile, &color_copy);
}

// draws a rounded block with highlight into a texture tile
pub fn drawBlockIntoTile(page_tex: *const ray.RenderTexture2D, tile_x: i32, tile_y: i32, tile_size: i32, _: []const u8, context: ?*const anyopaque) void {
    // padding to float for drawing
    const padding = @as(f32, @floatFromInt(gfx.window.cellpadding)) * 2.0;
    const block_size = @as(f32, @floatFromInt(tile_size)) - padding * 2.0;

    const rect = ray.Rectangle{
        .x = @as(f32, @floatFromInt(tile_x)) + padding,
        .y = @as(f32, @floatFromInt(tile_y)) + padding,
        .width = block_size,
        .height = block_size,
    };

    // rectangle (top-third of the block) for highlight
    const highlight_rect = ray.Rectangle{
        .x = rect.x + 2,
        .y = rect.y + 2,
        .width = rect.width - 4,
        .height = rect.height / 3,
    };

    // context must be a pointer to Color
    const color = @as(*const Color, @ptrCast(context.?)).*;
    const ray_color = gfx.toRayColor(color);
    const light_color = gfx.createLighterColor(color, 20);

    ray.BeginTextureMode(page_tex.*);
    ray.DrawRectangleRounded(highlight_rect, 0.4, 8, light_color);
    ray.DrawRectangleRounded(rect, 0.4, 20, ray_color);
    ray.EndTextureMode();
}

//-----------------------------------------------------------------------------
// entity creation helpers
//-----------------------------------------------------------------------------

// attach a texture component to an existing entity
pub fn addBlockTextureWithAtlas(entity: ecsroot.Entity, color: Color) !void {
    // get or create texture entry for this color
    const entry = try getOrCreateBlockTexture(color);

    ecs.replace(components.Texture, entity, components.Texture{
        .texture = entry.tex,
        .uv = entry.uv,
        .created = false, // shared atlas - not owned by the entity
    });
}

// create new entity equipped with sprite + texture
pub fn createBlockTextureWithAtlas(x: f32, y: f32, color: Color, scale: f32, rotation: f32) !ecsroot.Entity {
    const entity = ecs.createEntity();

    ecs.replace(components.Position, entity, components.Position{ .x = x, .y = y });
    ecs.replace(components.Sprite, entity, components.Sprite{ .rgba = color, .size = scale, .rotation = rotation });

    try addBlockTextureWithAtlas(entity, color);
    return entity;
}

// create entity for a single block
pub fn createBlockEntity(x: f32, y: f32, color: Color, scale: f32, is_ghost: bool) !ecsroot.Entity {
    const entity = try createBlockTextureWithAtlas(x, y, color, scale, 0.0);

    // add appropriate tag component
    if (is_ghost) {
        ecs.replace(components.GhostBlockTag, entity, components.GhostBlockTag{});
    } else {
        ecs.replace(components.PieceBlockTag, entity, components.PieceBlockTag{});
    }

    return entity;
}

// create a ghost block (semi-transparent preview at landing position)
pub fn createGhostBlock(x: f32, y: f32, color: Color) !ecsroot.Entity {
    // create semi-transparent version of the color
    var ghost_color = color;
    ghost_color[3] = 200; // reduce alpha for ghost effect

    return createBlockEntity(x, y, ghost_color, 1.0, true);
}

//-----------------------------------------------------------------------------
// piece creation functions
//-----------------------------------------------------------------------------

// create entities for a tetris piece (either main piece or ghost)
pub fn createPieceEntities(x: i32, y: i32, shape: [4][4]bool, color: Color, is_ghost: bool) void {
    const cs_i32: i32 = gfx.window.cellsize;
    const scale: f32 = 1.0;

    for (shape, 0..) |row, i| {
        for (row, 0..) |cell, j| {
            if (!cell) continue;

            const cellX = @as(i32, @intCast(i)) * cs_i32;
            const cellY = @as(i32, @intCast(j)) * cs_i32;
            const posX = @as(f32, @floatFromInt(x + cellX));
            const posY = @as(f32, @floatFromInt(y + cellY));

            // create entity for this block with appropriate tag
            _ = createBlockEntity(posX, posY, color, scale, is_ghost) catch {
                std.debug.print("failed to create block entity at position ({d}, {d})\n", .{ i, j });
                continue;
            };
        }
    }
}

// create the player's active piece
pub fn createPlayerPiece(x: i32, y: i32, shape: [4][4]bool, color: Color) void {
    // create main piece blocks
    createPieceEntities(x, y, shape, color, false);
}

// create a collection of ghost blocks based on a piece shape
pub fn createGhostPiece(x: i32, y: i32, shape: [4][4]bool, color: Color) void {
    // create semi-transparent version of the color
    var ghost_color = color;
    ghost_color[3] = 150; // semi-transparent

    createPieceEntities(x, y, shape, ghost_color, true);
}

//-----------------------------------------------------------------------------
// block clearing functions
//-----------------------------------------------------------------------------

// clear all piece blocks (active player piece)
pub fn clearPieceBlocks() void {
    var view = ecs.getPieceBlocksView();
    var it = view.entityIterator();
    while (it.next()) |entity| {
        ecs.getWorld().destroy(entity);
    }
}

// clear all ghost blocks (landing preview)
pub fn clearGhostBlocks() void {
    var view = ecs.getGhostBlocksView();
    var it = view.entityIterator();
    while (it.next()) |entity| {
        ecs.getWorld().destroy(entity);
    }
}

// clear both piece and ghost blocks
pub fn clearAllPlayerBlocks() void {
    clearPieceBlocks();
    clearGhostBlocks();
}

// create a flashing block animation (for row clear effects, etc.)
pub fn createFlashingBlock(x: f32, y: f32, color: Color) !ecsroot.Entity {
    const entity = try createBlockTextureWithAtlas(x, y, color, 1.0, 0.0);

    // add animation component for pulsing/flashing effect
    ecs.replace(components.Animation, entity, components.Animation{
        .animate_scale = true,
        .start_scale = 1.0,
        .target_scale = 1.3,
        .start_time = std.time.milliTimestamp(),
        .duration = 500, // half-second animation
        .easing = .ease_in_out,
        .loop = true, // make it loop
        .ping_pong = true, // scale up and down
        .remove_when_done = false,
    });

    return entity;
}
