const std = @import("std");
const cells = @import("cell.zig");
const CellData = cells.CellData;
const events = @import("events.zig");
const CellLayer = @import("cellrenderer.zig").CellLayer;
const pieces = @import("pieces.zig");
pub const Grid = struct {
    const Self = @This();
    pub const WIDTH = 10;
    pub const HEIGHT = 20;
    layer: *CellLayer, //

    pub fn init(layer: *CellLayer) !*Self {
        std.debug.print("init grid\n", .{});
        const allocator = layer.allocator;
        const gc = try allocator.create(Self);

        gc.* = Self{
            .layer = layer,
        };

        return gc;
    }

    pub fn deinit(self: *Self) void {
        std.debug.print("deinit grid\n", .{});
        const allocator = self.layer.allocator;
        allocator.destroy(self);
    }

    fn removeline(self: *Self, line: usize) void {
        std.debug.print("removeline {d}\n", .{line});

        // Emit LineClearing event before modifying the grid
        events.push(.{ .LineClearing = .{ .y = line } }, events.Source.Game);

        // Clear data cells
        for (0..WIDTH) |i| {
            self.layer.ptr(i, line).data = null;
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
            self.layer.ptr(i, line + 1).data = self.layer.ptr(i, line).data;
            self.layer.ptr(i, line).data = null;
        }
    }

    pub fn checkline(self: *Self, line: usize) bool {
        for (0..WIDTH) |i| {
            if (!self.layer.ptr(i, line).isOccupied()) {
                return false;
            }
        }
        return true;
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

    /// Occupy a cell with a color in data table
    pub fn occupy(self: *Self, gridy: usize, gridx: usize, color: [4]u8) void {
        // Create logical cell data
        self.layer.ptr(gridx, gridy).data = CellData.fromRgba(color);
    }

    /// Remove a cell from data table
    pub fn vacate(self: *Self, gridy: usize, gridx: usize) void {
        // Remove from data table
        self.layer.ptr(gridx, gridy).data = null;
    }

    pub fn clearall(self: *Self) void {
        self.layer.clear();
    }

    pub fn print(self: *Self) void {
        std.debug.print("\n", .{});

        // Print data cells
        for (0..HEIGHT) |y| {
            for (0..WIDTH) |x| {
                if (self.layer.ptr(x, y).isOccupied()) {
                    std.debug.print("+", .{});
                } else {
                    std.debug.print("-", .{});
                }
            }
            std.debug.print("\n", .{});
        }
    }

    pub fn checkmove(self: *Self, piece: ?pieces.tetramino, x: i32, y: i32, r: u32) bool {
        if (piece) |p| {
            const shape = p.shape[r];
            for (shape, 0..) |row, j| {
                for (row, 0..) |cell, i| {
                    if (cell) {
                        const gx = x + @as(i32, @intCast(j));
                        const gy = y + @as(i32, @intCast(i));
                        // cell is out of bounds
                        if (gx < 0 or gx >= WIDTH or gy < 0 or gy >= HEIGHT) {
                            return false;
                        }

                        const ix = @as(usize, @intCast(gx));
                        const iy = @as(usize, @intCast(gy));
                        // cell is already occupied via logical_data only
                        if (self.layer.ptr(ix, iy).isOccupied()) {
                            return false;
                        }
                    }
                }
            }
        }
        return true;
    }
};

test "init" {
    const GPA = std.heap.GeneralPurposeAllocator(.{});
    var gpa = GPA{};
    const allocator = gpa.allocator();

    const layer = try CellLayer.init(allocator, Grid.WIDTH, Grid.HEIGHT);
    defer layer.deinit();

    const g = try Grid.init(layer);
    defer g.deinit();

    g.occupy(0, 0, .{ 255, 255, 255, 255 });

    // Print the grid
    g.print();

    // Verify that the cell has the color
    const cell = g.layer.ptr(0, 0);
    if (cell.data) |cell_data| {
        const rgba = cell_data.toRgba();
        std.debug.print("cell color: {any}\n", .{rgba});
        try std.testing.expectEqual(@as(u8, 255), rgba[0]);
        try std.testing.expectEqual(@as(u8, 255), rgba[1]);
        try std.testing.expectEqual(@as(u8, 255), rgba[2]);
        try std.testing.expectEqual(@as(u8, 255), rgba[3]);
    } else {
        try std.testing.expect(false);
    }
}

test "rm" {
    std.debug.print("rm\n", .{});
    const GPA = std.heap.GeneralPurposeAllocator(.{});
    var gpa = GPA{};
    const allocator = gpa.allocator();

    const layer = try CellLayer.init(allocator, Grid.WIDTH, Grid.HEIGHT);
    defer layer.deinit();

    const g = try Grid.init(layer);
    defer g.deinit();

    // fill line 0
    for (0..Grid.WIDTH) |i| {
        g.occupy(0, i, .{ 255, 255, 255, 255 });
    }

    g.print();
    g.removeline(0);
    // assert empty grid
    for (0..Grid.WIDTH) |i| {
        try std.testing.expect(!g.layer.ptr(i, 0).isOccupied());
    }
    g.print();
}

test "shift" {
    std.debug.print("shift\n", .{});
    const GPA = std.heap.GeneralPurposeAllocator(.{});
    var gpa = GPA{};
    const allocator = gpa.allocator();

    const layer = try CellLayer.init(allocator, Grid.WIDTH, Grid.HEIGHT);
    defer layer.deinit();

    const g = try Grid.init(layer);
    defer g.deinit();

    // fill line 0
    for (0..Grid.WIDTH) |i| {
        g.occupy(0, i, .{ 255, 255, 255, 255 });
    }

    // fill line 1
    for (0..Grid.WIDTH) |i| {
        g.occupy(1, i, .{ 255, 255, 255, 255 });
    }

    g.print();

    g.shiftrow(1);

    // assert line 0 full
    try std.testing.expect(g.checkline(0) == true);

    // assert line 1 is empty
    for (0..Grid.WIDTH) |i| {
        try std.testing.expect(!g.layer.ptr(i, 1).isOccupied());
    }

    try std.testing.expect(g.checkline(2) == true);

    g.print();
}

test "clear" {
    std.debug.print("clear\n", .{});
    const GPA = std.heap.GeneralPurposeAllocator(.{});
    var gpa = GPA{};
    const allocator = gpa.allocator();

    const layer = try CellLayer.init(allocator, Grid.WIDTH, Grid.HEIGHT);
    defer layer.deinit();

    const g = try Grid.init(layer);
    defer g.deinit();

    // fill line 19 (bottom row)
    for (0..Grid.WIDTH) |i| {
        g.occupy(19, i, .{ 255, 255, 255, 255 });
    }

    // Add some cells in rows 18 and 17
    g.occupy(18, 0, .{ 255, 255, 255, 255 });
    g.occupy(17, 0, .{ 255, 255, 255, 255 });
    g.occupy(17, 1, .{ 255, 255, 255, 255 });

    // Fill row 16 completely
    for (0..Grid.WIDTH) |i| {
        g.occupy(16, i, .{ 255, 255, 255, 255 });
    }
    g.print();
    _ = g.clear();
    g.print();
    try std.testing.expect(g.checkline(19) == false);
    try std.testing.expect(g.checkline(16) == false);
}
