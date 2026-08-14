const std = @import("std");
const props = @import("props.zig");
const mathx = @import("mathx.zig");
const gfx = @import("gfx.zig");
const item = @import("item.zig");

const Kind = props.Kind;


pub const VERSION: u32 = 1;

/// Playable half-extent when a map doesn't say otherwise; the world spans 2x this per axis.
pub const DEFAULT_HALF: f32 = 280.0;

/// Sanity bound on a `half:` record, and a POSITIVE one.
pub const MAX_DECLARED_HALF: f32 = 312.0;

pub const MAX_OPS: usize = 2048;
pub const MAX_MIX: usize = 24; // a scatter's weighted kind mix (weight = repetition)
/// How many items one chest holds.
pub const MAX_LOOT: usize = 8;
pub const MAX_ZONES: usize = 16;
pub const MAX_CLEARINGS: usize = 32;
pub const MAX_FOES: usize = 256;
/// THE BAND A SPAWN'S SCALE MULTIPLIER MAY SIT IN, and the editor's own stepper limits — one set, because a
/// hand-edited file is the only way past that stepper. A ZERO IS NOT COSMETIC: every humanoid feeds its gait
/// `movedDist / scale`, so 0 makes the stride phase inf, then NaN, and `hero.sampleCurve` casts that NaN to
/// an index.
pub const FOE_SCALE_LO: f32 = 0.5;
pub const FOE_SCALE_HI: f32 = 2.0;
pub const NAME_CAP: usize = 48;


pub const OpKind = enum(u8) {
    /// One prop, placed exactly.
    at,
    /// Rect scatter: `n` ATTEMPTS in a box, rejected against the avoid set and the cover field.
    belt,
    /// Annulus scatter about a centre, r0..r1 — shorelines, reed beds, talus, drowned ruin.
    disc,
    ring,
    /// A broken run from a→b: segments nose to tail, some collapsed.
    line,
    ivy,
    edge,
    cover,
};

/// What a scatter refuses to grow through.
pub const Avoid = struct {
    runway: bool = false, // the hero's start lane, kept clear so a straight walk out is never blocked
    water: bool = false, // open water
    clear: bool = false, // the authored clearings
    solid: bool = false, // anything with a footprint collider (queried against the solid grid)
};

pub const Axis = enum(u8) { none, x, z };

pub const Op = struct {
    op: OpKind = .at,
    kind: Kind = .pillar, // the prop placed, or the mix's fallback when `nmix` is 0
    x: f32 = 0, // point / rect min / centre / line start
    z: f32 = 0,
    x1: f32 = 0, // rect max / line end
    z1: f32 = 0,
    r0: f32 = 0, // disc inner radius / ring radius / line segment length / edge step
    /// disc outer radius — and, for an `at`, HOW FAR OFF THE GROUND the one prop is lifted, in metres
    /// (`env.Placer.expand`). It is not one of `at`'s positionals, so it only ever arrives as an `r1=` tail;
    /// named here because a field doing two jobs under one comment is a field the next reader gets wrong.
    r1: f32 = 0,
    yaw: f32 = 0,
    scale: f32 = 1,
    /// TIP THE PROP OFF PLUMB: `lean` degrees, toward the compass direction `leanDir` (measured like yaw).
    lean: f32 = 0,
    leanDir: f32 = 0,
    sLo: f32 = 0.85, // scale band the instances draw from
    sHi: f32 = 1.15,
    n: i32 = 0, // attempts (belt/disc), positions (ring), talus count (edge)
    skip: i32 = -1, // ring: the position left empty; -1 = none
    seed: u64 = 0,
    chance: f32 = 1.0, // per-candidate acceptance (ivy takes, line segment survives)
    bias: f32 = 0,
    field: bool = false,
    /// Belt density gradient: acceptance ramps `gFloor`→1 as the axis runs gA→gB.
    gAxis: Axis = .none,
    gA: f32 = 0,
    gB: f32 = 0,
    gFloor: f32 = 0,
    avoid: Avoid = .{},
    mix: [MAX_MIX]Kind = undefined,
    nmix: u8 = 0,
    /// What is in the chest this op placed.
    loot: [MAX_LOOT]item.Kind = undefined,
    nloot: u8 = 0,

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

// The REQUIRED positionals per op kind, in the order written and read.
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
    // Every name in the table must BE a field of Op.
    @setEvalBranchQuota(20000);
    for (@typeInfo(OpKind).@"enum".fields) |ek| {
        const k: OpKind = @enumFromInt(ek.value);
        for (fieldsOf(k)) |name| {
            if (!@hasField(Op, name)) @compileError("worldfmt: " ++ @tagName(k) ++ " names a field Op does not have: " ++ name);
        }
    }
}

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
    pub fn pick(self: *const Zone, rng: *mathx.Rng) ?Kind {
        if (self.nmix == 0) return null;
        return self.mix[@intCast(rng.intn(@intCast(self.nmix)))];
    }
    pub fn label(self: *const Zone) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }
    /// `Map.setName`'s shape, one level down, so a name's length is never written as a literal.
    pub fn setName(self: *Zone, s: []const u8) void {
        self.name = [_]u8{0} ** NAME_CAP;
        const n = @min(s.len, NAME_CAP - 1);
        @memcpy(self.name[0..n], s[0..n]);
    }
};

/// A WEIGHTED KIND MIX, BOUNDED — a bare indexed loop over `[MAX_MIX]Kind` writes past the array the
/// moment a mix literal outgrows the cap.
pub fn setMix(dst: *[MAX_MIX]Kind, n: *u8, mix: []const Kind) void {
    const k = @min(mix.len, MAX_MIX);
    @memcpy(dst[0..k], mix[0..k]);
    n.* = @intCast(k);
}

pub const Clearing = struct { x: f32 = 0, z: f32 = 0, r: f32 = 12 };

/// APPEND-ONLY in spirit, like `gfx.Mat`: the editor's unit brushes are pinned to this enum's ORDER at
/// comptime, and each `roleOf` reads its own entries as a CONTIGUOUS RUN off the first of them — so
/// inserting a kind in the middle silently renumbers all of it.
pub const FoeKind = enum(u8) { toad, archer, ogre, berserker, priest, slinger, brood_mother, broodling, brood_sac, shieldman, greatsword, shade, leechfly, rooted, shroom, bone_knight, delver };

pub fn foeName(k: FoeKind) [:0]const u8 {
    return switch (k) {
        .toad => "Giant Toad",
        .archer => "Skeleton Archer",
        .ogre => "Cyclops",
        .berserker => "Kobold Berserker",
        .priest => "Kobold Priest",
        .slinger => "Kobold Slinger",
        .brood_mother => "Brood Mother",
        .broodling => "Broodling",
        .brood_sac => "Egg Sac",
        .shieldman => "Skeleton Shieldman",
        .greatsword => "Skeleton Greatsword",
        .shade => "Shade",
        .leechfly => "Leechfly",
        .rooted => "The Rooted",
        .shroom => "Sporeling",
        .bone_knight => "Bone Knight",
        .delver => "Delver",
    };
}

pub const Foe = struct {
    kind: FoeKind = .toad,
    x: f32 = 0,
    z: f32 = 0,
    yaw: f32 = 0,
    scale: f32 = 1,
    seed: f32 = 0,
};

/// How many of ONE kind a map may post.
pub const MAX_PER_KIND: usize = 24;

pub const Runway = struct { x: f32 = -3.4, z: f32 = -44, x1: f32 = 3.4, z1: f32 = 30 };


//
// StarEdit's own shape: a trigger is CONDITIONS and ACTIONS, every condition must hold, and then the
// action list runs in order. What makes that shape compose is not the condition vocabulary but SC1's
// general-purpose STATE — named switches (`flag`), named integer counters (what its death counts were
// really for) and countdown timers. Without them every new bit of story state wants a new condition kind.
//
// A NAME IS INTERNED TO A SLOT AT LOAD (`flag`/`counter`/`timer`), so a condition costs two bytes rather
// than a string, and the map carries the name tables so the file stays self-describing. A reference to
// something declared LATER in the file (a dialog, a node an `ask:` points at) keeps the written name as a
// span and is resolved by `link` after the whole file is read — order is meaning for OPS, and must not be
// for these.

pub const ID_CAP: usize = 24;
pub const Id = [ID_CAP]u8;

pub const MAX_NPCS: usize = 32;
pub const MAX_TRIGGERS: usize = 64;
pub const MAX_CONDS: usize = 8;
pub const MAX_ACTS: usize = 8;
pub const MAX_DIALOGS: usize = 32;
pub const MAX_NODES: usize = 192;
pub const MAX_CHOICES: usize = 5;
/// The shared pools an `ask:` line reaches into for its `need:` gate and its `gets:` actions.
pub const MAX_GATES: usize = 64;
pub const MAX_DACTS: usize = 128;
pub const MAX_FLAGS: usize = 48;
pub const MAX_COUNTERS: usize = 48;
pub const MAX_TIMERS: usize = 16;
/// Every line of prose in the map, packed end to end. A per-node text cap would be an arbitrary sentence
/// length; this is one budget for the whole world.
pub const DTEXT_CAP: usize = 8192;

/// "Ends the conversation" as a node target, and "nothing resolved" as an index.
pub const NO_NODE: u16 = 0xFFFF;
pub const NO_DIALOG: u16 = 0xFFFF;
/// The reserved `ask: … -> end` target. A node may not be called this.
pub const END_TARGET = "end";

/// A run of `Map.dtext` — how every piece of authored prose is held.
pub const Span = struct { at: u32 = 0, len: u16 = 0 };

pub fn setId(dst: *Id, s: []const u8) void {
    dst.* = [_]u8{0} ** ID_CAP;
    const n = @min(s.len, ID_CAP - 1);
    @memcpy(dst[0..n], s[0..n]);
}

pub fn idText(id: *const Id) []const u8 {
    return std.mem.sliceTo(id, 0);
}

pub const Cmp = enum(u8) {
    lt,
    le,
    eq,
    ge,
    gt,

    pub fn tok(c: Cmp) []const u8 {
        return switch (c) {
            .lt => "<",
            .le => "<=",
            .eq => "=",
            .ge => ">=",
            .gt => ">",
        };
    }
    pub fn holds(c: Cmp, a: i64, b: i64) bool {
        return switch (c) {
            .lt => a < b,
            .le => a <= b,
            .eq => a == b,
            .ge => a >= b,
            .gt => a > b,
        };
    }
    pub fn holdsF(c: Cmp, a: f32, b: f32) bool {
        return switch (c) {
            .lt => a < b,
            .le => a <= b,
            .eq => a == b,
            .ge => a >= b,
            .gt => a > b,
        };
    }
};

fn cmpFromTok(s: []const u8) !Cmp {
    inline for (@typeInfo(Cmp).@"enum".fields) |f| {
        const c: Cmp = @enumFromInt(f.value);
        if (std.mem.eql(u8, s, c.tok())) return c;
    }
    return ParseError.BadKind;
}

pub const CondKind = enum(u8) {
    /// SC1's Always / Never — the second is how a draft trigger is parked without deleting it.
    always,
    never,
    /// SC1's Switch.
    flag,
    /// SC1's Deaths used as a variable: a named integer.
    counter,
    /// SC1's Countdown Timer, asked as "has it run out".
    timer,
    /// Seconds since the world loaded — SC1's Elapsed Time.
    elapsed,
    /// SC1's Bring: the hero inside a rect, LIVE — true while he stands in it and false the moment he
    /// leaves. Two conditions that come true at different moments are what the `flag` switches are for.
    region,
    /// The hero within `r` of NPC `slot`.
    near,
    /// A dialog has been seen through to its end.
    talked,
    /// SC1's Deaths proper: how many of one foe kind have died since the world loaded.
    deaths,
    /// …and its Bring/Command twin: how many are still standing.
    alive,
};

pub const Cond = struct {
    kind: CondKind = .always,
    /// The interned flag/counter/timer slot, the NPC index, or the resolved dialog — as `kind` says.
    slot: u16 = 0,
    /// The name it was WRITTEN with, kept for the things `link` resolves (and for the writer).
    ref: Span = .{},
    foe: FoeKind = .toad,
    cmp: Cmp = .ge,
    n: i32 = 0,
    /// `near` radius, `elapsed` seconds.
    r: f32 = 0,
    x: f32 = 0,
    z: f32 = 0,
    x1: f32 = 0,
    z1: f32 = 0,
    /// What a `flag` must be, and whether a `timer` must be DONE.
    on: bool = false,
};

pub const Setop = enum(u8) { off, on, flip };
pub const Countop = enum(u8) { set, add, sub };

pub const ActKind = enum(u8) {
    /// SC1's Transmission: open a dialog, and hold the rest of this trigger's list until it closes.
    dialog,
    /// SC1's Display Text Message.
    text,
    flag,
    counter,
    timer,
    /// SC1's Wait — it blocks THIS trigger's action list and nothing else.
    wait,
    /// SC1's Preserve Trigger, spelled its own way. `once=0` is the same thing said in the header.
    preserve,
};

pub const Act = struct {
    kind: ActKind = .preserve,
    slot: u16 = 0,
    ref: Span = .{},
    setop: Setop = .on,
    countop: Countop = .set,
    n: i32 = 0,
    /// Timer seconds, or `wait` seconds.
    v: f32 = 0,
    /// The `text` action's line.
    line: Span = .{},
};

pub const Trigger = struct {
    id: Id = [_]u8{0} ** ID_CAP,
    /// Higher runs first when several are satisfied on one frame.
    pri: i32 = 0,
    once: bool = true,
    /// An unfinished draft, saved on purpose and never evaluated.
    wip: bool = false,
    conds: [MAX_CONDS]Cond = undefined,
    nconds: u8 = 0,
    acts: [MAX_ACTS]Act = undefined,
    nacts: u8 = 0,

    pub fn label(self: *const Trigger) []const u8 {
        return idText(&self.id);
    }
    pub fn condSlice(self: *const Trigger) []const Cond {
        return self.conds[0..self.nconds];
    }
    pub fn actSlice(self: *const Trigger) []const Act {
        return self.acts[0..self.nacts];
    }
};

pub const Choice = struct {
    label: Span = .{},
    /// The node id it was written with…
    target: Span = .{},
    /// …and where that landed. `NO_NODE` closes the conversation.
    next: u16 = NO_NODE,
    /// One gate condition in `Map.gates`, or -1 for an always-offered line.
    gate: i16 = -1,
    /// A run of `Map.dacts` fired when this line is PICKED.
    act0: u16 = 0,
    nact: u8 = 0,
};

pub const Node = struct {
    id: Id = [_]u8{0} ** ID_CAP,
    /// Who is speaking, if not the NPC whose dialog this is.
    who: Span = .{},
    text: Span = .{},
    choices: [MAX_CHOICES]Choice = undefined,
    nchoices: u8 = 0,
    /// Where a node with NO choices goes on Continue, written name then resolved.
    thenRef: Span = .{},
    next: u16 = NO_NODE,
    /// A run of `Map.dacts` fired when this node is SHOWN.
    act0: u16 = 0,
    nact: u8 = 0,

    pub fn choiceSlice(self: *const Node) []const Choice {
        return self.choices[0..self.nchoices];
    }
};

pub const Dialog = struct {
    id: Id = [_]u8{0} ** ID_CAP,
    /// Its nodes are a contiguous run of `Map.nodes`; the first one is where it starts.
    node0: u16 = 0,
    nnodes: u16 = 0,

    pub fn label(self: *const Dialog) []const u8 {
        return idText(&self.id);
    }
};

/// APPEND-ONLY, for `FoeKind`'s reason: the editor and `npc.roleOf` will pin to this order.
pub const NpcKind = enum(u8) { wanderer };

pub fn npcName(k: NpcKind) [:0]const u8 {
    return switch (k) {
        .wanderer => "Wanderer",
    };
}

/// How far a roaming NPC may be posted to stray from where it stands.
pub const NPC_ROAM_MAX: f32 = 8.0;

pub const Npc = struct {
    kind: NpcKind = .wanderer,
    x: f32 = 0,
    z: f32 = 0,
    yaw: f32 = 0,
    scale: f32 = 1,
    seed: f32 = 0,
    /// Metres it wanders about its post. 0 stands still.
    roam: f32 = 0,
    /// What the dialog panel calls it — empty falls back to `npcName`.
    call: Span = .{},
    /// The dialog its prompt opens, written name then resolved.
    dlgRef: Span = .{},
    dlg: u16 = NO_DIALOG,
};

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

    /// WHAT A STROKE OF THIS GETS IF NOBODY SAYS OTHERWISE — and what a map written before the edge grid
    /// existed comes back as, so an old world looks exactly as it did (`fillLegacyEdges`).
    pub fn defaultEdge(s: Soil) Edge {
        return switch (s) {
            .stone => .tiled, // masons stop where they stopped
            else => .natural,
        };
    }
};

/// **HOW A PAINTED PATCH ENDS.** One authored property per CELL, beside its material and its coverage —
/// not a property of the material, since six materials cannot carry eight shapes and the point is to lay a
/// tiled courtyard and a torn scree of the same stone in one world.
///
/// Three knobs make all of these: how far the lookup WANDERS off the authored line, at what WAVELENGTH,
/// and whether the boundary CUTS or feathers. See `shaders.zig`.
pub const Edge = enum(u8) {
    /// One material dissolves into the next over metres. The gentlest thing here: no line at all.
    blend,
    /// A boundary that wanders on its own, softly. Grass into dirt — what everything was before.
    natural,
    /// Light, fast wander with a soft finish. Turf creeping into gravel a handful at a time.
    frayed,
    /// Hard, fast, deep wander. A torn line: broken flags, the lip of a scree.
    jagged,
    /// Exactly where you painted it, cut clean. No wander, no snap.
    straight,
    /// Cut clean AND snapped to the grid, so every edge runs on an axis. Laid masonry.
    tiled,
    /// A deliberate repeating wave rather than noise — a laid border, a tide line.
    scallop,
    /// The line breaks up into detached flecks before it ends. Moss stippling out over stone.
    speckle,

    pub const N = @typeInfo(Edge).@"enum".fields.len;

    pub fn label(e: Edge) [:0]const u8 {
        return switch (e) {
            .blend => "blend",
            .natural => "natural",
            .frayed => "frayed",
            .jagged => "jagged",
            .straight => "straight",
            .tiled => "tiled",
            .scallop => "scallop",
            .speckle => "speckle",
        };
    }

    pub fn fromTag(s: []const u8) ?Edge {
        return std.meta.stringToEnum(Edge, s);
    }
};

comptime {
    // The shader's soilColor() hard-codes ids 1..6 and falls through to moss.
    std.debug.assert(Soil.N == 7);
    // …AND `shaders.zig`'s `edgeShape(e)` BRANCHES ON THESE ORDINALS, 0..7 in this order: an inserted row
    // would silently re-point every stroke in every map at the wrong shape.
    std.debug.assert(Edge.N == 8);
    std.debug.assert(@intFromEnum(Edge.blend) == 0);
    std.debug.assert(@intFromEnum(Edge.natural) == 1);
    std.debug.assert(@intFromEnum(Edge.frayed) == 2);
    std.debug.assert(@intFromEnum(Edge.jagged) == 3);
    std.debug.assert(@intFromEnum(Edge.straight) == 4);
    std.debug.assert(@intFromEnum(Edge.tiled) == 5);
    std.debug.assert(@intFromEnum(Edge.scallop) == 6);
    std.debug.assert(@intFromEnum(Edge.speckle) == 7);
}

/// **IS EVERY CELL'S EDGE THE ONE ITS MATERIAL WOULD HAVE CHOSEN** — what decides whether the grid is worth
/// a row in the file, and the exact inverse of `fillLegacyEdges`. One predicate, so the writer and the
/// loader cannot disagree about "default"; as a `!= .natural` test every map with stone in it grew a row.
fn edgesAllDefault(m: *const Map) bool {
    for (m.soil, m.soilEdge) |id, e| {
        const want: u8 = @intFromEnum(@as(Soil, @enumFromInt(@min(id, Soil.N - 1))).defaultEdge());
        if (e != want) return false;
    }
    return true;
}

/// A MAP WRITTEN BEFORE THE EDGE GRID gets each cell the edge its material used to imply — stone cut to the
/// cell grid, everything else soft — so an old world comes up looking exactly as it did. Run on load when
/// there was no `soiledge` row, and never otherwise.
fn fillLegacyEdges(m: *Map) void {
    for (m.soil, 0..) |id, i| {
        m.soilEdge[i] = @intFromEnum(@as(Soil, @enumFromInt(@min(id, Soil.N - 1))).defaultEdge());
    }
}

pub const COV_FULL: u8 = 255;

pub fn covF(v: u8) f32 {
    return @as(f32, @floatFromInt(v)) / 255.0;
}

pub fn covByte(v: f32) u8 {
    return @intFromFloat(std.math.clamp(v, 0, 1) * 255.0 + 0.5);
}

/// How much of the brush's radius is laid down at FULL strength before the margin starts.
const BRUSH_CORE: f32 = 0.55;

/// THE BRUSH'S SHAPE: 1 out to `BRUSH_CORE` of the radius, easing to 0 at the rim.
fn brushFalloff(d: f32, radius: f32) f32 {
    if (radius <= 0) return 1;
    const core = radius * BRUSH_CORE;
    if (d <= core) return 1;
    const u = std.math.clamp((radius - d) / (radius - core), 0, 1);
    return u * u * (3.0 - 2.0 * u);
}

/// THE ONE PAINTED-GRID SAMPLER — world position → cell index over an `n`-a-side grid spanning
/// `-half..+half`, or null outside it. The soil grid, the water mask and `env`'s water field all read it,
/// so where the clamp happens relative to the cast cannot be written two ways.
pub fn gridIndex(half: f32, n: usize, px: f32, pz: f32) ?usize {
    if (half <= 0) return null;
    const t = (px + half) / (2 * half);
    const u = (pz + half) / (2 * half);
    // WRITTEN AS THE POSITIVE TEST, so a NaN falls OUT of the grid rather than through it: `t < 0 or t >= 1`
    // is false for NaN either way, and the casts below are illegal behaviour on one. `sampleHeight` gets this
    // for free off `clampF`; this sampler is the other half of the same rule.
    if (!(t >= 0 and t < 1) or !(u >= 0 and u < 1)) return null;
    const nf: f32 = @floatFromInt(n);
    const cx = @min(@as(usize, @intFromFloat(t * nf)), n - 1);
    const cz = @min(@as(usize, @intFromFloat(u * nf)), n - 1);
    return cz * n + cx;
}

// A second painted grid, and a much simpler one: one BIT per cell — wet or dry.
pub const WATER_N: usize = @intCast(gfx.WATER_N);
pub const WATER_CELLS: usize = WATER_N * WATER_N;

// The third painted grid, and the only one with a datum: one QUANTISED HEIGHT per lattice point,
// `HEIGHT_STEP` metres a step, biased so byte `HEIGHT_ZERO` is the old flat ground.
pub const HEIGHT_N: usize = @intCast(gfx.HEIGHT_N);
pub const HEIGHT_CELLS: usize = HEIGHT_N * HEIGHT_N;
/// Metres per quantisation step.
pub const HEIGHT_STEP: f32 = 0.25;
/// The byte that means "ground level" — everything below it is dug out, above it raised.
pub const HEIGHT_ZERO: u8 = 64;
/// How far the encoding reaches: 16 m down (deep enough for any basin) and ~48 m up.
pub const HEIGHT_MIN: f32 = -@as(f32, @floatFromInt(HEIGHT_ZERO)) * HEIGHT_STEP;
pub const HEIGHT_MAX: f32 = @as(f32, @floatFromInt(255 - HEIGHT_ZERO)) * HEIGHT_STEP;

/// Byte → metres, and the inverse.
pub fn heightOf(b: u8) f32 {
    return (@as(f32, @floatFromInt(b)) - @as(f32, @floatFromInt(HEIGHT_ZERO))) * HEIGHT_STEP;
}
pub fn heightByte(m: f32) u8 {
    const q = @round(m / HEIGHT_STEP) + @as(f32, @floatFromInt(HEIGHT_ZERO));
    return @intFromFloat(mathx.clampF(q, 0, 255));
}

/// THE ONE HEIGHT SAMPLER — bilinear over an `HEIGHT_N` lattice spanning `-half..+half` inclusive.
pub fn sampleHeight(field: []const u8, half: f32, px: f32, pz: f32) f32 {
    std.debug.assert(field.len == HEIGHT_CELLS);
    const last: f32 = @floatFromInt(HEIGHT_N - 1);
    const step = 2 * half / last; // POINT pitch: N points, N-1 gaps
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

/// The terrain's GRADIENT at a point: (dh/dx, dh/dz), i.e. metres of rise per metre travelled.
pub fn sampleGrad(field: []const u8, half: f32, px: f32, pz: f32) [2]f32 {
    const step = 2 * half / @as(f32, @floatFromInt(HEIGHT_N - 1));
    const hx1 = sampleHeight(field, half, px + step, pz);
    const hx0 = sampleHeight(field, half, px - step, pz);
    const hz1 = sampleHeight(field, half, px, pz + step);
    const hz0 = sampleHeight(field, half, px, pz - step);
    return .{ (hx1 - hx0) / (2 * step), (hz1 - hz0) / (2 * step) };
}

pub const EMPTY_SPAN: [4]usize = .{ 1, 1, 0, 0 };

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

pub const Sculpt = enum {
    /// Push the ground up by `amount` metres at the centre, tapering to nothing at the rim.
    raise,
    /// …and down.
    lower,
    smooth,
    /// Flatten toward the height under the brush's centre — terraces, building pads, a road.
    flatten,
};


pub const Map = struct {
    name: [NAME_CAP]u8 = [_]u8{0} ** NAME_CAP,
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
    npcs: [MAX_NPCS]Npc = undefined,
    nnpcs: usize = 0,
    trigs: [MAX_TRIGGERS]Trigger = undefined,
    ntrigs: usize = 0,
    dialogs: [MAX_DIALOGS]Dialog = undefined,
    ndialogs: usize = 0,
    /// Every dialog's nodes, flat — a dialog owns a contiguous run of these.
    nodes: [MAX_NODES]Node = undefined,
    nnodes: usize = 0,
    gates: [MAX_GATES]Cond = undefined,
    ngates: usize = 0,
    dacts: [MAX_DACTS]Act = undefined,
    ndacts: usize = 0,
    flagNames: [MAX_FLAGS]Id = undefined,
    nflags: usize = 0,
    counterNames: [MAX_COUNTERS]Id = undefined,
    ncounters: usize = 0,
    timerNames: [MAX_TIMERS]Id = undefined,
    ntimers: usize = 0,
    /// EVERY LINE OF PROSE IN THE WORLD, packed. `Span`s index it.
    dtext: [DTEXT_CAP]u8 = undefined,
    ndtext: u32 = 0,
    /// The painted soil, row-major from -half to +half on both axes.
    soil: [SOIL_CELLS]u8 = [_]u8{0} ** SOIL_CELLS,
    /// HOW STRONGLY that material covers its cell, 0..255 — the same grid, one number deeper.
    soilCov: [SOIL_CELLS]u8 = [_]u8{COV_FULL} ** SOIL_CELLS,
    /// …and HOW THAT PATCH ENDS, one `Edge` per cell. Painted with the stroke, not derived from the
    /// material: the same stone is a laid courtyard in one place and a torn scree in another.
    soilEdge: [SOIL_CELLS]u8 = [_]u8{@intFromEnum(Edge.natural)} ** SOIL_CELLS,
    /// The painted WATER MASK, same layout, 1 = wet.
    water: [WATER_CELLS]u8 = [_]u8{0} ** WATER_CELLS,
    /// …AND HOW ITS COAST RUNS, one `Edge` per cell, painted with the water brush as the soil's is. Baked
    /// into the field by `env.uploadWater` and never read at draw time — see the note there.
    waterEdge: [WATER_CELLS]u8 = [_]u8{@intFromEnum(Edge.natural)} ** WATER_CELLS,
    /// THE SCULPTED GROUND: one quantised height per lattice POINT (see the HEIGHT block above).
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
        self.clearScript();
        self.soil = [_]u8{0} ** SOIL_CELLS;
        self.soilCov = [_]u8{COV_FULL} ** SOIL_CELLS;
        self.soilEdge = [_]u8{@intFromEnum(Edge.natural)} ** SOIL_CELLS;
        self.water = [_]u8{0} ** WATER_CELLS;
        self.waterEdge = [_]u8{@intFromEnum(Edge.natural)} ** WATER_CELLS;
        // To the DATUM, not to zero: `@memset(.., 0)` here would drop the ground to HEIGHT_MIN.
        self.height = [_]u8{HEIGHT_ZERO} ** HEIGHT_CELLS;
    }

    /// THE CLIFF RIM OP AND THE COVER SCATTER, minus their seeds — `blank` gives every new map both, and
    /// the editor's World panel adds a replacement rim off these same numbers.
    pub fn defaultRim() Op {
        var rim = defaults(.edge);
        rim.kind = .cliff;
        rim.r0 = 6.5;
        rim.n = 90;
        rim.sLo = 0.92;
        rim.sHi = 1.24;
        setMix(&rim.mix, &rim.nmix, &props.CLIFFS);
        return rim;
    }
    pub fn defaultCover() Op {
        var cover = defaults(.cover);
        cover.r0 = 3.3; // lattice pitch
        cover.sLo = 0.72;
        cover.sHi = 1.38;
        return cover;
    }

    /// The smallest VALID map: a world-spanning fallback zone plus the cover op that reads it.
    pub fn blank(self: *Map, name: []const u8) void {
        self.* = .{};
        self.setName(name);
        var z = Zone{ .x = -4000, .z = -4000, .x1 = 4000, .z1 = 4000, .density = 0.7 };
        setMix(&z.mix, &z.nmix, &.{ .grasstall, .grasstall, .patch, .tuft, .clover, .moss, .wildflowers });
        z.setName("plain");
        self.zones[0] = z;
        self.nzones = 1;

        var cover = defaultCover();
        cover.seed = 1001;
        self.ops[0] = cover;
        self.nops = 1;

        // The rim, so a new map is bounded terrain rather than a plane running into haze.
        var rim = defaultRim();
        rim.seed = 1002;
        self.ops[1] = self.ops[0];
        self.ops[0] = rim;
        self.nops = 2;
    }

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

    /// Move an op to a new position in the replay order.
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

    /// EVERYTHING THE SCRIPT LAYER OWNS, dropped in one place — `clear` empties the world, and a table it
    /// forgets is a dialog that outlives the map it was written for.
    pub fn clearScript(self: *Map) void {
        self.nnpcs = 0;
        self.ntrigs = 0;
        self.ndialogs = 0;
        self.nnodes = 0;
        self.ngates = 0;
        self.ndacts = 0;
        self.nflags = 0;
        self.ncounters = 0;
        self.ntimers = 0;
        self.ndtext = 0;
    }

    /// The authored prose a span points at.
    pub fn spanText(self: *const Map, s: Span) []const u8 {
        if (s.len == 0 or s.at + s.len > self.ndtext) return "";
        return self.dtext[s.at .. s.at + s.len];
    }

    /// Append a line to the arena. Empty in, empty out — an absent field costs no bytes.
    pub fn addText(self: *Map, s: []const u8) !Span {
        if (s.len == 0) return Span{};
        if (s.len > 0xFFFF or self.ndtext + s.len > DTEXT_CAP) return ParseError.TextFull;
        const at = self.ndtext;
        @memcpy(self.dtext[at .. at + s.len], s);
        self.ndtext += @intCast(s.len);
        return .{ .at = at, .len = @intCast(s.len) };
    }

    pub fn npcSlice(self: *const Map) []const Npc {
        return self.npcs[0..self.nnpcs];
    }
    pub fn trigSlice(self: *const Map) []const Trigger {
        return self.trigs[0..self.ntrigs];
    }
    pub fn nodesOf(self: *const Map, d: *const Dialog) []const Node {
        return self.nodes[d.node0 .. d.node0 + d.nnodes];
    }
    pub fn dialogAt(self: *const Map, i: u16) ?*const Dialog {
        return if (i < self.ndialogs) &self.dialogs[i] else null;
    }
    pub fn findDialog(self: *const Map, name: []const u8) ?u16 {
        for (self.dialogs[0..self.ndialogs], 0..) |*d, i| {
            if (std.mem.eql(u8, d.label(), name)) return @intCast(i);
        }
        return null;
    }
    /// The actions a node or an `ask:` owns.
    pub fn dactRun(self: *const Map, at: u16, n: u8) []const Act {
        if (at + n > self.ndacts) return &.{};
        return self.dacts[at .. at + n];
    }

    /// The interned slot for a name, MINTED if it is new — the one path both the parser's declaration
    /// records and its on-demand uses go through, so a flag used before it is declared is the same flag.
    pub fn internFlag(self: *Map, name: []const u8) !u16 {
        return intern(&self.flagNames, &self.nflags, name, ParseError.TooManyFlags);
    }
    pub fn internCounter(self: *Map, name: []const u8) !u16 {
        return intern(&self.counterNames, &self.ncounters, name, ParseError.TooManyCounters);
    }
    pub fn internTimer(self: *Map, name: []const u8) !u16 {
        return intern(&self.timerNames, &self.ntimers, name, ParseError.TooManyTimers);
    }

    /// …and the read-only side of the same tables, for a debug readout and for tests.
    pub fn findFlag(self: *const Map, name: []const u8) ?u16 {
        return found(self.flagNames[0..self.nflags], name);
    }
    pub fn findCounter(self: *const Map, name: []const u8) ?u16 {
        return found(self.counterNames[0..self.ncounters], name);
    }
    pub fn findTimer(self: *const Map, name: []const u8) ?u16 {
        return found(self.timerNames[0..self.ntimers], name);
    }

    /// IS THIS THE FALLBACK — the one `zoneAt` hands back for ground no rect contains. The editor inserts a
    /// new zone at the FRONT and refuses to erase this one off the same rule.
    pub fn isFallbackZone(self: *const Map, i: usize) bool {
        return self.nzones > 0 and i + 1 == self.nzones;
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

    /// The world size of one cell of an `n`-a-side painted grid.
    pub fn cellSize(self: *const Map, n: usize) f32 {
        return 2 * self.half / @as(f32, @floatFromInt(n));
    }

    pub fn waterIndex(self: *const Map, px: f32, pz: f32) ?usize {
        return gridIndex(self.half, WATER_N, px, pz);
    }

    /// World position → soil cell index, or null when it falls outside the grid.
    pub fn soilIndex(self: *const Map, px: f32, pz: f32) ?usize {
        return gridIndex(self.half, SOIL_N, px, pz);
    }

    /// The edge goes down WITH the stroke and is the stroke's, not the material's — `edge` null takes the
    /// material's own default, which is what every caller that predates the grid wants.
    pub fn paintSoil(self: *Map, px: f32, pz: f32, radius: f32, id: Soil, opacity: f32, edge: ?Edge) bool {
        const ev: u8 = @intFromEnum(edge orelse id.defaultEdge());
        const cell = self.cellSize(SOIL_N);
        const r2 = radius * radius;
        const want = std.math.clamp(opacity, 0, 1);
        var changed = false;
        var cz: usize = 0;
        while (cz < SOIL_N) : (cz += 1) {
            const wz = -self.half + (@as(f32, @floatFromInt(cz)) + 0.5) * cell;
            if (@abs(wz - pz) > radius + cell) continue;
            var cx: usize = 0;
            while (cx < SOIL_N) : (cx += 1) {
                const wx = -self.half + (@as(f32, @floatFromInt(cx)) + 0.5) * cell;
                // The COLUMN reject the row above already had: a stroke runs every frame the mouse moves,
                // and without it every cell of an in-range row paid the full distance and the contest.
                if (@abs(wx - px) > radius + cell) continue;
                const dx = wx - px;
                const dz = wz - pz;
                const d2 = dx * dx + dz * dz;
                if (d2 > r2) continue;
                const i = cz * SOIL_N + cx;
                const v: u8 = @intFromEnum(id);
                // ERASING is not a weak paint and must not be contested
                if (id == .none) {
                    if (self.soil[i] != 0 or self.soilCov[i] != COV_FULL) {
                        self.soil[i] = 0;
                        self.soilCov[i] = COV_FULL;
                        // …and the edge goes back to the DEFAULT, not to whatever the wiped stroke used: a
                        // bare cell has no edge, and one left behind is a policy the next stroke inherits
                        // without having asked for it.
                        self.soilEdge[i] = @intFromEnum(Edge.natural);
                        changed = true;
                    }
                    continue;
                }
                const t = brushFalloff(@sqrt(d2), radius);
                const here: f32 = if (self.soil[i] == v) covF(self.soilCov[i]) else 0;
                const next = here + (want - here) * t;
                const nv = covByte(next);
                // Contest: an incumbent material only loses a cell to coverage that MATCHES OR beats its own.
                if (self.soil[i] != v and self.soil[i] != 0 and nv < self.soilCov[i]) continue;
                if (self.soil[i] != v or self.soilCov[i] != nv or self.soilEdge[i] != ev) {
                    self.soil[i] = v;
                    self.soilCov[i] = nv;
                    // THE EDGE IS THE STROKE'S AND IT IS NOT BLENDED. Coverage is a quantity and eases; a
                    // shape is a choice, and half of one is not a shape. Every cell the stroke wins takes
                    // the shape whole, which is what makes re-painting an area a way to CHANGE its edge.
                    self.soilEdge[i] = ev;
                    changed = true;
                }
            }
        }
        return changed;
    }

    /// Paint (or wipe) a disc of the WATER MASK.
    /// `edge` null leaves each cell's coast shape alone, which is what an ERASE wants — wiping water is not
    /// a statement about how the water that is left ends.
    pub fn paintWater(self: *Map, px: f32, pz: f32, radius: f32, wet: bool, edge: ?Edge) bool {
        const cell = self.cellSize(WATER_N);
        const r2 = radius * radius;
        const v: u8 = if (wet) 1 else 0;
        const ev: ?u8 = if (edge) |e| @intFromEnum(e) else null;
        var changed = false;
        var cz: usize = 0;
        while (cz < WATER_N) : (cz += 1) {
            const wz = -self.half + (@as(f32, @floatFromInt(cz)) + 0.5) * cell;
            if (@abs(wz - pz) > radius + cell) continue;
            var cx: usize = 0;
            while (cx < WATER_N) : (cx += 1) {
                const wx = -self.half + (@as(f32, @floatFromInt(cx)) + 0.5) * cell;
                if (@abs(wx - px) > radius + cell) continue;
                const dx = wx - px;
                const dz = wz - pz;
                if (dx * dx + dz * dz > r2) continue;
                const i = cz * WATER_N + cx;
                if (self.water[i] != v) {
                    self.water[i] = v;
                    changed = true;
                }
                // THE SHAPE GOES DOWN WHOLE, like the soil's: half an edge is not an edge. Laid on every
                // cell the stroke touches, wet or not — a lake's coast runs through the DRY cells just
                // outside it, and the warp has to agree on both sides or it tears.
                if (ev) |want| {
                    if (self.waterEdge[i] != want) {
                        self.waterEdge[i] = want;
                        changed = true;
                    }
                }
            }
        }
        return changed;
    }

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

    pub fn gradAt(self: *const Map, px: f32, pz: f32) [2]f32 {
        return sampleGrad(&self.height, self.half, px, pz);
    }

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
        const target = self.heightAt(px, pz);
        var before: [HEIGHT_N]f32 = undefined; // row iz's heights as they were before this stroke…
        var above: [HEIGHT_N]f32 = undefined;
        var changed = false;
        var iz = zlo;
        while (iz <= zhi) : (iz += 1) {
            if (mode == .smooth) {
                if (iz == zlo) {
                    if (iz > 0) {
                        for (0..HEIGHT_N) |ix| above[ix] = heightOf(self.height[(iz - 1) * HEIGHT_N + ix]);
                    }
                } else above = before;
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
                    .smooth => blk: {
                        const xm = if (ix > 0) before[ix - 1] else cur;
                        const xp = if (ix + 1 < HEIGHT_N) before[ix + 1] else cur;
                        const zm = if (iz > 0) above[ix] else cur;
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


fn found(table: []const Id, name: []const u8) ?u16 {
    for (table, 0..) |*id, i| {
        if (std.mem.eql(u8, idText(id), name)) return @intCast(i);
    }
    return null;
}

fn intern(table: []Id, n: *usize, name: []const u8, full: ParseError) !u16 {
    if (found(table[0..n.*], name)) |i| return i;
    if (n.* >= table.len) return full;
    setId(&table[n.*], name);
    n.* += 1;
    return @intCast(n.* - 1);
}


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
        // …and its COVERAGE, only when some of it is not solid.
        for (m.soilCov) |c| {
            if (c != COV_FULL) {
                try writeGrid(w, "soilcov", &m.soilCov);
                break;
            }
        }
        // …and its EDGES, only when a stroke asked for something other than its material's own default, so
        // a map whose strokes all took the default writes no row and reads back through `fillLegacyEdges`.
        if (!edgesAllDefault(m)) try writeGrid(w, "soiledge", &m.soilEdge);
    }
    // …and the water mask the same way.
    if (m.anyWater()) {
        try w.writeAll("\n");
        try writeGrid(w, "water", &m.water);
        // …and its COAST SHAPES, only when a stroke asked for something other than the default. A map whose
        // every shore is `natural` writes no row and reads back identically, so no existing world changed.
        for (m.waterEdge) |e| {
            if (e != @intFromEnum(Edge.natural)) {
                try writeGrid(w, "wateredge", &m.waterEdge);
                break;
            }
        }
    }
    // …and the SCULPTED GROUND.
    if (m.anyHeight()) {
        try w.writeAll("\n");
        try writeGrid(w, "hgt", &m.height);
    }

    if (m.nfoes > 0) try w.writeAll("\n");
    for (m.foes[0..m.nfoes]) |f| {
        try w.print("foe: {s} {d:.2} {d:.2} {d:.1} {d:.2} {d:.2}\n", .{ @tagName(f.kind), f.x, f.z, f.yaw, f.scale, f.seed });
    }

    try writeScript(m, w);
}

/// The name tables FIRST, then the folk, then the dialogs, then the triggers that drive them. Nothing here
/// depends on the order — `link` resolves after the whole file is read — but a reader does.
fn writeScript(m: *const Map, w: anytype) !void {
    if (m.nflags > 0) {
        try w.writeAll("\nflags:");
        for (m.flagNames[0..m.nflags]) |*id| try w.print(" {s}", .{idText(id)});
        try w.writeAll("\n");
    }
    if (m.ncounters > 0) {
        try w.writeAll("counters:");
        for (m.counterNames[0..m.ncounters]) |*id| try w.print(" {s}", .{idText(id)});
        try w.writeAll("\n");
    }
    if (m.ntimers > 0) {
        try w.writeAll("timers:");
        for (m.timerNames[0..m.ntimers]) |*id| try w.print(" {s}", .{idText(id)});
        try w.writeAll("\n");
    }

    if (m.nnpcs > 0) try w.writeAll("\n");
    for (m.npcSlice()) |*p| {
        try w.print("npc: {s} {d:.2} {d:.2} {d:.1} {d:.2} {d:.2}", .{ @tagName(p.kind), p.x, p.z, p.yaw, p.scale, p.seed });
        if (p.roam != 0) try w.print(" roam={d}", .{p.roam});
        if (p.dlgRef.len > 0) try w.print(" dlg={s}", .{m.spanText(p.dlgRef)});
        try w.writeAll("\n");
        if (p.call.len > 0) try w.print("  call: {s}\n", .{m.spanText(p.call)});
    }

    for (m.dialogs[0..m.ndialogs]) |*d| {
        try w.print("\ndlg: {s}\n", .{d.label()});
        for (m.nodesOf(d)) |*nd| {
            try w.print("  node: {s}\n", .{idText(&nd.id)});
            if (nd.who.len > 0) try w.print("  who: {s}\n", .{m.spanText(nd.who)});
            if (nd.text.len > 0) try w.print("  say: {s}\n", .{m.spanText(nd.text)});
            for (m.dactRun(nd.act0, nd.nact)) |*a| {
                try w.writeAll("  act: ");
                try writeAct(m, w, a);
            }
            for (nd.choiceSlice()) |*c| {
                // An empty target IS the `end` sentinel, and it has to go back out as the word — a bare
                // arrow reads back as a missing field.
                try w.print("  ask: {s} -> {s}\n", .{ m.spanText(c.label), if (c.target.len > 0) m.spanText(c.target) else END_TARGET });
                if (c.gate >= 0) {
                    try w.writeAll("  need: ");
                    try writeCond(m, w, &m.gates[@intCast(c.gate)]);
                }
                for (m.dactRun(c.act0, c.nact)) |*a| {
                    try w.writeAll("  gets: ");
                    try writeAct(m, w, a);
                }
            }
            if (nd.nchoices == 0) try w.print("  then: {s}\n", .{if (nd.thenRef.len > 0) m.spanText(nd.thenRef) else END_TARGET});
        }
    }

    if (m.ntrigs > 0) try w.writeAll("\n");
    for (m.trigSlice()) |*t| {
        try w.print("trig: {s}", .{t.label()});
        if (t.pri != 0) try w.print(" pri={d}", .{t.pri});
        if (!t.once) try w.writeAll(" once=0");
        if (t.wip) try w.writeAll(" wip=1");
        try w.writeAll("\n");
        for (t.condSlice()) |*c| {
            try w.writeAll("  when: ");
            try writeCond(m, w, c);
        }
        for (t.actSlice()) |*a| {
            try w.writeAll("  do: ");
            try writeAct(m, w, a);
        }
    }
}

fn writeCond(m: *const Map, w: anytype, c: *const Cond) !void {
    switch (c.kind) {
        .always, .never => try w.print("{s}\n", .{@tagName(c.kind)}),
        .flag => try w.print("flag {s}={d}\n", .{ idText(&m.flagNames[c.slot]), @as(u8, if (c.on) 1 else 0) }),
        .counter => try w.print("counter {s} {s} {d}\n", .{ idText(&m.counterNames[c.slot]), c.cmp.tok(), c.n }),
        .timer => try w.print("timer {s}={s}\n", .{ idText(&m.timerNames[c.slot]), if (c.on) "done" else "running" }),
        .elapsed => try w.print("elapsed {s} {d}\n", .{ c.cmp.tok(), c.r }),
        .region => try w.print("region {d:.1} {d:.1} {d:.1} {d:.1}\n", .{ c.x, c.z, c.x1, c.z1 }),
        .near => try w.print("near npc={d} r={d}\n", .{ c.slot, c.r }),
        .talked => try w.print("talked {s}\n", .{m.spanText(c.ref)}),
        .deaths => try w.print("deaths {s} {s} {d}\n", .{ @tagName(c.foe), c.cmp.tok(), c.n }),
        .alive => try w.print("alive {s} {s} {d}\n", .{ @tagName(c.foe), c.cmp.tok(), c.n }),
    }
}

fn writeAct(m: *const Map, w: anytype, a: *const Act) !void {
    switch (a.kind) {
        .dialog => try w.print("dialog {s}\n", .{m.spanText(a.ref)}),
        .text => try w.print("text {s}\n", .{m.spanText(a.line)}),
        .flag => try w.print("flag {s}={s}\n", .{ idText(&m.flagNames[a.slot]), switch (a.setop) {
            .off => "0",
            .on => "1",
            .flip => "flip",
        } }),
        .counter => try w.print("counter {s} {s} {d}\n", .{ idText(&m.counterNames[a.slot]), @tagName(a.countop), a.n }),
        .timer => try w.print("timer {s}={d}\n", .{ idText(&m.timerNames[a.slot]), a.v }),
        .wait => try w.print("wait {d}\n", .{a.v}),
        .preserve => try w.writeAll("preserve\n"),
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
    if (o.nloot > 0) {
        try w.writeAll(" loot=");
        for (o.loot[0..o.nloot], 0..) |it, i| {
            if (i > 0) try w.writeAll(",");
            try w.writeAll(item.tag(it));
        }
    }
    try w.writeAll("\n");
}

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
    TooManyNpcs,
    TooManyTriggers,
    TooManyConds,
    TooManyActs,
    TooManyDialogs,
    TooManyNodes,
    TooManyChoices,
    TooManyGates,
    TooManyFlags,
    TooManyCounters,
    TooManyTimers,
    TextFull,
    /// A `when:`/`do:` with no `trig:` above it, a `say:` with no `node:`, a `need:` with no `ask:`.
    NoOwner,
    /// A dialog id, or an `ask:` target, that names nothing in the file.
    UnknownRef,
};

/// The records a multi-line one attaches its parts to. A `when:` belongs to the `trig:` above it, a `say:`
/// to the `node:` above it, a `need:` to the `ask:` above THAT — the same running-cursor idea the RLE grids
/// already use, so the grammar stays one line per fact.
const Cursor = struct {
    trig: ?usize = null,
    npc: ?usize = null,
    dlg: ?usize = null,
    node: ?usize = null,
    choice: ?usize = null,
};

pub fn parse(text: []const u8, m: *Map, lineOut: *usize) !void {
    m.* = .{};
    var seenVersion = false;
    var soilAt: usize = 0; // running cursor, so soil runs may wrap across lines
    var covAt: usize = 0;
    var edgeAt: usize = 0;
    var waterAt: usize = 0;
    var wEdgeAt: usize = 0;
    var hgtAt: usize = 0;
    var cur = Cursor{};
    var lines = std.mem.splitScalar(u8, text, '\n');
    var ln: usize = 0;
    while (lines.next()) |raw| {
        ln += 1;
        lineOut.* = ln;
        const line = trim(stripComment(raw));
        if (line.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return ParseError.UnknownRecord;
        const rec = trim(line[0..colon]);
        const rest = trim(line[colon + 1 ..]); // the WHOLE tail, for the records that carry prose
        var it = std.mem.tokenizeAny(u8, line[colon + 1 ..], " \t");
        if (try parseScript(m, rec, rest, &it, &cur)) continue;
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
            // Runs continue ACROSS lines
            soilAt = try readGrid(&it, &m.soil, soilAt, Soil.N);
        } else if (std.mem.eql(u8, rec, "soilcov")) {
            // Every byte is a legal coverage, so 256 like the heights.
            covAt = try readGrid(&it, &m.soilCov, covAt, 256);
        } else if (std.mem.eql(u8, rec, "soiledge")) {
            edgeAt = try readGrid(&it, &m.soilEdge, edgeAt, Edge.N);
        } else if (std.mem.eql(u8, rec, "water")) {
            waterAt = try readGrid(&it, &m.water, waterAt, 2);
        } else if (std.mem.eql(u8, rec, "wateredge")) {
            wEdgeAt = try readGrid(&it, &m.waterEdge, wEdgeAt, Edge.N);
        } else if (std.mem.eql(u8, rec, "hgt")) {
            hgtAt = try readGrid(&it, &m.height, hgtAt, 256);
        } else if (std.mem.eql(u8, rec, "foe")) {
            if (m.nfoes >= MAX_FOES) return ParseError.TooManyFoes;
            m.foes[m.nfoes] = .{
                .kind = try enumFromName(FoeKind, it.next() orelse return ParseError.MissingField),
                .x = try nextFloat(&it),
                .z = try nextFloat(&it),
                .yaw = try nextFloat(&it),
                .scale = try band(&it, FOE_SCALE_LO, FOE_SCALE_HI),
                .seed = try band(&it, 0, 1),
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
    // A grid is all-or-nothing: a hand-truncated `soil:`/`hgt:` record would leave its tail at
    // defaults with no error, and missing fields are LOAD ERRORS in this format.
    if (soilAt != 0 and soilAt != m.soil.len) return ParseError.MissingField;
    if (covAt != 0 and covAt != m.soilCov.len) return ParseError.MissingField;
    if (edgeAt != 0 and edgeAt != m.soilEdge.len) return ParseError.MissingField;
    if (waterAt != 0 and waterAt != m.water.len) return ParseError.MissingField;
    if (wEdgeAt != 0 and wEdgeAt != m.waterEdge.len) return ParseError.MissingField;
    if (hgtAt != 0 and hgtAt != m.height.len) return ParseError.MissingField;
    // NO `soiledge` ROW MEANS A MAP OLDER THAN THE GRID, and every cell takes the edge its material used to
    // imply. Keyed off the CURSOR rather than off "is the grid all-default", because a map that genuinely
    // wrote an all-natural grid is not the same thing as one that never had the row.
    if (edgeAt == 0) fillLegacyEdges(m);
    // Line numbers stop meaning anything here: a name resolved at the end failed WHEREVER it was written.
    lineOut.* = 0;
    try link(m);
    for (m.ops[0..m.nops]) |*o| {
        if (o.op == .cover) return;
    }
    return ParseError.NoCoverOp;
}

/// One RLE grid record, continuing from `at` and returning the new cursor.
fn readGrid(it: *std.mem.TokenIterator(u8, .any), cells: []u8, at: usize, lim: u16) !usize {
    var cur = at;
    while (it.next()) |tok| {
        const xi = std.mem.indexOfScalar(u8, tok, 'x') orelse return ParseError.BadNumber;
        const v = std.fmt.parseInt(u8, tok[0..xi], 10) catch return ParseError.BadNumber;
        const run = std.fmt.parseInt(usize, tok[xi + 1 ..], 10) catch return ParseError.BadNumber;
        if (v >= lim) return ParseError.BadKind;
        if (run > cells.len - cur) return ParseError.ExtraField;
        @memset(cells[cur .. cur + run], v);
        cur += run;
    }
    return cur;
}

const Toks = std.mem.TokenIterator(u8, .any);

/// Every script record, returning whether it took the line. Splitting it out keeps `parse`'s own chain
/// readable and puts the whole grammar of triggers/dialogs/folk in one place.
fn parseScript(m: *Map, rec: []const u8, rest: []const u8, it: *Toks, cur: *Cursor) !bool {
    if (std.mem.eql(u8, rec, "flags")) {
        while (it.next()) |t| _ = try m.internFlag(t);
        return true;
    }
    if (std.mem.eql(u8, rec, "counters")) {
        while (it.next()) |t| _ = try m.internCounter(t);
        return true;
    }
    if (std.mem.eql(u8, rec, "timers")) {
        while (it.next()) |t| _ = try m.internTimer(t);
        return true;
    }

    if (std.mem.eql(u8, rec, "npc")) {
        if (m.nnpcs >= MAX_NPCS) return ParseError.TooManyNpcs;
        var p = Npc{
            .kind = try enumFromName(NpcKind, it.next() orelse return ParseError.MissingField),
            .x = try nextFloat(it),
            .z = try nextFloat(it),
            .yaw = try nextFloat(it),
            .scale = try band(it, FOE_SCALE_LO, FOE_SCALE_HI),
            .seed = try band(it, 0, 1),
        };
        while (it.next()) |tok| {
            const eq = std.mem.indexOfScalar(u8, tok, '=') orelse return ParseError.UnknownKey;
            const key = tok[0..eq];
            const val = tok[eq + 1 ..];
            if (std.mem.eql(u8, key, "roam")) {
                p.roam = try finiteFloat(f32, val);
                if (p.roam < 0 or p.roam > NPC_ROAM_MAX) return ParseError.BadNumber;
            } else if (std.mem.eql(u8, key, "dlg")) {
                p.dlgRef = try m.addText(val);
            } else return ParseError.UnknownKey;
        }
        m.npcs[m.nnpcs] = p;
        cur.npc = m.nnpcs;
        m.nnpcs += 1;
        return true;
    }
    if (std.mem.eql(u8, rec, "call")) {
        const i = cur.npc orelse return ParseError.NoOwner;
        m.npcs[i].call = try m.addText(rest);
        return true;
    }

    if (std.mem.eql(u8, rec, "trig")) {
        if (m.ntrigs >= MAX_TRIGGERS) return ParseError.TooManyTriggers;
        var t = Trigger{};
        setId(&t.id, it.next() orelse return ParseError.MissingField);
        while (it.next()) |tok| {
            const eq = std.mem.indexOfScalar(u8, tok, '=') orelse return ParseError.UnknownKey;
            const key = tok[0..eq];
            const val = tok[eq + 1 ..];
            if (std.mem.eql(u8, key, "pri")) {
                t.pri = std.fmt.parseInt(i32, val, 10) catch return ParseError.BadNumber;
            } else if (std.mem.eql(u8, key, "once")) {
                t.once = try parseVal(bool, val);
            } else if (std.mem.eql(u8, key, "wip")) {
                t.wip = try parseVal(bool, val);
            } else return ParseError.UnknownKey;
        }
        m.trigs[m.ntrigs] = t;
        cur.trig = m.ntrigs;
        m.ntrigs += 1;
        return true;
    }
    if (std.mem.eql(u8, rec, "when")) {
        const t = &m.trigs[cur.trig orelse return ParseError.NoOwner];
        if (t.nconds >= MAX_CONDS) return ParseError.TooManyConds;
        t.conds[t.nconds] = try parseCond(m, it);
        t.nconds += 1;
        return true;
    }
    if (std.mem.eql(u8, rec, "do")) {
        const t = &m.trigs[cur.trig orelse return ParseError.NoOwner];
        if (t.nacts >= MAX_ACTS) return ParseError.TooManyActs;
        t.acts[t.nacts] = try parseAct(m, rest, it);
        t.nacts += 1;
        return true;
    }

    if (std.mem.eql(u8, rec, "dlg")) {
        if (m.ndialogs >= MAX_DIALOGS) return ParseError.TooManyDialogs;
        var d = Dialog{ .node0 = @intCast(m.nnodes) };
        setId(&d.id, it.next() orelse return ParseError.MissingField);
        if (it.next() != null) return ParseError.ExtraField;
        m.dialogs[m.ndialogs] = d;
        cur.dlg = m.ndialogs;
        cur.node = null;
        cur.choice = null;
        m.ndialogs += 1;
        return true;
    }
    if (std.mem.eql(u8, rec, "node")) {
        const di = cur.dlg orelse return ParseError.NoOwner;
        if (m.nnodes >= MAX_NODES) return ParseError.TooManyNodes;
        var nd = Node{ .act0 = @intCast(m.ndacts) };
        setId(&nd.id, it.next() orelse return ParseError.MissingField);
        if (it.next() != null) return ParseError.ExtraField;
        m.nodes[m.nnodes] = nd;
        cur.node = m.nnodes;
        cur.choice = null;
        m.nnodes += 1;
        m.dialogs[di].nnodes += 1;
        return true;
    }
    if (std.mem.eql(u8, rec, "who")) {
        m.nodes[cur.node orelse return ParseError.NoOwner].who = try m.addText(rest);
        return true;
    }
    if (std.mem.eql(u8, rec, "say")) {
        m.nodes[cur.node orelse return ParseError.NoOwner].text = try m.addText(rest);
        return true;
    }
    if (std.mem.eql(u8, rec, "then")) {
        const nd = &m.nodes[cur.node orelse return ParseError.NoOwner];
        nd.thenRef = if (std.mem.eql(u8, rest, END_TARGET)) Span{} else try m.addText(rest);
        return true;
    }
    if (std.mem.eql(u8, rec, "ask")) {
        const nd = &m.nodes[cur.node orelse return ParseError.NoOwner];
        if (nd.nchoices >= MAX_CHOICES) return ParseError.TooManyChoices;
        const arrow = std.mem.lastIndexOf(u8, rest, "->") orelse return ParseError.MissingField;
        var c = Choice{ .act0 = @intCast(m.ndacts) };
        c.label = try m.addText(trim(rest[0..arrow]));
        const tgt = trim(rest[arrow + 2 ..]);
        if (tgt.len == 0) return ParseError.MissingField;
        c.target = if (std.mem.eql(u8, tgt, END_TARGET)) Span{} else try m.addText(tgt);
        nd.choices[nd.nchoices] = c;
        cur.choice = nd.nchoices;
        nd.nchoices += 1;
        return true;
    }
    if (std.mem.eql(u8, rec, "need")) {
        const nd = &m.nodes[cur.node orelse return ParseError.NoOwner];
        const ci = cur.choice orelse return ParseError.NoOwner;
        if (m.ngates >= MAX_GATES) return ParseError.TooManyGates;
        m.gates[m.ngates] = try parseCond(m, it);
        nd.choices[ci].gate = @intCast(m.ngates);
        m.ngates += 1;
        return true;
    }
    // `act:` hangs on the NODE, `gets:` on the last `ask:` — the same Act either way, and both runs are
    // APPEND-ONLY into `dacts`, which is what makes them contiguous without a second pass.
    if (std.mem.eql(u8, rec, "act") or std.mem.eql(u8, rec, "gets")) {
        const nd = &m.nodes[cur.node orelse return ParseError.NoOwner];
        if (m.ndacts >= MAX_DACTS) return ParseError.TooManyActs;
        // OWNERSHIP IS SETTLED BEFORE THE ARENA IS TOUCHED. Refusing after the append leaves an act in
        // `dacts` that `ndacts` counts and no run reaches, which is the one thing an append-only cursor
        // may not carry.
        const onNode = std.mem.eql(u8, rec, "act");
        if (onNode and nd.nchoices > 0) return ParseError.NoOwner; // …or its run would swallow the choices'
        const ci = if (onNode) 0 else cur.choice orelse return ParseError.NoOwner;
        m.dacts[m.ndacts] = try parseAct(m, rest, it);
        m.ndacts += 1;
        if (onNode) nd.nact += 1 else nd.choices[ci].nact += 1;
        return true;
    }
    return false;
}

fn parseCond(m: *Map, it: *Toks) !Cond {
    var c = Cond{ .kind = try enumFromName(CondKind, it.next() orelse return ParseError.MissingField) };
    switch (c.kind) {
        .always, .never => {},
        .flag => {
            const kv = try splitKV(it);
            c.slot = try m.internFlag(kv.key);
            c.on = try parseVal(bool, kv.val);
        },
        .counter => {
            c.slot = try m.internCounter(it.next() orelse return ParseError.MissingField);
            c.cmp = try cmpFromTok(it.next() orelse return ParseError.MissingField);
            c.n = try nextI32(it);
        },
        .timer => {
            const kv = try splitKV(it);
            c.slot = try m.internTimer(kv.key);
            c.on = std.mem.eql(u8, kv.val, "done");
            if (!c.on and !std.mem.eql(u8, kv.val, "running")) return ParseError.BadKind;
        },
        .elapsed => {
            c.cmp = try cmpFromTok(it.next() orelse return ParseError.MissingField);
            c.r = try nextFloat(it);
        },
        .region => {
            c.x = try nextFloat(it);
            c.z = try nextFloat(it);
            c.x1 = try nextFloat(it);
            c.z1 = try nextFloat(it);
        },
        .near => {
            const npc = try splitKV(it);
            if (!std.mem.eql(u8, npc.key, "npc")) return ParseError.UnknownKey;
            c.slot = std.fmt.parseInt(u16, npc.val, 10) catch return ParseError.BadNumber;
            const r = try splitKV(it);
            if (!std.mem.eql(u8, r.key, "r")) return ParseError.UnknownKey;
            c.r = try finiteFloat(f32, r.val);
        },
        .talked => c.ref = try m.addText(it.next() orelse return ParseError.MissingField),
        .deaths, .alive => {
            c.foe = try enumFromName(FoeKind, it.next() orelse return ParseError.MissingField);
            c.cmp = try cmpFromTok(it.next() orelse return ParseError.MissingField);
            c.n = try nextI32(it);
        },
    }
    if (it.next() != null) return ParseError.ExtraField;
    return c;
}

/// `rest` is the whole tail, which only `text` wants — every other action is tokens.
fn parseAct(m: *Map, rest: []const u8, it: *Toks) !Act {
    const head = it.next() orelse return ParseError.MissingField;
    var a = Act{ .kind = try enumFromName(ActKind, head) };
    switch (a.kind) {
        .dialog => a.ref = try m.addText(it.next() orelse return ParseError.MissingField),
        .text => {
            const at = std.mem.indexOf(u8, rest, head) orelse return ParseError.MissingField;
            a.line = try m.addText(trim(rest[at + head.len ..]));
            if (a.line.len == 0) return ParseError.MissingField;
            return a; // the rest of the line IS the message — no tail to reject
        },
        .flag => {
            const kv = try splitKV(it);
            a.slot = try m.internFlag(kv.key);
            a.setop = if (std.mem.eql(u8, kv.val, "flip")) .flip else if (try parseVal(bool, kv.val)) .on else .off;
        },
        .counter => {
            a.slot = try m.internCounter(it.next() orelse return ParseError.MissingField);
            a.countop = try enumFromName(Countop, it.next() orelse return ParseError.MissingField);
            a.n = try nextI32(it);
        },
        .timer => {
            const kv = try splitKV(it);
            a.slot = try m.internTimer(kv.key);
            a.v = try finiteFloat(f32, kv.val);
            if (a.v < 0) return ParseError.BadNumber;
        },
        .wait => {
            a.v = try nextFloat(it);
            if (a.v < 0) return ParseError.BadNumber;
        },
        .preserve => {},
    }
    if (it.next() != null) return ParseError.ExtraField;
    return a;
}

const KV = struct { key: []const u8, val: []const u8 };

fn splitKV(it: *Toks) !KV {
    const tok = it.next() orelse return ParseError.MissingField;
    const eq = std.mem.indexOfScalar(u8, tok, '=') orelse return ParseError.UnknownKey;
    if (eq == 0 or eq + 1 == tok.len) return ParseError.MissingField;
    return .{ .key = tok[0..eq], .val = tok[eq + 1 ..] };
}

fn nextI32(it: *Toks) !i32 {
    const t = it.next() orelse return ParseError.MissingField;
    return std.fmt.parseInt(i32, t, 10) catch ParseError.BadNumber;
}

/// EVERY NAME RESOLVED AFTER THE WHOLE FILE IS READ, so a dialog may be declared below the trigger that
/// opens it and an `ask:` may point forward at a node it has not reached. Ops replay in file order because
/// each reads what the last one placed; a name is not that kind of dependency.
fn link(m: *Map) !void {
    for (m.npcs[0..m.nnpcs]) |*p| {
        if (p.dlgRef.len == 0) continue;
        p.dlg = m.findDialog(m.spanText(p.dlgRef)) orelse return ParseError.UnknownRef;
    }
    for (m.trigs[0..m.ntrigs]) |*t| {
        for (t.conds[0..t.nconds]) |*c| try linkCond(m, c);
        for (t.acts[0..t.nacts]) |*a| {
            if (a.kind != .dialog) continue;
            a.slot = m.findDialog(m.spanText(a.ref)) orelse return ParseError.UnknownRef;
        }
    }
    // …AND THE `need:` GATES, which are the same `Cond` in a pool of their own. Left out, a `talked` written
    // on an `ask:` line kept slot 0 and silently gated on whichever dialog happened to be declared first.
    for (m.gates[0..m.ngates]) |*c| try linkCond(m, c);
    for (m.dacts[0..m.ndacts]) |*a| {
        if (a.kind != .dialog) continue;
        a.slot = m.findDialog(m.spanText(a.ref)) orelse return ParseError.UnknownRef;
    }
    for (m.dialogs[0..m.ndialogs]) |*d| {
        const run = m.nodes[d.node0 .. d.node0 + d.nnodes];
        for (run) |*nd| {
            nd.next = if (nd.thenRef.len == 0) NO_NODE else try nodeIn(m, d, m.spanText(nd.thenRef));
            for (nd.choices[0..nd.nchoices]) |*c| {
                c.next = if (c.target.len == 0) NO_NODE else try nodeIn(m, d, m.spanText(c.target));
            }
        }
    }
}

/// One condition's forward references — `talked` names a dialog, `near` indexes the npc table. Every pool a
/// `Cond` can live in goes through here, so a new pool cannot inherit half the resolution.
fn linkCond(m: *Map, c: *Cond) !void {
    // A mistyped spawn index would otherwise be a trigger that never fires, not a load error.
    if (c.kind == .near and c.slot >= m.nnpcs) return ParseError.UnknownRef;
    if (c.kind != .talked) return;
    c.slot = m.findDialog(m.spanText(c.ref)) orelse return ParseError.UnknownRef;
}

/// A node name, resolved within ONE dialog — ids are local to their tree, so two dialogs may both have a
/// `root`. Returns the GLOBAL index, which is what a session walks.
fn nodeIn(m: *const Map, d: *const Dialog, name: []const u8) !u16 {
    for (m.nodes[d.node0 .. d.node0 + d.nnodes], 0..) |*nd, i| {
        if (std.mem.eql(u8, idText(&nd.id), name)) return @intCast(d.node0 + i);
    }
    return ParseError.UnknownRef;
}

fn parseZone(it: *std.mem.TokenIterator(u8, .any)) !Zone {
    var z = Zone{};
    z.setName(it.next() orelse return ParseError.MissingField);
    z.x = try nextFloat(it);
    z.z = try nextFloat(it);
    z.x1 = try nextFloat(it);
    z.z1 = try nextFloat(it);
    z.density = try nextFloat(it);
    z.nmix = try parseMix(it.next() orelse return ParseError.MissingField, &z.mix);
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
                if (std.mem.eql(u8, key, "loot")) {
                    o.nloot = try parseLoot(val, &o.loot);
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

fn parseLoot(s: []const u8, out: *[MAX_LOOT]item.Kind) !u8 {
    var n: u8 = 0;
    var parts = std.mem.splitScalar(u8, s, ',');
    while (parts.next()) |p| {
        const t = trim(p);
        if (t.len == 0) continue;
        if (n >= MAX_LOOT) return ParseError.ExtraField;
        out[n] = item.fromTag(t) orelse return ParseError.BadKind;
        n += 1;
    }
    return n;
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


pub const DIR = "worlds";
pub const START_MAP = DIR ++ "/01_fallen_plain" ++ EXT;

var textBuf: [1 << 20]u8 = undefined;

/// `load` parses HERE and copies out only on SUCCESS.
var loadScratch: Map = undefined;

pub fn load(path: []const u8, m: *Map, lineOut: *usize) !void {
    var f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    const n = try f.readAll(&textBuf);
    if (n == textBuf.len) return error.MapTooLarge; // a truncated map parses as a SHORTER world
    try parse(textBuf[0..n], &loadScratch, lineOut);
    m.* = loadScratch;
}

/// Load the world or DIE, printing the file and the line.
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

pub const Listing = struct {
    names: [MAX_FILES][PATH_CAP]u8 = undefined,
    n: usize = 0,

    /// NUL-terminated, because the UI list wants `[:0]const u8`.
    pub fn name(self: *const Listing, i: usize) [:0]const u8 {
        return std.mem.span(@as([*:0]const u8, @ptrCast(&self.names[i])));
    }

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
        std.mem.sort([PATH_CAP]u8, self.names[0..self.n], {}, struct {
            fn lt(_: void, a: [PATH_CAP]u8, b: [PATH_CAP]u8) bool {
                return std.mem.order(u8, std.mem.sliceTo(&a, 0), std.mem.sliceTo(&b, 0)) == .lt;
            }
        }.lt);
    }
};

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
    const stem = n; // where the NAME starts.
    var lastUnderscore = true;
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
        // BOUNDED, like the loops either side of it.
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


/// Is `name` one of this kind's required positionals?
fn isPositional(comptime k: OpKind, comptime name: []const u8) bool {
    // The field walk is O(op kinds x Op fields x name length) string compares at comptime, and the default 1000-branch budget is spent well before it finishes.
    @setEvalBranchQuota(20000);
    for (fieldsOf(k)) |f| {
        if (std.mem.eql(u8, f, name)) return true;
    }
    return false;
}

/// May `name` appear in this kind's optional key=value tail?
fn canTail(comptime k: OpKind, comptime name: []const u8) bool {
    @setEvalBranchQuota(20000);
    // The array-plus-count pairs are written by hand as their own `key=` tail (see writeOp), so the generic field walk must not also try to emit them — an `[8]item.Kind` has no `writeTail` form.
    const never = [_][]const u8{ "op", "mix", "nmix", "loot", "nloot" };
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

/// REFUSE a non-finite float.
fn finiteFloat(comptime T: type, tok: []const u8) !T {
    const v = std.fmt.parseFloat(T, tok) catch return ParseError.BadNumber;
    if (!std.math.isFinite(v)) return ParseError.BadNumber;
    return v;
}

fn nextFloat(it: *std.mem.TokenIterator(u8, .any)) !f32 {
    const t = it.next() orelse return ParseError.MissingField;
    return finiteFloat(f32, t);
}

fn band(it: *std.mem.TokenIterator(u8, .any), lo: f32, hi: f32) !f32 {
    const v = try nextFloat(it);
    if (v < lo or v > hi) return ParseError.BadNumber;
    return v;
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


/// THE SMALLEST MAP THAT LOADS — a version, a zone and the `cover` op `parse` insists on. Lives here rather
/// than in each script test's own file, so a change to what a minimal map must carry breaks one place.
pub const TEST_HEAD =
    \\version: 1
    \\zone: plain -4000 -4000 4000 4000 0.7 grasstall
    \\cover: 3.3 0.72 1.38 seed=1
    \\
;
const SCRIPT_HEAD = TEST_HEAD;

/// …and the parse behind it, reporting the LINE a failure landed on. The caller owns the `Map` (it is far too
/// big for a stack frame) and destroys it.
pub fn testMap(alloc: std.mem.Allocator, text: []const u8) !*Map {
    const m = try alloc.create(Map);
    errdefer alloc.destroy(m);
    var line: usize = 0;
    parse(text, m, &line) catch |e| {
        std.debug.print("test map failed at line {d}: {s}\n", .{ line, @errorName(e) });
        return e;
    };
    return m;
}

/// Every record and every condition/action kind the script layer has, so a new one that forgets its writer or
/// its parser fails HERE rather than the first time somebody authors it.
const SCRIPT_ALL = SCRIPT_HEAD ++
    \\npc: wanderer -6.50 18.00 200.0 1.00 0.31 roam=2.5 dlg=pilgrim
    \\  call: The Wandering Pilgrim
    \\dlg: pilgrim
    \\  node: root
    \\  who: The Wandering Pilgrim
    \\  say: You have the look of one who walks a long road alone.
    \\  act: counter greetings add 1
    \\  ask: The way north? -> north
    \\  ask: Through the gate, then. -> end
    \\  need: flag gate_open=1
    \\  gets: flag told_of_gate=1
    \\  node: north
    \\  say: North the great gate stands shut, and has since before I came.
    \\  then: root
    \\trig: greet pri=10
    \\  when: flag met=0
    \\  when: near npc=0 r=3
    \\  do: dialog pilgrim
    \\  do: flag met=1
    \\trig: everything once=0 wip=1 pri=-2
    \\  when: always
    \\  when: never
    \\  when: counter greetings >= 2
    \\  when: timer dusk=done
    \\  when: elapsed > 30
    \\  when: region -20 -20 20 20
    \\  when: talked pilgrim
    \\  when: deaths toad <= 3
    \\  do: text The gate grinds open somewhere to the north.
    \\  do: counter greetings sub 1
    \\  do: timer dusk=12.5
    \\  do: flag met=flip
    \\  do: wait 1.5
    \\  do: preserve
    \\trig: cleared
    \\  when: alive archer < 1
    \\  do: flag done=1
;

test "the whole script layer round-trips through write and parse" {
    const alloc = std.testing.allocator;
    const m = try alloc.create(Map);
    defer alloc.destroy(m);
    const back = try alloc.create(Map);
    defer alloc.destroy(back);
    var ln: usize = 0;
    parse(SCRIPT_ALL, m, &ln) catch |e| {
        std.debug.print("script parse failed at line {d}: {s}\n", .{ ln, @errorName(e) });
        return e;
    };

    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try write(m, fbs.writer());
    const once = fbs.getWritten();
    parse(once, back, &ln) catch |e| {
        std.debug.print("script re-parse failed at line {d}: {s}\n{s}\n", .{ ln, @errorName(e), once });
        return e;
    };

    // A SECOND PASS MUST BE BYTE-IDENTICAL. Comparing the two WRITES rather than the source is the only
    // honest test of a format whose reader normalises (the `-> end` sentinel, an omitted `then:`, a default
    // `once=1`): source-vs-output would fail on formatting and tell you nothing about the data.
    var buf2: [8192]u8 = undefined;
    var fbs2 = std.io.fixedBufferStream(&buf2);
    try write(back, fbs2.writer());
    try std.testing.expectEqualStrings(once, fbs2.getWritten());

    try std.testing.expectEqual(@as(usize, 1), m.nnpcs);
    try std.testing.expectEqual(@as(usize, 3), m.ntrigs);
    try std.testing.expectEqual(@as(usize, 1), m.ndialogs);
    try std.testing.expectEqual(@as(usize, 2), m.nnodes);
    try std.testing.expectEqualStrings("The Wandering Pilgrim", m.spanText(m.npcs[0].call));
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), m.npcs[0].roam, 1e-6);
    // …and every one of the three tables holds only what was actually named.
    try std.testing.expectEqual(@as(usize, 4), m.nflags); // met, gate_open, told_of_gate, done
    try std.testing.expectEqual(@as(usize, 1), m.ncounters);
    try std.testing.expectEqual(@as(usize, 1), m.ntimers);
}

test "a name is resolved wherever it was written, above or below its use" {
    const alloc = std.testing.allocator;
    const m = try alloc.create(Map);
    defer alloc.destroy(m);
    var ln: usize = 0;
    // The trigger opens a dialog declared BELOW it, and `root` answers to a node declared below THAT.
    try parse(SCRIPT_HEAD ++
        \\trig: t
        \\  when: always
        \\  do: dialog late
        \\dlg: late
        \\  node: root
        \\  say: Hm.
        \\  ask: On. -> tail
        \\  node: tail
        \\  say: Well then.
        \\  then: end
    , m, &ln);
    try std.testing.expectEqual(@as(u16, 0), m.trigs[0].acts[0].slot);
    try std.testing.expectEqual(@as(u16, 1), m.nodes[0].choices[0].next);
    try std.testing.expectEqual(NO_NODE, m.nodes[1].next);
}

test "a GATE's own references are resolved too, not just a trigger's" {
    const alloc = std.testing.allocator;
    const m = try alloc.create(Map);
    defer alloc.destroy(m);
    var ln: usize = 0;
    // THE bug: `link` walked `m.trigs` only, so a `talked` written on an `ask:` line kept slot 0 and gated
    // on whichever dialog was declared first — here, the WRONG one, and silently.
    try parse(SCRIPT_HEAD ++
        \\dlg: first
        \\  node: root
        \\  say: One.
        \\  then: end
        \\dlg: second
        \\  node: root
        \\  say: Two.
        \\  ask: go on -> end
        \\  need: talked second
    , m, &ln);
    try std.testing.expectEqual(@as(u16, 1), m.gates[0].slot);
    // …and a gate naming nothing is the same LOAD ERROR a trigger's would be.
    try std.testing.expectError(ParseError.UnknownRef, parse(SCRIPT_HEAD ++
        \\dlg: d
        \\  node: root
        \\  ask: go on -> end
        \\  need: talked missing
    , m, &ln));
}

test "node ids are local to their own dialog" {
    const alloc = std.testing.allocator;
    const m = try alloc.create(Map);
    defer alloc.destroy(m);
    var ln: usize = 0;
    try parse(SCRIPT_HEAD ++
        \\dlg: a
        \\  node: root
        \\  say: One.
        \\  then: end
        \\dlg: b
        \\  node: root
        \\  say: Two.
        \\  ask: again -> root
    , m, &ln);
    // `b`'s own `root`, not `a`'s — the second dialog's run starts at node 1.
    try std.testing.expectEqual(@as(u16, 1), m.dialogs[1].node0);
    try std.testing.expectEqual(@as(u16, 1), m.nodes[1].choices[0].next);
}

test "a script record with nothing above it, and a name that resolves to nothing, are LOAD ERRORS" {
    const alloc = std.testing.allocator;
    const m = try alloc.create(Map);
    defer alloc.destroy(m);
    var ln: usize = 0;
    try std.testing.expectError(ParseError.NoOwner, parse(SCRIPT_HEAD ++ "  when: always\n", m, &ln));
    try std.testing.expectError(ParseError.NoOwner, parse(SCRIPT_HEAD ++ "  say: nobody said this\n", m, &ln));
    try std.testing.expectError(ParseError.NoOwner, parse(SCRIPT_HEAD ++
        \\dlg: d
        \\  node: root
        \\  need: flag x=1
    , m, &ln));
    try std.testing.expectError(ParseError.UnknownRef, parse(SCRIPT_HEAD ++
        \\trig: t
        \\  when: always
        \\  do: dialog missing
    , m, &ln));
    try std.testing.expectError(ParseError.UnknownRef, parse(SCRIPT_HEAD ++
        \\dlg: d
        \\  node: root
        \\  ask: where -> nowhere
    , m, &ln));
    // …and a node's own actions may not be written after its choices, or its run would swallow theirs.
    try std.testing.expectError(ParseError.NoOwner, parse(SCRIPT_HEAD ++
        \\dlg: d
        \\  node: root
        \\  ask: a -> end
        \\  act: flag x=1
    , m, &ln));
}

test "clear empties the script layer with the world" {
    const alloc = std.testing.allocator;
    const m = try alloc.create(Map);
    defer alloc.destroy(m);
    var ln: usize = 0;
    try parse(SCRIPT_ALL, m, &ln);
    try std.testing.expect(m.ntrigs > 0 and m.ndtext > 0);
    m.clear();
    try std.testing.expectEqual(@as(usize, 0), m.ntrigs);
    try std.testing.expectEqual(@as(usize, 0), m.nnpcs);
    try std.testing.expectEqual(@as(usize, 0), m.ndialogs);
    try std.testing.expectEqual(@as(usize, 0), m.nnodes);
    try std.testing.expectEqual(@as(u32, 0), m.ndtext);
    try std.testing.expectEqual(@as(usize, 0), m.nflags);
}

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

test "A MAP OLDER THAN THE EDGE GRID COMES UP LOOKING THE SAME" {
    // The whole reason `fillLegacyEdges` exists. Written with no `soiledge:` row — which is what every
    // world file on disk is — stone must come back CUT and everything else soft, or adding the grid
    // silently re-shaped every floor already authored.
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    const back = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(back);
    m.blank("Legacy");
    _ = m.paintSoil(0, 0, 30, .stone, 1, null);
    _ = m.paintSoil(-60, 40, 20, .moss, 1, null);

    var buf: [1 << 18]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try write(m, fbs.writer());
    // …and it writes NO edge row, because every stroke took its material's default.
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "soiledge") == null);

    var line: usize = 0;
    try parse(fbs.getWritten(), back, &line);
    for (back.soil, back.soilEdge) |id, e| {
        const want = @as(Soil, @enumFromInt(id)).defaultEdge();
        try std.testing.expectEqual(want, @as(Edge, @enumFromInt(e)));
    }
    try std.testing.expectEqual(Edge.tiled, @as(Edge, @enumFromInt(back.soilEdge[back.soilIndex(0, 0).?])));
}

test "an edge is the STROKE's, so the same material carries two of them" {
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    m.blank("Two Edges");
    _ = m.paintSoil(-60, 0, 15, .stone, 1, .tiled);
    _ = m.paintSoil(60, 0, 15, .stone, 1, .jagged);
    const a = m.soilIndex(-60, 0).?;
    const b = m.soilIndex(60, 0).?;
    try std.testing.expectEqual(m.soil[a], m.soil[b]); // one material…
    try std.testing.expectEqual(Edge.tiled, @as(Edge, @enumFromInt(m.soilEdge[a])));
    try std.testing.expectEqual(Edge.jagged, @as(Edge, @enumFromInt(m.soilEdge[b]))); // …two edges

    // REPAINTING CHANGES THE SHAPE WHOLE. A shape does not ease the way coverage does: half a `tiled` is
    // not a shape, so a stroke that wins a cell takes its edge outright.
    _ = m.paintSoil(-60, 0, 15, .stone, 1, .scallop);
    try std.testing.expectEqual(Edge.scallop, @as(Edge, @enumFromInt(m.soilEdge[a])));

    // …and wiping puts it back to the default rather than leaving a policy for the next stroke to inherit.
    _ = m.paintSoil(-60, 0, 15, .none, 1, null);
    try std.testing.expectEqual(Edge.natural, @as(Edge, @enumFromInt(m.soilEdge[a])));
}

test "the soil grid and foe records survive a round trip" {
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    const back = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(back);
    m.blank("Round Trip");
    // A painted patch plus a lone cell, so both a long run and a one-cell run are exercised.
    _ = m.paintSoil(0, 0, 30, .stone, 1, .jagged);
    _ = m.paintSoil(-60, 40, 20, .moss, 0.4, .scallop);
    m.soil[SOIL_CELLS - 1] = @intFromEnum(Soil.ash);
    m.foes[0] = .{ .kind = .ogre, .x = 3, .z = -50, .yaw = 90, .scale = 1.2, .seed = 0.4 };
    m.nfoes = 1;

    var buf: [1 << 18]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try write(m, fbs.writer());
    var line: usize = 0;
    try parse(fbs.getWritten(), back, &line);

    try std.testing.expectEqualSlices(u8, &m.soil, &back.soil);
    try std.testing.expectEqualSlices(u8, &m.soilCov, &back.soilCov);
    try std.testing.expectEqualSlices(u8, &m.soilEdge, &back.soilEdge);
    try std.testing.expectEqual(@as(usize, 1), back.nfoes);
    try std.testing.expectEqual(FoeKind.ogre, back.foes[0].kind);
    try std.testing.expectApproxEqAbs(@as(f32, 1.2), back.foes[0].scale, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.4), back.foes[0].seed, 1e-4);
}

test "COVERAGE: an untouched grid costs no record, and the four rules the brush is built on" {
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    m.blank("Floors");

    m.soil[10] = @intFromEnum(Soil.dirt);
    {
        var buf: [1 << 18]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        try write(m, fbs.writer());
        try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "soilcov:") == null);
    }

    _ = m.paintSoil(0, 0, 40, .stone, 1, null);
    {
        var buf: [1 << 18]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        try write(m, fbs.writer());
        try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "soilcov:") != null);
    }

    const mid = m.soilIndex(0, 0).?;
    try std.testing.expectEqual(COV_FULL, m.soilCov[mid]);

    _ = m.paintSoil(0, 0, 40, .stone, 0.4, null);
    try std.testing.expect(m.soilCov[mid] < 200);
    for (0..8) |_| _ = m.paintSoil(0, 0, 40, .stone, 0.4, null);
    try std.testing.expectApproxEqAbs(@as(f32, 0.4), covF(m.soilCov[mid]), 0.01);

    _ = m.paintSoil(0, 0, 40, .moss, 0.1, null);
    try std.testing.expectEqual(@intFromEnum(Soil.stone), m.soil[mid]);
    _ = m.paintSoil(0, 0, 40, .moss, 1, null);
    try std.testing.expectEqual(@intFromEnum(Soil.moss), m.soil[mid]);
    _ = m.paintSoil(0, 0, 40, .dirt, 1, null);
    try std.testing.expectEqual(@intFromEnum(Soil.dirt), m.soil[mid]);
    try std.testing.expectEqual(COV_FULL, m.soilCov[mid]);

    _ = m.paintSoil(0, 0, 40, .none, 1, null);
    try std.testing.expectEqual(@as(u8, 0), m.soil[mid]);
    try std.testing.expectEqual(COV_FULL, m.soilCov[mid]);

    _ = m.paintSoil(0, 0, 40, .dirt, 1, null);
    const rim = m.soilIndex(0, 38).?;
    try std.testing.expect(m.soilCov[rim] < m.soilCov[mid]);
}

test "the height field round-trips, and a FLAT map writes no height record at all" {
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    const back = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(back);
    m.blank("Hills");

    // A FLAT map must not carry the record.
    {
        var buf: [1 << 18]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        try write(m, fbs.writer());
        try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "hgt:") == null);
        var line: usize = 0;
        try parse(fbs.getWritten(), back, &line);
        try std.testing.expect(!back.anyHeight());
        try std.testing.expectApproxEqAbs(@as(f32, 0), back.heightAt(0, 0), 1e-6);
        try std.testing.expectApproxEqAbs(@as(f32, 0), back.heightAt(-190, 77), 1e-6);
    }

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
    try std.testing.expect(back.heightAt(-40, 20) > 8.0);
    try std.testing.expect(back.heightAt(30, -10) < -3.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), back.heightAt(0, 200), 1e-6);
}

test "sculpt: the brush tapers, respects its radius, and cannot leave the encoding's range" {
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    m.blank("Sculpt");
    var span: [4]usize = undefined;

    _ = m.sculpt(0, 0, 20, .raise, 6.0, &span);
    const mid = m.heightAt(0, 0);
    const edge = m.heightAt(17, 0);
    try std.testing.expect(mid > 5.5);
    try std.testing.expect(edge > 0.0 and edge < mid * 0.6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), m.heightAt(40, 0), 1e-6); // outside: untouched

    _ = m.sculpt(60, 0, 3, .raise, 8.0, &span);
    const spike = m.heightAt(60, 0);
    _ = m.sculpt(60, 0, 7, .smooth, 1.0, &span);
    try std.testing.expect(m.heightAt(60, 0) < spike - 0.5);
    const plateau = m.heightAt(0, 0);
    _ = m.sculpt(0, 0, 20, .smooth, 1.0, &span);
    try std.testing.expectApproxEqAbs(plateau, m.heightAt(0, 0), HEIGHT_STEP);

    var f: usize = 0;
    while (f < 6) : (f += 1) _ = m.sculpt(0, 0, 20, .flatten, 1.0, &span);
    try std.testing.expectApproxEqAbs(m.heightAt(0, 0), m.heightAt(10, 0), 0.3);

    var i: usize = 0;
    while (i < 40) : (i += 1) _ = m.sculpt(0, 0, 20, .lower, 12.0, &span);
    try std.testing.expect(m.heightAt(0, 0) >= HEIGHT_MIN - 1e-4);
    i = 0;
    while (i < 80) : (i += 1) _ = m.sculpt(0, 0, 20, .raise, 12.0, &span);
    try std.testing.expect(m.heightAt(0, 0) <= HEIGHT_MAX + 1e-4);

    var out: [4]usize = undefined;
    try std.testing.expect(!m.sculpt(9000, 9000, 5, .raise, 4, &out));
    try std.testing.expect(out[0] > out[2] and out[1] > out[3]);
}

test "the height sampler is bilinear, edge-clamped, and its gradient points UPHILL" {
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    m.blank("Ramp");
    // A ramp built by hand: height rises with the x index, nothing varies in z.
    for (0..HEIGHT_N) |iz| {
        for (0..HEIGHT_N) |ix| {
            m.height[iz * HEIGHT_N + ix] = heightByte(@as(f32, @floatFromInt(ix)) * 0.25);
        }
    }
    const step = 2 * m.half / @as(f32, @floatFromInt(HEIGHT_N - 1));
    const x0 = -m.half + 10 * step;
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), m.heightAt(x0, 0), 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 2.625), m.heightAt(x0 + step * 0.5, 0), 1e-3);
    // Off the grid entirely, the edge height CONTINUES rather than dropping to zero: an actor at the world's bound must not fall off a lip that only exists because the field ran out.
    try std.testing.expectApproxEqAbs(m.heightAt(-m.half, 0), m.heightAt(-m.half - 60, 0), 1e-4);
    try std.testing.expectApproxEqAbs(m.heightAt(m.half, 0), m.heightAt(m.half + 60, 0), 1e-4);

    // The gradient: +x is uphill here, z is flat.
    const g = m.gradAt(0, 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), g[0], 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 0), g[1], 1e-4);
}

test "blank() produces a map its own loader accepts" {
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
    try std.testing.expectError(ParseError.BadNumber, parse(cover ++ "belt: fern -1 -1 1 1 10 0.8 1.2 field=ture\n", &m, &ln));
    try std.testing.expectError(ParseError.BadNumber, parse(cover ++ "belt: fern -1 -1 1 1 10 0.8 1.2 field=yes\n", &m, &ln));
    try parse(cover ++ "belt: fern -1 -1 1 1 10 0.8 1.2 field=0\n", &m, &ln);
    try std.testing.expect(!m.ops[1].field);
    // NON-FINITE floats parse fine in std, then crash deep inside env with no file and no line.
    try std.testing.expectError(ParseError.BadNumber, parse(cover ++ "at: pillar nan 0 0 1\n", &m, &ln));
    try std.testing.expectError(ParseError.BadNumber, parse(cover ++ "foe: toad 0 0 0 1 inf\n", &m, &ln));
    try std.testing.expectError(ParseError.BadNumber, parse("version: 1\nhalf: inf\n" ++ cover[11..], &m, &ln));
    // An absurd or non-positive `half` is a hang / an inverted world, not a big map.
    try std.testing.expectError(ParseError.BadNumber, parse("version: 1\nhalf: 0\n" ++ cover[11..], &m, &ln));
    try std.testing.expectError(ParseError.BadNumber, parse("version: 1\nhalf: 99999\n" ++ cover[11..], &m, &ln));
    try std.testing.expectError(ParseError.BadNumber, parse("version: 1\nhalf: 313\n" ++ cover[11..], &m, &ln));
    try parse("version: 1\nhalf: 312\n" ++ cover[11..], &m, &ln);
    try std.testing.expectApproxEqAbs(MAX_DECLARED_HALF, m.half, 1e-4);
    try parse("version: 1\nhalf: 280\n" ++ cover[11..], &m, &ln);
    try std.testing.expectApproxEqAbs(DEFAULT_HALF, m.half, 1e-4);
    try std.testing.expect(DEFAULT_HALF <= MAX_DECLARED_HALF); // the shipped world fits its own ceiling
    // A FOE'S SEED IS A 0..1 DIAL, and out of that band it is not an odd-looking foe: every rig turns it into an RNG stream with `@intFromFloat(@abs(seed) * ~1e5)` into a u64, which past ~1e14 is an out-of-range cast — illegal behaviour, not a big number.
    try std.testing.expectError(ParseError.BadNumber, parse(cover ++ "foe: toad 0 0 0 1 1e20\n", &m, &ln));
    try std.testing.expectError(ParseError.BadNumber, parse(cover ++ "foe: toad 0 0 0 1 -0.5\n", &m, &ln));
    try std.testing.expectError(ParseError.BadNumber, parse(cover ++ "foe: toad 0 0 0 1 1.5\n", &m, &ln));
    // …and both ENDS of the band still load, or the guard has eaten part of what it was protecting.
    try parse(cover ++ "foe: toad 0 0 0 1 0\nfoe: ogre 1 1 0 1 1\n", &m, &ln);
    try std.testing.expectEqual(@as(usize, 2), m.nfoes);
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
    m.reorder(3, 0);
    for (0..5) |i| try std.testing.expectEqual(@as(i32, @intCast(i)), m.ops[i].n);
}

test "A SPAWN'S SCALE IS VALIDATED ON LOAD, because zero is a NaN rig and not a small skeleton" {
    const head = "version: 1\nhalf: 100.0\ncover: 3.3 0.72 1.38\n";
    var m: Map = .{};
    var line: usize = 0;
    try parse(head ++ "foe: toad 0 0 0 1.0 0.5\n", &m, &line);
    try std.testing.expectEqual(@as(usize, 1), m.nfoes);
    // A hand-edited file is the only way past the editor's own stepper, so the LOAD has to hold the band.
    inline for (.{ "0", "0.0", "-1.0", "99.0" }) |bad| {
        try std.testing.expectError(
            ParseError.BadNumber,
            parse(head ++ "foe: toad 0 0 0 " ++ bad ++ " 0.5\n", &m, &line),
        );
    }
}
