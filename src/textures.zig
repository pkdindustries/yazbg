const std = @import("std");
const ray = @import("raylib.zig");
const ecs = @import("ecs.zig");
const ecsroot = @import("ecs");
const components = @import("components.zig");
const gfx = @import("gfx.zig");

// Common type definitions
pub const Color = [4]u8;
pub const ColorRGBA = ray.Color;

// 0-1 (u0, v0, u1, v1) normalized texture coordinates.
// flipped to raylib's coordinate system by render
pub const UV = [4]f32;

pub const AtlasEntry = struct {
    tex: *const ray.RenderTexture2D, // texture atlas
    uv: UV, // normalised UV rect
};

const Page = struct {
    tex: *ray.RenderTexture2D, // heap
    next_tile: u16, // number of tiles  populated
};

// 16 × 16 tiles → 256 colors per page.
const TILES_PER_ROW = 16;
const TILES_PER_PAGE = TILES_PER_ROW * TILES_PER_ROW;

var tile_px: i32 = 0; // width / height of one tile in px
var atlas_px: i32 = 0; // width / height of one page in px

var pages: std.ArrayList(Page) = undefined;

// Hash-map key → entry (pointer to page texture + UV rectangle)
var texture_lut: std.StringHashMap(AtlasEntry) = undefined;

// Store allocator for future use
var allocator: std.mem.Allocator = undefined;

// needs gfx.window.cellsize
pub fn init(alloc: std.mem.Allocator) !void {
    allocator = alloc;
    tile_px = gfx.window.cellsize * 2; // match previous implementation
    atlas_px = tile_px * TILES_PER_ROW;

    pages = std.ArrayList(Page).init(allocator);
    texture_lut = std.StringHashMap(AtlasEntry).init(allocator);
}

// Unload all pages and free memory.
pub fn deinit() void {
    for (pages.items) |p| {
        ray.UnloadRenderTexture(p.tex.*);
        allocator.destroy(p.tex);
    }
    pages.deinit();
    texture_lut.deinit();
}

// Get an existing entry from the cache, doesn't create a new one
pub fn getEntry(key: []const u8) !AtlasEntry {
    if (texture_lut.get(key)) |entry| {
        return entry;
    }
    return error.EntryNotFound;
}

// Create a new entry using the provided draw function
pub fn createEntry(key: []const u8, draw_fn: DrawIntoTileFn, context: ?*const anyopaque) !AtlasEntry {
    // Check if it already exists first
    if (texture_lut.get(key)) |entry| {
        return entry;
    }

    try ensureEntry(key, draw_fn, context);
    // safe to unwrap after ensureEntry succeeds
    const entry = texture_lut.get(key).?;
    // std.debug.print("Created entry for key '{s}'\n", .{key});
    return entry;
}

fn ensureEntry(key: []const u8, draw_fn: DrawIntoTileFn, context: ?*const anyopaque) !void {
    if (texture_lut.contains(key)) return; // already cached

    // Obtain a page with free space or allocate a new one.
    if (pages.items.len == 0 or pages.items[pages.items.len - 1].next_tile == TILES_PER_PAGE) {
        try allocatePage();
    }

    const page_index = pages.items.len - 1;
    var page = &pages.items[page_index];

    const tile_index: u16 = page.next_tile;
    page.next_tile += 1;

    // Calculate tile position
    const col: i32 = @as(i32, @intCast(tile_index % TILES_PER_ROW));
    const row: i32 = @as(i32, @intCast(tile_index / TILES_PER_ROW));
    const tile_x = col * tile_px;
    const tile_y = row * tile_px;

    // Call the provided drawing function
    draw_fn(page.tex, tile_x, tile_y, tile_px, key, context);

    // normalized UV rectangle for the tile
    const uv = gfx.calculateUV(col, row, tile_px, atlas_px);

    // std.debug.print("Tile {}: col={}, row={}, UV=[{d:.6}, {d:.6}, {d:.6}, {d:.6}]\n", .{ tile_index, col, row, uv[0], uv[1], uv[2], uv[3] });

    const entry = AtlasEntry{
        .tex = page.tex,
        .uv = uv,
    };

    try texture_lut.put(key, entry);
}

// Allocates a new texture atlas page.
fn allocatePage() !void {
    const tex_ptr = try allocator.create(ray.RenderTexture2D);

    tex_ptr.* = ray.LoadRenderTexture(atlas_px, atlas_px);
    if (tex_ptr.*.id == 0) {
        // std.debug.print("ERROR: Failed to create render texture (atlas_px: {})\n", .{atlas_px});
        allocator.destroy(tex_ptr);
        return error.TextureCreationFailed;
    }

    // std.debug.print("Created new texture atlas page: id={}, size={}x{}\n", .{ tex_ptr.*.id, atlas_px, atlas_px });

    ray.SetTextureFilter(tex_ptr.*.texture, ray.TEXTURE_FILTER_ANISOTROPIC_16X);

    // reset
    ray.BeginTextureMode(tex_ptr.*);
    ray.ClearBackground(ray.Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
    ray.EndTextureMode();

    try pages.append(.{ .tex = tex_ptr, .next_tile = 0 });
}

// Function pointer type for drawing into a tile
pub const DrawIntoTileFn = fn (page_tex: *const ray.RenderTexture2D, tile_x: i32, tile_y: i32, tile_size: i32, key: []const u8, context: ?*const anyopaque) void;
