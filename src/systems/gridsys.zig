const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const components = @import("../components.zig");
const Grid = @import("../grid.zig").Grid;
const game = @import("../game.zig");
const gfx = @import("../gfx.zig");
// The grid rendering system draws the grid from the game's grid data
pub fn gridRenderSystem() void {
    const grid = &game.state.grid;
    // Get window parameters from the game globals
    const window = gfx.window;
    const gridoffsetx = window.gridoffsetx;
    const gridoffsety = window.gridoffsety;
    const cellsize = window.cellsize;
    const cellpadding = window.cellpadding;

    // Draw grid cells
    for (0..Grid.HEIGHT) |y| {
        for (0..Grid.WIDTH) |x| {
            if (grid.data[y][x]) |cell_data| {
                const drawX = @as(i32, @intCast(x)) * cellsize;
                const drawY = @as(i32, @intCast(y)) * cellsize;

                // Calculate scaled dimensions
                const cellsize_scaled = @as(f32, @floatFromInt(cellsize));
                const padding_scaled = @as(f32, @floatFromInt(cellpadding));
                const width_scaled = cellsize_scaled - 2 * padding_scaled;

                // Calculate center of cell in screen coordinates
                const center_x = @as(f32, @floatFromInt(gridoffsetx + drawX)) +
                    @as(f32, @floatFromInt(cellsize)) / 2.0;
                const center_y = @as(f32, @floatFromInt(gridoffsety + drawY)) +
                    @as(f32, @floatFromInt(cellsize)) / 2.0;

                // Calculate top-left drawing position
                const rect_x = center_x - width_scaled / 2.0;
                const rect_y = center_y - width_scaled / 2.0;

                // Draw rounded rectangle
                // Get color from CellData (which packs it as a u32)
                const rgba = cell_data.toRgba();
                ray.DrawRectangleRounded(ray.Rectangle{
                    .x = rect_x,
                    .y = rect_y,
                    .width = width_scaled,
                    .height = width_scaled,
                }, 0.4, // Roundness
                    20, // Segments
                    ray.Color{
                        .r = rgba[0],
                        .g = rgba[1],
                        .b = rgba[2],
                        .a = rgba[3],
                    });
            }
        }
    }
}
