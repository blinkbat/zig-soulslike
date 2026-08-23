const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const heromod = @import("../play/hero.zig");
const archermod = @import("archer.zig");
const wolf = @import("wolf.zig");

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

// THE BONE SKITTERER (owner's creature, owner's name) — a splayed ribcage that walks ON ITS RIBS, with a long
// spine rising to a head that is one big EYE. The RIBS are the legs and the SPINE is the weapon: it CLOSES the
// eye and slams it into you, and the blink is the tell (owner: much cuter and less scary; six ribs, not eight).
// **FAST ON THE GROUND, SLOW IN THE SWING** (owner: really fast, but attack spd moderate) — it crosses ground
// quicker than the spirit wolf's gallop and then spends the longest close wind-up of any small body.

/// KEEL HEIGHT — every fraction in this file is a share of it. Low: a body at the hero's knee.
pub const W: f32 = 0.62;

pub const AGGRO_R: f32 = 15.0;
const HOME_R: f32 = 1.0;

const BODY_R: f32 = 0.42;
/// **THE SPHERE IS THE CAGE, AND THE BLADE IS DELIBERATELY OUTSIDE IT.** Measured: the cage runs 0 to 1.06 W
/// and the spine's base to 1.8 W, while the reared tip stands at 3.5 W — 2.2 m. A sphere big enough to hold the
/// tip is 1.1 m of radius on a body 0.99 m across, so half of every swing would connect with air a metre off it.
/// Centre 0.90 W, radius 1.00 W spans -0.10 W to 1.90 W.
const HURT_R: f32 = 1.00;
const CENTER_F: f32 = 0.90;
const TOP_F: f32 = 3.60;

/// Half the ravager's HP, poise under the hero's LIGHT poke (10), so every single connection interrupts the slice.
const HP_MAX: f32 = 46.0;
const POISE_MAX: f32 = 7.0;
const STANCE_MAX: f32 = 22.0;
/// Dry bone and marrow: nothing to freeze (the skeleton family's own 60-75 cold), nothing to poison, and no wet mass or metal for lightning to find.
const RESISTS = combat.resists(.{ .fire = -55, .cold = 70, .lightning = 0, .chaos = 50 });

const SOULS: u32 = 120;
/// A quarter. The ancient priest can make these all day (`ancientpriest.RAISE_CD`), so full price is a soul farm with a timer on it. What was PLACED on the map pays in full.
const SOULS_RAISED: u32 = 30;

const DEATH_DUR = archermod.DEATH_DUR;
const DISS_DUR = archermod.DISS_DUR;
const DISSOLVE = archermod.DISSOLVE;

const CHIP_SPRAY = archermod.boneChips(0.85);
const CHIP_LIGHT = 8;
const CHIP_HEAVY = 13;
const CHIP_DEATH = 15;
const NPART = 48;
comptime {
    // THE RING LAW, EXECUTABLE (the archer's): a killing heavy blow is both chip sprays and the shared wound on one frame, and the dissolve waits out `DEATH_DUR`.
    std.debug.assert(NPART >= foe.hitParts(CHIP_HEAVY) + foe.hitParts(CHIP_DEATH) + foe.WOUND_PARTS);
}

// **THE SLICE.** One move, straight down a vertical plane out in front of it. `SLICE_WIND` is the longest
// close-range tell any small body in the field carries, and it is what makes a fast creature fair.
const SLICE_WIND: f32 = 0.52;
const SLICE_STRIKE: f32 = 0.16;
const SLICE_RECOVER: f32 = 0.54;
const SLICE_COOL: f32 = 1.30;
/// Where the tip arrives, measured off the posed rig rather than argued (the ogre's club law) — the test prints it. The trigger ring is shorter, so it commits with him already inside.
const SLICE_R: f32 = 1.62;
const SLICE_TRIGGER_R: f32 = 1.35;
/// A share of the trigger ring, not a distance of its own. Under 1, so a creature that has arrived is already committed rather than shuffling on the boundary.
const STOP_FRAC: f32 = 0.72;
/// The head's own thickness for the swept test — a shut eye the size of a fist, not a honed edge.
const TIP_R: f32 = 0.19;
/// The ravager's bite is 24 off 88 HP, this is 20 off 46. Poise past the hero's own light stun so a connection matters, stance under his heavy so it is not a guard-breaker.
const SLICE_HIT = combat.Hit{ .dmg = 20, .poise = 18, .stance = 9 };

comptime {
    std.debug.assert(SLICE_WIND >= foe.TELL_MIN);
    std.debug.assert(SLICE_TRIGGER_R < SLICE_R);
    std.debug.assert(SLICE_COOL > SLICE_STRIKE + SLICE_RECOVER);
}

/// Degrees the spine chain lays BACK across the wind. Huge because the creature is small: at 34 the blade moved less than the hero's own shoulder does walking.
const REAR_BACK: f32 = 62.0;
/// Degrees it drives THROUGH from there. The sum is what the tip sweeps — back over the hips and down past the ground line ahead, which is what makes it a slice and not a jab.
const SLICE_THROUGH: f32 = 158.0;
/// How far back through the recovery the chain is still carrying the follow-through.
const SLICE_SETTLE: f32 = 0.62;

/// **IT CROSSES GROUND FASTER THAN ANYTHING ELSE ON FOOT** — over the spirit wolf's 5.2 m/s gallop, which is
/// the fastest thing the player has seen move. Nothing about it is heavy, so nothing about it is slow.
const RUN_SPEED: f32 = 6.4;
const IDLE_SPEED: f32 = 1.6;
const ACCEL: f32 = 16.0;
const TURN_RATE: f32 = 7.2;
const GAIT_BLEND: f32 = 11.0;

/// **METRES OF GROUND PER FULL WAVE OF THE SIX RIBS** (owner: "their anim is off… they move way too freaky
/// rapidly", and separately: "speed itself is ok"). Phase advances by DISTANCE, so the wave's FREQUENCY is
/// `RUN_SPEED / STRIDE` and nothing else: at 0.52 m that was 12.3 waves a second under a body travelling
/// 6.4 m/s — a vibration, not a gait. At 1.10 m it is 5.8 a second.
///
/// **THE LOWER RIB HAD TO GROW WITH IT.** A tip at radius `R` swept through ±θ covers `2·R·sin θ`, so this
/// stride off the old 0.31 m rib asked for `sin θ = 1.21` — unsatisfiable, and `RIB`'s clamp would have
/// silently delivered a short swing under a long stride. `RIB_KNEE_Y` 0.78 puts the rib at 0.48 m and lands the solve at `sin θ = 0.77`.
const STRIDE: f32 = 1.10;
/// Fraction of the wave each rib is DOWN. Over 0.5 by a wide margin — with six legs and a metachronal wave most are always planted, which is what stops it hopping.
const RIB_DUTY: f32 = 0.68;
/// Fraction of the wave the lag runs from one rib pair to the next. Pairs firing together is a pogo stick and
/// 0.5 is a trot; a third, with the side lag, spreads SIX phases evenly — the alternating-tripod stagger every real hexapod walks on.
const RIB_LAG: f32 = 1.0 / 3.0;
/// …and the two sides half a wave apart, so a plant is never symmetric.
const RIB_SIDE_LAG: f32 = 0.5;

pub const SHOVE = foe.Push{ .light = 1.05, .heavy = 2.40 };
const SHOVE_DECAY: f32 = 8.0;

/// THREE PAIRS, NOT FOUR (owner: less legs) — and it stopped being a spider, which was most of what frightened.
const PAIRS = 3;
const LEGS = PAIRS * 2;
/// Static geometry on the keel, so they cost one mesh and no bones. Few and TUCKED UP: at seven full-drop arcs they read as a second set of legs.
const FALSE_RIBS = 5;

pub const KEEL = 0;
pub const SP0 = 1;
pub const SP1 = 2;
pub const SP2 = 3;
pub const SP3 = 4;
pub const BLADE = 5;
const LEG0 = 6;
pub const N = LEG0 + LEGS * 2;

/// `2 * i` is the rib's upper bone (on the keel) and `2 * i + 1` its lower (the one that plants).
fn ribUp(i: usize) usize {
    return LEG0 + i * 2;
}
fn ribLo(i: usize) usize {
    return LEG0 + i * 2 + 1;
}
/// +1 its left, -1 its right.
fn ribSide(i: usize) f32 {
    return if (i < PAIRS) 1.0 else -1.0;
}
fn ribPair(i: usize) usize {
    return if (i < PAIRS) i else i - PAIRS;
}

// The cage, in shares of `W`. LONGER THAN IT IS TALL with the ribs splayed WIDE — a cage as deep as it is wide reads as a barrel.
const CAGE_Z = [PAIRS]f32{ 0.58, 0.04, -0.54 };
const RIB_ROOT_X: f32 = 0.11;
const RIB_KNEE_X: f32 = 0.64;
/// Raised for the stride (`STRIDE`'s note): a longer lower rib is what lets one swing cover more ground without the tip skating.
const RIB_KNEE_Y: f32 = 0.78;
const RIB_FOOT_X: f32 = 0.80;
/// The rib tips do NOT all reach the same ring — wabi-sabi between the three pairs, never along one rib. Multiplies `RIB_FOOT_X` and the pair's own `CAGE_Z` spread.
const PAIR_REACH = [PAIRS]f32{ 1.06, 0.90, 0.98 };

const SPINE_AT = [5]rl.Vector3{
    v3(0, 1.06, -0.62),
    v3(0, 1.78, -0.78),
    v3(0, 2.48, -0.58),
    v3(0, 2.96, -0.16),
    v3(0, 3.15, 0.38),
};

fn restPose() [N]rl.Vector3 {
    var r: [N]rl.Vector3 = undefined;
    r[KEEL] = v3(0, 1.0, 0);
    inline for (.{ SP0, SP1, SP2, SP3, BLADE }, 0..) |b, i| r[b] = SPINE_AT[i];
    for (0..LEGS) |i| {
        const side = ribSide(i);
        const p = ribPair(i);
        const z = CAGE_Z[p];
        r[ribUp(i)] = v3(side * RIB_ROOT_X, 1.0, z);
        r[ribLo(i)] = v3(side * RIB_KNEE_X * PAIR_REACH[p], RIB_KNEE_Y, z * 1.06);
    }
    for (&r) |*p| p.* = v3(p.x * W, p.y * W, p.z * W);
    return r;
}

/// THE LOWER RIB'S LENGTH, knee to tip, and **DEGREES OF SWING THAT MAKE THE TIP TRAVEL THE STRIDE AND NOT A
/// METRE MORE**: a tip at radius `R` swept through ±θ covers `2·R·sin θ`, so the stance half of a stride asks
/// for `θ = asin(STRIDE·RIB_DUTY / 2R)`. Guessed instead of solved, the feet skate.
///
/// **SOLVED AT COMPTIME, SIX ROWS, ONCE.** As two functions off the rest pose this was six `asin` calls and six
/// materialisations of the whole 18-bone rest array per creature per frame, for six numbers that cannot change.
const RIB = blk: {
    @setEvalBranchQuota(4000);
    const rest = restPose();
    var reach: [LEGS]f32 = undefined;
    var swing: [LEGS]f32 = undefined;
    for (0..LEGS) |i| {
        const lo = rest[ribLo(i)];
        reach[i] = mathx.maxF(mathx.lenV(mathx.subV(lo, v3(lo.x, 0, lo.z))), 0.05);
        const s = mathx.clampF(STRIDE * RIB_DUTY / (2.0 * reach[i]), 0, 0.85);
        swing[i] = mathx.degrees(std.math.asin(s));
    }
    break :blk .{ .reach = reach, .swing = swing };
};

/// How far the tip comes off the earth, in shares of `W`. Big on purpose: a long loping throw with real daylight under it is the difference between goofy and horrible.
const RIB_LIFT: f32 = 0.52;
/// Degrees the rib FOLDS at the knee as it lifts — a leg that swings without folding is a compass arm.
const RIB_FOLD: f32 = 44.0;

const BONE = archermod.BONE;
const BONE_DK = archermod.BONE_DK;
const BONE_LT = archermod.BONE_LT;
/// Alpha is the emissive channel. The one green light in the field, so an open eye reads at fight distance and a shut one reads as gone. Big dark pupil: a small one is a stare.
const EYE_GREEN = rgba(98, 190, 96, 96);
const PUPIL = rgba(14, 18, 12, 255);
/// The slam's wake — the eye's own green, paled.
const EYE_TRAIL = rgba(150, 212, 142, 255);
const MARROW = rgba(58, 46, 38, 255);
const SINEW = rgba(96, 82, 62, 220);

pub const State = enum { idle, move, slice, hurt, dead };

pub const Model = struct {
    mesh: [N]rl.Mesh,
    /// The head with the lid down — swapped in for `mesh[BLADE]` while `eyeShut()`, the frog's two-eye idiom.
    headShut: rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "skitterer");
        return .{ .mesh = buildMeshes(), .headShut = headShutMesh(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, s: *const Skitterer) void {
        const shut = s.eyeShut();
        for (0..N) |i| rl.drawMesh(if (i == BLADE and shut) self.headShut else self.mesh[i], self.mat, s.xf[i]);
    }
};

pub const Skitterer = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},
    parry: foe.Parry = .{},

    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,
    state: State = .idle,
    t: f32 = 0,
    phase: f32 = 0,
    speed: f32 = 0,
    speedS: f32 = 0,
    sliceCool: f32 = 0,
    /// **CLAWED OUT OF THE GROUND RATHER THAN PLACED** — worth less (`SOULS_RAISED`), and the drop table gives the whole kind nothing, because the supply is a priest's cooldown.
    bornRaised: bool = false,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    dealt: bool = false,
    heroHit: ?combat.Hit = null,
    heavyStun: bool = false,
    parried: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    reared: bool = false,
    sliced: bool = false,
    yelped: bool = false,

    fade: f32 = 0,
    gone: bool = false,

    parts: [NPART]foe.Particle = [_]foe.Particle{.{}} ** NPART,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    /// **THE HURT SHAPE IS THE POSED KIT** and never a yaw-guessed sector, so it is read after `pose` (the warrior's `wpnWas`).
    tipWas: [2]rl.Vector3 = .{ mathx.zero3, mathx.zero3 },
    trail: foe.Trail(18) = .{},

    rest: [N]rl.Vector3 = undefined,
    xf: [N]rl.Matrix = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Skitterer {
        var s = Skitterer{
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale,
            .seed = seed,
            .rest = restPose(),
        };
        s.fxRng = foe.fxStream(seed, 44851.0, 0x5C17);
        s.phase = wolf.wrap01(seed * 7.31);
        s.pose();
        s.tipWas = s.tipSeg();
        return s;
    }

    pub fn kind(_: *const Skitterer) wf.FoeKind {
        return .bone_skitterer;
    }

    pub fn centerWorld(self: *const Skitterer) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * W, self.scale, 0);
    }
    /// **THE MARK RIDES THE CAGE, NOT THE BLADE**: the tip travels 158 degrees of arc in 0.16 s, and a reticle on it would be unaimable. Off `KEEL` so it still rides the POSE.
    pub fn lockPoint(self: *const Skitterer) rl.Vector3 {
        return foe.markOn(self.xf[KEEL], v3(0, 0.10 * W, 0));
    }
    pub fn topWorld(self: *const Skitterer) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * W, self.scale, 0);
    }
    pub fn hurtRadius(self: *const Skitterer) f32 {
        return HURT_R * W * self.scale;
    }
    pub fn bodyR(self: *const Skitterer) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Skitterer) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Skitterer) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Skitterer) bool {
        return self.state == .hurt or self.state == .dead;
    }
    pub fn airborne(_: *const Skitterer) bool {
        return false;
    }
    pub fn flashFrac(self: *const Skitterer) f32 {
        return foe.flashFrac(self.flash);
    }
    pub fn soulValue(self: *const Skitterer) u32 {
        return if (self.bornRaised) SOULS_RAISED else SOULS;
    }
    pub fn stature(self: *const Skitterer) f32 {
        return W * self.scale;
    }

    /// The segment through the eye's own mass, which is what gets slammed into you.
    pub fn tipSeg(self: *const Skitterer) [2]rl.Vector3 {
        const base = foe.markOn(self.xf[BLADE], v3(0, EYE_C.y, EYE_C.z - 0.26 * W));
        const tip = foe.markOn(self.xf[BLADE], v3(0, EYE_C.y, EYE_C.z + 0.24 * W));
        return .{ base, tip };
    }

    /// **THE BLINK IS THE TELL** — shut for the whole wind and strike. One predicate, read by the draw, so the picture and the clock cannot disagree.
    pub fn eyeShut(self: *const Skitterer) bool {
        return self.state == .slice and self.t < SLICE_WIND + SLICE_STRIKE;
    }

    /// -1 fully reared back to +1 fully through, zero outside the move, so the same channel poses the settle back to a standing spine. No second timer for either to read.
    pub fn sliceAmt(self: *const Skitterer) f32 {
        if (self.state != .slice) return 0;
        if (self.t < SLICE_WIND) return -mathx.smoothstep(0, SLICE_WIND * 0.88, self.t);
        if (self.t < SLICE_WIND + SLICE_STRIKE) {
            return mathx.lerpF(-1.0, 1.0, foe.swingCurve((self.t - SLICE_WIND) / SLICE_STRIKE));
        }
        return 1.0 - mathx.smoothstep(
            SLICE_WIND + SLICE_STRIKE,
            SLICE_WIND + SLICE_STRIKE + SLICE_RECOVER * SLICE_SETTLE,
            self.t,
        );
    }

    pub fn navWant(self: *const Skitterer, hero: rl.Vector3) ?rl.Vector3 {
        if (self.state != .idle and self.state != .move) return null;
        if (foe.senseHero(&self.leash, self.pos, hero, AGGRO_R) <= AGGRO_R) return hero;
        return if (mathx.distXZ(self.pos, self.home) > HOME_R) self.home else null;
    }

    fn faceToward(self: *Skitterer, at: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, at, TURN_RATE, dt);
    }

    /// SECONDS BACK FROM THE TIP'S ARRIVAL, or null (`foe.PARRY_LEAD`). The impact frame is the middle of the strike window, where the arc crosses the ground line.
    fn toImpact(self: *const Skitterer) ?f32 {
        if (self.state != .slice) return null;
        return SLICE_WIND + SLICE_STRIKE * 0.5 - self.t;
    }

    fn parryable(self: *const Skitterer) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        return foe.hurtReach(SLICE_R, self.scale);
    }

    fn takeParry(self: *Skitterer) void {
        const reach = self.parryable() orelse return;
        if (!foe.caught(self, reach)) return;
        self.sliceCool = SLICE_COOL;
        self.chips(self.tipSeg()[1], mathx.dirXZ(self.pos, self.parry.at), 9, 3.0);
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(true),
            .light, .none => self.enterStun(false),
        }
    }

    pub fn update(self: *Skitterer, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        self.justDied = false;
        self.heroHit = null;
        self.parried = false;
        self.reared = false;
        self.sliced = false;
        self.yelped = false;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.tipWas = self.tipSeg();
        self.stateStep(dt, hero, bounds);
        // Tested AFTER the pose it is measured off exists, and the ribbon is pushed off the same two points.
        if (self.state == .slice and self.t >= SLICE_WIND and self.t < SLICE_WIND + SLICE_STRIKE) {
            // **THE SWING IS HEARD WHETHER OR NOT IT LANDS.** Fired off the hit it was silent on every miss. An
            // EDGE on the clock crossing, so a long frame cannot fire it twice.
            if (self.t - dt < SLICE_WIND) self.sliced = true;
            const seg = self.tipSeg();
            self.trail.push(seg[0], seg[1], self.tipWas[1], 0.25);
            self.tryReach(hero);
        }
        self.trail.age(dt);
        self.takeParry();
        self.tryHit(blade);
        return self.heroHit;
    }

    fn stateStep(self: *Skitterer, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);

        self.t += dt;
        self.vit.tick(dt);
        foe.fadeFlash(&self.flash, dt);
        self.sliceCool = mathx.maxF(0, self.sliceCool - dt);
        foe.tickLeash(&self.leash, dt, self.pos, self.home, hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        if (self.state == .dead) {
            foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            self.speed = 0;
            self.settle(dt);
            return self.pose();
        }
        if (self.state == .hurt) {
            if (self.t >= combat.foeStunDur(self.heavyStun)) self.state = .idle;
            self.speed = 0;
            self.settle(dt);
            return self.pose();
        }
        if (self.state == .slice) {
            // IT AIMS WHILE THE SPINE LAYS BACK AND STEERS NOT AT ALL AFTER — the commit is the tell's end, so the safe ground is a step to either side.
            if (self.t < SLICE_WIND) self.faceToward(hero, dt);
            self.speed = 0;
            if (self.t >= SLICE_WIND + SLICE_STRIKE + SLICE_RECOVER) {
                self.state = .idle;
                self.t = 0;
                self.sliceCool = SLICE_COOL;
                self.dealt = false;
            }
            self.settle(dt);
            return self.pose();
        }

        const sensed = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        const hunting = sensed <= AGGRO_R;
        const want = if (hunting) hero else self.home;
        const gap = mathx.distXZ(self.pos, want);
        const stop: f32 = if (hunting) stopR(foe.HERO_R) else HOME_R;

        if (hunting and gap <= triggerR(foe.HERO_R) and self.sliceCool <= 0) {
            self.state = .slice;
            self.t = 0;
            self.dealt = false;
            self.speed = 0;
            self.reared = true;
        } else if (gap > stop) {
            self.faceToward(self.nav.aim(self.pos, want), dt);
            const wantSpeed: f32 = if (hunting) RUN_SPEED else IDLE_SPEED;
            self.speed = mathx.approach(self.speed, wantSpeed, ACCEL * dt);
            const step = self.speed * dt * self.chill.travel();
            mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), step, bounds);
            self.phase = wolf.wrap01(self.phase + step / (STRIDE * self.scale));
            self.state = .move;
        } else {
            self.faceToward(want, dt);
            self.speed = mathx.approach(self.speed, 0, ACCEL * dt);
            self.state = .idle;
        }
        self.settle(dt);
        self.pose();
    }

    fn settle(self: *Skitterer, dt: f32) void {
        self.speedS = mathx.approach(self.speedS, self.speed, GAIT_BLEND * dt);
    }

    /// The hurt shape IS the kit: what the tip swept this frame against the column the hero stands in, latched to one blow per slice.
    fn tryReach(self: *Skitterer, hero: rl.Vector3) void {
        if (self.dealt) return;
        if (!foe.weaponReaches(self.tipWas, self.tipSeg(), hero, TIP_R * self.scale + foe.HERO_R)) return;
        self.heroHit = SLICE_HIT;
        self.dealt = true;
        self.leash.noteCombat();
    }

    pub fn tryHit(self: *Skitterer, blade_: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade_) orelse return;
        const heavy = foe.wounded(self, s, blade_, SHOVE);
        self.chips(s.contact, s.dir, if (heavy) CHIP_HEAVY else CHIP_LIGHT, if (heavy) 3.0 else 2.1);
        switch (s.reaction) {
            .death => {
                self.chips(s.contact, s.dir, CHIP_DEATH, 2.6);
                self.enterDeath();
            },
            .heavy => self.enterStun(true),
            .light => self.enterStun(false),
            .none => {},
        }
    }

    fn chips(self: *Skitterer, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32) void {
        foe.spray(&self.parts, &self.fxHead, &self.fxRng, at, dir, n, spd, self.scale, CHIP_SPRAY);
    }

    fn enterStun(self: *Skitterer, heavy: bool) void {
        self.state = .hurt;
        self.t = 0;
        self.heavyStun = heavy;
        self.dealt = false;
        self.trail.reset();
        self.yelped = true;
    }

    fn enterDeath(self: *Skitterer) void {
        if (self.state == .dead) return;
        self.state = .dead;
        self.t = 0;
        self.justDied = true;
        self.trail.reset();
    }

    pub fn stagger(self: *Skitterer, heavy: bool) void {
        self.enterStun(heavy);
    }

    /// **`stageGather` AND NOT `stageSlice`**: the shot harness stages every creature's signature move through this one name (`shots.runMapShots`).
    pub fn stageGather(self: *Skitterer, u: f32) void {
        self.state = .slice;
        self.t = mathx.clampF(u, 0, 1) * (SLICE_WIND + SLICE_STRIKE);
        self.pose();
        self.tipWas = self.tipSeg();
    }

    pub fn drawFx(self: *const Skitterer) void {
        foe.drawParticles(&self.parts);
        if (self.state == .slice) self.trail.draw(0.16, EYE_TRAIL, 0.55);
    }

    pub fn draw(self: *const Skitterer, model: *const Model) void {
        if (self.gone) return;
        model.draw(self);
    }

    pub fn pose(self: *Skitterer) void {
        const s = foe.rigScale(self.scale, self.fade);
        const m = mathx.clampF(self.speedS / RUN_SPEED, 0, 1);
        const react: f32 = if (self.state == .hurt) foe.stunCurve(self.t, self.heavyStun) else 0;
        const fall: f32 = if (self.state == .dead) mathx.clampF(self.t / (DEATH_DUR * 0.7), 0, 1) else 0;
        const k = self.sliceAmt();

        // **THE CAGE ROCKS ON THE WAVE PASSING DOWN IT, NOT ONCE PER RIB.** Read at the leg wave's own rate this
        // was 12 rolls a second and the body SHIMMERED; a travelling wave down a long body shows up as one slow
        // lean, so the roll is read at half the phase and the heave at the phase itself.
        const roll = mathx.sinf(self.phase * std.math.pi) * 7.0 * m;
        const heave = mathx.sinf(self.phase * std.math.tau) * 0.030 * W * m;
        const pitch = 16.0 * k - 22.0 * react;
        const sink = (0.34 * W * fall) + (0.05 * W * react);

        var wx: [N]rl.Matrix = undefined;
        wx[KEEL] = mul3(
            mul(scaleM(s, s, s), mul(rx(-pitch), rz(roll + 74.0 * mathx.smoothstep(0, 1, fall)))),
            mul(tr(0, (self.rest[KEEL].y + heave - sink) * s, 0), ry(mathx.degrees(self.facing))),
            heromod.rootAt(self.pos),
        );

        // The rear and the drive are ONE signed channel spread down the chain — the base carries most of it and the tip the least, which is what makes the tip WHIP.
        const drive = SLICE_THROUGH * 0.5 * (k + 1.0) - REAR_BACK;
        const bend = [4]f32{ 0.42, 0.28, 0.19, 0.11 };
        const sway = mathx.sinf(self.phase * std.math.pi + 0.7) * 5.5 * m;
        inline for (.{ SP0, SP1, SP2, SP3 }, 0..) |b, i| {
            const parent = if (i == 0) KEEL else b - 1;
            heromod.setJoint(&wx, &self.rest, b, parent, mul(
                rx(-drive * bend[i] - 12.0 * react * bend[i] / bend[0]),
                ry(sway * bend[i] / bend[0]),
            ));
        }
        heromod.setJoint(&wx, &self.rest, BLADE, SP3, rx(-drive * 0.10));

        self.poseRibs(&wx, m, react, fall);
        self.xf = wx;
    }

    /// The metachronal wave. Rotation-only: the swing amplitude is SOLVED off the stride (`RIB.swing`), so a planted tip travels backwards at the body's own speed instead of skating.
    fn poseRibs(self: *const Skitterer, wx: *[N]rl.Matrix, m: f32, react: f32, fall: f32) void {
        const g = wolf.Gait{ .duty = RIB_DUTY, .lag = RIB_LAG };
        for (0..LEGS) |i| {
            const side = ribSide(i);
            const p = ribPair(i);
            const ph = wolf.wrap01(self.phase +
                RIB_LAG * @as(f32, @floatFromInt(p)) +
                (if (side < 0) RIB_SIDE_LAG else 0));
            const down = wolf.planted(ph, g);
            // -1 fully aft, +1 fully forward: the stance half runs backwards and the swing half returns.
            const along: f32 = if (down)
                1.0 - 2.0 * (ph / g.duty)
            else
                -1.0 + 2.0 * ((ph - g.duty) / (1.0 - g.duty));
            // **A STANDING BODY HAS ALL SIX DOWN.** `phase` advances by DISTANCE, so a creature at rest is frozen wherever the wave stopped — ungated by `m` that froze two or three ribs in mid-air.
            const lift: f32 = if (down) 0 else mathx.sinf((ph - g.duty) / (1.0 - g.duty) * std.math.pi) * m;
            const swing = RIB.swing[i] * along * m;
            // A LIFT IS A RIB CURLING IN, not a leg lifting off: an arc rooted on the spine can only leave the ground by folding toward the keel.
            const curl = (RIB_LIFT * 34.0 * lift + 16.0 * react + 42.0 * fall) * mathx.maxF(m, if (down) 1.0 else 0.35);
            heromod.setJoint(wx, &self.rest, ribUp(i), KEEL, mul(rx(swing), rz(-side * curl)));
            heromod.setJoint(wx, &self.rest, ribLo(i), ribUp(i), mul(
                rx(-swing * 0.35),
                rz(side * (RIB_FOLD * lift * m + 0.35 * curl)),
            ));
        }
    }
};

pub fn triggerR(quarryR: f32) f32 {
    return SLICE_TRIGGER_R + quarryR;
}
/// **THE SAME RING THE TRIGGER IS, SHRUNK** (the ravager's `stopR`) — and NEITHER is scaled by the body, or the
/// two invert: at `SLICE_TRIGGER_R * scale * STOP_FRAC` a placement at 1.4 halted at 1.91 m outside a trigger ring standing at 1.90.
fn stopR(quarryR: f32) f32 {
    return SLICE_TRIGGER_R * STOP_FRAC + quarryR;
}
comptime {
    std.debug.assert(stopR(foe.HERO_R) < triggerR(foe.HERO_R));
}

/// In the head bone's own frame, face out along +z. ONE definition, shared by the two head meshes, the swept `tipSeg` and the test.
const EYE_C = v3(0, 0.05 * W, 0.10 * W);

const CAP_N = wf.MAX_PER_KIND;

pub const Clatter = struct {
    model: Model,
    band: [CAP_N]Skitterer = undefined,
    n: usize = 0,
    /// Every body the ancient priest has clawed out since the level loaded, so a raise can be seeded and counted without either side reaching into the other.
    raised: u32 = 0,
    raiseRng: mathx.Rng = mathx.Rng.init(0x5C17),

    pub fn init(shader: rl.Shader) Clatter {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Clatter) []Skitterer {
        return self.band[0..self.n];
    }
    pub fn liveConst(self: *const Clatter) []const Skitterer {
        return self.band[0..self.n];
    }
    pub fn reset(self: *Clatter, m: *const wf.Map) void {
        foe.resetGroup(Skitterer, &self.band, &self.n, m, .bone_skitterer);
        self.raised = 0;
        self.raiseRng = mathx.Rng.init(0x5C17);
    }
    pub fn clear(self: *Clatter) void {
        self.n = 0;
        self.raised = 0;
    }
    pub fn setShader(self: *Clatter, sh: rl.Shader) void {
        self.model.setShader(sh);
    }

    /// **A RAISED BODY IS A BODY, NOT A SPECIAL CASE** — same spawn, same tether, same souls; its post is where
    /// it came up. Dead slots are reused before the roster grows (the brood's law).
    pub fn raise(self: *Clatter, at: rl.Vector3, faceYaw: f32) void {
        const seed = self.raiseRng.float() * 64.0;
        for (self.live()) |*sk| {
            if (!sk.gone) continue;
            sk.* = Skitterer.spawn(at, faceYaw, 1.0, seed);
            sk.bornRaised = true;
            self.raised += 1;
            return;
        }
        // COUNTED ONLY WHEN A BODY ACTUALLY STANDS UP: bumped ahead of this guard, a full slab reported raises it had refused.
        if (self.n >= CAP_N) return;
        self.band[self.n] = Skitterer.spawn(at, faceYaw, 1.0, seed);
        self.band[self.n].bornRaised = true;
        self.n += 1;
        self.raised += 1;
    }

    pub fn update(self: *Clatter, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    pub fn draw(self: *const Clatter, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Clatter) void {
        for (self.liveConst()) |*sk| sk.drawFx();
    }
    pub fn pierce(self: *Clatter, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn setParry(self: *Clatter, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    pub fn anyParried(self: *const Clatter) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn anyDied(self: *const Clatter) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Clatter) u32 {
        return foe.soulsEach(self.liveConst());
    }
    pub fn totalHits(self: *const Clatter) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Clatter) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    const rest = restPose();
    for (0..N) |i| {
        var b = Builder.init();
        buildBone(&b, i, rest);
        mesh[i] = b.toMesh();
    }
    return mesh;
}

/// Shared by the open face and the shut one, so a blink cannot move the skull.
fn headBase(b: *Builder, rng: *mathx.Rng) void {
    b.addBlob(v3(0, 0.005 * W, -0.055 * W), v3(0.195 * W, 0.150 * W, 0.130 * W), 6, 9, BONE);
    b.addBlob(v3(EYE_C.x, EYE_C.y, EYE_C.z - 0.058 * W), v3(0.268 * W, 0.158 * W, 0.085 * W), 6, 10, BONE_LT);
    inline for (.{ 1.0, -1.0 }) |sgn| {
        const rr = 0.040 * W * rng.range(0.90, 1.10);
        b.addCapsule(
            v3(-0.250 * W, EYE_C.y + sgn * 0.030 * W, EYE_C.z + 0.012 * W),
            v3(-0.012 * W, EYE_C.y + sgn * 0.152 * W, EYE_C.z + 0.048 * W),
            rr,
            rr * 0.85,
            6,
            if (sgn > 0) BONE else BONE_DK,
        );
        b.addCapsule(
            v3(-0.012 * W, EYE_C.y + sgn * 0.152 * W, EYE_C.z + 0.048 * W),
            v3(0.250 * W, EYE_C.y + sgn * 0.030 * W, EYE_C.z + 0.012 * W),
            rr * 0.85,
            rr,
            6,
            if (sgn > 0) BONE else BONE_DK,
        );
    }
}

/// The head with the LID DOWN. What actually hits you.
fn headShutMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5C17 + @as(u64, BLADE));
    b.setMat(.plain);
    headBase(&b, &rng);
    b.addBlob(EYE_C, v3(0.238 * W, 0.132 * W, 0.096 * W), 6, 10, BONE_LT);
    b.addCapsule(
        v3(-0.195 * W, EYE_C.y + 0.012 * W, EYE_C.z + 0.086 * W),
        v3(0.195 * W, EYE_C.y - 0.012 * W, EYE_C.z + 0.086 * W),
        0.014 * W,
        0.011 * W,
        5,
        MARROW,
    );
    return b.toMesh();
}

/// Round mass, blunt ends: nothing dead is straight and nothing ends in a point (`AGENTS.md`). `fins` is off for the top segment — a row of spikes around a googly eye argues with it.
fn vertebra(b: *Builder, rng: *mathx.Rng, at: rl.Vector3, dir: rl.Vector3, len: f32, r: f32, fins: bool) void {
    const to = v3(at.x + dir.x * len, at.y + dir.y * len, at.z + dir.z * len);
    b.addCapsule(at, to, r, r * 0.86, 8, BONE);
    const n: i32 = @max(2, @as(i32, @intFromFloat(len / (r * 2.4))));
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const u = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(n));
        const c = v3(at.x + dir.x * len * u, at.y + dir.y * len * u, at.z + dir.z * len * u);
        const wobble = rng.range(0.82, 1.22);
        b.addBlob(c, v3(r * 1.24 * wobble, r * 0.62, r * 0.70 * wobble), 5, 7, BONE_LT);
        if (fins) b.addCapsule(
            c,
            v3(c.x + rng.signed() * r * 0.30, c.y + r * 1.55 * rng.range(0.72, 1.25), c.z - r * 0.55),
            r * 0.34,
            r * 0.12,
            5,
            BONE_DK,
        );
    }
}

fn buildBone(b: *Builder, i: usize, rest: [N]rl.Vector3) void {
    var rng = mathx.Rng.init(0x5C17 + @as(u64, @intCast(i)));
    b.setMat(.plain);
    switch (i) {
        // The plate OVERLAPS every rib root well past the joint, or the cage leaks sky at six seams (the packed-stone rule).
        KEEL => {
            b.addCapsule(v3(0, 0, CAGE_Z[PAIRS - 1] * W * 1.05), v3(0, 0, CAGE_Z[0] * W * 1.05), 0.115 * W, 0.135 * W, 9, BONE);
            b.addBlob(v3(0, -0.055 * W, 0.05 * W), v3(0.150 * W, 0.085 * W, 0.62 * W), 7, 8, BONE_DK);
            b.addBlob(v3(0, -0.010 * W, -0.30 * W), v3(0.100 * W, 0.060 * W, 0.28 * W), 6, 7, MARROW);
            for (0..PAIRS) |p| {
                const z = CAGE_Z[p] * W;
                b.addBlob(v3(0, 0.055 * W, z), v3(0.135 * W * rng.range(0.86, 1.14), 0.070 * W, 0.085 * W), 5, 7, BONE_LT);
            }
            // **THE CAGE IS THE FALSE RIBS, AND THEY ARE WHAT MAKE IT A RIBCAGE AND NOT A CENTIPEDE.** The six
            // that WALK are spaced for a gait, so between them the body was open sky. These arc out to two thirds of the walkers' spread and stop in the air.
            var f: u32 = 0;
            while (f < FALSE_RIBS) : (f += 1) {
                const t = (@as(f32, @floatFromInt(f)) + 0.5) / @as(f32, FALSE_RIBS);
                const z = mathx.lerpF(CAGE_Z[0] + 0.10, CAGE_Z[PAIRS - 1] - 0.06, t) * W;
                // TUCKED UP (owner: less legs): at 0.52+ of drop these dangled to the walkers' own knee line and read as a second set of legs.
                const drop = (0.40 + 0.13 * mathx.sinf(t * std.math.pi)) * W * rng.range(0.94, 1.06);
                const out = (0.36 + 0.14 * mathx.sinf(t * std.math.pi)) * W * rng.range(0.92, 1.08);
                const r = mathx.lerpF(0.042, 0.030, t) * W;
                inline for (.{ 1.0, -1.0 }) |side| {
                    const knee = v3(side * out * 0.86, -drop * 0.42, z + 0.02 * W * rng.signed());
                    const foot = v3(side * out, -drop, z + 0.03 * W * rng.signed());
                    b.addCapsule(v3(side * 0.075 * W, 0.010 * W, z), knee, r, r * 0.86, 6, BONE);
                    b.addCapsule(knee, foot, r * 0.86, r * 0.52, 6, BONE_LT);
                    b.addBlob(foot, v3(r * 0.80, r * 0.66, r * 0.80), 4, 6, BONE_DK);
                }
            }
        },
        SP0, SP1, SP2, SP3 => {
            const nextAt = rest[i + 1];
            const off = mathx.subV(nextAt, rest[i]);
            const len = mathx.lenV(off);
            const dir = if (len > 1e-5) mathx.scaleV(off, 1.0 / len) else v3(0, 1, 0);
            const r: f32 = switch (i) {
                SP0 => 0.105 * W,
                SP1 => 0.092 * W,
                SP2 => 0.078 * W,
                else => 0.062 * W,
            };
            vertebra(b, &rng, mathx.zero3, dir, len * 0.98, r, i != SP3);
            if (i == SP0) {
                b.addBlob(v3(0, 0.02 * W, 0.05 * W), v3(0.155 * W, 0.130 * W, 0.150 * W), 6, 8, BONE);
                b.addBlob(v3(0.075 * W, -0.02 * W, 0.02 * W), v3(0.060 * W, 0.090 * W, 0.075 * W), 5, 6, SINEW);
                b.addBlob(v3(-0.075 * W, -0.02 * W, 0.02 * W), v3(0.060 * W, 0.090 * W, 0.075 * W), 5, 6, SINEW);
            }
        },
        // **THE HEAD IS ONE BIG EYE AND NOTHING ELSE** (owner: a forward-facing big almond-shaped green eye, no
        // blade — they close it and slam it into you). The shut head is `headShutMesh`, swapped in by the draw.
        BLADE => {
            headBase(b, &rng);
            b.addBlob(EYE_C, v3(0.245 * W, 0.140 * W, 0.100 * W), 7, 12, EYE_GREEN);
            b.addBlob(v3(EYE_C.x, EYE_C.y + 0.005 * W, EYE_C.z + 0.088 * W), v3(0.088 * W, 0.096 * W, 0.038 * W), 5, 9, PUPIL);
        },
        else => {
            const leg = (i - LEG0) / 2;
            const lower = ((i - LEG0) % 2) == 1;
            const side = ribSide(leg);
            const p = ribPair(leg);
            const thick: f32 = mathx.lerpF(0.058, 0.044, @as(f32, @floatFromInt(p)) / @as(f32, PAIRS - 1)) * W;
            if (!lower) {
                const off = mathx.subV(rest[ribLo(leg)], rest[ribUp(leg)]);
                const mid = v3(off.x * 0.52 + side * 0.10 * W, off.y * 0.60, off.z + side * 0.0);
                b.addCapsule(mathx.zero3, mid, thick, thick * 0.92, 7, BONE);
                b.addCapsule(mid, off, thick * 0.92, thick * 0.80, 7, BONE_LT);
                b.addBlob(mathx.zero3, v3(thick * 1.5, thick * 1.4, thick * 1.7), 5, 6, BONE_DK);
            } else {
                const tip = v3(
                    (RIB_FOOT_X * PAIR_REACH[p] * side) * W - rest[ribLo(leg)].x,
                    -rest[ribLo(leg)].y,
                    rest[ribLo(leg)].z * 0.06,
                );
                const mid = v3(tip.x * 0.55 + side * 0.06 * W, tip.y * 0.42, tip.z * 0.55);
                b.addCapsule(mathx.zero3, mid, thick * 0.80, thick * 0.62, 7, BONE);
                b.addCapsule(mid, tip, thick * 0.62, thick * 0.30, 6, BONE_LT);
                b.addBlob(tip, v3(thick * 0.52, thick * 0.44, thick * 0.52), 4, 6, BONE_DK);
            }
        },
    }
}

test "IT IS A FOE, NOT A SPIRIT — its own tether, its own souls, and it answers for its own kind" {
    var s = Skitterer.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectEqual(wf.FoeKind.bone_skitterer, s.kind());
    try std.testing.expectEqual(foe.Nature.undead, foe.traitsOf(s.kind()).nature);
    try std.testing.expect(s.alive() and !s.dying() and !s.staggered());
    try std.testing.expect(s.hurtRadius() > s.bodyR());
    try std.testing.expect(s.topWorld().y > s.centerWorld().y);
    // The contract's accessors answer off ONE body: the hurt sphere has to contain the mark.
    const markOut = mathx.lenV(mathx.subV(s.centerWorld(), s.lockPoint()));
    std.debug.print("\n  skitterer mark stands {d:.2} m off the hurt centre (sphere r {d:.2}, body r {d:.2})\n", .{ markOut, s.hurtRadius(), s.bodyR() });
    try std.testing.expect(markOut < s.hurtRadius());
    s.vit.hp = 0;
    s.enterDeath();
    try std.testing.expect(s.dying() and s.justDied);
}

test "THE HURT SPHERE IS THE CAGE — you hit the body, and the blade over it is only ever a threat" {
    var s = Skitterer.spawn(mathx.zero3, 0, 1.0, 0.3);
    const c = s.centerWorld();
    const r = s.hurtRadius();
    const restTip = s.tipSeg()[1];
    std.debug.print("\n  cage centre {d:.2} m, sphere r {d:.2} m ({d:.2}..{d:.2}); blade tip {d:.2} m up\n", .{ c.y, r, c.y - r, c.y + r, restTip.y });
    // **THE GAIT'S OWN FREQUENCY, WHICH IS WHAT READ AS FREAKY** — `RUN_SPEED / STRIDE` and nothing else. Under 7 a second, or the cage buzzes instead of loping.
    const waveHz = RUN_SPEED / STRIDE;
    std.debug.print("  …rib wave {d:.1} a second at {d:.1} m/s, swing {d:.0} deg off a {d:.2} m rib (the clamp bites at 58)\n", .{ waveHz, RUN_SPEED, RIB.swing[0], RIB.reach[0] });
    try std.testing.expect(waveHz < 7.0);
    // A SOLVE THAT HIT ITS CLAMP IS A SKATE: the pose would deliver a stride short of the one `phase` is being advanced by.
    for (RIB.swing) |sw| try std.testing.expect(sw < 57.0);
    try std.testing.expect(c.y - r <= 0.02);
    try std.testing.expect(c.y + r > s.rest[SP1].y);
    // …and the reared tip stands OUTSIDE it, which is why the radius is not 1.1 m.
    s.stageGather(1.0);
    try std.testing.expect(mathx.lenV(mathx.subV(s.tipSeg()[1], s.centerWorld())) > r);
    try std.testing.expect(r > s.bodyR());
}

test "DRY BONE: fire is the answer to it, cold is not, and lightning finds nothing to run down" {
    var burnt = Skitterer.spawn(mathx.zero3, 0, 1.0, 0.3);
    const fire = combat.Hit{ .elem = combat.elems(.{ .fire = 20 }) };
    const cold = combat.Hit{ .elem = combat.elems(.{ .cold = 20 }) };
    const levin = combat.Hit{ .elem = combat.elems(.{ .lightning = 20 }) };
    try std.testing.expect(burnt.vit.damageFrom(fire) > 20.0 * 1.4);
    try std.testing.expect(burnt.vit.damageFrom(cold) < 20.0 * 0.4);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), burnt.vit.damageFrom(levin), 1e-4);
}

test "ANY CONNECTION INTERRUPTS IT — poise under the hero's lightest swing" {
    var light = Skitterer.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(POISE_MAX < heromod.ATK_LIGHT_HIT.poise);
    try std.testing.expect(light.vit.hit(heromod.ATK_LIGHT_HIT) != .none);
}

test "THE RIBS DO NOT SKATE — the swing amplitude is SOLVED off the stride, so a planted tip tracks the body" {
    var worst: f32 = 0;
    for (0..LEGS) |i| {
        const reach = RIB.reach[i];
        const covered = 2.0 * reach * mathx.sinf(mathx.radians(RIB.swing[i]));
        const want = STRIDE * RIB_DUTY;
        std.debug.print("  rib {d}: reach {d:.3} m, swing {d:.1} deg, tip covers {d:.3} m against a {d:.3} m stance\n", .{ i, reach, RIB.swing[i], covered, want });
        worst = mathx.maxF(worst, @abs(covered - want));
    }
    try std.testing.expect(worst < 0.002);
}

test "THE WAVE IS METACHRONAL — most of the six are always down, and never all at once" {
    const g = wolf.Gait{ .duty = RIB_DUTY, .lag = RIB_LAG };
    var minDown: usize = LEGS;
    var maxDown: usize = 0;
    var p: f32 = 0;
    while (p < 1.0) : (p += 1.0 / 120.0) {
        var down: usize = 0;
        for (0..LEGS) |i| {
            const ph = wolf.wrap01(p + RIB_LAG * @as(f32, @floatFromInt(ribPair(i))) + (if (ribSide(i) < 0) RIB_SIDE_LAG else 0));
            if (wolf.planted(ph, g)) down += 1;
        }
        minDown = @min(minDown, down);
        maxDown = @max(maxDown, down);
    }
    std.debug.print("\n  ribs down across one wave: {d}..{d} of {d}\n", .{ minDown, maxDown, LEGS });
    try std.testing.expect(minDown >= 4);
    try std.testing.expect(maxDown < LEGS);
}

test "IT IS THE FASTEST THING ON FOOT AND THE SLOWEST TO SWING" {
    try std.testing.expect(RUN_SPEED > wolf.GALLOP_SPEED);
    try std.testing.expect(SLICE_WIND > foe.TELL_MIN);
    std.debug.print("\n  skitterer: {d:.1} m/s chase against the wolf's {d:.1}; a {d:.2} s wind on a {d:.2} s strike\n", .{ RUN_SPEED, wolf.GALLOP_SPEED, SLICE_WIND, SLICE_STRIKE });
    var s = Skitterer.spawn(mathx.zero3, 0, 1.0, 0.3);
    s.state = .slice;
    s.t = 0;
    try std.testing.expect(s.sliceAmt() <= 0);
    s.t = SLICE_WIND;
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), s.sliceAmt(), 1e-3);
    s.t = SLICE_WIND + SLICE_STRIKE;
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), s.sliceAmt(), 1e-3);
}

test "THE SLICE IS COMMITTED AT THE END OF THE REAR — it aims while the spine lays back and not after" {
    var s = Skitterer.spawn(mathx.zero3, 0, 1.0, 0.3);
    s.state = .slice;
    s.t = 0;
    const side = mathx.ground(5, 0);
    var t: f32 = 0;
    // Past the whole wind, so what is captured is the heading it COMMITTED and not the last turn of the aim.
    while (t < SLICE_WIND + 0.01) : (t += 1.0 / 60.0) _ = s.update(1.0 / 60.0, side, 200.0, .{});
    const aimed = s.facing;
    try std.testing.expect(@abs(mathx.wrapPi(aimed - mathx.headingXZ(mathx.dirXZ(s.pos, side)))) < 0.5);
    const behind = mathx.ground(-8, -6);
    while (t < SLICE_WIND + SLICE_STRIKE) : (t += 1.0 / 60.0) {
        _ = s.update(1.0 / 60.0, behind, 200.0, .{});
        try std.testing.expectApproxEqAbs(aimed, s.facing, 1e-5);
    }
}

test "IT CAN ACTUALLY HURT HIM — one slice lands exactly one blow, and the tip is what lands it" {
    var s = Skitterer.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = mathx.ground(0, 1.1);
    s.leash.noteSeen();
    var landed: usize = 0;
    var reared = false;
    var t: f32 = 0;
    while (t < 4.0) : (t += 1.0 / 60.0) {
        if (s.update(1.0 / 60.0, hero, 200.0, .{})) |h| {
            landed += 1;
            try std.testing.expectApproxEqAbs(SLICE_HIT.dmg, h.dmg, 1e-4);
        }
        if (s.reared) reared = true;
        if (landed > 0 and s.state != .slice) break;
    }
    try std.testing.expect(reared);
    try std.testing.expectEqual(@as(usize, 1), landed);
}

test "A SLICE AIMED PAST HIM MISSES — the swept tip is the hurt shape, not a yaw sector" {
    var s = Skitterer.spawn(mathx.zero3, 0, 1.0, 0.3);
    const behind = mathx.ground(0, -1.2);
    s.stageGather(0.5);
    var t: f32 = 0;
    while (t < SLICE_STRIKE) : (t += 1.0 / 60.0) _ = s.update(1.0 / 60.0, behind, 200.0, .{});
    try std.testing.expect(s.heroHit == null);
    try std.testing.expect(!s.dealt);
}

test "THE BLADE ARRIVES INSIDE WHAT THE PARRY WINDOW PROMISES — measured off the pose, never argued" {
    var s = Skitterer.spawn(mathx.zero3, 0, 1.0, 0.3);
    var worst: f32 = 0;
    var u: f32 = 0;
    while (u <= 1.0) : (u += 1.0 / 32.0) {
        s.stageGather(u);
        const seg = s.tipSeg();
        worst = mathx.maxF(worst, mathx.distXZ(s.pos, seg[1]));
    }
    const promised = foe.hurtReach(SLICE_R, s.scale);
    std.debug.print("\n  skitterer tip reaches {d:.2} m of ground; the parry promises {d:.2} m\n", .{ worst, promised });
    try std.testing.expect(worst <= promised);
    try std.testing.expect(worst > promised * 0.55);
}

test "A PARRIED SLICE IS DROPPED AND PAID FOR" {
    var s = Skitterer.spawn(mathx.zero3, 0, 1.0, 0.3);
    s.stageGather(0.0);
    s.t = SLICE_WIND + SLICE_STRIKE * 0.5 - foe.PARRY_LEAD * 0.5;
    try std.testing.expect(s.parryable() != null);
    s.parry = .{ .live = true, .at = mathx.ground(0, 1.0), .facing = std.math.pi, .arc = combat.GUARD_ARC };
    s.takeParry();
    try std.testing.expect(s.parried);
    try std.testing.expect(s.staggered());
    try std.testing.expect(s.sliceCool > 0);
}

test "THE INCOMING LATCH IS NOT THE OUTGOING ONE — one swing of his may not wound the same body twice" {
    var s = Skitterer.spawn(mathx.zero3, 0, 1.0, 0.3);
    const swing = foe.Blade{
        .active = true,
        .r = 0.3,
        .a = v3(0, 0.6, -1.0),
        .b = v3(0, 0.6, 1.0),
        .a0 = v3(0, 0.6, -1.0),
        .b0 = v3(0, 0.6, 1.0),
        .hit = .{ .dmg = 4, .poise = 1 },
    };
    s.tryHit(swing);
    try std.testing.expectEqual(@as(u32, 1), s.hits);
    s.tryHit(swing);
    try std.testing.expectEqual(@as(u32, 1), s.hits);
}

test "A RAISED BODY IS A BODY — same spawn, and a dead slot is reused before the roster grows" {
    var c = Clatter{ .model = undefined };
    c.raise(mathx.ground(3, 4), 0.5);
    try std.testing.expectEqual(@as(usize, 1), c.n);
    try std.testing.expectEqual(@as(u32, 1), c.raised);
    try std.testing.expectEqual(wf.FoeKind.bone_skitterer, c.live()[0].kind());
    try std.testing.expectApproxEqAbs(@as(f32, 3), c.live()[0].home.x, 1e-5);
    c.band[0].gone = true;
    c.raise(mathx.ground(9, 9), 0);
    try std.testing.expectEqual(@as(usize, 1), c.n);
    try std.testing.expect(!c.live()[0].gone);
    try std.testing.expectApproxEqAbs(@as(f32, 9), c.live()[0].home.x, 1e-5);
    c.raise(mathx.ground(1, 1), 0);
    try std.testing.expectEqual(@as(usize, 2), c.n);
    try std.testing.expectEqual(@as(u32, 3), c.raised);
    for (c.live()) |*sk| try std.testing.expectEqual(SOULS_RAISED, sk.soulValue());
    const placed = Skitterer.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectEqual(SOULS, placed.soulValue());
}

test "A BIG PLACEMENT STILL ATTACKS — the stop ring may never grow past the trigger ring" {
    // The bug this pins: a `stop` scaled by the body against a `triggerR` that is not. It halted outside its own attack ring at every scale over ~1.4.
    for ([_]f32{ wf.FOE_SCALE_LO, 1.0, 1.4, wf.FOE_SCALE_HI }) |sc| {
        var s = Skitterer.spawn(mathx.zero3, 0, sc, 0.3);
        s.leash.noteSeen();
        const hero = mathx.ground(0, 9.0);
        var sliced = false;
        var t: f32 = 0;
        while (t < 6.0) : (t += 1.0 / 60.0) {
            _ = s.update(1.0 / 60.0, hero, 200.0, .{});
            if (s.sliced) sliced = true;
        }
        std.debug.print("  scale {d:.2}: halted {d:.2} m off, trigger ring {d:.2} m, sliced={}\n", .{ sc, mathx.distXZ(s.pos, hero), triggerR(foe.HERO_R), sliced });
        try std.testing.expect(sliced);
    }
}

test "THE HEAD IS THE EYE, IT RIDES THE TOP OF THE STALK, AND THE BLINK IS THE TELL" {
    var s = Skitterer.spawn(mathx.zero3, 0, 1.0, 0.3);
    const standing = foe.markOn(s.xf[BLADE], EYE_C);
    try std.testing.expect(standing.y > s.rest[SP2].y);
    try std.testing.expect(standing.y > 2.6 * W);
    try std.testing.expect(!s.eyeShut());
    s.stageGather(SLICE_WIND / (SLICE_WIND + SLICE_STRIKE));
    try std.testing.expect(s.eyeShut());
    const reared = foe.markOn(s.xf[BLADE], EYE_C);
    const travel = mathx.lenV(mathx.subV(reared, standing));
    std.debug.print("\n  skitterer eye-head: {d:.2} m up standing, travels {d:.2} m shut through the wind; {d} legs\n", .{ standing.y, travel, LEGS });
    try std.testing.expect(travel > 0.5);
    s.state = .slice;
    s.t = SLICE_WIND + SLICE_STRIKE + 0.01;
    try std.testing.expect(!s.eyeShut());
    try std.testing.expectEqual(@as(usize, 6), LEGS);
}

test "THE CAGE IS LONGER THAN IT IS TALL AND WIDER THAN IT IS DEEP — a frame, not a barrel" {
    const rest = restPose();
    const long = (CAGE_Z[0] - CAGE_Z[PAIRS - 1]) * W;
    const wide = RIB_FOOT_X * 2.0 * W;
    const tall = rest[KEEL].y;
    std.debug.print("\n  skitterer cage: {d:.2} m long, {d:.2} m across the tips, keel at {d:.2} m; blade tip {d:.2} m\n", .{ long, wide, tall, rest[BLADE].y });
    try std.testing.expect(long > tall);
    try std.testing.expect(wide > long);
    try std.testing.expect(rest[BLADE].y > tall * 2.5);
    var same: usize = 0;
    for (PAIR_REACH, 0..) |a, i| {
        for (PAIR_REACH[i + 1 ..]) |c| {
            if (@abs(a - c) < 1e-4) same += 1;
        }
    }
    try std.testing.expect(same == 0);
}
