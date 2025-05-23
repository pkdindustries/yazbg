// games/blocks/ecs_helpers.zig - Tetris-specific ECS view helpers
const ecs = @import("engine").ecs;
const engine_components = @import("engine").components;
const engine = @import("engine");
const components = engine.components;
const game_components = @import("components.zig");

// Helper to get view for entities with all blocks (settled on grid)
pub fn getBlocksView() @TypeOf(ecs.getWorld().view(.{ game_components.BlockTag, game_components.GridPos }, .{})) {
    return ecs.getWorld().view(.{ game_components.BlockTag, game_components.GridPos }, .{});
}

pub fn getPlayerView() @TypeOf(ecs.getWorld().view(.{game_components.ActivePieceTag}, .{})) {
    return ecs.getWorld().view(.{game_components.ActivePieceTag}, .{});
}

pub fn getPieceBlocksView() @TypeOf(ecs.getWorld().view(.{game_components.PieceBlockTag}, .{})) {
    return ecs.getWorld().view(.{game_components.PieceBlockTag}, .{});
}

pub fn getGhostBlocksView() @TypeOf(ecs.getWorld().view(.{game_components.GhostBlockTag}, .{})) {
    return ecs.getWorld().view(.{game_components.GhostBlockTag}, .{});
}