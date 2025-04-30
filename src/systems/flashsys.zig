const std = @import("std");
const ecs = @import("../ecs.zig");
const components = @import("../components.zig");
const gfx = @import("../gfx.zig");

pub fn flashSystem() void {
    const world = ecs.getWorld();

    // position, flash, sprite
    var view = world.view(.{ components.Flash, components.Sprite, components.Position }, .{});
    var it = view.entityIterator();

    // Use wall clock time directly
    const current_time_ms = std.time.milliTimestamp();

    while (it.next()) |entity| {
        const flash = view.get(components.Flash, entity);
        var sprite = view.get(components.Sprite, entity);
        const pos = view.get(components.Position, entity);

        const time_left_ms = flash.expires_at_ms - current_time_ms;

        if (time_left_ms <= 0) {
            std.debug.print("Flash expired for entity {}, removing Flash component\n", .{entity});

            world.remove(components.Flash, entity);
            // reset alpha
            sprite.rgba[3] = 255;
        } else {
            const progress = @as(f32, @floatFromInt(time_left_ms)) / @as(f32, @floatFromInt(flash.ttl_ms));
            sprite.rgba[3] = @intFromFloat(std.math.clamp(progress, 0.0, 1.0) * 255.0);
            const draw_x = @as(i32, @intFromFloat(pos.x));
            const draw_y = @as(i32, @intFromFloat(pos.y));
            gfx.drawbox(draw_x, draw_y, sprite.rgba, sprite.size);
        }
    }
}
