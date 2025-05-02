const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const ecsroot = @import("ecs");
const game = @import("../game.zig");
const components = @import("../components.zig");
const animsys = @import("animsys.zig");
const gfx = @import("../gfx.zig");
const blocktextures = @import("../blocktextures.zig");
//active player piece
var player_entity: ?ecsroot.Entity = null;
var piece_block_entities: std.ArrayList(ecsroot.Entity) = undefined;
var ghost_block_entities: std.ArrayList(ecsroot.Entity) = undefined;

pub fn init() void {
    // Initialize entity lists
    piece_block_entities = std.ArrayList(ecsroot.Entity).init(std.heap.page_allocator);
    ghost_block_entities = std.ArrayList(ecsroot.Entity).init(std.heap.page_allocator);

    // Create player piece entity if it doesn't exist
    if (player_entity == null) {
        player_entity = ecs.createEntity();

        ecs.addOrReplace(components.Position, player_entity.?, components.Position{
            .x = 0,
            .y = 0,
        });

        ecs.addOrReplace(components.ActivePieceTag, player_entity.?, components.ActivePieceTag{});
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
    ecs.addOrReplace(components.Position, player_entity.?, components.Position{
        .x = targetx,
        .y = targety,
    });

    // Update visual representation with current piece
    updatePieceEntities();
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

    // Update piece entities after move
    updatePieceEntities();
}

// Clear existing block entities and create new ones based on current piece
fn clearBlockEntities() void {
    // Clear piece blocks
    for (piece_block_entities.items) |entity| {
        ecs.getWorld().destroy(entity);
    }
    piece_block_entities.clearRetainingCapacity();

    // Clear ghost blocks
    for (ghost_block_entities.items) |entity| {
        ecs.getWorld().destroy(entity);
    }
    ghost_block_entities.clearRetainingCapacity();
}

// Create entity for a single block
fn createBlockEntity(x: f32, y: f32, color: [4]u8, scale: f32) !ecsroot.Entity {
    const entity = blocktextures.createUVTexturedSprite(x, y, color, scale, 0.0) catch |err| {
        std.debug.print("Failed to create block entity: {} {} {} {} {}\n", .{ color[0], color[1], color[2], color[3], err });
        return err;
    };
    return entity;
}
// Draw the player piece and ghost preview by creating entities
pub fn playerSystem() void {
    if (game.state.piece.current) |p| {
        if (player_entity == null) {
            init();
        }

        // Get the current animated position from the entity's Position component
        var drawX: i32 = 0;
        var drawY: i32 = 0;

        if (ecs.get(components.Position, player_entity.?)) |pos| {
            drawX = @as(i32, @intFromFloat(pos.x));
            drawY = @as(i32, @intFromFloat(pos.y));
        } else {
            // If for some reason the position component is missing, use default values
            drawX = game.state.piece.x * gfx.window.cellsize;
            drawY = game.state.piece.y * gfx.window.cellsize;

            // Update entity with current position for future animations
            ecs.addOrReplace(components.Position, player_entity.?, components.Position{
                .x = @floatFromInt(drawX),
                .y = @floatFromInt(drawY),
            });
        }

        // Clear all existing block entities
        clearBlockEntities();

        // Create entities for the active piece blocks
        createPieceEntities(drawX, drawY, p.shape[game.state.piece.r], p.color, false);

        // Create entities for ghost piece blocks (semi-transparent preview at landing position)
        const ghostY = ghosty() * gfx.window.cellsize;
        const ghostColor = .{ p.color[0], p.color[1], p.color[2], 60 };
        createPieceEntities(drawX, ghostY, p.shape[game.state.piece.r], ghostColor, true);
    }
}

// Update piece entities without redrawing (used after animations)
pub fn updatePieceEntities() void {
    if (game.state.piece.current) |p| {
        // Get the current position
        if (ecs.get(components.Position, player_entity.?)) |pos| {
            const drawX = @as(i32, @intFromFloat(pos.x));
            const drawY = @as(i32, @intFromFloat(pos.y));

            // Clear existing entities and create new ones
            clearBlockEntities();

            // Create main piece entities
            createPieceEntities(drawX, drawY, p.shape[game.state.piece.r], p.color, false);

            // Create ghost piece entities
            const ghostY = ghosty() * gfx.window.cellsize;
            const ghostColor = .{ p.color[0], p.color[1], p.color[2], 60 };
            createPieceEntities(drawX, ghostY, p.shape[game.state.piece.r], ghostColor, true);
        }
    }
}

// Create entities for a tetris piece (either main piece or ghost)
pub fn createPieceEntities(x: i32, y: i32, shape: [4][4]bool, color: [4]u8, is_ghost: bool) void {
    const scale: f32 = 1.0;

    for (shape, 0..) |row, i| {
        for (row, 0..) |cell, j| {
            if (cell) {
                const cellX = @as(i32, @intCast(i)) * gfx.window.cellsize;
                const cellY = @as(i32, @intCast(j)) * gfx.window.cellsize;
                const posX = @as(f32, @floatFromInt(x + cellX));
                const posY = @as(f32, @floatFromInt(y + cellY));

                // Create entity for this block
                const entity = createBlockEntity(posX, posY, color, scale) catch |err| {
                    std.debug.print("Failed to create block entity: {}\n", .{err});
                    return;
                };

                // Store entity reference in appropriate list
                if (is_ghost) {
                    ghost_block_entities.append(entity) catch |err| {
                        std.debug.print("Failed to append ghost entity: {}\n", .{err});
                    };
                } else {
                    piece_block_entities.append(entity) catch |err| {
                        std.debug.print("Failed to append piece entity: {}\n", .{err});
                    };
                }
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
    clearBlockEntities();

    if (player_entity) |entity| {
        ecs.getWorld().destroy(entity);
        player_entity = null;
    }

    piece_block_entities.deinit();
    ghost_block_entities.deinit();
}
