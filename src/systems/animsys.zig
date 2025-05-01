const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const ecsroot = @import("ecs");
const components = @import("../components.zig");

// calculate eased value based on animation progress
fn applyEasing(progress: f32, easing_type: components.easing_types) f32 {
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
        // `view` only contains the `Animation` component, so the registry returned a
        // `BasicView`, whose `get` method requires only the `entity` parameter.
        // Dereference the returned pointer to work with a copy of the component.
        const animation = view.get(entity).*;

        // check if animation should start yet (handle delay)
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
        if (raw_progress >= 1.0 and animation.remove_when_done) {
            // add to list of entities to remove animation from
            if (num_entities < entities_to_update.len) {
                entities_to_update[num_entities] = entity;
                num_entities += 1;
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
