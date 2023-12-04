const std = @import("std");
const sfx = @import("sfx.zig");
const rnd = @import("random.zig");
const anim = @import("animation.zig");
const Animated = anim.Animated;
const Grid = @import("grid.zig").Grid;
const PIECES = @import("pieces.zig");
const GPA = std.heap.GeneralPurposeAllocator(.{});

pub const YAZBG = struct {
    gpallocator: GPA = undefined,
    grid: *Grid = undefined,
    gameover: bool = false,
    paused: bool = false,
    // time of last move
    lastmove: f64 = 0,
    progression: struct {
        score: i32 = 0,
        level: i32 = 0,
        // total lines cleared
        cleared: i32 = 0,
        // lines cleared since last level up
        clearedperlevel: i32 = 0,
        // time between drops
        dropinterval: f64 = 2.0,
    } = .{},
    // current, next and held piece shapes
    piece: struct {
        current: ?PIECES.tetramino = null,
        next: ?PIECES.tetramino = null,
        held: ?PIECES.tetramino = null,
        swapped: bool = false,
        x: i32 = 0,
        y: i32 = 0,
        r: u32 = 0,
        slider: struct {
            active: bool = false,
            start_time: i64 = 0,
            duration: i64 = 50,
            targetx: i32 = 0,
            targety: i32 = 0,
            sourcex: i32 = 0,
            sourcey: i32 = 0,
        } = .{},
    } = .{},
};

pub var state = YAZBG{};

pub fn init() !void {
    std.debug.print("init game\n", .{});
    state.gpallocator = GPA{};
    state.grid = Grid.init(state.gpallocator.allocator()) catch @panic("OOM");
    state.piece.next = PIECES.tetraminos[rnd.ng.random().intRangeAtMost(u32, 0, 6)];
    nextpiece();
    sfx.playmusic();
}

pub fn deinit() void {
    std.debug.print("deinit game\n", .{});
    state.grid.deinit();
    if (state.gpallocator.deinit() == .leak) {
        std.debug.print("leaked memory\n", .{});
    }
}

pub fn reset() void {
    std.debug.print("reset game\n", .{});
    state.lastmove = 0;
    state.progression.score = 0;
    state.progression.level = 0;
    state.progression.cleared = 0;
    state.progression.clearedperlevel = 0;
    state.progression.dropinterval = 2.0;
    state.piece.next = PIECES.tetraminos[rnd.ng.random().intRangeAtMost(u32, 0, 6)];
    state.piece.held = null;
    state.piece.slider = .{};
    state.grid.deinit();
    state.grid = Grid.init(state.gpallocator.allocator()) catch @panic("OOM");
    nextpiece();
    state.gameover = false;
    state.paused = false;
}

pub fn nextpiece() void {
    state.piece.current = state.piece.next;
    state.piece.next = PIECES.tetraminos[rnd.ng.random().intRangeAtMost(u32, 0, 6)];
    state.piece.x = 3;
    state.piece.y = 0;
    state.piece.r = 0;
    state.piece.swapped = false;

    if (!checkmove(state.piece.x, state.piece.y)) {
        for (0..Grid.HEIGHT) |r| {
            anim.linecleardown(r);
            sfx.playgameover();
        }

        state.piece.current = null;
        state.gameover = true;
    }
}

pub fn swappiece() bool {
    if (state.piece.swapped) {
        std.debug.print("already swapped\n", .{});
        return false;
    }
    if (state.piece.held) |held| {
        state.piece.held = state.piece.current;
        state.piece.current = held;
    } else {
        state.piece.held = state.piece.current;
        nextpiece();
    }
    state.piece.swapped = true;
    state.lastmove = sfx.ray.GetTime();
    return state.piece.swapped;
}

pub fn pause() void {
    if (state.gameover) return;
    state.paused = !state.paused;
    std.debug.print("game.paused {}\n", .{state.paused});
}

pub fn ghosty() i32 {
    var y = state.piece.y;
    while (checkmove(state.piece.x, y + 1)) : (y += 1) {}
    return y;
}

pub fn checkmove(x: i32, y: i32) bool {
    if (state.piece.current) |piece| {
        const shape = piece.shape[state.piece.r];
        for (shape, 0..) |row, j| {
            for (row, 0..) |cell, i| {
                if (cell) {
                    const gx = x + @as(i32, @intCast(j));
                    const gy = y + @as(i32, @intCast(i));
                    // cell is out of bounds

                    if (gx < 0 or gx >= Grid.WIDTH or gy < 0 or gy >= Grid.HEIGHT) {
                        return false;
                    }

                    const ix = @as(usize, @intCast(gx));
                    const iy = @as(usize, @intCast(gy));
                    // cell is already occupied via newcells
                    if (state.grid.cells[iy][ix]) |_| {
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
    var y = state.piece.y;
    while (checkmove(state.piece.x, y + 1)) : (y += 1) {}
    state.piece.y = y;
    if (state.piece.current) |piece| {
        const shape = piece.shape[state.piece.r];
        for (shape, 0..) |row, i| {
            for (row, 0..) |cell, j| {
                if (cell) {
                    const gx = state.piece.x + @as(i32, @intCast(i));
                    const gy = state.piece.y + @as(i32, @intCast(j));
                    if (gx >= 0 and gx < Grid.WIDTH and gy >= 0 and gy < Grid.HEIGHT) {
                        const ix = @as(usize, @intCast(gx));
                        const iy = @as(usize, @intCast(gy));
                        const ac = Animated.init(state.gpallocator.allocator(), ix, iy, piece.color) catch |err| {
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
    state.progression.clearedperlevel += cleared;
    return cleared;
}

// move piece right
pub fn right() bool {
    const x: i32 = state.piece.x + 1;
    const y = state.piece.y;
    if (!checkmove(x, y)) {
        return false;
    }
    slidepiece(x, y);
    state.lastmove = sfx.ray.GetTime();
    return true;
}

// move piece left
pub fn left() bool {
    const x: i32 = state.piece.x - 1;
    const y = state.piece.y;
    if (!checkmove(x, y)) {
        return false;
    }

    slidepiece(x, y);
    state.lastmove = sfx.ray.GetTime();
    return true;
}

// move piece down
pub fn down() bool {
    const x: i32 = state.piece.x;
    const y: i32 = state.piece.y + 1;
    if (!checkmove(x, y)) {
        return false;
    }
    slidepiece(x, y);
    state.lastmove = sfx.ray.GetTime();
    return true;
}

// rotate piece clockwise
pub fn rotate() bool {
    const oldr: u32 = state.piece.r;
    state.piece.r = (state.piece.r + 1) % 4; // increment and wrap around the rotation
    std.debug.print("rotation {} -> {}\n", .{ oldr, state.piece.r });

    // after rotation, the piece fits, return
    if (checkmove(state.piece.x, state.piece.y)) {
        state.lastmove = sfx.ray.GetTime();
        return true;
    }

    // try wall-kicks to fit the piece
    if (state.piece.current) |piece| {
        const kickData = piece.kicks[finddirection(oldr, state.piece.r)];

        // kick and check if the moved piece fits
        for (kickData) |kick| {
            state.piece.x += kick[0];
            state.piece.y += kick[1];

            if (checkmove(state.piece.x, state.piece.y)) {
                std.debug.print("kick\n", .{});
                state.lastmove = sfx.ray.GetTime();
                return true;
            }
            // revert the kick
            std.debug.print("failed kick\n", .{});
            state.piece.x -= kick[0];
            state.piece.y -= kick[1];
        }
    }

    // unkickable, revert the rotation and return false
    state.piece.r = oldr;
    return false;
}

pub fn frozen() bool {
    return state.gameover or state.paused;
}

pub fn dropready() bool {
    return !state.piece.slider.active and !frozen() and sfx.ray.GetTime() - state.lastmove >= state.progression.dropinterval;
}

// (0 for CW, 1 for CCW)
fn finddirection(oldr: u32, newr: u32) u32 {
    if (oldr > newr or (oldr == 0 and newr == 3) or (oldr == 3 and newr == 0)) return 1;
    return 0;
}

fn slidepiece(x: i32, y: i32) void {
    state.piece.slider.targetx = x;
    state.piece.slider.targety = y;
    state.piece.slider.sourcex = state.piece.x;
    state.piece.slider.sourcey = state.piece.y;
    state.piece.x = state.piece.slider.targetx;
    state.piece.y = state.piece.slider.targety;
    state.piece.slider.start_time = std.time.milliTimestamp();
    state.piece.slider.active = true;
}
