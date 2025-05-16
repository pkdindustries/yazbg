const std = @import("std");

// Core data structure for representing a cell in the grid
// Contains only the essential data needed for game logic
pub const CellData = struct {
    // RGBA color value (packed as u32)
    color: u32,

    // Create a CellData from an RGBA array
    pub fn fromRgba(rgba: [4]u8) CellData {
        return CellData{
            .color = @as(u32, rgba[0]) << 24 |
                @as(u32, rgba[1]) << 16 |
                @as(u32, rgba[2]) << 8 |
                @as(u32, rgba[3]),
        };
    }

    // Convert CellData color back to RGBA array
    pub fn toRgba(self: CellData) [4]u8 {
        return .{
            @truncate((self.color >> 24) & 0xFF),
            @truncate((self.color >> 16) & 0xFF),
            @truncate((self.color >> 8) & 0xFF),
            @truncate(self.color & 0xFF),
        };
    }
};

test "CellData color conversion" {
    const original = [4]u8{ 255, 128, 64, 255 };
    const cell = CellData.fromRgba(original);
    const converted = cell.toRgba();

    try std.testing.expectEqual(original[0], converted[0]);
    try std.testing.expectEqual(original[1], converted[1]);
    try std.testing.expectEqual(original[2], converted[2]);
    try std.testing.expectEqual(original[3], converted[3]);
}
