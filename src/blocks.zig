const std = @import("std");
const ray = @import("raylib.zig");
const ecs = @import("ecs.zig");
const ecsroot = @import("ecs");
const components = @import("components.zig");
const gfx = @import("gfx.zig");
const textures = @import("textures.zig");
const pieces = @import("pieces.zig");

/// Draws a rounded block with highlight into a texture tile
pub fn drawBlockIntoTile(page_tex: *const ray.RenderTexture2D, tile_x: i32, tile_y: i32, tile_size: i32, color: [4]u8) void {
    // Padding to float for drawing
    const padding = @as(f32, @floatFromInt(gfx.window.cellpadding)) * 2.0;
    const block_size = @as(f32, @floatFromInt(tile_size)) - padding * 2.0;

    const rect = ray.Rectangle{
        .x = @as(f32, @floatFromInt(tile_x)) + padding,
        .y = @as(f32, @floatFromInt(tile_y)) + padding,
        .width = block_size,
        .height = block_size,
    };

    // Rectangle (top-third of the block) for highlight
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

// Create entity for a single block
pub fn createBlockEntity(x: f32, y: f32, color: [4]u8, scale: f32, is_ghost: bool) !ecsroot.Entity {
    const entity = createBlockTextureWithAtlas(x, y, color, scale, 0.0) catch |err| {
        std.debug.print("Failed to create block entity: {}\n", .{err});
        return err;
    };

    // Add appropriate tag component
    if (is_ghost) {
        ecs.addOrReplace(components.GhostBlockTag, entity, components.GhostBlockTag{});
    } else {
        ecs.addOrReplace(components.PieceBlockTag, entity, components.PieceBlockTag{});
    }

    return entity;
}

// new entity equipped with Sprite + Texture.
pub fn createBlockTextureWithAtlas(x: f32, y: f32, color: [4]u8, scale: f32, rotation: f32) !ecsroot.Entity {
    const entity = ecs.createEntity();

    ecs.addOrReplace(components.Position, entity, components.Position{ .x = x, .y = y });
    ecs.addOrReplace(components.Sprite, entity, components.Sprite{ .rgba = color, .size = scale, .rotation = rotation });

    try addBlockTextureWithAtlas(entity, color);
    return entity;
}

// attach a Texture component to an existing entity.
pub fn addBlockTextureWithAtlas(entity: ecsroot.Entity, color: [4]u8) !void {
    // Try to get an existing entry first
    const entry = blk: {
        if (textures.getEntry(color)) |existing| {
            break :blk existing;
        } else |_| {
            // If not found, create a new entry with our drawing function
            break :blk try textures.createEntry(color, drawBlockIntoTile);
        }
    };
    
    ecs.addOrReplace(components.Texture, entity, components.Texture{
        .texture = entry.tex,
        .uv = entry.uv,
        .created = false, // shared atlas – not owned by the entity
    });
}

// Create entities for a tetris piece (either main piece or ghost)
pub fn createPieceEntities(x: i32, y: i32, shape: [4][4]bool, color: [4]u8, is_ghost: bool) void {
    const scale: f32 = 1.0;

    for (shape, 0..) |row, i| {
        for (row, 0..) |cell, j| {
            if (cell) {
                const cs_i32: i32 = gfx.window.cellsize;
                const cellX = @as(i32, @intCast(i)) * cs_i32;
                const cellY = @as(i32, @intCast(j)) * cs_i32;
                const posX = @as(f32, @floatFromInt(x + cellX));
                const posY = @as(f32, @floatFromInt(y + cellY));

                // Create entity for this block with appropriate tag
                _ = createBlockEntity(posX, posY, color, scale, is_ghost) catch |err| {
                    std.debug.print("Failed to create block entity: {}\n", .{err});
                    return;
                };
            }
        }
    }
}