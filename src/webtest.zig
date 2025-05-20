const std = @import("std");
const ray = @import("raylib.zig");
const game = @import("game.zig");
const sfx = @import("sfx.zig");
const ecs = @import("ecs.zig");
const gfx = @import("gfx.zig");
pub fn main() !void {
    // initialize window
    const screen_width = 800;
    const screen_height = 600;

    ray.SetTraceLogLevel(ray.LOG_INFO);
    const allocator = std.heap.c_allocator;
    try game.init(allocator);
    defer game.deinit();

    try sfx.init(allocator);
    defer sfx.deinit();

    ecs.init(allocator);
    defer ecs.deinit();

    try gfx.init(allocator);
    // defer gfx.deinit();

    // set target fps
    // ray.SetTargetFPS(60);

    // main game loop
    while (!ray.WindowShouldClose()) {
        // begin drawing
        ray.BeginDrawing();
        defer ray.EndDrawing();

        // clear background
        ray.ClearBackground(ray.BLACK);
        const rect_width = 200;
        const rect_height = 100;
        const rect_x = @divFloor(screen_width - rect_width, 2);
        const rect_y = @divFloor(screen_height - rect_height, 2);

        ray.DrawRectangle(rect_x, rect_y, rect_width, rect_height, ray.RED);
        ray.DrawText("WebTest", rect_x + 50, rect_y + 40, 20, ray.WHITE);

        // display fps
        ray.DrawFPS(10, 10);
    }
}
