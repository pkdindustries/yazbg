const std = @import("std");
const cells = @import("../cell.zig");
const pieces = @import("../pieces.zig");
const events = @import("../events.zig");
const ecs = @import("../ecs.zig");
const ecsroot = @import("ecs");
const components = @import("../components.zig");
const animsys = @import("anim.zig");
const textures = @import("../textures.zig");

pub fn occupyCell(gridx: usize, gridy: usize, color: [4]u8) void {
    const entity = ecs.createEntity();
    const gx: i32 = @intCast(gridx);
    const gy: i32 = @intCast(gridy);

    ecs.addOrReplace(components.GridPos, entity, components.GridPos{ .x = gx, .y = gy });
    ecs.addOrReplace(components.BlockTag, entity, components.BlockTag{});

    // Scale from grid coordinates to pixel coordinates
    const cellsize_f32: f32 = 35.0; // Using default cell size, could be made configurable
    const px = @as(f32, @floatFromInt(gridx)) * cellsize_f32;
    const py = @as(f32, @floatFromInt(gridy)) * cellsize_f32;

    ecs.addOrReplace(components.Position, entity, components.Position{ .x = px, .y = py });
    ecs.addOrReplace(components.Sprite, entity, components.Sprite{ .rgba = color, .size = 1.0 });
    _ = textures.addBlockTextureWithAtlas(entity, color) catch |err| {
        std.debug.print("Failed to add texture component: {}\n", .{err});
        return;
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

    animsys.createRippledFallingRow(line, buffer[0..count]);
    // Original entities should be destroyed immediately
    for (buffer[0..count]) |entity| {
        ecs.getWorld().destroy(entity);
    }
}

pub fn shiftRowCells(line: usize) void {
    // Sshift all entities in this line down
    var blocks_view = ecs.getBlocksView();

    var buffer: [10]ecsroot.Entity = undefined;
    var pbuffer: [10]components.Position = undefined;
    var gbuffer: [10]components.GridPos = undefined;
    var count: usize = 0;

    // Collect entities to update
    var iter = blocks_view.entityIterator();
    while (iter.next()) |entity| {
        if (ecs.get(components.GridPos, entity)) |grid_pos| {
            if (grid_pos.y == @as(i32, @intCast(line))) {
                if (count < buffer.len) {
                    // Store entity
                    buffer[count] = entity;

                    // Store position
                    if (ecs.get(components.Position, entity)) |pos| {
                        pbuffer[count] = pos;
                    } else {
                        // If no position component, use default (unlikely)
                        const cellsize_f32: f32 = 35.0;
                        const px = @as(f32, @floatFromInt(grid_pos.x)) * cellsize_f32;
                        const py = @as(f32, @floatFromInt(grid_pos.y)) * cellsize_f32;
                        pbuffer[count] = .{ .x = px, .y = py };
                    }

                    // Store grid position
                    gbuffer[count] = grid_pos;

                    count += 1;
                }
            }
        }
    }

    // Update all collected entities
    for (0..count) |idx| {
        const entity = buffer[idx];
        const cellsize_f32: f32 = 35.0;
        var pos = pbuffer[idx];
        var grid_pos = gbuffer[idx];

        // Store the original position for animation
        const start_pos_y = pos.y;
        const target_pos_y = start_pos_y + cellsize_f32;

        // Remove old components
        ecs.getWorld().remove(components.GridPos, entity);
        ecs.getWorld().remove(components.Position, entity);

        // Add updated components (logical update happens immediately)
        grid_pos.y += 1;
        ecs.addOrReplace(components.GridPos, entity, grid_pos);

        // Position is updated for glame logic
        pos.y = target_pos_y;
        ecs.addOrReplace(components.Position, entity, pos);

        // Add animation component
        animsys.createRowShiftAnimation(entity, start_pos_y, target_pos_y);
    }
}
