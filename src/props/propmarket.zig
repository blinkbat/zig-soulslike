const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const art = @import("propart.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// **THE CARAVAN'S GOODS** (owner's brief: merchant hut, packs, tables, racks). Everything a caravaneer sets down
// when it stops, and everything here obeys one rule: **IT IS TIED, AND THE TIE SHOWS.** A crate is furniture; a
// bale under a rope with the rope biting into it is freight, and the difference is what makes a market read as a
// place somebody arrived at rather than a shop that was always there.
//
// **NOTHING HERE IS SQUARE ON.** Poles lean, a table's legs are cut at different lengths, a stack has slipped.
// `props.biome` files the family under `.ash`, which RECORDS the region it was authored against and does not act
// on it: nothing sows off that table, so the pieces go down by hand.
//
// Solved, not picked (`albedo = screen^2.2 / 1.72`, AGENTS.md): the awning has to be the PALEST thing in the
// region so a booth reads from across a field, and the freight under it the darkest so the goods read as mass.
//   canvas 196 -> 82    canvas lit 214 -> 102    sack 150 -> 46    bale 124 -> 31    rope 168 -> 59

/// Bleached cotton, and the one thing here that is brighter than the ash it stands on.
pub const CANVAS = rgba(82, 78, 66, 255);
pub const CANVAS_LT = rgba(102, 97, 84, 255);
/// The weather side, where the sun has had it: warmer and dirtier, never darker by much.
pub const CANVAS_SUN = rgba(88, 76, 58, 255);
const SACK = rgba(46, 40, 30, 255);
const SACK_LT = rgba(60, 52, 39, 255);
const BALE = rgba(31, 27, 21, 255);
const ROPE = rgba(59, 51, 36, 255);
const ROPE_LT = rgba(74, 64, 46, 255);
const POLE = art.TIMBER;
const POLE_LT = art.TIMBER_DK;
const PLANK = rgba(50, 38, 25, 255);
const PLANK_LT = rgba(66, 50, 33, 255);
/// The weave the caravaneer wears, so his stall and his coat really are off one loom — `propart` holds it, and
/// this used to be a copy of the literals under a comment that said otherwise.
const WEAVE = art.WEAVE;
const WEAVE_DK = art.WEAVE_DK;
const MADDER = art.MADDER;
const CLAY = rgba(54, 38, 26, 255);
const CLAY_LT = rgba(72, 52, 34, 255);
const BRASS = rgba(108, 82, 34, 255);
const IRON = art.IRON;
/// Harness leather. `propart` has no leather at all — every family that needs it owns its own, because a saddle
/// in a desert camp is bleached and one on a village door is not.
const TACK = rgba(38, 28, 20, 255);
const TACK_LT = rgba(54, 41, 29, 255);

/// **A ROPE THAT DOES NOT BITE IS A PAINTED LINE.** Three capsules over a bale: the two ends flat on the faces
/// and the middle pulled IN, so the cord dents the thing it is holding. `bite` is that inset.
fn lashInto(b: *Builder, rng: *mathx.Rng, c: rl.Vector3, half: rl.Vector3, along: bool, bite: f32) void {
    b.setMat(.cloth);
    // **THICK, AND PALER THAN WHAT IT IS HOLDING.** At 0.026 in the bale's own tone the cord was invisible and
    // nine bales read as a stack of crates; a rope you cannot see is a rope that is not doing its job.
    const r = 0.042 * rng.range(0.85, 1.15);
    const w = if (along) half.z else half.x;
    const d = if (along) half.x else half.z;
    const off = (rng.float() - 0.5) * w * 0.5;
    const a = if (along) v3(c.x - d, c.y, c.z + off) else v3(c.x + off, c.y, c.z - d);
    const z = if (along) v3(c.x + d, c.y, c.z + off) else v3(c.x + off, c.y, c.z + d);
    const mid = v3((a.x + z.x) * 0.5, c.y + half.y - bite, (a.z + z.z) * 0.5);
    b.addCapsule(a, mid, r, r, 6, ROPE_LT);
    b.addCapsule(mid, z, r, r, 6, ROPE_LT);
    // The knot, off centre, because nobody ties in the middle.
    b.addBlob(mathx.lerpV(a, mid, rng.range(0.3, 0.7)), v3(r * 1.9, r * 1.5, r * 1.9), 3, 7, ROPE);
    // …and a SECOND turn, across the first: one strap is a belt, two are freight.
    const b2 = if (along) v3(c.x, c.y, c.z - half.z) else v3(c.x - half.x, c.y, c.z);
    const e2 = if (along) v3(c.x, c.y, c.z + half.z) else v3(c.x + half.x, c.y, c.z);
    const m2 = v3((b2.x + e2.x) * 0.5, c.y + half.y - bite * 0.8, (b2.z + e2.z) * 0.5);
    b.addCapsule(b2, m2, r * 0.82, r * 0.82, 6, ROPE);
    b.addCapsule(m2, e2, r * 0.82, r * 0.82, 6, ROPE);
}

/// One sack or bale. **NOT A BOX**: the corners are pulled by whatever is inside, so it is a rounded slab with
/// two lumps proud of it and a rope over the top.
fn baleInto(b: *Builder, rng: *mathx.Rng, c: rl.Vector3, half: rl.Vector3, yaw: f32, tone: rl.Color) void {
    b.setMat(.cloth);
    const cy = mathx.cosf(yaw);
    const sy = mathx.sinf(yaw);
    b.addBox(
        c,
        v3(cy * half.x, rng.signed() * 0.02, sy * half.x),
        v3(0, half.y, 0),
        v3(-sy * half.z, rng.signed() * 0.02, cy * half.z),
        tone,
    );
    // **THE LUMPS BREAK THE CORNERS, SO THEY HAVE TO BE BIG.** At 0.6 of the half-extent they sat inside the box
    // and the box was the silhouette; at 0.95 they push past it and the thing reads as a bag with stuff in it.
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const rr = rng.range(0.72, 0.98);
        b.addBlob(
            v3(c.x + rng.signed() * half.x * 0.62, c.y + half.y * rng.range(-0.1, 0.6), c.z + rng.signed() * half.z * 0.62),
            v3(half.x * rr * 0.72, half.y * rr * 0.86, half.z * rr * 0.72),
            4,
            9,
            if (rng.float() < 0.4) SACK_LT else tone,
        );
    }
    lashInto(b, rng, c, half, rng.float() < 0.5, half.y * 0.22);
}

/// A leaning pole with a blunt top. `lean` is the tilt in radians and `at` the bearing it leans on — every upright
/// in this family gets one, because a plumb pole in a hand-pitched camp is the thing that reads as a game asset.
fn poleInto(b: *Builder, from: rl.Vector3, h: f32, r: f32, lean: f32, at: f32, tone: rl.Color) rl.Vector3 {
    b.setMat(.wood);
    const top = v3(from.x + mathx.cosf(at) * h * mathx.sinf(lean), from.y + h, from.z + mathx.sinf(at) * h * mathx.sinf(lean));
    b.addCylinder(from, top, r, r * 0.86, 7, tone);
    b.addBlob(top, v3(r * 1.15, r * 0.8, r * 1.15), 3, 7, POLE_LT);
    return top;
}

/// **A STRETCHED SHEET SAGS, AND THE SAG IS THE WHOLE OBJECT.** Quads across a grid whose height dips toward the
/// middle of each span — flat, a canvas is a lid, and a lid on four sticks reads as a table upside down.
fn canopyInto(b: *Builder, rng: *mathx.Rng, corners: [4]rl.Vector3, sag: f32, tone: rl.Color, toneLt: rl.Color) void {
    b.setMat(.cloth);
    const NU = 5;
    const NV = 5;
    var iu: usize = 0;
    while (iu + 1 < NU) : (iu += 1) {
        var iv: usize = 0;
        while (iv + 1 < NV) : (iv += 1) {
            const ua = @as(f32, @floatFromInt(iu)) / (NU - 1);
            const ub = @as(f32, @floatFromInt(iu + 1)) / (NU - 1);
            const va = @as(f32, @floatFromInt(iv)) / (NV - 1);
            const vb = @as(f32, @floatFromInt(iv + 1)) / (NV - 1);
            const p00 = sheetAt(corners, ua, va, sag);
            const p10 = sheetAt(corners, ub, va, sag);
            const p11 = sheetAt(corners, ub, vb, sag);
            const p01 = sheetAt(corners, ua, vb, sag);
            // Tone follows the SAG: the belly of the sheet is in its own shade, the taut edges catch the sun.
            const dip = (dipAt(ua, va) + dipAt(ub, vb)) * 0.5;
            sheetQuad(b, p00, p01, p11, p10, art.weathered(toneLt, tone, mathx.clampF(dip * 1.4, 0, 1)));
            _ = rng;
        }
    }
}

/// **A SAGGING SHEET HAS NO ONE NORMAL**, so each quad gets its own off its own corners. Flat-shaded on purpose:
/// smoothing a canvas across the sag loses the crease that makes it read as cloth under tension.
fn quadNormal(a: rl.Vector3, b: rl.Vector3, c: rl.Vector3) rl.Vector3 {
    const n = mathx.crossV(mathx.subV(b, a), mathx.subV(c, a));
    return if (mathx.lenV(n) > 1e-5) mathx.normV(n) else v3(0, 1, 0);
}

/// **CLOTH IS SEEN FROM BOTH SIDES, SO EVERY SHEET IS LAID TWICE.** One winding and the awning, the booth's roof
/// and the rack's hangings all VANISHED — a single-sided canopy is invisible from underneath, which is where you
/// stand, because the shade is the entire reason the thing is there.
fn sheetQuad(b: *Builder, a: rl.Vector3, c: rl.Vector3, d: rl.Vector3, e: rl.Vector3, col: rl.Color) void {
    const n = quadNormal(a, c, d);
    b.quad(a, c, d, e, n, col);
    b.quad(e, d, c, a, mathx.scaleV(n, -1), col);
}

fn dipAt(u: f32, v: f32) f32 {
    return mathx.sinf(u * std.math.pi) * mathx.sinf(v * std.math.pi);
}

fn sheetAt(c: [4]rl.Vector3, u: f32, v: f32, sag: f32) rl.Vector3 {
    const a = mathx.lerpV(c[0], c[1], u);
    const bb = mathx.lerpV(c[3], c[2], u);
    var p = mathx.lerpV(a, bb, v);
    p.y -= sag * dipAt(u, v);
    return p;
}

pub const HUT_W: f32 = 2.30;
pub const HUT_D: f32 = 1.95;
pub const HUT_TOP: f32 = 2.62;
/// **THE MERCHANT'S HUT: A BOOTH, AND ITS FRONT IS OPEN.** Three walls of hung cloth on a leaning frame, a
/// counter across the mouth and the goods behind it. **THE OPEN SIDE FACES -Z**, which is the bearing the object
/// viewer looks from and a placed yaw of 0 presents — a booth inspected from its closed back is a crate.
pub fn merchantHutMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x4A17);
    const hw = HUT_W * 0.5;
    const hd = HUT_D * 0.5;
    const eave = 1.94;
    // FOUR CORNER POLES, each leaning its own way and none the same height: the frame is lashed, not joined.
    var top: [4]rl.Vector3 = undefined;
    const feet = [4]rl.Vector3{
        v3(-hw, 0, hd),
        v3(hw, 0, hd),
        v3(hw, 0, -hd),
        v3(-hw, 0, -hd),
    };
    for (feet, 0..) |f, i| {
        // The BACK pair stand taller, so the roof falls toward the customer and the rain runs off the front.
        const h = eave * (if (i < 2) @as(f32, 1.14) else 1.0) * rng.range(0.97, 1.03);
        top[i] = poleInto(&b, f, h, 0.058, rng.range(0.02, 0.06), rng.angle(), if (@mod(i, 2) == 0) POLE else POLE_LT);
    }
    canopyInto(&b, &rng, top, 0.34, CANVAS_SUN, CANVAS_LT);
    // THREE WALLS of hung cloth, and each hangs to a different height off the ground — none of them reaches it.
    b.setMat(.cloth);
    const walls = [3][2]usize{ .{ 0, 1 }, .{ 1, 2 }, .{ 3, 0 } };
    for (walls, 0..) |w, wi| {
        const a = top[w[0]];
        const z = top[w[1]];
        const drop = rng.range(0.62, 0.86) * @min(a.y, z.y);
        const NU = 4;
        var i: usize = 0;
        while (i < NU) : (i += 1) {
            const t0 = @as(f32, @floatFromInt(i)) / NU;
            const t1 = @as(f32, @floatFromInt(i + 1)) / NU;
            const pa = mathx.lerpV(a, z, t0);
            const pb = mathx.lerpV(a, z, t1);
            // Panels of cloth, each pulled in a little at the bottom where the wind has it.
            const bow = rng.range(0.02, 0.09);
            const q0 = v3(pa.x, pa.y, pa.z);
            const q1 = v3(pa.x * (1.0 - bow), pa.y - drop, pa.z * (1.0 - bow));
            const q2 = v3(pb.x * (1.0 - bow), pb.y - drop, pb.z * (1.0 - bow));
            const q3 = v3(pb.x, pb.y, pb.z);
            sheetQuad(&b, q0, q1, q2, q3, if (wi == 0) WEAVE else if (@mod(i, 2) == 0) CANVAS else CANVAS_SUN);
        }
    }
    // THE COUNTER across the open mouth — waist high, one plank, and it overhangs its trestles.
    b.setMat(.wood);
    const cy: f32 = 0.92;
    b.addBox(v3(0, cy, -hd + 0.10), v3(hw * 1.06, rng.signed() * 0.012, 0), v3(0, 0.045, 0), v3(0, 0.02, 0.22), PLANK);
    for ([_]f32{ -1.0, 1.0 }) |side| {
        b.addCylinder(v3(side * hw * 0.74, 0, -hd + 0.10), v3(side * hw * 0.74, cy - 0.04, -hd + 0.12), 0.048, 0.042, 6, POLE);
    }
    // …and what is ON it: a scale, a coin dish and a jar. The goods are the reason the booth exists.
    b.setMat(.gilt);
    b.addCylinder(v3(-hw * 0.44, cy + 0.05, -hd + 0.10), v3(-hw * 0.44, cy + 0.30, -hd + 0.11), 0.010, 0.009, 6, BRASS);
    b.addCylinder(v3(-hw * 0.44 - 0.13, cy + 0.28, -hd + 0.10), v3(-hw * 0.44 + 0.13, cy + 0.31, -hd + 0.11), 0.006, 0.006, 5, BRASS);
    for ([_]f32{ -1.0, 1.0 }) |side| {
        b.addBlob(v3(-hw * 0.44 + side * 0.13, cy + 0.22, -hd + 0.10), v3(0.036, 0.008, 0.036), 3, 9, BRASS);
    }
    b.addBlob(v3(hw * 0.30, cy + 0.06, -hd + 0.06), v3(0.058, 0.014, 0.058), 3, 10, BRASS);
    b.setMat(.stone);
    b.addBlob(v3(hw * 0.62, cy + 0.12, -hd + 0.12), v3(0.070, 0.090, 0.070), 4, 9, CLAY);
    b.addCylinder(v3(hw * 0.62, cy + 0.19, -hd + 0.12), v3(hw * 0.62, cy + 0.25, -hd + 0.12), 0.030, 0.034, 8, CLAY_LT);
    // THE FREIGHT in the back of the booth, half in shadow, which is what makes the inside read as deep.
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const fi = @as(f32, @floatFromInt(i));
        baleInto(&b, &rng, v3(-hw * 0.5 + fi * hw * 0.5, 0.20, hd * 0.55), v3(0.24, 0.20, 0.19), rng.angle(), if (@mod(i, 2) == 0) BALE else SACK);
    }
    return b.toModel(shader);
}

pub const PACK_TOP: f32 = 1.42;
pub const PACK_R: f32 = 0.95;
/// **A STACK THAT HAS SLIPPED.** Bales roped in a pile with the top one off the line and a pack-saddle thrown
/// over the whole thing — the saddle is what says these came off an animal and were not delivered.
pub fn packStackMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x4A18);
    // Three courses, each smaller, each rotated and offset off the one below.
    var y: f32 = 0;
    var cx: f32 = 0;
    var cz: f32 = 0;
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / 2.0;
        const hx = mathx.lerpF(0.42, 0.26, t) * rng.range(0.9, 1.1);
        const hz = mathx.lerpF(0.34, 0.22, t) * rng.range(0.9, 1.1);
        const hy = mathx.lerpF(0.22, 0.16, t);
        baleInto(&b, &rng, v3(cx, y + hy, cz), v3(hx, hy, hz), rng.angle(), if (@mod(i, 2) == 0) BALE else SACK);
        y += hy * 1.85;
        cx += rng.signed() * 0.12;
        cz += rng.signed() * 0.10;
    }
    // THE PACK-SADDLE over the top: two padded bars and a girth, thrown on rather than fitted.
    b.setMat(.leather);
    const sy = y + 0.06;
    for ([_]f32{ -1.0, 1.0 }) |side| {
        b.addCapsule(
            v3(cx - 0.30, sy + side * 0.02, cz + side * 0.14),
            v3(cx + 0.28, sy - side * 0.03, cz + side * 0.16),
            0.055,
            0.048,
            7,
            TACK_LT,
        );
    }
    b.addBox(v3(cx, sy + 0.05, cz + 0.15), v3(0.20, 0.02, 0), v3(0, 0.035, 0), v3(0, 0.01, 0.13), TACK);
    // THE PADS under the bars — a saddle is a cushion on a frame, and without them the bars are two sticks.
    for ([_]f32{ -1.0, 1.0 }) |side| {
        b.addBlob(v3(cx - 0.08, sy - 0.05, cz + side * 0.15), v3(0.15, 0.055, 0.075), 4, 9, SACK);
        b.addBlob(v3(cx + 0.16, sy - 0.05, cz + side * 0.16), v3(0.10, 0.048, 0.070), 4, 8, SACK_LT);
    }
    b.setMat(.cloth);
    b.addCapsule(v3(cx - 0.05, sy, cz + 0.30), v3(cx - 0.10, 0.10, cz + 0.34), 0.026, 0.022, 5, ROPE);
    b.setMat(.gilt);
    b.addBlob(v3(cx + 0.18, sy + 0.04, cz + 0.20), v3(0.026, 0.020, 0.010), 3, 7, BRASS);
    // A SPILLED one at the foot, split, with the grain out of it — a stack this size loses one.
    b.setMat(.cloth);
    baleInto(&b, &rng, v3(cx - 0.62, 0.13, cz + 0.42), v3(0.24, 0.13, 0.19), rng.angle(), SACK_LT);
    b.setMat(.plant);
    var g: i32 = 0;
    while (g < 12) : (g += 1) {
        const a = rng.angle();
        const d = rng.range(0.05, 0.34);
        const rr = rng.range(0.016, 0.034);
        b.addBlob(v3(cx - 0.62 + mathx.cosf(a) * d, rr * 0.5, cz + 0.42 + mathx.sinf(a) * d * 0.8), v3(rr, rr * 0.45, rr), 2, 6, if (rng.float() < 0.5) art.GRASS_GOLD else art.SEED);
    }
    return b.toModel(shader);
}

pub const TABLE_TOP: f32 = 0.94;
pub const TABLE_W: f32 = 1.85;
/// **A TRESTLE TABLE, AND THE LEGS ARE NOT THE SAME LENGTH.** Cut on the road and packed to the shortest one:
/// the top sits level because a stone is under one foot, and the stone is on the model.
pub fn trestleTableMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x4A19);
    const hw = TABLE_W * 0.5;
    const hd: f32 = 0.42;
    // THE X-TRESTLES, and they splay: a trestle whose legs are parallel is a box.
    b.setMat(.wood);
    for ([_]f32{ -1.0, 1.0 }) |end| {
        const ex = end * hw * 0.66;
        const shrt = rng.range(0.86, 1.0);
        for ([_]f32{ -1.0, 1.0 }) |side| {
            b.addCylinder(
                v3(ex + rng.signed() * 0.03, 0, side * hd * 0.86),
                v3(ex - side * 0.05, TABLE_TOP - 0.06, -side * hd * 0.30),
                0.040,
                0.034,
                6,
                if (side > 0) POLE else POLE_LT,
            );
            _ = shrt;
        }
        b.addCylinder(v3(ex, TABLE_TOP * 0.42, -hd * 0.55), v3(ex, TABLE_TOP * 0.42, hd * 0.55), 0.028, 0.028, 6, POLE_LT);
    }
    // THE PACKING STONE under the short foot.
    b.setMat(.stone);
    b.addBlob(v3(-hw * 0.66 - 0.02, 0.035, -hd * 0.86), v3(0.085, 0.040, 0.075), 3, 8, art.STONE);
    // THE TOP: three planks, not one — different widths, a gap between them, and one bowed.
    b.setMat(.wood);
    var z: f32 = -hd;
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const w = hd * 2.0 / 3.0 * rng.range(0.82, 1.10);
        const bow = rng.range(-0.012, 0.012);
        b.addBox(
            v3(rng.signed() * 0.02, TABLE_TOP + bow, z + w * 0.5),
            v3(hw, rng.signed() * 0.008, 0),
            v3(0, 0.026, 0),
            v3(0, 0.006, w * 0.46),
            if (@mod(i, 2) == 0) PLANK else PLANK_LT,
        );
        z += w;
    }
    // THE WARES, in three groups, because a table with one thing on it is a plinth. Cloth bolts, jars, a heap.
    b.setMat(.cloth);
    for ([_]f32{ -0.62, -0.44 }) |bx| {
        b.addCapsule(
            v3(hw * bx, TABLE_TOP + 0.09, -0.10 + rng.signed() * 0.06),
            v3(hw * bx + rng.signed() * 0.05, TABLE_TOP + 0.09, 0.20),
            0.062,
            0.058,
            8,
            if (bx < -0.5) WEAVE else MADDER,
        );
    }
    b.setMat(.stone);
    var j: i32 = 0;
    while (j < 4) : (j += 1) {
        const fj = @as(f32, @floatFromInt(j));
        const rr = rng.range(0.048, 0.078);
        b.addBlob(v3(hw * (-0.02 + fj * 0.14), TABLE_TOP + rr * 0.85, rng.signed() * 0.20), v3(rr, rr * 1.15, rr), 3, 9, if (@mod(j, 2) == 0) CLAY else CLAY_LT);
    }
    b.setMat(.plant);
    var k: i32 = 0;
    while (k < 14) : (k += 1) {
        const rr = rng.range(0.018, 0.036);
        b.addBlob(
            v3(hw * (0.56 + rng.signed() * 0.18), TABLE_TOP + 0.03 + rng.range(0, 0.05), rng.signed() * 0.24),
            v3(rr, rr * 0.7, rr),
            2,
            7,
            if (rng.float() < 0.5) art.GRASS_GOLD else art.SEED,
        );
    }
    return b.toModel(shader);
}

pub const RACK_TOP: f32 = 2.35;
pub const RACK_W: f32 = 2.05;
/// **A RACK IS WHAT IS HANGING ON IT.** An A-frame of lashed poles with rugs and hides thrown over the crossbar,
/// each one a different length and none of them square — the frame is a coat-hanger and the cloth is the object.
pub fn goodsRackMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x4A1A);
    const hw = RACK_W * 0.5;
    // TWO A-FRAMES, leaning toward each other, with the bar across their crotches.
    var bar: [2]rl.Vector3 = undefined;
    for ([_]f32{ -1.0, 1.0 }, 0..) |end, ei| {
        const ex = end * hw;
        const apex = v3(ex - end * 0.10, RACK_TOP - 0.10, rng.signed() * 0.04);
        b.setMat(.wood);
        for ([_]f32{ -1.0, 1.0 }) |side| {
            b.addCylinder(v3(ex + rng.signed() * 0.05, 0, side * 0.46), apex, 0.050, 0.040, 7, if (side > 0) POLE else POLE_LT);
        }
        // THE LASHING at the crotch, which is the only join in the thing.
        b.setMat(.cloth);
        var t: i32 = 0;
        while (t < 3) : (t += 1) {
            const ft = @as(f32, @floatFromInt(t));
            b.addCylinder(
                v3(apex.x, apex.y - 0.02 - ft * 0.035, apex.z - 0.05),
                v3(apex.x, apex.y - 0.02 - ft * 0.035, apex.z + 0.05),
                0.030,
                0.030,
                6,
                ROPE,
            );
        }
        bar[ei] = apex;
    }
    b.setMat(.wood);
    b.addCylinder(v3(bar[0].x, bar[0].y - 0.06, bar[0].z), v3(bar[1].x, bar[1].y - 0.04, bar[1].z), 0.034, 0.034, 7, POLE);
    // THE HANGINGS. Four, each its own width, drop and tone, and each folded over the bar so it has two faces.
    const tones = [4][2]rl.Color{
        .{ WEAVE, WEAVE_DK },
        .{ MADDER, art.CLOTH_DK },
        .{ CANVAS, CANVAS_SUN },
        .{ SACK_LT, SACK },
    };
    b.setMat(.cloth);
    var i: usize = 0;
    var x: f32 = -hw * 0.86;
    while (i < 4) : (i += 1) {
        const w = rng.range(0.30, 0.46);
        const drop = rng.range(0.85, 1.55);
        const bx = x + w * 0.5;
        const by = mathx.lerpF(bar[0].y, bar[1].y, (bx + hw) / (hw * 2.0)) - 0.06;
        // FRONT and BACK faces, and the front is longer: cloth thrown over a bar never hangs even.
        for ([_]f32{ 1.0, -1.0 }) |face| {
            const d = drop * (if (face > 0) @as(f32, 1.0) else rng.range(0.62, 0.86));
            const zf = face * 0.048;
            const sway = rng.range(-0.06, 0.06);
            const q0 = v3(bx - w * 0.5, by, zf);
            const q1 = v3(bx - w * 0.5 + sway, by - d, zf * 1.6);
            const q2 = v3(bx + w * 0.5 + sway, by - d, zf * 1.6);
            const q3 = v3(bx + w * 0.5, by, zf);
            sheetQuad(&b, q0, q1, q2, q3, if (face > 0) tones[i][0] else tones[i][1]);
        }
        // The fold over the top, so the two faces are one piece of cloth and not two curtains.
        b.addCapsule(v3(bx - w * 0.5, by + 0.012, 0), v3(bx + w * 0.5, by + 0.012, 0), 0.050, 0.050, 6, tones[i][0]);
        x += w + rng.range(0.02, 0.10);
    }
    return b.toModel(shader);
}

pub const AWNING_TOP: f32 = 2.48;
/// **THE POLE SQUARE, AND THE COLLIDER IS THE SAME FOUR STICKS** (`props.INFO`) — written out there as bare
/// numbers they were the mesh's `hw`/`hd` transcribed, which is a doorway that walks away from its own poles.
pub const AWNING_HW: f32 = 1.55;
pub const AWNING_HD: f32 = 1.25;
/// **A SHEET ON FOUR STICKS, AND YOU WALK UNDER IT.** The hut without its walls: shade, which in a desert is the
/// thing actually being sold. Guyed off two of its poles, and the guys are pegged.
pub fn awningMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x4A1B);
    const hw = AWNING_HW;
    const hd = AWNING_HD;
    var top: [4]rl.Vector3 = undefined;
    const feet = [4]rl.Vector3{ v3(-hw, 0, hd), v3(hw, 0, hd), v3(hw, 0, -hd), v3(-hw, 0, -hd) };
    for (feet, 0..) |f, i| {
        // ONE CORNER IS DROPPED, so the sheet spills to that side and the whole thing has a fall.
        const h = (AWNING_TOP - 0.08) * (if (i == 3) @as(f32, 0.80) else rng.range(0.96, 1.02));
        top[i] = poleInto(&b, f, h, 0.052, rng.range(0.02, 0.07), rng.angle(), if (@mod(i, 2) == 0) POLE else POLE_LT);
    }
    canopyInto(&b, &rng, top, 0.30, CANVAS, CANVAS_LT);
    // THE GUYS, off the two tall corners, pegged out and TAUT — a slack guy is a rope lying on the ground.
    b.setMat(.cloth);
    for ([_]usize{ 0, 1 }) |ci| {
        const t = top[ci];
        const out = mathx.normV(v3(t.x, 0, t.z));
        const peg = v3(t.x + out.x * 0.95, 0.02, t.z + out.z * 0.95);
        b.addCapsule(t, peg, 0.014, 0.012, 5, ROPE);
        b.setMat(.wood);
        b.addCylinder(v3(peg.x, 0.16, peg.z), v3(peg.x + out.x * 0.06, -0.04, peg.z + out.z * 0.06), 0.020, 0.014, 5, POLE_LT);
        b.setMat(.cloth);
    }
    // A rug under it, because a patch of shade with nothing on it is not a stall.
    b.addBox(v3(rng.signed() * 0.15, 0.012, rng.signed() * 0.15), v3(0.72, 0, 0.04), v3(0, 0.012, 0), v3(-0.04, 0.004, 0.54), WEAVE);
    b.addBox(v3(rng.signed() * 0.15, 0.020, rng.signed() * 0.15), v3(0.58, 0, 0.03), v3(0, 0.010, 0), v3(-0.03, 0.003, 0.42), MADDER);
    return b.toModel(shader);
}

pub const RUGS_TOP: f32 = 0.68;
pub const RUGS_R: f32 = 0.85;
/// **ROLLED AND STOOD ON END, PLUS A PILE FLAT.** Two ways of stacking the same thing, because a market has both
/// and one alone reads as a delivery. Ankle-to-knee: walked round, not over.
pub fn rugPileMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x4A1C);
    b.setMat(.cloth);
    // THE FLAT PILE — five, each a hair smaller and each rotated, so the corners fan.
    var y: f32 = 0.02;
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / 4.0;
        const hx = mathx.lerpF(0.62, 0.46, t) * rng.range(0.94, 1.06);
        const hz = mathx.lerpF(0.44, 0.33, t) * rng.range(0.94, 1.06);
        const yaw = rng.range(-0.28, 0.28);
        const cy = mathx.cosf(yaw);
        const sy = mathx.sinf(yaw);
        const th = rng.range(0.028, 0.052);
        b.addBox(
            v3(rng.signed() * 0.04, y + th * 0.5, rng.signed() * 0.04),
            v3(cy * hx, rng.signed() * 0.006, sy * hx),
            v3(0, th * 0.5, 0),
            v3(-sy * hz, rng.signed() * 0.006, cy * hz),
            switch (@mod(i, 3)) {
                0 => WEAVE,
                1 => MADDER,
                else => SACK_LT,
            },
        );
        y += th;
    }
    // THE ROLLS, stood on end and LEANING on each other — three of them, no two the same height.
    const rolls = [3][3]f32{ .{ -0.52, 0.66, 0.10 }, .{ -0.36, 0.54, -0.14 }, .{ -0.62, 0.44, -0.30 } };
    for (rolls, 0..) |r, ri| {
        const at = rng.angle();
        const lean = rng.range(0.10, 0.22);
        const foot = v3(r[0], 0.02, r[2]);
        const tp = v3(foot.x + mathx.cosf(at) * r[1] * mathx.sinf(lean), r[1], foot.z + mathx.sinf(at) * r[1] * mathx.sinf(lean));
        const rr = rng.range(0.070, 0.098);
        b.addCylinder(foot, tp, rr, rr * 0.94, 9, switch (@mod(ri, 3)) {
            0 => WEAVE,
            1 => MADDER,
            else => CANVAS_SUN,
        });
        // The END of a roll is a spiral, and it is what says rolled rather than a log.
        b.addBlob(tp, v3(rr * 0.96, rr * 0.22, rr * 0.96), 3, 9, WEAVE_DK);
        b.addBlob(v3(tp.x, tp.y + 0.012, tp.z), v3(rr * 0.44, rr * 0.20, rr * 0.44), 3, 7, MADDER);
        // The tie round its middle.
        const mid = mathx.lerpV(foot, tp, 0.45);
        b.addCylinder(v3(mid.x, mid.y, mid.z), v3(mid.x, mid.y + 0.030, mid.z), rr * 1.10, rr * 1.10, 9, ROPE);
    }
    return b.toModel(shader);
}

pub const SCALE_TOP: f32 = 2.05;
/// **THE WEIGHING POST, AND ITS BEAM IS OFF LEVEL.** A public scale on a post: what settles a caravan's business.
/// A level beam is a diagram, so one pan is loaded and hangs low, and the weights that did it are on the ground.
pub fn scalePostMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x4A1D);
    b.setMat(.stone);
    b.addBlob(v3(0, 0.06, 0), v3(0.30, 0.070, 0.27), 3, 10, art.STONE_DK);
    const top = poleInto(&b, v3(0, 0.06, 0), SCALE_TOP - 0.30, 0.070, rng.range(0.015, 0.045), rng.angle(), POLE);
    // THE ARM out of the post, and the KNEE brace under it — an unbraced cantilever reads as floating.
    b.setMat(.wood);
    const armEnd = v3(top.x, top.y - 0.06, top.z + 0.60);
    b.addCylinder(v3(top.x, top.y - 0.04, top.z), armEnd, 0.048, 0.038, 6, POLE);
    b.addCylinder(v3(top.x, top.y - 0.46, top.z + 0.04), v3(armEnd.x, armEnd.y - 0.04, armEnd.z - 0.20), 0.030, 0.026, 5, POLE_LT);
    b.setMat(.gilt);
    // THE BEAM, tilted, hung off the arm's end.
    const tilt = mathx.radians(rng.range(7.0, 12.0));
    const half: f32 = 0.42;
    const dy = half * mathx.sinf(tilt);
    const bl = v3(armEnd.x - half, armEnd.y - 0.22 - dy, armEnd.z);
    const br = v3(armEnd.x + half, armEnd.y - 0.22 + dy, armEnd.z);
    b.addCylinder(v3(armEnd.x, armEnd.y - 0.06, armEnd.z), v3(armEnd.x, armEnd.y - 0.22, armEnd.z), 0.008, 0.008, 5, BRASS);
    b.addCylinder(bl, br, 0.014, 0.014, 6, BRASS);
    b.addBlob(v3(armEnd.x, armEnd.y - 0.22, armEnd.z), v3(0.028, 0.028, 0.024), 3, 8, BRASS);
    for ([_]rl.Vector3{ bl, br }) |e| {
        const loaded = e.y < armEnd.y - 0.22;
        const drop: f32 = if (loaded) 0.34 else 0.46;
        var i: i32 = 0;
        while (i < 3) : (i += 1) {
            const a = std.math.tau * @as(f32, @floatFromInt(i)) / 3.0;
            b.addCapsule(e, v3(e.x + mathx.cosf(a) * 0.10, e.y - drop, e.z + mathx.sinf(a) * 0.10), 0.005, 0.005, 4, BRASS);
        }
        b.addBlob(v3(e.x, e.y - drop - 0.02, e.z), v3(0.115, 0.024, 0.115), 3, 11, BRASS);
        if (loaded) {
            b.setMat(.cloth);
            baleInto(&b, &rng, v3(e.x, e.y - drop + 0.08, e.z), v3(0.10, 0.075, 0.09), rng.angle(), SACK);
            b.setMat(.gilt);
        }
    }
    // THE WEIGHTS on the ground, a graded set, each a different size and one on its side.
    b.setMat(.steel);
    var w: i32 = 0;
    while (w < 4) : (w += 1) {
        const fw = @as(f32, @floatFromInt(w));
        const rr = 0.038 + fw * 0.017;
        const a = -0.9 + fw * 0.5;
        const px = mathx.cosf(a) * 0.44;
        const pz = mathx.sinf(a) * 0.34 - 0.34;
        if (w == 2) {
            b.addCylinder(v3(px - rr, rr, pz), v3(px + rr, rr * 0.96, pz), rr * 0.86, rr * 0.86, 8, IRON);
        } else {
            b.addCylinder(v3(px, 0.004, pz), v3(px, rr * 1.5, pz), rr, rr * 0.82, 8, IRON);
            b.addBlob(v3(px, rr * 1.5, pz), v3(rr * 0.30, rr * 0.34, rr * 0.30), 3, 6, art.STEEL);
        }
    }
    return b.toModel(shader);
}

pub const JARS_TOP: f32 = 1.08;
pub const JARS_R: f32 = 0.88;
/// **WATER, WHICH IS WHAT A DESERT ACTUALLY TRADES.** Five amphorae in a rope cradle, no two the same height,
/// one on its side and empty. **A JAR HAS A NECK AND A SHOULDER**: a plain ovoid is an egg.
pub fn waterJarsMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x4A1E);
    const HS = [5][3]f32{ .{ -0.34, 0.0, 1.00 }, .{ 0.10, -0.26, 0.82 }, .{ 0.36, 0.16, 0.92 }, .{ -0.06, 0.28, 0.70 }, .{ 0.02, 0.02, 0.86 } };
    for (HS, 0..) |j, ji| {
        if (ji == 3) continue;
        const bx = j[0];
        const bz = j[1];
        const hh = (JARS_TOP - 0.16) * j[2];
        const rr = hh * 0.30;
        b.setMat(.stone);
        // BODY, SHOULDER, NECK, LIP — four primitives, and the shoulder is what makes it a jar.
        // **THE SHOULDER HAS TO PULL IN HARD OR IT IS A BARREL.** At 0.72 of the belly the taper was invisible and
        // five of these read as casks; 0.46 leaves a real neck standing above a real shoulder.
        b.addBlob(v3(bx, hh * 0.36, bz), v3(rr, hh * 0.38, rr), 5, 11, if (@mod(ji, 2) == 0) CLAY else CLAY_LT);
        b.addBlob(v3(bx, hh * 0.62, bz), v3(rr * 0.46, hh * 0.16, rr * 0.46), 4, 10, CLAY_LT);
        b.addCylinder(v3(bx, hh * 0.66, bz), v3(bx + rng.signed() * 0.014, hh, bz), rr * 0.26, rr * 0.22, 9, CLAY);
        b.addCylinder(v3(bx, hh * 0.96, bz), v3(bx, hh * 1.04, bz), rr * 0.34, rr * 0.30, 9, CLAY_LT);
        // A handle on some of them, and never on both sides.
        if (rng.float() < 0.6) {
            const sd: f32 = if (rng.float() < 0.5) 1.0 else -1.0;
            b.addCapsule(
                v3(bx + sd * rr * 0.24, hh * 0.86, bz),
                v3(bx + sd * rr * 0.66, hh * 0.58, bz),
                rr * 0.11,
                rr * 0.10,
                5,
                CLAY,
            );
        }
        // THE CRADLE: rope round the belly, which is how these travel.
        b.setMat(.cloth);
        b.addCylinder(v3(bx, hh * 0.42, bz), v3(bx, hh * 0.42 + 0.034, bz), rr * 1.06, rr * 1.06, 10, ROPE_LT);
        b.addCapsule(v3(bx - rr, hh * 0.42, bz), v3(bx - rr * 1.5, hh * 0.60, bz + rng.signed() * 0.06), 0.018, 0.014, 5, ROPE_LT);
    }
    // THE ONE ON ITS SIDE, empty, mouth toward you — the tell that this is a store and not a still life.
    b.setMat(.stone);
    const oy: f32 = 0.20;
    b.addBlob(v3(0.44, oy, 0.36), v3(0.24, oy, 0.20), 5, 11, CLAY);
    b.addCylinder(v3(0.62, oy, 0.42), v3(0.76, oy - 0.02, 0.46), 0.075, 0.068, 9, CLAY_LT);
    b.addBlob(v3(0.78, oy - 0.02, 0.47), v3(0.030, 0.070, 0.070), 3, 9, art.PAVE_DK);
    // …and the shards of the one that did not make it.
    var s: i32 = 0;
    while (s < 6) : (s += 1) {
        const a = rng.angle();
        const d = rng.range(0.10, 0.46);
        const rr = rng.range(0.030, 0.062);
        b.addBox(
            v3(-0.62 + mathx.cosf(a) * d, rr * 0.28, 0.44 + mathx.sinf(a) * d * 0.8),
            v3(rr, rng.signed() * 0.01, 0),
            v3(0, rr * 0.24, 0),
            v3(0, rng.signed() * 0.01, rr * rng.range(0.5, 1.0)),
            if (rng.float() < 0.4) CLAY_LT else CLAY,
        );
    }
    return b.toModel(shader);
}

pub const HITCH_TOP: f32 = 1.42;
pub const HITCH_R: f32 = 1.55;
/// **WHERE THE ANIMALS WENT.** Two posts and a rail, worn shiny where the ropes pull, with the ropes still on it
/// and nothing on the end of them. The ground is churned: that is the whole story of the object.
pub fn hitchRailMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x4A1F);
    const hw: f32 = 1.30;
    var tops: [2]rl.Vector3 = undefined;
    for ([_]f32{ -1.0, 1.0 }, 0..) |side, si| {
        tops[si] = poleInto(&b, v3(side * hw, 0, rng.signed() * 0.05), HITCH_TOP - 0.10, 0.078, rng.range(0.02, 0.06), rng.angle(), POLE);
        // The heel stone each post is packed with.
        b.setMat(.stone);
        b.addBlob(v3(side * hw + rng.signed() * 0.10, 0.05, rng.signed() * 0.14), v3(0.13, 0.055, 0.11), 3, 8, art.STONE_DK);
    }
    b.setMat(.wood);
    b.addCylinder(v3(tops[0].x, tops[0].y - 0.14, tops[0].z), v3(tops[1].x, tops[1].y - 0.10, tops[1].z), 0.054, 0.054, 7, POLE_LT);
    // THE WEAR: three bright bands where rope has been round it for years, sunk almost flush.
    for ([_]f32{ 0.26, 0.52, 0.79 }) |t| {
        const p = mathx.lerpV(v3(tops[0].x, tops[0].y - 0.14, tops[0].z), v3(tops[1].x, tops[1].y - 0.10, tops[1].z), t);
        b.addCylinder(v3(p.x - 0.05, p.y, p.z), v3(p.x + 0.05, p.y, p.z), 0.056, 0.056, 7, art.BARK_LIVE);
    }
    // TWO ROPES still tied, hanging with nothing on the end.
    b.setMat(.cloth);
    for ([_]f32{ -0.42, 0.30 }) |t| {
        const p = mathx.lerpV(v3(tops[0].x, tops[0].y - 0.14, tops[0].z), v3(tops[1].x, tops[1].y - 0.10, tops[1].z), t * 0.5 + 0.5);
        b.addCylinder(v3(p.x - 0.04, p.y, p.z), v3(p.x + 0.04, p.y, p.z), 0.062, 0.062, 7, ROPE);
        const mid = v3(p.x + rng.signed() * 0.10, p.y - 0.42, p.z + rng.range(0.10, 0.28));
        b.addCapsule(v3(p.x, p.y - 0.05, p.z), mid, 0.017, 0.015, 5, ROPE);
        b.addCapsule(mid, v3(mid.x + rng.signed() * 0.16, 0.03, mid.z + rng.range(0.05, 0.30)), 0.015, 0.013, 5, ROPE_LT);
    }
    // THE CHURNED GROUND, and the dung. It is a hitching rail.
    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.2, 1.15);
        const rr = rng.range(0.10, 0.22);
        b.addBlob(v3(mathx.cosf(a) * d, 0.014, mathx.sinf(a) * d * 0.7), v3(rr, 0.026, rr * 0.85), 3, 8, art.SOIL);
    }
    b.setMat(.plant);
    var g: i32 = 0;
    while (g < 4) : (g += 1) {
        const a = rng.angle();
        const d = rng.range(0.30, 0.90);
        const rr = rng.range(0.036, 0.062);
        b.addBlob(v3(mathx.cosf(a) * d, rr * 0.55, mathx.sinf(a) * d * 0.7), v3(rr, rr * 0.60, rr * 0.9), 3, 7, art.BARK_OLD);
    }
    return b.toModel(shader);
}

test "the awning is the PALEST thing here and the freight the darkest — a booth reads from across a field" {
    // 0..1, off the shader's own chain (`gfx.screenOfColor`, pinned to the GLSL) rather than a second copy of it.
    const lum = struct {
        fn of(c: rl.Color) f32 {
            return gfx.screenOfColor(c) / 255.0;
        }
    }.of;
    const canvas = lum(CANVAS_LT);
    const bale = lum(BALE);
    std.debug.print("\n  market: canvas {d:.0}/255 lit, bale {d:.0}, drift {d:.0}\n", .{
        canvas * 255.0, bale * 255.0, lum(art.DRIFT) * 255.0,
    });
    try std.testing.expect(canvas > lum(art.DRIFT));
    try std.testing.expect(bale < lum(art.DRIFT));
    // …and the SPREAD is what the wanderer's palette was missing: at least half a stop between the two ends.
    try std.testing.expect(canvas - bale > 0.25);
}

test "every upright LEANS — nothing in a hand-pitched camp is plumb" {
    var rng = mathx.Rng.init(0x4A17);
    var b = Builder.init();
    defer b.deinit();
    var plumb: usize = 0;
    var i: usize = 0;
    while (i < 12) : (i += 1) {
        const from = v3(0, 0, 0);
        const top = poleInto(&b, from, 2.0, 0.05, rng.range(0.02, 0.07), rng.angle(), POLE);
        if (mathx.lenXZ(mathx.subV(top, from)) < 0.01) plumb += 1;
    }
    try std.testing.expectEqual(@as(usize, 0), plumb);
}
