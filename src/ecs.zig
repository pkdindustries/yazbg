const std = @import("std");
const ecs = @import("ecs");
const components = @import("components.zig");

var world: ?ecs.Registry = null;

pub fn init(allocator: std.mem.Allocator) void {
    // std.debug.print("init ecs\n", .{});
    world = ecs.Registry.init(allocator);
}

pub inline fn createEntity() ecs.Entity {
    return world.?.create();
}

pub inline fn replace(comptime T: type, entity: ecs.Entity, value: anytype) void {
    // The caller passes `value` whose type must match `T`.
    _ = @as(T, value); // type-check
    if (world.?.has(T, entity)) {
        // Replace existing component value to avoid duplicate-set assertion.
        world.?.remove(T, entity);
    }
    world.?.add(entity, value);
}

pub inline fn get(comptime T: type, entity: ecs.Entity) ?T {
    return if (world.?.has(T, entity)) world.?.getConst(T, entity) else null;
}

// Get component for entity without null check (must call has() first)
pub inline fn getUnchecked(comptime T: type, entity: ecs.Entity) *T {
    return world.?.assure(T).get(entity);
}

// Whether `entity` currently owns component `T`.
pub inline fn has(comptime T: type, entity: ecs.Entity) bool {
    return world.?.has(T, entity);
}

pub fn getBlocksView() @TypeOf(world.?.view(.{ components.BlockTag, components.GridPos }, .{})) {
    return world.?.view(.{ components.BlockTag, components.GridPos }, .{});
}

pub fn getPlayerView() @TypeOf(world.?.view(.{components.ActivePieceTag}, .{})) {
    return world.?.view(.{components.ActivePieceTag}, .{});
}

pub fn getPieceBlocksView() @TypeOf(world.?.view(.{components.PieceBlockTag}, .{})) {
    return world.?.view(.{components.PieceBlockTag}, .{});
}

pub fn getGhostBlocksView() @TypeOf(world.?.view(.{components.GhostBlockTag}, .{})) {
    return world.?.view(.{components.GhostBlockTag}, .{});
}

pub fn getWorld() *ecs.Registry {
    return &world.?;
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

    // Any other components with deinit methods should be handled here

    // Now destroy the entity
    world.?.destroy(entity);
}

pub fn deinit() void {
    // std.debug.print("deinit ecs\n", .{});
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
