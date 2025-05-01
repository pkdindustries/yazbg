const std = @import("std");
const ray = @import("raylib.zig");
const game = @import("game.zig");
const hud = @import("hud.zig");
const events = @import("events.zig");
const Grid = @import("grid.zig").Grid;
const ecs = @import("ecs.zig");
const ecsroot = @import("ecs");
const components = @import("components.zig");
const rendersys = @import("systems/rendersys.zig");
const animsys = @import("systems/animsys.zig");
const playersys = @import("systems/playersys.zig");
const animationSystem = animsys.animationSystem;
const playerSystem = playersys.playerSystem;

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
        ray.SetTextureFilter(self.texture.texture, ray.TEXTURE_FILTER_TRILINEAR);

        // Initialize font
        self.font = ray.LoadFont("resources/font/space.ttf");
        ray.GenTextureMipmaps(&self.font.texture);
        ray.SetTextureFilter(self.font.texture, ray.TEXTURE_FILTER_TRILINEAR);
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

    pub fn draw(self: *Background) void {
        // Apply the warp shader when drawing the background
        ray.BeginShaderMode(self.shader);

        // Source and destination rectangles
        const src = ray.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(self.texture[self.index].width), .height = @floatFromInt(self.texture[self.index].height) };
        const tgt = ray.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(Window.OGWIDTH), .height = @floatFromInt(Window.OGHEIGHT) };

        // Draw background texture with shader applied
        ray.DrawTexturePro(self.texture[self.index], src, tgt, ray.Vector2{ .x = 0, .y = 0 }, 0, ray.WHITE);
        ray.EndShaderMode();
    }
};

pub var window = Window{};
var background = Background{};
// Effect timer for visual effects like warp
var warp_end_ms: i64 = 0;
var dropIntervalMs: i64 = 0;
var level: u8 = 0;
// Static effect shader
var static: ray.Shader = undefined;
var statictimeloc: i32 = 0;

pub fn init() !void {
    std.debug.print("init gfx\n", .{});

    // Initialize window
    try window.init();

    // Load static effect shader for game elements
    static = ray.LoadShader(null, "resources/shader/static.fs");
    statictimeloc = ray.GetShaderLocation(static, "time");

    // Initialize background
    try background.init();

    // Initialize player system
    playersys.init();
}

pub fn deinit() void {
    std.debug.print("deinit gfx\n", .{});

    // Unload the static shader
    ray.UnloadShader(static);

    // Clean up window resources
    window.deinit();

    // Clean up background resources
    background.deinit();

    // Clean up player system
    playersys.deinit();
}

pub fn nextbackground() void {
    background.next();
}

// Update shader parameters before drawing
fn preshade() void {
    const current_time = @as(f32, @floatCast(ray.GetTime()));

    // Update time uniforms for both shaders
    ray.SetShaderValue(background.shader, background.secondsloc, &current_time, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(static, statictimeloc, &current_time, ray.SHADER_UNIFORM_FLOAT);

    // Set background warp parameters based on game state
    const now = std.time.milliTimestamp();
    if (warp_end_ms > now) {
        // Intense warp effect for special events
        background.freqx = 25.0;
        background.freqy = 25.0;
        background.ampx = 10.0;
        background.ampy = 10.0;
        background.speedx = 25.0;
        background.speedy = 25.0;
    } else {
        // Normal warp effect scaling with level
        background.freqx = 10.0;
        background.freqy = 10.0;
        background.ampx = 2.0;
        background.ampy = 2.0;
        background.speedx = 0.15 * (@as(f32, @floatFromInt(level)) + 2.0);
        background.speedy = 0.15 * (@as(f32, @floatFromInt(level)) + 2.0);
    }

    // Update all shader uniforms
    ray.SetShaderValue(background.shader, background.freqxloc, &background.freqx, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(background.shader, background.freqyloc, &background.freqy, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(background.shader, background.ampxloc, &background.ampx, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(background.shader, background.ampyloc, &background.ampy, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(background.shader, background.speedxloc, &background.speedx, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(background.shader, background.speedyloc, &background.speedy, ray.SHADER_UNIFORM_FLOAT);

    // Set screen size for shader
    const size = [2]f32{
        @floatFromInt(Window.OGWIDTH),
        @floatFromInt(Window.OGHEIGHT),
    };
    ray.SetShaderValue(background.shader, background.sizeloc, &size, ray.SHADER_UNIFORM_VEC2);
}

pub fn frame() void {
    // Handle window resizing
    window.updateScale();

    playerSystem();
    animationSystem(); // Process all animations (core animation system)
    // Update shader uniforms
    preshade();

    // Animation system now handled by ECS

    ray.BeginDrawing();
    {
        // Draw to render texture at original resolution
        ray.BeginTextureMode(window.texture);
        {
            // Draw background with warp effect
            background.draw();

            // Apply static effect shader to game elements
            ray.BeginShaderMode(static);
            rendersys.drawSprites();
            ray.EndShaderMode();

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
            }, static);
        }
        ray.EndTextureMode();

        // Scale render texture to actual window size
        window.drawScaled();
    }
    ray.EndDrawing();
}

pub fn process(queue: *events.EventQueue) void {
    const now = std.time.milliTimestamp();
    for (queue.items()) |rec| {
        switch (rec.event) {
            // Original event handlers
            .LevelUp => |newlevel| {
                background.next();
                level = newlevel;
            },
            .NextBackground => background.next(),
            .Clear => |lines| {
                const extra_ms: i64 = 120 * @as(i64, @intCast(lines));
                if (warp_end_ms < now + extra_ms) warp_end_ms = now + extra_ms;
            },
            .GameOver => {
                background.next();
                warp_end_ms = now + 300;
            },
            .Reset => reset(),
            .MoveLeft => playersys.move(1, 0),
            .MoveRight => playersys.move(-1, 0),
            .MoveDown => playersys.move(0, -1),
            .DropInterval => |ms| dropIntervalMs = ms,
            .Spawn => playersys.spawn(),

            else => {},
        }
    }
}

pub fn reset() void {
    background.index = 0;
    level = 0;
}
