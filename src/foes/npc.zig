const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const heromod = @import("../play/hero.zig");
const wf = @import("../world/worldfmt.zig");
const art = @import("../props/propart.zig");

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
/// The inside of the cowl — near-black, and the one place a hard value break is free: it is a hole, so it cannot blow out, and the contrast against the shell is the whole read of a hood.
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

// **THE CARAVANEER** — a camel-humanoid, and the desert's merchant. Same rig as the wanderer to the bone
// (`heromod`'s humanoid), because it walks on two legs in a robe; what makes it a camel is the MUZZLE, the HUMP
// and the long NECK, and all three are mesh and none is a new joint.
//
// **THE NECK IS BUILT INTO THE MESH, NOT INTO THE SKELETON.** `restHumanoid` fixes where the skull bone hangs,
// so the extra length goes up out of `neckMesh` and the head's own contents are pushed up to sit on top of it
// (`MERCH_NECK`). Head rotations then pivot at the base of the extension, which is what a long neck does anyway.
//
// **SOLVED, AND WIDER THAN THE WANDERER ON PURPOSE.** That palette's own note is that every material sampled
// 30-36 albedo and the figure read flat; this one spans 24 to 100, which is 111 to 213 on screen. Layered on HUE
// too: warm hide and a madder sash against a COLD indigo stripe.
//   hide 72 -> 183    stripe 88 -> 201    indigo 34 -> 131    hump 38 -> 137    strap 24 -> 111
const HIDE = rgba(78, 66, 46, 255);
const HIDE_DK = rgba(48, 40, 30, 255);
/// Shaggier and darker than the flank: a hump carries the coat the rest of the body has rubbed off.
const HUMP = rgba(40, 34, 26, 255);
const HUMP_LT = rgba(56, 48, 36, 255);
/// **THE STRIPE IS BANDED ALONG THE ROBE ON PURPOSE** — the barber's-pole warning is about accidental banding on
/// a shaft, and a striped weave is the one place the alternation IS the design. Off `propart`, which is also
/// where his stall gets it (`propmarket`): one loom, one place to retune it.
const STRIPE = art.WEAVE;
const STRIPE_DK = art.WEAVE_DK;
const MADDER = art.MADDER;
const MADDER_LT = art.MADDER_LT;
const STRAP = rgba(24, 19, 14, 255);
const HOOF = rgba(34, 30, 26, 255);
const MUZZLE = rgba(96, 84, 62, 255);
const LASH = rgba(20, 17, 13, 255);
/// Brass borrowing the warm branch (`Mat.gilt`): under `steel` a yellow albedo comes back blued silver, which is
/// the note at the top of `propgold`. It is a pan and a chain, so the lie costs nothing.
const BRASS = rgba(108, 82, 34, 255);

/// How much taller the caravaneer's neck is than the wanderer's, in stature. The head mesh is offset by the same
/// figure, so the two cannot drift apart.
const MERCH_NECK: f32 = 0.100 * H;

pub const NKIND = @typeInfo(wf.NpcKind).@"enum".fields.len;

/// One row per `wf.NpcKind`, pinned in its order. `stoop` and `headFwd` are the CARRIAGE, and they are most of
/// what tells the two apart at distance: the wanderer is bent over his staff, the caravaneer stands up and holds
/// his head back over that neck.
const Spec = struct {
    kind: wf.NpcKind,
    /// On top of `SCALE`.
    size: f32 = 1.0,
    stoop: f32,
    headFwd: f32,
    /// Where the conversation panel photographs (`facePoint`), in the SKULL's own frame — a muzzle that projects
    /// 0.1 of a stature forward is not framed by the wanderer's point.
    faceAt: rl.Vector3,
    /// Stature to the crown, for the dialog marker and the talk reticle.
    top: f32,
};

const SPEC = [NKIND]Spec{
    .{ .kind = .wanderer, .stoop = 7.5, .headFwd = 5.0, .faceAt = FACE_AT, .top = 1.02 },
    .{ .kind = .merchant, .size = 1.06, .stoop = -3.0, .headFwd = -7.0, .faceAt = v3(0, 0.045 * H + MERCH_NECK, 0.085 * H), .top = 1.16 },
};

comptime {
    for (SPEC, 0..) |sp, i| {
        if (@intFromEnum(sp.kind) != i) @compileError("npc: SPEC is out of `wf.NpcKind` order");
    }
    // **THE TWO CARRIAGES MUST DISAGREE**, or one kind is the other in a different coat.
    std.debug.assert(spec(.merchant).stoop < spec(.wanderer).stoop and spec(.merchant).headFwd < spec(.wanderer).headFwd);
    std.debug.assert(spec(.merchant).top > spec(.wanderer).top);
}

pub fn spec(k: wf.NpcKind) Spec {
    return SPEC[@intFromEnum(k)];
}

pub const NOTICE_R: f32 = 7.0;
pub const REACH: f32 = 2.4;
const TURN_RATE = 3.2;
/// How square onto his errand he has to be before he sets off (radians).
const TURN_GATE = 0.22;
const AMBLE_SPEED = heromod.WALK_SPEED * 0.42;
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
    /// **ONE SET PER KIND, BECAUSE THE COLOUR AND THE SHAPE ARE BOTH IN THE VERTICES.** The rig, every pose curve
    /// and `legChain` are shared; what a kind owns is seventeen meshes and a pair of heads.
    bone: [NKIND][N]rl.Mesh,
    heads: [NKIND][2]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "npc");
        var heads: [NKIND][2]rl.Mesh = undefined;
        heads[0] = .{ hoodedHeadMesh(), bareHeadMesh() };
        heads[1] = .{ merchHeadMesh(true), merchHeadMesh(false) };
        var bone: [NKIND][N]rl.Mesh = undefined;
        bone[0] = wandererBones(heads[0][0]);
        bone[1] = merchantBones(heads[1][0]);
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

    /// **THE ONE DOOR**, so a kind cannot be posted without its own carriage, its own reach and its own meshes.
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
            if (mathx.lenXZ(to) > 0.001) self.wantYaw = mathx.headingXZ(to);
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

        self.facing = mathx.approachAngle(self.facing, self.wantYaw, TURN_RATE * dt);
        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, moved / self.scale, speed, moveYaw, self.facing);
        self.pose();
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

        heromod.legChain(&wx, &self.rest, self.pos.y, self.phase, m, 0, self.fwdB, self.latB, 1.0, HIPL, KNEEL, solePatches[0]);
        heromod.legChain(&wx, &self.rest, self.pos.y, self.phase + 0.5, m, 0, self.fwdB, self.latB, -1.0, HIPR, KNEER, solePatches[1]);
        self.poseUpper(&wx, prot, lean, breath, shift, bowK, m);
        self.xf = wx;
    }

    fn poseUpper(self: *Wanderer, wx: *[N]rl.Matrix, prot: f32, lean: f32, breath: f32, shift: f32, bowK: f32, m: f32) void {
        const rest = self.rest;
        const wonk = (self.seed - 0.5) * 5.0;
        const twoPi = std.math.tau;
        const trunk = lean;
        const nod = 1.6 * mathx.cosf(2.0 * twoPi * self.phase) * m;

        const lagC = mathx.sinf(twoPi * (self.phase - 0.06)) * m;
        const lagN = mathx.sinf(twoPi * (self.phase - 0.12)) * m;
        setLocal(wx, SPINE, rest, mul3(rx(trunk * 0.42 + nod + breath * A_BREATH * 0.5), ry(-0.35 * prot), rz(wonk * 0.5 - shift * A_LIST * 0.9)));
        setLocal(wx, CHEST, rest, mul3(rx(trunk * 0.58 + breath * A_BREATH), ry(-0.55 * prot + 1.4 * lagC), rz(-wonk * 0.3)));
        const fwd = spec(self.kind).headFwd;
        setLocal(wx, NECK, rest, rx(fwd * 0.4 + 8.0 * bowK - nod * 0.5));

        const still = 1.0 - m;
        const driftY = mathx.sinf(self.t * twoPi * DRIFT_RATE) * A_DRIFT_YAW * still;
        const driftX = mathx.cosf(self.t * twoPi * DRIFT_RATE * 1.7 + 1.3) * A_DRIFT_PITCH * still;
        setLocal(wx, SKULL, rest, mul3(
            rx(fwd * 0.6 + driftX - nod * 0.8 + 22.0 * bowK),
            ry(driftY - prot * 0.4 - 1.2 * lagN),
            rz(wonk + shift * A_LIST * 1.2),
        ));

        const plantPh = self.phase + 0.5;
        const plant = mathx.maxF(0, mathx.cosf(twoPi * plantPh)) * m;
        const push = STAFF_PLANT_SH * plant;
        setLocal(wx, SHR, rest, mul3(rx(-(STAFF_SH + push)), rz(-STAFF_ABD - wonk * 0.4), ry(-4.0 * plant)));
        setLocal(wx, ELR, rest, rx(STAFF_EL - 10.0 * plant));
        setLocal(wx, WRR, rest, rz(-6.0));
        // THE POLE IS NOT A BONE, AND WHERE IT POINTS IS AUTHORED IN THE WORLD, NOT IN THE WRIST. Built down the wrist's own −Y, left alone it inherits the entire arm chain and the plant laid the staff flat out in front of him like a lance. So the fit BILLS THE ARM for its own angles (`hero.shieldFit`'s law).
        const armPitch = -(STAFF_SH + push) + (STAFF_EL - 10.0 * plant);
        setLocal(wx, STAFF, rest, mul3(
            rz(STAFF_ABD + wonk * 0.4),
            rx(-armPitch - STAFF_TILT - 9.0 * plant),
            rz(wonk * 0.5),
        ));

        const swing = 15.0 * heromod.armSwing(self.phase) * m;
        var sh: f32 = FREE_SH - swing;
        var el: f32 = FREE_EL - mathx.maxF(0, -swing) * 0.8;
        var abd: f32 = FREE_ABD;
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

// THE CARAVANEER'S SEVENTEEN. Same bones, same order, same segment lengths — `heromod.SEG_*` is what `legChain`
// solves against and a limb that disagrees with it walks on its shins.

/// A run of stripes down a wrapped body, banded across `axis` — the weave, and the one intended alternation.
fn striped(b: *Builder, c: rl.Vector3, size: rl.Vector3, bands: i32, rng: *mathx.Rng) void {
    const n = @as(f32, @floatFromInt(bands));
    var i: i32 = 0;
    while (i < bands) : (i += 1) {
        const fi = @as(f32, @floatFromInt(i));
        // **THE BANDS OVERLAP THEIR OWN PITCH.** Uneven widths, so it is a hand-loom and not a barcode — but
        // never NARROWER than the pitch: at 0.80 the gaps between them read as segmented plate armour and the
        // robe stopped being cloth.
        const w = size.y * 2.0 / n * rng.range(1.06, 1.34);
        const y = c.y + size.y - (fi + 0.5) * (size.y * 2.0 / n);
        // **ONE DARK BAND IN THREE, NOT ONE IN TWO.** Alternating evenly, a single cold stripe fills the frame at
        // portrait range and the robe reads as banded metal; at one in three the weave is warm and the dark is a
        // stripe ON it.
        slab(b, v3(c.x, y, c.z), v3(size.x, w * 0.5, size.z), if (@mod(i, 3) == 1) STRIPE_DK else STRIPE);
    }
}

fn merchPelvisMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xCA30);
    b.setMat(.cloth);
    // **THE COLD TONE IS ONLY EVER A BAND.** As the base it showed through wherever `striped` did not reach and
    // a whole indigo panel at portrait range reads as plate armour, not cloth.
    slab(&b, v3(0, 0.005 * H, 0), v3(0.212 * H, 0.135 * H, 0.158 * H), STRIPE);
    // SHORTER THAN THE WANDERER'S SKIRT: he walks a caravan, so the hem is hitched and there are wraps under it.
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
    // …and the bands COVER the base rather than sitting in the middle of it: same half-height, a hair wider.
    striped(&b, v3(0, -0.005 * H, 0), v3(0.262 * H, 0.118 * H, 0.159 * H), 5, &rng);
    // **THE HUMP, AND IT IS THE SILHOUETTE.** Behind the shoulders and ABOVE them, so it breaks the line of the
    // back against the sky — sat between the blades it read as a rucksack. Two lobes, the rear one smaller and
    // slumped: a hump that has been across a desert leans.
    // **BEHIND THE SHOULDERS AND BELOW THE HEAD.** At 0.108 up and 0.086 back its crown stood 1.72 m against a
    // skull centred at 1.78 and it read as a second head; 0.052 up and 0.128 back puts it where a hump goes,
    // which is on the BACK.
    b.setMat(.hide);
    b.addBlob(v3(0.008 * H, 0.052 * H, -0.128 * H), v3(0.112 * H, 0.098 * H, 0.106 * H), 6, 12, HUMP);
    b.addBlob(v3(-0.014 * H, 0.020 * H, -0.160 * H), v3(0.074 * H, 0.062 * H, 0.068 * H), 5, 10, HUMP_LT);
    // The coat on it: A FEW PERCENT OF THE MASS (the relief law). At 0.026 on a 0.112 radius these were a fifth
    // of it and read as grey PLATES stuck to a ball, so they are halved and seated inside the surface.
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

/// **THE LONG NECK.** `MERCH_NECK` of extra column on top of the wanderer's, and the head mesh is offset by the
/// same figure — the two are one number so they cannot part company. A shaggy ruff at the base, thinning to bare
/// hide at the throat, because that is where a working animal wears through.
fn merchNeckMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xCA33);
    const top = 0.068 * H + MERCH_NECK;
    b.setMat(.hide);
    // Not plumb: it rises and carries FORWARD, which is the whole line of a camel's neck.
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

/// **THE MUZZLE IS THE CREATURE.** Everything else could be a tall man in a striped robe; a head that projects a
/// tenth of a stature forward and ends in a split lip cannot. Built up `MERCH_NECK` so it sits on its own neck.
///
/// `wrapped` is the headcloth variant — over the crown and down the sides, with the muzzle bare either way,
/// because a covered muzzle is a sack.
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
        // **THE FALLS HUG THE SKULL.** Authored as two slabs they stood off it as flat plates — the one thing a
        // cloth over a head cannot be. Capsules down the sides instead, each following the jaw and each its own
        // length, because a headcloth is thrown on and not fitted.
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

/// **THE PAD IS BROAD AND SPLAYED AND STILL INSIDE THE HERO'S FOOTPRINT** — `footMesh`'s own note is that the
/// envelope is fixed by the gait curves, so this reshapes within z -0.05..+0.14 and x +-0.0425 of a stature and
/// never past it. Two toes at the front, and the pad squashed flat because a camel walks on a cushion.
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

/// **A BEAM SCALE WHERE THE WANDERER HAS A STAFF**, so the held bone says the trade without a word. Built down
/// the wrist's own -Y like the staff, and `poseUpper` bills the arm for its angles, so it hangs level whatever
/// the arm is doing.
const SCALE_ARM: f32 = 0.115 * H;
const SCALE_DROP: f32 = 0.105 * H;
fn scaleBeamMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xCA36);
    const grip = 0.070 * H;
    b.setMat(.wood);
    b.addCylinder(v3(0, 0, 0), v3(0, -grip, 0), 0.011 * H, 0.010 * H, 6, WOOD);
    b.setMat(.gilt);
    // THE BEAM, and it hangs OFF LEVEL, because one pan has something in it. That tilt is the whole picture.
    const tilt = mathx.radians(rng.range(5.0, 9.0));
    const dy = SCALE_ARM * mathx.sinf(tilt);
    b.addCylinder(v3(-SCALE_ARM, -grip - dy, 0), v3(SCALE_ARM, -grip + dy, 0), 0.006 * H, 0.006 * H, 6, BRASS);
    b.addBlob(v3(0, -grip, 0), v3(0.013 * H, 0.013 * H, 0.011 * H), 3, 8, BRASS);
    for ([_]f32{ -1.0, 1.0 }) |side| {
        const ex = side * SCALE_ARM;
        const ey = -grip + side * dy;
        // The cords, three to a pan, and the pan under them. The loaded side hangs lower and is the DEEPER dish.
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

    /// **THE ONE BOUND ON A HELD INDEX.** `near` is a body picked THIS frame and a `dialog.Session`'s `npc` is
    /// one picked several frames ago, and the table is re-posted whenever the map moves (`reset`) — so the
    /// caller that indexes `list` raw is the caller that reads a stranger, or reads off the end.
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

    /// ONE of them, for the PORTRAIT: the conversation panel photographs the man you are talking to, and it is the ACTUAL MODEL in his ACTUAL POSE (`book.drawPortrait`'s trick) — so it cannot go stale, and a head that turns to look at you turns in the panel too.
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
    // Both ankles live inside the stance width and nothing else. A LIST moves them by the sine of a couple of degrees; a pelvis TRANSLATION would carry them the full `A_LIST`-worth of metres and read as skating.
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

    // The skull BONE hangs at the same rest offset on both — the skeleton is shared, and that is the point.
    const wSkull = rl.math.vector3Transform(mathx.zero3, w.xf[SKULL]);
    const cSkull = rl.math.vector3Transform(mathx.zero3, c.xf[SKULL]);
    const wFace = w.facePoint();
    const cFace = c.facePoint();
    std.debug.print("\n  skull bone: wanderer {d:.3} m, caravaneer {d:.3} m (rig is shared)\n", .{ wSkull.y, cSkull.y });
    std.debug.print("  face point: wanderer {d:.3} m up / {d:.3} m out, caravaneer {d:.3} / {d:.3}\n", .{
        wFace.y, wFace.z, cFace.y, cFace.z,
    });

    // **THE LENGTH IS IN THE MESH, SO IT IS THE FACE POINT THAT MOVES AND NOT THE BONE.** If the bone rose with
    // it the shared rig would have forked, and every pose curve with it.
    try std.testing.expect(@abs(cSkull.y - wSkull.y) < 0.12);
    try std.testing.expect(cFace.y > wFace.y + MERCH_NECK * 0.8);
    // …and the muzzle PROJECTS, measured from its OWN BONE and not in world z: the caravaneer carries its head
    // pitched BACK (`SPEC.headFwd` is negative), which swings a forward offset upward and shrinks the world-z
    // reading even as the muzzle sticks further out. The distance from the bone is what actually says muzzle.
    const wReach = mathx.lenV(mathx.subV(wFace, wSkull));
    const cReach = mathx.lenV(mathx.subV(cFace, cSkull));
    std.debug.print("  face is {d:.3} m off the bone on the wanderer, {d:.3} m on the caravaneer\n", .{ wReach, cReach });
    try std.testing.expect(cReach > wReach + 0.10);

    // THE CROWN clears the wanderer's, which is what makes them tell apart in a crowd.
    std.debug.print("  crown: wanderer {d:.2} m, caravaneer {d:.2} m\n", .{ w.topWorld().y, c.topWorld().y });
    try std.testing.expect(c.topWorld().y > w.topWorld().y + 0.10);
}

test "the two carriages disagree — one stoops over a staff, the other stands up over a neck" {
    const w = spec(.wanderer);
    const c = spec(.merchant);
    std.debug.print("\n  carriage: wanderer stoop {d:.1} head {d:.1}, caravaneer stoop {d:.1} head {d:.1}\n", .{
        w.stoop, w.headFwd, c.stoop, c.headFwd,
    });
    // The caravaneer leans BACK where the wanderer leans forward: opposite signs, not a smaller number.
    try std.testing.expect(w.stoop > 0 and c.stoop < 0);
    try std.testing.expect(w.headFwd > 0 and c.headFwd < 0);
}
