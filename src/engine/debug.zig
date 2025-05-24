// engine/debug_layer.zig - Engine-level debug layer implementation
const std = @import("std");
const ecs = @import("ecs.zig");
const components = @import("components.zig");
const ray = @import("raylib.zig");
const gfx = @import("gfx.zig");

pub const DebugLayerContext = struct {
    debug_state: components.DebugState,
    allocator: std.mem.Allocator,

    // engine system timing breakdown (in microseconds)
    last_anim_time_us: u64 = 0,
    last_shader_time_us: u64 = 0,
    last_collision_time_us: u64 = 0,
    last_render_time_us: u64 = 0,
    last_total_systems_us: u64 = 0,

    // layer timing data
    layer_timings: std.ArrayList(LayerTiming),

    // frame counting for reduced update frequency
    frame_count: u32 = 0,

    // cached entity counts (updated at 30Hz)
    cached_pos_entities: u32 = 0,
    cached_sprite_entities: u32 = 0,
    cached_texture_entities: u32 = 0,
    cached_shader_entities: u32 = 0,
    cached_anim_entities: u32 = 0,

    // 30Hz update timing
    update_accumulator: f32 = 0.0,

    // entity count history for graph
    total_entity_history: [GRAPH_HISTORY_SIZE]u32 = [_]u32{0} ** GRAPH_HISTORY_SIZE,

    // performance graph data
    frame_time_history: [GRAPH_HISTORY_SIZE]f32 = [_]f32{0.0} ** GRAPH_HISTORY_SIZE,
    frame_time_index: usize = 0,
    max_frame_time: f32 = 0.0,
    avg_frame_time: f32 = 0.0,

    // cached formatted strings to avoid allocations
    cached_value_texts: [6][32]u8 = undefined,
    cached_fps_text: [32]u8 = undefined,
    cached_stats_text: [64]u8 = undefined,

    // component breakdown history for stacked graph
    anim_history: [GRAPH_HISTORY_SIZE]f32 = [_]f32{0.0} ** GRAPH_HISTORY_SIZE,
    shader_history: [GRAPH_HISTORY_SIZE]f32 = [_]f32{0.0} ** GRAPH_HISTORY_SIZE,
    collision_history: [GRAPH_HISTORY_SIZE]f32 = [_]f32{0.0} ** GRAPH_HISTORY_SIZE,
    render_history: [GRAPH_HISTORY_SIZE]f32 = [_]f32{0.0} ** GRAPH_HISTORY_SIZE,

    // fixed interval sampling
    sample_accumulator: f32 = 0.0,
    sample_interval_ms: f32 = 16.0, // sample every 16ms (60Hz)

    // accumulated values for current sample
    accumulated_frame_time: f32 = 0.0,
    accumulated_anim_time: f32 = 0.0,
    accumulated_shader_time: f32 = 0.0,
    accumulated_collision_time: f32 = 0.0,
    accumulated_render_time: f32 = 0.0,
    accumulated_samples: u32 = 0,
    accumulated_entity_count: u32 = 0,

    const GRAPH_HISTORY_SIZE = 600;
    const UPDATE_INTERVAL_MS: f32 = 160;

    const LayerTiming = struct {
        name: []const u8,
        time_us: u64,
    };

    pub fn init(allocator: std.mem.Allocator) !*DebugLayerContext {
        const self = try allocator.create(DebugLayerContext);
        self.* = .{
            .debug_state = components.DebugState{},
            .allocator = allocator,
            .layer_timings = std.ArrayList(LayerTiming).init(allocator),
        };
        return self;
    }

    pub fn deinit(ctx: *anyopaque) void {
        const self: *DebugLayerContext = @ptrCast(@alignCast(ctx));
        self.layer_timings.deinit();
        self.allocator.destroy(self);
    }

    pub fn update(ctx: *anyopaque, dt: f32) void {
        const self: *DebugLayerContext = @ptrCast(@alignCast(ctx));

        // early exit if debug is disabled - save all CPU cycles
        if (!self.debug_state.enabled) return;

        const world = ecs.getWorld();
        const frame_ms = dt * 1000.0;

        // update the 30Hz accumulator
        self.update_accumulator += frame_ms;

        // only count entities and update stats at 30Hz
        var current_entity_count: u32 = 0;
        var pos_count: u32 = self.cached_pos_entities;
        var sprite_count: u32 = self.cached_sprite_entities;
        var texture_count: u32 = self.cached_texture_entities;
        var shader_count: u32 = self.cached_shader_entities;
        var anim_count: u32 = self.cached_anim_entities;

        // perform expensive entity counting only at 30Hz
        if (self.update_accumulator >= UPDATE_INTERVAL_MS) {
            // count entities with position
            pos_count = 0;
            var pos_view = world.view(.{components.Position}, .{});
            var pos_it = pos_view.entityIterator();
            while (pos_it.next()) |_| pos_count += 1;

            // count other component types
            sprite_count = 0;
            var sprite_view = world.view(.{components.Sprite}, .{});
            var sprite_it = sprite_view.entityIterator();
            while (sprite_it.next()) |_| sprite_count += 1;

            texture_count = 0;
            var texture_view = world.view(.{components.Texture}, .{});
            var texture_it = texture_view.entityIterator();
            while (texture_it.next()) |_| texture_count += 1;

            shader_count = 0;
            var shader_view = world.view(.{components.Shader}, .{});
            var shader_it = shader_view.entityIterator();
            while (shader_it.next()) |_| shader_count += 1;

            anim_count = 0;
            var anim_view = world.view(.{components.Animation}, .{});
            var anim_it = anim_view.entityIterator();
            while (anim_it.next()) |_| anim_count += 1;

            // update cached counts
            self.cached_pos_entities = pos_count;
            self.cached_sprite_entities = sprite_count;
            self.cached_texture_entities = texture_count;
            self.cached_shader_entities = shader_count;
            self.cached_anim_entities = anim_count;

            // reset the update accumulator
            self.update_accumulator = 0.0;
        }

        current_entity_count = pos_count;
        const total_count = pos_count + sprite_count + texture_count + shader_count + anim_count;

        // accumulate values for averaging
        self.accumulated_frame_time += frame_ms;
        self.accumulated_anim_time += @as(f32, @floatFromInt(self.last_anim_time_us)) / 1000.0;
        self.accumulated_shader_time += @as(f32, @floatFromInt(self.last_shader_time_us)) / 1000.0;
        self.accumulated_collision_time += @as(f32, @floatFromInt(self.last_collision_time_us)) / 1000.0;
        self.accumulated_render_time += @as(f32, @floatFromInt(self.last_render_time_us)) / 1000.0;
        self.accumulated_entity_count += total_count;
        self.accumulated_samples += 1;

        // update accumulator
        self.sample_accumulator += frame_ms;

        // check if we should take a sample
        if (self.sample_accumulator >= self.sample_interval_ms) {
            // calculate averages for this sample period
            const avg_frame = if (self.accumulated_samples > 0) self.accumulated_frame_time / @as(f32, @floatFromInt(self.accumulated_samples)) else frame_ms;
            const avg_anim = if (self.accumulated_samples > 0) self.accumulated_anim_time / @as(f32, @floatFromInt(self.accumulated_samples)) else 0.0;
            const avg_shader = if (self.accumulated_samples > 0) self.accumulated_shader_time / @as(f32, @floatFromInt(self.accumulated_samples)) else 0.0;
            const avg_collision = if (self.accumulated_samples > 0) self.accumulated_collision_time / @as(f32, @floatFromInt(self.accumulated_samples)) else 0.0;
            const avg_render = if (self.accumulated_samples > 0) self.accumulated_render_time / @as(f32, @floatFromInt(self.accumulated_samples)) else 0.0;
            const avg_entities = if (self.accumulated_samples > 0) self.accumulated_entity_count / self.accumulated_samples else total_count;

            // store the averaged sample
            self.frame_time_history[self.frame_time_index] = avg_frame;
            self.anim_history[self.frame_time_index] = avg_anim;
            self.shader_history[self.frame_time_index] = avg_shader;
            self.collision_history[self.frame_time_index] = avg_collision;
            self.render_history[self.frame_time_index] = avg_render;
            self.total_entity_history[self.frame_time_index] = avg_entities;

            // calculate statistics only at 30Hz
            self.max_frame_time = 0.0;
            var sum: f32 = 0.0;
            for (self.frame_time_history) |time| {
                sum += time;
                if (time > self.max_frame_time) self.max_frame_time = time;
            }
            self.avg_frame_time = sum / @as(f32, DebugLayerContext.GRAPH_HISTORY_SIZE);

            self.frame_time_index = (self.frame_time_index + 1) % GRAPH_HISTORY_SIZE;

            // reset accumulators
            self.sample_accumulator = 0.0;
            self.accumulated_frame_time = 0.0;
            self.accumulated_anim_time = 0.0;
            self.accumulated_shader_time = 0.0;
            self.accumulated_collision_time = 0.0;
            self.accumulated_render_time = 0.0;
            self.accumulated_entity_count = 0;
            self.accumulated_samples = 0;
        }
    }

    pub fn render(ctx: *anyopaque, rc: gfx.RenderContext) void {
        const self: *DebugLayerContext = @ptrCast(@alignCast(ctx));
        if (!self.debug_state.enabled) return;

        renderDebugOverlay(self, rc);
    }

    pub fn processEvent(ctx: *anyopaque, event: *const anyopaque) void {
        _ = ctx;
        _ = event;
        // for now, we'll handle the toggle via direct input checking in gfx.frame
        // since we don't have a generic event type across all games
    }

    pub fn toggle(self: *DebugLayerContext) void {
        self.debug_state.enabled = !self.debug_state.enabled;
        std.debug.print("engine debug layer: {s}\n", .{if (self.debug_state.enabled) "enabled" else "disabled"});
    }

    pub fn cycleDebugMode(self: *DebugLayerContext) void {
        const mode_count = @typeInfo(components.DebugMode).@"enum".fields.len;
        const current_mode_int = @intFromEnum(self.debug_state.mode);
        const next_mode_int = (current_mode_int + 1) % mode_count;
        self.debug_state.mode = @enumFromInt(next_mode_int);

        // Update enabled state based on mode
        self.debug_state.enabled = (self.debug_state.mode != .off);

        // Update individual flags based on mode
        switch (self.debug_state.mode) {
            .off => {
                self.debug_state.show_graphs = false;
                self.debug_state.show_entity_bounds = false;
                self.debug_state.show_component_info = false;
            },
            .charts_only => {
                self.debug_state.show_graphs = true;
                self.debug_state.show_entity_bounds = false;
                self.debug_state.show_component_info = false;
            },
            .full_monty => {
                self.debug_state.show_graphs = true;
                self.debug_state.show_entity_bounds = true;
                self.debug_state.show_component_info = true;
            },
        }

        const mode_names = [_][]const u8{ "off", "charts only", "full monty" };
        std.debug.print("debug mode: {s}\n", .{mode_names[@intFromEnum(self.debug_state.mode)]});
    }

    pub fn isEnabled(self: *DebugLayerContext) bool {
        return self.debug_state.enabled;
    }

    // Update engine system timing statistics
    pub fn updateSystemTiming(self: *DebugLayerContext, anim_us: u64, shader_us: u64, collision_us: u64, render_us: u64, total_us: u64) void {
        self.last_anim_time_us = anim_us;
        self.last_shader_time_us = shader_us;
        self.last_collision_time_us = collision_us;
        self.last_render_time_us = render_us;
        self.last_total_systems_us = total_us;
    }

    // Update layer timing statistics
    pub fn updateLayerTimings(self: *DebugLayerContext, timings: []const LayerTiming) void {
        self.layer_timings.clearRetainingCapacity();
        for (timings) |timing| {
            self.layer_timings.append(timing) catch continue;
        }
    }
};

fn renderDebugOverlay(ctx: *DebugLayerContext, rc: gfx.RenderContext) void {
    // semi-transparent dark overlay
    ray.DrawRectangle(0, 0, rc.logical_width, rc.logical_height, .{ .r = 0, .g = 0, .b = 0, .a = ctx.debug_state.overlay_opacity });

    // render performance graph on the right side - this is the main performance cost
    if (ctx.debug_state.show_graphs) {
        renderPerformanceGraph(ctx, rc);
    }

    var y_offset: i32 = 10;
    const line_height: i32 = 10;
    const font_size: i32 = 8;

    // fps and performance info
    if (ctx.debug_state.show_fps) {
        const fps_text = std.fmt.allocPrintZ(std.heap.c_allocator, "FPS: {d}", .{ray.GetFPS()}) catch "FPS: ERROR";
        defer std.heap.c_allocator.free(fps_text);
        ray.DrawText(fps_text, 10, y_offset, font_size, ray.GREEN);
        y_offset += line_height;
    }

    // entity counts are now updated in the update function at fixed intervals

    // render entity bounds and info
    if (ctx.debug_state.show_entity_bounds or ctx.debug_state.show_component_info) {
        renderEntityDebugInfo(ctx, &y_offset, font_size, line_height);
    }
}

fn renderEntityDebugInfo(ctx: *DebugLayerContext, y_offset: *i32, font_size: i32, line_height: i32) void {
    _ = y_offset;
    _ = font_size;
    _ = line_height;
    const world = ecs.getWorld();

    // get entities with position and sprite components for bounds visualization
    var view = world.view(.{ components.Position, components.Sprite }, .{});
    var entity_count: u32 = 0;
    var animation_count: u32 = 0;

    var it = view.entityIterator();
    while (it.next()) |entity| {
        const pos = view.get(components.Position, entity);
        const sprite = view.get(components.Sprite, entity);

        // draw entity bounds as a rectangle (adjusted for center origin)
        const bounds_color = ray.Color{ .r = 255, .g = 0, .b = 255, .a = 100 }; // magenta with transparency
        const half_size = sprite.size / 2.0;
        ray.DrawRectangleLines(@intFromFloat(pos.x - half_size), @intFromFloat(pos.y - half_size), @intFromFloat(sprite.size), @intFromFloat(sprite.size), bounds_color);

        // draw component letters above the entity
        var letter_x: i32 = @intFromFloat(pos.x);
        const letter_y: i32 = @intFromFloat(pos.y - 8);
        const letter_size = 6;
        const letter_spacing = 7;

        // check for common components and draw their letters
        if (world.has(components.Position, entity)) {
            ray.DrawText("p", letter_x, letter_y, letter_size, ray.WHITE);
            letter_x += letter_spacing;
        }
        if (world.has(components.Sprite, entity)) {
            ray.DrawText("s", letter_x, letter_y, letter_size, ray.GREEN);
            letter_x += letter_spacing;
        }
        if (world.has(components.Texture, entity)) {
            ray.DrawText("t", letter_x, letter_y, letter_size, ray.BLUE);
            letter_x += letter_spacing;
        }
        if (world.has(components.Shader, entity)) {
            ray.DrawText("m", letter_x, letter_y, letter_size, ray.YELLOW);
            letter_x += letter_spacing;
        }
        if (world.has(components.Animation, entity)) {
            ray.DrawText("a", letter_x, letter_y, letter_size, ray.RED);
            letter_x += letter_spacing;

            // Draw animation path in full monty mode (limited to first 500)
            if (ctx.debug_state.mode == .full_monty and animation_count < 500) {
                const anim = world.get(components.Animation, entity);

                // Check if this animation affects position
                if (anim.animate_position and anim.target_pos != null) {
                    animation_count += 1;
                    // Draw from current position to target position
                    const start_x = pos.x;
                    const start_y = pos.y;
                    const end_x = anim.target_pos.?[0];
                    const end_y = anim.target_pos.?[1];

                    // Only draw if there's actual movement
                    const dx = end_x - start_x;
                    const dy = end_y - start_y;
                    const distance = @sqrt(dx * dx + dy * dy);

                    if (distance > 1.0) {
                        // Draw dashed line from start to end
                        const segments = 10;
                        const seg_length = distance / @as(f32, @floatFromInt(segments * 2));
                        const angle = std.math.atan2(dy, dx);

                        // Draw dashed line
                        var i: usize = 0;
                        while (i < segments) : (i += 1) {
                            const seg_start = @as(f32, @floatFromInt(i * 2)) * seg_length;
                            const seg_end = seg_start + seg_length;

                            const sx = start_x + seg_start * @cos(angle);
                            const sy = start_y + seg_start * @sin(angle);
                            const ex = start_x + seg_end * @cos(angle);
                            const ey = start_y + seg_end * @sin(angle);

                            ray.DrawLineEx(ray.Vector2{ .x = sx, .y = sy }, ray.Vector2{ .x = ex, .y = ey }, 1.5, ray.Color{ .r = 255, .g = 100, .b = 100, .a = 150 } // light red
                            );
                        }

                        // Draw arrowhead at end position
                        const arrow_size = 8.0;
                        const arrow_angle = 0.5; // ~30 degrees

                        // Left wing of arrow
                        ray.DrawLineEx(ray.Vector2{ .x = end_x, .y = end_y }, ray.Vector2{ .x = end_x - arrow_size * @cos(angle - arrow_angle), .y = end_y - arrow_size * @sin(angle - arrow_angle) }, 2.0, ray.Color{ .r = 255, .g = 100, .b = 100, .a = 200 });

                        // Right wing of arrow
                        ray.DrawLineEx(ray.Vector2{ .x = end_x, .y = end_y }, ray.Vector2{ .x = end_x - arrow_size * @cos(angle + arrow_angle), .y = end_y - arrow_size * @sin(angle + arrow_angle) }, 2.0, ray.Color{ .r = 255, .g = 100, .b = 100, .a = 200 });
                    }
                }
            }
        }
        if (world.has(components.Velocity, entity)) {
            ray.DrawText("v", letter_x, letter_y, letter_size, ray.PURPLE);
            letter_x += letter_spacing;

            // Draw velocity vector in full monty mode
            if (ctx.debug_state.mode == .full_monty) {
                const vel = world.get(components.Velocity, entity);

                // Only draw if velocity is significant
                const vel_magnitude = @sqrt(vel.x * vel.x + vel.y * vel.y);
                if (vel_magnitude > 1.0) {
                    // Scale the velocity for visualization - longer vectors that scale with speed
                    // Base scale of 0.2 (2x previous) with additional scaling based on velocity magnitude
                    const base_scale = 0.2;
                    const magnitude_scale = @min(vel_magnitude / 500.0, 2.0); // caps at 2x for very fast objects
                    const scale = base_scale * (1.0 + magnitude_scale);
                    const end_x = pos.x + vel.x * scale;
                    const end_y = pos.y + vel.y * scale;

                    // Draw velocity vector as a line
                    ray.DrawLineEx(ray.Vector2{ .x = pos.x, .y = pos.y }, ray.Vector2{ .x = end_x, .y = end_y }, 2.0, // line thickness
                        ray.Color{ .r = 255, .g = 255, .b = 0, .a = 200 } // yellow
                    );

                    // Draw arrowhead pointing in direction of velocity
                    const arrow_size = 8.0;
                    const angle = std.math.atan2(vel.y, vel.x);
                    const arrow_angle = 0.5; // ~30 degrees

                    // Left wing of arrow
                    ray.DrawLineEx(ray.Vector2{ .x = end_x, .y = end_y }, ray.Vector2{ .x = end_x - arrow_size * @cos(angle - arrow_angle), .y = end_y - arrow_size * @sin(angle - arrow_angle) }, 2.0, ray.Color{ .r = 255, .g = 255, .b = 0, .a = 200 });

                    // Right wing of arrow
                    ray.DrawLineEx(ray.Vector2{ .x = end_x, .y = end_y }, ray.Vector2{ .x = end_x - arrow_size * @cos(angle + arrow_angle), .y = end_y - arrow_size * @sin(angle + arrow_angle) }, 2.0, ray.Color{ .r = 255, .g = 255, .b = 0, .a = 200 });
                }
            }
        }

        if (world.has(components.Collider, entity)) {
            ray.DrawText("c", letter_x, letter_y, letter_size, ray.PURPLE);
            letter_x += letter_spacing;

            // Draw collision bounds with animation
            const collider = world.get(components.Collider, entity);

            // determine color based on collision state
            var collision_color = ray.Color{ .r = 0, .g = 255, .b = 0, .a = 80 }; // default green
            var line_thickness: f32 = 1.0;

            if (world.has(components.CollisionState, entity)) {
                const collision_state = world.get(components.CollisionState, entity);
                if (collision_state.in_collision) {
                    // flash red and make thicker when in collision
                    const flash_progress = collision_state.collision_timer / collision_state.flash_duration;
                    const flash_intensity = @as(u8, @intFromFloat((1.0 - flash_progress) * 255.0));
                    collision_color = ray.Color{ .r = 255, .g = flash_intensity, .b = flash_intensity, .a = 150 };
                    line_thickness = 2.0 + (1.0 - flash_progress) * 2.0; // thicker lines during collision
                }
            }

            switch (collider.shape) {
                .rectangle => |rect| {
                    // Adjust for sprite center origin
                    const half_sprite = sprite.size / 2.0;
                    const collision_rect = ray.Rectangle{
                        .x = pos.x + rect.x - half_sprite,
                        .y = pos.y + rect.y - half_sprite,
                        .width = rect.width,
                        .height = rect.height,
                    };
                    ray.DrawRectangleLinesEx(collision_rect, line_thickness, collision_color);
                },
                .circle => |circ| {
                    // Adjust for sprite center origin
                    const half_sprite = sprite.size / 2.0;
                    const center = ray.Vector2{
                        .x = pos.x - half_sprite,
                        .y = pos.y - half_sprite,
                    };
                    ray.DrawCircleLinesV(center, circ.radius, collision_color);
                },
            }
        }

        entity_count += 1;

        // limit to first 5000 entities to avoid performance issues
        if (entity_count >= 5000) break;
    }
}

// Calculate approximate texture memory usage
fn calculateTextureMemory() u32 {
    // Get window texture memory (main render target)
    const window_tex = &gfx.window.texture;
    const window_memory = @as(u32, @intCast(window_tex.texture.width * window_tex.texture.height * 4)); // RGBA = 4 bytes per pixel

    // Get texture atlas memory (this is a rough estimate)
    // Each atlas page is typically the size of the window texture
    const atlas_pages = 2; // estimate - could query textures module for exact count
    const atlas_memory = window_memory * atlas_pages;

    // Convert to KB
    return (window_memory + atlas_memory) / 1024;
}

// Render the performance graph
fn renderPerformanceGraph(ctx: *DebugLayerContext, rc: gfx.RenderContext) void {
    const base_x = rc.logical_width - 160;
    const base_y = 10;
    const graph_width = 150;
    const graph_height = 50;
    const graph_spacing = 70;
    const padding = 3;

    // define the graphs to render
    const GraphType = enum { timing, entity };
    const GraphInfo = struct {
        title: []const u8,
        data: []const f32,
        color: ray.Color,
        current_value: f32,
        graph_type: GraphType,
    };

    // convert entity count to f32 for display
    var entity_data: [DebugLayerContext.GRAPH_HISTORY_SIZE]f32 = undefined;

    for (0..DebugLayerContext.GRAPH_HISTORY_SIZE) |i| {
        entity_data[i] = @floatFromInt(ctx.total_entity_history[i]);
    }

    const graphs = [_]GraphInfo{
        // Performance graphs
        .{
            .title = "Frame Time",
            .data = &ctx.frame_time_history,
            .color = ray.WHITE,
            .current_value = ctx.frame_time_history[(ctx.frame_time_index + DebugLayerContext.GRAPH_HISTORY_SIZE - 1) % DebugLayerContext.GRAPH_HISTORY_SIZE],
            .graph_type = .timing,
        },
        .{
            .title = "Animation",
            .data = &ctx.anim_history,
            .color = .{ .r = 255, .g = 100, .b = 100, .a = 255 },
            .current_value = ctx.anim_history[(ctx.frame_time_index + DebugLayerContext.GRAPH_HISTORY_SIZE - 1) % DebugLayerContext.GRAPH_HISTORY_SIZE],
            .graph_type = .timing,
        },
        .{
            .title = "Shader",
            .data = &ctx.shader_history,
            .color = .{ .r = 255, .g = 255, .b = 100, .a = 255 },
            .current_value = ctx.shader_history[(ctx.frame_time_index + DebugLayerContext.GRAPH_HISTORY_SIZE - 1) % DebugLayerContext.GRAPH_HISTORY_SIZE],
            .graph_type = .timing,
        },
        .{
            .title = "Collision",
            .data = &ctx.collision_history,
            .color = .{ .r = 200, .g = 100, .b = 255, .a = 255 },
            .current_value = ctx.collision_history[(ctx.frame_time_index + DebugLayerContext.GRAPH_HISTORY_SIZE - 1) % DebugLayerContext.GRAPH_HISTORY_SIZE],
            .graph_type = .timing,
        },
        .{
            .title = "Render",
            .data = &ctx.render_history,
            .color = .{ .r = 100, .g = 150, .b = 255, .a = 255 },
            .current_value = ctx.render_history[(ctx.frame_time_index + DebugLayerContext.GRAPH_HISTORY_SIZE - 1) % DebugLayerContext.GRAPH_HISTORY_SIZE],
            .graph_type = .timing,
        },
        // Entity count graph
        .{
            .title = "Total Entities",
            .data = &entity_data,
            .color = .{ .r = 150, .g = 255, .b = 150, .a = 255 },
            .current_value = @floatFromInt(ctx.cached_pos_entities + ctx.cached_sprite_entities + ctx.cached_texture_entities + ctx.cached_shader_entities + ctx.cached_anim_entities),
            .graph_type = .entity,
        },
    };

    // render each graph
    for (graphs, 0..) |graph_info, idx| {
        const graph_y = base_y + @as(i32, @intCast(idx)) * graph_spacing;

        // draw graph background
        ray.DrawRectangle(base_x - padding, graph_y - padding, graph_width + padding * 2, graph_height + padding * 2, .{ .r = 20, .g = 20, .b = 20, .a = 200 });
        ray.DrawRectangleLines(base_x - padding, graph_y - padding, graph_width + padding * 2, graph_height + padding * 2, .{ .r = 60, .g = 60, .b = 60, .a = 255 });

        // draw title and current value
        ray.DrawText(graph_info.title.ptr, base_x - padding, graph_y - padding - 10, 5, graph_info.color);
        const value_text = if (graph_info.graph_type == .timing)
            std.fmt.allocPrintZ(std.heap.c_allocator, "{d:.2}ms", .{graph_info.current_value}) catch "ERROR"
        else
            std.fmt.allocPrintZ(std.heap.c_allocator, "{d:.0}", .{graph_info.current_value}) catch "ERROR";
        defer std.heap.c_allocator.free(value_text);
        ray.DrawText(value_text, base_x + graph_width - 40, graph_y - padding - 10, 5, ray.LIGHTGRAY);

        // find max value for this graph to auto-scale
        var max_value: f32 = 0.1; // minimum scale
        for (graph_info.data) |value| {
            if (value > max_value) max_value = value;
        }
        // round up to nice numbers
        if (max_value > 10) {
            max_value = @ceil(max_value / 10) * 10;
        } else if (max_value > 1) {
            max_value = @ceil(max_value);
        } else {
            max_value = @ceil(max_value * 10) / 10;
        }

        // draw scale indicator
        const scale_text = std.fmt.allocPrintZ(std.heap.c_allocator, "{d:.1}", .{max_value}) catch "ERROR";
        defer std.heap.c_allocator.free(scale_text);
        ray.DrawText(scale_text, base_x - padding - 25, graph_y - padding, 6, .{ .r = 100, .g = 100, .b = 100, .a = 255 });

        // draw the graph line - reduce samples for performance
        const max_samples = 75; // draw every 4th sample for performance
        const samples_to_draw = @min(max_samples, graph_width);
        const x_step = @as(f32, @floatFromInt(graph_width)) / @as(f32, @floatFromInt(samples_to_draw));
        const sample_step = DebugLayerContext.GRAPH_HISTORY_SIZE / samples_to_draw;

        for (1..samples_to_draw) |i| {
            const history_idx = (ctx.frame_time_index + DebugLayerContext.GRAPH_HISTORY_SIZE - (samples_to_draw - i) * sample_step) % DebugLayerContext.GRAPH_HISTORY_SIZE;
            const prev_idx = (ctx.frame_time_index + DebugLayerContext.GRAPH_HISTORY_SIZE - (samples_to_draw - i + 1) * sample_step) % DebugLayerContext.GRAPH_HISTORY_SIZE;

            const x = base_x + @as(i32, @intFromFloat(@as(f32, @floatFromInt(i)) * x_step));
            const prev_x = base_x + @as(i32, @intFromFloat(@as(f32, @floatFromInt(i - 1)) * x_step));

            const height = (graph_info.data[history_idx] / max_value) * @as(f32, @floatFromInt(graph_height));
            const prev_height = (graph_info.data[prev_idx] / max_value) * @as(f32, @floatFromInt(graph_height));

            const y = graph_y + graph_height - @as(i32, @intFromFloat(height));
            const prev_y = graph_y + graph_height - @as(i32, @intFromFloat(prev_height));

            // use dimmer color for the first graph if performance is bad
            var line_color = graph_info.color;
            if (idx == 0) { // frame time graph
                if (graph_info.data[history_idx] > 33.333) {
                    line_color = .{ .r = 255, .g = 0, .b = 0, .a = 255 }; // red
                } else if (graph_info.data[history_idx] > 16.667) {
                    line_color = .{ .r = 255, .g = 255, .b = 0, .a = 255 }; // yellow
                }
            }

            ray.DrawLine(prev_x, prev_y, x, y, line_color);
        }

        // draw zero line
        ray.DrawLine(base_x, graph_y + graph_height, base_x + graph_width, graph_y + graph_height, .{ .r = 80, .g = 80, .b = 80, .a = 100 });
    }

    // draw overall stats at the bottom
    const stats_y = base_y + @as(i32, @intCast(graphs.len)) * graph_spacing;
    const stats_text = std.fmt.allocPrintZ(std.heap.c_allocator, "Avg: {d:.1}ms Max: {d:.1}ms", .{ ctx.avg_frame_time, ctx.max_frame_time }) catch "Stats: ERROR";
    defer std.heap.c_allocator.free(stats_text);
    ray.DrawText(stats_text, base_x, stats_y, 8, ray.LIGHTGRAY);
}

// Wrapper function to properly cast the init return type
fn debugLayerInit(allocator: std.mem.Allocator) anyerror!*anyopaque {
    const ctx = try DebugLayerContext.init(allocator);
    return ctx;
}

// Factory function to create the debug layer
pub fn createDebugLayer(_: std.mem.Allocator) !gfx.Layer {
    return gfx.Layer{
        .name = "engine_debug",
        .order = 1000, // render on top of everything
        .enabled = true,
        .init = debugLayerInit,
        .deinit = DebugLayerContext.deinit,
        .update = DebugLayerContext.update,
        .render = DebugLayerContext.render,
        .processEvent = DebugLayerContext.processEvent,
    };
}
