const common = @import("common.zig");
const std = common.std;
const ecs = common.ecs;
const gfx = common.gfx;
const ray = common.ray;
const events = common.events;
const constants = common.game_constants;

// Game imports
const game = @import("game.zig");
const layers = @import("layers.zig");

const MS = 1_000_000;
pub var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    var timer = try std.time.Timer.start();
    ray.SetTraceLogLevel(ray.LOG_WARNING);

    // const allocator = gpa.allocator();
    // defer _ = gpa.deinit();

    const allocator = std.heap.c_allocator;

    ecs.init(allocator);
    defer ecs.deinit();

    events.init(allocator);
    defer events.deinit();

    // Initialize graphics first - needed for texture system
    try gfx.init(allocator, 32); // 32x32 base sprite size
    defer gfx.deinit();

    try game.init(allocator);
    defer game.deinit();

    // Initialize game layers
    const layerarray = try layers.createLayers();
    for (layerarray) |layer| {
        try gfx.window.addLayer(layer);
    }

    std.debug.print("spaced init {}ms\n", .{timer.lap() / MS});
    printControls();

    while (!ray.WindowShouldClose()) {
        timer.reset();

        // Input
        events.processInputs();
        
        // Game update
        const dt = ray.GetFrameTime();
        game.update(dt);

        // Process events
        game.process(events.queue());

        // Process events for all layers
        for (events.queue().items()) |event| {
            gfx.window.processEvent(&event.event);
        }

        events.queue().clear();
        const gamelogic_elapsed = timer.lap();

        // Render
        gfx.frame(dt);

        // Performance stats
        const total_elapsed = timer.read();
        if (@mod(@as(u64, @intFromFloat(ray.GetTime() * 1000)), 1000) < 16) {
            std.debug.print("frame {}ms, game {}ms, total {}ms\n", .{
                total_elapsed / MS,
                gamelogic_elapsed / MS,
                total_elapsed / MS,
            });
        }
    }
}

fn printControls() void {
    std.debug.print("controls:\n", .{});
    std.debug.print("  WASD: move\n", .{});
    std.debug.print("  ESC: quit\n", .{});
    std.debug.print("  L: debug\n", .{});
}