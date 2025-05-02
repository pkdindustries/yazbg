const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const components = @import("../components.zig");
const Grid = @import("../grid.zig").Grid;
const game = @import("../game.zig");
const gfx = @import("../gfx.zig");

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

    // Second pass: entities without textures (using standard box rendering)
    var view = world.view(.{ components.Sprite, components.Position }, .{components.Texture});
    var it = view.entityIterator();

    while (it.next()) |entity| {
        const sprite = view.get(components.Sprite, entity);
        const pos = view.get(components.Position, entity);

        // Draw the static block
        const draw_x = @as(i32, @intFromFloat(pos.x));
        const draw_y = @as(i32, @intFromFloat(pos.y));

        drawbox(draw_x, draw_y, sprite.rgba, sprite.size, sprite.rotation);
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

// Draw a rounded box with scale factor applied and rotation
pub fn drawbox(x: i32, y: i32, color: [4]u8, scale: f32, rotation: f32) void {
    // Calculate scaled dimensions
    const cellsize_scaled = @as(f32, @floatFromInt(gfx.window.cellsize)) * scale;
    const padding_scaled = @as(f32, @floatFromInt(gfx.window.cellpadding)) * scale;
    const width_scaled = cellsize_scaled - 2 * padding_scaled;

    // Get center of cell
    const center = getCellCenter(x, y);

    // Calculate top-left drawing position
    const rect_x = center.x - width_scaled / 2.0;
    const rect_y = center.y - width_scaled / 2.0; // Width used for height to ensure square

    // Create a rectangle centered on the draw position
    const rect = ray.Rectangle{
        .x = rect_x,
        .y = rect_y,
        .width = width_scaled,
        .height = width_scaled, // Same as width for perfect square
    };

    const ray_color = toRayColor(color);

    if (rotation != 0) {
        ray.DrawRectanglePro(rect, ray.Vector2{ .x = width_scaled / 2.0, .y = width_scaled / 2.0 }, // Origin (center of rectangle)
            rotationToDegrees(rotation), ray_color);
    } else {
        ray.DrawRectangleRounded(rect, 0.4, // Roundness
            20, // Segments
            ray_color);
    }
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
    const src = ray.Rectangle{
        .x = tex_component.*.uv[0] * texture_width,
        .y = tex_component.*.uv[1] * texture_height,
        .width = (tex_component.*.uv[2] - tex_component.*.uv[0]) * texture_width,
        .height = -(tex_component.*.uv[3] - tex_component.*.uv[1]) * texture_height, // Negative to flip the texture vertically (render texture is flipped)
    };

    // Destination rectangle (centered on the position with proper scaling)
    const dest = ray.Rectangle{
        .x = center.x,
        .y = center.y,
        .width = cellsize_scaled,
        .height = cellsize_scaled,
    };

    // Origin (center of the texture)
    const origin = ray.Vector2{
        .x = cellsize_scaled / 2.0,
        .y = cellsize_scaled / 2.0,
    };

    // Draw the texture with rotation
    ray.DrawTexturePro(texture.*.texture, src, dest, origin, rotationToDegrees(rotation), toRayColor(tint));
}
