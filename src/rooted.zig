const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const foe = @import("foe.zig");
const wf = @import("worldfmt.zig");
const sfx = @import("audio.zig");
const art = @import("propart.zig");
const wood = @import("propwood.zig");

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

// THE DISGUISE IS THE SNAG'S OWN PALETTE AND THE SNAG'S OWN LIMB BUILDER (`wood.deadLimbInto`). Not a
// lookalike — the same code, so a `snag` standing beside one of these cannot be told from it.
const BARK_OLD = art.BARK_OLD;
const BARK_DK = art.BARK_DK;
const TIMBER = art.TIMBER;
const TIMBER_DK = art.TIMBER_DK;
const MOSS_DK = art.MOSS_DK;
/// THE ONE THING THAT GIVES IT AWAY: two embers down two knot-holes, and the only warm colour on a dead tree.
const EYE_DIM = rgba(120, 42, 14, 255);
const EYE_LIT = rgba(255, 132, 42, 255);
const SPLINTER = rgba(84, 66, 44, 235);
/// A LIMB IS A BIG SMOOTH SUNWARD FACE — 0.28 of a metre thick and near three long — so it needs a
/// near-black albedo where the snag`s thin 0.13 stubs get away with `BARK_DK` (AGENTS.md). At the stub`s own
/// tone these came back pale tan beside the real trees they are pretending to be.
const LIMB_BARK = rgba(13, 10, 8, 255);
const LIMB_LT = rgba(24, 19, 15, 255);

/// Its own stature, in metres — sized against `propwood.snagMesh`'s own 6.0..7.6 so it stands in a line of
/// them without being the tall one.
pub const H: f32 = 6.9;

/// It NOTICES this far, and it never comes. Its own moves reach further than the ring that wakes it
/// (`WAKE_R`), which is the trap: crossing four metres unfolds it, and backing off to five does not save you.
pub const AGGRO_R: f32 = 6.8;
const WAKE_R: f32 = 4.2;
/// **THE EYES OPEN OUT HERE** (owner's call), which is a metre and a half OUTSIDE its longest reach — so the
/// warning arrives while you can still act on it, and walking in past this ring is a choice you made with two
/// embers looking at you. Asleep it is a dead tree; this is the only step between the two.
const EYES_R: f32 = 6.5;
/// …and it folds up again out here. Past the eyes' own ring, because THE COUNTER IS LEAVING and a fight you
/// can walk out of has to actually let go of you — lids included.
const SLEEP_R: f32 = 8.2;

const BODY_R: f32 = 0.62; // a trunk: you cannot walk through it and it cannot be shouldered off its spot
/// THE HURT SPHERE IS LOW ON THE BOLE, and it has to be: the hero swings a capsule off his own shoulder, so
/// a sphere at the middle of a seven-metre tree is one a sword cannot reach. This spans his knees to his
/// reach, which is the band every other creature is hit in.
const HURT_R: f32 = 1.25;
const CENTER_F: f32 = 0.17;
const TOP_F: f32 = 0.96;
/// The reticle's seat in the BOLE's own frame: the face, between the two knot-holes. On the bole and not on
/// an eye, because the eyes ROTATE as they open and a mark that opened with them would slide off the tree.
const LOCK_AT = v3(0, 0.30 * H, 0.34);

/// TOUGH, AND DELIBERATELY EXPENSIVE TO SHOOT. It cannot chase, so a bow at range is free damage and the only
/// thing between that and a trivial kill is the size of the bill: at 130 it costs nine of ten plain shafts.
/// FIRE is the honest answer — five fire arrows do it, which is exactly how many you carry.
const HP_MAX: f32 = 130.0;
const POISE_MAX: f32 = 28.0; // a tree does not flinch at a sword
const STANCE_MAX: f32 = 40.0; // …but chained blows do break it, and that is the whole punish window
/// DEAD DRY WOOD. Fire is not a soft counter here, it is the counter; lightning splits it; cold and rot have
/// already had their turn.
const RESISTS = combat.resists(.{ .fire = -70, .cold = 40, .lightning = -20, .chaos = 30 });
pub const SOULS: u32 = 150;

const DEATH_DUR: f32 = 1.9; // it comes apart slowly and it is a long way down
const DISS_DUR: f32 = 1.1;
const DISSOLVE = foe.Dissolve{ .rate = 62.0, .spread = 1.15, .rise = 0.85, .flake = SPLINTER };

// THE THREE MOVES. Every band is covered, so standing anywhere inside its ring is answered — you do not kite
// this thing, you close on it or you leave.

pub const SLAM_HIT = combat.Hit{ .dmg = 34, .poise = 26, .stance = 10 };
pub const SWEEP_HIT = combat.Hit{ .dmg = 26, .poise = 20 };
/// THE HOOK. Light on damage because the damage is not the point: it is the DRAG, and being pulled back
/// inside the slam's own band is what it costs you.
pub const HOOK_HIT = combat.Hit{ .dmg = 14, .poise = 14 };
/// How far in it yanks him. Blocked, he keeps his ground (`game.applyYank`) — the boards are the answer to
/// a hook, which is the one place a shield beats leaving.
pub const DRAG_PULL: f32 = 3.4;

const Attack = struct {
    windDur: f32,
    strikeDur: f32,
    recoverDur: f32,
    cd: f32,
    minR: f32,
    maxR: f32,
    /// Half-arc either side of the facing this move's blow covers. Per MOVE, because a vertical slam has
    /// no business billing something off its shoulder that a horizontal scythe honestly crosses.
    arc: f32,
    hit: combat.Hit,
    /// Which limb swings it, and how the pose reads it.
    limb: usize,
};

pub const SLAM: usize = 0;
pub const SWEEP: usize = 1;
pub const HOOK: usize = 2;
/// Wind-ups are LONG — it is a tree, and its reach is what makes it dangerous. Every one clears
/// `foe.TELL_MIN`; the test at the foot of this file pins that. The bands are MEASURED off the posed tip:
/// the old 7.4 m hook billed a blow off a limb that passed three metres over his head.
const MOVES = [_]Attack{
    .{ .windDur = 0.86, .strikeDur = 0.26, .recoverDur = 0.95, .cd = 3.4, .minR = 0, .maxR = 2.4, .arc = 46.0, .hit = SLAM_HIT, .limb = LIMB_H },
    .{ .windDur = 0.70, .strikeDur = 0.32, .recoverDur = 0.80, .cd = 2.8, .minR = 1.2, .maxR = 3.8, .arc = 82.0, .hit = SWEEP_HIT, .limb = LIMB_L },
    .{ .windDur = 0.66, .strikeDur = 0.30, .recoverDur = 1.15, .cd = 5.0, .minR = 2.8, .maxR = 4.6, .arc = 58.0, .hit = HOOK_HIT, .limb = LIMB_R },
};

/// A move's clock, for anything aiming at a beat inside it (`shots.zig`) — the shared shape, off this table.
pub fn moveClock(which: usize) foe.Clock {
    return foe.moveClock(MOVES[@min(which, MOVES.len - 1)]);
}


const WAKE_DUR: f32 = 0.95; // the unfold, and it is the biggest tell in the game
const SLEEP_DUR: f32 = 1.30; // …folding back is slower, because nothing is chasing it

const SWAY_HZ: f32 = 0.21; // awake, the bole works against its own roots
const SWAY_DEG: f32 = 3.2;
/// …and it is heard on this cadence while it is awake. THINNED from 2.6: the creak is what says the thing is
/// alive, and once it has said so a second time you know. Its own `wood_creak` is under the floor besides.
const CREAK_EVERY: f32 = 4.4;
/// How fast the lids move. SLOW — an eye that snaps open is a jump-scare, and this one has to be NOTICED:
/// about a second and a half from bark to ember.
const EYES_RATE: f32 = 0.7;
/// …and how far a lid swings off its hollow when it does.
const LID_SWING: f32 = 96.0;

const PARTS = 56;

// The rig. Sixteen bones and not one that walks.
const N = 16;
const ROOT = 0; // the base, and it never moves
const BOLE = 1;
const BOLE2 = 2;
/// THE LIDS. Each is a shutter of bark over a knot-hole cut into the bole itself, and it is the BONE that
/// opens — the hollow and its ember stay where they are and the bark swings off them.
const LID_L = 3;
const LID_R = 4;
const LIMB_L = 5; // three segments each, front-left / front-right / overhead
const LIMB_R = 8;
const LIMB_H = 11;
const CLAW_L = 14; // two of the surface roots, which heave as it wakes
const CLAW_R = 15;
const SEGS = 3;

const EYE_Y: f32 = 0.30 * H;
const EYE_HALF: f32 = 0.21;
const EYE_Z: f32 = 0.34;

const BOLE_Y: f32 = 0.42 * H;
const BOLE2_Y: f32 = 0.34 * H;
/// Where a limb roots on the bole, and how long each of its three segments is.
const LIMB_Y = [_]f32{ 0.46 * H, 0.42 * H, 0.60 * H };
const LIMB_A = [_]f32{ 52.0, -58.0, 6.0 }; // bearing off the trunk's own front
/// THE LIMB IS AS LONG AS ITS REACH SAYS — and no longer. At 0.40/0.36/0.30 the three spanned 7.3 m: poles
/// crossing the whole clearing, hovering three metres over the hero's head while the hurt test billed him
/// anyway. 4.1 m of limb plus the bole's own LUNGE covers the hook's 5.0, and the tip test measures it.
const SEG_LEN = [_]f32{ 0.24 * H, 0.20 * H, 0.15 * H };

const REST = blk: {
    var r = [_]rl.Vector3{mathx.zero3} ** N;
    r[BOLE] = v3(0, 0, 0);
    r[BOLE2] = v3(0, BOLE_Y, 0);
    r[LID_L] = v3(EYE_HALF, EYE_Y, EYE_Z);
    r[LID_R] = v3(-EYE_HALF, EYE_Y, EYE_Z);
    for ([_]usize{ LIMB_L, LIMB_R, LIMB_H }, 0..) |b, i| {
        const a = mathx.radians(LIMB_A[i]);
        r[b] = v3(@sin(a) * 0.34, LIMB_Y[i], @cos(a) * 0.34);
        r[b + 1] = v3(0, 0, SEG_LEN[0]);
        r[b + 2] = v3(0, 0, SEG_LEN[1]);
    }
    r[CLAW_L] = v3(0.34, 0.30, 0.16);
    r[CLAW_R] = v3(-0.34, 0.26, -0.10);
    break :blk r;
};

const State = enum { dormant, wake, idle, wind, strike, recover, sleep, stunlight, stunheavy, dead };

/// PURE DECISION — a function of range and cooldowns, so the bands are testable without a world.
const Choice = enum { sleep, hold, slam, sweep, hook };
fn classify(dist: f32, ready: [MOVES.len]bool) Choice {
    if (dist > SLEEP_R) return .sleep;
    // NEAREST BAND FIRST: at three metres the slam and the sweep both answer, and the slam is the one that
    // should — a tree with something inside its guard brings the heavy limb down.
    if (dist <= MOVES[SLAM].maxR and ready[SLAM]) return .slam;
    if (dist >= MOVES[SWEEP].minR and dist <= MOVES[SWEEP].maxR and ready[SWEEP]) return .sweep;
    if (dist >= MOVES[HOOK].minR and dist <= MOVES[HOOK].maxR and ready[HOOK]) return .hook;
    return .hold;
}

/// What one frame of this thing did that the world outside it has to answer for.
pub const Act = union(enum) {
    none,
    /// A limb landed. `pull` is the HOOK's drag, 0 for the other two.
    struck: struct { hit: combat.Hit, pull: f32 },
};

pub const Model = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        var mat = rl.loadMaterialDefault() catch @panic("rooted material");
        mat.shader = shader;
        return .{ .mesh = buildMeshes(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, t: *const Rooted) void {
        for (0..N) |i| rl.drawMesh(self.mesh[i], self.mat, t.xf[i]);
    }
};

pub const Rooted = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// Stamped from outside like every creature's. Its FEET are the half that cannot matter here — the thing
    /// never travels — but the BITE is billed through the same `foe.grip`, so it is taken like everyone else's.
    root: combat.Root = .{},
    /// THE RIME BREATH'S COLD (`combat.Chill`) — billed through the same `foe.grip` the roots are. Its travel
    /// half is meaningless on a thing that never moves; the BITE is not.
    chill: combat.Chill = .{},
    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,

    state: State = .dormant,
    t: f32 = 0,
    elapsed: f32 = 0,
    atk: usize = SLAM,
    dealt: bool = false,
    cds: [MOVES.len]f32 = [_]f32{0} ** MOVES.len,
    creakT: f32 = 0,

    /// 0 = a dead tree, 1 = unfolded. Drives every limb, the bole's rise and the claws together.
    open: f32 = 0,
    /// …and the LIDS, which are their own channel and open FIRST: the eyes are the warning and the unfold is
    /// the fight, so one cannot be the other's fraction.
    eyes: f32 = 0,
    /// How far through the live move's own arc the swinging limb is, −1 (cocked back) … 1 (thrown through).
    swing: f32 = 0,
    /// …and the swing one and two JOINTS late (exponential followers, ticked every frame): the elbow arrives
    /// after the shoulder and the tip after the elbow, through every state including the stuns. Three segments
    /// peaking on one frame read as one welded paddle however big the arc — the staggered-lags law.
    swingL1: f32 = 0,
    swingL2: f32 = 0,
    sway: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3, // read by `foe.wounded` and never spent: it is rooted
    justDied: bool = false,
    /// WHO IT IS FIGHTING (`foe.Threat`) — embedded here and stamped by the game, `Leash`'s own law.
    threat: foe.Threat = .{},
    fade: f32 = 0,
    gone: bool = false,

    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    xf: [N]rl.Matrix = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Rooted {
        var t = Rooted{ .pos = home, .home = home, .facing = faceYaw, .scale = scale, .seed = seed };
        t.fxRng = foe.fxStream(seed, 40961.0, 0x700D);
        t.creakT = seed * CREAK_EVERY;
        t.pose();
        return t;
    }

    pub fn centerWorld(self: *const Rooted) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H, self.scale, 0);
    }
    pub fn lockPoint(self: *const Rooted) rl.Vector3 {
        return foe.markOn(self.xf[BOLE], LOCK_AT);
    }
    pub fn topWorld(self: *const Rooted) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * H, self.scale, 0);
    }
    pub fn hurtRadius(self: *const Rooted) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Rooted) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Rooted) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Rooted) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Rooted) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    /// It never leaves the ground and it never travels, so nothing here is ever airborne.
    pub fn airborne(self: *const Rooted) bool {
        _ = self;
        return false;
    }
    pub fn flashFrac(self: *const Rooted) f32 {
        return foe.flashFrac(self.flash);
    }
    /// ASLEEP IT IS SCENERY: not lockable, and no bar over it. `game.canSee` and the reticle both ask this,
    /// because a reticle offering to fix on a tree is the disguise given away for nothing.
    pub fn hidden(self: *const Rooted) bool {
        return self.state == .dormant;
    }
    /// Are the lids up? Its own question: a dormant one with its eyes open is exactly the state the warning
    /// exists to be seen in. Nothing reads it yet — it is what a cue or a shot predicate would ride, and
    /// neither exists, so do not take it for a wired-up state (`shroom.Cluster.fuming`'s note).
    pub fn watching(self: *const Rooted) bool {
        return self.eyes > 0.5;
    }

    /// Where the live move's limb tip is — what the reach is measured from and where its splinters fly off.
    pub fn tipWorld(self: *const Rooted) rl.Vector3 {
        const b = MOVES[@min(self.atk, MOVES.len - 1)].limb;
        return foe.markOn(self.xf[b + SEGS - 1], v3(0, 0, SEG_LEN[SEGS - 1]));
    }

    fn move(self: *const Rooted) Attack {
        return MOVES[@min(self.atk, MOVES.len - 1)];
    }

    pub fn update(self: *Rooted, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) Act {
        _ = bounds; // it does not travel, so there is no play area to be held inside
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return .none;
        }
        self.justDied = false;
        // THE ROOTS' OWN BITE (foe.grip). The FEET half is a no-op on a thing that never travels, but the
        // grip is also what BILLS the hold's chaos every frame — left out, a cast on this creature was
        // eighteen focus for no damage and a `combat.Root` clock that never ran down.
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        self.flash = mathx.maxF(0, self.flash - dt);
        for (&self.cds) |*c| c.* = mathx.maxF(0, c.* - dt);
        self.leash.tick(dt, 0, mathx.distXZ(self.home, hero), AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);

        var act: Act = .none;
        const d = mathx.distXZ(self.pos, hero);

        switch (self.state) {
            // A DEAD TREE. It does not turn, it does not sway, and nothing about it is a creature until the
            // hero is inside `WAKE_R` — or until a blade finds it, which is the reward for suspecting one.
            .dormant => {
                self.open = mathx.approach(self.open, 0, dt * 1.6);
                self.swing = mathx.approach(self.swing, 0, dt * 2.0);
                if (d <= WAKE_R) self.beginWake(hero);
            },
            .wake => {
                // `max`, never a bare assign: woken mid-FOLD (a blade in a sleeping one) the unfold picks
                // up from wherever the fold had got to — assigned, the limbs snapped shut for a frame first.
                self.open = mathx.maxF(self.open, mathx.smoothstep(0, WAKE_DUR, self.t));
                self.faceToward(hero, dt);
                if (self.t >= WAKE_DUR) self.enter(.idle);
            },
            .idle => {
                self.open = mathx.approach(self.open, 1.0, dt * 3.0);
                self.swing = mathx.approach(self.swing, 0, dt * 2.4);
                self.faceToward(hero, dt);
                self.decide(d);
            },
            .wind => {
                const a = self.move();
                self.faceToward(hero, dt);
                // Cocked back over the whole wind — the reach is long enough that the only warning you get
                // is the limb going the other way first.
                self.swing = -mathx.smoothstep(0, a.windDur, self.t);
                if (self.t >= a.windDur) {
                    sfx.world(.wood_swing, self.tipWorld());
                    self.enter(.strike);
                }
            },
            .strike => {
                const a = self.move();
                const u = mathx.clampF(self.t / a.strikeDur, 0, 1);
                self.swing = lerpF(-1.0, 1.0, foe.swingCurve(u));
                if (!self.dealt and u >= 0.40 and self.reaches(hero, a)) {
                    self.dealt = true;
                    self.leash.noteCombat();
                    sfx.world(.wood_hit, self.tipWorld());
                    self.splinters(self.tipWorld(), 10);
                    act = .{ .struck = .{ .hit = a.hit, .pull = if (self.atk == HOOK) DRAG_PULL else 0 } };
                }
                if (self.t >= a.strikeDur) self.enter(.recover);
            },
            .recover => {
                self.swing = mathx.approach(self.swing, 0, dt * 2.2);
                self.faceToward(hero, dt);
                if (self.t >= self.move().recoverDur) self.decide(d);
            },
            // FOLDING BACK. Nothing is chasing it, so it takes its time — and it is scenery again at the end,
            // which is what lets you walk back into the same clearing and be caught by the same tree.
            .sleep => {
                self.open = 1.0 - mathx.smoothstep(0, SLEEP_DUR, self.t);
                self.swing = mathx.approach(self.swing, 0, dt * 1.6);
                if (d <= WAKE_R) return self.wokeAgain(hero, dt, blade);
                if (self.t >= SLEEP_DUR) {
                    self.open = 0;
                    self.enter(.dormant);
                }
            },
            .stunlight => {
                self.swing = mathx.approach(self.swing, 0, dt * 3.0);
                if (self.t >= combat.FOE_LIGHT_STUN_DUR) self.enter(.idle);
            },
            .stunheavy => {
                self.swing = mathx.approach(self.swing, -0.25, dt * 2.0);
                if (self.t >= combat.FOE_HEAVY_STUN_DUR) self.enter(.idle);
            },
            .dead => {
                self.open = mathx.approach(self.open, 0.35, dt * 0.7);
                self.swing = mathx.approach(self.swing, 0.6, dt * 0.8);
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
        }

        // The elbow chases the shoulder, the tip chases the elbow — see `swingL1`.
        self.swingL1 = mathx.approach(self.swingL1, self.swing, dt * 11.0);
        self.swingL2 = mathx.approach(self.swingL2, self.swingL1, dt * 11.0);
        // THE LIDS TRACK THE RING AND NOT THE STATE: they come up as he crosses `EYES_R` whether it is
        // asleep, awake or mid-fold, which is what makes them a warning rather than a consequence.
        self.eyes = mathx.approach(self.eyes, if (d <= EYES_R and self.state != .dead) 1 else 0, dt * EYES_RATE);
        self.creak(dt);
        self.sway = mathx.sinf((self.elapsed + self.seed * 6.0) * SWAY_HZ * std.math.tau) * SWAY_DEG * self.open;
        self.pose();
        self.tryHit(blade);
        return act;
    }

    /// Woken out of the fold — the one path back that is not a fresh `beginWake`, so the unfold picks up from
    /// wherever it had got to rather than starting over from a tree.
    fn wokeAgain(self: *Rooted, hero: rl.Vector3, dt: f32, blade: foe.Blade) Act {
        self.enter(.idle);
        self.faceToward(hero, dt);
        self.pose();
        self.tryHit(blade);
        return .none;
    }

    /// Is he inside this move's own band — the right RANGE and inside the ARC this blow honestly covers?
    pub fn reaches(self: *const Rooted, hero: rl.Vector3, a: Attack) bool {
        const d = mathx.distXZ(self.pos, hero);
        if (d > (a.maxR + foe.HERO_REACH) * self.scale) return false;
        const to = mathx.dirXZ(self.pos, hero);
        if (mathx.lenXZ(to) < 1e-4) return true;
        return combat.withinArc(mathx.headingXZ(to), self.facing, a.arc);
    }

    fn faceToward(self: *Rooted, target: rl.Vector3, dt: f32) void {
        // SLOWLY: the bole twists on its own roots, it does not pivot. Turning is a real cost here, and
        // getting round behind it is the whole reason to close.
        foe.faceToward(self.pos, &self.facing, target, 1.5, dt);
    }

    fn enter(self: *Rooted, s: State) void {
        self.state = s;
        self.t = 0;
        self.dealt = false;
    }

    fn beginWake(self: *Rooted, hero: rl.Vector3) void {
        self.facing = mathx.headingXZ(mathx.dirXZ(self.pos, hero));
        sfx.world(.wood_wake, self.centerWorld());
        self.enter(.wake);
    }

    fn decide(self: *Rooted, dist: f32) void {
        var ready: [MOVES.len]bool = undefined;
        for (&ready, self.cds) |*r, c| r.* = c <= 0;
        switch (classify(dist, ready)) {
            .sleep => self.enter(.sleep),
            .hold => self.enter(.idle),
            .slam => self.begin(SLAM),
            .sweep => self.begin(SWEEP),
            .hook => self.begin(HOOK),
        }
    }

    fn begin(self: *Rooted, which: usize) void {
        self.atk = which;
        self.cds[which] = MOVES[which].cd;
        // THE TELL IS HEARD AS WELL AS SEEN: the whole bole groans as it gathers, on the wind's first
        // frame — the strike already had its own voice and the wind had nothing.
        sfx.world(.wood_creak, self.centerWorld());
        self.enter(.wind);
    }

    /// The bole working against its roots — heard while it is awake, and never while it is a tree.
    fn creak(self: *Rooted, dt: f32) void {
        if (self.open < 0.4 or self.state == .dead) return;
        self.creakT -= dt;
        if (self.creakT > 0) return;
        self.creakT = CREAK_EVERY * self.fxRng.range(0.7, 1.4);
        sfx.world(.wood_creak, self.centerWorld());
    }

    fn enterStun(self: *Rooted, s: State) void {
        self.enter(s);
        self.vit.beginStun(if (s == .stunheavy) .heavy else .light);
    }

    fn enterDeath(self: *Rooted) void {
        self.state = .dead;
        self.t = 0;
        self.justDied = true;
    }

    pub fn debugKill(self: *Rooted) void {
        self.enterDeath();
    }
    pub fn debugStagger(self: *Rooted, heavy: bool) void {
        self.open = 1;
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    /// Stage a beat of a move for the harness — a photograph of a limb mid-arc cannot be got by waiting.
    pub fn debugMove(self: *Rooted, which: usize) void {
        self.open = 1;
        self.begin(which);
    }
    pub fn debugWake(self: *Rooted) void {
        self.enter(.wake);
    }

    pub fn tryHit(self: *Rooted, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        // A BLADE IN IT WAKES IT. Finding one before it finds you is the whole payoff for suspecting a tree,
        // and it is paid in the free opening the unfold gives you.
        if (self.state == .dormant or self.state == .sleep) self.beginWake(mathx.addV(self.pos, mathx.scaleV(s.dir, -1)));
        // NOTHING SHOVES IT. `foe.wounded` writes the field either way; handed a real number it would slide
        // a thing whose whole design is that it cannot move.
        const heavy = foe.wounded(self, s, blade, .{ .light = 0, .heavy = 0 });
        self.splinters(s.contact, if (heavy) 16 else 9);
        sfx.world(.wood_hurt, s.contact);
        switch (s.reaction) {
            .death => {
                sfx.world(.wood_die, self.centerWorld());
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn emit(self: *Rooted, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
        foe.emitParticle(&self.parts, &self.fxHead, p, vel, life, r0, r1, col, grav);
    }

    fn splinters(self: *Rooted, at: rl.Vector3, n: i32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.6, 1.0) * 3.2;
            self.emit(
                v3(at.x + self.fxRng.signed() * 0.1, at.y + self.fxRng.signed() * 0.1, at.z + self.fxRng.signed() * 0.1),
                v3(mathx.cosf(a) * sp, self.fxRng.range(1.2, 3.6), mathx.sinf(a) * sp),
                self.fxRng.range(0.32, 0.62),
                self.fxRng.range(0.025, 0.055) * self.scale,
                0.008,
                if (self.fxRng.float() < 0.4) TIMBER else SPLINTER,
                7.0,
            );
        }
    }

    /// THE EMBER, and it is the whole tell. Faint asleep, bright awake, brightest through a wind-up — drawn
    /// unlit over the opaque pass because the mesh's emissive is a fixed vertex channel and cannot brighten.
    pub fn drawFx(self: *const Rooted) void {
        foe.drawParticles(&self.parts);
        if (self.gone or self.eyes <= 0.02) return;
        const cocked = if (self.state == .wind) mathx.clampF(-self.swing, 0, 1) else 0;
        const lit = mathx.clampF(0.30 * self.open + 0.35 * cocked, 0, 1);
        const a = self.eyes; // the lid is what lets any of it out
        const r = 0.072 * self.scale;
        for ([_]f32{ 1, -1 }) |side| {
            const p = foe.markOn(self.xf[BOLE], v3(side * EYE_HALF, EYE_Y, EYE_Z + 0.04));
            rl.drawSphereEx(p, r * a * (1.0 + 0.25 * lit), 8, 10, mathx.withAlpha(mathx.lerpColor(EYE_DIM, EYE_LIT, lit), mathx.u8f(255.0 * a)));
            rl.drawSphereEx(p, r * a * (2.2 + 1.4 * lit), 8, 10, mathx.withAlpha(EYE_LIT, mathx.u8f(64.0 * a * (0.4 + 0.6 * lit))));
        }
    }

    pub fn draw(self: *const Rooted, model: *const Model) void {
        model.draw(self);
    }

    pub fn pose(self: *Rooted) void {
        const fs = self.scale * (1.0 - 0.55 * self.fade);
        const root = mul3(
            scaleM(fs, fs, fs),
            ry(mathx.degrees(self.facing)),
            tr(self.pos.x, self.pos.y, self.pos.z),
        );
        self.xf[ROOT] = root;

        // THE BODY ANSWERS PER MOVE, and it is most of the tell: the old wind drifted one limb a few degrees
        // and left seven metres of tree stone still. The slam REARS the whole bole back and drives it through;
        // the sweep COILS it on its roots; the hook leans out and hauls back in. The bole's throw is real REACH.
        const swinging = self.state == .wind or self.state == .strike or self.state == .recover;
        const cock = if (swinging) mathx.clampF(-self.swingL1, 0, 1) else 0;
        const thru = if (swinging) mathx.clampF(self.swingL1, 0, 1) else 0;
        var boleRx: f32 = 0;
        var boleRy: f32 = 0;
        if (swinging) switch (self.atk) {
            SLAM => boleRx = -9.0 * cock + 16.0 * thru,
            SWEEP => {
                boleRy = -24.0 * cock + 26.0 * thru;
                boleRx = 4.0 * thru;
            },
            else => { // HOOK
                boleRx = 10.0 * cock - 5.0 * thru;
                boleRy = 10.0 * cock - 14.0 * thru;
            },
        };

        // THE BOLE RISES AND LEANS AS IT OPENS. Asleep it is plumb and dead; awake it stands INTO him, which
        // is most of what says the tree has become a creature.
        const lean = 9.0 * self.open + self.sway + boleRx;
        self.xf[BOLE] = mul(mul3(ry(boleRy * 0.5), rx(lean * 0.45), place(REST[BOLE])), root);
        self.xf[BOLE2] = mul(mul3(ry(boleRy * 0.5), rx(lean * 0.55), place(REST[BOLE2])), self.xf[BOLE]);

        // THE LIDS SWING UP OFF THEIR HOLLOWS, each about its own outer edge, so the two open apart rather
        // than both sliding the same way — which is a shutter and not an eye.
        inline for ([_]usize{ LID_L, LID_R }, [_]f32{ 1, -1 }) |b, side| {
            self.xf[b] = mul(mul3(rz(side * LID_SWING * 0.25 * self.eyes), rx(-LID_SWING * self.eyes), place(REST[b])), self.xf[BOLE]);
        }

        // THE LIMBS. Asleep each one droops against the trunk on its own axis, which is exactly where a snag's
        // dead limbs sit; opening swings them out into the raptorial hang — IN TURN, front-left first and the
        // overhead last, because three limbs unfolding on one shared fraction is machinery.
        inline for ([_]usize{ LIMB_L, LIMB_R, LIMB_H }, 0..) |b0, i| {
            const fi: f32 = @floatFromInt(i);
            const live = swinging and self.move().limb == b0;
            const overhead = b0 == LIMB_H;
            const openI = mathx.clampF((self.open - 0.14 * fi) / (1.0 - 0.14 * fi), 0, 1);
            for (0..SEGS) |seg| {
                const s: f32 = if (!live) 0 else switch (seg) {
                    0 => self.swing,
                    1 => self.swingL1,
                    else => self.swingL2,
                };
                const st = mathx.clampF(s, 0, 1);
                const pitch = lerpF(LIMB_SHUT[seg], LIMB_OPEN[seg], openI);
                // SEGMENT 0 CARRIES THE BEARING. Without it every limb chains along the bole`s own +Z and
                // three of them come out of the same face of the trunk pointing the same way.
                const yaw = if (seg == 0) LIMB_A[i] else 0;
                const m = if (overhead)
                    // The slam: cocked it REARS up past the crown, thrown it CRASHES down through — the
                    // sign that used to point the heavy limb at the sky on the frame it billed a crush.
                    mul3(ry(yaw), rx(pitch - SLAM_REAR[seg] * mathx.clampF(-s, 0, 1) + SLAM_DROP[seg] * st), place(REST[b0 + seg]))
                else blk: {
                    // A scythe: drawn back along its own bearing, whipped across the front — and it DIPS
                    // through the blow, or a horizontal arc at shoulder height passes clean over the man
                    // it is billed on. The elbow unfolds through the strike, so the reach arrives WITH it.
                    const dip = DIP[seg] * (if (live and self.state == .strike) (1.0 - s * s) else 0);
                    break :blk mul3(ry(yaw + LIMB_ARC[seg] * s * yawSign(i)), rx(pitch + dip + EXT[seg] * st), place(REST[b0 + seg]));
                };
                self.xf[b0 + seg] = mul(m, if (seg == 0) self.xf[BOLE] else self.xf[b0 + seg - 1]);
            }
        }

        // The surface roots heave as it wakes and settle back as it sleeps.
        const heave = 22.0 * self.open;
        self.xf[CLAW_L] = mul(mul(rx(-heave), place(REST[CLAW_L])), root);
        self.xf[CLAW_R] = mul(mul(rx(-heave * 0.7), place(REST[CLAW_R])), root);
    }
};

/// PER SEGMENT, AND THEY ARE PITCHES THAT ADD UP. Folded, the three hang down the bole, which is exactly where
/// a snag's dead limbs sit. Open they make the RAPTORIAL hang — down-forward, elbow re-folded up, claw dropped
/// — a mantis's arms, not scaffolding. One pair per segment lerped by `open`.
const LIMB_SHUT = [_]f32{ 74.0, 12.0, 10.0 };
const LIMB_OPEN = [_]f32{ 24.0, -34.0, 52.0 };
/// How much of the swing each joint yaws through. Shoulder-heavy — the WHIP now comes from the followers'
/// time lag, not from the elbow out-rotating the shoulder on the same frame.
const LIMB_ARC = [_]f32{ 38.0, 30.0, 20.0 };
/// The scythe's mid-stroke dip and its through-stroke elbow extension, in degrees of pitch per segment.
const DIP = [_]f32{ 0.0, 18.0, 26.0 };
const EXT = [_]f32{ 0.0, 26.0, -14.0 };
/// The slam limb's rear (cocked, up past the crown) and drop (thrown, down through the band).
const SLAM_REAR = [_]f32{ 26.0, 18.0, 12.0 };
const SLAM_DROP = [_]f32{ 30.0, 30.0, 16.0 };

fn yawSign(i: usize) f32 {
    return if (i == 0) -1 else 1;
}

fn place(p: rl.Vector3) rl.Matrix {
    return tr(p.x, p.y, p.z);
}


fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = baseMesh();
    mesh[BOLE] = boleMesh(0);
    mesh[BOLE2] = boleMesh(1);
    mesh[LID_L] = lidMesh(0);
    mesh[LID_R] = lidMesh(1);
    inline for ([_]usize{ LIMB_L, LIMB_R, LIMB_H }, 0..) |b0, i| {
        for (0..SEGS) |seg| mesh[b0 + seg] = limbMesh(i, seg);
    }
    mesh[CLAW_L] = clawMesh(0);
    mesh[CLAW_R] = clawMesh(1);
    return mesh;
}

/// The flare where it meets the ground, plus the ring of surface roots the two moving claws sit among — so
/// the two that heave are not the only roots it has.
fn baseMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x2007ED);
    b.setMat(.wood);
    b.addCapsule(v3(0, 0, 0), v3(0, 0.10 * H, 0), 0.78, 0.62, 9, BARK_OLD);
    var r: i32 = 0;
    while (r < 6) : (r += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(r)) / 6.0 + rng.signed() * 0.3;
        b.addCapsule(
            v3(0, 0.40, 0),
            v3(mathx.cosf(a) * rng.range(0.9, 1.5), 0.04, mathx.sinf(a) * rng.range(0.9, 1.5)),
            0.19,
            0.055,
            5,
            BARK_OLD,
        );
    }
    b.setMat(.plant);
    var g: i32 = 0;
    while (g < 4) : (g += 1) art.tuftInto(&b, &rng, rng.signed() * 1.4, rng.signed() * 1.4, 0.9);
    return b.toMesh();
}

/// One of the two trunk segments, dressed exactly as `propwood.snagMesh` dresses its own — the ring of
/// broken stubs, the dead limbs through the shared builder, and the moss up one side.
fn boleMesh(seg: usize) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x80BE + @as(u64, seg));
    b.setMat(.wood);
    const len: f32 = if (seg == 0) BOLE_Y else BOLE2_Y;
    const r0: f32 = if (seg == 0) 0.62 else 0.42;
    const r1: f32 = if (seg == 0) 0.44 else 0.27;
    b.addCapsule(v3(0, 0, 0), v3(0, len, 0), r0, r1, 9, if (seg == 0) LIMB_LT else LIMB_BARK);
    // The stub ring, uneven, sunk most of the way in — RELIEF IS SUBTLE.
    var s: i32 = 0;
    while (s < 7) : (s += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(s)) / 7.0 + rng.signed() * 0.24;
        const y0 = rng.range(0.1, len * 0.85);
        const y1 = @min(y0 + rng.range(0.5, len * 0.5), len - 0.1);
        const rr = lerpF(r0, r1, y0 / len) * 0.94;
        b.addCapsule(
            v3(mathx.cosf(a) * rr, y0, mathx.sinf(a) * rr),
            v3(mathx.cosf(a + rng.signed() * 0.15) * rr, y1, mathx.sinf(a + rng.signed() * 0.15) * rr),
            rng.range(0.05, 0.09),
            rng.range(0.03, 0.06),
            5,
            if (rng.float() < 0.7) BARK_DK else TIMBER,
        );
    }
    // …and the dead limbs, through the ONE builder both leafless trees call, so a snag beside this cannot be
    // told from it. Short and drooping — they are dressing, not the limbs that reach.
    var l: i32 = 0;
    while (l < 3) : (l += 1) {
        const y = rng.range(len * 0.3, len * 0.9);
        wood.deadLimbInto(&b, &rng, v3(0, y, 0), rng.angle(), rng.range(0.6, 1.2), rng.range(0.1, 0.35), 0.13, rng.intn(2));
    }
    if (seg == 1) {
        // The broken crown: a blunt snap of pale heartwood and a few splinters standing off it.
        b.addBlob(v3(0, len - 0.02, 0), v3(0.24, 0.06, 0.24), 3, 7, TIMBER);
        var k: i32 = 0;
        while (k < 4) : (k += 1) {
            const a = rng.angle();
            const d = rng.range(0.04, 0.2);
            b.addCapsule(
                v3(mathx.cosf(a) * d, len, mathx.sinf(a) * d),
                v3(mathx.cosf(a) * d * 1.9, len + rng.range(0.25, 0.9), mathx.sinf(a) * d * 1.9),
                rng.range(0.06, 0.13),
                0.015,
                4,
                if (rng.float() < 0.45) TIMBER else BARK_DK,
            );
        }
    }
    b.setMat(.plant);
    b.addBlob(v3(mathx.cosf(1.9) * r0 * 0.6, rng.range(0.4, len * 0.7), mathx.sinf(1.9) * r0 * 0.6), v3(0.28, 0.36, 0.24), 3, 6, MOSS_DK);
    return b.toMesh();
}

/// A LID: a scab of bark that covers its hollow when shut and swings off it when open. Uneven and
/// asymmetric, so the two do not read as a manufactured pair.
fn lidMesh(which: usize) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x11D0 + @as(u64, which));
    b.setMat(.wood);
    const w = 0.165 * rng.range(0.9, 1.1);
    b.addBlob(v3(0, 0, 0.02), v3(w, w * rng.range(0.62, 0.8), 0.055), 4, 9, BARK_OLD);
    b.addBlob(v3(rng.signed() * 0.05, w * 0.4, 0.05), v3(w * 0.5, w * 0.22, 0.03), 3, 6, BARK_DK);
    return b.toMesh();
}

/// One limb segment, authored along its own +Z: a tapered capsule with a knuckle at the far end and twigs
/// off the outer half. Nothing straight and nothing ending in a point — the tip is a blunt snap.
fn limbMesh(limb: usize, seg: usize) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x11B0 + @as(u64, limb) * 7 + @as(u64, seg));
    b.setMat(.wood);
    const len = SEG_LEN[seg];
    const r0 = 0.23 - 0.06 * @as(f32, @floatFromInt(seg));
    const r1 = r0 * 0.72;
    // THE JOINT BALL. Every segment hinges at its own origin, and a bare hinge opens a wedge of sky the
    // moment it bends — the mesh half of the old "disjointed" read. The ogre's `limb` has the same ball.
    b.addBlob(v3(0, 0, 0), v3(r0 * 1.14, r0 * 1.14, r0 * 0.96), 4, 9, LIMB_LT);
    // A KINK IN THE SEGMENT, not just between segments: one straight capsule per bone is a chain of elbows.
    const bend = v3(rng.signed() * len * 0.10, rng.signed() * len * 0.08, len * 0.55);
    b.addCapsule(v3(0, 0, 0), bend, r0, lerpF(r0, r1, 0.55), 7, LIMB_BARK);
    b.addCapsule(bend, v3(bend.x * 1.3, bend.y * 1.2, len), lerpF(r0, r1, 0.55), r1, 7, LIMB_BARK);
    b.addBlob(bend, v3(r0 * 0.9, r0 * 0.9, r0 * 0.7), 3, 7, LIMB_LT); // the knuckle, one step up so the kink reads
    if (seg == SEGS - 1) {
        b.addBlob(v3(bend.x * 1.3, bend.y * 1.2, len), v3(r1 * 1.5, r1 * 1.3, r1 * 1.1), 3, 6, TIMBER);
        // …and the hooks at the very end, which is what a limb takes hold of you with.
        var h: i32 = 0;
        while (h < 3) : (h += 1) {
            const a = rng.angle();
            const o = v3(bend.x * 1.3, bend.y * 1.2, len);
            b.addCapsule(
                o,
                v3(o.x + mathx.cosf(a) * len * 0.18, o.y + mathx.sinf(a) * len * 0.18, len + len * rng.range(0.12, 0.26)),
                r1 * 0.6,
                r1 * 0.22,
                5,
                TIMBER_DK,
            );
        }
    }
    var t: i32 = 0;
    while (t < 2) : (t += 1) {
        const u = rng.range(0.45, 0.9);
        const from = v3(bend.x * u * 1.2, bend.y * u * 1.1, len * u);
        const a = rng.angle();
        const tl = len * rng.range(0.22, 0.4);
        b.addCapsule(
            from,
            v3(from.x + mathx.cosf(a) * tl, from.y + mathx.sinf(a) * tl * 0.6, from.z + tl * 0.5),
            r1 * 0.5,
            r1 * 0.18,
            5,
            LIMB_BARK,
        );
    }
    return b.toMesh();
}

fn clawMesh(which: usize) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xC1A0 + @as(u64, which));
    b.setMat(.wood);
    const len: f32 = if (which == 0) 1.5 else 1.2;
    const kink = v3(rng.signed() * 0.2, -0.10, len * 0.6);
    b.addCapsule(v3(0, 0, 0), kink, 0.20, 0.13, 6, BARK_OLD);
    b.addCapsule(kink, v3(kink.x * 1.4, -0.24, len), 0.13, 0.05, 6, BARK_OLD);
    b.addBlob(v3(kink.x * 1.4, -0.24, len), v3(0.07, 0.06, 0.06), 3, 6, TIMBER_DK);
    return b.toMesh();
}


const CAP = wf.MAX_PER_KIND;

pub const Grove = struct {
    model: Model,
    trees: [CAP]Rooted = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Grove {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Grove) []Rooted {
        return self.trees[0..self.n];
    }
    pub fn liveConst(self: *const Grove) []const Rooted {
        return self.trees[0..self.n];
    }
    pub fn reset(self: *Grove, m: *const wf.Map) void {
        foe.resetGroup(Rooted, &self.trees, &self.n, m, .rooted);
    }
    pub fn setShader(self: *Grove, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn draw(self: *const Grove, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Grove) void {
        for (self.liveConst()) |*t| t.drawFx();
    }

    /// `yank` is the HOOK's drag, and it is handed the pull rather than applying it: only `game` knows
    /// whether the blow was blocked, and a blocked hook must not move him.
    pub fn update(
        self: *Grove,
        dt: f32,
        hero: rl.Vector3,
        bounds: f32,
        blade: foe.Blade,
        ctx: anytype,
        comptime yank: fn (@TypeOf(ctx), rl.Vector3, f32) void,
    ) ?foe.Blow {
        var blow: ?foe.Blow = null;
        for (self.live()) |*t| {
            switch (t.update(dt, t.threat.aim(hero), bounds, blade)) {
                .none => {},
                .struck => |s| {
                    foe.worseBlow(&blow, s.hit, t.pos, t.threat.on);
                    // The BLOW goes up as the return value like every other group's; the hook hands over
                    // only what is its own — where it pulls from and how far.
                    if (s.pull > 0) yank(ctx, t.pos, s.pull);
                },
            }
        }
        return blow;
    }

    pub fn pierce(self: *Grove, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Grove) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Grove) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Grove) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Grove) u32 {
        return foe.aliveCount(self.liveConst());
    }
};


test "it is scenery until you walk into it, and scenery again when you leave" {
    var t = Rooted.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(t.hidden()); // asleep: not lockable, no bar, no creature
    try std.testing.expectApproxEqAbs(@as(f32, 0), t.open, 1e-4);

    // Outside the waking ring it stays a tree however long you stand there.
    var k: u32 = 0;
    while (k < 240) : (k += 1) _ = t.update(1.0 / 60.0, v3(0, 0, WAKE_R + 2.0), 400, .{});
    try std.testing.expect(t.hidden());

    // …and inside it, it unfolds.
    _ = t.update(1.0 / 60.0, v3(0, 0, WAKE_R - 0.5), 400, .{});
    try std.testing.expect(!t.hidden());
    k = 0;
    while (k < 90) : (k += 1) _ = t.update(1.0 / 60.0, v3(0, 0, WAKE_R - 0.5), 400, .{});
    try std.testing.expect(t.open > 0.9);

    // LEAVING IS THE COUNTER: walk out past `SLEEP_R` and it folds back up to scenery.
    k = 0;
    while (k < 400) : (k += 1) _ = t.update(1.0 / 60.0, v3(0, 0, SLEEP_R + 3.0), 400, .{});
    try std.testing.expect(t.hidden());
    try std.testing.expectApproxEqAbs(@as(f32, 0), t.open, 1e-3);
}

test "THE GRIP BITES A ROOTED TOO, and it lets go of its own accord" {
    // Its feet were never the point, but the hold's chaos is billed through the same `foe.grip` every other
    // creature takes — without it a cast on this one was eighteen focus for nothing and a clock that never ran.
    var t = Rooted.spawn(mathx.zero3, 0, 1.0, 0.3);
    const full = t.vit.hp;
    t.root.grab();
    try std.testing.expect(t.root.held());
    var k: f32 = 0;
    while (k < combat.ROOT_HOLD + 0.2) : (k += 1.0 / 60.0) _ = t.update(1.0 / 60.0, v3(0, 0, 30), 400, .{});
    try std.testing.expect(!t.root.held()); // …and it expires rather than latching on for the fight
    // Chaos at +30 on this table, so the span's ~14 comes in around ten — a real bite, not the full figure.
    const paid = full - t.vit.hp;
    try std.testing.expect(paid > 0.5 * combat.ROOT_HOLD * combat.ROOT_DPS);
    try std.testing.expect(paid < combat.ROOT_HOLD * combat.ROOT_DPS);
}

test "IT NEVER MOVES, whatever is done to it" {
    var t = Rooted.spawn(v3(3, 0, -4), 0, 1.0, 0.3);
    const was = t.pos;
    var k: u32 = 0;
    while (k < 600) : (k += 1) _ = t.update(1.0 / 60.0, v3(3, 0, -2), 400, .{});
    try std.testing.expectEqual(was, t.pos);
    // …and a blow does not shove it either: `foe.wounded` is handed a zero pair on purpose.
    t.shove = mathx.zero3;
    _ = t.update(1.0 / 60.0, v3(3, 0, -2), 400, .{
        .active = true,
        .a = t.centerWorld(),
        .b = t.centerWorld(),
        .a0 = t.centerWorld(),
        .b0 = t.centerWorld(),
        .r = 0.2,
        .hit = .{ .dmg = 5, .poise = 1 },
    });
    try std.testing.expect(t.hits > 0); // it WAS hit…
    try std.testing.expectEqual(mathx.zero3, t.shove); // …and it did not budge
    try std.testing.expectEqual(was, t.pos);
}

test "a blade in a sleeping one wakes it — the reward for suspecting a tree" {
    var t = Rooted.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(t.hidden());
    const c = t.centerWorld();
    _ = t.update(1.0 / 60.0, v3(0, 0, WAKE_R + 4.0), 400, .{
        .active = true,
        .a = c,
        .b = c,
        .a0 = c,
        .b0 = c,
        .r = 0.2,
        .hit = .{ .dmg = 9, .poise = 3 },
    });
    try std.testing.expect(!t.hidden()); // …out of range, and awake anyway
}

test "every band is answered, so it cannot be kited" {
    const all = [_]bool{ true, true, true };
    var d: f32 = 0;
    while (d <= MOVES[HOOK].maxR) : (d += 0.2) {
        try std.testing.expect(classify(d, all) != .hold);
    }
    try std.testing.expectEqual(Choice.slam, classify(1.0, all));
    try std.testing.expectEqual(Choice.sweep, classify(3.0, all));
    try std.testing.expectEqual(Choice.hook, classify(4.4, all));
    try std.testing.expectEqual(Choice.sleep, classify(SLEEP_R + 0.1, all));
    // …and its reach OUTLASTS the ring that woke it, which is what makes crossing it a commitment.
    try std.testing.expect(MOVES[HOOK].maxR > WAKE_R);
    try std.testing.expect(SLEEP_R > MOVES[HOOK].maxR);
    // On cooldown it waits rather than falling through to a move it cannot make.
    try std.testing.expectEqual(Choice.hold, classify(1.0, [_]bool{ false, false, false }));
}

test "A LIMB GOES WHERE ITS BILL SAYS: the tip crosses the hero column, out near the band's edge" {
    // The old tree's whole dishonesty in one number: a hook billed at 7.4 m off a limb whose tip hung
    // 2.8 m over the hero's head. Walk each move's strike and measure the POSED tip — it must come down
    // into the column a sword-carrier occupies, and it must get near the range it charges for.
    for (0..MOVES.len) |which| {
        const a = MOVES[which];
        var t = Rooted.spawn(mathx.zero3, 0, 1.0, 0.3);
        const hero = v3(0, 0, a.maxR - 0.3);
        t.debugMove(which);
        var minY: f32 = 99;
        var maxR: f32 = 0;
        var fr: u32 = 0;
        while (fr < 200) : (fr += 1) {
            _ = t.update(1.0 / 60.0, hero, 400, .{});
            if (t.state != .strike and t.state != .recover) continue;
            const tip = t.tipWorld();
            minY = mathx.minF(minY, tip.y);
            maxR = mathx.maxF(maxR, mathx.distXZ(t.pos, tip));
            if (t.state == .recover and t.t > 0.3) break;
        }
        try std.testing.expect(minY < 1.55); // it comes DOWN through him, not over his hat
        try std.testing.expect(maxR + foe.HERO_REACH >= a.maxR - 0.2); // and it arrives at what it bills
    }
}

test "no attack comes out of nowhere, and the hook is the one that drags" {
    for (MOVES) |m| try std.testing.expect(m.windDur >= foe.TELL_MIN);
    try std.testing.expect(DRAG_PULL > 0);
    // The hook is LIGHT: what it costs you is the position, not the health.
    try std.testing.expect(HOOK_HIT.raw() < SWEEP_HIT.raw());
    try std.testing.expect(SWEEP_HIT.raw() < SLAM_HIT.raw());
    // …and being dragged `DRAG_PULL` in from the hook's own outer band leaves you inside the sweep's.
    try std.testing.expect(MOVES[HOOK].maxR - DRAG_PULL <= MOVES[SWEEP].maxR);
}

test "the mark rides the KNOT, and the knot rides the bole" {
    var t = Rooted.spawn(mathx.zero3, 0, 1.0, 0.3);
    t.open = 0;
    t.pose();
    const asleep = t.lockPoint();
    t.open = 1;
    t.sway = SWAY_DEG;
    t.pose();
    const awake = t.lockPoint();
    // The bole leans as it opens, so the eye moves with it — a fixed height would hold the reticle still
    // over something visibly rearing up.
    try std.testing.expect(mathx.lenV(mathx.subV(asleep, awake)) > 0.05);
}

test "shooting it dead costs the whole quiver, which is what stands in for a ranged answer" {
    // It cannot chase, so a bow past its reach is free damage — the only thing between that and a trivial
    // kill is the bill. Plain shafts: most of a full quiver. Fire: about exactly the five you carry.
    const plain = HP_MAX / 16.0; // heromod.ARROW_HIT.dmg
    try std.testing.expect(plain > 7.0 and plain <= combat.ARROWS_MAX);
    var v = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    const fire = combat.Hit{ .dmg = 16, .elem = combat.elems(.{ .fire = 8 }) };
    var shots: u32 = 0;
    while (!v.dead and shots < 40) : (shots += 1) _ = v.hit(fire);
    try std.testing.expect(shots <= combat.FIRE_ARROWS_MAX + 1);
}
