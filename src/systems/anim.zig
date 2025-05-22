const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const ecsroot = @import("ecs");
const components = @import("../components.zig");
const gfx = @import("../gfx.zig");
const textures = @import("../textures.zig");
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
inline fn updatePosition(position: *components.Position, animation: components.Animation, eased_progress: f32) void {
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
inline fn updateSprite(sprite: *components.Sprite, animation: components.Animation, eased_progress: f32) void {
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
pub fn update() void {
    const world = ecs.getWorld();

    // Owning group for Animation components (zipped, fast iteration)
    var anim_group = world.group(
        .{ components.Animation }, // owned
        .{}, // includes
        .{}, // excludes
    );

    const IterComp = struct { anim: *components.Animation };
    var it = anim_group.iterator(IterComp);

    const current_time = std.time.milliTimestamp();
    var entities_to_update: [128]ecsroot.Entity = undefined;
    var num_entities: usize = 0;

    while (it.next()) |comps| {
        const entity = it.entity();
        const animation = comps.anim.*;

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

            // Check if we should destroy the entity
            if (animation.destroy_entity_when_done) {
                ecs.destroyEntity(entity);
            }
        }
    }

    // remove Animation component from completed animations
    for (entities_to_update[0..num_entities]) |entity| {
        // Only if entity still exists (might have been destroyed if destroy_entity_when_done was true)
        if (world.valid(entity)) {
            world.remove(components.Animation, entity);
        }
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

    for (existing_entities) |entity| {
        const position_opt = ecs.get(components.Position, entity);
        if (position_opt == null) continue; // Shouldn't happen but be safe.

        const pos = position_opt.?;

        // Ensure the entity has a Sprite so it can still be rendered once the GridPos
        // component is removed. If not present we add a basic white one.
        if (!ecs.has(components.Sprite, entity)) {
            world.add(entity, components.Sprite{ .rgba = .{ 255, 255, 255, 255 }, .size = 1.0 });
        }

        // Calculate destination off-screen.
        const target_y_pos: f32 = @floatFromInt(gfx.Window.OGHEIGHT + 500);

        // Small ripple delay based on x position so cells on the left start first.
        const delay_ms: i64 = @as(i64, @intFromFloat(pos.x * 5.0));

        // `destroy_entity_when_done` so memory is eventually reclaimed
        const anim = components.Animation{
            .animate_position = true,
            .start_pos = .{ pos.x, pos.y },
            .target_pos = .{ pos.x, target_y_pos },
            .animate_rotation = true,
            .start_rotation = 0.0,
            .target_rotation = 4.0,
            .start_time = std.time.milliTimestamp(),
            .duration = 800 + delay_ms,
            .delay = 50,
            .easing = .ease_out,
            .remove_when_done = true,
            .destroy_entity_when_done = true,
        };

        if (world.has(components.Animation, entity)) {
            world.remove(components.Animation, entity);
        }
        world.add(entity, anim);
    }
}

pub fn createExplosionAll() void {
    const world = ecs.getWorld();
    var view = world.view(.{components.Position, components.Sprite}, .{});
    var it = view.entityIterator();

    const now = std.time.milliTimestamp();
    var rng = std.Random.DefaultPrng.init(blk: {
        const seed: u64 = @intCast(now);
        break :blk seed;
    });
    var rand = rng.random();

    const win_w: f32 = @as(f32, @floatFromInt(gfx.Window.OGWIDTH));
    const win_h: f32 = @as(f32, @floatFromInt(gfx.Window.OGHEIGHT));
    const diag: f32 = std.math.sqrt(win_w * win_w + win_h * win_h);

    while (it.next()) |entity| {
        const pos = view.get(components.Position, entity);
        const sprite = view.get(components.Sprite, entity);

        const deg: u32 = rand.intRangeAtMost(u32, 0, 359);
        const angle: f32 = @as(f32, @floatFromInt(deg)) * std.math.pi / 180.0;
        const target_x: f32 = pos.x + std.math.cos(angle) * diag;
        const target_y: f32 = pos.y + std.math.sin(angle) * diag;

        const start_scale: f32 = sprite.size;
        const scale_i: u32 = rand.intRangeAtMost(u32, 50, 200);
        const target_scale: f32 = @as(f32, @floatFromInt(scale_i)) / 100.0;

        const start_rot: f32 = sprite.rotation;
        const rot_i: i32 = rand.intRangeAtMost(i32, -400, 400);
        const target_rot: f32 = @as(f32, @floatFromInt(rot_i)) / 100.0;

        const dur: i64 = rand.intRangeAtMost(i64, 500, 1500);
        const anim = components.Animation{
            .animate_position = true,
            .start_pos = .{ pos.x, pos.y },
            .target_pos = .{ target_x, target_y },
            .animate_scale = true,
            .start_scale = start_scale,
            .target_scale = target_scale,
            .animate_rotation = true,
            .start_rotation = start_rot,
            .target_rotation = target_rot,
            .start_time = now,
            .duration = dur,
            .easing = .ease_out,
            .remove_when_done = true,
            .destroy_entity_when_done = true,
        };

        if (world.has(components.Animation, entity)) {
            world.remove(components.Animation, entity);
        }
        world.add(entity, anim);
    }
}
