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

    //  render entities with Mesh2D (arbitrary textured geometry)
    var mesh_view = world.view(
        .{ components.Mesh2D, components.Position, components.Sprite },
        .{},
    );

    var mesh_it = mesh_view.entityIterator();
    while (mesh_it.next()) |entity| {
        const mesh = mesh_view.get(components.Mesh2D, entity);
        const pos = mesh_view.get(components.Position, entity);
        const sprite = mesh_view.get(components.Sprite, entity);

        drawMeshEntity(mesh, pos, sprite);
    }
}

fn drawMeshEntity(mesh: *const components.Mesh2D, pos: *const components.Position, sprite: *const components.Sprite) void {
    const cellsize_scaled: f32 = @as(f32, @floatFromInt(gfx.window.cellsize)) * sprite.size;

    const angle_rad: f32 = sprite.rotation * std.math.tau;
    const cos_a: f32 = std.math.cos(angle_rad);
    const sin_a: f32 = std.math.sin(angle_rad);

    const pivot_x: f32 = cellsize_scaled / 2.0;
    const pivot_y: f32 = cellsize_scaled / 2.0;

    // Debug info
    std.debug.print("Drawing mesh with texture ID: {}\n", .{mesh.texture.*.texture.id});
    std.debug.print("Mesh has {} vertices and {} indices\n", .{ mesh.vertices.len, mesh.indices.len });
    std.debug.print("Position: x={d}, y={d}, size={d}\n", .{ pos.x, pos.y, sprite.size });
    std.debug.print("Color: r={}, g={}, b={}, a={}\n", .{ sprite.rgba[0], sprite.rgba[1], sprite.rgba[2], sprite.rgba[3] });

    // Draw a very small outline to mark the mesh position without overwhelming the view
    const small_debug_size = @as(i32, @intFromFloat(cellsize_scaled * 0.3));
    ray.DrawRectangleLines(
        @as(i32, @intFromFloat(pos.x)),
        @as(i32, @intFromFloat(pos.y)),
        small_debug_size,
        small_debug_size,
        ray.ColorAlpha(ray.GOLD, 0.8) // Using gold with high alpha for visibility
    );

    // Draw a solid texture rectangle to debug the texture itself
    // This uses the higher-level raylib functions which should be more reliable
    const src_rect = ray.Rectangle{
        .x = 0,
        .y = 0,
        .width = @as(f32, @floatFromInt(mesh.texture.*.texture.width)),
        .height = @as(f32, @floatFromInt(mesh.texture.*.texture.height)),
    };
    const dest_rect = ray.Rectangle{
        .x = pos.x + @as(f32, @floatFromInt(gfx.window.cellsize * 2)),
        .y = pos.y,
        .width = @as(f32, @floatFromInt(gfx.window.cellsize * 2)),
        .height = @as(f32, @floatFromInt(gfx.window.cellsize * 2)),
    };

    ray.DrawTexturePro(
        mesh.texture.*.texture,
        src_rect,
        dest_rect,
        .{ .x = 0, .y = 0 }, // origin
        0.0, // rotation
        ray.WHITE // tint
    );

    // Ensure we're using alpha blending
    ray.rlSetBlendMode(ray.BLEND_ALPHA);

    // Now try the texture-based approach
    // Bind the texture for rendering so the mesh is textured correctly.
    // Important: Make sure we're binding the correct texture ID from the render texture
    const texture_id = mesh.texture.*.texture.id;
    std.debug.print("Using texture ID: {} for mesh rendering\n", .{texture_id});

    // Double check if texture ID is valid
    if (texture_id == 0) {
        std.debug.print("WARNING: Invalid texture ID of 0!\n", .{});
        // Draw a solid fallback shape so we can at least see something
        ray.DrawRectangle(
            @as(i32, @intFromFloat(pos.x)),
            @as(i32, @intFromFloat(pos.y)),
            @as(i32, @intFromFloat(cellsize_scaled)),
            @as(i32, @intFromFloat(cellsize_scaled)),
            ray.ColorAlpha(ray.PURPLE, 0.7)
        );
    }
    ray.rlSetTexture(texture_id);

    // Set the color for the mesh vertices
    ray.rlColor4ub(sprite.rgba[0], sprite.rgba[1], sprite.rgba[2], sprite.rgba[3]);

    // Draw a debug outline of where the mesh should be for comparison
    const quad_size = cellsize_scaled;
    const quad_x = @as(i32, @intFromFloat(pos.x));
    const quad_y = @as(i32, @intFromFloat(pos.y));

    // Use thick lines and high contrast to make sure it's visible
    const thickness = 3;
    for (0..thickness) |i| {
        ray.DrawRectangleLines(
            quad_x - @as(i32, @intCast(i)),
            quad_y - @as(i32, @intCast(i)),
            @as(i32, @intFromFloat(quad_size)) + @as(i32, @intCast(i*2)),
            @as(i32, @intFromFloat(quad_size)) + @as(i32, @intCast(i*2)),
            ray.RED
        );
    }

    ray.rlBegin(ray.RL_TRIANGLES);

    if (mesh.indices.len > 0) {
        for (mesh.indices) |idx| {
            if (idx >= mesh.vertices.len) {
                std.debug.print("WARNING: Index {} out of bounds (max {})\n", .{ idx, mesh.vertices.len - 1 });
                continue;
            }
            const v = mesh.vertices[idx];
            commitVertex(v, pos, cellsize_scaled, pivot_x, pivot_y, cos_a, sin_a);
        }
    } else {
        for (mesh.vertices) |v| {
            commitVertex(v, pos, cellsize_scaled, pivot_x, pivot_y, cos_a, sin_a);
        }
    }

    ray.rlEnd();

    // Reset texture (defensive) – 0 tells rlgl to use default white texture
    ray.rlSetTexture(0);
}

fn commitVertex(
    v: components.Vertex2D,
    pos: *const components.Position,
    cellsize_scaled: f32,
    _: f32, // Unused pivot_x
    _: f32, // Unused pivot_y
    cos_a: f32,
    sin_a: f32,
) void {
    // Scale vertex position by cellsize
    const lx = v.pos[0] * cellsize_scaled;
    const ly = v.pos[1] * cellsize_scaled;

    // Rotate around center
    const rx = lx * cos_a - ly * sin_a;
    const ry = lx * sin_a + ly * cos_a;

    // Translate to world position - we want the mesh to be centered at the entity position
    // Changed to simple direct position to eliminate any potential offset issues
    const wx = pos.x + rx;
    const wy = pos.y + ry;

    std.debug.print("Vertex: pos={d},{d} uv={d},{d} -> world={d},{d}\n", .{ v.pos[0], v.pos[1], v.uv[0], v.uv[1], wx, wy });

    // Ensure UVs are within valid range (0.0-1.0)
    const u = std.math.clamp(v.uv[0], 0.0, 1.0);
    // CRUCIAL FIX: Flip V coordinate for render textures in raylib
    const v_coord = std.math.clamp(1.0 - v.uv[1], 0.0, 1.0);

    // Set texture coordinates and vertex position
    std.debug.print("Using flipped UV: u={d}, v={d}\n", .{ u, v_coord });
    ray.rlTexCoord2f(u, v_coord);
    ray.rlVertex2f(wx, wy);
}

// Draw a render texture with scaling and rotation using Texture component
pub fn drawTextureFromComponent(x: i32, y: i32, texture: *const ray.RenderTexture2D, tex_component: *const components.Texture, tint: [4]u8, scale: f32, rotation: f32) void {
    gfx.drawTexture(x, y, texture, tex_component.*.uv, tint, scale, rotation);
}
