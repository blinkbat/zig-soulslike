const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const sfx = @import("../core/audio.zig");
const elemfx = @import("../gfx/elemfx.zig");

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

// THE CINDER WAKE (owner's creature, owner's brief) — a body burnt down to the core that is still walking,
// and **THE GROUND IT WALKS OVER STAYS BURNING**. Every other hazard in the game is thrown at a place; this
// one is LAID, continuously, by the creature's own feet.
//
// **THE ARENA IS THE FIGHT.** It lays trail only while it MOVES, so a standing wake is standing on safe
// ground and a chasing one is spending the room. At `CHASE_SPEED` over `EMBER_LIFE` the live trail is 11.3 m
// of burning line behind it (asserted below) — a wall that expires, not a flood that does not.
//
// **AND IT IS SLOWER THAN YOU ARE.** `CHASE_SPEED` sits just over the hero's WALK and well under his run, so
// distance is always available. What it costs is the direction you spend getting it, which is the whole
// lesson: kill it early, and never circle the way it came.
//
// **COLD IS THE COUNTER AND FIRE IS NOTHING AT ALL TO IT.** Not the same bargain the birchwight offers: a
// torch makes THAT one worse and kills it, while a torch spent on this one is a torch spent on nothing.

pub const H: f32 = 1.66;
const HIP_HALF = heromod.HIP_HALF * 0.92;
const SHOULDER_HALF = heromod.SHOULDER_HALF * 0.88;
const REST = heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);

const N = heromod.N;
const ROOT = heromod.ROOT;
const SPINE = heromod.SPINE;
const CHEST = heromod.CHEST;
const NECK = heromod.NECK;
const SKULL = heromod.HEAD;
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
/// The rake is its own two hands. Bone 17 is never posed and never drawn — `Model.draw` walks `0..HELD`.
const HELD = heromod.HELD;

const solePatches = [_]heromod.SolePatch{
    .{ .bone = ANKL, .heel = 0.040 * H, .toe = 0.158 * H, .halfW = 0.048 * H, .drop = 0.032 * H },
    .{ .bone = ANKR, .heel = 0.040 * H, .toe = 0.158 * H, .halfW = 0.048 * H, .drop = 0.032 * H },
};

// **AUTHOR THE CRUST DARK AND LET THE SEAMS BE THE ONLY BRIGHT THING.** The body is a large smooth mass, so
// screen ∝ albedo^(1/2.2) puts it well above its albedo; the seam has to out-read it by a lot or the creature
// is a grey man. Crust 34 -> screen ~112, seam 226 clips toward white, which is the point.
const CRUST = rgba(34, 30, 28, 255);
const CRUST_LT = rgba(52, 46, 42, 255);
const CHAR = rgba(16, 14, 13, 255);
const ASH_DUST = rgba(118, 110, 102, 190);
const SEAM = rgba(226, 96, 28, 255);
const SEAM_DK = rgba(148, 50, 14, 255);
const EYE = rgba(255, 172, 72, 255);

pub const AGGRO_R: f32 = 14.0;
const HOME_R: f32 = 2.4;
const WALK_SPEED: f32 = heromod.WALK_SPEED * 0.55;
/// Just over the hero's WALK (1.7) and half his run. Backing off on foot does not shake it; RUNNING does, and
/// running is the whole cost — it commits you to a bearing while the trail eats the one behind you.
const CHASE_SPEED: f32 = heromod.WALK_SPEED * 1.02;
const ACCEL: f32 = 2.6;
const TURN_RATE: f32 = 2.4;

const BODY_R: f32 = 0.34;
const HURT_R: f32 = 0.52;
const CENTER_F: f32 = 0.56;
const TOP_F: f32 = 1.00;

const HP_MAX: f32 = 130.0;
const POISE_MAX: f32 = 22.0;
const STANCE_MAX: f32 = 34.0;
/// **FIRE IS NOTHING TO IT AND COLD IS THE ANSWER** — the one body a torch makes worse. `RES_CAP` is 75, so
/// the fire row is written at the cap rather than at a number that reads stronger than it can be.
const RESISTS = combat.resists(.{ .fire = 75, .cold = -70, .chaos = 25 });
pub const SOULS: u32 = 180;

const RAKE_R: f32 = 1.75;
const RAKE_FRONT_DOT: f32 = 0.42;
const RAKE_WIND: f32 = 0.44;
const RAKE_STRIKE: f32 = 0.20;
const RAKE_RECOVER: f32 = 0.72;
const RAKE_CD: f32 = 2.4;
pub const RAKE_HIT = combat.Hit{ .dmg = 13, .poise = 12, .stance = 9, .elem = combat.elems(.{ .fire = 11 }) };

// **THE TRAIL.** One `Ember` every `TRAIL_SPACING` of travel, each a disc of `EMBER_R` that burns for
// `EMBER_LIFE`. Spacing is under one diameter, so the line is CONTINUOUS rather than a row of dots you can
// thread — asserted below, because a gap you can walk through is the mechanic not existing.
pub const EMBER_R: f32 = 0.52;
pub const EMBER_LIFE: f32 = 6.5;
const TRAIL_SPACING: f32 = 0.42;
/// **PER SECOND STANDING IN IT.** Burning decays at 30/s (`combat.AILS`), so this is net +28 and a stand-in
/// fills the meter in 3.6 s. Crossing costs the entry bolus alone (`foe.ENTRY_BOLUS`) — a fifth of the bar,
/// gone in 0.66 s — so one crossing is a real bill and three in a row is a burn.
pub const TRAIL_BUILD: f32 = 58.0;

comptime {
    std.debug.assert(TRAIL_SPACING < 2.0 * EMBER_R);
    std.debug.assert(RAKE_WIND >= foe.TELL_MIN);
    std.debug.assert(CHASE_SPEED > heromod.WALK_SPEED and CHASE_SPEED < heromod.RUN_SPEED);
    // The live trail the header quotes, held here rather than only printed by a test.
    std.debug.assert(CHASE_SPEED * EMBER_LIFE > 8.0 and CHASE_SPEED * EMBER_LIFE < 14.0);
}

const DEATH_DUR: f32 = 1.15;
const DISS_DUR: f32 = 1.0;
const SHOVE_DECAY: f32 = 7.0;
const DISSOLVE = foe.Dissolve{ .rate = 40.0, .spread = 0.5, .rise = 0.9, .flake = ASH_DUST };

const A_PROT: f32 = 2.6;
const HUNCH: f32 = 16.0;
const PELVIS_SHARE: f32 = 1.0 / 6.0;

const SEAM_RATE: f32 = 14.0;
const SEAM_RATE_RAKE: f32 = 60.0;
const HIT_ASH_LIGHT = 4;
const HIT_ASH_HEAVY = 9;
/// Sized by ARITHMETIC over the worst frame: the seam emitter at its rake rate for one mote-life, plus a heavy
/// blow's ash and the wound haze the shared code lays on top.
const PARTS = 52;
comptime {
    std.debug.assert(@as(f32, PARTS) >= SEAM_RATE_RAKE * 0.52 +
        @as(f32, @floatFromInt(foe.hitParts(HIT_ASH_HEAVY) + foe.WOUND_PARTS)));
}

const State = enum { idle, walk, rake, stunlight, stunheavy, dead };

const Choice = enum { rest, hold, close, rake };

/// Pure over one situation, so the pick is testable without a body. `gap` is to the quarry's SKIN.
fn classify(gap: f32, sensed: f32, homeGap: f32, rakeReady: bool, rooted: bool) Choice {
    if (sensed > AGGRO_R) return if (homeGap > HOME_R) .hold else .rest;
    if (gap <= RAKE_R and rakeReady) return .rake;
    if (rooted) return .rest;
    return .close;
}

pub const Model = struct {
    bone: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        return .{ .bone = buildBones(), .mat = gfx.material(shader, "cinder wake") };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, c: *const Cinder) void {
        for (0..HELD) |i| rl.drawMesh(self.bone[i], self.mat, c.xf[i]);
    }
};

pub const Cinder = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
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
    rakeCd: f32 = 0,
    speed: f32 = 0,
    lift: f32 = 0,

    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,

    /// Metres of travel banked since the last ember. The trail is laid off DISTANCE, never a clock, or a
    /// chilled wake lays the same line in the same seconds while covering a third of the ground.
    laid: f32 = 0,
    /// One-frame, read by the group after `update`: where an ember is owed this frame.
    dropAt: ?rl.Vector3 = null,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    heroLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    heroHit: ?combat.Hit = null,
    justDied: bool = false,
    parried: bool = false,
    parry: foe.Parry = .{},
    fade: f32 = 0,
    gone: bool = false,

    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),
    aiRng: mathx.Rng = mathx.Rng.init(2),

    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = REST,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Cinder {
        var c = Cinder{ .pos = home, .home = home, .facing = faceYaw, .scale = scale, .seed = seed };
        c.fxRng = foe.fxStream(seed, 51217.0, 0xC1AD);
        c.aiRng = foe.fxStream(seed, 28879.0, 7);
        c.rakeCd = seed * 0.8;
        c.pose();
        return c;
    }

    pub fn centerWorld(self: *const Cinder) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H, self.scale, self.lift);
    }
    pub fn lockPoint(self: *const Cinder) rl.Vector3 {
        return foe.markOn(self.xf[CHEST], v3(0, 0.03 * H, 0));
    }
    pub fn topWorld(self: *const Cinder) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * H, self.scale, self.lift);
    }
    pub fn hurtRadius(self: *const Cinder) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Cinder) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Cinder) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Cinder) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Cinder) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    /// **IT NEVER LEAVES THE GROUND, AND THAT IS THE MECHANIC** — the trail is laid by feet on earth, so a
    /// wake with a hop would have a way to cross its own line without paying for it.
    pub fn airborne(_: *const Cinder) bool {
        return false;
    }
    pub fn flashFrac(self: *const Cinder) f32 {
        return foe.flashFrac(self.flash);
    }
    pub fn kind(self: *const Cinder) wf.FoeKind {
        _ = self;
        return .cinder_wake;
    }

    pub fn navWant(self: *const Cinder, quarry: rl.Vector3) ?rl.Vector3 {
        if (self.state != .idle and self.state != .walk) return null;
        if (foe.senseHero(&self.leash, self.pos, quarry, AGGRO_R) <= AGGRO_R) return quarry;
        return if (mathx.distXZ(self.pos, self.home) > HOME_R) self.home else null;
    }

    fn faceToward(self: *Cinder, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }

    /// Where the rake is in its own clock, 0 gathered to 1 driven through, and back to 0 across the recovery.
    fn rakeAmt(self: *const Cinder) f32 {
        if (self.state != .rake) return 0;
        if (self.t < RAKE_WIND) return -mathx.smoothstep(0, RAKE_WIND * 0.92, self.t);
        const s = self.t - RAKE_WIND;
        if (s < RAKE_STRIKE) return lerpF(-1.0, 1.0, foe.swingCurve(s / RAKE_STRIKE));
        return 1.0 - mathx.smoothstep(RAKE_STRIKE, RAKE_STRIKE + RAKE_RECOVER * 0.7, s);
    }

    fn stunAmount(self: *const Cinder) f32 {
        if (self.state != .stunlight and self.state != .stunheavy) return 0;
        return foe.stunCurve(self.t, self.state == .stunheavy);
    }

    pub fn update(self: *Cinder, dt: f32, quarry: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.heroHit = null;
        self.dropAt = null;
        self.justDied = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.vit.tick(dt);
        self.elapsed += dt;
        self.t += dt;
        self.rakeCd = mathx.maxF(0, self.rakeCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, self.home, quarry, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        var movedDist: f32 = 0;
        var moveSpeed: f32 = 0;
        var moveYaw: ?f32 = null;

        switch (self.state) {
            .dead => {
                self.speed = 0;
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
            .stunlight, .stunheavy => {
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                if (self.t >= combat.foeStunDur(self.state == .stunheavy)) self.enter(.idle);
            },
            .rake => {
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                if (self.t < RAKE_WIND) self.faceToward(quarry, dt);
                const s = self.t - RAKE_WIND;
                if (s >= 0 and s < RAKE_STRIKE) self.tryRake(quarry);
                if (self.t >= RAKE_WIND + RAKE_STRIKE + RAKE_RECOVER) {
                    self.heroLatch = false;
                    self.enter(.idle);
                }
            },
            .idle, .walk => {
                const sensed = foe.senseHero(&self.leash, self.pos, quarry, AGGRO_R);
                const gap = mathx.maxF(0, sensed - foe.HERO_R - self.bodyR());
                const homeGap = mathx.distXZ(self.pos, self.home);
                switch (classify(gap, sensed, homeGap, self.rakeCd <= 0, self.root.held())) {
                    .rest => {
                        if (sensed <= AGGRO_R) self.faceToward(quarry, dt);
                        self.speed = approach(self.speed, 0, ACCEL * dt);
                        self.state = .idle;
                    },
                    .rake => {
                        self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                        self.rakeCd = RAKE_CD * self.aiRng.range(0.85, 1.25);
                        self.heroLatch = false;
                        self.enter(.rake);
                        sfx.world(.shroom_coo, self.pos);
                    },
                    .hold, .close => |ch| {
                        const to = if (ch == .hold) self.home else quarry;
                        const want = if (ch == .hold) WALK_SPEED else CHASE_SPEED;
                        self.faceToward(self.nav.aim(self.pos, to), dt);
                        self.speed = approach(self.speed, want, ACCEL * dt);
                        moveSpeed = self.speed;
                        const moved = moveSpeed * dt * self.chill.travel();
                        const way = self.nav.along(mathx.headingDir(self.facing));
                        mathx.stepXZ(&self.pos, way, moved, bounds);
                        movedDist = moved;
                        moveYaw = mathx.headingXZ(way);
                        self.state = .walk;
                        self.layTrail(moved);
                    },
                }
            },
        }

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        self.emitSeams(dt);
        self.pose();
        self.tryHit(blade);
        return self.heroHit;
    }

    /// **LAID OFF DISTANCE, AND ONLY WHILE IT TRAVELS.** A standing wake stands on safe ground, which is the
    /// one thing that makes the trail readable: what is burning is exactly where it has BEEN.
    fn layTrail(self: *Cinder, moved: f32) void {
        if (self.state == .dead) return;
        const step = TRAIL_SPACING * self.scale;
        self.laid += moved;
        if (self.laid < step) return;
        // **THE SURPLUS IS CARRIED, NOT DROPPED.** Zeroed, a frame long enough to cover more than one spacing
        // threw the remainder away and the line thinned wherever the frame rate did.
        self.laid -= step;
        self.dropAt = v3(self.pos.x, self.pos.y, self.pos.z);
    }

    fn tryRake(self: *Cinder, quarry: rl.Vector3) void {
        if (self.heroLatch) return;
        if (!foe.inFront(self.pos, self.facing, quarry, foe.hurtReach(RAKE_R, self.scale), RAKE_FRONT_DOT)) return;
        self.heroHit = RAKE_HIT;
        self.heroLatch = true;
        self.leash.noteCombat();
    }

    pub fn tryHit(self: *Cinder, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        const heavy = foe.wounded(self, s, blade, .{ .light = 0.60, .heavy = 1.30 });
        self.ashBurst(s.contact, foe.hitParts(if (heavy) HIT_ASH_HEAVY else HIT_ASH_LIGHT));
        sfx.world(.shroom_hurt, self.pos);
        switch (s.reaction) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn enter(self: *Cinder, s: State) void {
        self.state = s;
        self.t = 0;
    }
    fn enterStun(self: *Cinder, s: State) void {
        self.heroLatch = false;
        self.enter(s);
    }
    fn enterDeath(self: *Cinder) void {
        if (self.state == .dead) return;
        self.heroLatch = false;
        self.enter(.dead);
        self.justDied = true;
        sfx.world(.shroom_die, self.pos);
    }
    pub fn stagger(self: *Cinder, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugRake(self: *Cinder) void {
        self.heroLatch = false;
        self.enter(.rake);
    }
    pub fn debugKill(self: *Cinder) void {
        self.enterDeath();
    }

    /// **THE SEAMS ARE WHERE THE CREATURE IS, NOT WHERE IT WENT** — they rise off the chest and the raking
    /// hands, so the body reads hot while the trail behind it reads spent.
    fn emitSeams(self: *Cinder, dt: f32) void {
        if (self.state == .dead) return;
        const raking = self.state == .rake;
        var owed = foe.emitDue(&self.fxAccum, dt, if (raking) SEAM_RATE_RAKE else SEAM_RATE);
        const sig = elemfx.sig(.fire);
        while (owed > 0) : (owed -= 1) {
            const from = if (raking and self.fxRng.float() < 0.6)
                foe.markOn(self.xf[if (self.fxRng.float() < 0.5) WRL else WRR], mathx.zero3)
            else
                foe.markOn(self.xf[CHEST], v3(self.fxRng.signed() * 0.05 * H, self.fxRng.range(-0.03, 0.06) * H, 0.05 * H));
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.2, 0.7);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = from,
                .v = v3(mathx.cosf(a) * sp, self.fxRng.range(0.5, 1.4), mathx.sinf(a) * sp),
                .life = self.fxRng.range(0.24, 0.52),
                .r0 = sig.r0,
                .r1 = sig.r1,
                .col = sig.core,
                .col1 = sig.cool,
                .grav = sig.grav,
                .drag = sig.drag,
            });
        }
    }

    /// **ASH LEAVES A BURNT BODY, NOT BLOOD.** A puff rather than a chip spray: nothing solid comes off it,
    /// which is also why a heavy blow reads as a cloud and not as a wound.
    const ASH_PUFF = foe.Puff{
        .blast = foe.Blast.of(foe.DUST_DRAG, 0.30, 0.55),
        .spdLo = 0.4,
        .upLo = 0.4,
        .upHi = 1.5,
        .rLo = 0.026,
        .rHi = 0.052,
        .col = ASH_DUST,
        .col1 = foe.DUST_THIN,
    };
    fn ashBurst(self: *Cinder, at: rl.Vector3, n: i32) void {
        foe.puff(&self.parts, &self.fxHead, &self.fxRng, at, n, 2.0, 0.18, self.scale, ASH_PUFF);
    }

    pub fn drawFx(self: *const Cinder) void {
        foe.drawParticles(&self.parts);
    }
    pub fn draw(self: *const Cinder, model: *const Model) void {
        model.draw(self);
    }

    pub fn pose(self: *Cinder) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = foe.rigSink(foe.SINK_HUMANOID, self.scale, self.fade);
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.55, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        const stun = self.stunAmount();
        const m = self.moving * (1.0 - dk);
        const pel = heromod.pelvisChannels(self.phase, m, self.fwdB, self.latB, A_PROT);
        const rake = self.rakeAmt();

        const bodyPitch = HUNCH + 14.0 * rake - 24.0 * stun + 44.0 * dk;
        const leanX = PELVIS_SHARE * bodyPitch;
        const waist = (1.0 - PELVIS_SHARE) * bodyPitch;
        const lumber = 3.6 * mathx.sinf(std.math.tau * self.phase) * m;
        const bellows = mathx.sinf(self.elapsed * 0.9 + self.seed * 6.28) * (1.0 - m);

        var wx: [N]rl.Matrix = undefined;
        const collapse = lerpF(hipY, 0.22 * H, dk);
        const pelvY = if (dead) collapse else hipY + pel.bob - pel.dip;
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(9.0 * dk + lumber * 0.5), rx(leanX), ry(pel.prot)),
            mul(tr(pel.sway * fs, pelvY * fs + sink, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));
        if (!dead) {
            heromod.legChain(&wx, &self.rest, self.pos.y, self.phase, m, 0, self.fwdB, self.latB, 1.0, HIPL, KNEEL, solePatches[0]);
            heromod.legChain(&wx, &self.rest, self.pos.y, self.phase + 0.5, m, 0, self.fwdB, self.latB, -1.0, HIPR, KNEER, solePatches[1]);
        } else {
            heromod.deadLegs(&wx, self.rest, dk);
        }
        self.poseUpper(&wx, waist, rake, stun, dk, pel.prot, lumber, bellows);
        self.xf = wx;
    }

    fn poseUpper(self: *Cinder, wx: *[N]rl.Matrix, waist: f32, rake: f32, stun: f32, dk: f32, prot: f32, lumber: f32, bellows: f32) void {
        const rest = self.rest;
        const twoPi = std.math.tau;
        const m = self.moving * (1.0 - dk);
        const wonk = (self.seed - 0.5) * 6.0;
        const nod = 1.6 * mathx.cosf(2.0 * twoPi * self.phase) * m;

        setLocal(wx, SPINE, rest, mul3(rx(waist * 0.42 + nod), ry(-0.32 * prot), rz(wonk * 0.5 - 0.3 * lumber)));
        setLocal(wx, CHEST, rest, mul3(rx(waist * 0.58 + nod * 0.6 + 1.0 * bellows), ry(-0.48 * prot), rz(-wonk * 0.3 - 0.2 * lumber)));
        setLocal(wx, NECK, rest, rx(-10.0 * rake + 7.0 * dk - 5.0 * stun));
        setLocal(wx, SKULL, rest, mul3(rx(-18.0 * rake + 14.0 * dk - 22.0 * stun + 2.5 * bellows), ry(-0.4 * prot), rz(wonk)));

        // **BOTH ARMS ARE THE WEAPON**: the rake hauls them overhead together and drags them down through the
        // hero, so the tell is a silhouette rather than a side to read.
        const armStun = -44.0 * stun;
        const swing = -12.0 * heromod.armSwing(self.phase) * m * @abs(self.fwdB);
        const haul = -96.0 * mathx.maxF(0, -rake);
        const drive = 62.0 * mathx.maxF(0, rake);
        inline for (.{ SHL, SHR }, .{ ELL, ELR }, .{ WRL, WRR }, .{ 1.0, -1.0 }) |sh, el, wr, side| {
            const s = if (side > 0) swing else -swing;
            setLocal(wx, sh, rest, mul3(rx(-(6.0 + s) + haul - drive + armStun - 20.0 * dk), ry(0), rz(side * (12.0 + 3.0 * @abs(wonk)))));
            setLocal(wx, el, rest, rx(-(30.0 + 22.0 * @abs(rake))));
            setLocal(wx, wr, rest, rz(side * (5.0 + 14.0 * mathx.maxF(0, rake))));
        }
    }
};

/// One burning patch of ground. It carries NO particles of its own — the group's single pool feeds every live
/// ember, so the flame cost is flat in the number of embers rather than linear in it.
pub const Ember = struct {
    pos: rl.Vector3 = mathx.zero3,
    t: f32 = 0,
    live: bool = false,

    pub fn radius(self: *const Ember) f32 {
        const grow = mathx.smoothstep(0, 0.35, self.t);
        const spend = 1.0 - mathx.smoothstep(EMBER_LIFE - 1.2, EMBER_LIFE, self.t);
        return EMBER_R * grow * (0.55 + 0.45 * spend);
    }
    pub fn covers(self: *const Ember, p: rl.Vector3) bool {
        return self.live and self.t < EMBER_LIFE and mathx.distXZ(self.pos, p) <= self.radius();
    }
};

/// **THE WHOLE FIELD'S TRAIL IN ONE RING.** At `CHASE_SPEED` one wake keeps 27 embers alive (asserted); the
/// ring holds nine wakes' worth and a tenth simply recycles the oldest patch, which is the right failure — an
/// old cinder going out early, never a young one missing.
const TRAIL_CAP: usize = 256;
const PER_WAKE = @as(usize, @intFromFloat(@ceil(CHASE_SPEED * EMBER_LIFE / TRAIL_SPACING)));
comptime {
    std.debug.assert(TRAIL_CAP >= PER_WAKE * 9);
}

const FLAME_RATE: f32 = 46.0;
const FLAME_PARTS = 128;
comptime {
    std.debug.assert(@as(f32, @floatFromInt(FLAME_PARTS)) >= FLAME_RATE * 0.52 * 2.0);
}

const CAP_N = wf.MAX_PER_KIND;

pub const Scorch = struct {
    model: Model,
    wakes: [CAP_N]Cinder = undefined,
    n: usize = 0,
    embers: [TRAIL_CAP]Ember = [_]Ember{.{}} ** TRAIL_CAP,
    head: usize = 0,
    soak: foe.Soak = .{},
    flame: [FLAME_PARTS]foe.Particle = [_]foe.Particle{.{}} ** FLAME_PARTS,
    flameHead: usize = 0,
    flameAccum: f32 = 0,
    flameRng: mathx.Rng = mathx.Rng.init(0xF1A3),

    pub fn init(shader: rl.Shader) Scorch {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Scorch) []Cinder {
        return self.wakes[0..self.n];
    }
    pub fn liveConst(self: *const Scorch) []const Cinder {
        return self.wakes[0..self.n];
    }
    pub fn reset(self: *Scorch, m: *const wf.Map) void {
        self.clearTrail();
        foe.resetGroup(Cinder, &self.wakes, &self.n, m, .cinder_wake);
    }
    pub fn clear(self: *Scorch) void {
        self.n = 0;
        self.clearTrail();
    }
    fn clearTrail(self: *Scorch) void {
        for (&self.embers) |*e| e.* = .{};
        self.head = 0;
    }
    pub fn setShader(self: *Scorch, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn setParry(self: *Scorch, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }

    pub fn lay(self: *Scorch, at: rl.Vector3) void {
        self.embers[self.head] = .{ .pos = at, .live = true };
        self.head = (self.head + 1) % TRAIL_CAP;
    }

    pub fn update(self: *Scorch, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        var worst: ?foe.Blow = null;
        for (self.live()) |*c| {
            if (c.update(dt, c.threat.aim(hero), bounds, blade)) |h| foe.worseBlow(&worst, h, c.pos, &c.threat);
            if (c.dropAt) |at| self.lay(at);
        }
        self.tickTrail(dt);
        return worst;
    }

    fn tickTrail(self: *Scorch, dt: f32) void {
        foe.tickParticles(&self.flame, dt, 0);
        var liveN: usize = 0;
        for (&self.embers) |*e| {
            if (!e.live) continue;
            e.t += dt;
            if (e.t >= EMBER_LIFE) {
                e.live = false;
                continue;
            }
            liveN += 1;
        }
        if (liveN == 0) return;
        // **ONE POOL OVER EVERY PATCH**: each owed mote picks a live ember at random, so a long trail thins
        // evenly rather than the near end burning and the far end going dark.
        var owed = foe.emitDue(&self.flameAccum, dt, FLAME_RATE);
        const sig = elemfx.sig(.fire);
        while (owed > 0) : (owed -= 1) {
            const pick = self.pickLive(liveN) orelse break;
            const e = &self.embers[pick];
            const a = self.flameRng.angle();
            const rr = self.flameRng.float() * e.radius();
            const cold = e.t / EMBER_LIFE;
            foe.emitPart(&self.flame, &self.flameHead, .{
                .p = v3(e.pos.x + mathx.cosf(a) * rr, e.pos.y + 0.02, e.pos.z + mathx.sinf(a) * rr),
                .v = v3(self.flameRng.signed() * 0.12, self.flameRng.range(0.35, 1.05) * (1.0 - 0.45 * cold), self.flameRng.signed() * 0.12),
                .life = self.flameRng.range(0.28, 0.52),
                .r0 = sig.r0 * 1.4,
                .r1 = sig.r1 * 1.6,
                .col = if (cold > 0.7) sig.cool.? else sig.core,
                .col1 = sig.ash,
                .grav = sig.grav * 0.7,
                .drag = sig.drag,
            });
        }
    }

    fn pickLive(self: *Scorch, liveN: usize) ?usize {
        if (liveN == 0) return null;
        var want: usize = @intFromFloat(self.flameRng.float() * @as(f32, @floatFromInt(liveN)));
        if (want >= liveN) want = liveN - 1;
        for (&self.embers, 0..) |*e, i| {
            if (!e.live) continue;
            if (want == 0) return i;
            want -= 1;
        }
        return null;
    }

    /// The hero's bill for standing on burnt ground, in the same coin the sporeling's cloud bills poison.
    pub fn scorching(self: *Scorch, dt: f32, hero: rl.Vector3) f32 {
        return self.soak.step(self.burning(hero), dt, TRAIL_BUILD);
    }
    pub fn burning(self: *const Scorch, at: rl.Vector3) bool {
        for (&self.embers) |*e| {
            if (e.covers(at)) return true;
        }
        return false;
    }
    pub fn emberCount(self: *const Scorch) u32 {
        var n: u32 = 0;
        for (&self.embers) |*e| {
            if (e.live and e.t < EMBER_LIFE) n += 1;
        }
        return n;
    }

    pub fn draw(self: *const Scorch, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Scorch) void {
        for (self.liveConst()) |*c| c.drawFx();
        foe.drawParticles(&self.flame);
    }
    pub fn pierce(self: *Scorch, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Scorch) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn anyParried(self: *const Scorch) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn soulsDropped(self: *const Scorch) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Scorch) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Scorch) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

fn buildBones() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = pelvisMesh();
    mesh[SPINE] = lumbarMesh();
    mesh[CHEST] = chestMesh();
    mesh[NECK] = neckMesh();
    mesh[SKULL] = skullMesh();
    mesh[HIPL] = thighMesh(311);
    mesh[KNEEL] = shinMesh();
    mesh[ANKL] = footMesh(1.0);
    mesh[HIPR] = thighMesh(313);
    mesh[KNEER] = shinMesh();
    mesh[ANKR] = footMesh(-1.0);
    mesh[SHL] = upperArmMesh(1.0);
    mesh[ELL] = forearmMesh(1.0);
    mesh[WRL] = clawMesh(1.0);
    mesh[SHR] = upperArmMesh(-1.0);
    mesh[ELR] = forearmMesh(-1.0);
    mesh[WRR] = clawMesh(-1.0);
    return mesh;
}

/// A crack laid ALONG the limb rather than a dot on it: burnt wood splits with the grain, and a scatter of
/// specks reads as damage to the mesh instead of heat inside the body.
fn seamStripe(b: *Builder, from: rl.Vector3, to: rl.Vector3, w: f32, col: rl.Color) void {
    b.addCapsule(from, to, w, w * 0.7, 5, col);
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, 0, 0), v3(0.088 * H, 0.070 * H, 0.076 * H), 9, 6, CRUST);
    b.addBlob(v3(0, -0.030 * H, 0.006 * H), v3(0.078 * H, 0.040 * H, 0.068 * H), 8, 5, CHAR);
    b.setMat(.plain);
    seamStripe(&b, v3(0.020 * H, -0.020 * H, 0.062 * H), v3(-0.014 * H, 0.026 * H, 0.058 * H), 0.007 * H, SEAM_DK);
    return b.toMesh();
}

fn lumbarMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(0, 0.078 * H, 0), 0.070 * H, 0.082 * H, 9, CRUST);
    b.addBlob(v3(0, 0.030 * H, -0.020 * H), v3(0.058 * H, 0.046 * H, 0.040 * H), 7, 5, CHAR);
    b.setMat(.plain);
    seamStripe(&b, v3(0.006 * H, 0.004 * H, 0.066 * H), v3(-0.010 * H, 0.070 * H, 0.070 * H), 0.008 * H, SEAM);
    return b.toMesh();
}

/// **THE FURNACE.** The chest is where the seam is widest and where the heat visibly comes from — the one
/// place on the body authored bright, so the silhouette says which end of the creature is still burning.
fn chestMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x0C1D);
    b.setMat(.skin);
    b.addBlob(v3(0, 0.040 * H, 0), v3(0.108 * H, 0.086 * H, 0.088 * H), 10, 7, CRUST);
    b.addBlob(v3(0, -0.006 * H, 0.010 * H), v3(0.096 * H, 0.054 * H, 0.080 * H), 9, 6, CRUST_LT);
    b.addBlob(v3(0, 0.086 * H, -0.008 * H), v3(0.092 * H, 0.036 * H, 0.080 * H), 8, 6, CHAR);
    b.setMat(.plain);
    b.addBlob(v3(0, 0.024 * H, 0.062 * H), v3(0.050 * H, 0.048 * H, 0.024 * H), 7, 6, SEAM);
    b.addBlob(v3(0, 0.024 * H, 0.070 * H), v3(0.030 * H, 0.030 * H, 0.016 * H), 6, 5, EYE);
    b.setMat(.skin);
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        const y = 0.006 * H + @as(f32, @floatFromInt(i)) * 0.022 * H;
        const w = 0.010 * H + rng.range(0, 0.004) * H;
        b.addCapsule(v3(-0.052 * H, y, 0.060 * H), v3(0.052 * H, y + rng.range(-0.004, 0.004) * H, 0.058 * H), w, w, 5, CHAR);
    }
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(0, 0.048 * H, -0.004 * H), 0.026 * H, 0.028 * H, 7, CHAR);
    return b.toMesh();
}

fn skullMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, 0.020 * H, 0.002 * H), v3(0.048 * H, 0.052 * H, 0.052 * H), 9, 7, CRUST);
    b.addBlob(v3(0, -0.010 * H, 0.020 * H), v3(0.034 * H, 0.026 * H, 0.034 * H), 7, 5, CHAR);
    b.setMat(.plain);
    b.addBlob(v3(0.019 * H, 0.024 * H, 0.042 * H), v3(0.012 * H, 0.011 * H, 0.008 * H), 5, 5, EYE);
    b.addBlob(v3(-0.019 * H, 0.024 * H, 0.042 * H), v3(0.012 * H, 0.011 * H, 0.008 * H), 5, 5, EYE);
    seamStripe(&b, v3(0.004 * H, 0.062 * H, 0.020 * H), v3(-0.008 * H, 0.040 * H, -0.030 * H), 0.005 * H, SEAM_DK);
    return b.toMesh();
}

fn thighMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.skin);
    const len = heromod.SEG_THIGH * H;
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), 0.040 * H, 0.032 * H, 8, CRUST);
    b.addBlob(v3(0, 0.004 * H, 0), v3(0.045 * H, 0.042 * H, 0.044 * H), 7, 5, CRUST);
    b.addBlob(v3(rng.signed() * 0.010 * H, -len * 0.5, 0.006 * H), v3(0.036 * H, 0.062 * H, 0.034 * H), 6, 5, CHAR);
    b.setMat(.plain);
    seamStripe(&b, v3(0.026 * H, -len * 0.18, 0.020 * H), v3(0.020 * H, -len * 0.82, 0.014 * H), 0.005 * H, SEAM_DK);
    return b.toMesh();
}

fn shinMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    const len = heromod.SEG_SHANK * H;
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0.004 * H), 0.030 * H, 0.020 * H, 8, CRUST);
    b.addBlob(v3(0, 0.002 * H, 0), v3(0.034 * H, 0.032 * H, 0.034 * H), 6, 5, CRUST);
    b.addBlob(v3(0, -len * 0.27, -0.006 * H), v3(0.028 * H, 0.052 * H, 0.026 * H), 6, 5, CHAR);
    return b.toMesh();
}

/// **THE FEET ARE THE APPLICATOR** — burnt through to the bone and glowing under, because they are what lays
/// the trail and the picture may not disagree with the mechanic.
fn footMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0.004 * H, -0.024 * H), v3(side * 0.006 * H, -0.006 * H, 0.086 * H), 0.028 * H, 0.020 * H, 7, CRUST);
    b.setMat(.plain);
    b.addBlob(v3(side * 0.004 * H, -0.014 * H, 0.030 * H), v3(0.020 * H, 0.006 * H, 0.052 * H), 6, 4, SEAM);
    return b.toMesh();
}

fn upperArmMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    const len = heromod.SEG_UPARM * H;
    b.addCapsule(v3(0, 0, 0), v3(side * 0.010 * H, -len, 0), 0.028 * H, 0.022 * H, 7, CRUST);
    b.addBlob(v3(0, 0.002 * H, 0), v3(0.033 * H, 0.032 * H, 0.032 * H), 6, 5, CRUST_LT);
    b.setMat(.plain);
    seamStripe(&b, v3(side * 0.020 * H, -len * 0.13, 0.010 * H), v3(side * 0.014 * H, -len * 0.86, 0.008 * H), 0.004 * H, SEAM_DK);
    return b.toMesh();
}

fn forearmMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    const len = heromod.SEG_FOREARM * H;
    b.addCapsule(v3(0, 0, 0), v3(side * 0.008 * H, -len, 0), 0.023 * H, 0.016 * H, 7, CRUST);
    b.addBlob(v3(0, 0.002 * H, 0), v3(0.026 * H, 0.025 * H, 0.026 * H), 6, 5, CRUST);
    b.setMat(.plain);
    seamStripe(&b, v3(side * 0.014 * H, -len * 0.10, 0.008 * H), v3(side * 0.010 * H, -len * 0.85, 0.006 * H), 0.004 * H, SEAM);
    return b.toMesh();
}

/// Fingers burnt to points. The rake is these, so they are the one small thing on the body allowed to read hot.
fn clawMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, -0.014 * H, 0.004 * H), v3(0.020 * H, 0.022 * H, 0.018 * H), 6, 5, CHAR);
    b.setMat(.plain);
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const f = @as(f32, @floatFromInt(i)) - 1.0;
        b.addCapsule(
            v3(side * f * 0.012 * H, -0.024 * H, 0.006 * H),
            v3(side * f * 0.018 * H, -0.058 * H, 0.020 * H),
            0.007 * H,
            0.002 * H,
            5,
            if (i == 1) SEAM else SEAM_DK,
        );
    }
    return b.toMesh();
}


test "THE TRAIL IS LAID BY TRAVEL, NOT BY THE CLOCK — a standing wake burns no ground" {
    var c = Cinder.spawn(mathx.zero3, 0, 1.0, 0.3);
    var laid: u32 = 0;
    var t: f32 = 0;
    // Quarry forty metres off: outside `AGGRO_R` and already at home, so it never takes a step.
    while (t < 6.0) : (t += 1.0 / 60.0) {
        _ = c.update(1.0 / 60.0, v3(0, 0, 40), 400, .{});
        if (c.dropAt != null) laid += 1;
    }
    try std.testing.expectEqual(@as(u32, 0), laid);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(c.pos, c.home), 1e-4);
}

test "A WALKING WAKE LAYS ONE EMBER EVERY `TRAIL_SPACING` OF GROUND, and the line has no gap in it" {
    var s = Scorch{ .model = undefined };
    s.wakes[0] = Cinder.spawn(mathx.zero3, 0, 1.0, 0.3);
    s.n = 1;
    // INSIDE ITS EYES, or it stands at home and the whole test passes on zero embers.
    const hero = v3(0, 0, AGGRO_R - 1.0);
    var t: f32 = 0;
    while (t < 4.0) : (t += 1.0 / 60.0) _ = s.update(1.0 / 60.0, hero, 400, .{});

    const travelled = mathx.distXZ(s.wakes[0].pos, mathx.zero3);
    const expect = travelled / TRAIL_SPACING;
    const got: f32 = @floatFromInt(s.emberCount());
    std.debug.print("\n  cinder wake: walked {d:.2} m, laid {d:.0} embers (one per {d:.2} m)\n", .{ travelled, got, TRAIL_SPACING });
    try std.testing.expect(got >= expect - 2.0 and got <= expect + 2.0);

    // NO GAP: every point along the line it walked is inside some live ember.
    var d: f32 = 0.1;
    while (d < travelled - 0.1) : (d += 0.05) {
        try std.testing.expect(s.burning(v3(0, 0, d)));
    }
}

test "THE TRAIL BURNS AND THEN GOES OUT — stand in it and the meter breaks, step off and it decays" {
    var s = Scorch{ .model = undefined };
    s.lay(mathx.zero3);
    const B = combat.ailRow(.burning);
    var burn = combat.Status{};
    var broke = false;
    var t: f32 = 0;
    while (t < EMBER_LIFE) : (t += 1.0 / 60.0) {
        s.tickTrail(1.0 / 60.0);
        burn.add(B, s.scorching(1.0 / 60.0, v3(0.1, 0, 0.1)));
        _ = burn.tick(B, 1.0 / 60.0, 100);
        if (burn.active()) broke = true;
    }
    std.debug.print("  trail: {d:.0}/s against a {d:.0}/s decay -> burning {s}\n", .{ TRAIL_BUILD, B.decay, if (broke) "BROKE" else "held" });
    try std.testing.expect(broke);
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.scorching(1.0 / 60.0, v3(20, 0, 20)), 1e-6);

    // …and past its life the patch is cold ground again.
    s.tickTrail(0.5);
    try std.testing.expect(!s.burning(mathx.zero3));
    try std.testing.expectEqual(@as(u32, 0), s.emberCount());
}

test "ONE CROSSING IS A BILL, NOT A BURN — the entry bolus alone never breaks the meter" {
    var s = Scorch{ .model = undefined };
    s.lay(mathx.zero3);
    s.tickTrail(0.4); // grown to full radius
    const B = combat.ailRow(.burning);
    var burn = combat.Status{};
    const inside = v3(0.1, 0, 0);
    const outside = v3(20, 0, 20);

    // A hero at 3.4 m/s crosses a 1.04 m patch in 0.31 s.
    var t: f32 = 0;
    while (t < 0.31) : (t += 1.0 / 60.0) {
        burn.add(B, s.scorching(1.0 / 60.0, inside));
        _ = burn.tick(B, 1.0 / 60.0, 100);
    }
    const afterOne = burn.meter;
    try std.testing.expect(!burn.active());
    std.debug.print("  one crossing costs {d:.0} of the {d:.0} burning meter\n", .{ afterOne, B.max });
    try std.testing.expect(afterOne > B.max * 0.15 and afterOne < B.max * 0.6);

    // Off it, the meter empties on its own — the quiet spell first, then the fall.
    _ = s.scorching(1.0 / 60.0, outside);
    const clears = B.decayDelay + afterOne / B.decay;
    t = 0;
    while (t < clears + 0.1) : (t += 1.0 / 60.0) _ = burn.tick(B, 1.0 / 60.0, 100);
    std.debug.print("  ...and it clears in {d:.2} s off the body ({d:.2} s quiet, then {d:.0}/s)\n", .{ clears, B.decayDelay, B.decay });
    try std.testing.expectApproxEqAbs(@as(f32, 0), burn.meter, 1e-4);
}

test "THE TRAIL OUTLIVES THE BODY — killing it late leaves you standing in what it made" {
    var s = Scorch{ .model = undefined };
    s.wakes[0] = Cinder.spawn(mathx.zero3, 0, 1.0, 0.3);
    s.n = 1;
    const hero = v3(0, 0, AGGRO_R - 1.0);
    var t: f32 = 0;
    while (t < 2.0) : (t += 1.0 / 60.0) _ = s.update(1.0 / 60.0, hero, 400, .{});
    const before = s.emberCount();
    try std.testing.expect(before > 0);
    s.wakes[0].debugKill();
    t = 0;
    while (t < 0.5) : (t += 1.0 / 60.0) _ = s.update(1.0 / 60.0, hero, 400, .{});
    try std.testing.expect(s.emberCount() >= before - 2);
    // A corpse lays nothing more, whatever it does while it falls.
    const held = s.emberCount();
    t = 0;
    while (t < 1.0) : (t += 1.0 / 60.0) _ = s.update(1.0 / 60.0, hero, 400, .{});
    try std.testing.expect(s.emberCount() <= held);
}

test "IT CANNOT OUTRUN YOU, AND IT DOES NOT LET GO EITHER" {
    try std.testing.expect(CHASE_SPEED > heromod.WALK_SPEED);
    try std.testing.expect(CHASE_SPEED < heromod.RUN_SPEED * 0.6);
    const perWake: f32 = CHASE_SPEED * EMBER_LIFE;
    std.debug.print("  live trail behind one wake: {d:.1} m at {d:.2} m/s over {d:.1} s\n", .{ perWake, CHASE_SPEED, EMBER_LIFE });
    try std.testing.expect(perWake > 8.0 and perWake < 14.0);
}

test "the pick is positional: rake in reach, close outside it, and it goes home when he leaves" {
    try std.testing.expectEqual(Choice.rake, classify(RAKE_R - 0.2, 2.0, 0, true, false));
    try std.testing.expectEqual(Choice.close, classify(RAKE_R - 0.2, 2.0, 0, false, false));
    try std.testing.expectEqual(Choice.close, classify(RAKE_R + 2.0, 4.0, 0, true, false));
    try std.testing.expectEqual(Choice.rest, classify(AGGRO_R, AGGRO_R + 1.0, 0, true, false));
    try std.testing.expectEqual(Choice.hold, classify(AGGRO_R, AGGRO_R + 1.0, HOME_R + 1.0, true, false));
    // Rooted it still rakes what is already in reach — the grip takes the FEET, not the arms.
    try std.testing.expectEqual(Choice.rake, classify(RAKE_R - 0.2, 2.0, 0, true, true));
    try std.testing.expectEqual(Choice.rest, classify(RAKE_R + 2.0, 4.0, 0, true, true));
}

test "FIRE IS NOTHING TO IT AND COLD IS THE ANSWER" {
    const fire = combat.Hit{ .elem = combat.elems(.{ .fire = 40 }) };
    const cold = combat.Hit{ .elem = combat.elems(.{ .cold = 40 }) };
    var hot = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    var iced = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    _ = hot.hit(fire);
    _ = iced.hit(cold);
    const tookFire = HP_MAX - hot.hp;
    const tookCold = HP_MAX - iced.hp;
    std.debug.print("  40 fire takes {d:.0} hp, 40 cold takes {d:.0}\n", .{ tookFire, tookCold });
    try std.testing.expect(tookCold > tookFire * 5.0);
}

test "the rake is telegraphed and it only lands once per swing" {
    var c = Cinder.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, 1.2);
    c.facing = mathx.headingXZ(mathx.dirXZ(c.pos, hero));
    c.debugRake();
    var landed: u32 = 0;
    var firstAt: f32 = 0;
    var t: f32 = 0;
    while (t < RAKE_WIND + RAKE_STRIKE + RAKE_RECOVER + 0.1) : (t += 1.0 / 60.0) {
        if (c.update(1.0 / 60.0, hero, 400, .{}) != null) {
            if (landed == 0) firstAt = t;
            landed += 1;
        }
    }
    try std.testing.expectEqual(@as(u32, 1), landed);
    try std.testing.expect(firstAt >= foe.TELL_MIN);
}
