const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const art = @import("propart.zig");

const v3 = mathx.v3;
const Builder = gfx.Builder;
const BONE_OLD = art.BONE_OLD;
const BONE_LT = art.BONE_LT;
const BONE_DK = art.BONE_DK;
const MARROW = art.MARROW;
const ASH_DK = art.ASH_DK;

// The only props at architecture scale that were never BUILT, so they keep the DEAD-GROWTH laws and not the
// masonry ones: nothing dead is straight, nothing ends in a point, and a curved shaft draws its curl ONCE and
// applies it every segment (`propwood.deadLimbInto`'s rule).

pub const RibKind = struct {
    /// Arc LENGTH along the shaft, not height — the height falls out of the curl and is measured, never typed.
    arc: f32,
    /// Total turn from the socket to the snap, in degrees.
    curl: f32,
    /// How far off plumb it already leans where it leaves the ground.
    tilt0: f32,
    r0: f32,
    r1: f32,
    segs: i32,
    /// The pair the shaft is weathered BETWEEN — dark and damp at the socket, bleached at the snap. Each
    /// kind carries its own, which is where the variation lives: never along one shaft.
    foot: rl.Color = BONE_DK,
    tip: rl.Color = BONE_LT,
    /// Sideways drift per segment, degrees — a rib that curves in ONE plane is a croquet hoop.
    yawPer: f32 = 0,
};

// SOLVED, NOT PICKED. `curl` is what decides the height-to-reach ratio and nothing else does: at 88 degrees
// the shaft ends horizontal and two of them make a SEMICIRCLE (span = twice the crown, which is an arch you
// walk under); under 60 it stays steep and stands alone. The measured figures are in the tests below and the
// table's `bound`/`top` come off the same solve.
pub const RIB_TALL = RibKind{ .arc = 10.4, .curl = 58.0, .tilt0 = 6.0, .r0 = 0.52, .r1 = 0.20, .segs = 11, .yawPer = 0.9, .foot = BONE_DK, .tip = BONE_LT };
pub const RIB_STOUT = RibKind{ .arc = 7.6, .curl = 88.0, .tilt0 = 2.0, .r0 = 0.60, .r1 = 0.26, .segs = 10, .yawPer = -1.1, .foot = BONE_DK, .tip = BONE_OLD };
pub const RIB_SPLIT = RibKind{ .arc = 7.2, .curl = 42.0, .tilt0 = 4.0, .r0 = 0.44, .r1 = 0.17, .segs = 9, .yawPer = 2.1, .foot = BONE_OLD, .tip = MARROW };

pub const RIB_MAX_SEGS = 16;

pub const RibPath = struct {
    p: [RIB_MAX_SEGS + 1]rl.Vector3,
    n: usize,

    pub fn tip(self: RibPath) rl.Vector3 {
        return self.p[self.n];
    }
    pub fn height(self: RibPath) f32 {
        var hi: f32 = 0;
        for (self.p[0 .. self.n + 1]) |q| hi = @max(hi, q.y);
        return hi;
    }
    /// The furthest any joint sits from the socket, in 3-D — what a bounding sphere has to hold.
    pub fn reach(self: RibPath) f32 {
        var far: f32 = 0;
        for (self.p[0 .. self.n + 1]) |q| far = @max(far, mathx.lenV(q));
        return far;
    }
};

/// THE SHAFT'S LINE, SOLVED ONCE — the mesh draws it and the table's `bound`/`top` are measured off it, so a
/// re-tuned curl cannot leave a rib poking out of its own bounding sphere.
pub fn ribPath(k: RibKind) RibPath {
    // The table's `bound`/`top` are four of these solved at COMPTIME, and a shaft is a dozen trig steps.
    @setEvalBranchQuota(40000);
    // CLAMPED AT BOTH ENDS. `segs` is an i32 on a public spec: at 0 the two divisions below are a divide by
    // zero, and below that the cast itself traps.
    const segs: usize = @intCast(mathx.clampI(k.segs, 1, RIB_MAX_SEGS));
    const step = k.arc / @as(f32, @floatFromInt(segs));
    const dA = mathx.radians(k.curl) / @as(f32, @floatFromInt(segs));
    const dY = mathx.radians(k.yawPer);
    var out = RibPath{ .p = undefined, .n = segs };
    var a = mathx.radians(k.tilt0);
    var yaw: f32 = 0;
    out.p[0] = mathx.zero3;
    for (1..segs + 1) |i| {
        const s = mathx.sinf(a);
        const dir = v3(s * mathx.cosf(yaw), mathx.cosf(a), s * mathx.sinf(yaw));
        out.p[i] = mathx.addV(out.p[i - 1], mathx.scaleV(dir, step));
        a += dA;
        yaw += dY;
    }
    return out;
}

fn ribR(k: RibKind, t: f32) f32 {
    // Thickest a THIRD of the way up rather than at the socket: a rib is a blade, and one that only tapers
    // reads as a horn.
    const swell = 1.0 + 0.22 * mathx.sinf(mathx.clampF(t, 0, 1) * std.math.pi);
    return mathx.lerpF(k.r0, k.r1, mathx.clampF(t, 0, 1)) * swell;
}

/// Spin a local point about Y and drop it at `base`. Shared by the rib and the skull because BOTH are
/// authored along one axis and then faced wherever the map (or the swatch) wants them.
fn put(base: rl.Vector3, cc: f32, ss: f32, q: rl.Vector3) rl.Vector3 {
    return v3(base.x + q.x * cc - q.z * ss, base.y + q.y, base.z + q.x * ss + q.z * cc);
}

pub fn ribInto(b: *Builder, rng: *mathx.Rng, k: RibKind, at: rl.Vector3, yaw: f32) void {
    const path = ribPath(k);
    const c = mathx.cosf(yaw);
    const sn = mathx.sinf(yaw);
    b.setMat(.stone);
    for (0..path.n) |i| {
        const t0 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(path.n));
        const t1 = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(path.n));
        const a0 = put(at, c, sn, path.p[i]);
        const a1 = put(at, c, sn, path.p[i + 1]);
        b.addCapsule(a0, a1, ribR(k, t0), ribR(k, t1), 9, art.weathered(k.foot, k.tip, t0));
    }
    // THE SNAP, and it is BLUNT: a dome of marrow across the cut, never a taper to nothing.
    const tipA = put(at, c, sn, path.p[path.n - 1]);
    const tipB = put(at, c, sn, path.p[path.n]);
    const away = mathx.normV(mathx.subV(tipB, tipA));
    b.addDome(tipB, away, ribR(k, 1.0) * 0.96, 7, MARROW);

    // The socket it stands out of — a knuckle half in the ground, with the spoil it pushed up round it.
    const head = put(at, c, sn, v3(0, 0.10, 0));
    b.addBlob(head, v3(k.r0 * 1.85, k.r0 * 1.20, k.r0 * 1.70), 4, 8, BONE_DK);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const a = rng.angle();
        const d = k.r0 * rng.range(1.6, 2.5);
        const r = k.r0 * rng.range(0.22, 0.44);
        b.addBlob(v3(at.x + mathx.cosf(a) * d, r * 0.5, at.z + mathx.sinf(a) * d), v3(r, r * 0.45, r * 1.2), 3, 6, ASH_DK);
    }

    // RELIEF IS SUBTLE: growth ridges at a few per cent of the shaft's own radius, sunk most of the way in.
    var j: usize = 1;
    while (j < path.n) : (j += 2) {
        const t = @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(path.n));
        const r = ribR(k, t);
        const on = put(at, c, sn, path.p[j]);
        const side = mathx.normV(mathx.crossV(mathx.subV(path.p[j + 1], path.p[j - 1]), v3(0, 1, 0)));
        const off = mathx.scaleV(v3(side.x * c - side.z * sn, 0, side.x * sn + side.z * c), r * 0.82);
        b.addBlob(mathx.addV(on, off), v3(r * 0.20, r * 0.62, r * 0.20), 3, 5, art.weathered(k.foot, k.tip, t + 0.12));
    }
}

fn ribModel(shader: rl.Shader, seed: u64, k: RibKind) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    ribInto(&b, &rng, k, mathx.zero3, 0);
    return b.toModel(shader);
}

/// **THE TABLE'S NUMBERS COME OFF THE SOLVE, NOT OFF A RULER.** `props.INFO` had them typed beside a
/// comment claiming they were measured — which was true when they were written and false the moment a curl
/// moved. The arch was the one that proved it: its keystone stands above the crown, so its `top` was short
/// by 0.29 m and the shadow pass could drop it while you were standing under it.
pub fn ribTop(k: RibKind) f32 {
    return ribPath(k).height() + k.r1;
}
pub fn ribBound(k: RibKind) f32 {
    return ribPath(k).reach() + k.r0 * 2.0;
}
pub fn archTop() f32 {
    // The keystone is two blobs, the upper one at `r1*0.9` with a radius of `r1*0.8`.
    return ribPath(RIB_STOUT).tip().y + RIB_STOUT.r1 * 1.7;
}
pub fn archBound() f32 {
    const path = ribPath(RIB_STOUT);
    const half = mathx.lenXZ(path.tip());
    var far: f32 = 0;
    for (path.p[0 .. path.n + 1]) |q| {
        // Both halves, the far one mirrored through the origin — the same joint either side.
        far = @max(far, mathx.lenV(v3(q.x - half, q.y, q.z)));
        far = @max(far, mathx.lenV(v3(half - q.x, q.y, -q.z)));
    }
    return far + RIB_STOUT.r0 * 2.0;
}

pub fn rib1(shader: rl.Shader) rl.Model {
    return ribModel(shader, 0xB0E1, RIB_TALL);
}
pub fn rib2(shader: rl.Shader) rl.Model {
    return ribModel(shader, 0xB0E2, RIB_STOUT);
}
pub fn rib3(shader: rl.Shader) rl.Model {
    return ribModel(shader, 0xB0E3, RIB_SPLIT);
}

/// **THE PAIR THAT STILL MEET** — the only gate in the world nobody built. Both halves are the same shaft
/// solved twice and faced at each other, so the span is the path's own reach and not a number typed here.
pub fn ribArchMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xB0E4);
    const k = RIB_STOUT;
    const path = ribPath(k);
    const half = mathx.lenXZ(path.tip());
    ribInto(&b, &rng, k, v3(-half, 0, 0), 0);
    ribInto(&b, &rng, k, v3(half, 0, 0), std.math.pi);
    // The keystone: where two snapped ends were driven back together and fused.
    b.setMat(.stone);
    const y = path.tip().y;
    b.addBlob(v3(0, y, 0), v3(k.r1 * 2.3, k.r1 * 1.5, k.r1 * 1.9), 4, 8, MARROW);
    b.addBlob(v3(0, y + k.r1 * 0.9, 0), v3(k.r1 * 1.1, k.r1 * 0.8, k.r1 * 1.0), 3, 6, BONE_DK);
    return b.toModel(shader);
}

pub const ARCH_HALF: f32 = blk: {
    @setEvalBranchQuota(20000);
    break :blk mathx.lenXZ(ribPath(RIB_STOUT).tip());
};


/// Half sunk and canted. Sockets are RELIEF INWARD — sunk blobs in shadow, not holes: a hole in a closed hull
/// is a hole you can see the inside of. **THE SWATCH IS PART OF THE TEST** — `runPropShots` frames every kind
/// from yaw 35, looking up +Z, so a head authored muzzle-on-+X shows the harness the back of its own skull.
const SKULL_YAW: f32 = 2.53;

pub fn skullMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xB0E5);
    const c = mathx.cosf(SKULL_YAW);
    const sn = mathx.sinf(SKULL_YAW);
    const o = mathx.zero3;
    b.setMat(.stone);

    // **WHAT MAKES A SKULL A SKULL IS THE HOLES AND THE ARCHES, NOT THE DOME** — one smooth cranium came back
    // an igloo. The mass is dark, the muzzle stands clear of the braincase, the cheek arches carry daylight
    // under them, and the sockets are RIDGE PLUS SHADOW: a depression in a closed hull is invisible outside.

    // The braincase, canted and half into the ground. Darkest thing on the prop: it is the biggest face.
    b.addBlob(put(o, c, sn, v3(-0.70, 1.06, 0)), v3(1.38, 1.00, 1.24), 6, 11, BONE_DK);
    b.addBlob(put(o, c, sn, v3(-1.05, 1.34, 0)), v3(0.96, 0.72, 0.92), 5, 9, BONE_OLD);
    // The crest down the midline — one ridge, sunk most of the way in.
    b.addBlob(put(o, c, sn, v3(-0.75, 1.94, 0)), v3(0.86, 0.16, 0.14), 3, 6, BONE_LT);

    // THE NECK. Narrower than both the things either side of it, which is the whole reason the muzzle reads
    // as a separate mass rather than as more dome.
    b.addCapsule(put(o, c, sn, v3(0.30, 1.10, 0)), put(o, c, sn, v3(0.92, 0.94, 0)), 0.62, 0.54, 9, BONE_DK);

    // The muzzle, DIPPING into the ground — a head that died face-down.
    b.addCapsule(put(o, c, sn, v3(0.92, 0.94, 0)), put(o, c, sn, v3(2.34, 0.50, 0)), 0.56, 0.34, 9, BONE_OLD);
    b.addDome(put(o, c, sn, v3(2.34, 0.50, 0)), put(mathx.zero3, c, sn, v3(1, -0.25, 0)), 0.32, 8, BONE_LT);
    b.addBlob(put(o, c, sn, v3(1.72, 0.86, 0)), v3(0.30, 0.22, 0.16), 3, 6, BONE_DK); // the nasal opening

    for ([_]f32{ -1.0, 1.0 }) |sd| {
        // THE CHEEK ARCH, and it is the one piece with real daylight under it: it leaves the braincase, bows
        // OUT past the widest part of the skull and lands on the muzzle. That gap is worth more to the
        // silhouette than any amount of surface detail.
        b.addCapsule(put(o, c, sn, v3(-0.35, 1.14, sd * 1.02)), put(o, c, sn, v3(0.62, 0.96, sd * 1.34)), 0.19, 0.15, 7, BONE_OLD);
        b.addCapsule(put(o, c, sn, v3(0.62, 0.96, sd * 1.34)), put(o, c, sn, v3(1.24, 0.80, sd * 0.66)), 0.15, 0.13, 7, BONE_LT);

        // THE SOCKET: a proud brow above it and a dark disc standing a hair off the surface below. Sunk
        // INTO the hull it was invisible — a closed mesh has no inside to see.
        b.addBlob(put(o, c, sn, v3(0.30, 1.62, sd * 0.72)), v3(0.46, 0.15, 0.30), 3, 7, BONE_LT);
        b.addBlob(put(o, c, sn, v3(0.34, 1.26, sd * 0.80)), v3(0.40, 0.34, 0.30), 4, 8, BONE_DK);
        b.addBlob(put(o, c, sn, v3(0.42, 1.22, sd * 0.86)), v3(0.26, 0.23, 0.20), 3, 6, ASH_DK);
    }

    // Teeth along the muzzle's underside — WORN BLUNT, and gapped. A full set is a dental chart.
    var i: i32 = 0;
    while (i < 8) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / 7.0;
        const x = mathx.lerpF(1.05, 2.28, t);
        const y = mathx.lerpF(0.52, 0.24, t);
        const r = rng.range(0.075, 0.135) * (1.0 - 0.30 * t);
        for ([_]f32{ -1.0, 1.0 }) |sd| {
            if (rng.float() < 0.24) continue;
            b.addBlob(v3(x, y, sd * (0.36 - 0.13 * t)), v3(r, r * rng.range(1.0, 1.5), r), 3, 5, MARROW);
        }
    }

    // THE JAW CAME OFF. Nothing dead stays articulated, so it lies to one side and at its own angle.
    b.addCapsule(put(o, c, sn, v3(0.10, 0.20, -1.55)), put(o, c, sn, v3(1.95, 0.15, -0.95)), 0.23, 0.15, 7, BONE_OLD);
    b.addCapsule(put(o, c, sn, v3(1.95, 0.15, -0.95)), put(o, c, sn, v3(2.30, 0.14, -0.62)), 0.15, 0.11, 6, BONE_LT);
    b.addBlob(put(o, c, sn, v3(0.05, 0.30, -1.62)), v3(0.22, 0.26, 0.18), 3, 6, BONE_DK);
    var t: i32 = 0;
    while (t < 5) : (t += 1) {
        const u = @as(f32, @floatFromInt(t)) / 4.0;
        b.addBlob(v3(mathx.lerpF(0.5, 2.0, u), 0.31, mathx.lerpF(-1.42, -0.86, u)), v3(0.075, 0.11, 0.075), 2, 5, MARROW);
    }

    // A crack across the crown, and the drift banked up the windward side of it.
    art.crackInto(&b, put(o, c, sn, v3(-1.55, 1.70, -0.60)), put(mathx.zero3, c, sn, v3(0.75, -0.15, 1.0)), put(mathx.zero3, c, sn, v3(1, 0, 0)), 1.9, 0.09, 0.15);
    var sct: i32 = 0;
    while (sct < 9) : (sct += 1) {
        const a = rng.range(1.2, 3.1);
        const d = rng.range(1.2, 2.1);
        const r = rng.range(0.18, 0.44);
        b.addBlob(v3(-0.70 + mathx.cosf(a) * d, r * 0.36, mathx.sinf(a) * d), v3(r * 1.6, r * 0.34, r * 1.2), 3, 7, ASH_DK);
    }
    return b.toModel(shader);
}


/// One knuckle of the spine, boulder-sized: a drum, a blade of neural spine over it and two processes out
/// the sides. It is the piece that says the ribs had something to hang off.
pub fn vertebraMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xB0E6);
    b.setMat(.stone);
    const lean = mathx.radians(14.0);
    const up = v3(mathx.sinf(lean), mathx.cosf(lean), 0);

    b.addCylinder(v3(0, 0.06, 0), mathx.scaleV(up, 1.05), 0.78, 0.72, 9, BONE_OLD);
    b.addDome(mathx.scaleV(up, 1.05), up, 0.72, 9, BONE_LT);
    b.addBlob(v3(0, 0.16, 0), v3(0.90, 0.22, 0.86), 3, 9, BONE_DK);

    // The spine off the top — a BLADE, so it is a flattened capsule and not a spike, and it snaps blunt.
    const base = mathx.scaleV(up, 0.98);
    const tipv = v3(base.x - 0.30, base.y + 1.28, base.z);
    b.addCapsule(base, tipv, 0.34, 0.20, 5, BONE_OLD);
    b.addDome(tipv, mathx.normV(mathx.subV(tipv, base)), 0.19, 6, MARROW);

    for ([_]f32{ -1.0, 1.0 }) |sd| {
        const a = mathx.scaleV(up, 0.68);
        const c = v3(a.x - 0.12, a.y, a.z + sd * 1.16);
        b.addCapsule(v3(a.x, a.y, a.z + sd * 0.35), c, 0.26, 0.15, 6, BONE_LT);
        b.addDome(c, v3(0, 0, sd), 0.14, 6, MARROW);
    }
    art.chipsInto(&b, &rng, 0, 0, 1.5, 0.10, 0.24, 5);
    var g: i32 = 0;
    while (g < 4) : (g += 1) {
        const a = rng.angle();
        const r = rng.range(0.14, 0.30);
        b.addBlob(v3(mathx.cosf(a) * rng.range(0.9, 1.4), r * 0.4, mathx.sinf(a) * rng.range(0.9, 1.4)), v3(r * 1.4, r * 0.34, r * 1.1), 3, 6, ASH_DK);
    }
    return b.toModel(shader);
}

test "a rib is solved once and the table's numbers are measured off that solve" {
    inline for (.{ RIB_TALL, RIB_STOUT, RIB_SPLIT }) |k| {
        const path = ribPath(k);
        try std.testing.expectEqual(@as(usize, @intCast(k.segs)), path.n);
        // It LEANS OVER: a rib whose tip is still over its own socket is a post.
        try std.testing.expect(mathx.lenXZ(path.tip()) > path.height() * 0.30);
        // …and it never turns past horizontal and starts coming back down.
        var prev: f32 = -1;
        for (path.p[0 .. path.n + 1]) |q| {
            try std.testing.expect(q.y >= prev);
            prev = q.y;
        }
        try std.testing.expect(path.height() > 3.0);
        try std.testing.expect(path.reach() >= path.height());
    }
}

test "THE ARCH IS ITS OWN SHAFT TWICE, so the two halves cannot part company" {
    const path = ribPath(RIB_STOUT);
    try std.testing.expectApproxEqAbs(mathx.lenXZ(path.tip()), ARCH_HALF, 1e-4);
    // The two snaps meet within a rib's own thickness of each other, which is what the keystone covers.
    try std.testing.expect(ARCH_HALF > RIB_STOUT.r1 * 2.0);
    std.debug.print(
        "\n  rib arch: span {d:.2} m, crown {d:.2} m, legs {d:.2} m apart\n",
        .{ ARCH_HALF * 2.0, path.tip().y, ARCH_HALF * 2.0 },
    );
}

test "the three ribs are three DIFFERENT ribs, not one at three scales" {
    const a = ribPath(RIB_TALL);
    const b = ribPath(RIB_STOUT);
    const c = ribPath(RIB_SPLIT);
    std.debug.print(
        "  ribs: tall {d:.2} m high / {d:.2} out, stout {d:.2} / {d:.2}, split {d:.2} / {d:.2}\n",
        .{ a.height(), mathx.lenXZ(a.tip()), b.height(), mathx.lenXZ(b.tip()), c.height(), mathx.lenXZ(c.tip()) },
    );
    // WABI-SABI BETWEEN THE INSTANCES: no two share a height inside a metre, or the field reads as a pattern.
    try std.testing.expect(@abs(a.height() - b.height()) > 1.0);
    try std.testing.expect(@abs(b.height() - c.height()) > 1.0);
    try std.testing.expect(@abs(a.height() - c.height()) > 1.0);
}
