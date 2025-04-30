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

// Component helpers
pub fn addPosition(entity: ecs.Entity, x: f32, y: f32) void {
    std.debug.print("addPosition {} {}\n", .{ x, y });
    world.?.add(entity, components.Position{ .x = x, .y = y });
}

pub fn getPosition(entity: ecs.Entity) ?components.Position {
    return if (world.?.has(components.Position, entity)) world.?.getConst(components.Position, entity) else null;
}

pub fn addSprite(entity: ecs.Entity, rgba: [4]u8, size: f32) void {
    world.?.add(entity, components.Sprite{ .rgba = rgba, .size = size });
}

pub fn getSprite(entity: ecs.Entity) ?components.Sprite {
    return if (world.?.has(components.Sprite, entity)) world.?.getConst(components.Sprite, entity) else null;
}

pub fn addFlash(entity: ecs.Entity, ttl_ms: i64) void {
    const expires_at = std.time.milliTimestamp() + ttl_ms;
    std.debug.print("addFlash {} {}\n", .{ ttl_ms, expires_at });
    
    // Check if entity already has a Flash component and remove it first
    if (world.?.has(components.Flash, entity)) {
        world.?.remove(components.Flash, entity);
    }
    
    world.?.add(entity, components.Flash{
        .ttl_ms = ttl_ms,
        .expires_at_ms = expires_at,
    });
}

pub fn getFlash(entity: ecs.Entity) ?components.Flash {
    return if (world.?.has(components.Flash, entity)) world.?.getConst(components.Flash, entity) else null;
}

pub fn addGridPos(entity: ecs.Entity, x: i32, y: i32) void {
    std.debug.print("addGridPos {} {}\n", .{ x, y });

    world.?.add(entity, components.GridPos{ .x = x, .y = y });
}

pub fn getGridPos(entity: ecs.Entity) ?components.GridPos {
    return if (world.?.has(components.GridPos, entity)) world.?.getConst(components.GridPos, entity) else null;
}

pub fn addBlockTag(entity: ecs.Entity) void {
    std.debug.print("addBlockTag\n", .{});
    world.?.add(entity, components.BlockTag{});
}

pub fn hasBlockTag(entity: ecs.Entity) bool {
    return world.?.has(components.BlockTag, entity);
}

pub fn addPieceKind(entity: ecs.Entity, shape: *const [4][4][4]bool, color: [4]u8) void {
    world.?.add(entity, components.PieceKind{ .shape = shape, .color = color });
}

pub fn getPieceKind(entity: ecs.Entity) ?components.PieceKind {
    return if (world.?.has(components.PieceKind, entity)) world.?.getConst(components.PieceKind, entity) else null;
}

pub fn addRotation(entity: ecs.Entity, index: u2) void {
    world.?.add(entity, components.Rotation{ .index = index });
}

pub fn getRotation(entity: ecs.Entity) ?components.Rotation {
    return if (world.?.has(components.Rotation, entity)) world.?.getConst(components.Rotation, entity) else null;
}

pub fn addActivePieceTag(entity: ecs.Entity) void {
    world.?.add(entity, components.ActivePieceTag{});
}

pub fn hasActivePieceTag(entity: ecs.Entity) bool {
    return world.?.has(components.ActivePieceTag, entity);
}

// View helpers
pub fn createRenderView() @TypeOf(world.?.view(.{ components.Position, components.Sprite }, .{})) {
    return world.?.view(.{ components.Position, components.Sprite }, .{});
}

pub fn getActivePiece() ?ecs.Entity {
    var view = world.?.view(.{components.ActivePieceTag}, .{});
    var iter = view.entityIterator();
    return iter.next();
}

pub fn getBlocksView() @TypeOf(world.?.view(.{ components.BlockTag, components.GridPos }, .{})) {
    return world.?.view(.{ components.BlockTag, components.GridPos }, .{});
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
