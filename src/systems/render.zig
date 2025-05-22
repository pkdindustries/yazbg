const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const components = @import("../components.zig");
const gfx = @import("../gfx.zig");
const shaders = @import("../shaders.zig");

// ---------------------------------------------------------------------------
// Rendering system – two passes:
//   1. Entities without any Shader component.
//   2. Entities grouped by the shader-type tag component so that we can issue
//      one BeginShaderMode/EndShaderMode pair per shader.
// ---------------------------------------------------------------------------

pub fn draw() void {
    const world = ecs.getWorld();

    // ----------------------------------------------------------
    // Pass 1: plain sprites (no Shader component attached)
    // ----------------------------------------------------------

    var regular_group = world.group(
        .{},
        .{ components.Sprite, components.Position, components.Texture },
        .{ components.Shader },
    );

    var it = regular_group.iterator();
    while (it.next()) |ent| {
        const sprite = regular_group.get(components.Sprite, ent);
        const pos    = regular_group.get(components.Position, ent);
        const tex    = regular_group.get(components.Texture, ent);

        drawTexturedSquare(@intFromFloat(pos.x), @intFromFloat(pos.y), tex.texture,
            tex, sprite.rgba, sprite.size, sprite.rotation);
    }

    // ----------------------------------------------------------
    // Pass 2: one sub-pass per known shader tag component
    // ----------------------------------------------------------

    const ShaderTagTypes = .{
        components.StaticShaderTag,
        components.GlitchShaderTag,
        components.WarpShaderTag,
    };

    inline for (ShaderTagTypes) |TagType| {
        var shader_group = world.group(
            .{},
            .{ components.Sprite, components.Position, components.Texture, components.Shader, TagType },
            .{},
        );

        if (shader_group.len() == 0) {
            // Nothing to draw for this shader tag
        } else {
            // Fetch shader pointer from the first entity in the group. All
            // entities in this group share the same shader.
            const first_entity = shader_group.data()[0];
            const shader_comp = shader_group.get(components.Shader, first_entity);

            ray.BeginShaderMode(shader_comp.shader.*);

            var sit = shader_group.iterator();
            while (sit.next()) |e| {
            const sprite = shader_group.get(components.Sprite, e);
            const pos    = shader_group.get(components.Position, e);
            const tex    = shader_group.get(components.Texture, e);

            // Update per-entity uniforms (if any)
            shaders.updateShaderUniforms(e) catch |err| {
                std.debug.print("Shader uniform update error: {}\n", .{err});
            };

            drawTexturedSquare(@intFromFloat(pos.x), @intFromFloat(pos.y), tex.texture,
                tex, sprite.rgba, sprite.size, sprite.rotation);
        }

            ray.EndShaderMode();
        }
    }
}

// ---------------------------------------------------------------------------
// Helper to submit a textured quad
// ---------------------------------------------------------------------------

fn drawTexturedSquare(
    x: i32,
    y: i32,
    texture: *const ray.RenderTexture2D,
    tex_component: *const components.Texture,
    tint: [4]u8,
    scale: f32,
    rotation: f32,
) void {
    gfx.drawTexture(x, y, texture, tex_component.uv, tint, scale, rotation);
}
