const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const anim = @import("../core/anim.zig");
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

const CHITIN = rgba(21, 20, 26, 255);
const CHITIN_LT = rgba(38, 36, 46, 255);
const CHITIN_DK = rgba(9, 9, 12, 255);
const SAC = rgba(46, 24, 22, 255);
const SAC_FULL = rgba(122, 26, 26, 255);
const SAC_DK = rgba(20, 11, 10, 255);
const BEAK = rgba(30, 24, 20, 255);
const BEAK_TIP = rgba(58, 46, 38, 255);
const LEG = rgba(16, 15, 20, 255);
/// THE WING. Nearly black and NORMALLY LIT (alpha 255): the emissive channel runs the other way — a low alpha is SELF-lit, and at 74 the membrane ignored the sun and came back a pale feather.
const WING = rgba(27, 29, 39, 255);
const WING_RIB = rgba(72, 74, 92, 255);
const EYE = rgba(38, 9, 10, 255);
const EYE_LIT = rgba(255, 52, 40, 255);
const BLOOD = rgba(126, 20, 18, 235);
const BLOOD_DRY = rgba(56, 9, 8, 225);
const CHIP = rgba(74, 70, 86, 235);

/// ITS OWN STATURE — nose to tail, and NOT the shared humanoid scaffold: it has no legs to walk on. 1.3 m of body with a wingspan half again as wide.
pub const H: f32 = 1.3;

const HOVER_LOW: f32 = 1.18;
const HOVER_IDLE: f32 = 1.75;
const HOVER_HIGH: f32 = 4.6;
const CLIMB_RATE: f32 = 8.5;
const DIVE_RATE: f32 = 7.0;
const SETTLE_RATE: f32 = 3.2;

pub var AGGRO_R: f32 = 15.0;
const BODY_R: f32 = 0.30;
const HURT_R: f32 = 0.40;
const CENTER_F: f32 = 0.10;
const TOP_F: f32 = 0.34;
const LOCK_AT = v3(0, 0.03 * H, 0.10 * H);

const STALK_SPEED: f32 = 4.7;
const CIRCLE_SPEED: f32 = 4.1;
const TURN_RATE: f32 = 9.5;

const HP_MAX: f32 = 30.0;
const POISE_MAX: f32 = 7.0;
const STANCE_MAX: f32 = 20.0;
const RESISTS = combat.resists(.{ .fire = -55, .cold = -25, .chaos = 35 });
pub var SOULS: u32 = 95;

const DEATH_DUR: f32 = 0.85;
const DISS_DUR: f32 = 0.8;
const DISSOLVE = foe.Dissolve{ .rate = 30.0, .spread = 0.45, .rise = 0.30, .flake = CHIP };
const SHOVE_DECAY: f32 = 8.0;

pub var STAB_HIT = combat.Hit{ .dmg = 6, .poise = 9 };
pub const DRINK_DPS: f32 = 10.0;
const LEECH_SHARE: f32 = 0.55;
const DRINK_DUR: f32 = 1.45;
const DRINK_EVERY: f32 = 0.80;
const FEED_CD: f32 = 3.4;
const STAB_R: f32 = 0.90;
const FEED_ARC: f32 = 62.0;
const FEED_CEIL: f32 = HOVER_LOW + 0.8;

const WIND_DUR: f32 = 0.34; // the rear-back. Clears `foe.TELL_MIN` (0.30) — no attack comes out of nowhere
const STAB_DUR: f32 = 0.16;
const STAB_IMPACT_K: f32 = 0.45;
const RECOVER_DUR: f32 = 0.45;

const THREAT_R: f32 = 2.0;
const CLIMB_CD: f32 = 3.8;
const PERCH_DUR: f32 = 1.5;
const SPOOK_DUR: f32 = 5.0;

const WING_HZ_FLY: f32 = 26.0;
const WING_HZ_HOVER: f32 = 20.0;
const WING_SWEEP: f32 = 62.0; // degrees either side of level
const BANK_MAX: f32 = 26.0;
const PITCH_MAX: f32 = 22.0;
const BOB_AMP: f32 = 0.035 * H;
const BOB_HZ: f32 = 3.1;
/// raylib cannot loop a synthesized take, so a note is a short voice retriggered; a phrase is a run of overlapping takes, and hushes outlast phrases.
const WHINE_EVERY: f32 = 0.26; // the retrigger INSIDE a phrase, under the take's own 0.32 so they overlap
const PHRASE_MIN: f32 = 0.30;
const PHRASE_MAX: f32 = 0.95;
const HUSH_MIN: f32 = 1.30;
const HUSH_MAX: f32 = 4.20;

const PARTS = 40;

const N = 15;
const ROOT = 0;
const ABDO = 1;
const ABDO2 = 2;
const HEAD = 3;
const PROB = 4;
const EYEL = 5;
const EYER = 6;
const WINGL = 7;
const WINGR = 8;
const LEG_0 = 9;
const LEG_N = 6;

const SH_HALF: f32 = 0.085 * H;
const EYE_HALF: f32 = 0.062 * H;

const REST = blk: {
    var r = [_]rl.Vector3{mathx.zero3} ** N;
    r[ROOT] = v3(0, 0, 0);
    r[ABDO] = v3(0, -0.020 * H, -0.145 * H);
    r[ABDO2] = v3(0, -0.010 * H, -0.335 * H);
    r[HEAD] = v3(0, 0.010 * H, 0.150 * H);
    r[PROB] = v3(0, -0.045 * H, 0.075 * H);
    r[EYEL] = v3(EYE_HALF, 0.030 * H, 0.048 * H);
    r[EYER] = v3(-EYE_HALF, 0.030 * H, 0.048 * H);
    r[WINGL] = v3(SH_HALF, 0.070 * H, -0.020 * H);
    r[WINGR] = v3(-SH_HALF, 0.070 * H, -0.020 * H);
    for (0..LEG_N) |i| {
        const pair = i / 2;
        const side: f32 = if (i % 2 == 0) 1 else -1;
        const fz = 0.075 - 0.075 * @as(f32, @floatFromInt(pair));
        r[LEG_0 + i] = v3(side * 0.055 * H, -0.048 * H, fz * H);
    }
    break :blk r;
};

fn legPair(i: usize) usize {
    return i / 2;
}
fn legSide(i: usize) f32 {
    return if (i % 2 == 0) 1 else -1;
}

pub fn feedClock() struct { wind: f32, stab: f32, drink: f32 } {
    return .{ .wind = WIND_DUR, .stab = STAB_DUR, .drink = DRINK_DUR };
}

const Posture = struct {
    pitch: f32 = 0,
    bank: f32 = 0,
    recoil: f32 = 0,
    lunge: f32 = 0,
    wing: f32 = 1,
    pub fn chan(p: Posture) [5]f32 {
        return .{ p.pitch, p.bank, p.recoil, p.lunge, p.wing };
    }
};
const Pose = anim.Pose(Posture);
const LOAD = Posture{ .pitch = -14, .lunge = -0.45 };
const STRUCK = Posture{ .pitch = 16, .lunge = 1 };
const WIND_KEYS = [_]Pose.PoseKey{
    .{ .t = 0, .p = .{} },
    .{ .t = 0.66, .p = LOAD, .ease = .decel },
    .{ .t = 1, .p = LOAD, .ease = .hold },
};
const STAB_KEYS = [_]Pose.PoseKey{
    .{ .t = 0, .p = LOAD },
    .{ .t = 0.50, .p = .{ .pitch = 19, .lunge = 1.15 }, .ease = .accel },
    .{ .t = 1, .p = STRUCK, .ease = .decel },
};
const RECOVER_KEYS = [_]Pose.PoseKey{
    .{ .t = 0, .p = STRUCK },
    .{ .t = 0.22, .p = .{ .pitch = 18, .lunge = 1.02 }, .ease = .decel },
    .{ .t = 0.73, .p = .{ .pitch = -5, .lunge = -0.14 } },
    .{ .t = 1, .p = .{}, .ease = .decel },
};
const State = enum { idle, stalk, circle, wind, stab, drink, recover, climb, perch, dive, stunlight, stunheavy, dead };

const Choice = enum { hold, close, circle, feed };
fn feedReach(scale: f32) f32 {
    return (STAB_R - foe.HERO_R) * scale + foe.HERO_R;
}
fn classify(dist: f32, scale: f32, feedReady: bool) Choice {
    if (dist > AGGRO_R) return .hold;
    const stab = feedReach(scale);
    if (dist <= stab) return if (feedReady) .feed else .circle;
    if (dist > stab + 1.4) return .close;
    return .circle;
}

fn wantsClimb(dist: f32, cd: f32, spooked: bool, s: State, rooted: bool) bool {
    if (cd > 0 or rooted) return false;
    if (!spooked and dist > THREAT_R) return false;
    return switch (s) {
        .idle, .stalk, .circle, .recover => true,
        .wind, .stab, .drink, .climb, .perch, .dive, .stunlight, .stunheavy, .dead => false,
    };
}

pub const Act = union(enum) {
    none,
    stab: combat.Hit,
    drink: combat.Hit,
};

pub const Model = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "leechfly");
        return .{ .mesh = buildMeshes(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, f: *const Leechfly) void {
        for (0..N) |i| rl.drawMesh(self.mesh[i], self.mat, f.xf[i]);
    }
};

pub const Leechfly = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    post: foe.Post = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    dealt: bool = false,
    parry: foe.Parry = .{},
    parried: bool = false,
    feedCd: f32 = 0,
    climbCd: f32 = 0,
    spookLeft: f32 = 0,
    driftDir: rl.Vector3 = mathx.zero3,
    orbitSign: f32 = 1,
    whineT: f32 = 0,
    phraseLeft: f32 = 0,

    /// HOW HIGH IT IS FLYING, in metres off the ground under it. The one field that makes this creature what it is: every world point it has is measured off `pos.y + hover`.
    hover: f32 = HOVER_IDLE,
    hoverTo: f32 = HOVER_IDLE,

    springs: anim.SpringBank(5) = .{},
    recoil: f32 = 0,
    wing: f32 = 1,
    wingPhase: f32 = 0,
    bank: f32 = 0,
    pitch: f32 = 0,
    lunge: f32 = 0,
    gorge: f32 = 0,
    glow: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    threat: foe.Threat = .{},
    fade: f32 = 0,
    gone: bool = false,

    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),
    wade: foe.Wade = .{},

    xf: [N]rl.Matrix = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Leechfly {
        var f = Leechfly{ .pos = home, .home = home, .facing = faceYaw, .scale = scale, .seed = seed };
        f.fxRng = foe.fxStream(seed, 61441.0, 0xB10D);
        f.orbitSign = if (seed < 0.5) 1 else -1;
        f.wingPhase = seed;
        f.whineT = seed * (HUSH_MIN + HUSH_MAX) * 0.5;
        f.phraseLeft = seed * PHRASE_MAX;
        f.feedCd = seed * FEED_CD;
        f.springs.seat((Posture{}).chan());
        f.pose();
        return f;
    }

    // EVERY WORLD POINT IS MEASURED OFF `pos.y` PLUS THE HOVER — `pos.y` is the ground under it and `hover` is how far it is flying above that, so one over a bank keeps its bar over its own head.
    fn lift(self: *const Leechfly) f32 {
        return self.hover * self.scale;
    }
    pub fn centerWorld(self: *const Leechfly) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H, self.scale, self.lift());
    }
    pub fn lockPoint(self: *const Leechfly) rl.Vector3 {
        return foe.markOn(self.xf[HEAD], LOCK_AT);
    }
    pub fn topWorld(self: *const Leechfly) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * H, self.scale, self.lift());
    }
    pub fn hurtRadius(self: *const Leechfly) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Leechfly) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Leechfly) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Leechfly) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Leechfly) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn airborne(self: *const Leechfly) bool {
        return !self.gone;
    }
    pub fn flashFrac(self: *const Leechfly) f32 {
        return foe.flashFrac(self.flash);
    }
    /// Where the beak's point is this frame — what the feed is measured from and where its blood flies off.
    pub fn beakWorld(self: *const Leechfly) rl.Vector3 {
        return foe.markOn(self.xf[PROB], v3(0, 0, PROB_LEN * H));
    }

    pub fn update(self: *Leechfly, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) Act {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return .none;
        }
        self.justDied = false;
        self.parried = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        foe.fadeFlash(&self.flash, dt);
        self.feedCd = mathx.maxF(0, self.feedCd - dt);
        self.climbCd = mathx.maxF(0, self.climbCd - dt);
        self.spookLeft = mathx.maxF(0, self.spookLeft - dt);
        foe.tickLeash(&self.leash, dt, self.pos, foe.tetherFor(self), hero, AGGRO_R);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);
        foe.tickParticles(&self.parts, dt, self.pos.y);

        var act: Act = .none;
        var stabbing = false;
        var drinking = false;
        const beakWas = self.beakSeg();
        self.bank = 0;
        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);

        switch (self.state) {
            .idle => {
                self.hoverTo = HOVER_IDLE;
                self.easeRest(dt);
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                if (foe.postWant(self, dt, d, AGGRO_R)) |go| {
                    const dir = mathx.dirXZ(self.pos, go);
                    if (mathx.lenXZ(dir) > 1e-3) {
                        const way = mathx.normV(dir);
                        self.flyXZ(way, STALK_SPEED, dt, bounds);
                        self.facing = mathx.approachAngle(self.facing, mathx.headingXZ(way), TURN_RATE * dt);
                    }
                }
                self.decide(d, hero);
            },
            .stalk => {
                self.hoverTo = HOVER_LOW;
                self.easeRest(dt);
                self.faceToward(hero, dt);
                self.flyXZ(self.driftDir, STALK_SPEED, dt, bounds);
                self.decide(d, hero);
            },
            .circle => {
                self.hoverTo = HOVER_LOW;
                self.easeRest(dt);
                self.faceToward(hero, dt);
                self.flyXZ(self.driftDir, CIRCLE_SPEED, dt, bounds);
                if (self.t >= 0.85) self.decide(d, hero) else self.aimOrbit(hero);
            },
            .wind => {
                self.hoverTo = HOVER_LOW + 0.30;
                self.faceToward(hero, dt);
                if (self.t >= WIND_DUR) self.enter(.stab);
            },
            .stab => {
                self.hoverTo = HOVER_LOW;
                const u = mathx.clampF(self.t / STAB_DUR, 0, 1);
                stabbing = !self.dealt and u >= STAB_IMPACT_K;
            },
            .drink => {
                self.hoverTo = HOVER_LOW;
                self.lunge = 0.86;
                self.pitch = 20.0;
                self.glow = mathx.approach(self.glow, 1.0, dt * 5.0);
                if (!self.holds(hero) or self.t >= DRINK_DUR) {
                    self.enter(.recover);
                } else {
                    self.faceToward(hero, dt);
                    self.clingTo(hero, dt, bounds);
                    drinking = true;
                }
            },
            .recover => {
                self.hoverTo = HOVER_LOW;
                self.easeRest(dt);
                self.faceToward(hero, dt);
                if (self.t >= RECOVER_DUR) self.decide(d, hero);
            },
            .climb => {
                self.hoverTo = HOVER_HIGH;
                self.easeRest(dt);
                self.faceToward(hero, dt);
                self.pitch = -30.0;
                if (self.hover >= HOVER_HIGH - 0.15) self.enter(.perch);
            },
            .perch => {
                self.hoverTo = HOVER_HIGH;
                self.easeRest(dt);
                self.faceToward(hero, dt);
                self.aimOrbit(hero);
                self.flyXZ(self.driftDir, CIRCLE_SPEED * 0.8, dt, bounds);
                if (self.t >= PERCH_DUR) self.enter(.dive);
            },
            .dive => {
                self.hoverTo = HOVER_LOW;
                self.faceToward(hero, dt);
                self.pitch = PITCH_MAX;
                self.driftDir = mathx.dirXZ(self.pos, hero);
                self.flyXZ(self.driftDir, STALK_SPEED, dt, bounds);
                if (self.hover <= HOVER_LOW + 0.20) self.decide(d, hero);
            },
            .stunlight => {
                self.hoverTo = HOVER_LOW * 0.55;
                self.easeRest(dt);
                if (self.t >= combat.FOE_LIGHT_STUN_DUR) self.enter(.idle);
            },
            .stunheavy => {
                self.hoverTo = HOVER_LOW * 0.35;
                self.easeRest(dt);
                if (self.t >= combat.FOE_HEAVY_STUN_DUR) self.enter(.idle);
            },
            .dead => {
                self.hoverTo = 0;
                self.lunge = -0.2;
                self.pitch = 62.0;
                self.bank = 74.0;
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
        }

        if (!stabbing and !drinking and wantsClimb(d, self.climbCd, self.spookLeft > 0, self.state, !foe.canLeap(&self.root))) self.enterClimb();

        self.flyTo(dt);
        self.beatWings(dt);
        self.poseStep(dt);
        self.pose();
        const stopped = self.takeParry();
        self.tryHit(blade);
        if (stopped or self.staggered()) return .none;
        if (stabbing and self.inFeedArc(hero) and self.beakTouches(beakWas, hero)) {
            self.dealt = true;
            self.leash.noteCombat();
            sfx.world(.leech_stab, self.beakWorld());
            act = .{ .stab = STAB_HIT };
        } else if (drinking) {
            if (self.holds(hero)) {
                if (@floor(self.t / DRINK_EVERY) != @floor((self.t - dt) / DRINK_EVERY)) sfx.world(.leech_drink, self.beakWorld());
                act = .{ .drink = self.sip(dt) };
            } else self.enter(.recover);
        }
        if (self.state == .stab and self.t >= STAB_DUR) self.enter(if (self.dealt) .drink else .recover);
        return act;
    }

    fn toImpact(self: *const Leechfly) ?f32 {
        const at = STAB_DUR * STAB_IMPACT_K;
        return switch (self.state) {
            .wind => (WIND_DUR - self.t) + at,
            .stab => at - self.t,
            .idle, .stalk, .circle, .drink, .recover, .climb, .perch, .dive, .stunlight, .stunheavy, .dead => null,
        };
    }

    fn parryable(self: *const Leechfly) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        return self.stabReach();
    }

    fn takeParry(self: *Leechfly) bool {
        const reach = self.parryable() orelse return false;
        if (!foe.caught(self, reach)) return false;
        self.dealt = false;
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light, .none => self.enterStun(.stunlight),
        }
        return true;
    }

    fn sip(self: *Leechfly, dt: f32) combat.Hit {
        const h = combat.Hit{ .dmg = DRINK_DPS * dt };
        _ = self.vit.heal(h.dmg * LEECH_SHARE);
        self.gorge = mathx.minF(1.0, self.gorge + dt / DRINK_DUR);
        self.bloodMotes();
        return h;
    }

    pub fn stabReach(self: *const Leechfly) f32 {
        return feedReach(self.scale);
    }

    fn inFeedArc(self: *const Leechfly, hero: rl.Vector3) bool {
        if (self.hover > FEED_CEIL) return false;
        if (mathx.distXZ(self.pos, hero) > self.stabReach()) return false;
        const to = mathx.dirXZ(self.pos, hero);
        if (mathx.lenXZ(to) < 1e-4) return true;
        return combat.withinArc(mathx.headingXZ(to), self.facing, FEED_ARC);
    }

    fn beakSeg(self: *const Leechfly) [2]rl.Vector3 {
        return .{ foe.markOn(self.xf[PROB], mathx.zero3), self.beakWorld() };
    }
    fn beakTouches(self: *const Leechfly, was: [2]rl.Vector3, hero: rl.Vector3) bool {
        return foe.sweptWeaponReaches(was, self.beakSeg(), hero, foe.HERO_R + 0.0125 * H * self.scale);
    }    pub fn holds(self: *const Leechfly, hero: rl.Vector3) bool {
        return self.inFeedArc(hero) and self.beakTouches(self.beakSeg(), hero);
    }

    fn poseStep(self: *Leechfly, dt: f32) void {
        var target = switch (self.state) {
            .wind => Pose.sample(&WIND_KEYS, self.t / WIND_DUR),
            .stab => Pose.sample(&STAB_KEYS, self.t / STAB_DUR),
            .recover => Pose.sample(&RECOVER_KEYS, self.t / RECOVER_DUR),
            .stunlight, .stunheavy => blk: {
                const heavy = self.state == .stunheavy;
                const u = self.t / combat.foeStunDur(heavy);
                const recoil = anim.keyAt(&.{
                    .{ .t = 0, .v = 0 },                 .{ .t = 0.12, .v = 1, .ease = .decel },
                    .{ .t = 0.60, .v = 0.85 },           .{ .t = 0.85, .v = -0.16 },
                    .{ .t = 1, .v = 0, .ease = .decel },
                }, u) * (if (heavy) @as(f32, 1) else 0.65);
                break :blk (Posture{ .pitch = -20 * recoil, .bank = 36 * recoil * self.orbitSign, .recoil = recoil, .lunge = -0.25 * recoil, .wing = 1 - 0.60 * recoil }).chan();
            },
            else => (Posture{ .pitch = self.pitch, .bank = self.bank, .lunge = self.lunge, .wing = if (self.state == .dead) 0.15 else 1 }).chan(),
        };
        self.springs.chase(&target, 3500, 0.68, 0.94, dt);
        self.pitch = target[0];
        self.bank = target[1];
        self.recoil = target[2];
        self.lunge = target[3];
        self.wing = target[4];
    }
    fn flyTo(self: *Leechfly, dt: f32) void {
        const gap = self.hoverTo - self.hover;
        const rate = if (gap > 0) CLIMB_RATE else DIVE_RATE;
        const ease = mathx.clampF(@abs(gap) / 0.6, 0.18, 1.0);
        self.hover = mathx.approach(self.hover, self.hoverTo, rate * ease * dt + SETTLE_RATE * 0.02 * dt);
    }

    fn flyXZ(self: *Leechfly, dir: rl.Vector3, speed: f32, dt: f32, bounds: f32) void {
        mathx.stepXZ(&self.pos, dir, speed * dt, bounds);
        const off = mathx.wrapPi(mathx.headingXZ(dir) - self.facing);
        self.bank = mathx.clampF(mathx.degrees(off) * 0.5, -BANK_MAX, BANK_MAX);
    }

    fn clingTo(self: *Leechfly, hero: rl.Vector3, dt: f32, bounds: f32) void {
        const want = self.stabReach() * 0.42;
        const gap = mathx.distXZ(self.pos, hero) - want;
        if (gap <= 0) return;
        mathx.stepXZ(&self.pos, mathx.dirXZ(self.pos, hero), mathx.minF(gap, STALK_SPEED * dt), bounds);
    }

    fn beatWings(self: *Leechfly, dt: f32) void {
        if (self.state == .dead) {
            self.wingPhase += dt * 2.0;
            return;
        }
        const moving = self.state == .stalk or self.state == .dive or self.state == .climb;
        self.wingPhase += dt * (if (moving) WING_HZ_FLY else WING_HZ_HOVER);
        self.whineT -= dt;
        if (self.whineT > 0) return;
        if (self.phraseLeft > 0) {
            self.phraseLeft -= WHINE_EVERY;
            self.whineT = WHINE_EVERY;
            sfx.world(.leech_wing, self.centerWorld());
            return;
        }
        self.whineT = self.fxRng.range(HUSH_MIN, HUSH_MAX);
        self.phraseLeft = self.fxRng.range(PHRASE_MIN, PHRASE_MAX);
    }

    fn faceToward(self: *Leechfly, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }

    fn easeRest(self: *Leechfly, dt: f32) void {
        self.lunge = 0;
        self.pitch = 0;
        self.glow = mathx.approach(self.glow, 0, dt * 2.2);
    }

    fn enter(self: *Leechfly, s: State) void {
        self.state = s;
        self.t = 0;
        self.dealt = false;
    }

    fn enterClimb(self: *Leechfly) void {
        self.climbCd = CLIMB_CD;
        self.spookLeft = 0;
        sfx.world(.leech_wing, self.centerWorld());
        self.enter(.climb);
    }

    fn decide(self: *Leechfly, dist: f32, hero: rl.Vector3) void {
        if (self.leash.goingHome()) {
            self.driftDir = mathx.dirXZ(self.pos, foe.tetherFor(self));
            return self.enter(.stalk);
        }
        switch (classify(dist, self.scale, self.feedCd <= 0)) {
            .hold => self.enter(.idle),
            .close => {
                self.driftDir = mathx.dirXZ(self.pos, hero);
                self.enter(.stalk);
            },
            .circle => {
                self.aimOrbit(hero);
                self.enter(.circle);
            },
            .feed => {
                self.feedCd = FEED_CD;
                self.enter(.wind);
            },
        }
    }

    fn aimOrbit(self: *Leechfly, hero: rl.Vector3) void {
        const to = mathx.dirXZ(hero, self.pos);
        self.driftDir = mathx.normV(v3(-to.z * self.orbitSign, 0, to.x * self.orbitSign));
    }

    fn enterStun(self: *Leechfly, s: State) void {
        self.enter(s);
        self.vit.beginStun(if (s == .stunheavy) .heavy else .light);
    }

    fn enterDeath(self: *Leechfly) void {
        self.state = .dead;
        self.t = 0;
        self.justDied = true;
    }

    pub fn debugKill(self: *Leechfly) void {
        self.enterDeath();
    }

    pub fn stagger(self: *Leechfly, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }

    pub fn debugFeedFrom(self: *Leechfly, runFor: f32) void {
        self.hover = HOVER_LOW;
        self.hoverTo = HOVER_LOW;
        self.feedCd = FEED_CD;
        self.climbCd = CLIMB_CD;
        if (runFor >= WIND_DUR + STAB_DUR) {
            self.enter(.drink);
            self.glow = 0.75;
            self.gorge = 0.45;
        } else {
            self.enter(.wind);
        }
    }

    pub fn debugClimb(self: *Leechfly) void {
        self.climbCd = CLIMB_CD;
        self.enter(.climb);
    }

    pub fn tryHit(self: *Leechfly, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        self.spookLeft = SPOOK_DUR;
        const heavy = foe.wounded(self, s, blade, .{ .light = 1.6, .heavy = 2.6 });
        self.splatter(s.contact, s.dir, if (heavy) 14 else 8);
        sfx.world(.leech_hurt, self.centerWorld());
        switch (s.reaction) {
            .death => {
                sfx.world(.leech_die, self.centerWorld());
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn splatter(self: *Leechfly, at: rl.Vector3, dir: rl.Vector3, n: i32) void {
        const parts = foe.hitParts(n);
        var i: i32 = 0;
        while (i < parts) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.5, 1.0) * 4.6;
            const wet = self.fxRng.float() < 0.35 + 0.5 * self.gorge;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(at.x + self.fxRng.signed() * 0.06, at.y + self.fxRng.signed() * 0.06, at.z + self.fxRng.signed() * 0.06),
                .v = v3(dir.x * sp + mathx.cosf(a) * sp * 0.85, self.fxRng.range(0.7, 3.0), dir.z * sp + mathx.sinf(a) * sp * 0.85),
                .life = self.fxRng.range(0.42, 0.78),
                .r0 = self.fxRng.range(0.02, 0.045) * self.scale,
                .r1 = 0.006,
                .col = if (wet) BLOOD else CHIP,
                .col1 = if (wet) BLOOD_DRY else null,
                .grav = if (wet) foe.BLOOD_GRAV else 11.0,
                .stretch = if (wet) foe.BLOOD_STRETCH else 0.030,
                .bounce = if (wet) 0 else 0.42,
                .splat = if (wet and foe.onDryGround(self)) 3.0 else 0,
                .drag = if (wet) foe.BLOOD_DRAG else 2.2,
            });
        }
    }

    fn bloodMotes(self: *Leechfly) void {
        if (self.fxRng.float() > 0.55) return;
        const tip = self.beakWorld();
        const to = self.centerWorld();
        const life = self.fxRng.range(0.14, 0.22);
        const d = mathx.subV(to, tip);
        foe.emitPart(&self.parts, &self.fxHead, .{
            .p = v3(tip.x + self.fxRng.signed() * 0.05, tip.y + self.fxRng.signed() * 0.05, tip.z + self.fxRng.signed() * 0.05),
            .v = mathx.scaleV(d, 1.0 / life),
            .life = life,
            .r0 = self.fxRng.range(0.018, 0.032) * self.scale,
            .r1 = 0.005,
            .col = BLOOD,
            .grav = -0.4,
            .stretch = 0.030,
        });
    }

    pub fn drawFx(self: *const Leechfly) void {
        foe.drawParticles(&self.parts);
        if (self.glow <= 0.02 or self.gone) return;
        const a = mathx.clampF(self.glow, 0, 1);
        const r = EYE_R * H * self.scale;
        for ([_]usize{ EYEL, EYER }) |b| {
            const p = foe.markOn(self.xf[b], mathx.zero3);
            rl.drawSphereEx(p, r * (1.10 + 0.10 * a), 8, 10, mathx.withAlpha(EYE_LIT, mathx.u8f(230.0 * a)));
            rl.drawSphereEx(p, r * (2.1 + 0.7 * a), 8, 10, mathx.withAlpha(EYE_LIT, mathx.u8f(60.0 * a)));
        }
    }

    pub fn draw(self: *const Leechfly, model: *const Model) void {
        model.draw(self);
    }

    pub fn pose(self: *Leechfly) void {
        if (!foe.posed(self)) return;
        const fs = foe.rigScale(self.scale, self.fade);
        const bob = mathx.sinf((self.elapsed + self.seed) * BOB_HZ * std.math.tau) * BOB_AMP * self.scale;
        const root = mul3(
            scaleM(fs, fs, fs),
            mul(rz(self.bank), mul(rx(self.pitch), ry(mathx.degrees(self.facing)))),
            tr(self.pos.x, self.pos.y + self.lift() + bob, self.pos.z),
        );
        self.xf[ROOT] = mul(place(REST[ROOT]), root);

        const droop = -(15.0 - 11.0 * self.gorge) + self.pitch * 0.45;
        const swing = mathx.sinf((self.elapsed * 1.7 + self.seed) * std.math.tau) * 4.0;
        self.xf[ABDO] = mul(mul3(scaleM(1 + 0.28 * self.gorge, 1 + 0.22 * self.gorge, 1 + 0.05 * self.gorge), rx(droop), place(REST[ABDO])), self.xf[ROOT]);
        self.xf[ABDO2] = mul(mul(rx(9.0 + swing), place(REST[ABDO2])), self.xf[ABDO]);

        const headPitch = 8.0 - 16.0 * self.lunge - 18 * self.recoil;
        self.xf[HEAD] = mul(mul(rx(headPitch), place(REST[HEAD])), self.xf[ROOT]);
        const probPitch = 46.0 - 40.0 * self.lunge;
        self.xf[PROB] = mul(mul(rx(probPitch), place(REST[PROB])), self.xf[HEAD]);
        self.xf[EYEL] = mul(place(REST[EYEL]), self.xf[HEAD]);
        self.xf[EYER] = mul(place(REST[EYER]), self.xf[HEAD]);

        const beat = mathx.sinf(self.wingPhase * std.math.tau);
        const feather = mathx.cosf(self.wingPhase * std.math.tau);
        const clearance = mathx.smoothstep(0.42, 0.90, self.hover);
        const power = @min(mathx.clampF(self.wing, 0.1, 1.15), 0.28 + 0.87 * clearance);
        const amp = WING_SWEEP * power;
        for ([_]usize{ WINGL, WINGR }, [_]f32{ 1, -1 }) |b, side| {
            const flap = beat * amp * side;
            const twist = (feather * 34.0 * power + 75 * @max(self.recoil, 1 - clearance)) * side;
            self.xf[b] = mul(mul3(ry(twist), rz(flap), place(REST[b])), self.xf[ROOT]);
        }

        for (0..LEG_N) |i| {
            const pair = legPair(i);
            const side = legSide(i);
            const ph = self.wingPhase * std.math.tau + @as(f32, @floatFromInt(pair)) * 1.9 + self.seed * 3.0;
            const kick = mathx.sinf(ph) * 7.0;
            const reach = 34.0 - 30.0 * @as(f32, @floatFromInt(pair));
            const splay = (14.0 + 8.0 * @as(f32, @floatFromInt(pair))) * side;
            self.xf[LEG_0 + i] = mul(mul3(rz(splay), rx(reach + kick + 42 * self.recoil), place(REST[LEG_0 + i])), self.xf[ROOT]);
        }
    }
};

fn place(p: rl.Vector3) rl.Matrix {
    return tr(p.x, p.y, p.z);
}

/// How long the proboscis is, in stature. Read by `beakWorld` as well as by the builder, so the point the feed is measured from IS the point the mesh draws (the ogre's `clubLowWorld` law).
const PROB_LEN: f32 = 0.30;
const EYE_R: f32 = 0.048;

fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = thoraxMesh();
    mesh[ABDO] = abdomenMesh(0);
    mesh[ABDO2] = abdomenMesh(1);
    mesh[HEAD] = headMesh();
    mesh[PROB] = probMesh();
    mesh[EYEL] = eyeMesh(1);
    mesh[EYER] = eyeMesh(-1);
    mesh[WINGL] = wingMesh(1);
    mesh[WINGR] = wingMesh(-1);
    for (0..LEG_N) |i| mesh[LEG_0 + i] = legMesh(i);
    return mesh;
}

fn thoraxMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x1EEC4);
    b.addBlob(v3(0, 0, 0), v3(0.088 * H, 0.098 * H, 0.132 * H), 9, 14, CHITIN);
    b.addBlob(v3(0, 0.058 * H, -0.010 * H), v3(0.066 * H, 0.052 * H, 0.086 * H), 7, 12, CHITIN_LT);
    b.addBlob(v3(0, 0.004 * H, 0.104 * H), v3(0.062 * H, 0.062 * H, 0.040 * H), 6, 12, CHITIN_DK);
    b.addBlob(v3(0, -0.014 * H, -0.126 * H), v3(0.050 * H, 0.048 * H, 0.036 * H), 6, 12, CHITIN_DK);
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const t = -0.06 + 0.032 * @as(f32, @floatFromInt(i));
        const w = rng.range(0.90, 1.1);
        const surface = 0.098 * @sqrt(1 - (t / 0.132) * (t / 0.132));
        b.addBlob(v3(rng.signed() * 0.006 * H, (surface - 0.008) * H, t * H), v3(0.010 * H, 0.010 * H * w, 0.012 * H), 4, 7, CHITIN_DK);
    }
    return b.toMesh();
}

fn abdomenMesh(seg: usize) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5AC0 + @as(u64, seg));
    const fat: f32 = if (seg == 0) 1.0 else 0.72;
    const len: f32 = if (seg == 0) 0.175 else 0.165;
    b.addCapsule(
        v3(0, 0, 0),
        v3(0, -0.010 * H, -len * H * 2.0),
        0.049 * H * fat,
        0.034 * H * fat,
        12,
        if (seg == 0) SAC else SAC_DK,
    );
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const t = 0.20 + 0.26 * @as(f32, @floatFromInt(i));
        const w = rng.range(0.9, 1.08);
        b.addBlob(
            v3(0, -0.010 * H * t, -len * H * 2.0 * t),
            v3(0.046 * H * fat * (1.0 - 0.26 * t) * w, 0.043 * H * fat * (1.0 - 0.26 * t), 0.008 * H),
            5,
            11,
            SAC_DK,
        );
    }
    if (seg == 0) b.addBlob(v3(0, -0.005 * H, -0.095 * H), v3(0.043 * H, 0.039 * H, 0.062 * H), 6, 12, SAC_FULL);
    if (seg == 1) b.addBlob(v3(0, -0.012 * H, -len * H * 2.04), v3(0.022 * H, 0.021 * H, 0.020 * H), 5, 10, SAC_DK);
    return b.toMesh();
}

fn headMesh() rl.Mesh {
    var b = Builder.init();
    b.addBlob(v3(0, 0, 0), v3(0.062 * H, 0.058 * H, 0.058 * H), 7, 12, CHITIN);
    b.addBlob(v3(0, 0.026 * H, -0.010 * H), v3(0.044 * H, 0.032 * H, 0.040 * H), 5, 10, CHITIN_LT);
    for ([_]f32{ 1, -1 }) |s| {
        const a0 = v3(s * 0.030 * H, 0.044 * H, 0.026 * H);
        const a1 = v3(s * 0.062 * H, 0.086 * H, -0.020 * H);
        const a2 = v3(s * 0.070 * H, 0.108 * H, -0.076 * H);
        b.addCapsule(a0, a1, 0.0075 * H, 0.0055 * H, 6, CHITIN_DK);
        b.addCapsule(a1, a2, 0.0055 * H, 0.0030 * H, 6, CHITIN_DK);
        b.addBlob(a2, v3(0.005 * H, 0.005 * H, 0.005 * H), 4, 7, CHITIN_DK);
    }
    return b.toMesh();
}

fn probMesh() rl.Mesh {
    var b = Builder.init();
    const tip = v3(0, 0, PROB_LEN * H);
    b.addCapsule(v3(0, 0, 0), tip, 0.0125 * H, 0.0032 * H, 8, BEAK);
    for ([_]f32{ 1, -1 }) |s| {
        b.addCapsule(
            v3(s * 0.008 * H, -0.004 * H, 0.020 * H),
            v3(s * 0.014 * H, -0.010 * H, PROB_LEN * H * 0.72),
            0.0042 * H,
            0.0018 * H,
            6,
            BEAK_TIP,
        );
    }
    b.addBlob(v3(0, 0, 0.010 * H), v3(0.018 * H, 0.017 * H, 0.012 * H), 5, 10, CHITIN_DK);
    return b.toMesh();
}

fn eyeMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.addBlob(v3(0, 0, 0), v3(EYE_R * H, EYE_R * H * 1.18, EYE_R * H * 1.06), 6, 10, EYE);
    b.addBlob(v3(side * 0.016 * H, 0.020 * H, 0.028 * H), v3(0.008 * H, 0.008 * H, 0.007 * H), 4, 8, rgba(104, 30, 26, 210));
    return b.toMesh();
}

fn wingChord(t: f32) f32 {
    return 0.135 * H * @sqrt(mathx.clampF(1.0 - t * t * t * 0.98, 0, 1)) * (0.42 + 0.58 * @min(1.0, t * 4.0));
}

fn wingPoint(side: f32, t: f32, chord: f32) rl.Vector3 {
    const span = 0.52 * H * (if (side > 0) @as(f32, 1.015) else 0.985);
    return v3(side * span * t, 0.008 * H * @sin(std.math.pi * t) * @sin(std.math.pi * chord), -span * 0.26 * t * t - wingChord(t) * chord);
}

fn wingMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    const segs = 20;
    for (0..segs) |i| {
        const t0 = @as(f32, @floatFromInt(i)) / segs;
        const t1 = @as(f32, @floatFromInt(i + 1)) / segs;
        for (0..3) |j| {
            const c0 = @as(f32, @floatFromInt(j)) / 3;
            const c1 = @as(f32, @floatFromInt(j + 1)) / 3;
            const p = [4]rl.Vector3{ wingPoint(side, t0, c0), wingPoint(side, t1, c0), wingPoint(side, t1, c1), wingPoint(side, t0, c1) };
            const n = mathx.normV(mathx.crossV(mathx.subV(p[1], p[0]), mathx.subV(p[2], p[0])));
            b.quad(p[0], p[1], p[2], p[3], n, WING);
            b.quad(p[3], p[2], p[1], p[0], mathx.scaleV(n, -1), WING);
        }
        b.addCapsule(wingPoint(side, t0, 0), wingPoint(side, t1, 0), lerpF(0.0060, 0.0020, t0) * H, lerpF(0.0060, 0.0020, t1) * H, 6, WING_RIB);
    }
    var rng = mathx.Rng.init(if (side > 0) 0x711E6 else 0x711E7);
    for (0..4) |i| {
        const start = 0.14 + 0.20 * @as(f32, @floatFromInt(i)) + rng.range(-0.012, 0.012);
        const end = @min(0.97, start + rng.range(0.13, 0.20));
        for (0..5) |j| {
            const k0 = @as(f32, @floatFromInt(j)) / 5;
            const k1 = @as(f32, @floatFromInt(j + 1)) / 5;
            b.addCapsule(wingPoint(side, lerpF(start, end, k0), 0.92 * k0), wingPoint(side, lerpF(start, end, k1), 0.92 * k1), lerpF(0.0025, 0.0012, k0) * H, lerpF(0.0025, 0.0012, k1) * H, 5, WING_RIB);
        }
    }
    return b.toMesh();
}
fn legMesh(i: usize) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x1E60 + @as(u64, i));
    const side = legSide(i);
    const pair = legPair(i);
    const len = (0.150 + 0.026 * @as(f32, @floatFromInt(pair))) * H * rng.range(0.94, 1.06);
    const knee = v3(side * len * 0.62, -len * 0.44, -len * 0.16 * rng.range(0.7, 1.3));
    const foot = v3(side * len * 0.74, -len * 1.06, -len * 0.52 * rng.range(0.8, 1.2));
    b.addCapsule(v3(0, 0, 0), knee, 0.0105 * H, 0.0075 * H, 6, LEG);
    b.addCapsule(knee, foot, 0.0075 * H, 0.0035 * H, 6, LEG);
    b.addBlob(knee, v3(0.011 * H, 0.011 * H, 0.011 * H), 4, 8, CHITIN_DK);
    b.addBlob(foot, v3(0.006 * H, 0.006 * H, 0.006 * H), 4, 7, CHITIN_DK);
    return b.toMesh();
}

const CAP = wf.MAX_PER_KIND;

pub const Swarm = struct {
    model: Model,
    flies: [CAP]Leechfly = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Swarm {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Swarm) []Leechfly {
        return self.flies[0..self.n];
    }
    pub fn liveConst(self: *const Swarm) []const Leechfly {
        return self.flies[0..self.n];
    }
    pub fn reset(self: *Swarm, m: *const wf.Map) void {
        foe.resetGroup(Leechfly, &self.flies, &self.n, m, .leechfly);
    }
    pub fn setShader(self: *Swarm, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn draw(self: *const Swarm, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Swarm) void {
        for (self.liveConst()) |*f| f.drawFx();
    }

    pub fn update(
        self: *Swarm,
        dt: f32,
        hero: rl.Vector3,
        bounds: f32,
        blade: foe.Blade,
        ctx: anytype,
        comptime sip: fn (@TypeOf(ctx), combat.Hit) void,
    ) ?foe.Blow {
        var blow: ?foe.Blow = null;
        for (self.live()) |*f| {
            switch (f.update(dt, f.threat.aim(hero), bounds, blade)) {
                .none => {},
                .stab => |h| foe.worseBlow(&blow, h, f.pos, &f.threat),
                .drink => |h| sip(ctx, h),
            }
        }
        return blow;
    }

    pub fn setParry(self: *Swarm, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    pub fn anyParried(self: *const Swarm) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn pierce(self: *Swarm, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Swarm) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Swarm) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Swarm) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Swarm) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

test "IT CLIMBS OUT OF SWORD REACH AND NOT OUT OF THE WORLD" {
    try std.testing.expect(HOVER_HIGH > 3.4); // clear of a swing off a 1.8 m man's shoulder
    try std.testing.expect(HOVER_HIGH < AGGRO_R);
    try std.testing.expect(HOVER_LOW < HOVER_HIGH);

    var f = Leechfly.spawn(mathx.zero3, 0, 1.0, 0.3);
    f.hover = HOVER_LOW;
    const low = f.centerWorld().y;
    f.hover = HOVER_HIGH;
    try std.testing.expect(f.centerWorld().y > low + 3.0);
    try std.testing.expect(f.centerWorld().y - f.hurtRadius() > 2.6);
}

test "the climb is a LEAP, so the roots refuse it" {
    try std.testing.expect(wantsClimb(1.0, 0, false, .stalk, false));
    try std.testing.expect(!wantsClimb(1.0, 0, false, .stalk, true)); // …held down, it cannot
    try std.testing.expect(!wantsClimb(1.0, 1.0, false, .stalk, false));
    try std.testing.expect(wantsClimb(AGGRO_R, 0, true, .stalk, false));
    for ([_]State{ .wind, .stab, .drink, .stunlight, .stunheavy, .dead, .climb, .perch, .dive }) |s| {
        try std.testing.expect(!wantsClimb(0.5, 0, true, s, false));
    }
}

test "THE FEED IS A BLOW AND THEN A HOLD, and the hold cannot reach from the sky" {
    try std.testing.expect(STAB_HIT.raw() > 0 and STAB_HIT.poise > 0);
    try std.testing.expect(DRINK_DPS > 0);
    try std.testing.expect(LEECH_SHARE > 0 and LEECH_SHARE < 1);

    var f = Leechfly.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, STAB_R * 0.5);
    f.hover = HOVER_LOW;
    f.facing = 0;
    f.pose();
    try std.testing.expect(f.holds(hero));
    f.hover = HOVER_HIGH;
    try std.testing.expect(!f.holds(hero));
    f.hover = HOVER_LOW;
    try std.testing.expect(!f.holds(v3(0, 0, -STAB_R * 0.5)));
}

test "it drinks itself well, and only up to full" {
    var f = Leechfly.spawn(mathx.zero3, 0, 1.0, 0.3);
    f.vit.hp = 10.0;
    const before = f.vit.hp;
    _ = f.sip(0.5);
    try std.testing.expect(f.vit.hp > before);
    try std.testing.expectApproxEqAbs(DRINK_DPS * 0.5 * LEECH_SHARE, f.vit.hp - before, 1e-3);
    try std.testing.expect(f.gorge > 0);
    f.vit.hp = f.vit.hpMax;
    var k: u32 = 0;
    while (k < 20) : (k += 1) _ = f.sip(0.1);
    try std.testing.expectApproxEqAbs(f.vit.hpMax, f.vit.hp, 1e-4);
}

test "no attack comes out of nowhere" {
    try std.testing.expect(WIND_DUR >= foe.TELL_MIN);
}

test "the bands never leave a gap the decision falls through" {
    var d: f32 = 0;
    while (d <= AGGRO_R) : (d += 0.25) {
        _ = classify(d, 1.0, true);
        _ = classify(d, 1.0, false);
    }
    try std.testing.expectEqual(Choice.hold, classify(AGGRO_R + 0.1, 1.0, true));
    try std.testing.expectEqual(Choice.feed, classify(STAB_R * 0.5, 1.0, true));
    try std.testing.expectEqual(Choice.circle, classify(STAB_R * 0.5, 1.0, false));
    try std.testing.expectEqual(Choice.close, classify(AGGRO_R - 0.1, 1.0, true));
}

test "THE MARK RIDES THE HEAD, four metres up as readily as one" {
    var f = Leechfly.spawn(mathx.zero3, 0, 1.0, 0.3);
    f.hover = HOVER_LOW;
    f.pose();
    const low = f.lockPoint();
    f.hover = HOVER_HIGH;
    f.pose();
    const high = f.lockPoint();
    try std.testing.expect(high.y - low.y > 2.5);
    f.lunge = 0;
    f.pose();
    const tucked = f.lockPoint();
    f.lunge = 1;
    f.pose();
    const thrown = f.lockPoint();
    try std.testing.expect(mathx.distXZ(tucked, thrown) > 0.01 or @abs(thrown.y - tucked.y) > 0.01);
}

test "the beak the feed is measured from IS the beak the mesh draws" {
    var f = Leechfly.spawn(mathx.zero3, 0, 1.0, 0.3);
    f.hover = HOVER_LOW;
    f.facing = 0;
    f.lunge = 1;
    f.pose();
    const tip = f.beakWorld();
    const head = foe.markOn(f.xf[HEAD], mathx.zero3);
    try std.testing.expect(tip.z > head.z);
    try std.testing.expect(mathx.lenV(mathx.subV(tip, head)) > PROB_LEN * H * 0.5);
}

test "THE WHINE IS PHRASED, and the silence is most of it" {
    try std.testing.expect(HUSH_MIN > PHRASE_MAX);
    try std.testing.expect(PHRASE_MIN >= WHINE_EVERY);

    const a = Leechfly.spawn(mathx.zero3, 0, 1.0, 0.10);
    const b = Leechfly.spawn(mathx.zero3, 0, 1.0, 0.80);
    try std.testing.expect(@abs(a.whineT - b.whineT) > 0.5);
    try std.testing.expect(a.whineT > 0 and b.whineT > 0);
}

test "leechfly stab reaches its physical band at different sizes and frame rates" {
    var misses: usize = 0;
    for ([_]f32{ 0.5, 1, 1.8 }) |size| {
        for ([_]f32{ 30, 60, 144 }) |fps| {
            for ([_]f32{ 0, 0.5, 1 }) |u| {
                var f = Leechfly.spawn(mathx.zero3, 0, size, 0.3);
                f.debugFeedFrom(0);
                const near = foe.closestApproach(f.bodyR()) + 0.025;
                const far = feedReach(size) * 0.97;
                const hero = v3(0, 0, lerpF(near, far, u));
                var hit: usize = 0;
                var gap: f32 = 999;
                for (0..@as(usize, @intFromFloat(fps * 0.8))) |_| {
                    const was = f;
                    const act = f.update(1 / fps, hero, 400, .{});
                    if (f.state == .stab) {
                        const beak = f.beakSeg();
                        gap = @min(gap, mathx.segmentGapV(beak[0], beak[1], v3(0, foe.HERO_LOW, hero.z), v3(0, foe.HERO_HIGH, hero.z)));
                    }
                    if (act == .stab) {
                        hit += 1;
                        try std.testing.expect(f.beakTouches(was.beakSeg(), hero));
                        try std.testing.expect(!f.beakTouches(was.beakSeg(), v3(0, 6, hero.z)));
                        var cut = was;
                        try std.testing.expect(cut.update(1 / fps, hero, 400, foe.shaftThrough(was.centerWorld(), .{ .dmg = 10000 })) == .none);
                        try std.testing.expect(cut.dying());
                    }
                }
                if (hit != 1) {
                    misses += 1;
                    std.debug.print("\n  leechfly x{d:.1} {d:.0} Hz at {d:.2} m: {d} contacts, gap {d:.2}\n", .{ size, fps, hero.z, hit, gap });
                }
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 0), misses);
}

test "leechfly drink stops healing as soon as the beak loses contact" {
    for ([_]f32{ 30, 60, 144 }) |fps| {
        var f = Leechfly.spawn(mathx.zero3, 0, 1, 0.3);
        f.debugFeedFrom(0);
        f.vit.hp = 10;
        const hero = v3(0, 0, 0.70);
        var fed = false;
        for (0..@as(usize, @intFromFloat(fps))) |_| {
            if (f.update(1 / fps, hero, 400, .{}) == .drink) {
                fed = true;
                break;
            }
        }
        try std.testing.expect(fed);
        const hp = f.vit.hp;
        const full = f.gorge;
        const escaped = v3(2, 0, 0.70);
        try std.testing.expect(f.update(1 / fps, escaped, 400, .{}) == .none);
        try std.testing.expectApproxEqAbs(hp, f.vit.hp, 1e-5);
        try std.testing.expectApproxEqAbs(full, f.gorge, 1e-5);
        try std.testing.expect(f.state == .recover);
    }
}

test "leechfly swat reaction stays continuous and rebounds before settling" {
    for ([_]f32{ 30, 60, 144 }) |fps| {
        var f = Leechfly.spawn(mathx.zero3, 0, 1, 0.3);
        f.debugFeedFrom(0);
        for (0..@as(usize, @intFromFloat(fps * 0.4))) |_| _ = f.update(1 / fps, v3(0, 0, 90), 400, .{});
        const before = f.beakWorld();
        f.stagger(true);
        f.pose();
        try std.testing.expect(mathx.lenV(mathx.subV(before, f.beakWorld())) < 1e-5);
        var peak: f32 = 0;
        var rebound: f32 = 0;
        for (0..@as(usize, @intFromFloat(fps * 2.7))) |_| {
            _ = f.update(1 / fps, v3(0, 0, 90), 400, .{});
            peak = @max(peak, f.recoil);
            rebound = @min(rebound, f.recoil);
            for ([_]usize{ WINGL, WINGR }, [_]f32{ 1, -1 }) |bone, side| {
                for (0..11) |i| {
                    const t = @as(f32, @floatFromInt(i)) / 10;
                    for ([_]f32{ 0, 0.5, 1 }) |chord| {
                        const point = rl.math.vector3Transform(wingPoint(side, t, chord), f.xf[bone]);
                        if (point.y < f.pos.y - 0.005) std.debug.print("\n  low wing {d:.3}m, t {d:.3}, recoil {d:.2}, pitch {d:.1}, bank {d:.1}, hover {d:.2}, Hz {d:.0}\n", .{ point.y, f.t, f.recoil, f.pitch, f.bank, f.hover, fps });
                        try std.testing.expect(point.y >= f.pos.y - 0.005);
                    }
                }
            }
        }
        try std.testing.expect(peak > 0.9);
        try std.testing.expect(rebound < -0.08);
        try std.testing.expect(@abs(f.recoil) < 0.01);
    }
}
