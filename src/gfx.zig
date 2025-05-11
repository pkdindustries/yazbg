const std = @import("std");
const builtin = @import("builtin");
const ray = @import("raylib.zig");
const game = @import("game.zig");
const hud = @import("hud.zig");
const events = @import("events.zig");
const ecs = @import("ecs.zig");
const ecsroot = @import("ecs");
const components = @import("components.zig");
const rendersys = @import("systems/render.zig");
const animsys = @import("systems/anim.zig");
const playersys = @import("systems/player.zig");
const textures = @import("textures.zig");
const shaders = @import("shaders.zig");
const gridsvc = @import("systems/gridsvc.zig");

pub const Window = struct {
    pub const OGWIDTH: i32 = 640;
    pub const OGHEIGHT: i32 = 760;
    width: i32 = OGWIDTH,
    height: i32 = OGHEIGHT,
    texture: ray.RenderTexture2D = undefined,
    font: ray.Font = undefined,
    gridoffsetx: i32 = 150,
    gridoffsety: i32 = 50,
    cellsize: i32 = 35,
    cellpadding: i32 = 2,
    drag_active: bool = false,

    pub fn init(self: *Window) !void {
        // Initialize window
        ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT | ray.FLAG_WINDOW_RESIZABLE);
        ray.InitWindow(Window.OGWIDTH, Window.OGHEIGHT, "yazbg");

        // Create render texture for resolution independence
        self.texture = ray.LoadRenderTexture(Window.OGWIDTH, Window.OGHEIGHT);
        ray.SetTextureFilter(self.texture.texture, ray.TEXTURE_FILTER_ANISOTROPIC_16X);

        // Initialize font
        self.font = ray.LoadFont("resources/font/space.ttf");
        ray.GenTextureMipmaps(&self.font.texture);
        ray.SetTextureFilter(self.font.texture, ray.TEXTURE_FILTER_ANISOTROPIC_16X);
    }

    pub fn deinit(self: *Window) void {
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
            std.debug.print("window resized to {}x{}\n", .{ self.width, self.height });
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
        // Scale render texture to actual window size
        const src = ray.Rectangle{ .x = 0, .y = 0, .width = Window.OGWIDTH, .height = -Window.OGHEIGHT };
        const tgt = ray.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(self.width), .height = @floatFromInt(self.height) };
        ray.DrawTexturePro(self.texture.texture, src, tgt, ray.Vector2{ .x = 0, .y = 0 }, 0, ray.WHITE);
    }
};

pub const Background = struct {
    index: usize = 0,
    shader: ray.Shader = undefined,
    texture: [8]ray.Texture2D = undefined,

    // Shader uniform locations
    secondsloc: i32 = 0,
    freqxloc: i32 = 0,
    freqyloc: i32 = 0,
    ampxloc: i32 = 0,
    ampyloc: i32 = 0,
    speedxloc: i32 = 0,
    speedyloc: i32 = 0,
    sizeloc: i32 = 0,

    // Shader parameters
    freqx: f32 = 10.0,
    freqy: f32 = 10.0,
    ampx: f32 = 2.0,
    ampy: f32 = 2.0,
    speedx: f32 = 0.15,
    speedy: f32 = 0.15,

    // Store when warp effect should end
    warp_end_ms: i64 = 0,
    level: u8 = 0,

    pub fn init(self: *Background) !void {
        // Load background textures
        self.texture[0] = ray.LoadTexture("resources/texture/starfield.png");
        self.texture[1] = ray.LoadTexture("resources/texture/starfield2.png");
        self.texture[2] = ray.LoadTexture("resources/texture/nebula.png");
        self.texture[3] = ray.LoadTexture("resources/texture/nebula2.png");
        self.texture[4] = ray.LoadTexture("resources/texture/bluestars.png");
        self.texture[5] = ray.LoadTexture("resources/texture/bokefall.png");
        self.texture[6] = ray.LoadTexture("resources/texture/starmap.png");
        self.texture[7] = ray.LoadTexture("resources/texture/warpgate.png");

        // Load warp effect shader
        self.shader = ray.LoadShader(null, "resources/shader/warp.fs");

        // Get uniform locations
        self.secondsloc = ray.GetShaderLocation(self.shader, "seconds");
        self.freqxloc = ray.GetShaderLocation(self.shader, "freqX");
        self.freqyloc = ray.GetShaderLocation(self.shader, "freqY");
        self.ampxloc = ray.GetShaderLocation(self.shader, "ampX");
        self.ampyloc = ray.GetShaderLocation(self.shader, "ampY");
        self.speedxloc = ray.GetShaderLocation(self.shader, "speedX");
        self.speedyloc = ray.GetShaderLocation(self.shader, "speedY");
        self.sizeloc = ray.GetShaderLocation(self.shader, "size");
    }

    pub fn deinit(self: *Background) void {
        // Unload all textures
        for (self.texture) |texture| {
            ray.UnloadTexture(texture);
        }

        // Unload the shader
        ray.UnloadShader(self.shader);
    }

    pub fn next(self: *Background) void {
        self.index = (self.index + 1) % self.texture.len;
    }

    pub fn updateShader(self: *Background) void {
        const current_time = @as(f32, @floatCast(ray.GetTime()));

        // Update time uniform
        ray.SetShaderValue(self.shader, self.secondsloc, &current_time, ray.SHADER_UNIFORM_FLOAT);

        // Set background warp parameters based on game state
        const now = std.time.milliTimestamp();
        if (self.warp_end_ms > now) {
            // Intense warp effect for special events
            self.freqx = 25.0;
            self.freqy = 25.0;
            self.ampx = 10.0;
            self.ampy = 10.0;
            self.speedx = 25.0;
            self.speedy = 25.0;
        } else {
            // Normal warp effect scaling with level
            self.freqx = 10.0;
            self.freqy = 10.0;
            self.ampx = 2.0;
            self.ampy = 2.0;
            self.speedx = 0.15 * (@as(f32, @floatFromInt(self.level)) + 2.0);
            self.speedy = 0.15 * (@as(f32, @floatFromInt(self.level)) + 2.0);
        }

        // Update all shader uniforms
        ray.SetShaderValue(self.shader, self.freqxloc, &self.freqx, ray.SHADER_UNIFORM_FLOAT);
        ray.SetShaderValue(self.shader, self.freqyloc, &self.freqy, ray.SHADER_UNIFORM_FLOAT);
        ray.SetShaderValue(self.shader, self.ampxloc, &self.ampx, ray.SHADER_UNIFORM_FLOAT);
        ray.SetShaderValue(self.shader, self.ampyloc, &self.ampy, ray.SHADER_UNIFORM_FLOAT);
        ray.SetShaderValue(self.shader, self.speedxloc, &self.speedx, ray.SHADER_UNIFORM_FLOAT);
        ray.SetShaderValue(self.shader, self.speedyloc, &self.speedy, ray.SHADER_UNIFORM_FLOAT);

        // Set screen size for shader
        const size = [2]f32{
            @floatFromInt(Window.OGWIDTH),
            @floatFromInt(Window.OGHEIGHT),
        };
        ray.SetShaderValue(self.shader, self.sizeloc, &size, ray.SHADER_UNIFORM_VEC2);
    }

    pub fn setWarpEffect(self: *Background, duration_ms: i64) void {
        const now = std.time.milliTimestamp();
        if (self.warp_end_ms < now + duration_ms) {
            self.warp_end_ms = now + duration_ms;
        }
    }

    pub fn setLevel(self: *Background, new_level: u8) void {
        self.level = new_level;
    }

    pub fn reset(self: *Background) void {
        self.index = 0;
        self.level = 0;
    }

    pub fn draw(self: *Background) void {
        // // Apply the warp shader when drawing the background
        // ray.BeginShaderMode(self.shader);

        // Source and destination rectangles
        const src = ray.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(self.texture[self.index].width), .height = @floatFromInt(self.texture[self.index].height) };
        const tgt = ray.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(Window.OGWIDTH), .height = @floatFromInt(Window.OGHEIGHT) };

        // Draw background texture with shader applied
        ray.DrawTexturePro(self.texture[self.index], src, tgt, ray.Vector2{ .x = 0, .y = 0 }, 0, ray.WHITE);
        // ray.EndShaderMode();
    }
};

pub var window = Window{};
var background = Background{};

pub fn init() !void {
    std.debug.print("init gfx\n", .{});

    // Initialize window
    try window.init();
    // Initialize texture and shader systems
    try textures.init();
    try shaders.init();
    // Initialize background
    try background.init();

    // Initialize player system
    playersys.init();
}

pub fn deinit() void {
    std.debug.print("deinit gfx\n", .{});

    // Clean up window resources
    window.deinit();

    // Clean up background resources
    background.deinit();

    // Clean up player system
    playersys.deinit();

    // Clean up texture and shader systems
    textures.deinit();
    shaders.deinit();
}

pub fn nextbackground() void {
    background.next();
}

pub fn frame() void {
    // Handle window resizing
    window.updateScale();

    playersys.update();
    animsys.update();
    {
        ray.BeginDrawing();
        ray.BeginTextureMode(window.texture);
        {
            ray.ClearBackground(ray.BLACK);
            rendersys.drawSprites();

            // Draw HUD elements
            hud.draw(.{
                .gridoffsetx = window.gridoffsetx,
                .gridoffsety = window.gridoffsety,
                .cellsize = window.cellsize,
                .cellpadding = window.cellpadding,
                .font = window.font,
                .og_width = Window.OGWIDTH,
                .og_height = Window.OGHEIGHT,
                .next_piece = game.state.piece.next,
                .held_piece = game.state.piece.held,
            });
        }
        ray.EndTextureMode();

        // Scale render texture to actual window size
        window.drawScaled();
    }
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

/// Draw a texture with scaling and rotation.
pub fn drawTexture(
    x: i32,
    y: i32,
    texture: *const ray.RenderTexture2D,
    uv: [4]f32,
    tint: [4]u8,
    scale: f32,
    rotation: f32,
) void {

    // Calculate the scaled sprite size (width == height).
    const cellsize_scaled = @as(f32, @floatFromInt(window.cellsize)) * scale;

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
        .x = @as(f32, @floatFromInt(x)),
        .y = @as(f32, @floatFromInt(y)),
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

pub fn process(queue: *events.EventQueue) void {
    for (queue.items()) |rec| {
        switch (rec.event) {
            // Original event handlers
            .LevelUp => |newlevel| {
                background.setLevel(newlevel);
            },
            .NextBackground => background.next(),
            .Clear => |lines| {
                const extra_ms: i64 = 120 * @as(i64, @intCast(lines));
                background.setWarpEffect(extra_ms);
            },
            .GameOver => {
                background.next();
                background.setWarpEffect(300);
            },
            .Reset => background.reset(),

            .HardDropEffect => playersys.harddrop(),
            .Spawn => playersys.spawn(),

            // Position update events for player system
            .PlayerPositionUpdated => |update| {
                // Update player system state with the new position data
                playersys.updatePlayerPosition(update.x, update.y, update.rotation, update.ghost_y, update.piece_index);
            },

            // Grid service handling
            .PieceLocked => |data| {
                for (0..data.count) |i| {
                    const block = data.blocks[i];
                    gridsvc.occupyCell(block.x, block.y, block.color);
                }
            },
            .LineClearing => |data| {
                gridsvc.removeLineCells(data.y);
            },
            .RowsShiftedDown => |data| {
                // Handle row shifts from line clearing
                for (0..data.count) |i| {
                    gridsvc.shiftRowCells(data.start_y + i);
                }
            },
            .GridReset => gridsvc.clearAllCells(),
            else => {},
        }
    }
}
