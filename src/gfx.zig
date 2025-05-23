const std = @import("std");
const builtin = @import("builtin");
const ray = @import("raylib.zig");
const events = @import("events.zig");
const ecs = @import("ecs.zig");
const ecsroot = @import("ecs");
const components = @import("components.zig");
const textures = @import("textures.zig");
const shaders = @import("shaders.zig");

// ---------------------------------------------------------------------------
// Layer System
// ---------------------------------------------------------------------------

pub const Layer = struct {
    name: []const u8,
    order: i32,              // Render order (lower = first)
    enabled: bool = true,    // Can toggle layers on/off
    
    // Lifecycle - init returns context, others receive it
    init: ?*const fn (allocator: std.mem.Allocator) anyerror!*anyopaque = null,
    deinit: ?*const fn (ctx: *anyopaque) void = null,
    
    // Called every frame
    update: ?*const fn (ctx: *anyopaque, dt: f32) void = null,
    render: *const fn (ctx: *anyopaque, rc: RenderContext) void,
    
    // Optional event handling  
    processEvent: ?*const fn (ctx: *anyopaque, event: events.Event) void = null,
    
    // Internal
    context: *anyopaque = undefined,
};

pub const RenderContext = struct {
    camera: ray.Camera2D,
    window_width: i32,
    window_height: i32,
    logical_width: i32,   // OGWIDTH
    logical_height: i32,  // OGHEIGHT  
    font: ray.Font,
    time: f32,           // Total elapsed time
};

// Layer comparison for sorting
fn layerLessThan(context: void, a: Layer, b: Layer) bool {
    _ = context;
    return a.order < b.order;
}

// Default cell size for compatibility with existing code
pub const DEFAULT_CELL_SIZE: i32 = 35;
pub const DEFAULT_CELL_PADDING: i32 = 2;
pub const DEFAULT_GRID_OFFSET_X: i32 = 165;
pub const DEFAULT_GRID_OFFSET_Y: i32 = 70;

pub const Window = struct {
    // Logical resolution of the off-screen render target (in pixels).
    // All coordinates in the game are expressed in this space.  We keep
    // those values unchanged so we do **not** have to touch any gameplay or
    // UI code when changing the internal rendering scale.
    pub const OGWIDTH: i32 = 640;
    pub const OGHEIGHT: i32 = 760;

    /// Render at a higher resolution than `OGWIDTH`×`OGHEIGHT` and scale the
    /// image down to the window size afterwards.  This acts like super-
    /// sampling and gives us crisper visuals (less aliasing) while keeping
    /// the window dimensions identical.
    pub const SCALE: i32 = 2; // <-- increase internal resolution by 2×
    width: i32 = OGWIDTH,
    height: i32 = OGHEIGHT,
    texture: ray.RenderTexture2D = undefined,
    font: ray.Font = undefined,
    drag_active: bool = false,
    
    // Layer management
    layers: std.ArrayList(Layer) = undefined,
    allocator: std.mem.Allocator = undefined,
    start_time: i64 = undefined,

    pub fn init(self: *Window, allocator: std.mem.Allocator) !void {
        // Initialize window
        ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT | ray.FLAG_WINDOW_RESIZABLE);
        ray.InitWindow(Window.OGWIDTH, Window.OGHEIGHT, "yazbg");

        // Calculate initial window size based on 65% of screen height
        const monitor_height = ray.GetMonitorHeight(0);
        const initial_height = @divTrunc(monitor_height * 65, 100); // 65% of screen height
        const initial_width = @divTrunc(initial_height * Window.OGWIDTH, Window.OGHEIGHT);
        ray.SetWindowSize(initial_width, initial_height);

        // Create render texture at higher resolution (super-sampling)
        self.texture = ray.LoadRenderTexture(
            Window.OGWIDTH * Window.SCALE,
            Window.OGHEIGHT * Window.SCALE,
        );
        ray.SetTextureFilter(self.texture.texture, ray.TEXTURE_FILTER_ANISOTROPIC_16X);

        // Initialize font
        self.font = ray.LoadFont("resources/font/space.ttf");
        ray.GenTextureMipmaps(&self.font.texture);
        ray.SetTextureFilter(self.font.texture, ray.TEXTURE_FILTER_ANISOTROPIC_16X);
        
        // Initialize layer system
        self.allocator = allocator;
        self.layers = std.ArrayList(Layer).init(allocator);
        self.start_time = std.time.milliTimestamp();
    }

    pub fn deinit(self: *Window) void {
        // Deinit layers in reverse order
        var i = self.layers.items.len;
        while (i > 0) : (i -= 1) {
            const layer = &self.layers.items[i - 1];
            if (layer.deinit) |deinitFn| {
                deinitFn(layer.context);
            }
        }
        self.layers.deinit();
        
        ray.UnloadTexture(self.texture.texture);
        ray.UnloadFont(self.font);
    }

    // Handle window resizing
    pub fn updateScale(self: *Window) void {
        if (ray.IsWindowResized()) {
            var width = ray.GetScreenWidth();
            var height = @divTrunc(width * Window.OGHEIGHT, Window.OGWIDTH);
            const maxheight = ray.GetMonitorHeight(0) - 100; // Assuming the primary monitor
            if (height > maxheight) {
                height = maxheight;
                width = @divTrunc(height * Window.OGWIDTH, Window.OGHEIGHT);
            }
            self.width = width;
            self.height = height;
            // std.debug.print("window resized to {}x{}\n", .{ self.width, self.height });
            ray.GenTextureMipmaps(&self.texture.texture);
            ray.SetWindowSize(width, height);
        }
    }

    // Update window drag state and position
    pub fn updateDrag(self: *Window) void {
        const DRAG_BAR_HEIGHT: f32 = 600.0;

        // Begin a new drag if the left button was just pressed inside the bar
        if (!self.drag_active and ray.IsMouseButtonPressed(ray.MOUSE_BUTTON_LEFT)) {
            const mouse = ray.GetMousePosition();
            if (mouse.y < DRAG_BAR_HEIGHT) {
                self.drag_active = true;
                _ = ray.GetMouseDelta();
            }
        }

        // Update the window position while the drag is active
        if (self.drag_active) {
            const delta = ray.GetMouseDelta();

            if (delta.x != 0 or delta.y != 0) {
                var win_pos = ray.GetWindowPosition();
                win_pos.x += delta.x;
                win_pos.y += delta.y;
                ray.SetWindowPosition(@as(i32, @intFromFloat(win_pos.x)), @as(i32, @intFromFloat(win_pos.y)));
            }

            // Stop the drag once the button is released
            if (!ray.IsMouseButtonDown(ray.MOUSE_BUTTON_LEFT)) {
                self.drag_active = false;
            }
        }
    }

    // Draw the scaled render texture to fit the current window size
    pub fn drawScaled(self: *Window) void {
        // Scale render texture (which is larger than OGWIDTH×OGHEIGHT) down
        // to the current window size.
        const src = ray.Rectangle{
            .x = 0,
            .y = 0,
            .width = @as(f32, @floatFromInt(self.texture.texture.width)),
            .height = -@as(f32, @floatFromInt(self.texture.texture.height)),
        };
        const tgt = ray.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(self.width), .height = @floatFromInt(self.height) };
        ray.DrawTexturePro(self.texture.texture, src, tgt, ray.Vector2{ .x = 0, .y = 0 }, 0, ray.WHITE);
    }
    
    // Layer management
    pub fn addLayer(self: *Window, layer: Layer) !void {
        var new_layer = layer;
        
        // Initialize layer if it has an init function
        if (new_layer.init) |initFn| {
            new_layer.context = try initFn(self.allocator);
        }
        
        try self.layers.append(new_layer);
        
        // Sort layers by order
        std.sort.heap(Layer, self.layers.items, {}, layerLessThan);
    }
    
    pub fn getLayer(self: *Window, name: []const u8) ?*Layer {
        for (self.layers.items) |*layer| {
            if (std.mem.eql(u8, layer.name, name)) {
                return layer;
            }
        }
        return null;
    }
    
    pub fn removeLayer(self: *Window, name: []const u8) void {
        var i: usize = 0;
        while (i < self.layers.items.len) {
            if (std.mem.eql(u8, self.layers.items[i].name, name)) {
                const layer = self.layers.orderedRemove(i);
                if (layer.deinit) |deinitFn| {
                    deinitFn(layer.context);
                }
            } else {
                i += 1;
            }
        }
    }
    
    // Update all layers
    fn updateLayers(self: *Window, dt: f32) void {
        for (self.layers.items) |*layer| {
            if (!layer.enabled) continue;
            if (layer.update) |updateFn| {
                updateFn(layer.context, dt);
            }
        }
    }
    
    // Process events for all layers
    pub fn processEvent(self: *Window, event: events.Event) void {
        for (self.layers.items) |*layer| {
            if (!layer.enabled) continue;
            if (layer.processEvent) |processFn| {
                processFn(layer.context, event);
            }
        }
    }
    
    // Render all layers
    fn renderLayers(self: *Window) void {
        const elapsed_ms = std.time.milliTimestamp() - self.start_time;
        const time = @as(f32, @floatFromInt(elapsed_ms)) / 1000.0;
        
        const rc = RenderContext{
            .camera = ray.Camera2D{
                .offset = ray.Vector2{ .x = 0, .y = 0 },
                .target = ray.Vector2{ .x = 0, .y = 0 },
                .rotation = 0,
                .zoom = @as(f32, @floatFromInt(Window.SCALE)),
            },
            .window_width = self.width,
            .window_height = self.height,
            .logical_width = Window.OGWIDTH,
            .logical_height = Window.OGHEIGHT,
            .font = self.font,
            .time = time,
        };
        
        ray.BeginMode2D(rc.camera);
        ray.ClearBackground(ray.BLACK);
        
        for (self.layers.items) |*layer| {
            if (!layer.enabled) continue;
            layer.render(layer.context, rc);
        }
        
        ray.EndMode2D();
    }
};

pub var window = Window{};

pub fn init(allocator: std.mem.Allocator) !void {
    std.debug.print("init gfx\n", .{});
    // Initialize window with layer system
    try window.init(allocator);
    // Initialize texture and shader systems
    try textures.init(allocator);
    try shaders.init(allocator);
}

pub fn deinit() void {
    // Clean up window resources (includes layers)
    window.deinit();
    
    // Clean up texture and shader systems
    textures.deinit();
    shaders.deinit();
}

pub fn frame(dt: f32) void {
    // Handle window resizing
    window.updateScale();
    
    // Update all enabled layers
    window.updateLayers(dt);

    ray.BeginDrawing();
    ray.BeginTextureMode(window.texture);
    
    // Render all enabled layers
    window.renderLayers();
    
    ray.EndTextureMode();
    
    // Scale render texture to actual window size
    window.drawScaled();
    ray.EndDrawing();
}

// Convert RGBA array to raylib Color
pub fn toRayColor(color: [4]u8) ray.Color {
    return ray.Color{
        .r = color[0],
        .g = color[1],
        .b = color[2],
        .a = color[3],
    };
}

// Creates a lighter version of the given color
pub fn createLighterColor(color: [4]u8, amount: u16) ray.Color {
    return ray.Color{
        .r = @as(u8, @intCast(@min(255, @as(u16, color[0]) + amount))),
        .g = @as(u8, @intCast(@min(255, @as(u16, color[1]) + amount))),
        .b = @as(u8, @intCast(@min(255, @as(u16, color[2]) + amount))),
        .a = color[3],
    };
}

// Calculate the center position of a cell in screen coordinates
// Convert rotation value (0.0 – 1.0) to degrees
pub fn rotationToDegrees(rotation: f32) f32 {
    return rotation * 360.0;
}

// Draw a texture with scaling and rotation.
pub fn drawTexture(
    x: f32,
    y: f32,
    texture: *const ray.RenderTexture2D,
    uv: [4]f32,
    tint: [4]u8,
    scale: f32,
    rotation: f32,
) void {

    // Calculate the scaled sprite size (width == height).
    const cellsize_scaled = @as(f32, @floatFromInt(DEFAULT_CELL_SIZE)) * scale;

    // Source rectangle (using UV coordinates).
    const texture_width = @as(f32, @floatFromInt(texture.*.texture.width));
    const texture_height = @as(f32, @floatFromInt(texture.*.texture.height));

    const src = ray.Rectangle{
        .x = uv[0] * texture_width,
        .y = (1.0 - uv[3]) * texture_height, // bottom-left origin in raylib
        .width = (uv[2] - uv[0]) * texture_width,
        .height = (uv[3] - uv[1]) * texture_height,
    };

    // Destination rectangle – top-left corner at (x, y).
    const dest = ray.Rectangle{
        .x = x,
        .y = y,
        .width = cellsize_scaled,
        .height = cellsize_scaled,
    };

    // Rotate around the centre of the sprite.
    const origin = ray.Vector2{
        .x = cellsize_scaled / 2.0,
        .y = cellsize_scaled / 2.0,
    };

    ray.DrawTexturePro(
        texture.*.texture,
        src,
        dest,
        origin,
        rotationToDegrees(rotation),
        toRayColor(tint),
    );
}

// Calculates normalized UV coordinates for a tile in the atlas
pub fn calculateUV(col: i32, row: i32, tile_size: i32, atlas_size: i32) [4]f32 {
    const mu0 = @as(f32, @floatFromInt(col * tile_size)) / @as(f32, @floatFromInt(atlas_size));
    const mv0 = @as(f32, @floatFromInt(row * tile_size)) / @as(f32, @floatFromInt(atlas_size));
    const mu1 = @as(f32, @floatFromInt((col + 1) * tile_size)) / @as(f32, @floatFromInt(atlas_size));
    const mv1 = @as(f32, @floatFromInt((row + 1) * tile_size)) / @as(f32, @floatFromInt(atlas_size));

    return .{ mu0, mv0, mu1, mv1 };
}
