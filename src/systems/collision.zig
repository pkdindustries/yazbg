const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const ecsroot = @import("ecs");
const components = @import("../components.zig");

// simple collision system using raylib's built-in collision functions
pub fn update() void {
    // move all entities with velocity
    moveEntities();
    
    // check collisions between entities
    checkCollisions();
}

fn moveEntities() void {
    var moving = ecs.getWorld().view(.{ components.Position, components.Velocity }, .{});
    var iter = moving.entityIterator();
    
    const dt = ray.GetFrameTime();
    const gravity = 500.0; // pixels per second squared
    
    while (iter.next()) |entity| {
        const pos = moving.get(components.Position, entity);
        const vel = moving.get(components.Velocity, entity);
        
        // apply gravity
        vel.y += gravity * dt;
        
        // apply velocity
        pos.x += vel.x * dt;
        pos.y += vel.y * dt;
        
        // simple bounce off screen edges
        if (pos.x < 0 or pos.x > 640) {
            vel.x *= -0.8; // bounce with dampening
        }
        if (pos.y > 760) {
            vel.y *= -0.6; // bounce off bottom
            pos.y = 760;
        }
    }
}

fn checkCollisions() void {
    var colliders = ecs.getWorld().view(.{ components.Position, components.Collider }, .{});
    var iter1 = colliders.entityIterator();
    
    // simple O(n²) collision detection - good enough for vampire survivors
    while (iter1.next()) |entity1| {
        const pos1 = colliders.get(components.Position, entity1);
        const col1 = colliders.get(components.Collider, entity1);
        
        var iter2 = colliders.entityIterator();
        while (iter2.next()) |entity2| {
            if (entity1 == entity2) continue;
            
            const pos2 = colliders.get(components.Position, entity2);
            const col2 = colliders.get(components.Collider, entity2);
            
            // skip if on same collision layer
            if (col1.layer == col2.layer) continue;
            
            if (checkCollision(pos1, col1, pos2, col2)) {
                // collision detected - could trigger events here
                handleCollision(entity1, entity2, col1, col2);
            }
        }
    }
}

fn checkCollision(
    pos1: *const components.Position,
    col1: *const components.Collider,
    pos2: *const components.Position,
    col2: *const components.Collider,
) bool {
    switch (col1.shape) {
        .rectangle => |rect1| {
            const r1 = ray.Rectangle{
                .x = pos1.x,
                .y = pos1.y,
                .width = rect1.width,
                .height = rect1.height,
            };
            
            switch (col2.shape) {
                .rectangle => |rect2| {
                    const r2 = ray.Rectangle{
                        .x = pos2.x,
                        .y = pos2.y,
                        .width = rect2.width,
                        .height = rect2.height,
                    };
                    return ray.CheckCollisionRecs(r1, r2);
                },
                .circle => |circ2| {
                    const center = ray.Vector2{ .x = pos2.x, .y = pos2.y };
                    return ray.CheckCollisionCircleRec(center, circ2.radius, r1);
                },
            }
        },
        .circle => |circ1| {
            const center1 = ray.Vector2{ .x = pos1.x, .y = pos1.y };
            
            switch (col2.shape) {
                .rectangle => |rect2| {
                    const r2 = ray.Rectangle{
                        .x = pos2.x,
                        .y = pos2.y,
                        .width = rect2.width,
                        .height = rect2.height,
                    };
                    return ray.CheckCollisionCircleRec(center1, circ1.radius, r2);
                },
                .circle => |circ2| {
                    const center2 = ray.Vector2{ .x = pos2.x, .y = pos2.y };
                    return ray.CheckCollisionCircles(center1, circ1.radius, center2, circ2.radius);
                },
            }
        },
    }
}

fn handleCollision(
    entity1: ecsroot.Entity,
    entity2: ecsroot.Entity,
    col1: *const components.Collider,
    col2: *const components.Collider,
) void {
    // basic collision response - could be expanded with events system
    
    // if either is a trigger, don't do physics response
    if (col1.is_trigger or col2.is_trigger) {
        // just log for now - could trigger pickup events, damage, etc.
        return;
    }
    
    // simple physics response - stop movement
    if (ecs.get(components.Velocity, entity1)) |_| {
        const vel1 = ecs.getUnchecked(components.Velocity, entity1);
        vel1.x *= 0.5; // simple bounce/friction
        vel1.y *= 0.5;
    }
    
    if (ecs.get(components.Velocity, entity2)) |_| {
        const vel2 = ecs.getUnchecked(components.Velocity, entity2);
        vel2.x *= 0.5;
        vel2.y *= 0.5;
    }
}

// helper functions for creating common collider shapes
pub fn createRectCollider(width: f32, height: f32, layer: u8) components.Collider {
    return .{
        .shape = .{ .rectangle = ray.Rectangle{ .x = 0, .y = 0, .width = width, .height = height } },
        .layer = layer,
    };
}

pub fn createCircleCollider(radius: f32, layer: u8) components.Collider {
    return .{
        .shape = .{ .circle = .{ .radius = radius } },
        .layer = layer,
    };
}

pub fn createTrigger(width: f32, height: f32, layer: u8) components.Collider {
    return .{
        .shape = .{ .rectangle = ray.Rectangle{ .x = 0, .y = 0, .width = width, .height = height } },
        .layer = layer,
        .is_trigger = true,
    };
}