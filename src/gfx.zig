const std = @import("std");
const ray = @import("raylib.zig");
const sfx = @import("sfx.zig");
const game = @import("game.zig");
const hud = @import("hud.zig");
const level = @import("level.zig");

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
    const Self = @This();
    path: [9][*:0]const u8 = .{
        "resources/texture/bluestars.png",
        "resources/texture/nebula.png",
        "resources/texture/starfield.png",
        "resources/texture/console.png",
        "resources/texture/bokefall.png",
        "resources/texture/nebula2.png",
        "resources/texture/warpgate.png",
        "resources/texture/starfield2.png",
        "resources/texture/starmap.png",
    },
    texture: [9]ray.Texture2D = undefined,
    index: u32 = 0,
    shader: ray.Shader = undefined,
    secondsloc: i32 = 0,
    freqxloc: i32 = 0,
    freqyloc: i32 = 0,
    ampxloc: i32 = 0,
    ampyloc: i32 = 0,
    speedxloc: i32 = 0,
    speedyloc: i32 = 0,
    sizeloc: i32 = 0,
    freqx: f32 = 10.0,
    freqy: f32 = 10.0,
    ampx: f32 = 2.0,
    ampy: f32 = 2.0,
    speedx: f32 = 0.25,
    speedy: f32 = 0.25,
};

var window = Window{};
var bg = Background{};

// Additional local effect timer to decouple from gameplay code.  Set by
// graphics‑only reactions (e.g. Clear/GameOver events) so we no longer need to
// mutate the game state from inside the renderer.
var warp_end_ms: i64 = 0;

// static shader
var static: ray.Shader = undefined;
var statictimeloc: i32 = 0;

pub fn frame() void {
    // resize
    updatescale();
    // shader uniforms
    preshade();
    ray.BeginDrawing();
    {
        // draw to texture first
        ray.BeginTextureMode(window.texture);
        {
            background();
            // static shader
            ray.BeginShaderMode(static);
            {
                // player piece and ghost
                player();
                // grid and animated
                drawcells();
            }
            ray.EndShaderMode();

            // draw the HUD
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
        // scale texture to window size
        const src = ray.Rectangle{ .x = 0, .y = 0, .width = Window.OGWIDTH, .height = -Window.OGHEIGHT };
        const tgt = ray.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(window.width), .height = @floatFromInt(window.height) };
        ray.DrawTexturePro(window.texture.texture, src, tgt, ray.Vector2{ .x = 0, .y = 0 }, 0, ray.WHITE);
    }
    ray.EndDrawing();
}

// -----------------------------------------------------------------------------
// Event handling – react to high‑level gameplay events that influence rendering
// but should not be triggered directly from game logic or main.zig.
// -----------------------------------------------------------------------------

const events = @import("events.zig");

/// Inspect the queued events and perform graphics‑related side effects.
/// Must be called once per frame.  Does NOT clear the queue – caller decides
/// when every subsystem has consumed the events.
pub fn process(queue: *events.EventQueue) void {
    // Currently we only react to a subset of events.  The switch statement is
    // kept exhaustive so the compiler reminds us when new events are added.
    const now = std.time.milliTimestamp();
    for (queue.items()) |e| switch (e) {
        .LevelUp => nextbackground(),
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
            nextbackground();
            warp_end_ms = now + 300;
        },
        // no‑op for the remaining events
        .Spawn, .Lock, .Hold, .Click, .Error, .Woosh, .Clack, .Win, .MoveLeft, .MoveRight, .MoveDown, .Rotate, .HardDrop, .SwapPiece, .Pause, .Reset => {},
    };
}

pub fn init() !void {
    std.debug.print("init gfx\n", .{});
    // window init
    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT | ray.FLAG_WINDOW_RESIZABLE);
    ray.InitWindow(Window.OGWIDTH, Window.OGHEIGHT, "yazbg");
    window.texture = ray.LoadRenderTexture(Window.OGWIDTH, Window.OGHEIGHT);
    //ray.GenTextureMipmaps(&texture.texture);
    ray.SetTextureFilter(window.texture.texture, ray.TEXTURE_FILTER_TRILINEAR);
    // background warp shader
    bg.shader = ray.LoadShader(null, "resources/shader/warp.fs");
    bg.secondsloc = ray.GetShaderLocation(bg.shader, "seconds");
    bg.freqxloc = ray.GetShaderLocation(bg.shader, "freqX");
    bg.freqyloc = ray.GetShaderLocation(bg.shader, "freqY");
    bg.ampxloc = ray.GetShaderLocation(bg.shader, "ampX");
    bg.ampyloc = ray.GetShaderLocation(bg.shader, "ampY");
    bg.speedxloc = ray.GetShaderLocation(bg.shader, "speedX");
    bg.speedyloc = ray.GetShaderLocation(bg.shader, "speedY");
    bg.sizeloc = ray.GetShaderLocation(bg.shader, "size");
    // block static shader
    static = ray.LoadShader(null, "resources/shader/static.fs");
    statictimeloc = ray.GetShaderLocation(static, "time");
    // font init
    window.font = ray.LoadFont("resources/font/nasa.otf");
    ray.GenTextureMipmaps(&window.font.texture);
    ray.SetTextureFilter(window.font.texture, ray.TEXTURE_FILTER_TRILINEAR);
    // load each of the images into an array of textures
    for (bg.path, 0..) |f, i| {
        var t = ray.LoadTexture(f);
        ray.GenTextureMipmaps(&t);
        ray.SetTextureFilter(t, ray.TEXTURE_FILTER_TRILINEAR);
        bg.texture[i] = t;
    }
    loadbackground();
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

pub fn loadbackground() void {
    ray.GenTextureMipmaps(&bg.texture[bg.index]);
    ray.SetTextureFilter(bg.texture[bg.index], ray.TEXTURE_FILTER_TRILINEAR);
}

pub fn nextbackground() void {
    bg.index += 1;
    if (bg.index >= bg.path.len) {
        bg.index = 0;
    }
    loadbackground();
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

// update shader stuff before draw call
fn preshade() void {
    ray.SetShaderValue(bg.shader, bg.secondsloc, &@as(f32, @floatCast(ray.GetTime())), ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(static, statictimeloc, &@as(f32, @floatCast(ray.GetTime())), ray.SHADER_UNIFORM_FLOAT);

    const now = std.time.milliTimestamp();
    if (warp_end_ms > now) {
        bg.freqx = 25.0;
        bg.freqy = 25.0;
        bg.ampx = 10.0;
        bg.ampy = 10.0;
        bg.speedx = 25;
        bg.speedy = 25;
    } else {
        bg.freqx = 10.0;
        bg.freqy = 10.0;
        bg.ampx = 2.0;
        bg.ampy = 2.0;
        bg.speedx = 0.15 * (@as(f32, @floatFromInt(level.progression.level)) + 2);
        bg.speedy = 0.15 * (@as(f32, @floatFromInt(level.progression.level)) + 2);
    }

    ray.SetShaderValue(bg.shader, bg.freqxloc, &bg.freqx, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(bg.shader, bg.freqyloc, &bg.freqy, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(bg.shader, bg.ampxloc, &bg.ampx, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(bg.shader, bg.ampyloc, &bg.ampy, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(bg.shader, bg.speedxloc, &bg.speedx, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(bg.shader, bg.speedyloc, &bg.speedy, ray.SHADER_UNIFORM_FLOAT);

    var size: [2]f32 = undefined;
    size[0] = @as(f32, @floatFromInt(Window.OGWIDTH));
    size[1] = @as(f32, @floatFromInt(Window.OGHEIGHT));
    ray.SetShaderValue(bg.shader, bg.sizeloc, &size, ray.SHADER_UNIFORM_VEC2);
}

fn background() void {
    ray.ClearBackground(ray.BLACK);
    ray.BeginShaderMode(bg.shader);

    const src = ray.Rectangle{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(bg.texture[bg.index].width),
        .height = @floatFromInt(bg.texture[bg.index].height),
    };

    const tgt = ray.Rectangle{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(Window.OGWIDTH),
        .height = @floatFromInt(Window.OGHEIGHT),
    };

    ray.DrawTexturePro(bg.texture[bg.index], src, tgt, ray.Vector2{ .x = 0, .y = 0 }, 0, ray.WHITE);
    ray.EndShaderMode();
}

fn player() void {
    if (game.state.piece.current) |p| {
        var drawX: i32 = game.state.piece.x * window.cellsize;
        var drawY: i32 = game.state.piece.y * window.cellsize;
        var fdrawx: f32 = @floatFromInt(drawX);
        var fdrawy: f32 = @floatFromInt(drawY);

        const elapsed_time = std.time.milliTimestamp() - game.state.piece.slider.start_time;
        // animate the piece if the slider is active
        if (game.state.piece.slider.active) {
            drawX = game.state.piece.slider.sourcex * window.cellsize;
            drawY = game.state.piece.slider.sourcey * window.cellsize;
            fdrawx = @floatFromInt(drawX);
            fdrawy = @floatFromInt(drawY);
            const duration: f32 = @floatFromInt(game.state.piece.slider.duration);
            const ratio: f32 = std.math.clamp(@as(f32, @floatFromInt(elapsed_time)) / duration, 0.0, 1.0);
            const targetx: f32 = @floatFromInt(game.state.piece.x * window.cellsize);
            const targety: f32 = @floatFromInt(game.state.piece.y * window.cellsize);
            // lerp between the current position and the target position
            fdrawx = std.math.lerp(fdrawx, targetx, ratio);
            fdrawy = std.math.lerp(fdrawy, targety, ratio);
            // deactivate slider, set position if animation is complete
            if (elapsed_time >= game.state.piece.slider.duration) {
                game.state.piece.slider.active = false;
                if (elapsed_time > game.state.piece.slider.duration + 5)
                    std.debug.print("slide {}ms\n", .{elapsed_time});
            }
        }

        const xdx: i32 = @intFromFloat(fdrawx);
        const ydx: i32 = @intFromFloat(fdrawy);
        // draw the piece at the interpolated position
        piece(xdx, ydx, p.shape[game.state.piece.r], p.color);

        // draw ghost
        const color = .{ p.color[0], p.color[1], p.color[2], 60 };
        piece(xdx, game.ghosty() * window.cellsize, p.shape[game.state.piece.r], color);
    }
}

fn drawcells() void {
    // find the active animatedcells
    inline for (game.state.grid.cells) |row| {
        for (row) |cell| {
            if (cell) |cptr| {
                cptr.lerp(std.time.milliTimestamp());
                const drawX: i32 = @as(i32, @intFromFloat(cptr.position[0]));
                const drawY: i32 = @as(i32, @intFromFloat(cptr.position[1]));
                roundedfillbox(drawX, drawY, cptr.color);
            } else {}
        }
    }

    game.state.grid.unattached.lerpall();
    inline for (game.state.grid.unattached.cells) |a| {
        if (a) |cptr| {
            const drawX: i32 = @as(i32, @intFromFloat(cptr.position[0]));
            const drawY: i32 = @as(i32, @intFromFloat(cptr.position[1]));
            roundedfillbox(drawX, drawY, cptr.color);
        }
    }
}

// draw a piece
fn piece(x: i32, y: i32, shape: [4][4]bool, color: [4]u8) void {
    for (shape, 0..) |row, i| {
        for (row, 0..) |cell, j| {
            if (cell) {
                const xs: i32 = @as(i32, @intCast(i)) * window.cellsize;
                const ys: i32 = @as(i32, @intCast(j)) * window.cellsize;
                roundedfillbox(x + xs, y + ys, color);
            }
        }
    }
}

// draw a rounded box (used internally by various rendering helpers within gfx)
fn roundedfillbox(x: i32, y: i32, color: [4]u8) void {
    ray.DrawRectangleRounded(ray.Rectangle{
        .x = @floatFromInt(window.gridoffsetx + x),
        .y = @floatFromInt(window.gridoffsety + y),
        .width = @floatFromInt(window.cellsize - 2 * window.cellpadding),
        .height = @floatFromInt(window.cellsize - 2 * window.cellpadding),
    }, 0.4, 20, ray.Color{
        .r = color[0],
        .g = color[1],
        .b = color[2],
        .a = color[3],
    });
}
