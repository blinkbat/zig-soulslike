const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
const foe = @import("foe.zig");
const wolf = @import("wolf.zig");
const shroommod = @import("shroom.zig");
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

// THE ROTGORGER (owner's creature, owner's brief) — the quadruped rig's THIRD user, and **IT EATS THE DEAD**.
// Every body that falls anywhere on the field is food, its own kin included, and a gorger that is hurt will
// BREAK OFF MID-FIGHT to go and take it.
//
// **WHAT IT PUNISHES IS A SLOW CLEAR.** Kill the room and then take your time and you have laid a table; kill
// the gorger first, or fight it somewhere nothing has died. There is no other creature in the game whose
// difficulty is a function of what you already killed.
//
// **AND THE FEED IS THE WINDOW.** Head down in a carcass it does not track, does not turn and does not
// answer — `FEED_HEAL` back for `FEED_DUR` of standing still in front of you. Letting it eat is a TRADE, and
// it is a trade you are allowed to want: the punish is worth more than the heal if you are in reach of it.

pub const W: f32 = 1.02;
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

/// **THE CAP IS MESH, NOT A BONE.** It is grown INTO the withers rather than worn on them — a fruiting body
/// has no joint, and giving it one would let it lag the back it is part of.
const HIDE = rgba(46, 42, 34, 255);
const HIDE_DK = rgba(26, 24, 19, 255);
const HIDE_LT = rgba(64, 58, 46, 255);
const BELLY = rgba(72, 64, 52, 255);
const GUM = rgba(96, 52, 48, 255);
const TOOTH = rgba(178, 168, 140, 255);
const CAP_COL = shroommod.CAP_COL;
const CAP_DK = shroommod.CAP_DK;
const GILL = rgba(148, 132, 96, 255);
const EYE = rgba(196, 206, 132, 255);

pub const AGGRO_R: f32 = 15.0;
const HOME_R: f32 = 3.0;
const WALK_SPEED: f32 = wolf.WALK_SPEED * 0.90;
const CHASE_SPEED: f32 = wolf.TROT_SPEED * 1.02;
/// **IT GOES TO FOOD FASTER THAN IT COMES TO YOU**, which is what makes breaking off read as a decision
/// rather than as losing interest.
const FEED_RUSH: f32 = wolf.TROT_SPEED * 1.35;
const ACCEL: f32 = 5.0;
const GAIT_BLEND: f32 = 6.0;
const TURN_RATE: f32 = 3.2;

const BODY_R: f32 = 0.52;
const HURT_R: f32 = 0.78;
const CENTER_Y: f32 = 0.62;
const TOP_Y: f32 = 1.05;
const SINK_DEPTH: f32 = 0.42;

const HP_MAX: f32 = 155.0;
const POISE_MAX: f32 = 20.0;
const STANCE_MAX: f32 = 30.0;
const RESISTS = combat.resists(.{ .fire = -45, .chaos = 60, .cold = 10 });
pub const SOULS: u32 = 165;

const BITE_R: f32 = 1.55;
const BITE_FRONT_DOT: f32 = 0.55;
const BITE_WIND: f32 = 0.38;
const BITE_STRIKE: f32 = 0.16;
const BITE_RECOVER: f32 = 0.60;
const BITE_CD: f32 = 1.9;
pub const BITE_HIT = combat.Hit{ .dmg = 15, .poise = 13, .stance = 8, .elem = combat.elems(.{ .chaos = 9 }) };

// **THE TABLE.** A `Carrion` is stamped where any body in the world falls (`game.billDeaths`, the one place a
// death is billed) and keeps for `CARRION_LIFE`. It is FOOD, not a corpse: nothing else in the game reads it,
// and it is gone the moment a gorger finishes with it.
pub const CARRION_LIFE: f32 = 30.0;
pub const SMELL_R: f32 = 22.0;
/// It only leaves a fight for a meal it actually needs. At full health it stays on you.
const HUNGER_FRAC: f32 = 0.86;
const FEED_R: f32 = 1.0;
const FEED_WIND: f32 = 0.45;
const FEED_DUR: f32 = 2.4;
const FEED_RISE: f32 = 0.40;
/// **A THIRD OF ITS OWN BAR.** Small enough that one meal is not the fight; big enough that three are.
pub const FEED_HEAL: f32 = 52.0;

comptime {
    std.debug.assert(BITE_WIND >= foe.TELL_MIN);
    std.debug.assert(FEED_WIND >= foe.TELL_MIN);
    std.debug.assert(FEED_RUSH > CHASE_SPEED);
    std.debug.assert(FEED_HEAL > HP_MAX * 0.25 and FEED_HEAL < HP_MAX * 0.45);
}

const DEATH_DUR: f32 = 1.25;
const DISS_DUR: f32 = 0.95;
const SHOVE_DECAY: f32 = 7.5;
const DISSOLVE = foe.Dissolve{ .rate = 44.0, .spread = 0.55, .rise = 0.7, .flake = shroommod.WART };

const SPORE_RATE: f32 = 9.0;
const SPORE_RATE_FEED: f32 = 34.0;
const HIT_PUFF_LIGHT = 5;
const HIT_PUFF_HEAVY = 10;
const PARTS = 56;
comptime {
    std.debug.assert(@as(f32, PARTS) >= SPORE_RATE_FEED * 0.7 +
        @as(f32, @floatFromInt(foe.hitParts(HIT_PUFF_HEAVY) + foe.WOUND_PARTS)));
}

const State = enum { idle, prowl, bite, rush, feed, stunlight, stunheavy, dead };

const Choice = enum { rest, hold, close, bite, feed };

/// Pure over one situation. `food` is the distance to the nearest carrion, or null for a clean field —
/// **A GORGER WITH NOTHING TO EAT IS AN ORDINARY BEAST**, which is the whole design stated as a branch.
fn classify(gap: f32, sensed: f32, homeGap: f32, hpFrac: f32, food: ?f32, biteReady: bool, rooted: bool) Choice {
    if (food) |d| {
        if (hpFrac < HUNGER_FRAC and d <= SMELL_R and !rooted) return .feed;
    }
    if (sensed > AGGRO_R) return if (homeGap > HOME_R) .hold else .rest;
    if (gap <= BITE_R and biteReady) return .bite;
    if (rooted) return .rest;
    return .close;
}

pub const Model = struct {
    bone: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        return .{ .bone = buildBones(), .mat = gfx.material(shader, "rotgorger") };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, g: *const Gorger) void {
        for (0..N) |i| rl.drawMesh(self.bone[i], self.mat, g.xf[i]);
    }
};

fn restPose() [N]rl.Vector3 {
    return wolf.restPose(W);
}

pub const Gorger = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// **THE FIELD A UNIT OWES ITS ORDERS** (`foe.Post`), stamped at spawn off the map's `ai=` and `wp=`.
    post: foe.Post = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},

    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    biteCd: f32 = 0,
    speed: f32 = 0,
    speedS: f32 = 0,
    phase: f32 = 0,

    /// Which carrion it is on its way to, and where that is — the INDEX so the group can retire it, the POINT
    /// so a gorger whose meal is eaten out from under it still walks somewhere rather than to the origin.
    meal: ?usize = null,
    mealAt: rl.Vector3 = mathx.zero3,
    /// One-frame, read by the group after `update`: this gorger has just finished a carcass.
    ate: ?usize = null,
    fed: bool = false,

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

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Gorger {
        var g = Gorger{ .pos = home, .home = home, .facing = faceYaw, .scale = scale, .seed = seed };
        g.rest = restPose();
        g.fxRng = foe.fxStream(seed, 44819.0, 0x607E);
        g.aiRng = foe.fxStream(seed, 31337.0, 11);
        g.biteCd = seed * 0.6;
        g.pose();
        return g;
    }

    pub fn centerWorld(self: *const Gorger) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_Y * W, self.scale, 0);
    }
    pub fn lockPoint(self: *const Gorger) rl.Vector3 {
        return foe.markOn(self.xf[CHEST], v3(0, 0.10 * W, 0));
    }
    pub fn topWorld(self: *const Gorger) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_Y * W, self.scale, 0);
    }
    pub fn hurtRadius(self: *const Gorger) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Gorger) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Gorger) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Gorger) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Gorger) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn airborne(_: *const Gorger) bool {
        return false;
    }
    pub fn flashFrac(self: *const Gorger) f32 {
        return foe.flashFrac(self.flash);
    }
    pub fn kind(_: *const Gorger) wf.FoeKind {
        return .rotgorger;
    }
    /// **HEAD DOWN IS HEAD DOWN.** Feeding it does not track, does not turn and does not answer a blow with
    /// anything but the flinch — which is the whole reason letting it eat is a trade and not a punishment.
    pub fn feeding(self: *const Gorger) bool {
        return self.state == .feed and self.t >= FEED_WIND;
    }

    pub fn navWant(self: *const Gorger, quarry: rl.Vector3) ?rl.Vector3 {
        return switch (self.state) {
            .rush => self.mealAt,
            .idle, .prowl => blk: {
                if (foe.senseHero(&self.leash, self.pos, quarry, AGGRO_R) <= AGGRO_R) break :blk quarry;
                break :blk if (mathx.distXZ(self.pos, self.home) > HOME_R) self.home else null;
            },
            else => null,
        };
    }

    fn faceToward(self: *Gorger, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }

    fn biteAmt(self: *const Gorger) f32 {
        if (self.state != .bite) return 0;
        if (self.t < BITE_WIND) return -mathx.smoothstep(0, BITE_WIND * 0.9, self.t);
        const s = self.t - BITE_WIND;
        if (s < BITE_STRIKE) return lerpF(-1.0, 1.0, foe.swingCurve(s / BITE_STRIKE));
        return 1.0 - mathx.smoothstep(BITE_STRIKE, BITE_STRIKE + BITE_RECOVER * 0.7, s);
    }

    /// How far the head is buried, 0 up to 1 in the carcass.
    fn feedAmt(self: *const Gorger) f32 {
        if (self.state != .feed) return 0;
        if (self.t < FEED_WIND) return mathx.smoothstep(0, FEED_WIND, self.t);
        if (self.t < FEED_WIND + FEED_DUR) return 1;
        return 1.0 - mathx.smoothstep(FEED_WIND + FEED_DUR, FEED_WIND + FEED_DUR + FEED_RISE, self.t);
    }

    fn stunAmount(self: *const Gorger) f32 {
        if (self.state != .stunlight and self.state != .stunheavy) return 0;
        return foe.stunCurve(self.t, self.state == .stunheavy);
    }

    /// The nearest live carcass, as the group sees it. Handed IN rather than reached for — the creature reads
    /// the field, it never walks the group's table itself (`foe.zig`'s cross-cutting-state law).
    pub const Smelled = struct { at: rl.Vector3, i: usize, d: f32 };

    pub fn update(self: *Gorger, dt: f32, quarry: rl.Vector3, bounds: f32, blade: foe.Blade, smelled: ?Smelled) ?combat.Hit {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.heroHit = null;
        self.ate = null;
        self.fed = false;
        self.justDied = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.vit.tick(dt);
        self.elapsed += dt;
        self.t += dt;
        self.biteCd = mathx.maxF(0, self.biteCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, foe.tetherFor(self), quarry, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        var moved: f32 = 0;

        switch (self.state) {
            .dead => {
                self.speed = 0;
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
            .stunlight, .stunheavy => {
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                if (self.t >= combat.foeStunDur(self.state == .stunheavy)) self.enter(.idle);
            },
            .bite => {
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                if (self.t < BITE_WIND) self.faceToward(quarry, dt);
                const s = self.t - BITE_WIND;
                if (s >= 0 and s < BITE_STRIKE) self.tryBite(quarry);
                if (self.t >= BITE_WIND + BITE_STRIKE + BITE_RECOVER) {
                    self.heroLatch = false;
                    self.enter(.idle);
                }
            },
            .rush => {
                // **THE MEAL CAN BE TAKEN OUT FROM UNDER IT** — another gorger, or the clock. Back to the fight.
                if (self.meal == null) {
                    self.enter(.idle);
                } else if (mathx.distXZ(self.pos, self.mealAt) <= FEED_R * self.scale) {
                    self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                    self.enter(.feed);
                    sfx.world(.shroom_coo, self.pos);
                } else {
                    self.faceToward(self.nav.aim(self.pos, self.mealAt), dt);
                    self.speed = approach(self.speed, FEED_RUSH, ACCEL * dt);
                    moved = self.travel(dt, bounds);
                }
            },
            .feed => {
                self.speed = approach(self.speed, 0, ACCEL * 3.0 * dt);
                if (self.t >= FEED_WIND and (self.t - dt) < FEED_WIND) {
                    _ = self.vit.heal(FEED_HEAL);
                    self.fed = true;
                    self.ate = self.meal;
                    self.meal = null;
                    sfx.world(.shroom_puff, self.pos);
                }
                if (self.t >= FEED_WIND + FEED_DUR + FEED_RISE) self.enter(.idle);
            },
            .idle, .prowl => {
                const sensed = foe.senseHero(&self.leash, self.pos, quarry, AGGRO_R);
                const gap = mathx.maxF(0, sensed - foe.HERO_R - self.bodyR());
                const homeGap = mathx.distXZ(self.pos, self.home);
                const foodD: ?f32 = if (smelled) |s| s.d else null;
                switch (classify(gap, sensed, homeGap, self.vit.hpFrac(), foodD, self.biteCd <= 0, self.root.held())) {
                    .feed => {
                        const s = smelled.?;
                        self.meal = s.i;
                        self.mealAt = s.at;
                        self.enter(.rush);
                        self.leash.noteCombat();
                    },
                    .rest => {
                        if (sensed <= AGGRO_R) self.faceToward(quarry, dt);
                        // **ORDERS ARE WHAT IT DOES BETWEEN MEALS** (`foe.postWant`) — through its own
                        // `travel`, so the prowl gait and the drag it leaves are the ones it already has.
                        if (foe.postWant(self, dt, sensed, AGGRO_R)) |go| {
                            self.faceToward(self.nav.aim(self.pos, go), dt);
                            self.speed = approach(self.speed, WALK_SPEED, ACCEL * dt);
                            moved = self.travel(dt, bounds);
                            self.state = .prowl;
                        } else {
                            self.speed = approach(self.speed, 0, ACCEL * dt);
                            self.state = .idle;
                        }
                    },
                    .bite => {
                        self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                        self.biteCd = BITE_CD * self.aiRng.range(0.85, 1.25);
                        self.heroLatch = false;
                        self.enter(.bite);
                    },
                    .hold, .close => |ch| {
                        const to = if (ch == .hold) self.home else quarry;
                        const want = if (ch == .hold) WALK_SPEED else CHASE_SPEED;
                        self.faceToward(self.nav.aim(self.pos, to), dt);
                        self.speed = approach(self.speed, want, ACCEL * dt);
                        moved = self.travel(dt, bounds);
                        self.state = .prowl;
                    },
                }
            },
        }

        self.speedS = approach(self.speedS, self.speed, GAIT_BLEND * dt);
        if (moved > 0) self.phase = wolf.wrap01(self.phase + moved / (wolf.strideFor(self.speed) * self.scale));
        self.emitSpores(dt);
        self.pose();
        self.tryHit(blade);
        return self.heroHit;
    }

    fn travel(self: *Gorger, dt: f32, bounds: f32) f32 {
        const step = self.speed * dt * self.chill.travel();
        const way = self.nav.along(mathx.headingDir(self.facing));
        mathx.stepXZ(&self.pos, way, step, bounds);
        return step;
    }

    fn tryBite(self: *Gorger, quarry: rl.Vector3) void {
        if (self.heroLatch) return;
        if (!foe.inFront(self.pos, self.facing, quarry, foe.hurtReach(BITE_R, self.scale), BITE_FRONT_DOT)) return;
        self.heroHit = BITE_HIT;
        self.heroLatch = true;
        self.leash.noteCombat();
    }

    pub fn tryHit(self: *Gorger, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        const heavy = foe.wounded(self, s, blade, .{ .light = 0.7, .heavy = 1.5 });
        self.puff(s.contact, foe.hitParts(if (heavy) HIT_PUFF_HEAVY else HIT_PUFF_LIGHT));
        sfx.world(.shroom_hurt, self.pos);
        switch (s.reaction) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn enter(self: *Gorger, s: State) void {
        self.state = s;
        self.t = 0;
    }
    fn enterStun(self: *Gorger, s: State) void {
        self.heroLatch = false;
        // **A BLOW TAKES ITS HEAD OUT OF THE CARCASS**, and the meal is forfeit — interrupting the feed is the
        // whole reason the window exists, so a stagger that left `meal` set would hand it straight back.
        self.meal = null;
        self.enter(s);
    }
    fn enterDeath(self: *Gorger) void {
        if (self.state == .dead) return;
        self.heroLatch = false;
        self.meal = null;
        self.enter(.dead);
        self.justDied = true;
        sfx.world(.shroom_die, self.pos);
    }
    pub fn stagger(self: *Gorger, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugBite(self: *Gorger) void {
        self.heroLatch = false;
        self.enter(.bite);
    }
    pub fn debugKill(self: *Gorger) void {
        self.enterDeath();
    }

    fn emitSpores(self: *Gorger, dt: f32) void {
        if (self.state == .dead) return;
        const feed = self.feedAmt() > 0.5;
        var owed = foe.emitDue(&self.fxAccum, dt, if (feed) SPORE_RATE_FEED else SPORE_RATE);
        while (owed > 0) : (owed -= 1) {
            const from = if (feed)
                foe.markOn(self.xf[HEAD], v3(0, 0, 0.10 * W))
            else
                foe.markOn(self.xf[SPINE], v3(self.fxRng.signed() * 0.10 * W, 0.16 * W, 0));
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.15, 0.55);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = from,
                .v = v3(mathx.cosf(a) * sp, self.fxRng.range(0.15, 0.6), mathx.sinf(a) * sp),
                .life = self.fxRng.range(0.35, 0.7),
                .r0 = self.fxRng.range(0.03, 0.06),
                .r1 = self.fxRng.range(0.08, 0.13),
                .col = GILL,
                .col1 = foe.DUST_THIN,
                .grav = 0.4,
                .drag = 3.2,
            });
        }
    }

    const PUFF = foe.Puff{
        .blast = foe.Blast.of(foe.DUST_DRAG, 0.30, 0.55),
        .spdLo = 0.4,
        .upLo = 0.4,
        .upHi = 1.4,
        .rLo = 0.03,
        .rHi = 0.06,
        .col = GILL,
        .col1 = foe.DUST_THIN,
    };
    fn puff(self: *Gorger, at: rl.Vector3, n: i32) void {
        foe.puff(&self.parts, &self.fxHead, &self.fxRng, at, n, 2.0, 0.2, self.scale, PUFF);
    }

    pub fn drawFx(self: *const Gorger) void {
        foe.drawParticles(&self.parts);
    }
    pub fn draw(self: *const Gorger, model: *const Model) void {
        model.draw(self);
    }

    pub fn pose(self: *Gorger) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = foe.rigSink(SINK_DEPTH, self.scale, self.fade);
        const g = wolf.gaitAt(self.speedS);
        const stride = wolf.strideFor(self.speedS);
        const ph = wolf.limbPhases(self.phase, g);
        const m = mathx.clampF(self.speedS / wolf.WALK_SPEED, 0, 1);

        const react = self.stunAmount();
        const dk: f32 = if (self.state == .dead) mathx.clampF(self.t / (DEATH_DUR * 0.7), 0, 1) else 0;
        const bite = self.biteAmt();
        const feed = self.feedAmt();

        // **THE WHOLE FRONT END GOES DOWN TO EAT** — the shoulders sink and the hind stays up, which is the
        // silhouette that says "head in something" from across the field.
        const crouch = 0.30 * feed + 0.10 * react + 0.46 * dk;
        const pitch = 16.0 * mathx.maxF(0, bite) + 26.0 * feed - 8.0 * mathx.maxF(0, -bite);
        const breath = (mathx.sinf(self.elapsed * 1.5) * 0.007 + mathx.sinf(self.elapsed * 0.7 + self.seed * 4.0) * 0.005) * W;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            mul(scaleM(fs, fs, fs), mul(rx(-pitch), rz(46.0 * mathx.smoothstep(0, 1, dk)))),
            mul(tr(0, (self.rest[ROOT].y + breath - crouch * W) * fs + sink, 0), ry(mathx.degrees(self.facing))),
            heromod.rootAt(self.pos),
        );
        const flex = mathx.sinf(self.phase * std.math.tau) * m * 6.0;
        heromod.setJoint(&wx, &self.rest, SPINE, ROOT, rx(-flex * 0.5 - 6.0 * react + 10.0 * feed));
        heromod.setJoint(&wx, &self.rest, CHEST, SPINE, rx(-flex * 0.5 - 5.0 * react + 14.0 * feed - 10.0 * dk));

        const neckPitch = flex * 0.4 + 4.0 * m - 10.0 * react - 30.0 * mathx.maxF(0, -bite) + 20.0 * mathx.maxF(0, bite) + 52.0 * feed;
        heromod.setJoint(&wx, &self.rest, NECK, CHEST, rx(neckPitch));
        heromod.setJoint(&wx, &self.rest, HEAD, NECK, rx(flex * 0.2 - 4.0 * m + 18.0 * react + 12.0 * bite + 24.0 * feed - 26.0 * dk));
        // The jaw is the whole creature: it hangs slack at rest, gapes on the wind, and CHEWS through the feed.
        const chew = if (self.feeding()) 9.0 + 9.0 * mathx.sinf(self.elapsed * 11.0) else 0;
        heromod.setJoint(&wx, &self.rest, JAW, HEAD, rx(6.0 + 34.0 * mathx.maxF(0, -bite) + 8.0 * mathx.maxF(0, bite) + chew));

        const wag = mathx.sinf(self.elapsed * 3.4 + self.seed * 5.0) * (4.0 + 8.0 * m) * (1.0 - dk);
        heromod.setJoint(&wx, &self.rest, TAIL0, ROOT, mul(ry(wag), rx(-8.0 + 18.0 * dk)));
        heromod.setJoint(&wx, &self.rest, TAIL1, TAIL0, mul(ry(wag * 0.8), rx(6.0)));
        heromod.setJoint(&wx, &self.rest, TAIL2, TAIL1, mul(ry(wag * 0.6), rx(8.0)));
        heromod.setJoint(&wx, &self.rest, EARL, HEAD, rz(-14.0 - 10.0 * react));
        heromod.setJoint(&wx, &self.rest, EARR, HEAD, rz(14.0 + 10.0 * react));

        wolf.legs(&wx, &self.rest, W, ph, g, stride, m * (1.0 - dk), crouch, dk * 0.6);
        self.xf = wx;
    }
};

/// A body on the ground, as food and nothing else. Stamped by `game.billDeaths` — the ONE place a death is
/// billed — so nothing has to remember to call it twice.
pub const Carrion = struct {
    pos: rl.Vector3 = mathx.zero3,
    t: f32 = 0,
    live: bool = false,

    pub fn edible(self: *const Carrion) bool {
        return self.live and self.t < CARRION_LIFE;
    }
};

const CARRION_CAP: usize = 48;
const CAP_N = wf.MAX_PER_KIND;

pub const Gorge = struct {
    model: Model,
    gorgers: [CAP_N]Gorger = undefined,
    n: usize = 0,
    table: [CARRION_CAP]Carrion = [_]Carrion{.{}} ** CARRION_CAP,
    head: usize = 0,

    pub fn init(shader: rl.Shader) Gorge {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Gorge) []Gorger {
        return self.gorgers[0..self.n];
    }
    pub fn liveConst(self: *const Gorge) []const Gorger {
        return self.gorgers[0..self.n];
    }
    pub fn reset(self: *Gorge, m: *const wf.Map) void {
        self.clearTable();
        foe.resetGroup(Gorger, &self.gorgers, &self.n, m, .rotgorger);
    }
    pub fn clear(self: *Gorge) void {
        self.n = 0;
        self.clearTable();
    }
    fn clearTable(self: *Gorge) void {
        for (&self.table) |*c| c.* = .{};
        self.head = 0;
    }
    pub fn setShader(self: *Gorge, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn setParry(self: *Gorge, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }

    /// **EVERY BODY IS FOOD, ITS OWN INCLUDED.** Called once per death from `game.billDeaths`; a field with no
    /// gorger on it stamps these and nothing ever reads them, which costs one write and keeps the caller
    /// from having to know whether a gorger is present.
    pub fn noteCorpse(self: *Gorge, at: rl.Vector3) void {
        self.table[self.head] = .{ .pos = at, .live = true };
        self.head = (self.head + 1) % CARRION_CAP;
    }

    fn nearest(self: *const Gorge, from: rl.Vector3) ?Gorger.Smelled {
        var best: ?Gorger.Smelled = null;
        for (&self.table, 0..) |*c, i| {
            if (!c.edible()) continue;
            const d = mathx.distXZ(from, c.pos);
            if (best == null or d < best.?.d) best = .{ .at = c.pos, .i = i, .d = d };
        }
        return best;
    }

    /// **TWO GORGERS MAY NOT SHARE ONE CARCASS** — the second would heal off a body that is already gone, and
    /// the picture (two heads in one dead toad) is the arithmetic saying so out loud.
    ///
    /// **ONE PASS OVER THE BAND, NOT ONE PER MEMBER.** Asked per gorger this was O(n²) every frame — at the
    /// group's own cap that is a quarter of a million comparisons a frame to answer a question one array can
    /// hold. **AND IT IS KEPT LIVE THROUGH THE LOOP, NOT SNAPSHOT BEFORE IT**: a claim taken this frame has
    /// to be visible to the gorger updated after it, or two of them pick the same carcass on the same frame
    /// and the whole rule quietly stops applying.
    fn claims(self: *const Gorge) [CARRION_CAP]bool {
        var out = [_]bool{false} ** CARRION_CAP;
        for (self.liveConst()) |*g| {
            if (g.meal) |m| out[m] = true;
        }
        return out;
    }

    pub fn update(self: *Gorge, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        for (&self.table) |*c| {
            if (!c.live) continue;
            c.t += dt;
            if (c.t >= CARRION_LIFE) c.live = false;
        }
        var spoken = self.claims();
        var worst: ?foe.Blow = null;
        var i: usize = 0;
        while (i < self.n) : (i += 1) {
            const g = &self.gorgers[i];
            var smelled = self.nearest(g.pos);
            if (smelled) |s| {
                // Its OWN claim is not somebody else's — a gorger already walking at a carcass keeps it.
                const mine = if (g.meal) |m| m == s.i else false;
                if (spoken[s.i] and !mine) smelled = null;
            }
            // A meal another gorger finished first is gone from under it; `rush` reads the null and gives up.
            if (g.meal) |m| {
                if (!self.table[m].edible()) g.meal = null;
            }
            if (g.update(dt, g.threat.aim(hero), bounds, blade, smelled)) |h| foe.worseBlow(&worst, h, g.pos, &g.threat);
            if (g.meal) |m| spoken[m] = true;
            if (g.ate) |m| {
                self.table[m].live = false;
                spoken[m] = false;
            }
        }
        return worst;
    }

    pub fn carrionCount(self: *const Gorge) u32 {
        var n: u32 = 0;
        for (&self.table) |*c| {
            if (c.edible()) n += 1;
        }
        return n;
    }
    pub fn anyFed(self: *const Gorge) bool {
        for (self.liveConst()) |*g| {
            if (g.fed) return true;
        }
        return false;
    }

    pub fn draw(self: *const Gorge, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Gorge) void {
        for (self.liveConst()) |*g| g.drawFx();
    }
    pub fn pierce(self: *Gorge, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Gorge) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn anyParried(self: *const Gorge) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn soulsDropped(self: *const Gorge) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Gorge) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Gorge) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

/// The rest chain is the only length that matters: a limb mesh shorter than the distance to its own child
/// leaves the joint standing in air. Fractions of `W`, since every mesh here is authored in them.
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
    mesh[TAIL0] = tailMesh(0.16, 0.055);
    mesh[TAIL1] = tailMesh(0.14, 0.040);
    mesh[TAIL2] = tailMesh(0.12, 0.026);
    mesh[EARL] = earMesh(1.0);
    mesh[EARR] = earMesh(-1.0);
    inline for (.{ wolf.SHL, wolf.SHR }, .{ 1.0, -1.0 }) |b, s| mesh[b] = upperLegMesh(s, segLen(b), 0.052);
    inline for (.{ wolf.ELL, wolf.ELR }, .{ 1.0, -1.0 }) |b, s| mesh[b] = lowerLegMesh(s, segLen(b), 0.036);
    inline for (.{ wolf.CAL, wolf.CAR }, .{ 1.0, -1.0 }) |b, s| mesh[b] = lowerLegMesh(s, segLen(b), 0.030);
    inline for (.{ wolf.PAWL, wolf.PAWR }) |b| mesh[b] = pawMesh();
    inline for (.{ wolf.HIPL, wolf.HIPR }, .{ 1.0, -1.0 }) |b, s| mesh[b] = upperLegMesh(s, segLen(b), 0.060);
    inline for (.{ wolf.STL, wolf.STR }, .{ 1.0, -1.0 }) |b, s| mesh[b] = lowerLegMesh(s, segLen(b), 0.038);
    inline for (.{ wolf.HKL, wolf.HKR }, .{ 1.0, -1.0 }) |b, s| mesh[b] = lowerLegMesh(s, segLen(b), 0.030);
    inline for (.{ wolf.HPAWL, wolf.HPAWR }) |b| mesh[b] = pawMesh();
    return mesh;
}

fn hipMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, 0.010 * W, 0), v3(0.150 * W, 0.135 * W, 0.210 * W), 10, 7, HIDE);
    b.addBlob(v3(0, -0.070 * W, 0.010 * W), v3(0.130 * W, 0.080 * W, 0.180 * W), 8, 6, BELLY);
    return b.toMesh();
}

fn loinMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, 0.005 * W, 0.060 * W), v3(0.158 * W, 0.140 * W, 0.280 * W), 10, 7, HIDE);
    b.addBlob(v3(0, -0.080 * W, 0.060 * W), v3(0.140 * W, 0.076 * W, 0.240 * W), 8, 6, BELLY);
    return b.toMesh();
}

/// **THE FRUITING BODY.** Caps growing straight out of the withers, biggest at the shoulder and dwindling down
/// the loin — the one silhouette cue that says fungal from behind, where the mouth cannot be seen.
fn withersMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x60A9);
    b.setMat(.skin);
    b.addBlob(v3(0, 0.005 * W, -0.050 * W), v3(0.168 * W, 0.152 * W, 0.300 * W), 10, 7, HIDE);
    b.addBlob(v3(0, -0.085 * W, -0.030 * W), v3(0.148 * W, 0.082 * W, 0.250 * W), 8, 6, BELLY);
    b.addBlob(v3(0, 0.110 * W, -0.070 * W), v3(0.120 * W, 0.060 * W, 0.185 * W), 8, 6, HIDE_DK);
    var i: u32 = 0;
    while (i < 7) : (i += 1) {
        const f = @as(f32, @floatFromInt(i)) / 6.0;
        const side: f32 = if (i % 2 == 0) 1.0 else -1.0;
        const cx = side * rng.range(0.02, 0.09) * W;
        const cy = (0.115 - 0.020 * f) * W;
        const cz = (-0.110 + 0.180 * f) * W;
        const r = (0.070 - 0.032 * f) * W * rng.range(0.85, 1.15);
        b.addBlob(v3(cx, cy + r * 0.30, cz), v3(r, r * 0.42, r * 0.92), 7, 6, CAP_COL);
        b.addBlob(v3(cx, cy + r * 0.10, cz), v3(r * 0.86, r * 0.16, r * 0.80), 6, 5, CAP_DK);
        b.addCapsule(v3(cx, cy - r * 0.30, cz), v3(cx, cy + r * 0.16, cz), r * 0.26, r * 0.20, 5, GILL);
    }
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(0, -0.010 * W, 0.135 * W), 0.112 * W, 0.098 * W, 9, HIDE);
    b.addBlob(v3(0, -0.055 * W, 0.070 * W), v3(0.086 * W, 0.052 * W, 0.100 * W), 7, 5, BELLY);
    return b.toMesh();
}

/// **THE MOUTH IS MOST OF THE FRONT OF IT.** No muzzle to speak of: a wide flat skull with the gape running
/// back past where an eye ought to be, and the eyes pushed up and out to the sides where a grazer keeps them.
fn headMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, 0, 0.020 * W), v3(0.106 * W, 0.078 * W, 0.115 * W), 9, 7, HIDE);
    b.addBlob(v3(0, 0.020 * W, 0.100 * W), v3(0.092 * W, 0.052 * W, 0.070 * W), 8, 6, HIDE_LT);
    b.setMat(.plain);
    b.addBlob(v3(0, -0.014 * W, 0.108 * W), v3(0.082 * W, 0.030 * W, 0.052 * W), 7, 5, GUM);
    var i: i32 = 0;
    while (i < 6) : (i += 1) {
        const f = (@as(f32, @floatFromInt(i)) - 2.5) / 2.5;
        b.addCapsule(
            v3(f * 0.062 * W, -0.008 * W, (0.120 - @abs(f) * 0.022) * W),
            v3(f * 0.066 * W, -0.040 * W, (0.116 - @abs(f) * 0.022) * W),
            0.011 * W,
            0.004 * W,
            5,
            TOOTH,
        );
    }
    b.addBlob(v3(0.070 * W, 0.048 * W, 0.048 * W), v3(0.020 * W, 0.019 * W, 0.019 * W), 6, 5, EYE);
    b.addBlob(v3(-0.070 * W, 0.048 * W, 0.048 * W), v3(0.020 * W, 0.019 * W, 0.019 * W), 6, 5, EYE);
    return b.toMesh();
}

fn jawMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, -0.014 * W, 0.058 * W), v3(0.080 * W, 0.030 * W, 0.092 * W), 8, 6, HIDE_DK);
    b.setMat(.plain);
    b.addBlob(v3(0, 0.004 * W, 0.078 * W), v3(0.066 * W, 0.018 * W, 0.062 * W), 7, 5, GUM);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const f = (@as(f32, @floatFromInt(i)) - 2.0) / 2.0;
        b.addCapsule(
            v3(f * 0.054 * W, 0.010 * W, (0.104 - @abs(f) * 0.020) * W),
            v3(f * 0.058 * W, 0.040 * W, (0.100 - @abs(f) * 0.020) * W),
            0.010 * W,
            0.004 * W,
            5,
            TOOTH,
        );
    }
    return b.toMesh();
}

fn tailMesh(len: f32, r: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(0, -len * 0.35 * W, -len * W), r * W, r * 0.7 * W, 7, HIDE_DK);
    return b.toMesh();
}

fn earMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(side * 0.010 * W, 0.026 * W, -0.010 * W), v3(0.024 * W, 0.038 * W, 0.012 * W), 5, 5, HIDE_DK);
    return b.toMesh();
}

fn upperLegMesh(side: f32, len: f32, r: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(side * 0.004 * W, -len * W, 0), r * W, r * 0.78 * W, 8, HIDE);
    return b.toMesh();
}

fn lowerLegMesh(side: f32, len: f32, r: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(side * 0.002 * W, -len * W, 0), r * W, r * 0.72 * W, 7, HIDE_DK);
    return b.toMesh();
}

fn pawMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, 0.014 * W, 0.020 * W), v3(0.044 * W, 0.024 * W, 0.055 * W), 7, 5, HIDE_DK);
    return b.toMesh();
}


test "A CLEAN FIELD MAKES IT AN ORDINARY BEAST — nothing dead, nothing to break off for" {
    try std.testing.expectEqual(Choice.close, classify(6.0, 6.0, 0, 0.4, null, true, false));
    try std.testing.expectEqual(Choice.bite, classify(BITE_R - 0.2, 1.5, 0, 0.4, null, true, false));
    // …and one body on the ground changes the same situation into a meal.
    try std.testing.expectEqual(Choice.feed, classify(6.0, 6.0, 0, 0.4, 8.0, true, false));
    try std.testing.expectEqual(Choice.feed, classify(BITE_R - 0.2, 1.5, 0, 0.4, 8.0, true, false));
}

test "IT ONLY LEAVES A FIGHT FOR A MEAL IT NEEDS — full health, it stays on you" {
    try std.testing.expectEqual(Choice.close, classify(6.0, 6.0, 0, 1.0, 4.0, true, false));
    try std.testing.expectEqual(Choice.close, classify(6.0, 6.0, 0, HUNGER_FRAC + 0.01, 4.0, true, false));
    try std.testing.expectEqual(Choice.feed, classify(6.0, 6.0, 0, HUNGER_FRAC - 0.01, 4.0, true, false));
    // And not for one it cannot smell.
    try std.testing.expectEqual(Choice.close, classify(6.0, 6.0, 0, 0.3, SMELL_R + 1.0, true, false));
    // Rooted it cannot go and get it, whatever it can smell.
    try std.testing.expectEqual(Choice.rest, classify(6.0, 6.0, 0, 0.3, 4.0, true, true));
}

test "IT BREAKS OFF, EATS, AND COMES BACK UP HEALED — and the carcass is gone after" {
    var g = Gorge{ .model = undefined };
    g.gorgers[0] = Gorger.spawn(mathx.zero3, 0, 1.0, 0.3);
    g.n = 1;
    g.gorgers[0].vit.hp = HP_MAX * 0.4;
    const before = g.gorgers[0].vit.hp;
    g.noteCorpse(v3(0, 0, 6.0));
    try std.testing.expectEqual(@as(u32, 1), g.carrionCount());

    const hero = v3(0, 0, -3.0);
    var sawRush = false;
    var sawFeed = false;
    var t: f32 = 0;
    while (t < 14.0) : (t += 1.0 / 60.0) {
        _ = g.update(1.0 / 60.0, hero, 400, .{});
        if (g.gorgers[0].state == .rush) sawRush = true;
        if (g.gorgers[0].feeding()) sawFeed = true;
        if (g.gorgers[0].fed) break;
    }
    try std.testing.expect(sawRush);
    try std.testing.expect(sawFeed);
    const after = g.gorgers[0].vit.hp;
    std.debug.print("\n  rotgorger: {d:.0} hp -> {d:.0} off one carcass (+{d:.0})\n", .{ before, after, after - before });
    try std.testing.expectApproxEqAbs(before + FEED_HEAL, after, 1e-3);
    // Eaten is eaten: the table is empty and a second gorger finds nothing there.
    try std.testing.expectEqual(@as(u32, 0), g.carrionCount());
}

test "A BLOW TAKES ITS HEAD OUT OF THE CARCASS — the feed is interruptible and the meal is forfeit" {
    var g = Gorge{ .model = undefined };
    g.gorgers[0] = Gorger.spawn(mathx.zero3, 0, 1.0, 0.3);
    g.n = 1;
    g.gorgers[0].vit.hp = HP_MAX * 0.4;
    g.noteCorpse(v3(0, 0, 5.0));
    const hero = v3(0, 0, -3.0);
    var t: f32 = 0;
    while (t < 14.0) : (t += 1.0 / 60.0) {
        _ = g.update(1.0 / 60.0, hero, 400, .{});
        if (g.gorgers[0].state == .rush and g.gorgers[0].meal != null) break;
    }
    try std.testing.expect(g.gorgers[0].meal != null);
    g.gorgers[0].stagger(true);
    try std.testing.expect(g.gorgers[0].meal == null);
    try std.testing.expect(!g.gorgers[0].feeding());
    // The carcass is still on the table — it was interrupted, not consumed.
    try std.testing.expectEqual(@as(u32, 1), g.carrionCount());
}

test "TWO GORGERS MAY NOT SHARE ONE CARCASS" {
    var g = Gorge{ .model = undefined };
    g.gorgers[0] = Gorger.spawn(v3(-2, 0, 0), 0, 1.0, 0.3);
    g.gorgers[1] = Gorger.spawn(v3(2, 0, 0), 0, 1.0, 0.7);
    g.n = 2;
    for (g.live()) |*x| x.vit.hp = HP_MAX * 0.4;
    g.noteCorpse(v3(0, 0, 6.0));
    const hero = v3(0, 0, -6.0);
    var t: f32 = 0;
    var bothClaimed = false;
    while (t < 12.0) : (t += 1.0 / 60.0) {
        _ = g.update(1.0 / 60.0, hero, 400, .{});
        if (g.gorgers[0].meal != null and g.gorgers[1].meal != null) bothClaimed = true;
    }
    try std.testing.expect(!bothClaimed);
    // …and exactly one of them got fed by it.
    var fedN: u32 = 0;
    for (g.liveConst()) |*x| {
        if (x.vit.hp > HP_MAX * 0.4 + 1.0) fedN += 1;
    }
    try std.testing.expectEqual(@as(u32, 1), fedN);
}

test "A CARCASS GOES OFF — leave it long enough and there is nothing to come back for" {
    var g = Gorge{ .model = undefined };
    g.noteCorpse(mathx.zero3);
    try std.testing.expectEqual(@as(u32, 1), g.carrionCount());
    var t: f32 = 0;
    while (t < CARRION_LIFE + 0.2) : (t += 1.0 / 60.0) _ = g.update(1.0 / 60.0, v3(0, 0, 40), 400, .{});
    try std.testing.expectEqual(@as(u32, 0), g.carrionCount());
    std.debug.print("  carrion keeps {d:.0} s\n", .{CARRION_LIFE});
}

test "the feed is a WINDOW: head down it neither tracks nor answers" {
    var g = Gorge{ .model = undefined };
    g.gorgers[0] = Gorger.spawn(mathx.zero3, 0, 1.0, 0.3);
    g.n = 1;
    g.gorgers[0].vit.hp = HP_MAX * 0.4;
    g.noteCorpse(v3(0, 0, 4.0));
    // The hero stands in its face the whole time; it must still never swing while it is eating.
    const hero = v3(0, 0, 1.0);
    var swungWhileFeeding = false;
    var fedFrames: u32 = 0;
    var t: f32 = 0;
    while (t < 12.0) : (t += 1.0 / 60.0) {
        const blow = g.update(1.0 / 60.0, hero, 400, .{});
        if (g.gorgers[0].feeding()) {
            fedFrames += 1;
            if (blow != null) swungWhileFeeding = true;
        }
    }
    try std.testing.expect(fedFrames > 0);
    try std.testing.expect(!swungWhileFeeding);
    std.debug.print("  the feed is {d:.2} s of open window ({d} frames measured)\n", .{ FEED_DUR, fedFrames });
}

test "IT IS RENDERED BY FIRE AND SHRUGS OFF ROT" {
    const fire = combat.Hit{ .elem = combat.elems(.{ .fire = 40 }) };
    const rot = combat.Hit{ .elem = combat.elems(.{ .chaos = 40 }) };
    var burnt = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    var rotted = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    _ = burnt.hit(fire);
    _ = rotted.hit(rot);
    try std.testing.expect(HP_MAX - burnt.hp > (HP_MAX - rotted.hp) * 3.0);
}

test "the bite is telegraphed and it only lands once per snap" {
    var g = Gorger.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, 1.1);
    g.facing = mathx.headingXZ(mathx.dirXZ(g.pos, hero));
    g.debugBite();
    var landed: u32 = 0;
    var firstAt: f32 = 0;
    var t: f32 = 0;
    while (t < BITE_WIND + BITE_STRIKE + BITE_RECOVER + 0.1) : (t += 1.0 / 60.0) {
        if (g.update(1.0 / 60.0, hero, 400, .{}, null) != null) {
            if (landed == 0) firstAt = t;
            landed += 1;
        }
    }
    try std.testing.expectEqual(@as(u32, 1), landed);
    try std.testing.expect(firstAt >= foe.TELL_MIN);
}
