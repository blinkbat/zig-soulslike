const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const foe = @import("../foes/foe.zig");
const wood = @import("../props/propwood.zig");
const sfx = @import("../core/audio.zig");
const chest = @import("chest.zig"); // for the one comptime assert below, and nothing else

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;


pub const REACH: f32 = 2.6;
comptime {
    std.debug.assert(REACH > chest.REACH);
}

/// The gold stands about chest height on the 1.8 m rig — tall enough to find across a clearing, short enough
/// that it never hides the thing that killed you standing behind it.
pub const H: f32 = 1.25;
const TOP_LIFT: f32 = 0.30;

const RISE: f32 = 0.55;
const RISE_PUNCH: f32 = 0.16;
const SPIN: f32 = 0.35; // radians a second
const BOB: f32 = 0.035;
const BOB_RATE: f32 = 1.3;

const MOTE_RATE: f32 = 38.0;
const MOTE_LIFE_LO: f32 = 0.9;
const MOTE_LIFE_HI: f32 = 1.7;
const PARTS = blk: {
    const worst = MOTE_RATE * MOTE_LIFE_HI + TAKE_MOTES;
    break :blk @as(usize, @intFromFloat(@ceil(worst))) + 4;
};
comptime {
    std.debug.assert(@as(f32, PARTS) >= MOTE_RATE * MOTE_LIFE_HI + TAKE_MOTES);
}
const TAKE_MOTES: f32 = 34.0;
const TAKE_PULL: f32 = 0.34;
const TAKE_INTO: f32 = 1.05;

/// THE HUM IS A RETRIGGER, NOT A LOOP (`leechfly.WHINE_EVERY`'s rule — raylib cannot loop a synthesized take). Cut a hair SHORTER than the voice itself so consecutive takes overlap: gapped, a standing hum pulses, and a pulse reads as something arming rather than something waiting.
const HUM_EVERY: f32 = 1.15;

/// It must read as GOLD and not as BONE. Vertex alpha is the emissive channel — the scene shader reads
/// `1 - fragColor.a`, so 255 is lit by the sun alone and lower is more self-lit.
/// MEASURED: at alpha 58 screen = 255·(albedo/255 · 1.236)^(1/2.2), so anything over albedo ~205 clips — tips
/// authored at 246,220,150 came back a white knuckle and read as bone. FOUR TONES: the reds step 150 → 214 → 246 → 254 and the blues 24 → 60 → 100 → 170, so it DESATURATES as it brightens, which is what hot metal does.
const EMISSIVE: u8 = 58;
const GOLD_DEEP = rgba(64, 20, 1, EMISSIVE);
const GOLD = rgba(141, 73, 8, EMISSIVE);
const GOLD_LT = rgba(191, 122, 26, EMISSIVE);
const GOLD_HOT = rgba(204, 174, 85, EMISSIVE);

const MOTE = rgba(250, 200, 96, 190);

/// The trunk's own dimensions, in metres. The taper is GENTLE: run 0.085 → 0.045 over half a metre and it is a carrot, and a cone that steep on a short shaft is most of why the first pass read as one moulded piece.
const BOLE_R0: f32 = 0.082;
const BOLE_R1: f32 = 0.038;
const BOLE_TOP: f32 = 0.68;
const BOLE_SEGS = 5;
const FORKS = [_]f32{ 0.42, 0.66, 0.88 };
const PER_FORK = [_]u32{ 3, 3, 2 };

pub const Drop = struct {
    at: rl.Vector3 = mathx.zero3,
    amount: u32 = 0,
    t: f32 = 0,
    live: bool = false,

    pub fn topWorld(self: *const Drop) rl.Vector3 {
        return v3(self.at.x, self.at.y + H + TOP_LIFT, self.at.z);
    }

    fn grown(self: *const Drop) f32 {
        const k = mathx.smoothstep(0, RISE, self.t);
        return k + RISE_PUNCH * mathx.pulse(self.t, RISE * 0.45, RISE * 0.8, RISE * 0.8, RISE * 2.0);
    }
};

pub const Souls = struct {
    mesh: rl.Mesh = undefined,
    mat: rl.Material = undefined,
    drop: Drop = .{},
    near: bool = false,

    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    humLeft: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(0x50015),
    fxFloor: f32 = 0,

    pub fn init(shader: rl.Shader) Souls {
        const mat = gfx.material(shader, "souls");
        return .{ .mesh = boughMesh(), .mat = mat };
    }

    pub fn setShader(self: *Souls, sh: rl.Shader) void {
        self.mat.shader = sh;
    }

    pub fn spill(self: *Souls, at: rl.Vector3, amount: u32) void {
        if (amount == 0) {
            self.drop = .{};
            self.near = false;
            return;
        }
        self.drop = .{ .at = at, .amount = amount, .t = 0, .live = true };
        self.near = false;
        self.fxFloor = at.y;
        self.humLeft = HUM_EVERY * 0.5;
        self.fxRng = foe.fxStream(at.x + at.z * 1.7 + @as(f32, @floatFromInt(amount)), 613.0, 0x5011);
    }

    pub fn look(self: *Souls, heroPos: rl.Vector3) void {
        self.near = self.drop.live and mathx.distXZ(self.drop.at, heroPos) <= REACH;
    }

    pub fn take(self: *Souls, heroPos: rl.Vector3) ?u32 {
        if (!self.drop.live) return null;
        const got = self.drop.amount;
        self.burst(heroPos);
        sfx.world(.souls_take, self.drop.at);
        self.drop = .{};
        self.near = false;
        return got;
    }

    pub fn standing(self: *const Souls) ?u32 {
        return if (self.drop.live) self.drop.amount else null;
    }

    pub fn clear(self: *Souls) void {
        self.drop = .{};
        self.near = false;
        for (&self.parts) |*p| p.* = .{};
    }

    pub fn update(self: *Souls, dt: f32) void {
        foe.tickParticles(&self.parts, dt, self.fxFloor);
        if (!self.drop.live) return;
        self.drop.t += dt;
        self.humLeft -= dt;
        if (self.humLeft <= 0) {
            self.humLeft = HUM_EVERY;
            sfx.world(.souls_hum, self.drop.topWorld());
        }
        const emitRate = MOTE_RATE * self.drop.grown();
        var owed = foe.emitDue(&self.fxAccum, dt, emitRate);
        while (owed > 0) : (owed -= 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.05, 0.42);
            const from = v3(
                self.drop.at.x + mathx.cosf(a) * rr,
                self.drop.at.y + self.fxRng.range(0.05, 1.0) * H,
                self.drop.at.z + mathx.sinf(a) * rr,
            );
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = from,
                .v = v3(self.fxRng.signed() * 0.18, self.fxRng.range(0.35, 0.9), self.fxRng.signed() * 0.18),
                .life = self.fxRng.range(MOTE_LIFE_LO, MOTE_LIFE_HI),
                .r0 = self.fxRng.range(0.022, 0.045),
                .r1 = 0.004,
                .col = MOTE,
                .grav = -0.55,
                .add = true,
            });
        }
    }

    fn burst(self: *Souls, heroPos: rl.Vector3) void {
        const into = v3(heroPos.x, heroPos.y + TAKE_INTO, heroPos.z);
        var i: f32 = 0;
        while (i < TAKE_MOTES) : (i += 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.05, 0.5);
            const from = v3(
                self.drop.at.x + mathx.cosf(a) * rr,
                self.drop.at.y + self.fxRng.range(0.05, 1.05) * H,
                self.drop.at.z + mathx.sinf(a) * rr,
            );
            const life = self.fxRng.range(TAKE_PULL * 0.6, TAKE_PULL);
            const v = mathx.scaleV(mathx.subV(into, from), 1.0 / life);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = from,
                .v = v3(v.x, v.y + self.fxRng.range(-0.4, 0.8), v.z),
                .life = life,
                .r0 = self.fxRng.range(0.030, 0.060),
                .r1 = 0.010,
                .col = MOTE,
                .stretch = 0.035,
                .add = true,
            });
        }
    }

    pub fn draw(self: *const Souls) void {
        if (!self.drop.live) return;
        const up = self.drop.grown();
        if (up <= 0.001) return;
        const bob = BOB * mathx.sinf(self.drop.t * BOB_RATE);
        const yaw = mathx.degrees(self.drop.t * SPIN);
        rl.drawMesh(self.mesh, self.mat, mathx.mul3(
            mathx.scaleM(1.0, up, 1.0),
            mathx.ry(yaw),
            mathx.tr(self.drop.at.x, self.drop.at.y + bob, self.drop.at.z),
        ));
    }

    pub fn drawFx(self: *const Souls) void {
        foe.drawParticles(&self.parts);
    }
};

fn boughMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x501D7EE);
    b.setMat(.plain);

    var joint: [BOLE_SEGS + 1]rl.Vector3 = undefined;
    var radius: [BOLE_SEGS + 1]f32 = undefined;
    joint[0] = mathx.zero3;
    radius[0] = BOLE_R0;
    var seg: usize = 0;
    while (seg < BOLE_SEGS) : (seg += 1) {
        const k = @as(f32, @floatFromInt(seg + 1)) / @as(f32, @floatFromInt(BOLE_SEGS));
        const a = rng.angle();
        const lean = rng.range(0.012, 0.042);
        joint[seg + 1] = v3(
            joint[seg].x + mathx.cosf(a) * lean,
            H * BOLE_TOP * k * rng.range(0.94, 1.06),
            joint[seg].z + mathx.sinf(a) * lean,
        );
        radius[seg + 1] = mathx.lerpF(BOLE_R0, BOLE_R1, k);
        b.addCapsule(joint[seg], joint[seg + 1], radius[seg], radius[seg + 1], 8, boleTone(k));
    }
    b.addBlob(
        joint[BOLE_SEGS],
        v3(radius[BOLE_SEGS] * 1.5, radius[BOLE_SEGS] * 1.2, radius[BOLE_SEGS] * 1.5),
        4,
        7,
        GOLD_HOT,
    );

    var spin = rng.angle();
    for (FORKS, PER_FORK) |where, n| {
        const at = boleAt(&joint, where);
        const r = mathx.lerpF(BOLE_R0, BOLE_R1, where);
        spin += rng.range(0.7, 1.5);
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const yaw = spin + std.math.tau * (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n))) + rng.range(-0.28, 0.28);
            const shrink = 1.0 - 0.35 * where;
            wood.deadLimbTinted(
                &b,
                &rng,
                at,
                yaw,
                H * rng.range(0.30, 0.48) * shrink,
                H * rng.range(0.16, 0.32) * shrink,
                r * rng.range(0.72, 0.98),
                1 + rng.intn(2),
                if (where > 0.75) GOLD_LT else GOLD,
                GOLD_HOT,
            );
        }
    }
    return b.toMesh();
}

fn boleTone(k: f32) rl.Color {
    return if (k < 0.34) GOLD_DEEP else if (k < 0.72) GOLD else GOLD_LT;
}

fn boleAt(joint: []const rl.Vector3, u: f32) rl.Vector3 {
    const t = mathx.clampF(u, 0, 1) * @as(f32, @floatFromInt(BOLE_SEGS));
    const i: usize = @min(@as(usize, @intFromFloat(t)), BOLE_SEGS - 1);
    return mathx.lerpV(joint[i], joint[i + 1], t - @as(f32, @floatFromInt(i)));
}


test "THERE IS EXACTLY ONE DROP, and a second death spends the first" {
    var s = Souls{};
    try std.testing.expect(s.standing() == null);
    s.spill(v3(4, 0, 4), 900);
    try std.testing.expectEqual(@as(u32, 900), s.standing().?);
    s.spill(v3(-20, 0, 7), 120);
    try std.testing.expectEqual(@as(u32, 120), s.standing().?);
    try std.testing.expectApproxEqAbs(@as(f32, -20), s.drop.at.x, 1e-5);
    try std.testing.expectEqual(@as(u32, 120), s.take(mathx.zero3).?);
    try std.testing.expect(s.take(mathx.zero3) == null);
    try std.testing.expect(s.standing() == null);
}

test "a death carrying NOTHING leaves no stain to walk back to" {
    var s = Souls{};
    s.spill(v3(1, 0, 1), 500);
    s.spill(v3(2, 0, 2), 0);
    try std.testing.expect(s.standing() == null);
    try std.testing.expect(!s.drop.live);
}

test "the prompt is a RING round the drop, and it is only offered where there is one" {
    var s = Souls{};
    s.look(mathx.zero3);
    try std.testing.expect(!s.near);
    s.spill(mathx.zero3, 300);
    s.look(v3(REACH * 0.5, 0, 0));
    try std.testing.expect(s.near);
    s.look(v3(REACH + 1.0, 0, 0));
    try std.testing.expect(!s.near);
    s.look(v3(REACH, 0, 0));
    try std.testing.expect(s.near);
    s.look(mathx.zero3);
    _ = s.take(mathx.zero3);
    s.look(mathx.zero3);
    try std.testing.expect(!s.near);
}

test "NOTHING BUT A DEATH OR A PICKUP SPENDS IT — no clock, no decay, no despawn" {
    var s = Souls{};
    s.spill(mathx.zero3, 4200);
    var t: f32 = 0;
    while (t < 600.0) : (t += 1.0 / 30.0) s.update(1.0 / 30.0);
    try std.testing.expectEqual(@as(u32, 4200), s.standing().?);
    try std.testing.expect(s.drop.grown() > 0.99);
    s.look(mathx.zero3);
    try std.testing.expect(s.near);
}

test "it GROWS out of the ground, overshoots, and settles onto its own height" {
    var s = Souls{};
    s.spill(mathx.zero3, 10);
    try std.testing.expect(s.drop.grown() < 0.05);
    var over: f32 = 0;
    var t: f32 = 0;
    while (t < RISE * 3.0) : (t += 1.0 / 120.0) {
        s.update(1.0 / 120.0);
        over = @max(over, s.drop.grown());
    }
    try std.testing.expect(over > 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), s.drop.grown(), 0.01);
}

test "THE RETRIEVAL SHOWER IS FLOORED ON THE EARTH IT LEFT, not on the datum" {
    var s = Souls{};
    s.spill(v3(0, -4.0, 0), 500);
    _ = s.take(v3(0.4, -4.0, 0.4));
    s.update(1.0 / 60.0);
    var live: usize = 0;
    for (s.parts) |p| {
        if (p.life <= 0) continue;
        live += 1;
        try std.testing.expect(p.p.y < 0);
    }
    try std.testing.expect(live > 0);
}

test "the prompt anchor is over the bloom, not at its foot" {
    var s = Souls{};
    s.spill(v3(3, 1.5, -2), 60);
    const top = s.drop.topWorld();
    try std.testing.expectApproxEqAbs(@as(f32, 3), top.x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, -2), top.z, 1e-5);
    try std.testing.expect(top.y > 1.5 + H); // measured from ITS OWN ground, like every world point here
}
