// engine/ecs.zig - Generic ECS wrapper
const std = @import("std");
const ecs = @import("ecs");
const components = @import("components.zig");

var world: ?ecs.Registry = null;

pub fn init(allocator: std.mem.Allocator) void {
    world = ecs.Registry.init(allocator);
}

pub fn deinit() void {
    if (world != null) {
        // Clean up any remaining shader components
        var shaderView = world.?.view(.{components.Shader}, .{});
        var it = shaderView.entityIterator();
        while (it.next()) |entity| {
            var shader_component = world.?.get(components.Shader, entity);
            shader_component.deinit();
        }

        world.?.deinit();
        world = null;
    }
}

pub fn getWorld() *ecs.Registry {
    return &world.?;
}

// Entity management
pub fn createEntity() ecs.Entity {
    return world.?.create();
}

// Helper function to safely remove a component with proper cleanup
pub fn safeRemove(comptime T: type, entity: ecs.Entity) void {
    if (world.?.has(T, entity)) {
        const component_ptr = world.?.get(T, entity);
        // Check if component has a deinit method and call it
        if (@hasDecl(T, "deinit")) {
            component_ptr.deinit();
        }
        world.?.remove(T, entity);
    }
}

// Safely destroy an entity with proper component cleanup
pub fn destroyEntity(entity: ecs.Entity) void {
    // Clean up components that need deinitialization
    if (world.?.has(components.Shader, entity)) {
        var shader_component = world.?.get(components.Shader, entity);
        shader_component.deinit();
    }

    // Now destroy the entity
    world.?.destroy(entity);
}

// Component operations - just forward to the world
pub fn add(entity: ecs.Entity, component: anytype) void {
    world.?.add(entity, component);
}

pub fn get(comptime T: type, entity: ecs.Entity) ?*T {
    if (world.?.has(T, entity)) {
        return world.?.get(T, entity);
    }
    return null;
}

pub fn getUnchecked(comptime T: type, entity: ecs.Entity) *T {
    return world.?.get(T, entity);
}

pub fn has(comptime T: type, entity: ecs.Entity) bool {
    return world.?.has(T, entity);
}

pub fn remove(comptime T: type, entity: ecs.Entity) void {
    world.?.remove(T, entity);
}

pub fn replace(comptime T: type, entity: ecs.Entity, component: T) void {
    if (world.?.has(T, entity)) {
        world.?.replace(entity, component);
    } else {
        world.?.add(entity, component);
    }
}

pub fn addOrReplace(comptime T: type, entity: ecs.Entity, component: T) void {
    world.?.addOrReplace(entity, component);
}

// Re-export the ecs.Entity type for convenience
pub const Entity = ecs.Entity;