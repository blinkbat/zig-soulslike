// ── PROPS: VILLAGE + WAYSIDE DRESSING ── the small things that say people lived here: carts, wells,
// shrines, lanterns, fences, casks, woodpiles, bones, sarcophagi, stairs, gibbets. None of them are
// landmarks; their whole job is to be FOUND, so they are cheap, low and scattered.
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

// A broken CART: two spoked wheels (one collapsed flat), a plank bed dropped on its axle,
// a snapped draught shaft in the air. Somebody was leaving when this happened.
pub fn cartMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4747);
    b.setMat(.wood);
    // The bed, tipped: planks along local X, one end down on the ground.
    var pl: i32 = 0;
    while (pl < 6) : (pl += 1) {
        const z = (@as(f32, @floatFromInt(pl)) - 2.5) * 0.28;
        if (rng.float() < 0.15) continue;
        b.addBox(v3(0, 0.72 + rng.signed() * 0.02, z), v3(1.05, -0.20, 0), v3(0, 0.055, 0), v3(0, 0, 0.13), if (@mod(pl, 2) == 0) TIMBER else TIMBER_DK);
    }
    b.addCapsule(v3(-1.05, 0.60, 0), v3(1.05, 0.44, 0), 0.09, 0.08, 6, TIMBER_DK); // axle beam
    b.addCapsule(v3(1.0, 0.50, 0.1), v3(2.15, 0.95, 0.25), 0.075, 0.05, 5, TIMBER_DK); // shaft, snapped upward
    // Wheels: a rim of short chords + spokes. One stands, one has folded flat.
    const wheel = struct {
        fn go(bb: *Builder, cx: f32, cy: f32, cz: f32, rad: f32, flat: bool, r: *mathx.Rng) void {
            const seg: i32 = 10;
            var i: i32 = 0;
            while (i < seg) : (i += 1) {
                const a0 = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(seg));
                const a1 = std.math.tau * @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(seg));
                if (r.float() < 0.12) continue; // a missing felloe
                const p0 = if (flat) v3(cx + mathx.cosf(a0) * rad, cy, cz + mathx.sinf(a0) * rad) else v3(cx + mathx.cosf(a0) * rad, cy + mathx.sinf(a0) * rad, cz);
                const p1 = if (flat) v3(cx + mathx.cosf(a1) * rad, cy, cz + mathx.sinf(a1) * rad) else v3(cx + mathx.cosf(a1) * rad, cy + mathx.sinf(a1) * rad, cz);
                bb.addCapsule(p0, p1, 0.075, 0.075, 5, BARK_DK);
                if (@mod(i, 2) == 0) bb.addCapsule(v3(cx, cy, cz), p0, 0.035, 0.028, 4, TIMBER_DK); // spoke
            }
        }
    }.go;
    wheel(&b, -0.9, 0.62, 0.95, 0.60, false, &rng);
    wheel(&b, 0.85, 0.09, -1.0, 0.58, true, &rng);
    b.setMat(.cloth);
    // A slumped CANVAS tarp of cargo cover — dyed red was tried twice (CLOTH, then the darker
    // fold tone) and both flared to neon on the sun-facing swell; see CANVAS. The one dyed
    // note left is a rag of the old crimson pinned under its edge.
    b.addBlob(v3(0.2, 0.84, 0.2), v3(0.45, 0.09, 0.35), 3, 5, CANVAS);
    b.addBlob(v3(0.42, 0.78, -0.04), v3(0.17, 0.045, 0.14), 3, 5, CLOTH_DK);
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 1.2, rng.signed() * 1.2, 0.7);
    return b.toModel(shader);
}

// ── VILLAGE + WAYSIDE DRESSING ── the small things that say people lived here. None of them are
// landmarks; their whole job is to be found, so they are cheap, low, and scattered.

// A WELL: a drum of field stone, a timber windlass on two posts, a rope, and a bucket lying on
// the coping where somebody left it.
pub fn wellMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2101);
    b.setMat(.stone);
    // The drum: a core cylinder under a COURSED FACING of blocks. It used to be three rings of
    // twelve identical rounded blobs, alternately pale and mossy — a lattice of beads that read as
    // bubble wrap, not field stone. Same rule as every other wall here: the core carries the form
    // and the facing only stands proud enough to catch the sun.
    const R: f32 = 0.80;
    b.addCylinder(v3(0, 0.02, 0), v3(0, 1.04, 0), R, R, 12, MORTAR);
    var c: i32 = 0;
    while (c < 4) : (c += 1) {
        const y0 = 0.05 + @as(f32, @floatFromInt(c)) * 0.25;
        // Walk the ring by ACCUMULATED ARC so block WIDTHS can vary: dividing the circle into n
        // equal slots is what makes a course read as beads however much the radii wobble. Each
        // course starts at its own angle, so no joint stacks into a vertical seam.
        var a = rng.angle();
        const stop = a + std.math.tau;
        while (a < stop) {
            const halfArc = rng.range(0.09, 0.19); // metres along the face
            const dHalf = halfArc / R;
            const am = a + dHalf;
            const cs = mathx.cosf(am);
            const sn = mathx.sinf(am);
            const hh = rng.range(0.085, 0.125);
            const depth = rng.range(0.045, 0.085); // how far out of the core it stands
            b.addBox(
                v3(cs * R, y0 + hh + rng.signed() * 0.012, sn * R),
                v3(-sn * halfArc, rng.signed() * 0.022, cs * halfArc), // along the face, a little out of level
                v3(0, hh, 0),
                v3(cs * depth, 0, sn * depth),
                // Mostly ONE stone: 30% pale and 35% mossy was a checkerboard. The moss belongs
                // where the wet is (see below), not sprinkled over the whole drum.
                if (rng.float() < 0.16) STONE_LT else if (rng.float() < 0.22) STONE_DK else STONE,
            );
            a += 2 * dHalf + rng.range(0.015, 0.05) / R;
        }
    }
    // Moss where a well is actually wet: the bottom course, and the shaded lip under the coping.
    for ([_]f32{ 0.10, 0.94 }) |my| {
        const ma = rng.angle();
        lichenInto(&b, &rng, v3(mathx.cosf(ma) * 0.84, my, mathx.sinf(ma) * 0.84), v3(0.22, 0.09, 0.20), 3);
    }
    b.setMat(.stone);
    // THE COPING, laid as slabs rather than turned as a ring — one has gone altogether and one has
    // been shoved out of line, which is the whole difference between a ruin and a garden feature.
    const nc: i32 = 11;
    var k: i32 = 0;
    while (k < nc) : (k += 1) {
        if (k == 7) continue; // the missing slab
        const am = std.math.tau * (@as(f32, @floatFromInt(k)) + 0.5) / @as(f32, @floatFromInt(nc));
        const shove: f32 = if (k == 3) rng.range(0.04, 0.07) else 0.0;
        const cs = mathx.cosf(am);
        const sn = mathx.sinf(am);
        // A SHADE OVER the exact share of the ring (2πr/n/2 = 0.25 m), because each slab is a flat box
        // tangent to a circle: butted exactly, the corners leave wedge gaps and the coping reads as
        // loose flagstones balanced round the rim.
        const halfArc = std.math.pi * 2.0 * 0.875 / @as(f32, @floatFromInt(nc)) * 0.5 * 1.18;
        // Deep enough to be a DRESSED coping stone and only just overhanging: thin slabs hung far
        // out past the face read as a frill of flagstones balanced on the rim. The inner edge stops
        // clear of the mouth, so no pale ends ring the hole.
        b.addBox(
            v3(cs * (0.875 + shove), 1.07 + rng.signed() * 0.012, sn * (0.875 + shove)),
            v3(-sn * halfArc, rng.signed() * 0.018, cs * halfArc),
            v3(0, rng.range(0.06, 0.078), 0),
            v3(cs * 0.13, 0, sn * 0.13),
            if (rng.float() < 0.22) STONE else STONE_DK,
        );
    }
    // THE MOUTH, dark. It has to be a CLOSED shape, not a tube: a tube shows you the world straight
    // through its far wall (that face points away and is culled), which reads as a hole in the mesh.
    // So the black is a solid dark lens seated just under the coping, wide enough to seal the whole
    // bore — deep water in shadow, which is all a well mouth ever is from standing height.
    b.addBlob(v3(0, 0.62, 0), v3(0.80, 0.26, 0.80), 3, 12, ROCK_DEEP);
    b.setMat(.wood);
    for ([_]f32{ -0.78, 0.78 }) |px| {
        b.addCapsule(v3(px, 1.0, 0), v3(px + rng.signed() * 0.05, 2.05, rng.signed() * 0.05), 0.085, 0.07, 6, TIMBER_DK);
    }
    b.addCapsule(v3(-0.9, 2.02, 0), v3(0.9, 2.06, 0), 0.075, 0.075, 6, TIMBER); // the windlass barrel
    b.addBox(v3(0.95, 2.04, 0.16), v3(0.03, 0, 0), v3(0, 0.02, 0.18), v3(0, 0.16, 0), TIMBER_DK); // crank handle
    b.addCapsule(v3(0.2, 2.0, 0), v3(0.2, 1.25, 0.02), 0.018, 0.018, 4, BARK_DK); // rope
    // The bucket, on the coping.
    b.addCylinder(v3(0.55, 1.10, 0.55), v3(0.55, 1.38, 0.55), 0.17, 0.19, 8, TIMBER);
    b.addDome(v3(0.55, 1.10, 0.55), v3(0, -1, 0), 0.17, 8, TIMBER_DK);
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 1.3, rng.signed() * 1.3, 0.8);
    // ON the coping, not off the edge of it: at radius 0.98 this patch was a green flap hanging in
    // the air beside the well.
    b.addBlob(v3(0.62, 1.10, -0.36), v3(0.19, 0.05, 0.16), 3, 6, MOSS_SOFT);
    return b.toModel(shader);
}

// A wayside SHRINE: a small gabled stone housing on a plinth holding a worn figure, with candle
// stubs burning on its step. Carries a light — the smallest fire in the world.
pub fn shrineMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2102);
    b.setMat(.stone);
    b.addCube(v3(0, 0.14, 0), v3(1.5, 0.28, 1.2), STONE_DK); // plinth
    b.addCube(v3(0, 0.36, 0), v3(1.2, 0.18, 0.95), STONE);
    // The housing: two side walls, a back, and a gable — open to the front (local −Z).
    for ([_]f32{ -0.44, 0.44 }) |sx| b.addCube(v3(sx, 1.05, 0.06), v3(0.22, 1.2, 0.82), STONE);
    b.addCube(v3(0, 1.05, 0.42), v3(1.1, 1.2, 0.2), STONE_DK);
    // THE CAP is a real PITCHED GABLE — two sloped slabs to a ridge stone — over one eaves band
    // that throws a shadow line across the front. It was four clean rectangles shrinking as they
    // went up: a stepped ziggurat, machine-square, and the tidiest object in the world sitting on
    // top of a wayside shrine.
    b.addBox(v3(0, 1.735, 0.06), v3(0.70, 0.015, 0), v3(0, 0.045, 0), v3(0, 0, 0.50), STONE_DK);
    for ([_]f32{ -1, 1 }) |sgn| {
        b.addBox(
            v3(sgn * 0.35, 1.97, 0.06),
            // DOWN the pitch, outward. The sign is the whole roof: a slab that rises as it leaves the
            // centre makes a VALLEY, and two of them make the butterfly the first cut of this read as.
            v3(sgn * 0.35, -0.195, 0),
            v3(0, 0.065, 0), // slab thickness
            v3(0, 0, 0.47 * rng.range(0.96, 1.04)),
            if (sgn < 0) STONE else STONE_LT, // one pitch takes the low sun, the other doesn't
        );
    }
    b.addBox(v3(rng.signed() * 0.02, 2.20, 0.06), v3(0.125, 0.008, 0), v3(0, 0.05, 0), v3(0, 0, 0.45), STONE_LT); // ridge stone, straddling the joint
    // …and it has not come through the years whole: a corner of the eaves has slipped, and the
    // piece that broke off it lies on the step below.
    b.addBox(v3(-0.58, 1.72, -0.30), v3(0.15, -0.05, 0), v3(0, 0.04, 0), v3(0, 0, 0.13), STONE_DK);
    b.addBlob(v3(0.40, 0.47, -0.30), v3(0.13, 0.05, 0.10), 3, 5, STONE_LT);
    lichenInto(&b, &rng, v3(-0.20, 2.02, -0.02), v3(0.15, 0.05, 0.13), 3); // where the rain sits on the pitch
    b.setMat(.stone);
    // The figure inside: a small hooded form, face lost.
    b.addCylinder(v3(0, 0.46, 0.06), v3(rng.signed() * 0.03, 1.24, 0.06), 0.26, 0.17, 8, STONE_LT);
    b.addBlob(v3(0, 1.34, 0.06), v3(0.17, 0.19, 0.17), 4, 7, STONE);
    b.setMat(.plain);
    // Candle stubs on the step, guttering.
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const x = -0.34 + @as(f32, @floatFromInt(i)) * 0.34;
        const h = rng.range(0.09, 0.17);
        b.setMat(.cloth);
        b.addCylinder(v3(x, 0.45, -0.34), v3(x, 0.45 + h, -0.34), 0.035, 0.032, 6, PETAL_WHITE);
        // A candle flame is a teardrop and already the right shape — it only wanted to MOVE. The
        // datum is this candle's OWN wick (the stubs are unequal), so each of the three gutters on
        // its own tiny amplitude instead of the three swaying together off a shared height.
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

// A post LANTERN: an iron cage on a hooked pole, lit. Marks a road at a distance the way a torch
// can't — it stands above the grass.
pub fn lanternMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2103);
    b.setMat(.stone);
    b.addBlob(v3(0, 0.12, 0), v3(0.34, 0.13, 0.32), 3, 6, STONE_DK); // a stone pad at the foot
    b.setMat(.wood);
    b.addCapsule(v3(0, 0.06, 0), v3(rng.signed() * 0.08, 2.78, rng.signed() * 0.08), 0.075, 0.055, 6, TIMBER_DK);
    b.setMat(.steel);
    b.addCapsule(v3(0.02, 2.76, 0), v3(0.30, 2.86, 0), 0.03, 0.024, 5, IRON); // the hook arm
    b.addCapsule(v3(0.30, 2.86, 0), v3(0.30, 2.74, 0), 0.02, 0.02, 4, IRON);
    // The cage: four uprights + two hoops + a little roof.
    var u: i32 = 0;
    while (u < 4) : (u += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(u)) / 4.0 + 0.4;
        b.addCapsule(v3(0.30 + mathx.cosf(a) * 0.12, 2.44, mathx.sinf(a) * 0.12), v3(0.30 + mathx.cosf(a) * 0.12, 2.74, mathx.sinf(a) * 0.12), 0.017, 0.017, 4, IRON);
    }
    b.addCylinder(v3(0.30, 2.42, 0), v3(0.30, 2.47, 0), 0.14, 0.14, 8, IRON);
    b.addCylinder(v3(0.30, 2.74, 0), v3(0.30, 2.80, 0), 0.16, 0.11, 8, IRON);
    b.addDome(v3(0.30, 2.80, 0), v3(0, 1, 0), 0.11, 8, IRON);
    // `.flame` + setAnimY, NOT flameInto: this flame is the right shape already and it lives inside
    // a 0.11 cage, where five tapered spires would poke straight through the ironwork. What it was
    // missing is the MOTION — on `.plain` it was the one fire in the world standing perfectly still.
    // Its height above the wick is small, so the shared writhe moves it proportionally little, which
    // is exactly what a sheltered flame in a housing does.
    b.setMat(.flame);
    b.setAnimY(2.48); // the wick, not the prop's base — the datum the writhe measures from
    b.addBlob(v3(0.30, 2.56, 0), v3(0.075, 0.10, 0.075), 4, 7, FLAME_CORE);
    b.addBlob(v3(0.30, 2.66, 0), v3(0.045, 0.07, 0.045), 3, 6, FLAME_MID);
    b.setAnimY(0);
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 0.5, rng.signed() * 0.5, 0.75);
    return b.toModel(shader);
}

// A FENCE run: split posts driven at uneven depths with two rails, several posts leaning or gone.
pub fn fenceMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2104);
    b.setMat(.wood);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const x = -3.0 + @as(f32, @floatFromInt(i)) * 1.0;
        if (rng.float() < 0.14) continue; // a post pulled out or rotted away
        const h = rng.range(0.85, 1.22);
        b.addCapsule(v3(x, 0, rng.signed() * 0.05), v3(x + rng.signed() * 0.16, h, rng.signed() * 0.14), 0.075, 0.06, 5, TIMBER_DK);
    }
    // Rails, in broken lengths rather than one continuous run.
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

// BARRELS and crates, stacked and spilled. Staves are individual, so the barrels read as coopered
// rather than as cylinders. Casks come BOTH WAYS — headed (full, still worth keeping) and stood
// OPEN and empty (owner's favourite): a store yard where every cask is sealed reads as a delivery
// that nobody has broken into yet.
pub fn barrelsMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2105);
    const barrel = struct {
        fn go(bb: *Builder, r: *mathx.Rng, cx: f32, cz: f32, tilt: f32, h: f32, open: bool) void {
            bb.setMat(.wood);
            // The BODY is solid and bellied — two tapered drums meeting at the bulge. The old
            // build was ten free-standing staves with daylight between them: a picket ring,
            // not a cask. Same rule as packed stone: the staves are only the FACING.
            bb.addCylinder(v3(cx, 0.01, cz), v3(cx + tilt * 0.5, h * 0.5, cz), 0.26, 0.30, 10, TIMBER_DK);
            bb.addCylinder(v3(cx + tilt * 0.5, h * 0.5, cz), v3(cx + tilt, h, cz), 0.30, 0.26, 10, TIMBER_DK);
            // Stave seams ride the body, proud at the chimes and sunk at the belly. On an OPEN cask they
            // stop well under the rim: run to the top and their capsule ends stand up through the chime
            // hoop as a crown of separate tabs — the picket ring, back again by the other door.
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
                bb.addBlob(v3(cx + tilt, h - 0.02, cz), v3(0.27, 0.035, 0.27), 3, 10, TIMBER_DK); // the head — CAPPED (an open cylinder end reads hollow)
                return;
            }
            // EMPTY: no head, and you see down INTO it. The cavity is a dark drum seen from
            // OUTSIDE — its near wall faces away and is culled, so the eye lands on the far wall
            // and the floor below it, which is what reads as depth. (A bare open cylinder end
            // reads as a hole in the mesh; a capped one reads as a lid.) The drum's rim sits a
            // hair proud of the body's so the two can't z-fight along the chime.
            bb.addCylinder(v3(cx + tilt * 0.42, h * 0.42, cz), v3(cx + tilt, h + 0.006, cz), 0.235, 0.256, 10, BARK_OLD);
            bb.addBlob(v3(cx + tilt * 0.42, h * 0.42, cz), v3(0.235, 0.025, 0.235), 3, 10, BARK_OLD); // the bottom head, seen from above
            bb.setMat(.steel);
            // The chime hoop sits AT the top edge, capping the stave ends. Below them and the stave
            // tops stand up as a crown of separate teeth — a picket ring again, the thing this prop
            // was rebuilt to stop reading as.
            bb.addCylinder(v3(cx + tilt, h - 0.045, cz), v3(cx + tilt, h + 0.012, cz), 0.305, 0.305, 10, RUST);
        }
    }.go;
    barrel(&b, &rng, 0, 0, 0.02, 0.82, false);
    barrel(&b, &rng, 0.62, 0.28, -0.04, 0.76, true);
    barrel(&b, &rng, -0.35, 0.66, 0.05, 0.70, true);
    // A crate, and one broken open.
    b.setMat(.wood);
    b.addCube(v3(-0.75, 0.26, -0.45), v3(0.62, 0.52, 0.58), TIMBER_DK);
    var p: i32 = 0;
    while (p < 4) : (p += 1) {
        const y = 0.08 + @as(f32, @floatFromInt(p)) * 0.14;
        b.addCube(v3(-0.75, y, -0.75), v3(0.64, 0.055, 0.03), TIMBER);
    }
    b.addBox(v3(0.55, 0.10, -0.72), v3(0.34, 0.06, 0), v3(0, 0.05, 0), v3(0, 0, 0.28), TIMBER); // a lid slid off
    b.setMat(.cloth);
    b.addBlob(v3(-0.2, 0.18, -0.9), v3(0.3, 0.16, 0.22), 3, 6, THATCH_DK); // a spilled sack
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 1.1, rng.signed() * 1.1, 0.7);
    return b.toModel(shader);
}

// A WOODPILE: split billets stacked in courses under a sagging cover, with a few fallen off.
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
                // Billet lengths WANDER (±0.15, not ±0.06): a stack of identical sausages is
                // the too-regular fail. A few show a pale sawn END disc.
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
    // The sagging cover, in two overlapped uneven swells — one 6-sided pancake read as a
    // hexagonal tabletop hovering over the stack.
    b.addBlob(v3(-0.12, 1.08, 0.06), v3(0.68, 0.09, 0.62), 4, 9, THATCH_DK);
    b.addBlob(v3(0.30, 1.05, -0.14), v3(0.44, 0.07, 0.40), 4, 9, THATCH_DK);
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 1.4, rng.signed() * 1.4, 0.75);
    return b.toModel(shader);
}

// BONES: a scatter of ribs, long bones and a skull, half sunk in the turf. Souls games put these
// where something went wrong, so they read as a WARNING more than as decoration.
pub fn bonesMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2107);
    b.setMat(.plain);
    // A skull: cranium plus a jaw slipped off it.
    b.addBlob(v3(0, 0.14, 0), v3(0.16, 0.15, 0.19), 4, 7, BONE);
    b.addBlob(v3(0, 0.09, -0.17), v3(0.11, 0.07, 0.09), 3, 6, BONE);
    b.addBlob(v3(0.14, 0.05, -0.22), v3(0.09, 0.04, 0.10), 3, 5, BONE);
    // Ribs, curved: two capsules each.
    var r: i32 = 0;
    while (r < 6) : (r += 1) {
        const z = 0.34 + @as(f32, @floatFromInt(r)) * 0.13;
        const sgn: f32 = if (@mod(r, 2) == 0) 1 else -1;
        const w = rng.range(0.18, 0.28);
        b.addCapsule(v3(0, 0.06, z), v3(sgn * w, 0.13, z + rng.signed() * 0.04), 0.022, 0.018, 4, BONE);
        b.addCapsule(v3(sgn * w, 0.13, z), v3(sgn * w * 1.35, 0.05, z + rng.signed() * 0.06), 0.018, 0.014, 4, BONE);
    }
    b.addCapsule(v3(0, 0.05, 0.28), v3(0, 0.05, 1.12), 0.035, 0.028, 5, BONE); // spine
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

// A stone SARCOPHAGUS with its lid shoved aside — whatever was in it isn't now.
pub fn sarcophagusMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2108);
    b.setMat(.stone);
    b.addCube(v3(0, 0.10, 0), v3(2.1, 0.20, 1.05), STONE_DK); // base slab
    // The chest: four walls, so the inside is a real void you can see into.
    b.addCube(v3(0, 0.52, 0.44), v3(1.9, 0.64, 0.16), STONE);
    b.addCube(v3(0, 0.52, -0.44), v3(1.9, 0.64, 0.16), STONE);
    b.addCube(v3(0.87, 0.52, 0), v3(0.16, 0.64, 0.75), STONE);
    b.addCube(v3(-0.87, 0.52, 0), v3(0.16, 0.64, 0.75), STONE);
    // Debris fill most of the way up the chest — with only a floor at the bottom the opening
    // under the canted lid was a pitch-black void with hard triangle edges, reading as a hole
    // in the mesh rather than an opened grave.
    b.addCube(v3(0, 0.36, 0), v3(1.6, 0.34, 0.6), MORTAR);
    // The lid, dragged off and canted against the side — MARBLE: it carries the effigy, and a
    // dressed lid over a rubble-stone chest is the kingdom's money showing.
    b.setMat(.marble);
    b.addBox(v3(-0.35, 0.92, 0.30), v3(1.0, 0.10, 0), v3(-0.04, 0.11, 0), v3(0, 0, 0.5), MARBLE);
    b.addBox(v3(1.35, 0.30, 0.5), v3(0.55, 0.42, 0), v3(0.16, 0.20, 0), v3(0, 0, 0.42), MARBLE_DK); // …a broken end on the ground
    b.setMat(.stone);
    // A worn effigy line down the lid, and moss where the rain sits.
    b.addBox(v3(-0.35, 1.00, 0.30), v3(0.7, 0.07, 0), v3(0, 0.03, 0), v3(0, 0, 0.10), STONE_MOSS);
    b.setMat(.plant);
    b.addBlob(v3(rng.signed() * 0.6, 0.98, -0.2), v3(0.35, 0.07, 0.22), 3, 6, MOSS_SOFT);
    tuftInto(&b, &rng, rng.range(-1.6, 1.6), rng.signed() * 1.0, 0.8);
    return b.toModel(shader);
}

// A fragment of STONE STAIR going nowhere — four or five treads and the stub of the wall that
// carried them. Cheap ruin storytelling: it implies a storey that is gone.
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
        if (i == 5 and rng.float() < 0.5) continue; // the top tread often gone
        b.addBox(
            v3(x, y, rng.signed() * 0.03),
            v3(0.28, rng.signed() * 0.012, 0),
            v3(0, 0.12, 0),
            v3(0, 0, w * 0.5),
            if (rng.float() < 0.28) STONE_LT else if (rng.float() < 0.5) STONE_MOSS else STONE,
        );
    }
    // The stub wall the flight was built against.
    b.addCube(v3(-0.2, 0.55, 0.86), v3(2.6, 1.1, 0.34), STONE_DK);
    b.addCube(v3(0.9, 1.25, 0.86), v3(0.7, 0.4, 0.30), STONE); // a surviving upstand
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

// A GIBBET: an iron cage on a leaning post, hanging empty, chain and all. Grim wayside furniture —
// the thing you see before you understand what the road is for.
pub fn gibbetMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2110);
    b.setMat(.stone);
    b.addBlob(v3(0, 0.14, 0), v3(0.44, 0.15, 0.40), 3, 6, STONE_DK);
    b.setMat(.wood);
    const lean = rng.signed() * 0.22;
    b.addCapsule(v3(0, 0.05, 0), v3(lean, 3.85, lean * 0.4), 0.115, 0.085, 6, TIMBER_DK); // post
    b.addCapsule(v3(lean, 3.78, lean * 0.4), v3(lean + 1.05, 3.92, lean * 0.4), 0.075, 0.055, 5, TIMBER_DK); // arm
    b.addCapsule(v3(lean + 0.1, 3.30, lean * 0.4), v3(lean + 0.62, 3.86, lean * 0.4), 0.05, 0.04, 4, TIMBER_DK); // brace
    b.setMat(.steel);
    // Chain: a short run of alternating links, hanging straight.
    var k: i32 = 0;
    while (k < 4) : (k += 1) {
        const y = 3.86 - @as(f32, @floatFromInt(k)) * 0.11;
        b.addCylinder(v3(lean + 1.0, y, 0), v3(lean + 1.0, y - 0.09, 0), 0.035, 0.035, 5, IRON);
    }
    // The cage: uprights bowed outward, three hoops, and a spiked base.
    const cx = lean + 1.0;
    const top: f32 = 3.42;
    var u: i32 = 0;
    while (u < 6) : (u += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(u)) / 6.0;
        // IRON bars, one or two gone rusty — all-RUST rods under the warm key read as pale
        // timber, and the whole cage read as a wooden birdcage.
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

// A CAIRN: field stones stacked by hand, largest at the bottom, leaning as they rise. A waymarker
// somebody built, which is why it is the one pile of rocks in the world that looks deliberate.
