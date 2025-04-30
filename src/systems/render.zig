const std = @import("std");
const ecs = @import("../ecs.zig");
const components = @import("../components.zig");
const gfx = @import("../gfx.zig");

pub fn blockRenderSystem() void {
    const world = ecs.getWorld();
    var view = world.view(.{ components.Position, components.Sprite }, .{});
    var it = view.entityIterator();

    while (it.next()) |entity| {
        const pos = view.get(components.Position, entity);
        const sprite = view.get(components.Sprite, entity);
        // Position is in grid-relative coordinates, without the grid offset
        // drawbox will add the offset during rendering
        gfx.drawbox(@intFromFloat(pos.x), @intFromFloat(pos.y), sprite.rgba, sprite.size);
    }
}
