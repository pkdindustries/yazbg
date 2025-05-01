const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const ecsroot = @import("ecs");
const components = @import("../components.zig");
const gfx = @import("../gfx.zig");
const events = @import("../events.zig");
const Grid = @import("../grid.zig").Grid;
const game = @import("../game.zig");
// New component for falling row animation
pub const RowFall = struct {
    y: usize, // original row position
    start_y: f32, // starting y position in pixels
    target_y: f32, // target y position in pixels (offscreen)
    start_time: i64, // when animation started
    duration: i64, // animation duration in ms
    opacity: f32, // current opacity (decreases as row falls)
};

// create falling row effects
pub fn rowFallSystem() void {
    const world = ecs.getWorld(); // Update existing falling row entities
    var view = world.view(.{ RowFall, components.Position, components.Sprite }, .{});
    var it = view.entityIterator();

    const current_time = std.time.milliTimestamp();

    while (it.next()) |entity| {
        var row_fall = view.get(RowFall, entity);
        var position = view.get(components.Position, entity);

        // Calculate progress (0.0 to 1.0)
        const elapsed = current_time - row_fall.start_time;
        const progress = @min(@as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(row_fall.duration)), 1.0);

        // Apply easeOut function: 1 - (1 - progress)^2
        const eased = 1.0 - std.math.pow(f32, 1.0 - progress, 2.0);

        // Update position using lerp
        position.y = row_fall.start_y + (row_fall.target_y - row_fall.start_y) * eased;

        // Decrease opacity as the row falls (based on progress)
        row_fall.opacity = 1.0;

        // Check if animation is complete
        if (progress >= 1.0) {
            std.debug.print("RowFallSystem: Destroying entity {}\n", .{entity});
            world.remove(RowFall, entity);
            world.remove(components.Position, entity);
            world.remove(components.Sprite, entity);
            world.destroy(entity);
        }
    }
}

// Create falling row effects from existing entities
pub fn createFallingRow(row_y: usize, existing_entities: []const ecsroot.Entity) void {
    std.debug.print("Converting {} entities in row {} to falling blocks\n", .{ existing_entities.len, row_y });
    const window = gfx.window;
    const world = ecs.getWorld();

    // Process all existing entities from the cleared row
    for (existing_entities) |entity| {
        // Get the current position
        if (ecs.get(components.Position, entity)) |position| {
            const start_y_pos = position.y;

            // Target position is off the bottom of the screen
            const target_y_pos = @as(f32, @floatFromInt(window.height + 100));

            // Add RowFall component to handle the animation
            world.add(entity, RowFall{
                .y = row_y,
                .start_y = start_y_pos,
                .target_y = target_y_pos,
                .start_time = std.time.milliTimestamp(),
                .duration = 400, // 350 ms for the fall
                .opacity = 0.5,
            });
        }
    }
}
//
