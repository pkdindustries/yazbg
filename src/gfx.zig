const std = @import("std");
const ray = @import("raylib.zig");
const sfx = @import("sfx.zig");
const game = @import("game.zig");
const rnd = @import("random.zig");

const ogwindowwidth: i32 = 640;
const ogwindowheight: i32 = 760;
var windowwidth: i32 = ogwindowwidth;
var windowheight: i32 = ogwindowheight;
var gridoffsetx: i32 = 150;
var gridoffsety: i32 = 50;
var cellsize: i32 = 35;
var cellpadding: i32 = 2;
var scalefactor: f32 = 1.0;

const images: [4][*:0]const u8 = .{
    "resources/texture/bluestars.png",
    "resources/texture/nebula.png",
    "resources/texture/starfield.png",
    "resources/texture/bokefall.png",
};

var texture = ray.RenderTexture2D{};
var spacefont = ray.Font{};

// shader stuff
var bgshader: ray.Shader = undefined;
var bgtexture: ray.Texture2D = undefined;
var secondsloc: i32 = 0;
var freqXLoc: i32 = 0;
var freqYLoc: i32 = 0;
var ampXLoc: i32 = 0;
var ampYLoc: i32 = 0;
var speedXLoc: i32 = 0;
var speedYLoc: i32 = 0;
var sizeLoc: i32 = 0;
var freqX: f32 = 10.0;
var freqY: f32 = 10.0;
var ampX: f32 = 2.0;
var ampY: f32 = 2.0;
var speedX: f32 = 0.25;
var speedY: f32 = 0.25;

pub fn frame() void {
    // resize
    updatescale();
    // shader uniforms
    preshade();
    ray.BeginDrawing();
    // draw to texture first
    ray.BeginTextureMode(texture);
    // background and shader
    background();
    // player piece and ghost
    player();
    // grid of cemented cells
    grid();
    // animation for line clears
    lineclears();
    // ux
    ui();
    ray.EndTextureMode();
    // scale texture to window size
    const src = ray.Rectangle{ .x = 0, .y = 0, .width = ogwindowwidth, .height = -ogwindowheight };
    const tgt = ray.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(windowwidth), .height = @floatFromInt(windowheight) };

    ray.DrawTexturePro(texture.texture, src, tgt, ray.Vector2{ .x = 0, .y = 0 }, 0, ray.WHITE);
    ray.EndDrawing();
}

pub fn init() !void {
    std.debug.print("init gfx\n", .{});

    // window init
    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT | ray.FLAG_WINDOW_RESIZABLE);
    ray.InitWindow(ogwindowwidth, ogwindowheight, "yazbg");
    texture = ray.LoadRenderTexture(ogwindowwidth, ogwindowheight);
    //ray.GenTextureMipmaps(&texture.texture);
    ray.SetTextureFilter(texture.texture, ray.TEXTURE_FILTER_TRILINEAR);

    // shader init
    bgshader = ray.LoadShader(null, "resources/shader/warp.fs");
    secondsloc = ray.GetShaderLocation(bgshader, "seconds");
    freqXLoc = ray.GetShaderLocation(bgshader, "freqX");
    freqYLoc = ray.GetShaderLocation(bgshader, "freqY");
    ampXLoc = ray.GetShaderLocation(bgshader, "ampX");
    ampYLoc = ray.GetShaderLocation(bgshader, "ampY");
    speedXLoc = ray.GetShaderLocation(bgshader, "speedX");
    speedYLoc = ray.GetShaderLocation(bgshader, "speedY");
    sizeLoc = ray.GetShaderLocation(bgshader, "size");

    // font init
    spacefont = ray.LoadFont("resources/font/nasa.otf");
    ray.GenTextureMipmaps(&spacefont.texture);
    ray.SetTextureFilter(spacefont.texture, ray.TEXTURE_FILTER_TRILINEAR);
    randombackground();
}

pub fn deinit() void {
    std.debug.print("deinit gfx\n", .{});
    ray.UnloadShader(bgshader);
    ray.UnloadTexture(bgtexture);
    ray.UnloadTexture(texture.texture);
    ray.UnloadFont(spacefont);
}

// set random background
pub fn randombackground() void {
    ray.UnloadTexture(bgtexture);
    const i: u32 = rnd.ng.random().intRangeAtMost(u32, 0, images.len - 1);
    const f = images[i];
    bgtexture = ray.LoadTexture(f);
    ray.GenTextureMipmaps(&bgtexture);
    ray.SetTextureFilter(bgtexture, ray.TEXTURE_FILTER_TRILINEAR);
}

pub fn updatescale() void {
    if (ray.IsWindowResized()) {
        var width = ray.GetScreenWidth();
        var height = @divTrunc(width * ogwindowheight, ogwindowwidth);
        const maxheight = ray.GetMonitorHeight(0) - 100; // Assuming the primary monitor
        if (height > maxheight) {
            height = maxheight;
            width = @divTrunc(height * ogwindowwidth, ogwindowheight);
        }
        windowwidth = width;
        windowheight = height;
        std.debug.print("window resized to {}x{}\n", .{ windowwidth, windowheight });
        ray.GenTextureMipmaps(&texture.texture);
        ray.SetWindowSize(width, height);
    }
}

// update shader stuff before draw call
fn preshade() void {
    ray.SetShaderValue(bgshader, secondsloc, &@as(f32, @floatCast(ray.GetTime())), ray.SHADER_UNIFORM_FLOAT);

    // go wild during a clear
    if (game.state.lineclearer.active) {
        freqX = 50.0;
        freqY = 50.0;
        ampX = 10.0;
        ampY = 10.0;
        speedX = 200.5;
        speedY = 200.5;
    } else {
        freqX = 10.0;
        freqY = 10.0;
        ampX = 2.0;
        ampY = 2.0;
        speedX = 0.1 * (@as(f32, @floatFromInt(game.state.level)) + 1);
        speedY = 0.1 * (@as(f32, @floatFromInt(game.state.level)) + 1);
    }

    ray.SetShaderValue(bgshader, freqXLoc, &freqX, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(bgshader, freqYLoc, &freqY, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(bgshader, ampXLoc, &ampX, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(bgshader, ampYLoc, &ampY, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(bgshader, speedXLoc, &speedX, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(bgshader, speedYLoc, &speedY, ray.SHADER_UNIFORM_FLOAT);

    var size: [2]f32 = undefined;
    size[0] = @as(f32, @floatFromInt(ogwindowwidth));
    size[1] = @as(f32, @floatFromInt(ogwindowheight));
    ray.SetShaderValue(bgshader, sizeLoc, &size, ray.SHADER_UNIFORM_VEC2);
}

fn background() void {
    ray.ClearBackground(ray.BLACK);
    ray.BeginShaderMode(bgshader);

    const src = ray.Rectangle{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(bgtexture.width),
        .height = @floatFromInt(bgtexture.height),
    };

    const tgt = ray.Rectangle{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(ogwindowwidth),
        .height = @floatFromInt(ogwindowheight),
    };

    ray.DrawTexturePro(bgtexture, src, tgt, ray.Vector2{ .x = 0, .y = 0 }, 0, ray.WHITE);
    ray.EndShaderMode();
}

fn lineclears() void {
    const elapsed_time = std.time.milliTimestamp() - game.state.lineclearer.start_time;
    if (game.state.lineclearer.active) {
        for (game.state.lineclearer.lines, 0..) |clearing, rowIndex| {
            if (clearing) {
                for (0..10) |colIndex| {
                    // find underlying cell
                    const cell = game.state.cells[rowIndex][colIndex];
                    // skip if cell is empty (game over effect)
                    if (cell[3] == 0) {
                        continue;
                    }
                    const x = @as(i32, @intCast(colIndex)) * cellsize;
                    const y = @as(i32, @intCast(rowIndex)) * cellsize;
                    const e: f32 = @floatFromInt(elapsed_time);
                    const d: f32 = @floatFromInt(game.state.lineclearer.duration);
                    // clamp between 0 and 255
                    const computed = e / d * 200;
                    const clamped = std.math.clamp(computed, 0.0, 255.0);
                    const ratio: u8 = @intFromFloat(clamped);

                    const color = .{ cell[0], cell[1], cell[2], 255 - ratio };
                    roundedfillbox(x, y + ratio, color);
                }
            }
        }
        if (elapsed_time >= game.state.lineclearer.duration) {
            game.removelines();
            game.state.lineclearer.active = false;
            game.state.lineclearer.lines = undefined;
            if (elapsed_time > game.state.lineclearer.duration)
                std.debug.print("lineclear animation {}ms\n", .{elapsed_time});
        }
    }
}

fn player() void {
    if (game.state.piece) |p| {
        var drawX: i32 = game.state.piecex * cellsize;
        var drawY: i32 = game.state.piecey * cellsize;
        var fdrawx: f32 = @floatFromInt(drawX);
        var fdrawy: f32 = @floatFromInt(drawY);

        const elapsed_time = std.time.milliTimestamp() - game.state.pieceslider.start_time;
        // animate the piece if the slider is active
        if (game.state.pieceslider.active) {
            drawX = game.state.pieceslider.sourcex * cellsize;
            drawY = game.state.pieceslider.sourcey * cellsize;
            fdrawx = @floatFromInt(drawX);
            fdrawy = @floatFromInt(drawY);
            const duration: f32 = @floatFromInt(game.state.pieceslider.duration);
            const ratio: f32 = std.math.clamp(@as(f32, @floatFromInt(elapsed_time)) / duration, 0.0, 1.0);
            const targetx: f32 = @floatFromInt(game.state.pieceslider.targetx * cellsize);
            const targety: f32 = @floatFromInt(game.state.pieceslider.targety * cellsize);
            // lerp between the current position and the target position
            fdrawx = std.math.lerp(fdrawx, targetx, ratio);
            fdrawy = std.math.lerp(fdrawy, targety, ratio);
            // deactivate slider, set position if animation is complete
            if (elapsed_time >= game.state.pieceslider.duration) {
                game.state.pieceslider.active = false;
                if (elapsed_time > game.state.pieceslider.duration)
                    std.debug.print("slide {}ms\n", .{elapsed_time});
            }
        }

        const xdx: i32 = @intFromFloat(fdrawx);
        const ydx: i32 = @intFromFloat(fdrawy);

        // draw the piece at the interpolated position
        piece(xdx, ydx, p.shape[game.state.piecer], p.color);

        // draw ghost
        const color = .{ p.color[0], p.color[1], p.color[2], 60 };
        piece(xdx, game.ghosty() * cellsize, p.shape[game.state.piecer], color);
    }
}

// draw a piece
fn piece(x: i32, y: i32, shape: [4][4]bool, color: [4]u8) void {
    for (shape, 0..) |row, i| {
        for (row, 0..) |cell, j| {
            if (cell) {
                const xs: i32 = @as(i32, @intCast(i)) * cellsize;
                const ys: i32 = @as(i32, @intCast(j)) * cellsize;
                roundedfillbox(x + xs, y + ys, color);
            }
        }
    }
}

// draw a box
fn box(x: i32, y: i32, color: [4]u8) void {
    ray.DrawRectangleLinesEx(ray.Rectangle{
        .x = @floatFromInt(gridoffsetx + x),
        .y = @floatFromInt(gridoffsety + y),
        .width = @floatFromInt(getcellwidth()),
        .height = @floatFromInt(getcellwidth()),
    }, 2, ray.Color{
        .r = color[0],
        .g = color[1],
        .b = color[2],
        .a = color[3],
    });
}

// draw a filled box
fn fillbox(x: i32, y: i32, color: [4]u8) void {
    ray.DrawRectangle(gridoffsetx + x, gridoffsety + y, getcellwidth(), getcellwidth(), ray.Color{
        .r = color[0],
        .g = color[1],
        .b = color[2],
        .a = color[3],
    });
}

// draw a rounded box
fn roundedfillbox(x: i32, y: i32, color: [4]u8) void {
    ray.DrawRectangleRounded(ray.Rectangle{
        .x = @floatFromInt(gridoffsetx + x),
        .y = @floatFromInt(gridoffsety + y),
        .width = @floatFromInt(getcellwidth()),
        .height = @floatFromInt(getcellwidth()),
    }, 0.4, 20, ray.Color{
        .r = color[0],
        .g = color[1],
        .b = color[2],
        .a = color[3],
    });
}
// draw the cemented cells and border
fn grid() void {
    for (game.state.cells, 0..) |row, y| {
        if (game.state.lineclearer.active and game.state.lineclearer.lines[y]) {
            continue;
        }
        for (row, 0..) |color, x| {
            if (color[3] != 0) {
                const xx = @as(i32, @intCast(x)) * cellsize;
                const yy = @as(i32, @intCast(y)) * cellsize;
                roundedfillbox(xx, yy, color);
            }
        }
    }
}

fn getcellwidth() i32 {
    return cellsize - 2 * cellpadding;
}

var textbuf: [1000]u8 = undefined;
fn ui() void {
    ray.SetTextLineSpacing(22);
    const bordercolor = ray.Color{
        .r = 0,
        .g = 0,
        .b = 255,
        .a = 20,
    };
    ray.DrawRectangle(0, 0, 140, ogwindowheight, bordercolor);
    ray.DrawRectangle(ogwindowwidth - 135, 0, 135, ogwindowheight, bordercolor);

    ray.DrawLine(140, 0, 140, ogwindowheight, ray.RED);
    ray.DrawLine(ogwindowwidth - 135, 0, ogwindowwidth - 135, ogwindowheight, ray.RED);
    if (std.fmt.bufPrintZ(&textbuf, "score\n{}\nlines\n{}\nlevel\n{}", .{ game.state.score, game.state.lines, game.state.level })) |score| {
        var color = ray.GREEN;
        var size: f32 = 22;
        if (game.state.lineclearer.active) {
            scramblefx(score, 10);
            color = ray.RED;
            size = 30;
        }
        // var scoreheight = ray.MeasureTextEx(sys.spacefont, score, size, 3).y;
        // var scorey = @as(f32, @floatFromInt(windowheight)) - scoreheight * 2;
        ray.DrawTextEx(spacefont, score, ray.Vector2{ .x = 10, .y = 620 }, size, 3, color);
    } else |err| {
        std.debug.print("error printing score: {}\n", .{err});
    }

    ray.DrawTextEx(spacefont, "next", ray.Vector2{ .x = 520, .y = 30 }, 40, // font size
        2, // spacing
        ray.GRAY // color
    );
    if (game.state.nextpiece) |nextpiece| {
        piece(ogwindowwidth - 250, 35, nextpiece.shape[0], nextpiece.color);
    }

    ray.DrawTextEx(spacefont, "held", ray.Vector2{ .x = 23, .y = 30 }, 40, // font size
        2, // spacing
        ray.GRAY // color
    );
    if (game.state.heldpiece) |held| {
        piece(35 - gridoffsetx, 35, held.shape[0], held.color);
    }

    if (game.state.paused) {
        ray.DrawRectangle(0, 0, ogwindowwidth, ogwindowheight, ray.Color{
            .r = 0,
            .g = 0,
            .b = 0,
            .a = 210,
        });

        if (std.fmt.bufPrintZ(&textbuf, "PAUSED", .{})) |paused| {
            scramblefx(paused, 10);
            ray.DrawTextEx(spacefont, paused, ray.Vector2{ .x = 210, .y = 300 }, 60, 3, ray.ORANGE);
            ray.DrawText("press p to unpause", 220, 350, 20, ray.RED);
        } else |err| {
            std.debug.print("error printing paused: {}\n", .{err});
        }
    }

    if (game.state.gameover and !game.state.lineclearer.active) {
        ray.DrawRectangle(0, 0, ogwindowwidth, ogwindowheight, ray.Color{
            .r = 10,
            .g = 0,
            .b = 0,
            .a = 200,
        });

        if (std.fmt.bufPrintZ(&textbuf, "GAME OVER", .{})) |over| {
            scramblefx(over, 1);
            ray.DrawTextEx(spacefont, over, ray.Vector2{ .x = 145, .y = 290 }, 60, 3, ray.RED);
            ray.DrawText("r to restart", 255, 350, 20, ray.WHITE);
            ray.DrawText("esc to exit", 255, 375, 20, ray.WHITE);
        } else |err| {
            std.debug.print("error printing game over: {}\n", .{err});
        }
    }
}

const scrambles = "!@#$%^&*+-=<>?/\\|~`";
fn scramblefx(s: []u8, intensity: i32) void {
    for (s) |*c| {
        const n = scrambles[rnd.ng.random().intRangeAtMost(u32, 0, scrambles.len)];
        if (c.* == '\n' or c.* == ' ') {
            continue;
        }

        if (rnd.ng.random().intRangeAtMost(u32, 0, 100) > 100 - intensity) {
            c.* = n;
        }
    }
}
