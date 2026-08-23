const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
const foe = @import("foe.zig");
const behave = @import("behave.zig");
const wf = @import("../world/worldfmt.zig");
const elemfx = @import("../gfx/elemfx.zig");
const archermod = @import("archer.zig");

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

// THE ANCIENT PRIEST (owner's creature, owner's name) — a lanky jackal-headed thing in rotted wrappings with a
// long staff. NO melee at all, and it never wants to be near you.
//
// **TWO ANSWERS AND THEY OWN DIFFERENT GROUND.** Far off it plants the staff and CLAWS A SKITTERER OUT OF BARE
// EARTH; close it breathes a cone of cold and withdraws. The two ranges are disjoint by construction (the
// assert below), so it can never walk to the one place it has no move.
//
// **THE NECROMANCER'S OPPOSITE.** That one is a SCAVENGER and needs a body `game.markVigil` holds open. This
// one needs nothing, so what limits it is a live COUNT (`flock`, stamped from outside) rather than a corpse.

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

/// 2.95 m to the crown of the ears against the hero's 1.8 — half a head over the necromancer, and it is all neck and shin.
pub const SCALE = (H + 1.15) / H;
/// Narrow through the hips and the shoulders both: the whole read is a body too long for its width.
const HIP_HALF = heromod.HIP_HALF * 0.54;
const SHOULDER_HALF = heromod.SHOULDER_HALF * 0.58;
const REST = heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);
const solePatches = archermod.solePatches;

pub const AGGRO_R: f32 = 24.0;
const TURN_RATE: f32 = 3.8;
const WALK_SPEED: f32 = heromod.WALK_SPEED * 1.02;
const BODY_R: f32 = 0.32;
const HURT_R: f32 = 0.44;
const CENTER_F: f32 = 0.58;
pub const SOULS: u32 = 480;

const HP_MAX: f32 = 96.0;
/// **ALMOST NONE** (the necromancer's rule): under the hero's light poke, so anything that lands drops the cast. A creature whose threat is a 1.55 s ritual must be answerable by reaching it.
const POISE_MAX: f32 = 6.0;
const STANCE_MAX: f32 = 30.0;

/// **LINEN, DRY HIDE AND GOLD.** Fire is the worst weakness in the field bar the homunculus; cold is what it BREATHES, so it is capped; the collar and ferrule are metal on a body with no earth under it.
const RESISTS = combat.resists(.{ .fire = -55, .cold = combat.RES_CAP, .lightning = -25, .chaos = 45 });

const DEATH_DUR = archermod.DEATH_DUR;
const DISS_DUR = archermod.DISS_DUR;
const SHOVE_DECAY: f32 = 7.0;
const A_PROT: f32 = 2.4;

const CHIP_SPRAY = archermod.boneChips(1.15);
const CHIP_LIGHT = 11;
const CHIP_HEAVY = 17;
const CHIP_DEATH = 19;

// **THE RAISE.** The staff goes up and comes down through the earth, and what stands up is a bone skitterer at a spot committed on the FIRST frame of the gather.
pub const RAISE_WIND: f32 = 1.55;
const RAISE_CAST: f32 = 0.38;
const RAISE_RECOVER: f32 = 1.05;
const RAISE_CD: f32 = 8.5;
/// How far in front of itself the ground opens, and WHY IT IS NOT AT THE HERO'S FEET: a body arriving inside his guard is a blow with no tell, and the walk from here to him is the rest of the announcement.
const RAISE_OUT: f32 = 3.4;
/// **HOW MANY OF ITS OWN IT WILL KEEP ON THE FIELD**, counted inside `RAISE_KEEP_R` and STAMPED FROM OUTSIDE (`flock`). Without a ceiling one priest left alone for a minute is seven skitterers.
pub const RAISE_KEEP: u32 = 3;
pub const RAISE_KEEP_R: f32 = 26.0;

// **THE CHILLING BREATH.** A cone POURED, not a blast thrown — its area is a thing it aims and holds, and a body walks out of it the way a body walks out of a swing.
pub const BREATH_WIND: f32 = 0.66;
pub const BREATH_DUR: f32 = 0.95;
const BREATH_RECOVER: f32 = 0.85;
const BREATH_CD: f32 = 5.2;
pub const BREATH_REACH: f32 = 6.2;
pub const BREATH_ARC: f32 = 26.0;
/// Cold per second. **BILLED ON AN INTERVAL AND NOT PER FRAME** (`knight.gasDose`'s law): a per-frame bill
/// against a raised shield is `combat.guardStamina`'s FLAT charge sixty times a second, which breaks the guard
/// in a blink and machine-guns the block voice. Four doses over the pour. No poise and no stance either way.
const BREATH_DPS: f32 = 26.0;
pub const BREATH_DOSE_EVERY: f32 = 0.22;
const BREATH_DOSE = combat.Hit{ .elem = combat.elems(.{ .cold = BREATH_DPS * BREATH_DOSE_EVERY }) };

/// Where it wants to stand. **OUTSIDE THE CONE IT ACTUALLY THROWS**, which is `BREATH_REACH * SCALE` = 10.2 m and not the bare 6.2: the near band is the breath's ground and this is the raise's.
const WANT_MIN: f32 = 12.0;
const WANT_MAX: f32 = 19.0;

comptime {
    std.debug.assert(RAISE_WIND >= foe.TELL_MIN and BREATH_WIND >= foe.TELL_MIN);
    std.debug.assert(BREATH_REACH * SCALE < WANT_MIN);
    std.debug.assert(WANT_MAX < AGGRO_R);
    std.debug.assert(RAISE_CD > RAISE_WIND + RAISE_CAST + RAISE_RECOVER);
    std.debug.assert(BREATH_CD > BREATH_WIND + BREATH_DUR + BREATH_RECOVER);
    std.debug.assert(RAISE_WIND > BREATH_WIND * 2.0);
    std.debug.assert(RAISE_OUT > 2.0);
}

/// Sized by ARITHMETIC over the worst FRAME (the necromancer's law): the pour lays `BREATH_RATE` a second at a mean life of ~0.5 s, and that frame can also carry the blow that kills the caster.
const NPART = 140;
const BREATH_RATE: f32 = 48.0;
const RAISE_BLOOM: usize = 26;
comptime {
    // Cold has the LONGEST mote life in `elemfx` by 2x, so the pour's resident count sizes this ring — the whole
    // owed through `pourCount` once. **THROUGH THE FUNCTION AND NOT A FACTOR COPIED OUT OF IT**: as a hand-written
    // 1.25 this mirrored `elemfx.POUR_ROOT_EVERY` in a second file.
    const resident: f32 = @floatFromInt(elemfx.pourCount(
        @as(usize, @intFromFloat(@ceil(BREATH_RATE * elemfx.sig(.cold).lifeHi))),
    ));
    std.debug.assert(@as(f32, NPART) >= resident +
        @as(f32, @floatFromInt(foe.hitParts(CHIP_HEAVY) + foe.hitParts(CHIP_DEATH))) + foe.WOUND_PARTS);
    std.debug.assert(RAISE_BLOOM < NPART / 2);
}

const State = enum { idle, drift, raise_wind, raise_cast, breath_wind, breath_pour, recover, stunlight, stunheavy, dead };

/// Its own type rather than a bool: the recovery reads it through an exhaustive switch, so a third move cannot be added without saying how long its opening is.
const Spent = enum { raise, breath };

const Choice = enum { raise, breath, keep, hold };

/// **THE WHOLE DECISION, AND IT READS FIVE NUMBERS.** Distance, the cone's own reach, two clocks and a count.
/// **`breathR` IS PASSED IN AND NOT READ OFF THE CONSTANT**: the cone lands at `BREATH_REACH * scale`, so a body the map placed at 0.7 would have decided to breathe from a range its breath never reached.
fn classify(dist: f32, breathR: f32, flock: u32, raiseReady: bool, breathReady: bool) Choice {
    if (dist > AGGRO_R) return .hold;
    if (dist <= breathR and breathReady) return .breath;
    if (dist > breathR and raiseReady and flock < RAISE_KEEP) return .raise;
    return .keep;
}

const LINEN = rgba(96, 86, 66, 255);
const LINEN_LT = rgba(124, 112, 88, 255);
const LINEN_DK = rgba(58, 52, 40, 255);
const HIDE = rgba(28, 26, 24, 255);
const HIDE_LT = rgba(44, 40, 36, 255);
/// The collar and the staff's rings. **GOLD IS NOT STEEL WITH A YELLOW ALBEDO** (`gfx.Mat.gilt`).
const GOLD = rgba(150, 116, 44, 255);
const GOLD_DK = rgba(96, 72, 26, 255);
const EYE = rgba(146, 210, 226, 120);
const BONE = archermod.BONE;
const GRAVE_DUST = foe.DUST;

pub const Model = struct {
    bone: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "ancient priest");
        var bone: [N]rl.Mesh = undefined;
        bone[ROOT] = pelvisMesh();
        bone[SPINE] = abdomenMesh();
        bone[CHEST] = chestMesh();
        bone[NECK] = neckMesh();
        bone[SKULL] = jackalMesh();
        bone[HIPL] = thighMesh();
        bone[KNEEL] = shankMesh();
        bone[ANKL] = archermod.footMesh(1.0, 907);
        bone[HIPR] = thighMesh();
        bone[KNEER] = shankMesh();
        bone[ANKR] = archermod.footMesh(-1.0, 911);
        bone[SHL] = upperArmMesh();
        bone[ELL] = forearmMesh();
        bone[WRL] = handMesh();
        bone[SHR] = upperArmMesh();
        bone[ELR] = forearmMesh();
        bone[WRR] = handMesh();
        bone[STAFF] = staffMesh();
        return .{ .bone = bone, .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, p: *const Ancient) void {
        for (0..N) |i| rl.drawMesh(self.bone[i], self.mat, p.xf[i]);
    }
};

/// **EVERY POSTURE CHANNEL IN ONE ROW, SO A MOVE IS A ROW AND NOT SEVEN ASSIGNMENTS.** Degrees. The necromancer has this as six near-identical `setXxx` functions per move.
const Posture = struct {
    staffSh: f32,
    staffEl: f32,
    staffAbd: f32,
    staffTilt: f32,
    freeSh: f32,
    freeEl: f32,
    freeAbd: f32,
    lean: f32,
    twist: f32,
    headPitch: f32,
    headYaw: f32,

    fn lerp(a: Posture, b: Posture, u: f32) Posture {
        var out: Posture = undefined;
        inline for (@typeInfo(Posture).@"struct".fields) |f| {
            @field(out, f.name) = lerpF(@field(a, f.name), @field(b, f.name), u);
        }
        return out;
    }
    fn toward(self: *Posture, b: Posture, e: f32) void {
        inline for (@typeInfo(Posture).@"struct".fields) |f| {
            @field(self, f.name) = approach(@field(self, f.name), @field(b, f.name), e);
        }
    }
};

// Sign is POSITIVE-IS-FORWARD on both shoulders — `poseUpper` negates on the way in (the warriors' rule),
// because authored the obvious way round the arms hang behind it. `staffTilt` is degrees off plumb in the WORLD, and the arm's own flexion is billed back out of it in `poseUpper`.
const CARRY = Posture{
    .staffSh = -12.0, .staffEl = -22.0, .staffAbd = 8.0, .staffTilt = 174.0,
    .freeSh = -5.0,   .freeEl = -18.0,  .freeAbd = 6.0,
    .lean = 5.0,      .twist = 0,       .headPitch = 3.0, .headYaw = 0,
};
/// THE STAFF GOES UP AND THE WHOLE BODY GOES BACK WITH IT — the gather travels away from where it ends (the knight's tell lesson).
const RAISE_UP = Posture{
    .staffSh = 62.0,  .staffEl = -8.0,  .staffAbd = 12.0, .staffTilt = 146.0,
    .freeSh = -96.0,  .freeEl = -52.0,  .freeAbd = 30.0,
    .lean = -20.0,    .twist = -22.0,   .headPitch = 24.0, .headYaw = -12.0,
};
const RAISE_PLANT = Posture{
    .staffSh = -58.0, .staffEl = -30.0, .staffAbd = 4.0,  .staffTilt = 196.0,
    .freeSh = 40.0,   .freeEl = -14.0,  .freeAbd = -6.0,
    .lean = 26.0,     .twist = 8.0,     .headPitch = -18.0, .headYaw = 0,
};
/// The muzzle comes UP and the jaw is drawn back, which is the whole tell: nothing else on the body moves far.
const BREATH_GATHER = Posture{
    .staffSh = -34.0, .staffEl = -46.0, .staffAbd = 20.0, .staffTilt = 158.0,
    .freeSh = -62.0,  .freeEl = -74.0,  .freeAbd = 22.0,
    .lean = -13.0,    .twist = -8.0,    .headPitch = -26.0, .headYaw = 0,
};
/// …and it comes DOWN across the pour, so the cone sweeps the ground rather than the sky.
const BREATH_OUT = Posture{
    .staffSh = -26.0, .staffEl = -40.0, .staffAbd = 16.0, .staffTilt = 164.0,
    .freeSh = -30.0,  .freeEl = -34.0,  .freeAbd = 12.0,
    .lean = 15.0,     .twist = -4.0,    .headPitch = 14.0, .headYaw = 0,
};

/// How far the muzzle stands off the skull joint, and the breath leaves from THERE — measured off the mesh, never a height above the feet (the ogre's club law).
const MUZZLE_OUT: f32 = 0.135 * H;
const MUZZLE_DROP: f32 = 0.030 * H;

const STAFF_UP = 0.72 * H;
const STAFF_DOWN = 0.44 * H;
const FIST_Y = -0.05 * H;
const FIST_Z = 0.02 * H;

pub const Ancient = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},
    routine: behave.Routine = .{},

    facing: f32 = 0,
    scale: f32 = SCALE,
    seed: f32 = 0,
    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    raiseCd: f32 = 0,
    breathCd: f32 = 0,
    /// Seeded at the interval so the frame he enters the cone is the frame it bills.
    breathT: f32 = BREATH_DOSE_EVERY,
    spent: Spent = .breath,

    /// **HOW MANY OF ITS OWN ARE ALREADY UP**, within `RAISE_KEEP_R`, stamped every frame by `game.zig`. A fact about the field, so NO INPUT READING holds by construction.
    flock: u32 = 0,
    /// The ground it committed to on the FIRST frame of the gather — a spot re-derived per frame as he moved would swing 1.55 s of announcement onto somewhere else.
    raiseAt: rl.Vector3 = mathx.zero3,
    /// **A BODY CAME UP THIS FRAME** — a one-frame edge, cleared at the TOP of `update`. The priest cannot do the raising itself: the body is in another group, another array, another type.
    raised: bool = false,
    homing: bool = false,

    pose_: Posture = CARRY,

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
    called: bool = false,
    drewBreath: bool = false,
    yelped: bool = false,

    fade: f32 = 0,
    gone: bool = false,

    parts: [NPART]foe.Particle = [_]foe.Particle{.{}} ** NPART,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Ancient {
        var p = Ancient{
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale * SCALE,
            .seed = seed,
        };
        p.rest = REST;
        p.fxRng = foe.fxStream(seed, 71053.0, 0xA9);
        // Two priests in one camp do not chant in step: the clocks start apart, off the map's own seed.
        p.raiseCd = 0.6 + seed * 1.6;
        p.breathCd = 0.5 + seed * 1.1;
        p.pose();
        return p;
    }

    pub fn kind(_: *const Ancient) wf.FoeKind {
        return .ancient_priest;
    }

    /// **NOT THE SKELETON FAMILY'S 0.95 H** (`archer.CENTER_F`): at a scale of 1.64 that puts the sphere's centre
    /// 2.80 m up and its FLOOR at 2.08 m, over the top of every swing the hero owns. 0.58 H is the trunk — the
    /// cyclops's own choice — and it lands the sphere at 0.99..2.43 m. The BAR still rides `TOP_F` above the crown.
    pub fn centerWorld(self: *const Ancient) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H, self.scale, 0);
    }
    pub fn topWorld(self: *const Ancient) rl.Vector3 {
        return foe.bodyPoint(self.pos, archermod.TOP_F * H, self.scale, 0);
    }
    pub fn lockPoint(self: *const Ancient) rl.Vector3 {
        return foe.markOn(self.xf[SKULL], archermod.LOCK_AT);
    }
    pub fn hurtRadius(self: *const Ancient) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Ancient) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Ancient) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Ancient) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Ancient) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn airborne(_: *const Ancient) bool {
        return false;
    }
    pub fn flashFrac(self: *const Ancient) f32 {
        return foe.flashFrac(self.flash);
    }
    pub fn soulValue(_: *const Ancient) u32 {
        return SOULS;
    }
    pub fn casting(self: *const Ancient) bool {
        return self.state == .raise_wind or self.state == .raise_cast;
    }
    pub fn breathing(self: *const Ancient) bool {
        return self.state == .breath_pour;
    }

    /// The muzzle, in the skull's own frame, so it rides the pose. The whole cone is measured off this and off `facing`, and nothing about it is guessed from a height.
    pub fn muzzleWorld(self: *const Ancient) rl.Vector3 {
        return foe.markOn(self.xf[SKULL], v3(0, MUZZLE_DROP, MUZZLE_OUT));
    }
    pub fn staffSeg(self: *const Ancient) [2]rl.Vector3 {
        return .{
            foe.markOn(self.xf[STAFF], v3(0, FIST_Y - STAFF_DOWN, FIST_Z)),
            foe.markOn(self.xf[STAFF], v3(0, FIST_Y + STAFF_UP, FIST_Z)),
        };
    }

    /// **THE COLD IT OWES THIS FRAME, OR NULL** — billed through the hero's ordinary door. The arc is measured
    /// from the BODY's bearing rather than the muzzle's, because what the player is dodging is the creature's
    /// facing (`foe.inArc`). ONE READER for the reach, so the decision and the blow cannot disagree.
    pub fn breathReach(self: *const Ancient) f32 {
        return BREATH_REACH * self.scale;
    }

    pub fn breathDose(self: *Ancient, dt: f32, hero: rl.Vector3) ?combat.Hit {
        const inIt = self.breathing() and
            foe.inArc(self.pos, self.facing, hero, self.breathReach() + foe.HERO_R, BREATH_ARC);
        if (!inIt) {
            // **SEEDED AT THE INTERVAL, NOT AT ZERO**: the frame he walks into the cone is the frame it bills, and stepping out and back in cannot buy him a free window.
            self.breathT = BREATH_DOSE_EVERY;
            return null;
        }
        self.breathT += dt;
        if (self.breathT < BREATH_DOSE_EVERY) return null;
        self.breathT -= BREATH_DOSE_EVERY;
        return BREATH_DOSE;
    }

    fn fdir(self: *const Ancient) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn faceToward(self: *Ancient, at: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, at, TURN_RATE, dt);
    }

    pub fn navWant(self: *const Ancient, hero: rl.Vector3) ?rl.Vector3 {
        if (self.state != .drift) return null;
        if (self.homing) return self.home;
        if (self.routine.current() != null) return self.routine.walkTo(self.pos, hero);
        return null;
    }

    pub fn update(self: *Ancient, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        self.raised = false;
        self.called = false;
        self.drewBreath = false;
        self.yelped = false;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.justDied = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        self.raiseCd = mathx.maxF(0, self.raiseCd - dt);
        self.breathCd = mathx.maxF(0, self.breathCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, self.home, hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;
        var moveSpeed: f32 = 0;
        const ease = dt * 6.0;

        switch (self.state) {
            .idle => {
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                self.pose_.toward(CARRY, ease);
                if (self.t >= 0.22) self.decide(d);
            },
            .drift => {
                self.pose_.toward(CARRY, ease);
                if (self.homing) {
                    self.faceToward(self.home, dt);
                    const way = self.nav.along(mathx.dirXZ(self.pos, self.home));
                    moveSpeed = WALK_SPEED;
                    const moved = moveSpeed * dt * self.chill.travel();
                    mathx.stepXZ(&self.pos, way, moved, bounds);
                    movedDist = moved;
                    moveYaw = mathx.headingXZ(way);
                    if (mathx.distXZ(self.pos, self.home) <= foe.LEASH_HOME_R) {
                        self.homing = false;
                        self.enter(.idle);
                    }
                } else {
                    const w = self.routine.step(dt, .{ .at = self.pos, .facing = self.facing, .quarry = hero, .quarryR = foe.HERO_R, .nav = self.nav });
                    self.faceToward(w.look orelse hero, dt);
                    if (w.go) |g| {
                        const way = mathx.dirXZ(self.pos, g);
                        if (mathx.lenXZ(way) > 1e-3) {
                            moveSpeed = WALK_SPEED;
                            const moved = moveSpeed * dt * self.chill.travel();
                            mathx.stepXZ(&self.pos, way, moved, bounds);
                            movedDist = moved;
                            moveYaw = mathx.headingXZ(way);
                        }
                    }
                    if (!self.routine.running) self.decide(d);
                }
            },
            .raise_wind => {
                // **IT TURNS TO THE GROUND IT COMMITTED TO, NOT TO HIM** — and that IS the tell.
                self.faceToward(self.raiseAt, dt);
                const u = mathx.clampF(self.t / RAISE_WIND, 0, 1);
                self.pose_ = Posture.lerp(CARRY, RAISE_UP, mathx.smoothstep(0, 0.94, u));
                self.gather(dt, u);
                if (self.t >= RAISE_WIND) self.enter(.raise_cast);
            },
            .raise_cast => {
                const u = mathx.clampF(self.t / RAISE_CAST, 0, 1);
                self.pose_ = Posture.lerp(RAISE_UP, RAISE_PLANT, foe.swingCurve(u));
                if (self.t >= RAISE_CAST) {
                    self.raised = true;
                    self.spent = .raise;
                    self.raiseCd = RAISE_CD;
                    self.bloom(self.raiseAt);
                    self.enter(.recover);
                }
            },
            .breath_wind => {
                self.faceToward(hero, dt);
                const u = mathx.clampF(self.t / BREATH_WIND, 0, 1);
                self.pose_ = Posture.lerp(CARRY, BREATH_GATHER, mathx.smoothstep(0, 0.9, u));
                self.frostGather(dt, u);
                if (self.t >= BREATH_WIND) self.enter(.breath_pour);
            },
            .breath_pour => {
                // IT TRACKS SLOWLY THROUGH THE POUR — a cone is aimed and HELD. A quarter of its turn rate, which is the whole dodge.
                self.faceToward(hero, dt * 0.25);
                const u = mathx.clampF(self.t / BREATH_DUR, 0, 1);
                self.pose_ = Posture.lerp(BREATH_GATHER, BREATH_OUT, mathx.smoothstep(0, 1, u));
                self.breathe(dt);
                if (self.t >= BREATH_DUR) {
                    self.spent = .breath;
                    self.breathCd = BREATH_CD;
                    self.enter(.recover);
                }
            },
            .recover => {
                self.pose_.toward(CARRY, ease * 0.9);
                if (self.t >= self.recoverDur()) self.decide(d);
            },
            .stunlight => {
                self.pose_.toward(CARRY, ease * 1.4);
                if (self.t >= combat.FOE_LIGHT_STUN_DUR) self.enter(.idle);
            },
            .stunheavy => {
                self.pose_.toward(CARRY, ease * 1.4);
                if (self.t >= combat.FOE_HEAVY_STUN_DUR) self.enter(.idle);
            },
            .dead => {
                self.pose_.toward(CARRY, ease);
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, archermod.DISSOLVE);
            },
        }

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        self.pose();
        self.tryHit(blade);
        // NO MELEE AT ALL: the breath is billed through `breathDose` on its own clock. The signature stays the group contract's.
        return null;
    }

    fn recoverDur(self: *const Ancient) f32 {
        return switch (self.spent) {
            .raise => RAISE_RECOVER,
            .breath => BREATH_RECOVER,
        };
    }

    fn enter(self: *Ancient, s: State) void {
        self.state = s;
        self.t = 0;
        switch (s) {
            .raise_wind => {
                const f = self.fdir();
                self.raiseAt = v3(self.pos.x + f.x * RAISE_OUT * self.scale, self.pos.y, self.pos.z + f.z * RAISE_OUT * self.scale);
                self.called = true;
            },
            .breath_wind => self.drewBreath = true,
            else => {},
        }
    }
    fn enterStun(self: *Ancient, s: State) void {
        self.state = s;
        self.t = 0;
        self.homing = false;
        self.routine.stop();
    }
    fn enterDeath(self: *Ancient) void {
        if (self.state == .dead) return;
        self.enterStun(.dead);
        self.justDied = true;
    }

    fn decide(self: *Ancient, dist: f32) void {
        if (self.leash.goingHome()) {
            self.homing = true;
            self.routine.stop();
            return self.enter(.drift);
        }
        self.homing = false;
        switch (classify(dist, self.breathReach(), self.flock, self.raiseCd <= 0, self.breathCd <= 0)) {
            .raise => self.enter(.raise_wind),
            .breath => self.enter(.breath_wind),
            .keep => {
                // **IT WALKS BACK OUT TO ITS OWN BAND AND NEVER TOWARD HIM** — except from outside the band altogether. The side is a seeded roll at the call site, so two priests in one camp part company.
                const side: f32 = if (self.seed < 0.5) 1.0 else -1.0;
                self.routine.start(if (dist > WANT_MAX) &CLOSE_UP else &WITHDRAW, side);
                self.enter(.drift);
            },
            .hold => {
                if (mathx.distXZ(self.pos, self.home) > foe.LEASH_HOME_R) {
                    self.homing = true;
                    self.enter(.drift);
                } else self.enter(.idle);
            },
        }
    }

    pub fn tryHit(self: *Ancient, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        const heavy = foe.wounded(self, s, blade, .{ .light = 1.6, .heavy = 2.5 });
        self.chips(s.contact, s.dir, if (heavy) CHIP_HEAVY else CHIP_LIGHT, if (heavy) 3.2 else 2.2);
        self.yelped = true;
        switch (s.reaction) {
            .death => {
                self.chips(s.contact, s.dir, CHIP_DEATH, 2.8);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn chips(self: *Ancient, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32) void {
        foe.spray(&self.parts, &self.fxHead, &self.fxRng, at, dir, n, spd, self.scale, CHIP_SPRAY);
    }

    pub fn debugRaise(self: *Ancient) void {
        self.raiseCd = 0;
        self.enter(.raise_wind);
    }
    pub fn debugBreath(self: *Ancient) void {
        self.breathCd = 0;
        self.enter(.breath_wind);
    }
    /// Stages either cast at a fraction of its own gather — the POSTURE and not merely the state, or a staged cell photographs a creature standing at ease. The RAISE carries the harness's shared name (`shots.runMapShots`).
    pub fn stageGather(self: *Ancient, u: f32) void {
        self.enter(.raise_wind);
        const k = mathx.clampF(u, 0, 1);
        self.t = k * RAISE_WIND;
        self.pose_ = Posture.lerp(CARRY, RAISE_UP, mathx.smoothstep(0, 0.94, k));
        self.pose();
    }
    pub fn stageBreath(self: *Ancient, u: f32) void {
        self.enter(.breath_wind);
        const k = mathx.clampF(u, 0, 1);
        self.t = k * BREATH_WIND;
        self.pose_ = Posture.lerp(CARRY, BREATH_GATHER, mathx.smoothstep(0, 0.9, k));
        self.pose();
    }

    pub fn stagger(self: *Ancient, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Ancient) void {
        self.enterDeath();
    }

    /// The staff hand gathers nothing; the GROUND does. So what the player reads is the place rather than the caster.
    fn gather(self: *Ancient, dt: f32, u: f32) void {
        const at = self.raiseAt;
        var owed = foe.emitDue(&self.fxAccum, dt, 8.0 + 26.0 * u);
        while (owed > 0) : (owed -= 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.25, 1.0) * 0.85 * self.scale;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(at.x + mathx.cosf(a) * rr, at.y + 0.02, at.z + mathx.sinf(a) * rr),
                .v = v3(self.fxRng.signed() * 0.25, self.fxRng.range(0.35, 1.20) * (0.4 + u), self.fxRng.signed() * 0.25),
                .life = self.fxRng.range(0.30, 0.62),
                .r0 = self.fxRng.range(0.030, 0.070) * self.scale,
                .r1 = 0.010,
                .col = GRAVE_DUST,
                .col1 = foe.DUST_THIN,
                .grav = foe.DUST_GRAV,
                .drag = foe.DUST_DRAG,
            });
        }
    }

    fn bloom(self: *Ancient, at: rl.Vector3) void {
        elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, v3(at.x, at.y + 0.10, at.z), v3(0, 1, 0), .cold, RAISE_BLOOM, self.scale);
    }

    fn frostGather(self: *Ancient, dt: f32, u: f32) void {
        const at = self.muzzleWorld();
        const owed = foe.emitDue(&self.fxAccum, dt, 10.0 + 22.0 * u);
        if (owed > 0) elemfx.gather(&self.parts, &self.fxHead, &self.fxRng, at, .cold, owed, 0.55, self.scale);
    }

    /// **THE POUR IS THE PICTURE OF THE CONE, SO ITS SPREAD AND ITS REACH ARE THE CONE'S OWN NUMBERS** — a breath drawn narrower than what it bills is a blow arriving out of clear air.
    fn breathe(self: *Ancient, dt: f32) void {
        const owed = foe.emitDue(&self.fxAccum, dt, BREATH_RATE);
        if (owed == 0) return;
        const from = self.muzzleWorld();
        var aim = self.fdir();
        aim.y = -0.22; // …and it goes DOWNHILL: cold falls (`elemfx`'s signature), and a cone aimed level misses his legs
        elemfx.pour(
            &self.parts,
            &self.fxHead,
            &self.fxRng,
            from,
            mathx.normV(aim),
            .cold,
            owed,
            mathx.radians(BREATH_ARC),
            self.breathReach(),
            self.scale,
        );
    }

    pub fn drawFx(self: *const Ancient) void {
        foe.drawParticles(&self.parts);
    }

    pub fn draw(self: *const Ancient, model: *const Model) void {
        if (self.gone) return;
        model.draw(self);
    }

    fn stunAmount(self: *const Ancient) f32 {
        return switch (self.state) {
            .stunlight => foe.stunCurve(self.t, false),
            .stunheavy => foe.stunCurve(self.t, true),
            else => 0,
        };
    }

    pub fn pose(self: *Ancient) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = -0.55 * self.scale * self.fade;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.45, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        const stun = self.stunAmount();
        const m = self.moving * (1.0 - dk);
        const pel = heromod.pelvisChannels(self.phase, m, self.fwdB, self.latB, A_PROT);

        var wx: [N]rl.Matrix = undefined;
        const collapse = lerpF(hipY, 0.20 * H, dk);
        const pelvY = if (dead) collapse else hipY + pel.bob - pel.dip;
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(8.0 * dk), rx(17.0 * dk), ry(pel.prot)),
            mul(tr(pel.sway * fs, pelvY * fs + sink, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));
        if (!dead) {
            heromod.legChain(&wx, &self.rest, self.phase, m, 0, self.fwdB, self.latB, 1.0, HIPL, KNEEL, solePatches[0]);
            heromod.legChain(&wx, &self.rest, self.phase + 0.5, m, 0, self.fwdB, self.latB, -1.0, HIPR, KNEER, solePatches[1]);
        }
        self.poseUpper(&wx, dk, stun, dead, pel.prot);
        self.xf = wx;
    }

    fn poseUpper(self: *Ancient, wx: *[N]rl.Matrix, dk: f32, stun: f32, dead: bool, prot: f32) void {
        const rest = self.rest;
        const twoPi = std.math.tau;
        const m = self.moving * (1.0 - dk);
        const p = self.pose_;
        // ITS OWN LEAN, off its own seed — no two of them stand the same way (wabi-sabi BETWEEN the instances).
        const wonk = (self.seed - 0.5) * 6.0;
        const idleAmt = (1.0 - mathx.clampF(self.moving * 2.0, 0, 1)) * (1.0 - dk);
        const swayArg = self.elapsed * (0.36 + 0.18 * (0.5 + 0.5 * mathx.sinf(self.seed * 21.7))) + self.seed * 6.28;
        const swy = mathx.sinf(swayArg) * idleAmt;
        const swyLag = mathx.sinf(swayArg - 0.9) * idleAmt;
        const nod = 1.5 * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const lean = p.lean - 18.0 * stun + 22.0 * dk;

        setLocal(wx, SPINE, rest, mul3(rx(lean * 0.45 + nod + 0.7 * swy), ry(-0.35 * prot + p.twist * 0.4), rz(wonk * 0.5 + swy)));
        setLocal(wx, CHEST, rest, mul3(rx(lean * 0.55 + nod * 0.6 + 0.5 * swyLag), ry(-0.5 * prot + p.twist * 0.6), rz(-wonk * 0.3 - 0.7 * swyLag)));
        // THE NECK CARRIES MOST OF THE HEAD PITCH on this body, not the skull: it is a long neck, and a muzzle that swung on the joint alone read as a nodding dog.
        setLocal(wx, NECK, rest, rx(p.headPitch * 0.55 + 9.0 * dk - 7.0 * stun));
        setLocal(wx, SKULL, rest, mul3(rx(p.headPitch * 0.45 + 16.0 * dk - 26.0 * stun), ry(p.headYaw - 0.5 * prot), rz(wonk - 1.2 * swyLag)));

        if (dead) heromod.deadLegs(wx, rest, dk);

        const armStun = -62.0 * stun;
        const swing = -9.0 * heromod.armSwing(self.phase) * m * @abs(self.fwdB);
        const fwdHalf = mathx.maxF(0, mathx.sinf(twoPi * self.phase));
        const freeSh = p.freeSh + swing + armStun - 28.0 * dk + 2.0 * swyLag;
        setLocal(wx, SHL, rest, mul3(rx(-freeSh), ry(0), rz(p.freeAbd + wonk * 0.4)));
        setLocal(wx, ELL, rest, rx(-p.freeEl - 12.0 * fwdHalf * m));
        setLocal(wx, WRL, rest, rz(-5.0));

        const plant = mathx.maxF(0, mathx.sinf(twoPi * self.phase + std.math.pi)) * m;
        const staffSh = p.staffSh - 6.0 * plant + armStun - 24.0 * dk + 1.5 * swy;
        const staffEl = p.staffEl - 4.0 * plant;
        setLocal(wx, SHR, rest, mul3(rx(-staffSh), ry(0), rz(-p.staffAbd - wonk * 0.4)));
        setLocal(wx, ELR, rest, rx(-staffEl));
        setLocal(wx, WRR, rest, rz(4.0));
        // The fit BILLS THE ARM for its own flexion, so `staffTilt` means degrees the head leads FORWARD of plumb in the WORLD (`hero.shieldFit`'s law).
        setLocal(wx, STAFF, rest, heromod.staffFit(p.staffTilt - staffSh - staffEl));
    }
};

/// **THE TWO SCRIPTS ARE ITS OWN BAND, NOT THE ARCHER'S.** `behave.KITE` opens to 9 m, inside the cone this
/// creature throws. Both are written off `WANT_MIN`/`WANT_MAX` and both stop a `BAND_SLACK` short of the edge they walk to, or the next `decide` sends it straight back out.
const BAND_SLACK: f32 = 1.5;
const WITHDRAW = [_]behave.Step{
    .{ .open = .{ .to = WANT_MIN + BAND_SLACK } },
    .{ .dwell = .{ .secs = 0.5 } },
};
const CLOSE_UP = [_]behave.Step{
    .{ .close = .{ .to = WANT_MAX - BAND_SLACK } },
    .{ .dwell = .{ .secs = 0.4 } },
};

const CAP_N = wf.MAX_PER_KIND;

pub const Crypt = struct {
    model: Model,
    band: [CAP_N]Ancient = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Crypt {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Crypt) []Ancient {
        return self.band[0..self.n];
    }
    pub fn liveConst(self: *const Crypt) []const Ancient {
        return self.band[0..self.n];
    }
    pub fn reset(self: *Crypt, m: *const wf.Map) void {
        foe.resetGroup(Ancient, &self.band, &self.n, m, .ancient_priest);
    }
    pub fn clear(self: *Crypt) void {
        self.n = 0;
    }
    pub fn setShader(self: *Crypt, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn update(self: *Crypt, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    /// **THE COLD ON ITS OWN CLOCK, WORST FIRST** — its own channel and not the group's blow, billed at `BREATH_DOSE_EVERY` rather than per frame.
    pub fn breathDose(self: *Crypt, dt: f32, hero: rl.Vector3) ?foe.Blow {
        var worst: ?foe.Blow = null;
        for (self.live()) |*p| {
            if (!foe.corporeal(p)) continue;
            if (p.breathDose(dt, hero)) |h| foe.worseBlow(&worst, h, p.pos, &p.threat);
        }
        return worst;
    }
    pub fn draw(self: *const Crypt, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Crypt) void {
        for (self.liveConst()) |*p| p.drawFx();
    }
    pub fn pierce(self: *Crypt, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Crypt) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Crypt) u32 {
        return foe.soulsEach(self.liveConst());
    }
    pub fn totalHits(self: *const Crypt) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Crypt) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

// Wrappings over a frame with nothing in between: every mass is a capsule or a blob, and the only boxes are the gold. The linen is banded BETWEEN the limbs rather than along one, so the two arms read as two ages of cloth.

fn wrapBand(b: *Builder, rng: *mathx.Rng, a: rl.Vector3, to: rl.Vector3, r: f32, n: u32, col: rl.Color) void {
    const off = mathx.subV(to, a);
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const u = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(n)) + rng.signed() * 0.05;
        const c = v3(a.x + off.x * u, a.y + off.y * u, a.z + off.z * u);
        b.addBlob(c, v3(r * rng.range(1.02, 1.13), r * rng.range(0.20, 0.34), r * rng.range(1.02, 1.13)), 5, 7, col);
    }
    if (rng.float() < 0.7) {
        const u = rng.range(0.35, 0.85);
        const c = v3(a.x + off.x * u, a.y + off.y * u, a.z + off.z * u);
        b.addCapsule(c, v3(c.x + rng.signed() * r * 1.4, c.y - r * rng.range(1.6, 3.0), c.z + rng.signed() * r * 1.2), r * 0.30, r * 0.12, 5, LINEN_DK);
    }
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xA901);
    b.setMat(.cloth);
    b.addBlob(v3(0, 0.012 * H, 0), v3(0.072 * H, 0.056 * H, 0.052 * H), 6, 9, LINEN);
    b.addBlob(v3(0, -0.030 * H, 0.004 * H), v3(0.062 * H, 0.040 * H, 0.046 * H), 5, 8, LINEN_DK);
    wrapBand(&b, &rng, v3(0, -0.045 * H, 0), v3(0, 0.030 * H, 0), 0.070 * H, 3, LINEN_LT);
    return b.toMesh();
}

fn abdomenMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xA902);
    b.setMat(.cloth);
    // **NARROW AND HOLLOW.** The waist is thinner than the pelvis above and below it, which is the whole of "lanky": a trunk graded straight from hip to shoulder reads as a man in a robe.
    b.addCapsule(v3(0, -0.010 * H, 0), v3(0, 0.075 * H, 0), 0.050 * H, 0.058 * H, 9, LINEN);
    b.addBlob(v3(0, 0.030 * H, -0.014 * H), v3(0.044 * H, 0.048 * H, 0.030 * H), 5, 8, LINEN_DK);
    wrapBand(&b, &rng, v3(0, -0.010 * H, 0), v3(0, 0.075 * H, 0), 0.054 * H, 4, LINEN_LT);
    return b.toMesh();
}

fn chestMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xA903);
    b.setMat(.cloth);
    b.addCapsule(v3(0, -0.006 * H, 0), v3(0, 0.062 * H, 0), 0.062 * H, 0.070 * H, 10, LINEN);
    b.addBlob(v3(0, 0.030 * H, 0.020 * H), v3(0.058 * H, 0.040 * H, 0.034 * H), 5, 8, LINEN_LT);
    // Sunk most of the way in, a few percent proud. Relief is subtle.
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        const y = 0.006 * H + 0.016 * H * @as(f32, @floatFromInt(i));
        b.addCapsule(v3(-0.048 * H, y, 0.026 * H), v3(0.048 * H, y + 0.004 * H * rng.signed(), 0.026 * H), 0.0055 * H, 0.0055 * H, 5, LINEN_DK);
    }
    // THE COLLAR — gold, and the one square-edged thing on the body. Its own material row (`Mat.gilt`).
    b.setMat(.gilt);
    var k: u32 = 0;
    while (k < 9) : (k += 1) {
        const a = std.math.pi * (-0.5 + @as(f32, @floatFromInt(k)) / 8.0) + rng.signed() * 0.05;
        const rr = 0.068 * H * rng.range(0.94, 1.08);
        const drop = 0.062 * H - 0.012 * H * @abs(@as(f32, @floatFromInt(k)) - 4.0) * 0.5;
        b.addBox(
            v3(mathx.sinf(a) * rr, drop, mathx.cosf(a) * rr * 0.7),
            v3(0.014 * H, 0, 0),
            v3(0, 0.020 * H * rng.range(0.85, 1.2), 0),
            v3(0, 0, 0.004 * H),
            if (k % 2 == 0) GOLD else GOLD_DK,
        );
    }
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCapsule(v3(0, -0.004 * H, 0), v3(0, 0.062 * H, 0.004 * H), 0.026 * H, 0.024 * H, 8, HIDE);
    b.addBlob(v3(0, 0.020 * H, 0), v3(0.030 * H, 0.018 * H, 0.028 * H), 4, 7, LINEN_DK);
    return b.toMesh();
}

/// THE JACKAL HEAD. The EARS are what carries it at range, so they are the biggest thing on the head.
fn jackalMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xA905);
    b.setMat(.hide);
    b.addBlob(v3(0, 0.008 * H, -0.004 * H), v3(0.032 * H, 0.034 * H, 0.040 * H), 6, 9, HIDE);
    b.addBlob(v3(0, -0.004 * H, 0.030 * H), v3(0.024 * H, 0.022 * H, 0.030 * H), 5, 8, HIDE_LT);
    // A long capsule that does NOT end in a point — a blunt nose pad closes it.
    b.addCapsule(v3(0, MUZZLE_DROP * 0.4, 0.030 * H), v3(0, MUZZLE_DROP, MUZZLE_OUT), 0.020 * H, 0.013 * H, 8, HIDE);
    b.addBlob(v3(0, MUZZLE_DROP, MUZZLE_OUT), v3(0.013 * H, 0.011 * H, 0.010 * H), 4, 7, rgba(16, 15, 14, 255));
    // The jaw hangs a little open at rest — a shut muzzle on a dead face reads as a mask.
    b.addCapsule(v3(0, MUZZLE_DROP * 0.3 - 0.012 * H, 0.030 * H), v3(0, MUZZLE_DROP - 0.016 * H, MUZZLE_OUT * 0.92), 0.013 * H, 0.008 * H, 6, HIDE_LT);
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const u = 0.30 + 0.16 * @as(f32, @floatFromInt(i));
        b.addBlob(
            v3(0.010 * H, MUZZLE_DROP * 0.5 - 0.008 * H, MUZZLE_OUT * u),
            v3(0.0035 * H, 0.006 * H * rng.range(0.7, 1.3), 0.0035 * H),
            3,
            5,
            BONE,
        );
        b.addBlob(
            v3(-0.010 * H, MUZZLE_DROP * 0.5 - 0.008 * H, MUZZLE_OUT * u),
            v3(0.0035 * H, 0.006 * H * rng.range(0.7, 1.3), 0.0035 * H),
            3,
            5,
            BONE,
        );
    }
    // Tall, back-swept, and NOT a matched pair: one stands a fifth taller and leans out further.
    inline for (.{ 1.0, -1.0 }, .{ 1.0, 0.82 }) |side, tall| {
        const base = v3(side * 0.022 * H, 0.032 * H, -0.010 * H);
        const tip = v3(side * (0.034 * H + 0.010 * H * tall), 0.032 * H + 0.098 * H * tall, -0.030 * H);
        b.addCapsule(base, tip, 0.014 * H, 0.005 * H, 6, HIDE);
        b.addBlob(mathx.lerpV(base, tip, 0.55), v3(0.016 * H, 0.030 * H * tall, 0.005 * H), 4, 7, HIDE_LT);
        b.addBlob(tip, v3(0.006 * H, 0.007 * H, 0.006 * H), 3, 5, HIDE);
    }
    b.addBlob(v3(0.024 * H, 0.014 * H, 0.020 * H), v3(0.008 * H, 0.007 * H, 0.006 * H), 3, 6, EYE);
    b.addBlob(v3(-0.024 * H, 0.014 * H, 0.020 * H), v3(0.008 * H, 0.007 * H, 0.006 * H), 3, 6, EYE);
    return b.toMesh();
}

fn thighMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xA906);
    b.setMat(.cloth);
    const len = heromod.SEG_THIGH * H;
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), 0.028 * H, 0.023 * H, 8, LINEN);
    wrapBand(&b, &rng, v3(0, 0, 0), v3(0, -len, 0), 0.028 * H, 3, LINEN_DK);
    return b.toMesh();
}

fn shankMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xA907);
    b.setMat(.cloth);
    const len = heromod.SEG_SHANK * H;
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), 0.023 * H, 0.015 * H, 8, HIDE);
    wrapBand(&b, &rng, v3(0, -len * 0.15, 0), v3(0, -len * 0.9, 0), 0.023 * H, 4, LINEN);
    return b.toMesh();
}

fn upperArmMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xA908);
    b.setMat(.cloth);
    const len = heromod.SEG_UPARM * H;
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), 0.021 * H, 0.017 * H, 7, LINEN);
    wrapBand(&b, &rng, v3(0, 0, 0), v3(0, -len, 0), 0.021 * H, 3, LINEN_LT);
    return b.toMesh();
}

fn forearmMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xA909);
    b.setMat(.cloth);
    const len = heromod.SEG_FOREARM * H;
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), 0.017 * H, 0.013 * H, 7, HIDE);
    wrapBand(&b, &rng, v3(0, 0, 0), v3(0, -len, 0), 0.017 * H, 3, LINEN_DK);
    return b.toMesh();
}

fn handMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xA90A);
    b.setMat(.hide);
    b.addBlob(v3(0, -0.014 * H, 0.004 * H), v3(0.014 * H, 0.020 * H, 0.012 * H), 4, 7, HIDE);
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        const x = (-0.008 * H) + 0.0055 * H * @as(f32, @floatFromInt(i));
        const drop = 0.030 * H * rng.range(0.72, 1.15);
        b.addCapsule(v3(x, -0.024 * H, 0.006 * H), v3(x, -0.024 * H - drop, 0.012 * H), 0.0035 * H, 0.0022 * H, 4, HIDE_LT);
    }
    return b.toMesh();
}

const STAFF_SEGS = 7;

/// Authored pointing UP off the grip; `staffFit` is what turns it into the world.
fn staffMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xA90B);
    b.setMat(.wood);
    const lo = FIST_Y - STAFF_DOWN;
    const hi = FIST_Y + STAFF_UP;
    // A pole in SEGMENTS with a lean on each — a single straight capsule end to end is a broom handle.
    var i: u32 = 0;
    while (i < STAFF_SEGS) : (i += 1) {
        const a = @as(f32, @floatFromInt(i)) / STAFF_SEGS;
        const c = @as(f32, @floatFromInt(i + 1)) / STAFF_SEGS;
        const bow = 0.010 * H;
        b.addCapsule(
            v3(mathx.sinf(a * 2.4) * bow, lerpF(lo, hi, a), FIST_Z + rng.signed() * 0.002 * H),
            v3(mathx.sinf(c * 2.4) * bow, lerpF(lo, hi, c), FIST_Z + rng.signed() * 0.002 * H),
            0.0105 * H,
            0.0098 * H,
            6,
            rgba(52, 42, 32, 255),
        );
    }
    b.setMat(.gilt);
    inline for (.{ 0.22, 0.48, 0.74 }) |u| {
        const y = lerpF(lo, hi, u);
        b.addCapsule(v3(0, y - 0.006 * H, FIST_Z), v3(0, y + 0.006 * H, FIST_Z), 0.0135 * H, 0.0135 * H, 7, GOLD_DK);
    }
    // A gold crescent standing on the pole, and its two horns are NOT the same height.
    const top = hi;
    b.addBlob(v3(0, top - 0.010 * H, FIST_Z), v3(0.020 * H, 0.018 * H, 0.014 * H), 4, 7, GOLD);
    inline for (.{ 1.0, -1.0 }, .{ 1.0, 0.78 }) |side, tall| {
        b.addCapsule(
            v3(side * 0.012 * H, top, FIST_Z),
            v3(side * 0.040 * H, top + 0.070 * H * tall, FIST_Z),
            0.0075 * H,
            0.0030 * H,
            5,
            GOLD,
        );
    }
    return b.toMesh();
}

test "IT IS A FOE WITH NO MELEE — its own tether, its own souls, and `update` never returns a blow" {
    var p = Ancient.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectEqual(wf.FoeKind.ancient_priest, p.kind());
    try std.testing.expectEqual(foe.Nature.undead, foe.traitsOf(p.kind()).nature);
    try std.testing.expect(p.alive() and !p.dying() and !p.staggered());
    try std.testing.expect(p.hurtRadius() > p.bodyR());
    try std.testing.expect(p.topWorld().y > p.centerWorld().y);
    const hero = mathx.ground(0, 1.0);
    p.leash.noteSeen();
    var t: f32 = 0;
    while (t < 6.0) : (t += 1.0 / 60.0) {
        try std.testing.expect(p.update(1.0 / 60.0, hero, 200.0, .{}) == null);
    }
}

test "THE HURT SPHERE IS INSIDE THE HERO'S REACH — a 3 m body centred at its crown is unhittable" {
    const p = Ancient.spawn(mathx.zero3, 0, 1.0, 0.3);
    const c = p.centerWorld().y;
    const r = p.hurtRadius();
    std.debug.print("\n  priest sphere {d:.2}..{d:.2} m (centre {d:.2}, r {d:.2}); the bar rides at {d:.2}\n", .{ c - r, c + r, c, r, p.topWorld().y });
    // His own high swing tops out near his own stature; the sphere's FLOOR has to sit under that.
    try std.testing.expect(c - r < heromod.H);
    try std.testing.expect(c - r > 0.5);
    try std.testing.expect(p.topWorld().y > c + r);
}

test "IT LOOKS DOWN AT HIM — taller than the necromancer, and narrower through the hips" {
    const p = Ancient.spawn(mathx.zero3, 0, 1.0, 0.3);
    const crown = archermod.TOP_F * H * p.scale;
    std.debug.print("\n  ancient priest stands {d:.2} m (hero 1.80), hips {d:.3} m across, shoulders {d:.3} m\n", .{ crown, HIP_HALF * 2.0 * p.scale, SHOULDER_HALF * 2.0 * p.scale });
    try std.testing.expect(crown > 2.6);
    try std.testing.expect(HIP_HALF < heromod.HIP_HALF);
    try std.testing.expect(SHOULDER_HALF < heromod.SHOULDER_HALF);
}

test "WRAPPED LINEN AND GOLD: fire is the worst answer to it and cold is no answer at all" {
    var p = Ancient.spawn(mathx.zero3, 0, 1.0, 0.3);
    const fire = combat.Hit{ .elem = combat.elems(.{ .fire = 20 }) };
    const cold = combat.Hit{ .elem = combat.elems(.{ .cold = 20 }) };
    const levin = combat.Hit{ .elem = combat.elems(.{ .lightning = 20 }) };
    try std.testing.expectApproxEqAbs(@as(f32, 31.0), p.vit.damageFrom(fire), 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), p.vit.damageFrom(cold), 1e-3);
    try std.testing.expect(p.vit.damageFrom(levin) > 20.0);
    // It breathes cold, so cold is the one thing it may not be soft to — capped, not merely resistant.
    try std.testing.expectApproxEqAbs(combat.RES_CAP, p.vit.res.at(.cold), 1e-4);
}

test "THE TWO RANGES ARE DISJOINT — there is no distance at which it has nothing to do" {
    const r = BREATH_REACH * SCALE;
    var d: f32 = 0;
    while (d <= AGGRO_R) : (d += 0.25) {
        const c = classify(d, r, 0, true, true);
        try std.testing.expect(c != .hold);
        if (d <= r) try std.testing.expectEqual(Choice.breath, c) else try std.testing.expectEqual(Choice.raise, c);
    }
    try std.testing.expectEqual(Choice.hold, classify(AGGRO_R + 1.0, r, 0, true, true));
    // …and with the pack already up, the far answer is to keep its distance rather than raise a fourth.
    try std.testing.expectEqual(Choice.keep, classify(14.0, r, RAISE_KEEP, true, true));
    try std.testing.expectEqual(Choice.keep, classify(14.0, r, 0, false, true));
    // **THE BAND IT WANTS IS OUTSIDE THE CONE IT THROWS**, at the scale it is actually drawn at.
    try std.testing.expect(r < WANT_MIN);
}

test "THE RAISE COMMITS TO ONE SPOT AND STARES AT IT — 1.55 s of announcement may not move" {
    var p = Ancient.spawn(mathx.zero3, 0, 1.0, 0.3);
    p.leash.noteSeen();
    p.debugRaise();
    try std.testing.expect(p.called);
    const at = p.raiseAt;
    try std.testing.expect(mathx.distXZ(p.pos, at) > 2.0);
    var t: f32 = 0;
    var away = mathx.ground(14, 0);
    while (t < RAISE_WIND) : (t += 1.0 / 60.0) {
        away = mathx.ground(14 - t * 3.0, t * 4.0);
        _ = p.update(1.0 / 60.0, away, 200.0, .{});
        try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(at, p.raiseAt), 1e-5);
        try std.testing.expect(!p.raised);
    }
    // …and the body comes up exactly once, on the cast's own frame.
    var ups: usize = 0;
    while (t < RAISE_WIND + RAISE_CAST + 0.2) : (t += 1.0 / 60.0) {
        _ = p.update(1.0 / 60.0, away, 200.0, .{});
        if (p.raised) ups += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), ups);
    try std.testing.expect(p.raiseCd > 0);
}

test "THE BREATH IS A CONE HE CAN WALK OUT OF, and it bills as a DRIP" {
    var p = Ancient.spawn(mathx.zero3, 0, 1.0, 0.3);
    p.debugBreath();
    p.state = .breath_pour;
    p.t = 0;
    p.facing = 0; // +Z
    const dt: f32 = 1.0 / 60.0;
    const ahead = mathx.ground(0, 3.0);
    const dose = p.breathDose(dt, ahead) orelse return error.TestUnexpectedResult;
    try std.testing.expectApproxEqAbs(BREATH_DPS * BREATH_DOSE_EVERY, dose.elem.at(.cold), 1e-5);
    // …AND NOT AGAIN UNTIL THE INTERVAL IS UP: sixty flat guard charges a second is a broken shield.
    try std.testing.expect(p.breathDose(dt, ahead) == null);
    var owed: usize = 0;
    var t2: f32 = 0;
    while (t2 < BREATH_DUR) : (t2 += dt) {
        if (p.breathDose(dt, ahead) != null) owed += 1;
    }
    std.debug.print("\n  breath bills {d} doses of {d:.1} cold over a {d:.2} s pour\n", .{ owed, BREATH_DOSE.elem.at(.cold), BREATH_DUR });
    try std.testing.expect(owed >= 3 and owed <= 5);
    // A DRIP: no poise and no stance, or a cone would flinch him every frame he stood in it.
    try std.testing.expectApproxEqAbs(@as(f32, 0), dose.poise, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), dose.stance, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), dose.dmg, 1e-6);
    // Out to the side, past the arc, and beyond the reach: nothing.
    try std.testing.expect(p.breathDose(dt, mathx.ground(3.0, 0.4)) == null);
    try std.testing.expect(p.breathDose(dt, mathx.ground(0, BREATH_REACH * p.scale + 2.0)) == null);
    p.state = .breath_wind;
    try std.testing.expect(p.breathDose(dt, ahead) == null);
}

test "THE WHOLE POUR IS WORTH LESS THAN ONE OF THE SKITTERER'S SLICES" {
    const whole = BREATH_DPS * BREATH_DUR;
    std.debug.print("\n  chilling breath: {d:.0} cold over {d:.2} s in a {d:.0} deg cone {d:.1} m long\n", .{ whole, BREATH_DUR, BREATH_ARC * 2.0, BREATH_REACH * SCALE });
    try std.testing.expect(whole < 30.0);
    // What it sells is the GROUND, not the damage.
    try std.testing.expect(BREATH_REACH * SCALE > 9.0);
}

test "THE MUZZLE IS WHERE THE BREATH LEAVES FROM — off the pose, never off a height" {
    var p = Ancient.spawn(mathx.zero3, 0, 1.0, 0.3);
    const level = p.muzzleWorld();
    p.pose_ = BREATH_GATHER;
    p.pose();
    const raisedUp = p.muzzleWorld();
    std.debug.print("\n  muzzle at {d:.2} m carried, {d:.2} m drawn back (hero's eye 1.25 m)\n", .{ level.y, raisedUp.y });
    try std.testing.expect(raisedUp.y > level.y);
    try std.testing.expect(level.y > 2.0);
    // It is out in FRONT of the skull joint, which is the whole reason it is not a height off the feet.
    try std.testing.expect(mathx.distXZ(p.pos, level) > 0.15);
}

test "A LANDED BLOW DROPS THE RITUAL — poise under the hero's lightest swing" {
    var p = Ancient.spawn(mathx.zero3, 0, 1.0, 0.3);
    p.debugRaise();
    try std.testing.expect(POISE_MAX < heromod.ATK_LIGHT_HIT.poise);
    // At the height its own sphere sits at — measured off the creature, never a literal.
    const y = p.centerWorld().y;
    const swing = foe.Blade{
        .active = true,
        .r = 0.4,
        .a = v3(0, y, -1.0),
        .b = v3(0, y, 1.0),
        .a0 = v3(0, y, -1.0),
        .b0 = v3(0, y, 1.0),
        .hit = heromod.ATK_LIGHT_HIT,
    };
    p.tryHit(swing);
    try std.testing.expectEqual(@as(u32, 1), p.hits);
    try std.testing.expect(p.staggered());
    try std.testing.expect(!p.casting());
}

test "IT NEVER WALKS TOWARD HIM WHILE HE IS INSIDE ITS BAND" {
    var p = Ancient.spawn(mathx.zero3, 0, 1.0, 0.3);
    p.leash.noteSeen();
    p.breathCd = 99.0; // …so the near answer is refused and the retreat is the only one left
    p.raiseCd = 99.0;
    const hero = mathx.ground(0, 3.0);
    const was = mathx.distXZ(p.pos, hero);
    var t: f32 = 0;
    var closest = was;
    while (t < 3.0) : (t += 1.0 / 60.0) {
        _ = p.update(1.0 / 60.0, hero, 200.0, .{});
        closest = mathx.minF(closest, mathx.distXZ(p.pos, hero));
    }
    const now = mathx.distXZ(p.pos, hero);
    std.debug.print("\n  priest stood {d:.2} m off, walked out to {d:.2} m (closest {d:.2} m)\n", .{ was, now, closest });
    try std.testing.expect(now > was + 1.5);
    try std.testing.expect(closest >= was - 0.15);
}

test "TWO PRIESTS IN A CAMP DO NOT CHANT IN STEP" {
    const a = Ancient.spawn(mathx.zero3, 0, 1.0, 0.1);
    const b = Ancient.spawn(mathx.zero3, 0, 1.0, 0.8);
    try std.testing.expect(@abs(a.raiseCd - b.raiseCd) > 0.5);
    try std.testing.expect(@abs(a.breathCd - b.breathCd) > 0.3);
}
