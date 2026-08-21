const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const heromod = @import("../play/hero.zig");
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

// THE FLORID RAVAGER (owner's creature, owner's name) — a big hound with an open flower for a head.
//
// **THE QUADRUPED RIG'S SECOND USER**: the bone layout, rest chain, gait dials, limb solver and leap all come
// from `wolf.zig`. Its own are a STATURE and a HEAD — anything else would be a transcription, which the rig
// law forbids.
//
// **THE BLOOM IS THE TELL AND THE TELL IS THE WHOLE FIGHT.** One scalar (`open`), read off the bite's own
// clock and never a second timer, so the picture cannot promise a lunge the mechanic is not throwing.

/// Height at the WITHERS. Over Hildebrand's 1.12 (owner: LARGE dogs) — it stands about as tall as the hero's
/// chest, which is what makes the head coming at you a head and not a knee.
pub const W: f32 = 1.34;

pub const AGGRO_R: f32 = 11.0;
const HOME_R: f32 = 1.2;

const BODY_R: f32 = 0.46;
/// **IT HAS TO HOLD THE STALK AS WELL AS THE BODY.** Sized for a ribcage it stopped at 1.4 m and the neck and
/// bloom — a third of the creature, and what the player aims at — were outside any sword. Solved to span the
/// barrel's middle (0.83 m) up to the bloom (2.17 m).
const HURT_R: f32 = 0.92;
const CENTER_F: f32 = 1.05;
const TOP_F: f32 = 1.66;

/// **TOUGH IN THE BODY, NOTHING IN THE STALK** (owner: tougher but poisebreak easily). The two numbers say
/// the same thing from opposite ends: it takes a long time to kill and it comes apart the moment you
/// interrupt it, so the fight is about catching the rear rather than about out-trading it.
const HP_MAX: f32 = 88.0;
/// **AND IT HAS TO SIT BETWEEN THE HERO'S TWO SWINGS**, not under both: at 9 a light poke flinched it, and a
/// creature you can stunlock with the fast button is not dangerous, it is furniture. The hero's light is 10
/// poise and his heavy is 22, so 12 is as low as "breaks easily" can go and still mean the HEAVY breaks it.
const POISE_MAX: f32 = 12.0;
const STANCE_MAX: f32 = 40.0;
const RESISTS = combat.resists(.{ .fire = -45, .cold = 30, .lightning = 0, .chaos = 20 });

const SOULS: u32 = 190;

const DEATH_DUR: f32 = 1.25;
const DISS_DUR: f32 = 1.05;
const DISSOLVE = foe.Dissolve{ .rate = 58.0, .spread = 0.9, .rise = 0.85, .flake = PETAL_LT };

/// Sized off what feeds it: `DISSOLVE.rate` 58/s against a mean mote life of ~0.72 s stands about 42 at the
/// fade's start, and the bloom's own puff is at most 8 in a frame.
const PARTS = 56;

const BITE_WIND: f32 = 0.38;
const BITE_STRIKE: f32 = 0.18;
const BITE_RECOVER: f32 = 0.46;
const BITE_COOL: f32 = 0.85;
/// Metres of forward travel across the wind and the strike — further than the wolf's 0.62, because this is a
/// bigger animal and the leap is the move.
const BITE_HOP: f32 = 0.86;
const BITE_R: f32 = 1.55;
const BITE_TRIGGER_R: f32 = BITE_R + BITE_HOP * 0.8;

/// **THE LEAP'S THREE INSTANTS, NAMED ONCE.** `LAUNCH_T` is the frame it leaves the earth, `HOP_END` the
/// frame it is back on it, and `APEX_T` the top of the arc between them. Written out as
/// `BITE_WIND + BITE_STRIKE` at six sites and `BITE_WIND * 0.55` at three, the pose, the mechanic, the
/// airborne gate and the staged photograph were four copies of one clock that had to agree by hand.
const LAUNCH_T: f32 = BITE_WIND * 0.55;
const HOP_END: f32 = BITE_WIND + BITE_STRIKE;
const APEX_T: f32 = (LAUNCH_T + HOP_END) * 0.5;

comptime {
    std.debug.assert(BITE_WIND >= foe.TELL_MIN);
    std.debug.assert(OPEN_BY < 1.0);
}

/// **THE GATE IS MEASURED FROM THE QUARRY'S HIDE** (`wolf.triggerR`'s law, and for its reason: asked
/// centre-to-centre a flat radius is unsatisfiable on anything broad, because `env.resolveActor` holds the
/// body `bodyR + its own` out and it circles a creature it can never trigger on).
pub fn triggerR(quarryR: f32) f32 {
    return BITE_TRIGGER_R + quarryR;
}
fn stopR(quarryR: f32) f32 {
    return BITE_R * 0.85 + quarryR;
}

const BITE_HIT = combat.Hit{ .dmg = 24, .poise = 20, .stance = 9 };

const OPEN_BY: f32 = 0.62;
const SHUT_BY: f32 = 0.75;
/// **AND IT OPENS FURTHER WHEN IT COMES AT YOU** (owner). The approach tier is unchanged; this is the leap's
/// own, and widening only the top of the range keeps the two tiers distinct instead of flattening them.
const ATTACK_OPEN: f32 = 2.10;
/// WHERE THE BLOOM STARTS TO WAKE and where it is at its full approach gape. The near end is the leap's own
/// trigger ring, so it is ALREADY at its widest on the frame the leap can be chosen: the attack tier then has
/// somewhere to go, and the opening is never news that arrives with the blow.
const NEAR_FAR: f32 = AGGRO_R * 0.8;
const NEAR_WIDE: f32 = BITE_TRIGGER_R + foe.HERO_R;
const NEAR_RATE: f32 = 2.4;

const TURN_RATE: f32 = 4.4; // rad/s — big and slower on its feet than the spirit's 5.6
const ACCEL: f32 = 7.5;
const GAIT_BLEND: f32 = 8.0;
/// It closes at a run and holds it — the thing you cannot simply walk away from.
const CHASE_SPEED: f32 = wolf.GALLOP_SPEED * 0.78;

pub const SHOVE = foe.Push{ .light = 1.20, .heavy = 2.90 };
const SHOVE_DECAY: f32 = 6.0;

/// How far down the jaw bone the bloom's throat sits, as a fraction of `W` — the point the mouth's height is
/// measured at, the wolf's `JAW_REACH` one creature along.
const JAW_REACH: f32 = 0.13;
/// …AND THE BLOOM'S OWN HALF-WIDTH, which its reach and measured height are both taken over: the mouth is a
/// RADIUS, not a point. Bigger head (owner) — this moves the silhouette, the reticle and the strike's reach
/// together.
const BLOOM_R: f32 = 0.40;
/// HOW FAR OFF ITS NOSE THE BLOOM STILL CATCHES HIM — the cosine of the frontal cone (the toad's own dial).
/// 0.25 is about 76 degrees either side, which is a ring of petals rather than a point.
const BITE_FRONT_DOT: f32 = 0.25;

const N = wolf.N;
const ROOT = wolf.ROOT;
const SPINE = wolf.SPINE;
const CHEST = wolf.CHEST;
const NECK = wolf.NECK;
const HEAD = wolf.HEAD;
const JAW = wolf.JAW;
const TAIL0 = wolf.TAIL0;
const TAIL1 = wolf.TAIL1;
const TAIL2 = wolf.TAIL2;
const EARL = wolf.EARL;
const EARR = wolf.EARR;

const PETALS_PER_SIDE = 3;

const LOCK_AT = v3(0, 0.335 * W, 0.15 * W);


const NECK_UP: f32 = 1.62;
const NECK_OUT: f32 = 0.30;
/// Where the neck's own midpoint sits, as a share of the way from the shoulder to the head. Under 0.5 puts the
/// bend low and the top run long, which is what a stalk looks like and a swan's neck does not.
const NECK_MID: f32 = 0.42;

const NECK_STRETCH: f32 = 0.26;

/// **AND THEN IT STRIKES DOWN, WHICH IS THE OTHER HALF OF HAVING A NECK LIKE THAT.** Degrees the whole head
/// chain pitches forward and under across the strike. It has to be big: reared and stretched the bloom rides
/// at 3.3 m, which is a metre and a half over the top of his head — a creature that leapt from there would
/// pass clean over him every time. The rear is the TELL and the dive is the BLOW, and both are the neck.
const STRIKE_DIVE: f32 = 108.0;
const DIVE_BY: f32 = 0.55;
/// How much of the neck's reach the dive takes back. High: the gather is the extension and the blow is the
/// fold, and the two sharing the same 0..1 is what keeps them from telling different stories.
const DIVE_COIL: f32 = 0.50;
const BODY_DIVE: f32 = 26.0;

fn restPose() [N]rl.Vector3 {
    var r = wolf.restPose(W);
    const sh = r[CHEST];
    r[HEAD] = v3(0, NECK_UP * W, sh.z + NECK_OUT * W);
    r[NECK] = v3(0, mathx.lerpF(sh.y, r[HEAD].y, NECK_MID), mathx.lerpF(sh.z, r[HEAD].z, NECK_MID * 0.6));
    r[JAW] = v3(0, r[HEAD].y - 0.035 * W, r[HEAD].z + 0.073 * W);
    r[EARL] = v3(0.050 * W, r[HEAD].y + 0.075 * W, r[HEAD].z - 0.055 * W);
    r[EARR] = v3(-0.050 * W, r[HEAD].y + 0.075 * W, r[HEAD].z - 0.055 * W);
    return r;
}

// **AUTHOR DARK, AND SOLVE IT RATHER THAN GUESS** — screen goes as albedo^(1/2.2), so a factor you want on
// screen is that factor^2.2 on the albedo. MEASURED: at (38, 34, 30) the hide came back at 144 against ground
// at 112 — BRIGHTER than its field. Wanted ~78, i.e. 0.54 on screen, 0.54^2.2 = 0.264 on the albedo. The
// bloom is the one thing allowed to be bright, because it is the read.
const HIDE = rgba(10, 9, 8, 206);
const HIDE_LT = rgba(15, 13, 11, 190);
const HIDE_DK = rgba(6, 6, 5, 210);
const PETAL = rgba(72, 60, 71, 214);
const PETAL_LT = rgba(88, 76, 85, 196);
const PETAL_BACK = rgba(28, 22, 26, 208);
const THROAT = rgba(255, 122, 132, 26);
const THROAT_DEEP = rgba(196, 54, 72, 58);
const THROAT_HALO = rgba(214, 96, 128, 104);
const STAMEN = rgba(248, 226, 150, 62);
const CLAW = rgba(8, 7, 6, 214);

pub const State = enum { idle, move, bite, hurt, dead };

pub const Model = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "ravager");
        return .{ .mesh = buildMeshes(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, r: *const Ravager) void {
        for (0..N) |i| rl.drawMesh(self.mesh[i], self.mat, r.xf[i]);
    }
};

pub const Ravager = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},

    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,
    state: State = .idle,
    t: f32 = 0,
    /// Gait phase, 0..1, advanced by DISTANCE and never by time — the hero's law, and why the paws do not skate.
    phase: f32 = 0,
    speed: f32 = 0,
    speedS: f32 = 0,
    biteCool: f32 = 0,
    /// **HOW AWAKE THE BLOOM IS**, 0..1, eased toward what the distance asks for (`NEAR_FAR`..`NEAR_WIDE`).
    /// A LEVEL and not an event: it has to be able to fall again when he backs off, and it may not step.
    nearK: f32 = 0,
    pounce: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    heroLatch: bool = false,
    /// THIS FRAME'S BLOW ON WHOEVER IT IS FIGHTING, read straight back out of `update`. **A FOE HURTS THE HERO
    /// BY RETURNING A `Hit`**, never by carrying a `foe.Blade` — that type is the other direction entirely
    /// (what HIS sword sweeps against a body). Built the wrong way round the creature leapt all day and could
    /// not take a point off him, and the swept capsule it maintained per frame fed nothing at all.
    heroHit: ?combat.Hit = null,
    heavyStun: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    /// Its voices' one-frame edges, cleared with `justDied` at the top of `update`. The creature says WHEN;
    /// `game.zig` owns the speaker, or a creature would play through the pause card and the shot harness.
    opened: bool = false,
    leapt: bool = false,
    snapped: bool = false,
    yelped: bool = false,

    fade: f32 = 0,
    gone: bool = false,

    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    rest: [N]rl.Vector3 = undefined,
    xf: [N]rl.Matrix = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Ravager {
        var r = Ravager{
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale,
            .seed = seed,
            .rest = restPose(),
        };
        r.fxRng = foe.fxStream(seed, 51787.0, 0x1F10);
        r.pose();
        return r;
    }

    pub fn kind(_: *const Ravager) wf.FoeKind {
        return .florid_ravager;
    }

    pub fn centerWorld(self: *const Ravager) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * W, self.scale, 0);
    }
    /// **THE MARK RIDES THE BODY, NOT THE BLOOM** (owner's call) — on the head it rode a stalk that rears
    /// 1.6 `W`, stretches a quarter more and DIVES 152 degrees, so the reticle travelled a metre and a half a
    /// strike. Off `CHEST` and not `centerWorld`, so it still rides the POSE (`foe.markOn`'s reason).
    pub fn lockPoint(self: *const Ravager) rl.Vector3 {
        return foe.markOn(self.xf[SPINE], LOCK_AT);
    }
    pub fn topWorld(self: *const Ravager) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * W, self.scale, 0);
    }
    pub fn hurtRadius(self: *const Ravager) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Ravager) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Ravager) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Ravager) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Ravager) bool {
        return self.state == .hurt or self.state == .dead;
    }
    pub fn airborne(self: *const Ravager) bool {
        return self.state == .bite and self.leapLift() > foe.AIRBORNE_LIFT;
    }
    pub fn flashFrac(self: *const Ravager) f32 {
        return foe.flashFrac(self.flash);
    }

    pub fn jawPoint(self: *const Ravager) rl.Vector3 {
        return foe.markOn(self.xf[JAW], v3(0, 0, JAW_REACH * W));
    }

    /// 0..1, **read off the bite's own clock and nowhere else**, so the picture and the mechanic cannot
    /// disagree. **TWO TIERS, AND THE SECOND IS THE TELL** (owner: open as he gets close, very wide; wider
    /// still when it attacks) — 0 shut, 1 the wide-awake gape while he is near, past 1 to `ATTACK_OPEN` for
    /// the leap. A RANGE and not a switch. The approach tier is SMOOTHED (`nearK`) so it cannot pop.
    pub fn openAmt(self: *const Ravager) f32 {
        const near = self.nearK;
        if (self.state != .bite) return near;
        const k: f32 = if (self.t < BITE_WIND)
            mathx.smoothstep(0, BITE_WIND * OPEN_BY, self.t)
        else if (self.t < HOP_END)
            1.0
        else
            1.0 - mathx.smoothstep(HOP_END, HOP_END + BITE_RECOVER * SHUT_BY, self.t);
        return mathx.lerpF(near, ATTACK_OPEN, k);
    }

    /// **HOW FAR THE NECK IS REACHING**, 0..1 — the bloom's own dial normalised, so the stalk rears as the
    /// flower opens and the two can never tell different stories. Past the approach gape it keeps going: the
    /// leap is the head arriving, and the neck going with it is most of what makes it arrive.
    pub fn stretchAmt(self: *const Ravager) f32 {
        return mathx.clampF(self.openAmt() / ATTACK_OPEN, 0, 1);
    }

    /// **HOW FAR INTO THE DIVE IT IS**, 0..1. Off the strike's own window, not the whole bite: the rear and
    /// the stretch own the gather, and this owns the frames the blow is live in.
    pub fn diveAmt(self: *const Ravager) f32 {
        if (self.state != .bite) return 0;
        if (self.t < BITE_WIND) return 0;
        if (self.t < HOP_END) return mathx.smoothstep(BITE_WIND, BITE_WIND + BITE_STRIKE * DIVE_BY, self.t);
        return 1.0 - mathx.smoothstep(HOP_END, HOP_END + BITE_RECOVER * SHUT_BY, self.t);
    }

    fn leapLift(self: *const Ravager) f32 {
        if (self.state != .bite) return 0;
        if (self.t <= LAUNCH_T or self.t >= HOP_END) return 0;
        const u = (self.t - LAUNCH_T) / (HOP_END - LAUNCH_T);
        return wolf.BITE_HOP_UP * mathx.sinf(u * std.math.pi) * mathx.lerpF(wolf.HOP_FLOOR, 1.0, self.pounce) * W;
    }


    pub fn navWant(self: *const Ravager, hero: rl.Vector3) ?rl.Vector3 {
        if (self.state != .idle and self.state != .move) return null;
        if (foe.senseHero(&self.leash, self.pos, hero, AGGRO_R) <= AGGRO_R) return hero;
        return if (mathx.distXZ(self.pos, self.home) > HOME_R) self.home else null;
    }

    fn faceToward(self: *Ravager, at: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, at, TURN_RATE, dt);
    }

    pub fn update(self: *Ravager, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        self.justDied = false;
        self.heroHit = null;
        self.opened = false;
        self.leapt = false;
        self.snapped = false;
        self.yelped = false;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.stateStep(dt, hero, bounds);
        self.tryHit(blade);
        return self.heroHit;
    }

    fn stateStep(self: *Ravager, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer if (!self.airborne()) grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();

        self.t += dt;
        self.vit.tick(dt);
        foe.fadeFlash(&self.flash, dt);
        self.biteCool = mathx.maxF(0, self.biteCool - dt);
        foe.tickLeash(&self.leash, dt, self.pos, self.home, hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);
        const seeR = mathx.distXZ(self.pos, hero);
        const wantOpen: f32 = if (self.state == .dead) 0 else mathx.clampF((NEAR_FAR - seeR) / (NEAR_FAR - NEAR_WIDE), 0, 1);
        self.nearK = mathx.approach(self.nearK, wantOpen, NEAR_RATE * dt);

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
        if (self.state == .bite) {
            if (self.t < BITE_WIND) self.faceToward(hero, dt);
            self.speed = 0;
            // THE LEAP CARRIES IT IN, through `stepXZ` like any other committed travel so the terrain gate
            // still gets the last word.
            // THE LAUNCH IS AN EDGE, caught by the clock CROSSING it — a long frame cannot fire it twice and
            // a short one cannot miss it (`hero.updateShot`'s rule).
            if (self.t - dt < LAUNCH_T and self.t >= LAUNCH_T) self.leapt = true;
            if (self.t < HOP_END) {
                mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), BITE_HOP * (dt / HOP_END), bounds);
            }
            if (self.t >= BITE_WIND and self.t < HOP_END) self.tryBite(hero);
            if (self.t >= HOP_END + BITE_RECOVER) {
                self.state = .idle;
                self.t = 0;
                self.biteCool = BITE_COOL;
                self.heroLatch = false;
            }
            self.settle(dt);
            return self.pose();
        }

        const sensed = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        const hunting = sensed <= AGGRO_R;
        const want = if (hunting) hero else self.home;
        const gap = mathx.distXZ(self.pos, want);
        const stop: f32 = if (hunting) stopR(foe.HERO_R) else HOME_R;

        // **THE JUMP IS GATED WHERE THE MOVE IS CHOSEN** — the one place a post-step gate cannot reach. Held
        // by the ankles it may not leap, and denying only its distance leaves it hopping on the spot inside a
        // fist of roots.
        if (hunting and gap <= triggerR(foe.HERO_R) and self.biteCool <= 0 and foe.canLeap(&self.root)) {
            self.state = .bite;
            self.t = 0;
            self.heroLatch = false;
            self.speed = 0;
            self.pounce = 1.0;
            self.opened = true;
        } else if (gap > stop) {
            self.faceToward(self.nav.aim(self.pos, want), dt);
            const wantSpeed: f32 = if (hunting) CHASE_SPEED else wolf.TROT_SPEED;
            self.speed = mathx.approach(self.speed, wantSpeed, ACCEL * dt);
            const step = self.speed * dt * self.chill.travel();
            mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), step, bounds);
            self.phase = wolf.wrap01(self.phase + step / wolf.strideFor(self.speed));
            self.state = .move;
        } else {
            self.faceToward(want, dt);
            self.speed = mathx.approach(self.speed, 0, ACCEL * dt);
            self.state = .idle;
        }
        self.settle(dt);
        self.pose();
    }

    fn tryBite(self: *Ravager, hero: rl.Vector3) void {
        if (self.heroLatch) return;
        const d = mathx.distXZ(self.pos, hero);
        if (d > BITE_R + foe.HERO_REACH) return;
        const to = mathx.dirXZ(self.pos, hero);
        const fwd = mathx.headingDir(self.facing);
        const front = to.x * fwd.x + to.z * fwd.z;
        if (d > 0.35 and front < BITE_FRONT_DOT) return;
        self.heroHit = BITE_HIT;
        self.heroLatch = true;
        self.snapped = true;
        self.leash.noteCombat();
    }

    fn settle(self: *Ravager, dt: f32) void {
        self.speedS = mathx.approach(self.speedS, self.speed, GAIT_BLEND * dt);
    }

    pub fn tryHit(self: *Ravager, blade_: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade_) orelse return;
        const heavy = foe.wounded(self, s, blade_, SHOVE);
        self.emitPetals(s.contact, if (heavy) 7 else 3);
        switch (s.reaction) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(true),
            .light => self.enterStun(false),
            .none => {},
        }
    }

    fn enterStun(self: *Ravager, heavy: bool) void {
        self.state = .hurt;
        self.t = 0;
        self.heavyStun = heavy;
        self.yelped = true;
    }

    fn enterDeath(self: *Ravager) void {
        if (self.state == .dead) return;
        self.state = .dead;
        self.t = 0;
        self.justDied = true;
    }

    pub fn debugStagger(self: *Ravager, heavy: bool) void {
        self.enterStun(heavy);
    }

    pub fn stagePounce(self: *Ravager, amt: f32) void {
        self.state = .bite;
        self.pounce = mathx.clampF(amt, 0, 1);
        self.t = APEX_T;
        self.pose();
    }
    pub fn stageGather(self: *Ravager, u: f32) void {
        self.state = .bite;
        self.t = mathx.clampF(u, 0, 1) * BITE_WIND;
        self.pose();
    }

    fn emitPetals(self: *Ravager, at: rl.Vector3, n: i32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.6, 1.7);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = at,
                .v = v3(mathx.cosf(a) * sp, self.fxRng.range(0.3, 1.6), mathx.sinf(a) * sp),
                .life = self.fxRng.range(0.38, 0.78),
                .r0 = self.fxRng.range(0.030, 0.058) * self.scale,
                .r1 = 0.006,
                .col = if (self.fxRng.float() < 0.5) PETAL else PETAL_LT,
                .grav = 2.2,
                // Petals FLUTTER — heavy drag against a light pull, so they leap off the bloom and then drift down.
                .drag = 2.8,
            });
        }
    }

    pub fn drawFx(self: *const Ravager) void {
        foe.drawParticles(&self.parts);
    }

    pub fn draw(self: *const Ravager, model: *const Model) void {
        if (self.gone) return;
        model.draw(self);
    }

    pub fn pose(self: *Ravager) void {
        const g = wolf.gaitAt(self.speedS);
        const stride = wolf.strideFor(self.speedS);
        const ph = wolf.limbPhases(self.phase, g);
        const m = mathx.clampF(self.speedS / wolf.WALK_SPEED, 0, 1);
        const s = self.scale;
        const breath = mathx.sinf(self.t * 1.7) * 0.007 * W;
        const react: f32 = if (self.state == .hurt) foe.stunCurve(self.t, self.heavyStun) else 0;
        const fall: f32 = if (self.state == .dead) mathx.clampF(self.t / (DEATH_DUR * 0.7), 0, 1) else 0;

        const lift = self.leapLift();
        const arcN = if (wolf.BITE_HOP_UP * W > 1e-5) lift / (wolf.BITE_HOP_UP * W) else 0;
        const pitch = wolf.BITE_PITCH * arcN - BODY_DIVE * self.diveAmt();
        var crouch: f32 = 0;
        if (self.state == .bite) {
            crouch = CROUCH * mathx.smoothstep(0, BITE_WIND * 0.8, self.t) * (1.0 - mathx.smoothstep(BITE_WIND, HOP_END, self.t));
        }

        var wx: [N]rl.Matrix = undefined;
        // **THE WHOLE RIG TAKES THE MAP'S SCALE, NOT JUST THE PELVIS HEIGHT** — `centerWorld`, `topWorld`,
        // `hurtRadius` and `bodyR` are all `self.scale`'d, so a rig drawn at 1 hangs a bigger hurt sphere and
        // bar round a body that never grew. INNERMOST, so every child bone inherits it through the chain.
        wx[ROOT] = mul3(
            mul(scaleM(s, s, s), mul(rx(-pitch), rz(-70.0 * mathx.smoothstep(0, 1, fall)))),
            mul(tr(0, (self.rest[ROOT].y + breath + lift - crouch * W - 0.10 * W * fall) * s, 0), ry(mathx.degrees(self.facing))),
            heromod.rootAt(self.pos),
        );
        const flex = mathx.sinf(self.phase * std.math.tau) * m * (4.0 + 9.0 * mathx.clampF((self.speedS - wolf.TROT_SPEED) / (wolf.GALLOP_SPEED - wolf.TROT_SPEED), 0, 1));
        const duck: f32 = 8.0 * react;
        heromod.setJoint(&wx, &self.rest, SPINE, ROOT, rx(-flex * 0.5 - duck * 0.3));
        heromod.setJoint(&wx, &self.rest, CHEST, SPINE, rx(-flex * 0.5 - duck * 0.3));
        // THE NECK, and it is UPRIGHT: the canid's forward reach is gone, so what the gait does to it is a
        // sway rather than a nod. It still ducks hard on a reaction — a stalk hit in the middle folds.
        // …AND IT DIVES ON THE STRIKE. Negative about X at the neck brings the head DOWN and forward (the
        // root's own sign, one joint along), which is what puts a bloom carried at 2.2 m into a man's chest.
        heromod.setJoint(&wx, &self.rest, NECK, CHEST, rx(flex * 0.5 + 3.0 * m - duck * 1.4 - STRIKE_DIVE * self.diveAmt()));
        // **THE HEAD STRETCHES UP THE NECK'S OWN AXIS**, not the world's: `setJoint` takes the bone length
        // from the DISTANCE between two rest points, so the reach is a translate on top and `jawPoint` comes
        // with it. **AND IT COILS BACK AS IT STRIKES** (owner: the neck goes crazy) — at full stretch through
        // 108 degrees of dive the bloom swept a metre and a half and read as a whip; `diveAmt` takes most of
        // the reach back over the blow.
        const reach = NECK_STRETCH * W * self.stretchAmt() * (1.0 - DIVE_COIL * self.diveAmt());
        const neckOff = mathx.subV(self.rest[HEAD], self.rest[NECK]);
        const up = if (mathx.lenV(neckOff) > 1e-5) mathx.normV(neckOff) else v3(0, 1, 0);
        wx[HEAD] = mul(
            mul(rx(flex * 0.25 - 3.0 * m - duck * 0.6), tr(neckOff.x + up.x * reach, neckOff.y + up.y * reach, neckOff.z + up.z * reach)),
            wx[NECK],
        );
        const open = self.openAmt();
        heromod.setJoint(&wx, &self.rest, JAW, HEAD, rx(PETAL_GAPE * open));
        const splay = PETAL_SPLAY * open;
        const layback = PETAL_BACK_ANG * open - 52.0 * react;
        heromod.setJoint(&wx, &self.rest, EARL, HEAD, mul(rx(layback), rz(-splay - 8.0)));
        heromod.setJoint(&wx, &self.rest, EARR, HEAD, mul(rx(layback), rz(splay + 8.0)));
        const tailSwing = mathx.sinf(self.phase * std.math.tau + 1.1) * 6.0 * m;
        heromod.setJoint(&wx, &self.rest, TAIL0, ROOT, mul(rx(-10.0 * m + 24.0 * react), ry(tailSwing)));
        heromod.setJoint(&wx, &self.rest, TAIL1, TAIL0, mul(rx(6.0 + 10.0 * react), ry(tailSwing * 0.7)));
        heromod.setJoint(&wx, &self.rest, TAIL2, TAIL1, mul(rx(9.0 + 8.0 * react), ry(tailSwing * 0.5)));
        const tuck = lift / @max(0.72 * W, 0.001);
        wolf.legs(&wx, &self.rest, W, ph, g, stride, m, crouch, tuck);
        self.xf = wx;
    }
};

/// How far the whole animal sinks through the gather, as a fraction of `W` — deeper than the spirit's 0.09
/// because it is a bigger body loading a longer leap, and the sink IS the wind-up you read the leap off.
const CROUCH: f32 = 0.13;
const PETAL_GAPE: f32 = 86.0;
const PETAL_SPLAY: f32 = 74.0;
const PETAL_BACK_ANG: f32 = -58.0;

const CAP_N = wf.MAX_PER_KIND;

pub const Thicket = struct {
    model: Model,
    dogs: [CAP_N]Ravager = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Thicket {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Thicket) []Ravager {
        return self.dogs[0..self.n];
    }
    pub fn liveConst(self: *const Thicket) []const Ravager {
        return self.dogs[0..self.n];
    }
    pub fn reset(self: *Thicket, m: *const wf.Map) void {
        foe.resetGroup(Ravager, &self.dogs, &self.n, m, .florid_ravager);
    }
    pub fn clear(self: *Thicket) void {
        self.n = 0;
    }
    pub fn setShader(self: *Thicket, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn update(self: *Thicket, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    pub fn draw(self: *const Thicket, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Thicket) void {
        for (self.liveConst()) |*r| r.drawFx();
    }
    pub fn pierce(self: *Thicket, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Thicket) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Thicket) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Thicket) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Thicket) u32 {
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
    var rng = mathx.Rng.init(0xF10D + @as(u64, @intCast(i)));
    switch (i) {
        ROOT => {
            b.addBlob(v3(0, 0, -0.04 * W), v3(0.21 * W, 0.23 * W, 0.26 * W), 10, 7, HIDE);
            b.addBlob(v3(0.12 * W, 0.02 * W, 0.02 * W), v3(0.10 * W, 0.15 * W, 0.16 * W), 8, 6, HIDE_LT);
            b.addBlob(v3(-0.12 * W, 0.02 * W, 0.02 * W), v3(0.10 * W, 0.15 * W, 0.16 * W), 8, 6, HIDE_LT);
        },
        SPINE => {
            const off = mathx.subV(rest[CHEST], rest[SPINE]);
            const len = mathx.lenV(off);
            b.addCapsule(v3(0, 0, 0), off, 0.19 * W, 0.19 * W, 10, HIDE);
            b.addBlob(v3(0, 0.15 * W, len * 0.5), v3(0.12 * W, 0.05 * W, len * 0.44), 8, 5, HIDE_DK);
        },
        CHEST => {
            b.addBlob(v3(0, 0.01 * W, 0.05 * W), v3(0.23 * W, 0.25 * W, 0.24 * W), 11, 8, HIDE);
            b.addBlob(v3(0, -0.13 * W, 0.06 * W), v3(0.18 * W, 0.13 * W, 0.20 * W), 9, 6, HIDE_LT);
        },
        NECK => {
            const off = mathx.subV(rest[HEAD], rest[NECK]);
            const len = mathx.lenV(off);
            const dir = if (len > 1e-5) mathx.scaleV(off, 1.0 / len) else v3(0, 1, 0);
            b.addCapsule(v3(0, 0, 0), mathx.scaleV(dir, len * 0.96), 0.135 * W, 0.115 * W, 10, HIDE);
            var k: u32 = 0;
            while (k < 5) : (k += 1) {
                const a = @as(f32, @floatFromInt(k)) / 5.0 * std.math.tau + rng.range(-0.15, 0.15);
                const rr = 0.13 * W;
                const up = mathx.scaleV(dir, len * 0.86);
                b.addBlob(
                    v3(up.x + mathx.cosf(a) * rr, up.y + mathx.sinf(a) * rr * 0.8, up.z),
                    v3(0.045 * W * rng.range(0.8, 1.25), 0.045 * W, 0.075 * W * rng.range(0.85, 1.2)),
                    6,
                    4,
                    PETAL_BACK,
                );
            }
        },
        HEAD => {
            b.addBlob(v3(0, 0, 0.02 * W), v3(0.115 * W, 0.115 * W, 0.13 * W), 9, 7, PETAL_BACK);
            // THE THROAT, emissive, sunk most of the way in — relief is a few percent (`AGENTS.md`), and what
            // is wanted here is a glow out of a hollow rather than a proud ball. THREE SHELLS, deep to hot:
            // the deep one is the hole, the halo washes the petal bases so the light looks like it is coming
            // OUT of something, and the core is the only truly bright thing on the animal.
            b.addBlob(v3(0, 0, 0.055 * W), v3(0.105 * W, 0.105 * W, 0.045 * W), 9, 7, THROAT_HALO);
            b.addBlob(v3(0, 0, 0.085 * W), v3(0.078 * W, 0.078 * W, 0.050 * W), 8, 6, THROAT_DEEP);
            b.addBlob(v3(0, 0, 0.108 * W), v3(0.050 * W, 0.050 * W, 0.040 * W), 8, 6, THROAT);
            var k: u32 = 0;
            while (k < 6) : (k += 1) {
                const a = @as(f32, @floatFromInt(k)) / 6.0 * std.math.tau + rng.range(-0.25, 0.25);
                const rr = 0.040 * W * rng.range(0.7, 1.3);
                const len = 0.075 * W * rng.range(0.75, 1.3);
                b.addCapsule(
                    v3(mathx.cosf(a) * rr, mathx.sinf(a) * rr, 0.10 * W),
                    v3(mathx.cosf(a) * rr * 1.5, mathx.sinf(a) * rr * 1.5, 0.10 * W + len),
                    0.011 * W,
                    0.013 * W,
                    5,
                    STAMEN,
                );
            }
            petalFan(b, &rng, 1.0, PETALS_PER_SIDE);
            petalFan(b, &rng, -1.0, PETALS_PER_SIDE);
        },
        JAW => {
            petalFan(b, &rng, 1.0, 2);
            petalFan(b, &rng, -1.0, 2);
        },
        EARL, EARR => {
            const side: f32 = if (i == EARL) 1.0 else -1.0;
            petal(b, &rng, v3(0, 0, 0), side, 0.30 * W, 1.35);
        },
        TAIL0, TAIL1, TAIL2 => {
            const len: f32 = switch (i) {
                TAIL0 => mathx.lenV(mathx.subV(rest[TAIL0], rest[TAIL1])),
                TAIL1 => mathx.lenV(mathx.subV(rest[TAIL1], rest[TAIL2])),
                else => 0.16 * W,
            };
            const r0: f32 = 0.045 * W * (if (i == TAIL0) @as(f32, 1.0) else if (i == TAIL1) @as(f32, 0.8) else @as(f32, 0.62));
            b.addCapsule(v3(0, 0, 0), v3(0, -len * 0.35, -len * 0.9), r0, r0, 7, HIDE_DK);
        },
        else => buildLimbBone(b, i, rest, &rng),
    }
}

fn petal(b: *Builder, rng: *mathx.Rng, at: rl.Vector3, side: f32, len: f32, wide: f32) void {
    const l = len * rng.range(0.84, 1.16);
    const w = 0.075 * W * wide * rng.range(0.85, 1.15);
    const tipZ = at.z + l;
    b.addBlob(v3(at.x + side * w * 0.35, at.y, at.z + l * 0.5), v3(w, 0.016 * W, l * 0.52), 7, 4, PETAL_BACK);
    b.addBlob(v3(at.x + side * w * 0.35, at.y + 0.010 * W, at.z + l * 0.52), v3(w * 0.86, 0.012 * W, l * 0.46), 7, 4, PETAL);
    b.addBlob(v3(at.x + side * w * 0.5 + rng.range(-0.012, 0.012) * W, at.y + rng.range(-0.01, 0.01) * W, tipZ), v3(w * 0.55, 0.014 * W, 0.030 * W), 6, 4, PETAL_LT);
}

fn petalFan(b: *Builder, rng: *mathx.Rng, side: f32, n: u32) void {
    var k: u32 = 0;
    while (k < n) : (k += 1) {
        const t = (@as(f32, @floatFromInt(k)) + 0.5) / @as(f32, @floatFromInt(n));
        const a = side * (0.35 + t * 1.05) + rng.range(-0.10, 0.10);
        const rr = 0.085 * W;
        petal(
            b,
            rng,
            v3(mathx.cosf(a) * rr * side, mathx.sinf(a) * rr, 0.045 * W),
            side,
            0.20 * W,
            1.0,
        );
    }
}

/// THE LEGS, off the rest chain's own segment lengths so a resized animal cannot grow a leg the solver does
/// not believe in.
fn buildLimbBone(b: *Builder, i: usize, rest: [N]rl.Vector3, rng: *mathx.Rng) void {
    const child: ?usize = blk: {
        for (0..N) |c| {
            if (wolf.PARENT[c] == @as(i32, @intCast(i))) break :blk c;
        }
        break :blk null;
    };
    const len: f32 = if (child) |c| mathx.lenV(mathx.subV(rest[i], rest[c])) else 0.10 * W;
    const paw = child == null;
    if (paw) {
        b.addBlob(v3(0, -0.018 * W, 0.028 * W), v3(0.062 * W, 0.032 * W, 0.078 * W), 8, 5, HIDE_DK);
        var k: u32 = 0;
        while (k < 4) : (k += 1) {
            const x = (@as(f32, @floatFromInt(k)) - 1.5) * 0.030 * W;
            b.addCapsule(
                v3(x, -0.026 * W, 0.070 * W),
                v3(x + rng.range(-0.004, 0.004) * W, -0.030 * W, 0.098 * W),
                0.013 * W,
                0.008 * W,
                5,
                CLAW,
            );
        }
        return;
    }
    const upper = i == wolf.SHL or i == wolf.SHR or i == wolf.HIPL or i == wolf.HIPR;
    const r0: f32 = if (upper) 0.072 * W else 0.048 * W;
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), r0, r0, 8, if (upper) HIDE else HIDE_DK);
}

test "THE BLOOM IS THE TELL: shut while it stalks, fully open BEFORE the blow, and shut again after" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.openAmt(), 1e-6);

    r.state = .bite;
    r.t = BITE_WIND * OPEN_BY;
    try std.testing.expectApproxEqAbs(ATTACK_OPEN, r.openAmt(), 1e-3);
    r.t = BITE_WIND;
    try std.testing.expectApproxEqAbs(ATTACK_OPEN, r.openAmt(), 1e-6);
    r.t = BITE_WIND + BITE_STRIKE * 0.5;
    try std.testing.expectApproxEqAbs(ATTACK_OPEN, r.openAmt(), 1e-6);

    r.t = BITE_WIND + BITE_STRIKE + BITE_RECOVER * SHUT_BY * 0.5;
    const half = r.openAmt();
    try std.testing.expect(half > 0.05 and half < ATTACK_OPEN * 0.95);
    r.t = BITE_WIND + BITE_STRIKE + BITE_RECOVER;
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.openAmt(), 1e-6);

    try std.testing.expect(BITE_WIND >= foe.TELL_MIN);
    try std.testing.expect(BITE_WIND * OPEN_BY >= foe.TELL_MIN * 0.6);
}

test "THE GATHER THREATENS AND THE STRIKE CUTS — the blow lands inside that window and nowhere else" {
    const hero = mathx.ground(0, 1.2);
    const dt: f32 = 1.0 / 60.0;
    for ([_]f32{ 0, BITE_WIND * 0.5, BITE_WIND - 2 * dt }) |at| {
        var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
        r.state = .bite;
        r.t = at - dt;
        _ = r.update(dt, hero, 200.0, .{});
        try std.testing.expect(r.heroHit == null);
    }
    var hit = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    hit.state = .bite;
    hit.t = BITE_WIND;
    try std.testing.expect(hit.update(dt, hero, 200.0, .{}) != null);
    var done = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    done.state = .bite;
    done.t = BITE_WIND + BITE_STRIKE;
    try std.testing.expect(done.update(dt, hero, 200.0, .{}) == null);
}

test "IT LEAVES THE EARTH, and the body drawn in the air is the body the terrain gate agrees is airborne" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(!r.airborne());
    r.stagePounce(1.0);
    try std.testing.expect(r.leapLift() > foe.AIRBORNE_LIFT);
    try std.testing.expect(r.airborne()); // the one reads the other, so they cannot disagree
    r.t = BITE_WIND + BITE_STRIKE;
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.leapLift(), 1e-6);
    try std.testing.expect(!r.airborne());
}

test "THE BLOOM RAKES DOWN THROUGH HIM — it rears above his head and the DIVE brings it into his column" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    r.pose();
    const rest = r.jawPoint().y - r.pos.y + BLOOM_R;
    r.state = .bite;
    r.t = BITE_WIND - 1e-4;
    r.pounce = 1.0;
    r.pose();
    const reared = r.jawPoint().y - r.pos.y;
    r.t = BITE_WIND + BITE_STRIKE * DIVE_BY;
    r.pose();
    const struck = r.jawPoint().y - r.pos.y;
    std.debug.print("\n  ravager bloom: {d:.2} m standing, {d:.2} m reared, {d:.2} m at the strike (hero {d:.2}..{d:.2})\n", .{
        rest, reared, struck, foe.HERO_LOW, foe.HERO_HIGH,
    });
    try std.testing.expect(reared > foe.HERO_HIGH);
    try std.testing.expect(struck + BLOOM_R > foe.HERO_LOW);
    try std.testing.expect(struck - BLOOM_R < foe.HERO_HIGH);
    try std.testing.expect(struck < reared - 0.6);
}

test "IT IS A FOE, NOT A SPIRIT — its own tether, its own souls, and it answers for its own kind" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectEqual(wf.FoeKind.florid_ravager, r.kind());
    try std.testing.expect(r.alive() and !r.dying() and !r.staggered());
    // The contract's accessors all answer off ONE body, so a bar anchored on one and a reticle on another
    // cannot drift: the hurt sphere has to contain the mark.
    try std.testing.expect(r.hurtRadius() > r.bodyR());
    try std.testing.expect(r.topWorld().y > r.centerWorld().y);
    const markOut = mathx.lenV(mathx.subV(r.centerWorld(), r.lockPoint()));
    std.debug.print("\n  ravager mark stands {d:.2} m off the hurt centre (sphere r {d:.2}, body r {d:.2})\n", .{ markOut, r.hurtRadius(), r.bodyR() });
    try std.testing.expect(markOut < r.hurtRadius());
    r.stageGather(1.0);
    const reared = mathx.lenV(mathx.subV(r.centerWorld(), r.lockPoint()));
    try std.testing.expect(reared < r.hurtRadius());
    std.debug.print("  …and {d:.2} m reared, where the bloom's own mark stood {d:.2} m out\n", .{ reared, mathx.lenV(mathx.subV(r.centerWorld(), foe.markOn(r.xf[HEAD], v3(0, 0.06 * W, 0.04 * W)))) });
    _ = r.vit.hit(.{ .dmg = 5, .poise = POISE_MAX + 1 });
    r.debugStagger(true);
    try std.testing.expect(r.staggered());
    r.vit.hp = 0;
    r.enterDeath();
    try std.testing.expect(r.dying() and r.justDied);
}

test "A LIGHT POKE DOES NOT FLINCH IT AND A HEAVY DOES — poise sized against the hero's own two swings" {
    var light = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectEqual(combat.HitResult.none, light.vit.hit(heromod.ATK_LIGHT_HIT));
    var heavy = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectEqual(combat.HitResult.light, heavy.vit.hit(heromod.ATK_HEAVY_HIT));
}

test "PLANT FLESH: fire is the answer to it and cold is not" {
    var burnt = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    var frozen = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    const fire = combat.Hit{ .elem = combat.elems(.{ .fire = 20 }) };
    const cold = combat.Hit{ .elem = combat.elems(.{ .cold = 20 }) };
    try std.testing.expect(burnt.vit.damageFrom(fire) > 20.0);
    try std.testing.expect(frozen.vit.damageFrom(cold) < 20.0);
    try std.testing.expect(burnt.vit.damageFrom(fire) > frozen.vit.damageFrom(cold));
}

test "THE LEAP IS COMMITTED AT THE LAUNCH — it aims while the bloom opens and steers not at all after" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    r.state = .bite;
    r.t = 0;
    const side = mathx.ground(6, 0);
    var t: f32 = 0;
    while (t < BITE_WIND - 0.02) : (t += 1.0 / 60.0) _ = r.update(1.0 / 60.0, side, 200.0, .{});
    const aimed = r.facing;
    try std.testing.expect(@abs(mathx.wrapPi(aimed - mathx.headingXZ(mathx.dirXZ(r.pos, side)))) < 0.5);
    const behind = mathx.ground(-8, -6);
    while (t < BITE_WIND + BITE_STRIKE) : (t += 1.0 / 60.0) {
        _ = r.update(1.0 / 60.0, behind, 200.0, .{});
        try std.testing.expectApproxEqAbs(aimed, r.facing, 1e-5);
    }
}

test "STEERING IS ONLY THE TRAVEL STATE — a heading bent under a committed leap aims the blow at the wall" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = mathx.ground(0, 3);
    r.leash.noteSeen();
    try std.testing.expect(r.navWant(hero) != null);
    r.state = .bite;
    try std.testing.expect(r.navWant(hero) == null);
    r.state = .hurt;
    try std.testing.expect(r.navWant(hero) == null);
    r.state = .dead;
    try std.testing.expect(r.navWant(hero) == null);
}

test "IT CAN ACTUALLY HURT HIM — a foe lands a blow by RETURNING one, and one leap lands exactly one" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = mathx.ground(0, 1.2);
    r.leash.noteSeen();
    var landed: usize = 0;
    var t: f32 = 0;
    var opened = false;
    while (t < 4.0) : (t += 1.0 / 60.0) {
        if (r.update(1.0 / 60.0, hero, 200.0, .{})) |h| {
            landed += 1;
            try std.testing.expectApproxEqAbs(BITE_HIT.dmg, h.dmg, 1e-4);
        }
        if (r.opened) opened = true;
        if (landed > 0 and r.state != .bite) break;
    }
    try std.testing.expect(opened);
    try std.testing.expectEqual(@as(usize, 1), landed);
}

test "A LEAP THAT WENT PAST HIM DOES NOT BITE HIM IN THE BACK OF THE NECK" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    r.state = .bite;
    r.t = BITE_WIND;
    r.tryBite(mathx.ground(0, -1.2));
    try std.testing.expect(r.heroHit == null);
    r.tryBite(mathx.ground(0, BITE_R + foe.HERO_REACH + 0.6));
    try std.testing.expect(r.heroHit == null);
    r.tryBite(mathx.ground(0, 1.2));
    try std.testing.expect(r.heroHit != null);
}

test "THE INCOMING LATCH IS NOT THE OUTGOING ONE — one swing of his may not wound the same body twice" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    const swing = foe.Blade{
        .active = true,
        .r = 0.3,
        .a = v3(0, 0.8, -1.0),
        .b = v3(0, 0.8, 1.0),
        .a0 = v3(0, 0.8, -1.0),
        .b0 = v3(0, 0.8, 1.0),
        .hit = .{ .dmg = 6, .poise = 2 },
    };
    r.tryHit(swing);
    try std.testing.expectEqual(@as(u32, 1), r.hits);
    r.tryHit(swing);
    try std.testing.expectEqual(@as(u32, 1), r.hits);
    // …and its own leap's clock may not clear that latch — it clears `heroLatch`, which is a different fact.
    // The SAME swing is still live across the frame, so it stays one wound.
    r.state = .bite;
    r.t = BITE_WIND + BITE_STRIKE + BITE_RECOVER;
    _ = r.update(1.0 / 60.0, mathx.ground(0, 40), 200.0, swing);
    try std.testing.expectEqual(@as(u32, 1), r.hits);
    _ = r.update(1.0 / 60.0, mathx.ground(0, 40), 200.0, .{});
    r.tryHit(swing);
    try std.testing.expectEqual(@as(u32, 2), r.hits);
}

test "HIS SWORD CAN ACTUALLY REACH IT — the blade is taken on every live state, not discarded" {
    const swing = foe.Blade{
        .active = true,
        .r = 0.35,
        .a = v3(0, 0.8, -1.2),
        .b = v3(0, 0.8, 1.2),
        .a0 = v3(0, 0.8, -1.2),
        .b0 = v3(0, 0.8, 1.2),
        .hit = .{ .dmg = 7, .poise = 3 },
    };
    for ([_]State{ .idle, .move, .bite, .hurt }) |st| {
        var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
        r.state = st;
        r.t = if (st == .bite) BITE_WIND * 0.5 else 0;
        _ = r.update(1.0 / 60.0, mathx.ground(0, 30), 200.0, swing);
        try std.testing.expectEqual(@as(u32, 1), r.hits);
        try std.testing.expect(r.vit.hp < HP_MAX);
    }
}

test "THE BLOOM IS WIDE WHEN HE IS NEAR AND WIDER WHEN IT LEAPS — two tiers, and neither is a switch" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    const dt: f32 = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < 2.0) : (t += dt) _ = r.update(dt, mathx.ground(0, NEAR_FAR + 6), 200.0, .{});
    try std.testing.expect(r.openAmt() < 0.05);

    var last = r.openAmt();
    var worst: f32 = 0;
    t = 0;
    while (t < 3.0) : (t += dt) {
        r.pos = mathx.zero3;
        r.state = .idle;
        _ = r.update(dt, mathx.ground(0, NEAR_WIDE), 200.0, .{});
        worst = @max(worst, @abs(r.openAmt() - last));
        last = r.openAmt();
    }
    const near = r.openAmt();
    try std.testing.expect(near > 0.9);
    try std.testing.expect(worst < 0.09);

    r.stagePounce(1.0);
    try std.testing.expect(r.openAmt() > near * 1.3);
    try std.testing.expectApproxEqAbs(ATTACK_OPEN, r.openAmt(), 1e-3);
    // The gape opens FROM where it already was, so choosing the leap cannot shut it for a frame first.
    r.state = .bite;
    r.t = 0;
    try std.testing.expectApproxEqAbs(near, r.openAmt(), 1e-3);
}

test "A DEAD ONE SHUTS — from across a field that is most of what says it is finished" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    const dt: f32 = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < 3.0) : (t += dt) _ = r.update(dt, mathx.ground(0, NEAR_WIDE), 200.0, .{});
    try std.testing.expect(r.openAmt() > 0.9);
    r.enterDeath();
    t = 0;
    while (t < 2.0) : (t += dt) _ = r.update(dt, mathx.ground(0, NEAR_WIDE), 200.0, .{});
    try std.testing.expect(r.openAmt() < 0.05);
}

test "…AND IN DEGREES, which is what the player is actually reading off the head" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    const dt: f32 = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < 3.0) : (t += dt) {
        r.pos = mathx.zero3;
        r.state = .idle;
        _ = r.update(dt, mathx.ground(0, NEAR_WIDE), 200.0, .{});
    }
    const near = r.openAmt();
    r.stagePounce(1.0);
    const atk = r.openAmt();
    std.debug.print("\n  ravager bloom: shut 0 deg | near {d:.0} deg gape, {d:.0} splay | attack {d:.0} deg gape, {d:.0} splay\n", .{
        PETAL_GAPE * near, PETAL_SPLAY * near, PETAL_GAPE * atk, PETAL_SPLAY * atk,
    });
    try std.testing.expect(PETAL_GAPE * near > 40.0);
    try std.testing.expect(PETAL_GAPE * atk > PETAL_GAPE * near + 15.0);
}

test "A GIRAFFE FLOWER, NOT A DOG — the neck is long, upright, and it stretches with the bloom" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    r.pose();
    const rest = restPose();
    const withers = rest[CHEST].y;
    const head = rest[HEAD].y;
    const out = rest[HEAD].z - rest[CHEST].z;
    std.debug.print("\n  ravager neck: withers {d:.2} m, head {d:.2} m ({d:.2}x), forward {d:.2} m\n", .{ withers, head, head / withers, out });
    try std.testing.expect(head > withers * 1.5);
    try std.testing.expect(out < (head - withers) * 0.5);

    const shut = r.jawPoint().y;
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.stretchAmt(), 1e-6);
    r.stagePounce(1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), r.stretchAmt(), 1e-6);
    const outAt = r.jawPoint().y;
    std.debug.print("  …bloom at {d:.2} m shut, {d:.2} m reaching (leap included)\n", .{ shut, outAt });
    try std.testing.expect(outAt > shut);
    try std.testing.expect(NECK_STRETCH > 0.1 and NECK_STRETCH < 0.4);
}
