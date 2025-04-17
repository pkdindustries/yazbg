const std = @import("std");

const anim = @import("animation.zig").Animated;
const Grid = @import("grid.zig").Grid;
const shapes = @import("pieces.zig");
const GPA = std.heap.GeneralPurposeAllocator(.{});
const events = @import("events.zig");

// ---------------------------------------------------------------------------
// Time handling
// ---------------------------------------------------------------------------

// The game logic does not obtain the current timestamp on its own.  Instead the
// outer loop (main.zig) calls `tick(now_ms)` once per frame to inject the
// monotonic time in milliseconds.  This makes the entire game state fully
// deterministic and unit‑testable.

// Return a monotonic timestamp in milliseconds.  This is used as the sole time
// source for gameplay logic so that the game code stays completely decoupled
// from rendering/audio libraries.

pub const YAZBG = struct {
    alloc: GPA = undefined,
    rng: std.Random.DefaultPrng = undefined,
    grid: *Grid = undefined,
    gameover: bool = false,
    paused: bool = false,
    // time of the last successful move (milliseconds, monotonic clock)
    lastmove_ms: i64 = 0,
    // latest timestamp pushed in via `tick()`
    current_time_ms: i64 = 0,
    progression: struct {
        score: i32 = 0,
        level: i32 = 0,
        // total lines cleared
        cleared: i32 = 0,
        // lines cleared since last level up
        clearedthislevel: i32 = 0,
        // time between automatic drops (in milliseconds)
        dropinterval_ms: i64 = 2_000,
    } = .{},
    // current, next and held piece shapes
    piece: struct {
        current: ?shapes.tetramino = null,
        next: ?shapes.tetramino = null,
        held: ?shapes.tetramino = null,
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

// Called once per frame by the host application.  All time‑dependent logic in
// the game state uses `state.current_time_ms`, supplied via this function.
pub fn tick(now_ms: i64) void {
    state.current_time_ms = now_ms;
}

pub fn init() !void {
    std.debug.print("init game\n", .{});
    state.alloc = GPA{};
    state.rng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        std.crypto.random.bytes(std.mem.asBytes(&seed)); // No `try` needed
        break :blk seed;
    });
    state.grid = Grid.init(state.alloc.allocator()) catch @panic("OOM");
    state.piece.next = shapes.tetraminos[state.rng.random().intRangeAtMost(u32, 0, 6)];
    nextpiece();
}

pub fn deinit() void {
    std.debug.print("deinit game\n", .{});
    state.grid.deinit();
    if (state.alloc.deinit() == .leak) {
        std.debug.print("leaked memory\n", .{});
    }
}

pub fn reset() void {
    std.debug.print("reset game\n", .{});
    state.lastmove_ms = 0;
    state.progression = .{};
    state.progression.dropinterval_ms = 2_000;
    state.piece = .{};
    state.piece.next = shapes.tetraminos[state.rng.random().intRangeAtMost(u32, 0, 6)];
    state.grid.deinit();
    state.grid = Grid.init(state.alloc.allocator()) catch @panic("OOM");
    nextpiece();
    state.gameover = false;
    state.paused = false;
}

pub fn nextpiece() void {
    state.piece.current = state.piece.next;
    state.piece.next = shapes.tetraminos[state.rng.random().intRangeAtMost(u32, 0, 6)];
    state.piece.x = 3;
    state.piece.y = 0;
    state.piece.r = 0;
    state.piece.swapped = false;
    if (!checkmove(state.piece.x, state.piece.y)) {
        for (0..Grid.HEIGHT) |r| {
            anim.linecleardown(r);
            events.push(.GameOver);
        }
        state.piece.current = null;
        state.gameover = true;
    }
}

pub fn swappiece() void {
    if (state.piece.swapped) {
        std.debug.print("already swapped\n", .{});
        return;
    }
    if (state.piece.held) |held| {
        state.piece.held = state.piece.current;
        state.piece.current = held;
    } else {
        state.piece.held = state.piece.current;
        nextpiece();
    }
    state.piece.swapped = true;
    state.lastmove_ms = state.current_time_ms;
    return;
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
pub fn harddrop() void {
    if (frozen()) return;

    // immediate sound effects (handled by audio subsystem)
    events.push(.Woosh);
    events.push(.Clack);

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
                        const ac = anim.init(state.alloc.allocator(), ix, iy, piece.color) catch |err| {
                            std.debug.print("failed to allocate cell: {}\n", .{err});
                            return;
                        };
                        state.grid.cells[iy][ix] = ac;
                    }
                }
            }
        }
    }

    state.lastmove_ms = state.current_time_ms;
    const cleared = state.grid.clear();
    std.debug.print("game.drop done {}\n", .{cleared});
    if (cleared > 0) {
        events.push(.{ .Clear = @as(u8, @intCast(cleared)) });
    }

    // spawn a new piece after the drop has settled
    nextpiece();

    return;
}

// move piece right
pub fn right() void {
    const x: i32 = state.piece.x + 1;
    const y = state.piece.y;
    if (!checkmove(x, y)) {
        events.push(.Error);
        return;
    }
    slidepiece(x, y);
    state.lastmove_ms = state.current_time_ms;
    events.push(.Click);
    return;
}

// move piece left
pub fn left() void {
    const x: i32 = state.piece.x - 1;
    const y = state.piece.y;
    if (!checkmove(x, y)) {
        events.push(.Error);
        return;
    }
    slidepiece(x, y);
    state.lastmove_ms = state.current_time_ms;
    events.push(.Click);
    return;
}

// move piece down
pub fn down() bool {
    const x: i32 = state.piece.x;
    const y: i32 = state.piece.y + 1;
    if (!checkmove(x, y)) {
        events.push(.Error);
        return false;
    }
    slidepiece(x, y);
    state.lastmove_ms = state.current_time_ms;
    events.push(.Click);
    return true;
}

// rotate piece clockwise
pub fn rotate() void {
    const oldr: u32 = state.piece.r;
    state.piece.r = (state.piece.r + 1) % 4; // increment and wrap around the rotation
    std.debug.print("rotation {} -> {}\n", .{ oldr, state.piece.r });

    // after rotation, the piece fits, return
    if (checkmove(state.piece.x, state.piece.y)) {
        state.lastmove_ms = state.current_time_ms;
        events.push(.Click);
        return;
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
                state.lastmove_ms = state.current_time_ms;
                events.push(.Click);
                return;
            }
            // revert the kick
            std.debug.print("failed kick\n", .{});
            state.piece.x -= kick[0];
            state.piece.y -= kick[1];
        }
    }

    // unkickable, revert the rotation and return false
    state.piece.r = oldr;
    events.push(.Error);
    return;
}

pub fn frozen() bool {
    return state.gameover or state.paused;
}

pub fn dropready() bool {
    return !state.piece.slider.active and !frozen() and
        (state.current_time_ms - state.lastmove_ms >= state.progression.dropinterval_ms);
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
