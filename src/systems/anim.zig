const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const ecsroot = @import("ecs");
const components = @import("../components.zig");
const gfx = @import("../gfx.zig");
const blocktextures = @import("../blocktextures.zig");
// calculate eased value based on animation progress
pub fn applyEasing(progress: f32, easing_type: components.easing_types) f32 {
    return switch (easing_type) {
        .linear => progress,
        .ease_in => std.math.pow(f32, progress, 2.0),
        .ease_out => 1.0 - std.math.pow(f32, 1.0 - progress, 2.0),
        .ease_in_out => {
            if (progress < 0.5) {
                return 2.0 * std.math.pow(f32, progress, 2.0);
            } else {
                return 1.0 - std.math.pow(f32, -2.0 * progress + 2.0, 2.0) / 2.0;
            }
        },
    };
}

// update position based on animation
fn updatePosition(position: *components.Position, animation: components.Animation, eased_progress: f32) void {
    if (animation.animate_position and animation.start_pos != null and animation.target_pos != null) {
        const start_pos = animation.start_pos.?;
        const target_pos = animation.target_pos.?;

        // interpolate position x
        position.x = start_pos[0] + (target_pos[0] - start_pos[0]) * eased_progress;

        // interpolate position y
        position.y = start_pos[1] + (target_pos[1] - start_pos[1]) * eased_progress;
    }
}

// update sprite properties based on animation
fn updateSprite(sprite: *components.Sprite, animation: components.Animation, eased_progress: f32) void {
    // update alpha/opacity
    if (animation.animate_alpha and animation.start_alpha != null and animation.target_alpha != null) {
        const start_alpha = animation.start_alpha.?;
        const target_alpha = animation.target_alpha.?;
        sprite.rgba[3] = @intFromFloat(@as(f32, @floatFromInt(start_alpha)) +
            (@as(f32, @floatFromInt(target_alpha)) - @as(f32, @floatFromInt(start_alpha))) *
                eased_progress);
    }

    // update scale
    if (animation.animate_scale and animation.start_scale != null and animation.target_scale != null) {
        const start_scale = animation.start_scale.?;
        const target_scale = animation.target_scale.?;
        sprite.size = start_scale + (target_scale - start_scale) * eased_progress;
    }

    // update color (RGB)
    if (animation.animate_color and animation.start_color != null and animation.target_color != null) {
        const start_color = animation.start_color.?;
        const target_color = animation.target_color.?;

        // interpolate each color channel (R, G, B)
        for (0..3) |i| {
            sprite.rgba[i] = @intFromFloat(@as(f32, @floatFromInt(start_color[i])) +
                (@as(f32, @floatFromInt(target_color[i])) - @as(f32, @floatFromInt(start_color[i]))) *
                    eased_progress);
        }
    }
    if (animation.animate_rotation and animation.start_rotation != null and animation.target_rotation != null) {
        const start_rotation = animation.start_rotation.?;
        const target_rotation = animation.target_rotation.?;
        // interpolate rotation
        sprite.rotation = start_rotation + (target_rotation - start_rotation) * eased_progress;
    }
}

// main animation system that updates all animated entities
pub fn animationSystem() void {
    const world = ecs.getWorld();

    // view entities with Animation component
    var view = world.view(.{components.Animation}, .{});
    var it = view.entityIterator();

    const current_time = std.time.milliTimestamp();
    var entities_to_update: [128]ecsroot.Entity = undefined;
    var num_entities: usize = 0;

    while (it.next()) |entity| {
        const animation = view.get(entity).*;

        // check if animation should start yet
        if (current_time < animation.start_time + animation.delay) {
            continue; // skip this animation for now
        }

        // calculate raw progress (0.0 to 1.0)
        const elapsed = current_time - (animation.start_time + animation.delay);
        const raw_progress = @min(@as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(animation.duration)), 1.0);

        // apply easing function
        const eased_progress = applyEasing(raw_progress, animation.easing);

        // update position component if it exists
        if (world.has(components.Position, entity)) {
            const position = world.get(components.Position, entity);
            updatePosition(position, animation, eased_progress);
        }

        // update sprite component if it exists
        if (world.has(components.Sprite, entity)) {
            const sprite = world.get(components.Sprite, entity);
            updateSprite(sprite, animation, eased_progress);
        }

        // check if animation is complete
        if (raw_progress >= 1.0) {
            // revert?
            if (animation.revert_when_done) {
                if (world.has(components.Position, entity) and animation.animate_position and animation.start_pos != null) {
                    const position = world.get(components.Position, entity);
                    position.* = components.Position{ .x = animation.start_pos.?[0], .y = animation.start_pos.?[1] };
                }

                if (world.has(components.Sprite, entity)) {
                    const sprite_ptr = world.get(components.Sprite, entity);

                    if (animation.animate_alpha and animation.start_alpha != null) {
                        sprite_ptr.rgba[3] = animation.start_alpha.?;
                    }

                    if (animation.animate_scale and animation.start_scale != null) {
                        sprite_ptr.size = animation.start_scale.?;
                    }

                    if (animation.animate_color and animation.start_color != null) {
                        sprite_ptr.rgba[0] = animation.start_color.?[0];
                        sprite_ptr.rgba[1] = animation.start_color.?[1];
                        sprite_ptr.rgba[2] = animation.start_color.?[2];
                    }

                    if (animation.animate_rotation and animation.start_rotation != null) {
                        sprite_ptr.rotation = animation.start_rotation.?;
                    }
                }
            }

            if (animation.remove_when_done) {
                // add to list of entities to remove animation from
                if (num_entities < entities_to_update.len) {
                    entities_to_update[num_entities] = entity;
                    num_entities += 1;
                }
            }
        }
    }

    // remove Animation component from completed animations
    for (entities_to_update[0..num_entities]) |entity| {
        world.remove(components.Animation, entity);
    }
}

// Helper functions to create common animations

// Create position animation (movement)
pub fn createMoveAnimation(entity: ecsroot.Entity, from_x: f32, from_y: f32, to_x: f32, to_y: f32, duration_ms: i64, easing_type: components.easing_types) void {
    const world = ecs.getWorld();

    // remove any existing animation component first
    if (world.has(components.Animation, entity)) {
        world.remove(components.Animation, entity);
    }

    // create the animation
    const anim = components.Animation{
        .animate_position = true,
        .start_pos = .{ from_x, from_y },
        .target_pos = .{ to_x, to_y },
        .start_time = std.time.milliTimestamp(),
        .duration = duration_ms,
        .easing = easing_type,
    };

    world.add(entity, anim);
}

pub fn createRowShiftAnimation(entity: ecsroot.Entity, from_y: f32, to_y: f32) void {
    const world = ecs.getWorld();

    if (ecs.get(components.Position, entity)) |_| {
        const position = world.get(components.Position, entity);
        const x = position.x;

        createMoveAnimation(entity, x, from_y, // Start position (x, y)
            x, to_y, // Target position (same x, new y)
            200, // 200ms for the shift animation
            .ease_in // Use ease in easing
        );
    }
}

// Create fade animation (alpha)
pub fn createFadeAnimation(entity: ecsroot.Entity, from_alpha: u8, to_alpha: u8, duration_ms: i64, easing_type: components.easing_types) void {
    const world = ecs.getWorld();

    // remove any existing animation component first
    if (world.has(components.Animation, entity)) {
        world.remove(components.Animation, entity);
    }

    // create the animation
    const anim = components.Animation{
        .animate_alpha = true,
        .start_alpha = from_alpha,
        .target_alpha = to_alpha,
        .start_time = std.time.milliTimestamp(),
        .duration = duration_ms,
        .easing = easing_type,
    };

    world.add(entity, anim);
}

// Create scale animation
pub fn createScaleAnimation(entity: ecsroot.Entity, from_scale: f32, to_scale: f32, duration_ms: i64, easing_type: components.easing_types) void {
    const world = ecs.getWorld();

    // remove any existing animation component first
    if (world.has(components.Animation, entity)) {
        world.remove(components.Animation, entity);
    }

    // create the animation
    const anim = components.Animation{
        .animate_scale = true,
        .start_scale = from_scale,
        .target_scale = to_scale,
        .start_time = std.time.milliTimestamp(),
        .duration = duration_ms,
        .easing = easing_type,
    };

    world.add(entity, anim);
}

// Create combined animation (position + fade)
pub fn createMoveAndFadeAnimation(entity: ecsroot.Entity, from_x: f32, from_y: f32, to_x: f32, to_y: f32, from_alpha: u8, to_alpha: u8, duration_ms: i64, easing_type: components.easing_types) void {
    const world = ecs.getWorld();

    // remove any existing animation component first
    if (world.has(components.Animation, entity)) {
        world.remove(components.Animation, entity);
    }

    // create the animation with multiple properties
    const anim = components.Animation{
        .animate_position = true,
        .start_pos = .{ from_x, from_y },
        .target_pos = .{ to_x, to_y },
        .animate_alpha = true,
        .start_alpha = from_alpha,
        .target_alpha = to_alpha,
        .start_time = std.time.milliTimestamp(),
        .duration = duration_ms,
        .easing = easing_type,
    };

    world.add(entity, anim);
}

// Create combined animation (position + rotation)
pub fn createMoveAndRotateAnimation(entity: ecsroot.Entity, from_x: f32, from_y: f32, to_x: f32, to_y: f32, from_rotation: f32, to_rotation: f32, duration_ms: i64, easing_type: components.easing_types) void {
    const world = ecs.getWorld();

    // remove any existing animation component first
    if (world.has(components.Animation, entity)) {
        world.remove(components.Animation, entity);
    }

    // create the animation with multiple properties
    const anim = components.Animation{
        .animate_position = true,
        .start_pos = .{ from_x, from_y },
        .target_pos = .{ to_x, to_y },
        .animate_rotation = true,
        .start_rotation = from_rotation,
        .target_rotation = to_rotation,
        .start_time = std.time.milliTimestamp(),
        .duration = duration_ms,
        .easing = easing_type,
    };

    world.add(entity, anim);
}

// Simple flash animation: fade the sprite's alpha from start_alpha to target_alpha
// over the given duration, then automatically reset it back to the starting alpha
// when the animation is finished.
pub fn createFlashAnimation(entity: ecsroot.Entity, start_alpha: u8, target_alpha: u8, duration_ms: i64) void {
    const world = ecs.getWorld();

    if (world.has(components.Animation, entity)) {
        world.remove(components.Animation, entity);
    }

    const anim = components.Animation{
        .animate_alpha = true,
        .start_alpha = start_alpha,
        .target_alpha = target_alpha,
        .start_time = std.time.milliTimestamp(),
        .duration = duration_ms,
        .easing = .linear,
        .revert_when_done = true,
    };

    world.add(entity, anim);
}

// Create new falling row effects for cleared lines using Animation components
pub fn createRippledFallingRow(_: usize, existing_entities: []const ecsroot.Entity) void {
    const world = ecs.getWorld();

    // Create new animation entities based on the cleared row's entities
    for (existing_entities) |old_entity| {
        // Get position and sprite from the original entity
        if (ecs.get(components.Position, old_entity)) |old_position| {
            var sprite_color = [4]u8{ 255, 255, 255, 255 };

            if (ecs.get(components.Sprite, old_entity)) |old_sprite| {
                sprite_color = old_sprite.rgba;
            }

            // Create a new entity for the falling animation
            const new_entity = world.create();

            // Start position is the same as the original entity
            const start_y_pos = old_position.y;

            // Target position is off the bottom of the screen - use original height
            const target_y_pos = @as(f32, @floatFromInt(gfx.Window.OGHEIGHT + 500));

            // Add Position component with the same x position
            world.add(new_entity, components.Position{
                .x = old_position.x,
                .y = start_y_pos,
            });

            // Add Sprite component with the same color
            world.add(new_entity, components.Sprite{
                .rgba = sprite_color,
                .size = 1.0,
            });

            _ = blocktextures.addTextureComponent(new_entity, sprite_color) catch |err| {
                std.debug.print("Failed to add texture component: {}\n", .{err});
            };
            // Calculate duration with a ripple effect based on x-position
            // This creates a ripple effect as each cell falls with slight delay
            const duration_ms = @as(i64, @intFromFloat(old_position.x * 5));

            // Create animation component directly with rotation
            const anim = components.Animation{
                .animate_position = true,
                .start_pos = .{ old_position.x, start_y_pos },
                .target_pos = .{ old_position.x, target_y_pos },
                .animate_rotation = true, // Add rotation
                .start_rotation = 0.0, // Start at 0 degrees rotation
                .target_rotation = 4.0, // Rotate twice (720 degrees) as it falls
                .start_time = std.time.milliTimestamp(),
                .duration = 800 + duration_ms, // Longer duration for a more noticeable effect
                .easing = .ease_out,
                .remove_when_done = true,
            };

            world.add(new_entity, anim);
        }
    }
}

// Create an animation for the player piece movement
pub fn createPlayerPieceAnimation(entity: ecsroot.Entity, from_x: f32, from_y: f32, to_x: f32, to_y: f32) void {
    //const world = ecs.getWorld();

    // Only add the animation if the entity has a Position component
    if (ecs.get(components.Position, entity)) |_| {
        // Create an animation from current position to target
        // Use a shorter duration (50ms) for player piece movements to keep them snappy
        createMoveAnimation(entity, from_x, from_y, // Start position
            to_x, to_y, // Target position
            50, // 50ms duration (same as original player animation)
            .ease_in_out);
    }
}
