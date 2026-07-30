// ── PROPS: THE RUINED KINGDOM ── the fallen avenue's own set: columns whole and snapped, ruin
// blocks, the gate arch, wall runs, graves, planted swords, the grace ember, the horizon towers and
// the colossal gate, banners, sentinel statues, rubble. What they share is DRESSED MASONRY gone
// over: same stone, same weathering moves (see propart.zig), same centuries.
//
// One kind is one `pub fn <name>Mesh(shader) rl.Model`, named in props.zig's INFO table and nowhere
// else. Nothing here is called from anywhere but that table.
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
const ASH = art.ASH;
const ASH_DK = art.ASH_DK;
const ASH_LT = art.ASH_LT;
const BARK_DK = art.BARK_DK;
const BONE = art.BONE;
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

// ── the original ruined-kingdom set ────────────────────────────────────────────────────

pub fn pillarWhole(shader: rl.Shader) rl.Model {
    return pillarMesh(shader, false);
}
pub fn pillarBroken(shader: rl.Shader) rl.Model {
    return pillarMesh(shader, true);
}

// A stone column — the most-seen prop in the world (the avenue is a colonnade of them, and it
// is where you start). Stepped plinth, torus base, a shaft of stacked DRUMS with FLUTES up
// them, necking ring, flared capital, and three centuries of weather over the lot.
//
// THE FLUTES ARE THE FIDELITY. A smooth 5 m cylinder is the biggest plain surface on the
// avenue, and the great trees' bark ridges taught the rule: a big smooth mass needs FORM BREAKS
// or it reads as plastic however dark you author it. Sixteen arrises cost ~130 triangles and
// turn a grey pipe into a column. Drums settle off-axis, joints step, the whole thing leans a
// degree off plumb — a machined column is the one thing a ruin can't be.
pub fn pillarMesh(shader: rl.Shader, broken: bool) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (broken) 4801 else 4802);
    b.setMat(.stone);

    // The column has SETTLED: everything above the plinth drifts along this lean.
    const leanX = rng.signed() * 0.035;
    const leanZ = rng.signed() * 0.030;
    const shaftTop: f32 = if (broken) rng.range(2.35, 2.95) else 4.98;
    const axisAt = struct { // the shaft's centre at height y, following the lean
        fn p(y: f32, lx: f32, lz: f32) rl.Vector3 {
            return v3(lx * y, y, lz * y);
        }
    }.p;
    const radAt = struct { // …and its radius there (a real column tapers — entasis)
        fn r(y: f32) f32 {
            return 0.62 - 0.115 * mathx.clampF(y / 4.98, 0, 1);
        }
    }.r;

    // ── the base ── two stepped slabs of rough footing STONE, then the column proper in MARBLE.
    // Dressed-and-glossed against the rubble wall behind it is the point of having two stones.
    b.addBox(v3(0, 0.18, 0), v3(0.85, rng.signed() * 0.012, 0.03), v3(0, 0.18, 0), v3(0.04, 0, 0.85), STONE_DK);
    b.addBox(v3(rng.signed() * 0.04, 0.46, rng.signed() * 0.04), v3(0.72, rng.signed() * 0.014, 0.02), v3(0, 0.12, 0), v3(0.03, 0, 0.72), STONE);
    b.setMat(.marble);
    b.addCylinder(v3(0, 0.56, 0), v3(0, 0.72, 0), 0.74, 0.66, 10, MARBLE_LT); // torus base
    b.addCylinder(v3(0, 0.70, 0), v3(0, 0.80, 0), 0.66, 0.63, 10, MARBLE_DK); // the fillet above it

    // ── the shaft ── four drums, each with its own radius jog and lateral shift, so the joints
    // step and catch the low sun. A flush stack of identical cylinders reads as one pipe.
    const nd: i32 = if (broken) 2 else 4;
    var d: i32 = 0;
    while (d < nd) : (d += 1) {
        const y0 = 0.78 + (shaftTop - 0.78) * @as(f32, @floatFromInt(d)) / @as(f32, @floatFromInt(nd));
        const y1 = 0.78 + (shaftTop - 0.78) * @as(f32, @floatFromInt(d + 1)) / @as(f32, @floatFromInt(nd));
        const off = v3(rng.signed() * 0.022, 0, rng.signed() * 0.022); // the drum has slipped
        const p0 = axisAt(y0, leanX, leanZ);
        const p1 = axisAt(y1, leanX, leanZ);
        // TWELVE sides, not nine. The shaft is the biggest curved surface in the world and the one
        // you stand next to; at nine the flats were wide enough that an arris landing mid-facet
        // read as a strip glued on rather than as an edge of the stone itself.
        b.addCylinder(
            v3(p0.x + off.x, y0, p0.z + off.z),
            v3(p1.x + off.x, y1, p1.z + off.z),
            radAt(y0) * rng.range(0.99, 1.02),
            radAt(y1) * rng.range(0.98, 1.01),
            12,
            if (@mod(d, 2) == 0) MARBLE else MARBLE_LT,
        );
        // The bed joint: a thin proud ring of mortar-line stone at every drum seam. 1.015, not
        // 1.03 — a joint is a line you notice, not a collar standing off the shaft.
        if (d > 0) b.addCylinder(v3(p0.x + off.x, y0 - 0.02, p0.z + off.z), v3(p0.x + off.x, y0 + 0.02, p0.z + off.z), radAt(y0) * 1.015, radAt(y0) * 1.015, 12, MARBLE_DK);
    }
    // FLUTING: sixteen arrises up the shaft, following its taper and lean; a fifth spalled away.
    // Keep them the SAME STONE as the drum. Tinting a ridge lighter turns fluting into a
    // BARCODE — the eye stops reading a round column and reads stripes painted on a cylinder.
    // The ridge's own shading is the whole effect; the colour must not help.
    //
    // THEY ARE ARRISES, NOT RODS. Real fluting is a groove cut INTO the shaft and the arris is the
    // sliver of original surface left between two of them, so the relief is a few millimetres of a
    // 60 cm shaft. Approximating it with proud cylinders inverts that, and at the old numbers the
    // inversion showed: a 4-SIDED rod is a square bar, and at radius 0.040 sitting on 0.985 of the
    // radius it stood ~11% of the shaft's own radius clear of the 9-gon's flats — sixteen strips
    // visibly stuck ON the column instead of cut into it. Now SUNK to 0.955 so most of the rod is
    // buried and only the arris breaks the surface, thinner, and 5-sided so it has no square corner
    // to catch the light along its whole length.
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
        // THE FRACTURE: a snapped column does not end flat. Half a dozen angular shards of
        // unequal height standing out of the break — but STANDING OUT is the part that was
        // overdone: at up to 0.34 tall and skewed ±0.07 on both in-plane axes they were a crown of
        // spikes, and the eye read them before it read the column. A break is a JAGGED PLANE, so
        // the shards keep their unequal heights and random bearings and lose two thirds of their
        // rise and half their tilt.
        const c = axisAt(shaftTop, leanX, leanZ);
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
        // The drums it shed. Both run along a WORLD axis on purpose: a cylinder is capless, so
        // an open end shows its culled interior (you see straight THROUGH it), and the only
        // cheap flat cap is an axis-flattened blob. Instance yaw varies their bearing.
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
        // ── the capital ── necking ring, echinus flare, abacus. The thin slab under the flare
        // closes the cone's open underside (cylinders are capless; from below you would see
        // straight through to striped interior backfaces).
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
        // A carved band worn nearly smooth under the echinus, and the corner the abacus lost.
        b.addCylinder(v3(c.x, shaftTop - 0.32, c.z), v3(c.x, shaftTop - 0.24, c.z), 0.545, 0.545, 9, MARBLE_LT);
        b.addBlob(v3(c.x + rng.signed() * 0.9, shaftTop + 0.40, c.z + rng.signed() * 0.9), v3(0.20, 0.10, 0.18), 3, 5, MARBLE_DK);
        // …and where it landed, at the foot.
        b.addBlob(v3(rng.signed() * 1.2, 0.16, rng.signed() * 1.2), v3(0.26, 0.15, 0.22), 3, 5, MARBLE);
    }

    // ── the weather ── a crack up the lowest drum, spalled chips shed round the plinth, a moss
    // streak down the shaded side, and grass coming up through the joints of the base.
    crackInto(&b, v3(mathx.cosf(0.7) * 0.60, 0.95, mathx.sinf(0.7) * 0.60), v3(0.10, 0.99, 0.02), v3(-mathx.sinf(0.7), 0, mathx.cosf(0.7)), rng.range(0.5, 1.1), 0.022, 0.03);
    chipsInto(&b, &rng, 0, 0, 1.45, 0.09, 0.24, 6);
    const ma = rng.angle();
    lichenInto(&b, &rng, v3(mathx.cosf(ma) * 0.60, rng.range(0.9, 1.6), mathx.sinf(ma) * 0.60), v3(0.16, 0.42, 0.16), 4);
    lichenInto(&b, &rng, v3(rng.signed() * 0.5, 0.75, rng.signed() * 0.5), v3(0.34, 0.02, 0.30), 3);
    tuftInto(&b, &rng, rng.signed() * 1.1, rng.signed() * 1.1, 0.75);
    tuftInto(&b, &rng, rng.signed() * 1.3, rng.signed() * 1.3, 0.6);
    return b.toModel(shader);
}

// A fallen ENTABLATURE BLOCK — dressed stone off a cornice, settled into the turf at a list.
// Twenty-six are scattered through the city, so it earns real detail: a moulded end (the
// profile it was cut with), tooled faces, a split, and the corner it lost on landing.
//
// Built SKEW on purpose. An axis-aligned cube half-sunk in grass is the most artificial thing
// a ruin can contain, because nothing that FELL lands square.
pub fn blockMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4803);
    b.setMat(.marble);
    // The mass, listing along both axes and sunk a little at one end.
    const tipX = rng.signed() * 0.11;
    const tipZ = rng.signed() * 0.09;
    b.addBox(
        v3(0, 0.48, 0),
        v3(1.10, tipX, 0.02),
        v3(-tipX * 0.4, 0.50, tipZ * 0.4),
        v3(0.03, tipZ, 0.80),
        MARBLE,
    );
    // The MOULDING: a projecting fillet and cyma along one end — what says "off a building"
    // rather than "a rock".
    for ([_]f32{ 0.86, 0.98 }) |t| {
        b.addBox(
            v3(t * 1.02, 0.48 + tipX * t * 1.02, 0),
            v3(0.06, tipX, 0),
            v3(0, 0.44 - (t - 0.86) * 1.4, tipZ * 0.4),
            v3(0, 0, 0.86 - (t - 0.86) * 1.2),
            if (t < 0.9) MARBLE_LT else MARBLE_DK,
        );
    }
    // TOOL MARKS: claw-chisel runs across the top face — they catch the raking sun and stop a
    // 2 m flat reading as poured concrete.
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
    // The top is ERODED, not flat: three low swells of weathered stone riding it.
    var e: i32 = 0;
    while (e < 3) : (e += 1) {
        const u = rng.range(-0.85, 0.85);
        b.addBlob(v3(u, 0.98 + tipX * u, rng.signed() * 0.5), v3(rng.range(0.28, 0.5), 0.055, rng.range(0.22, 0.4)), 3, 6, if (rng.float() < 0.4) MARBLE_LT else MARBLE);
    }
    // The stub of the NEXT course, still bedded on it: says this was a stack, not a boulder.
    b.addBox(
        v3(-0.55, 1.32, rng.signed() * 0.16),
        v3(0.36, tipX * 1.2, 0.03),
        v3(-tipX * 0.5, 0.34, 0),
        v3(0.02, 0, 0.50),
        MARBLE_DK,
    );
    b.addBlob(v3(-0.42, 1.62, rng.signed() * 0.2), v3(0.22, 0.10, 0.20), 3, 6, MARBLE_LT); // …weathered off at the break
    // The SPLIT: it cracked across the short way when it hit, and the far part has slipped.
    const sx = rng.range(-0.35, 0.35);
    crackInto(&b, v3(sx, 0.985, -0.80), v3(0.05, 0.0, 0.999), v3(1, 0, 0), 1.60, 0.024, 0.05);
    b.addBox(
        v3(sx + 0.62, 0.34, 0.05),
        v3(0.44, tipX * 1.8, 0),
        v3(-0.10, 0.34, 0),
        v3(0, 0, 0.74),
        MARBLE_DK,
    ); // the slipped half, dropped and canted
    // The corner it lost on landing, lying beside it.
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

// THE GATE ARCH — the threshold you run through on the avenue. A REAL arch: coursed piers
// carrying an impost, and a ring of wedge-cut VOUSSOIRS springing from one to the other with a
// keystone. Two boxes and a lintel is a door frame; an arch is the one piece of stonework whose
// point is that the geometry holds itself up, and you can see whether it does.
//
// BROKEN on the near haunch — three voussoirs gone, the stone lying under the gap. A complete
// arch reads as maintained, and nothing here is.
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
    // THE RING. a runs 0 (left springing) → pi (right); radial is (−cos a, sin a, 0) and the
    // tangent is (sin a, cos a, 0). Get that pair wrong and it's the watchtower's skewed-masonry
    // bug again — addBox accepts a non-perpendicular triple and never complains.
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
    // The SOFFIT closes the ring's inner face — look up through the arch and you see dressed
    // stone, not the gaps between wedges.
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
    // The stones the haunch shed, lying in the grass under the gap.
    b.setMat(.marble);
    b.addBox(v3(-2.05, 0.26, rng.range(-0.9, 0.9)), v3(0.34, rng.signed() * 0.14, 0.03), v3(rng.signed() * 0.12, 0.24, 0), v3(0, 0, 0.42), MARBLE);
    b.addBox(v3(-1.35, 0.20, rng.range(-1.1, 0.6)), v3(0.28, rng.signed() * 0.10, 0.02), v3(rng.signed() * 0.1, 0.19, 0), v3(0, 0, 0.36), MARBLE_DK);
    // Above the crown: the stub of the parapet that once ran across, most of it gone.
    b.setMat(.stone);
    // SPANDREL stubs first — the fill that carried the parapet over the ring's shoulders.
    // Without them the slab's ends hang over daylight where the ring curves away below.
    b.addCube(v3(1.30, spring + px + ringR - 0.26, -0.02), v3(0.56, 0.52, 0.56), STONE);
    b.addCube(v3(-0.76, spring + px + ringR - 0.18, 0.03), v3(0.50, 0.44, 0.60), STONE_DK);
    b.addBox(v3(0.3, spring + px + ringR + 0.20, 0), v3(1.35, rng.signed() * 0.02, 0), v3(0, 0.22, 0), v3(0, 0, 0.62), STONE_DK);
    b.addCube(v3(-0.5, spring + px + ringR + 0.56, 0.02), v3(0.62, 0.44, 0.86), STONE);
    b.addCube(v3(1.15, spring + px + ringR + 0.40, -0.04), v3(0.5, 0.26, 0.72), STONE_DK);
    // The weather: lichen in the shade under the arch, a crack up the near pier, chips and
    // grass at both feet.
    for ([_]f32{ -px, px }) |x| {
        crackInto(&b, v3(x + 0.53, rng.range(0.6, 1.2), rng.signed() * 0.3), v3(rng.signed() * 0.18, 0.98, 0.05), v3(0, 0, 1), rng.range(0.8, 1.6), 0.020, 0.03);
        chipsInto(&b, &rng, x, 0, 1.5, 0.08, 0.22, 5);
        lichenInto(&b, &rng, v3(x, rng.range(0.5, 1.3), 0.56), v3(0.30, 0.30, 0.02), 3);
        tuftInto(&b, &rng, x + rng.signed() * 1.1, rng.signed() * 1.2, 0.8);
    }
    // The damp soffit: lichen ON the ring's inner face, half-sunk into the stone — the old
    // version floated a patch mid-opening. Both spots sit clear of the collapsed haunch
    // (t 0.23..0.37), flanking the keystone where the drip line runs.
    for ([_]f32{ 0.47, 0.62 }) |t| {
        const a = std.math.pi * t;
        const rIn = px - 0.30;
        lichenInto(&b, &rng, v3(-mathx.cosf(a) * rIn, spring + mathx.sinf(a) * rIn, rng.signed() * 0.22), v3(0.15, 0.10, 0.15), 3);
    }
    return b.toModel(shader);
}

// A ruined WALL run — the city perimeter and the downs' boundaries, so more of these are drawn
// than of anything else built by hand. Laid course by course over a packed core, in THREE spans
// of different height so the top line BREAKS: one shoulder-high with a surviving merlon, one
// worn to waist, one collapsed to a stub. A wall with a level top is a fence.
pub fn wallMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4805);
    const th: f32 = 0.40; // half-thickness
    // Three spans along local X, overlapping so no seam of daylight shows where runs meet.
    courseInto(&b, &rng, -3.55, 0, -0.85, 0, .{ .thick = th, .height = 2.55, .courses = 8, .blockW = 0.62, .crumbleTop = 0.52 });
    courseInto(&b, &rng, -1.05, 0.02, 1.95, -0.02, .{ .thick = th, .height = 3.00, .courses = 9, .blockW = 0.66, .crumbleTop = 0.42 });
    courseInto(&b, &rng, 1.75, 0, 3.55, 0, .{ .thick = th * 1.06, .height = 1.35, .courses = 4, .blockW = 0.58, .crumbleTop = 0.55 });
    // THROUGH-STONES: the long blocks tying the two faces together, proud of the facing every
    // few courses. Real walls show them; models never do.
    var ts: i32 = 0;
    while (ts < 5) : (ts += 1) {
        const x = rng.range(-3.3, 3.2);
        const y = rng.range(0.35, 1.9);
        b.setMat(.stone);
        b.addBox(v3(x, y, 0), v3(rng.range(0.30, 0.46), rng.signed() * 0.02, 0), v3(0, rng.range(0.13, 0.2), 0), v3(0, 0, th * 1.18), if (rng.float() < 0.4) STONE_LT else STONE_DK);
    }
    // A surviving MERLON on the tall span, and the stub of the one beside it.
    b.setMat(.stone);
    b.addBox(v3(0.35, 3.28, 0), v3(0.52, rng.signed() * 0.02, 0), v3(0, 0.32, 0), v3(0, 0, th * 0.9), STONE);
    b.addBox(v3(1.45, 3.08, rng.signed() * 0.04), v3(0.34, rng.signed() * 0.03, 0), v3(0, 0.12, 0), v3(0, 0, th * 0.86), STONE_DK);
    // A PUTLOG HOLE — the socket a scaffold beam sat in. One dark rectangle, and the wall
    // acquires a construction history.
    b.addCube(v3(-2.05, 1.62, 0), v3(0.20, 0.17, th * 1.6), IRON);
    crackInto(&b, v3(-0.35, 0.15, th * 1.02), v3(rng.signed() * 0.3, 0.95, 0), v3(1, 0, 0), rng.range(1.0, 2.0), 0.024, 0.04);
    // Shed stone heaped along both faces — also what hides the line where masonry meets terrain.
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
    // The first round-topped stone's placement, kept so the face lichen below has a real
    // stone to grow on (it used to float at head height over an empty plot).
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
        // The earth mound each one stands in, settled and grassed over.
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
                b.addBlob(v3(x + tipX * ay - 0.12, ay - 0.02, z + tipZ * ay), v3(0.055, 0.075, 0.06), 3, 5, STONE_DK); // …and the stub of the lost one
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

// A SWORD left standing in the earth, blade down — a grave marker for somebody nobody buried.
// Nine are strewn across the battlefield, and they are the only STEEL you meet outside a fight,
// so they carry the shader's blinding metal glint and want detail worthy of it: a fullered
// blade nicked and rusting, a wrapped grip you can count the turns of, a drooping crossguard
// with one quillon snapped, heaped earth and a cairn stone at its foot.
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
    // Two tapers, wide at the shoulder to the buried point, with a FULLER down the flat. That
    // single dark stripe is what turns a steel plank into a sword.
    b.addBox(off(d, p1, p2, 0.30, 0, 0), v3(p1.x * 0.062, p1.y * 0.062, p1.z * 0.062), at(d, 0.30), v3(p2.x * 0.013, p2.y * 0.013, p2.z * 0.013), STEEL);
    b.addBox(off(d, p1, p2, 0.72, 0, 0), v3(p1.x * 0.052, p1.y * 0.052, p1.z * 0.052), at(d, 0.16), v3(p2.x * 0.011, p2.y * 0.011, p2.z * 0.011), STEEL);
    for ([_]f32{ 1, -1 }) |sgn| {
        b.addBox(off(d, p1, p2, 0.50, 0, sgn * 0.012), v3(p1.x * 0.020, p1.y * 0.020, p1.z * 0.020), at(d, 0.38), v3(p2.x * 0.004 * sgn, p2.y * 0.004 * sgn, p2.z * 0.004 * sgn), IRON);
    }
    // NICKS in the edge, and rust creeping up from the soil — it was used, then left out.
    var n: i32 = 0;
    while (n < 4) : (n += 1) {
        const t = rng.range(0.16, 0.86);
        const sgn: f32 = if (@mod(n, 2) == 0) 1 else -1;
        b.addBlob(off(d, p1, p2, t, sgn * 0.058, 0), v3(0.016, 0.022, 0.016), 3, 5, if (rng.float() < 0.5) RUST else IRON);
    }
    b.addBox(off(d, p1, p2, 0.13, 0, 0), v3(p1.x * 0.058, p1.y * 0.058, p1.z * 0.058), at(d, 0.11), v3(p2.x * 0.0125, p2.y * 0.0125, p2.z * 0.0125), RUST);
    // CROSSGUARD: drooping toward the point the way a real cross does, one quillon snapped.
    b.addBox(off(d, p1, p2, 0.94, 0.06, 0), v3(p1.x * 0.145, p1.y * 0.145 - 0.030, p1.z * 0.145), at(d, 0.028), v3(p2.x * 0.030, p2.y * 0.030, p2.z * 0.030), STEEL);
    b.addBox(off(d, p1, p2, 0.94, -0.055, 0), v3(p1.x * 0.055, p1.y * 0.055 + 0.018, p1.z * 0.055), at(d, 0.026), v3(p2.x * 0.028, p2.y * 0.028, p2.z * 0.028), RUST);
    b.addBlob(off(d, p1, p2, 0.945, 0, 0), v3(0.036, 0.040, 0.036), 3, 6, STEEL); // the écusson at its centre
    // GRIP: seven turns of leather cord over the tang — a smooth cylinder reads as plastic.
    b.setMat(.leather);
    var w: i32 = 0;
    while (w < 7) : (w += 1) {
        const t = 0.975 + @as(f32, @floatFromInt(w)) * 0.032;
        b.addCylinder(at(d, t), at(d, t + 0.026), 0.030 + rng.range(0, 0.004), 0.029, 6, if (@mod(w, 2) == 0) IRON else BARK_DK);
    }
    b.setMat(.steel);
    b.addBlob(at(d, 1.235), v3(0.058, 0.052, 0.058), 4, 7, BRASS); // pommel, a disc not a cube
    b.addCylinder(at(d, 1.255), at(d, 1.275), 0.020, 0.016, 6, BRASS); // …and its peened tang button
    // The ground it went into: heaved earth, a cairn stone set beside it, grass grown back.
    b.setMat(.stone);
    b.addBlob(v3(0.02, 0.055, 0.02), v3(0.30, 0.075, 0.27), 3, 6, STONE_MOSS);
    b.addBlob(v3(rng.range(0.22, 0.40), 0.10, rng.range(-0.34, -0.16)), v3(0.13, 0.11, 0.11), 3, 5, STONE_DK);
    chipsInto(&b, &rng, 0, 0, 0.55, 0.04, 0.09, 3);
    tuftInto(&b, &rng, rng.signed() * 0.28, rng.signed() * 0.28, 0.72);
    tuftInto(&b, &rng, rng.signed() * 0.42, rng.signed() * 0.42, 0.55);
    return b.toModel(shader);
}

// The grace ember: an iron bowl on a stone foot, banked gold coals, and a thin rising
// wisp — the coals and wisp ride the EMISSIVE vertex-alpha channel, so they burn through
// shadow and haze like a beacon. It also carries a real point light (INFO), so the ground
// around it now catches the glow instead of the ember floating in its own brightness.
pub fn graceMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4809);
    // THE SITE. A grace is a place people came BACK to, so it gets the one piece of tended
    // ground in the world: set kerbstones and a worn marble pave. Nothing else in this file is
    // deliberate — that contrast is the whole read.
    b.setMat(.stone);
    // …and the ring is HAND-LAID, not machined. Eleven stones at even spacing, matched radii and a
    // matched stand-off came out as a COG: a gear tooth every 33 degrees round a pale disc. The
    // wabi-sabi law covers this exactly — the cure is a wide size band, a wide distance band and
    // real angular jitter, not fewer stones.
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
    // THE ASH BED filling the ring — a shallow pale mound, raked flatter in the middle where
    // people have knelt at it. Sunk at its rim so it reads as lying IN the ring of stones rather
    // than as a disc set on top of them.
    b.setMat(.plain);
    b.addBlob(v3(0, 0.055, 0), v3(0.82, 0.070, 0.82), 3, 12, ASH_DK);
    b.addBlob(v3(rng.signed() * 0.06, 0.095, rng.signed() * 0.06), v3(0.66, 0.070, 0.64), 3, 11, ASH);
    b.addBlob(v3(rng.signed() * 0.10, 0.125, rng.signed() * 0.10), v3(0.40, 0.055, 0.38), 3, 9, ASH_LT);
    // …drifts and scorch, so the bed is not one smooth pat of grey.
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
    // BONES in the ash. Whoever kindled it, and everyone who tried before them — the one piece of
    // narrative the prop carries, and the reason it is a bonfire and not a fire pit.
    var bn: i32 = 0;
    while (bn < 6) : (bn += 1) {
        const a = rng.angle();
        const dd = rng.range(0.20, 0.62);
        const ln = rng.range(0.10, 0.22);
        const a2 = a + rng.signed() * 1.4;
        b.addCapsule(
            v3(mathx.cosf(a) * dd, 0.135, mathx.sinf(a) * dd),
            v3(mathx.cosf(a) * dd + mathx.cosf(a2) * ln, 0.135 + rng.range(0, 0.05), mathx.sinf(a) * dd + mathx.sinf(a2) * ln),
            rng.range(0.016, 0.028),
            rng.range(0.014, 0.024),
            4,
            BONE,
        );
    }
    b.addBlob(v3(rng.signed() * 0.4, 0.17, rng.signed() * 0.4), v3(0.075, 0.065, 0.080), 3, 6, BONE); // a skull, half sunk
    // ── THE COILED SWORD ── the whole silhouette, and the one thing that names this a bonfire
    // rather than a brazier: a straight blade driven POINT-DOWN into the ash, hilt up, its blade
    // TWISTED down its length. The twist is not decoration — a straight flat blade at this size
    // reads as a stick from ten metres, and the coil is what catches the sun differently every few
    // centimetres so the eye reads a sword.
    //
    // Canted a few degrees off plumb, because nothing organic here is machined (wabi-sabi) and
    // because a sword somebody DROVE into the ground would not land true.
    b.setMat(.steel);
    const tilt = rng.signed() * 0.05; // radians off vertical, carried up the blade
    const BLADE_TOP: f32 = 1.12;
    const SEGS: i32 = 10;
    var sg: i32 = 0;
    while (sg < SEGS) : (sg += 1) {
        const t0 = @as(f32, @floatFromInt(sg)) / @as(f32, @floatFromInt(SEGS));
        const y = 0.09 + t0 * (BLADE_TOP - 0.09);
        // BROAD, and only half-twisted. At 0.07 half-width over a metre of height the blade was a
        // 4 cm sliver — the twist had no facet wide enough to catch the light differently, so the
        // whole thing read as a thin white SPIKE and the coil was invisible. A coiled sword is a
        // big flat blade; widen it and the twist does its job.
        const a = t0 * 2.6 + 0.35; // ~150 deg from point to shoulder — fewer, wider facets
        const hw = mathx.lerpF(0.030, 0.115, t0); // narrow at the point, broad at the shoulder
        const th = mathx.lerpF(0.011, 0.021, t0); // …and thicker edge-to-edge as it widens
        // ax = the flat (twisting), ay = up the blade, az = edge-to-edge. Perpendicular BY
        // CONSTRUCTION — addBox happily builds a skewed parallelepiped out of a sloppy triple.
        b.addBox(
            v3(tilt * y * 3.0, y, tilt * y * 1.2),
            v3(mathx.cosf(a) * hw, 0, mathx.sinf(a) * hw),
            v3(0, (BLADE_TOP - 0.09) / @as(f32, @floatFromInt(SEGS)) * 0.66, 0),
            v3(-mathx.sinf(a) * th, 0, mathx.cosf(a) * th),
            // DARK IRON with steel only as a glint. Mostly-STEEL came back near-white under the
            // hot key and the blade lost its edges against the sky (the big-mass albedo rule again,
            // on a small mass that happens to be the brightest thing in the prop).
            if (@mod(sg, 2) == 0) IRON else if (rng.float() < 0.35) STEEL else RUST,
        );
    }
    // The HILT: crossguard, bound grip, pommel. From behind, the hilt is the whole read.
    const hx = tilt * BLADE_TOP * 3.0;
    const hz = tilt * BLADE_TOP * 1.2;
    b.addBox(v3(hx, BLADE_TOP + 0.03, hz), v3(0.185, 0, 0.02), v3(0, 0.020, 0), v3(-0.012, 0, 0.032), IRON); // quillons
    b.addBlob(v3(hx + 0.185, BLADE_TOP + 0.03, hz), v3(0.030, 0.030, 0.030), 3, 5, RUST); // …a knop at each end
    b.addBlob(v3(hx - 0.185, BLADE_TOP + 0.03, hz), v3(0.028, 0.028, 0.028), 3, 5, RUST);
    b.setMat(.leather);
    b.addCylinder(v3(hx, BLADE_TOP + 0.05, hz), v3(hx + tilt * 0.1, BLADE_TOP + 0.20, hz), 0.030, 0.028, 6, TIMBER_DK); // bound grip
    b.setMat(.steel);
    b.addBlob(v3(hx + tilt * 0.12, BLADE_TOP + 0.235, hz), v3(0.046, 0.040, 0.046), 3, 6, RUST); // pommel
    // …and THE FIRE at its base, low and broad, licking up the blade. Through `flameInto`, so it
    // gets the vertex writhe and the same tongue vocabulary as every other fire in the world.
    // …and kept LOW. At scale 1.05 the tongues reached 0.64 and swallowed the lower two thirds of
    // the blade: the fire won the silhouette the sword is supposed to own, which is the whole point
    // of a bonfire being a sword and not a campfire. Round its base, not up its length.
    flameInto(&b, &rng, rng.signed() * 0.04, 0.13, rng.signed() * 0.04, 0.70);
    flameInto(&b, &rng, rng.signed() * 0.20, 0.11, rng.signed() * 0.20, 0.44);
    b.setMat(.plain);
    // The rising WISP + drifting motes: the bonfire's tell from across the plain, kept from the
    // grace it replaces because that read was the one thing about it that worked.
    //
    // SHORTER AND THINNER than the grace's were. WISP is strongly emissive (alpha 120), and a
    // 1.6 m tapered cylinder of it stood BEHIND the sword and read as a white spike taller than
    // the blade — it was winning the silhouette the sword is supposed to own. At this length it
    // goes back to being heat-shimmer coming off the fire.
    b.addCylinder(v3(0, 0.60, 0), v3(rng.signed() * 0.05, 1.02, rng.signed() * 0.05), 0.018, 0.002, 5, WISP);
    b.addCylinder(v3(0.07, 0.58, -0.05), v3(0.15, 0.86, -0.11), 0.014, 0.002, 5, WISP);
    var m: i32 = 0;
    while (m < 9) : (m += 1) {
        const t = @as(f32, @floatFromInt(m)) / 9.0;
        const a = t * 7.4 + rng.signed() * 0.5;
        const dd = 0.08 + t * rng.range(0.22, 0.46);
        const sz = 0.024 * (1.0 - 0.55 * t);
        b.addBlob(v3(mathx.cosf(a) * dd, 0.70 + t * 0.86 + rng.signed() * 0.06, mathx.sinf(a) * dd), v3(sz, sz, sz), 3, 5, WISP);
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 1.05, rng.signed() * 1.05, 0.55);
    lichenInto(&b, &rng, v3(rng.signed() * 0.6, 0.07, rng.signed() * 0.6), v3(0.24, 0.02, 0.22), 3);
    return b.toModel(shader);
}

// A colossal broken KEEP for the horizon. Eight stand around the world's edge at `view = FAR`,
// so they are on screen almost always and from almost everywhere.
//
// At that distance you cannot see a single block, so the fidelity must survive two hundred
// metres of haze: horizontal COURSE BANDING (the only cue that reads "built" and not
// "outcrop"), a battered plinth, BUTTRESSES breaking the flat faces into light and shade, a
// corbelled parapet, and a genuinely broken crown. Cheap, too — a course is one box.
pub fn towerMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4810);
    b.setMat(.stone);
    const W: f32 = 6.4;
    // The BATTERED PLINTH — a keep that meets the turf at a right angle reads as pasted on.
    b.addBox(v3(0, 0.55, 0), v3(W * 0.60, rng.signed() * 0.01, 0), v3(0, 0.55, 0), v3(0, 0, W * 0.60), STONE_DK);
    b.addBox(v3(0, 1.20, 0), v3(W * 0.545, rng.signed() * 0.01, 0), v3(0, 0.30, 0), v3(0, 0, W * 0.545), STONE);
    // The two masses, laid as courses over `courseStack`'s solid core.
    const yMid = courseStack(&b, &rng, 0, 1.42, 0, W, W, 0.86, 8, 0.06);
    b.addBox(v3(0.15, yMid + 0.16, -0.1), v3(W * 0.56, rng.signed() * 0.012, 0), v3(0, 0.16, 0), v3(0, 0, W * 0.56), STONE_LT); // string course
    const yTop = courseStack(&b, &rng, 0.3, yMid + 0.32, -0.2, W * 0.85, W * 0.85, 0.82, 7, 0.07);
    // BUTTRESSES: one clasping strip up the middle of each face, stopping at a weathered set-off.
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
    // ARROW SLITS: dark recesses punched through the faces. At range they are the only thing
    // giving the mass a SCALE — without them it could be six metres or sixty.
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
    // The CORBEL TABLE under the parapet — the one silhouette detail that says "castle" from
    // two hundred metres.
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
    // THE CROWN, genuinely broken: merlons missing in runs along two sides, standing in others,
    // and one corner sheared clean off.
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
    // The jagged shards the sheared corner left standing.
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
    // TALUS heaped against one flank, big blocks nearest the wall — it hides the line where the
    // keep meets flat terrain.
    var t: i32 = 0;
    while (t < 12) : (t += 1) {
        const a = rng.range(0.2, 1.7);
        const dd = rng.range(W * 0.55, W * 0.55 + 3.4);
        const rr = rng.range(0.35, 1.5) * (1.0 - 0.32 * (dd - W * 0.55) / 3.4);
        b.addBlob(v3(mathx.cosf(a) * dd, rr * 0.55, mathx.sinf(a) * dd), v3(rr, rr * 0.7, rr * rng.range(0.8, 1.25)), 3, 6, if (rng.float() < 0.3) STONE_MOSS else if (rng.float() < 0.55) STONE_LT else STONE_DK);
    }
    // Scrub on the ledges — a green line along the set-offs says nobody has climbed it in years.
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

// THE COLOSSAL HORIZON GATE — what the avenue points at, and the landmark the whole opening
// view is composed around, so it gets more than anything else in the file.
//
// Twin coursed towers, and between them a REAL arched portal: sixteen wedge-cut voussoirs on a
// five-metre radius with a keystone, the stumps of a portcullis still hanging in it, the
// corbelled fighting platform above. Its crest is broken open — a gate that still shuts is a
// gate somebody is holding.
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
    // THE CURTAIN between the towers, with the portal cut through it — coursed, so its face
    // bands like the towers do.
    courseInto(&b, &rng, -TX + 1.0, 0, TX - 1.0, 0, .{ .thick = DEP, .height = 15.6, .courses = 17, .blockW = 1.15, .crumbleTop = 0.40, .crumble = 0.03, .gapLo = -R - 0.3, .gapHi = R + 0.3, .sillY = -1, .headY = SPR + R + 0.7 });
    // THE VOUSSOIRS. Radial is (−cos a, sin a, 0), tangent (sin a, cos a, 0). Pass a
    // non-perpendicular pair and addBox silently builds skewed blocks with daylight between —
    // the watchtower's lesson, and at this scale it costs you the whole landmark.
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
        // …and the soffit band closing the ring's underside.
        b.addBox(
            v3(-ca * (R - 0.28), SPR + sa * (R - 0.28), 0),
            v3(sa * half * 1.2, ca * half * 1.2, 0),
            v3(-ca * 0.30, sa * 0.30, 0),
            v3(0, 0, DEP * 0.97),
            STONE_DK,
        );
    }
    // THE PORTCULLIS, dropped and rusted into place — four bars left of it, snapped short.
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
    // The CORBEL TABLE and machicolations under the fighting platform.
    var cb: i32 = 0;
    while (cb < 13) : (cb += 1) {
        if (rng.float() < 0.18) continue;
        const px = (@as(f32, @floatFromInt(cb)) - 6.0) * 1.05;
        for ([_]f32{ -1, 1 }) |sgn| {
            b.addBox(v3(px, 13.55, sgn * DEP * 1.06), v3(0.34, rng.signed() * 0.03, 0), v3(0, 0.28, 0), v3(0, 0, 0.34), STONE_DK);
        }
    }
    b.addBox(v3(0, 14.25, 0), v3(TX - 0.6, rng.signed() * 0.02, 0), v3(0, 0.55, 0), v3(0, 0, DEP * 1.14), STONE); // the platform slab
    // THE BROKEN CREST: merlons across the span, a run gone on the near side, and the crack
    // that took them running down into the parapet.
    var m: i32 = 0;
    while (m < 11) : (m += 1) {
        if (m >= 3 and m <= 5) continue;
        if (rng.float() < 0.24) continue;
        const px = (@as(f32, @floatFromInt(m)) - 5.0) * 1.24;
        const h = rng.range(0.7, 1.5);
        b.addBox(v3(px, 14.8 + h * 0.5, rng.signed() * 0.06), v3(0.46, rng.signed() * 0.03, 0), v3(0, h * 0.5, 0), v3(0, 0, DEP * 0.92), if (rng.float() < 0.3) STONE_LT else STONE_DK);
    }
    crackInto(&b, v3(-1.9, 14.7, DEP * 1.16), v3(rng.signed() * 0.35, -0.94, 0), v3(1, 0, 0), 2.6, 0.09, 0.14);
    // The masonry the crest shed, heaped in the portal's mouth and against the towers' feet.
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

// A leaning war banner: bent pole, crossarm, and two ragged strips of faded crimson —
// the fallen army's colors, matching the hero's cape.
pub fn bannerMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4812);
    const tilt = v3(rng.range(0.16, 0.34), 0, rng.signed() * 0.16);
    const top = v3(tilt.x, 3.18, tilt.z);
    b.setMat(.wood);
    b.addCapsule(v3(0, 0, 0), top, 0.058, 0.036, 6, BARK_DK); // the pole
    // BINDING: turns of cord where the crossarm is lashed on.
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
    // THE STANDARD, in ribbons: eleven strips to their own torn-off lengths, all drifting the
    // same way — it has hung in one prevailing wind a long time. The ragged hem IS the prop;
    // two flat quads read as a For Sale sign.
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
        // …and its frayed end, thinner and paler where the sun has eaten the dye out.
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

// A weathered headless SENTINEL — marble on a plinth, one arm lost, the neck snapped and the
// head lying face-down in the grass at its feet. It watched the road once.
//
// The fidelity here is DRAPERY. A robe modelled as a bare tapered cylinder is a traffic cone
// and no albedo noise fixes it: cloth reads through the vertical folds that catch and lose the
// light, so the robe gets eleven plus a mantle. And the plinth gets a carved inscription band,
// because what every ruined statue has is a name nobody can read any more.
pub fn statueMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4813);
    b.setMat(.stone);
    b.addBox(v3(0, 0.16, 0), v3(0.80, rng.signed() * 0.01, 0.02), v3(0, 0.16, 0), v3(0.02, 0, 0.80), STONE_DK); // plinth
    b.addBox(v3(rng.signed() * 0.02, 0.46, rng.signed() * 0.02), v3(0.68, rng.signed() * 0.012, 0.02), v3(0, 0.14, 0), v3(0.02, 0, 0.68), STONE);
    b.addBlob(v3(rng.range(0.35, 0.62), 0.16, rng.range(-0.7, -0.4)), v3(0.22, 0.16, 0.20), 3, 5, STONE_MOSS); // a spalled plinth corner
    // The INSCRIPTION: three shallow carved lines round the plinth face, worn illegible.
    var ins: i32 = 0;
    while (ins < 3) : (ins += 1) {
        b.addBox(v3(rng.signed() * 0.10, 0.24 + @as(f32, @floatFromInt(ins)) * 0.075, -0.79), v3(rng.range(0.28, 0.52), 0, 0), v3(0, 0.016, 0), v3(0, 0, 0.02), STONE_DK);
    }
    b.setMat(.marble);
    b.addBox(v3(0, 0.62, 0), v3(0.56, rng.signed() * 0.01, 0), v3(0, 0.08, 0), v3(0, 0, 0.56), MARBLE_LT); // the statue's own base
    // The figure: a robe narrowing to the shoulders, LEANING a couple of degrees off true.
    const sway = v3(rng.signed() * 0.06, 0, rng.signed() * 0.05);
    const shoulderY: f32 = 2.36;
    b.addCapsule(v3(0, 0.66, 0), v3(sway.x, shoulderY, sway.z), 0.46, 0.29, 9, MARBLE);
    // DRAPERY: folds the height of the robe, each its own depth and drift, gathering to one
    // side the way cloth hangs off a contrapposto hip.
    var f: i32 = 0;
    while (f < 11) : (f += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(f)) / 11.0 + rng.signed() * 0.18;
        const y0 = rng.range(0.68, 0.92);
        const y1 = rng.range(1.9, 2.32);
        const r0 = 0.455 - 0.16 * (y0 - 0.66) / 1.7;
        const r1 = 0.455 - 0.16 * (y1 - 0.66) / 1.7;
        b.addCapsule(
            v3(mathx.cosf(a) * r0, y0, mathx.sinf(a) * r0),
            v3(sway.x * 0.8 + mathx.cosf(a + rng.signed() * 0.25) * r1 * 0.72, y1, sway.z * 0.8 + mathx.sinf(a + rng.signed() * 0.25) * r1 * 0.72),
            rng.range(0.040, 0.072),
            rng.range(0.022, 0.048),
            4,
            if (rng.float() < 0.32) MARBLE_LT else if (rng.float() < 0.55) MARBLE_DK else MARBLE,
        );
    }
    // The hem, flared where it pools on the base.
    b.addCylinder(v3(0, 0.64, 0), v3(0, 0.84, 0), 0.52, 0.455, 10, MARBLE_DK);
    // A MANTLE over the shoulders, and the shoulders themselves.
    b.addBlob(v3(sway.x, shoulderY - 0.10, sway.z), v3(0.40, 0.20, 0.30), 4, 8, MARBLE_LT);
    b.addBox(v3(sway.x, shoulderY + 0.06, sway.z), v3(0.38, rng.signed() * 0.02, 0), v3(0, 0.11, 0), v3(0, 0, 0.21), MARBLE);
    // The SNAPPED NECK — a jagged stub, not a clean cut.
    b.addCylinder(v3(sway.x, shoulderY + 0.14, sway.z), v3(sway.x + 0.03, shoulderY + 0.26, sway.z + 0.02), 0.115, 0.095, 7, MARBLE_DK);
    var jn: i32 = 0;
    while (jn < 4) : (jn += 1) {
        const a = rng.angle();
        b.addBlob(v3(sway.x + mathx.cosf(a) * 0.06, shoulderY + 0.28 + rng.range(0, 0.05), sway.z + mathx.sinf(a) * 0.06), v3(0.045, 0.035, 0.045), 3, 5, MARBLE_LT);
    }
    // THE SURVIVING ARM, reaching; the other lost at the shoulder, its break left rough.
    const ea = v3(sway.x + 0.38, shoulderY - 0.28, sway.z + 0.16);
    b.addCapsule(v3(sway.x + 0.26, shoulderY - 0.06, sway.z + 0.04), ea, 0.105, 0.078, 6, MARBLE);
    b.addCapsule(ea, v3(sway.x + 0.60, shoulderY - 0.46, sway.z + 0.34), 0.078, 0.055, 6, MARBLE);
    b.addBlob(v3(sway.x + 0.64, shoulderY - 0.52, sway.z + 0.38), v3(0.075, 0.055, 0.070), 3, 6, MARBLE_LT); // the hand
    b.addBlob(v3(sway.x - 0.30, shoulderY - 0.10, sway.z), v3(0.11, 0.10, 0.11), 3, 6, MARBLE_DK); // the lost arm's break
    // THE HEAD, lying face-down in the grass where it came off. This is the prop.
    const hx = rng.range(-1.05, -0.62);
    const hz = rng.range(-0.5, 0.75);
    b.addBlob(v3(hx, 0.20, hz), v3(0.21, 0.19, 0.24), 4, 8, MARBLE);
    b.addBlob(v3(hx + 0.06, 0.13, hz - 0.16), v3(0.13, 0.10, 0.11), 3, 6, MARBLE_DK); // the jaw, half in the turf
    b.addBlob(v3(hx - 0.12, 0.30, hz + 0.10), v3(0.13, 0.09, 0.14), 3, 6, MARBLE_LT); // the crown of it, catching the sun
    // The forearm it also dropped, and the rubble round the plinth.
    b.addCapsule(v3(rng.range(0.5, 0.9), 0.09, rng.range(0.2, 0.8)), v3(rng.range(0.9, 1.3), 0.07, rng.range(-0.1, 0.5)), 0.075, 0.055, 5, MARBLE_DK);
    chipsInto(&b, &rng, 0, 0, 1.45, 0.07, 0.18, 6);
    // The weather: lichen up the shaded side of the robe and over the plinth, grass at the foot.
    const la = rng.angle();
    lichenInto(&b, &rng, v3(mathx.cosf(la) * 0.40, rng.range(1.0, 1.9), mathx.sinf(la) * 0.40), v3(0.13, 0.42, 0.13), 4);
    lichenInto(&b, &rng, v3(rng.signed() * 0.4, 0.61, rng.signed() * 0.4), v3(0.36, 0.02, 0.32), 4);
    lichenInto(&b, &rng, v3(hx, 0.32, hz), v3(0.14, 0.02, 0.14), 2); // …and over the fallen head
    tuftInto(&b, &rng, rng.range(-1.3, 1.3), rng.range(-1.2, 1.2), 0.85);
    tuftInto(&b, &rng, rng.range(-1.3, 1.3), rng.range(-1.2, 1.2), 0.65);
    return b.toModel(shader);
}

// Low RUBBLE scatter — what a building leaves on the ground. Mixed on purpose: blocks worn
// shapeless, a couple of fresh-broken pieces that still have edges, a drum shard, a fragment of
// carved moulding, grit between. A heap of same-size anything reads as a texture swatch.
pub fn rubbleMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4814);
    b.setMat(.stone);
    // The big rounded pieces, half-sunk to varying depths.
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
    // Two angular pieces that broke recently enough to still have corners on them. Each gets a
    // real TIPPED orthonormal frame (yaw + a hard lean about it) and sits low — the old ones
    // stood square and pale, and a dressed block sitting flat reads as delivered, not fallen.
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
    // A DRUM SHARD and a scrap of carved moulding — the pieces that say this came off something
    // built rather than off a hill.
    b.setMat(.marble);
    b.addCylinder(v3(-0.15, 0.15, 0.62), v3(0.42, 0.13, 0.92), 0.17, 0.15, 7, MARBLE);
    b.addBlob(v3(-0.15, 0.15, 0.62), v3(0.03, 0.17, 0.17), 3, 7, MARBLE_DK);
    b.addBox(v3(rng.range(-0.9, -0.4), 0.055, rng.range(-0.8, 0.2)), v3(0.20, rng.signed() * 0.05, 0.02), v3(0, 0.05, 0), v3(0, 0, 0.13), MARBLE_LT);
    // Grit and chips filling between them, so the ground under the heap isn't bare turf.
    chipsInto(&b, &rng, 0, 0, 1.0, 0.035, 0.09, 9);
    lichenInto(&b, &rng, v3(rng.signed() * 0.4, 0.14, rng.signed() * 0.4), v3(0.26, 0.02, 0.24), 3);
    tuftInto(&b, &rng, rng.signed() * 0.9, rng.signed() * 0.9, 0.6);
    tuftInto(&b, &rng, rng.signed() * 1.0, rng.signed() * 1.0, 0.45);
    return b.toModel(shader);
}

