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
            std.debug.print("Destroying entity {}\n", .{entity});
            world.remove(components.Flash, entity);
            world.remove(components.Sprite, entity);
            world.remove(components.Position, entity);
            world.destroy(entity);
        } else {
            // Update alpha based on remaining time and initial TTL
            const progress = @as(f32, @floatFromInt(time_left_ms)) / @as(f32, @floatFromInt(flash.ttl_ms));
            // Ensure alpha stays within [0,1]
            sprite.rgba[3] = @intFromFloat(std.math.clamp(progress, 0.0, 1.0) * 255.0);

            // Draw the sprite using the current alpha.
            const draw_x = @as(i32, @intFromFloat(pos.x));
            const draw_y = @as(i32, @intFromFloat(pos.y));
            gfx.drawbox(draw_x, draw_y, sprite.rgba, sprite.size);
        }
    }
}
