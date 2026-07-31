const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// ── PROP ART KIT ── the shared vocabulary every mesh is authored in: the PALETTE, the weathering
// moves that separate a model from a ruin (courses, quoins, lichen, shed chips, a crack), the grass
// clump that creeps over half the props in the world, and the flame.
//
// It is one file because these are the things a change to ANY mesh may touch, and because a colour
// or a course that drifted between two of them would show as one region ageing differently from the
// next. Nothing here knows what a Kind is — it is below props.zig, not beside it.
// ── palettes ── pre-gamma DARK: the shader's hot key (*1.72) plus its 1/2.2 gamma lift turns
// any mid value into poured concrete wherever a big face takes the low sun square on.
pub const STONE = rgba(58, 55, 49, 255); // ruin masonry: ochre-grey mineral, not builders' slab
pub const STONE_LT = rgba(73, 70, 62, 255);
pub const STONE_DK = rgba(38, 36, 32, 255);
pub const STONE_MOSS = rgba(52, 58, 40, 255);
// The packed core behind every facing. Only ever glimpsed through a joint, so darker than any
// facing stone: a gap must read as DEPTH, never as a hole through to the sky.
pub const MORTAR = rgba(36, 33, 29, 255);
// MARBLE — dressed stone, against STONE's rubble masonry. Cooler and a touch paler, and the
// shader does the rest (gfx.Mat.marble veins it and gives it the only gloss besides steel and
// water). That polish is what says one of them was built with money.
pub const MARBLE = rgba(54, 54, 52, 255);
pub const MARBLE_LT = rgba(70, 70, 68, 255); // capitals, abaci, an altar top
pub const MARBLE_DK = rgba(34, 34, 34, 255); // in shade, or where the soot and rain got in
// Living rock: colder and greyer than ruin masonry, and DARKER than feels right on the swatch.
// A cliff face is a huge mass taking the low sun almost square on, and the scene shader's hot key
// plus its gamma lift turned the first (70,66,62) version chalk white from 40 m away.
pub const CLIFF_ROCK = rgba(47, 45, 42, 255);
pub const CLIFF_DK = rgba(31, 30, 28, 255);
pub const CLIFF_LT = rgba(62, 59, 55, 255);
// For rock you stand NEXT to (boulders, field stones). Darker again than the cliff set, which is
// only ever seen through 40 m of haze — up close that same value comes back as a pale pillow.
pub const ROCK_DEEP = rgba(23, 22, 21, 255);
// The city's old road surface. Darker than STONE for the same reason, plus one of its own: paving
// is a thing you half-notice underfoot, and at STONE's value it read as sheets of paper thrown
// across the grass.
pub const PAVE = rgba(32, 31, 27, 255);
pub const PAVE_DK = rgba(22, 21, 19, 255);
pub const PAVE_LT = rgba(41, 40, 35, 255); // the crown of a sett, worn smooth by feet and cartwheels
pub const SOIL = rgba(28, 23, 17, 255); // the dirt showing through where the road has lost its stones
pub const BARK = rgba(36, 29, 22, 255);
pub const BARK_DK = rgba(26, 21, 17, 255);
pub const BARK_LIVE = rgba(44, 36, 27, 255); // a living trunk reads a touch warmer than a dead one
// For BIG barrels only. The wider a smooth mass is, the more of it takes the sun square on, and
// the scene shader's hot key plus its 1/2.2 gamma lift then flattens a mid-dark albedo to pale
// beige — a great tree's bole needs to start nearly black to come back as bark.
pub const BARK_OLD = rgba(22, 17, 13, 255);
pub const IRON = rgba(30, 28, 26, 255);
pub const STEEL = rgba(100, 106, 116, 255);
pub const BRASS = rgba(122, 92, 40, 255);
pub const TIMBER = rgba(48, 37, 25, 255);
pub const TIMBER_DK = rgba(33, 26, 18, 255);
pub const THATCH = rgba(74, 60, 30, 255);
pub const THATCH_DK = rgba(52, 42, 22, 255);
// Emissive (vertex alpha < 255 = self-lit): the grace ember, its wisp, and every flame.
pub const EMBER = rgba(240, 162, 58, 40);
pub const WISP = rgba(250, 196, 110, 120);
// Eased DOWN across the board (owner: all flames a bit more subtle). These ride the EMISSIVE
// channel, which the scene shader takes to `base*1.35` — so a near-white core at 255 came back
// blown out and a fire was the loudest thing on any screen it appeared in. Same hues, same
// core→mid→tip ramp, less glare; the light each fire casts is unchanged.
pub const FLAME_CORE = rgba(226, 190, 128, 25); // pale heart of a torch — no longer near-WHITE
pub const FLAME_MID = rgba(214, 138, 48, 40);
pub const FLAME_TIP = rgba(176, 82, 24, 90); // the cooler tongue — and now the most transparent of them
pub const COAL = rgba(196, 78, 22, 70);
pub const CLOTH = rgba(76, 20, 12, 255); // faded war-banner crimson (matches the hero's cape)
pub const CLOTH_DK = rgba(48, 14, 10, 255); // …in the folds, and where the rain got into it
pub const CLOTH_SUN = rgba(96, 46, 32, 255); // …and at the frayed hem, where the sun ate the dye out
// Undyed CANVAS for tarps and sacking. Any of the dyed reds on a sun-facing swell saturates to
// plastic under the warm key — R so far ahead of G/B survives every darkening. Canvas doesn't.
pub const CANVAS = rgba(42, 36, 28, 255);

// Plant palette (pre-gamma dark) — Limgrave gold over scrub green.
pub const GRASS_GOLD = rgba(96, 76, 34, 255);
pub const GRASS_DRY = rgba(78, 64, 30, 255);
pub const GRASS_GRN = rgba(50, 56, 28, 255);
pub const SCRUB = rgba(38, 46, 26, 255);
pub const SCRUB_DK = rgba(28, 34, 20, 255);
pub const STEM = rgba(44, 54, 28, 255);
pub const PETAL = rgba(210, 196, 152, 255);
pub const SEED = rgba(118, 94, 46, 255);
pub const PETAL_GLOW = rgba(242, 206, 118, 200); // slight emissive — kin to the grace ember
// Canopy foliage: deep and unlit-looking in the mass, gold-touched where the sun catches it.
pub const LEAF_DK = rgba(26, 34, 20, 255);
pub const LEAF = rgba(36, 45, 24, 255);
pub const LEAF_LT = rgba(52, 58, 28, 255);
pub const LEAF_GOLD = rgba(74, 66, 30, 255);
pub const LEAF_PALE = rgba(58, 64, 34, 255); // willow: silvered, thirstier green
pub const BERRY = rgba(58, 14, 18, 255);
// The lush layer: a meadow needs more than gold grass, so there are damp greens, a couple of
// flower hues, and the browns of things that have died back. All pre-gamma dark, as ever.
pub const LEAF_DAMP = rgba(30, 44, 26, 255); // shade-grown: greener and cooler than the sunlit gold
pub const CLOVER_GRN = rgba(40, 54, 30, 255);
pub const MOSS_SOFT = rgba(44, 56, 32, 255);
pub const MOSS_DK = rgba(30, 40, 24, 255);
// Dead fern, collapsed. Kept DARK: at (84,60,30) the gamma lift turned patches of it into sheets
// of bright gold lying on the forest floor, which pulled the eye straight to the litter layer.
pub const BRACKEN_BRN = rgba(50, 35, 19, 255);
pub const NETTLE = rgba(34, 48, 26, 255);
pub const PURPLE = rgba(72, 44, 76, 255); // thistle / foxglove / heather bloom
pub const PURPLE_DK = rgba(50, 30, 56, 255);
pub const GORSE_GOLD = rgba(126, 100, 28, 255); // the only genuinely bright flower out here
pub const PETAL_WHITE = rgba(196, 190, 168, 255);
pub const PETAL_BLUE = rgba(96, 108, 140, 255);
pub const CAP_BROWN = rgba(88, 60, 40, 255); // mushroom cap
pub const CAP_PALE = rgba(126, 116, 96, 255);
pub const LILY_GRN = rgba(46, 60, 34, 255);
pub const IVY_GRN = rgba(28, 40, 24, 255);
pub const NEEDLE = rgba(23, 33, 25, 255); // conifer: the darkest green in the world
pub const NEEDLE_LT = rgba(34, 44, 28, 255);
pub const BIRCH_BARK = rgba(104, 100, 90, 255); // pale, and the only tree you can pick out at distance
pub const BIRCH_SCAR = rgba(44, 42, 38, 255);
pub const BONE = rgba(108, 104, 92, 255);
pub const RUST = rgba(58, 38, 24, 255);
// BONFIRE ASH — the palest albedo in the world, and deliberately so. Everything else out here is
// authored near-black because the shader's hot key plus the gamma lift turn mid values pale; ash is
// the one material that WANTS to come back pale, because a grey pat of it in a ring of stones is
// what finds your eye across a hundred metres of golden plain. That is the bonfire's whole job, and
// it is done by albedo, not by the light. Still kept well under mid grey: at 126 the lift took it
// to 237 and the pit read as spilled paint.
pub const ASH = rgba(78, 74, 70, 255);
pub const ASH_LT = rgba(96, 92, 86, 255); // where it has been raked over, or a fresh drift
pub const ASH_DK = rgba(46, 43, 40, 255); // wet, or trodden into the kerb
// The tarn: dark peat-water in the middle, silted a little paler at the rim. The RIPPLES and
// the sun glitter are the shader's (gfx.Mat.water); these are only what's suspended in it.
// Authored DARK on purpose — the first pass was three times this bright and the lake read as
// milky ice, because a water surface gets nearly all of its light from the specular, not the
// albedo. And the deep→shallow spread is kept narrow: the sheet is a fan of flat-shaded quads,
// so a wide gradient shows up as concentric BANDS rather than as depth.
pub const WATER_DEEP = rgba(13, 19, 21, 255);
pub const WATER_MID = rgba(18, 25, 26, 255);
pub const WATER_SHALLOW = rgba(30, 35, 31, 255);
pub const WATER_MUD = rgba(40, 35, 25, 255); // the wet margin the sheet sits in

/// One footprint collider in a kind's LOCAL space (a capsule a→b with radius r; a==b is a plain
/// circle). env rotates it by the instance yaw and multiplies by its scale. `h` is the piece's own
/// top height — what makes arrow COVER work (a shot clears a low kerb but thunks into a chapel
/// wall), so it is per-part, not per-kind. Re-exported by props.zig as `props.Part`.
pub const Part = struct { ax: f32 = 0, az: f32 = 0, bx: f32 = 0, bz: f32 = 0, r: f32, h: f32 };

// The watchtower's collider ring: 11 of 14 positions around the drum, the other 3 left open as
// the doorway. Generated so it can't drift from the masonry the mesh actually lays down (both
// read TOWER_R / TOWER_SIDES / TOWER_DOOR).
pub const TOWER_R: f32 = 2.35; // wall centre-line radius
pub const TOWER_SIDES: i32 = 14;
pub const TOWER_DOOR: i32 = 3; // masonry columns omitted for the door, centred on local −Z (index 0)
pub const towerRing = blk: {
    var out: [TOWER_SIDES - TOWER_DOOR]Part = undefined;
    var n: usize = 0;
    for (0..TOWER_SIDES) |i| {
        if (towerDoorway(@intCast(i))) continue;
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, TOWER_SIDES);
        out[n] = .{ .ax = @sin(a) * TOWER_R, .az = -@cos(a) * TOWER_R, .bx = @sin(a) * TOWER_R, .bz = -@cos(a) * TOWER_R, .r = 0.62, .h = 11.0 };
        n += 1;
    }
    std.debug.assert(n == out.len);
    break :blk out;
};

// Is masonry column `i` part of the doorway gap? A column's outward direction is
// `radial(a) = (sin a, 0, −cos a)`, so ANGLE 0 — index 0 — is the one facing local −Z. The gap is
// therefore centred on index 0 and WRAPS the seam, which is what puts the door on local −Z and a
// yaw-0 tower's entrance to the south.
//
// It used to centre on index TOWER_SIDES/2 (angle pi) on the reasoning that "angle pi = −Z" — but
// at angle pi `radial` is (0, 0, +1), so the opening came out on local +Z, the opposite side from
// every consumer: env.towerSite marks the door with a brazier at local −Z (which stood against the
// blank back wall), and the --shot framings aim at a −Z doorway. Six comments said −Z and only the
// arithmetic said +Z. The test below pins the side so the seam-wrap can't be "simplified" back.
pub fn towerDoorway(i: i32) bool {
    const half = @divTrunc(TOWER_DOOR, 2);
    return @mod(i + half, TOWER_SIDES) < TOWER_DOOR;
}

// ── SHARED MASONRY + WEATHERING ─────────────────────────────────────────────────────────
// The moves that separate a MODEL from a RUIN — courses, lichen, shed chips, a crack. Shared so
// the whole avenue weathers one way instead of five.
//
// The rule they encode: a big plain face is the enemy. A near-black albedo is only half of it —
// a 6 m cube of stone is a grey monolith at any value, and the same cube laid as nine jittered
// courses with quoins up its corners reads as masonry from the far side of the world.

// PACKED STONE HAS A CORE (owner's law). A row of blocks is only the FACING; a real wall is
// packed solid behind it. Forget that and you get both of the failures that were in here: the
// joints leak sky (or the far side of the room), and the packing reads loose — blocks butted in
// their own slot show a seam all round each one, like a dry-stone model kit. So every coursed
// run lays a MORTAR substrate first, then overlaps its facing 1.2–1.5x the pitch, vertically
// too. Any remaining joint then shows packed depth, never daylight.

/// A run of coursed masonry from (ax,az) to (bx,bz). `courses` bands of overlapping blocks laid
/// `thick` deep over a solid core, an OPENING skipped between `gapLo..gapHi` along the run
/// (signed distance from its centre) and `sillY..headY` up it, and the top two courses shedding
/// blocks at `crumbleTop`. Leaves the builder on `.stone`.
pub const Course = struct {
    thick: f32,
    height: f32,
    courses: i32 = 9,
    blockW: f32 = 0.72, // nominal block length along the run
    crumbleTop: f32 = 0.45, // the top two courses have not been pointed in three centuries
    crumble: f32 = 0.04, // …every course below them
    gapLo: f32 = 9, // no opening by default (the run is only ever a few metres)
    gapHi: f32 = 9,
    sillY: f32 = 0,
    headY: f32 = 0,
    core: f32 = 0.80, // substrate thickness as a fraction of `thick` (0 = facing only)
};

// ── RELIEF IS SUBTLE (owner's call) ────────────────────────────────────────────────────
// Surface detail — bedding bands, arrises, quoins, joints, coursing, fracture shards — exists to
// BREAK UP a big dark mass so it doesn't read as plastic. It does that job with a few centimetres.
// Every one of these started out standing far enough off its mass to be counted individually, and
// the result reads as DISHEVELED: strips stuck onto a column, slates hung off a cliff, a wall of
// rubble tipped into a mould. Rules of thumb, all learned the same way:
//
//   - Detail on a curved mass should protrude a FEW PERCENT of that mass's radius, not a tenth.
//     Sink a proud primitive most of the way in and let only its edge break the surface.
//   - Prefer more SIDES on the mass over more relief on top of it. A 9-gon shaft has flats wide
//     enough that anything sitting on one reads as glued to it; a 12-gon does not.
//   - Cut AMPLITUDE, never irregularity. Same counts, same seeds, same asymmetry and lean — the
//     wabi-sabi law stands. Quieter is not the same as more regular, and a model that has been
//     made regular is the other failure, not the fix for this one.
//   - The exceptions that must stay generous: the coursing OVERLAP (butted blocks show a seam
//     round every one) and the substrate CORE (without it the joints leak sky).

pub fn courseInto(bb: *Builder, r: *mathx.Rng, ax: f32, az: f32, bx: f32, bz: f32, spec: Course) void {
    bb.setMat(.stone);
    const dx = bx - ax;
    const dz = bz - az;
    const runLen = @sqrt(dx * dx + dz * dz);
    const ux = dx / runLen;
    const uz = dz / runLen;
    const ch = spec.height / @as(f32, @floatFromInt(spec.courses));
    // THE SUBSTRATE, course by course so it dodges the same opening the facing does.
    if (spec.core > 0.001) {
        var c: i32 = 0;
        while (c < spec.courses) : (c += 1) {
            const y0 = @as(f32, @floatFromInt(c)) * ch;
            const yc = y0 + ch * 0.5;
            const open = yc > spec.sillY and yc < spec.headY;
            // Below/above the opening the core spans the whole run; through it, two flanks.
            const lo: f32 = if (open) spec.gapLo else runLen * 0.5;
            const hi: f32 = if (open) spec.gapHi else runLen * 0.5;
            const spans = [2][2]f32{ .{ -runLen * 0.5, @min(lo, runLen * 0.5) }, .{ @max(hi, -runLen * 0.5), runLen * 0.5 } };
            for (spans, 0..) |sp, si| {
                if (si == 1 and !open) break; // one span covers it when there is no opening here
                const w = sp[1] - sp[0];
                if (w <= 0.02) continue;
                const mid = (sp[0] + sp[1]) * 0.5;
                bb.addBox(
                    v3(ax + ux * (runLen * 0.5 + mid), yc, az + uz * (runLen * 0.5 + mid)),
                    v3(ux * w * 0.5, 0, uz * w * 0.5),
                    v3(0, ch * 0.56, 0),
                    v3(-uz * spec.thick * spec.core, 0, ux * spec.thick * spec.core),
                    MORTAR,
                );
            }
        }
    }
    var c: i32 = 0;
    while (c < spec.courses) : (c += 1) {
        const yc = @as(f32, @floatFromInt(c)) * ch + ch * 0.5;
        const crumble: f32 = if (c >= spec.courses - 2) spec.crumbleTop else spec.crumble;
        const nb: i32 = @intFromFloat(@max(runLen / spec.blockW, 2.0));
        var i: i32 = 0;
        while (i < nb) : (i += 1) {
            const t = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(nb));
            const s = (t - 0.5) * runLen; // signed distance along the run from its centre
            if (s > spec.gapLo and s < spec.gapHi and yc > spec.sillY and yc < spec.headY) continue; // the opening
            if (r.float() < crumble) continue;
            // The OVERLAP stays generous — butted blocks show a seam round every one, and the
            // facing has to run well past its slot. What comes down is everything OUT OF PLANE:
            // the ±0.03 shove, the roll, the skew and the course-height spread together made every
            // block stand a different distance off its neighbours, and a wall of that reads as
            // rubble tipped into a mould rather than as coursed masonry. A facade should be felt
            // across a whole face, not counted block by block.
            const bw = (runLen / @as(f32, @floatFromInt(nb))) * r.range(1.20, 1.50); // BEDDED, not butted
            const col = if (r.float() < 0.15) STONE_LT else if (r.float() < 0.32) STONE_DK else STONE;
            bb.addBox(
                v3(ax + ux * (t * runLen) + r.signed() * 0.016, yc, az + uz * (t * runLen) + r.signed() * 0.016),
                v3(ux * bw * 0.5, r.signed() * 0.006, uz * bw * 0.5),
                v3(r.signed() * 0.010, ch * 0.54 * r.range(1.0, 1.06), r.signed() * 0.010),
                v3(-uz * spec.thick, 0, ux * spec.thick),
                col,
            );
        }
    }
}

/// A SQUARE coursed mass (a pier, a keep, a gate tower): a solid core with `n` facing slabs
/// `w` x `d` over it, each nudged off axis and tilted a hair, alternating tint, tapering by
/// `taper`. Returns the y it finished at, so masses stack. Leaves `.stone`.
pub fn courseStack(bb: *Builder, r: *mathx.Rng, cx: f32, y0: f32, cz: f32, w: f32, d: f32, ch: f32, n: i32, taper: f32) f32 {
    bb.setMat(.stone);
    const total = ch * @as(f32, @floatFromInt(n));
    bb.addCube(v3(cx, y0 + total * 0.5, cz), v3(w * (1.0 - taper * 0.5) * 0.94, total, d * (1.0 - taper * 0.5) * 0.94), MORTAR); // the core
    var y = y0;
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
        // Same rule as `courseInto`: the courses still overlap (a butted stack shows every seam)
        // but each slab sits far closer to the one under it. The ±0.05 shove was a fifth of a
        // course height, so a tower's silhouette stepped in and out all the way up.
        const sw = w * (1.0 - taper * t) * r.range(0.99, 1.014);
        const sd = d * (1.0 - taper * t) * r.range(0.99, 1.014);
        const h = ch * r.range(1.0, 1.08); // courses OVERLAP
        bb.addBox(
            v3(cx + r.signed() * 0.026, y + h * 0.45, cz + r.signed() * 0.026),
            v3(sw * 0.5, r.signed() * 0.008, r.signed() * 0.007),
            v3(0, h * 0.5, 0),
            v3(r.signed() * 0.007, 0, sd * 0.5),
            // The banding stays — it is the form break a big dark mass needs — but every OTHER
            // course being the darkest stone was a zebra. Dark only TENDS even: odd courses
            // go dark too (less often), so the period never survives more than a few courses.
            if (r.float() < (if (@mod(i, 2) == 0) @as(f32, 0.5) else 0.24)) STONE_DK else if (r.float() < 0.16) STONE_LT else STONE,
        );
        y += ch;
    }
    return y;
}

/// Alternating corner QUOINS up an edge — long/short blocks tying two faces together. What
/// stops a course-stacked mass reading as a stack of pancakes.
pub fn quoinsInto(bb: *Builder, r: *mathx.Rng, cx: f32, cz: f32, y0: f32, ch: f32, n: i32, big: f32, small: f32) void {
    bb.setMat(.stone);
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const long = @mod(i, 2) == 0;
        const sx = if (long) big else small;
        const sz = if (long) small else big;
        bb.addCube(
            v3(cx, y0 + (@as(f32, @floatFromInt(i)) + 0.5) * ch, cz),
            v3(sx * r.range(0.94, 1.06), ch * r.range(0.86, 0.98), sz * r.range(0.94, 1.06)),
            if (r.float() < 0.3) STONE_LT else STONE,
        );
    }
}

/// Lichen / moss over a surface. `ext` is the CLUSTER's half-extent and each patch keeps its
/// flat axis flat — small `y` for a mossy cap, small `z` for a streak down a weather face.
/// Leaves the builder on `.plant`.
pub fn lichenInto(bb: *Builder, r: *mathx.Rng, c: rl.Vector3, ext: rl.Vector3, n: i32) void {
    bb.setMat(.plant);
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const f = r.range(0.32, 0.66);
        bb.addBlob(
            v3(c.x + r.signed() * ext.x, c.y + r.signed() * ext.y, c.z + r.signed() * ext.z),
            v3(@max(ext.x * f, 0.014), @max(ext.y * f, 0.014), @max(ext.z * f, 0.014)),
            3,
            5,
            if (r.float() < 0.4) MOSS_DK else if (r.float() < 0.7) STONE_MOSS else MOSS_SOFT,
        );
    }
}

/// Stone SHED at the foot of something — chips, a broken corner, a drum shard. Rounded: a chip
/// that came off a wall three centuries ago has no edges left. Leaves `.stone`.
pub fn chipsInto(bb: *Builder, r: *mathx.Rng, cx: f32, cz: f32, spread: f32, lo: f32, hi: f32, n: i32) void {
    bb.setMat(.stone);
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const a = r.angle();
        const d = r.range(0.2, 1.0) * spread;
        const rr = r.range(lo, hi);
        bb.addBlob(
            v3(cx + mathx.cosf(a) * d, rr * r.range(0.34, 0.62), cz + mathx.sinf(a) * d),
            v3(rr, rr * r.range(0.48, 0.8), rr * r.range(0.8, 1.3)),
            3,
            5,
            if (r.float() < 0.26) STONE_MOSS else if (r.float() < 0.5) STONE_LT else STONE_DK,
        );
    }
}

/// A fracture across a face: a thin dark sliver sunk into the stone. Runs from `a` along unit
/// `dir` for `len`, `w` wide across unit `side`, sinking `into` the surface along dir x side —
/// both in-face axes are the caller's and the depth falls out, so one call works on a wall and
/// on a slab top alike. Twelve triangles that read from ten metres: the cheapest age in here.
pub fn crackInto(bb: *Builder, a: rl.Vector3, dir: rl.Vector3, side: rl.Vector3, len: f32, w: f32, into: f32) void {
    bb.setMat(.stone);
    const nx = dir.y * side.z - dir.z * side.y;
    const ny = dir.z * side.x - dir.x * side.z;
    const nz = dir.x * side.y - dir.y * side.x;
    const nl = @max(@sqrt(nx * nx + ny * ny + nz * nz), 1e-5);
    bb.addBox(
        v3(a.x + dir.x * len * 0.5, a.y + dir.y * len * 0.5, a.z + dir.z * len * 0.5),
        mathx.scaleV(dir, len * 0.5),
        mathx.scaleV(side, w),
        v3(nx / nl * into, ny / nl * into, nz / nl * into),
        STONE_DK,
    );
}

// One flame: emissive TONGUES, not a cone. A fire reads from its SILHOUETTE — tall narrow lobes at
// uneven heights and leans, mostly orange, with only a small hot heart. Built as a fat stack of
// near-white blobs it read as a traffic cone: the pale core was the biggest thing in it. The tongues
// are also the one thing in the scene the shader draws SEMI-TRANSPARENT (`FLAME_A_CORE`/`_TIP`),
// graded off this ramp's own emissive — so the silhouette still has to carry it, but the thin end of
// it now lets the world through.
pub fn flameInto(b: *Builder, rng: *mathx.Rng, cx: f32, cy: f32, cz: f32, s: f32) void {
    // `.flame` gets two things `.plain` could not: the vertex shader's WRITHE (so the thing
    // actually moves — the light has been guttering since it was written, over a flame standing
    // perfectly still) and no surface grain at all, which is what the old comment here asked for.
    // `setAnimY(cy)` is what tells the shader where the fuel is, so the coals hold still while the
    // tongues dance; both are STICKY, so both are put back at the end.
    b.setMat(.flame);
    b.setAnimY(cy);
    // THE HEART: a low pool at the fuel, and a BROAD one — a fire sits in its bed, it does not
    // balance on it. (Small and tight is what made an earlier version read as a traffic cone; the
    // opposite failure, a narrow heart under narrow tongues, read as a candle.)
    b.addBlob(v3(cx, cy + 0.015 * s, cz), v3(0.175 * s, 0.045 * s, 0.175 * s), 3, 9, COAL);
    b.addBlob(v3(cx, cy + 0.055 * s, cz), v3(0.078 * s, 0.048 * s, 0.078 * s), 3, 8, FLAME_CORE);
    // TONGUES: TAPERED SPIRES, not stacked blobs. A capsule with ra > rb is a smooth cone with
    // rounded ends, which is the shape of a flame tongue — two fat blobs one on top of the other is
    // the shape of a snowman, and at six sides their facet folds were most of what read as crumpled
    // paper once the vertex writhe started bending them.
    //
    // LOW AND WIDE (owner's call — they read SKINNY and weird). A real fire is roughly as broad as
    // it is tall and it BOILS; a tall thin one is a blowtorch. Three numbers carry that: the height
    // band came down by a third, the tongue gauge nearly doubled, and the base spread out — so the
    // silhouette is now a squat cluster of fat lobes instead of a bundle of needles, and the vertex
    // writhe has something with body to bend rather than whipping a wire about.
    //
    // SIX, at unequal heights, each in TWO segments so the spire can bend on its way up (a straight
    // one is a spike). The tips also stay FATTER: tapering to a twelfth of the base is what turned
    // every tongue into a hair at the top, and hairs are exactly what read as "weird".
    var t: i32 = 0;
    while (t < 6) : (t += 1) {
        const a = rng.angle();
        const off = rng.range(0.02, 0.115) * s; // a BROAD base — the lobes sit beside each other
        const h = rng.range(0.17, 0.44) * s; // the tallest tongue sets the flame's height
        const w = rng.range(0.058, 0.100) * s; // …and they are FAT relative to it now
        const lean = rng.range(0.01, 0.05) * s;
        const y0 = cy + 0.02 * s;
        const x0 = cx + mathx.cosf(a) * off;
        const z0 = cz + mathx.sinf(a) * off;
        const mx = x0 + mathx.cosf(a) * lean;
        const mz = z0 + mathx.sinf(a) * lean;
        const tx = mx + mathx.cosf(a) * lean * 1.6 + rng.signed() * 0.02 * s;
        const tz = mz + mathx.sinf(a) * lean * 1.6 + rng.signed() * 0.02 * s;
        b.addCapsule(
            v3(x0, y0, z0),
            v3(mx, y0 + h * 0.55, mz),
            w,
            w * 0.82,
            7,
            if (t == 0) FLAME_MID else if (rng.float() < 0.55) FLAME_MID else FLAME_TIP,
        );
        b.addCapsule(v3(mx, y0 + h * 0.52, mz), v3(tx, y0 + h, tz), w * 0.80, w * 0.26, 6, FLAME_TIP);
    }
    // …and a few loose EMBERS drifting off the top. Brought DOWN with the tongues: embers hanging
    // where the old flame's tips used to be left a column of specks over a fire that no longer
    // reaches them.
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const r = rng.range(0.010, 0.022) * s;
        b.addBlob(v3(cx + rng.signed() * 0.16 * s, cy + rng.range(0.30, 0.62) * s, cz + rng.signed() * 0.16 * s), v3(r, r, r), 3, 5, WISP);
    }
    b.setAnimY(0); // sticky, like setMat — hand the Builder back the way it was found
}
pub fn blade(b: *Builder, x: f32, z: f32, h: f32, lx: f32, lz: f32, r: f32, col: rl.Color) void {
    b.addCylinder(v3(x, 0, z), v3(x + lx, h, z + lz), r, 0.003, 4, col);
}

pub fn bladeColor(rng: *mathx.Rng) rl.Color {
    const roll = rng.float();
    if (roll < 0.5) return GRASS_GOLD;
    if (roll < 0.8) return GRASS_DRY;
    return GRASS_GRN;
}

// Grow one clump of blades (plus the odd seed stalk) around (cx, cz) into b. Shared by the
// flora meshes AND by any prop that wants grass creeping over its base.
pub fn tuftInto(b: *Builder, rng: *mathx.Rng, cx: f32, cz: f32, s: f32) void {
    const nb = 6 + rng.intn(3);
    var i: i32 = 0;
    while (i < nb) : (i += 1) {
        const a = rng.angle();
        const rr = rng.range(0.02, 0.10) * s;
        const x = cx + mathx.cosf(a) * rr;
        const z = cz + mathx.sinf(a) * rr;
        const lean = rng.range(0.06, 0.24) * s;
        const la = rng.angle();
        blade(b, x, z, rng.range(0.26, 0.52) * s, mathx.cosf(la) * lean, mathx.sinf(la) * lean, 0.016 * s, bladeColor(rng));
    }
    if (rng.float() < 0.55) {
        // a taller seed stalk rising out of the clump
        const la = rng.angle();
        const lean = rng.range(0.04, 0.12) * s;
        const h = rng.range(0.55, 0.8) * s;
        const tx = cx + mathx.cosf(la) * lean;
        const tz = cz + mathx.sinf(la) * lean;
        blade(b, cx, cz, h, mathx.cosf(la) * lean, mathx.sinf(la) * lean, 0.012 * s, GRASS_DRY);
        b.addCube(v3(tx, h, tz), v3(0.035 * s, 0.09 * s, 0.035 * s), SEED);
    }
}

// A single golden grass clump.
