const std = @import("std");
const ray = @import("../raylib.zig");
const ecs = @import("../ecs.zig");
const ecsroot = @import("ecs");
const components = @import("../components.zig");

// simple collision system using raylib's built-in collision functions
pub fn update() void {
    // move all entities with velocity
    moveEntities();

    // update collision state timers
    updateCollisionStates();

    // check collisions between entities
    checkCollisions();
}

fn moveEntities() void {
    var moving = ecs.getWorld().view(.{ components.Position, components.Velocity }, .{});
    var iter = moving.entityIterator();

    const dt = ray.GetFrameTime();

    while (iter.next()) |entity| {
        const pos = moving.get(components.Position, entity);
        const vel = moving.get(components.Velocity, entity);

        // apply gravity only if entity has Gravity component
        if (ecs.get(components.Gravity, entity)) |grav| {
            vel.x += grav.x * dt;
            vel.y += grav.y * dt;
        }

        // apply velocity
        pos.x += vel.x * dt;
        pos.y += vel.y * dt;
    }
}

fn checkCollisions() void {
    var colliders = ecs.getWorld().view(.{ components.Position, components.Collider }, .{});
    var iter1 = colliders.entityIterator();

    var collision_count: u32 = 0;
    var entity_count: u32 = 0;

    // simple O(n²) collision detection - good enough for vampire survivors
    while (iter1.next()) |entity1| {
        entity_count += 1;
        const pos1 = colliders.get(components.Position, entity1);
        const col1 = colliders.get(components.Collider, entity1);

        var iter2 = colliders.entityIterator();
        while (iter2.next()) |entity2| {
            if (entity1 == entity2) continue;

            const pos2 = colliders.get(components.Position, entity2);
            const col2 = colliders.get(components.Collider, entity2);

            // all entities collide with each other regardless of layer

            if (checkCollision(pos1, col1, pos2, col2)) {
                collision_count += 1;
                // std.debug.print("collision detected: {} <-> {}\n", .{ entity1, entity2 });
                // mark entities as in collision
                markCollision(entity1);
                markCollision(entity2);
                // collision detected - could trigger events here
                handleCollision(entity1, entity2, col1, col2);
            }
        }
    }
}

// triangle collision detection using sameside algorithm
fn sameSide(p1: [2]f32, p2: [2]f32, a: [2]f32, b: [2]f32) bool {
    // calculate cross products for 2D (z component only)
    const ab_x = b[0] - a[0];
    const ab_y = b[1] - a[1];
    const ap1_x = p1[0] - a[0];
    const ap1_y = p1[1] - a[1];
    const ap2_x = p2[0] - a[0];
    const ap2_y = p2[1] - a[1];
    
    // 2D cross product (z component)
    const cp1 = ab_x * ap1_y - ab_y * ap1_x;
    const cp2 = ab_x * ap2_y - ab_y * ap2_x;
    
    return cp1 * cp2 >= 0;
}

fn pointInTriangle(point: [2]f32, p1: [2]f32, p2: [2]f32, p3: [2]f32) bool {
    return sameSide(point, p1, p2, p3) and 
           sameSide(point, p2, p3, p1) and 
           sameSide(point, p3, p1, p2);
}

fn checkTriangleTriangleCollision(pos1: *const components.Position, tri1: anytype, pos2: *const components.Position, tri2: anytype) bool {
    // transform triangle points to world space
    const t1_p1 = [2]f32{ pos1.x + tri1.p1[0], pos1.y + tri1.p1[1] };
    const t1_p2 = [2]f32{ pos1.x + tri1.p2[0], pos1.y + tri1.p2[1] };
    const t1_p3 = [2]f32{ pos1.x + tri1.p3[0], pos1.y + tri1.p3[1] };
    
    const t2_p1 = [2]f32{ pos2.x + tri2.p1[0], pos2.y + tri2.p1[1] };
    const t2_p2 = [2]f32{ pos2.x + tri2.p2[0], pos2.y + tri2.p2[1] };
    const t2_p3 = [2]f32{ pos2.x + tri2.p3[0], pos2.y + tri2.p3[1] };

    // check if any vertex of triangle 2 is inside triangle 1
    if (pointInTriangle(t2_p1, t1_p1, t1_p2, t1_p3) or
        pointInTriangle(t2_p2, t1_p1, t1_p2, t1_p3) or
        pointInTriangle(t2_p3, t1_p1, t1_p2, t1_p3)) {
        return true;
    }

    // check if any vertex of triangle 1 is inside triangle 2
    if (pointInTriangle(t1_p1, t2_p1, t2_p2, t2_p3) or
        pointInTriangle(t1_p2, t2_p1, t2_p2, t2_p3) or
        pointInTriangle(t1_p3, t2_p1, t2_p2, t2_p3)) {
        return true;
    }

    return false;
}

fn checkTriangleCircleCollision(tri_pos: *const components.Position, triangle: anytype, circle_pos: *const components.Position, radius: f32) bool {
    const t_p1 = [2]f32{ tri_pos.x + triangle.p1[0], tri_pos.y + triangle.p1[1] };
    const t_p2 = [2]f32{ tri_pos.x + triangle.p2[0], tri_pos.y + triangle.p2[1] };
    const t_p3 = [2]f32{ tri_pos.x + triangle.p3[0], tri_pos.y + triangle.p3[1] };
    const circle_center = [2]f32{ circle_pos.x, circle_pos.y };

    // check if circle center is inside triangle
    if (pointInTriangle(circle_center, t_p1, t_p2, t_p3)) {
        return true;
    }

    // check distance from circle center to each triangle edge
    const d1 = distanceToLineSegment(circle_center[0], circle_center[1], t_p1[0], t_p1[1], t_p2[0], t_p2[1]);
    const d2 = distanceToLineSegment(circle_center[0], circle_center[1], t_p2[0], t_p2[1], t_p3[0], t_p3[1]);
    const d3 = distanceToLineSegment(circle_center[0], circle_center[1], t_p3[0], t_p3[1], t_p1[0], t_p1[1]);

    return (d1 <= radius) or (d2 <= radius) or (d3 <= radius);
}

fn checkTriangleRectCollision(tri_pos: *const components.Position, triangle: anytype, rect: *const ray.Rectangle) bool {
    const t_p1 = [2]f32{ tri_pos.x + triangle.p1[0], tri_pos.y + triangle.p1[1] };
    const t_p2 = [2]f32{ tri_pos.x + triangle.p2[0], tri_pos.y + triangle.p2[1] };
    const t_p3 = [2]f32{ tri_pos.x + triangle.p3[0], tri_pos.y + triangle.p3[1] };

    // check if any triangle vertex is inside rectangle
    if (ray.CheckCollisionPointRec(.{ .x = t_p1[0], .y = t_p1[1] }, rect.*) or
        ray.CheckCollisionPointRec(.{ .x = t_p2[0], .y = t_p2[1] }, rect.*) or
        ray.CheckCollisionPointRec(.{ .x = t_p3[0], .y = t_p3[1] }, rect.*)) {
        return true;
    }

    // check if any rectangle corner is inside triangle
    const corners = [4][2]f32{
        [2]f32{ rect.x, rect.y },
        [2]f32{ rect.x + rect.width, rect.y },
        [2]f32{ rect.x, rect.y + rect.height },
        [2]f32{ rect.x + rect.width, rect.y + rect.height },
    };

    for (corners) |corner| {
        if (pointInTriangle(corner, t_p1, t_p2, t_p3)) {
            return true;
        }
    }

    return false;
}

fn distanceToLineSegment(px: f32, py: f32, ax: f32, ay: f32, bx: f32, by: f32) f32 {
    const dx = bx - ax;
    const dy = by - ay;
    const length_sq = dx * dx + dy * dy;

    if (length_sq < 0.0001) {
        const dpx = px - ax;
        const dpy = py - ay;
        return @sqrt(dpx * dpx + dpy * dpy);
    }

    const t = std.math.clamp(((px - ax) * dx + (py - ay) * dy) / length_sq, 0.0, 1.0);
    const closest_x = ax + t * dx;
    const closest_y = ay + t * dy;
    const dcx = px - closest_x;
    const dcy = py - closest_y;
    return @sqrt(dcx * dcx + dcy * dcy);
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
                .triangle => |tri2| {
                    return checkTriangleRectCollision(pos2, &tri2, &r1);
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
                .triangle => |tri2| {
                    return checkTriangleCircleCollision(pos2, &tri2, pos1, circ1.radius);
                },
            }
        },
        .triangle => |tri1| {
            switch (col2.shape) {
                .rectangle => |rect2| {
                    const r2 = ray.Rectangle{
                        .x = pos2.x,
                        .y = pos2.y,
                        .width = rect2.width,
                        .height = rect2.height,
                    };
                    return checkTriangleRectCollision(pos1, &tri1, &r2);
                },
                .circle => |circ2| {
                    return checkTriangleCircleCollision(pos1, &tri1, pos2, circ2.radius);
                },
                .triangle => |tri2| {
                    return checkTriangleTriangleCollision(pos1, &tri1, pos2, &tri2);
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

    // simple physics response - bounce off
    if (ecs.get(components.Velocity, entity1)) |_| {
        const vel1 = ecs.getUnchecked(components.Velocity, entity1);
        const pos1 = ecs.getUnchecked(components.Position, entity1);
        const pos2 = ecs.getUnchecked(components.Position, entity2);

        // calculate collision normal (simplified)
        const dx = pos1.x - pos2.x;
        const dy = pos1.y - pos2.y;
        const dist = @sqrt(dx * dx + dy * dy);

        if (dist > 0.01) { // avoid division by zero
            // normalize
            const nx = dx / dist;
            const ny = dy / dist;

            // calculate overlap amount (simplified - assumes circles)
            const min_distance = 50.0; // approximate size
            const overlap = min_distance - dist;

            if (overlap > 0) {
                // separate objects to prevent overlap
                const separation = overlap * 0.5;
                pos1.x += nx * separation;
                pos1.y += ny * separation;
            }

            // apply bounce force
            const bounce_force = 100.0;
            vel1.x += nx * bounce_force;
            vel1.y += ny * bounce_force;

            // apply some damping
            vel1.x *= 0.95;
            vel1.y *= 0.95;
        }
    }

    if (ecs.get(components.Velocity, entity2)) |_| {
        const vel2 = ecs.getUnchecked(components.Velocity, entity2);
        const pos1 = ecs.getUnchecked(components.Position, entity1);
        const pos2 = ecs.getUnchecked(components.Position, entity2);

        // calculate collision normal (opposite direction)
        const dx = pos2.x - pos1.x;
        const dy = pos2.y - pos1.y;
        const dist = @sqrt(dx * dx + dy * dy);

        if (dist > 0.01) { // avoid division by zero
            // normalize and apply bounce
            const nx = dx / dist;
            const ny = dy / dist;
            const bounce_force = 200.0;

            vel2.x += nx * bounce_force;
            vel2.y += ny * bounce_force;

            // apply some damping
            vel2.x *= 0.9;
            vel2.y *= 0.9;
        }
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

pub fn createTriangleCollider(p1: [2]f32, p2: [2]f32, p3: [2]f32, layer: u8) components.Collider {
    return .{
        .shape = .{ .triangle = .{ .p1 = p1, .p2 = p2, .p3 = p3 } },
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

// update collision state timers
fn updateCollisionStates() void {
    var collision_states = ecs.getWorld().view(.{components.CollisionState}, .{});
    var iter = collision_states.entityIterator();

    const dt = ray.GetFrameTime();

    while (iter.next()) |entity| {
        const state = collision_states.get(entity);

        // update timer
        state.collision_timer += dt;

        // reset collision flag if enough time has passed
        if (state.collision_timer > state.flash_duration) {
            state.in_collision = false;
        }
    }
}

// mark an entity as being in collision
fn markCollision(entity: ecsroot.Entity) void {
    if (ecs.get(components.CollisionState, entity)) |state| {
        state.in_collision = true;
        state.collision_timer = 0.0;
    } else {
        // add collision state component if it doesn't exist
        ecs.add(entity, components.CollisionState{
            .in_collision = true,
            .collision_timer = 0.0,
        });
    }
}
