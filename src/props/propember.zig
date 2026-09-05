const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const art = @import("propart.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;
const CHAR = art.CHAR;
const EMBER_LIVE = art.EMBER_LIVE;

// Solved through the chain (screen = 255 x (albedo x 1.72)^(1/2.2)): basalt 24 -> 106, its light 40 -> 137. Darker than CLIFF_ROCK because every piece here is a big smooth mass (the great-bone law).
pub const BASALT = rgba(24, 22, 22, 255);
pub const BASALT_LT = rgba(40, 36, 34, 255);
pub const BASALT_DK = rgba(15, 14, 14, 255);
const CRUST = rgba(30, 26, 24, 255);

/// Alpha is the EMISSIVE channel: the hot core of a seam is the lowest number here, the cooling rim the highest, and nothing over 128 glows.
pub const SEAM_HOT = rgba(255, 176, 70, 28);
pub const SEAM = rgba(238, 112, 30, 46);
pub const SEAM_COOL = rgba(168, 56, 18, 92);

fn heatCol(t: f32) rl.Color {
    const u = mathx.clampF(t, 0, 1);
    return if (u < 0.5) mathx.lerpColor(SEAM_COOL, SEAM, u * 2.0) else mathx.lerpColor(SEAM, SEAM_HOT, (u - 0.5) * 2.0);
}

/// A point on an ellipsoid's skin at (`theta` round, `phi` up), pushed `lift` of its radius outward so a seam laid there sits ON the rock and not in it.
pub fn skinPoint(c: rl.Vector3, r: rl.Vector3, theta: f32, phi: f32, lift: f32) rl.Vector3 {
    const cp = mathx.cosf(phi);
    return v3(
        c.x + r.x * cp * mathx.cosf(theta) * lift,
        c.y + r.y * mathx.sinf(phi) * lift,
        c.z + r.z * cp * mathx.sinf(theta) * lift,
    );
}

const VEIN_LIFT: f32 = 1.02;

/// One glowing crack walked across a blob's skin: `steps` capsules, hottest in the middle and cooling to both ends.
fn veinOn(b: *Builder, rng: *mathx.Rng, c: rl.Vector3, r: rl.Vector3, steps: i32, w: f32) void {
    var theta = rng.angle();
    var phi = rng.range(-0.55, 0.85);
    const dTheta = rng.range(0.16, 0.30) * (if (rng.float() < 0.5) @as(f32, -1) else 1);
    const dPhi = rng.range(-0.22, 0.22);
    var p = skinPoint(c, r, theta, phi, VEIN_LIFT);
    var i: i32 = 0;
    while (i < steps) : (i += 1) {
        theta += dTheta + rng.signed() * 0.08;
        phi = mathx.clampF(phi + dPhi + rng.signed() * 0.10, -0.8, 1.2);
        const q = skinPoint(c, r, theta, phi, VEIN_LIFT);
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps - 1));
        const heat = 1.0 - @abs(t - 0.5) * 2.0;
        const ww = w * mathx.lerpF(0.55, 1.0, heat);
        b.addCapsule(p, q, ww, ww, 5, heatCol(heat * 0.9 + 0.1));
        p = q;
    }
}

/// A glowing seam along the GROUND from `a` to `c`, wandering sideways, with a hot node where it kinks.
fn seamAlong(b: *Builder, rng: *mathx.Rng, a: rl.Vector3, c: rl.Vector3, w: f32, wander: f32) void {
    const n: i32 = 5;
    var p = a;
    var i: i32 = 1;
    while (i <= n) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
        const side = if (i < n) rng.signed() * wander else 0;
        const q = v3(
            mathx.lerpF(a.x, c.x, t) + side * (c.z - a.z),
            a.y,
            mathx.lerpF(a.z, c.z, t) - side * (c.x - a.x),
        );
        const heat = 0.35 + 0.65 * mathx.sinf(t * std.math.pi);
        b.addCapsule(p, q, w, w * 0.9, 5, heatCol(heat));
        if (rng.float() < 0.35) b.addBlob(q, v3(w * 2.2, w * 1.3, w * 2.2), 2, 6, SEAM_HOT);
        p = q;
    }
}

fn coalsInto(b: *Builder, rng: *mathx.Rng, cx: f32, cz: f32, spread: f32, n: i32) void {
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.05, spread) * @sqrt(rng.float());
        const r = rng.range(0.035, 0.085);
        b.addBlob(
            v3(cx + mathx.cosf(a) * d, r * 0.35, cz + mathx.sinf(a) * d),
            v3(r, r * 0.55, r * rng.range(0.8, 1.25)),
            3,
            5,
            if (rng.float() < 0.3) SEAM else EMBER_LIVE,
        );
    }
}

fn basaltTone(rng: *mathx.Rng) rl.Color {
    const u = rng.float();
    return if (u < 0.22) BASALT_LT else if (u < 0.60) BASALT else BASALT_DK;
}

pub const ROCK_TOP: f32 = 2.10;
pub const ROCK_R: f32 = 1.25;
pub fn emberRockMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xE0B0);
    b.setMat(.stone);
    const c = v3(0, ROCK_TOP * 0.44, 0);
    const r = v3(ROCK_R, ROCK_TOP * 0.50, ROCK_R * 0.86);
    b.addBlob(c, r, 5, 11, BASALT);
    const c2 = v3(0.34, ROCK_TOP * 0.66, -0.22);
    const r2 = v3(ROCK_R * 0.62, ROCK_TOP * 0.34, ROCK_R * 0.58);
    b.addBlob(c2, r2, 4, 9, BASALT_LT);
    b.addBlob(v3(-0.62, ROCK_TOP * 0.22, 0.40), v3(ROCK_R * 0.52, ROCK_TOP * 0.26, ROCK_R * 0.46), 4, 8, BASALT_DK);
    var i: i32 = 0;
    while (i < 5) : (i += 1) veinOn(&b, &rng, c, r, 6, rng.range(0.030, 0.050));
    veinOn(&b, &rng, c2, r2, 5, 0.034);
    veinOn(&b, &rng, c2, r2, 4, 0.028);
    art.chipsInto(&b, &rng, 0, 0, 1.7, 0.08, 0.20, 6);
    coalsInto(&b, &rng, 0, 0, 1.5, 5);
    return b.toModel(shader);
}

pub fn emberRocksMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xE0B1);
    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.1, 1.35);
        const rr = rng.range(0.18, 0.48);
        const c = v3(mathx.cosf(a) * d, rr * rng.range(0.42, 0.78), mathx.sinf(a) * d);
        const r = v3(rr * rng.range(0.9, 1.3), rr * rng.range(0.6, 0.9), rr * rng.range(0.9, 1.2));
        b.addBlob(c, r, 3, 7, basaltTone(&rng));
        if (i < 4) veinOn(&b, &rng, c, r, 4, rr * 0.09);
    }
    coalsInto(&b, &rng, 0, 0, 1.4, 7);
    return b.toModel(shader);
}

pub const BURN_TOP: f32 = 2.40;
pub const BURN_LIGHT_Y: f32 = 1.45;
pub fn burningRockMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xE0B2);
    b.setMat(.stone);
    const c = v3(0, 0.62, 0);
    const r = v3(0.98, 0.70, 0.88);
    b.addBlob(c, r, 5, 10, BASALT);
    // The cleft: two shoulders either side of the flame's seat, so the fire sits IN the rock rather than on it.
    b.addBlob(v3(-0.42, 1.12, 0.10), v3(0.46, 0.26, 0.40), 4, 8, BASALT_LT);
    b.addBlob(v3(0.44, 1.08, -0.14), v3(0.42, 0.24, 0.38), 4, 8, BASALT_DK);
    b.addBlob(v3(0, 1.10, 0), v3(0.30, 0.06, 0.26), 2, 8, SEAM_HOT);
    var i: i32 = 0;
    while (i < 4) : (i += 1) veinOn(&b, &rng, c, r, 5, 0.036);
    art.chipsInto(&b, &rng, 0, 0, 1.5, 0.07, 0.18, 5);
    coalsInto(&b, &rng, 0, 0, 1.3, 6);
    art.flameInto(&b, &rng, 0, 1.14, 0, 1.30);
    art.flameInto(&b, &rng, 0.14, 1.12, -0.10, 0.80);
    return b.toModel(shader);
}

pub const CONE_TOP: f32 = 3.60;
pub const CONE_R: f32 = 2.60;
pub const CONE_LIGHT_Y: f32 = 3.35;
/// The summit blob crowns at 3.12, so the vent sits ON it and not inside it.
const CONE_VENT_Y: f32 = 3.10;
pub fn cinderConeMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xE0B3);
    b.setMat(.stone);
    const N = 6;
    var i: i32 = 0;
    while (i < N) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, N - 1);
        const rr = mathx.lerpF(CONE_R, 0.95, t) * rng.range(0.94, 1.06);
        const y = 2.85 * t;
        b.addBlob(v3(rng.signed() * 0.10, y * 0.92 + 0.10, rng.signed() * 0.10), v3(rr, 0.40, rr * rng.range(0.92, 1.08)), 4, 12, if (@mod(i, 2) == 0) BASALT_DK else CRUST);
    }
    // The crater lip, and the vent glowing inside it.
    var k: i32 = 0;
    while (k < 9) : (k += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(k)) / 9.0 + rng.signed() * 0.2;
        const rr = rng.range(0.16, 0.30);
        b.addBlob(v3(mathx.cosf(a) * 0.82, CONE_VENT_Y + rr * 0.5, mathx.sinf(a) * 0.82), v3(rr, rr * 0.8, rr * 1.1), 3, 7, if (rng.float() < 0.5) BASALT_LT else BASALT);
    }
    b.addBlob(v3(0, CONE_VENT_Y + 0.02, 0), v3(0.62, 0.08, 0.60), 3, 10, SEAM);
    b.addBlob(v3(0, CONE_VENT_Y + 0.06, 0), v3(0.34, 0.07, 0.32), 3, 8, SEAM_HOT);
    // Six seams running down the flank from the lip, like spilt light.
    var s: i32 = 0;
    while (s < 6) : (s += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(s)) / 6.0 + rng.signed() * 0.3;
        const len = rng.range(0.45, 0.95);
        const top = v3(mathx.cosf(a) * 0.98, 2.85 * 0.92 + 0.10, mathx.sinf(a) * 0.98);
        const foot = v3(mathx.cosf(a) * (0.98 + (CONE_R - 0.98) * len), 2.85 * (1.0 - len) * 0.92 + 0.12, mathx.sinf(a) * (0.98 + (CONE_R - 0.98) * len));
        seamAlong(&b, &rng, top, foot, 0.040, 0.06);
    }
    coalsInto(&b, &rng, 0, 0, CONE_R * 1.15, 8);
    art.smokeInto(&b, &rng, CONE_VENT_Y, 1.6);
    return b.toModel(shader);
}

pub const FIRE_SPIRE_H: f32 = 8.40;
pub const FIRE_SPIRE_LIGHT_Y: f32 = 8.20;
pub fn fireSpireMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xE0B4);
    b.setMat(.stone);
    const lean = mathx.radians(5.5);
    const N = 9;
    var y: f32 = 0;
    var i: i32 = 0;
    while (i < N) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / N;
        const bh = FIRE_SPIRE_H / N;
        const r = mathx.lerpF(1.30, 0.42, t) * rng.range(0.92, 1.08);
        const off = mathx.sinf(lean) * y;
        const c = v3(off, y + bh * 0.5, rng.signed() * 0.05);
        const rr = v3(r, bh * 0.76, r * rng.range(0.88, 1.12));
        b.addBlob(c, rr, 4, 10, if (@mod(i, 3) == 0) BASALT_LT else if (@mod(i, 3) == 1) BASALT else BASALT_DK);
        if (i >= 1 and i <= 6 and @mod(i, 2) == 1) veinOn(&b, &rng, c, rr, 4, 0.034);
        y += bh;
    }
    const top = v3(mathx.sinf(lean) * y, y, 0);
    // The long fissure: one seam from the vent down the flank, hottest at the top where the fire is.
    var p = v3(top.x + 0.30, top.y - 0.30, 0.32);
    var k: i32 = 0;
    while (k < 8) : (k += 1) {
        const t = @as(f32, @floatFromInt(k + 1)) / 8.0;
        const yy = top.y - 0.30 - t * FIRE_SPIRE_H * 0.58;
        const r = mathx.lerpF(0.44, 1.00, t) * 1.02;
        const a = 0.9 + rng.signed() * 0.25 + t * 0.6;
        const q = v3(mathx.sinf(lean) * yy + mathx.cosf(a) * r, yy, mathx.sinf(a) * r);
        b.addCapsule(p, q, 0.045, 0.040, 5, heatCol(1.0 - t * 0.85));
        p = q;
    }
    b.addBlob(v3(top.x, top.y - 0.06, top.z), v3(0.40, 0.10, 0.38), 2, 8, SEAM);
    var j: i32 = 0;
    while (j < 6) : (j += 1) {
        const a = rng.angle();
        const d = rng.range(1.3, 2.3);
        const r = rng.range(0.20, 0.44);
        b.addBlob(v3(mathx.cosf(a) * d, r * 0.55, mathx.sinf(a) * d), v3(r, r * rng.range(0.5, 0.8), r * rng.range(0.8, 1.3)), 3, 6, basaltTone(&rng));
    }
    art.chipsInto(&b, &rng, 0, 0, 2.2, 0.08, 0.20, 7);
    coalsInto(&b, &rng, 0, 0, 2.0, 6);
    art.flameInto(&b, &rng, top.x, top.y - 0.02, top.z, 1.60);
    art.smokeInto(&b, &rng, top.y + 0.20, 1.3);
    return b.toModel(shader);
}

pub const PILLAR_H: f32 = 5.20;
pub const PILLAR_R: f32 = 0.56;
pub fn emberPillarMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xE0B5);
    b.setMat(.stone);
    const lean = v3(0.18, PILLAR_H, -0.10);
    const SEGS = 4;
    var i: i32 = 0;
    while (i < SEGS) : (i += 1) {
        const t0 = @as(f32, @floatFromInt(i)) / SEGS;
        const t1 = @as(f32, @floatFromInt(i + 1)) / SEGS;
        const r0 = PILLAR_R * mathx.lerpF(1.0, 0.86, t0) * rng.range(0.96, 1.04);
        const r1 = PILLAR_R * mathx.lerpF(1.0, 0.86, t1) * rng.range(0.96, 1.04);
        b.addCylinder(mathx.scaleV(lean, t0), mathx.scaleV(lean, t1), r0, r1, 6, if (@mod(i, 2) == 0) BASALT else BASALT_LT);
        // A glowing joint where two drums meet, 3% proud of the drum so it reads as a line: the heat is in the seams, never on the faces.
        if (i > 0) b.addCylinder(v3(lean.x * t0, lean.y * t0 - 0.03, lean.z * t0), v3(lean.x * t0, lean.y * t0 + 0.03, lean.z * t0), r0 * 1.03, r0 * 1.03, 6, heatCol(0.9 - t0 * 0.7));
    }
    // The rift: one seam up the face, from a white-hot foot to a dull-red head. A hexagon's face stands at 0.87 of its radius, so the seam is laid at 0.90 to sit IN the face.
    const face = 0.7;
    var p = v3(mathx.cosf(face) * PILLAR_R * 0.90, 0.10, mathx.sinf(face) * PILLAR_R * 0.90);
    var k: i32 = 0;
    while (k < 7) : (k += 1) {
        const t = @as(f32, @floatFromInt(k + 1)) / 7.0;
        const rr = PILLAR_R * mathx.lerpF(1.0, 0.86, t) * 0.90;
        const a = face + rng.signed() * 0.22 + t * 0.35;
        const q = v3(lean.x * t + mathx.cosf(a) * rr, PILLAR_H * t * 0.92, lean.z * t + mathx.sinf(a) * rr);
        b.addCapsule(p, q, 0.052, 0.040, 5, heatCol(1.0 - t * 0.9));
        p = q;
    }
    b.addBlob(v3(lean.x, PILLAR_H - 0.02, lean.z), v3(PILLAR_R * 0.92, 0.16, PILLAR_R * 0.84), 3, 6, BASALT_DK);
    b.addBlob(v3(lean.x + 0.12, PILLAR_H + 0.10, lean.z - 0.08), v3(PILLAR_R * 0.46, 0.14, PILLAR_R * 0.40), 3, 6, BASALT_LT);
    art.chipsInto(&b, &rng, 0, 0, 1.4, 0.07, 0.18, 6);
    coalsInto(&b, &rng, mathx.cosf(face) * 0.7, mathx.sinf(face) * 0.7, 0.5, 5);
    return b.toModel(shader);
}

pub const ARCH_H: f32 = 4.40;
pub const ARCH_HALF: f32 = 1.80;
pub const ARCH_LEG_R: f32 = 0.50;
pub fn emberArchMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xE0B6);
    b.setMat(.stone);
    const legH = ARCH_H * 0.68;
    for ([_]f32{ -1, 1 }) |sx| {
        const x = sx * ARCH_HALF;
        b.addCylinder(v3(x, 0, 0), v3(x + sx * 0.06, legH, 0.04), ARCH_LEG_R, ARCH_LEG_R * 0.88, 6, if (sx < 0) BASALT else BASALT_LT);
        b.addCylinder(v3(x, legH * 0.5 - 0.03, 0), v3(x, legH * 0.5 + 0.03, 0), ARCH_LEG_R * 0.97, ARCH_LEG_R * 0.97, 6, heatCol(0.6));
    }
    // The span: five voussoirs on a circular arc, the keystone's joints the hottest.
    const N = 5;
    var i: i32 = 0;
    while (i < N) : (i += 1) {
        const u = (@as(f32, @floatFromInt(i)) + 0.5) / N;
        const a = std.math.pi * (1.0 - u);
        const cx = mathx.cosf(a) * ARCH_HALF;
        const cy = legH + mathx.sinf(a) * (ARCH_H - legH - 0.30);
        const tang = v3(mathx.sinf(a), -mathx.cosf(a), 0);
        const len = std.math.pi * ARCH_HALF / N * 0.52;
        b.addBox(v3(cx, cy, 0), mathx.scaleV(tang, len), v3(-tang.y * 0.34, tang.x * 0.34, 0), v3(0, 0, 0.42), if (@mod(i, 2) == 0) BASALT else BASALT_DK);
        if (i > 0) {
            const ja = std.math.pi * (1.0 - @as(f32, @floatFromInt(i)) / N);
            const jx = mathx.cosf(ja) * ARCH_HALF;
            const jy = legH + mathx.sinf(ja) * (ARCH_H - legH - 0.30);
            const heat = 1.0 - @abs(@as(f32, @floatFromInt(i)) / N - 0.5) * 1.6;
            b.addBox(v3(jx, jy, 0), v3(mathx.sinf(ja) * 0.03, -mathx.cosf(ja) * 0.03, 0), v3(-mathx.cosf(ja) * 0.32, -mathx.sinf(ja) * 0.32, 0), v3(0, 0, 0.44), heatCol(heat));
        }
    }
    // A crack down the left leg, and rubble where the arch has shed.
    var p = v3(-ARCH_HALF - ARCH_LEG_R * 0.90, legH - 0.30, 0.10);
    var k: i32 = 0;
    while (k < 5) : (k += 1) {
        const t = @as(f32, @floatFromInt(k + 1)) / 5.0;
        const a = std.math.pi + 0.25 - t * 0.9 + rng.signed() * 0.15;
        const q = v3(-ARCH_HALF + mathx.cosf(a) * ARCH_LEG_R * 0.92, legH - 0.30 - t * (legH - 0.5), mathx.sinf(a) * ARCH_LEG_R * 0.92);
        b.addCapsule(p, q, 0.042, 0.036, 5, heatCol(0.3 + t * 0.7));
        p = q;
    }
    art.chipsInto(&b, &rng, ARCH_HALF, 0, 1.0, 0.08, 0.22, 5);
    art.chipsInto(&b, &rng, -ARCH_HALF, 0, 1.0, 0.08, 0.22, 4);
    coalsInto(&b, &rng, 0, 0, 1.3, 6);
    return b.toModel(shader);
}

pub const COLS_H: f32 = 3.20;
pub const COLS_R: f32 = 1.55;
pub fn basaltColumnsMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xE0B7);
    b.setMat(.stone);
    // Hexagonal packing: one at the centre, six round it, then a broken outer few.
    const SPACING: f32 = 0.86;
    const COL_R: f32 = 0.44;
    var cells: [13][2]f32 = undefined;
    var n: usize = 0;
    cells[n] = .{ 0, 0 };
    n += 1;
    var k: i32 = 0;
    while (k < 6) : (k += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(k)) / 6.0;
        cells[n] = .{ mathx.cosf(a) * SPACING, mathx.sinf(a) * SPACING };
        n += 1;
    }
    for ([_]i32{ 0, 2, 3, 5 }) |kk| {
        const a = std.math.tau * (@as(f32, @floatFromInt(kk)) + 0.5) / 6.0;
        cells[n] = .{ mathx.cosf(a) * SPACING * 1.74, mathx.sinf(a) * SPACING * 1.74 };
        n += 1;
    }
    for (cells[0..n], 0..) |c, i| {
        const d = @sqrt(c[0] * c[0] + c[1] * c[1]);
        const h = COLS_H * mathx.clampF(1.0 - d / (SPACING * 2.4), 0.30, 1.0) * rng.range(0.82, 1.0);
        const tone = if (@mod(i, 3) == 0) BASALT_LT else if (@mod(i, 3) == 1) BASALT else BASALT_DK;
        b.addCylinder(v3(c[0], 0, c[1]), v3(c[0] + rng.signed() * 0.03, h, c[1] + rng.signed() * 0.03), COL_R, COL_R * 0.96, 6, tone);
        b.addCylinder(v3(c[0], h - 0.02, c[1]), v3(c[0], h + 0.04, c[1]), COL_R * 0.94, COL_R * 0.80, 6, if (rng.float() < 0.5) BASALT_LT else BASALT);
    }
    // The light is UNDER them: seams in the gaps between neighbouring columns, glowing from below.
    for (cells[0..n], 0..) |c, i| {
        for (cells[i + 1 .. n]) |o| {
            const dx = o[0] - c[0];
            const dz = o[1] - c[1];
            if (@sqrt(dx * dx + dz * dz) > SPACING * 1.15) continue;
            const mx = (c[0] + o[0]) * 0.5;
            const mz = (c[1] + o[1]) * 0.5;
            const px = -dz / SPACING;
            const pz = dx / SPACING;
            b.addCapsule(v3(mx - px * 0.30, 0.05, mz - pz * 0.30), v3(mx + px * 0.30, 0.05, mz + pz * 0.30), 0.045, 0.045, 5, heatCol(rng.range(0.5, 1.0)));
        }
    }
    art.chipsInto(&b, &rng, 0, 0, 2.2, 0.06, 0.16, 8);
    coalsInto(&b, &rng, 0, 0, 2.1, 7);
    return b.toModel(shader);
}

pub const SLAB_TOP: f32 = 0.90;
pub const SLAB_R: f32 = 1.55;
pub fn crackedSlabMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xE0B8);
    b.setMat(.stone);
    // Four plates of one broken slab, each heaved a little differently, the seams between them the light.
    const Plate = struct { x: f32, z: f32, hw: f32, hd: f32, lift: f32, tilt: f32 };
    const plates = [_]Plate{
        .{ .x = -0.80, .z = -0.55, .hw = 0.72, .hd = 0.62, .lift = 0.18, .tilt = 0.10 },
        .{ .x = 0.78, .z = -0.50, .hw = 0.68, .hd = 0.58, .lift = 0.30, .tilt = -0.16 },
        .{ .x = -0.70, .z = 0.72, .hw = 0.66, .hd = 0.54, .lift = 0.24, .tilt = 0.06 },
        .{ .x = 0.74, .z = 0.70, .hw = 0.70, .hd = 0.60, .lift = 0.16, .tilt = 0.14 },
    };
    for (plates, 0..) |p, i| {
        const th: f32 = 0.34;
        b.addBox(
            v3(p.x, p.lift, p.z),
            v3(p.hw, p.tilt * p.hw, 0),
            v3(0, th * 0.5, 0),
            v3(0, -p.tilt * 0.4 * p.hd, p.hd),
            if (@mod(i, 2) == 0) BASALT else CRUST,
        );
    }
    seamAlong(&b, &rng, v3(0, 0.10, -1.30), v3(0, 0.10, 1.40), 0.055, 0.06);
    seamAlong(&b, &rng, v3(-1.60, 0.10, 0.05), v3(1.55, 0.10, 0.12), 0.050, 0.05);
    b.addBlob(v3(0.02, 0.14, 0.08), v3(0.26, 0.10, 0.24), 3, 8, SEAM_HOT);
    art.chipsInto(&b, &rng, 0, 0, 2.0, 0.06, 0.16, 7);
    coalsInto(&b, &rng, 0, 0, 1.9, 6);
    return b.toModel(shader);
}

pub const VEIN_R: f32 = 1.05;
pub fn magmaVeinMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xE0B9);
    b.setMat(.stone);
    var run: i32 = 0;
    while (run < 4) : (run += 1) {
        var a = rng.angle();
        var p = v3(rng.signed() * 0.35, 0.03, rng.signed() * 0.35);
        var seg: i32 = 0;
        while (seg < 7) : (seg += 1) {
            a += rng.signed() * 0.7;
            const len = rng.range(0.20, 0.44);
            const q = v3(p.x + mathx.cosf(a) * len, 0.03, p.z + mathx.sinf(a) * len);
            if (mathx.lenXZ(q) > VEIN_R) break;
            const r = rng.range(0.022, 0.046);
            const heat = 1.0 - mathx.lenXZ(q) / VEIN_R * 0.8;
            b.addCapsule(p, q, r, r * 0.85, 5, heatCol(heat));
            if (rng.float() < 0.3) b.addBlob(q, v3(r * 2.2, r * 1.4, r * 2.2), 2, 6, SEAM_HOT);
            p = q;
        }
    }
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.2, VEIN_R);
        const r = rng.range(0.05, 0.11);
        b.addBlob(v3(mathx.cosf(a) * d, r * 0.30, mathx.sinf(a) * d), v3(r, r * 0.35, r * 1.2), 2, 6, if (rng.float() < 0.5) CRUST else BASALT_DK);
    }
    return b.toModel(shader);
}

pub const CRUST_R: f32 = 1.15;
pub fn lavaCrustMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xE0BA);
    b.setMat(.stone);
    // Plates on a jittered grid, the gaps between them glowing: the crust of a flow that has skinned over.
    const PITCH: f32 = 0.46;
    var cells: [16][3]f32 = undefined;
    var n: usize = 0;
    var ix: i32 = -2;
    while (ix < 2) : (ix += 1) {
        var iz: i32 = -2;
        while (iz < 2) : (iz += 1) {
            const x = (@as(f32, @floatFromInt(ix)) + 0.5) * PITCH + rng.signed() * 0.05;
            const z = (@as(f32, @floatFromInt(iz)) + 0.5) * PITCH + rng.signed() * 0.05;
            if (@sqrt(x * x + z * z) > CRUST_R) continue;
            const lift = rng.range(0.04, 0.10);
            cells[n] = .{ x, z, lift };
            n += 1;
            const yaw = rng.signed() * 0.25;
            const hw = PITCH * 0.5 * rng.range(0.74, 0.88);
            b.addBox(
                v3(x, lift, z),
                v3(mathx.cosf(yaw) * hw, rng.signed() * 0.02, mathx.sinf(yaw) * hw),
                v3(0, 0.035, 0),
                v3(-mathx.sinf(yaw) * hw, rng.signed() * 0.02, mathx.cosf(yaw) * hw),
                if (rng.float() < 0.3) BASALT_LT else if (rng.float() < 0.6) CRUST else BASALT,
            );
        }
    }
    for (cells[0..n], 0..) |c, i| {
        for (cells[i + 1 .. n]) |o| {
            const dx = o[0] - c[0];
            const dz = o[1] - c[1];
            if (@sqrt(dx * dx + dz * dz) > PITCH * 1.25) continue;
            const mx = (c[0] + o[0]) * 0.5;
            const mz = (c[1] + o[1]) * 0.5;
            const px = -dz / PITCH * 0.5;
            const pz = dx / PITCH * 0.5;
            const hw = PITCH * 0.42;
            b.addCapsule(v3(mx - px * hw, 0.03, mz - pz * hw), v3(mx + px * hw, 0.03, mz + pz * hw), 0.028, 0.028, 4, heatCol(rng.range(0.35, 1.0)));
        }
    }
    return b.toModel(shader);
}

pub const BED_R: f32 = 1.05;
pub fn emberBedMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xE0BB);
    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 12) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, BED_R) * @sqrt(rng.float());
        const r = rng.range(0.14, 0.36);
        b.addBlob(v3(mathx.cosf(a) * d, r * 0.10, mathx.sinf(a) * d), v3(r, r * rng.range(0.10, 0.20), r * rng.range(0.7, 1.3)), 3, 6, if (rng.float() < 0.5) CHAR else BASALT_DK);
    }
    coalsInto(&b, &rng, 0, 0, BED_R * 0.95, 16);
    b.addBlob(v3(rng.signed() * 0.2, 0.03, rng.signed() * 0.2), v3(0.16, 0.05, 0.14), 2, 7, SEAM_HOT);
    return b.toModel(shader);
}

pub const SCORIA_R: f32 = 1.30;
pub fn scoriaMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xE0BC);
    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 26) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0, SCORIA_R) * @sqrt(rng.float());
        const r = rng.range(0.06, 0.19);
        b.addBlob(
            v3(mathx.cosf(a) * d, r * 0.55, mathx.sinf(a) * d),
            v3(r, r * rng.range(0.55, 0.85), r * rng.range(0.8, 1.25)),
            3,
            6,
            if (rng.float() < 0.4) CHAR else basaltTone(&rng),
        );
    }
    coalsInto(&b, &rng, 0, 0, SCORIA_R * 0.8, 5);
    return b.toModel(shader);
}

test "THE SEAMS ARE EMISSIVE AND THE BASALT IS NOT, and the basalt is darker than the plain's own rock" {
    try std.testing.expect(SEAM_HOT.a < SEAM.a and SEAM.a < SEAM_COOL.a);
    try std.testing.expect(SEAM_COOL.a < 128);
    try std.testing.expectEqual(@as(u8, 255), BASALT.a);
    try std.testing.expectEqual(@as(u8, 255), BASALT_LT.a);
    try std.testing.expectEqual(@as(u8, 255), CRUST.a);
    try std.testing.expect(BASALT.r < art.CLIFF_ROCK.r);
    try std.testing.expect(BASALT_LT.r < art.CLIFF_LT.r);
    try std.testing.expect(SEAM_HOT.r > SEAM.r and SEAM.r > SEAM_COOL.r);
    std.debug.print("\n  ember rock: basalt {d}/{d}/{d} on screen, its light {d}; a hot seam is emissive {d:.2}, a cooling one {d:.2}\n", .{
        @as(u32, @intFromFloat(gfx.screenOf(@floatFromInt(BASALT.r)))),
        @as(u32, @intFromFloat(gfx.screenOf(@floatFromInt(BASALT.g)))),
        @as(u32, @intFromFloat(gfx.screenOf(@floatFromInt(BASALT.b)))),
        @as(u32, @intFromFloat(gfx.screenOf(@floatFromInt(BASALT_LT.r)))),
        1.0 - @as(f32, @floatFromInt(SEAM_HOT.a)) / 255.0,
        1.0 - @as(f32, @floatFromInt(SEAM_COOL.a)) / 255.0,
    });
}

test "A VEIN LIES ON THE SKIN OF ITS ROCK — every point of it a hair outside the ellipsoid, never inside" {
    const c = v3(0.3, 1.1, -0.2);
    const r = v3(1.25, 1.05, 1.08);
    var theta: f32 = 0;
    while (theta < std.math.tau) : (theta += 0.13) {
        var phi: f32 = -0.8;
        while (phi <= 1.2) : (phi += 0.1) {
            const p = skinPoint(c, r, theta, phi, VEIN_LIFT);
            const ux = (p.x - c.x) / r.x;
            const uy = (p.y - c.y) / r.y;
            const uz = (p.z - c.z) / r.z;
            const q = @sqrt(ux * ux + uy * uy + uz * uz);
            try std.testing.expectApproxEqAbs(VEIN_LIFT, q, 1e-4);
        }
    }
    try std.testing.expect(VEIN_LIFT > 1.0 and VEIN_LIFT < 1.06);
}

test "THE HEAT RAMP RUNS COOL TO HOT WITHOUT A STEP, and hotter is always brighter" {
    var prev = heatCol(0);
    var t: f32 = 0.01;
    while (t <= 1.0) : (t += 0.01) {
        const c = heatCol(t);
        try std.testing.expect(c.a <= prev.a);
        try std.testing.expect(c.r >= prev.r);
        prev = c;
    }
    try std.testing.expectEqual(SEAM_COOL.a, heatCol(0).a);
    try std.testing.expectEqual(SEAM_HOT.a, heatCol(1).a);
    std.debug.print("  ember rock: fire spire {d:.1} m, cinder cone {d:.1} m, riven pillar {d:.1} m, arch {d:.1} m over a {d:.1} m span\n", .{ FIRE_SPIRE_H, CONE_TOP, PILLAR_H, ARCH_H, ARCH_HALF * 2.0 });
}
