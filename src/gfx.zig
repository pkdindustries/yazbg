const std = @import("std");
const ray = @import("raylib.zig");
const game = @import("game.zig");
const hud = @import("hud.zig");
const events = @import("events.zig");
const Grid = @import("grid.zig").Grid;
const CellLayer = @import("cellrenderer.zig").CellLayer;
const AnimationState = @import("cellrenderer.zig").AnimationState;
const Animator = @import("animator.zig").Animator;

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
        ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT | ray.FLAG_WINDOW_RESIZABLE | ray.FLAG_VSYNC_HINT);
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

    pub fn load(self: *Background) void {
        _ = self; // This is just for semantic clarity - textures are already loaded
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

var window = Window{};
var background = Background{};

// Graphics state variables
// Effect timer for visual effects like warp
var warp_end_ms: i64 = 0;
var dropIntervalMs: i64 = 0;
var level: u8 = 0;
var animator: Animator = undefined;

// Static effect shader
var static: ray.Shader = undefined;
var statictimeloc: i32 = 0;

const PlayerPiece = struct {
    active: bool = false,
    start_time: i64 = 0,
    duration: i64 = 50, // ms
    sourcex: i32 = 0,
    sourcey: i32 = 0,
    targetx: i32 = 0,
    targety: i32 = 0,
    last_piece_x: i32 = 0,
    last_piece_y: i32 = 0,

    // Start a slide animation for the player piece
    pub fn move(self: *PlayerPiece, dx: i32, dy: i32) void {
        self.active = true;
        self.start_time = std.time.milliTimestamp();
        self.targetx = game.state.piece.x * window.cellsize;
        self.targety = game.state.piece.y * window.cellsize;
        self.sourcex = self.targetx + dx * window.cellsize;
        self.sourcey = self.targety + dy * window.cellsize;
    }

    // Draw the player piece and ghost preview
    pub fn draw(self: *PlayerPiece) void {
        if (game.state.piece.current) |p| {
            // Calculate base position in pixels
            const baseX = game.state.piece.x * window.cellsize;
            const baseY = game.state.piece.y * window.cellsize;

            // Start with base position
            var drawX: f32 = @floatFromInt(baseX);
            var drawY: f32 = @floatFromInt(baseY);

            // Apply animation if active
            if (self.active) {
                const elapsed_time = std.time.milliTimestamp() - self.start_time;
                const duration: f32 = @floatFromInt(self.duration);
                const progress: f32 = std.math.clamp(@as(f32, @floatFromInt(elapsed_time)) / duration, 0.0, 1.0);

                // Smoothly interpolate between source and target positions
                drawX = std.math.lerp(@as(f32, @floatFromInt(self.sourcex)), @as(f32, @floatFromInt(self.targetx)), progress);
                drawY = std.math.lerp(@as(f32, @floatFromInt(self.sourcey)), @as(f32, @floatFromInt(self.targety)), progress);

                // End animation when complete
                if (elapsed_time >= self.duration) {
                    self.active = false;
                }
            } else {
                // Update position tracking for next animation
                self.last_piece_x = game.state.piece.x;
                self.last_piece_y = game.state.piece.y;
            }

            // Convert back to integer coordinates for drawing
            const finalX = @as(i32, @intFromFloat(drawX));
            const finalY = @as(i32, @intFromFloat(drawY));

            // Draw the active piece
            drawpiece(finalX, finalY, p.shape[game.state.piece.r], p.color);

            // Draw ghost piece (semi-transparent preview at landing position)
            const ghostColor = .{ p.color[0], p.color[1], p.color[2], 60 };
            drawpiece(finalX, ghosty() * window.cellsize, p.shape[game.state.piece.r], ghostColor);
        }
    }
    pub fn ghosty() i32 {
        // Calculate the ghost position based on the current piece position
        var y = game.state.piece.y;
        while (game.checkmove(game.state.piece.x, y + 1)) : (y += 1) {}
        return y;
    }
};

var player: PlayerPiece = .{};

pub fn init() !void {
    std.debug.print("init gfx\n", .{});

    // Initialize window
    try window.init();

    // Load static effect shader for game elements
    static = ray.LoadShader(null, "resources/shader/static.fs");
    statictimeloc = ray.GetShaderLocation(static, "time");

    // Initialize background
    try background.init();

    // Initialize animator
    animator = try Animator.init(game.state.alloc, game.state.cells);
}

pub fn deinit() void {
    std.debug.print("deinit gfx\n", .{});

    // Unload the static shader
    ray.UnloadShader(static);

    // Clean up window resources
    window.deinit();

    // Clean up background resources
    background.deinit();

    // Clean up animator resources
    animator.deinit();
}

// These global functions now call the Background struct methods
pub fn loadbackground() void {
    background.load();
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

fn drawcells(layer: *CellLayer) void {
    // Iterate through all cells in the layer
    for (layer.cells, 0..) |cell, idx| {
        if (cell.anim_state) |anim| {
            // Draw animated cell
            const drawX = @as(i32, @intFromFloat(anim.position[0]));
            const drawY = @as(i32, @intFromFloat(anim.position[1]));
            drawbox(drawX, drawY, anim.color, anim.scale);
        } else if (cell.data) |logic| {
            // Draw static cell based on logical data
            const coords = layer.coordsFromIdx(idx);
            const drawX = @as(i32, @intCast(coords.x)) * window.cellsize;
            const drawY = @as(i32, @intCast(coords.y)) * window.cellsize;
            drawbox(drawX, drawY, logic.toRgba(), 1.0);
        }
    }
}

// Draw a tetromino piece
fn drawpiece(x: i32, y: i32, shape: [4][4]bool, color: [4]u8) void {
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

pub fn frame() void {
    // Handle window resizing
    window.updateScale();

    //window drag, if we want to fuck with an undecorated window
    //window.updateDrag();

    // Update shader uniforms
    preshade();

    // Update animations
    animator.step(0); // dt parameter isn't used since we're using timestamps

    ray.BeginDrawing();
    {
        // Draw to render texture at original resolution
        ray.BeginTextureMode(window.texture);
        {
            // Draw background with warp effect
            background.draw();

            // Apply static effect shader to game elements
            ray.BeginShaderMode(static);
            {
                // Draw player piece and ghost
                player.draw();

                // Draw grid cells
                drawcells(game.state.cells);
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
        window.drawScaled();
    }
    ray.EndDrawing();
}

// Explode all cells in a given row with flying animation
fn explodeRow(row: usize) void {
    // Create exploding animation for each cell in row
    for (0..Grid.WIDTH) |x| {
        const idx = game.state.cells.index(x, row);
        const cell_ptr = &game.state.cells.cells[idx];

        if (cell_ptr.data != null) {
            // Set random end position for explosion with much wider range
            const xr: f32 = -2000.0 + std.crypto.random.float(f32) * 4000.0;
            const yr: f32 = -2000.0 + std.crypto.random.float(f32) * 4000.0;

            // Get current position
            const x_pos = @as(f32, @floatFromInt(x * @as(usize, @intCast(window.cellsize))));
            const y_pos = @as(f32, @floatFromInt(row * @as(usize, @intCast(window.cellsize))));

            // Get current color
            const color = cell_ptr.data.?.toRgba();

            // Set up animation
            const anim_state = AnimationState{
                .source = .{ x_pos, y_pos },
                .target = .{ xr, yr },
                .position = .{ x_pos, y_pos },
                .scale = 1.0,
                .color_source = color,
                .color_target = .{ 0, 0, 0, 0 },
                .color = color,
                .startedat = std.time.milliTimestamp(),
                .duration = 1000,
                .mode = .easein,
                .animating = true,
            };

            // Start animation
            animator.startAnimation(idx, anim_state) catch {};
        }
    }
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
                // Prolong the background warp effect proportionally to the number
                // of lines removed so it is visible even when the grid animation
                // finishes very quickly.
                const extra_ms: i64 = 120 * @as(i64, @intCast(lines));
                if (warp_end_ms < now + extra_ms) warp_end_ms = now + extra_ms;
            },
            .GameOver => {
                // Immediately intensify the warp and pick a contrasting background
                // to highlight the end of the run.
                background.next();
                warp_end_ms = now + 300;

                // Create the line splat effect for all rows
                for (0..Grid.HEIGHT) |y| {
                    explodeRow(y);
                }
            },
            .Reset => reset(),
            .MoveLeft => player.move(1, 0),
            .MoveRight => player.move(-1, 0),
            .MoveDown => player.move(0, -1),
            // Drop interval tweaked by the level subsystem.
            .DropInterval => |ms| dropIntervalMs = ms,
            .Spawn => player.active = false,
            .Debug => {
                const active_count = animator.countActiveAnimations();
                std.debug.print("Active animations: {}\n", .{active_count});
                const total_count = game.state.cells.countTotalAnimations();
                std.debug.print("Total animations: {}\n", .{total_count});
            },
            .RowsShiftedDown => |shift_data| {
                const start_y = shift_data.start_y;
                const target_y = start_y + 1; // The row where we're moving cells to

                // Animate cells shifting down
                for (0..Grid.WIDTH) |x| {
                    const target_idx = game.state.cells.index(x, target_y);

                    // Only animate if there was data at the source position
                    // Check the target cell because the logical pos has already been moved
                    // by the grid.shiftrow() function
                    if (game.state.cells.ptr(x, target_y).data != null) {
                        // Get source and target positions
                        const source_x = @as(f32, @floatFromInt(x * @as(usize, @intCast(window.cellsize))));
                        const source_y = @as(f32, @floatFromInt(start_y * @as(usize, @intCast(window.cellsize))));
                        const target_y_pos = @as(f32, @floatFromInt(target_y * @as(usize, @intCast(window.cellsize))));
                        const color = game.state.cells.ptr(x, target_y).data.?.toRgba();

                        // Set up movement animation
                        const anim_state = AnimationState{
                            .source = .{ source_x, source_y },
                            .target = .{ source_x, target_y_pos },
                            .position = .{ source_x, source_y },
                            .scale = 1.0,
                            .color_source = color,
                            .color_target = color,
                            .color = color,
                            .startedat = std.time.milliTimestamp(),
                            .duration = 150,
                            .notbefore = std.time.milliTimestamp() + 100,
                            .mode = .easeout,
                            .animating = true,
                        };

                        // Start animation at the target position
                        animator.startAnimation(target_idx, anim_state) catch {};
                    }
                }
            },
            .GridReset => {
                // Stop all animations
                var idx: usize = 0;
                while (idx < animator.indices.items.len) {
                    animator.stopAnimation(animator.indices.items[idx]);
                    idx += 1;
                }
                animator.indices.clearRetainingCapacity();
            },
            else => {},
        }
    }
}

/// Reset graphics to first level state
pub fn reset() void {
    background.index = 0;
    level = 0;
    background.load();

    // Clear all animations
    var idx: usize = 0;
    while (idx < animator.indices.items.len) {
        animator.stopAnimation(animator.indices.items[idx]);
        idx += 1;
    }
    animator.indices.clearRetainingCapacity();
}
