const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
const foe = @import("foe.zig");
const anim = @import("../core/anim.zig");
const wf = @import("../world/worldfmt.zig");
const elemfx = @import("../gfx/elemfx.zig");
const shroommod = @import("shroom.zig");
const archermod = @import("archer.zig");
const koboldmod = @import("kobold.zig");

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
const setLocal = heromod.setHumanoid;

// THE MUSHROOM MAGE (owner's creature, owner's brief) — a cloaked fungal caster that throws SLOW, BOUNCING
// fireballs.
//
// **THE CAP IS THE HOOD** — one silhouette, not a hood WITH a mushroom under it, which would be two fighting.
//
// **AND THE FIREBALL IS THE FIGHT.** It BOUNCES (`archer.bouncesOf`), so it threatens a LINE running away
// from the caster: measured, a ball aimed at 11 m touches at 11.9, 18.1 and 21.0 and rests at 22.4. **WHAT IT
// PUNISHES IS BACKING OFF** — backwards is down the bounce line, so the arc you dodged catches you on the
// second touch. The answer is sideways, or forwards into its face, where it has no melee at all.

/// **IT STANDS OVER YOU NOW** (owner: taller, bigger). It was a head shorter than the hero at 0.82; at 1.13
/// it is 2.04 m to the crown of the cap, which is what a thing that lobs detonators over your head should be.
pub const SCALE = (heromod.H + 0.24) / heromod.H;
const HIP_HALF = heromod.HIP_HALF * 1.26;
const SHOULDER_HALF = heromod.SHOULDER_HALF * 1.14;
const H: f32 = heromod.H;
const REST = heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);

const N = heromod.N;
const ROOT = heromod.ROOT;
const SPINE = heromod.SPINE;
const CHEST = heromod.CHEST;
const NECK = heromod.NECK;
const CAP = heromod.HEAD;
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
/// **THE HELD SLOT IS EMPTY AND THAT IS A DECISION.** A staff is the necromancer's and the wanderer's; this
/// one conjures BETWEEN ITS TWO HANDS, which is what makes the gather a thing you watch grow rather than a
/// glow on the end of a pole. Bone 17 is therefore never posed and never drawn — `Model.draw` walks `0..HELD`
/// for exactly that reason, and nothing reads `xf[HELD]`.
const HELD = heromod.HELD;

const SOLES = [_]heromod.SolePatch{
    .{ .bone = ANKL, .heel = 0.045 * H, .toe = 0.180 * H, .halfW = 0.058 * H, .drop = 0.036 * H },
    .{ .bone = ANKR, .heel = 0.045 * H, .toe = 0.180 * H, .halfW = 0.058 * H, .drop = 0.036 * H },
};

// **AUTHOR DARK AND SOLVE IT** — screen goes as albedo^(1/2.2), so the bigger and smoother the mass the
// darker it has to start. The cloak is the biggest face here.

/// Damp and GREEN-BLACK, and it may NOT go blue-black: that is the necromancer's separation, and two dark
/// robed things at one colour cannot be told apart at fighting range.
///
/// **SOLVED OFF THE RENDER, NOT PICKED.** At (16,22,15) it sampled 83 luma against ground at 102 — 0.81 of
/// its field. Wanted ~0.64, so the albedo factor is 0.79^2.2 = 0.59.
const CLOAK = rgba(10, 13, 9, 255);
const CLOAK_LT = rgba(15, 19, 13, 255);
const HEM = rgba(6, 9, 6, 255);
const CORD = rgba(78, 62, 40, 255);

const CAP_COL = shroommod.CAP_COL;
const CAP_DK = shroommod.CAP_DK;
const GILL = rgba(14, 9, 8, 255);
const WART = shroommod.WART;
const FLESH = rgba(58, 52, 42, 255);

const EYE = rgba(232, 148, 62, 44);

const FIRE_CORE = elemfx.sig(.fire).core;
const FIRE_EDGE = elemfx.sig(.fire).edge;


pub const AGGRO_R: f32 = 22.0;
const TURN_RATE: f32 = 2.6;
/// **SLOWER, BECAUSE IT IS NOW WORTH DODGING** (owner: tougher, slower, more dangerous). Three-fifths of a
/// walk. It cannot chase and it is not meant to; what it does is make you come to it through its own fire.
const WALK_SPEED: f32 = heromod.WALK_SPEED * 0.60;

const BODY_R: f32 = 0.43;
/// **IT HAS TO HOLD THE CAP, NOT JUST THE BARREL** (the ravager's lesson). Fitted to the body the sphere
/// stopped at 1.45 m with the mark 1.35 m up on its own rim — a reticle on a place you cannot hit. MEASURED
/// off the posed rig: head bone at 0.885·H, crown 0.17·H above it.
const HURT_R: f32 = 0.88;
const CENTER_F: f32 = 0.66;
const TOP_F: f32 = 1.10;

const HP_MAX: f32 = 96.0;
const POISE_MAX: f32 = 22.0;
const STANCE_MAX: f32 = 44.0;
const RESISTS = combat.resists(.{ .fire = 55, .cold = 20, .lightning = -20, .chaos = -45 });

pub const SOULS: u32 = 260;

const DEATH_DUR: f32 = 1.15;
const DISS_DUR: f32 = 1.0;
const DISSOLVE = foe.Dissolve{ .rate = 54.0, .spread = 0.8, .rise = 0.95, .flake = WART };
const NPART = 60;
const SHOVE_DECAY: f32 = 6.5;
const A_PROT: f32 = 3.2;


/// Longer wind-up with the bigger blast: the tell has to be worth the damage behind it.
pub const LOB_WIND: f32 = 0.94;
const LOB_THROW: f32 = 0.16;
const LOB_RECOVER: f32 = 0.54;
const LOB_CD: f32 = 3.4;
const RELEASE_K: f32 = 0.34;

/// **SLOWER AND FLATTER** (owner: slower bounce, lower lob). At 8.0 with a full ballistic loft the shot went
/// up and came down on you; at 6.4 with `archer.EMBER_LOFT` at 0.52 it comes ACROSS the ground, which is what
/// makes the bounce line readable and the sideways dodge the answer.
pub const EMBER_SPEED: f32 = 6.4;
pub const EMBER_HIT = combat.Hit{ .poise = 20, .elem = combat.elems(.{ .fire = 27 }) };

const LOB_MIN: f32 = 4.5;
const LOB_MAX: f32 = 16.0;
const FLEE_R: f32 = 3.6;
const DRIFT_DUR: f32 = 0.75;

comptime {
    std.debug.assert(LOB_WIND >= foe.TELL_MIN);
    std.debug.assert(RELEASE_K > 0 and RELEASE_K < 1.0);
    std.debug.assert(FLEE_R < LOB_MIN);
}

// **AN ATTACK IS A SEQUENCE OF KEY POSES CHASED BY SPRINGS, NEVER TWO CONSTANTS AND A LERP.** Channels are
// flattened ROOT-most to TIP-most and the bank's falloff lags the hands behind the trunk.

const CHAN_N = 7;
const Chan = [CHAN_N]f32;
const CH_LEAN = 0;
const CH_TWIST = 1;
const CH_HEAD = 2;
const CH_SH = 3;
const CH_ABD = 4;
const CH_EL = 5;
const CH_CUP = 6;

const CARRY_LEAN: f32 = 8.0;
const CARRY_HEAD: f32 = 5.0;
const CARRY_SH: f32 = 14.0;
const CARRY_ABD: f32 = 13.0;
const CARRY_EL: f32 = 44.0;

const P = struct {
    lean: f32 = CARRY_LEAN,
    twist: f32 = 0,
    head: f32 = CARRY_HEAD,
    sh: f32 = CARRY_SH,
    abd: f32 = CARRY_ABD,
    el: f32 = CARRY_EL,
    /// How much fire is cupped between the hands, 0..1 — a POSE channel and not a clock beside one, so the
    /// picture of the spell cannot promise a throw the mechanic is not making.
    cup: f32 = 0,

    pub fn chan(self: P) Chan {
        var c: Chan = undefined;
        c[CH_LEAN] = self.lean;
        c[CH_TWIST] = self.twist;
        c[CH_HEAD] = self.head;
        c[CH_SH] = self.sh;
        c[CH_ABD] = self.abd;
        c[CH_EL] = self.el;
        c[CH_CUP] = self.cup;
        return c;
    }
};

const PoseKey = anim.Pose(P).PoseKey;
const samplePose = anim.Pose(P).sample;

const SPRING_STIFF: f32 = 1500.0; // period ~0.16 s — inside the 0.16 s throw, so the snap survives the bank
const SPRING_ZETA: f32 = 0.70;
const SPRING_FALLOFF: f32 = 0.93;

const WIND_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = .{} },
    .{ .t = 0.38, .p = .{ .lean = 15.0, .head = 7.0, .sh = 38.0, .abd = 10.0, .el = 70.0, .cup = 0.30 }, .ease = .accel },
    .{ .t = 0.78, .p = .{ .lean = 21.0, .head = 10.0, .sh = 50.0, .abd = 12.5, .el = 80.0, .cup = 0.88 }, .ease = .decel },
    .{ .t = 1.00, .p = .{ .lean = 18.0, .head = 8.5, .sh = 46.0, .abd = 11.0, .el = 77.0, .cup = 1.0 } },
};

const THROW_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = .{ .lean = 18.0, .head = 8.5, .sh = 46.0, .abd = 11.0, .el = 77.0, .cup = 1.0 } },
    .{ .t = 0.34, .p = .{ .lean = -5.0, .head = -4.0, .sh = 116.0, .abd = 19.0, .el = 24.0, .cup = 0.30 }, .ease = .snap },
    .{ .t = 1.00, .p = .{ .lean = -10.0, .head = -9.0, .sh = 132.0, .abd = 24.0, .el = 13.0, .cup = 0 } },
};

const CARRY: Chan = (P{}).chan();

const RECOVER_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = .{ .lean = -10.0, .head = -9.0, .sh = 132.0, .abd = 24.0, .el = 13.0, .cup = 0 } },
    .{ .t = 1.00, .p = .{}, .ease = .decel },
};

const State = enum { idle, drift, lob_wind, lob_throw, recover, stunlight, stunheavy, dead };

const Choice = enum { hold, back, lob, keep };
fn classify(dist: f32, lobReady: bool) Choice {
    if (dist > AGGRO_R) return .hold;
    if (dist < FLEE_R) return .back;
    if (lobReady and dist >= LOB_MIN and dist <= LOB_MAX) return .lob;
    return .keep;
}

pub const Model = struct {
    bone: [N]rl.Mesh,
    cloak: rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "mushroom mage");
        return .{ .bone = buildBones(), .cloak = cloakMesh(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, k: *const Mage) void {
        // **`0..HELD`, NOT `0..N`** — bone 17 is the weapon slot and this creature carries nothing, so it
        // was never built and never posed. Walked to `N` the draw hands raylib an undefined mesh.
        for (0..HELD) |i| rl.drawMesh(self.bone[i], self.mat, k.xf[i]);
        rl.drawMesh(self.cloak, self.mat, k.cloakXf());
    }
};

pub const Mage = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    parry: foe.Parry = .{},
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},

    facing: f32 = 0,
    scale: f32 = SCALE,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    lobCd: f32 = 0,
    /// **A FIREBALL LEFT ITS HANDS THIS FRAME** — a one-frame edge (`justDied`'s law), reset at the TOP of
    /// `update` and read by the game after it, because the pool the ball flies in belongs to nobody here.
    /// Latched inside the throw so a long frame cannot fire two and a short one cannot miss it.
    lobbed: bool = false,
    lobFrom: rl.Vector3 = mathx.zero3,
    kindled: bool = false,
    yelped: bool = false,

    moveDir: rl.Vector3 = mathx.zero3,
    homing: bool = false,

    // posture channels (degrees, and `cup` a fraction) — written by the state and settled by the bank
    bodyLean: f32 = CARRY_LEAN,
    twist: f32 = 0,
    headPitch: f32 = CARRY_HEAD,
    armSh: f32 = CARRY_SH,
    armAbd: f32 = CARRY_ABD,
    armEl: f32 = CARRY_EL,
    cup: f32 = 0,
    springs: anim.SpringBank(CHAN_N) = .{},

    cloakLean: f32 = 0,
    cloakVel: f32 = 0,

    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,

    fade: f32 = 0,
    gone: bool = false,

    parts: [NPART]foe.Particle = [_]foe.Particle{.{}} ** NPART,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    xf: [N]rl.Matrix = undefined,
    cloakMat: rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Mage {
        var k = Mage{
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale * SCALE,
            .seed = seed,
            .vit = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
        };
        k.rest = REST;
        k.fxRng = foe.fxStream(seed, 44927.0, 0x2C1);
        k.lobCd = 0.5 + seed * 1.4;
        k.springs.seat(CARRY);
        k.chanSet(CARRY);
        k.pose();
        return k;
    }

    pub fn kind(_: *const Mage) wf.FoeKind {
        return .mushroom_mage;
    }

    pub fn centerWorld(self: *const Mage) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H, self.scale, 0);
    }
    pub fn topWorld(self: *const Mage) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * H, self.scale, 0);
    }
    pub fn lockPoint(self: *const Mage) rl.Vector3 {
        return foe.markOn(self.xf[CAP], v3(0, 0.03 * H, 0));
    }
    pub fn hurtRadius(self: *const Mage) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Mage) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Mage) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Mage) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Mage) bool {
        return switch (self.state) {
            .stunlight, .stunheavy, .dead => true,
            else => false,
        };
    }
    pub fn airborne(_: *const Mage) bool {
        return false;
    }
    pub fn flashFrac(self: *const Mage) f32 {
        return foe.flashFrac(self.flash);
    }

    pub fn cupWorld(self: *const Mage) rl.Vector3 {
        const l = foe.markOn(self.xf[WRL], v3(0, -0.02 * H, 0.05 * H));
        const r = foe.markOn(self.xf[WRR], v3(0, -0.02 * H, 0.05 * H));
        return mathx.lerpV(l, r, 0.5);
    }

    pub fn cupAmt(self: *const Mage) f32 {
        return mathx.clampF(self.cup, 0, 1);
    }

    fn parryable(_: *const Mage) ?f32 {
        return null;
    }

    fn fdir(self: *const Mage) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn faceToward(self: *Mage, at: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, at, TURN_RATE, dt);
    }

    pub fn navWant(self: *const Mage, hero: rl.Vector3) ?rl.Vector3 {
        _ = hero;
        if (self.state != .drift) return null;
        if (self.homing) return self.home;
        return mathx.addV(self.pos, self.moveDir);
    }

    fn chanGet(self: *const Mage) Chan {
        var c: Chan = undefined;
        c[CH_LEAN] = self.bodyLean;
        c[CH_TWIST] = self.twist;
        c[CH_HEAD] = self.headPitch;
        c[CH_SH] = self.armSh;
        c[CH_ABD] = self.armAbd;
        c[CH_EL] = self.armEl;
        c[CH_CUP] = self.cup;
        return c;
    }
    fn chanSet(self: *Mage, c: Chan) void {
        self.bodyLean = c[CH_LEAN];
        self.twist = c[CH_TWIST];
        self.headPitch = c[CH_HEAD];
        self.armSh = c[CH_SH];
        self.armAbd = c[CH_ABD];
        self.armEl = c[CH_EL];
        self.cup = c[CH_CUP];
    }

    fn settlePose(self: *Mage, dt: f32) void {
        var want = self.chanGet();
        self.springs.chase(&want, SPRING_STIFF, SPRING_ZETA, SPRING_FALLOFF, dt);
        self.chanSet(want);
    }

    fn enter(self: *Mage, s: State) void {
        self.state = s;
        self.t = 0;
    }

    pub fn update(self: *Mage, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        self.justDied = false;
        self.lobbed = false;
        self.kindled = false;
        self.yelped = false;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.stateStep(dt, hero, bounds);
        self.tryHit(blade);
        return null;
    }

    fn stateStep(self: *Mage, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();

        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        self.lobCd = mathx.maxF(0, self.lobCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, self.home, hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;
        var moveSpeed: f32 = 0;

        switch (self.state) {
            .idle => {
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                self.chanSet(CARRY);
                if (self.t >= 0.18) self.decide(d);
            },
            .drift => {
                self.faceToward(hero, dt);
                const way = self.nav.along(self.moveDir);
                moveSpeed = WALK_SPEED;
                const moved = moveSpeed * dt * self.chill.travel();
                mathx.stepXZ(&self.pos, way, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(way);
                self.chanSet(CARRY);
                if (self.homing and mathx.distXZ(self.pos, self.home) <= foe.LEASH_HOME_R) {
                    self.homing = false;
                    self.enter(.idle);
                } else if (self.t >= DRIFT_DUR) self.decide(d);
            },
            .lob_wind => {
                self.faceToward(hero, dt);
                const u = mathx.clampF(self.t / LOB_WIND, 0, 1);
                self.chanSet(samplePose(&WIND_KEYS, u));
                self.kindle(dt, u);
                if (self.t >= LOB_WIND) self.enter(.lob_throw);
            },
            .lob_throw => {
                if (self.t < LOB_THROW * RELEASE_K) self.faceToward(hero, dt * 0.35);
                const u = mathx.clampF(self.t / LOB_THROW, 0, 1);
                self.chanSet(samplePose(&THROW_KEYS, u));
                // THE RELEASE IS AN EDGE, caught by the clock CROSSING it — a long frame cannot fire it
                // twice and a short one cannot miss it (`hero.updateShot`'s rule).
                const at = LOB_THROW * RELEASE_K;
                if (self.t - dt < at and self.t >= at) {
                    self.lobbed = true;
                    self.lobFrom = self.cupWorld();
                    self.burstCup();
                }
                if (self.t >= LOB_THROW) {
                    self.lobCd = LOB_CD;
                    self.enter(.recover);
                }
            },
            .recover => {
                if (d <= AGGRO_R) self.faceToward(hero, dt * 0.6);
                self.chanSet(samplePose(&RECOVER_KEYS, mathx.clampF(self.t / LOB_RECOVER, 0, 1)));
                if (self.t >= LOB_RECOVER) self.enter(.idle);
            },
            .stunlight, .stunheavy => {
                self.chanSet(CARRY);
                if (self.t >= combat.foeStunDur(self.state == .stunheavy)) self.enter(.idle);
            },
            .dead => {
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
        }

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        const wantLean = -CLOAK_DRAG * mathx.clampF(moveSpeed / WALK_SPEED, 0, 1) * self.fwdB;
        self.cloakVel += (CLOAK_STIFF * (wantLean - self.cloakLean) - CLOAK_DAMP * self.cloakVel) * dt;
        self.cloakLean += self.cloakVel * dt;
        self.settlePose(dt);
        self.pose();
    }

    /// The pick is `classify`'s and the plumbing is here, so the decision pins by test with no world near it.
    /// **IT MOVES OFF ITS OWN BEARING, NEVER OFF HIS POSITION**: every branch above has already spent the
    /// frame facing him, so `fdir()` IS toward the hero. Which way it circles is SEEDED — a ring of them must
    /// not drift as one body.
    fn decide(self: *Mage, dist: f32) void {
        if (self.leash.goingHome()) {
            self.homing = true;
            self.moveDir = mathx.dirXZ(self.pos, self.home);
            return self.enter(.drift);
        }
        self.homing = false;
        const f = self.fdir();
        const side: f32 = if (self.seed < 0.5) 1.0 else -1.0;
        const lat = mathx.scaleV(mathx.perpXZ(f), side);
        switch (classify(dist, self.lobCd <= 0)) {
            .lob => {
                self.kindled = true;
                self.enter(.lob_wind);
            },
            .back => {
                self.moveDir = mathx.normV(mathx.addV(mathx.scaleV(f, -1.0), mathx.scaleV(lat, 0.55)));
                self.enter(.drift);
            },
            .keep => {
                self.moveDir = if (dist > LOB_MAX)
                    mathx.normV(mathx.addV(f, mathx.scaleV(lat, 0.4)))
                else
                    lat;
                self.enter(.drift);
            },
            .hold => {
                if (mathx.distXZ(self.pos, self.home) > foe.LEASH_HOME_R) {
                    self.homing = true;
                    self.moveDir = mathx.dirXZ(self.pos, self.home);
                    self.enter(.drift);
                } else self.enter(.idle);
            },
        }
    }

    fn kindle(self: *Mage, dt: f32, u: f32) void {
        const rate = lerpF(KINDLE_RATE_0, KINDLE_RATE_1, u * u);
        const n = foe.emitTicks(&self.fxAccum, dt, rate, KINDLE_CAP);
        if (n == 0) return;
        elemfx.gather(&self.parts, &self.fxHead, &self.fxRng, self.cupWorld(), .fire, n, BALL_R * (0.4 + 0.6 * u) * self.scale, self.scale);
    }

    fn burstCup(self: *Mage) void {
        elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, self.cupWorld(), self.fdir(), .fire, THROW_PUFF, self.scale);
    }

    pub fn tryHit(self: *Mage, blade_: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade_) orelse return;
        const heavy = foe.wounded(self, s, blade_, SHOVE);
        self.puff(s.contact, if (heavy) 9 else 4);
        switch (s.reaction) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(true),
            .light => self.enterStun(false),
            .none => {},
        }
    }

    fn enterStun(self: *Mage, heavy: bool) void {
        self.enter(if (heavy) .stunheavy else .stunlight);
        self.yelped = true;
        // **AND WHATEVER WAS IN ITS HANDS GOES OUT.** Left standing, an interrupted mage keeps a fireball
        // cupped in its fists through the whole flinch and the player who earned the interrupt cannot tell
        // it worked. The channel is the picture and the picture has to agree with the mechanic.
        self.cup = 0;
    }

    fn enterDeath(self: *Mage) void {
        if (self.state == .dead) return;
        self.enter(.dead);
        self.cup = 0;
        self.justDied = true;
    }

    pub fn debugStagger(self: *Mage, heavy: bool) void {
        self.enterStun(heavy);
    }

    pub fn stageGather(self: *Mage, u: f32) void {
        self.state = .lob_wind;
        self.t = mathx.clampF(u, 0, 1) * LOB_WIND;
        const want = samplePose(&WIND_KEYS, mathx.clampF(u, 0, 1));
        self.springs.seat(want); // …AT the pose, not chasing it: a still frame cannot show a spring settling
        self.chanSet(want);
        self.pose();
    }

    fn puff(self: *Mage, at: rl.Vector3, n: i32) void {
        var i: i32 = 0;
        const total = foe.hitParts(n);
        while (i < total) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.5, 1.5);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = at,
                .v = v3(mathx.cosf(a) * sp, self.fxRng.range(0.4, 1.7), mathx.sinf(a) * sp),
                .life = self.fxRng.range(0.28, 0.58),
                .r0 = self.fxRng.range(0.020, 0.044) * self.scale,
                .r1 = 0.004,
                .col = if (self.fxRng.float() < 0.5) WART else CAP_DK,
                .grav = 1.4,
                .drag = 1.5,
            });
        }
    }

    pub fn cloakXf(self: *const Mage) rl.Matrix {
        return self.cloakMat;
    }

    fn stunAmount(self: *const Mage) f32 {
        return switch (self.state) {
            .stunlight => foe.stunCurve(self.t, false),
            .stunheavy => foe.stunCurve(self.t, true),
            else => 0,
        };
    }

    pub fn pose(self: *Mage) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = -0.42 * self.scale * self.fade;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.5, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        const stun = self.stunAmount();

        const m = self.moving * (1.0 - dk);
        const pel = heromod.pelvisChannels(self.phase, m, self.fwdB, self.latB, A_PROT);

        var wx: [N]rl.Matrix = undefined;
        const collapse = lerpF(hipY, 0.16 * H, dk);
        const pelvY = if (dead) collapse else hipY + pel.bob - pel.dip;
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(11.0 * dk), rx(20.0 * dk), ry(pel.prot)),
            mul(tr(pel.sway * fs, pelvY * fs + sink, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));

        if (!dead) {
            heromod.legChain(&wx, &self.rest, self.phase, m, 0, self.fwdB, self.latB, 1.0, HIPL, KNEEL, SOLES[0]);
            heromod.legChain(&wx, &self.rest, self.phase + 0.5, m, 0, self.fwdB, self.latB, -1.0, HIPR, KNEER, SOLES[1]);
        }
        self.poseUpper(&wx, dk, stun, dead, pel.prot);
        self.xf = wx;
        self.chainCloak();
    }

    fn poseUpper(self: *Mage, wx: *[N]rl.Matrix, dk: f32, stun: f32, dead: bool, prot: f32) void {
        const rest = self.rest;
        const twoPi = std.math.tau;
        const m = self.moving * (1.0 - dk);
        const wonk = (self.seed - 0.5) * 6.5;
        const idleAmt = (1.0 - mathx.clampF(self.moving * 2.0, 0, 1)) * (1.0 - dk);
        const swayArg = self.elapsed * (0.55 + 0.22 * (0.5 + 0.5 * mathx.sinf(self.seed * 31.7))) + self.seed * 6.28;
        const swy = mathx.sinf(swayArg) * idleAmt;
        const swyLag = mathx.sinf(swayArg - 0.85) * idleAmt;

        const nod = 1.8 * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const lean = self.bodyLean - 22.0 * stun + 26.0 * dk;
        setLocal(wx, SPINE, rest, mul3(
            rx(lean * 0.42 + nod + 0.8 * swy),
            ry(-0.35 * prot + self.twist * 0.4),
            rz(wonk * 0.5 + 1.1 * swy),
        ));
        setLocal(wx, CHEST, rest, mul3(
            rx(lean * 0.58 + nod * 0.6 + 0.6 * swyLag),
            ry(-0.5 * prot + self.twist * 0.6),
            rz(-wonk * 0.3 - 0.8 * swyLag),
        ));
        setLocal(wx, NECK, rest, rx(self.headPitch * 0.30 + 9.0 * dk - 6.0 * stun));
        setLocal(wx, CAP, rest, mul3(
            rx(self.headPitch * 0.70 + 17.0 * dk - 30.0 * stun),
            ry(-0.5 * prot),
            rz(wonk * 1.4 - 1.3 * swyLag - 0.9 * nod),
        ));

        if (dead) heromod.deadLegs(wx, rest, dk);

        const armStun = -58.0 * stun;
        const busy = mathx.clampF(self.cup + mathx.smoothstep(CARRY_SH, CARRY_SH + 30.0, self.armSh), 0, 1);
        const swing = 13.0 * mathx.sinf(twoPi * self.phase) * m * @abs(self.fwdB) * (1.0 - busy);
        const fwdHalf = mathx.maxF(0, mathx.sinf(twoPi * self.phase)) * m * (1.0 - busy);
        inline for (.{ .{ SHL, ELL, WRL, @as(f32, 1.0) }, .{ SHR, ELR, WRR, @as(f32, -1.0) } }) |arm| {
            const sh = arm[0];
            const el = arm[1];
            const wr = arm[2];
            const side: f32 = arm[3];
            const flex = self.armSh + side * swing + armStun - 26.0 * dk + 1.7 * swyLag + wonk * 0.35 * side;
            setLocal(wx, sh, rest, mul(rx(-flex), rz(side * (self.armAbd + wonk * 0.5 * side))));
            setLocal(wx, el, rest, rx(-(self.armEl - 12.0 * fwdHalf * side + wonk * 0.8 * side)));
            setLocal(wx, wr, rest, mul(rz(side * -22.0 * self.cupAmt()), rx(-14.0 * self.cupAmt())));
        }
    }

    fn chainCloak(self: *Mage) void {
        const swayLag = CLOAK_SWAY * mathx.sinf(std.math.tau * self.phase - 0.85) * self.moving;
        self.cloakMat = mul(mul(rx(self.cloakLean), rz(swayLag)), self.xf[ROOT]);
    }

    pub fn draw(self: *const Mage, model: *const Model) void {
        if (self.gone) return;
        model.draw(self);
    }

    /// The unlit pass — the fire in its hands and the spore dust. Drawn here rather than baked into the mesh
    /// for the leechfly's reason: vertex alpha is a FIXED emissive channel and cannot brighten, and
    /// brightening from nothing to a held ball is the whole cue.
    pub fn drawFx(self: *const Mage) void {
        self.drawCup();
        foe.drawParticles(&self.parts);
    }

    fn drawCup(self: *const Mage) void {
        const k = self.cupAmt();
        if (k <= 0.02) return;
        const at = self.cupWorld();
        const s = self.scale * k * (1.0 + 0.10 * mathx.sinf(self.elapsed * 13.0));
        rl.drawSphereEx(at, BALL_R * s, 8, 8, mathx.withAlpha(FIRE_EDGE, mathx.u8f(120.0 * k)));
        rl.drawSphereEx(at, BALL_CORE * s, 8, 8, mathx.withAlpha(FIRE_CORE, mathx.u8f(220.0 * k)));
    }
};

/// How far the cloak is dragged back by walking, in degrees, and the spring that gets it there.
const CLOAK_DRAG: f32 = 9.0;
const CLOAK_SWAY: f32 = 4.0;
const CLOAK_STIFF: f32 = 90.0;
const CLOAK_DAMP: f32 = 11.0;

/// **ONE NUMBER FOR BOTH ENDS OF THE MOVE** — the thing cupped in its hands and the thing flying at you are
/// the SAME OBJECT. Written out twice they drifted to 0.178 and 0.170: a spell that changes size on the frame
/// it is thrown. METRES, before the creature's own scale. **A DETONATOR, NOT AN EMBER** (owner: bigger
/// fireball, fungal detonator) — half again, and the hands are sized off it.
pub const BALL_R: f32 = 0.212;
pub const BALL_CORE: f32 = BALL_R * 0.64;
const KINDLE_RATE_0: f32 = 8.0;
const KINDLE_RATE_1: f32 = 74.0;
/// …and a ceiling per frame, so a hitched frame cannot spend the whole pool on one gather.
const KINDLE_CAP: usize = 6;
const THROW_PUFF: usize = 14;

pub const SHOVE = foe.Push{ .light = 1.35, .heavy = 3.10 };


fn buildBones() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = pelvisMesh();
    mesh[SPINE] = lumbarMesh();
    mesh[CHEST] = chestMesh();
    mesh[NECK] = neckMesh();
    mesh[CAP] = capMesh();
    mesh[HIPL] = thighMesh(201);
    mesh[KNEEL] = shinMesh(202);
    mesh[ANKL] = bootMesh(1.0, 203);
    mesh[HIPR] = thighMesh(204);
    mesh[KNEER] = shinMesh(205);
    mesh[ANKR] = bootMesh(-1.0, 206);
    mesh[SHL] = upperArmMesh(1.0, 207);
    mesh[ELL] = forearmMesh(1.0, 208);
    mesh[WRL] = handMesh(1.0, 209);
    mesh[SHR] = upperArmMesh(-1.0, 210);
    mesh[ELR] = forearmMesh(-1.0, 211);
    mesh[WRR] = handMesh(-1.0, 212);
    return mesh;
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addBlob(v3(0, -0.005 * H, 0), v3(0.105 * H, 0.075 * H, 0.088 * H), 9, 6, CLOAK);
    b.addBlob(v3(0, 0.030 * H, 0.004 * H), v3(0.100 * H, 0.016 * H, 0.086 * H), 8, 5, CORD);
    return b.toMesh();
}

fn lumbarMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCapsule(v3(0, 0, 0), v3(0, 0.085 * H, 0), 0.098 * H, 0.108 * H, 9, CLOAK);
    return b.toMesh();
}

fn chestMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x3F17);
    b.setMat(.cloth);
    b.addBlob(v3(0, 0.045 * H, 0.004 * H), v3(0.132 * H, 0.098 * H, 0.108 * H), 10, 7, CLOAK);
    b.addBlob(v3(0, -0.010 * H, 0.012 * H), v3(0.118 * H, 0.062 * H, 0.098 * H), 9, 6, CLOAK_LT);
    b.addBlob(v3(0, 0.100 * H, -0.006 * H), v3(0.116 * H, 0.042 * H, 0.100 * H), 9, 6, HEM);
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const a = rng.angle();
        const rr = 0.104 * H;
        b.addBlob(
            v3(mathx.cosf(a) * rr, 0.088 * H + rng.range(-0.010, 0.012) * H, mathx.sinf(a) * rr * 0.9),
            v3(rng.range(0.018, 0.032) * H, rng.range(0.020, 0.036) * H, 0.016 * H),
            5,
            4,
            if (rng.float() < 0.5) HEM else CLOAK,
        );
    }
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(0, 0.040 * H, 0), 0.046 * H, 0.052 * H, 8, FLESH);
    return b.toMesh();
}

/// **THE CAP IS THE READ AND IT GOT BIGGER** (owner: bigger shroom head). 0.150 -> 0.200 of H, which with
/// the new `SCALE` puts the brim at 0.41 m of half-width against the old 0.22 — nearly double. The ceiling
/// below is the same one as before and it still holds: wider than the shoulders, not wider than the creature.
const RIM: f32 = 0.200 * H;
comptime {
    std.debug.assert(RIM > SHOULDER_HALF * 1.35);
    std.debug.assert(RIM < SHOULDER_HALF * 2.4);
}

fn capMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x9C4B);
    b.setMat(.skin);
    // WIDE — wider than the shoulders under it, a hair oblong and leaning a few degrees.
    //
    // **AND WIDE HAS A CEILING, WHICH IS THE BODY.** At 0.196·H the brim was 0.35 m of half-width on a 1.48 m
    // creature: as broad as the whole cloak, and it swallowed the hollow, the eyes and the fire in its hands.
    // `RIM` is that half-width and everything under the dome is a share of it.
    b.addBlob(v3(0, 0.072 * H, 0.004 * H), v3(RIM, 0.090 * H, RIM * 0.94), 11, 9, CAP_COL);
    b.addBlob(v3(0.016 * H, 0.114 * H, -0.012 * H), v3(RIM * 0.56, 0.052 * H, RIM * 0.53), 8, 6, CAP_COL);
    b.addBlob(v3(0, 0.042 * H, 0.006 * H), v3(RIM * 0.90, 0.022 * H, RIM * 0.85), 7, 7, GILL);
    b.addBlob(v3(0, 0.018 * H, 0.048 * H), v3(RIM * 0.50, 0.036 * H, RIM * 0.36), 7, 6, GILL);
    b.setMat(.plain);
    b.addBlob(v3(RIM * 0.24, 0.022 * H, RIM * 0.56), v3(0.016 * H, 0.013 * H, 0.011 * H), 5, 5, EYE);
    b.addBlob(v3(-RIM * 0.22, 0.020 * H, RIM * 0.56), v3(0.015 * H, 0.012 * H, 0.011 * H), 5, 5, EYE);
    b.setMat(.skin);
    var w: u32 = 0;
    while (w < 11) : (w += 1) {
        const a = rng.angle();
        const rr = rng.range(0.20, 0.88) * RIM;
        const sz = rng.range(0.11, 0.22) * RIM;
        b.addBlob(
            v3(mathx.cosf(a) * rr, 0.086 * H + 0.042 * H * (1.0 - rr / RIM), mathx.sinf(a) * rr * 0.94),
            v3(sz, sz * 0.42, sz),
            5,
            4,
            WART,
        );
    }
    b.addBlob(v3(-RIM * 0.72, 0.058 * H, -RIM * 0.56), v3(RIM * 0.26, 0.026 * H, RIM * 0.24), 5, 4, CAP_DK);
    return b.toMesh();
}

fn cloakMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x1D55);
    b.setMat(.cloth);
    const top = 0.075 * H;
    const bot = -0.022 * H - REST[ROOT].y;
    const waist = -0.16 * REST[ROOT].y;
    const knee = -0.58 * REST[ROOT].y;
    skirt(&b, v3(0, top, 0), 0.112 * H, top - waist, 0.104 * H, 11, CLOAK, &rng);
    skirt(&b, v3(0, waist, 0), 0.104 * H, waist - knee, 0.122 * H, 12, HEM, &rng);
    skirt(&b, v3(0, knee, 0), 0.122 * H, knee - bot, 0.156 * H, 13, HEM, &rng);
    return b.toMesh();
}

/// One band of the cloak: a ring of overlapping vertical folds from `r0` to `r1` over `drop`. **AUTHORED AS
/// FOLDS AND NOT AS A CONE** — a turned surface reads as a lampshade however good the colour is, and the
/// unevenness between the folds is what makes it cloth. Cut in AMPLITUDE, never in irregularity.
fn skirt(b: *Builder, at: rl.Vector3, r0: f32, drop: f32, r1: f32, n: u32, col: rl.Color, rng: *mathx.Rng) void {
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const a = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n)) * std.math.tau + rng.range(-0.09, 0.09);
        const wob = rng.range(0.90, 1.12);
        const ca = mathx.cosf(a);
        const sa = mathx.sinf(a);
        b.addCapsule(
            v3(at.x + ca * r0, at.y, at.z + sa * r0),
            v3(at.x + ca * r1 * wob, at.y - drop, at.z + sa * r1 * wob),
            r0 * 0.34,
            r1 * 0.36 * wob,
            5,
            col,
        );
    }
}

fn thighMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.cloth);
    const len = REST[HIPL].y - REST[KNEEL].y;
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), 0.052 * H * rng.range(0.95, 1.08), 0.044 * H, 7, HEM);
    return b.toMesh();
}

fn shinMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.skin);
    const len = REST[KNEEL].y - REST[ANKL].y;
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), 0.038 * H * rng.range(0.94, 1.1), 0.031 * H, 7, FLESH);
    return b.toMesh();
}

fn bootMesh(side: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.skin);
    b.addBlob(v3(side * 0.004 * H, -0.020 * H, 0.058 * H), v3(0.054 * H, 0.026 * H, 0.098 * H), 8, 5, FLESH);
    b.addBlob(v3(0, -0.012 * H, -0.020 * H), v3(0.044 * H, 0.028 * H, 0.038 * H), 6, 4, FLESH);
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const x = (@as(f32, @floatFromInt(i)) - 1.0) * 0.030 * H;
        b.addBlob(v3(x, -0.026 * H, 0.140 * H + rng.range(-0.006, 0.006) * H), v3(0.017 * H, 0.013 * H, 0.020 * H), 4, 4, FLESH);
    }
    return b.toMesh();
}

fn upperArmMesh(side: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.cloth);
    const len = mathx.lenV(mathx.subV(REST[SHL], REST[ELL]));
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), 0.046 * H * rng.range(0.95, 1.06), 0.054 * H, 7, CLOAK);
    b.addBlob(v3(side * 0.006 * H, 0.012 * H, 0), v3(0.058 * H, 0.046 * H, 0.052 * H), 7, 5, CLOAK_LT);
    return b.toMesh();
}

fn forearmMesh(side: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.cloth);
    const len = mathx.lenV(mathx.subV(REST[ELL], REST[WRL]));
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), 0.050 * H, 0.038 * H * rng.range(0.94, 1.08), 7, CLOAK);
    b.addBlob(v3(side * 0.004 * H, -len * 0.94, 0), v3(0.044 * H, 0.020 * H, 0.042 * H), 6, 4, HEM);
    return b.toMesh();
}

fn handMesh(side: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.skin);
    b.addBlob(v3(0, -0.026 * H, 0.010 * H), v3(0.030 * H, 0.034 * H, 0.028 * H), 6, 5, FLESH);
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        const x = side * ((@as(f32, @floatFromInt(i)) - 1.5) * 0.015 * H);
        const l = 0.038 * H * rng.range(0.8, 1.2);
        b.addCapsule(
            v3(x, -0.046 * H, 0.016 * H),
            v3(x + side * rng.range(-0.004, 0.004) * H, -0.046 * H - l * 0.35, 0.016 * H + l),
            0.011 * H,
            0.009 * H,
            5,
            FLESH,
        );
    }
    b.addCapsule(v3(side * 0.026 * H, -0.036 * H, 0.008 * H), v3(side * 0.040 * H, -0.048 * H, 0.030 * H), 0.011 * H, 0.009 * H, 5, FLESH);
    return b.toMesh();
}

pub fn emberMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plain);
    b.addBlob(mathx.zero3, v3(BALL_R, BALL_R, BALL_R), 8, 12, mathx.withAlpha(FIRE_EDGE, 110));
    b.addBlob(mathx.zero3, v3(BALL_CORE, BALL_CORE, BALL_CORE), 7, 10, mathx.withAlpha(FIRE_CORE, 36));
    return b.toModel(shader);
}


const CAP_N = wf.MAX_PER_KIND;

/// Sized off what feeds it: at most a handful of balls in the air at once, `BURST_PUFF` on the last touch of
/// each and `BOUNCE_PUFF` on the ones before, against a fire mote's own ~0.5 s life.
const EMBER_PARTS = 120;
const BOUNCE_PUFF: usize = 10;
const BURST_PUFF: usize = 26;

pub const Ring = struct {
    model: Model,
    mages: [CAP_N]Mage = undefined,
    n: usize = 0,
    parts: [EMBER_PARTS]foe.Particle = [_]foe.Particle{.{}} ** EMBER_PARTS,
    fxHead: usize = 0,
    fxRng: mathx.Rng = mathx.Rng.init(0x8E11),

    pub fn init(shader: rl.Shader) Ring {
        return .{ .model = Model.init(shader) };
    }

    pub fn bounce(self: *Ring, at: rl.Vector3) void {
        const from = self.fxHead;
        elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, at, v3(0, 1, 0), .fire, BOUNCE_PUFF, 1.0);
        foe.floorBurst(&self.parts, from, self.fxHead, at.y);
    }

    pub fn splash(self: *Ring, at: rl.Vector3) void {
        const from = self.fxHead;
        elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, at, v3(0, 1, 0), .fire, BURST_PUFF, 1.0);
        foe.floorBurst(&self.parts, from, self.fxHead, at.y);
    }
    pub fn live(self: *Ring) []Mage {
        return self.mages[0..self.n];
    }
    pub fn liveConst(self: *const Ring) []const Mage {
        return self.mages[0..self.n];
    }
    pub fn reset(self: *Ring, m: *const wf.Map) void {
        foe.resetGroup(Mage, &self.mages, &self.n, m, .mushroom_mage);
    }
    pub fn clear(self: *Ring) void {
        self.n = 0;
    }
    pub fn setShader(self: *Ring, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn update(self: *Ring, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        foe.tickParticles(&self.parts, dt, hero.y);
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    pub fn draw(self: *const Ring, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Ring) void {
        for (self.liveConst()) |*k| k.drawFx();
        foe.drawParticles(&self.parts);
    }
    pub fn pierce(self: *Ring, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Ring) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Ring) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Ring) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Ring) u32 {
        return foe.aliveCount(self.liveConst());
    }
};


test "THE GATHER IS A REAL TELL, and the ball leaves inside the throw that follows it" {
    try std.testing.expect(LOB_WIND >= foe.TELL_MIN);
    // …and it is the LONGEST part of the move by a clear margin: the thing being read is the FACING at the
    // release, and a gather you can only just see is a facing you cannot read at all.
    try std.testing.expect(LOB_WIND > LOB_THROW * 3.0);
    try std.testing.expect(RELEASE_K > 0 and RELEASE_K < 0.5);
}

test "THE SEAM IS THE END POSE — wind[1.0] and throw[0.0] are the same pose, and so are throw[1] and recover[0]" {
    const windEnd = samplePose(&WIND_KEYS, 1.0);
    const throwStart = samplePose(&THROW_KEYS, 0.0);
    for (windEnd, throwStart) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-5);
    const throwEnd = samplePose(&THROW_KEYS, 1.0);
    const recStart = samplePose(&RECOVER_KEYS, 0.0);
    for (throwEnd, recStart) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-5);
    const recEnd = samplePose(&RECOVER_KEYS, 1.0);
    for (CARRY, recEnd) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-5);
}

test "THE THROW HAS A SHAPE — most of its travel in the first third, and the fire is out of its hands by the end" {
    const a = samplePose(&THROW_KEYS, 0.0);
    const mid = samplePose(&THROW_KEYS, 1.0 / 3.0);
    const b = samplePose(&THROW_KEYS, 1.0);
    var moved: f32 = 0;
    var total: f32 = 0;
    for (a, mid, b) |v0, vm, v1| {
        moved += @abs(vm - v0);
        total += @abs(v1 - v0);
    }
    try std.testing.expect(total > 1e-3);
    try std.testing.expect(moved > total * 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), b[CH_CUP], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), a[CH_CUP], 1e-6);
}

test "IT KEEPS ITS DISTANCE: it throws from its band, backs off inside it, and closes from outside it" {
    try std.testing.expectEqual(Choice.hold, classify(AGGRO_R + 1.0, true));
    try std.testing.expectEqual(Choice.lob, classify((LOB_MIN + LOB_MAX) * 0.5, true));
    try std.testing.expectEqual(Choice.back, classify(FLEE_R - 0.5, true));
    try std.testing.expectEqual(Choice.keep, classify((LOB_MIN + LOB_MAX) * 0.5, false));
    try std.testing.expectEqual(Choice.keep, classify(LOB_MAX + 2.0, true));
}

test "THE FIREBALL IS SLOW, IT BOUNCES, AND IT IS THE ONLY THING IN THE POOL THAT DOES" {
    try std.testing.expect(EMBER_SPEED < koboldmod.CLUMP_SPEED);
    try std.testing.expect(archermod.bouncesOf(.emberball) >= 2);
    inline for (.{ .arrow, .firearrow, .clump, .crock, .venom, .bolt, .wisp }) |s| {
        try std.testing.expectEqual(@as(u8, 0), archermod.bouncesOf(s));
    }
    try std.testing.expectApproxEqAbs(@as(f32, 0), EMBER_HIT.dmg, 1e-6);
    try std.testing.expectApproxEqAbs(EMBER_HIT.raw(), EMBER_HIT.elem.at(.fire), 1e-6);
}

test "IT IS NOT KILLED BY ITS OWN ELEMENT, and chaos is what answers it" {
    var v = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    _ = v.hit(combat.Hit{ .elem = combat.elems(.{ .fire = 30 }) });
    const afterFire = HP_MAX - v.hp;
    v = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    _ = v.hit(combat.Hit{ .elem = combat.elems(.{ .chaos = 30 }) });
    const afterChaos = HP_MAX - v.hp;
    try std.testing.expect(afterFire < 30.0);
    try std.testing.expect(afterChaos > 30.0);
    try std.testing.expect(afterChaos > afterFire * 1.8);
    std.debug.print("\n  mushroom mage: 30 fire takes {d:.1} HP, 30 chaos takes {d:.1}\n", .{ afterFire, afterChaos });
}

test "AN INTERRUPTED MAGE DROPS WHAT IT WAS HOLDING — the picture may not keep a spell the mechanic lost" {
    var k = Mage.spawn(mathx.zero3, 0, 1.0, 0.4);
    k.stageGather(1.0);
    try std.testing.expect(k.cupAmt() > 0.9);
    k.debugStagger(false);
    try std.testing.expectApproxEqAbs(@as(f32, 0), k.cupAmt(), 1e-6);
    try std.testing.expect(k.staggered());
}

test "THE BALL LEAVES ITS HANDS ONCE, however the frame falls" {
    const hero = mathx.ground(0, 9.0);
    var fired: u32 = 0;
    var k = Mage.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.state = .lob_throw;
    k.t = 0;
    for ([_]f32{ 1.0 / 60.0, 1.0 / 12.0 }) |dt| {
        var m = k;
        var t: f32 = 0;
        while (t < LOB_THROW + dt) : (t += dt) {
            _ = m.update(dt, hero, 200.0, .{});
            if (m.lobbed) fired += 1;
        }
        try std.testing.expectEqual(@as(u32, 1), fired);
        fired = 0;
    }
}

test "THE CAP CARRIES THE MARK AND THE HURT SPHERE HOLDS IT" {
    var k = Mage.spawn(mathx.zero3, 0, 1.0, 0.5);
    k.pose();
    const mark = k.lockPoint();
    const c = k.centerWorld();
    const r = k.hurtRadius();
    // The mark rides the posed cap, so it is above the hurt centre and inside the sphere — a mark outside
    // what a sword can reach is a reticle on a place you cannot hit.
    try std.testing.expect(mark.y > c.y);
    try std.testing.expect(mathx.lenV(mathx.subV(mark, c)) <= r);
    try std.testing.expect(k.topWorld().y > mark.y);
    std.debug.print("  mushroom mage: crown {d:.2} m, mark {d:.2} m, hurt centre {d:.2} m (r {d:.2})\n", .{
        k.topWorld().y, mark.y, c.y, r,
    });
}

test "THE CUP IS BETWEEN THE HANDS AND IN FRONT OF THE BODY, at the frame it throws off" {
    var k = Mage.spawn(mathx.zero3, 0, 1.0, 0.2);
    k.stageGather(1.0);
    const at = k.cupWorld();
    const l = foe.markOn(k.xf[WRL], v3(0, -0.02 * H, 0.05 * H));
    const r = foe.markOn(k.xf[WRR], v3(0, -0.02 * H, 0.05 * H));
    const apart = mathx.lenV(mathx.subV(l, r));
    const tall = H * SCALE;
    std.debug.print("  mushroom mage cup: {d:.2} m up of {d:.2}, {d:.2} m out, hands {d:.2} m apart, ball {d:.2} across\n", .{ at.y, tall, at.z, apart, BALL_R * 2.0 * SCALE });
    // In FRONT of it (it faces +Z at yaw 0) and up at its own chest — a ball conjured behind or below the
    // creature is one the player never sees being made.
    try std.testing.expect(at.z > 0.10);
    // **SHARES OF THE CREATURE, NOT METRE MARKS.** It grew (`SCALE`) and both bounds here were the OLD
    // mage written down as constants — 1.35 m of chest height and 0.55 m of shoulder span. Either one
    // fails the next time somebody resizes it, which is exactly what happened.
    try std.testing.expect(at.y > tall * 0.30 and at.y < tall * 0.85);
    // Two hands cupping ONE ball may not be further apart than the ball is wide, twice over.
    try std.testing.expect(apart < BALL_R * 4.0 * SCALE);
}
