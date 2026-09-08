const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const sfx = @import("../core/audio.zig");
const propwood = @import("../props/propwood.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const scaleM = mathx.scaleM;
const lerpF = mathx.lerpF;
const approach = mathx.approach;
const setLocal = heromod.setHumanoid;

/// 2.56x the hero, the tallest thing in the game that walks — over the cyclops (4.14 m) and under the Rooted's fixed 7.2.
pub const H: f32 = 4.6;
const HIP_HALF = heromod.HIP_HALF * 1.14;
const SHOULDER_HALF = heromod.SHOULDER_HALF * 1.34;
/// A BOLE HAS NO NECK: `restHumanoid` puts the head 0.067 of stature over the shoulders and the trunk's own 0.132 swallowed it, so the crown goes up 0.090.
const REST = blk: {
    var r = heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);
    r[heromod.NECK].y += 0.030 * H;
    r[heromod.HEAD].y += 0.090 * H;
    break :blk r;
};

const N = heromod.N;
const ROOT = heromod.ROOT;
const SPINE = heromod.SPINE;
const CHEST = heromod.CHEST;
const NECK = heromod.NECK;
const CROWN = heromod.HEAD;
const HIPL = heromod.HIPL;
const KNEEL = heromod.KNEEL;
const ANKL = heromod.ANKL;
const HIPR = heromod.HIPR;
const KNEER = heromod.KNEER;
const ANKR = heromod.ANKR;
const SHL = heromod.SHL;
const ELL = heromod.ELL;
const WRL = heromod.WRL;
const SHR = heromod.SHR;
const ELR = heromod.ELR;
const WRR = heromod.WRR;
const HELD = heromod.HELD;

const solePatches = [_]heromod.SolePatch{
    .{ .bone = ANKL, .heel = 0.026 * H, .toe = 0.112 * H, .halfW = 0.062 * H, .drop = 0.022 * H },
    .{ .bone = ANKR, .heel = 0.026 * H, .toe = 0.112 * H, .halfW = 0.062 * H, .drop = 0.022 * H },
};

// Sampled off `gfx`'s ladder: 54 reads ~160 on screen, a full step under the birch's 92, and the riven heartwood at 118 is the one bright thing on the body.
const BARK = rgba(54, 43, 31, 255);
const BARK_DK = rgba(36, 29, 21, 255);
const BARK_LT = rgba(72, 58, 42, 255);
const BARK_LIVE = rgba(64, 56, 36, 255);
const HEARTWOOD = rgba(118, 100, 70, 255);
const SPLINTER = rgba(140, 122, 88, 255);
const ROT = rgba(46, 44, 30, 255);
const KNOTHOLE = rgba(13, 11, 9, 255);
const CANKER = rgba(58, 66, 34, 255);
const EYE = rgba(196, 138, 46, 255);
const ACORN_SHELL = rgba(96, 68, 34, 255);
const ACORN_CUP = rgba(58, 44, 26, 255);

pub var AGGRO_R: f32 = 20.0;
const HOME_R: f32 = 3.2;
const WALK_SPEED: f32 = heromod.WALK_SPEED_BANK * 0.40;
const CHASE_SPEED: f32 = heromod.WALK_SPEED_BANK * 0.66;
const ACCEL: f32 = 1.6;
const TURN_RATE: f32 = 1.3;

const BODY_R: f32 = 0.95;
/// SIZED AGAINST THE CYCLOPS: what makes a tall body hittable is his chest's stand-off at `closestApproach` AS A MULTIPLE of the radius — 1.33 for the cyclops, and the test holds this one at or under it.
const HURT_R: f32 = 1.55;
const CENTER_F: f32 = 0.50;
const TOP_F: f32 = 1.04;

const HP_MAX: f32 = 420.0;
const POISE_MAX: f32 = 46.0;
const STANCE_MAX: f32 = 96.0;
const RESISTS = combat.resists(.{ .fire = -60, .lightning = -15, .cold = 30, .chaos = 35 });
pub var SOULS: u32 = 780;

/// THE SWEEP HAS NO INNER HOLE: a `minR` here would invert under `wf.FOE_SCALE_LO` and leave a dead pocket inside a body the hero cannot walk out of (`foe.closestApproach` 1.31 m against the sector's 4.05).
const SWIPE_R: f32 = 3.50;
const SWIPE_ARC: f32 = 150.0;
/// Where the sector sits relative to facing, in the swinging hand's own sign: the bough finishes across the body.
const SWIPE_ARC_MID: f32 = -46.0;
const SWIPE_WIND: f32 = 0.72;
const SWIPE_STRIKE: f32 = 0.24;
const SWIPE_IMPACT_K: f32 = 0.60;
const SWIPE_RECOVER: f32 = 0.85;
const SWIPE_CD: f32 = 2.4;
pub var SWIPE_HIT = combat.Hit{ .dmg = 34, .poise = 38, .stance = 18, .shove = 0.9 };

/// The return comes off the far hand with the arm already out, so its wind is half the opener's.
const RET_WIND: f32 = 0.34;
const RET_STRIKE: f32 = 0.26;
const RET_IMPACT_K: f32 = 0.48;
const RET_RECOVER: f32 = 0.62;
const RET_CHANCE: f32 = 0.6;
pub var RET_HIT = combat.Hit{ .dmg = 26, .poise = 30, .stance = 12, .shove = 0.7 };

/// The share of `TURN_RATE * wind` the gate may count on; the rest is slack for a man who is moving.
const WIND_TURN_SHARE: f32 = 0.8;

/// THE SHAKE IS RANGED AND ITS BAND IS NOT A LIMB, so the metres are the world's and do not scale with the body.
const SHAKE_MIN: f32 = 5.5;
const SHAKE_MAX: f32 = 17.0;
const SHAKE_WIND: f32 = 1.15;
const SHAKE_STRIKE: f32 = 0.60;
/// Share of the strike at which the boughs let go.
const SHAKE_RELEASE_K: f32 = 0.35;
const SHAKE_RECOVER: f32 = 1.20;
const SHAKE_CD: f32 = 9.0;
const SHAKE_HZ: f32 = 7.5;

pub const ACORNS: usize = 7;
pub const ACORN_SPEED: f32 = 13.0;
pub const ACORN_R: f32 = 0.19;
/// Metres about the man the fall is spread over. The FIRST nut is aimed at him exactly, so standing still is answered and moving is the counter.
const ACORN_SCATTER: f32 = 2.6;
pub const ACORN_SPLASH_R: f32 = 1.7;
pub var ACORN_HIT = combat.Hit{ .dmg = 16, .poise = 15, .elem = combat.elems(.{ .chaos = 6 }) };

comptime {
    std.debug.assert(SWIPE_WIND >= foe.TELL_MIN);
    std.debug.assert(RET_WIND >= foe.TELL_MIN);
    std.debug.assert(SHAKE_WIND >= foe.TELL_MIN);
    std.debug.assert(ACORN_SCATTER > ACORN_SPLASH_R);
}

const DEATH_DUR: f32 = 1.8;
const DISS_DUR: f32 = 1.25;
const SHOVE_DECAY: f32 = 5.0;
const DISSOLVE = foe.Dissolve{ .rate = 54.0, .spread = 0.9, .rise = 0.70, .flake = BARK_LT };

const A_PROT: f32 = 1.8;
const SWAY: f32 = 4.0;
const PELVIS_SHARE: f32 = 0.16;

const HIT_CHIP_LIGHT = 9;
const HIT_CHIP_HEAVY = 18;
const CHIP_DEATH = 22;
const PARRY_CHIPS = 12;
const SHAKE_CHIPS = 20;
const PARTS = 96;
comptime {
    std.debug.assert(PARTS >= SHAKE_CHIPS + PARRY_CHIPS +
        foe.hitParts(HIT_CHIP_HEAVY) + foe.hitParts(CHIP_DEATH) + foe.WOUND_PARTS);
}

const State = enum { idle, walk, swipe, ret, shake, stunlight, stunheavy, dead };

const Choice = enum { rest, hold, close, swipe, shake, wait };

/// The sector's own half-width, plus what the wind turns, plus what the man subtends at that stand. Off it the body LOOMS (`.wait` is idle, which faces at the full rate).
fn swipeBearing(dist: f32, wind: f32) f32 {
    return SWIPE_ARC * 0.5 + mathx.degrees(TURN_RATE * WIND_TURN_SHARE * wind) +
        combat.subtendedArc(foe.HERO_REACH, dist);
}

fn classify(sensed: f32, bearingDeg: f32, homeGap: f32, scale: f32, swipeReady: bool, shakeReady: bool, rooted: bool) Choice {
    if (sensed > AGGRO_R) return if (homeGap > HOME_R) .hold else .rest;
    if (sensed <= foe.hurtReach(SWIPE_R, scale)) {
        if (!swipeReady) return .wait;
        return if (@abs(bearingDeg) <= swipeBearing(sensed, SWIPE_WIND)) .swipe else .wait;
    }
    if (shakeReady and sensed >= SHAKE_MIN and sensed <= SHAKE_MAX) return .shake;
    if (rooted) return .rest;
    return .close;
}

/// One nut let go: where it leaves the crown, and the point on the ground it is thrown at.
pub const Toss = struct { from: rl.Vector3 = mathx.zero3, at: rl.Vector3 = mathx.zero3 };

pub const Model = struct {
    bone: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        return .{ .bone = buildBones(), .mat = gfx.material(shader, "corruptent") };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, e: *const Ent) void {
        for (0..HELD) |i| rl.drawMesh(self.bone[i], self.mat, e.xf[i]);
    }
};

pub const Ent = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    post: foe.Post = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},

    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    swipeCd: f32 = 0,
    shakeCd: f32 = 0,
    speed: f32 = 0,
    /// +1 sweeps right-to-left, -1 the other way. Picked off the man's bearing at the choose, flipped for the return.
    hand: f32 = 1,

    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,

    /// The nuts let go THIS FRAME, which `game.zig` turns into shafts. A one-frame edge like `justDied`.
    tossN: usize = 0,
    tosses: [ACORNS]Toss = [_]Toss{.{}} ** ACORNS,
    shook: bool = false,
    groaned: bool = false,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    heroLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    heroHit: ?combat.Hit = null,
    justDied: bool = false,
    parry: foe.Parry = .{},
    motion: foe.StrokeMotion = .{},
    deflect: foe.Deflect = .{},
    parried: bool = false,
    fade: f32 = 0,
    gone: bool = false,

    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),
    aiRng: mathx.Rng = mathx.Rng.init(2),

    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = REST,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Ent {
        var e = Ent{ .pos = home, .home = home, .facing = faceYaw, .scale = scale, .seed = seed };
        e.fxRng = foe.fxStream(seed, 44851.0, 0xE17C);
        e.aiRng = foe.fxStream(seed, 19073.0, 41);
        e.swipeCd = seed * 0.8;
                // Never a volley in the first breath of a fight.
        e.shakeCd = 3.0 + seed * 2.0;
        e.pose();
        return e;
    }

    pub fn centerWorld(self: *const Ent) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H, self.scale, 0);
    }
    pub fn lockPoint(self: *const Ent) rl.Vector3 {
        return foe.markOn(self.xf[CHEST], v3(0, 0.05 * H, 0));
    }
    pub fn topWorld(self: *const Ent) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * H, self.scale, 0);
    }
    pub fn hurtRadius(self: *const Ent) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Ent) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Ent) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Ent) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Ent) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn airborne(_: *const Ent) bool {
        return false;
    }
    pub fn flashFrac(self: *const Ent) f32 {
        return foe.flashFrac(self.flash);
    }
    pub fn kind(_: *const Ent) wf.FoeKind {
        return .corrupt_ent;
    }

    fn swipeReach(self: *const Ent) f32 {
        return foe.hurtReach(SWIPE_R, self.scale);
    }

    fn clock(self: *const Ent) ?foe.Clock {
        return switch (self.state) {
            .swipe => .{ .wind = SWIPE_WIND, .strike = SWIPE_STRIKE, .recover = SWIPE_RECOVER },
            .ret => .{ .wind = RET_WIND, .strike = RET_STRIKE, .recover = RET_RECOVER },
            .shake => .{ .wind = SHAKE_WIND, .strike = SHAKE_STRIKE, .recover = SHAKE_RECOVER },
            .idle, .walk, .stunlight, .stunheavy, .dead => null,
        };
    }

    fn impactK(self: *const Ent) f32 {
        return switch (self.state) {
            .ret => RET_IMPACT_K,
            .shake => SHAKE_RELEASE_K,
            .swipe, .idle, .walk, .stunlight, .stunheavy, .dead => SWIPE_IMPACT_K,
        };
    }

    fn impactAt(self: *const Ent) ?f32 {
        const c = self.clock() orelse return null;
        return c.wind + c.strike * self.impactK();
    }

    fn sweeping(self: *const Ent) bool {
        return self.state == .swipe or self.state == .ret;
    }

    pub fn navWant(self: *const Ent, quarry: rl.Vector3) ?rl.Vector3 {
        if (self.state != .idle and self.state != .walk) return null;
        if (foe.senseHero(&self.leash, self.pos, quarry, AGGRO_R) <= AGGRO_R) return quarry;
        if (foe.postAim(self)) |go| return go;
        return if (mathx.distXZ(self.pos, foe.homeFor(self)) > HOME_R) self.home else null;
    }

    fn faceToward(self: *Ent, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }

    fn strokeTarget(self: *const Ent) foe.StrokePose {
        const c = self.clock() orelse return .{};
        return foe.strokePose(self.t, c);
    }

    fn stunAmount(self: *const Ent) f32 {
        if (self.state != .stunlight and self.state != .stunheavy) return 0;
        return foe.recoilPose(self.t, self.state == .stunheavy);
    }

    pub fn update(self: *Ent, dt: f32, quarry: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.heroHit = null;
        self.parried = false;
        self.tossN = 0;
        self.shook = false;
        self.groaned = false;
        self.deflect.tick(dt);
        self.justDied = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.vit.tick(dt);
        self.elapsed += dt;
        self.t += dt;
        self.swipeCd = mathx.maxF(0, self.swipeCd - dt);
        self.shakeCd = mathx.maxF(0, self.shakeCd - dt);
        foe.tickBody(self, dt, quarry, bounds, AGGRO_R, SHOVE_DECAY);

        var movedDist: f32 = 0;
        var moveSpeed: f32 = 0;
        var moveYaw: ?f32 = null;

        switch (self.state) {
            .dead => {
                self.speed = 0;
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
            .stunlight, .stunheavy => {
                self.speed = approach(self.speed, 0, ACCEL * 2.5 * dt);
                if (self.t >= combat.foeStunDur(self.state == .stunheavy)) self.enter(.idle);
            },
            .swipe, .ret, .shake => {
                self.speed = approach(self.speed, 0, ACCEL * 2.5 * dt);
                const c = self.clock().?;
                if (self.t < c.wind) self.faceToward(quarry, dt);
                if (self.t >= c.wind + c.strike + c.recover) {
                    self.heroLatch = false;
                    if (self.state == .swipe and self.wantsReturn(quarry)) {
                        self.hand = -self.hand;
                        self.enter(.ret);
                    } else self.enter(.idle);
                }
            },
            .idle, .walk => {
                const sensed = foe.senseHero(&self.leash, self.pos, quarry, AGGRO_R);
                const homeGap = mathx.distXZ(self.pos, foe.homeFor(self));
                const bearing = foe.bearingDeg(self.pos, self.facing, quarry);
                switch (classify(sensed, bearing, homeGap, self.scale, self.swipeCd <= 0, self.shakeCd <= 0, self.root.held())) {
                    .rest => {
                        if (sensed <= AGGRO_R) self.faceToward(quarry, dt);
                        self.state = if (foe.postAmble(self, dt, bounds, WALK_SPEED, ACCEL, sensed, AGGRO_R, TURN_RATE, &movedDist, &moveSpeed, &moveYaw)) .walk else .idle;
                    },
                    .wait => {
                        self.faceToward(quarry, dt);
                        self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                        self.state = .idle;
                    },
                    .swipe => {
                        self.speed = approach(self.speed, 0, ACCEL * 2.5 * dt);
                        self.hand = if (bearing < 0) 1 else -1;
                        self.swipeCd = SWIPE_CD * self.aiRng.range(0.85, 1.2);
                        self.heroLatch = false;
                        self.enter(.swipe);
                    },
                    .shake => {
                        self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                        self.shakeCd = SHAKE_CD * self.aiRng.range(0.9, 1.15);
                        self.heroLatch = false;
                        self.enter(.shake);
                        self.groaned = true;
                    },
                    .hold, .close => |ch| {
                        const to = if (ch == .hold) self.home else quarry;
                        const want = if (ch == .hold) WALK_SPEED else CHASE_SPEED;
                        self.faceToward(self.nav.aim(self.pos, to), dt);
                        self.speed = approach(self.speed, want, ACCEL * dt);
                        foe.stride(self, dt, bounds, &movedDist, &moveSpeed, &moveYaw);
                        self.state = .walk;
                    },
                }
            },
        }

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        if (self.sweeping() and self.crossed(self.clock().?.wind, dt)) sfx.world(.wood_swing, self.pos);
        self.motion.tick(self.strokeTarget(), self.stunAmount(), dt);
        self.pose();

        if (self.impactAt()) |at| {
            const c = self.clock().?;
            const until: ?f32 = if (self.sweeping()) at - self.t else null;
            if (foe.catchMelee(self, self.swipeReach(), -0.2, until)) {
                self.chips(foe.markOn(self.xf[if (self.hand > 0) WRR else WRL], mathx.zero3), mathx.dirXZ(self.pos, self.parry.at), PARRY_CHIPS);
            } else if (self.state == .shake) {
                if (self.crossed(at, dt)) self.letGo(quarry);
            } else if (self.t >= at and self.t < c.wind + c.strike) {
                self.trySweep(quarry);
            }
        }
        self.tryHit(blade);
        return self.heroHit;
    }

    fn crossed(self: *const Ent, at: f32, dt: f32) bool {
        return self.t >= at and self.t - dt < at;
    }

        /// The return is only a choice if the far hand can reach him — a whiff is not a worse option.
    fn wantsReturn(self: *Ent, quarry: rl.Vector3) bool {
        if (self.aiRng.float() >= RET_CHANCE) return false;
        const d = mathx.distXZ(self.pos, quarry);
        if (d > self.swipeReach()) return false;
        const bearing = foe.bearingDeg(self.pos, self.facing, quarry);
        const mid = -self.hand * SWIPE_ARC_MID;
        return @abs(mathx.wrapDeg(bearing - mid)) <= SWIPE_ARC * 0.5 + mathx.degrees(TURN_RATE * WIND_TURN_SHARE * RET_WIND) +
            combat.subtendedArc(foe.HERO_REACH, d);
    }

    fn trySweep(self: *Ent, quarry: rl.Vector3) void {
        if (self.heroLatch) return;
        const d = mathx.distXZ(self.pos, quarry);
        if (d > self.swipeReach()) return;
        const mid = self.hand * SWIPE_ARC_MID;
        const slack = combat.subtendedArc(foe.HERO_REACH, mathx.maxF(d, 0.6));
        if (@abs(mathx.wrapDeg(foe.bearingDeg(self.pos, self.facing, quarry) - mid)) > SWIPE_ARC * 0.5 + slack) return;
        self.heroHit = if (self.state == .ret) RET_HIT else SWIPE_HIT;
        self.heroLatch = true;
        self.leash.noteCombat();
    }

    fn letGo(self: *Ent, quarry: rl.Vector3) void {
        self.shook = true;
        self.tossN = ACORNS;
        const crown = self.xf[CROWN];
        var i: usize = 0;
        while (i < ACORNS) : (i += 1) {
            const fi: f32 = @floatFromInt(i);
            const a = std.math.tau * fi / @as(f32, ACORNS) + self.aiRng.signed() * 0.35;
            const out = if (i == 0) 0.0 else self.aiRng.range(0.40, 1.0) * ACORN_SCATTER;
            const bough = self.aiRng.angle();
            const lift = self.aiRng.range(0.02, 0.10) * H * self.scale;
            self.tosses[i] = .{
                .from = foe.markOn(crown, v3(
                    mathx.cosf(bough) * 0.09 * H,
                    0.05 * H + lift / mathx.maxF(self.scale, 1e-3),
                    mathx.sinf(bough) * 0.09 * H,
                )),
                .at = v3(quarry.x + mathx.cosf(a) * out, quarry.y + 0.30, quarry.z + mathx.sinf(a) * out),
            };
        }
        self.chips(foe.markOn(crown, v3(0, 0.04 * H, 0)), v3(0, 1, 0), SHAKE_CHIPS);
        self.leash.noteCombat();
    }

    pub fn tryHit(self: *Ent, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        const heavy = foe.wounded(self, s, blade, .{ .light = 0.30, .heavy = 0.75 });
        self.chips(s.contact, s.dir, foe.hitParts(if (heavy) HIT_CHIP_HEAVY else HIT_CHIP_LIGHT));
        sfx.world(.wood_hurt, self.pos);
        switch (s.reaction) {
            .death => {
                self.chips(s.contact, s.dir, foe.hitParts(CHIP_DEATH));
                sfx.world(.wood_die, self.pos);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn enter(self: *Ent, s: State) void {
        self.state = s;
        self.t = 0;
    }
    fn enterStun(self: *Ent, s: State) void {
        self.heroLatch = false;
        self.enter(s);
    }
    fn enterDeath(self: *Ent) void {
        if (self.state == .dead) return;
        self.heroLatch = false;
        self.enter(.dead);
        self.justDied = true;
    }
    pub fn stagger(self: *Ent, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugSwipe(self: *Ent) void {
        self.heroLatch = false;
        self.enter(.swipe);
    }
    pub fn debugShake(self: *Ent) void {
        self.heroLatch = false;
        self.enter(.shake);
    }
    pub fn debugKill(self: *Ent) void {
        self.enterDeath();
    }

    const CHIP_SPRAY = foe.Spray{
        .fanLo = 0.30,
        .fanHi = 1.30,
        .upLo = 0.5,
        .upHi = 2.2,
        .lifeLo = 0.40,
        .lifeHi = 0.90,
        .rLo = 0.024,
        .rHi = 0.052,
        .r1 = 0.012,
        .col = SPLINTER,
        .col1 = ROT,
        .grav = foe.DUST_GRAV,
        .bounce = 0.22,
        .stretch = 0.030,
    };
    fn chips(self: *Ent, at: rl.Vector3, dir: rl.Vector3, n: i32) void {
        foe.spray(&self.parts, &self.fxHead, &self.fxRng, at, dir, n, 3.2, self.scale, CHIP_SPRAY);
    }

    pub fn drawFx(self: *const Ent) void {
        foe.drawParticles(&self.parts);
    }
    pub fn draw(self: *const Ent, model: *const Model) void {
        model.draw(self);
    }

    /// The whole crown rattling through the throw — 7.5 Hz over the strike, decaying into the recovery.
    fn shudder(self: *const Ent) f32 {
        if (self.state != .shake) return 0;
        const from = SHAKE_WIND;
        if (self.t < from) return 0;
        const u = (self.t - from) / (SHAKE_STRIKE + SHAKE_RECOVER * 0.45);
        if (u >= 1) return 0;
        return mathx.sinf(std.math.tau * SHAKE_HZ * (self.t - from)) * (1.0 - u) * (1.0 - u);
    }

    pub fn pose(self: *Ent) void {
        if (!foe.posed(self)) return;
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = foe.rigSink(foe.SINK_HUMANOID, self.scale, self.fade);
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.6, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        const stun = self.motion.reaction;
        const m = self.moving * (1.0 - dk);
        const pel = heromod.pelvisChannels(self.phase, m, self.fwdB, self.latB, A_PROT);

        const creak = SWAY * mathx.gutter(self.elapsed * 0.34 + self.seed * 6.28, self.seed * 5.1) * (1.0 - m);
        const shaking = self.state == .shake;
        const rear = if (shaking) self.motion.load else 0;
        const throwF = if (shaking) self.motion.drive else 0;
        const bodyPitch = 26.0 * throwF - 20.0 * rear - 16.0 * stun + 78.0 * dk +
            (if (shaking) 0.0 else 12.0 * self.motion.drive - 8.0 * self.motion.load);
        const leanX = PELVIS_SHARE * bodyPitch;
        const waist = (1.0 - PELVIS_SHARE) * bodyPitch;
        const lumber = 3.0 * mathx.sinf(std.math.tau * self.phase) * m;
        const shud = self.shudder();

        var wx: [N]rl.Matrix = undefined;
        const pelvY = if (dead) lerpF(hipY, hipY * 0.70, dk) else hipY + pel.bob - pel.dip;
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(creak * 0.5 + lumber * 0.4 + 7.0 * dk), rx(leanX), ry(pel.prot)),
            mul(tr(pel.sway * fs, pelvY * fs + sink, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));
        if (!dead) {
            heromod.legPair(&wx, &self.rest, self.pos.y, self.phase, m, 0, self.fwdB, self.latB, HIPL, KNEEL, HIPR, KNEER, solePatches);
        } else {
            heromod.deadLegs(&wx, self.rest, dk);
        }
        self.poseUpper(&wx, waist, stun, dk, pel.prot, lumber, creak, shud, shaking);
        wx[HELD] = wx[WRR];
        heromod.deflectUpper(&wx, self.deflect.spring.v, self.facing, false);
        self.xf = wx;
    }

    fn poseUpper(self: *Ent, wx: *[N]rl.Matrix, waist: f32, stun: f32, dk: f32, prot: f32, lumber: f32, creak: f32, shud: f32, shaking: bool) void {
        const rest = self.rest;
        const m = self.moving * (1.0 - dk);
        const lean = (self.seed - 0.5) * 7.0;
        // The sweep's own channel: -1 fully cocked, +1 fully through, in the swinging hand's sign.
        const sw = if (shaking) 0 else self.hand * self.motion.body;
        const load = if (shaking) 0 else self.motion.load;
        const drive = if (shaking) 0 else self.motion.drive;

        setLocal(wx, SPINE, rest, mul3(rx(waist * 0.38), ry(-0.25 * prot - 16.0 * sw), rz(lean * 0.4 + creak * 0.5 - 0.3 * lumber + 3.0 * shud)));
        setLocal(wx, CHEST, rest, mul3(rx(waist * 0.62), ry(-0.4 * prot - 22.0 * sw), rz(lean * 0.3 + creak * 0.4 - 0.2 * lumber + 5.0 * shud)));
        setLocal(wx, NECK, rest, mul3(rx(-7.0 * drive + 6.0 * dk - 5.0 * stun - 10.0 * shud), ry(-6.0 * sw), rz(2.0 * shud)));
        setLocal(wx, CROWN, rest, mul3(rx(-14.0 * drive + 11.0 * dk - 22.0 * stun - 18.0 * shud), ry(-0.3 * prot - 8.0 * sw), rz(lean + creak + 9.0 * shud)));

        const armStun = -30.0 * stun;
        const swing = -6.0 * heromod.armSwing(self.phase) * m * @abs(self.fwdB);
        const raise = if (shaking) -96.0 * self.motion.load - 34.0 * self.motion.drive else 0;
        inline for (.{ SHL, SHR }, .{ ELL, ELR }, .{ WRL, WRR }, .{ 1.0, -1.0 }) |sh, el, wr, side| {
            const s = if (side > 0) swing else -swing;
            const own = side * self.hand > 0; // this arm is the swinging one
            const gain: f32 = if (side > 0) 0.96 else 1.04;
            const abd = 20.0 + 6.0 * @abs(lean) +
                (if (shaking) 26.0 * (load + drive) else if (own) 58.0 * mathx.maxF(load, drive) else 10.0 * drive);
            const sweep = if (own) 64.0 * load - 104.0 * drive else -14.0 * drive;
            setLocal(wx, sh, rest, mul3(
                rx(-(8.0 + s) + raise * gain + armStun - 12.0 * dk),
                ry(self.hand * sweep + (if (shaking) 12.0 * shud * side else 0)),
                rz(side * abd),
            ));
            setLocal(wx, el, rest, mul3(
                rx(-(12.0 + (if (own) 34.0 * load - 12.0 * drive else 0) + (if (shaking) 42.0 * self.motion.load else 0))),
                ry(if (shaking) 16.0 * shud * side else 0),
                rz(0),
            ));
            setLocal(wx, wr, rest, mul3(rz(side * 5.0 + 3.0 * creak), ry(if (shaking) 20.0 * shud * side else self.hand * sweep * 0.18), rx(0)));
        }
    }
};

const CAP_N = wf.MAX_PER_KIND;

pub const Copse = struct {
    model: Model,
    ents: [CAP_N]Ent = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Copse {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Copse) []Ent {
        return self.ents[0..self.n];
    }
    pub fn liveConst(self: *const Copse) []const Ent {
        return self.ents[0..self.n];
    }
    pub fn reset(self: *Copse, m: *const wf.Map) void {
        foe.resetGroup(Ent, &self.ents, &self.n, m, .corrupt_ent);
    }
    pub fn summon(self: *Copse, at: rl.Vector3, faceYaw: f32, seed: f32) void {
        foe.summonInto(Ent, &self.ents, &self.n, .corrupt_ent, Ent.spawn(at, faceYaw, 1.0, seed));
    }
    pub fn clear(self: *Copse) void {
        self.n = 0;
    }
    pub fn setShader(self: *Copse, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn setParry(self: *Copse, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    pub fn update(self: *Copse, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    pub fn draw(self: *const Copse, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Copse) void {
        for (self.liveConst()) |*e| e.drawFx();
    }
    pub fn pierce(self: *Copse, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Copse) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn anyParried(self: *const Copse) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn soulsDropped(self: *const Copse) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Copse) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Copse) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

fn buildBones() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = boleMesh(0.130, 0.118, 0.086, 0xE100);
    mesh[SPINE] = boleMesh(0.118, 0.108, -0.126, 0xE101);
    mesh[CHEST] = trunkMesh();
    mesh[NECK] = boleMesh(0.070, 0.060, -0.106, 0xE103);
    mesh[CROWN] = crownMesh();
    mesh[HIPL] = boughMesh(1.0, heromod.SEG_THIGH, 0.074, 0.058, 0xE104);
    mesh[KNEEL] = boughMesh(1.0, heromod.SEG_SHANK, 0.056, 0.044, 0xE105);
    mesh[ANKL] = rootFootMesh(1.0);
    mesh[HIPR] = boughMesh(-1.0, heromod.SEG_THIGH, 0.074, 0.058, 0xE106);
    mesh[KNEER] = boughMesh(-1.0, heromod.SEG_SHANK, 0.056, 0.044, 0xE107);
    mesh[ANKR] = rootFootMesh(-1.0);
    mesh[SHL] = boughMesh(1.0, heromod.SEG_UPARM, 0.062, 0.050, 0xE108);
    mesh[ELL] = boughMesh(1.0, heromod.SEG_FOREARM, 0.050, 0.038, 0xE109);
    mesh[WRL] = clawMesh(1.0);
    mesh[SHR] = boughMesh(-1.0, heromod.SEG_UPARM, 0.062, 0.050, 0xE10A);
    mesh[ELR] = boughMesh(-1.0, heromod.SEG_FOREARM, 0.050, 0.038, 0xE10B);
    mesh[WRR] = clawMesh(-1.0);
    return mesh;
}

/// Bark relief is a few PERCENT of the mass, sunk most of the way in — ridges running WITH the grain, never round it.
fn ridges(b: *Builder, rng: *mathx.Rng, len: f32, r: f32, n: u32) void {
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const a = rng.angle();
        const y0 = -len * H * rng.range(0.02, 0.60);
        const y1 = y0 - len * H * rng.range(0.20, 0.38);
        const rr = r * H * 0.94;
        b.addCapsule(
            v3(mathx.cosf(a) * rr, y0, mathx.sinf(a) * rr),
            v3(mathx.cosf(a + rng.signed() * 0.12) * rr, y1, mathx.sinf(a + rng.signed() * 0.12) * rr),
            0.0042 * H,
            0.0030 * H,
            4,
            if (rng.float() < 0.4) BARK_LT else BARK_DK,
        );
    }
}

fn boleMesh(rTop: f32, rBot: f32, len: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.bark);
    b.addCapsule(v3(0, 0, 0), v3(0, -len * H, 0), rTop * H, rBot * H, 12, BARK);
    ridges(&b, &rng, @abs(len), rBot, 9);
    return b.toMesh();
}

fn trunkMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xE102);
    b.setMat(.bark);
    inline for (.{ -1.0, 1.0 }) |side| {
        b.addCapsule(v3(side * 0.058 * H, 0.050 * H, 0), v3(side * SHOULDER_HALF * H, 0.044 * H, 0), 0.060 * H, 0.050 * H, 12, BARK);
    }
    b.addCapsule(v3(0, -0.016 * H, 0), v3(0, 0.058 * H, 0), 0.122 * H, 0.104 * H, 13, BARK);
    b.addCapsule(v3(0, 0.058 * H, 0), v3(0, 0.082 * H, -0.006 * H), 0.104 * H, 0.074 * H, 12, BARK_LIVE);
    ridges(&b, &rng, 0.090, 0.120, 16);

    b.setMat(.wood);
        // A SPLIT IS BUILT ADDITIVELY — nothing sunk inside the bole is ever seen: the pale strip sits 3% proud of the 0.122 bole and the two bark lips 7%.
    b.addCapsule(v3(0, -0.040 * H, 0.082 * H), v3(0, 0.072 * H, 0.066 * H), 0.046 * H, 0.036 * H, 9, HEARTWOOD);
    inline for (.{ -1.0, 1.0 }) |side| {
        b.addCapsule(v3(side * 0.062 * H, -0.044 * H, 0.092 * H), v3(side * 0.050 * H, 0.070 * H, 0.076 * H), 0.020 * H, 0.015 * H, 7, KNOTHOLE);
    }
    var i: u32 = 0;
    while (i < 6) : (i += 1) {
        const y = rng.range(-0.034, 0.062) * H;
        const s = if (rng.float() < 0.5) @as(f32, 1) else -1;
        b.addCapsule(
            v3(s * 0.030 * H, y, 0.098 * H),
            v3(s * rng.range(0.004, 0.018) * H, y - rng.range(0.020, 0.044) * H, 0.106 * H),
            0.008 * H,
            0.004 * H,
            5,
            SPLINTER,
        );
    }
    b.setMat(.plant);
    b.addBlob(v3(-0.086 * H, 0.020 * H, 0.060 * H), v3(0.030 * H, 0.024 * H, 0.016 * H), 6, 6, CANKER);
    b.addBlob(v3(0.094 * H, -0.012 * H, 0.044 * H), v3(0.024 * H, 0.030 * H, 0.014 * H), 6, 6, CANKER);
    return b.toMesh();
}

fn crownMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xEC0E);
    b.setMat(.bark);
    b.addCapsule(v3(0, -0.062 * H, 0), v3(0, 0.052 * H, 0), 0.078 * H, 0.086 * H, 12, BARK);
    b.addBlob(v3(0, 0.010 * H, 0.008 * H), v3(0.086 * H, 0.062 * H, 0.080 * H), 8, 8, BARK);
    ridges(&b, &rng, 0.100, 0.082, 11);

    b.setMat(.wood);
    b.addBlob(v3(0, 0.054 * H, 0), v3(0.062 * H, 0.012 * H, 0.058 * H), 6, 9, HEARTWOOD);
    var s: u32 = 0;
    while (s < 8) : (s += 1) {
        const a = rng.angle();
        const rr = rng.range(0.018, 0.056) * H;
        b.addCapsule(
            v3(mathx.cosf(a) * rr, 0.052 * H, mathx.sinf(a) * rr),
            v3(mathx.cosf(a) * rr * 1.12, 0.052 * H + rng.range(0.016, 0.048) * H, mathx.sinf(a) * rr * 1.12),
            0.011 * H,
            0.004 * H,
            5,
            SPLINTER,
        );
    }

        // `deadLimbTinted` is the one both leafless trees call.
    b.setMat(.bark);
    var tips: [6]rl.Vector3 = undefined;
    var boughs: u32 = 0;
    while (boughs < 6) : (boughs += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(boughs)) / 6.0 + rng.signed() * 0.34;
        const reach = rng.range(0.21, 0.35) * H;
        const rise = rng.range(0.15, 0.26) * H;
        const root = v3(mathx.cosf(a) * 0.048 * H, 0.040 * H, mathx.sinf(a) * 0.048 * H);
        propwood.deadLimbTinted(&b, &rng, root, a, reach, rise, 0.034 * H, 3, if (boughs & 1 == 0) BARK else BARK_LIVE, SPLINTER);
        tips[boughs] = v3(root.x + mathx.cosf(a) * reach * 0.72, root.y + rise * 0.86, root.z + mathx.sinf(a) * reach * 0.72);
    }

    b.setMat(.plant);
    for (tips) |tip| {
        var n: u32 = 0;
        while (n < 3) : (n += 1) {
            const at = v3(
                tip.x * rng.range(0.52, 1.0) + rng.signed() * 0.016 * H,
                tip.y * rng.range(0.60, 1.02) - 0.010 * H,
                tip.z * rng.range(0.52, 1.0) + rng.signed() * 0.016 * H,
            );
            b.addBlob(at, v3(0.017 * H, 0.022 * H, 0.017 * H), 5, 7, ACORN_SHELL);
            b.addBlob(v3(at.x, at.y + 0.018 * H, at.z), v3(0.018 * H, 0.009 * H, 0.018 * H), 4, 7, ACORN_CUP);
        }
    }

    b.setMat(.plain);
    inline for (.{ -1.0, 1.0 }) |side| {
        b.addBlob(v3(side * 0.036 * H, 0.006 * H, 0.062 * H), v3(0.024 * H, 0.022 * H, 0.014 * H), 6, 7, KNOTHOLE);
        b.addBlob(v3(side * 0.036 * H, 0.006 * H, 0.072 * H), v3(0.014 * H, 0.013 * H, 0.008 * H), 5, 7, EYE);
    }
    b.addCapsule(v3(-0.030 * H, -0.038 * H, 0.066 * H), v3(0.030 * H, -0.042 * H, 0.066 * H), 0.014 * H, 0.011 * H, 6, KNOTHOLE);
    return b.toMesh();
}

fn boughMesh(side: f32, len: f32, rTop: f32, rBot: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
        // WABI-SABI BETWEEN THE INSTANCES, NOT ALONG ONE: alternated segment by segment the two tones band a limb like a barber's pole, so the pick is per LIMB.
    const tone = if (seed & 1 == 0) BARK else BARK_LIVE;
    b.setMat(.bark);
    const knee = v3(side * 0.012 * H, -len * H * 0.56, 0.008 * H);
    const tip = v3(side * 0.030 * H, -len * H, -0.006 * H);
    b.addCapsule(v3(0, 0, 0), knee, rTop * H, (rTop + rBot) * 0.5 * H, 10, tone);
    b.addCapsule(knee, tip, (rTop + rBot) * 0.5 * H, rBot * H, 10, tone);
    b.addBlob(v3(0, 0.005 * H, 0), v3(rTop * 1.20 * H, rTop * 1.06 * H, rTop * 1.20 * H), 7, 6, tone);
    b.addBlob(knee, v3(rTop * 1.10 * H, rTop * 0.96 * H, rTop * 1.10 * H), 6, 6, BARK_LT);
    ridges(&b, &rng, len, rBot, 7);
    return b.toMesh();
}

/// The hand is the far end of the bough, and it is what the sweep is measured to.
fn clawMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 0xE1C1 else 0xE1C2);
    b.setMat(.bark);
    const wrist = v3(0, 0, 0);
    const palm = v3(side * 0.020 * H, -0.092 * H, 0.008 * H);
    b.addCapsule(wrist, palm, 0.044 * H, 0.040 * H, 9, BARK);
    b.addBlob(palm, v3(0.050 * H, 0.040 * H, 0.046 * H), 7, 7, BARK);
    b.setMat(.wood);
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const f = (@as(f32, @floatFromInt(i)) - 1.0);
        const a = 0.35 * f + rng.signed() * 0.12;
        const elbow = v3(palm.x + mathx.sinf(a) * 0.048 * H, palm.y - 0.066 * H, palm.z + mathx.cosf(a) * 0.038 * H);
        const end = v3(elbow.x + mathx.sinf(a) * 0.052 * H, elbow.y - 0.058 * H + rng.range(-0.016, 0.008) * H, elbow.z + mathx.cosf(a) * 0.032 * H);
        b.addCapsule(palm, elbow, 0.024 * H, 0.017 * H, 7, BARK_DK);
        b.addCapsule(elbow, end, 0.017 * H, 0.010 * H, 7, BARK_DK);
        b.addBlob(elbow, v3(0.019 * H, 0.017 * H, 0.019 * H), 4, 7, BARK_DK);
        b.addBlob(end, v3(0.013 * H, 0.011 * H, 0.013 * H), 4, 7, SPLINTER);
    }
    return b.toMesh();
}

fn rootFootMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) @as(u64, 0xE00F) else 0xE010);
    b.setMat(.bark);
    b.addBlob(v3(0, 0.008 * H, 0.014 * H), v3(0.066 * H, 0.036 * H, 0.080 * H), 8, 7, BARK);
    var i: u32 = 0;
    while (i < 6) : (i += 1) {
        const a = rng.range(-1.3, 1.3) + (if (side > 0) @as(f32, 0.25) else @as(f32, -0.25));
        const toe = v3(mathx.sinf(a) * 0.074 * H, -0.016 * H, mathx.cosf(a) * 0.092 * H);
        b.addCapsule(v3(0, 0.006 * H, 0.010 * H), toe, 0.016 * H, 0.007 * H, 6, BARK_DK);
        b.addBlob(toe, v3(0.009 * H, 0.007 * H, 0.009 * H), 4, 5, ROT);
    }
    return b.toMesh();
}

/// ONE NUT, drawn by `game.drawArrows` off the shared `archer.Shot` pipeline.
pub fn acornModel(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plant);
    b.addBlob(v3(0, 0, 0), v3(ACORN_R, ACORN_R * 1.35, ACORN_R), 7, 8, ACORN_SHELL);
    b.addBlob(v3(0, ACORN_R * 0.95, 0), v3(ACORN_R * 1.05, ACORN_R * 0.45, ACORN_R * 1.05), 5, 8, ACORN_CUP);
    b.addCapsule(v3(0, ACORN_R * 1.2, 0), v3(0, ACORN_R * 1.7, 0), ACORN_R * 0.14, ACORN_R * 0.08, 5, ACORN_CUP);
    return b.toModel(shader);
}

test "the pick is positional: sweep in reach, shake at range, and the crown is telegraphed once" {
    try std.testing.expectEqual(Choice.swipe, classify(3.0, 0, 0, 1.0, true, true, false));
    try std.testing.expectEqual(Choice.wait, classify(3.0, 0, 0, 1.0, false, true, false));
    try std.testing.expectEqual(Choice.shake, classify(9.0, 0, 0, 1.0, true, true, false));
    try std.testing.expectEqual(Choice.close, classify(9.0, 0, 0, 1.0, true, false, false));
    try std.testing.expectEqual(Choice.close, classify(19.0, 0, 0, 1.0, true, true, false));
    try std.testing.expectEqual(Choice.rest, classify(AGGRO_R + 1.0, 0, 0, 1.0, true, true, false));
    try std.testing.expectEqual(Choice.hold, classify(AGGRO_R + 1.0, 0, HOME_R + 1.0, 1.0, true, true, false));
    const overrun = foe.hurtReach(SWIPE_R, wf.FOE_SCALE_HI);
    try std.testing.expect(overrun > SHAKE_MIN);
    try std.testing.expectEqual(Choice.swipe, classify(SHAKE_MIN + 0.1, 0, 0, wf.FOE_SCALE_HI, true, true, false));

    var e = Ent.spawn(mathx.zero3, 0, 1.0, 0.3);
    e.swipeCd = 0;
    const hero = v3(0, 0, 2.6);
    e.facing = mathx.headingXZ(mathx.dirXZ(e.pos, hero));
    e.debugSwipe();
    var landed: u32 = 0;
    var firstAt: f32 = 0;
    var t: f32 = 0;
    while (t < SWIPE_WIND + SWIPE_STRIKE + SWIPE_RECOVER - 0.02) : (t += 1.0 / 60.0) {
        if (e.update(1.0 / 60.0, hero, 400, .{}) != null) {
            if (landed == 0) firstAt = t;
            landed += 1;
        }
    }
    std.debug.print("\n  corrupt ent: sweep bills once, {d:.2} s in (tell floor {d:.2}); sector {d:.0} deg out to {d:.2} m\n", .{ firstAt, foe.TELL_MIN, SWIPE_ARC, foe.hurtReach(SWIPE_R, 1.0) });
    try std.testing.expectEqual(@as(u32, 1), landed);
    try std.testing.expect(firstAt >= foe.TELL_MIN);
}

test "THE BOUGH LANDS ON THE MAN WHERE HE STANDS - thrown for real, either side, at every scale" {
    const dt: f32 = 1.0 / 120.0;
    var misses: usize = 0;
    var thrown: usize = 0;
    var widest: f32 = 0;
    for ([_]f32{ wf.FOE_SCALE_LO, 1.0, wf.FOE_SCALE_HI }) |scale| {
        const probe = Ent.spawn(mathx.ground(0, 0), 0, scale, 0.31);
        const apart = foe.closestApproach(probe.bodyR());
        const far = foe.hurtReach(SWIPE_R, scale);
        for ([_]f32{ -1.0, 1.0 }) |sign| {
            for ([_]f32{ 0.0, 0.34, 0.67, 0.92, 1.0 }) |u| {
                const stand = lerpF(apart + 0.05, far - 0.002, u);
                const gate = swipeBearing(stand, SWIPE_WIND);
                widest = @max(widest, gate);
                for ([_]f32{ 0.0, 0.5, 0.9, 1.0 }) |bu| {
                    const deg = sign * gate * bu;
                    if (classify(stand, deg, 0, scale, true, false, false) != Choice.swipe) continue;
                    thrown += 1;
                    var c = Ent.spawn(mathx.ground(0, 0), 0, scale, 0.31);
                    c.swipeCd = 0;
                    c.shakeCd = 1000;
                    const a = mathx.radians(deg);
                    const hero = v3(@sin(a) * stand, 0, @cos(a) * stand);
                    var hit = false;
                    var t: f32 = 0;
                    while (t < SWIPE_WIND + SWIPE_STRIKE + SWIPE_RECOVER + 0.2) : (t += dt) {
                        if (c.update(dt, hero, 400.0, .{}) != null) {
                            hit = true;
                            break;
                        }
                    }
                    if (!hit) {
                        misses += 1;
                        std.debug.print("\n  x{d:.2} at {d:.2} m, {d:.0} deg off: MISSED - the gate says {d:.0} deg, the sector is {d:.0} out to {d:.2}\n", .{ scale, stand, deg, gate, SWIPE_ARC, far });
                    }
                }
            }
        }
    }
    std.debug.print("\n  corrupt ent: {d} stands thrown across three scales and both sides, {d} billed nothing; the widest gate handed out is {d:.0} deg\n", .{ thrown, misses, widest });
    try std.testing.expectEqual(@as(usize, 0), misses);
}

test "THE CROWN LETS GO ALL AT ONCE - one nut on the man, the rest fanned round him" {
    var e = Ent.spawn(mathx.ground(0, 0), 0, 1.0, 0.42);
    const hero = v3(0, 0, 9.0);
    e.facing = mathx.headingXZ(mathx.dirXZ(e.pos, hero));
    e.debugShake();
    var frames: u32 = 0;
    var release: f32 = 0;
    var got: usize = 0;
    var tosses: [ACORNS]Toss = undefined;
    var t: f32 = 0;
    while (t < SHAKE_WIND + SHAKE_STRIKE + SHAKE_RECOVER + 0.1) : (t += 1.0 / 120.0) {
        _ = e.update(1.0 / 120.0, hero, 400, .{});
        if (e.tossN == 0) continue;
        frames += 1;
        release = t;
        got = e.tossN;
        tosses = e.tosses;
    }
    try std.testing.expectEqual(@as(u32, 1), frames);
    try std.testing.expectEqual(ACORNS, got);
    try std.testing.expect(release >= foe.TELL_MIN);

    var near: f32 = 1e9;
    var offs: [ACORNS]f32 = undefined;
    for (tosses[0..got], 0..) |tos, i| {
        offs[i] = mathx.distXZ(tos.at, hero);
        near = @min(near, offs[i]);
        try std.testing.expect(offs[i] <= ACORN_SCATTER + 1e-3);
        try std.testing.expect(tos.from.y > TOP_F * H * 0.6);
    }
    try std.testing.expectApproxEqAbs(@as(f32, 0), near, 1e-3);
    std.debug.print("\n  corrupt ent: {d} nuts let go {d:.2} s in (wind {d:.2}), scattered ", .{ got, release, SHAKE_WIND });
    for (offs[0..got]) |o| std.debug.print("{d:.2} ", .{o});
    std.debug.print("m off him (ring {d:.1} m each)\n", .{ACORN_SPLASH_R});
}

test "AND A NUT IS A REAL ARC: it comes down where it was thrown, with time to be somewhere else" {
    const archermod = @import("archer.zig");
    const dt: f32 = 1.0 / 120.0;
    var worst: f32 = 0;
    var slowest: f32 = 0;
    var quickest: f32 = 1e9;
    for ([_]f32{ SHAKE_MIN, 11.0, SHAKE_MAX }) |range| {
        const from = v3(0, TOP_F * H * 0.92, 0);
        const at = v3(0, 0.30, range);
        var a = archermod.launchShaft(from, at, ACORN_SPEED, ACORN_HIT, true, .acorn);
        var flight: f32 = 0;
        while (a.live and !a.stuck and flight < 8.0) : (flight += dt) _ = archermod.stepShaft(&a, 0, &.{}, dt);
        const miss = mathx.distXZ(a.pos, at);
        worst = @max(worst, miss);
        slowest = @max(slowest, flight);
        quickest = @min(quickest, flight);
        std.debug.print("  acorn thrown {d:.1} m: {d:.2} s in the air, landed {d:.2} m off the mark\n", .{ range, flight, miss });
    }
    try std.testing.expect(worst <= ACORN_SPLASH_R);
    try std.testing.expect(quickest >= 0.45);
    try std.testing.expect(slowest <= 3.0);
}

test "IT IS THE BIGGEST THING THAT WALKS, AND FIRE IS THE ANSWER" {
    const ogremod = @import("ogre.zig");
    std.debug.print("\n  corrupt ent {d:.2} m against the cyclops's {d:.2} m and the birchwight's 2.15\n", .{ H, heromod.H * ogremod.SCALE });
    try std.testing.expect(H > heromod.H * ogremod.SCALE);

    const shot = 50.0;
    var fire = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    var levin = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    var rime = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    var rot = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    _ = fire.hit(.{ .elem = combat.elems(.{ .fire = shot }) });
    _ = levin.hit(.{ .elem = combat.elems(.{ .lightning = shot }) });
    _ = rime.hit(.{ .elem = combat.elems(.{ .cold = shot }) });
    _ = rot.hit(.{ .elem = combat.elems(.{ .chaos = shot }) });
    std.debug.print("  50 into a corrupt ent: fire {d:.0}, lightning {d:.0}, cold {d:.0}, chaos {d:.0}\n", .{ HP_MAX - fire.hp, HP_MAX - levin.hp, HP_MAX - rime.hp, HP_MAX - rot.hp });
    try std.testing.expect(HP_MAX - fire.hp > HP_MAX - levin.hp);
    try std.testing.expect(HP_MAX - levin.hp > HP_MAX - rime.hp);
    try std.testing.expect(HP_MAX - rime.hp > HP_MAX - rot.hp);
}

test "IT IS NO HARDER TO REACH THAN THE CYCLOPS — a tall body's hurt sphere is sized against his chest" {
    const ogremod = @import("ogre.zig");
    const Reach = struct {
        fn of(bodyR: f32, hurtR: f32, centerY: f32) f32 {
            const apart = foe.closestApproach(bodyR);
            const up = centerY - foe.HERO_CHEST;
            return @sqrt(apart * apart + up * up) / hurtR;
        }
    };
    const e = Ent.spawn(mathx.ground(0, 0), 0, 1.0, 0.31);
    const o = ogremod.Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.31);
    const mine = Reach.of(e.bodyR(), e.hurtRadius(), e.centerWorld().y);
    const his = Reach.of(o.bodyR(), o.hurtRadius(), o.centerWorld().y);
    std.debug.print("\n  corrupt ent: sphere {d:.2} m about a centre {d:.2} m up, nearest stand {d:.2} m — his chest is x{d:.2} of the radius off it (cyclops x{d:.2})\n", .{ e.hurtRadius(), e.centerWorld().y, foe.closestApproach(e.bodyR()), mine, his });
    try std.testing.expect(mine <= his);
    try std.testing.expect(e.centerWorld().y - e.hurtRadius() < foe.HERO_CHEST);
}

test "THE RETURN COMES OFF THE FAR HAND — the answer to rolling round behind the first sweep" {
    const dt: f32 = 1.0 / 120.0;
    var fired: usize = 0;
    var billed: usize = 0;
    var lead: f32 = 0;
    for (0..24) |i| {
        var e = Ent.spawn(mathx.ground(0, 0), 0, 1.0, @as(f32, @floatFromInt(i)) / 24.0);
        e.swipeCd = 0;
        e.shakeCd = 1000;
        const hero = v3(2.2, 0, 1.8);
        e.facing = mathx.headingXZ(mathx.dirXZ(e.pos, hero));
        e.debugSwipe();
        var opener = e.hand;
        var sawRet = false;
        var retHits: usize = 0;
        var t: f32 = 0;
        var retAt: f32 = 0;
        while (t < 6.0) : (t += dt) {
            const blow = e.update(dt, hero, 400.0, .{});
            if (e.state == .swipe) opener = e.hand;
            if (e.state == .ret) {
                if (!sawRet) {
                    sawRet = true;
                    retAt = t;
                    try std.testing.expect(e.hand == -opener);
                }
                if (blow != null) retHits += 1;
            } else if (sawRet) break;
        }
        if (!sawRet) continue;
        fired += 1;
        lead += retAt;
        if (retHits == 1) billed += 1;
    }
    lead /= @floatFromInt(@max(fired, 1));
    std.debug.print("\n  corrupt ent: the return chained on {d} of 24 seeds (per-sweep chance {d:.2}), all {d} of them billing exactly once off the far hand; the first lands {d:.2} s into the exchange\n", .{ fired, RET_CHANCE, billed, lead });
    try std.testing.expect(fired > 0);
    try std.testing.expectEqual(fired, billed);
    try std.testing.expect(RET_WIND < SWIPE_WIND);
}
