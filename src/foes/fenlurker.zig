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
const PARTS = 72;


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

const TURN_RATE: f32 = 2.2;

pub const SHOVE = foe.Push{ .light = 0.55, .heavy = 1.30 };
const SHOVE_DECAY: f32 = 9.0;


pub const N = 10;
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
const NECK = [_]usize{ S0, S1, S2, S3, S4 };
pub const PARENT = [N]i32{ -1, ROOT, S0, S1, S2, S3, S4, HEAD, HEAD, HEAD };

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

pub const State = enum { sunk, surge, lash, recover, sink, hurt, dead };

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
        for (0..N) |i| rl.drawMesh(self.mesh[i], self.mat, l.xf[i]);
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

    pub fn update(self: *Lurker, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        self.justDied = false;
        self.heroHit = null;
        self.broke = false;
        self.lashed = false;
        self.yelped = false;
        self.sank = false;
        self.parried = false;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.stateStep(dt, hero, bounds);
        self.takeParry();
        self.tryHit(blade);
        return self.heroHit;
    }

    fn toImpact(self: *const Lurker) ?f32 {
        const at = LASH_DUR * LASH_IMPACT_K;
        return switch (self.state) {
            .surge => (SURGE_DUR - self.t) + at,
            .lash => at - self.t,
            .sunk, .recover, .sink, .hurt, .dead => null,
        };
    }

    fn parryable(self: *const Lurker) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        return foe.hurtReach(LASH_R, self.scale);
    }

    fn takeParry(self: *Lurker) void {
        const reach = self.parryable() orelse return;
        if (!foe.caught(self, reach)) return;
        self.heroLatch = true;
        self.splash(foe.markOn(self.xf[HEAD], mathx.zero3), 8);
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
        foe.tickFixedLeash(&self.leash, dt, self.home, hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        switch (self.state) {
            .dead => {
                self.up = mathx.approach(self.up, 0, dt / SINK_DUR);
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
            .hurt => {
                self.up = mathx.approach(self.up, 1.0, dt * 2.2);
                if (self.t >= combat.foeStunDur(self.heavyStun)) self.enter(.recover);
            },
            .sunk => {
                if (!self.pooled()) {
                    self.up = mathx.approach(self.up, 1.0, dt / SINK_DUR);
                    if (self.feelsDry(hero)) self.begin(hero);
                    return self.settleAndPose(dt);
                }
                self.up = mathx.approach(self.up, 0, dt / SINK_DUR);
                if (self.restT <= 0 and self.feels(hero)) self.begin(hero);
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
            .recover => {
                self.up = 1.0;
                self.swing = mathx.approach(self.swing, 0, dt * 2.6);
                self.heroLatch = false;
                if (self.t >= RECOVER_DUR) {
                    if (self.canReach(hero)) {
                        self.enter(.surge);
                        self.t = SURGE_DUR * 0.45;
                    } else if (self.pooled()) {
                        self.beginSink();
                    } else self.enter(.sunk);
                }
            },
            .sink => {
                self.up = 1.0 - mathx.smoothstep(0, SINK_DUR, self.t);
                self.swing = mathx.approach(self.swing, 0, dt * 2.0);
                if (self.pooled() and self.canReach(hero)) {
                    self.enter(.surge);
                    self.t = SURGE_DUR * self.up;
                    return self.settleAndPose(dt);
                }
                if (self.t >= SINK_DUR) {
                    self.restT = REST_DUR;
                    self.enter(.sunk);
                }
            },
        }
        self.settleAndPose(dt);
    }

    fn begin(self: *Lurker, hero: rl.Vector3) void {
        self.faceToward(hero, 1.0);
        self.enter(.surge);
        self.heroLatch = false;
        self.broke = true;
    }

    fn feelsDry(self: *const Lurker, hero: rl.Vector3) bool {
        return mathx.distXZ(self.pos, hero) <= AGGRO_R;
    }

    fn canReach(self: *const Lurker, hero: rl.Vector3) bool {
        if (self.leash.goingHome()) return false;
        return if (self.pooled()) self.feels(hero) else self.feelsDry(hero);
    }

    fn beginSink(self: *Lurker) void {
        self.enter(.sink);
        self.sank = true;
    }

    fn settleAndPose(self: *Lurker, dt: f32) void {
        self.swingL1 = mathx.approach(self.swingL1, self.swing, dt * LAG_1);
        self.swingL2 = mathx.approach(self.swingL2, self.swingL1, dt * LAG_2);
        self.pose();
    }

    fn tryLash(self: *Lurker, hero: rl.Vector3) void {
        if (self.heroLatch) return;
        if (!foe.inFront(self.pos, self.facing, hero, foe.hurtReach(LASH_R, self.scale), LASH_FRONT_DOT)) return;
        self.heroHit = LASH_HIT;
        self.heroLatch = true;
        self.leash.noteCombat();
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
        const s = self.scale;
        const react: f32 = if (self.state == .hurt) foe.stunCurve(self.t, self.heavyStun) else 0;
        const fall: f32 = if (self.state == .dead) mathx.clampF(self.t / (DEATH_DUR * 0.7), 0, 1) else 0;
        const sink = -(1.0 - self.up) * SUBMERGE * H;
        const breath = mathx.sinf(self.elapsed * 1.35 + self.seed * 6.28) * 0.010 * H * self.up;

        // THE WHOLE BODY DIVES WITH THE STROKE. A curled chain moves the head SIDEWAYS more than down — measured, five distributed bends finished the lash at 2.04 m, over his head.
        const dive = LASH_DIVE * mathx.maxF(0, self.swing);
        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            mul(scaleM(s, s, s), mul(rx(dive), rz(-38.0 * mathx.smoothstep(0, 1, fall)))),
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
        heromod.setJoint(&wx, &self.rest, HEAD, S4, mul(rx(HEAD_BEND * self.swing - 26.0 * react), rz(-6.0 * self.swingL2)));
        const gape = GAPE * mathx.clampF(self.swing * 0.5 + 0.5, 0, 1) * self.up - 34.0 * react;
        heromod.setJoint(&wx, &self.rest, JAW, HEAD, rx(gape));
        const trail = -18.0 * self.swingL2 + 10.0 * react;
        heromod.setJoint(&wx, &self.rest, BARBL, HEAD, mul(rx(trail), rz(-BARB_SPLAY - 5.0 * self.swingL2)));
        heromod.setJoint(&wx, &self.rest, BARBR, HEAD, mul(rx(trail), rz(BARB_SPLAY + 5.0 * self.swingL2)));
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
    pub fn update(self: *Marsh, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        for (self.live()) |*l| {
            if (foe.corporeal(l) and l.hidden() and l.pooled()) l.ripple(dt);
        }
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
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
    for (0..N) |i| crown = @max(crown, foe.markOn(l.xf[i], mathx.zero3).y - l.pos.y);
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
        if (l.update(dt, hero, 200.0, .{})) |h| {
            landed += 1;
            try std.testing.expectApproxEqAbs(LASH_HIT.dmg, h.dmg, 1e-4);
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

test "THE NECK IS A WHIP, NOT A HINGE — the tip carries more of the stroke than the root does" {
    try std.testing.expect(SEG_BEND_HI > SEG_BEND_LO * 2.0);
    try std.testing.expect(HEAD_BEND > SEG_BEND_HI);
    try std.testing.expect(LAG_2 < LAG_1);
}
