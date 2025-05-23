// game.zig - Core spaced game logic
const common = @import("common.zig");
const std = common.std;
const components = common.components;
const ecs = common.ecs;
const events = common.events;
const ray = common.ray;
const constants = common.game_constants;

var player_entity: ?ecs.Entity = null;
var game_time: f32 = 0.0;
var last_enemy_spawn: f32 = 0.0;
const ENEMY_SPAWN_INTERVAL: f32 = 2.0; // seconds between spawns

pub fn init(allocator: std.mem.Allocator) !void {
    _ = allocator;

    // Create player entity
    const player = ecs.createEntity();
    player_entity = player;

    // Add player components
    ecs.add(player, components.Player{});
    ecs.add(player, components.Position{ .x = constants.WORLD_WIDTH / 2, .y = constants.WORLD_HEIGHT / 2 });
    ecs.add(player, components.Velocity{ .x = 0, .y = 0 });
    ecs.add(player, components.Sprite{
        .rgba = .{ 0, 255, 0, 255 }, // Green player
        .size = constants.PLAYER_SIZE, // Actual pixel size
    });

    // Add texture component for rendering (solid color)
    try addSolidColorTexture(player, .{ 0, 255, 0, 255 });
    ecs.add(player, components.Health{
        .current = constants.PLAYER_START_HEALTH,
        .max = constants.PLAYER_MAX_HEALTH,
    });

    // Add collider for collision detection
    ecs.add(player, components.Collider{
        .shape = .{ .rectangle = ray.Rectangle{ .x = 0, .y = 0, .width = constants.PLAYER_SIZE, .height = constants.PLAYER_SIZE } },
        .layer = 1, // Player layer
        .is_trigger = false, // Participate in collision detection
    });

    std.debug.print("Player created at ({}, {})\n", .{ constants.WORLD_WIDTH / 2, constants.WORLD_HEIGHT / 2 });
}

pub fn deinit() void {
    // Cleanup handled by ECS
}

pub fn update(dt: f32) void {
    game_time += dt;

    // Spawn enemies periodically
    if (game_time - last_enemy_spawn > ENEMY_SPAWN_INTERVAL) {
        spawnEnemy() catch |err| {
            std.debug.print("Failed to spawn enemy: {}\n", .{err});
        };
        last_enemy_spawn = game_time;
    }

    // Update player movement based on input
    updatePlayerMovement(dt);

    // Update enemy AI
    updateEnemyAI(dt);

    // Update positions without gravity (custom for top-down game)
    updateMovement(dt);

    // Update camera to follow player
    updateCamera();
}

fn updatePlayerMovement(dt: f32) void {
    _ = dt;
    if (player_entity) |player| {
        if (ecs.get(components.Velocity, player)) |vel| {
            var new_vel = vel.*;
            new_vel.x = 0;
            new_vel.y = 0;

            // WASD movement
            if (ray.IsKeyDown(ray.KEY_W) or ray.IsKeyDown(ray.KEY_UP)) {
                new_vel.y = -constants.PLAYER_SPEED;
            }
            if (ray.IsKeyDown(ray.KEY_S) or ray.IsKeyDown(ray.KEY_DOWN)) {
                new_vel.y = constants.PLAYER_SPEED;
            }
            if (ray.IsKeyDown(ray.KEY_A) or ray.IsKeyDown(ray.KEY_LEFT)) {
                new_vel.x = -constants.PLAYER_SPEED;
            }
            if (ray.IsKeyDown(ray.KEY_D) or ray.IsKeyDown(ray.KEY_RIGHT)) {
                new_vel.x = constants.PLAYER_SPEED;
            }

            // Normalize diagonal movement
            if (new_vel.x != 0 and new_vel.y != 0) {
                const length = @sqrt(new_vel.x * new_vel.x + new_vel.y * new_vel.y);
                new_vel.x = new_vel.x / length * constants.PLAYER_SPEED;
                new_vel.y = new_vel.y / length * constants.PLAYER_SPEED;
            }

            ecs.replace(components.Velocity, player, new_vel);
        }
    }
}

fn updateMovement(dt: f32) void {
    // Update all entities with position and velocity (no gravity for top-down game)
    var view = ecs.getWorld().view(.{ components.Position, components.Velocity }, .{});
    var iter = view.entityIterator();

    while (iter.next()) |entity| {
        const pos = view.get(components.Position, entity);
        const vel = view.get(components.Velocity, entity);

        var new_pos = pos.*;
        new_pos.x += vel.x * dt;
        new_pos.y += vel.y * dt;

        // Keep player in bounds
        if (ecs.has(components.Player, entity)) {
            new_pos.x = std.math.clamp(new_pos.x, 0, constants.WORLD_WIDTH - constants.PLAYER_SIZE);
            new_pos.y = std.math.clamp(new_pos.y, 0, constants.WORLD_HEIGHT - constants.PLAYER_SIZE);
        }

        ecs.replace(components.Position, entity, new_pos);
    }
}

fn updateCamera() void {
    // Center camera on player
    if (player_entity) |player| {
        if (ecs.get(components.Position, player)) |pos| {
            // TODO: Update camera in graphics system once we have camera access
            // For now, the rendering will be at world coordinates
            _ = pos;
        }
    }
}

pub fn process(queue: *events.EventQueue) void {
    for (queue.items()) |event| {
        switch (event.event) {
            .Debug => {
                std.debug.print("Debug: game_time={:.2}s\n", .{game_time});
                if (player_entity) |player| {
                    if (ecs.get(components.Position, player)) |pos| {
                        std.debug.print("Player pos: ({:.1}, {:.1})\n", .{ pos.x, pos.y });
                    }
                }
            },
            .GameOver => {
                std.debug.print("Game Over!\n", .{});
            },
            else => {
                // Handle other events as needed
            },
        }
    }
}

// Helper function to create solid color texture for entities
fn addSolidColorTexture(entity: ecs.Entity, color: [4]u8) !void {
    const textures = common.textures;

    // Create a key for this color
    var buf: [64]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "solid_{d}_{d}_{d}_{d}", .{ color[0], color[1], color[2], color[3] }) catch {
        return error.KeyFormatError;
    };

    // Try to get existing entry or create new one
    const entry = textures.getEntry(key) catch |err| blk: {
        if (err != error.EntryNotFound) return err;

        // Create new entry - need heap-allocated key
        const heap_key = try std.heap.c_allocator.dupe(u8, key);
        var color_copy = color;
        break :blk try textures.createEntry(heap_key, drawSolidIntoTile, &color_copy);
    };

    // Add texture component to entity
    ecs.add(entity, components.Texture{
        .texture = entry.tex,
        .uv = entry.uv,
        .created = false, // Shared atlas entry
    });
}

// Draw function for solid color tiles
fn drawSolidIntoTile(
    page_tex: *const ray.RenderTexture2D,
    tile_x: i32,
    tile_y: i32,
    tile_size: i32,
    _: []const u8,
    context: ?*const anyopaque,
) void {
    const color_ptr = @as(*const [4]u8, @ptrCast(@alignCast(context.?)));
    const color = ray.Color{
        .r = color_ptr[0],
        .g = color_ptr[1],
        .b = color_ptr[2],
        .a = color_ptr[3],
    };

    ray.BeginTextureMode(page_tex.*);
    ray.DrawRectangle(tile_x, tile_y, tile_size, tile_size, color);
    ray.EndTextureMode();
}

// Spawn a new enemy at a random edge of the screen
fn spawnEnemy() !void {
    const enemy = ecs.createEntity();

    // Spawn at random edge of screen
    var spawn_x: f32 = 0;
    var spawn_y: f32 = 0;
    const edge = @as(i32, @intCast(@mod(std.time.timestamp(), 4)));

    switch (edge) {
        0 => { // Top edge
            spawn_x = @mod(game_time * 100, constants.WORLD_WIDTH);
            spawn_y = -constants.ENEMY_SIZE;
        },
        1 => { // Right edge
            spawn_x = constants.WORLD_WIDTH + constants.ENEMY_SIZE;
            spawn_y = @mod(game_time * 150, constants.WORLD_HEIGHT);
        },
        2 => { // Bottom edge
            spawn_x = @mod(game_time * 200, constants.WORLD_WIDTH);
            spawn_y = constants.WORLD_HEIGHT + constants.ENEMY_SIZE;
        },
        else => { // Left edge
            spawn_x = -constants.ENEMY_SIZE;
            spawn_y = @mod(game_time * 180, constants.WORLD_HEIGHT);
        },
    }

    // Add enemy components
    ecs.add(enemy, components.Enemy{});
    ecs.add(enemy, components.Position{ .x = spawn_x, .y = spawn_y });
    ecs.add(enemy, components.Velocity{ .x = 0, .y = 0 });
    ecs.add(enemy, components.Sprite{
        .rgba = .{ 255, 0, 0, 255 }, // Red enemies
        .size = constants.ENEMY_SIZE,
    });
    ecs.add(enemy, components.Health{
        .current = 50.0,
        .max = 50.0,
    });

    // Add collider for collision detection
    ecs.add(enemy, components.Collider{
        .shape = .{ .rectangle = ray.Rectangle{ .x = 0, .y = 0, .width = constants.ENEMY_SIZE, .height = constants.ENEMY_SIZE } },
        .layer = 2, // Enemy layer
        .is_trigger = false, // Participate in collision detection
    });

    // Add texture component for rendering
    try addSolidColorTexture(enemy, .{ 255, 0, 0, 255 });

    std.debug.print("Spawned enemy at ({:.1}, {:.1})\n", .{ spawn_x, spawn_y });
}

// Update enemy AI to move toward player
fn updateEnemyAI(dt: f32) void {
    _ = dt;

    if (player_entity == null) return;

    const player_pos = ecs.get(components.Position, player_entity.?) orelse return;

    // Update all enemies to move toward player
    var view = ecs.getWorld().view(.{ components.Enemy, components.Position, components.Velocity }, .{});
    var iter = view.entityIterator();

    while (iter.next()) |enemy| {
        const enemy_pos = view.get(components.Position, enemy);

        // Calculate direction to player
        const dx = player_pos.x - enemy_pos.x;
        const dy = player_pos.y - enemy_pos.y;
        const distance = @sqrt(dx * dx + dy * dy);

        if (distance > 0) {
            // Normalize direction and apply enemy speed
            const new_vel = components.Velocity{
                .x = (dx / distance) * constants.ENEMY_SPEED,
                .y = (dy / distance) * constants.ENEMY_SPEED,
            };

            ecs.replace(components.Velocity, enemy, new_vel);
        }
    }
}
