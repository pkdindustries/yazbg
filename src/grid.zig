const std = @import("std");
const cells = @import("cell.zig");
const CellData = cells.CellData;
const pieces = @import("pieces.zig");
const events = @import("events.zig");
const ecs = @import("ecs.zig");
const ecsroot = @import("ecs");
const components = @import("components.zig");
//const entity_traits = @import("ecs").entity_traits;

pub const Grid = struct {
    const Self = @This();
    pub const WIDTH = 10;
    pub const HEIGHT = 20;

    pub fn init() Self {
        return Self{};
    }

    pub fn isOccupied(self: *const Self, x: usize, y: usize) bool {
        _ = self; // Unused parameter
        if (x >= WIDTH or y >= HEIGHT) return false;

        // Check ECS entities
        var blocks_view = ecs.getBlocksView();
        var iter = blocks_view.entityIterator();

        while (iter.next()) |entity| {
            if (ecs.getGridPos(entity)) |grid_pos| {
                if (grid_pos.x == @as(i32, @intCast(x)) and grid_pos.y == @as(i32, @intCast(y))) {
                    return true;
                }
            }
        }

        return false;
    }

    pub fn occupy(_: *Self, gridx: usize, gridy: usize, color: [4]u8) void {
        const entity = ecs.createEntity();
        const gx: i32 = @intCast(gridx);
        const gy: i32 = @intCast(gridy);
        ecs.addGridPos(entity, gx, gy);
        ecs.addBlockTag(entity);

        // Scale from grid coordinates to pixel coordinates
        const cellsize_f32: f32 = 35.0; // Using default cell size, could be made configurable
        const px = @as(f32, @floatFromInt(gridx)) * cellsize_f32;
        const py = @as(f32, @floatFromInt(gridy)) * cellsize_f32;

        ecs.addPosition(entity, px, py);
        ecs.addSprite(entity, color, 1.0);
        ecs.addFlash(entity, 200); // Flash duration in milliseconds
    }

    pub fn vacate(self: *Self, gridy: i32, gridx: i32) void {
        _ = self; // Unused parameter
        if (gridx >= WIDTH or gridy >= HEIGHT) return;

        // Find and remove entity at this position
        var blocks_view = ecs.getBlocksView();
        var iter = blocks_view.entityIterator();
        var found_entity: ?ecsroot.Entity = null;

        while (iter.next()) |entity| {
            if (ecs.getGridPos(entity)) |grid_pos| {
                if (grid_pos.x == @as(i32, @intCast(gridx)) and grid_pos.y == @as(i32, @intCast(gridy))) {
                    found_entity = entity;
                    break;
                }
            }
        }

        if (found_entity) |entity| {
            ecs.getWorld().destroy(entity);
        }
    }

    pub fn clearall(self: *Self) void {
        _ = self; // Unused parameter

        // Remove all block entities
        var blocks_view = ecs.getBlocksView();
        var entities = std.ArrayList(ecsroot.Entity).init(std.heap.c_allocator);
        defer entities.deinit();

        // Collect entities to destroy (can't modify while iterating)
        var iter = blocks_view.entityIterator();
        while (iter.next()) |entity| {
            entities.append(entity) catch continue;
        }

        // Destroy all collected entities
        for (entities.items) |entity| {
            ecs.getWorld().destroy(entity);
        }
    }

    fn removeline(self: *Self, line: usize) void {
        _ = self; // Unused parameter
        std.debug.print("removeline {d}\n", .{line});

        // Emit LineClearing event before modifying the grid
        events.push(.{ .LineClearing = .{ .y = line } }, events.Source.Game);

        // Remove all entities in this line
        var blocks_view = ecs.getBlocksView();
        var entities = std.ArrayList(ecsroot.Entity).init(std.heap.c_allocator);
        defer entities.deinit();

        // Collect entities to destroy
        var iter = blocks_view.entityIterator();
        while (iter.next()) |entity| {
            if (ecs.getGridPos(entity)) |grid_pos| {
                if (grid_pos.y == @as(i32, @intCast(line))) {
                    entities.append(entity) catch continue;
                }
            }
        }

        // Destroy all collected entities
        for (entities.items) |entity| {
            ecs.getWorld().destroy(entity);
        }
    }

    // shift a single line down
    fn shiftrow(self: *Self, line: usize) void {
        _ = self; // Unused parameter

        // Check if the line is within bounds
        if (line >= HEIGHT - 1) {
            return; // Cannot shift the last row down
        }

        // Emit RowsShiftedDown event before modifying the grid
        events.push(.{ .RowsShiftedDown = .{ .start_y = line, .count = 1 } }, events.Source.Game);

        // Shift all entities in this line down
        var blocks_view = ecs.getBlocksView();
        var entities_to_update = std.ArrayList(ecsroot.Entity).init(std.heap.c_allocator);
        var positions_to_update = std.ArrayList(components.Position).init(std.heap.c_allocator);
        var grid_positions_to_update = std.ArrayList(components.GridPos).init(std.heap.c_allocator);
        defer entities_to_update.deinit();
        defer positions_to_update.deinit();
        defer grid_positions_to_update.deinit();

        // Collect entities to update
        var iter = blocks_view.entityIterator();
        while (iter.next()) |entity| {
            if (ecs.getGridPos(entity)) |grid_pos| {
                if (grid_pos.y == @as(i32, @intCast(line))) {
                    // Store entity and its positions
                    entities_to_update.append(entity) catch continue;

                    if (ecs.getPosition(entity)) |pos| {
                        positions_to_update.append(pos) catch continue;
                    } else {
                        // If no position component, use default (unlikely)
                        const cellsize_f32: f32 = 35.0;
                        const px = @as(f32, @floatFromInt(grid_pos.x)) * cellsize_f32;
                        const py = @as(f32, @floatFromInt(grid_pos.y)) * cellsize_f32;
                        positions_to_update.append(.{ .x = px, .y = py }) catch continue;
                    }

                    grid_positions_to_update.append(grid_pos) catch continue;
                }
            }
        }

        // Update all collected entities
        for (entities_to_update.items, 0..) |entity, idx| {
            // Remove old components
            ecs.getWorld().remove(components.GridPos, entity);
            ecs.getWorld().remove(components.Position, entity);

            // Add updated components
            var grid_pos = grid_positions_to_update.items[idx];
            grid_pos.y += 1;
            ecs.addGridPos(entity, grid_pos.x, grid_pos.y);

            var pos = positions_to_update.items[idx];
            const cellsize_f32: f32 = 35.0;
            pos.y += cellsize_f32;
            ecs.addPosition(entity, pos.x, pos.y);
        }
    }

    pub fn clear(self: *Self) u8 {
        var line: u8 = HEIGHT - 1;
        var count: u8 = 0;
        while (line > 0) {
            if (self.checkline(line)) {
                self.removeline(line);
                count += 1;
                // Shift all rows above down by one
                var shift_line = line;
                while (shift_line > 0) {
                    self.shiftrow(shift_line - 1);
                    shift_line -= 1;
                }
            } else {
                line -= 1;
            }
        }
        return count;
    }

    pub fn print(self: *const Self) void {
        std.debug.print("\n", .{});
        for (0..HEIGHT) |y| {
            for (0..WIDTH) |x| {
                if (self.isOccupied(x, y)) {
                    std.debug.print("+", .{});
                } else {
                    std.debug.print("-", .{});
                }
            }
            std.debug.print("\n", .{});
        }
    }

    pub fn checkline(self: *const Self, y: usize) bool {
        if (y >= HEIGHT) return false;

        for (0..WIDTH) |x| {
            if (!self.isOccupied(x, y)) {
                return false;
            }
        }
        return true;
    }

    pub fn checkmove(self: *const Self, piece: ?pieces.tetramino, x: i32, y: i32, r: u32) bool {
        if (piece) |p| {
            const shape = p.shape[r];
            for (shape, 0..) |row, j| {
                for (row, 0..) |cell, i| {
                    if (cell) {
                        const gx = x + @as(i32, @intCast(j));
                        const gy = y + @as(i32, @intCast(i));

                        // Cell is out of bounds
                        if (gx < 0 or gx >= WIDTH or gy < 0 or gy >= HEIGHT) {
                            return false;
                        }

                        const ix = @as(usize, @intCast(gx));
                        const iy = @as(usize, @intCast(gy));

                        // Cell is already occupied
                        if (self.isOccupied(ix, iy)) {
                            return false;
                        }
                    }
                }
            }
        }
        return true;
    }
};

test "grid init" {
    // Initialize ECS world for testing
    ecs.init();
    defer ecs.deinit();

    var grid = Grid.init();

    // Test that grid is empty
    for (0..Grid.HEIGHT) |y| {
        for (0..Grid.WIDTH) |x| {
            try std.testing.expect(!grid.isOccupied(x, y));
        }
    }

    // Test occupation
    grid.occupy(0, 0, .{ 255, 255, 255, 255 });
    try std.testing.expect(grid.isOccupied(0, 0));

    // Test vacate
    grid.vacate(0, 0);
    try std.testing.expect(!grid.isOccupied(0, 0));
}

test "check line" {
    // Initialize ECS world for testing
    ecs.init();
    defer ecs.deinit();

    var grid = Grid.init();

    // Fill a row
    for (0..Grid.WIDTH) |x| {
        grid.occupy(5, x, .{ 255, 255, 255, 255 });
    }

    try std.testing.expect(grid.checkline(5));
    try std.testing.expect(!grid.checkline(0));

    // Clear grid
    grid.clearall();
    try std.testing.expect(!grid.checkline(5));
}

test "rm" {
    std.debug.print("rm\n", .{});

    // Initialize ECS world for testing
    ecs.init();
    defer ecs.deinit();

    var grid = Grid.init();

    // fill line 0
    for (0..Grid.WIDTH) |i| {
        grid.occupy(0, i, .{ 255, 255, 255, 255 });
    }

    grid.print();
    grid.removeline(0);
    // assert empty grid
    for (0..Grid.WIDTH) |i| {
        try std.testing.expect(!grid.isOccupied(i, 0));
    }
    grid.print();
}

test "shift" {
    std.debug.print("shift\n", .{});

    // Initialize ECS world for testing
    ecs.init();
    defer ecs.deinit();

    var grid = Grid.init();

    // fill line 0
    for (0..Grid.WIDTH) |i| {
        grid.occupy(0, i, .{ 255, 255, 255, 255 });
    }

    // fill line 1
    for (0..Grid.WIDTH) |i| {
        grid.occupy(1, i, .{ 255, 255, 255, 255 });
    }

    grid.print();

    grid.shiftrow(1);

    // assert line 0 full
    try std.testing.expect(grid.checkline(0) == true);

    // assert line 1 is empty
    for (0..Grid.WIDTH) |i| {
        try std.testing.expect(!grid.isOccupied(1, i));
    }

    try std.testing.expect(grid.checkline(2) == true);

    grid.print();
}

test "clear" {
    std.debug.print("clear\n", .{});

    // Initialize ECS world for testing
    ecs.init();
    defer ecs.deinit();

    var grid = Grid.init();

    // fill line 19 (bottom row)
    for (0..Grid.WIDTH) |i| {
        grid.occupy(19, i, .{ 255, 255, 255, 255 });
    }

    // Add some cells in rows 18 and 17
    grid.occupy(18, 0, .{ 255, 255, 255, 255 });
    grid.occupy(17, 0, .{ 255, 255, 255, 255 });
    grid.occupy(17, 1, .{ 255, 255, 255, 255 });

    // Fill row 16 completely
    for (0..Grid.WIDTH) |i| {
        grid.occupy(16, i, .{ 255, 255, 255, 255 });
    }
    grid.print();
    _ = grid.clear();
    grid.print();
    try std.testing.expect(grid.checkline(19) == false);
    try std.testing.expect(grid.checkline(16) == false);
}
