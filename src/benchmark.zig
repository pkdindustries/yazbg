const std = @import("std");
const ray = @import("raylib.zig");
const ecs = @import("ecs.zig");
const ecsroot = @import("ecs");
const components = @import("components.zig");
const animsys = @import("systems/animsys.zig");
const rendersys = @import("systems/rendersys.zig");
const gfx = @import("gfx.zig");

// Benchmark parameters
const NUM_ENTITIES = 100000;
const ANIMATION_DURATION_MS = 1000;
const BENCHMARK_ITERATIONS = 1;

// -----------------------------------------------------------------------------
// Globals
// -----------------------------------------------------------------------------

// All benchmark entities
var entities: [NUM_ENTITIES]ecsroot.Entity = undefined;

// Single PRNG reused across the whole benchmark (instead of re-seeding each time)
var prng: std.Random.DefaultPrng = undefined;

// Setup functions
fn setupEcs() !void {
    std.debug.print("Initializing ECS...\n", .{});
    ecs.init();
}

// Track the current number of active entities
var current_entity_count: usize = 0;

// Track performance per 10000 entities
var batch_frame_count: u32 = 0;
var batch_anim_time: u64 = 0;
var batch_render_time: u64 = 0;
var last_entity_milestone: usize = 0;

fn createEntities() !void {
    std.debug.print("Creating entities gradually over time...\n", .{});

    // Start with 0 entities - we'll create them incrementally
    current_entity_count = 0;
    batch_frame_count = 0;
    batch_anim_time = 0;
    batch_render_time = 0;
    last_entity_milestone = 0;
}

fn resetAnimations() void {
    const rng = prng.random();
    const current_time = std.time.milliTimestamp();

    // Cache render size to avoid repeated C calls
    const render_w = ray.GetRenderWidth();
    const render_h = ray.GetRenderHeight();

    for (entities) |entity| {
        // Get position
        if (ecs.get(components.Position, entity)) |pos| {
            const x = pos.x;
            const y = pos.y;

            // Get sprite
            var size: f32 = 1.0;
            if (ecs.get(components.Sprite, entity)) |sprite| {
                size = sprite.size;
            }

            // Add animation component (random movement)
            const target_x = @as(f32, @floatFromInt(rng.intRangeAtMost(c_int, -render_w, render_w * 2)));
            const target_y = @as(f32, @floatFromInt(rng.intRangeAtMost(c_int, -render_h, render_h * 2)));

            // Update animation component
            ecs.add(components.Animation, entity, components.Animation{
                .animate_position = true,
                .start_pos = .{ x, y },
                .target_pos = .{ target_x, target_y },
                .animate_scale = true,
                .start_scale = size,
                .target_scale = rng.float(f32) * 1.5 + 0.5,
                .animate_rotation = true,
                .start_rotation = 0.0,
                .target_rotation = rng.float(f32) * 2.0,
                .start_time = current_time,
                .duration = ANIMATION_DURATION_MS,
                .easing = @enumFromInt(rng.intRangeAtMost(u8, 0, 3)),
                .remove_when_done = false,
            });
        }
    }
}

fn setupRenderingForBenchmark() !void {
    std.debug.print("\nSetting up rendering for benchmark...\n", .{});
    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT | ray.FLAG_WINDOW_RESIZABLE);
    ray.InitWindow(1024, 768, "Animation/Render Benchmark");

    // Initialize window settings needed for render system
    gfx.window = .{
        .cellsize = 20,
        .cellpadding = 2,
        .gridoffsetx = 10,
        .gridoffsety = 10,
        .width = 1024,
        .height = 768,
    };
}

fn benchmarkRenderSystem() !void {
    std.debug.print("\nBenchmarking Render System...\n", .{});

    var timer = try std.time.Timer.start();
    var total_time: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |i| {
        // Reset timer
        timer.reset();

        // Begin draw
        ray.BeginDrawing();
        ray.ClearBackground(ray.BLACK);

        // Run render system
        rendersys.drawSprites();

        // End draw
        ray.EndDrawing();

        // Record elapsed time
        const elapsed = timer.read();
        total_time += elapsed;

        // Print progress every 10 iterations
        if ((i + 1) % 10 == 0) {
            std.debug.print("Iteration {d}/{d}: {d} ns\n", .{ i + 1, BENCHMARK_ITERATIONS, elapsed });
        }
    }

    const avg_time = total_time / BENCHMARK_ITERATIONS;
    const avg_time_ms = @as(f64, @floatFromInt(avg_time)) / 1_000_000.0;

    std.debug.print("\nRender System Benchmark Results:\n", .{});
    std.debug.print("Total entities: {d}\n", .{NUM_ENTITIES});
    std.debug.print("Average time: {d:.4} ms\n", .{avg_time_ms});
    std.debug.print("Entities per ms: {d:.2}\n", .{@as(f64, @floatFromInt(NUM_ENTITIES)) / avg_time_ms});
}

// -----------------------------------------------------------------------------
// Visual benchmark helpers
// -----------------------------------------------------------------------------

fn drawStats(avg_anim_time_ms: f64, avg_render_time_ms: f64) void {
    var buffer: [64]u8 = undefined;

    ray.DrawText("Visual Animation Benchmark", 10, 30, 30, ray.WHITE);
    ray.DrawText(std.fmt.bufPrintZ(&buffer, "Active Entities: {d}/{d}", .{ current_entity_count, NUM_ENTITIES }) catch unreachable, 10, 60, 20, ray.WHITE);
    ray.DrawText(std.fmt.bufPrintZ(&buffer, "Animation: {d:.3} ms", .{avg_anim_time_ms}) catch unreachable, 10, 80, 20, ray.WHITE);
    ray.DrawText(std.fmt.bufPrintZ(&buffer, "Rendering: {d:.3} ms", .{avg_render_time_ms}) catch unreachable, 10, 100, 20, ray.WHITE);
    ray.DrawText(std.fmt.bufPrintZ(&buffer, "FPS: {d}", .{ray.GetFPS()}) catch unreachable, 10, 120, 20, ray.WHITE);
    ray.DrawText("Press ESC to exit", 10, 140, 16, ray.WHITE);
}

fn createNewEntity() void {
    const rng = prng.random();

    // Cache screen size
    const screen_w = ray.GetScreenWidth();
    const screen_h = ray.GetScreenHeight();

    const entity = ecs.createEntity();
    entities[current_entity_count] = entity;

    // Random position
    const x = @as(f32, @floatFromInt(rng.intRangeAtMost(c_int, 0, screen_w)));
    const y = @as(f32, @floatFromInt(rng.intRangeAtMost(c_int, 0, screen_h)));

    // Random color
    const r = rng.intRangeAtMost(u8, 50, 255);
    const g = rng.intRangeAtMost(u8, 50, 255);
    const b = rng.intRangeAtMost(u8, 50, 255);
    const a = rng.intRangeAtMost(u8, 150, 255);

    // Random size
    const size = rng.float(f32) * 2 + 0.5;

    // Add position component
    ecs.add(components.Position, entity, components.Position{
        .x = x,
        .y = y,
    });

    // Add sprite component
    ecs.add(components.Sprite, entity, components.Sprite{
        .rgba = .{ r, g, b, a },
        .size = size,
    });

    // Add animation component (random movement)
    const target_x = @as(f32, @floatFromInt(rng.intRangeAtMost(c_int, 0, screen_w)));
    const target_y = @as(f32, @floatFromInt(rng.intRangeAtMost(c_int, 0, screen_h)));

    ecs.add(components.Animation, entity, components.Animation{
        .animate_position = true,
        .start_pos = .{ x, y },
        .target_pos = .{ target_x, target_y },
        .animate_scale = true,
        .start_scale = size,
        .target_scale = rng.float(f32) * 2 + 0.5,
        .animate_rotation = true,
        .start_rotation = 0.0,
        .target_rotation = rng.float(f32) * 2.0,
        .start_time = std.time.milliTimestamp(),
        .duration = ANIMATION_DURATION_MS,
        .easing = @enumFromInt(rng.intRangeAtMost(u8, 0, 3)),
        .remove_when_done = false,
    });

    current_entity_count += 1;
}

fn runFrame(timer: *std.time.Timer, frame_count: *u32, total_anim_time: *u64, total_render_time: *u64) void {
    // Add new entities gradually over time
    const animation_progress = @as(f32, @floatFromInt(frame_count.*)) / @as(f32, @floatFromInt(ANIMATION_DURATION_MS * 4));
    const target_entities = @min(NUM_ENTITIES, @as(usize, @intFromFloat(animation_progress * @as(f32, @floatFromInt(NUM_ENTITIES)))));

    // Limit how many entities we create per frame to avoid lag spikes
    const max_new_per_frame = 100;
    const to_create = @min(target_entities - current_entity_count, max_new_per_frame);

    // Create new entities if needed
    var i: usize = 0;
    while (i < to_create) : (i += 1) {
        createNewEntity();
    }

    // Measure animation system performance
    timer.reset();
    animsys.animationSystem();
    const anim_time = timer.read();
    total_anim_time.* += anim_time;
    batch_anim_time += anim_time;

    // Measure render system performance
    timer.reset();

    ray.BeginDrawing();
    ray.ClearBackground(ray.BLACK);

    // Draw entities
    rendersys.drawSprites();

    const avg_anim_time_ms = @as(f64, @floatFromInt(total_anim_time.*)) / @as(f64, @floatFromInt(frame_count.* + 1)) / 1_000_000.0;
    const avg_render_time_ms = @as(f64, @floatFromInt(total_render_time.*)) / @as(f64, @floatFromInt(frame_count.* + 1)) / 1_000_000.0;

    drawStats(avg_anim_time_ms, avg_render_time_ms);

    ray.EndDrawing();

    const render_time = timer.read();
    total_render_time.* += render_time;
    batch_render_time += render_time;
    batch_frame_count += 1;

    // Print info every 10000 entities (only when we cross a milestone)
    const milestone = current_entity_count / 10000;
    if (milestone > last_entity_milestone and current_entity_count > 0) {
        const batch_avg_anim_time_ms = @as(f64, @floatFromInt(batch_anim_time)) / @as(f64, @floatFromInt(batch_frame_count)) / 1_000_000.0;
        const batch_avg_render_time_ms = @as(f64, @floatFromInt(batch_render_time)) / @as(f64, @floatFromInt(batch_frame_count)) / 1_000_000.0;
        std.debug.print("Entities: {d}, FPS: {d}, Anim: {d:.3} ms, Draw: {d:.3} ms\n", .{ current_entity_count, ray.GetFPS(), batch_avg_anim_time_ms, batch_avg_render_time_ms });

        // Reset batch counters
        batch_frame_count = 0;
        batch_anim_time = 0;
        batch_render_time = 0;
        last_entity_milestone = milestone;
    }

    frame_count.* += 1;
}

fn visualBenchmark() !void {
    std.debug.print("\nStarting Visual Benchmark (animation demo)...\n", .{});
    std.debug.print("Press ESC to exit\n", .{});

    // Reset animations to start fresh
    resetAnimations();

    // Track frames and timing
    var frame_count: u32 = 0;
    var total_anim_time: u64 = 0;
    var total_render_time: u64 = 0;
    var timer = try std.time.Timer.start();
    var last_reset_time = std.time.milliTimestamp();

    // Main loop for visual benchmark
    while (!ray.WindowShouldClose()) {
        const current_time = std.time.milliTimestamp();

        runFrame(&timer, &frame_count, &total_anim_time, &total_render_time);

        // Check if all animations are done and reset them if needed
        if (current_time > last_reset_time + ANIMATION_DURATION_MS - 500) {
            resetAnimations();
            last_reset_time = current_time;
        }
    }

    // Close window
    ray.CloseWindow();

    std.debug.print("\nVisual Benchmark complete!\n", .{});
    std.debug.print("Average Animation time: {d:.4} ms\n", .{@as(f64, @floatFromInt(total_anim_time)) / @as(f64, @floatFromInt(frame_count)) / 1_000_000.0});
    std.debug.print("Average Render time: {d:.4} ms\n", .{@as(f64, @floatFromInt(total_render_time)) / @as(f64, @floatFromInt(frame_count)) / 1_000_000.0});
}

fn cleanup() void {
    std.debug.print("\nCleaning up...\n", .{});

    // Close window
    ray.CloseWindow();

    // Cleanup ECS
    ecs.deinit();
}

pub fn main() !void {
    std.debug.print("Starting Animation/Render System Benchmark\n", .{});
    std.debug.print("Entities: {d}, Iterations: {d}\n", .{ NUM_ENTITIES, BENCHMARK_ITERATIONS });

    // Seed global RNG
    var seed: u64 = undefined;
    std.crypto.random.bytes(std.mem.asBytes(&seed));
    prng = std.Random.DefaultPrng.init(seed);

    // Setup
    try setupEcs();
    // Setup rendering
    try setupRenderingForBenchmark();
    try createEntities();

    // Run the visual benchmark instead of the performance tests
    try visualBenchmark();

    // For performance benchmarks (uncomment these and comment out visualBenchmark)
    // try benchmarkAnimationSystem();
    // resetAnimations();
    // try setupRenderingForBenchmark();
    // try benchmarkRenderSystem();
    // cleanup();

    std.debug.print("\nBenchmark complete!\n", .{});
}
