const std = @import("std");
const game = @import("game.zig");

const MAX_ANIMATED = 500;
pub const UnattachedAnimating = struct {
    const Self = @This();
    allocator: std.mem.Allocator = undefined,
    cells: [MAX_ANIMATED]?*Animated = undefined,

    pub fn init(allocator: std.mem.Allocator) !*Self {
        std.debug.print("init unattached\n", .{});
        const c = try allocator.create(Self);
        c.* = Self{ .allocator = allocator };
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
                self.allocator.destroy(cptr);
            }
        }
        self.allocator.destroy(self);
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
                    self.allocator.destroy(cptr);
                }
            }
        }
    }
};

pub const Animated = struct {
    const Self = @This();
    id: i128 = 0,
    color: [4]u8 = undefined,
    source: [2]f32 = undefined,
    target: [2]f32 = undefined,
    position: [2]f32 = undefined,
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

    pub fn init(allocator: std.mem.Allocator, gridx: usize, gridy: usize, color: [4]u8) !*Self {
        const p: [2]f32 = .{
            @as(f32, @floatFromInt(gridx * 35)),
            @as(f32, @floatFromInt(gridy * 35)),
        };

        const cell = try allocator.create(Self);
        cell.* = Self{
            .source = p,
            .position = p,
            .target = p,
            .color = color,
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
        self.colorposition = color;
        self.colortarget = color;
    }

    pub fn stop(self: *Self) void {
        self.source = self.target;
        self.position = self.target;
        self.animating = false;
    }

    pub fn start(self: *Self) void {
        self.startedat = std.time.milliTimestamp();
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
    }

    // set a row to random x,y
    pub fn linesplat(row: usize) void {
        inline for (game.state.grid.cells[row], 0..) |ac, i| {
            if (ac) |cptr| {
                const xr: i32 = game.state.rng.random().intRangeAtMost(i32, -2000, 2000);
                const yr: i32 = game.state.rng.random().intRangeAtMost(i32, -2000, 2000);
                cptr.target[0] = @as(f32, @floatFromInt(xr));
                cptr.target[1] = @as(f32, @floatFromInt(yr));
                cptr.duration = 1000;
                cptr.mode = .easein;
                game.state.grid.unattached.add(cptr);
                game.state.grid.cells[row][i] = null;
                cptr.start();
            }
        }
    }

    pub fn linecleardown(row: usize) void {
        inline for (game.state.grid.cells[row], 0..) |ac, i| {
            if (ac) |cptr| {
                cptr.target[1] = 800;
                cptr.duration = 1000;
                cptr.mode = .easeout;
                game.state.grid.unattached.add(cptr);
                game.state.grid.cells[row][i] = null;
                cptr.start();
            }
        }
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
