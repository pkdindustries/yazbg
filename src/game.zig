const std = @import("std");

const Grid = @import("grid.zig").Grid;
const shapes = @import("pieces.zig");
const events = @import("events.zig");
const level = @import("level.zig");

// helper: pick a random tetramino
fn randomTetramino(rng: *std.Random.DefaultPrng) shapes.tetramino {
    return shapes.tetraminos[rng.random().intRangeAtMost(u32, 0, 6)];
}

// game state
pub const YAZBG = struct {
    alloc: std.mem.Allocator = undefined,
    rng: std.Random.DefaultPrng = undefined,
    grid: Grid = undefined,
    gameover: bool = false,
    paused: bool = false,
    lastmove_ms: i64 = 0, // last successful move timestamp
    current_time_ms: i64 = 0, // latest timestamp from tick()

    // piece state
    piece: struct {
        current: ?shapes.tetramino = null,
        next: ?shapes.tetramino = null,
        held: ?shapes.tetramino = null,
        // Removed swapped flag to allow multiple swaps
        x: i32 = 0,
        y: i32 = 0,
        r: u32 = 0,
    } = .{},

    progression: level.Progression = level.Progression{},
};

pub var state = YAZBG{};

// update current time
pub fn tick(now_ms: i64) void {
    state.current_time_ms = now_ms;
}

// initialize game state
pub fn init(allocator: std.mem.Allocator) !void {
    // std.debug.print("init game\n", .{});
    state.alloc = allocator;

    // init rng with random seed
    state.rng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        std.crypto.random.bytes(std.mem.asBytes(&seed));
        break :blk seed;
    });

    state.grid = Grid.init();
    state.piece.next = randomTetramino(&state.rng);
    nextpiece();
}

// clean up resources
pub fn deinit() void {
    // std.debug.print("deinit game\n", .{});
}

// reset game to initial state
pub fn reset() void {
    // std.debug.print("reset game\n", .{});
    state.progression.reset();
    state.lastmove_ms = 0;
    // Initialize piece state without the swapped flag
    state.piece = .{};
    state.piece.next = randomTetramino(&state.rng);

    events.push(.GridReset, events.Source.Game);
    state.grid.clearall();

    nextpiece();
    state.gameover = false;
    state.paused = false;
}

// get ghost piece y position
fn calculateGhostY() i32 {
    var ghost_y = state.piece.y;
    while (checkmove(state.piece.x, ghost_y + 1)) : (ghost_y += 1) {}
    return ghost_y;
}

// emit position update event
fn pushUpdate() void {
    if (state.piece.current) |piece| {
        var piece_index: u32 = 0;
        for (shapes.tetraminos, 0..) |t, i| {
            if (t.id == piece.id) {
                piece_index = @as(u32, @intCast(i));
                break;
            }
        }

        events.push(.{ .PlayerPositionUpdated = .{
            .x = state.piece.x,
            .y = state.piece.y,
            .rotation = state.piece.r,
            .ghost_y = calculateGhostY(),
            .piece_index = piece_index,
            .next_piece_index = 1,
            .hold_piece_index = 2,
        } }, events.Source.Game);
    }
}

// spawn next piece
pub fn nextpiece() void {
    state.piece.current = state.piece.next;
    state.piece.next = randomTetramino(&state.rng);
    state.piece.x = 4;
    state.piece.y = 0;
    state.piece.r = 0;
    // Removed setting swapped=false to allow multiple swaps

    if (!state.gameover) {
        pushUpdate();
        events.push(.Spawn, events.Source.Game);
    }

    // check if new piece collides (game over)
    if (!checkmove(state.piece.x, state.piece.y)) {
        state.piece.current = null;
        state.gameover = true;
        events.push(.GameOver, events.Source.Game);
    }
}

// swap current and held pieces
pub fn swappiece() void {
    // Removed the swapped flag check to allow multiple swaps

    if (state.piece.held) |held| {
        state.piece.held = state.piece.current;
        state.piece.current = held;
    } else {
        state.piece.held = state.piece.current;
        nextpiece();
    }

    // No longer setting the swapped flag
    state.lastmove_ms = state.current_time_ms;
    pushUpdate();
    events.push(.Hold, events.Source.Game);
}

// toggle pause state
pub fn pause() void {
    if (state.gameover) return;
    state.paused = !state.paused;
}

// check if piece can move to position
pub fn checkmove(x: i32, y: i32) bool {
    return state.grid.checkmove(state.piece.current, x, y, state.piece.r);
}

// drop piece to lowest valid position
fn dropToBottom() void {
    var y = state.piece.y;
    while (checkmove(state.piece.x, y + 1)) : (y += 1) {}
    state.piece.y = y;
    pushUpdate();
}

// result type for lock piece operation
const LockResult = struct { 
    blocks: [4]events.CellDataPos, 
    count: usize,
};

// lock piece blocks into the grid
fn lockPiece() LockResult {
    var result = LockResult{
        .blocks = undefined,
        .count = 0,
    };
    
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
                        
                        if (result.count < result.blocks.len) {
                            result.blocks[result.count] = .{ .x = ix, .y = iy, .color = piece.color };
                            result.count += 1;
                        }
                        
                        state.grid.occupyBlocks(ix, iy, piece.color);
                    }
                }
            }
        }
    }
    
    return result;
}

// clear completed lines and update progression
fn clearCompletedLines() void {
    const cleared = state.grid.clear();
    if (cleared > 0) {
        state.progression.clear(@as(u8, @intCast(cleared)));
        events.push(.{ .Clear = @as(u8, @intCast(cleared)) }, events.Source.Game);
    }
}

// drop piece to bottom and clear lines
pub fn harddrop() void {
    if (frozen()) return;
    
    // drop to bottom
    dropToBottom();
    
    // lock piece and get block positions
    const lock_result = lockPiece();
    
    // emit events
    events.push(.HardDropEffect, events.Source.Game);
    if (lock_result.count > 0) {
        events.push(.{ .PieceLocked = .{ 
            .blocks = lock_result.blocks, 
            .count = lock_result.count 
        } }, events.Source.Game);
    }
    
    // update timing
    state.lastmove_ms = state.current_time_ms;
    
    // clear lines
    clearCompletedLines();
    
    // spawn next piece
    nextpiece();
}

// handle piece movement
fn move(dx: i32, dy: i32) bool {
    const x = state.piece.x + dx;
    const y = state.piece.y + dy;

    if (!checkmove(x, y)) {
        events.push(.Error, events.Source.Game);
        return false;
    }

    state.piece.x = x;
    state.piece.y = y;
    state.lastmove_ms = state.current_time_ms;
    pushUpdate();
    return true;
}

// move piece right
pub fn right() void {
    _ = move(1, 0);
}

// move piece left
pub fn left() void {
    _ = move(-1, 0);
}

// move piece down
pub fn down() bool {
    return move(0, 1);
}

// rotate piece
pub fn rotate(ccw: bool) void {
    const oldr = state.piece.r;

    // adjust rotation
    if (ccw) {
        state.piece.r = (state.piece.r + 3) % 4; // -1 mod 4 = +3 mod 4
    } else {
        state.piece.r = (state.piece.r + 1) % 4;
    }

    // check if rotation works
    if (checkmove(state.piece.x, state.piece.y)) {
        state.lastmove_ms = state.current_time_ms;
        pushUpdate();
        return;
    }

    // try wall kicks
    if (state.piece.current) |piece| {
        const kickIndex: usize = if (ccw) 0 else 1;
        const kickData = piece.kicks[kickIndex];

        // try each kick position
        for (kickData) |kick| {
            state.piece.x += kick[0];
            state.piece.y += kick[1];

            if (checkmove(state.piece.x, state.piece.y)) {
                state.lastmove_ms = state.current_time_ms;
                events.push(.Kick, events.Source.Game);
                pushUpdate();
                return;
            }

            // revert failed kick
            state.piece.x -= kick[0];
            state.piece.y -= kick[1];
        }
    }

    // unkickable, revert rotation
    state.piece.r = oldr;
    events.push(.Error, events.Source.Game);
}

// check if game is frozen (paused or over)
pub fn frozen() bool {
    return state.gameover or state.paused;
}

// check if piece should drop
pub fn dropready() bool {
    return !frozen() and (state.current_time_ms - state.lastmove_ms >= state.progression.dropinterval_ms);
}

// process game events
pub fn process(queue: *events.EventQueue) void {
    for (queue.items()) |rec| {
        switch (rec.event) {
            .MoveLeft => left(),
            .MoveRight => right(),
            .MoveDown => if (!down()) harddrop(),
            .Rotate => rotate(true),
            .RotateCCW => rotate(false),
            .HardDrop => harddrop(),
            .AutoDrop => if (!down()) harddrop(),
            .SwapPiece => swappiece(),
            .Pause => pause(),
            .Reset => reset(),
            else => {},
        }
    }
}
