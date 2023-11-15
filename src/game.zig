const pieces = @import("pieces.zig");
const std = @import("std");
const sys = @import("system.zig");

const cell_height = 20;
const cell_width = 10;

pub const YAZBG = struct {
    cells: [cell_height][cell_width][4]u8 = undefined,
    score: i32 = 0,
    level: i32 = 0,
    lines: i32 = 0,
    swapped: bool = false,
    piece: ?pieces.tetramino = null,
    nextpiece: ?pieces.tetramino = null,
    heldpiece: ?pieces.tetramino = null,
    piecex: i32 = 0,
    piecey: i32 = 0,
    piecer: u32 = 0,
    currtime: f64 = 0,
    lastmove: f64 = 0,
    dropinterval: f64 = 2.0,
    gameover: bool = false,
    paused: bool = false,

    lineclearer: struct {
        active: bool = false,
        start_time: i64 = 0,
        duration: i64 = 500,
        lines: [cell_height]bool = undefined,
    } = .{},
};

pub var state = YAZBG{};

pub fn init() void {
    // reset
    state.score = 0;
    state.level = 0;
    state.lines = 0;
    state.lastmove = 0;
    state.dropinterval = 2.0;
    state.nextpiece = pieces.tetraminos[sys.rng.random().intRangeAtMost(u32, 0, 6)];
    nextpiece();
    state.heldpiece = null;

    state.lineclearer = .{
        .active = false,
        .start_time = 0,
        .duration = 500,
        .lines = undefined,
    };
    for (state.cells, 0..) |row, r| {
        for (row, 0..) |_, c| {
            state.cells[r][c] = .{ 0, 0, 0, 0 };
        }
    }

    state.gameover = false;
    state.paused = false;
    std.debug.print("init game\n", .{});
}

pub fn nextpiece() void {
    state.piece = state.nextpiece;
    state.nextpiece = pieces.tetraminos[sys.rng.random().intRangeAtMost(u32, 0, 6)];
    state.piecex = 3;
    state.piecey = 0;
    state.piecer = 0;
    state.swapped = false;

    if (!checkmove()) {
        state.gameover = true;
    }
}

pub fn clearlines() bool {
    var lines: i32 = 0;
    for (state.cells, 0..) |row, r| {
        if (iscompleted(row)) {
            state.lineclearer.lines[r] = true;
            lines += 1;
        }
    }

    state.lines += lines;

    if (lines > 0) {
        state.lineclearer.active = true;
        state.lineclearer.start_time = std.time.milliTimestamp();
        state.score += 1000 * lines * lines;

        if (lines == 4) {
            sys.playwin();
        }

        if (@rem(state.lines, 3) == 0) {
            std.debug.print("level up\n", .{});
            sys.playlevel();
            state.level += 1;
            state.score += 1000 * state.level;
            state.dropinterval -= 0.15;
            if (state.dropinterval < 0.2) {
                state.dropinterval = 0.2;
            }
        }
    }
    return lines > 0;
}

fn iscompleted(row: [10][4]u8) bool {
    for (row) |cell| {
        if (cell[3] == 0) return false;
    }

    return true;
}

pub fn removeline(row: usize) void {
    // lines from the removed line upwards.
    var r = row;
    while (r > 0) {
        state.cells[r] = state.cells[r - 1];
        r -= 1;
    }

    // clear the topmost line.
    for (state.cells[0], 0..) |_, c| {
        state.cells[0][c] = .{ 0, 0, 0, 0 };
    }
}

pub fn pause() void {
    if (state.gameover) return;
    state.paused = !state.paused;
    std.debug.print("game.paused {}\n", .{state.paused});
}

pub fn ghosty() i32 {
    var y = state.piecey;
    while (true) {
        state.piecey += 1;
        if (!checkmove()) {
            state.piecey -= 1;
            break;
        }
    }
    var f = state.piecey;
    state.piecey = y;
    return f;
}

pub fn checkmove() bool {
    //std.debug.print("game.checkmove {} {}\n", .{ state.piecex, state.piecey });
    if (state.piece) |piece| {
        const shape = piece.shape[state.piecer];
        for (shape, 0..) |row, j| {
            for (row, 0..) |cell, i| {
                if (cell) {
                    const gx = state.piecex + @as(i32, @intCast(j));
                    const gy = state.piecey + @as(i32, @intCast(i));
                    // cell is out of bounds
                    if (gx < 0 or gx >= cell_width or gy < 0 or gy >= cell_height) {
                        return false;
                    }
                    //  cell is already occupied
                    if (state.cells[@as(usize, @intCast(gy))][@as(usize, @intCast(gx))][3] != 0) {
                        return false;
                    }
                }
            }
        }
    }
    return true;
}

pub fn drop() bool {
    std.debug.print("game.drop\n", .{});
    while (down()) {}
    if (state.piece) |piece| {
        const shape = piece.shape[state.piecer];
        for (shape, 0..) |row, i| {
            for (row, 0..) |cell, j| {
                if (cell) {
                    const gx = state.piecex + @as(i32, @intCast(i));
                    const gy = state.piecey + @as(i32, @intCast(j));
                    if (gx >= 0 and gx < cell_width and gy >= 0 and gy < cell_height) {
                        state.cells[@as(usize, @intCast(gy))][@as(usize, @intCast(gx))] = piece.color;
                    }
                }
            }
        }
    }
    state.lastmove = sys.ray.GetTime();
    return clearlines();
}

pub fn right() bool {
    state.piecex += 1;
    if (!checkmove()) {
        state.piecex -= 1;
        return false;
    }
    state.lastmove = sys.ray.GetTime();
    return true;
}

pub fn left() bool {
    state.piecex -= 1;
    if (!checkmove()) {
        state.piecex += 1;
        return false;
    }
    state.lastmove = sys.ray.GetTime();
    return true;
}

pub fn frozen() bool {
    return state.gameover or state.paused;
}

pub fn rotate() bool {
    var oldr: u32 = state.piecer;
    state.piecer = (state.piecer + 1) % 4; // Increment and wrap around the rotation
    std.debug.print("rotation {} -> {}\n", .{ oldr, state.piecer });

    // after rotation, the piece fits, return
    if (checkmove()) {
        state.lastmove = sys.ray.GetTime();
        return true;
    }

    // try wall-kicks to fit the piece
    if (state.piece) |piece| {
        const kickData = piece.kicks[finddirection(oldr, state.piecer)];

        // kick and check if the moved piece fits
        for (kickData) |kick| {
            state.piecex += kick[0];
            state.piecey += kick[1];

            if (checkmove()) {
                std.debug.print("kick\n", .{});
                return true;
            }
            // revert the kick
            std.debug.print("failed kick\n", .{});
            state.piecex -= kick[0];
            state.piecey -= kick[1];
        }
    }

    // unkickable, revert the rotation and return false
    state.piecer = oldr;
    return false;
}

// (0 for CW, 1 for CCW)
fn finddirection(oldr: u32, newr: u32) u32 {
    if (oldr > newr or (oldr == 0 and newr == 3) or (oldr == 3 and newr == 0)) return 1;
    return 0;
}

pub fn down() bool {
    state.piecey += 1;
    if (!checkmove()) {
        state.piecey -= 1;
        return false;
    }
    state.lastmove = sys.ray.GetTime();

    return true;
}
