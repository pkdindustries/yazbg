// layers.zig - Adapts the existing game rendering to the layer system
const common = @import("common.zig");
const std = common.std;
const components = common.components;
const ecs = common.ecs;
const gfx = common.gfx;
const ray = common.ray;
const shaders = common.shaders;
const animsys = common.animsys;
const collisionsys = common.collisionsys;
const events = common.events;
const constants = common.game_constants;

const game = @import("game.zig");
const hud = @import("hud.zig");
const playersys = @import("systems/player.zig");
const gridsvc = @import("systems/gridsvc.zig");
const previewsys = @import("systems/preview.zig");
const pieces = @import("pieces.zig");
const ecsroot = @import("ecs");

// ---------------------------------------------------------------------------
// Background Layer
// ---------------------------------------------------------------------------

pub const BackgroundContext = struct {
    index: usize = 0,
    texture: [8]ray.Texture2D = undefined,
    shader_entity: ecsroot.Entity = undefined,
    warp_end_ms: i64 = 0,
    level: u8 = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*BackgroundContext {
        const self = try allocator.create(BackgroundContext);
        self.* = .{ .allocator = allocator };

        // Load background textures
        self.texture[0] = ray.LoadTexture("resources/texture/starfield.png");
        self.texture[1] = ray.LoadTexture("resources/texture/starfield2.png");
        self.texture[2] = ray.LoadTexture("resources/texture/nebula.png");
        self.texture[3] = ray.LoadTexture("resources/texture/nebula2.png");
        self.texture[4] = ray.LoadTexture("resources/texture/bluestars.png");
        self.texture[5] = ray.LoadTexture("resources/texture/bokefall.png");
        self.texture[6] = ray.LoadTexture("resources/texture/starmap.png");
        self.texture[7] = ray.LoadTexture("resources/texture/warpgate.png");

        // Create entity for shader
        self.shader_entity = ecs.createEntity();
        try shaders.addShaderToEntity(self.shader_entity, "warp");

        // Set initial shader parameters
        var shader_component = ecs.getUnchecked(components.Shader, self.shader_entity);
        try shader_component.setFloat("seconds", 0.0);
        try shader_component.setFloat("freqX", 10.0);
        try shader_component.setFloat("freqY", 10.0);
        try shader_component.setFloat("ampX", 2.0);
        try shader_component.setFloat("ampY", 2.0);
        try shader_component.setFloat("speedX", 0.15);
        try shader_component.setFloat("speedY", 0.15);

        const size = [2]f32{
            @floatFromInt(gfx.Window.OGWIDTH * gfx.Window.SCALE),
            @floatFromInt(gfx.Window.OGHEIGHT * gfx.Window.SCALE),
        };
        try shader_component.setVec2("size", size);

        return self;
    }

    pub fn deinit(self: *BackgroundContext) void {
        // Unload all textures
        for (self.texture) |texture| {
            ray.UnloadTexture(texture);
        }
        // Destroy shader entity
        ecs.destroyEntity(self.shader_entity);
        self.allocator.destroy(self);
    }

    pub fn updateShader(self: *BackgroundContext) !void {
        var shader_component = ecs.getUnchecked(components.Shader, self.shader_entity);

        const now = std.time.milliTimestamp();
        if (self.warp_end_ms > now) {
            // Intense warp effect
            try shader_component.setFloat("freqX", 25.0);
            try shader_component.setFloat("freqY", 25.0);
            try shader_component.setFloat("ampX", 10.0);
            try shader_component.setFloat("ampY", 10.0);
            try shader_component.setFloat("speedX", 25.0);
            try shader_component.setFloat("speedY", 25.0);
        } else {
            // Normal warp effect
            const speed_factor = 0.15 * (@as(f32, @floatFromInt(self.level)) + 2.0);
            try shader_component.setFloat("freqX", 10.0);
            try shader_component.setFloat("freqY", 10.0);
            try shader_component.setFloat("ampX", 2.0);
            try shader_component.setFloat("ampY", 2.0);
            try shader_component.setFloat("speedX", speed_factor);
            try shader_component.setFloat("speedY", speed_factor);
        }

        const current_time = @as(f32, @floatCast(ray.GetTime()));
        try shader_component.setFloat("seconds", current_time);
        try shaders.updateShaderUniforms(self.shader_entity);
    }
};

fn backgroundInit(allocator: std.mem.Allocator) anyerror!*anyopaque {
    const ctx = try BackgroundContext.init(allocator);
    return ctx;
}

fn backgroundDeinit(ctx: *anyopaque) void {
    const self = @as(*BackgroundContext, @ptrCast(@alignCast(ctx)));
    self.deinit();
}

fn backgroundRender(ctx: *anyopaque, rc: gfx.RenderContext) void {
    const self = @as(*BackgroundContext, @ptrCast(@alignCast(ctx)));

    // Update shader
    self.updateShader() catch {};
    const shader_component = ecs.getUnchecked(components.Shader, self.shader_entity);
    const shader = shader_component.shader;

    // Apply the warp shader
    ray.BeginShaderMode(shader.*);

    // Draw background
    const src = ray.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(self.texture[self.index].width), .height = @floatFromInt(self.texture[self.index].height) };
    const tgt = ray.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(rc.logical_width), .height = @floatFromInt(rc.logical_height) };

    ray.DrawTexturePro(self.texture[self.index], src, tgt, ray.Vector2{ .x = 0, .y = 0 }, 0, ray.WHITE);
    ray.EndShaderMode();
}

fn backgroundProcessEvent(ctx: *anyopaque, event: *const anyopaque) void {
    const self = @as(*BackgroundContext, @ptrCast(@alignCast(ctx)));
    const e = @as(*const events.Event, @ptrCast(@alignCast(event))).*;

    switch (e) {
        .LevelUp => |newlevel| {
            self.level = newlevel;
        },
        .NextBackground => {
            self.index = (self.index + 1) % self.texture.len;
        },
        .Clear => |lines| {
            const extra_ms: i64 = 120 * @as(i64, @intCast(lines));
            const now = std.time.milliTimestamp();
            if (self.warp_end_ms < now + extra_ms) {
                self.warp_end_ms = now + extra_ms;
            }
        },
        .GameOver => {
            self.index = (self.index + 1) % self.texture.len;
            const now = std.time.milliTimestamp();
            self.warp_end_ms = now + 300;
        },
        .Reset => {
            self.index = 0;
            self.level = 0;
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// Game Entities Layer
// ---------------------------------------------------------------------------

pub const GameContext = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*GameContext {
        const self = try allocator.create(GameContext);
        self.* = .{ .allocator = allocator };

        // Initialize player system
        playersys.init();

        return self;
    }

    pub fn deinit(self: *GameContext) void {
        playersys.deinit();
        self.allocator.destroy(self);
    }
};

fn gameInit(allocator: std.mem.Allocator) anyerror!*anyopaque {
    const ctx = try GameContext.init(allocator);
    return ctx;
}

fn gameDeinit(ctx: *anyopaque) void {
    const self = @as(*GameContext, @ptrCast(@alignCast(ctx)));
    self.deinit();
}

fn gameUpdate(ctx: *anyopaque, dt: f32) void {
    _ = ctx;
    _ = dt;

    // Update game systems
    playersys.update();
    collisionsys.update();
    animsys.update();
}

fn gameRender(ctx: *anyopaque, rc: gfx.RenderContext) void {
    _ = ctx;
    _ = rc;

    // Render all game entities with cell-based sizing
    gfx.drawEntities(calculateSizeFromScale);
}

// Convert sprite scale to actual pixel size
fn calculateSizeFromScale(scale: f32) f32 {
    return @as(f32, @floatFromInt(constants.CELL_SIZE)) * scale;
}

fn gameProcessEvent(ctx: *anyopaque, event: *const anyopaque) void {
    _ = ctx;
    const e = @as(*const events.Event, @ptrCast(@alignCast(event))).*;

    switch (e) {
        .GameOver => {
            animsys.createExplosionAll();
        },
        .Reset => {
            animsys.createExplosionAll();
            previewsys.reset();
        },
        .HardDropEffect => playersys.harddrop(),
        .Spawn => {
            previewsys.spawn(game.state.piece.next);
        },
        .PlayerPositionUpdated => |update| {
            playersys.updatePlayerPosition(update.x, update.y, update.rotation, update.ghost_y, update.piece_index);
        },
        .PieceLocked => |data| {
            for (0..data.count) |i| {
                const block = data.blocks[i];
                gridsvc.occupyCell(@intCast(block.x), @intCast(block.y), block.color);
            }
        },
        .LineClearing => |data| {
            gridsvc.removeLineCells(@intCast(data.y));
        },
        .RowsShiftedDown => |data| {
            for (0..@as(usize, @intCast(data.count))) |i| {
                gridsvc.shiftRowCells(@intCast(data.start_y + @as(i32, @intCast(i))));
            }
        },
        .Hold => {
            previewsys.hold(game.state.piece.held);
            playersys.redraw();
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// HUD Layer
// ---------------------------------------------------------------------------

pub const HudContext = struct {
    allocator: std.mem.Allocator,
    // Grid layout constants
    gridoffsetx: i32 = 165,
    gridoffsety: i32 = 70,
    cellsize: i32 = 35,
    cellpadding: i32 = 2,

    pub fn init(allocator: std.mem.Allocator) !*HudContext {
        const self = try allocator.create(HudContext);
        self.* = .{ .allocator = allocator };
        return self;
    }

    pub fn deinit(self: *HudContext) void {
        self.allocator.destroy(self);
    }
};

fn hudInit(allocator: std.mem.Allocator) anyerror!*anyopaque {
    const ctx = try HudContext.init(allocator);
    return ctx;
}

fn hudDeinit(ctx: *anyopaque) void {
    const self = @as(*HudContext, @ptrCast(@alignCast(ctx)));
    self.deinit();
}

fn hudRender(ctx: *anyopaque, rc: gfx.RenderContext) void {
    const self = @as(*HudContext, @ptrCast(@alignCast(ctx)));

    // Draw HUD
    hud.draw(.{
        .gridoffsetx = self.gridoffsetx,
        .gridoffsety = self.gridoffsety,
        .cellsize = self.cellsize,
        .cellpadding = self.cellpadding,
        .font = rc.font,
        .og_width = rc.logical_width,
        .og_height = rc.logical_height,
        .next_piece = game.state.piece.next,
        .held_piece = game.state.piece.held,
    });
}

// ---------------------------------------------------------------------------
// Layer Definitions
// ---------------------------------------------------------------------------

pub fn createLayers() ![3]gfx.Layer {
    return [3]gfx.Layer{
        // Background layer
        gfx.Layer{
            .name = "background",
            .order = 0,
            .init = backgroundInit,
            .deinit = backgroundDeinit,
            .render = backgroundRender,
            .processEvent = backgroundProcessEvent,
        },
        // Game entities layer
        gfx.Layer{
            .name = "game",
            .order = 100,
            .init = gameInit,
            .deinit = gameDeinit,
            .update = gameUpdate,
            .render = gameRender,
            .processEvent = gameProcessEvent,
        },
        // HUD layer
        gfx.Layer{
            .name = "hud",
            .order = 200,
            .init = hudInit,
            .deinit = hudDeinit,
            .render = hudRender,
        },
    };
}
