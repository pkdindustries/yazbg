const std = @import("std");
const ray = @import("raylib.zig");
const sys = @import("system.zig");
const game = @import("game.zig");

pub const width = 570;
pub const height = 660;
pub const cellsize: i32 = 30;
pub const cellpadding: i32 = 1;
pub const offsetx: i32 = 145;
pub const offsety: i32 = 30;
pub const cellwidth: i32 = cellsize - 2 * cellpadding;
const scrambles = "!@#$%^&*+-=<>?/\\|~`";

var buf: [1000]u8 = undefined;

pub fn frame() void {
    ray.BeginDrawing();
    grid();
    player();
    animation();
    ui();
    ray.EndDrawing();
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

                    // clamp between 0 and 255
                    const computed = e / d * 250.0;
                    const clamped = std.math.clamp(computed, 0.0, 255.0);
                    var ratio: u8 = @intFromFloat(clamped);

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
fn piece(x: i32, y: i32, shape: [4][4]bool, color: [4]u8) void {
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
}

// draw piece
fn player() void {
    // draw shape
    if (game.state.piece) |p| {
        const pcolor = .{ p.color[0], p.color[1], p.color[2], sys.rng.random().intRangeAtMost(u8, 200, 255) };
        piece(game.state.piecex * cellsize, game.state.piecey * cellsize, p.shape[game.state.piecer], pcolor);

        // draw ghost
        const ghostY = game.ghosty();
        const color = .{ p.color[0], p.color[1], p.color[2], sys.rng.random().intRangeAtMost(u8, 60, 70) };
        piece(game.state.piecex * cellsize, ghostY * cellsize, p.shape[game.state.piecer], color);
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
    if (std.fmt.bufPrintZ(&buf, "{} {} {} {d:.2} {d:.2}", .{ game.state.piecex, game.state.piecey, game.state.piecer, game.state.dropinterval, game.state.lastmove })) |status| {
        ray.DrawText(status, 10, 620, 12, ray.GRAY);
    } else |err| {
        std.debug.print("error printing score: {}\n", .{err});
    }

    ray.DrawText("next", 460, 30, 18, ray.GRAY);
    if (game.state.nextpiece) |nextpiece| {
        piece(width - 240, 35, nextpiece.shape[0], nextpiece.color);
    }
    ray.DrawText("held", 5, 30, 18, ray.GRAY);
    if (game.state.heldpiece) |held| {
        piece(35 - offsetx, 35, held.shape[0], held.color);
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
        ray.DrawText("r to restart", 225, 350, 20, ray.WHITE);
        ray.DrawText("esc to exit", 225, 375, 20, ray.WHITE);
    }
}

fn scramblefx(s: []u8) void {
    for (s) |*c| {
        var n = scrambles[sys.rng.random().intRangeAtMost(u32, 0, scrambles.len)];
        if (sys.rng.random().intRangeAtMost(u32, 0, 100) > 99) {
            c.* = n;
        }
    }
}
