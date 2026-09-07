const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const art = @import("propart.zig");
const gold = @import("propgold.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// SOLVE IT, DO NOT GUESS IT (AGENTS.md): screen = 255 x (albedo x 1.72)^(1/2.2). The body wants to read PALER
// than the Gilded Ruins' ashlar (188) and far warmer, because it stands on orange sand: 196/172/138.
pub const SAND = rgba(83, 62, 38, 255);
pub const SAND_LT = rgba(101, 79, 52, 255);
pub const SAND_DK = rgba(46, 33, 19, 255);
/// The SAME stone with the desert's mark on it — iron run down a face over centuries, not a second material. Solved to 128/92/66, two thirds the body's screen value and twice its warmth.
pub const IRONWASH = rgba(33, 16, 8, 255);

/// **THE JEWEL IS A LIGHT, NOT A COLOUR.** Alpha is the EMISSIVE channel (`1 - a/255`), so the heart of a stone is the LOWEST number here. Solved to 40/190/120, 14/124/76 and 128/238/180.
pub const EMERALD = rgba(3, 78, 28, 210);
pub const EMERALD_DK = rgba(0, 30, 10, 238);
pub const EMERALD_LT = rgba(33, 127, 69, 150);

/// **GOLD ON PALE STONE IS NOT GOLD ON GREY STONE.** `propgold.GOLD` was solved to sit a hair UNDER the Gilded
/// Ruins' ashlar at 178; against sandstone at 196 that same leaf reads as a SHADOW LINE, and every band on the
/// spire came back a dark seam. Solved OVER the body instead — 216/176/96, brighter in red and far less blue,
/// so it separates on value and on hue at once. It is the same metal, lit by a desert.
pub const PGOLD = rgba(103, 66, 17, 255);
pub const PGOLD_LT = rgba(123, 87, 33, 255);
pub const PGOLD_DK = rgba(61, 33, 7, 255);

/// Deep green, gold-bordered. A banner is cloth in its own shade: 86/140/112.
pub const BANNER = rgba(14, 40, 24, 255);
pub const BANNER_DK = rgba(6, 19, 12, 255);

/// The colour the palace's own emeralds throw. Every light in this family is this one.
pub const GEM_LIGHT = v3(0.20, 0.76, 0.46);

/// **THE PALACE IS THE GILDED RUINS' ORNAMENT IN THE DESERT'S STONE.** One muqarnas, one band, one ring, one
/// star (`propart`); what makes this family its own is this row and the three motifs below it.
pub const SUN: art.Tone = .{
    .stone = SAND,
    .stoneLt = SAND_LT,
    .stoneDk = SAND_DK,
    .burn = IRONWASH,
    .gold = PGOLD,
    .goldLt = PGOLD_LT,
    .goldDk = PGOLD_DK,
};

/// **THE FAMILY'S PLAN IS AN OCTAGON**, the Gilded Ruins' own — the two are one architecture at two scales, so it is that number and not a second copy of it.
pub const OCTAGON: i32 = gold.OCTAGON;
const HORSE_EXTRA: f32 = 30.0;

fn stoneTone(r: *mathx.Rng) rl.Color {
    return SUN.stoneOf(r);
}

fn goldTone(r: *mathx.Rng) rl.Color {
    return SUN.goldOf(r);
}

fn gemTone(r: *mathx.Rng) rl.Color {
    const f = r.float();
    if (f < 0.26) return EMERALD_LT;
    if (f < 0.52) return EMERALD_DK;
    return EMERALD;
}



/// **THE GRECA IS ONE LINE THAT NEVER CROSSES ITSELF** — Mitla's stepped fret. Two continuous rails with a meander between them; broken into separate keys it reads as a row of blocks.
fn grecaInto(b: *Builder, r: *mathx.Rng, a: rl.Vector3, c: rl.Vector3, face: rl.Vector3, h: f32, out: f32, gild: f32) void {
    const span = mathx.subV(c, a);
    const len = mathx.lenV(span);
    if (len < h * 1.2) return;
    const u = mathx.normV(span);
    const f = mathx.normV(v3(face.x, 0, face.z));
    const rail = h * 0.19;
    const mid = v3((a.x + c.x) * 0.5, 0, (a.z + c.z) * 0.5);

    b.setMat(.stone);
    for ([_]f32{ rail * 0.5, h - rail * 0.5 }) |ry| {
        b.addBox(
            v3(mid.x + f.x * out * 0.5, a.y + ry, mid.z + f.z * out * 0.5),
            v3(u.x * len * 0.5, 0, u.z * len * 0.5),
            v3(0, rail * 0.5, 0),
            v3(f.x * out * 0.5, 0, f.z * out * 0.5),
            SAND_LT,
        );
    }

    // ONE REPEAT PER BAND HEIGHT. At a third of that the keys are finer than the course they sit on and
    // the whole frieze greys out at twenty metres.
    const cells: i32 = @max(2, @as(i32, @intFromFloat(len / (h * 1.05))));
    const cell = len / @as(f32, @floatFromInt(cells));
    const inner = h - rail * 2.0;
    var i: i32 = 0;
    while (i < cells) : (i += 1) {
        const s0 = -len * 0.5 + @as(f32, @floatFromInt(i)) * cell;
        const up = @mod(i, 2) == 0;
        const leaf = r.float() < gild;
        b.setMat(if (leaf) .gilt else .stone);
        const col = if (leaf) goldTone(r) else stoneTone(r);
        const bar = inner * 0.30;

        const rs = s0 + cell * 0.20;
        b.addBox(
            v3(mid.x + u.x * rs + f.x * out * 0.5, a.y + h * 0.5, mid.z + u.z * rs + f.z * out * 0.5),
            v3(u.x * bar * 0.5, 0, u.z * bar * 0.5),
            v3(0, inner * 0.5, 0),
            v3(f.x * out * 0.5, 0, f.z * out * 0.5),
            col,
        );
        const ty = if (up) a.y + rail + inner * 0.78 else a.y + rail + inner * 0.22;
        const t0 = rs + bar * 0.5;
        const t1 = s0 + cell * 0.86;
        b.addBox(
            v3(mid.x + u.x * (t0 + t1) * 0.5 + f.x * out * 0.5, ty, mid.z + u.z * (t0 + t1) * 0.5 + f.z * out * 0.5),
            v3(u.x * (t1 - t0) * 0.5, 0, u.z * (t1 - t0) * 0.5),
            v3(0, bar * 0.5, 0),
            v3(f.x * out * 0.5, 0, f.z * out * 0.5),
            col,
        );
    }
}

/// **THE SUN SIGN IS FOUR GROUPS OF FOUR** — the Zia, and the badge this whole place wears. The two inner rays
/// of a group are the long ones; a group with equal rays reads as a compass rose.
fn ziaInto(b: *Builder, r: *mathx.Rng, c: rl.Vector3, face: rl.Vector3, radius: f32, out: f32) void {
    const t = SUN;
    const f = mathx.normV(v3(face.x, 0, face.z));
    const s = v3(-f.z, 0, f.x);
    const put = struct {
        fn at(cc: rl.Vector3, sv: rl.Vector3, across: f32, rise: f32, fv: rl.Vector3, o: f32) rl.Vector3 {
            return v3(cc.x + sv.x * across + fv.x * o, cc.y + rise, cc.z + sv.z * across + fv.z * o);
        }
    }.at;

    const RING: i32 = 18;
    b.setMat(.gilt);
    var i: i32 = 0;
    while (i < RING) : (i += 1) {
        const a0 = std.math.tau * (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, RING);
        const half = std.math.tau * radius / @as(f32, RING) * 0.52;
        const tx = -mathx.sinf(a0);
        const ty = mathx.cosf(a0);
        b.addBox(
            put(c, s, mathx.cosf(a0) * radius, mathx.sinf(a0) * radius, f, out * 0.5),
            v3(s.x * tx * half, ty * half, s.z * tx * half),
            v3(s.x * ty * radius * 0.055, -tx * radius * 0.055, s.z * ty * radius * 0.055),
            v3(f.x * out * 0.5, 0, f.z * out * 0.5),
            goldTone(r),
        );
    }

    var g: i32 = 0;
    while (g < 4) : (g += 1) {
        const base = std.math.pi * 0.5 * @as(f32, @floatFromInt(g));
        var k: i32 = 0;
        while (k < 4) : (k += 1) {
            const fk = @as(f32, @floatFromInt(k));
            const a = base + mathx.radians((fk - 1.5) * 9.0);
            const long = k == 1 or k == 2;
            const reach = radius * (if (long) @as(f32, 0.95) else 0.66) * r.range(0.94, 1.04);
            const r0 = radius * 1.06;
            const rm = r0 + reach * 0.5;
            const w = radius * 0.105;
            b.setMat(.gilt);
            b.addBox(
                put(c, s, mathx.cosf(a) * rm, mathx.sinf(a) * rm, f, out * 0.42),
                v3(s.x * mathx.cosf(a) * reach * 0.5, mathx.sinf(a) * reach * 0.5, s.z * mathx.cosf(a) * reach * 0.5),
                v3(-s.x * mathx.sinf(a) * w, mathx.cosf(a) * w, -s.z * mathx.sinf(a) * w),
                v3(f.x * out * 0.42, 0, f.z * out * 0.42),
                goldTone(r),
            );
        }
    }

    // THE BOSS IS A COLLAR WITH A STONE IN IT. Sunk deepest and widest, the masonry dome swallows the jewel
    // it holds and the sun comes back with a black hole in the middle of it.
    b.setMat(.stone);
    b.addDome(v3(c.x + f.x * out * 0.12, c.y, c.z + f.z * out * 0.12), f, radius * 0.44, 12, SAND_DK);
    b.setMat(.gilt);
    b.addDome(v3(c.x + f.x * out * 0.34, c.y, c.z + f.z * out * 0.34), f, radius * 0.36, 12, t.goldOf(r));
    b.setMat(.marble);
    b.addDome(v3(c.x + f.x * out * 0.72, c.y, c.z + f.z * out * 0.72), f, radius * 0.30, 10, EMERALD);
    b.addDome(v3(c.x + f.x * out * 1.05, c.y, c.z + f.z * out * 1.05), f, radius * 0.16, 8, EMERALD_LT);
}

/// A PECKED PANEL. Sunk FIRST: a figure proud of a flat face reads as tile, so every motif stands proud of the sinking.
fn glyphBandInto(b: *Builder, r: *mathx.Rng, a: rl.Vector3, c: rl.Vector3, face: rl.Vector3, h: f32, out: f32) void {
    const span = mathx.subV(c, a);
    const len = mathx.lenV(span);
    if (len < h) return;
    const u = mathx.normV(span);
    const f = mathx.normV(v3(face.x, 0, face.z));
    const mid = v3((a.x + c.x) * 0.5, 0, (a.z + c.z) * 0.5);

    b.setMat(.stone);
    b.addBox(
        v3(mid.x + f.x * out * 0.35, a.y + h * 0.5, mid.z + f.z * out * 0.35),
        v3(u.x * len * 0.5, 0, u.z * len * 0.5),
        v3(0, h * 0.5, 0),
        v3(f.x * out * 0.35, 0, f.z * out * 0.35),
        IRONWASH,
    );

    const dot = struct {
        fn at(bb: *Builder, o: rl.Vector3, uu: rl.Vector3, ff: rl.Vector3, across: f32, rise: f32, w: f32, tall: f32, oo: f32, col: rl.Color) void {
            bb.addBox(
                v3(o.x + uu.x * across + ff.x * oo, o.y + rise, o.z + uu.z * across + ff.z * oo),
                v3(uu.x * w, 0, uu.z * w),
                v3(0, tall, 0),
                v3(ff.x * oo, 0, ff.z * oo),
                col,
            );
        }
    }.at;

    const n: i32 = @max(1, @as(i32, @intFromFloat(len / (h * 0.92))));
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        if (r.float() < 0.14) continue;
        const s = -len * 0.5 + (@as(f32, @floatFromInt(i)) + 0.5) * (len / @as(f32, @floatFromInt(n)));
        const o = v3(mid.x + u.x * s, a.y + h * 0.5, mid.z + u.z * s);
        const col = if (r.float() < 0.30) SAND_LT else SAND;
        const e = h * 0.11;
        const oo = out * 0.62;
        switch (@mod(@as(i32, @intFromFloat(r.float() * 4.0)), 4)) {
            0 => { // a body: one bar, a head, arms down and legs apart
                dot(b, o, u, f, 0, 0, e * 0.30, h * 0.20, oo, col);
                dot(b, o, u, f, 0, h * 0.26, e * 0.62, e * 0.55, oo, col);
                dot(b, o, u, f, 0, h * 0.06, e * 1.35, e * 0.24, oo, col);
                dot(b, o, u, f, -e * 0.75, -h * 0.20, e * 0.24, h * 0.12, oo, col);
                dot(b, o, u, f, e * 0.75, -h * 0.20, e * 0.24, h * 0.12, oo, col);
            },
            1 => { // a spiral, walked outward
                var k: i32 = 0;
                var ang: f32 = 0;
                while (k < 9) : (k += 1) {
                    const rad = e * 0.24 + @as(f32, @floatFromInt(k)) * e * 0.16;
                    dot(b, o, u, f, mathx.cosf(ang) * rad, mathx.sinf(ang) * rad, e * 0.20, e * 0.20, oo, col);
                    ang += 0.86;
                }
            },
            2 => { // a hand
                dot(b, o, u, f, 0, -h * 0.08, e * 0.70, e * 0.62, oo, col);
                var k: i32 = 0;
                while (k < 4) : (k += 1) {
                    const fx = (@as(f32, @floatFromInt(k)) - 1.5) * e * 0.42;
                    dot(b, o, u, f, fx, h * 0.10, e * 0.16, e * 0.46, oo, col);
                }
                dot(b, o, u, f, 0, -h * 0.26, e * 0.22, h * 0.10, oo, col);
            },
            else => { // a snake, or water: five bars stepped
                var k: i32 = 0;
                while (k < 5) : (k += 1) {
                    const fk = @as(f32, @floatFromInt(k));
                    dot(b, o, u, f, (fk - 2.0) * e * 0.62, (if (@mod(k, 2) == 0) @as(f32, 1) else -1) * e * 0.42, e * 0.36, e * 0.18, oo, col);
                }
            },
        }
    }
}

/// A PIERCED SCREEN; `hw`/`hh` are half-extents in the (across, up) plane.
fn jaliInto(b: *Builder, r: *mathx.Rng, c: rl.Vector3, face: rl.Vector3, hw: f32, hh: f32, thick: f32, pitch: f32) void {
    const f = mathx.normV(v3(face.x, 0, face.z));
    const s = v3(-f.z, 0, f.x);
    const bar = thick * 0.34;
    b.setMat(.stone);
    for ([_]f32{ 45.0, -45.0 }) |deg| {
        const a = mathx.radians(deg);
        const ca = mathx.cosf(a);
        const sa = mathx.sinf(a);
        const reach = @sqrt(hw * hw + hh * hh);
        const n: i32 = @max(2, @as(i32, @intFromFloat(reach * 2.0 / pitch)));
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const t = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(n)) * 2.0 - 1.0;
            const px = -sa * t * reach;
            const py = ca * t * reach;
            if (@abs(px) > hw * 0.98 or @abs(py) > hh * 0.98) continue;
            const half = @min(hw - @abs(px), hh - @abs(py)) * 1.15;
            b.addBox(
                v3(c.x + s.x * px, c.y + py, c.z + s.z * px),
                v3(s.x * ca * half, sa * half, s.z * ca * half),
                v3(-s.x * sa * bar, ca * bar, -s.z * sa * bar),
                v3(f.x * thick * 0.5, 0, f.z * thick * 0.5),
                if (r.float() < 0.22) SAND_LT else SAND,
            );
        }
    }
    for ([_][4]f32{ .{ 0, hh, hw, thick * 0.6 }, .{ 0, -hh, hw, thick * 0.6 }, .{ -hw, 0, thick * 0.6, hh }, .{ hw, 0, thick * 0.6, hh } }) |q| {
        b.addBox(
            v3(c.x + s.x * q[0], c.y + q[1], c.z + s.z * q[0]),
            v3(s.x * q[2], 0, s.z * q[2]),
            v3(0, q[3], 0),
            v3(f.x * thick * 0.9, 0, f.z * thick * 0.9),
            stoneTone(r),
        );
    }
}

/// A CUT STONE IN ITS COLLET: two bands of eight is an octahedron with the girdle rounded off, not a ball.
fn gemInto(b: *Builder, r: *mathx.Rng, c: rl.Vector3, rad: f32) void {
    b.setMat(.gilt);
    var i: i32 = 0;
    while (i < 8) : (i += 1) {
        const a = std.math.tau * (@as(f32, @floatFromInt(i)) + 0.5) / 8.0;
        b.addBox(
            v3(c.x + mathx.cosf(a) * rad * 0.94, c.y - rad * 0.30, c.z + mathx.sinf(a) * rad * 0.94),
            v3(-mathx.sinf(a) * rad * 0.42, 0, mathx.cosf(a) * rad * 0.42),
            v3(0, rad * 0.30, 0),
            v3(mathx.cosf(a) * rad * 0.16, 0, mathx.sinf(a) * rad * 0.16),
            goldTone(r),
        );
    }
    b.setMat(.marble);
    b.addBlob(c, v3(rad, rad * 0.92, rad), 2, 8, EMERALD);
    b.addBlob(v3(c.x, c.y + rad * 0.06, c.z), v3(rad * 0.52, rad * 0.50, rad * 0.52), 2, 8, EMERALD_LT);
}

/// A BERYL: a six-sided prism with a shallow pyramid on it. `dir` need not be plumb and mostly should not be.
fn crystalInto(b: *Builder, r: *mathx.Rng, base: rl.Vector3, dir: rl.Vector3, len: f32, rad: f32) void {
    const d = mathx.normV(dir);
    const tip = v3(base.x + d.x * len, base.y + d.y * len, base.z + d.z * len);
    const shoulder = v3(base.x + d.x * (len - rad * 1.15), base.y + d.y * (len - rad * 1.15), base.z + d.z * (len - rad * 1.15));
    b.setMat(.marble);
    b.addCylinder(base, shoulder, rad, rad * 0.94, 6, if (r.float() < 0.34) EMERALD_DK else EMERALD);
    b.addCylinder(shoulder, tip, rad * 0.94, rad * 0.26, 6, EMERALD_LT);
    b.addDome(tip, d, rad * 0.26, 6, EMERALD_LT);
    b.setMat(.gilt);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const a = r.angle();
        const up = r.range(0.05, 0.42) * len;
        const rr = rad * r.range(0.10, 0.24);
        b.addBlob(
            v3(base.x + d.x * up + mathx.cosf(a) * rad * 0.95, base.y + d.y * up, base.z + d.z * up + mathx.sinf(a) * rad * 0.95),
            v3(rr, rr * 0.7, rr),
            2,
            6,
            goldTone(r),
        );
    }
}

/// **TALUD-TABLERO: A BATTERED SKIRT UNDER A PANEL THAT OVERSAILS IT** — the whole silhouette here is this profile stacked. Returns the height it left off at.
fn taludInto(b: *Builder, r: *mathx.Rng, cx: f32, cz: f32, y0: f32, half: f32, talud: f32, tablero: f32, batter: f32, gild: f32) f32 {
    const courses: i32 = @max(3, @as(i32, @intFromFloat(talud / 0.55)));
    const top = art.courseStack(b, r, cx, y0, cz, half * 2.0, half * 2.0, talud / @as(f32, @floatFromInt(courses)), courses, batter, SUN);
    const inner = half * (1.0 - batter * 0.5);

    b.setMat(.stone);
    b.addCube(v3(cx, top + tablero * 0.5, cz), v3(inner * 2.14, tablero, inner * 2.14), SAND_DK);
    for ([_][2]f32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }) |sg| {
        const face = v3(sg[0], 0, sg[1]);
        const along = v3(-sg[1], 0, sg[0]);
        const c0 = v3(cx - along.x * inner * 0.94 + sg[0] * inner * 1.07, top + tablero * 0.18, cz - along.z * inner * 0.94 + sg[1] * inner * 1.07);
        const c1 = v3(cx + along.x * inner * 0.94 + sg[0] * inner * 1.07, top + tablero * 0.18, cz + along.z * inner * 0.94 + sg[1] * inner * 1.07);
        grecaInto(b, r, c0, c1, face, tablero * 0.62, 0.16, gild);
    }
    b.setMat(.stone);
    b.addCube(v3(cx, top + tablero + 0.13, cz), v3(inner * 2.32, 0.26, inner * 2.32), stoneTone(r));
    art.giltBandInto(b, r, cx, top + tablero + 0.13, cz, inner * 1.17, inner * 1.17, 0.19, SUN);
    return top + tablero + 0.26;
}

/// `springY` is the impost; the ring carries PAST the semicircle and tucks back under itself. `gone0`/`gone1` are the voussoirs the centuries took.
fn horseshoeInto(b: *Builder, r: *mathx.Rng, cx: f32, cz: f32, springY: f32, radius: f32, depth: f32, gone0: i32, gone1: i32) void {
    const span = 180.0 + HORSE_EXTRA * 2.0;
    const NV: i32 = 25;
    var i: i32 = 0;
    while (i < NV) : (i += 1) {
        if (i >= gone0 and i <= gone1) continue;
        const t = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, NV);
        const a = mathx.radians(-HORSE_EXTRA + span * t);
        const ca = mathx.cosf(a);
        const sa = mathx.sinf(a);
        const half = mathx.radians(span) * radius / @as(f32, NV) * 0.5 * r.range(1.03, 1.16);
        const key = i == NV / 2;
        const rad = radius * 0.17 * (if (key) @as(f32, 1.30) else r.range(0.90, 1.08));
        const cr = radius + rad * 0.10;
        const gilded = @mod(i, 2) == 0 and r.float() < 0.72;
        b.setMat(if (gilded) .gilt else .stone);
        b.addBox(
            v3(cx - ca * cr, springY + sa * cr, cz + r.signed() * 0.02),
            v3(sa * half, ca * half, 0),
            v3(-ca * rad, sa * rad, 0),
            v3(0, 0, depth * (if (key) @as(f32, 1.10) else 1.0)),
            if (gilded) goldTone(r) else stoneTone(r),
        );
    }
}



pub const SPIRE_BASE: f32 = 5.40;
pub const SPIRE_SHAFT: f32 = 26.0;
pub const SPIRE_TOP: f32 = 36.1;
const SPIRE_SIDES: i32 = OCTAGON;

pub fn sunSpireMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A_11_01);

    // THREE STAGES, EACH A FULL TALUD-TABLERO. Two thin plates under a long shaft is a chimney; the mass
    // has to climb in steps you could walk round before the tower starts.
    var y = taludInto(&b, &rng, 0, 0, 0, SPIRE_BASE, 2.60, 1.30, 0.14, 0.32);
    y = taludInto(&b, &rng, 0, 0, y, 4.20, 2.30, 1.15, 0.13, 0.46);
    y = taludInto(&b, &rng, 0, 0, y, 3.10, 2.00, 1.00, 0.12, 0.60);

    // THE SHEAR IS ONE PLANE, NOT A NIBBLE — three of the eight sides stop 4 m short and the break runs across them.
    const shearFrom: i32 = 2;
    const shearTo: i32 = 4;
    const CH: f32 = 0.80;
    const y0 = y;
    while (y < SPIRE_SHAFT) : (y += CH) {
        const t = (y - y0) / (SPIRE_SHAFT - y0);
        const rr = 2.95 * (1.0 - 0.24 * t);
        var s: i32 = 0;
        while (s < SPIRE_SIDES) : (s += 1) {
            const sheared = s >= shearFrom and s <= shearTo;
            if (sheared and y > SPIRE_SHAFT - 4.2 - @as(f32, @floatFromInt(s - shearFrom)) * 0.9) continue;
            const a0 = std.math.tau * @as(f32, @floatFromInt(s)) / @as(f32, SPIRE_SIDES);
            const a1 = std.math.tau * @as(f32, @floatFromInt(s + 1)) / @as(f32, SPIRE_SIDES);
            const na = (a0 + a1) * 0.5;
            const half = mathx.sinf((a1 - a0) * 0.5) * rr * 1.05;
            b.setMat(.stone);
            b.addBox(
                v3(mathx.cosf(na) * rr, y + CH * 0.5, mathx.sinf(na) * rr),
                v3(-mathx.sinf(na) * half, rng.signed() * 0.008, mathx.cosf(na) * half),
                v3(0, CH * 0.5 * rng.range(0.96, 1.05), 0),
                v3(mathx.cosf(na) * 0.30, 0, mathx.sinf(na) * 0.30),
                stoneTone(&rng),
            );
        }
        const band = @as(i32, @intFromFloat((y - y0) / CH));
        if (@mod(band, 5) == 3) {
            var g: i32 = 0;
            while (g < SPIRE_SIDES) : (g += 1) {
                if (g >= shearFrom and g <= shearTo and y > SPIRE_SHAFT - 5.0) continue;
                const a0 = std.math.tau * @as(f32, @floatFromInt(g)) / @as(f32, SPIRE_SIDES);
                const a1 = std.math.tau * @as(f32, @floatFromInt(g + 1)) / @as(f32, SPIRE_SIDES);
                const na = (a0 + a1) * 0.5;
                const half = mathx.sinf((a1 - a0) * 0.5) * rr;
                grecaInto(
                    &b,
                    &rng,
                    v3(mathx.cosf(na) * rr - mathx.sinf(na) * half * 0.9, y + 0.08, mathx.sinf(na) * rr + mathx.cosf(na) * half * 0.9),
                    v3(mathx.cosf(na) * rr + mathx.sinf(na) * half * 0.9, y + 0.08, mathx.sinf(na) * rr - mathx.cosf(na) * half * 0.9),
                    v3(mathx.cosf(na), 0, mathx.sinf(na)),
                    CH * 0.88,
                    0.22,
                    0.62,
                );
            }
        }
        if (@mod(band, 9) == 7) {
            const a = rng.angle();
            glyphBandInto(
                &b,
                &rng,
                v3(mathx.cosf(a) * rr * 1.0 - mathx.sinf(a) * 0.62, y + 0.10, mathx.sinf(a) * rr * 1.0 + mathx.cosf(a) * 0.62),
                v3(mathx.cosf(a) * rr * 1.0 + mathx.sinf(a) * 0.62, y + 0.10, mathx.sinf(a) * rr * 1.0 - mathx.cosf(a) * 0.62),
                v3(mathx.cosf(a), 0, mathx.sinf(a)),
                CH * 0.82,
                0.18,
            );
        }
    }

    const gr: f32 = 2.30;
    var q: i32 = 0;
    while (q < SPIRE_SIDES) : (q += 1) {
        const a = std.math.tau * (@as(f32, @floatFromInt(q)) + 0.5) / @as(f32, SPIRE_SIDES);
        art.muqarnasInto(&b, &rng, v3(mathx.cosf(a) * gr * 0.86, SPIRE_SHAFT - 1.55, mathx.sinf(a) * gr * 0.86), v3(mathx.cosf(a), 0, mathx.sinf(a)), 1.42, 1.55, 0.78, SUN);
    }
    b.setMat(.stone);
    b.addCube(v3(0, SPIRE_SHAFT + 0.22, 0), v3(gr * 2.9, 0.44, gr * 2.9), SAND_LT);
    art.giltRingInto(&b, &rng, 0, SPIRE_SHAFT + 0.72, 0, gr * 1.44, 0.86, SPIRE_SIDES, SUN);

    var c: i32 = 0;
    var cy = SPIRE_SHAFT + 1.15;
    var cr2: f32 = 2.05;
    while (c < 5) : (c += 1) {
        b.setMat(.stone);
        b.addCube(v3(rng.signed() * 0.02, cy + 0.45, rng.signed() * 0.02), v3(cr2 * 2.0, 0.90, cr2 * 2.0), stoneTone(&rng));
        art.giltBandInto(&b, &rng, 0, cy + 0.45, 0, cr2 * 1.02, cr2 * 1.02, 0.42, SUN);
        cy += 0.90;
        cr2 *= 0.80;
    }
    b.setMat(.gilt);
    b.addCylinder(v3(0, cy, 0), v3(0, cy + 0.95, 0), 0.52, 0.36, 8, PGOLD_LT);
    gemInto(&b, &rng, v3(0, cy + 2.60, 0), 1.90);

    b.setMat(.stone);
    var f: i32 = 0;
    while (f < 3) : (f += 1) {
        const a = std.math.tau * (@as(f32, @floatFromInt(shearFrom + f)) + 0.5) / @as(f32, SPIRE_SIDES);
        const d = rng.range(5.6, 8.4);
        b.addBox(
            v3(mathx.cosf(a) * d, rng.range(0.14, 0.26), mathx.sinf(a) * d),
            v3(rng.range(0.55, 0.95), rng.signed() * 0.10, rng.signed() * 0.20),
            v3(rng.signed() * 0.14, rng.range(0.13, 0.22), 0),
            v3(rng.signed() * 0.16, 0, rng.range(0.42, 0.78)),
            stoneTone(&rng),
        );
    }
    art.chipsInto(&b, &rng, 0, 0, SPIRE_BASE * 1.6, 0.12, 0.34, 16);
    return b.toModel(shader);
}



pub const GATE_PIER_X: f32 = 6.90;
pub const GATE_PIER_HALF: f32 = 2.20;
pub const GATE_SPRING: f32 = 11.6;
/// The ring springs off the piers' INNER FACES, or the arch hangs in the air two metres short of them.
pub const GATE_R: f32 = GATE_PIER_X - GATE_PIER_HALF;
pub const GATE_WALL_TOP: f32 = 26.0;
pub const GATE_TOP: f32 = 27.6;

pub fn sunGateMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A_11_02);

    for ([_]f32{ -GATE_PIER_X, GATE_PIER_X }) |x| {
        const lost: f32 = if (x > 0) 1.30 else 0; // the east pier lost its top courses
        b.setMat(.stone);
        b.addCube(v3(x, 0.26, 0), v3(GATE_PIER_HALF * 2.5, 0.52, GATE_PIER_HALF * 2.5), SAND_DK);
        const top = art.courseStack(&b, &rng, x, 0.52, 0, GATE_PIER_HALF * 2.0, GATE_PIER_HALF * 2.0, 0.94, @as(i32, @intFromFloat((GATE_SPRING - 0.52 - lost) / 0.94)), 0.07, SUN);
        for ([_][2]f32{ .{ 0, 1 }, .{ 0, -1 } }) |sg| {
            const face = v3(0, 0, sg[1]);
            grecaInto(
                &b,
                &rng,
                v3(x - GATE_PIER_HALF * 0.88, 3.10, sg[1] * GATE_PIER_HALF * 0.99),
                v3(x + GATE_PIER_HALF * 0.88, 3.10, sg[1] * GATE_PIER_HALF * 0.99),
                face,
                1.65,
                0.30,
                0.64,
            );
            glyphBandInto(
                &b,
                &rng,
                v3(x - GATE_PIER_HALF * 0.88, 5.30, sg[1] * GATE_PIER_HALF * 0.99),
                v3(x + GATE_PIER_HALF * 0.88, 5.30, sg[1] * GATE_PIER_HALF * 0.99),
                face,
                2.10,
                0.24,
            );
            art.giltBandInto(&b, &rng, x, 8.20, sg[1] * 0.0, GATE_PIER_HALF * 0.99, GATE_PIER_HALF * 0.99, 0.54, SUN);
        }
        const inward: f32 = if (x < 0) 1 else -1;
        art.muqarnasInto(&b, &rng, v3(x + inward * GATE_PIER_HALF * 0.55, GATE_SPRING - 2.30 - lost, 0), v3(inward, 0, 0), 2.90, 2.30, 0.76, SUN);
        art.chipsInto(&b, &rng, x, 0, GATE_PIER_HALF * 2.2, 0.12, 0.32, 8);
        art.crackInto(&b, v3(x + GATE_PIER_HALF * 0.98, rng.range(1.2, 2.6), rng.signed() * 0.9), v3(rng.signed() * 0.22, 0.97, 0.04), v3(0, 0, 1), rng.range(1.8, 3.4), 0.035, 0.05);
        _ = top;
    }

    horseshoeInto(&b, &rng, 0, 0, GATE_SPRING, GATE_R, 1.55, 15, 16);

    const wallTop: f32 = GATE_WALL_TOP;
    // **THE SPANDRELS ARE SOLID.** An arch with daylight in its shoulders is a lintel standing on two stilts;
    // the mass has to carry from the pier round the ring to the crown before the tympanum starts.
    const ringR = GATE_R + 1.00;
    var spY = GATE_SPRING;
    while (spY < GATE_SPRING + ringR) : (spY += 0.92) {
        const dy = spY + 0.46 - GATE_SPRING;
        const inner = if (dy < ringR) @sqrt(ringR * ringR - dy * dy) else 0;
        for ([_]f32{ -1, 1 }) |sg| {
            const a0 = sg * @max(inner, 0.5);
            const a1 = sg * (GATE_PIER_X + GATE_PIER_HALF);
            if (@abs(a1 - a0) < 0.7) continue;
            art.courseInto(&b, &rng, a0, 0, a1, 0, .{
                .thick = 1.15,
                .height = 0.92,
                .y0 = spY,
                .courses = 1,
                .blockW = 1.30,
                .crumbleTop = 0.08,
                .crumble = 0.05,
                .tone = SUN,
            });
        }
    }

    b.setMat(.stone);
    var c: i32 = 0;
    const chY = GATE_SPRING + GATE_R * 1.28;
    var wy = chY;
    while (wy < wallTop) : (wy += 0.92) {
        const gapped = c == 2;
        art.courseInto(&b, &rng, -GATE_PIER_X - GATE_PIER_HALF * 0.5, 0, GATE_PIER_X + GATE_PIER_HALF * 0.5, 0, .{
            .thick = 1.15,
            .height = 0.92,
            .y0 = wy,
            .courses = 1,
            .blockW = 1.30,
            .crumbleTop = if (gapped) 0.34 else 0.06,
            .crumble = 0.05,
            .tone = SUN,
        });
        c += 1;
    }
    // THE SIGN GOES IN THE MIDDLE OF THE WALL THAT HOLDS IT, and is sized off that wall's own height: rays
    // that carry past the cornice read as a spiked mess and not as a sun.
    const ziaY = (chY + wallTop) * 0.5;
    // A ZIA IS FOUR TIMES ITS RING ACROSS: the rays run a further two radii out past it.
    const ziaR = (wallTop - chY) * 0.245;
    ziaInto(&b, &rng, v3(0, ziaY, 1.32), v3(0, 0, 1), ziaR, 0.46);
    ziaInto(&b, &rng, v3(0, ziaY, -1.32), v3(0, 0, -1), ziaR, -0.46);
    for ([_]f32{ -1, 1 }) |sx| {
        for ([_]f32{ -1, 1 }) |sz| {
            glyphBandInto(
                &b,
                &rng,
                v3(sx * (ziaR * 2.30), ziaY, sz * 1.20),
                v3(sx * (GATE_PIER_X + GATE_PIER_HALF) * 0.92, ziaY, sz * 1.20),
                v3(0, 0, sz),
                2.60,
                0.24,
            );
        }
    }
    for ([_]f32{ -1, 1 }) |sz| {
        grecaInto(
            &b,
            &rng,
            v3(-(GATE_PIER_X + GATE_PIER_HALF) * 0.94, wallTop - 1.55, sz * 1.20),
            v3((GATE_PIER_X + GATE_PIER_HALF) * 0.94, wallTop - 1.55, sz * 1.20),
            v3(0, 0, sz),
            1.30,
            0.26,
            0.66,
        );
    }
    for ([_]f32{ -1, 1 }) |sg| {
        grecaInto(
            &b,
            &rng,
            v3(-(GATE_PIER_X + GATE_PIER_HALF) * 0.94, chY + 0.34, sg * 1.20),
            v3((GATE_PIER_X + GATE_PIER_HALF) * 0.94, chY + 0.34, sg * 1.20),
            v3(0, 0, sg),
            1.30,
            0.26,
            0.62,
        );
    }

    b.setMat(.stone);
    b.addCube(v3(0, wallTop + 0.40, 0), v3((GATE_PIER_X + GATE_PIER_HALF) * 2.15, 0.80, 3.30), SAND_LT);
    art.giltBandInto(&b, &rng, 0, wallTop + 0.40, 0, (GATE_PIER_X + GATE_PIER_HALF) * 1.06, 1.64, 0.64, SUN);
    b.setMat(.stone);
    var m: i32 = 0;
    while (m < 11) : (m += 1) {
        if (m >= 8 and m <= 10) continue;
        const t = (@as(f32, @floatFromInt(m)) + 0.5) / 11.0 * 2.0 - 1.0;
        b.addCube(
            v3(t * (GATE_PIER_X + GATE_PIER_HALF) * 0.96 + rng.signed() * 0.05, wallTop + 1.18, rng.signed() * 0.06),
            v3(1.30, 0.76, 2.80),
            stoneTone(&rng),
        );
    }
    return b.toModel(shader);
}



pub const HALL_HX: f32 = 10.0;
pub const HALL_HZ: f32 = 6.50;
pub const HALL_H: f32 = 9.0;
pub const HALL_DOOR_HALF: f32 = 2.20;
pub const HALL_DOOR_HEAD: f32 = 5.60;
pub const HALL_TOP: f32 = 10.6;
pub const HALL_COL_X = [_]f32{ -6.2, -2.1, 2.1, 6.2 };
pub const HALL_COL_Z: f32 = 3.40;
pub const HALL_COL_R: f32 = 0.62;
pub const HALL_COL_H: f32 = 7.50;
/// Which of the eight is a snapped stub. The mesh and `props.HALL_PARTS` both ask, so moving the break moves the collider with it.
pub fn hallSnapped(cx: f32, sg: f32) bool {
    return cx > 4.0 and sg > 0;
}
/// The +x half of the roof is GONE. Everything under this x is still covered.
pub const HALL_ROOF_TO: f32 = 1.20;

pub fn palaceHallMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A_11_03);

    b.setMat(.stone);
    // THE FLOOR TOPS OUT UNDER `wf.STEP_UP`: a stylobate a body steps onto owes no collider, and anything laid on it has to stay under the same bar.
    b.addCube(v3(0, 0.12, 0), v3(HALL_HX * 2.5, 0.24, HALL_HZ * 2.5), SAND_DK);
    b.addCube(v3(0, 0.33, 0), v3(HALL_HX * 2.3, 0.20, HALL_HZ * 2.3), stoneTone(&rng));

    for ([_]f32{ -1, 1 }) |sg| {
        art.courseInto(&b, &rng, -HALL_HX, sg * HALL_HZ, HALL_HX, sg * HALL_HZ, .{
            .thick = 0.52,
            .height = 6.0,
            .y0 = 0.43,
            .courses = 6,
            .blockW = 1.25,
            .crumbleTop = 0.10,
            .crumble = 0.03,
            .tone = SUN,
        });
        var k: i32 = 0;
        while (k < 5) : (k += 1) {
            const x = (@as(f32, @floatFromInt(k)) - 2.0) * 3.65;
            if (x > 4.0 and rng.float() < 0.55) continue; // the ruined end lost its screens
            jaliInto(&b, &rng, v3(x, 7.80, sg * HALL_HZ), v3(0, 0, sg), 1.42, 1.05, 0.34, 0.52);
        }
        art.courseInto(&b, &rng, -HALL_HX, sg * HALL_HZ, HALL_HX, sg * HALL_HZ, .{
            .thick = 0.50,
            .height = 2.46,
            .y0 = 6.54,
            .courses = 3,
            .blockW = 1.25,
            .crumbleTop = 0.42,
            .crumble = 0.05,
            .gapLo = -6.0,
            .gapHi = 6.0,
            .sillY = 6.80,
            .headY = 8.90,
            .tone = SUN,
        });
        grecaInto(&b, &rng, v3(-HALL_HX * 0.94, 5.05, sg * (HALL_HZ + 0.30)), v3(HALL_HX * 0.94, 5.05, sg * (HALL_HZ + 0.30)), v3(0, 0, sg), 1.10, 0.22, 0.48);
        glyphBandInto(&b, &rng, v3(-HALL_HX * 0.94, 2.10, sg * (HALL_HZ + 0.30)), v3(HALL_HX * 0.94, 2.10, sg * (HALL_HZ + 0.30)), v3(0, 0, sg), 1.70, 0.17);
    }

    for ([_]f32{ -1, 1 }) |sg| {
        const x = sg * HALL_HX;
        art.courseInto(&b, &rng, x, -HALL_HZ, x, HALL_HZ, .{
            .thick = 0.52,
            .height = HALL_H,
            .courses = 9,
            .blockW = 1.25,
            .crumbleTop = 0.40,
            .crumble = 0.04,
            .gapLo = -HALL_DOOR_HALF,
            .gapHi = HALL_DOOR_HALF,
            .headY = HALL_DOOR_HEAD,
            .tone = SUN,
        });
        // The ring is drawn in the x-z plane, so it is turned onto the end wall by hand.
        const NV: i32 = 19;
        const span = 180.0 + HORSE_EXTRA * 2.0;
        var i: i32 = 0;
        while (i < NV) : (i += 1) {
            const t = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, NV);
            const a = mathx.radians(-HORSE_EXTRA + span * t);
            const ca = mathx.cosf(a);
            const sa = mathx.sinf(a);
            const half = mathx.radians(span) * HALL_DOOR_HALF / @as(f32, NV) * 0.5 * rng.range(1.03, 1.16);
            const rad = HALL_DOOR_HALF * 0.20;
            const gilded = @mod(i, 2) == 0 and rng.float() < 0.68;
            b.setMat(if (gilded) .gilt else .stone);
            b.addBox(
                v3(x + rng.signed() * 0.02, HALL_DOOR_HEAD - HALL_DOOR_HALF + sa * (HALL_DOOR_HALF + rad * 0.1), -ca * (HALL_DOOR_HALF + rad * 0.1)),
                v3(0, ca * half, -sa * half),
                v3(0, sa * rad, -ca * rad),
                v3(sg * 0.62, 0, 0),
                if (gilded) goldTone(&rng) else stoneTone(&rng),
            );
        }
        art.muqarnasInto(&b, &rng, v3(x - sg * 0.62, HALL_DOOR_HEAD - HALL_DOOR_HALF - 1.35, 0), v3(-sg, 0, 0), 2.4, 1.35, 0.66, SUN);
    }

    for (HALL_COL_X) |cx| {
        for ([_]f32{ -1, 1 }) |sg| {
            const cz = sg * HALL_COL_Z;
            const snapped = hallSnapped(cx, sg);
            const upTo: f32 = if (snapped) 3.15 else HALL_COL_H;
            b.setMat(.stone);
            b.addCube(v3(cx, 0.60, cz), v3(1.70, 0.34, 1.70), SAND_DK);
            var fy: f32 = 0.86;
            while (fy < upTo) : (fy += 0.62) {
                var s: i32 = 0;
                while (s < 12) : (s += 1) {
                    const a = std.math.tau * (@as(f32, @floatFromInt(s)) + 0.5) / 12.0;
                    b.addBox(
                        v3(cx + mathx.cosf(a) * HALL_COL_R * 0.92, fy + 0.31, cz + mathx.sinf(a) * HALL_COL_R * 0.92),
                        v3(-mathx.sinf(a) * HALL_COL_R * 0.28, 0, mathx.cosf(a) * HALL_COL_R * 0.28),
                        v3(0, 0.31, 0),
                        v3(mathx.cosf(a) * HALL_COL_R * 0.14, 0, mathx.sinf(a) * HALL_COL_R * 0.14),
                        stoneTone(&rng),
                    );
                }
                b.addCylinder(v3(cx, fy, cz), v3(cx, fy + 0.62, cz), HALL_COL_R * 0.80, HALL_COL_R * 0.80, 12, SAND_DK);
            }
            if (snapped) {
                b.addBlob(v3(cx + rng.signed() * 0.06, upTo + 0.10, cz + rng.signed() * 0.06), v3(HALL_COL_R * 0.98, 0.22, HALL_COL_R * 0.98), 2, 9, IRONWASH);
                var d: i32 = 0;
                while (d < 3) : (d += 1) {
                    const dz = cz + rng.range(1.2, 2.6);
                    b.addCylinder(v3(cx - 1.4 + @as(f32, @floatFromInt(d)) * 0.2, HALL_COL_R * 0.82, dz), v3(cx + 1.4 + @as(f32, @floatFromInt(d)) * 0.2, HALL_COL_R * 0.82, dz + rng.signed() * 0.3), HALL_COL_R * 0.82, HALL_COL_R * 0.78, 10, stoneTone(&rng));
                }
                continue;
            }
            art.giltRingInto(&b, &rng, cx, 1.05, cz, HALL_COL_R * 1.10, 0.16, 12, SUN);
            art.giltRingInto(&b, &rng, cx, HALL_COL_H - 0.95, cz, HALL_COL_R * 1.04, 0.20, 12, SUN);
            for ([_][2]f32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }) |q| {
                art.muqarnasInto(&b, &rng, v3(cx + q[0] * HALL_COL_R * 0.42, HALL_COL_H - 0.86, cz + q[1] * HALL_COL_R * 0.42), v3(q[0], 0, q[1]), 1.02, 0.86, 0.70, SUN);
            }
            b.setMat(.stone);
            b.addCube(v3(cx, HALL_COL_H + 0.16, cz), v3(1.62, 0.32, 1.62), SAND_LT);
            b.setMat(.marble);
            b.addBlob(v3(cx, HALL_COL_H + 0.44, cz), v3(0.26, 0.24, 0.26), 2, 8, EMERALD);
        }
    }

    b.setMat(.stone);
    var bi: i32 = 0;
    while (bi < 7) : (bi += 1) {
        const bx = -HALL_HX + 0.9 + @as(f32, @floatFromInt(bi)) * 2.95;
        if (bx > HALL_ROOF_TO) {
            b.addBox(v3(bx * 0.0 + HALL_ROOF_TO + 0.3, HALL_H + 0.30, rng.signed() * 4.0), v3(0.42, rng.signed() * 0.09, 0), v3(0, 0.34, 0), v3(0, 0, 0.60), IRONWASH);
            continue;
        }
        b.addBox(v3(bx, HALL_H + 0.28, 0), v3(0.44, rng.signed() * 0.02, 0), v3(0, 0.34, 0), v3(0, 0, HALL_HZ * 1.02), stoneTone(&rng));
        art.giltBandInto(&b, &rng, bx, HALL_H + 0.28, 0, 0.45, HALL_HZ * 1.01, 0.16, SUN);
    }
    var ci: i32 = 0;
    while (ci < 6) : (ci += 1) {
        const cx = -HALL_HX + 2.35 + @as(f32, @floatFromInt(ci)) * 2.95;
        if (cx > HALL_ROOF_TO) continue;
        var cz: i32 = 0;
        while (cz < 5) : (cz += 1) {
            const z = (@as(f32, @floatFromInt(cz)) - 2.0) * 2.45;
            b.setMat(.stone);
            b.addCube(v3(cx, HALL_H + 0.62, z), v3(2.30, 0.34, 1.95), SAND_DK);
            b.setMat(.gilt);
            b.addCube(v3(cx, HALL_H + 0.44, z), v3(1.55, 0.10, 1.30), goldTone(&rng));
        }
    }
    b.setMat(.stone);
    b.addBox(v3((-HALL_HX + HALL_ROOF_TO) * 0.5, HALL_H + 0.94, 0), v3((HALL_ROOF_TO + HALL_HX) * 0.5, 0, 0), v3(0, 0.22, 0), v3(0, 0, HALL_HZ * 1.06), SAND_LT);
    art.giltBandInto(&b, &rng, (-HALL_HX + HALL_ROOF_TO) * 0.5, HALL_H + 0.94, 0, (HALL_ROOF_TO + HALL_HX) * 0.5, HALL_HZ * 1.05, 0.30, SUN);

    art.starInto(&b, &rng, v3(-1.4, 0.46, 0), 3.30, 0.06, SAND_LT, SUN);
    art.starInto(&b, &rng, v3(-1.4, 0.47, 0), 2.05, 0.06, SAND, SUN);
    b.setMat(.marble);
    b.addBlob(v3(-1.4, 0.47, 0), v3(0.95, 0.04, 0.95), 2, 8, EMERALD_DK);
    b.setMat(.stone);
    var g: i32 = 0;
    while (g < 26) : (g += 1) {
        const gx = rng.range(2.0, HALL_HX * 0.96);
        b.addBlob(v3(gx, 0.40 + rng.range(0, 0.05), rng.signed() * HALL_HZ * 0.9), v3(rng.range(0.5, 1.5), rng.range(0.04, 0.09), rng.range(0.5, 1.5)), 2, 7, IRONWASH);
    }
    art.chipsInto(&b, &rng, 5.0, 0, 5.5, 0.12, 0.34, 16);
    return b.toModel(shader);
}



pub const VAULT_R: f32 = 6.20;
pub const VAULT_WALL: f32 = 6.00;
pub const VAULT_RISE: f32 = 5.60;
pub const VAULT_TOP: f32 = 12.6;
pub const VAULT_SEGS: usize = 20;
/// The two segments at either end of z are left out for the doors — the collider ring in `props.zig` reads the same four.
pub fn vaultDoorway(i: usize) bool {
    return i == 4 or i == 5 or i == 14 or i == 15;
}
const VAULT_RIBS: i32 = 16;
/// The wedge of dome that came down, in rib indices.
const VAULT_GONE_0: i32 = 5;
const VAULT_GONE_1: i32 = 9;

pub fn emeraldVaultMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A_11_04);

    b.setMat(.stone);
    b.addCylinder(v3(0, 0.02, 0), v3(0, 0.44, 0), VAULT_R * 1.22, VAULT_R * 1.16, VAULT_SEGS, SAND_DK);

    var s: usize = 0;
    while (s < VAULT_SEGS) : (s += 1) {
        if (vaultDoorway(s)) continue;
        const a0 = std.math.tau * @as(f32, @floatFromInt(s)) / @as(f32, VAULT_SEGS);
        const a1 = std.math.tau * @as(f32, @floatFromInt(s + 1)) / @as(f32, VAULT_SEGS);
        art.courseInto(&b, &rng, mathx.cosf(a0) * VAULT_R, mathx.sinf(a0) * VAULT_R, mathx.cosf(a1) * VAULT_R, mathx.sinf(a1) * VAULT_R, .{
            .thick = 0.46,
            .height = VAULT_WALL,
            .y0 = 0.44,
            .courses = 7,
            .blockW = 0.98,
            .crumbleTop = 0.24,
            .crumble = 0.04,
            .tone = SUN,
        });
        const na = (a0 + a1) * 0.5;
        const half = mathx.sinf((a1 - a0) * 0.5) * VAULT_R * 0.92;
        if (@mod(s, 2) == 0) {
            grecaInto(
                &b,
                &rng,
                v3(mathx.cosf(na) * VAULT_R - mathx.sinf(na) * half, 2.40, mathx.sinf(na) * VAULT_R + mathx.cosf(na) * half),
                v3(mathx.cosf(na) * VAULT_R + mathx.sinf(na) * half, 2.40, mathx.sinf(na) * VAULT_R - mathx.cosf(na) * half),
                v3(mathx.cosf(na), 0, mathx.sinf(na)),
                1.45,
                0.28,
                0.62,
            );
        } else {
            jaliInto(&b, &rng, v3(mathx.cosf(na) * VAULT_R, 4.35, mathx.sinf(na) * VAULT_R), v3(mathx.cosf(na), 0, mathx.sinf(na)), half * 0.82, 0.92, 0.32, 0.46);
        }
    }
    art.giltRingInto(&b, &rng, 0, VAULT_WALL + 0.30, 0, VAULT_R * 1.05, 0.62, VAULT_SEGS, SUN);
    b.setMat(.stone);
    b.addCylinder(v3(0, VAULT_WALL + 0.44, 0), v3(0, VAULT_WALL + 0.78, 0), VAULT_R * 1.10, VAULT_R * 1.02, VAULT_SEGS, SAND_LT);

    const drum = VAULT_WALL + 0.78;
    const NSEG: i32 = 8;
    var k: i32 = 0;
    while (k < VAULT_RIBS) : (k += 1) {
        const az = std.math.tau * (@as(f32, @floatFromInt(k)) + 0.5) / @as(f32, VAULT_RIBS);
        const gone = k >= VAULT_GONE_0 and k <= VAULT_GONE_1;
        const upTo: i32 = if (gone) 1 + @as(i32, @intFromFloat(rng.range(0, 2.4))) else NSEG;
        var j: i32 = 0;
        while (j < upTo) : (j += 1) {
            const t0 = @as(f32, @floatFromInt(j)) / @as(f32, NSEG);
            const t1 = @as(f32, @floatFromInt(j + 1)) / @as(f32, NSEG);
            const e0 = std.math.pi * 0.5 * t0;
            const e1 = std.math.pi * 0.5 * t1;
            const rm = (mathx.cosf(e0) + mathx.cosf(e1)) * 0.5 * VAULT_R;
            const ym = drum + (mathx.sinf(e0) + mathx.sinf(e1)) * 0.5 * VAULT_RISE;
            const along = (mathx.sinf(e1) - mathx.sinf(e0)) * VAULT_RISE * 0.58;
            // A RIB IS NARROW AND PROUD, A PANE IS WIDE AND FLUSH. At one width the gold and the glass are
            // one chequer and the shell has no structure left.
            const wide = std.math.tau * rm / @as(f32, VAULT_RIBS) * 0.20;
            b.setMat(.gilt);
            b.addBox(
                v3(mathx.cosf(az) * rm, ym, mathx.sinf(az) * rm),
                v3(-mathx.sinf(az) * wide, 0, mathx.cosf(az) * wide),
                v3(0, along, 0),
                v3(mathx.cosf(az) * 0.32, 0, mathx.sinf(az) * 0.32),
                goldTone(&rng),
            );
        }
        if (gone) continue;
        const az2 = az + std.math.tau / @as(f32, VAULT_RIBS) * 0.5;
        var w: i32 = 0;
        while (w < NSEG) : (w += 1) {
            const t = (@as(f32, @floatFromInt(w)) + 0.5) / @as(f32, NSEG);
            const e = std.math.pi * 0.5 * t;
            const rm = mathx.cosf(e) * VAULT_R * 0.99;
            const ym = drum + mathx.sinf(e) * VAULT_RISE;
            const wide = std.math.tau * rm / @as(f32, VAULT_RIBS) * 0.72;
            b.setMat(.marble);
            b.addBox(
                v3(mathx.cosf(az2) * rm, ym, mathx.sinf(az2) * rm),
                v3(-mathx.sinf(az2) * wide, 0, mathx.cosf(az2) * wide),
                v3(0, VAULT_RISE / @as(f32, NSEG) * 0.52, 0),
                v3(mathx.cosf(az2) * 0.07, 0, mathx.sinf(az2) * 0.07),
                gemTone(&rng),
            );
        }
    }
    b.setMat(.gilt);
    b.addCylinder(v3(0, drum + VAULT_RISE - 0.10, 0), v3(0, drum + VAULT_RISE + 0.52, 0), 0.62, 0.42, 8, PGOLD_LT);
    b.setMat(.marble);
    b.addBlob(v3(0, drum + VAULT_RISE + 0.92, 0), v3(0.44, 0.52, 0.44), 2, 8, EMERALD_LT);

    b.setMat(.stone);
    b.addCylinder(v3(0, 0.44, 0), v3(0, 1.10, 0), 1.72, 1.55, OCTAGON, stoneTone(&rng));
    art.giltRingInto(&b, &rng, 0, 0.96, 0, 1.62, 0.22, OCTAGON, SUN);
    gemInto(&b, &rng, v3(0, 1.92, 0), 0.72);

    const wedge = std.math.tau * (@as(f32, @floatFromInt(VAULT_GONE_0 + VAULT_GONE_1)) * 0.5 + 0.5) / @as(f32, VAULT_RIBS);
    b.setMat(.marble);
    var f: i32 = 0;
    while (f < 16) : (f += 1) {
        const a = wedge + rng.signed() * 0.75;
        const d = rng.range(1.9, VAULT_R * 0.94);
        const rr = rng.range(0.18, 0.52);
        b.addBox(
            v3(mathx.cosf(a) * d, 0.42 + rr * 0.06, mathx.sinf(a) * d),
            v3(rr, rng.signed() * 0.02, rng.signed() * 0.10),
            v3(rng.signed() * 0.03, 0.025, 0),
            v3(0, rng.signed() * 0.03, rr * rng.range(0.5, 1.0)),
            gemTone(&rng),
        );
    }
    b.setMat(.stone);
    art.chipsInto(&b, &rng, mathx.cosf(wedge) * VAULT_R * 1.2, mathx.sinf(wedge) * VAULT_R * 1.2, 3.2, 0.12, 0.30, 12);
    return b.toModel(shader);
}



/// A FLIGHT IS SECTIONS (`props.Info.stack` + `flight`), the ladder's convention: local −Z is what it climbs to.
/// Four risers of one `wf.HEIGHT_STEP` over 2.6 m of run — a processional going, three times the ruin stair's tread.
pub const PSTAIR_SEG: f32 = 1.0;
pub const PSTAIR_RUN: f32 = 2.60;
pub const PSTAIR_TREADS: u32 = 4;
pub const PSTAIR_HALF: f32 = 2.60;

pub fn palaceStairMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A_11_05);
    const riser = PSTAIR_SEG / @as(f32, @floatFromInt(PSTAIR_TREADS));
    const tread = PSTAIR_RUN / @as(f32, @floatFromInt(PSTAIR_TREADS));

    b.setMat(.stone);
    b.addBox(v3(0, 0.30, -PSTAIR_RUN * 0.5), v3(PSTAIR_HALF * 0.98, 0, 0), v3(0, 0.16, 0), v3(0, PSTAIR_SEG * 0.5, -PSTAIR_RUN * 0.5), SAND_DK);
    for (0..PSTAIR_TREADS) |k| {
        const kf = @as(f32, @floatFromInt(k));
        const zc = -(kf + 0.5) * tread;
        const yc = kf * riser + riser * 0.5;
        const hw = PSTAIR_HALF * rng.range(0.98, 1.02);
        b.addBox(
            v3(rng.signed() * 0.02, yc, zc + rng.signed() * 0.01),
            v3(hw, rng.signed() * 0.005, 0),
            v3(rng.signed() * 0.01, riser * 0.5, rng.signed() * 0.006),
            v3(0, 0, tread * 0.5 + 0.04),
            if (k % 2 == 0) SAND else SAND_LT,
        );
        b.setMat(.gilt);
        b.addBox(
            v3(rng.signed() * 0.03, yc, zc - tread * 0.5 - 0.02),
            v3(hw * rng.range(0.62, 0.94), 0, 0),
            v3(0, riser * 0.22, 0),
            v3(0, 0, 0.030),
            goldTone(&rng),
        );
        b.setMat(.stone);
    }
    for ([_]f32{ -1, 1 }) |sgn| {
        const x = sgn * (PSTAIR_HALF + 0.26);
        b.addBox(v3(x, 0.50, -PSTAIR_RUN * 0.5), v3(0.24, 0, 0), v3(rng.signed() * 0.02, 0.30, 0), v3(0, PSTAIR_SEG * 0.5, -PSTAIR_RUN * 0.5), stoneTone(&rng));
        grecaInto(
            &b,
            &rng,
            v3(x + sgn * 0.22, 0.34, 0.05),
            v3(x + sgn * 0.22, 0.34 + PSTAIR_SEG, -PSTAIR_RUN + 0.05),
            v3(sgn, 0, 0),
            0.44,
            0.10,
            0.44,
        );
    }
    return b.toModel(shader);
}



pub const PWALL_HALF: f32 = 8.00;
pub const PWALL_H: f32 = 8.00;
pub const PWALL_BREACH_X: f32 = 4.00;
pub const PWALL_BREACH_H: f32 = 2.60;
pub const PWALL_TOP: f32 = 9.10;

pub fn palaceWallMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A_11_06);

    b.setMat(.stone);
    b.addCube(v3(-2.0, 0.20, 0), v3(PWALL_HALF * 2.1, 0.40, 2.30), SAND_DK);
    art.courseInto(&b, &rng, -PWALL_HALF, 0, PWALL_BREACH_X, 0, .{
        .thick = 0.60,
        .height = PWALL_H,
        .y0 = 0.40,
        .courses = 8,
        .blockW = 1.35,
        .crumbleTop = 0.22,
        .crumble = 0.03,
        .tone = SUN,
    });
    art.courseInto(&b, &rng, PWALL_BREACH_X, 0, PWALL_HALF, 0, .{
        .thick = 0.58,
        .height = PWALL_BREACH_H,
        .y0 = 0.40,
        .courses = 3,
        .blockW = 1.35,
        .crumbleTop = 0.62,
        .crumble = 0.18,
        .tone = SUN,
    });

    for ([_]f32{ -1, 1 }) |sg| {
        grecaInto(&b, &rng, v3(-PWALL_HALF * 0.94, 5.30, sg * 0.62), v3(PWALL_BREACH_X * 0.90, 5.30, sg * 0.62), v3(0, 0, sg), 1.15, 0.20, 0.50);
        glyphBandInto(&b, &rng, v3(-PWALL_HALF * 0.92, 1.60, sg * 0.62), v3(PWALL_BREACH_X * 0.86, 1.60, sg * 0.62), v3(0, 0, sg), 1.55, 0.16);
    }
    var k: i32 = 0;
    while (k < 3) : (k += 1) {
        jaliInto(&b, &rng, v3(-5.4 + @as(f32, @floatFromInt(k)) * 3.9, 3.30, 0.60), v3(0, 0, 1), 1.05, 0.85, 0.60, 0.48);
    }

    b.setMat(.stone);
    b.addBox(v3((-PWALL_HALF + PWALL_BREACH_X) * 0.5, PWALL_H + 0.60, 0), v3((PWALL_HALF + PWALL_BREACH_X) * 0.5, 0, 0), v3(0, 0.30, 0), v3(0, 0, 1.05), SAND_LT);
    art.giltBandInto(&b, &rng, (-PWALL_HALF + PWALL_BREACH_X) * 0.5, PWALL_H + 0.60, 0, (PWALL_HALF + PWALL_BREACH_X) * 0.5, 1.02, 0.32, SUN);
    var m: i32 = 0;
    while (m < 9) : (m += 1) {
        if (rng.float() < 0.24) continue;
        const t = (@as(f32, @floatFromInt(m)) + 0.5) / 9.0;
        b.setMat(.stone);
        b.addCube(v3(mathx.lerpF(-PWALL_HALF, PWALL_BREACH_X, t) + rng.signed() * 0.04, PWALL_H + 1.16, rng.signed() * 0.05), v3(0.86, 0.80, 1.10), stoneTone(&rng));
    }
    b.setMat(.stone);
    var f: i32 = 0;
    while (f < 9) : (f += 1) {
        b.addBox(
            v3(rng.range(PWALL_BREACH_X - 1.0, PWALL_HALF + 1.4), rng.range(0.10, 0.28), rng.signed() * 2.6),
            v3(rng.range(0.42, 0.86), rng.signed() * 0.14, rng.signed() * 0.22),
            v3(rng.signed() * 0.18, rng.range(0.10, 0.20), 0),
            v3(rng.signed() * 0.20, 0, rng.range(0.34, 0.70)),
            stoneTone(&rng),
        );
    }
    art.chipsInto(&b, &rng, PWALL_BREACH_X + 1.5, 0, 3.4, 0.10, 0.30, 14);
    return b.toModel(shader);
}



pub const PCOL_H: f32 = 9.60;
pub const PCOL_R: f32 = 0.86;
pub const PCOL_TOP: f32 = 11.2;
const PCOL_FLUTES: i32 = 16;

pub fn palaceColumnMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A_11_07);

    b.setMat(.stone);
    b.addCube(v3(0, 0.22, 0), v3(2.46, 0.44, 2.46), SAND_DK);
    b.addCube(v3(rng.signed() * 0.02, 0.62, rng.signed() * 0.02), v3(2.10, 0.36, 2.10), stoneTone(&rng));
    b.addCylinder(v3(0, 0.80, 0), v3(0, 1.16, 0), PCOL_R * 1.22, PCOL_R * 1.04, 16, SAND_LT);

    b.addCylinder(v3(0, 1.10, 0), v3(0, PCOL_H - 0.90, 0), PCOL_R, PCOL_R * 0.86, 16, SAND);
    var f: i32 = 0;
    while (f < PCOL_FLUTES) : (f += 1) {
        const a = std.math.tau * (@as(f32, @floatFromInt(f)) + 0.5) / @as(f32, PCOL_FLUTES);
        var fy: f32 = 1.24;
        while (fy < PCOL_H - 1.00) : (fy += 0.78) {
            const t = (fy - 1.10) / (PCOL_H - 2.0);
            const rr = PCOL_R * mathx.lerpF(1.0, 0.86, t);
            b.addBox(
                v3(mathx.cosf(a) * rr * 0.985, fy + 0.39, mathx.sinf(a) * rr * 0.985),
                v3(-mathx.sinf(a) * rr * 0.17, 0, mathx.cosf(a) * rr * 0.17),
                v3(0, 0.39, 0),
                v3(mathx.cosf(a) * rr * 0.055, 0, mathx.sinf(a) * rr * 0.055),
                // A FLUTE IS A SHADOW, NOT A STAIN: sunk in the iron wash the whole shaft came back charred.
                if (@mod(f, 2) == 0) SAND_DK else SAND,
            );
        }
    }
    art.giltRingInto(&b, &rng, 0, 1.42, 0, PCOL_R * 1.06, 0.20, PCOL_FLUTES, SUN);
    grecaInto(&b, &rng, v3(-PCOL_R * 0.86, 2.30, PCOL_R * 0.96), v3(PCOL_R * 0.86, 2.30, PCOL_R * 0.96), v3(0, 0, 1), 0.72, 0.14, 0.46);
    grecaInto(&b, &rng, v3(PCOL_R * 0.86, 2.30, -PCOL_R * 0.96), v3(-PCOL_R * 0.86, 2.30, -PCOL_R * 0.96), v3(0, 0, -1), 0.72, 0.14, 0.46);

    b.setMat(.marble);
    var e: i32 = 0;
    while (e < 10) : (e += 1) {
        const a = std.math.tau * (@as(f32, @floatFromInt(e)) + 0.5) / 10.0;
        b.addBlob(v3(mathx.cosf(a) * PCOL_R * 0.96, 5.10, mathx.sinf(a) * PCOL_R * 0.96), v3(0.17, 0.20, 0.17), 2, 7, gemTone(&rng));
    }
    art.giltRingInto(&b, &rng, 0, 5.10, 0, PCOL_R * 1.08, 0.44, 10, SUN);
    art.giltRingInto(&b, &rng, 0, PCOL_H - 1.10, 0, PCOL_R * 0.94, 0.24, PCOL_FLUTES, SUN);
    for ([_][2]f32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }) |q| {
        art.muqarnasInto(&b, &rng, v3(q[0] * PCOL_R * 0.40, PCOL_H - 1.00, q[1] * PCOL_R * 0.40), v3(q[0], 0, q[1]), 1.30, 1.00, 0.74, SUN);
    }
    b.setMat(.stone);
    b.addCube(v3(rng.signed() * 0.02, PCOL_H + 0.20, rng.signed() * 0.02), v3(2.24, 0.40, 2.24), SAND_LT);
    art.giltBandInto(&b, &rng, 0, PCOL_H + 0.20, 0, 1.13, 1.13, 0.24, SUN);
    b.setMat(.stone);
    b.addBox(v3(0.72, PCOL_H + 0.72, 0.20), v3(0.86, 0.16, 0), v3(-0.16, 0.44, 0), v3(0, 0, 0.72), stoneTone(&rng));
    art.chipsInto(&b, &rng, 0, 0, 2.4, 0.10, 0.28, 8);
    return b.toModel(shader);
}

pub const PFALL_TOP: f32 = 1.75;
/// The drums are laid at AUTHORED lengths, not rolled ones: the collider in `props.zig` is a segment from the first drum's foot to the last one's head, and a re-rolled length moves that end.
const PFALL_DRUMS = [_]f32{ 2.05, 1.85, 2.20 };
const PFALL_GAPS = [_]f32{ 0.26, 0.18 };
pub const PFALL_X0: f32 = -3.10;
pub const PFALL_CAP_X: f32 = PFALL_X0 + PFALL_DRUMS[0] + PFALL_GAPS[0] + PFALL_DRUMS[1] + PFALL_GAPS[1] + PFALL_DRUMS[2] + 0.80;

pub fn fallenColumnMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A_11_08);

    var x: f32 = PFALL_X0;
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const len = PFALL_DRUMS[@intCast(i)];
        const sink = rng.range(0.12, 0.34) * @as(f32, @floatFromInt(i + 1)) * 0.5;
        const drift = rng.signed() * 0.34;
        const a = v3(x, PCOL_R * 0.90 - sink, drift);
        const c = v3(x + len, PCOL_R * 0.90 - sink, drift + rng.signed() * 0.24);
        b.setMat(.stone);
        b.addCylinder(a, c, PCOL_R * rng.range(0.92, 1.0), PCOL_R * rng.range(0.90, 0.98), 14, stoneTone(&rng));
        var f: i32 = 0;
        while (f < PCOL_FLUTES) : (f += 1) {
            const ang = std.math.tau * (@as(f32, @floatFromInt(f)) + 0.5) / @as(f32, PCOL_FLUTES);
            const dy = mathx.sinf(ang) * PCOL_R * 0.97;
            const dz = mathx.cosf(ang) * PCOL_R * 0.97;
            if (dy < -PCOL_R * 0.55) continue; // buried
            b.addBox(
                v3((a.x + c.x) * 0.5, a.y + dy, (a.z + c.z) * 0.5 + dz),
                v3(len * 0.48, 0, 0),
                v3(0, mathx.sinf(ang) * PCOL_R * 0.055, mathx.cosf(ang) * PCOL_R * 0.055),
                v3(0, mathx.cosf(ang) * PCOL_R * 0.16, -mathx.sinf(ang) * PCOL_R * 0.16),
                if (@mod(f, 2) == 0) SAND_DK else SAND,
            );
        }
        if (i == 1) art.giltRingInto(&b, &rng, (a.x + c.x) * 0.5, a.y, (a.z + c.z) * 0.5, PCOL_R * 1.04, 0.30, 12, SUN);
        x += len + (if (i < 2) PFALL_GAPS[@intCast(i)] else 0);
    }
    b.setMat(.stone);
    b.addCube(v3(x + 0.80, 0.44, rng.signed() * 0.30), v3(2.20, 0.88, 2.20), stoneTone(&rng));
    art.giltBandInto(&b, &rng, x + 0.80, 0.44, 0, 1.11, 1.11, 0.26, SUN);
    art.muqarnasInto(&b, &rng, v3(x + 0.80, 0.90, 0.30), v3(0, 0, 1), 1.20, 0.62, 0.60, SUN);

    b.setMat(.stone);
    var d: i32 = 0;
    while (d < 12) : (d += 1) {
        const dx = rng.range(-3.6, x + 1.9);
        const dz = rng.range(0.55, 1.35) * (if (rng.float() < 0.5) @as(f32, -1) else 1);
        b.addBlob(v3(dx, rng.range(0.06, 0.22), dz), v3(rng.range(0.5, 1.3), rng.range(0.08, 0.24), rng.range(0.3, 0.7)), 2, 7, IRONWASH);
    }
    art.chipsInto(&b, &rng, 0, 0, 3.6, 0.09, 0.26, 12);
    return b.toModel(shader);
}



/// The plan is the family's octagon and `TERR_R` is its CIRCUMradius, so the deck disc is the INRADIUS: a
/// body walks to the parapet and no further, and there is no corner of floor hanging off the stone.
pub const TERR_R: f32 = 5.62;
pub const TERR_IN: f32 = TERR_R * 0.9239;
pub const TERR_DECK: f32 = 4.00;
pub const TERR_PARAPET: f32 = 5.10;
pub const TERR_TOP: f32 = 5.85;
/// The TWO octagon edges the stair lands on, which the parapet leaves open. Two, because no single edge of an
/// octagon is centred on an axis and a landing off to one side is a landing you walk off.
pub const TERR_GAP_0: usize = 5;
pub const TERR_GAP_1: usize = 6;

pub fn palaceTerraceMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A_11_09);

    b.setMat(.stone);
    b.addCylinder(v3(0, 0.0, 0), v3(0, 0.85, 0), TERR_R * 1.04, TERR_R * 1.03, OCTAGON, SAND_DK);
    b.addCylinder(v3(0, 0.85, 0), v3(0, 3.10, 0), TERR_R * 1.03, TERR_R * 0.94, OCTAGON, SAND);
    b.addCylinder(v3(0, 3.10, 0), v3(0, 3.76, 0), TERR_R * 0.96, TERR_R * 0.96, OCTAGON, SAND_DK);
    b.addCylinder(v3(0, 3.76, 0), v3(0, 4.00, 0), TERR_R * 1.00, TERR_R * 0.99, OCTAGON, SAND_LT);

    var s: i32 = 0;
    while (s < OCTAGON) : (s += 1) {
        const a0 = std.math.tau * @as(f32, @floatFromInt(s)) / @as(f32, OCTAGON);
        const a1 = std.math.tau * @as(f32, @floatFromInt(s + 1)) / @as(f32, OCTAGON);
        const na = (a0 + a1) * 0.5;
        const half = mathx.sinf((a1 - a0) * 0.5) * TERR_R * 0.86;
        const at = TERR_IN * 0.96;
        grecaInto(
            &b,
            &rng,
            v3(mathx.cosf(na) * at - mathx.sinf(na) * half, 3.20, mathx.sinf(na) * at + mathx.cosf(na) * half),
            v3(mathx.cosf(na) * at + mathx.sinf(na) * half, 3.20, mathx.sinf(na) * at - mathx.cosf(na) * half),
            v3(mathx.cosf(na), 0, mathx.sinf(na)),
            0.50,
            0.22,
            0.52,
        );
        if (@mod(s, 2) == 0) {
            glyphBandInto(
                &b,
                &rng,
                v3(mathx.cosf(na) * (TERR_R * 1.0) - mathx.sinf(na) * half * 0.8, 1.30, mathx.sinf(na) * (TERR_R * 1.0) + mathx.cosf(na) * half * 0.8),
                v3(mathx.cosf(na) * (TERR_R * 1.0) + mathx.sinf(na) * half * 0.8, 1.30, mathx.sinf(na) * (TERR_R * 1.0) - mathx.cosf(na) * half * 0.8),
                v3(mathx.cosf(na), 0, mathx.sinf(na)),
                1.40,
                0.16,
            );
        }
    }
    art.giltRingInto(&b, &rng, 0, 3.88, 0, TERR_R * 1.02, 0.22, OCTAGON, SUN);

    b.setMat(.stone);
    var p: i32 = 0;
    while (p < 34) : (p += 1) {
        const a = rng.angle();
        const d = rng.range(0.2, 1.0) * TERR_IN * 0.94;
        const yaw = rng.signed() * 0.10;
        const hw = rng.range(0.42, 0.86);
        b.addBox(
            v3(mathx.cosf(a) * d, TERR_DECK + 0.02, mathx.sinf(a) * d),
            v3(mathx.cosf(yaw) * hw, rng.signed() * 0.006, mathx.sinf(yaw) * hw),
            v3(0, 0.04, 0),
            v3(-mathx.sinf(yaw) * hw * 0.8, rng.signed() * 0.006, mathx.cosf(yaw) * hw * 0.8),
            stoneTone(&rng),
        );
    }
    art.starInto(&b, &rng, v3(0, TERR_DECK + 0.08, 0), 2.20, 0.08, SAND_LT, SUN);
    b.setMat(.marble);
    b.addBlob(v3(0, TERR_DECK + 0.10, 0), v3(0.72, 0.04, 0.72), 2, 8, EMERALD_DK);

    var q: usize = 0;
    while (q < OCTAGON) : (q += 1) {
        if (q == TERR_GAP_0 or q == TERR_GAP_1) continue;
        const a0 = std.math.tau * @as(f32, @floatFromInt(q)) / @as(f32, OCTAGON);
        const a1 = std.math.tau * @as(f32, @floatFromInt(q + 1)) / @as(f32, OCTAGON);
        const broken = q == 2;
        art.courseInto(&b, &rng, mathx.cosf(a0) * TERR_R * 0.97, mathx.sinf(a0) * TERR_R * 0.97, mathx.cosf(a1) * TERR_R * 0.97, mathx.sinf(a1) * TERR_R * 0.97, .{
            .thick = 0.26,
            .height = TERR_PARAPET - TERR_DECK,
            .y0 = TERR_DECK,
            .courses = 2,
            .blockW = 0.74,
            .crumbleTop = if (broken) 0.70 else 0.14,
            .crumble = if (broken) 0.34 else 0.03,
            .tone = SUN,
        });
        if (broken) continue;
        const na = (a0 + a1) * 0.5;
        const half = mathx.sinf((a1 - a0) * 0.5) * TERR_R * 0.82;
        jaliInto(&b, &rng, v3(mathx.cosf(na) * TERR_R * 0.97, TERR_DECK + 0.56, mathx.sinf(na) * TERR_R * 0.97), v3(mathx.cosf(na), 0, mathx.sinf(na)), half, 0.34, 0.24, 0.40);
    }
    art.giltRingInto(&b, &rng, 0, TERR_PARAPET - 0.10, 0, TERR_R * 0.99, 0.18, OCTAGON, SUN);

    var c: i32 = 0;
    while (c < OCTAGON) : (c += 1) {
        if (c == 2 or c == 3) continue;
        const a = std.math.tau * @as(f32, @floatFromInt(c)) / @as(f32, OCTAGON);
        const cx = mathx.cosf(a) * TERR_R * 0.94;
        const cz = mathx.sinf(a) * TERR_R * 0.94;
        b.setMat(.stone);
        b.addCube(v3(cx, TERR_PARAPET + 0.16, cz), v3(0.52, 0.32, 0.52), SAND_LT);
        b.setMat(.gilt);
        b.addCylinder(v3(cx, TERR_PARAPET + 0.32, cz), v3(cx, TERR_PARAPET + 0.60, cz), 0.17, 0.11, 8, goldTone(&rng));
        b.setMat(.marble);
        b.addBlob(v3(cx, TERR_PARAPET + 0.72, cz), v3(0.13, 0.15, 0.13), 2, 7, EMERALD);
    }
    b.setMat(.stone);
    art.chipsInto(&b, &rng, 0, 0, TERR_R * 1.4, 0.10, 0.28, 12);
    return b.toModel(shader);
}



pub const IDOL_HALF: f32 = 2.35;
pub const IDOL_TOP: f32 = 14.0;

pub fn watcherIdolMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A_11_0A);

    const top = taludInto(&b, &rng, 0, 0, 0, IDOL_HALF, 1.40, 0.60, 0.12, 0.40);
    const y0 = top;

    // **THE TORSO IS NARROWER THAN THE SHOULDERS ARE WIDE.** At 1.6 m of radius it swallowed both arms and the
    // chin, and what came back was a snowman.
    b.setMat(.stone);
    b.addCube(v3(0, y0 + 1.80, 0), v3(3.10, 3.60, 2.10), SAND);
    b.addCube(v3(0, y0 + 3.80, 0), v3(3.50, 0.44, 2.44), SAND_LT);
    for ([_][2]f32{ .{ 0, 1 }, .{ 0, -1 } }) |sg| {
        grecaInto(&b, &rng, v3(-1.42, y0 + 0.80, sg[1] * 1.07), v3(1.42, y0 + 0.80, sg[1] * 1.07), v3(0, 0, sg[1]), 1.55, 0.24, 0.68);
        glyphBandInto(&b, &rng, v3(-1.42, y0 + 2.75, sg[1] * 1.07), v3(1.42, y0 + 2.75, sg[1] * 1.07), v3(0, 0, sg[1]), 1.25, 0.18);
    }
    art.giltBandInto(&b, &rng, 0, y0 + 3.80, 0, 1.76, 1.24, 0.48, SUN);

    const chest = y0 + 7.20;
    b.addCapsule(v3(0, y0 + 4.10, 0), v3(0, chest, 0.10), 1.10, 1.24, 11, SAND);
    b.addCapsule(v3(-1.98, chest + 0.10, 0.06), v3(1.98, chest + 0.10, 0.06), 0.56, 0.56, 9, SAND);
    b.addBlob(v3(0, chest + 0.30, 0.16), v3(1.34, 0.60, 0.82), 4, 11, SAND_LT);
    ziaInto(&b, &rng, v3(0, chest - 0.34, 0.94), v3(0, 0, 1), 0.96, 0.24);

    // A NECK, AND IT CLEARS THE SHOULDERS, or the head sits on them like a lid.
    b.addCapsule(v3(0, chest + 0.45, 0.10), v3(0, chest + 1.60, 0.16), 0.46, 0.38, 9, SAND);
    art.giltRingInto(&b, &rng, 0, chest + 0.74, 0.12, 0.62, 0.32, 12, SUN);

    for ([_]f32{ -1, 1 }) |sg| {
        const sh = v3(sg * 2.02, chest + 0.02, 0.06);
        const el = v3(sg * 2.52, chest - 2.60, 0.62);
        b.addCapsule(sh, el, 0.50, 0.38, 9, SAND);
        if (sg < 0) {
            b.addBlob(el, v3(0.40, 0.26, 0.40), 3, 8, IRONWASH);
            continue;
        }
        const wr = v3(sg * 2.30, chest - 4.80, 1.20);
        b.addCapsule(el, wr, 0.38, 0.29, 9, SAND);
        b.addBlob(v3(wr.x, wr.y - 0.28, wr.z + 0.16), v3(0.40, 0.15, 0.44), 3, 9, SAND_LT);
        var fgr: i32 = 0;
        while (fgr < 4) : (fgr += 1) {
            const fx = (@as(f32, @floatFromInt(fgr)) - 1.5) * 0.18;
            b.addCapsule(
                v3(wr.x + fx, wr.y - 0.32, wr.z + 0.30),
                v3(wr.x + fx * 1.25, wr.y - 0.38, wr.z + 0.72),
                0.070,
                0.054,
                6,
                SAND_LT,
            );
        }
    }
    b.addCapsule(v3(-2.95, 0.22, 1.55), v3(-4.35, 0.20, 1.05), 0.30, 0.24, 9, SAND_DK);
    b.addBlob(v3(-4.60, 0.18, 0.92), v3(0.34, 0.13, 0.36), 3, 8, IRONWASH);

    // A WIDE CRANIUM OVER A NARROW CHIN, and ONE blob for the cranium in the SAME stone: a pale cap on top read
    // as a beret, and the collar belongs at the jaw, not across the brow.
    const head = chest + 2.85;
    b.addBlob(v3(0, head - 1.30, 0.24), v3(0.54, 0.48, 0.50), 4, 9, SAND);
    b.addBlob(v3(0, head - 0.76, 0.20), v3(0.92, 0.66, 0.86), 5, 11, SAND);
    b.addBlob(v3(0, head + 0.16, 0.10), v3(1.28, 1.40, 1.14), 6, 13, SAND);
    art.giltRingInto(&b, &rng, 0, head - 1.02, 0.22, 0.78, 0.28, 14, SUN);

    for ([_]f32{ -1, 1 }) |sg| {
        const ex = sg * 0.62;
        const tilt = mathx.radians(sg * 22.0);
        b.setMat(.stone);
        b.addBox(
            v3(ex, head + 0.16, 1.16),
            v3(mathx.cosf(tilt) * 0.72, mathx.sinf(tilt) * 0.72, 0),
            v3(-mathx.sinf(tilt) * 0.36, mathx.cosf(tilt) * 0.36, 0),
            v3(0, 0, 0.12),
            SAND_DK,
        );
        const dead = sg < 0;
        b.setMat(.marble);
        b.addBox(
            v3(ex, head + 0.16, 1.26),
            v3(mathx.cosf(tilt) * 0.62, mathx.sinf(tilt) * 0.62, 0),
            v3(-mathx.sinf(tilt) * 0.29, mathx.cosf(tilt) * 0.29, 0),
            v3(0, 0, 0.11),
            if (dead) IRONWASH else EMERALD,
        );
        if (dead) {
            b.setMat(.stone);
            art.crackInto(&b, v3(ex - 0.48, head + 0.46, 1.34), v3(0.72, -0.68, 0.10), v3(0, 0, 1), 1.05, 0.028, 0.035);
            continue;
        }
        b.addBox(
            v3(ex, head + 0.16, 1.33),
            v3(mathx.cosf(tilt) * 0.34, mathx.sinf(tilt) * 0.34, 0),
            v3(-mathx.sinf(tilt) * 0.15, mathx.cosf(tilt) * 0.15, 0),
            v3(0, 0, 0.07),
            EMERALD_LT,
        );
    }
    b.setMat(.stone);
    art.crackInto(&b, v3(-1.02, chest + 0.10, 0.86), v3(0.94, -0.34, 0.08), v3(0, 1, 0), 2.20, 0.030, 0.04);
    art.chipsInto(&b, &rng, 0, 0, IDOL_HALF * 2.2, 0.12, 0.34, 12);
    return b.toModel(shader);
}



pub const OBEL_H: f32 = 11.4;
pub const OBEL_TOP: f32 = 13.0;
pub const OBEL_HALF: f32 = 0.78;

pub fn sunObeliskMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A_11_0B);

    b.setMat(.stone);
    b.addCube(v3(0, 0.24, 0), v3(2.70, 0.48, 2.70), SAND_DK);
    b.addCube(v3(rng.signed() * 0.02, 0.68, rng.signed() * 0.02), v3(2.24, 0.40, 2.24), stoneTone(&rng));
    art.giltBandInto(&b, &rng, 0, 0.68, 0, 1.13, 1.13, 0.22, SUN);

    const y0: f32 = 0.88;
    const CH: f32 = 0.72;
    var y = y0;
    while (y < OBEL_H) : (y += CH) {
        const t = (y - y0) / (OBEL_H - y0);
        const hw = OBEL_HALF * (1.0 - 0.38 * t);
        b.addBox(
            v3(rng.signed() * 0.012, y + CH * 0.5, rng.signed() * 0.012),
            v3(hw, rng.signed() * 0.005, 0),
            v3(0, CH * 0.5 * rng.range(0.98, 1.04), 0),
            v3(0, rng.signed() * 0.005, hw),
            stoneTone(&rng),
        );
    }
    var bandY: f32 = 1.60;
    var n: i32 = 0;
    while (bandY < OBEL_H - 1.20) : (bandY += 2.05) {
        const t = (bandY - y0) / (OBEL_H - y0);
        const hw = OBEL_HALF * (1.0 - 0.38 * t);
        for ([_][2]f32{ .{ 0, 1 }, .{ 0, -1 }, .{ 1, 0 }, .{ -1, 0 } }, 0..) |sg, si| {
            const face = v3(sg[0], 0, sg[1]);
            const along = v3(-sg[1], 0, sg[0]);
            const a = v3(-along.x * hw * 0.90 + sg[0] * hw * 1.0, bandY, -along.z * hw * 0.90 + sg[1] * hw * 1.0);
            const c = v3(along.x * hw * 0.90 + sg[0] * hw * 1.0, bandY, along.z * hw * 0.90 + sg[1] * hw * 1.0);
            if (@mod(n + @as(i32, @intCast(si)), 4) == 0) {
                grecaInto(&b, &rng, a, c, face, 0.90, 0.11, 0.58);
            } else {
                glyphBandInto(&b, &rng, a, c, face, 1.32, 0.10);
            }
        }
        n += 1;
    }

    const py = OBEL_H;
    const ph = OBEL_HALF * (1.0 - 0.38);
    b.setMat(.gilt);
    var k: i32 = 0;
    while (k < 5) : (k += 1) {
        const t0 = @as(f32, @floatFromInt(k)) / 5.0;
        const t1 = @as(f32, @floatFromInt(k + 1)) / 5.0;
        const w0 = ph * (1.0 - t0 * 0.82);
        const w1 = ph * (1.0 - t1 * 0.82);
        b.addBox(
            v3(0, py + (t0 + t1) * 0.5 * 1.30, 0),
            v3((w0 + w1) * 0.5, 0, 0),
            v3(0, 0.13, 0),
            v3(0, 0, (w0 + w1) * 0.5),
            goldTone(&rng),
        );
    }
    b.setMat(.marble);
    b.addBlob(v3(0, py + 1.46, 0), v3(0.20, 0.24, 0.20), 2, 8, EMERALD);
    b.setMat(.stone);
    art.crackInto(&b, v3(OBEL_HALF * 0.98, 2.10, -0.30), v3(0.10, 0.99, 0), v3(0, 0, 1), 1.70, 0.020, 0.028);
    art.chipsInto(&b, &rng, 0, 0, 2.6, 0.09, 0.26, 9);
    return b.toModel(shader);
}



pub const BASIN_R: f32 = 3.30;
pub const BASIN_TOP: f32 = 1.52;

pub fn starBasinMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A_11_0C);

    // **THE PLAN IS THE OCTAGON AND THE STAR IS ONLY THE BOWL.** A khatim this big at walk height is eight
    // corners a body stands inside, and the only collider that holds them is a square over a rosette.
    b.setMat(.stone);
    b.addCylinder(v3(0, 0.0, 0), v3(0, 0.30, 0), BASIN_R, BASIN_R * 0.97, OCTAGON, SAND_DK);
    b.addCylinder(v3(0, 0.30, 0), v3(0, 0.72, 0), BASIN_R * 0.88, BASIN_R * 0.85, OCTAGON, SAND);
    b.addCylinder(v3(0, 0.72, 0), v3(0, 0.86, 0), BASIN_R * 0.74, BASIN_R * 0.74, OCTAGON, SAND_DK);
    var s: i32 = 0;
    while (s < OCTAGON) : (s += 1) {
        const a0 = std.math.tau * @as(f32, @floatFromInt(s)) / @as(f32, OCTAGON);
        const a1 = std.math.tau * @as(f32, @floatFromInt(s + 1)) / @as(f32, OCTAGON);
        const na = (a0 + a1) * 0.5;
        const half = mathx.sinf((a1 - a0) * 0.5) * BASIN_R * 0.80;
        grecaInto(
            &b,
            &rng,
            v3(mathx.cosf(na) * BASIN_R * 0.87 - mathx.sinf(na) * half, 0.34, mathx.sinf(na) * BASIN_R * 0.87 + mathx.cosf(na) * half),
            v3(mathx.cosf(na) * BASIN_R * 0.87 + mathx.sinf(na) * half, 0.34, mathx.sinf(na) * BASIN_R * 0.87 - mathx.cosf(na) * half),
            v3(mathx.cosf(na), 0, mathx.sinf(na)),
            0.34,
            0.14,
            0.52,
        );
    }

    const GONE_0: i32 = 5;
    const GONE_1: i32 = 7;
    var i: i32 = 0;
    while (i < 16) : (i += 1) {
        if (i >= GONE_0 and i <= GONE_1) continue;
        const a = std.math.tau * (@as(f32, @floatFromInt(i)) + 0.5) / 16.0;
        const half = std.math.tau * BASIN_R * 0.78 / 16.0 * 0.54;
        b.setMat(.stone);
        b.addBox(
            v3(mathx.cosf(a) * BASIN_R * 0.78, 1.02 + rng.signed() * 0.02, mathx.sinf(a) * BASIN_R * 0.78),
            v3(-mathx.sinf(a) * half, 0, mathx.cosf(a) * half),
            v3(0, 0.22, 0),
            v3(mathx.cosf(a) * 0.16, 0, mathx.sinf(a) * 0.16),
            stoneTone(&rng),
        );
        if (rng.float() < 0.24) continue;
        b.setMat(.gilt);
        b.addBox(
            v3(mathx.cosf(a) * BASIN_R * 0.78, 1.26, mathx.sinf(a) * BASIN_R * 0.78),
            v3(-mathx.sinf(a) * half * 0.92, 0, mathx.cosf(a) * half * 0.92),
            v3(0, 0.045, 0),
            v3(mathx.cosf(a) * 0.17, 0, mathx.sinf(a) * 0.17),
            goldTone(&rng),
        );
    }

    art.starInto(&b, &rng, v3(0, 0.90, 0), BASIN_R * 0.54, 0.09, SAND_LT, SUN);
    b.setMat(.marble);
    art.starInto(&b, &rng, v3(0, 0.93, 0), BASIN_R * 0.42, 0.06, EMERALD_DK, SUN);
    const ga = std.math.tau * 6.5 / 16.0;
    b.setMat(.stone);
    var f: i32 = 0;
    while (f < 7) : (f += 1) {
        b.addBox(
            v3(mathx.cosf(ga) * BASIN_R * rng.range(1.05, 1.75), rng.range(0.10, 0.26), mathx.sinf(ga) * BASIN_R * rng.range(1.05, 1.75)),
            v3(rng.range(0.30, 0.62), rng.signed() * 0.10, rng.signed() * 0.18),
            v3(rng.signed() * 0.12, rng.range(0.10, 0.20), 0),
            v3(rng.signed() * 0.16, 0, rng.range(0.24, 0.52)),
            stoneTone(&rng),
        );
    }
    var d: i32 = 0;
    while (d < 14) : (d += 1) {
        const a = ga + rng.signed() * 1.1;
        const dd = rng.range(0.1, BASIN_R * 0.48);
        b.addBlob(v3(mathx.cosf(a) * dd, 0.94 + rng.range(0, 0.06), mathx.sinf(a) * dd), v3(rng.range(0.30, 0.80), rng.range(0.04, 0.12), rng.range(0.30, 0.80)), 2, 7, IRONWASH);
    }

    b.setMat(.stone);
    b.addCylinder(v3(0, 0.90, 0), v3(0, 1.28, 0), 0.62, 0.52, 10, stoneTone(&rng));
    art.giltRingInto(&b, &rng, 0, 1.20, 0, 0.58, 0.14, 10, SUN);
    gemInto(&b, &rng, v3(0.05, 1.32, 0.05), 0.26);
    art.chipsInto(&b, &rng, 0, 0, BASIN_R * 1.35, 0.08, 0.22, 12);
    return b.toModel(shader);
}



pub const POLE_H: f32 = 11.4;
pub const POLE_TOP: f32 = 12.6;

pub fn palaceBannerMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A_11_0D);

    b.setMat(.stone);
    b.addCube(v3(0, 0.20, 0), v3(2.20, 0.40, 2.20), SAND_DK);
    const top = art.courseStack(&b, &rng, 0, 0.40, 0, 1.60, 1.60, 0.36, 3, 0.16, SUN);
    for ([_][2]f32{ .{ 0, 1 }, .{ 0, -1 }, .{ 1, 0 }, .{ -1, 0 } }) |sg| {
        const face = v3(sg[0], 0, sg[1]);
        const along = v3(-sg[1], 0, sg[0]);
        grecaInto(
            &b,
            &rng,
            v3(-along.x * 0.56 + sg[0] * 0.68, 0.62, -along.z * 0.56 + sg[1] * 0.68),
            v3(along.x * 0.56 + sg[0] * 0.68, 0.62, along.z * 0.56 + sg[1] * 0.68),
            face,
            0.62,
            0.11,
            0.55,
        );
    }
    b.setMat(.stone);
    b.addCube(v3(0, top + 0.18, 0), v3(1.02, 0.36, 1.02), SAND_LT);

    const lean: f32 = 0.22;
    b.setMat(.gilt);
    b.addCylinder(v3(0, top + 0.30, 0), v3(lean * 0.35, POLE_H * 0.55, 0.05), 0.16, 0.13, 10, PGOLD);
    b.addCylinder(v3(lean * 0.35, POLE_H * 0.55, 0.05), v3(lean, POLE_H, 0.14), 0.13, 0.095, 10, PGOLD_LT);
    art.giltRingInto(&b, &rng, lean * 0.35, POLE_H * 0.55, 0.05, 0.19, 0.12, 8, SUN);
    const bar = POLE_H - 0.90;
    b.addCylinder(v3(lean * 0.9, bar, 0.12), v3(lean * 0.9 - 1.85, bar + 0.10, 0.12), 0.075, 0.060, 8, PGOLD);
    b.setMat(.marble);
    b.addBlob(v3(lean, POLE_H + 0.22, 0.14), v3(0.20, 0.26, 0.20), 2, 8, EMERALD);
    b.setMat(.gilt);
    var z: i32 = 0;
    while (z < 8) : (z += 1) {
        const a = std.math.tau * (@as(f32, @floatFromInt(z)) + 0.5) / 8.0;
        const long = z == 0 or z == 2 or z == 4 or z == 6;
        const reach: f32 = if (long) 0.46 else 0.30;
        b.addBox(
            v3(lean + mathx.cosf(a) * (0.28 + reach * 0.5), POLE_H + 0.22 + mathx.sinf(a) * 0.10, 0.14 + mathx.sinf(a) * (0.28 + reach * 0.5)),
            v3(mathx.cosf(a) * reach * 0.5, 0, mathx.sinf(a) * reach * 0.5),
            v3(0, 0.030, 0),
            v3(-mathx.sinf(a) * 0.035, 0, mathx.cosf(a) * 0.035),
            goldTone(&rng),
        );
    }

    // ONE SHEET IN SLATS, NOT A STACK OF FLAGS: one wave runs the whole drop (`propart.clothInto`'s law).
    const SL: i32 = 15;
    const drop: f32 = 6.20;
    const wide: f32 = 1.72;
    var i: i32 = 0;
    while (i < SL) : (i += 1) {
        const t = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, SL);
        const y = bar - 0.14 - t * drop;
        const curl = mathx.sinf(t * 3.2 + 0.6) * 0.34 * t;
        const torn = t > 0.72;
        const lose = if (torn) (t - 0.72) / 0.28 * rng.range(0.25, 0.85) else 0;
        const hw = wide * 0.5 * (1.0 - lose);
        const cx = lean * 0.9 - 0.92 + (wide * 0.5 - hw) * (if (@mod(i, 2) == 0) @as(f32, 1) else -1) * 0.6;
        b.setMat(.cloth);
        b.addBox(
            v3(cx, y, 0.12 + curl),
            v3(hw, rng.signed() * 0.01, 0),
            v3(0, drop / @as(f32, SL) * 0.56, 0),
            v3(0, 0, 0.030 + @abs(curl) * 0.10),
            if (@mod(i, 3) == 0) BANNER_DK else BANNER,
        );
        if (@mod(i, 4) == 1) {
            b.setMat(.gilt);
            b.addBox(
                v3(cx, y, 0.12 + curl + 0.020),
                v3(hw * 0.86, 0, 0),
                v3(0, drop / @as(f32, SL) * 0.20, 0),
                v3(0, 0, 0.012),
                goldTone(&rng),
            );
        }
    }
    return b.toModel(shader);
}



pub const STELE_H: f32 = 2.70;
pub const STELE_TOP: f32 = 3.10;

pub fn wayStelaMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A_11_0E);

    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const a = std.math.tau * (@as(f32, @floatFromInt(i)) + 0.5) / 7.0;
        const d = rng.range(0.52, 0.86);
        const rr = rng.range(0.16, 0.30);
        b.addBlob(v3(mathx.cosf(a) * d, rr * 0.62, mathx.sinf(a) * d), v3(rr, rr * 0.72, rr * rng.range(0.8, 1.3)), 3, 7, stoneTone(&rng));
    }
    const lean = mathx.radians(5.5);
    const tipX = mathx.sinf(lean) * STELE_H;
    b.addBox(
        v3(tipX * 0.5, STELE_H * 0.5, 0),
        v3(mathx.cosf(lean) * 0.34, mathx.sinf(lean) * 0.34, 0),
        v3(-mathx.sinf(lean) * STELE_H * 0.5, mathx.cosf(lean) * STELE_H * 0.5, 0),
        v3(0, 0, 0.24),
        SAND,
    );
    b.addBox(
        v3(tipX + mathx.sinf(lean) * 0.14, STELE_H + 0.14, 0),
        v3(0.44, mathx.sinf(lean) * 0.44, 0),
        v3(0, 0.13, 0),
        v3(0, 0, 0.32),
        SAND_LT,
    );
    art.giltBandInto(&b, &rng, tipX, STELE_H + 0.14, 0, 0.44, 0.32, 0.16, SUN);
    glyphBandInto(&b, &rng, v3(tipX * 0.32, 0.55, 0.25), v3(tipX * 0.32, 1.95, 0.25), v3(0, 0, 1), 0.54, 0.10);
    glyphBandInto(&b, &rng, v3(tipX * 0.32, 1.95, -0.25), v3(tipX * 0.32, 0.55, -0.25), v3(0, 0, -1), 0.54, 0.10);

    for ([_][3]f32{ .{ 2.24, 34.0, 1.15 }, .{ 2.00, -128.0, 0.92 } }) |arm| {
        const y = arm[0];
        const a = mathx.radians(arm[1]);
        const reach = arm[2];
        const ax = mathx.cosf(a);
        const az = mathx.sinf(a);
        const root = v3(tipX * (y / STELE_H) + ax * 0.30, y, az * 0.30);
        b.setMat(.gilt);
        b.addBox(
            v3(root.x + ax * reach * 0.5, y, root.z + az * reach * 0.5),
            v3(ax * reach * 0.5, 0, az * reach * 0.5),
            v3(0, 0.115, 0),
            v3(-az * 0.035, 0, ax * 0.035),
            goldTone(&rng),
        );
        b.addBox(
            v3(root.x + ax * (reach + 0.16), y, root.z + az * (reach + 0.16)),
            v3(ax * 0.16, 0, az * 0.16),
            v3(0, 0.070, 0),
            v3(-az * 0.028, 0, ax * 0.028),
            PGOLD_LT,
        );
        b.setMat(.marble);
        b.addBlob(v3(root.x, y + 0.02, root.z), v3(0.13, 0.15, 0.13), 2, 7, gemTone(&rng));
    }
    b.setMat(.stone);
    art.chipsInto(&b, &rng, 0, 0, 1.4, 0.06, 0.16, 7);
    return b.toModel(shader);
}



pub const SHARD_TOP: f32 = 6.40;
pub const SHARD_LIGHT_Y: f32 = 2.30;

pub fn emeraldShardMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A_11_0F);

    b.setMat(.stone);
    b.addBlob(v3(0, 0.10, 0), v3(2.35, 0.62, 2.05), 3, 11, IRONWASH);
    var i: i32 = 0;
    while (i < 9) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.6, 2.4);
        const rr = rng.range(0.16, 0.44);
        b.addBlob(v3(mathx.cosf(a) * d, rr * 0.4, mathx.sinf(a) * d), v3(rr, rr * 0.45, rr * rng.range(0.8, 1.4)), 3, 7, if (rng.float() < 0.5) SAND_DK else IRONWASH);
    }

    const spec = [_][5]f32{
        .{ 0.10, 0.20, 5.90, 0.72, 0.34 },
        .{ 2.15, -0.55, 4.10, 0.52, 0.62 },
        .{ 4.05, 0.35, 3.20, 0.44, 0.78 },
        .{ 5.35, -0.30, 2.35, 0.36, 0.55 },
        .{ 1.20, 0.72, 2.90, 0.30, 0.90 },
    };
    for (spec) |s| {
        const yaw = s[0];
        const tilt = s[1];
        const len = s[2];
        const rad = s[3];
        const off = s[4];
        const dir = mathx.normV(v3(mathx.cosf(yaw) * tilt, 1.0, mathx.sinf(yaw) * tilt));
        crystalInto(&b, &rng, v3(mathx.cosf(yaw) * off, 0.22, mathx.sinf(yaw) * off), dir, len, rad);
    }
    b.setMat(.marble);
    var f: i32 = 0;
    while (f < 11) : (f += 1) {
        const a = rng.angle();
        const d = rng.range(1.4, 3.2);
        const l = rng.range(0.26, 0.72);
        b.addCylinder(
            v3(mathx.cosf(a) * d, 0.12, mathx.sinf(a) * d),
            v3(mathx.cosf(a) * (d + l), 0.10, mathx.sinf(a) * (d + l) + rng.signed() * 0.2),
            rng.range(0.06, 0.14),
            rng.range(0.04, 0.09),
            6,
            gemTone(&rng),
        );
    }
    return b.toModel(shader);
}



pub const KIOSK_HALF: f32 = 2.90;
pub const KIOSK_PIER: f32 = 0.46;
pub const KIOSK_SPRING: f32 = 3.60;
pub const KIOSK_TOP: f32 = 7.90;

pub fn palaceKioskMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A_11_10);

    b.setMat(.stone);
    b.addCube(v3(0, 0.14, 0), v3(KIOSK_HALF * 2.6, 0.28, KIOSK_HALF * 2.6), SAND_DK);
    b.addCube(v3(0, 0.38, 0), v3(KIOSK_HALF * 2.35, 0.20, KIOSK_HALF * 2.35), stoneTone(&rng));
    art.starInto(&b, &rng, v3(0, 0.48, 0), KIOSK_HALF * 0.80, 0.06, SAND_LT, SUN);

    var p: i32 = 0;
    while (p < 4) : (p += 1) {
        const sx: f32 = if (p == 0 or p == 3) -1 else 1;
        const sz: f32 = if (p < 2) -1 else 1;
        const px = sx * KIOSK_HALF;
        const pz = sz * KIOSK_HALF;
        const lost: f32 = if (p == 2) 0.55 else 0;
        _ = art.courseStack(&b, &rng, px, 0.48, pz, KIOSK_PIER * 2.0, KIOSK_PIER * 2.0, 0.52, @as(i32, @intFromFloat((KIOSK_SPRING - 0.48 - lost) / 0.52)), 0.05, SUN);
        art.giltBandInto(&b, &rng, px, 1.40, pz, KIOSK_PIER * 1.02, KIOSK_PIER * 1.02, 0.18, SUN);
        art.muqarnasInto(&b, &rng, v3(px - sx * KIOSK_PIER * 0.40, KIOSK_SPRING - 0.94 - lost, pz), v3(-sx, 0, 0), 0.82, 0.94, 0.70, SUN);
        art.muqarnasInto(&b, &rng, v3(px, KIOSK_SPRING - 0.94 - lost, pz - sz * KIOSK_PIER * 0.40), v3(0, 0, -sz), 0.82, 0.94, 0.66, SUN);
        if (p == 2) art.crackInto(&b, v3(px + KIOSK_PIER * 0.98, 0.7, pz - 0.3), v3(rng.signed() * 0.2, 0.97, 0), v3(0, 0, 1), 1.9, 0.026, 0.035);
    }

    for ([_][2]f32{ .{ 0, 1 }, .{ 0, -1 }, .{ 1, 0 }, .{ -1, 0 } }, 0..) |sg, si| {
        const broke = si == 2;
        const along = v3(-sg[1], 0, sg[0]);
        const span = 180.0 + HORSE_EXTRA * 2.0;
        const NV: i32 = 17;
        var i: i32 = 0;
        while (i < NV) : (i += 1) {
            if (broke and i >= 7 and i <= 9) continue;
            const t = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, NV);
            const a = mathx.radians(-HORSE_EXTRA + span * t);
            const ca = mathx.cosf(a);
            const sa = mathx.sinf(a);
            const rr = KIOSK_HALF - KIOSK_PIER * 0.35;
            const half = mathx.radians(span) * rr / @as(f32, NV) * 0.5 * rng.range(1.03, 1.16);
            const rad = 0.30;
            const gilded = @mod(i, 2) == 0 and rng.float() < 0.70;
            b.setMat(if (gilded) .gilt else .stone);
            b.addBox(
                v3(along.x * -ca * rr + sg[0] * KIOSK_HALF, KIOSK_SPRING + sa * rr, along.z * -ca * rr + sg[1] * KIOSK_HALF),
                v3(along.x * sa * half, ca * half, along.z * sa * half),
                v3(along.x * -ca * rad, sa * rad, along.z * -ca * rad),
                v3(sg[0] * 0.32, 0, sg[1] * 0.32),
                if (gilded) goldTone(&rng) else stoneTone(&rng),
            );
        }
    }

    const cor = KIOSK_SPRING + (KIOSK_HALF - KIOSK_PIER * 0.35) * 0.92;
    b.setMat(.stone);
    b.addCube(v3(0, cor + 0.24, 0), v3((KIOSK_HALF + KIOSK_PIER) * 2.30, 0.48, (KIOSK_HALF + KIOSK_PIER) * 2.30), SAND_LT);
    for ([_][2]f32{ .{ 0, 1 }, .{ 0, -1 }, .{ 1, 0 }, .{ -1, 0 } }) |sg| {
        const along = v3(-sg[1], 0, sg[0]);
        const e = (KIOSK_HALF + KIOSK_PIER) * 1.13;
        grecaInto(
            &b,
            &rng,
            v3(-along.x * e + sg[0] * e, cor + 0.56, -along.z * e + sg[1] * e),
            v3(along.x * e + sg[0] * e, cor + 0.56, along.z * e + sg[1] * e),
            v3(sg[0], 0, sg[1]),
            0.62,
            0.14,
            0.60,
        );
    }
    b.setMat(.stone);
    b.addCylinder(v3(0, cor + 0.48, 0), v3(0, cor + 0.92, 0), KIOSK_HALF * 1.14, KIOSK_HALF * 1.02, OCTAGON, SAND);
    const dr = KIOSK_HALF * 1.02;
    const NR: i32 = 12;
    var k: i32 = 0;
    while (k < NR) : (k += 1) {
        const az = std.math.tau * (@as(f32, @floatFromInt(k)) + 0.5) / @as(f32, NR);
        var j: i32 = 0;
        while (j < 5) : (j += 1) {
            const t0 = @as(f32, @floatFromInt(j)) / 5.0;
            const t1 = @as(f32, @floatFromInt(j + 1)) / 5.0;
            const e0 = std.math.pi * 0.5 * t0;
            const e1 = std.math.pi * 0.5 * t1;
            const rm = (mathx.cosf(e0) + mathx.cosf(e1)) * 0.5 * dr;
            const ym = cor + 0.92 + (mathx.sinf(e0) + mathx.sinf(e1)) * 0.5 * dr * 0.62;
            const along2 = (mathx.sinf(e1) - mathx.sinf(e0)) * dr * 0.40;
            const wide = std.math.tau * rm / @as(f32, NR) * 0.56;
            b.setMat(.gilt);
            b.addBox(
                v3(mathx.cosf(az) * rm, ym, mathx.sinf(az) * rm),
                v3(-mathx.sinf(az) * wide, 0, mathx.cosf(az) * wide),
                v3(0, along2, 0),
                v3(mathx.cosf(az) * 0.13, 0, mathx.sinf(az) * 0.13),
                goldTone(&rng),
            );
        }
    }
    b.setMat(.gilt);
    b.addCylinder(v3(0, cor + 0.90, 0), v3(0, cor + 0.20, 0), 0.10, 0.075, 8, PGOLD_DK);
    gemInto(&b, &rng, v3(0, cor - 0.16, 0), 0.40);
    b.setMat(.stone);
    art.chipsInto(&b, &rng, 0, 0, KIOSK_HALF * 1.8, 0.09, 0.26, 10);
    return b.toModel(shader);
}


test "the palace reads WARM and PALE against orange sand, and its jewel is a light" {
    const lit = struct {
        fn f(c: rl.Color) f32 {
            return gfx.screenOf(@floatFromInt(c.r));
        }
    }.f;
    const body = lit(SAND);
    std.debug.print("\n  sun palace: sandstone {d:.0} on screen (gilt ruins' ashlar {d:.0}), ironwash {d:.0}, gold {d:.0} over it (the ruins' gold {d:.0}, under theirs)\n", .{ body, lit(gold.ASHLAR), lit(IRONWASH), lit(PGOLD), lit(gold.GOLD) });
    try std.testing.expect(body > lit(gold.ASHLAR));
    try std.testing.expect(@as(f32, @floatFromInt(SAND.r)) > @as(f32, @floatFromInt(SAND.b)) * 1.8);
    try std.testing.expect(@as(f32, @floatFromInt(gold.ASHLAR.r)) < @as(f32, @floatFromInt(gold.ASHLAR.b)) * 1.8);
    try std.testing.expect(lit(IRONWASH) < body * 0.75 and IRONWASH.r > IRONWASH.b);
    try std.testing.expect(lit(PGOLD) > body and lit(gold.GOLD) < lit(gold.ASHLAR));
    try std.testing.expect(@as(f32, @floatFromInt(PGOLD.r)) > @as(f32, @floatFromInt(PGOLD.b)) * 4.0);
    try std.testing.expect(EMERALD_LT.a < EMERALD.a and EMERALD.a < EMERALD_DK.a);
    try std.testing.expect(EMERALD.g > EMERALD.r * 8 and EMERALD.g > EMERALD.b * 2);
}

test "THE FAMILY IS THREE LAYERS AND THE SPIRE IS THE LANDMARK" {
    try std.testing.expect(SPIRE_TOP > GATE_TOP and GATE_TOP > IDOL_TOP);
    try std.testing.expect(IDOL_TOP > VAULT_TOP and VAULT_TOP > HALL_TOP);
    try std.testing.expect(HALL_TOP > KIOSK_TOP and KIOSK_TOP > SHARD_TOP);
    try std.testing.expect((GATE_PIER_X - GATE_PIER_HALF) * 2.0 > 8.0);
    try std.testing.expect(HALL_DOOR_HALF * 2.0 > 4.0 and HALL_DOOR_HEAD > 4.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), PSTAIR_SEG / @as(f32, @floatFromInt(PSTAIR_TREADS)), 1e-6);
    std.debug.print("  sun palace heights: spire {d:.1} gate {d:.1} watcher {d:.1} vault {d:.1} hall {d:.1} kiosk {d:.1}\n", .{ SPIRE_TOP, GATE_TOP, IDOL_TOP, VAULT_TOP, HALL_TOP, KIOSK_TOP });
}
