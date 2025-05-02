const std = @import("std");
const ray = @import("raylib.zig");
const ecs = @import("ecs.zig");
const ecsroot = @import("ecs");
const components = @import("components.zig");
const rendersys = @import("systems/rendersys.zig");
const gfx = @import("gfx.zig");

// Pre-rendered textures for different block types
var block_textures: std.AutoHashMap([4]u8, ray.RenderTexture2D) = undefined;

// Initialize the texture system and pre-render common block textures
pub fn init() !void {
    block_textures = std.AutoHashMap([4]u8, ray.RenderTexture2D).init(std.heap.page_allocator);

    // Create standard block textures for common colors
    try createBlockTexture(&.{ 255, 0, 0, 255 }); // Red
    try createBlockTexture(&.{ 0, 255, 0, 255 }); // Green
    try createBlockTexture(&.{ 0, 0, 255, 255 }); // Blue
    try createBlockTexture(&.{ 255, 255, 0, 255 }); // Yellow
    try createBlockTexture(&.{ 255, 0, 255, 255 }); // Magenta
    try createBlockTexture(&.{ 0, 255, 255, 255 }); // Cyan
    try createBlockTexture(&.{ 255, 165, 0, 255 }); // Orange
    try createBlockTexture(&.{ 128, 0, 128, 255 }); // Purple
    try createBlockTexture(&.{ 255, 255, 255, 128 }); // Ghost piece (transparent white)
}

// Cleanup textures when done
pub fn deinit() void {
    var it = block_textures.valueIterator();
    while (it.next()) |texture| {
        ray.UnloadRenderTexture(texture.*);
    }
    block_textures.deinit();
}

// Create and cache a texture for a block with the given color
fn createBlockTexture(color_ptr: *const [4]u8) !void {
    const color = color_ptr.*;

    // Skip if this color already exists
    if (block_textures.contains(color)) {
        return;
    }

    // Texture size is twice the cell size for better quality when scaled/rotated
    const texture_size = gfx.window.cellsize * 2;

    // Create render texture
    const texture = ray.LoadRenderTexture(texture_size, texture_size);
    if (texture.id == 0) {
        return error.TextureCreationFailed;
    }

    // Set texture filtering mode for better scaling
    ray.SetTextureFilter(texture.texture, ray.TEXTURE_FILTER_BILINEAR);

    // Begin drawing to the render texture
    ray.BeginTextureMode(texture);
    {
        // Clear with transparent background
        ray.ClearBackground(ray.Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

        // Get block dimensions
        const padding = @as(f32, @floatFromInt(gfx.window.cellpadding)) * 2.0;
        const block_size = @as(f32, @floatFromInt(texture_size)) - padding * 2.0;

        // Create rectangle for the block
        const rect = ray.Rectangle{
            .x = padding,
            .y = padding,
            .width = block_size,
            .height = block_size,
        };

        // Draw a rounded rectangle
        const ray_color = ray.Color{
            .r = color[0],
            .g = color[1],
            .b = color[2],
            .a = color[3],
        };

        // Add a subtle gradient from center for 3D effect
        const dark_color = ray.Color{
            .r = @max(0, color[0] - 40),
            .g = @max(0, color[1] - 40),
            .b = @max(0, color[2] - 40),
            .a = color[3],
        };

        const light_color = ray.Color{
            .r = @min(255, color[0] + 20),
            .g = @min(255, color[1] + 20),
            .b = @min(255, color[2] + 20),
            .a = color[3],
        };

        // Draw subtle highlight along top edge
        const highlight_rect = ray.Rectangle{
            .x = padding + 2,
            .y = padding + 2,
            .width = block_size - 4,
            .height = block_size / 3,
        };
        ray.DrawRectangleRounded(highlight_rect, 0.4, 8, light_color);

        // Draw main block
        ray.DrawRectangleRounded(rect, 0.4, 20, ray_color);

        // Draw subtle shadow at bottom
        const shadow_rect = ray.Rectangle{
            .x = padding + 4,
            .y = padding + block_size - (block_size / 3) - 2,
            .width = block_size - 8,
            .height = block_size / 4,
        };
        ray.DrawRectangleRounded(shadow_rect, 0.3, 8, dark_color);

        // Add a slight inner border for definition
        const inner_rect = ray.Rectangle{
            .x = padding + 3,
            .y = padding + 3,
            .width = block_size - 6,
            .height = block_size - 6,
        };
        // Draw inner highlight border
        ray.DrawRectangleRoundedLines(inner_rect, 0.4, 20, ray.Color{ .r = light_color.r, .g = light_color.g, .b = light_color.b, .a = 100 });
    }
    ray.EndTextureMode();

    // Store in the hash map
    try block_textures.put(color, texture);
}

// Get a render texture for a specific color
// If the texture doesn't exist yet, it will be created
pub fn getBlockTexture(color: [4]u8) !ray.RenderTexture2D {
    // Check if we already have this color
    if (block_textures.get(color)) |texture| {
        return texture;
    }

    // Create the texture if it doesn't exist
    try createBlockTexture(&color);

    // Now it should exist
    return block_textures.get(color).?;
}

// Create a textured block entity
pub fn createTexturedBlockEntity(x: f32, y: f32, color: [4]u8, scale: f32, rotation: f32) !ecsroot.Entity {
    const entity = ecs.createEntity();

    // Add position and sprite components
    ecs.add(components.Position, entity, components.Position{
        .x = x,
        .y = y,
    });
    
    ecs.add(components.Sprite, entity, components.Sprite{
        .rgba = color,
        .size = scale,
        .rotation = rotation,
    });

    // Get or create the appropriate texture
    const texture = try getBlockTexture(color);

    // Add sprite texture component
    ecs.add(components.SpriteTexture, entity, components.SpriteTexture{
        .texture = texture,
        .created = false, // We don't want the entity to destroy the shared texture
    });

    return entity;
}
