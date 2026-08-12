const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const foe = @import("foe.zig");
const wf = @import("worldfmt.zig");
const sfx = @import("audio.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const scaleM = mathx.scaleM;
const lerpF = mathx.lerpF;
const placeAt = mathx.placeAt;

// A BIG SMOOTH MASS NEEDS A NEARLY-BLACK ALBEDO (AGENTS.md): the hot key plus the gamma lift turns any
// mid-dark value pale on a sunward face, and this thing is one sunward face from the shoulders down. What
// separates the three tones is therefore HUE — cold violet against cold blue — and not value.
const SHROUD = rgba(13, 12, 19, 255); // the cloth itself
const SHROUD_LT = rgba(26, 24, 38, 255); // the ridge of a fold, catching what light there is
const SHROUD_DK = rgba(6, 6, 10, 255); // the gutter beside it
const HOLLOW = rgba(2, 2, 4, 255); // inside the cowl, and it is a HOLE, not a face
const LIMB = rgba(19, 17, 30, 255); // arms — one step warmer than the shroud, so they read off it
const LIMB_DK = rgba(9, 8, 15, 255);
/// THE ONLY THING ON IT THAT IS NOT BLACK, and the whole read at range. Vertex alpha is the EMISSIVE
/// channel here (255 = plainly lit, lower = self-lit), so these two are lit from inside the hood.
const EYE = rgba(126, 92, 206, 70);
const EYE_CORE = rgba(206, 180, 255, 30);

// FX. The MOTE is the world's bonfire-dust and stays the world's; everything else here is this creature's.
const WISP_COL = rgba(96, 118, 176, 210); // what it throws, and what it comes apart into
const WISP_DK = rgba(46, 58, 96, 190);
const DRAIN = rgba(150, 116, 232, 220); // focus leaving the hero — the ONE violet on this creature
const RIFT = rgba(176, 196, 244, 235); // the pale tear a blink leaves behind it

/// ITS OWN STATURE. Nothing here is on the shared 18-bone humanoid scaffold and nothing here should be:
/// it has no legs to walk on, so `hero.legChain` has nothing to solve and `advanceGait` nothing to phase.
pub const H: f32 = 1.92;
/// How far the hem floats off the earth. Small on purpose — a thing hanging a metre up reads as a balloon,
/// and the hem brushing the grass is what says it is HERE rather than in the sky.
const HOVER: f32 = 0.20;
const CORE_Y: f32 = 0.56 * H; // the ROOT joint: the waist of the shroud, everything else hangs off it

pub const AGGRO_R: f32 = 22.0;
const BODY_R: f32 = 0.33;
const HURT_R: f32 = 0.44;
/// Fractions of stature: the hurt sphere's centre, the lock mark, and where the HP bar hangs.
const CENTER_F: f32 = 0.62;
const TOP_F: f32 = 1.00;
/// The reticle's seat in the COWL's own frame: the mouth of the hood, between the two lights, which is the
/// only thing about this creature you can see at range anyway.
const LOCK_AT = v3(0, 0.052 * H, 0.060 * H);

const DRIFT_SPEED: f32 = 2.15; // a shade closes at better than a walk and worse than a run
const CIRCLE_SPEED: f32 = 1.95; // …and orbits a touch slower than it closes
const TURN_RATE: f32 = 7.0;

const HP_MAX: f32 = 46.0;
const POISE_MAX: f32 = 11.0; // a clean light hit flinches it out of anything
const STANCE_MAX: f32 = 26.0;
/// WHAT THE WAND IS FOR. Chaos is the most-resisted column in the game and the shade is the one thing that
/// is WEAK to it: the bolt is the answer to a haunting, and the haunting's own touch takes the focus to
/// cast it with. Fire is no use — there is nothing there to burn — and cold is what it already is.
const RESISTS = combat.resists(.{ .fire = 30, .cold = 65, .chaos = -45 });
pub const SOULS: u32 = 110;

const DEATH_DUR: f32 = 0.55; // it does not fall over; it comes apart
const DISS_DUR: f32 = 0.75;
const SHOVE_DECAY: f32 = 9.0;

/// THE TOUCH. Most of it is the BLUE bar (`combat.Hit.fp`): 14 of a 60-point pool is a cast and a sixth, so
/// two of these and the wand is empty. The red half is deliberately slight — this move is not how it kills
/// you, it is how it takes away the thing that kills IT.
pub const GRASP_HIT = combat.Hit{ .dmg = 7, .poise = 12, .fp = 14 };
/// …AND THE WISP, which is the opposite bargain: it hurts, and it does not touch the focus at all. Sits
/// between an arrow's 16 and a heavy slash's 27, so a pack of these at range is a real clock on you.
pub const WISP_HIT = combat.Hit{ .dmg = 20, .poise = 10 };
pub const WISP_SPEED: f32 = 13.5;

/// One row per move. Every window here clears `foe.TELL_MIN` (0.30) — the law that no attack comes out of
/// nowhere — and the test at the foot of this file pins that rather than trusting the reading.
const Attack = struct {
    windDur: f32,
    strikeDur: f32,
    recoverDur: f32,
    cd: f32,
    minR: f32,
    maxR: f32,
    hit: combat.Hit,
    /// A thrown wisp, or the arms closing on him where it stands.
    hurl: bool,
};

pub const GRASP: usize = 0;
pub const WISP: usize = 1;
const MOVES = [_]Attack{
    .{ .windDur = 0.46, .strikeDur = 0.30, .recoverDur = 0.55, .cd = 2.6, .minR = 0, .maxR = 2.05, .hit = GRASP_HIT, .hurl = false },
    .{ .windDur = 0.68, .strikeDur = 0.18, .recoverDur = 0.62, .cd = 4.6, .minR = 4.2, .maxR = 12.0, .hit = WISP_HIT, .hurl = true },
};
/// A MOVE'S CLOCK, for anything aiming at a beat inside it (`shots.zig`) — the shared shape, off this table.
pub fn moveClock(which: usize) foe.Clock {
    return foe.moveClock(MOVES[@min(which, MOVES.len - 1)]);
}

/// How far the closing arms reach, off its own centre. Past `MOVES[GRASP].maxR` by the hero's own slack, so
/// a hero who walked in on the wind-up is still inside it on the frame the hands meet.
const GRASP_REACH: f32 = MOVES[GRASP].maxR + foe.HERO_REACH;

// THE BLINK — the one thing it does that nothing else in the game does.

/// How close he has to be before it wants out. Inside the grasp's own band on purpose: it does not blink
/// away from a fight it is winning, it blinks away from a SWORD.
const THREAT_R: f32 = 2.4;
const BLINK_CD: f32 = 5.2; // an evade you can spam is a wall (the archer's backstep law)
pub const BLINK_OUT: f32 = 0.18; // fading out where it stood…
pub const BLINK_IN: f32 = 0.24; // …and gathering again where it arrives
/// Where it comes back: this far off the HERO, on a bearing swung round behind him. Outside his sword and
/// inside the wisp's band, so the blink is a repositioning and not a disengage.
const BLINK_R: f32 = 5.0;
const BLINK_TURN_MIN: f32 = 105.0; // …and the bearing is swung at least this far round from where it was,
const BLINK_TURN_MAX: f32 = 165.0; // which is what puts it off the shoulder a guard cannot cover.
/// How long a blow keeps it wanting out. Over `BLINK_CD`, so a hit always buys the blink it is meant to —
/// and finite, so one arrow does not leave a shade blinking on its cooldown for the rest of the map.
const SPOOK_DUR: f32 = 7.0;

/// THE ARMS' OWN ARC. The grasp is both hands closing in FRONT of it, so a hero at its back is not
/// somebody it has hold of — tested on distance alone it landed a blow that the shield's own 65° could
/// never answer and that no frame of the animation showed. A move tests its own band (the ogre's law).
const GRASP_ARC: f32 = 78.0;

const CIRCLE_DUR: f32 = 1.3; // how long one orbit leg lasts before it re-decides
const CIRCLE_BAND: f32 = 3.1; // …and the radius it tries to hold while it does

const IDLE_BOB: f32 = 0.055 * H; // the hover's own breathing
const BOB_HZ: f32 = 0.62;
const LEAN_MAX: f32 = 15.0; // degrees it tips into its travel — from the WAIST, it has no hips to hinge at
/// The hem's LAG, and it is the whole reason the drift reads as a mass and not as a decal sliding about: the
/// tatters trail the body, OVERSHOOT its rest when it stops, and settle back onto it.
const HEM_LAG_RATE: f32 = 5.2;
const HEM_SWING: f32 = 34.0; // degrees of tatter throw at full travel
const HEM_WOBBLE: f32 = 6.0;

const PARTS = 48;

// The rig. Seventeen joints — nine of body and arms, eight of hem — and not one of them a leg.
const N = 17;
const ROOT = 0;
const TORSO = 1;
const COWL = 2;
const SHL = 3;
const ELL = 4;
const WRL = 5;
const SHR = 6;
const ELR = 7;
const WRR = 8;
const HEM_0 = 9;
/// EIGHT TATTERS. Three hanging off a waist are two legs and a tail however they are dressed — what makes
/// a skirt is a RING of them, close enough together that the gaps read as tears in one hem.
const HEM_N = 8;
/// …hung INSIDE the shroud's own hem radius, not on it: the flare has to overhang where they start, or the
/// tops of them show as eight separate things fixed to the underside of a bell.
const HEM_R: f32 = 0.074 * H;
const HEM_Y: f32 = -0.118 * H;

/// The shoulder's half-width. Inside the shroud's own, so the arms hang CLEAR of the mass rather than
/// inside its silhouette — an arm you cannot see is an arm the reach cannot tell you about.
const SH_HALF: f32 = 0.118 * H;
const SH_Y: f32 = 0.190 * H;

/// Each joint's rest offset IN ITS PARENT'S FRAME. `ROOT`'s own is the hover height, which the pose adds.
const REST = blk: {
    var r = [_]rl.Vector3{mathx.zero3} ** N;
    r[ROOT] = v3(0, 0, 0);
    r[TORSO] = v3(0, 0, 0); // the shroud is authored about the waist
    r[COWL] = v3(0, 0.300 * H, 0);
    r[SHL] = v3(SH_HALF, SH_Y, 0);
    r[ELL] = v3(0, -0.155 * H, 0);
    r[WRL] = v3(0, -0.145 * H, 0);
    r[SHR] = v3(-SH_HALF, SH_Y, 0);
    r[ELR] = v3(0, -0.155 * H, 0);
    r[WRR] = v3(0, -0.145 * H, 0);
    for (0..HEM_N) |i| {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / HEM_N;
        r[HEM_0 + i] = v3(@cos(a) * HEM_R, HEM_Y, @sin(a) * HEM_R * 0.86);
    }
    break :blk r;
};

const State = enum { idle, drift, circle, wind, strike, recover, blinkout, blinkin, stunlight, stunheavy, dead };

/// PURE DECISION — a function of range and cooldowns, so the bands are testable without a world.
const Choice = enum { hold, close, circle, grasp, wisp };
fn classify(dist: f32, graspReady: bool, wispReady: bool) Choice {
    if (dist > AGGRO_R) return .hold;
    if (dist <= MOVES[GRASP].maxR) return if (graspReady) .grasp else .circle;
    if (dist >= MOVES[WISP].minR and dist <= MOVES[WISP].maxR and wispReady) return .wisp;
    if (dist > CIRCLE_BAND) return .close;
    return .circle;
}

/// …AND THE BLINK'S OWN GATE, the same shape. `spooked` is what a landed blow leaves behind: it does not
/// teleport out of the stagger itself (that would erase the punish window the flinch exists to open), it
/// teleports the moment the flinch lets go — which reads as the thing deciding it has had enough.
fn wantsBlink(dist: f32, cd: f32, spooked: bool, s: State, rooted: bool) bool {
    if (cd > 0 or rooted) return false; // ROOTED: a blink LEAVES THE EARTH, and roots deny that outright
    if (!spooked and dist > THREAT_R) return false;
    return switch (s) {
        .idle, .drift, .circle, .recover => true,
        .wind, .strike, .blinkout, .blinkin, .stunlight, .stunheavy, .dead => false,
    };
}

/// What one frame of this creature did that the world outside it has to answer for.
pub const Act = union(enum) {
    none,
    /// It let a wisp go, from this point.
    hurl: rl.Vector3,
    /// Its hands closed on him.
    grasp: combat.Hit,
};

pub const Model = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        var mat = rl.loadMaterialDefault() catch @panic("shade material");
        mat.shader = shader;
        return .{ .mesh = buildMeshes(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, s: *const Shade) void {
        for (0..N) |i| rl.drawMesh(self.mesh[i], self.mat, s.xf[i]);
    }
};

pub const Shade = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// THE WAND'S ROOTS, when they have hold of it — stamped from outside, like the leash's eyes.
    root: combat.Root = .{},
    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    atk: usize = GRASP,
    dealt: bool = false, // one blow per strike, latched
    cds: [MOVES.len]f32 = [_]f32{0} ** MOVES.len,
    blinkCd: f32 = 0,
    /// A LANDED BLOW ARMS IT, the next choose site spends it — see `wantsBlink`. A COUNTDOWN and not a
    /// latch, `Leash.rouseLeft`'s own rule: a bare bool is never cleared by anything but a blink, so one
    /// arrow into a shade that then walks home leaves it teleporting on its cooldown forever.
    spookLeft: f32 = 0,
    /// Where the current blink is putting it down. Committed at `blinkout` so the arrival cannot chase a
    /// hero who moved during the fade, which would read as a lunge rather than as a place it went to.
    blinkTo: rl.Vector3 = mathx.zero3,
    driftDir: rl.Vector3 = mathx.zero3,
    orbitSign: f32 = 1,

    // posture channels, resolved by the state and read by pose()
    lean: f32 = 0,
    reach: f32 = 0, // 0 = arms furled at the chest, 1 = thrown out at him
    gather: f32 = 0, // the wisp balled up between the hands
    hemLag: rl.Vector3 = mathx.zero3, // world XZ the tatters are trailing by
    /// 0 = solid, 1 = gone. Drives the whole rig's scale AND the dissipation, so a blink and a death are the
    /// same channel — there is only one way this thing leaves a place.
    thin: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    /// WHO IT IS FIGHTING (`foe.Threat`) — embedded here and stamped by the game, `Leash`'s own law.
    threat: foe.Threat = .{},
    /// …AND THE WAY ROUND WHAT IS IN FRONT OF IT (`foe.Nav`), stamped the same way and for the same reason. It
    /// is `airborne()` through a blink, which is exactly when the stamp is skipped: nothing in the middle of a
    /// blink is walking anywhere.
    nav: foe.Nav = .{},
    gone: bool = false,

    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    xf: [N]rl.Matrix = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Shade {
        var s = Shade{ .pos = home, .home = home, .facing = faceYaw, .scale = scale, .seed = seed };
        s.fxRng = foe.fxStream(seed, 7331.0, 0x5EED);
        s.orbitSign = if (seed < 0.5) 1 else -1;
        s.cds[WISP] = seed * MOVES[WISP].cd; // stagger a haunting, or three wisps leave on one frame
        s.pose();
        return s;
    }

    // EVERY WORLD POINT IS MEASURED OFF `pos.y` PLUS THE HOVER, so a shade over a bank keeps its own head.
    /// What it is holding itself off the ground by — the `lift` every other creature passes a hop or a leap
    /// as, which for this one is simply always there.
    fn hover(self: *const Shade) f32 {
        return HOVER * self.scale;
    }
    pub fn centerWorld(self: *const Shade) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H, self.scale, self.hover());
    }
    /// THE MARK RIDES THE COWL — and this creature is why the rule is worth having twice over: it BOBS on its
    /// hover the whole time it is alive, and it THINS to nothing through a blink. A height off the ground held
    /// the reticle dead still over something visibly moving, and in empty air while the body was not there.
    pub fn lockPoint(self: *const Shade) rl.Vector3 {
        return foe.markOn(self.xf[COWL], LOCK_AT);
    }
    pub fn topWorld(self: *const Shade) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * H, self.scale, self.hover());
    }
    pub fn hurtRadius(self: *const Shade) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Shade) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Shade) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Shade) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Shade) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    /// HALFWAY THROUGH A BLINK IT IS NOWHERE — which is what exempts the jump from the terrain gate
    /// (`game.gateTerrain`) and from being shouldered. A step it never took cannot be walked back.
    pub fn airborne(self: *const Shade) bool {
        return self.state == .blinkout or self.state == .blinkin;
    }
    pub fn flashFrac(self: *const Shade) f32 {
        return foe.flashFrac(self.flash);
    }

    /// Where a thrown wisp leaves from: the hands, held together in front of the cowl.
    pub fn wispWorld(self: *const Shade) rl.Vector3 {
        const l = rl.math.vector3Transform(mathx.zero3, self.xf[WRL]);
        const r = rl.math.vector3Transform(mathx.zero3, self.xf[WRR]);
        return mathx.lerpV(l, r, 0.5);
    }

    fn move(self: *const Shade) Attack {
        return MOVES[@min(self.atk, MOVES.len - 1)];
    }

    pub fn update(self: *Shade, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) Act {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return .none;
        }
        self.justDied = false; // one-frame flag, reset at the TOP (the foe contract's own rule)
        // THE ROOTS HAVE ITS FEET — such as they are. The drift is given back as a post-step gate and the
        // grasp still closes; the BLINK is the one thing refused outright, at the choose site below.
        const grip = foe.grip(&self.root, &self.vit, dt, self.pos);
        // Airborne is half a blink: the arrival write must not be snapped back to the departure point,
        // leaving the rift flash five metres from the body (a leap in the air finishes its arc).
        defer if (!self.airborne()) grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        self.flash = mathx.maxF(0, self.flash - dt);
        for (&self.cds) |*c| c.* = mathx.maxF(0, c.* - dt);
        self.blinkCd = mathx.maxF(0, self.blinkCd - dt);
        self.spookLeft = mathx.maxF(0, self.spookLeft - dt);
        foe.tickLeash(&self.leash, dt, self.pos, self.home, hero, AGGRO_R);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);
        foe.tickParticles(&self.parts, dt, self.pos.y);

        var act: Act = .none;
        // WHERE THE WISP LEAVES FROM IS READ AFTER THE POSE, not at the release: `reach` snaps from the wind's
        // 0.30 to 1.0 on this exact frame, swinging the shoulder through 94 degrees — so `wispWorld()` taken
        // here answers with the hands still furled at the chest, a metre behind where the frame shows them.
        var hurling = false;
        const was = self.pos;
        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);

        switch (self.state) {
            .idle => {
                self.easeRest(dt);
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                self.decide(d, hero);
            },
            .drift => {
                self.easeRest(dt);
                self.faceToward(hero, dt);
                // …ROUND WHAT IS IN THE WAY (`foe.Nav`), at the STEP: it drifts on a committed vector with its
                // cowl still turned on him. Only the drift — the CIRCLE is an orbit at a band it re-aims every
                // frame, and bending that would be steering the shape of the orbit itself.
                mathx.stepXZ(&self.pos, self.nav.along(self.driftDir), DRIFT_SPEED * dt, bounds);
                self.decide(d, hero);
            },
            .circle => {
                self.easeRest(dt);
                self.faceToward(hero, dt);
                mathx.stepXZ(&self.pos, self.driftDir, CIRCLE_SPEED * dt, bounds);
                if (self.t >= CIRCLE_DUR) self.decide(d, hero) else self.aimOrbit(hero);
            },
            .wind => {
                const a = self.move();
                self.faceToward(hero, dt);
                const u = mathx.clampF(self.t / a.windDur, 0, 1);
                if (a.hurl) {
                    self.gather = mathx.smoothstep(0.15, 1.0, u);
                    self.reach = mathx.approach(self.reach, 0.30, dt * 3.0);
                } else {
                    // THE ARMS GO WIDE BEFORE THEY COME IN. Straight to the closing pose there is no tell
                    // at all — the whole move is one frame of hands already on you.
                    self.reach = mathx.approach(self.reach, -0.55, dt * 5.0);
                }
                self.lean = mathx.approach(self.lean, if (a.hurl) -6.0 else -9.0, dt * 60.0);
                if (self.t >= a.windDur) self.enter(.strike);
            },
            .strike => {
                const a = self.move();
                if (a.hurl) {
                    if (!self.dealt) {
                        self.dealt = true;
                        self.gather = 0;
                        self.reach = 1.0;
                        self.leash.noteCombat();
                        sfx.world(.shade_wisp, self.pos);
                        hurling = true;
                    }
                    self.reach = mathx.approach(self.reach, 0.55, dt * 4.0);
                } else {
                    const u = mathx.clampF(self.t / a.strikeDur, 0, 1);
                    self.reach = lerpF(-0.55, 1.0, foe.swingCurve(u));
                    if (!self.dealt and u >= 0.42 and self.holds(hero)) {
                        self.dealt = true;
                        self.leash.noteCombat();
                        sfx.world(.shade_touch, self.pos);
                        self.drainMotes(hero);
                        act = .{ .grasp = a.hit };
                    }
                }
                self.lean = mathx.approach(self.lean, 7.0, dt * 90.0);
                if (self.t >= a.strikeDur) self.enter(.recover);
            },
            .recover => {
                self.easeRest(dt);
                self.faceToward(hero, dt);
                if (self.t >= self.move().recoverDur) self.decide(d, hero);
            },
            .blinkout => {
                self.thin = mathx.clampF(self.t / BLINK_OUT, 0, 1);
                self.easeRest(dt);
                if (self.t >= BLINK_OUT) {
                    self.pos.x = self.blinkTo.x;
                    self.pos.z = self.blinkTo.z;
                    self.rift();
                    self.enter(.blinkin);
                }
            },
            .blinkin => {
                self.thin = 1.0 - mathx.clampF(self.t / BLINK_IN, 0, 1);
                self.easeRest(dt);
                self.faceToward(hero, dt);
                if (self.t >= BLINK_IN) {
                    self.thin = 0;
                    self.decide(foe.senseHero(&self.leash, self.pos, hero, AGGRO_R), hero);
                }
            },
            .stunlight => {
                self.easeRest(dt);
                if (self.t >= combat.FOE_LIGHT_STUN_DUR) self.enter(.idle);
            },
            .stunheavy => {
                self.easeRest(dt);
                if (self.t >= combat.FOE_HEAVY_STUN_DUR) self.enter(.idle);
            },
            // THE ONE BODY THAT DOES NOT DISSIPATE (`foe.dissipate`, which every other death runs through). It
            // has no collapse to be still after and nothing to shed: it does not fall over, it comes APART —
            // `thin` from the first frame, and motes off a thing made of nothing is a substance it never had.
            .dead => {
                self.reach = mathx.approach(self.reach, -0.2, dt * 2.0);
                self.thin = mathx.smoothstep(0, DEATH_DUR + DISS_DUR, self.t);
                if (self.t >= DEATH_DUR + DISS_DUR) self.gone = true;
            },
        }

        // THE BLINK IS ASKED LAST, off the state the frame settled into. Asked before the machine instead it
        // fires on the frame a stun ENDS and eats its own arrival, which reads as a stutter and not a jump.
        if (wantsBlink(d, self.blinkCd, self.spookLeft > 0, self.state, !foe.canLeap(&self.root))) self.enterBlink(hero);

        // …and the hem is told what it TRAVELLED, which a jump is not: fed the arrival's five metres in one
        // frame the tatters pin at full swing for most of a second after the thing has stopped moving.
        self.trailHem(if (self.airborne()) self.pos else was, dt);
        self.pose();
        if (hurling) act = .{ .hurl = self.wispWorld() }; // …off the hands the frame actually DRAWS
        self.tryHit(blade); // the hero's blade AFTER the machine, so a kill sets justDied for THIS frame
        return act;
    }

    /// How far the closing hands actually reach in world units — its own scale, since a big one has long arms.
    pub fn graspReach(self: *const Shade) f32 {
        return GRASP_REACH * self.scale;
    }

    /// Is he inside the closing arms — BOTH near enough and in front of them?
    pub fn holds(self: *const Shade, hero: rl.Vector3) bool {
        if (mathx.distXZ(self.pos, hero) > self.graspReach()) return false;
        const to = mathx.dirXZ(self.pos, hero);
        if (mathx.lenXZ(to) < 1e-4) return true; // standing inside it: no bearing to be wrong about
        return @abs(mathx.degrees(mathx.wrapPi(mathx.headingXZ(to) - self.facing))) <= GRASP_ARC;
    }

    fn faceToward(self: *Shade, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }

    /// WHERE IT IS TRYING TO GO, or null when it is not going anywhere (`game.markWay`) — read off the drift's
    /// own committed vector, which is the whole errand whether that is closing on him or going home.
    pub fn navWant(self: *const Shade, hero: rl.Vector3) ?rl.Vector3 {
        _ = hero;
        if (self.state != .drift) return null;
        return mathx.addV(self.pos, self.driftDir);
    }

    fn easeRest(self: *Shade, dt: f32) void {
        self.reach = mathx.approach(self.reach, 0, dt * 3.4);
        self.gather = mathx.approach(self.gather, 0, dt * 4.0);
        self.lean = mathx.approach(self.lean, 0, dt * 40.0);
    }

    fn enter(self: *Shade, s: State) void {
        self.state = s;
        self.t = 0;
        self.dealt = false;
    }

    fn decide(self: *Shade, dist: f32, hero: rl.Vector3) void {
        if (self.leash.goingHome()) {
            self.driftDir = mathx.dirXZ(self.pos, self.home);
            return self.enter(.drift);
        }
        switch (classify(dist, self.cds[GRASP] <= 0, self.cds[WISP] <= 0)) {
            .hold => self.enter(.idle),
            .close => {
                self.driftDir = mathx.dirXZ(self.pos, hero);
                self.enter(.drift);
            },
            .circle => {
                self.aimOrbit(hero);
                self.enter(.circle);
            },
            .grasp => self.begin(GRASP),
            .wisp => self.begin(WISP),
        }
    }

    fn begin(self: *Shade, which: usize) void {
        self.atk = which;
        self.cds[which] = MOVES[which].cd;
        self.enter(.wind);
        sfx.world(if (MOVES[which].hurl) .shade_gather else .shade_reach, self.pos);
    }

    /// The orbit leg: tangent about the hero, plus whatever it owes toward or away from the band. Solved
    /// every frame of the circle rather than committed at the top of it, or a hero who walks two metres
    /// leaves it orbiting a place he is not standing in.
    fn aimOrbit(self: *Shade, hero: rl.Vector3) void {
        const out = mathx.dirXZ(hero, self.pos);
        if (mathx.lenXZ(out) < 1e-3) {
            self.driftDir = mathx.headingDir(self.facing);
            return;
        }
        const tangent = v3(-out.z * self.orbitSign, 0, out.x * self.orbitSign);
        const err = mathx.distXZ(self.pos, hero) - CIRCLE_BAND;
        const pull = mathx.clampF(-err * 0.6, -1, 1);
        self.driftDir = mathx.normV(v3(tangent.x + out.x * pull, 0, tangent.z + out.z * pull));
    }

    /// COMMITTED THE MOMENT IT STARTS FADING. The arrival bearing is swung round from where it stands now,
    /// so it comes back off the shoulder the hero has just turned away from — which is the whole point of
    /// the move, and it is got without the creature ever reaching out for the hero's facing.
    fn enterBlink(self: *Shade, hero: rl.Vector3) void {
        var out = mathx.dirXZ(hero, self.pos);
        if (mathx.lenXZ(out) < 1e-3) out = mathx.headingDir(self.facing);
        const swing = mathx.radians(lerpF(BLINK_TURN_MIN, BLINK_TURN_MAX, self.fxRng.float())) * self.orbitSign;
        const yaw = mathx.headingXZ(out) + swing;
        const dir = mathx.headingDir(yaw);
        self.blinkTo = v3(hero.x + dir.x * BLINK_R, self.pos.y, hero.z + dir.z * BLINK_R);
        self.orbitSign = -self.orbitSign; // …and it comes back round the OTHER way next time
        self.blinkCd = BLINK_CD;
        self.spookLeft = 0;
        self.rift();
        sfx.world(.shade_blink, self.pos);
        self.enter(.blinkout);
    }

    fn enterStun(self: *Shade, s: State) void {
        self.state = s;
        self.t = 0;
        self.dealt = false;
        self.gather = 0;
        self.thin = 0;
    }

    fn enterDeath(self: *Shade) void {
        if (self.state == .dead) return;
        self.state = .dead;
        self.t = 0;
        self.justDied = true;
        self.unravel();
    }

    pub fn tryHit(self: *Shade, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        self.spookLeft = SPOOK_DUR; // …and it will go the moment it is done flinching (`wantsBlink`)
        _ = foe.wounded(self, s, blade, .{ .light = 0.95, .heavy = 1.5 });
        self.tornMotes(s.contact, s.dir);
        sfx.world(.shade_hurt, self.pos);
        switch (s.reaction) {
            .death => {
                sfx.world(.shade_die, self.pos);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    // Debug hooks for the --shot harness (force one pose in isolation).
    pub fn debugMove(self: *Shade, which: usize) void {
        self.atk = @min(which, MOVES.len - 1);
        self.enter(.wind);
    }
    pub fn debugBlink(self: *Shade, hero: rl.Vector3) void {
        self.blinkCd = 0;
        self.enterBlink(hero);
    }
    pub fn debugStagger(self: *Shade, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Shade) void {
        self.enterDeath();
    }


    fn emit(self: *Shade, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
        foe.emitParticle(&self.parts, &self.fxHead, p, vel, life, r0, r1, col, grav);
    }

    /// THE TEAR A BLINK LEAVES, at both ends of it. Motes that fall INWARD (negative gravity is up here, so
    /// a positive one on a rising spark is what makes it collapse) — the place closing after it.
    fn rift(self: *Shade) void {
        const c = self.centerWorld();
        var i: i32 = 0;
        while (i < 14) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(1.6, 3.4) * self.scale;
            self.emit(
                v3(c.x, c.y + self.fxRng.range(-0.35, 0.45) * self.scale, c.z),
                v3(mathx.cosf(a) * sp, self.fxRng.range(-0.4, 1.6), mathx.sinf(a) * sp),
                self.fxRng.range(0.16, 0.30),
                self.fxRng.range(0.032, 0.062) * self.scale,
                0.006,
                if (self.fxRng.float() < 0.4) RIFT else WISP_COL,
                1.2,
            );
        }
    }

    /// WHAT THE TOUCH TAKES, thrown from the HERO back toward the hands: the only picture of a drain that
    /// reads at all is the stuff going the wrong way.
    fn drainMotes(self: *Shade, hero: rl.Vector3) void {
        const to = self.centerWorld();
        var i: i32 = 0;
        while (i < 12) : (i += 1) {
            const from = v3(
                hero.x + self.fxRng.range(-0.3, 0.3),
                hero.y + self.fxRng.range(0.5, 1.5),
                hero.z + self.fxRng.range(-0.3, 0.3),
            );
            const d = mathx.subV(to, from);
            const life = self.fxRng.range(0.22, 0.34);
            self.emit(
                from,
                mathx.scaleV(d, 1.0 / life),
                life,
                // SIZED BETWEEN TWO FAILURES (AGENTS.md): at 0.09 the stream was a row of beach balls with
                // the arm that caused it hidden behind them. Judged against the CREATURE, not the hero.
                self.fxRng.range(0.026, 0.046),
                0.008,
                DRAIN,
                -0.6, // …and they RISE as they go, or the drain reads as something spilling on the floor
            );
        }
    }

    fn tornMotes(self: *Shade, at: rl.Vector3, dir: rl.Vector3) void {
        var i: i32 = 0;
        while (i < 10) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.5, 1.9);
            self.emit(
                at,
                v3(dir.x * sp + mathx.cosf(a) * 0.7, self.fxRng.range(0.3, 1.8), dir.z * sp + mathx.sinf(a) * 0.7),
                self.fxRng.range(0.26, 0.46),
                self.fxRng.range(0.04, 0.085) * self.scale,
                0.01,
                WISP_DK,
                2.4,
            );
        }
    }

    /// IT DOES NOT FALL OVER. There is nothing in it to fall — the shroud simply lets go of its own shape.
    fn unravel(self: *Shade) void {
        const c = self.centerWorld();
        var i: i32 = 0;
        while (i < 26) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.4, 2.2) * self.scale;
            self.emit(
                v3(c.x, c.y + self.fxRng.range(-0.7, 0.6) * self.scale, c.z),
                v3(mathx.cosf(a) * sp, self.fxRng.range(0.2, 2.4), mathx.sinf(a) * sp),
                self.fxRng.range(0.5, 1.05),
                self.fxRng.range(0.07, 0.15) * self.scale,
                0.01,
                if (self.fxRng.float() < 0.3) foe.MOTE else WISP_COL,
                1.1,
            );
        }
    }

    pub fn drawFx(self: *const Shade) void {
        foe.drawParticles(&self.parts);
    }
    pub fn draw(self: *const Shade, model: *const Model) void {
        model.draw(self);
    }


    /// The hem's trail, updated off the distance actually covered: a mass in motion OVERSHOOTS its rest and
    /// settles back onto it, so this is an eased lag and never the frame's travel read straight.
    fn trailHem(self: *Shade, was: rl.Vector3, dt: f32) void {
        const step = mathx.subV(self.pos, was);
        const want = if (dt > 1e-5) mathx.scaleV(v3(step.x, 0, step.z), -1.0 / dt) else mathx.zero3;
        self.hemLag = mathx.approachV(self.hemLag, want, HEM_LAG_RATE * dt * DRIFT_SPEED);
    }

    pub fn pose(self: *Shade) void {
        // ONE CHANNEL FOR EVERY WAY IT LEAVES: a blink and a death both thin it out, so `thin` shrinks the
        // whole rig rather than each state carrying its own vanish.
        const fs = self.scale * (1.0 - 0.82 * self.thin);
        const facingDeg = mathx.degrees(self.facing);
        // The bob's RATE is dealt as well as its phase — a haunting of three phase-offset copies of one
        // clock still beats in step every few seconds, and three clocks that never agree do not.
        const bob = IDLE_BOB * mathx.sinf(self.elapsed * BOB_HZ * (1.0 + 0.16 * (self.seed - 0.5)) * std.math.tau + self.seed * 6.28);
        // …and a DEAD one settles as it goes, where a blinking one holds its height: one is coming apart on
        // the spot, the other is somewhere else already.
        const sink = if (self.state == .dead) -0.30 * self.scale * self.thin else 0;
        const leanDeg = mathx.clampF(self.lean, -LEAN_MAX, LEAN_MAX);

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul(
            tr(0, (CORE_Y + bob) * fs + HOVER * self.scale + sink, 0),
            mul(ry(facingDeg), tr(self.pos.x, self.pos.y, self.pos.z)),
        ));

        // THE LEAN LIVES IN THE TRUNK, not at the root: there are no legs to be rotated out from under it,
        // but the hem tatters hang off the ROOT and a root pitch would swing them forward with the chest —
        // which is the one thing a trailing hem must never do.
        wx[TORSO] = placeAt(REST[TORSO], mul(rx(leanDeg), rz(mathx.sinf(self.elapsed * (0.41 + 0.07 * (self.seed - 0.5)) + self.seed * 7.7) * 2.4)), wx[ROOT]);
        wx[COWL] = placeAt(REST[COWL], mul(
            rx(-leanDeg * 0.35 + 4.0 * self.reach),
            ry(mathx.sinf(self.elapsed * 0.33 + self.seed * 4.0) * 5.0),
        ), wx[TORSO]);

        self.poseArm(&wx, SHL, ELL, WRL, 1.0);
        self.poseArm(&wx, SHR, ELR, WRR, -1.0);
        self.poseHem(&wx);
        self.xf = wx;
    }

    /// Both arms, mirrored by `side`. The GRASP's reach is a STRETCH as much as a swing — the shoulder's own
    /// scale runs down the whole chain, so the limb lengthens toward him rather than merely pointing.
    fn poseArm(self: *Shade, wx: *[N]rl.Matrix, sh: usize, el: usize, wr: usize, side: f32) void {
        const r = self.reach;
        const out = mathx.maxF(r, 0);
        const furl = mathx.maxF(-r, 0);
        // Furled: taken WIDE and back, which is the tell. Thrown: shoulders up and forward, elbows opening.
        const shX = lerpF(20.0, -74.0, out) + 16.0 * furl + 6.0 * self.gather;
        // POSITIVE `rz` ABDUCTS the +X arm — the sign that keeps the limbs OUTSIDE the shroud's silhouette.
        // Negative here and both arms cross into the mass, where nothing about the reach can be read.
        const shZ = side * (lerpF(30.0, 11.0, out) + 34.0 * furl);
        const elX = lerpF(52.0, 9.0, out) + 30.0 * furl - 18.0 * self.gather;
        // 1 at rest, longer as it reaches: what makes a shade's arm read as smoke and not as a limb.
        const stretch = 1.0 + 0.85 * out;
        wx[sh] = placeAt(REST[sh], mul(scaleM(1, stretch, 1), mul(rx(shX), rz(shZ))), wx[TORSO]);
        wx[el] = placeAt(REST[el], rx(elX), wx[sh]);
        // …and the HAND gives back exactly what the chain stretched, or the fingers come out a foot long.
        wx[wr] = placeAt(REST[wr], mul(scaleM(1, 1.0 / stretch, 1), rz(side * -12.0 * out)), wx[el]);
    }

    /// THE TATTERS, and they are the whole of what says this thing is moving. Each swings by the eased lag
    /// (so they trail the drift and settle back through it), on its own phase, and the phases are stepped
    /// rather than shared — three tongues peaking on one frame is one welded skirt.
    fn poseHem(self: *Shade, wx: *[N]rl.Matrix) void {
        const lagX = mathx.clampF(self.hemLag.x, -1.4, 1.4);
        const lagZ = mathx.clampF(self.hemLag.z, -1.4, 1.4);
        // The lag is in WORLD XZ and the tatters hang in the ROOT's frame, which is already turned by the
        // facing — so it has to be turned back, or a shade drifting north swings its hem east.
        const c = mathx.cosf(-self.facing);
        const s = mathx.sinf(-self.facing);
        const localX = lagX * c + lagZ * s;
        const localZ = -lagX * s + lagZ * c;
        for (0..HEM_N) |i| {
            const b = HEM_0 + i;
            const fi: f32 = @floatFromInt(i);
            const phase = self.elapsed * (0.79 + 0.13 * fi) + self.seed * 5.0 + fi * 1.7;
            const wobble = mathx.sinf(phase) * HEM_WOBBLE;
            wx[b] = placeAt(REST[b], mul(
                rx(localZ * HEM_SWING + wobble),
                rz(-localX * HEM_SWING + mathx.cosf(phase * 0.7) * HEM_WOBBLE * 0.6),
            ), wx[ROOT]);
        }
    }
};

const CAP = wf.MAX_PER_KIND;

/// A HAUNTING — where they stand is the MAP's business (`foe: shade …` records).
pub const Haunt = struct {
    model: Model,
    shades: [CAP]Shade = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Haunt {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Haunt) []Shade {
        return self.shades[0..self.n];
    }
    pub fn liveConst(self: *const Haunt) []const Shade {
        return self.shades[0..self.n];
    }
    pub fn reset(self: *Haunt, m: *const wf.Map) void {
        foe.resetGroup(Shade, &self.shades, &self.n, m, .shade);
    }
    pub fn setShader(self: *Haunt, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn draw(self: *const Haunt, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Haunt) void {
        for (self.liveConst()) |*s| s.drawFx();
    }

    pub fn update(
        self: *Haunt,
        dt: f32,
        hero: rl.Vector3,
        bounds: f32,
        blade: foe.Blade,
        ctx: anytype,
        comptime hurl: fn (@TypeOf(ctx), rl.Vector3) void,
    ) ?foe.Blow {
        var blow: ?foe.Blow = null;
        for (self.live()) |*s| {
            switch (s.update(dt, s.threat.aim(hero), bounds, blade)) {
                .none => {},
                .hurl => |from| hurl(ctx, from),
                .grasp => |h| foe.worseBlow(&blow, h, s.pos, s.threat.on),
            }
        }
        return blow;
    }

    // The shared group roll-ups (foe.zig) — one-line delegates, the standard's own rule.
    pub fn pierce(self: *Haunt, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Haunt) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Haunt) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Haunt) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Haunt) u32 {
        return foe.aliveCount(self.liveConst());
    }
};


fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = emptyMesh();
    mesh[TORSO] = shroudMesh();
    mesh[COWL] = cowlMesh();
    mesh[SHL] = armMesh(311);
    mesh[ELL] = forearmMesh(312);
    mesh[WRL] = handMesh(1.0, 313);
    mesh[SHR] = armMesh(314);
    mesh[ELR] = forearmMesh(315);
    mesh[WRR] = handMesh(-1.0, 316);
    // NO TWO THE SAME LENGTH, and the ring of them is where the wabi-sabi lives on this creature: one mesh
    // is shared by every instance, so the variation cannot be BETWEEN shades — it is between the tatters.
    const len = [HEM_N]f32{ 0.40, 0.29, 0.43, 0.34, 0.38, 0.26, 0.42, 0.31 };
    for (0..HEM_N) |i| {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / HEM_N;
        mesh[HEM_0 + i] = tatterMesh(len[i], a, 321 + @as(u64, i));
    }
    return mesh;
}

/// The ROOT carries no geometry of its own, and there is no such thing as an empty `rl.Mesh` to put there —
/// so it gets one speck, sunk inside the shroud where nothing can see it.
fn emptyMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addBlob(v3(0, 0, 0), v3(0.004, 0.004, 0.004), 3, 4, SHROUD_DK);
    return b.toMesh();
}

/// THE SHROUD — ONE MASS, and everything about how it is built serves that. Eleven rings, each twice as tall
/// as the gap to the next so they fuse instead of stacking, on a smooth taper with a waist: a straight cone
/// is a traffic bollard and a stepped one is a stack of tyres. AND IT IS ALL ONE TONE — alternating the three
/// shroud values ring by ring banded it like a barber's pole. The other two live on the FOLDS.
/// The shroud's profile: four stations, each a height in stature and the half-width there. Broad at the
/// shoulders, NIPPED at the waist, flaring under it — the three moves that separate a robed figure from a
/// tapered tube. Written down once and read by the meshing, the folds and the hem's overhang alike.
const PROF = [_][2]f32{
    .{ 0.250, 0.084 }, // the throat, where the cowl comes out
    .{ 0.208, 0.128 }, // the shoulders
    .{ 0.108, 0.112 },
    .{ 0.006, 0.080 }, // the waist
};
const HEM_FLARE: f32 = 0.150; // …and the skirt's own half-width, on a squashed dome centred here:
const HEM_DOME_Y: f32 = -0.078;

fn shroudMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4409);
    b.setMat(.cloth);
    // FOUR TAPERED RUNS, EACH PICKING UP THE LAST ONE'S RADIUS. Eleven overlapping blobs read as eleven
    // blobs however dark they are: every one of them puts its own equator proud of its neighbours', and a
    // column of equators is a corrugation. A capsule whose `ra` IS the previous `rb` has no seam to show.
    var i: usize = 0;
    while (i + 1 < PROF.len) : (i += 1) {
        b.addCapsule(
            v3(rng.range(-0.006, 0.006) * H, PROF[i][0] * H, rng.range(-0.005, 0.005) * H),
            v3(rng.range(-0.006, 0.006) * H, PROF[i + 1][0] * H, rng.range(-0.005, 0.005) * H),
            PROF[i][1] * H,
            PROF[i + 1][1] * H,
            13,
            SHROUD,
        );
    }
    // THE SKIRT: one squashed dome flaring off the waist, wide enough to OVERHANG where the tatters start.
    b.addBlob(v3(0, HEM_DOME_Y * H, 0), v3(HEM_FLARE * H, 0.098 * H, HEM_FLARE * H * 0.86), 6, 13, SHROUD);
    // THE FOLDS: vertical ridges a couple of per cent of the mass's radius proud of it (RELIEF IS SUBTLE),
    // sunk most of the way back in. These are the only place the other two shroud values appear.
    var f: usize = 0;
    while (f < 10) : (f += 1) {
        const a = rng.range(0, std.math.tau);
        // ABOVE THE WAIST ONLY. `shroudHalf` interpolates the hem as a CONE where the mesh puts a squashed
        // dome, so a fold crossing the waist tracks a radius the surface never has and stands off it as a
        // free-floating strut — which is what the side-on shot came back showing.
        const y0 = rng.range(0.055, 0.185) * H;
        const y1 = mathx.maxF(y0 - rng.range(0.09, 0.20) * H, PROF[PROF.len - 1][0] * H + 0.004 * H);
        const cx = mathx.cosf(a);
        const cz = mathx.sinf(a) * 0.86;
        // …tracked against the taper at BOTH ends, or a ridge authored at one radius floats off the waist.
        const r0 = 0.96 * shroudHalf(y0 / H) * H;
        const r1 = 0.96 * shroudHalf(y1 / H) * H;
        b.addCapsule(
            v3(cx * r0, y0, cz * r0),
            v3(cx * r1, y1, cz * r1),
            0.0080 * H * rng.range(0.8, 1.25),
            0.0055 * H,
            5,
            if (rng.float() < 0.5) SHROUD_LT else SHROUD_DK,
        );
    }
    // The cloth gathered at the throat, where the cowl comes out of it — a break, not a seam.
    b.addBlob(v3(0, 0.244 * H, -0.006 * H), v3(0.080 * H, 0.036 * H, 0.072 * H), 5, 11, SHROUD_LT);
    return b.toMesh();
}

/// The shroud's half-width at height `y` (in stature): the profile above, interpolated, with the hem's own
/// dome taking over under the waist. One answer, so a fold cannot sit beside the mass it belongs to.
fn shroudHalf(y: f32) f32 {
    if (y <= PROF[PROF.len - 1][0]) {
        const t = mathx.clampF((PROF[PROF.len - 1][0] - y) / (PROF[PROF.len - 1][0] - HEM_DOME_Y), 0, 1);
        return lerpF(PROF[PROF.len - 1][1], HEM_FLARE, t);
    }
    var i: usize = 0;
    while (i + 1 < PROF.len) : (i += 1) {
        if (y <= PROF[i][0] and y >= PROF[i + 1][0]) {
            const t = (PROF[i][0] - y) / (PROF[i][0] - PROF[i + 1][0]);
            return lerpF(PROF[i][1], PROF[i + 1][1], t);
        }
    }
    return PROF[0][1];
}

/// THE COWL, and the read is the HOLE in it. The hood is a blob; the hollow is a second, darker blob sunk
/// into its front; the two eyes hang inside that, self-lit off the vertex alpha.
fn cowlMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(9127);
    b.setMat(.cloth);
    // The hood: taller than it is wide, tipped a little forward, with the point of it rounded OFF — nothing
    // ends in a point, so the peak is a blunt roll of cloth and not a witch's cone.
    b.addBlob(v3(0, 0.055 * H, -0.010 * H), v3(0.083 * H, 0.098 * H, 0.086 * H), 5, 10, SHROUD);
    b.addBlob(v3(rng.range(-0.006, 0.006) * H, 0.118 * H, -0.030 * H), v3(0.050 * H, 0.052 * H, 0.048 * H), 4, 8, SHROUD_LT);
    // …and the cloth that falls off the back of it onto the shoulders.
    b.addBlob(v3(0, 0.010 * H, -0.056 * H), v3(0.072 * H, 0.070 * H, 0.048 * H), 4, 8, SHROUD_DK);
    // THE HOLLOW: sunk most of the way in, so what shows is a mouth of shadow rather than a ball stuck on.
    b.addBlob(v3(0, 0.048 * H, 0.052 * H), v3(0.056 * H, 0.062 * H, 0.048 * H), 5, 9, HOLLOW);
    b.setMat(.plain);
    // AT THE MOUTH OF THE HOLLOW, not inside it. Sunk to where the hollow's centre is they were behind its
    // own front wall — a creature whose entire read at range is two lights, with both lights buried.
    for ([_]f32{ 1, -1 }) |side| {
        const ex = side * 0.024 * H * rng.range(0.92, 1.08);
        const ey = (0.052 + rng.range(-0.006, 0.006)) * H; // …and they do not sit level
        b.addBlob(v3(ex, ey, 0.092 * H), v3(0.0125 * H, 0.0165 * H, 0.011 * H), 4, 8, EYE);
        b.addBlob(v3(ex, ey, 0.100 * H), v3(0.0058 * H, 0.0080 * H, 0.005 * H), 3, 7, EYE_CORE);
    }
    return b.toMesh();
}

/// An upper arm: authored down its own −Y, tapering, so a scale on this joint lengthens the whole limb.
fn armMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.cloth);
    b.addCapsule(
        v3(0, 0.012 * H, 0),
        v3(rng.range(-0.008, 0.008) * H, -0.152 * H, rng.range(-0.006, 0.006) * H),
        0.038 * H * rng.range(0.94, 1.06),
        0.028 * H,
        8,
        LIMB,
    );
    // A rag of the shroud still hanging off it — the thing has no edge where the sleeve stops.
    b.addBlob(v3(0, -0.030 * H, -0.010 * H), v3(0.046 * H, 0.055 * H, 0.040 * H), 4, 8, SHROUD_DK);
    return b.toMesh();
}

fn forearmMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.cloth);
    b.addCapsule(
        v3(0, 0.010 * H, 0),
        v3(rng.range(-0.007, 0.007) * H, -0.140 * H, rng.range(-0.005, 0.005) * H),
        0.028 * H * rng.range(0.94, 1.06),
        0.020 * H,
        7,
        LIMB_DK,
    );
    return b.toMesh();
}

/// A HAND OF THREE FINGERS, and every one of them ends in a blunt curl. Straight tapered spikes off a palm
/// is a rosette of spokes — NOTHING ENDS IN A POINT.
fn handMesh(side: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.cloth);
    b.addBlob(v3(0, -0.012 * H, 0.004 * H), v3(0.026 * H, 0.024 * H, 0.020 * H), 4, 8, LIMB);
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const fi: f32 = @floatFromInt(i);
        const spread = (fi - 1.0) * 0.020 * H * side;
        const knuckle = v3(spread, -0.030 * H, 0.010 * H);
        const mid = v3(spread * 1.5, -0.058 * H * rng.range(0.85, 1.1), 0.030 * H);
        const tip = v3(spread * 1.7, -0.062 * H, 0.056 * H); // …and it CURLS back up, it does not spear
        b.addCapsule(knuckle, mid, 0.0090 * H, 0.0074 * H, 5, LIMB_DK);
        b.addCapsule(mid, tip, 0.0074 * H, 0.0068 * H, 5, LIMB_DK);
        b.addBlob(tip, v3(0.0072 * H, 0.0072 * H, 0.0072 * H), 3, 6, LIMB); // the blunt end of it
    }
    return b.toMesh();
}

/// ONE HEM TATTER, and it is a PANEL OF CLOTH, not a rod. Eight rods hanging off a waist are eight legs
/// however thin — what makes a hem is a curtain, so each is wide tangentially and millimetres through. At
/// this width the eight OVERLAP at the top and part company toward the bottom, which reads as torn cloth.
/// `addBox` rather than a capsule: cloth is one of the things the round-mass law exempts. ONE curl, drawn
/// once and applied every segment, ending in a blunt fray rather than a point.
fn tatterMesh(len: f32, ang: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.cloth);
    const tan = v3(-mathx.sinf(ang), 0, mathx.cosf(ang));
    const rad = v3(mathx.cosf(ang), 0, mathx.sinf(ang));
    const SEGS = 4;
    const curlX = rng.range(-0.05, 0.05); // the whole panel's bow, decided ONCE
    const curlZ = rng.range(-0.04, 0.04);
    const segLen = len * H / SEGS;
    const THICK = 0.0055 * H;
    var p = v3(0, 0, 0);
    var hw = 0.058 * H * rng.range(0.88, 1.12); // …half the panel's width, wide enough to close the ring
    var i: i32 = 0;
    while (i < SEGS) : (i += 1) {
        const fi: f32 = @floatFromInt(i + 1);
        const q = v3(
            curlX * segLen * fi * fi * 0.5,
            -segLen * fi,
            curlZ * segLen * fi * fi * 0.5,
        );
        const hw1 = hw * rng.range(0.74, 0.88); // it narrows as it falls, so the hem frays rather than fringes
        const mid = mathx.lerpV(p, q, 0.5);
        const half = mathx.scaleV(mathx.subV(q, p), 0.5);
        const w = (hw + hw1) * 0.5;
        // ONE TONE DOWN THE WHOLE PANEL — banded per segment it barber-poles, the shroud's own lesson at a
        // tenth the scale. What separates the eight is their LENGTH, their width and their curl.
        b.addBox(mid, mathx.scaleV(tan, w), half, mathx.scaleV(rad, THICK), SHROUD);
        p = q;
        hw = hw1;
    }
    b.addBlob(p, v3(hw * 0.9, THICK * 2.2, hw * 0.9), 3, 7, SHROUD_LT); // the fray at the end of it, blunt
    return b.toMesh();
}

/// THE WISP IN FLIGHT — drawn along +Z, the axis `archer.arrowXform` puts down the line of travel, and
/// STRETCHED along it so a shot crossing the frame reads as a streak. The vertex alpha is the emissive
/// channel. Two shells, and the outer one is the DARKER: this projectile eats light rather than giving it
/// off, and a hot core inside a cold husk is the only way to draw that.
pub fn wispMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plain);
    b.addBlob(mathx.zero3, v3(0.080, 0.080, 0.180), 7, 11, rgba(WISP_DK.r, WISP_DK.g, WISP_DK.b, 120));
    b.addBlob(v3(0, 0, 0.022), v3(0.042, 0.042, 0.100), 6, 9, rgba(WISP_COL.r, WISP_COL.g, WISP_COL.b, 45));
    return b.toModel(shader);
}


test "the rig's tables are the rig's size, and the tatters are the tail of it" {
    try std.testing.expectEqual(@as(usize, N), REST.len);
    try std.testing.expectEqual(@as(usize, N), HEM_0 + HEM_N);
    // Every tatter hangs off the ROOT at its own bearing on the ring, and none of them is on the axis.
    for (0..HEM_N) |i| {
        const o = REST[HEM_0 + i];
        try std.testing.expectApproxEqAbs(HEM_Y, o.y, 1e-5);
        try std.testing.expect(mathx.lenXZ(o) > HEM_R * 0.8);
    }
}

test "NO ATTACK COMES OUT OF NOWHERE: every window clears the standard's own floor" {
    for (MOVES) |m| {
        try std.testing.expect(m.windDur >= foe.TELL_MIN);
        try std.testing.expect(m.strikeDur > 0 and m.recoverDur > 0);
        try std.testing.expect(m.cd > m.windDur + m.strikeDur + m.recoverDur);
    }
    // …and the two bands do not overlap, or one range would offer both and the pick would be arbitrary.
    try std.testing.expect(MOVES[WISP].minR > MOVES[GRASP].maxR);
}

test "the bands decide the move, and a spent cooldown never buys a free one" {
    try std.testing.expectEqual(Choice.hold, classify(AGGRO_R + 1, true, true));
    try std.testing.expectEqual(Choice.grasp, classify(1.0, true, true));
    // Toe to toe with the grasp spent it ORBITS: it does not stand there, and it does not throw a wisp
    // point blank — the wisp's own band starts well outside sword reach.
    try std.testing.expectEqual(Choice.circle, classify(1.0, false, true));
    try std.testing.expectEqual(Choice.wisp, classify(7.0, true, true));
    try std.testing.expectEqual(Choice.close, classify(7.0, true, false));
    try std.testing.expectEqual(Choice.circle, classify(MOVES[GRASP].maxR + 0.3, false, false));
    try std.testing.expectEqual(Choice.close, classify(MOVES[WISP].maxR + 2.0, true, true));
}

test "THE BLINK: threatened or wounded, never mid-swing, and never while the roots have it" {
    // A sword in its face is the whole trigger — there is no blinking away from a fight at range.
    try std.testing.expect(wantsBlink(1.0, 0, false, .circle, false));
    try std.testing.expect(!wantsBlink(9.0, 0, false, .circle, false));
    // …unless it has been HIT, which reaches it wherever it is standing.
    try std.testing.expect(wantsBlink(9.0, 0, true, .circle, false));
    // Spent, it stays and takes it. An evade you can spam is a wall.
    try std.testing.expect(!wantsBlink(1.0, 0.5, true, .circle, false));
    // ROOTED it cannot go at all: a blink does not travel, it leaves the earth (`foe.canLeap`).
    try std.testing.expect(!wantsBlink(1.0, 0, true, .circle, true));
    // …and it never abandons a swing it has committed to, nor a stagger the flinch has opened.
    try std.testing.expect(!wantsBlink(1.0, 0, true, .strike, false));
    try std.testing.expect(!wantsBlink(1.0, 0, true, .wind, false));
    try std.testing.expect(!wantsBlink(1.0, 0, true, .stunheavy, false));
    try std.testing.expect(!wantsBlink(1.0, 0, true, .dead, false));
}

test "THE TOUCH TAKES THE BLUE BAR AND THE WISP DOES NOT, and neither one is dearer than a heavy" {
    try std.testing.expect(GRASP_HIT.fp > 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), WISP_HIT.fp, 1e-6);
    // The wisp is the one that HURTS, which is the whole trade between the two.
    try std.testing.expect(WISP_HIT.dmg > GRASP_HIT.dmg * 2.0);
    // A DRAIN HAS NO WEIGHT: it must not turn up in `raw()`, or a shield's stamina bill and the "how hard
    // was that" beat would both read a touch as the heaviest thing in the game.
    try std.testing.expectApproxEqAbs(GRASP_HIT.dmg, GRASP_HIT.raw(), 1e-6);
    // Two touches empty a wand-user's pool but leave him alive to swing: it disarms, it does not kill.
    try std.testing.expect(GRASP_HIT.fp * 2.0 < combat.FP_MAX);
    try std.testing.expect(GRASP_HIT.fp * 5.0 > combat.FP_MAX);
}

test "it blinks to a bearing swung round from where it stands, at the hero's own range" {
    var s = Shade.spawn(v3(0, 0, 3), 0, 1.0, 0.3);
    const hero = mathx.zero3;
    s.debugBlink(hero);
    try std.testing.expectEqual(State.blinkout, s.state);
    // It arrives AT THE HERO'S OWN RANGE, whatever it did to get there…
    try std.testing.expectApproxEqAbs(BLINK_R, mathx.distXZ(s.blinkTo, hero), 1e-3);
    // …and well round from the bearing it left on, which is the flank the guard arc cannot cover.
    const wasBearing = mathx.headingXZ(mathx.dirXZ(hero, v3(0, 0, 3)));
    const now = mathx.headingXZ(mathx.dirXZ(hero, s.blinkTo));
    const swung = @abs(mathx.degrees(mathx.wrapPi(now - wasBearing)));
    try std.testing.expect(swung >= BLINK_TURN_MIN - 1.0 and swung <= BLINK_TURN_MAX + 1.0);
    try std.testing.expect(swung > combat.GUARD_ARC);
}

test "a blink puts it down where it said it would, and it is nowhere in between" {
    var s = Shade.spawn(v3(0, 0, 3), 0, 1.0, 0.3);
    const hero = mathx.zero3;
    s.debugBlink(hero);
    const want = s.blinkTo;
    var t: f32 = 0;
    while (t < BLINK_OUT * 0.5) : (t += 1.0 / 60.0) {
        _ = s.update(1.0 / 60.0, hero, 400, .{});
        try std.testing.expect(s.airborne()); // exempt from the terrain gate for exactly this long
    }
    // MEASURED THE FRAME IT LANDS, not some frames later: the moment it is down it starts orbiting again,
    // and a couple of centimetres of that is not the jump missing its mark.
    while (s.airborne() and t < 2.0) : (t += 1.0 / 60.0) _ = s.update(1.0 / 60.0, hero, 400, .{});
    try std.testing.expectApproxEqAbs(want.x, s.pos.x, 1e-3);
    try std.testing.expectApproxEqAbs(want.z, s.pos.z, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.thin, 1e-5); // …and solid again when it lands
}

test "a hit spooks it, a stagger holds it there, and the punish window is not teleported out of" {
    var s = Shade.spawn(v3(0, 0, 2), 0, 1.0, 0.3);
    const hero = mathx.zero3;
    s.debugStagger(true);
    s.spookLeft = SPOOK_DUR;
    // Through the WHOLE heavy stagger it stays exactly where the blow left it.
    var t: f32 = 0;
    while (t < combat.FOE_HEAVY_STUN_DUR - 0.05) : (t += 1.0 / 60.0) {
        _ = s.update(1.0 / 60.0, hero, 400, .{});
        try std.testing.expect(s.state == .stunheavy);
    }
    // …and then it goes.
    while (t < combat.FOE_HEAVY_STUN_DUR + 0.10) : (t += 1.0 / 60.0) _ = s.update(1.0 / 60.0, hero, 400, .{});
    try std.testing.expect(s.state == .blinkout or s.state == .blinkin);
}

test "ONE BLOW BUYS ONE BLINK, not every blink for the rest of the map" {
    // The bug a bool had: nothing but a blink ever cleared it, so a shade poked once at range kept
    // teleporting on its cooldown forever — including all the way home.
    try std.testing.expect(SPOOK_DUR > BLINK_CD);
    var s = Shade.spawn(mathx.zero3, 0, 1.0, 0.3);
    const away = v3(0, 0, AGGRO_R + 40.0);
    s.spookLeft = SPOOK_DUR;
    s.blinkCd = BLINK_CD; // spent: it cannot go yet, and by the time it can the fright is stale
    var t: f32 = 0;
    while (t < SPOOK_DUR + 1.0) : (t += 1.0 / 60.0) _ = s.update(1.0 / 60.0, away, 400, .{});
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.spookLeft, 1e-4);
    try std.testing.expect(!wantsBlink(mathx.LONG_AGO, 0, s.spookLeft > 0, .idle, false));
}

test "A JUMP IS NOT TRAVEL: the hem does not swing off a teleport" {
    var s = Shade.spawn(v3(0, 0, 3), 0, 1.0, 0.3);
    const hero = mathx.zero3;
    s.debugBlink(hero);
    var t: f32 = 0;
    while (s.airborne() and t < 2.0) : (t += 1.0 / 60.0) {
        _ = s.update(1.0 / 60.0, hero, 400, .{});
        // Five metres crossed in one frame is 300 units of "velocity" — fed to the lag it pins the
        // tatters at full swing for most of a second after the thing has stopped.
        try std.testing.expect(mathx.lenXZ(s.hemLag) < 0.1);
    }
    try std.testing.expect(t < 1.0); // …and it did land, rather than the loop falling out of its bound
}

test "THE ARMS CLOSE IN FRONT OF IT: a hero at its back is not somebody it has hold of" {
    var s = Shade.spawn(mathx.zero3, 0, 1.0, 0.3); // facing +Z
    try std.testing.expect(s.holds(v3(0, 0, 1.2)));
    try std.testing.expect(!s.holds(v3(0, 0, -1.2))); // square behind it
    try std.testing.expect(!s.holds(v3(0, 0, 9.0))); // …and out of reach in front
    // The arc is WIDER than the shield's, or a grasp you turned to face would still land behind you.
    try std.testing.expect(GRASP_ARC > combat.GUARD_ARC);
    const edge = mathx.radians(GRASP_ARC - 3.0);
    try std.testing.expect(s.holds(v3(1.2 * mathx.sinf(edge), 0, 1.2 * mathx.cosf(edge))));
    const past = mathx.radians(GRASP_ARC + 3.0);
    try std.testing.expect(!s.holds(v3(1.2 * mathx.sinf(past), 0, 1.2 * mathx.cosf(past))));

    // …and the whole move honours it, not just the predicate.
    var back = Shade.spawn(mathx.zero3, 0, 1.0, 0.3);
    const behind = v3(0, 0, -1.2);
    back.facing = 0;
    back.debugMove(GRASP);
    var t: f32 = 0;
    while (t < MOVES[GRASP].windDur + MOVES[GRASP].strikeDur + 0.05) : (t += 1.0 / 60.0) {
        back.facing = 0; // held: the state machine would otherwise simply turn round and face him
        try std.testing.expect(back.update(1.0 / 60.0, behind, 400, .{}) != .grasp);
    }
}

test "the touch lands once per grasp and only on somebody inside its arms" {
    var s = Shade.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, 1.2);
    s.debugMove(GRASP);
    var landed: u32 = 0;
    var t: f32 = 0;
    while (t < MOVES[GRASP].windDur + MOVES[GRASP].strikeDur + 0.05) : (t += 1.0 / 60.0) {
        if (s.update(1.0 / 60.0, hero, 400, .{}) == .grasp) landed += 1;
    }
    try std.testing.expectEqual(@as(u32, 1), landed);

    // …and the same grasp thrown at somebody standing well clear lands nothing at all.
    var miss = Shade.spawn(mathx.zero3, 0, 1.0, 0.3);
    const away = v3(0, 0, 9.0);
    miss.debugMove(GRASP);
    t = 0;
    while (t < MOVES[GRASP].windDur + MOVES[GRASP].strikeDur + 0.05) : (t += 1.0 / 60.0) {
        try std.testing.expect(miss.update(1.0 / 60.0, away, 400, .{}) != .grasp);
    }
}

test "the wisp leaves the hands exactly once, and from between them" {
    var s = Shade.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, 7.0);
    s.debugMove(WISP);
    var thrown: u32 = 0;
    var from = mathx.zero3;
    var t: f32 = 0;
    while (t < MOVES[WISP].windDur + MOVES[WISP].strikeDur + 0.05) : (t += 1.0 / 60.0) {
        switch (s.update(1.0 / 60.0, hero, 400, .{})) {
            .hurl => |p| {
                thrown += 1;
                from = p;
            },
            else => {},
        }
    }
    try std.testing.expectEqual(@as(u32, 1), thrown);
    // Off its own body, not out of the ground under it: a wisp born at the feet reads as a trap.
    try std.testing.expect(from.y > s.pos.y + 0.5);
    try std.testing.expect(mathx.distXZ(from, s.pos) < 1.6);
}

test "A CORPSE IS NOT A COLLIDER, and it comes apart rather than falling over" {
    var s = Shade.spawn(mathx.zero3, 0, 1.0, 0.3);
    s.debugKill();
    try std.testing.expect(s.justDied);
    try std.testing.expect(s.alive() and s.dying());
    try std.testing.expect(!foe.corporeal(&s));
    var t: f32 = 0;
    while (t < DEATH_DUR + DISS_DUR + 0.1) : (t += 1.0 / 60.0) _ = s.update(1.0 / 60.0, v3(0, 0, 9), 400, .{});
    try std.testing.expect(!s.alive());
    // …and `justDied` is a ONE-FRAME flag, not a latch that bills the death sixty times a second.
    try std.testing.expect(!s.justDied);
}

test "every world point is measured off the ground under it plus the hover" {
    var low = Shade.spawn(mathx.zero3, 0, 1.0, 0.3);
    var high = Shade.spawn(v3(0, 4.0, 0), 0, 1.0, 0.3);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), high.centerWorld().y - low.centerWorld().y, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), high.topWorld().y - low.topWorld().y, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), high.lockPoint().y - low.lockPoint().y, 1e-4);
    // The bar hangs over the head, the lock sits under it, and the hurt sphere is lower again.
    try std.testing.expect(low.topWorld().y > low.lockPoint().y);
    try std.testing.expect(low.lockPoint().y > low.centerWorld().y);
    // …and it FLOATS: nothing on it is measured from the earth itself.
    try std.testing.expect(low.centerWorld().y > low.pos.y + HOVER * 0.9);
}

test "the roots take its drift and refuse it the blink" {
    var s = Shade.spawn(v3(0, 0, 6), 0, 1.0, 0.3);
    const hero = mathx.zero3;
    s.root.grab();
    const was = s.pos;
    var t: f32 = 0;
    while (t < 0.6) : (t += 1.0 / 60.0) _ = s.update(1.0 / 60.0, hero, 400, .{});
    try std.testing.expectApproxEqAbs(was.x, s.pos.x, 1e-4);
    try std.testing.expectApproxEqAbs(was.z, s.pos.z, 1e-4);
    // …and being hit while held does not buy it a way out.
    s.spookLeft = SPOOK_DUR;
    t = 0;
    while (t < 0.6) : (t += 1.0 / 60.0) _ = s.update(1.0 / 60.0, hero, 400, .{});
    try std.testing.expect(s.state != .blinkout and s.state != .blinkin);
}

test "it turns for home like anything else, and the tether is its own ring plus the standard's slack" {
    var s = Shade.spawn(mathx.zero3, 0, 1.0, 0.3);
    s.pos = v3(0, 0, foe.leashR(AGGRO_R) + 4.0);
    const away = v3(0, 0, foe.leashR(AGGRO_R) + AGGRO_R + 30.0);
    var t: f32 = 0;
    while (t < foe.LEASH_CALM + 0.2) : (t += 1.0 / 60.0) _ = s.update(1.0 / 60.0, away, 400, .{});
    try std.testing.expect(s.leash.goingHome());
    const before = mathx.distXZ(s.pos, s.home);
    t = 0;
    while (t < 1.0) : (t += 1.0 / 60.0) _ = s.update(1.0 / 60.0, away, 400, .{});
    try std.testing.expect(mathx.distXZ(s.pos, s.home) < before);
}

test "the hem TRAILS the drift and settles back through its own rest" {
    var s = Shade.spawn(mathx.zero3, 0, 1.0, 0.3);
    const dt = 1.0 / 60.0;
    // Driven north, the lag points SOUTH — the tatters are behind it, not in front.
    var t: f32 = 0;
    while (t < 0.5) : (t += dt) {
        const was = s.pos;
        s.pos.z += DRIFT_SPEED * dt;
        s.trailHem(was, dt);
    }
    try std.testing.expect(s.hemLag.z < -0.5);
    // Stopped, it eases back to nothing rather than snapping there.
    const held = s.hemLag.z;
    s.trailHem(s.pos, dt);
    try std.testing.expect(s.hemLag.z > held and s.hemLag.z < 0);
    t = 0;
    while (t < 2.0) : (t += dt) s.trailHem(s.pos, dt);
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.hemLag.z, 1e-3);
}
