const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const art = @import("propart.zig");

const v3 = mathx.v3;
const Builder = gfx.Builder;
const BARK_DK = art.BARK_DK;
const BARK_OLD = art.BARK_OLD;
const BONE = art.BONE;
const CANVAS = art.CANVAS;
const CLOTH_DK = art.CLOTH_DK;
const FLAME_CORE = art.FLAME_CORE;
const FLAME_MID = art.FLAME_MID;
const FLAME_TIP = art.FLAME_TIP;
const IRON = art.IRON;
const MARBLE = art.MARBLE;
const MARBLE_DK = art.MARBLE_DK;
const MARBLE_LT = art.MARBLE_LT;
const MORTAR = art.MORTAR;
const MOSS_SOFT = art.MOSS_SOFT;
const PETAL_WHITE = art.PETAL_WHITE;
const ROCK_DEEP = art.ROCK_DEEP;
const RUST = art.RUST;
const STONE = art.STONE;
const STONE_DK = art.STONE_DK;
const STONE_LT = art.STONE_LT;
const STONE_MOSS = art.STONE_MOSS;
const THATCH = art.THATCH;
const THATCH_DK = art.THATCH_DK;
const TIMBER = art.TIMBER;
const TIMBER_DK = art.TIMBER_DK;
const lichenInto = art.lichenInto;
const tuftInto = art.tuftInto;

pub fn cartMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4747);
    b.setMat(.wood);
    var pl: i32 = 0;
    while (pl < 6) : (pl += 1) {
        const z = (@as(f32, @floatFromInt(pl)) - 2.5) * 0.28;
        if (rng.float() < 0.15) continue;
        b.addBox(v3(0, 0.72 + rng.signed() * 0.02, z), v3(1.05, -0.20, 0), v3(0, 0.055, 0), v3(0, 0, 0.13), if (@mod(pl, 2) == 0) TIMBER else TIMBER_DK);
    }
    b.addCapsule(v3(-1.05, 0.60, 0), v3(1.05, 0.44, 0), 0.09, 0.08, 6, TIMBER_DK);
    b.addCapsule(v3(1.0, 0.50, 0.1), v3(2.15, 0.95, 0.25), 0.075, 0.05, 5, TIMBER_DK);
    for ([_]f32{ -1, 1 }) |sz| {
        const zr = sz * 0.80;
        var st: i32 = 0;
        while (st < 3) : (st += 1) {
            const sx = -0.85 + @as(f32, @floatFromInt(st)) * 0.85 + rng.signed() * 0.06;
            const by = 0.72 - 0.20 * (sx / 1.05);
            b.addCapsule(v3(sx, by - 0.06, zr), v3(sx + rng.signed() * 0.04, by + 0.34, zr + rng.signed() * 0.04), 0.042, 0.034, 4, TIMBER_DK);
        }
        if (sz > 0) {
            b.addBox(v3(0.0, 0.72 + 0.36, zr), v3(1.02, -0.195, 0), v3(0, 0.045, 0), v3(0, 0, 0.035), TIMBER);
        } else {
            b.addBox(v3(-0.55, 0.72 + 0.105 + 0.36, zr), v3(0.48, -0.09, 0), v3(0, 0.045, 0), v3(0, 0, 0.035), TIMBER);
            b.addBox(v3(0.42, 0.60, zr + 0.10), v3(0.34, -0.16, 0.05), v3(0, 0.04, 0.02), v3(0, 0.015, 0.032), TIMBER_DK);
        }
    }
    const wheel = struct {
        fn go(bb: *Builder, cx: f32, cy: f32, cz: f32, rad: f32, flat: bool, r: *mathx.Rng) void {
            const seg: i32 = 10;
            var i: i32 = 0;
            while (i < seg) : (i += 1) {
                const a0 = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(seg));
                const a1 = std.math.tau * @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(seg));
                if (r.float() < 0.12) continue;
                const p0 = if (flat) v3(cx + mathx.cosf(a0) * rad, cy, cz + mathx.sinf(a0) * rad) else v3(cx + mathx.cosf(a0) * rad, cy + mathx.sinf(a0) * rad, cz);
                const p1 = if (flat) v3(cx + mathx.cosf(a1) * rad, cy, cz + mathx.sinf(a1) * rad) else v3(cx + mathx.cosf(a1) * rad, cy + mathx.sinf(a1) * rad, cz);
                bb.addCapsule(p0, p1, 0.075, 0.075, 5, BARK_DK);
                if (@mod(i, 2) == 0) bb.addCapsule(v3(cx, cy, cz), p0, 0.035, 0.028, 4, TIMBER_DK);
            }
            bb.setMat(.steel);
            i = 0;
            while (i < seg) : (i += 1) {
                const a0 = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(seg));
                const a1 = std.math.tau * @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(seg));
                const tr2 = rad + 0.075;
                const p0 = if (flat) v3(cx + mathx.cosf(a0) * tr2, cy, cz + mathx.sinf(a0) * tr2) else v3(cx + mathx.cosf(a0) * tr2, cy + mathx.sinf(a0) * tr2, cz);
                const p1 = if (flat) v3(cx + mathx.cosf(a1) * tr2, cy, cz + mathx.sinf(a1) * tr2) else v3(cx + mathx.cosf(a1) * tr2, cy + mathx.sinf(a1) * tr2, cz);
                bb.addCapsule(p0, p1, 0.030, 0.030, 4, if (r.float() < 0.35) RUST else IRON);
            }
            bb.setMat(.wood);
            bb.addBlob(v3(cx, cy, cz), if (flat) v3(0.13, 0.09, 0.13) else v3(0.13, 0.13, 0.09), 4, 8, TIMBER_DK);
            bb.setMat(.steel);
            bb.addBlob(v3(cx, cy, cz), if (flat) v3(0.055, 0.115, 0.055) else v3(0.055, 0.055, 0.115), 3, 6, RUST);
            bb.setMat(.wood);
        }
    }.go;
    wheel(&b, -0.9, 0.62, 0.95, 0.60, false, &rng);
    wheel(&b, 0.85, 0.09, -1.0, 0.58, true, &rng);
    b.setMat(.steel);
    b.addBox(v3(0.0, 0.79, 0.02), v3(0.05, -0.01, 0), v3(0, 0.014, 0), v3(0, 0, 0.72), IRON);
    b.setMat(.cloth);
    b.addBlob(v3(0.2, 0.84, 0.2), v3(0.45, 0.10, 0.36), 4, 7, CLOTH_DK);
    b.addBlob(v3(0.52, 0.72, 0.42), v3(0.24, 0.07, 0.20), 3, 6, CANVAS);
    b.addBlob(v3(0.42, 0.78, -0.04), v3(0.17, 0.045, 0.14), 3, 5, CLOTH_DK);
    b.setMat(.leather);
    b.addCapsule(v3(0.55, 0.80, 0.35), v3(0.86, 0.52, 0.78), 0.016, 0.014, 4, BARK_DK);
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 1.2, rng.signed() * 1.2, 0.7);
    return b.toModel(shader);
}


pub fn wellMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2101);
    b.setMat(.stone);
    const R: f32 = 0.80;
    b.addCylinder(v3(0, 0.02, 0), v3(0, 1.04, 0), R, R, 12, MORTAR);
    var c: i32 = 0;
    while (c < 4) : (c += 1) {
        const y0 = 0.05 + @as(f32, @floatFromInt(c)) * 0.25;
        var a = rng.angle();
        const stop = a + std.math.tau;
        while (a < stop) {
            const halfArc = rng.range(0.09, 0.19);
            const dHalf = halfArc / R;
            const am = a + dHalf;
            const cs = mathx.cosf(am);
            const sn = mathx.sinf(am);
            const hh = rng.range(0.085, 0.125);
            const depth = rng.range(0.045, 0.085);
            b.addBox(
                v3(cs * R, y0 + hh + rng.signed() * 0.012, sn * R),
                v3(-sn * halfArc, rng.signed() * 0.022, cs * halfArc),
                v3(0, hh, 0),
                v3(cs * depth, 0, sn * depth),
                if (rng.float() < 0.16) STONE_LT else if (rng.float() < 0.22) STONE_DK else STONE,
            );
            a += 2 * dHalf + rng.range(0.015, 0.05) / R;
        }
    }
    for ([_]f32{ 0.10, 0.94 }) |my| {
        const ma = rng.angle();
        lichenInto(&b, &rng, v3(mathx.cosf(ma) * 0.84, my, mathx.sinf(ma) * 0.84), v3(0.22, 0.09, 0.20), 3);
    }
    b.setMat(.stone);
    const nc: i32 = 11;
    var k: i32 = 0;
    while (k < nc) : (k += 1) {
        if (k == 7) continue;
        const am = std.math.tau * (@as(f32, @floatFromInt(k)) + 0.5) / @as(f32, @floatFromInt(nc));
        const shove: f32 = if (k == 3) rng.range(0.04, 0.07) else 0.0;
        const cs = mathx.cosf(am);
        const sn = mathx.sinf(am);
        const halfArc = std.math.pi * 2.0 * 0.875 / @as(f32, @floatFromInt(nc)) * 0.5 * 1.18;
        b.addBox(
            v3(cs * (0.875 + shove), 1.07 + rng.signed() * 0.012, sn * (0.875 + shove)),
            v3(-sn * halfArc, rng.signed() * 0.018, cs * halfArc),
            v3(0, rng.range(0.06, 0.078), 0),
            v3(cs * 0.13, 0, sn * 0.13),
            if (rng.float() < 0.22) STONE else STONE_DK,
        );
    }
    b.addBlob(v3(0, 0.62, 0), v3(0.80, 0.26, 0.80), 3, 12, ROCK_DEEP);
    b.setMat(.wood);
    for ([_]f32{ -0.78, 0.78 }) |px| {
        b.addCapsule(v3(px, 1.0, 0), v3(px + rng.signed() * 0.05, 2.05, rng.signed() * 0.05), 0.085, 0.07, 6, TIMBER_DK);
    }
    b.addCapsule(v3(-0.9, 2.02, 0), v3(0.9, 2.06, 0), 0.075, 0.075, 6, TIMBER);
    b.addBox(v3(0.95, 2.04, 0.16), v3(0.03, 0, 0), v3(0, 0.02, 0.18), v3(0, 0.16, 0), TIMBER_DK);
    b.addCapsule(v3(0.2, 2.0, 0), v3(0.2, 1.25, 0.02), 0.018, 0.018, 4, BARK_DK);
    b.addCylinder(v3(0.55, 1.10, 0.55), v3(0.55, 1.38, 0.55), 0.17, 0.19, 8, TIMBER);
    b.addDome(v3(0.55, 1.10, 0.55), v3(0, -1, 0), 0.17, 8, TIMBER_DK);
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 1.3, rng.signed() * 1.3, 0.8);
    b.addBlob(v3(0.62, 1.10, -0.36), v3(0.19, 0.05, 0.16), 3, 6, MOSS_SOFT);
    return b.toModel(shader);
}

pub fn shrineMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2102);
    b.setMat(.stone);
    b.addCube(v3(0, 0.14, 0), v3(1.5, 0.28, 1.2), STONE_DK);
    b.addCube(v3(0, 0.36, 0), v3(1.2, 0.18, 0.95), STONE);
    for ([_]f32{ -0.44, 0.44 }) |sx| b.addCube(v3(sx, 1.05, 0.06), v3(0.22, 1.2, 0.82), STONE);
    b.addCube(v3(0, 1.05, 0.42), v3(1.1, 1.2, 0.2), STONE_DK);
    b.addBox(v3(0, 1.735, 0.06), v3(0.70, 0.015, 0), v3(0, 0.045, 0), v3(0, 0, 0.50), STONE_DK);
    for ([_]f32{ -1, 1 }) |sgn| {
        b.addBox(
            v3(sgn * 0.35, 1.97, 0.06),
            v3(sgn * 0.35, -0.195, 0),
            v3(0, 0.065, 0),
            v3(0, 0, 0.47 * rng.range(0.96, 1.04)),
            if (sgn < 0) STONE else STONE_LT,
        );
    }
    b.addBox(v3(rng.signed() * 0.02, 2.20, 0.06), v3(0.125, 0.008, 0), v3(0, 0.05, 0), v3(0, 0, 0.45), STONE_LT);
    b.addBox(v3(-0.58, 1.72, -0.30), v3(0.15, -0.05, 0), v3(0, 0.04, 0), v3(0, 0, 0.13), STONE_DK);
    b.addBlob(v3(0.40, 0.47, -0.30), v3(0.13, 0.05, 0.10), 3, 5, STONE_LT);
    lichenInto(&b, &rng, v3(-0.20, 2.02, -0.02), v3(0.15, 0.05, 0.13), 3);
    b.setMat(.stone);
    b.addCylinder(v3(0, 0.46, 0.06), v3(rng.signed() * 0.03, 1.24, 0.06), 0.26, 0.17, 8, STONE_LT);
    b.addBlob(v3(0, 1.34, 0.06), v3(0.17, 0.19, 0.17), 4, 7, STONE);
    b.setMat(.plain);
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const x = -0.34 + @as(f32, @floatFromInt(i)) * 0.34;
        const h = rng.range(0.09, 0.17);
        b.setMat(.cloth);
        b.addCylinder(v3(x, 0.45, -0.34), v3(x, 0.45 + h, -0.34), 0.035, 0.032, 6, PETAL_WHITE);
        b.setMat(.flame);
        b.setAnimY(0.45 + h);
        b.addBlob(v3(x, 0.45 + h + 0.035, -0.34), v3(0.022, 0.045, 0.022), 3, 5, FLAME_CORE);
        b.addBlob(v3(x, 0.45 + h + 0.085, -0.34), v3(0.014, 0.035, 0.014), 3, 5, FLAME_TIP);
        b.setAnimY(0);
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 1.0, rng.signed() * 0.9, 0.7);
    b.addBlob(v3(rng.signed() * 0.7, 0.42, -0.5), v3(0.2, 0.07, 0.16), 3, 5, MOSS_SOFT);
    return b.toModel(shader);
}

pub fn lanternMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2103);
    b.setMat(.stone);
    b.addBlob(v3(0, 0.12, 0), v3(0.34, 0.13, 0.32), 3, 6, STONE_DK);
    b.setMat(.wood);
    b.addCapsule(v3(0, 0.06, 0), v3(rng.signed() * 0.08, 2.78, rng.signed() * 0.08), 0.075, 0.055, 6, TIMBER_DK);
    b.setMat(.steel);
    b.addCapsule(v3(0.02, 2.76, 0), v3(0.30, 2.86, 0), 0.03, 0.024, 5, IRON);
    b.addCapsule(v3(0.30, 2.86, 0), v3(0.30, 2.74, 0), 0.02, 0.02, 4, IRON);
    var u: i32 = 0;
    while (u < 4) : (u += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(u)) / 4.0 + 0.4;
        b.addCapsule(v3(0.30 + mathx.cosf(a) * 0.12, 2.44, mathx.sinf(a) * 0.12), v3(0.30 + mathx.cosf(a) * 0.12, 2.74, mathx.sinf(a) * 0.12), 0.017, 0.017, 4, IRON);
    }
    b.addCylinder(v3(0.30, 2.42, 0), v3(0.30, 2.47, 0), 0.14, 0.14, 8, IRON);
    b.addDome(v3(0.30, 2.42, 0), v3(0, -1, 0), 0.14, 8, IRON);
    b.addCylinder(v3(0.30, 2.74, 0), v3(0.30, 2.80, 0), 0.16, 0.11, 8, IRON);
    b.addDome(v3(0.30, 2.80, 0), v3(0, 1, 0), 0.11, 8, IRON);
    b.setMat(.flame);
    b.setAnimY(2.48);
    b.addBlob(v3(0.30, 2.56, 0), v3(0.075, 0.10, 0.075), 4, 7, FLAME_CORE);
    b.addBlob(v3(0.30, 2.66, 0), v3(0.045, 0.07, 0.045), 3, 6, FLAME_MID);
    b.setAnimY(0);
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 0.5, rng.signed() * 0.5, 0.75);
    return b.toModel(shader);
}

pub fn fenceMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2104);
    b.setMat(.wood);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const x = -3.0 + @as(f32, @floatFromInt(i)) * 1.0;
        if (rng.float() < 0.14) continue;
        const h = rng.range(0.85, 1.22);
        b.addCapsule(v3(x, 0, rng.signed() * 0.05), v3(x + rng.signed() * 0.16, h, rng.signed() * 0.14), 0.075, 0.06, 5, TIMBER_DK);
    }
    var r: i32 = 0;
    while (r < 2) : (r += 1) {
        const y = 0.48 + @as(f32, @floatFromInt(r)) * 0.36;
        var x: f32 = -3.0;
        while (x < 2.9) {
            const seg = rng.range(0.9, 2.1);
            if (rng.float() > 0.22) {
                b.addBox(v3(x + seg * 0.5, y + rng.signed() * 0.04, 0), v3(seg * 0.5, rng.signed() * 0.03, 0), v3(0, 0.045, 0), v3(0, 0, 0.035), if (rng.float() < 0.5) TIMBER else TIMBER_DK);
            }
            x += seg + rng.range(0.05, 0.35);
        }
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.range(-2.6, 2.6), rng.signed() * 0.3, 0.85);
    tuftInto(&b, &rng, rng.range(-2.6, 2.6), rng.signed() * 0.3, 0.7);
    return b.toModel(shader);
}

pub fn barrelsMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2105);
    const barrel = struct {
        fn go(bb: *Builder, r: *mathx.Rng, cx: f32, cz: f32, tilt: f32, h: f32, open: bool) void {
            bb.setMat(.wood);
            bb.addCylinder(v3(cx, 0.01, cz), v3(cx + tilt * 0.5, h * 0.5, cz), 0.26, 0.30, 10, TIMBER_DK);
            bb.addCylinder(v3(cx + tilt * 0.5, h * 0.5, cz), v3(cx + tilt, h, cz), 0.30, 0.26, 10, TIMBER_DK);
            const staves: i32 = 9;
            const staveTop = if (open) h - 0.11 else h - 0.03;
            var i: i32 = 0;
            while (i < staves) : (i += 1) {
                const a = std.math.tau * (@as(f32, @floatFromInt(i)) + r.range(-0.15, 0.15)) / @as(f32, @floatFromInt(staves));
                bb.addCapsule(
                    v3(cx + mathx.cosf(a) * 0.245, 0.04, cz + mathx.sinf(a) * 0.245),
                    v3(cx + mathx.cosf(a) * 0.245 + tilt, staveTop, cz + mathx.sinf(a) * 0.245),
                    0.045,
                    0.04,
                    4,
                    if (r.float() < 0.4) TIMBER else TIMBER_DK,
                );
            }
            bb.setMat(.steel);
            for ([_]f32{ 0.18, 0.74 }) |t| {
                bb.addCylinder(v3(cx + tilt * t, h * t, cz), v3(cx + tilt * t, h * t + 0.05, cz), 0.315, 0.315, 10, RUST);
            }
            bb.setMat(.wood);
            if (!open) {
                bb.addBlob(v3(cx + tilt, h - 0.02, cz), v3(0.27, 0.035, 0.27), 3, 10, TIMBER_DK);
                return;
            }
            bb.addCylinder(v3(cx + tilt * 0.42, h * 0.42, cz), v3(cx + tilt, h + 0.006, cz), 0.235, 0.256, 10, BARK_OLD);
            bb.addBlob(v3(cx + tilt * 0.42, h * 0.42, cz), v3(0.235, 0.025, 0.235), 3, 10, BARK_OLD);
            bb.setMat(.steel);
            bb.addCylinder(v3(cx + tilt, h - 0.045, cz), v3(cx + tilt, h + 0.012, cz), 0.305, 0.305, 10, RUST);
        }
    }.go;
    barrel(&b, &rng, 0, 0, 0.02, 0.82, false);
    barrel(&b, &rng, 0.62, 0.28, -0.04, 0.76, true);
    barrel(&b, &rng, -0.35, 0.66, 0.05, 0.70, true);
    b.setMat(.wood);
    b.addCube(v3(-0.75, 0.25, -0.45), v3(0.56, 0.48, 0.52), BARK_OLD);
    for ([_]f32{ -1, 1 }) |sx| {
        for ([_]f32{ -1, 1 }) |sz| {
            b.addCube(v3(-0.75 + sx * 0.29, 0.27 + rng.signed() * 0.015, -0.45 + sz * 0.27), v3(0.06, 0.54, 0.06), TIMBER_DK);
        }
    }
    var p: i32 = 0;
    while (p < 3) : (p += 1) {
        const y = 0.11 + @as(f32, @floatFromInt(p)) * 0.16 + rng.signed() * 0.012;
        if (p == 1 and rng.float() < 0.6) {
            b.addBox(v3(-0.75, y, -0.76), v3(0.31, 0.02, 0.03), v3(0.02, 0.06, 0.015), v3(0.01, 0, 0.024), TIMBER);
        } else {
            b.addCube(v3(-0.75 + rng.signed() * 0.01, y, -0.76), v3(0.62, 0.115, 0.045), if (@mod(p, 2) == 0) TIMBER else TIMBER_DK);
        }
        b.addCube(v3(-0.44, y + rng.signed() * 0.01, -0.45), v3(0.045, 0.115, 0.56), if (@mod(p, 2) == 0) TIMBER_DK else TIMBER);
    }
    b.addBox(v3(-0.72, 0.545, -0.42), v3(0.33, 0.015, 0.03), v3(0.02, 0.035, 0), v3(-0.05, 0, 0.31), TIMBER);
    b.addBox(v3(0.55, 0.10, -0.72), v3(0.34, 0.06, 0), v3(0, 0.05, 0), v3(0, 0, 0.28), TIMBER);
    b.setMat(.cloth);
    b.addBlob(v3(-0.20, 0.15, -0.92), v3(0.27, 0.16, 0.21), 5, 9, THATCH_DK);
    b.addBlob(v3(-0.06, 0.10, -0.76), v3(0.18, 0.11, 0.15), 4, 8, THATCH_DK);
    b.addCapsule(v3(-0.36, 0.22, -1.05), v3(-0.46, 0.10, -1.13), 0.065, 0.035, 5, THATCH_DK);
    b.setMat(.leather);
    b.addCapsule(v3(-0.39, 0.195, -1.07), v3(-0.42, 0.165, -1.10), 0.056, 0.056, 5, BARK_DK);
    b.setMat(.plant);
    b.addBlob(v3(-0.52, 0.022, -1.18), v3(0.10, 0.024, 0.085), 3, 6, THATCH);
    b.addBlob(v3(-0.61, 0.018, -1.26), v3(0.055, 0.018, 0.05), 3, 5, THATCH);
    b.addBlob(v3(-0.44, 0.016, -1.24), v3(0.04, 0.014, 0.045), 3, 5, THATCH);
    tuftInto(&b, &rng, rng.signed() * 1.1, rng.signed() * 1.1, 0.7);
    return b.toModel(shader);
}

pub fn woodpileMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2106);
    b.setMat(.wood);
    var c: i32 = 0;
    while (c < 5) : (c += 1) {
        const y = 0.11 + @as(f32, @floatFromInt(c)) * 0.21;
        const halfW = 1.15 - @as(f32, @floatFromInt(c)) * 0.10;
        var z: f32 = -halfW;
        while (z < halfW) {
            const d = rng.range(0.17, 0.24);
            if (rng.float() > 0.10) {
                const x1 = 0.55 + rng.signed() * 0.15;
                b.addCapsule(v3(-0.55 + rng.signed() * 0.15, y, z), v3(x1, y + rng.signed() * 0.03, z), d * 0.5, d * 0.5, 5, if (rng.float() < 0.35) BARK_DK else if (rng.float() < 0.6) TIMBER else TIMBER_DK);
                if (rng.float() < 0.35) b.addBlob(v3(x1 + 0.01, y, z), v3(0.025, d * 0.36, d * 0.36), 3, 6, THATCH);
            }
            z += d;
        }
    }
    var f: i32 = 0;
    while (f < 4) : (f += 1) {
        const a = rng.angle();
        const d = rng.range(1.2, 1.9);
        b.addCapsule(v3(mathx.cosf(a) * d, 0.10, mathx.sinf(a) * d), v3(mathx.cosf(a) * d + rng.signed() * 0.5, 0.10, mathx.sinf(a) * d + rng.signed() * 0.5), 0.095, 0.085, 5, TIMBER_DK);
    }
    b.setMat(.cloth);
    b.addBlob(v3(-0.12, 1.08, 0.06), v3(0.68, 0.09, 0.62), 4, 9, THATCH_DK);
    b.addBlob(v3(0.30, 1.05, -0.14), v3(0.44, 0.07, 0.40), 4, 9, THATCH_DK);
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 1.4, rng.signed() * 1.4, 0.75);
    return b.toModel(shader);
}

pub fn bonesMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2107);
    b.setMat(.plain);
    b.addBlob(v3(0, 0.14, 0), v3(0.16, 0.15, 0.19), 4, 7, BONE);
    b.addBlob(v3(0, 0.09, -0.17), v3(0.11, 0.07, 0.09), 3, 6, BONE);
    b.addBlob(v3(0.14, 0.05, -0.22), v3(0.09, 0.04, 0.10), 3, 5, BONE);
    var r: i32 = 0;
    while (r < 6) : (r += 1) {
        const z = 0.34 + @as(f32, @floatFromInt(r)) * 0.13;
        const sgn: f32 = if (@mod(r, 2) == 0) 1 else -1;
        const w = rng.range(0.18, 0.28);
        b.addCapsule(v3(0, 0.06, z), v3(sgn * w, 0.13, z + rng.signed() * 0.04), 0.022, 0.018, 4, BONE);
        b.addCapsule(v3(sgn * w, 0.13, z), v3(sgn * w * 1.35, 0.05, z + rng.signed() * 0.06), 0.018, 0.014, 4, BONE);
    }
    b.addCapsule(v3(0, 0.05, 0.28), v3(0, 0.05, 1.12), 0.035, 0.028, 5, BONE);
    var l: i32 = 0;
    while (l < 4) : (l += 1) {
        const a = rng.angle();
        const d = rng.range(0.3, 1.0);
        const len = rng.range(0.25, 0.45);
        b.addCapsule(
            v3(mathx.cosf(a) * d, 0.045, mathx.sinf(a) * d + 0.5),
            v3(mathx.cosf(a) * d + mathx.cosf(a + 1.2) * len, 0.05, mathx.sinf(a) * d + 0.5 + mathx.sinf(a + 1.2) * len),
            0.03,
            0.036,
            5,
            BONE,
        );
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 0.9, 0.5 + rng.signed() * 0.9, 0.7);
    return b.toModel(shader);
}

pub fn sarcophagusMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2108);
    b.setMat(.stone);
    b.addCube(v3(0, 0.10, 0), v3(2.1, 0.20, 1.05), STONE_DK);
    b.addCube(v3(0, 0.52, 0.44), v3(1.9, 0.64, 0.16), STONE);
    b.addCube(v3(0, 0.52, -0.44), v3(1.9, 0.64, 0.16), STONE);
    b.addCube(v3(0.87, 0.52, 0), v3(0.16, 0.64, 0.75), STONE);
    b.addCube(v3(-0.87, 0.52, 0), v3(0.16, 0.64, 0.75), STONE);
    b.addCube(v3(0, 0.36, 0), v3(1.6, 0.34, 0.6), MORTAR);
    b.addCube(v3(0, 0.245, 0), v3(1.98, 0.09, 1.13), STONE_DK);
    b.addCube(v3(0.10, 0.80, 0), v3(1.80, 0.075, 1.11), STONE);
    for ([_]f32{ -1, 1 }) |sz| {
        b.addCube(v3(-0.08, 0.50, sz * 0.525), v3(1.35, 0.34, 0.045), STONE_LT);
        b.addCube(v3(-0.08, 0.50, sz * 0.5365), v3(1.05, 0.22, 0.03), STONE_DK);
    }
    b.setMat(.marble);
    b.addBox(v3(-0.35, 0.92, 0.30), v3(1.0, 0.10, 0), v3(-0.04, 0.11, 0), v3(0, 0, 0.5), MARBLE);
    b.addBox(v3(1.35, 0.30, 0.5), v3(0.55, 0.42, 0), v3(0.16, 0.20, 0), v3(0, 0, 0.42), MARBLE_DK);
    b.addBlob(v3(-0.55, 1.09, 0.28), v3(0.24, 0.12, 0.20), 4, 8, MARBLE_LT);
    b.addCapsule(v3(-0.45, 1.09, 0.29), v3(0.30, 1.01, 0.335), 0.175, 0.125, 8, MARBLE);
    b.addBlob(v3(-0.02, 1.13, 0.30), v3(0.10, 0.055, 0.09), 3, 6, MARBLE_LT);
    b.addBlob(v3(0.38, 1.02, 0.34), v3(0.09, 0.06, 0.11), 3, 6, MARBLE_DK);
    b.setMat(.stone);
    b.addBox(v3(-0.30, 0.995, 0.62), v3(0.62, 0.055, 0), v3(0, 0.018, 0), v3(0, 0, 0.09), STONE_MOSS);
    b.setMat(.plant);
    b.addBlob(v3(0.10 + rng.signed() * 0.3, 1.055, 0.70), v3(0.26, 0.035, 0.13), 3, 6, MOSS_SOFT);
    tuftInto(&b, &rng, rng.range(-1.6, 1.6), rng.signed() * 1.0, 0.8);
    return b.toModel(shader);
}

pub fn stairsMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2109);
    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 6) : (i += 1) {
        const t = @as(f32, @floatFromInt(i));
        const y = 0.14 + t * 0.24;
        const x = -1.1 + t * 0.42;
        const w = 1.5 - t * 0.10;
        if (i == 5 and rng.float() < 0.5) continue;
        b.addBox(
            v3(x, y, rng.signed() * 0.03),
            v3(0.28, rng.signed() * 0.012, 0),
            v3(0, 0.12, 0),
            v3(0, 0, w * 0.5),
            if (rng.float() < 0.28) STONE_LT else if (rng.float() < 0.5) STONE_MOSS else STONE,
        );
    }
    b.addCube(v3(-0.2, 0.55, 0.86), v3(2.6, 1.1, 0.34), STONE_DK);
    b.addCube(v3(0.9, 1.25, 0.86), v3(0.7, 0.4, 0.30), STONE);
    var d: i32 = 0;
    while (d < 5) : (d += 1) {
        const r = rng.range(0.14, 0.30);
        b.addBlob(v3(rng.range(-1.6, 1.6), r * 0.6, rng.range(-1.2, 0.4)), v3(r, r * 0.7, r), 3, 5, STONE_DK);
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.range(-1.3, 1.3), rng.range(-0.8, 0.4), 0.8);
    b.addBlob(v3(rng.range(-1.0, 1.0), 0.30, 0.5), v3(0.3, 0.08, 0.2), 3, 5, MOSS_SOFT);
    return b.toModel(shader);
}

pub fn gibbetMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2110);
    b.setMat(.stone);
    b.addBlob(v3(0, 0.14, 0), v3(0.44, 0.15, 0.40), 3, 6, STONE_DK);
    b.setMat(.wood);
    const lean = rng.signed() * 0.22;
    b.addCapsule(v3(0, 0.05, 0), v3(lean, 3.85, lean * 0.4), 0.115, 0.085, 6, TIMBER_DK);
    b.addCapsule(v3(lean, 3.78, lean * 0.4), v3(lean + 1.05, 3.92, lean * 0.4), 0.075, 0.055, 5, TIMBER_DK);
    b.addCapsule(v3(lean + 0.1, 3.30, lean * 0.4), v3(lean + 0.62, 3.86, lean * 0.4), 0.05, 0.04, 4, TIMBER_DK);
    b.setMat(.steel);
    var k: i32 = 0;
    while (k < 4) : (k += 1) {
        const y = 3.86 - @as(f32, @floatFromInt(k)) * 0.11;
        b.addCylinder(v3(lean + 1.0, y, 0), v3(lean + 1.0, y - 0.09, 0), 0.035, 0.035, 5, IRON);
    }
    const cx = lean + 1.0;
    const top: f32 = 3.42;
    var u: i32 = 0;
    while (u < 6) : (u += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(u)) / 6.0;
        const bar = if (rng.float() < 0.25) RUST else IRON;
        b.addCapsule(v3(cx + mathx.cosf(a) * 0.08, top, mathx.sinf(a) * 0.08), v3(cx + mathx.cosf(a) * 0.30, top - 0.55, mathx.sinf(a) * 0.30), 0.022, 0.026, 4, bar);
        b.addCapsule(v3(cx + mathx.cosf(a) * 0.30, top - 0.55, mathx.sinf(a) * 0.30), v3(cx + mathx.cosf(a) * 0.20, top - 1.25, mathx.sinf(a) * 0.20), 0.026, 0.022, 4, bar);
    }
    for ([_]f32{ 0.0, -0.55, -1.25 }) |dy| {
        const rr: f32 = if (dy < -0.3) 0.26 else 0.20;
        b.addCylinder(v3(cx, top + dy, 0), v3(cx, top + dy + 0.04, 0), rr, rr, 8, if (dy < -1.0) RUST else IRON);
    }
    b.addCylinder(v3(cx, top - 1.28, 0), v3(cx, top - 1.22, 0), 0.20, 0.20, 8, IRON);
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 0.8, rng.signed() * 0.8, 0.8);
    return b.toModel(shader);
}


pub const CHEST_HALF_X: f32 = 0.52;
pub const CHEST_HALF_Z: f32 = 0.34;
pub const CHEST_FOOT_H: f32 = 0.09;
pub const CHEST_BODY_H: f32 = 0.52;
pub const CHEST_HINGE_Y: f32 = CHEST_FOOT_H + CHEST_BODY_H;
pub const CHEST_HINGE_Z: f32 = -CHEST_HALF_Z;
pub const CHEST_LID_R: f32 = CHEST_HALF_Z * 0.84;
const CHEST_LID_SLAB: f32 = 0.10;
const CHEST_INSIDE = mathx.rgba(9, 7, 5, 255);
const CHEST_RELIEF_PROUD: f32 = 0.065;
pub const CHEST_TOP: f32 = CHEST_HINGE_Y + CHEST_LID_SLAB + CHEST_LID_R + CHEST_RELIEF_PROUD;

pub fn chestMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2112);
    b.setMat(.wood);
    const hx = CHEST_HALF_X;
    const hz = CHEST_HALF_Z;
    for ([_]f32{ -1, 1 }) |sx| {
        for ([_]f32{ -1, 1 }) |sz| {
            b.addCube(v3(sx * (hx - 0.07), CHEST_FOOT_H * 0.5, sz * (hz - 0.06)), v3(0.13, CHEST_FOOT_H, 0.12), TIMBER_DK);
        }
    }
    const mid = CHEST_FOOT_H + CHEST_BODY_H * 0.5;
    const wall = 0.075;
    const inX = hx - 0.015;
    const inZ = hz - 0.015;
    for ([_]f32{ -1, 1 }) |sz| {
        b.addCube(v3(0, mid, sz * (inZ - wall * 0.5)), v3(inX * 2.0, CHEST_BODY_H, wall), TIMBER_DK);
    }
    for ([_]f32{ -1, 1 }) |sx2| {
        b.addCube(v3(sx2 * (inX - wall * 0.5), mid, 0), v3(wall, CHEST_BODY_H, inZ * 2.0), TIMBER_DK);
    }
    b.addCube(v3(0, CHEST_FOOT_H + 0.055, 0), v3(inX * 2.0, 0.11, inZ * 2.0), CHEST_INSIDE);
    var x = -hx + 0.04;
    while (x < hx - 0.06) {
        const w = @min(rng.range(0.13, 0.22), hx - 0.04 - x);
        const cx = x + w * 0.5;
        for ([_]f32{ -1, 1 }) |sz| {
            b.addCube(v3(cx, CHEST_FOOT_H + CHEST_BODY_H * 0.5, sz * hz), v3(w - 0.012, CHEST_BODY_H - 0.05, 0.03), if (rng.float() < 0.4) TIMBER else TIMBER_DK);
        }
        x += w;
    }
    b.setMat(.steel);
    for ([_]f32{ 0.30, 0.72 }) |f| {
        const y = CHEST_FOOT_H + CHEST_BODY_H * f;
        b.addCube(v3(0, y, 0), v3(hx * 2.0 + 0.02, 0.055, hz * 2.0 + 0.02), if (rng.float() < 0.35) RUST else IRON);
    }
    b.addCube(v3(0, CHEST_HINGE_Y - 0.06, hz + 0.012), v3(0.20, 0.19, 0.035), IRON);
    b.addCylinder(v3(0, CHEST_HINGE_Y - 0.10, hz + 0.035), v3(0, CHEST_HINGE_Y - 0.10, hz + 0.075), 0.035, 0.030, 7, RUST);
    b.addDome(v3(0, CHEST_HINGE_Y - 0.10, hz + 0.075), v3(0, 0, 1), 0.035, 7, RUST);
    return b.toModel(shader);
}

const CHEST_GLOW_EMISSIVE: u8 = 26;
const CHEST_GLOW = mathx.rgba(226, 170, 78, CHEST_GLOW_EMISSIVE);
const CHEST_GLOW_HOT = mathx.rgba(244, 216, 152, CHEST_GLOW_EMISSIVE);
/// How far the seam plate stands PROUD of the carcase's outer face — the iron bands' own 0.010.
const CHEST_SEAM_PROUD: f32 = 0.010;
const CHEST_SEAM_H: f32 = 0.034;

pub fn chestGlowMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    const hx = CHEST_HALF_X + CHEST_SEAM_PROUD;
    const hz = CHEST_HALF_Z + CHEST_SEAM_PROUD;
    b.setMat(.plain);
    b.addCube(v3(0, CHEST_HINGE_Y, 0), v3(hx * 2.0, CHEST_SEAM_H, hz * 2.0), CHEST_GLOW);
    const inX = CHEST_HALF_X - 0.09;
    const inZ = CHEST_HALF_Z - 0.09;
    b.addBlob(v3(0, CHEST_HINGE_Y - 0.13, 0), v3(inX, 0.10, inZ), 3, 8, CHEST_GLOW_HOT);
    return b.toModel(shader);
}

pub fn chestLidMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2113);
    b.setMat(.wood);
    const hx = CHEST_HALF_X;
    const d = CHEST_HALF_Z * 2.0;
    const axis = CHEST_LID_SLAB;
    const R = CHEST_LID_R;
    b.addCube(v3(0, axis * 0.5, d * 0.5), v3(hx * 2.0 - 0.02, axis, d - 0.02), TIMBER_DK);
    const ex = hx - 0.01;
    barrelHalf(&b, ex, axis, d * 0.5, R, TIMBER_DK);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const a = -0.9 + @as(f32, @floatFromInt(i)) * 0.45 + rng.signed() * 0.06;
        const r = R * 1.024;
        b.addCube(
            v3(0, axis + mathx.cosf(a) * r, d * 0.5 + mathx.sinf(a) * r),
            v3(hx * 2.0 - 0.06, 0.028, d * rng.range(0.16, 0.26)),
            if (rng.float() < 0.4) TIMBER else TIMBER_DK,
        );
    }
    b.setMat(.steel);
    for ([_]f32{ -1, 1 }) |sx| {
        const bx = sx * (hx - 0.15);
        var seg: i32 = 0;
        while (seg < 5) : (seg += 1) {
            const a = -1.15 + @as(f32, @floatFromInt(seg)) * 0.575;
            const r = R * 1.036;
            b.addCube(v3(bx, axis + mathx.cosf(a) * r, d * 0.5 + mathx.sinf(a) * r), v3(0.10, 0.052, d * 0.24), if (rng.float() < 0.35) RUST else IRON);
        }
    }
    b.addCube(v3(0, axis * 0.62, d - 0.010), v3(0.17, 0.13, 0.045), IRON);
    b.addCube(v3(0, axis * 0.30, d - 0.055), v3(0.13, 0.055, 0.10), RUST);
    b.setMat(.wood);
    var u: i32 = 0;
    while (u < 6) : (u += 1) {
        const z = d * 0.5 + (@as(f32, @floatFromInt(u)) - 2.5) * (R * 2.0 / 6.0);
        b.addCube(v3(0, -0.015, z), v3(hx * 2.0 - 0.05, 0.030, R * 2.0 / 6.0 - 0.012), CHEST_INSIDE);
    }
    for ([_]f32{ -1, 1 }) |sx| {
        b.addCube(v3(sx * (hx * 0.56), -0.055, d * 0.5), v3(0.12, 0.055, d * 0.66), TIMBER);
    }
    return b.toModel(shader);
}

fn barrelHalf(b: *Builder, ex: f32, axis: f32, cz: f32, r: f32, col: rl.Color) void {
    const SEGS = 9;
    const at = struct {
        fn p(x: f32, ax: f32, z: f32, rr: f32, a: f32) rl.Vector3 {
            return v3(x, ax + mathx.cosf(a) * rr, z + mathx.sinf(a) * rr);
        }
    }.p;
    var i: i32 = 0;
    while (i < SEGS) : (i += 1) {
        const a0 = -std.math.pi * 0.5 + std.math.pi * @as(f32, @floatFromInt(i)) / SEGS;
        const a1 = -std.math.pi * 0.5 + std.math.pi * @as(f32, @floatFromInt(i + 1)) / SEGS;
        const n = v3(0, mathx.cosf((a0 + a1) * 0.5), mathx.sinf((a0 + a1) * 0.5));
        b.quad(at(-ex, axis, cz, r, a0), at(-ex, axis, cz, r, a1), at(ex, axis, cz, r, a1), at(ex, axis, cz, r, a0), n, col);
        const c0 = v3(0, axis, cz + mathx.sinf(a0) * r);
        const c1 = v3(0, axis, cz + mathx.sinf(a1) * r);
        b.quad(v3(ex, c0.y, c0.z), at(ex, axis, cz, r, a0), at(ex, axis, cz, r, a1), v3(ex, c1.y, c1.z), v3(1, 0, 0), col);
        b.quad(v3(-ex, c1.y, c1.z), at(-ex, axis, cz, r, a1), at(-ex, axis, cz, r, a0), v3(-ex, c0.y, c0.z), v3(-1, 0, 0), col);
    }
}
