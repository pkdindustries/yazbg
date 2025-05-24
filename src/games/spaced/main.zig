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
    // Custom config for spaced game - wider aspect ratio for space game
    const config = gfx.GraphicsConfig{
        .design_width = 1920, // Wider for space shooter
        .design_height = 1080, // 16:9 aspect ratio
        .render_scale = 4, // Keep super-sampling for quality
        .fullscreen = false, // Can be set to true
        .vsync = false,
        .title = "spaced",
        .texture_tile_size = 512,
    };

    try gfx.initWithConfig(allocator, config);
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

        // Render
        gfx.frame(dt);
    }
}

fn printControls() void {
    std.debug.print("controls:\n", .{});
    std.debug.print("  A/D: turn left/right\n", .{});
    std.debug.print("  W: thrust forward\n", .{});
    std.debug.print("  ESC: quit\n", .{});
    std.debug.print("  L: debug\n", .{});
}
