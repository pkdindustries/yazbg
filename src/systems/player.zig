const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const ecsroot = @import("ecs");
const game = @import("../game.zig");
const components = @import("../components.zig");
const animsys = @import("anim.zig");
const gfx = @import("../gfx.zig");
const textures = @import("../textures.zig");

fn getPlayerEntity() ?ecsroot.Entity {
    var view = ecs.getPlayerView();

    var it = view.entityIterator();
    if (it.next()) |entity| {
        return entity;
    }
    return null;
}

fn getPieceBlocks() std.ArrayList(ecsroot.Entity) {
    var result = std.ArrayList(ecsroot.Entity).init(std.heap.page_allocator);

    var view = ecs.getPieceBlocksView();

    var it = view.entityIterator();
    while (it.next()) |entity| {
        result.append(entity) catch {};
    }

    return result;
}

fn getGhostBlocks() std.ArrayList(ecsroot.Entity) {
    var result = std.ArrayList(ecsroot.Entity).init(std.heap.page_allocator);

    var view = ecs.getGhostBlocksView();

    var it = view.entityIterator();
    while (it.next()) |entity| {
        result.append(entity) catch {};
    }

    return result;
}

pub fn init() void {
    // Create player piece entity if it doesn't exist
    if (getPlayerEntity() == null) {
        const entity = ecs.createEntity();

        ecs.addOrReplace(components.Position, entity, components.Position{
            .x = 0,
            .y = 0,
        });

        ecs.addOrReplace(components.ActivePieceTag, entity, components.ActivePieceTag{});
    }
}

// Handle a spawn event
pub fn spawn() void {
    // Make sure entity exists
    var player_entity = getPlayerEntity();
    if (player_entity == null) {
        init();
        player_entity = getPlayerEntity();
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
    var player_entity = getPlayerEntity();
    if (player_entity == null) {
        init();
        player_entity = getPlayerEntity();
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
    var piece_blocks = getPieceBlocks();
    defer piece_blocks.deinit();
    for (piece_blocks.items) |entity| {
        ecs.getWorld().destroy(entity);
    }

    // Clear ghost blocks
    var ghost_blocks = getGhostBlocks();
    defer ghost_blocks.deinit();
    for (ghost_blocks.items) |entity| {
        ecs.getWorld().destroy(entity);
    }
}

// Create entity for a single block
fn createBlockEntity(x: f32, y: f32, color: [4]u8, scale: f32, is_ghost: bool) !ecsroot.Entity {
    const entity = textures.createBlockTextureWithAtlas(x, y, color, scale, 0.0) catch |err| {
        std.debug.print("Failed to create block entity: {}\n", .{err});
        return err;
    };

    // Add appropriate tag component
    if (is_ghost) {
        ecs.addOrReplace(components.GhostBlockTag, entity, components.GhostBlockTag{});
    } else {
        ecs.addOrReplace(components.PieceBlockTag, entity, components.PieceBlockTag{});
    }

    return entity;
}
// Draw the player piece and ghost preview by creating entities
pub fn playerSystem() void {
    if (game.state.piece.current) |p| {
        var player_entity = getPlayerEntity();
        if (player_entity == null) {
            init();
            player_entity = getPlayerEntity();
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
        // Get the current position from the player entity
        const player_entity = getPlayerEntity() orelse return;

        if (ecs.get(components.Position, player_entity)) |pos| {
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

                // Create entity for this block with appropriate tag
                _ = createBlockEntity(posX, posY, color, scale, is_ghost) catch |err| {
                    std.debug.print("Failed to create block entity: {}\n", .{err});
                    return;
                };
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

pub fn harddrop() void {
    // Create animations from current piece blocks to ghost piece positions
    std.debug.print("creating hard drop animations\n", .{});

    var piece_blocks = getPieceBlocks();
    defer piece_blocks.deinit();

    var ghost_blocks = getGhostBlocks();
    defer ghost_blocks.deinit();

    if (piece_blocks.items.len == 0) return;
    if (ghost_blocks.items.len == 0) return; // Nothing to animate

    // We need to create animations for each piece block
    for (piece_blocks.items) |piece_entity| {
        if (ecs.get(components.Position, piece_entity)) |piece_pos| {
            // Find the corresponding ghost block that has the same X position
            for (ghost_blocks.items) |ghost_entity| {
                if (ecs.get(components.Position, ghost_entity)) |ghost_pos| {
                    if (@trunc(piece_pos.x) == @trunc(ghost_pos.x)) {
                        // Get color from the piece block
                        var color = [4]u8{ 255, 255, 255, 255 };
                        if (ecs.get(components.Sprite, piece_entity)) |sprite| {
                            color = sprite.rgba;
                        }

                        // Create a new entity for the hard drop animation
                        const new_entity = ecs.getWorld().create();

                        // Add Position component
                        ecs.getWorld().add(new_entity, components.Position{
                            .x = piece_pos.x,
                            .y = piece_pos.y,
                        });

                        // Add Sprite component with the same color, full opacity
                        ecs.getWorld().add(new_entity, components.Sprite{
                            .rgba = .{ color[0], color[1], color[2], 60 },
                            .size = 1.0,
                        });

                        // Add texture
                        _ = textures.addBlockTextureWithAtlas(new_entity, color) catch |err| {
                            std.debug.print("Failed to add texture component: {}\n", .{err});
                        };

                        // Create animation component with fast drop to ghost position
                        const anim = components.Animation{
                            .animate_position = true,
                            .start_pos = .{ piece_pos.x, piece_pos.y },
                            .target_pos = .{ ghost_pos.x, ghost_pos.y },
                            .start_time = std.time.milliTimestamp(),
                            .duration = 100, // Fast animation (100ms)
                            .easing = .ease_in,
                            .remove_when_done = true,
                            .destroy_entity_when_done = true, // Destroy the entity when animation completes
                        };

                        ecs.getWorld().add(new_entity, anim);
                        break; // Found the corresponding ghost block, move to next piece block
                    }
                }
            }
        }
    }
}

// Clean up when the game ends
pub fn deinit() void {
    clearBlockEntities();

    // Find and destroy the player entity
    if (getPlayerEntity()) |entity| {
        ecs.getWorld().destroy(entity);
    }
}
