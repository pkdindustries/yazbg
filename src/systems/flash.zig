const std = @import("std");
const ecs = @import("../ecs.zig");
const components = @import("../components.zig");

pub fn flashSystem() void {
    const world = ecs.getWorld();
    var view = world.view(.{ components.Flash, components.Sprite }, .{});
    var it = view.entityIterator();

    // Use wall clock time directly
    const current_time_ms = std.time.milliTimestamp();

    // Only log if we have entities to process
    var entity_count: usize = 0;

    while (it.next()) |entity| {
        entity_count += 1;
        var flash = view.get(components.Flash, entity);
        var sprite = view.get(components.Sprite, entity);

        // Age calculation - first frame, initialize creation time
        if (flash.ttl_ms == 50) {
            flash.ttl_ms = current_time_ms + 50; // Store expiration time
            std.debug.print("Entity {} TTL initialized, expires at {}\n", .{ entity, flash.ttl_ms });
        }

        // Time left = expiration time - current time
        const time_left_ms = flash.ttl_ms - current_time_ms;

        // Debug logging
        // std.debug.print("Entity {} time left: {}ms (expires at: {}, now: {})\n",
        //        .{entity, time_left_ms, flash.ttl_ms, current_time_ms});

        if (time_left_ms <= 0) {
            std.debug.print("Destroying entity {}\n", .{entity});
            world.remove(components.Flash, entity);
            world.remove(components.Sprite, entity);
            world.remove(components.Position, entity);
            world.destroy(entity);
        } else {
            // Update alpha based on remaining time and initial TTL
            const progress = @as(f32, @floatFromInt(time_left_ms)) / 120.0;
            // Ensure alpha doesn't wrap around or go negative
            sprite.rgba[3] = @intFromFloat(std.math.clamp(progress, 0.0, 1.0) * 255.0);
        }
    }

    if (entity_count > 0) {
        // std.debug.print("FlashSystem processed {} entities\n", .{entity_count});
    }
}
