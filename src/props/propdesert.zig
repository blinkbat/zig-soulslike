const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const art = @import("propart.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// SOLVE IT, DO NOT GUESS IT (AGENTS.md): screen = 255 x (albedo x 1.72)^(1/2.2). A seven-metre cactus is a BIG
// SMOOTH MASS, so its body is authored DARKER than the plain's scrub and separates on hue: 96/118/82.
pub const CACTUS = rgba(17, 27, 12, 255);
pub const CACTUS_LT = rgba(30, 45, 21, 255);
pub const CACTUS_DK = rgba(7, 11, 5, 255);
/// Sun-scorched flank — the SAME flesh with the drought on it, not a second plant. 128/122/74.
pub const STARVED = rgba(33, 29, 10, 255);
/// The woody ribs a saguaro leaves standing. Bleached, and PALER than any live tissue here: 156/134/96.
pub const DEADWOOD = rgba(50, 36, 17, 255);
/// Spines read as a HALO, not as needles — one pale areole where a real plant has twenty spines. Solved to
/// 206/200/176, which is 1.7x the flesh: at 188 it only tied it and the plant came back a green post. COOL
/// against everything else here, because a warm halo reads as gold beading on a green pipe.
pub const SPINE = rgba(93, 87, 66, 255);
pub const BLOOM = rgba(101, 87, 46, 255);
pub const DEADTWIG = rgba(22, 14, 7, 255);

// A DUNE IS NOT THE PAINTED FLOOR: a two-metre mound of the same sand comes back paler for its size, so it is
// solved at 150/108/74 against the floor's 164/116/81 and the crest is lifted from there.
pub const DUNE = rgba(46, 22, 10, 255);
pub const DUNE_LT = rgba(66, 34, 16, 255);
pub const DUNE_DK = rgba(27, 12, 5, 255);

/// How much of its own radius a rib stands off the flesh. RELIEF IS SUBTLE (AGENTS.md) — a tenth reads as a bundle of pipes.
const RIB_PROUD: f32 = 0.040;
/// Metres between areoles up a rib. Any closer and the halo becomes a solid pale skin.
const AREOLE_EVERY: f32 = 0.55;

fn fleshTone(r: *mathx.Rng) rl.Color {
    const f = r.float();
    if (f < 0.16) return CACTUS_LT;
    if (f < 0.30) return CACTUS_DK;
    if (f < 0.38) return STARVED;
    return CACTUS;
}

const Axis = struct {
    d: rl.Vector3,
    u: rl.Vector3,
    w: rl.Vector3,
    len: f32,

    fn of(a: rl.Vector3, b: rl.Vector3) Axis {
        const span = mathx.subV(b, a);
        const len = @max(mathx.lenV(span), 1e-4);
        const d = mathx.scaleV(span, 1.0 / len);
        const ref = if (@abs(d.y) > 0.92) v3(1, 0, 0) else v3(0, 1, 0);
        const u = mathx.normV(mathx.crossV(d, ref));
        return .{ .d = d, .u = u, .w = mathx.crossV(d, u), .len = len };
    }

    fn at(ax: Axis, o: rl.Vector3, t: f32, ang: f32, rad: f32) rl.Vector3 {
        const c = mathx.cosf(ang);
        const s = mathx.sinf(ang);
        return v3(
            o.x + ax.d.x * t + (ax.u.x * c + ax.w.x * s) * rad,
            o.y + ax.d.y * t + (ax.u.y * c + ax.w.y * s) * rad,
            o.z + ax.d.z * t + (ax.u.z * c + ax.w.z * s) * rad,
        );
    }
};

/// **A CACTUS IS FLESH, SO IT IS ROUND** (AGENTS.md). Any bearing; a limb that turns does it in two calls.
fn limbInto(b: *Builder, r: *mathx.Rng, a: rl.Vector3, c: rl.Vector3, ra: f32, rb: f32, ribs: i32, spiny: f32) void {
    const ax = Axis.of(a, c);
    b.setMat(.plant);
    b.addCapsule(a, c, ra, rb, 11, fleshTone(r));
    const n: f32 = @floatFromInt(ribs);
    var i: i32 = 0;
    while (i < ribs) : (i += 1) {
        const ang = std.math.tau * @as(f32, @floatFromInt(i)) / n + r.signed() * 0.02;
        const p0 = Axis.at(ax, a, 0.04 * ax.len, ang, ra * (1.0 + RIB_PROUD));
        const p1 = Axis.at(ax, a, 0.97 * ax.len, ang, rb * (1.0 + RIB_PROUD));
        b.addCapsule(p0, p1, ra * 0.09, rb * 0.08, 5, if (r.float() < 0.24) STARVED else CACTUS_LT);
        if (spiny <= 0.001) continue;
        var t: f32 = AREOLE_EVERY * 0.5;
        while (t < ax.len) : (t += AREOLE_EVERY) {
            if (r.float() > spiny) continue;
            const k = t / ax.len;
            const rad = mathx.lerpF(ra, rb, k) * (1.0 + RIB_PROUD * 1.9);
            const q = Axis.at(ax, a, t, ang, rad);
            const s = mathx.lerpF(ra, rb, k) * r.range(0.08, 0.14);
            b.addBlob(q, v3(s, s, s), 2, 5, if (r.float() < 0.3) DEADWOOD else SPINE);
        }
    }
}

fn crownInto(b: *Builder, r: *mathx.Rng, c: rl.Vector3, rad: f32, n: i32) void {
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const a = r.angle();
        const d = r.range(0.15, 0.95) * rad;
        const s = r.range(0.055, 0.105);
        const at = v3(c.x + mathx.cosf(a) * d, c.y + r.range(0.02, 0.10), c.z + mathx.sinf(a) * d);
        b.addBlob(at, v3(s, s * 0.72, s), 2, 7, if (r.float() < 0.30) STARVED else BLOOM);
        b.addBlob(v3(at.x, at.y + s * 0.72, at.z), v3(s * 0.55, s * 0.42, s * 0.55), 2, 6, BLOOM);
    }
}

/// A STIFF POINTED BLADE, and the one thing here that IS a box: a leaf under tension is a folded plane.
fn bladeInto(b: *Builder, r: *mathx.Rng, root: rl.Vector3, yaw: f32, pitch: f32, len: f32, wide: f32, col: rl.Color, tipCol: rl.Color) void {
    const cy = mathx.cosf(yaw);
    const sy = mathx.sinf(yaw);
    const cp = mathx.cosf(pitch);
    const sp = mathx.sinf(pitch);
    const d = v3(cy * cp, sp, sy * cp);
    const side = v3(-sy, 0, cy);
    const bow = len * 0.06 * r.range(0.7, 1.4);
    const mid = v3(root.x + d.x * len * 0.5, root.y + d.y * len * 0.5 + bow, root.z + d.z * len * 0.5);
    b.setMat(.plant);
    b.addBox(
        mid,
        v3(d.x * len * 0.5, d.y * len * 0.5, d.z * len * 0.5),
        v3(-d.y * wide * 0.34, (1.0 - @abs(d.y)) * wide * 0.34 + 0.01, 0),
        v3(side.x * wide * 0.5, 0, side.z * wide * 0.5),
        col,
    );
    const tip = v3(root.x + d.x * len, root.y + d.y * len + bow * 1.5, root.z + d.z * len);
    b.addBox(
        v3(tip.x - d.x * len * 0.07, tip.y - d.y * len * 0.07, tip.z - d.z * len * 0.07),
        v3(d.x * len * 0.08, d.y * len * 0.08, d.z * len * 0.08),
        v3(0, wide * 0.10, 0),
        v3(side.x * wide * 0.14, 0, side.z * wide * 0.14),
        tipCol,
    );
}



pub const SAG_TOP: f32 = 7.30;
pub const SAG_R: f32 = 0.44;
const SAG_RIBS: i32 = 13;

/// An arm leaves the trunk on the horizontal, elbows, and then runs PARALLEL to it. One straight diagonal is a branch, and a saguaro has none.
fn armInto(b: *Builder, r: *mathx.Rng, trunkR: f32, at: f32, yaw: f32, out: f32, up: f32, rad: f32) rl.Vector3 {
    const cx = mathx.cosf(yaw);
    const cz = mathx.sinf(yaw);
    const root = v3(cx * trunkR * 0.55, at, cz * trunkR * 0.55);
    const elbow = v3(cx * out, at + out * 0.42, cz * out);
    const tip = v3(elbow.x + cx * 0.10, elbow.y + up, elbow.z + cz * 0.10);
    limbInto(b, r, root, elbow, rad * 1.05, rad, SAG_RIBS - 2, 0.55);
    limbInto(b, r, elbow, tip, rad, rad * 0.86, SAG_RIBS - 2, 0.55);
    b.setMat(.plant);
    b.addDome(tip, v3(cx * 0.10, up, cz * 0.10), rad * 0.86, 9, CACTUS);
    return tip;
}

pub fn saguaroMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5D_E5_01);
    const H: f32 = 6.95;

    b.setMat(.plant);
    b.addBlob(v3(0, 0.14, 0), v3(SAG_R * 1.45, 0.30, SAG_R * 1.40), 3, 11, CACTUS_DK);
    limbInto(&b, &rng, v3(0, 0.10, 0), v3(rng.signed() * 0.10, H, rng.signed() * 0.10), SAG_R * 1.10, SAG_R * 0.82, SAG_RIBS, 0.62);
    b.setMat(.plant);
    b.addDome(v3(rng.signed() * 0.10, H, rng.signed() * 0.10), v3(0, 1, 0), SAG_R * 0.82, 11, CACTUS);

    const a0 = armInto(&b, &rng, SAG_R * 1.02, 2.55, rng.angle(), 1.15, 2.70, SAG_R * 0.66);
    const a1 = armInto(&b, &rng, SAG_R * 0.96, 3.80, rng.angle(), 0.95, 1.70, SAG_R * 0.58);
    crownInto(&b, &rng, v3(rng.signed() * 0.10, H + 0.02, rng.signed() * 0.10), SAG_R * 0.70, 9);
    crownInto(&b, &rng, a0, SAG_R * 0.52, 5);
    _ = a1;

    b.setMat(.stone);
    art.chipsInto(&b, &rng, 0, 0, 1.5, 0.05, 0.14, 7);
    b.setMat(.wood);
    b.addCapsule(v3(0.65, 0.06, 0.35), v3(1.55, 0.05, 0.72), 0.035, 0.026, 5, DEADWOOD);
    return b.toModel(shader);
}

pub const SAG2_TOP: f32 = 9.50;

pub fn saguaroOldMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5D_E5_02);
    const H: f32 = 9.10;
    const R: f32 = 0.54;
    const LEAN: f32 = 0.42; // metres of drift at the crown, over nine of trunk

    b.setMat(.plant);
    b.addBlob(v3(0, 0.16, 0), v3(R * 1.50, 0.34, R * 1.44), 3, 11, CACTUS_DK);
    limbInto(&b, &rng, v3(0, 0.10, 0), v3(LEAN * 0.35, H * 0.55, 0.10), R * 1.12, R * 0.98, SAG_RIBS + 1, 0.60);
    limbInto(&b, &rng, v3(LEAN * 0.35, H * 0.55, 0.10), v3(LEAN, H, 0.18), R * 0.98, R * 0.80, SAG_RIBS + 1, 0.60);
    b.setMat(.plant);
    b.addDome(v3(LEAN, H, 0.18), v3(LEAN * 0.1, 1, 0.02), R * 0.80, 11, CACTUS);

    _ = armInto(&b, &rng, R * 1.05, 2.30, 0.35, 1.35, 4.10, R * 0.72);
    _ = armInto(&b, &rng, R * 1.02, 3.15, 2.55, 1.20, 3.20, R * 0.66);
    _ = armInto(&b, &rng, R * 0.98, 4.60, 4.35, 1.05, 2.30, R * 0.60);
    _ = armInto(&b, &rng, R * 0.94, 5.90, 1.60, 0.88, 1.55, R * 0.52);

    const sy: f32 = 5.7;
    const sa: f32 = 3.55;
    const sx = mathx.cosf(sa);
    const sz = mathx.sinf(sa);
    b.setMat(.plant);
    b.addBlob(v3(sx * R * 1.05, sy, sz * R * 1.05), v3(0.34, 0.30, 0.34), 3, 9, CACTUS_DK);
    b.setMat(.wood);
    b.addBlob(v3(sx * R * 1.22, sy, sz * R * 1.22), v3(0.24, 0.22, 0.24), 3, 8, DEADTWIG);
    var k: i32 = 0;
    while (k < 5) : (k += 1) {
        const t = (@as(f32, @floatFromInt(k)) - 2.0) * 0.09;
        b.addCapsule(
            v3(sx * R * 1.12 - sz * t, sy - 0.20, sz * R * 1.12 + sx * t),
            v3(sx * R * 1.40 - sz * t, sy + 0.16 + rng.signed() * 0.06, sz * R * 1.40 + sx * t),
            0.022,
            0.016,
            5,
            DEADWOOD,
        );
    }

    const ba: f32 = 0.9;
    b.setMat(.wood);
    b.addBlob(v3(mathx.cosf(ba) * R * 1.06, 3.0, mathx.sinf(ba) * R * 1.06), v3(0.19, 0.24, 0.19), 3, 8, DEADTWIG);
    b.setMat(.plant);
    b.addCapsule(
        v3(mathx.cosf(ba) * R * 1.04, 2.72, mathx.sinf(ba) * R * 1.04),
        v3(mathx.cosf(ba) * R * 1.02, 0.90, mathx.sinf(ba) * R * 1.02),
        0.10,
        0.14,
        7,
        STARVED,
    );
    crownInto(&b, &rng, v3(LEAN, H + 0.02, 0.18), R * 0.70, 11);
    b.setMat(.stone);
    art.chipsInto(&b, &rng, 0, 0, 1.8, 0.05, 0.15, 8);
    return b.toModel(shader);
}

pub const SAGDEAD_TOP: f32 = 6.10;

pub fn deadSaguaroMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5D_E5_03);
    const H: f32 = 5.80;
    const R: f32 = 0.36;
    const RIBS: i32 = 12;

    b.setMat(.plant);
    b.addBlob(v3(0, 0.24, 0), v3(R * 1.55, 0.50, R * 1.48), 3, 11, STARVED);
    b.setMat(.wood);
    var i: i32 = 0;
    while (i < RIBS) : (i += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, RIBS) + rng.signed() * 0.03;
        const snapped = i == 2 or i == 3 or i == 8;
        const top = if (snapped) rng.range(2.2, 3.6) else H * rng.range(0.90, 1.0);
                // NOTHING DEAD IS STRAIGHT: every rib bows out at the waist and splays where the flesh let go.
        const bow = rng.range(0.10, 0.22);
        const splay = if (snapped) rng.range(0.30, 0.62) else rng.range(0.14, 0.34);
        const p0 = v3(mathx.cosf(a) * R, 0.20, mathx.sinf(a) * R);
        const p1 = v3(mathx.cosf(a) * (R + bow), top * 0.5, mathx.sinf(a) * (R + bow));
        const p2 = v3(mathx.cosf(a) * (R + splay), top, mathx.sinf(a) * (R + splay));
        b.addCapsule(p0, p1, 0.040, 0.034, 5, if (rng.float() < 0.3) DEADTWIG else DEADWOOD);
        b.addCapsule(p1, p2, 0.034, 0.026, 5, DEADWOOD);
        b.addBlob(p2, v3(0.038, 0.030, 0.038), 2, 6, DEADTWIG);
        if (rng.float() < 0.42) {
            const t = rng.range(0.30, 0.80);
            const q = mathx.lerpV(p0, p2, t);
            const nx = mathx.cosf(a + 1.57);
            const nz = mathx.sinf(a + 1.57);
            b.addCapsule(q, v3(q.x + nx * 0.14, q.y + rng.signed() * 0.05, q.z + nz * 0.14), 0.020, 0.014, 4, DEADWOOD);
        }
    }
    var f: i32 = 0;
    while (f < 5) : (f += 1) {
        const a = rng.angle();
        const d0 = rng.range(0.5, 1.0);
        const l = rng.range(0.9, 2.1);
        b.addCapsule(
            v3(mathx.cosf(a) * d0, 0.045, mathx.sinf(a) * d0),
            v3(mathx.cosf(a) * (d0 + l), 0.035, mathx.sinf(a) * (d0 + l) + rng.signed() * 0.3),
            0.034,
            0.024,
            5,
            DEADWOOD,
        );
    }
    b.setMat(.stone);
    b.addBlob(v3(rng.signed() * 0.2, 0.10, rng.signed() * 0.2), v3(R * 1.3, 0.16, R * 1.2), 3, 9, DUNE_LT);
    art.chipsInto(&b, &rng, 0, 0, 1.3, 0.05, 0.13, 6);
    return b.toModel(shader);
}



pub const JOSH_TOP: f32 = 6.70;

fn rosetteInto(b: *Builder, r: *mathx.Rng, c: rl.Vector3, rad: f32, n: i32) void {
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const yaw = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n)) + r.signed() * 0.12;
        const dead = r.float() < 0.34;
        const pitch = if (dead) r.range(-0.95, -0.42) else r.range(0.28, 1.05);
        bladeInto(b, r, c, yaw, pitch, rad * r.range(0.78, 1.15), rad * 0.20, if (dead) DEADWOOD else CACTUS, if (dead) DEADTWIG else CACTUS_DK);
    }
}

pub fn joshuaMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5D_E5_04);

    b.setMat(.wood);
    b.addBlob(v3(0, 0.20, 0), v3(0.72, 0.36, 0.68), 3, 11, DEADTWIG);
    const fork = v3(rng.signed() * 0.12, 2.35, rng.signed() * 0.12);
    b.addCapsule(v3(0, 0.12, 0), fork, 0.40, 0.31, 11, art.BARK_OLD);
    var s: i32 = 0;
    while (s < 90) : (s += 1) {
        const t = rng.float();
        const a = rng.angle();
        const y = 0.30 + t * 2.0;
        const rr = mathx.lerpF(0.40, 0.31, t) * 1.02;
        bladeInto(
            &b,
            &rng,
            v3(mathx.cosf(a) * rr, y, mathx.sinf(a) * rr),
            a,
            rng.range(-1.25, -0.70),
            rng.range(0.20, 0.40),
            0.10,
            if (rng.float() < 0.4) DEADTWIG else DEADWOOD,
            DEADTWIG,
        );
        b.setMat(.wood);
    }

    var tips: [9]rl.Vector3 = undefined;
    var nt: usize = 0;
    var k: i32 = 0;
    while (k < 3) : (k += 1) {
        const a = std.math.tau * (@as(f32, @floatFromInt(k)) + 0.35) / 3.0;
        const mid = v3(fork.x + mathx.cosf(a) * 0.92, fork.y + rng.range(1.35, 1.75), fork.z + mathx.sinf(a) * 0.92);
        b.setMat(.wood);
        b.addCapsule(fork, mid, 0.30, 0.22, 9, art.BARK_OLD);
        var j: i32 = 0;
        const branches: i32 = if (k == 1) 2 else 3;
        while (j < branches) : (j += 1) {
            const a2 = a + (@as(f32, @floatFromInt(j)) - 1.0) * 0.95 + rng.signed() * 0.16;
            const tip = v3(mid.x + mathx.cosf(a2) * rng.range(0.55, 0.92), mid.y + rng.range(1.05, 1.60), mid.z + mathx.sinf(a2) * rng.range(0.55, 0.92));
            b.setMat(.wood);
            b.addCapsule(mid, tip, 0.22, 0.15, 9, if (rng.float() < 0.3) art.BARK_DK else art.BARK_OLD);
            if (nt < tips.len) {
                tips[nt] = tip;
                nt += 1;
            }
        }
    }
    for (tips[0..nt]) |t| rosetteInto(&b, &rng, t, 0.52, 15);
    b.setMat(.stone);
    art.chipsInto(&b, &rng, 0, 0, 1.6, 0.05, 0.14, 7);
    return b.toModel(shader);
}



pub const OCO_TOP: f32 = 5.50;
pub const OCO_SPREAD: f32 = 2.10;

pub fn ocotilloMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5D_E5_05);

    b.setMat(.wood);
    b.addBlob(v3(0, 0.20, 0), v3(0.42, 0.30, 0.40), 3, 11, DEADTWIG);
    const WH: i32 = 16;
    var i: i32 = 0;
    while (i < WH) : (i += 1) {
        const a = std.math.tau * (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, WH) + rng.signed() * 0.10;
        const dead = rng.float() < 0.26;
        const len = rng.range(3.5, 5.15) * (if (dead) @as(f32, 0.78) else 1.0);
        const splay = rng.range(0.06, 0.16);
        const col = if (dead) DEADWOOD else STARVED;
        var p = v3(mathx.cosf(a) * 0.20, 0.30, mathx.sinf(a) * 0.20);
        var out = splay;
        var yaw = a;
        var t: i32 = 0;
        b.setMat(.wood);
        while (t < 3) : (t += 1) {
            const seg = len / 3.0;
            yaw += rng.signed() * 0.16;
            const q = v3(
                p.x + mathx.cosf(yaw) * seg * out,
                p.y + seg * @sqrt(@max(1.0 - out * out, 0.10)),
                p.z + mathx.sinf(yaw) * seg * out,
            );
            const r0 = mathx.lerpF(0.075, 0.028, @as(f32, @floatFromInt(t)) / 3.0);
            const r1 = mathx.lerpF(0.075, 0.028, @as(f32, @floatFromInt(t + 1)) / 3.0);
            b.addCapsule(p, q, r0, r1, 6, col);
            var k: i32 = 0;
            while (k < 5) : (k += 1) {
                const u = (@as(f32, @floatFromInt(k)) + 0.5) / 5.0;
                const m = mathx.lerpV(p, q, u);
                const s = r1 * rng.range(0.9, 1.6);
                b.addBlob(v3(m.x + rng.signed() * s, m.y, m.z + rng.signed() * s), v3(s * 0.6, s * 0.6, s * 0.6), 2, 4, SPINE);
            }
            p = q;
                        // THE FAN COMES AFTER THE SEGMENT: grown first, the lowest joint already stands three quarters of a metre off the crown and the plant is a thicket at chest height.
            out += rng.range(0.14, 0.30) * (if (dead and t == 1) @as(f32, 2.2) else 1.0);
            if (t == 2) b.addBlob(p, v3(r1 * 1.25, r1 * 1.10, r1 * 1.25), 2, 6, if (dead) DEADTWIG else col);
        }
        if (!dead and rng.float() < 0.55) {
            b.setMat(.plant);
            var f: i32 = 0;
            while (f < 4) : (f += 1) {
                b.addBlob(
                    v3(p.x + rng.signed() * 0.07, p.y - @as(f32, @floatFromInt(f)) * 0.075, p.z + rng.signed() * 0.07),
                    v3(0.035, 0.055, 0.035),
                    2,
                    5,
                    art.BERRY,
                );
            }
            b.setMat(.wood);
        }
    }
    b.setMat(.stone);
    art.chipsInto(&b, &rng, 0, 0, 1.2, 0.04, 0.12, 6);
    return b.toModel(shader);
}



pub const AGAVE_TOP: f32 = 5.80;
pub const AGAVE_R: f32 = 1.30;

pub fn agaveMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5D_E5_06);

    b.setMat(.plant);
    b.addBlob(v3(0, 0.16, 0), v3(0.42, 0.26, 0.42), 3, 9, CACTUS_DK);
    const N: i32 = 19;
    var i: i32 = 0;
    while (i < N) : (i += 1) {
        const yaw = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, N) + rng.signed() * 0.09;
        const ring = @mod(i, 3);
        const pitch: f32 = switch (ring) {
            0 => rng.range(0.10, 0.34),
            1 => rng.range(0.48, 0.80),
            else => rng.range(0.92, 1.25),
        };
        const len = AGAVE_R * (switch (ring) {
            0 => rng.range(0.92, 1.10),
            1 => rng.range(0.78, 0.96),
            else => rng.range(0.58, 0.78),
        });
        const dying = ring == 0 and rng.float() < 0.40;
        bladeInto(
            &b,
            &rng,
            v3(mathx.cosf(yaw) * 0.16, 0.18, mathx.sinf(yaw) * 0.16),
            yaw,
            pitch,
            len,
            AGAVE_R * 0.26,
            if (dying) STARVED else CACTUS,
            CACTUS_DK,
        );
    }

    b.setMat(.wood);
    const top: f32 = 5.55;
    const lean: f32 = 0.30;
    b.addCapsule(v3(0, 0.30, 0), v3(lean * 0.4, top * 0.55, 0.06), 0.115, 0.085, 9, DEADWOOD);
    b.addCapsule(v3(lean * 0.4, top * 0.55, 0.06), v3(lean, top, 0.12), 0.085, 0.055, 9, DEADWOOD);
    b.addBlob(v3(lean, top, 0.12), v3(0.060, 0.050, 0.060), 2, 6, DEADTWIG);
    var k: i32 = 0;
    while (k < 9) : (k += 1) {
        const t = 0.52 + @as(f32, @floatFromInt(k)) / 9.0 * 0.44;
        const y = t * top;
        const a = @as(f32, @floatFromInt(k)) * 2.40;
        const reach = mathx.lerpF(0.86, 0.34, (t - 0.52) / 0.44);
        const root = v3(lean * mathx.clampF(y / top / 0.55, 0, 1) * 0.4 + (if (t > 0.55) (lean - lean * 0.4) * (t - 0.55) / 0.45 else 0), y, 0.06);
        const tip = v3(root.x + mathx.cosf(a) * reach, y + reach * 0.30, root.z + mathx.sinf(a) * reach);
        b.addCapsule(root, tip, 0.042, 0.026, 6, DEADWOOD);
        b.addBlob(tip, v3(0.055, 0.048, 0.055), 2, 6, DEADTWIG);
        var p: i32 = 0;
        while (p < 4) : (p += 1) {
            const u = 0.45 + @as(f32, @floatFromInt(p)) / 4.0 * 0.5;
            const m = mathx.lerpV(root, tip, u);
            b.addBlob(v3(m.x, m.y - 0.055, m.z), v3(0.038, 0.062, 0.038), 2, 5, if (rng.float() < 0.4) DEADTWIG else DEADWOOD);
        }
    }
    b.setMat(.stone);
    art.chipsInto(&b, &rng, 0, 0, 1.5, 0.04, 0.13, 6);
    return b.toModel(shader);
}



pub const YUCCA_TOP: f32 = 3.70;

pub fn yuccaMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5D_E5_07);
    const H: f32 = 2.35;

    b.setMat(.wood);
    b.addBlob(v3(0, 0.16, 0), v3(0.46, 0.28, 0.44), 3, 9, DEADTWIG);
    b.addCapsule(v3(0, 0.10, 0), v3(rng.signed() * 0.12, H, rng.signed() * 0.12), 0.30, 0.24, 11, art.BARK_OLD);
    var s: i32 = 0;
    while (s < 74) : (s += 1) {
        const t = rng.float();
        const a = rng.angle();
        const y = 0.22 + t * (H - 0.28);
        const rr = mathx.lerpF(0.30, 0.24, t) * 1.03;
        bladeInto(
            &b,
            &rng,
            v3(mathx.cosf(a) * rr, y, mathx.sinf(a) * rr),
            a,
            rng.range(-1.30, -0.75),
            rng.range(0.24, 0.46),
            0.09,
            if (rng.float() < 0.42) DEADTWIG else DEADWOOD,
            DEADTWIG,
        );
        b.setMat(.wood);
    }
    rosetteInto(&b, &rng, v3(rng.signed() * 0.12, H, rng.signed() * 0.12), 0.78, 22);

    b.setMat(.wood);
    const sp = v3(rng.signed() * 0.14, H + 1.25, rng.signed() * 0.14);
    b.addCapsule(v3(rng.signed() * 0.10, H + 0.10, rng.signed() * 0.10), sp, 0.055, 0.030, 7, DEADWOOD);
    var k: i32 = 0;
    while (k < 11) : (k += 1) {
        const t = @as(f32, @floatFromInt(k)) / 11.0;
        const a = @as(f32, @floatFromInt(k)) * 2.1;
        const y = H + 0.25 + t * 1.05;
        const reach = mathx.lerpF(0.26, 0.09, t);
        b.addBlob(
            v3(mathx.cosf(a) * reach, y, mathx.sinf(a) * reach),
            v3(0.042, 0.055, 0.042),
            2,
            5,
            if (rng.float() < 0.3) DEADTWIG else DEADWOOD,
        );
    }
    b.setMat(.stone);
    art.chipsInto(&b, &rng, 0, 0, 1.2, 0.04, 0.12, 6);
    return b.toModel(shader);
}



pub const CHOLLA_TOP: f32 = 2.05;

fn jointInto(b: *Builder, r: *mathx.Rng, a: rl.Vector3, c: rl.Vector3, rad: f32) void {
    b.setMat(.plant);
    b.addCapsule(a, c, rad, rad * 0.86, 9, if (r.float() < 0.24) STARVED else CACTUS);
    const ax = Axis.of(a, c);
    var i: i32 = 0;
    while (i < 26) : (i += 1) {
        const t = r.float() * ax.len;
        const ang = r.angle();
        const s = rad * r.range(0.24, 0.42);
        const q = Axis.at(ax, a, t, ang, rad * 1.05);
        b.addBlob(q, v3(s, s * 0.7, s), 2, 4, if (r.float() < 0.3) DEADWOOD else SPINE);
    }
}

pub fn chollaMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5D_E5_08);

    b.setMat(.wood);
    b.addCapsule(v3(0, 0.05, 0), v3(0, 0.55, 0), 0.16, 0.13, 9, DEADTWIG);
    var arms: [10]rl.Vector3 = undefined;
    var na: usize = 0;
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const a = std.math.tau * (@as(f32, @floatFromInt(i)) + 0.3) / 4.0;
        var p = v3(0, 0.50, 0);
        var yaw = a;
        var j: i32 = 0;
        const n: i32 = 2 + @as(i32, @intFromFloat(rng.range(0, 2.9)));
        while (j < n) : (j += 1) {
            yaw += rng.signed() * 0.55;
            const out = rng.range(0.22, 0.44);
            const up = rng.range(0.28, 0.46);
            const q = v3(p.x + mathx.cosf(yaw) * out, p.y + up, p.z + mathx.sinf(yaw) * out);
            jointInto(&b, &rng, p, q, mathx.lerpF(0.135, 0.085, @as(f32, @floatFromInt(j)) / 3.0));
            p = q;
        }
        if (na < arms.len) {
            arms[na] = p;
            na += 1;
        }
    }
    var f: i32 = 0;
    while (f < 6) : (f += 1) {
        const a = rng.angle();
        const d = rng.range(0.5, 1.5);
        const l = rng.range(0.18, 0.32);
        jointInto(&b, &rng, v3(mathx.cosf(a) * d, 0.09, mathx.sinf(a) * d), v3(mathx.cosf(a) * (d + l), 0.08, mathx.sinf(a) * (d + l)), 0.085);
    }
    b.setMat(.stone);
    art.chipsInto(&b, &rng, 0, 0, 1.1, 0.04, 0.11, 5);
    return b.toModel(shader);
}



pub const PEAR_TOP: f32 = 1.45;

pub fn pricklyPearMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5D_E5_09);

        // A PAD GROWS OFF THE RIM OF THE ONE BELOW IT, edge on — a stack of parallel plates reads as a cactus made of coins.
    const Pad = struct { c: rl.Vector3, yaw: f32, rad: f32 };
    var pads: [12]Pad = undefined;
    var n: usize = 0;
    var root: i32 = 0;
    while (root < 3) : (root += 1) {
        const base = std.math.tau * (@as(f32, @floatFromInt(root)) + 0.4) / 3.0;
        var p = Pad{ .c = v3(mathx.cosf(base) * 0.18, 0.26, mathx.sinf(base) * 0.18), .yaw = base, .rad = rng.range(0.30, 0.40) };
        var k: i32 = 0;
        const up: i32 = 2 + @as(i32, @intFromFloat(rng.range(0, 2.4)));
        while (k < up and n < pads.len) : (k += 1) {
            pads[n] = p;
            n += 1;
            const lean = rng.signed() * 0.55;
            p = .{
                .c = v3(p.c.x + mathx.cosf(p.yaw + 1.57) * p.rad * lean, p.c.y + p.rad * 1.42, p.c.z + mathx.sinf(p.yaw + 1.57) * p.rad * lean),
                .yaw = p.yaw + rng.signed() * 0.75,
                .rad = p.rad * rng.range(0.74, 0.94),
            };
        }
    }
    for (pads[0..n]) |p| {
        const cy = mathx.cosf(p.yaw);
        const sy = mathx.sinf(p.yaw);
        b.setMat(.plant);
        b.addBox(
            p.c,
            v3(cy * p.rad, 0, sy * p.rad),
            v3(0, p.rad * 1.25, 0),
            v3(-sy * p.rad * 0.20, 0, cy * p.rad * 0.20),
            if (rng.float() < 0.22) STARVED else CACTUS,
        );
        b.addBlob(v3(p.c.x, p.c.y + p.rad * 1.20, p.c.z), v3(cy * p.rad + 0.02, p.rad * 0.18, sy * p.rad + 0.02), 2, 7, CACTUS_LT);
        var s: i32 = 0;
        while (s < 14) : (s += 1) {
            const u = rng.signed();
            const w = rng.signed();
            const side: f32 = if (rng.float() < 0.5) 1 else -1;
            const at = v3(p.c.x + cy * u * p.rad * 0.85 - sy * side * p.rad * 0.22, p.c.y + w * p.rad * 1.05, p.c.z + sy * u * p.rad * 0.85 + cy * side * p.rad * 0.22);
            b.addBlob(at, v3(0.020, 0.020, 0.020), 2, 4, SPINE);
        }
        if (rng.float() < 0.42) {
            const at = v3(p.c.x + cy * rng.signed() * p.rad * 0.6, p.c.y + p.rad * 1.28, p.c.z + sy * rng.signed() * p.rad * 0.6);
            b.addBlob(at, v3(0.055, 0.075, 0.055), 2, 6, art.BERRY);
        }
    }
    return b.toModel(shader);
}

pub const BARREL_TOP: f32 = 1.00;

pub fn barrelCactusMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5D_E5_0A);

    const spec = [_][4]f32{ .{ 0, 0, 0.40, 0.86 }, .{ 0.78, -0.42, 0.27, 0.56 }, .{ -0.52, 0.62, 0.19, 0.38 } };
    for (spec) |s| {
        const cx = s[0];
        const cz = s[1];
        const rad = s[2];
        const h = s[3];
        b.setMat(.plant);
        b.addBlob(v3(cx, h * 0.5, cz), v3(rad, h * 0.52, rad), 5, 13, CACTUS);
        const RIBS: i32 = 13;
        var i: i32 = 0;
        while (i < RIBS) : (i += 1) {
            const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, RIBS);
            b.addCapsule(
                v3(cx + mathx.cosf(a) * rad * 0.99, 0.05, cz + mathx.sinf(a) * rad * 0.99),
                v3(cx + mathx.cosf(a) * rad * 0.42, h * 0.98, cz + mathx.sinf(a) * rad * 0.42),
                rad * 0.10,
                rad * 0.07,
                5,
                if (rng.float() < 0.26) STARVED else CACTUS_LT,
            );
            var t: f32 = 0.12;
            while (t < 0.94) : (t += 0.17) {
                const rr = mathx.lerpF(rad * 0.99, rad * 0.42, t) * 1.06;
                const sz = rad * rng.range(0.10, 0.17);
                b.addBlob(
                    v3(cx + mathx.cosf(a) * rr, t * h, cz + mathx.sinf(a) * rr),
                    v3(sz, sz * 0.8, sz),
                    2,
                    4,
                    if (rng.float() < 0.35) DEADWOOD else SPINE,
                );
            }
        }
        var k: i32 = 0;
        while (k < 7) : (k += 1) {
            const a = std.math.tau * (@as(f32, @floatFromInt(k)) + 0.5) / 7.0;
            b.addBlob(v3(cx + mathx.cosf(a) * rad * 0.30, h * 1.0, cz + mathx.sinf(a) * rad * 0.30), v3(0.055, 0.048, 0.055), 2, 6, BLOOM);
        }
    }
    return b.toModel(shader);
}

pub const BRUSH_TOP: f32 = 0.80;

pub fn deadBrushMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5D_E5_0B);

    b.setMat(.wood);
    var i: i32 = 0;
    while (i < 22) : (i += 1) {
        const a = rng.angle();
        const d0 = rng.range(0.02, 0.14);
        var p = v3(mathx.cosf(a) * d0, 0.02, mathx.sinf(a) * d0);
        var yaw = a;
        var pitch = rng.range(0.75, 1.30);
        var j: i32 = 0;
        const n: i32 = 2 + @as(i32, @intFromFloat(rng.range(0, 2.4)));
        var rad: f32 = rng.range(0.020, 0.034);
        while (j < n) : (j += 1) {
            yaw += rng.signed() * 0.95;
            pitch = mathx.clampF(pitch + rng.signed() * 0.42, 0.20, 1.45);
            const seg = rng.range(0.13, 0.28);
            const q = v3(p.x + mathx.cosf(yaw) * mathx.cosf(pitch) * seg, p.y + mathx.sinf(pitch) * seg, p.z + mathx.sinf(yaw) * mathx.cosf(pitch) * seg);
            b.addCapsule(p, q, rad, rad * 0.78, 4, if (rng.float() < 0.34) DEADWOOD else DEADTWIG);
            rad *= 0.78;
            p = q;
        }
        b.addBlob(p, v3(rad * 1.3, rad * 1.1, rad * 1.3), 2, 4, DEADTWIG);
    }
    b.setMat(.plant);
    var k: i32 = 0;
    while (k < 9) : (k += 1) {
        const a = rng.angle();
        const d = rng.range(0.10, 0.40);
        b.addBlob(v3(mathx.cosf(a) * d, rng.range(0.14, 0.62), mathx.sinf(a) * d), v3(0.045, 0.020, 0.030), 2, 5, STARVED);
    }
    return b.toModel(shader);
}

pub const TUMBLE_TOP: f32 = 0.92;

pub fn tumbleweedMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5D_E5_0C);
    const R: f32 = 0.44;

    b.setMat(.wood);
    var i: i32 = 0;
    while (i < 46) : (i += 1) {
        const a0 = rng.angle();
        const e0 = rng.range(-0.9, 1.35);
        const a1 = a0 + rng.signed() * 0.85;
        const e1 = mathx.clampF(e0 + rng.signed() * 0.80, -1.0, 1.45);
        const s0 = rng.range(0.30, 1.0);
        const s1 = rng.range(0.55, 1.0);
        const p = v3(mathx.cosf(e0) * mathx.cosf(a0) * R * s0, 0.40 + mathx.sinf(e0) * R * 0.78 * s0, mathx.cosf(e0) * mathx.sinf(a0) * R * s0);
        const q = v3(mathx.cosf(e1) * mathx.cosf(a1) * R * s1, 0.40 + mathx.sinf(e1) * R * 0.78 * s1, mathx.cosf(e1) * mathx.sinf(a1) * R * s1);
        b.addCapsule(
            v3(p.x, @max(p.y, 0.03), p.z),
            v3(q.x, @max(q.y, 0.03), q.z),
            rng.range(0.010, 0.020),
            rng.range(0.008, 0.015),
            4,
            if (rng.float() < 0.36) DEADWOOD else DEADTWIG,
        );
    }
    b.addCapsule(v3(0, 0.06, 0), v3(rng.signed() * 0.10, 0.02, rng.signed() * 0.10), 0.030, 0.020, 5, DEADWOOD);
    return b.toModel(shader);
}



/// A DUNE IS NOT A LOAF, AND IT IS NOT A RAMP EITHER. The lee falls at the angle of repose (33 deg) and the windward
/// back at well under half of it. A real dune's back is 11 deg over ten metres; 2.5 m of height over 13 is the shallowest back that still reads as a hill.
pub const DUNE_LEN: f32 = 15.0;
pub const DUNE_WID: f32 = 13.0;
pub const DUNE_H: f32 = 2.40;
pub const DUNE_TOP: f32 = 2.60;
/// The crest's z, measured from the middle: `DUNE_WID/2` less the lee's own run.
pub const DUNE_LEE: f32 = DUNE_H * 1.54;
pub const DUNE_CREST_Z: f32 = DUNE_WID * 0.5 - DUNE_LEE;

/// One station across the dune: what its height, its crest and its two faces are at this `x`.
const Station = struct { h: f32, crest: f32, lee: f32, wind: f32 };

fn stationAt(x: f32) Station {
    const along = mathx.clampF(1.0 - @abs(x) / (DUNE_LEN * 0.5), 0, 1);
    const fall = mathx.sinf(along * std.math.pi * 0.5);
    return .{
        .h = DUNE_H * fall,
        .crest = DUNE_CREST_Z * fall,
        .lee = DUNE_LEE * fall,
        .wind = DUNE_WID * 0.5 + DUNE_CREST_Z * fall,
    };
}

pub fn sandDuneMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5D_E5_0D);
    // At nineteen narrow stations the ellipsoids' own facets read as a row of tents: the mass has to be wider than the facet.
    const NX: i32 = 13;

        // A DUNE IS BLOBS, NOT PANELS: three rows per station, all centred at y = 0 so the bottom half is underground.
    b.setMat(.stone);
    const step = DUNE_LEN * 0.98 / @as(f32, @floatFromInt(NX));
    var i: i32 = 0;
    while (i < NX) : (i += 1) {
        const x = ((@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(NX)) - 0.5) * DUNE_LEN * 0.98;
        const st = stationAt(x);
        if (st.h < 0.06) continue;
        const crest = st.crest + mathx.sinf(x * 0.46) * 0.62 + rng.signed() * 0.14;
        const hx = step * 1.45;

        b.addBlob(
            v3(x, rng.signed() * 0.04, crest),
            v3(hx, st.h, st.lee * 1.00),
            6,
            17,
            if (rng.float() < 0.34) DUNE_LT else DUNE,
        );
        b.addBlob(
            v3(x, rng.signed() * 0.03, crest - st.wind * 0.45),
            v3(hx, st.h * 0.62, st.wind * 0.55),
            6,
            17,
            if (rng.float() < 0.24) DUNE_LT else DUNE,
        );
        b.addBlob(
            v3(x, 0, crest - st.wind * 0.78),
            v3(hx, st.h * 0.24, st.wind * 0.24),
            4,
            13,
            if (rng.float() < 0.30) DUNE_DK else DUNE,
        );
    }

    art.chipsInto(&b, &rng, -DUNE_LEN * 0.30, -DUNE_WID * 0.40, 1.8, 0.09, 0.22, 6);
    b.setMat(.wood);
    b.addCapsule(v3(DUNE_LEN * 0.28, 0.12, -DUNE_WID * 0.42), v3(DUNE_LEN * 0.28 + 0.95, 0.30, -DUNE_WID * 0.42 + 0.40), 0.045, 0.028, 5, DEADWOOD);
    return b.toModel(shader);
}

pub const RIPPLE_R: f32 = 2.60;

pub fn sandRipplesMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5D_E5_0E);

    // FINE SAND, SO THE RIPPLE IS FINE: 18 cm apart and 4 cm proud. Any coarser and the floor reads as gravel.
    b.setMat(.stone);
    const yaw = rng.range(-0.25, 0.25);
    const cy = mathx.cosf(yaw);
    const sy = mathx.sinf(yaw);
    var i: i32 = 0;
    while (i < 27) : (i += 1) {
        const t = (@as(f32, @floatFromInt(i)) + 0.5) / 27.0 * 2.0 - 1.0;
        const off = t * RIPPLE_R * 0.96;
        const half = RIPPLE_R * @sqrt(@max(1.0 - t * t, 0.02)) * rng.range(0.80, 1.0);
        var s: i32 = 0;
        while (s < 3) : (s += 1) {
            const u = (@as(f32, @floatFromInt(s)) - 1.0) / 3.0;
            const bow = (1.0 - u * u * 4.0) * RIPPLE_R * 0.05;
            const cx = -sy * (off + bow) + cy * u * half * 2.0;
            const cz = cy * (off + bow) + sy * u * half * 2.0;
            b.addBox(
                v3(cx, 0.018, cz),
                v3(cy * half * 0.36, rng.signed() * 0.006, sy * half * 0.36),
                v3(0, 0.018, 0),
                v3(-sy * 0.052, 0, cy * 0.052),
                if (@mod(i, 2) == 0) DUNE_LT else DUNE_DK,
            );
        }
    }
    var k: i32 = 0;
    while (k < 9) : (k += 1) {
        const a = rng.angle();
        const d = rng.range(0.2, 1.0) * RIPPLE_R;
        const rr = rng.range(0.035, 0.085);
        b.addBlob(v3(mathx.cosf(a) * d, rr * 0.35, mathx.sinf(a) * d), v3(rr, rr * 0.32, rr * rng.range(0.8, 1.3)), 2, 6, if (rng.float() < 0.4) DUNE_DK else DUNE_LT);
    }
    return b.toModel(shader);
}


test "the desert's flesh is DARK and its spines are the palest thing on it" {
    const lit = struct {
        fn f(c: rl.Color) f32 {
            return gfx.screenOf(@floatFromInt(c.g));
        }
    }.f;
    std.debug.print("\n  desert: cactus {d:.0} on screen, scrub {d:.0}, spine {d:.0}, deadwood {d:.0}\n", .{ lit(CACTUS), lit(art.SCRUB), lit(SPINE), lit(DEADWOOD) });
    try std.testing.expect(lit(CACTUS) < lit(art.SCRUB));
    try std.testing.expect(lit(SPINE) > lit(CACTUS) * 1.5);
    try std.testing.expect(lit(DEADWOOD) > lit(CACTUS));
    try std.testing.expect(STARVED.r > CACTUS.r and STARVED.r > STARVED.b * 2);
}

test "A DUNE IS NOT SYMMETRICAL — the slip face is at repose and the windward back is a third of it" {
    const wind = DUNE_WID * 0.5 + DUNE_CREST_Z;
    const lee = mathx.degrees(std.math.atan(DUNE_H / DUNE_LEE));
    const back = mathx.degrees(std.math.atan(DUNE_H / wind));
    std.debug.print("  dune: {d:.1} x {d:.1} x {d:.1} m; lee {d:.0} deg over {d:.1} m, windward {d:.0} deg over {d:.1} m\n", .{ DUNE_LEN, DUNE_WID, DUNE_H, lee, DUNE_LEE, back, wind });
    try std.testing.expect(lee > 28.0 and lee < 38.0);
    try std.testing.expect(back * 2.0 < lee);
    try std.testing.expect(DUNE_WID > DUNE_H * 5.0 and DUNE_H > 2.0);
    // Full height in the middle, nothing at either nose, and the two faces always meeting at the crest.
    const mid = stationAt(0);
    try std.testing.expectApproxEqAbs(DUNE_H, mid.h, 1e-4);
    try std.testing.expectApproxEqAbs(DUNE_CREST_Z, mid.crest, 1e-4);
    try std.testing.expectApproxEqAbs(DUNE_WID * 0.5, mid.crest + mid.lee, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 0), stationAt(DUNE_LEN * 0.5).h, 1e-3);
    try std.testing.expect(stationAt(DUNE_LEN * 0.25).h < DUNE_H);
}

test "every plant here is taller than it is wide, which is what water-starved looks like" {
    try std.testing.expect(SAG2_TOP > SAG_TOP and SAG_TOP > JOSH_TOP);
    try std.testing.expect(JOSH_TOP > SAGDEAD_TOP and SAGDEAD_TOP > AGAVE_TOP);
    try std.testing.expect(AGAVE_TOP > YUCCA_TOP and YUCCA_TOP > CHOLLA_TOP);
    try std.testing.expect(OCO_TOP > OCO_SPREAD * 2.0);
    try std.testing.expect(AGAVE_TOP > AGAVE_R * 3.0);
    std.debug.print("  desert heights: saguaro {d:.1}/{d:.1} dead {d:.1} joshua {d:.1} ocotillo {d:.1} agave {d:.1} yucca {d:.1}\n", .{ SAG_TOP, SAG2_TOP, SAGDEAD_TOP, JOSH_TOP, OCO_TOP, AGAVE_TOP, YUCCA_TOP });
}
