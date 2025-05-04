const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const components = @import("../components.zig");
const Grid = @import("../grid.zig").Grid;
const game = @import("../game.zig");
const gfx = @import("../gfx.zig");
const shaders = @import("../shaders.zig");

const DEBUG = false;
pub fn drawSprites() void {
    const world = ecs.getWorld();

    // First pass: entities with textures but no custom shader (using global shader)
    var texture_view = world.view(.{ components.Sprite, components.Position, components.Texture }, .{components.Shader});
    var texture_it = texture_view.entityIterator();

    while (texture_it.next()) |entity| {
        const sprite = texture_view.get(components.Sprite, entity);
        const pos = texture_view.get(components.Position, entity);
        const st = texture_view.get(components.Texture, entity);
        
        // Check if entity has a custom shader
        if (ecs.has(components.Shader, entity)) {
            const shader_comp = ecs.getUnchecked(components.Shader, entity);
            // Use entity-specific shader
            ray.BeginShaderMode(shader_comp.shader.*);
            
            // Draw the texture with the entity-specific shader
            const draw_x = @as(i32, @intFromFloat(pos.x));
            const draw_y = @as(i32, @intFromFloat(pos.y));
            drawTextureFromComponent(draw_x, draw_y, st.texture, st, sprite.rgba, sprite.size, sprite.rotation);
            
            // End entity-specific shader
            ray.EndShaderMode();
        } else {
            // Draw with the currently active shader (set by gfx.frame())
            const draw_x = @as(i32, @intFromFloat(pos.x));
            const draw_y = @as(i32, @intFromFloat(pos.y));
            drawTextureFromComponent(draw_x, draw_y, st.texture, st, sprite.rgba, sprite.size, sprite.rotation);
        }
    }
}

// Draw a render texture with scaling and rotation using Texture component
pub fn drawTextureFromComponent(x: i32, y: i32, texture: *const ray.RenderTexture2D, tex_component: *const components.Texture, tint: [4]u8, scale: f32, rotation: f32) void {
    gfx.drawTexture(x, y, texture, tex_component.*.uv, tint, scale, rotation);
}
