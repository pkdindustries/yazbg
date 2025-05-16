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

//-----------------------------------------------------------------------------
// texture handling functions
//-----------------------------------------------------------------------------

// get an existing block texture or create a new one if it doesn't exist
pub fn getOrCreateBlockTexture(color: Color) !AtlasEntry {
    return blk: {
        if (textures.getEntry(color)) |existing| {
            break :blk existing;
        } else |_| {
            break :blk try textures.createEntry(color, drawBlockIntoTile);
        }
    };
}

// draws a rounded block with highlight into a texture tile
pub fn drawBlockIntoTile(page_tex: *const ray.RenderTexture2D, tile_x: i32, tile_y: i32, tile_size: i32, color: Color) void {
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
    ghost_color[3] = 120; // reduce alpha for ghost effect

    return createBlockEntity(x, y, ghost_color, 1.0, true);
}

// create a grid block (fixed block in the game grid)
pub fn createGridBlock(grid_x: i32, grid_y: i32, color: Color) !ecsroot.Entity {
    // convert grid coordinates to screen coordinates
    const cs = @as(f32, @floatFromInt(gfx.window.cellsize));
    const x = @as(f32, @floatFromInt(gfx.window.gridoffsetx)) + @as(f32, @floatFromInt(grid_x)) * cs;
    const y = @as(f32, @floatFromInt(gfx.window.gridoffsety)) + @as(f32, @floatFromInt(grid_y)) * cs;

    // create block entity
    const entity = try createBlockEntity(x, y, color, 1.0, false);

    // add grid position component
    ecs.replace(components.BlockTag, entity, components.BlockTag{});
    ecs.replace(components.GridPos, entity, components.GridPos{ .x = grid_x, .y = grid_y });

    return entity;
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

//-----------------------------------------------------------------------------
// animation functions
//-----------------------------------------------------------------------------

// move a block entity to a new position with optional animation
pub fn moveBlock(entity: ecsroot.Entity, x: f32, y: f32, animate: bool, duration_ms: i32) !void {
    // get current position
    const current_pos = ecs.get(components.Position, entity) orelse {
        std.debug.print("failed to move block: entity has no position component\n", .{});
        return error.MissingPosition;
    };

    if (animate) {
        // create animation component
        ecs.replace(components.Animation, entity, components.Animation{
            .animate_position = true,
            .start_pos = .{ current_pos.x, current_pos.y },
            .target_pos = .{ x, y },
            .start_time = std.time.milliTimestamp(),
            .duration = duration_ms,
            .easing = .ease_out,
            .remove_when_done = true,
            .destroy_entity_when_done = false,
        });
    } else {
        // update position immediately
        ecs.replace(components.Position, entity, components.Position{
            .x = x,
            .y = y,
        });
    }
}

// create an entity that animates from one position to another and then destroys itself
pub fn createBlockDropAnimation(from_x: f32, from_y: f32, to_y: f32, color: Color) !ecsroot.Entity {
    var anim_color = color;
    anim_color[3] = 100; // very transparent

    const entity = try createBlockTextureWithAtlas(from_x, from_y, anim_color, 1.0, 0.0);

    // add animation component
    ecs.replace(components.Animation, entity, components.Animation{
        .animate_position = true,
        .start_pos = .{ from_x, from_y },
        .target_pos = .{ from_x, to_y },
        .start_time = std.time.milliTimestamp(),
        .duration = 100, // fast animation (100ms)
        .easing = .ease_in,
        .remove_when_done = true,
        .destroy_entity_when_done = true,
    });

    return entity;
}

// create a hard drop animation from source entity to a destination y position
pub fn createHardDropAnimation(entity: ecsroot.Entity, to_y: f32) !ecsroot.Entity {
    const pos = ecs.get(components.Position, entity) orelse return error.MissingPosition;
    const sprite = ecs.get(components.Sprite, entity) orelse return error.MissingSprite;

    return createBlockDropAnimation(pos.x, pos.y, to_y, sprite.rgba);
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
