// games/blocks/ecs_helpers.zig - Tetris-specific ECS view helpers
const common = @import("common.zig");
const components = common.components;
const ecs = common.ecs;

// Helper to get view for entities with all blocks (settled on grid)
pub fn getBlocksView() @TypeOf(ecs.getWorld().view(.{ components.BlockTag, components.GridPos }, .{})) {
    return ecs.getWorld().view(.{ components.BlockTag, components.GridPos }, .{});
}

pub fn getPlayerView() @TypeOf(ecs.getWorld().view(.{components.ActivePieceTag}, .{})) {
    return ecs.getWorld().view(.{components.ActivePieceTag}, .{});
}

pub fn getPieceBlocksView() @TypeOf(ecs.getWorld().view(.{components.PieceBlockTag}, .{})) {
    return ecs.getWorld().view(.{components.PieceBlockTag}, .{});
}

pub fn getGhostBlocksView() @TypeOf(ecs.getWorld().view(.{components.GhostBlockTag}, .{})) {
    return ecs.getWorld().view(.{components.GhostBlockTag}, .{});
}