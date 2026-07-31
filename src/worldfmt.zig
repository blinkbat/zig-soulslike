const std = @import("std");
const props = @import("props.zig");
const mathx = @import("mathx.zig");
const gfx = @import("gfx.zig");

const Kind = props.Kind;

// ── THE MAP ── the world is DATA: a versioned text file of authoring OPS, replayed in order by
// env.zig; the editor is the only thing that writes one.
//
// The ops are the AUTHORING, not its output. A wood is one `belt` of 260 attempts with a mix and an
// edge gradient, not 260 coordinates — so the file stays readable in a diff and a density dial
// re-expands it instead of stamping instances.
//
// EVERY GENERATOR OP CARRIES ITS OWN SEED and gets its own Rng. That is the load-bearing difference
// from the code-authored world it replaces, which drew every op from ONE shared stream: there,
// inserting a belt re-rolled every op after it, so no edit was ever local. The world is deterministic
// either way; independent seeds are what make it EDITABLE.
//
// FORMAT — one record per line, `#` comments, blank lines ignored:
//     <name> <required positionals, in fieldsOf() order> [key=value ...]
// The positionals come from ONE table both the writer and the parser walk, so a field added to one
// can't go missing from the other; the optional tail carries the sparse dials, matched by field name.
// An unknown key, a missing positional or a value that only LOOKS parseable is a LOAD ERROR, never a
// silent default — a map that half-loads is a world with a hole in it, a long way from the typo.

pub const VERSION: u32 = 1;

/// Playable half-extent when a map doesn't say otherwise; the world spans 2x this per axis. THE MAP IS
/// THE ONLY SOURCE — the movement clamp, the cliff ring, the cover extent and the soil grid all read
/// `Map.half`. `env.MAX_HALF` is the ceiling the fixed grid can index and env's tests pin this default
/// under it. Lives here because env imports this file, not the other way round.
pub const DEFAULT_HALF: f32 = 280.0;

/// Sanity bound on a `half:` record, and a POSITIVE one. Not the design limit (`env.MAX_HALF` is), but
/// the cover lattice is O((half/pitch)²) candidates, so an absurd value is a HANG at load rather than
/// a big world — and a zero or negative half inverts every derived extent.
pub const MAX_DECLARED_HALF: f32 = 4096.0;

pub const MAX_OPS: usize = 2048;
pub const MAX_MIX: usize = 24; // a scatter's weighted kind mix (weight = repetition)
pub const MAX_ZONES: usize = 16;
pub const MAX_CLEARINGS: usize = 32;
pub const MAX_FOES: usize = 256;
pub const NAME_CAP: usize = 48;

// ── ops ────────────────────────────────────────────────────────────────────────────────

pub const OpKind = enum(u8) {
    /// One prop, placed exactly. No RNG, no seed — what the editor stamps and drags.
    at,
    /// Rect scatter: `n` ATTEMPTS in a box, rejected against the avoid set and the cover field.
    /// Attempts, not a guarantee — rejection is what keeps a scatter from reading sown.
    belt,
    /// Annulus scatter about a centre, r0..r1 — shorelines, reed beds, talus, drowned ruin.
    disc,
    /// Evenly spaced ring facing its centre, one position left out (`skip`): a full ring reads as a fence.
    ring,
    /// A broken run from a→b: segments nose to tail, some collapsed. City walls.
    line,
    /// Sow a climber at the FEET of stonework already standing in a box — ivy needs a wall behind it,
    /// so this walks the props that are THERE rather than scattering over ground.
    ivy,
    /// The world's rock rim: four walls of overlapping cliff segments, height from two long waves so
    /// the crest reads as topography rather than jitter.
    edge,
    /// The lattice ground cover over the whole world: one candidate per cell, kind and density from the
    /// zone it lands in, scaled by the cover field. Exactly one per map.
    cover,
};

/// What a scatter refuses to grow through. Defaults differ per op kind, and the editor exposes them as
/// tick boxes — a belt that ignores water is how you sow lilies.
pub const Avoid = struct {
    runway: bool = false, // the hero's start lane, kept clear so a straight walk out is never blocked
    water: bool = false, // open water
    clear: bool = false, // the authored clearings
    solid: bool = false, // anything with a footprint collider (queried against the solid grid)
};

/// Which axis a belt's density gradient runs along; `.none` is a flat belt.
pub const Axis = enum(u8) { none, x, z };

/// One authoring operation. FLAT rather than a tagged union: the properties panel pokes fields by name,
/// `fieldsOf` decides which ones a kind uses, and the unused ones cost a few bytes and no ceremony.
pub const Op = struct {
    op: OpKind = .at,
    kind: Kind = .pillar, // the prop placed, or the mix's fallback when `nmix` is 0
    x: f32 = 0, // point / rect min / centre / line start
    z: f32 = 0,
    x1: f32 = 0, // rect max / line end
    z1: f32 = 0,
    r0: f32 = 0, // disc inner radius / ring radius / line segment length / edge step
    r1: f32 = 0, // disc outer radius
    yaw: f32 = 0,
    scale: f32 = 1,
    /// TIP THE PROP OFF PLUMB: `lean` degrees, toward the compass direction `leanDir` (measured
    /// like yaw). A literal `at` leans exactly this much and in exactly that direction; a SCATTER
    /// reads `lean` as the MOST any one instance gets and rolls both amount and direction per
    /// instance, so a wood leans every which way instead of as one hurricane-struck block. 0 =
    /// plumb, which is every op's default — nothing in a map without these keys draws from its
    /// stream, so adding the field cannot reshuffle a world.
    lean: f32 = 0,
    leanDir: f32 = 0,
    sLo: f32 = 0.85, // scale band the instances draw from
    sHi: f32 = 1.15,
    n: i32 = 0, // attempts (belt/disc), positions (ring), talus count (edge)
    skip: i32 = -1, // ring: the position left empty; -1 = none
    seed: u64 = 0,
    chance: f32 = 1.0, // per-candidate acceptance (ivy takes, line segment survives)
    /// Disc radial bias: 0 spreads evenly across the annulus, 1 is area-uniform (sqrt), clustering
    /// toward the inner edge — how a lily raft sits on its rootstock.
    bias: f32 = 0,
    /// Respect the world's COVER FIELD (the noise that carves clearings, so a clearing is a clearing for
    /// everything standing in it)? On for belts. OFF for a scatter that carries its own shaping (the
    /// canopy's gradient) or has no business thinning (a shoreline reed bed): double-dipping thins it
    /// twice and the second one is invisible in the numbers.
    field: bool = false,
    /// Belt density gradient: acceptance ramps `gFloor`→1 as the axis runs gA→gB. What stops a wood
    /// ending in a hard tree line that reads as a wall of scenery.
    gAxis: Axis = .none,
    gA: f32 = 0,
    gB: f32 = 0,
    gFloor: f32 = 0,
    avoid: Avoid = .{},
    /// Weighted kind mix, weight BY REPETITION — the cheapest honest weighting for a small set, and it
    /// keeps a region's character readable as one line of text. Empty = use `kind`.
    mix: [MAX_MIX]Kind = undefined,
    nmix: u8 = 0,

    /// The kind this op places for one instance.
    pub fn pick(self: *const Op, r: *mathx.Rng) Kind {
        if (self.nmix == 0) return self.kind;
        return self.mix[@intCast(r.intn(@intCast(self.nmix)))];
    }

    /// This op's own generator, independent of every other op's.
    pub fn stream(self: *const Op) mathx.Rng {
        return mathx.Rng.init(self.seed);
    }

    /// The gradient's acceptance multiplier at a point (1 where there is no gradient).
    pub fn gradAt(self: *const Op, px: f32, pz: f32) f32 {
        const v = switch (self.gAxis) {
            .none => return 1.0,
            .x => px,
            .z => pz,
        };
        return self.gFloor + (1.0 - self.gFloor) * mathx.smoothstep(self.gA, self.gB, v);
    }
};

// The REQUIRED positionals per op kind, in the order written and read. ONE table, both directions —
// the whole defence against a writer and a parser that agree today and disagree after the next field.
// A comptime function because the walk must run at COMPTIME to index the struct by name. Driving it off
// `std.meta.fields(Op)` reads the STRUCT's order instead, silently ignoring this table and writing `n`
// in the wrong column the moment the two disagree.
fn fieldsOf(comptime k: OpKind) []const []const u8 {
    return switch (k) {
        .at => &.{ "kind", "x", "z", "yaw", "scale" },
        .belt => &.{ "kind", "x", "z", "x1", "z1", "n", "sLo", "sHi" },
        .disc => &.{ "kind", "x", "z", "r0", "r1", "n", "sLo", "sHi" },
        .ring => &.{ "kind", "x", "z", "r0", "n", "sLo", "sHi" },
        .line => &.{ "kind", "x", "z", "x1", "z1", "r0", "sLo", "sHi" },
        .ivy => &.{ "kind", "x", "z", "x1", "z1", "sLo", "sHi" },
        .edge => &.{ "kind", "r0", "n", "sLo", "sHi" },
        .cover => &.{ "r0", "sLo", "sHi" }, // r0 = lattice pitch
    };
}

comptime {
    // Every name in the table must BE a field of Op. A typo here would otherwise surface as a
    // compile error deep inside @field, pointing at the walk rather than at the table.
    @setEvalBranchQuota(20000);
    for (@typeInfo(OpKind).@"enum".fields) |ek| {
        const k: OpKind = @enumFromInt(ek.value);
        for (fieldsOf(k)) |name| {
            if (!@hasField(Op, name)) @compileError("worldfmt: " ++ @tagName(k) ++ " names a field Op does not have: " ++ name);
        }
    }
}

// Per-kind defaults for the non-positional fields, so a hand-written line behaves the way that op is
// meant to without spelling out every dial.
pub fn defaults(k: OpKind) Op {
    var o = Op{ .op = k };
    switch (k) {
        .at => {},
        .belt => {
            o.avoid = .{ .runway = true, .water = true };
            o.field = true;
        },
        .disc => {},
        .ring => o.skip = -1,
        .line => o.chance = 0.78, // ~a fifth of the run has fallen
        .ivy => o.chance = 0.55,
        .edge => {},
        .cover => o.avoid = .{ .runway = true, .water = true, .solid = true },
    }
    return o;
}

// ── the tables an op is read against ───────────────────────────────────────────────────

/// What the lattice scatter grows inside this rect, and how thickly WHERE IT IS THICKEST: `density` is
/// the PEAK and the cover field scales it down to nothing in the clearings. Tested in order, FIRST
/// containing rect wins — so a small zone laid after a large one cuts a hole in it.
pub const Zone = struct {
    name: [NAME_CAP]u8 = [_]u8{0} ** NAME_CAP,
    x: f32 = 0,
    z: f32 = 0,
    x1: f32 = 0,
    z1: f32 = 0,
    density: f32 = 0.6,
    mix: [MAX_MIX]Kind = undefined,
    nmix: u8 = 0,

    pub fn contains(self: *const Zone, px: f32, pz: f32) bool {
        return px >= self.x and px <= self.x1 and pz >= self.z and pz <= self.z1;
    }
    /// OPTIONAL, not a fallback kind: `mix` is `undefined` until filled and `Rng.intn(0)` returns 0, so
    /// an unguarded version read raw heap bytes as a `props.Kind` — an out-of-range enum, illegal
    /// whatever those bytes are. `parseZone` rejects an empty mix too; this is the second lock on the
    /// same door, since the editor can hold a zone in that state between a drag and its seeding.
    pub fn pick(self: *const Zone, rng: *mathx.Rng) ?Kind {
        if (self.nmix == 0) return null;
        return self.mix[@intCast(rng.intn(@intCast(self.nmix)))];
    }
    pub fn label(self: *const Zone) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }
};

/// A circle the canopy and the cover scatter keep out of — the stone circle's glade, the cottage yard.
/// A clearing you authored is worth more than one the noise happened to leave.
pub const Clearing = struct { x: f32 = 0, z: f32 = 0, r: f32 = 12 };

pub const FoeKind = enum(u8) { toad, archer, ogre };

/// One posted spawn. `yaw` is DEGREES like every yaw in the format (the rigs take radians; the loader
/// converts). `seed` is the per-instance animation phase in 0..1 — what stops a knot of toads breathing
/// and hopping as one body.
pub const Foe = struct {
    kind: FoeKind = .toad,
    x: f32 = 0,
    z: f32 = 0,
    yaw: f32 = 0,
    scale: f32 = 1,
    seed: f32 = 0,
};

/// How many of ONE kind a map may post. Each group keeps a fixed array this size.
pub const MAX_PER_KIND: usize = 24;

/// The hero's start lane, kept clear of every scatter (the `--shot` corridor and the live start), so
/// walking straight out of the grace is never blocked by something that grew.
pub const Runway = struct { x: f32 = -3.4, z: f32 = -44, x1: f32 = 3.4, z1: f32 = 30 };

// ── the painted soil ───────────────────────────────────────────────────────────────────
// A material id per grid cell, 0 = UNPAINTED, meaning "leave the procedural ground exactly as it is" —
// so the authored look survives painting by construction and a fresh map's grid is empty.

pub const SOIL_N: usize = @intCast(gfx.SOIL_N);
pub const SOIL_CELLS: usize = SOIL_N * SOIL_N;

pub const Soil = enum(u8) {
    none, // unpainted — the procedural floor shows through untouched
    dirt,
    turf,
    stone,
    silt,
    ash,
    moss,

    pub const N = @typeInfo(Soil).@"enum".fields.len;
};

comptime {
    // The shader's soilColor() hard-codes ids 1..6 and falls through to moss. Adding a soil
    // without extending it would paint the new material as moss, silently.
    std.debug.assert(Soil.N == 7);
}

// ── the painted WATER ───────────────────────────────────────────────────────────────────
// A second painted grid, and a much simpler one: one BIT per cell — wet or dry. Everything that
// makes water read as water (where the coast is, how the shallows fade into the deep, where the sand
// is soaked) is DERIVED from this mask by env's signed distance field, never painted by hand. That
// is the whole design: painting a lake is painting its OUTLINE, and the gradient is arithmetic.
//
// Finer than the soil grid, because a shoreline is a shape you read and a material patch is not.
pub const WATER_N: usize = @intCast(gfx.WATER_N);
pub const WATER_CELLS: usize = WATER_N * WATER_N;

// ── the sculpted ELEVATION ───────────────────────────────────────────────────────────────
// The third painted grid, and the only one with a datum: one QUANTISED HEIGHT per lattice point,
// `HEIGHT_STEP` metres a step, biased so byte `HEIGHT_ZERO` is the old flat ground. A fresh map is
// every cell at that datum, which is byte-identical in behaviour to the world before elevation
// existed — and RLEs to a single run, so a flat map's file does not grow at all.
//
// QUANTISED because the file is TEXT and the writer is a run-length encoder. A float grid would be
// 50,176 unique values, i.e. an unreadable megabyte with no runs in it; a 0.25 m step is finer than
// a foot and lets a plateau, a bank and a flat valley floor each collapse to one run. It is also the
// visible limit on smoothness — a long shallow ramp is a staircase of 0.25 m risers 2.5 m apart,
// which at 5.7 degrees is under the mesh's own faceting.
//
// SAMPLED AT LATTICE POINTS, NOT CELL CENTRES (unlike soil and water, which are cell PAINT). A
// height is a corner of the terrain mesh: N points span -half..+half inclusive, so the field's edge
// lands exactly on the world's edge and there is no half-cell of unexplained ground at the rim.
pub const HEIGHT_N: usize = @intCast(gfx.HEIGHT_N);
pub const HEIGHT_CELLS: usize = HEIGHT_N * HEIGHT_N;
/// Metres per quantisation step.
pub const HEIGHT_STEP: f32 = 0.25;
/// The byte that means "ground level" — everything below it is dug out, above it raised.
pub const HEIGHT_ZERO: u8 = 64;
/// How far the encoding reaches: 16 m down (deep enough for any basin) and ~48 m up.
pub const HEIGHT_MIN: f32 = -@as(f32, @floatFromInt(HEIGHT_ZERO)) * HEIGHT_STEP;
pub const HEIGHT_MAX: f32 = @as(f32, @floatFromInt(255 - HEIGHT_ZERO)) * HEIGHT_STEP;

/// Byte → metres, and the inverse. The only two places the encoding is spelled out.
pub fn heightOf(b: u8) f32 {
    return (@as(f32, @floatFromInt(b)) - @as(f32, @floatFromInt(HEIGHT_ZERO))) * HEIGHT_STEP;
}
pub fn heightByte(m: f32) u8 {
    const q = @round(m / HEIGHT_STEP) + @as(f32, @floatFromInt(HEIGHT_ZERO));
    return @intFromFloat(mathx.clampF(q, 0, 255));
}

/// THE ONE HEIGHT SAMPLER — bilinear over an `HEIGHT_N` lattice spanning `-half..+half` inclusive.
/// Free function over a slice rather than a method, because the field has two owners that must agree
/// to the millimetre: the MAP holds the authored grid and the editor sculpts it, while `env` keeps
/// the live copy the terrain mesh was built from and every actor stands on. Two implementations of
/// this is a hero who walks a centimetre off the mesh he can see.
pub fn sampleHeight(field: []const u8, half: f32, px: f32, pz: f32) f32 {
    std.debug.assert(field.len == HEIGHT_CELLS);
    const last: f32 = @floatFromInt(HEIGHT_N - 1);
    const step = 2 * half / last; // POINT pitch: N points, N-1 gaps
    // Clamped rather than zeroed outside: past the rim the ground continues at the edge's height,
    // which is what the terrain skirt draws and what keeps an actor at the bound from falling.
    const fx = mathx.clampF((px + half) / step, 0, last);
    const fz = mathx.clampF((pz + half) / step, 0, last);
    const x0: usize = @intFromFloat(@floor(fx));
    const z0: usize = @intFromFloat(@floor(fz));
    const x1 = @min(x0 + 1, HEIGHT_N - 1);
    const z1 = @min(z0 + 1, HEIGHT_N - 1);
    const tx = fx - @floor(fx);
    const tz = fz - @floor(fz);
    const h00 = heightOf(field[z0 * HEIGHT_N + x0]);
    const h10 = heightOf(field[z0 * HEIGHT_N + x1]);
    const h01 = heightOf(field[z1 * HEIGHT_N + x0]);
    const h11 = heightOf(field[z1 * HEIGHT_N + x1]);
    return mathx.lerpF(mathx.lerpF(h00, h10, tx), mathx.lerpF(h01, h11, tx), tz);
}

/// The terrain's GRADIENT at a point: (dh/dx, dh/dz), i.e. metres of rise per metre travelled. Its
/// length is the tangent of the slope angle, which is what the walkable test and the hero's lean read.
///
/// Measured over a whole cell either side rather than at the sample: the field is bilinear, so its
/// true derivative is piecewise-constant and JUMPS at every lattice line — a lean driven off that
/// steps visibly as you cross one, and a slope limit driven off it turns a smooth bank into stripes.
pub fn sampleGrad(field: []const u8, half: f32, px: f32, pz: f32) [2]f32 {
    const step = 2 * half / @as(f32, @floatFromInt(HEIGHT_N - 1));
    const hx1 = sampleHeight(field, half, px + step, pz);
    const hx0 = sampleHeight(field, half, px - step, pz);
    const hz1 = sampleHeight(field, half, px, pz + step);
    const hz0 = sampleHeight(field, half, px, pz - step);
    return .{ (hx1 - hx0) / (2 * step), (hz1 - hz0) / (2 * step) };
}

/// A touched-lattice rect that contains nothing, as `lo > hi` on both axes — what `Map.sculpt` reports
/// for a stroke that missed the grid, so a caller's rebuild loops simply do not run.
pub const EMPTY_SPAN: [4]usize = .{ 1, 1, 0, 0 };

/// The lattice-point index range a brush of radius `r` centred at `c` reaches on one axis, INCLUSIVE,
/// or null when it misses the grid entirely. Signed internally on purpose: clamping first would turn a
/// brush a hundred metres off the map into a hit on point 0.
fn pointSpan(c: f32, r: f32, half: f32, step: f32) ?[2]usize {
    const last: f32 = @floatFromInt(HEIGHT_N - 1);
    const a = @ceil((c - r + half) / step);
    const b = @floor((c + r + half) / step);
    if (b < 0 or a > last) return null;
    const lo = mathx.clampF(a, 0, last);
    const hi = mathx.clampF(b, 0, last);
    if (lo > hi) return null;
    return .{ @intFromFloat(lo), @intFromFloat(hi) };
}

/// What a sculpt brush does to the ground under it.
pub const Sculpt = enum {
    /// Push the ground up by `amount` metres at the centre, tapering to nothing at the rim.
    raise,
    /// …and down.
    lower,
    /// Pull every point toward the average of its neighbours — the dial that turns a lumpy raise
    /// into a bank you can walk. Without it a brush stroke is all cliffs.
    smooth,
    /// Flatten toward the height under the brush's centre — terraces, building pads, a road.
    flatten,
};

// ── the map ────────────────────────────────────────────────────────────────────────────

pub const Map = struct {
    name: [NAME_CAP]u8 = [_]u8{0} ** NAME_CAP,
    /// Playable half-extent. The movement clamp and the cliff rim are derived from it.
    half: f32 = DEFAULT_HALF,
    runway: Runway = .{},

    ops: [MAX_OPS]Op = undefined,
    nops: usize = 0,
    zones: [MAX_ZONES]Zone = undefined,
    nzones: usize = 0,
    clearings: [MAX_CLEARINGS]Clearing = undefined,
    nclearings: usize = 0,
    foes: [MAX_FOES]Foe = undefined,
    nfoes: usize = 0,
    /// The painted soil, row-major from -half to +half on both axes. All zero = nothing painted.
    soil: [SOIL_CELLS]u8 = [_]u8{0} ** SOIL_CELLS,
    /// The painted WATER MASK, same layout, 1 = wet. Depth, shoreline and wet sand are all derived
    /// from it (see env.uploadWater) — this is only the outline.
    water: [WATER_CELLS]u8 = [_]u8{0} ** WATER_CELLS,
    /// THE SCULPTED GROUND: one quantised height per lattice POINT (see the HEIGHT block above).
    /// Defaults to the DATUM, not to zero — an all-zero grid would sink the whole world 16 m.
    height: [HEIGHT_CELLS]u8 = [_]u8{HEIGHT_ZERO} ** HEIGHT_CELLS,

    pub fn label(self: *const Map) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }

    pub fn setName(self: *Map, s: []const u8) void {
        self.name = [_]u8{0} ** NAME_CAP;
        const n = @min(s.len, NAME_CAP - 1);
        @memcpy(self.name[0..n], s[0..n]);
    }

    pub fn clear(self: *Map) void {
        self.nops = 0;
        self.nzones = 0;
        self.nclearings = 0;
        self.nfoes = 0;
        self.soil = [_]u8{0} ** SOIL_CELLS;
        self.water = [_]u8{0} ** WATER_CELLS;
        // To the DATUM, not to zero: `@memset(.., 0)` here would drop the ground to HEIGHT_MIN.
        self.height = [_]u8{HEIGHT_ZERO} ** HEIGHT_CELLS;
    }

    /// The smallest VALID map: a world-spanning fallback zone plus the cover op that reads it. A truly
    /// empty map fails its own loader (`NoCoverOp`) and shows as bare terrain, so "New" must hand back
    /// something that loads and grows grass.
    pub fn blank(self: *Map, name: []const u8) void {
        self.* = .{};
        self.setName(name);
        var z = Zone{ .x = -4000, .z = -4000, .x1 = 4000, .z1 = 4000, .density = 0.7 };
        const mix = [_]Kind{ .grasstall, .grasstall, .patch, .tuft, .clover, .moss, .wildflowers };
        for (mix, 0..) |k, i| z.mix[i] = k;
        z.nmix = mix.len;
        @memcpy(z.name[0..5], "plain");
        self.zones[0] = z;
        self.nzones = 1;

        var cover = defaults(.cover);
        cover.r0 = 3.3; // lattice pitch
        cover.sLo = 0.72;
        cover.sHi = 1.38;
        cover.seed = 1001;
        self.ops[0] = cover;
        self.nops = 1;

        // The rim, so a new map is bounded terrain rather than a plane running into haze.
        var rim = defaults(.edge);
        rim.kind = .cliff;
        rim.r0 = 6.5;
        rim.n = 90;
        rim.sLo = 0.92;
        rim.sHi = 1.24;
        rim.seed = 1002;
        for (props.CLIFFS, 0..) |k, i| rim.mix[i] = k;
        rim.nmix = props.CLIFFS.len;
        // Before the cover op: the ground cover queries the solid grid, so the rim has to exist
        // by then or grass grows through the cliffs.
        self.ops[1] = self.ops[0];
        self.ops[0] = rim;
        self.nops = 2;
    }

    /// Append an op, returning its index. Capacity overflow is a hard error rather than a
    /// silent drop: a dropped op is a missing region, and nothing downstream would say so.
    pub fn add(self: *Map, o: Op) !usize {
        if (self.nops >= MAX_OPS) return error.TooManyOps;
        self.ops[self.nops] = o;
        self.nops += 1;
        return self.nops - 1;
    }

    pub fn remove(self: *Map, i: usize) void {
        if (i >= self.nops) return;
        std.mem.copyForwards(Op, self.ops[i .. self.nops - 1], self.ops[i + 1 .. self.nops]);
        self.nops -= 1;
    }

    /// Move an op to a new position in the replay order. Order is meaningful — `ivy` reads the
    /// stonework placed before it, and the cover scatter must run after everything solid.
    pub fn reorder(self: *Map, from: usize, to: usize) void {
        if (from >= self.nops or to >= self.nops or from == to) return;
        const moved = self.ops[from];
        if (from < to) {
            std.mem.copyForwards(Op, self.ops[from..to], self.ops[from + 1 .. to + 1]);
        } else {
            std.mem.copyBackwards(Op, self.ops[to + 1 .. from + 1], self.ops[to..from]);
        }
        self.ops[to] = moved;
    }

    pub fn slice(self: *const Map) []const Op {
        return self.ops[0..self.nops];
    }

    /// The zone governing a point — first containing rect wins, last zone is the fallback.
    pub fn zoneAt(self: *const Map, px: f32, pz: f32) ?*const Zone {
        if (self.nzones == 0) return null;
        for (self.zones[0..self.nzones]) |*z| {
            if (z.contains(px, pz)) return z;
        }
        return &self.zones[self.nzones - 1];
    }

    pub fn onRunway(self: *const Map, px: f32, pz: f32) bool {
        const r = self.runway;
        return px >= r.x and px <= r.x1 and pz >= r.z and pz <= r.z1;
    }

    /// The world size of one cell of an `n`-a-side painted grid. Both grids span `-half..+half`, so
    /// this one expression is the SOIL grid's pitch, the WATER grid's pitch, and what the properties
    /// panel prints as "cell N m" — it was written out at each of those sites, and a pitch that
    /// disagreed with the grid it indexes puts a brush stroke in the wrong cells.
    pub fn cellSize(self: *const Map, n: usize) f32 {
        return 2 * self.half / @as(f32, @floatFromInt(n));
    }

    /// World position → soil cell index, or null when it falls outside the grid.
    pub fn soilIndex(self: *const Map, px: f32, pz: f32) ?usize {
        const t = (px + self.half) / (2 * self.half);
        const u = (pz + self.half) / (2 * self.half);
        if (t < 0 or t >= 1 or u < 0 or u >= 1) return null;
        const cx: usize = @intFromFloat(t * @as(f32, @floatFromInt(SOIL_N)));
        const cz: usize = @intFromFloat(u * @as(f32, @floatFromInt(SOIL_N)));
        return @min(cz, SOIL_N - 1) * SOIL_N + @min(cx, SOIL_N - 1);
    }

    /// Paint a disc of soil. Returns whether anything actually changed, so a stroke that lands
    /// on ground already that material doesn't bank an undo step or raise the dirty flag.
    pub fn paintSoil(self: *Map, px: f32, pz: f32, radius: f32, id: Soil) bool {
        const cell = self.cellSize(SOIL_N);
        const r2 = radius * radius;
        var changed = false;
        var cz: usize = 0;
        while (cz < SOIL_N) : (cz += 1) {
            const wz = -self.half + (@as(f32, @floatFromInt(cz)) + 0.5) * cell;
            if (@abs(wz - pz) > radius + cell) continue;
            var cx: usize = 0;
            while (cx < SOIL_N) : (cx += 1) {
                const wx = -self.half + (@as(f32, @floatFromInt(cx)) + 0.5) * cell;
                const dx = wx - px;
                const dz = wz - pz;
                if (dx * dx + dz * dz > r2) continue;
                const i = cz * SOIL_N + cx;
                const v: u8 = @intFromEnum(id);
                if (self.soil[i] != v) {
                    self.soil[i] = v;
                    changed = true;
                }
            }
        }
        return changed;
    }

    /// Paint (or wipe) a disc of the WATER MASK. Same shape as `paintSoil` — and deliberately the
    /// same shape, because they are the same gesture on two grids — but on the finer lattice and with
    /// only two values. Returns whether anything changed.
    pub fn paintWater(self: *Map, px: f32, pz: f32, radius: f32, wet: bool) bool {
        const cell = self.cellSize(WATER_N);
        const r2 = radius * radius;
        const v: u8 = if (wet) 1 else 0;
        var changed = false;
        var cz: usize = 0;
        while (cz < WATER_N) : (cz += 1) {
            const wz = -self.half + (@as(f32, @floatFromInt(cz)) + 0.5) * cell;
            if (@abs(wz - pz) > radius + cell) continue;
            var cx: usize = 0;
            while (cx < WATER_N) : (cx += 1) {
                const wx = -self.half + (@as(f32, @floatFromInt(cx)) + 0.5) * cell;
                const dx = wx - px;
                const dz = wz - pz;
                if (dx * dx + dz * dz > r2) continue;
                const i = cz * WATER_N + cx;
                if (self.water[i] != v) {
                    self.water[i] = v;
                    changed = true;
                }
            }
        }
        return changed;
    }

    /// Is this cell of the mask wet? Out-of-grid is dry.
    pub fn waterAt(self: *const Map, px: f32, pz: f32) bool {
        const t = (px + self.half) / (2 * self.half);
        const u = (pz + self.half) / (2 * self.half);
        if (t < 0 or t >= 1 or u < 0 or u >= 1) return false;
        const cx: usize = @min(@as(usize, @intFromFloat(t * @as(f32, @floatFromInt(WATER_N)))), WATER_N - 1);
        const cz: usize = @min(@as(usize, @intFromFloat(u * @as(f32, @floatFromInt(WATER_N)))), WATER_N - 1);
        return self.water[cz * WATER_N + cx] != 0;
    }

    /// Has anything been painted wet at all? What lets the renderer skip the sheet entirely.
    pub fn anyWater(self: *const Map) bool {
        for (self.water) |v| {
            if (v != 0) return true;
        }
        return false;
    }

    /// The ground height at a world position, in metres above the old flat datum.
    pub fn heightAt(self: *const Map, px: f32, pz: f32) f32 {
        return sampleHeight(&self.height, self.half, px, pz);
    }

    /// The terrain gradient there — (dh/dx, dh/dz).
    pub fn gradAt(self: *const Map, px: f32, pz: f32) [2]f32 {
        return sampleGrad(&self.height, self.half, px, pz);
    }

    /// Has the ground been sculpted at all? What lets the renderer keep the old single-quad plane.
    pub fn anyHeight(self: *const Map) bool {
        for (self.height) |v| {
            if (v != HEIGHT_ZERO) return true;
        }
        return false;
    }

    /// The world position of height lattice point (ix, iz) — the mesh's own corner grid.
    pub fn heightPoint(self: *const Map, ix: usize, iz: usize) [2]f32 {
        const step = 2 * self.half / @as(f32, @floatFromInt(HEIGHT_N - 1));
        return .{ -self.half + @as(f32, @floatFromInt(ix)) * step, -self.half + @as(f32, @floatFromInt(iz)) * step };
    }

    /// SCULPT the ground under a brush. `amount` is metres for raise/lower and a 0..1 strength for
    /// smooth/flatten; returns whether anything changed (so a stroke that achieves nothing banks no
    /// undo step, exactly like `paintSoil`).
    ///
    /// The falloff is a SMOOTHSTEP over the radius, not a disc: a flat-topped brush leaves a cylinder
    /// with a vertical wall around it — unwalkable by construction, so every stroke would need
    /// smoothing afterwards to be usable at all. Cosine-shouldered, the raise brush alone already
    /// produces banks you can climb.
    ///
    /// `out` receives the rect of lattice points touched (lo x, lo z, hi x, hi z inclusive) so the
    /// caller can rebuild just those terrain chunks; it is the whole grid's worth of nothing when the
    /// stroke misses. Reported even when nothing CHANGED — a caller that only rebuilt on a change
    /// would be right, but the rect is also what the editor draws its brush ring from.
    pub fn sculpt(self: *Map, px: f32, pz: f32, radius: f32, mode: Sculpt, amount: f32, out: *[4]usize) bool {
        const step = 2 * self.half / @as(f32, @floatFromInt(HEIGHT_N - 1));
        const r = mathx.maxF(radius, step * 0.5);
        out.* = EMPTY_SPAN;
        const xs = pointSpan(px, r, self.half, step) orelse return false;
        const zs = pointSpan(pz, r, self.half, step) orelse return false;
        out.* = .{ xs[0], zs[0], xs[1], zs[1] };
        const lo = xs[0];
        const hi = xs[1];
        const zlo = zs[0];
        const zhi = zs[1];
        // FLATTEN's target and SMOOTH's source are both read BEFORE anything is written: a flatten
        // that re-read its own output would creep the target as the brush moved, and a smooth done in
        // place is a directional blur that drags the terrain toward +x.
        const target = self.heightAt(px, pz);
        var before: [HEIGHT_N]f32 = undefined; // one row of the pre-pass, for smooth's neighbours
        var changed = false;
        var iz = zlo;
        while (iz <= zhi) : (iz += 1) {
            if (mode == .smooth) {
                var ix: usize = 0;
                while (ix < HEIGHT_N) : (ix += 1) before[ix] = heightOf(self.height[iz * HEIGHT_N + ix]);
            }
            var ix = lo;
            while (ix <= hi) : (ix += 1) {
                const p = self.heightPoint(ix, iz);
                const dx = p[0] - px;
                const dz = p[1] - pz;
                const d = @sqrt(dx * dx + dz * dz);
                if (d > r) continue;
                const fall = mathx.smoothstep(r, r * 0.15, d); // 1 in the middle, 0 at the rim
                const i = iz * HEIGHT_N + ix;
                const cur = heightOf(self.height[i]);
                const want = switch (mode) {
                    .raise => cur + amount * fall,
                    .lower => cur - amount * fall,
                    .flatten => mathx.lerpF(cur, target, mathx.clampF(amount, 0, 1) * fall),
                    // The 4-neighbour mean, from the UNTOUCHED row above and the pre-pass row here.
                    // Edge points reuse themselves, which leaves the rim where it is instead of
                    // pulling it toward a neighbour that does not exist.
                    .smooth => blk: {
                        const xm = if (ix > 0) before[ix - 1] else cur;
                        const xp = if (ix + 1 < HEIGHT_N) before[ix + 1] else cur;
                        const zm = if (iz > 0) heightOf(self.height[(iz - 1) * HEIGHT_N + ix]) else cur;
                        const zp = if (iz + 1 < HEIGHT_N) heightOf(self.height[(iz + 1) * HEIGHT_N + ix]) else cur;
                        break :blk mathx.lerpF(cur, (xm + xp + zm + zp) * 0.25, mathx.clampF(amount, 0, 1) * fall);
                    },
                };
                const v = heightByte(mathx.clampF(want, HEIGHT_MIN, HEIGHT_MAX));
                if (self.height[i] != v) {
                    self.height[i] = v;
                    changed = true;
                }
            }
        }
        return changed;
    }

    pub fn inClearing(self: *const Map, px: f32, pz: f32) bool {
        for (self.clearings[0..self.nclearings]) |c| {
            const dx = px - c.x;
            const dz = pz - c.z;
            if (dx * dx + dz * dz < c.r * c.r) return true;
        }
        return false;
    }
};

// ── writing ────────────────────────────────────────────────────────────────────────────

pub fn write(m: *const Map, w: anytype) !void {
    try w.print("version: {d}\n", .{VERSION});
    try w.print("name: {s}\n", .{m.label()});
    try w.print("half: {d:.1}\n", .{m.half});
    try w.print("runway: {d:.2} {d:.2} {d:.2} {d:.2}\n", .{ m.runway.x, m.runway.z, m.runway.x1, m.runway.z1 });
    try w.writeAll("\n");

    for (m.zones[0..m.nzones]) |*z| {
        try w.print("zone: {s} {d:.1} {d:.1} {d:.1} {d:.1} {d:.3} ", .{ z.label(), z.x, z.z, z.x1, z.z1, z.density });
        try writeMix(w, z.mix[0..z.nmix]);
        try w.writeAll("\n");
    }
    for (m.clearings[0..m.nclearings]) |c| {
        try w.print("clear: {d:.1} {d:.1} {d:.1}\n", .{ c.x, c.z, c.r });
    }
    if (m.nzones + m.nclearings > 0) try w.writeAll("\n");

    for (m.ops[0..m.nops]) |*o| try writeOp(o, w);

    // The soil grid, RUN-LENGTH encoded: 4096 cells that are almost all the same value, so
    // runs turn a 4 KB wall of digits into a handful of readable lines. Omitted entirely when
    // nothing is painted, which is the common case and keeps a fresh map clean.
    var anyPaint = false;
    for (m.soil) |v| {
        if (v != 0) {
            anyPaint = true;
            break;
        }
    }
    if (anyPaint) {
        try w.writeAll("\n");
        try writeGrid(w, "soil", &m.soil);
    }
    // …and the water mask the same way. All three grids are RLE because all three are mostly one
    // value; the shared writer is what keeps the records from drifting into different encodings.
    if (m.anyWater()) {
        try w.writeAll("\n");
        try writeGrid(w, "water", &m.water);
    }
    // …and the SCULPTED GROUND. Omitted for a flat map, which is why adding elevation did not touch a
    // single existing world file. A sculpted one is the biggest record in the format by far — heights
    // vary continuously, so the runs are short — and that is the honest cost of storing a shape
    // instead of the ops that made it.
    if (m.anyHeight()) {
        try w.writeAll("\n");
        try writeGrid(w, "hgt", &m.height);
    }

    if (m.nfoes > 0) try w.writeAll("\n");
    for (m.foes[0..m.nfoes]) |f| {
        try w.print("foe: {s} {d:.2} {d:.2} {d:.1} {d:.2} {d:.2}\n", .{ @tagName(f.kind), f.x, f.z, f.yaw, f.scale, f.seed });
    }
}

fn writeOp(o: *const Op, w: anytype) !void {
    try w.print("{s}:", .{@tagName(o.op)});
    const d = defaults(o.op);
    switch (o.op) {
        inline else => |k| {
            inline for (comptime fieldsOf(k)) |name| {
                try w.writeAll(" ");
                try writeTail(w, @field(o, name));
            }
            // The tail carries only what differs from this kind's DEFAULTS, so a plain belt stays one
            // short line and every key in a file is a decision somebody made. Positionals are excluded
            // per-kind — emitting one here too would write `kind=fern` after the fern in column one.
            inline for (@typeInfo(Op).@"struct".fields) |f| {
                if (comptime canTail(k, f.name)) {
                    if (!eqlVal(@field(o, f.name), @field(d, f.name))) {
                        try w.print(" {s}=", .{f.name});
                        try writeTail(w, @field(o, f.name));
                    }
                }
            }
        },
    }
    if (o.nmix > 0) {
        try w.writeAll(" mix=");
        try writeMix(w, o.mix[0..o.nmix]);
    }
    try w.writeAll("\n");
}

/// One painted grid, RUN-LENGTH encoded: thousands of cells that are almost all the same value, so
/// runs turn a wall of digits into a handful of readable lines. Wrapped at 16 runs a line; the reader
/// carries a running cursor, so where it wraps is not part of the format.
fn writeGrid(w: anytype, label: []const u8, cells: []const u8) !void {
    var i: usize = 0;
    var perLine: usize = 0;
    while (i < cells.len) {
        const v = cells[i];
        var run: usize = 1;
        while (i + run < cells.len and cells[i + run] == v) run += 1;
        if (perLine == 0) try w.print("{s}:", .{label});
        try w.print(" {d}x{d}", .{ v, run });
        i += run;
        perLine += 1;
        if (perLine == 16) {
            try w.writeAll("\n");
            perLine = 0;
        }
    }
    if (perLine != 0) try w.writeAll("\n");
}

fn writeMix(w: anytype, mix: []const Kind) !void {
    for (mix, 0..) |k, i| {
        if (i > 0) try w.writeAll(",");
        try w.writeAll(@tagName(k));
    }
}

fn writeTail(w: anytype, v: anytype) !void {
    const T = @TypeOf(v);
    switch (@typeInfo(T)) {
        .@"enum" => try w.print("{s}", .{@tagName(v)}),
        .float => try w.print("{d}", .{v}),
        .int => try w.print("{d}", .{v}),
        .bool => try w.print("{s}", .{if (v) "1" else "0"}),
        .@"struct" => { // Avoid — a comma list of the flags that are on, or `-` for none
            var any = false;
            inline for (@typeInfo(T).@"struct".fields) |f| {
                if (@field(v, f.name)) {
                    if (any) try w.writeAll(",");
                    try w.writeAll(f.name);
                    any = true;
                }
            }
            if (!any) try w.writeAll("-");
        },
        else => @compileError("worldfmt: no serializer for " ++ @typeName(T)),
    }
}

// ── reading ────────────────────────────────────────────────────────────────────────────

pub const ParseError = error{
    BadVersion,
    UnknownRecord,
    UnknownKey,
    MissingField,
    ExtraField,
    BadNumber,
    BadKind,
    TooManyOps,
    TooManyZones,
    TooManyClearings,
    TooManyFoes,
    NoCoverOp,
};

/// Parse a whole map. `lineOut` receives the 1-based line number a failure landed on, so the
/// editor's load error can point at it instead of just saying the file is bad.
pub fn parse(text: []const u8, m: *Map, lineOut: *usize) !void {
    m.* = .{};
    var seenVersion = false;
    var soilAt: usize = 0; // running cursor, so soil runs may wrap across lines
    var waterAt: usize = 0; // …and the water mask's own
    var hgtAt: usize = 0; // …and the sculpted ground's
    var lines = std.mem.splitScalar(u8, text, '\n');
    var ln: usize = 0;
    while (lines.next()) |raw| {
        ln += 1;
        lineOut.* = ln;
        const line = trim(stripComment(raw));
        if (line.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return ParseError.UnknownRecord;
        const rec = trim(line[0..colon]);
        var it = std.mem.tokenizeAny(u8, line[colon + 1 ..], " \t");
        if (std.mem.eql(u8, rec, "version")) {
            if (try nextInt(&it) != VERSION) return ParseError.BadVersion;
            seenVersion = true;
        } else if (std.mem.eql(u8, rec, "name")) {
            m.setName(trim(line[colon + 1 ..]));
        } else if (std.mem.eql(u8, rec, "half")) {
            m.half = try nextFloat(&it);
            if (!(m.half > 0 and m.half <= MAX_DECLARED_HALF)) return ParseError.BadNumber;
        } else if (std.mem.eql(u8, rec, "runway")) {
            m.runway = .{ .x = try nextFloat(&it), .z = try nextFloat(&it), .x1 = try nextFloat(&it), .z1 = try nextFloat(&it) };
        } else if (std.mem.eql(u8, rec, "zone")) {
            if (m.nzones >= MAX_ZONES) return ParseError.TooManyZones;
            m.zones[m.nzones] = try parseZone(&it);
            m.nzones += 1;
        } else if (std.mem.eql(u8, rec, "clear")) {
            if (m.nclearings >= MAX_CLEARINGS) return ParseError.TooManyClearings;
            m.clearings[m.nclearings] = .{ .x = try nextFloat(&it), .z = try nextFloat(&it), .r = try nextFloat(&it) };
            m.nclearings += 1;
        } else if (std.mem.eql(u8, rec, "soil")) {
            // Runs continue ACROSS lines — `soilAt` is a running cursor over the whole grid, so
            // the writer can wrap wherever it likes and a hand-edited file can too.
            soilAt = try readGrid(&it, &m.soil, soilAt, Soil.N);
        } else if (std.mem.eql(u8, rec, "water")) {
            // The mask is one bit wide, so the ceiling is 2 — anything else in the file is a typo,
            // and a stray 7 would otherwise become "very wet" in whatever reads it next.
            waterAt = try readGrid(&it, &m.water, waterAt, 2);
        } else if (std.mem.eql(u8, rec, "hgt")) {
            // EVERY byte is a legal height, so the ceiling is 256 — which is why `readGrid` takes a
            // u16 limit rather than the u8 the other two grids need.
            hgtAt = try readGrid(&it, &m.height, hgtAt, 256);
        } else if (std.mem.eql(u8, rec, "foe")) {
            if (m.nfoes >= MAX_FOES) return ParseError.TooManyFoes;
            m.foes[m.nfoes] = .{
                .kind = try enumFromName(FoeKind, it.next() orelse return ParseError.MissingField),
                .x = try nextFloat(&it),
                .z = try nextFloat(&it),
                .yaw = try nextFloat(&it),
                .scale = try nextFloat(&it),
                .seed = try nextFloat(&it),
            };
            m.nfoes += 1;
        } else if (enumFromName(OpKind, rec)) |k| {
            if (m.nops >= MAX_OPS) return ParseError.TooManyOps;
            m.ops[m.nops] = try parseOp(k, &it);
            m.nops += 1;
        } else |_| {
            return ParseError.UnknownRecord;
        }
    }
    if (!seenVersion) return ParseError.BadVersion;
    // A map with no cover op has no ground cover, which LOOKS like a load failure and isn't — so it is
    // one. Same reasoning as env's caps: fail loudly at the cause.
    for (m.ops[0..m.nops]) |o| {
        if (o.op == .cover) return;
    }
    return ParseError.NoCoverOp;
}

/// One RLE grid record, continuing from `at` and returning the new cursor. `lim` is the exclusive
/// ceiling on a cell value — a value past it is a corrupt file, not a new material. A u16, because the
/// height grid's ceiling is 256: every byte is a legal elevation, and a u8 limit cannot say so.
fn readGrid(it: *std.mem.TokenIterator(u8, .any), cells: []u8, at: usize, lim: u16) !usize {
    var cur = at;
    while (it.next()) |tok| {
        const xi = std.mem.indexOfScalar(u8, tok, 'x') orelse return ParseError.BadNumber;
        const v = std.fmt.parseInt(u8, tok[0..xi], 10) catch return ParseError.BadNumber;
        const run = std.fmt.parseInt(usize, tok[xi + 1 ..], 10) catch return ParseError.BadNumber;
        if (v >= lim) return ParseError.BadKind;
        // SUBTRACT, never add: `run` is a usize parsed straight out of the file, so `cur + run`
        // overflows on any run near usize's ceiling — an integer-overflow panic in Debug, and in
        // ReleaseFast a wrapped comparison that passes and then @memsets a wrapped range.
        if (run > cells.len - cur) return ParseError.ExtraField;
        @memset(cells[cur .. cur + run], v);
        cur += run;
    }
    return cur;
}

fn parseZone(it: *std.mem.TokenIterator(u8, .any)) !Zone {
    var z = Zone{};
    const nm = it.next() orelse return ParseError.MissingField;
    const n = @min(nm.len, NAME_CAP - 1);
    @memcpy(z.name[0..n], nm[0..n]);
    z.x = try nextFloat(it);
    z.z = try nextFloat(it);
    z.x1 = try nextFloat(it);
    z.z1 = try nextFloat(it);
    z.density = try nextFloat(it);
    z.nmix = try parseMix(it.next() orelse return ParseError.MissingField, &z.mix);
    // A zone with no mix grows NOTHING, and `zoneAt` hands it out as the fallback for every point it
    // covers — a bald region, a long way from the line. (A token of pure separators parses to 0.)
    if (z.nmix == 0) return ParseError.MissingField;
    if (it.next() != null) return ParseError.ExtraField;
    return z;
}

fn parseOp(kind: OpKind, it: *std.mem.TokenIterator(u8, .any)) !Op {
    var o = defaults(kind);
    switch (kind) {
        inline else => |k| {
            // Required positionals, in TABLE order — the same walk the writer makes.
            inline for (comptime fieldsOf(k)) |name| {
                const tok = it.next() orelse return ParseError.MissingField;
                @field(o, name) = try parseVal(@TypeOf(@field(o, name)), tok);
            }
            // Optional key=value tail.
            while (it.next()) |tok| {
                const eq = std.mem.indexOfScalar(u8, tok, '=') orelse return ParseError.UnknownKey;
                const key = tok[0..eq];
                const val = tok[eq + 1 ..];
                if (std.mem.eql(u8, key, "mix")) {
                    o.nmix = try parseMix(val, &o.mix);
                    continue;
                }
                var matched = false;
                inline for (@typeInfo(Op).@"struct".fields) |f| {
                    if (comptime canTail(k, f.name)) {
                        if (std.mem.eql(u8, key, f.name)) {
                            @field(o, f.name) = try parseVal(@TypeOf(@field(o, f.name)), val);
                            matched = true;
                        }
                    }
                }
                if (!matched) return ParseError.UnknownKey;
            }
        },
    }
    return o;
}

fn parseMix(s: []const u8, out: *[MAX_MIX]Kind) !u8 {
    var n: u8 = 0;
    var parts = std.mem.splitScalar(u8, s, ',');
    while (parts.next()) |p| {
        const t = trim(p);
        if (t.len == 0) continue;
        if (n >= MAX_MIX) return ParseError.ExtraField;
        out[n] = try enumFromName(Kind, t);
        n += 1;
    }
    return n;
}

fn parseVal(comptime T: type, tok: []const u8) !T {
    return switch (@typeInfo(T)) {
        .@"enum" => try enumFromName(T, tok),
        .float => try finiteFloat(T, tok),
        .int => std.fmt.parseInt(T, tok, 10) catch ParseError.BadNumber,
        // Anything else is a LOAD ERROR, not `false`: leniency here meant `field=yes` or a typo like
        // `field=ture` read as OFF, silently taking a belt off the cover field with nothing pointing at
        // the line. Same rule as an unknown key.
        .bool => blk: {
            if (std.mem.eql(u8, tok, "1") or std.mem.eql(u8, tok, "true")) break :blk true;
            if (std.mem.eql(u8, tok, "0") or std.mem.eql(u8, tok, "false")) break :blk false;
            break :blk ParseError.BadNumber;
        },
        .@"struct" => blk: { // Avoid
            var v: T = .{};
            if (std.mem.eql(u8, tok, "-")) break :blk v;
            var parts = std.mem.splitScalar(u8, tok, ',');
            while (parts.next()) |p| {
                const t = trim(p);
                if (t.len == 0) continue;
                var hit = false;
                inline for (@typeInfo(T).@"struct".fields) |f| {
                    if (std.mem.eql(u8, t, f.name)) {
                        @field(v, f.name) = true;
                        hit = true;
                    }
                }
                if (!hit) break :blk ParseError.UnknownKey;
            }
            break :blk v;
        },
        else => @compileError("worldfmt: no parser for " ++ @typeName(T)),
    };
}

// ── files ──────────────────────────────────────────────────────────────────────────────

pub const DIR = "worlds";
pub const START_MAP = "worlds/01_fallen_plain.world";

// One scratch buffer for whole-file reads — a map is a few tens of KB, and a file-level buffer keeps
// load/save off the allocator like everything else here.
var textBuf: [1 << 20]u8 = undefined;

/// `load` parses HERE and copies out only on SUCCESS. `parse` blanks its destination on the first line,
/// so parsing straight into the caller's map left a half-loaded world behind on any error — and the
/// editor went on editing a map that no longer matched the one on screen.
var loadScratch: Map = undefined;

pub fn load(path: []const u8, m: *Map, lineOut: *usize) !void {
    var f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    const n = try f.readAll(&textBuf);
    if (n == textBuf.len) return error.MapTooLarge; // a truncated map parses as a SHORTER world
    try parse(textBuf[0..n], &loadScratch, lineOut);
    m.* = loadScratch;
}

/// Load the world or DIE, printing the file and the line. Deliberately NOT a fallback to a built-in
/// default: the map IS the world, so quietly running a different one hides the fault behind a world
/// nobody authored. Same rule as env's caps — fail at the cause.
pub fn loadOrPanic(path: []const u8, m: *Map) void {
    var line: usize = 0;
    load(path, m, &line) catch |e| {
        std.debug.print("world: cannot load {s} — {s} (line {d})\n", .{ path, @errorName(e), line });
        @panic("worldfmt: the map failed to load");
    };
}

pub const EXT = ".world";
pub const MAX_FILES: usize = 64;
pub const PATH_CAP: usize = 96;

/// The maps on disk. Fixed storage like everything else here; a directory with more than MAX_FILES maps
/// lists the first MAX_FILES rather than failing.
pub const Listing = struct {
    names: [MAX_FILES][PATH_CAP]u8 = undefined,
    n: usize = 0,

    /// NUL-terminated, because the UI list wants `[:0]const u8`. Safe because `scan` zeroes each slot
    /// before copying and always leaves the final byte clear.
    pub fn name(self: *const Listing, i: usize) [:0]const u8 {
        return std.mem.span(@as([*:0]const u8, @ptrCast(&self.names[i])));
    }

    /// Rescan `worlds/`. A missing directory is an EMPTY listing, not an error — just a project that
    /// hasn't saved a map yet.
    pub fn scan(self: *Listing) void {
        self.n = 0;
        var dir = std.fs.cwd().openDir(DIR, .{ .iterate = true }) catch return;
        defer dir.close();
        var it = dir.iterate();
        while (it.next() catch null) |e| {
            if (e.kind != .file) continue;
            if (!std.mem.endsWith(u8, e.name, EXT)) continue;
            if (self.n >= MAX_FILES) break;
            const len = @min(e.name.len, PATH_CAP - 1);
            @memset(&self.names[self.n], 0);
            @memcpy(self.names[self.n][0..len], e.name[0..len]);
            self.n += 1;
        }
        // Lexicographic, so the list is stable between scans instead of following whatever
        // order the filesystem happens to hand back.
        std.mem.sort([PATH_CAP]u8, self.names[0..self.n], {}, struct {
            fn lt(_: void, a: [PATH_CAP]u8, b: [PATH_CAP]u8) bool {
                return std.mem.order(u8, std.mem.sliceTo(&a, 0), std.mem.sliceTo(&b, 0)) == .lt;
            }
        }.lt);
    }
};

/// Build `worlds/<slug>.world` from a typed name. Anything non-alphanumeric becomes an underscore, so a
/// name with a slash or a colon can neither escape the directory nor produce a path the OS refuses.
pub fn pathFor(dst: []u8, name: []const u8) []const u8 {
    var n: usize = 0;
    for (DIR) |c| {
        if (n < dst.len) {
            dst[n] = c;
            n += 1;
        }
    }
    if (n < dst.len) {
        dst[n] = '/';
        n += 1;
    }
    const stem = n; // where the NAME starts. The emptiness test below is against THIS, not 0: `n`
    // already carries "worlds/", and a name of pure punctuation would otherwise slip past the fallback
    // and produce the hidden file "worlds/.world".
    var lastUnderscore = true; // also trims leading separators
    for (name) |c| {
        if (n + EXT.len >= dst.len) break;
        const ok = std.ascii.isAlphanumeric(c);
        if (!ok and lastUnderscore) continue; // never two separators in a row
        dst[n] = if (ok) std.ascii.toLower(c) else '_';
        lastUnderscore = !ok;
        n += 1;
    }
    if (n > stem and dst[n - 1] == '_') n -= 1; // no trailing separator
    if (n == stem) { // a name of pure punctuation still has to land somewhere
        // BOUNDED, like the loops either side of it. This was the one unchecked write in the
        // function whose whole job is making an untrusted typed name safe: on a `dst` too short to
        // hold "worlds/" + "untitled" + ".world" it ran straight off the end. Every caller passes a
        // PATH_CAP buffer today, so nothing has ever hit it — which is exactly why it would have
        // stayed until something passed a smaller one.
        for ("untitled") |c| {
            if (n + EXT.len >= dst.len) break;
            dst[n] = c;
            n += 1;
        }
    }
    for (EXT) |c| {
        if (n >= dst.len) break;
        dst[n] = c;
        n += 1;
    }
    return dst[0..n];
}

pub fn save(path: []const u8, m: *const Map) !void {
    try std.fs.cwd().makePath(DIR);
    var f = try std.fs.cwd().createFile(path, .{});
    defer f.close();
    var buf = std.io.bufferedWriter(f.writer());
    try write(m, buf.writer());
    try buf.flush();
}

// ── shared plumbing ────────────────────────────────────────────────────────────────────

/// Is `name` one of this kind's required positionals?
fn isPositional(comptime k: OpKind, comptime name: []const u8) bool {
    // The field walk is O(op kinds x Op fields x name length) string compares at comptime, and
    // the default 1000-branch budget is spent well before it finishes.
    @setEvalBranchQuota(20000);
    for (fieldsOf(k)) |f| {
        if (std.mem.eql(u8, f, name)) return true;
    }
    return false;
}

/// May `name` appear in this kind's optional key=value tail? Everything except the
/// discriminator, the mix (written as one `mix=` key) and the kind's own positionals — so
/// exactly one place in the line can ever set a given field, in both directions.
fn canTail(comptime k: OpKind, comptime name: []const u8) bool {
    @setEvalBranchQuota(20000);
    const never = [_][]const u8{ "op", "mix", "nmix" };
    for (never) |n| {
        if (std.mem.eql(u8, n, name)) return false;
    }
    return !isPositional(k, name);
}

fn eqlVal(a: anytype, b: @TypeOf(a)) bool {
    return switch (@typeInfo(@TypeOf(a))) {
        .@"struct" => std.meta.eql(a, b),
        else => a == b,
    };
}

fn enumFromName(comptime T: type, s: []const u8) !T {
    return std.meta.stringToEnum(T, s) orelse ParseError.BadKind;
}

/// REFUSE a non-finite float. `parseFloat` accepts "nan" and "inf" and neither survives the world: a
/// NaN x/z walks straight through `env.cellCoord`'s `f <= 0` guard into `@intFromFloat` (illegal
/// behaviour), a NaN `seed` does the same in `frog.spawn`, and an infinite `half:` overflows the cover
/// lattice's count — all a long way from the line that caused it.
fn finiteFloat(comptime T: type, tok: []const u8) !T {
    const v = std.fmt.parseFloat(T, tok) catch return ParseError.BadNumber;
    if (!std.math.isFinite(v)) return ParseError.BadNumber;
    return v;
}

fn nextFloat(it: *std.mem.TokenIterator(u8, .any)) !f32 {
    const t = it.next() orelse return ParseError.MissingField;
    return finiteFloat(f32, t);
}

fn nextInt(it: *std.mem.TokenIterator(u8, .any)) !u32 {
    const t = it.next() orelse return ParseError.MissingField;
    return std.fmt.parseInt(u32, t, 10) catch ParseError.BadNumber;
}

fn stripComment(s: []const u8) []const u8 {
    return if (std.mem.indexOfScalar(u8, s, '#')) |i| s[0..i] else s;
}

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

// ── tests ──────────────────────────────────────────────────────────────────────────────

test "an op round-trips through write and parse" {
    var m = Map{};
    m.setName("Round Trip");
    var o = defaults(.belt);
    o.kind = .fern;
    o.x = -152;
    o.z = -125;
    o.x1 = -54;
    o.z1 = 132;
    o.n = 220;
    o.sLo = 0.8;
    o.sHi = 1.35;
    o.seed = 4711;
    o.gAxis = .x;
    o.gA = -54;
    o.gB = -84;
    o.gFloor = 0.18;
    o.nmix = 3;
    o.mix[0] = .bigtree;
    o.mix[1] = .conifer;
    o.mix[2] = .birch;
    _ = try m.add(o);
    _ = try m.add(defaults(.cover));

    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try write(&m, fbs.writer());

    var back = Map{};
    var ln: usize = 0;
    try parse(fbs.getWritten(), &back, &ln);
    try std.testing.expectEqual(@as(usize, 2), back.nops);
    const b = back.ops[0];
    try std.testing.expectEqual(Kind.fern, b.kind);
    try std.testing.expectEqual(@as(i32, 220), b.n);
    try std.testing.expectEqual(@as(u64, 4711), b.seed);
    try std.testing.expectEqual(Axis.x, b.gAxis);
    try std.testing.expectApproxEqAbs(@as(f32, 0.18), b.gFloor, 1e-6);
    try std.testing.expectEqual(@as(u8, 3), b.nmix);
    try std.testing.expectEqual(Kind.conifer, b.mix[1]);
    try std.testing.expect(b.avoid.runway and b.avoid.water and !b.avoid.solid);
}

test "the soil grid and foe records survive a round trip" {
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    const back = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(back);
    m.blank("Round Trip");
    // A painted patch plus a lone cell, so both a long run and a one-cell run are exercised.
    _ = m.paintSoil(0, 0, 30, .stone);
    m.soil[SOIL_CELLS - 1] = @intFromEnum(Soil.ash);
    m.foes[0] = .{ .kind = .ogre, .x = 3, .z = -50, .yaw = 90, .scale = 1.2, .seed = 0.4 };
    m.nfoes = 1;

    var buf: [1 << 18]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try write(m, fbs.writer());
    var line: usize = 0;
    try parse(fbs.getWritten(), back, &line);

    try std.testing.expectEqualSlices(u8, &m.soil, &back.soil);
    try std.testing.expectEqual(@as(usize, 1), back.nfoes);
    try std.testing.expectEqual(FoeKind.ogre, back.foes[0].kind);
    try std.testing.expectApproxEqAbs(@as(f32, 1.2), back.foes[0].scale, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.4), back.foes[0].seed, 1e-4);
}

test "the height field round-trips, and a FLAT map writes no height record at all" {
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    const back = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(back);
    m.blank("Hills");

    // A FLAT map must not carry the record. This is what kept every existing world file byte-identical
    // when elevation arrived, and it is also 50 KB of RLE nobody wants in a diff for a plain.
    {
        var buf: [1 << 18]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        try write(m, fbs.writer());
        try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "hgt:") == null);
        // …and it loads back FLAT, not at the bottom of the encoding's range. The grid's default is the
        // datum byte, so a `.{}`-initialised map is ground level; defaulting to 0 would sink the world
        // HEIGHT_MIN metres and every prop with it.
        var line: usize = 0;
        try parse(fbs.getWritten(), back, &line);
        try std.testing.expect(!back.anyHeight());
        try std.testing.expectApproxEqAbs(@as(f32, 0), back.heightAt(0, 0), 1e-6);
        try std.testing.expectApproxEqAbs(@as(f32, 0), back.heightAt(-190, 77), 1e-6);
    }

    // Now sculpt: a hill, a hollow beside it, and one lattice point set by hand at the far corner so a
    // one-cell run is exercised as well as long ones.
    var span: [4]usize = undefined;
    try std.testing.expect(m.sculpt(-40, 20, 30, .raise, 9.0, &span));
    try std.testing.expect(m.sculpt(30, -10, 18, .lower, 4.0, &span));
    m.height[HEIGHT_CELLS - 1] = heightByte(2.5);
    try std.testing.expect(m.anyHeight());

    var buf: [1 << 21]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try write(m, fbs.writer());
    var line: usize = 0;
    try parse(fbs.getWritten(), back, &line);
    try std.testing.expectEqualSlices(u8, &m.height, &back.height);
    // …and the SHAPE survived, not just the bytes: the hill is up, the hollow is down, and untouched
    // ground between them is still exactly zero.
    try std.testing.expect(back.heightAt(-40, 20) > 8.0);
    try std.testing.expect(back.heightAt(30, -10) < -3.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), back.heightAt(0, 200), 1e-6);
}

test "sculpt: the brush tapers, respects its radius, and cannot leave the encoding's range" {
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    m.blank("Sculpt");
    var span: [4]usize = undefined;

    // A single raise: full bite in the middle, LESS at the rim, nothing outside it. The taper is what
    // makes a stroke walkable at all — a flat-topped brush leaves a vertical wall round a cylinder.
    _ = m.sculpt(0, 0, 20, .raise, 6.0, &span);
    const mid = m.heightAt(0, 0);
    const edge = m.heightAt(17, 0);
    try std.testing.expect(mid > 5.5);
    try std.testing.expect(edge > 0.0 and edge < mid * 0.6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), m.heightAt(40, 0), 1e-6); // outside: untouched

    // SMOOTH pulls each point toward its neighbours, so a SPIKE comes down…
    _ = m.sculpt(60, 0, 3, .raise, 8.0, &span);
    const spike = m.heightAt(60, 0);
    _ = m.sculpt(60, 0, 7, .smooth, 1.0, &span);
    try std.testing.expect(m.heightAt(60, 0) < spike - 0.5);
    // …and a PLATEAU is left where it is, because its neighbours are already at its own height. That
    // asymmetry is the whole reason smoothing is safe to sweep over ground you have already shaped:
    // it takes the lumps out of a bank without eroding the terrace beside it.
    const plateau = m.heightAt(0, 0);
    _ = m.sculpt(0, 0, 20, .smooth, 1.0, &span);
    try std.testing.expectApproxEqAbs(plateau, m.heightAt(0, 0), HEIGHT_STEP);

    // FLATTEN takes the ground toward the height under the brush CENTRE — so a stroke started on the
    // dome's top pulls its shoulder UP to that height rather than cutting the top off. A few passes,
    // because one pass moves each point most of the way and the taper leaves the rim behind.
    var f: usize = 0;
    while (f < 6) : (f += 1) _ = m.sculpt(0, 0, 20, .flatten, 1.0, &span);
    try std.testing.expectApproxEqAbs(m.heightAt(0, 0), m.heightAt(10, 0), 0.3);

    // …and no amount of digging can leave the byte range. A clamp that wrapped would put a pit at the
    // top of a mountain.
    var i: usize = 0;
    while (i < 40) : (i += 1) _ = m.sculpt(0, 0, 20, .lower, 12.0, &span);
    try std.testing.expect(m.heightAt(0, 0) >= HEIGHT_MIN - 1e-4);
    i = 0;
    while (i < 80) : (i += 1) _ = m.sculpt(0, 0, 20, .raise, 12.0, &span);
    try std.testing.expect(m.heightAt(0, 0) <= HEIGHT_MAX + 1e-4);

    // A stroke that MISSES the grid changes nothing and reports an empty rect, so a caller's rebuild
    // loops don't run (and don't index a wild range).
    var out: [4]usize = undefined;
    try std.testing.expect(!m.sculpt(9000, 9000, 5, .raise, 4, &out));
    try std.testing.expect(out[0] > out[2] and out[1] > out[3]);
}

test "the height sampler is bilinear, edge-clamped, and its gradient points UPHILL" {
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    m.blank("Ramp");
    // A ramp built by hand: height rises with the x index, nothing varies in z. Every sampled value in
    // between must land ON that ramp — a nearest-neighbour lookup would give a staircase instead, and
    // the hero would climb 2.5 m-wide steps up a slope that is supposed to be smooth.
    for (0..HEIGHT_N) |iz| {
        for (0..HEIGHT_N) |ix| {
            m.height[iz * HEIGHT_N + ix] = heightByte(@as(f32, @floatFromInt(ix)) * 0.25);
        }
    }
    const step = 2 * m.half / @as(f32, @floatFromInt(HEIGHT_N - 1));
    const x0 = -m.half + 10 * step;
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), m.heightAt(x0, 0), 1e-3);
    // …and half a cell along is half a step up. THE bilinear claim.
    try std.testing.expectApproxEqAbs(@as(f32, 2.625), m.heightAt(x0 + step * 0.5, 0), 1e-3);
    // Off the grid entirely, the edge height CONTINUES rather than dropping to zero: an actor at the
    // world's bound must not fall off a lip that only exists because the field ran out.
    try std.testing.expectApproxEqAbs(m.heightAt(-m.half, 0), m.heightAt(-m.half - 60, 0), 1e-4);
    try std.testing.expectApproxEqAbs(m.heightAt(m.half, 0), m.heightAt(m.half + 60, 0), 1e-4);

    // The gradient: +x is uphill here, z is flat. Its LENGTH is the tangent of the slope angle, which
    // is what the walkable test compares against — 0.25 m per 2.5 m cell is 0.1.
    const g = m.gradAt(0, 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), g[0], 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 0), g[1], 1e-4);
}

test "blank() produces a map its own loader accepts" {
    // `New` must hand back something that LOADS: an empty map trips NoCoverOp and shows as bare terrain,
    // which reads as a rendering bug rather than an empty document.
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    const back = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(back);
    m.blank("Fresh");
    var buf: [1 << 16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try write(m, fbs.writer());
    var line: usize = 0;
    try parse(fbs.getWritten(), back, &line);
    try std.testing.expect(back.zoneAt(0, 0) != null);
    try std.testing.expect(back.zoneAt(0, 0).?.nmix > 0);
}

test "pathFor slugifies, and cannot escape the worlds directory" {
    var buf: [PATH_CAP]u8 = undefined;
    try std.testing.expectEqualStrings("worlds/the_fallen_plain.world", pathFor(&buf, "The Fallen Plain"));
    // Separators and traversal collapse to underscores rather than reaching a parent directory.
    try std.testing.expectEqualStrings("worlds/etc_passwd.world", pathFor(&buf, "../../etc/passwd"));
    try std.testing.expectEqualStrings("worlds/a_b.world", pathFor(&buf, "  a   b  "));
    try std.testing.expectEqualStrings("worlds/untitled.world", pathFor(&buf, "///"));
}

test "a bad key or a missing field is a load error, never a default" {
    var m = Map{};
    var ln: usize = 0;
    try std.testing.expectError(ParseError.UnknownKey, parse(
        "version: 1\ncover: 3.3 0.7 1.4\nbelt: fern -1 -1 1 1 10 0.8 1.2 wobble=3\n",
        &m,
        &ln,
    ));
    try std.testing.expectError(ParseError.MissingField, parse("version: 1\nbelt: fern -1 -1 1 1\n", &m, &ln));
    try std.testing.expectError(ParseError.UnknownRecord, parse("version: 1\nsplat: 1 2 3\n", &m, &ln));
    try std.testing.expectError(ParseError.BadVersion, parse("version: 99\n", &m, &ln));
    // A map with no ground cover is a silent-looking failure, so it fails loudly instead.
    try std.testing.expectError(ParseError.NoCoverOp, parse("version: 1\nat: pillar 0 0 0 1\n", &m, &ln));
}

test "a value that only LOOKS parseable is a load error too" {
    var m = Map{};
    var ln: usize = 0;
    const cover = "version: 1\ncover: 3.3 0.7 1.4\n";
    // `field=ture` used to load as OFF and quietly take the belt off the cover field — a whole region
    // thinning differently, five hundred lines from the typo.
    try std.testing.expectError(ParseError.BadNumber, parse(cover ++ "belt: fern -1 -1 1 1 10 0.8 1.2 field=ture\n", &m, &ln));
    try std.testing.expectError(ParseError.BadNumber, parse(cover ++ "belt: fern -1 -1 1 1 10 0.8 1.2 field=yes\n", &m, &ln));
    // …and `0`/`false` still mean off, so the writer's own output round-trips.
    try parse(cover ++ "belt: fern -1 -1 1 1 10 0.8 1.2 field=0\n", &m, &ln);
    try std.testing.expect(!m.ops[1].field);
    // NON-FINITE floats parse fine in std, then crash deep inside env with no file and no line.
    try std.testing.expectError(ParseError.BadNumber, parse(cover ++ "at: pillar nan 0 0 1\n", &m, &ln));
    try std.testing.expectError(ParseError.BadNumber, parse(cover ++ "foe: toad 0 0 0 1 inf\n", &m, &ln));
    try std.testing.expectError(ParseError.BadNumber, parse("version: 1\nhalf: inf\n" ++ cover[11..], &m, &ln));
    // An absurd or non-positive `half` is a hang / an inverted world, not a big map.
    try std.testing.expectError(ParseError.BadNumber, parse("version: 1\nhalf: 0\n" ++ cover[11..], &m, &ln));
    try std.testing.expectError(ParseError.BadNumber, parse("version: 1\nhalf: 99999\n" ++ cover[11..], &m, &ln));
    try parse("version: 1\nhalf: 280\n" ++ cover[11..], &m, &ln);
    try std.testing.expectApproxEqAbs(DEFAULT_HALF, m.half, 1e-4);
}

test "each op gets its own stream, so editing one cannot re-roll another" {
    var a = defaults(.belt);
    a.seed = 100;
    var b = defaults(.belt);
    b.seed = 200;
    var ra = a.stream();
    var rb = b.stream();
    const a0 = ra.float();
    _ = rb.float();
    // Re-running `a` alone reproduces it exactly, whatever `b` has drawn in between.
    var ra2 = a.stream();
    try std.testing.expectEqual(a0, ra2.float());
}

test "zones resolve first-match-wins with the last as fallback" {
    var m = Map{};
    m.nzones = 2;
    m.zones[0] = .{ .x = -200, .z = -200, .x1 = -52, .z1 = 200, .density = 0.98 };
    m.zones[1] = .{ .x = -200, .z = -200, .x1 = 200, .z1 = 200, .density = 0.80 };
    try std.testing.expectApproxEqAbs(@as(f32, 0.98), m.zoneAt(-100, 0).?.density, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.80), m.zoneAt(0, 0).?.density, 1e-6);
    // Outside every rect still resolves — to the fallback, never to null.
    try std.testing.expectApproxEqAbs(@as(f32, 0.80), m.zoneAt(9999, 9999).?.density, 1e-6);
}

test "reorder preserves every other op's position" {
    var m = Map{};
    for (0..5) |i| {
        var o = defaults(.at);
        o.n = @intCast(i);
        _ = try m.add(o);
    }
    m.reorder(0, 3); // 0,1,2,3,4 -> 1,2,3,0,4
    const want = [_]i32{ 1, 2, 3, 0, 4 };
    for (want, 0..) |v, i| try std.testing.expectEqual(v, m.ops[i].n);
    m.reorder(3, 0); // and back
    for (0..5) |i| try std.testing.expectEqual(@as(i32, @intCast(i)), m.ops[i].n);
}
