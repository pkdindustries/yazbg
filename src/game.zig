const std = @import("std");

const Grid = @import("grid.zig").Grid;
const shapes = @import("pieces.zig");
const events = @import("events.zig");
const CellLayer = @import("cellrenderer.zig").CellLayer;

pub const YAZBG = struct {
    alloc: std.mem.Allocator = undefined,
    rng: std.Random.DefaultPrng = undefined,
    grid: *Grid = undefined,
    cells: *CellLayer = undefined,
    gameover: bool = false,
    paused: bool = false,
    // time of the last successful move (milliseconds, monotonic clock)
    lastmove_ms: i64 = 0,
    // latest timestamp pushed in via `tick()`
    current_time_ms: i64 = 0,
    // current drop interval (ms), owned by level module and received via events
    dropinterval_ms: i64 = 2_000,
    // current, next and held piece shapes
    piece: struct {
        current: ?shapes.tetramino = null,
        next: ?shapes.tetramino = null,
        held: ?shapes.tetramino = null,
        swapped: bool = false,
        x: i32 = 0,
        y: i32 = 0,
        r: u32 = 0,
    } = .{},
};

pub var state = YAZBG{};

// Called once per frame by the host application.  All time‑dependent logic in
// the game state uses `state.current_time_ms`, supplied via this function.
pub fn tick(now_ms: i64) void {
    state.current_time_ms = now_ms;
}

pub fn init(allocator: std.mem.Allocator) !void {
    std.debug.print("init game\n", .{});

    state.alloc = allocator;

    state.rng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        std.crypto.random.bytes(std.mem.asBytes(&seed)); // No `try` needed
        break :blk seed;
    });

    state.cells = try CellLayer.init(allocator, Grid.WIDTH, Grid.HEIGHT);
    state.grid = try Grid.init(state.cells);

    state.piece.next = shapes.tetraminos[state.rng.random().intRangeAtMost(u32, 0, 6)];
    nextpiece();
}

pub fn deinit() void {
    std.debug.print("deinit game\n", .{});
    state.grid.deinit();
    state.cells.deinit();
}

pub fn reset() void {
    std.debug.print("reset game\n", .{});
    state.lastmove_ms = 0;
    state.piece = .{};
    state.piece.next = shapes.tetraminos[state.rng.random().intRangeAtMost(u32, 0, 6)];

    // Emit GridReset event before clearing the grid
    events.push(.GridReset, events.Source.Game);

    // Clear logical data in the grid instead of recreating it
    state.grid.clearall();

    nextpiece();
    state.gameover = false;
    state.paused = false;
}

pub fn nextpiece() void {
    state.piece.current = state.piece.next;
    state.piece.next = shapes.tetraminos[state.rng.random().intRangeAtMost(u32, 0, 6)];
    state.piece.x = 4;
    state.piece.y = 0;
    state.piece.r = 0;
    state.piece.swapped = false;

    if (!state.gameover) {
        events.push(.Spawn, events.Source.Game);
    }
    if (!checkmove(state.piece.x, state.piece.y)) {
        state.piece.current = null;
        state.gameover = true;
        events.push(.GameOver, events.Source.Game);
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

    events.push(.Hold, events.Source.Game);
    return;
}

pub fn pause() void {
    if (state.gameover) return;
    state.paused = !state.paused;
    std.debug.print("game.paused {}\n", .{state.paused});
}

pub fn checkmove(x: i32, y: i32) bool {
    return state.grid.checkmove(state.piece.current, x, y, state.piece.r);
}

// drop the piece to the bottom, clear lines and return num cleared
pub fn harddrop() void {
    if (frozen()) return;

    var y = state.piece.y;
    while (checkmove(state.piece.x, y + 1)) : (y += 1) {}
    state.piece.y = y;
    // Collect blocks for the PieceLocked event
    var blocks: [4]events.CellDataPos = undefined;
    var block_count: usize = 0;

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

                        // Store block position and color for event
                        if (block_count < blocks.len) {
                            blocks[block_count] = .{
                                .x = ix,
                                .y = iy,
                                .color = piece.color,
                            };
                            block_count += 1;
                        }

                        // Occupy cell in grid
                        state.grid.occupy(iy, ix, piece.color);
                    }
                }
            }
        }
    }

    // Emit PieceLocked event with block data before updating grid
    events.push(.{ .PieceLocked = .{ .blocks = blocks, .count = block_count } }, events.Source.Game);

    state.lastmove_ms = state.current_time_ms;
    const cleared = state.grid.clear();
    if (cleared > 0) {
        events.push(.{ .Clear = @as(u8, @intCast(cleared)) }, events.Source.Game);
    }

    // Piece is now locked into the grid.
    events.push(.Lock, events.Source.Game);

    // spawn a new piece after the drop has settled
    nextpiece();

    return;
}

// move piece right
pub fn right() void {
    const x: i32 = state.piece.x + 1;
    const y = state.piece.y;
    if (!checkmove(x, y)) {
        events.push(.Error, events.Source.Game);
        return;
    }
    state.piece.x = x;
    state.piece.y = y;
    state.lastmove_ms = state.current_time_ms;
    events.push(.MoveRight, events.Source.Game);
    return;
}

// move piece left
pub fn left() void {
    const x: i32 = state.piece.x - 1;
    const y = state.piece.y;
    if (!checkmove(x, y)) {
        events.push(.Error, events.Source.Game);
        return;
    }
    state.piece.x = x;
    state.piece.y = y;
    state.lastmove_ms = state.current_time_ms;
    events.push(.MoveLeft, events.Source.Game);
    return;
}

// move piece down
pub fn down() bool {
    const x: i32 = state.piece.x;
    const y: i32 = state.piece.y + 1;
    if (!checkmove(x, y)) {
        events.push(.Error, events.Source.Game);
        return false;
    }
    state.piece.x = x;
    state.piece.y = y;
    state.lastmove_ms = state.current_time_ms;
    events.push(.MoveDown, events.Source.Game);
    return true;
}

// rotate piece clockwise
pub fn rotate() void {
    const oldr: u32 = state.piece.r;
    state.piece.r = (state.piece.r + 1) % 4; // increment and wrap around the rotation

    // after rotation, the piece fits, return
    if (checkmove(state.piece.x, state.piece.y)) {
        state.lastmove_ms = state.current_time_ms;
        events.push(.Rotate, events.Source.Game);
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
                events.push(.Kick, events.Source.Game);
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
    events.push(.Error, events.Source.Game);
    return;
}

pub fn frozen() bool {
    return state.gameover or state.paused;
}

pub fn dropready() bool {
    return !frozen() and (state.current_time_ms - state.lastmove_ms >= state.dropinterval_ms);
}

// (0 for CW, 1 for CCW)
fn finddirection(oldr: u32, newr: u32) u32 {
    if (oldr > newr or (oldr == 0 and newr == 3) or (oldr == 3 and newr == 0)) return 1;
    return 0;
}

/// Handle progression events emitted by level (e.g., drop interval changes).
pub fn process(queue: *events.EventQueue) void {
    for (queue.items()) |rec| {
        // debug: print event, source, and timestamp
        switch (rec.event) {
            .DropInterval => |ms| {
                state.dropinterval_ms = ms;
            },
            .MoveLeft => left(),
            .MoveRight => right(),
            .MoveDown => if (!down()) harddrop(),
            .Rotate => rotate(),
            .HardDrop => harddrop(),
            .AutoDrop => if (!down()) harddrop(),
            .SwapPiece => swappiece(),
            .Pause => pause(),
            .Reset => reset(),
            else => {},
        }
    }
}
