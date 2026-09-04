const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
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
const scaleM = mathx.scaleM;
const lerpF = mathx.lerpF;
const placeAt = mathx.placeAt;

const Pal = struct {
    shroud: rl.Color,
    shroudLt: rl.Color,
    shroudDk: rl.Color,
    hollow: rl.Color,
    limb: rl.Color,
    limbDk: rl.Color,
    eye: rl.Color,
    eyeCore: rl.Color,
};

const PAL = [NROLE]Pal{
    .{
        .shroud = rgba(13, 12, 19, 255),
        .shroudLt = rgba(26, 24, 38, 255),
        .shroudDk = rgba(6, 6, 10, 255),
        .hollow = rgba(2, 2, 4, 255),
        .limb = rgba(19, 17, 30, 255),
        .limbDk = rgba(9, 8, 15, 255),
        .eye = rgba(126, 92, 206, 70),
        .eyeCore = rgba(206, 180, 255, 30),
    },
    .{
        .shroud = rgba(17, 17, 19, 255),
        .shroudLt = rgba(33, 33, 36, 255),
        .shroudDk = rgba(8, 8, 9, 255),
        .hollow = rgba(2, 2, 2, 255),
        .limb = rgba(24, 23, 25, 255),
        .limbDk = rgba(11, 11, 12, 255),
        .eye = rgba(174, 162, 194, 78),
        .eyeCore = rgba(228, 222, 240, 34),
    },
};

const WISP_COL = rgba(96, 118, 176, 210);
const WISP_DK = rgba(46, 58, 96, 190);
const DRAIN = rgba(150, 116, 232, 220);
const RIFT = rgba(176, 196, 244, 235);

pub const H: f32 = 1.92;
const HOVER: f32 = 0.20;
const CORE_Y: f32 = 0.56 * H;

pub var AGGRO_R: f32 = 22.0;
const BODY_R: f32 = 0.33;
const HURT_R: f32 = 0.44;
const CENTER_F: f32 = 0.62;
const TOP_F: f32 = 1.00;
const LOCK_AT = v3(0, 0.052 * H, 0.060 * H);

const DRIFT_SPEED: f32 = 2.15;
const CIRCLE_SPEED: f32 = 1.95;
const TURN_RATE: f32 = 7.0;

const HP_MAX: f32 = 46.0;
const POISE_MAX: f32 = 11.0;
const STANCE_MAX: f32 = 26.0;
const RESISTS = combat.resists(.{ .fire = 30, .cold = 65, .chaos = -45 });
pub var SOULS: u32 = 110;

const DEATH_DUR: f32 = 0.55;
const DISS_DUR: f32 = 0.75;
const SHOVE_DECAY: f32 = 9.0;

pub const GRASP_HIT = combat.Hit{ .dmg = 7, .poise = 12, .fp = 14 };

/// **TWO GRASPS, NOT ONE**: 52 against a 100 meter decaying 20/s after 1.1 s quiet.
pub const MOURN_STUPEFY: f32 = 52.0;
pub const MOURN_GRASP_HIT = blk: {
    var h = GRASP_HIT;
    h.dmg = 16;
    h.poise = 20;
    h.dose = combat.Doses.one(.stupefy, MOURN_STUPEFY);
    break :blk h;
};

pub const Role = enum { shade, mourner };
pub const NROLE = @typeInfo(Role).@"enum".fields.len;

pub fn roleOf(k: wf.FoeKind) ?Role {
    return switch (k) {
        .shade => .shade,
        .mourner => .mourner,
        else => null,
    };
}

pub fn kindOf(r: Role) wf.FoeKind {
    return switch (r) {
        .shade => .shade,
        .mourner => .mourner,
    };
}

const Spec = struct {
    role: Role,
    hp: f32,
    souls: u32,
    size: f32,
    /// Its own clocks, divided. Over 1 is SLOWER.
    slow: f32,
    grasp: combat.Hit,
};

const SPEC = [NROLE]Spec{
    .{ .role = .shade, .hp = HP_MAX, .souls = 110, .size = 1.0, .slow = 1.0, .grasp = GRASP_HIT },
    .{ .role = .mourner, .hp = 96.0, .souls = 265, .size = 1.28, .slow = 1.24, .grasp = MOURN_GRASP_HIT },
};

comptime {
    for (SPEC, 0..) |sp, i| {
        if (@intFromEnum(sp.role) != i) @compileError("shade: SPEC is out of `Role` order");
        if (sp.hp <= 0 or sp.size <= 0 or sp.slow <= 0) @compileError("shade: a role with no body");
    }
    std.debug.assert(spec(.mourner).size > spec(.shade).size and spec(.mourner).slow > spec(.shade).slow);
    std.debug.assert(spec(.mourner).souls > spec(.shade).souls and spec(.mourner).hp > spec(.shade).hp);
    std.debug.assert(spec(.shade).grasp.dose.at(.stupefy) == 0);
    std.debug.assert(spec(.mourner).grasp.dose.at(.stupefy) > 0);
}

pub fn spec(r: Role) Spec {
    return SPEC[@intFromEnum(r)];
}
pub const WISP_HIT = combat.Hit{ .dmg = 20, .poise = 10 };
pub const WISP_SPEED: f32 = 13.5;

const Attack = struct {
    windDur: f32,
    strikeDur: f32,
    recoverDur: f32,
    cd: f32,
    minR: f32,
    maxR: f32,
    hit: combat.Hit,
    hurl: bool,
};

pub const GRASP: usize = 0;
pub const WISP: usize = 1;
const MOVES_BANK = [_]Attack{
    .{ .windDur = 0.46, .strikeDur = 0.30, .recoverDur = 0.55, .cd = 2.6, .minR = 0, .maxR = 2.05, .hit = GRASP_HIT, .hurl = false },
    .{ .windDur = 0.68, .strikeDur = 0.18, .recoverDur = 0.62, .cd = 4.6, .minR = 4.2, .maxR = 12.0, .hit = WISP_HIT, .hurl = true },
};
/// the bench can reach is `MOVES[i].hit`, so a move retuned in the source flows through (`play/tune.zig`).
pub var MOVES = MOVES_BANK;

comptime {
    const named = .{ .{ GRASP, false }, .{ WISP, true } };
    if (named.len != MOVES.len) @compileError("shade: MOVES and the named indices disagree on how many moves there are");
    for (named) |row| {
        if (MOVES_BANK[row[0]].hurl != row[1]) @compileError("shade: a named index no longer points at its own row of MOVES");
    }
}
pub fn moveClock(which: usize) foe.Clock {
    return foe.moveClock(MOVES[@min(which, MOVES.len - 1)]);
}

const GRASP_REACH: f32 = MOVES_BANK[GRASP].maxR;


const THREAT_R: f32 = 2.4;
const BLINK_CD: f32 = 5.2;
pub const BLINK_OUT: f32 = 0.18;
pub const BLINK_IN: f32 = 0.24;
const BLINK_R: f32 = 5.0;
const BLINK_TURN_MIN: f32 = 105.0;
const BLINK_TURN_MAX: f32 = 165.0; // which is what puts it off the shoulder a guard cannot cover.
const SPOOK_DUR: f32 = 7.0;

/// THE ARMS' OWN ARC. The grasp is both hands closing in FRONT of it, so a hero at its back is not somebody it has hold of: tested on distance alone it landed a blow the shield's own 65° could never answer.
const GRASP_ARC: f32 = 78.0;
const GRASP_IMPACT_K: f32 = 0.42;

const CIRCLE_DUR: f32 = 1.3;
const CIRCLE_BAND: f32 = 3.1;

const IDLE_BOB: f32 = 0.055 * H;
const BOB_HZ: f32 = 0.62;
const LEAN_MAX: f32 = 15.0; // degrees it tips into its travel — from the WAIST, it has no hips to hinge at
const HEM_LAG_RATE: f32 = 5.2;
const HEM_SWING: f32 = 34.0; // degrees of tatter throw at full travel
const HEM_WOBBLE: f32 = 6.0;
const HEM_LEE: f32 = 0.34;

const RIFT_N = 14;
const DRAIN_N = 12;
const TORN_N = 10;
const UNRAVEL_N = 26;
/// ARITHMETIC over the worst frame (the ring law): the killing strike lays `tornMotes` (15) and the shared wound, then `enterDeath` unravels the body over the same frame — 45 on its own, with a blink's rift (14, still up at a 0.30 s life) under it.
const PARTS = 64;
comptime {
    std.debug.assert(PARTS >= RIFT_N + foe.hitParts(TORN_N) + UNRAVEL_N + foe.WOUND_PARTS);
    std.debug.assert(RIFT_N >= DRAIN_N); // the rift is the bigger of the two one-shots the blow can land on
}

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
const HEM_N = 8;
const HEM_R: f32 = 0.074 * H;
const HEM_Y: f32 = -0.118 * H;

const SH_HALF: f32 = 0.118 * H;
const SH_Y: f32 = 0.190 * H;

const REST = blk: {
    var r = [_]rl.Vector3{mathx.zero3} ** N;
    r[ROOT] = v3(0, 0, 0);
    r[TORSO] = v3(0, 0, 0);
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

const Choice = enum { hold, close, circle, grasp, wisp };
fn classify(dist: f32, graspReady: bool, wispReady: bool) Choice {
    if (dist > AGGRO_R) return .hold;
    if (dist <= MOVES[GRASP].maxR) return if (graspReady) .grasp else .circle;
    if (dist >= MOVES[WISP].minR and dist <= MOVES[WISP].maxR and wispReady) return .wisp;
    if (dist > CIRCLE_BAND) return .close;
    return .circle;
}

fn wantsBlink(dist: f32, cd: f32, spooked: bool, s: State, rooted: bool) bool {
    if (cd > 0 or rooted) return false;
    if (!spooked and dist > THREAT_R) return false;
    return switch (s) {
        .idle, .drift, .circle, .recover => true,
        .wind, .strike, .blinkout, .blinkin, .stunlight, .stunheavy, .dead => false,
    };
}

pub const Act = union(enum) {
    none,
    hurl: rl.Vector3,
    grasp: combat.Hit,
};

pub const Model = struct {
    mesh: [NROLE][N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "shade");
        var mesh: [NROLE][N]rl.Mesh = undefined;
        for (0..NROLE) |r| mesh[r] = buildMeshes(PAL[r]);
        return .{ .mesh = mesh, .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, s: *const Shade) void {
        const set = &self.mesh[@intFromEnum(s.role)];
        for (0..N) |i| rl.drawMesh(set[i], self.mat, s.xf[i]);
    }
};

pub const Shade = struct {
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
    atk: usize = GRASP,
    parry: foe.Parry = .{},
    parried: bool = false,
    dealt: bool = false,
    cds: [MOVES.len]f32 = [_]f32{0} ** MOVES.len,
    blinkCd: f32 = 0,
    spookLeft: f32 = 0,
    blinkTo: rl.Vector3 = mathx.zero3,
    driftDir: rl.Vector3 = mathx.zero3,
    orbitSign: f32 = 1,

    lean: f32 = 0,
    reach: f32 = 0,
    gather: f32 = 0,
    hemVel: rl.Vector3 = mathx.zero3,
    thin: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    role: Role = .shade,
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},
    gone: bool = false,

    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    xf: [N]rl.Matrix = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Shade {
        return spawnAs(.shade, home, faceYaw, scale, seed);
    }

    pub fn spawnAs(role: Role, home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Shade {
        const sp = spec(role);
        var s = Shade{ .pos = home, .home = home, .facing = faceYaw, .scale = scale * sp.size, .seed = seed, .role = role };
        s.vit = combat.Vitals.initFoe(sp.hp, POISE_MAX, STANCE_MAX).withRes(RESISTS);
        s.fxRng = foe.fxStream(seed, 7331.0, 0x5EED);
        s.orbitSign = if (seed < 0.5) 1 else -1;
        s.cds[WISP] = seed * MOVES[WISP].cd;
        s.pose();
        return s;
    }

    pub fn kind(self: *const Shade) wf.FoeKind {
        return kindOf(self.role);
    }
    pub fn soulValue(self: *const Shade) u32 {
        return spec(self.role).souls;
    }

    /// What it is holding itself off the ground by — the `lift` every other creature passes a hop or a leap as, which for this one is simply always there. EVERY WORLD POINT IS MEASURED OFF `pos.y` PLUS THIS, so a shade over a bank keeps its own head.
    fn hover(self: *const Shade) f32 {
        return HOVER * self.scale;
    }
    pub fn centerWorld(self: *const Shade) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H, self.scale, self.hover());
    }
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
    pub fn airborne(self: *const Shade) bool {
        return self.state == .blinkout or self.state == .blinkin;
    }
    pub fn flashFrac(self: *const Shade) f32 {
        return foe.flashFrac(self.flash);
    }

    pub fn wispWorld(self: *const Shade) rl.Vector3 {
        const l = rl.math.vector3Transform(mathx.zero3, self.xf[WRL]);
        const r = rl.math.vector3Transform(mathx.zero3, self.xf[WRR]);
        return mathx.lerpV(l, r, 0.5);
    }

    fn move(self: *const Shade) Attack {
        var a = MOVES[@min(self.atk, MOVES.len - 1)];
        if (self.atk == GRASP) a.hit = spec(self.role).grasp;
        return a;
    }

    pub fn update(self: *Shade, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) Act {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return .none;
        }
        self.justDied = false;
        self.parried = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer if (!self.airborne()) grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.elapsed += dt;
        self.t += dt / spec(self.role).slow;
        self.vit.tick(dt);
        foe.fadeFlash(&self.flash, dt);
        for (&self.cds) |*c| c.* = mathx.maxF(0, c.* - dt);
        self.blinkCd = mathx.maxF(0, self.blinkCd - dt);
        self.spookLeft = mathx.maxF(0, self.spookLeft - dt);
        foe.tickLeash(&self.leash, dt, self.pos, foe.tetherFor(self), hero, AGGRO_R);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);
        foe.tickParticles(&self.parts, dt, self.pos.y);

        var act: Act = .none;
        // WHERE THE WISP LEAVES FROM IS READ AFTER THE POSE, not at the release: `reach` snaps from the wind's 0.30 to 1.0 on this exact frame, swinging the shoulder through 94 degrees.
        var hurling = false;
        const was = self.pos;
        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);

        switch (self.state) {
            .idle => {
                self.easeRest(dt);
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                const ps = foe.postStep(self, dt, bounds, DRIFT_SPEED, d, AGGRO_R);
                if (ps.yaw) |w| self.facing = mathx.approachAngle(self.facing, w, TURN_RATE * dt);
                self.decide(d, hero);
            },
            .drift => {
                self.easeRest(dt);
                self.faceToward(hero, dt);
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
                    if (!self.dealt and u >= GRASP_IMPACT_K and self.holds(hero)) {
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
                    mathx.holdXZ(&self.pos, bounds);
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
            .dead => {
                self.reach = mathx.approach(self.reach, -0.2, dt * 2.0);
                self.thin = mathx.smoothstep(0, DEATH_DUR + DISS_DUR, self.t);
                if (self.t >= DEATH_DUR + DISS_DUR) self.gone = true;
            },
        }

        if (wantsBlink(d, self.blinkCd, self.spookLeft > 0, self.state, !foe.canLeap(&self.root))) self.enterBlink(hero);

        self.trailHem(if (self.airborne()) self.pos else was, dt);
        self.pose();
        if (hurling) act = .{ .hurl = self.wispWorld() };
        if (self.takeParry()) act = .none;
        self.tryHit(blade);
        return act;
    }

    /// SECONDS BACK FROM THE HAND ARRIVING, or null. **THE GRASP ONLY, NEVER THE WISP** — a shield is braced against a stroke, and the hurl is a thing thrown from 12 m away.
    fn toImpact(self: *const Shade) ?f32 {
        if (self.atk != GRASP) return null;
        const a = MOVES[GRASP];
        const at = a.strikeDur * GRASP_IMPACT_K;
        return switch (self.state) {
            .wind => (a.windDur - self.t) + at,
            .strike => at - self.t,
            .idle, .drift, .circle, .recover, .blinkout, .blinkin, .stunlight, .stunheavy, .dead => null,
        };
    }

    fn parryable(self: *const Shade) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        return self.graspReach();
    }

    fn takeParry(self: *Shade) bool {
        const reach = self.parryable() orelse return false;
        if (!foe.caught(self, reach)) return false;
        self.cds[GRASP] = MOVES[GRASP].cd;
        self.dealt = true;
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light, .none => self.enterStun(.stunlight),
        }
        return true;
    }

    pub fn graspReach(self: *const Shade) f32 {
        return foe.hurtReach(GRASP_REACH, self.scale);
    }

    pub fn holds(self: *const Shade, hero: rl.Vector3) bool {
        return foe.inArc(self.pos, self.facing, hero, self.graspReach(), GRASP_ARC);
    }

    fn faceToward(self: *Shade, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }

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
            self.driftDir = mathx.dirXZ(self.pos, foe.tetherFor(self));
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

    fn enterBlink(self: *Shade, hero: rl.Vector3) void {
        var out = mathx.dirXZ(hero, self.pos);
        if (mathx.lenXZ(out) < 1e-3) out = mathx.headingDir(self.facing);
        const swing = mathx.radians(lerpF(BLINK_TURN_MIN, BLINK_TURN_MAX, self.fxRng.float())) * self.orbitSign;
        const yaw = mathx.headingXZ(out) + swing;
        const dir = mathx.headingDir(yaw);
        self.blinkTo = v3(hero.x + dir.x * BLINK_R, self.pos.y, hero.z + dir.z * BLINK_R);
        self.orbitSign = -self.orbitSign;
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
        self.spookLeft = SPOOK_DUR;
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

    pub fn debugMove(self: *Shade, which: usize) void {
        self.atk = @min(which, MOVES.len - 1);
        self.enter(.wind);
    }
    pub fn debugBlink(self: *Shade, hero: rl.Vector3) void {
        self.blinkCd = 0;
        self.enterBlink(hero);
    }
    pub fn stagger(self: *Shade, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Shade) void {
        self.enterDeath();
    }



    fn rift(self: *Shade) void {
        const c = self.centerWorld();
        var i: i32 = 0;
        while (i < RIFT_N) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(1.6, 3.4) * self.scale;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(c.x, c.y + self.fxRng.range(-0.35, 0.45) * self.scale, c.z),
                .v = v3(mathx.cosf(a) * sp, self.fxRng.range(-0.4, 1.6), mathx.sinf(a) * sp),
                .life = self.fxRng.range(0.16, 0.30),
                .r0 = self.fxRng.range(0.032, 0.062) * self.scale,
                .r1 = 0.006,
                .col = if (self.fxRng.float() < 0.4) RIFT else WISP_COL,
                .grav = 1.2,
                .drag = 3.0,
                .stretch = 0.045,
                .add = true,
            });
        }
    }

    fn drainMotes(self: *Shade, hero: rl.Vector3) void {
        const to = self.centerWorld();
        var i: i32 = 0;
        while (i < DRAIN_N) : (i += 1) {
            const from = v3(
                hero.x + self.fxRng.range(-0.3, 0.3),
                hero.y + self.fxRng.range(0.5, 1.5),
                hero.z + self.fxRng.range(-0.3, 0.3),
            );
            const d = mathx.subV(to, from);
            const life = self.fxRng.range(0.22, 0.34);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = from,
                .v = mathx.scaleV(d, 1.0 / life),
                .life = life,
                .r0 = self.fxRng.range(0.026, 0.046),
                .r1 = 0.008,
                .col = DRAIN,
                .grav = -0.6,
                .stretch = 0.030,
                .add = true,
            });
        }
    }

    fn tornMotes(self: *Shade, at: rl.Vector3, dir: rl.Vector3) void {
        const parts = foe.hitParts(TORN_N);
        var i: i32 = 0;
        while (i < parts) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.5, 1.9);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = at,
                .v = v3(dir.x * sp + mathx.cosf(a) * 0.7, self.fxRng.range(0.3, 1.8), dir.z * sp + mathx.sinf(a) * 0.7),
                .life = self.fxRng.range(0.26, 0.46),
                .r0 = self.fxRng.range(0.04, 0.085) * self.scale,
                .r1 = 0.01,
                .col = WISP_DK,
                .grav = 2.4,
                .drag = 2.0,
            });
        }
    }

    fn unravel(self: *Shade) void {
        const c = self.centerWorld();
        var i: i32 = 0;
        while (i < UNRAVEL_N) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.4, 2.2) * self.scale;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(c.x, c.y + self.fxRng.range(-0.7, 0.6) * self.scale, c.z),
                .v = v3(mathx.cosf(a) * sp, self.fxRng.range(0.2, 2.4), mathx.sinf(a) * sp),
                .life = self.fxRng.range(0.5, 1.05),
                .r0 = self.fxRng.range(0.07, 0.15) * self.scale,
                .r1 = 0.01,
                .col = if (self.fxRng.float() < 0.3) foe.MOTE else WISP_COL,
                .grav = 1.1,
                .drag = 1.6,
                .add = true,
            });
        }
    }

    pub fn drawFx(self: *const Shade) void {
        foe.drawParticles(&self.parts);
    }
    pub fn draw(self: *const Shade, model: *const Model) void {
        model.draw(self);
    }


    fn trailHem(self: *Shade, was: rl.Vector3, dt: f32) void {
        const step = mathx.subV(self.pos, was);
        const want = if (dt > 1e-5) mathx.scaleV(v3(step.x, 0, step.z), 1.0 / dt) else mathx.zero3;
        self.hemVel = mathx.approachV(self.hemVel, want, HEM_LAG_RATE * dt * DRIFT_SPEED);
    }

    pub fn pose(self: *Shade) void {
        const fs = self.scale * (1.0 - 0.82 * self.thin);
        const facingDeg = mathx.degrees(self.facing);
        const bob = IDLE_BOB * mathx.sinf(self.elapsed * BOB_HZ * (1.0 + 0.16 * (self.seed - 0.5)) * std.math.tau + self.seed * 6.28);
        const sink = if (self.state == .dead) foe.rigSink(0.30, self.scale, self.thin) else 0;
        const leanDeg = mathx.clampF(self.lean, -LEAN_MAX, LEAN_MAX);

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul(
            tr(0, (CORE_Y + bob) * fs + HOVER * self.scale + sink, 0),
            mul(ry(facingDeg), tr(self.pos.x, self.pos.y, self.pos.z)),
        ));

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

    fn poseArm(self: *Shade, wx: *[N]rl.Matrix, sh: usize, el: usize, wr: usize, side: f32) void {
        const r = self.reach;
        const out = mathx.maxF(r, 0);
        const furl = mathx.maxF(-r, 0);
        const shX = lerpF(20.0, -74.0, out) + 16.0 * furl + 6.0 * self.gather;
        const shZ = side * (lerpF(30.0, 11.0, out) + 34.0 * furl);
        const elX = lerpF(52.0, 9.0, out) + 30.0 * furl - 18.0 * self.gather;
        const stretch = 1.0 + 0.85 * out;
        wx[sh] = placeAt(REST[sh], mul(scaleM(1, stretch, 1), mul(rx(shX), rz(shZ))), wx[TORSO]);
        wx[el] = placeAt(REST[el], rx(elX), wx[sh]);
        wx[wr] = placeAt(REST[wr], mul(scaleM(1, 1.0 / stretch, 1), rz(side * -12.0 * out)), wx[el]);
    }

    fn poseHem(self: *Shade, wx: *[N]rl.Matrix) void {
        const velX = mathx.clampF(self.hemVel.x, -1.4, 1.4);
        const velZ = mathx.clampF(self.hemVel.z, -1.4, 1.4);
        const c = mathx.cosf(-self.facing);
        const s = mathx.sinf(-self.facing);
        const localX = velX * c + velZ * s;
        const localZ = -velX * s + velZ * c;
        const speed = @sqrt(localX * localX + localZ * localZ);
        for (0..HEM_N) |i| {
            const b = HEM_0 + i;
            const fi: f32 = @floatFromInt(i);
            const a = std.math.tau * fi / HEM_N;
            // Its own outward bearing on the ring, ellipse and all (`REST` uses the same 0.86 on Z).
            const outX = mathx.cosf(a);
            const outZ = mathx.sinf(a) * 0.86;
            const facingWind = if (speed > 1e-4) (outX * localX + outZ * localZ) / speed else 0;
            const gain = lerpF(1.0, HEM_LEE, 0.5 + 0.5 * facingWind);
            const phase = self.elapsed * (0.79 + 0.13 * fi) + self.seed * 5.0 + fi * 1.7;
            const wobble = mathx.sinf(phase) * HEM_WOBBLE;
            wx[b] = placeAt(REST[b], mul(
                rx(gain * localZ * HEM_SWING + wobble),
                rz(-gain * localX * HEM_SWING + mathx.cosf(phase * 0.7) * HEM_WOBBLE * 0.6),
            ), wx[ROOT]);
        }
    }
};

const CAP = wf.MAX_PER_KIND;

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
        foe.resetRoles(Shade, Role, &self.shades, &self.n, m, roleOf);
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
                .grasp => |h| foe.worseBlow(&blow, h, s.pos, &s.threat),
            }
        }
        return blow;
    }

    pub fn setParry(self: *Haunt, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    pub fn anyParried(self: *const Haunt) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn pierce(self: *Haunt, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Haunt) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Haunt) u32 {
        return foe.soulsEach(self.liveConst());
    }
    pub fn totalHits(self: *const Haunt) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Haunt) u32 {
        return foe.aliveCount(self.liveConst());
    }
};


fn buildMeshes(pal: Pal) [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = emptyMesh(pal);
    mesh[TORSO] = shroudMesh(pal);
    mesh[COWL] = cowlMesh(pal);
    mesh[SHL] = armMesh(pal, 311);
    mesh[ELL] = forearmMesh(pal, 312);
    mesh[WRL] = handMesh(pal, 1.0, 313);
    mesh[SHR] = armMesh(pal, 314);
    mesh[ELR] = forearmMesh(pal, 315);
    mesh[WRR] = handMesh(pal, -1.0, 316);
    const len = [HEM_N]f32{ 0.40, 0.29, 0.43, 0.34, 0.38, 0.26, 0.42, 0.31 };
    for (0..HEM_N) |i| {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / HEM_N;
        mesh[HEM_0 + i] = tatterMesh(pal, len[i], a, 321 + @as(u64, i));
    }
    return mesh;
}

fn emptyMesh(pal: Pal) rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addBlob(v3(0, 0, 0), v3(0.004, 0.004, 0.004), 3, 4, pal.shroudDk);
    return b.toMesh();
}

const PROF = [_][2]f32{
    .{ 0.250, 0.084 },
    .{ 0.208, 0.128 },
    .{ 0.108, 0.112 },
    .{ 0.006, 0.080 },
};
const HEM_FLARE: f32 = 0.150;
const HEM_DOME_Y: f32 = -0.078;

fn shroudMesh(pal: Pal) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4409);
    b.setMat(.cloth);
    var i: usize = 0;
    while (i + 1 < PROF.len) : (i += 1) {
        b.addCapsule(
            v3(rng.range(-0.006, 0.006) * H, PROF[i][0] * H, rng.range(-0.005, 0.005) * H),
            v3(rng.range(-0.006, 0.006) * H, PROF[i + 1][0] * H, rng.range(-0.005, 0.005) * H),
            PROF[i][1] * H,
            PROF[i + 1][1] * H,
            13,
            pal.shroud,
        );
    }
    b.addBlob(v3(0, HEM_DOME_Y * H, 0), v3(HEM_FLARE * H, 0.098 * H, HEM_FLARE * H * 0.86), 6, 13, pal.shroud);
    var f: usize = 0;
    while (f < 10) : (f += 1) {
        const a = rng.range(0, std.math.tau);
        const y0 = rng.range(0.055, 0.185) * H;
        const y1 = mathx.maxF(y0 - rng.range(0.09, 0.20) * H, PROF[PROF.len - 1][0] * H + 0.004 * H);
        const cx = mathx.cosf(a);
        const cz = mathx.sinf(a) * 0.86;
        const r0 = 0.96 * shroudHalf(y0 / H) * H;
        const r1 = 0.96 * shroudHalf(y1 / H) * H;
        b.addCapsule(
            v3(cx * r0, y0, cz * r0),
            v3(cx * r1, y1, cz * r1),
            0.0080 * H * rng.range(0.8, 1.25),
            0.0055 * H,
            5,
            if (rng.float() < 0.5) pal.shroudLt else pal.shroudDk,
        );
    }
    b.addBlob(v3(0, 0.244 * H, -0.006 * H), v3(0.080 * H, 0.036 * H, 0.072 * H), 5, 11, pal.shroudLt);
    return b.toMesh();
}

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

fn cowlMesh(pal: Pal) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(9127);
    b.setMat(.cloth);
    b.addBlob(v3(0, 0.055 * H, -0.010 * H), v3(0.083 * H, 0.098 * H, 0.086 * H), 5, 10, pal.shroud);
    b.addBlob(v3(rng.range(-0.006, 0.006) * H, 0.118 * H, -0.030 * H), v3(0.050 * H, 0.052 * H, 0.048 * H), 4, 8, pal.shroudLt);
    b.addBlob(v3(0, 0.010 * H, -0.056 * H), v3(0.072 * H, 0.070 * H, 0.048 * H), 4, 8, pal.shroudDk);
    b.addBlob(v3(0, 0.048 * H, 0.052 * H), v3(0.056 * H, 0.062 * H, 0.048 * H), 5, 9, pal.hollow);
    b.setMat(.plain);
    for ([_]f32{ 1, -1 }) |side| {
        const ex = side * 0.024 * H * rng.range(0.92, 1.08);
        const ey = (0.052 + rng.range(-0.006, 0.006)) * H;
        b.addBlob(v3(ex, ey, 0.092 * H), v3(0.0125 * H, 0.0165 * H, 0.011 * H), 4, 8, pal.eye);
        b.addBlob(v3(ex, ey, 0.100 * H), v3(0.0058 * H, 0.0080 * H, 0.005 * H), 3, 7, pal.eyeCore);
    }
    return b.toMesh();
}

fn armMesh(pal: Pal, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.cloth);
    b.addCapsule(
        v3(0, 0.012 * H, 0),
        v3(rng.range(-0.008, 0.008) * H, -0.152 * H, rng.range(-0.006, 0.006) * H),
        0.038 * H * rng.range(0.94, 1.06),
        0.028 * H,
        8,
        pal.limb,
    );
    b.addBlob(v3(0, -0.030 * H, -0.010 * H), v3(0.046 * H, 0.055 * H, 0.040 * H), 4, 8, pal.shroudDk);
    return b.toMesh();
}

fn forearmMesh(pal: Pal, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.cloth);
    b.addCapsule(
        v3(0, 0.010 * H, 0),
        v3(rng.range(-0.007, 0.007) * H, -0.140 * H, rng.range(-0.005, 0.005) * H),
        0.028 * H * rng.range(0.94, 1.06),
        0.020 * H,
        7,
        pal.limbDk,
    );
    return b.toMesh();
}

fn handMesh(pal: Pal, side: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.cloth);
    b.addBlob(v3(0, -0.012 * H, 0.004 * H), v3(0.026 * H, 0.024 * H, 0.020 * H), 4, 8, pal.limb);
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const fi: f32 = @floatFromInt(i);
        const spread = (fi - 1.0) * 0.020 * H * side;
        const knuckle = v3(spread, -0.030 * H, 0.010 * H);
        const mid = v3(spread * 1.5, -0.058 * H * rng.range(0.85, 1.1), 0.030 * H);
        const tip = v3(spread * 1.7, -0.062 * H, 0.056 * H);
        b.addCapsule(knuckle, mid, 0.0090 * H, 0.0074 * H, 5, pal.limbDk);
        b.addCapsule(mid, tip, 0.0074 * H, 0.0068 * H, 5, pal.limbDk);
        b.addBlob(tip, v3(0.0072 * H, 0.0072 * H, 0.0072 * H), 3, 6, pal.limb);
    }
    return b.toMesh();
}

fn tatterMesh(pal: Pal, len: f32, ang: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.cloth);
    const tan = v3(-mathx.sinf(ang), 0, mathx.cosf(ang));
    const rad = v3(mathx.cosf(ang), 0, mathx.sinf(ang));
    const SEGS = 4;
    const curlX = rng.range(-0.05, 0.05);
    const curlZ = rng.range(-0.04, 0.04);
    const segLen = len * H / SEGS;
    const THICK = 0.0055 * H;
    var p = v3(0, 0, 0);
    var hw = 0.058 * H * rng.range(0.88, 1.12);
    var i: i32 = 0;
    while (i < SEGS) : (i += 1) {
        const fi: f32 = @floatFromInt(i + 1);
        const q = v3(
            curlX * segLen * fi * fi * 0.5,
            -segLen * fi,
            curlZ * segLen * fi * fi * 0.5,
        );
        const hw1 = hw * rng.range(0.74, 0.88);
        const mid = mathx.lerpV(p, q, 0.5);
        const half = mathx.scaleV(mathx.subV(q, p), 0.5);
        const w = (hw + hw1) * 0.5;
        b.addBox(mid, mathx.scaleV(tan, w), half, mathx.scaleV(rad, THICK), pal.shroud);
        p = q;
        hw = hw1;
    }
    b.addBlob(p, v3(hw * 0.9, THICK * 2.2, hw * 0.9), 3, 7, pal.shroudLt);
    return b.toMesh();
}

pub fn wispMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plain);
    b.addBlob(mathx.zero3, v3(0.080, 0.080, 0.180), 7, 11, mathx.withAlpha(WISP_DK, 120));
    b.addBlob(v3(0, 0, 0.022), v3(0.042, 0.042, 0.100), 6, 9, mathx.withAlpha(WISP_COL, 45));
    return b.toModel(shader);
}


test "the rig's tables are the rig's size, and the tatters are the tail of it" {
    try std.testing.expectEqual(@as(usize, N), REST.len);
    try std.testing.expectEqual(@as(usize, N), HEM_0 + HEM_N);
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
    try std.testing.expect(MOVES[WISP].minR > MOVES[GRASP].maxR);
}

test "the bands decide the move, and a spent cooldown never buys a free one" {
    try std.testing.expectEqual(Choice.hold, classify(AGGRO_R + 1, true, true));
    try std.testing.expectEqual(Choice.grasp, classify(1.0, true, true));
    try std.testing.expectEqual(Choice.circle, classify(1.0, false, true));
    try std.testing.expectEqual(Choice.wisp, classify(7.0, true, true));
    try std.testing.expectEqual(Choice.close, classify(7.0, true, false));
    try std.testing.expectEqual(Choice.circle, classify(MOVES[GRASP].maxR + 0.3, false, false));
    try std.testing.expectEqual(Choice.close, classify(MOVES[WISP].maxR + 2.0, true, true));
}

test "THE BLINK: threatened or wounded, never mid-swing, and never while the roots have it" {
    try std.testing.expect(wantsBlink(1.0, 0, false, .circle, false));
    try std.testing.expect(!wantsBlink(9.0, 0, false, .circle, false));
    try std.testing.expect(wantsBlink(9.0, 0, true, .circle, false));
    try std.testing.expect(!wantsBlink(1.0, 0.5, true, .circle, false));
    try std.testing.expect(!wantsBlink(1.0, 0, true, .circle, true));
    try std.testing.expect(!wantsBlink(1.0, 0, true, .strike, false));
    try std.testing.expect(!wantsBlink(1.0, 0, true, .wind, false));
    try std.testing.expect(!wantsBlink(1.0, 0, true, .stunheavy, false));
    try std.testing.expect(!wantsBlink(1.0, 0, true, .dead, false));
}

test "THE TOUCH TAKES THE BLUE BAR AND THE WISP DOES NOT, and neither one is dearer than a heavy" {
    try std.testing.expect(GRASP_HIT.fp > 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), WISP_HIT.fp, 1e-6);
    try std.testing.expect(WISP_HIT.dmg > GRASP_HIT.dmg * 2.0);
    try std.testing.expectApproxEqAbs(GRASP_HIT.dmg, GRASP_HIT.raw(), 1e-6);
    try std.testing.expect(GRASP_HIT.fp * 2.0 < combat.FP_MAX);
    try std.testing.expect(GRASP_HIT.fp * 5.0 > combat.FP_MAX);
}

test "it blinks to a bearing swung round from where it stands, at the hero's own range" {
    var s = Shade.spawn(v3(0, 0, 3), 0, 1.0, 0.3);
    const hero = mathx.zero3;
    s.debugBlink(hero);
    try std.testing.expectEqual(State.blinkout, s.state);
    try std.testing.expectApproxEqAbs(BLINK_R, mathx.distXZ(s.blinkTo, hero), 1e-3);
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
        try std.testing.expect(s.airborne());
    }
    // MEASURED THE FRAME IT LANDS: the moment it is down it starts orbiting again, and a couple of centimetres of that is not the jump missing its mark.
    while (s.airborne() and t < 2.0) : (t += 1.0 / 60.0) _ = s.update(1.0 / 60.0, hero, 400, .{});
    try std.testing.expectApproxEqAbs(want.x, s.pos.x, 1e-3);
    try std.testing.expectApproxEqAbs(want.z, s.pos.z, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.thin, 1e-5);
}

test "a hit spooks it, a stagger holds it there, and the punish window is not teleported out of" {
    var s = Shade.spawn(v3(0, 0, 2), 0, 1.0, 0.3);
    const hero = mathx.zero3;
    s.stagger(true);
    s.spookLeft = SPOOK_DUR;
    var t: f32 = 0;
    while (t < combat.FOE_HEAVY_STUN_DUR - 0.05) : (t += 1.0 / 60.0) {
        _ = s.update(1.0 / 60.0, hero, 400, .{});
        try std.testing.expect(s.state == .stunheavy);
    }
    while (t < combat.FOE_HEAVY_STUN_DUR + 0.10) : (t += 1.0 / 60.0) _ = s.update(1.0 / 60.0, hero, 400, .{});
    try std.testing.expect(s.state == .blinkout or s.state == .blinkin);
}

test "ONE BLOW BUYS ONE BLINK, not every blink for the rest of the map" {
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
        try std.testing.expect(mathx.lenXZ(s.hemVel) < 0.1);
    }
    try std.testing.expect(t < 1.0);
}

test "THE ARMS CLOSE IN FRONT OF IT: a hero at its back is not somebody it has hold of" {
    var s = Shade.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(s.holds(v3(0, 0, 1.2)));
    try std.testing.expect(!s.holds(v3(0, 0, -1.2)));
    try std.testing.expect(!s.holds(v3(0, 0, 9.0)));
    try std.testing.expect(GRASP_ARC > combat.GUARD_ARC);
    const edge = mathx.radians(GRASP_ARC - 3.0);
    try std.testing.expect(s.holds(v3(1.2 * mathx.sinf(edge), 0, 1.2 * mathx.cosf(edge))));
    const past = mathx.radians(GRASP_ARC + 3.0);
    try std.testing.expect(!s.holds(v3(1.2 * mathx.sinf(past), 0, 1.2 * mathx.cosf(past))));

    var back = Shade.spawn(mathx.zero3, 0, 1.0, 0.3);
    const behind = v3(0, 0, -1.2);
    back.facing = 0;
    back.debugMove(GRASP);
    var t: f32 = 0;
    while (t < MOVES[GRASP].windDur + MOVES[GRASP].strikeDur + 0.05) : (t += 1.0 / 60.0) {
        back.facing = 0;
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
    try std.testing.expect(from.y > s.pos.y + 0.5);
    try std.testing.expect(mathx.distXZ(from, s.pos) < 1.6);
}

test "THE UNRAVEL DOES NOT EAT ITSELF — a blink's rift is still up when the killing blow lands" {
    var s = Shade.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, 5);
    s.debugBlink(hero);
    var live: usize = 0;
    for (&s.parts) |*q| {
        if (q.life > 0) live += 1;
    }
    try std.testing.expectEqual(@as(usize, RIFT_N), live);

    const cut = foe.Blade{
        .active = true,
        .r = 0.4,
        .a = mathx.addV(s.centerWorld(), v3(-1, 0, 0)),
        .b = mathx.addV(s.centerWorld(), v3(1, 0, 0)),
        .hit = .{ .dmg = 9999, .poise = 999, .stance = 40 }, // `stance` is what makes a blow HEAVY
    };
    s.tryHit(cut);
    try std.testing.expect(s.justDied);
    live = 0;
    for (&s.parts) |*q| {
        if (q.life > 0) live += 1;
    }
    std.debug.print("\n  shade death frame: {d} live motes in a {d}-slot ring\n", .{ live, PARTS });
    try std.testing.expectEqual(@as(usize, RIFT_N + @as(usize, @intCast(foe.hitParts(TORN_N))) + UNRAVEL_N + foe.WOUND_PARTS), live);
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
    try std.testing.expect(!s.justDied);
}

test "every world point is measured off the ground under it plus the hover" {
    var low = Shade.spawn(mathx.zero3, 0, 1.0, 0.3);
    var high = Shade.spawn(v3(0, 4.0, 0), 0, 1.0, 0.3);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), high.centerWorld().y - low.centerWorld().y, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), high.topWorld().y - low.topWorld().y, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), high.lockPoint().y - low.lockPoint().y, 1e-4);
    try std.testing.expect(low.topWorld().y > low.lockPoint().y);
    try std.testing.expect(low.lockPoint().y > low.centerWorld().y);
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
    var t: f32 = 0;
    while (t < 0.5) : (t += dt) {
        const was = s.pos;
        s.pos.z += DRIFT_SPEED * dt;
        s.trailHem(was, dt);
    }
    try std.testing.expect(s.hemVel.z > 0.5);
    const held = s.hemVel.z;
    s.trailHem(s.pos, dt);
    try std.testing.expect(s.hemVel.z < held and s.hemVel.z > 0);
    t = 0;
    while (t < 2.0) : (t += dt) s.trailHem(s.pos, dt);
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.hemVel.z, 1e-3);
}

test "a shade flying forward leaves its gown BEHIND it, and the trailing edge is the one that lifts" {
    var s = Shade.spawn(mathx.zero3, 0, 1.0, 0.3);
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < 0.6) : (t += dt) {
        const was = s.pos;
        s.pos.z += DRIFT_SPEED * dt;
        s.trailHem(was, dt);
    }
    s.pose();

    // Facing 0, so the shade's own forward IS world +Z and the tips can be read straight off the matrices.
    const TIP = v3(0, -0.33, 0);
    var lead: f32 = 0;
    var trail: f32 = 0;
    var pushed: usize = 0;
    for (0..HEM_N) |i| {
        const bone = s.xf[HEM_0 + i];
        const root = rl.math.vector3Transform(mathx.zero3, bone);
        const tip = rl.math.vector3Transform(TIP, bone);
        if (tip.z < root.z - 0.01) pushed += 1;
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / HEM_N;
        // The ring's own bearings: index 2 of 8 is +Z (the leading edge), index 6 is -Z (the trailing edge).
        if (mathx.sinf(a) > 0.9) lead = tip.y - root.y;
        if (mathx.sinf(a) < -0.9) trail = tip.y - root.y;
    }
    std.debug.print("\n  hem at {d:.2} m/s: {d}/{d} tatters downwind, leading tip {d:.3} m, trailing {d:.3} m\n", .{
        s.hemVel.z, pushed, HEM_N, lead, trail,
    });
    try std.testing.expectEqual(HEM_N, pushed);
    try std.testing.expect(trail > lead + 0.05);
    try std.testing.expect(lead < 0 and trail < 0);
}
