const std = @import("std");
const ray = @import("raylib.zig");
const game = @import("game.zig");
const hud = @import("hud.zig");
const events = @import("events.zig");

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
};

pub const Background = struct {
    texture: [9]ray.Texture2D = undefined,
    index: u32 = 0,
    shader: ray.Shader = undefined,

    // Shader locations
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
    speedx: f32 = 0.25,
    speedy: f32 = 0.25,

    const paths = [_][*:0]const u8{
        "resources/texture/bluestars.png",
        "resources/texture/nebula.png",
        "resources/texture/starfield.png",
        "resources/texture/console.png",
        "resources/texture/bokefall.png",
        "resources/texture/nebula2.png",
        "resources/texture/warpgate.png",
        "resources/texture/starfield2.png",
        "resources/texture/starmap.png",
    };

    // Update current texture filtering
    pub fn load(self: *Background) void {
        ray.GenTextureMipmaps(&self.texture[self.index]);
        ray.SetTextureFilter(self.texture[self.index], ray.TEXTURE_FILTER_TRILINEAR);
    }

    // Cycle to next background texture
    pub fn next(self: *Background) void {
        self.index += 1;
        if (self.index >= paths.len) {
            self.index = 0;
        }
        self.load();
    }
};

var window = Window{};
var bg = Background{};

// Window dragging state and logic - currently disabled in frame()
var drag_active: bool = false;
fn updatedrag() void {
    const DRAG_BAR_HEIGHT: f32 = 600.0;

    // Begin a new drag if the left button was just pressed inside the bar
    if (!drag_active and ray.IsMouseButtonPressed(ray.MOUSE_BUTTON_LEFT)) {
        const mouse = ray.GetMousePosition();
        if (mouse.y < DRAG_BAR_HEIGHT) {
            drag_active = true;
            _ = ray.GetMouseDelta();
        }
    }

    // Update the window position while the drag is active
    if (drag_active) {
        const delta = ray.GetMouseDelta();

        if (delta.x != 0 or delta.y != 0) {
            var win_pos = ray.GetWindowPosition();
            win_pos.x += delta.x;
            win_pos.y += delta.y;
            ray.SetWindowPosition(@as(i32, @intFromFloat(win_pos.x)), @as(i32, @intFromFloat(win_pos.y)));
        }

        // Stop the drag once the button is released
        if (!ray.IsMouseButtonDown(ray.MOUSE_BUTTON_LEFT)) {
            drag_active = false;
        }
    }
}

// Graphics state variables
// Effect timer for visual effects like warp
var warp_end_ms: i64 = 0;
var dropIntervalMs: i64 = 0;
var level: u8 = 0;

// Static effect shader
var static: ray.Shader = undefined;
var statictimeloc: i32 = 0;

const Slide = struct {
    active: bool = false,
    start_time: i64 = 0,
    duration: i64 = 50, // ms
    sourcex: i32 = 0,
    sourcey: i32 = 0,
    targetx: i32 = 0,
    targety: i32 = 0,
};

var slide: Slide = .{};
var last_piece_x: i32 = 0;
var last_piece_y: i32 = 0;

pub fn frame() void {
    // Handle window resizing
    updatescale();

    // Update shader uniforms
    preshade();

    ray.BeginDrawing();
    {
        // Draw to render texture at original resolution
        ray.BeginTextureMode(window.texture);
        {
            // Draw background with warp effect
            background();

            // Apply static effect shader to game elements
            ray.BeginShaderMode(static);
            {
                // Draw player piece and ghost
                player();

                // Draw grid cells
                drawcells();
            }
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
        const src = ray.Rectangle{ .x = 0, .y = 0, .width = Window.OGWIDTH, .height = -Window.OGHEIGHT };
        const tgt = ray.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(window.width), .height = @floatFromInt(window.height) };
        ray.DrawTexturePro(window.texture.texture, src, tgt, ray.Vector2{ .x = 0, .y = 0 }, 0, ray.WHITE);
    }
    ray.EndDrawing();
}

pub fn process(queue: *events.EventQueue) void {
    const now = std.time.milliTimestamp();
    for (queue.items()) |rec| {
        switch (rec.event) {
            // Original event handlers
            .LevelUp => |newlevel| {
                bg.next();
                level = newlevel;
            },
            .NextBackground => bg.next(),
            .Clear => |lines| {
                // Prolong the background warp effect proportionally to the number
                // of lines removed so it is visible even when the grid animation
                // finishes very quickly.
                const extra_ms: i64 = 120 * @as(i64, @intCast(lines));
                if (warp_end_ms < now + extra_ms) warp_end_ms = now + extra_ms;
            },
            .GameOver => {
                // Immediately intensify the warp and pick a contrasting background
                // to highlight the end of the run.
                bg.next();
                warp_end_ms = now + 300;
            },
            .Reset => reset(),
            .MoveLeft => startSlide(1, 0),
            .MoveRight => startSlide(-1, 0),
            .MoveDown => startSlide(0, -1),
            // Drop interval tweaked by the level subsystem.
            .DropInterval => |ms| dropIntervalMs = ms,
            .Spawn => slide.active = false,
            
            // New event handlers for checkpoint #3
            .PieceLocked => |piece_data| {
                // Compatibility shim: spawn animations for the locked piece blocks
                // This will be implemented fully in checkpoint #5
                // For now, we're just acknowledging the event
                _ = piece_data;
            },
            .LineClearing => |row_data| {
                // Compatibility shim: start row fade animation
                // This will be implemented fully in checkpoint #5
                // For now, we're just acknowledging the event
                _ = row_data;
                
                // Note: Clear events should still work during transition
            },
            .RowsShiftedDown => |shift_data| {
                // Compatibility shim: handle rows shifted down
                // This will be implemented fully in checkpoint #5
                _ = shift_data;
            },
            .GridReset => {
                // Compatibility shim: handle grid reset
                // This will be implemented fully in checkpoint #5
            },
            else => {},
        }
    }
}

/// Reset graphics to first level state
pub fn reset() void {
    bg.index = 0;
    level = 0;
    bg.load();
}

fn startSlide(dx: i32, dy: i32) void {
    slide.active = true;
    slide.start_time = std.time.milliTimestamp();
    slide.targetx = game.state.piece.x * window.cellsize;
    slide.targety = game.state.piece.y * window.cellsize;
    slide.sourcex = slide.targetx + dx * window.cellsize;
    slide.sourcey = slide.targety + dy * window.cellsize;
}

pub fn init() !void {
    std.debug.print("init gfx\n", .{});

    // Initialize window
    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT | ray.FLAG_WINDOW_RESIZABLE | ray.FLAG_VSYNC_HINT);
    ray.InitWindow(Window.OGWIDTH, Window.OGHEIGHT, "yazbg");

    // Create render texture for resolution independence
    window.texture = ray.LoadRenderTexture(Window.OGWIDTH, Window.OGHEIGHT);
    ray.SetTextureFilter(window.texture.texture, ray.TEXTURE_FILTER_TRILINEAR);

    // Load and setup background warp shader
    bg.shader = ray.LoadShader(null, "resources/shader/warp.fs");
    bg.secondsloc = ray.GetShaderLocation(bg.shader, "seconds");
    bg.freqxloc = ray.GetShaderLocation(bg.shader, "freqX");
    bg.freqyloc = ray.GetShaderLocation(bg.shader, "freqY");
    bg.ampxloc = ray.GetShaderLocation(bg.shader, "ampX");
    bg.ampyloc = ray.GetShaderLocation(bg.shader, "ampY");
    bg.speedxloc = ray.GetShaderLocation(bg.shader, "speedX");
    bg.speedyloc = ray.GetShaderLocation(bg.shader, "speedY");
    bg.sizeloc = ray.GetShaderLocation(bg.shader, "size");

    // Load static effect shader for game elements
    static = ray.LoadShader(null, "resources/shader/static.fs");
    statictimeloc = ray.GetShaderLocation(static, "time");

    // Initialize font
    window.font = ray.LoadFont("resources/font/space.ttf");
    ray.GenTextureMipmaps(&window.font.texture);
    ray.SetTextureFilter(window.font.texture, ray.TEXTURE_FILTER_TRILINEAR);

    // Load background textures
    for (Background.paths, 0..) |path, i| {
        var texture = ray.LoadTexture(path);
        ray.GenTextureMipmaps(&texture);
        ray.SetTextureFilter(texture, ray.TEXTURE_FILTER_TRILINEAR);
        bg.texture[i] = texture;
    }

    bg.load();
}

pub fn deinit() void {
    std.debug.print("deinit gfx\n", .{});
    ray.UnloadShader(bg.shader);
    ray.UnloadShader(static);
    for (bg.texture) |t| {
        ray.UnloadTexture(t);
    }
    ray.UnloadTexture(window.texture.texture);
    ray.UnloadFont(window.font);
}

// These global functions now call the Background struct methods
pub fn loadbackground() void {
    bg.load();
}

pub fn nextbackground() void {
    bg.next();
}

pub fn updatescale() void {
    if (ray.IsWindowResized()) {
        var width = ray.GetScreenWidth();
        var height = @divTrunc(width * Window.OGHEIGHT, Window.OGWIDTH);
        const maxheight = ray.GetMonitorHeight(0) - 100; // Assuming the primary monitor
        if (height > maxheight) {
            height = maxheight;
            width = @divTrunc(height * Window.OGWIDTH, Window.OGHEIGHT);
        }
        window.width = width;
        window.height = height;
        std.debug.print("window resized to {}x{}\n", .{ window.width, window.height });
        ray.GenTextureMipmaps(&window.texture.texture);
        ray.SetWindowSize(width, height);
    }
}

// Update shader parameters before drawing
fn preshade() void {
    const current_time = @as(f32, @floatCast(ray.GetTime()));

    // Update time uniforms for both shaders
    ray.SetShaderValue(bg.shader, bg.secondsloc, &current_time, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(static, statictimeloc, &current_time, ray.SHADER_UNIFORM_FLOAT);

    // Set background warp parameters based on game state
    const now = std.time.milliTimestamp();
    if (warp_end_ms > now) {
        // Intense warp effect for special events
        bg.freqx = 25.0;
        bg.freqy = 25.0;
        bg.ampx = 10.0;
        bg.ampy = 10.0;
        bg.speedx = 25.0;
        bg.speedy = 25.0;
    } else {
        // Normal warp effect scaling with level
        bg.freqx = 10.0;
        bg.freqy = 10.0;
        bg.ampx = 2.0;
        bg.ampy = 2.0;
        bg.speedx = 0.15 * (@as(f32, @floatFromInt(level)) + 2.0);
        bg.speedy = 0.15 * (@as(f32, @floatFromInt(level)) + 2.0);
    }

    // Update all shader uniforms
    ray.SetShaderValue(bg.shader, bg.freqxloc, &bg.freqx, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(bg.shader, bg.freqyloc, &bg.freqy, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(bg.shader, bg.ampxloc, &bg.ampx, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(bg.shader, bg.ampyloc, &bg.ampy, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(bg.shader, bg.speedxloc, &bg.speedx, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(bg.shader, bg.speedyloc, &bg.speedy, ray.SHADER_UNIFORM_FLOAT);

    // Set screen size for shader
    const size = [2]f32{
        @floatFromInt(Window.OGWIDTH),
        @floatFromInt(Window.OGHEIGHT),
    };
    ray.SetShaderValue(bg.shader, bg.sizeloc, &size, ray.SHADER_UNIFORM_VEC2);
}

fn background() void {
    ray.ClearBackground(ray.BLACK);
    ray.BeginShaderMode(bg.shader);

    // Define source rectangle (entire texture)
    const src = ray.Rectangle{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(bg.texture[bg.index].width),
        .height = @floatFromInt(bg.texture[bg.index].height),
    };

    // Define target rectangle (entire window)
    const tgt = ray.Rectangle{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(Window.OGWIDTH),
        .height = @floatFromInt(Window.OGHEIGHT),
    };

    // Draw background texture with shader applied
    ray.DrawTexturePro(bg.texture[bg.index], src, tgt, ray.Vector2{ .x = 0, .y = 0 }, 0, ray.WHITE);

    ray.EndShaderMode();
}

fn player() void {
    if (game.state.piece.current) |p| {
        // Calculate base position in pixels
        const baseX = game.state.piece.x * window.cellsize;
        const baseY = game.state.piece.y * window.cellsize;

        // Start with base position
        var drawX: f32 = @floatFromInt(baseX);
        var drawY: f32 = @floatFromInt(baseY);

        // Apply animation if active
        if (slide.active) {
            const elapsed_time = std.time.milliTimestamp() - slide.start_time;
            const duration: f32 = @floatFromInt(slide.duration);
            const progress: f32 = std.math.clamp(@as(f32, @floatFromInt(elapsed_time)) / duration, 0.0, 1.0);

            // Smoothly interpolate between source and target positions
            drawX = std.math.lerp(@as(f32, @floatFromInt(slide.sourcex)), @as(f32, @floatFromInt(slide.targetx)), progress);
            drawY = std.math.lerp(@as(f32, @floatFromInt(slide.sourcey)), @as(f32, @floatFromInt(slide.targety)), progress);

            // End animation when complete
            if (elapsed_time >= slide.duration) {
                slide.active = false;
            }
        } else {
            // Update position tracking for next animation
            last_piece_x = game.state.piece.x;
            last_piece_y = game.state.piece.y;
        }

        // Convert back to integer coordinates for drawing
        const finalX = @as(i32, @intFromFloat(drawX));
        const finalY = @as(i32, @intFromFloat(drawY));

        // Draw the active piece
        piece(finalX, finalY, p.shape[game.state.piece.r], p.color);

        // Draw ghost piece (semi-transparent preview at landing position)
        const ghostColor = .{ p.color[0], p.color[1], p.color[2], 60 };
        piece(finalX, game.ghosty() * window.cellsize, p.shape[game.state.piece.r], ghostColor);
    }
}

fn drawcells() void {
    // This function needs to be reimplemented as part of checkpoint #5
    // We'll replace this with a temporary version that draws cells directly from cells_data
    
    const Grid = @import("grid.zig").Grid;
    
    // Draw static cells from data (temporary implementation)
    for (0..Grid.HEIGHT) |y| {
        for (0..Grid.WIDTH) |x| {
            if (game.state.grid.cells_data[y][x]) |cell_data| {
                const drawX = @as(i32, @intCast(x)) * window.cellsize;
                const drawY = @as(i32, @intCast(y)) * window.cellsize;
                
                // Draw the cell with the data color
                const rgba = cell_data.toRgba();
                drawbox(drawX, drawY, rgba, 1.0);
            }
        }
    }
    
    // TODO: In checkpoint #5, we'll implement animation management here
}

// Draw a tetromino piece
fn piece(x: i32, y: i32, shape: [4][4]bool, color: [4]u8) void {
    const scale: f32 = 1.0;

    for (shape, 0..) |row, i| {
        for (row, 0..) |cell, j| {
            if (cell) {
                const cellX = @as(i32, @intCast(i)) * window.cellsize;
                const cellY = @as(i32, @intCast(j)) * window.cellsize;
                drawbox(x + cellX, y + cellY, color, scale);
            }
        }
    }
}

// Draw a rounded box with scale factor applied
fn drawbox(x: i32, y: i32, color: [4]u8, scale: f32) void {
    // Calculate scaled dimensions
    const cellsize_scaled = @as(f32, @floatFromInt(window.cellsize)) * scale;
    const padding_scaled = @as(f32, @floatFromInt(window.cellpadding)) * scale;
    const width_scaled = cellsize_scaled - 2 * padding_scaled;

    // Calculate center of cell in screen coordinates
    const center_x = @as(f32, @floatFromInt(window.gridoffsetx + x)) +
        @as(f32, @floatFromInt(window.cellsize)) / 2.0;
    const center_y = @as(f32, @floatFromInt(window.gridoffsety + y)) +
        @as(f32, @floatFromInt(window.cellsize)) / 2.0;

    // Calculate top-left drawing position
    const rect_x = center_x - width_scaled / 2.0;
    const rect_y = center_y - width_scaled / 2.0; // Width used for height to ensure square

    // Draw rounded rectangle
    ray.DrawRectangleRounded(ray.Rectangle{
        .x = rect_x,
        .y = rect_y,
        .width = width_scaled,
        .height = width_scaled, // Same as width for perfect square
    }, 0.4, // Roundness
        20, // Segments
        ray.Color{
            .r = color[0],
            .g = color[1],
            .b = color[2],
            .a = color[3],
        });
}
