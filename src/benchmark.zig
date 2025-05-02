const std = @import("std");
const ray = @import("raylib.zig");
const ecs = @import("ecs.zig");
const ecsroot = @import("ecs");
const components = @import("components.zig");
const animsys = @import("systems/anim.zig");
const rendersys = @import("systems/render.zig");
const gfx = @import("gfx.zig");
const textures = @import("textures.zig");
const Grid = @import("grid.zig").Grid;
const pieces = @import("pieces.zig");

// -----------------------------------------------------------------------------
// Grid/Game-logic micro-benchmark
// -----------------------------------------------------------------------------

// How many random collision-checks to run. Reduced to 50k when including gridsvc
// to avoid too many entity creations but still get meaningful measurements.
const GRID_BENCH_ITERATIONS: usize = 500_0000;

fn benchmarkGridLogic() !void {
    ray.SetTraceLogLevel(ray.LOG_ERROR);

    std.debug.print("\nRunning Grid/Game-logic benchmark\n", .{});

    // We need ECS to test the grid service
    try setupEcs();
    defer ecs.deinit();

    // Setup raylib window for textures to work
    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT);
    ray.InitWindow(640, 480, "Grid Benchmark");
    defer ray.CloseWindow();

    // Initialize window settings needed for block textures
    gfx.window = .{
        .cellsize = 35,
        .cellpadding = 2,
        .gridoffsetx = 10,
        .gridoffsety = 10,
        .width = 640,
        .height = 480,
    };

    // Initialize block textures for gridsvc
    try textures.init();
    defer textures.deinit();

    var grid = Grid.init();

    // Import gridsvc
    const gridsvc = @import("systems/gridsvc.zig");

    // Timer for the whole loop
    var timer = try std.time.Timer.start();

    const rng = prng.random();

    // Main tight loop – perform random `checkmove` calls and gridsvc updates
    std.debug.print("Starting grid benchmark with {d} iterations...\n", .{GRID_BENCH_ITERATIONS});
    var i: usize = 0;
    while (i < GRID_BENCH_ITERATIONS) : (i += 1) {
        // Random tetramino and rotation
        const piece_idx: u32 = rng.intRangeAtMost(u32, 0, 6);
        const piece = pieces.tetraminos[piece_idx];
        const rot: u32 = rng.intRangeAtMost(u32, 0, 3);

        // Random position – allow a small out-of-bounds range to exercise the
        // boundary checks inside `checkmove`.
        const x: i32 = rng.intRangeAtMost(i32, -2, Grid.WIDTH + 1);
        const y: i32 = rng.intRangeAtMost(i32, -2, Grid.HEIGHT + 1);

        // Perform the collision test
        const result = grid.checkmove(piece, x, y, rot);

        // If valid move and within bounds, update the ECS state with gridsvc
        // Find the width and height by examining the shape
        const width = 4; // tetrominos are always 4x4 maximum
        const height = 4;
        if (result and x >= 0 and y >= 0 and x + width <= Grid.WIDTH and y + height <= Grid.HEIGHT) {
            // Every 1000th iteration, actually occupy cells to avoid too much spam
            if (i % 1000 == 0) {
                // Occupy cells with the piece color (randomly select a color)
                const color_idx = rng.intRangeAtMost(usize, 0, 7);
                const colors = [_][4]u8{
                    .{ 255, 0, 0, 255 }, // red
                    .{ 0, 255, 0, 255 }, // green
                    .{ 0, 0, 255, 255 }, // blue
                    .{ 255, 255, 0, 255 }, // yellow
                    .{ 0, 255, 255, 255 }, // cyan
                    .{ 255, 0, 255, 255 }, // magenta
                    .{ 255, 128, 0, 255 }, // orange
                    .{ 128, 128, 255, 255 }, // purple
                };

                // Occupy cells based on the piece shape
                for (0..height) |py| {
                    for (0..width) |px| {
                        if (piece.shape[rot][py][px]) {
                            const abs_x: usize = @intCast(x + @as(i32, @intCast(px)));
                            const abs_y: usize = @intCast(y + @as(i32, @intCast(py)));
                            gridsvc.occupyCell(abs_x, abs_y, colors[color_idx]);
                        }
                    }
                }

                // Every 5000th iteration, also test clearing cells
                if (i % 5000 == 0) {
                    // Clear a random row
                    const row = rng.intRangeAtMost(usize, 0, Grid.HEIGHT - 1);
                    gridsvc.removeLineCells(row);

                    // And shift a random row
                    const shift_row = rng.intRangeAtMost(usize, 0, Grid.HEIGHT - 2);
                    gridsvc.shiftRowCells(shift_row);

                    // Every 20000th iteration, clear everything
                    if (i % 20000 == 0) {
                        gridsvc.clearAllCells();
                    }
                }
            }
        }
    }

    const elapsed = timer.read();
    const elapsed_ms: f64 = @as(f64, @floatFromInt(elapsed)) / 1_000_000.0;
    const iter_per_ms: f64 = @as(f64, @floatFromInt(GRID_BENCH_ITERATIONS)) / elapsed_ms;

    std.debug.print("\n==== GRID BENCHMARK RESULTS ====\n", .{});
    std.debug.print("Grid checked {d} iterations in {d:.3} ms\n", .{ GRID_BENCH_ITERATIONS, elapsed_ms });
    std.debug.print("Performance: {d:.0} iterations/ms\n", .{iter_per_ms});
    std.debug.print("===============================\n", .{});
}

// Benchmark parameters
const NUM_ENTITIES = 100000;
const ANIMATION_DURATION_MS = 5000;
const BENCHMARK_ITERATIONS = 1;
var TEXTURED = true;
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

    // Only process up to current_entity_count, not the full array
    for (entities[0..current_entity_count]) |entity| {
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
            ecs.addOrReplace(components.Animation, entity, components.Animation{
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
        .cellsize = 7,
        .cellpadding = 2,
        .gridoffsetx = 10,
        .gridoffsety = 10,
        .width = 1024,
        .height = 768,
    };

    // Initialize block textures for the benchmark
    try textures.init();
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

    ray.DrawText(std.fmt.bufPrintZ(&buffer, "Active Entities: {d}/{d}", .{ current_entity_count, NUM_ENTITIES }) catch unreachable, 10, 60, 25, ray.WHITE);
    ray.DrawText(std.fmt.bufPrintZ(&buffer, "Animation: {d:.3} ms", .{avg_anim_time_ms}) catch unreachable, 10, 80, 25, ray.WHITE);
    ray.DrawText(std.fmt.bufPrintZ(&buffer, "Rendering: {d:.3} ms", .{avg_render_time_ms}) catch unreachable, 10, 100, 25, ray.WHITE);
    ray.DrawText(std.fmt.bufPrintZ(&buffer, "FPS: {d}", .{ray.GetFPS()}) catch unreachable, 10, 120, 25, ray.WHITE);
    ray.DrawText(std.fmt.bufPrintZ(&buffer, "Textures: {s}", .{if (TEXTURED) "ON" else "OFF"}) catch unreachable, 10, 140, 25, ray.WHITE);
    ray.DrawText("Press ESC to exit", 10, 180, 16, ray.WHITE);
}

fn createNewEntity() void {
    const rng = prng.random();

    // Cache screen size
    const screen_w = ray.GetScreenWidth();
    const screen_h = ray.GetScreenHeight();

    // Random position
    const x = @as(f32, @floatFromInt(rng.intRangeAtMost(c_int, 0, screen_w)));
    const y = @as(f32, @floatFromInt(rng.intRangeAtMost(c_int, 0, screen_h)));

    const block_colors = [_][4]u8{
        .{ 255, 0, 0, 255 }, // Red
        .{ 0, 255, 0, 255 }, // Green
        .{ 0, 0, 255, 255 }, // Blue
        .{ 255, 255, 0, 255 }, // Yellow
        .{ 255, 0, 255, 255 }, // Magenta
        .{ 0, 255, 255, 255 }, // Cyan
        .{ 255, 165, 0, 255 }, // Orange
        .{ 128, 0, 128, 255 }, // Purple
    };

    const color_idx = rng.intRangeAtMost(usize, 0, block_colors.len - 1);
    const color = block_colors[color_idx];

    // Random size
    const size = rng.float(f32) * 2 + 0.5;

    // Random rotation
    const rotation = rng.float(f32) * 0.5; // Initial rotation in turns (0.5 = 180 degrees)

    var entity = ecs.createEntity();
    if (TEXTURED) {
        entity = textures.createBlockTextureWithAtlas(x, y, color, size, rotation) catch |err| {
            std.debug.print("Failed to create textured block entity: {}\n", .{err});
            return;
        };
    } else {
        ecs.addOrReplace(components.Position, entity, components.Position{
            .x = x,
            .y = y,
        });
        ecs.addOrReplace(components.Sprite, entity, components.Sprite{
            .rgba = color,
            .size = size,
            .rotation = rotation,
        });
    }
    // Store the entity in our array
    entities[current_entity_count] = entity;

    // Add animation component (random movement)
    const target_x = @as(f32, @floatFromInt(rng.intRangeAtMost(c_int, 0, screen_w)));
    const target_y = @as(f32, @floatFromInt(rng.intRangeAtMost(c_int, 0, screen_h)));

    ecs.addOrReplace(components.Animation, entity, components.Animation{
        .animate_position = true,
        .start_pos = .{ x, y },
        .target_pos = .{ target_x, target_y },
        .animate_scale = true,
        .start_scale = size,
        .target_scale = rng.float(f32) * 2 + 0.5,
        .animate_rotation = true,
        .start_rotation = rotation,
        .target_rotation = rotation + rng.float(f32) * 2.5,
        .start_time = std.time.milliTimestamp(),
        .duration = ANIMATION_DURATION_MS,
        .easing = @enumFromInt(rng.intRangeAtMost(u8, 0, 3)),
        .remove_when_done = false,
    });

    current_entity_count += 1;
}

fn runFrame(timer: *std.time.Timer, frame_count: *u32, total_anim_time: *u64, total_render_time: *u64) void {
    // Add new entities gradually over time
    const animation_progress = @as(f32, @floatFromInt(frame_count.*)) / @as(f32, @floatFromInt(ANIMATION_DURATION_MS * 2));
    const target_entities = @min(NUM_ENTITIES, @as(usize, @intFromFloat(animation_progress * @as(f32, @floatFromInt(NUM_ENTITIES)))));

    // Limit how many entities we create per frame
    const max_new_per_frame = 1000;
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
    ray.SetTraceLogLevel(ray.LOG_ERROR);

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
        ray.DrawFPS(10, 10);
        // // Toggle textures with 'T' key
        // if (ray.IsKeyPressed(ray.KEY_T)) {
        //     TEXTURED = !TEXTURED;
        //     std.debug.print("Textures: {s}\n", .{if (TEXTURED) "ON" else "OFF"});
        // }

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

    textures.deinit();
    // Cleanup ECS
    ecs.deinit();
}

pub fn main() !void {
    std.debug.print("Starting Animation/Render System Benchmark\n", .{});
    std.debug.print("Entities: {d}, Iterations: {d}, Textures: {s}\n", .{ NUM_ENTITIES, BENCHMARK_ITERATIONS, if (TEXTURED) "ON" else "OFF" });

    // Seed global RNG
    var seed: u64 = undefined;
    std.crypto.random.bytes(std.mem.asBytes(&seed));
    prng = std.Random.DefaultPrng.init(seed);

    // Run grid/game-logic benchmark first (no ECS or rendering involved)
    try benchmarkGridLogic();

    // Setup for animation/render benchmark
    try setupEcs();
    // Setup rendering
    try setupRenderingForBenchmark();
    try createEntities();

    // Run the visual benchmark instead of the performance tests
    try visualBenchmark();

    // Always cleanup
    cleanup();

    std.debug.print("\nBenchmark complete!\n", .{});
}
