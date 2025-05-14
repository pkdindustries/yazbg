const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const ecsroot = @import("ecs");
const components = @import("../components.zig");
const animsys = @import("anim.zig");
const gfx = @import("../gfx.zig");
const textures = @import("../textures.zig");
const shaders = @import("../shaders.zig");
const pieces = @import("../pieces.zig");

fn cellSize() f32 {
    return @as(f32, @floatFromInt(gfx.window.cellsize));
}

fn getPlayerEntity() ?ecsroot.Entity {
    var view = ecs.getPlayerView();

    var it = view.entityIterator();
    if (it.next()) |entity| {
        return entity;
    }
    return null;
}

fn getPieceBlocks() @TypeOf(ecs.getPieceBlocksView().entityIterator()) {
    var view = ecs.getPieceBlocksView();
    return view.entityIterator();
}

fn getGhostBlocks() @TypeOf(ecs.getGhostBlocksView().entityIterator()) {
    var view = ecs.getGhostBlocksView();
    return view.entityIterator();
}

pub fn init() void {
    // Create player piece entity if it doesn't exist
    if (getPlayerEntity() == null) {
        const entity = ecs.createEntity();

        // Add required components
        ecs.addOrReplace(components.Position, entity, components.Position{
            .x = 0,
            .y = 0,
        });

        // Add the player piece state component with default values
        ecs.addOrReplace(components.PlayerPieceState, entity, components.PlayerPieceState{
            .x = 4,
            .y = 0,
            .rotation = 0,
            .ghost_y = 0,
            .piece_index = 0,
            .has_piece = false,
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

    // Check if we have a piece to spawn
    const piece_state = ecs.get(components.PlayerPieceState, player_entity.?) orelse return;
    if (!piece_state.has_piece) return;

    // Translate logical grid position to absolute pixels (top-left).
    const cs = cellSize();
    const targetx = @as(f32, @floatFromInt(gfx.window.gridoffsetx)) + @as(f32, @floatFromInt(piece_state.x)) * cs;
    const targety = @as(f32, @floatFromInt(gfx.window.gridoffsety)) + @as(f32, @floatFromInt(piece_state.y)) * cs;

    // Position is set immediately for spawning, no animation
    ecs.addOrReplace(components.Position, player_entity.?, components.Position{
        .x = targetx,
        .y = targety,
    });

    // Update visual representation with current piece
    updatePieceEntities();
}

// Clear existing block entities and create new ones based on current piece
fn clearBlockEntities() void {
    // Clear piece blocks
    var piece_it = getPieceBlocks();
    while (piece_it.next()) |entity| {
        ecs.getWorld().destroy(entity);
    }

    // Clear ghost blocks
    var ghost_it = getGhostBlocks();
    while (ghost_it.next()) |entity| {
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

// Update the player's position based on game state
pub fn updatePlayerPosition(x: i32, y: i32, rotation: u32, ghost_y: i32, piece_index: u32) void {
    // Get or create the player entity
    var player_entity: ecsroot.Entity = undefined;
    if (getPlayerEntity()) |entity| {
        player_entity = entity;
    } else {
        init();
        player_entity = getPlayerEntity() orelse return;
    }

    // Update the PlayerPieceState component
    ecs.addOrReplace(components.PlayerPieceState, player_entity, components.PlayerPieceState{
        .x = x,
        .y = y,
        .rotation = rotation,
        .ghost_y = ghost_y,
        .piece_index = piece_index,
        .has_piece = true,
    });

    // Update the Position component
    const cs = cellSize();
    const pixelX = @as(f32, @floatFromInt(gfx.window.gridoffsetx)) + @as(f32, @floatFromInt(x)) * cs;
    const pixelY = @as(f32, @floatFromInt(gfx.window.gridoffsety)) + @as(f32, @floatFromInt(y)) * cs;

    ecs.addOrReplace(components.Position, player_entity, components.Position{
        .x = pixelX,
        .y = pixelY,
    });
}

// Draw the player piece and ghost preview by creating entities
pub fn update() void {
    var player_entity = getPlayerEntity();
    if (player_entity == null) {
        init();
        player_entity = getPlayerEntity();
    }

    // Get the player piece state component
    const piece_state = ecs.get(components.PlayerPieceState, player_entity.?) orelse return;
    if (!piece_state.has_piece) return;

    // Get the current animated position from the entity's Position component
    var drawX: i32 = 0;
    var drawY: i32 = 0;

    if (ecs.get(components.Position, player_entity.?)) |pos| {
        drawX = @as(i32, @intFromFloat(pos.x));
        drawY = @as(i32, @intFromFloat(pos.y));
    } else {
        // If for some reason the position component is missing, calculate position from piece state
        const cs_i32: i32 = gfx.window.cellsize;
        drawX = gfx.window.gridoffsetx + piece_state.x * cs_i32;
        drawY = gfx.window.gridoffsety + piece_state.y * cs_i32;

        // Update entity with current position for future animations
        ecs.addOrReplace(components.Position, player_entity.?, components.Position{
            .x = @floatFromInt(drawX),
            .y = @floatFromInt(drawY),
        });
    }

    // Clear all existing block entities
    clearBlockEntities();

    // Get the current piece from the saved piece index
    const piece_type = pieces.tetraminos[piece_state.piece_index];
    const piece_shape = piece_type.shape[piece_state.rotation];
    const piece_color = piece_type.color;

    // Create entities for the active piece blocks
    createPieceEntities(drawX, drawY, piece_shape, piece_color, false);

    // Create entities for ghost piece blocks (semi-transparent preview at landing position)
    const ghostY = gfx.window.gridoffsety + piece_state.ghost_y * gfx.window.cellsize;
    const ghostColor = .{ piece_color[0], piece_color[1], piece_color[2], 200 }; // Increased alpha for better visibility
    createPieceEntities(drawX, ghostY, piece_shape, ghostColor, true);
}

// Update piece entities without redrawing (used after animations)
pub fn updatePieceEntities() void {
    const player_entity = getPlayerEntity() orelse return;

    // Get the player piece state
    const piece_state = ecs.get(components.PlayerPieceState, player_entity) orelse return;
    if (!piece_state.has_piece) return;

    // Get the current position from the player entity
    if (ecs.get(components.Position, player_entity)) |pos| {
        const drawX = @as(i32, @intFromFloat(pos.x));
        const drawY = @as(i32, @intFromFloat(pos.y));

        // Clear existing entities and create new ones
        clearBlockEntities();

        // Get the current piece from the saved piece index
        const piece_type = pieces.tetraminos[piece_state.piece_index];
        const piece_shape = piece_type.shape[piece_state.rotation];
        const piece_color = piece_type.color;

        // Create main piece entities
        createPieceEntities(drawX, drawY, piece_shape, piece_color, false);

        // Create ghost piece entities
        const ghostY = gfx.window.gridoffsety + piece_state.ghost_y * gfx.window.cellsize;
        const ghostColor = .{ piece_color[0], piece_color[1], piece_color[2], 120 }; // Semi-transparent
        createPieceEntities(drawX, ghostY, piece_shape, ghostColor, true);
    }
}

// Create entities for a tetris piece (either main piece or ghost)
pub fn createPieceEntities(x: i32, y: i32, shape: [4][4]bool, color: [4]u8, is_ghost: bool) void {
    const scale: f32 = 1.0;

    for (shape, 0..) |row, i| {
        for (row, 0..) |cell, j| {
            if (cell) {
                const cs_i32: i32 = gfx.window.cellsize;
                const cellX = @as(i32, @intCast(i)) * cs_i32;
                const cellY = @as(i32, @intCast(j)) * cs_i32;
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

// Get ghost piece's landing position from current state
pub fn ghosty() i32 {
    if (getPlayerEntity()) |entity| {
        if (ecs.get(components.PlayerPieceState, entity)) |piece_state| {
            return piece_state.ghost_y;
        }
    }
    return 0;
}
var piece_entities = std.ArrayList(ecsroot.Entity).init(std.heap.page_allocator);
var ghost_entities = std.ArrayList(ecsroot.Entity).init(std.heap.page_allocator);

pub fn harddrop() void {
    if (getPlayerEntity()) |entity| {
        if (ecs.get(components.PlayerPieceState, entity)) |piece_state| {
            if (!piece_state.has_piece) return;
        } else {
            return;
        }
    } else {
        return;
    }

    piece_entities.clearAndFree();
    ghost_entities.clearAndFree();

    // Collect piece entities
    var piece_it = getPieceBlocks();
    while (piece_it.next()) |entity| {
        piece_entities.append(entity) catch {};
    }

    // Collect ghost entities
    var ghost_it = getGhostBlocks();
    while (ghost_it.next()) |entity| {
        ghost_entities.append(entity) catch {};
    }

    if (piece_entities.items.len == 0) return;
    if (ghost_entities.items.len == 0) return; // Nothing to animate

    // We need to create animations for each piece block
    for (piece_entities.items) |piece_entity| {
        if (ecs.get(components.Position, piece_entity)) |piece_pos| {
            // Find the corresponding ghost block that has the same X position
            for (ghost_entities.items) |ghost_entity| {
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

                        // Add Sprite component with the same color, reduced opacity
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
