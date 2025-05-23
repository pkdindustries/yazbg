const std = @import("std");
const cells = @import("../cell.zig");
const pieces = @import("../pieces.zig");
const events = @import("../events.zig");
const ecs = @import("../ecs.zig");
const ecsroot = @import("ecs");
const components = @import("../components.zig");
const animsys = @import("anim.zig");
const shaders = @import("../shaders.zig");
const gfx = @import("../gfx.zig");
const textures = @import("../textures.zig");
const blocks = @import("../blockbuilder.zig");
const game_constants = @import("../game_constants.zig");

pub fn occupyCell(gridx: usize, gridy: usize, color: [4]u8) void {
    const entity = ecs.createEntity();
    const gx: i32 = @intCast(gridx);
    const gy: i32 = @intCast(gridy);

    ecs.replace(components.GridPos, entity, components.GridPos{ .x = gx, .y = gy });
    ecs.replace(components.BlockTag, entity, components.BlockTag{});

    // Translate logical grid coordinates into absolute pixel positions (top-left).
    const cellsize_f32: f32 = @as(f32, @floatFromInt(game_constants.CELL_SIZE));
    const px = @as(f32, @floatFromInt(game_constants.GRID_OFFSET_X)) + @as(f32, @floatFromInt(gridx)) * cellsize_f32;
    const py = @as(f32, @floatFromInt(game_constants.GRID_OFFSET_Y)) + @as(f32, @floatFromInt(gridy)) * cellsize_f32;

    ecs.replace(components.Position, entity, components.Position{ .x = px, .y = py });
    ecs.replace(components.Sprite, entity, components.Sprite{ .rgba = color, .size = 1.0 });
    _ = blocks.addBlockTextureWithAtlas(entity, color) catch |err| {
        std.debug.print("Failed to add texture component: {}\n", .{err});
        return;
    };

    // Add static shader to the occupied block
    shaders.addShaderToEntity(entity, "static") catch |err| {
        std.debug.print("Failed to add static shader: {}\n", .{err});
    };

    const ttl_ms: i64 = 350;
    animsys.createFlashAnimation(entity, 255, 0, ttl_ms);
}

pub fn vacateCell(gridy: i32, gridx: i32) void {
    // Find and remove entity at this position
    var blocks_view = ecs.getBlocksView();
    var iter = blocks_view.entityIterator();
    var found_entity: ?ecsroot.Entity = null;

    while (iter.next()) |entity| {
        if (ecs.get(components.GridPos, entity)) |grid_pos| {
            if (grid_pos.x == gridx and grid_pos.y == gridy) {
                found_entity = entity;
                break;
            }
        }
    }

    if (found_entity) |entity| {
        ecs.getWorld().destroy(entity);
    }
}

pub fn clearAllCells() void {
    // Remove all block entities
    var blocks_view = ecs.getBlocksView();

    // We know the maximum entities is WIDTH*HEIGHT (from grid.zig)
    var buffer: [10 * 20]ecsroot.Entity = undefined;
    var count: usize = 0;

    // Collect entities to destroy (can't modify while iterating)
    var iter = blocks_view.entityIterator();
    while (iter.next()) |entity| {
        if (count < buffer.len) {
            buffer[count] = entity;
            count += 1;
        }
    }

    // Destroy all collected entities
    for (buffer[0..count]) |entity| {
        ecs.getWorld().destroy(entity);
    }
}

pub fn removeLineCells(line: usize) void {
    // get blocks in this line
    var blocks_view = ecs.getBlocksView();

    var buffer: [10]ecsroot.Entity = undefined;
    var count: usize = 0;

    var iter = blocks_view.entityIterator();
    while (iter.next()) |entity| {
        if (ecs.get(components.GridPos, entity)) |grid_pos| {
            if (grid_pos.y == @as(i32, @intCast(line))) {
                if (count < buffer.len) {
                    buffer[count] = entity;
                    count += 1;
                }
            }
        }
    }

    // detach the cleared-line blocks from the logical grid
    for (buffer[0..count]) |entity| {
        ecs.getWorld().remove(components.GridPos, entity);
        ecs.getWorld().remove(components.BlockTag, entity);
    }

    // these self destruct
    animsys.createRippledFallingRow(line, buffer[0..count]);
}

var shiftbuffer: [10]ecsroot.Entity = undefined;
var shiftpbuffer: [10]components.Position = undefined;
var shiftgbuffer: [10]components.GridPos = undefined;
pub fn shiftRowCells(line: usize) void {
    // Sshift all entities in this line down
    var blocks_view = ecs.getBlocksView();

    var count: usize = 0;

    // Collect entities to update
    var iter = blocks_view.entityIterator();
    while (iter.next()) |entity| {
        if (ecs.get(components.GridPos, entity)) |grid_pos| {
            if (grid_pos.y == @as(i32, @intCast(line))) {
                if (count < shiftbuffer.len) {
                    // Store entity
                    shiftbuffer[count] = entity;

                    // Store position
                    if (ecs.get(components.Position, entity)) |pos| {
                        shiftpbuffer[count] = pos;
                    } else {
                        // If no position component, use default (unlikely)
                        const cellsize_f32: f32 = @as(f32, @floatFromInt(game_constants.CELL_SIZE));
                        const px = @as(f32, @floatFromInt(game_constants.GRID_OFFSET_X)) + @as(f32, @floatFromInt(grid_pos.x)) * cellsize_f32;
                        const py = @as(f32, @floatFromInt(game_constants.GRID_OFFSET_Y)) + @as(f32, @floatFromInt(grid_pos.y)) * cellsize_f32;
                        shiftpbuffer[count] = .{ .x = px, .y = py };
                    }

                    // Store grid position
                    shiftgbuffer[count] = grid_pos;

                    count += 1;
                }
            }
        }
    }

    // Update all collected entities
    for (0..count) |idx| {
        const entity = shiftbuffer[idx];
        const cellsize_f32: f32 = @as(f32, @floatFromInt(game_constants.CELL_SIZE));
        var pos = shiftpbuffer[idx];
        var grid_pos = shiftgbuffer[idx];

        // Store the original position for animation
        const start_pos_y = pos.y;
        const target_pos_y = start_pos_y + cellsize_f32;

        // Remove old components
        ecs.getWorld().remove(components.GridPos, entity);
        ecs.getWorld().remove(components.Position, entity);

        // Add updated components (logical update happens immediately)
        grid_pos.y += 1;
        ecs.replace(components.GridPos, entity, grid_pos);

        pos.y = target_pos_y;
        ecs.replace(components.Position, entity, pos);

        // Add animation component
        animsys.createRowShiftAnimation(entity, start_pos_y, target_pos_y);
    }
}
