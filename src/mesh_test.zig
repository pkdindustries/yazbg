//! Minimal standalone executable to exercise the Mesh2D rendering path.
//!
//! It sets up:
//!   * raylib window
//!   * global gfx.window (required by textures and renderer helpers)
//!   * ECS world
//!   * texture atlas system (textures.zig)
//!   * single entity with Mesh2D component (textured quad)
//!
//! The render loop just invokes the existing `render.drawSprites()` so we
//! end-to-end test the same path used by the main game, while keeping the
//! surrounding code to an absolute minimum.

const std = @import("std");
const ray = @import("raylib.zig");
const ecs = @import("ecs.zig");
const ecsroot = @import("ecs");
const components = @import("components.zig");
const textures = @import("textures.zig");
const rendersys = @import("systems/render.zig");
const gfx = @import("gfx.zig");

// ---------------------------------------------------------------------------
// Mesh data (static)
// ---------------------------------------------------------------------------

// Simple quad from 0,0 to 1,1 rather than centered at origin
// Makes position math easier and more predictable
var quad_vertices: [4]components.Vertex2D = .{
    .{ .pos = .{ 0.0, 0.0 }, .uv = .{ 0.0, 0.0 } }, // top-left
    .{ .pos = .{ 1.0, 0.0 }, .uv = .{ 0.0, 0.0 } }, // top-right
    .{ .pos = .{ 1.0, 1.0 }, .uv = .{ 0.0, 0.0 } }, // bottom-right
    .{ .pos = .{ 0.0, 1.0 }, .uv = .{ 0.0, 0.0 } }, // bottom-left
};

const quad_indices = [_]u16{ 0, 1, 2, 0, 2, 3 };

// ---------------------------------------------------------------------------
// Helper: create one coloured block entity rendered via Mesh2D.
// ---------------------------------------------------------------------------

fn createMeshEntity(color: [4]u8) !void {
    // Request (or lazily generate) a tile in the atlas for this colour.
    const entry = try textures.getEntry(color);

    std.debug.print("Got texture entry with id: {}, UV: [{d}, {d}, {d}, {d}]\n", .{ entry.tex.*.texture.id, entry.uv[0], entry.uv[1], entry.uv[2], entry.uv[3] });

    // Fill the quad's UVs with the atlas coordinates (same order as vertices).
    // entry.uv = [u0, v0, u1, v1] using top-left origin in our convention.
    quad_vertices[0].uv = .{ entry.uv[0], entry.uv[1] }; // TL
    quad_vertices[1].uv = .{ entry.uv[2], entry.uv[1] }; // TR
    quad_vertices[2].uv = .{ entry.uv[2], entry.uv[3] }; // BR
    quad_vertices[3].uv = .{ entry.uv[0], entry.uv[3] }; // BL

    // Debug: print all vertices
    for (quad_vertices, 0..) |v, i| {
        std.debug.print("Vertex {}: pos=[{d}, {d}], uv=[{d}, {d}]\n", .{ i, v.pos[0], v.pos[1], v.uv[0], v.uv[1] });
    }

    const entity = ecs.createEntity();

    // Position it more in the upper left for better visibility alongside our debug elements
    ecs.addOrReplace(components.Position, entity, components.Position{
        .x = 50.0, // Upper left position to make it clearly visible
        .y = 50.0,
    });

    // Use a more sensible size with tint that shows the texture properly
    ecs.addOrReplace(components.Sprite, entity, components.Sprite{
        .rgba = .{ 255, 100, 100, 255 }, // Reddish tint to match the block color
        .size = 5.0, // reasonable size that doesn't overwhelm the screen
        .rotation = 0.0,
    });

    ecs.addOrReplace(components.Mesh2D, entity, components.Mesh2D{
        .vertices = &quad_vertices,
        .indices = &quad_indices,
        .texture = entry.tex,
    });

    std.debug.print("Created entity with ID: {}\n", .{entity});
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

pub fn main() !void {
    std.debug.print("Entering main()...\n", .{});
    // ---- System initialisation ----
    ecs.init();

    // Basic window / raylib setup (no resolution-independent back-buffer – we
    // don't need the extra indirection for this test).
    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT | ray.FLAG_WINDOW_RESIZABLE);
    ray.InitWindow(700, 500, "Mesh2D path test");

    // Minimal initialisation of globals used by utility functions.
    // Initialise the global window state with defaults then tweak only the
    // fields relevant to the renderer/texture helpers. Avoid the heavyweight
    // font/RenderTexture setup performed by gfx.Window.init() – they are not
    // needed for this micro-test.
    gfx.window = gfx.Window{};
    gfx.window.width = 700;
    gfx.window.height = 500;
    gfx.window.cellsize = 35;
    gfx.window.cellpadding = 2;
    gfx.window.gridoffsetx = 0;
    gfx.window.gridoffsety = 0;

    // Texture atlas system depends on window.cellsize.
    try textures.init();

    // Create several test blocks with different colors to test mesh rendering
    try createMeshEntity(.{ 255, 0, 0, 255 }); // Red - should be clearly visible

    // Create a second entity at a different position so we can verify multiple meshes work
    const entity2 = ecs.createEntity();
    ecs.addOrReplace(components.Position, entity2, components.Position{
        .x = 200.0,
        .y = 200.0,
    });
    ecs.addOrReplace(components.Sprite, entity2, components.Sprite{
        .rgba = .{ 100, 100, 255, 255 }, // Bluish tint to match the block color
        .size = 5.0, // reasonable size that doesn't overwhelm the screen
        .rotation = 0.0,
    });

    // Try with blue for the second mesh
    const entry2 = try textures.getEntry(.{ 0, 0, 255, 255 });
    ecs.addOrReplace(components.Mesh2D, entity2, components.Mesh2D{
        .vertices = &quad_vertices,
        .indices = &quad_indices,
        .texture = entry2.tex,
    });

    // Add a debug message to confirm entity creation
    std.debug.print("Entity created successfully!\n", .{});

    std.debug.print("Created entities: Mesh2D count = {}\n", .{ecs.getWorld().len(components.Mesh2D)});
    // ---- Main loop ----
    // Create render texture for consistent rendering with main game
    const render_texture = ray.LoadRenderTexture(gfx.window.width, gfx.window.height);
    defer ray.UnloadRenderTexture(render_texture);

    while (!ray.WindowShouldClose()) {
        ray.BeginDrawing();

        // First render to texture (like main game does)
        ray.BeginTextureMode(render_texture);
        {
            // Clear with dark gray instead of black for better visibility of meshes
            ray.ClearBackground(ray.DARKGRAY);

            // Draw all ECS entities via the existing renderer.
            rendersys.drawSprites();

            // Draw debug info on screen
            ray.DrawText("Mesh2D test – press ESC to quit", 10, 10, 20, ray.WHITE);

            // Draw FPS counter at the top
            ray.DrawFPS(10, 70);
        }
        ray.EndTextureMode();

        // Draw the render texture with y-axis flipped
        const src = ray.Rectangle{ .x = 0, .y = 0, .width = @as(f32, @floatFromInt(render_texture.texture.width)), .height = -@as(f32, @floatFromInt(render_texture.texture.height)) };
        const dest = ray.Rectangle{ .x = 0, .y = 0, .width = @as(f32, @floatFromInt(gfx.window.width)), .height = @as(f32, @floatFromInt(gfx.window.height)) };
        ray.DrawTexturePro(render_texture.texture, src, dest, ray.Vector2{ .x = 0, .y = 0 }, 0, ray.WHITE);

        ray.EndDrawing();
    }

    // ---- Shutdown ----
    textures.deinit();
    ecs.deinit();
    ray.CloseWindow();
}
