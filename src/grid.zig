const std = @import("std");
const cells = @import("cell.zig");
const CellData = cells.CellData;
const pieces = @import("pieces.zig");
const events = @import("events.zig");

pub const Grid = struct {
    const Self = @This();
    pub const WIDTH = 10;
    pub const HEIGHT = 20;
    
    // 2D array of optional CellData
    data: [HEIGHT][WIDTH]?CellData,
    
    pub fn init() Self {
        return Self{
            .data = [_][WIDTH]?CellData{[_]?CellData{null} ** WIDTH} ** HEIGHT,
        };
    }
    
    pub fn isOccupied(self: *const Self, x: usize, y: usize) bool {
        return if (x < WIDTH and y < HEIGHT) self.data[y][x] != null else false;
    }
    
    pub fn occupy(self: *Self, gridy: usize, gridx: usize, color: [4]u8) void {
        if (gridx < WIDTH and gridy < HEIGHT) {
            self.data[gridy][gridx] = CellData.fromRgba(color);
        }
    }
    
    pub fn vacate(self: *Self, gridy: usize, gridx: usize) void {
        if (gridx < WIDTH and gridy < HEIGHT) {
            self.data[gridy][gridx] = null;
        }
    }
    
    pub fn clearall(self: *Self) void {
        self.data = [_][WIDTH]?CellData{[_]?CellData{null} ** WIDTH} ** HEIGHT;
    }
    
    fn removeline(self: *Self, line: usize) void {
        std.debug.print("removeline {d}\n", .{line});

        // Emit LineClearing event before modifying the grid
        events.push(.{ .LineClearing = .{ .y = line } }, events.Source.Game);

        // Clear data cells
        for (0..WIDTH) |i| {
            self.data[line][i] = null;
        }
    }

    // shift a single line down
    fn shiftrow(self: *Self, line: usize) void {
        // Check if the line is within bounds
        if (line >= HEIGHT - 1) {
            return; // Cannot shift the last row down
        }

        // Emit RowsShiftedDown event before modifying the grid
        events.push(.{ .RowsShiftedDown = .{ .start_y = line, .count = 1 } }, events.Source.Game);

        // Move each cell in the row down by one row
        for (0..WIDTH) |i| {
            // Shift data cells down
            self.data[line + 1][i] = self.data[line][i];
            self.data[line][i] = null;
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
                if (self.data[y][x] != null) {
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
            if (self.data[y][x] == null) {
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
                        if (self.data[iy][ix] != null) {
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
    
    // Test getting cell data
    if (grid.data[0][0]) |cell_data| {
        const rgba = cell_data.toRgba();
        try std.testing.expectEqual(@as(u8, 255), rgba[0]);
        try std.testing.expectEqual(@as(u8, 255), rgba[1]);
        try std.testing.expectEqual(@as(u8, 255), rgba[2]);
        try std.testing.expectEqual(@as(u8, 255), rgba[3]);
    } else {
        try std.testing.expect(false);
    }
    
    // Test vacate
    grid.vacate(0, 0);
    try std.testing.expect(!grid.isOccupied(0, 0));
}

test "check line" {
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
        try std.testing.expect(grid.data[1][i] == null);
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