// ── PROPS: WOOD ── everything that was a tree. The dead tree (the most repeated silhouette in the
// world), the great trees and their canopy builder, willow, conifer, birch, the snag, the sapling,
// the stump and the fallen log.
//
// THEY ARE TOGETHER BECAUSE THEY FAIL TOGETHER: bark takes the low sun square on, and at anything
// lighter than BARK_OLD the shader's hot key plus its gamma lift hands back a smooth PALE TAN post.
// Every fix here is the same fix — dark bark, grain ridges to break the mass, pale heartwood where
// it snapped — so a change to one is nearly always a change to all of them.
const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const art = @import("propart.zig");

const v3 = mathx.v3;
const Builder = gfx.Builder;
// The shared vocabulary this file draws on, aliased so a mesh body still reads as a recipe
// (`art.STONE_DK` in front of every colour buries the shape in namespace). GENERATED from what
// the file actually references — the list IS the dependency, so it is worth reading.
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
const SCRUB_DK = art.SCRUB_DK;
const STONE_MOSS = art.STONE_MOSS;
const TIMBER = art.TIMBER;
const crackInto = art.crackInto;
const lichenInto = art.lichenInto;
const tuftInto = art.tuftInto;

// A DEAD TREE — the Lands Between silhouette against the haze, and the most repeated tree in
// the world. Everything it has is SILHOUETTE, because it has no leaves to hide behind: a bent
// bole with the bark peeling, a split up one side, branches that fork TWICE (fork once and it
// reads as a garden fork stuck in the ground), bracket fungus, and a root flare lifted on one
// side where the ground gave.
pub fn treeMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4806);
    b.setMat(.wood);
    const bend = v3(rng.range(0.08, 0.24), 0, rng.signed() * 0.14);
    const j1 = v3(bend.x, 1.70, bend.z);
    const j2 = v3(bend.x * 2.8, 3.05, bend.z * 2.4);
    // A point ON the bole: the taper and the BEND both. Anything dressed onto the trunk goes
    // through here — seated at a fixed radius on a trunk that leans, the fungus and the lichen
    // floated off its side like stickers.
    const onBole = struct {
        fn go(bd: rl.Vector3, y: f32, a: f32, sink: f32) rl.Vector3 {
            const rr = (0.26 - 0.056 * y) * (1.0 - sink);
            return v3(bd.x * (y / 1.7) + mathx.cosf(a) * rr, y, bd.z * (y / 1.7) + mathx.sinf(a) * rr);
        }
    }.go;
    // BARK_OLD, not BARK — the same correction the great trees, the stump and the log all needed:
    // this bole takes the low sun square on, and at BARK's value the shader's hot key plus its
    // gamma lift handed back a smooth PALE TAN post. A dead tree is the darkest thing on the plain.
    b.addCapsule(v3(0, 0, 0), j1, 0.26, 0.165, 8, BARK_OLD);
    b.addCapsule(j1, j2, 0.165, 0.095, 7, BARK_OLD);
    b.addCapsule(j2, v3(j2.x + rng.signed() * 0.3, 4.05, j2.z + rng.signed() * 0.25), 0.095, 0.012, 6, BARK_DK); // the snapped leader
    // PEELING BARK: slim strips up the bole, a couple standing away from it. Those vertical
    // breaks are what stop the trunk reading as a smooth dowel under the low sun.
    var s: i32 = 0;
    while (s < 7) : (s += 1) {
        const a = rng.angle();
        const y0 = rng.range(0.05, 1.1);
        const y1 = y0 + rng.range(0.5, 1.5);
        const r0 = 0.235 - 0.055 * y0;
        const r1 = 0.235 - 0.055 * y1;
        const lift: f32 = if (rng.float() < 0.3) rng.range(0.04, 0.10) else 0.0; // one has come away
        b.addCylinder(
            v3(bend.x * (y0 / 1.7) + mathx.cosf(a) * (r0 + lift), y0, bend.z * (y0 / 1.7) + mathx.sinf(a) * (r0 + lift)),
            v3(bend.x * (y1 / 1.7) + mathx.cosf(a + rng.signed() * 0.2) * (r1 + lift * 1.6), y1, bend.z * (y1 / 1.7) + mathx.sinf(a + rng.signed() * 0.2) * (r1 + lift * 1.6)),
            rng.range(0.030, 0.055),
            rng.range(0.018, 0.040),
            4,
            // The VALUE INVERSION that says "peeling": strips still holding are dark bark, and where
            // one has lifted or gone, the wood UNDER it is bare and pale. Dark strips on a dark bole
            // are invisible; dark strips on a pale bole read as painted stripes.
            if (rng.float() < 0.45) BARK_DK else if (rng.float() < 0.7) TIMBER else BARK_OLD,
        );
    }
    // A SPLIT up the heartwood, and the hollow where a limb rotted out of it.
    crackInto(&b, v3(mathx.cosf(1.9) * 0.22, 0.30, mathx.sinf(1.9) * 0.22), v3(0.06, 0.99, 0.02), v3(-mathx.sinf(1.9), 0, mathx.cosf(1.9)), rng.range(0.9, 1.5), 0.026, 0.05);
    b.setMat(.wood);
    b.addBlob(v3(bend.x * 0.7 + 0.20, 1.25, bend.z * 0.7 - 0.06), v3(0.09, 0.14, 0.09), 3, 6, IRON); // the rot hollow, dark
    // BRANCHES, each forking again — six primaries off the two joints, two or three twigs each.
    var br: i32 = 0;
    while (br < 6) : (br += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(br)) / 6.0 + rng.signed() * 0.6;
        const from = if (rng.float() < 0.45) j1 else j2;
        const out = rng.range(0.8, 1.55);
        const up = rng.range(0.5, 1.15);
        const tip = v3(from.x + mathx.cosf(a) * out, from.y + up, from.z + mathx.sinf(a) * out);
        b.addCapsule(from, tip, rng.range(0.055, 0.085), rng.range(0.014, 0.026), 5, BARK_DK);
        const nt: i32 = 2 + rng.intn(2);
        var t: i32 = 0;
        while (t < nt) : (t += 1) {
            const ta = a + rng.signed() * 1.3;
            const tl = rng.range(0.35, 0.85);
            b.addCapsule(
                v3(from.x + (tip.x - from.x) * rng.range(0.5, 0.9), from.y + (tip.y - from.y) * rng.range(0.5, 0.9), from.z + (tip.z - from.z) * rng.range(0.5, 0.9)),
                v3(tip.x + mathx.cosf(ta) * tl, tip.y + rng.range(0.1, 0.65), tip.z + mathx.sinf(ta) * tl),
                0.026,
                0.006,
                4,
                BARK_DK,
            );
        }
    }
    // ROOT FLARE: five roots splaying onto the ground, one LIFTED where the earth gave under it.
    var r: i32 = 0;
    while (r < 5) : (r += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(r)) / 5.0 + rng.signed() * 0.35;
        const d = rng.range(0.42, 0.72);
        const heave: f32 = if (r == 2) rng.range(0.14, 0.26) else 0.0;
        b.addCapsule(v3(0, 0.26, 0), v3(mathx.cosf(a) * d, 0.02 + heave, mathx.sinf(a) * d), rng.range(0.09, 0.13), rng.range(0.025, 0.05), 5, BARK_OLD);
    }
    // BRACKET FUNGUS on the shaded side: a dead trunk with fungus has been dead for years; one
    // without has been dead since Tuesday.
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

// A GRAVE CLUSTER — a family plot the wood took back. Six markers of FOUR kinds (round-topped
// headstone, a cross with an arm gone, a ledger slab sunk into the turf, a stumpy footstone),
// each leaning its own way and sunk to its own depth. What sells a graveyard is that no two
// stones share a shape or an angle; matched slabs read as a municipal cemetery.
// ── TIMBER ──

// A broken stump: splintered barrel, a couple of standing splinters, root flare, and a
// mossy cap where the heartwood is rotting out.
pub fn stumpMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(313);
    b.setMat(.wood);
    // BARK_OLD, not BARK — the barrel takes the sun face-on and came back a pale smooth loaf
    // (same correction as the great tree's trunk).
    b.addCapsule(v3(0, 0, 0), v3(rng.signed() * 0.08, 1.05, rng.signed() * 0.08), 0.46, 0.40, 8, BARK_OLD);
    // Bark ridges, mostly buried (RELIEF IS SUBTLE) — the texture that stops the barrel
    // reading as plastic however dark it starts.
    var rb: i32 = 0;
    while (rb < 7) : (rb += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(rb)) / 7.0 + rng.signed() * 0.25;
        // Seated so the rod's EDGE breaks the surface (~5% of the radius proud). The first cut
        // buried them completely and the barrel stayed one smooth lit loaf.
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
    // The broken top reads as WOOD: a pale heartwood face just proud of the bark, the moss
    // cap riding it off-centre where the rot got in.
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

// A fallen trunk gone over in some old storm: one long tapered barrel lying along local X,
// stubs of snapped branches, a torn root plate at the butt, moss along the upper face.
pub fn logMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(818);
    b.setMat(.wood);
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
    // The snapped tip shows pale heartwood — the one bright note, and what says "broken",
    // not "moulded with a round end".
    b.addBlob(v3(1.94, 0.30, 0.02), v3(0.07, 0.20, 0.17), 4, 7, TIMBER);
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const x = rng.range(-1.5, 1.6);
        const a = rng.angle();
        b.addCapsule(v3(x, 0.34, 0), v3(x + rng.signed() * 0.35, 0.34 + @abs(mathx.sinf(a)) * 0.45, mathx.cosf(a) * 0.62), 0.075, 0.02, 5, BARK_DK);
    }
    // The root plate: a torn disc of roots and clung earth standing up at the butt end.
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

// ── GREAT TREES ── the Old Wood's skyline. Casters (so they lay long raking shadows across
// the plain) and therefore rigid: the depth pass has no wind term, so a swaying caster's
// shadow crawls away from its trunk.

// One great tree's proportions. THREE variants exist (bigtree / bigtree2 / bigtree3) because
// this is the most repeated large prop in the world: with a single mesh, a wood of sixty trees
// is sixty copies of the same silhouette, and yaw + scale do not hide that. Different seeds
// alone would do it, but varying the PROPORTIONS as well gives the wood a species mix.
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

// A soft, LUMPY canopy mass — many interpenetrating blobs on a rough ellipsoid shell rather
// than one big flattened dome. The dome version read as a MUSHROOM: a bare trunk with a plate
// on top, because a single blob has a smooth silhouette and nothing hangs down between the
// boughs. Masses on the underside are darker (self-shadowed), the sunward crown is gold.
pub fn canopyInto(b: *Builder, rng: *mathx.Rng, cx: f32, cy: f32, cz: f32, rx: f32, ry: f32, gold: f32, n: i32) void {
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        // Distribute over the SHELL, biased outward, so the mass is hollow-ish and its
        // silhouette is made of many bumps instead of one curve. Masses are LARGE relative to
        // that shell (0.34..0.56 of it) so they interpenetrate into one body: at half this size
        // the canopy read as a cluster of separate BUBBLES hanging in the air.
        const a = rng.angle();
        const t = rng.range(0.30, 0.88);
        const yt = rng.signed(); // -1 = underside, +1 = crown
        const rr = rx * t;
        const px = cx + mathx.cosf(a) * rr;
        const pz = cz + mathx.sinf(a) * rr;
        const py = cy + yt * ry * (1.0 - 0.45 * t);
        const size = rx * rng.range(0.34, 0.56) * (1.0 - 0.20 * t);
        const col = if (yt > 0.35 and rng.float() < gold) LEAF_GOLD else if (yt > 0.0) (if (rng.float() < 0.4) LEAF_LT else LEAF) else if (rng.float() < 0.55) LEAF_DK else LEAF;
        b.addBlob(v3(px, py, pz), v3(size, size * rng.range(0.62, 0.92), size * rng.range(0.82, 1.18)), 5, 7, col);
    }
}

// A GREAT TREE: buttressed root flare, a trunk that leans and forks LOW, boughs reaching out
// and up, and a canopy of interpenetrating foliage masses that clothes those boughs all the way
// in — deep and near-black underneath, gold on the crown where the low sun rakes it. One bough
// is dead and bare (the wabi-sabi break in an otherwise full crown).
pub fn bigTreeMesh(shader: rl.Shader, spec: TreeSpec) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(spec.seed);
    b.setMat(.wood);
    const leanX = rng.signed() * 0.55;
    const leanZ = rng.signed() * 0.45;
    // Buttress roots: fat capsules splaying from the trunk foot out onto the ground.
    var r: i32 = 0;
    while (r < 7) : (r += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(r)) / 7.0 + rng.signed() * 0.3;
        const d = rng.range(1.1, 1.9);
        b.addCapsule(v3(0, 0.85, 0), v3(mathx.cosf(a) * d, 0.04, mathx.sinf(a) * d), rng.range(0.20, 0.34), rng.range(0.06, 0.12), 6, BARK);
    }
    // Trunk in three lengths, narrowing and drifting off vertical. BARK_OLD, not BARK: a 2 m
    // barrel taking the sun face-on comes back a pale flat beige after the shader's hot key and
    // gamma lift (AGENTS.md: author dark colours near-black, and a big smooth mass needs it most).
    const t1 = v3(leanX * 0.3, spec.trunk * 0.42, leanZ * 0.3);
    const t2 = v3(leanX * 0.7, spec.trunk * 0.78, leanZ * 0.7);
    const fork = v3(leanX, spec.trunk, leanZ);
    b.addCapsule(v3(0, 0.0, 0), t1, 0.95, 0.80, 9, BARK_OLD);
    b.addCapsule(t1, t2, 0.80, 0.62, 9, BARK_OLD);
    b.addCapsule(t2, fork, 0.62, 0.48, 8, BARK);
    // Bark RIDGES: slim darker capsules running up the barrel. Without them the trunk is one
    // smooth lit cylinder and reads as plastic however dark you make it — the form needs breaks.
    //
    // Same correction as the column's flutes (see RELIEF IS SUBTLE): these were 4-SIDED rods, so
    // square bars, and at radius 0.15 sitting as far out as 0.92 of a ~0.93 barrel they stood a
    // FIFTH of the trunk's radius clear of its flats — more proud than the flutes were. Bark is a
    // texture you read at two metres, not a set of battens. Thinner, seated further in so the rod
    // is mostly buried, 6-sided so there is no square corner running the whole height.
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
    // Boughs: six reaching out from the fork zone at wide, uneven bearings.
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
        // Twiggy sub-branches off each bough, so the canopy has something inside it.
        var s: i32 = 0;
        while (s < 3) : (s += 1) {
            const sa = a + rng.signed() * 1.1;
            const sl = rng.range(0.7, 1.5);
            b.addCapsule(mid, v3(mid.x + mathx.cosf(sa) * sl, mid.y + rng.range(0.4, 1.1), mid.z + mathx.sinf(sa) * sl), 0.09, 0.03, 5, BARK_DK);
        }
        tips[@intCast(i)] = tip;
    }
    // One dead bough, bare and clawing.
    const da = rng.angle();
    b.addCapsule(t2, v3(t2.x + mathx.cosf(da) * 3.4 * spec.spread, t2.y + 0.9, t2.z + mathx.sinf(da) * 3.4), 0.26, 0.05, 6, BARK_DK);

    // THE CANOPY, in three layers so the silhouette is lumpy from every side:
    b.setMat(.plant);
    const crownY = spec.trunk + 2.5 * spec.lift + 1.5;
    const crownR = 3.7 * spec.spread;
    //   1. foliage CLOTHING each bough — this is what removes the bare-trunk/plate-on-top read
    i = 0;
    while (i < NB) : (i += 1) {
        const tip = tips[@intCast(i)];
        const mid = v3((tip.x + fork.x) * 0.5, (tip.y + fork.y) * 0.5 + 0.3, (tip.z + fork.z) * 0.5);
        canopyInto(&b, &rng, tip.x, tip.y + 0.5, tip.z, 1.7 * spec.spread, 1.1, spec.gold, 5);
        canopyInto(&b, &rng, mid.x, mid.y, mid.z, 1.35 * spec.spread, 0.95, spec.gold * 0.5, 3);
    }
    //   2. the main mass over the whole crown
    canopyInto(&b, &rng, leanX * 1.1, crownY, leanZ * 1.1, crownR, 1.9, spec.gold, 16);
    //   3. a gold-touched top, where the sun actually lands
    canopyInto(&b, &rng, leanX * 1.2, crownY + 1.5, leanZ * 1.2, crownR * 0.55, 0.9, 0.85, 5);
    var g: i32 = 0;
    while (g < 4) : (g += 1) {
        const a = rng.angle();
        const d = rng.range(1.2, 2.3);
        tuftInto(&b, &rng, mathx.cosf(a) * d, mathx.sinf(a) * d, rng.range(0.7, 1.0));
    }
    return b.toModel(shader);
}

// A WILLOW at the water's edge: short thick bole, boughs that go UP then break and pour back
// down, with narrow pale foliage strung along the falls. Silvered green — thirstier than the
// wood's oaks.
pub fn willowMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(7002);
    b.setMat(.wood);
    var r: i32 = 0;
    while (r < 5) : (r += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(r)) / 5.0 + rng.signed() * 0.3;
        b.addCapsule(v3(0, 0.6, 0), v3(mathx.cosf(a) * 1.0, 0.03, mathx.sinf(a) * 1.0), 0.16, 0.06, 5, BARK);
    }
    const crown = v3(rng.signed() * 0.35, 3.4, rng.signed() * 0.3);
    b.addCapsule(v3(0, 0, 0), v3(crown.x * 0.5, 1.8, crown.z * 0.5), 0.70, 0.52, 8, BARK_OLD);
    b.addCapsule(v3(crown.x * 0.5, 1.8, crown.z * 0.5), crown, 0.52, 0.34, 7, BARK);
    // Six boughs up-and-over, each ending well out and DOWN — the willow's whole read.
    const NB = 6;
    var i: i32 = 0;
    while (i < NB) : (i += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, NB) + rng.signed() * 0.35;
        const out = rng.range(2.0, 3.2);
        const top = v3(crown.x + mathx.cosf(a) * out * 0.55, crown.y + rng.range(0.9, 1.7), crown.z + mathx.sinf(a) * out * 0.55);
        const fallTo = v3(crown.x + mathx.cosf(a) * out, rng.range(0.9, 2.1), crown.z + mathx.sinf(a) * out);
        b.addCapsule(crown, top, 0.28, 0.18, 6, BARK);
        b.addCapsule(top, fallTo, 0.18, 0.07, 5, BARK_LIVE);
        // The curtain: narrow foliage masses strung DOWN the fall, plus a few whips below it.
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
        b.setMat(.wood);
    }
    b.setMat(.plant);
    b.addBlob(crown, v3(1.9, 1.15, 1.85), 5, 8, LEAF_DK); // the dense heart of the crown
    var g: i32 = 0;
    while (g < 3) : (g += 1) {
        const a = rng.angle();
        tuftInto(&b, &rng, mathx.cosf(a) * rng.range(0.9, 1.6), mathx.sinf(a) * rng.range(0.9, 1.6), 0.85);
    }
    return b.toModel(shader);
}

// A CONIFER: a dark spire. Whorls of drooping branch fans stepping in as they rise, over a bare
// straight bole. It exists for the SKYLINE — a wood of nothing but broad round crowns has no
// punctuation in it, and one spire per dozen oaks fixes that.
pub fn coniferMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(7101);
    b.setMat(.wood);
    const H: f32 = rng.range(9.5, 11.5);
    b.addCapsule(v3(0, 0, 0), v3(rng.signed() * 0.25, H * 0.55, rng.signed() * 0.2), 0.52, 0.32, 8, BARK_OLD);
    b.addCapsule(v3(rng.signed() * 0.25, H * 0.55, rng.signed() * 0.2), v3(rng.signed() * 0.3, H, rng.signed() * 0.25), 0.32, 0.05, 7, BARK_DK);
    var r: i32 = 0;
    while (r < 5) : (r += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(r)) / 5.0;
        b.addCapsule(v3(0, 0.5, 0), v3(mathx.cosf(a) * 0.85, 0.03, mathx.sinf(a) * 0.85), 0.13, 0.05, 5, BARK);
    }
    // Whorls: each one a ring of fans, narrowing with height. Branches DROOP (the tips sit below
    // where they leave the trunk) — that downward sweep is the whole silhouette of a conifer.
    b.setMat(.plant);
    // MANY whorls, closely spaced, and each fan wide enough to reach the one above it. At 13 well-
    // separated whorls the tree read as a PAGODA — a stack of discrete tiers with air between them.
    // A conifer's silhouette is a continuous ragged cone, so the tiers have to overlap.
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
            b.setMat(.wood);
            b.addCapsule(v3(0, y, 0), v3(px, y - reach * 0.22, pz), 0.055, 0.02, 4, BARK_DK);
            b.setMat(.plant);
            // Two masses per fan, the outer one lower — a drooping bough of needles. Deliberately
            // TALL enough (0.22 of reach) to meet the whorl above and close the cone.
            b.addBlob(v3(px * 0.55, y - reach * 0.08, pz * 0.55), v3(reach * 0.42, reach * 0.22, reach * 0.42), 3, 6, if (rng.float() < 0.28) NEEDLE_LT else NEEDLE);
            b.addBlob(v3(px * 0.92, y - reach * 0.20, pz * 0.92), v3(reach * 0.32, reach * 0.17, reach * 0.32), 3, 6, NEEDLE);
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

// A BIRCH: a slender PALE trunk with dark scars, and a light open crown. The only tree you can
// pick out by colour at distance, so it reads as a different species from across the plain.
pub fn birchMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(7102);
    b.setMat(.wood);
    const H: f32 = rng.range(7.0, 8.6);
    const lean = rng.signed() * 0.5;
    const mid = v3(lean * 0.4, H * 0.5, rng.signed() * 0.3);
    const fork = v3(lean, H * 0.72, rng.signed() * 0.4);
    b.addCapsule(v3(0, 0, 0), mid, 0.30, 0.24, 8, BIRCH_BARK);
    b.addCapsule(mid, fork, 0.24, 0.17, 7, BIRCH_BARK);
    // The scars: short dark bands round the trunk, which is what makes it read as birch and not
    // as a dead pale stick.
    var s: i32 = 0;
    while (s < 12) : (s += 1) {
        const t = rng.range(0.05, 0.70);
        const a = rng.angle();
        const yy = H * t;
        const rr = 0.30 - 0.13 * t;
        b.addBlob(v3(lean * t * 0.55 + mathx.cosf(a) * rr * 0.85, yy, mathx.sinf(a) * rr * 0.85), v3(rr * rng.range(0.25, 0.6), rng.range(0.025, 0.06), rr * rng.range(0.25, 0.6)), 3, 5, BIRCH_SCAR);
    }
    // Branches: fine, ascending, and few — a birch crown is airy, you see sky through it.
    b.setMat(.plant);
    const NB = 7;
    var i: i32 = 0;
    while (i < NB) : (i += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, NB) + rng.signed() * 0.5;
        const out = rng.range(1.4, 2.6);
        const up = rng.range(1.0, 2.2);
        const base = if (rng.float() < 0.4) mid else fork;
        const tip = v3(base.x + mathx.cosf(a) * out, base.y + up, base.z + mathx.sinf(a) * out);
        b.setMat(.wood);
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

// A SNAG: a tall dead trunk stripped of bark and branches, snapped off jagged at the top. Pure
// silhouette — the thing a wood needs so its skyline isn't uniformly alive.
pub fn snagMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(7103);
    b.setMat(.wood);
    const H: f32 = rng.range(6.0, 7.6);
    const lean = rng.signed() * 0.4;
    b.addCapsule(v3(0, 0, 0), v3(lean * 0.5, H * 0.6, lean * 0.3), 0.55, 0.36, 8, BARK_OLD);
    b.addCapsule(v3(lean * 0.5, H * 0.6, lean * 0.3), v3(lean, H, lean * 0.6), 0.36, 0.26, 7, BARK_DK);
    // A point on the TRUNK's surface at height y and angle a: taper and lean both, so what is
    // dressed onto it stays on it all the way up.
    const onTrunk = struct {
        fn go(hh: f32, ln: f32, y: f32, a: f32, sink: f32) rl.Vector3 {
            const t = y / hh;
            const rr = (if (t < 0.6) 0.55 + (0.36 - 0.55) * (t / 0.6) else 0.36 + (0.26 - 0.36) * ((t - 0.6) / 0.4)) * (1.0 - sink);
            const ax = if (t < 0.6) ln * 0.5 * (t / 0.6) else ln * (0.5 + 0.5 * ((t - 0.6) / 0.4));
            return v3(ax + mathx.cosf(a) * rr, y, ax * 0.6 + mathx.sinf(a) * rr);
        }
    }.go;
    // GRAIN RIDGES up the trunk, mostly buried. Without them a 7 m eight-sided cone is one smooth
    // lit face from every angle and the snag reads as a PLANK stood on end — the same correction
    // the stump and the fallen log needed, and the more necessary here for the height.
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
            // Bare dead wood: shade grooves, and a couple of ribs the weather has silvered.
            if (rng.float() < 0.72) BARK_DK else TIMBER,
        );
    }
    // The snapped crown: pale HEARTWOOD across the break — the one bright note, and what says
    // "snapped" rather than "moulded to a point" — with splinters of unequal length out of it.
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
    // A couple of broken limb stubs, and one long bare branch still on. STUBS, so they are thick
    // at the trunk and end in a pale snapped face — thin even tapers read as twigs stuck on.
    var l: i32 = 0;
    while (l < 4) : (l += 1) {
        const a = rng.angle();
        const y = rng.range(H * 0.35, H * 0.9);
        const reach = rng.range(0.45, 0.95);
        const tip = v3(lean * 0.4 + mathx.cosf(a) * reach, y + rng.range(-0.1, 0.4), lean * 0.2 + mathx.sinf(a) * reach);
        b.addCapsule(v3(lean * 0.4, y, lean * 0.2), tip, 0.17, 0.065, 5, BARK_DK);
        b.addBlob(tip, v3(0.065, 0.055, 0.065), 3, 5, TIMBER);
    }
    const ba = rng.angle();
    b.addCapsule(v3(lean * 0.5, H * 0.7, lean * 0.3), v3(lean * 0.5 + mathx.cosf(ba) * 2.6, H * 0.85, lean * 0.3 + mathx.sinf(ba) * 2.6), 0.16, 0.03, 5, BARK_DK);
    var r: i32 = 0;
    while (r < 5) : (r += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(r)) / 5.0 + rng.signed() * 0.3;
        b.addCapsule(v3(0, 0.5, 0), v3(mathx.cosf(a) * rng.range(0.7, 1.2), 0.03, mathx.sinf(a) * rng.range(0.7, 1.2)), 0.15, 0.05, 5, BARK_OLD);
    }
    b.setMat(.plant);
    b.addBlob(v3(rng.signed() * 0.3, rng.range(0.6, 2.2), rng.signed() * 0.5), v3(0.28, 0.35, 0.24), 3, 6, MOSS_DK); // moss up the weather side
    var g: i32 = 0;
    while (g < 3) : (g += 1) tuftInto(&b, &rng, rng.signed() * 1.2, rng.signed() * 1.2, 0.85);
    return b.toModel(shader);
}

// A SAPLING: a young tree, a couple of whippy stems and a thin crown. Fills the gap between a bush
// and a great tree — a wood with no young trees in it reads as scenery rather than as a forest.
pub fn saplingMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(7104);
    b.setMat(.wood);
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
        // Side twigs, and a small crown of leaf masses on top.
        var tw: i32 = 0;
        while (tw < 4) : (tw += 1) {
            const t = rng.range(0.35, 0.95);
            const ta = rng.angle();
            const tl = rng.range(0.25, 0.6);
            const bx = x0 + (tipX - x0) * t;
            const bz = z0 + (tipZ - z0) * t;
            b.addCapsule(v3(bx, h * t, bz), v3(bx + mathx.cosf(ta) * tl, h * t + rng.range(0.15, 0.45), bz + mathx.sinf(ta) * tl), 0.028, 0.010, 4, BARK_DK);
        }
        // The crown starts LOW on the stem and is made of many small masses. Seven big blobs on the
        // top third made a lollipop; a young tree is leafy most of the way down.
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
        b.setMat(.wood);
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 0.5, rng.signed() * 0.5, 0.8);
    return b.toModel(shader);
}

