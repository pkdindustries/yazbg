const std = @import("std");

pub var ng = std.rand.DefaultPrng.init(0);

pub fn init() !void {
    std.debug.print("init rng\n", .{});
    ng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.os.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
}

pub fn deinit() void {
    std.debug.print("deinit rng\n", .{});
    ng = undefined;
}
