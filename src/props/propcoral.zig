const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const art = @import("propart.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;
const CAP_FLESH = art.CAP_FLESH;
const CAP_FLESH_DK = art.CAP_FLESH_DK;
const CAP_GLOW = art.CAP_GLOW;
const SPORE_GLOW = art.SPORE_GLOW;
const STIPE_DK = art.STIPE_DK;
const PUNK_DK = art.PUNK_DK;


// **NEAR-BLACK, LIKE EVERYTHING ELSE BIG AND SMOOTH IN THIS GAME** — screen goes as albedo^(1/2.2), so a mid-grey mass comes out chalk: the spire at 150,96,92 photographed as a pink concrete slab eight metres high. These sit with `CAP_FLESH_DK` (29,23,28) and `FLESH_PINK` (74,44,54).
const TUBE = rgba(34, 20, 22, 255);
const TUBE_LT = rgba(58, 35, 34, 255);
const TUBE_MOUTH = rgba(10, 6, 8, 255);
const FAN = rgba(40, 23, 26, 255);
const FAN_LT = rgba(66, 40, 40, 255);
const SAC = rgba(70, 43, 42, 255);


pub const TUBE_H: f32 = 2.9;
pub const TUBE_R: f32 = 1.30;

fn swell(t: f32) f32 {
    return 0.80 + 0.34 * mathx.sinf(std.math.pi * mathx.clampF(t, 0, 1) * 0.86);
}

fn tubeInto(b: *Builder, rng: *mathx.Rng, cx: f32, cz: f32, h: f32, r: f32, lean: f32) void {
    const dir = rng.angle();
    const ox = mathx.cosf(dir) * mathx.sinf(lean) * h;
    const oz = mathx.sinf(dir) * mathx.sinf(lean) * h;
    const SEGS = 7;
    var i: i32 = 0;
    while (i < SEGS) : (i += 1) {
        const t0 = @as(f32, @floatFromInt(i)) / SEGS;
        const t1 = @as(f32, @floatFromInt(i + 1)) / SEGS;
        b.addCylinder(
            v3(cx + ox * t0, h * t0, cz + oz * t0),
            v3(cx + ox * t1, h * t1, cz + oz * t1),
            r * swell(t0),
            r * swell(t1),
            11,
            art.weathered(TUBE, TUBE_LT, t0),
        );
    }
    const rm = r * swell(1.0);
    b.addCylinder(v3(cx + ox, h - rm * 2.4, cz + oz), v3(cx + ox, h + 0.02, cz + oz), rm * 0.52, rm * 0.84, 11, TUBE_MOUTH);
    var p: i32 = 0;
    while (p < 9) : (p += 1) {
        const t = rng.range(0.18, 0.88);
        const a = rng.angle();
        const rr = r * swell(t) * 0.95;
        const s = rng.range(0.05, 0.11);
        b.addBlob(v3(cx + ox * t + mathx.cosf(a) * rr, h * t, cz + oz * t + mathx.sinf(a) * rr), v3(s, s, s), 2, 5, TUBE_MOUTH);
    }
}

pub fn tubeCoralMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xC02A11);
    b.setMat(.plant);
    const HS = [_]f32{ 1.00, 0.62, 0.83, 0.44, 0.72, 0.53 };
    for (HS, 0..) |k, i| {
        const a = @as(f32, @floatFromInt(i)) * 1.31 + rng.signed() * 0.22;
        const d = if (i == 0) 0.0 else rng.range(0.36, 0.78);
        tubeInto(&b, &rng, mathx.cosf(a) * d, mathx.sinf(a) * d, TUBE_H * k, 0.20 + 0.13 * k, rng.range(0.02, 0.13));
    }
    b.addBlob(v3(0, 0.06, 0), v3(TUBE_R * 0.86, 0.11, TUBE_R * 0.80), 3, 9, STIPE_DK);
    return b.toModel(shader);
}

pub const SPIRE_H: f32 = 8.6;
pub const SPIRE_R: f32 = 2.30;
pub const SPIRE_LIGHT_Y: f32 = SPIRE_H - 0.9;

pub fn tubeSpireMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xC02A17);
    b.setMat(.plant);
    tubeInto(&b, &rng, 0, 0, SPIRE_H, 1.22, 0.05);
    tubeInto(&b, &rng, 1.32, 0.48, SPIRE_H * 0.54, 0.62, 0.10);
    tubeInto(&b, &rng, -0.96, -1.14, SPIRE_H * 0.33, 0.47, 0.12);
    var i: i32 = 0;
    while (i < 26) : (i += 1) {
        const t = rng.range(0.22, 0.94);
        const a = rng.angle();
        // RECESSED, not stuck on: at 0.90 of the wall the blob sits INSIDE it and reads as an opening.
        const rr = 1.22 * swell(t) * 0.80;
        b.addBlob(
            v3(mathx.cosf(a) * rr, SPIRE_H * t, mathx.sinf(a) * rr),
            v3(rng.range(0.13, 0.23), rng.range(0.17, 0.30), rng.range(0.13, 0.23)),
            2,
            5,
            if (rng.float() < 0.55) art.BLOOM_GLOW else TUBE_MOUTH,
        );
    }
    b.addBlob(v3(0, SPIRE_H - 0.60, 0), v3(0.56, 0.34, 0.56), 3, 9, art.BLOOM_GLOW);
    b.addBlob(v3(0, SPIRE_H - 0.80, 0), v3(0.34, 0.26, 0.34), 3, 8, art.BLOOM_CORE);
    b.addBlob(v3(0, 0.09, 0), v3(SPIRE_R * 0.82, 0.16, SPIRE_R * 0.78), 3, 9, STIPE_DK);
    return b.toModel(shader);
}


pub const FAN_H: f32 = 3.2;
pub const FAN_W: f32 = 3.6;

pub fn fanCoralMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xC02A12);
    b.setMat(.plant);
    const RIBS = 9;
    const yaw = 0.28;
    const nx = mathx.cosf(yaw);
    const nz = mathx.sinf(yaw);
    var mids: [RIBS]rl.Vector3 = undefined;
    var tops: [RIBS]rl.Vector3 = undefined;
    var i: usize = 0;
    while (i < RIBS) : (i += 1) {
        const u = @as(f32, @floatFromInt(i)) / (RIBS - 1) * 2.0 - 1.0;
        const h = FAN_H * @sqrt(mathx.maxF(1.0 - u * u * 0.86, 0.05)) * rng.range(0.93, 1.07);
        const spread = FAN_W * 0.5 * u;
        const SEG = 6;
        var prev = v3(0, 0.10, 0);
        var s: i32 = 1;
        while (s <= SEG) : (s += 1) {
            const t = @as(f32, @floatFromInt(s)) / SEG;
            const w = spread * t * t;
            const p = v3(nx * w + rng.signed() * 0.03, 0.10 + h * t, nz * w + rng.signed() * 0.03);
            const r = mathx.lerpF(0.075, 0.026, t);
            b.addCylinder(prev, p, r * 1.12, r, 6, art.weathered(FAN, FAN_LT, t));
            if (s == SEG / 2) mids[i] = p;
            prev = p;
        }
        tops[i] = prev;
        b.addBlob(prev, v3(0.055, 0.070, 0.055), 2, 6, FAN_LT);
    }
    i = 1;
    while (i < RIBS) : (i += 1) {
        b.addCylinder(mids[i - 1], mids[i], 0.030, 0.030, 5, FAN);
        if (i % 2 == 0) b.addCylinder(tops[i - 1], tops[i], 0.024, 0.024, 5, FAN);
    }
    b.addBlob(v3(0, 0.10, 0), v3(0.34, 0.16, 0.30), 3, 8, STIPE_DK);
    return b.toModel(shader);
}

pub const ANTLER_H: f32 = 2.6;

fn branchInto(b: *Builder, rng: *mathx.Rng, from: rl.Vector3, dir: rl.Vector3, r: f32, len: f32, depth: i32) void {
    if (depth <= 0 or r < 0.022) {
        b.addBlob(from, v3(r * 1.9, r * 2.3, r * 1.9), 2, 6, FAN_LT);
        return;
    }
    const d = mathx.normV(dir);
    const to = v3(from.x + d.x * len, from.y + d.y * len, from.z + d.z * len);
    const t = 1.0 - @as(f32, @floatFromInt(depth)) / 4.0;
    b.addCylinder(from, to, r, r * 0.74, 7, art.weathered(FAN, FAN_LT, t));
    const forks: i32 = if (depth >= 3) 3 else 2;
    var i: i32 = 0;
    while (i < forks) : (i += 1) {
        const a = rng.angle();
        const tilt = rng.range(0.34, 0.72);
        branchInto(b, rng, to, v3(d.x + mathx.cosf(a) * tilt, d.y + rng.range(0.10, 0.42), d.z + mathx.sinf(a) * tilt), r * rng.range(0.58, 0.74), len * rng.range(0.62, 0.82), depth - 1);
    }
}

pub fn antlerCoralMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xC02A13);
    b.setMat(.plant);
    branchInto(&b, &rng, v3(0, 0.08, 0), v3(0, 1, 0), 0.20, ANTLER_H * 0.34, 4);
    b.addBlob(v3(0, 0.07, 0), v3(0.40, 0.13, 0.36), 3, 9, STIPE_DK);
    return b.toModel(shader);
}


pub const FLOAT_Y: f32 = 4.10;
pub const FLOAT_R: f32 = 0.92;
pub const FLOAT_LIGHT_Y: f32 = FLOAT_Y - 0.20;

fn sacInto(b: *Builder, rng: *mathx.Rng, cx: f32, cz: f32, y: f32, r: f32, glow: bool) void {
    const ax = cx + rng.signed() * 0.10;
    const az = cz + rng.signed() * 0.10;
    b.addCylinder(v3(ax, 0.05, az), v3(cx, y - r * 0.90, cz), 0.030, 0.020, 5, STIPE_DK);
    b.addBlob(v3(ax, 0.09, az), v3(0.17, 0.09, 0.16), 3, 8, STIPE_DK);
    b.addBlob(v3(cx, y, cz), v3(r, r * 1.16, r * 0.94), 4, 11, SAC);
    b.addBlob(v3(cx, y - r * 0.78, cz), v3(r * 0.52, r * 0.44, r * 0.50), 3, 9, CAP_FLESH_DK);
    if (glow) b.addBlob(v3(cx, y + r * 0.10, cz), v3(r * 0.42, r * 0.50, r * 0.42), 3, 8, CAP_GLOW);
    var i: i32 = 0;
    while (i < 6) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.12, r * 0.72);
        const len = rng.range(0.45, 1.25);
        const px = cx + mathx.cosf(a) * d;
        const pz = cz + mathx.sinf(a) * d;
        const y0 = y - r * 0.85;
        b.addCylinder(v3(px, y0, pz), v3(px, y0 - len, pz), 0.020, 0.011, 4, CAP_FLESH_DK);
        b.addBlob(v3(px, y0 - len, pz), v3(0.035, 0.045, 0.035), 2, 5, if (glow) SPORE_GLOW else CAP_FLESH);
    }
}

pub fn floatSacMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xC02A14);
    b.setMat(.plant);
    sacInto(&b, &rng, 0, 0, FLOAT_Y, FLOAT_R, true);
    return b.toModel(shader);
}

pub const SHOAL_TOP: f32 = 5.40;

pub fn floatShoalMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xC02A15);
    b.setMat(.plant);
    const YS = [_]f32{ 1.00, 0.58, 0.79, 0.44, 0.67 };
    for (YS, 0..) |k, i| {
        const a = @as(f32, @floatFromInt(i)) * 1.27 + rng.signed() * 0.25;
        const d = if (i == 0) 0.0 else rng.range(0.55, 1.45);
        sacInto(&b, &rng, mathx.cosf(a) * d, mathx.sinf(a) * d, SHOAL_TOP * k, 0.26 + 0.30 * k, k > 0.6);
    }
    return b.toModel(shader);
}


pub const HANG_SPAN: f32 = 5.2;
pub const HANG_H: f32 = 4.6;
pub const HANG_LIGHT_Y: f32 = 2.40;

fn sparY(x: f32) f32 {
    const t = mathx.clampF((x + HANG_SPAN * 0.5) / HANG_SPAN, 0, 1);
    return 0.06 + HANG_H * mathx.sinf(std.math.pi * t * 0.82) / mathx.sinf(std.math.pi * 0.82);
}

pub fn hangCurtainMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xC02A16);
    b.setMat(.plant);
    const half = HANG_SPAN * 0.5;
    const SEG = 9;
    var prev = v3(-half, 0.06, 0);
    var s: i32 = 1;
    while (s <= SEG) : (s += 1) {
        const t = @as(f32, @floatFromInt(s)) / SEG;
        const x = mathx.lerpF(-half, half * 0.86, t);
        const p = v3(x, sparY(x), rng.signed() * 0.12);
        b.addCylinder(prev, p, mathx.lerpF(0.20, 0.11, t), mathx.lerpF(0.19, 0.10, t), 8, art.weathered(PUNK_DK, TUBE_LT, t));
        prev = p;
    }
    b.addBlob(prev, v3(0.16, 0.20, 0.16), 3, 7, TUBE_LT);
    b.addBlob(v3(-half, 0.12, 0), v3(0.36, 0.18, 0.33), 3, 9, STIPE_DK);
    var i: i32 = 0;
    while (i < 22) : (i += 1) {
        const u = @as(f32, @floatFromInt(i)) / 21.0;
        const x = mathx.lerpF(-half * 0.80, half * 0.80, u) + rng.signed() * 0.10;
        const top = sparY(x) - 0.08;
        const len = mathx.maxF(top - 0.55, 0.20) * rng.range(0.42, 0.92);
        const z = rng.signed() * 0.22;
        b.addCylinder(v3(x, top, z), v3(x, top - len, z), 0.026, 0.014, 5, art.weathered(CAP_FLESH_DK, PUNK_DK, 0.4));
        const glow = rng.float() < 0.42;
        b.addBlob(v3(x, top - len, z), v3(0.055, 0.085, 0.055), 2, 6, if (glow) CAP_GLOW else CAP_FLESH);
        if (glow) b.addBlob(v3(x, top - len - 0.05, z), v3(0.030, 0.038, 0.030), 2, 5, SPORE_GLOW);
    }
    return b.toModel(shader);
}

test "A REEF IS HOLES AND HEIGHTS — the tubes are open, the fan is a lattice, the floaters are off the floor" {
    std.debug.print("\n  reef: tubes {d:.1} m, spire {d:.1} m, fan {d:.1} m, antler {d:.1} m, floater {d:.1} m, shoal {d:.1} m, curtain {d:.1} m\n", .{ TUBE_H, SPIRE_H, FAN_H, ANTLER_H, FLOAT_Y, SHOAL_TOP, HANG_H });
    try std.testing.expect(SPIRE_H > TUBE_H * 2.5);
    try std.testing.expect(SHOAL_TOP > FLOAT_Y);
    try std.testing.expect(FLOAT_Y > FAN_H);
    try std.testing.expect(FLOAT_Y - FLOAT_R > 2.4);
    try std.testing.expect(HANG_LIGHT_Y < HANG_H * 0.6);
    const lo = sparY(-HANG_SPAN * 0.5);
    const mid = sparY(0);
    const hi = sparY(HANG_SPAN * 0.5);
    std.debug.print("  ...spar {d:.2} m at the foot, {d:.2} m at the crown, {d:.2} m at the tip\n", .{ lo, mid, hi });
    try std.testing.expect(mid > lo and mid > hi);
    const s0 = swell(0.0);
    const sm = swell(0.36);
    const s1 = swell(1.0);
    std.debug.print("  ...tube radius x{d:.2} at the foot, x{d:.2} at the belly, x{d:.2} at the mouth\n", .{ s0, sm, s1 });
    try std.testing.expect(sm > s0 and sm > s1);
    try std.testing.expect(s1 > 0.7);
}



pub const BRAIN_R: f32 = 0.98;
pub const BRAIN_H: f32 = 0.66;

pub fn brainKnotMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xB2A17);
    b.setMat(.plant);
    const dome = struct {
        fn y(nx: f32, nz: f32) f32 {
            const dd = @sqrt(nx * nx + nz * nz) / BRAIN_R;
            return BRAIN_H * 0.40 + BRAIN_H * 0.62 * @sqrt(mathx.maxF(1.0 - dd * dd, 0.02));
        }
    };
    b.addBlob(v3(0, BRAIN_H * 0.40, 0), v3(BRAIN_R, BRAIN_H * 0.62, BRAIN_R * 0.92), 4, 13, TUBE_MOUTH);

    var a = rng.angle();
    var x: f32 = 0;
    var z: f32 = 0;
    var i: i32 = 0;
    while (i < 132) : (i += 1) {
        a += rng.range(-0.58, 0.58);
        const step = 0.098;
        var nx = x + mathx.cosf(a) * step;
        var nz = z + mathx.sinf(a) * step;
        if (@sqrt(nx * nx + nz * nz) > BRAIN_R * 0.84) {
            a += std.math.pi * rng.range(0.62, 1.38);
            nx = x + mathx.cosf(a) * step;
            nz = z + mathx.sinf(a) * step;
        }
        const r = rng.range(0.070, 0.098);
        b.addBlob(v3(nx, dome.y(nx, nz) - r * 0.34, nz), v3(r, r * 0.86, r), 3, 9, art.weathered(FAN, FAN_LT, rng.float()));
        x = nx;
        z = nz;
    }
    b.addBlob(v3(0, 0.030, 0), v3(BRAIN_R * 0.96, 0.042, BRAIN_R * 0.90), 3, 11, TUBE_MOUTH);
    return b.toModel(shader);
}

pub const CLUTCH_H: f32 = 0.78;

pub fn pipeClutchMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xC107C4);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 13) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0, 0.42) * @sqrt(rng.float());
        tubeInto(&b, &rng, mathx.cosf(a) * d, mathx.sinf(a) * d, CLUTCH_H * rng.range(0.38, 1.0), rng.range(0.055, 0.105), rng.range(0.03, 0.18));
    }
    b.addBlob(v3(0, 0.06, 0), v3(0.56, 0.09, 0.52), 3, 9, STIPE_DK);
    return b.toModel(shader);
}

pub const CCRUST_R: f32 = 1.20;

/// PLATED. Encrusting coral: overlapping shelves creeping out from one centre, each plate a little proud of the one under it. It has EDGES where the fungal crust has lobes — the whole difference between the two at a glance.
pub fn coralCrustMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xCC2057);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 15) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / 14.0;
        const a = @as(f32, @floatFromInt(i)) * 2.399 + rng.signed() * 0.30;
        const d = CCRUST_R * 0.62 * t * rng.range(0.8, 1.2);
        const w = mathx.lerpF(0.34, 0.17, t) * rng.range(0.85, 1.15);
        const y = 0.16 * (1.0 - t) + 0.02;
        const yaw = a + rng.signed() * 0.4;
        b.addBox(
            v3(mathx.cosf(a) * d, y, mathx.sinf(a) * d),
            v3(mathx.cosf(yaw) * w, rng.range(0.02, 0.09), mathx.sinf(yaw) * w),
            v3(0, rng.range(0.022, 0.042), 0),
            v3(-mathx.sinf(yaw) * w * 0.66, 0, mathx.cosf(yaw) * w * 0.66),
            art.weathered(FAN, FAN_LT, t),
        );
    }
    b.addBlob(v3(0, 0.20, 0), v3(0.26, 0.13, 0.24), 3, 8, art.weathered(FAN_LT, SAC, 0.5));
    return b.toModel(shader);
}

test "THE REEF FLOOR IS A GROOVE, A BUNDLE AND A CRUST — all three under the knee" {
    std.debug.print("\n  reef floor: brain {d:.2} m, clutch {d:.2} m, crust {d:.2} m across\n", .{ BRAIN_H, CLUTCH_H, CCRUST_R * 2 });
    try std.testing.expect(BRAIN_H < 1.0);
    try std.testing.expect(CLUTCH_H < 1.0);
    try std.testing.expect(CLUTCH_H < TUBE_H * 0.4);
    try std.testing.expect(CCRUST_R * 2 > BRAIN_R * 2 * 0.9);
}
