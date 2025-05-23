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

    // cached entity counts (updated every 30 frames)
    cached_pos_entities: u32 = 0,
    cached_sprite_entities: u32 = 0,
    cached_texture_entities: u32 = 0,
    cached_shader_entities: u32 = 0,
    cached_anim_entities: u32 = 0,

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
        _ = ctx;
        _ = dt;
        // no per-frame updates needed for debug layer
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
    const world = ecs.getWorld();
    // increment frame counter
    ctx.frame_count += 1;

    // semi-transparent dark overlay
    ray.DrawRectangle(0, 0, rc.logical_width, rc.logical_height, .{ .r = 0, .g = 0, .b = 0, .a = ctx.debug_state.overlay_opacity });

    var y_offset: i32 = 10;
    const line_height: i32 = 10;
    const font_size: i32 = 8;

    // fps and performance info
    if (ctx.debug_state.show_fps) {
        const fps_text = std.fmt.allocPrintZ(std.heap.c_allocator, "FPS: {d}", .{ray.GetFPS()}) catch "FPS: ERROR";
        defer std.heap.c_allocator.free(fps_text);
        ray.DrawText(fps_text, 10, y_offset, font_size, ray.GREEN);
        y_offset += line_height;

        const frame_time = ray.GetFrameTime() * 1000; // convert to ms
        const frame_text = std.fmt.allocPrintZ(std.heap.c_allocator, "Total Frame: {d:.2}ms", .{frame_time}) catch "Frame: ERROR";
        defer std.heap.c_allocator.free(frame_text);
        ray.DrawText(frame_text, 10, y_offset, font_size, ray.GREEN);
        y_offset += line_height;

        // engine system timing breakdown if we have data
        if (ctx.last_total_systems_us > 0) {
            const anim_ms = @as(f32, @floatFromInt(ctx.last_anim_time_us)) / 1000.0;
            const shader_ms = @as(f32, @floatFromInt(ctx.last_shader_time_us)) / 1000.0;
            const collision_ms = @as(f32, @floatFromInt(ctx.last_collision_time_us)) / 1000.0;
            const render_ms = @as(f32, @floatFromInt(ctx.last_render_time_us)) / 1000.0;
            const total_systems_ms = @as(f32, @floatFromInt(ctx.last_total_systems_us)) / 1000.0;
            const other_ms = frame_time - total_systems_ms;

            // display system timings - one per line
            ray.DrawText("Engine Systems:", 10, y_offset, font_size, ray.YELLOW);
            y_offset += line_height;

            const anim_text = std.fmt.allocPrintZ(std.heap.c_allocator, "Animation: {d:.2}ms", .{anim_ms}) catch "Animation: ERROR";
            defer std.heap.c_allocator.free(anim_text);
            ray.DrawText(anim_text, 20, y_offset, font_size, ray.WHITE);
            y_offset += line_height;

            const shader_text = std.fmt.allocPrintZ(std.heap.c_allocator, "Shader: {d:.2}ms", .{shader_ms}) catch "Shader: ERROR";
            defer std.heap.c_allocator.free(shader_text);
            ray.DrawText(shader_text, 20, y_offset, font_size, ray.WHITE);
            y_offset += line_height;

            const collision_text = std.fmt.allocPrintZ(std.heap.c_allocator, "Collision: {d:.2}ms", .{collision_ms}) catch "Collision: ERROR";
            defer std.heap.c_allocator.free(collision_text);
            ray.DrawText(collision_text, 20, y_offset, font_size, ray.WHITE);
            y_offset += line_height;

            const render_text = std.fmt.allocPrintZ(std.heap.c_allocator, "Render: {d:.2}ms", .{render_ms}) catch "Render: ERROR";
            defer std.heap.c_allocator.free(render_text);
            ray.DrawText(render_text, 20, y_offset, font_size, ray.WHITE);
            y_offset += line_height;

            const other_text = std.fmt.allocPrintZ(std.heap.c_allocator, "Other: {d:.2}ms (game logic, input, etc)", .{other_ms}) catch "Other: ERROR";
            defer std.heap.c_allocator.free(other_text);
            ray.DrawText(other_text, 10, y_offset, font_size, ray.LIGHTGRAY);
            y_offset += line_height;
        }
    }

    // system-level statistics (updated every 30 frames)
    if (ctx.debug_state.show_entity_count) {
        // update entity counts every 30 frames
        if (ctx.frame_count % 30 == 0) {
            // total entities with position
            ctx.cached_pos_entities = 0;
            var pos_view = world.view(.{components.Position}, .{});
            var pos_it = pos_view.entityIterator();
            while (pos_it.next()) |_| ctx.cached_pos_entities += 1;

            // entities by component type
            ctx.cached_sprite_entities = 0;
            var sprite_view = world.view(.{components.Sprite}, .{});
            var sprite_it = sprite_view.entityIterator();
            while (sprite_it.next()) |_| ctx.cached_sprite_entities += 1;

            ctx.cached_texture_entities = 0;
            var texture_view = world.view(.{components.Texture}, .{});
            var texture_it = texture_view.entityIterator();
            while (texture_it.next()) |_| ctx.cached_texture_entities += 1;

            ctx.cached_shader_entities = 0;
            var shader_view = world.view(.{components.Shader}, .{});
            var shader_it = shader_view.entityIterator();
            while (shader_it.next()) |_| ctx.cached_shader_entities += 1;

            ctx.cached_anim_entities = 0;
            var anim_view = world.view(.{components.Animation}, .{});
            var anim_it = anim_view.entityIterator();
            while (anim_it.next()) |_| ctx.cached_anim_entities += 1;
        }

        // memory usage approximation using cached values
        const approx_memory_kb = (ctx.cached_pos_entities * @sizeOf(components.Position) +
            ctx.cached_sprite_entities * @sizeOf(components.Sprite) +
            ctx.cached_texture_entities * @sizeOf(components.Texture) +
            ctx.cached_shader_entities * @sizeOf(components.Shader) +
            ctx.cached_anim_entities * @sizeOf(components.Animation)) / 1024;

        // display entity counts - one per line
        ray.DrawText("Entity Components:", 10, y_offset, font_size, ray.YELLOW);
        y_offset += line_height;

        const pos_text = std.fmt.allocPrintZ(std.heap.c_allocator, "Position: {d}", .{ctx.cached_pos_entities}) catch "Position: ERROR";
        defer std.heap.c_allocator.free(pos_text);
        ray.DrawText(pos_text, 20, y_offset, font_size, ray.WHITE);
        y_offset += line_height;

        const sprite_text = std.fmt.allocPrintZ(std.heap.c_allocator, "Sprite: {d}", .{ctx.cached_sprite_entities}) catch "Sprite: ERROR";
        defer std.heap.c_allocator.free(sprite_text);
        ray.DrawText(sprite_text, 20, y_offset, font_size, ray.WHITE);
        y_offset += line_height;

        const texture_text = std.fmt.allocPrintZ(std.heap.c_allocator, "Texture: {d}", .{ctx.cached_texture_entities}) catch "Texture: ERROR";
        defer std.heap.c_allocator.free(texture_text);
        ray.DrawText(texture_text, 20, y_offset, font_size, ray.WHITE);
        y_offset += line_height;

        const shader_text = std.fmt.allocPrintZ(std.heap.c_allocator, "Shader: {d}", .{ctx.cached_shader_entities}) catch "Shader: ERROR";
        defer std.heap.c_allocator.free(shader_text);
        ray.DrawText(shader_text, 20, y_offset, font_size, ray.WHITE);
        y_offset += line_height;

        const anim_text = std.fmt.allocPrintZ(std.heap.c_allocator, "Animation: {d}", .{ctx.cached_anim_entities}) catch "Animation: ERROR";
        defer std.heap.c_allocator.free(anim_text);
        ray.DrawText(anim_text, 20, y_offset, font_size, ray.WHITE);
        y_offset += line_height;

        const memory_text = std.fmt.allocPrintZ(std.heap.c_allocator, "Component Memory: ~{d}KB", .{approx_memory_kb}) catch "Memory: ERROR";
        defer std.heap.c_allocator.free(memory_text);
        ray.DrawText(memory_text, 10, y_offset, font_size, ray.ORANGE);
        y_offset += line_height;

        // calculate texture memory usage
        const texture_memory_kb = calculateTextureMemory();
        const texture_mem_text = std.fmt.allocPrintZ(std.heap.c_allocator, "Texture Memory: ~{d}KB", .{texture_memory_kb}) catch "Texture Memory: ERROR";
        defer std.heap.c_allocator.free(texture_mem_text);
        ray.DrawText(texture_mem_text, 10, y_offset, font_size, ray.ORANGE);
        y_offset += line_height;

        // render batching info using cached values
        const batch_text = std.fmt.allocPrintZ(std.heap.c_allocator, "Render: {d} textured, {d} with shaders", .{ ctx.cached_texture_entities, ctx.cached_shader_entities }) catch "Render: ERROR";
        defer std.heap.c_allocator.free(batch_text);
        ray.DrawText(batch_text, 10, y_offset, font_size, ray.LIGHTGRAY);
        y_offset += line_height;
    }

    // render entity bounds and info
    if (ctx.debug_state.show_entity_bounds or ctx.debug_state.show_component_info) {
        renderEntityDebugInfo(ctx, &y_offset, font_size, line_height);
    }
}

fn renderEntityDebugInfo(ctx: *DebugLayerContext, y_offset: *i32, font_size: i32, line_height: i32) void {
    _ = ctx;
    _ = y_offset;
    _ = font_size;
    _ = line_height;
    const world = ecs.getWorld();

    // get entities with position and sprite components for bounds visualization
    var view = world.view(.{ components.Position, components.Sprite }, .{});
    var entity_count: u32 = 0;

    var it = view.entityIterator();
    while (it.next()) |entity| {
        const pos = view.get(components.Position, entity);
        const sprite = view.get(components.Sprite, entity);

        // draw entity bounds as a rectangle
        const bounds_color = ray.Color{ .r = 255, .g = 0, .b = 255, .a = 100 }; // magenta with transparency
        ray.DrawRectangleLines(@intFromFloat(pos.x), @intFromFloat(pos.y), @intFromFloat(sprite.size), @intFromFloat(sprite.size), bounds_color);

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
        }
        if (world.has(components.Velocity, entity)) {
            ray.DrawText("v", letter_x, letter_y, letter_size, ray.PURPLE);
            letter_x += letter_spacing;
        }

        if (world.has(components.Collider, entity)) {
            ray.DrawText("c", letter_x, letter_y, letter_size, ray.PURPLE);
            letter_x += letter_spacing;
        }

        entity_count += 1;

        // limit to first 20 entities to avoid screen clutter
        if (entity_count >= 1000) break;
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
