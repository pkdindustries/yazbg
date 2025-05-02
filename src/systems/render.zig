const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const components = @import("../components.zig");
const Grid = @import("../grid.zig").Grid;
const game = @import("../game.zig");
const gfx = @import("../gfx.zig");

const DEBUG = false;
pub fn drawSprites() void {
    const world = ecs.getWorld();

    // First pass: entities with textures
    var texture_view = world.view(.{ components.Sprite, components.Position, components.Texture }, .{});
    var texture_it = texture_view.entityIterator();

    while (texture_it.next()) |entity| {
        const sprite = texture_view.get(components.Sprite, entity);
        const pos = texture_view.get(components.Position, entity);
        const st = texture_view.get(components.Texture, entity);

        // Draw the texture with rotation and scaling
        const draw_x = @as(i32, @intFromFloat(pos.x));
        const draw_y = @as(i32, @intFromFloat(pos.y));

        drawTexture(draw_x, draw_y, st.texture, st, sprite.rgba, sprite.size, sprite.rotation);
    }
}

// Convert RGBA array to raylib Color
fn toRayColor(color: [4]u8) ray.Color {
    return ray.Color{
        .r = color[0],
        .g = color[1],
        .b = color[2],
        .a = color[3],
    };
}

// Calculate the center position of a cell in screen coordinates
fn getCellCenter(x: i32, y: i32) struct { x: f32, y: f32 } {
    return .{
        .x = @as(f32, @floatFromInt(gfx.window.gridoffsetx + x)) +
            @as(f32, @floatFromInt(gfx.window.cellsize)) / 2.0,
        .y = @as(f32, @floatFromInt(gfx.window.gridoffsety + y)) +
            @as(f32, @floatFromInt(gfx.window.cellsize)) / 2.0,
    };
}

// Convert rotation value to degrees
fn rotationToDegrees(rotation: f32) f32 {
    return rotation * 360.0;
}

// Draw a render texture with scaling and rotation
pub fn drawTexture(x: i32, y: i32, texture: *const ray.RenderTexture2D, tex_component: *const components.Texture, tint: [4]u8, scale: f32, rotation: f32) void {
    // Calculate scaled dimensions
    const cellsize_scaled = @as(f32, @floatFromInt(gfx.window.cellsize)) * scale;

    // Get center of cell
    const center = getCellCenter(x, y);

    // Source rectangle (using UV coordinates from the Texture component)
    const texture_width = @as(f32, @floatFromInt(texture.*.texture.width));
    const texture_height = @as(f32, @floatFromInt(texture.*.texture.height));

    // Fix for render texture handling in raylib - RenderTextures are y-flipped
    // We need to change how we access the texture to compensate
    const src = ray.Rectangle{
        .x = tex_component.*.uv[0] * texture_width,
        .y = (1.0 - tex_component.*.uv[3]) * texture_height, // Start from bottom of the region
        .width = (tex_component.*.uv[2] - tex_component.*.uv[0]) * texture_width,
        .height = (tex_component.*.uv[3] - tex_component.*.uv[1]) * texture_height, // Use positive height
    };

    if (DEBUG)
        std.debug.print("Src rect: x={d:.1}, y={d:.1}, w={d:.1}, h={d:.1}\n", .{ src.x, src.y, src.width, src.height });

    // Destination rectangle (centered on the position with proper scaling)
    const dest = ray.Rectangle{
        .x = center.x,
        .y = center.y,
        .width = cellsize_scaled,
        .height = cellsize_scaled,
    };

    if (DEBUG)
        std.debug.print("Dest rect: x={d:.1}, y={d:.1}, w={d:.1}, h={d:.1}\n", .{ dest.x, dest.y, dest.width, dest.height });

    // Origin (center of the texture)
    const origin = ray.Vector2{
        .x = cellsize_scaled / 2.0,
        .y = cellsize_scaled / 2.0,
    };

    if (DEBUG)
        std.debug.print("Drawing with rotation: {d:.1}°, tint: [{}, {}, {}, {}]\n", .{ rotationToDegrees(rotation), tint[0], tint[1], tint[2], tint[3] });

    // Draw the texture with rotation
    ray.DrawTexturePro(texture.*.texture, src, dest, origin, rotationToDegrees(rotation), toRayColor(tint));
}
