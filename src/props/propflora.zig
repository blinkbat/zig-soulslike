const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const art = @import("propart.zig");

const v3 = mathx.v3;
const Builder = gfx.Builder;
const BARK = art.BARK;
const BARK_DK = art.BARK_DK;
const BERRY = art.BERRY;
const BRACKEN_BRN = art.BRACKEN_BRN;
const CAP_BROWN = art.CAP_BROWN;
const CAP_PALE = art.CAP_PALE;
const CLOVER_GRN = art.CLOVER_GRN;
const GORSE_GOLD = art.GORSE_GOLD;
const GRASS_DRY = art.GRASS_DRY;
const GRASS_GOLD = art.GRASS_GOLD;
const GRASS_GRN = art.GRASS_GRN;
const IVY_GRN = art.IVY_GRN;
const LEAF = art.LEAF;
const LEAF_DAMP = art.LEAF_DAMP;
const LEAF_DK = art.LEAF_DK;
const LEAF_GOLD = art.LEAF_GOLD;
const LEAF_LT = art.LEAF_LT;
const LILY_GRN = art.LILY_GRN;
const MOSS_DK = art.MOSS_DK;
const MOSS_SOFT = art.MOSS_SOFT;
const NETTLE = art.NETTLE;
const PETAL = art.PETAL;
const PETAL_BLUE = art.PETAL_BLUE;
const PETAL_GLOW = art.PETAL_GLOW;
const PETAL_WHITE = art.PETAL_WHITE;
const PURPLE = art.PURPLE;
const PURPLE_DK = art.PURPLE_DK;
const SCRUB = art.SCRUB;
const SCRUB_DK = art.SCRUB_DK;
const SEED = art.SEED;
const STEM = art.STEM;
const blade = art.blade;
const bladeColor = art.bladeColor;
const tuftInto = art.tuftInto;


pub fn tuftMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plant);
    var rng = mathx.Rng.init(11);
    tuftInto(&b, &rng, 0, 0, 1.0);
    return b.toModel(shader);
}

pub fn patchMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plant);
    var rng = mathx.Rng.init(23);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.2, 1.25);
        tuftInto(&b, &rng, mathx.cosf(a) * d, mathx.sinf(a) * d, rng.range(0.7, 1.1));
    }
    return b.toModel(shader);
}

pub fn shrubMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plant);
    var rng = mathx.Rng.init(37);
    var i: i32 = 0;
    while (i < 14) : (i += 1) {
        const a = rng.angle();
        const rr = rng.range(0.0, 0.36);
        const x = mathx.cosf(a) * rr;
        const z = mathx.sinf(a) * rr;
        const base = rng.range(0.02, 0.14);
        const lobeR = rng.range(0.11, 0.20) * (1.0 - 0.5 * rr / 0.36);
        const top = base + lobeR * rng.range(1.5, 2.4) * (1.0 - 0.4 * rr / 0.36);
        const col = if (rng.float() < 0.5) SCRUB else SCRUB_DK;
        b.addCapsule(v3(x, base, z), v3(x + rng.signed() * 0.05, top, z + rng.signed() * 0.05), lobeR, lobeR * 0.45, 6, col);
    }
    var f: i32 = 0;
    while (f < 8) : (f += 1) {
        const a = rng.angle();
        const d = rng.range(0.18, 0.42);
        const r = rng.range(0.055, 0.10);
        b.addBlob(v3(mathx.cosf(a) * d, rng.range(0.12, 0.44) * (1.0 - 0.5 * d / 0.42), mathx.sinf(a) * d), v3(r, r * 0.7, r * 1.1), 3, 6, if (rng.float() < 0.5) SCRUB_DK else SCRUB);
    }
    b.addCylinder(v3(0.06, 0.0, 0.03), v3(0.20, 0.54, 0.12), 0.018, 0.004, 4, BARK_DK);
    b.addCylinder(v3(-0.05, 0.0, -0.02), v3(-0.24, 0.48, -0.20), 0.018, 0.004, 4, BARK_DK);
    tuftInto(&b, &rng, 0.30, -0.30, 0.7);
    return b.toModel(shader);
}

pub fn flowersMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plant);
    var rng = mathx.Rng.init(53);
    tuftInto(&b, &rng, 0, 0, 0.8);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.05, 0.30);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const h = rng.range(0.26, 0.44);
        b.addCylinder(v3(x, 0, z), v3(x, h, z), 0.009, 0.005, 4, STEM);
        b.addCube(v3(x, h + 0.02, z), v3(0.07, 0.05, 0.07), PETAL);
    }
    return b.toModel(shader);
}

pub fn reedsMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plant);
    var rng = mathx.Rng.init(71);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.03, 0.22);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const la = rng.angle();
        const lean = rng.range(0.05, 0.16);
        const h = rng.range(0.75, 1.25);
        const lx = mathx.cosf(la) * lean;
        const lz = mathx.sinf(la) * lean;
        blade(&b, x, z, h, lx, lz, 0.016, if (rng.float() < 0.7) GRASS_DRY else GRASS_GOLD);
        b.addCube(v3(x + lx, h + 0.03, z + lz), v3(0.038, 0.13, 0.038), SEED);
    }
    return b.toModel(shader);
}

pub fn glowMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plant);
    var rng = mathx.Rng.init(89);
    tuftInto(&b, &rng, 0, 0, 0.75);
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.06, 0.2);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const h = rng.range(0.32, 0.5);
        b.addCylinder(v3(x, 0, z), v3(x, h, z), 0.008, 0.005, 4, STEM);
        b.addCube(v3(x, h + 0.025, z), v3(0.05, 0.04, 0.05), PETAL_GLOW);
    }
    return b.toModel(shader);
}

pub fn bushMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(6161);
    b.setMat(.wood);
    var s: i32 = 0;
    while (s < 4) : (s += 1) {
        const a = rng.angle();
        b.addCapsule(v3(0, 0.0, 0), v3(mathx.cosf(a) * 0.28, rng.range(0.35, 0.6), mathx.sinf(a) * 0.28), 0.045, 0.025, 5, BARK_DK);
    }
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 16) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.62);
        const t = d / 0.62;
        const r = rng.range(0.20, 0.34) * (1.0 - 0.30 * t);
        const y = rng.range(0.30, 0.88) * (1.0 - 0.30 * t);
        const col = if (i == 0 or rng.float() < 0.22) LEAF_GOLD else if (rng.float() < 0.5) LEAF else LEAF_DK;
        b.addBlob(v3(mathx.cosf(a) * d, y, mathx.sinf(a) * d), v3(r, r * rng.range(0.62, 0.9), r * rng.range(0.85, 1.15)), 4, 7, col);
    }
    var f: i32 = 0;
    while (f < 10) : (f += 1) {
        const a = rng.angle();
        const d = rng.range(0.32, 0.60);
        const r = rng.range(0.07, 0.13);
        const y = rng.range(0.20, 0.74) * (1.0 - 0.30 * d / 0.62);
        const col = if (rng.float() < 0.16) LEAF_GOLD else if (rng.float() < 0.55) LEAF_DK else LEAF;
        b.addBlob(v3(mathx.cosf(a) * d, y, mathx.sinf(a) * d), v3(r, r * 0.7, r * 1.1), 3, 6, col);
    }
    tuftInto(&b, &rng, rng.signed() * 0.55, rng.signed() * 0.55, 0.7);
    return b.toModel(shader);
}

pub fn brambleMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(6262);
    b.setMat(.wood);
    var i: i32 = 0;
    while (i < 10) : (i += 1) {
        const a = rng.angle();
        const d0 = rng.range(0.0, 0.45);
        const x0 = mathx.cosf(a) * d0;
        const z0 = mathx.sinf(a) * d0;
        const arc = rng.range(0.5, 0.95);
        const b2 = a + rng.signed() * 1.5;
        const apex = v3(x0 + mathx.cosf(b2) * arc * 0.5, rng.range(0.24, 0.46), z0 + mathx.sinf(b2) * arc * 0.5);
        b.addCapsule(v3(x0, 0.02, z0), apex, 0.030, 0.024, 4, BARK_DK);
        b.addCapsule(apex, v3(x0 + mathx.cosf(b2) * arc, 0.03, z0 + mathx.sinf(b2) * arc), 0.024, 0.016, 4, BARK_DK);
    }
    b.setMat(.plant);
    var l: i32 = 0;
    while (l < 44) : (l += 1) {
        const a = rng.angle();
        const d = rng.range(0.05, 0.95);
        const r = rng.range(0.065, 0.125);
        b.addBlob(v3(mathx.cosf(a) * d, rng.range(0.06, 0.42), mathx.sinf(a) * d), v3(r, r * 0.8, r * 1.1), 3, 6, if (rng.float() < 0.6) LEAF_DK else LEAF);
    }
    var be: i32 = 0;
    while (be < 6) : (be += 1) {
        const a = rng.angle();
        const d = rng.range(0.2, 0.8);
        b.addBlob(v3(mathx.cosf(a) * d, rng.range(0.18, 0.48), mathx.sinf(a) * d), v3(0.028, 0.028, 0.028), 3, 5, BERRY);
    }
    return b.toModel(shader);
}

pub fn fernMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(6363);
    b.setMat(.plant);
    var f: i32 = 0;
    while (f < 7) : (f += 1) {
        const a = rng.angle();
        const reach = rng.range(0.45, 0.78);
        const rise = rng.range(0.42, 0.72);
        const ux = mathx.cosf(a);
        const uz = mathx.sinf(a);
        const tip = v3(ux * reach, rise * 0.72, uz * reach);
        b.addCylinder(v3(0, 0.03, 0), tip, 0.020, 0.005, 4, STEM);
        const nl: i32 = 5 + rng.intn(3);
        var l: i32 = 0;
        while (l < nl) : (l += 1) {
            const t = (@as(f32, @floatFromInt(l)) + 1.0) / (@as(f32, @floatFromInt(nl)) + 1.0);
            const y = 0.03 + rise * @sqrt(t) * 0.72;
            const px = ux * reach * t;
            const pz = uz * reach * t;
            const leafLen = rng.range(0.10, 0.19) * (1.0 - 0.55 * t);
            for ([_]f32{ -1, 1 }) |sgn| {
                b.addBlob(
                    v3(px - uz * sgn * leafLen, y + 0.035, pz + ux * sgn * leafLen),
                    v3(@abs(uz) * leafLen + 0.03, 0.055, @abs(ux) * leafLen + 0.03),
                    3,
                    5,
                    if (rng.float() < 0.35) GRASS_GRN else if (rng.float() < 0.6) LEAF_LT else SCRUB,
                );
            }
        }
    }
    tuftInto(&b, &rng, rng.signed() * 0.4, rng.signed() * 0.4, 0.55);
    return b.toModel(shader);
}


pub fn grassTallMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3001);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 22) : (i += 1) {
        const a = rng.angle();
        const rr = rng.range(0.0, 0.09);
        const x = mathx.cosf(a) * rr;
        const z = mathx.sinf(a) * rr;
        const la = rng.angle();
        const lean = rng.range(0.10, 0.42);
        const h = rng.range(0.55, 1.10);
        blade(&b, x, z, h, mathx.cosf(la) * lean, mathx.sinf(la) * lean, 0.020, if (rng.float() < 0.35) GRASS_GRN else bladeColor(&rng));
    }
    var s: i32 = 0;
    while (s < 3) : (s += 1) {
        const la = rng.angle();
        const lean = rng.range(0.05, 0.16);
        const h = rng.range(0.95, 1.18);
        blade(&b, 0, 0, h, mathx.cosf(la) * lean, mathx.sinf(la) * lean, 0.013, GRASS_DRY);
        b.addCube(v3(mathx.cosf(la) * lean, h, mathx.sinf(la) * lean), v3(0.032, 0.11, 0.032), SEED);
    }
    return b.toModel(shader);
}

pub fn cloverMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3002);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 20) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.72) * @sqrt(rng.float());
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const h = rng.range(0.05, 0.13);
        b.addCylinder(v3(x, 0, z), v3(x, h, z), 0.008, 0.006, 4, STEM);
        var l: i32 = 0;
        while (l < 3) : (l += 1) {
            const la = a + std.math.tau * @as(f32, @floatFromInt(l)) / 3.0 + rng.signed() * 0.3;
            const lr = rng.range(0.035, 0.058);
            b.addBlob(v3(x + mathx.cosf(la) * lr, h + 0.006, z + mathx.sinf(la) * lr), v3(lr, 0.010, lr), 3, 5, if (rng.float() < 0.4) CLOVER_GRN else LEAF_DAMP);
        }
    }
    var f: i32 = 0;
    while (f < 3) : (f += 1) {
        const a = rng.angle();
        const d = rng.range(0.1, 0.6);
        b.addBlob(v3(mathx.cosf(a) * d, 0.155, mathx.sinf(a) * d), v3(0.032, 0.030, 0.032), 3, 5, PETAL_WHITE);
    }
    return b.toModel(shader);
}

pub fn mossMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3003);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 9) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.85) * @sqrt(rng.float());
        const r = rng.range(0.22, 0.48) * (1.0 - 0.3 * d);
        b.addBlob(v3(mathx.cosf(a) * d, rng.range(0.02, 0.06), mathx.sinf(a) * d), v3(r, rng.range(0.035, 0.075), r * rng.range(0.8, 1.2)), 3, 6, if (rng.float() < 0.45) MOSS_DK else MOSS_SOFT);
    }
    var s: i32 = 0;
    while (s < 8) : (s += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.7);
        blade(&b, mathx.cosf(a) * d, mathx.sinf(a) * d, rng.range(0.06, 0.13), 0, 0, 0.008, MOSS_SOFT);
    }
    return b.toModel(shader);
}

pub fn mushroomsMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3004);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 8) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.34);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const h = rng.range(0.07, 0.28);
        const capR = rng.range(0.045, 0.135) * (0.5 + 0.6 * h / 0.28);
        b.addCylinder(v3(x, 0, z), v3(x + rng.signed() * 0.02, h, z + rng.signed() * 0.02), capR * 0.30, capR * 0.24, 5, CAP_PALE);
        b.addBlob(v3(x + rng.signed() * 0.02, h + capR * 0.22, z + rng.signed() * 0.02), v3(capR, capR * rng.range(0.42, 0.72), capR), 3, 6, if (rng.float() < 0.6) CAP_BROWN else CAP_PALE);
    }
    return b.toModel(shader);
}

pub fn nettlesMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3005);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 11) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.5);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const h = rng.range(0.45, 0.88);
        b.addCylinder(v3(x, 0, z), v3(x + rng.signed() * 0.07, h, z + rng.signed() * 0.07), 0.013, 0.008, 4, NETTLE);
        const pairs: i32 = 4 + rng.intn(3);
        var p: i32 = 0;
        while (p < pairs) : (p += 1) {
            const t = (@as(f32, @floatFromInt(p)) + 0.8) / (@as(f32, @floatFromInt(pairs)) + 0.4);
            const y = h * t;
            const la = a + rng.signed() * 0.8 + @as(f32, @floatFromInt(p)) * 1.1;
            const ll = rng.range(0.085, 0.145) * (1.0 - 0.35 * t);
            for ([_]f32{ -1, 1 }) |sgn| {
                b.addBlob(v3(x + mathx.cosf(la) * sgn * ll, y, z + mathx.sinf(la) * sgn * ll), v3(ll * 0.9, 0.032, ll * 0.72), 3, 6, if (rng.float() < 0.4) LEAF_DAMP else NETTLE);
            }
        }
    }
    return b.toModel(shader);
}

pub fn thistleMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3006);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.26);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const h = rng.range(0.55, 0.98);
        const tipX = x + rng.signed() * 0.09;
        const tipZ = z + rng.signed() * 0.09;
        b.addCylinder(v3(x, 0, z), v3(tipX, h, tipZ), 0.017, 0.011, 4, SCRUB);
        b.addBlob(v3(tipX, h + 0.03, tipZ), v3(0.038, 0.045, 0.038), 3, 6, SCRUB_DK);
        b.addBlob(v3(tipX, h + 0.095, tipZ), v3(0.040, 0.052, 0.040), 3, 6, if (rng.float() < 0.7) PURPLE else PURPLE_DK);
        var l: i32 = 0;
        while (l < 5) : (l += 1) {
            const la = rng.angle();
            const ll = rng.range(0.14, 0.28);
            const ty = rng.range(0.06, 0.16);
            b.addCylinder(v3(x, 0.03, z), v3(x + mathx.cosf(la) * ll, ty, z + mathx.sinf(la) * ll), 0.030, 0.006, 4, SCRUB);
            b.addBlob(v3(x + mathx.cosf(la) * ll * 0.55, ty * 0.6 + 0.02, z + mathx.sinf(la) * ll * 0.55), v3(ll * 0.34, 0.022, ll * 0.34), 3, 5, if (rng.float() < 0.5) SCRUB else SCRUB_DK);
        }
    }
    return b.toModel(shader);
}

pub fn foxgloveMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3007);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.22);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const h = rng.range(0.75, 1.22);
        const lean = rng.range(0.04, 0.14);
        const la = rng.angle();
        const lx = mathx.cosf(la) * lean;
        const lz = mathx.sinf(la) * lean;
        b.addCylinder(v3(x, 0, z), v3(x + lx, h, z + lz), 0.016, 0.009, 4, STEM);
        const nb: i32 = 5 + rng.intn(3);
        var f: i32 = 0;
        while (f < nb) : (f += 1) {
            const t = 0.42 + 0.55 * (@as(f32, @floatFromInt(f)) / @as(f32, @floatFromInt(nb)));
            const br = rng.range(0.030, 0.052) * (1.3 - 0.6 * t);
            const bx = x + lx * t + mathx.cosf(la) * 0.045;
            const bz = z + lz * t + mathx.sinf(la) * 0.045;
            b.addBlob(v3(bx, h * t, bz), v3(br, br * 1.35, br), 3, 6, if (rng.float() < 0.75) PURPLE else PURPLE_DK);
        }
        var lf: i32 = 0;
        while (lf < 3) : (lf += 1) {
            const bla = rng.angle();
            const ll = rng.range(0.09, 0.16);
            b.addBlob(v3(x + mathx.cosf(bla) * ll, rng.range(0.05, 0.18), z + mathx.sinf(bla) * ll), v3(ll * 0.8, 0.016, ll * 0.45), 3, 5, LEAF_DAMP);
        }
    }
    return b.toModel(shader);
}

pub fn heatherMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3008);
    b.setMat(.wood);
    var s: i32 = 0;
    while (s < 7) : (s += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.6);
        b.addCapsule(v3(0, 0.02, 0), v3(mathx.cosf(a) * d, rng.range(0.10, 0.22), mathx.sinf(a) * d), 0.018, 0.010, 4, BARK_DK);
    }
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 26) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.82) * @sqrt(rng.float());
        const r = rng.range(0.07, 0.15) * (1.0 - 0.25 * d);
        const y = rng.range(0.09, 0.34) * (1.0 - 0.35 * d);
        const col = if (rng.float() < 0.34) (if (rng.float() < 0.6) PURPLE else PURPLE_DK) else if (rng.float() < 0.5) SCRUB_DK else BRACKEN_BRN;
        b.addBlob(v3(mathx.cosf(a) * d, y, mathx.sinf(a) * d), v3(r, r * 0.7, r * rng.range(0.85, 1.15)), 3, 5, col);
    }
    return b.toModel(shader);
}

pub fn gorseMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3009);
    b.setMat(.wood);
    var s: i32 = 0;
    while (s < 16) : (s += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.5);
        const h = rng.range(0.35, 0.95) * (1.0 - 0.4 * d);
        b.addCylinder(v3(mathx.cosf(a) * d, 0.0, mathx.sinf(a) * d), v3(mathx.cosf(a) * d * 1.5, h, mathx.sinf(a) * d * 1.5), 0.022, 0.004, 4, SCRUB_DK);
    }
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 18) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.62);
        const r = rng.range(0.09, 0.17) * (1.0 - 0.25 * d);
        const y = rng.range(0.14, 0.78) * (1.0 - 0.3 * d);
        b.addBlob(v3(mathx.cosf(a) * d, y, mathx.sinf(a) * d), v3(r, r * 0.8, r), 3, 6, if (rng.float() < 0.42) GORSE_GOLD else if (rng.float() < 0.6) SCRUB else SCRUB_DK);
    }
    return b.toModel(shader);
}

pub fn cattailsMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3010);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 9) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.02, 0.30);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const la = rng.angle();
        const lean = rng.range(0.03, 0.13);
        const h = rng.range(0.9, 1.55);
        blade(&b, x, z, h, mathx.cosf(la) * lean, mathx.sinf(la) * lean, 0.022, if (rng.float() < 0.5) GRASS_GRN else GRASS_DRY);
        if (rng.float() < 0.55) {
            const sx = x + mathx.cosf(la) * lean * 0.6;
            const sz = z + mathx.sinf(la) * lean * 0.6;
            const sh = h * rng.range(0.85, 1.05);
            b.addCylinder(v3(x, 0, z), v3(sx, sh, sz), 0.014, 0.012, 4, STEM);
            b.addBlob(v3(sx, sh + 0.10, sz), v3(0.032, 0.115, 0.032), 3, 6, CAP_BROWN);
            b.addCylinder(v3(sx, sh + 0.21, sz), v3(sx, sh + 0.30, sz), 0.010, 0.003, 4, STEM);
        }
    }
    return b.toModel(shader);
}

pub fn lilypadsMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3011);
    b.setMat(.plant);
    const Y: f32 = 0.075; // just above the water sheet's own 0.055
    var i: i32 = 0;
    while (i < 16) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 1.7) * @sqrt(rng.float());
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const r = rng.range(0.30, 0.58);
        b.addBlob(v3(x, Y, z), v3(r, 0.016, r * rng.range(0.88, 1.1)), 3, 7, if (rng.float() < 0.35) LEAF_DAMP else LILY_GRN);
        if (rng.float() < 0.22) {
            b.addBlob(v3(x + rng.signed() * 0.08, Y + 0.055, z + rng.signed() * 0.08), v3(0.055, 0.045, 0.055), 3, 6, PETAL_WHITE);
            b.addBlob(v3(x + rng.signed() * 0.08, Y + 0.085, z + rng.signed() * 0.08), v3(0.028, 0.030, 0.028), 3, 5, PETAL);
        }
    }
    return b.toModel(shader);
}

pub fn brackenMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3012);
    b.setMat(.plant);
    var f: i32 = 0;
    while (f < 9) : (f += 1) {
        const a = rng.angle();
        const reach = rng.range(0.35, 0.85);
        const ux = mathx.cosf(a);
        const uz = mathx.sinf(a);
        const rise = rng.range(0.12, 0.36);
        b.addCylinder(v3(0, 0.03, 0), v3(ux * reach, rise, uz * reach), 0.018, 0.006, 4, BRACKEN_BRN);
        const nl: i32 = 4 + rng.intn(3);
        var l: i32 = 0;
        while (l < nl) : (l += 1) {
            const t = (@as(f32, @floatFromInt(l)) + 1.0) / (@as(f32, @floatFromInt(nl)) + 1.0);
            const y = 0.03 + rise * @sqrt(t) * 0.85;
            const ll = rng.range(0.06, 0.13) * (1.0 - 0.5 * t);
            for ([_]f32{ -1, 1 }) |sgn| {
                b.addBlob(v3(ux * reach * t - uz * sgn * ll, y, uz * reach * t + ux * sgn * ll), v3(@abs(uz) * ll + 0.022, 0.030, @abs(ux) * ll + 0.022), 3, 5, if (rng.float() < 0.6) BRACKEN_BRN else SCRUB_DK);
            }
        }
    }
    return b.toModel(shader);
}

pub fn thicketMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3013);
    b.setMat(.wood);
    var tips: [14][3]f32 = undefined;
    var s: i32 = 0;
    while (s < 14) : (s += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.7);
        const h = rng.range(0.7, 1.6);
        const x0 = mathx.cosf(a) * d;
        const z0 = mathx.sinf(a) * d;
        const kx = x0 + mathx.cosf(a) * rng.range(0.05, 0.3) + rng.signed() * 0.12;
        const kz = z0 + mathx.sinf(a) * rng.range(0.05, 0.3) + rng.signed() * 0.12;
        const ky = h * rng.range(0.6, 0.82);
        const col = if (rng.float() < 0.5) BARK_DK else BARK;
        b.addCapsule(v3(x0, 0.0, z0), v3(kx, ky, kz), rng.range(0.030, 0.055), rng.range(0.022, 0.038), 4, col);
        const tx = kx + mathx.cosf(a) * rng.range(0.12, 0.34) + rng.signed() * 0.10;
        const tz = kz + mathx.sinf(a) * rng.range(0.12, 0.34) + rng.signed() * 0.10;
        const ty = h * rng.range(0.94, 1.06);
        b.addCapsule(v3(kx, ky, kz), v3(tx, ty, tz), rng.range(0.022, 0.038), 0.012, 4, col);
        tips[@intCast(s)] = .{ tx, ty, tz };
    }
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 46) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 1.0) * @sqrt(rng.float());
        const low = i < 16;
        const r = rng.range(0.10, 0.21) * (1.0 - 0.25 * d);
        const y = if (low) rng.range(0.10, 0.55) else rng.range(0.35, 1.45) * (1.0 - 0.22 * d);
        // Gold is a HIGHLIGHT: at 15% it was a spatter of bright yellow plates across the mass.
        const col = if (rng.float() < 0.07) LEAF_GOLD else if (rng.float() < 0.12) BRACKEN_BRN else if (rng.float() < 0.5) LEAF_DK else if (rng.float() < 0.72) LEAF else LEAF_DAMP;
        b.addBlob(v3(mathx.cosf(a) * d, y, mathx.sinf(a) * d), v3(r, r * rng.range(0.78, 1.0), r * rng.range(0.9, 1.15)), 4, 7, col);
    }
    for (tips) |t| {
        if (rng.float() < 0.3) continue;
        const r = rng.range(0.075, 0.135);
        b.addBlob(v3(t[0], t[1], t[2]), v3(r, r * rng.range(0.8, 1.0), r * rng.range(0.9, 1.1)), 3, 6, if (rng.float() < 0.35) LEAF_DK else if (rng.float() < 0.7) LEAF else LEAF_DAMP);
    }
    tuftInto(&b, &rng, rng.signed() * 0.9, rng.signed() * 0.9, 0.85);
    return b.toModel(shader);
}

pub fn wildflowersMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3014);
    b.setMat(.plant);
    tuftInto(&b, &rng, 0, 0, 0.9);
    tuftInto(&b, &rng, rng.signed() * 0.5, rng.signed() * 0.5, 0.7);
    var i: i32 = 0;
    while (i < 16) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.05, 0.72);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const h = rng.range(0.22, 0.55);
        const lean = rng.range(0.0, 0.07);
        const la = rng.angle();
        const tx = x + mathx.cosf(la) * lean;
        const tz = z + mathx.sinf(la) * lean;
        b.addCylinder(v3(x, 0, z), v3(tx, h, tz), 0.009, 0.005, 4, STEM);
        const roll = rng.float();
        const col = if (roll < 0.38) PETAL_WHITE else if (roll < 0.62) PETAL_BLUE else if (roll < 0.82) PETAL else PURPLE;
        const pr = rng.range(0.024, 0.040);
        b.addBlob(v3(tx, h + 0.012, tz), v3(pr * 0.5, 0.012, pr * 0.5), 3, 5, SEED);
        var p: i32 = 0;
        while (p < 5) : (p += 1) {
            const pa = std.math.tau * @as(f32, @floatFromInt(p)) / 5.0 + rng.signed() * 0.2;
            b.addBlob(v3(tx + mathx.cosf(pa) * pr, h + 0.014, tz + mathx.sinf(pa) * pr), v3(pr * 0.72, 0.010, pr * 0.72), 3, 5, col);
        }
    }
    return b.toModel(shader);
}

pub fn ivyMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3015);
    b.setMat(.plant);
    var m: i32 = 0;
    while (m < 10) : (m += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.65);
        const r = rng.range(0.16, 0.32) * (1.0 - 0.25 * d);
        b.addBlob(v3(mathx.cosf(a) * d, rng.range(0.06, 0.30), mathx.sinf(a) * d), v3(r, r * 0.6, r), 3, 6, if (rng.float() < 0.5) IVY_GRN else LEAF_DK);
    }
    const face = rng.angle();
    var s: i32 = 0;
    while (s < 5) : (s += 1) {
        const x0 = mathx.cosf(face) * rng.range(0.1, 0.5) + rng.signed() * 0.2;
        const z0 = mathx.sinf(face) * rng.range(0.1, 0.5) + rng.signed() * 0.2;
        const h = rng.range(0.7, 1.85);
        b.addCylinder(v3(x0, 0.05, z0), v3(x0 + rng.signed() * 0.12, h, z0 + rng.signed() * 0.12), 0.016, 0.008, 4, BARK_DK);
        const nl: i32 = 4 + rng.intn(4);
        var l: i32 = 0;
        while (l < nl) : (l += 1) {
            const t = (@as(f32, @floatFromInt(l)) + 0.6) / @as(f32, @floatFromInt(nl));
            const la = rng.angle();
            const lr = rng.range(0.055, 0.10);
            b.addBlob(v3(x0 + mathx.cosf(la) * lr, h * t, z0 + mathx.sinf(la) * lr), v3(lr, 0.018, lr * 0.9), 3, 5, if (rng.float() < 0.4) LEAF_DK else IVY_GRN);
        }
    }
    return b.toModel(shader);
}

