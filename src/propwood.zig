const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const art = @import("propart.zig");

const v3 = mathx.v3;
const Builder = gfx.Builder;
const BARK = art.BARK;
const BARK_DK = art.BARK_DK;
const BARK_LIVE = art.BARK_LIVE;
const BARK_OLD = art.BARK_OLD;
const BIRCH_BARK = art.BIRCH_BARK;
const BIRCH_SCAR = art.BIRCH_SCAR;
const CAP_BROWN = art.CAP_BROWN;
const CAP_PALE = art.CAP_PALE;
const IRON = art.IRON;
const LEAF = art.LEAF;
const LEAF_DAMP = art.LEAF_DAMP;
const LEAF_DK = art.LEAF_DK;
const LEAF_GOLD = art.LEAF_GOLD;
const LEAF_LT = art.LEAF_LT;
const LEAF_PALE = art.LEAF_PALE;
const MOSS_DK = art.MOSS_DK;
const NEEDLE = art.NEEDLE;
const NEEDLE_LT = art.NEEDLE_LT;
const NEEDLE_DK = art.NEEDLE_DK;
const SCRUB_DK = art.SCRUB_DK;
const STONE_MOSS = art.STONE_MOSS;
const TIMBER = art.TIMBER;
const crackInto = art.crackInto;
const lichenInto = art.lichenInto;
const tuftInto = art.tuftInto;

/// Nothing dead is straight and nothing ends in a point: one straight capsule to a needle tip is a SPEAR, and a
/// rosette of them is a hub of spokes. So leave the bole on the bole's own AXIS, rise to an elbow, then droop
/// off the line to a blunt snap of pale heartwood. Twigs root on that OUTER half and carry on outward — struck
/// across the limb instead, a twig crosses its parent and reads as a needle lying near a branch.
pub fn deadLimbInto(b: *Builder, rng: *mathx.Rng, root: rl.Vector3, a: f32, reach: f32, rise: f32, r0: f32, twigs: i32) void {
    const elbow = v3(root.x + mathx.cosf(a) * reach * 0.58, root.y + rise, root.z + mathx.sinf(a) * reach * 0.58);
    const r1 = r0 * 0.52;
    b.addCapsule(root, elbow, r0, r1, 5, BARK_DK);
    const oa = a + rng.signed() * 0.55;
    const drop = rise * rng.range(-0.7, 0.05); // its own weight has taken it back down
    const tip = v3(elbow.x + mathx.cosf(oa) * reach * 0.42, elbow.y + drop, elbow.z + mathx.sinf(oa) * reach * 0.42);
    const r2 = r1 * 0.5;
    b.addCapsule(elbow, tip, r1, r2, 5, BARK_DK);
    b.addBlob(tip, v3(r2 * 1.7, r2 * 1.3, r2 * 1.7), 3, 5, TIMBER); // where it broke off
    var t: i32 = 0;
    while (t < twigs) : (t += 1) {
        const u = rng.range(0.05, 0.6);
        const from = mathx.lerpV(elbow, tip, u);
        // Sized off the PARENT's radius where it leaves it, or the fork bulges out of the branch growing it.
        const tr = mathx.lerpF(r1, r2, u) * 0.75;
        const ta = oa + rng.signed() * 0.85;
        const tl = reach * rng.range(0.24, 0.44);
        // Its droop is capped against its own REACH, or a twig off a steeply-drooping limb hangs plumb
        // and reads as something suspended from the tree rather than a part of it.
        const dy = mathx.clampF(rise * 0.12 + drop * rng.range(0.2, 0.7), -tl * 0.6, tl * 0.6);
        b.addCapsule(from, v3(from.x + mathx.cosf(ta) * tl, from.y + dy, from.z + mathx.sinf(ta) * tl), tr, tr * 0.4, 5, BARK_DK);
    }
}

pub fn treeMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4806);
    b.setMat(.bark);
    const bend = v3(rng.range(0.08, 0.24), 0, rng.signed() * 0.14);
    const j1 = v3(bend.x, 1.70, bend.z);
    const j2 = v3(bend.x * 2.8, 3.05, bend.z * 2.4);
    const onBole = struct {
        fn go(bd: rl.Vector3, y: f32, a: f32, sink: f32) rl.Vector3 {
            const rr = (0.26 - 0.056 * y) * (1.0 - sink);
            return v3(bd.x * (y / 1.7) + mathx.cosf(a) * rr, y, bd.z * (y / 1.7) + mathx.sinf(a) * rr);
        }
    }.go;
    const j3 = v3(j2.x + rng.signed() * 0.3, 4.05, j2.z + rng.signed() * 0.25);
    b.addCapsule(v3(0, 0, 0), j1, 0.26, 0.165, 8, BARK_OLD);
    b.addCapsule(j1, j2, 0.165, 0.095, 7, BARK_OLD);
    b.addCapsule(j2, j3, 0.095, 0.035, 6, BARK_DK); // the snapped leader — SNAPPED, so blunt…
    b.addBlob(j3, v3(0.045, 0.030, 0.045), 3, 5, TIMBER); // …and showing its heartwood
    // Peeling bark: strips SUNK so only an edge breaks the surface, and the loose one curls off at its TOP
    // only. Stood clear along its whole length (0.16 off a bole of radius 0.2) a strip is a dark floating tube.
    var s: i32 = 0;
    while (s < 7) : (s += 1) {
        const a = rng.angle();
        const y0 = rng.range(0.05, 1.1);
        const y1 = y0 + rng.range(0.5, 1.5);
        const rr = rng.range(0.030, 0.055);
        const curl: f32 = if (rng.float() < 0.3) rr * rng.range(0.9, 1.8) else 0.0;
        b.addCapsule(
            onBole(bend, y0, a, rr * 0.6 / (0.26 - 0.056 * y0)),
            onBole(bend, y1, a + rng.signed() * 0.2, (rr * 0.6 - curl) / (0.26 - 0.056 * y1)),
            rr,
            rng.range(0.018, 0.040),
            5,
            if (rng.float() < 0.45) BARK_DK else if (rng.float() < 0.7) TIMBER else BARK_OLD,
        );
    }
    crackInto(&b, v3(mathx.cosf(1.9) * 0.22, 0.30, mathx.sinf(1.9) * 0.22), v3(0.06, 0.99, 0.02), v3(-mathx.sinf(1.9), 0, mathx.cosf(1.9)), rng.range(0.9, 1.5), 0.026, 0.05);
    b.setMat(.bark);
    b.addBlob(v3(bend.x * 0.7 + 0.20, 1.25, bend.z * 0.7 - 0.06), v3(0.09, 0.14, 0.09), 3, 6, IRON); // the rot hollow, dark
    // BRANCHES: six, each rooted at its OWN height on the real bole (j1→j2 low, j2→j3 above, alternating
    // so the low ones are not all on one side) and thinner than the bole it leaves — a limb fatter than
    // the stem above it is a thing no tree does. Six off two exact joints was two rosettes of spokes.
    var br: i32 = 0;
    while (br < 6) : (br += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(br)) / 6.0 + rng.signed() * 0.6;
        const low = @rem(br, 2) == 0;
        const u = rng.range(0.05, 0.85);
        const root = mathx.lerpV(if (low) j1 else j2, if (low) j2 else j3, u);
        const boleR = if (low) mathx.lerpF(0.165, 0.095, u) else mathx.lerpF(0.095, 0.035, u);
        deadLimbInto(&b, &rng, root, a, rng.range(0.9, 1.7) * (if (low) @as(f32, 1.0) else 0.72), rng.range(0.45, 1.0), boleR * rng.range(0.5, 0.78), 1 + rng.intn(2));
    }
    var r: i32 = 0;
    while (r < 5) : (r += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(r)) / 5.0 + rng.signed() * 0.35;
        const d = rng.range(0.42, 0.72);
        const heave: f32 = if (r == 2) rng.range(0.14, 0.26) else 0.0;
        b.addCapsule(v3(0, 0.26, 0), v3(mathx.cosf(a) * d, 0.02 + heave, mathx.sinf(a) * d), rng.range(0.09, 0.13), rng.range(0.025, 0.05), 5, BARK_OLD);
    }
    b.setMat(.plant);
    const fa = rng.angle();
    const fy1 = rng.range(0.7, 1.5);
    const fy2 = rng.range(0.4, 1.0);
    b.addBlob(onBole(bend, fy1, fa, 0.35), v3(0.17, 0.035, 0.14), 3, 6, CAP_BROWN);
    b.addBlob(onBole(bend, fy2, fa + 0.5, 0.30), v3(0.11, 0.028, 0.10), 3, 5, CAP_PALE);
    lichenInto(&b, &rng, onBole(bend, rng.range(0.5, 1.6), fa + 3.0, 0.25), v3(0.10, 0.34, 0.10), 3);
    tuftInto(&b, &rng, rng.signed() * 0.8, rng.signed() * 0.8, 0.8);
    tuftInto(&b, &rng, rng.signed() * 1.0, rng.signed() * 1.0, 0.62);
    return b.toModel(shader);
}


pub fn stumpMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(313);
    b.setMat(.bark);
    b.addCapsule(v3(0, 0, 0), v3(rng.signed() * 0.08, 1.05, rng.signed() * 0.08), 0.46, 0.40, 8, BARK_OLD);
    var rb: i32 = 0;
    while (rb < 7) : (rb += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(rb)) / 7.0 + rng.signed() * 0.25;
        // Seated so the rod's EDGE breaks the surface (~5% of the radius proud).
        const r0 = rng.range(0.43, 0.465);
        b.addCapsule(
            v3(mathx.cosf(a) * r0, rng.range(0.0, 0.2), mathx.sinf(a) * r0),
            v3(mathx.cosf(a + rng.signed() * 0.2) * r0 * 0.90, rng.range(0.72, 1.0), mathx.sinf(a + rng.signed() * 0.2) * r0 * 0.90),
            rng.range(0.035, 0.055),
            rng.range(0.025, 0.045),
            6,
            if (rng.float() < 0.5) BARK_DK else BARK_OLD,
        );
    }
    b.addBlob(v3(0.02, 1.06, -0.03), v3(0.36, 0.055, 0.34), 4, 8, TIMBER);
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.12, 0.32);
        b.addBox(
            v3(mathx.cosf(a) * d, 1.12 + rng.range(0.0, 0.13), mathx.sinf(a) * d),
            v3(rng.range(0.05, 0.12), 0, 0),
            v3(rng.signed() * 0.05, rng.range(0.06, 0.20), rng.signed() * 0.05),
            v3(0, 0, rng.range(0.05, 0.11)),
            BARK_DK,
        );
    }
    var r: i32 = 0;
    while (r < 4) : (r += 1) {
        const a = rng.angle();
        b.addCapsule(v3(0, 0.30, 0), v3(mathx.cosf(a) * 0.72, 0.02, mathx.sinf(a) * 0.72), 0.15, 0.05, 5, BARK_OLD);
    }
    b.setMat(.plant);
    b.addBlob(v3(-0.12, 1.07, 0.10), v3(0.26, 0.08, 0.24), 3, 6, STONE_MOSS);
    return b.toModel(shader);
}

pub fn logMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(818);
    b.setMat(.bark);
    // BARK_OLD + ridges run ALONG the barrel — same plastic-loaf correction as the stump.
    b.addCapsule(v3(-1.85, 0.36, rng.signed() * 0.1), v3(1.9, 0.30, rng.signed() * 0.12), 0.36, 0.25, 8, BARK_OLD);
    var rb: i32 = 0;
    while (rb < 6) : (rb += 1) {
        const phi = std.math.tau * @as(f32, @floatFromInt(rb)) / 6.0 + rng.signed() * 0.3;
        const sink = rng.range(0.78, 0.90);
        b.addCapsule(
            v3(rng.range(-1.75, -1.1), 0.36 + mathx.sinf(phi) * 0.33 * sink, mathx.cosf(phi) * 0.33 * sink),
            v3(rng.range(1.0, 1.75), 0.31 + mathx.sinf(phi + rng.signed() * 0.3) * 0.26 * sink, mathx.cosf(phi + rng.signed() * 0.3) * 0.26 * sink),
            rng.range(0.028, 0.05),
            rng.range(0.02, 0.04),
            6,
            if (rng.float() < 0.5) BARK_DK else BARK_OLD,
        );
    }
    b.addBlob(v3(1.94, 0.30, 0.02), v3(0.07, 0.20, 0.17), 4, 7, TIMBER);
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const x = rng.range(-1.5, 1.6);
        const a = rng.angle();
        b.addCapsule(v3(x, 0.34, 0), v3(x + rng.signed() * 0.35, 0.34 + @abs(mathx.sinf(a)) * 0.45, mathx.cosf(a) * 0.62), 0.075, 0.02, 5, BARK_DK);
    }
    var r: i32 = 0;
    while (r < 5) : (r += 1) {
        const a = rng.angle();
        b.addCapsule(v3(-1.85, 0.34, 0), v3(-2.05 + rng.signed() * 0.1, 0.34 + mathx.sinf(a) * 0.55, mathx.cosf(a) * 0.55), 0.10, 0.03, 5, BARK_DK);
    }
    b.setMat(.plant);
    b.addBlob(v3(rng.range(-1.0, 0.6), 0.62, 0), v3(0.55, 0.10, 0.24), 3, 6, STONE_MOSS);
    b.addBlob(v3(rng.range(0.2, 1.4), 0.60, 0.05), v3(0.34, 0.09, 0.22), 3, 6, SCRUB_DK);
    tuftInto(&b, &rng, rng.range(-1.2, 1.2), rng.signed() * 0.55, 0.7);
    return b.toModel(shader);
}


pub const TreeSpec = struct {
    seed: u64,
    trunk: f32, // height of the fork — the shorter this is, the more the canopy sits ON the tree
    spread: f32, // bough reach multiplier
    lift: f32, // how much the boughs climb as they reach out (low = a spreading oak, high = a poplar)
    gold: f32, // fraction of canopy masses that catch the sun
};

pub fn bigTree1(shader: rl.Shader) rl.Model {
    return bigTreeMesh(shader, .{ .seed = 7001, .trunk = 4.5, .spread = 1.0, .lift = 0.55, .gold = 0.30 });
}
pub fn bigTree2(shader: rl.Shader) rl.Model {
    return bigTreeMesh(shader, .{ .seed = 7011, .trunk = 3.4, .spread = 1.22, .lift = 0.30, .gold = 0.42 }); // squat + broad
}
pub fn bigTree3(shader: rl.Shader) rl.Model {
    return bigTreeMesh(shader, .{ .seed = 7023, .trunk = 5.6, .spread = 0.82, .lift = 0.85, .gold = 0.22 }); // tall + narrow
}

pub fn canopyInto(b: *Builder, rng: *mathx.Rng, cx: f32, cy: f32, cz: f32, rx: f32, ry: f32, gold: f32, n: i32) void {
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const a = rng.angle();
        const t = rng.range(0.30, 0.88);
        const yt = rng.signed(); // -1 = underside, +1 = crown
        const rr = rx * t;
        const px = cx + mathx.cosf(a) * rr;
        const pz = cz + mathx.sinf(a) * rr;
        const py = cy + yt * ry * (1.0 - 0.45 * t);
        const size = rx * rng.range(0.34, 0.56) * (1.0 - 0.20 * t);
        const col = if (yt > 0.35 and rng.float() < gold) LEAF_GOLD else if (yt > 0.0) (if (rng.float() < 0.4) LEAF_LT else LEAF) else if (rng.float() < 0.55) LEAF_DK else LEAF;
        const big = size > 1.0;
        b.addBlob(v3(px, py, pz), v3(size, size * rng.range(0.62, 0.92), size * rng.range(0.82, 1.18)), if (big) 6 else 5, if (big) 9 else 7, col);
    }
    var f: i32 = 0;
    const nf = @divTrunc(n * 4, 5);
    while (f < nf) : (f += 1) {
        const a = rng.angle();
        const yt = rng.signed();
        const t = rng.range(0.86, 1.04);
        const flat = 1.0 - 0.55 * @abs(yt); // shell radius pinches toward the poles
        const rr = rx * t * flat;
        const px = cx + mathx.cosf(a) * rr;
        const pz = cz + mathx.sinf(a) * rr;
        const py = cy + yt * ry * rng.range(0.85, 1.05);
        const size = rx * rng.range(0.14, 0.26);
        const col = if (yt > 0.30 and rng.float() < gold * 1.3) LEAF_GOLD else if (yt > 0.0) (if (rng.float() < 0.5) LEAF_LT else LEAF) else if (rng.float() < 0.7) LEAF_DK else LEAF_DAMP;
        b.addBlob(
            v3(px, py, pz),
            v3(size * (1.0 - 0.35 * @abs(mathx.cosf(a))), size * rng.range(0.55, 0.8), size * (1.0 - 0.35 * @abs(mathx.sinf(a)))),
            4,
            6,
            col,
        );
    }
}

pub fn bigTreeMesh(shader: rl.Shader, spec: TreeSpec) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(spec.seed);
    b.setMat(.bark);
    const leanX = rng.signed() * 0.55;
    const leanZ = rng.signed() * 0.45;
    var r: i32 = 0;
    while (r < 7) : (r += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(r)) / 7.0 + rng.signed() * 0.3;
        const d = rng.range(1.1, 1.9);
        b.addCapsule(v3(0, 0.85, 0), v3(mathx.cosf(a) * d, 0.04, mathx.sinf(a) * d), rng.range(0.20, 0.34), rng.range(0.06, 0.12), 6, BARK);
    }
    const t1 = v3(leanX * 0.3, spec.trunk * 0.42, leanZ * 0.3);
    const t2 = v3(leanX * 0.7, spec.trunk * 0.78, leanZ * 0.7);
    const fork = v3(leanX, spec.trunk, leanZ);
    b.addCapsule(v3(0, 0.0, 0), t1, 0.95, 0.80, 9, BARK_OLD);
    b.addCapsule(t1, t2, 0.80, 0.62, 9, BARK_OLD);
    b.addCapsule(t2, fork, 0.62, 0.48, 8, BARK);
    var rb: i32 = 0;
    while (rb < 9) : (rb += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(rb)) / 9.0 + rng.signed() * 0.2;
        const r0 = rng.range(0.70, 0.83);
        const y0 = rng.range(0.0, 0.6);
        const y1 = rng.range(0.65, 1.0) * spec.trunk;
        b.addCapsule(
            v3(mathx.cosf(a) * r0, y0, mathx.sinf(a) * r0),
            v3(mathx.cosf(a + rng.signed() * 0.25) * r0 * 0.72, y1, mathx.sinf(a + rng.signed() * 0.25) * r0 * 0.72),
            rng.range(0.05, 0.10),
            rng.range(0.03, 0.065),
            6,
            if (rng.float() < 0.5) BARK_DK else BARK_OLD,
        );
    }
    const NB = 6;
    var tips: [NB]rl.Vector3 = undefined;
    var i: i32 = 0;
    while (i < NB) : (i += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, NB) + rng.signed() * 0.5;
        const out = rng.range(2.6, 4.4) * spec.spread;
        const up = out * spec.lift * rng.range(0.8, 1.25);
        const base = if (rng.float() < 0.45) t2 else fork;
        const mid = v3(base.x + mathx.cosf(a) * out * 0.45, base.y + up * 0.6, base.z + mathx.sinf(a) * out * 0.45);
        const tip = v3(base.x + mathx.cosf(a) * out, base.y + up, base.z + mathx.sinf(a) * out);
        b.addCapsule(base, mid, 0.34, 0.24, 7, BARK);
        b.addCapsule(mid, tip, 0.24, 0.11, 6, BARK_LIVE);
        var s: i32 = 0;
        while (s < 3) : (s += 1) {
            const sa = a + rng.signed() * 1.1;
            const sl = rng.range(0.7, 1.5);
            b.addCapsule(mid, v3(mid.x + mathx.cosf(sa) * sl, mid.y + rng.range(0.4, 1.1), mid.z + mathx.sinf(sa) * sl), 0.09, 0.03, 5, BARK_DK);
        }
        tips[@intCast(i)] = tip;
    }
    const da = rng.angle();
    b.addCapsule(t2, v3(t2.x + mathx.cosf(da) * 3.4 * spec.spread, t2.y + 0.9, t2.z + mathx.sinf(da) * 3.4 * spec.spread), 0.26, 0.05, 6, BARK_DK);

    b.setMat(.plant);
    const crownY = spec.trunk + 2.5 * spec.lift + 1.5;
    const crownR = 3.7 * spec.spread;
    i = 0;
    while (i < NB) : (i += 1) {
        const tip = tips[@intCast(i)];
        const mid = v3((tip.x + fork.x) * 0.5, (tip.y + fork.y) * 0.5 + 0.3, (tip.z + fork.z) * 0.5);
        canopyInto(&b, &rng, tip.x, tip.y + 0.5, tip.z, 1.7 * spec.spread, 1.1, spec.gold, 5);
        canopyInto(&b, &rng, mid.x, mid.y, mid.z, 1.35 * spec.spread, 0.95, spec.gold * 0.5, 3);
    }
    canopyInto(&b, &rng, leanX * 1.1, crownY, leanZ * 1.1, crownR, 1.9, spec.gold, 16);
    canopyInto(&b, &rng, leanX * 1.2, crownY + 1.5, leanZ * 1.2, crownR * 0.55, 0.9, 0.85, 5);
    var g: i32 = 0;
    while (g < 4) : (g += 1) {
        const a = rng.angle();
        const d = rng.range(1.2, 2.3);
        tuftInto(&b, &rng, mathx.cosf(a) * d, mathx.sinf(a) * d, rng.range(0.7, 1.0));
    }
    return b.toModel(shader);
}

pub fn willowMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(7002);
    b.setMat(.bark);
    var r: i32 = 0;
    while (r < 5) : (r += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(r)) / 5.0 + rng.signed() * 0.3;
        b.addCapsule(v3(0, 0.6, 0), v3(mathx.cosf(a) * 1.0, 0.03, mathx.sinf(a) * 1.0), 0.16, 0.06, 5, BARK);
    }
    const crown = v3(rng.signed() * 0.35, 3.4, rng.signed() * 0.3);
    b.addCapsule(v3(0, 0, 0), v3(crown.x * 0.5, 1.8, crown.z * 0.5), 0.70, 0.52, 8, BARK_OLD);
    b.addCapsule(v3(crown.x * 0.5, 1.8, crown.z * 0.5), crown, 0.52, 0.34, 7, BARK);
    const NB = 6;
    var i: i32 = 0;
    while (i < NB) : (i += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, NB) + rng.signed() * 0.35;
        const out = rng.range(2.0, 3.2);
        const top = v3(crown.x + mathx.cosf(a) * out * 0.55, crown.y + rng.range(0.9, 1.7), crown.z + mathx.sinf(a) * out * 0.55);
        const fallTo = v3(crown.x + mathx.cosf(a) * out, rng.range(0.9, 2.1), crown.z + mathx.sinf(a) * out);
        b.addCapsule(crown, top, 0.28, 0.18, 6, BARK);
        b.addCapsule(top, fallTo, 0.18, 0.07, 5, BARK_LIVE);
        b.setMat(.plant);
        var c: i32 = 0;
        while (c < 4) : (c += 1) {
            const t = (@as(f32, @floatFromInt(c)) + 0.5) / 4.0;
            const px = top.x + (fallTo.x - top.x) * t;
            const pz = top.z + (fallTo.z - top.z) * t;
            const py = top.y + (fallTo.y - top.y) * t;
            const rr = rng.range(0.55, 0.95);
            b.addBlob(v3(px, py - 0.25, pz), v3(rr * 0.7, rr * 1.25, rr * 0.7), 4, 6, if (rng.float() < 0.45) LEAF_PALE else LEAF);
        }
        var w: i32 = 0;
        while (w < 3) : (w += 1) {
            const wx = fallTo.x + rng.signed() * 0.5;
            const wz = fallTo.z + rng.signed() * 0.5;
            b.addCylinder(v3(wx, fallTo.y - 0.1, wz), v3(wx + rng.signed() * 0.2, rng.range(0.15, 0.7), wz + rng.signed() * 0.2), 0.035, 0.008, 4, LEAF_PALE);
        }
        b.setMat(.bark);
    }
    b.setMat(.plant);
    b.addBlob(crown, v3(1.9, 1.15, 1.85), 5, 8, LEAF_DK); // the dense heart of the crown
    var fh: i32 = 0;
    while (fh < 8) : (fh += 1) { // leaf clusters breaking the heart's shell
        const a = rng.angle();
        const rr = rng.range(0.16, 0.30);
        b.addBlob(v3(crown.x + mathx.cosf(a) * 1.75, crown.y + rng.signed() * 0.8, crown.z + mathx.sinf(a) * 1.70), v3(rr, rr * 0.7, rr), 4, 6, if (rng.float() < 0.4) LEAF_PALE else LEAF);
    }
    var g: i32 = 0;
    while (g < 3) : (g += 1) {
        const a = rng.angle();
        tuftInto(&b, &rng, mathx.cosf(a) * rng.range(0.9, 1.6), mathx.sinf(a) * rng.range(0.9, 1.6), 0.85);
    }
    return b.toModel(shader);
}

pub fn coniferMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(7101);
    b.setMat(.bark);
    const H: f32 = rng.range(9.5, 11.5);
    b.addCapsule(v3(0, 0, 0), v3(rng.signed() * 0.25, H * 0.55, rng.signed() * 0.2), 0.52, 0.32, 8, BARK_OLD);
    b.addCapsule(v3(rng.signed() * 0.25, H * 0.55, rng.signed() * 0.2), v3(rng.signed() * 0.3, H, rng.signed() * 0.25), 0.32, 0.05, 7, BARK_DK);
    var r: i32 = 0;
    while (r < 5) : (r += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(r)) / 5.0;
        b.addCapsule(v3(0, 0.5, 0), v3(mathx.cosf(a) * 0.85, 0.03, mathx.sinf(a) * 0.85), 0.13, 0.05, 5, BARK);
    }
    b.setMat(.plant);
    const whorls: i32 = 22;
    var w: i32 = 0;
    while (w < whorls) : (w += 1) {
        const t = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(whorls - 1));
        const y = H * (0.16 + 0.84 * t);
        const reach = (3.1 * (1.0 - t * 0.86)) * rng.range(0.86, 1.14);
        const nf: i32 = @max(3, @as(i32, @intFromFloat(6.0 * (1.0 - t * 0.5))));
        var f: i32 = 0;
        while (f < nf) : (f += 1) {
            const a = std.math.tau * @as(f32, @floatFromInt(f)) / @as(f32, @floatFromInt(nf)) + @as(f32, @floatFromInt(w)) * 0.7;
            const px = mathx.cosf(a) * reach;
            const pz = mathx.sinf(a) * reach;
            b.setMat(.bark);
            b.addCapsule(v3(0, y, 0), v3(px, y - reach * 0.22, pz), 0.055, 0.02, 4, BARK_DK);
            b.setMat(.plant);
            // The tone follows the LIGHT the whorl grows in: lit tips toward the crown, its own shade in
            // the low inner tiers — one flat needle green per whorl is what stacked the pagoda roofs.
            const shadeT = 1.0 - t;
            const inner: rl.Color = if (rng.float() < 0.55 * shadeT) NEEDLE_DK else NEEDLE;
            b.addBlob(v3(px * 0.55, y - reach * 0.08, pz * 0.55), v3(reach * 0.42, reach * 0.22, reach * 0.42), 3, 7, if (rng.float() < 0.20 + 0.30 * t) NEEDLE_LT else inner);
            b.addBlob(v3(px * 0.92, y - reach * 0.20, pz * 0.92), v3(reach * 0.32, reach * 0.17, reach * 0.32), 3, 7, inner);
        }
    }
    b.addBlob(v3(0, H * 0.99, 0), v3(0.34, 0.65, 0.34), 3, 6, NEEDLE); // the leader
    var g: i32 = 0;
    while (g < 3) : (g += 1) {
        const a = rng.angle();
        tuftInto(&b, &rng, mathx.cosf(a) * rng.range(0.9, 1.7), mathx.sinf(a) * rng.range(0.9, 1.7), 0.75);
    }
    return b.toModel(shader);
}

pub fn birchMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(7102);
    b.setMat(.wood); // birch bark is SMOOTH — the fissures belong to the oaks
    const H: f32 = rng.range(7.0, 8.6);
    const lean = rng.signed() * 0.5;
    const mid = v3(lean * 0.4, H * 0.5, rng.signed() * 0.3);
    const fork = v3(lean, H * 0.72, rng.signed() * 0.4);
    b.addCapsule(v3(0, 0, 0), mid, 0.30, 0.24, 8, BIRCH_BARK);
    b.addCapsule(mid, fork, 0.24, 0.17, 7, BIRCH_BARK);
    var s: i32 = 0;
    while (s < 12) : (s += 1) {
        const t = rng.range(0.05, 0.70);
        const a = rng.angle();
        const yy = H * t;
        const rr = 0.30 - 0.13 * t;
        b.addBlob(v3(lean * t * 0.55 + mathx.cosf(a) * rr * 0.85, yy, mathx.sinf(a) * rr * 0.85), v3(rr * rng.range(0.25, 0.6), rng.range(0.025, 0.06), rr * rng.range(0.25, 0.6)), 3, 5, BIRCH_SCAR);
    }
    b.setMat(.plant);
    const NB = 7;
    var i: i32 = 0;
    while (i < NB) : (i += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, NB) + rng.signed() * 0.5;
        const out = rng.range(1.4, 2.6);
        const up = rng.range(1.0, 2.2);
        const base = if (rng.float() < 0.4) mid else fork;
        const tip = v3(base.x + mathx.cosf(a) * out, base.y + up, base.z + mathx.sinf(a) * out);
        b.setMat(.bark);
        b.addCapsule(base, tip, 0.09, 0.025, 5, BIRCH_SCAR);
        b.setMat(.plant);
        var c: i32 = 0;
        while (c < 3) : (c += 1) {
            const rr = rng.range(0.55, 0.95);
            b.addBlob(
                v3(tip.x + rng.signed() * 0.7, tip.y + rng.range(-0.3, 0.7), tip.z + rng.signed() * 0.7),
                v3(rr, rr * rng.range(0.6, 0.9), rr * rng.range(0.85, 1.15)),
                4,
                6,
                if (rng.float() < 0.42) LEAF_GOLD else if (rng.float() < 0.6) LEAF_LT else LEAF,
            );
        }
    }
    canopyInto(&b, &rng, lean, H * 0.94, 0, 2.0, 1.1, 0.5, 8);
    var g: i32 = 0;
    while (g < 3) : (g += 1) tuftInto(&b, &rng, rng.signed() * 1.3, rng.signed() * 1.3, 0.8);
    return b.toModel(shader);
}

pub fn snagMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(7103);
    b.setMat(.wood); // stripped of its bark, by its own description
    const H: f32 = rng.range(6.0, 7.6);
    const lean = rng.signed() * 0.4;
    b.addCapsule(v3(0, 0, 0), v3(lean * 0.5, H * 0.6, lean * 0.3), 0.55, 0.36, 8, BARK_OLD);
    b.addCapsule(v3(lean * 0.5, H * 0.6, lean * 0.3), v3(lean, H, lean * 0.6), 0.36, 0.26, 7, BARK_DK);
    const onTrunk = struct {
        fn go(hh: f32, ln: f32, y: f32, a: f32, sink: f32) rl.Vector3 {
            const t = y / hh;
            const rr = (if (t < 0.6) 0.55 + (0.36 - 0.55) * (t / 0.6) else 0.36 + (0.26 - 0.36) * ((t - 0.6) / 0.4)) * (1.0 - sink);
            const ax = if (t < 0.6) ln * 0.5 * (t / 0.6) else ln * (0.5 + 0.5 * ((t - 0.6) / 0.4));
            return v3(ax + mathx.cosf(a) * rr, y, ax * 0.6 + mathx.sinf(a) * rr);
        }
    }.go;
    var rb: i32 = 0;
    while (rb < 8) : (rb += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(rb)) / 8.0 + rng.signed() * 0.22;
        const y0 = rng.range(0.1, 2.1);
        const y1 = @min(y0 + rng.range(1.6, 3.6), H - 0.25);
        b.addCapsule(
            onTrunk(H, lean, y0, a, 0.055),
            onTrunk(H, lean, y1, a + rng.signed() * 0.16, 0.055),
            rng.range(0.05, 0.085),
            rng.range(0.03, 0.06),
            5,
            if (rng.float() < 0.72) BARK_DK else TIMBER,
        );
    }
    b.addBlob(v3(lean, H - 0.02, lean * 0.6), v3(0.235, 0.055, 0.235), 3, 7, TIMBER);
    var s: i32 = 0;
    while (s < 5) : (s += 1) {
        const a = rng.angle();
        const d = rng.range(0.05, 0.22);
        b.addCapsule(
            v3(lean + mathx.cosf(a) * d, H, lean * 0.6 + mathx.sinf(a) * d),
            v3(lean + mathx.cosf(a) * d * 1.8, H + rng.range(0.25, 0.95), lean * 0.6 + mathx.sinf(a) * d * 1.8),
            rng.range(0.06, 0.14),
            0.015,
            4,
            if (rng.float() < 0.45) TIMBER else BARK_DK,
        );
    }
    // Broken limb stubs, and one long branch still on — all through `deadLimbInto`, so they elbow, droop
    // and snap blunt instead of standing out as horizontal spears, and all rooted on the trunk's OWN axis
    // (`onTrunk` at full sink), which is the point the lean already knows about and `lean * 0.4` guessed at.
    var l: i32 = 0;
    while (l < 4) : (l += 1) {
        const y = rng.range(H * 0.35, H * 0.9);
        deadLimbInto(&b, &rng, onTrunk(H, lean, y, 0, 1.0), rng.angle(), rng.range(0.7, 1.3), rng.range(0.1, 0.4), 0.15, rng.intn(2));
    }
    deadLimbInto(&b, &rng, onTrunk(H, lean, H * 0.7, 0, 1.0), rng.angle(), 2.6, 0.5, 0.16, 2);
    var r: i32 = 0;
    while (r < 5) : (r += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(r)) / 5.0 + rng.signed() * 0.3;
        b.addCapsule(v3(0, 0.5, 0), v3(mathx.cosf(a) * rng.range(0.7, 1.2), 0.03, mathx.sinf(a) * rng.range(0.7, 1.2)), 0.15, 0.05, 5, BARK_OLD);
    }
    b.setMat(.plant);
    // Moss up the weather side, SEATED on the trunk with only a cushion of it proud. Parked at a random
    // offset from the AXIS instead it was a green hexagon bolted to the bark — the offset can exceed the
    // trunk's own radius, and even inside it a 0.28 blob on a 0.48 trunk stands most of the way clear.
    b.addBlob(onTrunk(H, lean, rng.range(0.6, 2.2), rng.angle(), 0.55), v3(0.26, 0.34, 0.22), 3, 6, MOSS_DK);
    var g: i32 = 0;
    while (g < 3) : (g += 1) tuftInto(&b, &rng, rng.signed() * 1.2, rng.signed() * 1.2, 0.85);
    return b.toModel(shader);
}

pub fn saplingMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(7104);
    b.setMat(.bark);
    const H: f32 = rng.range(2.2, 3.1);
    const nstems: i32 = 1 + rng.intn(2);
    var st: i32 = 0;
    while (st < nstems) : (st += 1) {
        const a = rng.angle();
        const off = if (st == 0) @as(f32, 0) else rng.range(0.08, 0.22);
        const x0 = mathx.cosf(a) * off;
        const z0 = mathx.sinf(a) * off;
        const h = H * (if (st == 0) @as(f32, 1.0) else rng.range(0.6, 0.9));
        const tipX = x0 + rng.signed() * 0.30;
        const tipZ = z0 + rng.signed() * 0.30;
        b.addCapsule(v3(x0, 0, z0), v3(tipX, h, tipZ), 0.075, 0.028, 6, BARK);
        var tw: i32 = 0;
        while (tw < 4) : (tw += 1) {
            const t = rng.range(0.35, 0.95);
            const ta = rng.angle();
            const tl = rng.range(0.25, 0.6);
            const bx = x0 + (tipX - x0) * t;
            const bz = z0 + (tipZ - z0) * t;
            b.addCapsule(v3(bx, h * t, bz), v3(bx + mathx.cosf(ta) * tl, h * t + rng.range(0.15, 0.45), bz + mathx.sinf(ta) * tl), 0.028, 0.010, 4, BARK_DK);
        }
        b.setMat(.plant);
        var c: i32 = 0;
        while (c < 16) : (c += 1) {
            const ca = rng.angle();
            const cd = rng.range(0.0, 0.62);
            const rr = rng.range(0.15, 0.28);
            b.addBlob(
                v3(x0 + (tipX - x0) * 0.7 + mathx.cosf(ca) * cd, h * rng.range(0.34, 1.02), z0 + (tipZ - z0) * 0.7 + mathx.sinf(ca) * cd),
                v3(rr, rr * rng.range(0.6, 0.9), rr * rng.range(0.85, 1.15)),
                4,
                6,
                if (rng.float() < 0.25) LEAF_GOLD else if (rng.float() < 0.5) LEAF_LT else if (rng.float() < 0.75) LEAF else LEAF_DAMP,
            );
        }
        b.setMat(.bark);
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 0.5, rng.signed() * 0.5, 0.8);
    return b.toModel(shader);
}

