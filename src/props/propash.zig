const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const art = @import("propart.zig");
const wood = @import("propwood.zig");

const v3 = mathx.v3;
const Builder = gfx.Builder;
const DRIFT = art.DRIFT;
const DRIFT_LT = art.DRIFT_LT;
const DRIFT_DK = art.DRIFT_DK;
const CHAR = art.CHAR;
const CHAR_LT = art.CHAR_LT;
const CINDER_GREY = art.CINDER_GREY;
const EMBER_LIVE = art.EMBER_LIVE;


const Drift = struct {
    len: f32,
    wide: f32,
    high: f32,
    /// Where the crest sits across the section, -1 (windward toe) to 1 (lee toe). Positive: the long ramp is on the windward side and the short slip face on the lee, which is the whole silhouette.
    crest: f32 = 0.18,
    toe: f32 = -0.80,
    seed: u64 = 1,
};

/// Height of the drift's surface at (`u` across, `v` along), both -1..1 / 0..1. A PURE FUNCTION, so the mesh and its normals come off the same shape and the test below can measure the profile without a builder.
fn duneH(d: Drift, u: f32, v: f32, jitter: f32) f32 {
    const env = std.math.pow(f32, mathx.clampF(mathx.sinf(v * std.math.pi), 0, 1), 0.62) *
        (0.86 + 0.14 * mathx.sinf(v * 7.3 + jitter));
    const prof = if (u <= d.crest)
        mathx.smoothstep(d.toe, d.crest, u)
    else
        1.0 - mathx.smoothstep(d.crest, d.crest + 0.34, u) * 0.94;
    return d.high * env * mathx.clampF(prof, 0, 1);
}

const DUNE_NV: usize = 15;
const DUNE_NU: usize = 13;

fn driftInto(b: *Builder, rng: *mathx.Rng, d: Drift, cx: f32, cz: f32, yaw: f32) void {
    b.setMat(.stone);
    const c = mathx.cosf(yaw);
    const sn = mathx.sinf(yaw);
    const jit = @as(f32, @floatFromInt(d.seed % 17)) * 0.37;
    const at = struct {
        fn p(dd: Drift, ux: f32, vz: f32, j: f32, ccx: f32, ccz: f32, cc: f32, ss: f32) rl.Vector3 {
            const lx = ux * dd.wide;
            const lz = (vz - 0.5) * dd.len;
            return v3(ccx + lx * cc - lz * ss, duneH(dd, ux, vz, j), ccz + lx * ss + lz * cc);
        }
    }.p;
    const nrm = struct {
        fn n(dd: Drift, ux: f32, vz: f32, j: f32, cc: f32, ss: f32) rl.Vector3 {
            const e: f32 = 0.02;
            const dhx = (duneH(dd, ux + e, vz, j) - duneH(dd, ux - e, vz, j)) / (2.0 * e * dd.wide);
            const dhz = (duneH(dd, ux, vz + e, j) - duneH(dd, ux, vz - e, j)) / (2.0 * e * dd.len);
            const lv = v3(-dhx, 1.0, -dhz);
            return mathx.normV(v3(lv.x * cc - lv.z * ss, lv.y, lv.x * ss + lv.z * cc));
        }
    }.n;

    var iv: usize = 0;
    while (iv + 1 < DUNE_NV) : (iv += 1) {
        const v0 = @as(f32, @floatFromInt(iv)) / @as(f32, DUNE_NV - 1);
        const v1 = @as(f32, @floatFromInt(iv + 1)) / @as(f32, DUNE_NV - 1);
        var iu: usize = 0;
        while (iu + 1 < DUNE_NU) : (iu += 1) {
            const ua = d.toe + (d.crest + 0.34 - d.toe) * @as(f32, @floatFromInt(iu)) / @as(f32, DUNE_NU - 1);
            const ub = d.toe + (d.crest + 0.34 - d.toe) * @as(f32, @floatFromInt(iu + 1)) / @as(f32, DUNE_NU - 1);
            const p00 = at(d, ua, v0, jit, cx, cz, c, sn);
            const p10 = at(d, ub, v0, jit, cx, cz, c, sn);
            const p11 = at(d, ub, v1, jit, cx, cz, c, sn);
            const p01 = at(d, ua, v1, jit, cx, cz, c, sn);
            const t = mathx.clampF(0.5 * (p00.y + p11.y) / mathx.maxF(d.high, 0.01), 0, 1);
            const CREST: f32 = 0.80;
            const tone = if (t < CREST)
                art.weathered(DRIFT_DK, DRIFT, t / CREST)
            else
                art.weathered(DRIFT, DRIFT_LT, (t - CREST) / (1.0 - CREST));
            b.quadSmooth(
                p00,
                p01,
                p11,
                p10,
                nrm(d, ua, v0, jit, c, sn),
                nrm(d, ua, v1, jit, c, sn),
                nrm(d, ub, v1, jit, c, sn),
                nrm(d, ub, v0, jit, c, sn),
                tone,
            );
        }
    }
    var j: i32 = 0;
    while (j < 8) : (j += 1) {
        const uu = rng.range(d.toe * 1.25, d.toe * 0.7);
        const vv = rng.range(0.1, 0.9);
        const lx = uu * d.wide;
        const lz = (vv - 0.5) * d.len;
        const r = rng.range(0.05, 0.14);
        b.addBlob(v3(cx + lx * c - lz * sn, r * 0.6, cz + lx * sn + lz * c), v3(r, r * 0.7, r * 1.1), 3, 6, CHAR);
    }
}

// Solved through the chain, not picked (screen = 255 x (albedo x 1.72)^(1/2.2)):
//   clinker 96 -> 17    clinker face 130 -> 34    dripstone 175 -> 65    dripstone band 140 -> 40

/// FUSED ASH, not stone: it ran and set, so it is glassy and the darkest thing in the region by a long way.
const CLINKER = mathx.rgba(18, 17, 16, 255);
const CLINKER_LT = mathx.rgba(36, 33, 30, 255);
const DRIP = mathx.rgba(66, 64, 58, 255);
const DRIP_BAND = mathx.rgba(42, 39, 35, 255);

fn bankInto(b: *Builder, rng: *mathx.Rng, r: f32, high: f32) void {
    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 6) : (i += 1) {
        const fi = @as(f32, @floatFromInt(i)) / 5.0;
        const a = -1.0 + fi * 2.0;
        const d = r * rng.range(0.55, 0.92);
        const h = high * (0.40 + 0.60 * mathx.sinf(fi * std.math.pi)) * rng.range(0.85, 1.12);
        // **SUNK TO THE WAIST, NOT STOOD ON THE GRASS.** Centred at `h * 0.34` these were flat pale discs.
        b.addBlob(
            v3(-mathx.cosf(a) * d, 0, mathx.sinf(a) * d),
            v3(r * rng.range(0.34, 0.52), h, r * rng.range(0.30, 0.44)),
            4,
            11,
            if (rng.float() < 0.30) DRIFT_LT else DRIFT,
        );
    }
}

pub const CRAG_TOP: f32 = 5.20;
pub const CRAG_R: f32 = 1.55;
pub fn ashCragMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xA5C0);
    b.setMat(.stone);
    const plates = 9;
    const leanA = rng.range(0.25, 0.55);
    var y: f32 = 0;
    var cx: f32 = 0;
    var cz: f32 = 0;
    var i: i32 = 0;
    while (i < plates) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / (plates - 1);
        const th = CRAG_TOP / plates * mathx.lerpF(1.22, 0.68, t);
        const half = CRAG_R * mathx.lerpF(1.0, 0.24, t) * rng.range(0.86, 1.12);
        const yaw = rng.angle();
        const u = v3(mathx.cosf(yaw), 0, mathx.sinf(yaw));
        const w = v3(-u.z, 0, u.x);
        b.addBox(
            v3(cx, y + th * 0.5, cz),
            v3(u.x * half, rng.signed() * 0.10, u.z * half),
            v3(rng.signed() * 0.12, th * 0.5, rng.signed() * 0.12),
            v3(w.x * half * rng.range(0.62, 0.94), rng.signed() * 0.08, w.z * half * rng.range(0.62, 0.94)),
            if (rng.float() < 0.34) CLINKER_LT else CLINKER,
        );
        y += th * rng.range(0.86, 0.98);
        cx += mathx.cosf(leanA) * CRAG_TOP * 0.028 + rng.signed() * 0.06;
        cz += mathx.sinf(leanA) * CRAG_TOP * 0.028 + rng.signed() * 0.06;
    }
    var f: i32 = 0;
    while (f < 12) : (f += 1) {
        const t = rng.float();
        const a = rng.angle();
        const rr = rng.range(0.06, 0.15);
        const d = CRAG_R * mathx.lerpF(0.94, 0.22, t);
        b.addBlob(
            v3(cx * t + mathx.cosf(a) * d, CRAG_TOP * t * 0.92, cz * t + mathx.sinf(a) * d),
            v3(rr, rr * rng.range(0.5, 1.0), rr * 0.7),
            3,
            7,
            if (rng.float() < 0.4) CHAR else CLINKER_LT,
        );
    }
    bankInto(&b, &rng, CRAG_R * 1.35, 0.90);
    return b.toModel(shader);
}

pub const STAL_TOP: f32 = 2.35;
pub const STAL_R: f32 = 1.10;
pub fn stalagmiteMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xA5C1);
    b.setMat(.stone);
    const HEIGHTS = [_]f32{ 1.00, 0.42, 0.71, 0.28, 0.86, 0.36, 0.55 };
    for (HEIGHTS, 0..) |hs, i| {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / HEIGHTS.len + rng.signed() * 0.4;
        const d = STAL_R * rng.range(0.10, 0.92);
        const bx = mathx.cosf(a) * d;
        const bz = mathx.sinf(a) * d * 0.84;
        const top = STAL_TOP * hs;
        const base = 0.30 * mathx.lerpF(0.55, 1.0, hs) * rng.range(0.85, 1.15);
        const tipA = rng.angle();
        const off = top * rng.range(0.03, 0.11);
        const segs = 6;
        var y: f32 = 0;
        var wx: f32 = bx;
        var wz: f32 = bz;
        var rprev = base;
        var j: i32 = 0;
        while (j < segs) : (j += 1) {
            const t1 = @as(f32, @floatFromInt(j + 1)) / segs;
            const r1 = base * (1.0 - t1 * 0.74) * rng.range(0.80, 1.22);
            const nx = bx + mathx.cosf(tipA) * off * t1 + rng.signed() * base * 0.20;
            const nz = bz + mathx.sinf(tipA) * off * t1 + rng.signed() * base * 0.20;
            b.addCapsule(
                v3(wx, y, wz),
                v3(nx, top * t1, nz),
                rprev,
                r1,
                9,
                if (@mod(j, 2) == 0) DRIP else DRIP_BAND,
            );
            if (j + 1 < segs) {
                b.addBlob(v3(nx, top * t1, nz), v3(r1 * 1.22, r1 * 0.34, r1 * 1.16), 3, 8, if (rng.float() < 0.4) DRIP else DRIP_BAND);
            }
            y = top * t1;
            wx = nx;
            wz = nz;
            rprev = r1;
        }
        const off2 = v3(wx - bx, 0, wz - bz);
        _ = off2;
        b.addBlob(v3(wx, top, wz), v3(rprev * 1.5, rprev * 1.2, rprev * 1.45), 3, 8, DRIP);
        b.addBlob(v3(bx, base * 0.10, bz), v3(base * 1.5, base * 0.20, base * 1.35), 3, 9, DRIP_BAND);
    }
    bankInto(&b, &rng, STAL_R * 1.25, 0.34);
    return b.toModel(shader);
}

pub const MENHIR_TOP: f32 = 4.40;
pub const MENHIR_R: f32 = 0.72;
pub fn menhirMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xA5C2);
    b.setMat(.stone);
    const leanDeg = rng.range(4.0, 7.5);
    const leanA = rng.angle();
    const tipX = mathx.cosf(leanA) * MENHIR_TOP * mathx.sinf(mathx.radians(leanDeg));
    const tipZ = mathx.sinf(leanA) * MENHIR_TOP * mathx.sinf(mathx.radians(leanDeg));
    const SPANS = [3][2]f32{ .{ 0.00, 0.78 }, .{ 0.14, 0.94 }, .{ 0.34, 1.00 } };
    const WIDE = [3]f32{ 1.00, 0.82, 0.61 };
    for (SPANS, WIDE, 0..) |sp, wide, i| {
        const t0 = sp[0];
        const t1 = sp[1];
        const tm = (t0 + t1) * 0.5;
        const half = MENHIR_R * wide * rng.range(0.90, 1.06);
        const yaw = rng.signed() * 0.42;
        const u = v3(mathx.cosf(yaw), 0, mathx.sinf(yaw));
        const w = v3(-u.z, 0, u.x);
        b.addBox(
            v3(tipX * tm, MENHIR_TOP * tm, tipZ * tm),
            v3(u.x * half, rng.signed() * 0.05, u.z * half),
            v3(tipX * (t1 - t0) * 0.5, MENHIR_TOP * (t1 - t0) * 0.5, tipZ * (t1 - t0) * 0.5),
            v3(w.x * half * rng.range(0.54, 0.82), rng.signed() * 0.05, w.z * half * rng.range(0.54, 0.82)),
            art.weathered(art.STONE_DK, art.STONE_LT, @as(f32, @floatFromInt(i)) * 0.5),
        );
    }
    b.addBlob(v3(tipX, MENHIR_TOP, tipZ), v3(MENHIR_R * 0.44, MENHIR_R * 0.22, MENHIR_R * 0.36), 4, 9, art.STONE_LT);
    var f: i32 = 0;
    while (f < 14) : (f += 1) {
        const t = rng.float();
        const a = rng.angle();
        const rr = rng.range(0.035, 0.085);
        const d = MENHIR_R * mathx.lerpF(0.92, 0.44, t);
        b.addBlob(
            v3(tipX * t + mathx.cosf(a) * d, MENHIR_TOP * t, tipZ * t + mathx.sinf(a) * d),
            v3(rr, rr * rng.range(0.6, 1.4), rr * 0.7),
            3,
            7,
            if (rng.float() < 0.45) art.STONE_DK else art.STONE,
        );
    }
    var k: i32 = 0;
    while (k < 6) : (k += 1) {
        const a = rng.angle();
        const d = MENHIR_R * rng.range(0.85, 1.35);
        const rr = rng.range(0.10, 0.22);
        b.addBox(
            v3(mathx.cosf(a) * d, rr * 0.55, mathx.sinf(a) * d),
            v3(rr, rng.signed() * 0.04, 0),
            v3(0, rr * 0.55, 0),
            v3(0, rng.signed() * 0.04, rr * rng.range(0.6, 1.1)),
            if (rng.float() < 0.4) art.STONE_DK else art.STONE,
        );
    }
    bankInto(&b, &rng, MENHIR_R * 1.9, 0.55);
    return b.toModel(shader);
}

pub const CARVE_TOP: f32 = 1.35;
pub const CARVE_R: f32 = 1.45;
pub fn stoneCarveMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xA5C3);
    b.setMat(.stone);
    b.addBlob(v3(0, CARVE_TOP * 0.42, -0.10), v3(CARVE_R, CARVE_TOP * 0.50, CARVE_R * 0.72), 5, 12, art.STONE);
    b.addBlob(v3(rng.signed() * 0.20, CARVE_TOP * 0.72, -0.22), v3(CARVE_R * 0.66, CARVE_TOP * 0.30, CARVE_R * 0.50), 4, 10, art.STONE_LT);
    b.addBlob(v3(rng.signed() * 0.25, CARVE_TOP * 0.18, 0.10), v3(CARVE_R * 0.86, CARVE_TOP * 0.24, CARVE_R * 0.58), 4, 10, art.STONE_DK);
    const faceY = CARVE_TOP * 0.52;
    const tilt: f32 = 0.16;
    const groove = art.weathered(art.STONE_DK, art.ROCK_DEEP, 0.7);
    for ([_]f32{ 1.0, -1.0 }) |sz| {
        const faceZ = CARVE_R * 0.46 * sz;
        b.addBox(
            v3(0, faceY, faceZ),
            v3(CARVE_R * 0.72, 0, 0),
            v3(0, CARVE_TOP * 0.32, -tilt * CARVE_TOP * 0.32 * sz),
            v3(0, tilt * 0.10 * sz, 0.16 * sz),
            art.STONE_LT,
        );
        // **TWICE AS WIDE AS A REAL GROOVE.** At 0.022 m they vanished at ten paces — legibility beats scale.
        const gz = faceZ + CARVE_R * 0.14 * sz;
        if (sz > 0) {
            const turns: f32 = 2.4;
            const steps = 26;
            const cxs = -CARVE_R * 0.20;
            var prev = v3(cxs, faceY, gz);
            var i: i32 = 1;
            while (i <= steps) : (i += 1) {
                const u = @as(f32, @floatFromInt(i)) / steps;
                const ang = u * std.math.tau * turns;
                const rr = 0.34 * u;
                const p = v3(cxs + mathx.cosf(ang) * rr, faceY + mathx.sinf(ang) * rr, gz + tilt * mathx.sinf(ang) * rr * sz);
                b.addCapsule(prev, p, 0.048, 0.048, 5, groove);
                prev = p;
            }
        } else {
            var i: i32 = 0;
            const n = 7;
            while (i < n) : (i += 1) {
                const x = -CARVE_R * 0.52 + @as(f32, @floatFromInt(i)) * 0.082 + rng.signed() * 0.010;
                const h = 0.15 * rng.range(0.7, 1.25);
                b.addCapsule(
                    v3(x, faceY + CARVE_TOP * 0.18 - h, gz),
                    v3(x + rng.signed() * 0.014, faceY + CARVE_TOP * 0.18 + h, gz + tilt * h * sz),
                    0.042,
                    0.038,
                    5,
                    groove,
                );
            }
            const fx = CARVE_R * 0.36;
            const fy = faceY - CARVE_TOP * 0.12;
            b.addCapsule(v3(fx, fy, gz), v3(fx + 0.02, fy + 0.32, gz), 0.048, 0.044, 5, groove);
            b.addCapsule(v3(fx - 0.17, fy + 0.36, gz), v3(fx + 0.18, fy + 0.24, gz), 0.042, 0.042, 5, groove);
            b.addCapsule(v3(fx + 0.01, fy, gz), v3(fx - 0.14, fy - 0.24, gz), 0.042, 0.038, 5, groove);
            b.addCapsule(v3(fx + 0.01, fy, gz), v3(fx + 0.16, fy - 0.22, gz), 0.042, 0.038, 5, groove);
        }
    }
    bankInto(&b, &rng, CARVE_R * 1.15, 0.40);
    return b.toModel(shader);
}

pub fn ashHeapMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xA511);
    driftInto(&b, &rng, .{ .len = 3.0, .wide = 1.7, .high = 0.68, .seed = 3 }, 0, 0, 0);
    return b.toModel(shader);
}

pub fn ashDuneMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xA512);
    driftInto(&b, &rng, .{ .len = 9.2, .wide = 3.9, .high = 2.05, .seed = 5 }, 0, 0, 0);
    driftInto(&b, &rng, .{ .len = 5.6, .wide = 2.6, .high = 1.10, .seed = 11 }, 1.9, 3.4, mathx.radians(-13.0));
    return b.toModel(shader);
}

/// **THE ONE GROUND-LEVEL THING IN THE GAME THAT IS ITS OWN LIGHT.** The coals carry a low vertex ALPHA, which the scene shader reads as EMISSIVE — so they hold their glow at any hour without costing a `LightSpec`, and a field of them can be sown by the hundred where sixteen real lights is the whole budget.
pub fn cindersMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xA513);
    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 11) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 1.05);
        const r = rng.range(0.16, 0.40);
        b.addBlob(
            v3(mathx.cosf(a) * d, r * 0.11, mathx.sinf(a) * d),
            v3(r, r * rng.range(0.10, 0.20), r * rng.range(0.7, 1.3)),
            3,
            6,
            if (rng.float() < 0.4) CINDER_GREY else CHAR,
        );
    }
    var j: i32 = 0;
    while (j < 9) : (j += 1) {
        const a = rng.angle();
        const d = rng.range(0.05, 0.95);
        const r = rng.range(0.030, 0.075);
        b.addBlob(v3(mathx.cosf(a) * d, r * 0.35, mathx.sinf(a) * d), v3(r, r * 0.55, r), 3, 5, EMBER_LIVE);
    }
    var k: i32 = 0;
    while (k < 5) : (k += 1) {
        const a = rng.angle();
        const d = rng.range(0.8, 1.25);
        const r = rng.range(0.10, 0.22);
        b.addBlob(v3(mathx.cosf(a) * d, r * 0.3, mathx.sinf(a) * d), v3(r * 1.3, r * 0.30, r), 3, 6, DRIFT_DK);
    }
    return b.toModel(shader);
}

pub const SPAR_H: f32 = 5.4;

pub fn charSparMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xA514);
    b.setMat(.bark);
    const lean = mathx.radians(rng.range(4.0, 9.0));
    const dir = v3(mathx.sinf(lean), mathx.cosf(lean), 0);
    const segs = 6;
    var prev = v3(0, 0, 0);
    var i: i32 = 0;
    while (i < segs) : (i += 1) {
        const t0 = @as(f32, @floatFromInt(i)) / segs;
        const t1 = @as(f32, @floatFromInt(i + 1)) / segs;
        const p1 = mathx.addV(mathx.scaleV(dir, SPAR_H * t1), v3(rng.signed() * 0.09, 0, rng.signed() * 0.09));
        b.addCapsule(prev, p1, mathx.lerpF(0.44, 0.17, t0), mathx.lerpF(0.44, 0.17, t1), 9, art.weathered(CHAR, CHAR_LT, t0));
        prev = p1;
    }
    b.addDome(prev, dir, 0.17, 6, art.PUNK_DK);
    var l: i32 = 0;
    while (l < 3) : (l += 1) {
        const t = 0.34 + 0.22 * @as(f32, @floatFromInt(l));
        const root = mathx.scaleV(dir, SPAR_H * t);
        wood.deadLimbTinted(&b, &rng, root, rng.angle(), rng.range(1.1, 2.0), rng.range(0.25, 0.65), rng.range(0.13, 0.19), 2, CHAR, CHAR_LT);
    }
    b.setMat(.stone);
    var f: i32 = 0;
    while (f < 6) : (f += 1) {
        const a = rng.angle();
        const d = rng.range(0.42, 0.86);
        const r = rng.range(0.16, 0.32);
        b.addBlob(v3(mathx.cosf(a) * d, r * 0.34, mathx.sinf(a) * d), v3(r * 1.4, r * 0.42, r * 1.1), 3, 7, if (rng.float() < 0.5) DRIFT_DK else CHAR);
    }
    return b.toModel(shader);
}

test "A DUNE IS ASYMMETRIC OR IT IS A PUDDING — the long ramp and the short slip face, measured" {
    const d = Drift{ .len = 9.2, .wide = 3.9, .high = 2.05, .seed = 5 };
    const mid: f32 = 0.5;
    var best: f32 = -1;
    var bestU: f32 = 0;
    var u: f32 = d.toe;
    while (u <= d.crest + 0.34) : (u += 0.01) {
        const h = duneH(d, u, mid, 0);
        if (h > best) {
            best = h;
            bestU = u;
        }
    }
    const windward = bestU - d.toe;
    const lee = (d.crest + 0.34) - bestU;
    std.debug.print("\n  ash dune: {d:.2} m high, windward ramp {d:.2} of the section, slip face {d:.2}\n", .{ best, windward, lee });
    try std.testing.expect(windward > lee * 2.0);
    try std.testing.expect(duneH(d, bestU, 0.02, 0) < best * 0.25);
    try std.testing.expect(duneH(d, bestU, 0.98, 0) < best * 0.25);
}

test "the coals are EMISSIVE and the ash around them is not" {
    // Vertex alpha is the emissive channel (255 = fully lit), so a coal must sit well under it and the crust it lies in must not — the two together are the whole effect.
    try std.testing.expect(EMBER_LIVE.a < 128);
    try std.testing.expectEqual(@as(u8, 255), CINDER_GREY.a);
    try std.testing.expectEqual(@as(u8, 255), DRIFT_DK.a);
    try std.testing.expect(CHAR.r < art.BARK_OLD.r);
}
