const std = @import("std");
const anim = @import("animation.zig");
const width = 10;
const height = 20;

pub const Grid = struct {
    const Self = @This();
    allocator: std.mem.Allocator = undefined,
    animated: *anim.Animating = undefined,
    cells: [height][width]?*anim.AnimatedCell = undefined,

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const gc = try allocator.create(Self);
        gc.* = Self{
            .allocator = allocator,
            .animated = try anim.Animating.init(allocator),
        };
        return gc;
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    fn removeline(self: *Self, line: usize) void {
        std.debug.print("removeline {d}\n", .{line});
        for (self.cells[line], 0..) |cell, i| {
            if (cell) |cptr| {
                cptr.target[1] = 1000;
                self.animated.add(cptr);
                self.cells[line][i] = null;
            }
        }
    }

    // shift a single line down
    fn shiftrow(self: *Self, line: usize) void {
        // Check if the line is within bounds
        if (line >= height - 1) {
            return; // Cannot shift the last row down
        }

        // Move each cell in the row down by one row
        for (self.cells[line], 0..) |cell, i| {
            self.cells[line + 1][i] = cell; // Shift down
            self.cells[line][i] = null; // Clear the original cell
            // coords
            if (cell) |cptr| {
                cptr.duration = 100;
                cptr.setcoords(i, line + 1);
            }
        }
    }

    pub fn destroy(self: *Self) void {
        for (self.cells, 0..) |line, i| {
            for (line, 0..) |cell, j| {
                if (cell) |cptr| {
                    self.allocator.destroy(cptr);
                    self.cells[i][j] = null;
                }
            }
        }
    }

    pub fn checkline(self: *Self, line: usize) bool {
        for (self.cells[line]) |cell| {
            if (cell == null) {
                return false;
            }
        }
        return true;
    }

    pub fn clear(self: *Self) u8 {
        var line: u8 = height - 1;
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
                line -= 1; // Move to the next row up only if the current line is not completed
            }
        }
        return count;
    }

    pub fn print(self: *Self) void {
        std.debug.print("\n", .{});
        for (self.cells) |line| {
            for (line) |cell| {
                if (cell) |cptr| {
                    _ = cptr;
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
    defer gpa.allocator().destroy(g);
    g.cells[0][0] = try anim.AnimatedCell.init(&gpa.allocator(), 0, 0, .{ 255, 255, 255, 255 });

    if (g.cells[0][0]) |cptr| {
        std.debug.print("0 0 {any}\n", .{cptr.*});
        g.cells[0][0] = null;
        gpa.allocator().destroy(cptr);
    }

    if (g.cells[0][0]) |cptr| {
        std.debug.print("nulled {any}\n", .{cptr.*});
    }
}

test "rm" {
    std.debug.print("rm\n", .{});
    const GPA = std.heap.GeneralPurposeAllocator(.{});
    var gpa = GPA{};
    const g = try Grid.init(gpa.allocator());
    defer g.deinit();
    defer gpa.allocator().destroy(g);

    // fill line 0
    for (g.cells[0], 0..) |_, i| {
        g.cells[0][i] = try anim.AnimatedCell.init(&gpa.allocator(), i, 0, .{ 255, 255, 255, 255 });
    }

    g.print();
    g.removeline(0);
    // assert empty grid
    for (g.cells[0]) |cell| {
        try std.testing.expect(cell == null);
    }
    g.print();
}

test "shift" {
    std.debug.print("shift\n", .{});
    const GPA = std.heap.GeneralPurposeAllocator(.{});
    var gpa = GPA{};
    const g = try Grid.init(gpa.allocator());
    defer g.deinit();
    defer gpa.allocator().destroy(g);

    // fill line 0
    for (g.cells[0], 0..) |_, i| {
        g.cells[0][i] = try anim.AnimatedCell.init(&gpa.allocator(), i, 0, .{ 255, 255, 255, 255 });
    }

    // fill line 1
    for (g.cells[1], 0..) |_, i| {
        g.cells[1][i] = try anim.AnimatedCell.init(&gpa.allocator(), i, 1, .{ 255, 255, 255, 255 });
    }

    g.print();

    g.shiftrow(1);

    // assert line 0 full
    try std.testing.expect(g.checkline(0) == true);

    // assert line 1 is empty
    for (g.cells[1]) |cell| {
        try std.testing.expect(cell == null);
    }

    try std.testing.expect(g.checkline(2) == true);

    g.print();
    g.destroy();
}

test "clear" {
    std.debug.print("clear\n", .{});
    const GPA = std.heap.GeneralPurposeAllocator(.{});
    var gpa = GPA{};
    const g = try Grid.init(gpa.allocator());
    defer g.deinit();
    defer gpa.allocator().destroy(g);

    // fill line 0
    for (g.cells[19], 0..) |_, i| {
        g.cells[19][i] = try anim.AnimatedCell.init(&gpa.allocator(), i, 0, .{ 255, 255, 255, 255 });
    }

    g.cells[18][0] = try anim.AnimatedCell.init(&gpa.allocator(), 0, 18, .{ 255, 255, 255, 255 });
    g.cells[17][0] = try anim.AnimatedCell.init(&gpa.allocator(), 0, 18, .{ 255, 255, 255, 255 });
    g.cells[17][1] = try anim.AnimatedCell.init(&gpa.allocator(), 0, 18, .{ 255, 255, 255, 255 });

    for (g.cells[16], 0..) |_, i| {
        g.cells[16][i] = try anim.AnimatedCell.init(&gpa.allocator(), i, 0, .{ 255, 255, 255, 255 });
    }
    g.print();
    _ = g.clear();
    g.print();
    try std.testing.expect(g.checkline(19) == false);
    try std.testing.expect(g.checkline(16) == false);

    g.destroy();
}
