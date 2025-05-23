pub const tetramino = struct {
    shape: [4][4][4]bool,
    color: [4]u8,
    kicks: [2][5][2]i32,
    id: u32, // Unique identifier for each piece type
};

const o = false;
const X = true;
pub const tetraminos = [_]tetramino{
    // I - Line piece
    tetramino{
        .shape = .{
            .{ // Rotation 1
                .{ o, o, o, o },
                .{ X, X, X, X },
                .{ o, o, o, o },
                .{ o, o, o, o },
            },
            .{ // Rotation 2
                .{ o, o, X, o },
                .{ o, o, X, o },
                .{ o, o, X, o },
                .{ o, o, X, o },
            },
            // Remaining rotations are the same for I piece
            .{ // Rotation 3
                .{ o, o, o, o },
                .{ o, o, o, o },
                .{ X, X, X, X },
                .{ o, o, o, o },
            },
            .{ // Rotation 4
                .{ o, X, o, o },
                .{ o, X, o, o },
                .{ o, X, o, o },
                .{ o, X, o, o },
            },
        },
        .color = .{ 102, 191, 235, 255 },
        .id = 0,
        .kicks = .{
            // CW kicks
            .{
                .{ 0, 0 },
                .{ -2, 0 },
                .{ 1, 0 },
                .{ -2, -1 },
                .{ 1, 2 },
            },
            // CCW kicks
            .{
                .{ 0, 0 },
                .{ 2, 0 },
                .{ -1, 0 },
                .{ 2, 1 },
                .{ -1, -2 },
            },
        },
    },
    // O - Square piece (Only one unique rotation)
    tetramino{
        .shape = .{
            // All rotations are the same for O piece
            .{ // Rotation 1
                .{ X, X, o, o },
                .{ X, X, o, o },
                .{ o, o, o, o },
                .{ o, o, o, o },
            },
            .{ // Rotation 2
                .{ X, X, o, o },
                .{ X, X, o, o },
                .{ o, o, o, o },
                .{ o, o, o, o },
            },
            .{ // Rotation 3
                .{ X, X, o, o },
                .{ X, X, o, o },
                .{ o, o, o, o },
                .{ o, o, o, o },
            },
            .{ // Rotation 4
                .{ X, X, o, o },
                .{ X, X, o, o },
                .{ o, o, o, o },
                .{ o, o, o, o },
            },
        },
        .color = .{ 233, 229, 0, 255 },
        .id = 5,
        .kicks = .{
            // CW kicks
            .{
                .{ 0, 0 },
                .{ 0, 0 },
                .{ 0, 0 },
                .{ 0, 0 },
                .{ 0, 0 },
            },
            // CCW kicks
            .{
                .{ 0, 0 },
                .{ 0, 0 },
                .{ 0, 0 },
                .{ 0, 0 },
                .{ 0, 0 },
            },
        },
    },
    // S piece
    tetramino{
        .shape = .{
            .{ // Rotation 1
                .{ o, X, X, o },
                .{ X, X, o, o },
                .{ o, o, o, o },
                .{ o, o, o, o },
            },
            .{ // Rotation 2
                .{ X, o, o, o },
                .{ X, X, o, o },
                .{ o, X, o, o },
                .{ o, o, o, o },
            },
            // Remaining rotations are the same for S piece
            .{ // Rotation 3
                .{ o, X, X, o },
                .{ X, X, o, o },
                .{ o, o, o, o },
                .{ o, o, o, o },
            },
            .{ // Rotation 4
                .{ X, o, o, o },
                .{ X, X, o, o },
                .{ o, X, o, o },
                .{ o, o, o, o },
            },
        },
        .color = .{ 0, 150, 44, 255 },
        .id = 1,
        .kicks = .{
            // CW kicks
            .{
                .{ 0, 0 },
                .{ -1, 0 },
                .{ -1, 1 },
                .{ 0, -2 },
                .{ -1, -2 },
            },
            // CCW kicks
            .{
                .{ 0, 0 },
                .{ 1, 0 },
                .{ 1, -1 },
                .{ 0, 2 },
                .{ 1, 2 },
            },
        },
    },
    // Z piece
    tetramino{
        .shape = .{
            .{ // Rotation 1
                .{ X, X, o, o },
                .{ o, X, X, o },
                .{ o, o, o, o },
                .{ o, o, o, o },
            },
            .{ // Rotation 2
                .{ o, X, o, o },
                .{ X, X, o, o },
                .{ X, o, o, o },
                .{ o, o, o, o },
            },
            // Remaining rotations are the same for Z piece
            .{ // Rotation 3
                .{ X, X, o, o },
                .{ o, X, X, o },
                .{ o, o, o, o },
                .{ o, o, o, o },
            },
            .{ // Rotation 4
                .{ o, X, o, o },
                .{ X, X, o, o },
                .{ X, o, o, o },
                .{ o, o, o, o },
            },
        },
        .color = .{ 220, 41, 55, 255 },
        .id = 6,
        .kicks = .{
            // CW kicks
            .{
                .{ 0, 0 },
                .{ -1, 0 },
                .{ -1, 1 },
                .{ 0, -2 },
                .{ -1, -2 },
            },
            // CCW kicks
            .{
                .{ 0, 0 },
                .{ 1, 0 },
                .{ 1, -1 },
                .{ 0, 2 },
                .{ 1, 2 },
            },
        },
    },
    // T piece
    tetramino{
        .shape = .{
            .{ // Rotation 1
                .{ o, X, o, o },
                .{ X, X, X, o },
                .{ o, o, o, o },
                .{ o, o, o, o },
            },
            .{ // Rotation 2
                .{ X, o, o, o },
                .{ X, X, o, o },
                .{ X, o, o, o },
                .{ o, o, o, o },
            },
            .{ // Rotation 3
                .{ X, X, X, o },
                .{ o, X, o, o },
                .{ o, o, o, o },
                .{ o, o, o, o },
            },
            .{ // Rotation 4
                .{ o, X, o, o },
                .{ X, X, o, o },
                .{ o, X, o, o },
                .{ o, o, o, o },
            },
        },
        .color = .{ 220, 90, 220, 255 },
        .id = 2,
        .kicks = .{
            // CW kicks
            .{
                .{ 0, 0 },
                .{ -1, 0 },
                .{ -1, 1 },
                .{ 0, -2 },
                .{ -1, -2 },
            },
            // CCW kicks
            .{
                .{ 0, 0 },
                .{ 1, 0 },
                .{ 1, -1 },
                .{ 0, 2 },
                .{ 1, 2 },
            },
        },
    },
    // L piece
    tetramino{
        .shape = .{
            .{ // Rotation 1
                .{ o, o, X, o },
                .{ X, X, X, o },
                .{ o, o, o, o },
                .{ o, o, o, o },
            },
            .{ // Rotation 2
                .{ X, o, o, o },
                .{ X, o, o, o },
                .{ X, X, o, o },
                .{ o, o, o, o },
            },
            .{ // Rotation 3
                .{ X, X, X, o },
                .{ X, o, o, o },
                .{ o, o, o, o },
                .{ o, o, o, o },
            },
            .{ // Rotation 4
                .{ o, X, X, o },
                .{ o, o, X, o },
                .{ o, o, X, o },
                .{ o, o, o, o },
            },
        },
        .color = .{ 255, 161, 0, 255 },
        .id = 3,
        .kicks = .{
            // CW kicks
            .{
                .{ 0, 0 },
                .{ -1, 0 },
                .{ -1, 1 },
                .{ 0, -2 },
                .{ -1, -2 },
            },
            // CCW kicks
            .{
                .{ 0, 0 },
                .{ 1, 0 },
                .{ 1, -1 },
                .{ 0, 2 },
                .{ 1, 2 },
            },
        },
    },
    // J piece
    tetramino{
        .shape = .{
            .{ // Rotation 1
                .{ X, o, o, o },
                .{ X, X, X, o },
                .{ o, o, o, o },
                .{ o, o, o, o },
            },
            .{ // Rotation 2
                .{ X, X, o, o },
                .{ X, o, o, o },
                .{ X, o, o, o },
                .{ o, o, o, o },
            },
            .{ // Rotation 3
                .{ X, X, X, o },
                .{ o, o, X, o },
                .{ o, o, o, o },
                .{ o, o, o, o },
            },
            .{ // Rotation 4
                .{ o, X, o, o },
                .{ o, X, o, o },
                .{ X, X, o, o },
                .{ o, o, o, o },
            },
        },
        .color = .{ 0, 121, 241, 255 },
        .id = 4,
        .kicks = .{
            // CW kicks
            .{
                .{ 0, 0 },
                .{ -1, 0 },
                .{ -1, 1 },
                .{ 0, -2 },
                .{ -1, -2 },
            },
            // CCW kicks
            .{
                .{ 0, 0 },
                .{ 1, 0 },
                .{ 1, -1 },
                .{ 0, 2 },
                .{ 1, 2 },
            },
        },
    },
};
