//! Tetromino benchmark – renders 5 000 animated tetromino sprites.
//!
//! Every tetromino is pre-rendered once into its own 4×4-cell render texture
//! (with the familiar rounded-corner block look).  At runtime we spawn 5 000
//! ECS entities that share those textures.  Each entity carries an Animation
//! component that drives position, scale *and* rotation, so the entire piece
//! moves and morphs as a single sprite.
//!
//! Build/run:
//!     zig build benchmark

const std = @import("std");
const ray = @import("raylib.zig");

const ecs = @import("ecs.zig");
const ecsroot = @import("ecs");
const components = @import("components.zig");
const textures = @import("textures.zig");
const pieces = @import("pieces.zig");
const rendersys = @import("systems/render.zig");
const animsys = @import("systems/anim.zig");
const gfx = @import("gfx.zig");
const shaders = @import("shaders.zig");
// ---------------------------------------------------------------------------
// Globals – one render texture per tetromino shape (shared between entities)
// ---------------------------------------------------------------------------

var piece_textures: [pieces.tetraminos.len]*ray.RenderTexture2D = undefined;

// PRNG for runtime randomisations
var global_prng: std.Random.DefaultPrng = undefined;

// Size of one block while drawing into the piece texture (double resolution to
// match the atlas quality used elsewhere).
fn tilePx() i32 {
    return gfx.window.cellsize * 2;
}

// Width/height of the full tetromino texture in pixels (4 blocks wide).
fn piecePx() i32 {
    return tilePx() * 4;
}

/// Draw one rounded block at `col,row` (0-3,0-3) inside the currently bound
/// render-texture.  Drawing style matches textures.drawBlockIntoTile().
fn drawBlock(col: i32, row: i32, color: [4]u8) void {
    const px = tilePx();
    const padding: f32 = @as(f32, @floatFromInt(gfx.window.cellpadding)) * 2.0;

    const x = @as(f32, @floatFromInt(col * px)) + padding;
    const y = @as(f32, @floatFromInt(row * px)) + padding;
    const size = @as(f32, @floatFromInt(px)) - padding * 2.0;

    const rect = ray.Rectangle{ .x = x, .y = y, .width = size, .height = size };

    const base_color = gfx.toRayColor(color);

    ray.DrawRectangleRounded(rect, 0.4, 20, base_color);
}

/// Create (once) a 4×4-block texture for the given tetromino.
fn makePieceTexture(t: pieces.tetramino) !*ray.RenderTexture2D {
    const tex_ptr = try std.heap.c_allocator.create(ray.RenderTexture2D);

    const size = piecePx();
    tex_ptr.* = ray.LoadRenderTexture(size, size);
    if (tex_ptr.*.id == 0) return error.TextureCreationFailed;

    ray.SetTextureFilter(tex_ptr.*.texture, ray.TEXTURE_FILTER_ANISOTROPIC_16X);

    // Draw blocks into the texture.
    ray.BeginTextureMode(tex_ptr.*);
    defer ray.EndTextureMode();

    // Fully transparent clear.
    ray.ClearBackground(ray.Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

    const shape = t.shape[0]; // only first rotation needed for drawing
    var row: usize = 0;
    while (row < shape.len) : (row += 1) {
        var col: usize = 0;
        while (col < shape[row].len) : (col += 1) {
            if (shape[row][col]) {
                drawBlock(@intCast(col), @intCast(row), t.color);
            }
        }
    }

    return tex_ptr;
}

fn createPieceTextures() !void {
    var i: usize = 0;
    while (i < pieces.tetraminos.len) : (i += 1) {
        piece_textures[i] = try makePieceTexture(pieces.tetraminos[i]);
    }
}

fn destroyPieceTextures() void {
    for (piece_textures) |tex_ptr| {
        ray.UnloadRenderTexture(tex_ptr.*);
        std.heap.c_allocator.destroy(tex_ptr);
    }
}

// ---------------------------------------------------------------------------
// Animation re-randomiser (called every few seconds)
// ---------------------------------------------------------------------------

const RESET_INTERVAL_MS: i64 = 3_000;

fn randomizeAllAnimations() void {
    const world = ecs.getWorld();
    var view = world.view(.{ components.Position, components.Sprite, components.Animation }, .{});
    var it = view.entityIterator();

    const rng = global_prng.random();

    const screen_w: f32 = @floatFromInt(ray.GetScreenWidth());
    const screen_h: f32 = @floatFromInt(ray.GetScreenHeight());
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
        const max_offset_x = screen_w * 1.5; // up to 2× screen dimension
        const max_offset_y = screen_h * 1.5;
        const offset_x = (rng.float(f32) * max_offset_x * 2.0) - max_offset_x;
        const offset_y = (rng.float(f32) * max_offset_y * 2.0) - max_offset_y;

        // Start small then expand massively (up to 10×)
        const size0 = 4.0 * (0.2 + rng.float(f32) * 0.6); // 0.8 – 3.2 block size
        // const size1 = 4.0 * (3.0 + rng.float(f32) * 1.0);
        sprite_ptr.size = size0;

        // Multi-spin rotation (several full turns)
        const rot0 = rng.float(f32) * 4.0;
        const rot1 = rot0 + ((rng.float(f32) * 6.0) - 3.0);
        sprite_ptr.rotation = rot0;

        const now_ms = std.time.milliTimestamp();
        anim_ptr.* = components.Animation{
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

// ---------------------------------------------------------------------------
// Spawning helpers
// ---------------------------------------------------------------------------

/// Spawn one tetromino sprite entity and attach an Animation component that
/// drives position, scale and rotation.
fn spawnAnimatedTetromino(rng: anytype) !void {
    const screen_w: f32 = @floatFromInt(ray.GetScreenWidth());
    const screen_h: f32 = @floatFromInt(ray.GetScreenHeight());

    // Random tetromino type ----------------------------------------------
    const t_index = rng.intRangeAtMost(usize, 0, pieces.tetraminos.len - 1);
    const tex_ptr = piece_textures[t_index];

    // Random starting top-left position (keep fully on-screen) -------------
    const piece_px_f: f32 = @floatFromInt(piecePx());
    const start_x = rng.float(f32) * (screen_w - piece_px_f);
    const start_y = rng.float(f32) * (screen_h - piece_px_f);

    // Random scale (-0.5‒1.5) and target scale (-0.5‒2.0) -------------------
    const scale0_blocks = (rng.float(f32) * 2.0) - 0.5; // Range from -0.5 to 1.5

    // Convert to sprite.size domain (1.0 == one cell) ----------------------
    const size0 = 4.0 * scale0_blocks;

    // Random rotations and duration ---------------------------------------
    const rot0 = rng.float(f32) * 2.0; // turns (0–2)
    const duration_ms: i64 = @intFromFloat(3000.0 + rng.float(f32) * 4000.0);

    // ---------------------------------------------------------------------
    const entity = ecs.createEntity();

    if (t_index == 4) {
        // try shaders.addShaderToEntity(entity, "static");
    }

    ecs.addOrReplace(components.Position, entity, components.Position{ .x = start_x, .y = start_y });

    // White tint so texture shows original colours.
    ecs.addOrReplace(components.Sprite, entity, components.Sprite{ .rgba = .{ 255, 255, 255, 255 }, .size = size0, .rotation = rot0 });

    ecs.addOrReplace(components.Texture, entity, components.Texture{
        .texture = tex_ptr,
        .uv = .{ 0.0, 0.0, 1.0, 1.0 },
        .created = false,
    });

    // Unified animation for the whole piece.
    const start_time = std.time.milliTimestamp();
    ecs.addOrReplace(components.Animation, entity, components.Animation{
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

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

pub fn main() !void {
    // ---- Basic init ------------------------------------------------------
    ecs.init();

    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT | ray.FLAG_WINDOW_RESIZABLE | ray.FLAG_MSAA_4X_HINT);

    ray.InitWindow(ray.GetScreenWidth(), ray.GetScreenHeight(), "Tetromino sprite benchmark");

    // Minimal window globals for helpers.
    gfx.window = gfx.Window{};
    gfx.window.width = ray.GetScreenWidth();
    gfx.window.height = ray.GetScreenHeight();
    gfx.window.cellsize = 35;
    gfx.window.cellpadding = 2;
    gfx.window.gridoffsetx = 10;
    gfx.window.gridoffsety = 10;

    // Initialize graphics system
    try gfx.init();

    // Pre-render the 7 piece textures
    try createPieceTextures();

    // ---- Spawn 5 000 animated tetrominos -------------------------------
    var seed: u64 = undefined;
    std.crypto.random.bytes(std.mem.asBytes(&seed));
    global_prng = std.Random.DefaultPrng.init(seed);
    const rng = global_prng.random();
    try shaders.init();

    const total_pieces: usize = 10000;
    var i: usize = 0;
    while (i < total_pieces) : (i += 1) {
        try spawnAnimatedTetromino(rng);
    }
    randomizeAllAnimations();
    // ---- Main loop -------------------------------------------------------
    var last_reset_ms: i64 = std.time.milliTimestamp();

    while (!ray.WindowShouldClose()) {
        ray.BeginDrawing();
        defer ray.EndDrawing();

        ray.ClearBackground(ray.BLACK);

        // Update & draw
        animsys.update();
        rendersys.draw();

        ray.DrawText("10 000 animated tetrominos", 100, 100, 20, ray.WHITE);
        ray.DrawFPS(10, 35);

        // periodically reset animations
        const now_ms = std.time.milliTimestamp();
        if (now_ms - last_reset_ms >= RESET_INTERVAL_MS) {
            randomizeAllAnimations();
            last_reset_ms = now_ms;
        }
    }

    // ---- Shutdown --------------------------------------------------------
    destroyPieceTextures();
    textures.deinit();
    ecs.deinit();
    ray.CloseWindow();
}
