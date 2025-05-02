const std = @import("std");
const cells = @import("cell.zig");
const pieces = @import("pieces.zig");
const events = @import("events.zig");

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
        // Update bit-grid and color array and immediately emit event
        if (gridx < WIDTH and gridy < HEIGHT) {
            self.occupied[gridy][gridx] = true;
            self.colors[gridy][gridx] = color;
        }

        // Emit individual event (will be replaced by batched event)
        events.push(.{
            .PieceLocked = .{
                .blocks = [_]events.CellDataPos{
                    .{ .x = gridx, .y = gridy, .color = color },
                    undefined,
                    undefined,
                    undefined,
                },
                .count = 1,
            },
        }, .Game);
    }

    // New method for occupying blocks without emitting events
    // Used by game.zig for batched event emission
    pub fn occupyBlocks(self: *Self, gridx: usize, gridy: usize, color: [4]u8) void {
        // Update bit-grid and color array only (no event)
        if (gridx < WIDTH and gridy < HEIGHT) {
            self.occupied[gridy][gridx] = true;
            self.colors[gridy][gridx] = color;
        }
    }

    pub fn vacate(self: *Self, gridy: i32, gridx: i32) void {
        if (gridx < 0 or gridy < 0 or gridx >= WIDTH or gridy >= HEIGHT) return;

        // Update bit-grid
        const gx: usize = @intCast(gridx);
        const gy: usize = @intCast(gridy);
        self.occupied[gy][gx] = false;
        self.colors[gy][gx] = .{ 0, 0, 0, 0 }; // Clear color

        // Emit event for ECS operation
        events.push(.{
            .LineClearing = .{
                .y = gy,
            },
        }, .Game);
    }

    pub fn clearall(self: *Self) void {
        // Clear bit-grid and color array
        self.occupied = [_][WIDTH]bool{[_]bool{false} ** WIDTH} ** HEIGHT;
        self.colors = [_][WIDTH][4]u8{[_][4]u8{[_]u8{0} ** 4} ** WIDTH} ** HEIGHT;

        // Emit event for ECS operations
        events.push(.GridReset, .Game);
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

        // Emit event for ECS operations
        events.push(.{
            .LineClearing = .{
                .y = line,
            },
        }, .Game);
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

        // Emit event for ECS operations
        events.push(.{
            .RowsShiftedDown = .{
                .start_y = line,
                .count = 1,
            },
        }, .Game);
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
        grid.occupy(x, 5, .{ 255, 255, 255, 255 });
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
        grid.occupy(i, 0, .{ 255, 255, 255, 255 });
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
        grid.occupy(i, 0, .{ 255, 255, 255, 255 });
    }

    // fill line 1
    for (0..Grid.WIDTH) |i| {
        grid.occupy(i, 1, .{ 255, 255, 255, 255 });
    }

    grid.print();

    grid.shiftrow(1);

    // assert line 0 remains full
    try std.testing.expect(grid.checkline(0) == true);

    // assert line 1 is empty
    for (0..Grid.WIDTH) |i| {
        try std.testing.expect(!grid.isOccupied(i, 1));
    }

    // assert line 2 is now full (content from line 1 shifted down)
    try std.testing.expect(grid.checkline(2) == true);

    grid.print();
}

test "clear" {
    std.debug.print("clear\n", .{});

    var grid = Grid.init();

    // fill line 19 (bottom row)
    for (0..Grid.WIDTH) |i| {
        grid.occupy(i, 19, .{ 255, 255, 255, 255 });
    }

    // Add some cells in rows 18 and 17
    grid.occupy(0, 18, .{ 255, 255, 255, 255 });
    grid.occupy(0, 17, .{ 255, 255, 255, 255 });
    grid.occupy(1, 17, .{ 255, 255, 255, 255 });

    // Fill row 16 completely
    for (0..Grid.WIDTH) |i| {
        grid.occupy(i, 16, .{ 255, 255, 255, 255 });
    }
    grid.print();
    _ = grid.clear();
    grid.print();
    try std.testing.expect(grid.checkline(19) == false);
    try std.testing.expect(grid.checkline(16) == false);
}
