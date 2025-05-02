const std = @import("std");
const ray = @import("raylib.zig");
const ecs = @import("ecs.zig");
const ecsroot = @import("ecs");
const components = @import("components.zig");
const rendersys = @import("systems/rendersys.zig");
const gfx = @import("gfx.zig");

// Pre-rendered textures for different block types
// store heap alloc textures in a hash-map and share them between all entities.

var block_textures: std.AutoHashMap([4]u8, *ray.RenderTexture2D) = undefined;

// Initialize the texture system and pre-render common block textures
pub fn init() !void {
    block_textures = std.AutoHashMap([4]u8, *ray.RenderTexture2D).init(std.heap.page_allocator);

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
    while (it.next()) |value_ptr| {
        const tex_ptr = value_ptr.*; // Pointer to the actual texture
        ray.UnloadRenderTexture(tex_ptr.*);
        std.heap.c_allocator.destroy(tex_ptr);
    }
    block_textures.deinit();
}

// Create and cache a texture for a block with the given color
fn createBlockTexture(color_ptr: *const [4]u8) !void {
    const color = color_ptr.*;

    // Skip if this colour already has a cached texture.
    if (block_textures.contains(color))
        return;

    // ---------------------------------------------------------------------
    // Allocate a RenderTexture2D on the heap so its address remains stable
    // even if the hash-map itself grows and relocates its internal buffer.
    // ---------------------------------------------------------------------
    const tex_ptr = try std.heap.c_allocator.create(ray.RenderTexture2D);

    // Texture size is twice the cell size for better quality when scaled / rotated.
    const texture_size = gfx.window.cellsize * 2;

    tex_ptr.* = ray.LoadRenderTexture(texture_size, texture_size);
    if (tex_ptr.*.id == 0) {
        std.heap.c_allocator.destroy(tex_ptr);
        return error.TextureCreationFailed;
    }

    // Set texture filtering mode for better scaling
    ray.SetTextureFilter(tex_ptr.*.texture, ray.TEXTURE_FILTER_BILINEAR);

    // ---------------------------------------------------------------------
    // Render the rounded block into the texture.
    // ---------------------------------------------------------------------
    ray.BeginTextureMode(tex_ptr.*);
    {
        // Clear with a fully transparent background.
        ray.ClearBackground(ray.Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

        // Block dimensions inside the texture.
        const padding = @as(f32, @floatFromInt(gfx.window.cellpadding)) * 2.0;
        const block_size = @as(f32, @floatFromInt(texture_size)) - padding * 2.0;

        const rect = ray.Rectangle{
            .x = padding,
            .y = padding,
            .width = block_size,
            .height = block_size,
        };

        const ray_color = ray.Color{ .r = color[0], .g = color[1], .b = color[2], .a = color[3] };

        // A lighter tint used for a subtle top-edge highlight.
        const light_color = ray.Color{
            .r = @as(u8, @intCast(@min(255, @as(u16, color[0]) + 20))),
            .g = @as(u8, @intCast(@min(255, @as(u16, color[1]) + 20))),
            .b = @as(u8, @intCast(@min(255, @as(u16, color[2]) + 20))),
            .a = color[3],
        };

        const highlight_rect = ray.Rectangle{
            .x = padding + 2,
            .y = padding + 2,
            .width = block_size - 4,
            .height = block_size / 3,
        };

        ray.DrawRectangleRounded(highlight_rect, 0.4, 8, light_color);
        ray.DrawRectangleRounded(rect, 0.4, 20, ray_color);
    }
    ray.EndTextureMode();

    // Store the pointer in the hash-map.
    block_textures.put(color, tex_ptr) catch |err| {
        ray.UnloadRenderTexture(tex_ptr.*);
        std.heap.c_allocator.destroy(tex_ptr);
        return err;
    };
}

// Get a render texture for a specific color
// If the texture doesn't exist yet, it will be created
/// Retrieve a *pointer* to the cached render texture for the given colour. If
/// the texture does not yet exist it is created on-demand and its address is
/// returned.
pub fn getBlockTexture(color: [4]u8) !*const ray.RenderTexture2D {
    // If the texture is already cached simply return the pointer to it.
    if (block_textures.get(color)) |tex_ptr| {
        return tex_ptr;
    }

    // Otherwise create it, then fetch the pointer.
    try createBlockTexture(&color);
    return block_textures.get(color).?;
}

// Create a textured block entity
pub fn createTexturedSprite(x: f32, y: f32, color: [4]u8, scale: f32, rotation: f32) !ecsroot.Entity {
    const entity = ecs.createEntity();

    // Add position and sprite components
    ecs.addOrReplace(components.Position, entity, components.Position{
        .x = x,
        .y = y,
    });

    ecs.addOrReplace(components.Sprite, entity, components.Sprite{
        .rgba = color,
        .size = scale,
        .rotation = rotation,
    });

    // Get or create the appropriate texture and attach it to the entity.
    const texture_ptr = try getBlockTexture(color);

    ecs.addOrReplace(components.SpriteTexture, entity, components.SpriteTexture{
        .texture = texture_ptr,
        .created = false, // This is a shared cached texture.
    });

    return entity;
}

pub fn addTextureComponent(entity: ecsroot.Entity, color: [4]u8) !ecsroot.Entity {
    // Get or create the appropriate texture and attach it to the entity.
    const texture_ptr = try getBlockTexture(color);

    ecs.addOrReplace(components.SpriteTexture, entity, components.SpriteTexture{
        .texture = texture_ptr,
        .created = false, // This is a shared cached texture.
    });
    return entity;
}
