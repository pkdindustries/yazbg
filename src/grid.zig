const std = @import("std");
const cells = @import("cell.zig");
const pieces = @import("pieces.zig");
const events = @import("events.zig");
const ecs = @import("ecs.zig");
const ecsroot = @import("ecs");
const components = @import("components.zig");
const createFallingRow = @import("systems/rowfallsys.zig").createRippledFallingRow;
const addRowShiftAnim = @import("systems/rowshiftsys.zig").addRowShiftAnim;

pub const Grid = struct {
    const Self = @This();
    pub const WIDTH = 10;
    pub const HEIGHT = 20;

    // Bitgrid to track occupied cells
    occupied: [HEIGHT][WIDTH]bool,
    // Color array for occupied cells
    colors: [HEIGHT][WIDTH][4]u8,

    pub fn init() Self {
        return Self{
            .occupied = [_][WIDTH]bool{[_]bool{false} ** WIDTH} ** HEIGHT,
            .colors = [_][WIDTH][4]u8{[_][4]u8{[_]u8{0} ** 4} ** WIDTH} ** HEIGHT,
        };
    }

    pub fn isOccupied(self: *const Self, x: usize, y: usize) bool {
        if (x >= WIDTH or y >= HEIGHT) return false;
        return self.occupied[y][x];
    }

    pub fn occupy(self: *Self, gridx: usize, gridy: usize, color: [4]u8) void {
        const entity = ecs.createEntity();
        const gx: i32 = @intCast(gridx);
        const gy: i32 = @intCast(gridy);
        ecs.add(components.GridPos, entity, components.GridPos{ .x = gx, .y = gy });
        ecs.add(components.BlockTag, entity, components.BlockTag{});

        // Update bit-grid and color array
        if (gridx < WIDTH and gridy < HEIGHT) {
            self.occupied[gridy][gridx] = true;
            self.colors[gridy][gridx] = color;
        }

        // Scale from grid coordinates to pixel coordinates
        const cellsize_f32: f32 = 35.0; // Using default cell size, could be made configurable
        const px = @as(f32, @floatFromInt(gridx)) * cellsize_f32;
        const py = @as(f32, @floatFromInt(gridy)) * cellsize_f32;

        ecs.add(components.Position, entity, components.Position{ .x = px, .y = py });
        ecs.add(components.Sprite, entity, components.Sprite{ .rgba = color, .size = 1.0 });

        const ttl_ms: i64 = 350;
        ecs.add(components.Flash, entity, components.Flash{
            .ttl_ms = ttl_ms,
            .expires_at_ms = std.time.milliTimestamp() + ttl_ms,
        });
    }

    pub fn vacate(self: *Self, gridy: i32, gridx: i32) void {
        if (gridx < 0 or gridy < 0 or gridx >= WIDTH or gridy >= HEIGHT) return;

        // Update bit-grid
        const gx: usize = @intCast(gridx);
        const gy: usize = @intCast(gridy);
        self.occupied[gy][gx] = false;
        self.colors[gy][gx] = .{ 0, 0, 0, 0 }; // Clear color

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

    pub fn clearall(self: *Self) void {
        // Clear bit-grid and color array
        self.occupied = [_][WIDTH]bool{[_]bool{false} ** WIDTH} ** HEIGHT;
        self.colors = [_][WIDTH][4]u8{[_][4]u8{[_]u8{0} ** 4} ** WIDTH} ** HEIGHT;

        // Remove all block entities
        var blocks_view = ecs.getBlocksView();

        // We know the maximum entities is WIDTH*HEIGHT
        var buffer: [WIDTH * HEIGHT]ecsroot.Entity = undefined;
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

    fn removeline(self: *Self, line: usize) void {
        std.debug.print("removeline {d}\n", .{line});

        // Clear the line in bit-grid
        if (line < HEIGHT) {
            for (0..WIDTH) |x| {
                self.occupied[line][x] = false;
                self.colors[line][x] = .{ 0, 0, 0, 0 }; // Clear color
            }
        }

        // get blocks in this line
        var blocks_view = ecs.getBlocksView();

        // We know the maximum entities in a line is WIDTH
        var buffer: [WIDTH]ecsroot.Entity = undefined;
        var count: usize = 0;

        // Collect entities in the line
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

        createFallingRow(line, buffer[0..count]);
        // Original entities should be destroyed immediately
        for (buffer[0..count]) |entity| {
            ecs.getWorld().destroy(entity);
        }
    }

    // shift a single line down
    fn shiftrow(self: *Self, line: usize) void {
        // Check if the line is within bounds
        if (line >= HEIGHT - 1) {
            return; // Cannot shift the last row down
        }

        // Update the bit-grid by moving cells from line to line+1
        if (line + 1 < HEIGHT) {
            for (0..WIDTH) |x| {
                self.occupied[line + 1][x] = self.occupied[line][x];
                self.colors[line + 1][x] = self.colors[line][x];
                self.occupied[line][x] = false;
                self.colors[line][x] = .{ 0, 0, 0, 0 };
            }
        }

        // Shift all entities in this line down
        var blocks_view = ecs.getBlocksView();

        // We know the maximum entities in a line is WIDTH
        var buffer: [WIDTH]ecsroot.Entity = undefined;
        var pbuffer: [WIDTH]components.Position = undefined;
        var gbuffer: [WIDTH]components.GridPos = undefined;
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
            ecs.add(components.GridPos, entity, grid_pos);

            // Position is updated for game logic
            pos.y = target_pos_y;
            ecs.add(components.Position, entity, pos);

            // Add animation component
            addRowShiftAnim(entity, start_pos_y, target_pos_y);
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
            if (!self.occupied[y][x]) {
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

                        // Cell is already occupied - direct bit-grid check
                        if (self.occupied[iy][ix]) {
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
