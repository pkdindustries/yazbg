// game_audio.zig - Audio configuration and event mapping for the tetris game
const std = @import("std");
const sfx = @import("sfx.zig");
const events = @import("events.zig");

// ---------------------------------------------------------------------------
// Audio Configuration
// ---------------------------------------------------------------------------

pub const audio_config = sfx.AudioConfig{
    .sounds = &[_]sfx.SoundConfig{
        .{ .path = "resources/sfx/deny.mp3", .volume = 0.7 },
        .{ .path = "resources/sfx/clack.mp3", .volume = 0.8 },
        .{ .path = "resources/sfx/click.mp3", .volume = 0.6 },
        .{ .path = "resources/sfx/clear.mp3", .volume = 1.0 },
        .{ .path = "resources/sfx/level.mp3", .volume = 1.0 },
        .{ .path = "resources/sfx/woosh.mp3", .volume = 0.5 },
        .{ .path = "resources/sfx/win.mp3", .volume = 1.0 },
        .{ .path = "resources/sfx/gameover.mp3", .volume = 1.0 },
    },
    .music = &[_]sfx.MusicConfig{
        .{ .path = "resources/music/fast.mp3" },
        .{ .path = "resources/music/grievous.mp3" },
        .{ .path = "resources/music/level0.mp3" },
        .{ .path = "resources/music/lieu.mp3" },
        .{ .path = "resources/music/newbit.mp3" },
        .{ .path = "resources/music/wonder.mp3" },
    },
    .master_volume = 1.0,
    .sound_volume = 0.5,
    .music_volume = 0.15,
};

// ---------------------------------------------------------------------------
// Event-to-Sound Mapping
// ---------------------------------------------------------------------------

fn getEventSound(event: events.Event) ?[]const u8 {
    return switch (event) {
        // Movement sounds
        .MoveLeft => "click",
        .MoveRight => "click",
        .MoveDown => "click",
        
        // Rotation sounds
        .Rotate, .RotateCCW => "woosh",
        
        // Action sounds
        .HardDropEffect => "woosh",
        .SwapPiece => "click",
        .Pause => "click",
        
        // Game events
        .Error => "deny",
        .Clear => "clear",
        .Win => "win",
        .LevelUp => "level",
        .GameOver => "gameover",
        .Kick => "clack",
        .PieceLocked => "clack",
        
        // Events without sounds
        else => null,
    };
}

// ---------------------------------------------------------------------------
// Process Events (with special handling)
// ---------------------------------------------------------------------------

pub fn processEvents(queue: *events.EventQueue) void {
    for (queue.items()) |rec| {
        // Play sound for event if mapped
        if (getEventSound(rec.event)) |sound_name| {
            sfx.playSound(sound_name);
        }
        
        // Special handling for events that need additional actions
        switch (rec.event) {
            .LevelUp => {
                // Also advance to next music track
                sfx.nextMusic();
            },
            .Reset => {
                // Reset to first music track
                sfx.stopMusic();
                sfx.playMusic();
            },
            .MuteAudio => {
                sfx.toggleMute();
            },
            .NextMusic => {
                sfx.nextMusic();
            },
            else => {},
        }
    }
}