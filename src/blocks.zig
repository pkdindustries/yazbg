const std = @import("std");
const ray = @import("raylib.zig");
const ecs = @import("ecs.zig");
const ecsroot = @import("ecs");
const components = @import("components.zig");
const gfx = @import("gfx.zig");
const textures = @import("textures.zig");
const pieces = @import("pieces.zig");

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
    const entry = try textures.getEntry(color);
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