const std = @import("std");

// Pool size for animated objects
const MAX_ANIMATED = 500;

pub const AnimationPool = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    pool: std.heap.MemoryPool(Animated),
    inuse: usize = 0,

    pub fn init(allocator: std.mem.Allocator) !*Self {
        std.debug.print("init animation pool\n", .{});
        const pool = try allocator.create(Self);

        // Initialize memory pool for Animated objects
        pool.pool = std.heap.MemoryPool(Animated).init(allocator);
        errdefer pool.pool.deinit();

        pool.allocator = allocator;
        pool.inuse = 0;

        return pool;
    }

    pub fn deinit(self: *Self) void {
        std.debug.print("deinit animation pool\n", .{});
        self.pool.deinit();
        self.allocator.destroy(self);
    }

    pub fn create(self: *Self, gridx: usize, gridy: usize, color: [4]u8) ?*Animated {
        const cell = self.pool.create() catch {
            std.debug.print("WARNING: Animation pool allocation failed!\n", .{});
            return null;
        };

        self.inuse += 1;

        const p: [2]f32 = .{
            @as(f32, @floatFromInt(gridx * 35)),
            @as(f32, @floatFromInt(gridy * 35)),
        };

        cell.* = Animated{
            .source = p,
            .position = p,
            .target = p,
            .color_source = color,
            .color = color,
            .color_target = color,
            .source_scale = 1.0,
            .target_scale = 1.0,
            .scale = 1.0,
        };

        return cell;
    }

    pub fn release(self: *Self, cell: *Animated) void {
        self.pool.destroy(cell);
        self.inuse -= 1;
    }
};

pub const UnattachedCell = struct {
    const Self = @This();
    pool: *AnimationPool,
    cells: [MAX_ANIMATED]?*Animated = undefined,

    pub fn init(pool: *AnimationPool) !*Self {
        std.debug.print("init unattached\n", .{});
        const c = try pool.allocator.create(Self);
        c.* = Self{ .pool = pool };
        for (c.cells, 0..) |_, i| {
            c.cells[i] = null;
        }
        return c;
    }

    pub fn deinit(self: *Self) void {
        std.debug.print("deinit unattached\n", .{});
        inline for (self.cells, 0..) |cell, i| {
            if (cell) |cptr| {
                self.cells[i] = null;
                self.pool.release(cptr);
            }
        }
        self.pool.allocator.destroy(self);
    }

    pub fn add(self: *Self, cell: *Animated) void {
        cell.start();
        // find a free slot
        for (self.cells, 0..) |c, i| {
            if (c) |_| {
                continue;
            } else {
                self.cells[i] = cell;
                return;
            }
        }
    }

    pub fn lerpall(self: *Self) void {
        inline for (self.cells, 0..) |cell, i| {
            if (cell) |cptr| {
                if (cptr.animating) {
                    cptr.lerp(std.time.milliTimestamp());
                } else {
                    self.cells[i] = null;
                    self.pool.release(cptr);
                }
            }
        }
    }
};

pub const Animated = struct {
    const Self = @This();
    id: i128 = 0,
    color: [4]u8 = undefined,
    color_source: [4]u8 = undefined,
    color_target: [4]u8 = undefined,
    source: [2]f32 = undefined,
    target: [2]f32 = undefined,
    position: [2]f32 = undefined,
    source_scale: f32 = 1.0,
    target_scale: f32 = 1.0,
    scale: f32 = 1.0,
    startedat: i64 = 0,
    startnotbefore: i64 = 0,
    duration: i64 = 200,
    animating: bool = false,

    mode: enum {
        easeinout,
        linear,
        easein,
        easeout,
    } = .easeinout,

    // Legacy init function for tests and compatibility
    pub fn init(allocator: std.mem.Allocator, gridx: usize, gridy: usize, color: [4]u8) !*Self {
        // This is a fallback for tests, should not be used in production code
        std.debug.print("WARNING: Using legacy Animated.init, should use pool.create!\n", .{});
        const cell = try allocator.create(Self);
        const p: [2]f32 = .{
            @as(f32, @floatFromInt(gridx * 35)),
            @as(f32, @floatFromInt(gridy * 35)),
        };

        cell.* = Self{
            .source = p,
            .position = p,
            .target = p,
            .color_source = color,
            .color = color,
            .color_target = color,
            .source_scale = 1.0,
            .target_scale = 1.0,
            .scale = 1.0,
        };

        return cell;
    }

    pub fn setcoords(self: *Self, x: usize, y: usize) void {
        const drawx: f32 = @floatFromInt(x * 35);
        const drawy: f32 = @floatFromInt(y * 35);
        self.target[0] = drawx;
        self.target[1] = drawy;
        self.start();
    }

    pub fn setcolor(self: *Self, color: [4]u8) void {
        self.color = color;
        self.color_source = color;
        self.color_target = color;
    }

    pub fn stop(self: *Self) void {
        self.source = self.target;
        self.position = self.target;
        self.source_scale = self.target_scale;
        self.scale = self.target_scale;
        self.color = self.color_target;
        self.animating = false;
    }

    pub fn start(self: *Self) void {
        self.startedat = std.time.milliTimestamp();
        self.source_scale = self.scale;
        self.animating = true;
    }

    pub fn easeinout(self: *Self, t: f32) f32 {
        _ = self;
        return t * t * t * (t * (t * 6 - 15) + 10);
    }
    pub fn easein(self: *Self, t: f32) f32 {
        _ = self;
        return t * t;
    }

    pub fn easeout(self: *Self, t: f32) f32 {
        _ = self;
        return t * (2 - t);
    }

    pub fn lerp(self: *Self, timestamp: i64) void {
        if (!self.animating) {
            return;
        }

        if (std.time.milliTimestamp() < self.startnotbefore) {
            std.debug.print("skipping differed animation\n", .{});
            return;
        }

        const elapsed_time = timestamp - self.startedat;
        if (elapsed_time >= self.duration) {
            if (elapsed_time > self.duration + 20)
                std.debug.print("elapsed:{} > duration:{}\n", .{ elapsed_time, self.duration });
            self.position = self.target;
            self.stop();
            return;
        }

        const e = @as(f32, @floatFromInt(elapsed_time));
        const d = @as(f32, @floatFromInt(self.duration));
        var t = std.math.clamp(e / d, 0.0, 1.0);
        switch (self.mode) {
            .easeinout => t = self.easeinout(t),
            .linear => {},
            .easein => t = self.easein(t),
            .easeout => t = self.easeout(t),
        }

        self.position = .{
            std.math.lerp(self.source[0], self.target[0], t),
            std.math.lerp(self.source[1], self.target[1], t),
        };

        // Lerp the scale
        self.scale = std.math.lerp(self.source_scale, self.target_scale, t);
    }
};

const testing = std.testing;
// test init
test "lerp function" {
    var anim: Animated = undefined;
    anim.animating = true;
    anim.startedat = 0;
    anim.duration = 1000;
    anim.source[0] = 0.0;
    anim.source[1] = 0.0;

    anim.target[0] = 10.0;
    anim.target[1] = 10.0;
    anim.mode = .linear;
    // Call the lerp function with a timestamp of 500
    anim.lerp(500);

    // Assert that the position has been updated correctly
    try testing.expect(anim.position[0] == 5.0);

    // Call the lerp function with a timestamp of 1500
    anim.lerp(1500);

    // Assert that the position has been updated to the target value
    try testing.expect(anim.position[0] == 10.0);

    // Assert that the animation has stopped
    try testing.expect(!anim.animating);
}

test "animation pool" {
    const GPA = std.heap.GeneralPurposeAllocator(.{});
    var gpa = GPA{};

    // Create a pool
    const pool = try AnimationPool.init(gpa.allocator());
    defer pool.deinit();

    // Get a few cells
    const cell1 = pool.create(0, 0, .{ 255, 0, 0, 255 }) orelse unreachable;
    const cell2 = pool.create(1, 1, .{ 0, 255, 0, 255 }) orelse unreachable;
    const cell3 = pool.create(2, 2, .{ 0, 0, 255, 255 }) orelse unreachable;

    // Ensure they have appropriate values
    try testing.expect(cell1.position[0] == 0.0);
    try testing.expect(cell2.position[0] == 35.0);
    try testing.expect(cell3.position[0] == 70.0);

    // Release one cell back to the pool
    pool.release(cell2);

    // Get another cell, this time with different coordinates
    const cell4 = pool.create(3, 3, .{ 255, 255, 0, 255 }) orelse unreachable;
    try testing.expect(cell4.position[0] == 105.0);

    // Test UnattachedAnimating
    const unattached = try UnattachedCell.init(pool);
    defer unattached.deinit();

    // Add an animated cell to unattached
    unattached.add(cell1);
    cell1.duration = 100;
    try testing.expect(cell1.animating);

    // Lerp it past completion
    unattached.lerpall();
    cell1.lerp(cell1.startedat + 200); // Past duration
    unattached.lerpall(); // This should release the cell

    // Verify the cell has been auto-released
    try testing.expect(!cell1.animating);
}
