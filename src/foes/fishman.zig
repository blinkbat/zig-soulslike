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
const setLocal = heromod.setHumanoid;

// THE FISHMEN (owner's creature, owner's brief) — the dried lake's own people, stranded on the bed of the
// water they were born in. **THE SECOND WARBAND**, and it is a warband for a different reason than the
// kobolds are: theirs is held together by a priest keeping them alive, and this one by a NET.
//
// **THE THREE ARE ONE MOVE IN THREE PARTS.** The netter takes the hero's feet; the spearman drives a
// two-handed trident down the line he can no longer step out of; the shaman puts back what you took off all
// of them. Pull any one out and the other two are ordinary.
//
// **AND THE SHAMAN IS THE ANSWER, BUT THE NETTER IS WHAT KILLS YOU** — the lesson every player learns in the
// wrong order, which is the whole reason to build it this way.

pub const H: f32 = 1.74;
const HIP_HALF = heromod.HIP_HALF * 1.04;
const SHOULDER_HALF = heromod.SHOULDER_HALF * 0.98;
const REST = heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);

const N = heromod.N;
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
/// **THE ONE CREATURE HERE THAT USES BONE 17.** The trident, the net and the rattle are all HELD things, so
/// each role fills the weapon slot with its own mesh and `Model.draw` walks the whole rig.
const HELD = heromod.HELD;

const solePatches = [_]heromod.SolePatch{
    .{ .bone = ANKL, .heel = 0.046 * H, .toe = 0.196 * H, .halfW = 0.062 * H, .drop = 0.030 * H },
    .{ .bone = ANKR, .heel = 0.046 * H, .toe = 0.196 * H, .halfW = 0.062 * H, .drop = 0.030 * H },
};

const A_PROT: f32 = 4.0;

// Wet-looking on a dry lake: the scales keep a green-grey sheen the rest of the pan has lost, which is what
// makes them read as OUT OF PLACE rather than as part of the ground.
const SCALE = rgba(52, 66, 58, 255);
const SCALE_LT = rgba(78, 96, 82, 255);
const SCALE_DK = rgba(28, 38, 34, 255);
const BELLY = rgba(122, 126, 106, 255);
const FIN = rgba(96, 112, 108, 220);
const FIN_DK = rgba(46, 58, 56, 230);
const EYE = rgba(214, 206, 92, 255);
const EYE_RIM = rgba(16, 18, 16, 255);
const GILL = rgba(112, 44, 44, 255);
const BONE = rgba(150, 142, 120, 255);
const CORD = rgba(112, 104, 78, 255);
const SALT = rgba(214, 214, 204, 255);
const TOTEM = rgba(84, 62, 44, 255);

pub const Role = enum { spearman, netter, shaman };

const Spec = struct {
    hp: f32,
    poise: f32,
    stance: f32,
    speed: f32,
    bodyR: f32,
    hurtR: f32,
    souls: u32,
    /// The band it wants to stand in. The spearman wants his own reach, the netter wants his throw, and the
    /// shaman wants to be behind both of them.
    wantMin: f32,
    wantMax: f32,
};

const SPEC = [_]Spec{
    .{ .hp = 118, .poise = 16, .stance = 34, .speed = 1.12, .bodyR = 0.40, .hurtR = 0.60, .souls = 155, .wantMin = 0.0, .wantMax = 2.4 },
    .{ .hp = 88, .poise = 11, .stance = 26, .speed = 1.26, .bodyR = 0.38, .hurtR = 0.58, .souls = 175, .wantMin = 4.5, .wantMax = 8.5 },
    .{ .hp = 74, .poise = 10, .stance = 22, .speed = 0.92, .bodyR = 0.38, .hurtR = 0.58, .souls = 265, .wantMin = 8.0, .wantMax = 13.0 },
};

fn spec(r: Role) *const Spec {
    return &SPEC[@intFromEnum(r)];
}

comptime {
    if (SPEC.len != @typeInfo(Role).@"enum".fields.len) @compileError("fishman: a Role with no spec row");
    // A CONTIGUOUS RUN off `spearman` in role order — `roleOf`/`kindOf` are an ordinal shift, so a kind
    // inserted mid-run would silently post the wrong role with nothing failing to compile.
    for (@typeInfo(Role).@"enum".fields, 0..) |f, i| {
        const fk: wf.FoeKind = @enumFromInt(@intFromEnum(wf.FoeKind.fish_spearman) + i);
        if (!std.mem.eql(u8, f.name, @tagName(fk)[5..])) {
            @compileError("fishman: wf.FoeKind." ++ @tagName(fk) ++ " is not in the shoal's contiguous run");
        }
    }
    // **THE SHAMAN IS WORTH THE MOST AND IS THE SOFTEST**, which is the whole priority lesson written as a
    // pair of numbers rather than as a hint.
    std.debug.assert(SPEC[2].souls > SPEC[0].souls and SPEC[2].hp < SPEC[0].hp);
}

pub fn roleOf(k: wf.FoeKind) ?Role {
    const lo = @intFromEnum(wf.FoeKind.fish_spearman);
    const i = @intFromEnum(k);
    if (i < lo or i >= lo + SPEC.len) return null;
    return @enumFromInt(i - lo);
}

pub fn kindOf(r: Role) wf.FoeKind {
    return @enumFromInt(@intFromEnum(wf.FoeKind.fish_spearman) + @intFromEnum(r));
}

pub const AGGRO_R: f32 = 16.0;
const HOME_R: f32 = 2.0;
const TURN_RATE: f32 = 3.6;
const ACCEL: f32 = 4.0;
const WALK_BASE: f32 = heromod.WALK_SPEED;

const CENTER_F: f32 = 0.56;
const TOP_F: f32 = 1.02;

/// Amphibian on a salt pan: the water is gone and the cold went with it.
const RESISTS = combat.resists(.{ .cold = -40, .lightning = -30, .fire = 20, .chaos = 25 });

// **THE TRIDENT.** Two-handed, both hands on the shaft, and it THRUSTS — the longest melee reach any common
// body has, paid for with the slowest recovery.
const THRUST_R: f32 = 2.70;
const THRUST_FRONT_DOT: f32 = 0.62;
const THRUST_WIND: f32 = 0.52;
const THRUST_STRIKE: f32 = 0.16;
const THRUST_RECOVER: f32 = 0.86;
const THRUST_CD: f32 = 2.6;
pub const THRUST_HIT = combat.Hit{ .dmg = 20, .poise = 16, .stance = 12 };

// **THE NET.** Almost no damage. What it does is take his FEET, and everything else in the band is priced
// against that.
const NET_R: f32 = 8.5;
const NET_MIN: f32 = 2.2;
const NET_WIND: f32 = 0.58;
const NET_RECOVER: f32 = 0.74;
const NET_CD: f32 = 7.5;
const NET_SPEED: f32 = 12.0;
const NET_HIT_R: f32 = 0.95;
/// **ONE GRAVITY FOR THE SOLVE AND THE FLIGHT.** `loose` solves the lob against it and `Net.step` integrates
/// with it; two spellings drift and the net quietly stops landing where it was aimed.
const NET_GRAV: f32 = 6.0;
/// Seconds of held feet. Priced against the trident: one net has to be long enough for a spearman to WIND
/// and land one thrust, and no longer — being netted through two of them is a death with no decision in it.
pub const NET_HOLD: f32 = 1.35;
pub const NET_HIT = combat.Hit{ .dmg = 4, .poise = 6 };

// **THE RATTLE.** No blow at all. It puts health back on everything in the band including itself, which is
// what makes killing it first the answer and killing it last the mistake.
const RITE_WIND: f32 = 0.68;
const RITE_DUR: f32 = 0.55;
const RITE_RECOVER: f32 = 0.80;
const RITE_CD: f32 = 9.0;
const RITE_RANGE: f32 = 14.0;
/// Off each body's OWN maximum, so it is worth the same to a spearman as to a netter.
pub const RITE_HEAL_FRAC: f32 = 0.22;
/// It will not spend the rite on scratches.
const RITE_SLACK: f32 = 0.80;

comptime {
    std.debug.assert(THRUST_WIND >= foe.TELL_MIN);
    std.debug.assert(NET_WIND >= foe.TELL_MIN);
    std.debug.assert(RITE_WIND >= foe.TELL_MIN);
    // **THE NET BUYS EXACTLY ONE THRUST.** Long enough to wind and land one, short enough that the second
    // never arrives inside the same hold.
    std.debug.assert(NET_HOLD > THRUST_WIND + THRUST_STRIKE);
    std.debug.assert(NET_HOLD < THRUST_WIND + THRUST_STRIKE + THRUST_RECOVER);
    // The netter must not be able to stand where the spear cannot reach him back.
    std.debug.assert(SPEC[1].wantMin > THRUST_R);
}

const DEATH_DUR: f32 = 1.05;
const DISS_DUR: f32 = 0.9;
const SHOVE_DECAY: f32 = 7.5;
const DISSOLVE = foe.Dissolve{ .rate = 42.0, .spread = 0.5, .rise = 0.7, .flake = SALT };

const HIT_SPRAY_LIGHT = 5;
const HIT_SPRAY_HEAVY = 11;
const RITE_MOTES: u32 = 26;
const PARTS = 64;
comptime {
    std.debug.assert(@as(f32, PARTS) >= @as(f32, @floatFromInt(RITE_MOTES + foe.hitParts(HIT_SPRAY_HEAVY) + foe.WOUND_PARTS)));
}

const State = enum { idle, walk, thrust, cast, rite, stunlight, stunheavy, dead };

const Choice = enum { rest, hold, close, back, thrust, net, rite };

/// Pure over one situation, so every role's pick is testable without a body on a field.
fn classify(role: Role, gap: f32, sensed: f32, homeGap: f32, ready: bool, wounded: bool, rooted: bool) Choice {
    if (sensed > AGGRO_R) return if (homeGap > HOME_R) .hold else .rest;
    const s = spec(role);
    switch (role) {
        .spearman => if (gap <= THRUST_R and ready) return .thrust,
        .netter => if (ready and gap <= NET_R and gap >= NET_MIN) return .net,
        .shaman => if (ready and wounded) return .rite,
    }
    if (rooted) return .rest;
    if (sensed < s.wantMin) return .back;
    if (sensed > s.wantMax) return .close;
    return .rest;
}

/// A net in the air. It has TRAVEL, so the throw is dodgeable sideways and not just outrun — the one thing
/// that keeps a 1.35 s hold from being a coin toss.
pub const Net = struct {
    at: rl.Vector3 = mathx.zero3,
    vel: rl.Vector3 = mathx.zero3,
    live: bool = false,
    t: f32 = 0,
    spin: f32 = 0,

    pub fn step(self: *Net, dt: f32, target: rl.Vector3) bool {
        if (!self.live) return false;
        self.t += dt;
        self.spin += dt * 5.0;
        self.at = v3(self.at.x + self.vel.x * dt, self.at.y + self.vel.y * dt, self.at.z + self.vel.z * dt);
        self.vel.y -= NET_GRAV * dt;
        if (self.at.y <= 0.05 or self.t > 2.0) {
            self.live = false;
            return false;
        }
        if (mathx.distXZ(self.at, target) <= NET_HIT_R and @abs(self.at.y - (target.y + 0.9)) < 1.4) {
            self.live = false;
            return true;
        }
        return false;
    }
};

pub const Model = struct {
    bone: [N]rl.Mesh,
    /// Per-role heads and held things. The BODY is one mesh set for all three — they are one people.
    head: [SPEC.len]rl.Mesh,
    hand: [SPEC.len]rl.Mesh,
    net: rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        // **THE TWO PER-ROLE SLOTS ARE FILLED FROM THE ROLE TABLES, NOT BUILT TWICE.** `bone[SKULL]` and
        // `bone[HELD]` are never drawn — `draw` reaches into `head`/`hand` for those — so building them a
        // second time inside `buildBones` uploaded two meshes nothing would ever reference.
        const head = [SPEC.len]rl.Mesh{ headMesh(.spearman), headMesh(.netter), headMesh(.shaman) };
        const hand = [SPEC.len]rl.Mesh{ tridentMesh(), netBundleMesh(), rattleMesh() };
        var bone = buildBones();
        bone[SKULL] = head[0];
        bone[HELD] = hand[0];
        return .{
            .bone = bone,
            .head = head,
            .hand = hand,
            .net = netFlightMesh(),
            .mat = gfx.material(shader, "fishman"),
        };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, f: *const Fishman) void {
        const r = @intFromEnum(f.role);
        for (0..SKULL) |i| rl.drawMesh(self.bone[i], self.mat, f.xf[i]);
        rl.drawMesh(self.head[r], self.mat, f.xf[SKULL]);
        for (SKULL + 1..HELD) |i| rl.drawMesh(self.bone[i], self.mat, f.xf[i]);
        // The netter's bundle goes with the net: once it is in the air his hand is empty.
        if (!(f.role == .netter and f.net.live)) rl.drawMesh(self.hand[r], self.mat, f.xf[HELD]);
        if (f.net.live) rl.drawMesh(self.net, self.mat, f.netMat());
    }
};

pub const Fishman = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},

    role: Role = .spearman,
    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    cd: f32 = 0,
    speed: f32 = 0,

    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,

    net: Net = .{},
    /// One-frame edges the group reads after `update`.
    threw: bool = false,
    rang: bool = false,
    /// One-frame: the net closed on the hero this frame, and for how long it holds him.
    snared: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(1, 1, 1),
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
    rest: [N]rl.Vector3 = REST,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Fishman {
        return spawnAs(.spearman, home, faceYaw, scale, seed);
    }

    pub fn spawnAs(role: Role, home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Fishman {
        const s = spec(role);
        var f = Fishman{ .pos = home, .home = home, .facing = faceYaw, .scale = scale, .seed = seed, .role = role };
        f.vit = combat.Vitals.initFoe(s.hp, s.poise, s.stance).withRes(RESISTS);
        f.fxRng = foe.fxStream(seed, 47713.0, 0xF15A);
        f.aiRng = foe.fxStream(seed, 33301.0, 19);
        f.cd = seed * 1.2;
        f.pose();
        return f;
    }

    pub fn kind(self: *const Fishman) wf.FoeKind {
        return kindOf(self.role);
    }
    pub fn soulValue(self: *const Fishman) u32 {
        return spec(self.role).souls;
    }

    pub fn centerWorld(self: *const Fishman) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H, self.scale, 0);
    }
    pub fn lockPoint(self: *const Fishman) rl.Vector3 {
        return foe.markOn(self.xf[CHEST], v3(0, 0.03 * H, 0));
    }
    pub fn topWorld(self: *const Fishman) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * H, self.scale, 0);
    }
    pub fn hurtRadius(self: *const Fishman) f32 {
        return spec(self.role).hurtR * self.scale;
    }
    pub fn bodyR(self: *const Fishman) f32 {
        return spec(self.role).bodyR * self.scale;
    }
    pub fn alive(self: *const Fishman) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Fishman) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Fishman) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn airborne(_: *const Fishman) bool {
        return false;
    }
    pub fn flashFrac(self: *const Fishman) f32 {
        return foe.flashFrac(self.flash);
    }

    pub fn navWant(self: *const Fishman, quarry: rl.Vector3) ?rl.Vector3 {
        if (self.state != .idle and self.state != .walk) return null;
        if (foe.senseHero(&self.leash, self.pos, quarry, AGGRO_R) <= AGGRO_R) return quarry;
        return if (mathx.distXZ(self.pos, self.home) > HOME_R) self.home else null;
    }

    fn faceToward(self: *Fishman, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }

    /// -1 gathered, +1 driven through, easing home across the recovery. One shape for all three roles' one
    /// move, so the tell reads the same whichever of them is doing it.
    fn actAmt(self: *const Fishman, wind: f32, strike: f32, recover: f32) f32 {
        if (self.t < wind) return -mathx.smoothstep(0, wind * 0.92, self.t);
        const s = self.t - wind;
        if (s < strike) return lerpF(-1.0, 1.0, foe.swingCurve(s / strike));
        return 1.0 - mathx.smoothstep(strike, strike + recover * 0.7, s);
    }

    fn moveAmt(self: *const Fishman) f32 {
        return switch (self.state) {
            .thrust => self.actAmt(THRUST_WIND, THRUST_STRIKE, THRUST_RECOVER),
            .cast => self.actAmt(NET_WIND, 0.10, NET_RECOVER),
            .rite => self.actAmt(RITE_WIND, RITE_DUR, RITE_RECOVER),
            else => 0,
        };
    }

    fn stunAmount(self: *const Fishman) f32 {
        if (self.state != .stunlight and self.state != .stunheavy) return 0;
        return foe.stunCurve(self.t, self.state == .stunheavy);
    }

    pub fn netMat(self: *const Fishman) rl.Matrix {
        const s = self.scale;
        return mul3(
            mul(scaleM(s, s, s), rx(mathx.degrees(self.net.spin))),
            ry(mathx.degrees(self.net.spin * 0.7)),
            tr(self.net.at.x, self.net.at.y, self.net.at.z),
        );
    }

    /// `bandHurt` is what the group has seen of its own health — the shaman reads the field, it never walks
    /// the band itself (`foe.zig`'s cross-cutting-state law).
    pub fn update(self: *Fishman, dt: f32, quarry: rl.Vector3, bounds: f32, blade: foe.Blade, bandHurt: bool) ?combat.Hit {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.heroHit = null;
        self.threw = false;
        self.rang = false;
        self.snared = 0;
        self.justDied = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.vit.tick(dt);
        self.elapsed += dt;
        self.t += dt;
        self.cd = mathx.maxF(0, self.cd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, self.home, quarry, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        // **THE NET FLIES ON ITS OWN CLOCK**, outliving the throw and even the thrower: a body cut down mid-
        // throw has already let go, and the net in the air is not his any more.
        if (self.net.step(dt, quarry)) self.snared = NET_HOLD;

        var movedDist: f32 = 0;
        var moveSpeed: f32 = 0;
        var moveYaw: ?f32 = null;

        switch (self.state) {
            .dead => {
                self.speed = 0;
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
            .stunlight, .stunheavy => {
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                if (self.t >= combat.foeStunDur(self.state == .stunheavy)) self.enter(.idle);
            },
            .thrust => {
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                if (self.t < THRUST_WIND) self.faceToward(quarry, dt);
                const s = self.t - THRUST_WIND;
                if (s >= 0 and s < THRUST_STRIKE) self.tryThrust(quarry);
                if (self.t >= THRUST_WIND + THRUST_STRIKE + THRUST_RECOVER) {
                    self.heroLatch = false;
                    self.enter(.idle);
                }
            },
            .cast => {
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                if (self.t < NET_WIND) self.faceToward(quarry, dt);
                if (self.t >= NET_WIND and (self.t - dt) < NET_WIND) self.loose(quarry);
                if (self.t >= NET_WIND + NET_RECOVER) self.enter(.idle);
            },
            .rite => {
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                if (self.t >= RITE_WIND and (self.t - dt) < RITE_WIND) {
                    self.rang = true;
                    self.riteMotes();
                    sfx.world(.priest_call, self.pos);
                }
                if (self.t >= RITE_WIND + RITE_DUR + RITE_RECOVER) self.enter(.idle);
            },
            .idle, .walk => {
                const sensed = foe.senseHero(&self.leash, self.pos, quarry, AGGRO_R);
                const gap = mathx.maxF(0, sensed - foe.HERO_R - self.bodyR());
                const homeGap = mathx.distXZ(self.pos, self.home);
                switch (classify(self.role, gap, sensed, homeGap, self.cd <= 0, bandHurt, self.root.held())) {
                    .rest => {
                        if (sensed <= AGGRO_R) self.faceToward(quarry, dt);
                        self.speed = approach(self.speed, 0, ACCEL * dt);
                        self.state = .idle;
                    },
                    .thrust => {
                        self.cd = THRUST_CD * self.aiRng.range(0.85, 1.25);
                        self.heroLatch = false;
                        self.enter(.thrust);
                    },
                    .net => {
                        self.cd = NET_CD * self.aiRng.range(0.9, 1.25);
                        self.enter(.cast);
                    },
                    .rite => {
                        self.cd = RITE_CD * self.aiRng.range(0.9, 1.2);
                        self.enter(.rite);
                    },
                    .hold, .close, .back => |ch| {
                        const want = spec(self.role).speed * WALK_BASE;
                        const to = if (ch == .hold) self.home else quarry;
                        self.faceToward(self.nav.aim(self.pos, to), dt);
                        self.speed = approach(self.speed, want, ACCEL * dt);
                        moveSpeed = self.speed;
                        const moved = moveSpeed * dt * self.chill.travel();
                        // **BACKING OFF IS WALKING BACKWARDS, NOT TURNING ROUND** — a shaman that turns its
                        // back to reposition is a shaman you cannot read, and the gait channel already knows
                        // how to walk a body in a direction it is not facing.
                        const face = self.nav.along(mathx.headingDir(self.facing));
                        const way = if (ch == .back) v3(-face.x, 0, -face.z) else face;
                        mathx.stepXZ(&self.pos, way, moved, bounds);
                        movedDist = moved;
                        moveYaw = mathx.headingXZ(way);
                        self.state = .walk;
                    },
                }
            },
        }

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        self.pose();
        self.tryHit(blade);
        return self.heroHit;
    }

    fn tryThrust(self: *Fishman, quarry: rl.Vector3) void {
        if (self.heroLatch) return;
        if (!foe.inFront(self.pos, self.facing, quarry, foe.hurtReach(THRUST_R, self.scale), THRUST_FRONT_DOT)) return;
        self.heroHit = THRUST_HIT;
        self.heroLatch = true;
        self.leash.noteCombat();
    }

    fn loose(self: *Fishman, quarry: rl.Vector3) void {
        const from = foe.markOn(self.xf[HELD], mathx.zero3);
        const to = v3(quarry.x, quarry.y + 0.9, quarry.z);
        const d = mathx.subV(to, from);
        const flat = mathx.lenXZ(d);
        const tof = mathx.maxF(0.05, flat / NET_SPEED);
        self.net = .{
            .at = from,
            // Solved for the arc rather than aimed flat: the lob is what makes the throw readable in the air.
            .vel = v3(d.x / tof, d.y / tof + 0.5 * NET_GRAV * tof, d.z / tof),
            .live = true,
        };
        self.threw = true;
        self.leash.noteCombat();
        sfx.world(.shroom_fling, self.pos);
    }

    pub fn tryHit(self: *Fishman, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        const heavy = foe.wounded(self, s, blade, .{ .light = 0.75, .heavy = 1.45 });
        self.spray(s.contact, s.dir, foe.hitParts(if (heavy) HIT_SPRAY_HEAVY else HIT_SPRAY_LIGHT));
        sfx.world(.lurker_hurt, self.pos);
        switch (s.reaction) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn enter(self: *Fishman, s: State) void {
        self.state = s;
        self.t = 0;
    }
    fn enterStun(self: *Fishman, s: State) void {
        self.heroLatch = false;
        self.enter(s);
    }
    fn enterDeath(self: *Fishman) void {
        if (self.state == .dead) return;
        self.heroLatch = false;
        self.enter(.dead);
        self.justDied = true;
        sfx.world(.lurker_die, self.pos);
    }
    pub fn stagger(self: *Fishman, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugAct(self: *Fishman) void {
        self.heroLatch = false;
        self.enter(switch (self.role) {
            .spearman => .thrust,
            .netter => .cast,
            .shaman => .rite,
        });
    }
    pub fn debugKill(self: *Fishman) void {
        self.enterDeath();
    }

    const SPRAY = foe.Spray{
        .fanLo = 0.25,
        .fanHi = 0.95,
        .upLo = 0.3,
        .upHi = 1.4,
        .lifeLo = 0.28,
        .lifeHi = 0.55,
        .rLo = 0.014,
        .rHi = 0.030,
        .r1 = 0.008,
        .col = GILL,
        .col1 = foe.DUST_THIN,
        .grav = foe.BLOOD_GRAV,
        .stretch = foe.BLOOD_STRETCH,
    };
    fn spray(self: *Fishman, at: rl.Vector3, dir: rl.Vector3, n: i32) void {
        foe.spray(&self.parts, &self.fxHead, &self.fxRng, at, dir, n, 2.4, self.scale, SPRAY);
    }

    fn riteMotes(self: *Fishman) void {
        var i: u32 = 0;
        while (i < RITE_MOTES) : (i += 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.1, 0.7) * self.scale;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(self.pos.x + mathx.cosf(a) * rr, self.pos.y + self.fxRng.range(0.1, 1.5) * self.scale, self.pos.z + mathx.sinf(a) * rr),
                .v = v3(0, self.fxRng.range(0.5, 1.5), 0),
                .life = self.fxRng.range(0.5, 1.0),
                .r0 = 0.03,
                .r1 = 0.10,
                .col = SALT,
                .col1 = foe.DUST_THIN,
                .grav = -0.4,
                .drag = 2.4,
            });
        }
    }

    pub fn drawFx(self: *const Fishman) void {
        foe.drawParticles(&self.parts);
    }
    pub fn draw(self: *const Fishman, model: *const Model) void {
        model.draw(self);
    }

    pub fn pose(self: *Fishman) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = foe.rigSink(foe.SINK_HUMANOID, self.scale, self.fade);
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.5, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        const stun = self.stunAmount();
        const m = self.moving * (1.0 - dk);
        const pel = heromod.pelvisChannels(self.phase, m, self.fwdB, self.latB, A_PROT);
        const act = self.moveAmt();

        const bodyPitch = 9.0 + 14.0 * mathx.maxF(0, act) - 8.0 * mathx.maxF(0, -act) - 22.0 * stun + 42.0 * dk;
        const leanX = bodyPitch / 6.0;
        const waist = bodyPitch - leanX;
        const lumber = 3.0 * mathx.sinf(std.math.tau * self.phase) * m;
        const gulp = mathx.sinf(self.elapsed * 2.6 + self.seed * 6.28) * (1.0 - m);

        var wx: [N]rl.Matrix = undefined;
        const pelvY = if (dead) lerpF(hipY, 0.26 * H, dk) else hipY + pel.bob - pel.dip;
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(10.0 * dk + lumber * 0.5), rx(leanX), ry(pel.prot)),
            mul(tr(pel.sway * fs, pelvY * fs + sink, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));
        if (!dead) {
            heromod.legChain(&wx, &self.rest, self.phase, m, 0, self.fwdB, self.latB, 1.0, HIPL, KNEEL, solePatches[0]);
            heromod.legChain(&wx, &self.rest, self.phase + 0.5, m, 0, self.fwdB, self.latB, -1.0, HIPR, KNEER, solePatches[1]);
        } else {
            heromod.deadLegs(&wx, self.rest, dk);
        }
        self.poseUpper(&wx, waist, act, stun, dk, pel.prot, lumber, gulp);
        self.xf = wx;
    }

    fn poseUpper(self: *Fishman, wx: *[N]rl.Matrix, waist: f32, act: f32, stun: f32, dk: f32, prot: f32, lumber: f32, gulp: f32) void {
        const rest = self.rest;
        const m = self.moving * (1.0 - dk);
        const wonk = (self.seed - 0.5) * 5.0;
        const nod = 1.6 * mathx.cosf(2.0 * std.math.tau * self.phase) * m;
        // The trident's drive twists the whole trunk; the net's throw is a shoulder; the rite is neither.
        const twist: f32 = switch (self.state) {
            .thrust => 22.0 * act,
            .cast => 30.0 * act,
            else => 0,
        };

        setLocal(wx, SPINE, rest, mul3(rx(waist * 0.42 + nod), ry(-0.3 * prot + twist * 0.45), rz(wonk * 0.5 - 0.3 * lumber)));
        setLocal(wx, CHEST, rest, mul3(rx(waist * 0.58 + nod * 0.6 + 1.4 * gulp), ry(-0.45 * prot + twist * 0.55), rz(-wonk * 0.3 - 0.2 * lumber)));
        setLocal(wx, NECK, rest, rx(-8.0 * act + 6.0 * dk - 5.0 * stun));
        setLocal(wx, SKULL, rest, mul3(
            rx(-12.0 * act + 12.0 * dk - 22.0 * stun + 2.0 * gulp - (if (self.state == .rite) 26.0 * mathx.maxF(0, act) else 0)),
            ry(-0.4 * prot - twist * 0.2),
            rz(wonk),
        ));

        const armStun = -44.0 * stun;
        const swing = -11.0 * heromod.armSwing(self.phase) * m * @abs(self.fwdB);
        switch (self.role) {
            // **BOTH HANDS ON THE SHAFT.** The off hand is posed to the same angles as the weapon hand and
            // one socket further down, so the grip reads as two hands on one pole and not as a spare arm.
            .spearman => {
                const drive = 74.0 * mathx.maxF(0, act);
                const haul = -30.0 * mathx.maxF(0, -act);
                setLocal(wx, SHR, rest, mul3(rx(-40.0 + haul - drive * 0.5 + armStun - 18.0 * dk), ry(0), rz(-16.0)));
                setLocal(wx, ELR, rest, rx(-(66.0 - 44.0 * mathx.maxF(0, act))));
                setLocal(wx, WRR, rest, rz(-6.0));
                setLocal(wx, SHL, rest, mul3(rx(-58.0 + haul - drive * 0.7 + armStun - 18.0 * dk), ry(-14.0), rz(24.0)));
                setLocal(wx, ELL, rest, rx(-(48.0 - 34.0 * mathx.maxF(0, act))));
                setLocal(wx, WRL, rest, rz(6.0));
            },
            // Overarm: hauled back behind the shoulder, then thrown across the body.
            .netter => {
                const throw_ = 96.0 * mathx.maxF(0, act);
                const haul = -74.0 * mathx.maxF(0, -act);
                setLocal(wx, SHR, rest, mul3(rx(-14.0 + haul - throw_ + armStun - 18.0 * dk), ry(0), rz(-10.0 - 18.0 * mathx.maxF(0, -act))));
                setLocal(wx, ELR, rest, rx(-(40.0 + 40.0 * mathx.maxF(0, -act) - 30.0 * mathx.maxF(0, act))));
                setLocal(wx, WRR, rest, rz(-6.0));
                setLocal(wx, SHL, rest, mul3(rx(-(8.0 - swing) + armStun - 18.0 * dk), ry(0), rz(14.0)));
                setLocal(wx, ELL, rest, rx(-26.0));
                setLocal(wx, WRL, rest, rz(6.0));
            },
            // The rattle goes UP and STAYS up through the rite — the one silhouette worth reading at range,
            // because it is the one you are supposed to interrupt.
            .shaman => {
                const up = 128.0 * mathx.maxF(0, act) + 40.0 * mathx.maxF(0, -act);
                setLocal(wx, SHR, rest, mul3(rx(-(10.0 - swing) - up + armStun - 18.0 * dk), ry(0), rz(-12.0 - 20.0 * mathx.maxF(0, act))));
                setLocal(wx, ELR, rest, rx(-(30.0 - 22.0 * mathx.maxF(0, act))));
                setLocal(wx, WRR, rest, rz(-6.0));
                setLocal(wx, SHL, rest, mul3(rx(-(8.0 + swing) - up * 0.35 + armStun - 18.0 * dk), ry(0), rz(12.0)));
                setLocal(wx, ELL, rest, rx(-(34.0 - 10.0 * mathx.maxF(0, act))));
                setLocal(wx, WRL, rest, rz(6.0));
            },
        }
        // The held thing rides the right wrist for all three.
        heromod.setJoint(wx, &rest, HELD, WRR, ry(0));
    }
};

const CAP_N = wf.MAX_PER_KIND;

pub const Shoal = struct {
    model: Model,
    band: [CAP_N]Fishman = undefined,
    n: usize = 0,
    /// One-frame: seconds of net the hero is owed, or 0. `game` reads it after the group's update, which is
    /// the same shape the sporeling's cloud and the bloom's gas are taken in.
    pendingSnare: f32 = 0,

    pub fn init(shader: rl.Shader) Shoal {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Shoal) []Fishman {
        return self.band[0..self.n];
    }
    pub fn liveConst(self: *const Shoal) []const Fishman {
        return self.band[0..self.n];
    }
    pub fn reset(self: *Shoal, m: *const wf.Map) void {
        foe.resetRoles(Fishman, Role, &self.band, &self.n, m, roleOf);
    }
    pub fn clear(self: *Shoal) void {
        self.n = 0;
    }
    pub fn setShader(self: *Shoal, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn setParry(self: *Shoal, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }

    /// Whether anything in the band is hurt enough to be worth a rite. Read ONCE per frame and handed to
    /// every member, so two shamans see the same field and cannot answer differently within one frame.
    fn hurt(self: *const Shoal) bool {
        for (self.liveConst()) |*f| {
            if (!foe.corporeal(f)) continue;
            if (f.vit.hpFrac() < RITE_SLACK) return true;
        }
        return false;
    }

    pub fn update(self: *Shoal, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        const bandHurt = self.hurt();
        var worst: ?foe.Blow = null;
        var snare: f32 = 0;
        var i: usize = 0;
        while (i < self.n) : (i += 1) {
            const f = &self.band[i];
            if (f.update(dt, f.threat.aim(hero), bounds, blade, bandHurt)) |h| foe.worseBlow(&worst, h, f.pos, &f.threat);
            if (f.snared > 0) {
                snare = @max(snare, f.snared);
                // The net is a blow as well as a hold, and it goes through the ordinary door so a shield
                // and a parry board both get their say about the thing that took his feet.
                foe.worseBlow(&worst, NET_HIT, f.pos, &f.threat);
            }
            if (f.rang) self.mend(f.pos);
        }
        self.pendingSnare = snare;
        return worst;
    }

    pub fn takeSnare(self: *Shoal) f32 {
        const s = self.pendingSnare;
        self.pendingSnare = 0;
        return s;
    }

    /// **THE RITE HEALS ITS OWN, INCLUDING THE SHAMAN THAT RANG IT** — a share of each body's OWN maximum, so
    /// it is worth the same to the spearman as to the netter and cannot be tuned per role by accident.
    fn mend(self: *Shoal, from: rl.Vector3) void {
        for (self.live()) |*f| {
            if (!foe.corporeal(f)) continue;
            if (mathx.distXZ(from, f.pos) > RITE_RANGE) continue;
            _ = f.vit.heal(f.vit.hpMax * RITE_HEAL_FRAC);
        }
    }

    pub fn draw(self: *const Shoal, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Shoal) void {
        for (self.liveConst()) |*f| f.drawFx();
    }
    pub fn pierce(self: *Shoal, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Shoal) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn anyParried(self: *const Shoal) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn soulsDropped(self: *const Shoal) u32 {
        return foe.soulsEach(self.liveConst());
    }
    pub fn totalHits(self: *const Shoal) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Shoal) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

/// The body every role shares. `SKULL` and `HELD` are left undefined here and filled by `Model.init` from
/// the per-role tables — they are the two bones this creature does NOT hold in common.
fn buildBones() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = pelvisMesh();
    mesh[SPINE] = lumbarMesh();
    mesh[CHEST] = chestMesh();
    mesh[NECK] = neckMesh();
    mesh[HIPL] = thighMesh(1.0);
    mesh[KNEEL] = shinMesh(1.0);
    mesh[ANKL] = footMesh(1.0);
    mesh[HIPR] = thighMesh(-1.0);
    mesh[KNEER] = shinMesh(-1.0);
    mesh[ANKR] = footMesh(-1.0);
    mesh[SHL] = upperArmMesh(1.0);
    mesh[ELL] = forearmMesh(1.0);
    mesh[WRL] = handMesh(1.0);
    mesh[SHR] = upperArmMesh(-1.0);
    mesh[ELR] = forearmMesh(-1.0);
    mesh[WRR] = handMesh(-1.0);
    return mesh;
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, 0, 0), v3(0.086 * H, 0.068 * H, 0.074 * H), 9, 6, SCALE);
    b.addBlob(v3(0, -0.020 * H, 0.030 * H), v3(0.070 * H, 0.044 * H, 0.052 * H), 8, 5, BELLY);
    return b.toMesh();
}

fn lumbarMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(0, 0.076 * H, 0), 0.062 * H, 0.074 * H, 9, SCALE);
    b.addBlob(v3(0, 0.034 * H, 0.038 * H), v3(0.056 * H, 0.040 * H, 0.036 * H), 7, 5, BELLY);
    return b.toMesh();
}

/// **THE DORSAL FIN IS THE SILHOUETTE.** From behind, with no face and no weapon visible, the ridge is the
/// only thing that says what these are — so it is on the trunk and not on the head.
fn chestMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, 0.040 * H, 0), v3(0.104 * H, 0.082 * H, 0.082 * H), 10, 7, SCALE);
    b.addBlob(v3(0, -0.004 * H, 0.020 * H), v3(0.086 * H, 0.052 * H, 0.062 * H), 9, 6, BELLY);
    b.addBlob(v3(0, 0.086 * H, -0.008 * H), v3(0.090 * H, 0.034 * H, 0.076 * H), 8, 6, SCALE_DK);
    b.setMat(.plain);
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const f = @as(f32, @floatFromInt(i)) / 4.0;
        const hgt = (0.030 + 0.026 * mathx.sinf(f * std.math.pi)) * H;
        b.addBlob(
            v3(0, (0.070 + hgt * 0.5) * H / H, (-0.040 + 0.060 * f) * H),
            v3(0.006 * H, hgt, 0.016 * H),
            5,
            5,
            if (i % 2 == 0) FIN else FIN_DK,
        );
    }
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(0, 0.042 * H, -0.004 * H), 0.030 * H, 0.032 * H, 7, SCALE);
    b.setMat(.plain);
    // Gills: three slits a side, and they are the one warm colour on the body.
    inline for (.{ 1.0, -1.0 }) |side| {
        var i: u32 = 0;
        while (i < 3) : (i += 1) {
            const y = 0.006 * H + @as(f32, @floatFromInt(i)) * 0.013 * H;
            b.addBlob(v3(side * 0.028 * H, y, 0.006 * H), v3(0.008 * H, 0.005 * H, 0.014 * H), 5, 4, GILL);
        }
    }
    return b.toMesh();
}

/// **THE THREE ARE TOLD APART AT THE HEAD**, because that is what a player can see over a shield wall: the
/// spearman is bare, the netter has a swept crest, the shaman wears a fish skull over its own.
fn headMesh(role: Role) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, 0.014 * H, 0.014 * H), v3(0.046 * H, 0.048 * H, 0.058 * H), 9, 7, SCALE);
    b.addBlob(v3(0, -0.010 * H, 0.044 * H), v3(0.034 * H, 0.026 * H, 0.036 * H), 7, 5, BELLY);
    b.setMat(.plain);
    b.addBlob(v3(0.030 * H, 0.026 * H, 0.024 * H), v3(0.017 * H, 0.017 * H, 0.015 * H), 6, 5, EYE);
    b.addBlob(v3(-0.030 * H, 0.026 * H, 0.024 * H), v3(0.017 * H, 0.017 * H, 0.015 * H), 6, 5, EYE);
    b.addBlob(v3(0.034 * H, 0.028 * H, 0.028 * H), v3(0.008 * H, 0.008 * H, 0.007 * H), 5, 4, EYE_RIM);
    b.addBlob(v3(-0.034 * H, 0.028 * H, 0.028 * H), v3(0.008 * H, 0.008 * H, 0.007 * H), 5, 4, EYE_RIM);
    switch (role) {
        .spearman => {},
        .netter => {
            var i: u32 = 0;
            while (i < 5) : (i += 1) {
                const f = @as(f32, @floatFromInt(i)) / 4.0;
                b.addBlob(
                    v3(0, (0.052 + 0.020 * mathx.sinf(f * std.math.pi)) * H, (0.020 - 0.052 * f) * H),
                    v3(0.005 * H, 0.022 * H, 0.012 * H),
                    5,
                    4,
                    FIN,
                );
            }
        },
        .shaman => {
            // A fish's skull worn as a hood: the long jaw comes forward over its own brow.
            b.addBlob(v3(0, 0.044 * H, 0.006 * H), v3(0.050 * H, 0.030 * H, 0.056 * H), 8, 6, BONE);
            b.addCapsule(v3(0, 0.040 * H, 0.040 * H), v3(0, 0.020 * H, 0.098 * H), 0.020 * H, 0.009 * H, 7, BONE);
            var i: u32 = 0;
            while (i < 4) : (i += 1) {
                const f = @as(f32, @floatFromInt(i)) / 3.0;
                b.addCapsule(
                    v3(0.014 * H, (0.036 - 0.008 * f) * H, (0.050 + 0.036 * f) * H),
                    v3(0.018 * H, (0.020 - 0.008 * f) * H, (0.052 + 0.036 * f) * H),
                    0.004 * H,
                    0.002 * H,
                    4,
                    SALT,
                );
            }
        },
    }
    return b.toMesh();
}

fn thighMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(side * 0.004 * H, -0.140 * H, 0), 0.040 * H, 0.030 * H, 8, SCALE);
    return b.toMesh();
}

fn shinMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(side * 0.002 * H, -0.136 * H, 0.004 * H), 0.028 * H, 0.020 * H, 8, SCALE_DK);
    b.setMat(.plain);
    // A trailing fin off the calf — the leg is still a fish's.
    b.addBlob(v3(side * 0.024 * H, -0.070 * H, -0.014 * H), v3(0.005 * H, 0.030 * H, 0.020 * H), 5, 4, FIN_DK);
    return b.toMesh();
}

/// Splayed webbed feet — wide, because a body built for silt is what still walks on the pan.
fn footMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0.004 * H, -0.030 * H), v3(side * 0.008 * H, -0.004 * H, 0.100 * H), 0.028 * H, 0.020 * H, 7, SCALE_DK);
    b.setMat(.plain);
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const f = @as(f32, @floatFromInt(i)) - 1.0;
        b.addBlob(v3(side * f * 0.026 * H, -0.006 * H, 0.110 * H), v3(0.014 * H, 0.005 * H, 0.026 * H), 5, 4, FIN);
    }
    return b.toMesh();
}

fn upperArmMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(side * 0.006 * H, -0.100 * H, 0), 0.028 * H, 0.022 * H, 7, SCALE);
    return b.toMesh();
}

fn forearmMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(side * 0.004 * H, -0.078 * H, 0), 0.021 * H, 0.016 * H, 7, SCALE_LT);
    b.setMat(.plain);
    b.addBlob(v3(side * 0.020 * H, -0.040 * H, -0.010 * H), v3(0.004 * H, 0.024 * H, 0.016 * H), 5, 4, FIN_DK);
    return b.toMesh();
}

fn handMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, -0.016 * H, 0.004 * H), v3(0.020 * H, 0.022 * H, 0.018 * H), 6, 5, SCALE_LT);
    b.setMat(.plain);
    // Webbing between the fingers, which is most of what a hand at this size reads as.
    b.addBlob(v3(side * 0.006 * H, -0.034 * H, 0.010 * H), v3(0.019 * H, 0.014 * H, 0.016 * H), 5, 4, FIN);
    return b.toMesh();
}

/// **THREE PRONGS AND A BARB ON EACH**, because the whole reach of this creature is one thrust and the thing
/// on the end has to look like it earns 2.7 m.
fn tridentMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    b.addCapsule(v3(0, 0.34 * H, 0), v3(0, -0.60 * H, 0), 0.012 * H, 0.010 * H, 7, TOTEM);
    b.addCapsule(v3(0, 0.30 * H, 0), v3(0, 0.36 * H, 0), 0.016 * H, 0.014 * H, 6, CORD);
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const f = @as(f32, @floatFromInt(i)) - 1.0;
        const tipY = 0.50 * H;
        b.addCapsule(v3(f * 0.026 * H, 0.36 * H, 0), v3(f * 0.030 * H, tipY, 0), 0.008 * H, 0.002 * H, 6, BONE);
        // The barb: a short spur back down the prong, the reason a trident is not three sticks.
        b.addCapsule(v3(f * 0.030 * H, tipY - 0.030 * H, 0), v3(f * 0.048 * H, tipY - 0.058 * H, 0), 0.004 * H, 0.001 * H, 4, BONE);
    }
    return b.toMesh();
}

/// The bundle in the hand before it is thrown: a gathered mass of cord with the weights hanging off it.
fn netBundleMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xF15E);
    b.setMat(.plain);
    b.addBlob(v3(0, -0.030 * H, 0.010 * H), v3(0.048 * H, 0.042 * H, 0.044 * H), 7, 6, CORD);
    var i: u32 = 0;
    while (i < 6) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.030, 0.062) * H;
        b.addBlob(v3(mathx.cosf(a) * d, -0.072 * H, mathx.sinf(a) * d), v3(0.010 * H, 0.010 * H, 0.010 * H), 5, 4, SALT);
    }
    return b.toMesh();
}

/// The net OPEN, in the air: a ring of weights with the mesh strung between. Drawn spinning, so what a player
/// sees coming is a widening circle rather than a thrown rock.
fn netFlightMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    const R = 0.46 * H;
    var i: u32 = 0;
    while (i < 12) : (i += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / 12.0;
        const nxt = std.math.tau * @as(f32, @floatFromInt(i + 1)) / 12.0;
        b.addCapsule(
            v3(mathx.cosf(a) * R, 0, mathx.sinf(a) * R),
            v3(mathx.cosf(nxt) * R, 0, mathx.sinf(nxt) * R),
            0.008 * H,
            0.008 * H,
            4,
            CORD,
        );
        b.addBlob(v3(mathx.cosf(a) * R, -0.010 * H, mathx.sinf(a) * R), v3(0.014 * H, 0.012 * H, 0.014 * H), 5, 4, SALT);
        // Two chords across the middle each way, which is all a mesh needs to read as a mesh in flight.
        if (i < 6) {
            const opp = a + std.math.pi;
            b.addCapsule(
                v3(mathx.cosf(a) * R, 0, mathx.sinf(a) * R),
                v3(mathx.cosf(opp) * R, 0, mathx.sinf(opp) * R),
                0.004 * H,
                0.004 * H,
                4,
                CORD,
            );
        }
    }
    return b.toMesh();
}

/// A jaw on a stick with the teeth still in it, and salt-crusted rings that make the noise.
fn rattleMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    b.addCapsule(v3(0, 0.18 * H, 0), v3(0, -0.10 * H, 0), 0.011 * H, 0.009 * H, 6, TOTEM);
    b.addCapsule(v3(0, 0.16 * H, -0.020 * H), v3(0, 0.26 * H, 0.030 * H), 0.016 * H, 0.010 * H, 7, BONE);
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const f = @as(f32, @floatFromInt(i)) / 4.0;
        b.addCapsule(
            v3(0.008 * H, (0.18 + 0.070 * f) * H, (-0.014 + 0.038 * f) * H),
            v3(0.014 * H, (0.16 + 0.070 * f) * H, (-0.010 + 0.038 * f) * H),
            0.003 * H,
            0.0015 * H,
            4,
            SALT,
        );
    }
    var j: u32 = 0;
    while (j < 3) : (j += 1) {
        b.addBlob(v3(0, (0.06 + 0.036 * @as(f32, @floatFromInt(j))) * H, 0), v3(0.020 * H, 0.005 * H, 0.020 * H), 6, 4, SALT);
    }
    return b.toMesh();
}


test "THE THREE PICK DIFFERENT THINGS FROM THE SAME PLACE — that is what makes them a band" {
    const near = 1.8;
    const mid = 6.0;
    // At the spearman's own reach: he thrusts, the netter is too close to throw, the shaman does nothing.
    try std.testing.expectEqual(Choice.thrust, classify(.spearman, near, near, 0, true, false, false));
    try std.testing.expectEqual(Choice.back, classify(.netter, near, near, 0, true, false, false));
    try std.testing.expectEqual(Choice.back, classify(.shaman, near, near, 0, true, false, false));
    // Out at the netter's band: he throws, the spearman closes, the shaman still holds off.
    try std.testing.expectEqual(Choice.net, classify(.netter, mid, mid, 0, true, false, false));
    try std.testing.expectEqual(Choice.close, classify(.spearman, mid, mid, 0, true, false, false));
    try std.testing.expectEqual(Choice.back, classify(.shaman, mid, mid, 0, true, false, false));
}

test "THE NET IS NOT A MELEE MOVE — inside `NET_MIN` he cannot throw it and has to give ground" {
    try std.testing.expectEqual(Choice.back, classify(.netter, NET_MIN - 0.2, NET_MIN - 0.2, 0, true, false, false));
    try std.testing.expectEqual(Choice.net, classify(.netter, NET_MIN + 0.2, NET_MIN + 0.2, 0, true, false, false));
    try std.testing.expectEqual(Choice.close, classify(.netter, NET_R + 1.0, NET_R + 1.0, 0, true, false, false));
}

test "THE SHAMAN SPENDS THE RITE ON WOUNDS AND NOT ON SCRATCHES" {
    try std.testing.expectEqual(Choice.rest, classify(.shaman, 10.0, 10.0, 0, true, false, false));
    try std.testing.expectEqual(Choice.rite, classify(.shaman, 10.0, 10.0, 0, true, true, false));
    // …and it holds the rite while it is on cooldown rather than waiting on the spot for it.
    try std.testing.expectEqual(Choice.rest, classify(.shaman, 10.0, 10.0, 0, false, true, false));
}

test "THE NET TAKES HIS FEET AND BUYS EXACTLY ONE THRUST" {
    std.debug.print("\n  fishmen: net holds {d:.2} s; a thrust lands at {d:.2} s and the next at {d:.2} s\n", .{
        NET_HOLD,
        THRUST_WIND + THRUST_STRIKE,
        THRUST_WIND + THRUST_STRIKE + THRUST_RECOVER,
    });
    try std.testing.expect(NET_HOLD > THRUST_WIND + THRUST_STRIKE);
    try std.testing.expect(NET_HOLD < THRUST_WIND + THRUST_STRIKE + THRUST_RECOVER);

    // The hero's own half of this — held feet, live sword — is pinned in `hero.zig`, where his test rig is.
}

test "A NET IN THE AIR OUTLIVES THE THROWER, AND IT CAN BE STEPPED OUT OF" {
    var f = Fishman.spawnAs(.netter, mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, 6.0);
    f.facing = mathx.headingXZ(mathx.dirXZ(f.pos, hero));
    f.debugAct();
    var caught = false;
    var flew = false;
    var t: f32 = 0;
    while (t < 3.0) : (t += 1.0 / 60.0) {
        _ = f.update(1.0 / 60.0, hero, 400, .{}, false);
        if (f.net.live) flew = true;
        if (f.snared > 0) caught = true;
    }
    try std.testing.expect(flew);
    try std.testing.expect(caught);

    // The same throw, with the hero walking out of the line: it lands on empty ground.
    var g = Fishman.spawnAs(.netter, mathx.zero3, 0, 1.0, 0.3);
    g.facing = mathx.headingXZ(mathx.dirXZ(g.pos, hero));
    g.debugAct();
    var dodged = true;
    var at = hero;
    t = 0;
    while (t < 3.0) : (t += 1.0 / 60.0) {
        at.x += heromod.RUN_SPEED * (1.0 / 60.0);
        _ = g.update(1.0 / 60.0, at, 400, .{}, false);
        if (g.snared > 0) dodged = false;
    }
    std.debug.print("  the net travels: standing still it lands, running sideways it does not\n", .{});
    try std.testing.expect(dodged);
}

test "THE RITE PUTS BACK A SHARE OF EACH BODY'S OWN BAR — and it reaches the whole band" {
    var s = Shoal{ .model = undefined };
    s.band[0] = Fishman.spawnAs(.shaman, mathx.zero3, 0, 1.0, 0.3);
    s.band[1] = Fishman.spawnAs(.spearman, v3(0, 0, 3.0), 0, 1.0, 0.5);
    s.band[2] = Fishman.spawnAs(.netter, v3(0, 0, 6.0), 0, 1.0, 0.7);
    // …and one the far side of the field, out of the rite AND out of aggro so it stays there.
    s.band[3] = Fishman.spawnAs(.spearman, v3(0, 0, -(RITE_RANGE + 6.0)), 0, 1.0, 0.9);
    s.n = 4;
    for (s.live()) |*f| f.vit.hp = f.vit.hpMax * 0.5;
    const before = [_]f32{ s.band[0].vit.hp, s.band[1].vit.hp, s.band[2].vit.hp, s.band[3].vit.hp };

    // **INSIDE ITS EYES**: past `AGGRO_R` the band is at rest and no rite is ever chosen, so a hero parked
    // forty metres off tests nothing at all.
    const hero = v3(0, 0, 12.0);
    var rang = false;
    var t: f32 = 0;
    while (t < 12.0) : (t += 1.0 / 60.0) {
        _ = s.update(1.0 / 60.0, hero, 400, .{});
        if (s.band[0].rang) {
            rang = true;
            break;
        }
    }
    try std.testing.expect(rang);
    for (0..3) |i| {
        const want = before[i] + s.band[i].vit.hpMax * RITE_HEAL_FRAC;
        try std.testing.expectApproxEqAbs(want, s.band[i].vit.hp, 1e-3);
    }
    try std.testing.expectApproxEqAbs(before[3], s.band[3].vit.hp, 1e-4);
    std.debug.print("  rite: +{d:.0}% of each body's own bar over {d:.0} m — the one outside it got nothing\n", .{ RITE_HEAL_FRAC * 100.0, RITE_RANGE });
}

test "KILL THE SHAMAN FIRST: it is worth the most and it is the softest thing there" {
    try std.testing.expect(spec(.shaman).souls > spec(.spearman).souls);
    try std.testing.expect(spec(.shaman).souls > spec(.netter).souls);
    try std.testing.expect(spec(.shaman).hp < spec(.spearman).hp);
    try std.testing.expect(spec(.shaman).hp < spec(.netter).hp);
    // …and it stands furthest back, which is what makes the right answer the hard one.
    try std.testing.expect(spec(.shaman).wantMin > spec(.netter).wantMin);
    try std.testing.expect(spec(.netter).wantMin > spec(.spearman).wantMin);
    std.debug.print("  souls {d}/{d}/{d}, hp {d:.0}/{d:.0}/{d:.0}, band {d:.1}/{d:.1}/{d:.1} m\n", .{
        spec(.spearman).souls,   spec(.netter).souls,   spec(.shaman).souls,
        spec(.spearman).hp,      spec(.netter).hp,      spec(.shaman).hp,
        spec(.spearman).wantMin, spec(.netter).wantMin, spec(.shaman).wantMin,
    });
}

test "the roles are a contiguous run and the map can post each of them" {
    try std.testing.expectEqual(Role.spearman, roleOf(.fish_spearman).?);
    try std.testing.expectEqual(Role.netter, roleOf(.fish_netter).?);
    try std.testing.expectEqual(Role.shaman, roleOf(.fish_shaman).?);
    try std.testing.expect(roleOf(.toad) == null);
    inline for (.{ Role.spearman, Role.netter, Role.shaman }) |r| {
        try std.testing.expectEqual(r, roleOf(kindOf(r)).?);
    }
}

test "the trident is the longest common reach in the game, and it is telegraphed" {
    try std.testing.expect(THRUST_R > 2.5);
    var f = Fishman.spawnAs(.spearman, mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, 2.3);
    f.facing = mathx.headingXZ(mathx.dirXZ(f.pos, hero));
    f.debugAct();
    var landed: u32 = 0;
    var firstAt: f32 = 0;
    var t: f32 = 0;
    while (t < THRUST_WIND + THRUST_STRIKE + THRUST_RECOVER + 0.1) : (t += 1.0 / 60.0) {
        if (f.update(1.0 / 60.0, hero, 400, .{}, false) != null) {
            if (landed == 0) firstAt = t;
            landed += 1;
        }
    }
    try std.testing.expectEqual(@as(u32, 1), landed);
    try std.testing.expect(firstAt >= foe.TELL_MIN);
    std.debug.print("  trident: {d:.1} m of reach, arriving at {d:.2} s\n", .{ THRUST_R, firstAt });
}
