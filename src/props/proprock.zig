const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const art = @import("propart.zig");

const v3 = mathx.v3;
const Builder = gfx.Builder;
const BARK_DK = art.BARK_DK;
const CLIFF_DK = art.CLIFF_DK;
const CLIFF_LT = art.CLIFF_LT;
const CLIFF_ROCK = art.CLIFF_ROCK;
const IVY_GRN = art.IVY_GRN;
const MORTAR = art.MORTAR;
const MOSS_DK = art.MOSS_DK;
const ROCK_DEEP = art.ROCK_DEEP;
const SCRUB_DK = art.SCRUB_DK;
const STONE_MOSS = art.STONE_MOSS;
const tuftInto = art.tuftInto;


pub const CliffKind = struct {
    H: f32,
    wLo: f32,
    wHi: f32,
    cleft: f32,
    blocky: f32,
    bands: i32,
    ivy: f32 = 0,
    broken: f32 = 0,
};

pub const CLIFF_ROUND = CliffKind{ .H = 13.5, .wLo = 2.9, .wHi = 5.0, .cleft = 0.55, .blocky = 0.15, .bands = 7 };
pub const CLIFF_BLOCKY = CliffKind{ .H = 12.2, .wLo = 2.4, .wHi = 4.2, .cleft = 1.15, .blocky = 0.85, .bands = 10 };
pub const CLIFF_RAGGED = CliffKind{ .H = 14.6, .wLo = 3.2, .wHi = 5.6, .cleft = 0.85, .blocky = 0.5, .bands = 8 };
pub const CLIFF_IVIED = CliffKind{ .H = 13.0, .wLo = 3.0, .wHi = 5.2, .cleft = 0.70, .blocky = 0.22, .bands = 8, .ivy = 1.0 };
pub const CLIFF_SHATTERED = CliffKind{ .H = 11.6, .wLo = 2.2, .wHi = 4.6, .cleft = 1.35, .blocky = 0.90, .bands = 5, .broken = 1.0 };
pub const CLIFF_OVERGROWN = CliffKind{ .H = 12.6, .wLo = 2.7, .wHi = 4.8, .cleft = 0.95, .blocky = 0.45, .bands = 7, .ivy = 0.8, .broken = 0.55 };
/// The painted faces (`env.cliffWall`) draw from the same six, so a face and the prop beside it are one geology.
pub const CLIFF_KINDS = [_]CliffKind{ CLIFF_ROUND, CLIFF_BLOCKY, CLIFF_RAGGED, CLIFF_IVIED, CLIFF_SHATTERED, CLIFF_OVERGROWN };

pub fn cliff1(shader: rl.Shader) rl.Model {
    return cliffMesh(shader, 90210, CLIFF_ROUND);
}
pub fn cliff2(shader: rl.Shader) rl.Model {
    return cliffMesh(shader, 90277, CLIFF_BLOCKY);
}
pub fn cliff3(shader: rl.Shader) rl.Model {
    return cliffMesh(shader, 90341, CLIFF_RAGGED);
}
pub fn cliff4(shader: rl.Shader) rl.Model {
    return cliffMesh(shader, 90407, CLIFF_IVIED);
}
pub fn cliff5(shader: rl.Shader) rl.Model {
    return cliffMesh(shader, 90473, CLIFF_SHATTERED);
}
pub fn cliff6(shader: rl.Shader) rl.Model {
    return cliffMesh(shader, 90539, CLIFF_OVERGROWN);
}

/// `cliff2`'s own face washed toward slate: near enough to pass at a glance, off enough to be found by someone who looks.
pub const ILLUSION_WASH = mathx.rgba(96, 104, 134, 255);
pub const ILLUSION_WASH_T: f32 = 0.36;
pub fn illusoryMesh(shader: rl.Shader) rl.Model {
    var b = cliffBuild(90277, CLIFF_BLOCKY);
    b.wash(ILLUSION_WASH, ILLUSION_WASH_T);
    return b.toModel(shader);
}

pub const CliffBody = struct { x: f32, y: f32, z: f32, rx: f32, ry: f32, rz: f32 };

pub fn cliffFaceZ(bs: []const CliffBody, x: f32, y: f32) ?f32 {
    var best: ?f32 = null;
    for (bs) |bd| {
        const ux = (x - bd.x) / bd.rx;
        const uy = (y - bd.y) / bd.ry;
        const q = 1.0 - ux * ux - uy * uy;
        if (q <= 0.04) continue;
        const z = bd.z - bd.rz * @sqrt(q);
        if (best == null or z < best.?) best = z;
    }
    return best;
}

pub fn cliffSeatZ(bs: []const CliffBody, x: f32, y: f32, halfW: f32, halfH: f32) ?f32 {
    var back = cliffFaceZ(bs, x, y) orelse return null;
    for ([_]f32{ -1, 0, 1 }) |dx| {
        for ([_]f32{ -1, 0, 1 }) |dy| {
            const z = cliffFaceZ(bs, x + dx * halfW, y + dy * halfH) orelse continue;
            if (z > back) back = z;
        }
    }
    return back;
}

/// THE CLIFF FACES A PAINTED WALL CAN WEAR. One row each; `env.cliffWall` picks one at random per stretch and sinks it half into the wall.
pub const CliffFace = struct { name: []const u8, seed: u64, kind: CliffKind };
pub const CLIFF_FACES = [_]CliffFace{
    .{ .name = "Rocky Cliff", .seed = 90210, .kind = CLIFF_ROUND },
    .{ .name = "Rocky Cliff II", .seed = 41077, .kind = CLIFF_ROUND },
    .{ .name = "Blocky Cliff", .seed = 4471, .kind = CLIFF_BLOCKY },
    .{ .name = "Ragged Cliff", .seed = 7331, .kind = CLIFF_RAGGED },
    .{ .name = "Shattered Cliff", .seed = 1999, .kind = CLIFF_SHATTERED },
    .{ .name = "Ivied Cliff", .seed = 6160, .kind = CLIFF_IVIED },
};

pub fn cliffMesh(shader: rl.Shader, seed: u64, k: CliffKind) rl.Model {
    var b = cliffBuild(seed, k);
    return b.toModel(shader);
}

/// The mesh before it is a model, so it can be stamped into a wall instead of drawn as a prop.
pub fn cliffBuild(seed: u64, k: CliffKind) Builder {
    const H = k.H;
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    var frng = mathx.Rng.init(seed ^ 0x5C1FF00D);
    b.setMat(.stone);
    const NM = 5;
    const Summit = struct { x: f32, z: f32, y: f32, rx: f32, rz: f32, ry: f32 };
    var top: [NM]Summit = undefined;
    var bodies: [NM * 2]CliffBody = undefined;
    var nbody: usize = 0;
    var m: i32 = 0;
    while (m < NM) : (m += 1) {
        const u = @as(f32, @floatFromInt(m)) / @as(f32, NM - 1);
        const cx = (u * 2.0 - 1.0) * 5.2;
        const hgt = H * (0.93 + 0.07 * mathx.sinf(u * std.math.pi)) * rng.range(0.88, 1.12);
        const rx = rng.range(k.wLo, k.wHi);
        const rz = rng.range(2.0, 3.4);
        const inOut = rng.signed() * k.cleft;
        const sides: i32 = @intFromFloat(@round(10.0 - 4.0 * k.blocky + rng.signed() * 1.4));
        const rings: i32 = @intFromFloat(@round(6.0 - 2.0 * k.blocky + rng.signed() * 0.8));
        const fz = inOut + rng.signed() * 0.4;
        b.addBlob(v3(cx, hgt * 0.34, fz), v3(rx, hgt * 0.42, rz), rings, sides, if (@mod(m, 2) == 0) CLIFF_ROCK else CLIFF_DK);
        bodies[nbody] = .{ .x = cx, .y = hgt * 0.34, .z = fz, .rx = rx, .ry = hgt * 0.42, .rz = rz };
        nbody += 1;
        const sx = cx + rng.signed() * 0.9;
        const sz = inOut * 0.7 + 0.5 + rng.signed() * 0.7;
        const sy = hgt * 0.78;
        const srx = rx * rng.range(0.62, 0.88);
        const sry = hgt * rng.range(0.26, 0.40);
        const srz = rz * rng.range(0.7, 0.95);
        b.addBlob(
            v3(sx, sy, sz),
            v3(srx, sry, srz),
            @max(rings - 1, 3),
            @max(sides - 1, 5),
            if (rng.float() < 0.3) CLIFF_LT else CLIFF_ROCK,
        );
        bodies[nbody] = .{ .x = sx, .y = sy, .z = sz, .rx = srx, .ry = sry, .rz = srz };
        nbody += 1;
        top[@intCast(m)] = .{ .x = sx, .z = sz, .y = sy + sry, .rx = srx, .rz = srz, .ry = sry };
    }
    const face = bodies[0..nbody];
    var course: i32 = 0;
    while (course < k.bands) : (course += 1) {
        const t = @as(f32, @floatFromInt(course)) / @as(f32, @floatFromInt(k.bands - 1));
        const y = H * (0.07 + 0.86 * t) * rng.range(0.96, 1.04);
        const halfW = (5.4 - 2.0 * t) * rng.range(0.85, 1.15);
        const back = 1.1 * t;
        const nb = 2 + rng.intn(3);
        const bold = rng.float() < 0.22;
        const depth: f32 = if (bold) rng.range(0.34, 0.50) else rng.range(0.16, 0.28);
        const rise: f32 = if (bold) rng.range(0.20, 0.32) else rng.range(0.09, 0.18);
        var i: i32 = 0;
        while (i < nb) : (i += 1) {
            const fi = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(nb));
            const cx = (fi * 2.0 - 1.0) * halfW;
            const w = (2.0 * halfW / @as(f32, @floatFromInt(nb))) * rng.range(0.95, 1.35);
            b.addBox(
                v3(cx + rng.signed() * 0.22, y, back - 1.20 + rng.signed() * 0.16),
                v3(w * 0.5, rng.signed() * 0.045, rng.signed() * 0.03),
                v3(rng.signed() * 0.05, rise, rng.signed() * 0.04),
                v3(rng.signed() * 0.04, 0, depth),
                if (rng.float() < 0.24) CLIFF_LT else if (rng.float() < 0.46) CLIFF_DK else CLIFF_ROCK,
            );
        }
    }
    var f: i32 = 0;
    while (f < 6) : (f += 1) {
        const cx = rng.range(-4.6, 4.6);
        const h = rng.range(0.26, 0.68) * H;
        const bold = rng.float() < 0.3;
        const rr = if (bold) rng.range(0.42, 0.60) else rng.range(0.20, 0.34);
        const z0: f32 = if (bold) -1.55 else -1.25;
        b.addCapsule(
            v3(cx, 0.2, z0 + rng.signed() * 0.14),
            v3(cx + rng.signed() * 0.34, h, z0 + 0.35 + rng.signed() * 0.18),
            rr,
            rr * rng.range(0.70, 0.92),
            @as(i32, if (bold) 9 else 7),
            CLIFF_DK,
        );
    }
    var t: i32 = 0;
    while (t < 9) : (t += 1) {
        const cx = rng.range(-6.4, 6.4);
        const cz = rng.range(-2.1, -0.7);
        const r = rng.range(0.35, 1.25) * (1.0 - 0.4 * @abs(cz + 0.7) / 1.4);
        b.addBlob(v3(cx, r * 0.55, cz), v3(r, r * 0.7, r * rng.range(0.8, 1.2)), 4, 6, if (rng.float() < 0.3) CLIFF_LT else CLIFF_ROCK);
    }
    if (k.broken > 0) {
        const gx = frng.range(-3.0, 3.0);
        const gTop = H * frng.range(0.58, 0.84);
        const gW = frng.range(0.75, 1.25) * (0.6 + 0.4 * k.broken);
        b.setMat(.stone);
        for ([_]f32{ 1, -1 }) |sgn| {
            const rTop = gTop * frng.range(0.62, 1.0);
            const rGirth = frng.range(0.78, 1.25);
            const rSegs: i32 = 5;
            var prev: ?rl.Vector3 = null;
            var prevR: f32 = 0;
            var st: i32 = 0;
            while (st <= rSegs) : (st += 1) {
                const rt = @as(f32, @floatFromInt(st)) / @as(f32, @floatFromInt(rSegs));
                const rw = frng.range(0.48, 1.02) * rGirth * (1.0 - 0.34 * rt);
                const cx = gx + sgn * (gW + rw * 0.9);
                const y = rTop * (0.04 + 0.94 * rt);
                const fz = cliffFaceZ(face, cx, y) orelse {
                    prev = null;
                    continue;
                };
                const proud: f32 = if (st == rSegs) 0.85 else 0.25;
                const p = v3(cx, y, fz + rw * proud);
                if (prev) |q| b.addCapsule(q, p, prevR, rw, 9, if (frng.float() < 0.3) CLIFF_DK else CLIFF_ROCK);
                prev = p;
                prevR = rw;
            }
        }
        var e: i32 = 0;
        while (e < 7) : (e += 1) {
            const w = frng.range(0.20, 0.45);
            const cx = gx + frng.signed() * gW * 0.7;
            const y = gTop * frng.range(0.08, 0.94);
            const hh = frng.range(0.35, 0.95);
            const fz = cliffSeatZ(face, cx, y, w, hh) orelse continue;
            const d = frng.range(0.26, 0.38);
            b.addBox(
                v3(cx, y, fz + d - 0.06),
                v3(w, frng.signed() * 0.05, frng.signed() * 0.04),
                v3(frng.signed() * 0.06, hh, frng.signed() * 0.05),
                v3(0, 0, d),
                CLIFF_LT,
            );
        }
        const nApron: i32 = @intFromFloat(@round(8.0 + 6.0 * k.broken));
        var ap: i32 = 0;
        while (ap < nApron) : (ap += 1) {
            const out = frng.float();
            const cx = gx + frng.signed() * (1.3 + 2.6 * out);
            const cz = -1.0 - out * frng.range(1.2, 2.8);
            const r = frng.range(0.30, 1.15) * (1.0 - 0.45 * out);
            b.addBlob(v3(cx, r * 0.5, cz), v3(r, r * frng.range(0.55, 0.80), r * frng.range(0.80, 1.25)), 4, 6, if (frng.float() < 0.28) CLIFF_LT else CLIFF_ROCK);
        }
        var sl: i32 = 0;
        while (sl < 3) : (sl += 1) {
            const hh = frng.range(1.1, 2.0);
            const lean = frng.range(0.45, 0.95) * (if (frng.float() < 0.5) @as(f32, -1) else 1);
            b.addBox(
                v3(gx + frng.signed() * 3.4, hh * 0.42, -2.8 + frng.signed() * 0.9),
                v3(frng.range(0.70, 1.40), 0, frng.signed() * 0.20),
                v3(lean * hh, hh, frng.signed() * 0.30),
                v3(0, 0, frng.range(0.22, 0.42)),
                if (frng.float() < 0.4) CLIFF_LT else CLIFF_DK,
            );
        }
    }
    var c: i32 = 0;
    while (c + 1 < NM) : (c += 1) {
        const a = top[@intCast(c)];
        const d = top[@intCast(c + 1)];
        const lo = @min(a.y, d.y);
        b.addBlob(
            v3((a.x + d.x) * 0.5, lo - H * rng.range(0.05, 0.10), (a.z + d.z) * 0.5 + rng.signed() * 0.4),
            v3(@abs(d.x - a.x) * 0.5 + @min(a.rx, d.rx) * 0.75, H * rng.range(0.07, 0.12), @min(a.rz, d.rz) * rng.range(0.85, 1.05)),
            5,
            9,
            if (rng.float() < 0.25) CLIFF_LT else CLIFF_ROCK,
        );
    }
    b.setMat(.plant);
    var g: i32 = 0;
    while (g < 6) : (g += 1) {
        const s = top[@intCast(rng.intn(NM))];
        const r = rng.range(0.30, 0.55);
        const nx = rng.signed() * 0.5;
        const nz = rng.signed() * 0.35;
        const gx = s.x + nx * s.rx;
        const gz = s.z + nz * s.rz;
        const gy = s.y - s.ry * (1.0 - @sqrt(@max(1.0 - nx * nx - nz * nz, 0.0))) - r * rng.range(0.20, 0.34);
        b.addBlob(
            v3(gx, gy, gz),
            v3(r, r * rng.range(0.30, 0.48), r * rng.range(0.7, 1.1)),
            3,
            7,
            if (rng.float() < 0.5) SCRUB_DK else MOSS_DK,
        );
        art.lichenInto(&b, &rng, v3(gx, gy + r * 0.22, gz), v3(r * 1.15, 0.06, r * 1.05), 4);
    }
    if (k.ivy > 0) {
        const nCurtain: i32 = @intFromFloat(@round(7.0 + 5.0 * k.ivy));
        var cu: i32 = 0;
        while (cu < nCurtain) : (cu += 1) {
            var cx = frng.range(-5.4, 5.4);
            const y0 = H * frng.range(0.34, 0.86);
            const drop = y0 * frng.range(0.60, 0.95);
            const steps: i32 = 8;
            var prev: ?rl.Vector3 = null;
            var st: i32 = 0;
            while (st <= steps) : (st += 1) {
                const s = @as(f32, @floatFromInt(st)) / @as(f32, @floatFromInt(steps));
                const y = y0 - drop * s;
                cx += frng.signed() * 0.18;
                const fz = cliffFaceZ(face, cx, y) orelse {
                    prev = null;
                    continue;
                };
                const p = v3(cx, y, fz - 0.06);
                if (prev) |q| {
                    b.setMat(.wood);
                    b.addCapsule(q, p, 0.030, 0.045, 5, BARK_DK);
                }
                prev = p;
                b.setMat(.plant);
                const nLeaf: i32 = 2 + frng.intn(3);
                var lf: i32 = 0;
                while (lf < nLeaf) : (lf += 1) {
                    const lx = cx + frng.signed() * 0.55;
                    const ly = y + frng.signed() * 0.30;
                    const lz = cliffFaceZ(face, lx, ly) orelse continue;
                    const r = frng.range(0.16, 0.38);
                    const rz2 = r * frng.range(0.55, 0.85);
                    b.addBlob(
                        v3(lx, ly, lz + rz2 - r * 0.15),
                        v3(r, r * frng.range(0.7, 1.15), rz2),
                        3,
                        7,
                        if (frng.float() < 0.35) SCRUB_DK else IVY_GRN,
                    );
                }
            }
        }
        b.setMat(.plant);
        var ms: i32 = 0;
        while (ms < 16) : (ms += 1) {
            const mx = frng.range(-5.0, 5.0);
            const my = H * frng.range(0.08, 0.74);
            const w = frng.range(0.40, 1.05);
            const hh = w * frng.range(0.30, 0.60);
            const fz = cliffSeatZ(face, mx, my, w, hh) orelse continue;
            b.addBlob(
                v3(mx, my, fz + 0.22),
                v3(w, hh, 0.26),
                3,
                7,
                if (frng.float() < 0.5) MOSS_DK else STONE_MOSS,
            );
        }
        var cs: i32 = 0;
        while (cs < 5) : (cs += 1) {
            const s = top[@intCast(frng.intn(NM))];
            const r = frng.range(0.45, 0.85);
            const nx = frng.signed() * 0.5;
            const nz = frng.signed() * 0.35;
            const cxp = s.x + nx * s.rx;
            const czp = s.z + nz * s.rz;
            const cyp = s.y - s.ry * (1.0 - @sqrt(@max(1.0 - nx * nx - nz * nz, 0.0))) - r * frng.range(0.18, 0.30);
            b.addBlob(
                v3(cxp, cyp, czp),
                v3(r, r * frng.range(0.34, 0.55), r * frng.range(0.7, 1.1)),
                3,
                7,
                if (frng.float() < 0.4) IVY_GRN else SCRUB_DK,
            );
            art.lichenInto(&b, &frng, v3(cxp, cyp + r * 0.28, czp), v3(r * 1.05, 0.07, r * 0.95), 3);
        }
    }
    return b;
}

pub fn boulderMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4242);
    b.setMat(.stone);
    const nm = 3 + rng.intn(2);
    var crownC = v3(0, 0, 0);
    var crownR = v3(1, 1, 1);
    var i: i32 = 0;
    while (i < nm) : (i += 1) {
        const r = rng.range(0.75, 1.15) * (1.0 - 0.12 * @as(f32, @floatFromInt(i)));
        const c = v3(rng.signed() * 0.42, rng.range(0.55, 1.15), rng.signed() * 0.38);
        const e = v3(r, r * rng.range(0.68, 0.95), r * rng.range(0.82, 1.18));
        b.addBlob(c, e, 5, 7, if (@mod(i, 2) == 0) CLIFF_DK else ROCK_DEEP);
        if (c.y + e.y > crownC.y + crownR.y) {
            crownC = c;
            crownR = e;
        }
    }
    var c: i32 = 0;
    while (c < 4) : (c += 1) {
        const r = rng.range(0.14, 0.32);
        b.addBlob(v3(rng.signed() * 1.35, r * 0.55, rng.signed() * 1.3), v3(r, r * 0.7, r), 3, 5, CLIFF_LT);
    }
    b.setMat(.plant);
    const nx = rng.signed() * 0.45;
    const nz = rng.signed() * 0.35;
    const mx = crownC.x + nx * crownR.x;
    const mz = crownC.z + nz * crownR.z;
    const my = crownC.y + crownR.y * @sqrt(@max(1.0 - nx * nx - nz * nz, 0.0));
    b.addBlob(v3(mx, my - 0.10, mz), v3(0.34, 0.11, 0.30), 3, 7, MOSS_DK);
    art.lichenInto(&b, &rng, v3(mx, my - 0.02, mz), v3(0.40, 0.05, 0.36), 5);
    return b.toModel(shader);
}

pub fn rocksMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(1717);
    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.1, 1.35);
        const r = rng.range(0.16, 0.46);
        b.addBlob(
            v3(mathx.cosf(a) * d, r * rng.range(0.42, 0.78), mathx.sinf(a) * d),
            v3(r * rng.range(0.9, 1.3), r * rng.range(0.6, 0.9), r * rng.range(0.9, 1.2)),
            3,
            6,
            if (rng.float() < 0.25) CLIFF_ROCK else if (rng.float() < 0.55) CLIFF_DK else ROCK_DEEP,
        );
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 0.8, rng.signed() * 0.8, 0.6);
    return b.toModel(shader);
}

pub fn monolithMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(606);
    b.setMat(.stone);
    const leanSX: f32 = if (rng.float() < 0.5) 1 else -1;
    const leanSZ: f32 = if (rng.float() < 0.5) 1 else -1;
    const lean = v3(leanSX * rng.range(0.14, 0.32), 4.55, leanSZ * rng.range(0.10, 0.26));
    b.addBox(
        v3(lean.x * 0.5, lean.y * 0.5, lean.z * 0.5),
        v3(0.58, 0.04, 0.02),
        v3(lean.x * 0.5, lean.y * 0.5, lean.z * 0.5),
        v3(0.03, 0, 0.40),
        CLIFF_ROCK,
    );
    b.addBox(v3(lean.x + rng.signed() * 0.1, lean.y + 0.16, lean.z), v3(0.42, 0.05, 0), v3(0, 0.18, 0.04), v3(0, 0, 0.30), CLIFF_DK);
    b.addBlob(v3(lean.x * 0.62 + 0.5, lean.y * 0.6, lean.z * 0.6 + 0.2), v3(0.20, 0.26, 0.18), 3, 5, CLIFF_LT);
    for ([_]f32{ 0.24, 0.49, 0.76 }, 0..) |t0, bi| {
        const t = t0 + rng.signed() * 0.04;
        const broken = bi == 1;
        b.addBox(
            v3(lean.x * t + (if (broken) @as(f32, 0.26) else rng.signed() * 0.02), lean.y * t, lean.z * t),
            v3((if (broken) @as(f32, 0.34) else 0.60) * rng.range(0.94, 1.03), 0, 0),
            v3(0, rng.range(0.038, 0.075), 0),
            v3(0, 0, 0.42 * rng.range(0.92, 1.04)),
            CLIFF_DK,
        );
    }
    for ([_]f32{ 0.24, 0.49, 0.76 }, 0..) |t0, bi| {
        const broken = bi == 1;
        var st: i32 = 0;
        while (st < 2) : (st += 1) {
            if (rng.float() < 0.25) continue;
            const sh = rng.range(0.14, 0.34);
            b.addBox(
                v3(lean.x * t0 + (if (broken) @as(f32, 0.26) else 0) + rng.signed() * 0.38, lean.y * t0 - 0.10 - sh, lean.z * t0),
                v3(rng.range(0.020, 0.048), 0, 0),
                v3(0, sh, 0),
                v3(0, 0, 0.412),
                ROCK_DEEP,
            );
        }
    }
    b.addBox(v3(0, 0.22, 0), v3(0.585, 0, 0), v3(0, rng.range(0.16, 0.26), 0), v3(0.03, 0, 0.408), CLIFF_DK);
    var mo: i32 = 0;
    while (mo < 2) : (mo += 1) {
        const t = rng.range(0.30, 0.72);
        b.addBox(
            v3(lean.x * t + rng.signed() * 0.30, lean.y * t, lean.z * t),
            v3(rng.range(0.09, 0.17), 0, 0),
            v3(0, rng.range(0.28, 0.55), 0),
            v3(0, 0, 0.405),
            CLIFF_LT,
        );
    }
    b.setMat(.plant);
    b.addBlob(v3(lean.x * 0.25 - 0.42, 0.75, lean.z * 0.25), v3(0.16, 0.55, 0.30), 3, 5, STONE_MOSS);
    b.addBlob(v3(0, 0.10, 0), v3(0.85, 0.10, 0.75), 3, 6, SCRUB_DK);
    art.lichenInto(&b, &rng, v3(-0.30, 0.55, 0.20), v3(0.16, 0.28, 0.14), 4);
    art.lichenInto(&b, &rng, v3(0.30, rng.range(1.3, 2.0), -0.15), v3(0.12, 0.30, 0.12), 3);
    return b.toModel(shader);
}

pub fn cairnMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2111);
    b.setMat(.stone);
    b.addCylinder(v3(0, 0.0, 0), v3(0, 1.34, 0), 0.34, 0.10, 7, MORTAR);
    var y: f32 = 0.0;
    var i: i32 = 0;
    const n: i32 = 7;
    while (i < n) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
        const r = (0.46 - 0.30 * t) * rng.range(0.85, 1.15);
        const hh = r * rng.range(0.42, 0.7);
        b.addBlob(v3(rng.signed() * 0.09 * (1.0 + t), y + hh, rng.signed() * 0.09 * (1.0 + t)), v3(r, hh, r * rng.range(0.82, 1.18)), 3, 6, if (rng.float() < 0.3) CLIFF_LT else if (rng.float() < 0.55) CLIFF_DK else CLIFF_ROCK);
        y += hh * 1.55;
    }
    var f: i32 = 0;
    while (f < 3) : (f += 1) {
        const a = rng.angle();
        const r = rng.range(0.12, 0.22);
        b.addBlob(v3(mathx.cosf(a) * rng.range(0.6, 1.0), r * 0.55, mathx.sinf(a) * rng.range(0.6, 1.0)), v3(r, r * 0.7, r), 3, 5, CLIFF_ROCK);
    }
    b.setMat(.plant);
    b.addBlob(v3(0, 0.06, 0), v3(0.62, 0.08, 0.58), 3, 6, MOSS_DK);
    tuftInto(&b, &rng, rng.signed() * 0.7, rng.signed() * 0.7, 0.7);
    return b.toModel(shader);
}

pub fn outcropMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2112);
    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const x = -1.2 + @as(f32, @floatFromInt(i)) * 0.8;
        const h = rng.range(0.45, 0.95);
        b.addBlob(v3(x + rng.signed() * 0.2, h * 0.42, rng.signed() * 0.4), v3(rng.range(0.6, 1.0), h * 0.5, rng.range(0.5, 0.9)), 4, 6, if (@mod(i, 2) == 0) CLIFF_ROCK else CLIFF_DK);
    }
    var s: i32 = 0;
    while (s < 5) : (s += 1) {
        const y = 0.12 + @as(f32, @floatFromInt(s)) * 0.17;
        b.addBox(
            v3(rng.range(-1.3, 1.3), y, -0.55 + rng.signed() * 0.2),
            v3(rng.range(0.35, 0.7), rng.signed() * 0.05, 0),
            v3(0, rng.range(0.06, 0.11), 0),
            v3(0, 0, rng.range(0.2, 0.4)),
            if (rng.float() < 0.3) CLIFF_LT else CLIFF_DK,
        );
    }
    var t: i32 = 0;
    while (t < 5) : (t += 1) {
        const r = rng.range(0.13, 0.26);
        b.addBlob(v3(rng.range(-1.8, 1.8), r * 0.5, rng.range(-1.3, -0.5)), v3(r, r * 0.65, r), 3, 5, CLIFF_ROCK);
    }
    b.setMat(.plant);
    var g: i32 = 0;
    while (g < 3) : (g += 1) {
        const px = rng.range(-1.2, 1.2);
        const py = rng.range(0.5, 0.9);
        const pz = rng.range(0.3, 0.8);
        b.addBlob(v3(px, py, pz), v3(rng.range(0.22, 0.40), 0.09, rng.range(0.20, 0.36)), 3, 7, if (rng.float() < 0.5) MOSS_DK else SCRUB_DK);
        art.lichenInto(&b, &rng, v3(px, py + 0.05, pz), v3(0.48, 0.05, 0.42), 3);
    }
    tuftInto(&b, &rng, rng.range(-1.5, 1.5), rng.range(0.2, 0.9), 0.8);
    return b.toModel(shader);
}

pub fn screeMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2113);
    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 42) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0, 1.9) * @sqrt(rng.float());
        const r = rng.range(0.05, 0.19);
        b.addBlob(
            v3(mathx.cosf(a) * d, r * rng.range(0.28, 0.6), mathx.sinf(a) * d * rng.range(0.7, 1.0)),
            v3(r, r * rng.range(0.3, 0.55), r * rng.range(0.85, 1.25)),
            3,
            5,
            if (rng.float() < 0.3) CLIFF_LT else if (rng.float() < 0.6) CLIFF_ROCK else CLIFF_DK,
        );
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 1.5, rng.signed() * 1.5, 0.6);
    return b.toModel(shader);
}



fn stratumCol(i: i32, n: i32) rl.Color {
    const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(@max(n - 1, 1)));
    return art.seam(art.weathered(ROCK_DEEP, CLIFF_LT, t), CLIFF_DK, i, 4);
}

fn bedsInto(b: *Builder, rng: *mathx.Rng, cx: f32, cz: f32, y0: f32, h: f32, r0: f32, r1: f32, n: i32, wander: f32) rl.Vector3 {
    var y = y0;
    var x = cx;
    var z = cz;
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
        const bh = h / @as(f32, @floatFromInt(n));
        const r = mathx.lerpF(r0, r1, t) * rng.range(0.90, 1.10);
        b.addBlob(v3(x, y + bh * 0.5, z), v3(r, bh * 0.78, r * rng.range(0.90, 1.10)), 4, 10, stratumCol(i, n));
        y += bh;
        x += rng.signed() * wander;
        z += rng.signed() * wander;
    }
    return v3(x, y, z);
}

pub const HOODOO_H: f32 = 5.6;

pub fn hoodooMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x0C1);
    b.setMat(.stone);
    const skirt = bedsInto(&b, &rng, 0, 0, 0, HOODOO_H * 0.30, 1.05, 0.62, 3, 0.05);
    const neck = bedsInto(&b, &rng, skirt.x, skirt.z, skirt.y, HOODOO_H * 0.46, 0.52, 0.34, 4, 0.09);
    b.addBlob(v3(neck.x, neck.y + 0.42, neck.z), v3(1.30, 0.46, 1.15), 4, 9, ROCK_DEEP);
    b.addBlob(v3(neck.x + 0.10, neck.y + 0.80, neck.z - 0.06), v3(0.95, 0.34, 0.86), 3, 8, CLIFF_DK);
    b.addDome(v3(neck.x + 0.10, neck.y + 0.92, neck.z - 0.06), v3(0, 1, 0), 0.72, 10, ROCK_DEEP);
    art.chipsInto(&b, &rng, 0, 0, 1.8, 0.10, 0.26, 6);
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 1.3, rng.signed() * 1.3, 0.5);
    return b.toModel(shader);
}

pub const SPIRE_H: f32 = 9.2;

pub fn spireMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x0C2);
    b.setMat(.stone);
    const lean = mathx.radians(7.5);
    var y: f32 = 0;
    var i: i32 = 0;
    const N = 9;
    while (i < N) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / N;
        const bh = SPIRE_H / N;
        const r = mathx.lerpF(1.35, 0.40, t) * rng.range(0.92, 1.08);
        const off = mathx.sinf(lean) * y;
        b.addBlob(v3(off, y + bh * 0.5, rng.signed() * 0.05), v3(r, bh * 0.76, r * rng.range(0.88, 1.12)), 4, 10, stratumCol(i, N));
        y += bh;
    }
    const top = v3(mathx.sinf(lean) * y, y, 0);
    b.addBlob(v3(top.x, top.y - 0.10, top.z), v3(0.46, 0.13, 0.42), 2, 8, CLIFF_LT);
    art.crackInto(&b, v3(top.x - 0.3, top.y - 0.4, 0.30), v3(-0.10, -1.0, 0.06), v3(1, 0, 0), SPIRE_H * 0.55, 0.10, 0.16);
    var j: i32 = 0;
    while (j < 6) : (j += 1) {
        const a = rng.range(-0.9, 0.9);
        const d = rng.range(1.3, 2.4);
        const r = rng.range(0.20, 0.46);
        b.addBlob(v3(mathx.cosf(a) * d, r * 0.55, mathx.sinf(a) * d), v3(r, r * rng.range(0.5, 0.8), r * rng.range(0.8, 1.3)), 3, 6, if (rng.float() < 0.5) CLIFF_DK else ROCK_DEEP);
    }
    art.chipsInto(&b, &rng, 0, 0, 2.2, 0.08, 0.20, 7);
    return b.toModel(shader);
}

pub const BALANCED_H: f32 = 3.9;

pub fn balancedMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x0C3);
    b.setMat(.stone);
    const ped = bedsInto(&b, &rng, 0, 0, 0, 1.55, 1.15, 0.58, 4, 0.06);
    b.addBlob(v3(ped.x, ped.y + 0.10, ped.z), v3(0.42, 0.12, 0.38), 2, 7, ROCK_DEEP);
    const cx = ped.x + 0.62;
    const cz = ped.z - 0.24;
    const cy = ped.y + 1.18;
    b.addBlob(v3(cx, cy, cz), v3(1.62, 1.02, 1.44), 5, 10, CLIFF_ROCK);
    b.addBlob(v3(cx - 0.45, cy + 0.34, cz + 0.30), v3(0.92, 0.62, 0.86), 4, 8, CLIFF_DK);
    b.addBlob(v3(cx + 0.70, cy - 0.20, cz - 0.35), v3(0.62, 0.44, 0.58), 3, 7, CLIFF_LT);
    art.lichenInto(&b, &rng, v3(cx - 0.2, cy + 0.86, cz), v3(0.70, 0.03, 0.62), 4);
    art.chipsInto(&b, &rng, 0, 0, 1.9, 0.09, 0.24, 6);
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 1.2, rng.signed() * 1.2, 0.55);
    return b.toModel(shader);
}

pub const FINGERS_H: f32 = 4.6;

pub fn fingersMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x0C4);
    b.setMat(.stone);
    const N = 5;
    var i: i32 = 0;
    while (i < N) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / (N - 1);
        const h = FINGERS_H * mathx.lerpF(1.0, 0.46, t) * rng.range(0.94, 1.06);
        const lean = mathx.radians(mathx.lerpF(6.0, 34.0, t));
        const x = mathx.lerpF(-0.9, 1.7, t);
        const z = rng.signed() * 0.26;
        const w = mathx.lerpF(0.58, 0.34, t);
        const foot = v3(x, 0, z);
        const head = v3(x + mathx.sinf(lean) * h, mathx.cosf(lean) * h, z + rng.signed() * 0.14);
        // A SLAB, so it is wide across the fan and thin along it — 4 sides, not a cylinder.
        b.addCylinder(foot, head, w, w * 0.72, 4, stratumCol(i, N));
        b.addDome(head, mathx.normV(mathx.subV(head, foot)), w * 0.70, 6, CLIFF_LT);
        b.addBlob(v3(x, 0.16, z), v3(w * 1.5, 0.22, w * 1.3), 3, 7, ROCK_DEEP);
    }
    art.chipsInto(&b, &rng, 0.4, 0, 2.0, 0.08, 0.22, 8);
    b.setMat(.plant);
    tuftInto(&b, &rng, -1.4, rng.signed() * 1.0, 0.5);
    tuftInto(&b, &rng, 2.1, rng.signed() * 1.0, 0.42);
    return b.toModel(shader);
}

test "a formation is top-heavy, a spire is not, and both know their own height" {
    try std.testing.expect(HOODOO_H > 4.0);
    try std.testing.expect(SPIRE_H > HOODOO_H);
    try std.testing.expect(BALANCED_H < HOODOO_H);
    try std.testing.expect(FINGERS_H < SPIRE_H);
}



pub const SHARD_H: f32 = 0.58;

/// A 4-SIDED TAPERED CYLINDER, NOT A BOX (`fingersMesh`'s reason): a box face square-on to the key takes the whole of it, so `ROCK_DEEP` at 23,22,21 renders light grey, and boxes sharing the lean plane z-fought where they touched. The LEAN is shared because one bed failed; the YAW is not.
pub fn shardsMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A11D);
    b.setMat(.stone);
    const plane = rng.angle();
    const N = 9;
    var i: i32 = 0;
    while (i < N) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0, 0.86) * @sqrt(rng.float());
        const h = SHARD_H * rng.range(0.32, 1.0);
        const lean = rng.range(0.22, 0.62);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const w = rng.range(0.055, 0.125);
        const foot = v3(x, -0.04, z);
        const head = v3(x + mathx.cosf(plane) * h * lean, h, z + mathx.sinf(plane) * h * lean);
        b.addCylinder(foot, head, w, w * rng.range(0.12, 0.30), 4, stratumCol(i, N));
        b.addDome(head, mathx.normV(mathx.subV(head, foot)), w * 0.26, 5, CLIFF_DK);
    }
    art.chipsInto(&b, &rng, 0, 0, 1.15, 0.05, 0.13, 9);
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 0.8, rng.signed() * 0.8, 0.42);
    return b.toModel(shader);
}

pub fn slabsMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x51AB5);
    b.setMat(.stone);
    var y: f32 = 0.03;
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0, 0.55);
        const w = rng.range(0.42, 0.92);
        const t = rng.range(0.035, 0.075);
        const yaw = rng.angle();
        b.addBox(
            v3(mathx.cosf(a) * d, y + t * 0.5, mathx.sinf(a) * d),
            v3(mathx.cosf(yaw) * w, rng.signed() * 0.05, mathx.sinf(yaw) * w),
            v3(0, t, 0),
            v3(-mathx.sinf(yaw) * w * rng.range(0.55, 0.9), 0, mathx.cosf(yaw) * w * rng.range(0.55, 0.9)),
            art.weathered(CLIFF_DK, CLIFF_LT, @as(f32, @floatFromInt(i)) / 6.0),
        );
        y += t * rng.range(0.35, 0.85);
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 0.9, rng.signed() * 0.9, 0.36);
    return b.toModel(shader);
}

pub fn cobblesMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xC0BB1E);
    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 34) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0, 1.15) * @sqrt(rng.float());
        const r = rng.range(0.07, 0.17);
        b.addBlob(
            v3(mathx.cosf(a) * d, r * 0.55, mathx.sinf(a) * d),
            v3(r, r * rng.range(0.52, 0.78), r * rng.range(0.85, 1.2)),
            3,
            7,
            if (rng.float() < 0.22) STONE_MOSS else art.weathered(ROCK_DEEP, CLIFF_LT, rng.float()),
        );
    }
    return b.toModel(shader);
}

pub const WHALE_H: f32 = 0.92;

pub fn whalebackMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x3A1E);
    b.setMat(.stone);
    const yaw = rng.angle();
    const L = 2.15;
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const t = (@as(f32, @floatFromInt(i)) + 0.5) / 5.0;
        const bulge = mathx.sinf(std.math.pi * mathx.clampF(t * 0.88 + 0.06, 0, 1));
        const along = (t - 0.5) * L * 2.0;
        b.addBlob(
            v3(mathx.cosf(yaw) * along, WHALE_H * bulge * 0.52, mathx.sinf(yaw) * along),
            v3(0.86 * bulge * rng.range(0.92, 1.08), WHALE_H * bulge * 0.62, 0.86 * bulge * rng.range(0.92, 1.08)),
            4,
            9,
            art.weathered(ROCK_DEEP, CLIFF_ROCK, t),
        );
    }
    const SINK: f32 = 0.62;
    i = 0;
    while (i < 17) : (i += 1) {
        const t = rng.range(0.10, 0.90);
        const bulge = mathx.sinf(std.math.pi * mathx.clampF(t * 0.88 + 0.06, 0, 1));
        const along = (t - 0.5) * L * 2.0;
        const across = rng.signed() * 0.46;
        const surf = WHALE_H * bulge * 0.44 + WHALE_H * bulge * 0.62 * @sqrt(mathx.maxF(1.0 - across * across, 0.02));
        const r = rng.range(0.13, 0.27);
        b.addBlob(
            v3(
                mathx.cosf(yaw) * along - mathx.sinf(yaw) * across * 0.86 * bulge,
                surf - r * SINK,
                mathx.sinf(yaw) * along + mathx.cosf(yaw) * across * 0.86 * bulge,
            ),
            v3(r, r * 0.78, r * rng.range(0.8, 1.25)),
            3,
            7,
            if (rng.float() < 0.45) MOSS_DK else STONE_MOSS,
        );
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, mathx.cosf(yaw + 1.6) * 0.9, mathx.sinf(yaw + 1.6) * 0.9, 0.5);
    return b.toModel(shader);
}

test "SMALL STONE IS FOUR BREAKS, NOT FOUR SIZES — and every one of them is under the knee" {
    std.debug.print("\n  small stone: shards {d:.2} m, whaleback {d:.2} m — knee is 0.48 m\n", .{ SHARD_H, WHALE_H });
    try std.testing.expect(SHARD_H < 1.0);
    try std.testing.expect(WHALE_H < 1.0);
    try std.testing.expect(WHALE_H > SHARD_H);
}
