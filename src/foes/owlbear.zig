const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const sfx = @import("../core/audio.zig");

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

// THE OWLBEAR (owner's creature, owner's brief) — a carved stone owl on a bear's frame, sat in the ruins as
// masonry until you walk up to it.
//
// **THE FIRST CONSTRUCT.** `foe.Nature.construct` was a named row with nothing filed under it; this is what
// it was named for. Everything else on this field is grown, raised or born.
//
// **DORMANT IT IS THE STATUE, NOT A CREATURE PRETENDING TO BE ONE.** No bar, no reticle, and a blade RINGS
// OFF IT — you cannot open on it, and nothing you do at range starts the fight. What starts the fight is
// standing near it. The rooted's mimicry is a disguise you can see through and stab; this is stone until it
// decides otherwise, which is a different promise and a harder one to keep honest.
//
// **THE EYES ARE THE WHOLE TELL, AND THEY LEAD THE BODY.** `EYE_LEAD` of the wake is two lights coming up in
// a carving that has not moved yet — long enough to back out of `WAKE_R` and leave it sitting there.
//
// **AWAKE IT IS A TOUGH MELEE FIGHTER**, and tough is spent on POISE and HP rather than on speed: it is a
// tonne of rock that swings twice and does not flinch off a light.
//
// **AND IT WILL NOT BE CROWDED.** Inside `BURST_R` it JUMPS BACK and looses a fan of stone quills on the way,
// which is the one thing it does that answers a man already inside its arms.

/// Its own stature, in metres. Over the birchwight's 2.15 and well under the rooted's 6.9: a statue you look
/// up at, on a plinth-less perch, and still a body a sword reaches all of.
pub const H: f32 = 2.60;

const HIP_HALF = heromod.HIP_HALF * 1.24;
const SHOULDER_HALF = heromod.SHOULDER_HALF * 1.32;
const REST = heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);

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
/// The wings ARE the arms. Bone 17 is never posed and never drawn — `Model.draw` walks `0..HELD`.
const HELD = heromod.HELD;

/// A TALON PLATE, not a boot. Wide and short: the thing stands like a bird, on two spread feet.
const solePatches = [_]heromod.SolePatch{
    .{ .bone = ANKL, .heel = 0.044 * H, .toe = 0.126 * H, .halfW = 0.070 * H, .drop = 0.022 * H },
    .{ .bone = ANKR, .heel = 0.044 * H, .toe = 0.126 * H, .halfW = 0.070 * H, .drop = 0.022 * H },
};

// **IT IS MASONRY, SO IT IS AUTHORED AT MASONRY'S OWN TONE** — over the beasts, under the birch's 92, and
// COOL where every hide on this field is warm. The lichen is the only colour on it and the eyes are the only
// light; a statue that reads grey from ten metres is the one that pays off when it stands up.
const STONE = rgba(74, 72, 69, 255);
const STONE_LT = rgba(98, 96, 92, 255);
const STONE_DK = rgba(38, 37, 35, 255);
const GRANITE = rgba(58, 57, 55, 255);
const LICHEN = rgba(52, 62, 40, 255);
const LICHEN_LT = rgba(72, 84, 54, 255);
const BEAK = rgba(88, 78, 58, 255);
const BEAK_LT = rgba(116, 104, 78, 255);
const SOCKET = rgba(18, 17, 16, 255);
/// Cold, and near enough the socket to be a hole in the carving rather than an eye that is merely shut.
const EYE_COLD = rgba(30, 32, 34, 255);
/// …and lit. An owl's amber, and the ONE bright thing on the body — the whole wake is read off these two dots.
const EYE_LIT = rgba(255, 196, 86, 255);
const DUST = rgba(96, 92, 86, 235);
const CHIP = rgba(66, 64, 61, 240);

pub const AGGRO_R: f32 = 12.0;
const HOME_R: f32 = 2.2;
/// **HOW NEAR IS NEAR.** Well inside `AGGRO_R`, because the wake is not the sighting: it has to be a thing
/// you walked up to. Also outside `BURST_R` and both melee bands, so nothing can be woken already swinging.
const WAKE_R: f32 = 4.6;

const WALK_SPEED: f32 = heromod.WALK_SPEED * 0.62;
const CHASE_SPEED: f32 = heromod.WALK_SPEED * 1.02;
const ACCEL: f32 = 3.2;
const TURN_RATE: f32 = 2.1;

const BODY_R: f32 = 0.52;
const HURT_R: f32 = 0.88;
const CENTER_F: f32 = 0.54;
const TOP_F: f32 = 1.04;
const LOCK_AT = v3(0, 0.06 * H, 0);

/// **TOUGH IS HP AND POISE, NOT SPEED** (owner: a tough melee fighter). Between the rooted's 130, which cannot
/// chase, and the birchwight's 180, which is a slower thing than this.
const HP_MAX: f32 = 165.0;
/// **STONE DOES NOT FLINCH OFF A POKE.** Over the hero's heavy (22), so a committed swing is worth about one
/// and a half and a light is worth nothing on its own — the pool is what it shrugs off inside the refill.
const POISE_MAX: f32 = 30.0;
const STANCE_MAX: f32 = 46.0;
/// A rock: fire does nothing to it, cold cracks it, and lightning finds it standing in the open.
const RESISTS = combat.resists(.{ .fire = 55, .cold = -45, .lightning = -30, .chaos = 25 });
pub const SOULS: u32 = 240;

const DEATH_DUR: f32 = 1.45;
const DISS_DUR: f32 = 1.05;
const SHOVE_DECAY: f32 = 7.0;
/// It goes back to being rubble — grit, not motes, and it falls further than a body of flesh does.
const DISSOLVE = foe.Dissolve{ .rate = 54.0, .spread = 0.75, .rise = 0.45, .flake = CHIP };

pub const SHOVE = foe.Push{ .light = 0.55, .heavy = 1.35 };

// **THE WAKE.** One scalar, `rouse` 0..1, and everything the statue does on the way up is a share of it. The
// eyes come first and the stone second, which is what makes the tell a warning rather than an announcement.

const WAKE_DUR: f32 = 1.25;
/// The share of the wake the EYES have to themselves — half of it, near enough, and it is the whole warning:
/// 0.62 s of two lights in a carving that has not moved.
const EYE_LEAD: f32 = 0.50;
/// …and the same on the way down, when the leash sends it back to its perch and it seats itself again.
const SEAT_DUR: f32 = 1.60;
/// **IT ONLY GOES BACK TO STONE AT HOME.** Anywhere else a re-seat is a body that healed by walking away.
const SEAT_R: f32 = 0.85;

comptime {
    // The eyes have to lead by a real tell or the wake is one event and there is nothing to read.
    std.debug.assert(WAKE_DUR * EYE_LEAD >= foe.TELL_MIN * 2.0);
}

// **THE TWO CLOSE MOVES.** A fast rake and a slow slam, and they do not share a band: the rake answers a man
// at arm's length, the slam a man who stood still for it.

const Attack = struct {
    windDur: f32,
    strikeDur: f32,
    recoverDur: f32,
    cd: f32,
    minR: f32,
    maxR: f32,
    frontDot: f32,
    hit: combat.Hit,
};

pub const RAKE: usize = 0;
pub const SLAM: usize = 1;

pub const RAKE_HIT = combat.Hit{ .dmg = 19, .poise = 20, .stance = 8 };
/// **A TONNE OF ROCK COMING DOWN.** The launch is the same one the rooted's slam carries; it is the only
/// thing this creature does that puts a man in the air.
pub const SLAM_HIT = combat.Hit{ .dmg = 33, .poise = 32, .stance = 16, .launch = combat.SLAM_LAUNCH };

/// Every wind clears `foe.TELL_MIN`, and the slam's is nearly a second: the thing is slow and the reach is
/// what makes it dangerous.
const MOVES = [_]Attack{
    .{ .windDur = 0.58, .strikeDur = 0.20, .recoverDur = 0.52, .cd = 2.3, .minR = 0, .maxR = 2.45, .frontDot = 0.40, .hit = RAKE_HIT },
    .{ .windDur = 0.94, .strikeDur = 0.24, .recoverDur = 0.98, .cd = 5.2, .minR = 0, .maxR = 2.20, .frontDot = 0.52, .hit = SLAM_HIT },
};

/// Where in a strike the talons arrive, as a share of it — the ONE frame the boards are asked about, read
/// from one constant so the blow and the parry cannot disagree about when it happened.
const IMPACT_K: f32 = 0.42;

comptime {
    const named = .{ .{ RAKE, RAKE_HIT }, .{ SLAM, SLAM_HIT } };
    if (named.len != MOVES.len) @compileError("owlbear: MOVES and the named indices disagree on how many strikes there are");
    for (named) |row| {
        if (!std.meta.eql(MOVES[row[0]].hit, row[1])) @compileError("owlbear: a named index no longer points at its own row of MOVES");
    }
    for (MOVES) |mv| std.debug.assert(mv.windDur >= foe.TELL_MIN);
}

pub fn moveClock(which: usize) foe.Clock {
    return foe.moveClock(MOVES[@min(which, MOVES.len - 1)]);
}

// **THE BURST — THE JUMP BACK, AND THE QUILLS GO WITH IT** (owner: a jump back where he launches feathers at
// you). It is the answer to being crowded and nothing else: it opens a gap it does not want closed, and it
// bills the ground it just left.

/// Inside this it would rather leave than swing. UNDER both melee bands on purpose — a man at rake distance
/// gets raked, a man in its chest gets jumped away from.
const BURST_R: f32 = 1.55;
const BURST_CD: f32 = 7.5;
const BURST_GATHER: f32 = 0.22;
const BURST_FLIGHT: f32 = 0.52;
const BURST_LAND: f32 = 0.38;
/// Metres of the hop and how high it carries. It clears its own `BURST_R` several times over, so the move
/// buys real ground and not a shuffle.
const BURST_DIST: f32 = 5.4;
const BURST_RISE: f32 = 0.58;
/// Where in the flight the quills leave, as a share of it — at the TOP of the arc, which is the frame the
/// picture and the fan agree on.
const BURST_LOOSE_K: f32 = 0.45;

comptime {
    std.debug.assert(BURST_GATHER >= foe.TELL_MIN * 0.6);
    std.debug.assert(BURST_DIST > BURST_R * 3.0);
}

pub const QUILLS_PER_BURST: usize = 5;
/// Degrees of the whole fan, and it is WIDE — a narrow one is a thing you walk out of sideways without
/// deciding to. Half of this each side of the bearing it left on.
const QUILL_FAN: f32 = 62.0;
pub const QUILL_R: f32 = 0.075;
/// **UNDER A SPRINT AND OVER A WALK.** `hero.SPRINT_SPEED` is 5.1: a quill at 12.5 cannot be outrun in a
/// straight line, which is what makes the fan a thing you cross rather than a thing you flee. It does not
/// home — the deer's spore is the homing shot, and two of those would be one creature written twice.
pub const QUILL_SPEED: f32 = 12.5;
/// Seconds in the air. At 12.5 m/s this is 16 m of reach, past `AGGRO_R` — the fan is spent by distance, not
/// by the clock, and the clock is only there so nothing lives forever.
pub const QUILL_LIFE: f32 = 1.3;
/// Metres it DROPS over its own life, as a share of the drop a thrown thing would take. Small: a stone quill
/// is heavy and fast, and a visible arc on a 1.3 s shot reads as a lobbed rock.
const QUILL_FALL: f32 = 1.6;
/// Three of these land for 33 raw, under one slam — a fan you eat whole is worse than a swing and better
/// than the launch, which is the right price for standing in it.
pub const QUILL_HIT = combat.Hit{ .dmg = 11, .poise = 10, .stance = 4 };

const SWAY_HZ: f32 = 0.26;
const SWAY_DEG: f32 = 2.1;
const A_PROT: f32 = 1.2;
const PELVIS_SHARE: f32 = 1.0 / 6.0;

const HIT_CHIP_LIGHT = 6;
const HIT_CHIP_HEAVY = 13;
const WAKE_GRIT: usize = 22;
const PARTS = 74;
comptime {
    std.debug.assert(@as(f32, PARTS) >= @as(f32, @floatFromInt(WAKE_GRIT + foe.hitParts(HIT_CHIP_HEAVY) + foe.WOUND_PARTS)));
}

/// `stone` is the statue, `wake` the stand-up, `seat` the sit-down. The rest is an ordinary fighter.
const State = enum { stone, wake, seat, idle, walk, rake, slam, burst, stunlight, stunheavy, dead };

const Choice = enum { rest, hold, close, rake, slam, burst };

fn classify(gap: f32, sensed: f32, homeGap: f32, rakeReady: bool, slamReady: bool, burstReady: bool, rooted: bool) Choice {
    if (sensed > AGGRO_R) return if (homeGap > HOME_R) .hold else .rest;
    // **THE BURST IS ASKED FIRST AND IT IS ASKED ABOUT ONE THING** — a man this close. Below the melee bands,
    // so it can never take a stand the rake or the slam had a better answer for.
    if (gap <= BURST_R and burstReady and !rooted) return .burst;
    if (gap <= MOVES[SLAM].maxR and slamReady) return .slam;
    if (gap <= MOVES[RAKE].maxR and rakeReady) return .rake;
    if (rooted) return .rest;
    return .close;
}

pub const Model = struct {
    bone: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        return .{ .bone = buildBones(), .mat = gfx.material(shader, "owlbear") };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, o: *const Owlbear) void {
        for (0..HELD) |i| rl.drawMesh(self.bone[i], self.mat, o.xf[i]);
    }
};

pub const Owlbear = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    post: foe.Post = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},

    facing: f32 = 0,
    /// The bearing the carving was set on, which is the one it seats itself back onto.
    perchYaw: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,

    state: State = .stone,
    t: f32 = 0,
    elapsed: f32 = 0,
    speed: f32 = 0,

    /// **0 IS THE STATUE AND 1 IS THE CREATURE**, and every dial on the wake is a share of it: the eyes, the
    /// unlocking of the pose, whether a blade bites and whether the reticle finds it. One scalar, so the
    /// picture cannot promise a fight the mechanic has not started.
    rouse: f32 = 0,
    /// One-frame edge for the beat the eyes come up on.
    justWoke: bool = false,

    rakeCd: f32 = 0,
    slamCd: f32 = 0,
    burstCd: f32 = 0,
    /// The hop's own lift, in metres. `pose` adds it to the pelvis and `airborne` is asked of it.
    hop: f32 = 0,
    /// The bearing the burst committed to, and whether its quills have gone yet.
    burstYaw: f32 = 0,
    loosed: bool = false,
    /// One-frame edge the `Perch` reads to put a fan in the air, and where from.
    threw: bool = false,
    threwFrom: rl.Vector3 = mathx.zero3,

    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    heroLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    heroHit: ?combat.Hit = null,
    justDied: bool = false,
    parry: foe.Parry = .{},
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

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Owlbear {
        var o = Owlbear{ .pos = home, .home = home, .facing = faceYaw, .perchYaw = faceYaw, .scale = scale, .seed = seed };
        o.fxRng = foe.fxStream(seed, 51407.0, 0x0B1B);
        o.aiRng = foe.fxStream(seed, 33119.0, 17);
        o.rakeCd = seed * 0.8;
        o.pose();
        return o;
    }

    pub fn centerWorld(self: *const Owlbear) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H, self.scale, self.hop);
    }
    pub fn lockPoint(self: *const Owlbear) rl.Vector3 {
        return foe.markOn(self.xf[CHEST], LOCK_AT);
    }
    pub fn topWorld(self: *const Owlbear) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * H, self.scale, self.hop);
    }
    pub fn hurtRadius(self: *const Owlbear) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Owlbear) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Owlbear) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Owlbear) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Owlbear) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    /// The hop is the only thing that leaves the ground, and only past the shared lift.
    pub fn airborne(self: *const Owlbear) bool {
        return self.hop > foe.AIRBORNE_LIFT;
    }
    pub fn flashFrac(self: *const Owlbear) f32 {
        return foe.flashFrac(self.flash);
    }
    pub fn kind(_: *const Owlbear) wf.FoeKind {
        return .owlbear;
    }

    /// **STONE IS NOT A CREATURE TO LOOK AT** — no reticle and no bar while the carving is still a carving.
    /// It is DRAWN throughout: that is the whole point of it, and `game.disguised` asks this about lock-on
    /// alone.
    pub fn hidden(self: *const Owlbear) bool {
        return self.rouse < 1.0 and self.state != .dead;
    }
    /// …and SEPARATE from being solid, which it is at every value of `rouse`. A statue is a thing you walk
    /// into, and one you could walk through would give the disguise away before the eyes did.
    pub fn phased(_: *const Owlbear) bool {
        return false;
    }

    /// **HOW LIT THE EYES ARE**, 0..1 — the first half of the wake has them to itself, and they are the only
    /// thing that has moved by the time a player still has room to leave.
    pub fn eyeGlow(self: *const Owlbear) f32 {
        if (self.state == .dead) return 0;
        return mathx.clampF(self.rouse / EYE_LEAD, 0, 1);
    }
    /// …and how far the BODY has come up. Nothing before `EYE_LEAD`, so the carving holds its pose through
    /// the whole warning.
    fn woke(self: *const Owlbear) f32 {
        return mathx.smoothstep(EYE_LEAD, 1.0, self.rouse);
    }

    pub fn navWant(self: *const Owlbear, quarry: rl.Vector3) ?rl.Vector3 {
        if (self.state != .idle and self.state != .walk) return null;
        if (foe.senseHero(&self.leash, self.pos, quarry, AGGRO_R) <= AGGRO_R) return quarry;
        if (foe.postAim(self)) |go| return go;
        return if (mathx.distXZ(self.pos, foe.homeFor(self)) > HOME_R) self.home else null;
    }

    fn faceToward(self: *Owlbear, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }

    fn row(self: *const Owlbear) Attack {
        return MOVES[if (self.state == .slam) SLAM else RAKE];
    }

    /// -1 hauled back, +1 driven through, easing off across the recovery. One curve for both close moves —
    /// they differ in their clock and their band, not in the shape of the stroke.
    fn strokeAmt(self: *const Owlbear) f32 {
        if (self.state != .rake and self.state != .slam) return 0;
        const mv = self.row();
        if (self.t < mv.windDur) return -mathx.smoothstep(0, mv.windDur * 0.94, self.t);
        const s = self.t - mv.windDur;
        if (s < mv.strikeDur) return lerpF(-1.0, 1.0, foe.swingCurve(s / mv.strikeDur));
        return 1.0 - mathx.smoothstep(mv.strikeDur, mv.strikeDur + mv.recoverDur * 0.7, s);
    }

    /// 0..1 of the hop's own flight, which is what the lift and the loose are both read off.
    fn leapU(self: *const Owlbear) f32 {
        if (self.state != .burst) return 0;
        return mathx.clampF((self.t - BURST_GATHER) / BURST_FLIGHT, 0, 1);
    }

    fn stunAmount(self: *const Owlbear) f32 {
        if (self.state != .stunlight and self.state != .stunheavy) return 0;
        return foe.stunCurve(self.t, self.state == .stunheavy);
    }

    /// SECONDS BACK FROM THE TALONS ARRIVING, or null — what the boards are offered. The burst is NOT in it:
    /// a hop away from you is not a stroke, and a window on it would be a parry for backing off.
    fn toImpact(self: *const Owlbear) ?f32 {
        const mv = self.row();
        const at = mv.strikeDur * IMPACT_K;
        return switch (self.state) {
            .rake, .slam => if (self.t < mv.windDur) (mv.windDur - self.t) + at else at - (self.t - mv.windDur),
            else => null,
        };
    }

    pub fn parryable(self: *const Owlbear) ?f32 {
        return self.toImpact();
    }

    pub fn update(self: *Owlbear, dt: f32, quarry: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.heroHit = null;
        self.justDied = false;
        self.justWoke = false;
        self.threw = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.vit.tick(dt);
        self.elapsed += dt;
        self.t += dt;
        self.rakeCd = mathx.maxF(0, self.rakeCd - dt);
        self.slamCd = mathx.maxF(0, self.slamCd - dt);
        self.burstCd = mathx.maxF(0, self.burstCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);
        // **THE LEASH ONLY RUNS ONCE IT IS AWAKE.** A statue has not seen anybody and cannot be provoked from
        // across a field, so its eyes are the proximity check and nothing else.
        if (self.rouse >= 1.0) foe.tickLeash(&self.leash, dt, self.pos, foe.tetherFor(self), quarry, AGGRO_R);

        var movedDist: f32 = 0;
        var moveSpeed: f32 = 0;
        var moveYaw: ?f32 = null;

        switch (self.state) {
            .dead => {
                self.speed = 0;
                self.hop = 0;
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
            .stone => self.tickStone(dt, quarry),
            .wake => {
                self.speed = 0;
                self.rouse = mathx.clampF(self.t / WAKE_DUR, 0, 1);
                self.shedGrit(dt);
                // It comes round onto him as it stands, but only once the stone has actually broken.
                if (self.rouse > EYE_LEAD) self.faceToward(quarry, dt * self.woke());
                if (self.rouse >= 1.0) self.enter(.idle);
            },
            .seat => {
                self.speed = 0;
                self.rouse = mathx.clampF(1.0 - self.t / SEAT_DUR, 0, 1);
                foe.faceToward(self.pos, &self.facing, mathx.addV(self.pos, mathx.headingDir(self.perchYaw)), TURN_RATE, dt);
                if (self.rouse <= 0) {
                    self.vit.heal(HP_MAX);
                    self.enter(.stone);
                }
            },
            .stunlight, .stunheavy => {
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                if (self.t >= combat.foeStunDur(self.state == .stunheavy)) self.enter(.idle);
            },
            .rake, .slam => {
                const mv = self.row();
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                if (self.t < mv.windDur) self.faceToward(quarry, dt);
                const s = self.t - mv.windDur;
                if (s >= 0 and s < mv.strikeDur) self.tryStroke(quarry, mv);
                if (self.t >= mv.windDur + mv.strikeDur + mv.recoverDur) {
                    self.heroLatch = false;
                    self.enter(.idle);
                }
            },
            .burst => self.tickBurst(dt, bounds, &movedDist, &moveSpeed, &moveYaw),
            .idle, .walk => {
                const sensed = foe.senseHero(&self.leash, self.pos, quarry, AGGRO_R);
                const gap = mathx.maxF(0, sensed - foe.HERO_R - self.bodyR());
                const homeGap = mathx.distXZ(self.pos, foe.homeFor(self));
                // **BACK ON ITS PERCH WITH NOBODY IN SIGHT, IT SITS DOWN AGAIN** — the statue is the resting
                // state and not a one-shot, so a wood full of these can be walked past twice.
                if (self.leash.goingHome() and homeGap <= SEAT_R and sensed > AGGRO_R) {
                    self.enter(.seat);
                } else switch (classify(gap, sensed, homeGap, self.rakeCd <= 0, self.slamCd <= 0, self.burstCd <= 0 and foe.canLeap(&self.root), self.root.held())) {
                    .rest => {
                        if (sensed <= AGGRO_R) self.faceToward(quarry, dt);
                        self.state = if (foe.postAmble(self, dt, bounds, WALK_SPEED, ACCEL, sensed, AGGRO_R, TURN_RATE, &movedDist, &moveSpeed, &moveYaw)) .walk else .idle;
                    },
                    .rake, .slam => |ch| {
                        self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                        self.heroLatch = false;
                        if (ch == .slam) {
                            self.slamCd = MOVES[SLAM].cd * self.aiRng.range(0.86, 1.2);
                            self.enter(.slam);
                        } else {
                            self.rakeCd = MOVES[RAKE].cd * self.aiRng.range(0.86, 1.2);
                            self.enter(.rake);
                        }
                    },
                    .burst => {
                        self.speed = 0;
                        self.burstCd = BURST_CD * self.aiRng.range(0.9, 1.15);
                        self.heroLatch = false;
                        self.loosed = false;
                        // AWAY from him, and the bearing is taken ONCE: the hop does not steer inside itself.
                        self.faceToward(quarry, dt);
                        self.burstYaw = mathx.headingXZ(mathx.dirXZ(quarry, self.pos));
                        self.enter(.burst);
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
                    },
                }
            },
        }

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        self.pose();
        self.tryHit(blade);
        return self.heroHit;
    }

    /// **THE STATUE ASKS ONE QUESTION AND IT IS ABOUT DISTANCE** — never about what he is holding, never about
    /// whether he has seen it, and never about a blow, because a blow cannot land on it.
    fn tickStone(self: *Owlbear, dt: f32, quarry: rl.Vector3) void {
        self.speed = 0;
        self.hop = 0;
        self.rouse = 0;
        _ = dt;
        if (mathx.distXZ(self.pos, quarry) > WAKE_R * self.scale) return;
        self.justWoke = true;
        self.leash.provoke();
        sfx.world(.stone_grind, self.pos);
        self.enter(.wake);
    }

    /// The hop, and the fan that leaves at the top of it. The travel is on the bearing it committed to, so a
    /// man who rolled through it does not drag the creature round with him.
    fn tickBurst(self: *Owlbear, dt: f32, bounds: f32, movedDist: *f32, moveSpeed: *f32, moveYaw: *?f32) void {
        const u = self.leapU();
        self.hop = BURST_RISE * mathx.sinf(u * std.math.pi);
        if (self.t > BURST_GATHER and u < 1.0) {
            const way = mathx.headingDir(self.burstYaw);
            // The arc's own speed, not a constant: fastest off the ground and easing into the landing.
            const rate = BURST_DIST / BURST_FLIGHT * mathx.sinf(u * std.math.pi) * (std.math.pi / 2.0);
            const moved = rate * dt;
            mathx.stepXZ(&self.pos, way, moved, bounds);
            movedDist.* = moved;
            moveSpeed.* = rate;
            moveYaw.* = self.burstYaw;
        }
        if (!self.loosed and u >= BURST_LOOSE_K) {
            self.loosed = true;
            self.threw = true;
            self.threwFrom = foe.markOn(self.xf[CHEST], v3(0, 0, 0.10 * H));
            sfx.world(.arrow_loose, self.pos);
        }
        if (self.t >= BURST_GATHER + BURST_FLIGHT + BURST_LAND) {
            self.hop = 0;
            self.enter(.idle);
        }
    }

    /// **WHERE THE FAN IS AIMED**, and it is where the creature CAME FROM — the ground it just left, not
    /// wherever the man is standing when the quills leave. That is what makes the burst a punish for
    /// crowding it and not a second homing shot.
    pub fn burstBearing(self: *const Owlbear) f32 {
        return mathx.headingXZ(mathx.scaleV(mathx.headingDir(self.burstYaw), -1));
    }

    fn tryStroke(self: *Owlbear, quarry: rl.Vector3, mv: Attack) void {
        if (self.heroLatch) return;
        if (!foe.inFront(self.pos, self.facing, quarry, foe.hurtReach(mv.maxR, self.scale), mv.frontDot)) return;
        self.heroHit = mv.hit;
        self.heroLatch = true;
        self.leash.noteCombat();
    }

    /// **A BLADE RINGS OFF THE STONE.** Not a resistance and not a shield: the blow never happens, so nothing
    /// it carries builds a meter, nothing latches, and the swing costs him a swing. `hidden` is the same
    /// predicate, so what the reticle refuses and what the edge refuses are one rule.
    pub fn tryHit(self: *Owlbear, blade: foe.Blade) void {
        if (self.state == .dead or self.hidden()) return;
        const s = foe.reached(self, blade) orelse return;
        const heavy = foe.wounded(self, s, blade, SHOVE);
        self.chips(s.contact, s.dir, foe.hitParts(if (heavy) HIT_CHIP_HEAVY else HIT_CHIP_LIGHT));
        switch (s.reaction) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn enter(self: *Owlbear, s: State) void {
        self.state = s;
        self.t = 0;
    }
    fn enterStun(self: *Owlbear, s: State) void {
        self.heroLatch = false;
        self.hop = 0;
        self.enter(s);
    }
    fn enterDeath(self: *Owlbear) void {
        if (self.state == .dead) return;
        self.heroLatch = false;
        self.hop = 0;
        self.rouse = 1.0;
        self.enter(.dead);
        self.justDied = true;
    }
    pub fn stagger(self: *Owlbear, heavy: bool) void {
        if (self.hidden()) return;
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }

    pub fn debugWake(self: *Owlbear) void {
        self.rouse = 1.0;
        self.enter(.idle);
    }
    pub fn debugRake(self: *Owlbear) void {
        self.debugWake();
        self.heroLatch = false;
        self.enter(.rake);
    }
    pub fn debugSlam(self: *Owlbear) void {
        self.debugWake();
        self.heroLatch = false;
        self.enter(.slam);
    }
    /// The signature move `shots.runMapShots` finds by `@hasDecl`, and it is the burst.
    pub fn stageGather(self: *Owlbear) void {
        self.debugWake();
        self.heroLatch = false;
        self.loosed = false;
        self.burstYaw = self.facing;
        self.enter(.burst);
        self.t = BURST_GATHER + BURST_FLIGHT * BURST_LOOSE_K;
    }
    pub fn debugKill(self: *Owlbear) void {
        self.enterDeath();
    }

    const CHIP_SPRAY = foe.Spray{
        .fanLo = 0.22,
        .fanHi = 0.90,
        .upLo = 0.35,
        .upHi = 1.7,
        .lifeLo = 0.30,
        .lifeHi = 0.70,
        .rLo = 0.014,
        .rHi = 0.030,
        .r1 = 0.006,
        .col = CHIP,
        .col1 = STONE_DK,
        .grav = foe.DUST_GRAV,
        .bounce = 0.22,
    };
    fn chips(self: *Owlbear, at: rl.Vector3, dir: rl.Vector3, n: i32) void {
        foe.spray(&self.parts, &self.fxHead, &self.fxRng, at, dir, n, 2.4, self.scale, CHIP_SPRAY);
    }

    /// **THE STONE BREAKING IS THE SECOND HALF OF THE TELL** — grit off the seams while the body comes up, and
    /// none of it before `EYE_LEAD`, because nothing has moved yet.
    fn shedGrit(self: *Owlbear, dt: f32) void {
        const w = self.woke();
        if (w <= 0.01) return;
        var owed = foe.emitDue(&self.fxAccum, dt, 46.0 * w);
        while (owed > 0) : (owed -= 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.10, 0.30) * H * self.scale;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(
                    self.pos.x + mathx.cosf(a) * rr,
                    self.pos.y + self.fxRng.float() * TOP_F * H * self.scale,
                    self.pos.z + mathx.sinf(a) * rr,
                ),
                .v = v3(self.fxRng.signed() * 0.25, self.fxRng.range(-0.2, 0.35), self.fxRng.signed() * 0.25),
                .life = self.fxRng.range(0.35, 0.85),
                .r0 = self.fxRng.range(0.012, 0.030),
                .r1 = 0.004,
                .col = DUST,
                .col1 = foe.DUST_THIN,
                .grav = foe.DUST_GRAV * 0.7,
                .drag = 2.4,
            });
        }
    }

    pub fn drawFx(self: *const Owlbear) void {
        foe.drawParticles(&self.parts);
        // **THE EYES ARE DRAWN OVER THE CARVING, NOT BAKED INTO IT** — a mesh colour cannot come up, and the
        // whole warning is these two dots kindling in a face that has not moved.
        const g = self.eyeGlow();
        if (g <= 0.02 or self.state == .dead) return;
        for ([_]f32{ 1.0, -1.0 }) |side| {
            const at = foe.markOn(self.xf[CROWN], v3(side * 0.062 * H, 0.030 * H, 0.086 * H));
            rl.drawSphereEx(at, 0.030 * H * self.scale * (0.7 + 0.3 * g), 7, 6, mathx.lerpColor(EYE_COLD, EYE_LIT, g));
            rl.drawSphereEx(at, 0.058 * H * self.scale * g, 8, 6, mathx.withAlpha(EYE_LIT, mathx.u8f(96.0 * g)));
        }
    }
    pub fn draw(self: *const Owlbear, model: *const Model) void {
        model.draw(self);
    }

    pub fn pose(self: *Owlbear) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = foe.rigSink(foe.SINK_HUMANOID, self.scale, self.fade);
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.6, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        const stun = self.stunAmount();
        const w = self.woke();
        const m = self.moving * (1.0 - dk) * w;
        const pel = heromod.pelvisChannels(self.phase, m, self.fwdB, self.latB, A_PROT);
        const stroke = self.strokeAmt();
        const u = self.leapU();
        // The hop TUCKS: knees up and shoulders back over the top of the arc, so the body reads as thrown
        // rather than as walked backwards in the air.
        const tuck = if (self.state == .burst) mathx.sinf(u * std.math.pi) else 0;

        // **THE CARVING'S OWN POSE IS A CROUCH**, and `w` is what lets it out: hunched over its feet at 0,
        // standing at 1. That one number is the difference between the statue and the creature.
        const settle = (1.0 - w) * (1.0 - dk);
        const sway = SWAY_DEG * mathx.gutter(self.elapsed * SWAY_HZ + self.seed * 6.28, self.seed * 3.7) * (1.0 - m) * w;
        const bodyPitch = 26.0 * mathx.maxF(0, stroke) - 15.0 * mathx.maxF(0, -stroke) - 20.0 * stun + 68.0 * dk + 30.0 * settle - 22.0 * tuck;
        const leanX = PELVIS_SHARE * bodyPitch;
        const waist = (1.0 - PELVIS_SHARE) * bodyPitch;

        var wx: [N]rl.Matrix = undefined;
        // The crouch drops the pelvis as well as folding it: a statue sits INTO its own base.
        const crouch = 0.16 * H * settle;
        const pelvY = if (dead) lerpF(hipY, hipY * 0.60, dk) else hipY + pel.bob - pel.dip - crouch + self.hop / mathx.maxF(fs, 1e-4) * 0;
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(sway * 0.5), rx(leanX), ry(pel.prot)),
            mul(tr(pel.sway * fs, pelvY * fs + sink + self.hop * self.scale, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));
        if (!dead) {
            heromod.legChain(&wx, &self.rest, self.pos.y + self.hop * self.scale, self.phase, m, 0, self.fwdB, self.latB, 1.0, HIPL, KNEEL, solePatches[0]);
            heromod.legChain(&wx, &self.rest, self.pos.y + self.hop * self.scale, self.phase + 0.5, m, 0, self.fwdB, self.latB, -1.0, HIPR, KNEER, solePatches[1]);
        } else {
            heromod.deadLegs(&wx, self.rest, dk);
        }
        self.poseUpper(&wx, waist, stroke, stun, dk, pel.prot, sway, settle, tuck);
        self.xf = wx;
    }

    fn poseUpper(self: *Owlbear, wx: *[N]rl.Matrix, waist: f32, stroke: f32, stun: f32, dk: f32, prot: f32, sway: f32, settle: f32, tuck: f32) void {
        const rest = self.rest;
        const m = self.moving * (1.0 - dk);
        const slam = self.state == .slam;

        setLocal(wx, SPINE, rest, mul3(rx(waist * 0.38), ry(-0.25 * prot), rz(sway * 0.5)));
        setLocal(wx, CHEST, rest, mul3(rx(waist * 0.62), ry(-0.4 * prot), rz(sway * 0.4)));
        // **THE HEAD IS THE OWL AND IT BARELY MOVES** — a bird's skull rides level while the body pitches
        // under it, so the neck spends most of the trunk's own lean back again. Sunk into the shoulders while
        // it is stone, which is what a carved owl does with its neck.
        setLocal(wx, NECK, rest, rx(-waist * 0.42 - 8.0 * stroke + 6.0 * dk - 6.0 * stun + 16.0 * settle));
        setLocal(wx, CROWN, rest, mul3(rx(-waist * 0.30 - 10.0 * stroke + 12.0 * dk - 18.0 * stun + 8.0 * settle), ry(-0.3 * prot), rz(sway)));

        // **THE WINGS COME UP TOGETHER AND COME DOWN TOGETHER**, and the slam hauls them further than the
        // rake does: one stroke shape, two amplitudes, so the two moves read as the same animal.
        const armStun = -30.0 * stun;
        const swing = -9.0 * heromod.armSwing(self.phase) * m * @abs(self.fwdB);
        const gainUp: f32 = if (slam) 140.0 else 96.0;
        const gainDown: f32 = if (slam) 96.0 else 68.0;
        const haul = -gainUp * mathx.maxF(0, -stroke);
        const drive = gainDown * mathx.maxF(0, stroke);
        const late = std.math.pow(f32, @abs(stroke), 1.5);
        // Folded flat to the body while it is stone, and thrown wide across the hop.
        const fold = 26.0 * settle;
        const flare = 44.0 * tuck;
        inline for (.{ SHL, SHR }, .{ ELL, ELR }, .{ WRL, WRR }, .{ 1.0, -1.0 }) |sh, el, wr, side| {
            const s = if (side > 0) swing else -swing;
            const gain: f32 = if (side > 0) 0.96 else 1.04;
            setLocal(wx, sh, rest, mul3(
                rx(-(8.0 + s) + (haul - drive) * gain + armStun - 12.0 * dk + 10.0 * settle),
                ry(0),
                rz(side * (14.0 - fold + flare)),
            ));
            setLocal(wx, el, rest, rx(-(18.0 + 20.0 * late * (if (side > 0) @as(f32, 0.92) else @as(f32, 1.1))) - 16.0 * settle));
            setLocal(wx, wr, rest, rz(side * 5.0 + 2.0 * sway));
        }
    }
};

/// **A QUILL IN THE AIR.** A straight shot with a little drop on it and no owner — it answers for the hero and
/// for nothing else, and it does not steer: what makes the fan a decision is its WIDTH, not its aim.
pub const Quill = struct {
    live: bool = false,
    at: rl.Vector3 = mathx.zero3,
    vel: rl.Vector3 = mathx.zero3,
    t: f32 = 0,
    spin: f32 = 0,
    /// The ground under the body that threw it — what `foe.landed` measures against.
    floor: f32 = 0,
};

pub const QUILL_N: usize = 30;

const CAP_N = wf.MAX_PER_KIND;
const PERCH_PARTS: usize = 64;

/// A quill in the air belongs to nobody standing anywhere — a `Threat` with no spirit and no owner says so.
const AIR_THREAT = foe.Threat{};

pub const Perch = struct {
    model: Model,
    birds: [CAP_N]Owlbear = undefined,
    n: usize = 0,

    /// Six fans before the pool degrades, and a full pool DROPS rather than wraps: wrapping would put a quill
    /// in the air that nothing had thrown.
    quills: [QUILL_N]Quill = [_]Quill{.{}} ** QUILL_N,

    parts: [PERCH_PARTS]foe.Particle = [_]foe.Particle{.{}} ** PERCH_PARTS,
    fxHead: usize = 0,
    fxRng: mathx.Rng = mathx.Rng.init(0x0B1C),

    pub fn init(shader: rl.Shader) Perch {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Perch) []Owlbear {
        return self.birds[0..self.n];
    }
    pub fn liveConst(self: *const Perch) []const Owlbear {
        return self.birds[0..self.n];
    }
    pub fn reset(self: *Perch, m: *const wf.Map) void {
        self.clearAir();
        foe.resetGroup(Owlbear, &self.birds, &self.n, m, .owlbear);
    }
    /// **`clear` EMPTIES THE FIELD** — the bodies AND what they left in the air over it, or a reload comes up
    /// standing in a fan nothing threw.
    pub fn clear(self: *Perch) void {
        self.n = 0;
        self.clearAir();
    }
    fn clearAir(self: *Perch) void {
        self.quills = [_]Quill{.{}} ** QUILL_N;
    }
    pub fn setShader(self: *Perch, sh: rl.Shader) void {
        self.model.setShader(sh);
    }

    pub fn update(self: *Perch, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        var worst: ?foe.Blow = null;
        for (self.live()) |*o| {
            if (o.update(dt, o.threat.aim(hero), bounds, blade)) |h| foe.worseBlow(&worst, h, o.pos, &o.threat);
            if (o.threw) self.fan(o.threwFrom, o.burstBearing(), o.pos.y);
        }
        self.tickQuills(dt, hero, &worst);
        foe.tickParticles(&self.parts, dt, hero.y);
        return worst;
    }

    /// **A FAN ON THE BEARING IT LEFT ON, SPREAD `QUILL_FAN` WIDE.** The middle quill is on the line and the
    /// rest step off it evenly — an even fan is the one you can read and cross; a random one is a shotgun.
    fn fan(self: *Perch, from: rl.Vector3, bearing: f32, floor: f32) void {
        var placed: usize = 0;
        for (&self.quills) |*q| {
            if (placed >= QUILLS_PER_BURST) break;
            if (q.live) continue;
            const half = @as(f32, @floatFromInt(QUILLS_PER_BURST - 1)) * 0.5;
            const step = QUILL_FAN / @as(f32, @floatFromInt(QUILLS_PER_BURST - 1));
            const off = (@as(f32, @floatFromInt(placed)) - half) * step;
            const dir = mathx.headingDir(bearing + mathx.radians(off));
            q.* = .{
                .live = true,
                .at = from,
                .vel = mathx.scaleV(v3(dir.x, 0, dir.z), QUILL_SPEED),
                .spin = self.fxRng.float(),
                .floor = floor,
            };
            placed += 1;
        }
    }

    fn tickQuills(self: *Perch, dt: f32, hero: rl.Vector3, worst: *?foe.Blow) void {
        const chest = foe.heroChest(hero);
        for (&self.quills) |*q| {
            if (!q.live) continue;
            q.t += dt;
            q.vel.y -= QUILL_FALL * dt;
            q.at = mathx.addV(q.at, mathx.scaleV(q.vel, dt));
            if (mathx.lenV(mathx.subV(q.at, chest)) <= QUILL_R + foe.HERO_R) {
                q.live = false;
                self.shatter(q.at, 7);
                foe.worseBlow(worst, QUILL_HIT, q.at, &AIR_THREAT);
                continue;
            }
            if (q.t >= QUILL_LIFE or foe.landed(q.at.y, q.floor, hero.y)) {
                q.live = false;
                self.shatter(q.at, 5);
            }
        }
    }

    fn shatter(self: *Perch, at: rl.Vector3, n: usize) void {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.5, 1.6);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = at,
                .v = v3(mathx.cosf(a) * sp, self.fxRng.range(0.2, 1.1), mathx.sinf(a) * sp),
                .life = self.fxRng.range(0.24, 0.55),
                .r0 = self.fxRng.range(0.014, 0.030),
                .r1 = 0.004,
                .col = if (self.fxRng.float() < 0.5) CHIP else STONE_LT,
                .grav = foe.DUST_GRAV,
                .drag = 2.8,
            });
        }
    }

    pub fn draw(self: *const Perch, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }

    pub fn drawFx(self: *const Perch) void {
        for (self.liveConst()) |*o| o.drawFx();
        for (&self.quills) |*q| {
            if (!q.live) continue;
            // Drawn as the shaft it is: a stretched bead along its own heading, so the fan reads as five
            // things flying and not as five pebbles.
            const back = mathx.scaleV(mathx.normV(q.vel), -QUILL_R * 2.6);
            rl.drawCylinderEx(mathx.addV(q.at, back), q.at, QUILL_R * 0.5, QUILL_R * 0.14, 5, STONE_LT);
            rl.drawSphereEx(q.at, QUILL_R * (0.9 + 0.1 * mathx.sinf((q.t + q.spin) * 22.0)), 6, 5, STONE);
        }
        foe.drawParticles(&self.parts);
    }

    pub fn setParry(self: *Perch, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    pub fn anyParried(self: *const Perch) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn pierce(self: *Perch, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Perch) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn anyWoke(self: *const Perch) bool {
        for (self.liveConst()) |*o| {
            if (o.justWoke) return true;
        }
        return false;
    }
    pub fn soulsDropped(self: *const Perch) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Perch) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Perch) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

fn buildBones() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    var rng = mathx.Rng.init(0x0B1D);
    mesh[ROOT] = blockMesh(0.132, 0.108, 0.116, &rng);
    mesh[SPINE] = blockMesh(0.126, 0.098, 0.132, &rng);
    mesh[CHEST] = chestMesh(&rng);
    mesh[NECK] = blockMesh(0.070, 0.050, 0.072, &rng);
    mesh[CROWN] = skullMesh(&rng);
    mesh[HIPL] = limbMesh(0.062, 0.052, REST[KNEEL].y - REST[HIPL].y, &rng);
    mesh[KNEEL] = limbMesh(0.052, 0.044, REST[ANKL].y - REST[KNEEL].y, &rng);
    mesh[ANKL] = talonMesh(&rng);
    mesh[HIPR] = limbMesh(0.062, 0.052, REST[KNEER].y - REST[HIPR].y, &rng);
    mesh[KNEER] = limbMesh(0.052, 0.044, REST[ANKR].y - REST[KNEER].y, &rng);
    mesh[ANKR] = talonMesh(&rng);
    mesh[SHL] = wingMesh(1.0, &rng);
    mesh[ELL] = foreMesh(1.0, &rng);
    mesh[WRL] = clawMesh(1.0, &rng);
    mesh[SHR] = wingMesh(-1.0, &rng);
    mesh[ELR] = foreMesh(-1.0, &rng);
    mesh[WRR] = clawMesh(-1.0, &rng);
    mesh[HELD] = Builder.init().toMesh();
    return mesh;
}

/// **THE WHOLE BODY IS BLOCKED OUT, NOT BLOBBED** — a carving is chiselled, so every mass on it is a squat
/// box with its corners knocked off. `addBlob` at low segment counts is what gives it the faceted read.
fn blockMesh(rx0: f32, rz0: f32, ry0: f32, rng: *mathx.Rng) rl.Mesh {
    var b = Builder.init();
    b.setMat(.stone);
    b.addBlob(v3(0, 0, 0), v3(rx0 * H, ry0 * H, rz0 * H), 4, 6, STONE);
    b.addBlob(v3(0, ry0 * H * 0.42, 0), v3(rx0 * H * 0.86, ry0 * H * 0.44, rz0 * H * 0.88), 4, 6, STONE_LT);
    lichen(&b, rx0 * H, ry0 * H, rng, 3);
    return b.toMesh();
}

/// The barrel, and it is the widest thing on the body: a bear's chest under an owl's plumage, blocked as a
/// slab of masonry with a carved breast panel standing proud of it.
fn chestMesh(rng: *mathx.Rng) rl.Mesh {
    var b = Builder.init();
    b.setMat(.stone);
    b.addBlob(v3(0, 0.010 * H, 0), v3(0.176 * H, 0.150 * H, 0.140 * H), 5, 8, STONE);
    b.addBlob(v3(0, 0.086 * H, -0.018 * H), v3(0.166 * H, 0.062 * H, 0.120 * H), 4, 7, STONE_DK);
    // THE BREAST PANEL: carved courses of feather, cut as four stepped plates rather than as plumage. A
    // feathered chest on a statue is a thing nobody can chisel and nobody would.
    var k: u32 = 0;
    while (k < 4) : (k += 1) {
        const u = @as(f32, @floatFromInt(k)) / 3.0;
        const rr = (0.130 - 0.030 * u) * H;
        b.addBlob(
            v3(0, (0.062 - 0.086 * u) * H, 0.096 * H),
            v3(rr, 0.040 * H, 0.030 * H),
            4,
            8,
            if (k & 1 == 0) STONE_LT else GRANITE,
        );
    }
    b.setMat(.marble);
    // The shoulder bosses — where the wings are pinned into the body, and the one polished surface on it.
    b.addBlob(v3(0.164 * H, 0.070 * H, 0), v3(0.052 * H, 0.062 * H, 0.062 * H), 4, 7, STONE_LT);
    b.addBlob(v3(-0.164 * H, 0.070 * H, 0), v3(0.052 * H, 0.062 * H, 0.062 * H), 4, 7, STONE_LT);
    b.setMat(.stone);
    lichen(&b, 0.176 * H, 0.150 * H, rng, 5);
    return b.toMesh();
}

/// **THE HEAD IS THE WHOLE SILHOUETTE** — a great round facial disc, two ear tufts and a short hooked beak.
/// Nothing else on the body has to say "owl", and from ten metres nothing else can.
fn skullMesh(rng: *mathx.Rng) rl.Mesh {
    var b = Builder.init();
    b.setMat(.stone);
    b.addBlob(v3(0, 0.014 * H, 0.006 * H), v3(0.122 * H, 0.118 * H, 0.106 * H), 6, 9, STONE);
    // THE FACIAL DISC: a flat dish carved onto the front of the skull, its rim standing proud all round.
    b.addBlob(v3(0, 0.006 * H, 0.070 * H), v3(0.110 * H, 0.108 * H, 0.032 * H), 5, 10, STONE_LT);
    var k: u32 = 0;
    while (k < 10) : (k += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(k)) / 10.0;
        b.addBlob(
            v3(mathx.cosf(a) * 0.104 * H, 0.006 * H + mathx.sinf(a) * 0.100 * H, 0.062 * H),
            v3(0.022 * H, 0.022 * H, 0.018 * H),
            4,
            6,
            GRANITE,
        );
    }
    // THE SOCKETS the eyes sit in — sunk and near-black, so the two lights have somewhere to come up FROM.
    for ([_]f32{ 1.0, -1.0 }) |side| {
        b.addBlob(v3(side * 0.062 * H, 0.030 * H, 0.082 * H), v3(0.040 * H, 0.040 * H, 0.020 * H), 5, 8, SOCKET);
    }
    // THE EAR TUFTS: two blunt horns off the crown, one a shade shorter — the wabi-sabi is BETWEEN them.
    for ([_]f32{ 1.0, -1.0 }, [_]f32{ 1.0, 0.88 }) |side, share| {
        const tip = v3(side * 0.086 * H, (0.108 + 0.070 * share) * H, -0.020 * H);
        b.addCapsule(v3(side * 0.062 * H, 0.086 * H, -0.004 * H), tip, 0.030 * H, 0.016 * H, 6, STONE);
        b.addBlob(tip, v3(0.016 * H, 0.016 * H, 0.015 * H), 4, 6, STONE_LT);
    }
    // THE BEAK — short, hooked and DOWN, and it is the one warm tone on a cold body.
    b.setMat(.marble);
    b.addCapsule(v3(0, 0.006 * H, 0.092 * H), v3(0, -0.026 * H, 0.128 * H), 0.030 * H, 0.017 * H, 6, BEAK);
    b.addBlob(v3(0, -0.034 * H, 0.120 * H), v3(0.014 * H, 0.018 * H, 0.016 * H), 4, 7, BEAK_LT);
    b.setMat(.stone);
    lichen(&b, 0.122 * H, 0.118 * H, rng, 3);
    return b.toMesh();
}

fn limbMesh(r0: f32, r1: f32, len: f32, rng: *mathx.Rng) rl.Mesh {
    var b = Builder.init();
    b.setMat(.stone);
    const l = @abs(len);
    b.addCapsule(v3(0, 0, 0), v3(0, -l, 0), r0 * H, r1 * H, 7, STONE);
    b.addBlob(v3(0, -l * 0.06, 0.006 * H), v3(r0 * H * 1.10, r0 * H * 0.80, r0 * H * 1.06), 4, 7, STONE_LT);
    b.addBlob(v3(0, -l * 0.94, 0.006 * H), v3(r1 * H * 1.14, r1 * H * 0.82, r1 * H * 1.10), 4, 7, GRANITE);
    lichen(&b, r0 * H, l * 0.4, rng, 2);
    return b.toMesh();
}

/// **A TALON PLATE, NOT A FOOT** — three forward toes and one back, each ending in a blunt carved hook. It is
/// the last thing that would still say "bear" if it were left alone.
fn talonMesh(rng: *mathx.Rng) rl.Mesh {
    var b = Builder.init();
    b.setMat(.stone);
    b.addBlob(v3(0, -0.014 * H, 0.026 * H), v3(0.062 * H, 0.030 * H, 0.070 * H), 4, 8, STONE);
    for ([_]f32{ -1.0, 0.0, 1.0 }) |lat| {
        const tip = v3(lat * 0.048 * H, -0.030 * H, 0.126 * H);
        b.addCapsule(v3(lat * 0.024 * H, -0.014 * H, 0.050 * H), tip, 0.022 * H, 0.011 * H, 5, STONE);
        b.addBlob(tip, v3(0.012 * H, 0.011 * H, 0.013 * H), 4, 6, GRANITE);
    }
    const heel = v3(0, -0.028 * H, -0.052 * H);
    b.addCapsule(v3(0, -0.014 * H, -0.006 * H), heel, 0.020 * H, 0.010 * H, 5, STONE);
    b.addBlob(heel, v3(0.011 * H, 0.010 * H, 0.012 * H), 4, 6, GRANITE);
    lichen(&b, 0.062 * H, 0.030 * H, rng, 2);
    return b.toMesh();
}

/// The upper wing, and it is carved FOLDED: a slab of coverts laid against the body, with the courses cut
/// across it. Open plumage on a statue is a thing that snaps off, which is why no real one has it.
fn wingMesh(side: f32, rng: *mathx.Rng) rl.Mesh {
    var b = Builder.init();
    b.setMat(.stone);
    const len = REST[ELL].y - REST[SHL].y;
    const l = @abs(len);
    b.addCapsule(v3(0, 0, 0), v3(0, -l, 0), 0.070 * H, 0.056 * H, 7, STONE);
    // FOUR COURSES of covert, stepping down the outer face — relief is a few percent of the mass.
    var k: u32 = 0;
    while (k < 4) : (k += 1) {
        const u = (@as(f32, @floatFromInt(k)) + 0.5) / 4.0;
        b.addBlob(
            v3(side * 0.048 * H, -l * u, 0.006 * H),
            v3(0.030 * H, 0.052 * H, 0.058 * H),
            4,
            7,
            if (k & 1 == 0) STONE_LT else GRANITE,
        );
    }
    lichen(&b, 0.070 * H, l * 0.4, rng, 3);
    return b.toMesh();
}

/// The forewing — the primaries, and they are the QUILLS the burst throws. Carved as five stepped blades
/// laid along the limb, so what leaves the body in the fan is a thing the player has already seen on it.
fn foreMesh(side: f32, rng: *mathx.Rng) rl.Mesh {
    var b = Builder.init();
    b.setMat(.stone);
    const len = REST[WRL].y - REST[ELL].y;
    const l = @abs(len);
    b.addCapsule(v3(0, 0, 0), v3(0, -l, 0), 0.054 * H, 0.042 * H, 7, STONE);
    var k: u32 = 0;
    while (k < 5) : (k += 1) {
        const u = (@as(f32, @floatFromInt(k)) + 0.4) / 5.0;
        const reach = (0.070 - 0.016 * u) * H;
        const from = v3(side * 0.030 * H, -l * u, 0.008 * H);
        const to = v3(side * (0.030 * H + reach), -l * u - reach * 0.42, -0.014 * H);
        b.addCapsule(from, to, 0.019 * H, 0.008 * H, 5, if (k & 1 == 0) STONE_LT else STONE);
        b.addBlob(to, v3(0.009 * H, 0.008 * H, 0.009 * H), 4, 6, GRANITE);
    }
    lichen(&b, 0.054 * H, l * 0.4, rng, 2);
    return b.toMesh();
}

/// The wing claw — a bear's paw at the end of a bird's wing, which is the whole joke of the creature and the
/// thing the rake actually lands with.
fn clawMesh(side: f32, rng: *mathx.Rng) rl.Mesh {
    var b = Builder.init();
    b.setMat(.stone);
    b.addBlob(v3(0, -0.036 * H, 0.010 * H), v3(0.052 * H, 0.048 * H, 0.050 * H), 5, 8, STONE);
    for ([_]f32{ -1.0, -0.34, 0.34, 1.0 }) |lat| {
        const tip = v3(side * 0.014 * H + lat * 0.040 * H, -0.106 * H, 0.044 * H);
        b.addCapsule(v3(lat * 0.030 * H, -0.058 * H, 0.014 * H), tip, 0.017 * H, 0.008 * H, 5, STONE);
        b.addBlob(tip, v3(0.009 * H, 0.008 * H, 0.009 * H), 4, 6, GRANITE);
    }
    lichen(&b, 0.052 * H, 0.048 * H, rng, 2);
    return b.toMesh();
}

/// **THE ONE THING THAT SAYS THE STATUE HAS BEEN THERE A LONG TIME.** Patches, never a coat: lichen over the
/// whole body reads as paint, and lichen in the seams reads as years.
fn lichen(b: *Builder, rx0: f32, ry0: f32, rng: *mathx.Rng, n: u32) void {
    b.setMat(.plant);
    var k: u32 = 0;
    while (k < n) : (k += 1) {
        const a = rng.angle();
        const rr = rng.range(0.14, 0.34) * rx0;
        b.addBlob(
            v3(mathx.cosf(a) * rx0 * 0.86, rng.signed() * ry0 * 0.62, mathx.sinf(a) * rx0 * 0.86),
            v3(rr, rr * 0.62, rr),
            3,
            6,
            if (rng.float() < 0.45) LICHEN_LT else LICHEN,
        );
    }
    b.setMat(.stone);
}
