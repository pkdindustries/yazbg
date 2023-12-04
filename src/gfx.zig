const std = @import("std");
const ray = @import("raylib.zig");
const sfx = @import("sfx.zig");
const game = @import("game.zig");
const rnd = @import("random.zig");

const ogwindowwidth: i32 = 640;
const ogwindowheight: i32 = 760;

var windowwidth: i32 = ogwindowwidth;
var windowheight: i32 = ogwindowheight;
var windowtexture = ray.RenderTexture2D{};
var spacefont = ray.Font{};
// grid location and size
var gridoffsetx: i32 = 150;
var gridoffsety: i32 = 50;
var cellsize: i32 = 35;
var cellpadding: i32 = 2;
// background stuff
const bgimagefiles: [9][*:0]const u8 = .{
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
var bgimagetextures: [9]ray.Texture2D = undefined;
var bgimageindex: u32 = 0;
// shader stuff
// static shader
var fgshader: ray.Shader = undefined;
var fgtime: i32 = 0;
// warp shader
var bgshader: ray.Shader = undefined;
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

var freakoutstart: u64 = 0;
var freakoutduration: u64 = 200;

pub fn frame() void {
    // resize
    updatescale();
    // shader uniforms
    preshade();
    ray.BeginDrawing();
    {
        // draw to texture first
        ray.BeginTextureMode(windowtexture);
        {
            // background and shader
            background();
            // static shader
            ray.BeginShaderMode(fgshader);
            {
                // player piece and ghost
                player();
                // grid
                drawcells();
            }
            ray.EndShaderMode();
            // ux
            ui();
        }

        ray.EndTextureMode();
        // scale texture to window size
        const src = ray.Rectangle{ .x = 0, .y = 0, .width = ogwindowwidth, .height = -ogwindowheight };
        const tgt = ray.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(windowwidth), .height = @floatFromInt(windowheight) };
        ray.DrawTexturePro(windowtexture.texture, src, tgt, ray.Vector2{ .x = 0, .y = 0 }, 0, ray.WHITE);
    }
    ray.EndDrawing();
}

pub fn init() !void {
    std.debug.print("init gfx\n", .{});

    // window init
    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT | ray.FLAG_WINDOW_RESIZABLE);
    ray.InitWindow(ogwindowwidth, ogwindowheight, "yazbg");
    windowtexture = ray.LoadRenderTexture(ogwindowwidth, ogwindowheight);
    //ray.GenTextureMipmaps(&texture.texture);
    ray.SetTextureFilter(windowtexture.texture, ray.TEXTURE_FILTER_TRILINEAR);

    // background warp shader
    bgshader = ray.LoadShader(null, "resources/shader/warp.fs");
    secondsloc = ray.GetShaderLocation(bgshader, "seconds");
    freqXLoc = ray.GetShaderLocation(bgshader, "freqX");
    freqYLoc = ray.GetShaderLocation(bgshader, "freqY");
    ampXLoc = ray.GetShaderLocation(bgshader, "ampX");
    ampYLoc = ray.GetShaderLocation(bgshader, "ampY");
    speedXLoc = ray.GetShaderLocation(bgshader, "speedX");
    speedYLoc = ray.GetShaderLocation(bgshader, "speedY");
    sizeLoc = ray.GetShaderLocation(bgshader, "size");

    // block static shader
    fgshader = ray.LoadShader(null, "resources/shader/static.fs");
    fgtime = ray.GetShaderLocation(fgshader, "time");

    // font init
    spacefont = ray.LoadFont("resources/font/nasa.otf");
    ray.GenTextureMipmaps(&spacefont.texture);
    ray.SetTextureFilter(spacefont.texture, ray.TEXTURE_FILTER_TRILINEAR);

    // load each of the images into bgtextures
    for (bgimagefiles, 0..) |f, i| {
        var t = ray.LoadTexture(f);
        ray.GenTextureMipmaps(&t);
        ray.SetTextureFilter(t, ray.TEXTURE_FILTER_TRILINEAR);
        bgimagetextures[i] = t;
    }
    loadbackground();
}

pub fn deinit() void {
    std.debug.print("deinit gfx\n", .{});
    ray.UnloadShader(bgshader);
    ray.UnloadShader(fgshader);
    for (bgimagetextures) |t| {
        ray.UnloadTexture(t);
    }
    ray.UnloadTexture(windowtexture.texture);
    ray.UnloadFont(spacefont);
}

pub fn loadbackground() void {
    ray.GenTextureMipmaps(&bgimagetextures[bgimageindex]);
    ray.SetTextureFilter(bgimagetextures[bgimageindex], ray.TEXTURE_FILTER_TRILINEAR);
}

pub fn nextbackground() void {
    bgimageindex += 1;
    if (bgimageindex >= bgimagefiles.len) {
        bgimageindex = 0;
    }
    loadbackground();
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
        ray.GenTextureMipmaps(&windowtexture.texture);
        ray.SetWindowSize(width, height);
    }
}

// update shader stuff before draw call
fn preshade() void {
    ray.SetShaderValue(bgshader, secondsloc, &@as(f32, @floatCast(ray.GetTime())), ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(fgshader, fgtime, &@as(f32, @floatCast(ray.GetTime())), ray.SHADER_UNIFORM_FLOAT);

    // go wild during a clear
    if (false) {
        freqX = 50.0;
        freqY = 50.0;
        ampX = 10.0;
        ampY = 10.0;
        speedX = 100;
        speedY = 100;
    } else {
        freqX = 10.0;
        freqY = 10.0;
        ampX = 2.0;
        ampY = 2.0;
        speedX = 0.15 * (@as(f32, @floatFromInt(game.state.progression.level)) + 2);
        speedY = 0.15 * (@as(f32, @floatFromInt(game.state.progression.level)) + 2);
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
        .width = @floatFromInt(bgimagetextures[bgimageindex].width),
        .height = @floatFromInt(bgimagetextures[bgimageindex].height),
    };

    const tgt = ray.Rectangle{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(ogwindowwidth),
        .height = @floatFromInt(ogwindowheight),
    };

    ray.DrawTexturePro(bgimagetextures[bgimageindex], src, tgt, ray.Vector2{ .x = 0, .y = 0 }, 0, ray.WHITE);
    ray.EndShaderMode();
}

fn player() void {
    if (game.state.piece.current) |p| {
        var drawX: i32 = game.state.piece.x * cellsize;
        var drawY: i32 = game.state.piece.y * cellsize;
        var fdrawx: f32 = @floatFromInt(drawX);
        var fdrawy: f32 = @floatFromInt(drawY);

        const elapsed_time = std.time.milliTimestamp() - game.state.piece.slider.start_time;
        // animate the piece if the slider is active
        if (game.state.piece.slider.active) {
            drawX = game.state.piece.slider.sourcex * cellsize;
            drawY = game.state.piece.slider.sourcey * cellsize;
            fdrawx = @floatFromInt(drawX);
            fdrawy = @floatFromInt(drawY);
            const duration: f32 = @floatFromInt(game.state.piece.slider.duration);
            const ratio: f32 = std.math.clamp(@as(f32, @floatFromInt(elapsed_time)) / duration, 0.0, 1.0);
            const targetx: f32 = @floatFromInt(game.state.piece.x * cellsize);
            const targety: f32 = @floatFromInt(game.state.piece.y * cellsize);
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
        piece(xdx, game.ghosty() * cellsize, p.shape[game.state.piece.r], color);
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
                const xs: i32 = @as(i32, @intCast(i)) * cellsize;
                const ys: i32 = @as(i32, @intCast(j)) * cellsize;
                roundedfillbox(x + xs, y + ys, color);
            }
        }
    }
}

// draw a rounded box
fn roundedfillbox(x: i32, y: i32, color: [4]u8) void {
    ray.DrawRectangleRounded(ray.Rectangle{
        .x = @floatFromInt(gridoffsetx + x),
        .y = @floatFromInt(gridoffsety + y),
        .width = @floatFromInt(cellsize - 2 * cellpadding),
        .height = @floatFromInt(cellsize - 2 * cellpadding),
    }, 0.4, 20, ray.Color{
        .r = color[0],
        .g = color[1],
        .b = color[2],
        .a = color[3],
    });
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

    ray.DrawLineEx(ray.Vector2{ .x = 140, .y = 0 }, ray.Vector2{ .x = 140, .y = @floatFromInt(ogwindowheight) }, 3, ray.RED);
    ray.DrawLineEx(ray.Vector2{ .x = ogwindowwidth - 135, .y = 0 }, ray.Vector2{ .x = ogwindowwidth - 135, .y = @floatFromInt(ogwindowheight) }, 3, ray.RED);

    if (std.fmt.bufPrintZ(&textbuf, "score\n{}\nlines\n{}\nlevel\n{}", .{ game.state.progression.score, game.state.progression.cleared, game.state.progression.level })) |score| {
        var color = ray.GREEN;
        var size: f32 = 22;
        if (false) {
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
    if (game.state.piece.next) |nextpiece| {
        piece(ogwindowwidth - 250, 35, nextpiece.shape[0], nextpiece.color);
    }

    ray.DrawTextEx(spacefont, "held", ray.Vector2{ .x = 23, .y = 30 }, 40, // font size
        2, // spacing
        ray.GRAY // color
    );
    if (game.state.piece.held) |held| {
        piece(35 - gridoffsetx, 35, held.shape[0], held.color);
    }

    if (game.state.paused) {
        ray.BeginShaderMode(fgshader);
        ray.DrawRectangle(0, 0, ogwindowwidth, ogwindowheight, ray.Color{
            .r = 0,
            .g = 0,
            .b = 0,
            .a = 210,
        });
        ray.EndShaderMode();

        if (std.fmt.bufPrintZ(&textbuf, "PAUSED", .{})) |paused| {
            scramblefx(paused, 10);
            ray.DrawTextEx(spacefont, paused, ray.Vector2{ .x = 210, .y = 300 }, 60, 3, ray.ORANGE);
            ray.DrawText("press p to unpause", 220, 350, 20, ray.RED);
        } else |err| {
            std.debug.print("error printing paused: {}\n", .{err});
        }
    }

    if (game.state.gameover) {
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
