// ── PROPS: ROCK ── living rock, not cut masonry: colder, greyer and never square. The six cliff
// variants that ring the world (one shared builder, six characters), boulders, field stones, the
// leaning monolith, cairns, outcrops, scree.
//
// The cliffs are the only props whose SHAPE is load-bearing for gameplay: they are what makes the
// movement clamp read as terrain instead of an invisible wall, so only the inward face is detailed.
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

// ── ROCK ── living rock, not cut masonry: colder, greyer, and never square.

// A CLIFF segment — the world's edge, so the movement clamp reads as terrain instead of as an
// invisible wall in open grass. Only the INWARD face is ever seen, so all the detail lives on
// local −Z.
//
// The bulk is ROUNDED (big faceted blobs forming an undulating ridge) with ANGULAR strata slabs
// laid on the face. That split is the whole trick, and getting it wrong is instructive: the
// first version built the mass itself out of stepped rectangular courses, and a row of those
// along the horizon read as a BRUTALIST SKYLINE — grey boxes with flat tops and hard vertical
// corners, exactly like distant tower blocks. Rock silhouettes undulate; buildings crenellate.
// Rounded mass gives the silhouette, the slabs give the surface its bedding.
// THE THREE VARIANTS MUST ACTUALLY DIFFER. They used to differ only by seed and height, which is
// the same rock three times: at ±15% per-instance scale and ±7° of yaw, a wall built from three
// near-identical meshes reads UNIFORM however smooth each one is — the failure at the other end
// from the spikes. So each carries a CHARACTER, and because `mix=cliff,cliff2,cliff3` picks per
// segment, the wall alternates between three kinds of rock in random order.
//
// Variation belongs in the MASS, not in protruding detail (see RELIEF IS SUBTLE). Body widths,
// how far a body sits back, how faceted it is, how deep the clefts between them run — all of that
// is silhouette and surface at long wavelength, and none of it makes a spike.
pub const CliffKind = struct {
    H: f32,
    /// Body half-width band. WIDE ranges are what stop the face reading as a row of matched
    /// columns; the bodies still have to overlap their neighbours, so the floor stays generous.
    wLo: f32,
    wHi: f32,
    /// How far bodies wander in and out of the face. This is the CLEFT dial: a body set back
    /// leaves a shadowed vertical channel between its neighbours, which is the negative space a
    /// rock face has and a smooth mass does not.
    cleft: f32,
    /// 0 = rounded and weathered, 1 = angular and freshly broken. Drives the facet counts, so one
    /// variant is chunky rock and another is worn smooth.
    blocky: f32,
    /// Bedding bands across the face, and how much their relief VARIES. Varying the relief is what
    /// reads as strata; a fixed relief on every band reads as corduroy.
    bands: i32,
    /// OVERGROWTH. Curtains of creeper pouring down the face, moss packed into the bedding seams,
    /// and a fuller green crest. 0 = bare rock. This is the one variation that is not stone: a
    /// green-shot face beside a bare one is the biggest read the wall has, because it changes the
    /// HUE and not just the silhouette.
    ivy: f32 = 0,
    /// COLLAPSE. How far the face has lost a piece of itself: a gully torn down through the mass,
    /// pale freshly-broken rock along its edges, and the missing volume lying in an apron at the
    /// foot. 0 = intact.
    broken: f32 = 0,
};

const CLIFF_ROUND = CliffKind{ .H = 13.5, .wLo = 2.9, .wHi = 5.0, .cleft = 0.55, .blocky = 0.15, .bands = 7 };
const CLIFF_BLOCKY = CliffKind{ .H = 12.2, .wLo = 2.4, .wHi = 4.2, .cleft = 1.15, .blocky = 0.85, .bands = 10 };
const CLIFF_RAGGED = CliffKind{ .H = 14.6, .wLo = 3.2, .wHi = 5.6, .cleft = 0.85, .blocky = 0.5, .bands = 8 };
// A damp, weathered face that the wood has got into: rounded rock under creeper.
const CLIFF_IVIED = CliffKind{ .H = 13.0, .wLo = 3.0, .wHi = 5.2, .cleft = 0.70, .blocky = 0.22, .bands = 8, .ivy = 1.0 };
// The one that came down: angular, freshly broken, LOWER than its neighbours (it lost its crest)
// and standing in its own rubble. Few bands, because half the strata are on the floor.
const CLIFF_SHATTERED = CliffKind{ .H = 11.6, .wLo = 2.2, .wHi = 4.6, .cleft = 1.35, .blocky = 0.90, .bands = 5, .broken = 1.0 };
// An OLD collapse: the scar has softened and gone green. Both dials, neither at full — the point
// of it is that it reads as time passing, not as a third kind of damage.
const CLIFF_OVERGROWN = CliffKind{ .H = 12.6, .wLo = 2.7, .wHi = 4.8, .cleft = 0.95, .blocky = 0.45, .bands = 7, .ivy = 0.8, .broken = 0.55 };

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

/// One rock body of a cliff segment — an ellipsoid, as `addBlob` builds it.
pub const CliffBody = struct { x: f32, y: f32, z: f32, rx: f32, ry: f32, rz: f32 };

/// The FRONTMOST rock surface at (x, y): the smallest z any of the segment's bodies reaches there,
/// or null when no body covers the point at all — in which case nothing gets placed, which is the
/// whole point. This is what lets the creeper follow the rock's curve and the collapse scar sit ON
/// the face instead of both being hung on a guessed depth plane.
///
/// `q <= 0.04` skips a body the point is outside of, and also the very rim of one, where the
/// ellipsoid is edge-on: the surface there is nearly parallel to the view and anything anchored to
/// it reads as sticking out sideways.
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

/// …the same query for something with a FOOTPRINT rather than a point: the REARMOST surface across
/// a grid over (halfW, halfH), so a flat pad or plate is seated behind the shallowest rock it spans
/// instead of behind its own centre. A wide one seated on its centre leaves the curving face at its
/// own ends and comes out as a shelf with a lit top face — the horizontal version of the mistake a
/// fixed depth plane makes vertically. The centre must be on the rock; samples that fall off it are
/// ignored rather than rejecting the whole thing, or the flanks lose their dressing entirely.
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

pub fn cliffMesh(shader: rl.Shader, seed: u64, k: CliffKind) rl.Model {
    const H = k.H;
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    // The COLLAPSE and OVERGROWTH blocks below draw from their own stream. A shared one would have
    // meant every draw they make shifts `rng` for everything after it, so bolting them on would
    // silently re-roll the three original variants — the same locality argument the map's
    // per-op seeds are built on, one scale down.
    var frng = mathx.Rng.init(seed ^ 0x5C1FF00D);
    b.setMat(.stone);
    // THE MASS: five overlapping rock bodies along local X. Their crest follows a smooth
    // (not random) ridge curve, so neighbouring segments in the ring still line up into a
    // continuous escarpment rather than a sawtooth.
    const NM = 5;
    // THE REAL SUMMIT of each body, recorded as it is built. The crest furniture used to be placed
    // off `hgt` — the height the body was ASKED for — which stopped describing the summit the moment
    // the shoulder's own height began to vary: caps then landed anywhere from buried in the rock to
    // a flat plate hanging off it, and the scrub floated. Anything that sits ON the rock has to be
    // told where the rock actually ended.
    const Summit = struct { x: f32, z: f32, y: f32, rx: f32, rz: f32 };
    var top: [NM]Summit = undefined;
    // EVERY BODY, recorded the same way and for the same reason one step further on: the OVERGROWTH
    // and COLLAPSE blocks below have to know where the face IS, not just where its summits are. The
    // mass is a stack of ellipsoids, so it curves away at its top and its flanks; anything hung on
    // a fixed z plane clings to the rock at mid-height and pokes out into thin air above it. The
    // bands and ribs get away with a fixed depth only because they are meant to be MOSTLY BURIED
    // and to show wherever the surface happens to be shallow — a runner that crosses the whole
    // height of the face has no such licence.
    var bodies: [NM * 2]CliffBody = undefined;
    var nbody: usize = 0;
    var m: i32 = 0;
    while (m < NM) : (m += 1) {
        const u = @as(f32, @floatFromInt(m)) / @as(f32, NM - 1); // 0..1 across the segment
        const cx = (u * 2.0 - 1.0) * 5.2;
        // A shallow arch across the segment plus a small wobble: high in the middle, lower at
        // the shoulders, so segments read as one ridge line running along.
        // Nearly FLAT across the segment (0.93..1.00). The first version arched 20% over each
        // segment, and because every segment is the same mesh repeated every 8 m along the ring,
        // that arch tiled into a row of regular TEETH along the horizon. The undulation has to
        // come from the per-instance scale, whose wavelength is the whole wall.
        // Per-body height wander, on TOP of the near-flat arch. Irregular heights across the
        // segment are safe where an ARCH is not: an arch is a symmetric shape and repeats into
        // regular teeth, whereas unequal shoulders just read as broken rock.
        const hgt = H * (0.93 + 0.07 * mathx.sinf(u * std.math.pi)) * rng.range(0.88, 1.12);
        // Bodies are WIDE relative to their spacing (they span ±9 over a ±5.2 layout), so a
        // segment's mass runs well past its own footprint and interpenetrates its neighbours in
        // the ring. Narrower bodies left a V-shaped notch of sky between every pair of segments,
        // and the wall read as a row of separate rock stacks instead of one escarpment.
        //
        // The BAND is the variant's, and it is wide on purpose: matched body widths are most of
        // what made the smoothed wall read as a row of columns.
        const rx = rng.range(k.wLo, k.wHi);
        const rz = rng.range(2.0, 3.4);
        // …and this is the CLEFT: how far this body sits in or out of the face. A body set back
        // leaves a shadowed vertical channel beside its neighbours. Negative space, which costs
        // nothing in silhouette and is what a smooth mass is missing.
        const inOut = rng.signed() * k.cleft;
        // Facet counts follow `blocky`, and they VARY body to body — a face of mixed chunky and
        // worn masses reads as rock, where one tessellation for all of them reads as one material
        // extruded. This is the variation that replaces the spikes, not a return to them.
        const sides: i32 = @intFromFloat(@round(10.0 - 4.0 * k.blocky + rng.signed() * 1.4));
        const rings: i32 = @intFromFloat(@round(6.0 - 2.0 * k.blocky + rng.signed() * 0.8));
        // Two stacked bodies per position: a broad foot and a narrower shoulder, so the profile
        // tapers the way weathered rock does instead of standing up like a column.
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
        top[@intCast(m)] = .{ .x = sx, .z = sz, .y = sy + sry, .rx = srx, .rz = srz };
    }
    const face = bodies[0..nbody];
    // BEDDING PLANES: thin wide slabs laid across the face, each stepped back and up. These are
    // what read as rock strata, and they must only ever protrude A LITTLE from the rounded mass.
    //
    // THEY USED TO STAND RIGHT OFF IT. A half-depth of 1.1 centred at z −2.2 reached past the
    // body's own front face, so every slab was a shelf hanging in the air rather than a band in
    // the rock — nine courses of them and the wall read as disheveled, a heap of slates instead of
    // an escarpment. Bedded back into the mass with a third of the stand-off and half the tilt,
    // the banding still catches the low sun (the form break a dark mass needs) without the
    // silhouette breaking up. Count and seeds unchanged: this is QUIETER, not more regular.
    // SIX broad bands, not nine narrow ones, and each BEDDED INTO the body rather than laid on it.
    // The stand-off has to be judged against the ASSEMBLED wall, not one mesh: rim segments overlap
    // heavily (a body spans ±9 over a ±5.2 layout) and a neighbour's front surface can sit a metre
    // shallower than your own, so anything that clears its own body by a little clears the
    // neighbour's by a lot. Sunk to z −1.2 with a 0.4 half-depth, a band shows where the surface
    // happens to be shallow and hides where it is deep — which is what strata do.
    // …and the RELIEF PER BAND VARIES WIDELY. That is the correction to the over-smoothed version:
    // six bands all standing the same shallow amount is corduroy, and reads as uniform even though
    // no single band is obtrusive. Most bands here are nearly flush — a tonal seam more than a
    // ledge — and one in five stands out enough to catch the sun and throw a line of shadow. The
    // CEILING is what matters for not being disheveled, not the average.
    var course: i32 = 0;
    while (course < k.bands) : (course += 1) {
        const t = @as(f32, @floatFromInt(course)) / @as(f32, @floatFromInt(k.bands - 1));
        const y = H * (0.07 + 0.86 * t) * rng.range(0.96, 1.04); // bands are not evenly spaced either
        const halfW = (5.4 - 2.0 * t) * rng.range(0.85, 1.15);
        const back = 1.1 * t; // the face rakes back as it rises
        const nb = 2 + rng.intn(3);
        // This band's own prominence: mostly a seam, occasionally a real ledge.
        const bold = rng.float() < 0.22;
        const depth: f32 = if (bold) rng.range(0.34, 0.50) else rng.range(0.16, 0.28);
        const rise: f32 = if (bold) rng.range(0.20, 0.32) else rng.range(0.09, 0.18);
        var i: i32 = 0;
        while (i < nb) : (i += 1) {
            const fi = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(nb));
            const cx = (fi * 2.0 - 1.0) * halfW;
            const w = (2.0 * halfW / @as(f32, @floatFromInt(nb))) * rng.range(0.95, 1.35); // bands RUN
            b.addBox(
                v3(cx + rng.signed() * 0.22, y, back - 1.20 + rng.signed() * 0.16),
                v3(w * 0.5, rng.signed() * 0.045, rng.signed() * 0.03), // slabs still TILT, a little
                v3(rng.signed() * 0.05, rise, rng.signed() * 0.04),
                v3(rng.signed() * 0.04, 0, depth),
                if (rng.float() < 0.24) CLIFF_LT else if (rng.float() < 0.46) CLIFF_DK else CLIFF_ROCK,
            );
        }
    }
    // FRACTURE: a few near-vertical ribs up the face, breaking the horizontal banding. Tapered
    // capsules, not boxes — a rock rib is a spine, not a pilaster.
    //
    // THESE WERE THE SPIKES. A 6-sided capsule tapering from 1.0 down to 0.2 over eleven metres is
    // a hexagonal CONE, and five of them leaning off each segment at unrelated angles is most of
    // what read as disheveled — worst on the assembled rim, where they stood out of the neighbour
    // segment's body as well as their own. Now barely tapered (a spine of even thickness, not a
    // horn), shorter, sunk to the band depth, and rounder in section.
    // Their PROMINENCE varies the same way the bands' does: mostly a crease you read as shading,
    // one or two standing far enough out to break the horizontal banding, which is their job.
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
    // TALUS: blocks shed off the face and piled at its foot — round, because a scree block that
    // has fallen 14 m is not a cube any more. This is also what hides the seam where the rock
    // meets the flat terrain.
    var t: i32 = 0;
    while (t < 16) : (t += 1) {
        const cx = rng.range(-6.8, 6.8);
        const cz = rng.range(-4.2, -1.0);
        const r = rng.range(0.35, 1.30) * (1.0 - 0.4 * @abs(cz + 1.0) / 3.2); // biggest against the wall
        b.addBlob(v3(cx, r * 0.55, cz), v3(r, r * 0.7, r * rng.range(0.8, 1.2)), 4, 6, if (rng.float() < 0.3) CLIFF_LT else CLIFF_ROCK);
    }
    // ── THE COLLAPSE (`k.broken`) ── a face that has LOST a piece of itself. There is no CSG in
    // the Builder, so the void is made the way the `cleft` dial already makes one: a near-black
    // mass sunk INTO the face where the rock should be, which reads as depth. It sits at the
    // BANDS' depth for the same reason they do — the bodies wander in and out, so a fixed z shows
    // the scar where the surface is proud and swallows it where the surface is deep.
    if (k.broken > 0) {
        const gx = frng.range(-3.0, 3.0); // where the gully comes down
        const gTop = H * frng.range(0.58, 0.84); // …and how far up it reaches
        const gW = frng.range(0.75, 1.25) * (0.6 + 0.4 * k.broken); // half-width of the GAP itself
        // THE GULLY IS MADE OF ROCK AND SHADOW, NOT OF A DARK COLOUR. A near-black albedo does not
        // read as a void on a sunlit face: the scene shader's hot key plus its gamma lift bring
        // ROCK_DEEP back as MID TAN wherever the low sun catches it square (the trap the palette
        // block at the top of this file exists for), and the first version's "dark channel" came out
        // as a stack of pale lumps climbing the face like a totem.
        //
        // So it is built the way the `cleft` dial already builds negative space: two BUTTRESSES
        // standing forward either side of the gap, and the shadow one of them throws across it IS
        // the gully. Same construction as the FRACTURE ribs above, one scale up.
        // Each buttress is a RUN OF CAPSULES following the face, not a stack of blobs: an `addBlob`
        // at three rings has a cone POLE at each end, and seven of them stacked up a rib came out
        // as a row of stalagmites — the spike failure again, wearing a different hat. Capsule ends
        // are hemispherical and consecutive segments share a radius at the joint, so the whole rib
        // is one continuous spine. Exactly the lesson the FRACTURE block above already learned.
        b.setMat(.stone);
        for ([_]f32{ 1, -1 }) |sgn| {
            // THE TWO SIDES ARE NOT A PAIR. One rib runs tall and lean, the other short and stout:
            // matched ribs either side of a gap read as a DOORWAY, which is the one thing a rockfall
            // scar must not look like — and that is exactly how the first capsule version came out.
            const rTop = gTop * frng.range(0.62, 1.0);
            const rGirth = frng.range(0.78, 1.25);
            const rSegs: i32 = 5;
            var prev: ?rl.Vector3 = null;
            var prevR: f32 = 0;
            var st: i32 = 0;
            while (st <= rSegs) : (st += 1) {
                const rt = @as(f32, @floatFromInt(st)) / @as(f32, @floatFromInt(rSegs));
                // Barely tapered overall (a spine, not a horn) but it SWELLS AND PINCHES on the way
                // up — an even-width capsule run is a pilaster, which the fracture note above
                // already says a rock rib is not.
                const rw = frng.range(0.48, 1.02) * rGirth * (1.0 - 0.34 * rt);
                const cx = gx + sgn * (gW + rw * 0.9);
                const y = rTop * (0.04 + 0.94 * rt);
                const fz = cliffFaceZ(face, cx, y) orelse {
                    prev = null;
                    continue;
                };
                // …and the LAST segment is sunk nearly flush, so the rib DIES INTO the face instead
                // of ending on a smooth dome standing clear of it (two of those read as thumbs).
                const proud: f32 = if (st == rSegs) 0.85 else 0.25;
                const p = v3(cx, y, fz + rw * proud);
                if (prev) |q| b.addCapsule(q, p, prevR, rw, 9, if (frng.float() < 0.3) CLIFF_DK else CLIFF_ROCK);
                prev = p;
                prevR = rw;
            }
        }
        // FRESH ROCK in the FLOOR of the channel: the pale scar the fall exposed, nearly flush, so
        // it is a tonal step and not another lump. Pale rock lying in the buttresses' shadow is what
        // says BROKEN rather than merely bumpy — and it has to be inside the gap, not flanking it
        // (an earlier pass put wide plates either side, and they simply covered the channel).
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
        // THE APRON: the volume that left the face, fanned out from under the gully. More of it
        // than the shared talus above, spread much further, and SORTED — the big blocks stop first
        // and the small stuff runs out. An unsorted pile reads as scenery scattered by hand.
        const nApron: i32 = @intFromFloat(@round(14.0 + 10.0 * k.broken));
        var ap: i32 = 0;
        while (ap < nApron) : (ap += 1) {
            const out = frng.float(); // 0 = against the wall, 1 = the toe of the fan
            const cx = gx + frng.signed() * (1.6 + 4.4 * out);
            const cz = -1.2 - out * frng.range(2.0, 5.4);
            const r = frng.range(0.30, 1.15) * (1.0 - 0.45 * out);
            b.addBlob(v3(cx, r * 0.5, cz), v3(r, r * frng.range(0.55, 0.80), r * frng.range(0.80, 1.25)), 4, 6, if (frng.float() < 0.28) CLIFF_LT else CLIFF_ROCK);
        }
        // …and two TOPPLED SLABS leaning on the foot, which is what a collapse leaves that a scree
        // slope does not: pieces still recognisable as pieces of the face. Sheared on purpose (the
        // vertical axis leans while the horizontal stays level) — that IS a slab come to rest.
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
    // THE CREST fills the SADDLES between the summits — it does not crown them.
    //
    // The caps were the worst thing on the cliff. Each sat on its own body, WIDER than the body it
    // sat on and only 0.35–0.70 m thick, which is a plate: five mushroom brims per segment, three
    // hundred segments of them along the skyline. And their height was placed off the height the
    // body was ASKED for, not the summit it actually reached, so they wandered between buried and
    // hanging in the air.
    //
    // Their real job was never to cap anything — it was to stop a NOTCH OF SKY opening between
    // neighbouring masses, which is what made an earlier version read as a row of separate stacks.
    // So they belong in the dips, not on the peaks: a low mass bridging each pair of summits, its
    // top kept BELOW both of them so it can never become a peak of its own or break the silhouette.
    var c: i32 = 0;
    while (c + 1 < NM) : (c += 1) {
        const a = top[@intCast(c)];
        const d = top[@intCast(c + 1)];
        const lo = @min(a.y, d.y);
        // Wide enough to reach into both summits, and seated so its crown sits just under the lower
        // of the two. Rounded (5x9) because this IS the skyline where the two masses meet.
        b.addBlob(
            v3((a.x + d.x) * 0.5, lo - H * rng.range(0.05, 0.10), (a.z + d.z) * 0.5 + rng.signed() * 0.4),
            v3(@abs(d.x - a.x) * 0.5 + @min(a.rx, d.rx) * 0.75, H * rng.range(0.07, 0.12), @min(a.rz, d.rz) * rng.range(0.85, 1.05)),
            5,
            9,
            if (rng.float() < 0.25) CLIFF_LT else CLIFF_ROCK,
        );
    }
    // SCRUB on the crest — placed against the real summit, and sitting a little BELOW it so it
    // hugs the rock. Floating a flat green disc above the skyline was the other half of what read
    // as stupid up there.
    b.setMat(.plant);
    var g: i32 = 0;
    while (g < 6) : (g += 1) {
        const s = top[@intCast(rng.intn(NM))];
        const r = rng.range(0.6, 1.3);
        b.addBlob(
            v3(s.x + rng.signed() * s.rx * 0.6, s.y - rng.range(0.10, 0.45), s.z + rng.signed() * s.rz * 0.5),
            v3(r, r * rng.range(0.45, 0.75), r * rng.range(0.7, 1.1)),
            3,
            6,
            if (rng.float() < 0.5) SCRUB_DK else STONE_MOSS,
        );
    }
    // ── THE OVERGROWTH (`k.ivy`) ── creeper down the face, moss in the seams, a fuller green
    // crest. Hung at the BANDS' depth, and that is the whole trick: ivy takes where the rock is
    // proud and skips the hollows, so a runner sunk to a fixed z clings to some bodies and
    // vanishes behind others. Standing every curtain clear of the face would be a green sheet
    // hanging in the air — the RELIEF IS SUBTLE failure in leaf form.
    if (k.ivy > 0) {
        const nCurtain: i32 = @intFromFloat(@round(7.0 + 5.0 * k.ivy));
        var cu: i32 = 0;
        while (cu < nCurtain) : (cu += 1) {
            var cx = frng.range(-5.4, 5.4);
            // It starts PARTWAY UP and hangs down from there: ivy climbs off the ground and the
            // growing tip is at the top, so the mass belongs low and the runner thins as it rises.
            const y0 = H * frng.range(0.34, 0.86);
            const drop = y0 * frng.range(0.60, 0.95);
            const steps: i32 = 8;
            var prev: ?rl.Vector3 = null;
            var st: i32 = 0;
            while (st <= steps) : (st += 1) {
                const s = @as(f32, @floatFromInt(st)) / @as(f32, @floatFromInt(steps));
                const y = y0 - drop * s;
                cx += frng.signed() * 0.18; // the runner WANDERS as it descends — it isn't a plumb line
                // Off the rock at this height → this length of runner simply does not exist. That
                // clause is the whole fix for the version that hung green tiles in the sky above
                // the mass; `prev = null` also breaks the woody run, so nothing spans the gap.
                const fz = cliffFaceZ(face, cx, y) orelse {
                    prev = null;
                    continue;
                };
                const p = v3(cx, y, fz - 0.06); // a hair proud: it clings, it does not hang
                if (prev) |q| {
                    b.setMat(.wood);
                    b.addCapsule(q, p, 0.030, 0.045, 5, BARK_DK); // thickening downward, toward the root
                }
                prev = p;
                // LEAVES: small, many, and SUNK most of the way into the rock so only the front cap
                // breaks the surface — about 25% of the radius. The first pass used blobs three
                // times this size standing clear of the face, and a leaf that stands 40 cm off a
                // rock reads as a green tile stuck to it, which is exactly how it came out.
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
                        7, // rounder than the old 6: at this size the facets ARE the silhouette
                        if (frng.float() < 0.35) SCRUB_DK else IVY_GRN,
                    );
                }
            }
        }
        // Moss packed into the seams: low wide pads pressed flat onto the face, on the same measured
        // surface. This is what carries the damp read across the rock the creeper hasn't reached.
        // SMALL pads, MANY of them, and seated across their whole FOOTPRINT (cliffSeatZ, not
        // cliffFaceZ). A pad seated on its centre alone leaves the curving surface at its own ends
        // however well its middle sits — at half-widths up to 2.2 they came out as flat green
        // SHELVES with a lit top face, the horizontal version of the mistake the runners were
        // making vertically. Moss grows in patches anyway.
        b.setMat(.plant);
        var ms: i32 = 0;
        while (ms < 16) : (ms += 1) {
            const mx = frng.range(-5.0, 5.0);
            const my = H * frng.range(0.08, 0.74);
            const w = frng.range(0.40, 1.05);
            const hh = w * frng.range(0.30, 0.60);
            const fz = cliffSeatZ(face, mx, my, w, hh) orelse continue;
            b.addBlob(
                v3(mx, my, fz + 0.22), // ~4 cm of it shows: a tonal patch, not a cushion
                v3(w, hh, 0.26),
                3,
                7,
                if (frng.float() < 0.5) MOSS_DK else STONE_MOSS,
            );
        }
        // …and a fuller crest on top of the shared scrub. An overgrown face is green OVER the top,
        // not only down the front — from the plain the skyline is most of what you see of it.
        var cs: i32 = 0;
        while (cs < 5) : (cs += 1) {
            const s = top[@intCast(frng.intn(NM))];
            const r = frng.range(0.8, 1.6);
            b.addBlob(
                v3(s.x + frng.signed() * s.rx * 0.7, s.y - frng.range(0.05, 0.35), s.z + frng.signed() * s.rz * 0.6),
                v3(r, r * frng.range(0.40, 0.70), r * frng.range(0.7, 1.1)),
                3,
                6,
                if (frng.float() < 0.4) IVY_GRN else SCRUB_DK,
            );
        }
    }
    return b.toModel(shader);
}

// A BOULDER: three or four interpenetrating rounded masses (a single blob reads as an egg),
// faceted by a low side count, with chips at the base and moss on whatever faces the sky.
pub fn boulderMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4242);
    b.setMat(.stone);
    // Bodies use the DARK end of the rock palette. A boulder is a big smooth mass close to the
    // camera, so the hot key + gamma lift turns anything mid-valued into a pale pillow — the same
    // trap the tree trunks and the cliffs fell into, and worst here because you stand next to them.
    const nm = 3 + rng.intn(2);
    var i: i32 = 0;
    while (i < nm) : (i += 1) {
        const r = rng.range(0.75, 1.15) * (1.0 - 0.12 * @as(f32, @floatFromInt(i)));
        b.addBlob(
            v3(rng.signed() * 0.42, rng.range(0.55, 1.15), rng.signed() * 0.38),
            v3(r, r * rng.range(0.68, 0.95), r * rng.range(0.82, 1.18)),
            5,
            7,
            if (@mod(i, 2) == 0) CLIFF_DK else ROCK_DEEP,
        );
    }
    var c: i32 = 0;
    while (c < 4) : (c += 1) {
        const r = rng.range(0.14, 0.32);
        b.addBlob(v3(rng.signed() * 1.35, r * 0.55, rng.signed() * 1.3), v3(r, r * 0.7, r), 3, 5, CLIFF_LT);
    }
    b.setMat(.plant);
    b.addBlob(v3(rng.signed() * 0.3, 1.62, rng.signed() * 0.3), v3(0.62, 0.14, 0.55), 3, 6, STONE_MOSS); // moss cap
    return b.toModel(shader);
}

// A cluster of smaller field stones, half-sunk — the litter that makes a rock field read as
// a field rather than a few props on a lawn.
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
            v3(mathx.cosf(a) * d, r * rng.range(0.42, 0.78), mathx.sinf(a) * d), // sunk to varying depths
            v3(r * rng.range(0.9, 1.3), r * rng.range(0.6, 0.9), r * rng.range(0.9, 1.2)),
            3,
            6,
            if (rng.float() < 0.25) CLIFF_ROCK else if (rng.float() < 0.55) CLIFF_DK else ROCK_DEEP,
        );
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 0.8, rng.signed() * 0.8, 0.6); // grass creeping between them
    return b.toModel(shader);
}

// A standing stone: one rough monolith leaning off vertical, tapering, with shallow carved
// bands worn nearly smooth and lichen up the weather side.
pub fn monolithMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(606);
    b.setMat(.stone);
    // Guaranteed VISIBLE lean — signed() can roll near plumb, and a plumb monolith reads as
    // set by a crane yesterday. Direction random, magnitude never less than a hand's width.
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
    // A narrower cap slab, snapped a little off-axis, and a shoulder chunk lost.
    b.addBox(v3(lean.x + rng.signed() * 0.1, lean.y + 0.16, lean.z), v3(0.42, 0.05, 0), v3(0, 0.18, 0.04), v3(0, 0, 0.30), CLIFF_DK);
    b.addBlob(v3(lean.x * 0.62 + 0.5, lean.y * 0.6, lean.z * 0.6 + 0.2), v3(0.20, 0.26, 0.18), 3, 5, CLIFF_LT);
    // Carved bands: three shallow inset courses. Spacing, thickness and reach all wander (a
    // mason's hand, not a ruler), and the middle band is BROKEN — it stops where the shoulder
    // spalled instead of ringing the stone like a barrel hoop.
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
    b.setMat(.plant);
    b.addBlob(v3(lean.x * 0.25 - 0.42, 0.75, lean.z * 0.25), v3(0.16, 0.55, 0.30), 3, 5, STONE_MOSS); // lichen streak
    b.addBlob(v3(0, 0.10, 0), v3(0.85, 0.10, 0.75), 3, 6, SCRUB_DK); // grass swallowing the base
    return b.toModel(shader);
}

pub fn cairnMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2111);
    b.setMat(.stone);
    // A tapered core: a hand-built cairn has smaller stones wedged into its middle, and without
    // them you see clean through the stack.
    b.addCylinder(v3(0, 0.0, 0), v3(0, 1.34, 0), 0.34, 0.10, 7, MORTAR);
    var y: f32 = 0.0;
    var i: i32 = 0;
    const n: i32 = 7;
    while (i < n) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
        const r = (0.46 - 0.30 * t) * rng.range(0.85, 1.15);
        const hh = r * rng.range(0.42, 0.7);
        // Each stone sits a little off the axis, so the stack leans and reads as hand-built.
        b.addBlob(v3(rng.signed() * 0.09 * (1.0 + t), y + hh, rng.signed() * 0.09 * (1.0 + t)), v3(r, hh, r * rng.range(0.82, 1.18)), 3, 6, if (rng.float() < 0.3) CLIFF_LT else if (rng.float() < 0.55) CLIFF_DK else CLIFF_ROCK);
        y += hh * 1.55; // stones sit DOWN onto each other rather than balancing on a point
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

// An OUTCROP: bedrock breaking through the turf — a low shelf with a stepped face and grass
// growing over its back. The cheapest way to stop a plain looking like a lawn.
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
    // A stepped face on the exposed side — bedding, same as the cliffs.
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
    while (g < 3) : (g += 1) b.addBlob(v3(rng.range(-1.2, 1.2), rng.range(0.5, 0.9), rng.range(0.3, 0.8)), v3(rng.range(0.3, 0.6), 0.10, rng.range(0.25, 0.5)), 3, 6, if (rng.float() < 0.5) MOSS_DK else SCRUB_DK);
    tuftInto(&b, &rng, rng.range(-1.5, 1.5), rng.range(0.2, 0.9), 0.8);
    return b.toModel(shader);
}

// A SCREE patch: loose gravel and chips lying flat where water once ran or rock once fell.
pub fn screeMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2113);
    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 42) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0, 1.9) * @sqrt(rng.float()); // area-even
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

