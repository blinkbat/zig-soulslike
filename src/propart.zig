const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

pub const STONE = rgba(58, 55, 49, 255); // ruin masonry: ochre-grey mineral, not builders' slab
pub const STONE_LT = rgba(73, 70, 62, 255);
pub const STONE_DK = rgba(38, 36, 32, 255);
pub const STONE_MOSS = rgba(52, 58, 40, 255);
// The packed core behind every facing.
pub const MORTAR = rgba(36, 33, 29, 255);
// MARBLE — dressed stone, against STONE's rubble masonry.
pub const MARBLE = rgba(54, 54, 52, 255);
pub const MARBLE_LT = rgba(70, 70, 68, 255); // capitals, abaci, an altar top
pub const MARBLE_DK = rgba(34, 34, 34, 255); // in shade, or where the soot and rain got in
// Living rock: colder and greyer than ruin masonry, and DARKER than feels right on the swatch.
pub const CLIFF_ROCK = rgba(47, 45, 42, 255);
pub const CLIFF_DK = rgba(31, 30, 28, 255);
pub const CLIFF_LT = rgba(62, 59, 55, 255);
// For rock you stand NEXT to (boulders, field stones).
pub const ROCK_DEEP = rgba(23, 22, 21, 255);
// The city's old road surface.
pub const PAVE = rgba(32, 31, 27, 255);
pub const PAVE_DK = rgba(22, 21, 19, 255);
pub const PAVE_LT = rgba(41, 40, 35, 255); // the crown of a sett, worn smooth by feet and cartwheels
pub const SOIL = rgba(28, 23, 17, 255); // the dirt showing through where the road has lost its stones
pub const BARK = rgba(36, 29, 22, 255);
pub const BARK_DK = rgba(26, 21, 17, 255);
pub const BARK_LIVE = rgba(44, 36, 27, 255); // a living trunk reads a touch warmer than a dead one
// For BIG barrels only.
pub const BARK_OLD = rgba(22, 17, 13, 255);
pub const IRON = rgba(30, 28, 26, 255);
pub const STEEL = rgba(100, 106, 116, 255);
pub const BRASS = rgba(122, 92, 40, 255);
pub const TIMBER = rgba(48, 37, 25, 255);
pub const TIMBER_DK = rgba(33, 26, 18, 255);
// A GUITAR'S SPRUCE TOP — the one manufactured surface out here, and the palest warm wood in the set.
pub const SPRUCE = rgba(59, 46, 30, 255);
pub const THATCH = rgba(74, 60, 30, 255);
pub const THATCH_DK = rgba(52, 42, 22, 255);
// Emissive (vertex alpha < 255 = self-lit): the grace ember, its wisp, and every flame.
pub const EMBER = rgba(252, 184, 80, 14);
pub const WISP = rgba(250, 196, 110, 120);
// Eased DOWN across the board (owner: all flames a bit more subtle).
pub const FLAME_CORE = rgba(226, 190, 128, 25); // pale heart of a torch — no longer near-WHITE
pub const FLAME_MID = rgba(214, 138, 48, 40);
pub const FLAME_TIP = rgba(176, 82, 24, 90); // the cooler tongue — and now the most transparent of them
pub const COAL = rgba(196, 78, 22, 70);
// OPAQUE (alpha 255), and that is the correction that matters here: in this renderer a vertex alpha under 255 does NOT mean see-through, it means SELF-LIT (see EMBER above).
pub const SMOKE_HOT = rgba(64, 54, 46, 255);
pub const SMOKE_MID = rgba(58, 55, 52, 255);
pub const SMOKE_COLD = rgba(52, 52, 55, 255); // …cooling to the blue-grey of the sky it is joining
pub const CLOTH = rgba(76, 20, 12, 255); // faded war-banner crimson (matches the hero's cape)
pub const CLOTH_DK = rgba(48, 14, 10, 255); // …in the folds, and where the rain got into it
pub const CLOTH_SUN = rgba(96, 46, 32, 255); // …and at the frayed hem, where the sun ate the dye out
// Undyed CANVAS for tarps and sacking.
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
// The lush layer: a meadow needs more than gold grass, so there are damp greens, a couple of flower hues, and the browns of things that have died back.
pub const LEAF_DAMP = rgba(30, 44, 26, 255); // shade-grown: greener and cooler than the sunlit gold
pub const CLOVER_GRN = rgba(40, 54, 30, 255);
pub const MOSS_SOFT = rgba(44, 56, 32, 255);
pub const MOSS_DK = rgba(30, 40, 24, 255);
// Dead fern, collapsed.
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
// BONFIRE ASH — the palest albedo in the world, and deliberately so.
pub const ASH = rgba(78, 74, 70, 255);
pub const ASH_LT = rgba(96, 92, 86, 255); // where it has been raked over, or a fresh drift
pub const ASH_DK = rgba(46, 43, 40, 255); // wet, or trodden into the kerb
// The tarn: dark peat-water in the middle, silted a little paler at the rim.
pub const WATER_DEEP = rgba(13, 19, 21, 255);
pub const WATER_MID = rgba(18, 25, 26, 255);
pub const WATER_SHALLOW = rgba(30, 35, 31, 255);
pub const WATER_MUD = rgba(40, 35, 25, 255); // the wet margin the sheet sits in

/// One footprint collider in a kind's LOCAL space (a capsule a→b with radius r; a==b is a plain circle). env rotates it by the instance yaw and multiplies by its scale.
pub const Part = struct { ax: f32 = 0, az: f32 = 0, bx: f32 = 0, bz: f32 = 0, r: f32, h: f32 };

// The watchtower's collider ring: 11 of 14 positions around the drum, the other 3 left open as the doorway.
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

// Is masonry column `i` part of the doorway gap?
pub fn towerDoorway(i: i32) bool {
    const half = @divTrunc(TOWER_DOOR, 2);
    return @mod(i + half, TOWER_SIDES) < TOWER_DOOR;
}

// The moves that separate a MODEL from a RUIN — courses, lichen, shed chips, a crack.

// PACKED STONE HAS A CORE (owner's law).

/// A run of coursed masonry from (ax,az) to (bx,bz).
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

// Surface detail — bedding bands, arrises, quoins, joints, coursing, fracture shards — exists to BREAK UP a big dark mass so it doesn't read as plastic.

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
            // The OVERLAP stays generous — butted blocks show a seam round every one, and the facing has to run well past its slot.
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

/// A SQUARE coursed mass (a pier, a keep, a gate tower): a solid core with `n` facing slabs `w` x `d` over it, each nudged off axis and tilted a hair, alternating tint, tapering by `taper`.
pub fn courseStack(bb: *Builder, r: *mathx.Rng, cx: f32, y0: f32, cz: f32, w: f32, d: f32, ch: f32, n: i32, taper: f32) f32 {
    bb.setMat(.stone);
    const total = ch * @as(f32, @floatFromInt(n));
    bb.addCube(v3(cx, y0 + total * 0.5, cz), v3(w * (1.0 - taper * 0.5) * 0.94, total, d * (1.0 - taper * 0.5) * 0.94), MORTAR); // the core
    var y = y0;
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
        // Same rule as `courseInto`: the courses still overlap (a butted stack shows every seam) but each slab sits far closer to the one under it.
        const sw = w * (1.0 - taper * t) * r.range(0.99, 1.014);
        const sd = d * (1.0 - taper * t) * r.range(0.99, 1.014);
        const h = ch * r.range(1.0, 1.08); // courses OVERLAP
        bb.addBox(
            v3(cx + r.signed() * 0.026, y + h * 0.45, cz + r.signed() * 0.026),
            v3(sw * 0.5, r.signed() * 0.008, r.signed() * 0.007),
            v3(0, h * 0.5, 0),
            v3(r.signed() * 0.007, 0, sd * 0.5),
            // The banding stays — it is the form break a big dark mass needs — but every OTHER course being the darkest stone was a zebra.
            if (r.float() < (if (@mod(i, 2) == 0) @as(f32, 0.5) else 0.24)) STONE_DK else if (r.float() < 0.16) STONE_LT else STONE,
        );
        y += ch;
    }
    return y;
}

/// Alternating corner QUOINS up an edge — long/short blocks tying two faces together.
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

/// Lichen / moss over a surface.
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

/// Stone SHED at the foot of something — chips, a broken corner, a drum shard.
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

/// A fracture across a face: a thin dark sliver sunk into the stone.
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

// One flame: emissive TONGUES, not a cone.
pub fn flameInto(b: *Builder, rng: *mathx.Rng, cx: f32, cy: f32, cz: f32, s: f32) void {
    // `.flame` gets two things `.plain` could not: the vertex shader's WRITHE (so the thing actually moves — the light has been guttering since it was written, over a flame standing perfectly still) and no surface grain at all, which is what the old comment here asked for.
    b.setMat(.flame);
    b.setAnimY(cy);
    // THE HEART: a low pool at the fuel, and a BROAD one — a fire sits in its bed, it does not balance on it.
    b.addBlob(v3(cx, cy + 0.015 * s, cz), v3(0.175 * s, 0.045 * s, 0.175 * s), 3, 9, COAL);
    b.addBlob(v3(cx, cy + 0.055 * s, cz), v3(0.078 * s, 0.048 * s, 0.078 * s), 3, 8, FLAME_CORE);
    // TONGUES: TAPERED SPIRES, not stacked blobs.
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
    // …and a few loose EMBERS drifting off the top.
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

// Grow one clump of blades (plus the odd seed stalk) around (cx, cz) into b.
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

// Up here in the art kit rather than in propruins because TWO things hold this instrument now: the bonfire camp props one against its rock, and the HERO picks one up to play at a rest (see hero.poseRest).

/// AN ORIENTED FRAME for a flat object: `w` across it, `a` along it, `n` out through its face, with n = w x a.
pub const Frame = struct {
    o: rl.Vector3,
    w: rl.Vector3,
    a: rl.Vector3,
    n: rl.Vector3,
    s: f32 = 1,

    pub fn at(self: Frame, across: f32, along: f32, out: f32) rl.Vector3 {
        const ac = across * self.s;
        const al = along * self.s;
        const ou = out * self.s;
        return v3(
            self.o.x + self.w.x * ac + self.a.x * al + self.n.x * ou,
            self.o.y + self.w.y * ac + self.a.y * al + self.n.y * ou,
            self.o.z + self.w.z * ac + self.a.z * al + self.n.z * ou,
        );
    }
    // A point on a circle of radius `r` lying IN the face plane, for the round features on it.
    pub fn ring(self: Frame, across: f32, along: f32, out: f32, r: f32, ang: f32) rl.Vector3 {
        return self.at(across + mathx.cosf(ang) * r, along + mathx.sinf(ang) * r, out);
    }
    // Half-extent vectors for `addBox`, so a box in this frame scales with everything else.
    pub fn axis(self: Frame, across: f32, along: f32, out: f32) rl.Vector3 {
        const ac = across * self.s;
        const al = along * self.s;
        const ou = out * self.s;
        return v3(
            self.w.x * ac + self.a.x * al + self.n.x * ou,
            self.w.y * ac + self.a.y * al + self.n.y * ou,
            self.w.z * ac + self.a.z * al + self.n.z * ou,
        );
    }
};

/// A FLAT PLATE from a closed outline: `prof` is (along, half-width, half-depth) up the frame's `a` axis, mirrored across `w`.
pub fn plateInto(b: *Builder, fr: Frame, prof: []const [3]f32, face: rl.Color, side: rl.Color) void {
    const back = v3(-fr.n.x, -fr.n.y, -fr.n.z);
    var i: usize = 0;
    while (i + 1 < prof.len) : (i += 1) {
        const t0 = prof[i][0];
        const w0 = prof[i][1];
        const d0 = prof[i][2];
        const t1 = prof[i + 1][0];
        const w1 = prof[i + 1][1];
        const d1 = prof[i + 1][2];
        b.quad(fr.at(-w0, t0, d0), fr.at(w0, t0, d0), fr.at(w1, t1, d1), fr.at(-w1, t1, d1), fr.n, face);
        b.quad(fr.at(-w0, t0, -d0), fr.at(-w1, t1, -d1), fr.at(w1, t1, -d1), fr.at(w0, t0, -d0), back, side);
        // The rims.
        const out = mathx.normV(mathx.crossV(mathx.subV(fr.at(w1, t1, 0), fr.at(w0, t0, 0)), fr.n));
        b.quad(fr.at(w0, t0, -d0), fr.at(w1, t1, -d1), fr.at(w1, t1, d1), fr.at(w0, t0, d0), out, side);
        b.quad(fr.at(-w0, t0, -d0), fr.at(-w0, t0, d0), fr.at(-w1, t1, d1), fr.at(-w1, t1, -d1), v3(-out.x, -out.y, -out.z), side);
    }
}

/// A FLAT ROUND FACE lying ON a plate — the sound hole and its rosette.
pub fn faceDiscInto(b: *Builder, fr: Frame, across: f32, along: f32, out: f32, r: f32, sides: i32, col: rl.Color) void {
    const c = fr.at(across, along, out);
    const sf: f32 = @floatFromInt(sides);
    var s: i32 = 0;
    while (s < sides) : (s += 2) {
        const a0 = std.math.tau * @as(f32, @floatFromInt(s)) / sf;
        const a1 = std.math.tau * @as(f32, @floatFromInt(s + 1)) / sf;
        const a2 = std.math.tau * @as(f32, @floatFromInt(s + 2)) / sf;
        b.quad(c, fr.ring(across, along, out, r, a0), fr.ring(across, along, out, r, a1), fr.ring(across, along, out, r, a2), fr.n, col);
    }
}

/// THE GUITAR BODY'S OUTLINE, in metres up the instrument's axis from its tail: (along, half-width, half-depth).
const GUITAR_BODY = [_][3]f32{
    .{ 0.000, 0.023, 0.030 },
    .{ 0.024, 0.104, 0.046 },
    .{ 0.058, 0.158, 0.053 },
    .{ 0.104, 0.190, 0.056 },
    .{ 0.152, 0.198, 0.056 }, // lower bout, at its widest
    .{ 0.208, 0.191, 0.055 },
    .{ 0.258, 0.164, 0.053 },
    .{ 0.300, 0.135, 0.051 }, // THE WAIST — 0.68 of the bout, which is what names the silhouette
    .{ 0.344, 0.145, 0.049 },
    .{ 0.394, 0.165, 0.047 },
    .{ 0.444, 0.166, 0.045 }, // upper bout
    .{ 0.488, 0.138, 0.043 },
    .{ 0.520, 0.070, 0.042 }, // the heel the neck goes into
};

/// The instrument's whole length up `fr.a`, so a caller can seat it or prop it without re-deriving where the headstock ends up.
pub const GUITAR_LEN: f32 = 1.0;

/// ONE GUITAR, in `fr`: `fr.o` is where the body's TAIL sits, `fr.a` runs up the neck and `fr.n` is the soundboard's outward normal.
pub fn guitarInto(b: *Builder, fr: Frame) void {
    b.setMat(.wood);
    plateInto(b, fr, &GUITAR_BODY, SPRUCE, TIMBER_DK);
    // THE SOUND HOLE at 0.63 of the body — over the waist, where it belongs — ringed by a rosette, because at this albedo nothing in this renderer goes black and a bare dark disc reads as a stain.
    faceDiscInto(b, fr, 0, 0.330, 0.052, 0.070, 14, BONE);
    faceDiscInto(b, fr, 0, 0.330, 0.054, 0.055, 14, BARK_OLD);
    // THE BRIDGE and its saddle, a quarter of the way up the lower bout — and both kept LOW.
    b.addBox(fr.at(0, 0.128, 0.062), fr.axis(0.058, 0, 0), fr.axis(0, 0.013, 0), fr.axis(0, 0, 0.007), BARK_OLD);
    b.addBox(fr.at(0, 0.132, 0.0715), fr.axis(0.050, 0, 0), fr.axis(0, 0.003, 0), fr.axis(0, 0, 0.0025), BONE);
    // THE NECK, flush at the front with the soundboard, and its fretboard laid on top.
    b.addBox(fr.at(0, 0.690, 0.026), fr.axis(0.029, 0, 0), fr.axis(0, 0.175, 0), fr.axis(0, 0, 0.016), TIMBER_DK);
    b.addBox(fr.at(0, 0.700, 0.048), fr.axis(0.027, 0, 0), fr.axis(0, 0.165, 0), fr.axis(0, 0, 0.006), BARK_OLD);
    // FRETS at the real equal-temperament positions off the 0.737 m nut-to-saddle scale — the spacing CLOSING as it runs down toward the body is what makes a neck read as a neck instead of a stick.
    for ([_]f32{ 1, 3, 5, 7, 9 }) |semis| {
        const t = 0.865 - 0.737 * (1.0 - std.math.pow(f32, 2.0, -semis / 12.0));
        b.addBox(fr.at(0, t, 0.0555), fr.axis(0.027, 0, 0), fr.axis(0, 0.0025, 0), fr.axis(0, 0, 0.0015), BONE);
    }
    b.addBox(fr.at(0, 0.868, 0.0555), fr.axis(0.028, 0, 0), fr.axis(0, 0.004, 0), fr.axis(0, 0, 0.004), BONE); // the nut
    // THE HEADSTOCK, broken back off the neck the way a real one is — a head in line with the fretboard is the single detail that makes a guitar look like a toy.
    const hc = mathx.cosf(0.22);
    const hs = mathx.sinf(0.22);
    const hd = Frame{
        .o = fr.at(0, 0.872, 0.022),
        .w = fr.w,
        .a = mathx.subV(mathx.scaleV(fr.a, hc), mathx.scaleV(fr.n, hs)),
        .n = mathx.addV(mathx.scaleV(fr.n, hc), mathx.scaleV(fr.a, hs)),
        .s = fr.s,
    };
    b.addBox(hd.at(0, 0.072, 0), hd.axis(0.037, 0, 0), hd.axis(0, 0.072, 0), hd.axis(0, 0, 0.012), TIMBER_DK);
    // …and its TUNERS, one per string, all down one side like a slotted head.
    b.setMat(.steel);
    for ([_]f32{ 0.030, 0.072, 0.114 }) |t| {
        b.addCapsule(hd.at(0.030, t, 0), hd.at(0.060, t, 0), 0.005, 0.005, 5, BRASS);
        b.addBox(hd.at(0.072, t, 0), hd.axis(0.011, 0, 0), hd.axis(0, 0.014, 0), hd.axis(0, 0, 0.004), BONE);
    }
    // THE STRINGS, saddle to tuner in two runs so the second one fans out to the pegs, and fanning WIDER at the bridge than at the nut the way a real set does.
    for ([_]f32{ -0.026, 0, 0.026 }, [_]f32{ -0.019, 0, 0.019 }, [_]f32{ 0.030, 0.072, 0.114 }) |low, high, peg| {
        b.addCapsule(fr.at(low, 0.130, 0.0725), fr.at(high, 0.866, 0.058), 0.0022, 0.0022, 4, IRON);
        b.addCapsule(fr.at(high, 0.866, 0.058), hd.at(0.034, peg, 0.006), 0.0022, 0.0022, 4, IRON);
    }
}

// A single golden grass clump.
