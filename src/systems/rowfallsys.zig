const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
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
        const sprite = view.get(components.Sprite, entity);

        // Calculate progress (0.0 to 1.0)
        const elapsed = current_time - row_fall.start_time;
        const progress = @min(@as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(row_fall.duration)), 1.0);

        // Apply easeOut function: 1 - (1 - progress)^2
        const eased = 1.0 - std.math.pow(f32, 1.0 - progress, 2.0);

        // Update position using lerp
        position.y = row_fall.start_y + (row_fall.target_y - row_fall.start_y) * eased;

        // Decrease opacity as the row falls (based on progress)
        row_fall.opacity = 1.0;

        // Draw the falling block
        const draw_x = @as(i32, @intFromFloat(position.x));
        const draw_y = @as(i32, @intFromFloat(position.y));
        std.debug.print("RowFallSystem: Drawing entity {} progress {} at ({}, {}) with opacity {}\n", .{ entity, progress, draw_x, draw_y, row_fall.opacity });

        gfx.drawbox(draw_x, draw_y, sprite.rgba, sprite.size);

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

// Create entities for a falling row effect
pub fn createFallingRowEntities(row_y: usize) void {
    std.debug.print("Creating falling row entities for row {}\n", .{row_y});
    const window = gfx.window;
    const gridoffsetx = window.gridoffsetx;
    const gridoffsety = window.gridoffsety;
    const cellsize = window.cellsize;

    // For each cell in the row, create a falling entity
    for (0..Grid.WIDTH) |x| {
        // Create an entity for this cell
        const entity = ecs.createEntity();

        // Calculate screen position
        const screen_x = gridoffsetx + @as(i32, @intCast(x)) * cellsize;
        const screen_y = gridoffsety + @as(i32, @intCast(row_y)) * cellsize;

        // this will directly query entities with BlockTag components.. someday
        const grid = game.state.grid;
        if (x < Grid.WIDTH and row_y < Grid.HEIGHT and grid.data[row_y][x] == null) {
            // Skip creating entities for empty cells
            ecs.getWorld().destroy(entity);
            continue;
        }

        // Get cell color
        const color = grid.data[row_y][x].?.toRgba();

        // Calculate animation parameters
        const start_y_pos = @as(f32, @floatFromInt(screen_y));

        // Target is off screen - add random horizontal drift for more natural look
        const random_drift = @as(f32, @floatFromInt(@mod(std.time.milliTimestamp() + @as(i64, @intCast(x)) * 10, 100))) / 50.0 - 1.0; // -1.0 to 1.0
        const target_y_pos = @as(f32, @floatFromInt(window.height + 100));

        // Add components
        ecs.addPosition(entity, @as(f32, @floatFromInt(screen_x)) + random_drift * 10.0, start_y_pos);
        ecs.addSprite(entity, color, 1.0);

        // Add our custom RowFall component with easing parameters
        const world = ecs.getWorld();
        world.add(entity, RowFall{
            .y = row_y,
            .start_y = start_y_pos,
            .target_y = target_y_pos,
            .start_time = std.time.milliTimestamp(),
            // NOTE: the intent is to have the row fall fairly quickly – roughly a
            // quarter of a second. The extra two zeros slipped in during the
            // initial implementation made the duration **25 000 ms** (25 s)
            // instead of **250 ms**. This caused the animation to move almost
            // imperceptibly and appear "stuck". Restoring the intended value
            // makes the effect visible again.
            .duration = 250, // 250 ms for the fall
            .opacity = 1.0,
        });
    }
}
//
