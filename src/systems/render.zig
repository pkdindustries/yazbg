const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const components = @import("../components.zig");
const gfx = @import("../gfx.zig");
const shaders = @import("../shaders.zig");

// Sorting helper: order Shader components by the pointer value so that all
// entities using the same Shader end up contiguous in the group array.
pub fn shaderLess(_: void, a: components.Shader, b: components.Shader) bool {
    return @intFromPtr(a.shader) < @intFromPtr(b.shader);
}

// ---------------------------------------------------------------------------
// Rendering system using zig-ecs groups.
// ---------------------------------------------------------------------------

pub fn draw() void {
    const world = ecs.getWorld();

    // ---------------------------------------------------------------------
    // Pass 1: draw all entities that do NOT have a Shader component.
    //   BasicGroup caches membership for us; no run-time filtering needed.
    // ---------------------------------------------------------------------

    var regular_group = world.group(
        .{},
        .{ components.Sprite, components.Position, components.Texture },
        .{ components.Shader }, // exclude all entities that own a Shader
    );

    var rit = regular_group.iterator();
    while (rit.next()) |e| {
        const sprite = regular_group.get(components.Sprite, e);
        const pos    = regular_group.get(components.Position, e);
        const tex    = regular_group.get(components.Texture, e);

        drawTexturedSquare(@intFromFloat(pos.x), @intFromFloat(pos.y), tex.texture,
            tex, sprite.rgba, sprite.size, sprite.rotation);
    }

    // ---------------------------------------------------------------------
    // Pass 2: draw entities WITH a Shader component using an OWNING group so
    // that Sprite/Position/Texture/Shader storages are kept zipped.  Sorting
    // will therefore keep all component arrays in sync which improves cache
    // locality when we touch multiple components per entity.
    // ---------------------------------------------------------------------

    var shader_group = world.group(
        // owned components
        .{ components.Sprite, components.Position, components.Texture, components.Shader },
        // no additional includes
        .{},
        // no excludes
        .{},
    );

    if (shader_group.len() == 0) return;

    shader_group.sort(components.Shader, {}, shaderLess);

    const IterComp = struct {
        sprite: *components.Sprite,
        position: *components.Position,
        texture: *components.Texture,
        shader: *components.Shader,
    };

    var it = shader_group.iterator(IterComp);
    var current_shader_ptr: ?*const ray.Shader = null;

    while (it.next()) |comps| {
        if (current_shader_ptr == null or comps.shader.shader != current_shader_ptr.?) {
            if (current_shader_ptr != null) ray.EndShaderMode();
            current_shader_ptr = comps.shader.shader;
            ray.BeginShaderMode(current_shader_ptr.? .*);
        }

        shaders.updateShaderUniforms(it.entity()) catch |err| {
            std.debug.print("Shader uniforms error: {}\n", .{err});
        };

        drawTexturedSquare(
            @intFromFloat(comps.position.x),
            @intFromFloat(comps.position.y),
            comps.texture.texture,
            comps.texture,
            comps.sprite.rgba,
            comps.sprite.size,
            comps.sprite.rotation,
        );
    }

    if (current_shader_ptr != null) ray.EndShaderMode();
}

// ---------------------------------------------------------------------------
// Helper
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
