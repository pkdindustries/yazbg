const std = @import("std");
const cellrenderer = @import("cellrenderer.zig");
const CellLayer = cellrenderer.CellLayer;
const Cell = cellrenderer.Cell;
const AnimationState = cellrenderer.AnimationState;

pub const Animator = struct {
    layer: *CellLayer,
    indices: std.ArrayList(usize),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, layer: *CellLayer) !Animator {
        return Animator{
            .allocator = allocator,
            .layer = layer,
            .indices = std.ArrayList(usize).init(allocator),
        };
    }

    pub fn countActiveAnimations(self: *const Animator) usize {
        return self.indices.items.len;
    }

    pub fn deinit(self: *Animator) void {
        self.indices.deinit();
    }

    pub fn startAnimation(self: *Animator, idx: usize, params: AnimationState) !void {
        const cell_ptr = &self.layer.cells[idx];
        cell_ptr.anim_state = params;
        cell_ptr.anim_state.?.animating = true;

        for (self.indices.items) |existing_idx| {
            if (existing_idx == idx) return;
        }

        try self.indices.append(idx);
    }

    pub fn stopAnimation(self: *Animator, idx: usize) void {
        const cell_ptr = &self.layer.cells[idx];
        cell_ptr.anim_state = null;

        for (self.indices.items, 0..) |existing_idx, i| {
            if (existing_idx == idx) {
                _ = self.indices.swapRemove(i);
                break;
            }
        }
    }

    pub fn step(self: *Animator, dt: f32) void {
        _ = dt; // we're using timestamps for now

        var i: usize = 0;
        while (i < self.indices.items.len) {
            const idx = self.indices.items[i];
            const cell_ptr = &self.layer.cells[idx];

            if (cell_ptr.anim_state) |*anim| {
                if (!anim.animating) {
                    _ = self.indices.swapRemove(i);
                    continue;
                }

                const now = std.time.milliTimestamp();
                
                // Check if we should start the animation yet
                if (now < anim.notbefore) {
                    // Not time to start yet, keep in the animation list but don't update
                    i += 1;
                    continue;
                }
                
                // If we just passed the notbefore time, update startedat to now
                if (anim.startedat < anim.notbefore) {
                    anim.startedat = now;
                }
                
                const elapsed = @as(f32, @floatFromInt(now - anim.startedat));
                const duration = @as(f32, @floatFromInt(anim.duration));
                var progress = std.math.clamp(elapsed / duration, 0.0, 1.0);

                switch (anim.mode) {
                    .linear => {},
                    .easein => progress = progress * progress,
                    .easeout => progress = 1.0 - (1.0 - progress) * (1.0 - progress),
                }

                // update position
                anim.position[0] = anim.source[0] + (anim.target[0] - anim.source[0]) * progress;
                anim.position[1] = anim.source[1] + (anim.target[1] - anim.source[1]) * progress;

                // color
                for (0..4) |c| {
                    const src = @as(f32, @floatFromInt(anim.color_source[c]));
                    const tgt = @as(f32, @floatFromInt(anim.color_target[c]));
                    const color_val = @as(u8, @intFromFloat(src + (tgt - src) * progress));
                    anim.color[c] = color_val;
                }

                // finished?
                if (elapsed >= duration) {
                    anim.position = anim.target;
                    anim.color = anim.color_target;
                    anim.scale = 1.0;
                    anim.animating = false;

                    cell_ptr.anim_state = null;

                    // remove from active animations list
                    _ = self.indices.swapRemove(i);
                    continue;
                }
            } else {
                _ = self.indices.swapRemove(i);
                continue;
            }

            i += 1;
        }
    }
};
