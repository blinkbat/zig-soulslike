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

// THE BLINKBAT (owner's creature, owner's brief) — large, weirdly humanoid, a flyer, and **IT IS NEVER WHERE
// YOU LAST HIT IT**. It BLINKS in on your flank, takes one bite, and blinks back out to a ring. Hit and run.
//
// **THE BLINK IS THE TRAVEL AND THE BITE IS THE POINT.** Nothing about it closes ground: it does not chase, it
// does not circle, it does not walk. It hangs at `BLINK_FAR`, disappears, and reappears inside its own reach.
// You cannot back away from a thing that does not travel, so the fight is not about distance at all — it is
// about the ARRIVAL, which is the longest thing it does (`BLINK_IN` 0.30 s of a body fading back in, and then
// `BITE_WIND` on top before the jaws move).
//
// **IT IS A VAMPIRE, SO A BITE THAT DRAWS BLOOD IS THE ONLY THING THAT FEEDS IT.** The bite is an ordinary
// `foe.Blow` — blockable, parryable, carrying where it came from. What it does with that blow is the creature:
// a bite that LANDS puts it into `.feed`, PLANTED, drinking `DRAIN_SHARE` of what it took over `FEED_DUR`.
//   - **A SHIELD DENIES THE HEAL OUTRIGHT** — no blood, no feed, and it recoils off the boards instead.
//   - **AND THE FEED IS INTERRUPTIBLE**, which is the whole answer to a healer: it is planted, it cannot blink,
//     it is paying the heal by the SECOND rather than banking it, and its poise is the lowest of anything this
//     large. Stagger it and the rest of the drink is gone.
// **AND THAT IS NOT INPUT READING.** `fedOn` is stamped by `game.zig` off `heroTakes`' own outcome — whether
// this creature's jaws drew blood, which is a fact about the world and about ITS OWN BLOW. It never learns that
// a button was pressed; it learns that it bit something hard (`foe.zig`'s cross-cutting-state law, and the same
// shape the leechfly's drink and the fishman's snare already take).
//
// **WHAT IT IS NOT** is the leechfly. That one answers a sword by CLIMBING — it goes where the blade is not, and
// the trade is your bow against its altitude. This one stays in reach the whole time and answers a sword by not
// being there when it lands. Two flyers, two different refusals, and neither is the other's dial.
//
// **FIRE IS THE COUNTER.** The wing is a stretched membrane and it is the biggest surface on the field.

pub const H: f32 = 2.35;
const HIP_HALF = heromod.HIP_HALF * 0.86;
/// Broad across the shoulders and narrow at the hip: the whole mass is chest, because the whole animal is a
/// pair of wings with a man hung off them.
const SHOULDER_HALF = heromod.SHOULDER_HALF * 1.26;

/// **THE ARMS ARE THE WINGS** — which is what "weirdly humanoid" is: the hero's own 18-bone scaffold with the
/// forearm drawn out to nearly twice its length and a membrane stretched off it. Not one joint is invented.
const UPPER_LEN: f32 = 0.255;
const FORE_LEN: f32 = 0.395;

const N = heromod.N + 3;
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
/// Bone 17 is the hero's held-weapon slot. This thing carries nothing — `Model.draw` skips it.
const HELD = heromod.HELD;

/// **THE THREE THE MAN HAS NO USE FOR.** Appended ABOVE the scaffold's 18, so every index the shared rig solves
/// is where it was. The JAW is the bite's own tell and the EARS are the character: a face that is mostly ear.
const JAW = heromod.N + 0;
const EARL = heromod.N + 1;
const EARR = heromod.N + 2;

const PARENT = heromod.PARENT ++ [_]i32{ SKULL, SKULL, SKULL };

comptime {
    std.debug.assert(PARENT.len == N);
    std.debug.assert(FORE_LEN > UPPER_LEN);
}

fn restPose() [N]rl.Vector3 {
    var r: [N]rl.Vector3 = undefined;
    const base = heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);
    for (base, 0..) |p, i| r[i] = p;
    // The scaffold hangs a man's arm; this one is a spar. Both sides re-cut off the SHOULDER so the shared
    // `restHumanoid` stays the one place a joint layout is written down.
    r[ELL] = v3(base[SHL].x, base[SHL].y - UPPER_LEN * H, 0);
    r[WRL] = v3(base[SHL].x, r[ELL].y - FORE_LEN * H, 0);
    r[ELR] = v3(base[SHR].x, base[SHR].y - UPPER_LEN * H, 0);
    r[WRR] = v3(base[SHR].x, r[ELR].y - FORE_LEN * H, 0);
    r[HELD] = r[WRR];
    const sk = base[SKULL];
    r[JAW] = v3(0, sk.y - 0.030 * H, sk.z + 0.052 * H);
    r[EARL] = v3(0.046 * H, sk.y + 0.040 * H, -0.012 * H);
    r[EARR] = v3(-0.046 * H, sk.y + 0.040 * H, -0.012 * H);
    return r;
}

const REST = restPose();

fn setLocal(wx: *[N]rl.Matrix, i: usize, rest: [N]rl.Vector3, animRot: rl.Matrix) void {
    heromod.setJoint(wx, &rest, i, @intCast(PARENT[i]), animRot);
}

pub const AGGRO_R: f32 = 18.0;
const HOME_R: f32 = 3.0;

/// **`pos.y` IS THE GROUND UNDER IT AND `hover` IS WHAT IT FLIES ABOVE THAT** (the leechfly's law) — every world
/// point it owns is measured off `pos.y + hover * scale`, so one hanging over a bank keeps its bar over its own
/// head instead of down in the field.
const HOVER_BITE: f32 = 1.02;
const HOVER_IDLE: f32 = 2.05;
const HOVER_WAIT: f32 = 2.60;
const HOVER_RATE: f32 = 5.4;

// **IT DOES NOT CLIMB OUT OF REACH** — that is the leechfly's answer and this one may not borrow it, or the two
// flyers are one creature. The whole band sits under a swing off a 1.8 m man's shoulder.
comptime {
    std.debug.assert(HOVER_WAIT < 3.2);
    std.debug.assert(HOVER_BITE < HOVER_IDLE and HOVER_IDLE < HOVER_WAIT);
}

const BLINK_OUT: f32 = 0.20;
const BLINK_IN: f32 = 0.30;
const BLINK_CD: f32 = 2.40;
/// Where it puts itself down for a pass, and where it withdraws to. **BOTH ARE MEASURED FROM THE QUARRY'S HIDE**
/// (`wolf.triggerR`'s law): asked centre-to-centre a flat radius is unsatisfiable on anything broad.
const BLINK_NEAR: f32 = 1.62;
const BLINK_FAR: f32 = 6.40;
/// How far round the quarry a pass lands — never in front, or the arrival is a thing you were already looking at.
const BLINK_ARC_MIN: f32 = 88.0;
const BLINK_ARC_MAX: f32 = 168.0;

const BITE_WIND: f32 = 0.44;
const BITE_STRIKE: f32 = 0.13;
const BITE_RECOVER: f32 = 0.46;
const BITE_R: f32 = 2.05;
const BITE_FRONT_DOT: f32 = 0.34;

/// Seconds it hangs at the ring doing nothing between passes. The lull IS the reposition window, and it is the
/// only ground the fight gives you.
const WAIT_MIN: f32 = 0.55;
const WAIT_MAX: f32 = 1.15;

/// **THE DRINK IS PAID BY THE SECOND, NEVER BANKED** — an interrupted feed loses the rest, which is what makes
/// staggering it the answer rather than a nicety.
const FEED_DUR: f32 = 1.50;
const DRAIN_SHARE: f32 = 0.90;
/// After it has fed it cannot vanish for this long — the drink is bought with the escape.
const FEED_BLINK_LOCK: f32 = 0.85;

const HP_MAX: f32 = 138;
/// **THE LOWEST POISE OF ANYTHING THIS LARGE, ON PURPOSE.** A healer that could not be interrupted would be a
/// healer with no answer; a light stroke has to be able to take the drink off it.
const POISE_MAX: f32 = 13;
const STANCE_MAX: f32 = 30;
const RESISTS = combat.resists(.{ .fire = -55, .cold = 20, .lightning = -15, .chaos = 15 });
pub const SOULS: u32 = 265;

/// Five bites fill the bleed meter, solved rather than picked (`item.ENVENOMED`'s idiom).
const BITE_BLEED: f32 = combat.ailRow(.bleed).max / 5.0;

pub const BITE_HIT = combat.Hit{
    .dmg = 22,
    .poise = 13,
    .stance = 15,
    .dose = combat.Doses.one(.bleed, BITE_BLEED),
};

const SHOVE = foe.Push{ .light = 0.80, .heavy = 1.75 };
const TURN_RATE: f32 = 2.6;
const DRIFT_SPEED: f32 = 1.35;
const ACCEL: f32 = 5.0;
const SHOVE_DECAY: f32 = 7.0;

const DEATH_DUR: f32 = 1.05;
const DISS_DUR: f32 = 1.00;

const BODY_R: f32 = 0.52;
const HURT_R: f32 = 0.86;
const CENTER_F: f32 = 0.40;
const TOP_F: f32 = 0.96;

const WING_HZ_HOVER: f32 = 3.4;
const WING_HZ_BEAT: f32 = 7.2;

comptime {
    std.debug.assert(BITE_WIND > foe.TELL_MIN);
    // **THE WITHDRAWAL HAS TO LEAVE REACH**, or "hit and run" is a body standing in your swing.
    std.debug.assert(BLINK_FAR > BITE_R + 2.0);
    // …and the arrival has to be INSIDE it, or the gather is spent closing and the bite whiffs on its own.
    std.debug.assert(BLINK_NEAR + foe.HERO_R < BITE_R);
    // A pass costs more than the drink it buys, so a bat that lands every bite still cannot out-heal a fight.
    std.debug.assert(BLINK_OUT + BLINK_IN + BITE_WIND + BITE_STRIKE + BITE_RECOVER > FEED_DUR);
}

// **AUTHOR DARK, AND SOLVE IT OFF A SAMPLED RENDER RATHER THAN BY EYE** (the ravager's lesson, AGENTS.md).
// Screen goes as albedo^(1/2.2) through a x1.72 key: at the (46, 34, 40) this was first written on, the lit
// torso SAMPLED 135,108,102 against a field of 99,102,64 — a nocturnal animal reading BRIGHTER and PINKER
// than the grass it hangs over. Wanted ~85 on screen, i.e. (85/135)^2.2 = 0.36 of the albedo.
// **AND IT SEPARATES ON HUE AS WELL AS VALUE**: everything outdoors here is warm, so the hide runs COLD
// (blue over red) and the one warm thing on the animal is the membrane it flies on.
const HIDE = rgba(13, 11, 17, 255);
const HIDE_DK = rgba(8, 7, 11, 255);
const MEMBRANE = rgba(26, 14, 16, 255);
const MEMBRANE_DK = rgba(17, 9, 11, 255);
const SNOUT = rgba(30, 19, 19, 255);
// Small and proud, so these are the only things allowed near the top of the range — and still under the 148
// where the chain clips to white.
const FANG = rgba(138, 132, 118, 255);
const CLAW = rgba(96, 90, 82, 255);
/// Literal screen values — drawn unlit over the opaque pass, where a mesh colour would be an albedo.
const EYE = rgba(228, 74, 62, 255);
const MOTE = rgba(150, 92, 128, 255);
const RIFT = rgba(126, 78, 150, 255);

const DISSOLVE = foe.Dissolve{ .rate = 48.0, .spread = 0.95, .rise = 0.82, .flake = MEMBRANE_DK };
const CHIP_SPRAY = foe.Spray{
    .fanLo = 0.20,
    .fanHi = 0.95,
    .upLo = 0.10,
    .upHi = 0.80,
    .lifeLo = 0.24,
    .lifeHi = 0.52,
    .rLo = 0.022,
    .rHi = 0.050,
    .r1 = 0.014,
    .col = MEMBRANE,
    .col1 = MEMBRANE_DK,
    .grav = 5.0,
};
const CHIP_LIGHT: i32 = 9;
const CHIP_HEAVY: i32 = 18;
const CHIP_DEATH: i32 = 26;
const PARTS: usize = 96;

const State = enum { hang, wait, blinkout, blinkin, wind, strike, recover, feed, repelled, stunlight, stunheavy, dead };

const Choice = enum { blink, bite, drift, hold, rest };

/// **THE WHOLE DECISION, AND IT READS FIVE NUMBERS** — a distance, a distance home, two clocks and whether the
/// roots have it. No hero state reaches this function, which is what makes NO INPUT READING checkable rather
/// than asserted (`foe.zig`'s law), and pure over its arguments, which is what makes it testable at all.
fn classify(sensed: f32, gap: f32, homeGap: f32, blinkReady: bool, rooted: bool, spent: bool) Choice {
    if (sensed > AGGRO_R) return if (homeGap > HOME_R) .hold else .rest;
    // **IT DOES NOT TAKE TWO BITES FROM ONE SPOT.** Measured before this existed: 20 s stood in its face was 6
    // bites and ZERO blinks — the creature was a slow leechfly and the whole run half of hit-and-run was dead
    // code, because nothing ever asked it to leave a place it could still reach from.
    // …and while it is spent it does not bite AT ALL: it goes if it can, and hangs there waiting to if it
    // cannot. That wait is the reposition window, and gating only the blink left it chewing through the
    // `FEED_BLINK_LOCK` it had just bought — two bites off one spot, which is the thing this rule forbids.
    if (spent and !rooted) return if (blinkReady) .blink else .rest;
    if (gap <= BITE_R) return .bite;
    // **ROOTED IT CANNOT VANISH, SO IT HAS TO FLY THE DISTANCE LIKE ANYTHING ELSE** — which is the only time
    // this creature is ever chaseable, and it is what a rod buys.
    if (!blinkReady or rooted) return .drift;
    return .blink;
}


pub const Model = struct {
    bone: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        return .{ .bone = buildBones(), .mat = gfx.material(shader, "blinkbat") };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, b: *const Bat) void {
        // HALFWAY THROUGH A BLINK THERE IS NOTHING TO DRAW — `thin` is what the rift replaces.
        if (b.thin >= 0.999) return;
        for (0..N) |i| {
            if (i == HELD) continue;
            rl.drawMesh(self.bone[i], self.mat, b.xf[i]);
        }
    }
};

pub const Bat = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// **THE FIELD A UNIT OWES ITS ORDERS** (`foe.Post`), stamped at spawn off the map's `ai=` and `wp=`.
    post: foe.Post = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    threat: foe.Threat = .{},

    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,

    state: State = .hang,
    t: f32 = 0,
    elapsed: f32 = 0,
    blinkCd: f32 = 0,
    waitFor: f32 = 0,
    speed: f32 = 0,

    /// Metres off the ground under it. The one field that makes this a flyer.
    hover: f32 = HOVER_IDLE,
    hoverTo: f32 = HOVER_IDLE,
    /// 0 solid, 1 gone. The blink's own fade, and what `Model.draw` reads.
    thin: f32 = 0,
    /// Where the current blink is putting it down. **COMMITTED AT `blinkout`**, so an arrival cannot chase a
    /// quarry that moved during the fade — that would read as a lunge rather than as a place it went to.
    blinkTo: rl.Vector3 = mathx.zero3,
    /// True while the committed blink is a PASS at the quarry rather than a withdrawal to the ring.
    blinkNear: bool = false,
    /// Which way round the quarry it works. Kept between passes so a bat does not saw back and forth.
    arcSign: f32 = 1,
    /// **THE PASS IS SPENT** — it has bitten from here, so wherever it stands is somewhere it is leaving.
    /// Cleared at the launch of the blink that takes it away, and by a stagger, which ends the pass for it.
    spent: bool = false,
    wingPhase: f32 = 0,
    jawOpen: f32 = 0,

    /// How much blood is still to come out of the current drink, and how fast. Set by `fedOn`, spent by `.feed`.
    drinkLeft: f32 = 0,
    /// 0 empty, 1 gorged. Cosmetic only — the belly fills and the eyes come up.
    gorge: f32 = 0,
    /// One-frame, read by the group after `update`: this bat's jaws closed on something this frame.
    bit: bool = false,
    /// One-frame: it started a drink. `game` sizes the beat off it.
    drank: bool = false,

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
    rest: [N]rl.Vector3 = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Bat {
        var b = Bat{ .pos = home, .home = home, .facing = faceYaw, .scale = scale, .seed = seed };
        b.rest = REST;
        b.fxRng = foe.fxStream(seed, 51217.0, 0xBA7);
        b.aiRng = foe.fxStream(seed, 27361.0, 17);
        b.blinkCd = seed * BLINK_CD;
        b.arcSign = if (seed < 0.5) 1 else -1;
        b.wingPhase = seed;
        b.pose();
        return b;
    }

    fn lift(self: *const Bat) f32 {
        return self.hover * self.scale;
    }
    pub fn centerWorld(self: *const Bat) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H, self.scale, self.lift());
    }
    pub fn lockPoint(self: *const Bat) rl.Vector3 {
        return foe.markOn(self.xf[CHEST], v3(0, 0, 0));
    }
    pub fn topWorld(self: *const Bat) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * H, self.scale, self.lift());
    }
    pub fn hurtRadius(self: *const Bat) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Bat) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Bat) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Bat) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Bat) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .repelled or self.state == .dead;
    }
    /// **ALWAYS TRUE** — it never lands. Nothing on the ground shoulders it, the terrain riser rule never
    /// applies, and it is never steered (`game.gateTerrain`'s `airborne` skip: the probe is a rule for FEET).
    pub fn airborne(self: *const Bat) bool {
        return !self.gone;
    }
    pub fn flashFrac(self: *const Bat) f32 {
        return foe.flashFrac(self.flash);
    }
    pub fn kind(_: *const Bat) wf.FoeKind {
        return .blinkbat;
    }

    /// **MIDWAY THROUGH A BLINK IT IS NOWHERE**, so there is nothing to lock on to and nothing to hit — the
    /// swept test refuses it because `hurtRadius` has gone with the body (`hidden` is the Rooted's predicate,
    /// found by `@hasDecl` in `game.disguised`).
    pub fn hidden(self: *const Bat) bool {
        return self.thin >= 0.5;
    }

    /// **HEAD DOWN IS HEAD DOWN** (the rotgorger's rule, on a body that flies): drinking it does not track, does
    /// not turn, and cannot vanish. That is what makes letting it feed a real cost and not a formality.
    pub fn feeding(self: *const Bat) bool {
        return self.state == .feed;
    }

    pub fn update(self: *Bat, dt: f32, quarry: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.heroHit = null;
        self.bit = false;
        self.drank = false;
        self.justDied = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.vit.tick(dt);
        self.elapsed += dt;
        self.t += dt;
        self.blinkCd = mathx.maxF(0, self.blinkCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, foe.tetherFor(self), quarry, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        switch (self.state) {
            .dead => {
                self.speed = 0;
                self.hoverTo = 0;
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
            .stunlight, .stunheavy => {
                // A SWATTED BAT DROPS (the leechfly's rule) — the stun pulls the hover down and it climbs back.
                self.hoverTo = HOVER_BITE * 0.72;
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                if (self.t >= combat.foeStunDur(self.state == .stunheavy)) self.enter(.hang);
            },
            .repelled => {
                // **A BITE THE BOARDS ATE THROWS IT BACK** and it hangs there, open, for as long as the wind
                // it wasted. No feed, and no free exit either.
                self.hoverTo = HOVER_IDLE;
                self.speed = approach(self.speed, 0, ACCEL * 2.4 * dt);
                self.driftAway(quarry, dt, bounds);
                if (self.t >= BITE_WIND) self.enter(.hang);
            },
            .blinkout => {
                self.thin = mathx.clampF(self.t / BLINK_OUT, 0, 1);
                self.hoverTo = HOVER_IDLE;
                if (self.t >= BLINK_OUT) {
                    self.pos.x = self.blinkTo.x;
                    self.pos.z = self.blinkTo.z;
                    // **THE ONE MOVER THAT WRITES `pos` INSTEAD OF STEPPING IT**, so it is the one that has to
                    // ask the bounds itself: `mathx.stepXZ` clamps every other metre travelled in this game,
                    // and a mark taken off a quarry at the edge stands up to `BLINK_FAR` outside the square.
                    mathx.holdXZ(&self.pos, bounds);
                    self.faceNow(quarry);
                    self.enter(.blinkin);
                    self.rift();
                }
            },
            .blinkin => {
                self.thin = 1.0 - mathx.clampF(self.t / BLINK_IN, 0, 1);
                self.hoverTo = if (self.wantsPass()) HOVER_BITE else HOVER_WAIT;
                self.faceToward(quarry, dt);
                if (self.t >= BLINK_IN) {
                    self.thin = 0;
                    if (self.wantsPass()) {
                        self.enter(.wind);
                        sfx.world(.shade_gather, self.pos);
                    } else {
                        self.waitFor = self.aiRng.range(WAIT_MIN, WAIT_MAX);
                        self.enter(.wait);
                    }
                }
            },
            .wait => {
                self.hoverTo = HOVER_WAIT;
                self.speed = approach(self.speed, 0, ACCEL * dt);
                self.faceToward(quarry, dt);
                if (self.t >= self.waitFor) self.enter(.hang);
            },
            .wind => {
                self.hoverTo = HOVER_BITE;
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                // **THE GATHER AIMS AND THE COMMIT DOES NOT** (the knight's law) — once the jaws move it is
                // pointed where it was pointed, so a sidestep off the arrival beats it.
                self.faceToward(quarry, dt);
                self.jawOpen = mathx.smoothstep(0, BITE_WIND, self.t);
                if (self.t >= BITE_WIND) {
                    self.heroLatch = false;
                    self.enter(.strike);
                    sfx.world(.leech_stab, self.pos);
                }
            },
            .strike => {
                self.hoverTo = HOVER_BITE;
                self.tryBite(quarry);
                if (self.t >= BITE_STRIKE) self.enter(.recover);
            },
            .recover => {
                self.hoverTo = HOVER_IDLE;
                self.speed = approach(self.speed, 0, ACCEL * dt);
                // A MISS IS THE ONE OUTCOME IT WALKS AWAY FROM CLEAN — but it still walks away.
                if (self.t >= BITE_RECOVER) {
                    self.spent = true;
                    self.enter(.hang);
                }
            },
            .feed => {
                self.hoverTo = HOVER_BITE;
                self.speed = 0;
                const sip = mathx.minF(self.drinkLeft, (DRAIN_SHARE * BITE_HIT.dmg / FEED_DUR) * dt);
                if (sip > 0) {
                    _ = self.vit.heal(sip);
                    self.drinkLeft -= sip;
                    self.gorge = mathx.minF(1.0, self.gorge + dt / FEED_DUR);
                }
                self.emitDrink(dt);
                if (self.t >= FEED_DUR or self.drinkLeft <= 0) {
                    self.spent = true;
                    self.enter(.hang);
                }
            },
            .hang => {
                const sensed = foe.senseHero(&self.leash, self.pos, quarry, AGGRO_R);
                const gap = mathx.maxF(0, sensed - foe.HERO_R - self.bodyR());
                const homeGap = mathx.distXZ(self.pos, self.home);
                self.hoverTo = HOVER_IDLE;
                switch (classify(sensed, gap, homeGap, self.blinkCd <= 0, !foe.canLeap(&self.root), self.spent)) {
                    .rest => {
                        // **IT DRIFTS ITS ROUND RATHER THAN BLINKING IT** (`foe.postWant`). The blink is what
                        // it spends on a FLANK — a bat that teleported its way round a patrol would have no
                        // tell left for the one move that matters, and its own `travel` is already this drift.
                        if (foe.postWant(self, dt, sensed, AGGRO_R)) |go| {
                            self.faceToward(go, dt);
                            self.speed = approach(self.speed, DRIFT_SPEED, ACCEL * dt);
                            self.travel(dt, bounds);
                        } else {
                            self.speed = approach(self.speed, 0, ACCEL * dt);
                            if (sensed <= AGGRO_R) self.faceToward(quarry, dt);
                        }
                    },
                    .hold => {
                        self.faceToward(self.home, dt);
                        self.speed = approach(self.speed, DRIFT_SPEED, ACCEL * dt);
                        self.travel(dt, bounds);
                    },
                    .drift => {
                        self.faceToward(quarry, dt);
                        self.speed = approach(self.speed, DRIFT_SPEED, ACCEL * dt);
                        self.travel(dt, bounds);
                    },
                    .bite => {
                        self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                        self.enter(.wind);
                        sfx.world(.shade_gather, self.pos);
                    },
                    .blink => self.enterBlink(quarry),
                }
            },
        }

        self.hover = approach(self.hover, self.hoverTo, HOVER_RATE * dt);
        const beating = self.state == .blinkin or self.state == .wind or self.speed > 0.1;
        self.wingPhase += dt * (if (beating) WING_HZ_BEAT else WING_HZ_HOVER);
        self.wingPhase -= @floor(self.wingPhase);
        if (self.state != .wind and self.state != .strike) self.jawOpen = approach(self.jawOpen, 0, 5.0 * dt);
        self.pose();
        self.tryHit(blade);
        return self.heroHit;
    }

    /// Whether THIS blink is a pass at the quarry or a withdrawal to the ring. **DECIDED AT THE LAUNCH**, so
    /// the arrival reads a committed flag rather than re-measuring a distance the quarry has since changed.
    fn wantsPass(self: *const Bat) bool {
        return self.blinkNear;
    }

    fn travel(self: *Bat, dt: f32, bounds: f32) void {
        const step = self.speed * dt * self.chill.travel();
        mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), step, bounds);
    }

    fn driftAway(self: *Bat, quarry: rl.Vector3, dt: f32, bounds: f32) void {
        const away = mathx.dirXZ(quarry, self.pos);
        if (mathx.lenXZ(away) < 1e-4) return;
        mathx.stepXZ(&self.pos, mathx.normV(away), DRIFT_SPEED * 0.9 * dt, bounds);
    }

    fn faceToward(self: *Bat, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }
    fn faceNow(self: *Bat, target: rl.Vector3) void {
        const d = mathx.dirXZ(self.pos, target);
        if (mathx.lenXZ(d) > 1e-4) self.facing = mathx.headingXZ(d);
    }

    fn tryBite(self: *Bat, quarry: rl.Vector3) void {
        if (self.heroLatch) return;
        if (!foe.inFront(self.pos, self.facing, quarry, foe.hurtReach(BITE_R, self.scale), BITE_FRONT_DOT)) return;
        self.heroHit = BITE_HIT;
        self.heroLatch = true;
        self.bit = true;
        self.leash.noteCombat();
    }

    /// **STAMPED BY THE GAME, OFF ITS OWN BLOW'S OUTCOME** — not off anything the player did. `landed` is
    /// whether this creature's jaws reached flesh; a shield in the way makes it false and there is no drink.
    pub fn fedOn(self: *Bat, landed: bool) void {
        if (self.state == .dead) return;
        if (!landed) {
            self.enter(.repelled);
            self.blinkCd = mathx.maxF(self.blinkCd, FEED_BLINK_LOCK);
            sfx.world(.foe_guarded, self.pos);
            return;
        }
        self.drinkLeft = DRAIN_SHARE * BITE_HIT.dmg;
        self.drank = true;
        self.blinkCd = mathx.maxF(self.blinkCd, FEED_DUR + FEED_BLINK_LOCK);
        self.enter(.feed);
        sfx.world(.leech_drink, self.pos);
    }

    pub fn tryHit(self: *Bat, blade: foe.Blade) void {
        if (self.state == .dead or self.hidden()) return;
        const s = foe.reached(self, blade) orelse return;
        const heavy = foe.wounded(self, s, blade, SHOVE);
        self.chips(s.contact, s.dir, if (heavy) CHIP_HEAVY else CHIP_LIGHT, if (heavy) 3.0 else 2.1);
        sfx.world(.leech_hurt, self.pos);
        switch (s.reaction) {
            .death => {
                self.chips(s.contact, s.dir, CHIP_DEATH, 3.4);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn chips(self: *Bat, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32) void {
        foe.spray(&self.parts, &self.fxHead, &self.fxRng, at, dir, n, spd, self.scale, CHIP_SPRAY);
    }

    fn enter(self: *Bat, s: State) void {
        self.state = s;
        self.t = 0;
    }

    fn enterStun(self: *Bat, s: State) void {
        self.heroLatch = false;
        // **A STAGGER TAKES THE DRINK OFF IT** — the rest of the blood is forfeit, which is the whole reason
        // the window exists. Left set, an interrupted feed handed the heal straight back on the next entry.
        self.drinkLeft = 0;
        self.thin = 0;
        self.spent = false;
        self.enter(s);
    }

    fn enterDeath(self: *Bat) void {
        if (self.state == .dead) return;
        self.heroLatch = false;
        self.drinkLeft = 0;
        self.thin = 0;
        self.enter(.dead);
        self.justDied = true;
        sfx.world(.leech_die, self.pos);
    }

    pub fn stagger(self: *Bat, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }

    /// Where this pass puts it down, committed here and never re-aimed. **THE ARC IS SWUNG OFF THE QUARRY'S
    /// BEARING, NOT OFF ITS FACING** — world state, so NO INPUT READING holds by construction.
    fn enterBlink(self: *Bat, quarry: rl.Vector3) void {
        const near = self.aiRng.float() < 0.72;
        const outR = if (near) BLINK_NEAR + foe.HERO_R else BLINK_FAR;
        const bear = mathx.headingXZ(mathx.dirXZ(quarry, self.pos));
        const swing = mathx.radians(lerpF(BLINK_ARC_MIN, BLINK_ARC_MAX, self.aiRng.float())) * self.arcSign;
        const dir = mathx.headingDir(bear + swing);
        self.blinkTo = v3(quarry.x + dir.x * outR, self.pos.y, quarry.z + dir.z * outR);
        self.blinkNear = near;
        self.spent = false;
        self.blinkCd = BLINK_CD * self.aiRng.range(0.85, 1.25);
        // It works one way round for a while and then changes its mind, so a player cannot pre-aim the ring.
        if (self.aiRng.float() < 0.22) self.arcSign = -self.arcSign;
        self.enter(.blinkout);
        self.rift();
        sfx.world(.shade_blink, self.pos);
    }

    pub fn debugBite(self: *Bat) void {
        self.heroLatch = false;
        self.enter(.wind);
    }
    pub fn debugKill(self: *Bat) void {
        self.enterDeath();
    }
    /// The shot harness stages every creature's signature move through this one name (`shots.runMapShots`).
    pub fn stageGather(self: *Bat, u: f32) void {
        self.state = .wind;
        self.t = BITE_WIND * mathx.clampF(u, 0, 1);
        self.jawOpen = mathx.smoothstep(0, BITE_WIND, self.t);
        self.hover = HOVER_BITE;
        self.hoverTo = HOVER_BITE;
        self.pose();
    }

    fn rift(self: *Bat) void {
        var i: i32 = 0;
        while (i < 16) : (i += 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.15, 0.62) * self.scale;
            const c = self.centerWorld();
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(c.x + mathx.cosf(a) * rr, c.y + self.fxRng.signed() * 0.45 * self.scale, c.z + mathx.sinf(a) * rr),
                .v = v3(mathx.cosf(a) * 0.9, self.fxRng.range(-0.3, 0.9), mathx.sinf(a) * 0.9),
                .life = self.fxRng.range(0.20, 0.42),
                .r0 = self.fxRng.range(0.05, 0.10),
                .r1 = 0.012,
                .col = RIFT,
                .col1 = MOTE,
                .grav = -0.5,
                .drag = 3.0,
            });
        }
    }

    fn emitDrink(self: *Bat, dt: f32) void {
        var owed = foe.emitDue(&self.fxAccum, dt, 26.0);
        while (owed > 0) : (owed -= 1) {
            const m = foe.markOn(self.xf[JAW], v3(0, -0.04 * H, 0.10 * H));
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = m,
                .v = v3(self.fxRng.signed() * 0.35, self.fxRng.range(-1.4, -0.2), self.fxRng.signed() * 0.35),
                .life = self.fxRng.range(0.22, 0.46),
                .r0 = self.fxRng.range(0.018, 0.038),
                .r1 = 0.010,
                .col = EYE,
                .col1 = MOTE,
                .grav = 7.0,
                .drag = 1.4,
            });
        }
    }

    pub fn draw(self: *const Bat, model: *const Model) void {
        model.draw(self);
    }

    pub fn drawFx(self: *const Bat) void {
        foe.drawParticles(&self.parts);
        if (self.gone or self.hidden()) return;
        // **THE EYES ARE UNLIT SPHERES OVER THE OPAQUE PASS** (the leechfly's rule): vertex alpha is a FIXED
        // emissive channel and cannot be brightened, so a fed bat's eyes have to be drawn, not tinted.
        const glow = 0.34 + 0.66 * self.gorge;
        const r = (0.026 + 0.012 * self.gorge) * H * self.scale * (1.0 - self.fade);
        if (r <= 0) return;
        inline for (.{ 1.0, -1.0 }) |side| {
            const at = foe.markOn(self.xf[SKULL], v3(side * 0.030 * H, 0.014 * H, 0.062 * H));
            rl.drawSphereEx(at, r, 6, 6, mathx.withAlpha(EYE, mathx.u8f(235.0 * glow)));
        }
    }

    pub fn pose(self: *Bat) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const facingDeg = mathx.degrees(self.facing);
        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.62, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        const stun = self.stunAmount();
        const hipY = self.rest[ROOT].y;

        const bite = self.biteAmt();
        const feed = if (self.state == .feed) mathx.smoothstep(0, 0.18, self.t) else 0;
        const beat = mathx.sinf(self.wingPhase * std.math.tau);
        const wing = beat * (1.0 - dk);
        const bob = mathx.sinf((self.elapsed + self.seed) * 1.6) * 0.045 * H * (1.0 - dk);

        // **THE BODY HINGES AT THE WAIST AND THE PELVIS STAYS NEAR-UPRIGHT** (`ogre.PELVIS_SHARE`'s law on a
        // hanging body): a lean taken at the ROOT rotates the legs and reads as the whole animal tipping.
        const bodyPitch = 16.0 + 30.0 * bite + 46.0 * feed - 34.0 * stun + 74.0 * dk;
        const leanX = 0.28 * bodyPitch;
        const waist = bodyPitch - leanX;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul(rz(24.0 * dk), rx(leanX)),
            mul(tr(0, hipY * fs + bob, 0), ry(facingDeg)),
            heromod.rootAt(v3(self.pos.x, self.pos.y + self.lift(), self.pos.z)),
        ));

        setLocal(&wx, SPINE, self.rest, rx(waist * 0.55));
        setLocal(&wx, CHEST, self.rest, rx(waist * 0.45));
        const neckPitch = -6.0 + 34.0 * bite + 48.0 * feed - 16.0 * stun;
        setLocal(&wx, NECK, self.rest, rx(neckPitch * 0.45));
        setLocal(&wx, SKULL, self.rest, mul(rx(neckPitch * 0.55), rz(4.0 * mathx.sinf(self.elapsed * 0.7 + self.seed))));

        // JAW: the gape IS the tell, and it is the widest thing on the creature before the jaws move.
        setLocal(&wx, JAW, self.rest, rx(6.0 + 42.0 * self.jawOpen - 30.0 * feed));
        const flick = mathx.sinf(self.elapsed * 2.3 + self.seed * 6.28) * 5.0;
        setLocal(&wx, EARL, self.rest, mul(rz(-16.0 - 10.0 * bite + flick), rx(-10.0)));
        setLocal(&wx, EARR, self.rest, mul(rz(16.0 + 10.0 * bite - flick), rx(-10.0)));

        const sweep = 62.0 + 26.0 * wing - 34.0 * bite + 18.0 * dk;
        const fold = 34.0 - 22.0 * wing + 40.0 * bite + 30.0 * feed - 44.0 * dk;
        const cam = 12.0 + 16.0 * wing;
        inline for (.{ .{ SHL, ELL, WRL, 1.0 }, .{ SHR, ELR, WRR, -1.0 } }) |w| {
            const side: f32 = w[3];
            // **STAGGER THE LAGS** — a wing whose spar, elbow and hand peak on one frame reads as a plank.
            const lagE = mathx.sinf((self.wingPhase - 0.08) * std.math.tau) * (1.0 - dk);
            const lagW = mathx.sinf((self.wingPhase - 0.17) * std.math.tau) * (1.0 - dk);
            setLocal(&wx, w[0], self.rest, mul3(rz(side * sweep), rx(-cam), ry(side * (10.0 + 8.0 * wing))));
            setLocal(&wx, w[1], self.rest, mul(rz(side * (fold + 14.0 * lagE)), rx(-8.0 - 10.0 * lagE)));
            setLocal(&wx, w[2], self.rest, mul(rz(side * (fold * 0.7 + 18.0 * lagW)), rx(-6.0 - 12.0 * lagW)));
        }

        // It never stands, so there is no gait and no sole to level: no `legChain` call, on purpose.
        const tuck = 46.0 + 16.0 * bite + 26.0 * feed - 30.0 * dk;
        const swayL = mathx.sinf((self.elapsed * 1.1 + self.seed) * std.math.tau) * 4.0;
        inline for (.{ .{ HIPL, KNEEL, ANKL, 1.0 }, .{ HIPR, KNEER, ANKR, -1.0 } }) |l| {
            const side: f32 = l[3];
            setLocal(&wx, l[0], self.rest, mul(rx(tuck + side * swayL), rz(side * 6.0)));
            setLocal(&wx, l[1], self.rest, rx(-(tuck * 1.5) - 10.0 * dk));
            setLocal(&wx, l[2], self.rest, rx(18.0 + 10.0 * bite));
        }

        wx[HELD] = wx[WRR];
        self.xf = wx;
    }

    fn biteAmt(self: *const Bat) f32 {
        return switch (self.state) {
            .wind => -mathx.smoothstep(0, BITE_WIND * 0.9, self.t),
            .strike => lerpF(-1.0, 1.0, foe.swingCurve(mathx.clampF(self.t / BITE_STRIKE, 0, 1))),
            .recover => 1.0 - mathx.smoothstep(0, BITE_RECOVER * 0.7, self.t),
            else => 0,
        };
    }

    fn stunAmount(self: *const Bat) f32 {
        if (self.state == .repelled) return 0.6 * (1.0 - mathx.smoothstep(0, BITE_WIND, self.t));
        if (self.state != .stunlight and self.state != .stunheavy) return 0;
        return foe.stunCurve(self.t, self.state == .stunheavy);
    }
};


const CAP_N = wf.MAX_PER_KIND;

pub const Roost = struct {
    model: Model,
    bats: [CAP_N]Bat = undefined,
    n: usize = 0,
    /// Which row's blow the group actually handed back this frame. **THE ONLY ROW A FEED CAN BE STAMPED ONTO**,
    /// because it is the only one `game` bills: a second bat biting on the same frame goes hungry rather than
    /// drinking off a blow nobody took.
    bitter: ?usize = null,

    pub fn init(shader: rl.Shader) Roost {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Roost) []Bat {
        return self.bats[0..self.n];
    }
    pub fn liveConst(self: *const Roost) []const Bat {
        return self.bats[0..self.n];
    }
    pub fn reset(self: *Roost, m: *const wf.Map) void {
        self.bitter = null;
        foe.resetGroup(Bat, &self.bats, &self.n, m, .blinkbat);
    }
    pub fn clear(self: *Roost) void {
        self.n = 0;
        self.bitter = null;
    }
    pub fn setShader(self: *Roost, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn setParry(self: *Roost, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }

    pub fn update(self: *Roost, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        var worst: ?foe.Blow = null;
        self.bitter = null;
        for (self.live(), 0..) |*b, i| {
            if (b.update(dt, b.threat.aim(hero), bounds, blade)) |h| {
                foe.worseBlow(&worst, h, b.pos, &b.threat);
                // The winner is whoever's `from` is standing in `worst` right now. An exact compare is honest
                // here: it is the same value COPIED in, not one computed twice.
                if (worst) |w| {
                    if (w.from.x == b.pos.x and w.from.y == b.pos.y and w.from.z == b.pos.z) self.bitter = i;
                }
            }
        }
        return worst;
    }

    /// **THE OUTCOME OF THE BLOW, HANDED BACK** (`game.heroTakes`). Blood feeds it; a shield does not.
    pub fn fedOn(self: *Roost, landed: bool) void {
        const i = self.bitter orelse return;
        self.bitter = null;
        self.bats[i].fedOn(landed);
    }

    pub fn anyDrank(self: *const Roost) bool {
        for (self.liveConst()) |*b| {
            if (b.drank) return true;
        }
        return false;
    }

    pub fn draw(self: *const Roost, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Roost) void {
        for (self.liveConst()) |*b| b.drawFx();
    }
    pub fn pierce(self: *Roost, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Roost) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn anyParried(self: *const Roost) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn soulsDropped(self: *const Roost) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Roost) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Roost) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

// THE BODY. Flesh is round; the membrane is the one thing on it that is not.

fn buildBones() [N]rl.Mesh {
    var out: [N]rl.Mesh = undefined;
    for (0..N) |i| out[i] = boneMesh(i);
    return out;
}

fn boneMesh(i: usize) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x8A7 + @as(u64, @intCast(i)) * 7919);
    const len = struct {
        fn to(child: usize, parent: usize) f32 {
            return mathx.lenV(mathx.subV(REST[child], REST[parent]));
        }
    }.to;
    switch (i) {
        ROOT => {
            b.setMat(.hide);
            b.addBlob(v3(0, 0.020 * H, 0), v3(0.088 * H, 0.072 * H, 0.078 * H), 6, 9, HIDE);
            b.addBlob(v3(0, -0.030 * H, 0.012 * H), v3(0.062 * H, 0.048 * H, 0.058 * H), 5, 8, HIDE_DK);
        },
        SPINE => {
            b.setMat(.hide);
            const up: f32 = len(CHEST, SPINE);
            b.addCapsule(v3(0, 0, 0), v3(0, up, 0), 0.086 * H, 0.104 * H, 10, HIDE);
            // The swell is authored: a mesh cannot show `gorge`, so the eyes carry it (`drawFx`) — the one
            // channel that can brighten.
            b.addBlob(v3(0, up * 0.35, 0.052 * H), v3(0.074 * H, 0.070 * H, 0.056 * H), 5, 9, HIDE_DK);
        },
        CHEST => {
            b.setMat(.hide);
            const up: f32 = len(NECK, CHEST);
            b.addBlob(v3(0, up * 0.10, 0.020 * H), v3(0.128 * H, 0.104 * H, 0.094 * H), 6, 10, HIDE);
            b.addBlob(v3(0, up * 0.05, 0.088 * H), v3(0.050 * H, 0.086 * H, 0.038 * H), 5, 8, HIDE_DK);
            var k: i32 = 0;
            while (k < 3) : (k += 1) {
                const y = up * (0.10 + 0.22 * @as(f32, @floatFromInt(k)));
                const rr = (0.020 + rng.range(-0.004, 0.006)) * H;
                b.addCapsule(v3(-0.104 * H, y, 0.010 * H), v3(0.104 * H, y, 0.010 * H), rr, rr, 6, HIDE_DK);
            }
        },
        NECK => {
            b.setMat(.hide);
            b.addCapsule(v3(0, 0, 0), v3(0, len(SKULL, NECK), 0.010 * H), 0.054 * H, 0.048 * H, 9, HIDE);
        },
        SKULL => {
            b.setMat(.hide);
            b.addBlob(v3(0, 0.006 * H, 0.004 * H), v3(0.062 * H, 0.058 * H, 0.062 * H), 6, 10, HIDE);
            b.setMat(.skin);
            b.addCapsule(v3(0, -0.004 * H, 0.048 * H), v3(0, -0.014 * H, 0.092 * H), 0.030 * H, 0.022 * H, 8, SNOUT);
            b.addBlob(v3(0, 0.004 * H, 0.086 * H), v3(0.020 * H, 0.016 * H, 0.014 * H), 4, 7, SNOUT);
            b.setMat(.plain);
            inline for (.{ 1.0, -1.0 }) |s| {
                const sx: f32 = s;
                b.addCapsule(
                    v3(sx * 0.017 * H, -0.020 * H, 0.078 * H),
                    v3(sx * 0.019 * H, -0.052 * H, 0.074 * H),
                    0.0075 * H,
                    0.0018 * H,
                    6,
                    FANG,
                );
            }
        },
        JAW => {
            b.setMat(.skin);
            b.addCapsule(v3(0, 0, 0), v3(0, -0.012 * H, 0.062 * H), 0.026 * H, 0.018 * H, 8, SNOUT);
            b.setMat(.plain);
            inline for (.{ 1.0, -1.0 }) |s| {
                const sx: f32 = s;
                b.addCapsule(
                    v3(sx * 0.014 * H, -0.004 * H, 0.052 * H),
                    v3(sx * 0.015 * H, 0.020 * H, 0.056 * H),
                    0.0060 * H,
                    0.0015 * H,
                    6,
                    FANG,
                );
            }
        },
        EARL, EARR => {
            // **A FACE THAT IS MOSTLY EAR.** Authored as a membrane, not as flesh — thin panels on a rib, which
            // is also what makes the ears read as the same substance as the wings.
            const side: f32 = if (i == EARL) 1.0 else -1.0;
            b.setMat(.hide);
            b.addCapsule(v3(0, 0, 0), v3(side * 0.030 * H, 0.150 * H, -0.006 * H), 0.013 * H, 0.005 * H, 7, HIDE);
            b.setMat(.cloth);
            b.addBox(
                v3(side * 0.018 * H, 0.076 * H, -0.004 * H),
                v3(side * 0.030 * H, 0.010 * H, 0),
                v3(0, 0.076 * H, 0),
                v3(0, 0, 0.0035 * H),
                MEMBRANE,
            );
        },
        SHL, SHR => {
            const side: f32 = if (i == SHL) 1.0 else -1.0;
            b.setMat(.hide);
            const down: f32 = -len(if (i == SHL) @as(usize, ELL) else @as(usize, ELR), i);
            b.addCapsule(v3(0, 0, 0), v3(0, down, 0), 0.052 * H, 0.040 * H, 9, HIDE);
            b.addBlob(v3(side * 0.014 * H, -0.012 * H, 0), v3(0.048 * H, 0.044 * H, 0.044 * H), 5, 8, HIDE_DK);
        },
        ELL, ELR => {
            const side: f32 = if (i == ELL) 1.0 else -1.0;
            const down: f32 = -len(if (i == ELL) @as(usize, WRL) else @as(usize, WRR), i);
            b.setMat(.hide);
            b.addCapsule(v3(0, 0, 0), v3(0, down, 0), 0.040 * H, 0.028 * H, 9, HIDE);
            // THE INNER MEMBRANE, on the forearm's own bone so the wing folds at the elbow like an arm and no
            // panel is ever asked to span two bones that move apart.
            b.setMat(.cloth);
            b.addBox(
                v3(side * -0.052 * H, down * 0.5, 0.004 * H),
                v3(side * 0.052 * H, 0, 0),
                v3(0, down * 0.5, 0),
                v3(0, 0, 0.0040 * H),
                MEMBRANE,
            );
        },
        WRL, WRR => {
            // **THE HAND IS THE WING.** Three struts fanning off the wrist with the membrane hung between them:
            // uneven lengths and uneven spread, because a fan of three identical spokes reads as a paper toy.
            const side: f32 = if (i == WRL) 1.0 else -1.0;
            const spokes = [3][2]f32{ .{ 0.560, -26.0 }, .{ 0.640, 6.0 }, .{ 0.470, 40.0 } };
            var prev: ?rl.Vector3 = null;
            for (spokes, 0..) |sp, k| {
                const L = sp[0] * H * (1.0 + rng.range(-0.035, 0.035));
                const a = mathx.radians(sp[1] + rng.range(-3.0, 3.0));
                const tip = v3(side * L * mathx.cosf(a) * 0.34, -L * @abs(mathx.cosf(a)) * 0.62, L * mathx.sinf(a));
                b.setMat(.hide);
                const r0 = (0.020 - 0.0035 * @as(f32, @floatFromInt(k))) * H;
                b.addCapsule(v3(0, 0, 0), tip, r0, r0 * 0.24, 7, HIDE_DK);
                b.setMat(.plain);
                b.addCapsule(
                    tip,
                    v3(tip.x * 1.06, tip.y - 0.020 * H, tip.z * 1.06),
                    0.0060 * H,
                    0.0015 * H,
                    5,
                    CLAW,
                );
                if (prev) |p| {
                    b.setMat(.cloth);
                    // The panel is a quad standing between two struts: a HALF-axis from their midpoint out to
                    // each, which is what `addBox` takes (`necro`'s skirt rule — half-axes, never extents).
                    const mid = mathx.lerpV(p, tip, 0.5);
                    b.addBox(
                        v3(mid.x * 0.62, mid.y * 0.62, mid.z * 0.62),
                        mathx.scaleV(mathx.subV(tip, p), 0.5),
                        mathx.scaleV(mid, 0.30),
                        v3(0, 0, 0.0035 * H),
                        if (k == 1) MEMBRANE else MEMBRANE_DK,
                    );
                }
                prev = tip;
            }
        },
        HIPL, HIPR => {
            const child: usize = if (i == HIPL) KNEEL else KNEER;
            b.setMat(.hide);
            b.addCapsule(v3(0, 0, 0), v3(0, -len(child, i), 0), 0.040 * H, 0.030 * H, 8, HIDE);
        },
        KNEEL, KNEER => {
            const child: usize = if (i == KNEEL) ANKL else ANKR;
            b.setMat(.hide);
            b.addCapsule(v3(0, 0, 0), v3(0, -len(child, i), 0), 0.030 * H, 0.021 * H, 8, HIDE_DK);
        },
        ANKL, ANKR => {
            const side: f32 = if (i == ANKL) 1.0 else -1.0;
            b.setMat(.hide);
            b.addBlob(v3(0, -0.008 * H, 0), v3(0.024 * H, 0.020 * H, 0.024 * H), 4, 7, HIDE_DK);
            b.setMat(.plain);
            var k: i32 = 0;
            while (k < 4) : (k += 1) {
                const a = mathx.radians(-42.0 + 32.0 * @as(f32, @floatFromInt(k)) + rng.range(-5.0, 5.0));
                const L = (0.052 + rng.range(-0.008, 0.010)) * H;
                b.addCapsule(
                    v3(0, -0.014 * H, 0),
                    v3(side * mathx.sinf(a) * L * 0.5, -0.014 * H - L * 0.7, mathx.cosf(a) * L),
                    0.0070 * H,
                    0.0018 * H,
                    5,
                    CLAW,
                );
            }
        },
        else => {},
    }
    return b.toMesh();
}


fn testBat() Bat {
    return Bat.spawn(mathx.ground(0, 0), 0, 1.0, 0.31);
}

test "IT ARRIVES INSIDE ITS OWN REACH AND WITHDRAWS OUT OF IT — hit and run is a distance, not a mood" {
    try std.testing.expect(BLINK_NEAR + foe.HERO_R < BITE_R);
    try std.testing.expect(BLINK_FAR > BITE_R + 2.0);
    std.debug.print("\n  blinkbat: pass lands {d:.2} m out (bite reaches {d:.2}), withdraws to {d:.2} m\n", .{ BLINK_NEAR + foe.HERO_R, BITE_R, BLINK_FAR });
}

test "THE ARRIVAL IS THE TELL, and it clears the floor every attack in the game has to" {
    try std.testing.expect(BITE_WIND > foe.TELL_MIN);
    const warned = BLINK_IN + BITE_WIND;
    try std.testing.expect(warned > 0.70);
    std.debug.print("  a pass shows itself for {d:.2} s before the jaws move ({d:.2} fading in, {d:.2} gathering)\n", .{ warned, BLINK_IN, BITE_WIND });
}

test "A SHIELD DENIES THE HEAL OUTRIGHT — no blood, no feed" {
    var b = testBat();
    b.vit.hp = 60;
    b.state = .strike;
    b.fedOn(false);
    try std.testing.expectEqual(State.repelled, b.state);
    try std.testing.expectApproxEqAbs(@as(f32, 60), b.vit.hp, 1e-4);
    try std.testing.expect(b.drinkLeft == 0);
}

test "A BITE THAT DRAWS BLOOD FEEDS IT, and the drink is paid by the SECOND rather than banked" {
    var b = testBat();
    b.vit.hp = 60;
    b.fedOn(true);
    try std.testing.expectEqual(State.feed, b.state);
    const owed = b.drinkLeft;
    try std.testing.expect(owed > 0);

    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < FEED_DUR * 0.5) : (t += dt) _ = b.update(dt, mathx.ground(0, 3), 400, .{});
    const half = b.vit.hp;
    try std.testing.expect(half > 60 and half < 60 + owed);
    b.stagger(false);
    try std.testing.expectApproxEqAbs(@as(f32, 0), b.drinkLeft, 1e-6);
    t = 0;
    while (t < FEED_DUR) : (t += dt) _ = b.update(dt, mathx.ground(0, 3), 400, .{});
    try std.testing.expectApproxEqAbs(half, b.vit.hp, 0.51);
    std.debug.print("  drink owed {d:.1} hp; interrupted at half it kept {d:.1} and the rest was forfeit\n", .{ owed, half - 60 });
}

test "THE FEED CANNOT BE BLINKED OUT OF — it is bought with the escape" {
    var b = testBat();
    b.blinkCd = 0;
    b.fedOn(true);
    try std.testing.expect(b.blinkCd >= FEED_DUR);
}

test "MIDWAY THROUGH A BLINK IT IS NOWHERE: no body to hit and no body to lock" {
    var b = testBat();
    b.enterBlink(mathx.ground(0, 4));
    try std.testing.expectEqual(State.blinkout, b.state);
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    var everHidden = false;
    while (t < BLINK_OUT + BLINK_IN) : (t += dt) {
        _ = b.update(dt, mathx.ground(0, 4), 400, .{});
        if (b.hidden()) everHidden = true;
    }
    try std.testing.expect(everHidden);
    try std.testing.expect(!b.hidden());
}

test "THE ROOTS REFUSE THE BLINK — the one time this creature is chaseable" {
    try std.testing.expectEqual(Choice.blink, classify(9.0, 8.0, 0, true, false, false));
    try std.testing.expectEqual(Choice.drift, classify(9.0, 8.0, 0, true, true, false));
    try std.testing.expectEqual(Choice.drift, classify(9.0, 8.0, 0, false, false, false));
    try std.testing.expectEqual(Choice.bite, classify(2.0, BITE_R - 0.1, 0, true, false, false));
    try std.testing.expectEqual(Choice.rest, classify(AGGRO_R + 1, 20, 0, true, false, false));
    try std.testing.expectEqual(Choice.hold, classify(AGGRO_R + 1, 20, HOME_R + 1, true, false, false));
}

test "IT IS NOT THE LEECHFLY: it never climbs out of a swing" {
    // The leechfly answers a sword with ALTITUDE (`HOVER_HIGH` 4.6). This one stays in reach the whole time and
    // answers with the blink, and a test says so because two flyers sharing one refusal is one creature twice.
    try std.testing.expect(HOVER_WAIT < 3.2);
    var b = testBat();
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    var high: f32 = 0;
    while (t < 12.0) : (t += dt) {
        _ = b.update(dt, mathx.ground(0, 3.5), 400, .{});
        high = mathx.maxF(high, b.hover);
    }
    try std.testing.expect(high < 3.2);
    std.debug.print("  over 12 s of fighting it never flew higher than {d:.2} m\n", .{high});
}

test "THE BODY IS LARGE, and every world point it owns rides the hover" {
    var b = testBat();
    b.hover = 2.0;
    b.pos = mathx.ground(0, 0);
    b.pos.y = 5.0; // a bank
    b.pose();
    try std.testing.expectApproxEqAbs(@as(f32, 5.0) + CENTER_F * H + 2.0, b.centerWorld().y, 1e-4);
    try std.testing.expect(b.topWorld().y > b.centerWorld().y);
    try std.testing.expect(H > heromod.H);
    std.debug.print("  blinkbat stands {d:.2} m to the hero's {d:.2}, and hangs {d:.2}-{d:.2} m up\n", .{ H, heromod.H, HOVER_BITE, HOVER_WAIT });
}

test "the wingspan is a wing, not a pair of arms" {
    const r = REST;
    const spar = mathx.lenV(mathx.subV(r[WRL], r[SHL]));
    const strut = 0.640 * H;
    const half = SHOULDER_HALF * H + spar + strut * 0.34;
    std.debug.print("  spar {d:.2} m + longest strut {d:.2} m: half-span {d:.2} m, wing to wing {d:.2} m\n", .{ spar, strut, half, half * 2 });
    try std.testing.expect(spar > mathx.lenV(mathx.subV(r[KNEEL], r[HIPL])));
    try std.testing.expect(half * 2 > H * 1.6);
}

test "a body goes out the one way every body goes out" {
    var b = testBat();
    b.enterDeath();
    try std.testing.expect(b.justDied and b.dying());
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < DEATH_DUR + DISS_DUR + 0.2) : (t += dt) _ = b.update(dt, mathx.ground(0, 6), 400, .{});
    try std.testing.expect(b.gone);
    try std.testing.expect(!foe.corporeal(&b));
}

test "`justDied` is a ONE-FRAME flag" {
    var b = testBat();
    b.enterDeath();
    var fired: u32 = 0;
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < 1.0) : (t += dt) {
        _ = b.update(dt, mathx.ground(0, 6), 400, .{});
        if (b.justDied) fired += 1;
    }
    try std.testing.expectEqual(@as(u32, 0), fired);
}

test "IT DOES NOT TAKE TWO BITES FROM ONE SPOT — hit and RUN" {
    var b = testBat();
    const hero = mathx.ground(0, 1.2);
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    var bites: u32 = 0;
    var blinks: u32 = 0;
    var sinceBlink: u32 = 0;
    var worst: u32 = 0;
    var wasBlink = false;
    while (t < 20.0) : (t += dt) {
        _ = b.update(dt, hero, 400, .{});
        if (b.bit) {
            bites += 1;
            sinceBlink += 1;
            worst = @max(worst, sinceBlink);
        }
        const nowBlink = b.state == .blinkout;
        if (nowBlink and !wasBlink) {
            blinks += 1;
            sinceBlink = 0;
        }
        wasBlink = nowBlink;
    }
    std.debug.print("\n  20 s stood in its face: {d} bites, {d} blinks, never more than {d} from one spot\n", .{ bites, blinks, worst });
    try std.testing.expect(bites > 0 and blinks > 0);
    try std.testing.expectEqual(@as(u32, 1), worst);
}

test "A SPENT PASS LEAVES — but rooted it stays and fights, which is the one time it is beatable on foot" {
    const near = BITE_R - 0.2;
    try std.testing.expectEqual(Choice.bite, classify(2.0, near, 0, true, false, false));
    try std.testing.expectEqual(Choice.blink, classify(2.0, near, 0, true, false, true));
    // …unless the roots have it, and then it has to finish the fight where it stands.
    try std.testing.expectEqual(Choice.bite, classify(2.0, near, 0, true, true, true));
    try std.testing.expectEqual(Choice.rest, classify(2.0, near, 0, false, false, true));
}
