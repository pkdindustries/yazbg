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
            world.remove(RowFall, entity);
            world.remove(components.Position, entity);
            world.remove(components.Sprite, entity);
            world.destroy(entity);
        }
    }
}

// Create new falling row effects for cleared lines
pub fn createFallingRow(row_y: usize, existing_entities: []const ecsroot.Entity) void {
    const window = gfx.window;
    const world = ecs.getWorld();

    // Create new animation entities based on the cleared row's entities
    for (existing_entities) |old_entity| {
        // Get position and sprite from the original entity
        if (ecs.get(components.Position, old_entity)) |old_position| {
            var sprite_color: [4]u8 = .{ 255, 255, 255, 255 };

            if (ecs.get(components.Sprite, old_entity)) |old_sprite| {
                sprite_color = old_sprite.rgba;
            }

            // Create a new entity for the falling animation
            const new_entity = world.create();

            // Start position is the same as the original entity
            const start_y_pos = old_position.y;

            // Target position is off the bottom of the screen
            const target_y_pos = @as(f32, @floatFromInt(window.height + 100));

            // Add necessary components to the new entity
            world.add(new_entity, RowFall{
                .y = row_y,
                .start_y = start_y_pos,
                .target_y = target_y_pos,
                .start_time = std.time.milliTimestamp(),
                .duration = 300,
                .opacity = 1.0,
            });

            // Add Position component with the same x position
            world.add(new_entity, components.Position{
                .x = old_position.x,
                .y = start_y_pos,
            });

            // Add Sprite component with the same color
            world.add(new_entity, components.Sprite{
                .rgba = sprite_color,
                .size = 1.0,
            });
        }
    }

    // Original entities should be destroyed immediately
    for (existing_entities) |entity| {
        world.destroy(entity);
    }
}
//
