const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const components = @import("../components.zig");
const Grid = @import("../grid.zig").Grid;
const game = @import("../game.zig");
const gfx = @import("../gfx.zig");

pub fn drawSprites() void {
    const world = ecs.getWorld();

    // First pass: entities with UV textures (using the atlas)
    var uvtexture_view = world.view(.{ components.Sprite, components.Position, components.UVTexture }, .{});
    var uvtexture_it = uvtexture_view.entityIterator();

    while (uvtexture_it.next()) |entity| {
        const sprite = uvtexture_view.get(components.Sprite, entity);
        const pos = uvtexture_view.get(components.Position, entity);
        const uvt = uvtexture_view.get(components.UVTexture, entity);

        // Draw the texture with rotation and scaling
        const draw_x = @as(i32, @intFromFloat(pos.x));
        const draw_y = @as(i32, @intFromFloat(pos.y));

        drawUVTexture(draw_x, draw_y, uvt.texture, uvt.uv, sprite.rgba, sprite.size, sprite.rotation);
    }

    // // Second pass: entities with regular textures (legacy)
    // var texture_view = world.view(.{ components.Sprite, components.Position, components.Texture }, .{components.UVTexture});
    // var texture_it = texture_view.entityIterator();

    // while (texture_it.next()) |entity| {
    //     const sprite = texture_view.get(components.Sprite, entity);
    //     const pos = texture_view.get(components.Position, entity);
    //     const st = texture_view.get(components.Texture, entity);

    //     // Draw the texture with rotation and scaling
    //     const draw_x = @as(i32, @intFromFloat(pos.x));
    //     const draw_y = @as(i32, @intFromFloat(pos.y));

    //     drawTexture(draw_x, draw_y, st.texture, sprite.rgba, sprite.size, sprite.rotation);
    // }

    // entities without textures (using standard box rendering)
    // var view = world.view(.{ components.Sprite, components.Position }, .{components.Texture, components.UVTexture});
    // var it = view.entityIterator();

    // while (it.next()) |entity| {
    //     const sprite = view.get(components.Sprite, entity);
    //     const pos = view.get(components.Position, entity);

    //     // Draw the static block
    //     const draw_x = @as(i32, @intFromFloat(pos.x));
    //     const draw_y = @as(i32, @intFromFloat(pos.y));

    //     drawbox(draw_x, draw_y, sprite.rgba, sprite.size, sprite.rotation);
    // }
}

// Draw a rounded box with scale factor applied and rotation
pub fn drawbox(x: i32, y: i32, color: [4]u8, scale: f32, rotation: f32) void {
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

    // Create a rectangle centered on the draw position
    const rect = ray.Rectangle{
        .x = rect_x,
        .y = rect_y,
        .width = width_scaled,
        .height = width_scaled, // Same as width for perfect square
    };

    const ray_color = ray.Color{
        .r = color[0],
        .g = color[1],
        .b = color[2],
        .a = color[3],
    };

    if (rotation != 0) {
        ray.DrawRectanglePro(rect, ray.Vector2{ .x = width_scaled / 2.0, .y = width_scaled / 2.0 }, // Origin (center of rectangle)
            rotation * 360.0, // Convert rotations to degrees (e.g., 1.0 = 360 degrees)
            ray_color);
    } else {
        ray.DrawRectangleRounded(rect, 0.4, // Roundness
            20, // Segments
            ray_color);
    }
}

// Draw a render texture or texture from an atlas with scaling and rotation
pub fn drawTexture(x: i32, y: i32, texture: *const ray.RenderTexture2D, tint: [4]u8, scale: f32, rotation: f32) void {
    // For regular textures, use the entire texture as source
    const uv = [4]f32{ 0, 0, 1, 1 };
    drawTextureWithUV(x, y, texture, uv, tint, scale, rotation);
}

// Draw a texture from an atlas using UV coordinates
pub fn drawUVTexture(x: i32, y: i32, texture: *const ray.RenderTexture2D, uv: [4]f32, tint: [4]u8, scale: f32, rotation: f32) void {
    drawTextureWithUV(x, y, texture, uv, tint, scale, rotation);
}

// Common implementation for both texture drawing functions
fn drawTextureWithUV(x: i32, y: i32, texture: *const ray.RenderTexture2D, uv: [4]f32, tint: [4]u8, scale: f32, rotation: f32) void {
    // Calculate scaled dimensions
    const cellsize_scaled = @as(f32, @floatFromInt(gfx.window.cellsize)) * scale;

    // Calculate center of cell in screen coordinates, applying window scale factor
    const center_x = @as(f32, @floatFromInt(gfx.window.gridoffsetx + x)) +
        @as(f32, @floatFromInt(gfx.window.cellsize)) / 2.0;
    const center_y = @as(f32, @floatFromInt(gfx.window.gridoffsety + y)) +
        @as(f32, @floatFromInt(gfx.window.cellsize)) / 2.0;

    // Source rectangle (portion of the atlas texture defined by UV coordinates)
    const src = ray.Rectangle{
        .x = uv[0] * @as(f32, @floatFromInt(texture.*.texture.width)),
        .y = uv[1] * @as(f32, @floatFromInt(texture.*.texture.height)),
        .width = (uv[2] - uv[0]) * @as(f32, @floatFromInt(texture.*.texture.width)),
        .height = -(uv[3] - uv[1]) * @as(f32, @floatFromInt(texture.*.texture.height)), // Negative to flip the texture vertically (render texture is flipped)
    };

    // Destination rectangle (centered on the position with proper scaling)
    const dest = ray.Rectangle{
        .x = center_x,
        .y = center_y,
        .width = cellsize_scaled,
        .height = cellsize_scaled,
    };

    // Origin (center of the texture)
    const origin = ray.Vector2{
        .x = cellsize_scaled / 2.0,
        .y = cellsize_scaled / 2.0,
    };

    // Convert color array to raylib Color
    const ray_color = ray.Color{
        .r = tint[0],
        .g = tint[1],
        .b = tint[2],
        .a = tint[3],
    };

    // Draw the texture with rotation
    ray.DrawTexturePro(texture.*.texture, src, dest, origin, rotation * 360.0, // Convert rotations to degrees
        ray_color);
}
