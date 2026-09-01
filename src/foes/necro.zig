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
const archermod = @import("archer.zig");
const propart = @import("../props/propart.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

const BONE = archermod.BONE;
const BONE_DK = archermod.BONE_DK;
const BONE_LT = archermod.BONE_LT;

const ROBE = rgba(14, 19, 36, 255);
const ROBE_LT = rgba(22, 28, 48, 255);
const ROBE_DK = rgba(9, 12, 22, 255);
const HEM = rgba(8, 12, 26, 255);
const CORD = rgba(74, 62, 44, 255);

const RIME_ALB = rgba(44, 58, 72, 255);
const RIME_ALB_LT = rgba(62, 80, 96, 255);
const RIME = mathx.withAlpha(elemfx.sig(.cold).edge, 255);
const RIME_LT = rgba(206, 234, 246, 255);
const FROST_MOTE = elemfx.sig(.cold).core;
const FROST_SHARD = rgba(168, 208, 228, 240);
const FROST_COOL = elemfx.sig(.cold).cool;
const RAISE_GLOW = rgba(236, 198, 104, 200);

const DUST = foe.DUST;
/// He is the archer's own skeleton — same stature, same feet, same dissolve — so he chips at the archer's grade.
const CHIP_SPRAY = archermod.boneChips(1.0);

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
const STAFF = heromod.HELD;

const H: f32 = heromod.H;

/// 2.85 m to the crown against the hero's 1.8 — it looks DOWN at him from across the field.
pub const SCALE = (H + 1.05) / H;
const HIP_HALF = heromod.HIP_HALF * 0.60;
const SHOULDER_HALF = heromod.SHOULDER_HALF * 0.64;
const REST = heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);
/// His feet are the archer's feet, and `footMesh` is what a sole patch is measured off.
const solePatches = archermod.solePatches;

const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const scaleM = mathx.scaleM;
const lerpF = mathx.lerpF;
const setLocal = heromod.setHumanoid;

const FIST_Y = -0.05 * H;
const FIST_Z = 0.02 * H;

pub var AGGRO_R: f32 = 26.0;
const TURN_RATE = 4.6;
const WALK_SPEED = heromod.WALK_SPEED_BANK * 1.18;
const SPEED = 1.0;
const BODY_R = 0.34;
const HURT_R = 0.42;
pub var SOULS: u32 = 520;

const HP_MAX: f32 = 84.0;
/// **ALMOST NONE.** Under the hero's light poke (10 poise), so ANYTHING that lands staggers it.
const POISE_MAX: f32 = 5.0;
const STANCE_MAX: f32 = 34.0;

const RESISTS = combat.resists(.{ .fire = -35, .cold = 75, .chaos = 45 });

const DEATH_DUR = archermod.DEATH_DUR;
const DISS_DUR = archermod.DISS_DUR;
const SHOVE_DECAY = 7.0;
const A_PROT = 2.6;

// **THE CORPSE IS THE MECHANIC, AND THE WINDOW HAD TO BE MADE TO EXIST.** A skeleton is 2.05 s from the killing
// blow to its last mote and a readable tell does not fit inside that, so a body inside `RAISE_R` of a living
// necromancer **STOPS DISSIPATING** (`vigil`, stamped by `game.markVigil`, read by `foe.dissipate`).
pub const RAISE_R: f32 = 11.0;
pub const RAISE_WIND: f32 = 1.90;
const RAISE_DUR: f32 = 0.42;
const RAISE_RECOVER: f32 = 1.15;
const RAISE_CD: f32 = 7.5;
pub const RAISE_HP_FRAC: f32 = 0.55;
pub const RAISE_MATCH_R: f32 = 1.2;

const FROST_HIT_BANK = combat.Hit{ .poise = 18, .stance = 8, .elem = combat.elems(.{ .cold = 38 }) };
pub var FROST_HIT = FROST_HIT_BANK;
pub const FROST_R: f32 = 2.4;
/// The cast — the staff comes up and the hand goes out over the mark. PUBLIC because the harness aims a beat with it (`shots.FROST_TELL_AT`): a portrait pinned to a literal 0.65 s photographs somewhere else later.
pub const FROST_WIND: f32 = 0.72;
const FROST_CAST_DUR: f32 = 0.30;
const FROST_RECOVER: f32 = 0.70;
/// **AND IT GREW WITH THE CASTER.** The ring lands at `FROST_R * SCALE`, so making the necromancer taller widened it from 3.80 m to 4.16 m of ground to clear. 2.4 m/s of walking over 2.7 s clears 4.59 m.
pub const FROST_FUSE: f32 = 2.70;
const FROST_CD: f32 = 4.2;
const FROST_R_MIN: f32 = 3.0;
const FROST_R_MAX: f32 = 18.0;

comptime {
    // The ring lands centred on him, so he must clear its radius plus his own footprint. **MEASURED AT THE SCALE IT IS DRAWN AT** — the field radius is `FROST_R * scale`, and asserting the bare `FROST_R` would pass on a ring a third wider.
    std.debug.assert(FROST_FUSE * 1.7 > FROST_R * SCALE + foe.HERO_R);
    std.debug.assert(FROST_WIND >= foe.TELL_MIN);
    std.debug.assert(RAISE_WIND > FROST_WIND + FROST_CAST_DUR);
    std.debug.assert(RAISE_CD > RAISE_WIND + RAISE_DUR + RAISE_RECOVER);
    std.debug.assert(FROST_HIT_BANK.dmg == 0 and FROST_HIT_BANK.elem.at(.cold) > 0);
    std.debug.assert(RAISE_R > FROST_R_MIN);
    // **THE RANGE IT WANTS TO STAND AT MUST SIT INSIDE THE RANGE IT CAN CAST FROM.** Two independently authored bands that only happen to overlap is a creature that walks to the one place it cannot cast.
    std.debug.assert(WANT_MIN >= FROST_R_MIN and WANT_MAX <= FROST_R_MAX);
    std.debug.assert(WANT_MIN < WANT_MAX);
    std.debug.assert(WANT_MIN > FROST_R * SCALE);
}

/// Sized by ARITHMETIC over the worst FRAME, not over the biggest burst — which is what 104 was. The sigil's
/// fuse runs on its own clock, so the ring going off (60) lands on the creep it has been laying the whole 2.70 s (22/s at a 1.0 s life) and can share that frame with the blow that kills the caster. At 104 that frame overwrote 34 of its own motes.
const NPART = 144;
const RAISE_BLOOM: u32 = 40;
const FROST_BLOOM: u32 = 30;
const FROST_SHARDS: u32 = 60;
const CREEP_RATE: f32 = 22.0;
const CREEP_LIFE_HI: f32 = 1.00;
const CHIP_LIGHT: u32 = 11;
const CHIP_HEAVY: u32 = 18;
const CHIP_DEATH: u32 = 20;
comptime {
    std.debug.assert(@as(f32, NPART) >= CREEP_RATE * CREEP_LIFE_HI + @as(f32, @floatFromInt(FROST_SHARDS +
        @as(u32, @intCast(foe.hitParts(CHIP_HEAVY) + foe.hitParts(CHIP_DEATH))) + foe.WOUND_PARTS)));
    // The raise's bloom is the other one-shot that can be up under all that, and it is smaller than the blow.
    std.debug.assert(RAISE_BLOOM <= foe.hitParts(CHIP_HEAVY) + foe.hitParts(CHIP_DEATH) and FROST_BLOOM < NPART);
}

const HEM_DRAG = 15.0;
const HEM_EASE = 6.5;
const HEM_SETTLE = 3.4;
const HEM_SWAY = 2.2;

const State = enum { idle, drift, leap, raise_wind, raise_up, frost_wind, frost_cast, recover, stunlight, stunheavy, dead };

/// Its own type rather than a bool, because the recovery reads it through an exhaustive switch — a third move then cannot be added without saying how long its opening is.
const Spent = enum { raise, frost };

const Choice = enum { raise, frost, keep, hold };
fn classify(dist: f32, hasBody: bool, raiseReady: bool, frostReady: bool) Choice {
    if (dist > AGGRO_R) return .hold;
    if (hasBody and raiseReady) return .raise;
    if (frostReady and dist >= FROST_R_MIN and dist <= FROST_R_MAX) return .frost;
    return .keep;
}

// **AND IT LEAPS AWAY RATHER THAN BACKING UP.** Inside `LEAP_R` it goes backwards in one burst — four times its own walk for a third of a second, which buys most of the band it wants in less time than a swing takes.
const LEAP_R: f32 = 4.2;
const LEAP_DUR: f32 = 0.34;
const LEAP_SPEED: f32 = 4.6;
const LEAP_CD: f32 = 2.2;
/// A hop, not a glide. Metres at the top of the arc — enough to read as leaving the ground and not enough to clear anything.
const LEAP_UP: f32 = 0.55;

const WANT_MIN: f32 = 8.0;
const WANT_MAX: f32 = 15.0;
const DRIFT_DUR: f32 = 0.9;

/// A CORPSE THIS CREATURE IS HOLDING OPEN, stamped by the game (`game.markVigil`) — `Leash`'s law: the creature reads the field and never reaches out for the state. Null means nothing worth standing over.
pub const Vigil = struct {
    at: ?rl.Vector3 = null,

    pub fn any(self: *const Vigil) bool {
        return self.at != null;
    }
};

const Sigil = struct {
    at: rl.Vector3 = mathx.zero3,
    left: f32 = 0,
    blew: f32 = mathx.LONG_AGO,

    fn live(self: *const Sigil) bool {
        return self.left > 0;
    }
    /// **0 AT THE CAST, 1 AT THE BURST** — what the ring on the ground is drawn off, so the picture and the fuse are one number.
    fn fill(self: *const Sigil) f32 {
        return mathx.clampF(1.0 - self.left / FROST_FUSE, 0, 1);
    }
};

pub const Model = struct {
    bone: [N]rl.Mesh,
    hem: rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "necro");
        var bone: [N]rl.Mesh = undefined;
        bone[ROOT] = pelvisMesh();
        bone[SPINE] = abdomenMesh();
        bone[CHEST] = chestMesh();
        bone[NECK] = neckMesh();
        bone[SKULL] = helmMesh();
        bone[HIPL] = thighMesh();
        bone[KNEEL] = shankMesh();
        bone[ANKL] = archermod.footMesh(1.0, 211);
        bone[HIPR] = thighMesh();
        bone[KNEER] = shankMesh();
        bone[ANKR] = archermod.footMesh(-1.0, 214);
        bone[SHL] = sleeveMesh();
        bone[ELL] = forearmMesh();
        bone[WRL] = handMesh();
        bone[SHR] = sleeveMesh();
        bone[ELR] = forearmMesh();
        bone[WRR] = handMesh();
        bone[STAFF] = staffMesh();
        return .{ .bone = bone, .hem = hemMesh(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, k: *const Necro) void {
        for (0..N) |i| rl.drawMesh(self.bone[i], self.mat, k.xf[i]);
        rl.drawMesh(self.hem, self.mat, k.hemXf());
    }
};

pub const Necro = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// **THE FIELD A UNIT OWES ITS ORDERS** (`foe.Post`), stamped at spawn off the map's `ai=` and `wp=`.
    post: foe.Post = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    vigil: Vigil = .{},
    facing: f32 = 0,
    scale: f32 = SCALE,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    raiseCd: f32 = 0,
    frostCd: f32 = 0,
    /// **THE BODY IT RAISED THIS FRAME** — a one-frame flag, reset at the TOP of `update`. The creature cannot do the raising itself: the body is in another group, another array, another type.
    raised: bool = false,
    raiseAt: rl.Vector3 = mathx.zero3,
    spent: Spent = .frost,
    sigil: Sigil = .{},
    /// **A RING WENT INTO THE GROUND THIS FRAME** — a one-frame edge, reset at the TOP of `update`. As a window on the fuse's own clock it read true for three frames at 60 fps: one cast, three shakes.
    laid: bool = false,
    heroHit: ?combat.Hit = null,
    hitFrom: rl.Vector3 = mathx.zero3,
    moveDir: rl.Vector3 = mathx.zero3,
    homing: bool = false,
    parried: bool = false,

    staffSh: f32 = STAFF_CARRY_SH,
    staffEl: f32 = STAFF_CARRY_EL,
    staffAbd: f32 = STAFF_CARRY_ABD,
    staffTilt: f32 = STAFF_CARRY_TILT,
    castSh: f32 = FREE_CARRY_SH,
    castEl: f32 = FREE_CARRY_EL,
    castAbd: f32 = FREE_CARRY_ABD,
    bodyLean: f32 = 6.0,
    twist: f32 = 0,
    headPitch: f32 = 4.0,
    headYaw: f32 = 0,
    hemLean: f32 = 0,
    hemVel: f32 = 0,

    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,
    prevPhase: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    leapCd: f32 = 0,
    hop: f32 = 0,
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},
    fade: f32 = 0,
    gone: bool = false,

    parts: [NPART]foe.Particle = [_]foe.Particle{.{}} ** NPART,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    sigAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    xf: [N]rl.Matrix = undefined,
    hemMat: rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Necro {
        var k = Necro{
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale * SCALE,
            .seed = seed,
            .vit = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
        };
        k.rest = REST;
        k.fxRng = foe.fxStream(seed, 68041.0, 23);
        k.raiseCd = 0.4 + seed * 1.1;
        k.frostCd = 0.9 + seed * 1.3;
        k.pose();
        return k;
    }

    pub fn centerWorld(self: *const Necro) rl.Vector3 {
        return foe.markOn(self.xf[CHEST], mathx.zero3);
    }
    pub fn hurtRadius(self: *const Necro) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Necro) f32 {
        return BODY_R * self.scale;
    }
    pub fn lockPoint(self: *const Necro) rl.Vector3 {
        return foe.markOn(self.xf[SKULL], archermod.LOCK_AT);
    }
    pub fn topWorld(self: *const Necro) rl.Vector3 {
        return foe.bodyPoint(self.pos, archermod.TOP_F * H, self.scale, 0);
    }
    pub fn alive(self: *const Necro) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Necro) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Necro) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn flashFrac(self: *const Necro) f32 {
        return foe.flashFrac(self.flash);
    }
    pub fn airborne(self: *const Necro) bool {
        _ = self;
        return false;
    }
    pub fn soulValue(self: *const Necro) u32 {
        _ = self;
        return SOULS;
    }

    pub fn casting(self: *const Necro) bool {
        return self.state == .raise_wind or self.state == .raise_up;
    }

    fn fdir(self: *const Necro) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn faceToward(self: *Necro, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }

    pub fn navWant(self: *const Necro, hero: rl.Vector3) ?rl.Vector3 {
        _ = hero;
        if (self.state != .drift) return null;
        if (self.homing) return self.home;
        return mathx.addV(self.pos, self.moveDir);
    }

    pub fn update(self: *Necro, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        // **CLEARED BEFORE THE `gone` BRANCH, NOT AFTER IT.** The ring outlives its caster, so reset only on the live path the corpse's own branch returned the SAME hit every frame from the burst onward — cold damage forever, off one ring, silently.
        self.heroHit = null;
        self.laid = false;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            self.tickSigil(dt, hero);
            return self.heroHit;
        }
        self.justDied = false;
        self.raised = false;
        self.parried = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        self.raiseCd = mathx.maxF(0, self.raiseCd - dt);
        self.frostCd = mathx.maxF(0, self.frostCd - dt);
        self.leapCd = mathx.maxF(0, self.leapCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, foe.tetherFor(self), hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;
        var moveSpeed: f32 = 0;

        switch (self.state) {
            .idle => {
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                self.setCarry(dt);
                // **ORDERS ARE WHAT IT DOES BEFORE IT HAS SEEN ANYBODY** (`foe.postDrive`), refused inside the ring.
                _ = foe.postDrive(self, dt, bounds, WALK_SPEED, d, AGGRO_R, TURN_RATE, &movedDist, &moveSpeed, &moveYaw);
                if (self.t >= 0.20) self.decide(d);
            },
            .leap => {
                self.faceToward(hero, dt);
                const way = self.nav.along(self.moveDir);
                const u = mathx.clampF(self.t / LEAP_DUR, 0, 1);
                moveSpeed = LEAP_SPEED * mathx.sinf(std.math.pi * u);
                const moved = moveSpeed * dt;
                mathx.stepXZ(&self.pos, way, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(way);
                self.hop = LEAP_UP * mathx.sinf(std.math.pi * u);
                self.setCarry(dt);
                if (self.t >= LEAP_DUR) {
                    self.hop = 0;
                    self.decide(d);
                }
            },
            .drift => {
                self.faceToward(hero, dt);
                const way = self.nav.along(self.moveDir);
                moveSpeed = WALK_SPEED * SPEED;
                const moved = moveSpeed * dt;
                mathx.stepXZ(&self.pos, way, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(way);
                self.setCarry(dt);
                if (self.homing and mathx.distXZ(self.pos, self.home) <= foe.LEASH_HOME_R) {
                    self.homing = false;
                    self.enter(.idle);
                } else if (self.t >= DRIFT_DUR) self.decide(d);
            },
            .raise_wind => {
                // **IT TURNS TO THE BODY IT COMMITTED TO, NOT TO HIM** — and that IS the tell. `raiseAt` and never `vigil.at`: the spot is committed at the START of the gather, so a nearer body falling mid-tell cannot swing 1.9 s of announcement onto somewhere else.
                self.faceToward(self.raiseAt, dt);
                const u = mathx.clampF(self.t / RAISE_WIND, 0, 1);
                self.setRaiseWind(u);
                self.gather(dt, u);
                if (self.t >= RAISE_WIND) self.enter(.raise_up);
            },
            .raise_up => {
                self.setRaiseUp(mathx.clampF(self.t / RAISE_DUR, 0, 1));
                if (self.t >= RAISE_DUR) {
                    self.raised = true;
                    self.spent = .raise;
                    self.raiseCd = RAISE_CD;
                    self.bloom(self.raiseAt, RAISE_BLOOM);
                    sfx.world(.shade_gather, self.raiseAt);
                    self.enter(.recover);
                }
            },
            .frost_wind => {
                self.faceToward(hero, dt);
                self.setFrostWind(mathx.clampF(self.t / FROST_WIND, 0, 1));
                if (self.t >= FROST_WIND) self.enter(.frost_cast);
            },
            .frost_cast => {
                self.faceToward(hero, dt * 0.4);
                const u = mathx.clampF(self.t / FROST_CAST_DUR, 0, 1);
                self.setFrostCast(u);
                if (self.t >= FROST_CAST_DUR) {
                    self.lay(hero);
                    self.spent = .frost;
                    self.frostCd = FROST_CD;
                    self.enter(.recover);
                }
            },
            .recover => {
                self.setRecover(mathx.clampF(self.t / self.recoverDur(), 0, 1));
                if (self.t >= self.recoverDur()) self.decide(d);
            },
            .stunlight => {
                self.easeNeutral(dt);
                if (self.t >= combat.FOE_LIGHT_STUN_DUR) self.enter(.idle);
            },
            .stunheavy => {
                self.easeNeutral(dt);
                if (self.t >= combat.FOE_HEAVY_STUN_DUR) self.enter(.idle);
            },
            .dead => {
                self.easeNeutral(dt);
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, archermod.DISSOLVE);
            },
        }

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        self.footfalls();
        self.tickHem(dt, moveSpeed);
        self.pose();
        self.tickSigil(dt, hero);
        self.tryHit(blade);
        return self.heroHit;
    }

    fn recoverDur(self: *const Necro) f32 {
        return switch (self.spent) {
            .raise => RAISE_RECOVER,
            .frost => FROST_RECOVER,
        };
    }

    fn tickSigil(self: *Necro, dt: f32, hero: rl.Vector3) void {
        self.sigil.blew = mathx.minF(self.sigil.blew + dt, mathx.LONG_AGO);
        if (!self.sigil.live()) return;
        self.sigil.left -= dt;
        self.creep(dt);
        if (self.sigil.left > 0) return;
        self.sigil.left = 0;
        self.sigil.blew = 0;
        self.burst();
        if (mathx.distXZ(self.sigil.at, hero) <= FROST_R * self.scale + foe.HERO_R) {
            // THE ORIGIN IS THE RING, NOT THE CASTER (the delver's burst): stood on the mark there is no bearing, so the boards cannot answer it, and caught at the rim they can.
            self.bill(FROST_HIT, self.sigil.at);
        }
    }

    /// **A BLOW AND WHERE IT CAME FROM, SET TOGETHER OR NOT AT ALL.** A move that set `heroHit` and forgot the other half would bill from the WORLD ORIGIN — a bearing the shield can answer, on the one blow that must never have one.
    fn bill(self: *Necro, hit: combat.Hit, from: rl.Vector3) void {
        self.heroHit = hit;
        self.hitFrom = from;
        self.leash.noteCombat();
    }

    fn lay(self: *Necro, hero: rl.Vector3) void {
        self.sigil = .{ .at = v3(hero.x, hero.y, hero.z), .left = FROST_FUSE, .blew = mathx.LONG_AGO };
        self.laid = true;
        sfx.world(.wand_cast, self.sigil.at);
        self.mark(FROST_BLOOM);
    }

    fn enter(self: *Necro, s: State) void {
        self.state = s;
        self.t = 0;
        switch (s) {
            .raise_wind => {
                self.raiseAt = self.vigil.at orelse self.pos;
                sfx.world(.shade_reach, self.pos);
            },
            .frost_wind => sfx.world(.wand_charge, self.pos),
            else => {},
        }
    }
    fn enterStun(self: *Necro, s: State) void {
        self.state = s;
        self.t = 0;
        self.homing = false;
    }
    fn enterDeath(self: *Necro) void {
        self.enterStun(.dead);
        self.justDied = true;
    }

    fn decide(self: *Necro, dist: f32) void {
        if (self.leash.goingHome()) {
            self.homing = true;
            self.moveDir = mathx.dirXZ(self.pos, self.home);
            return self.enter(.drift);
        }
        self.homing = false;
        switch (classify(dist, self.vigil.any(), self.raiseCd <= 0, self.frostCd <= 0)) {
            .raise => self.enter(.raise_wind),
            .frost => self.enter(.frost_wind),
            .keep => {
                const f = self.fdir();
                const side: f32 = if (self.seed < 0.5) 1.0 else -1.0;
                const out = mathx.scaleV(f, -1.0);
                const lat = mathx.scaleV(mathx.perpXZ(f), side);
                if (dist < LEAP_R and self.leapCd <= 0) {
                    self.leapCd = LEAP_CD;
                    self.moveDir = mathx.normV(mathx.addV(out, mathx.scaleV(lat, 0.35)));
                    return self.enter(.leap);
                }
                self.moveDir = if (dist < WANT_MIN)
                    mathx.normV(mathx.addV(out, mathx.scaleV(lat, 0.5)))
                else if (dist > WANT_MAX)
                    mathx.normV(mathx.addV(f, mathx.scaleV(lat, 0.4)))
                else
                    lat;
                self.enter(.drift);
            },
            .hold => {
                if (mathx.distXZ(self.pos, foe.homeFor(self)) > foe.LEASH_HOME_R) {
                    self.homing = true;
                    self.moveDir = mathx.dirXZ(self.pos, self.home);
                    self.enter(.drift);
                } else self.enter(.idle);
            },
        }
    }

    pub fn tryHit(self: *Necro, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        const heavyBlow = foe.wounded(self, s, blade, .{ .light = 1.5, .heavy = 2.3 });
        self.chips(s.contact, s.dir, if (heavyBlow) CHIP_HEAVY else CHIP_LIGHT, if (heavyBlow) 3.2 else 2.2);
        sfx.world(.bone_hurt, self.pos);
        switch (s.reaction) {
            .death => {
                self.chips(s.contact, s.dir, CHIP_DEATH, 2.8);
                sfx.world(.bone_die, self.pos);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    pub fn debugRaise(self: *Necro, at: rl.Vector3) void {
        self.vigil.at = at;
        self.raiseCd = 0;
        self.enter(.raise_wind);
    }
    pub fn debugFrost(self: *Necro) void {
        self.frostCd = 0;
        self.enter(.frost_wind);
    }
    pub fn debugLay(self: *Necro, hero: rl.Vector3) void {
        self.lay(hero);
    }
    pub fn stagger(self: *Necro, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Necro) void {
        self.enterDeath();
    }


    fn setCarry(self: *Necro, dt: f32) void {
        const e = dt * 6.0;
        self.staffSh = approach(self.staffSh, STAFF_CARRY_SH, e);
        self.staffEl = approach(self.staffEl, STAFF_CARRY_EL, e);
        self.staffAbd = approach(self.staffAbd, STAFF_CARRY_ABD, e);
        self.staffTilt = approach(self.staffTilt, STAFF_CARRY_TILT, e);
        self.castSh = approach(self.castSh, FREE_CARRY_SH, e);
        self.castEl = approach(self.castEl, FREE_CARRY_EL, e);
        self.castAbd = approach(self.castAbd, FREE_CARRY_ABD, e);
        self.bodyLean = approach(self.bodyLean, 6.0, e);
        self.twist = approach(self.twist, 0, e);
        self.headPitch = approach(self.headPitch, 4.0, e);
        self.headYaw = approach(self.headYaw, 0, e);
    }

    /// **THE GATHER TRAVELS HARD, AND IT TRAVELS AWAY FROM WHERE IT ENDS** (the knight's tell lesson). Every channel is moving for the whole 1.9 s, because a committed action that shows nothing never began.
    fn setRaiseWind(self: *Necro, u: f32) void {
        const e = mathx.smoothstep(0, 0.92, u);
        self.staffSh = lerpF(STAFF_CARRY_SH, RAISE_STAFF_SH, e);
        self.staffEl = lerpF(STAFF_CARRY_EL, RAISE_STAFF_EL, e);
        self.staffAbd = lerpF(STAFF_CARRY_ABD, RAISE_STAFF_ABD, e);
        self.staffTilt = lerpF(STAFF_CARRY_TILT, RAISE_STAFF_TILT, e);
        self.castSh = lerpF(FREE_CARRY_SH, RAISE_FREE_SH, e);
        self.castEl = lerpF(FREE_CARRY_EL, RAISE_FREE_EL, e);
        self.castAbd = lerpF(FREE_CARRY_ABD, RAISE_FREE_ABD, e);
        self.bodyLean = lerpF(6.0, RAISE_LEAN, e);
        self.twist = lerpF(0, RAISE_TWIST, e);
        self.headPitch = lerpF(4.0, RAISE_HEAD, e);
        self.headYaw = lerpF(0, RAISE_HEAD_YAW, e);
    }

    fn setRaiseUp(self: *Necro, u: f32) void {
        const e = foe.swingCurve(u);
        self.castSh = lerpF(RAISE_FREE_SH, RAISE_THROW_SH, e);
        self.castEl = lerpF(RAISE_FREE_EL, RAISE_THROW_EL, e);
        self.castAbd = lerpF(RAISE_FREE_ABD, RAISE_THROW_ABD, e);
        self.bodyLean = lerpF(RAISE_LEAN, RAISE_THROW_LEAN, e);
        self.twist = lerpF(RAISE_TWIST, -RAISE_TWIST * 0.4, e);
        self.headPitch = lerpF(RAISE_HEAD, RAISE_HEAD + 12.0, e);
    }

    fn setFrostWind(self: *Necro, u: f32) void {
        const e = mathx.smoothstep(0, 0.9, u);
        self.staffSh = lerpF(STAFF_CARRY_SH, FROST_STAFF_SH, e);
        self.staffEl = lerpF(STAFF_CARRY_EL, FROST_STAFF_EL, e);
        self.staffAbd = lerpF(STAFF_CARRY_ABD, FROST_STAFF_ABD, e);
        self.staffTilt = lerpF(STAFF_CARRY_TILT, FROST_STAFF_TILT, e);
        self.castSh = lerpF(FREE_CARRY_SH, FROST_FREE_SH, e);
        self.castEl = lerpF(FREE_CARRY_EL, FROST_FREE_EL, e);
        self.castAbd = lerpF(FREE_CARRY_ABD, FROST_FREE_ABD, e);
        self.bodyLean = lerpF(6.0, FROST_LEAN, e);
        self.twist = lerpF(0, FROST_TWIST, e);
        self.headPitch = lerpF(4.0, -8.0, e);
    }

    fn setFrostCast(self: *Necro, u: f32) void {
        const e = foe.swingCurve(u);
        self.castSh = lerpF(FROST_FREE_SH, FROST_THROW_SH, e);
        self.castEl = lerpF(FROST_FREE_EL, FROST_THROW_EL, e);
        self.castAbd = lerpF(FROST_FREE_ABD, FROST_THROW_ABD, e);
        self.bodyLean = lerpF(FROST_LEAN, FROST_THROW_LEAN, e);
        self.twist = lerpF(FROST_TWIST, -FROST_TWIST * 0.5, e);
        self.headPitch = lerpF(-8.0, 16.0, e);
    }

    fn setRecover(self: *Necro, u: f32) void {
        const e = mathx.smoothstep(0, 1, u);
        self.staffSh = lerpF(self.staffSh, STAFF_CARRY_SH, e * 0.22);
        self.staffEl = lerpF(self.staffEl, STAFF_CARRY_EL, e * 0.22);
        self.staffAbd = lerpF(self.staffAbd, STAFF_CARRY_ABD, e * 0.22);
        self.staffTilt = lerpF(self.staffTilt, STAFF_CARRY_TILT, e * 0.22);
        self.castSh = lerpF(self.castSh, FREE_CARRY_SH, e * 0.22);
        self.castEl = lerpF(self.castEl, FREE_CARRY_EL, e * 0.22);
        self.castAbd = lerpF(self.castAbd, FREE_CARRY_ABD, e * 0.22);
        self.bodyLean = lerpF(self.bodyLean, 6.0, e * 0.22);
        self.twist = lerpF(self.twist, 0, e * 0.22);
        self.headPitch = lerpF(self.headPitch, 4.0, e * 0.22);
        self.headYaw = lerpF(self.headYaw, 0, e * 0.22);
    }

    fn easeNeutral(self: *Necro, dt: f32) void {
        self.setCarry(dt * 1.4);
    }

    fn tickHem(self: *Necro, dt: f32, speed: f32) void {
        const want = HEM_DRAG * mathx.clampF(speed / (heromod.WALK_SPEED_BANK * SPEED), 0, 1);
        const accel = (want - self.hemLean) * HEM_EASE * HEM_SETTLE;
        self.hemVel += accel * dt;
        self.hemVel *= mathx.maxF(0, 1.0 - HEM_EASE * dt);
        self.hemLean += self.hemVel * dt;
    }

    pub fn hemXf(self: *const Necro) rl.Matrix {
        return self.hemMat;
    }

    fn chainHem(self: *Necro) void {
        const swayLag = HEM_SWAY * mathx.sinf(std.math.tau * self.phase - 0.9) * self.moving;
        self.hemMat = mul(mul(rx(self.hemLean), rz(swayLag)), self.xf[ROOT]);
    }

    fn stunAmount(self: *const Necro) f32 {
        return switch (self.state) {
            .stunlight => foe.stunCurve(self.t, false),
            .stunheavy => foe.stunCurve(self.t, true),
            else => 0,
        };
    }

    pub fn pose(self: *Necro) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = foe.rigSink(foe.SINK_HUMANOID, self.scale, self.fade);
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.45, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        const stun = self.stunAmount();

        const m = self.moving * (1.0 - dk);
        const pel = heromod.pelvisChannels(self.phase, m, self.fwdB, self.latB, A_PROT);
        const bob = pel.bob;
        const sway = pel.sway;
        const prot = pel.prot;
        const dip = pel.dip;

        var wx: [N]rl.Matrix = undefined;
        const collapse = lerpF(hipY, 0.20 * H, dk);
        const pitchBody = 18.0 * dk;
        const pelvY = if (dead) collapse else hipY + bob - dip + self.hop / mathx.maxF(self.scale, 1e-3);
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(9.0 * dk), rx(pitchBody), ry(prot)),
            mul(tr(sway * fs, pelvY * fs + sink, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));

        if (!dead) {
            heromod.legChain(&wx, &self.rest, self.pos.y, self.phase, m, 0, self.fwdB, self.latB, 1.0, HIPL, KNEEL, solePatches[0]);
            heromod.legChain(&wx, &self.rest, self.pos.y, self.phase + 0.5, m, 0, self.fwdB, self.latB, -1.0, HIPR, KNEER, solePatches[1]);
        }
        self.poseUpper(&wx, dk, stun, dead, prot);
        self.xf = wx;
        self.chainHem();
    }

    fn poseUpper(self: *Necro, wx: *[N]rl.Matrix, dk: f32, stun: f32, dead: bool, prot: f32) void {
        const rest = self.rest;
        const twoPi = std.math.tau;
        const m = self.moving * (1.0 - dk);
        const wonk = (self.seed - 0.5) * 5.0;
        const idleAmt = (1.0 - mathx.clampF(self.moving * 2.0, 0, 1)) * (1.0 - dk);
        const swayArg = self.elapsed * (0.42 + 0.20 * (0.5 + 0.5 * mathx.sinf(self.seed * 27.3))) + self.seed * 6.28;
        const swy = mathx.sinf(swayArg) * idleAmt;
        const swyLag = mathx.sinf(swayArg - 0.9) * idleAmt;

        const nod = 1.6 * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const lean = self.bodyLean - 20.0 * stun + 24.0 * dk;
        setLocal(wx, SPINE, rest, mul3(
            rx(lean * 0.45 + nod + 0.7 * swy),
            ry(-0.35 * prot + self.twist * 0.4),
            rz(wonk * 0.5 + 1.0 * swy),
        ));
        setLocal(wx, CHEST, rest, mul3(
            rx(lean * 0.55 + nod * 0.6 + 0.5 * swyLag),
            ry(-0.5 * prot + self.twist * 0.6),
            rz(-wonk * 0.3 - 0.7 * swyLag),
        ));
        setLocal(wx, NECK, rest, rx(self.headPitch * 0.35 + 10.0 * dk - 7.0 * stun));
        setLocal(wx, SKULL, rest, mul3(
            rx(self.headPitch * 0.65 + 18.0 * dk - 28.0 * stun),
            ry(self.headYaw - 0.5 * prot),
            rz(wonk - 1.2 * swyLag - 0.8 * nod),
        ));

        if (dead) heromod.deadLegs(wx, rest, dk);

        const armStun = -66.0 * stun;
        const swing = -11.0 * heromod.armSwing(self.phase) * m * @abs(self.fwdB);
        const fwdHalf = mathx.maxF(0, mathx.sinf(twoPi * self.phase));
        const castSh = self.castSh + swing + armStun - 30.0 * dk + 2.0 * swyLag;
        setLocal(wx, SHL, rest, mul3(rx(-castSh), ry(0), rz(self.castAbd + wonk * 0.4)));
        setLocal(wx, ELL, rest, rx(-self.castEl - 14.0 * fwdHalf * m));
        setLocal(wx, WRL, rest, rz(-5.0));

        const plant = mathx.maxF(0, mathx.sinf(twoPi * self.phase + std.math.pi)) * m;
        const staffSh = self.staffSh - 7.0 * plant + armStun - 26.0 * dk + 1.6 * swy;
        const staffEl = self.staffEl - 5.0 * plant;
        setLocal(wx, SHR, rest, mul3(rx(-staffSh), ry(0), rz(-self.staffAbd - wonk * 0.4)));
        setLocal(wx, ELR, rest, rx(-staffEl));
        setLocal(wx, WRR, rest, rz(4.0));
        // WHERE THE STAFF POINTS IS AUTHORED IN THE WORLD, NOT IN THE WRIST (`hero.shieldFit`'s law): the fit
        // BILLS THE ARM for its own flexion, so `staffTilt` means degrees the head leads FORWARD OF PLUMB in the
        // world. The arm's own rx down this chain is `-(staffSh + staffEl)`, and the sign was measured: added instead, the pole read out at 93 degrees, flat like a lance.
        setLocal(wx, STAFF, rest, staffFit(self.staffTilt - staffSh - staffEl));
    }

    pub fn draw(self: *const Necro, model: *const Model) void {
        model.draw(self);
    }

    /// The unlit pass — the sigil, the gather at the free hand, and the particles. Drawn here rather than in the mesh for the leechfly's reason: vertex alpha is a FIXED emissive channel and cannot brighten.
    pub fn drawFx(self: *const Necro) void {
        self.drawSigil();
        self.drawGather();
        foe.drawParticles(&self.parts);
    }

    /// **THE RING SAYS HOW LONG IS LEFT IN ITS OWN PICTURE.** The rim sits at the full radius from the first frame, so what is drawn is exactly the ground that is about to go — a ring that grew to its reach would promise safety at a rim it had not got to yet.
    fn drawSigil(self: *const Necro) void {
        const r = FROST_R * self.scale;
        const at = self.sigil.at;
        const y = at.y + MARK_LIFT;
        const grain = RUNE_GRAIN * self.scale;
        if (self.sigil.live()) {
            const f = self.sigil.fill();
            ringOfGrains(v3(at.x, y, at.z), r, grain * GRAIN_RIM, mathx.withAlpha(RIME, 215), RING_DOTS);
            ringOfGrains(v3(at.x, y, at.z), r * RING_INNER, grain * GRAIN_IN, mathx.withAlpha(RIME, mathx.u8f(150.0 + 85.0 * f)), RING_DOTS_IN);
            ringOfGrains(v3(at.x, y, at.z), r * RING_EYE, grain * GRAIN_EYE, mathx.withAlpha(RIME_LT, mathx.u8f(140.0 + 100.0 * f)), RING_DOTS_EYE);
            const march = f * @as(f32, @floatFromInt(RUNE_N));
            const lit = @floor(march);
            var i: i32 = 0;
            while (i < RUNE_N) : (i += 1) {
                const a = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(RUNE_N)) * std.math.tau;
                const fi = @as(f32, @floatFromInt(i));
                const heat: f32 = if (fi < lit) 1.0 else if (fi < lit + 1.0) march - lit else 0.0;
                const col = if (heat > 0.02) RIME_LT else RIME;
                const alpha: f32 = if (heat > 0.02) 170.0 + 85.0 * heat else 150.0;
                runeAt(v3(at.x, y + RUNE_LIFT, at.z), a, r * RUNE_R, grain * (1.0 + 0.5 * heat), mathx.withAlpha(col, mathx.u8f(alpha)));
            }
            return;
        }
        // …AND THE BURST'S OWN RING RIDES ITS OWN DECAY, never a clock beside it (the knight's landing).
        const age = self.sigil.blew;
        if (age >= FROST_BURST_RING) return;
        const u = age / FROST_BURST_RING;
        const fade = (1.0 - u) * (1.0 - u);
        ringOfGrains(v3(at.x, y, at.z), r * (1.0 + 0.52 * u), grain * (GRAIN_RIM + 0.6 * u), mathx.withAlpha(RIME_LT, mathx.u8f(255.0 * fade)), RING_DOTS);
        ringOfGrains(v3(at.x, y, at.z), r * (RING_INNER + 0.78 * u), grain * (GRAIN_IN + 0.5 * u), mathx.withAlpha(RIME_LT, mathx.u8f(235.0 * fade)), RING_DOTS_IN);
        var i: i32 = 0;
        while (i < RUNE_N) : (i += 1) {
            const a = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(RUNE_N)) * std.math.tau;
            runeAt(v3(at.x, y + RUNE_LIFT, at.z), a, r * RUNE_R * (1.0 + 0.44 * u), grain * (1.5 - 0.6 * u), mathx.withAlpha(RIME_LT, mathx.u8f(255.0 * fade)));
        }
    }

    pub fn sigilLight(self: *const Necro) ?gfx.Light {
        const r = FROST_R * self.scale;
        const at = v3(self.sigil.at.x, self.sigil.at.y + SIGIL_LIT_Y, self.sigil.at.z);
        if (self.sigil.live()) {
            const f = self.sigil.fill();
            return .{
                .pos = at,
                .col = mathx.scaleV(SIGIL_LIT, SIGIL_LIT_LOW + (SIGIL_LIT_HIGH - SIGIL_LIT_LOW) * f),
                .radius = r * SIGIL_LIT_R,
            };
        }
        const age = self.sigil.blew;
        if (age >= SIGIL_LIT_BURST) return null;
        const u = 1.0 - age / SIGIL_LIT_BURST;
        return .{
            .pos = at,
            .col = mathx.scaleV(SIGIL_LIT, SIGIL_LIT_FLASH * u * u),
            .radius = r * SIGIL_LIT_R * (1.0 + 0.45 * (1.0 - u)),
        };
    }

    fn drawGather(self: *const Necro) void {
        const at = self.castPoint();
        switch (self.state) {
            .raise_wind, .raise_up => {
                const f = if (self.state == .raise_up) 1.0 else mathx.smoothstep(0.15, 1.0, self.t / RAISE_WIND);
                rl.drawSphereEx(at, 0.085 * self.scale * (0.4 + 0.6 * f), 7, 9, mathx.withAlpha(RAISE_GLOW, mathx.u8f(210.0 * f)));
            },
            .frost_wind, .frost_cast => {
                const f = if (self.state == .frost_cast) 1.0 else mathx.smoothstep(0.1, 1.0, self.t / FROST_WIND);
                rl.drawSphereEx(at, 0.075 * self.scale * (0.4 + 0.6 * f), 7, 9, mathx.withAlpha(RIME_LT, mathx.u8f(220.0 * f)));
            },
            else => {},
        }
    }

    pub fn castPoint(self: *const Necro) rl.Vector3 {
        return foe.markOn(self.xf[WRL], v3(0, FIST_Y, FIST_Z));
    }
    /// …and THE STAFF, as the segment it occupies — ferrule to head, measured off the mesh's own constants (the ogre's `clubLowWorld` law). Nothing about where the pole is may be guessed from a yaw.
    pub fn staffSeg(self: *const Necro) [2]rl.Vector3 {
        return .{
            foe.markOn(self.xf[STAFF], v3(0, FIST_Y - STAFF_DOWN, FIST_Z)),
            foe.markOn(self.xf[STAFF], v3(0, FIST_Y + STAFF_UP, FIST_Z)),
        };
    }


    fn gather(self: *Necro, dt: f32, u: f32) void {
        const emitRate = (10.0 + 26.0 * u);
        const at = self.castPoint();
        var owed = foe.emitDue(&self.fxAccum, dt, emitRate);
        while (owed > 0) : (owed -= 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.35, 1.0) * 0.55 * self.scale;
            const p = v3(at.x + mathx.cosf(a) * rr, at.y + self.fxRng.range(-0.2, 0.5) * self.scale, at.z + mathx.sinf(a) * rr);
            const life = self.fxRng.range(0.20, 0.34);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = p,
                .v = mathx.scaleV(mathx.subV(at, p), 1.0 / life),
                .life = life,
                .r0 = self.fxRng.range(0.020, 0.042) * self.scale,
                .r1 = 0.004,
                .col = RAISE_GLOW,
                .stretch = 0.030,
                .add = true,
            });
        }
    }

    fn bloom(self: *Necro, at: rl.Vector3, n: u32) void {
        const from = self.fxHead;
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.2, 1.0) * 1.15;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(at.x + mathx.cosf(a) * rr, at.y + self.fxRng.range(1.0, 2.2), at.z + mathx.sinf(a) * rr),
                .v = v3(mathx.cosf(a) * -0.5, -self.fxRng.range(1.6, 3.2), mathx.sinf(a) * -0.5),
                .life = self.fxRng.range(0.42, 0.78),
                .r0 = self.fxRng.range(0.05, 0.10),
                .r1 = 0.006,
                .col = RAISE_GLOW,
                .grav = -1.4,
                .stretch = 0.030,
                .add = true,
            });
        }
        foe.floorBurst(&self.parts, from, self.fxHead, at.y);
    }

    fn mark(self: *Necro, n: u32) void {
        const from = self.fxHead;
        const at = self.sigil.at;
        const r = FROST_R * self.scale;
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.1, 1.0) * r;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(at.x + mathx.cosf(a) * rr, at.y + 0.05, at.z + mathx.sinf(a) * rr),
                .v = v3(mathx.cosf(a) * 0.7, self.fxRng.range(0.3, 0.9), mathx.sinf(a) * 0.7),
                .life = self.fxRng.range(0.30, 0.60),
                .r0 = self.fxRng.range(0.03, 0.06) * self.scale,
                .r1 = 0.008,
                .col = FROST_MOTE,
                .col1 = FROST_COOL,
                .grav = 1.4,
                .stretch = 0.020,
                .add = true,
            });
        }
        foe.floorBurst(&self.parts, from, self.fxHead, at.y);
    }

    fn creep(self: *Necro, dt: f32) void {
        const emitRate = CREEP_RATE;
        var owed = foe.emitDue(&self.sigAccum, dt, emitRate);
        while (owed > 0) : (owed -= 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.80, 1.04) * FROST_R * self.scale;
            const from = self.fxHead;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(self.sigil.at.x + mathx.cosf(a) * rr, self.sigil.at.y + 0.04, self.sigil.at.z + mathx.sinf(a) * rr),
                .v = v3(0, self.fxRng.range(0.55, 1.30), 0),
                .life = self.fxRng.range(0.55, CREEP_LIFE_HI),
                .r0 = self.fxRng.range(0.028, 0.055) * self.scale,
                .r1 = 0.010,
                .col = FROST_MOTE,
                .col1 = FROST_COOL,
                .grav = 0.5,
                .add = true,
            });
            foe.floorBurst(&self.parts, from, self.fxHead, self.sigil.at.y);
        }
    }

    fn burst(self: *Necro) void {
        const from = self.fxHead;
        const at = self.sigil.at;
        const r = FROST_R * self.scale;
        sfx.world(.shade_touch, at);
        var i: u32 = 0;
        while (i < FROST_SHARDS) : (i += 1) {
            const a = self.fxRng.angle();
            const wall = i % 3 != 0;
            const rr = if (wall) self.fxRng.range(0.86, 1.06) * r else self.fxRng.range(0.0, 0.85) * r;
            const s = self.fxRng.range(0.7, 1.0) * 6.2;
            const out: f32 = if (wall) 0.30 else 0.62;
            // Ice erupting is SLIVERS, not snowballs — the stretch is what makes the wall read as shards.
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(at.x + mathx.cosf(a) * rr, at.y + MARK_LIFT, at.z + mathx.sinf(a) * rr),
                .v = v3(mathx.cosf(a) * s * out, self.fxRng.range(4.2, 8.4), mathx.sinf(a) * s * out),
                .life = self.fxRng.range(0.46, 0.82),
                .r0 = self.fxRng.range(0.07, 0.15) * self.scale,
                .r1 = 0.016,
                .col = FROST_SHARD,
                .col1 = FROST_COOL,
                .grav = 5.4,
                .stretch = 0.040,
                .bounce = 0.30,
                .add = true,
            });
        }
        foe.floorBurst(&self.parts, from, self.fxHead, at.y);
    }

    fn chips(self: *Necro, at: rl.Vector3, dir: rl.Vector3, n: u32, spd: f32) void {
        foe.spray(&self.parts, &self.fxHead, &self.fxRng, at, dir, @intCast(n), spd, self.scale, CHIP_SPRAY);
    }

    /// The hem sweeping the ground rather than a boot striking it — barefoot bone under a metre of wet cloth, so the footfall is a DRAG. At or under the fight's floor (the audio law).
    fn footfalls(self: *Necro) void {
        const ph = self.phase;
        const crossed = @floor(ph * 2.0) != @floor(self.prevPhase * 2.0);
        self.prevPhase = ph;
        if (!crossed or self.moving < 0.25) return;
        sfx.world(.step_soft, self.pos);
        const f = self.fdir();
        var i: u32 = 0;
        while (i < 4) : (i += 1) {
            const a = self.fxRng.angle();
            const B = comptime foe.Blast.of(foe.DUST_DRAG, 0.30, 0.55);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(self.pos.x + self.fxRng.signed() * 0.26 * self.scale, self.pos.y + 0.03, self.pos.z + self.fxRng.signed() * 0.26 * self.scale),
                .v = v3((-f.x * 0.5 + mathx.cosf(a) * 0.35) * B.boost, self.fxRng.range(0.15, 0.5) * B.boost, (-f.z * 0.5 + mathx.sinf(a) * 0.35) * B.boost),
                .life = B.life(&self.fxRng),
                .r0 = self.fxRng.range(0.05, 0.10) * self.scale,
                .r1 = 0.22 * self.scale,
                .col = DUST,
                .col1 = foe.DUST_THIN,
                .grav = foe.DUST_GRAV,
                .drag = foe.DUST_DRAG,
            });
        }
    }
};

fn approach(cur: f32, want: f32, e: f32) f32 {
    return lerpF(cur, want, mathx.clampF(e, 0, 1));
}

// **BUILT OUT OF `drawSphereEx` AND NOTHING ELSE.** Do not replace it with line or strip geometry: `rl.drawLine3D`
// is one pixel however close you stand, and a `drawTriangleStrip3D` annulus came back INVISIBLE beside particles
// on the same spot. **THE FUSE BURNS ROUND THE RING RATHER THAN FILLING IT** — runes lighting one by one are a
// countdown you can COUNT from any bearing. **MEASURED:** 157 `drawSphereEx` calls at 4x6, ~7.5k CPU-transformed triangles a frame per live sigil, ~23k for three casters.
const RUNE_N: i32 = 14;
const RUNE_R: f32 = 0.89;
const RING_INNER: f32 = 0.78;
/// A small rosette at dead centre. Six grains, and it answers the one question the rim cannot: which way is OUT — stood on the mark you cannot see the whole rim at once, but you can always see the middle.
const RING_EYE: f32 = 0.18;
const RING_DOTS: i32 = 46;
const RING_DOTS_IN: i32 = @intFromFloat(@as(f32, @floatFromInt(RING_DOTS)) * RING_INNER);
const RING_DOTS_EYE: i32 = 6;
const GRAIN_RIM: f32 = 0.72;
const GRAIN_IN: f32 = 0.58;
const GRAIN_EYE: f32 = 0.55;
const MARK_LIFT: f32 = 0.06;
const RUNE_LIFT: f32 = 0.008;
const RUNE_GRAIN: f32 = 0.078;
const FROST_BURST_RING: f32 = 0.46;

const SIGIL_LIT = mathx.colVec(rgba(48, 138, 242, 255));
const SIGIL_LIT_LOW: f32 = 0.45;
const SIGIL_LIT_HIGH: f32 = 1.55;
const SIGIL_LIT_FLASH: f32 = 4.60;
const SIGIL_LIT_BURST: f32 = 0.40;
const SIGIL_LIT_R: f32 = 1.60;
const SIGIL_LIT_Y: f32 = 0.55;

fn runeAt(at: rl.Vector3, ang: f32, r: f32, size: f32, col: rl.Color) void {
    const ca = mathx.cosf(ang);
    const sa = mathx.sinf(ang);
    var i: i32 = -1;
    while (i <= 1) : (i += 1) {
        const rr = r + @as(f32, @floatFromInt(i)) * size * 0.9;
        rl.drawSphereEx(v3(at.x + ca * rr, at.y, at.z + sa * rr), size * 0.5, 4, 6, col);
    }
    for ([_]f32{ -1.0, 1.0 }) |s| {
        rl.drawSphereEx(
            v3(at.x + ca * r - sa * s * size * 0.95, at.y, at.z + sa * r + ca * s * size * 0.95),
            size * 0.42,
            4,
            6,
            col,
        );
    }
}

fn ringOfGrains(at: rl.Vector3, r: f32, size: f32, col: rl.Color, n: i32) void {
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const a = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n)) * std.math.tau;
        rl.drawSphereEx(v3(at.x + mathx.cosf(a) * r, at.y, at.z + mathx.sinf(a) * r), size, 4, 6, col);
    }
}

// Sign is POSITIVE-IS-FORWARD on both shoulders — `poseUpper` negates on the way in, exactly as the warriors' does, because authored the obvious way round the arms hang behind him.

const STAFF_CARRY_SH = -14.0;
const STAFF_CARRY_EL = -26.0;
const STAFF_CARRY_ABD = 9.0;
const STAFF_CARRY_TILT = 172.0;

const FREE_CARRY_SH = -6.0;
const FREE_CARRY_EL = -22.0;
const FREE_CARRY_ABD = 7.0;

const RAISE_STAFF_SH = 26.0;
const RAISE_STAFF_EL = -12.0;
const RAISE_STAFF_ABD = 8.0;
/// **THE TRUNK IS NOT BILLED BY THE FIT, ONLY THE ARM IS — so a pose that arches the spine pays for it here.** `RAISE_LEAN` takes the chest back 22 degrees and the staff inherits every one of them, so the same 180-is-plumb number that stands the pole up at the carry laid it out at nearly 50 degrees.
const RAISE_STAFF_TILT = 150.0;
const RAISE_FREE_SH = -128.0;
const RAISE_FREE_EL = -58.0;
const RAISE_FREE_ABD = 34.0;
const RAISE_LEAN = -22.0;
const RAISE_TWIST = -26.0;
const RAISE_HEAD = 26.0;
const RAISE_HEAD_YAW = -14.0;
const RAISE_THROW_SH = 74.0;
const RAISE_THROW_EL = -10.0;
const RAISE_THROW_ABD = -8.0;
const RAISE_THROW_LEAN = 30.0;

const FROST_STAFF_SH = -74.0;
const FROST_STAFF_EL = -34.0;
const FROST_STAFF_ABD = 16.0;
const FROST_STAFF_TILT = 138.0;
const FROST_FREE_SH = -86.0;
const FROST_FREE_EL = -66.0;
const FROST_FREE_ABD = 26.0;
const FROST_LEAN = -14.0;
const FROST_TWIST = -18.0;
const FROST_THROW_SH = 58.0;
const FROST_THROW_EL = -8.0;
const FROST_THROW_ABD = -6.0;
const FROST_THROW_LEAN = 24.0;


const staffFit = heromod.staffFit;

// **BOTH ENDS ARE SOLVED AGAINST THE BODY, not chosen.** The fist rides at `rest[WRR].y` = 0.485·H, which on this rig is 1.17 m off the ground: the ferrule is the drop that puts it ON the ground (0.30·H left it floating half a metre up) and the head is the rise that puts it just over the helm.
const STAFF_UP = 0.65 * H; // fist → the head, landing ~2.74 m: a hand over the crown
const STAFF_DOWN = 0.46 * H; // …and down past the fist to the ferrule, landing ~0.06 m: on the ground
const STAFF_SEGS = 7;
const STAFF_CURL = 0.055;

fn staffMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4409);
    const fz = FIST_Z;

    b.setMat(.bark);
    const total = STAFF_UP + STAFF_DOWN;
    const seg = total / @as(f32, @floatFromInt(STAFF_SEGS));
    var prev = v3(0, FIST_Y - STAFF_DOWN, fz);
    var lean: f32 = -STAFF_CURL * @as(f32, @floatFromInt(STAFF_SEGS)) * 0.5;
    var i: i32 = 0;
    while (i < STAFF_SEGS) : (i += 1) {
        lean += STAFF_CURL;
        const wob = rng.range(-0.010, 0.010) * H;
        const next = v3(
            prev.x + mathx.sinf(lean) * seg * 0.42 + wob,
            prev.y + seg,
            prev.z + mathx.cosf(lean * 0.7) * seg * 0.10 + wob * 0.5,
        );
        const ra = (0.0150 - 0.0008 * @as(f32, @floatFromInt(i))) * H * rng.range(0.93, 1.09);
        const rb = (0.0142 - 0.0008 * @as(f32, @floatFromInt(i))) * H * rng.range(0.93, 1.09);
        b.addCapsule(prev, next, ra, rb, 7, if (rng.float() < 0.34) propart.BARK_DK else propart.BARK_OLD);
        if (rng.float() < 0.42) {
            const a = rng.angle();
            const out = rng.range(0.030, 0.062) * H;
            const elb = v3(next.x + mathx.cosf(a) * out * 0.6, next.y + rng.range(0.004, 0.020) * H, next.z + mathx.sinf(a) * out * 0.6);
            b.addCapsule(next, elb, 0.0075 * H, 0.0062 * H, 6, propart.BARK_DK);
            b.addCapsule(elb, v3(elb.x + mathx.cosf(a) * out * 0.5, elb.y - rng.range(0.014, 0.034) * H, elb.z + mathx.sinf(a) * out * 0.5), 0.0062 * H, 0.0058 * H, 6, propart.TIMBER);
        }
        prev = next;
    }
    b.addBlob(v3(prev.x, prev.y + 0.010 * H, prev.z), v3(0.030 * H, 0.040 * H, 0.028 * H), 4, 9, propart.TIMBER);
    b.setMat(.marble);
    b.addBlob(v3(prev.x + 0.004 * H, prev.y + 0.030 * H, prev.z), v3(0.016 * H, 0.024 * H, 0.014 * H), 3, 8, RIME_ALB);
    b.addBlob(v3(prev.x - 0.008 * H, prev.y + 0.016 * H, prev.z + 0.006 * H), v3(0.009 * H, 0.013 * H, 0.008 * H), 3, 7, RIME_ALB_LT);
    b.setMat(.steel);
    const foot = v3(0, FIST_Y - STAFF_DOWN, fz);
    b.addCapsule(foot, v3(foot.x, foot.y + 0.030 * H, foot.z), 0.0150 * H, 0.0165 * H, 7, rgba(44, 42, 40, 255));
    return b.toMesh();
}

fn chestMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(9111);
    b.setMat(.cloth);
    b.addBlob(v3(0, -0.012 * H, 0), v3(0.072 * H, 0.082 * H, 0.056 * H), 4, 10, ROBE);
    b.addBlob(v3(0, 0.048 * H, 0), v3(0.082 * H, 0.052 * H, 0.060 * H), 4, 10, ROBE_LT);
    // **THE YOKE, and without it the arms hang in mid-air.** `restHumanoid` puts the shoulder joints at ±0.117·H while this chest is 0.072·H across, so there is 0.045·H of daylight either side of a sleeve 0.023·H thick. The ONE place this creature may carry width.
    const shx = SHOULDER_HALF * H;
    const shy = (0.818 - 0.760) * H;
    b.addCapsule(v3(-shx, shy, 0), v3(shx, shy, 0), 0.030 * H, 0.030 * H, 8, ROBE);
    skirt(&b, v3(0, 0.062 * H, 0), 0.058 * H, 0.082 * H, 0.082 * H, 9, ROBE_DK, &rng);
    b.addCapsule(v3(-0.088 * H, 0.052 * H, -0.014 * H), v3(-0.070 * H, -0.088 * H, -0.040 * H), 0.030 * H, 0.038 * H, 8, ROBE_DK);
    return b.toMesh();
}

fn abdomenMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addBlob(v3(0, -0.004 * H, 0), v3(0.070 * H, 0.086 * H, 0.058 * H), 4, 10, ROBE);
    b.addBlob(v3(0, 0.048 * H, 0), v3(0.074 * H, 0.056 * H, 0.060 * H), 4, 9, ROBE);
    b.setMat(.leather);
    b.addCapsule(v3(-0.080 * H, -0.020 * H, 0), v3(0.080 * H, -0.024 * H, 0), 0.011 * H, 0.011 * H, 7, CORD);
    b.addCapsule(v3(0.052 * H, -0.026 * H, 0.050 * H), v3(0.062 * H, -0.120 * H, 0.054 * H), 0.008 * H, 0.006 * H, 6, CORD);
    b.addCapsule(v3(0.038 * H, -0.026 * H, 0.052 * H), v3(0.030 * H, -0.078 * H, 0.058 * H), 0.007 * H, 0.005 * H, 6, CORD);
    return b.toMesh();
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addBlob(v3(0, 0.010 * H, 0), v3(0.064 * H, 0.070 * H, 0.054 * H), 4, 10, ROBE);
    return b.toMesh();
}

fn hemMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(7717);
    b.setMat(.cloth);
    // From the hip down past the feet. `-0.030·H` is BELOW the sole plane on purpose: that is the drag, and a hem stopping at the ankle is a dress.
    const top = 0.010 * H;
    const bot = -0.030 * H - REST[ROOT].y;
    const hip = -0.20 * REST[ROOT].y;
    const knee = -0.55 * REST[ROOT].y;
    skirt(&b, v3(0, top, 0), 0.060 * H, top - hip, 0.066 * H, 10, HEM, &rng);
    skirt(&b, v3(0, hip, 0), 0.066 * H, hip - knee, 0.080 * H, 11, HEM, &rng);
    skirt(&b, v3(0, knee, 0), 0.080 * H, knee - bot, 0.116 * H, 13, HEM, &rng);
    b.addBox(
        v3(-0.018 * H, (knee + bot) * 0.5, -0.112 * H),
        v3(0.086 * H, 0, 0.010 * H),
        v3(0, (knee - bot) * 0.5, 0.026 * H),
        v3(0, 0, 0.042 * H),
        HEM,
    );
    b.setMat(.marble);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const a = rng.angle();
        const rr = 0.112 * H;
        b.addBlob(
            v3(mathx.cosf(a) * rr, bot + rng.range(0.004, 0.040) * H, mathx.sinf(a) * rr),
            v3(rng.range(0.010, 0.022) * H, rng.range(0.006, 0.016) * H, rng.range(0.008, 0.018) * H),
            3,
            7,
            if (rng.float() < 0.4) RIME_ALB_LT else RIME_ALB,
        );
    }
    return b.toMesh();
}

/// **THE ONE SKIRT IN THE GAME** (`gfx.Builder.addSkirt`) — the fishman shaman's robe is the same garment, and
/// a second copy of the panel maths is a second place for the half-axis rule to be got wrong.
fn skirt(b: *Builder, c: rl.Vector3, rTop: f32, drop: f32, rBot: f32, sides: i32, col: rl.Color, rng: *mathx.Rng) void {
    b.addSkirt(c, rTop, drop, rBot, 0.008 * H, sides, col, rng);
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const y = @as(f32, @floatFromInt(i)) * 0.014 * H;
        b.addBlob(v3(0, y, -0.002 * H), v3(0.014 * H, 0.008 * H, 0.014 * H), 3, 7, if (@mod(i, 2) == 0) BONE else BONE_DK);
    }
    return b.toMesh();
}

/// **THE BONE HELM.** The eye sockets are left as HOLES, and a hole is the one place a hard value break is free (the wanderer's `HOOD_IN` law): it cannot blow out, and the contrast is the whole read of a face.
fn helmMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(5153);
    b.setMat(.plain);
    b.addBlob(v3(0, 0.014 * H, 0.002 * H), v3(0.046 * H, 0.052 * H, 0.052 * H), 5, 11, BONE_DK);
    b.addBlob(v3(0.002 * H, 0.026 * H, 0), v3(0.050 * H, 0.046 * H, 0.054 * H), 5, 11, BONE);
    b.addCapsule(
        v3(-0.042 * H, 0.014 * H, 0.036 * H),
        v3(0.042 * H, 0.016 * H, 0.036 * H),
        0.013 * H,
        0.012 * H,
        8,
        BONE_LT,
    );
    b.addCapsule(v3(0.001 * H, 0.012 * H, 0.044 * H), v3(-0.001 * H, -0.026 * H, 0.040 * H), 0.008 * H, 0.010 * H, 7, BONE_LT);
    for ([_]f32{ -1.0, 1.0 }) |s| {
        const drop = rng.range(0.052, 0.070) * H;
        b.addCapsule(
            v3(s * 0.040 * H, 0.006 * H, 0.020 * H),
            v3(s * 0.036 * H, -drop, 0.024 * H),
            0.014 * H,
            0.011 * H,
            7,
            if (s > 0) BONE else BONE_DK,
        );
    }
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const z = 0.030 * H - @as(f32, @floatFromInt(i)) * 0.016 * H;
        const up = rng.range(0.014, 0.030) * H;
        b.addCapsule(
            v3(rng.signed() * 0.003 * H, 0.062 * H, z),
            v3(rng.signed() * 0.006 * H, 0.062 * H + up, z - 0.006 * H),
            0.009 * H,
            0.0075 * H,
            6,
            if (rng.float() < 0.5) BONE_LT else BONE,
        );
    }
    b.setMat(.plain);
    for ([_]f32{ -1.0, 1.0 }) |s| {
        b.addBlob(
            v3(s * 0.020 * H, -0.002 * H, 0.038 * H),
            v3(0.012 * H, 0.010 * H, 0.008 * H),
            3,
            8,
            rgba(7, 8, 10, 255),
        );
    }
    return b.toMesh();
}

fn thighMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCylinder(v3(0, 0, 0), v3(0, -heromod.SEG_THIGH * H, 0), 0.044 * H, 0.036 * H, 9, ROBE_DK);
    b.addDome(v3(0, 0, 0), v3(0, 1, 0), 0.044 * H, 9, ROBE_DK);
    return b.toMesh();
}

fn shankMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCylinder(v3(0, 0, 0), v3(0, -0.090 * H, 0), 0.034 * H, 0.028 * H, 9, ROBE_DK);
    b.setMat(.plain);
    b.addCapsule(v3(0, -0.085 * H, 0), v3(0, -heromod.SEG_SHANK * H, 0), 0.017 * H, 0.014 * H, 8, BONE_DK);
    return b.toMesh();
}

/// **THE SLEEVES ARE THE THINNEST THING ON HIM.** At 0.038·H of radius each arm was 0.14 wide against a 0.26 chest, so the pair hung off the shoulders as bolsters.
fn sleeveMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addBlob(v3(0, 0.002 * H, 0), v3(0.024 * H, 0.026 * H, 0.024 * H), 4, 9, ROBE);
    b.addCylinder(v3(0, 0, 0), v3(0, -heromod.SEG_UPARM * H, 0), 0.023 * H, 0.027 * H, 8, ROBE);
    return b.toMesh();
}

fn forearmMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCylinder(v3(0, 0, 0), v3(0, -0.070 * H, 0), 0.027 * H, 0.034 * H, 8, ROBE);
    b.setMat(.plain);
    b.addCapsule(v3(0, -0.062 * H, 0), v3(0, -heromod.SEG_FOREARM * H, 0), 0.012 * H, 0.010 * H, 8, BONE_DK);
    return b.toMesh();
}

fn handMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(2801);
    b.setMat(.plain);
    b.addBlob(v3(0, FIST_Y, FIST_Z), v3(0.019 * H, 0.023 * H, 0.017 * H), 4, 8, BONE);
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const x = (-1.5 + @as(f32, @floatFromInt(i))) * 0.009 * H;
        const len = rng.range(0.030, 0.044) * H;
        const knuckle = v3(x, FIST_Y - 0.016 * H, FIST_Z + 0.012 * H);
        const mid = v3(x + rng.signed() * 0.002 * H, knuckle.y - len * 0.6, knuckle.z + 0.008 * H);
        b.addCapsule(knuckle, mid, 0.0050 * H, 0.0044 * H, 6, if (@mod(i, 2) == 0) BONE else BONE_LT);
        b.addCapsule(mid, v3(mid.x, mid.y - len * 0.4, mid.z - 0.004 * H), 0.0044 * H, 0.0042 * H, 6, BONE_DK);
    }
    b.addCapsule(
        v3(0.016 * H, FIST_Y - 0.006 * H, FIST_Z + 0.004 * H),
        v3(0.026 * H, FIST_Y - 0.026 * H, FIST_Z + 0.014 * H),
        0.0052 * H,
        0.0046 * H,
        6,
        BONE,
    );
    return b.toMesh();
}


const CAP = wf.MAX_PER_KIND;

pub const Rite = struct {
    model: Model,
    band: [CAP]Necro = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Rite {
        return .{ .model = Model.init(shader) };
    }
    pub fn markLights(self: *const Rite, out: []gfx.Light) usize {
        var n: usize = 0;
        for (self.liveConst()) |*x| {
            if (n >= out.len) break;
            if (x.sigilLight()) |l| {
                out[n] = l;
                n += 1;
            }
        }
        return n;
    }

    pub fn live(self: *Rite) []Necro {
        return self.band[0..self.n];
    }
    pub fn liveConst(self: *const Rite) []const Necro {
        return self.band[0..self.n];
    }

    pub fn reset(self: *Rite, m: *const wf.Map) void {
        foe.resetGroup(Necro, &self.band, &self.n, m, .necromancer);
    }
    pub fn setShader(self: *Rite, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn draw(self: *const Rite, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Rite) void {
        for (self.liveConst()) |*k| k.drawFx();
    }
    pub fn pierce(self: *Rite, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Rite) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn totalHits(self: *const Rite) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Rite) u32 {
        return foe.aliveCount(self.liveConst());
    }
    pub fn soulsDropped(self: *const Rite) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn anyLaid(self: *const Rite) bool {
        for (self.liveConst()) |*k| {
            if (k.laid) return true;
        }
        return false;
    }

    pub fn update(self: *Rite, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        var blow: ?foe.Blow = null;
        for (self.live()) |*k| {
            if (k.update(dt, k.threat.aim(hero), bounds, blade)) |h| foe.worseBlow(&blow, h, k.hitFrom, &k.threat);
        }
        return blow;
    }
};


test "TALL AND SKINNY is two dials, and the RATIO is what either of them alone cannot say" {
    const scaffold = heromod.restHumanoid(heromod.HIP_HALF, heromod.SHOULDER_HALF, H);
    try std.testing.expect(SCALE > archermod.SCALE);
    try std.testing.expect(SCALE * H > 2.3);
    // SKINNY: narrower than the shared scaffold at the shoulder AND at the hip. Measured off the rest pose rather than off the constants, and against the SCAFFOLD's own rest.
    try std.testing.expect(REST[SHL].x < scaffold[SHL].x);
    try std.testing.expect(@abs(REST[HIPL].x) < @abs(scaffold[HIPL].x));
    const mySpan = 2.0 * REST[SHL].x * SCALE;
    const archerSpan = 2.0 * scaffold[SHL].x * archermod.SCALE;
    try std.testing.expect(mySpan < archerSpan);
    try std.testing.expect((SCALE * H) / mySpan > (archermod.SCALE * H) / archerSpan);
    try std.testing.expectApproxEqAbs(scaffold[ROOT].y, REST[ROOT].y, 1e-5);
}

test "THE STAFF STANDS UP, ON ITS OWN SIDE, AND ITS FOOT IS ON THE GROUND — measured, not argued" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.4);
    var j: u32 = 0;
    while (j < 30) : (j += 1) _ = k.update(1.0 / 60.0, v3(0, 0, 40), 400, .{});
    const seg = k.staffSeg();
    const foot = seg[0];
    const head = seg[1];
    const crown = k.topWorld().y;
    std.debug.print(
        "\n  necro: crown {d:.2} | staff foot y {d:.2} head y {d:.2} | foot out {d:.2} head out {d:.2} | lean {d:.1} deg\n",
        .{
            crown,
            foot.y,
            head.y,
            mathx.lenXZ(mathx.subV(foot, k.pos)),
            mathx.lenXZ(mathx.subV(head, k.pos)),
            mathx.tiltDeg(foot, head),
        },
    );
    try std.testing.expect(head.y > foot.y);
    // **SHARES OF THE CREATURE, NOT METRE MARKS.** Both of these were the OLD necromancer's proportions written down as absolutes — 0.30 m of ground clearance and 0.90 m of reach.
    try std.testing.expect(foot.y < crown * 0.13);
    try std.testing.expect(mathx.lenXZ(mathx.subV(foot, k.pos)) < crown * 0.36);
    try std.testing.expect(head.y > k.centerWorld().y);
    try std.testing.expect(head.y < crown + 0.20);
    // NEAR PLUMB, and never laid out flat: past about 35 degrees off vertical it stops being carried and
    // starts being pointed.
    const lean = mathx.tiltDeg(foot, head);
    try std.testing.expect(lean < 35.0);
    const side = mathx.headingDir(k.facing);
    const right = mathx.perpXZ(side);
    const footSide = foot.x * right.x + foot.z * right.z;
    const headSide = head.x * right.x + head.z * right.z;
    try std.testing.expect(footSide * headSide > 0);
}

test "…AND IT STAYS A STAFF THROUGH BOTH CASTS — the trunk's own lean is billed, or it becomes a lance" {
    const at = struct {
        fn lean(k: *Necro) f32 {
            const s = k.staffSeg();
            return mathx.tiltDeg(s[0], s[1]);
        }
    }.lean;
    const dt = 1.0 / 60.0;

    // THE RAISE. `RAISE_LEAN` arches the chest back 22 degrees and the pole inherits all of it. Planted, it
    // must still stand.
    var r = Necro.spawn(mathx.zero3, 0, 1.0, 0.4);
    r.debugRaise(v3(2, 0, 2));
    var t: f32 = 0;
    while (t < RAISE_WIND * 0.95) : (t += dt) {
        r.vigil.at = v3(2, 0, 2);
        _ = r.update(dt, v3(0, 0, 9), 400, .{});
    }
    const rSeg = r.staffSeg();
    std.debug.print("  necro raise: staff lean {d:.1} deg, ferrule y {d:.2}\n", .{ at(&r), rSeg[0].y });
    try std.testing.expect(rSeg[1].y > rSeg[0].y);
    try std.testing.expect(at(&r) < 34.0);
    try std.testing.expect(rSeg[0].y < 0.45);

    var f = Necro.spawn(mathx.zero3, 0, 1.0, 0.4);
    f.debugFrost();
    t = 0;
    while (t < FROST_WIND * 0.95) : (t += dt) _ = f.update(dt, v3(0, 0, 9), 400, .{});
    const fSeg = f.staffSeg();
    std.debug.print("  necro frost: staff lean {d:.1} deg, ferrule y {d:.2}\n", .{ at(&f), fSeg[0].y });
    try std.testing.expect(fSeg[1].y > fSeg[0].y);
    try std.testing.expect(fSeg[0].y > rSeg[0].y + 0.30);
}

test "THE HEM REACHES THE GROUND AND PAST IT — that is what dragging means" {
    const bot = -0.030 * H - REST[ROOT].y;
    try std.testing.expect(bot + REST[ROOT].y < heromod.SOLE_Y);
    try std.testing.expect(bot + REST[ROOT].y < REST[ANKL].y);
}

test "THE HEM IS A SPRING: it lags going out, and it OVERSHOOTS its rest coming back" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.3);
    const dt = 1.0 / 60.0;
    k.tickHem(dt, heromod.WALK_SPEED_BANK * SPEED);
    try std.testing.expect(k.hemLean > 0 and k.hemLean < HEM_DRAG * 0.5);
    var t: f32 = 0;
    while (t < 2.0) : (t += dt) k.tickHem(dt, heromod.WALK_SPEED_BANK * SPEED);
    try std.testing.expect(@abs(k.hemLean - HEM_DRAG) < 1.5);
    var least: f32 = 999;
    t = 0;
    while (t < 2.5) : (t += dt) {
        k.tickHem(dt, 0);
        least = mathx.minF(least, k.hemLean);
    }
    try std.testing.expect(least < -0.05);
    try std.testing.expect(@abs(k.hemLean) < 1.0);
}

test "THE RAISE OUTRANKS THE FROST whenever a body is offered, and distance decides the rest" {
    try std.testing.expectEqual(Choice.raise, classify(6.0, true, true, true));
    try std.testing.expectEqual(Choice.raise, classify(16.0, true, true, false));
    try std.testing.expectEqual(Choice.frost, classify(6.0, false, true, true));
    try std.testing.expectEqual(Choice.frost, classify(6.0, true, false, true));
    try std.testing.expectEqual(Choice.keep, classify(FROST_R_MIN - 0.5, false, true, true));
    try std.testing.expectEqual(Choice.keep, classify(FROST_R_MAX + 1.0, false, true, true));
    try std.testing.expectEqual(Choice.keep, classify(9.0, false, false, false));
    try std.testing.expectEqual(Choice.hold, classify(AGGRO_R + 1.0, true, true, true));
}

test "THE SPOT IS COMMITTED: the sigil does not follow him, and it goes off where it was laid" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
    const stood = v3(4, 0, 5);
    k.debugLay(stood);
    try std.testing.expect(k.sigil.live());
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(stood, k.sigil.at), 1e-5);
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    var fired = false;
    var ranAt = mathx.zero3;
    while (t < FROST_FUSE + 0.2) : (t += dt) {
        ranAt = v3(stood.x + 40.0 * t, 0, stood.z);
        _ = k.update(dt, ranAt, 400, .{});
        if (k.heroHit != null) fired = true;
    }
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(stood, k.sigil.at), 1e-5);
    try std.testing.expect(!fired);
}

test "A WALK CLEARS THE RING and standing still does not — the counter is his feet" {
    const dt = 1.0 / 60.0;
    var stay = Necro.spawn(v3(0, 0, 20), 0, 1.0, 0.2);
    const at = v3(0, 0, 0);
    stay.debugLay(at);
    var hit = false;
    var t: f32 = 0;
    while (t < FROST_FUSE + 0.2) : (t += dt) {
        _ = stay.update(dt, at, 400, .{});
        if (stay.heroHit != null) hit = true;
    }
    try std.testing.expect(hit);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(at, stay.hitFrom), 1e-5);

    var walk = Necro.spawn(v3(0, 0, 20), 0, 1.0, 0.2);
    walk.debugLay(at);
    var caught = false;
    t = 0;
    while (t < FROST_FUSE + 0.2) : (t += dt) {
        const he = v3(heromod.WALK_SPEED_BANK * t, 0, 0);
        _ = walk.update(dt, he, 400, .{});
        if (walk.heroHit != null) caught = true;
    }
    try std.testing.expect(!caught);
}

test "THE RING BILLS ITS BLOW ONCE, even from a caster that has left the field" {
    var k = Necro.spawn(v3(0, 0, 12), 0, 1.0, 0.2);
    const at = mathx.zero3;
    k.debugLay(at);
    k.debugKill();
    const dt = 1.0 / 60.0;
    var bills: u32 = 0;
    var t: f32 = 0;
    while (t < DEATH_DUR + DISS_DUR + FROST_FUSE + 1.5) : (t += dt) {
        if (k.update(dt, at, 400, .{}) != null) bills += 1;
    }
    try std.testing.expectEqual(@as(u32, 1), bills);
}

test "THE RAISE'S OPENING IS THE LONG ONE, and it stays long past the frame it landed on" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
    const body = v3(2, 0, 2);
    const hero = v3(0, 0, 9);
    k.debugRaise(body);
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < RAISE_WIND + RAISE_DUR + 0.05) : (t += dt) {
        k.vigil.at = body;
        _ = k.update(dt, hero, 400, .{});
    }
    try std.testing.expectEqual(State.recover, k.state);
    var n: u32 = 0;
    while (n < 20) : (n += 1) {
        k.vigil.at = null;
        _ = k.update(dt, hero, 400, .{});
    }
    try std.testing.expectEqual(State.recover, k.state);
    try std.testing.expect(RAISE_RECOVER > FROST_RECOVER * 1.5);
    t = 0;
    while (t < RAISE_RECOVER) : (t += dt) {
        k.vigil.at = null;
        _ = k.update(dt, hero, 400, .{});
    }
    try std.testing.expect(k.state != State.recover);
}

test "A FUSE LIT IS A ONE-FRAME EDGE — the pad is not struck three times for one cast" {
    var k = Necro.spawn(v3(0, 0, 9), 0, 1.0, 0.2);
    const dt = 1.0 / 60.0;
    k.debugFrost();
    var edges: u32 = 0;
    var t: f32 = 0;
    while (t < FROST_WIND + FROST_CAST_DUR + 0.5) : (t += dt) {
        _ = k.update(dt, mathx.zero3, 400, .{});
        if (k.laid) edges += 1;
    }
    try std.testing.expectEqual(@as(u32, 1), edges);
}

test "THE RING OUTLIVES THE CASTER — killing it after the cast does not un-cast it" {
    var k = Necro.spawn(v3(0, 0, 12), 0, 1.0, 0.2);
    const at = mathx.zero3;
    k.debugLay(at);
    k.debugKill();
    const dt = 1.0 / 60.0;
    var hit = false;
    var t: f32 = 0;
    while (t < DEATH_DUR + DISS_DUR + FROST_FUSE + 0.4) : (t += dt) {
        _ = k.update(dt, at, 400, .{});
        if (k.heroHit != null) hit = true;
    }
    try std.testing.expect(!k.alive());
    try std.testing.expect(hit);
}

test "THE FROST IS THE FIRST COLD IN THE GAME, and it arrives as cold and nothing else" {
    try std.testing.expectApproxEqAbs(@as(f32, 0), FROST_HIT.dmg, 1e-6);
    try std.testing.expect(FROST_HIT.elem.at(.cold) > 0);
    try std.testing.expectApproxEqAbs(FROST_HIT.elem.at(.cold), FROST_HIT.elem.total(), 1e-6);
    var v = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    _ = v.hit(FROST_HIT);
    // **OFF THE BLOW, NOT A LITERAL** — it sits at `RES_CAP`, so its own element costs it exactly the quarter.
    const quarter = FROST_HIT.elem.at(.cold) * (1.0 - combat.RES_CAP / 100.0);
    try std.testing.expectApproxEqAbs(HP_MAX - quarter, v.hp, 0.01);
    var f = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    _ = f.hit(combat.Hit{ .dmg = 10, .elem = combat.elems(.{ .fire = 5 }) });
    try std.testing.expect(f.hp < HP_MAX - 16.0);
}

test "THE RAISE IS THE LONGEST TELL IT HAS, it is PLANTED for all of it, and it reports rather than acts" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
    const body = v3(2, 0, 2);
    const hero = v3(0, 0, 9);
    k.debugRaise(body);
    const dt = 1.0 / 60.0;
    const startedAt = k.pos;
    var t: f32 = 0;
    var raisedOn: f32 = -1;
    while (t < RAISE_WIND + RAISE_DUR + 0.2) : (t += dt) {
        k.vigil.at = body;
        _ = k.update(dt, hero, 400, .{});
        if (k.raised) raisedOn = t;
    }
    try std.testing.expect(raisedOn > RAISE_WIND);
    try std.testing.expect(raisedOn < RAISE_WIND + RAISE_DUR + 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(startedAt, k.pos), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(body, k.raiseAt), 1e-5);
    _ = k.update(dt, hero, 400, .{});
    try std.testing.expect(!k.raised);
}

test "INTERRUPTING THE GATHER SPENDS IT — a staggered necromancer raises nothing" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
    const body = v3(2, 0, 2);
    k.debugRaise(body);
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < RAISE_WIND * 0.8) : (t += dt) {
        k.vigil.at = body;
        _ = k.update(dt, v3(0, 0, 9), 400, .{});
    }
    try std.testing.expect(k.casting());
    k.stagger(true);
    try std.testing.expect(!k.casting());
    var raisedEver = false;
    t = 0;
    while (t < combat.FOE_HEAVY_STUN_DUR + 0.5) : (t += dt) {
        k.vigil.at = body;
        _ = k.update(dt, v3(0, 0, 9), 400, .{});
        if (k.raised) raisedEver = true;
    }
    try std.testing.expect(!raisedEver);
}

test "IT NEVER MELEES, AND IT NEVER CLOSES — it holds the range its ice works at" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
    const dt = 1.0 / 60.0;
    const near = v3(0, 0, 1.2);
    var t: f32 = 0;
    var closest: f32 = 999;
    while (t < 6.0) : (t += dt) {
        _ = k.update(dt, near, 400, .{});
        closest = mathx.minF(closest, mathx.distXZ(k.pos, near));
    }
    try std.testing.expect(mathx.distXZ(k.pos, near) > 1.2);
    try std.testing.expect(k.heroHit == null or k.sigil.blew < 1.0);
}

test "IT IS FRAIL, AND THE PRICE SAYS IT IS THE PRIORITY TARGET" {
    try std.testing.expect(HP_MAX < 92.0);
    try std.testing.expect(POISE_MAX < 15.0);
    try std.testing.expect(SOULS > 280);
    try std.testing.expect(AGGRO_R > archermod.AGGRO_R);
}

test "A CORPSE IS HELD OPEN WITHIN REACH AND NOWHERE ELSE, so walking the fight away is an answer" {
    var k = Necro.spawn(mathx.zero3, 0, 1.0, 0.2);
    try std.testing.expect(!k.vigil.any());
    k.vigil.at = v3(3, 0, 3);
    try std.testing.expect(k.vigil.any());
    k.vigil.at = null;
    try std.testing.expect(!k.vigil.any());
    try std.testing.expect(RAISE_R > FROST_R_MIN);
}
