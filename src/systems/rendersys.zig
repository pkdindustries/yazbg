const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const components = @import("../components.zig");
const Grid = @import("../grid.zig").Grid;
const game = @import("../game.zig");
const gfx = @import("../gfx.zig");

pub fn renderSystem() void {
    drawSprites();
}

pub fn drawSprites() void {
    const world = ecs.getWorld();

    var view = world.view(.{ components.Sprite, components.Position }, .{}); // Include all blocks, even those with Flash
    var it = view.entityIterator();

    while (it.next()) |entity| {
        const sprite = view.get(components.Sprite, entity);
        const pos = view.get(components.Position, entity);

        // Draw the static block
        const draw_x = @as(i32, @intFromFloat(pos.x));
        const draw_y = @as(i32, @intFromFloat(pos.y));

        drawbox(draw_x, draw_y, sprite.rgba, sprite.size);
    }
}

// Draw a rounded box with scale factor applied
pub fn drawbox(x: i32, y: i32, color: [4]u8, scale: f32) void {
    // Calculate scaled dimensions
    const cellsize_scaled = @as(f32, @floatFromInt(gfx.window.cellsize)) * scale;
    const padding_scaled = @as(f32, @floatFromInt(gfx.window.cellpadding)) * scale;
    const width_scaled = cellsize_scaled - 2 * padding_scaled;

    // Calculate center of cell in screen coordinates, applying window scale factor
    const center_x = @as(f32, @floatFromInt(gfx.window.gridoffsetx + x)) +
        @as(f32, @floatFromInt(gfx.window.cellsize)) / 2.0;
    const center_y = @as(f32, @floatFromInt(gfx.window.gridoffsety + y)) +
        @as(f32, @floatFromInt(gfx.window.cellsize)) / 2.0;

    // Calculate top-left drawing position
    const rect_x = center_x - width_scaled / 2.0;
    const rect_y = center_y - width_scaled / 2.0; // Width used for height to ensure square

    // Draw rounded rectangle
    ray.DrawRectangleRounded(ray.Rectangle{
        .x = rect_x,
        .y = rect_y,
        .width = width_scaled,
        .height = width_scaled, // Same as width for perfect square
    }, 0.4, // Roundness
        20, // Segments
        ray.Color{
            .r = color[0],
            .g = color[1],
            .b = color[2],
            .a = color[3],
        });
}
