const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const foe = @import("foe.zig");
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


pub const W: f32 = 1.12;
pub const PORTRAIT_DIST: f32 = 1.05;

pub const ROOT = 0;
pub const SPINE = 1;
pub const CHEST = 2;
pub const NECK = 3;
pub const HEAD = 4;
pub const JAW = 5;
pub const TAIL0 = 6;
pub const TAIL1 = 7;
pub const TAIL2 = 8;
pub const EARL = 9;
pub const EARR = 10;
pub const SHL = 11;
pub const ELL = 12;
pub const CAL = 13;
pub const PAWL = 14;
pub const SHR = 15;
pub const ELR = 16;
pub const CAR = 17;
pub const PAWR = 18;
pub const HIPL = 19;
pub const STL = 20;
pub const HKL = 21;
pub const HPAWL = 22;
pub const HIPR = 23;
pub const STR = 24;
pub const HKR = 25;
pub const HPAWR = 26;
pub const N = 27;

pub const PARENT = [N]i32{
    -1,    ROOT,  SPINE, CHEST, NECK,  HEAD,
    ROOT,  TAIL0, TAIL1,
    HEAD,  HEAD,
    CHEST, SHL,   ELL,   CAL,
    CHEST, SHR,   ELR,   CAR,
    ROOT,  HIPL,  STL,   HKL,
    ROOT,  HIPR,  STR,   HKR,
};

const Limb = struct { bones: [4]usize, upper: f32, lower: f32, bend: f32, jointY: f32 };

const LIMBS = [4]Limb{
    .{ .bones = .{ HIPL, STL, HKL, HPAWL }, .upper = FEMUR, .lower = HIND_LOWER, .bend = -1.0, .jointY = HIP_Y },
    .{ .bones = .{ HIPR, STR, HKR, HPAWR }, .upper = FEMUR, .lower = HIND_LOWER, .bend = -1.0, .jointY = HIP_Y },
    .{ .bones = .{ SHL, ELL, CAL, PAWL }, .upper = HUMERUS, .lower = FORE_LOWER, .bend = 1.0, .jointY = SHOULDER_Y },
    .{ .bones = .{ SHR, ELR, CAR, PAWR }, .upper = HUMERUS, .lower = FORE_LOWER, .bend = 1.0, .jointY = SHOULDER_Y },
};

comptime {
    for (LIMBS) |L| {
        if (@as(usize, @intCast(PARENT[L.bones[1]])) != L.bones[0] or
            @as(usize, @intCast(PARENT[L.bones[2]])) != L.bones[1] or
            @as(usize, @intCast(PARENT[L.bones[3]])) != L.bones[2]) @compileError("wolf: a limb chain disagrees with PARENT");
    }
}

// Segment lengths as fractions of `W`, summing to the stature they are measured against. THE CHEST IS HALF THE HEIGHT: a canid's brisket sits at ~0.55 of the withers. Built with the shoulder at 0.62 the trunk floated on stilts and read as a deer.
const SHOULDER_Y = 0.70;
const HIP_Y = 0.72;
const BRISKET_Y = 0.46;
const HUMERUS = 0.24;
const FORE_LOWER = 0.50;
const FEMUR = 0.29;
const HIND_LOWER = 0.52;
const TRACK = 0.145;
const CHEST_Z = 0.42;
const HIP_Z = -0.42; // …and the pelvis behind it: a 0.84 W trunk
const HEAD_LEN = 0.26;
const HEAD_Y = 0.82;
const HEAD_Z = 0.72;

/// In the animal's own standing frame (X its left, Y up, Z forward), as fractions of the WITHERS HEIGHT it is
/// handed. **THE ONE DIAL THAT IS HONESTLY PER-CREATURE**, and why this takes it rather than reading `W`: a second quadruped is a stature and a head, never a second copy of the joint layout.
pub fn restPose(w: f32) [N]rl.Vector3 {
    var r: [N]rl.Vector3 = undefined;
    r[ROOT] = v3(0, HIP_Y, HIP_Z);
    r[SPINE] = v3(0, HIP_Y - 0.005, HIP_Z + 0.27);
    r[CHEST] = v3(0, SHOULDER_Y, CHEST_Z);
    r[NECK] = v3(0, SHOULDER_Y + 0.045, CHEST_Z + 0.12);
    r[HEAD] = v3(0, HEAD_Y, HEAD_Z);
    r[JAW] = v3(0, HEAD_Y - 0.035, HEAD_Z + HEAD_LEN * 0.28);
    r[TAIL0] = v3(0, HIP_Y + 0.015, HIP_Z - 0.07);
    r[TAIL1] = v3(0, HIP_Y - 0.075, HIP_Z - 0.27);
    r[TAIL2] = v3(0, HIP_Y - 0.185, HIP_Z - 0.45);
    r[EARL] = v3(0.050, HEAD_Y + 0.075, HEAD_Z - 0.055);
    r[EARR] = v3(-0.050, HEAD_Y + 0.075, HEAD_Z - 0.055);
    // THE REST CHAIN CARRIES THE TRUE SEGMENT LENGTHS, so its paw hangs BELOW the ground — that surplus is the zig-zag. `setJoint` takes each bone's length from the DISTANCE between two rest points, so laying the paw at y = 0 tells the solver a lower segment 4-10% longer than the bones are.
    inline for (.{ .{ SHL, ELL, CAL, PAWL, TRACK }, .{ SHR, ELR, CAR, PAWR, -TRACK } }) |c| {
        r[c[0]] = v3(c[4], SHOULDER_Y, CHEST_Z);
        r[c[1]] = v3(c[4], SHOULDER_Y - HUMERUS, CHEST_Z);
        r[c[2]] = v3(c[4], SHOULDER_Y - HUMERUS - FORE_LOWER * 0.68, CHEST_Z);
        r[c[3]] = v3(c[4], SHOULDER_Y - HUMERUS - FORE_LOWER, CHEST_Z);
    }
    inline for (.{ .{ HIPL, STL, HKL, HPAWL, TRACK }, .{ HIPR, STR, HKR, HPAWR, -TRACK } }) |c| {
        r[c[0]] = v3(c[4], HIP_Y, HIP_Z);
        r[c[1]] = v3(c[4], HIP_Y - FEMUR, HIP_Z);
        r[c[2]] = v3(c[4], HIP_Y - FEMUR - HIND_LOWER * 0.62, HIP_Z);
        r[c[3]] = v3(c[4], HIP_Y - FEMUR - HIND_LOWER, HIP_Z);
    }
    for (&r) |*p| p.* = v3(p.x * w, p.y * w, p.z * w);
    return r;
}

pub const Gait = struct {
    /// Fraction of the stride each foot is ON THE GROUND. Above 0.5 something is always down (a walk); below
    /// it there are moments with no feet on the earth at all, which is what an aerial phase IS.
    duty: f32,
    /// How far the FOREfoot's strike lags the hind foot on the SAME SIDE, as a fraction of the stride. 0.5 is the trot's diagonal couplets; 0.84 is the lateral-sequence walk.
    lag: f32,
};

/// The three measured anchors. Speeds are the m/s each gait is actually used at.
pub const WALK = Gait{ .duty = 0.65, .lag = 0.84 };
pub const TROT = Gait{ .duty = 0.55, .lag = 0.50 };
pub const GALLOP = Gait{ .duty = 0.42, .lag = 0.63 };
pub const WALK_SPEED: f32 = 1.1;
/// A WOLF'S TRAVELLING GAIT, and the speed it will hold for hours: 2.2-2.7 m/s. Just over the hero's walk.
pub const TROT_SPEED: f32 = 2.4;
pub const GALLOP_SPEED: f32 = 5.2;

pub fn gaitAt(speed: f32) Gait {
    if (speed <= WALK_SPEED) return WALK;
    if (speed >= GALLOP_SPEED) return GALLOP;
    if (speed <= TROT_SPEED) {
        const t = (speed - WALK_SPEED) / (TROT_SPEED - WALK_SPEED);
        return .{ .duty = mathx.lerpF(WALK.duty, TROT.duty, t), .lag = mathx.lerpF(WALK.lag, TROT.lag, t) };
    }
    const t = (speed - TROT_SPEED) / (GALLOP_SPEED - TROT_SPEED);
    return .{ .duty = mathx.lerpF(TROT.duty, GALLOP.duty, t), .lag = mathx.lerpF(TROT.lag, GALLOP.lag, t) };
}

/// STRIDE LENGTH IN METRES AT A GIVEN SPEED, and it is LINEAR — measured, across every gait a dog uses. The intercept is what keeps a near-stationary creature's phase from running away to nothing.
pub fn strideFor(speed: f32) f32 {
    return mathx.clampF(0.55 * speed + 0.06, 0.34, 1.70);
}

pub fn limbPhases(p: f32, g: Gait) [4]f32 {
    return .{
        wrap01(p),
        wrap01(p + 0.5),
        wrap01(p + g.lag),
        wrap01(p + g.lag + 0.5),
    };
}

pub fn wrap01(x: f32) f32 {
    const f = x - @floor(x);
    return if (f < 0) f + 1.0 else f;
}

pub fn planted(phase: f32, g: Gait) bool {
    return phase < g.duty;
}

pub fn pawAt(phase: f32, g: Gait, stride: f32, w: f32) struct { z: f32, y: f32 } {
    const half = stride * g.duty * 0.5;
    if (planted(phase, g)) {
        const s = phase / g.duty;
        return .{ .z = half * (1.0 - 2.0 * s), .y = 0 };
    }
    const s = (phase - g.duty) / (1.0 - g.duty);
    return .{ .z = half * (-1.0 + 2.0 * s), .y = SWING_LIFT * w * mathx.sinf(s * std.math.pi) };
}

const SWING_LIFT: f32 = 0.115;

/// **THE SHARED HALF OF THE QUADRUPED RIG** — a free function over `rest` and a withers height, because a second
/// four-legged creature owes a stature and a head, never a transcription of the joint layout. `crouch` is how far the animal has sunk off the joint's own height, `tuck` how far the paws are drawn up under it, 0..1 of the limb's reach.
pub fn legs(
    wx: *[N]rl.Matrix,
    rest: *const [N]rl.Vector3,
    w: f32,
    ph: [4]f32,
    g: Gait,
    stride: f32,
    m: f32,
    crouch: f32,
    tuck: f32,
) void {
    inline for (LIMBS, 0..) |L, i| {
        const phase = ph[i];
        const top = L.bones[0];
        const mid = L.bones[1];
        const low = L.bones[2];
        const paw = L.bones[3];
        const at = pawAt(phase, g, stride, w);
        const dz = -at.z * m;
        const dy = ((L.jointY - crouch) * w - at.y * m) * (1.0 - mathx.clampF(tuck, 0, 0.6));
        const sol = limbChain(L.upper * w, L.lower * w, dy, dz, L.bend);
        heromod.setJoint(wx, rest, top, @intCast(PARENT[top]), rx(sol.upper));
        heromod.setJoint(wx, rest, mid, top, rx(sol.lower));
        // The carpus/hock takes a share of the lower segment's fold back the other way — that second bend is the zig-zag a canid's leg has and a two-link solve cannot show.
        heromod.setJoint(wx, rest, low, mid, rx(-sol.lower * 0.45));
        const lift: f32 = if (planted(phase, g)) 0 else 26.0 * m;
        heromod.setJoint(wx, rest, paw, low, rx(-sol.upper - sol.lower * 0.55 + lift));
    }
}

pub fn limbChain(a: f32, b: f32, dy: f32, dz: f32, bend: f32) struct { upper: f32, lower: f32 } {
    const want = @sqrt(dy * dy + dz * dz);
    const d = mathx.clampF(want, @abs(a - b) + 1e-4, a + b - 1e-4);
    const t = std.math.atan2(dz, @max(dy, 1e-4));
    const alpha = std.math.acos(mathx.clampF((a * a + d * d - b * b) / (2.0 * a * d), -1, 1));
    const knee = std.math.acos(mathx.clampF((a * a + b * b - d * d) / (2.0 * a * b), -1, 1));
    return .{
        .upper = mathx.degrees(t + bend * alpha),
        .lower = -bend * mathx.degrees(std.math.pi - knee),
    };
}

const SHEEN: u8 = 206;
const SHEEN_LT: u8 = 188;
const PELT = rgba(44, 47, 55, SHEEN);
const PELT_LT = rgba(66, 70, 79, SHEEN_LT);
const SADDLE = rgba(27, 29, 35, SHEEN);
const BELLY = rgba(84, 84, 86, SHEEN_LT);
const MUZZLE_DK = rgba(24, 25, 29, SHEEN);
const PAW = rgba(28, 29, 34, SHEEN);
const FUR = rgba(78, 86, 98, 172);
const FUR_DK = rgba(40, 44, 52, SHEEN);

/// How solid he draws in the lit pass. With depth writes ON, the far side of him is already gone, so the remaining alpha does ONE job — letting a little of the world through his near face — and at 0.72 that read as a jellyfish.
pub const SPIRIT_FADE: f32 = 0.86;
const NOSE = rgba(22, 20, 19, 255);
const EYE = rgba(150, 180, 210, 110);

fn peltAt(k: f32) rl.Color {
    if (k > 0.72) return SADDLE;
    if (k < 0.28) return BELLY;
    return PELT;
}

fn furRing(b: *Builder, rng: *mathx.Rng, at: rl.Vector3, r: f32, len: f32, n: i32, col: rl.Color) void {
    var k: i32 = 0;
    while (k < n) : (k += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(n)) + rng.range(-0.30, 0.30);
        const c = mathx.cosf(a);
        const sn = mathx.sinf(a);
        const l = len * rng.range(0.55, 1.30);
        const OUT = 0.34;
        const from = v3(at.x + c * r * 0.55, at.y + sn * r * 0.55, at.z + rng.range(-0.25, 0.25) * r);
        const to = v3(
            at.x + c * (r + l * OUT),
            at.y + sn * (r + l * OUT) - l * 0.16,
            at.z - l * rng.range(0.72, 1.05),
        );
        b.addCapsule(from, to, r * 0.16, r * 0.055, 5, col);
    }
}

fn boneMesh(i: usize) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x1F0 +% @as(u64, i));
    b.setMat(.hide);
    const s = W;
    switch (i) {
        // THE TRUNK, ROUND and ONE MASS: blobs and capsules, never a box. Each section OVERLAPS its neighbour well past the joint (the packed-stone rule) and the radii GRADE. The chest is DEEP — brisket 0.55 W to withers 1.00 — and the barrel is WIDE on the X radii, because depth alone reads as a slab.
        CHEST => {
            const dep = (SHOULDER_Y - BRISKET_Y) + 0.26;
            b.addBlob(v3(0, -0.015 * s, -0.10 * s), v3(0.205 * s, dep * 0.5 * s, 0.36 * s), 6, 11, peltAt(0.5));
            b.addBlob(v3(0, 0.105 * s, -0.12 * s), v3(0.160 * s, 0.090 * s, 0.22 * s), 5, 10, SADDLE);
            b.addBlob(v3(0, -0.135 * s, -0.09 * s), v3(0.140 * s, 0.072 * s, 0.19 * s), 4, 9, BELLY);
            furRing(&b, &rng, v3(0, 0.075 * s, -0.16 * s), 0.150 * s, 0.080 * s, 9, FUR);
            furRing(&b, &rng, v3(0, 0.020 * s, 0.09 * s), 0.185 * s, 0.055 * s, 8, FUR_DK);
        },
        SPINE => {
            b.addBlob(v3(0, 0.005 * s, 0), v3(0.172 * s, 0.160 * s, 0.26 * s), 5, 10, peltAt(0.55));
            b.addBlob(v3(0, -0.092 * s, 0), v3(0.120 * s, 0.055 * s, 0.16 * s), 4, 9, BELLY);
        },
        ROOT => {
            b.addBlob(v3(0, -0.01 * s, 0.06 * s), v3(0.196 * s, 0.180 * s, 0.28 * s), 5, 10, peltAt(0.5));
            b.addBlob(v3(0, 0.095 * s, 0.05 * s), v3(0.145 * s, 0.078 * s, 0.18 * s), 4, 9, SADDLE);
            furRing(&b, &rng, v3(0, -0.020 * s, -0.10 * s), 0.190 * s, 0.090 * s, 10, FUR);
        },
        NECK => {
            b.addCapsule(v3(0, -0.03 * s, -0.10 * s), v3(0, 0.02 * s, 0.16 * s), 0.165 * s, 0.100 * s, 10, peltAt(0.6));
            b.addBlob(v3(0, 0.005 * s, -0.02 * s), v3(0.195 * s, 0.150 * s, 0.140 * s), 4, 10, SADDLE);
            furRing(&b, &rng, v3(0, 0.005 * s, -0.03 * s), 0.190 * s, 0.105 * s, 11, FUR);
            furRing(&b, &rng, v3(0, 0.000 * s, 0.055 * s), 0.155 * s, 0.070 * s, 9, FUR);
            b.addCapsule(v3(0, -0.085 * s, -0.02 * s), v3(0, -0.050 * s, 0.14 * s), 0.088 * s, 0.058 * s, 8, BELLY);
        },
        HEAD => {
            b.addBlob(v3(0, 0.005 * s, -0.01 * s), v3(0.082 * s, 0.078 * s, 0.098 * s), 4, 10, peltAt(0.7));
            b.addBlob(v3(0.048 * s, -0.018 * s, 0.045 * s), v3(0.034 * s, 0.040 * s, 0.055 * s), 3, 8, peltAt(0.5));
            b.addBlob(v3(-0.048 * s, -0.018 * s, 0.045 * s), v3(0.034 * s, 0.040 * s, 0.055 * s), 3, 8, peltAt(0.5));
            b.addCapsule(v3(0, -0.018 * s, 0.045 * s), v3(0, -0.036 * s, 0.150 * s), 0.058 * s, 0.044 * s, 9, peltAt(0.55));
            b.addBlob(v3(0, -0.038 * s, 0.162 * s), v3(0.040 * s, 0.035 * s, 0.030 * s), 3, 8, MUZZLE_DK);
            b.addBlob(v3(0, -0.028 * s, 0.178 * s), v3(0.020 * s, 0.017 * s, 0.014 * s), 3, 7, NOSE);
            b.addBlob(v3(0.042 * s, 0.024 * s, 0.070 * s), v3(0.016 * s, 0.014 * s, 0.013 * s), 3, 7, EYE);
            b.addBlob(v3(-0.042 * s, 0.024 * s, 0.070 * s), v3(0.016 * s, 0.014 * s, 0.013 * s), 3, 7, EYE);
        },
        JAW => {
            b.addCapsule(v3(0, 0, 0.02 * s), v3(0, -0.010 * s, 0.125 * s), 0.032 * s, 0.024 * s, 7, MUZZLE_DK);
            b.addBlob(v3(0, 0.004 * s, 0.060 * s), v3(0.026 * s, 0.016 * s, 0.055 * s), 3, 7, BELLY);
        },
        EARL, EARR => {
            const lean: f32 = if (i == EARL) 1.0 else -1.0;
            const h = 0.105 * s * rng.range(0.94, 1.06);
            b.addCapsule(v3(0, 0, 0), v3(lean * 0.020 * s, h, -0.014 * s), 0.044 * s, 0.020 * s, 7, peltAt(0.8));
            b.addCapsule(v3(0, 0.008 * s, 0.006 * s), v3(lean * 0.015 * s, h * 0.80, -0.006 * s), 0.030 * s, 0.011 * s, 6, MUZZLE_DK);
        },
        TAIL0, TAIL1, TAIL2 => {
            const r0: f32 = switch (i) {
                TAIL0 => 0.082,
                TAIL1 => 0.076,
                else => 0.058,
            };
            const tip = v3(0, -0.055 * s, -0.150 * s);
            b.addCapsule(v3(0, 0, 0), tip, r0 * s, r0 * s * 0.88, 8, peltAt(0.62));
            furRing(&b, &rng, v3(0, -0.028 * s, -0.075 * s), r0 * s * 0.92, 0.070 * s, 7, FUR);
            if (i == TAIL2) {
                b.addBlob(tip, v3(0.052 * s, 0.052 * s, 0.058 * s), 3, 8, MUZZLE_DK);
                furRing(&b, &rng, tip, r0 * s * 0.80, 0.055 * s, 6, FUR_DK);
            }
        },
        SHL, SHR => b.addCapsule(v3(0, 0.02 * s, 0), v3(0, -HUMERUS * s, 0), 0.105 * s, 0.062 * s, 8, peltAt(0.45)),
        HIPL, HIPR => b.addCapsule(v3(0, 0.02 * s, 0), v3(0, -FEMUR * s, 0), 0.125 * s, 0.068 * s, 8, peltAt(0.45)),
        ELL, ELR => b.addCapsule(v3(0, 0, 0), v3(0, -FORE_LOWER * 0.68 * s, 0), 0.062 * s, 0.036 * s, 7, peltAt(0.3)),
        STL, STR => b.addCapsule(v3(0, 0, 0), v3(0, -HIND_LOWER * 0.62 * s, 0), 0.078 * s, 0.038 * s, 7, peltAt(0.3)),
        CAL, CAR => b.addCapsule(v3(0, 0, 0), v3(0, -FORE_LOWER * 0.32 * s, 0), 0.038 * s, 0.032 * s, 6, peltAt(0.2)),
        HKL, HKR => b.addCapsule(v3(0, 0, 0), v3(0, -HIND_LOWER * 0.38 * s, 0), 0.040 * s, 0.033 * s, 6, peltAt(0.2)),
        PAWL, PAWR, HPAWL, HPAWR => {
            b.addBlob(v3(0, 0.020 * s, 0.016 * s), v3(0.052 * s, 0.034 * s, 0.064 * s), 3, 8, PAW);
        },
        else => {},
    }
    return b.toMesh();
}

pub const SCALE: f32 = 1.0;
pub const BODY_R: f32 = 0.34;
pub const HURT_R: f32 = 0.42;
const CENTER_H: f32 = 0.62;
const TOP_H: f32 = 1.05;

pub const HP: f32 = 88.0;
pub const POISE: f32 = 26.0;
pub const STANCE: f32 = 52.0;

pub const DEATH_DUR: f32 = 1.05;
pub const DISS_DUR: f32 = 1.25;
pub const DISSOLVE = foe.Dissolve{ .rate = 62.0, .spread = 1.05, .rise = 0.85, .flake = PELT_LT };

pub const HUNT_R: f32 = 16.0;
/// **A FOE THE HERO HAS WALKED AWAY FROM IS NOT THIS SPIRIT'S PROBLEM.** Its tether is to HIM, not to a post — the whole difference between a summon and a creature. At the old 19 m it would stay behind worrying at an archer the player had long since left.
pub const TETHER_R: f32 = 12.0;
/// …and the hard recall. Past this from him, NOTHING is worth chasing. Above `TETHER_R` so the two rules cannot fight — the first stops it TAKING distant work, this one drops work it is already on.
pub const RECALL_R: f32 = 15.0;
pub const HEEL_R: f32 = 3.2;
pub const RUN_GAP: f32 = 7.0;
/// HOW LONG IT MAY BE OUT PAST `RECALL_R` BEFORE THE BOND MOVES IT ITSELF. Measured against the recall ring rather than a distance of its own, so the clock only runs while it has already been told to come back.
pub const LOST_DWELL: f32 = 3.0;
pub const BITE_R: f32 = 1.35;

const BITE_WIND: f32 = 0.26;
const BITE_STRIKE: f32 = 0.16;
const BITE_RECOVER: f32 = 0.34;
const BITE_COOL: f32 = 0.55;
const BITE_HOP: f32 = 0.62;
const BITE_TRIGGER_R: f32 = BITE_R + BITE_HOP * 0.8;

pub const HUNT_KEEP: f32 = 1.7;

/// A point, HOW BROAD (the bite gate is off the radius), HOW HIGH the mass sits, and WHICH BODY. The key is OPAQUE — only `game.zig` mints one and reads it back. **`aim` IS WHY THE LEAP IS THE QUARRY'S AND NOT A CONSTANT**: metres above the quarry's OWN FEET, so 0 means "no idea", a flat-footed snap.
pub const Quarry = struct { at: rl.Vector3, r: f32 = 0, aim: f32 = 0, key: u32 = NO_QUARRY };
pub const NO_QUARRY: u32 = std.math.maxInt(u32);

/// **THE GATE IS MEASURED FROM THE QUARRY'S HIDE, NOT ITS CENTRE** — the knight's `triggerR` idiom. Asked
/// centre-to-centre, a flat 1.85 m is unsatisfiable on anything broad: `env.resolveActor` holds the wolf `bodyR + its own` out, which on the Bone Knight is 2.11 m, so the jaws opened 0.26 m closer than the animal could ever stand. The ogre had 0.24 m of margin.
pub fn triggerR(quarryR: f32) f32 {
    return BITE_TRIGGER_R + quarryR;
}

/// The one dial the halt sits on, named for the same reason the skitterer's and the hollow's are.
const STOP_FRAC: f32 = 0.85;
fn stopR(quarryR: f32) f32 {
    return BITE_R * STOP_FRAC + quarryR;
}
comptime {
    std.debug.assert(stopR(foe.HERO_R) < triggerR(foe.HERO_R));
}
/// **WHAT THE LEAP BUYS IS HEIGHT**, as a fraction of `W`. At 0.14 it lifted the teeth 0.16 m onto a resting 1.08 — 0.25 m inside the BOTTOM of an ogre's hurt sphere, a 0.89 m window against a collider holding her 1.61 m out. MEASURED: `POUNCE_INTO` says how far up the mass the teeth must arrive.
pub const BITE_HOP_UP: f32 = 0.40;
pub const BITE_PITCH: f32 = 24.0;
/// **AND SHE STILL LEAVES THE GROUND FOR THE LOWEST THING SHE BITES** — the share of the leap a `pounce` of 0 keeps. This is what the hop used to be (0.14 of `W`) as a fraction of what the full leap is now.
pub const HOP_FLOOR: f32 = 0.14 / BITE_HOP_UP;
/// **HOW FAR UP THE MASS THE TEETH HAVE TO ARRIVE**, as a share of the hurt sphere's own radius above its floor
/// — the requirement the two dials above are solved against. A share rather than a height because the thing she is biting is a toad on one day and a five-metre knight on the next. At half the radius the horizontal window on an ogre opens from 0.89 m to 1.44 m.
pub const POUNCE_INTO: f32 = 0.5;

pub fn pounceApexT() f32 {
    return (BITE_WIND * 0.55 + BITE_WIND + BITE_STRIKE) * 0.5;
}

/// WHERE HER TEETH ARE WITH ALL FOUR PAWS DOWN, and at the top of a full pounce — the two ends of the dial `pounceFor` interpolates. MEASURED off the posed rig by a test rather than written from the pose's arithmetic.
pub const TEETH_REST: f32 = 1.08;
pub const TEETH_POUNCE: f32 = 1.97;

pub fn pounceFor(aim: f32) f32 {
    return mathx.clampF((aim - TEETH_REST) / (TEETH_POUNCE - TEETH_REST), 0, 1);
}

/// **AND SHE PUTS HER NOSE DOWN FOR WHAT IS ON THE FLOOR.** `pounceFor` only ever asked for HEIGHT: under her
/// resting teeth it clamped to 0 and the jaws shut at `TEETH_REST`, over the top of a sporeling entirely. **AND IT IS THE NECK THAT GOES DOWN, NOT THE BODY** — dropping the root would sink the legs (FEET DO NOT SINK), so the stoop is degrees through NECK and HEAD.
pub const STOOP_MAX: f32 = 62.0;
/// **AND THE FOREQUARTERS COME DOWN WITH IT — A PLAY-BOW.** The neck alone is worth 0.20 m (a canid's neck reaches FORWARD, so rotating it swings the skull down AND back) against a 0.65 m gap to a sporeling. In W units, through the SAME `crouch` the gather uses.
pub const STOOP_SINK: f32 = 0.26;
pub const STOOP_NECK_SHARE: f32 = 0.62;
pub const STOOP_LOW: f32 = 0.34;
/// WHERE HER TEETH ARE AT A FULL STOOP, the third end of the same dial. MEASURED off the posed rig.
pub const TEETH_STOOP: f32 = 0.39;

pub fn stoopFor(aim: f32) f32 {
    if (aim <= 0) return 0;
    return mathx.clampF((TEETH_REST - aim) / (TEETH_REST - STOOP_LOW), 0, 1);
}

comptime {
    std.debug.assert(STOOP_LOW < TEETH_REST and TEETH_REST < TEETH_POUNCE);
    // WHAT THE STOOP ACTUALLY REACHES IS NOT ASSERTABLE HERE — it comes out of the posed rig off three contributions (the neck, the bow, and the hop it gives up). The bar is `POUNCE_INTO` against the smallest sphere she is asked to bite, and the test is where that lives.
    std.debug.assert(TEETH_STOOP < TEETH_REST);
    std.debug.assert(STOOP_NECK_SHARE > 0.5 and STOOP_NECK_SHARE < 1.0);
}
const BITE_CROUCH: f32 = 0.09;
pub var BITE_HIT = combat.Hit{ .dmg = 21, .poise = 16, .stance = 3 };

const GROWL_EVERY: f32 = 2.6;

/// THE DISSOLVE'S RING, named rather than left a bare literal — a ring overwrites its oldest SILENTLY. `DISSOLVE.rate` 62 a second against a mean life of ~0.72 s stands about 45 at the fade's start.
const PARTS = 48;
const RIFT_N = 12;
/// What the rift's light dies to — cold blue-white down to a dim slate, never a warm ember.
const RIFT_COOL = rgba(72, 96, 128, 40);

/// How far down the jaw bone the teeth sit, as a fraction of `W` — where the bite's blade is measured from.
const JAW_REACH: f32 = 0.10;

pub const SHOVE = foe.Push{ .light = 1.44, .heavy = 3.30 };
const SHOVE_DECAY: f32 = 6.0;

const TURN_RATE: f32 = 5.6;
const ACCEL: f32 = 9.0;
const GAIT_BLEND: f32 = 8.0;

pub const State = enum { idle, move, bite, hurt, dead };

pub const Wolf = struct {
    pos: rl.Vector3 = mathx.zero3,
    facing: f32 = 0,
    scale: f32 = SCALE,
    vit: combat.Vitals = combat.Vitals.initFoe(HP, POISE, STANCE),
    state: State = .idle,
    t: f32 = 0,
    phase: f32 = 0,
    speed: f32 = 0,
    speedS: f32 = 0,
    justDied: bool = false,
    bit: bool = false,
    growled: bool = false,
    yelped: bool = false,
    growlCool: f32 = 0,
    hitLatch: bool = false,
    heavyStun: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    /// WHICH BODY IT IS GOING FOR. An index into the field, handed in by game.zig — the creature never reaches out for the foe list (`foe.Parry`'s law).
    quarry: ?Quarry = null,
    nav: foe.Nav = .{},
    /// SECONDS IT HAS BEEN OUT PAST `RECALL_R`, measured against `LOST_DWELL`.
    lostT: f32 = 0,
    biteCool: f32 = 0,
    wasAt: rl.Vector3 = mathx.zero3,
    pounce: f32 = 0,
    /// …and the same latch for the OTHER half of the dial (`stoopFor`). Latched at the commit for `pounce`'s reason, and never both at once (the comptime assert above).
    stoop: f32 = 0,
    jaw0: rl.Vector3 = mathx.zero3,
    jaw1: rl.Vector3 = mathx.zero3,
    fade: f32 = 0,
    gone: bool = false,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(0xD16E),
    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    rest: [N]rl.Vector3 = undefined,
    xf: [N]rl.Matrix = undefined,

    pub fn alive(self: *const Wolf) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Wolf) bool {
        return self.state == .dead;
    }
    pub fn airborne(_: *const Wolf) bool {
        return false;
    }
    pub fn bodyR(self: *const Wolf) f32 {
        return BODY_R * self.scale;
    }
    pub fn hurtRadius(self: *const Wolf) f32 {
        return HURT_R * self.scale;
    }
    pub fn centerWorld(self: *const Wolf) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_H * W, self.scale, 0);
    }
    pub fn topWorld(self: *const Wolf) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_H * W, self.scale, 0);
    }
    pub fn lockPoint(self: *const Wolf) rl.Vector3 {
        return foe.markOn(self.xf[HEAD], v3(0, 0.02 * W, 0.05 * W));
    }
    pub fn flashFrac(self: *const Wolf) f32 {
        return self.flash;
    }
    pub fn facePoint(self: *const Wolf) rl.Vector3 {
        return foe.markOn(self.xf[HEAD], v3(0, 0.02 * W, 0.24 * W));
    }

    pub fn spawn(at: rl.Vector3, facing: f32) Wolf {
        var w = Wolf{ .pos = at, .facing = facing, .rest = restPose(W) };
        w.pose();
        // THE JAW STARTS WHERE THE JAW IS. Left at the origin, the first frame's swept bite is a segment from world zero to its teeth — a blade across the entire map.
        w.jaw1 = w.jawPoint();
        w.jaw0 = w.jaw1;
        return w;
    }

    pub fn jawPoint(self: *const Wolf) rl.Vector3 {
        return foe.markOn(self.xf[JAW], v3(0, 0, JAW_REACH * W));
    }

    pub fn takeHit(self: *Wolf, h: combat.Hit) combat.HitOutcome {
        if (self.state == .dead or self.gone) return .ignored;
        const r = self.vit.hit(h);
        self.flash = 1.0;
        switch (r) {
            .death => {
                self.enterDeath();
                return .taken;
            },
            .heavy, .light => {
                self.state = .hurt;
                self.t = 0;
                self.heavyStun = r == .heavy;
                self.yelped = true;
            },
            .none => {},
        }
        return .taken;
    }

    fn enterDeath(self: *Wolf) void {
        self.state = .dead;
        self.t = 0;
        self.justDied = true;
    }

    pub fn blade(self: *const Wolf) foe.Blade {
        const live = self.state == .bite and self.t >= BITE_WIND and self.t < BITE_WIND + BITE_STRIKE;
        return .{
            .active = live,
            .r = 0.20 * self.scale,
            .a = self.jaw0,
            .b = self.jaw1,
            .a0 = self.jaw0,
            .b0 = self.jaw1,
            .pierce = true,
            .by = .spirit,
            .hit = BITE_HIT,
        };
    }

    pub fn update(self: *Wolf, dt: f32, heel: rl.Vector3, bounds: f32) void {
        self.justDied = false;
        self.wasAt = self.pos;
        self.bit = false;
        self.growled = false;
        self.yelped = false;
        self.growlCool = mathx.maxF(0, self.growlCool - dt);
        self.t += dt;
        self.vit.tick(dt);
        foe.fadeFlash(&self.flash, dt);
        self.biteCool = mathx.maxF(0, self.biteCool - dt);
        // HOW LONG IT HAS BEEN OUT OF HIS REACH. Up here with the other clocks and BEFORE the early returns: a spirit stuck 20 m off worrying at something is exactly as lost as one stuck against a bank.
        if (mathx.distXZ(self.pos, heel) > RECALL_R) self.lostT += dt else self.lostT = 0;
        foe.tickParticles(&self.parts, dt, self.pos.y);
        self.jaw0 = self.jaw1;

        if (self.state == .dead) {
            foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            self.speed = 0;
            self.pose();
            return;
        }
        if (self.state == .hurt) {
            if (self.t >= combat.foeStunDur(self.heavyStun)) self.state = .idle;
            self.speed = 0;
            self.settle(dt, bounds);
            self.pose();
            return;
        }
        if (self.state == .bite) {
            self.faceToward(if (self.quarry) |q| q.at else heel, dt);
            self.speed = 0;
            const hopEnd = BITE_WIND + BITE_STRIKE;
            if (self.t < hopEnd) {
                const step = BITE_HOP * (dt / hopEnd);
                mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), step, bounds);
            }
            if (self.t >= hopEnd + BITE_RECOVER) {
                self.state = .idle;
                self.t = 0;
                self.biteCool = BITE_COOL;
                self.hitLatch = false;
            }
            self.settle(dt, bounds);
            self.pose();
            return;
        }

        const want = self.wants(heel);
        const gap = mathx.distXZ(self.pos, want);
        const stop: f32 = if (self.quarry) |q| stopR(q.r) else HEEL_R;
        if (self.quarry != null and gap <= triggerR(self.quarry.?.r) and self.biteCool <= 0) {
            self.state = .bite;
            self.t = 0;
            self.hitLatch = false;
            self.speed = 0;
            self.pounce = pounceFor(self.quarry.?.aim);
            self.stoop = stoopFor(self.quarry.?.aim);
            self.bit = true;
        } else if (gap > stop) {
            if (self.quarry != null and self.growlCool <= 0) {
                self.growled = true;
                self.growlCool = GROWL_EVERY;
            }
            const far = gap > RUN_GAP;
            const want_speed: f32 = if (far or self.quarry != null)
                GALLOP_SPEED * 0.82
            else if (gap > HEEL_R * 2.0) TROT_SPEED else WALK_SPEED;
            self.speed = mathx.approach(self.speed, want_speed, ACCEL * dt);
            self.state = .move;
            // …AND IT TURNS ROUND WHAT IS IN THE WAY RATHER THAN INTO IT (`foe.Nav`). It walks where it is LOOKING, so the way through is read at the FACING and the step below is untouched — the GAP is still measured to the real target.
            self.faceToward(self.nav.aim(self.pos, want), dt);
            const step = self.speed * dt;
            mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), step, bounds);
            self.phase = wrap01(self.phase + step / strideFor(self.speed));
        } else {
            self.speed = mathx.approach(self.speed, 0, ACCEL * 2.0 * dt);
            self.state = .idle;
            self.faceToward(self.wants(heel), dt);
        }
        self.settle(dt, bounds);
        self.pose();
    }

    fn settle(self: *Wolf, dt: f32, bounds: f32) void {
        self.speedS = mathx.approach(self.speedS, self.speed, GAIT_BLEND * dt);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);
    }

    pub fn wants(self: *const Wolf, heel: rl.Vector3) rl.Vector3 {
        return if (self.quarry) |q| q.at else heel;
    }

    pub fn quarryKey(self: *const Wolf) u32 {
        return if (self.quarry) |q| q.key else NO_QUARRY;
    }

    /// …and the same thing as the steering asks it (`foe.Nav`): null while it is not walking anywhere, so a
    /// stale heading cannot bend the bite's own hop or a stun.
    pub fn navWant(self: *const Wolf, heel: rl.Vector3) ?rl.Vector3 {
        if (self.state == .dead or self.state == .hurt or self.state == .bite) return null;
        return self.wants(heel);
    }

    pub fn lost(self: *const Wolf) bool {
        return self.lostT >= LOST_DWELL and self.state != .dead and !self.gone;
    }

    pub fn reappear(self: *Wolf, at: rl.Vector3, facing: f32) void {
        const was = self.pos;
        const from = self.fxHead;
        self.rift(was);
        foe.floorBurst(&self.parts, from, self.fxHead, was.y);
        self.pos = at;
        self.facing = facing;
        self.state = .idle;
        self.t = 0;
        self.speed = 0;
        self.speedS = 0;
        self.shove = mathx.zero3;
        self.lostT = 0;
        self.nav = .{};
        self.wasAt = at;
        self.rift(at);
        self.pose();
        self.jaw1 = self.jawPoint();
        self.jaw0 = self.jaw1;
    }

    fn rift(self: *Wolf, at: rl.Vector3) void {
        var i: i32 = 0;
        while (i < RIFT_N) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(1.4, 3.0) * self.scale;
            // The draws stay in the order they were written in — height, velocity, life, radius, THEN the coin for which half this mote is. Hoisting that coin re-deals every rift off the same seed.
            const p = v3(at.x, at.y + (CENTER_H * W + self.fxRng.range(-0.32, 0.42)) * self.scale, at.z);
            const v = v3(mathx.cosf(a) * sp, self.fxRng.range(-0.3, 1.5), mathx.sinf(a) * sp);
            const life = self.fxRng.range(0.18, 0.32);
            const r0 = self.fxRng.range(0.030, 0.058) * self.scale;
            // HALF LIGHT, HALF PELT — the rift's glow is additive and cools out; the fur torn off with it is matter and stays alpha, or it would brighten into the same white smear.
            const lit = self.fxRng.float() < 0.4;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = p,
                .v = v,
                .life = life,
                .r0 = r0,
                .r1 = 0.006,
                .col = if (lit) EYE else PELT_LT,
                .col1 = if (lit) RIFT_COOL else null,
                .grav = 1.2,
                .stretch = 0.030,
                .drag = 2.4,
                .add = lit,
            });
        }
    }

    fn faceToward(self: *Wolf, at: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, at, TURN_RATE, dt);
    }

    pub fn stageGather(self: *Wolf, u: f32) void {
        self.state = .bite;
        self.t = mathx.clampF(u, 0, 1) * BITE_WIND;
        self.pose();
    }

    pub fn stagePounce(self: *Wolf, amt: f32) void {
        self.state = .bite;
        self.pounce = mathx.clampF(amt, 0, 1);
        self.stoop = 0;
        self.t = pounceApexT();
        self.pose();
    }

    /// **THE BITE AS IT WOULD ACTUALLY ARRIVE AT A BODY OF THAT MASS HEIGHT**, both halves of the dial latched off ONE number exactly as `update` does. The hook is `aim` and not the pair, because a leap and a stoop set by hand can be given values the fight can never produce.
    pub fn stageBiteAt(self: *Wolf, aim: f32) void {
        self.state = .bite;
        self.pounce = pounceFor(aim);
        self.stoop = stoopFor(aim);
        self.t = pounceApexT();
        self.pose();
    }

    pub fn pose(self: *Wolf) void {
        const g = gaitAt(self.speedS);
        const stride = strideFor(self.speedS);
        const ph = limbPhases(self.phase, g);
        const m = mathx.clampF(self.speedS / WALK_SPEED, 0, 1);
        const s = self.scale;
        const breath = mathx.sinf(self.t * 2.1) * 0.006 * W;
        const react: f32 = if (self.state == .hurt) foe.stunCurve(self.t, self.heavyStun) else 0;
        const fall: f32 = if (self.state == .dead) mathx.clampF(self.t / (DEATH_DUR * 0.7), 0, 1) else 0;

        // One arc off the bite's own clock, so the lift and the travel cannot drift apart the way a second timer would let them.
        var hop: f32 = 0;
        var crouch: f32 = 0;
        // …AND THE NOSE-UP RIDES THE SAME ARC, so the jaws cannot be highest while the body is not.
        var pitch: f32 = 0;
        var duckN: f32 = 0;
        if (self.state == .bite) {
            const hopEnd = BITE_WIND + BITE_STRIKE;
            crouch = BITE_CROUCH * mathx.smoothstep(0, BITE_WIND * 0.8, self.t) * (1.0 - mathx.smoothstep(BITE_WIND, hopEnd, self.t));
            if (self.t > BITE_WIND * 0.55 and self.t < hopEnd) {
                const u = (self.t - BITE_WIND * 0.55) / (hopEnd - BITE_WIND * 0.55);
                const bell = mathx.sinf(u * std.math.pi);
                // **AND SHE GIVES UP THE HOP TO STOOP.** `HOP_FLOOR` is the flat-footed snap and it lifts the teeth 0.16 m — the wrong way for a mouthful of dirt, and a sixth of the whole gap to a sporeling.
                const arc = bell * mathx.lerpF(HOP_FLOOR * (1.0 - self.stoop), 1.0, self.pounce);
                hop = BITE_HOP_UP * arc;
                pitch = BITE_PITCH * arc;
                crouch += STOOP_SINK * bell * self.stoop;
                duckN = STOOP_MAX * bell * self.stoop;
            }
        }
        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            mul(rx(-pitch), rz(-72.0 * mathx.smoothstep(0, 1, fall))),
            mul(tr(0, self.rest[ROOT].y * s + breath + (hop - crouch) * W - 0.10 * W * fall, 0), ry(mathx.degrees(self.facing))),
            heromod.rootAt(self.pos),
        );
        const flex = mathx.sinf(self.phase * std.math.tau) * m * (4.0 + 9.0 * mathx.clampF((self.speedS - TROT_SPEED) / (GALLOP_SPEED - TROT_SPEED), 0, 1));
        const duck: f32 = 8.0 * react;
        heromod.setJoint(&wx, &self.rest, SPINE, ROOT, rx(-flex * 0.5 - duck * 0.3));
        heromod.setJoint(&wx, &self.rest, CHEST, SPINE, rx(-flex * 0.5 - duck * 0.3));
        heromod.setJoint(&wx, &self.rest, NECK, CHEST, rx(flex * 0.7 + 6.0 * m - duck + duckN * STOOP_NECK_SHARE));
        heromod.setJoint(&wx, &self.rest, HEAD, NECK, rx(flex * 0.3 - 4.0 * m - duck * 0.6 + duckN * (1.0 - STOOP_NECK_SHARE)));
        const gape: f32 = if (self.state == .bite) blk: {
            if (self.t < BITE_WIND) break :blk 34.0 * mathx.smoothstep(0, BITE_WIND, self.t);
            break :blk 34.0 * (1.0 - mathx.smoothstep(BITE_WIND, BITE_WIND + BITE_STRIKE * 0.5, self.t));
        } else 0;
        heromod.setJoint(&wx, &self.rest, JAW, HEAD, rx(gape));
        const ear: f32 = -58.0 * react;
        heromod.setJoint(&wx, &self.rest, EARL, HEAD, mul(rx(ear), rz(-6.0)));
        heromod.setJoint(&wx, &self.rest, EARR, HEAD, mul(rx(ear), rz(6.0)));
        const tailSwing = mathx.sinf(self.phase * std.math.tau + 1.1) * 7.0 * m;
        heromod.setJoint(&wx, &self.rest, TAIL0, ROOT, mul(rx(-12.0 * m + 26.0 * react), ry(tailSwing)));
        heromod.setJoint(&wx, &self.rest, TAIL1, TAIL0, mul(rx(-6.0 * m + 10.0 * react), ry(tailSwing * 0.8)));
        heromod.setJoint(&wx, &self.rest, TAIL2, TAIL1, mul(rx(-3.0 * m), ry(tailSwing * 0.6)));

        const tuck = hop / @max(HIP_Y, 0.001);
        legs(&wx, &self.rest, W, ph, g, stride, m, crouch, tuck);
        self.xf = wx;
    }

    pub fn draw(self: *const Wolf, mesh: *const [N]rl.Mesh, mat: rl.Material) void {
        if (self.gone) return;
        for (0..N) |i| rl.drawMesh(mesh[i], mat, self.xf[i]);
    }

    pub fn drawFx(self: *const Wolf) void {
        foe.drawParticles(&self.parts);
    }
};

pub const Pack = struct {
    wolves: [combat.SUMMON_MAX]Wolf = undefined,
    n: usize = 0,
    mesh: [N]rl.Mesh = undefined,
    mat: rl.Material = undefined,
    ready: bool = false,

    pub fn load(self: *Pack, shader: rl.Shader) void {
        for (0..N) |i| self.mesh[i] = boneMesh(i);
        self.mat = gfx.material(shader, "wolf");
        self.ready = true;
    }
    pub fn setShader(self: *Pack, sh: rl.Shader) void {
        self.mat.shader = sh;
    }

    pub fn live(self: *Pack) []Wolf {
        return self.wolves[0..self.n];
    }
    pub fn liveConst(self: *const Pack) []const Wolf {
        return self.wolves[0..self.n];
    }
    pub fn room(self: *const Pack) bool {
        return self.n < combat.SUMMON_MAX;
    }
    pub fn firstConst(self: *const Pack) ?*const Wolf {
        if (self.n == 0) return null;
        return &self.wolves[0];
    }

    pub fn clear(self: *Pack) void {
        self.n = 0;
    }

    pub fn call(self: *Pack, at: rl.Vector3, facing: f32) bool {
        if (!self.room()) return false;
        self.wolves[self.n] = Wolf.spawn(at, facing);
        self.n += 1;
        return true;
    }

    pub fn update(self: *Pack, dt: f32, heel: rl.Vector3, bounds: f32) void {
        var i: usize = 0;
        while (i < self.n) {
            self.wolves[i].update(dt, heel, bounds);
            if (self.wolves[i].gone) {
                self.wolves[i] = self.wolves[self.n - 1];
                self.n -= 1;
                continue;
            }
            i += 1;
        }
    }

    pub fn draw(self: *const Pack) void {
        if (!self.ready) return;
        for (self.liveConst()) |*w| w.draw(&self.mesh, self.mat);
    }

    pub fn drawFirst(self: *const Pack) void {
        if (!self.ready or self.n == 0) return;
        self.wolves[0].draw(&self.mesh, self.mat);
    }

    pub fn drawFx(self: *const Pack) void {
        for (self.liveConst()) |*w| w.drawFx();
    }

};

test "ONE SPIRIT STANDS AT A TIME, and its slot comes back when it is gone" {
    var p = Pack{};
    try std.testing.expect(p.room());
    try std.testing.expect(p.call(mathx.zero3, 0));
    try std.testing.expectEqual(@as(usize, combat.SUMMON_MAX), p.n);
    try std.testing.expect(!p.room());
    try std.testing.expect(!p.call(v3(3, 0, 3), 0));
    p.wolves[0].gone = true;
    p.update(1.0 / 60.0, mathx.zero3, 100);
    try std.testing.expectEqual(@as(usize, 0), p.n);
    try std.testing.expect(p.room());
}

test "a spirit dies and stops being a collider before it stops being drawn" {
    var w = Wolf.spawn(mathx.zero3, 0);
    try std.testing.expect(foe.corporeal(&w));
    _ = w.takeHit(.{ .dmg = HP * 2 });
    try std.testing.expect(w.justDied);
    try std.testing.expect(!foe.corporeal(&w));
    try std.testing.expect(w.alive());
    w.update(1.0 / 60.0, mathx.zero3, 100);
    try std.testing.expect(!w.justDied);
}

test "THE EDGES A BLOW SETS DO NOT SURVIVE THE UPDATE — so they have to be read above it" {
    // `takeHit` runs with the FIELD's blows and `update` clears every one-frame edge at the top of its body, so a caller reading these two AFTER `Pack.update` reads false on every frame. Pinned here rather than in game.zig: the contract is the creature's.
    var hurt = Wolf.spawn(mathx.zero3, 0);
    hurt.vit.poise = 0.5;
    _ = hurt.takeHit(.{ .dmg = 1 });
    try std.testing.expect(hurt.yelped);
    hurt.update(1.0 / 60.0, mathx.zero3, 100);
    try std.testing.expect(!hurt.yelped);

    var slain = Wolf.spawn(mathx.zero3, 0);
    _ = slain.takeHit(.{ .dmg = HP * 2 });
    try std.testing.expect(slain.justDied);
    slain.update(1.0 / 60.0, mathx.zero3, 100);
    try std.testing.expect(!slain.justDied);
}

test "IT WALKS THE STAMPED WAY, and the gap is still measured to the real target" {
    var w = Wolf.spawn(mathx.zero3, 0);
    const heel = mathx.ground(0, 30);
    w.nav.dir = v3(1, 0, 0);
    var t: f32 = 0;
    while (t < 2.0) : (t += 1.0 / 60.0) w.update(1.0 / 60.0, heel, 100);
    try std.testing.expect(w.pos.x > 1.0);
    try std.testing.expect(@abs(w.pos.z) < w.pos.x);

    try std.testing.expectEqual(State.move, w.state);
    try std.testing.expect(w.speed > TROT_SPEED);
}

test "A SPIRIT THAT CANNOT GET HOME IS MOVED HOME" {
    var w = Wolf.spawn(mathx.ground(0, RECALL_R + 8.0), 0);
    const heel = mathx.zero3;
    var t: f32 = 0;
    while (t < LOST_DWELL) : (t += 1.0 / 60.0) {
        const at = w.pos;
        w.update(1.0 / 60.0, heel, 100);
        w.pos = at;
        try std.testing.expect(!w.lost() or t >= LOST_DWELL - 1.0 / 30.0);
    }
    w.update(1.0 / 60.0, heel, 100);
    w.pos = mathx.ground(0, RECALL_R + 8.0);
    try std.testing.expect(w.lost());

    const spot = mathx.ground(1.5, 0.5);
    w.reappear(spot, 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(spot, w.pos), 1e-5);
    try std.testing.expectEqual(State.idle, w.state);
    try std.testing.expectApproxEqAbs(@as(f32, 0), w.lostT, 1e-6);
    try std.testing.expect(!w.lost());
    // THE JAWS ARRIVED WITH IT. Left behind, the swept bite is a blade from the old spot to the new one.
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(w.jaw0, w.jaw1), 1e-5);
    try std.testing.expect(mathx.distXZ(w.jaw1, spot) < 2.0);
    w.update(1.0 / 60.0, heel, 100);
    try std.testing.expect(!w.lost());
}

test "a dead spirit is never moved — the bond does not fetch a corpse" {
    var w = Wolf.spawn(mathx.ground(0, RECALL_R + 8.0), 0);
    _ = w.takeHit(.{ .dmg = HP * 2 });
    w.lostT = LOST_DWELL * 2.0;
    try std.testing.expect(!w.lost());
}

test "HILDEBRAND'S TWO DIALS ARE THE GAIT — the anchors are the published ones and the blend is continuous" {
    // The measured figures, so a retune has to argue with the papers rather than with a comment.
    try std.testing.expectApproxEqAbs(@as(f32, 0.65), WALK.duty, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.84), WALK.lag, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.50), TROT.lag, 1e-6);
    // A WALK ALWAYS HAS A FOOT DOWN and a gallop does not — that is what duty factor 0.5 divides.
    try std.testing.expect(WALK.duty > 0.5);
    try std.testing.expect(GALLOP.duty < 0.5);
    var prev = gaitAt(0);
    var s: f32 = 0;
    while (s < 7.0) : (s += 0.05) {
        const g = gaitAt(s);
        try std.testing.expect(@abs(g.duty - prev.duty) < 0.02);
        try std.testing.expect(@abs(g.lag - prev.lag) < 0.03);
        prev = g;
    }
}

test "A PLANTED PAW IS WORLD-FIXED — the whole of why the feet do not skate" {
    const g = TROT;
    const stride = strideFor(TROT_SPEED);
    const p0: f32 = 0.10;
    const advance: f32 = 0.06;
    const p1 = p0 + advance / stride;
    try std.testing.expect(planted(p0, g) and planted(p1, g));
    const a = pawAt(p0, g, stride, W);
    const b = pawAt(p1, g, stride, W);
    try std.testing.expectApproxEqAbs(advance, a.z - b.z, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), (a.z) - (b.z + advance), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0), a.y, 1e-6);
}

test "THE HIND FOOT LANDS IN THE FOREFOOT'S PRINT — one stride length for all four limbs" {
    // Fore and hind stride lengths in the working-dog data are equal to two decimals. Here that is structural: every limb reads the same `stride`, so tracking up cannot drift.
    const g = TROT;
    const stride = strideFor(TROT_SPEED);
    const swept = pawAt(0, g, stride, W).z - pawAt(g.duty - 1e-5, g, stride, W).z;
    try std.testing.expectApproxEqAbs(stride * g.duty, swept, 1e-3);
    try std.testing.expectApproxEqAbs(pawAt(0, g, stride, W).z, pawAt(1.0 - 1e-6, g, stride, W).z, 1e-3);

    const ph = limbPhases(0.0, g);
    try std.testing.expectApproxEqAbs(ph[0], wrap01(ph[3]), 1e-5);
    try std.testing.expectApproxEqAbs(ph[1], wrap01(ph[2]), 1e-5);
}

/// The lowest of the four paw bones' origins, in world Y — what "standing on the ground" is measured off.
fn deepestPaw(w: *const Wolf) f32 {
    var low: f32 = 1e9;
    for ([_]usize{ PAWL, PAWR, HPAWL, HPAWR }) |p| low = mathx.minF(low, foe.markOn(w.xf[p], mathx.zero3).y);
    return low;
}

test "A GATHER FOLDS THE LEGS, IT DOES NOT SINK THE ANIMAL — the paws stay where they were standing" {
    var w = Wolf.spawn(mathx.zero3, 0);
    const standing = deepestPaw(&w);
    w.state = .bite;
    var t: f32 = 0;
    var worst: f32 = standing;
    while (t <= BITE_WIND) : (t += 1.0 / 240.0) {
        w.t = t;
        w.pose();
        worst = mathx.minF(worst, deepestPaw(&w));
    }
    try std.testing.expect(worst > standing - 0.05);
}

test "CLEARING THE PACK SENDS IT HOME, IT DOES NOT UNLOAD IT" {
    var p = Pack{};
    p.ready = true;
    p.n = 1;
    p.clear();
    try std.testing.expectEqual(@as(usize, 0), p.n);
    try std.testing.expect(p.ready);
}

test "the two-link solver reaches what it is given and folds the right way round" {
    const a: f32 = 0.30;
    const b: f32 = 0.40;
    const straight = limbChain(a, b, a + b, 0, -1);
    try std.testing.expect(@abs(straight.upper) < 3.0);
    try std.testing.expect(@abs(straight.lower) < 4.0);
    const fore = limbChain(a, b, 0.55, 0.05, -1);
    const hind = limbChain(a, b, 0.55, 0.05, 1);
    try std.testing.expect(fore.lower > 0);
    try std.testing.expect(hind.lower < 0);
    try std.testing.expect(@abs(fore.lower) > 5.0);
}
