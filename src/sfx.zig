// sfx.zig - Game-agnostic sound effects and music system
pub const ray = @import("raylib.zig");
const std = @import("std");
const builtin = @import("builtin");
const target = builtin.target;

const MAX_INSTANCES = 10;

// ---------------------------------------------------------------------------
// Sound Configuration Types
// ---------------------------------------------------------------------------

pub const SoundConfig = struct {
    path: [*:0]const u8,
    volume: f32 = 1.0,
    allow_overlap: bool = true,
};

pub const MusicConfig = struct {
    path: [*:0]const u8,
    volume: f32 = 0.15,
    loop: bool = true,
};

pub const AudioConfig = struct {
    sounds: []const SoundConfig,
    music: []const MusicConfig,
    master_volume: f32 = 1.0,
    sound_volume: f32 = 0.5,
    music_volume: f32 = 0.15,
};

// ---------------------------------------------------------------------------
// Sound Bank for Concurrent Playback
// ---------------------------------------------------------------------------

const SoundBank = struct {
    base: ray.Sound,
    instances: [MAX_INSTANCES]ray.Sound,
    current: usize = 0,
    config: SoundConfig,
};

// ---------------------------------------------------------------------------
// Audio System State
// ---------------------------------------------------------------------------

var allocator: std.mem.Allocator = undefined;
var sounds: std.StringHashMap(SoundBank) = undefined;
var music: std.ArrayList(ray.Music) = undefined;
var event_mappings: std.AutoHashMap(usize, []const u8) = undefined;
var current_music_index: usize = 0;
var sound_volume: f32 = 0.5;
var music_volume: f32 = 0.15;
var master_volume: f32 = 1.0;
var muted: bool = false;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn init(alloc: std.mem.Allocator) !void {
    allocator = alloc;
    ray.InitAudioDevice();
    
    sounds = std.StringHashMap(SoundBank).init(allocator);
    music = std.ArrayList(ray.Music).init(allocator);
    event_mappings = std.AutoHashMap(usize, []const u8).init(allocator);
}

pub fn deinit() void {
    // Unload all sounds
    var sound_iter = sounds.iterator();
    while (sound_iter.next()) |entry| {
        const bank = entry.value_ptr;
        // Unload aliases first
        for (bank.instances) |instance| {
            ray.UnloadSoundAlias(instance);
        }
        // Then unload base sound
        ray.UnloadSound(bank.base);
    }
    sounds.deinit();
    
    // Unload all music
    for (music.items) |m| {
        ray.UnloadMusicStream(m);
    }
    music.deinit();
    
    // Clear event mappings
    var mapping_iter = event_mappings.iterator();
    while (mapping_iter.next()) |entry| {
        allocator.free(entry.value_ptr.*);
    }
    event_mappings.deinit();
    
    ray.CloseAudioDevice();
}

// Load audio configuration
pub fn loadConfig(config: AudioConfig) !void {
    // Set volumes
    master_volume = config.master_volume;
    sound_volume = config.sound_volume;
    music_volume = config.music_volume;
    
    // Load sounds
    for (config.sounds) |sound_config| {
        try loadSound(sound_config);
    }
    
    // Load music
    for (config.music) |music_config| {
        try loadMusic(music_config);
    }
}

// Map an event type to a sound
pub fn mapEventToSound(comptime EventType: type, event: EventType, sound_name: []const u8) !void {
    const event_id = @intFromEnum(event);
    const name_copy = try allocator.dupe(u8, sound_name);
    try event_mappings.put(event_id, name_copy);
}

// Process events and play corresponding sounds
pub fn processEvent(event: anytype) void {
    const event_id = @intFromEnum(event);
    if (event_mappings.get(event_id)) |sound_name| {
        playSound(sound_name);
    }
}

// ---------------------------------------------------------------------------
// Sound Management
// ---------------------------------------------------------------------------

fn loadSound(config: SoundConfig) !void {
    if (!ray.IsAudioDeviceReady() or target.os.tag == .linux) return;
    
    var bank = SoundBank{
        .base = ray.LoadSound(config.path),
        .instances = undefined,
        .config = config,
    };
    
    // Create aliases for concurrent playback
    for (0..MAX_INSTANCES) |i| {
        bank.instances[i] = ray.LoadSoundAlias(bank.base);
    }
    
    // Extract filename as key
    const path_str = std.mem.sliceTo(config.path, 0);
    const basename = std.fs.path.basename(path_str);
    const name = std.fs.path.stem(basename);
    
    try sounds.put(name, bank);
}

pub fn playSound(name: []const u8) void {
    if (muted) return;
    
    if (sounds.getPtr(name)) |bank| {
        const instance = &bank.instances[bank.current];
        ray.SetSoundVolume(instance.*, sound_volume * master_volume * bank.config.volume);
        ray.PlaySound(instance.*);
        
        // Move to next instance for concurrent playback
        bank.current = (bank.current + 1) % MAX_INSTANCES;
    }
}

// ---------------------------------------------------------------------------
// Music Management
// ---------------------------------------------------------------------------

fn loadMusic(config: MusicConfig) !void {
    if (!ray.IsAudioDeviceReady() or target.os.tag == .linux) return;
    
    const m = ray.LoadMusicStream(config.path);
    try music.append(m);
    
    // Start playing first track if this is the first music loaded
    if (music.items.len == 1) {
        playMusic();
    }
}

pub fn playMusic() void {
    if (music.items.len == 0) return;
    
    const current = music.items[current_music_index];
    ray.SetMusicVolume(current, music_volume * master_volume);
    ray.PlayMusicStream(current);
}

pub fn nextMusic() void {
    if (music.items.len == 0) return;
    
    ray.StopMusicStream(music.items[current_music_index]);
    current_music_index = (current_music_index + 1) % music.items.len;
    playMusic();
}

pub fn stopMusic() void {
    if (music.items.len == 0) return;
    ray.StopMusicStream(music.items[current_music_index]);
}

pub fn updateMusic() void {
    if (music.items.len == 0) return;
    ray.UpdateMusicStream(music.items[current_music_index]);
}

// ---------------------------------------------------------------------------
// Volume Control
// ---------------------------------------------------------------------------

pub fn toggleMute() void {
    muted = !muted;
    if (muted) {
        ray.SetMusicVolume(music.items[current_music_index], 0);
    } else {
        ray.SetMusicVolume(music.items[current_music_index], music_volume * master_volume);
    }
}

pub fn setSoundVolume(volume: f32) void {
    sound_volume = std.math.clamp(volume, 0.0, 1.0);
}

pub fn setMusicVolume(volume: f32) void {
    music_volume = std.math.clamp(volume, 0.0, 1.0);
    if (music.items.len > 0) {
        ray.SetMusicVolume(music.items[current_music_index], music_volume * master_volume);
    }
}

pub fn setMasterVolume(volume: f32) void {
    master_volume = std.math.clamp(volume, 0.0, 1.0);
    if (music.items.len > 0) {
        ray.SetMusicVolume(music.items[current_music_index], music_volume * master_volume);
    }
}