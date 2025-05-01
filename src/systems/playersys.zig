const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const ecsroot = @import("ecs");
const game = @import("../game.zig");
const components = @import("../components.zig");
const animsys = @import("animsys.zig");
const gfx = @import("../gfx.zig");
const rendersys = @import("rendersys.zig");
//active player piece
var player_entity: ?ecsroot.Entity = null;

pub fn init() void {
    //  player piece entity if it doesn't exist
    if (player_entity == null) {
        player_entity = ecs.createEntity();

        ecs.add(components.Position, player_entity.?, components.Position{
            .x = 0,
            .y = 0,
        });

        ecs.add(components.ActivePieceTag, player_entity.?, components.ActivePieceTag{});
    }
}

// Handle a spawn event
pub fn spawn() void {
    // Make sure entity exists
    if (player_entity == null) {
        init();
    }

    // Set position to match the game state without animation
    const targetx = @as(f32, @floatFromInt(game.state.piece.x * gfx.window.cellsize));
    const targety = @as(f32, @floatFromInt(game.state.piece.y * gfx.window.cellsize));

    // Position is set immediately for spawning, no animation
    ecs.add(components.Position, player_entity.?, components.Position{
        .x = targetx,
        .y = targety,
    });
}

// Start a slide animation for the player piece
pub fn move(dx: i32, dy: i32) void {
    if (player_entity == null) {
        init();
    }

    // Calculate target position (where piece will end up)
    const targetx = @as(f32, @floatFromInt(game.state.piece.x * gfx.window.cellsize));
    const targety = @as(f32, @floatFromInt(game.state.piece.y * gfx.window.cellsize));

    // Calculate source position (where piece is visually coming from)
    const sourcex = targetx + @as(f32, @floatFromInt(dx * gfx.window.cellsize));
    const sourcey = targety + @as(f32, @floatFromInt(dy * gfx.window.cellsize));

    // Create animation using the animsys
    animsys.createPlayerPieceAnimation(player_entity.?, sourcex, sourcey, targetx, targety);
}

// Draw the player piece and ghost preview
pub fn draw() void {
    if (game.state.piece.current) |p| {
        if (player_entity == null) {
            init();
        }

        // Get the current animated position from the entity's Position component
        var drawX: i32 = 0;
        var drawY: i32 = 0;

        if (ecs.get(components.Position, player_entity.?)) |pos| {
            drawX = @intFromFloat(pos.x);
            drawY = @intFromFloat(pos.y);
        } else {
            // If for some reason the position component is missing, use default values
            drawX = game.state.piece.x * gfx.window.cellsize;
            drawY = game.state.piece.y * gfx.window.cellsize;

            // Update entity with current position for future animations
            ecs.add(components.Position, player_entity.?, components.Position{
                .x = @floatFromInt(drawX),
                .y = @floatFromInt(drawY),
            });
        }

        // Draw the active piece
        drawpiece(drawX, drawY, p.shape[game.state.piece.r], p.color);

        // Draw ghost piece (semi-transparent preview at landing position)
        const ghostColor = .{ p.color[0], p.color[1], p.color[2], 60 };
        drawpiece(drawX, ghosty() * gfx.window.cellsize, p.shape[game.state.piece.r], ghostColor);
    }
}

pub fn drawpiece(x: i32, y: i32, shape: [4][4]bool, color: [4]u8) void {
    const scale: f32 = 1.0;

    for (shape, 0..) |row, i| {
        for (row, 0..) |cell, j| {
            if (cell) {
                const cellX = @as(i32, @intCast(i)) * gfx.window.cellsize;
                const cellY = @as(i32, @intCast(j)) * gfx.window.cellsize;
                rendersys.drawbox(x + cellX, y + cellY, color, scale);
            }
        }
    }
}
// Get ghost piece's landing position
pub fn ghosty() i32 {
    // Calculate the ghost position based on the current piece position
    var y = game.state.piece.y;
    while (game.checkmove(game.state.piece.x, y + 1)) : (y += 1) {}
    return y;
}

// Clean up when the game ends
pub fn deinit() void {
    if (player_entity) |entity| {
        ecs.getWorld().destroy(entity);
        player_entity = null;
    }
}
