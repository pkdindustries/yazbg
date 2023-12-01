const std = @import("std");
const pieces = @import("pieces.zig");
const sfx = @import("sfx.zig");
const rnd = @import("random.zig");
const anim = @import("animation.zig");
const grid = @import("grid.zig");
pub const grid_rows = 20;
pub const grid_cols = 10;

const GPA = std.heap.GeneralPurposeAllocator(.{});
pub var gpa = GPA{};

pub const YAZBG = struct {
    grid: *grid.Grid = undefined,
    score: i32 = 0,
    level: i32 = 0,
    lines: i32 = 0,
    lineslevelup: i32 = 0,
    init: bool = true,
    swapped: bool = false,
    // time between drops
    dropinterval: f64 = 2.0,
    gameover: bool = false,
    paused: bool = false,
    // time of last move
    lastmove: f64 = 0,
    // current, next and held piece shapes
    piece: ?pieces.tetramino = null,
    nextpiece: ?pieces.tetramino = null,
    heldpiece: ?pieces.tetramino = null,
    // player piece position,rotation
    piecex: i32 = 0,
    piecey: i32 = 0,
    piecer: u32 = 0,
    // state for various animations
    pieceslider: struct {
        active: bool = false,
        start_time: i64 = 0,
        duration: i64 = 50,
        targetx: i32 = 0,
        targety: i32 = 0,
        sourcex: i32 = 0,
        sourcey: i32 = 0,
    } = .{},
};

pub var state = YAZBG{};

pub fn frozen() bool {
    return state.gameover or state.paused;
}

pub fn tickable() bool {
    return !false and !state.pieceslider.active and !frozen() and sfx.ray.GetTime() - state.lastmove >= state.dropinterval;
}

pub fn reset() void {
    state.score = 0;
    state.level = 0;
    state.lines = 0;
    state.lineslevelup = 0;
    state.lastmove = 0;
    state.dropinterval = 2.0;
    state.nextpiece = pieces.tetraminos[rnd.ng.random().intRangeAtMost(u32, 0, 6)];
    state.heldpiece = null;

    state.pieceslider = .{
        .active = false,
        .start_time = 0,
        .duration = 50,
        .targetx = 0,
        .targety = 0,
    };

    if (state.init == true) {
        state.grid = grid.Grid.init(gpa.allocator()) catch |err| {
            std.debug.print("failed to allocate grid: {}\n", .{err});
            return;
        };
        state.init = false;
    } else {
        state.grid.destroy();
    }
    nextpiece();

    state.gameover = false;
    state.paused = false;
    std.debug.print("init game\n", .{});
}

pub fn nextpiece() void {
    state.piece = state.nextpiece;
    state.nextpiece = pieces.tetraminos[rnd.ng.random().intRangeAtMost(u32, 0, 6)];
    state.piecex = 3;
    state.piecey = 0;
    state.piecer = 0;
    state.swapped = false;

    if (!checkmove(state.piecex, state.piecey)) {
        for (0..grid_rows) |r| {
            anim.linesplat(r);
            sfx.playgameover();
        }

        state.piece = null;
        state.gameover = true;
    }
}

pub fn swappiece() bool {
    if (state.swapped) {
        std.debug.print("already swapped\n", .{});
        return false;
    }
    if (state.heldpiece) |held| {
        state.heldpiece = state.piece;
        state.piece = held;
    } else {
        state.heldpiece = state.piece;
        nextpiece();
    }
    state.swapped = true;
    state.lastmove = sfx.ray.GetTime();
    return state.swapped;
}

pub fn pause() void {
    if (state.gameover) return;
    state.paused = !state.paused;
    std.debug.print("game.paused {}\n", .{state.paused});
}

pub fn ghosty() i32 {
    var y = state.piecey;
    while (checkmove(state.piecex, y + 1)) : (y += 1) {}
    return y;
}

pub fn checkmove(x: i32, y: i32) bool {
    if (state.piece) |piece| {
        const shape = piece.shape[state.piecer];
        for (shape, 0..) |row, j| {
            for (row, 0..) |cell, i| {
                if (cell) {
                    const gx = x + @as(i32, @intCast(j));
                    const gy = y + @as(i32, @intCast(i));
                    // cell is out of bounds
                    if (gx < 0 or gx >= grid_cols or gy < 0 or gy >= grid_rows) {
                        return false;
                    }

                    // cell is already occupied via newcells
                    if (state.grid.cells[@as(usize, @intCast(gy))][@as(usize, @intCast(gx))]) |_| {
                        return false;
                    }
                }
            }
        }
    }
    return true;
}

// drop the piece to the bottom, clear lines and return num cleared
pub fn harddrop() i32 {
    std.debug.print("game.drop\n", .{});
    var y = state.piecey;
    while (checkmove(state.piecex, y + 1)) : (y += 1) {}
    state.piecey = y;
    if (state.piece) |piece| {
        const shape = piece.shape[state.piecer];
        for (shape, 0..) |row, i| {
            for (row, 0..) |cell, j| {
                if (cell) {
                    const gx = state.piecex + @as(i32, @intCast(i));
                    const gy = state.piecey + @as(i32, @intCast(j));
                    if (gx >= 0 and gx < grid_cols and gy >= 0 and gy < grid_rows) {
                        const ix = @as(usize, @intCast(gx));
                        const iy = @as(usize, @intCast(gy));
                        const ac = anim.AnimatedCell.init(&gpa.allocator(), ix, iy, piece.color) catch |err| {
                            std.debug.print("failed to allocate cell: {}\n", .{err});
                            return 0;
                        };
                        state.grid.cells[iy][ix] = ac;
                    }
                }
            }
        }
    }

    state.lastmove = sfx.ray.GetTime();
    const cleared = state.grid.clear();
    std.debug.print("game.drop done {}\n", .{cleared});
    state.lineslevelup += cleared;
    return cleared;
}

// move piece right
pub fn right() bool {
    const x: i32 = state.piecex + 1;
    const y = state.piecey;
    if (!checkmove(x, y)) {
        return false;
    }
    slidepiece(x, y);
    state.lastmove = sfx.ray.GetTime();
    return true;
}

// move piece left
pub fn left() bool {
    const x: i32 = state.piecex - 1;
    const y = state.piecey;
    if (!checkmove(x, y)) {
        return false;
    }

    slidepiece(x, y);
    state.lastmove = sfx.ray.GetTime();
    return true;
}

// move piece down
pub fn down() bool {
    const x: i32 = state.piecex;
    const y: i32 = state.piecey + 1;
    if (!checkmove(x, y)) {
        return false;
    }
    slidepiece(x, y);
    state.lastmove = sfx.ray.GetTime();
    return true;
}

// rotate piece clockwise
pub fn rotate() bool {
    const oldr: u32 = state.piecer;
    state.piecer = (state.piecer + 1) % 4; // increment and wrap around the rotation
    std.debug.print("rotation {} -> {}\n", .{ oldr, state.piecer });

    // after rotation, the piece fits, return
    if (checkmove(state.piecex, state.piecey)) {
        state.lastmove = sfx.ray.GetTime();
        return true;
    }

    // try wall-kicks to fit the piece
    if (state.piece) |piece| {
        const kickData = piece.kicks[finddirection(oldr, state.piecer)];

        // kick and check if the moved piece fits
        for (kickData) |kick| {
            state.piecex += kick[0];
            state.piecey += kick[1];

            if (checkmove(state.piecex, state.piecey)) {
                std.debug.print("kick\n", .{});
                state.lastmove = sfx.ray.GetTime();
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

fn slidepiece(x: i32, y: i32) void {
    state.pieceslider.targetx = x;
    state.pieceslider.targety = y;
    state.pieceslider.sourcex = state.piecex;
    state.pieceslider.sourcey = state.piecey;
    state.piecex = state.pieceslider.targetx;
    state.piecey = state.pieceslider.targety;
    state.pieceslider.start_time = std.time.milliTimestamp();
    state.pieceslider.active = true;
}
