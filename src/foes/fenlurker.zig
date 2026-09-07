const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const heromod = @import("../play/hero.zig");

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


/// How far out of the water the head rides at full surge, in metres — its own stature, and everything on the rig is a fraction of it. Over the hero's own 1.8 so the thing that comes up is looking DOWN at him.
pub const H: f32 = 2.55;

pub var AGGRO_R: f32 = 9.0;

pub const WADE_MIN: f32 = 0.30;

pub const POOL_MIN: f32 = 0.22;

const BODY_R: f32 = 0.52;
const HURT_R: f32 = 0.98;
const CENTER_F: f32 = 0.62;
const TOP_F: f32 = 1.12;

const HP_MAX: f32 = 78.0;
/// It flinches off a hero heavy (22) and not off a light (10) — the ravager's own sizing, because a thing with a window this narrow may not be stunlockable inside it.
const POISE_MAX: f32 = 20.0;
const STANCE_MAX: f32 = 36.0;
const RESISTS = combat.resists(.{ .fire = 45, .cold = 25, .lightning = -60, .chaos = 0 });

pub var SOULS: u32 = 170;

const DEATH_DUR: f32 = 1.15;
const DISS_DUR: f32 = 1.0;
const DISSOLVE = foe.Dissolve{ .rate = 60.0, .spread = 0.95, .rise = 0.55, .flake = SILT };
/// Arithmetic over the worst frame, not a round number: the wake lays `WAKE_RATE` a second, and the two burst
/// emitters are `splash(9)` off a heavy blow and `splash(7)` off the tongue's own pad, which can land on one frame.
const PARTS = 88;
comptime {
    std.debug.assert(PARTS >= foe.hitParts(9) + foe.hitParts(7) + @as(i32, @intFromFloat(WAKE_RATE)));
}


const SURGE_DUR: f32 = 0.72;
const LASH_DUR: f32 = 0.20;
const RECOVER_DUR: f32 = 0.62;
const SINK_DUR: f32 = 0.85;
const REST_DUR: f32 = 1.10;

pub var LASH_HIT = combat.Hit{ .dmg = 26, .poise = 24, .stance = 11 };

/// How far out the head reaches at the strike, off the creature's own centre — MEASURED off the posed rig by the test at the foot of this file, never guessed.
const LASH_R: f32 = 2.35;
const LASH_FRONT_DOT: f32 = 0.30;
const LASH_IMPACT_K: f32 = 0.5;
/// Its reach and measured height are both taken over this: a flat skull coming down is a MASS, not a point.
const HEAD_R: f32 = 0.34;

/// THE TONGUE IS THE REACH, AND THE NECK NEVER WAS. Four segments of this against a 2.55 m stature — a chameleon's
/// is twice its body and this is twice that, because a fixture in a pool whose only blow ends at 2.35 m is beaten by
/// standing in the shallows and waiting.
const TONGUE_SEG: f32 = 1.24;
const TONGUE_LEN: f32 = TONGUE_SEG * @as(f32, @floatFromInt(TSEGS));
/// How far the TIP carries off the creature's own centre at full extension, and the far edge of the tongue's band.
/// MEASURED off the posed rig by the test at the foot of this file, and authored UNDER what it measures: a band that
/// promises more than the kit reaches is a blow thrown at a man it cannot touch.
pub const TONGUE_R: f32 = 4.80;
/// The shaft's own half-thickness for the bill, and it tracks the mesh's own thickness rather than being picked:
/// the WHOLE length answers, not the pad, because five metres of muscle passing through a man takes him whether the
/// end of it stopped at his chest or went three metres past his shoulder.
const TONGUE_SHAFT_R: f32 = TONGUE_R0 * H * 1.6;
pub var TONGUE_HIT = combat.Hit{ .dmg = 15, .poise = 15, .stance = 5 };
/// Metres he is HAULED toward the pool when it lands. Sized so a hit taken at the tongue's own far edge puts him
/// inside the LASH's band, which is the rooted hook's rule (`rooted.DRAG_PULL`) and what makes the drag a SETUP
/// rather than a nuisance. A test pins it.
pub const TONGUE_PULL: f32 = 2.70;

const GAPE_DUR: f32 = 0.95;
/// How far back the coil loads before it spits, on the lash's own `swing` channel — so the neck coils, the skull
/// lifts and the jaws come apart through the one set of joints the creature already has.
const GAPE_REAR: f32 = 0.65;
/// The share of the tell spent SURFACING. Short, so the reared coil and the open mouth own the rest of it.
const GAPE_RISE: f32 = 0.45;
/// The share of the tell spent loading. The rest is the snap forward, and it has to finish before the shaft goes.
const GAPE_LOAD: f32 = 0.72;
const SPIT_DUR: f32 = 0.18;
const REEL_DUR: f32 = 0.34;
/// The punish window a whiffed tongue buys him — over the lash's, because the tongue is the longer reach.
const TONGUE_RECOVER: f32 = 1.05;
const TONGUE_CD: f32 = 5.0;

const TURN_RATE: f32 = 2.2;

pub const Move = enum { lash, tongue };

fn lashBand(scale: f32) f32 {
    return foe.hurtReach(LASH_R, scale);
}
/// THE SWEPT BILL'S OWN ALLOWANCE, AND IT IS NOT `foe.hurtReach`'s. That 0.55 m is what a centre-to-centre RADIUS
/// test owes the man's body; a swept segment is tested against his CAPSULE, so what it adds is his radius and the
/// shaft's own half-thickness. It is also the `r` the bill is handed — one number, or the band promises a reach the
/// sweep is not looking for.
/// The tongue's stroke on the house shape, so the shot harness stamps its frames off the clock rather than a
/// hand-copied list that goes stale the moment either duration moves.
pub fn tongueClock() foe.Clock {
    return .{ .wind = GAPE_DUR, .strike = SPIT_DUR, .recover = REEL_DUR };
}

pub fn lashClock() foe.Clock {
    return .{ .wind = SURGE_DUR, .strike = LASH_DUR, .recover = RECOVER_DUR };
}

/// The far edge of each band, for a bench that has to stand a body inside one.
pub fn bandOf(m: Move, scale: f32) f32 {
    return switch (m) {
        .lash => lashBand(scale),
        .tongue => tongueBand(scale),
    };
}

fn tongueGrip(scale: f32) f32 {
    return foe.HERO_R + TONGUE_SHAFT_R * scale;
}
fn tongueBand(scale: f32) f32 {
    return TONGUE_R * scale + tongueGrip(scale);
}

/// HOW FAR ROUND EACH WIND CAN ACTUALLY BRING THE KIT, in degrees — the turn its own tell buys plus what the kit
/// subtends at the far end of its band. SOLVED off `TURN_RATE` and the durations rather than picked, so retuning
/// either end cannot leave the gate behind.
fn windSweep(m: Move) f32 {
    const turn = mathx.degrees(TURN_RATE) * (switch (m) {
        .lash => SURGE_DUR,
        .tongue => GAPE_DUR,
    });
    // The skull answers a CONE and the shaft answers nothing but where it is pointing, so only the lash gets the
    // second term. `inFront`'s dot is a half-angle.
    return turn + (switch (m) {
        .lash => mathx.degrees(std.math.acos(LASH_FRONT_DOT)),
        .tongue => 0.0,
    });
}

/// CLOSE IS THE SKULL, FAR IS THE TONGUE, AND OFF THE TONGUE'S CLOCK AT RANGE IT DOES NEITHER — it comes up and
/// LOOMS. Both bands are taken off the constant the blow itself bills at, never an authored world metre: the editor
/// posts a body anywhere in `wf.FOE_SCALE_LO`..`HI` and a band that does not scale with the hurt box hands out a
/// blow that cannot land. It used to have no band at all and surged at anything inside `AGGRO_R` — nine metres
/// against a two-metre skull.
///
/// AND A BEARING THE WIND CANNOT COME ROUND TO IS A HARD GATE HERE, not a lower score: the tongue is a SHAFT with no
/// cone at all, so thrown at a man 170 degrees off it turned the 120 its own tell buys and fired 50 degrees past
/// him. A whiff is not a worse option, it is not an option — and what it falls through to is the LOOM, which turns.
fn classify(dist: f32, bearing: f32, scale: f32, tongueReady: bool) ?Move {
    if (dist <= lashBand(scale) and @abs(bearing) <= windSweep(.lash)) return .lash;
    if (tongueReady and dist <= tongueBand(scale) and @abs(bearing) <= windSweep(.tongue)) return .tongue;
    return null;
}

pub const SHOVE = foe.Push{ .light = 0.55, .heavy = 1.30 };
const SHOVE_DECAY: f32 = 9.0;


pub const N = 14;
const ROOT = 0;
const S0 = 1;
const S1 = 2;
const S2 = 3;
const S3 = 4;
const S4 = 5;
const HEAD = 6;
const JAW = 7;
const BARBL = 8;
const BARBR = 9;
/// THE TONGUE RIDES THE SKULL, NOT THE LOWER JAW. Hung off `JAW` it inherited the gape, and MEASURED that put the
/// pad 1.99 m UNDER the water at 2.84 m out: 6 degrees at the coil plus 10 at the skull plus the jaw's own 45 is a
/// shaft pitched 61 degrees into the mud. A tongue leaves along the head's axis and the mouth opens AROUND it.
const TONGUE = 10;
const TSEGS: usize = 4;
const TIP = TONGUE + TSEGS - 1;
const NECK = [_]usize{ S0, S1, S2, S3, S4 };
pub const PARENT = [N]i32{ -1, ROOT, S0, S1, S2, S3, S4, HEAD, HEAD, HEAD, HEAD, TONGUE, TONGUE + 1, TONGUE + 2 };

comptime {
    std.debug.assert(TIP + 1 == N);
}

const SEG: f32 = 0.185;

fn restPose() [N]rl.Vector3 {
    var r: [N]rl.Vector3 = undefined;
    r[ROOT] = v3(0, 0, 0);
    var y: f32 = 0;
    for (NECK, 0..) |b, i| {
        y += if (i == 0) SEG * H * 0.6 else SEG * H;
        r[b] = v3(0, y, 0);
    }
    r[HEAD] = v3(0, y + SEG * H * 0.85, 0);
    r[JAW] = v3(r[HEAD].x, r[HEAD].y - 0.030 * H, r[HEAD].z + 0.055 * H);
    r[BARBL] = v3(r[HEAD].x + 0.055 * H, r[HEAD].y - 0.010 * H, r[HEAD].z + 0.070 * H);
    r[BARBR] = v3(r[HEAD].x - 0.055 * H, r[HEAD].y - 0.010 * H, r[HEAD].z + 0.070 * H);
    // AUTHORED AT FULL LENGTH AND CURLED AWAY, never telescoped: the mesh is built once off this pose, so a rest
    // that shortened the chain would slide the segments apart and leave gaps down the shaft.
    r[TONGUE] = v3(r[HEAD].x, r[HEAD].y - 0.038 * H, r[HEAD].z + 0.105 * H);
    for (1..TSEGS) |k| {
        r[TONGUE + k] = v3(r[TONGUE].x, r[TONGUE].y, r[TONGUE].z + @as(f32, @floatFromInt(k)) * TONGUE_SEG);
    }
    return r;
}

// AUTHOR DARK, AND SOLVE IT — screen goes as albedo^(1/2.2). This hide comes up against the WATER SHEET, the brighter backdrop, so it is authored UNDER the ravager's.

const HIDE = rgba(9, 13, 11, 208);
const HIDE_LT = rgba(14, 19, 16, 194);
const HIDE_DK = rgba(5, 8, 7, 214);
const BELLY = rgba(48, 52, 42, 200);
const SILT = rgba(74, 68, 52, 190);
const EYE = rgba(180, 226, 150, 40);
const GULLET = rgba(122, 44, 48, 96);
const TOOTH = rgba(206, 200, 176, 235);
// WET MUSCLE, AND IT IS MATTER: authored at 248 per the alpha law, so it is dark because the ALBEDO is dark and not
// because a low alpha is holding a floor under the terminator. Screen goes as albedo^(1/2.2) x 1.72, so 58 lands
// near 166 in sun — a tongue, against a hide solved at half that.
const TONGUE_FLESH = rgba(58, 22, 26, 248);
const TONGUE_DK = rgba(38, 14, 18, 250);
const TONGUE_PAD = rgba(66, 28, 32, 248);

pub const State = enum { sunk, loom, surge, lash, gape, spit, reel, recover, sink, hurt, dead };

/// The lurker answers with a BLOW AND A HAUL, the way the rooted's hook does — one union rather than two returns,
/// because a pull with no hit behind it is a yank nobody was struck by.
pub const Act = union(enum) {
    none,
    struck: struct { hit: combat.Hit, pull: f32 },
};

pub const Model = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "fen lurker");
        return .{ .mesh = buildMeshes(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, l: *const Lurker) void {
        // A COILED TONGUE IS INSIDE THE MOUTH, so it is not drawn there: fully curled the four segments overlap the
        // skull, and a tangle showing through the crown is not a mouthful of anything.
        const shaft = l.ext > TONGUE_SHOW;
        for (0..N) |i| {
            if (i >= TONGUE and !shaft) continue;
            rl.drawMesh(self.mesh[i], self.mat, l.xf[i]);
        }
    }
};

pub const Lurker = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    wade: foe.Wade = .{},
    threat: foe.Threat = .{},

    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,
    state: State = .sunk,
    t: f32 = 0,
    elapsed: f32 = 0,
    restT: f32 = 0,

    /// HOW FAR OUT OF THE WATER IT IS, 0..1 — one scalar, read off the state's own clock and nowhere else. It is what the pose rides, what `hidden` is asked of, and what decides whether a sword can reach it.
    up: f32 = 0,
    swing: f32 = 0,
    swingL1: f32 = 0,
    swingL2: f32 = 0,

    move: Move = .lash,
    tongueCd: f32 = 0,
    /// HOW FAR THE TONGUE IS OUT, 0..1. Linear on the way out ON PURPOSE — a tongue leaves at a near-constant speed,
    /// and that is what lets `toImpact` be SOLVED for the range he is actually standing at instead of taken at a
    /// share of the stroke, which is right at exactly one distance and wrong at every other.
    ext: f32 = 0,
    extL: f32 = 0,
    /// How far off the quarry is, stamped every frame: the parry window is a TIME and the tongue's depends on it.
    aimD: f32 = 0,
    pull: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    heroLatch: bool = false,
    heroHit: ?combat.Hit = null,
    heavyStun: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    broke: bool = false,
    lashed: bool = false,
    gaped: bool = false,
    spat: bool = false,
    yelped: bool = false,
    sank: bool = false,
    parry: foe.Parry = .{},
    parried: bool = false,

    fade: f32 = 0,
    gone: bool = false,

    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    rest: [N]rl.Vector3 = undefined,
    xf: [N]rl.Matrix = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Lurker {
        var l = Lurker{
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale,
            .seed = seed,
            .rest = restPose(),
        };
        l.fxRng = foe.fxStream(seed, 60271.0, 0x3E7);
        l.restT = seed * REST_DUR;
        l.pose();
        return l;
    }

    pub fn kind(_: *const Lurker) wf.FoeKind {
        return .fen_lurker;
    }

    pub fn centerWorld(self: *const Lurker) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H * self.up, self.scale, 0);
    }
    pub fn lockPoint(self: *const Lurker) rl.Vector3 {
        return foe.markOn(self.xf[HEAD], v3(0, 0.02 * H, 0.05 * H));
    }
    /// HOW TALL THE CREATURE IS, NOT HOW FAR UP IT HAPPENS TO BE. Scaled by `up` it answered 0.43 m while down, and `shots.runMapShots` solves its camera off this BEFORE the pose.
    pub fn topWorld(self: *const Lurker) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * H, self.scale, 0);
    }
    pub fn hurtRadius(self: *const Lurker) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Lurker) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Lurker) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Lurker) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Lurker) bool {
        return self.state == .hurt or self.state == .dead;
    }
    pub fn airborne(_: *const Lurker) bool {
        return false;
    }
    pub fn flashFrac(self: *const Lurker) f32 {
        return foe.flashFrac(self.flash);
    }

    pub fn hidden(self: *const Lurker) bool {
        return self.up <= SHOW_AT;
    }

    /// SEPARATE from `hidden`, which is about being SEEN where this is about being SOLID. Without it `game.collideActors` pushes him out of a sunk lurker's full 2.9 m crown.
    pub fn phased(self: *const Lurker) bool {
        return self.hidden();
    }

    pub fn jawPoint(self: *const Lurker) rl.Vector3 {
        return foe.markOn(self.xf[JAW], v3(0, 0, 0.10 * H));
    }

    /// The far end of the pad, which is the far end of the reach.
    pub fn tipPoint(self: *const Lurker) rl.Vector3 {
        return foe.markOn(self.xf[TIP], v3(0, 0, TONGUE_SEG));
    }

    /// The shaft as ONE segment, mouth to pad — what the reach is MEASURED over.
    pub fn tongueSeg(self: *const Lurker) [2]rl.Vector3 {
        return .{ foe.markOn(self.xf[TONGUE], mathx.zero3), self.tipPoint() };
    }

    /// Its JOINTS, mouth to pad, because the bill is taken segment by segment the way the brood's claws are.
    /// `foe.weaponReaches` samples five points ALONG whatever it is handed, so given the whole 4.96 m shaft as one
    /// segment those samples sit 1.24 m apart against a 0.47 m grip — MEASURED, it passed clean through a man
    /// standing at 2.95 m and billed nothing at the one stand the tongue exists to punish.
    pub fn tongueJoints(self: *const Lurker) [TSEGS + 1]rl.Vector3 {
        var out: [TSEGS + 1]rl.Vector3 = undefined;
        for (0..TSEGS) |k| out[k] = foe.markOn(self.xf[TONGUE + k], mathx.zero3);
        out[TSEGS] = self.tipPoint();
        return out;
    }

    pub fn tonguing(self: *const Lurker) bool {
        return switch (self.state) {
            .gape, .spit, .reel => true,
            else => false,
        };
    }

    pub fn pooled(self: *const Lurker) bool {
        return self.wade.here >= POOL_MIN;
    }

    fn feels(self: *const Lurker, hero: rl.Vector3) bool {
        if (self.wade.quarry < WADE_MIN) return false;
        return mathx.distXZ(self.pos, hero) <= AGGRO_R;
    }

    fn faceToward(self: *Lurker, at: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, at, TURN_RATE, dt);
    }

    fn enter(self: *Lurker, s: State) void {
        self.state = s;
        self.t = 0;
    }

    pub fn update(self: *Lurker, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) Act {
        self.justDied = false;
        self.heroHit = null;
        self.pull = 0;
        self.broke = false;
        self.lashed = false;
        self.gaped = false;
        self.spat = false;
        self.yelped = false;
        self.sank = false;
        self.parried = false;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return .none;
        }
        self.stateStep(dt, hero, bounds);
        self.takeParry();
        self.tryHit(blade);
        const h = self.heroHit orelse return .none;
        return .{ .struck = .{ .hit = h, .pull = self.pull } };
    }

    /// Share of the tongue's own reach the quarry is standing at — 0 in its mouth, 1 at the far edge.
    fn spitShare(self: *const Lurker) f32 {
        return mathx.clampF(self.aimD / tongueBand(self.scale), 0, 1);
    }

    fn toImpact(self: *const Lurker) ?f32 {
        const at = LASH_DUR * LASH_IMPACT_K;
        return switch (self.state) {
            .surge => (SURGE_DUR - self.t) + at,
            .lash => at - self.t,
            // THE TONGUE'S ARRIVAL IS SOLVED FOR WHERE HE IS STANDING. One shaft crossing five metres at a constant
            // speed reaches a man at 3 m in a third of the time it reaches one at 4.8, so a share of the stroke is
            // right at exactly one range: the parry window would open late up close and early far out.
            .gape => (GAPE_DUR - self.t) + SPIT_DUR * self.spitShare(),
            .spit => SPIT_DUR * self.spitShare() - self.t,
            .sunk, .loom, .reel, .recover, .sink, .hurt, .dead => null,
        };
    }

    fn parryable(self: *const Lurker) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!self.parry.window(left)) return null;
        return if (self.tonguing()) tongueBand(self.scale) else lashBand(self.scale);
    }

    fn takeParry(self: *Lurker) void {
        const reach = self.parryable() orelse self.parry.reach() orelse return;
        if (!foe.caught(self, reach, self.toImpact(), null)) return;
        self.heroLatch = true;
        self.splash(foe.markOn(self.xf[if (self.tonguing()) TONGUE else HEAD], mathx.zero3), 8);
        self.enterStun(false);
    }

    fn stateStep(self: *Lurker, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);

        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        foe.fadeFlash(&self.flash, dt);
        self.restT = mathx.maxF(0, self.restT - dt);
        self.tongueCd = mathx.maxF(0, self.tongueCd - dt);
        // Stamped BEFORE the state machine, because `decide` and the parry window are both solved off it.
        self.aimD = mathx.distXZ(self.pos, hero);
        foe.tickFixedLeash(&self.leash, dt, self.home, hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        switch (self.state) {
            .dead => {
                self.up = mathx.approach(self.up, 0, dt / SINK_DUR);
                self.ext = mathx.approach(self.ext, 0, dt * 5.0);
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
            .hurt => {
                self.up = mathx.approach(self.up, 1.0, dt * 2.2);
                // A FLINCH SWALLOWS THE TONGUE. Left out it hung in the air through the whole stagger, and the shaft
                // was still billing off a body that had stopped throwing it.
                self.ext = mathx.approach(self.ext, 0, dt * 8.0);
                if (self.t >= combat.foeStunDur(self.heavyStun)) self.enter(.recover);
            },
            .sunk => {
                self.ext = 0;
                if (!self.pooled()) {
                    self.up = mathx.approach(self.up, 1.0, dt / SINK_DUR);
                    if (self.feelsDry(hero)) _ = self.decide(hero);
                    return self.settleAndPose(dt);
                }
                self.up = mathx.approach(self.up, 0, dt / SINK_DUR);
                if (self.restT <= 0 and self.feels(hero)) {
                    self.broke = true;
                    _ = self.decide(hero);
                }
            },
            // OFF EVERY BAND IT LOOMS, AND LOOMING IS THE TURN. A gate at the choose with nothing behind it is a
            // hole: it used to strike at anything inside `AGGRO_R`, so nine metres out it surged, whiffed and sank.
            .loom => {
                self.up = mathx.approach(self.up, 1.0, dt / SURGE_DUR);
                self.ext = mathx.approach(self.ext, 0, dt * 6.0);
                self.swing = mathx.approach(self.swing, 0, dt * 2.0);
                self.faceToward(hero, dt);
                if (!self.canEngage(hero)) {
                    if (self.pooled()) self.beginSink() else self.enter(.sunk);
                } else _ = self.decide(hero);
            },
            .surge => {
                self.faceToward(hero, dt);
                // A SURGE ONLY EVER RISES: the clock is resumed part-way through on a chained stroke, and read straight off it a body already up teleported back DOWN 1.7 m.
                self.up = mathx.maxF(self.up, mathx.smoothstep(0, SURGE_DUR, self.t));
                self.swing = -mathx.smoothstep(SURGE_DUR * 0.35, SURGE_DUR, self.t);
                if (self.t >= SURGE_DUR) {
                    self.enter(.lash);
                    self.lashed = true;
                }
            },
            .lash => {
                self.up = 1.0;
                const u = mathx.clampF(self.t / LASH_DUR, 0, 1);
                self.swing = lerpF(-1.0, 1.0, foe.swingCurve(u));
                // The skull is still reared at u 0; it is down from `LASH_IMPACT_K`, which is where the parry window says it is.
                if (u >= LASH_IMPACT_K) self.tryLash(hero);
                if (self.t >= LASH_DUR) self.enter(.recover);
            },
            // THE TONGUE'S WIND, AND IT IS THE LONGEST TELL THE CREATURE HAS: the coil rears, the skull pitches down
            // onto his line and the jaws come apart around a tongue you can see loading in the throat.
            .gape => {
                const u = mathx.clampF(self.t / GAPE_DUR, 0, 1);
                // UP FIRST, THEN LOAD. Surfacing over the whole tell left it half submerged at 0.41 s of a 0.95 s
                // wind, which is the same picture the lash's surge draws — so what the tongue's tell is FOR only
                // began to read once it was nearly spent.
                self.up = mathx.maxF(self.up, mathx.smoothstep(0, GAPE_DUR * GAPE_RISE, self.t));
                self.ext = 0;
                // IT REARS BACK AND SNAPS FORWARD, the way a bow is drawn. A mouth opening on a body that does not
                // move is not a tell, and this is the longest one the creature has. RELEASED before the shaft goes,
                // because the rear-back's own head pitch runs against `GAPE_PITCH`: held to the spit it cancels the
                // aim and five metres of tongue leaves level, over his crown.
                self.swing = -GAPE_REAR * (if (u < GAPE_LOAD)
                    mathx.smoothstep(0, GAPE_LOAD, u)
                else
                    1.0 - mathx.smoothstep(GAPE_LOAD, 1.0, u));
                self.faceToward(hero, dt);
                if (self.t >= GAPE_DUR) self.enter(.spit);
            },
            .spit => {
                self.up = 1.0;
                // THE SWEEP IS TAKEN ACROSS THE FRAME, so the pose the bill reads is THIS frame's and the one it is
                // swept from is last frame's — which is why the pose runs here and the bill after it.
                const was = self.tongueJoints();
                self.ext = mathx.clampF(self.t / SPIT_DUR, 0, 1);
                if (self.t >= SPIT_DUR) {
                    self.enter(.reel);
                    self.spat = true;
                }
                self.settleAndPose(dt);
                self.tryTongue(was, hero);
                return;
            },
            // THE REEL DOES NOT BILL. Dodging five metres of tongue buys the whole haul-back plus the recovery, and
            // a shaft that took him on its way home would be the same blow twice off one commitment.
            .reel => {
                self.up = 1.0;
                self.ext = 1.0 - mathx.smoothstep(0, REEL_DUR, self.t);
                if (self.t >= REEL_DUR) self.enter(.recover);
            },
            .recover => {
                self.up = 1.0;
                self.ext = mathx.approach(self.ext, 0, dt * 6.0);
                self.swing = mathx.approach(self.swing, 0, dt * 2.6);
                self.heroLatch = false;
                if (self.t >= self.recoverDur()) {
                    if (!self.canEngage(hero)) {
                        if (self.pooled()) self.beginSink() else self.enter(.sunk);
                    } else if (self.decide(hero) and self.move == .lash) {
                        // A CHAINED LASH RESUMES ITS WIND PART-WAY: the body is already up, so the rise is not paid
                        // twice. The TONGUE always pays its whole tell — it has to load, and that is its fairness.
                        self.t = SURGE_DUR * 0.45;
                    }
                }
            },
            .sink => {
                self.up = 1.0 - mathx.smoothstep(0, SINK_DUR, self.t);
                self.ext = mathx.approach(self.ext, 0, dt * 6.0);
                self.swing = mathx.approach(self.swing, 0, dt * 2.0);
                if (self.pooled() and self.canEngage(hero)) {
                    if (self.decide(hero) and self.move == .lash) self.t = SURGE_DUR * self.up;
                    if (self.state != .sink) return self.settleAndPose(dt);
                }
                if (self.t >= SINK_DUR) {
                    self.restT = REST_DUR;
                    self.enter(.sunk);
                }
            },
        }
        self.settleAndPose(dt);
    }

    fn recoverDur(self: *const Lurker) f32 {
        return switch (self.move) {
            .lash => RECOVER_DUR,
            .tongue => TONGUE_RECOVER,
        };
    }

    /// Is there anything to fight at all? A POOLED one only answers a body standing IN its water — dry land is the
    /// whole counter to it; one with no pool under it stands up to anyone inside its ring.
    fn canEngage(self: *const Lurker, hero: rl.Vector3) bool {
        if (self.leash.goingHome()) return false;
        return if (self.pooled()) self.feels(hero) else self.feelsDry(hero);
    }

    /// Throws whatever its own bands ask for and answers whether one was thrown. Nothing in band is `.loom`, and the
    /// guard on the re-enter is load-bearing: without it the loom's clock resets on every frame it re-decides.
    fn decide(self: *Lurker, hero: rl.Vector3) bool {
        const want = classify(self.aimD, foe.bearingDeg(self.pos, self.facing, hero), self.scale, self.tongueCd <= 0) orelse {
            if (self.state != .loom) self.enter(.loom);
            return false;
        };
        self.begin(hero, want);
        return true;
    }

    fn begin(self: *Lurker, hero: rl.Vector3, which: Move) void {
        self.faceToward(hero, 1.0);
        self.move = which;
        self.heroLatch = false;
        switch (which) {
            .lash => {
                self.enter(.surge);
                self.lashed = false;
            },
            .tongue => {
                self.tongueCd = TONGUE_CD;
                self.enter(.gape);
                self.gaped = true;
            },
        }
    }

    fn feelsDry(self: *const Lurker, hero: rl.Vector3) bool {
        return mathx.distXZ(self.pos, hero) <= AGGRO_R;
    }

    fn beginSink(self: *Lurker) void {
        self.enter(.sink);
        self.sank = true;
    }

    fn settleAndPose(self: *Lurker, dt: f32) void {
        self.swingL1 = mathx.approach(self.swingL1, self.swing, dt * LAG_1);
        self.swingL2 = mathx.approach(self.swingL2, self.swingL1, dt * LAG_2);
        self.extL = mathx.approach(self.extL, self.ext, dt * EXT_LAG);
        self.pose();
    }

    fn tryLash(self: *Lurker, hero: rl.Vector3) void {
        if (self.heroLatch) return;
        if (!foe.inFront(self.pos, self.facing, hero, lashBand(self.scale), LASH_FRONT_DOT)) return;
        self.heroHit = LASH_HIT;
        self.heroLatch = true;
        self.leash.noteCombat();
    }

    /// A SWEPT SEGMENT, SO IT BILLS WHERE THE EDGE CROSSES HIM rather than at a share of the stroke — and the segment
    /// is the WHOLE shaft, jaw to tip, not the pad: five metres of muscle passing through a man takes him whether the
    /// end of it stopped at his chest or went three metres past his shoulder.
    fn tryTongue(self: *Lurker, was: [TSEGS + 1]rl.Vector3, hero: rl.Vector3) void {
        if (self.heroLatch) return;
        const now = self.tongueJoints();
        const r = tongueGrip(self.scale);
        var caught = false;
        for (0..TSEGS) |k| {
            if (foe.weaponReaches(.{ was[k], was[k + 1] }, .{ now[k], now[k + 1] }, hero, r)) caught = true;
        }
        if (!caught) return;
        self.heroHit = TONGUE_HIT;
        self.pull = TONGUE_PULL * self.scale;
        self.heroLatch = true;
        self.leash.noteCombat();
        self.splash(self.tipPoint(), 7);
    }

    pub fn tryHit(self: *Lurker, blade_: foe.Blade) void {
        if (self.state == .dead or self.hidden()) return;
        const s = foe.reached(self, blade_) orelse return;
        const heavy = foe.wounded(self, s, blade_, SHOVE);
        self.splash(s.contact, if (heavy) 9 else 4);
        switch (s.reaction) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(true),
            .light => self.enterStun(false),
            .none => {},
        }
    }

    fn enterStun(self: *Lurker, heavy: bool) void {
        self.enter(.hurt);
        self.heavyStun = heavy;
        self.yelped = true;
    }

    fn enterDeath(self: *Lurker) void {
        if (self.state == .dead) return;
        self.enter(.dead);
        self.justDied = true;
    }

    pub fn stagger(self: *Lurker, heavy: bool) void {
        self.enterStun(heavy);
    }

    pub fn stageGather(self: *Lurker, u: f32) void {
        const k = mathx.clampF(u, 0, 1);
        self.state = .surge;
        self.t = k * SURGE_DUR;
        self.up = mathx.smoothstep(0, SURGE_DUR, self.t);
        self.swing = -mathx.smoothstep(SURGE_DUR * 0.35, SURGE_DUR, self.t);
        self.swingL1 = self.swing;
        self.swingL2 = self.swing;
        self.pose();
    }

    /// The tongue's WIND, at `u` of it — the jaws apart and the skull down on his line, nothing out yet.
    pub fn stageGape(self: *Lurker, u: f32) void {
        const k = mathx.clampF(u, 0, 1);
        self.state = .gape;
        self.t = k * GAPE_DUR;
        self.up = 1.0;
        self.swing = 0;
        self.swingL1 = 0;
        self.swingL2 = 0;
        self.ext = 0;
        self.extL = 0;
        self.pose();
    }

    /// The tongue OUT, at `u` of its extension. `u` 1 is the full reach the band is measured against.
    pub fn stageSpit(self: *Lurker, u: f32) void {
        const k = mathx.clampF(u, 0, 1);
        self.state = .spit;
        self.t = k * SPIT_DUR;
        self.up = 1.0;
        self.swing = 0;
        self.swingL1 = 0;
        self.swingL2 = 0;
        self.ext = k;
        self.extL = k;
        self.pose();
    }

    pub fn stageLash(self: *Lurker, u: f32) void {
        const k = mathx.clampF(u, 0, 1);
        self.state = .lash;
        self.t = k * LASH_DUR;
        self.up = 1.0;
        self.swing = lerpF(-1.0, 1.0, foe.swingCurve(k));
        self.swingL1 = self.swing;
        self.swingL2 = self.swing;
        self.pose();
    }

    fn splash(self: *Lurker, at: rl.Vector3, n: i32) void {
        var i: i32 = 0;
        const total = foe.hitParts(n);
        while (i < total) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.7, 2.1);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = at,
                .v = v3(mathx.cosf(a) * sp, self.fxRng.range(0.8, 2.6), mathx.sinf(a) * sp),
                .life = self.fxRng.range(0.24, 0.50),
                .r0 = self.fxRng.range(0.022, 0.050) * self.scale,
                .r1 = 0.005,
                .col = if (self.fxRng.float() < 0.5) SPRAY else SILT,
                .grav = 7.0,
                .stretch = 0.040,
            });
        }
    }

    fn ripple(self: *Lurker, dt: f32) void {
        const n = foe.emitDue(&self.fxAccum, dt, WAKE_RATE);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.25, 1.0) * WAKE_R * self.scale;
            const p = v3(self.pos.x + mathx.cosf(a) * rr, self.pos.y + WAKE_Y, self.pos.z + mathx.sinf(a) * rr);
            const B = comptime foe.Blast.of(WAKE_DRAG, 0.30, 0.62);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = p,
                .v = v3(mathx.cosf(a) * WAKE_SPREAD * B.boost, 0.02, mathx.sinf(a) * WAKE_SPREAD * B.boost),
                .life = B.life(&self.fxRng),
                .r0 = self.fxRng.range(0.020, 0.038) * self.scale,
                .r1 = 0.055,
                .col = SPRAY,
                .col1 = SPRAY_FLAT,
                .drag = WAKE_DRAG,
            });
        }
    }

    pub fn drawFx(self: *const Lurker) void {
        foe.drawParticles(&self.parts);
    }

    pub fn draw(self: *const Lurker, model: *const Model) void {
        if (self.gone or self.hidden()) return;
        model.draw(self);
    }

    pub fn pose(self: *Lurker) void {
        if (!foe.posed(self)) return;
        const s = self.scale;
        const react: f32 = if (self.state == .hurt) foe.stunCurve(self.t, self.heavyStun) else 0;
        const fall: f32 = if (self.state == .dead) mathx.clampF(self.t / (DEATH_DUR * 0.7), 0, 1) else 0;
        const sink = -(1.0 - self.up) * SUBMERGE * H;
        const breath = mathx.sinf(self.elapsed * 1.35 + self.seed * 6.28) * 0.010 * H * self.up;

        // THE WHOLE BODY DIVES WITH THE STROKE. A curled chain moves the head SIDEWAYS more than down — measured, five distributed bends finished the lash at 2.04 m, over his head.
        const dive = LASH_DIVE * mathx.maxF(0, self.swing);
        // HOW FAR THE TONGUE'S OWN AIM IS IN, 0..1 — the lean and the skull's pitch ride it, and it holds through
        // the spit and the reel so the shaft does not swing while it is out.
        const aim: f32 = switch (self.state) {
            .gape => mathx.smoothstep(0, GAPE_DUR * 0.75, self.t),
            .spit, .reel => 1.0,
            else => self.extL,
        };
        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            mul(scaleM(s, s, s), mul(rx(dive + GAPE_LEAN * aim), rz(-38.0 * mathx.smoothstep(0, 1, fall)))),
            mul(tr(0, (sink + breath) * s, 0), ry(mathx.degrees(self.facing))),
            heromod.rootAt(self.pos),
        );

        for (NECK, 0..) |b, i| {
            const u = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(NECK.len - 1));
            const lagged = switch (i) {
                0 => self.swing,
                1, 2 => self.swingL1,
                else => self.swingL2,
            };
            const bend = lerpF(SEG_BEND_LO, SEG_BEND_HI, u) * lagged;
            const idle = mathx.sinf(self.elapsed * 1.1 - u * 2.2 + self.seed * 4.0) * IDLE_SWAY * (1.0 - @abs(lagged));
            heromod.setJoint(&wx, &self.rest, b, if (i == 0) ROOT else NECK[i - 1], mul(rx(bend + 14.0 * react * u), rz(idle)));
        }
        heromod.setJoint(&wx, &self.rest, HEAD, S4, mul(rx(HEAD_BEND * self.swing - 26.0 * react + GAPE_PITCH * aim), rz(-6.0 * self.swingL2)));
        const gape = GAPE * mathx.clampF(self.swing * 0.5 + 0.5, 0, 1) * self.up + TONGUE_GAPE * aim - 34.0 * react;
        heromod.setJoint(&wx, &self.rest, JAW, HEAD, rx(gape));
        const trail = -18.0 * self.swingL2 + 10.0 * react;
        const flare = BARB_SPLAY * (1.0 + 0.55 * aim);
        heromod.setJoint(&wx, &self.rest, BARBL, HEAD, mul(rx(trail), rz(-flare - 5.0 * self.swingL2)));
        heromod.setJoint(&wx, &self.rest, BARBR, HEAD, mul(rx(trail), rz(flare + 5.0 * self.swingL2)));

        // A TELESCOPE, NOT A COIL, and it is ONE Z SCALE on the first tongue joint. `setJoint` translates by the
        // rest offset AFTER the local matrix and then through the parent's, so a scale there takes the whole chain
        // with it — every segment's length AND every offset under it — and the tip travels a STRAIGHT line along the
        // skull's own axis. MEASURED with a curl instead: four joints at 142 degrees each still hold 69 degrees of
        // accumulated bend at 0.88 of the way out, so the shaft left the mouth, ELBOWED, and dived into the mud
        // short of the man it was thrown at. It is also what makes `ext` linear in the tip's distance, which is what
        // `toImpact` solves the parry window off.
        const grow = mathx.maxF(self.ext, 1e-3);
        const droop = TONGUE_DROOP * (1.0 - self.ext);
        const whip = TONGUE_WAVER * (self.ext - self.extL);
        for (0..TSEGS) |k| {
            const b = TONGUE + k;
            const bend = mul(rx(droop), rz(whip));
            heromod.setJoint(&wx, &self.rest, b, if (k == 0) HEAD else b - 1, if (k == 0) mul(scaleM(1, 1, grow), bend) else bend);
        }
        self.xf = wx;
    }
};

const SUBMERGE: f32 = 1.18;
const SHOW_AT: f32 = 0.06;

/// THESE COMPOUND — each joint rotates relative to its PARENT, so the head ends up at the SUM down the chain. Authored as absolutes (9 rising to 27, plus 34) the rear came to 124 degrees. `TOTAL_BEND` is the sum and a test pins it.
const SEG_BEND_LO: f32 = 3.5;
const SEG_BEND_HI: f32 = 11.0;
const HEAD_BEND: f32 = 15.0;
const TOTAL_BEND: f32 = blk: {
    var sum: f32 = 0;
    for (0..NECK.len) |i| {
        const u = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(NECK.len - 1));
        sum += SEG_BEND_LO + (SEG_BEND_HI - SEG_BEND_LO) * u;
    }
    break :blk sum + HEAD_BEND;
};
comptime {
    std.debug.assert(TOTAL_BEND > 35.0 and TOTAL_BEND < 80.0);
}
/// HOW FAR THE WHOLE COIL TIPS OVER ACROSS THE STROKE. Solved against the measured jaw height — at 0 the lash finished at 2.04 m, a third of a metre over his crown.
const LASH_DIVE: f32 = 46.0;
const LAG_1: f32 = 15.0;
const LAG_2: f32 = 9.0;
const IDLE_SWAY: f32 = 3.2;
const GAPE: f32 = 38.0;
const BARB_SPLAY: f32 = 26.0;

/// HOW THE SHAFT IS LAID THROUGH HIS OWN HEIGHT, and it is a PITCH and not a lean. MEASURED: the jaw rides 2.71 m
/// reared and the tongue leaves along the skull's own axis, so fired level it passed over a 1.71 m crown for the
/// first two metres of its run. 6 at the coil and 10 at the skull puts it in his chest from the near edge of the
/// band out and knee-high at the far end — and a big lean cannot do this job, because tipping the coil 30 degrees
/// pitches the head's forward axis with it and drives the tip two and a half metres underground.
const GAPE_LEAN: f32 = 6.0;
/// SOLVED, NOT PICKED: at 16 degrees of total pitch the shaft crossed the near edge of its own band at 1.74 m — three
/// centimetres over a 1.71 m crown, so the one stand the tongue exists to punish was the one it flew over. 20 puts it
/// at 1.52 m there and 0.77 m at the pad, which is chest down to thigh across the whole run.
const GAPE_PITCH: f32 = 14.0;
/// Degrees the jaws come apart ON TOP of the idle gape, so the loaded tongue is visible in the throat before it goes.
const TONGUE_GAPE: f32 = 26.0;
/// A SHAFT STILL COMING OUT SAGS, per joint, and it is nothing at all once it is out. Small on purpose: this is
/// character on a straight line, not the arc a coil was drawing.
const TONGUE_DROOP: f32 = 5.0;
/// Under this much extension the shaft is not drawn: coiled it overlaps the skull, and a tangle through the crown is
/// not a mouthful of anything.
const TONGUE_SHOW: f32 = 0.02;
const TONGUE_WAVER: f32 = 26.0;
const EXT_LAG: f32 = 11.0;
/// The shaft's own taper, as a share of `H` at the root and at the pad. At 0.052 it measured 27 cm through at the
/// mouth over a 4.96 m run and photographed as a PIPE — a tongue is thin and it tapers hard, so what reads at the
/// far end is the PAD and not the shaft carrying it.
const TONGUE_R0: f32 = 0.030;
const TONGUE_R1: f32 = 0.008;
/// The pad, as a share of `H`, and the hooks under it. The widest part of the whole appendage on purpose.
const TONGUE_PAD_R: f32 = 0.075;
const TONGUE_HOOK: f32 = 0.052;

const WAKE_RATE: f32 = 16.0;
const WAKE_R: f32 = 0.85;
const WAKE_SPREAD: f32 = 0.55;
const WAKE_Y: f32 = 0.06;
const SPRAY = rgba(150, 162, 152, 175);
const SPRAY_FLAT = rgba(178, 190, 186, 55);
const WAKE_DRAG: f32 = 2.4;

const CAP_N = wf.MAX_PER_KIND;

pub const Marsh = struct {
    model: Model,
    eels: [CAP_N]Lurker = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Marsh {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Marsh) []Lurker {
        return self.eels[0..self.n];
    }
    pub fn liveConst(self: *const Marsh) []const Lurker {
        return self.eels[0..self.n];
    }
    pub fn reset(self: *Marsh, m: *const wf.Map) void {
        foe.resetGroup(Lurker, &self.eels, &self.n, m, .fen_lurker);
    }
    pub fn clear(self: *Marsh) void {
        self.n = 0;
    }
    pub fn setShader(self: *Marsh, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn update(
        self: *Marsh,
        dt: f32,
        hero: rl.Vector3,
        bounds: f32,
        blade: foe.Blade,
        ctx: anytype,
        comptime yank: fn (@TypeOf(ctx), rl.Vector3, f32) void,
    ) ?foe.Blow {
        for (self.live()) |*l| {
            if (foe.corporeal(l) and l.hidden() and l.pooled()) l.ripple(dt);
        }
        var blow: ?foe.Blow = null;
        for (self.live()) |*l| {
            switch (l.update(dt, l.threat.aim(hero), bounds, blade)) {
                .none => {},
                .struck => |s| {
                    foe.worseBlow(&blow, s.hit, l.pos, &l.threat);
                    if (s.pull > 0) yank(ctx, l.pos, s.pull);
                },
            }
        }
        return blow;
    }
    pub fn draw(self: *const Marsh, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Marsh) void {
        for (self.liveConst()) |*l| l.drawFx();
    }
    pub fn setParry(self: *Marsh, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    pub fn anyParried(self: *const Marsh) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn pierce(self: *Marsh, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Marsh) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Marsh) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Marsh) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Marsh) u32 {
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

fn buildBone(b: *Builder, i: usize, rest: [N]rl.Vector3) void {
    var rng = mathx.Rng.init(0xFE41 + @as(u64, @intCast(i)));
    switch (i) {
        ROOT => {
            b.addBlob(v3(0, 0.02 * H, -0.02 * H), v3(0.30 * H, 0.16 * H, 0.34 * H), 11, 7, HIDE);
            b.addBlob(v3(0, -0.05 * H, 0.06 * H), v3(0.24 * H, 0.11 * H, 0.26 * H), 9, 6, BELLY);
            b.addBlob(v3(0.03 * H, 0.11 * H, -0.06 * H), v3(0.19 * H, 0.09 * H, 0.22 * H), 9, 6, HIDE_DK);
            var k: u32 = 0;
            while (k < 5) : (k += 1) {
                const t = @as(f32, @floatFromInt(k)) / 4.0;
                b.addBlob(
                    v3(rng.range(-0.02, 0.02) * H, 0.14 * H - t * 0.03 * H, (-0.16 + t * 0.30) * H),
                    v3(0.030 * H * rng.range(0.7, 1.3), 0.038 * H * rng.range(0.8, 1.4), 0.048 * H),
                    6,
                    4,
                    HIDE_DK,
                );
            }
        },
        S0, S1, S2, S3, S4 => {
            const above: usize = if (i == S4) HEAD else i + 1;
            const len = mathx.lenV(mathx.subV(rest[above], rest[i]));
            const t = @as(f32, @floatFromInt(i - S0)) / @as(f32, @floatFromInt(NECK.len - 1));
            // A NECK, NOT A TENTACLE: at 0.135·H the base was 0.69 m through on a creature whose skull is 0.75 m wide. Sized against the HEAD instead.
            const r0 = lerpF(0.082, 0.058, t) * H;
            const r1 = lerpF(0.074, 0.052, t) * H;
            b.addCapsule(v3(0, 0, 0), v3(0, len * 0.98, 0), r0, r1, 10, HIDE);
            b.addCapsule(v3(0, 0.02 * len, r0 * 0.42), v3(0, len * 0.92, r1 * 0.40), r0 * 0.44, r1 * 0.42, 8, BELLY);
            var k: u32 = 0;
            while (k < 4) : (k += 1) {
                const a = @as(f32, @floatFromInt(k)) / 4.0 * std.math.tau + rng.range(-0.2, 0.2);
                b.addBlob(
                    v3(mathx.cosf(a) * r0 * 0.92, len * 0.12, mathx.sinf(a) * r0 * 0.92),
                    v3(0.026 * H * rng.range(0.8, 1.3), 0.030 * H, 0.026 * H),
                    5,
                    4,
                    HIDE_LT,
                );
            }
        },
        HEAD => {
            b.addBlob(v3(0, 0.010 * H, 0.055 * H), v3(HEAD_R * H * 0.86, 0.062 * H, 0.155 * H), 11, 7, HIDE);
            b.addBlob(v3(0, -0.012 * H, 0.030 * H), v3(HEAD_R * H * 0.72, 0.042 * H, 0.120 * H), 9, 6, BELLY);
            b.addBlob(v3(0, 0.004 * H, 0.150 * H), v3(0.082 * H, 0.046 * H, 0.058 * H), 8, 6, HIDE_LT);
            // THE EYES SIT PROUD OF THE DOME — the one place the relief law does not apply. Sunk to y 0.048 against a crown at 0.072 they were INSIDE the mass.
            b.addBlob(v3(0.086 * H, 0.064 * H, 0.058 * H), v3(0.030 * H, 0.028 * H, 0.030 * H), 6, 5, EYE);
            b.addBlob(v3(-0.084 * H, 0.063 * H, 0.056 * H), v3(0.029 * H, 0.027 * H, 0.029 * H), 6, 5, EYE);
            b.addBlob(v3(0.094 * H, 0.050 * H, 0.010 * H), v3(0.038 * H, 0.020 * H, 0.048 * H), 6, 4, HIDE_DK);
            b.addBlob(v3(-0.092 * H, 0.049 * H, 0.008 * H), v3(0.037 * H, 0.019 * H, 0.047 * H), 6, 4, HIDE_DK);
            var k: u32 = 0;
            while (k < 7) : (k += 1) {
                const x = (@as(f32, @floatFromInt(k)) - 3.0) * 0.026 * H;
                const l = 0.020 * H * rng.range(0.6, 1.35);
                b.addCapsule(
                    v3(x, -0.026 * H, 0.100 * H + rng.range(-0.010, 0.010) * H),
                    v3(x + rng.range(-0.004, 0.004) * H, -0.026 * H - l, 0.104 * H),
                    0.008 * H,
                    0.005 * H,
                    5,
                    TOOTH,
                );
            }
        },
        JAW => {
            b.addBlob(v3(0, -0.014 * H, 0.070 * H), v3(0.098 * H, 0.030 * H, 0.130 * H), 9, 6, HIDE);
            b.addBlob(v3(0, 0.004 * H, 0.060 * H), v3(0.078 * H, 0.020 * H, 0.105 * H), 8, 5, GULLET);
            var k: u32 = 0;
            while (k < 6) : (k += 1) {
                const x = (@as(f32, @floatFromInt(k)) - 2.5) * 0.028 * H;
                const l = 0.017 * H * rng.range(0.6, 1.3);
                b.addCapsule(
                    v3(x, 0.010 * H, 0.098 * H),
                    v3(x + rng.range(-0.004, 0.004) * H, 0.010 * H + l, 0.102 * H),
                    0.007 * H,
                    0.005 * H,
                    5,
                    TOOTH,
                );
            }
        },
        TONGUE, TONGUE + 1, TONGUE + 2, TIP => {
            const k = i - TONGUE;
            const t0 = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(TSEGS));
            const t1 = @as(f32, @floatFromInt(k + 1)) / @as(f32, @floatFromInt(TSEGS));
            const r0 = lerpF(TONGUE_R0, TONGUE_R1, t0) * H;
            const r1 = lerpF(TONGUE_R0, TONGUE_R1, t1) * H;
            b.addCapsule(v3(0, 0, 0), v3(0, 0, TONGUE_SEG), r0, r1, 9, TONGUE_FLESH);
            // A WET ORGAN IS NOT A DOWEL. Lumps along the underside, seeded off the bone index so the build stays
            // deterministic, and BETWEEN the segments rather than along one — four identical beads down a shaft
            // band it like a barber's pole.
            var m: u32 = 0;
            while (m < 4) : (m += 1) {
                const u = (@as(f32, @floatFromInt(m)) + 0.5) / 4.0;
                const rr = lerpF(r0, r1, u);
                b.addBlob(
                    v3(rng.range(-0.34, 0.34) * rr, -rr * 0.52, u * TONGUE_SEG),
                    v3(rr * rng.range(0.34, 0.62), rr * 0.40, rr * rng.range(0.7, 1.3)),
                    6,
                    4,
                    TONGUE_DK,
                );
            }
            if (i == TIP) {
                // THE PAD IS WHAT TAKES HOLD OF HIM, so it is SIZED IN THE WORLD and not off the shaft's tip radius.
                // Scaled off `r1` it came to 16 cm at the end of a 4.96 m run and photographed as a BEAD; a grip has
                // to read from the far side of its own band, which is what the whole appendage is for. Blunt, too —
                // a swollen end over a fan of short hooks, never a dart.
                const pr = TONGUE_PAD_R * H;
                b.addBlob(v3(0, 0, TONGUE_SEG), v3(pr, pr * 0.66, pr * 1.15), 11, 8, TONGUE_PAD);
                b.addBlob(v3(0, -pr * 0.34, TONGUE_SEG - pr * 0.26), v3(pr * 0.70, pr * 0.40, pr * 0.74), 9, 6, TONGUE_DK);
                // A CUP, NOT A DISC: a rim proud of the underside is what a grip looks like from in front of it.
                b.addBlob(v3(0, pr * 0.30, TONGUE_SEG + pr * 0.22), v3(pr * 0.62, pr * 0.34, pr * 0.44), 9, 6, TONGUE_FLESH);
                var h: u32 = 0;
                while (h < 5) : (h += 1) {
                    const a = (@as(f32, @floatFromInt(h)) - 2.0) * 0.46 + rng.range(-0.06, 0.06);
                    const l = TONGUE_HOOK * H * rng.range(0.75, 1.3);
                    b.addCapsule(
                        v3(mathx.sinf(a) * pr * 0.72, -pr * 0.30, TONGUE_SEG + mathx.cosf(a) * pr * 0.80),
                        v3(mathx.sinf(a) * pr * 0.92, -pr * 0.30 - l, TONGUE_SEG + mathx.cosf(a) * pr * 0.50),
                        TONGUE_HOOK * H * 0.22,
                        TONGUE_HOOK * H * 0.11,
                        5,
                        TOOTH,
                    );
                }
            }
        },
        BARBL, BARBR => {
            const side: f32 = if (i == BARBL) 1.0 else -1.0;
            var at = v3(0, 0, 0);
            var k: u32 = 0;
            while (k < 3) : (k += 1) {
                const l = 0.070 * H * rng.range(0.8, 1.2);
                const to = v3(
                    at.x + side * l * 0.30 * rng.range(0.6, 1.4),
                    at.y - l * (0.20 + 0.22 * @as(f32, @floatFromInt(k))),
                    at.z + l * 0.72,
                );
                b.addCapsule(at, to, 0.014 * H / (1.0 + 0.4 * @as(f32, @floatFromInt(k))), 0.011 * H / (1.0 + 0.5 * @as(f32, @floatFromInt(k))), 5, HIDE_LT);
                at = to;
            }
            b.addBlob(at, v3(0.013 * H, 0.011 * H, 0.013 * H), 5, 4, BELLY);
        },
        else => {},
    }
}


test "IT IS A FOE, AND IT ANSWERS THE SHARED CONTRACT OFF ONE BODY" {
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectEqual(wf.FoeKind.fen_lurker, l.kind());
    try std.testing.expect(l.alive() and !l.dying() and !l.staggered());
    try std.testing.expect(!l.airborne());
    try std.testing.expect(l.hurtRadius() > l.bodyR());
    _ = l.vit.hit(.{ .dmg = 5, .poise = POISE_MAX + 1 });
    l.stagger(true);
    try std.testing.expect(l.staggered());
    l.vit.hp = 0;
    l.enterDeath();
    try std.testing.expect(l.dying() and l.justDied);
}

test "SUNK IT IS NOT THERE — no reticle, no bar, and a sword goes through the water" {
    const swing = foe.Blade{
        .active = true,
        .r = 0.4,
        .a = v3(0, 0.4, -2.0),
        .b = v3(0, 0.4, 2.0),
        .a0 = v3(0, 0.4, -2.0),
        .b0 = v3(0, 0.4, 2.0),
        .hit = .{ .dmg = 9, .poise = 3 },
    };
    var down = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(down.hidden());
    down.tryHit(swing);
    try std.testing.expectEqual(@as(u32, 0), down.hits);
    try std.testing.expectApproxEqAbs(HP_MAX, down.vit.hp, 1e-4);

    var up = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    up.stageLash(0.5);
    try std.testing.expect(!up.hidden());
    up.tryHit(swing);
    try std.testing.expectEqual(@as(u32, 1), up.hits);
    try std.testing.expect(up.vit.hp < HP_MAX);
}

test "A SUNK ONE IS NOT IN HIS WAY — no wall he cannot see, and it goes solid the moment it is up" {
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(l.hidden() and l.phased());
    try std.testing.expect(l.topWorld().y - l.pos.y > H);

    l.stageGather(1.0);
    try std.testing.expect(!l.phased());
    try std.testing.expect(l.bodyR() > 0);
}

test "THE WATER IS THE TRIGGER, AND IT IS A FACT ABOUT THE GROUND HE IS ON" {
    const dt: f32 = 1.0 / 60.0;
    const near = mathx.ground(0, 3.0);
    var dry = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    dry.wade = .{ .here = 1.0, .quarry = 0 };
    var t: f32 = 0;
    while (t < 2.0) : (t += dt) _ = dry.update(dt, near, 200.0, .{});
    try std.testing.expect(dry.hidden());
    try std.testing.expectEqual(State.sunk, dry.state);

    var wet = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    wet.wade = .{ .here = 1.0, .quarry = WADE_MIN + 0.05 };
    wet.restT = 0;
    var broke = false;
    t = 0;
    while (t < 2.0) : (t += dt) {
        _ = wet.update(dt, near, 200.0, .{});
        if (wet.broke) broke = true;
    }
    try std.testing.expect(broke);
    try std.testing.expect(!wet.hidden());
}

test "THE SURGE IS A REAL TELL, and the wake leads the body out of the water" {
    try std.testing.expect(SURGE_DUR >= foe.TELL_MIN);
    try std.testing.expect(SURGE_DUR > LASH_DUR * 3.0);
    try std.testing.expect(WAKE_RATE > 0);

    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.stageGather(0.0);
    try std.testing.expect(l.up < 0.05);
    l.stageGather(0.5);
    const half = l.up;
    try std.testing.expect(half > 0.1 and half < 0.95);
    l.stageGather(1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), l.up, 1e-5);
}

test "THE CROWN THE CAMERA FRAMES IS THE CROWN THE RIG ACTUALLY HAS" {
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.stageGather(1.0);
    var crown: f32 = 0;
    // The BODY's bones. A coiled tongue is inside the head and `Model.draw` skips it, so what it measures is not
    // what the camera has to hold — and the test beside this one pins that it stays inside the skull's own reach.
    for (0..TONGUE) |i| crown = @max(crown, foe.markOn(l.xf[i], mathx.zero3).y - l.pos.y);
    const said = l.topWorld().y - l.pos.y;
    std.debug.print("\n  fen lurker: posed crown {d:.2} m, topWorld says {d:.2} m\n", .{ crown, said });
    try std.testing.expect(said >= crown);
    try std.testing.expect(said <= crown * 1.35);
    var sunk = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(sunk.hidden());
    try std.testing.expectApproxEqAbs(said, sunk.topWorld().y - sunk.pos.y, 1e-5);
}

test "THE HEAD RIDES ABOVE HIM AND THE LASH BRINGS IT DOWN INTO HIS COLUMN" {
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.stageGather(1.0);
    const reared = l.jawPoint().y - l.pos.y;
    l.stageLash(1.0);
    const struck = l.jawPoint().y - l.pos.y;
    std.debug.print("\n  fen lurker: jaws {d:.2} m reared, {d:.2} m at the strike (hero {d:.2}..{d:.2}), chain bends {d:.0} deg\n", .{
        reared, struck, foe.HERO_LOW, foe.HERO_HIGH, TOTAL_BEND,
    });
    try std.testing.expect(reared > foe.HERO_HIGH);
    try std.testing.expect(struck - HEAD_R > foe.HERO_LOW);
    try std.testing.expect(struck + HEAD_R < foe.HERO_HIGH);
    try std.testing.expect(reared - struck > H * 0.5);
}

test "ONE LASH IS ONE BLOW, and one that went past him does not take him in the back" {
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.state = .lash;
    l.t = 0;
    l.tryLash(mathx.ground(0, -1.5));
    try std.testing.expect(l.heroHit == null);
    l.tryLash(mathx.ground(0, LASH_R + foe.HERO_REACH + 0.8));
    try std.testing.expect(l.heroHit == null);
    l.tryLash(mathx.ground(0, 1.4));
    try std.testing.expect(l.heroHit != null);
    l.heroHit = null;
    l.tryLash(mathx.ground(0, 1.4));
    try std.testing.expect(l.heroHit == null);
}

test "IT HURTS HIM BY RETURNING A BLOW, and one surge lands exactly one" {
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.wade = .{ .here = 1.0, .quarry = 1.0 };
    l.restT = 0;
    const hero = mathx.ground(0, 1.4);
    const dt: f32 = 1.0 / 60.0;
    var landed: usize = 0;
    var t: f32 = 0;
    while (t < 3.0) : (t += dt) {
        switch (l.update(dt, hero, 200.0, .{})) {
            .none => {},
            .struck => |s| {
                landed += 1;
                try std.testing.expectApproxEqAbs(LASH_HIT.dmg, s.hit.dmg, 1e-4);
                try std.testing.expectApproxEqAbs(@as(f32, 0), s.pull, 1e-6);
            },
        }
        if (landed > 0 and l.state != .lash) break;
    }
    try std.testing.expectEqual(@as(usize, 1), landed);
}

test "HE LEAVES THE WATER AND IT GOES DOWN — and stepping back in brings it straight back up" {
    const dt: f32 = 1.0 / 60.0;
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.wade = .{ .here = 1.0, .quarry = 1.0 };
    l.restT = 0;
    const wet = mathx.ground(0, 3.0);
    var t: f32 = 0;
    while (t < 2.0) : (t += dt) _ = l.update(dt, wet, 200.0, .{});
    try std.testing.expect(!l.hidden());

    l.wade.quarry = 0;
    t = 0;
    while (t < 4.0) : (t += dt) _ = l.update(dt, wet, 200.0, .{});
    try std.testing.expect(l.hidden());
    try std.testing.expectEqual(State.sunk, l.state);

    l.wade.quarry = 1.0;
    l.restT = 0;
    t = 0;
    while (t < 2.0) : (t += dt) _ = l.update(dt, wet, 200.0, .{});
    try std.testing.expect(!l.hidden());
}

test "A STAGGER DOES NOT PUT IT UNDER — the flinch is the punish window, not its way out" {
    const dt: f32 = 1.0 / 60.0;
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.wade = .{ .here = 1.0, .quarry = 1.0 };
    l.stageLash(0.5);
    l.stagger(true);
    var t: f32 = 0;
    while (t < combat.FOE_HEAVY_STUN_DUR * 0.8) : (t += dt) _ = l.update(dt, mathx.ground(0, 2.0), 200.0, .{});
    try std.testing.expect(!l.hidden());
    try std.testing.expectEqual(State.hurt, l.state);
}

test "WET FLESH IN STANDING WATER: lightning is the answer to it and fire is not" {
    var struck = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    var burnt = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    const levin = combat.Hit{ .elem = combat.elems(.{ .lightning = 20 }) };
    const fire = combat.Hit{ .elem = combat.elems(.{ .fire = 20 }) };
    try std.testing.expect(struck.vit.damageFrom(levin) > 20.0);
    try std.testing.expect(burnt.vit.damageFrom(fire) < 20.0);
    try std.testing.expect(struck.vit.damageFrom(levin) > burnt.vit.damageFrom(fire) * 2.0);
}

test "A LIGHT POKE DOES NOT FLINCH IT AND A HEAVY DOES — poise against the hero's own two swings" {
    var light = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectEqual(combat.HitResult.none, light.vit.hit(heromod.ATK_LIGHT_HIT));
    var heavy = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectEqual(combat.HitResult.light, heavy.vit.hit(heromod.ATK_HEAVY_HIT));
}

test "A LURKER WITH NO POOL STANDS UP AND FIGHTS rather than sinking into a field" {
    const dt: f32 = 1.0 / 60.0;
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.wade = .{ .here = 0, .quarry = 0 };
    try std.testing.expect(!l.pooled());
    var t: f32 = 0;
    while (t < 2.0) : (t += dt) _ = l.update(dt, mathx.ground(0, 3.0), 200.0, .{});
    try std.testing.expect(!l.hidden());
}

test "A LURKER WITH NO POOL IS STILL THERE WHEN NOBODY IS LOOKING" {
    const dt: f32 = 1.0 / 60.0;
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.wade = .{ .here = 0, .quarry = 0 };
    const far = mathx.ground(0, AGGRO_R + 6.0);
    var t: f32 = 0;
    while (t < 6.0) : (t += dt) _ = l.update(dt, far, 200.0, .{});
    try std.testing.expectEqual(State.sunk, l.state);
    try std.testing.expect(!l.hidden() and !l.phased());
}

test "A CHAINED SECOND STROKE DOES NOT DROP THE BODY BACK IN THE WATER" {
    const dt: f32 = 1.0 / 60.0;
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.wade = .{ .here = 1.0, .quarry = 1.0 };
    l.restT = 0;
    const hero = mathx.ground(0, 1.4);
    var lowest: f32 = 1.0;
    var reachedTop = false;
    var t: f32 = 0;
    while (t < 6.0) : (t += dt) {
        _ = l.update(dt, hero, 200.0, .{});
        if (l.up >= 0.999) reachedTop = true;
        if (reachedTop) lowest = @min(lowest, l.up);
    }
    std.debug.print("\n  fen lurker: chained strokes hold the body at {d:.3} of full surge\n", .{lowest});
    try std.testing.expect(reachedTop);
    try std.testing.expect(lowest > 0.99);
}

test "THE TONGUE'S REACH IS MEASURED OFF THE POSED RIG, and the shaft is laid through his own height" {
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.stageSpit(1.0);
    const seg = l.tongueSeg();
    const reach = mathx.distXZ(l.pos, seg[1]);
    std.debug.print(
        "\n  fen lurker tongue: {d:.2} m of shaft over a {d:.2} m stature, reaching {d:.2} m out (band says {d:.2}); jaw {d:.2} m down to {d:.2} m at the pad\n",
        .{ TONGUE_LEN, H, reach, TONGUE_R, seg[0].y - l.pos.y, seg[1].y - l.pos.y },
    );
    // THE BAND MAY NEVER PROMISE MORE THAN THE KIT REACHES, so the constant is authored under what it measures.
    try std.testing.expect(reach >= TONGUE_R);
    try std.testing.expect(reach <= TONGUE_R * 1.14);
    try std.testing.expect(TONGUE_LEN > H * 1.5);

    // EVERY PART OF THE RUN THE BAND CAN BILL AT is inside his capsule. Fired level off a 2.7 m jaw the first two
    // metres of it passed clean over a 1.71 m crown, which is the whole reason the skull pitches at all.
    for (0..25) |i| {
        const at = mathx.lerpV(seg[0], seg[1], @as(f32, @floatFromInt(i)) / 24.0);
        if (mathx.distXZ(l.pos, at) < lashBand(1.0)) continue;
        const y = at.y - l.pos.y;
        if (y > foe.HERO_LOW and y < foe.HERO_HIGH) continue;
        std.debug.print("  the shaft is at {d:.2} m {d:.2} m out — outside {d:.2}..{d:.2}\n", .{ y, mathx.distXZ(l.pos, at), foe.HERO_LOW, foe.HERO_HIGH });
        return error.TestUnexpectedResult;
    }

    // Coiled, it is INSIDE the mouth and not drawn: nothing of it stands out past the skull's own reach, and nothing
    // of it stands over the crown the shot camera frames the body off.
    l.stageGape(1.0);
    try std.testing.expect(l.ext <= TONGUE_SHOW);
    const coiled = l.tipPoint();
    std.debug.print("  ...and coiled the pad sits {d:.2} m out at {d:.2} m up, inside a {d:.2} m skull under a {d:.2} m crown\n", .{
        mathx.distXZ(l.pos, coiled), coiled.y - l.pos.y, lashBand(1.0), l.topWorld().y - l.pos.y,
    });
    try std.testing.expect(mathx.distXZ(l.pos, coiled) < lashBand(1.0));
    try std.testing.expect(coiled.y - l.pos.y < l.topWorld().y - l.pos.y);
}

test "THE TONGUE IS BILLED WHERE IT CROSSES HIM, AND AT EVERY STAND ACROSS ITS OWN BAND" {
    const dt: f32 = 1.0 / 60.0;
    var stands: usize = 0;
    var nearest: f32 = 1e9;
    var furthest: f32 = 0;
    var d = lashBand(1.0) + 0.05;
    while (d <= tongueBand(1.0)) : (d += 0.30) {
        var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
        l.wade = .{ .here = 1.0, .quarry = 1.0 };
        l.restT = 0;
        const hero = mathx.ground(0, d);
        var hit: ?combat.Hit = null;
        var pull: f32 = 0;
        var t: f32 = 0;
        while (t < GAPE_DUR + SPIT_DUR + REEL_DUR + 0.5) : (t += dt) {
            switch (l.update(dt, hero, 200.0, .{})) {
                .none => {},
                .struck => |s| {
                    hit = s.hit;
                    pull = s.pull;
                },
            }
        }
        if (hit == null) {
            std.debug.print("\n  the tongue billed NOTHING at {d:.2} m, inside a band of {d:.2}\n", .{ d, tongueBand(1.0) });
            return error.TestUnexpectedResult;
        }
        try std.testing.expectApproxEqAbs(TONGUE_HIT.dmg, hit.?.dmg, 1e-4);
        try std.testing.expect(pull > 0);
        nearest = @min(nearest, d);
        furthest = @max(furthest, d);
        stands += 1;
    }
    std.debug.print("  ...and it bills at all {d} stands from {d:.2} to {d:.2} m, hauling him {d:.2} m in\n", .{ stands, nearest, furthest, TONGUE_PULL });
    try std.testing.expect(stands >= 6);
}

test "THE TELL IS A LOAD, AND IT IS RELEASED BEFORE THE SHAFT GOES" {
    const dt: f32 = 1.0 / 60.0;
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.wade = .{ .here = 1.0, .quarry = 1.0 };
    l.restT = 0;
    const hero = mathx.ground(0, tongueBand(1.0) * 0.8);
    var reared: f32 = 0;
    var atSpit: f32 = 1e9;
    var t: f32 = 0;
    while (t < GAPE_DUR + SPIT_DUR) : (t += dt) {
        const was = l.state;
        _ = l.update(dt, hero, 200.0, .{});
        if (l.state == .gape) reared = @min(reared, l.swing);
        if (was == .gape and l.state == .spit) atSpit = @abs(l.swing);
    }
    std.debug.print("\n  fen lurker tell: the coil loads to {d:.2} of the lash's own channel and is back to {d:.2} when the tongue goes\n", .{ reared, atSpit });
    // A load worth reading...
    try std.testing.expect(reared <= -GAPE_REAR * 0.9);
    // ...and spent by the time it matters, or the rear-back's head pitch cancels `GAPE_PITCH` and the shaft fires level.
    try std.testing.expect(atSpit < 0.1);
}

test "THE HAUL IS A SETUP, NOT A NUISANCE — a hit at the far edge lands him inside the skull's own band" {
    try std.testing.expect(TONGUE_PULL > 0);
    try std.testing.expect(TONGUE_R - TONGUE_PULL <= LASH_R);
    // The band's own form of the same rule: hauled off the FAR edge he lands inside the skull's reach, so the drag
    // is what hands him to the lash rather than a nuisance that moves him and nothing else.
    try std.testing.expect(tongueBand(1.0) - TONGUE_PULL <= lashBand(1.0));
    // THE LONGER REACH IS THE LIGHTER BLOW, and it is the one that moves him: the rooted's hook keeps the same shape.
    try std.testing.expect(TONGUE_HIT.raw() < LASH_HIT.raw());
    // And a whiff buys the longer window, because it was the longer reach.
    try std.testing.expect(TONGUE_RECOVER > RECOVER_DUR);
    try std.testing.expect(GAPE_DUR > SURGE_DUR and GAPE_DUR > foe.TELL_MIN);
    try std.testing.expect(SPIT_DUR < LASH_DUR * 1.5);
    std.debug.print(
        "\n  fen lurker: skull {d:.2} m band / {d:.0} dmg / {d:.2} s tell, tongue {d:.2} m / {d:.0} dmg / {d:.2} s tell, haul {d:.2} m, {d:.1} s off the clock\n",
        .{ lashBand(1.0), LASH_HIT.dmg, SURGE_DUR, tongueBand(1.0), TONGUE_HIT.dmg, GAPE_DUR, TONGUE_PULL, TONGUE_CD },
    );
}

test "CLOSE IS THE SKULL AND FAR IS THE TONGUE, and off its clock at range it LOOMS rather than whiffing" {
    for ([_]f32{ wf.FOE_SCALE_LO, 1.0, wf.FOE_SCALE_HI }) |s| {
        try std.testing.expect(lashBand(s) < tongueBand(s));
        try std.testing.expectEqual(Move.lash, classify(lashBand(s) * 0.5, 0, s, true).?);
        try std.testing.expectEqual(Move.lash, classify(lashBand(s) - 0.01, 0, s, true).?);
        try std.testing.expectEqual(Move.tongue, classify(lashBand(s) + 0.01, 0, s, true).?);
        try std.testing.expectEqual(Move.tongue, classify(tongueBand(s) - 0.01, 0, s, true).?);
        // A close stand is the skull whatever the tongue's clock says, and off that clock the far band is nothing.
        try std.testing.expectEqual(Move.lash, classify(lashBand(s) * 0.5, 0, s, false).?);
        try std.testing.expect(classify(lashBand(s) + 0.01, 0, s, false) == null);
        try std.testing.expect(classify(tongueBand(s) + 0.01, 0, s, true) == null);
    }
    // It may not reach past the ring it senses him in: a band over `AGGRO_R` is a blow thrown at a man the creature
    // has not noticed, and one under half of it leaves the free water the tongue exists to close.
    try std.testing.expect(tongueBand(1.0) <= AGGRO_R);
    try std.testing.expect(tongueBand(1.0) > AGGRO_R * 0.5);
}

test "A BEARING THE WIND CANNOT COME ROUND TO IS REFUSED AT THE CHOOSE, and what it falls through to TURNS" {
    // The gate is what each wind buys, so it cannot go stale against a retune of either.
    try std.testing.expect(windSweep(.lash) > windSweep(.tongue));
    try std.testing.expect(windSweep(.tongue) > 90.0 and windSweep(.tongue) < 180.0);
    const far = tongueBand(1.0) - 0.2;
    try std.testing.expectEqual(Move.tongue, classify(far, windSweep(.tongue) - 1.0, 1.0, true).?);
    try std.testing.expect(classify(far, windSweep(.tongue) + 1.0, 1.0, true) == null);
    const near = lashBand(1.0) - 0.2;
    try std.testing.expectEqual(Move.lash, classify(near, windSweep(.lash) - 1.0, 1.0, true).?);
    try std.testing.expect(classify(near, windSweep(.lash) + 1.0, 1.0, true) == null);

    // AND IT IS THROWN AT EVERY BEARING IT DOES ACCEPT: a gate solved too wide is a shaft fired past him.
    const dt: f32 = 1.0 / 60.0;
    var worst: f32 = 0;
    var thrown: usize = 0;
    var deg: f32 = 0;
    while (deg <= windSweep(.tongue) - 2.0) : (deg += 15.0) {
        var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
        l.wade = .{ .here = 1.0, .quarry = 1.0 };
        l.restT = 0;
        const a = mathx.radians(deg);
        const hero = mathx.ground(mathx.sinf(a) * far, mathx.cosf(a) * far);
        var hit = false;
        var t: f32 = 0;
        while (t < GAPE_DUR + SPIT_DUR + REEL_DUR + 0.4) : (t += dt) {
            switch (l.update(dt, hero, 200.0, .{})) {
                .none => {},
                .struck => hit = true,
            }
        }
        if (!hit) {
            std.debug.print("\n  the tongue was ACCEPTED at {d:.0} deg off and billed nothing\n", .{deg});
            return error.TestUnexpectedResult;
        }
        worst = @max(worst, deg);
        thrown += 1;
    }
    std.debug.print("\n  fen lurker gate: the tongue is refused past {d:.0} deg off and lands at all {d} bearings inside it (worst {d:.0})\n", .{ windSweep(.tongue), thrown, worst });
    try std.testing.expect(thrown >= 7);
}

test "IN THE WATER AND OUT OF EVERY BAND IT COMES UP AND WATCHES — a gate with nothing behind it is a hole" {
    const dt: f32 = 1.0 / 60.0;
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.wade = .{ .here = 1.0, .quarry = 1.0 };
    l.restT = 0;
    // Inside its ring, outside the tongue.
    const far = mathx.ground(0, (tongueBand(1.0) + AGGRO_R) * 0.5);
    var t: f32 = 0;
    while (t < 4.0) : (t += dt) _ = l.update(dt, far, 200.0, .{});
    try std.testing.expectEqual(State.loom, l.state);
    try std.testing.expect(!l.hidden());
    try std.testing.expect(l.ext <= TONGUE_SHOW);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), l.up, 1e-3);
    // It TURNS while it looms — that is what makes the gate a stance and not a stall.
    var turned = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    turned.wade = .{ .here = 1.0, .quarry = 1.0 };
    turned.restT = 0;
    turned.facing = std.math.pi;
    const side = mathx.ground((tongueBand(1.0) + AGGRO_R) * 0.5, 0);
    t = 0;
    while (t < 4.0) : (t += dt) _ = turned.update(dt, side, 200.0, .{});
    try std.testing.expect(@abs(foe.bearingDeg(turned.pos, turned.facing, side)) < 8.0);

    // And he walks out of the water, and it goes back down.
    l.wade.quarry = 0;
    t = 0;
    while (t < 4.0) : (t += dt) _ = l.update(dt, far, 200.0, .{});
    try std.testing.expect(l.hidden());
}

test "ONE COMMITMENT IS ONE BLOW — the tongue does not take him again on its way home, and a flinch swallows it" {
    const dt: f32 = 1.0 / 60.0;
    const at = lashBand(1.0) + 0.6;
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.wade = .{ .here = 1.0, .quarry = 1.0 };
    l.restT = 0;
    const hero = mathx.ground(0, at);
    var landed: usize = 0;
    var t: f32 = 0;
    while (t < GAPE_DUR + SPIT_DUR + REEL_DUR + 0.4) : (t += dt) {
        switch (l.update(dt, hero, 200.0, .{})) {
            .none => {},
            .struck => landed += 1,
        }
    }
    try std.testing.expectEqual(@as(usize, 1), landed);

    // A FLINCH SWALLOWS IT. Left out, the shaft hung in the air through the whole stagger and went on billing off a
    // body that had stopped throwing it.
    var hurt = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    hurt.wade = .{ .here = 1.0, .quarry = 1.0 };
    hurt.stageSpit(1.0);
    try std.testing.expect(mathx.distXZ(hurt.pos, hurt.tipPoint()) > lashBand(1.0));
    hurt.stagger(true);
    t = 0;
    while (t < combat.foeStunDur(true) * 0.9) : (t += dt) _ = hurt.update(dt, hero, 200.0, .{});
    try std.testing.expectEqual(State.hurt, hurt.state);
    try std.testing.expect(hurt.ext <= TONGUE_SHOW);
    try std.testing.expect(!hurt.hidden());
}

test "THE BANDS DO NOT OVERLAP, SO NEITHER MOVE IS EVER WHIFFED — and out of the skull's reach it looms between tongues" {
    const dt: f32 = 1.0 / 60.0;
    const stands = [_]f32{ lashBand(1.0) * 0.5, lashBand(1.0) + 0.4, tongueBand(1.0) - 0.3 };
    for (stands) |at| {
        var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
        l.wade = .{ .here = 1.0, .quarry = 1.0 };
        l.restT = 0;
        const hero = mathx.ground(0, at);
        var tongues: usize = 0;
        var skulls: usize = 0;
        var loomed: usize = 0;
        var was: State = l.state;
        var t: f32 = 0;
        while (t < TONGUE_CD * 3.0) : (t += dt) {
            _ = l.update(dt, hero, 200.0, .{});
            if (l.state == was) continue;
            switch (l.state) {
                .gape => tongues += 1,
                .surge => skulls += 1,
                .loom => loomed += 1,
                else => {},
            }
            was = l.state;
        }
        std.debug.print("  fen lurker over {d:.0} s at {d:.2} m: {d} tongues, {d} skulls, {d} looms\n", .{ TONGUE_CD * 3.0, at, tongues, skulls, loomed });
        // ONE BAND, ONE MOVE: inside the skull's reach it never spends the tongue, and outside it never throws a
        // skull that cannot arrive. What fills the tongue's cooldown is the LOOM.
        if (at <= lashBand(1.0)) {
            try std.testing.expect(skulls > 0 and tongues == 0);
        } else {
            try std.testing.expect(tongues > 0 and skulls == 0);
            try std.testing.expect(loomed >= tongues - 1);
        }
    }
    // Every tongue pays its whole tell, and its clock outlasts the whole stroke — so the loom is real time, not a frame.
    try std.testing.expect(TONGUE_CD > GAPE_DUR + SPIT_DUR + REEL_DUR + TONGUE_RECOVER);
}

test "THE NECK IS A WHIP, NOT A HINGE — the tip carries more of the stroke than the root does" {
    try std.testing.expect(SEG_BEND_HI > SEG_BEND_LO * 2.0);
    try std.testing.expect(HEAD_BEND > SEG_BEND_HI);
    try std.testing.expect(LAG_2 < LAG_1);
}
