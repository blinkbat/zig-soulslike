const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const heromod = @import("../play/hero.zig");
const wf = @import("../world/worldfmt.zig");
const art = @import("../props/propart.zig");
const forge = @import("../props/propforge.zig");

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
const setLocal = heromod.setHumanoid;


const H: f32 = heromod.H;
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
const STAFF = heromod.HELD;

pub const SCALE = (H - 0.065) / H;
const FACE_AT = mathx.v3(0, 0.045 * H, 0.02 * H);

pub const PORTRAIT_DIST: f32 = 0.86;
const REST = heromod.restHumanoid(heromod.HIP_HALF, heromod.SHOULDER_HALF * 0.96, H);

// SOLVED AGAINST THE RENDER, NOT PICKED. Every material sampled 30-36 on screen — a lit figure at the value of ground in SHADOW — where the hero spans 29-50 plus skin near 90: what separates a body is RANGE. On this sun albedo 40 comes back at 142 and 58 at 168, so the layering is on HUE (warm wool, COLD cloak).
const ROBE = rgba(50, 42, 33, 255);
const ROBE_LT = rgba(68, 58, 45, 255);
const ROBE_DK = rgba(30, 25, 20, 255);
const CLOAK = rgba(58, 57, 66, 255);
const CLOAK_LT = rgba(74, 72, 80, 255);
const CLOAK_DK = rgba(40, 39, 46, 255);
const HOOD_IN = rgba(10, 9, 8, 255);
const SASH = rgba(110, 72, 38, 255);
const LINEN = rgba(132, 122, 100, 255);
const LINEN_DK = rgba(96, 88, 72, 255);
const LEATHER = rgba(40, 30, 22, 255);
const LEATHER_LT = rgba(56, 42, 30, 255);
const BOOT = rgba(30, 24, 19, 255);
const SKIN = rgba(150, 112, 84, 255);
const SKIN_DK = rgba(114, 84, 62, 255);
const HAIR = rgba(140, 134, 122, 255);
const BEARD = rgba(150, 144, 132, 255);
const WOOD = rgba(44, 32, 20, 255);
const WOOD_LT = rgba(62, 46, 28, 255);
const GOURD = rgba(98, 78, 44, 255);
const IRON = rgba(44, 42, 40, 255);

// Layered on HUE, spanning albedo 24 to 100 — 111 to 213 on screen:
//   hide 72 -> 183    stripe 88 -> 201    indigo 34 -> 131    hump 38 -> 137    strap 24 -> 111
const HIDE = rgba(78, 66, 46, 255);
const HIDE_DK = rgba(48, 40, 30, 255);
const HUMP = rgba(40, 34, 26, 255);
const HUMP_LT = rgba(56, 48, 36, 255);
const STRIPE = art.WEAVE;
const STRIPE_DK = art.WEAVE_DK;
const MADDER = art.MADDER;
const MADDER_LT = art.MADDER_LT;
const STRAP = rgba(24, 19, 14, 255);
const HOOF = rgba(34, 30, 26, 255);
const MUZZLE = rgba(96, 84, 62, 255);
const LASH = rgba(20, 17, 13, 255);
const BRASS = rgba(108, 82, 34, 255);

const MERCH_NECK: f32 = 0.100 * H;

// **AUTHOR DARK, AND SOLVE IT OFF THE CHAIN** (AGENTS.md): screen goes as (albedo x 1.72)^(1/2.2), so a big
// palette here has had to cover. MEASURED down the chain — albedo 20 -> 103 on screen, 30 -> 123, 46 -> 150,
// 72 -> 183, 104 -> 217:
//     bark 30 -> 123 (warm)   heart 86 -> 199 (warm)   lichen 104 -> 217 (COLD green)   iron 30 -> 123
const BARKS = rgba(30, 25, 20, 255);
const BARKS_DK = rgba(18, 15, 12, 255);
const BARKS_LT = rgba(46, 38, 28, 255);
const HEART = rgba(86, 52, 30, 255);
const HEART_DK = rgba(52, 32, 19, 255);
const LICHEN = rgba(104, 112, 92, 255);
const LICHEN_DK = rgba(72, 80, 64, 255);
const LICHEN_PALE = rgba(126, 132, 112, 255);
const SMOSS = rgba(44, 56, 32, 255);
const EYE = rgba(226, 138, 52, 96);
const APRON = rgba(34, 26, 19, 255);
const APRON_LT = rgba(50, 39, 28, 255);
const SIRON = rgba(30, 28, 26, 255);
const SIRON_LT = rgba(46, 44, 42, 255);
const HAFT = rgba(52, 40, 26, 255);

pub const SMITH_SIZE: f32 = 1.76;
const SMITH_TOP: f32 = 1.06;
const SMITH_STOOP: f32 = 25.0;
const SMITH_HEAD_FWD: f32 = 21.0;


/// Seconds a whole stroke takes. SLOW, because he is enormous and gentle — a farrier's tap is 0.5 s.
pub const HAMMER_PERIOD: f32 = 2.15;
const HAMMER_RISE: f32 = 0.46;
const HAMMER_FALL: f32 = 0.60;
const HAMMER_REBOUND: f32 = 0.09;
const HAM_SH_LO: f32 = 60.0;
const HAM_SH_HI: f32 = 78.0;
const HAM_EL_LO: f32 = 8.0;
const HAM_EL_HI: f32 = 112.0;
const HAM_ABD: f32 = 7.0;
const HAM_WRIST: f32 = 14.0;
/// **WHERE THE HEAD ACTUALLY POINTS, IN THE WORLD** — degrees it leads FORWARD of plumb (0 down, 90 level, 180 on end).
pub const HAM_BEAR_FACE: f32 = 30.0;
pub const HAM_BEAR_TOP: f32 = 140.0;
const HAM_TILT_LO: f32 = 63.0;
const HAM_TILT_HI: f32 = 166.0;
const HAM_TRUNK: f32 = 7.5;
const BEARD_SWING: f32 = 15.0;
const BEARD_LAG: f32 = 0.11;

const HOLD_SH: f32 = 44.0;
const HOLD_EL: f32 = 74.0;
const HOLD_ABD: f32 = 15.0;

const HAFT_LEN: f32 = 0.255 * H;
const HEAD_R: f32 = 0.052 * H;

/// Metres forward of the pin he is placed on, MEASURED off the posed rig at the bottom of the stroke: the head
/// bottoms at 0.98 m up and 1.00 m out.
pub const SMITH_ANVIL_Z: f32 = 1.00;

pub const NKIND = @typeInfo(wf.NpcKind).@"enum".fields.len;

const SMITH_HEAD_TRACK: f32 = 74.0;
const SMITH_HEAD_DIP: f32 = 26.0;
const HEAD_TRACK_RATE: f32 = 200.0;

const Spec = struct {
    kind: wf.NpcKind,
    size: f32 = 1.0,
    stoop: f32,
    headFwd: f32,
    faceAt: rl.Vector3,
    top: f32,
    /// **HE TRACKS YOU WITH HIS HEAD AND HIS BODY STAYS PUT** (owner). Degrees of neck; 0 turns the whole body
    headTrack: f32 = 0,
    headDip: f32 = 0,
};

const SPEC = [NKIND]Spec{
    .{ .kind = .wanderer, .stoop = 7.5, .headFwd = 5.0, .faceAt = FACE_AT, .top = 1.02 },
    .{ .kind = .merchant, .size = 1.06, .stoop = -3.0, .headFwd = -7.0, .faceAt = v3(0, 0.045 * H + MERCH_NECK, 0.085 * H), .top = 1.16 },
    .{ .kind = .smith, .size = SMITH_SIZE, .stoop = SMITH_STOOP, .headFwd = SMITH_HEAD_FWD, .faceAt = v3(0, 0.062 * H, 0.048 * H), .top = SMITH_TOP, .headTrack = SMITH_HEAD_TRACK, .headDip = SMITH_HEAD_DIP },
};

comptime {
    for (SPEC, 0..) |sp, i| {
        if (@intFromEnum(sp.kind) != i) @compileError("npc: SPEC is out of `wf.NpcKind` order");
    }
    std.debug.assert(spec(.merchant).stoop < spec(.wanderer).stoop and spec(.merchant).headFwd < spec(.wanderer).headFwd);
    std.debug.assert(spec(.merchant).top > spec(.wanderer).top);
    std.debug.assert(spec(.smith).stoop > spec(.wanderer).stoop and spec(.smith).headFwd > spec(.wanderer).headFwd);
    std.debug.assert(spec(.smith).size > spec(.merchant).size * 1.3);
    std.debug.assert(HAMMER_RISE < HAMMER_FALL and HAMMER_FALL < 1.0);
    std.debug.assert(HAMMER_FALL - HAMMER_RISE < HAMMER_RISE * 0.5);
    std.debug.assert(HAM_EL_HI > HAM_EL_LO and HAM_SH_HI > HAM_SH_LO);
    std.debug.assert(HAM_EL_HI - HAM_EL_LO > 3.0 * (HAM_SH_HI - HAM_SH_LO));
}

pub fn spec(k: wf.NpcKind) Spec {
    return SPEC[@intFromEnum(k)];
}

pub const NOTICE_R: f32 = 7.0;
pub const REACH: f32 = 2.4;
const TURN_RATE = 3.2;
const TURN_GATE = 0.22;
const AMBLE_SPEED = heromod.WALK_SPEED_BANK * 0.42;
const BODY_R = 0.32;

const A_BOB = heromod.A_BOB;
const A_PROT = 3.2;

const BREATH_RATE = 0.62; // Hz-ish (radians below)
const SHIFT_RATE = 0.19;
const DRIFT_RATE = 0.113;
const A_BREATH = 2.1;
const A_LIST = 1.3;
const A_DRIFT_YAW = 7.5;
const A_DRIFT_PITCH = 3.0;


const STAFF_SH = 12.0;
const STAFF_EL = -34.0;
const STAFF_ABD = 15.0;
const STAFF_TILT = 8.0;
const STAFF_PLANT_SH = 16.0;
/// FIST → FERRULE. The wrist rides at 0.485·H and the pole is raked a few degrees off plumb, so this is that height less the rake's cost: longer and it drives through the floor and out the far side, which is what 0.66·H did.
const STAFF_LEN = 0.455 * H;
const STAFF_UP = 0.32 * H;
const STAFF_R = 0.020 * H;

const FREE_SH = 8.0;
const FREE_EL = -22.0;
const FREE_ABD = 9.0;

pub const Gesture = enum { none, beckon, point, bow };

fn gestureDur(g: Gesture) f32 {
    return switch (g) {
        .none => 0,
        .beckon => 1.15,
        .point => 0.95,
        .bow => 1.20,
    };
}

const TALK_BEAT: f32 = 3.4;
const DWELL: f32 = 2.6;
const ARRIVE: f32 = 0.35;

pub const Model = struct {
    bone: [NKIND][N]rl.Mesh,
    heads: [NKIND][2]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "npc");
        var heads: [NKIND][2]rl.Mesh = undefined;
        heads[0] = .{ hoodedHeadMesh(), bareHeadMesh() };
        heads[1] = .{ merchHeadMesh(true), merchHeadMesh(false) };
        heads[2] = .{ burlHeadMesh(false), burlHeadMesh(true) };
        var bone: [NKIND][N]rl.Mesh = undefined;
        bone[0] = wandererBones(heads[0][0]);
        bone[1] = merchantBones(heads[1][0]);
        bone[2] = smithBones(heads[2][0]);
        return .{ .bone = bone, .heads = heads, .mat = mat };
    }

    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }

    pub fn draw(self: *const Model, p: *const Wanderer) void {
        const k = @intFromEnum(p.kind);
        for (0..N) |i| {
            if (i == SKULL) {
                rl.drawMesh(self.heads[k][p.variant], self.mat, p.xf[SKULL]);
                continue;
            }
            rl.drawMesh(self.bone[k][i], self.mat, p.xf[i]);
        }
    }
};

fn wandererBones(head: rl.Mesh) [N]rl.Mesh {
    var bone: [N]rl.Mesh = undefined;
    bone[ROOT] = pelvisMesh();
    bone[SPINE] = abdomenMesh();
    bone[CHEST] = chestMesh();
    bone[NECK] = neckMesh();
    bone[SKULL] = head;
    bone[HIPL] = thighMesh();
    bone[KNEEL] = shankMesh();
    bone[ANKL] = footMesh();
    bone[HIPR] = thighMesh();
    bone[KNEER] = shankMesh();
    bone[ANKR] = footMesh();
    bone[SHL] = sleeveMesh();
    bone[ELL] = forearmMesh();
    bone[WRL] = handMesh();
    bone[SHR] = sleeveMesh();
    bone[ELR] = forearmMesh();
    bone[WRR] = handMesh();
    bone[STAFF] = staffMesh();
    return bone;
}

fn smithBones(head: rl.Mesh) [N]rl.Mesh {
    var bone: [N]rl.Mesh = undefined;
    bone[ROOT] = smithPelvisMesh();
    bone[SPINE] = smithAbdomenMesh();
    bone[CHEST] = smithChestMesh();
    bone[NECK] = smithNeckMesh();
    bone[SKULL] = head;
    bone[HIPL] = smithThighMesh();
    bone[KNEEL] = smithShankMesh();
    bone[ANKL] = smithFootMesh();
    bone[HIPR] = smithThighMesh();
    bone[KNEER] = smithShankMesh();
    bone[ANKR] = smithFootMesh();
    bone[SHL] = smithUpperArmMesh();
    bone[ELL] = smithForearmMesh();
    bone[WRL] = smithHandMesh(true);
    bone[SHR] = smithUpperArmMesh();
    bone[ELR] = smithForearmMesh();
    bone[WRR] = smithHandMesh(false);
    bone[STAFF] = hammerMesh();
    return bone;
}

fn merchantBones(head: rl.Mesh) [N]rl.Mesh {
    var bone: [N]rl.Mesh = undefined;
    bone[ROOT] = merchPelvisMesh();
    bone[SPINE] = merchAbdomenMesh();
    bone[CHEST] = merchChestMesh();
    bone[NECK] = merchNeckMesh();
    bone[SKULL] = head;
    bone[HIPL] = merchThighMesh();
    bone[KNEEL] = merchShankMesh();
    bone[ANKL] = merchFootMesh();
    bone[HIPR] = merchThighMesh();
    bone[KNEER] = merchShankMesh();
    bone[ANKR] = merchFootMesh();
    bone[SHL] = merchSleeveMesh();
    bone[ELL] = merchForearmMesh();
    bone[WRL] = merchHandMesh();
    bone[SHR] = merchSleeveMesh();
    bone[ELR] = merchForearmMesh();
    bone[WRR] = merchHandMesh();
    bone[STAFF] = scaleBeamMesh();
    return bone;
}

pub const Wanderer = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    postYaw: f32 = 0,
    facing: f32 = 0,
    scale: f32 = SCALE,
    seed: f32 = 0,
    variant: usize = 0,
    kind: wf.NpcKind = .wanderer,
    rec: u16 = 0,
    roamR: f32 = 0,

    talking: bool = false,
    noticed: bool = false,

    t: f32 = 0,
    wantYaw: f32 = 0,
    gesture: Gesture = .none,
    gt: f32 = 0,
    beat: f32 = TALK_BEAT,
    /// **THE SMITH'S STROKE, AS A REPEATING PHASE.** 0 is the hammer on the face, `HAMMER_RISE` is the top of
    /// the raise. Nothing else has one and on every other kind it stays 0.
    hammer: f32 = 0,
    headYaw: f32 = 0,
    headDip: f32 = 0,
    struck: bool = false,

    target: rl.Vector3 = mathx.zero3,
    dwell: f32 = 0,
    rng: mathx.Rng = mathx.Rng.init(1),

    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,
    prevPhase: f32 = 0,

    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,

    pub fn facePoint(self: *const Wanderer) rl.Vector3 {
        return rl.math.vector3Transform(spec(self.kind).faceAt, self.xf[SKULL]);
    }

    pub fn spawn(rec: u16, home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32, roam: f32) Wanderer {
        return spawnAs(.wanderer, rec, home, faceYaw, scale, seed, roam);
    }

    pub fn spawnAs(kind: wf.NpcKind, rec: u16, home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32, roam: f32) Wanderer {
        var p = Wanderer{
            .kind = kind,
            .pos = home,
            .home = home,
            .postYaw = faceYaw,
            .facing = faceYaw,
            .wantYaw = faceYaw,
            .scale = SCALE * scale * spec(kind).size,
            .seed = seed,
            .variant = if (seed < 0.5) 0 else 1,
            .rec = rec,
            .roamR = roam,
            .target = home,
            .rng = mathx.Rng.init(@as(u64, @intFromFloat(@abs(seed) * 65535.0)) ^ (@as(u64, rec) << 20) ^ 0x5EED),
        };
        p.t = seed * 40.0;
        p.rest = REST;
        p.pose();
        return p;
    }

    pub fn bodyR(self: *const Wanderer) f32 {
        return BODY_R * self.scale;
    }

    pub fn topWorld(self: *const Wanderer) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + spec(self.kind).top * H * self.scale, self.pos.z);
    }

    pub fn greet(self: *Wanderer) void {
        self.begin(.beckon);
    }
    pub fn farewell(self: *Wanderer) void {
        self.begin(.bow);
    }

    fn begin(self: *Wanderer, g: Gesture) void {
        self.gesture = g;
        self.gt = 0;
    }

    fn gfrac(self: *const Wanderer) f32 {
        const d = gestureDur(self.gesture);
        return if (d <= 0) 0 else mathx.clampF(self.gt / d, 0, 1);
    }

    pub fn update(self: *Wanderer, dt: f32, heroPos: rl.Vector3, bounds: f32) void {
        self.t += dt;
        self.tickHammer(dt);
        if (self.gesture != .none) {
            self.gt += dt;
            if (self.gt >= gestureDur(self.gesture)) self.gesture = .none;
        }

        const d = mathx.distXZ(self.pos, heroPos);
        const sees = d < NOTICE_R * self.scale;
        if (sees and !self.noticed and !self.talking) self.greet();
        self.noticed = sees;

        const attend = self.talking or sees;
        var moved: f32 = 0;
        var moveYaw: ?f32 = null;
        var speed: f32 = 0;
        if (attend) {
            const to = mathx.dirXZ(self.pos, heroPos);
            if (mathx.lenXZ(to) > 0.001) {
                const bearing = mathx.headingXZ(to);
                if (spec(self.kind).headTrack > 0 and !self.talking) {
                    self.wantYaw = self.postYaw;
                    self.aimHead(bearing, heroPos, dt);
                } else {
                    self.wantYaw = bearing;
                    self.restHead(dt);
                }
            }
            self.dwell = DWELL;
            if (self.talking) {
                self.beat -= dt;
                if (self.beat <= 0) {
                    self.beat = TALK_BEAT;
                    if (self.gesture == .none) self.begin(.point);
                }
            } else self.beat = TALK_BEAT;
        } else if (self.roamR > 0.01) {
            if (self.dwell > 0) {
                self.dwell -= dt;
                self.wantYaw = self.postYaw;
            } else if (mathx.distXZ(self.pos, self.target) <= ARRIVE) {
                self.dwell = DWELL * self.rng.range(0.6, 1.6);
                const a = self.rng.angle();
                const r = self.roamR * @sqrt(self.rng.float());
                self.target = v3(self.home.x + mathx.cosf(a) * r, self.home.y, self.home.z + mathx.sinf(a) * r);
            } else {
                const to = mathx.dirXZ(self.pos, self.target);
                if (mathx.lenXZ(to) > 0.001) {
                    self.wantYaw = mathx.headingXZ(to);
                    if (@abs(mathx.wrapPi(self.wantYaw - self.facing)) < TURN_GATE) {
                        moveYaw = self.wantYaw;
                        speed = AMBLE_SPEED;
                        const step = speed * dt;
                        mathx.stepXZ(&self.pos, to, step, bounds);
                        moved = step;
                    }
                }
            }
        } else {
            self.wantYaw = self.postYaw;
        }

        if (!attend) self.restHead(dt);
        self.facing = mathx.approachAngle(self.facing, self.wantYaw, TURN_RATE * dt);
        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, moved / self.scale, speed, moveYaw, self.facing);
        self.pose();
    }

    fn tickHammer(self: *Wanderer, dt: f32) void {
        self.struck = false;
        if (self.kind != .smith or self.talking or self.moving > 0.15) return;
        const was = self.hammer;
        self.hammer = @mod(self.hammer + dt / HAMMER_PERIOD, 1.0);
        const wrapped = self.hammer < was;
        if ((!wrapped and was < HAMMER_FALL and self.hammer >= HAMMER_FALL) or
            (wrapped and (was < HAMMER_FALL or self.hammer >= HAMMER_FALL))) self.struck = true;
    }

    fn aimHead(self: *Wanderer, want: f32, at: rl.Vector3, dt: f32) void {
        const lim = spec(self.kind).headTrack;
        const off = mathx.degrees(mathx.wrapPi(want - self.facing));
        const eye = self.facePoint();
        const flat = mathx.distXZ(eye, at);
        const dip = mathx.degrees(std.math.atan2(eye.y - (at.y + heromod.H * 0.55), mathx.maxF(flat, 0.2)));
        const step = HEAD_TRACK_RATE * dt;
        self.headYaw = mathx.approach(self.headYaw, mathx.clampF(off, -lim, lim), step);
        self.headDip = mathx.approach(self.headDip, mathx.clampF(dip, 0, spec(self.kind).headDip), step);
    }

    fn restHead(self: *Wanderer, dt: f32) void {
        const step = HEAD_TRACK_RATE * dt;
        self.headYaw = mathx.approach(self.headYaw, 0, step);
        self.headDip = mathx.approach(self.headDip, 0, step);
    }

    fn poseHammer(self: *const Wanderer, wx: *[N]rl.Matrix, rest: [N]rl.Vector3, wonk: f32, m: f32) void {
        const k = self.hammerLift() * (1.0 - m);
        const flex = lerpF(HAM_SH_LO, HAM_SH_HI, k);
        const elbow = lerpF(HAM_EL_LO, HAM_EL_HI, k);
        setLocal(wx, SHR, rest, mul(rx(-flex), rz(-HAM_ABD - wonk * 0.4)));
        setLocal(wx, ELR, rest, rx(-elbow));
        setLocal(wx, WRR, rest, mul(rx(-HAM_WRIST * k), rz(-6.0)));
        // MEASURED at the size he was then, the head swung 1.96 m and topped out at 2.83 m — over his own crown
        // of 2.80 — which is the executioner `HAM_EL_HI`'s note forbids. The arm's own rx down the chain is
        // `-(flex + elbow + wrist)`, and the sign is `necro`'s, measured there.
        setLocal(wx, STAFF, rest, heromod.staffFit(lerpF(HAM_TILT_LO, HAM_TILT_HI, k) - flex - elbow - HAM_WRIST * k));
    }

    /// Height of the head above the anvil, as a share of the raise: 1 at the top, 0 on the face.
    pub fn hammerLift(self: *const Wanderer) f32 {
        return self.liftAt(self.hammer);
    }

    pub fn liftAt(self: *const Wanderer, phase: f32) f32 {
        _ = self;
        const ph = @mod(phase + 1.0, 1.0);
        if (ph < HAMMER_RISE) {
            const u = ph / HAMMER_RISE;
            return 1.0 - (1.0 - u) * (1.0 - u);
        }
        if (ph < HAMMER_FALL) {
            const u = (ph - HAMMER_RISE) / (HAMMER_FALL - HAMMER_RISE);
            return 1.0 - u * u;
        }
        const u = (ph - HAMMER_FALL) / (1.0 - HAMMER_FALL);
        return HAMMER_REBOUND * mathx.sinf(std.math.pi * u) * (1.0 - u);
    }

    pub fn pose(self: *Wanderer) void {
        const fs = self.scale;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        const twoPi = std.math.tau;
        const m = self.moving;
        const wonk = (self.seed - 0.5) * 5.0;

        const still = 1.0 - m;
        const breath = mathx.sinf(self.t * twoPi * BREATH_RATE) * still;
        const shift = mathx.sinf(self.t * twoPi * SHIFT_RATE + self.seed * twoPi) * still;
        const bowK = if (self.gesture == .bow) mathx.sinf(std.math.pi * self.gfrac()) else 0;

        const bob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const sway = heromod.strafeSway(@abs(self.latB) * m, 0) * mathx.sinf(twoPi * self.phase) * m;
        const prot = A_PROT * mathx.sinf(twoPi * self.phase) * m * @abs(self.fwdB) +
            heromod.strafeProt(self.phase, self.latB, m);

        const lean = spec(self.kind).stoop + wonk * 0.6 + 16.0 * bowK;
        const list = shift * A_LIST;
        const listLift = heromod.HIP_HALF * H * @abs(mathx.sinf(mathx.radians(list)));
        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul(ry(prot), rz(list)),
            mul(tr(sway * fs, (hipY + bob + listLift) * fs, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));

        heromod.legPair(&wx, &self.rest, self.pos.y, self.phase, m, 0, self.fwdB, self.latB, HIPL, KNEEL, HIPR, KNEER, solePatches);
        self.poseUpper(&wx, prot, lean, breath, shift, bowK, m);
        self.xf = wx;
    }

    fn poseUpper(self: *Wanderer, wx: *[N]rl.Matrix, prot: f32, lean: f32, breath: f32, shift: f32, bowK: f32, m: f32) void {
        const rest = self.rest;
        const wonk = (self.seed - 0.5) * 5.0;
        const twoPi = std.math.tau;
        const drive: f32 = if (self.kind == .smith) (1.0 - self.hammerLift()) * (1.0 - m) else 0;
        const trunk = lean + HAM_TRUNK * drive;
        const nod = 1.6 * mathx.cosf(2.0 * twoPi * self.phase) * m;

        const lagC = mathx.sinf(twoPi * (self.phase - 0.06)) * m;
        const lagN = mathx.sinf(twoPi * (self.phase - 0.12)) * m;
        setLocal(wx, SPINE, rest, mul3(rx(trunk * 0.42 + nod + breath * A_BREATH * 0.5), ry(-0.35 * prot), rz(wonk * 0.5 - shift * A_LIST * 0.9)));
        setLocal(wx, CHEST, rest, mul3(rx(trunk * 0.58 + breath * A_BREATH), ry(-0.55 * prot + 1.4 * lagC), rz(-wonk * 0.3)));
        const fwd = spec(self.kind).headFwd;
        const neckShare: f32 = 0.34;
        setLocal(wx, NECK, rest, mul(
            rx(fwd * 0.4 + 8.0 * bowK - nod * 0.5 + self.headDip * neckShare),
            ry(self.headYaw * neckShare),
        ));

        const still = 1.0 - m;
        const driftY = mathx.sinf(self.t * twoPi * DRIFT_RATE) * A_DRIFT_YAW * still;
        const driftX = mathx.cosf(self.t * twoPi * DRIFT_RATE * 1.7 + 1.3) * A_DRIFT_PITCH * still;
        const beard: f32 = if (self.kind == .smith)
            BEARD_SWING * (1.0 - self.liftAt(self.hammer - BEARD_LAG)) * (1.0 - m)
        else
            0;
        setLocal(wx, SKULL, rest, mul3(
            rx(fwd * 0.6 + driftX - nod * 0.8 + 22.0 * bowK + beard + self.headDip * (1.0 - neckShare)),
            ry(driftY - prot * 0.4 - 1.2 * lagN + self.headYaw * (1.0 - neckShare)),
            rz(wonk + shift * A_LIST * 1.2),
        ));

        const plantPh = self.phase + 0.5;
        const plant = mathx.maxF(0, mathx.cosf(twoPi * plantPh)) * m;
        const push = STAFF_PLANT_SH * plant;
        const smith = self.kind == .smith;
        if (smith) {
            self.poseHammer(wx, rest, wonk, m);
        } else {
            setLocal(wx, SHR, rest, mul3(rx(-(STAFF_SH + push)), rz(-STAFF_ABD - wonk * 0.4), ry(-4.0 * plant)));
            setLocal(wx, ELR, rest, rx(STAFF_EL - 10.0 * plant));
            setLocal(wx, WRR, rest, rz(-6.0));
            const armPitch = -(STAFF_SH + push) + (STAFF_EL - 10.0 * plant);
            setLocal(wx, STAFF, rest, mul3(
                rz(STAFF_ABD + wonk * 0.4),
                rx(-armPitch - STAFF_TILT - 9.0 * plant),
                rz(wonk * 0.5),
            ));
        }

        const swing = 15.0 * heromod.armSwing(self.phase) * m;
        const atWork: f32 = if (smith) 1.0 - m else 0;
        var sh: f32 = lerpF(FREE_SH, HOLD_SH, atWork) - swing;
        var el: f32 = lerpF(FREE_EL, HOLD_EL, atWork) - mathx.maxF(0, -swing) * 0.8;
        var abd: f32 = lerpF(FREE_ABD, HOLD_ABD, atWork);
        var wrist: f32 = 4.0;
        switch (self.gesture) {
            .none, .bow => {},
            .beckon => {
                const u = self.gfrac();
                const up = mathx.sinf(std.math.pi * u);
                sh -= 52.0 * up;
                abd += 16.0 * up;
                el -= (26.0 + 30.0 * mathx.sinf(twoPi * 2.0 * u)) * up;
                wrist += 14.0 * up;
            },
            .point => {
                const u = self.gfrac();
                const out = mathx.sinf(std.math.pi * u);
                sh -= 62.0 * out;
                el = lerpF(el, -4.0, out);
                abd -= 5.0 * out;
            },
        }
        setLocal(wx, SHL, rest, mul3(rx(-sh), rz(abd + wonk * 0.4), ry(0)));
        setLocal(wx, ELL, rest, rx(-el));
        setLocal(wx, WRL, rest, rz(wrist));
    }
};


fn striped(b: *Builder, c: rl.Vector3, size: rl.Vector3, bands: i32, rng: *mathx.Rng) void {
    const n = @as(f32, @floatFromInt(bands));
    var i: i32 = 0;
    while (i < bands) : (i += 1) {
        const fi = @as(f32, @floatFromInt(i));
        const w = size.y * 2.0 / n * rng.range(1.06, 1.34);
        const y = c.y + size.y - (fi + 0.5) * (size.y * 2.0 / n);
        slab(b, v3(c.x, y, c.z), v3(size.x, w * 0.5, size.z), if (@mod(i, 3) == 1) STRIPE_DK else STRIPE);
    }
}

fn merchPelvisMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xCA30);
    b.setMat(.cloth);
    slab(&b, v3(0, 0.005 * H, 0), v3(0.212 * H, 0.135 * H, 0.158 * H), STRIPE);
    skirt(&b, v3(0, 0.045 * H, 0), 0.185 * H, 0.115 * H, 0.190 * H, 12, STRIPE);
    b.setMat(.leather);
    slab(&b, v3(0, 0.058 * H, 0), v3(0.226 * H, 0.042 * H, 0.170 * H), MADDER);
    slab(&b, v3(0, 0.058 * H, 0.090 * H), v3(0.034 * H, 0.034 * H, 0.010 * H), BRASS);
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const a = rng.range(-2.4, 2.4);
        const r = rng.range(0.030, 0.052) * H;
        const px = mathx.cosf(a) * 0.185 * H;
        const pz = mathx.sinf(a) * 0.140 * H;
        b.addBlob(v3(px, -0.012 * H - r * rng.range(0.4, 1.1), pz), v3(r, r * rng.range(0.85, 1.25), r * 0.72), 4, 8, if (rng.float() < 0.4) LEATHER_LT else LEATHER);
        b.addCylinder(v3(px, 0.040 * H, pz), v3(px, -0.008 * H, pz), 0.006 * H, 0.005 * H, 5, STRAP);
    }
    b.setMat(.gilt);
    b.addBlob(v3(0.150 * H, -0.052 * H, 0.078 * H), v3(0.014 * H, 0.014 * H, 0.005 * H), 3, 8, BRASS);
    return b.toMesh();
}

fn merchAbdomenMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xCA31);
    b.setMat(.cloth);
    striped(&b, v3(0, 0.010 * H, 0), v3(0.208 * H, 0.132 * H, 0.150 * H), 5, &rng);
    b.setMat(.leather);
    slab(&b, v3(0, -0.038 * H, 0.004 * H), v3(0.210 * H, 0.030 * H, 0.150 * H), MADDER);
    b.setMat(.wood);
    b.addCylinder(v3(-0.135 * H, -0.030 * H, 0.070 * H), v3(-0.150 * H, -0.135 * H, 0.062 * H), 0.011 * H, 0.009 * H, 6, WOOD);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const t = (@as(f32, @floatFromInt(i)) + 0.5) / 5.0;
        b.addBlob(
            mathx.lerpV(v3(-0.135 * H, -0.030 * H, 0.070 * H), v3(-0.150 * H, -0.135 * H, 0.062 * H), t),
            v3(0.013 * H, 0.004 * H, 0.013 * H),
            2,
            6,
            WOOD_LT,
        );
    }
    return b.toMesh();
}

fn merchChestMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xCA32);
    b.setMat(.cloth);
    slab(&b, v3(0, -0.005 * H, 0), v3(0.258 * H, 0.118 * H, 0.156 * H), STRIPE);
    striped(&b, v3(0, -0.005 * H, 0), v3(0.262 * H, 0.118 * H, 0.159 * H), 5, &rng);
    // **BEHIND THE SHOULDERS AND BELOW THE HEAD.** At 0.108 up and 0.086 back its crown stood 1.72 m against a
    // skull centred at 1.78 and it read as a second head; 0.052 up and 0.128 back puts it where a hump goes,
    b.setMat(.hide);
    b.addBlob(v3(0.008 * H, 0.052 * H, -0.128 * H), v3(0.112 * H, 0.098 * H, 0.106 * H), 6, 12, HUMP);
    b.addBlob(v3(-0.014 * H, 0.020 * H, -0.160 * H), v3(0.074 * H, 0.062 * H, 0.068 * H), 5, 10, HUMP_LT);
    // The coat on it: A FEW PERCENT OF THE MASS (the relief law). At 0.026 on a 0.112 radius these were a fifth
    var i: i32 = 0;
    while (i < 11) : (i += 1) {
        const a = rng.angle();
        const el = rng.range(-0.2, 1.1);
        const rr = rng.range(0.007, 0.013) * H;
        b.addBlob(
            v3(0.008 * H + mathx.cosf(a) * 0.100 * H * @cos(el), 0.052 * H + 0.086 * H * @sin(el), -0.128 * H + mathx.sinf(a) * 0.094 * H * @cos(el)),
            v3(rr, rr * rng.range(0.7, 1.5), rr * 0.8),
            3,
            7,
            if (rng.float() < 0.5) HUMP_LT else HIDE_DK,
        );
    }
    b.setMat(.leather);
    slab(&b, v3(0.068 * H, -0.010 * H, 0.078 * H), v3(0.030 * H, 0.140 * H, 0.012 * H), STRAP);
    slab(&b, v3(-0.072 * H, -0.004 * H, 0.076 * H), v3(0.026 * H, 0.132 * H, 0.012 * H), STRAP);
    b.setMat(.gilt);
    b.addBlob(v3(0.068 * H, 0.052 * H, 0.086 * H), v3(0.016 * H, 0.016 * H, 0.006 * H), 3, 8, BRASS);
    return b.toMesh();
}

fn merchNeckMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xCA33);
    const top = 0.068 * H + MERCH_NECK;
    b.setMat(.hide);
    b.addCylinder(v3(0, 0, 0), v3(0, top * 0.55, 0.014 * H), 0.040 * H, 0.034 * H, 9, HIDE_DK);
    b.addCylinder(v3(0, top * 0.55, 0.014 * H), v3(0, top, 0.008 * H), 0.034 * H, 0.030 * H, 9, HIDE);
    b.addDome(v3(0, top, 0.008 * H), v3(0, 1, 0), 0.030 * H, 8, HIDE);
    var i: i32 = 0;
    while (i < 8) : (i += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / 8.0 + rng.signed() * 0.2;
        const rr = rng.range(0.016, 0.030) * H;
        b.addBlob(
            v3(mathx.cosf(a) * 0.040 * H, rng.range(0.004, 0.030) * H, mathx.sinf(a) * 0.036 * H),
            v3(rr, rr * rng.range(0.9, 1.7), rr * 0.9),
            3,
            7,
            if (@mod(i, 2) == 0) HUMP else HUMP_LT,
        );
    }
    b.setMat(.cloth);
    b.addCylinder(v3(0, 0.006 * H, 0), v3(0, 0.032 * H, 0.004 * H), 0.046 * H, 0.042 * H, 9, STRIPE);
    return b.toMesh();
}

fn merchHeadMesh(wrapped: bool) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (wrapped) 0xCA34 else 0xCA35);
    const y = MERCH_NECK;
    b.setMat(.hide);
    b.addBlob(v3(0, y + 0.074 * H, -0.014 * H), v3(0.058 * H, 0.062 * H, 0.070 * H), 6, 10, HIDE);
    b.addBlob(v3(0, y + 0.056 * H, 0.040 * H), v3(0.048 * H, 0.046 * H, 0.058 * H), 5, 10, HIDE);
    b.addCapsule(v3(0, y + 0.058 * H, 0.062 * H), v3(0, y + 0.036 * H, 0.132 * H), 0.040 * H, 0.028 * H, 9, HIDE);
    b.addBlob(v3(0, y + 0.033 * H, 0.140 * H), v3(0.030 * H, 0.026 * H, 0.024 * H), 4, 9, MUZZLE);
    for ([_]f32{ -1.0, 1.0 }) |side| {
        b.addBlob(v3(side * 0.014 * H, y + 0.024 * H, 0.146 * H), v3(0.014 * H, 0.014 * H, 0.013 * H), 3, 8, MUZZLE);
    }
    for ([_]f32{ -1.0, 1.0 }) |side| {
        b.addCapsule(
            v3(side * 0.020 * H, y + 0.046 * H, 0.136 * H),
            v3(side * 0.024 * H, y + 0.036 * H, 0.138 * H),
            0.006 * H,
            0.004 * H,
            5,
            HOOF,
        );
    }
    b.addBlob(v3(0, y + 0.092 * H, 0.038 * H), v3(0.056 * H, 0.020 * H, 0.040 * H), 4, 9, HIDE_DK);
    for ([_]f32{ -1.0, 1.0 }) |side| {
        b.addBlob(v3(side * 0.046 * H, y + 0.074 * H, 0.030 * H), v3(0.015 * H, 0.016 * H, 0.014 * H), 3, 8, HOOF);
        b.addBlob(v3(side * 0.049 * H, y + 0.077 * H, 0.034 * H), v3(0.007 * H, 0.007 * H, 0.006 * H), 3, 6, MUZZLE);
        var l: i32 = 0;
        while (l < 3) : (l += 1) {
            const fl = @as(f32, @floatFromInt(l)) - 1.0;
            const from = v3(side * (0.044 * H + fl * 0.006 * H), y + 0.086 * H, 0.030 * H + fl * 0.004 * H);
            b.addCapsule(from, mathx.addV(from, v3(side * 0.008 * H, 0.020 * H, 0.014 * H)), 0.0035 * H, 0.0015 * H, 4, LASH);
        }
        b.addBlob(v3(side * 0.050 * H, y + 0.098 * H, -0.038 * H), v3(0.012 * H, 0.020 * H, 0.010 * H), 3, 7, HIDE_DK);
    }
    if (wrapped) {
        b.setMat(.cloth);
        b.addBlob(v3(0, y + 0.096 * H, -0.020 * H), v3(0.072 * H, 0.054 * H, 0.080 * H), 5, 11, STRIPE);
        for ([_]f32{ -1.0, 1.0 }) |side| {
            const drop = if (side > 0) 0.052 * H else 0.104 * H;
            b.addCapsule(
                v3(side * 0.056 * H, y + 0.092 * H, -0.016 * H),
                v3(side * 0.062 * H, y + 0.092 * H - drop, -0.006 * H),
                0.030 * H,
                0.024 * H,
                7,
                STRIPE,
            );
        }
        b.addCapsule(v3(0, y + 0.094 * H, -0.052 * H), v3(0, y + 0.020 * H, -0.062 * H), 0.048 * H, 0.036 * H, 9, STRIPE_DK);
        b.addBlob(v3(0, y + 0.104 * H, -0.052 * H), v3(0.050 * H, 0.028 * H, 0.040 * H), 4, 9, MADDER);
        b.setMat(.leather);
        b.addCylinder(v3(-0.062 * H, y + 0.098 * H, 0), v3(0.062 * H, y + 0.098 * H, 0), 0.007 * H, 0.007 * H, 6, STRAP);
    } else {
        b.setMat(.cloth);
        b.addCylinder(v3(0, y + 0.112 * H, -0.016 * H), v3(0, y + 0.148 * H, -0.020 * H), 0.050 * H, 0.046 * H, 10, MADDER);
        b.addDome(v3(0, y + 0.148 * H, -0.020 * H), v3(0, 1, 0), 0.046 * H, 10, MADDER_LT);
        b.setMat(.hide);
        var t: i32 = 0;
        while (t < 5) : (t += 1) {
            const a = rng.angle();
            const rr = rng.range(0.010, 0.020) * H;
            b.addBlob(v3(mathx.cosf(a) * 0.030 * H, y + 0.112 * H, -0.016 * H + mathx.sinf(a) * 0.028 * H), v3(rr, rr * 1.4, rr), 3, 7, HUMP);
        }
    }
    return b.toMesh();
}

fn merchThighMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCylinder(v3(0, 0, 0), v3(0, -0.070 * H, 0), 0.068 * H, 0.050 * H, 9, STRIPE);
    b.addDome(v3(0, 0, 0), v3(0, 1, 0), 0.068 * H, 9, STRIPE);
    b.setMat(.hide);
    b.addCylinder(v3(0, -0.066 * H, 0), v3(0, -heromod.SEG_THIGH * H, 0), 0.044 * H, 0.034 * H, 9, HIDE_DK);
    return b.toMesh();
}

fn merchShankMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    b.addBlob(v3(0, -0.006 * H, 0.008 * H), v3(0.040 * H, 0.034 * H, 0.036 * H), 4, 9, HIDE_DK);
    b.addCylinder(v3(0, -0.020 * H, 0), v3(0, -heromod.SEG_SHANK * H, 0), 0.030 * H, 0.026 * H, 9, HIDE);
    b.setMat(.cloth);
    for ([_]f32{ 0.30, 0.52, 0.74 }) |t| {
        const yy = -heromod.SEG_SHANK * H * t;
        b.addCylinder(v3(0, yy, 0), v3(0, yy - 0.022 * H, 0), 0.032 * H, 0.031 * H, 9, if (t > 0.5) LINEN_DK else LINEN);
    }
    return b.toMesh();
}

fn merchFootMesh() rl.Mesh {
    var b = Builder.init();
    const ay = 0.039 * H;
    b.setMat(.hide);
    b.addBlob(v3(0, -ay + 0.026 * H, 0.038 * H), v3(0.084 * H, 0.026 * H, 0.150 * H), 4, 11, HIDE_DK);
    b.addBlob(v3(0, -ay + 0.062 * H, -0.014 * H), v3(0.062 * H, 0.044 * H, 0.070 * H), 4, 9, HIDE);
    b.setMat(.leather);
    for ([_]f32{ -1.0, 1.0 }) |side| {
        b.addBlob(v3(side * 0.034 * H, -ay + 0.022 * H, 0.126 * H), v3(0.036 * H, 0.022 * H, 0.040 * H), 3, 8, HOOF);
    }
    return b.toMesh();
}

fn merchSleeveMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addBlob(v3(0, 0.002 * H, 0), v3(0.052 * H, 0.046 * H, 0.050 * H), 4, 9, STRIPE);
    b.addCylinder(v3(0, 0, 0), v3(0, -heromod.SEG_UPARM * H, 0), 0.054 * H, 0.042 * H, 9, STRIPE);
    return b.toMesh();
}

fn merchForearmMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    b.addCylinder(v3(0, 0, 0), v3(0, -heromod.SEG_FOREARM * H, 0), 0.038 * H, 0.028 * H, 9, HIDE);
    b.setMat(.gilt);
    for ([_]f32{ 0.34, 0.50, 0.80 }) |t| {
        const yy = -heromod.SEG_FOREARM * H * t;
        b.addCylinder(v3(0, yy, 0), v3(0, yy - 0.008 * H, 0), 0.037 * H, 0.036 * H, 9, BRASS);
    }
    return b.toMesh();
}

fn merchHandMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    b.addBlob(v3(0, -0.040 * H, 0.004 * H), v3(0.026 * H, 0.045 * H, 0.021 * H), 4, 8, HIDE);
    b.addBlob(v3(0.014 * H, -0.020 * H, 0.008 * H), v3(0.013 * H, 0.020 * H, 0.014 * H), 3, 7, HIDE_DK);
    return b.toMesh();
}

const SCALE_ARM: f32 = 0.115 * H;
const SCALE_DROP: f32 = 0.105 * H;
fn scaleBeamMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xCA36);
    const grip = 0.070 * H;
    b.setMat(.wood);
    b.addCylinder(v3(0, 0, 0), v3(0, -grip, 0), 0.011 * H, 0.010 * H, 6, WOOD);
    b.setMat(.gilt);
    const tilt = mathx.radians(rng.range(5.0, 9.0));
    const dy = SCALE_ARM * mathx.sinf(tilt);
    b.addCylinder(v3(-SCALE_ARM, -grip - dy, 0), v3(SCALE_ARM, -grip + dy, 0), 0.006 * H, 0.006 * H, 6, BRASS);
    b.addBlob(v3(0, -grip, 0), v3(0.013 * H, 0.013 * H, 0.011 * H), 3, 8, BRASS);
    for ([_]f32{ -1.0, 1.0 }) |side| {
        const ex = side * SCALE_ARM;
        const ey = -grip + side * dy;
        const drop = SCALE_DROP * (if (side > 0) @as(f32, 1.0) else 0.86);
        var i: i32 = 0;
        while (i < 3) : (i += 1) {
            const a = std.math.tau * @as(f32, @floatFromInt(i)) / 3.0;
            b.addCapsule(
                v3(ex, ey, 0),
                v3(ex + mathx.cosf(a) * 0.026 * H, ey - drop, mathx.sinf(a) * 0.026 * H),
                0.0022 * H,
                0.0022 * H,
                4,
                BRASS,
            );
        }
        b.addBlob(v3(ex, ey - drop - 0.006 * H, 0), v3(0.030 * H, 0.008 * H, 0.030 * H), 3, 10, BRASS);
        if (side > 0) {
            b.setMat(.stone);
            b.addBlob(v3(ex, ey - drop + 0.008 * H, 0), v3(0.014 * H, 0.010 * H, 0.014 * H), 3, 7, HOOF);
            b.setMat(.gilt);
        }
    }
    return b.toMesh();
}

pub const solePatches = heromod.BOOT_SOLE;

pub const CAP: usize = wf.MAX_NPCS;

pub const Folk = struct {
    model: Model = undefined,
    list: [CAP]Wanderer = undefined,
    n: usize = 0,
    near: ?usize = null,

    pub fn init(shader: rl.Shader) Folk {
        return .{ .model = Model.init(shader) };
    }
    pub fn setShader(self: *Folk, sh: rl.Shader) void {
        self.model.setShader(sh);
    }

    pub fn live(self: *Folk) []Wanderer {
        return self.list[0..self.n];
    }
    pub fn liveConst(self: *const Folk) []const Wanderer {
        return self.list[0..self.n];
    }

    pub fn at(self: *Folk, i: usize) ?*Wanderer {
        return if (i < self.n) &self.list[i] else null;
    }
    pub fn atConst(self: *const Folk, i: usize) ?*const Wanderer {
        return if (i < self.n) &self.list[i] else null;
    }

    /// POSTED FROM THE MAP, on the ground the map's own height field puts under them — a spawn table stores x/z only, and dropping a man at y = 0 on a sculpted rise buries him to the waist (`foe.resetGroup`).
    pub fn reset(self: *Folk, m: *const wf.Map) void {
        self.n = 0;
        self.near = null;
        for (m.npcSlice(), 0..) |p, i| {
            if (self.n >= CAP) break;
            self.list[self.n] = Wanderer.spawnAs(
                p.kind,
                @intCast(i),
                v3(p.x, m.heightAt(p.x, p.z), p.z),
                mathx.radians(p.yaw),
                p.scale,
                p.seed,
                p.roam,
            );
            self.n += 1;
        }
    }

    pub fn update(self: *Folk, dt: f32, heroPos: rl.Vector3, bounds: f32) void {
        var near = mathx.Nearest.within(REACH);
        for (self.live(), 0..) |*p, i| {
            p.update(dt, heroPos, bounds);
            near.offer(i, p.pos, heroPos);
        }
        self.near = near.best;
    }

    pub fn positions(self: *const Folk, m: *const wf.Map, out: []rl.Vector3) []const rl.Vector3 {
        const n = @min(m.nnpcs, out.len);
        for (0..n) |i| {
            const rec = &m.npcs[i];
            out[i] = v3(rec.x, m.heightAt(rec.x, rec.z), rec.z);
        }
        for (self.liveConst()) |*p| {
            if (p.rec < n) out[p.rec] = p.pos;
        }
        return out[0..n];
    }

    pub fn draw(self: *const Folk) void {
        for (self.liveConst()) |*p| self.model.draw(p);
    }

    pub fn drawOne(self: *const Folk, i: usize) void {
        if (i >= self.n) return;
        self.model.draw(&self.list[i]);
    }

    pub fn hush(self: *Folk) void {
        for (self.live()) |*p| p.talking = false;
    }
};

pub fn nameOf(m: *const wf.Map, rec: u16) []const u8 {
    if (rec >= m.nnpcs) return wf.npcName(.wanderer);
    const p = &m.npcs[rec];
    const s = m.spanText(p.call);
    return if (s.len > 0) s else wf.npcName(p.kind);
}



const slab = heromod.slab;

fn skirt(b: *Builder, top: rl.Vector3, drop: f32, rTop: f32, rBot: f32, sides: i32, col: rl.Color) void {
    b.addCylinder(top, v3(top.x, top.y - drop, top.z), rTop, rBot, sides, col);
    b.addBlob(v3(top.x, top.y - drop, top.z), v3(rBot, rBot * 0.28, rBot), 3, sides, col);
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    slab(&b, v3(0, 0.005 * H, 0), v3(0.215 * H, 0.14 * H, 0.16 * H), ROBE);
    skirt(&b, v3(0, 0.045 * H, 0), 0.30 * H, 0.115 * H, 0.205 * H, 12, ROBE_DK);
    slab(&b, v3(0.02 * H, -0.14 * H, 0.098 * H), v3(0.09 * H, 0.20 * H, 0.012 * H), ROBE_LT);
    slab(&b, v3(-0.10 * H, -0.115 * H, -0.055 * H), v3(0.075 * H, 0.145 * H, 0.014 * H), ROBE);
    b.setMat(.leather);
    slab(&b, v3(0, 0.055 * H, 0), v3(0.222 * H, 0.038 * H, 0.166 * H), LEATHER);
    slab(&b, v3(0, 0.055 * H, 0.086 * H), v3(0.03 * H, 0.03 * H, 0.010 * H), LEATHER_LT);
    slab(&b, v3(-0.10 * H, -0.01 * H, -0.028 * H), v3(0.058 * H, 0.07 * H, 0.05 * H), LEATHER);
    slab(&b, v3(-0.10 * H, 0.022 * H, -0.028 * H), v3(0.062 * H, 0.018 * H, 0.056 * H), LEATHER_LT);
    b.setMat(.wood);
    b.addBlob(v3(0.10 * H, -0.02 * H, -0.03 * H), v3(0.042 * H, 0.05 * H, 0.038 * H), 5, 8, GOURD);
    b.addCylinder(v3(0.10 * H, 0.026 * H, -0.03 * H), v3(0.10 * H, 0.05 * H, -0.03 * H), 0.014 * H, 0.011 * H, 7, WOOD);
    b.addDome(v3(0.10 * H, 0.05 * H, -0.03 * H), v3(0, 1, 0), 0.012 * H, 7, WOOD_LT);
    return b.toMesh();
}

fn abdomenMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    slab(&b, v3(0, -0.005 * H, 0), v3(0.20 * H, 0.13 * H, 0.145 * H), ROBE);
    slab(&b, v3(0, 0.072 * H, 0), v3(0.228 * H, 0.085 * H, 0.155 * H), ROBE);
    slab(&b, v3(0, -0.035 * H, 0.005 * H), v3(0.212 * H, 0.032 * H, 0.152 * H), SASH);
    slab(&b, v3(0.05 * H, -0.075 * H, 0.078 * H), v3(0.038 * H, 0.075 * H, 0.011 * H), SASH);
    return b.toMesh();
}

fn chestMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    slab(&b, v3(0, -0.005 * H, 0), v3(0.265 * H, 0.12 * H, 0.16 * H), ROBE);
    skirt(&b, v3(0, 0.058 * H, -0.004 * H), 0.082 * H, 0.088 * H, 0.158 * H, 12, CLOAK);
    skirt(&b, v3(0.030 * H, 0.052 * H, -0.012 * H), 0.132 * H, 0.070 * H, 0.118 * H, 11, CLOAK_DK);
    slab(&b, v3(0.072 * H, -0.048 * H, 0.076 * H), v3(0.048 * H, 0.150 * H, 0.013 * H), CLOAK_LT);
    slab(&b, v3(-0.078 * H, -0.038 * H, 0.074 * H), v3(0.044 * H, 0.130 * H, 0.013 * H), CLOAK);
    b.setMat(.steel);
    b.addBlob(v3(0, 0.048 * H, 0.070 * H), v3(0.016 * H, 0.016 * H, 0.006 * H), 3, 8, IRON);
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCylinder(v3(0, 0, 0), v3(0, 0.068 * H, 0), 0.037 * H, 0.034 * H, 8, SKIN_DK);
    b.addDome(v3(0, 0.068 * H, 0), v3(0, 1, 0), 0.034 * H, 8, SKIN_DK);
    b.setMat(.cloth);
    b.addCylinder(v3(0, 0.004 * H, 0), v3(0, 0.030 * H, 0), 0.042 * H, 0.038 * H, 9, LINEN);
    return b.toMesh();
}

fn hoodedHeadMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, 0.072 * H, -0.004 * H), v3(0.068 * H, 0.078 * H, 0.076 * H), 6, 10, SKIN_DK);
    b.addBlob(v3(0, 0.050 * H, 0.074 * H), v3(0.014 * H, 0.017 * H, 0.020 * H), 3, 7, SKIN_DK);
    b.setMat(.leather);
    b.addBlob(v3(0, 0.026 * H, 0.056 * H), v3(0.044 * H, 0.032 * H, 0.038 * H), 4, 8, BEARD);
    b.setMat(.cloth);
    b.addBlob(v3(0, 0.080 * H, -0.014 * H), v3(0.086 * H, 0.092 * H, 0.094 * H), 6, 11, CLOAK);
    slab(&b, v3(0, 0.128 * H, -0.030 * H), v3(0.058 * H, 0.036 * H, 0.070 * H), CLOAK_LT);
    slab(&b, v3(0.062 * H, 0.078 * H, -0.006 * H), v3(0.024 * H, 0.120 * H, 0.090 * H), CLOAK_DK);
    b.addBlob(v3(0, 0.066 * H, 0.048 * H), v3(0.066 * H, 0.068 * H, 0.020 * H), 4, 10, CLOAK_LT);
    b.addBlob(v3(0, 0.062 * H, 0.052 * H), v3(0.058 * H, 0.060 * H, 0.030 * H), 4, 9, HOOD_IN);
    skirt(&b, v3(0, 0.012 * H, 0), 0.058 * H, 0.062 * H, 0.104 * H, 11, CLOAK_DK);
    return b.toMesh();
}

fn bareHeadMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, 0.074 * H, -0.006 * H), v3(0.070 * H, 0.082 * H, 0.078 * H), 6, 10, SKIN);
    b.addBlob(v3(0, 0.028 * H, 0.020 * H), v3(0.052 * H, 0.040 * H, 0.058 * H), 5, 9, SKIN);
    b.addBlob(v3(0, 0.058 * H, 0.070 * H), v3(0.015 * H, 0.019 * H, 0.020 * H), 3, 7, SKIN_DK);
    b.setMat(.leather);
    b.addBlob(v3(0, 0.108 * H, -0.020 * H), v3(0.074 * H, 0.048 * H, 0.080 * H), 5, 9, HAIR);
    slab(&b, v3(0, 0.048 * H, -0.084 * H), v3(0.062 * H, 0.090 * H, 0.030 * H), HAIR);
    b.addBlob(v3(0, 0.014 * H, 0.036 * H), v3(0.050 * H, 0.046 * H, 0.044 * H), 5, 9, BEARD);
    b.setMat(.cloth);
    b.addBlob(v3(0, 0.026 * H, -0.078 * H), v3(0.062 * H, 0.052 * H, 0.040 * H), 4, 9, CLOAK_DK);
    skirt(&b, v3(0, 0.012 * H, 0), 0.050 * H, 0.058 * H, 0.098 * H, 11, CLOAK_DK);
    return b.toMesh();
}

fn thighMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCylinder(v3(0, 0, 0), v3(0, -heromod.SEG_THIGH * H, 0), 0.070 * H, 0.056 * H, 9, ROBE_DK);
    b.addDome(v3(0, 0, 0), v3(0, 1, 0), 0.070 * H, 9, ROBE_DK);
    return b.toMesh();
}

fn shankMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCylinder(v3(0, 0, 0), v3(0, -0.105 * H, 0), 0.054 * H, 0.048 * H, 9, ROBE_DK);
    b.setMat(.leather);
    b.addCylinder(v3(0, -0.100 * H, 0), v3(0, -heromod.SEG_SHANK * H, 0), 0.050 * H, 0.036 * H, 9, LEATHER);
    slab(&b, v3(0, -0.155 * H, 0.006 * H), v3(0.052 * H, 0.016 * H, 0.050 * H), LEATHER_LT);
    return b.toMesh();
}

/// THE BOOT IS THE HERO'S FOOTPRINT EXACTLY — z −0.05·H…+0.14·H, x ±0.0425·H, sole on the ankle plane. Not a style choice: the gait curves plantarflex the ankle to a fixed angle at toe-off, so a longer toe is a longer lever below the plane and `legChain` can only level the ankle, never lift the body off it.
fn footMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.leather);
    const ay = 0.039 * H;
    slab(&b, v3(0, -ay + 0.028 * H, 0.045 * H), v3(0.085 * H, 0.056 * H, 0.190 * H), BOOT);
    slab(&b, v3(0, -ay + 0.075 * H, -0.020 * H), v3(0.075 * H, 0.050 * H, 0.090 * H), BOOT);
    return b.toMesh();
}

fn sleeveMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addBlob(v3(0, 0.002 * H, 0), v3(0.050 * H, 0.044 * H, 0.048 * H), 4, 9, ROBE);
    b.addCylinder(v3(0, 0, 0), v3(0, -heromod.SEG_UPARM * H, 0), 0.052 * H, 0.044 * H, 9, ROBE);
    return b.toMesh();
}

fn forearmMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCylinder(v3(0, 0, 0), v3(0, -0.058 * H, 0), 0.044 * H, 0.038 * H, 9, ROBE);
    b.addCylinder(v3(0, -0.055 * H, 0), v3(0, -heromod.SEG_FOREARM * H, 0), 0.038 * H, 0.030 * H, 9, LINEN);
    b.addCylinder(v3(0, -0.072 * H, 0), v3(0, -0.088 * H, 0), 0.039 * H, 0.037 * H, 9, LINEN_DK);
    b.addCylinder(v3(0, -0.112 * H, 0), v3(0, -0.126 * H, 0), 0.034 * H, 0.032 * H, 9, LINEN_DK);
    return b.toMesh();
}

fn handMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, -0.040 * H, 0.004 * H), v3(0.026 * H, 0.045 * H, 0.021 * H), 4, 8, SKIN);
    b.addBlob(v3(0.014 * H, -0.020 * H, 0.008 * H), v3(0.013 * H, 0.020 * H, 0.014 * H), 3, 7, SKIN_DK);
    return b.toMesh();
}


fn barkLimb(b: *Builder, rng: *mathx.Rng, a: rl.Vector3, c: rl.Vector3, ra: f32, rb: f32, ribs: i32, tone: rl.Color) void {
    b.addCapsule(a, c, ra, rb, 9, tone);
    const d = mathx.subV(c, a);
    const len = mathx.lenV(d);
    if (len < 1e-4) return;
    const up = mathx.scaleV(d, 1.0 / len);
    var side = mathx.normV(mathx.crossV(up, v3(0, 0, 1)));
    if (mathx.lenV(side) < 0.5) side = v3(1, 0, 0);
    const other = mathx.normV(mathx.crossV(up, side));
    var i: i32 = 0;
    while (i < ribs) : (i += 1) {
        const ang = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(ribs)) + rng.range(-0.3, 0.3);
        const off = mathx.addV(mathx.scaleV(side, mathx.cosf(ang)), mathx.scaleV(other, mathx.sinf(ang)));
        const t0 = rng.range(0.02, 0.22);
        const t1 = rng.range(0.72, 0.99);
        const p0 = mathx.addV(mathx.lerpV(a, c, t0), mathx.scaleV(off, ra * 0.86));
        const p1 = mathx.addV(mathx.lerpV(a, c, t1), mathx.scaleV(mathx.normV(mathx.addV(off, mathx.scaleV(side, rng.signed() * 0.5))), rb * 0.88));
        b.addCapsule(p0, p1, ra * rng.range(0.13, 0.21), rb * rng.range(0.10, 0.17), 5, if (rng.float() < 0.4) BARKS_LT else BARKS_DK);
    }
}

fn smithPelvisMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5B01);
    b.setMat(.bark);
    b.addBlob(v3(0, 0.010 * H, 0), v3(0.235 * H, 0.150 * H, 0.185 * H), 6, 11, BARKS);
    for ([_]f32{ -1, 1 }) |sx| {
        barkLimb(&b, &rng, v3(sx * 0.070 * H, 0.070 * H, 0), v3(sx * 0.150 * H, -0.070 * H, rng.signed() * 0.03 * H), 0.075 * H, 0.095 * H, 3, BARKS);
    }
    b.setMat(.leather);
    slab(&b, v3(0, -0.055 * H, 0.150 * H), v3(0.175 * H, 0.205 * H, 0.020 * H), APRON);
    slab(&b, v3(0, 0.055 * H, 0.150 * H), v3(0.185 * H, 0.030 * H, 0.026 * H), APRON_LT);
    b.setMat(.steel);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        b.addBlob(v3(rng.range(-0.14, 0.14) * H, -0.235 * H + rng.signed() * 0.012 * H, 0.166 * H), v3(0.008 * H, 0.008 * H, 0.005 * H), 2, 6, SIRON_LT);
    }
    return b.toMesh();
}

fn smithAbdomenMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5B02);
    b.setMat(.bark);
    b.addBlob(v3(0, 0.010 * H, 0), v3(0.215 * H, 0.140 * H, 0.170 * H), 6, 11, BARKS);
    var k: i32 = 0;
    while (k < 3) : (k += 1) {
        const y = (-0.060 + 0.062 * @as(f32, @floatFromInt(k))) * H;
        b.addCylinder(v3(0, y - 0.010 * H, 0), v3(0, y + 0.010 * H, 0), 0.208 * H, 0.212 * H, 12, if (k == 1) BARKS_LT else BARKS_DK);
    }
    b.setMat(.leather);
    slab(&b, v3(0, -0.020 * H, 0.160 * H), v3(0.170 * H, 0.140 * H, 0.018 * H), APRON);
    for ([_]f32{ -1, 1 }) |sx| {
        slab(&b, v3(sx * 0.090 * H, 0.075 * H, 0.150 * H), v3(0.028 * H, 0.075 * H, 0.020 * H), APRON_LT);
    }
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const a = rng.range(1.9, 4.4);
        const rr = rng.range(0.022, 0.040) * H;
        b.addBlob(v3(mathx.cosf(a) * 0.19 * H, rng.range(-0.09, 0.10) * H, mathx.sinf(a) * 0.15 * H), v3(rr, rr * 0.6, rr), 3, 7, SMOSS);
    }
    return b.toMesh();
}

fn smithChestMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5B03);
    b.setMat(.bark);
    b.addBlob(v3(0, 0.005 * H, 0), v3(0.300 * H, 0.135 * H, 0.185 * H), 6, 12, BARKS);
    for ([_]f32{ -1, 1 }) |sx| {
        b.addBlob(v3(sx * 0.235 * H, 0.048 * H, 0), v3(0.105 * H, 0.100 * H, 0.115 * H), 5, 10, BARKS_DK);
    }
    b.setMat(.plain);
    var k: i32 = 0;
    while (k < 6) : (k += 1) {
        const t = @as(f32, @floatFromInt(k)) / 5.0;
        const y = lerpF(-0.110, 0.100, t) * H;
        b.addBlob(v3(rng.signed() * 0.018 * H, y, 0.170 * H), v3(0.030 * H * (1.0 - 0.4 * @abs(t - 0.45)), 0.028 * H, 0.014 * H), 3, 7, if (@mod(k, 2) == 0) HEART else HEART_DK);
    }
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const a = rng.range(2.0, 4.3);
        const rr = rng.range(0.026, 0.050) * H;
        b.addBlob(v3(mathx.cosf(a) * 0.26 * H, rng.range(-0.06, 0.09) * H, mathx.sinf(a) * 0.16 * H), v3(rr, rr * 0.55, rr), 3, 7, if (rng.float() < 0.5) SMOSS else LICHEN_DK);
    }
    return b.toMesh();
}

fn smithNeckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.bark);
    b.addCylinder(v3(0, 0, 0), v3(0, 0.062 * H, 0), 0.072 * H, 0.066 * H, 9, BARKS_DK);
    b.addDome(v3(0, 0.062 * H, 0), v3(0, 1, 0), 0.066 * H, 9, BARKS_DK);
    return b.toMesh();
}

fn burlHeadMesh(forked: bool) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (forked) 0x5B11 else 0x5B10);
    b.setMat(.bark);
    b.addBlob(v3(0, 0.070 * H, -0.004 * H), v3(0.098 * H, 0.104 * H, 0.100 * H), 6, 11, BARKS);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const a = rng.angle();
        const e = rng.range(-0.2, 1.1);
        const rr = rng.range(0.020, 0.042) * H;
        b.addBlob(
            v3(mathx.cosf(a) * 0.088 * H, 0.070 * H + e * 0.070 * H, mathx.sinf(a) * 0.088 * H - 0.004 * H),
            v3(rr, rr * 0.8, rr),
            3,
            7,
            if (rng.float() < 0.5) BARKS_LT else BARKS_DK,
        );
    }
    barkLimb(&b, &rng, v3(0.052 * H, 0.140 * H, -0.030 * H), v3(0.115 * H, 0.212 * H, -0.070 * H), 0.024 * H, 0.011 * H, 2, BARKS_DK);
    b.addBlob(v3(0, 0.086 * H, 0.070 * H), v3(0.088 * H, 0.026 * H, 0.032 * H), 4, 9, BARKS_LT);
    b.setMat(.ember);
    for ([_]f32{ -1, 1 }) |sx| {
        b.addBlob(v3(sx * 0.040 * H, 0.062 * H, 0.078 * H), v3(0.017 * H, 0.014 * H, 0.010 * H), 3, 7, EYE);
    }
    b.setMat(.bark);
    b.addBlob(v3(0, 0.014 * H, 0.086 * H), v3(0.046 * H, 0.009 * H, 0.012 * H), 3, 7, BARKS_DK);
    b.setMat(.plant);
    const ropes: usize = if (forked) 4 else 2;
    var r: usize = 0;
    while (r < ropes) : (r += 1) {
        const side: f32 = if (r % 2 == 0) -1.0 else 1.0;
        const outer: f32 = if (r < 2) 1.0 else 0.62;
        var p = v3(side * 0.044 * H * outer, 0.014 * H, 0.078 * H);
        var dir = mathx.normV(v3(side * 0.30, -1.0, 0.34));
        const segs: usize = 5;
        var s: usize = 0;
        while (s < segs) : (s += 1) {
            const t = @as(f32, @floatFromInt(s)) / @as(f32, segs);
            const seg = (0.036 + 0.010 * t) * H * outer;
            dir = mathx.normV(mathx.addV(dir, v3(side * 0.06, -0.05, -0.11)));
            const nxt = mathx.addV(p, mathx.scaleV(dir, seg));
            const rr = lerpF(0.020, 0.008, t) * H * outer;
            b.addCapsule(p, nxt, rr, rr * 0.82, 6, if (s % 2 == 0) LICHEN else LICHEN_DK);
            var f: i32 = 0;
            while (f < 2) : (f += 1) {
                const a = rng.angle();
                b.addCapsule(
                    p,
                    mathx.addV(p, v3(mathx.cosf(a) * rr * 2.4, rng.range(-0.024, -0.006) * H, mathx.sinf(a) * rr * 2.4)),
                    rr * 0.42,
                    rr * 0.20,
                    4,
                    LICHEN_PALE,
                );
            }
            p = nxt;
        }
    }
    for ([_]f32{ -1, 1 }) |sx| {
        b.addCapsule(v3(sx * 0.020 * H, 0.094 * H, 0.086 * H), v3(sx * 0.078 * H, 0.086 * H, 0.070 * H), 0.014 * H, 0.008 * H, 5, LICHEN_DK);
    }
    return b.toMesh();
}

fn smithThighMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5B04);
    b.setMat(.bark);
    barkLimb(&b, &rng, v3(0, 0, 0), v3(0, -heromod.SEG_THIGH * H, 0), 0.098 * H, 0.078 * H, 4, BARKS);
    b.addDome(v3(0, 0, 0), v3(0, 1, 0), 0.098 * H, 9, BARKS);
    return b.toMesh();
}

fn smithShankMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5B05);
    b.setMat(.bark);
    barkLimb(&b, &rng, v3(0, 0, 0), v3(0, -heromod.SEG_SHANK * H, 0), 0.076 * H, 0.062 * H, 3, BARKS_DK);
    return b.toMesh();
}

/// every one of them stays inside z −0.05·H…+0.14·H with its sole on the plane.
fn smithFootMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5B06);
    b.setMat(.bark);
    const ay = 0.039 * H;
    b.addBlob(v3(0, -ay + 0.040 * H, 0.030 * H), v3(0.090 * H, 0.056 * H, 0.100 * H), 5, 10, BARKS);
    const toes = [_][3]f32{ .{ -0.062, 0.130, 0.020 }, .{ 0.0, 0.140, 0.016 }, .{ 0.062, 0.126, 0.020 }, .{ -0.070, -0.042, 0.018 }, .{ 0.070, -0.046, 0.018 } };
    for (toes) |t| {
        b.addCapsule(
            v3(t[0] * H * 0.5, -ay + 0.042 * H, t[1] * H * 0.35),
            v3(t[0] * H, -ay + t[2] * H, t[1] * H),
            0.030 * H,
            t[2] * H * rng.range(0.85, 1.05),
            7,
            if (rng.float() < 0.4) BARKS_LT else BARKS_DK,
        );
    }
    return b.toMesh();
}

fn smithUpperArmMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5B07);
    b.setMat(.bark);
    b.addBlob(v3(0, 0.004 * H, 0), v3(0.082 * H, 0.072 * H, 0.078 * H), 5, 10, BARKS);
    barkLimb(&b, &rng, v3(0, 0, 0), v3(0, -heromod.SEG_UPARM * H, 0), 0.076 * H, 0.062 * H, 3, BARKS);
    return b.toMesh();
}

fn smithForearmMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5B08);
    b.setMat(.bark);
    barkLimb(&b, &rng, v3(0, 0, 0), v3(0, -heromod.SEG_FOREARM * H, 0), 0.066 * H, 0.052 * H, 3, BARKS);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / 5.0;
        b.addCapsule(
            v3(mathx.cosf(a) * 0.052 * H, -0.100 * H, mathx.sinf(a) * 0.052 * H),
            v3(mathx.cosf(a) * 0.072 * H, -0.132 * H, mathx.sinf(a) * 0.072 * H),
            0.014 * H,
            0.007 * H,
            5,
            if (@mod(i, 2) == 0) LICHEN_DK else SMOSS,
        );
    }
    return b.toMesh();
}

fn smithHandMesh(work: bool) rl.Mesh {
    var b = Builder.init();
    b.setMat(.bark);
    b.addBlob(v3(0, -0.044 * H, 0.004 * H), v3(0.048 * H, 0.052 * H, 0.042 * H), 4, 9, BARKS);
    if (work) {
        for ([_]f32{ -1.4, -0.45, 0.45, 1.4 }) |k| {
            b.addCapsule(
                v3(k * 0.016 * H, -0.062 * H, 0.020 * H),
                v3(k * 0.026 * H, -0.084 * H, 0.062 * H),
                0.014 * H,
                0.010 * H,
                5,
                BARKS_DK,
            );
        }
        b.setMat(.steel);
        for ([_]f32{ -1, 1 }) |sx| {
            b.addCapsule(v3(sx * 0.012 * H, -0.070 * H, 0.040 * H), v3(sx * 0.006 * H, -0.086 * H, 0.230 * H), 0.011 * H, 0.008 * H, 5, SIRON);
            b.addCapsule(v3(sx * 0.012 * H, -0.070 * H, 0.040 * H), v3(sx * 0.030 * H, -0.052 * H, -0.090 * H), 0.010 * H, 0.008 * H, 5, SIRON_LT);
        }
        // **NOT `Mat.ember`.** That id is one of the two VERTEX-ANIMATED branches (`shaders`' `> 11.5 && < 13.5`)
        // and it is for sparks LEAVING a fire: it rises `life * 5.60` m and drifts sideways, so the bar of stock
        // already. The GLOW is the low alpha, which is the emissive channel and needs no animation at all.
        b.setMat(.plain);
        b.addCapsule(v3(0, -0.088 * H, 0.210 * H), v3(0, -0.092 * H, 0.330 * H), 0.014 * H, 0.012 * H, 6, rgba(238, 122, 34, 40));
    } else {
        b.addBlob(v3(0, -0.070 * H, 0.020 * H), v3(0.050 * H, 0.030 * H, 0.038 * H), 4, 8, BARKS_DK);
        b.addBlob(v3(0.030 * H, -0.044 * H, 0.022 * H), v3(0.018 * H, 0.026 * H, 0.020 * H), 3, 7, BARKS_LT);
    }
    return b.toMesh();
}

fn hammerMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5B09);
    b.setMat(.wood);
    var p = v3(0, -0.030 * H, 0);
    const segs: usize = 4;
    var i: usize = 0;
    while (i < segs) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, segs);
        const nxt = v3(rng.signed() * 0.004 * H, -0.030 * H + (t + 1.0 / @as(f32, segs)) * HAFT_LEN, 0);
        b.addCapsule(p, nxt, lerpF(0.019, 0.026, t) * H, lerpF(0.019, 0.026, t + 0.25) * H, 7, if (i % 2 == 0) HAFT else art.TIMBER_DK);
        p = nxt;
    }
    b.setMat(.steel);
    const hy = HAFT_LEN - 0.030 * H;
    b.addCube(v3(0, hy, 0), v3(HEAD_R * 1.9, HEAD_R * 0.95, HEAD_R * 0.95), SIRON);
    b.addCube(v3(-HEAD_R * 1.95, hy, 0), v3(HEAD_R * 0.20, HEAD_R * 0.90, HEAD_R * 0.90), SIRON_LT);
    b.addBox(v3(HEAD_R * 2.05, hy, 0), v3(HEAD_R * 0.55, 0, 0), v3(0, HEAD_R * 0.80, 0), v3(0, 0, HEAD_R * 0.22), SIRON_LT);
    b.addCube(v3(0, hy - HEAD_R * 0.98, 0), v3(HEAD_R * 0.44, HEAD_R * 0.10, HEAD_R * 0.40), SIRON_LT);
    return b.toMesh();
}

fn staffMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.wood);
    const SEGS: usize = 7;
    const total = STAFF_LEN + STAFF_UP;
    const segLen = total / @as(f32, SEGS);
    const arc = 7.0; // degrees over the WHOLE pole
    const curl = mathx.radians(arc / @as(f32, SEGS));
    var p = v3(0, STAFF_UP, 0);
    var dir = v3(mathx.sinf(mathx.radians(-arc * 0.5)), -1, 0);
    dir = mathx.normV(dir);
    var i: usize = 0;
    while (i < SEGS) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, SEGS);
        const nxt = mathx.addV(p, mathx.scaleV(dir, segLen));
        const r0 = lerpF(STAFF_R, STAFF_R * 0.78, t);
        const r1 = lerpF(STAFF_R, STAFF_R * 0.78, t + 1.0 / @as(f32, SEGS));
        b.addCapsule(p, nxt, r0, r1, 8, if (i % 2 == 0) WOOD else WOOD_LT);
        p = nxt;
        const c = mathx.cosf(curl);
        const s = mathx.sinf(curl);
        dir = mathx.normV(v3(dir.x * c - dir.y * s, dir.x * s + dir.y * c, dir.z));
    }
    b.addBlob(v3(0, STAFF_UP + 0.008 * H, 0), v3(STAFF_R * 1.8, STAFF_R * 1.6, STAFF_R * 1.7), 4, 9, WOOD_LT);
    b.addBlob(v3(STAFF_R * 0.5, STAFF_UP - total * 0.31, 0), v3(STAFF_R * 1.25, STAFF_R * 0.9, STAFF_R * 1.1), 3, 8, WOOD_LT);
    b.setMat(.steel);
    const ferrule = mathx.scaleV(dir, 0.024 * H);
    b.addCylinder(p, mathx.addV(p, ferrule), STAFF_R * 0.9, STAFF_R * 0.72, 8, IRON);
    b.addDome(mathx.addV(p, ferrule), dir, STAFF_R * 0.72, 8, IRON);
    return b.toMesh();
}


test "a wanderer is posted on the ground the map puts under it, and keeps its record" {
    const alloc = std.testing.allocator;
    const m = try alloc.create(wf.Map);
    defer alloc.destroy(m);
    m.blank("folk");
    m.npcs[0] = .{ .kind = .wanderer, .x = 4, .z = -9, .yaw = 90, .scale = 1, .seed = 0.25, .roam = 3 };
    m.npcs[1] = .{ .kind = .wanderer, .x = -20, .z = 6, .yaw = 0, .scale = 1, .seed = 0.75 };
    m.nnpcs = 2;

    var folk = Folk{};
    folk.reset(m);
    try std.testing.expectEqual(@as(usize, 2), folk.n);
    try std.testing.expectEqual(@as(u16, 1), folk.list[1].rec);
    try std.testing.expectEqual(m.heightAt(4, -9), folk.list[0].pos.y);
    try std.testing.expect(folk.list[0].variant != folk.list[1].variant);
}

test "he looks up when you come near and settles back to his post when you go" {
    var p = Wanderer.spawn(0, mathx.zero3, 0, 1, 0.3, 0);
    var t: f32 = 0;
    while (t < 0.5) : (t += 1.0 / 60.0) p.update(1.0 / 60.0, v3(0, 0, 40), 200);
    try std.testing.expect(!p.noticed);
    try std.testing.expectEqual(Gesture.none, p.gesture);

    p.update(1.0 / 60.0, v3(0, 0, 3), 200);
    try std.testing.expect(p.noticed);
    try std.testing.expectEqual(Gesture.beckon, p.gesture);
    const turned = p.facing;
    t = 0;
    while (t < 1.5) : (t += 1.0 / 60.0) p.update(1.0 / 60.0, v3(0, 0, 3), 200);
    try std.testing.expect(@abs(mathx.wrapPi(p.facing)) < @abs(mathx.wrapPi(turned)) + 0.001);
    try std.testing.expect(@abs(mathx.wrapPi(p.facing - 0)) < 0.05);
    try std.testing.expectEqual(Gesture.none, p.gesture);
}

test "a roamer stays inside its tether and a posted one never moves" {
    var roamer = Wanderer.spawn(0, mathx.zero3, 0, 1, 0.4, 3.0);
    var still = Wanderer.spawn(1, mathx.zero3, 0, 1, 0.6, 0);
    var t: f32 = 0;
    var far: f32 = 0;
    while (t < 120.0) : (t += 1.0 / 60.0) {
        roamer.update(1.0 / 60.0, v3(0, 0, 500), 200);
        still.update(1.0 / 60.0, v3(0, 0, 500), 200);
        far = @max(far, mathx.distXZ(roamer.pos, roamer.home));
    }
    try std.testing.expect(far > 0.5);
    try std.testing.expect(far <= 3.0 + 0.05);
    try std.testing.expectEqual(@as(f32, 0), mathx.distXZ(still.pos, still.home));
}

test "a talking wanderer stops attending to his errand and punctuates" {
    var p = Wanderer.spawn(0, mathx.zero3, 0, 1, 0.5, 4.0);
    p.talking = true;
    var t: f32 = 0;
    var gestured = false;
    while (t < TALK_BEAT + 0.5) : (t += 1.0 / 60.0) {
        p.update(1.0 / 60.0, v3(0, 0, 3), 200);
        if (p.gesture == .point) gestured = true;
    }
    try std.testing.expectEqual(@as(f32, 0), mathx.distXZ(p.pos, p.home));
    try std.testing.expect(gestured);
}

test "his feet do not rake through the floor, standing or walking" {
    var p = Wanderer.spawn(0, mathx.zero3, 0, 1, 0.2, 5.0);
    var t: f32 = 0;
    var worst: f32 = std.math.floatMax(f32);
    while (t < 30.0) : (t += 1.0 / 60.0) {
        p.update(1.0 / 60.0, v3(0, 0, 500), 200);
        worst = @min(worst, heromod.soleDepth(&p.xf, &solePatches));
    }
    try std.testing.expect(worst > heromod.SOLE_Y - 0.015);
}

test "he turns before he sets off, so his amble is never a sidestep" {
    var p = Wanderer.spawn(0, mathx.zero3, 0, 1, 0.45, 4.0);
    var t: f32 = 0;
    var worstLat: f32 = 0;
    while (t < 90.0) : (t += 1.0 / 60.0) {
        p.update(1.0 / 60.0, v3(0, 0, 500), 200);
        worstLat = @max(worstLat, @abs(p.latB) * p.moving);
    }
    // A CRAB-WALK IS A STRAFE, and the strafe path's foot clearance carries eight centimetres of tolerance (`hero`'s own budget at lat 0.7). Nothing here has any business needing it.
    try std.testing.expect(worstLat < 0.12);
}

test "the idle weight shift does not slide him along the ground" {
    var p = Wanderer.spawn(0, mathx.zero3, 0, 1, 0.35, 0);
    var t: f32 = 0;
    var minX: f32 = std.math.floatMax(f32);
    var maxX: f32 = -std.math.floatMax(f32);
    while (t < 20.0) : (t += 1.0 / 60.0) {
        p.update(1.0 / 60.0, v3(0, 0, 500), 200);
        for ([_]usize{ ANKL, ANKR }) |bone| {
            const x = rl.math.vector3Transform(mathx.zero3, p.xf[bone]).x;
            minX = @min(minX, x);
            maxX = @max(maxX, x);
        }
    }
    const stance = 2.0 * heromod.HIP_HALF * H * p.scale;
    try std.testing.expect(maxX - minX < stance + 0.02);
}

test "the name comes off the record, and falls back to the kind" {
    const alloc = std.testing.allocator;
    const m = try alloc.create(wf.Map);
    defer alloc.destroy(m);
    m.blank("folk");
    m.npcs[0] = .{};
    m.npcs[1] = .{ .call = try m.addText("The Wandering Pilgrim") };
    m.nnpcs = 2;
    try std.testing.expectEqualStrings("Wanderer", nameOf(m, 0));
    try std.testing.expectEqualStrings("The Wandering Pilgrim", nameOf(m, 1));
    try std.testing.expectEqualStrings("Wanderer", nameOf(m, 99));
}

test "THE CARAVANEER CARRIES ITS HEAD ON A LONGER NECK, and the face point is on the muzzle" {
    var w = Wanderer.spawnAs(.wanderer, 0, mathx.zero3, 0, 1.0, 0.3, 0);
    var c = Wanderer.spawnAs(.merchant, 1, mathx.zero3, 0, 1.0, 0.3, 0);
    w.pose();
    c.pose();

    const wSkull = rl.math.vector3Transform(mathx.zero3, w.xf[SKULL]);
    const cSkull = rl.math.vector3Transform(mathx.zero3, c.xf[SKULL]);
    const wFace = w.facePoint();
    const cFace = c.facePoint();
    std.debug.print("\n  skull bone: wanderer {d:.3} m, caravaneer {d:.3} m (rig is shared)\n", .{ wSkull.y, cSkull.y });
    std.debug.print("  face point: wanderer {d:.3} m up / {d:.3} m out, caravaneer {d:.3} / {d:.3}\n", .{
        wFace.y, wFace.z, cFace.y, cFace.z,
    });

    try std.testing.expect(@abs(cSkull.y - wSkull.y) < 0.12);
    try std.testing.expect(cFace.y > wFace.y + MERCH_NECK * 0.8);
    const wReach = mathx.lenV(mathx.subV(wFace, wSkull));
    const cReach = mathx.lenV(mathx.subV(cFace, cSkull));
    std.debug.print("  face is {d:.3} m off the bone on the wanderer, {d:.3} m on the caravaneer\n", .{ wReach, cReach });
    try std.testing.expect(cReach > wReach + 0.10);

    std.debug.print("  crown: wanderer {d:.2} m, caravaneer {d:.2} m\n", .{ w.topWorld().y, c.topWorld().y });
    try std.testing.expect(c.topWorld().y > w.topWorld().y + 0.10);
}

test "the two carriages disagree — one stoops over a staff, the other stands up over a neck" {
    const w = spec(.wanderer);
    const c = spec(.merchant);
    std.debug.print("\n  carriage: wanderer stoop {d:.1} head {d:.1}, caravaneer stoop {d:.1} head {d:.1}\n", .{
        w.stoop, w.headFwd, c.stoop, c.headFwd,
    });
    try std.testing.expect(w.stoop > 0 and c.stoop < 0);
    try std.testing.expect(w.headFwd > 0 and c.headFwd < 0);
}

pub fn hammerHead(p: *const Wanderer) rl.Vector3 {
    return rl.math.vector3Transform(v3(0, HAFT_LEN - 0.030 * H, 0), p.xf[STAFF]);
}

pub fn hammerBearing(p: *const Wanderer) f32 {
    const grip = rl.math.vector3Transform(mathx.zero3, p.xf[STAFF]);
    const d = mathx.subV(hammerHead(p), grip);
    return mathx.degrees(std.math.atan2(d.z, -d.y));
}

pub fn headBearing(p: *const Wanderer) f32 {
    const at = rl.math.vector3Transform(mathx.zero3, p.xf[SKULL]);
    const ahead = rl.math.vector3Transform(v3(0, 0, 0.2 * H), p.xf[SKULL]);
    const d = mathx.subV(ahead, at);
    return mathx.degrees(mathx.wrapPi(mathx.headingXZ(d) - p.facing));
}

test "THE SMITH TRACKS YOU WITH HIS HEAD AND HIS BODY NEVER LEAVES THE ANVIL" {
    const dt: f32 = 1.0 / 60.0;
    const settle = struct {
        fn run(k: wf.NpcKind, at: rl.Vector3) Wanderer {
            var w = Wanderer.spawnAs(k, 1, mathx.zero3, 0, 1.0, 0.3, 0);
            var i: usize = 0;
            while (i < 240) : (i += 1) w.update(dt, at, 400);
            return w;
        }
    }.run;
    const right = v3(4.0, 0, 1.2);
    const left = v3(-4.0, 0, 1.2);
    var a = settle(.smith, right);
    var b = settle(.smith, left);
    const spread = headBearing(&a) - headBearing(&b);
    const want = mathx.degrees(mathx.wrapPi(mathx.headingXZ(mathx.dirXZ(mathx.zero3, right)))) * 2.0;
    std.debug.print("\n  smith: head swings {d:.0} deg between a hero either side of him (the two stand {d:.0} deg apart)\n", .{ spread, want });
    std.debug.print("  ...and his body is still on the yaw he was placed at: {d:.0} deg and {d:.0} deg\n", .{
        mathx.degrees(mathx.wrapPi(a.facing)), mathx.degrees(mathx.wrapPi(b.facing)),
    });
    try std.testing.expect(spread > 0);
    try std.testing.expectApproxEqAbs(want * 0.5, a.headYaw, 6.0);
    try std.testing.expectApproxEqAbs(-want * 0.5, b.headYaw, 6.0);
    // **THE BODY NEVER MOVES.** Placed at yaw 0 and still on it, with the hero well inside notice on both sides.
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.degrees(mathx.wrapPi(a.facing)), 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.degrees(mathx.wrapPi(b.facing)), 1.0);
    const w = settle(.wanderer, right);
    std.debug.print("  the wanderer, same spot, turned his whole body to {d:.0} deg\n", .{ mathx.degrees(mathx.wrapPi(w.facing)) });
    try std.testing.expect(@abs(mathx.degrees(mathx.wrapPi(w.facing))) > 30.0);

    const back = settle(.smith, v3(-3.0, 0, -2.0));
    std.debug.print("  behind him the neck stops at {d:.0} deg of its {d:.0} deg range\n", .{ back.headYaw, SMITH_HEAD_TRACK });
    try std.testing.expect(@abs(back.headYaw) <= SMITH_HEAD_TRACK + 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.degrees(mathx.wrapPi(back.facing)), 1.0);
    try std.testing.expect(a.headDip > 8.0);
}

test "MOSSBEARD IS THE BIGGEST BODY THAT TALKS, and he is bowed without being folded" {
    var w = Wanderer.spawnAs(.wanderer, 0, mathx.zero3, 0, 1.0, 0.3, 0);
    var s = Wanderer.spawnAs(.smith, 1, mathx.zero3, 0, 1.0, 0.3, 0);
    w.pose();
    s.pose();
    const crown = s.topWorld().y;
    std.debug.print("\n  mossbeard: crown {d:.2} m against the wanderer's {d:.2} m ({d:.2}x), body radius {d:.2} m\n", .{
        crown, w.topWorld().y, crown / w.topWorld().y, s.bodyR(),
    });
    try std.testing.expect(crown > w.topWorld().y * 1.4);
    try std.testing.expect(crown < art.TOWER_DOOR_HEAD);

    const hip = rl.math.vector3Transform(mathx.zero3, s.xf[ROOT]);
    const chest = rl.math.vector3Transform(mathx.zero3, s.xf[CHEST]);
    const skull = rl.math.vector3Transform(mathx.zero3, s.xf[SKULL]);
    std.debug.print("  carriage: hip z {d:.3}, chest z {d:.3}, skull z {d:.3} — head leads the chest by {d:.3} m\n", .{
        hip.z, chest.z, skull.z, skull.z - chest.z,
    });
    try std.testing.expect(skull.z > chest.z);
    try std.testing.expect(chest.z - hip.z < skull.z - chest.z);
}

test "THE STROKE IS THE IDLE: it rises slowly, lands once a cycle, and overshoots its own rest" {
    var s = Wanderer.spawnAs(.smith, 1, mathx.zero3, 0, 1.0, 0.3, 0);
    const dt: f32 = 1.0 / 60.0;
    var strikes: usize = 0;
    var lowest: f32 = 1e9;
    var highest: f32 = -1e9;
    var lowAt: f32 = 0;
    var highAt: f32 = 0;
    var rebound: f32 = 0;
    var frames: usize = 0;
    while (frames < @as(usize, @intFromFloat(3.0 * HAMMER_PERIOD * 60.0))) : (frames += 1) {
        s.update(dt, v3(0, 0, 400), 400);
        if (s.struck) strikes += 1;
        const head = hammerHead(&s);
        if (head.y < lowest) {
            lowest = head.y;
            lowAt = head.z;
        }
        if (head.y > highest) {
            highest = head.y;
            highAt = head.z;
        }
        if (s.hammer > HAMMER_FALL) rebound = mathx.maxF(rebound, head.y - lowest);
    }
    std.debug.print("\n  stroke: {d} landings in {d:.1} s ({d:.2} s apart) | head {d:.2} m up at the top, {d:.2} m at the face — {d:.2} m of travel\n", .{
        strikes, 3.0 * HAMMER_PERIOD, HAMMER_PERIOD, highest, lowest, highest - lowest,
    });
    std.debug.print("  head stands {d:.2} m forward of him at the face, {d:.2} m at the top; rebound {d:.3} m off the anvil\n", .{
        lowAt, highAt, rebound,
    });
    s.hammer = 0;
    s.pose();
    const atFace = hammerBearing(&s);
    s.hammer = HAMMER_RISE;
    s.pose();
    const atTop = hammerBearing(&s);
    std.debug.print("  haft bears {d:.0} deg off plumb on the face and {d:.0} deg at the top (authored {d:.0} / {d:.0})\n", .{
        atFace, atTop, HAM_TILT_LO, HAM_TILT_HI,
    });
    try std.testing.expectApproxEqAbs(HAM_BEAR_FACE, atFace, 10.0);
    try std.testing.expectApproxEqAbs(HAM_BEAR_TOP, atTop, 10.0);
    try std.testing.expect(highest < s.topWorld().y);
    try std.testing.expectEqual(@as(usize, 3), strikes);
    try std.testing.expect(highest - lowest > HEAD_R * SMITH_SIZE * 6.0);
    try std.testing.expect(rebound > 0.02);
    try std.testing.expect(HAMMER_RISE > (HAMMER_FALL - HAMMER_RISE) * 2.0);
}

test "THE ANVIL IS SOLVED OFF THE STROKE, not the other way round" {
    var s = Wanderer.spawnAs(.smith, 1, mathx.zero3, 0, 1.0, 0.3, 0);
    const dt: f32 = 1.0 / 240.0;
    var lowest: f32 = 1e9;
    var at: rl.Vector3 = mathx.zero3;
    var frames: usize = 0;
    while (frames < @as(usize, @intFromFloat(2.0 * HAMMER_PERIOD * 240.0))) : (frames += 1) {
        s.update(dt, v3(0, 0, 400), 400);
        const head = hammerHead(&s);
        if (head.y < lowest) {
            lowest = head.y;
            at = head;
        }
    }
    std.debug.print("\n  hammer bottoms at {d:.3} m, {d:.3} m forward of his own axis | anvil face authored at {d:.2} m\n", .{
        lowest, at.z, forge.ANVIL_FACE,
    });
    try std.testing.expectApproxEqAbs(forge.ANVIL_FACE, lowest, 0.03);
    try std.testing.expectApproxEqAbs(SMITH_ANVIL_Z, at.z, 0.04);
    try std.testing.expect(SMITH_ANVIL_Z > BODY_R * SCALE * SMITH_SIZE);
}

