const std = @import("std");

pub const AnimationState = struct {
    source_position: [2]f32,
    target_position: [2]f32,
    current_position: [2]f32,
    source_scale: f32,
    target_scale: f32,
    current_scale: f32,
    source_color: [4]u8,
    target_color: [4]u8,
    current_color: [4]u8,
    started_at: i64,
    duration: i64,
    start_after: i64 = 0, // Timestamp when animation should start (0 = start immediately)
    mode: enum { linear, easein, easeout },
};
