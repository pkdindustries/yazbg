const std = @import("std");
const ray = @import("raylib.zig");
const sys = @import("system.zig");
const game = @import("game.zig");

pub var windowwidth: i32 = 640;
pub var windowheight: i32 = 760;
pub var gridoffsetx: i32 = 150;
pub var gridoffsety: i32 = 50;
pub const cellsize: i32 = 35;
pub const cellpadding: i32 = 1;
pub const cellwidth: i32 = cellsize - 2 * cellpadding;
pub const totalgridwidth: i32 = game.grid_cols * cellsize + 2 * gridoffsetx;
pub var scalefactor: f32 = 1.0; // Default scale factor

pub const backgrounds: [5][*:0]const u8 = .{
    "resources/texture/bluestars.png",
    "resources/texture/nebula.png",
    "resources/texture/starfall.png",
    "resources/texture/starfield.png",
    "resources/texture/bokefall.png",
};

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
    updatescale();
    preshade();
    ray.BeginDrawing();
    background();
    player();
    grid();
    lineclears();
    ui();
    ray.EndDrawing();
}

pub fn init() !void {
    std.debug.print("init gfx\n", .{});
    bgshader = ray.LoadShader(null, "resources/shader/warp.fs");
    randombackground();
    secondsloc = ray.GetShaderLocation(bgshader, "seconds");
    freqXLoc = ray.GetShaderLocation(bgshader, "freqX");
    freqYLoc = ray.GetShaderLocation(bgshader, "freqY");
    ampXLoc = ray.GetShaderLocation(bgshader, "ampX");
    ampYLoc = ray.GetShaderLocation(bgshader, "ampY");
    speedXLoc = ray.GetShaderLocation(bgshader, "speedX");
    speedYLoc = ray.GetShaderLocation(bgshader, "speedY");
    sizeLoc = ray.GetShaderLocation(bgshader, "size");
}

pub fn deinit() void {
    std.debug.print("deinit gfx\n", .{});
    ray.UnloadShader(bgshader);
    ray.UnloadTexture(bgtexture);
}

// set random background
pub fn randombackground() void {
    ray.UnloadTexture(bgtexture);
    var i: u32 = sys.rng.random().intRangeAtMost(u32, 0, backgrounds.len - 1);
    var f = backgrounds[i];
    bgtexture = ray.LoadTexture(f);
    ray.SetTextureFilter(bgtexture, ray.TEXTURE_FILTER_TRILINEAR);
}

pub fn updatescale() void {
    if (ray.IsWindowResized()) {
        std.debug.print("window resized\n", .{});
        var newWidth = ray.GetScreenWidth();
        var newHeight = ray.GetScreenHeight();
        scalefactor = @min(@as(f32, @floatFromInt(newWidth)) / @as(f32, @floatFromInt(windowwidth)), @as(f32, @floatFromInt(newHeight)) / @as(f32, @floatFromInt(windowheight)));
        std.debug.print("scalefactor: {d} {} {}\n", .{ scalefactor, newWidth, newHeight });
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
    size[0] = @as(f32, @floatFromInt(ray.GetScreenWidth()));
    size[1] = @as(f32, @floatFromInt(ray.GetScreenHeight()));
    ray.SetShaderValue(bgshader, sizeLoc, &size, ray.SHADER_UNIFORM_VEC2);
}

fn background() void {
    ray.ClearBackground(ray.BLACK);
    ray.BeginShaderMode(bgshader);
    ray.DrawTexturePro(bgtexture, ray.Rectangle{
        .x = 0,
        .y = 0,
        .width = @as(f32, @floatFromInt(bgtexture.width)),
        .height = @as(f32, @floatFromInt(bgtexture.height)),
    }, ray.Rectangle{
        .x = 0,
        .y = 0,
        .width = @as(f32, @floatFromInt(ray.GetScreenWidth())),
        .height = @as(f32, @floatFromInt(ray.GetScreenHeight())),
    }, ray.Vector2{ .x = 0, .y = 0 }, 0, ray.WHITE);
    ray.EndShaderMode();
}

fn lineclears() void {
    const elapsed_time = std.time.milliTimestamp() - game.state.lineclearer.start_time;
    if (game.state.lineclearer.active) {
        for (game.state.lineclearer.lines, 0..) |clearing, rowIndex| {
            if (clearing) {
                for (0..10) |colIndex| {
                    var x = @as(i32, @intCast(colIndex)) * cellsize;
                    var y = @as(i32, @intCast(rowIndex)) * cellsize;
                    var e = @as(f32, @floatFromInt(elapsed_time));
                    var d = @as(f32, @floatFromInt(game.state.lineclearer.duration));
                    // clamp between 0 and 255
                    const computed = e / d * 255.0;
                    const clamped = std.math.clamp(computed, 0.0, 255.0);
                    var ratio: u8 = @intFromFloat(clamped);

                    // find underlying cell
                    var cell = game.state.cells[rowIndex][colIndex];

                    const color = .{ cell[0], cell[1], cell[2], 255 - ratio };
                    roundedfillbox(x, y, color);
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
        var drawX = game.state.piecex * cellsize;
        var drawY = game.state.piecey * cellsize;
        var fdrawx: f32 = @as(f32, @floatFromInt(drawX));
        var fdrawy: f32 = @as(f32, @floatFromInt(drawY));

        const elapsed_time = std.time.milliTimestamp() - game.state.pieceslider.start_time;
        // animate the piece if the slider is active
        if (game.state.pieceslider.active) {
            var duration = @as(f32, @floatFromInt(game.state.pieceslider.duration));
            const ratio: f32 = std.math.clamp(@as(f32, @floatFromInt(elapsed_time)) / duration, 0.0, 1.0);
            var targetx = @as(f32, @floatFromInt(game.state.pieceslider.targetx * cellsize));
            var targety = @as(f32, @floatFromInt(game.state.pieceslider.targety * cellsize));
            // lerp between the current position and the target position
            fdrawx = std.math.lerp(fdrawx, targetx, ratio);
            fdrawy = std.math.lerp(fdrawy, targety, ratio);
            // deactivate slider, set position if animation is complete
            if (elapsed_time >= game.state.pieceslider.duration) {
                game.state.pieceslider.active = false;
                game.state.piecex = game.state.pieceslider.targetx;
                game.state.piecey = game.state.pieceslider.targety;
                if (elapsed_time > game.state.pieceslider.duration)
                    std.debug.print("slide {}ms\n", .{elapsed_time});
            }
        }

        var xdx = @as(i32, @intFromFloat(fdrawx));
        var ydx = @as(i32, @intFromFloat(fdrawy));

        // draw the piece at the interpolated position
        piece(xdx, ydx, p.shape[game.state.piecer], p.color);

        // draw ghost
        const color = .{ p.color[0], p.color[1], p.color[2], 50 };
        piece(xdx, game.ghosty() * cellsize, p.shape[game.state.piecer], color);
    }
}

// draw a piece
fn piece(x: i32, y: i32, shape: [4][4]bool, color: [4]u8) void {
    for (shape, 0..) |row, i| {
        for (row, 0..) |cell, j| {
            if (cell) {
                roundedfillbox(x + @as(i32, @intCast(i)) * cellsize, y + @as(i32, @intCast(j)) * cellsize, color);
            }
        }
    }
}

// draw a box
fn box(x: i32, y: i32, color: [4]u8) void {
    ray.DrawRectangleLinesEx(ray.Rectangle{
        .x = @as(f32, @floatFromInt(gridoffsetx + x)),
        .y = @as(f32, @floatFromInt(gridoffsety + y)),
        .width = @as(f32, @floatFromInt(cellwidth)),
        .height = @as(f32, @floatFromInt(cellwidth)),
    }, 2, ray.Color{
        .r = color[0],
        .g = color[1],
        .b = color[2],
        .a = color[3],
    });
}

// draw a filled box
fn fillbox(x: i32, y: i32, color: [4]u8) void {
    ray.DrawRectangle(gridoffsetx + x, gridoffsety + y, cellwidth, cellwidth, ray.Color{
        .r = color[0],
        .g = color[1],
        .b = color[2],
        .a = color[3],
    });
}

// draw a rounded box
fn roundedfillbox(x: i32, y: i32, color: [4]u8) void {
    ray.DrawRectangleRounded(ray.Rectangle{
        .x = @as(f32, @floatFromInt(gridoffsetx + x)),
        .y = @as(f32, @floatFromInt(gridoffsety + y)),
        .width = @as(f32, @floatFromInt(cellwidth)),
        .height = @as(f32, @floatFromInt(cellwidth)),
    }, 0.5, 5, ray.Color{
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
                roundedfillbox(@as(i32, @intCast(x * cellsize)), @as(i32, @intCast(y * cellsize)), color);
            }
        }
    }
}

var textbuf: [1000]u8 = undefined;
fn ui() void {
    ray.SetTextLineSpacing(22);
    //ray.DrawRectangleLines(gridoffsetx - 10, gridoffsety - 10, 320, 622, ray.WHITE);
    ray.DrawRectangle(0, 0, 140, windowheight, ray.Color{
        .r = 0,
        .g = 0,
        .b = 0,
        .a = 40,
    });

    ray.DrawRectangle(windowwidth - 135, 0, 135, windowheight, ray.Color{
        .r = 0,
        .g = 0,
        .b = 0,
        .a = 40,
    });

    // ray.DrawRectangle(140, windowheight - 60, windowwidth - 135 - 135, 60, ray.Color{
    //     .r = 0,
    //     .g = 0,
    //     .b = 0,
    //     .a = 100,
    // });

    if (std.fmt.bufPrintZ(&textbuf, "score\n{}\nlines\n{}\nlevel\n{}", .{ game.state.score, game.state.lines, game.state.level })) |score| {
        var color = ray.GREEN;
        var size: f32 = 23;
        if (game.state.lineclearer.active) {
            scramblefx(score);
            color = ray.RED;
            size = 30;
        }
        // var scoreheight = ray.MeasureTextEx(sys.spacefont, score, size, 3).y;
        // var scorey = @as(f32, @floatFromInt(windowheight)) - scoreheight * 2;
        ray.DrawTextEx(sys.spacefont, score, ray.Vector2{ .x = 10, .y = 620 }, size, 3, color);
    } else |err| {
        std.debug.print("error printing score: {}\n", .{err});
    }

    ray.DrawTextEx(sys.spacefont, "next", ray.Vector2{ .x = 520, .y = 30 }, 22, // font size
        2, // spacing
        ray.GRAY // color
    );
    if (game.state.nextpiece) |nextpiece| {
        piece(windowwidth - 240, 35, nextpiece.shape[0], nextpiece.color);
    }

    ray.DrawTextEx(sys.spacefont, "held", ray.Vector2{ .x = 5, .y = 30 }, 22, // font size
        2, // spacing
        ray.GRAY // color
    );
    if (game.state.heldpiece) |held| {
        piece(35 - gridoffsetx, 35, held.shape[0], held.color);
    }

    if (game.state.paused) {
        ray.DrawRectangle(0, 0, windowwidth, windowheight, ray.Color{
            .r = 0,
            .g = 0,
            .b = 0,
            .a = 210,
        });

        ray.DrawTextEx(sys.spacefont, "PAUSED", ray.Vector2{ .x = 180, .y = 300 }, 60, 3, ray.ORANGE);
        ray.DrawText("press p to unpause", 190, 350, 20, ray.RED);
    }

    if (game.state.gameover) {
        ray.DrawRectangle(0, 0, windowwidth, windowheight, ray.Color{
            .r = 10,
            .g = 0,
            .b = 0,
            .a = 200,
        });

        ray.DrawTextEx(sys.spacefont, "GAME OVER", ray.Vector2{ .x = 110, .y = 290 }, 60, 3, ray.RED);
        ray.DrawText("r to restart", 225, 350, 20, ray.WHITE);
        ray.DrawText("esc to exit", 225, 375, 20, ray.WHITE);
    }
}

const scrambles = "!@#$%^&*+-=<>?/\\|~`";
fn scramblefx(s: []u8) void {
    for (s) |*c| {
        var n = scrambles[sys.rng.random().intRangeAtMost(u32, 0, scrambles.len)];
        if (c.* == '\n') {
            continue;
        }

        if (sys.rng.random().intRangeAtMost(u32, 0, 100) > 90) {
            c.* = n;
        }
    }
}
