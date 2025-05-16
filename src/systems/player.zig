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
const blocks = @import("../blockbuilder.zig");

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
        ecs.replace(components.Position, entity, components.Position{
            .x = 0,
            .y = 0,
        });

        // Add the player piece state component with default values
        ecs.replace(components.PlayerPieceState, entity, components.PlayerPieceState{
            .x = 4,
            .y = 0,
            .rotation = 0,
            .ghost_y = 0,
            .piece_index = 0,
            .has_piece = false,
        });

        ecs.replace(components.ActivePieceTag, entity, components.ActivePieceTag{});
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
    ecs.replace(components.Position, player_entity.?, components.Position{
        .x = targetx,
        .y = targety,
    });

    // Update visual representation with current piece
    updatePieceEntities();
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
    ecs.replace(components.PlayerPieceState, player_entity, components.PlayerPieceState{
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

    ecs.replace(components.Position, player_entity, components.Position{
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
        std.debug.print("Player entity has no Position component\n", .{});
        return;
    }
    // Clear all existing player blocks
    blocks.clearAllPlayerBlocks();

    // Get the current piece from the saved piece index
    const piece_type = pieces.tetraminos[piece_state.piece_index];
    const piece_shape = piece_type.shape[piece_state.rotation];
    const piece_color = piece_type.color;

    // Create entities for the active piece blocks
    blocks.createPlayerPiece(drawX, drawY, piece_shape, piece_color);

    // Create entities for ghost piece blocks (semi-transparent preview at landing position)
    const ghostY = gfx.window.gridoffsety + piece_state.ghost_y * gfx.window.cellsize;
    // Use directly the createGhostPiece function from blocks module
    blocks.createGhostPiece(drawX, ghostY, piece_shape, piece_color);
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
        blocks.clearAllPlayerBlocks();

        // Get the current piece from the saved piece index
        const piece_type = pieces.tetraminos[piece_state.piece_index];
        const piece_shape = piece_type.shape[piece_state.rotation];
        const piece_color = piece_type.color;

        // Create main piece entities
        blocks.createPieceEntities(drawX, drawY, piece_shape, piece_color, false);

        // Create ghost piece entities
        const ghostY = gfx.window.gridoffsety + piece_state.ghost_y * gfx.window.cellsize;
        blocks.createGhostPiece(drawX, ghostY, piece_shape, piece_color);
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
                            .rgba = .{ color[0], color[1], color[2], 100 },
                            .size = 1.0,
                        });

                        // Add texture
                        _ = blocks.addBlockTextureWithAtlas(new_entity, color) catch |err| {
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
    blocks.clearAllPlayerBlocks();
    // Find and destroy the player entity
    if (getPlayerEntity()) |entity| {
        ecs.getWorld().destroy(entity);
    }
}
