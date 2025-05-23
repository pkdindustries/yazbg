const common = @import("common.zig");
const std = common.std;
const ecs = common.ecs;
const gfx = common.gfx;
const sfx = common.sfx;
const ray = common.ray;
const events = common.events;
const constants = common.game_constants;

// Game imports
const game = @import("game.zig");
const hud = @import("hud.zig");
const layers = @import("layers.zig");
const audio = @import("audio.zig");

const MS = 1_000_000;
pub var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    var timer = try std.time.Timer.start();
    ray.SetTraceLogLevel(ray.LOG_WARNING);

    // Create central allocator to use throughout the application
    // const allocator = gpa.allocator();
    // defer _ = gpa.deinit();

    const allocator = std.heap.c_allocator;

    ecs.init(allocator);
    defer ecs.deinit();

    events.init(allocator);
    defer events.deinit();

    try game.init(allocator);
    defer game.deinit();

    try sfx.init(allocator);
    defer sfx.deinit();

    // Load audio configuration
    try sfx.loadConfig(audio.audio_config);

    // Initialize graphics with texture tile size (2x cell size for high quality)
    try gfx.init(allocator, constants.CELL_SIZE * 2);
    defer gfx.deinit();

    // Initialize game layers
    const layerarray = try layers.createLayers();
    for (layerarray) |layer| {
        try gfx.window.addLayer(layer);
    }

    std.debug.print("system init {}ms\n", .{timer.lap() / MS});

    printkeys();

    while (!ray.WindowShouldClose()) {
        // update clock
        game.tick(std.time.milliTimestamp());
        // keep music fed
        sfx.updateMusic();

        // Handle single-press keys via GetKeyPressed() – suitable for actions
        // that should not auto-repeat (e.g. toggle, debug, etc.).
        switch (ray.GetKeyPressed()) {
            ray.KEY_P => events.push(.Pause, events.Source.Input),
            ray.KEY_R => events.push(.Reset, events.Source.Input),
            ray.KEY_SPACE => events.push(.HardDrop, events.Source.Input),
            ray.KEY_C => events.push(.SwapPiece, events.Source.Input),
            ray.KEY_B => events.push(.NextBackground, events.Source.Input),
            ray.KEY_M => events.push(.MuteAudio, events.Source.Input),
            ray.KEY_N => events.push(.NextMusic, events.Source.Input),
            ray.KEY_L => events.push(.Debug, events.Source.Input),
            else => {},
        }

        // Keys that benefit from auto-repeat (movement / rotation)
        const repeat_keys = [_]struct { key: c_int, ev: events.Event }{
            .{ .key = ray.KEY_LEFT, .ev = events.Event.MoveLeft },
            .{ .key = ray.KEY_RIGHT, .ev = events.Event.MoveRight },
            .{ .key = ray.KEY_DOWN, .ev = events.Event.MoveDown },
            .{ .key = ray.KEY_UP, .ev = events.Event.Rotate },
            .{ .key = ray.KEY_Z, .ev = events.Event.RotateCCW },
        };

        inline for (repeat_keys) |rk| {
            if (ray.IsKeyPressed(rk.key) or ray.IsKeyPressedRepeat(rk.key)) {
                events.push(rk.ev, events.Source.Input);
            }
        }

        // Check if it's time for automatic piece drop
        if (game.dropready()) {
            events.push(.AutoDrop, events.Source.Game);
        }

        // queued events
        game.process(events.queue());
        audio.processEvents(events.queue());
        hud.process(events.queue());

        // Process events for all layers
        for (events.queue().items()) |event| {
            gfx.window.processEvent(&event.event);
        }

        events.queue().clear();
        const gamelogic_elapsed = timer.lap();

        // draw the frame with delta time
        const dt = ray.GetFrameTime();
        gfx.frame(dt);

        // performance stats
        const frametime_elapsed = timer.lap();
        const total_elapsed = gamelogic_elapsed + frametime_elapsed;
        if (gamelogic_elapsed > 1 * MS or frametime_elapsed > 16 * MS) {
            std.debug.print("frame {}ms, game {}ms, total {}ms\n", .{ frametime_elapsed / MS, gamelogic_elapsed / MS, total_elapsed / MS });
        }
    }
}

fn printkeys() void {
    std.debug.print("keys:\n", .{});
    std.debug.print("  left/right: move\n", .{});
    std.debug.print("  up: rotate counter-clockwise\n", .{});
    std.debug.print("  z: rotate clockwise\n", .{});
    std.debug.print("  down: drop\n", .{});
    std.debug.print("  space: hard drop\n", .{});
    std.debug.print("  c: swap piece\n", .{});
    std.debug.print("  b: next background\n", .{});
    std.debug.print("  m: mute\n", .{});
    std.debug.print("  n: next music\n", .{});
    std.debug.print("  p: pause\n", .{});
    std.debug.print("  r: reset\n", .{});
}
