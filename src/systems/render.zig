const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const components = @import("../components.zig");
const game = @import("../game.zig");
const gfx = @import("../gfx.zig");
const shaders = @import("../shaders.zig");

const DEBUG = false;
pub fn drawSprites() void {
    const world = ecs.getWorld();

    // First pass: render entities WITHOUT custom shaders
    var regular_view = world.view(.{ components.Sprite, components.Position, components.Texture }, .{components.Shader});
    var regular_it = regular_view.entityIterator();

    while (regular_it.next()) |entity| {
        const sprite = regular_view.get(components.Sprite, entity);
        const pos = regular_view.get(components.Position, entity);
        const st = regular_view.get(components.Texture, entity);

        const draw_x = @as(i32, @intFromFloat(pos.x));
        const draw_y = @as(i32, @intFromFloat(pos.y));
        drawTextureFromComponent(draw_x, draw_y, st.texture, st, sprite.rgba, sprite.size, sprite.rotation);
    }

    // Second pass: render entities WITH custom shaders
    var shader_view = world.view(.{ components.Sprite, components.Position, components.Texture, components.Shader }, .{});
    var shader_it = shader_view.entityIterator();

    while (shader_it.next()) |entity| {
        const sprite = shader_view.get(components.Sprite, entity);
        const pos = shader_view.get(components.Position, entity);
        const st = shader_view.get(components.Texture, entity);
        const shader_comp = shader_view.get(components.Shader, entity);
        shaders.updateShaderUniforms(entity) catch |err| {
            std.debug.print("Error updating shader uniforms: {}\n", .{err});
        };

        // Apply entity-specific shader
        ray.BeginShaderMode(shader_comp.shader.*);

        const draw_x = @as(i32, @intFromFloat(pos.x));
        const draw_y = @as(i32, @intFromFloat(pos.y));
        drawTextureFromComponent(draw_x, draw_y, st.texture, st, sprite.rgba, sprite.size, sprite.rotation);

        // End entity-specific shader
        ray.EndShaderMode();
    }
}

// Draw a render texture with scaling and rotation using Texture component
pub fn drawTextureFromComponent(x: i32, y: i32, texture: *const ray.RenderTexture2D, tex_component: *const components.Texture, tint: [4]u8, scale: f32, rotation: f32) void {
    gfx.drawTexture(x, y, texture, tex_component.*.uv, tint, scale, rotation);
}
