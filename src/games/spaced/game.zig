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
const ENEMY_SPAWN_INTERVAL: f32 = 0.1; // seconds between spawns

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
        .rgba = .{ 255, 255, 255, 255 }, // White (no tint)
        .size = constants.PLAYER_SIZE, // Actual pixel size
        .rotation = 0.0, // Start facing up (0 = north)
    });
    ecs.add(player, components.Spaceship{
        .max_speed = constants.PLAYER_SPEED,
        .acceleration = constants.PLAYER_ACCELERATION,
        .deceleration = constants.PLAYER_DECELERATION,
        .turn_speed = constants.PLAYER_TURN_SPEED,
    });
    ecs.add(player, components.ThrustEffect{});
    ecs.add(player, components.ControlInput{}); // For keyboard input

    // Add texture component for rendering (ship.png)
    try addShipTexture(player);
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

    // Update control inputs
    updatePlayerInput(); // Keyboard -> ControlInput for player
    updateEnemyInput(); // AI -> ControlInput for enemies

    // Process all spaceship movement based on control inputs
    updateSpaceshipMovement(dt);

    // Note: Movement and collision detection is handled by the collision system in gfx.frame()

    // Update camera to follow player
    updateCamera();
}

fn updatePlayerInput() void {
    if (player_entity) |player| {
        var control = ecs.get(components.ControlInput, player) orelse return;

        // Read keyboard input
        control.turn_input = 0.0;
        control.thrust_input = 0.0;

        // Rotation input (A/D or Left/Right)
        if (ray.IsKeyDown(ray.KEY_A) or ray.IsKeyDown(ray.KEY_LEFT)) {
            control.turn_input = -1.0;
        }
        if (ray.IsKeyDown(ray.KEY_D) or ray.IsKeyDown(ray.KEY_RIGHT)) {
            control.turn_input = 1.0;
        }

        // Thrust input (W or Up)
        if (ray.IsKeyDown(ray.KEY_W) or ray.IsKeyDown(ray.KEY_UP)) {
            control.thrust_input = 1.0;
        }
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

// Helper function to create ship.png texture for entities
fn addShipTexture(entity: ecs.Entity) !void {
    const textures = common.textures;

    // Use ship.png from resources
    const key = "ship";

    // Try to get existing entry or create new one
    const entry = textures.getEntry(key) catch |err| blk: {
        if (err != error.EntryNotFound) return err;

        // Create new entry - load ship.png from resources
        const heap_key = try std.heap.c_allocator.dupe(u8, key);
        const file_path = "resources/texture/ship.png";
        break :blk try textures.createEntry(heap_key, drawPngIntoTile, file_path.ptr);
    };

    // Add texture component to entity
    ecs.add(entity, components.Texture{
        .texture = entry.tex,
        .uv = entry.uv,
        .created = false, // Shared atlas entry
    });
}

// Helper function to create red-tinted spaceship texture for enemies
fn addEnemyShipTexture(entity: ecs.Entity) !void {
    const textures = common.textures;

    // Use ship.png with red tint for enemies
    const key = "enemy_ship";

    // Try to get existing entry or create new one
    const entry = textures.getEntry(key) catch |err| blk: {
        if (err != error.EntryNotFound) return err;

        // Create new entry - load ship.png from resources
        const heap_key = try std.heap.c_allocator.dupe(u8, key);
        const file_path = "resources/texture/ship.png";
        break :blk try textures.createEntry(heap_key, drawPngIntoTile, file_path.ptr);
    };

    // Add texture component to entity
    ecs.add(entity, components.Texture{
        .texture = entry.tex,
        .uv = entry.uv,
        .created = false, // Shared atlas entry
    });
}

// Draw function for PNG files into atlas tiles
fn drawPngIntoTile(
    page_tex: *const ray.RenderTexture2D,
    tile_x: i32,
    tile_y: i32,
    tile_size: i32,
    _: []const u8,
    context: ?*const anyopaque,
) void {
    // Get the file path from context
    const file_path = @as([*:0]const u8, @ptrCast(context.?));

    // Load the PNG texture
    const texture = ray.LoadTexture(file_path);
    defer ray.UnloadTexture(texture);

    // Draw it into the tile (flipped vertically to point up)
    ray.BeginTextureMode(page_tex.*);
    const src = ray.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(texture.width), .height = -@as(f32, @floatFromInt(texture.height)) }; // Negative height flips vertically
    const dest = ray.Rectangle{ .x = @floatFromInt(tile_x), .y = @floatFromInt(tile_y), .width = @floatFromInt(tile_size), .height = @floatFromInt(tile_size) };
    ray.DrawTexturePro(texture, src, dest, ray.Vector2{ .x = 0, .y = 0 }, 0, ray.WHITE);
    ray.EndTextureMode();
}

// Draw function for solid color tiles (for enemies)
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
        .rgba = .{ 255, 255, 0, 255 }, // White for proper texture tinting
        .size = constants.ENEMY_SIZE,
        .rotation = 0.0,
    });
    ecs.add(enemy, components.Health{
        .current = 50.0,
        .max = 50.0,
    });

    // Add control input component for AI
    ecs.add(enemy, components.ControlInput{});

    // Add spaceship physics component for enemies
    ecs.add(enemy, components.Spaceship{
        .max_speed = constants.ENEMY_SPEED,
        .acceleration = 200.0,
        .deceleration = 100.0,
        .turn_speed = 1.5,
        .thrust = 0.0,
        .target_rotation = 0.0,
        .angular_velocity = 0.0,
        .thrust_particles = false,
        .banking_angle = 0.0,
    });

    // Add collider for collision detection
    ecs.add(enemy, components.Collider{
        .shape = .{ .rectangle = ray.Rectangle{ .x = 0, .y = 0, .width = constants.ENEMY_SIZE, .height = constants.ENEMY_SIZE } },
        .layer = 2, // Enemy layer
        .is_trigger = false, // Participate in collision detection
    });

    // Add texture component for rendering (red-tinted spaceship)
    try addEnemyShipTexture(enemy);

    std.debug.print("Spawned enemy at ({:.1}, {:.1})\n", .{ spawn_x, spawn_y });
}

// Animation helper functions for later enhancement
// TODO: Add thrust particle effects and more sophisticated animations

// Update enemy AI by generating control inputs
fn updateEnemyInput() void {
    if (player_entity == null) return;

    const player_pos = ecs.get(components.Position, player_entity.?) orelse return;

    // Update all enemies to generate control inputs based on AI
    var view = ecs.getWorld().view(.{ components.Enemy, components.Position, components.ControlInput, components.Sprite }, .{});
    var iter = view.entityIterator();

    while (iter.next()) |enemy| {
        const enemy_pos = view.get(components.Position, enemy);
        var control = view.get(components.ControlInput, enemy);
        const sprite = view.get(components.Sprite, enemy);

        // Calculate direction to player
        const dx = player_pos.x - enemy_pos.x;
        const dy = player_pos.y - enemy_pos.y;
        const distance = @sqrt(dx * dx + dy * dy);

        if (distance > 50.0) {
            // Calculate desired angle to face player
            const desired_angle = std.math.atan2(dy, dx);

            // Convert to normalized rotation (0.0 to 1.0)
            // The texture points up at rotation = 0, so we need to adjust
            var target_rotation = (desired_angle + std.math.pi / 2.0) / std.math.tau;
            while (target_rotation < 0) target_rotation += 1.0;
            while (target_rotation >= 1.0) target_rotation -= 1.0;

            // Calculate angle difference for turning
            const current_rotation = sprite.rotation;
            var angle_diff = target_rotation - current_rotation;

            // Handle wrap-around
            if (angle_diff > 0.5) angle_diff -= 1.0;
            if (angle_diff < -0.5) angle_diff += 1.0;

            // Generate turn input based on angle difference
            if (@abs(angle_diff) > 0.02) { // Dead zone to prevent oscillation
                control.turn_input = std.math.clamp(angle_diff * 5.0, -1.0, 1.0); // Proportional control
            } else {
                control.turn_input = 0.0;
            }

            // Only thrust if we're facing roughly the right direction (within 30 degrees)
            if (@abs(angle_diff) < 0.083) { // 30 degrees in normalized units
                control.thrust_input = 1.0;
            } else {
                control.thrust_input = 0.0; // Turn first, then thrust
            }
        } else {
            // Stop when close to player
            control.turn_input = 0.0;
            control.thrust_input = 0.0;
        }
    }
}

// Update spaceship movement for all entities with control inputs
fn updateSpaceshipMovement(dt: f32) void {
    var view = ecs.getWorld().view(.{ components.Spaceship, components.Velocity, components.Sprite, components.ControlInput }, .{});
    var iter = view.entityIterator();

    while (iter.next()) |entity| {
        var ship = view.get(components.Spaceship, entity);
        var vel = view.get(components.Velocity, entity);
        var sprite = view.get(components.Sprite, entity);
        const control = view.get(components.ControlInput, entity);

        // Update thrust effect if this entity has one
        if (ecs.get(components.ThrustEffect, entity)) |thrust_effect| {
            thrust_effect.intensity = control.thrust_input;
        }

        // Update angular velocity based on control input
        if (control.turn_input != 0.0) {
            // Apply turn acceleration
            ship.angular_velocity += control.turn_input * ship.turn_speed * dt;
            ship.angular_velocity = std.math.clamp(ship.angular_velocity, -ship.turn_speed, ship.turn_speed);
        } else {
            // Decelerate rotation when no input
            const decel = ship.turn_speed * 3.0 * dt;
            if (@abs(ship.angular_velocity) < decel) {
                ship.angular_velocity = 0.0;
            } else {
                ship.angular_velocity -= std.math.sign(ship.angular_velocity) * decel;
            }
        }

        // Apply rotation
        sprite.rotation += ship.angular_velocity * dt;
        // Normalize rotation to 0-1 range
        while (sprite.rotation >= 1.0) sprite.rotation -= 1.0;
        while (sprite.rotation < 0.0) sprite.rotation += 1.0;

        // Thrust physics
        if (control.thrust_input > 0.0) {
            // Convert rotation to angle (0.0 = pointing up, increases clockwise)
            const angle = sprite.rotation * std.math.tau;

            // Calculate thrust force components (ship points up at rotation = 0)
            const thrust_force = control.thrust_input * ship.acceleration;
            const force_x = @sin(angle) * thrust_force;
            const force_y = -@cos(angle) * thrust_force; // Negative because Y is down in screen coords

            // Apply thrust to velocity
            vel.x += force_x * dt;
            vel.y += force_y * dt;
        } else {
            // Apply deceleration when not thrusting
            const decel_factor = std.math.pow(f32, ship.deceleration / 1000.0, dt);
            vel.x *= decel_factor;
            vel.y *= decel_factor;
        }

        // Speed limiting
        const current_speed = @sqrt(vel.x * vel.x + vel.y * vel.y);
        if (current_speed > ship.max_speed) {
            const scale = ship.max_speed / current_speed;
            vel.x *= scale;
            vel.y *= scale;
        }

        // Banking effect for visual appeal
        const target_bank = ship.angular_velocity * 0.3;
        ship.banking_angle += (target_bank - ship.banking_angle) * 5.0 * dt;
    }
}
