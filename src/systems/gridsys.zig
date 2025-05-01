const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const components = @import("../components.zig");
const Grid = @import("../grid.zig").Grid;
const game = @import("../game.zig");
const gfx = @import("../gfx.zig");

// The grid rendering system draws the static blocks on the grid
pub fn renderSystem() void {
    renderBlocks();
}

fn renderBlocks() void {
    const world = ecs.getWorld();

    var view = world.view(.{ components.BlockTag, components.GridPos, components.Sprite, components.Position }, .{}); // Include all blocks, even those with Flash

    var it = view.entityIterator();

    while (it.next()) |entity| {
        const sprite = view.get(components.Sprite, entity);
        const pos = view.get(components.Position, entity);

        // Draw the static block
        const draw_x = @as(i32, @intFromFloat(pos.x));
        const draw_y = @as(i32, @intFromFloat(pos.y));

        gfx.drawbox(draw_x, draw_y, sprite.rgba, sprite.size);
    }
}
