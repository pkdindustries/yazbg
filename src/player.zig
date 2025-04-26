const std = @import("std");
const animation = @import("animation.zig");
const game = @import("game.zig");
const Grid = @import("grid.zig").Grid;

/// Animated player piece blocks
pub const PlayerPiece = struct {
    blocks: [4]?*animation.Animated = [_]?*animation.Animated{null} ** 4,
    ghost_blocks: [4]?*animation.Animated = [_]?*animation.Animated{null} ** 4,
    active: bool = false,
    duration: i64 = 50, // ms
    anim_pool: *animation.AnimationPool = undefined,
    cellsize: i32 = 35,

    /// Initialize player piece animation
    pub fn init(pool: *animation.AnimationPool, cell_size: i32) PlayerPiece {
        return .{
            .anim_pool = pool,
            .cellsize = cell_size,
        };
    }

    /// Release all animations and resources
    pub fn cleanup(self: *PlayerPiece) void {
        // Clean up player piece animations
        for (&self.blocks) |*block_ptr| {
            if (block_ptr.*) |block| {
                self.anim_pool.release(block);
                block_ptr.* = null;
            }
        }
        
        // Clean up ghost piece animations
        for (&self.ghost_blocks) |*block_ptr| {
            if (block_ptr.*) |block| {
                self.anim_pool.release(block);
                block_ptr.* = null;
            }
        }
        
        self.active = false;
    }

    /// Update player piece animation for movement
    pub fn updateAnimation(self: *PlayerPiece, sourceX: i32, sourceY: i32, targetX: i32, targetY: i32) void {
        if (game.state.piece.current) |current_piece| {
            const shape = current_piece.shape[game.state.piece.r];
            var block_index: usize = 0;
            
            // Release any existing blocks first
            for (&self.blocks) |*block_ptr| {
                if (block_ptr.*) |block| {
                    self.anim_pool.release(block);
                    block_ptr.* = null;
                }
            }
            
            // Create new animated blocks for the player piece
            for (shape, 0..) |row, i| {
                for (row, 0..) |cell, j| {
                    if (cell and block_index < self.blocks.len) {
                        const gridX = i;
                        const gridY = j;
                        
                        // Create a new animated block
                        if (self.anim_pool.create(0, 0, current_piece.color)) |block| {
                            // Calculate positions
                            const cellSourceX = @as(f32, @floatFromInt(sourceX + @as(i32, @intCast(gridX)) * self.cellsize));
                            const cellSourceY = @as(f32, @floatFromInt(sourceY + @as(i32, @intCast(gridY)) * self.cellsize));
                            const cellTargetX = @as(f32, @floatFromInt(targetX + @as(i32, @intCast(gridX)) * self.cellsize));
                            const cellTargetY = @as(f32, @floatFromInt(targetY + @as(i32, @intCast(gridY)) * self.cellsize));
                            
                            // Set animation properties
                            block.source = .{ cellSourceX, cellSourceY };
                            block.position = .{ cellSourceX, cellSourceY };
                            block.target = .{ cellTargetX, cellTargetY };
                            block.duration = self.duration;
                            block.mode = .easeinout;
                            block.start();
                            
                            // Store the block
                            self.blocks[block_index] = block;
                            block_index += 1;
                        }
                    }
                }
            }
            
            self.active = true;
        }
    }

    /// Create/update ghost piece
    pub fn updateGhost(self: *PlayerPiece) void {
        if (game.state.piece.current) |current_piece| {
            const shape = current_piece.shape[game.state.piece.r];
            const ghostY = game.ghosty() * self.cellsize;
            const playerX = game.state.piece.x * self.cellsize;
            var block_index: usize = 0;
            
            // Release any existing ghost blocks first
            for (&self.ghost_blocks) |*block_ptr| {
                if (block_ptr.*) |block| {
                    self.anim_pool.release(block);
                    block_ptr.* = null;
                }
            }
            
            // Create ghost blocks
            for (shape, 0..) |row, i| {
                for (row, 0..) |cell, j| {
                    if (cell and block_index < self.ghost_blocks.len) {
                        const gridX = i;
                        const gridY = j;
                        
                        // Create semi-transparent ghost block
                        const ghostColor = .{ current_piece.color[0], current_piece.color[1], current_piece.color[2], 60 };
                        if (self.anim_pool.create(0, 0, ghostColor)) |block| {
                            // Set position directly (no animation for ghost)
                            const cellX = @as(f32, @floatFromInt(playerX + @as(i32, @intCast(gridX)) * self.cellsize));
                            const cellY = @as(f32, @floatFromInt(ghostY + @as(i32, @intCast(gridY)) * self.cellsize));
                            
                            block.source = .{ cellX, cellY };
                            block.position = .{ cellX, cellY };
                            block.target = .{ cellX, cellY };
                            block.animating = false;
                            
                            // Store the block
                            self.ghost_blocks[block_index] = block;
                            block_index += 1;
                        }
                    }
                }
            }
        }
    }

    /// Process animation updates
    pub fn update(self: *PlayerPiece) void {
        // Check if inactive and current piece exists - need to create animations
        if (!self.active and game.state.piece.current != null) {
            const baseX = game.state.piece.x * self.cellsize;
            const baseY = game.state.piece.y * self.cellsize;
            
            // Initialize player piece at current position (no animation)
            self.updateAnimation(baseX, baseY, baseX, baseY);
            
            // Set blocks to not animate (instant positioning)
            for (self.blocks) |block_opt| {
                if (block_opt) |block| {
                    block.animating = false;
                }
            }
        }
        
        // Update ghost piece
        self.updateGhost();
        
        // Process animations
        var all_done = true;
        for (self.blocks) |block_opt| {
            if (block_opt) |block| {
                if (block.animating) {
                    const now = std.time.milliTimestamp();
                    block.lerp(now);
                    
                    if (block.animating) {
                        all_done = false;
                    }
                }
            }
        }
        
        // If all animations are done, mark player piece as inactive
        if (all_done and self.active) {
            self.active = false;
        }
    }
    
    /// Handle movement event - start slide animation
    pub fn startSlide(self: *PlayerPiece, dx: i32, dy: i32) void {
        if (game.state.piece.current == null) return;
        
        // Calculate target positions for the new piece position
        const targetX = game.state.piece.x * self.cellsize;
        const targetY = game.state.piece.y * self.cellsize;
        
        // Calculate source positions (where the animation starts)
        const sourceX = targetX + dx * self.cellsize;
        const sourceY = targetY + dy * self.cellsize;
        
        // Update player piece animations
        self.updateAnimation(sourceX, sourceY, targetX, targetY);
    }
};