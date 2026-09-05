const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
const foe = @import("foe.zig");
const wolf = @import("wolf.zig");
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

/// Withers, in metres. The quadruped rig is the wolf's at W; everything about the body is authored as shares of it.
pub const W: f32 = 2.35;
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

// AUTHORED DARK (the deer's rule): a big smooth mass comes back brighter than the field it stands in.
const HIDE = rgba(38, 32, 27, 255);
const HIDE_DK = rgba(24, 20, 17, 255);
const HIDE_LT = rgba(52, 44, 36, 255);
const BELLY = rgba(46, 40, 34, 255);
const HORN = rgba(128, 118, 96, 255);
const HORN_DK = rgba(92, 84, 66, 255);
const HORN_LT = rgba(160, 150, 124, 255);
const GUM = rgba(74, 36, 34, 255);
const TOOTH = rgba(166, 156, 130, 255);
const EYE = rgba(190, 150, 70, 90);
const DUST = foe.DUST;

pub const AGGRO_R_BANK: f32 = 22.0;
pub var AGGRO_R: f32 = AGGRO_R_BANK;
const HOME_R: f32 = 3.0;
const TURN_RATE: f32 = 2.2;
/// ELEPHANT SPEEDS: a walk, and an AMBLE at the charge — the same lateral-sequence footfall run fast, never a trot and never a gallop.
const WALK_SPEED: f32 = 1.7;
const CLOSE_SPEED: f32 = 2.6;
pub const CHARGE_SPEED: f32 = 7.5;
const ACCEL: f32 = 3.2;
const GAIT_BLEND: f32 = 4.0;

const BODY_R: f32 = 1.15;
const HURT_R: f32 = 1.35;
const CENTER_Y: f32 = 0.60;
const TOP_Y: f32 = 1.06;
const SINK_DEPTH: f32 = 0.55;

const HP_MAX: f32 = 560.0;
const POISE_MAX: f32 = 70.0;
const STANCE_MAX: f32 = 140.0;
const RESISTS = combat.resists(.{ .fire = 10, .cold = 20, .lightning = -15, .chaos = 10 });
pub var SOULS: u32 = 1100;

const BUTT_R: f32 = 2.4;
const BUTT_FRONT_DOT: f32 = 0.55;
const BUTT_WIND: f32 = 0.50;
const BUTT_STRIKE: f32 = 0.20;
const BUTT_RECOVER: f32 = 0.70;
const BUTT_CD: f32 = 2.4;
const BUTT_IMPACT_K: f32 = 0.5;
pub var BUTT_HIT = combat.Hit{ .dmg = 34, .poise = 46, .stance = 22, .launch = 1.6 };

const BITE_R: f32 = 2.0;
const BITE_FRONT_DOT: f32 = 0.6;
const BITE_WIND: f32 = 0.42;
const BITE_STRIKE: f32 = 0.18;
const BITE_RECOVER: f32 = 0.60;
const BITE_CD: f32 = 1.8;
/// OWNER: MORE OOMPH. The bite throws the whole beast at you — `BITE_LUNGE` of ground through the strike, the forefeet down on the snap — and a bite that lands SHOVES (`Hit.shove`).
const BITE_LUNGE: f32 = 0.9;
pub const BITE_SHOVE: f32 = 1.3;
/// Where in the strike the jaws arrive: the bill and the parry window read the same number.
const BITE_IMPACT_K: f32 = 0.5;
pub var BITE_HIT = combat.Hit{ .dmg = 24, .poise = 40, .stance = 14, .shove = BITE_SHOVE };

/// FROM A DISTANCE: it paws, drops its head and comes at you flat out down a line it can barely bend. Hits whatever the horns meet.
pub const CHARGE_MIN: f32 = 6.0;
pub const CHARGE_MAX: f32 = 16.0;
const CHARGE_WIND: f32 = 0.75;
const CHARGE_DUR: f32 = 2.4;
/// Radians a second the line bends: a few degrees over the whole run, so a step aside IS a step aside.
const CHARGE_TURN: f32 = 0.08;
const CHARGE_RECOVER: f32 = 1.10;
const CHARGE_CD: f32 = 7.0;
const CHARGE_HALF_W: f32 = 1.1;
/// How far ahead of `pos` the horns reach, pre-scale.
const CHARGE_NOSE: f32 = 1.9;
pub var CHARGE_HIT = combat.Hit{ .dmg = 40, .poise = 60, .stance = 30, .launch = 2.0 };

/// THE JUMP-LUNGE (owner: dangerous, long recovery): it comes down where you stood, and then it is on its knees for a long moment. That moment is the fight.
pub const LUNGE_MIN: f32 = 3.5;
pub const LUNGE_MAX: f32 = 8.0;
const LUNGE_WIND: f32 = 0.60;
const LUNGE_AIR: f32 = 0.55;
const LUNGE_UP: f32 = 2.2;
pub const LUNGE_REACH: f32 = 8.0;
pub const LUNGE_R: f32 = 2.6;
pub const LUNGE_RECOVER: f32 = 2.2;
const LUNGE_CD: f32 = 9.0;
pub var LUNGE_HIT = combat.Hit{ .dmg = 52, .poise = 70, .stance = 40, .launch = 2.4 };

/// BEHIND HIM IS THE TAIL: a rear sweep that also brings him round to face you, so the tail is never free ground twice.
pub const TAIL_R: f32 = 3.6;
const TAIL_BEARING: f32 = 125.0;
const TAIL_WIND: f32 = 0.35;
const TAIL_SWING: f32 = 0.35;
const TAIL_RECOVER: f32 = 0.50;
const TAIL_CD: f32 = 3.0;
/// HALF-angle about his rear (`combat.withinArc` takes a half-width): a 200-degree sweep behind him.
const TAIL_ARC: f32 = 100.0;
/// OWNER: MORE OOMPH. A tail this size takes him off his feet.
pub var TAIL_HIT = combat.Hit{ .dmg = 24, .poise = 48, .stance = 16, .launch = 1.4 };
/// THE WHIP: he loads AGAINST it for `TAIL_LOAD` of the wind (`TAIL_TWIST` the other way), comes round `TAIL_OVER` past the mark inside the swing, and settles back through the recover with the hind feet down and the mass rocked onto them.
const TAIL_LOAD: f32 = 0.6;
/// The tuft is still coiled at the swing's first frame; it passes behind him from here.
const TAIL_IMPACT_K: f32 = 0.25;
const TAIL_TWIST: f32 = 0.24;
const TAIL_OVER: f32 = 0.42;
/// The rear lifting through the whip, as a share of W — DRAWN, never `lift`, since `foe.AIRBORNE_LIFT` is 0.04 m.
const TAIL_HOP: f32 = 0.06;

const DEATH_DUR: f32 = 1.9;
const DISS_DUR: f32 = 1.3;
const SHOVE_DECAY: f32 = 5.0;
const DISSOLVE = foe.Dissolve{ .rate = 70.0, .spread = 1.4, .rise = 0.7, .flake = HIDE_LT };

comptime {
    std.debug.assert(BUTT_WIND >= foe.TELL_MIN and BITE_WIND >= foe.TELL_MIN and CHARGE_WIND >= foe.TELL_MIN and LUNGE_WIND >= foe.TELL_MIN and TAIL_WIND >= foe.TELL_MIN);
    std.debug.assert(BUTT_CD > BUTT_WIND + BUTT_STRIKE + BUTT_RECOVER);
    std.debug.assert(BITE_CD > BITE_WIND + BITE_STRIKE + BITE_RECOVER);
    std.debug.assert(CHARGE_CD > CHARGE_WIND + CHARGE_DUR + CHARGE_RECOVER);
    std.debug.assert(LUNGE_CD > LUNGE_WIND + LUNGE_AIR + LUNGE_RECOVER);
    std.debug.assert(TAIL_CD > TAIL_WIND + TAIL_SWING + TAIL_RECOVER);
    std.debug.assert(BITE_R < BUTT_R and BUTT_R < LUNGE_MIN and LUNGE_MAX > CHARGE_MIN and CHARGE_MAX < AGGRO_R_BANK);
    std.debug.assert(LUNGE_REACH >= LUNGE_MAX);
    std.debug.assert(LUNGE_RECOVER > 2.0 * BUTT_RECOVER); // the punish window is the point of the move
    std.debug.assert(TAIL_BEARING > 90.0 and TAIL_R > BUTT_R);
}

/// Sized over the worst frame: the lunge's landing dust with a killing heavy blow's two sprays and the shared wound.
const PARTS = 112;
const DUST_LAND = 30;
const DUST_STEP = 4;
const BLOOD_LIGHT = 9;
const BLOOD_HEAVY = 16;
const BLOOD_DEATH = 18;
const BLOOD = rgba(70, 18, 14, 235);
const BLOOD_SPRAY = foe.Spray{
    .fanLo = 0.8,  .fanHi = 4.2,
    .upLo = 1.0,   .upHi = 3.8,
    .lifeLo = 0.60, .lifeHi = 1.05,
    .rLo = 0.04,   .rHi = 0.08,
    .r1 = 0.01,    .col = BLOOD, .grav = foe.BLOOD_GRAV,
    .col1 = rgba(36, 8, 6, 220), .stretch = foe.BLOOD_STRETCH, .splat = 3.0, .drag = foe.BLOOD_DRAG,
};
const DUST_SPRAY = foe.Spray{
    .fanLo = 0.8,  .fanHi = 3.6,
    .upLo = 0.4,   .upHi = 1.8,
    .lifeLo = 0.50, .lifeHi = 1.10,
    .rLo = 0.10,   .rHi = 0.24,
    .r1 = 0.34,    .col = DUST, .grav = 0.5,
    .col1 = foe.DUST_THIN, .drag = 2.4,
};
comptime {
    std.debug.assert(PARTS >= foe.hitParts(DUST_LAND) + foe.hitParts(BLOOD_HEAVY) + foe.hitParts(BLOOD_DEATH) + foe.WOUND_PARTS);
}

/// LATERAL SEQUENCE, ALWAYS: an elephant walks LH, LF, RH, RF and runs the same order faster with less of each foot on the ground — an amble, no aerial phase, never a trot.
pub const WALK = wolf.Gait{ .duty = 0.70, .lag = 0.78 };
pub const AMBLE = wolf.Gait{ .duty = 0.52, .lag = 0.72 };
pub fn gaitAt(speed: f32) wolf.Gait {
    const t = mathx.clampF((speed - WALK_SPEED) / (CHARGE_SPEED - WALK_SPEED), 0, 1);
    return .{ .duty = lerpF(WALK.duty, AMBLE.duty, t), .lag = lerpF(WALK.lag, AMBLE.lag, t) };
}
/// The wolf's stride law is a dog's; a beast twice the wolf's withers takes a stride that long again.
pub fn strideFor(speed: f32) f32 {
    return wolf.strideFor(speed) * (W / wolf.W) * 0.9;
}

const State = enum { idle, walk, butt, bite, charge_wind, charge, charge_rec, lunge_wind, lunge_air, lunge_rec, tail, stunlight, stunheavy, dead };

const Choice = enum { tail, bite, butt, lunge, charge, close, hold };
fn classify(dist: f32, bearingDeg: f32, scale: f32, tailReady: bool, biteReady: bool, buttReady: bool, lungeReady: bool, chargeReady: bool) Choice {
    if (dist > AGGRO_R) return .hold;
    if (@abs(bearingDeg) >= TAIL_BEARING and dist <= foe.hurtReach(TAIL_R, scale) and tailReady) return .tail;
    const front = @abs(bearingDeg) <= 70.0;
    if (front and dist <= foe.hurtReach(BITE_R, scale) and biteReady) return .bite;
    if (front and dist <= foe.hurtReach(BUTT_R, scale) and buttReady) return .butt;
    if (front and dist >= LUNGE_MIN and dist <= LUNGE_MAX and lungeReady) return .lunge;
    if (front and dist >= CHARGE_MIN and dist <= CHARGE_MAX and chargeReady) return .charge;
    return .close;
}

pub const Model = struct {
    bone: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        return .{ .bone = buildBones(), .mat = gfx.material(shader, "mastodon") };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, m: *const Mastodon) void {
        for (0..N) |i| rl.drawMesh(self.bone[i], self.mat, m.xf[i]);
    }
};

/// THE BODY IS AN ELEPHANT'S ON A WOLF'S LEGS: the head hangs LOW off a short thick neck, the tail is long, and the ears are sails.
fn restPose() [N]rl.Vector3 {
    var r = wolf.restPose(W);
    const sh = r[CHEST];
    r[NECK] = v3(0, sh.y - 0.02 * W, sh.z + 0.16 * W);
    r[HEAD] = v3(0, sh.y - 0.10 * W, sh.z + 0.40 * W);
    r[JAW] = v3(0, r[HEAD].y - 0.11 * W, r[HEAD].z + 0.14 * W);
    r[EARL] = v3(0.12 * W, r[HEAD].y + 0.10 * W, r[HEAD].z - 0.10 * W);
    r[EARR] = v3(-0.12 * W, r[HEAD].y + 0.10 * W, r[HEAD].z - 0.10 * W);
    const hip = r[ROOT];
    r[TAIL0] = v3(0, hip.y + 0.04 * W, hip.z - 0.12 * W);
    r[TAIL1] = v3(0, hip.y - 0.10 * W, hip.z - 0.40 * W);
    r[TAIL2] = v3(0, hip.y - 0.30 * W, hip.z - 0.66 * W);
    return r;
}

pub const Mastodon = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    post: foe.Post = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},
    parry: foe.Parry = .{},
    wade: foe.Wade = .{},

    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    buttCd: f32 = 0,
    biteCd: f32 = 0,
    chargeCd: f32 = 0,
    lungeCd: f32 = 0,
    tailCd: f32 = 0,
    speed: f32 = 0,
    speedS: f32 = 0,
    phase: f32 = 0,
    lift: f32 = 0,
    launch: rl.Vector3 = mathx.zero3,
    landAt: rl.Vector3 = mathx.zero3,
    /// Where he was pointed when the tail went, and where it is bringing him: the swipe turns him through `turnFrom`+pi.
    turnFrom: f32 = 0,
    tailSide: f32 = 1,
    heroSide: f32 = 0,
    passed: bool = false,
    charging: bool = false,
    landed: bool = false,
    bellowed: bool = false,
    stamped: bool = false,
    swept: bool = false,
    snapped: bool = false,
    tailLanded: bool = false,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    heroLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    heroHit: ?combat.Hit = null,
    justDied: bool = false,
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

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Mastodon {
        var m = Mastodon{ .pos = home, .home = home, .facing = faceYaw, .scale = scale, .seed = seed };
        m.rest = restPose();
        m.fxRng = foe.fxStream(seed, 90121.0, 0x3A5);
        m.aiRng = foe.fxStream(seed, 27311.0, 0x3A6);
        m.buttCd = seed * 0.8;
        m.chargeCd = 1.5 + seed * 2.0;
        m.lungeCd = 3.0 + seed * 2.0;
        m.pose();
        return m;
    }

    pub fn centerWorld(self: *const Mastodon) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_Y * W, self.scale, self.lift);
    }
    /// The mark rides the head, low and forward, where the horns are.
    pub fn lockPoint(self: *const Mastodon) rl.Vector3 {
        return foe.markOn(self.xf[HEAD], v3(0, 0.06 * W, 0.04 * W));
    }
    pub fn topWorld(self: *const Mastodon) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_Y * W, self.scale, self.lift);
    }
    pub fn hurtRadius(self: *const Mastodon) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Mastodon) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Mastodon) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Mastodon) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Mastodon) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn airborne(self: *const Mastodon) bool {
        return self.lift > foe.AIRBORNE_LIFT;
    }
    pub fn flashFrac(self: *const Mastodon) f32 {
        return foe.flashFrac(self.flash);
    }
    pub fn kind(_: *const Mastodon) wf.FoeKind {
        return .mastodon;
    }
    pub fn stature(self: *const Mastodon) f32 {
        return W * self.scale;
    }
    /// Where the horns are: what the charge bills from.
    pub fn noseWorld(self: *const Mastodon) rl.Vector3 {
        return foe.markOn(self.xf[HEAD], v3(0, 0, 0.16 * W));
    }
    pub fn recovering(self: *const Mastodon) bool {
        return self.state == .lunge_rec or self.state == .charge_rec;
    }

    pub fn navWant(self: *const Mastodon, hero: rl.Vector3) ?rl.Vector3 {
        return switch (self.state) {
            .idle, .walk => blk: {
                if (foe.senseHero(&self.leash, self.pos, hero, AGGRO_R) <= AGGRO_R) break :blk hero;
                if (foe.postAim(self)) |go| break :blk go;
                break :blk if (mathx.distXZ(self.pos, foe.homeFor(self)) > HOME_R) self.home else null;
            },
            else => null,
        };
    }

    fn faceToward(self: *Mastodon, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }
    fn bearingTo(self: *const Mastodon, hero: rl.Vector3) f32 {
        return foe.bearingDeg(self.pos, self.facing, hero);
    }

    fn toImpact(self: *const Mastodon) ?f32 {
        return switch (self.state) {
            .butt => BUTT_WIND + BUTT_STRIKE * BUTT_IMPACT_K - self.t,
            .bite => BITE_WIND + BITE_STRIKE * BITE_IMPACT_K - self.t,
            else => null,
        };
    }
    fn parryable(self: *const Mastodon) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        return foe.hurtReach(if (self.state == .butt) BUTT_R else BITE_R, self.scale);
    }
    fn takeParry(self: *Mastodon) void {
        const reach = self.parryable() orelse return;
        if (!foe.caught(self, reach)) return;
        self.buttCd = BUTT_CD;
        self.biteCd = BITE_CD;
        self.dust(self.noseWorld(), 8, 2.4);
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light, .none => self.enterStun(.stunlight),
        }
    }

    pub fn update(self: *Mastodon, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        self.heroHit = null;
        self.landed = false;
        self.bellowed = false;
        self.stamped = false;
        self.swept = false;
        self.snapped = false;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.justDied = false;
        self.parried = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer if (!self.airborne()) grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.vit.tick(dt);
        self.elapsed += dt;
        self.t += dt;
        self.buttCd = mathx.maxF(0, self.buttCd - dt);
        self.biteCd = mathx.maxF(0, self.biteCd - dt);
        self.chargeCd = mathx.maxF(0, self.chargeCd - dt);
        self.lungeCd = mathx.maxF(0, self.lungeCd - dt);
        self.tailCd = mathx.maxF(0, self.tailCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, foe.tetherFor(self), hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        var moved: f32 = 0;
        const sensed = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        const bearing = self.bearingTo(hero);

        switch (self.state) {
            .dead => {
                self.speed = 0;
                self.lift = 0;
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
            .stunlight, .stunheavy => {
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                self.lift = approach(self.lift, 0, dt * 6.0);
                if (self.t >= combat.foeStunDur(self.state == .stunheavy)) self.enter(.idle);
            },
            .butt => {
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                if (self.t < BUTT_WIND) self.faceToward(hero, dt);
                const s = self.t - BUTT_WIND;
                if (s >= BUTT_STRIKE * BUTT_IMPACT_K and s < BUTT_STRIKE) self.tryFront(hero, BUTT_HIT, BUTT_R, BUTT_FRONT_DOT);
                if (self.t >= BUTT_WIND + BUTT_STRIKE + BUTT_RECOVER) {
                    self.heroLatch = false;
                    self.enter(.idle);
                }
            },
            .bite => {
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                if (self.t < BITE_WIND) self.faceToward(hero, dt);
                const s = self.t - BITE_WIND;
                if (s >= 0 and s < BITE_STRIKE) {
                    // THE WHOLE BEAST COMES FORWARD THROUGH THE STRIKE, and the jaws are judged off where it arrives.
                    mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), BITE_LUNGE * self.scale * dt / BITE_STRIKE, bounds);
                    if (s >= BITE_STRIKE * BITE_IMPACT_K) self.tryFront(hero, BITE_HIT, BITE_R, BITE_FRONT_DOT);
                }
                if (s >= BITE_STRIKE and s - dt < BITE_STRIKE) {
                    self.snapped = true;
                    self.stamped = true;
                    self.dust(self.footWorld(wolf.PAWL), DUST_STEP * 2, 2.2);
                    self.dust(self.footWorld(wolf.PAWR), DUST_STEP * 2, 2.2);
                }
                if (self.t >= BITE_WIND + BITE_STRIKE + BITE_RECOVER) {
                    self.heroLatch = false;
                    self.enter(.idle);
                }
            },
            .charge_wind => {
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                self.faceToward(hero, dt);
                // The paw: a stamp at the end of the wind the dust answers.
                if (self.t >= CHARGE_WIND * 0.55 and self.t - dt < CHARGE_WIND * 0.55) {
                    self.stamped = true;
                    self.dust(self.footWorld(wolf.PAWR), DUST_STEP * 3, 2.4);
                }
                if (self.t >= CHARGE_WIND) {
                    self.passed = false;
                    self.charging = true;
                    self.bellowed = true;
                    self.enter(.charge);
                }
            },
            .charge => {
                // A LINE HE CAN BARELY BEND: the turn is a fraction of his walk's, so a step aside is a step aside.
                foe.faceToward(self.pos, &self.facing, hero, CHARGE_TURN, dt);
                self.speed = approach(self.speed, CHARGE_SPEED, ACCEL * 4.0 * dt);
                moved = self.travel(dt, bounds);
                self.tryCharge(hero);
                const rel = mathx.subV(hero, self.pos);
                const f = mathx.headingDir(self.facing);
                if (rel.x * f.x + rel.z * f.z < -self.bodyR()) self.passed = true;
                if (self.heroLatch or self.passed or self.t >= CHARGE_DUR) {
                    self.charging = false;
                    self.chargeCd = CHARGE_CD * self.aiRng.range(0.9, 1.25);
                    self.dust(self.footWorld(wolf.PAWL), DUST_STEP * 4, 3.0);
                    self.enter(.charge_rec);
                }
            },
            .charge_rec => {
                // The skid: he keeps coming for a stride and stops.
                self.speed = approach(self.speed, 0, ACCEL * 2.2 * dt);
                moved = self.travel(dt, bounds);
                if (self.t >= CHARGE_RECOVER) {
                    self.heroLatch = false;
                    self.enter(.idle);
                }
            },
            .lunge_wind => {
                self.speed = approach(self.speed, 0, ACCEL * 3.0 * dt);
                self.faceToward(hero, dt);
                if (self.t >= LUNGE_WIND) {
                    const way = mathx.dirXZ(self.pos, hero);
                    const gap = mathx.minF(mathx.distXZ(self.pos, hero), LUNGE_REACH);
                    self.launch = mathx.scaleV(way, gap);
                    self.landAt = mathx.addV(self.pos, self.launch);
                    self.bellowed = true;
                    self.enter(.lunge_air);
                }
            },
            .lunge_air => {
                const u = mathx.clampF(self.t / LUNGE_AIR, 0, 1);
                const step = mathx.lenV(self.launch) / LUNGE_AIR * dt;
                mathx.stepXZ(&self.pos, mathx.normV(self.launch), step, bounds);
                moved = step;
                self.lift = LUNGE_UP * mathx.sinf(std.math.pi * u) * self.scale;
                if (u >= 1.0) {
                    self.lift = 0;
                    self.landed = true;
                    self.dust(self.pos, DUST_LAND, 4.2);
                    if (mathx.distXZ(self.pos, hero) <= LUNGE_R * self.scale + foe.HERO_R) {
                        self.heroHit = LUNGE_HIT;
                        self.leash.noteCombat();
                    }
                    self.lungeCd = LUNGE_CD * self.aiRng.range(0.9, 1.2);
                    self.enter(.lunge_rec);
                }
            },
            .lunge_rec => {
                self.speed = 0;
                if (self.t >= LUNGE_RECOVER) self.enter(.idle);
            },
            .tail => {
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                const s = self.t - TAIL_WIND;
                if (s >= TAIL_SWING * TAIL_IMPACT_K and s < TAIL_SWING) self.tryTail(hero);
                // THE SWIPE TURNS HIM, AND IT IS VIOLENT: he twists AGAINST it through the load, whips round past the mark inside the swing, and the hindquarters settle back over the recover.
                const tp = self.tailPhase();
                const load = TAIL_WIND * TAIL_LOAD;
                if (self.t < load) {
                    self.facing = self.turnFrom - self.tailSide * TAIL_TWIST * mathx.smoothstep(0, 1, self.t / load);
                } else {
                    const sweep = foe.swingCurve(tp.whip) * (TAIL_TWIST + std.math.pi + TAIL_OVER) - TAIL_OVER * mathx.smoothstep(0, 1, tp.settle);
                    self.facing = self.turnFrom - self.tailSide * TAIL_TWIST + self.tailSide * sweep;
                    if (self.t - dt < load) self.swept = true;
                    if (tp.whip >= 1.0 and !self.tailLanded) {
                        self.tailLanded = true;
                        self.stamped = true;
                        self.dust(self.footWorld(wolf.HPAWL), DUST_STEP * 3, 2.6);
                        self.dust(self.footWorld(wolf.HPAWR), DUST_STEP * 3, 2.6);
                    }
                }
                if (self.t >= TAIL_WIND + TAIL_SWING + TAIL_RECOVER) {
                    self.heroLatch = false;
                    self.tailCd = TAIL_CD * self.aiRng.range(0.9, 1.2);
                    self.enter(.idle);
                }
            },
            .idle, .walk => {
                const homeGap = mathx.distXZ(self.pos, foe.homeFor(self));
                switch (classify(sensed, bearing, self.scale, self.tailCd <= 0, self.biteCd <= 0, self.buttCd <= 0, self.lungeCd <= 0 and foe.canLeap(&self.root), self.chargeCd <= 0 and !self.root.held())) {
                    .tail => {
                        self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                        self.heroLatch = false;
                        self.turnFrom = self.facing;
                        self.tailSide = if (bearing >= 0) 1.0 else -1.0;
                        self.heroSide = self.tailSide;
                        self.enter(.tail);
                    },
                    .bite => {
                        self.heroLatch = false;
                        self.biteCd = BITE_CD * self.aiRng.range(0.85, 1.25);
                        self.enter(.bite);
                    },
                    .butt => {
                        self.heroLatch = false;
                        self.buttCd = BUTT_CD * self.aiRng.range(0.85, 1.25);
                        self.enter(.butt);
                    },
                    .lunge => {
                        self.heroLatch = false;
                        self.enter(.lunge_wind);
                    },
                    .charge => {
                        self.heroLatch = false;
                        self.enter(.charge_wind);
                    },
                    .close => {
                        self.faceToward(self.nav.aim(self.pos, hero), dt);
                        const stop = foe.hurtReach(BITE_R, self.scale) * 0.8 + foe.HERO_R;
                        if (mathx.distXZ(self.pos, hero) > stop) {
                            self.speed = approach(self.speed, CLOSE_SPEED, ACCEL * dt);
                            moved = self.travel(dt, bounds);
                            self.state = .walk;
                        } else {
                            self.speed = approach(self.speed, 0, ACCEL * dt);
                            self.state = .idle;
                        }
                    },
                    .hold => {
                        if (foe.postWant(self, dt, sensed, AGGRO_R)) |go| {
                            self.faceToward(self.nav.aim(self.pos, go), dt);
                            self.speed = approach(self.speed, WALK_SPEED, ACCEL * dt);
                            moved = self.travel(dt, bounds);
                            self.state = .walk;
                        } else if (homeGap > HOME_R) {
                            self.faceToward(self.nav.aim(self.pos, self.home), dt);
                            self.speed = approach(self.speed, WALK_SPEED, ACCEL * dt);
                            moved = self.travel(dt, bounds);
                            self.state = .walk;
                        } else {
                            self.speed = approach(self.speed, 0, ACCEL * dt);
                            self.state = .idle;
                        }
                    },
                }
            },
        }

        self.speedS = approach(self.speedS, self.speed, GAIT_BLEND * dt);
        if (moved > 0) self.phase = wolf.wrap01(self.phase + moved / (strideFor(self.speed) * self.scale));
        self.footfalls(dt);
        self.takeParry();
        self.pose();
        self.tryHit(blade);
        return self.heroHit;
    }

    fn travel(self: *Mastodon, dt: f32, bounds: f32) f32 {
        const step = self.speed * dt;
        const way = if (self.state == .charge or self.state == .charge_rec) mathx.headingDir(self.facing) else self.nav.along(mathx.headingDir(self.facing));
        mathx.stepXZ(&self.pos, way, step, bounds);
        return step;
    }

    fn tryFront(self: *Mastodon, hero: rl.Vector3, hit: combat.Hit, r: f32, dot: f32) void {
        if (self.heroLatch) return;
        if (!foe.inFront(self.pos, self.facing, hero, foe.hurtReach(r, self.scale), dot)) return;
        self.heroHit = hit;
        self.heroLatch = true;
        self.leash.noteCombat();
    }

    /// The horns meet him: a strip `CHARGE_HALF_W` either side of the line, from the body out to the nose.
    fn tryCharge(self: *Mastodon, hero: rl.Vector3) void {
        if (self.heroLatch) return;
        const f = mathx.headingDir(self.facing);
        const nose = v3(self.pos.x + f.x * CHARGE_NOSE * self.scale, self.pos.y, self.pos.z + f.z * CHARGE_NOSE * self.scale);
        const q = mathx.closestOnSegV(v3(hero.x, self.pos.y, hero.z), self.pos, nose);
        if (mathx.distXZ(q, hero) > CHARGE_HALF_W * self.scale + foe.HERO_R) return;
        self.heroHit = CHARGE_HIT;
        self.heroLatch = true;
        self.leash.noteCombat();
    }

    fn tryTail(self: *Mastodon, hero: rl.Vector3) void {
        if (self.heroLatch) return;
        if (mathx.distXZ(self.pos, hero) > foe.hurtReach(TAIL_R, self.scale)) return;
        // Behind him, as he was pointed when the tail went — the sweep is a rear arc about THAT facing.
        const back = mathx.wrapPi(self.turnFrom + std.math.pi);
        const to = mathx.dirXZ(self.pos, hero);
        if (mathx.lenXZ(to) > 1e-4 and !combat.withinArc(mathx.headingXZ(to), back, TAIL_ARC)) return;
        self.heroHit = TAIL_HIT;
        self.heroLatch = true;
        self.leash.noteCombat();
    }

    pub fn tryHit(self: *Mastodon, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        const heavy = foe.wounded(self, s, blade, .{ .light = 0.25, .heavy = 0.55 });
        self.blood(s.contact, s.dir, if (heavy) BLOOD_HEAVY else BLOOD_LIGHT, if (heavy) 6.5 else 4.8);
        switch (s.reaction) {
            .death => {
                self.blood(s.contact, s.dir, BLOOD_DEATH, 5.5);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn enter(self: *Mastodon, s: State) void {
        self.state = s;
        self.t = 0;
        if (s == .tail) self.tailLanded = false;
    }
    fn enterStun(self: *Mastodon, s: State) void {
        self.heroLatch = false;
        self.charging = false;
        self.enter(s);
    }
    fn enterDeath(self: *Mastodon) void {
        if (self.state == .dead) return;
        self.heroLatch = false;
        self.charging = false;
        self.lift = 0;
        self.enter(.dead);
        self.justDied = true;
    }
    pub fn stagger(self: *Mastodon, heavy: bool) void {
        if (self.state == .dead) return;
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Mastodon) void {
        self.enterDeath();
    }
    pub fn debugButt(self: *Mastodon) void {
        self.heroLatch = false;
        self.enter(.butt);
    }
    pub fn debugBite(self: *Mastodon) void {
        self.heroLatch = false;
        self.enter(.bite);
    }
    pub fn debugCharge(self: *Mastodon) void {
        self.heroLatch = false;
        self.enter(.charge_wind);
    }
    pub fn debugLunge(self: *Mastodon) void {
        self.heroLatch = false;
        self.enter(.lunge_wind);
    }
    pub fn debugTail(self: *Mastodon, side: f32) void {
        self.heroLatch = false;
        self.turnFrom = self.facing;
        self.tailSide = side;
        self.enter(.tail);
    }
    pub fn stageGather(self: *Mastodon, u: f32) void {
        self.state = .charge_wind;
        self.t = mathx.clampF(u, 0, 1) * CHARGE_WIND;
        self.pose();
    }

    fn footWorld(self: *const Mastodon, paw: usize) rl.Vector3 {
        return foe.markOn(self.xf[paw], mathx.zero3);
    }

    /// Every footfall of a body this heavy raises dust, and the amble raises more of it.
    fn footfalls(self: *Mastodon, dt: f32) void {
        if (self.speedS < 0.3) return;
        const g = gaitAt(self.speedS);
        const ph = wolf.limbPhases(self.phase, g);
        const was = wolf.limbPhases(wolf.wrap01(self.phase - self.speedS * dt / (strideFor(self.speedS) * self.scale)), g);
        inline for (.{ wolf.HPAWL, wolf.HPAWR, wolf.PAWL, wolf.PAWR }, 0..) |paw, i| {
            if (!wolf.planted(was[i], g) and wolf.planted(ph[i], g)) {
                self.dust(self.footWorld(paw), DUST_STEP, 1.2 + 0.25 * self.speedS);
            }
        }
    }

    fn dust(self: *Mastodon, at: rl.Vector3, n: i32, spd: f32) void {
        foe.spray(&self.parts, &self.fxHead, &self.fxRng, v3(at.x, self.pos.y, at.z), v3(0, 1, 0), n, spd, self.scale, DUST_SPRAY);
    }
    fn blood(self: *Mastodon, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32) void {
        foe.spray(&self.parts, &self.fxHead, &self.fxRng, at, dir, n, spd, self.scale, BLOOD_SPRAY);
    }

    pub fn drawFx(self: *const Mastodon) void {
        foe.drawParticles(&self.parts);
    }
    pub fn draw(self: *const Mastodon, model: *const Model) void {
        model.draw(self);
    }

    fn stunAmount(self: *const Mastodon) f32 {
        if (self.state != .stunlight and self.state != .stunheavy) return 0;
        return foe.stunCurve(self.t, self.state == .stunheavy);
    }
    /// -1 the head drawn back, +1 driven through: the butt's one clock.
    fn buttAmt(self: *const Mastodon) f32 {
        if (self.state != .butt) return 0;
        if (self.t < BUTT_WIND) return -mathx.smoothstep(0, BUTT_WIND * 0.9, self.t);
        const s = self.t - BUTT_WIND;
        if (s < BUTT_STRIKE) return lerpF(-1.0, 1.0, foe.swingCurve(s / BUTT_STRIKE));
        return 1.0 - mathx.smoothstep(BUTT_STRIKE, BUTT_STRIKE + BUTT_RECOVER * 0.7, s);
    }
    fn biteAmt(self: *const Mastodon) f32 {
        if (self.state != .bite) return 0;
        if (self.t < BITE_WIND) return -mathx.smoothstep(0, BITE_WIND * 0.9, self.t);
        const s = self.t - BITE_WIND;
        if (s < BITE_STRIKE) return lerpF(-1.0, 1.0, foe.swingCurve(s / BITE_STRIKE));
        return 1.0 - mathx.smoothstep(BITE_STRIKE, BITE_STRIKE + BITE_RECOVER * 0.7, s);
    }
    /// 0..1 through the charge's wind: the head comes down, the forequarters load.
    fn loadAmt(self: *const Mastodon) f32 {
        return switch (self.state) {
            .charge_wind => mathx.smoothstep(0, CHARGE_WIND * 0.9, self.t),
            .charge => 1.0,
            .charge_rec => 1.0 - mathx.smoothstep(0, CHARGE_RECOVER * 0.7, self.t),
            else => 0,
        };
    }
    /// The lunge: crouch through the wind, stretched in the air, and DOWN ON HIS KNEES through the recover — the whole long moment he cannot answer.
    fn lungeAmt(self: *const Mastodon) struct { crouch: f32, air: f32, down: f32 } {
        return switch (self.state) {
            .lunge_wind => .{ .crouch = mathx.smoothstep(0, LUNGE_WIND * 0.85, self.t), .air = 0, .down = 0 },
            .lunge_air => .{ .crouch = 0, .air = mathx.sinf(std.math.pi * mathx.clampF(self.t / LUNGE_AIR, 0, 1)), .down = 0 },
            .lunge_rec => .{ .crouch = 0, .air = 0, .down = mathx.smoothstep(0, 0.18, self.t) * (1.0 - mathx.smoothstep(LUNGE_RECOVER * 0.7, LUNGE_RECOVER, self.t)) },
            else => .{ .crouch = 0, .air = 0, .down = 0 },
        };
    }
    /// The whip and the settle behind it, 0..1 each — what the turn, the roll and the hop all read.
    fn tailPhase(self: *const Mastodon) struct { whip: f32, settle: f32 } {
        if (self.state != .tail) return .{ .whip = 0, .settle = 0 };
        const load = TAIL_WIND * TAIL_LOAD;
        const span = TAIL_SWING + TAIL_WIND * (1.0 - TAIL_LOAD);
        return .{
            .whip = mathx.clampF((self.t - load) / span, 0, 1),
            .settle = mathx.clampF((self.t - load - span) / (TAIL_RECOVER * 0.7), 0, 1),
        };
    }
    /// The head shaking off the bite through the recover, 1 at the snap and gone before the next choice.
    fn biteToss(self: *const Mastodon) f32 {
        if (self.state != .bite or self.t < BITE_WIND + BITE_STRIKE) return 0;
        return 1.0 - mathx.smoothstep(0, BITE_RECOVER * 0.8, self.t - BITE_WIND - BITE_STRIKE);
    }
    /// -1 the tail coiled to the far side, +1 swept through.
    fn tailAmt(self: *const Mastodon) f32 {
        if (self.state != .tail) return 0;
        if (self.t < TAIL_WIND) return -mathx.smoothstep(0, TAIL_WIND * 0.9, self.t);
        const s = self.t - TAIL_WIND;
        if (s < TAIL_SWING) return lerpF(-1.0, 1.0, foe.swingCurve(s / TAIL_SWING));
        return 1.0 - mathx.smoothstep(TAIL_SWING, TAIL_SWING + TAIL_RECOVER * 0.8, s);
    }

    pub fn pose(self: *Mastodon) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = foe.rigSink(SINK_DEPTH, self.scale, self.fade);
        const g = gaitAt(self.speedS);
        const stride = strideFor(self.speedS);
        const ph = wolf.limbPhases(self.phase, g);
        const m = mathx.clampF(self.speedS / WALK_SPEED, 0, 1);
        const fast = mathx.clampF((self.speedS - WALK_SPEED) / (CHARGE_SPEED - WALK_SPEED), 0, 1);

        const react = self.stunAmount();
        const dk: f32 = if (self.state == .dead) mathx.clampF(self.t / (DEATH_DUR * 0.7), 0, 1) else 0;
        const butt = self.buttAmt();
        const bite = self.biteAmt();
        const load = self.loadAmt();
        const lg = self.lungeAmt();
        const tail = self.tailAmt();
        const whip = mathx.sinf(std.math.pi * self.tailPhase().whip);
        const toss = self.biteToss();
        const cyc = self.phase * std.math.tau;

        // ELEPHANT: the back stays LEVEL — the bounce is a hair — and the mass ROLLS onto the standing side; the head nods low with the forelegs. The tail whip rolls him hard into the swing and lifts the rear; the bite loads down and plunges.
        const roll = 2.6 * mathx.sinf(cyc) * m * (1.0 + 0.6 * fast) + 11.0 * self.tailSide * whip;
        const bounce = 0.008 * W * mathx.sinf(cyc * 2.0) * m + TAIL_HOP * W * whip;
        const crouch = 0.14 * lg.crouch + 0.24 * lg.down + 0.06 * load + 0.08 * react + 0.42 * dk + 0.07 * mathx.maxF(0, -bite);
        const pitch = 6.0 * load + 10.0 * mathx.maxF(0, butt) - 5.0 * mathx.maxF(0, -butt) + 14.0 * lg.crouch - 10.0 * lg.air + 12.0 * lg.down - 4.0 * react + 9.0 * mathx.maxF(0, bite) - 4.0 * mathx.maxF(0, -bite) + 7.0 * whip;
        const breath = (mathx.sinf(self.elapsed * 0.9) * 0.006 + mathx.sinf(self.elapsed * 0.45 + self.seed * 4.0) * 0.004) * W;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            mul(scaleM(fs, fs, fs), mul3(rx(-pitch), rz(roll + 52.0 * mathx.smoothstep(0, 1, dk)), ry(0))),
            mul(tr(0, (self.rest[ROOT].y + breath + bounce - crouch * W) * fs + self.lift + sink, 0), ry(mathx.degrees(self.facing))),
            heromod.rootAt(self.pos),
        );
        const flex = mathx.sinf(cyc) * m * 3.0;
        heromod.setJoint(&wx, &self.rest, SPINE, ROOT, rx(-flex * 0.4 - 4.0 * react + 6.0 * load + 8.0 * lg.down));
        heromod.setJoint(&wx, &self.rest, CHEST, SPINE, mul(rx(-flex * 0.4 - 4.0 * react + 8.0 * load - 8.0 * dk), rz(-roll * 0.4)));

        // The neck is short and thick; the head hangs low and swings with the stride, drops right down for the charge and REARS for the butt.
        const sway = 5.0 * mathx.sinf(cyc) * m;
        const rear = mathx.maxF(0, -butt);
        const drive = mathx.maxF(0, butt);
        const neckPitch = 14.0 * m * 0.3 - 8.0 * react - 26.0 * rear + 24.0 * drive + 22.0 * load - 24.0 * mathx.maxF(0, -bite) + 26.0 * mathx.maxF(0, bite) + 30.0 * lg.down - 10.0 * lg.air;
        heromod.setJoint(&wx, &self.rest, NECK, CHEST, mul(rx(neckPitch), ry(sway * 0.6)));
        heromod.setJoint(&wx, &self.rest, HEAD, NECK, mul(rx(6.0 + 14.0 * react + 10.0 * drive - 8.0 * rear + 8.0 * load - 20.0 * dk), ry(sway * 0.5 + 55.0 * self.heroSide * mathx.maxF(0, tail) + 16.0 * toss * mathx.sinf(self.t * 28.0))));
        // The jaws: wide through the wind, CLENCHED at the drive.
        const jaw = 4.0 + 58.0 * mathx.maxF(0, -bite) - 2.0 * mathx.maxF(0, bite) + 14.0 * react + 26.0 * dk + 12.0 * load + 20.0 * lg.air;
        heromod.setJoint(&wx, &self.rest, JAW, HEAD, rx(jaw));

        // THE TAIL: long, and it hangs; it swings lazily with the walk and it LASHES for the swipe, coiled to one side and whipped round to the other.
        const lazy = mathx.sinf(self.elapsed * 1.6 + self.seed * 5.0) * (5.0 + 10.0 * m) * (1.0 - dk);
        const lash = self.tailSide * 110.0 * tail;
        heromod.setJoint(&wx, &self.rest, TAIL0, ROOT, mul(ry(lazy + lash * 0.55), rx(-10.0 + 20.0 * dk + 14.0 * @abs(tail))));
        heromod.setJoint(&wx, &self.rest, TAIL1, TAIL0, mul(ry(lazy * 0.8 + lash * 0.35), rx(8.0 + 6.0 * @abs(tail))));
        heromod.setJoint(&wx, &self.rest, TAIL2, TAIL1, mul(ry(lazy * 0.6 + lash * 0.25), rx(10.0)));
        // Ears like sails, flapping slow, laid back for the charge.
        const flap = mathx.sinf(self.elapsed * 1.1 + self.seed * 3.0) * 10.0 * (1.0 - load);
        heromod.setJoint(&wx, &self.rest, EARL, HEAD, mul(rz(-24.0 - flap - 18.0 * react), ry(-30.0 * load)));
        heromod.setJoint(&wx, &self.rest, EARR, HEAD, mul(rz(24.0 + flap + 18.0 * react), ry(30.0 * load)));

        const tuck: f32 = if (self.state == .lunge_air) 0.5 * lg.air else dk * 0.5;
        wolf.legs(&wx, &self.rest, W, ph, g, stride, m * (1.0 - dk) * (1.0 - lg.air), crouch, tuck);
        self.xf = wx;
    }
};

const CAP_N = wf.MAX_PER_KIND;

pub const Drove = struct {
    model: Model,
    band: [CAP_N]Mastodon = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Drove {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Drove) []Mastodon {
        return self.band[0..self.n];
    }
    pub fn liveConst(self: *const Drove) []const Mastodon {
        return self.band[0..self.n];
    }
    pub fn reset(self: *Drove, m: *const wf.Map) void {
        foe.resetGroup(Mastodon, &self.band, &self.n, m, .mastodon);
    }
    pub fn clear(self: *Drove) void {
        self.n = 0;
    }
    pub fn setShader(self: *Drove, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn setParry(self: *Drove, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    pub fn anyParried(self: *const Drove) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn update(self: *Drove, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    pub fn anyLanded(self: *const Drove) bool {
        for (self.liveConst()) |*m| {
            if (m.landed) return true;
        }
        return false;
    }
    pub fn anyStamped(self: *const Drove) bool {
        for (self.liveConst()) |*m| {
            if (m.stamped) return true;
        }
        return false;
    }
    pub fn draw(self: *const Drove, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Drove) void {
        for (self.liveConst()) |*m| m.drawFx();
    }
    pub fn pierce(self: *Drove, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Drove) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Drove) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Drove) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Drove) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

fn segLen(i: usize) f32 {
    const rest = restPose();
    for (0..N) |c| {
        if (wolf.PARENT[c] == @as(i32, @intCast(i))) return mathx.lenV(mathx.subV(rest[i], rest[c])) / W;
    }
    return 0;
}

fn buildBones() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = hipMesh();
    mesh[SPINE] = loinMesh();
    mesh[CHEST] = withersMesh();
    mesh[NECK] = neckMesh();
    mesh[HEAD] = headMesh();
    mesh[JAW] = jawMesh();
    mesh[TAIL0] = tailMesh(0, 0.30);
    mesh[TAIL1] = tailMesh(1, 0.34);
    mesh[TAIL2] = tailMesh(2, 0.36);
    mesh[EARL] = earMesh(1.0);
    mesh[EARR] = earMesh(-1.0);
    inline for (.{ wolf.SHL, wolf.SHR }, .{ 1.0, -1.0 }) |b, s| mesh[b] = columnMesh(s, segLen(b), 0.115, 0.098);
    inline for (.{ wolf.ELL, wolf.ELR }, .{ 1.0, -1.0 }) |b, s| mesh[b] = columnMesh(s, segLen(b), 0.096, 0.086);
    inline for (.{ wolf.CAL, wolf.CAR }, .{ 1.0, -1.0 }) |b, s| mesh[b] = columnMesh(s, segLen(b), 0.086, 0.088);
    inline for (.{ wolf.PAWL, wolf.PAWR }) |b| mesh[b] = footMesh();
    inline for (.{ wolf.HIPL, wolf.HIPR }, .{ 1.0, -1.0 }) |b, s| mesh[b] = columnMesh(s, segLen(b), 0.130, 0.104);
    inline for (.{ wolf.STL, wolf.STR }, .{ 1.0, -1.0 }) |b, s| mesh[b] = columnMesh(s, segLen(b), 0.100, 0.088);
    inline for (.{ wolf.HKL, wolf.HKR }, .{ 1.0, -1.0 }) |b, s| mesh[b] = columnMesh(s, segLen(b), 0.088, 0.090);
    inline for (.{ wolf.HPAWL, wolf.HPAWR }) |b| mesh[b] = footMesh();
    return mesh;
}

/// A horn: a curved capsule chain off a root, thick and blunt (nothing ends in a point), uneven between horns and never along one.
fn hornInto(b: *Builder, rng: *mathx.Rng, root: rl.Vector3, dir: rl.Vector3, len: f32, r0: f32) void {
    const curl = rng.range(0.10, 0.28);
    const d = mathx.normV(dir);
    const side = mathx.normV(v3(-d.z, 0, d.x));
    const p1 = mathx.addV(root, mathx.scaleV(d, len * 0.45));
    const p2 = mathx.addV(mathx.addV(root, mathx.scaleV(d, len * 0.85)), mathx.addV(mathx.scaleV(side, curl * len * rng.signed()), v3(0, curl * len, 0)));
    b.addCapsule(root, p1, r0, r0 * 0.72, 7, HORN_DK);
    b.addCapsule(p1, p2, r0 * 0.72, r0 * 0.36, 6, HORN);
    b.addBlob(p2, v3(r0 * 0.40, r0 * 0.36, r0 * 0.40), 4, 7, HORN_LT);
}

fn hipMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    b.addBlob(v3(0, 0.02 * W, 0.02 * W), v3(0.22 * W, 0.20 * W, 0.26 * W), 10, 8, HIDE);
    b.addBlob(v3(0, -0.10 * W, 0.04 * W), v3(0.19 * W, 0.10 * W, 0.22 * W), 8, 6, BELLY);
    b.addBlob(v3(0, 0.14 * W, -0.02 * W), v3(0.14 * W, 0.07 * W, 0.20 * W), 6, 6, HIDE_DK);
    return b.toMesh();
}

fn loinMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    b.addBlob(v3(0, 0.005 * W, 0.08 * W), v3(0.235 * W, 0.215 * W, 0.34 * W), 10, 8, HIDE);
    b.addBlob(v3(0, -0.14 * W, 0.08 * W), v3(0.21 * W, 0.10 * W, 0.30 * W), 8, 6, BELLY);
    return b.toMesh();
}

/// THE SHOULDERS, and the horns that stand off them: a ridge of them down the withers and a rank off each shoulder.
fn withersMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x3A01);
    b.setMat(.hide);
    b.addBlob(v3(0, 0.02 * W, -0.06 * W), v3(0.245 * W, 0.235 * W, 0.36 * W), 10, 8, HIDE);
    b.addBlob(v3(0, -0.13 * W, -0.04 * W), v3(0.22 * W, 0.11 * W, 0.30 * W), 8, 6, BELLY);
    b.addBlob(v3(0, 0.20 * W, -0.10 * W), v3(0.17 * W, 0.11 * W, 0.24 * W), 8, 6, HIDE_DK);
    b.setMat(.stone);
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const f = @as(f32, @floatFromInt(i)) / 4.0;
        const z = (-0.28 + 0.36 * f) * W;
        hornInto(&b, &rng, v3(rng.signed() * 0.03 * W, (0.28 - 0.04 * f) * W, z), v3(rng.signed() * 0.3, 1.0, -0.35 + 0.5 * f), (0.16 + 0.08 * rng.float()) * W, 0.040 * W);
    }
    inline for (.{ 1.0, -1.0 }) |side| {
        var k: u32 = 0;
        while (k < 4) : (k += 1) {
            const f = @as(f32, @floatFromInt(k)) / 3.0;
            const root = v3(side * (0.20 + 0.03 * f) * W, (0.16 - 0.12 * f) * W, (-0.02 + 0.18 * f) * W);
            hornInto(&b, &rng, root, v3(side * 1.0, 0.45 - 0.3 * f, 0.3 + 0.4 * f), (0.14 + 0.10 * rng.float()) * W, 0.036 * W);
        }
    }
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x3A02);
    b.setMat(.hide);
    b.addCapsule(v3(0, 0.02 * W, -0.10 * W), v3(0, -0.04 * W, 0.20 * W), 0.20 * W, 0.17 * W, 10, HIDE);
    b.addBlob(v3(0, -0.10 * W, 0.06 * W), v3(0.15 * W, 0.08 * W, 0.16 * W), 7, 5, BELLY);
    b.setMat(.stone);
    inline for (.{ 1.0, -1.0 }) |side| {
        hornInto(&b, &rng, v3(side * 0.16 * W, 0.10 * W, 0.04 * W), v3(side * 0.8, 0.7, 0.2), 0.14 * W, 0.030 * W);
    }
    return b.toMesh();
}

/// THE HEAD IS A CROWN OF HORNS: a great pair off the brow, a boss of short ones over the skull, and the two off the jawline that a headbutt leads with.
fn headMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x3A03);
    b.setMat(.hide);
    b.addBlob(v3(0, 0.02 * W, 0.02 * W), v3(0.17 * W, 0.15 * W, 0.20 * W), 9, 7, HIDE);
    b.addBlob(v3(0, -0.02 * W, 0.16 * W), v3(0.13 * W, 0.10 * W, 0.12 * W), 8, 6, HIDE_LT);
    b.addBlob(v3(0, 0.10 * W, -0.04 * W), v3(0.14 * W, 0.08 * W, 0.14 * W), 6, 6, HIDE_DK);
    b.setMat(.plain);
    inline for (.{ 1.0, -1.0 }) |side| {
        b.addBlob(v3(side * 0.12 * W, 0.05 * W, 0.12 * W), v3(0.026 * W, 0.022 * W, 0.020 * W), 5, 6, EYE);
    }
    b.setMat(.stone);
    inline for (.{ 1.0, -1.0 }) |side| {
        hornInto(&b, &rng, v3(side * 0.10 * W, 0.12 * W, 0.08 * W), v3(side * 0.7, 0.8, 0.9), 0.30 * W, 0.052 * W);
        hornInto(&b, &rng, v3(side * 0.13 * W, -0.05 * W, 0.20 * W), v3(side * 0.5, 0.2, 1.0), 0.20 * W, 0.040 * W);
        hornInto(&b, &rng, v3(side * 0.15 * W, 0.06 * W, -0.06 * W), v3(side * 1.0, 0.4, -0.2), 0.14 * W, 0.034 * W);
    }
    var i: u32 = 0;
    while (i < 6) : (i += 1) {
        const a = rng.angle();
        const rr = rng.range(0.04, 0.10) * W;
        const root = v3(mathx.cosf(a) * rr, 0.13 * W + rng.range(0, 0.03) * W, mathx.sinf(a) * rr - 0.02 * W);
        hornInto(&b, &rng, root, v3(mathx.cosf(a) * 0.4, 1.0, mathx.sinf(a) * 0.3), (0.07 + 0.06 * rng.float()) * W, 0.026 * W);
    }
    b.setMat(.plain);
    b.addBlob(v3(0, -0.06 * W, 0.19 * W), v3(0.10 * W, 0.036 * W, 0.06 * W), 7, 5, GUM);
    i = 0;
    while (i < 6) : (i += 1) {
        const f = (@as(f32, @floatFromInt(i)) - 2.5) / 2.5;
        b.addCapsule(v3(f * 0.080 * W, -0.06 * W, (0.22 - @abs(f) * 0.02) * W), v3(f * 0.084 * W, -0.10 * W, (0.21 - @abs(f) * 0.02) * W), 0.014 * W, 0.005 * W, 5, TOOTH);
    }
    return b.toMesh();
}

fn jawMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    b.addBlob(v3(0, -0.02 * W, 0.06 * W), v3(0.11 * W, 0.045 * W, 0.12 * W), 8, 6, HIDE_DK);
    b.setMat(.plain);
    b.addBlob(v3(0, 0.005 * W, 0.09 * W), v3(0.09 * W, 0.024 * W, 0.08 * W), 7, 5, GUM);
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const f = (@as(f32, @floatFromInt(i)) - 2.0) / 2.0;
        b.addCapsule(v3(f * 0.070 * W, 0.010 * W, (0.14 - @abs(f) * 0.02) * W), v3(f * 0.074 * W, 0.045 * W, (0.135 - @abs(f) * 0.02) * W), 0.012 * W, 0.005 * W, 5, TOOTH);
    }
    return b.toMesh();
}

fn tailMesh(i: u32, len: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    const r0: f32 = 0.070 - 0.014 * @as(f32, @floatFromInt(i));
    const tip = v3(0, -len * 0.45 * W, -len * W);
    b.addCapsule(v3(0, 0, 0), tip, r0 * W, r0 * 0.78 * W, 7, HIDE_DK);
    if (i == 2) {
        // The tuft: a club of hair, which is what a tail swipe hits with.
        b.addBlob(tip, v3(0.075 * W, 0.070 * W, 0.085 * W), 4, 8, HIDE_LT);
    }
    return b.toMesh();
}

fn earMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    b.addBlob(v3(side * 0.09 * W, 0.02 * W, -0.02 * W), v3(0.11 * W, 0.15 * W, 0.030 * W), 5, 7, HIDE);
    b.addBlob(v3(side * 0.08 * W, 0.02 * W, -0.01 * W), v3(0.08 * W, 0.11 * W, 0.020 * W), 4, 6, HIDE_LT);
    return b.toMesh();
}

/// A leg is a COLUMN: nearly as thick at the foot as at the joint — that is the whole of "elephant" in a leg.
fn columnMesh(side: f32, len: f32, r0: f32, r1: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    b.addBlob(v3(0, 0.01 * W, 0), v3(r0 * W * 1.1, r0 * W * 0.9, r0 * W * 1.1), 4, 8, HIDE);
    b.addCapsule(v3(0, 0, 0), v3(side * 0.004 * W, -len * W, 0), r0 * W, r1 * W, 9, HIDE);
    return b.toMesh();
}

fn footMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    b.addBlob(v3(0, 0.030 * W, 0.010 * W), v3(0.105 * W, 0.050 * W, 0.110 * W), 6, 9, HIDE_DK);
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        const a = -0.9 + 0.6 * @as(f32, @floatFromInt(i));
        b.addBlob(v3(mathx.sinf(a) * 0.085 * W, 0.020 * W, 0.06 * W + mathx.cosf(a) * 0.05 * W), v3(0.024 * W, 0.020 * W, 0.024 * W), 3, 6, HORN_DK);
    }
    return b.toMesh();
}

// ---------------------------------------------------------------------------------------------------------------

test "IT IS AN ELEPHANT ON ITS FEET: lateral sequence at every speed, never an aerial phase, a stride a beast's length" {
    const walk = gaitAt(WALK_SPEED);
    const amble = gaitAt(CHARGE_SPEED);
    try std.testing.expect(walk.duty > 0.5 and amble.duty > 0.5);
    try std.testing.expect(walk.lag > 0.6 and amble.lag > 0.6);
    // Lateral sequence: the forefoot on a side follows its own hind foot by more than half the stride (a trot's couplets sit at exactly half).
    try std.testing.expect(walk.lag > 0.5 and amble.lag > 0.5);
    std.debug.print("\n  mastodon gait: walk duty {d:.2} lag {d:.2}, amble duty {d:.2} lag {d:.2}; strides {d:.2} m walking, {d:.2} m charging\n", .{ walk.duty, walk.lag, amble.duty, amble.lag, strideFor(WALK_SPEED), strideFor(CHARGE_SPEED) });
    try std.testing.expect(strideFor(WALK_SPEED) > 1.6 and strideFor(CHARGE_SPEED) > strideFor(WALK_SPEED));
    var m = Mastodon.spawn(mathx.zero3, 0, 1.0, 0.3);
    std.debug.print("  mastodon {d:.2} m at the withers, head {d:.2} m up, crown {d:.2} m, body r {d:.2}\n", .{ W, m.lockPoint().y, m.topWorld().y, m.bodyR() });
    try std.testing.expect(m.lockPoint().y < W and m.lockPoint().y > W * 0.4);
    try std.testing.expect(foe.traitsOf(.mastodon).nature == .beast and !foe.isBoss(.mastodon));
}

test "EVERY BLOW LANDS ON THE MAN WHERE HE STANDS — butt and bite thrown for real across the band, once each, after a tell" {
    const dt: f32 = 1.0 / 120.0;
    var misses: usize = 0;
    var thrown: usize = 0;
    for ([_]f32{ wf.FOE_SCALE_LO, 1.0, wf.FOE_SCALE_HI }) |scale| {
        const probe = Mastodon.spawn(mathx.zero3, 0, scale, 0.3);
        const near = foe.closestApproach(probe.bodyR()) + 0.05;
        inline for (.{ .{ "butt", BUTT_R, State.butt }, .{ "bite", BITE_R, State.bite } }) |row| {
            const far = foe.hurtReach(row[1], scale) - 0.02;
            if (far > near) {
                for ([_]f32{ 0, 30 }) |deg| {
                    for ([_]f32{ 0.0, 0.5, 1.0 }) |u| {
                        const stand = lerpF(near, far, u);
                        var m = Mastodon.spawn(mathx.zero3, 0, scale, 0.3);
                        const a = mathx.radians(deg);
                        const hero = v3(@sin(a) * stand, 0, @cos(a) * stand);
                        m.heroLatch = false;
                        m.enter(row[2]);
                        thrown += 1;
                        var hit = false;
                        var firstAt: f32 = 0;
                        var t: f32 = 0;
                        while (t < 2.0) : (t += dt) {
                            if (m.update(dt, hero, 400.0, .{})) |_| {
                                if (!hit) firstAt = t;
                                hit = true;
                            }
                            if (m.state == .idle) break;
                        }
                        if (!hit) {
                            misses += 1;
                            std.debug.print("\n  mastodon {s} x{d:.2} at {d:.2} m, {d:.0} deg: MISSED\n", .{ row[0], scale, stand, deg });
                        } else try std.testing.expect(firstAt >= foe.TELL_MIN);
                    }
                }
            }
        }
    }
    std.debug.print("\n  mastodon: {d} strokes thrown across three scales, {d} billed nothing\n", .{ thrown, misses });
    try std.testing.expectEqual(@as(usize, 0), misses);
}

test "THE CHARGE COMES FROM A DISTANCE, DOWN A LINE, AND MEETS THE MAN WHO STANDS ON IT — and passes the one who steps off" {
    const dt: f32 = 1.0 / 120.0;
    var m = Mastodon.spawn(mathx.zero3, 0, 1.0, 0.3);
    m.leash.noteSeen();
    const hero = mathx.ground(0, 11.0);
    try std.testing.expectEqual(Choice.charge, classify(11.0, 0, 1.0, false, false, false, false, true));
    m.debugCharge();
    var hit = false;
    var top: f32 = 0;
    var t: f32 = 0;
    while (t < CHARGE_WIND + CHARGE_DUR + CHARGE_RECOVER) : (t += dt) {
        if (m.update(dt, hero, 400.0, .{})) |b| {
            hit = true;
            try std.testing.expectApproxEqAbs(CHARGE_HIT.dmg, b.dmg, 1e-4);
            try std.testing.expect(t + dt >= CHARGE_WIND - 1e-3);
        }
        top = @max(top, m.speed);
        if (m.state == .idle) break;
    }
    std.debug.print("\n  mastodon charge: reached {d:.1} m/s, landed={}, stood again at {d:.2} s\n", .{ top, hit, t });
    try std.testing.expect(hit and top > CHARGE_SPEED * 0.8);

    var side = Mastodon.spawn(mathx.zero3, 0, 1.0, 0.3);
    side.leash.noteSeen();
    side.debugCharge();
    var dodged = true;
    var passed = false;
    t = 0;
    while (t < CHARGE_WIND + CHARGE_DUR + CHARGE_RECOVER) : (t += dt) {
        // He steps four metres off the line the moment the beast commits.
        const h = if (t < CHARGE_WIND) mathx.ground(0, 11.0) else mathx.ground(4.0, 11.0);
        if (side.update(dt, h, 400.0, .{})) |_| dodged = false;
        if (side.passed) passed = true;
        if (side.state == .idle) break;
    }
    try std.testing.expect(dodged and passed);
}

test "THE JUMP-LUNGE COMES DOWN WHERE YOU STOOD AND LEAVES HIM ON HIS KNEES — the recovery is the longest window he gives" {
    const dt: f32 = 1.0 / 120.0;
    var m = Mastodon.spawn(mathx.zero3, 0, 1.0, 0.3);
    m.leash.noteSeen();
    const hero = mathx.ground(0, 6.0);
    try std.testing.expectEqual(Choice.lunge, classify(6.0, 0, 1.0, false, false, false, true, true));
    m.debugLunge();
    var hit = false;
    var peak: f32 = 0;
    var airT: f32 = 0;
    var downFor: f32 = 0;
    var t: f32 = 0;
    while (t < LUNGE_WIND + LUNGE_AIR + LUNGE_RECOVER + 0.2) : (t += dt) {
        if (m.update(dt, hero, 400.0, .{})) |b| {
            hit = true;
            try std.testing.expectApproxEqAbs(LUNGE_HIT.dmg, b.dmg, 1e-4);
        }
        if (m.airborne()) airT += dt;
        peak = @max(peak, m.lift);
        if (m.state == .lunge_rec) downFor += dt;
    }
    std.debug.print("\n  mastodon lunge: {d:.2} s in the air, {d:.2} m up, came down {d:.2} m from him, landed={}, then {d:.2} s on his knees\n", .{ airT, peak, mathx.distXZ(m.pos, hero), hit, downFor });
    try std.testing.expect(hit and airT > 0.4 and peak > 1.5);
    try std.testing.expect(mathx.distXZ(m.pos, hero) < LUNGE_R);
    try std.testing.expect(downFor >= LUNGE_RECOVER - 2.0 * dt);
    try std.testing.expect(LUNGE_RECOVER > BUTT_RECOVER * 2.0);
}

test "BEHIND HIM IS THE TAIL — the swipe bills the man at his back and brings him round to face where the man stood" {
    const dt: f32 = 1.0 / 120.0;
    var m = Mastodon.spawn(mathx.zero3, 0, 1.0, 0.3);
    m.leash.noteSeen();
    const hero = mathx.ground(0.6, -2.4);
    const bearing = m.bearingTo(hero);
    try std.testing.expect(@abs(bearing) >= TAIL_BEARING);
    try std.testing.expectEqual(Choice.tail, classify(2.5, bearing, 1.0, true, true, true, true, true));
    const facingWas = m.facing;
    m.debugTail(if (bearing >= 0) 1.0 else -1.0);
    var hits: u32 = 0;
    var t: f32 = 0;
    while (t < TAIL_WIND + TAIL_SWING + TAIL_RECOVER + 0.05) : (t += dt) {
        if (m.update(dt, hero, 400.0, .{})) |b| {
            hits += 1;
            try std.testing.expectApproxEqAbs(TAIL_HIT.dmg, b.dmg, 1e-4);
            try std.testing.expect(t + dt >= TAIL_WIND - 1e-3);
        }
    }
    const turned = mathx.degrees(@abs(mathx.wrapPi(m.facing - facingWas)));
    std.debug.print("\n  mastodon tail: {d} hit(s) on a man {d:.0} deg behind, and he came round {d:.0} deg\n", .{ hits, bearing, turned });
    try std.testing.expectEqual(@as(u32, 1), hits);
    try std.testing.expect(turned > 150.0);
    try std.testing.expect(@abs(m.bearingTo(hero)) < 40.0);

    var front = Mastodon.spawn(mathx.zero3, 0, 1.0, 0.3);
    front.debugTail(1.0);
    var frontHits: u32 = 0;
    t = 0;
    while (t < TAIL_WIND + TAIL_SWING + TAIL_RECOVER) : (t += dt) {
        if (front.update(dt, mathx.ground(0, 2.4), 400.0, .{})) |_| frontHits += 1;
    }
    try std.testing.expectEqual(@as(u32, 0), frontHits);
}

test "THE BANDS ARE ORDERED: bite inside butt inside the lunge inside the charge, all inside its notice" {
    try std.testing.expectEqual(Choice.bite, classify(1.5, 0, 1.0, true, true, true, true, true));
    try std.testing.expectEqual(Choice.butt, classify(1.5, 0, 1.0, true, false, true, true, true));
    try std.testing.expectEqual(Choice.lunge, classify(5.0, 0, 1.0, true, true, true, true, true));
    try std.testing.expectEqual(Choice.charge, classify(12.0, 0, 1.0, true, true, true, true, true));
    try std.testing.expectEqual(Choice.close, classify(12.0, 0, 1.0, true, true, true, true, false));
    try std.testing.expectEqual(Choice.close, classify(12.0, 100.0, 1.0, true, true, true, true, true));
    try std.testing.expectEqual(Choice.hold, classify(AGGRO_R + 1.0, 0, 1.0, true, true, true, true, true));
    const ogremod = @import("ogre.zig");
    std.debug.print("\n  mastodon blows: bite {d:.0}, butt {d:.0}, tail {d:.0}, charge {d:.0}, lunge {d:.0} (the ogre's slam is {d:.0})\n", .{ BITE_HIT.dmg, BUTT_HIT.dmg, TAIL_HIT.dmg, CHARGE_HIT.dmg, LUNGE_HIT.dmg, ogremod.SLAM_HIT.dmg });
    try std.testing.expect(LUNGE_HIT.dmg > ogremod.SLAM_HIT.dmg);
}
