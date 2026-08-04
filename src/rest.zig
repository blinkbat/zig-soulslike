const rl = @import("raylib");
const mathx = @import("mathx.zig");
const props = @import("props.zig");
const sfx = @import("audio.zig");

const v3 = mathx.v3;

// Sit at the bonfire.

/// How many bonfires one world may hold.
pub const CAP: usize = 32;

/// How close you have to stand for the prompt (metres, XZ from the camp's own origin).
pub const REACH: f32 = 3.2;

const FADE_DOWN: f32 = 0.75; // to black, on the way in
const FADE_UP: f32 = 1.10;
const FADE_OUT: f32 = 0.60; // to black again on the way back to the field
const FADE_RETURN: f32 = 0.90;
const MIN_SIT: f32 = 2.2;
const BED_IN: f32 = 2.6;
const BED_OUT: f32 = 0.55;
/// A nudge OFF the fire, toward the lens.
const SEAT_TURN: f32 = 0.20;

pub const Site = struct {
    pos: rl.Vector3 = mathx.zero3,
    yaw: f32 = 0, // degrees, the prop's own — the camp's layout is authored in its local frame
};

pub const Phase = enum {
    off, // out in the field
    in, // fading down to black, still standing
    sit, // at the fire
    out, // fading down to black again, on the way back
};

pub const Rest = struct {
    list: [CAP]Site = undefined,
    n: usize = 0,
    near: ?usize = null,

    phase: Phase = .off,
    /// Seconds INTO the current phase.
    t: f32 = mathx.LONG_AGO,
    site: Site = .{},

    /// EDGES, true for exactly the one frame the transition happens on.
    justEntered: bool = false,
    justLeft: bool = false,

    /// Rebuild from the world.
    pub fn reset(self: *Rest, sites: []const Site) void {
        self.n = 0;
        self.near = null;
        for (sites) |s| {
            if (self.n >= CAP) break;
            self.list[self.n] = s;
            self.n += 1;
        }
    }

    pub fn active(self: *const Rest) bool {
        return self.phase != .off;
    }
    /// True while the rest scene — not the field — is what is being drawn.
    pub fn scene(self: *const Rest) bool {
        return self.phase == .sit or self.phase == .out;
    }

    /// HOW BLACK THE SCREEN IS, 0..1.
    pub fn fade(self: *const Rest) f32 {
        return switch (self.phase) {
            .in => mathx.clampF(self.t / FADE_DOWN, 0, 1),
            .sit => 1.0 - mathx.smoothstep(0, FADE_UP, self.t),
            .out => mathx.clampF(self.t / FADE_OUT, 0, 1),
            .off => 1.0 - mathx.smoothstep(0, FADE_RETURN, self.t),
        };
    }

    /// HOW FAR INTO DUSK the world is pulled, 0..1 (see gfx.Scene.setDim).
    pub fn dim(self: *const Rest) f32 {
        return switch (self.phase) {
            .in, .off => 0,
            .sit => 1,
            .out => 1.0 - mathx.clampF(self.t / FADE_OUT, 0, 1),
        };
    }

    /// THE FIRE BED'S LEVEL.
    pub fn bedLevel(self: *const Rest) f32 {
        return switch (self.phase) {
            .in, .off => 0,
            .sit => mathx.smoothstep(0, BED_IN, self.t),
            .out => 1.0 - mathx.smoothstep(0, BED_OUT, self.t),
        };
    }

    /// Pick the bonfire in reach.
    pub fn look(self: *Rest, heroPos: rl.Vector3) void {
        if (self.phase != .off or self.fadeRunning()) {
            self.near = null;
            return;
        }
        var best: ?usize = null;
        var bestD: f32 = REACH * REACH;
        for (self.list[0..self.n], 0..) |*s, i| {
            const d = mathx.dist2XZ(s.pos, heroPos);
            if (d < bestD) {
                bestD = d;
                best = i;
            }
        }
        self.near = best;
    }

    fn fadeRunning(self: *const Rest) bool {
        return self.phase == .off and self.t < FADE_RETURN;
    }

    /// BEGIN, if there is a fire in reach.
    pub fn begin(self: *Rest) bool {
        if (self.phase != .off or self.fadeRunning()) return false;
        const i = self.near orelse return false;
        self.site = self.list[i];
        self.phase = .in;
        self.t = 0;
        self.near = null;
        return true;
    }

    /// LEAVE, on any button.
    pub fn leave(self: *Rest) void {
        if (self.phase != .sit or self.t < MIN_SIT) return;
        self.phase = .out;
        self.t = 0;
    }

    /// One frame.
    pub fn update(self: *Rest, dt: f32) void {
        self.justEntered = false;
        self.justLeft = false;
        // Clamped in `.off` so the idle clock cannot run away over a long session.
        self.t = if (self.phase == .off) @min(self.t + dt, mathx.LONG_AGO) else self.t + dt;
        switch (self.phase) {
            .off => {},
            .in => if (self.t >= FADE_DOWN) {
                self.phase = .sit;
                self.t = 0;
                self.justEntered = true;
                sfx.restFireOn(true);
            },
            .sit => {},
            .out => if (self.t >= FADE_OUT) {
                self.phase = .off;
                self.t = 0;
                self.justLeft = true;
                sfx.restFireOn(false);
            },
        }
        sfx.restFireLevel(self.bedLevel());
    }

    /// WHERE THE HERO SITS, and which way he faces.
    pub fn seat(self: *const Rest) struct { pos: rl.Vector3, facing: f32, axis: f32 } {
        const yaw = mathx.radians(self.site.yaw);
        const c = mathx.cosf(yaw);
        const s = mathx.sinf(yaw);
        const lx: f32 = 1.25;
        const lz: f32 = -1.95;
        const pos = v3(self.site.pos.x + c * lx + s * lz, self.site.pos.y, self.site.pos.z - s * lx + c * lz);
        // `axis` points at the fire and is what the camera stands broadside to.
        const axis = mathx.headingXZ(mathx.subV(self.site.pos, pos));
        return .{ .pos = pos, .facing = axis + SEAT_TURN, .axis = axis };
    }
};

/// Every bonfire that was actually planted, in prop order
pub fn siteFromProp(pos: rl.Vector3, yaw: f32) Site {
    return .{ .pos = pos, .yaw = yaw };
}

/// THE KINDS YOU CAN SIT AT. The bonfire camp, and the lit campfire — a camp you can pitch anywhere,
/// and it is a FULL grace (owner's call): the same restore and the same world reload, because the one
/// thing worse than a second rest kind is a second rest kind with its own half-rules.
pub fn isRestKind(k: props.Kind) bool {
    return k == .grace or k == .campfire_lit;
}
