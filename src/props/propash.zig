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

// ── THE ASHFALL ─────────────────────────────────────────────────────────────────────────────────────────
//
// **A DRIFT HAS A WINDWARD SIDE AND A LEE, AND THAT IS THE WHOLE OF WHY IT READS AS ASH.** A symmetrical
// mound is a pile of anything; the long shallow ramp into the wind and the short steep slip-face out of it
// is the one silhouette that says a fall was blown here rather than tipped. Every heap below is laid on the
// same +X wind, so a field of them agrees about which way the weather came from.

const Drift = struct {
    /// Along the RIDGE, which runs across the wind.
    len: f32,
    /// Across it, which is the axis the asymmetry lives on.
    wide: f32,
    high: f32,
    /// Where the crest sits across the section, -1 (windward toe) to 1 (lee toe). Positive: the long ramp is
    /// on the windward side and the short slip face on the lee, which is the whole silhouette.
    crest: f32 = 0.18,
    /// How far the windward toe reaches. The lee toe is fixed just past the crest — that IS the slip face.
    toe: f32 = -0.80,
    seed: u64 = 1,
};

/// Height of the drift's surface at (`u` across, `v` along), both -1..1 / 0..1. A PURE FUNCTION, so the mesh
/// and its normals come off the same shape and the test below can measure the profile without a builder.
fn duneH(d: Drift, u: f32, v: f32, jitter: f32) f32 {
    // Along the ridge it swells and dies at both ends, off centre so it is not a sausage.
    const env = std.math.pow(f32, mathx.clampF(mathx.sinf(v * std.math.pi), 0, 1), 0.62) *
        (0.86 + 0.14 * mathx.sinf(v * 7.3 + jitter));
    // Across it: a LONG ramp into the wind, a SHORT drop out of it. Everything about a dune is this line.
    const prof = if (u <= d.crest)
        mathx.smoothstep(d.toe, d.crest, u)
    else
        1.0 - mathx.smoothstep(d.crest, d.crest + 0.34, u) * 0.94;
    return d.high * env * mathx.clampF(prof, 0, 1);
}

const DUNE_NV: usize = 15;
const DUNE_NU: usize = 13;

/// **ONE CONTINUOUS SURFACE.** Built as a row of blobs it was a line of loaves however far they overlapped —
/// each one keeps its own crown, and a dune has exactly one. So it is swept: a profile walked along the ridge
/// with smoothed normals, which is the only way the long ramp and the slip face can meet in a single edge.
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
            // TONE FOLLOWS THE HEIGHT, not the station — the crest catches light and the toes do not, which
            // is a gradient across the slope and not a band along it.
            // A CONTINUOUS TWO-STOP GRADIENT. Switching the lerp's TARGET at a threshold puts a step in the
            // colour along that contour — a hard ring round the crest, which is the banding law again in a
            // gradient's clothing. Toes to body, then body to the catch of light, and they meet at 0.80.
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
    // What the drift did not bury: char at its feet, on the windward side where it is being scoured out.
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
    // A SECOND RUN BEHIND THE FIRST, shorter and offset — one ridge is a wall, two are a dune field.
    driftInto(&b, &rng, .{ .len = 5.6, .wide = 2.6, .high = 1.10, .seed = 11 }, 1.9, 3.4, mathx.radians(-13.0));
    return b.toModel(shader);
}

/// **THE ONE GROUND-LEVEL THING IN THE GAME THAT IS ITS OWN LIGHT.** The coals carry a low vertex ALPHA,
/// which the scene shader reads as EMISSIVE — so they hold their glow at any hour without costing a
/// `LightSpec`, and a field of them can be sown by the hundred where sixteen real lights is the whole budget.
pub fn cindersMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xA513);
    b.setMat(.stone);
    // The crust: flat plates, cracked apart, most of the mass sunk so only a few centimetres stand proud.
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
        // IN THE CRACKS, not on the plates: a coal sitting on top of the crust is a berry.
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

/// A tree that burned standing. Charcoal is the darkest albedo in the world and it needs to be: this is a
/// tall smooth mass and anything lighter comes back grey. The limbs are `propwood`'s own — the dead-growth
/// law is the same whether the limb rotted off or burned off.
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
    // Snapped off, and the break shows the one un-burnt thing on it.
    b.addDome(prev, dir, 0.17, 6, art.PUNK_DK);
    var l: i32 = 0;
    while (l < 3) : (l += 1) {
        const t = 0.34 + 0.22 * @as(f32, @floatFromInt(l));
        const root = mathx.scaleV(dir, SPAR_H * t);
        wood.deadLimbTinted(&b, &rng, root, rng.angle(), rng.range(1.1, 2.0), rng.range(0.25, 0.65), rng.range(0.13, 0.19), 2, CHAR, CHAR_LT);
    }
    // The root flare, and the ash the fire left banked against it.
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
    // The crest is where the surface is highest, and it is nowhere near the middle of the section.
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
    // …and it dies at both ends of the ridge rather than being cut off square.
    try std.testing.expect(duneH(d, bestU, 0.02, 0) < best * 0.25);
    try std.testing.expect(duneH(d, bestU, 0.98, 0) < best * 0.25);
}

test "the coals are EMISSIVE and the ash around them is not" {
    // Vertex alpha is the emissive channel (255 = fully lit), so a coal must sit well under it and the
    // crust it lies in must not — the two together are the whole effect.
    try std.testing.expect(EMBER_LIVE.a < 128);
    try std.testing.expectEqual(@as(u8, 255), CINDER_GREY.a);
    try std.testing.expectEqual(@as(u8, 255), DRIFT_DK.a);
    // …and char is the darkest thing in the world, because it is the smoothest big mass in it.
    try std.testing.expect(CHAR.r < art.BARK_OLD.r);
}
