const std = @import("std");
const ray = @import("raylib.zig");
const sfx = @import("sfx.zig");
const game = @import("game.zig");

pub const OGWIDTH: i32 = 640;
pub const OGHEIGHT: i32 = 760;

pub const Window = struct {
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
            ui();
        }
        ray.EndTextureMode();
        // scale texture to window size
        const src = ray.Rectangle{ .x = 0, .y = 0, .width = OGWIDTH, .height = -OGHEIGHT };
        const tgt = ray.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(window.width), .height = @floatFromInt(window.height) };
        ray.DrawTexturePro(window.texture.texture, src, tgt, ray.Vector2{ .x = 0, .y = 0 }, 0, ray.WHITE);
    }
    ray.EndDrawing();
}

pub fn init() !void {
    std.debug.print("init gfx\n", .{});
    // window init
    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT | ray.FLAG_WINDOW_RESIZABLE);
    ray.InitWindow(OGWIDTH, OGHEIGHT, "yazbg");
    window.texture = ray.LoadRenderTexture(OGWIDTH, OGHEIGHT);
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
        var height = @divTrunc(width * OGHEIGHT, OGWIDTH);
        const maxheight = ray.GetMonitorHeight(0) - 100; // Assuming the primary monitor
        if (height > maxheight) {
            height = maxheight;
            width = @divTrunc(height * OGWIDTH, OGHEIGHT);
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

    if (game.state.grid.cleartimer > (std.time.milliTimestamp())) {
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
        bg.speedx = 0.15 * (@as(f32, @floatFromInt(game.state.progression.level)) + 2);
        bg.speedy = 0.15 * (@as(f32, @floatFromInt(game.state.progression.level)) + 2);
    }

    ray.SetShaderValue(bg.shader, bg.freqxloc, &bg.freqx, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(bg.shader, bg.freqyloc, &bg.freqy, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(bg.shader, bg.ampxloc, &bg.ampx, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(bg.shader, bg.ampyloc, &bg.ampy, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(bg.shader, bg.speedxloc, &bg.speedx, ray.SHADER_UNIFORM_FLOAT);
    ray.SetShaderValue(bg.shader, bg.speedyloc, &bg.speedy, ray.SHADER_UNIFORM_FLOAT);

    var size: [2]f32 = undefined;
    size[0] = @as(f32, @floatFromInt(OGWIDTH));
    size[1] = @as(f32, @floatFromInt(OGHEIGHT));
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
        .width = @floatFromInt(OGWIDTH),
        .height = @floatFromInt(OGHEIGHT),
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

// draw a rounded box
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

var textbuf: [1000]u8 = undefined;
fn ui() void {
    ray.SetTextLineSpacing(22);

    const bordercolor = ray.Color{
        .r = 0,
        .g = 0,
        .b = 255,
        .a = 20,
    };

    ray.DrawRectangle(0, 0, 140, OGHEIGHT, bordercolor);
    ray.DrawRectangle(OGWIDTH - 135, 0, 135, OGHEIGHT, bordercolor);

    ray.DrawLineEx(ray.Vector2{ .x = 140, .y = 0 }, ray.Vector2{ .x = 140, .y = @floatFromInt(OGHEIGHT) }, 3, ray.RED);
    ray.DrawLineEx(ray.Vector2{ .x = OGWIDTH - 135, .y = 0 }, ray.Vector2{ .x = OGWIDTH - 135, .y = @floatFromInt(OGHEIGHT) }, 3, ray.RED);

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
        ray.DrawTextEx(window.font, score, ray.Vector2{ .x = 10, .y = 620 }, size, 3, color);
    } else |err| {
        std.debug.print("error printing score: {}\n", .{err});
    }
    ray.DrawTextEx(window.font, "next", ray.Vector2{ .x = 520, .y = 30 }, 40, // font size
        2, // spacing
        ray.GRAY // color
    );
    if (game.state.piece.next) |nextpiece| {
        piece(OGWIDTH - 250, 35, nextpiece.shape[0], nextpiece.color);
    }

    ray.DrawTextEx(window.font, "held", ray.Vector2{ .x = 23, .y = 30 }, 40, // font size
        2, // spacing
        ray.GRAY // color
    );
    if (game.state.piece.held) |held| {
        piece(35 - window.gridoffsetx, 35, held.shape[0], held.color);
    }

    if (game.state.paused) {
        ray.BeginShaderMode(static);
        ray.DrawRectangle(0, 0, OGWIDTH, OGHEIGHT, ray.Color{
            .r = 0,
            .g = 0,
            .b = 0,
            .a = 210,
        });
        ray.EndShaderMode();

        if (std.fmt.bufPrintZ(&textbuf, "PAUSED", .{})) |paused| {
            scramblefx(paused, 10);
            ray.DrawTextEx(window.font, paused, ray.Vector2{ .x = 210, .y = 300 }, 60, 3, ray.ORANGE);
            ray.DrawText("press p to unpause", 220, 350, 20, ray.RED);
        } else |err| {
            std.debug.print("error printing paused: {}\n", .{err});
        }
    }

    if (game.state.gameover) {
        ray.DrawRectangle(0, 0, OGWIDTH, OGHEIGHT, ray.Color{
            .r = 10,
            .g = 0,
            .b = 0,
            .a = 200,
        });

        if (std.fmt.bufPrintZ(&textbuf, "GAME OVER", .{})) |over| {
            scramblefx(over, 1);
            ray.DrawTextEx(window.font, over, ray.Vector2{ .x = 145, .y = 290 }, 60, 3, ray.RED);
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
        const n = scrambles[game.state.rng.random().intRangeAtMost(u32, 0, scrambles.len)];
        if (c.* == '\n' or c.* == ' ') {
            continue;
        }

        if (game.state.rng.random().intRangeAtMost(u32, 0, 100) > 100 - intensity) {
            c.* = n;
        }
    }
}
