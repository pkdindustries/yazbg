const std = @import("std");
const cells = @import("cell.zig");
const CellData = cells.CellData;
const events = @import("events.zig");

pub const Grid = struct {
    const Self = @This();
    pub const WIDTH = 10;
    pub const HEIGHT = 20;
    allocator: std.mem.Allocator = undefined,
    cells_data: [HEIGHT][WIDTH]?CellData = undefined,

    pub fn init(allocator: std.mem.Allocator) !*Self {
        std.debug.print("init grid\n", .{});
        const gc = try allocator.create(Self);

        gc.* = Self{
            .allocator = allocator,
        };

        for (0..HEIGHT) |i| {
            for (0..WIDTH) |j| {
                gc.cells_data[i][j] = null;
            }
        }
        return gc;
    }

    pub fn deinit(self: *Self) void {
        std.debug.print("deinit grid\n", .{});
        self.allocator.destroy(self);
    }

    fn removeline(self: *Self, line: usize) void {
        std.debug.print("removeline {d}\n", .{line});

        // Emit LineClearing event before modifying the grid
        events.push(.{ .LineClearing = .{ .y = line } }, events.Source.Game);

        // Clear data cells
        for (0..WIDTH) |i| {
            self.cells_data[line][i] = null;
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
            self.cells_data[line + 1][i] = self.cells_data[line][i];
            self.cells_data[line][i] = null;
        }
    }

    pub fn checkline(self: *Self, line: usize) bool {
        for (self.cells_data[line]) |cell_data| {
            if (cell_data == null) {
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
        self.cells_data[gridy][gridx] = CellData.fromRgba(color);
    }

    /// Remove a cell from data table
    pub fn vacate(self: *Self, gridy: usize, gridx: usize) void {
        // Remove from data table
        self.cells_data[gridy][gridx] = null;
    }

    pub fn print(self: *Self) void {
        std.debug.print("\n", .{});

        // Print data cells
        for (self.cells_data) |line| {
            for (line) |cell_data| {
                if (cell_data != null) {
                    std.debug.print("+", .{});
                } else {
                    std.debug.print("-", .{});
                }
            }
            std.debug.print("\n", .{});
        }
    }
};

test "init" {
    const GPA = std.heap.GeneralPurposeAllocator(.{});
    var gpa = GPA{};
    const g = try Grid.init(gpa.allocator());
    defer g.deinit();
    g.occupy(0, 0, .{ 255, 255, 255, 255 });

    // Print the grid
    g.print();

    // Verify that cells_data has the color
    if (g.cells_data[0][0]) |cell_data| {
        const rgba = cell_data.toRgba();
        std.debug.print("cells_data[0][0] color: {any}\n", .{rgba});
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
    const g = try Grid.init(gpa.allocator());
    defer g.deinit();

    // fill line 0
    for (0..Grid.WIDTH) |i| {
        g.occupy(0, i, .{ 255, 255, 255, 255 });
    }

    g.print();
    g.removeline(0);
    // assert empty grid
    for (g.cells_data[0]) |cell_data| {
        try std.testing.expect(cell_data == null);
    }
    g.print();
}

test "shift" {
    std.debug.print("shift\n", .{});
    const GPA = std.heap.GeneralPurposeAllocator(.{});
    var gpa = GPA{};
    const g = try Grid.init(gpa.allocator());
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
    for (g.cells_data[1]) |cell_data| {
        try std.testing.expect(cell_data == null);
    }

    try std.testing.expect(g.checkline(2) == true);

    g.print();
}

test "clear" {
    std.debug.print("clear\n", .{});
    const GPA = std.heap.GeneralPurposeAllocator(.{});
    var gpa = GPA{};
    const g = try Grid.init(gpa.allocator());
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
