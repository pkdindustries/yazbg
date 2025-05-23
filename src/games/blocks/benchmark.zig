//! Tetromino benchmark – renders 10,000 animated tetromino sprites using modern layer system.
//!
//! Every tetromino is pre-rendered once into its own 4×4-cell render texture
//! (with the familiar rounded-corner block look).  At runtime we spawn 10,000
//! ECS entities that share those textures.  Each entity carries an Animation
//! component that drives position, scale *and* rotation, so the entire piece
//! moves and morphs as a single sprite.
//!
//! Build/run:
//!     zig build benchmark

const common = @import("common.zig");
const std = common.std;
const components = common.components;
const ecs = common.ecs;
const gfx = common.gfx;
const ray = common.ray;
const textures = common.textures;
const shaders = common.shaders;
const animsys = common.animsys;
const game_constants = common.game_constants;
const engine = @import("engine");

const blockbuilder = @import("blockbuilder.zig");
const pieces = @import("pieces.zig");
const ecsroot = @import("ecs");

// ---------------------------------------------------------------------------
// Benchmark Layer Context
// ---------------------------------------------------------------------------

pub const BenchmarkContext = struct {
    allocator: std.mem.Allocator,
    piece_entries: [pieces.tetraminos.len]textures.AtlasEntry,
    global_prng: std.Random.DefaultPrng,
    last_reset_ms: i64,
    total_pieces: usize,

    const RESET_INTERVAL_MS: i64 = 3_000;

    pub fn init(allocator: std.mem.Allocator) !*BenchmarkContext {
        const self = try allocator.create(BenchmarkContext);

        // Initialize PRNG
        var seed: u64 = undefined;
        std.crypto.random.bytes(std.mem.asBytes(&seed));

        self.* = .{
            .allocator = allocator,
            .piece_entries = undefined,
            .global_prng = std.Random.DefaultPrng.init(seed),
            .last_reset_ms = std.time.milliTimestamp(),
            .total_pieces = 10000,
        };

        // Create atlas entries for all tetrominos
        try self.createPieceAtlasEntries();

        // Spawn initial pieces
        try self.spawnAllPieces();
        self.randomizeAllAnimations();

        return self;
    }

    pub fn deinit(self: *BenchmarkContext) void {
        self.allocator.destroy(self);
    }

    pub fn update(self: *BenchmarkContext, dt: f32) void {
        _ = dt;

        // Periodically reset animations for visual variety
        const now_ms = std.time.milliTimestamp();
        if (now_ms - self.last_reset_ms >= RESET_INTERVAL_MS) {
            self.randomizeAllAnimations();
            self.last_reset_ms = now_ms;
        }
    }

    pub fn render(self: *BenchmarkContext, rc: gfx.RenderContext) void {
        _ = self;
        _ = rc;
        ray.DrawFPS(0, 0); // reset FPS counter

        // Draw all entities using the engine's optimized renderer
        gfx.drawEntities(calculateSizeFromScale);
    }

    // Create atlas entries for all seven tetrominos
    fn createPieceAtlasEntries(self: *BenchmarkContext) !void {
        const alloc = self.allocator;
        var i: usize = 0;
        while (i < pieces.tetraminos.len) : (i += 1) {
            const key_heap = try std.fmt.allocPrint(alloc, "benchmark_piece_{d}", .{i});
            self.piece_entries[i] = try textures.createEntry(key_heap, drawTetrominoIntoTile, &pieces.tetraminos[i]);
        }
    }

    // Spawn all benchmark pieces
    fn spawnAllPieces(self: *BenchmarkContext) !void {
        const rng = self.global_prng.random();
        var i: usize = 0;
        while (i < self.total_pieces) : (i += 1) {
            try self.spawnAnimatedTetromino(rng);
        }
    }

    // Spawn one animated tetromino
    fn spawnAnimatedTetromino(self: *BenchmarkContext, rng: anytype) !void {
        const screen_w: f32 = @floatFromInt(gfx.Window.OGWIDTH);
        const screen_h: f32 = @floatFromInt(gfx.Window.OGHEIGHT);

        // Random tetromino type
        const t_index = rng.intRangeAtMost(usize, 0, pieces.tetraminos.len - 1);
        const entry = self.piece_entries[t_index];

        // Random starting position
        const piece_px_f: f32 = @floatFromInt(piecePx());
        const start_x = rng.float(f32) * (screen_w - piece_px_f);
        const start_y = rng.float(f32) * (screen_h - piece_px_f);

        // Random scale and rotation
        const scale0_blocks = (rng.float(f32) * 2.0) - 0.5; // -0.5 to 1.5
        const size0 = 4.0 * scale0_blocks;
        const rot0 = rng.float(f32) * 2.0; // 0-2 turns
        const duration_ms: i64 = @intFromFloat(3000.0 + rng.float(f32) * 4000.0);

        // Create entity with components
        const entity = ecs.createEntity();

        ecs.replace(components.Position, entity, .{ .x = start_x, .y = start_y });
        ecs.replace(components.Sprite, entity, .{ .rgba = .{ 255, 255, 255, 255 }, .size = size0, .rotation = rot0 });
        ecs.replace(components.Texture, entity, .{ .texture = entry.tex, .uv = entry.uv, .created = false });

        // Add animation component
        const start_time = std.time.milliTimestamp();
        ecs.replace(components.Animation, entity, .{
            .animate_position = true,
            .start_pos = .{ start_x, start_y },
            .target_pos = .{ start_x, start_y },
            .animate_scale = true,
            .target_scale = 1,
            .animate_rotation = true,
            .start_rotation = rot0,
            .target_rotation = 0,
            .start_time = start_time,
            .duration = duration_ms,
            .easing = .ease_in_out,
            .remove_when_done = false,
        });
    }

    // Randomize all animations for visual variety
    fn randomizeAllAnimations(self: *BenchmarkContext) void {
        const world = ecs.getWorld();
        var view = world.view(.{ components.Position, components.Sprite, components.Animation }, .{});
        var it = view.entityIterator();

        const rng = self.global_prng.random();
        const screen_w: f32 = @floatFromInt(gfx.Window.OGWIDTH);
        const screen_h: f32 = @floatFromInt(gfx.Window.OGHEIGHT);
        const piece_px_f: f32 = @floatFromInt(piecePx());

        while (it.next()) |entity| {
            const pos_ptr = view.get(components.Position, entity);
            const sprite_ptr = view.get(components.Sprite, entity);
            const anim_ptr = view.get(components.Animation, entity);

            // New random start position
            const start_x = rng.float(f32) * (screen_w - piece_px_f);
            const start_y = rng.float(f32) * (screen_h - piece_px_f);
            pos_ptr.* = .{ .x = start_x, .y = start_y };

            // Huge outward burst – pick a direction and push far off-screen
            const max_offset_x = screen_w * 1.5;
            const max_offset_y = screen_h * 1.5;
            const offset_x = (rng.float(f32) * max_offset_x * 2.0) - max_offset_x;
            const offset_y = (rng.float(f32) * max_offset_y * 2.0) - max_offset_y;

            // Start small then expand
            const size0 = 4.0 * (0.2 + rng.float(f32) * 0.6);
            sprite_ptr.size = size0;

            // Multi-spin rotation
            const rot0 = rng.float(f32) * 4.0;
            const rot1 = rot0 + ((rng.float(f32) * 6.0) - 3.0);
            sprite_ptr.rotation = rot0;

            const now_ms = std.time.milliTimestamp();
            anim_ptr.* = .{
                .animate_position = true,
                .start_pos = .{ start_x, start_y },
                .target_pos = .{ start_x + offset_x, start_y + offset_y },
                .animate_scale = true,
                .animate_rotation = true,
                .start_rotation = rot0,
                .target_rotation = rot1,
                .start_time = now_ms,
                .duration = @intFromFloat(1200.0 + rng.float(f32) * 1800.0), // 1.2 – 3.0 s
                .easing = .ease_out,
                .remove_when_done = false,
            };
        }
    }
};

// ---------------------------------------------------------------------------
// Helper Functions
// ---------------------------------------------------------------------------

// Convert sprite scale to actual pixel size
fn calculateSizeFromScale(scale: f32) f32 {
    return 10.0 * scale; // match the gfx.init cell size
}

// Size calculations for tetromino pieces
fn tilePx() i32 {
    return 10 * 2; // match the gfx.init cell size
}

fn piecePx() i32 {
    return tilePx() * 4;
}

// Draw a tetromino into a single atlas tile
fn drawTetrominoIntoTile(
    page_tex: *const ray.RenderTexture2D,
    tile_x: i32,
    tile_y: i32,
    tile_size: i32,
    _: []const u8,
    context: ?*const anyopaque,
) void {
    const t_unaligned: *align(1) const pieces.tetramino = @ptrCast(context.?);
    const t: *const pieces.tetramino = @alignCast(t_unaligned);

    // One block == 1/4 of the tile
    const sub_px: i32 = @divTrunc(tile_size, 4);
    const shape = t.shape[0]; // first rotation is enough

    var row: usize = 0;
    while (row < 4) : (row += 1) {
        var col: usize = 0;
        while (col < 4) : (col += 1) {
            if (!shape[row][col]) continue;

            const block_x = tile_x + @as(i32, @intCast(col)) * sub_px;
            const block_y = tile_y + @as(i32, @intCast(row)) * sub_px;

            var color_copy = t.color; // stack copy for pointer cast
            blockbuilder.drawBlockIntoTile(page_tex, block_x, block_y, sub_px, "", &color_copy);
        }
    }
}

// ---------------------------------------------------------------------------
// Layer Factory Functions
// ---------------------------------------------------------------------------

fn benchmarkInit(allocator: std.mem.Allocator) anyerror!*anyopaque {
    const ctx = try BenchmarkContext.init(allocator);
    return ctx;
}

fn benchmarkDeinit(ctx: *anyopaque) void {
    const self = @as(*BenchmarkContext, @ptrCast(@alignCast(ctx)));
    self.deinit();
}

fn benchmarkUpdate(ctx: *anyopaque, dt: f32) void {
    const self = @as(*BenchmarkContext, @ptrCast(@alignCast(ctx)));
    self.update(dt);
}

fn benchmarkRender(ctx: *anyopaque, rc: gfx.RenderContext) void {
    const self = @as(*BenchmarkContext, @ptrCast(@alignCast(ctx)));
    self.render(rc);
}

// Create the benchmark layer
pub fn createBenchmarkLayer() !gfx.Layer {
    return gfx.Layer{
        .name = "benchmark",
        .order = 100,
        .init = benchmarkInit,
        .deinit = benchmarkDeinit,
        .update = benchmarkUpdate,
        .render = benchmarkRender,
    };
}

// ---------------------------------------------------------------------------
// Main Function
// ---------------------------------------------------------------------------

pub fn main() !void {
    var timer = try std.time.Timer.start();
    ray.SetTraceLogLevel(ray.LOG_WARNING);

    const allocator = std.heap.c_allocator;

    // Initialize engine systems
    ecs.init(allocator);
    defer ecs.deinit();

    try gfx.init(std.heap.c_allocator, game_constants.CELL_SIZE * 2);
    defer gfx.deinit();

    // Add the benchmark layer
    const benchmark_layer = try createBenchmarkLayer();
    try gfx.window.addLayer(benchmark_layer);

    std.debug.print("benchmark init {}ms\n", .{timer.lap() / 1_000_000});

    // Main loop using modern engine frame system
    while (!ray.WindowShouldClose()) {
        const dt = ray.GetFrameTime();
        gfx.frame(dt);
    }
}
