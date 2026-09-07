const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const anim = @import("../core/anim.zig");
const combat = @import("../play/combat.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const sfx = @import("../core/audio.zig");
const art = @import("../props/propart.zig");
const wood = @import("../props/propwood.zig");

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

const BARK_OLD = art.BARK_OLD;
const BARK_DK = art.BARK_DK;
const TIMBER = art.TIMBER;
const TIMBER_DK = art.TIMBER_DK;
const MOSS_DK = art.MOSS_DK;
const EYE_DIM = rgba(120, 42, 14, 255);
const EYE_LIT = rgba(255, 132, 42, 255);
const SPLINTER = rgba(84, 66, 44, 235);
/// A LIMB IS A BIG SMOOTH SUNWARD FACE — 0.28 m thick and near three long — so it needs a near-black albedo where the snag's thin 0.13 stubs get away with `BARK_DK` (AGENTS.md).
const LIMB_BARK = rgba(13, 10, 8, 255);
const LIMB_LT = rgba(24, 19, 15, 255);

/// Its own stature, in metres — sized against `propwood.snagMesh`'s own 6.0..7.6 so it stands in a line of them without being the tall one.
pub const H: f32 = 6.9;

pub var AGGRO_R: f32 = 6.8;
const WAKE_R: f32 = 4.2;
const EYES_R: f32 = 6.5;
const SLEEP_R: f32 = 8.2;

const BODY_R: f32 = 0.62; // a trunk: you cannot walk through it and it cannot be shouldered off its spot
const HURT_R: f32 = 1.25;
const CENTER_F: f32 = 0.17;
const TOP_F: f32 = 0.96;
const LOCK_AT = v3(0, 0.30 * H, 0.45);

const HP_MAX: f32 = 130.0;
const POISE_MAX: f32 = 28.0;
const STANCE_MAX: f32 = 40.0;
const RESISTS = combat.resists(.{ .fire = -70, .cold = 40, .lightning = -20, .chaos = 30 });
pub var SOULS: u32 = 150;

const DEATH_DUR: f32 = 1.9;
const DISS_DUR: f32 = 1.1;
const DISSOLVE = foe.Dissolve{ .rate = 62.0, .spread = 1.15, .rise = 0.85, .flake = SPLINTER };

pub const SLAM_HIT = combat.Hit{ .dmg = 34, .poise = 26, .stance = 10, .launch = combat.SLAM_LAUNCH };
pub const SWEEP_HIT = combat.Hit{ .dmg = 26, .poise = 20 };
pub const HOOK_HIT = combat.Hit{ .dmg = 14, .poise = 14 };
pub const DRAG_PULL: f32 = 3.4;
const IMPACT_K: f32 = 0.68;

const Attack = struct {
    windDur: f32,
    strikeDur: f32,
    recoverDur: f32,
    cd: f32,
    minR: f32,
    maxR: f32,
    arc: f32,
    hit: combat.Hit,
    limb: usize,
};

pub const SLAM: usize = 0;
pub const SWEEP: usize = 1;
pub const HOOK: usize = 2;
/// Wind-ups are LONG and every one clears `foe.TELL_MIN`. The bands are MEASURED off the posed tip: the old 7.4 m hook billed a blow off a limb that passed three metres over his head.
const MOVES_BANK = [_]Attack{
    .{ .windDur = 0.86, .strikeDur = 0.26, .recoverDur = 0.95, .cd = 3.4, .minR = 0, .maxR = 2.4, .arc = 46.0, .hit = SLAM_HIT, .limb = LIMB_H },
    .{ .windDur = 0.70, .strikeDur = 0.32, .recoverDur = 0.80, .cd = 2.8, .minR = 1.2, .maxR = 3.8, .arc = 82.0, .hit = SWEEP_HIT, .limb = LIMB_L },
    .{ .windDur = 0.66, .strikeDur = 0.30, .recoverDur = 1.15, .cd = 5.0, .minR = 2.8, .maxR = 4.25, .arc = 58.0, .hit = HOOK_HIT, .limb = LIMB_R },
};
/// the bench can reach is `MOVES[i].hit`, so a move retuned in the source flows through (`play/tune.zig`).
pub var MOVES = MOVES_BANK;

comptime {
    const named = .{ .{ SLAM, SLAM_HIT }, .{ SWEEP, SWEEP_HIT }, .{ HOOK, HOOK_HIT } };
    if (named.len != MOVES.len) @compileError("rooted: MOVES and the named indices disagree on how many strikes there are");
    for (named) |row| {
        if (!std.meta.eql(MOVES_BANK[row[0]].hit, row[1])) @compileError("rooted: a named index no longer points at its own row of MOVES");
    }
}

pub fn moveClock(which: usize) foe.Clock {
    return foe.moveClock(MOVES[@min(which, MOVES.len - 1)]);
}

const WAKE_DUR: f32 = 0.95;
const SLEEP_DUR: f32 = 1.30;

const SWAY_HZ: f32 = 0.21;
const SWAY_DEG: f32 = 3.2;
const CREAK_EVERY: f32 = 4.4;
const EYES_RATE: f32 = 0.7;
const LID_SWING: f32 = 96.0;

const HIT_CHIP_LIGHT = 9;
const HIT_CHIP_HEAVY = 16;
/// What the tip throws off the ground it lands its own blow on.
const STRIKE_SPLINTERS: i32 = 15;
const PARTS = 56;
comptime {
    // Its tip landing a blow on the same frame a heavy of his wounds the trunk.
    std.debug.assert(PARTS >= STRIKE_SPLINTERS + foe.hitParts(HIT_CHIP_HEAVY) + foe.WOUND_PARTS);
}

const N = 16;
const ROOT = 0;
const BOLE = 1;
const BOLE2 = 2;
const LID_L = 3;
const LID_R = 4;
const LIMB_L = 5;
const LIMB_R = 8;
const LIMB_H = 11;
const CLAW_L = 14;
const CLAW_R = 15;
const SEGS = 3;
const LIMBS = [_]usize{ LIMB_L, LIMB_R, LIMB_H };
comptime {
    std.debug.assert(LIMB_R == LIMB_L + SEGS and LIMB_H == LIMB_R + SEGS and CLAW_L == LIMB_H + SEGS);
    std.debug.assert(SEG_LEN.len == SEGS and LIMB_SHUT.len == SEGS and LIMB_OPEN.len == SEGS);
    std.debug.assert(LIMB_Y.len == LIMBS.len and LIMB_A.len == LIMBS.len);
}

const EYE_Y: f32 = 0.30 * H;
const EYE_HALF: f32 = 0.21;
const EYE_Z: f32 = 0.45;

const BOLE_Y: f32 = 0.42 * H;
const BOLE2_Y: f32 = 0.34 * H;
const LIMB_Y = [_]f32{ 0.46 * H, 0.42 * H, 0.60 * H };
const LIMB_A = [_]f32{ 52.0, -58.0, 6.0 };
const SEG_LEN = [_]f32{ 0.24 * H, 0.20 * H, 0.15 * H };

const REST = blk: {
    var r = [_]rl.Vector3{mathx.zero3} ** N;
    r[BOLE] = v3(0, 0, 0);
    r[BOLE2] = v3(0, BOLE_Y, 0);
    r[LID_L] = v3(EYE_HALF, EYE_Y, EYE_Z);
    r[LID_R] = v3(-EYE_HALF, EYE_Y, EYE_Z);
    for (LIMBS, 0..) |b, i| {
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

const Choice = enum { sleep, hold, slam, sweep, hook };
// Height limits the large bodies before horizontal arm length does.
fn bandR(a: Attack, scale: f32) f32 {
    const rootY = LIMB_Y[(a.limb - LIMB_L) / SEGS] * scale;
    const reach = (SEG_LEN[0] + SEG_LEN[1] + SEG_LEN[2]) * scale * 0.985;
    const drop = @max(0, rootY - 1.35);
    const physical = @sqrt(@max(0, reach * reach - drop * drop)) + 0.22 * scale + foe.HERO_R;
    return @min(foe.triggerBand(a.maxR, 1.0, scale), physical);
}
/// THE NEAR EDGE IS THE SAME LIMB, SO IT TAKES THE SAME TRIANGLE. Held raw against a scaled far edge the hook's band INVERTS at `wf.FOE_SCALE_LO` — 2.8 against a 2.58 — and a fixture that cannot close never throws it at all.
fn nearR(a: Attack, scale: f32) f32 {
    return foe.triggerBand(a.minR, 1.0, scale);
}
fn classify(dist: f32, scale: f32, ready: [MOVES.len]bool) Choice {
    if (dist > SLEEP_R) return .sleep;
    if (dist <= bandR(MOVES[SLAM], scale) and ready[SLAM]) return .slam;
    if (dist >= nearR(MOVES[SWEEP], scale) and dist <= bandR(MOVES[SWEEP], scale) and ready[SWEEP]) return .sweep;
    if (dist >= nearR(MOVES[HOOK], scale) and dist <= bandR(MOVES[HOOK], scale) and ready[HOOK]) return .hook;
    return .hold;
}

pub const Act = union(enum) {
    none,
    struck: struct { hit: combat.Hit, pull: f32 },
};

pub const Model = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "rooted");
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
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    facing: f32 = 0,
    scale: f32 = 1.0,
    aimR: f32 = 2.4,
    seed: f32 = 0,

    state: State = .dormant,
    t: f32 = 0,
    elapsed: f32 = 0,
    atk: usize = SLAM,
    dealt: bool = false,
    parry: foe.Parry = .{},
    parried: bool = false,
    cds: [MOVES.len]f32 = [_]f32{0} ** MOVES.len,
    creakT: f32 = 0,

    open: f32 = 0,
    eyes: f32 = 0,
    swing: f32 = 0,
    angles: [20]f32 = [_]f32{0} ** 20,
    springs: anim.SpringBank(20) = .{},
    sway: f32 = 0,

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

    xf: [N]rl.Matrix = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Rooted {
        var t = Rooted{ .pos = home, .home = home, .facing = faceYaw, .scale = scale, .seed = seed };
        t.fxRng = foe.fxStream(seed, 40961.0, 0x700D);
        t.creakT = seed * CREAK_EVERY;
        t.seatPose();
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
    pub fn airborne(self: *const Rooted) bool {
        _ = self;
        return false;
    }
    pub fn flashFrac(self: *const Rooted) f32 {
        return foe.flashFrac(self.flash);
    }
    pub fn hidden(self: *const Rooted) bool {
        return self.state == .dormant;
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
        _ = bounds;
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
        for (&self.cds) |*c| c.* = mathx.maxF(0, c.* - dt);
        foe.tickFixedLeash(&self.leash, dt, self.home, hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);

        const limbWas = self.limbWorld(self.move().limb);
        var striking = false;
        const d = mathx.distXZ(self.pos, hero);

        switch (self.state) {
            .dormant => {
                self.open = mathx.approach(self.open, 0, dt * 1.6);
                self.swing = mathx.approach(self.swing, 0, dt * 2.0);
                if (d <= WAKE_R) self.beginWake();
            },
            .wake => {
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
                self.aimR = d;
                self.swing = anim.keyAt(&WIND_KEYS, self.t / a.windDur);
                if (self.t >= a.windDur) {
                    sfx.world(.wood_swing, self.tipWorld());
                    self.enter(.strike);
                }
            },
            .strike => {
                const a = self.move();
                const u = mathx.clampF(self.t / a.strikeDur, 0, 1);
                self.swing = anim.keyAt(&STRIKE_KEYS, u);
                striking = !self.dealt and u >= 0.12;
                if (self.t >= a.strikeDur) self.enter(.recover);
            },
            .recover => {
                self.swing = anim.keyAt(&RECOVER_KEYS, self.t / self.move().recoverDur);
                self.faceToward(hero, dt);
                if (self.t >= self.move().recoverDur) self.decide(d);
            },
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

        self.eyes = mathx.approach(self.eyes, if (d <= EYES_R and self.state != .dead) 1 else 0, dt * EYES_RATE);
        self.creak(dt);
        self.sway = mathx.sinf((self.elapsed + self.seed * 6.0) * SWAY_HZ * std.math.tau) * SWAY_DEG * self.open;
        self.poseStep(dt);
        self.pose();
        const contact = striking and self.branchTouches(limbWas, hero);
        const stopped = self.takeParry(striking and self.branchTouches(limbWas, self.parry.at));
        self.tryHit(blade);
        if (stopped or self.staggered()) return .none;
        if (contact) {
            self.dealt = true;
            self.leash.noteCombat();
            sfx.world(.wood_hit, self.tipWorld());
            self.splinters(self.tipWorld(), STRIKE_SPLINTERS);
            return .{ .struck = .{ .hit = self.move().hit, .pull = if (self.atk == HOOK) DRAG_PULL else 0 } };
        }
        return .none;
    }

    fn toImpact(self: *const Rooted) ?f32 {
        if (self.atk == SLAM) return null;
        const a = self.move();
        const at = a.strikeDur * IMPACT_K;
        return switch (self.state) {
            .wind => (a.windDur - self.t) + at,
            .strike => at - self.t,
            .dormant, .wake, .idle, .recover, .sleep, .stunlight, .stunheavy, .dead => null,
        };
    }

    fn parryable(self: *const Rooted) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!self.parry.window(left)) return null;
        return foe.hurtReach(self.move().maxR, self.scale);
    }

    fn takeParry(self: *Rooted, touching: bool) bool {
        if (self.atk == SLAM) return false;
        const reach = self.parryable() orelse self.parry.reach() orelse if (touching) foe.hurtReach(self.move().maxR, self.scale) else return false;
        if (!foe.caught(self, reach, self.toImpact(), touching)) return false;
        self.cds[self.atk] = self.move().cd;
        self.dealt = true;
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light, .none => self.enterStun(.stunlight),
        }
        return true;
    }

    fn wokeAgain(self: *Rooted, hero: rl.Vector3, dt: f32, blade: foe.Blade) Act {
        self.enter(.idle);
        self.faceToward(hero, dt);
        self.poseStep(dt);
        self.pose();
        self.tryHit(blade);
        return .none;
    }

    fn limbWorld(self: *const Rooted, b: usize) [SEGS][3]rl.Vector3 {
        var out: [SEGS][3]rl.Vector3 = undefined;
        const limb = (b - LIMB_L) / SEGS;
        for (&out, 0..) |*points, seg| {
            for (points, limbLine(limb, seg)) |*p, local| p.* = foe.markOn(self.xf[b + seg], local);
        }
        return out;
    }

    fn branchTouches(self: *const Rooted, was: [SEGS][3]rl.Vector3, hero: rl.Vector3) bool {
        const now = self.limbWorld(self.move().limb);
        for (was, now, 0..) |old, points, seg| {
            for (0..2) |k| {
                const r = limbRadius(seg) * lerpF(1, 0.72, @as(f32, @floatFromInt(k)) * 0.55);
                if (foe.sweptWeaponReaches(.{ old[k], old[k + 1] }, .{ points[k], points[k + 1] }, hero, foe.HERO_R + r * self.scale)) return true;
            }
        }
        return false;
    }

    pub fn reaches(self: *const Rooted, hero: rl.Vector3, a: Attack) bool {
        _ = a;
        return self.branchTouches(self.limbWorld(self.move().limb), hero);
    }
    fn faceToward(self: *Rooted, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, 1.5, dt);
    }

    fn enter(self: *Rooted, s: State) void {
        self.state = s;
        self.t = 0;
        self.dealt = false;
    }

    fn beginWake(self: *Rooted) void {
        sfx.world(.wood_wake, self.centerWorld());
        self.enter(.wake);
    }

    fn decide(self: *Rooted, dist: f32) void {
        var ready: [MOVES.len]bool = undefined;
        for (&ready, self.cds) |*r, c| r.* = c <= 0;
        switch (classify(dist, self.scale, ready)) {
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
        sfx.world(.wood_creak, self.centerWorld());
        self.enter(.wind);
    }

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
    pub fn stagger(self: *Rooted, heavy: bool) void {
        self.open = 1;
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugMove(self: *Rooted, which: usize) void {
        self.open = 1;
        self.enter(.idle);
        self.seatPose();
        self.pose();
        self.begin(which);
    }
    pub fn debugWake(self: *Rooted) void {
        self.enter(.wake);
    }

    pub fn tryHit(self: *Rooted, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const face = self.facing;
        const s = self.trunkHit(blade) orelse return;
        self.facing = face;
        if (self.state == .dormant or self.state == .sleep) self.beginWake();
        const heavy = foe.wounded(self, s, blade, .{ .light = 0, .heavy = 0 });
        self.splinters(s.contact, foe.hitParts(if (heavy) HIT_CHIP_HEAVY else HIT_CHIP_LIGHT));
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

    fn trunkHit(self: *Rooted, blade: foe.Blade) ?foe.Strike {
        if (!blade.active) {
            if (!blade.pierce) self.hitLatch = false;
            return null;
        }
        for ([_]usize{ BOLE, BOLE2 }, 0..) |bone, seg| {
            const line = boleLine(seg);
            const radii = boleRadii(seg);
            for (0..2) |piece| {
                const start: f32 = if (piece == 0) 0 else 0.53;
                const end: f32 = if (piece == 0) 0.53 else 1;
                const steps: usize = @intFromFloat(@ceil(mathx.lenV(mathx.subV(line[piece + 1], line[piece])) / (radii[1] * 0.5)));
                for (0..steps + 1) |k| {
                    const along = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(steps));
                    const center = foe.markOn(self.xf[bone], mathx.lerpV(line[piece], line[piece + 1], along));
                    const radius = lerpF(radii[0], radii[1], lerpF(start, end, along)) * self.scale;
                    if (foe.reachedPart(self, &self.vit, blade, .{ .center = center, .r = radius })) |hit| return hit;
                }
            }
        }
        return null;
    }
    fn splinters(self: *Rooted, at: rl.Vector3, motes: i32) void {
        var i: i32 = 0;
        while (i < motes) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.6, 1.0) * 3.2;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(at.x + self.fxRng.signed() * 0.1, at.y + self.fxRng.signed() * 0.1, at.z + self.fxRng.signed() * 0.1),
                .v = v3(mathx.cosf(a) * sp, self.fxRng.range(1.2, 3.6), mathx.sinf(a) * sp),
                .life = self.fxRng.range(0.32, 0.62),
                .r0 = self.fxRng.range(0.025, 0.055) * self.scale,
                .r1 = 0.008,
                .col = if (self.fxRng.float() < 0.4) TIMBER else SPLINTER,
                .grav = 7.0,
                .stretch = 0.035,
                .bounce = 0.30,
            });
        }
    }

    pub fn drawFx(self: *const Rooted) void {
        foe.drawParticles(&self.parts);
        if (self.gone or self.eyes <= 0.02) return;
        const cocked = if (self.state == .wind) mathx.clampF(-self.swing, 0, 1) else 0;
        const lit = mathx.clampF(0.30 * self.open + 0.35 * cocked, 0, 1);
        const a = self.eyes;
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

    fn targets(self: *const Rooted) [20]f32 {
        const swinging = self.state == .wind or self.state == .strike or self.state == .recover;
        const swing = if (swinging) self.swing else 0;
        const cock = mathx.clampF(-swing, 0, 1);
        const thru = mathx.clampF(swing, 0, 1);
        const reaction: f32 = switch (self.state) {
            .stunlight, .stunheavy => anim.keyAt(&RECOIL_KEYS, self.t / combat.foeStunDur(self.state == .stunheavy)) * (if (self.state == .stunheavy) @as(f32, 1) else 0.55),
            else => 0,
        };
        const death = if (self.state == .dead) mathx.smoothstep(0, DEATH_DUR * 0.6, self.t) else 0;
        var out = [_]f32{0} ** 20;
        out[0] = 9 * self.open + self.sway - 26 * reaction + 26 * death;
        out[1] = 9 * reaction;
        if (swinging) switch (self.atk) {
            SLAM => out[0] += -9 * cock + 16 * thru,
            SWEEP => {
                out[0] += 4 * thru;
                out[1] += -24 * cock + 26 * thru;
            },
            else => {
                out[0] += 10 * cock - 5 * thru;
                out[1] += 10 * cock - 14 * thru;
            },
        };
        for (LIMBS, 0..) |b0, i| {
            const fi: f32 = @floatFromInt(i);
            const live = swinging and self.move().limb == b0;
            const s = if (live) swing else 0;
            const openI = mathx.clampF((self.open - 0.14 * fi) / (1 - 0.14 * fi), 0, 1);
            for (0..SEGS) |seg| {
                const ch = 2 + seg * 6 + i * 2;
                out[ch] = lerpF(LIMB_SHUT[seg], LIMB_OPEN[seg], openI) - 20 * reaction - 22 * death;
                out[ch + 1] = (if (seg == 0) LIMB_A[i] else 0) + 12 * reaction * yawSign(i);
            }
            if (live) {
                const phase: f32 = if (self.state == .wind) 0 else if (self.state == .strike) (s + 1) * 0.5 else 1;
                const weight = if (self.state == .wind) cock else if (self.state == .strike) 1 else anim.keyAt(&RETURN_KEYS, self.t / self.move().recoverDur);
                const solved = self.strikeAngles(i, &out, mathx.clampF(phase, 0, 1));
                for (0..SEGS) |seg| {
                    const ch = 2 + seg * 6 + i * 2;
                    out[ch] += mathx.wrapDeg(solved[seg * 2] - out[ch]) * weight;
                    out[ch + 1] += mathx.wrapDeg(solved[seg * 2 + 1] - out[ch + 1]) * weight;
                }
            }
        }
        return out;
    }

    fn strikeAngles(self: *const Rooted, limb: usize, body: *const [20]f32, phase: f32) [6]f32 {
        const lowerBole = mul(ry(body[1] * 0.5), rx(body[0] * 0.45));
        const bole = mul(mul3(ry(body[1] * 0.5), rx(body[0] * 0.55), place(REST[BOLE2])), lowerBole);
        const shoulder = foe.markOn(bole, branchRest(LIMBS[limb]));
        const reach = mathx.clampF(self.aimR - 0.12, BODY_R * self.scale + 0.15, bandR(self.move(), self.scale)) / self.scale;
        var target: rl.Vector3 = undefined;
        switch (self.atk) {
            SLAM => target = v3(0, lerpF(LIMB_Y[2] + 2.1, 0.42 / self.scale, phase), lerpF(0.85, reach, phase)),
            SWEEP => {
                const bearing = mathx.radians(lerpF(70, -55, phase));
                target = v3(@sin(bearing) * reach, 1.05 / self.scale, @cos(bearing) * reach);
            },
            else => {
                const bearing = mathx.radians(lerpF(-55, 18, phase));
                const extend = anim.keyAt(&.{ .{ .t = 0, .v = 0.63 }, .{ .t = 0.76, .v = 1, .ease = .decel }, .{ .t = 1, .v = 0.88 } }, phase);
                target = v3(@sin(bearing) * reach * extend, lerpF(1.8 / self.scale + 0.35, 0.82 / self.scale, phase), @cos(bearing) * reach * extend);
            },
        }
        const curl = mathx.radians(if (self.atk == SLAM) @as(f32, 26) else 16);
        const lower = @sqrt(SEG_LEN[1] * SEG_LEN[1] + SEG_LEN[2] * SEG_LEN[2] + 2 * SEG_LEN[1] * SEG_LEN[2] * @cos(curl));
        const hint = v3(if (limb == 0) @as(f32, 0.3) else -0.3, 1, -0.15);
        const upper = mathx.twoBone(shoulder, target, SEG_LEN[0], lower, hint);
        const outer = mathx.twoBone(upper.joint, upper.end, SEG_LEN[1], SEG_LEN[2], v3(0, -1, 0));
        const points = [_]rl.Vector3{ shoulder, upper.joint, outer.joint, outer.end };
        var parent = bole;
        var result: [6]f32 = undefined;
        for (0..SEGS) |seg| {
            const inverse = rl.math.matrixInvert(parent);
            const local = mathx.normV(mathx.subV(foe.markOn(inverse, points[seg + 1]), foe.markOn(inverse, points[seg])));
            const pitch = mathx.degrees(std.math.atan2(-local.y, mathx.lenXZ(local)));
            const yaw = mathx.degrees(std.math.atan2(local.x, local.z));
            result[seg * 2] = pitch;
            result[seg * 2 + 1] = yaw;
            parent = mul(mul(rx(pitch), ry(yaw)), parent);
        }
        return result;
    }
    fn seatPose(self: *Rooted) void {
        self.angles = self.targets();
        self.springs.seat(self.angles);
    }

    fn poseStep(self: *Rooted, dt: f32) void {
        self.angles = self.targets();
        for (&self.angles, self.springs.s) |*target, spring| target.* = spring.v + mathx.wrapDeg(target.* - spring.v);
        self.springs.chase(&self.angles, 2100, 0.74, 0.98, dt);
    }

    pub fn pose(self: *Rooted) void {
        if (!foe.posed(self)) return;
        const fs = foe.rigScale(self.scale, self.fade);
        const root = mul3(scaleM(fs, fs, fs), ry(mathx.degrees(self.facing)), tr(self.pos.x, self.pos.y, self.pos.z));
        self.xf[ROOT] = root;
        self.xf[BOLE] = mul(mul3(ry(self.angles[1] * 0.5), rx(self.angles[0] * 0.45), place(REST[BOLE])), root);
        self.xf[BOLE2] = mul(mul3(ry(self.angles[1] * 0.5), rx(self.angles[0] * 0.55), place(REST[BOLE2])), self.xf[BOLE]);

        inline for ([_]usize{ LID_L, LID_R }, [_]f32{ 1, -1 }) |b, side| {
            self.xf[b] = mul(mul3(rz(side * LID_SWING * 0.25 * self.eyes), rx(-LID_SWING * self.eyes), place(REST[b])), self.xf[BOLE]);
        }
        for (LIMBS, 0..) |b0, i| {
            for (0..SEGS) |seg| {
                const ch = 2 + seg * 6 + i * 2;
                const m = mul3(rx(self.angles[ch]), ry(self.angles[ch + 1]), place(if (seg == 0) branchRest(b0) else REST[b0 + seg]));
                self.xf[b0 + seg] = mul(m, if (seg == 0) self.xf[BOLE2] else self.xf[b0 + seg - 1]);
            }
        }
        const heave = 22 * self.open;
        self.xf[CLAW_L] = mul(mul(rx(-heave), place(REST[CLAW_L])), root);
        self.xf[CLAW_R] = mul(mul(rx(-heave * 0.7), place(REST[CLAW_R])), root);
    }
};

const WIND_KEYS = [_]anim.Key{
    .{ .t = 0, .v = 0 },
    .{ .t = 0.64, .v = -1, .ease = .decel },
    .{ .t = 1, .v = -1, .ease = .hold },
};
const STRIKE_KEYS = [_]anim.Key{
    .{ .t = 0, .v = -1 },
    .{ .t = 0.72, .v = 1, .ease = .accel },
    .{ .t = 1, .v = 1.12, .ease = .decel },
};
const RECOVER_KEYS = [_]anim.Key{
    .{ .t = 0, .v = 1.12 },
    .{ .t = 0.16, .v = 1.12, .ease = .hold },
    .{ .t = 0.70, .v = -0.10, .ease = .decel },
    .{ .t = 1, .v = 0 },
};
const RETURN_KEYS = [_]anim.Key{
    .{ .t = 0, .v = 1 },
    .{ .t = 0.16, .v = 1, .ease = .hold },
    .{ .t = 0.80, .v = -0.06, .ease = .decel },
    .{ .t = 1, .v = 0 },
};
const RECOIL_KEYS = [_]anim.Key{
    .{ .t = 0, .v = 0 },
    .{ .t = 0.18, .v = 1, .ease = .decel },
    .{ .t = 0.68, .v = -0.22, .ease = .decel },
    .{ .t = 1, .v = 0 },
};
const LIMB_SHUT = [_]f32{ 84.0, -48.0, -28.0 };
const LIMB_OPEN = [_]f32{ 24.0, -34.0, 52.0 };

fn yawSign(i: usize) f32 {
    return if (i == 0) -1 else 1;
}

fn branchRest(b: usize) rl.Vector3 {
    return mathx.subV(REST[b], REST[BOLE2]);
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
    inline for (LIMBS, 0..) |b0, i| {
        for (0..SEGS) |seg| mesh[b0 + seg] = limbMesh(i, seg);
    }
    mesh[CLAW_L] = clawMesh(0);
    mesh[CLAW_R] = clawMesh(1);
    return mesh;
}

fn baseMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x2007ED);
    b.setMat(.wood);
    b.addCapsule(v3(0, 0, 0), v3(0, 0.10 * H, 0), 0.78, 0.62, 14, BARK_OLD);
    var r: i32 = 0;
    while (r < 6) : (r += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(r)) / 6.0 + rng.signed() * 0.3;
        const end = v3(mathx.cosf(a) * rng.range(0.9, 1.5), 0.04, mathx.sinf(a) * rng.range(0.9, 1.5));
        const elbow = v3(end.x * 0.53 + rng.signed() * 0.1, rng.range(0.14, 0.24), end.z * 0.58);
        b.addCapsule(v3(0, 0.40, 0), elbow, 0.19, 0.13, 9, BARK_OLD);
        b.addCapsule(
            elbow,
            end,
            0.13,
            0.055,
            9,
            BARK_OLD,
        );
    }
    b.setMat(.plant);
    var g: i32 = 0;
    while (g < 4) : (g += 1) art.tuftInto(&b, &rng, rng.signed() * 1.4, rng.signed() * 1.4, 0.9);
    return b.toMesh();
}

fn boleLine(seg: usize) [3]rl.Vector3 {
    const len: f32 = if (seg == 0) BOLE_Y else BOLE2_Y;
    return .{ mathx.zero3, v3(if (seg == 0) @as(f32, 0.075) else -0.06, len * 0.53, -0.035), v3(0, len, 0) };
}

fn boleRadii(seg: usize) [2]f32 {
    return if (seg == 0) .{ 0.62, 0.44 } else .{ 0.42, 0.27 };
}
fn boleMesh(seg: usize) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x80BE + @as(u64, seg));
    b.setMat(.wood);
    const len: f32 = if (seg == 0) BOLE_Y else BOLE2_Y;
    const radii = boleRadii(seg);
    const r0 = radii[0];
    const r1 = radii[1];
    const line = boleLine(seg);
    const bend = line[1];
    const bark = if (seg == 0) LIMB_LT else LIMB_BARK;
    const middle = lerpF(r0, r1, 0.53);
    b.addCapsule(line[0], bend, r0, middle, 14, bark);
    b.addCapsule(bend, line[2], middle, r1, 14, bark);
    var s: i32 = 0;
    while (s < 7) : (s += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(s)) / 7.0 + rng.signed() * 0.24;
        const y0 = rng.range(0.1, len * 0.85);
        const y1 = @min(y0 + rng.range(0.5, len * 0.5), len - 0.1);
        const rr0 = lerpF(r0, r1, y0 / len) * 0.94;
        const rr1 = lerpF(r0, r1, y1 / len) * 0.94;
        const turn = a + rng.signed() * 0.15;
        b.addCapsule(
            v3(mathx.cosf(a) * rr0, y0, mathx.sinf(a) * rr0),
            v3(mathx.cosf(turn) * rr1, y1, mathx.sinf(turn) * rr1),
            rr0 * rng.range(0.06, 0.085),
            rr1 * rng.range(0.06, 0.085),
            5,
            if (rng.float() < 0.7) BARK_DK else TIMBER,
        );
    }
    var l: i32 = 0;
    while (l < 3) : (l += 1) {
        const y = rng.range(len * 0.3, len * 0.9);
        wood.deadLimbInto(&b, &rng, v3(0, y, 0), rng.angle(), rng.range(0.6, 1.2), rng.range(0.1, 0.35), 0.13, rng.intn(2));
    }
    if (seg == 1) {
        b.addBlob(v3(0, len - 0.02, 0), v3(0.24, 0.06, 0.24), 3, 7, TIMBER);
        var k: i32 = 0;
        while (k < 4) : (k += 1) {
            const a = rng.angle();
            const d = rng.range(0.04, 0.2);
            b.addCapsule(
                v3(mathx.cosf(a) * d, len, mathx.sinf(a) * d),
                v3(mathx.cosf(a) * d * 1.9, len + rng.range(0.25, 0.9), mathx.sinf(a) * d * 1.9),
                rng.range(0.06, 0.13),
                0.045,
                4,
                if (rng.float() < 0.45) TIMBER else BARK_DK,
            );
        }
    }
    b.setMat(.plant);
    b.addBlob(v3(mathx.cosf(1.9) * r0 * 0.6, rng.range(0.4, len * 0.7), mathx.sinf(1.9) * r0 * 0.6), v3(0.28, 0.36, 0.24), 3, 6, MOSS_DK);
    return b.toMesh();
}

fn lidMesh(which: usize) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x11D0 + @as(u64, which));
    b.setMat(.wood);
    const w = 0.165 * rng.range(0.9, 1.1);
    b.addBlob(v3(0, 0, 0.02), v3(w, w * rng.range(0.62, 0.8), 0.055), 4, 9, BARK_OLD);
    b.addBlob(v3(rng.signed() * 0.05, w * 0.4, 0.05), v3(w * 0.5, w * 0.22, 0.03), 3, 6, BARK_DK);
    return b.toMesh();
}

fn limbRadius(seg: usize) f32 {
    return 0.23 - 0.06 * @as(f32, @floatFromInt(seg));
}

fn limbLine(limb: usize, seg: usize) [3]rl.Vector3 {
    var rng = mathx.Rng.init(0x11B0 + @as(u64, limb) * 7 + @as(u64, seg));
    const len = SEG_LEN[seg];
    return .{ mathx.zero3, v3(rng.signed() * len * 0.10, rng.signed() * len * 0.08, len * 0.55), v3(0, 0, len) };
}

fn limbMesh(limb: usize, seg: usize) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x91B0 + @as(u64, limb) * 7 + @as(u64, seg));
    b.setMat(.wood);
    const line = limbLine(limb, seg);
    const r0 = limbRadius(seg);
    const r1 = r0 * 0.72;
    b.addBlob(line[0], v3(r0 * 1.035, r0 * 1.02, r0 * 0.96), 5, 12, LIMB_BARK);
    b.addCapsule(line[0], line[1], r0, lerpF(r0, r1, 0.55), 12, LIMB_BARK);
    b.addCapsule(line[1], line[2], lerpF(r0, r1, 0.55), r1, 12, LIMB_BARK);
    if (seg == SEGS - 1) {
        b.addBlob(line[2], v3(r1 * 0.93, r1 * 0.87, r1 * 0.14), 4, 10, TIMBER);
        for (0..3) |_| {
            const a = rng.angle();
            const from = mathx.addV(line[2], v3(mathx.cosf(a) * r1 * 0.45, mathx.sinf(a) * r1 * 0.45, -r1 * 0.3));
            const elbow = mathx.addV(from, v3(mathx.cosf(a) * 0.10, 0.08, rng.range(0.10, 0.18)));
            const tip = mathx.addV(elbow, v3(mathx.cosf(a) * 0.04, -0.07, 0.06));
            b.addCapsule(from, elbow, r1 * 0.46, r1 * 0.32, 7, LIMB_BARK);
            b.addCapsule(elbow, tip, r1 * 0.32, r1 * 0.28, 7, LIMB_BARK);
            b.addBlob(tip, v3(r1 * 0.26, r1 * 0.24, r1 * 0.12), 3, 7, TIMBER);
        }
    }
    for (0..2) |_| {
        const k = rng.range(0.1, 0.75);
        const from = mathx.lerpV(line[1], line[2], k);
        wood.deadLimbInto(&b, &rng, from, rng.angle(), SEG_LEN[seg] * rng.range(0.18, 0.32), 0.07, r1 * 0.48, 0);
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
                    foe.worseBlow(&blow, s.hit, t.pos, &t.threat);
                    if (s.pull > 0) yank(ctx, t.pos, s.pull);
                },
            }
        }
        return blow;
    }

    pub fn setParry(self: *Grove, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    pub fn anyParried(self: *const Grove) bool {
        return foe.anyParried(self.liveConst());
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
    try std.testing.expect(t.hidden());
    try std.testing.expectApproxEqAbs(@as(f32, 0), t.open, 1e-4);

    var k: u32 = 0;
    while (k < 240) : (k += 1) _ = t.update(1.0 / 60.0, v3(0, 0, WAKE_R + 2.0), 400, .{});
    try std.testing.expect(t.hidden());

    _ = t.update(1.0 / 60.0, v3(0, 0, WAKE_R - 0.5), 400, .{});
    try std.testing.expect(!t.hidden());
    k = 0;
    while (k < 90) : (k += 1) _ = t.update(1.0 / 60.0, v3(0, 0, WAKE_R - 0.5), 400, .{});
    try std.testing.expect(t.open > 0.9);

    k = 0;
    while (k < 400) : (k += 1) _ = t.update(1.0 / 60.0, v3(0, 0, SLEEP_R + 3.0), 400, .{});
    try std.testing.expect(t.hidden());
    try std.testing.expectApproxEqAbs(@as(f32, 0), t.open, 1e-3);
}

test "THE GRIP BITES A ROOTED TOO, and it lets go of its own accord" {
    var t = Rooted.spawn(mathx.zero3, 0, 1.0, 0.3);
    const full = t.vit.hp;
    t.root.grab();
    try std.testing.expect(t.root.held());
    var k: f32 = 0;
    while (k < combat.ROOT_HOLD + 0.2) : (k += 1.0 / 60.0) _ = t.update(1.0 / 60.0, v3(0, 0, 30), 400, .{});
    try std.testing.expect(!t.root.held());
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
    try std.testing.expect(t.hits > 0);
    try std.testing.expectEqual(mathx.zero3, t.shove);
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
    try std.testing.expect(!t.hidden());
}

test "every band is answered, so it cannot be kited" {
    const all = [_]bool{ true, true, true };
    var d: f32 = 0;
    while (d <= bandR(MOVES[HOOK], 1)) : (d += 0.2) {
        try std.testing.expect(classify(d, 1.0, all) != .hold);
    }
    try std.testing.expectEqual(Choice.slam, classify(1.0, 1.0, all));
    try std.testing.expectEqual(Choice.sweep, classify(3.0, 1.0, all));
    try std.testing.expectEqual(Choice.hook, classify(bandR(MOVES[HOOK], 1) - 0.05, 1.0, all));
    try std.testing.expectEqual(Choice.sleep, classify(SLEEP_R + 0.1, 1.0, all));
    try std.testing.expect(MOVES[HOOK].maxR > WAKE_R);
    try std.testing.expect(SLEEP_R > MOVES[HOOK].maxR);
    try std.testing.expectEqual(Choice.hold, classify(1.0, 1.0, [_]bool{ false, false, false }));

    // AND AT EVERY SCALE THE MAP CAN POST IT. A fixture cannot walk out of a gap, so a near edge left at the authored metre while the far edge scales is a ring of ground it owns and never swings at.
    for ([_]f32{ wf.FOE_SCALE_LO, 1.0, wf.FOE_SCALE_HI }) |scale| {
        const far = bandR(MOVES[HOOK], scale);
        try std.testing.expect(nearR(MOVES[HOOK], scale) < far);
        try std.testing.expect(nearR(MOVES[SWEEP], scale) < bandR(MOVES[SWEEP], scale));
        var s: f32 = 0;
        while (s <= far) : (s += 0.05) {
            try std.testing.expect(classify(s, scale, all) != .hold);
        }
        std.debug.print("\n  rooted x{d:.2}: slam to {d:.2}, sweep {d:.2}-{d:.2}, hook {d:.2}-{d:.2}\n", .{
            scale,                      bandR(MOVES[SLAM], scale), nearR(MOVES[SWEEP], scale),
            bandR(MOVES[SWEEP], scale), nearR(MOVES[HOOK], scale), far,
        });
    }
}

test "A LIMB GOES WHERE ITS BILL SAYS: the tip crosses the hero column, out near the band's edge" {
    // Walk each move's strike and measure the POSED tip: a hook billed at 7.4 m off a limb whose tip hung 2.8 m over the hero's head.
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
        try std.testing.expect(minY < 1.55);
        try std.testing.expect(maxR + foe.HERO_REACH >= a.maxR - 0.2);
    }
}

test "no attack comes out of nowhere, and the hook is the one that drags" {
    for (MOVES) |m| try std.testing.expect(m.windDur >= foe.TELL_MIN);
    try std.testing.expect(DRAG_PULL > 0);
    try std.testing.expect(HOOK_HIT.raw() < SWEEP_HIT.raw());
    try std.testing.expect(SWEEP_HIT.raw() < SLAM_HIT.raw());
    try std.testing.expect(MOVES[HOOK].maxR - DRAG_PULL <= MOVES[SWEEP].maxR);
}

test "the mark rides the KNOT, and the knot rides the bole" {
    var t = Rooted.spawn(mathx.zero3, 0, 1.0, 0.3);
    t.open = 0;
    t.pose();
    const asleep = t.lockPoint();
    t.open = 1;
    t.sway = SWAY_DEG;
    t.seatPose();
    t.pose();
    const awake = t.lockPoint();
    try std.testing.expect(mathx.lenV(mathx.subV(asleep, awake)) > 0.05);
}

test "THE SWEEP AND THE HOOK CAN BE CAUGHT, AND THE SLAM CANNOT — the launcher is answered on foot" {
    for ([_]usize{ SWEEP, HOOK }) |mv| {
        var r = Rooted.spawn(mathx.zero3, 0, 1.0, 0.3);
        r.state = .strike;
        r.atk = mv;
        const a = MOVES[mv];
        r.t = a.strikeDur * IMPACT_K - foe.PARRY_LEAD * 0.5;
        const reach = r.parryable() orelse return error.TestUnexpectedResult;
        try std.testing.expectApproxEqAbs(foe.hurtReach(a.maxR, r.scale), reach, 1e-5);
        r.parry = .{ .live = true, .at = mathx.ground(0, a.maxR * 0.5), .facing = std.math.pi, .arc = combat.GUARD_ARC };
        try std.testing.expect(!r.takeParry(false));
        try std.testing.expect(r.parry.pending != null);
        r.t = a.strikeDur * IMPACT_K;
        try std.testing.expect(r.takeParry(true));
        try std.testing.expect(r.parried);
        try std.testing.expect(r.cds[mv] > 0);
        try std.testing.expect(r.state == .stunlight or r.state == .stunheavy);
        try std.testing.expect(r.parryable() == null);
    }
    var big = Rooted.spawn(mathx.zero3, 0, 1.0, 0.3);
    big.atk = SLAM;
    try std.testing.expect(SLAM_HIT.launch > 0);
    for ([_]State{ .wind, .strike }) |st| {
        big.state = st;
        var t: f32 = 0;
        while (t < MOVES[SLAM].windDur + MOVES[SLAM].strikeDur) : (t += 1.0 / 240.0) {
            big.t = t;
            try std.testing.expect(big.parryable() == null);
        }
    }
}

test "shooting it dead costs the whole quiver, which is what stands in for a ranged answer" {
    const plain = HP_MAX / 16.0;
    try std.testing.expect(plain > 7.0 and plain <= combat.ARROWS_MAX);
    var v = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    const fire = combat.Hit{ .dmg = 16, .elem = combat.elems(.{ .fire = 8 }) };
    var shots: u32 = 0;
    while (!v.dead and shots < 40) : (shots += 1) _ = v.hit(fire);
    try std.testing.expect(shots <= combat.FIRE_ARROWS_MAX + 1);
}

test "rooted branches reach their whole choice band at every scale and frame rate" {
    for ([_]f32{ 0.5, 1, 1.8, wf.FOE_SCALE_HI }) |size| {
        for ([_]f32{ 30, 60, 144 }) |fps| {
            for (0..MOVES.len) |which| {
                const a = MOVES[which];
                const near = @max(BODY_R * size + foe.HERO_R, nearR(a, size));
                const far = bandR(a, size);
                for (0..9) |stand| {
                    const distance = lerpF(near, far, @as(f32, @floatFromInt(stand)) / 8);
                    const hero = v3(0, 0, distance);
                    var body = Rooted.spawn(mathx.zero3, 0, size, 0.3);
                    body.debugMove(which);
                    var elapsed: f32 = 0;
                    var hits: usize = 0;
                    while (elapsed < a.windDur + a.strikeDur + 0.5) : (elapsed += 1 / fps) {
                        const old = body.limbWorld(a.limb);
                        const result = body.update(1 / fps, hero, 400, .{});
                        if (result == .struck) {
                            try std.testing.expect(elapsed + 1 / fps >= a.windDur);
                            try std.testing.expect(body.branchTouches(old, hero));
                            if (which != SLAM) {
                                var caught = body;
                                caught.dealt = false;
                                caught.parry = .{ .live = true, .at = hero, .facing = std.math.pi, .arc = combat.GUARD_ARC };
                                try std.testing.expect(caught.takeParry(caught.branchTouches(old, hero)));
                                try std.testing.expect(caught.parried);
                            }
                            hits += 1;
                        }
                    }
                    if (hits != 1) std.debug.print("\n rooted miss: move {d}, x{d:.1}, {d:.0}Hz, range {d:.3}, hits {d}\n", .{ which, size, fps, distance, hits });
                    try std.testing.expectEqual(@as(usize, 1), hits);
                }
            }
        }
    }
}

test "rooted branch interruptions stay continuous, rebound and cancel outgoing contact" {
    for (0..MOVES.len) |which| {
        const a = MOVES[which];
        var body = Rooted.spawn(mathx.zero3, 0, 1, 0.3);
        body.debugMove(which);
        const hero = v3(0, 0, bandR(a, 1) - 0.2);
        while (body.state == .wind) _ = body.update(1.0 / 60.0, hero, 400, .{});
        for (0..3) |_| _ = body.update(1.0 / 60.0, hero, 400, .{});
        const was = body.tipWorld();
        const angles = body.angles;
        body.stagger(true);
        body.pose();
        try std.testing.expect(mathx.lenV(mathx.subV(was, body.tipWorld())) < 0.0001);
        try std.testing.expectEqual(angles, body.angles);
        var back: f32 = 0;
        var forward: f32 = 0;
        for (0..180) |_| {
            const hit = body.update(1.0 / 60.0, v3(0, 0, 7), 400, .{});
            try std.testing.expect(hit == .none);
            back = @min(back, body.angles[0]);
            forward = @max(forward, body.angles[0]);
        }
        try std.testing.expect(back < -8);
        try std.testing.expect(forward > 12);

        var trial = Rooted.spawn(mathx.zero3, 0, 1, 0.3);
        trial.debugMove(which);
        var interrupted = false;
        for (0..180) |_| {
            var probe = trial;
            if (probe.update(1.0 / 60.0, hero, 400, .{}) == .struck) {
                const c = trial.centerWorld();
                const hit = trial.update(1.0 / 60.0, hero, 400, .{ .active = true, .a = c, .b = c, .a0 = c, .b0 = c, .r = 0.1, .hit = .{ .dmg = 1, .stance = 100 } });
                try std.testing.expect(hit == .none);
                try std.testing.expect(trial.staggered());
                interrupted = true;
                break;
            }
            trial = probe;
        }
        try std.testing.expect(interrupted);
    }
}

test "rooted wood never bills a hit through empty height or behind the tree" {
    for (0..MOVES.len) |which| {
        var body = Rooted.spawn(mathx.zero3, 0, 1, 0.3);
        body.debugMove(which);
        const quarry = v3(0, 0, bandR(MOVES[which], 1) - 0.1);
        for (0..160) |_| {
            const was = body.limbWorld(MOVES[which].limb);
            _ = body.update(1.0 / 60.0, quarry, 400, .{});
            if (body.state != .strike) continue;
            try std.testing.expect(!body.branchTouches(was, v3(0, 12, quarry.z)));
            try std.testing.expect(!body.branchTouches(was, v3(0, 0, -3)));
        }
    }
}

test "rooted folded branches clear the floor through wake recoil and death" {
    for ([_]f32{ 0.5, 1, 2 }) |size| {
        for (0..4) |mode| {
            var body = Rooted.spawn(mathx.zero3, 0, size, 0.3);
            switch (mode) {
                1 => body.debugWake(),
                2 => body.stagger(true),
                3 => {
                    body.debugMove(SWEEP);
                    body.debugKill();
                },
                else => {},
            }
            for (0..180) |frame| {
                _ = body.update(1.0 / 60.0, v3(0, 0, if (mode == 1) @as(f32, 4) else 90), 400, .{});
                if (body.fade > 0.05) break;
                for (LIMBS) |limb| {
                    for (body.limbWorld(limb), 0..) |points, seg| {
                        for (points) |point| {
                            const sole = point.y - limbRadius(seg) * size;
                            if (sole < -0.04) std.debug.print("\n rooted floor: mode {d} frame {d}, x{d:.1}, limb {d} seg {d}, depth {d:.3}\n", .{ mode, frame, size, limb, seg, sole });
                            try std.testing.expect(sole >= -0.04);
                        }
                    }
                }
            }
        }
    }
}
test "rooted trunk hurt volume follows the bent wood and accepts its upper bole" {
    for ([_]f32{ 0.5, 1, 2 }) |size| {
        var body = Rooted.spawn(mathx.zero3, 0, size, 0.3);
        body.debugMove(SWEEP);
        for (0..30) |_| _ = body.update(1.0 / 60.0, v3(0, 0, 3), 400, .{});
        const face = body.facing;
        for ([_]usize{ BOLE, BOLE2 }, 0..) |bone, seg| {
            const line = boleLine(seg);
            const surface = foe.markOn(body.xf[bone], line[1]);
            var hit = body;
            hit.tryHit(foe.shaftThrough(surface, .{ .dmg = 1 }));
            try std.testing.expectEqual(body.hits + 1, hit.hits);
            try std.testing.expectApproxEqAbs(face, hit.facing, 1e-5);
        }
        var miss = body;
        const empty = mathx.addV(body.centerWorld(), v3(1.1 * size, 0, 0));
        miss.tryHit(.{ .active = true, .a = empty, .b = empty, .a0 = empty, .b0 = empty, .r = 0.03, .hit = .{ .dmg = 1 } });
        try std.testing.expectEqual(body.hits, miss.hits);
    }
}
