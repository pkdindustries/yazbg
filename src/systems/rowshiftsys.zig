const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const ecsroot = @import("ecs");
const components = @import("../components.zig");

// Component for animating row shift down
// This is purely visual - the grid position is already updated in the game logic
pub const RowShift = struct {
    start_pos_y: f32, // starting y position in pixels
    target_pos_y: f32, // target y position in pixels
    start_time: i64, // when animation started
    duration: i64, // animation duration in ms
};

// System that updates row shift animations
pub fn rowShiftSystem() void {
    const world = ecs.getWorld();
    var view = world.view(.{ RowShift, components.Position, components.Sprite }, .{});
    var it = view.entityIterator();

    const current_time = std.time.milliTimestamp();
    var entities_to_update: [128]ecsroot.Entity = undefined;
    var num_entities: usize = 0;

    while (it.next()) |entity| {
        const row_shift = view.get(RowShift, entity);

        var position = view.get(components.Position, entity);

        // Calculate progress (0.0 to 1.0)
        const elapsed = current_time - row_shift.start_time;
        const progress = @min(@as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(row_shift.duration)), 1.0);

        // Apply easeOutQuad function: 1 - (1 - progress)^2
        const eased = 1.0 - std.math.pow(f32, 1.0 - progress, 2.0);

        // Update visual position using lerp
        position.y = row_shift.start_pos_y + (row_shift.target_pos_y - row_shift.start_pos_y) * eased;

        // Check if animation is complete
        if (progress >= 1.0) {
            // Remove the RowShift component, animation is done
            if (num_entities < entities_to_update.len) {
                entities_to_update[num_entities] = entity;
                num_entities += 1;
            }
        }
    }

    // Remove RowShift components from completed animations
    for (entities_to_update[0..num_entities]) |entity| {
        world.remove(RowShift, entity);
    }
}

//  function to create row shift animation for a specific entity
pub fn addRowShiftAnim(entity: ecsroot.Entity, from_y: f32, to_y: f32) void {
    const world = ecs.getWorld();

    // Only add the animation if the entity has a Position component
    // and doesn't already have a RowShift component
    if (ecs.get(components.Position, entity)) |_| {
        // Remove any existing RowShift component first to avoid conflicts
        if (world.has(RowShift, entity)) {
            world.remove(RowShift, entity);
        }

        // Now add the new RowShift component
        world.add(entity, RowShift{
            .start_pos_y = from_y,
            .target_pos_y = to_y,
            .start_time = std.time.milliTimestamp(),
            .duration = 200, // 200ms for the shift animation
        });
    }
}
