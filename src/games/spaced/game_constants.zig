// game_constants.zig - Spaced game constants
pub const PLAYER_SPEED: f32 = 200.0; // max pixels per second
pub const PLAYER_ACCELERATION: f32 = 400.0; // pixels per second^2
pub const PLAYER_DECELERATION: f32 = 200.0; // pixels per second^2
pub const PLAYER_TURN_SPEED: f32 = 2.0; // radians per second
pub const PLAYER_SIZE: f32 = 30.0; // player sprite size (doubled)

pub const ENEMY_SPEED: f32 = 50.0; // pixels per second
pub const ENEMY_SIZE: f32 = 20.0; // enemy sprite size (smaller than player)

pub const PLAYER_MAX_HEALTH: f32 = 100.0;
pub const PLAYER_START_HEALTH: f32 = 100.0;

pub const WORLD_WIDTH: f32 = 1920;
pub const WORLD_HEIGHT: f32 = 1280;

// Camera
pub const CAMERA_ZOOM: f32 = 1.0;

// Animation constants
pub const TURN_ANIMATION_TIME: f32 = 200.0; // milliseconds
pub const THRUST_ANIMATION_TIME: f32 = 100.0; // milliseconds
pub const BANKING_FACTOR: f32 = 0.3; // max banking angle multiplier
