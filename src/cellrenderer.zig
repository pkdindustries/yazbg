const std = @import("std");
const CellData = @import("cell.zig").CellData;

pub const AnimationState = struct {
    source: [2]f32,
    target: [2]f32,
    position: [2]f32,
    scale: f32,
    color_source: [4]u8,
    color_target: [4]u8,
    color: [4]u8,
    startedat: i64,
    duration: i64,
    notbefore: i64 = 0, // Timestamp when animation should start (0 = start immediately)
    mode: enum { linear, easein, easeout },
    animating: bool,
};

pub const Cell = struct {
    data: ?CellData = null,
    anim_state: ?AnimationState = null,

    pub fn isOccupied(self: Cell) bool {
        return self.data != null;
    }

    pub fn isAnimating(self: Cell) bool {
        return self.anim_state != null and self.anim_state.?.animating;
    }
};

pub const CellLayer = struct {
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    cells: []Cell,

    pub fn countTotalAnimations(self: *const CellLayer) usize {
        var count: usize = 0;
        for (self.cells) |cell| {
            if (cell.anim_state != null) {
                count += 1;
            }
        }
        return count;
    }

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !*CellLayer {
        const self = try allocator.create(CellLayer);
        self.allocator = allocator;
        self.width = width;
        self.height = height;
        self.cells = try allocator.alloc(Cell, width * height);

        // Initialize all cells
        for (self.cells) |*cell| {
            cell.* = .{};
        }

        return self;
    }

    pub fn deinit(self: *CellLayer) void {
        self.allocator.free(self.cells);
        self.allocator.destroy(self);
    }

    pub fn index(self: *const CellLayer, x: usize, y: usize) usize {
        return y * self.width + x;
    }

    pub fn ptr(self: *CellLayer, x: usize, y: usize) *Cell {
        return &self.cells[self.index(x, y)];
    }

    pub fn coordsFromIdx(self: *const CellLayer, idx: usize) struct { x: usize, y: usize } {
        const y = idx / self.width;
        const x = idx % self.width;
        return .{ .x = x, .y = y };
    }

    pub fn clear(self: *CellLayer) void {
        for (self.cells) |*cell| {
            cell.data = null;
        }
    }
};