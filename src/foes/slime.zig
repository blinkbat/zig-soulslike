const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const anim = @import("../core/anim.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const sfx = @import("../core/audio.zig");
const foestat = @import("foestat.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

const rx = mathx.rx;
const ry = mathx.ry;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const scaleM = mathx.scaleM;
const lerpF = mathx.lerpF;
const approach = mathx.approach;

/// THE GEN-0 BODY'S OWN METRE. Every generation under it is this times `GEN_SIZE_K` per split, carried on `scale`.
pub const H: f32 = 1.05;

const N = 3;
const BODY = 0;
/// The nucleus, drawn THROUGH the body. It is the lock point.
const NUC = 1;
/// The protrusion. Authored along local +Z at `PROT_LEN` and TELESCOPED by one Z scale (`fenlurker`'s law): the tip travels a straight line and `ext` stays LINEAR in its distance, which is what lets `toImpact` be solved rather than searched.
const PROT = 2;

/// Where the shaft leaves the mass, SHIN HEIGHT: `foe.HERO_LOW` is -0.10, so a lash at 0.38 m is inside his
/// capsule the whole way down. Under 0.30 H the pad grazes the turf. `REST[PROT]` is this number.
const PROT_Y: f32 = 0.36 * H;

const REST = [N]rl.Vector3{
    v3(0, 0, 0),
    v3(0.03 * H, 0.58 * H, 0.05 * H),
    v3(0, PROT_Y, 0),
};

const Hull = foe.Hull;
const HULLS = [_]Hull{
    .{ .bone = BODY, .center = v3(0, 0.34 * H, 0), .radii = v3(0.40 * H, 0.33 * H, 0.40 * H) },
};

// Alpha is the EMISSIVE channel, not transparency, so matter wants 248+. Albedos solved off a sampled render:
// screen = 255*(albedo*1.72/255)^(1/2.2) — these come back ~(52,97,71) lit and (40,76,55) in the sag.
const JELLY = rgba(4, 18, 9, 250);
const JELLY_LT = rgba(9, 27, 13, 250);
const JELLY_DK = rgba(3, 10, 5, 252);
const JELLY_WET = rgba(14, 36, 17, 248);
const NUCLEUS = rgba(150, 214, 128, 108);
const OOZE = rgba(52, 96, 60, 246);
const OOZE_THIN = rgba(88, 132, 94, 0);

pub var AGGRO_R: f32 = 11.0;
const HOME_R: f32 = 2.0;
const WALK_SPEED: f32 = heromod.WALK_SPEED_BANK * 0.42;
const CHASE_SPEED: f32 = heromod.WALK_SPEED_BANK * 0.70;
const ACCEL: f32 = 2.0;
const TURN_RATE: f32 = 2.6;

const BODY_R: f32 = 0.42;
const HURT_R: f32 = 0.56;
const CENTER_F: f32 = 0.34;
const TOP_F: f32 = 0.74;

const HP_MAX: f32 = 120.0;
const POISE_MAX: f32 = 22.0;
const STANCE_MAX: f32 = 34.0;
const RESISTS = combat.resists(.{ .fire = -45, .cold = 25, .lightning = -30, .chaos = 60 });
pub var SOULS: u32 = 110;

/// Generation 0 is what the map posts; `GENS - 1` is the leaf and does not split.
pub const GENS: u8 = 3;
/// A child is born FULL at its own smaller max, which is what stops a split cascading inside one frame.
pub const GEN_HP_K: f32 = 0.5;
/// Half the VOLUME, so the cube root of 0.5.
pub const GEN_SIZE_K: f32 = 0.7937;
/// The share of its OWN max it divides at, never the line's, so every generation splits at the same point.
pub const SPLIT_AT: f32 = 0.5;
/// Seconds coming apart. It neither moves nor strikes through it.
pub const SPLIT_DUR: f32 = 0.62;
/// Metres PRE-SCALE the halves are set apart, measured ACROSS the facing.
const SPLIT_SET: f32 = 0.34;
/// The floor on the leaf's bar: `hero.ATK_LIGHT_HIT.dmg` is 13 and a leaf one light erases is chaff.
const LEAF_HP_FLOOR: f32 = 16.0;
/// How far the mass spreads ACROSS its facing and draws in ALONG it at the peak of the split, as a share of its width.
const PINCH_SPREAD: f32 = 0.34;
/// Metres of stature the nucleus is dragged aside through the split.
const PINCH_PULL: f32 = 0.16;

comptime {
    std.debug.assert(GENS >= 2);
    std.debug.assert(GEN_HP_K > 0 and GEN_HP_K < 1);
    std.debug.assert(GEN_SIZE_K > 0 and GEN_SIZE_K < 1);
    std.debug.assert(SPLIT_AT > 0 and SPLIT_AT < 1);
    std.debug.assert(SPLIT_DUR >= foe.TELL_MIN);
    // `hero.ATK_LIGHT_HIT` is a BENCH `var` and cannot be read at comptime, so the floor is authored and named.
    var leaf: f32 = HP_MAX;
    for (0..GENS - 1) |_| leaf *= GEN_HP_K;
    std.debug.assert(leaf > LEAF_HP_FLOOR);
}

/// The whole bar off the PARENT and never a table — `foestat.arm` writes the multiplied pools onto the gen-0 body
/// alone, so poise and stance read from the constants stop dead at the first split.
fn childVit(parent: combat.Vitals) combat.Vitals {
    var v = combat.Vitals.initFoe(parent.hpMax * GEN_HP_K, parent.poiseMax * GEN_HP_K, parent.stanceMax * GEN_HP_K).withRes(RESISTS);
    v.breakShare = parent.breakShare;
    return v;
}

fn gen0Vit() combat.Vitals {
    return combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
}

/// Metres of shaft at full extension on the gen-0 body, along the bone's own +Z. `hurtReach` scales it.
const PROT_LEN: f32 = 2.30;
const PROT_R: f32 = 0.115;
/// What a SWEPT bill may add (the lurker's form): his radius plus the shaft's half-thickness, never `foe.hurtReach`'s
/// 0.55 m, which is what a centre-to-centre RADIUS test owes. It is both the band's tail and the `r` the bill is handed.
fn protGrip(scale: f32) f32 {
    return foe.HERO_R + PROT_R * scale;
}
const LASH_WIND: f32 = 0.46;
const LASH_STRIKE: f32 = 0.20;
const LASH_RECOVER: f32 = 0.52;
const LASH_CD: f32 = 2.4;
const LASH_FRONT_DOT: f32 = 0.42;
pub const LASH_STUPEFY: f32 = 42.0;
pub var LASH_HIT = combat.Hit{
    .dmg = 7,
    .poise = 6,
    .dose = combat.Doses.one(.stupefy, LASH_STUPEFY),
};

comptime {
    std.debug.assert(LASH_WIND >= foe.TELL_MIN);
    std.debug.assert(PROT_LEN > BODY_R * 3.0);
}

/// How far the shaft is out: 0 inside the body, 1 at full stretch. LINEAR on the way out, which is what `toImpact` solves off.
fn extAt(t: f32) f32 {
    if (t < LASH_WIND) return 0;
    const s = t - LASH_WIND;
    if (s <= LASH_STRIKE) return mathx.clampF(s / LASH_STRIKE, 0, 1);
    return mathx.clampF(1.0 - (s - LASH_STRIKE) / LASH_RECOVER, 0, 1);
}

const DEATH_DUR: f32 = 0.26;
const DISS_DUR: f32 = 0.62;
const SHOVE_DECAY: f32 = 9.0;
const DISSOLVE = foe.Dissolve{ .rate = 46.0, .spread = 0.5, .rise = 0.15, .flake = OOZE };

const SPLAT = foe.Spray{ .fanLo = 0.5, .fanHi = 2.1, .upLo = 0.5, .upHi = 2.0, .lifeLo = 0.26, .lifeHi = 0.62, .rLo = 0.05, .rHi = 0.15, .r1 = 0.01, .col = OOZE, .col1 = OOZE_THIN, .grav = 5.5 };

const HIT_OOZE_LIGHT = 5;
const HIT_OOZE_HEAVY = 11;
const PARRY_OOZE = 8;
const SPLIT_OOZE = 26;
const PARTS = 96;
comptime {
    std.debug.assert(@as(f32, PARTS) >= @as(f32, @floatFromInt(SPLIT_OOZE + PARRY_OOZE + foe.hitParts(HIT_OOZE_HEAVY) + foe.WOUND_PARTS)));
}

const State = enum { idle, walk, lash, splitting, stunlight, stunheavy, dead };

const Choice = enum { rest, hold, close, lash };

/// The SWEEP's own arithmetic, never `foe.hurtReach`: written with `hurtReach` the choose took stands 0.4 m past
/// anything the shaft could cross. A splitter finds this seam first because its scale moves MID-FIGHT.
fn lashBand(scale: f32) f32 {
    return PROT_LEN * scale + protGrip(scale);
}

/// Degrees the wind can bring the shaft round, off `TURN_RATE` (`fenlurker.windSweep`); a shaft adds no cone.
const LASH_SWEEP: f32 = mathx.degrees(TURN_RATE) * LASH_WIND;

/// `bearing` is degrees off the facing; past `LASH_SWEEP` the lash is REFUSED, not scored down, and `.close` turns it.
fn classify(sensed: f32, bearing: f32, homeGap: f32, scale: f32, lashReady: bool, rooted: bool) Choice {
    if (sensed > AGGRO_R) return if (homeGap > HOME_R) .hold else .rest;
    // The grip takes the FEET, so the bail stands BELOW the band — a telescoping shaft needs none.
    if (sensed <= lashBand(scale) and @abs(bearing) <= LASH_SWEEP and lashReady) return .lash;
    if (rooted) return .rest;
    return .close;
}

/// Reported for ONE frame (the shroom's `burstAt` rule): the GROUP puts the two bodies on the field, because a body
/// cannot reach into the array that holds it.
pub const Act = union(enum) {
    none,
    split: struct { at: rl.Vector3, facing: f32, gen: u8, scale: f32, seed: f32 },
};

pub const Model = struct {
    bone: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        return .{ .bone = buildBones(), .mat = gfx.material(shader, "slime") };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, s: *const Slime) void {
        rl.drawMesh(self.bone[BODY], self.mat, s.xf[BODY]);
        rl.drawMesh(self.bone[NUC], self.mat, s.xf[NUC]);
        // At `ext` 0 the shaft is inside the mass: drawing it is a spike through the body's own face.
        if (s.ext > 0.02) rl.drawMesh(self.bone[PROT], self.mat, s.xf[PROT]);
    }
};

pub const Slime = struct {
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
    gen: u8 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    lashCd: f32 = 0,
    speed: f32 = 0,
    /// DISTANCE travelled, never a clock, so a held body stops wobbling.
    phase: f32 = 0,
    ext: f32 = 0,

    squash: f32 = 1,
    lean: f32 = 0,
    pinch: f32 = 0,
    posed: [3]f32 = .{ 1, 0, 0 },
    springs: anim.SpringBank(3) = .{},

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    heroLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    heroHit: ?combat.Hit = null,
    justDied: bool = false,
    parry: foe.Parry = .{},
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

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Slime {
        return spawnGen(home, faceYaw, scale, seed, 0, gen0Vit());
    }

    /// For the bench and the harness only: the fight's own children come through `divide`, off the body that bore them.
    pub fn spawnAt(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32, gen: u8) Slime {
        var vit = gen0Vit();
        for (0..gen) |_| vit = childVit(vit);
        return spawnGen(home, faceYaw, scale, seed, gen, vit);
    }

    pub fn spawnGen(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32, gen: u8, vit: combat.Vitals) Slime {
        var s = Slime{ .pos = home, .home = home, .facing = faceYaw, .scale = scale, .seed = seed, .gen = gen, .vit = vit };
        s.fxRng = foe.fxStream(seed, 51407.0, 0x51E0);
        s.aiRng = foe.fxStream(seed, 28711.0, 0x51E1);
        s.lashCd = 0.3 + seed * 0.7;
        s.springs.seat(s.posed);
        s.pose();
        return s;
    }

    pub fn centerWorld(self: *const Slime) rl.Vector3 {
        return foe.markOn(self.xf[BODY], v3(0, CENTER_F * H, 0));
    }
    pub fn lockPoint(self: *const Slime) rl.Vector3 {
        return foe.markOn(self.xf[NUC], mathx.zero3);
    }
    pub fn topWorld(self: *const Slime) rl.Vector3 {
        return foe.markOn(self.xf[BODY], v3(0, TOP_F * H, 0));
    }
    pub fn hurtRadius(self: *const Slime) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Slime) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Slime) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Slime) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Slime) bool {
        return foe.inStun(self) or self.state == .dead;
    }
    pub fn airborne(self: *const Slime) bool {
        _ = self;
        return false;
    }
    pub fn flashFrac(self: *const Slime) f32 {
        return foe.flashFrac(self.flash);
    }
    fn fdir(self: *const Slime) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    pub fn navWant(self: *const Slime, hero: rl.Vector3) ?rl.Vector3 {
        if (self.state != .idle and self.state != .walk) return null;
        return foe.navChase(self, hero, AGGRO_R, HOME_R);
    }
    fn faceToward(self: *Slime, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }

    pub fn splits(self: *const Slime) bool {
        return self.gen + 1 < GENS and self.state != .splitting and !self.dying();
    }

    /// Seconds to the impact frame, off the shaft's LINEAR extension: one crossing its reach at a constant rate meets a
    /// man at 1 m in far less time than one at 2 m, so a fixed share of the stroke is right at exactly one range.
    fn toImpact(self: *const Slime) ?f32 {
        if (self.state != .lash) return null;
        const gap = mathx.distXZ(self.pos, self.parry.at);
        // The grip comes off the GAP first: the bill is a SWEPT segment and lands when `reach + protGrip` crosses him,
        // not when the tip reaches his centre. Left in, the clock ran 26-73 ms behind the bill and no stand could parry.
        const want = mathx.clampF((gap - protGrip(self.scale)) / (PROT_LEN * self.scale), 0, 1);
        return LASH_WIND + LASH_STRIKE * want - self.t;
    }

    fn enter(self: *Slime, s: State) void {
        self.state = s;
        self.t = 0;
    }
    fn enterStun(self: *Slime, s: State) void {
        self.heroLatch = false;
        self.ext = 0;
        self.enter(s);
    }
    pub fn stagger(self: *Slime, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    fn enterDeath(self: *Slime) void {
        self.heroLatch = false;
        self.ext = 0;
        self.enter(.dead);
        self.justDied = true;
    }
    /// The halves are reported at the END of the anim, so the body is a sitting duck for exactly as long as it runs.
    fn enterSplit(self: *Slime) void {
        self.heroLatch = false;
        self.ext = 0;
        self.lashCd = @max(self.lashCd, SPLIT_DUR);
        self.enter(.splitting);
        sfx.world(.shroom_puff, self.pos);
    }

    pub fn debugSplit(self: *Slime) void {
        if (self.splits()) self.enterSplit();
    }
    /// `shots.STAGE_SHOT` finds this by name and calls it at 1.0, so `u` must run the gather THROUGH to full stretch —
    /// walked to the end of the WIND instead it is the shaft retracted, which is the stand pose again.
    pub fn stageGather(self: *Slime, u: f32) void {
        self.enter(.lash);
        self.t = (LASH_WIND + LASH_STRIKE) * mathx.clampF(u, 0, 1);
        self.ext = extAt(self.t);
        self.chaseChannels(0);
        self.springs.seat(self.posed);
        self.pose();
    }

    pub fn update(self: *Slime, dt: f32, quarry: rl.Vector3, bounds: f32, blade: foe.Blade) Act {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return .none;
        }
        self.heroHit = null;
        self.parried = false;
        self.justDied = false;
        self.deflect.tick(dt);
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.vit.tick(dt);
        self.elapsed += dt;
        self.t += dt;
        self.lashCd = mathx.maxF(0, self.lashCd - dt);
        foe.tickBody(self, dt, quarry, bounds, AGGRO_R, SHOVE_DECAY);

        var moved: f32 = 0;

        switch (self.state) {
            .dead => {
                self.speed = 0;
                self.ext = 0;
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
            .splitting => {
                self.speed = 0;
                // Before the pose, the parry and `tryHit`: its halves overwrite this body.
                if (self.t >= SPLIT_DUR) return self.divide();
            },
            .stunlight, .stunheavy => {
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                if (self.t >= combat.foeStunDur(self.state == .stunheavy)) self.enter(.idle);
            },
            .lash => {
                self.speed = approach(self.speed, 0, ACCEL * 2.2 * dt);
                if (self.t < LASH_WIND) self.faceToward(quarry, dt);
                self.ext = extAt(self.t);
                if (self.t >= LASH_WIND + LASH_STRIKE + LASH_RECOVER) {
                    self.heroLatch = false;
                    self.enter(.idle);
                }
            },
            .idle, .walk => {
                self.ext = 0;
                const sensed = foe.senseHero(&self.leash, self.pos, quarry, AGGRO_R);
                const homeGap = mathx.distXZ(self.pos, foe.homeFor(self));
                const bearing = foe.bearingDeg(self.pos, self.facing, quarry);
                switch (classify(sensed, bearing, homeGap, self.scale, self.lashCd <= 0, self.root.held())) {
                    .rest => {
                        if (sensed <= AGGRO_R) self.faceToward(quarry, dt);
                        if (foe.postWant(self, dt, sensed, AGGRO_R)) |go| {
                            self.faceToward(self.nav.aim(self.pos, go), dt);
                            self.speed = approach(self.speed, WALK_SPEED, ACCEL * dt);
                            moved = foe.strideBy(self, dt, bounds);
                            self.state = .walk;
                        } else {
                            self.speed = approach(self.speed, 0, ACCEL * dt);
                            self.state = .idle;
                        }
                    },
                    .lash => {
                        self.speed = approach(self.speed, 0, ACCEL * 2.2 * dt);
                        self.lashCd = LASH_CD * self.aiRng.range(0.85, 1.25);
                        self.heroLatch = false;
                        self.enter(.lash);
                    },
                    .hold, .close => |ch| {
                        foe.chaseAim(self, ch == .hold, quarry, dt, WALK_SPEED, CHASE_SPEED, ACCEL, TURN_RATE);
                        moved = foe.strideBy(self, dt, bounds);
                        self.state = .walk;
                    },
                }
            },
        }

        if (moved > 0) self.phase = mathx.wrap01(self.phase + moved / (0.9 * self.scale));
        if (self.state == .lash and self.t >= LASH_WIND and self.t - dt < LASH_WIND) sfx.world(.shroom_fling, self.pos);
        self.chaseChannels(dt);
        self.pose();

        self.takeParry(dt);
        if (!self.parried and self.state == .lash and self.ext > 0) self.tryLash(quarry, dt);
        self.tryHit(blade);
        return .none;
    }

    /// Billed segment by segment along the sweep (the lurker's rule): handed the whole reach as one segment the samples
    /// sit far enough apart to pass clean through a man.
    fn tryLash(self: *Slime, quarry: rl.Vector3, dt: f32) void {
        if (self.heroLatch) return;
        if (!self.sweptOnto(quarry, dt)) return;
        foe.bill(self, LASH_HIT);
    }

    /// The ONE geometry the bill and the catch both ask, so neither can land a frame ahead of the other.
    fn sweptOnto(self: *const Slime, at: rl.Vector3, dt: f32) bool {
        const then = self.protSegAt(extAt(mathx.maxF(0, self.t - dt)));
        return foe.weaponReaches(then, self.protSeg(), at, protGrip(self.scale));
    }

    /// The SWEEP delivers the catch, the clock only earns it (the ogre's rule). Waiting for `toImpact` to cross zero puts
    /// it one frame behind `tryLash` and `heroLatch` has shut the window: a shield caught nothing at twelve of twelve stands.
    fn takeParry(self: *Slime, dt: f32) void {
        const reach = lashBand(self.scale);
        const aimed = foe.inFront(self.pos, self.facing, self.parry.at, reach, LASH_FRONT_DOT);
        const until = if (self.heroLatch or !aimed) null else self.toImpact();
        const touching = self.state == .lash and self.ext > 0 and self.sweptOnto(self.parry.at, dt);
        if (!foe.caught(self, reach, until, touching)) return;
        const tip = self.protTipWorld();
        self.stagger(foe.parryBroke(self));
        self.ooze(tip, mathx.dirXZ(self.pos, self.parry.at), PARRY_OOZE);
    }

    fn protSeg(self: *const Slime) [2]rl.Vector3 {
        return self.protSegAt(self.ext);
    }
    fn protSegAt(self: *const Slime, ext: f32) [2]rl.Vector3 {
        const base = foe.markOn(self.xf[BODY], v3(REST[PROT].x, REST[PROT].y, REST[PROT].z));
        const d = self.fdir();
        const reach = PROT_LEN * self.scale * ext;
        return .{ base, v3(base.x + d.x * reach, base.y, base.z + d.z * reach) };
    }
    fn protTipWorld(self: *const Slime) rl.Vector3 {
        return self.protSeg()[1];
    }

    fn divide(self: *Slime) Act {
        self.ooze(self.centerWorld(), v3(0, 1, 0), SPLIT_OOZE);
        self.gone = true;
        return .{ .split = .{
            .at = self.pos,
            .facing = self.facing,
            .gen = self.gen + 1,
            .scale = self.scale * GEN_SIZE_K,
            .seed = self.seed,
        } };
    }

    pub fn tryHit(self: *Slime, blade: foe.Blade) void {
        if (self.dying()) return;
        if (blade.active and !self.hullTouches(blade.a, blade.b, blade.r) and !self.hullTouches(blade.a0, blade.b0, blade.r)) return;
        const s = foe.reached(self, blade) orelse return;
        const heavy = foe.wounded(self, s, blade, .{ .light = 0.8, .heavy = 1.3 });
        self.ooze(s.contact, s.dir, foe.hitParts(if (heavy) HIT_OOZE_HEAVY else HIT_OOZE_LIGHT));
        sfx.world(.shroom_hurt, self.pos);
        switch (s.reaction) {
            .death => {
                sfx.world(.shroom_die, self.pos);
                self.enterDeath();
                return;
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
        // One blow is one split however far under the line it drove the bar; `splitting` is what refuses a second.
        if (self.splits() and self.vit.hpFrac() <= SPLIT_AT) self.enterSplit();
    }

    fn hullTouches(self: *const Slime, a: rl.Vector3, b: rl.Vector3, r: f32) bool {
        return foe.hullsTouch(&self.xf, &HULLS, a, b, r);
    }

    fn ooze(self: *Slime, at: rl.Vector3, dir: rl.Vector3, n: i32) void {
        foe.ownSpray(self, at, dir, n, 2.0, self.scale, SPLAT);
    }

    fn chaseChannels(self: *Slime, dt: f32) void {
        const u = if (self.state == .splitting) mathx.clampF(self.t / SPLIT_DUR, 0, 1) else 0;
        const gather = mathx.smoothstep(0.0, 0.34, u);
        const part = mathx.smoothstep(0.30, 1.0, u);
        const wob = 0.055 * mathx.sinf(self.phase * std.math.tau * 2.0);
        self.squash = if (self.state == .splitting) lerpF(1.0, 0.72, gather) + 0.10 * part else 1.0 + wob;
        self.lean = if (self.state == .lash) lerpF(0, 16.0, self.ext) else 0;
        self.pinch = part;
        self.posed = .{ self.squash, self.lean, self.pinch };
        self.springs.chase(&self.posed, 1500, 0.72, 0.80, dt);
    }

    pub fn stunAmount(self: *const Slime) f32 {
        return foe.stunShape(self, foe.stunCurve);
    }

    pub fn pose(self: *Slime) void {
        if (!foe.posed(self)) return;
        const fs = foe.rigScale(self.scale, self.fade);
        const sy = self.posed[0];
        // Volume is kept: a squat widens.
        const sxz = 1.0 / @sqrt(mathx.maxF(0.4, sy));
        // `PINCH_SPREAD` either way of one: across the facing and thin along it.
        const pinch = self.posed[2];
        const sx = sxz * (1.0 + PINCH_SPREAD * pinch);
        const sz = sxz * (1.0 - PINCH_SPREAD * pinch);
        const stun = self.stunAmount();
        const root = mul3(
            mul(scaleM(sx * fs, sy * fs, sz * fs), rx(self.posed[1] + stun * 9.0)),
            ry(mathx.degrees(self.facing)),
            tr(self.pos.x, self.pos.y, self.pos.z),
        );
        self.xf[BODY] = root;
        const drift = 0.035 * H * mathx.sinf(self.elapsed * 0.9 + self.seed * 7.0);
        const pull = PINCH_PULL * pinch * H;
        self.xf[NUC] = mul(tr(REST[NUC].x + drift + pull, REST[NUC].y, REST[NUC].z + drift * 0.6), root);
        // Off the bill's frame: `root` carries the lash lean.
        const base = foe.markOn(root, REST[PROT]);
        self.xf[PROT] = mul3(scaleM(fs, fs, fs * mathx.maxF(1e-3, self.ext)), ry(mathx.degrees(self.facing)), tr(base.x, base.y, base.z));
    }

    pub fn draw(self: *const Slime, model: *const Model) void {
        model.draw(self);
    }

    pub fn drawFx(self: *const Slime) void {
        foe.drawParticles(&self.parts);
    }
};

fn buildBones() [N]rl.Mesh {
    var out: [N]rl.Mesh = undefined;
    var rng = mathx.Rng.init(0x511E);

    var body = Builder.init();
    body.setMat(.skin);
    // The lobes stand a few PERCENT of the radius PROUD, not sunk: at 0.40 H sunk they caught no normal of their own.
    const R = 0.40 * H;
    body.addBlob(v3(0.02 * H, 0.33 * H, -0.01 * H), v3(R * rng.range(0.96, 1.10), 0.33 * H, R * rng.range(0.92, 1.06)), 13, 9, JELLY);
    // The widest point is LOW but INSIDE the silhouette: proud of it at 1.06 R the ring reads as a plate, not a sag.
    body.addBlob(v3(0, 0.13 * H, 0), v3(R * 0.99, 0.13 * H, R * 0.97), 13, 6, JELLY_DK);
    body.addBlob(v3(0.21 * H, 0.28 * H, -0.13 * H), v3(0.21 * H, 0.18 * H, 0.20 * H), 8, 7, JELLY_LT);
    body.addBlob(v3(-0.19 * H, 0.21 * H, 0.15 * H), v3(0.17 * H, 0.14 * H, 0.16 * H), 8, 7, JELLY_LT);
    body.addBlob(v3(-0.05 * H, 0.44 * H, -0.19 * H), v3(0.15 * H, 0.13 * H, 0.14 * H), 8, 7, JELLY_DK);
    body.addBlob(v3(0.06 * H, 0.50 * H, 0.17 * H), v3(0.16 * H, 0.14 * H, 0.15 * H), 8, 7, JELLY_WET);
    out[BODY] = body.toMesh();

    var nuc = Builder.init();
    nuc.setMat(.skin);
    nuc.addBlob(mathx.zero3, v3(0.13 * H, 0.12 * H, 0.13 * H), 9, 7, NUCLEUS);
    out[NUC] = nuc.toMesh();

    // Along +Z at FULL length so one Z scale is the whole telescope, and the axis STAYS STRAIGHT because the bill is a
    // straight segment down the facing. A 0.115 -> 0.085 taper over 1.9 m is invisible, so the profile carries it instead.
    var prot = Builder.init();
    prot.setMat(.skin);
    const L = PROT_LEN;
    const seg = [_]struct { z: f32, r: f32 }{
        .{ .z = 0.00, .r = 0.235 },
        .{ .z = 0.16, .r = 0.128 },
        .{ .z = 0.42, .r = 0.092 },
        .{ .z = 0.68, .r = 0.088 },
        .{ .z = 0.86, .r = 0.125 },
    };
    for (seg[0 .. seg.len - 1], seg[1..]) |a, b| {
        prot.addCapsule(v3(0, 0, a.z * L), v3(0, 0, b.z * L), a.r, b.r, 8, JELLY);
    }
    prot.addBlob(v3(0, 0, 0.93 * L), v3(0.175, 0.150, 0.190), 8, 6, JELLY_LT);
    out[PROT] = prot.toMesh();
    return out;
}

const CAP_N = wf.MAX_PER_KIND;

pub const Mire = struct {
    model: Model,
    slimes: [CAP_N]Slime = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Mire {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Mire) []Slime {
        return self.slimes[0..self.n];
    }
    pub fn liveConst(self: *const Mire) []const Slime {
        return self.slimes[0..self.n];
    }
    pub fn reset(self: *Mire, m: *const wf.Map) void {
        foe.resetGroup(Slime, &self.slimes, &self.n, m, .slime);
    }
    pub fn setShader(self: *Mire, sh: rl.Shader) void {
        self.model.setShader(sh);
    }

    /// NOT routed through `foe.summonInto`: that arms `foestat`, which records whatever pools the body carries as the
    /// KIND's authored ones, so a gen-2 body would rewrite the line's own bar.
    fn seat(self: *Mire, body: Slime) void {
        var b = body;
        b.leash.call();
        foe.seatInto(Slime, &self.slimes, &self.n, b);
    }

    pub fn update(self: *Mire, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        var blow: ?foe.Blow = null;
        var i: usize = 0;
        // Walked by INDEX because `seat` may append: a slice taken once is the array as it was BEFORE the split.
        while (i < self.n) : (i += 1) {
            const act = self.slimes[i].update(dt, self.slimes[i].threat.aim(hero), bounds, blade);
            if (self.slimes[i].heroHit) |h| foe.worseBlow(&blow, h, self.slimes[i].pos, &self.slimes[i].threat);
            switch (act) {
                .none => {},
                .split => |s| {
                    // The bar comes off the body still in the slot: a `Vitals` on the one-frame union is 288 B per slab slot.
                    const vit = childVit(self.slimes[i].vit);
                    // The map's `when=` is the line's, like its `scale=`.
                    const when = self.slimes[i].leash.win.when;
                    // Kept across `seatInto`, which reuses the parent's slot: the ooze `divide` threw is in this pool.
                    const motes = self.slimes[i].parts;
                    const head = self.slimes[i].fxHead;
                    const across = mathx.perpXZNeg(mathx.headingDir(s.facing));
                    for ([_]f32{ -1, 1 }, 0..) |side, k| {
                        const off = SPLIT_SET * s.scale * side;
                        const at = v3(s.at.x + across.x * off, s.at.y, s.at.z + across.z * off);
                        const seed = mathx.wrap01(s.seed + 0.37 * @as(f32, @floatFromInt(k + 1)));
                        var child = Slime.spawnGen(at, s.facing, s.scale, seed, s.gen, vit);
                        child.leash.win.when = when;
                        self.seat(child);
                    }
                    if (!self.slimes[i].gone) {
                        self.slimes[i].parts = motes;
                        self.slimes[i].fxHead = head;
                    }
                },
            }
        }
        return blow;
    }

    pub fn draw(self: *const Mire, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Mire) void {
        for (self.liveConst()) |*s| s.drawFx();
    }
    pub fn pierce(self: *Mire, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn soulsDropped(self: *const Mire) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn anyDied(self: *const Mire) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn totalHits(self: *const Mire) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Mire) u32 {
        return foe.aliveCount(self.liveConst());
    }
    pub fn setParry(self: *Mire, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    pub fn anyParried(self: *const Mire) bool {
        return foe.anyParried(self.liveConst());
    }
};

fn probe(scale: f32) Slime {
    return Slime.spawn(mathx.ground(0, 0), 0, scale, 0.31);
}

fn smack(s: *Slime, dmg: f32) void {
    const at = s.centerWorld();
    const a = v3(at.x - 1.0, at.y, at.z);
    const b = v3(at.x + 1.0, at.y, at.z);
    s.tryHit(.{ .active = true, .pierce = true, .r = 0.1, .a = a, .b = b, .a0 = a, .b0 = b, .hit = .{ .dmg = dmg } });
}

test "THE PROTRUSION LANDS ON THE MAN WHERE HE STANDS — thrown for real, at every scale its own band picks it at" {
    const dt: f32 = 1.0 / 120.0;
    var thrown: usize = 0;
    var misses: usize = 0;
    var widest: f32 = 0;
    for ([_]f32{ wf.FOE_SCALE_LO, 1.0, wf.FOE_SCALE_HI }) |scale| {
        const p = probe(scale);
        const apart = foe.closestApproach(p.bodyR());
        var lo: f32 = apart;
        var hi: f32 = AGGRO_R;
        for (0..48) |_| {
            const mid = (lo + hi) * 0.5;
            if (classify(mid, 0, 0, scale, true, false) == Choice.lash) lo = mid else hi = mid;
        }
        const far = lo;
        widest = @max(widest, far - lashBand(scale));
        for ([_]f32{ 0, 18, 34 }) |deg| {
            for ([_]f32{ 0.0, 0.3, 0.6, 0.85, 1.0 }) |u| {
                const stand = lerpF(apart + 0.05, far - 0.002, u);
                if (classify(stand, 0, 0, scale, true, false) != Choice.lash) continue;
                thrown += 1;
                const a = mathx.radians(deg);
                var c = probe(scale);
                const hero = v3(@sin(a) * stand, 0, @cos(a) * stand);
                c.enter(.lash);
                var hit = false;
                var guard: usize = 0;
                while (guard < 2000) : (guard += 1) {
                    if (c.update(dt, hero, 400.0, .{}) != .none) {}
                    if (c.heroHit != null) {
                        hit = true;
                        break;
                    }
                    if (c.state != .lash) break;
                }
                if (!hit) {
                    misses += 1;
                    std.debug.print("\n  x{d:.2} at {d:.2} m, {d:.0} deg off: MISSED — the band runs to {d:.2} m, the shaft bills to {d:.2}\n", .{ scale, stand, deg, far, lashBand(scale) });
                }
            }
        }
    }
    std.debug.print("\n  slime: {d} stands thrown across three scales, {d} billed nothing; band overruns its reach by at most {d:.3} m\n", .{ thrown, misses, widest });
    try std.testing.expectEqual(@as(usize, 0), misses);
    try std.testing.expect(widest <= 0.001);
}

test "ONE BLOW, ONE SPLIT — however far under the line it drove the bar" {
    var s = probe(1.0);
    smack(&s, HP_MAX * 0.95);
    try std.testing.expectEqual(State.splitting, s.state);
    try std.testing.expect(s.vit.hpFrac() <= SPLIT_AT);

    smack(&s, 1.0);
    try std.testing.expectEqual(State.splitting, s.state);
    std.debug.print("\n  slime: one blow of {d:.0} crosses both thresholds and still divides ONCE, at {d:.0}% of its bar\n", .{ HP_MAX * 0.95, s.vit.hpFrac() * 100 });
}

test "A CHILD IS BORN FULL AT HALF THE BAR, AND THE LINE TERMINATES" {
    const dt: f32 = 1.0 / 60.0;
    var mire = Mire{ .model = undefined };
    mire.n = 1;
    mire.slimes[0] = probe(1.0);
    const parentMax = mire.slimes[0].vit.hpMax;

    smack(&mire.slimes[0], parentMax * 0.6);
    var guard: usize = 0;
    while (guard < 400 and mire.n == 1) : (guard += 1) _ = mire.update(dt, v3(0, 0, 40), 400.0, .{});

    var kids: usize = 0;
    var kidMax: f32 = 0;
    for (mire.liveConst()) |*c| {
        if (c.gone) continue;
        kids += 1;
        kidMax = c.vit.hpMax;
        try std.testing.expectApproxEqAbs(c.vit.hpMax, c.vit.hp, 1e-3);
        try std.testing.expectEqual(@as(u8, 1), c.gen);
        try std.testing.expect(c.scale < 1.0);
    }
    try std.testing.expectEqual(@as(usize, 2), kids);
    try std.testing.expectApproxEqAbs(parentMax * GEN_HP_K, kidMax, 1e-3);

    var leaf = Slime.spawnAt(mathx.ground(0, 0), 0, 1.0, 0.2, GENS - 1);
    try std.testing.expect(!leaf.splits());
    smack(&leaf, leaf.vit.hpMax * 0.9);
    try std.testing.expect(leaf.state != .splitting);

    std.debug.print("\n  slime: gen 0 {d:.0} HP -> two gen-1 at {d:.0} each, born full; gen {d} is the leaf and cannot divide\n", .{ parentMax, kidMax, GENS - 1 });
}

test "THE BENCH REACHES EVERY GENERATION — the whole bar comes off the body it came out of, not off the table" {
    const slot = @intFromEnum(wf.FoeKind.slime);
    const was = foestat.mult[slot];
    defer foestat.mult[slot] = was;
    foestat.mult[slot] = .{ .hp = 2.0, .poise = 3.0, .stance = 0.5, .brk = 1.5 };

    var parent = probe(1.0);
    foestat.arm(&parent.vit, .slime);
    const kid = childVit(parent.vit);
    try std.testing.expectApproxEqAbs(parent.vit.hpMax * GEN_HP_K, kid.hpMax, 1e-3);
    try std.testing.expectApproxEqAbs(parent.vit.poiseMax * GEN_HP_K, kid.poiseMax, 1e-3);
    try std.testing.expectApproxEqAbs(parent.vit.stanceMax * GEN_HP_K, kid.stanceMax, 1e-3);
    try std.testing.expectApproxEqAbs(parent.vit.breakShare, kid.breakShare, 1e-6);
    try std.testing.expect(kid.poiseMax > POISE_MAX * GEN_HP_K);
    std.debug.print("\n  slime: a x3 poise on the bench reaches gen 1 at {d:.1}, where the table alone gives {d:.1}\n", .{ kid.poiseMax, POISE_MAX * GEN_HP_K });
}

test "THE SPLIT IS A PUNISH WINDOW — the body neither travels nor strikes while it is coming apart" {
    const dt: f32 = 1.0 / 60.0;
    var s = probe(1.0);
    smack(&s, HP_MAX * 0.6);
    try std.testing.expectEqual(State.splitting, s.state);
    var t: f32 = 0;
    while (t < SPLIT_DUR * 0.9) : (t += dt) {
        _ = s.update(dt, v3(0, 0, 1.2), 400.0, .{});
        // The window forbids the body CHOOSING to travel or strike, not the shove off the blow that split it.
        try std.testing.expect(s.heroHit == null);
        try std.testing.expectApproxEqAbs(@as(f32, 0), s.speed, 1e-6);
        try std.testing.expectApproxEqAbs(@as(f32, 0), s.ext, 1e-6);
    }
    std.debug.print("\n  slime: {d:.2} s of split at zero speed, shaft in, billing nothing with the man at 1.2 m\n", .{SPLIT_DUR});
}

test "THE SHAFT IS LINEAR ON THE WAY OUT, which is what lets the parry window be SOLVED" {
    // `toImpact` divides the gap by the reach; that is only honest while `ext` is linear in the tip's distance.
    var prev: f32 = -1;
    var u: f32 = 0;
    while (u <= 1.0) : (u += 0.05) {
        const e = extAt(LASH_WIND + LASH_STRIKE * u);
        try std.testing.expect(e > prev);
        try std.testing.expectApproxEqAbs(u, e, 1e-4);
        prev = e;
    }
    try std.testing.expectApproxEqAbs(@as(f32, 0), extAt(0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), extAt(LASH_WIND + LASH_STRIKE + LASH_RECOVER), 1e-4);
    std.debug.print("\n  slime: the shaft is linear over its whole {d:.2} m stretch, and is back inside the body by the recover\n", .{PROT_LEN});
}

test "HEIGHT IS A SEPARATE QUESTION FROM REACH — where the shaft actually crosses him, at every scale" {
    // The lurker's lesson: a shaft that reaches far enough and passes UNDER him bills nothing, and a band test
    // cannot see it. `foe.HERO_LOW` is -0.10 and `HERO_HIGH` 1.71, so the shaft has to sit inside that band.
    for ([_]f32{ wf.FOE_SCALE_LO, 1.0, wf.FOE_SCALE_HI }) |scale| {
        var c = probe(scale);
        c.enter(.lash);
        c.t = LASH_WIND + LASH_STRIKE;
        c.ext = 1.0;
        c.pose();
        const seg = c.protSeg();
        const y = seg[1].y - c.pos.y;
        // Inside his capsule all the way down, and CLEAR OF THE TURF so the pad is not ploughing it.
        try std.testing.expect(y > foe.HERO_LOW);
        try std.testing.expect(y < foe.HERO_HIGH);
        try std.testing.expect(y > 0.08 * scale);
        const reach = mathx.distXZ(seg[0], seg[1]);
        std.debug.print("\n  slime x{d:.2}: the shaft crosses him at {d:.2} m off his feet, {d:.2} m out — shin height, and the dose takes the feet\n", .{ scale, y, reach });
    }
}

test "THE WINDOW SITS ON THE IMPACT FRAME — what `toImpact` promises is when the shaft actually bills" {
    const dt: f32 = 1.0 / 120.0;
    var worst: f32 = 0;
    var missed: usize = 0;
    var thrown: usize = 0;
    for ([_]f32{ wf.FOE_SCALE_LO, 1.0, wf.FOE_SCALE_HI }) |scale| {
        const near = foe.closestApproach(BODY_R * scale) + 0.05;
        for ([_]f32{ 0.0, 0.35, 0.7, 1.0 }) |u| {
            const stand = lerpF(near, lashBand(scale) - 0.01, u);
            if (stand <= near - 0.001 or classify(stand, 0, 0, scale, true, false) != Choice.lash) continue;
            thrown += 1;
            const hero = v3(0, 0, stand);

            var a = probe(scale);
            a.enter(.lash);
            var lie: f32 = 0;
            var guard: usize = 0;
            while (guard < 2000) : (guard += 1) {
                // `toImpact` reads the stamped position: without it the clock is solved for a hero stood on the slime.
                a.parry = .{ .at = hero, .facing = std.math.pi };
                const before = a.toImpact();
                _ = a.update(dt, hero, 400.0, .{});
                if (a.heroHit != null) {
                    lie = before orelse 0;
                    break;
                }
                if (a.state != .lash) break;
            }
            worst = @max(worst, @abs(lie));

            var b = probe(scale);
            b.enter(.lash);
            guard = 0;
            while (guard < 2000) : (guard += 1) {
                b.parry = .{ .live = true, .active = true, .at = hero, .facing = std.math.pi };
                _ = b.update(dt, hero, 400.0, .{});
                if (b.parried) break;
                if (b.state != .lash) break;
            }
            if (!b.parried) {
                missed += 1;
                std.debug.print("\n  x{d:.2} at {d:.2} m: a shield held the whole stroke caught NOTHING — the clock was {d:.3} s out at the bill\n", .{ scale, stand, lie });
            }
        }
    }
    std.debug.print("\n  slime: {d} stands, the impact clock is at worst {d:.3} s off the frame the shaft bills, {d} uncatchable\n", .{ thrown, worst, missed });
    try std.testing.expectEqual(@as(usize, 0), missed);
    try std.testing.expect(worst <= dt * 2.0);
}

test "A BEARING THE WIND CANNOT COME ROUND TO IS REFUSED AT THE CHOOSE — and what it falls through to TURNS, then lands" {
    const stand = lashBand(1.0) - 0.3;
    try std.testing.expectEqual(Choice.lash, classify(stand, LASH_SWEEP - 1.0, 0, 1.0, true, false));
    try std.testing.expectEqual(Choice.close, classify(stand, LASH_SWEEP + 1.0, 0, 1.0, true, false));
    try std.testing.expectEqual(Choice.rest, classify(stand, -LASH_SWEEP - 1.0, 0, 1.0, true, true));

    const dt: f32 = 1.0 / 60.0;
    var thrown: usize = 0;
    var slowest: f32 = 0;
    var deg: f32 = 0;
    while (deg <= 180.0) : (deg += 15.0) {
        var s = probe(1.0);
        s.lashCd = 0;
        const a = mathx.radians(deg);
        const hero = mathx.ground(mathx.sinf(a) * stand, mathx.cosf(a) * stand);
        var t: f32 = 0;
        var swung = false;
        var hit = false;
        while (t < 4.0 and !(swung and s.state != .lash)) : (t += dt) {
            _ = s.update(dt, hero, 400.0, .{});
            const apart = foe.closestApproach(s.bodyR());
            if (mathx.distXZ(s.pos, hero) < apart) {
                const back = mathx.dirXZ(hero, s.pos);
                s.pos = v3(hero.x + back.x * apart, s.pos.y, hero.z + back.z * apart);
            }
            if (s.state == .lash) swung = true;
            if (s.heroHit != null) hit = true;
        }
        if (!hit) {
            std.debug.print("\n  slime: stood {d:.0} deg off, the first lash billed nothing\n", .{deg});
            return error.TestUnexpectedResult;
        }
        slowest = @max(slowest, t);
        thrown += 1;
    }
    std.debug.print("\n  slime gate: the lash is refused past {d:.1} deg off; the first one lands from all {d} bearings, the slowest by {d:.2} s\n", .{ LASH_SWEEP, thrown, slowest });
}

test "THE SHAFT DRAWN IS THE SHAFT BILLED — the lean tips the mass, never the protrusion" {
    const dt: f32 = 1.0 / 120.0;
    for ([_]f32{ wf.FOE_SCALE_LO, 1.0, wf.FOE_SCALE_HI }) |scale| {
        var s = probe(scale);
        s.lashCd = 0;
        const hero = mathx.ground(0, lashBand(scale) - 0.2);
        var worst: f32 = 0;
        var lean: f32 = 0;
        var t: f32 = 0;
        while (t < 2.0) : (t += dt) {
            _ = s.update(dt, hero, 400.0, .{});
            if (s.ext <= 0.02) continue;
            const seg = s.protSeg();
            const tip = foe.markOn(s.xf[PROT], v3(0, 0, PROT_LEN));
            const base = foe.markOn(s.xf[PROT], mathx.zero3);
            worst = @max(worst, @max(mathx.lenV(mathx.subV(tip, seg[1])), mathx.lenV(mathx.subV(base, seg[0]))));
            lean = @max(lean, s.posed[1]);
        }
        std.debug.print("\n  slime x{d:.2}: drawn shaft within {d:.4} m of the billed one through a {d:.1} deg lean", .{ scale, worst, lean });
        try std.testing.expect(lean > 5.0);
        try std.testing.expect(worst < 0.005);
    }
    std.debug.print("\n", .{});
}

test "A BODY THAT HAS GONE STILL FLIES ITS MOTES OUT — and the split's own ooze survives the slot it was thrown from" {
    const dt: f32 = 1.0 / 60.0;
    const far = mathx.ground(0, 40);
    var s = probe(1.0);
    smack(&s, HP_MAX * 2.0);
    try std.testing.expectEqual(State.dead, s.state);
    var guard: usize = 0;
    while (!s.gone and guard < 600) : (guard += 1) _ = s.update(dt, far, 400.0, .{});
    try std.testing.expect(s.gone);
    const inFlight = liveMotes(&s.parts);
    try std.testing.expect(inFlight > 0);
    var t: f32 = 0;
    while (t < 2.0) : (t += dt) _ = s.update(dt, far, 400.0, .{});
    try std.testing.expectEqual(@as(usize, 0), liveMotes(&s.parts));

    var mire = Mire{ .model = undefined };
    mire.n = 1;
    mire.slimes[0] = probe(1.0);
    mire.slimes[0].debugSplit();
    guard = 0;
    while (mire.n == 1 and guard < 400) : (guard += 1) _ = mire.update(dt, far, 400.0, .{});
    var motes: usize = 0;
    for (mire.liveConst()) |*c| motes += liveMotes(&c.parts);
    try std.testing.expect(motes >= SPLIT_OOZE);
    std.debug.print("\n  slime: {d} dissolve motes still flying when the body went, all spent 2 s later; {d} ooze motes in flight the frame it divides\n", .{ inFlight, motes });
}

fn liveMotes(pool: []const foe.Particle) usize {
    var n: usize = 0;
    for (pool) |*q| {
        if (q.life > 0) n += 1;
    }
    return n;
}
