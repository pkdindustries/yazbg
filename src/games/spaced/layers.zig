// layers.zig - Spaced game rendering layers
const common = @import("common.zig");
const std = common.std;
const components = common.components;
const ecs = common.ecs;
const gfx = common.gfx;
const ray = common.ray;
const events = common.events;

// ---------------------------------------------------------------------------
// Game Layer - Renders all game entities
// ---------------------------------------------------------------------------

const GameContext = struct {
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) !*Self {
        _ = allocator;
        const ctx = std.heap.c_allocator.create(Self) catch unreachable;
        return ctx;
    }
    
    pub fn deinit(self: *Self) void {
        std.heap.c_allocator.destroy(self);
    }
};

fn gameInit(allocator: std.mem.Allocator) anyerror!*anyopaque {
    const ctx = try GameContext.init(allocator);
    return ctx;
}

fn gameDeinit(ctx: *anyopaque) void {
    const self = @as(*GameContext, @ptrCast(@alignCast(ctx)));
    self.deinit();
}

fn gameUpdate(ctx: *anyopaque, dt: f32) void {
    _ = ctx;
    _ = dt;
    // Game update logic is handled in game.zig
}

fn gameRender(ctx: *anyopaque, rc: gfx.RenderContext) void {
    _ = ctx;
    _ = rc;
    
    // Render all entities with position and sprite
    gfx.drawEntities(null); // Use default sizing
}

fn gameProcessEvent(ctx: *anyopaque, event: *const anyopaque) void {
    _ = ctx;
    const e = @as(*const events.Event, @ptrCast(@alignCast(event))).*;
    
    switch (e) {
        .PlayerDied => {
            std.debug.print("Player died - game over effect could go here\n", .{});
        },
        else => {
            // Handle other events
        },
    }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn createLayers() ![]gfx.Layer {
    const allocator = std.heap.c_allocator;
    
    const layers = try allocator.alloc(gfx.Layer, 1);
    
    layers[0] = gfx.Layer{
        .name = "game",
        .order = 100,
        .init = gameInit,
        .deinit = gameDeinit,
        .update = gameUpdate,
        .render = gameRender,
        .processEvent = gameProcessEvent,
    };
    
    return layers;
}