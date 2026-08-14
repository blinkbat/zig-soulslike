const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const art = @import("propart.zig");

const v3 = mathx.v3;
const Builder = gfx.Builder;
const ASH = art.ASH;
const ASH_DK = art.ASH_DK;
const ASH_LT = art.ASH_LT;
const BARK_DK = art.BARK_DK;
const BRASS = art.BRASS;
const CLOTH = art.CLOTH;
const CLOTH_DK = art.CLOTH_DK;
const CLOTH_SUN = art.CLOTH_SUN;
const IRON = art.IRON;
const MARBLE = art.MARBLE;
const MARBLE_DK = art.MARBLE_DK;
const MARBLE_LT = art.MARBLE_LT;
const MOSS_DK = art.MOSS_DK;
const ROCK_DEEP = art.ROCK_DEEP;
const RUST = art.RUST;
const SCRUB_DK = art.SCRUB_DK;
const STEEL = art.STEEL;
const STONE = art.STONE;
const STONE_DK = art.STONE_DK;
const STONE_LT = art.STONE_LT;
const STONE_MOSS = art.STONE_MOSS;
const THATCH_DK = art.THATCH_DK;
const TIMBER_DK = art.TIMBER_DK;
const WISP = art.WISP;
const blade = art.blade;
const chipsInto = art.chipsInto;
const courseInto = art.courseInto;
const courseStack = art.courseStack;
const crackInto = art.crackInto;
const flameInto = art.flameInto;
const lichenInto = art.lichenInto;
const quoinsInto = art.quoinsInto;
const tuftInto = art.tuftInto;


pub fn pillarWhole(shader: rl.Shader) rl.Model {
    return pillarMesh(shader, false);
}
pub fn pillarBroken(shader: rl.Shader) rl.Model {
    return pillarMesh(shader, true);
}

pub fn pillarMesh(shader: rl.Shader, broken: bool) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (broken) 4801 else 4802);
    b.setMat(.stone);

    const leanX = rng.signed() * 0.035;
    const leanZ = rng.signed() * 0.030;
    const shaftTop: f32 = if (broken) rng.range(2.35, 2.95) else 4.98;
    const axisAt = struct { // the shaft's centre at height y, following the lean
        fn p(y: f32, lx: f32, lz: f32) rl.Vector3 {
            return v3(lx * y, y, lz * y);
        }
    }.p;
    const radAt = struct {
        fn r(y: f32) f32 {
            return 0.62 - 0.115 * mathx.clampF(y / 4.98, 0, 1);
        }
    }.r;

    b.addBox(v3(0, 0.18, 0), v3(0.85, rng.signed() * 0.012, 0.03), v3(0, 0.18, 0), v3(0.04, 0, 0.85), STONE_DK);
    b.addBox(v3(rng.signed() * 0.04, 0.46, rng.signed() * 0.04), v3(0.72, rng.signed() * 0.014, 0.02), v3(0, 0.12, 0), v3(0.03, 0, 0.72), STONE);
    b.setMat(.marble);
    b.addCylinder(v3(0, 0.56, 0), v3(0, 0.72, 0), 0.74, 0.66, 10, MARBLE_LT); // torus base
    b.addCylinder(v3(0, 0.70, 0), v3(0, 0.80, 0), 0.66, 0.63, 10, MARBLE_DK); // the fillet above it

    const nd: i32 = if (broken) 2 else 4;
    var d: i32 = 0;
    while (d < nd) : (d += 1) {
        const y0 = 0.78 + (shaftTop - 0.78) * @as(f32, @floatFromInt(d)) / @as(f32, @floatFromInt(nd));
        const y1 = 0.78 + (shaftTop - 0.78) * @as(f32, @floatFromInt(d + 1)) / @as(f32, @floatFromInt(nd));
        const off = v3(rng.signed() * 0.022, 0, rng.signed() * 0.022); // the drum has slipped
        const p0 = axisAt(y0, leanX, leanZ);
        const p1 = axisAt(y1, leanX, leanZ);
        b.addCylinder(
            v3(p0.x + off.x, y0, p0.z + off.z),
            v3(p1.x + off.x, y1, p1.z + off.z),
            radAt(y0) * rng.range(0.99, 1.02),
            radAt(y1) * rng.range(0.98, 1.01),
            12,
            if (@mod(d, 2) == 0) MARBLE else MARBLE_LT,
        );
        if (d > 0) b.addCylinder(v3(p0.x + off.x, y0 - 0.02, p0.z + off.z), v3(p0.x + off.x, y0 + 0.02, p0.z + off.z), radAt(y0) * 1.015, radAt(y0) * 1.015, 12, MARBLE_DK);
    }
    var fl: i32 = 0;
    while (fl < 16) : (fl += 1) {
        if (rng.float() < 0.20) continue;
        const a = std.math.tau * @as(f32, @floatFromInt(fl)) / 16.0;
        const y0 = 0.80 + rng.range(0.0, 0.25);
        const y1 = shaftTop - rng.range(0.02, 0.30);
        const c0 = axisAt(y0, leanX, leanZ);
        const c1 = axisAt(y1, leanX, leanZ);
        const r0 = radAt(y0) * 0.955;
        const r1 = radAt(y1) * 0.955;
        b.addCylinder(
            v3(c0.x + mathx.cosf(a) * r0, y0, c0.z + mathx.sinf(a) * r0),
            v3(c1.x + mathx.cosf(a) * r1, y1, c1.z + mathx.sinf(a) * r1),
            rng.range(0.016, 0.023),
            rng.range(0.013, 0.019),
            5,
            if (rng.float() < 0.30) MARBLE_DK else MARBLE,
        );
    }

    if (broken) {
        const c = axisAt(shaftTop, leanX, leanZ);
        // THE SNAPPED BED, the fallen drums' own treatment: without it the top drum is an open tube and
        // an overhead framing sees the ground through the shaft (the rubble only half covers it).
        b.addBlob(v3(c.x, shaftTop, c.z), v3(radAt(shaftTop), 0.02, radAt(shaftTop)), 3, 9, MARBLE_DK);
        var s: i32 = 0;
        while (s < 7) : (s += 1) {
            const a = rng.angle();
            const rr = rng.range(0.05, 0.38);
            const h = rng.range(0.04, 0.13);
            b.addBox(
                v3(c.x + mathx.cosf(a) * rr, shaftTop + h * 0.4, c.z + mathx.sinf(a) * rr),
                v3(rng.range(0.10, 0.24), rng.signed() * 0.025, rng.signed() * 0.03),
                v3(rng.signed() * 0.035, h * 0.5, rng.signed() * 0.035),
                v3(rng.signed() * 0.025, 0, rng.range(0.09, 0.22)),
                if (rng.float() < 0.35) MARBLE_LT else MARBLE_DK,
            );
        }
        const dz = rng.range(1.02, 1.32);
        const dx = rng.signed() * 0.5;
        b.addCylinder(v3(dx, 0.52, dz - 0.42), v3(dx + rng.signed() * 0.05, 0.50, dz + 0.42), 0.54, 0.51, 9, MARBLE);
        b.addBlob(v3(dx, 0.52, dz - 0.42), v3(0.54, 0.54, 0.02), 3, 9, MARBLE_DK); // the sawn bed, up-slope
        b.addBlob(v3(dx, 0.50, dz + 0.42), v3(0.51, 0.51, 0.02), 3, 9, MARBLE_LT);
        const ex = -rng.range(1.05, 1.45);
        const ez = rng.signed() * 0.7;
        b.addCylinder(v3(ex - 0.30, 0.26, ez), v3(ex + 0.30, 0.24, ez + rng.signed() * 0.06), 0.47, 0.45, 8, MARBLE_DK); // half-buried
        b.addBlob(v3(ex + 0.30, 0.24, ez), v3(0.02, 0.45, 0.45), 3, 8, MARBLE_DK);
        b.addBlob(v3(ex - 0.30, 0.26, ez), v3(0.02, 0.47, 0.47), 3, 8, MARBLE_DK);
        lichenInto(&b, &rng, v3(dx, 1.02, dz), v3(0.30, 0.03, 0.34), 4);
    } else {
        const c = axisAt(shaftTop, leanX, leanZ);
        b.addCylinder(v3(c.x, shaftTop - 0.14, c.z), v3(c.x, shaftTop, c.z), 0.50, 0.53, 9, MARBLE_DK); // necking
        b.addCube(v3(c.x, shaftTop + 0.02, c.z), v3(1.12, 0.06, 1.12), MARBLE_LT);
        b.addCylinder(v3(c.x, shaftTop, c.z), v3(c.x, shaftTop + 0.30, c.z), 0.53, 0.78, 9, MARBLE_LT); // echinus
        b.addBox( // abacus, laid a touch skew and chipped at one corner
            v3(c.x + rng.signed() * 0.03, shaftTop + 0.42, c.z + rng.signed() * 0.03),
            v3(0.75, rng.signed() * 0.016, 0.02),
            v3(0, 0.11, 0),
            v3(0.02, 0, 0.75),
            MARBLE_DK,
        );
        b.addCylinder(v3(c.x, shaftTop - 0.32, c.z), v3(c.x, shaftTop - 0.24, c.z), 0.545, 0.545, 9, MARBLE_LT);
        b.addBlob(v3(c.x + rng.signed() * 0.9, shaftTop + 0.40, c.z + rng.signed() * 0.9), v3(0.20, 0.10, 0.18), 3, 5, MARBLE_DK);
        b.addBlob(v3(rng.signed() * 1.2, 0.16, rng.signed() * 1.2), v3(0.26, 0.15, 0.22), 3, 5, MARBLE);
    }

    crackInto(&b, v3(mathx.cosf(0.7) * 0.60, 0.95, mathx.sinf(0.7) * 0.60), v3(0.10, 0.99, 0.02), v3(-mathx.sinf(0.7), 0, mathx.cosf(0.7)), rng.range(0.5, 1.1), 0.022, 0.03);
    chipsInto(&b, &rng, 0, 0, 1.45, 0.09, 0.24, 6);
    const ma = rng.angle();
    lichenInto(&b, &rng, v3(mathx.cosf(ma) * 0.60, rng.range(0.9, 1.6), mathx.sinf(ma) * 0.60), v3(0.16, 0.42, 0.16), 4);
    lichenInto(&b, &rng, v3(rng.signed() * 0.5, 0.75, rng.signed() * 0.5), v3(0.34, 0.02, 0.30), 3);
    tuftInto(&b, &rng, rng.signed() * 1.1, rng.signed() * 1.1, 0.75);
    tuftInto(&b, &rng, rng.signed() * 1.3, rng.signed() * 1.3, 0.6);
    return b.toModel(shader);
}

pub fn blockMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4803);
    b.setMat(.marble);
    const tipX = rng.signed() * 0.11;
    const tipZ = rng.signed() * 0.09;
    b.addBox(
        v3(0, 0.48, 0),
        v3(1.10, tipX, 0.02),
        v3(-tipX * 0.4, 0.50, tipZ * 0.4),
        v3(0.03, tipZ, 0.80),
        MARBLE,
    );
    for ([_]f32{ 0.86, 0.98 }) |t| {
        b.addBox(
            v3(t * 1.02, 0.48 + tipX * t * 1.02, 0),
            v3(0.06, tipX, 0),
            v3(0, 0.44 - (t - 0.86) * 1.4, tipZ * 0.4),
            v3(0, 0, 0.86 - (t - 0.86) * 1.2),
            if (t < 0.9) MARBLE_LT else MARBLE_DK,
        );
    }
    var tm: i32 = 0;
    while (tm < 6) : (tm += 1) {
        const u = -0.86 + @as(f32, @floatFromInt(tm)) * 0.30 + rng.signed() * 0.05;
        b.addBox(
            v3(u, 0.985 + tipX * u, rng.signed() * 0.12),
            v3(0.035, 0, 0),
            v3(0, 0.012, 0),
            v3(0, 0, rng.range(0.5, 0.76)),
            if (rng.float() < 0.5) MARBLE_LT else MARBLE_DK,
        );
    }
    var e: i32 = 0;
    while (e < 3) : (e += 1) {
        const u = rng.range(-0.85, 0.85);
        b.addBlob(v3(u, 0.98 + tipX * u, rng.signed() * 0.5), v3(rng.range(0.28, 0.5), 0.055, rng.range(0.22, 0.4)), 3, 6, if (rng.float() < 0.4) MARBLE_LT else MARBLE);
    }
    b.addBox(
        v3(-0.55, 1.32, rng.signed() * 0.16),
        v3(0.36, tipX * 1.2, 0.03),
        v3(-tipX * 0.5, 0.34, 0),
        v3(0.02, 0, 0.50),
        MARBLE_DK,
    );
    b.addBlob(v3(-0.42, 1.62, rng.signed() * 0.2), v3(0.22, 0.10, 0.20), 3, 6, MARBLE_LT);
    const sx = rng.range(-0.35, 0.35);
    crackInto(&b, v3(sx, 0.985, -0.80), v3(0.05, 0.0, 0.999), v3(1, 0, 0), 1.60, 0.024, 0.05);
    b.addBox(
        v3(sx + 0.62, 0.34, 0.05),
        v3(0.44, tipX * 1.8, 0),
        v3(-0.10, 0.34, 0),
        v3(0, 0, 0.74),
        MARBLE_DK,
    ); // the slipped half, dropped and canted
    b.addBox(
        v3(rng.range(-1.5, -1.05), 0.24, rng.range(-1.1, 1.1)),
        v3(0.30, rng.signed() * 0.12, 0.04),
        v3(rng.signed() * 0.1, 0.24, 0),
        v3(0, 0, 0.28),
        MARBLE_LT,
    );
    chipsInto(&b, &rng, 0, 0, 1.55, 0.08, 0.20, 6);
    lichenInto(&b, &rng, v3(rng.signed() * 0.5, 1.02, rng.signed() * 0.4), v3(0.5, 0.025, 0.4), 5); // mossy cap
    lichenInto(&b, &rng, v3(rng.signed() * 0.7, 0.34, -0.84), v3(0.34, 0.20, 0.02), 3); // damp north face
    tuftInto(&b, &rng, rng.range(-1.6, 1.6), rng.range(-1.2, 1.2), 0.8);
    tuftInto(&b, &rng, rng.range(-1.6, 1.6), rng.range(-1.2, 1.2), 0.62);
    return b.toModel(shader);
}

pub fn archMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4804);
    const px: f32 = 2.7; // pier centre offset — the path (x ~ 0 +/- 1) passes clean between
    const spring: f32 = 3.05; // where the arch leaves the piers
    const ringR: f32 = 0.44; // radial thickness of the arch ring
    const dep: f32 = 0.58; // half-depth through the wall
    b.setMat(.stone);
    for ([_]f32{ -px, px }) |x| {
        b.addBox(v3(x, 0.22, 0), v3(0.82, rng.signed() * 0.012, 0.02), v3(0, 0.22, 0), v3(0.02, 0, 0.82), STONE_DK); // base slab
        _ = courseStack(&b, &rng, x, 0.42, 0, 1.05, 1.05, 0.44, 6, 0.05); // the pier, laid in courses
        b.setMat(.marble);
        b.addBox(v3(x, spring - 0.10, 0), v3(0.70, rng.signed() * 0.012, 0), v3(0, 0.13, 0), v3(0, 0, 0.70), MARBLE_LT); // impost
        b.setMat(.stone);
    }
    const NV = 15;
    b.setMat(.marble);
    var i: i32 = 0;
    while (i < NV) : (i += 1) {
        if (i >= 3 and i <= 5) continue; // the collapsed haunch
        const t = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, NV);
        const a = std.math.pi * t;
        const key = i == 7; // the keystone stands proud and a touch deeper
        const ca = mathx.cosf(a);
        const sa = mathx.sinf(a);
        const half = (std.math.pi * px / @as(f32, NV)) * 0.5 * rng.range(1.06, 1.20); // wedges OVERLAP
        const rad = ringR * (if (key) @as(f32, 1.28) else rng.range(0.94, 1.06));
        const cr = px + rad * 0.10; // sits a hair proud of the springing radius
        b.addBox(
            v3(-ca * cr, spring + sa * cr, rng.signed() * 0.015),
            v3(sa * half, ca * half, 0), // tangential: the wedge's width along the ring
            v3(-ca * rad, sa * rad, 0), // radial: its depth through the ring
            v3(0, 0, dep * (if (key) @as(f32, 1.12) else 1.0)),
            if (key) MARBLE_LT else if (rng.float() < 0.26) MARBLE_LT else if (rng.float() < 0.45) MARBLE_DK else MARBLE,
        );
    }
    var s: i32 = 0;
    while (s < NV) : (s += 1) {
        if (s >= 3 and s <= 5) continue;
        const a = std.math.pi * (@as(f32, @floatFromInt(s)) + 0.5) / @as(f32, NV);
        const half = (std.math.pi * px / @as(f32, NV)) * 0.62;
        b.addBox(
            v3(-mathx.cosf(a) * (px - 0.16), spring + mathx.sinf(a) * (px - 0.16), 0),
            v3(mathx.sinf(a) * half, mathx.cosf(a) * half, 0),
            v3(-mathx.cosf(a) * 0.17, mathx.sinf(a) * 0.17, 0),
            v3(0, 0, dep * 0.96),
            MARBLE_DK,
        );
    }
    b.setMat(.marble);
    b.addBox(v3(-2.05, 0.26, rng.range(-0.9, 0.9)), v3(0.34, rng.signed() * 0.14, 0.03), v3(rng.signed() * 0.12, 0.24, 0), v3(0, 0, 0.42), MARBLE);
    b.addBox(v3(-1.35, 0.20, rng.range(-1.1, 0.6)), v3(0.28, rng.signed() * 0.10, 0.02), v3(rng.signed() * 0.1, 0.19, 0), v3(0, 0, 0.36), MARBLE_DK);
    b.setMat(.stone);
    b.addCube(v3(1.30, spring + px + ringR - 0.26, -0.02), v3(0.56, 0.52, 0.56), STONE);
    b.addCube(v3(-0.76, spring + px + ringR - 0.18, 0.03), v3(0.50, 0.44, 0.60), STONE_DK);
    b.addBox(v3(0.3, spring + px + ringR + 0.20, 0), v3(1.35, rng.signed() * 0.02, 0), v3(0, 0.22, 0), v3(0, 0, 0.62), STONE_DK);
    b.addCube(v3(-0.5, spring + px + ringR + 0.56, 0.02), v3(0.62, 0.44, 0.86), STONE);
    b.addCube(v3(1.15, spring + px + ringR + 0.40, -0.04), v3(0.5, 0.26, 0.72), STONE_DK);
    for ([_]f32{ -px, px }) |x| {
        crackInto(&b, v3(x + 0.53, rng.range(0.6, 1.2), rng.signed() * 0.3), v3(rng.signed() * 0.18, 0.98, 0.05), v3(0, 0, 1), rng.range(0.8, 1.6), 0.020, 0.03);
        chipsInto(&b, &rng, x, 0, 1.5, 0.08, 0.22, 5);
        lichenInto(&b, &rng, v3(x, rng.range(0.5, 1.3), 0.56), v3(0.30, 0.30, 0.02), 3);
        tuftInto(&b, &rng, x + rng.signed() * 1.1, rng.signed() * 1.2, 0.8);
    }
    for ([_]f32{ 0.47, 0.62 }) |t| {
        const a = std.math.pi * t;
        const rIn = px - 0.30;
        lichenInto(&b, &rng, v3(-mathx.cosf(a) * rIn, spring + mathx.sinf(a) * rIn, rng.signed() * 0.22), v3(0.15, 0.10, 0.15), 3);
    }
    return b.toModel(shader);
}

pub fn wallMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4805);
    const th: f32 = 0.40; // half-thickness
    courseInto(&b, &rng, -3.55, 0, -0.85, 0, .{ .thick = th, .height = 2.55, .courses = 8, .blockW = 0.62, .crumbleTop = 0.52 });
    courseInto(&b, &rng, -1.05, 0.02, 1.95, -0.02, .{ .thick = th, .height = 3.00, .courses = 9, .blockW = 0.66, .crumbleTop = 0.42 });
    courseInto(&b, &rng, 1.75, 0, 3.55, 0, .{ .thick = th * 1.06, .height = 1.35, .courses = 4, .blockW = 0.58, .crumbleTop = 0.55 });
    var ts: i32 = 0;
    while (ts < 5) : (ts += 1) {
        const x = rng.range(-3.3, 3.2);
        const y = rng.range(0.35, 1.9);
        b.setMat(.stone);
        b.addBox(v3(x, y, 0), v3(rng.range(0.30, 0.46), rng.signed() * 0.02, 0), v3(0, rng.range(0.13, 0.2), 0), v3(0, 0, th * 1.18), if (rng.float() < 0.4) STONE_LT else STONE_DK);
    }
    b.setMat(.stone);
    b.addBox(v3(0.35, 3.28, 0), v3(0.52, rng.signed() * 0.02, 0), v3(0, 0.32, 0), v3(0, 0, th * 0.9), STONE);
    b.addBox(v3(1.45, 3.08, rng.signed() * 0.04), v3(0.34, rng.signed() * 0.03, 0), v3(0, 0.12, 0), v3(0, 0, th * 0.86), STONE_DK);
    b.addCube(v3(-2.05, 1.62, 0), v3(0.20, 0.17, th * 1.6), IRON);
    crackInto(&b, v3(-0.35, 0.15, th * 1.02), v3(rng.signed() * 0.3, 0.95, 0), v3(1, 0, 0), rng.range(1.0, 2.0), 0.024, 0.04);
    chipsInto(&b, &rng, 2.9, 0.5, 1.3, 0.14, 0.42, 6);
    chipsInto(&b, &rng, -3.0, -0.6, 1.1, 0.12, 0.34, 5);
    chipsInto(&b, &rng, 0.4, 0.85, 1.6, 0.09, 0.24, 5);
    lichenInto(&b, &rng, v3(-2.3, 2.5, 0), v3(0.7, 0.06, 0.34), 5); // moss along the broken top
    lichenInto(&b, &rng, v3(1.0, 2.9, 0), v3(0.6, 0.06, 0.32), 4);
    lichenInto(&b, &rng, v3(rng.range(-3, 3), rng.range(0.4, 1.4), -th), v3(0.4, 0.4, 0.02), 4); // the shaded face
    tuftInto(&b, &rng, rng.range(-3.4, 3.4), rng.range(0.5, 0.9), 0.85);
    tuftInto(&b, &rng, rng.range(-3.4, 3.4), rng.range(-0.9, -0.5), 0.7);
    tuftInto(&b, &rng, rng.range(-3.4, 3.4), rng.range(-0.8, 0.8), 0.6);
    return b.toModel(shader);
}

pub fn gravesMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4807);
    const spots = [_][2]f32{ .{ 0, 0 }, .{ 0.95, -0.55 }, .{ -0.85, 0.42 }, .{ 1.62, 0.38 }, .{ -0.35, -0.95 }, .{ 0.55, 0.95 } };
    var lx: f32 = 0;
    var lz: f32 = 0;
    var lh: f32 = 0.6;
    for (spots, 0..) |sp, i| {
        const x = sp[0] + rng.signed() * 0.10;
        const z = sp[1] + rng.signed() * 0.10;
        const tipX = rng.signed() * 0.24; // every stone leans, and none of them the same way
        const tipZ = rng.signed() * 0.16;
        const col = if (rng.float() < 0.24) STONE_LT else if (rng.float() < 0.5) STONE_MOSS else STONE;
        b.setMat(.stone);
        b.addBlob(v3(x, 0.045, z + 0.28), v3(rng.range(0.30, 0.44), 0.055, rng.range(0.36, 0.52)), 3, 6, STONE_MOSS);
        switch (@mod(i, 4)) {
            0 => { // round-topped headstone
                const h = rng.range(0.52, 0.78);
                if (i == 0) {
                    lx = x;
                    lz = z;
                    lh = h;
                }
                b.addBox(v3(x + tipX * h * 0.5, h * 0.5, z + tipZ * h * 0.5), v3(0.26, tipX, 0.02), v3(-tipX * 0.2, h * 0.5, 0), v3(0.01, tipZ, 0.075), col);
                b.addBlob(v3(x + tipX * h, h, z + tipZ * h), v3(0.255, 0.16, 0.075), 3, 7, col);
                crackInto(&b, v3(x + tipX * h * 0.3 + 0.09, h * 0.30, z + tipZ * h * 0.3 + 0.08), v3(tipX * 0.4, 0.98, 0.06), v3(1, 0, 0), rng.range(0.14, 0.34), 0.012, 0.02);
            },
            1 => { // a cross, one arm broken off
                const h = rng.range(0.62, 0.92);
                b.addBox(v3(x + tipX * h * 0.5, h * 0.5, z + tipZ * h * 0.5), v3(0.09, tipX, 0), v3(-tipX * 0.2, h * 0.5, 0), v3(0, tipZ, 0.07), col);
                const ay = h * 0.76;
                b.addBox(v3(x + tipX * ay + 0.11, ay, z + tipZ * ay), v3(0.20, tipX, 0), v3(0, 0.085, 0), v3(0, 0, 0.065), col); // the surviving arm
                b.addBlob(v3(x + tipX * ay - 0.12, ay - 0.02, z + tipZ * ay), v3(0.055, 0.075, 0.06), 3, 5, STONE_DK);
                b.addBlob(v3(x - rng.range(0.24, 0.44), 0.05, z + rng.signed() * 0.3), v3(0.11, 0.05, 0.055), 3, 5, STONE_MOSS); // where it fell
            },
            2 => { // a LEDGER slab, laid flat and sinking at one end
                b.addBox(
                    v3(x, 0.055, z),
                    v3(0.30, rng.signed() * 0.07, 0.03),
                    v3(rng.signed() * 0.05, 0.045, 0),
                    v3(0, rng.signed() * 0.05, 0.44),
                    if (rng.float() < 0.5) STONE_MOSS else STONE_DK,
                );
                // A worn inscription band down it — two shallow lines, all that is legible.
                for ([_]f32{ -0.12, 0.06 }) |o| {
                    b.addBox(v3(x + o, 0.098, z), v3(0.03, 0, 0), v3(0, 0.008, 0), v3(0, 0, 0.30), STONE_DK);
                }
            },
            else => { // a stubby footstone, half swallowed
                const h = rng.range(0.20, 0.34);
                b.addBox(v3(x + tipX * h, h * 0.5, z + tipZ * h), v3(0.15, tipX * 1.5, 0.02), v3(0, h * 0.5, 0), v3(0.01, tipZ, 0.06), STONE_DK);
            },
        }
    }
    chipsInto(&b, &rng, 0.4, 0, 1.35, 0.05, 0.13, 5);
    lichenInto(&b, &rng, v3(lx + 0.08, lh * 0.35, lz + 0.05), v3(0.10, 0.10, 0.05), 4); // on the first stone's face

    lichenInto(&b, &rng, v3(rng.signed() * 0.9, 0.07, rng.signed() * 0.7), v3(0.34, 0.02, 0.30), 4);
    tuftInto(&b, &rng, rng.range(-1.1, 1.8), rng.range(-1.1, 1.1), 0.75);
    tuftInto(&b, &rng, rng.range(-1.1, 1.8), rng.range(-1.1, 1.1), 0.6);
    tuftInto(&b, &rng, rng.range(-1.1, 1.8), rng.range(-1.1, 1.1), 0.5);
    return b.toModel(shader);
}

pub fn swordMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4808);
    const d = v3(0.10, 0.90, 0.42); // unit-ish lean of the blade (point buried at origin)
    const p1 = v3(0.995, 0.090, 0.042); // ~perpendicular, edge direction
    const p2 = v3(0, -0.422, 0.9045); // ~perpendicular, flat direction
    const at = mathx.scaleV; // a point t along a (unit-ish) direction — reuse the shared helper
    const off = struct { // a point t along the blade, nudged e across the edge and f across the flat
        fn p(dd: rl.Vector3, a: rl.Vector3, c: rl.Vector3, t: f32, e: f32, f: f32) rl.Vector3 {
            return v3(dd.x * t + a.x * e + c.x * f, dd.y * t + a.y * e + c.y * f, dd.z * t + a.z * e + c.z * f);
        }
    }.p;
    b.setMat(.steel);
    b.addBox(off(d, p1, p2, 0.30, 0, 0), v3(p1.x * 0.062, p1.y * 0.062, p1.z * 0.062), at(d, 0.30), v3(p2.x * 0.013, p2.y * 0.013, p2.z * 0.013), STEEL);
    b.addBox(off(d, p1, p2, 0.72, 0, 0), v3(p1.x * 0.052, p1.y * 0.052, p1.z * 0.052), at(d, 0.16), v3(p2.x * 0.011, p2.y * 0.011, p2.z * 0.011), STEEL);
    for ([_]f32{ 1, -1 }) |sgn| {
        b.addBox(off(d, p1, p2, 0.50, 0, sgn * 0.012), v3(p1.x * 0.020, p1.y * 0.020, p1.z * 0.020), at(d, 0.38), v3(p2.x * 0.004 * sgn, p2.y * 0.004 * sgn, p2.z * 0.004 * sgn), IRON);
    }
    var n: i32 = 0;
    while (n < 4) : (n += 1) {
        const t = rng.range(0.16, 0.86);
        const sgn: f32 = if (@mod(n, 2) == 0) 1 else -1;
        b.addBlob(off(d, p1, p2, t, sgn * 0.058, 0), v3(0.016, 0.022, 0.016), 3, 5, if (rng.float() < 0.5) RUST else IRON);
    }
    b.addBox(off(d, p1, p2, 0.13, 0, 0), v3(p1.x * 0.058, p1.y * 0.058, p1.z * 0.058), at(d, 0.11), v3(p2.x * 0.0125, p2.y * 0.0125, p2.z * 0.0125), RUST);
    b.addBox(off(d, p1, p2, 0.94, 0.06, 0), v3(p1.x * 0.145, p1.y * 0.145 - 0.030, p1.z * 0.145), at(d, 0.028), v3(p2.x * 0.030, p2.y * 0.030, p2.z * 0.030), STEEL);
    b.addBox(off(d, p1, p2, 0.94, -0.055, 0), v3(p1.x * 0.055, p1.y * 0.055 + 0.018, p1.z * 0.055), at(d, 0.026), v3(p2.x * 0.028, p2.y * 0.028, p2.z * 0.028), RUST);
    b.addBlob(off(d, p1, p2, 0.945, 0, 0), v3(0.036, 0.040, 0.036), 3, 6, STEEL); // the écusson at its centre
    b.setMat(.leather);
    var w: i32 = 0;
    while (w < 7) : (w += 1) {
        const t = 0.975 + @as(f32, @floatFromInt(w)) * 0.032;
        b.addCylinder(at(d, t), at(d, t + 0.026), 0.030 + rng.range(0, 0.004), 0.029, 6, if (@mod(w, 2) == 0) IRON else BARK_DK);
    }
    b.setMat(.steel);
    b.addBlob(at(d, 1.235), v3(0.058, 0.052, 0.058), 4, 7, BRASS); // pommel, a disc not a cube
    b.addCylinder(at(d, 1.255), at(d, 1.275), 0.020, 0.016, 6, BRASS);
    b.setMat(.stone);
    b.addBlob(v3(0.02, 0.055, 0.02), v3(0.30, 0.075, 0.27), 3, 6, STONE_MOSS);
    b.addBlob(v3(rng.range(0.22, 0.40), 0.10, rng.range(-0.34, -0.16)), v3(0.13, 0.11, 0.11), 3, 5, STONE_DK);
    chipsInto(&b, &rng, 0, 0, 0.55, 0.04, 0.09, 3);
    tuftInto(&b, &rng, rng.signed() * 0.28, rng.signed() * 0.28, 0.72);
    tuftInto(&b, &rng, rng.signed() * 0.42, rng.signed() * 0.42, 0.55);
    return b.toModel(shader);
}

pub fn bonfireMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4809);
    b.setMat(.stone);
    var k: i32 = 0;
    while (k < 10) : (k += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(k)) / 10.0 + rng.signed() * 0.30;
        const dd = rng.range(0.78, 1.08);
        const rr = rng.range(0.085, 0.215);
        b.addBlob(
            v3(mathx.cosf(a) * dd, rr * rng.range(0.36, 0.70), mathx.sinf(a) * dd),
            v3(rr, rr * rng.range(0.55, 0.85), rr * rng.range(0.85, 1.30)),
            3,
            5 + rng.intn(2),
            if (rng.float() < 0.3) STONE_MOSS else if (rng.float() < 0.5) ROCK_DEEP else STONE_DK,
        );
    }
    b.setMat(.plain);
    b.addBlob(v3(0, 0.055, 0), v3(0.82, 0.070, 0.82), 3, 12, ASH_DK);
    b.addBlob(v3(rng.signed() * 0.06, 0.095, rng.signed() * 0.06), v3(0.66, 0.070, 0.64), 3, 11, ASH);
    b.addBlob(v3(rng.signed() * 0.10, 0.125, rng.signed() * 0.10), v3(0.40, 0.055, 0.38), 3, 9, ASH_LT);
    var dr: i32 = 0;
    while (dr < 7) : (dr += 1) {
        const a = rng.angle();
        const dd = rng.range(0.18, 0.66);
        const rr = rng.range(0.09, 0.20);
        b.addBlob(
            v3(mathx.cosf(a) * dd, 0.115 + rng.range(0, 0.03), mathx.sinf(a) * dd),
            v3(rr, rng.range(0.018, 0.038), rr * rng.range(0.7, 1.2)),
            3,
            6,
            if (rng.float() < 0.4) ASH_LT else if (rng.float() < 0.6) ASH_DK else ASH,
        );
    }
    b.setMat(.wood);
    var lg: i32 = 0;
    while (lg < 6) : (lg += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(lg)) / 6.0 + rng.signed() * 0.34;
        const foot = rng.range(0.42, 0.56);
        const apex = rng.range(0.10, 0.19);
        const top = rng.range(0.62, 0.88);
        b.addCapsule(
            v3(mathx.cosf(a) * foot, 0.10, mathx.sinf(a) * foot),
            v3(mathx.cosf(a) * apex + rng.signed() * 0.05, top, mathx.sinf(a) * apex + rng.signed() * 0.05),
            rng.range(0.055, 0.082),
            rng.range(0.042, 0.065),
            5,
            if (rng.float() < 0.45) IRON else if (rng.float() < 0.5) BARK_DK else TIMBER_DK,
        );
    }
    var fd: i32 = 0;
    while (fd < 3) : (fd += 1) {
        const a = rng.angle();
        const far = rng.range(1.05, 1.45);
        b.addCapsule(
            v3(mathx.cosf(a) * far, rng.range(0.07, 0.11), mathx.sinf(a) * far),
            v3(mathx.cosf(a) * 0.20, rng.range(0.20, 0.30), mathx.sinf(a) * 0.20),
            rng.range(0.058, 0.086),
            rng.range(0.045, 0.062),
            5,
            if (rng.float() < 0.4) BARK_DK else TIMBER_DK,
        );
    }
    flameInto(&b, &rng, rng.signed() * 0.05, 0.16, rng.signed() * 0.05, 2.20);
    flameInto(&b, &rng, rng.signed() * 0.30, 0.13, rng.signed() * 0.30, 1.45);
    flameInto(&b, &rng, rng.signed() * 0.34, 0.12, rng.signed() * 0.34, 1.05);
    bedrollInto(&b, &rng, 1.28, -0.62, 2.42);
    art.guitarRockInto(&b, &rng, GUITAR_CX, GUITAR_CZ);
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 1.05, rng.signed() * 1.05, 0.55);
    lichenInto(&b, &rng, v3(rng.signed() * 0.6, 0.07, rng.signed() * 0.6), v3(0.24, 0.02, 0.22), 3);
    return b.toModel(shader);
}

pub fn bonfireVeilMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4811);
    smokeInto(&b, &rng);
    return b.toModel(shader);
}

fn smokeInto(b: *Builder, rng: *mathx.Rng) void {
    const SRC: f32 = 1.0; // the source height the shader billows each puff about
    const PUFFS = 14;
    b.setMat(.smoke);
    var s: i32 = 0;
    while (s < PUFFS) : (s += 1) {
        const phase = (@as(f32, @floatFromInt(s)) + rng.range(0, 0.55)) / @as(f32, @floatFromInt(PUFFS));
        b.setAnimY(gfx.smokeAnim(SRC, phase));
        const r = rng.range(0.135, 0.235);
        b.addBlob(
            v3(rng.signed() * 0.10, SRC + rng.signed() * 0.06, rng.signed() * 0.10),
            v3(r, r * rng.range(0.72, 0.98), r * rng.range(0.85, 1.20)),
            3,
            7,
            if (phase < 0.3) art.SMOKE_HOT else if (phase < 0.65) art.SMOKE_MID else art.SMOKE_COLD,
        );
    }

    b.setMat(.ember);
    var e: i32 = 0;
    while (e < 26) : (e += 1) {
        const phase = (@as(f32, @floatFromInt(e)) + rng.range(0, 0.9)) / 26.0;
        b.setAnimY(gfx.smokeAnim(SRC, phase));
        const a = rng.angle();
        const dd = rng.range(0.04, 0.30);
        const sz = rng.range(0.018, 0.038);
        b.addBlob(
            v3(mathx.cosf(a) * dd, SRC - rng.range(0.18, 0.34), mathx.sinf(a) * dd),
            v3(sz, sz, sz),
            2,
            5,
            if (rng.float() < 0.75) art.EMBER else WISP,
        );
    }
    b.setAnimY(0);
    b.setMat(.plain);
}

fn bedrollInto(b: *Builder, rng: *mathx.Rng, cx: f32, cz: f32, yaw: f32) void {
    const ux = mathx.cosf(yaw);
    const uz = mathx.sinf(yaw);
    b.setMat(.cloth);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const t = (@as(f32, @floatFromInt(i)) / 4.0 - 0.5) * 0.92;
        const r = 0.185 * (1.0 - 0.18 * @abs(t) / 0.46);
        b.addBlob(
            v3(cx + ux * t, 0.055 + rng.range(0, 0.012), cz + uz * t),
            v3(r, 0.052, r),
            3,
            7,
            if (rng.float() < 0.4) THATCH_DK else TIMBER_DK,
        );
    }
    var k: i32 = 0;
    while (k < 4) : (k += 1) {
        const t = (@as(f32, @floatFromInt(k)) / 3.0 - 0.55) * 0.70;
        b.addBlob(
            v3(cx + ux * t - uz * 0.055, 0.105 + rng.range(0, 0.03), cz + uz * t + ux * 0.055),
            v3(rng.range(0.130, 0.175), rng.range(0.045, 0.070), rng.range(0.130, 0.175)),
            3,
            6,
            if (rng.float() < 0.5) CLOTH_DK else CLOTH,
        );
    }
    b.addCapsule(
        v3(cx + ux * 0.50 - uz * 0.15, 0.115, cz + uz * 0.50 + ux * 0.15),
        v3(cx + ux * 0.50 + uz * 0.15, 0.115, cz + uz * 0.50 - ux * 0.15),
        0.105,
        0.095,
        7,
        CLOTH_SUN,
    );
}

pub fn bonfireGuitarMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    art.guitarLeaningInto(&b, GUITAR_CX, GUITAR_CZ, GUITAR_YAW, GUITAR_S);
    return b.toModel(shader);
}

/// Where the rock and its guitar sit in the camp's local frame — read by BOTH meshes, so the guitar cannot
/// drift off the rock it leans on. The placement itself is `propart`'s now: the campfire grew one too, and the
/// lean is not a thing to keep in step in two files.
const GUITAR_CX: f32 = -1.62;
const GUITAR_CZ: f32 = 1.18;
const GUITAR_YAW: f32 = -1.56;
const GUITAR_S: f32 = 1.5;

pub fn towerMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4810);
    b.setMat(.stone);
    const W: f32 = 6.4;
    b.addBox(v3(0, 0.55, 0), v3(W * 0.60, rng.signed() * 0.01, 0), v3(0, 0.55, 0), v3(0, 0, W * 0.60), STONE_DK);
    b.addBox(v3(0, 1.20, 0), v3(W * 0.545, rng.signed() * 0.01, 0), v3(0, 0.30, 0), v3(0, 0, W * 0.545), STONE);
    const yMid = courseStack(&b, &rng, 0, 1.42, 0, W, W, 0.86, 8, 0.06);
    b.addBox(v3(0.15, yMid + 0.16, -0.1), v3(W * 0.56, rng.signed() * 0.012, 0), v3(0, 0.16, 0), v3(0, 0, W * 0.56), STONE_LT); // string course
    const yTop = courseStack(&b, &rng, 0.3, yMid + 0.32, -0.2, W * 0.85, W * 0.85, 0.82, 7, 0.07);
    for ([_][2]f32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }) |f| {
        const h = rng.range(0.62, 0.88) * yMid;
        b.addBox(
            v3(f[0] * W * 0.52, h * 0.5, f[1] * W * 0.52),
            v3(@abs(f[1]) * 1.05 + @abs(f[0]) * 0.30, rng.signed() * 0.02, 0),
            v3(0, h * 0.5, 0),
            v3(0, 0, @abs(f[0]) * 1.05 + @abs(f[1]) * 0.30),
            if (rng.float() < 0.4) STONE_LT else STONE_DK,
        );
        b.addBlob(v3(f[0] * W * 0.52, h + 0.12, f[1] * W * 0.52), v3(0.95, 0.22, 0.95), 3, 6, STONE); // its weathered set-off
    }
    var sl: i32 = 0;
    while (sl < 9) : (sl += 1) {
        const face = rng.intn(4);
        const y = rng.range(2.6, yTop - 1.2);
        const along = rng.range(-W * 0.34, W * 0.34);
        const outward: f32 = W * 0.505;
        const p = switch (face) {
            0 => v3(outward, y, along),
            1 => v3(-outward, y, along),
            2 => v3(along, y, outward),
            else => v3(along, y, -outward),
        };
        const tall = rng.range(0.45, 1.05);
        const wide = rng.range(0.13, 0.24);
        const across = face < 2;
        b.addCube(v3(p.x, p.y, p.z), v3(if (across) 0.34 else wide, tall, if (across) wide else 0.34), IRON);
        b.addCube(v3(p.x, p.y + tall * 0.62, p.z), v3(if (across) 0.30 else wide * 1.9, 0.14, if (across) wide * 1.9 else 0.30), STONE_LT); // its lintel
    }
    for ([_][2]f32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }) |f| {
        var cb: i32 = 0;
        while (cb < 5) : (cb += 1) {
            if (rng.float() < 0.22) continue; // some have fallen
            const t = (@as(f32, @floatFromInt(cb)) - 2.0) * 1.15;
            const px = f[0] * W * 0.47 + f[1] * t + 0.3;
            const pz = f[1] * W * 0.47 + f[0] * t - 0.2;
            b.addBox(v3(px, yTop - 0.25, pz), v3(0.28, rng.signed() * 0.03, 0), v3(0, 0.20, 0), v3(0, 0, 0.28), STONE_DK);
        }
    }
    var m: i32 = 0;
    while (m < 16) : (m += 1) {
        const side = @divTrunc(m, 4);
        const t = (@as(f32, @floatFromInt(@mod(m, 4))) - 1.5) * 1.25;
        if (side == 1 and @mod(m, 4) < 3) continue; // a whole run gone
        if (rng.float() < 0.35) continue;
        const sx: f32 = switch (side) {
            0 => W * 0.40,
            1 => -W * 0.40,
            2 => t,
            else => t,
        };
        const sz: f32 = switch (side) {
            0 => t,
            1 => t,
            2 => W * 0.40,
            else => -W * 0.40,
        };
        const h = rng.range(0.5, 1.5);
        b.addBox(v3(sx + 0.3, yTop + h * 0.5, sz - 0.2), v3(0.48, rng.signed() * 0.03, 0), v3(0, h * 0.5, 0), v3(0, 0, 0.48), if (rng.float() < 0.3) STONE_LT else STONE_DK);
    }
    var js: i32 = 0;
    while (js < 4) : (js += 1) {
        const a = rng.angle();
        const dd = rng.range(0.4, 2.1);
        const h = rng.range(0.8, 2.9);
        b.addBox(
            v3(0.3 + mathx.cosf(a) * dd, yTop + h * 0.45, -0.2 + mathx.sinf(a) * dd),
            v3(rng.range(0.5, 1.3), rng.signed() * 0.1, 0),
            v3(rng.signed() * 0.15, h * 0.5, rng.signed() * 0.15),
            v3(0, 0, rng.range(0.5, 1.2)),
            if (rng.float() < 0.35) STONE else STONE_DK,
        );
    }
    var t: i32 = 0;
    while (t < 12) : (t += 1) {
        const a = rng.range(0.2, 1.7);
        const dd = rng.range(W * 0.55, W * 0.55 + 3.4);
        const rr = rng.range(0.35, 1.5) * (1.0 - 0.32 * (dd - W * 0.55) / 3.4);
        b.addBlob(v3(mathx.cosf(a) * dd, rr * 0.55, mathx.sinf(a) * dd), v3(rr, rr * 0.7, rr * rng.range(0.8, 1.25)), 3, 6, if (rng.float() < 0.3) STONE_MOSS else if (rng.float() < 0.55) STONE_LT else STONE_DK);
    }
    b.setMat(.plant);
    var g: i32 = 0;
    while (g < 5) : (g += 1) {
        const a = rng.angle();
        b.addBlob(v3(mathx.cosf(a) * W * 0.5, rng.range(1.4, yTop * 0.9), mathx.sinf(a) * W * 0.5), v3(rng.range(0.4, 0.9), 0.22, rng.range(0.4, 0.9)), 3, 6, if (rng.float() < 0.5) SCRUB_DK else MOSS_DK);
    }
    tuftInto(&b, &rng, rng.signed() * 4.2, rng.signed() * 4.2, 1.1);
    tuftInto(&b, &rng, rng.signed() * 4.6, rng.signed() * 4.6, 0.9);
    return b.toModel(shader);
}

pub fn gateMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4811);
    const TX: f32 = 7.5; // tower centres — the portal opens between their inner faces at ±5
    const R: f32 = 5.0; // portal radius
    const SPR: f32 = 6.2; // springing height
    const DEP: f32 = 1.7; // half-depth of the gate wall
    b.setMat(.stone);
    for ([_]f32{ -TX, TX }) |x| {
        b.addBox(v3(x, 0.7, 0), v3(3.05, rng.signed() * 0.01, 0), v3(0, 0.7, 0), v3(0, 0, 3.05), STONE_DK); // battered plinth
        const yc = courseStack(&b, &rng, x, 1.4, 0, 5.0, 5.0, 0.92, 14, 0.05);
        b.addBox(v3(x, yc + 0.22, 0), v3(2.85, rng.signed() * 0.014, 0), v3(0, 0.22, 0), v3(0, 0, 2.85), STONE_LT); // cornice
        _ = courseStack(&b, &rng, x, yc + 0.44, 0, 4.2, 4.2, 0.78, 2, 0.04);
        quoinsInto(&b, &rng, x - 2.4, -2.4, 1.4, 0.92, 14, 0.9, 0.42);
        quoinsInto(&b, &rng, x + 2.4, 2.4, 1.4, 0.92, 14, 0.9, 0.42);
    }
    courseInto(&b, &rng, -TX + 1.0, 0, TX - 1.0, 0, .{ .thick = DEP, .height = 15.6, .courses = 17, .blockW = 1.15, .crumbleTop = 0.40, .crumble = 0.03, .gapLo = -R - 0.3, .gapHi = R + 0.3, .sillY = -1, .headY = SPR + R + 0.7 });
    const NV = 16;
    var i: i32 = 0;
    while (i < NV) : (i += 1) {
        const t = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, NV);
        const a = std.math.pi * t;
        const key = i == 7 or i == 8;
        const ca = mathx.cosf(a);
        const sa = mathx.sinf(a);
        const half = (std.math.pi * R / @as(f32, NV)) * 0.5 * rng.range(1.06, 1.18);
        const rad = 0.92 * (if (key) @as(f32, 1.22) else rng.range(0.94, 1.08));
        const cr = R + rad;
        b.addBox(
            v3(-ca * cr, SPR + sa * cr, 0),
            v3(sa * half, ca * half, 0),
            v3(-ca * rad, sa * rad, 0),
            v3(0, 0, DEP * (if (key) @as(f32, 1.14) else rng.range(0.98, 1.04))),
            if (key) STONE_LT else if (rng.float() < 0.24) STONE_LT else if (rng.float() < 0.44) STONE_DK else STONE,
        );
        b.addBox(
            v3(-ca * (R - 0.28), SPR + sa * (R - 0.28), 0),
            v3(sa * half * 1.2, ca * half * 1.2, 0),
            v3(-ca * 0.30, sa * 0.30, 0),
            v3(0, 0, DEP * 0.97),
            STONE_DK,
        );
    }
    b.setMat(.steel);
    var pc: i32 = 0;
    while (pc < 7) : (pc += 1) {
        if (rng.float() < 0.4) continue;
        const px = (@as(f32, @floatFromInt(pc)) - 3.0) * 1.25;
        const drop = @sqrt(@max(R * R - px * px, 0.1));
        b.addCapsule(v3(px, SPR + drop - 0.4, -DEP * 0.55), v3(px + rng.signed() * 0.2, SPR + drop * rng.range(0.15, 0.6), -DEP * 0.55), 0.13, 0.10, 5, RUST);
    }
    b.addCapsule(v3(-3.6, SPR + 2.4, -DEP * 0.55), v3(3.4, SPR + 2.7, -DEP * 0.55), 0.14, 0.12, 5, RUST); // a surviving cross-bar
    b.setMat(.stone);
    var cb: i32 = 0;
    while (cb < 13) : (cb += 1) {
        if (rng.float() < 0.18) continue;
        const px = (@as(f32, @floatFromInt(cb)) - 6.0) * 1.05;
        for ([_]f32{ -1, 1 }) |sgn| {
            b.addBox(v3(px, 13.55, sgn * DEP * 1.06), v3(0.34, rng.signed() * 0.03, 0), v3(0, 0.28, 0), v3(0, 0, 0.34), STONE_DK);
        }
    }
    b.addBox(v3(0, 14.25, 0), v3(TX - 0.6, rng.signed() * 0.02, 0), v3(0, 0.55, 0), v3(0, 0, DEP * 1.14), STONE); // the platform slab
    var m: i32 = 0;
    while (m < 11) : (m += 1) {
        if (m >= 3 and m <= 5) continue;
        if (rng.float() < 0.24) continue;
        const px = (@as(f32, @floatFromInt(m)) - 5.0) * 1.24;
        const h = rng.range(0.7, 1.5);
        b.addBox(v3(px, 14.8 + h * 0.5, rng.signed() * 0.06), v3(0.46, rng.signed() * 0.03, 0), v3(0, h * 0.5, 0), v3(0, 0, DEP * 0.92), if (rng.float() < 0.3) STONE_LT else STONE_DK);
    }
    crackInto(&b, v3(-1.9, 14.7, DEP * 1.16), v3(rng.signed() * 0.35, -0.94, 0), v3(1, 0, 0), 2.6, 0.09, 0.14);
    chipsInto(&b, &rng, 0, -DEP * 1.6, 3.2, 0.35, 1.05, 8);
    for ([_]f32{ -TX, TX }) |x| chipsInto(&b, &rng, x, 0, 3.6, 0.30, 1.25, 7);
    b.setMat(.plant);
    var g: i32 = 0;
    while (g < 7) : (g += 1) {
        const a = rng.angle();
        const dd = rng.range(4.0, 10.0);
        b.addBlob(v3(mathx.cosf(a) * dd, rng.range(1.6, 13.0), mathx.sinf(a) * dd * 0.24), v3(rng.range(0.5, 1.1), 0.26, rng.range(0.4, 0.9)), 3, 6, if (rng.float() < 0.5) SCRUB_DK else MOSS_DK);
    }
    tuftInto(&b, &rng, rng.signed() * 8.0, rng.signed() * 3.0, 1.2);
    tuftInto(&b, &rng, rng.signed() * 9.0, rng.signed() * 3.0, 1.0);
    return b.toModel(shader);
}

pub fn bannerMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4812);
    const tilt = v3(rng.range(0.16, 0.34), 0, rng.signed() * 0.16);
    const top = v3(tilt.x, 3.18, tilt.z);
    b.setMat(.wood);
    b.addCapsule(v3(0, 0, 0), top, 0.058, 0.036, 6, BARK_DK); // the pole
    b.setMat(.cloth);
    var w: i32 = 0;
    while (w < 5) : (w += 1) {
        const t = 0.925 + @as(f32, @floatFromInt(w)) * 0.011;
        b.addCylinder(v3(tilt.x * t, 3.18 * t, tilt.z * t), v3(tilt.x * (t + 0.008), 3.18 * (t + 0.008), tilt.z * (t + 0.008)), 0.050, 0.048, 5, if (@mod(w, 2) == 0) THATCH_DK else BARK_DK);
    }
    b.setMat(.wood);
    const armY: f32 = 3.02;
    b.addCapsule(v3(tilt.x * 0.95 - 0.30, armY, tilt.z * 0.95 + 0.02), v3(tilt.x * 0.95 + 0.82, armY + 0.09, tilt.z * 0.95 + 0.06), 0.030, 0.022, 5, BARK_DK); // crossarm
    b.setMat(.steel);
    b.addBlob(top, v3(0.048, 0.07, 0.048), 3, 6, RUST); // the socket
    b.addCylinder(v3(top.x, 3.24, top.z), v3(top.x + tilt.x * 0.08, 3.62, top.z), 0.042, 0.004, 5, IRON); // a spear finial
    b.setMat(.cloth);
    var s: i32 = 0;
    while (s < 11) : (s += 1) {
        const u = (@as(f32, @floatFromInt(s)) + 0.5) / 11.0;
        const px = tilt.x * 0.95 - 0.26 + u * 1.04;
        const pz = tilt.z * 0.95 + 0.03 + u * 0.04;
        const shape = 0.42 + 0.58 * mathx.sinf(u * std.math.pi); // long in the middle, torn short at the flanks
        const len = rng.range(0.36, 1.02) * shape;
        if (rng.float() < 0.10) continue; // a strip gone entirely
        const drift = rng.range(0.03, 0.13);
        b.addBox(
            v3(px + drift * 0.5, armY - len * 0.5 - 0.04, pz + drift * 0.25),
            v3(0.052, rng.signed() * 0.004, rng.signed() * 0.006),
            v3(drift, -len * 0.5, drift * 0.4),
            v3(0.004, 0, 0.016),
            if (rng.float() < 0.28) CLOTH_DK else CLOTH,
        );
        if (rng.float() < 0.55) {
            b.addBox(
                v3(px + drift * 1.1, armY - len - 0.10, pz + drift * 0.5),
                v3(0.030, 0, 0),
                v3(drift * 0.4, -rng.range(0.05, 0.18), 0),
                v3(0.003, 0, 0.012),
                CLOTH_SUN,
            );
        }
    }
    b.addBox(v3(rng.range(0.4, 0.9), 0.07, rng.range(-0.5, 0.5)), v3(0.14, rng.signed() * 0.03, 0.02), v3(0, 0.012, 0), v3(0.01, 0, 0.20), CLOTH_DK); // a tatter caught in the grass
    chipsInto(&b, &rng, 0.04, 0.02, 0.42, 0.11, 0.22, 6); // the stones packed round the butt
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 0.55, rng.signed() * 0.55, 0.8);
    tuftInto(&b, &rng, rng.signed() * 0.8, rng.signed() * 0.8, 0.6);
    return b.toModel(shader);
}

pub fn statueMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4813);
    b.setMat(.stone);
    b.addBox(v3(0, 0.16, 0), v3(0.80, rng.signed() * 0.01, 0.02), v3(0, 0.16, 0), v3(0.02, 0, 0.80), STONE_DK); // plinth
    b.addBox(v3(rng.signed() * 0.02, 0.46, rng.signed() * 0.02), v3(0.68, rng.signed() * 0.012, 0.02), v3(0, 0.14, 0), v3(0.02, 0, 0.68), STONE);
    b.addBlob(v3(rng.range(0.35, 0.62), 0.16, rng.range(-0.7, -0.4)), v3(0.22, 0.16, 0.20), 3, 5, STONE_MOSS); // a spalled plinth corner
    var ins: i32 = 0;
    while (ins < 3) : (ins += 1) {
        // Spaced to stay on the LOWER plinth's face (it tops out at 0.32): the old 0.075 step put the
        // third line above the stone and 11 cm in front of the upper one — a bar hanging in the air.
        b.addBox(v3(rng.signed() * 0.10, 0.16 + @as(f32, @floatFromInt(ins)) * 0.05, -0.79), v3(rng.range(0.28, 0.52), 0, 0), v3(0, 0.016, 0), v3(0, 0, 0.02), STONE_DK);
    }
    b.setMat(.marble);
    b.addBox(v3(0, 0.62, 0), v3(0.56, rng.signed() * 0.01, 0), v3(0, 0.08, 0), v3(0, 0, 0.56), MARBLE_LT); // the statue's own base
    // One smooth taper read as an obelisk however good the folds on it.
    const sway = v3(rng.signed() * 0.06, 0, rng.signed() * 0.05);
    const shoulderY: f32 = 2.36;
    b.addCapsule(v3(0, 0.72, 0), v3(sway.x * 0.4, 1.34, sway.z * 0.4), 0.455, 0.385, 10, MARBLE); // the skirt over the hips
    b.addCapsule(v3(sway.x * 0.4, 1.34, sway.z * 0.4), v3(sway.x * 0.75, 1.80, sway.z * 0.75), 0.385, 0.295, 10, MARBLE); // drawn in through the waist
    b.addCapsule(v3(sway.x * 0.75, 1.80, sway.z * 0.75), v3(sway.x, shoulderY - 0.08, sway.z), 0.295, 0.33, 10, MARBLE); // the chest filling back out
    const rOf = struct {
        fn go(y: f32) f32 {
            if (y < 1.34) return mathx.lerpF(0.455, 0.385, (y - 0.72) / 0.62);
            if (y < 1.80) return mathx.lerpF(0.385, 0.295, (y - 1.34) / 0.46);
            return mathx.lerpF(0.295, 0.33, (y - 1.80) / 0.48);
        }
    }.go;
    var f: i32 = 0;
    while (f < 7) : (f += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(f)) / 7.0 + rng.signed() * 0.55;
        const y0 = rng.range(0.70, 1.10);
        const y1 = rng.range(1.45, 2.20);
        const fr = rng.range(0.055, 0.085);
        const a1 = a + rng.signed() * 0.30;
        const in0 = rOf(y0) - fr * 0.55;
        const in1 = rOf(y1) - fr * 0.55;
        b.addCapsule(
            v3(mathx.cosf(a) * in0 + sway.x * (y0 - 0.66) / 1.7, y0, mathx.sinf(a) * in0 + sway.z * (y0 - 0.66) / 1.7),
            v3(mathx.cosf(a1) * in1 + sway.x * (y1 - 0.66) / 1.7, y1, mathx.sinf(a1) * in1 + sway.z * (y1 - 0.66) / 1.7),
            fr,
            fr * rng.range(0.55, 0.8),
            5,
            if (rng.float() < 0.32) MARBLE_LT else if (rng.float() < 0.55) MARBLE_DK else MARBLE,
        );
    }
    b.addCylinder(v3(0, 0.64, 0), v3(0, 0.84, 0), 0.52, 0.455, 10, MARBLE_DK);
    b.addBlob(v3(sway.x, shoulderY - 0.04, sway.z), v3(0.42, 0.17, 0.29), 6, 10, MARBLE_LT);
    b.addBox(v3(sway.x, shoulderY + 0.06, sway.z), v3(0.38, rng.signed() * 0.02, 0), v3(0, 0.11, 0), v3(0, 0, 0.21), MARBLE);
    b.addCylinder(v3(sway.x, shoulderY + 0.14, sway.z), v3(sway.x + 0.03, shoulderY + 0.26, sway.z + 0.02), 0.115, 0.095, 7, MARBLE_DK);
    var jn: i32 = 0;
    while (jn < 4) : (jn += 1) {
        const a = rng.angle();
        b.addBlob(v3(sway.x + mathx.cosf(a) * 0.06, shoulderY + 0.28 + rng.range(0, 0.05), sway.z + mathx.sinf(a) * 0.06), v3(0.045, 0.035, 0.045), 3, 5, MARBLE_LT);
    }
    const ea = v3(sway.x + 0.40, shoulderY - 0.30, sway.z + 0.18);
    b.addCapsule(v3(sway.x + 0.24, shoulderY - 0.04, sway.z + 0.02), ea, 0.155, 0.115, 8, MARBLE); // the sleeve
    b.addCapsule(ea, v3(sway.x + 0.34, shoulderY - 0.64, sway.z + 0.10), 0.095, 0.05, 6, MARBLE_DK); // its cloth hanging off the elbow
    b.addCapsule(ea, v3(sway.x + 0.62, shoulderY - 0.44, sway.z + 0.36), 0.085, 0.062, 7, MARBLE); // the bare forearm
    b.addBlob(v3(sway.x + 0.68, shoulderY - 0.49, sway.z + 0.41), v3(0.085, 0.058, 0.078), 4, 7, MARBLE_LT); // the open hand
    b.addBlob(v3(sway.x - 0.32, shoulderY - 0.08, sway.z + 0.02), v3(0.15, 0.12, 0.13), 4, 7, MARBLE_DK); // the lost arm's break, rough
    const hx = rng.range(-1.05, -0.62);
    const hz = rng.range(-0.5, 0.75);
    b.addBlob(v3(hx, 0.20, hz), v3(0.21, 0.19, 0.24), 4, 8, MARBLE);
    b.addBlob(v3(hx + 0.06, 0.13, hz - 0.16), v3(0.13, 0.10, 0.11), 3, 6, MARBLE_DK); // the jaw, half in the turf
    b.addBlob(v3(hx - 0.12, 0.30, hz + 0.10), v3(0.13, 0.09, 0.14), 3, 6, MARBLE_LT); // the crown of it, catching the sun
    b.addCapsule(v3(hx - 0.06, 0.245, hz + 0.19), v3(hx + 0.10, 0.235, hz + 0.17), 0.035, 0.030, 5, MARBLE_DK); // the brow line
    b.addBlob(v3(hx + 0.03, 0.185, hz + 0.235), v3(0.032, 0.045, 0.036), 3, 6, MARBLE_LT); // the nose
    b.addCapsule(v3(rng.range(0.5, 0.9), 0.09, rng.range(0.2, 0.8)), v3(rng.range(0.9, 1.3), 0.07, rng.range(-0.1, 0.5)), 0.075, 0.055, 5, MARBLE_DK);
    chipsInto(&b, &rng, 0, 0, 1.45, 0.07, 0.18, 6);
    const la = rng.angle();
    lichenInto(&b, &rng, v3(mathx.cosf(la) * 0.40, rng.range(1.0, 1.9), mathx.sinf(la) * 0.40), v3(0.13, 0.42, 0.13), 4);
    lichenInto(&b, &rng, v3(rng.signed() * 0.4, 0.61, rng.signed() * 0.4), v3(0.36, 0.02, 0.32), 4);
    lichenInto(&b, &rng, v3(hx, 0.32, hz), v3(0.14, 0.02, 0.14), 2);
    tuftInto(&b, &rng, rng.range(-1.3, 1.3), rng.range(-1.2, 1.2), 0.85);
    tuftInto(&b, &rng, rng.range(-1.3, 1.3), rng.range(-1.2, 1.2), 0.65);
    return b.toModel(shader);
}

pub fn rubbleMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4814);
    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 6) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.85) * @sqrt(rng.float());
        const rr = rng.range(0.14, 0.34);
        b.addBlob(
            v3(mathx.cosf(a) * d, rr * rng.range(0.32, 0.66), mathx.sinf(a) * d),
            v3(rr, rr * rng.range(0.5, 0.85), rr * rng.range(0.8, 1.3)),
            3,
            6,
            if (rng.float() < 0.26) STONE_MOSS else if (rng.float() < 0.5) STONE_LT else STONE_DK,
        );
    }
    var g: i32 = 0;
    while (g < 2) : (g += 1) {
        const a = rng.angle();
        const d = rng.range(0.3, 0.9);
        const s = rng.range(0.16, 0.30);
        const yaw = rng.angle();
        const lean = rng.range(0.18, 0.42);
        const cy = mathx.cosf(yaw);
        const sy = mathx.sinf(yaw);
        const cl = mathx.cosf(lean);
        const sl = mathx.sinf(lean);
        const u = v3(cy * cl, sl, sy * cl); // long axis, tipped off the horizontal
        const w = v3(-cy * sl, cl, -sy * sl); // its up, leaning with it
        const hd = s * rng.range(0.6, 1.1); // half-depth along the level third axis
        b.addBox(
            v3(mathx.cosf(a) * d, s * 0.38, mathx.sinf(a) * d),
            v3(u.x * s, u.y * s, u.z * s),
            v3(w.x * s * 0.62, w.y * s * 0.62, w.z * s * 0.62),
            v3(-sy * hd, 0, cy * hd),
            if (rng.float() < 0.5) STONE_DK else STONE,
        );
    }
    b.setMat(.marble);
    b.addCylinder(v3(-0.15, 0.15, 0.62), v3(0.42, 0.13, 0.92), 0.17, 0.15, 7, MARBLE);
    b.addBlob(v3(-0.15, 0.15, 0.62), v3(0.03, 0.17, 0.17), 3, 7, MARBLE_DK);
    b.addBox(v3(rng.range(-0.9, -0.4), 0.055, rng.range(-0.8, 0.2)), v3(0.20, rng.signed() * 0.05, 0.02), v3(0, 0.05, 0), v3(0, 0, 0.13), MARBLE_LT);
    chipsInto(&b, &rng, 0, 0, 1.0, 0.035, 0.09, 9);
    lichenInto(&b, &rng, v3(rng.signed() * 0.4, 0.14, rng.signed() * 0.4), v3(0.26, 0.02, 0.24), 3);
    tuftInto(&b, &rng, rng.signed() * 0.9, rng.signed() * 0.9, 0.6);
    tuftInto(&b, &rng, rng.signed() * 1.0, rng.signed() * 1.0, 0.45);
    return b.toModel(shader);
}

