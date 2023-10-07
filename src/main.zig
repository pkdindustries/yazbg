const std = @import("std");
const ray = @import("raylib.zig");
const pieces = @import("pieces.zig");
const game = @import("game.zig");
const sys = @import("system.zig");

const width = 570;
const height = 660;
const cellsize: i32 = 30;
const cellpadding: i32 = 1;
const offsetx: i32 = 145;
const offsety: i32 = 30;
const cellwidth: i32 = cellsize - 2 * cellpadding;
pub fn main() !void {
    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT | ray.FLAG_VSYNC_HINT | ray.FLAG_WINDOW_ALWAYS_RUN);
    ray.InitWindow(width, height, "yazbg");
    ray.SetTraceLogLevel(ray.LOG_WARNING);

    try sys.init();
    defer sys.deinit();

    game.init();

    while (!ray.WindowShouldClose()) {
        sys.update();
        defer draw();

        // game flow
        // restart
        if (ray.IsKeyPressed(ray.KEY_R)) {
            game.init();
        }
        // pause
        if (ray.IsKeyPressed(ray.KEY_P)) {
            if (game.state.gameover) continue;
            game.state.paused = !game.state.paused;
        }
        // we are frozen
        if (game.state.gameover or game.state.paused)
            continue;

        // game ticker
        if (ray.GetTime() - game.state.lastdrop >= game.state.dropinterval) {
            std.debug.print("tick\n", .{});
            if (!move(game.down, sys.playclick, drop)) {
                std.debug.print("tick failed, dropped\n", .{});
            }
            game.state.lastdrop = ray.GetTime();
        }

        // controls
        if (ray.IsKeyPressed(ray.KEY_LEFT))
            _ = move(game.left, sys.playclick, sys.playerror);

        if (ray.IsKeyPressed(ray.KEY_RIGHT))
            _ = move(game.right, sys.playclick, sys.playerror);

        if (ray.IsKeyPressed(ray.KEY_DOWN)) {
            _ = move(game.down, sys.playclick, drop);
            game.state.lastdrop = ray.GetTime();
        }

        if (ray.IsKeyPressed(ray.KEY_UP)) {
            _ = move(game.rotate, sys.playclick, sys.playerror);
        }

        if (ray.IsKeyPressed(ray.KEY_SPACE)) {
            drop();
        }

        if (ray.IsKeyPressed(ray.KEY_C)) {
            swap();
        }
    }
}

fn swap() void {
    if (game.state.swapped) {
        sys.playerror();
        std.debug.print("already swapped\n", .{});
        return;
    }

    // held piece, swap it
    if (game.state.heldpiece) |held| {
        game.state.heldpiece = game.state.piece;
        game.state.piece = held;
    } else {
        // replace the current piece with the next piece and generate a new
        game.state.heldpiece = game.state.piece;
        game.state.piece = game.state.nextpiece;
        game.nextpiece();
    }

    sys.playwoosh();
    game.state.swapped = true;
    game.state.piecex = 3;
    game.state.piecey = 0;
    game.state.piecer = 0;
}

fn drop() void {
    std.debug.print("drop\n", .{});
    sys.playwoosh();
    sys.playclack();
    if (game.drop()) {
        sys.playclear();
    }
    game.nextpiece();
    game.state.lastdrop = ray.GetTime();
}

// move the piece, if it can't move, call failback
fn move(comptime movefn: fn () bool, comptime ok: fn () void, comptime fail: fn () void) bool {
    if (movefn()) {
        ok();
        return true;
    } else {
        fail();
        return false;
    }
}

fn draw() void {
    ray.BeginDrawing();
    defer ray.EndDrawing();
    grid();
    player();
    animation();
    ui();
}

fn animation() void {
    const elapsed_time = std.time.milliTimestamp() - game.state.lineclearer.start_time;
    if (game.state.lineclearer.active) {
        for (game.state.lineclearer.lines, 0..) |clearing, rowIndex| {
            if (clearing) {
                for (0..10) |colIndex| {
                    var x = @as(i32, @intCast(colIndex)) * cellsize;
                    var y = @as(i32, @intCast(rowIndex)) * cellsize;
                    var e = @as(f32, @floatFromInt(elapsed_time));
                    var d = @as(f32, @floatFromInt(game.state.lineclearer.duration));

                    // Calculate ratio and clamp between 0 and 255
                    const computedValue = e / d * 250.0;
                    const clampedValue = std.math.clamp(computedValue, 0.0, 255.0);
                    var ratio: u8 = @intFromFloat(clampedValue);

                    const color = .{ 0, 0, 0, ratio };
                    box(x, y, color);
                }
            }
        }
    }
    if (elapsed_time >= game.state.lineclearer.duration) {
        game.state.lineclearer.active = false;
        for (game.state.lineclearer.lines, 0..) |c, i| {
            if (c) game.removeline(i);
            game.state.lineclearer.lines[i] = false;
        }
    }
}

// draw a piece
fn drawpiece(x: i32, y: i32, shape: [4][4]bool, color: [4]u8) void {
    for (shape, 0..) |row, i| {
        for (row, 0..) |cell, j| {
            if (cell) {
                box(x + @as(i32, @intCast(i)) * cellsize, y + @as(i32, @intCast(j)) * cellsize, color);
            }
        }
    }
}

// draw a box
fn box(x: i32, y: i32, color: [4]u8) void {
    ray.DrawRectangleLinesEx(ray.Rectangle{
        .x = @as(f32, @floatFromInt(offsetx + x)),
        .y = @as(f32, @floatFromInt(offsety + y)),
        .width = @as(f32, @floatFromInt(cellwidth)),
        .height = @as(f32, @floatFromInt(cellwidth)),
    }, 2, ray.Color{
        .r = color[0],
        .g = color[1],
        .b = color[2],
        .a = color[3],
    });

    // ray.DrawRectangleRoundedLines(ray.Rectangle{
    //     .x = @as(f32, @floatFromInt(offsetx + x)),
    //     .y = @as(f32, @floatFromInt(offsety + y)),
    //     .width = @as(f32, @floatFromInt(cellwidth)),
    //     .height = @as(f32, @floatFromInt(cellwidth)),
    // }, 0.45, 20, 1, ray.Color{
    //     .r = color[0],
    //     .g = color[1],
    //     .b = color[2],
    //     .a = color[3],
    // });
    // ray.DrawCircle(offsetx + x + cellwidth / 2, offsety + y + cellwidth / 2, 10, ray.Color{
    //     .r = color[0],
    //     .g = color[1],
    //     .b = color[2],
    //     .a = color[3],
    // });
}

// draw piece
fn player() void {
    // draw shape
    if (game.state.piece) |piece| {
        if (game.state.gameover) {
            return;
        }
        const pcolor = .{ piece.color[0], piece.color[1], piece.color[2], sys.rng.random().intRangeAtMost(u8, 200, 255) };
        drawpiece(game.state.piecex * cellsize, game.state.piecey * cellsize, piece.shape[game.state.piecer], pcolor);

        // draw ghost
        const ghostY = game.ghosty();
        const color = .{ piece.color[0], piece.color[1], piece.color[2], sys.rng.random().intRangeAtMost(u8, 60, 70) };
        drawpiece(game.state.piecex * cellsize, ghostY * cellsize, piece.shape[game.state.piecer], color);
    }
}

// draw the grid
fn grid() void {
    for (game.state.cells, 0..) |row, y| {
        for (row, 0..) |color, x| {
            if (color[3] != 0) {
                box(@as(i32, @intCast(x * cellsize)), @as(i32, @intCast(y * cellsize)), color);
            }
        }
    }
}

// draw the ui/score
var buf: [1000]u8 = undefined;
fn ui() void {
    ray.ClearBackground(ray.BLACK);

    ray.DrawRectangleLines(140, 5, 310, 632, ray.WHITE);

    if (std.fmt.bufPrintZ(&buf, "score {}", .{game.state.score})) |score| {
        scramblefx(score);
        ray.DrawText(score, 10, 560, 18, ray.GREEN);
    } else |err| {
        std.debug.print("error printing score: {}\n", .{err});
    }

    if (std.fmt.bufPrintZ(&buf, "lines {}", .{game.state.lines})) |lines| {
        scramblefx(lines);
        ray.DrawText(lines, 10, 580, 18, ray.GREEN);
    } else |err| {
        std.debug.print("error printing score: {}\n", .{err});
    }

    if (std.fmt.bufPrintZ(&buf, "level {}", .{game.state.level})) |level| {
        scramblefx(level);
        ray.DrawText(level, 10, 600, 18, ray.GREEN);
    } else |err| {
        std.debug.print("error printing score: {}\n", .{err});
    }

    // debug status
    if (std.fmt.bufPrintZ(&buf, "{} {} {} {d:.2} {d:.2}", .{ game.state.piecex, game.state.piecey, game.state.piecer, game.state.dropinterval, game.state.lastdrop })) |status| {
        ray.DrawText(status, 10, 620, 12, ray.GRAY);
    } else |err| {
        std.debug.print("error printing score: {}\n", .{err});
    }

    ray.DrawText("next", 460, 30, 18, ray.GRAY);
    if (game.state.nextpiece) |nextpiece| {
        drawpiece(width - 240, 35, nextpiece.shape[0], nextpiece.color);
    }
    ray.DrawText("held", 5, 30, 18, ray.GRAY);
    if (game.state.heldpiece) |held| {
        drawpiece(35 - offsetx, 35, held.shape[0], held.color);
    }

    if (game.state.paused) {
        ray.DrawRectangle(0, 0, width, height, ray.Color{
            .r = 0,
            .g = 0,
            .b = 0,
            .a = 210,
        });
        ray.DrawText("PAUSED", 190, 300, 50, ray.WHITE);
        ray.DrawText("press p to unpause", 190, 350, 20, ray.RED);
    }

    if (game.state.gameover) {
        ray.DrawRectangle(0, 0, width, height, ray.Color{
            .r = 0,
            .g = 0,
            .b = 0,
            .a = 210,
        });
        ray.DrawText("GAME OVER", 170, 300, 40, ray.RED);
        ray.DrawText("press r to restart", 200, 350, 20, ray.WHITE);
    }
}

fn scramblefx(s: []u8) void {
    var scrambles = "!@#$%^&*+-=<>?/\\|~`";
    for (s) |*c| {
        var n = scrambles[sys.rng.random().intRangeAtMost(u32, 0, scrambles.len)];
        if (sys.rng.random().intRangeAtMost(u32, 0, 100) > 99) {
            c.* = n;
        }
    }
}
