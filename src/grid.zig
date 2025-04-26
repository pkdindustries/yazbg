const std = @import("std");
const anim_mod = @import("animation.zig");
const Animated = anim_mod.Animated;
const Unattached = anim_mod.UnattachedCell;
const AnimationPool = anim_mod.AnimationPool;
const cell_mod = @import("cell.zig");
const CellData = cell_mod.CellData;

pub const Grid = struct {
    const Self = @This();
    pub const WIDTH = 10;
    pub const HEIGHT = 20;
    allocator: std.mem.Allocator = undefined,
    animpool: *AnimationPool = undefined,
    unattached: *Unattached = undefined,
    cells: [HEIGHT][WIDTH]?*Animated = undefined,
    cells_data: [HEIGHT][WIDTH]?CellData = undefined,
    cleartimer: i64 = 0,

    pub fn init(allocator: std.mem.Allocator) !*Self {
        std.debug.print("init grid\n", .{});
        const gc = try allocator.create(Self);

        // Initialize the animation pool
        const pool = try AnimationPool.init(allocator);

        gc.* = Self{
            .allocator = allocator,
            .animpool = pool,
            .unattached = try Unattached.init(pool),
        };

        for (gc.cells, 0..) |line, i| {
            for (line, 0..) |_, j| {
                gc.cells[i][j] = null;
                gc.cells_data[i][j] = null;
            }
        }
        return gc;
    }

    pub fn deinit(self: *Self) void {
        std.debug.print("deinit grid\n", .{});

        // Release all cells back to the pool
        for (self.cells, 0..) |line, i| {
            for (line, 0..) |grid_cell, j| {
                if (grid_cell) |cptr| {
                    self.animpool.release(cptr);
                    self.cells[i][j] = null;
                }
            }
        }

        // Deinit unattached animations first (will release cells to the pool)
        self.unattached.deinit();

        // Finally deinit the pool itself
        self.animpool.deinit();
        self.allocator.destroy(self);
    }

    fn removeline(self: *Self, line: usize) void {
        std.debug.print("removeline {d}\n", .{line});
        inline for (self.cells[line], 0..) |grid_cell, i| {
            // Handle animation cells
            if (grid_cell) |cptr| {
                cptr.target[1] = 800;
                cptr.mode = .easein;
                cptr.duration = 250;
                self.unattached.add(cptr);
                self.cells[line][i] = null;
                self.cleartimer = std.time.milliTimestamp() + 100;
            }
            
            // Clear data cells
            self.cells_data[line][i] = null;
        }
    }

    // shift a single line down
    fn shiftrow(self: *Self, line: usize) void {
        // Check if the line is within bounds
        if (line >= HEIGHT - 1) {
            return; // Cannot shift the last row down
        }

        // Move each cell in the row down by one row
        inline for (self.cells[line], 0..) |grid_cell, i| {
            // Shift animated cells down
            self.cells[line + 1][i] = grid_cell;
            self.cells[line][i] = null;
            
            // Shift data cells down
            self.cells_data[line + 1][i] = self.cells_data[line][i];
            self.cells_data[line][i] = null;
            
            // Update animation coordinates
            if (grid_cell) |cptr| {
                cptr.duration = 200;
                cptr.mode = .easeinout;
                cptr.setcoords(i, line + 1);
            }
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

    pub fn createCell(self: *Self, gridx: usize, gridy: usize, color: [4]u8) ?*Animated {
        return self.animpool.create(gridx, gridy, color);
    }
    
    /// Occupy a cell with a color in both animation and data tables
    pub fn occupy(self: *Self, gridy: usize, gridx: usize, color: [4]u8) void {
        // Create animated cell
        const animated = self.createCell(gridx, gridy, color);
        if (animated) |animated_cell| {
            self.cells[gridy][gridx] = animated_cell;
        }
        
        // Create logical cell data
        self.cells_data[gridy][gridx] = CellData.fromRgba(color);
    }
    
    /// Remove a cell from both animation and data tables
    pub fn vacate(self: *Self, gridy: usize, gridx: usize) void {
        // Remove from animation table
        if (self.cells[gridy][gridx]) |cell_ptr| {
            self.animpool.release(cell_ptr);
            self.cells[gridy][gridx] = null;
        }
        
        // Remove from data table
        self.cells_data[gridy][gridx] = null;
    }

    pub fn print(self: *Self) void {
        std.debug.print("\n", .{});
        
        // Print animated cells
        std.debug.print("Animation cells:\n", .{});
        for (self.cells) |line| {
            for (line) |grid_cell| {
                if (grid_cell) |cptr| {
                    _ = cptr;
                    std.debug.print("+", .{});
                } else {
                    std.debug.print("-", .{});
                }
            }
            std.debug.print("\n", .{});
        }
        
        // Print data cells
        std.debug.print("Data cells:\n", .{});
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

    // Print both tables to verify they match
    g.print();

    if (g.cells[0][0]) |cptr| {
        std.debug.print("0 0 {any}\n", .{cptr.*});
        g.cells[0][0] = null;
        // No need to destroy, just set to null and the pool will reuse it later
    }

    // Also verify that cells_data has the color
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
    for (g.cells[0]) |grid_cell| {
        try std.testing.expect(grid_cell == null);
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
    for (g.cells[1]) |grid_cell| {
        try std.testing.expect(grid_cell == null);
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
