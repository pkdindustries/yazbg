const std = @import("std");
const ray = @import("raylib.zig");
const shaders = @import("shaders.zig");
const ecs = @import("ecs.zig");
const ecsroot = @import("ecs");
const components = @import("components.zig");
const gfx = @import("gfx.zig");
const textures = @import("textures.zig");
const rendersys = @import("systems/render.zig");
const events = @import("events.zig");

// Window dimensions
const screen_width: i32 = 800;
const screen_height: i32 = 600;

// Global entities for the shader blocks
var static_entity: ecsroot.Entity = undefined;
var pulse_entity: ecsroot.Entity = undefined;

pub fn main() !void {
    // Initialize raylib window with MSAA for smoother rendering
    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT);
    ray.InitWindow(screen_width, screen_height, "Shader System Test");
    defer ray.CloseWindow();

    // Initialize ECS
    ecs.init();
    defer ecs.deinit();

    // Initialize texture system
    try textures.init();
    defer textures.deinit();

    // Initialize shaders (loads built-in shaders)
    try shaders.init();
    defer shaders.deinit();

    // Load our custom pulse shader
    try shaders.loadShader("pulse", "resources/shader/pulse.fs");

    // Create the test entities
    try setupEntities();

    // Setup our debug rendering function
    defer cleanupEntities();

    // Main loop
    ray.SetTargetFPS(60);
    while (!ray.WindowShouldClose()) {
        // Update uniform values
        updateUniforms();

        // Debug output
        debugShaderUniforms(pulse_entity);

        // Draw everything
        draw();
    }
}

// Set up test entities
fn setupEntities() !void {
    // Create entity with static shader
    static_entity = ecs.createEntity();
    
    // Position it on the left side of screen
    const static_x = @as(f32, @floatFromInt(screen_width / 4));
    const static_y = @as(f32, @floatFromInt(screen_height / 2));
    ecs.addOrReplace(components.Position, static_entity, components.Position{
        .x = static_x,
        .y = static_y,
    });
    
    // Add visual properties
    ecs.addOrReplace(components.Sprite, static_entity, components.Sprite{
        .rgba = [4]u8{ 255, 255, 255, 255 },
        .size = 200.0,
    });
    
    // Add a texture from the atlas
    try textures.addBlockTextureWithAtlas(static_entity, [4]u8{ 255, 255, 255, 255 });
    
    // Add the static shader
    try shaders.addShaderToEntity(static_entity, "static");
    
    // Create entity with pulse shader
    pulse_entity = ecs.createEntity();
    
    // Position it on the right side of screen
    const pulse_x = @as(f32, @floatFromInt(3 * screen_width / 4));
    const pulse_y = @as(f32, @floatFromInt(screen_height / 2));
    ecs.addOrReplace(components.Position, pulse_entity, components.Position{
        .x = pulse_x,
        .y = pulse_y,
    });
    
    // Add visual properties
    ecs.addOrReplace(components.Sprite, pulse_entity, components.Sprite{
        .rgba = [4]u8{ 255, 255, 255, 255 },
        .size = 200.0,
    });
    
    // Add a texture from the atlas
    try textures.addBlockTextureWithAtlas(pulse_entity, [4]u8{ 255, 255, 255, 255 });
    
    // Add the pulse shader and configure its uniforms
    try shaders.addShaderToEntity(pulse_entity, "pulse");
    var pulse_shader = ecs.getUnchecked(components.Shader, pulse_entity);
    try pulse_shader.setFloat("frequency", 3.0);
    try pulse_shader.setFloat("intensity", 1.0);
    
    std.debug.print("Entities created. Pulse shader ID: {}\n", .{pulse_shader.shader.*.id});
}

// Clean up test entities - not actually implemented
fn cleanupEntities() void {
    // The ECS wrapper doesn't expose destroy function, but entities will be
    // cleaned up automatically when the program exits
}

// Update shader uniforms each frame
fn updateUniforms() void {
    // Update the time uniform in all shader entities
    shaders.updateTimeUniforms();
    
    // Apply the updated uniforms
    shaders.updateShaderUniforms(static_entity) catch |err| {
        std.debug.print("Error updating static shader: {}\n", .{err});
    };
    
    shaders.updateShaderUniforms(pulse_entity) catch |err| {
        std.debug.print("Error updating pulse shader: {}\n", .{err});
    };
}

// Draw everything
fn draw() void {
    ray.BeginDrawing();
    ray.ClearBackground(ray.BLACK);
    
    // Direct rendering of each entity to avoid the static shader effect
    const entities = [_]ecsroot.Entity{ static_entity, pulse_entity };
    for (entities) |entity| {
        const position = ecs.getUnchecked(components.Position, entity);
        const sprite = ecs.getUnchecked(components.Sprite, entity);
        const texture = ecs.getUnchecked(components.Texture, entity);
        const shader = ecs.getUnchecked(components.Shader, entity);
        
        // Calculate absolute screen position
        const x = @as(i32, @intFromFloat(position.x));
        const y = @as(i32, @intFromFloat(position.y));
        
        // Create rectangles for drawing
        const src_rect = ray.Rectangle{
            .x = texture.uv[0] * @as(f32, @floatFromInt(texture.texture.*.texture.width)),
            .y = (1.0 - texture.uv[3]) * @as(f32, @floatFromInt(texture.texture.*.texture.height)),
            .width = (texture.uv[2] - texture.uv[0]) * @as(f32, @floatFromInt(texture.texture.*.texture.width)),
            .height = (texture.uv[3] - texture.uv[1]) * @as(f32, @floatFromInt(texture.texture.*.texture.height)),
        };
        
        const dest_rect = ray.Rectangle{
            .x = @as(f32, @floatFromInt(x)),
            .y = @as(f32, @floatFromInt(y)),
            .width = sprite.size,
            .height = sprite.size,
        };
        
        // Apply shader and draw
        ray.BeginShaderMode(shader.shader.*);
        
        ray.DrawTexturePro(
            texture.texture.*.texture,
            src_rect,
            dest_rect,
            .{ .x = sprite.size / 2.0, .y = sprite.size / 2.0 }, // origin at center
            0.0,  // rotation
            ray.Color{
                .r = sprite.rgba[0],
                .g = sprite.rgba[1],
                .b = sprite.rgba[2],
                .a = sprite.rgba[3],
            }
        );
        
        ray.EndShaderMode();
    }
    
    // Draw labels
    ray.DrawText("Static Shader", screen_width / 4 - 80, screen_height / 2 + 120, 20, ray.YELLOW);
    ray.DrawText("Pulse Shader", 3 * screen_width / 4 - 80, screen_height / 2 + 120, 20, ray.YELLOW);
    
    // Help text
    ray.DrawText("Press ESC to quit", 10, 10, 20, ray.WHITE);
    ray.DrawText("Using direct rendering", 10, 40, 20, ray.YELLOW);
    
    ray.EndDrawing();
}

// Debug function to examine shader uniforms at runtime
fn debugShaderUniforms(entity: ecsroot.Entity) void {
    // Only debug once per second to avoid flooding the console
    const current_time = ray.GetTime();
    const debug_interval = 1.0; // Debug once per second
    const should_debug = @mod(current_time, debug_interval) < 0.016; // One frame's worth of time

    if (!should_debug) return;

    if (!ecs.has(components.Shader, entity)) return;

    const shader_component = ecs.getUnchecked(components.Shader, entity);
    const shader = shader_component.shader;

    std.debug.print("\n--- Shader Uniform Debug at time {d:.2} ---\n", .{current_time});
    std.debug.print("Shader ID: {}\n", .{shader.*.id});

    // Manual location check of key uniforms
    const time_loc = ray.GetShaderLocation(shader.*, "time");
    const freq_loc = ray.GetShaderLocation(shader.*, "frequency");
    const intens_loc = ray.GetShaderLocation(shader.*, "intensity");

    std.debug.print("Uniform locations - time: {}, frequency: {}, intensity: {}\n", .{ time_loc, freq_loc, intens_loc });

    // Check what's in the uniform hashmap
    std.debug.print("Uniforms in hashmap: {}\n", .{shader_component.uniforms.count()});

    var iter = shader_component.uniforms.iterator();
    while (iter.next()) |entry| {
        const name = entry.key_ptr.*;
        const uniform = entry.value_ptr.*;

        std.debug.print("  Uniform '{s}': ", .{name});
        switch (uniform) {
            .float => |value| std.debug.print("float = {d:.4}\n", .{value}),
            .vec2 => |value| std.debug.print("vec2 = [{d:.2}, {d:.2}]\n", .{ value[0], value[1] }),
            .vec3 => |value| std.debug.print("vec3 = [{d:.2}, {d:.2}, {d:.2}]\n", .{ value[0], value[1], value[2] }),
            .vec4 => |value| std.debug.print("vec4 = [{d:.2}, {d:.2}, {d:.2}, {d:.2}]\n", .{ value[0], value[1], value[2], value[3] }),
        }

        // Check location again for each uniform
        const location = ray.GetShaderLocation(shader.*, name.ptr);
        std.debug.print("    Location: {}\n", .{location});
    }

    std.debug.print("--- End Debug ---\n\n", .{});
}