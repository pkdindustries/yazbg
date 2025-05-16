const std = @import("std");
const ecs = @import("ecs");
const components = @import("components.zig");

var world: ?ecs.Registry = null;

pub fn init() void {
    std.debug.print("init ecs\n", .{});
    world = ecs.Registry.init(std.heap.c_allocator);
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

pub fn deinit() void {
    std.debug.print("deinit ecs\n", .{});
    if (world != null) {
        world.?.deinit();
        world = null;
    }
}
