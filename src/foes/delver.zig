const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const sfx = @import("../core/audio.zig");
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

const HIDE = rgba(8, 8, 11, 255);
const HIDE_LO = rgba(12, 11, 15, 255);
const PLATE = rgba(17, 16, 21, 255);
const CLAW = rgba(44, 40, 32, 255);
const CLAW_LT = rgba(96, 88, 70, 255);
const SNOUT = rgba(20, 17, 14, 255);
const EYE = rgba(70, 66, 54, 255);
const SOIL = rgba(24, 19, 14, 255);
const SOIL_DK = rgba(15, 12, 9, 255);
const CLOD = rgba(148, 120, 84, 220);
const CLOD_DK = rgba(106, 84, 58, 210);

pub const H: f32 = 1.55;

pub const AGGRO_R: f32 = 14.0;
const HOME_R: f32 = 2.5;

const BODY_R: f32 = 0.62;
const HURT_R: f32 = 0.95;
const CENTER_F: f32 = 0.42;
const BODY_HALF: f32 = 0.80;
const TOP_F: f32 = 0.66;

const HP_MAX: f32 = 118.0;
const POISE_MAX: f32 = 26.0;
const STANCE_MAX: f32 = 58.0;
const RESISTS = combat.resists(.{ .fire = 20, .cold = -30, .lightning = -40 });
pub const SOULS: u32 = 155;

pub const CLAW_HIT = combat.Hit{ .dmg = 15, .poise = 20, .stance = 6 };
pub const BURST_HIT = combat.Hit{ .dmg = 28, .poise = 42, .stance = 18 };
pub const BURST_R: f32 = 1.9;

const WALK_SPEED: f32 = 2.2;
const CHASE_SPEED: f32 = 3.9;
const TURN_RATE: f32 = 4.2;
/// WHAT THE POSED CLAW ACTUALLY REACHES off the creature's own axis. **MEASURED, NOT ARGUED** — a test walks
/// the stroke frame by frame and brackets this from both sides, which is what caught the first pass declaring
/// 2.9 m off a limb that arrived at 1.19.
const CLAW_REACH: f32 = 1.75;
const CLAW_SWEEP_R: f32 = 0.34;
/// **THE DECISION IS TAKEN AT THE RANGE THE BLOW LANDS AT**, never at a number beside it, or it spends half a
/// second on a guaranteed miss (the ogre's swipe-inner lesson).
///
/// **AND WHAT THAT RANGE IS, IS WHERE THE ARC CROSSES HIM — NOT HOW FAR THE TIP GETS** (owner: the moles
/// cannot hit me with their regular attacks). `CLAW_REACH + CLAW_SWEEP_R` is the tip's RADIAL reach, which it
/// achieves out to the SIDE at the end of the sweep; a man standing in front is only ever struck where the
/// arc passes through the body's own forward line, and that is nearer. At 2.09 the outer fifth of its own
/// trigger band was a committed stroke that could not land by construction, on top of the missing lateral
/// channel (`SWING_YAW`) that meant none of the band could. MEASURED by the band test below.
const CLAW_BAND: f32 = 1.65;
const CLAW_KEEP: f32 = CLAW_BAND - 0.5;
pub const CLAW_WIND: f32 = 0.48;
const CLAW_STRIKE: f32 = 0.20;
/// **AND IT IS VICIOUS ON ITS FEET, NOT ONLY UNDER THEM** (owner: more vicious even when not underground).
/// The surface kit was a courtesy — one stroke every 1.9 s off a body that walked at 2.2 m/s, so a delver
/// caught above ground was a punching bag between dives and the whole creature lived in the burrow. The
/// recovery is shorter, the cooldown is most of a second off, and it CLOSES rather than ambling: the thing
/// that goes under the world is not supposed to be safe to stand next to when it comes out of it.
const CLAW_RECOVER: f32 = 0.40;
const CLAW_CD: f32 = 1.05;

pub const DIVE_WIND: f32 = 0.62;
const DIVE_DUR: f32 = 0.42;
const UNDER_MIN: f32 = 2.6;
const UNDER_MAX: f32 = 7.0;
const UNDER_SPEED: f32 = 4.8;
const UNDER_TURN: f32 = 2.6;
/// HOW FAR UNDER THE GROUND ITS BODY RIDES. See the comptime assert below: this number is what makes it
/// unhittable while it is down, and nothing else does.
pub const UNDER_DEPTH: f32 = 2.6;
const SURGE_LOCK_R: f32 = 1.0;
const MOUND_TRAVEL_R: f32 = 1.05;
const MOUND_TRAVEL_H: f32 = 0.28;

/// **THE TELL IS THROWN EARTH, NOT A SWELLING DOME** (owner: instead of distending the bump, steadily add
/// particles until he jumps out). The dome grew to `BURST_R * 0.86` and stood there — a mound inflating is a
/// slow, soft read at exactly the moment the read has to be urgent, and a shape held for over a second stops
/// being motion at all. What replaces it is a spray that BUILDS: a few clods at the commit, a fountain by the
/// end, so the ground comes apart harder every frame and the eye is pulled by CHANGE rather than by size.
/// The disc the blow lands on is still exactly `BURST_R` — the picture has simply stopped lying about it by
/// being smaller than the thing it announces.
///
/// The mound itself HOLDS at its travelling size right to the burst, which is what keeps the spot honest: the
/// ridge stopped there, and that is where it comes out.
const MOUND_SWELL_R: f32 = MOUND_TRAVEL_R;
const MOUND_SWELL_H: f32 = MOUND_TRAVEL_H;
const SURGE_SPRAY_0: f32 = 14.0;
const SURGE_SPRAY_1: f32 = 190.0;
const SURGE_SPRAY_CURVE: f32 = 2.4;
const SURGE_SPRAY_LIFT: f32 = 2.6;
/// THE TELL, AND IT IS THE LONGEST THING IT DOES. The mound STOPS, the earth domes up over the spot and
/// throws dirt; the blow lands where it stopped. Bracketed from below by its own dive wind, because the one
/// move that arrives from a direction the camera cannot be turned toward may not be the one you get least
/// warning of (the Bone Knight's fall, one creature along) — and bracketed again by what it costs to get out
/// of the ring, which is the assert below. It is on TOP of a mound that has been visible the whole way in:
/// this is the final commit, not the whole warning.
pub const SURGE_DUR: f32 = 1.15;
pub const BURST_RISE: f32 = 0.28;
const BURST_RECOVER: f32 = 0.95;
const DIVE_CD: f32 = 6.5;
/// **THE CHURN IS A RETRIGGER, NOT A LOOP** (the leechfly's whine idiom — raylib cannot loop a synthesized
/// take), and the voice is cut a hair longer than this so consecutive ones overlap. It is what a player
/// looking the wrong way has instead of the mound, so it is the one thing about this creature that reaches
/// further than it can see.
pub const CHURN_EVERY: f32 = 0.72;
/// The stride the limb phase is measured in — one number, read by the surface walk and by the swim under it.
const STRIDE: f32 = 0.92;

comptime {
    // **SUBMERGED IT CANNOT BE STRUCK, AND THAT IS GEOMETRY RATHER THAN A GUARD IN `tryHit`.** Its hurt
    // sphere is measured off `pos.y` like everything else's (`foe.bodyPoint`, with the depth as a NEGATIVE
    // lift), so at `UNDER_DEPTH` the top of it sits this far under the ground he is standing on — further
    // than any blade of his reaches below his own boots, and the swept test then refuses it on its own.
    // A creature that needed a special case here would need one at every future site that swings anything.
    //
    // **AND IT HOLDS AT EVERY SCALE THE MAP CAN POST, which is why this may be written in bare constants.**
    // `depth` is in SCALE-1 METRES and `ride()` is what multiplies it (`-depth * scale`), so every term below
    // is the same multiple of `scale` and the whole inequality is scale-invariant. Read the other way — depth
    // as world metres — it looks like a check that only pins scale 1, and "fixing" that by scaling `depth`
    // at its writers double-scales the burrow and surfaces a small delver. The test below is the pin.
    std.debug.assert(UNDER_DEPTH - CENTER_F * H - HURT_R > 0.8);
    std.debug.assert(SURGE_DUR > DIVE_WIND and DIVE_WIND >= foe.TELL_MIN and CLAW_WIND >= foe.TELL_MIN);
    // A COMMITTED SPOT HE CAN GET OFF, and the price of standing still. He starts at the CENTRE — it came
    // up under him — so what he has to clear is the whole radius plus his own footprint. A RUN does it with
    // room to spare and a ROLL does it outright; a WALK covers 1.96 m of the 2.26 and is deliberately not
    // enough, or the move is a tax on being anywhere rather than a thing you answer. The hero's own figures
    // are written out here rather than imported for `foe.HERO_*`'s reason: this file sits below `hero.zig`.
    std.debug.assert(SURGE_DUR * 3.4 > BURST_R + foe.HERO_R);
    std.debug.assert(SURGE_DUR > 0.70 + 0.30);
}

pub const PLOUGH_HIT = combat.Hit{ .dmg = 20, .poise = 30, .stance = 12 };
pub const PLOUGH_R: f32 = 1.15;
pub const PLOUGH_WIND: f32 = 0.55;
const PLOUGH_DUR: f32 = 0.85;
const PLOUGH_SPEED: f32 = 9.2;
const PLOUGH_R_MIN: f32 = 3.0;
const PLOUGH_R_MAX: f32 = PLOUGH_SPEED * PLOUGH_DUR * 0.8;
const PLOUGH_ARC: f32 = 38.0;
const MOUND_PLOUGH_R: f32 = MOUND_TRAVEL_R * 1.1;
const MOUND_PLOUGH_H: f32 = MOUND_TRAVEL_H * 1.45;
const MOUND_PLOUGH_LONG: f32 = 2.8;

pub const RAKE_HIT = combat.Hit{ .dmg = 12, .poise = 16, .stance = 5 };
/// **AND IT IS STILL LONG ENOUGH TO BE CAUGHT ON, WHICH IS WHAT SIZES IT FROM BELOW.** It carries a parry
/// window like the opener does, and `foe.PARRY_LEAD` brackets every wind in the game from above (the toad's
/// `LUNGE_COIL` and the brood's `BITE_WINDUP` were both pushed up for exactly this). At 0.33 the game's one
/// difficulty dial covered 55% of this tell against under half of the claw's beside it — the same move twice
/// at two difficulties, and nothing pinned it.
pub const RAKE_WIND: f32 = 0.40;
const RAKE_STRIKE: f32 = 0.18;
const RAKE_CHANCE: f32 = 0.55;

comptime {
    std.debug.assert(PLOUGH_WIND >= foe.TELL_MIN and RAKE_WIND >= foe.TELL_MIN);
    std.debug.assert(RAKE_WIND < CLAW_WIND);
    std.debug.assert(foe.PARRY_LEAD < RAKE_WIND * 0.5 and foe.PARRY_LEAD < CLAW_WIND * 0.5);
    std.debug.assert(PLOUGH_R_MIN > SURGE_LOCK_R and PLOUGH_R_MAX > PLOUGH_R_MIN);
    std.debug.assert(PLOUGH_HIT.stance < BURST_HIT.stance and RAKE_HIT.stance < BURST_HIT.stance);
    std.debug.assert(RAKE_HIT.dmg < CLAW_HIT.dmg);
}

const DEATH_DUR: f32 = 1.15;
const DISS_DUR: f32 = 1.05;
const SHOVE_DECAY: f32 = 7.0;
const DISSOLVE = foe.Dissolve{ .rate = 58.0, .spread = 0.9, .rise = 0.75, .flake = CLOD };

/// Sized by ARITHMETIC over the worst frame (the ring law), and the worst frame is the PLOUGH'S LAST one, not
/// the burst's: the furrow can land its blow on the same frame the run ends, so the 12-clod hit burst and the
/// 40 of `burstDirt` go in together — on top of what the run itself left resident, which is `emitWake` at 22/s
/// and `emitSpray` at 24/s against lives of 0.3-0.7 s, about 22. That is 74 against the 72 this used to be,
/// and a ring that overwrites its oldest does it SILENTLY. 96 clears it with room for the shove's dust.
const PARTS = 96;

const N = 10;
const BODY = 0;
const HEAD = 1;
const ARML = 2;
const ARMR = 3;
const CLAWL = 4;
const CLAWR = 5;
const HINDL = 6;
const HINDR = 7;
const TAIL = 8;
const MOUND = 9;

const REST = [N]rl.Vector3{
    v3(0, 0, 0),
    v3(0, 0.30 * H, 0.66),
    v3(0.34, 0.26 * H, 0.34),
    v3(-0.34, 0.26 * H, 0.34),
    v3(0.12, -0.14, 0.44),
    v3(-0.12, -0.14, 0.44),
    v3(0.30, 0.21 * H, -0.48),
    v3(-0.30, 0.21 * H, -0.48),
    v3(0, 0.26 * H, -0.82),
    v3(0, 0, 0),
};

/// The far end of the middle digging claw, in the claw bone's own frame — what the stroke actually swings,
/// and what `parryable` hands over as its reach. MEASURED off the mesh, never argued (the ogre's club law).
const CLAW_TIP = v3(0, -0.16, 0.78);

/// **HOW FAR ACROSS ITS OWN FRONT THE STROKE CARRIES, in degrees at the shoulder** — the lateral half of
/// `swing`, and the half that was missing. The shoulder sits 0.34 m off the axis and the claw rides about
/// 1.2 m out in front of it, so this is solved against the crossing rather than picked: the tip has to pass
/// THROUGH the body's own forward line inside the strike window, or a man standing where the creature is
/// looking is never crossed by anything. MEASURED by the reach test below, never argued.
const SWING_YAW: f32 = 46.0;

const State = enum { idle, walk, claw, rake, recover, dive, under, surge, plough, burst, heave, stunlight, stunheavy, dead };

const Choice = enum { rest, wait, walk, claw, dive };
fn classify(dist: f32, clawReady: bool, diveReady: bool, rooted: bool) Choice {
    if (dist > AGGRO_R) return .rest;
    if (diveReady and !rooted) return .dive;
    if (dist <= CLAW_BAND and clawReady) return .claw;
    if (dist > CLAW_KEEP) return .walk;
    return .wait;
}

pub const Model = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "delver");
        return .{ .mesh = buildMeshes(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, d: *const Delver) void {
        const buried = d.deep();
        for (0..N) |i| {
            if (i == MOUND) {
                if (!d.mounded()) continue;
            } else if (buried) continue;
            rl.drawMesh(self.mesh[i], self.mat, d.xf[i]);
        }
    }
};

pub const Delver = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    parry: foe.Parry = .{},
    /// The boards caught the claw this frame — a ONE-FRAME flag, `justDied`'s exactly.
    parried: bool = false,
    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    idleWait: f32 = 0.3,
    clawCd: f32 = 0,
    diveCd: f32 = 0,
    heroLatch: bool = false,
    raked: bool = false,
    homing: bool = false,
    /// It went under this frame, and it broke the surface this frame — one-frame edges the GROUP reads, which
    /// is what lets the game put a shake and a low rumble under a tell arriving from off screen.
    surged: bool = false,

    /// HOW FAR UNDER ITS OWN GROUND THE BODY IS RIDING, metres. 0 at the surface; every world point on it is
    /// measured with this as a NEGATIVE lift, so the whole creature goes down together and nothing has to be
    /// told about it twice.
    depth: f32 = 0,
    moundR: f32 = 0,
    moundH: f32 = 0,
    surgeK: f32 = 0,
    moundLong: f32 = 1,
    churn: f32 = 0,

    rear: f32 = 0,
    drill: f32 = 0,
    swing: f32 = 0,
    crouch: f32 = 0,
    gait: f32 = 0,
    shudder: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    heroHit: ?combat.Hit = null,
    justDied: bool = false,
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},
    fade: f32 = 0,
    gone: bool = false,

    clawWas: [2]rl.Vector3 = [_]rl.Vector3{mathx.zero3} ** 2,

    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),
    aiRng: mathx.Rng = mathx.Rng.init(2),

    xf: [N]rl.Matrix = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Delver {
        var d = Delver{ .pos = home, .home = home, .facing = faceYaw, .scale = scale, .seed = seed };
        d.fxRng = foe.fxStream(seed, 51473.0, 0xD31E);
        d.aiRng = foe.fxStream(seed, 29399.0, 7);
        d.idleWait = 0.2 + seed * 0.5;
        d.diveCd = DIVE_CD * (0.25 + seed * 0.5);
        d.pose();
        d.clawWas = d.clawSeg();
        return d;
    }

    fn ride(self: *const Delver) f32 {
        return -self.depth * self.scale;
    }
    pub fn centerWorld(self: *const Delver) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H, self.scale, self.ride());
    }
    pub fn lockPoint(self: *const Delver) rl.Vector3 {
        return foe.markOn(self.xf[HEAD], v3(0, 0.06, 0.10));
    }
    pub fn topWorld(self: *const Delver) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * H, self.scale, self.ride());
    }
    pub fn hurtRadius(self: *const Delver) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Delver) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Delver) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Delver) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Delver) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn airborne(self: *const Delver) bool {
        return self.depth > foe.AIRBORNE_LIFT;
    }
    pub fn deep(self: *const Delver) bool {
        return self.depth >= UNDER_DEPTH - 1e-3;
    }
    pub fn mounded(self: *const Delver) bool {
        return self.moundR > 1e-3;
    }
    /// **YOU CANNOT FIX ON WHAT IS UNDER THE GROUND** (owner's call) — the Rooted's `hidden` predicate, which
    /// `game.disguised` finds by `@hasDecl` and every targeting site already asks. A held lock DROPS the frame
    /// it goes under, the flick skips it, a fresh press cannot take it, no bar hangs over the hole and the
    /// wolf stops trying to bite two and a half metres of earth. Coming back up is a re-acquire, and that is
    /// the point of the move: the camera is yours again and it is your problem where the mound went.
    pub fn hidden(self: *const Delver) bool {
        return self.deep();
    }
    pub fn flashFrac(self: *const Delver) f32 {
        return foe.flashFrac(self.flash);
    }

    fn fdir(self: *const Delver) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn clawSeg(self: *const Delver) [2]rl.Vector3 {
        return .{ foe.markOn(self.xf[CLAWR], mathx.zero3), foe.markOn(self.xf[CLAWR], CLAW_TIP) };
    }
    pub fn navWant(self: *const Delver, hero: rl.Vector3) ?rl.Vector3 {
        if (self.state != .walk and self.state != .idle) return null;
        if (self.airborne()) return null;
        if (foe.senseHero(&self.leash, self.pos, hero, AGGRO_R) <= AGGRO_R) return hero;
        return if (mathx.distXZ(self.pos, self.home) > HOME_R) self.home else null;
    }

    fn faceToward(self: *Delver, target: rl.Vector3, rate: f32, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, rate, dt);
    }

    fn goingFor(self: *const Delver, hero: rl.Vector3) rl.Vector3 {
        return if (self.homing or self.leash.goingHome()) self.home else hero;
    }

    pub fn update(self: *Delver, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.heroHit = null;
        self.justDied = false;
        self.parried = false;
        self.surged = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer if (!self.airborne()) grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        self.vit.tick(dt);
        self.elapsed += dt;
        self.t += dt;
        self.clawCd = mathx.maxF(0, self.clawCd - dt);
        self.diveCd = mathx.maxF(0, self.diveCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, self.home, hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        switch (self.state) {
            .idle => self.updateIdle(dt, hero),
            .walk => self.updateWalk(dt, hero, bounds),
            .claw => self.updateClaw(dt, hero),
            .rake => self.updateRake(dt, hero),
            .recover => {
                self.swing = mathx.approach(self.swing, 0, dt * 3.2);
                self.crouch = mathx.approach(self.crouch, 0.05, dt * 1.4);
                self.rear = mathx.approach(self.rear, 0, dt * 2.2);
                if (self.t >= CLAW_RECOVER) self.enterIdle(0.12);
            },
            .heave => {
                self.depth = mathx.approach(self.depth, 0, dt * 9.0);
                const k = mathx.smoothstep(0, BURST_RECOVER, self.t);
                self.rear = lerpF(0.58, 0, k);
                self.swing = lerpF(0.45, 0, k) + 0.09 * mathx.sinf(self.t * 21.0) * (1.0 - k);
                self.crouch = lerpF(0.30, 0.05, k);
                if (self.t < BURST_RECOVER * 0.4) self.emitScuff(dt);
                if (self.t >= BURST_RECOVER) self.enterIdle(0.12);
            },
            .dive => self.updateDive(dt, hero),
            .under => self.updateUnder(dt, hero, bounds),
            .surge => self.updateSurge(dt),
            .plough => self.updatePlough(dt, hero, bounds),
            .burst => self.updateBurst(dt, hero),
            .stunlight, .stunheavy => {
                // KNOCKED BACK ONTO ITS HAUNCHES, forelimbs up and useless. It cannot be flinched while it is
                // under — nothing down there is taking a blow — so this is always a surfaced pose.
                self.rear = mathx.approach(self.rear, 0.34 * foe.stunCurve(self.t, self.state == .stunheavy), dt * 6.0);
                self.crouch = mathx.approach(self.crouch, 0.16, dt * 5.0);
                self.swing = mathx.approach(self.swing, 0, dt * 4.0);
                self.depth = mathx.approach(self.depth, 0, dt * 5.0);
                if (self.t >= combat.foeStunDur(self.state == .stunheavy)) self.enterIdle(0.14);
            },
            .dead => {
                self.rear = mathx.approach(self.rear, 0, dt * 3.0);
                self.crouch = mathx.approach(self.crouch, 0.62, dt * 1.6);
                self.drill = mathx.approach(self.drill, 12.0, dt * 40.0);
                self.depth = mathx.approach(self.depth, 0, dt * 3.4);
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
        }

        self.settleMound(dt);
        self.pose();
        const now = self.clawSeg();
        const swung: ?combat.Hit = switch (self.state) {
            .claw => if (self.t >= CLAW_WIND and self.t < CLAW_WIND + CLAW_STRIKE) CLAW_HIT else null,
            .rake => if (self.t >= RAKE_WIND and self.t < RAKE_WIND + RAKE_STRIKE) RAKE_HIT else null,
            else => null,
        };
        if (swung) |h| {
            if (!self.heroLatch and foe.weaponReaches(self.clawWas, now, hero, CLAW_SWEEP_R * self.scale)) {
                self.heroLatch = true;
                self.heroHit = h;
                self.leash.noteCombat();
            }
        }
        self.clawWas = now;
        self.takeParry();
        self.tryHit(blade);
        return self.heroHit;
    }

    fn updateIdle(self: *Delver, dt: f32, hero: rl.Vector3) void {
        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        if (d <= AGGRO_R) self.faceToward(self.goingFor(hero), TURN_RATE, dt);
        // Three clocks that never line up (the wanderer's law): a breath, a shoulder roll, a snout that casts
        // about. A digger standing still is still SMELLING for you.
        const br = mathx.sinf(self.elapsed * (1.5 + 0.3 * self.seed) + self.seed * 6.28);
        self.crouch = mathx.approach(self.crouch, 0.05 + 0.025 * br, dt * 3.0);
        self.rear = mathx.approach(self.rear, 0.04 + 0.03 * mathx.sinf(self.elapsed * 0.9 + self.seed * 4.0), dt * 2.0);
        self.swing = mathx.approach(self.swing, 0.06 * mathx.sinf(self.elapsed * 1.3 + self.seed * 11.0), dt * 2.0);
        self.drill = mathx.approach(self.drill, 0, dt * 60.0);
        if (self.t >= self.idleWait) self.decide(d);
    }

    fn updateWalk(self: *Delver, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const to = self.goingFor(hero);
        self.faceToward(self.nav.aim(self.pos, to), TURN_RATE, dt);
        const moved = (if (self.homing) WALK_SPEED else CHASE_SPEED) * self.scale * dt;
        mathx.stepXZ(&self.pos, self.fdir(), moved, bounds);
        self.gait += moved / (STRIDE * self.scale);
        self.crouch = 0.10 + 0.035 * mathx.sinf(self.gait * std.math.tau * 2.0);
        self.rear = mathx.approach(self.rear, 0, dt * 3.0);
        self.swing = 0.24 * mathx.sinf(self.gait * std.math.tau);
        self.emitScuff(dt);
        if (self.homing and mathx.distXZ(self.pos, self.home) <= HOME_R) {
            self.homing = false;
            self.enterIdle(0.4);
            return;
        }
        if (self.t >= 0.22) self.decide(foe.senseHero(&self.leash, self.pos, hero, AGGRO_R));
    }

    fn updateClaw(self: *Delver, dt: f32, hero: rl.Vector3) void {
        if (self.t < CLAW_WIND) {
            self.faceToward(hero, TURN_RATE * 0.6, dt);
            const u = mathx.smoothstep(0, CLAW_WIND, self.t);
            self.swing = lerpF(0, -1.0, u);
            self.rear = lerpF(0, 0.72, u);
            self.crouch = lerpF(0.05, -0.10, u);
        } else if (self.t < CLAW_WIND + CLAW_STRIKE) {
            const u = (self.t - CLAW_WIND) / CLAW_STRIKE;
            self.swing = lerpF(-1.0, 1.0, foe.swingCurve(u));
            self.rear = lerpF(0.72, 0.24, u);
            self.crouch = lerpF(-0.10, 0.16, u);
        } else if (self.wantsRake(hero)) {
            self.raked = true;
            self.heroLatch = false;
            sfx.world(.delver_claw, self.pos);
            self.enter(.rake);
        } else {
            self.enter(.recover);
        }
    }

    fn wantsRake(self: *Delver, hero: rl.Vector3) bool {
        if (self.raked) return false;
        if (mathx.distXZ(self.pos, hero) > CLAW_BAND) return false;
        return self.aiRng.float() < RAKE_CHANCE;
    }

    fn updateRake(self: *Delver, dt: f32, hero: rl.Vector3) void {
        if (self.t < RAKE_WIND) {
            self.faceToward(hero, TURN_RATE * 0.9, dt);
            const u = mathx.smoothstep(0, RAKE_WIND, self.t);
            self.swing = lerpF(1.0, 0.88, u);
            self.rear = lerpF(0.24, 0.54, u);
            self.crouch = lerpF(0.16, -0.04, u);
        } else if (self.t < RAKE_WIND + RAKE_STRIKE) {
            const u = (self.t - RAKE_WIND) / RAKE_STRIKE;
            self.swing = lerpF(0.88, -1.0, foe.swingCurve(u));
            self.rear = lerpF(0.54, 0.18, u);
            self.crouch = lerpF(-0.04, 0.14, u);
        } else {
            self.enter(.recover);
        }
    }

    fn aheadOf(self: *const Delver, to: rl.Vector3) bool {
        if (mathx.distXZ(self.pos, to) < PLOUGH_R_MIN * self.scale) return false;
        const dir = mathx.dirXZ(self.pos, to);
        if (mathx.lenXZ(dir) < 1e-4) return false;
        return combat.withinArc(mathx.headingXZ(dir), self.facing, PLOUGH_ARC);
    }

    fn linedUp(self: *const Delver, to: rl.Vector3) bool {
        return self.aheadOf(to) and mathx.distXZ(self.pos, to) <= PLOUGH_R_MAX * self.scale;
    }

    fn updatePlough(self: *Delver, dt: f32, hero: rl.Vector3, bounds: f32) void {
        self.depth = UNDER_DEPTH;
        if (self.t < PLOUGH_WIND) {
            const u = mathx.smoothstep(0, PLOUGH_WIND, self.t);
            mathx.stepXZ(&self.pos, self.fdir(), UNDER_SPEED * 0.45 * self.scale * dt, bounds);
            self.moundR = lerpF(MOUND_TRAVEL_R, MOUND_PLOUGH_R, u);
            self.moundH = lerpF(MOUND_TRAVEL_H, MOUND_PLOUGH_H, u);
            self.moundLong = lerpF(1.0, MOUND_PLOUGH_LONG, u);

            self.shudder = u * 0.6;
            self.emitSpray(dt, 10.0 + 22.0 * u);
            return;
        }
        const u = mathx.clampF((self.t - PLOUGH_WIND) / PLOUGH_DUR, 0, 1);
        const speed = PLOUGH_SPEED * lerpF(0.55, 1.0, mathx.smoothstep(0, 0.30, u)) *
            (1.0 - 0.5 * mathx.smoothstep(0.75, 1.0, u));
        const was = self.pos;
        mathx.stepXZ(&self.pos, self.fdir(), speed * self.scale * dt, bounds);
        self.gait += speed * dt / (STRIDE * self.scale);
        self.emitWake(dt);
        self.emitSpray(dt, 24.0);
        // **THE FURROW IS A SWEPT SEGMENT.** At nine metres a second it covers fifteen centimetres a frame,
        // and a point test against a body 0.36 m across steps straight over him about half the time.
        if (!self.heroLatch and self.furrowed(was, hero)) {
            self.heroLatch = true;
            self.heroHit = PLOUGH_HIT;
            self.leash.noteCombat();
            self.dirtBurst(v3(hero.x, self.pos.y + 0.08, hero.z), 12, 3.0, 0.20);
        }
        if (u >= 1.0) {
            sfx.world(.delver_burst, self.pos);
            self.burstDirt();
            self.armDive();
            self.enter(.heave);
        }
    }

    fn furrowed(self: *const Delver, was: rl.Vector3, hero: rl.Vector3) bool {
        const q = mathx.closestOnSegXZ(hero, was, self.pos);
        return mathx.distXZ(hero, q) <= PLOUGH_R * self.scale + foe.HERO_R;
    }

    fn updateDive(self: *Delver, dt: f32, hero: rl.Vector3) void {
        if (self.t < DIVE_WIND) {
            self.faceToward(self.goingFor(hero), TURN_RATE, dt);
            // UP ON ITS HIND LEGS, forelimbs overhead — the biggest it ever is, and the only frame of this
            // creature you can read from across the field.
            const u = mathx.smoothstep(0, DIVE_WIND, self.t);
            self.rear = lerpF(0, 1.0, u);
            self.swing = lerpF(0, -0.7, u);
            self.crouch = lerpF(0.05, -0.22, u);
            self.drill = lerpF(0, -18.0, u);
            if (self.t >= DIVE_WIND * 0.6) self.emitScrape(dt);
            return;
        }
        if (!foe.canLeap(&self.root)) {
            sfx.world(.delver_hurt, self.pos);
            self.enter(.recover);
            return;
        }
        const u = mathx.clampF((self.t - DIVE_WIND) / DIVE_DUR, 0, 1);
        self.rear = lerpF(1.0, 0, u);
        self.drill = lerpF(-18.0, 62.0, u);
        self.swing = lerpF(-0.7, 0.8, u);
        self.depth = UNDER_DEPTH * u;
        self.emitSpray(dt, 26.0);
        if (u >= 1.0) self.enter(.under);
    }

    fn updateUnder(self: *Delver, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const to = self.goingFor(hero);
        self.depth = UNDER_DEPTH;
        self.faceToward(to, UNDER_TURN, dt);
        mathx.stepXZ(&self.pos, self.fdir(), UNDER_SPEED * self.scale * dt, bounds);
        self.gait += UNDER_SPEED * dt / (STRIDE * self.scale);
        self.drill = 0;
        self.emitWake(dt);
        self.churn += dt;
        if (self.churn >= CHURN_EVERY) {
            self.churn -= CHURN_EVERY;
            sfx.world(.delver_churn, self.pos);
        }
        if (self.t < UNDER_MIN) return;
        if (mathx.distXZ(self.pos, to) <= SURGE_LOCK_R + self.bodyR()) return self.enterSurge();
        if (self.linedUp(to)) return self.enterPlough();
        if (self.t >= UNDER_MAX) {
            if (self.aheadOf(to)) return self.enterPlough();
            return self.enterSurge();
        }
    }

    fn enterSurge(self: *Delver) void {
        sfx.world(.delver_surge, self.pos);
        self.surged = true;
        self.enter(.surge);
    }

    fn enterPlough(self: *Delver) void {
        sfx.world(.delver_churn, self.pos);
        self.surged = true;
        self.heroLatch = false;
        self.enter(.plough);
    }

    fn updateSurge(self: *Delver, dt: f32) void {
        self.depth = UNDER_DEPTH;
        const u = mathx.smoothstep(0, SURGE_DUR, self.t);
        self.moundR = MOUND_SWELL_R;
        self.moundH = MOUND_SWELL_H;
        self.shudder = u;
        self.surgeK = std.math.pow(f32, u, SURGE_SPRAY_CURVE);
        self.emitSpray(dt, lerpF(SURGE_SPRAY_0, SURGE_SPRAY_1, self.surgeK));
        if (self.t >= SURGE_DUR) {
            sfx.world(.delver_burst, self.pos);
            self.enter(.burst);
        }
    }

    fn updateBurst(self: *Delver, dt: f32, hero: rl.Vector3) void {
        const u = mathx.clampF(self.t / BURST_RISE, 0, 1);
        self.depth = UNDER_DEPTH * (1.0 - u);
        self.rear = lerpF(1.0, 0.58, u);
        self.swing = lerpF(-0.85, 0.45, u);
        self.drill = lerpF(-52.0, -14.0, u);
        self.shudder = 0;
        self.moundR = lerpF(MOUND_SWELL_R, 0, u);
        self.moundH = lerpF(MOUND_SWELL_H, 0, u * u);
        if ((self.t - dt) <= 0 and self.t > 0) {
            // The blow is on the OPENING frame, and its reach is a RADIUS — the ground opening has no edge to
            // sweep. Its `from` is the hole itself, so stood dead on it there is no bearing and the boards
            // cannot answer it (the zero-`fromDir` rule); caught at the rim, they can.
            self.burstDirt();
            if (mathx.distXZ(self.pos, hero) <= BURST_R * self.scale + foe.HERO_R) {
                self.heroHit = BURST_HIT;
                self.leash.noteCombat();
            }
        }
        if (self.t >= BURST_RISE) {
            self.depth = 0;
            self.moundR = 0;
            self.moundH = 0;
            self.surgeK = 0;
            self.armDive();
            self.enter(.heave);
        }
    }

    fn armDive(self: *Delver) void {
        self.diveCd = DIVE_CD * self.aiRng.range(0.85, 1.25);
    }

    fn decide(self: *Delver, d: f32) void {
        const pick = classify(d, self.clawCd <= 0, self.diveCd <= 0, !foe.canLeap(&self.root));
        if (pick != .rest) self.homing = false;
        switch (pick) {
            .rest => {
                if (mathx.distXZ(self.pos, self.home) > HOME_R) {
                    self.homing = true;
                    self.enter(.walk);
                } else self.enterIdle(0.5 + self.seed * 0.5);
            },
            .wait => self.enterIdle(0.24),
            .walk => self.enter(.walk),
            .claw => {
                self.clawCd = CLAW_CD * self.aiRng.range(0.85, 1.3);
                self.heroLatch = false;
                self.raked = false;
                sfx.world(.delver_claw, self.pos);
                self.enter(.claw);
            },
            .dive => {
                sfx.world(.delver_dig, self.pos);
                self.enter(.dive);
            },
        }
    }

    /// The mound has a life of its own on the way in and the way out — it is a heap of earth, and a heap of
    /// earth does not appear on one frame. Driven off what the BODY is doing rather than off a clock beside
    /// it, so the two can never disagree about whether there is anything down there.
    fn settleMound(self: *Delver, dt: f32) void {
        const wantR: f32 = switch (self.state) {
            .dive => MOUND_TRAVEL_R * mathx.clampF(self.depth / UNDER_DEPTH, 0, 1),
            .under => MOUND_TRAVEL_R,
            .surge, .plough, .burst => self.moundR,
            else => 0,
        };
        const wantH: f32 = switch (self.state) {
            .dive => MOUND_TRAVEL_H * mathx.clampF(self.depth / UNDER_DEPTH, 0, 1),
            .under => MOUND_TRAVEL_H + 0.05 * mathx.sinf(self.gait * std.math.tau),
            .surge, .plough, .burst => self.moundH,
            else => 0,
        };
        const wantLong: f32 = if (self.state == .plough) self.moundLong else 1.0;
        self.moundR = mathx.approach(self.moundR, wantR, dt * 5.0);
        self.moundH = mathx.approach(self.moundH, wantH, dt * 5.0);
        self.moundLong = mathx.approach(self.moundLong, wantLong, dt * 6.0);
        if (self.state != .surge and self.state != .plough) self.shudder = mathx.approach(self.shudder, 0, dt * 4.0);
    }

    fn enter(self: *Delver, s: State) void {
        self.state = s;
        self.t = 0;
    }
    fn enterIdle(self: *Delver, wait: f32) void {
        self.state = .idle;
        self.t = 0;
        self.idleWait = wait;
        self.surgeK = 0;
    }
    /// A BLOW NEVER LANDS ON SOMETHING SUBMERGED, so a stun always finds it on the surface — but the depth is
    /// cleared here anyway, because a stagger arriving on the rise must not strand it half in the ground.
    fn enterStun(self: *Delver, s: State) void {
        self.enter(s);
        self.moundR = 0;
        self.moundH = 0;
        self.heroLatch = false;
    }
    fn enterDeath(self: *Delver) void {
        self.state = .dead;
        self.t = 0;
        self.justDied = true;
    }

    pub fn debugDive(self: *Delver) void {
        self.diveCd = 0;
        self.enter(.dive);
    }
    pub fn debugClaw(self: *Delver) void {
        self.heroLatch = false;
        self.raked = false;
        self.enter(.claw);
    }
    pub fn debugRake(self: *Delver) void {
        self.heroLatch = false;
        self.raked = true;
        self.enter(.rake);
    }
    pub fn debugPlough(self: *Delver) void {
        self.heroLatch = false;
        self.depth = UNDER_DEPTH;
        self.moundR = MOUND_TRAVEL_R;
        self.moundH = MOUND_TRAVEL_H;
        self.enter(.plough);
    }
    pub fn debugKill(self: *Delver) void {
        self.enterDeath();
    }
    pub fn debugStagger(self: *Delver, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }

    fn toImpact(self: *const Delver) ?f32 {
        return switch (self.state) {
            .claw => CLAW_WIND - self.t,
            .rake => RAKE_WIND - self.t,
            .idle, .walk, .recover, .dive, .under, .surge, .plough, .burst, .heave, .stunlight, .stunheavy, .dead => null,
        };
    }

    fn parryable(self: *const Delver) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        return CLAW_BAND + foe.HERO_REACH;
    }

    fn takeParry(self: *Delver) void {
        const reach = self.parryable() orelse return;
        if (!self.parry.catches(self.pos, reach)) return;
        self.parried = true;
        self.flash = foe.FLASH_DUR;
        self.leash.noteCombat();
        self.clawCd = CLAW_CD;
        self.heroLatch = false;
        sfx.world(.delver_hurt, self.pos);
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light, .none => self.enterStun(.stunlight),
        }
    }

    pub fn tryHit(self: *Delver, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        const heavy = foe.wounded(self, s, blade, .{ .light = 0.7, .heavy = 1.15 });
        self.dirtBurst(s.contact, if (heavy) 9 else 5, 2.0, 0.13);
        sfx.world(.delver_hurt, self.pos);
        switch (s.reaction) {
            .death => {
                sfx.world(.delver_die, self.pos);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn emit(self: *Delver, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
        foe.emitParticle(&self.parts, &self.fxHead, p, vel, life, r0, r1, col, grav);
    }
    fn dirtBurst(self: *Delver, c: rl.Vector3, n: i32, spd: f32, big: f32) void {
        const parts = foe.hitParts(n);
        var i: i32 = 0;
        while (i < parts) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.4, 1.0) * spd;
            self.emit(c, v3(mathx.cosf(a) * sp, self.fxRng.range(0.6, 2.0), mathx.sinf(a) * sp), self.fxRng.range(0.3, 0.6), self.fxRng.range(0.05, 0.10), big, foe.DUST, 5.0);
        }
    }
    fn burstDirt(self: *Delver) void {
        var i: i32 = 0;
        while (i < 26) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.5, 1.0) * 4.2;
            self.emit(
                v3(self.pos.x + mathx.cosf(a) * 0.4, self.pos.y + 0.10, self.pos.z + mathx.sinf(a) * 0.4),
                v3(mathx.cosf(a) * sp, self.fxRng.range(2.4, 5.2), mathx.sinf(a) * sp),
                self.fxRng.range(0.55, 0.9),
                self.fxRng.range(0.07, 0.15),
                0.03,
                if (self.fxRng.float() < 0.35) CLOD_DK else CLOD,
                9.0,
            );
        }
        self.dirtBurst(v3(self.pos.x, self.pos.y + 0.06, self.pos.z), 14, 3.4, 0.24);
    }
    fn emitWake(self: *Delver, dt: f32) void {
        const emitRate = 22.0;
        var owed = foe.emitTicks(&self.fxAccum, dt, emitRate, foe.emitCap(emitRate));
        while (owed > 0) : (owed -= 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.3, 1.0) * self.moundR * self.scale;
            const back = mathx.scaleV(self.fdir(), -self.fxRng.range(0.1, 0.7));
            self.emit(
                v3(self.pos.x + back.x + mathx.cosf(a) * rr, self.pos.y + 0.08, self.pos.z + back.z + mathx.sinf(a) * rr),
                v3(mathx.cosf(a) * 0.5, self.fxRng.range(0.5, 1.5), mathx.sinf(a) * 0.5),
                self.fxRng.range(0.35, 0.7),
                self.fxRng.range(0.05, 0.11),
                0.03,
                if (self.fxRng.float() < 0.4) CLOD_DK else CLOD,
                6.0,
            );
        }
    }
    fn emitSpray(self: *Delver, dt: f32, rate: f32) void {
        if (rate <= 0) return;
        const kick = 1.0 + (SURGE_SPRAY_LIFT - 1.0) * self.surgeK;
        const emitRate = rate;
        var owed = foe.emitTicks(&self.fxAccum, dt, emitRate, foe.emitCap(emitRate));
        while (owed > 0) : (owed -= 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.2, 1.0) * mathx.maxF(0.5, self.moundR) * self.scale;
            self.emit(
                v3(self.pos.x + mathx.cosf(a) * rr, self.pos.y + 0.06, self.pos.z + mathx.sinf(a) * rr),
                v3(mathx.cosf(a) * 0.8 * kick, self.fxRng.range(1.2, 3.0) * kick, mathx.sinf(a) * 0.8 * kick),
                self.fxRng.range(0.3, 0.6) * (1.0 + 0.5 * self.surgeK),
                self.fxRng.range(0.05, 0.11),
                0.03,
                if (self.fxRng.float() < 0.4) CLOD_DK else CLOD,
                7.5,
            );
        }
    }
    fn emitScrape(self: *Delver, dt: f32) void {
        const emitRate = 14.0;
        var owed = foe.emitTicks(&self.fxAccum, dt, emitRate, foe.emitCap(emitRate));
        while (owed > 0) : (owed -= 1) {
            const f = self.fdir();
            const a = self.fxRng.angle();
            self.emit(
                v3(self.pos.x + f.x * 0.5 + mathx.cosf(a) * 0.3, self.pos.y + 0.05, self.pos.z + f.z * 0.5 + mathx.sinf(a) * 0.3),
                v3(-f.x * 1.6, self.fxRng.range(0.4, 1.2), -f.z * 1.6),
                self.fxRng.range(0.25, 0.5),
                self.fxRng.range(0.04, 0.08),
                0.02,
                CLOD_DK,
                6.0,
            );
        }
    }
    fn emitScuff(self: *Delver, dt: f32) void {
        const emitRate = 5.0;
        var owed = foe.emitTicks(&self.fxAccum, dt, emitRate, foe.emitCap(emitRate));
        while (owed > 0) : (owed -= 1) {
            const a = self.fxRng.angle();
            self.emit(
                v3(self.pos.x + mathx.cosf(a) * 0.4, self.pos.y + 0.03, self.pos.z + mathx.sinf(a) * 0.4),
                v3(mathx.cosf(a) * 0.3, self.fxRng.range(0.2, 0.6), mathx.sinf(a) * 0.3),
                self.fxRng.range(0.2, 0.4),
                0.05,
                0.10,
                foe.DUST,
                4.0,
            );
        }
    }
    pub fn drawFx(self: *const Delver) void {
        foe.drawParticles(&self.parts);
    }

    pub fn draw(self: *const Delver, model: *const Model) void {
        model.draw(self);
    }

    pub fn pose(self: *Delver) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = mathx.sinf(mathx.radians(@abs(self.drill))) * BODY_HALF;
        const clear = sink * (1.0 - mathx.clampF(self.depth / UNDER_DEPTH, 0, 1)) * fs;
        const root = mul3(
            mul(scaleM(fs, fs, fs), rx(self.drill)),
            ry(mathx.degrees(self.facing)),
            tr(self.pos.x, self.pos.y + self.ride() + clear, self.pos.z),
        );
        self.xf[BODY] = root;

        const headPitch = -22.0 * self.rear + 16.0 * self.crouch + 10.0 * self.swing;
        const headYaw = 12.0 * self.swing;
        self.xf[HEAD] = mul(mul3(ry(headYaw), rx(headPitch), tr(REST[HEAD].x, REST[HEAD].y + 0.10 * self.rear, REST[HEAD].z)), root);

        for ([_]usize{ ARML, ARMR }, [_]usize{ CLAWL, CLAWR }, [_]f32{ 1, -1 }) |ai, ci, sgn| {
            const own = if (sgn < 0) self.swing else self.swing * 0.45;
            const shoulder = -74.0 * self.rear - 34.0 * own;
            const abd = 16.0 + 26.0 * self.rear + 10.0 * @abs(own);
            const hip = v3(REST[ai].x, REST[ai].y - 0.12 * self.crouch, REST[ai].z);
            // **AND THE STROKE HAS TO GO ACROSS HIM, WHICH MEANS IT NEEDS A LATERAL CHANNEL** (owner: the
            // moles cannot hit me with their regular attacks). `swing` was spent entirely on `rx` — a
            // SAGITTAL rake — while `abd` used `@abs(own)`, so the limb was pushed FURTHER OUT at both ends
            // of the arc. Measured, the claw ran from x −0.51 to −1.07 and back and never once crossed the
            // body's own axis: the whole stroke happened down its flank while the man it was aimed at stood
            // dead ahead. The reach test passed the whole time because it measured RADIAL distance from the
            // body centre, which a swipe out to the side satisfies perfectly.
            const cross = SWING_YAW * own * -sgn;
            self.xf[ai] = mul(mul(mul3(rz(sgn * abd), rx(shoulder), ry(cross)), tr(hip.x, hip.y, hip.z)), root);
            const elbow = 40.0 - 46.0 * own - 26.0 * self.rear;
            self.xf[ci] = mul(mul(rx(elbow), tr(REST[ci].x, REST[ci].y, REST[ci].z)), self.xf[ai]);
        }

        const step = mathx.sinf(self.gait * std.math.tau);
        for ([_]usize{ HINDL, HINDR }, [_]f32{ 1, -1 }) |bi, sgn| {
            const ph = step * sgn;
            const hipA = 18.0 * self.rear + 26.0 * ph - 20.0 * self.crouch;
            self.xf[bi] = mul(mul3(rz(sgn * 10.0), rx(hipA), tr(REST[bi].x, REST[bi].y - 0.14 * self.crouch, REST[bi].z)), root);
        }

        const tailA = 34.0 * self.rear - 20.0 * self.swing;
        self.xf[TAIL] = mul(mul3(ry(-14.0 * self.swing), rx(tailA), tr(REST[TAIL].x, REST[TAIL].y, REST[TAIL].z)), root);

        const sh = self.shudder;
        const throb = 1.0 + 0.06 * sh * mathx.sinf(self.elapsed * 26.0);
        const mr = self.moundR * self.scale * throb;
        const mh = self.moundH * self.scale * throb;
        self.xf[MOUND] = mul3(
            mul(scaleM(mr, mh, mr * self.moundLong), rz(2.6 * sh * mathx.sinf(self.elapsed * 31.0))),
            ry(mathx.degrees(self.facing)),
            tr(self.pos.x, self.pos.y + 0.02, self.pos.z),
        );
    }
};

const CAP_N = wf.MAX_PER_KIND;

pub const Warrens = struct {
    model: Model,
    delvers: [CAP_N]Delver = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Warrens {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Warrens) []Delver {
        return self.delvers[0..self.n];
    }
    pub fn liveConst(self: *const Warrens) []const Delver {
        return self.delvers[0..self.n];
    }
    pub fn reset(self: *Warrens, m: *const wf.Map) void {
        foe.resetGroup(Delver, &self.delvers, &self.n, m, .delver);
    }
    pub fn setShader(self: *Warrens, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn setParry(self: *Warrens, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    pub fn anyParried(self: *const Warrens) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn anySurged(self: *const Warrens) bool {
        for (self.liveConst()) |*d| {
            if (d.surged) return true;
        }
        return false;
    }
    pub fn update(self: *Warrens, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    pub fn draw(self: *const Warrens, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Warrens) void {
        for (self.liveConst()) |*d| d.drawFx();
    }
    pub fn pierce(self: *Warrens, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Warrens) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Warrens) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Warrens) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Warrens) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[BODY] = bodyMesh();
    mesh[HEAD] = headMesh();
    mesh[ARML] = armMesh(1);
    mesh[ARMR] = armMesh(-1);
    mesh[CLAWL] = clawMesh(1);
    mesh[CLAWR] = clawMesh(-1);
    mesh[HINDL] = hindMesh(1);
    mesh[HINDR] = hindMesh(-1);
    mesh[TAIL] = tailMesh();
    mesh[MOUND] = moundMesh();
    return mesh;
}

fn bodyMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xD31E);
    b.setMat(.skin);
    // LONG AND LOW. A digger is a wedge lying on the ground, not a boulder standing on it: the first pass
    // was 0.87 m tall on a 1.55 m creature and read as a tortoise.
    b.addBlob(v3(0, 0.26 * H, -0.08), v3(0.42, 0.17 * H, 0.80), 8, 14, HIDE);
    b.addBlob(v3(0, 0.30 * H, 0.30), v3(0.40, 0.15 * H, 0.38), 7, 13, HIDE);
    b.addBlob(v3(0, 0.14 * H, 0.04), v3(0.36, 0.09 * H, 0.66), 6, 12, HIDE_LO);
    b.addBlob(v3(0, 0.22 * H, -0.66), v3(0.30, 0.13 * H, 0.28), 6, 12, HIDE_LO);
    var i: i32 = 0;
    while (i < 8) : (i += 1) {
        const u = @as(f32, @floatFromInt(i)) / 7.0;
        const z = 0.50 - u * 1.24;
        const taper = 1.0 - 0.45 * u;
        b.addBlob(
            v3(rng.signed() * 0.04, (0.26 + 0.155) * H - 0.05 * u * u, z),
            v3(rng.range(0.16, 0.26) * taper, rng.range(0.024, 0.042), rng.range(0.08, 0.12)),
            5,
            10,
            PLATE,
        );
    }
    return b.toMesh();
}

fn headMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, 0, 0.04), v3(0.22, 0.16, 0.26), 7, 13, HIDE);
    b.addCapsule(v3(0, -0.02, 0.18), v3(0, -0.06, 0.38), 0.14, 0.09, 9, SNOUT);
    b.addBlob(v3(0, -0.06, 0.41), v3(0.10, 0.075, 0.07), 5, 10, SNOUT);
    b.addBlob(v3(0, 0.09, 0.12), v3(0.185, 0.042, 0.18), 5, 11, PLATE);
    b.setMat(.plain);
    b.addBlob(v3(0.13, 0.01, 0.20), v3(0.030, 0.026, 0.026), 4, 8, EYE);
    b.addBlob(v3(-0.13, 0.01, 0.20), v3(0.030, 0.026, 0.026), 4, 8, EYE);
    return b.toMesh();
}

fn armMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, 0, 0), v3(0.19, 0.18, 0.19), 5, 10, HIDE);
    b.addCapsule(v3(0, -0.02, 0.02), v3(side * 0.12, -0.14, 0.44), 0.155, 0.125, 9, HIDE_LO);
    return b.toMesh();
}

fn clawMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(side * 0.05, -0.09, 0.40), 0.125, 0.10, 9, HIDE_LO);
    b.addBlob(v3(side * 0.05, -0.10, 0.44), v3(0.14, 0.11, 0.13), 5, 10, HIDE_LO);
    b.setMat(.plain);
    // **THE CLAWS ARE THE CREATURE'S POINT AND THEY HAVE TO LOOK IT** (owner: more pronounced claws and
    // nails). At 0.04 thick and 0.22 long they were three scratches on the end of a pad — a digging animal's
    // whole argument is its hands, and on a body this dark the only thing that carries at distance is the pale
    // horn on the front of it. Half again as long, half again as thick at the root, and hooked DOWN and UNDER
    // rather than laid flat, which is what says they are for tearing earth rather than for standing on.
    //
    // Still THREE, still uneven, still longest in the middle, and **still none of them ends in a point** — the
    // tip is a blunt capsule cap, because a rosette of needles is a hub of spokes. What makes them read as
    // sharp is the TAPER (0.062 to 0.020, a hair over 3:1) and the hook, never a spike.
    inline for (.{
        .{ 0.11, -0.12, 0.50, 0.13, -0.30, 0.92, 0.056, 0.020 },
        .{ 0.00, -0.13, 0.51, 0.00, -0.33, 1.02, 0.062, 0.022 },
        .{ -0.09, -0.12, 0.49, -0.12, -0.28, 0.87, 0.050, 0.019 },
    }) |c| {
        b.addBlob(v3(side * c[0], c[1] + 0.01, c[2] - 0.02), v3(c[6] * 1.5, c[6] * 1.4, c[6] * 1.6), 5, 8, HIDE_LO);
        const mx = side * (c[0] + c[3]) * 0.5;
        const my = (c[1] + c[4]) * 0.5 + 0.035;
        const mz = (c[2] + c[5]) * 0.5;
        b.addCapsule(v3(side * c[0], c[1], c[2]), v3(mx, my, mz), c[6], c[6] * 0.72, 7, CLAW);
        b.addCapsule(v3(mx, my, mz), v3(side * c[3], c[4], c[5]), c[6] * 0.72, c[7], 7, CLAW);
        b.addBlob(v3(side * c[3], c[4], c[5]), v3(c[7] * 1.1, c[7] * 1.1, c[7] * 1.2), 4, 7, CLAW_LT);
    }
    return b.toMesh();
}

fn hindMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(side * 0.06, -0.28, -0.06), 0.16, 0.12, 9, HIDE_LO);
    b.addBlob(v3(side * 0.07, -0.34, 0.02), v3(0.13, 0.07, 0.17), 5, 10, HIDE_LO);
    return b.toMesh();
}

fn tailMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(0, -0.06, -0.34), 0.17, 0.10, 9, HIDE_LO);
    b.addBlob(v3(0, -0.08, -0.40), v3(0.10, 0.09, 0.10), 5, 10, HIDE_LO);
    return b.toMesh();
}

fn moundMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x50110);
    b.setMat(.stone);
    b.addBlob(v3(0, -0.62, 0.08), v3(0.74, 1.30, 1.06), 6, 14, SOIL);
    b.addBlob(v3(0.10, -0.60, -0.32), v3(0.50, 1.12, 0.56), 5, 11, SOIL_DK);
    b.addBlob(v3(-0.08, -0.62, 0.48), v3(0.42, 1.16, 0.42), 5, 11, SOIL);
    var i: i32 = 0;
    while (i < 11) : (i += 1) {
        const a = rng.angle();
        const rr = rng.range(0.30, 0.80);
        const sz = rng.range(0.09, 0.19);
        b.addBlob(
            v3(mathx.cosf(a) * rr * 0.62, rng.range(0.16, 0.52), mathx.sinf(a) * rr * 1.05),
            v3(sz, sz * 1.5, sz),
            4,
            9,
            if (rng.float() < 0.5) SOIL_DK else SOIL,
        );
    }
    return b.toMesh();
}

test "IT STAYS DOWN, and it comes up under him" {
    var d = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, 9.0);
    d.debugDive();
    var under: f32 = 0;
    var burst = false;
    var fr: u32 = 0;
    while (fr < 60 * 20) : (fr += 1) {
        _ = d.update(1.0 / 60.0, hero, 400, .{});
        if (d.state == .under) under += 1.0 / 60.0;
        if (d.state == .burst) {
            burst = true;
            break;
        }
    }
    try std.testing.expect(burst);
    try std.testing.expect(under >= UNDER_MIN);
    try std.testing.expect(mathx.distXZ(d.pos, hero) < BURST_R);
    try std.testing.expect(mathx.distXZ(d.pos, mathx.zero3) > 4.0);
}

test "TWO WAYS OUT OF THE BURROW: under him it BURSTS, out in front of him it PLOUGHS" {
    {
        var d = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
        const hero = v3(0, 0, 6.0);
        d.debugDive();
        var fr: u32 = 0;
        while (fr < 60 * 20 and d.state != .surge and d.state != .plough) : (fr += 1) {
            _ = d.update(1.0 / 60.0, hero, 400, .{});
        }
        try std.testing.expectEqual(State.surge, d.state);
    }
    // …and SPRINTING he cannot be — `SPRINT_SPEED` is over `UNDER_SPEED`, so the chase is one it will never
    // win. It stops trying to get under him and drives the ridge down the ground he is running over instead,
    // which is the one answer this creature did not have to a player who simply keeps walking.
    {
        var d = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
        var hero = v3(0, 0, 4.5);
        d.debugDive();
        var fr: u32 = 0;
        while (fr < 60 * 20 and d.state != .surge and d.state != .plough) : (fr += 1) {
            hero.z += 5.1 * (1.0 / 60.0);
            _ = d.update(1.0 / 60.0, hero, 400, .{});
        }
        try std.testing.expectEqual(State.plough, d.state);
        try std.testing.expect(d.depth >= UNDER_DEPTH - 1e-3);
    }
}

test "SUBMERGED IT IS UNDER THE GROUND AT EVERY SCALE THE MAP CAN POST, not just at 1" {
    // The comptime block above is written in bare constants, which READS like a check that can only speak for
    // scale 1 — and a map may post this creature anywhere in `wf.FOE_SCALE_LO..HI`. It is in fact
    // scale-invariant, because `depth` is in scale-1 metres and `ride()` is the thing that scales it. This
    // walks the band and measures the actual sphere, so the next reader who spots the same apparent gap and
    // scales `depth` at its writers gets told: that double-scales the burrow, and a 0.5 delver surfaces.
    for ([_]f32{ wf.FOE_SCALE_LO, 1.0, 1.4, wf.FOE_SCALE_HI }) |sc| {
        var d = Delver.spawn(mathx.zero3, 0, sc, 0.3);
        d.debugDive();
        var fr: u32 = 0;
        while (fr < 60 * 6 and !d.deep()) : (fr += 1) _ = d.update(1.0 / 60.0, v3(0, 0, 1.2), 400, .{});
        try std.testing.expect(d.deep());
        // The sphere the swept blade tests against, measured exactly as `foe.bodyPoint` builds it.
        const c = d.centerWorld();
        try std.testing.expect(c.y + d.hurtRadius() < d.pos.y);
    }
}

test "THE PLOUGH IS A LINE, and stepping off it is the whole counter" {
    const struck = struct {
        fn at(off: f32) bool {
            var d = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
            const hero = v3(off, 0, 6.0);
            d.debugPlough();
            var fr: u32 = 0;
            while (fr < 60 * 4) : (fr += 1) {
                if (d.update(1.0 / 60.0, hero, 400, .{})) |h| return h.dmg == PLOUGH_HIT.dmg;
                if (d.state == .heave) return false;
            }
            return false;
        }
    }.at;
    try std.testing.expect(struck(0));
    try std.testing.expect(struck(PLOUGH_R * 0.5));
    try std.testing.expect(!struck(PLOUGH_R + foe.HERO_R + 1.0));
    try std.testing.expect(PLOUGH_HIT.stance < BURST_HIT.stance);
}

test "THE CLAW COMES BACK — the surfaced window is a trade now, not a free hit" {
    try std.testing.expect(RAKE_WIND < CLAW_WIND);
    var seen = false;
    var s: u32 = 0;
    while (s < 24 and !seen) : (s += 1) {
        var d = Delver.spawn(mathx.zero3, 0, 1.0, @as(f32, @floatFromInt(s)) / 24.0);
        const hero = v3(0, 0, 1.4);
        d.debugClaw();
        var fr: u32 = 0;
        while (fr < 60 * 3) : (fr += 1) {
            _ = d.update(1.0 / 60.0, hero, 400, .{});
            if (d.state == .rake) seen = true;
            if (d.state == .rake or d.state == .recover) break;
        }
    }
    try std.testing.expect(seen);

    // …AND NEVER AT A MAN WHO HAS ALREADY LEFT. A backhand thrown at empty air is the creature announcing
    // that the punish was free after all, which is the thing this move exists to stop.
    var far = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
    const gone = v3(0, 0, CLAW_BAND + 4.0);
    far.debugClaw();
    var fr: u32 = 0;
    while (fr < 60 * 3) : (fr += 1) {
        _ = far.update(1.0 / 60.0, gone, 400, .{});
        try std.testing.expect(far.state != .rake);
        if (far.state == .recover) break;
    }
}

test "THE COOLDOWN IS SURFACE TIME — the burrow does not spend the dial that gates it" {
    // Armed where it went DOWN, the under, the surge, the rise and the opening ran most of `DIVE_CD` off
    // before the creature was ever standing in front of you — and a burrow that went to `UNDER_MAX` left
    // nothing at all, so it re-dived on the frame it finished getting up.
    try std.testing.expect(UNDER_MIN + SURGE_DUR + BURST_RISE + BURST_RECOVER > DIVE_CD * 0.5);
    var d = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, 3.0);
    d.debugDive();
    var fr: u32 = 0;
    while (fr < 60 * 30 and d.state != .heave) : (fr += 1) _ = d.update(1.0 / 60.0, hero, 400, .{});
    try std.testing.expectEqual(State.heave, d.state);
    try std.testing.expect(d.diveCd > DIVE_CD * 0.8);
}

test "A BLOW ON THE RISE DOES NOT HAUL IT OUT OF THE GROUND" {
    var d = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
    d.state = .burst;
    d.t = 0;
    d.depth = UNDER_DEPTH * 0.6;
    const was = d.depth;
    d.debugStagger(true);
    try std.testing.expectApproxEqAbs(was, d.depth, 1e-5);
    _ = d.update(1.0 / 60.0, v3(0, 0, 3), 400, .{});
    try std.testing.expect(d.depth < was);
    try std.testing.expect(d.depth > was - 0.4);
}

test "SUBMERGED IT CANNOT BE STRUCK, and the sword answers it the moment it breaks the surface" {
    var d = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, 3.0);
    const sword = foe.Blade{
        .active = true,
        .r = 0.2,
        .a = v3(-1.2, 0.9, 0),
        .b = v3(1.2, 0.2, 0),
        .a0 = v3(-1.2, 0.9, 0),
        .b0 = v3(1.2, 0.2, 0),
        .hit = .{ .dmg = 20, .poise = 30 },
    };
    d.debugDive();
    var fr: u32 = 0;
    while (fr < 60 * 8 and d.state != .under) : (fr += 1) _ = d.update(1.0 / 60.0, hero, 400, .{});
    try std.testing.expectEqual(State.under, d.state);
    const hitsWhenDown = d.hits;
    fr = 0;
    while (fr < 60) : (fr += 1) {
        d.hitLatch = false;
        _ = d.update(1.0 / 60.0, hero, 400, sword);
    }
    try std.testing.expectEqual(hitsWhenDown, d.hits);
    d.depth = 0;
    d.state = .idle;
    d.hitLatch = false;
    d.pos = mathx.zero3;
    d.pose();
    d.tryHit(sword);
    try std.testing.expect(d.hits > hitsWhenDown);
}

test "THE DIVE IS A LEAP AND THE ROOTS REFUSE IT — at the choose AND at the launch" {
    try std.testing.expectEqual(Choice.dive, classify(6.0, true, true, false));
    try std.testing.expectEqual(Choice.walk, classify(6.0, true, true, true));
    try std.testing.expectEqual(Choice.claw, classify(CLAW_BAND - 0.2, true, false, true));
    try std.testing.expectEqual(Choice.rest, classify(AGGRO_R + 1.0, true, true, false));

    var d = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
    d.debugDive();
    var fr: u32 = 0;
    while (fr < 60 * 2 and d.state == .dive and d.t < DIVE_WIND * 0.5) : (fr += 1) {
        _ = d.update(1.0 / 60.0, v3(0, 0, 5), 400, .{});
    }
    d.root.grab();
    fr = 0;
    while (fr < 60 * 2 and d.state == .dive) : (fr += 1) _ = d.update(1.0 / 60.0, v3(0, 0, 5), 400, .{});
    try std.testing.expect(d.state != .under);
    try std.testing.expectApproxEqAbs(@as(f32, 0), d.depth, 1e-5);
}

test "THE BURST IS A RING ROUND THE HOLE, and standing off it is the whole counter" {
    var d = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
    d.state = .surge;
    d.t = SURGE_DUR;
    d.depth = UNDER_DEPTH;
    var on = d;
    var hit: ?combat.Hit = null;
    var fr: u32 = 0;
    while (fr < 30 and hit == null) : (fr += 1) hit = on.update(1.0 / 60.0, v3(0.4, 0, 0.3), 400, .{});
    try std.testing.expect(hit != null);
    try std.testing.expectEqual(BURST_HIT.dmg, hit.?.dmg);
    var off = d;
    hit = null;
    fr = 0;
    while (fr < 30 and hit == null) : (fr += 1) hit = off.update(1.0 / 60.0, v3(0, 0, BURST_R + 1.2), 400, .{});
    try std.testing.expect(hit == null);
}

test "BOTH STROKES ARE PARRYABLE AND THE BURST IS NOT, and the window is the game's own lead" {
    try std.testing.expect(foe.PARRY_LEAD < CLAW_WIND * 0.5);
    try std.testing.expect(foe.PARRY_LEAD < RAKE_WIND * 0.5);
    var d = Delver.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    const step = 1.0 / 600.0;
    const Stroke = struct { state: State, wind: f32, strike: f32 };
    for ([_]Stroke{
        .{ .state = .claw, .wind = CLAW_WIND, .strike = CLAW_STRIKE },
        .{ .state = .rake, .wind = RAKE_WIND, .strike = RAKE_STRIKE },
    }) |a| {
        var open: f32 = -1;
        var shut: f32 = -1;
        var elapsed: f32 = 0;
        d.state = a.state;
        while (elapsed <= a.wind + a.strike) : (elapsed += step) {
            d.t = elapsed;
            if (d.parryable() != null) {
                if (open < 0) open = elapsed;
                shut = elapsed;
            }
        }
        try std.testing.expect(open > 0);
        try std.testing.expectApproxEqAbs(a.wind, shut, 3.0 * step);
        try std.testing.expectApproxEqAbs(foe.PARRY_LEAD, shut - open, 3.0 * step);
    }
    for ([_]State{ .idle, .walk, .recover, .dive, .under, .surge, .plough, .burst, .heave, .stunlight, .stunheavy, .dead }) |s| {
        d.state = s;
        d.t = 0;
        try std.testing.expect(d.parryable() == null);
        d.t = SURGE_DUR - foe.PARRY_LEAD * 0.5;
        try std.testing.expect(d.parryable() == null);
    }
}

test "A CAUGHT CLAW NEVER ARRIVES" {
    var d = Delver.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    const hero = v3(0, 0, 2.0);
    d.state = .claw;
    d.t = CLAW_WIND - foe.PARRY_LEAD * 0.5;
    d.parry = .{ .live = true, .at = hero, .facing = 0 };
    d.takeParry();
    try std.testing.expect(!d.parried and d.state == .claw);
    d.parry = .{ .live = true, .at = hero, .facing = std.math.pi };
    d.takeParry();
    try std.testing.expect(d.parried);
    try std.testing.expect(d.state == .stunlight or d.state == .stunheavy);
    try std.testing.expect(d.clawCd > 0);
}

test "EVERY REACH IS MEASURED, NOT ARGUED — the claw arrives inside what `parryable` promises" {
    var d = Delver.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    d.state = .claw;
    var far: f32 = 0;
    var elapsed: f32 = 0;
    while (elapsed <= CLAW_WIND + CLAW_STRIKE) : (elapsed += 1.0 / 240.0) {
        d.t = elapsed;
        d.updateClaw(1.0 / 240.0, v3(0, 0, 3));
        d.pose();
        const seg = d.clawSeg();
        far = mathx.maxF(far, mathx.distXZ(d.pos, seg[1]));
    }
    std.debug.print("\n  delver claw arrives at {d:.2} m against a declared {d:.2}; band {d:.2}, hero held {d:.2} out\n", .{ far, CLAW_REACH, CLAW_BAND, BODY_R + foe.HERO_R });
    try std.testing.expect(far <= CLAW_REACH);
    try std.testing.expect(far > CLAW_REACH * 0.9);
    try std.testing.expect(CLAW_BAND > BODY_R + foe.HERO_R + 0.3);
    // **AND HEIGHT IS ITS OWN QUESTION.** Its shoulders sit at 0.40 m, so the stroke only ever crosses a
    // standing man because the creature REARS for it — which is why the rear is in the wind and not a
    // flourish. Held flat the rake topped out under his knee, and three claws going past his boots while
    // `weaponReaches` reported a hit is the mesh and the mechanic saying opposite things.
    var high: f32 = 0;
    var rise: f32 = CLAW_WIND;
    while (rise <= CLAW_WIND + CLAW_STRIKE) : (rise += 1.0 / 240.0) {
        d.t = rise;
        d.updateClaw(1.0 / 240.0, v3(0, 0, 3));
        d.pose();
        for (d.clawSeg()) |q| high = mathx.maxF(high, q.y - d.pos.y);
    }
    std.debug.print("  …and the rake tops out at {d:.2} m (his knee is ~0.50, his chest 1.12)\n", .{high});
    try std.testing.expect(high > 0.60);
}

test "IT WALKS ITS LIMBS OFF DISTANCE, and a wandered one goes home" {
    var d = Delver.spawn(mathx.ground(6, 0), 0, 1.0, 0.3);
    d.home = mathx.zero3;
    d.diveCd = 999;
    var fr: u32 = 0;
    while (fr < 60 * 20) : (fr += 1) {
        _ = d.update(1.0 / 60.0, v3(0, 0, 60), 400, .{});
        d.diveCd = 999;
    }
    try std.testing.expect(mathx.distXZ(d.pos, d.home) < HOME_R + 0.6);
    try std.testing.expect(d.gait > 1.0);
}

test "hurt in its own coin: a bolt earths through it, the cold stiffens it, fire smoulders" {
    const bolt = combat.Hit{ .elem = combat.elems(.{ .lightning = 20 }) };
    var v = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    _ = v.hit(bolt);
    try std.testing.expect(v.hp < HP_MAX - 26.0);
    var f = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    _ = f.hit(combat.Hit{ .elem = combat.elems(.{ .fire = 20 }) });
    try std.testing.expect(f.hp > HP_MAX - 17.0);
}

test "THE SURFACE TELL IS A BUILDING SPRAY, NOT A SWELLING DOME — the mound holds and the earth escalates" {
    var d = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
    d.enter(.surge);
    var rates: [3]f32 = undefined;
    for ([_]f32{ 0.1, 0.5, 0.95 }, 0..) |frac, i| {
        d.t = SURGE_DUR * frac;
        d.updateSurge(0);
        try std.testing.expectApproxEqAbs(MOUND_TRAVEL_R, d.moundR, 1e-5);
        try std.testing.expectApproxEqAbs(MOUND_TRAVEL_H, d.moundH, 1e-5);
        rates[i] = lerpF(SURGE_SPRAY_0, SURGE_SPRAY_1, d.surgeK);
    }
    try std.testing.expect(rates[1] > rates[0] * 2.0);
    try std.testing.expect(rates[2] > rates[1] * 3.0);
    try std.testing.expect(rates[2] > SURGE_SPRAY_1 * 0.85);
    std.debug.print("\n  delver surge: spray {d:.0} -> {d:.0} -> {d:.0} clods/s, mound held at r {d:.2}\n", .{ rates[0], rates[1], rates[2], d.moundR });
    d.enterIdle(0.2);
    try std.testing.expectApproxEqAbs(@as(f32, 0), d.surgeK, 1e-6);
}

test "IT IS VICIOUS ON ITS FEET TOO — it runs him down and its stroke comes round again quickly" {
    try std.testing.expect(CHASE_SPEED > heromod.RUN_SPEED);
    try std.testing.expect(CHASE_SPEED < heromod.SPRINT_SPEED);
    try std.testing.expect(WALK_SPEED < heromod.RUN_SPEED);
    // THE STROKE COMES BACK. A claw every 1.9 s off a body that could not close was a punching bag between
    // dives; the whole cycle now fits inside what the dive alone used to cost.
    const cycle = CLAW_WIND + CLAW_STRIKE + CLAW_RECOVER + CLAW_CD;
    try std.testing.expect(cycle < 2.2);
    // …but the TELL is untouched: faster may never mean harder to read (`foe.TELL_MIN`, and the parry).
    try std.testing.expect(CLAW_WIND >= foe.TELL_MIN);
    try std.testing.expect(foe.PARRY_LEAD < CLAW_WIND * 0.5);
    std.debug.print("  delver surface: chases {d:.2} m/s (hero runs {d:.2}, sprints {d:.2}), claw cycle {d:.2} s\n", .{
        CHASE_SPEED, heromod.RUN_SPEED, heromod.SPRINT_SPEED, cycle,
    });
}

test "THE STROKE CROSSES A MAN STANDING IN FRONT — every range inside its own band lands" {
    // **THE BUG THE REACH TEST COULD NOT SEE.** That one measures the tip's RADIAL distance from the body
    // centre and its HEIGHT, and a swipe raked down the creature's own flank satisfies both perfectly. The
    // question it never asked is the only one that matters: does the swept claw actually cross the man it is
    // aimed at. Measured, it did not — at ANY range. The claw ran from x -0.51 to -1.07 and back, so the
    // closest it ever came to a hero on the creature's own facing line was 0.50 m against a 0.34 m blade.
    var dist: f32 = BODY_R + foe.HERO_R;
    var worst: f32 = 0;
    while (dist <= CLAW_BAND + 1e-3) : (dist += 0.05) {
        var d = Delver.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
        const hero = v3(0, 0, dist);
        d.clawCd = 0;
        d.decide(dist);
        try std.testing.expectEqual(State.claw, d.state);
        var landed = false;
        var closest: f32 = 1e9;
        var el: f32 = 0;
        while (el < CLAW_WIND + CLAW_STRIKE + RAKE_WIND + RAKE_STRIKE) : (el += 1.0 / 60.0) {
            if (d.update(1.0 / 60.0, hero, 400, .{}) != null) landed = true;
            for (d.clawSeg()) |q| {
                const lo = v3(hero.x, hero.y + foe.HERO_LOW, hero.z);
                const hi = v3(hero.x, hero.y + foe.HERO_HIGH, hero.z);
                closest = @min(closest, mathx.lenV(mathx.subV(q, mathx.closestOnSegV(q, lo, hi))));
            }
        }
        worst = mathx.maxF(worst, closest);
        try std.testing.expect(landed);
    }
    std.debug.print("\n  delver claw crosses him at every range out to {d:.2} m (worst pass {d:.2} against a {d:.2} m blade)\n", .{ CLAW_BAND, worst, CLAW_SWEEP_R });
    try std.testing.expect(worst <= CLAW_SWEEP_R);

    var d = Delver.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    d.state = .claw;
    var lo: f32 = 1e9;
    var hi: f32 = -1e9;
    var t: f32 = CLAW_WIND;
    while (t <= CLAW_WIND + CLAW_STRIKE) : (t += 1.0 / 240.0) {
        d.t = t;
        d.updateClaw(1.0 / 240.0, v3(0, 0, 3));
        d.pose();
        const tip = d.clawSeg()[1];
        lo = @min(lo, tip.x);
        hi = @max(hi, tip.x);
    }
    std.debug.print("  ...and the tip sweeps x {d:.2} -> {d:.2}, through its own axis\n", .{ lo, hi });
    try std.testing.expect(lo < 0 and hi > 0);
}
