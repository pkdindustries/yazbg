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

// Single texture atlas for all block colors
var block_atlas: ?ray.RenderTexture2D = null;
// UV coordinates for each block color in the atlas
var block_uvs: std.AutoHashMap([4]u8, [4]f32) = undefined;

// Initialize the texture system and pre-render common block textures
pub fn init() !void {
    block_textures = std.AutoHashMap([4]u8, *ray.RenderTexture2D).init(std.heap.page_allocator);
    block_uvs = std.AutoHashMap([4]u8, [4]f32).init(std.heap.page_allocator);

    // Standard block colors
    const colors = [_][4]u8{
        .{ 255, 0, 0, 255 }, // Red
        .{ 0, 255, 0, 255 }, // Green
        .{ 0, 0, 255, 255 }, // Blue
        .{ 255, 255, 0, 255 }, // Yellow
        .{ 255, 0, 255, 255 }, // Magenta
        .{ 0, 255, 255, 255 }, // Cyan
        .{ 255, 165, 0, 255 }, // Orange
        .{ 128, 0, 128, 255 }, // Purple
        .{ 255, 255, 255, 128 }, // Ghost piece (transparent white)
        .{ 220, 90, 220, 60 }, // Light purple (for the ghost piece)
        .{ 0, 121, 241, 60 }, // Light blue (for the ghost piece)
        .{ 0, 100, 44, 255 }, // Dark green
        .{ 255, 0, 0, 60 }, // Light red (for the ghost piece)
        .{ 0, 0, 0, 255 }, // Black
        .{ 0, 121, 241, 255 },
        .{ 0, 100, 44, 60 }, // Light green (for the ghost piece)
        .{ 255, 161, 0, 255 },
        .{ 255, 161, 0, 60 },
        .{ 220, 90, 220, 255 },
        .{ 102, 191, 235, 60 },
        .{ 233, 229, 0, 255 },
        // --- Additional piece colours that were missing from the atlas ---
        // I piece (cyan-ish)
        .{ 102, 191, 235, 255 },
        // Z piece (red)
        .{ 220, 41, 55, 255 },

        // Ghost variants for the above colours (alpha 60)
        .{ 233, 229, 0, 60 }, // Yellow – ghost
        .{ 220, 41, 55, 60 }, // Red – ghost
    };

    // Create the texture atlas
    try createTextureAtlas(colors[0..]);

    // For backward compatibility, also create individual textures
    for (colors) |color| {
        try createBlockTexture(&color);
    }
}

// Create a texture atlas containing all block textures in a 3x3 grid (256x256)
fn createTextureAtlas(colors: []const [4]u8) !void {
    // Create a 256x256 render texture
    const atlas_size = 256;

    // Determine grid dimensions so that every colour fits inside the atlas.
    // Create a square grid large enough to host `colors.len` cells.
    const grid_size = blk: {
        var gs: usize = 1;
        while (gs * gs < colors.len) : (gs += 1) {}
        break :blk gs;
    };

    // Calculate cell size in the atlas
    const cell_size = @divTrunc(atlas_size, @as(i32, @intCast(grid_size)));

    // Create the atlas render texture
    const atlas = ray.LoadRenderTexture(atlas_size, atlas_size);
    if (atlas.id == 0) {
        return error.TextureAtlasCreationFailed;
    }

    // Set texture filtering mode for better scaling
    ray.SetTextureFilter(atlas.texture, ray.TEXTURE_FILTER_BILINEAR);

    // Render each block texture into the atlas
    ray.BeginTextureMode(atlas);
    {
        // Clear with a fully transparent background
        ray.ClearBackground(ray.Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

        // Draw each block texture in its own cell
        for (colors, 0..) |color, i| {
            const row = @as(i32, @intCast(i / grid_size));
            const col = @as(i32, @intCast(i % grid_size));

            // Position in the atlas
            const x = col * cell_size;
            const y = row * cell_size;

            // Block dimensions inside each cell
            const padding = @as(f32, @floatFromInt(gfx.window.cellpadding)) * 2.0;
            const block_size = @as(f32, @floatFromInt(cell_size)) - padding * 2.0;

            const rect = ray.Rectangle{
                .x = @as(f32, @floatFromInt(x)) + padding,
                .y = @as(f32, @floatFromInt(y)) + padding,
                .width = block_size,
                .height = block_size,
            };

            const ray_color = ray.Color{ .r = color[0], .g = color[1], .b = color[2], .a = color[3] };

            // A lighter tint used for a subtle top-edge highlight
            const light_color = ray.Color{
                .r = @as(u8, @intCast(@min(255, @as(u16, color[0]) + 20))),
                .g = @as(u8, @intCast(@min(255, @as(u16, color[1]) + 20))),
                .b = @as(u8, @intCast(@min(255, @as(u16, color[2]) + 20))),
                .a = color[3],
            };

            const highlight_rect = ray.Rectangle{
                .x = @as(f32, @floatFromInt(x)) + padding + 2,
                .y = @as(f32, @floatFromInt(y)) + padding + 2,
                .width = block_size - 4,
                .height = block_size / 3,
            };

            ray.DrawRectangleRounded(highlight_rect, 0.4, 8, light_color);
            ray.DrawRectangleRounded(rect, 0.4, 20, ray_color);

            // Store UV coordinates for this color
            // UV coordinates are normalized in the 0.0-1.0 range
            const uv = [4]f32{
                @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(atlas_size)), // U1 (left)
                @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(atlas_size)), // V1 (top)
                @as(f32, @floatFromInt(x + cell_size)) / @as(f32, @floatFromInt(atlas_size)), // U2 (right)
                @as(f32, @floatFromInt(y + cell_size)) / @as(f32, @floatFromInt(atlas_size)), // V2 (bottom)
            };

            block_uvs.put(color, uv) catch |err| {
                ray.UnloadRenderTexture(atlas);
                return err;
            };
        }
    }
    ray.EndTextureMode();

    // Store the atlas
    block_atlas = atlas;
}

// Cleanup textures when done
pub fn deinit() void {
    // Unload individual textures
    var it = block_textures.valueIterator();
    while (it.next()) |value_ptr| {
        const tex_ptr = value_ptr.*; // Pointer to the actual texture
        ray.UnloadRenderTexture(tex_ptr.*);
        std.heap.c_allocator.destroy(tex_ptr);
    }
    block_textures.deinit();

    // Unload the texture atlas if it exists
    if (block_atlas) |atlas| {
        ray.UnloadRenderTexture(atlas);
        block_atlas = null;
    }

    // Deinit the UV coordinates map
    block_uvs.deinit();
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

// Get the texture atlas
// Returns a pointer to the shared atlas texture
pub fn getTextureAtlas() !*const ray.RenderTexture2D {
    if (block_atlas) |*atlas| {
        return atlas;
    }
    return error.TextureAtlasNotInitialized;
}

// Get UV coordinates for a specific color in the atlas
pub fn getBlockUV(color: [4]u8) ![4]f32 {
    if (block_uvs.get(color)) |uv| {
        return uv;
    }
    return error.ColorNotInAtlas;
}

// Create a textured block entity - Using individual textures (legacy)
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

    ecs.addOrReplace(components.Texture, entity, components.Texture{
        .texture = texture_ptr,
        .created = false, // This is a shared cached texture.
    });

    return entity;
}

// Create a textured block entity using the atlas with UV coordinates
pub fn createUVTexturedSprite(x: f32, y: f32, color: [4]u8, scale: f32, rotation: f32) !ecsroot.Entity {
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

    // Get the texture atlas and UV coordinates for the color
    const atlas_ptr = try getTextureAtlas();
    const uv = try getBlockUV(color);

    // Add UVTexture component
    ecs.addOrReplace(components.UVTexture, entity, components.UVTexture{
        .uv = uv,
        .texture = atlas_ptr,
        .created = false, // This is a shared atlas texture.
    });

    return entity;
}

pub fn addTextureComponent(entity: ecsroot.Entity, color: [4]u8) !ecsroot.Entity {
    // Get or create the appropriate texture and attach it to the entity.
    const texture_ptr = try getBlockTexture(color);

    ecs.addOrReplace(components.Texture, entity, components.Texture{
        .texture = texture_ptr,
        .created = false, // This is a shared cached texture.
    });
    return entity;
}

pub fn addUVTextureComponent(entity: ecsroot.Entity, color: [4]u8) !ecsroot.Entity {
    // Get the texture atlas and UV coordinates for the color
    const atlas_ptr = try getTextureAtlas();
    const uv = try getBlockUV(color);

    // Add UVTexture component
    ecs.addOrReplace(components.UVTexture, entity, components.UVTexture{
        .uv = uv,
        .texture = atlas_ptr,
        .created = false, // This is a shared atlas texture.
    });
    return entity;
}
