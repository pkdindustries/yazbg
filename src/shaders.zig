const std = @import("std");
const ray = @import("raylib.zig");
const ecs = @import("ecs.zig");
const ecsroot = @import("ecs");
const components = @import("components.zig");
const gfx = @import("gfx.zig");

// shader entry in the shader library
const ShaderEntry = struct {
    shader: *ray.Shader, // heap-allocated shader pointer
    name: []const u8, // shader name/identifier
};

// global state
var shaders: std.StringHashMap(ShaderEntry) = undefined;
var allocator: std.mem.Allocator = undefined;

// initialize shader system
pub fn init(alloc: std.mem.Allocator) !void {
    allocator = alloc;
    shaders = std.StringHashMap(ShaderEntry).init(allocator);
    std.debug.print("Shader system initialized\n", .{});

    // Pre-load common shaders
    try loadShader("static", "resources/shader/static_es100.fs");
    try loadShader("warp", "resources/shader/warp_es100.fs");
    // try loadShader("nearest_cell", "resources/shader/nearest_cell.fs");
}

// clean up all shaders and free memory
pub fn deinit() void {
    var iter = shaders.iterator();
    while (iter.next()) |entry| {
        const shader_entry = entry.value_ptr;
        ray.UnloadShader(shader_entry.shader.*);
        allocator.free(shader_entry.name);
        allocator.destroy(shader_entry.shader);
    }

    shaders.deinit();
}

// load a shader from file and add it to the library
pub fn loadShader(name: []const u8, fragment_path: []const u8) !void {
    // Check if shader with this name already exists
    if (shaders.contains(name)) {
        // std.debug.print("Shader '{s}' already exists, skipping load\n", .{name});
        return;
    }

    // Allocate shader on heap
    const shader_ptr = try allocator.create(ray.Shader);

    // Load shader from file
    shader_ptr.* = ray.LoadShader(null, fragment_path.ptr);
    if (shader_ptr.*.id == 0) {
        // std.debug.print("ERROR: Failed to load shader from {s}\n", .{fragment_path});
        allocator.destroy(shader_ptr);
        return error.ShaderLoadFailed;
    }

    // Store shader name
    const name_copy = try allocator.dupe(u8, name);

    // Add to library
    try shaders.put(name_copy, .{
        .shader = shader_ptr,
        .name = name_copy,
    });

    // std.debug.print("Loaded shader '{s}' from {s} (id={})\n", .{ name, fragment_path, shader_ptr.*.id });
}

// get a shader by name
pub fn getShader(name: []const u8) ?*const ray.Shader {
    if (shaders.get(name)) |entry| {
        return entry.shader;
    }
    return null;
}

// add a shader component to an entity
pub fn addShaderToEntity(entity: ecsroot.Entity, shader_name: []const u8) !void {
    const shader = getShader(shader_name) orelse {
        // std.debug.print("ERROR: Shader '{s}' not found\n", .{shader_name});
        return error.ShaderNotFound;
    };

    var shader_component = components.Shader.init(allocator);
    shader_component.shader = shader;
    shader_component.created = false; // not owned by this component

    ecs.replace(components.Shader, entity, shader_component);
}

// create entity with shader and default uniform
pub fn createEntityWithShader(
    x: f32,
    y: f32,
    color: [4]u8,
    scale: f32,
    shader_name: []const u8,
    time_value: f32,
) !ecsroot.Entity {
    const entity = ecs.createEntity();

    ecs.replace(components.Position, entity, components.Position{ .x = x, .y = y });
    ecs.replace(components.Sprite, entity, components.Sprite{ .rgba = color, .size = scale });

    try addShaderToEntity(entity, shader_name);

    // Add default time uniform for most shaders
    var shader_component = ecs.getUnchecked(components.Shader, entity);
    try shader_component.setFloat("time", time_value);

    return entity;
}

// update shader uniforms before rendering
pub fn updateShaderUniforms(entity: ecsroot.Entity) !void {
    if (!ecs.has(components.Shader, entity)) return;

    const shader_component = ecs.getUnchecked(components.Shader, entity);
    const shader = shader_component.shader;

    // Always update the time uniform with current time
    const time_location = ray.GetShaderLocation(shader.*, "time");
    if (time_location != -1) {
        const current_time = @as(f32, @floatCast(ray.GetTime()));
        ray.SetShaderValue(shader.*, time_location, &current_time, ray.SHADER_UNIFORM_FLOAT);
    }

    // Update all uniforms in the hashmap
    var iter = shader_component.uniforms.iterator();
    while (iter.next()) |entry| {
        const name = entry.key_ptr.*;
        const uniform = entry.value_ptr.*;

        // Skip time uniform as we've already updated it
        if (std.mem.eql(u8, name, "time")) continue;

        // Get location for the uniform
        const location = ray.GetShaderLocation(shader.*, name.ptr);
        if (location != -1) {
            switch (uniform) {
                .float => |value| {
                    ray.SetShaderValue(shader.*, location, &value, ray.SHADER_UNIFORM_FLOAT);
                },
                .vec2 => |value| {
                    ray.SetShaderValue(shader.*, location, &value, ray.SHADER_UNIFORM_VEC2);
                },
                .vec3 => |value| {
                    ray.SetShaderValue(shader.*, location, &value, ray.SHADER_UNIFORM_VEC3);
                },
                .vec4 => |value| {
                    ray.SetShaderValue(shader.*, location, &value, ray.SHADER_UNIFORM_VEC4);
                },
                .texture => |tex_ptr| {
                    // Bind texture to the shader uniform slot
                    ray.SetShaderValueTexture(shader.*, location, tex_ptr.*);
                },
            }
        }
    }
}
