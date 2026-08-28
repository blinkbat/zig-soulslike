const std = @import("std");
const rl = @import("raylib");
const props = @import("../props/props.zig");
const mathx = @import("../core/mathx.zig");
const gfx = @import("../gfx/gfx.zig");
const item = @import("../play/item.zig");

const Kind = props.Kind;


pub const VERSION: u32 = 1;

/// Playable half-extent when a map doesn't say otherwise; the world spans 2x this per axis.
pub const DEFAULT_HALF: f32 = 280.0;

pub const MAX_DECLARED_HALF: f32 = 312.0;

/// **RAISED FROM 2048 WHEN THE GLOBAL COVER OP WAS BAKED INTO ORDINARY DECOR** — one `cover:` line grew 13,228 plants a man could not select or delete, each its own `at:` op now on top of the map's ~1,290. Raised again when the WOOD went the same way (`env.explodeOp`): a generator op is one thing to delete, so 260 attempts were one tree. This number IS memory: the editor's 24-deep undo ring is whole-`Map` copies.
pub const MAX_OPS: usize = 20480;
pub const MAX_MIX: usize = 24;
pub const MAX_LOOT: usize = 8;
/// Creatures one fog gate may seal on. Two is the duo; the spare is for the warband nobody has authored yet.
pub const MAX_SEAL: usize = 4;
pub const MAX_ZONES: usize = 16;
pub const MAX_CLEARINGS: usize = 32;
/// Rooms a map may wall. A map wanting more than this many sealed fights is not one map.
pub const MAX_ARENAS: usize = 8;
/// Corners one room may have. **THREE IS THE FLOOR** — two points are a line and bound nothing — and the cap
/// is what a hand-drawn room takes before it is really terrain.
pub const MAX_ARENA_VERTS: usize = 24;
/// **THE ONE FOE LIMIT** (owner: can u make it 512, this map is huge). Every group's slab is this wide too
/// (`MAX_PER_KIND`), so raising it costs one slab per `game.FOE_GROUPS` row — and so does every creature added,
/// which is the term that actually moves: at 512 the twenty-nine rows measure 144.4 MB of the one startup allocation (`game.zig`'s "WHAT THE FRAME COSTS" prints it), and `build.zig`'s
/// stack reserve carries the same figure again because startup builds those
/// groups BY VALUE. Both are address space rather than resident memory; the frame cost is nil, since every pass walks `live()`.
pub const MAX_FOES: usize = 512;
pub const FOE_SCALE_LO: f32 = 0.5;
pub const FOE_SCALE_HI: f32 = 2.0;
pub const NAME_CAP: usize = 48;


pub const OpKind = enum(u8) {
    at,
    belt,
    disc,
    ring,
    line,
    ivy,
};

pub const Avoid = struct {
    runway: bool = false,
    water: bool = false,
    clear: bool = false,
    solid: bool = false,
};

pub const Axis = enum(u8) { none, x, z };

pub const Op = struct {
    op: OpKind = .at,
    kind: Kind = .pillar,
    x: f32 = 0,
    z: f32 = 0,
    x1: f32 = 0,
    z1: f32 = 0,
    r0: f32 = 0,
    /// disc outer radius — and, for an `at`, HOW FAR OFF THE GROUND the one prop is lifted, in metres (`env.Placer.expand`). It is not one of `at`'s positionals, so it only ever arrives as an `r1=` tail.
    r1: f32 = 0,
    yaw: f32 = 0,
    scale: f32 = 1,
    /// TIP THE PROP OFF PLUMB: `lean` degrees, toward the compass direction `leanDir` (measured like yaw).
    lean: f32 = 0,
    leanDir: f32 = 0,
    sLo: f32 = 0.85,
    sHi: f32 = 1.15,
    n: i32 = 0,
    skip: i32 = -1,
    seed: u64 = 0,
    chance: f32 = 1.0,
    bias: f32 = 0,
    field: bool = false,
    gAxis: Axis = .none,
    gA: f32 = 0,
    gB: f32 = 0,
    gFloor: f32 = 0,
    avoid: Avoid = .{},
    mix: [MAX_MIX]Kind = undefined,
    nmix: u8 = 0,
    /// What is in the CONTAINER this op placed — a chest, or an item pickup (`props.holdsLoot`). Written and parsed on `nloot > 0` alone and never on the kind, which is why the glow needed no format change.
    loot: [MAX_LOOT]item.Kind = undefined,
    nloot: u8 = 0,
    /// WHAT MUST DIE BEFORE A FOG GATE OPENS AGAIN — read by `ward` kinds alone (`props.Info.ward`), the way `loot` is read by containers alone. `boss=-` in the file is a gate that never shuts: a doorway, not an arena. **A DUO IS TWO, SO THE SEAL IS A LIST** (`fungalduo`): the gate holds while ANY name on it still stands, and every bar behind it waits on the same list (`game.bossBars`). The default is the FIRST boss, so a stamped gate works with nothing typed and writes no tail.
    boss: [MAX_SEAL]FoeKind = [_]FoeKind{.bone_knight} ** MAX_SEAL,
    nboss: u8 = 1,

    /// The creatures this gate is sealed on, in the order they were picked. Empty is a doorway.
    pub fn seal(self: *const Op) []const FoeKind {
        return sealList(&self.boss, self.nboss);
    }

    pub fn sealsOn(self: *const Op, k: FoeKind) bool {
        return sealHas(self.seal(), k);
    }

    pub fn pick(self: *const Op, r: *mathx.Rng) Kind {
        if (self.nmix == 0) return self.kind;
        return self.mix[@intCast(r.intn(@intCast(self.nmix)))];
    }

    pub fn stream(self: *const Op) mathx.Rng {
        return mathx.Rng.init(self.seed);
    }

    pub fn gradAt(self: *const Op, px: f32, pz: f32) f32 {
        const v = switch (self.gAxis) {
            .none => return 1.0,
            .x => px,
            .z => pz,
        };
        return self.gFloor + (1.0 - self.gFloor) * mathx.smoothstep(self.gA, self.gB, v);
    }
};

fn fieldsOf(comptime k: OpKind) []const []const u8 {
    return switch (k) {
        .at => &.{ "kind", "x", "z", "yaw", "scale" },
        .belt => &.{ "kind", "x", "z", "x1", "z1", "n", "sLo", "sHi" },
        .disc => &.{ "kind", "x", "z", "r0", "r1", "n", "sLo", "sHi" },
        .ring => &.{ "kind", "x", "z", "r0", "n", "sLo", "sHi" },
        .line => &.{ "kind", "x", "z", "x1", "z1", "r0", "sLo", "sHi" },
        .ivy => &.{ "kind", "x", "z", "x1", "z1", "sLo", "sHi" },
    };
}

comptime {
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
        .line => o.chance = 0.78,
        .ivy => o.chance = 0.55,
    }
    return o;
}


pub const MAX_LOCATIONS: usize = 64;

/// **THE ONE RECTANGLE TEST.** Four rows carry a corner pair — a location, a zone, the runway and `Cond.region` —
/// and two of the four normalised the corners while two compared them raw, so a rect authored with `x1 < x`
/// answered for nothing in one and for its own area in the other. The editor always emits them normalised
/// (`normRect`); a hand-written map never had to.
pub fn inRect(px: f32, pz: f32, x0: f32, z0: f32, x1: f32, z1: f32) bool {
    return px >= @min(x0, x1) and px <= @max(x0, x1) and pz >= @min(z0, z1) and pz <= @max(z0, z1);
}

/// StarEdit's Location: declared ONCE and referred to by name, where `Cond.region`'s inline coordinates meant
/// two triggers about one doorway held two copies of it.
///
/// **THEY OVERLAP FREELY AND THE MOST RECENTLY PAINTED ONE WINS** — `locationAt` takes the FIRST match and the editor prepends. Any other rule makes a location you can see disagree with the one that answers.
pub const Location = struct {
    name: [NAME_CAP]u8 = [_]u8{0} ** NAME_CAP,
    x: f32 = 0,
    z: f32 = 0,
    x1: f32 = 0,
    z1: f32 = 0,
    /// **THE WEATHER THIS PLACE KEEPS**, or null for "no opinion". There is ONE sky, ONE sun and ONE rain sheet drawn round the camera, so a location cannot make it rain over there while it is dry here: what it does is drive the GLOBAL level while he is inside it, cross-faded over `blend`.
    wet: ?f32 = null,
    fog: ?f32 = null,
    /// **SPOREFALL** — fog's third channel, and a DIFFERENT weather rather than a tint on the same one: it carries the peach haze, the lit banks and the motes together, and it is the only one of the three that reads at all on a clear bright hour.
    spore: ?f32 = null,
    /// Seconds the cross-fade takes, in or out. A hard switch at the boundary is a pop.
    blend: f32 = 6.0,

    pub fn contains(self: *const Location, px: f32, pz: f32) bool {
        return inRect(px, pz, self.x, self.z, self.x1, self.z1);
    }
    /// Does it say anything about the sky at all? A location with no weather is still a perfectly good location — it is a name for a place, and the script layer is its other customer.
    pub fn hasWeather(self: *const Location) bool {
        return self.wet != null or self.fog != null or self.spore != null;
    }
    pub fn label(self: *const Location) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }
    pub fn setName(self: *Location, s: []const u8) void {
        self.name = [_]u8{0} ** NAME_CAP;
        const n = @min(s.len, NAME_CAP - 1);
        @memcpy(self.name[0..n], s[0..n]);
    }
};

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
        return inRect(px, pz, self.x, self.z, self.x1, self.z1);
    }
    pub fn pick(self: *const Zone, rng: *mathx.Rng) ?Kind {
        if (self.nmix == 0) return null;
        return self.mix[@intCast(rng.intn(@intCast(self.nmix)))];
    }
    pub fn label(self: *const Zone) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }
    pub fn setName(self: *Zone, s: []const u8) void {
        self.name = [_]u8{0} ** NAME_CAP;
        const n = @min(s.len, NAME_CAP - 1);
        @memcpy(self.name[0..n], s[0..n]);
    }
};

/// Do the two open segments properly cross? Written on the sign of four turns rather than on an intersection
/// point, so a shared endpoint and a parallel pair answer FALSE without a division anywhere.
fn segsCrossXZ(ax: f32, az: f32, bx: f32, bz: f32, cx: f32, cz: f32, dx: f32, dz: f32) bool {
    const d1 = turn(cx, cz, dx, dz, ax, az);
    const d2 = turn(cx, cz, dx, dz, bx, bz);
    const d3 = turn(ax, az, bx, bz, cx, cz);
    const d4 = turn(ax, az, bx, bz, dx, dz);
    return ((d1 > 0) != (d2 > 0)) and ((d3 > 0) != (d4 > 0));
}

fn turn(ax: f32, az: f32, bx: f32, bz: f32, px: f32, pz: f32) f32 {
    return (bx - ax) * (pz - az) - (bz - az) * (px - ax);
}

pub fn setMix(dst: *[MAX_MIX]Kind, n: *u8, mix: []const Kind) void {
    const k = @min(mix.len, MAX_MIX);
    @memcpy(dst[0..k], mix[0..k]);
    n.* = @intCast(k);
}

/// **THE DOOR AND THE ROOM CARRY THE SAME SEAL, SO THEY ASK IT THE SAME WAY.** Both keep it as plain fields
/// because both are serialized off the format's own field table; every question about it lives here.
pub fn sealList(boss: *const [MAX_SEAL]FoeKind, n: u8) []const FoeKind {
    return boss[0..@min(n, MAX_SEAL)];
}

pub fn sealHas(seal: []const FoeKind, k: FoeKind) bool {
    for (seal) |s| {
        if (s == k) return true;
    }
    return false;
}

/// **IS ANY NAME ON IT STILL STANDING** — a duo is two, and a seal that let go with half the fight up let you
/// walk out of an arena you were sealed into. `alive` is the per-kind tally the loop already keeps.
pub fn sealStanding(seal: []const FoeKind, alive: []const u32) bool {
    for (seal) |b| {
        const i = @intFromEnum(b);
        if (i < alive.len and alive[i] > 0) return true;
    }
    return false;
}

/// `boss=a,b`, or `boss=-` for a seal that names nobody. The exact inverse of `parseSeal`.
pub fn writeSeal(w: anytype, seal: []const FoeKind) !void {
    try w.writeAll(" boss=");
    if (seal.len == 0) try w.writeAll("-");
    for (seal, 0..) |k, i| {
        if (i > 0) try w.writeAll(",");
        try w.writeAll(@tagName(k));
    }
}

pub const Clearing = struct { x: f32 = 0, z: f32 = 0, r: f32 = 12 };

/// **WHERE THE PLAYER STANDS UP.** Every world put him at (0, 4) facing south because `game.beginGame` said
/// so and the format had no way to disagree — which is why every test map had to be built around that spot.
/// `yaw` is the house convention, degrees, 0 facing +Z.
pub const Start = struct {
    x: f32 = 0,
    z: f32 = 4,
    yaw: f32 = 180,

    pub fn at(self: *const Start) rl.Vector3 {
        return mathx.ground(self.x, self.z);
    }
    pub fn facing(self: *const Start) f32 {
        return mathx.radians(self.yaw);
    }
};

/// **A ROOM, AND THE FOG GATE IS ONLY ITS DOOR.** The gate refuses one line 0.8 m thick, so an arena on open
/// ground is a gate you walk round and a magus that dissolves out of its own fight (owner). An XZ polygon that
/// holds every body inside it, his included, for as long as `boss` still stands.
///
/// **THE SEAL IS THE ROOM'S AND NOT THE DOOR'S** (`Op.boss` is the gate's own copy, same grammar) — a room can
/// be walled with no gate in it, and a gate can be a doorway in no room. Where a map has both, a test pins the
/// two lists against each other rather than trusting them to agree.
pub const Arena = struct {
    name: [NAME_CAP]u8 = [_]u8{0} ** NAME_CAP,
    vx: [MAX_ARENA_VERTS]f32 = [_]f32{0} ** MAX_ARENA_VERTS,
    vz: [MAX_ARENA_VERTS]f32 = [_]f32{0} ** MAX_ARENA_VERTS,
    n: u8 = 0,
    boss: [MAX_SEAL]FoeKind = [_]FoeKind{.bone_knight} ** MAX_SEAL,
    nboss: u8 = 1,

    /// Empty is bounds that never hold.
    pub fn seal(self: *const Arena) []const FoeKind {
        return sealList(&self.boss, self.nboss);
    }

    pub fn sealsOn(self: *const Arena, k: FoeKind) bool {
        return sealHas(self.seal(), k);
    }

    pub fn verts(self: *const Arena) usize {
        return @min(self.n, MAX_ARENA_VERTS);
    }

    /// **EVEN-ODD, AND THE HALF-OPEN RULE ON Z IS WHAT MAKES A SHARED CORNER COUNT ONCE.** Written with two
    /// `<=` a ray through a vertex crosses both its edges and the point outside reads as inside.
    pub fn contains(self: *const Arena, px: f32, pz: f32) bool {
        const n = self.verts();
        if (n < 3) return false;
        var in = false;
        var j = n - 1;
        for (0..n) |i| {
            const zi = self.vz[i];
            const zj = self.vz[j];
            if ((zi > pz) != (zj > pz)) {
                const t = (pz - zi) / (zj - zi);
                if (px < self.vx[i] + t * (self.vx[j] - self.vx[i])) in = !in;
            }
            j = i;
        }
        return in;
    }

    /// The distance is unsigned — `contains` answers which side of the wall `p` is on.
    pub fn nearestWall(self: *const Arena, p: rl.Vector3) struct { at: rl.Vector3, d: f32 } {
        const n = self.verts();
        // `j = n - 1` on a usize is the wrap, not -1: an Arena with no corners panicked here rather than
        // answering. `hold` and `onWall` guard it themselves, but this is `pub` and the next caller will not.
        if (n < 3) return .{ .at = p, .d = 0 };
        var best = mathx.zero3;
        var bd: f32 = std.math.floatMax(f32);
        var j = n - 1;
        for (0..n) |i| {
            const q = mathx.closestOnSegXZ(p, mathx.ground(self.vx[j], self.vz[j]), mathx.ground(self.vx[i], self.vz[i]));
            const d = mathx.distXZ(q, p);
            if (d < bd) {
                bd = d;
                best = q;
            }
            j = i;
        }
        return .{ .at = best, .d = bd };
    }

    /// **THE WALL IS A PUSH-OUT, NOT A REFUSAL.** A blink lands a body wherever it lands and a refusal would
    /// strand it; the room takes it by the shoulder and stands it `r` back inside its own line.
    ///
    /// It walks every wall on every call, and the obvious cache — the room's INRADIUS off `middle`, which by the
    /// triangle inequality lets a body near the centre skip that walk in one distance test — is NOT applied.
    /// MEASURED on the shipped room: 11 walls, six bodies, two calls a frame each is **396 crossings a frame**,
    /// and every map with no `arena:` row pays a zero-length loop. There is nothing there to buy.
    pub fn hold(self: *const Arena, p: rl.Vector3, r: f32) rl.Vector3 {
        if (self.verts() < 3) return p;
        const inside = self.contains(p.x, p.z);
        const near = self.nearestWall(p);
        if (inside and near.d >= r) return p;
        // Toward the interior: away from the wall when he is in, toward it when he is out. On the line itself
        // neither is defined, so the centroid is what breaks the tie.
        var dir = if (inside) mathx.dirXZ(near.at, p) else mathx.dirXZ(p, near.at);
        if (mathx.lenXZ(dir) < 1e-4) dir = mathx.dirXZ(near.at, self.middle());
        if (mathx.lenXZ(dir) < 1e-4) return p;
        const u = mathx.normV(dir);
        return mathx.v3(near.at.x + u.x * r, p.y, near.at.z + u.z * r);
    }

    /// **HOW NEAR A GATE HAS TO STAND TO COUNT AS BEING IN THIS ROOM'S WALL.** A door is authored ON the line;
    /// the slack is for a hand-typed corner, not for a gate somewhere in the middle of the floor.
    pub const GATE_ON_WALL: f32 = 2.0;

    /// What pairs a fog gate to the room it is the door of.
    pub fn onWall(self: *const Arena, px: f32, pz: f32) bool {
        if (self.verts() < 3) return false;
        return self.nearestWall(mathx.ground(px, pz)).d <= GATE_ON_WALL;
    }

    /// **DOES THE OUTLINE CROSS ITSELF.** A figure-of-eight room has an even-odd test that answers `false` in
    /// its own middle, so it holds nothing where it looks most like a room — and it is drawn by hand, so
    /// nothing else would catch it. O(n2) over at most `MAX_ARENA_VERTS`, and only ever asked offline.
    pub fn simple(self: *const Arena) bool {
        const n = self.verts();
        if (n < 3) return false;
        for (0..n) |i| {
            for (0..n) |j| {
                // Adjacent edges SHARE a corner, which is a touch and not a crossing.
                if (j <= i + 1 or (i == 0 and j == n - 1)) continue;
                if (segsCrossXZ(
                    self.vx[i],
                    self.vz[i],
                    self.vx[(i + 1) % n],
                    self.vz[(i + 1) % n],
                    self.vx[j],
                    self.vz[j],
                    self.vx[(j + 1) % n],
                    self.vz[(j + 1) % n],
                )) return false;
            }
        }
        return true;
    }

    /// The corners' mean — a tie-break and a place to aim a camera, never a centre of area.
    pub fn middle(self: *const Arena) rl.Vector3 {
        const n = self.verts();
        if (n == 0) return mathx.zero3;
        var sx: f32 = 0;
        var sz: f32 = 0;
        for (0..n) |i| {
            sx += self.vx[i];
            sz += self.vz[i];
        }
        const k: f32 = @floatFromInt(n);
        return mathx.ground(sx / k, sz / k);
    }

    pub fn label(self: *const Arena) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }
    pub fn setName(self: *Arena, s: []const u8) void {
        self.name = [_]u8{0} ** NAME_CAP;
        const n = @min(s.len, NAME_CAP - 1);
        @memcpy(self.name[0..n], s[0..n]);
    }
};

/// APPEND-ONLY in spirit, like `gfx.Mat`: the editor's unit brushes are pinned to this enum's ORDER at comptime, and each `roleOf` reads its own entries as a CONTIGUOUS RUN off the first of them.
pub const FoeKind = enum(u8) { toad, archer, ogre, berserker, priest, slinger, brood_mother, broodling, brood_sac, shieldman, greatsword, shade, leechfly, rooted, shroom, bone_knight, delver, necromancer, florid_ravager, mushroom_mage, fen_lurker, spore_golem, bone_skitterer, ancient_priest, tolling_hollow, mourner, slumber_bloom, cinder_wake, rotgorger, birchwight, salt_husk, fish_spearman, fish_netter, fish_shaman, blinkbat, fungal_swordsman, fungal_magus };

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
        .necromancer => "Necromancer",
        .florid_ravager => "Florid Ravager",
        .mushroom_mage => "Mushroom Mage",
        .fen_lurker => "Fen Lurker",
        .spore_golem => "Spore Homunculus",
        .bone_skitterer => "Bone Skitterer",
        .ancient_priest => "Ancient Priest",
        .tolling_hollow => "Tolling Hollow",
        .mourner => "Mourner",
        .slumber_bloom => "Slumber Bloom",
        .cinder_wake => "Cinder Wake",
        .rotgorger => "Rotgorger",
        .birchwight => "Birchwight",
        .salt_husk => "Salt Husk",
        .fish_spearman => "Fishman Spearman",
        .fish_netter => "Fishman Netter",
        .fish_shaman => "Fishman Shaman",
        .blinkbat => "Blinkbat",
        .fungal_swordsman => "Fungal Swordsman",
        .fungal_magus => "Fungal Magus",
    };
}

/// **WHAT A UNIT DOES BEFORE IT HAS SEEN ANYBODY.** The names are StarEdit's, because that is the vocabulary
/// these maps are authored in: JUNKYARD DOG is roaming about a post, leashed or not. APPEND-ONLY like every
/// other authored enum. **`hold` is what every unit did before this existed**, so a map that never mentions
/// `ai=` loads unchanged.
pub const FoeAi = enum(u8) {
    hold,
    roam,
    roam_free,
    patrol,
};

/// A painted patrol point. Ground only — the route follows the terrain the unit stands on.
pub const Wp = struct { x: f32 = 0, z: f32 = 0 };
/// Per unit. Eight legs is a long beat for a guard and keeps the map's foe table at 34 KB across `MAX_FOES`.
pub const MAX_WP: usize = 8;

pub const Foe = struct {
    kind: FoeKind = .toad,
    x: f32 = 0,
    z: f32 = 0,
    yaw: f32 = 0,
    scale: f32 = 1,
    seed: f32 = 0,
    ai: FoeAi = .hold,
    wp: [MAX_WP]Wp = [_]Wp{.{}} ** MAX_WP,
    nwp: u8 = 0,

    pub fn route(self: *const Foe) []const Wp {
        return self.wp[0..@min(self.nwp, MAX_WP)];
    }

    /// **THE ROUTE IS WORLD-SPACE, SO IT MOVES WITH THE BODY.** Every editor gesture that shifts a spawn — the
    /// marquee drag, the clipboard's centring and its paste, the inspector's steppers — moved `x`/`z` alone and
    /// left a patrol walking back to the coordinates the unit was copied from.
    pub fn translate(self: *Foe, dx: f32, dz: f32) void {
        self.x += dx;
        self.z += dz;
        self.moveRoute(dx, dz);
    }

    /// For the one mover that writes `x`/`z` in place (the inspector's steppers): the legs take the same delta.
    pub fn moveRoute(self: *Foe, dx: f32, dz: f32) void {
        if (dx == 0 and dz == 0) return;
        for (self.wp[0..@min(self.nwp, MAX_WP)]) |*q| {
            q.x += dx;
            q.z += dz;
        }
    }
};

/// **THERE IS ONE FOE LIMIT AND IT IS `MAX_FOES`** (owner: remove the foe limits, seems dumb to have). At 24 a
/// per-kind cap sat under the global one: `foe.resetGroup` fills a fixed slab and `continue`s past the
/// overflow, so a 25th shroom was a body the map placed, the editor drew, the save counted and the level never
/// spawned — and `01_fallen_plain` stands on exactly 24. Set to the whole budget it cannot bite. It costs memory — measured, the slabs come to 101.6 MB of one startup allocation.
pub const MAX_PER_KIND: usize = MAX_FOES;

pub const Runway = struct { x: f32 = -3.4, z: f32 = -44, x1: f32 = 3.4, z1: f32 = 30 };



pub const ID_CAP: usize = 24;
pub const Id = [ID_CAP]u8;

pub const MAX_NPCS: usize = 32;
pub const MAX_TRIGGERS: usize = 64;
pub const MAX_CONDS: usize = 8;
pub const MAX_ACTS: usize = 8;
pub const MAX_DIALOGS: usize = 32;
pub const MAX_NODES: usize = 192;
pub const MAX_CHOICES: usize = 5;
pub const MAX_GATES: usize = 64;
pub const MAX_DACTS: usize = 128;
pub const MAX_FLAGS: usize = 48;
pub const MAX_COUNTERS: usize = 48;
pub const MAX_TIMERS: usize = 16;
pub const DTEXT_CAP: usize = 8192;

pub const NO_NODE: u16 = 0xFFFF;
pub const NO_DIALOG: u16 = 0xFFFF;
pub const END_TARGET = "end";

pub const Span = struct { at: u32 = 0, len: u16 = 0 };

/// **AN ID THAT DOES NOT FIT IS A LOAD ERROR, NEVER A TRUNCATED ONE.** Every id here is a REFERENCE and
/// `found` compares the stored text against the full name, so a clipped one never matches itself: a
/// 26-character flag interned a fresh row per mention, and the `do:` that set it and the `need:` that read
/// it landed on different rows with the gate never opening.
pub fn setId(dst: *Id, s: []const u8) !void {
    if (s.len >= ID_CAP) return ParseError.NameTooLong;
    dst.* = [_]u8{0} ** ID_CAP;
    @memcpy(dst[0..s.len], s);
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
    always,
    never,
    flag,
    counter,
    timer,
    elapsed,
    region,
    near,
    talked,
    deaths,
    alive,
};

pub const Cond = struct {
    kind: CondKind = .always,
    slot: u16 = 0,
    ref: Span = .{},
    foe: FoeKind = .toad,
    cmp: Cmp = .ge,
    n: i32 = 0,
    r: f32 = 0,
    x: f32 = 0,
    z: f32 = 0,
    x1: f32 = 0,
    z1: f32 = 0,
    on: bool = false,
};

pub const Setop = enum(u8) { off, on, flip };
pub const Countop = enum(u8) { set, add, sub };

pub const ActKind = enum(u8) {
    dialog,
    text,
    flag,
    counter,
    timer,
    wait,
    preserve,
};

pub const Act = struct {
    kind: ActKind = .preserve,
    slot: u16 = 0,
    ref: Span = .{},
    setop: Setop = .on,
    countop: Countop = .set,
    n: i32 = 0,
    v: f32 = 0,
    line: Span = .{},
};

pub const Trigger = struct {
    id: Id = [_]u8{0} ** ID_CAP,
    pri: i32 = 0,
    once: bool = true,
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
    target: Span = .{},
    next: u16 = NO_NODE,
    gate: i16 = -1,
    act0: u16 = 0,
    nact: u8 = 0,
};

pub const Node = struct {
    id: Id = [_]u8{0} ** ID_CAP,
    who: Span = .{},
    text: Span = .{},
    choices: [MAX_CHOICES]Choice = undefined,
    nchoices: u8 = 0,
    thenRef: Span = .{},
    next: u16 = NO_NODE,
    act0: u16 = 0,
    nact: u8 = 0,

    pub fn choiceSlice(self: *const Node) []const Choice {
        return self.choices[0..self.nchoices];
    }
};

pub const Dialog = struct {
    id: Id = [_]u8{0} ** ID_CAP,
    node0: u16 = 0,
    nnodes: u16 = 0,

    pub fn label(self: *const Dialog) []const u8 {
        return idText(&self.id);
    }
};

/// APPEND-ONLY, for `FoeKind`'s reason: it is an `enum(u8)` and the editor's own picker indexes it by ordinal. The MAP FILE is safe either way — `parseScript` reads the kind back by TAG (`enumFromName`).
pub const NpcKind = enum(u8) { wanderer, merchant };

pub fn npcName(k: NpcKind) [:0]const u8 {
    return switch (k) {
        .wanderer => "Wanderer",
        .merchant => "Caravaneer",
    };
}

pub const NPC_ROAM_MAX: f32 = 8.0;

pub const Npc = struct {
    kind: NpcKind = .wanderer,
    x: f32 = 0,
    z: f32 = 0,
    yaw: f32 = 0,
    scale: f32 = 1,
    seed: f32 = 0,
    roam: f32 = 0,
    call: Span = .{},
    dlgRef: Span = .{},
    dlg: u16 = NO_DIALOG,
};

pub const SOIL_N: usize = @intCast(gfx.SOIL_N);
pub const SOIL_CELLS: usize = SOIL_N * SOIL_N;

pub const Soil = enum(u8) {
    none,
    dirt,
    turf,
    stone,
    silt,
    ash,
    moss,
    bone,
    cinder,
    spore,
    bloom,

    pub const N = @typeInfo(Soil).@"enum".fields.len;

    /// Bone SCATTERS and burnt ground TEARS — a shard field has no line and a burn has a ragged one.
    pub fn defaultEdge(s: Soil) Edge {
        return switch (s) {
            .stone => .tiled,
            .bone => .speckle,
            .cinder => .frayed,
            .bloom => .blend,
            else => .natural,
        };
    }
};

/// **WHAT THE PAINTED SHEET IS MADE OF.** One per cell, beside the coast shape, so a map may hold a tarn and a
/// lava run at once. `water` is 0, which is what every map written before this comes up as. The behaviour is
/// the water's for all four — the wading, the coast, the gate a `Gait` reads — and only the LOOK, the STATUS it
/// soaks into you and its voice differ.
pub const Liquid = enum(u8) {
    water,
    oil,
    fungal,
    lava,

    pub const N = @typeInfo(Liquid).@"enum".fields.len;

    pub fn label(l: Liquid) [:0]const u8 {
        return switch (l) {
            .water => "water",
            .oil => "oil",
            .fungal => "fungal",
            .lava => "lava",
        };
    }

    pub fn fromTag(s: []const u8) ?Liquid {
        return std.meta.stringToEnum(Liquid, s);
    }
};

/// **HOW A PAINTED PATCH ENDS.** One authored property per CELL, beside its material and its coverage — not a property of the material, since six materials cannot carry eight shapes and the point is to lay a tiled courtyard and a torn scree of the same stone in one world.
pub const Edge = enum(u8) {
    blend,
    natural,
    frayed,
    jagged,
    straight,
    tiled,
    scallop,
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
    // `shaders.zig`'s `soilColor(id)` carries one branch per id from 1 up; a soil added without a colour there comes out as the fallback, which is a new material that draws as moss.
    std.debug.assert(Soil.N == 11);
    // …AND `shaders.zig`'s `edgeShape(e)` BRANCHES ON THESE ORDINALS, 0..7 in this order: an inserted row would silently re-point every stroke in every map at the wrong shape.
    std.debug.assert(Edge.N == 8);
    std.debug.assert(@intFromEnum(Edge.blend) == 0);
    std.debug.assert(@intFromEnum(Edge.natural) == 1);
    std.debug.assert(@intFromEnum(Edge.frayed) == 2);
    std.debug.assert(@intFromEnum(Edge.jagged) == 3);
    std.debug.assert(@intFromEnum(Edge.straight) == 4);
    std.debug.assert(@intFromEnum(Edge.tiled) == 5);
    std.debug.assert(@intFromEnum(Edge.scallop) == 6);
    std.debug.assert(@intFromEnum(Edge.speckle) == 7);
    // …and `shaders.liquidTone` is a flat 3-per-kind array indexed by THIS ordinal.
    std.debug.assert(Liquid.N == gfx.LIQUID_N);
    std.debug.assert(@intFromEnum(Liquid.water) == 0);
    // **AND `props.LIQUID_TONES` IS THAT ARRAY ON THE CPU SIDE, PINNED TAG-FOR-TAG** — `game.LIQUID_VOICE`'s
    // rule, applied to the one liquid table that was held in this order by a comment alone. It lives here and
    // not beside the table because `props` cannot import this file; reordered, four lakes silently repaint.
    const art = @import("../props/propart.zig");
    for (0..Liquid.N) |i| {
        const tag = upperTag(@tagName(@as(Liquid, @enumFromInt(i))));
        for ([3][]const u8{ "_SHALLOW", "_MID", "_DEEP" }, 0..) |depth, k| {
            const want = mathx.colVec(@field(art, tag ++ depth));
            const got = props.LIQUID_TONES[i * 3 + k];
            std.debug.assert(got.x == want.x and got.y == want.y and got.z == want.z);
        }
    }
}

/// A tag in the SHOUTING spelling `propart` names its colours in — the only reason this exists is so a table
/// can be pinned to an enum by NAME rather than by counting rows.
fn upperTag(comptime s: []const u8) []const u8 {
    comptime {
        var out: [s.len]u8 = undefined;
        for (s, 0..) |c, i| out[i] = std.ascii.toUpper(c);
        const frozen = out;
        return &frozen;
    }
}

/// **IS EVERY CELL'S EDGE THE ONE ITS MATERIAL WOULD HAVE CHOSEN** — what decides whether the grid is worth a row in the file, and the exact inverse of `fillLegacyEdges`. As a `!= .natural` test every map with stone in it grew a row.
fn edgesAllDefault(m: *const Map) bool {
    for (m.soil, m.soilEdge) |id, e| {
        const want: u8 = @intFromEnum(@as(Soil, @enumFromInt(@min(id, Soil.N - 1))).defaultEdge());
        if (e != want) return false;
    }
    return true;
}

fn fillLegacyEdges(m: *Map) void {
    for (m.soil, 0..) |id, i| {
        m.soilEdge[i] = @intFromEnum(@as(Soil, @enumFromInt(@min(id, Soil.N - 1))).defaultEdge());
    }
}

pub const COV_FULL: u8 = 255;

pub fn covF(v: u8) f32 {
    return @as(f32, @floatFromInt(v)) / 255.0;
}

/// `mathx.clampF` and not `std.math.clamp`: that one PROPAGATES a NaN, and a NaN reaching `@intFromFloat` on a `u8` is illegal behaviour rather than a bad byte.
pub fn covByte(v: f32) u8 {
    return @intFromFloat(mathx.clampF(v, 0, 1) * 255.0 + 0.5);
}

const BRUSH_CORE: f32 = 0.55;

fn brushFalloff(d: f32, radius: f32) f32 {
    if (radius <= 0) return 1;
    const core = radius * BRUSH_CORE;
    if (d <= core) return 1;
    const u = mathx.clampF((radius - d) / (radius - core), 0, 1);
    return u * u * (3.0 - 2.0 * u);
}

/// THE ONE PAINTED-GRID SAMPLER — world position → cell index over an `n`-a-side grid spanning `-half..+half`, or null outside it. The soil grid, the water mask and `env`'s water field all read it, so where the clamp happens relative to the cast cannot be written two ways.
pub fn gridIndex(half: f32, n: usize, px: f32, pz: f32) ?usize {
    if (half <= 0) return null;
    const t = (px + half) / (2 * half);
    const u = (pz + half) / (2 * half);
    if (!(t >= 0 and t < 1) or !(u >= 0 and u < 1)) return null;
    const nf: f32 = @floatFromInt(n);
    const cx = @min(@as(usize, @intFromFloat(t * nf)), n - 1);
    const cz = @min(@as(usize, @intFromFloat(u * nf)), n - 1);
    return cz * n + cx;
}

/// `gridIndex`'s INVERSE — the world coordinate of cell `i`'s centre on one axis. Every brush walk and every
/// scan over a painted grid needs it, and written out at the call site it was the same line in three files.
pub fn cellCentre(half: f32, cell: f32, i: usize) f32 {
    return -half + (@as(f32, @floatFromInt(i)) + 0.5) * cell;
}

/// World coordinate → cell index on ONE axis, CLAMPED into the grid rather than refused. `gridIndex` is the
/// point sampler and answers null off the end; a scan bounding a box by a radius wants the rim cell instead.
pub fn cellAxis(half: f32, n: usize, w: f32) usize {
    if (n == 0 or !(half > 0)) return 0;
    const cell = 2 * half / @as(f32, @floatFromInt(n));
    const hi: f32 = @floatFromInt(n - 1);
    return @min(@as(usize, @intFromFloat(mathx.clampF((w + half) / cell, 0, hi))), n - 1);
}

pub const WATER_N: usize = @intCast(gfx.WATER_N);
pub const WATER_CELLS: usize = WATER_N * WATER_N;

pub const HEIGHT_N: usize = @intCast(gfx.HEIGHT_N);
pub const HEIGHT_CELLS: usize = HEIGHT_N * HEIGHT_N;
pub const HEIGHT_STEP: f32 = 0.25;
pub const HEIGHT_ZERO: u8 = 64;
/// How far the encoding reaches: 16 m down (deep enough for any basin) and ~48 m up.
pub const HEIGHT_MIN: f32 = -@as(f32, @floatFromInt(HEIGHT_ZERO)) * HEIGHT_STEP;
pub const HEIGHT_MAX: f32 = @as(f32, @floatFromInt(255 - HEIGHT_ZERO)) * HEIGHT_STEP;

pub fn heightOf(b: u8) f32 {
    return (@as(f32, @floatFromInt(b)) - @as(f32, @floatFromInt(HEIGHT_ZERO))) * HEIGHT_STEP;
}
pub fn heightByte(m: f32) u8 {
    const q = @round(m / HEIGHT_STEP) + @as(f32, @floatFromInt(HEIGHT_ZERO));
    return @intFromFloat(mathx.clampF(q, 0, 255));
}

pub fn sampleHeight(field: []const u8, half: f32, px: f32, pz: f32) f32 {
    std.debug.assert(field.len == HEIGHT_CELLS);
    const last: f32 = @floatFromInt(HEIGHT_N - 1);
    const step = 2 * half / last;
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
    raise,
    lower,
    smooth,
    flatten,
};


pub const Map = struct {
    name: [NAME_CAP]u8 = [_]u8{0} ** NAME_CAP,
    half: f32 = DEFAULT_HALF,
    runway: Runway = .{},
    start: Start = .{},

    ops: [MAX_OPS]Op = undefined,
    nops: usize = 0,
    locations: [MAX_LOCATIONS]Location = undefined,
    nlocations: usize = 0,
    zones: [MAX_ZONES]Zone = undefined,
    nzones: usize = 0,
    clearings: [MAX_CLEARINGS]Clearing = undefined,
    nclearings: usize = 0,
    arenas: [MAX_ARENAS]Arena = undefined,
    narenas: usize = 0,
    foes: [MAX_FOES]Foe = undefined,
    nfoes: usize = 0,
    npcs: [MAX_NPCS]Npc = undefined,
    nnpcs: usize = 0,
    trigs: [MAX_TRIGGERS]Trigger = undefined,
    ntrigs: usize = 0,
    dialogs: [MAX_DIALOGS]Dialog = undefined,
    ndialogs: usize = 0,
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
    dtext: [DTEXT_CAP]u8 = undefined,
    ndtext: u32 = 0,
    soil: [SOIL_CELLS]u8 = [_]u8{0} ** SOIL_CELLS,
    soilCov: [SOIL_CELLS]u8 = [_]u8{COV_FULL} ** SOIL_CELLS,
    soilEdge: [SOIL_CELLS]u8 = [_]u8{@intFromEnum(Edge.natural)} ** SOIL_CELLS,
    water: [WATER_CELLS]u8 = [_]u8{0} ** WATER_CELLS,
    /// …AND HOW ITS COAST RUNS, one `Edge` per cell, painted with the water brush as the soil's is. Baked into the field by `env.uploadWater` and never read at draw time.
    waterEdge: [WATER_CELLS]u8 = [_]u8{@intFromEnum(Edge.natural)} ** WATER_CELLS,
    /// …AND WHAT IT IS, one `Liquid` per cell. Dilated one cell off the paint at upload like the coast is
    /// (`env.dilateWaterEdge`), so the dry side of a bank answers with the pool's own kind.
    waterKind: [WATER_CELLS]u8 = [_]u8{@intFromEnum(Liquid.water)} ** WATER_CELLS,
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
        self.narenas = 0;
        self.nfoes = 0;
        self.clearScript();
        self.soil = [_]u8{0} ** SOIL_CELLS;
        self.soilCov = [_]u8{COV_FULL} ** SOIL_CELLS;
        self.soilEdge = [_]u8{@intFromEnum(Edge.natural)} ** SOIL_CELLS;
        self.water = [_]u8{0} ** WATER_CELLS;
        self.waterEdge = [_]u8{@intFromEnum(Edge.natural)} ** WATER_CELLS;
        self.waterKind = [_]u8{@intFromEnum(Liquid.water)} ** WATER_CELLS;
        // To the DATUM, not to zero: `@memset(.., 0)` here would drop the ground to HEIGHT_MIN.
        self.height = [_]u8{HEIGHT_ZERO} ** HEIGHT_CELLS;
    }

    pub fn blank(self: *Map, name: []const u8) void {
        self.* = .{};
        self.setName(name);
        var z = Zone{ .x = -4000, .z = -4000, .x1 = 4000, .z1 = 4000, .density = 0.7 };
        setMix(&z.mix, &z.nmix, &.{ .grasstall, .grasstall, .patch, .tuft, .clover, .moss, .wildflowers });
        z.setName("plain");
        self.zones[0] = z;
        self.nzones = 1;

        // **NO GROUND COVER.** A blank map used to open with a global `cover:` op, and it grew thirteen thousand plants nobody could select or delete. Cover is ordinary `at:` decor now.
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

    /// Widen the one op at `i` into `n` slots, its neighbours keeping their order — how a generator op is
    /// replaced by the props it made. `n == 0` deletes it. The slots come back UNWRITTEN.
    pub fn splice(self: *Map, i: usize, n: usize) !void {
        if (i >= self.nops) return error.NoSuchOp;
        if (n == 0) return self.remove(i);
        const grow = n - 1;
        if (grow == 0) return;
        if (self.nops + grow > MAX_OPS) return error.TooManyOps;
        std.mem.copyBackwards(Op, self.ops[i + n .. self.nops + grow], self.ops[i + 1 .. self.nops]);
        self.nops += grow;
    }

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

    pub fn spanText(self: *const Map, s: Span) []const u8 {
        if (s.len == 0 or s.at + s.len > self.ndtext) return "";
        return self.dtext[s.at .. s.at + s.len];
    }

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
    pub fn dactRun(self: *const Map, at: u16, n: u8) []const Act {
        if (at + n > self.ndacts) return &.{};
        return self.dacts[at .. at + n];
    }

    pub fn internFlag(self: *Map, name: []const u8) !u16 {
        return intern(&self.flagNames, &self.nflags, name, ParseError.TooManyFlags);
    }
    pub fn internCounter(self: *Map, name: []const u8) !u16 {
        return intern(&self.counterNames, &self.ncounters, name, ParseError.TooManyCounters);
    }
    pub fn internTimer(self: *Map, name: []const u8) !u16 {
        return intern(&self.timerNames, &self.ntimers, name, ParseError.TooManyTimers);
    }

    pub fn findFlag(self: *const Map, name: []const u8) ?u16 {
        return found(self.flagNames[0..self.nflags], name);
    }
    pub fn findCounter(self: *const Map, name: []const u8) ?u16 {
        return found(self.counterNames[0..self.ncounters], name);
    }
    pub fn findTimer(self: *const Map, name: []const u8) ?u16 {
        return found(self.timerNames[0..self.ntimers], name);
    }

    pub fn isFallbackZone(self: *const Map, i: usize) bool {
        return self.nzones > 0 and i + 1 == self.nzones;
    }

    /// FIRST MATCH, which is the most recently painted (the editor prepends). Null outside them all — unlike `zoneAt`, a location has no last-resort fallback: being nowhere in particular is a real answer.
    pub fn locationAt(self: *const Map, px: f32, pz: f32) ?*const Location {
        for (self.locations[0..self.nlocations]) |*l| {
            if (l.contains(px, pz)) return l;
        }
        return null;
    }

    /// …and the first one that actually has an opinion about the sky. A weatherless location standing over a rainy one may not silence it — it is a name for a place, not a hole in the storm.
    pub fn weatherAt(self: *const Map, px: f32, pz: f32) ?*const Location {
        for (self.locations[0..self.nlocations]) |*l| {
            if (l.hasWeather() and l.contains(px, pz)) return l;
        }
        return null;
    }

    /// FIRST MATCH, like a location — rooms are not expected to overlap, and if two do the one painted last
    /// is the one that answers. **THE INDEX AND NOT THE POINTER** is the primitive, because whether a room is
    /// SHUT is per-frame state `game` holds beside the map and looks up by the same number.
    pub fn arenaIndexAt(self: *const Map, px: f32, pz: f32) ?usize {
        for (self.arenas[0..self.narenas], 0..) |*a, i| {
            if (a.contains(px, pz)) return i;
        }
        return null;
    }

    pub fn arenaAt(self: *const Map, px: f32, pz: f32) ?*const Arena {
        return &self.arenas[self.arenaIndexAt(px, pz) orelse return null];
    }

    pub fn findLocation(self: *const Map, name: []const u8) ?u16 {
        for (self.locations[0..self.nlocations], 0..) |*l, i| {
            if (std.mem.eql(u8, l.label(), name)) return @intCast(i);
        }
        return null;
    }

    pub fn zoneAt(self: *const Map, px: f32, pz: f32) ?*const Zone {
        if (self.nzones == 0) return null;
        for (self.zones[0..self.nzones]) |*z| {
            if (z.contains(px, pz)) return z;
        }
        return &self.zones[self.nzones - 1];
    }

    pub fn onRunway(self: *const Map, px: f32, pz: f32) bool {
        const r = self.runway;
        return inRect(px, pz, r.x, r.z, r.x1, r.z1);
    }

    pub fn cellSize(self: *const Map, n: usize) f32 {
        return 2 * self.half / @as(f32, @floatFromInt(n));
    }

    pub fn soilIndex(self: *const Map, px: f32, pz: f32) ?usize {
        return gridIndex(self.half, SOIL_N, px, pz);
    }

    pub fn paintSoil(self: *Map, px: f32, pz: f32, radius: f32, id: Soil, opacity: f32, edge: ?Edge) bool {
        const ev: u8 = @intFromEnum(edge orelse id.defaultEdge());
        const cell = self.cellSize(SOIL_N);
        const r2 = radius * radius;
        const want = mathx.clampF(opacity, 0, 1);
        var changed = false;
        var cz: usize = 0;
        while (cz < SOIL_N) : (cz += 1) {
            const wz = cellCentre(self.half, cell, cz);
            if (@abs(wz - pz) > radius + cell) continue;
            var cx: usize = 0;
            while (cx < SOIL_N) : (cx += 1) {
                const wx = cellCentre(self.half, cell, cx);
                if (@abs(wx - px) > radius + cell) continue;
                const dx = wx - px;
                const dz = wz - pz;
                const d2 = dx * dx + dz * dz;
                if (d2 > r2) continue;
                const i = cz * SOIL_N + cx;
                const v: u8 = @intFromEnum(id);
                if (id == .none) {
                    if (self.soil[i] != 0 or self.soilCov[i] != COV_FULL) {
                        self.soil[i] = 0;
                        self.soilCov[i] = COV_FULL;
                        self.soilEdge[i] = @intFromEnum(Edge.natural);
                        changed = true;
                    }
                    continue;
                }
                const t = brushFalloff(@sqrt(d2), radius);
                const here: f32 = if (self.soil[i] == v) covF(self.soilCov[i]) else 0;
                const next = here + (want - here) * t;
                const nv = covByte(next);
                if (self.soil[i] != v and self.soil[i] != 0 and nv < self.soilCov[i]) continue;
                if (self.soil[i] != v or self.soilCov[i] != nv or self.soilEdge[i] != ev) {
                    self.soil[i] = v;
                    self.soilCov[i] = nv;
                    self.soilEdge[i] = ev;
                    changed = true;
                }
            }
        }
        return changed;
    }

    pub fn paintWater(self: *Map, px: f32, pz: f32, radius: f32, wet: bool, edge: ?Edge, kind: ?Liquid) bool {
        const cell = self.cellSize(WATER_N);
        const r2 = radius * radius;
        const v: u8 = if (wet) 1 else 0;
        const ev: ?u8 = if (edge) |e| @intFromEnum(e) else null;
        const kv: ?u8 = if (kind) |k| @intFromEnum(k) else null;
        var changed = false;
        var cz: usize = 0;
        while (cz < WATER_N) : (cz += 1) {
            const wz = cellCentre(self.half, cell, cz);
            if (@abs(wz - pz) > radius + cell) continue;
            var cx: usize = 0;
            while (cx < WATER_N) : (cx += 1) {
                const wx = cellCentre(self.half, cell, cx);
                if (@abs(wx - px) > radius + cell) continue;
                const dx = wx - px;
                const dz = wz - pz;
                if (dx * dx + dz * dz > r2) continue;
                const i = cz * WATER_N + cx;
                if (self.water[i] != v) {
                    self.water[i] = v;
                    changed = true;
                }
                if (ev) |want| {
                    if (self.waterEdge[i] != want) {
                        self.waterEdge[i] = want;
                        changed = true;
                    }
                }
                if (kv) |want| {
                    if (self.waterKind[i] != want) {
                        self.waterKind[i] = want;
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
        var before: [HEIGHT_N]f32 = undefined;
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
                const fall = mathx.smoothstep(r, r * 0.15, d);
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
    try setId(&table[n.*], name);
    n.* += 1;
    return @intCast(n.* - 1);
}


pub fn write(m: *const Map, w: anytype) !void {
    try w.print("version: {d}\n", .{VERSION});
    try w.print("name: {s}\n", .{m.label()});
    try w.print("half: {d:.1}\n", .{m.half});
    try w.print("runway: {d:.2} {d:.2} {d:.2} {d:.2}\n", .{ m.runway.x, m.runway.z, m.runway.x1, m.runway.z1 });
    try w.print("start: {d:.2} {d:.2} {d:.1}\n", .{ m.start.x, m.start.z, m.start.yaw });
    try w.writeAll("\n");

    for (m.zones[0..m.nzones]) |*z| {
        try w.print("zone: {s} {d:.1} {d:.1} {d:.1} {d:.1} {d:.3} ", .{ z.label(), z.x, z.z, z.x1, z.z1, z.density });
        try writeMix(w, z.mix[0..z.nmix]);
        try w.writeAll("\n");
    }
    for (m.locations[0..m.nlocations]) |*l| {
        try w.print("location: {s} {d:.1} {d:.1} {d:.1} {d:.1}", .{ l.label(), l.x, l.z, l.x1, l.z1 });
        if (l.wet) |v| try w.print(" wet={d:.3}", .{v});
        if (l.fog) |v| try w.print(" fog={d:.3}", .{v});
        if (l.spore) |v| try w.print(" spore={d:.3}", .{v});
        if (l.blend != 6.0) try w.print(" blend={d:.2}", .{l.blend});
        try w.writeAll("\n");
    }
    for (m.clearings[0..m.nclearings]) |c| {
        try w.print("clear: {d:.1} {d:.1} {d:.1}\n", .{ c.x, c.z, c.r });
    }
    for (m.arenas[0..m.narenas]) |*a| {
        try w.print("arena: {s}", .{a.label()});
        // ALWAYS, and not on a difference the way `writeOp` writes the gate's: a room whose line reads as
        // bounds alone is a room that silently holds nothing, and there is no stamped default here.
        try writeSeal(w, a.seal());
        for (0..a.verts()) |i| try w.print(" {d:.2} {d:.2}", .{ a.vx[i], a.vz[i] });
        try w.writeAll("\n");
    }
    if (m.nzones + m.nclearings + m.nlocations + m.narenas > 0) try w.writeAll("\n");

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
        for (m.soilCov) |c| {
            if (c != COV_FULL) {
                try writeGrid(w, "soilcov", &m.soilCov);
                break;
            }
        }
        if (!edgesAllDefault(m)) try writeGrid(w, "soiledge", &m.soilEdge);
    }
    if (m.anyWater()) {
        try w.writeAll("\n");
        try writeGrid(w, "water", &m.water);
        for (m.waterEdge) |e| {
            if (e != @intFromEnum(Edge.natural)) {
                try writeGrid(w, "wateredge", &m.waterEdge);
                break;
            }
        }
        // …and the same rule for the kind: a map that is all water writes no row and comes back byte for byte.
        for (m.waterKind) |k| {
            if (k != @intFromEnum(Liquid.water)) {
                try writeGrid(w, "liquid", &m.waterKind);
                break;
            }
        }
    }
    if (m.anyHeight()) {
        try w.writeAll("\n");
        try writeGrid(w, "hgt", &m.height);
    }

    if (m.nfoes > 0) try w.writeAll("\n");
    for (m.foes[0..m.nfoes]) |f| {
        // **THE TAIL IS WRITTEN ONLY WHEN IT SAYS SOMETHING.** A unit on the default AI emits exactly the line it
        // always did, so a map authored before any of this round-trips byte for byte.
        try w.print("foe: {s} {d:.2} {d:.2} {d:.1} {d:.2} {d:.2}", .{ @tagName(f.kind), f.x, f.z, f.yaw, f.scale, f.seed });
        if (f.ai != .hold) try w.print(" ai={s}", .{@tagName(f.ai)});
        for (f.route()) |q| try w.print(" wp={d:.2},{d:.2}", .{ q.x, q.z });
        try w.print("\n", .{});
    }

    try writeScript(m, w);
}

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

/// **A SLOT PAST THE END OF ITS TABLE IS `undefined` MEMORY, AND THE WRITER MUST NEVER READ IT.** The tables
/// are sized `MAX_*` and filled to `n*`; a condition on a flag the map never declared pointed at slot 0 of
/// nothing and would have put those bytes in the file. `unset` parses straight back as a declared name, so the
/// round trip stays lossless rather than the row being dropped.
fn slotName(table: []const Id, n: usize, i: u16) []const u8 {
    return if (i < n) idText(&table[i]) else "unset";
}

fn writeCond(m: *const Map, w: anytype, c: *const Cond) !void {
    switch (c.kind) {
        .always, .never => try w.print("{s}\n", .{@tagName(c.kind)}),
        .flag => try w.print("flag {s}={d}\n", .{ slotName(&m.flagNames, m.nflags, c.slot), @as(u8, if (c.on) 1 else 0) }),
        .counter => try w.print("counter {s} {s} {d}\n", .{ slotName(&m.counterNames, m.ncounters, c.slot), c.cmp.tok(), c.n }),
        .timer => try w.print("timer {s}={s}\n", .{ slotName(&m.timerNames, m.ntimers, c.slot), if (c.on) "done" else "running" }),
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
        .flag => try w.print("flag {s}={s}\n", .{ slotName(&m.flagNames, m.nflags, a.slot), switch (a.setop) {
            .off => "0",
            .on => "1",
            .flip => "flip",
        } }),
        .counter => try w.print("counter {s} {s} {d}\n", .{ slotName(&m.counterNames, m.ncounters, a.slot), @tagName(a.countop), a.n }),
        .timer => try w.print("timer {s}={d}\n", .{ slotName(&m.timerNames, m.ntimers, a.slot), a.v }),
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
    if (!sameSeal(o, &d)) try writeSeal(w, o.seal());
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
        .optional => if (v) |x| try writeTail(w, x) else try w.writeAll("-"),
        .@"enum" => try w.print("{s}", .{@tagName(v)}),
        .float => try w.print("{d}", .{v}),
        .int => try w.print("{d}", .{v}),
        .bool => try w.print("{s}", .{if (v) "1" else "0"}),
        .@"struct" => {
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
    TooManyLocations,
    TooManyClearings,
    TooManyArenas,
    ShortArena,
    TooManyFoes,
    TooManyWaypoints,
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
    NoOwner,
    UnknownRef,
    NameTooLong,
};

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
    var soilAt: usize = 0;
    var covAt: usize = 0;
    var edgeAt: usize = 0;
    var waterAt: usize = 0;
    var wEdgeAt: usize = 0;
    var wKindAt: usize = 0;
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
        const rest = trim(line[colon + 1 ..]);
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
        } else if (std.mem.eql(u8, rec, "start")) {
            m.start = .{ .x = try nextFloat(&it), .z = try nextFloat(&it), .yaw = try nextFloat(&it) };
        } else if (std.mem.eql(u8, rec, "zone")) {
            if (m.nzones >= MAX_ZONES) return ParseError.TooManyZones;
            m.zones[m.nzones] = try parseZone(&it);
            m.nzones += 1;
        } else if (std.mem.eql(u8, rec, "location")) {
            if (m.nlocations >= MAX_LOCATIONS) return ParseError.TooManyLocations;
            m.locations[m.nlocations] = try parseLocation(&it);
            m.nlocations += 1;
        } else if (std.mem.eql(u8, rec, "clear")) {
            if (m.nclearings >= MAX_CLEARINGS) return ParseError.TooManyClearings;
            m.clearings[m.nclearings] = .{ .x = try nextFloat(&it), .z = try nextFloat(&it), .r = try nextFloat(&it) };
            m.nclearings += 1;
        } else if (std.mem.eql(u8, rec, "arena")) {
            if (m.narenas >= MAX_ARENAS) return ParseError.TooManyArenas;
            m.arenas[m.narenas] = try parseArena(&it);
            m.narenas += 1;
        } else if (std.mem.eql(u8, rec, "soil")) {
            soilAt = try readGrid(&it, &m.soil, soilAt, Soil.N);
        } else if (std.mem.eql(u8, rec, "soilcov")) {
            covAt = try readGrid(&it, &m.soilCov, covAt, 256);
        } else if (std.mem.eql(u8, rec, "soiledge")) {
            edgeAt = try readGrid(&it, &m.soilEdge, edgeAt, Edge.N);
        } else if (std.mem.eql(u8, rec, "water")) {
            waterAt = try readGrid(&it, &m.water, waterAt, 2);
        } else if (std.mem.eql(u8, rec, "wateredge")) {
            wEdgeAt = try readGrid(&it, &m.waterEdge, wEdgeAt, Edge.N);
        } else if (std.mem.eql(u8, rec, "liquid")) {
            wKindAt = try readGrid(&it, &m.waterKind, wKindAt, Liquid.N);
        } else if (std.mem.eql(u8, rec, "hgt")) {
            hgtAt = try readGrid(&it, &m.height, hgtAt, 256);
        } else if (std.mem.eql(u8, rec, "foe")) {
            if (m.nfoes >= MAX_FOES) return ParseError.TooManyFoes;
            var f = Foe{
                .kind = try enumFromName(FoeKind, it.next() orelse return ParseError.MissingField),
                .x = try nextFloat(&it),
                .z = try nextFloat(&it),
                .yaw = try nextFloat(&it),
                .scale = try band(&it, FOE_SCALE_LO, FOE_SCALE_HI),
                .seed = try band(&it, 0, 1),
            };
            // OPTIONAL AND ORDERLESS. A line written before any of this has none of it and takes the defaults.
            while (it.next()) |tok| {
                const eq = std.mem.indexOfScalar(u8, tok, '=') orelse return ParseError.UnknownKey;
                const key = tok[0..eq];
                const val = tok[eq + 1 ..];
                if (std.mem.eql(u8, key, "ai")) {
                    f.ai = try enumFromName(FoeAi, val);
                } else if (std.mem.eql(u8, key, "wp")) {
                    if (f.nwp >= MAX_WP) return ParseError.TooManyWaypoints;
                    const comma = std.mem.indexOfScalar(u8, val, ',') orelse return ParseError.MissingField;
                    f.wp[f.nwp] = .{
                        .x = try finiteFloat(f32, val[0..comma]),
                        .z = try finiteFloat(f32, val[comma + 1 ..]),
                    };
                    f.nwp += 1;
                } else return ParseError.UnknownKey;
            }
            m.foes[m.nfoes] = f;
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
    if (soilAt != 0 and soilAt != m.soil.len) return ParseError.MissingField;
    if (covAt != 0 and covAt != m.soilCov.len) return ParseError.MissingField;
    if (edgeAt != 0 and edgeAt != m.soilEdge.len) return ParseError.MissingField;
    if (waterAt != 0 and waterAt != m.water.len) return ParseError.MissingField;
    if (wEdgeAt != 0 and wEdgeAt != m.waterEdge.len) return ParseError.MissingField;
    if (wKindAt != 0 and wKindAt != m.waterKind.len) return ParseError.MissingField;
    if (hgtAt != 0 and hgtAt != m.height.len) return ParseError.MissingField;
    if (edgeAt == 0) fillLegacyEdges(m);
    lineOut.* = 0;
    try link(m);
}

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
        try setId(&t.id, it.next() orelse return ParseError.MissingField);
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
        try setId(&d.id, it.next() orelse return ParseError.MissingField);
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
        try setId(&nd.id, it.next() orelse return ParseError.MissingField);
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
    if (std.mem.eql(u8, rec, "act") or std.mem.eql(u8, rec, "gets")) {
        const nd = &m.nodes[cur.node orelse return ParseError.NoOwner];
        if (m.ndacts >= MAX_DACTS) return ParseError.TooManyActs;
        const onNode = std.mem.eql(u8, rec, "act");
        if (onNode and nd.nchoices > 0) return ParseError.NoOwner;
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

fn parseAct(m: *Map, rest: []const u8, it: *Toks) !Act {
    const head = it.next() orelse return ParseError.MissingField;
    var a = Act{ .kind = try enumFromName(ActKind, head) };
    switch (a.kind) {
        .dialog => a.ref = try m.addText(it.next() orelse return ParseError.MissingField),
        .text => {
            const at = std.mem.indexOf(u8, rest, head) orelse return ParseError.MissingField;
            a.line = try m.addText(trim(rest[at + head.len ..]));
            if (a.line.len == 0) return ParseError.MissingField;
            return a;
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

/// One condition's forward references — `talked` names a dialog, `near` indexes the npc table. Every pool a `Cond` can live in goes through here, so a new pool cannot inherit half the resolution.
fn linkCond(m: *Map, c: *Cond) !void {
    if (c.kind == .near and c.slot >= m.nnpcs) return ParseError.UnknownRef;
    if (c.kind != .talked) return;
    c.slot = m.findDialog(m.spanText(c.ref)) orelse return ParseError.UnknownRef;
}

fn nodeIn(m: *const Map, d: *const Dialog, name: []const u8) !u16 {
    for (m.nodes[d.node0 .. d.node0 + d.nnodes], 0..) |*nd, i| {
        if (std.mem.eql(u8, idText(&nd.id), name)) return @intCast(d.node0 + i);
    }
    return ParseError.UnknownRef;
}

/// `location: <name> <x> <z> <x1> <z1> [wet=..] [fog=..] [spore=..] [blend=..]` — the rectangle is positional and the sky is optional, because most locations will never have anything to do with the weather.
fn parseLocation(it: *std.mem.TokenIterator(u8, .any)) !Location {
    var l = Location{};
    l.setName(it.next() orelse return ParseError.MissingField);
    l.x = try nextFloat(it);
    l.z = try nextFloat(it);
    l.x1 = try nextFloat(it);
    l.z1 = try nextFloat(it);
    while (it.next()) |tok| {
        const eq = std.mem.indexOfScalar(u8, tok, '=') orelse return ParseError.UnknownKey;
        const key = tok[0..eq];
        const val = tok[eq + 1 ..];
        if (std.mem.eql(u8, key, "wet")) {
            l.wet = try band01(val);
        } else if (std.mem.eql(u8, key, "fog")) {
            l.fog = try band01(val);
        } else if (std.mem.eql(u8, key, "spore")) {
            l.spore = try band01(val);
        } else if (std.mem.eql(u8, key, "blend")) {
            l.blend = try finiteFloat(f32, val);
            if (!(l.blend >= 0 and l.blend <= 120)) return ParseError.BadNumber;
        } else return ParseError.UnknownKey;
    }
    return l;
}

fn band01(tok: []const u8) !f32 {
    const v = try finiteFloat(f32, tok);
    if (!(v >= 0 and v <= 1)) return ParseError.BadNumber;
    return v;
}

test "LOCATIONS OVERLAP AND THE LAST PAINTED WINS, and a weatherless one does not silence a wet one" {
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    m.* = .{};
    // The editor PREPENDS, so index 0 is the newest — `locationAt` takes the first match.
    m.locations[0] = .{ .x = -10, .z = -10, .x1 = 10, .z1 = 10, .wet = 0.9 };
    m.locations[0].setName("inner");
    m.locations[1] = .{ .x = -50, .z = -50, .x1 = 50, .z1 = 50, .wet = 0.2 };
    m.locations[1].setName("outer");
    m.nlocations = 2;

    try std.testing.expectEqualStrings("inner", m.locationAt(0, 0).?.label());
    try std.testing.expectEqualStrings("outer", m.locationAt(30, 30).?.label());
    try std.testing.expect(m.locationAt(80, 80) == null);
    try std.testing.expectApproxEqAbs(@as(f32, 0.9), m.weatherAt(0, 0).?.wet.?, 1e-6);

    // A NAMED PLACE WITH NO SKY OPINION IS STILL A PLACE. Standing over a wet one it must not answer for the weather, or every trigger rectangle you draw punches a dry hole in the storm.
    m.locations[0].wet = null;
    m.locations[0].fog = null;
    try std.testing.expectEqualStrings("inner", m.locationAt(0, 0).?.label());
    try std.testing.expectEqualStrings("outer", m.weatherAt(0, 0).?.label());
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), m.weatherAt(0, 0).?.wet.?, 1e-6);

    try std.testing.expect(m.findLocation("outer").? == 1);
    try std.testing.expect(m.findLocation("nowhere") == null);
}

test "a location round-trips through the format with and without its weather" {
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    var line: usize = 0;
    const text =
        "version: 1\n" ++
        "half: 100\n" ++
        "location: plain -20 -20 20 20\n" ++
        "location: storm 0 0 40 40 wet=0.750 fog=0.300 blend=9.00\n";
    try parse(text, m, &line);
    try std.testing.expectEqual(@as(usize, 2), m.nlocations);
    try std.testing.expect(!m.locations[0].hasWeather());
    try std.testing.expect(m.locations[1].hasWeather());
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), m.locations[1].wet.?, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 9.0), m.locations[1].blend, 1e-4);
    // Out of range is refused rather than clamped: a wet of 4 is a typo, not an intention.
    var bad: usize = 0;
    try std.testing.expectError(ParseError.BadNumber, parse(
        "version: 1\nhalf: 100\nlocation: x 0 0 1 1 wet=4\n",
        m,
        &bad,
    ));
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

/// **THE SEAL COMES BEFORE THE CORNERS AND THE CORNERS ARE THE REST OF THE LINE.** Written the other way round
/// a room with an odd float in it eats its own `boss=` tail; parsed this way a truncated line is a `ShortArena`
/// and never a room silently one corner smaller than it was authored.
fn parseArena(it: *std.mem.TokenIterator(u8, .any)) !Arena {
    var a = Arena{};
    a.setName(it.next() orelse return ParseError.MissingField);
    const tok = it.next() orelse return ParseError.MissingField;
    const eq = std.mem.indexOfScalar(u8, tok, '=') orelse return ParseError.UnknownKey;
    if (!std.mem.eql(u8, tok[0..eq], "boss")) return ParseError.UnknownKey;
    a.nboss = try parseSeal(tok[eq + 1 ..], &a.boss);
    while (it.next()) |xt| {
        if (a.n >= MAX_ARENA_VERTS) return ParseError.ExtraField;
        a.vx[a.n] = try finiteFloat(f32, xt);
        a.vz[a.n] = try nextFloat(it);
        a.n += 1;
    }
    if (a.n < 3) return ParseError.ShortArena;
    return a;
}

fn parseOp(kind: OpKind, it: *std.mem.TokenIterator(u8, .any)) !Op {
    var o = defaults(kind);
    switch (kind) {
        inline else => |k| {
            inline for (comptime fieldsOf(k)) |name| {
                const tok = it.next() orelse return ParseError.MissingField;
                @field(o, name) = try parseVal(@TypeOf(@field(o, name)), tok);
            }
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
                if (std.mem.eql(u8, key, "boss")) {
                    o.nboss = try parseSeal(val, &o.boss);
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

/// `-` is the doorway, and it is the only token that may stand alone: a gate sealed on nothing never shuts.
fn parseSeal(s: []const u8, out: *[MAX_SEAL]FoeKind) !u8 {
    var n: u8 = 0;
    var parts = std.mem.splitScalar(u8, s, ',');
    while (parts.next()) |p| {
        const t = trim(p);
        if (t.len == 0 or std.mem.eql(u8, t, "-")) continue;
        if (n >= MAX_SEAL) return ParseError.ExtraField;
        out[n] = try enumFromName(FoeKind, t);
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
        .optional => |o| if (std.mem.eql(u8, tok, "-")) null else try parseVal(o.child, tok),
        .@"enum" => try enumFromName(T, tok),
        .float => try finiteFloat(T, tok),
        .int => std.fmt.parseInt(T, tok, 10) catch ParseError.BadNumber,
        .bool => blk: {
            if (std.mem.eql(u8, tok, "1") or std.mem.eql(u8, tok, "true")) break :blk true;
            if (std.mem.eql(u8, tok, "0") or std.mem.eql(u8, tok, "false")) break :blk false;
            break :blk ParseError.BadNumber;
        },
        .@"struct" => blk: {
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

var bootMap: []const u8 = START_MAP;

pub fn startMap() []const u8 {
    return bootMap;
}

pub fn setStartMap(path: []const u8) void {
    bootMap = path;
}

/// Bytes an `at:` line spends on the shipped maps, rounded up from a measured 49.7 and pinned by a test.
const OP_LINE_TYPICAL: usize = 64;
/// Worst-case bytes an RLE grid cell spends: `" 255x1"` plus a share of the per-16-run label.
const GRID_CELL_CAP: usize = 7;

/// **THE READ BUFFER IS DERIVED FROM THE CAPS, NOT PICKED.** At `MAX_OPS` the ops alone outgrew the 1 MB it
/// used to be, so a map filling every cap was one `load` could only answer `MapTooLarge` to. An op carrying a
/// full `mix=` or `loot=` still runs far past `OP_LINE_TYPICAL` — `save` measures and refuses for that.
pub const TEXT_CAP: usize =
    256 + NAME_CAP + 48 +
    MAX_ZONES * (NAME_CAP + 64 + MAX_MIX * (longestTag(Kind) + 1)) +
    MAX_LOCATIONS * (NAME_CAP + 128) +
    MAX_CLEARINGS * 48 +
    MAX_ARENAS * (NAME_CAP + 16 + MAX_SEAL * (longestTag(FoeKind) + 1) + MAX_ARENA_VERTS * 22) +
    MAX_OPS * OP_LINE_TYPICAL +
    (3 * SOIL_CELLS + 3 * WATER_CELLS + HEIGHT_CELLS) * GRID_CELL_CAP +
    MAX_FOES * (longestTag(FoeKind) + 48) +
    (MAX_FLAGS + MAX_COUNTERS + MAX_TIMERS) * (ID_CAP + 2) + 64 +
    MAX_NPCS * (ID_CAP + NAME_CAP + 128) +
    MAX_TRIGGERS * (ID_CAP + 64 + (MAX_CONDS + MAX_ACTS) * (ID_CAP + 48)) +
    MAX_DIALOGS * (ID_CAP + 16) +
    MAX_NODES * (ID_CAP + 32 + MAX_CHOICES * (ID_CAP + 32)) +
    DTEXT_CAP;

fn longestTag(comptime T: type) usize {
    var n: usize = 0;
    for (@typeInfo(T).@"enum".fields) |f| n = @max(n, f.name.len);
    return n;
}

var textBuf: [TEXT_CAP]u8 = undefined;

var loadScratch: Map = undefined;

pub fn load(path: []const u8, m: *Map, lineOut: *usize) !void {
    var f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    const n = try f.readAll(&textBuf);
    if (n == textBuf.len) return error.MapTooLarge;
    try parse(textBuf[0..n], &loadScratch, lineOut);
    m.* = loadScratch;
}

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
    const stem = n;
    var lastUnderscore = true;
    for (name) |c| {
        if (n + EXT.len >= dst.len) break;
        const ok = std.ascii.isAlphanumeric(c);
        if (!ok and lastUnderscore) continue;
        dst[n] = if (ok) std.ascii.toLower(c) else '_';
        lastUnderscore = !ok;
        n += 1;
    }
    if (n > stem and dst[n - 1] == '_') n -= 1;
    if (n == stem) {
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

/// **A MAP IS RENDERED BESIDE ITS FILE AND ONLY THEN PUT IN ITS PLACE.** `createFile` truncates first, so a
/// failed save in place — full disk, or a map past `TEXT_CAP` — destroyed the last good copy. The size is
/// checked here because this is the last moment the old file still exists.
pub fn save(path: []const u8, m: *const Map) !void {
    try std.fs.cwd().makePath(DIR);
    var tmpBuf: [PATH_CAP + 8]u8 = undefined;
    const tmp = try std.fmt.bufPrint(&tmpBuf, "{s}.tmp", .{path});
    errdefer std.fs.cwd().deleteFile(tmp) catch {};
    {
        var f = try std.fs.cwd().createFile(tmp, .{});
        defer f.close();
        var buf = std.io.bufferedWriter(f.writer());
        try write(m, buf.writer());
        try buf.flush();
        if (try f.getEndPos() >= TEXT_CAP) return error.MapTooLarge;
    }
    try std.fs.cwd().rename(tmp, path);
}


fn isPositional(comptime k: OpKind, comptime name: []const u8) bool {
    // The field walk is O(op kinds x Op fields x name length) string compares at comptime, and the default 1000-branch budget is spent well before it finishes.
    @setEvalBranchQuota(20000);
    for (fieldsOf(k)) |f| {
        if (std.mem.eql(u8, f, name)) return true;
    }
    return false;
}

fn canTail(comptime k: OpKind, comptime name: []const u8) bool {
    @setEvalBranchQuota(20000);
    // The array-plus-count pairs are written by hand as their own `key=` tail (see writeOp), so the generic field walk must not also try to emit them — an `[8]item.Kind` has no `writeTail` form.
    const never = [_][]const u8{ "op", "mix", "nmix", "loot", "nloot", "boss", "nboss" };
    for (never) |n| {
        if (std.mem.eql(u8, n, name)) return false;
    }
    return !isPositional(k, name);
}

/// A tail is written only when it says something (`writeOp`), and the seal is compared over its LIVE entries — the slots past `nboss` are stale picks nobody reads.
fn sameSeal(a: *const Op, b: *const Op) bool {
    return a.nboss == b.nboss and std.mem.eql(FoeKind, a.seal(), b.seal());
}

fn eqlVal(a: anytype, b: @TypeOf(a)) bool {
    return switch (@typeInfo(@TypeOf(a))) {
        .@"struct", .optional => std.meta.eql(a, b),
        else => a == b,
    };
}

fn enumFromName(comptime T: type, s: []const u8) !T {
    return std.meta.stringToEnum(T, s) orelse ParseError.BadKind;
}

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


pub const TEST_HEAD =
    \\version: 1
    \\zone: plain -4000 -4000 4000 4000 0.7 grasstall
    \\
;
const SCRIPT_HEAD = TEST_HEAD;

/// …and the parse behind it, reporting the LINE a failure landed on. The caller owns the `Map` (it is far too big for a stack frame) and destroys it.
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
    try std.testing.expectEqual(@as(usize, 4), m.nflags);
    try std.testing.expectEqual(@as(usize, 1), m.ncounters);
    try std.testing.expectEqual(@as(usize, 1), m.ntimers);
}

test "a name is resolved wherever it was written, above or below its use" {
    const alloc = std.testing.allocator;
    const m = try alloc.create(Map);
    defer alloc.destroy(m);
    var ln: usize = 0;
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

test "AN ID TOO LONG TO STORE IS REFUSED, not quietly clipped into a second flag" {
    const long = "a" ** (ID_CAP + 2);
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    var ln: usize = 0;
    try std.testing.expectError(ParseError.NameTooLong, parse(TEST_HEAD ++ "flags: " ++ long ++ "\n", m, &ln));

    // The longest that still fits round-trips, and interning it twice is one row — which is the whole point:
    // the `do:` that sets a flag and the `need:` that reads it have to land on the same one.
    const fits = "b" ** (ID_CAP - 1);
    try parse(TEST_HEAD ++ "flags: " ++ fits ++ "\n", m, &ln);
    try std.testing.expectEqual(@as(usize, 1), m.nflags);
    try std.testing.expectEqual(@as(?u16, 0), m.findFlag(fits));
    try std.testing.expectEqual(@as(u16, 0), try m.internFlag(fits));
    try std.testing.expectEqual(@as(usize, 1), m.nflags);
}

test "A MAP THAT FILLS EVERY CAP IS STILL A MAP THAT LOADS" {
    var n = std.io.countingWriter(std.io.null_writer);
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    m.* = .{};
    m.blank("Full");
    var o = defaults(.at);
    o.kind = .pillar;
    while (m.nops < MAX_OPS) _ = try m.add(o);
    // The grids resist: RLE'd, a painted map is a few tens of KB. It is the OPS that carry a file.
    for (&m.soil, 0..) |*c, i| c.* = @intCast(i % 4);
    for (&m.height, 0..) |*c, i| c.* = @intCast(HEIGHT_ZERO -% @as(u8, @intCast(i % 3)));
    for (&m.water, 0..) |*c, i| c.* = @intCast(i % 2);
    // …and the two grids that ride the water, at the same churn: every cell its own run, which is the worst
    // case the buffer is sized for and the only way `TEXT_CAP` is honestly tested.
    for (&m.waterEdge, 0..) |*c, i| c.* = @intCast(i % Edge.N);
    for (&m.waterKind, 0..) |*c, i| c.* = @intCast(i % Liquid.N);
    try write(m, n.writer());
    std.debug.print("\n  a map at every cap writes {d} bytes into a {d} B buffer ({d:.0}% used)\n", .{
        n.bytes_written, TEXT_CAP, 100.0 * @as(f64, @floatFromInt(n.bytes_written)) / @as(f64, @floatFromInt(TEXT_CAP)),
    });
    try std.testing.expect(n.bytes_written < TEXT_CAP);
}

test "THE SHIPPED MAPS SIT INSIDE THE READ BUFFER, and `save` refuses to write one that would not" {
    var dir = std.fs.cwd().openDir(DIR, .{ .iterate = true }) catch return error.SkipZigTest;
    defer dir.close();
    var it = dir.iterate();
    var worst: u64 = 0;
    var worstName: [PATH_CAP]u8 = [_]u8{0} ** PATH_CAP;
    while (try it.next()) |ent| {
        if (ent.kind != .file or !std.mem.endsWith(u8, ent.name, EXT)) continue;
        const st = try dir.statFile(ent.name);
        if (st.size <= worst) continue;
        worst = st.size;
        @memcpy(worstName[0..@min(ent.name.len, PATH_CAP)], ent.name[0..@min(ent.name.len, PATH_CAP)]);
    }
    std.debug.print("  biggest shipped map {s} {d} B, {d:.0}% of the buffer\n", .{
        std.mem.sliceTo(&worstName, 0), worst, 100.0 * @as(f64, @floatFromInt(worst)) / @as(f64, @floatFromInt(TEXT_CAP)),
    });
    try std.testing.expect(worst * 2 < TEXT_CAP);

    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    m.* = .{};
    m.blank("Saved");
    var at = defaults(.at);
    at.kind = .pillar;
    at.x = 12.5;
    _ = try m.add(at);

    const kept = DIR ++ "/test_saveroundtrip" ++ EXT;
    defer std.fs.cwd().deleteFile(kept) catch {};
    try save(kept, m);
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access(kept ++ ".tmp", .{}));
    const back = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(back);
    var line: usize = 0;
    try load(kept, back, &line);
    try std.testing.expectEqual(m.nops, back.nops);
    try std.testing.expectEqual(at.x, back.ops[0].x);

    // A map past the buffer is REFUSED, and the file it would have replaced is left exactly as it was.
    var o = defaults(.at);
    o.kind = .pillar;
    o.nmix = MAX_MIX;
    for (&o.mix) |*k| k.* = .trestletable;
    o.nloot = MAX_LOOT;
    while (m.nops < MAX_OPS) _ = try m.add(o);
    try std.testing.expectError(error.MapTooLarge, save(kept, m));
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access(kept ++ ".tmp", .{}));
    try load(kept, back, &line);
    try std.testing.expectEqual(@as(usize, 1), back.nops);
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

    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try write(&m, fbs.writer());

    var back = Map{};
    var ln: usize = 0;
    try parse(fbs.getWritten(), &back, &ln);
    try std.testing.expectEqual(@as(usize, 1), back.nops);
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

test "A FOG GATE'S BOSS ROUND-TRIPS, and the default costs the file nothing" {
    var m = Map{};
    m.setName("Seals");
    var plain = defaults(.at);
    plain.kind = .foggate;
    _ = try m.add(plain);
    var named = defaults(.at);
    named.kind = .foggate;
    named.boss[0] = .ogre;
    _ = try m.add(named);
    var never = defaults(.at);
    never.kind = .foggate;
    never.nboss = 0;
    _ = try m.add(never);
    // A DUO IS TWO NAMES ON ONE GATE, which is the whole reason the seal is a list.
    var pair = defaults(.at);
    pair.kind = .foggate;
    pair.boss[0] = .fungal_swordsman;
    pair.boss[1] = .fungal_magus;
    pair.nboss = 2;
    _ = try m.add(pair);

    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try write(&m, fbs.writer());
    const text = fbs.getWritten();
    // The default is the only boss in the game, so an untouched gate writes no tail at all.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, text, "boss=bone_knight"));
    try std.testing.expect(std.mem.indexOf(u8, text, "boss=ogre") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "boss=-") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "boss=fungal_swordsman,fungal_magus") != null);

    var back = Map{};
    var ln: usize = 0;
    try parse(text, &back, &ln);
    try std.testing.expectEqual(@as(usize, 4), back.nops);
    try std.testing.expect(back.ops[0].sealsOn(.bone_knight));
    try std.testing.expect(back.ops[1].sealsOn(.ogre) and !back.ops[1].sealsOn(.bone_knight));
    try std.testing.expectEqual(@as(usize, 0), back.ops[2].seal().len);
    try std.testing.expect(back.ops[3].sealsOn(.fungal_swordsman) and back.ops[3].sealsOn(.fungal_magus));
    try std.testing.expectEqual(@as(usize, 2), back.ops[3].seal().len);
}

test "A MAP OLDER THAN THE EDGE GRID COMES UP LOOKING THE SAME" {
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
    try std.testing.expectEqual(m.soil[a], m.soil[b]);
    try std.testing.expectEqual(Edge.tiled, @as(Edge, @enumFromInt(m.soilEdge[a])));
    try std.testing.expectEqual(Edge.jagged, @as(Edge, @enumFromInt(m.soilEdge[b])));

    _ = m.paintSoil(-60, 0, 15, .stone, 1, .scallop);
    try std.testing.expectEqual(Edge.scallop, @as(Edge, @enumFromInt(m.soilEdge[a])));

    _ = m.paintSoil(-60, 0, 15, .none, 1, null);
    try std.testing.expectEqual(Edge.natural, @as(Edge, @enumFromInt(m.soilEdge[a])));
}

test "the soil grid and foe records survive a round trip" {
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    const back = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(back);
    m.blank("Round Trip");
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

test "THE LIQUID GRID ROUND-TRIPS, and a map of plain water writes no `liquid:` row at all" {
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    const back = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(back);
    var buf: [1 << 20]u8 = undefined;

    m.blank("Tarn");
    try std.testing.expect(m.paintWater(0, 0, 40, true, .speckle, .water));
    {
        var fbs = std.io.fixedBufferStream(&buf);
        try write(m, fbs.writer());
        // WATER IS ORDINAL 0, so a map that predates the liquids costs the file nothing and comes back the same.
        try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "liquid:") == null);
        var line: usize = 0;
        try parse(fbs.getWritten(), back, &line);
        try std.testing.expectEqual(Liquid.water, @as(Liquid, @enumFromInt(back.waterKind[gridIndex(back.half, WATER_N, 0, 0).?])));
    }

    m.blank("Four Pools");
    inline for (.{ .{ -60.0, -60.0, Liquid.water }, .{ 60.0, -60.0, Liquid.oil }, .{ -60.0, 60.0, Liquid.fungal }, .{ 60.0, 60.0, Liquid.lava } }) |p| {
        try std.testing.expect(m.paintWater(p[0], p[1], 25, true, .speckle, p[2]));
    }
    var fbs = std.io.fixedBufferStream(&buf);
    try write(m, fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "liquid:") != null);
    var line: usize = 0;
    try parse(fbs.getWritten(), back, &line);
    try std.testing.expectEqualSlices(u8, &m.water, &back.water);
    try std.testing.expectEqualSlices(u8, &m.waterEdge, &back.waterEdge);
    try std.testing.expectEqualSlices(u8, &m.waterKind, &back.waterKind);
    inline for (.{ .{ -60.0, -60.0, Liquid.water }, .{ 60.0, -60.0, Liquid.oil }, .{ -60.0, 60.0, Liquid.fungal }, .{ 60.0, 60.0, Liquid.lava } }) |p| {
        const i = gridIndex(back.half, WATER_N, p[0], p[1]).?;
        try std.testing.expectEqual(@as(u8, 1), back.water[i]);
        try std.testing.expectEqual(@as(u8, @intFromEnum(p[2])), back.waterKind[i]);
    }
    // AN ERASED POOL TAKES ITS KIND WITH IT, or plain water painted over an old lava run comes up molten.
    try std.testing.expect(m.paintWater(60, 60, 25, false, null, .water));
    const lav = gridIndex(m.half, WATER_N, 60, 60).?;
    try std.testing.expectEqual(@as(u8, 0), m.water[lav]);
    try std.testing.expectEqual(@as(u8, @intFromEnum(Liquid.water)), m.waterKind[lav]);
}

test "the height field round-trips, and a FLAT map writes no height record at all" {
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    const back = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(back);
    m.blank("Hills");

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
    try std.testing.expectApproxEqAbs(@as(f32, 0), m.heightAt(40, 0), 1e-6);

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
    for (0..HEIGHT_N) |iz| {
        for (0..HEIGHT_N) |ix| {
            m.height[iz * HEIGHT_N + ix] = heightByte(@as(f32, @floatFromInt(ix)) * 0.25);
        }
    }
    const step = 2 * m.half / @as(f32, @floatFromInt(HEIGHT_N - 1));
    const x0 = -m.half + 10 * step;
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), m.heightAt(x0, 0), 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 2.625), m.heightAt(x0 + step * 0.5, 0), 1e-3);
    try std.testing.expectApproxEqAbs(m.heightAt(-m.half, 0), m.heightAt(-m.half - 60, 0), 1e-4);
    try std.testing.expectApproxEqAbs(m.heightAt(m.half, 0), m.heightAt(m.half + 60, 0), 1e-4);

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
        "version: 1\nbelt: fern -1 -1 1 1 10 0.8 1.2 wobble=3\n",
        &m,
        &ln,
    ));
    try std.testing.expectError(ParseError.MissingField, parse("version: 1\nbelt: fern -1 -1 1 1\n", &m, &ln));
    try std.testing.expectError(ParseError.UnknownRecord, parse("version: 1\nsplat: 1 2 3\n", &m, &ln));
    try std.testing.expectError(ParseError.BadVersion, parse("version: 99\n", &m, &ln));
}

test "ONE FOE LIMIT, AND A MAP MAY SPEND ALL OF IT ON ONE KIND" {
    var m = Map{};
    var ln: usize = 0;
    const head = "version: 1\n";

    // The WHOLE budget as a single kind — the case a per-kind cap used to silently truncate at 24.
    var rows: [40 * MAX_FOES]u8 = undefined;
    var at: usize = 0;
    for (0..MAX_FOES) |i| at += (try std.fmt.bufPrint(rows[at..], "foe: shroom {d} 0 0 1 0.5\n", .{i % 90})).len;
    var doc: [40 * MAX_FOES + 64]u8 = undefined;
    try parse(try std.fmt.bufPrint(&doc, "{s}{s}", .{ head, rows[0..at] }), &m, &ln);
    try std.testing.expectEqual(MAX_FOES, m.nfoes);

    // …and every one of them fits the group that will have to hold it.
    try std.testing.expect(MAX_PER_KIND >= MAX_FOES);

    // One past the global budget is still a refusal, because that one is the map's own table.
    var over = Map{};
    try std.testing.expectError(ParseError.TooManyFoes, parse(
        try std.fmt.bufPrint(&doc, "{s}{s}foe: shroom 1 0 0 1 0.5\n", .{ head, rows[0..at] }),
        &over,
        &ln,
    ));
}

test "a value that only LOOKS parseable is a load error too" {
    var m = Map{};
    var ln: usize = 0;
    const head = "version: 1\n";
    try std.testing.expectError(ParseError.BadNumber, parse(head ++ "belt: fern -1 -1 1 1 10 0.8 1.2 field=ture\n", &m, &ln));
    try std.testing.expectError(ParseError.BadNumber, parse(head ++ "belt: fern -1 -1 1 1 10 0.8 1.2 field=yes\n", &m, &ln));
    try parse(head ++ "belt: fern -1 -1 1 1 10 0.8 1.2 field=0\n", &m, &ln);
    try std.testing.expect(!m.ops[1].field);
    try std.testing.expectError(ParseError.BadNumber, parse(head ++ "at: pillar nan 0 0 1\n", &m, &ln));
    try std.testing.expectError(ParseError.BadNumber, parse(head ++ "foe: toad 0 0 0 1 inf\n", &m, &ln));
    try std.testing.expectError(ParseError.BadNumber, parse("version: 1\nhalf: inf\n" ++ head[11..], &m, &ln));
    try std.testing.expectError(ParseError.BadNumber, parse("version: 1\nhalf: 0\n" ++ head[11..], &m, &ln));
    try std.testing.expectError(ParseError.BadNumber, parse("version: 1\nhalf: 99999\n" ++ head[11..], &m, &ln));
    try std.testing.expectError(ParseError.BadNumber, parse("version: 1\nhalf: 313\n" ++ head[11..], &m, &ln));
    try parse("version: 1\nhalf: 312\n" ++ head[11..], &m, &ln);
    try std.testing.expectApproxEqAbs(MAX_DECLARED_HALF, m.half, 1e-4);
    try parse("version: 1\nhalf: 280\n" ++ head[11..], &m, &ln);
    try std.testing.expectApproxEqAbs(DEFAULT_HALF, m.half, 1e-4);
    try std.testing.expect(DEFAULT_HALF <= MAX_DECLARED_HALF);
    try std.testing.expectError(ParseError.BadNumber, parse(head ++ "foe: toad 0 0 0 1 1e20\n", &m, &ln));
    try std.testing.expectError(ParseError.BadNumber, parse(head ++ "foe: toad 0 0 0 1 -0.5\n", &m, &ln));
    try std.testing.expectError(ParseError.BadNumber, parse(head ++ "foe: toad 0 0 0 1 1.5\n", &m, &ln));
    try parse(head ++ "foe: toad 0 0 0 1 0\nfoe: ogre 1 1 0 1 1\n", &m, &ln);
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
    m.reorder(0, 3);
    const want = [_]i32{ 1, 2, 3, 0, 4 };
    for (want, 0..) |v, i| try std.testing.expectEqual(v, m.ops[i].n);
    m.reorder(3, 0);
    for (0..5) |i| try std.testing.expectEqual(@as(i32, @intCast(i)), m.ops[i].n);
}

test "A SPAWN'S SCALE IS VALIDATED ON LOAD, because zero is a NaN rig and not a small skeleton" {
    const head = "version: 1\nhalf: 100.0\n";
    var m: Map = .{};
    var line: usize = 0;
    try parse(head ++ "foe: toad 0 0 0 1.0 0.5\n", &m, &line);
    try std.testing.expectEqual(@as(usize, 1), m.nfoes);
    inline for (.{ "0", "0.0", "-1.0", "99.0" }) |bad| {
        try std.testing.expectError(
            ParseError.BadNumber,
            parse(head ++ "foe: toad 0 0 0 " ++ bad ++ " 0.5\n", &m, &line),
        );
    }
}

test "THE OP CAP IS MEMORY — the editor's undo ring is whole-Map copies" {
    const one = @sizeOf(Map);
    const ring = one * 24;
    std.debug.print("\n  ops: {d} cap, {d} B an Op, {d:.1} MB a Map, {d:.1} MB for a 24-deep undo ring\n", .{ MAX_OPS, @sizeOf(Op), @as(f64, @floatFromInt(one)) / 1048576.0, @as(f64, @floatFromInt(ring)) / 1048576.0 });
    // The whole reason cover was baked to PATCHES and not to 13,228 individual `at:` ops.
    try std.testing.expect(ring < 200 * 1024 * 1024);
}

test "A UNIT'S IDLE AI AND ITS ROUTE SURVIVE A ROUND TRIP — and a map that never mentions them is untouched" {
    const head = "version: 1\n";
    var m: Map = undefined;
    var ln: usize = 0;
    // **THE OLD LINE STILL PARSES AND STILL WRITES ITSELF BACK IDENTICALLY.** This is the whole reason the tail
    // is optional: `01_fallen_plain.world` is authored and shipping, and it must not be rewritten by loading it.
    try parse(head ++ "foe: toad 3.00 -4.00 90.0 1.00 0.50\n", &m, &ln);
    try std.testing.expectEqual(FoeAi.hold, m.foes[0].ai);
    try std.testing.expectEqual(@as(u8, 0), m.foes[0].nwp);

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try write(&m, fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "foe: toad 3.00 -4.00 90.0 1.00 0.50\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "ai=") == null);
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "wp=") == null);

    // …and a unit that DOES carry one comes back with every point where it was put.
    ln = 0;
    try parse(head ++ "foe: ogre 1.00 2.00 0.0 1.00 0.25 ai=patrol wp=8.00,-3.00 wp=12.00,5.00\n", &m, &ln);
    try std.testing.expectEqual(FoeAi.patrol, m.foes[0].ai);
    try std.testing.expectEqual(@as(u8, 2), m.foes[0].nwp);
    try std.testing.expectApproxEqAbs(@as(f32, 12), m.foes[0].wp[1].x, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 5), m.foes[0].wp[1].z, 1e-4);
    try std.testing.expectEqual(@as(usize, 2), m.foes[0].route().len);

    fbs.reset();
    try write(&m, fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "ai=patrol") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "wp=8.00,-3.00") != null);
    // AND IT LOADS BACK THE SAME — the round trip is the claim, not the spelling.
    var back: Map = undefined;
    var bl: usize = 0;
    try parse(out, &back, &bl);
    try std.testing.expectEqual(m.foes[0].ai, back.foes[0].ai);
    try std.testing.expectEqual(m.foes[0].nwp, back.foes[0].nwp);

    // A ROUTE MAY NOT OVERRUN ITS OWN CAP, and a mode nobody has heard of is an error rather than a silent hold.
    ln = 0;
    try std.testing.expectError(ParseError.BadKind, parse(head ++ "foe: toad 0 0 0 1 0 ai=chase\n", &m, &ln));
    ln = 0;
    try std.testing.expectError(ParseError.UnknownKey, parse(head ++ "foe: toad 0 0 0 1 0 nonsense=1\n", &m, &ln));
    ln = 0;
    var many: [512]u8 = undefined;
    var at: usize = 0;
    at += (try std.fmt.bufPrint(many[at..], "{s}foe: toad 0 0 0 1 0", .{head})).len;
    for (0..MAX_WP + 1) |_| at += (try std.fmt.bufPrint(many[at..], " wp=1,1", .{})).len;
    at += (try std.fmt.bufPrint(many[at..], "\n", .{})).len;
    try std.testing.expectError(ParseError.TooManyWaypoints, parse(many[0..at], &m, &ln));
}

test "A SPAWN CARRIES ITS ROUTE WHEN IT MOVES — the legs are world-space, so a copy is not a body patrolling its old post" {
    var f = Foe{ .kind = .ogre, .x = 10, .z = -4, .ai = .patrol, .nwp = 2 };
    f.wp[0] = .{ .x = 14, .z = -4 };
    f.wp[1] = .{ .x = 14, .z = 6 };

    f.translate(-3, 7);
    try std.testing.expectApproxEqAbs(@as(f32, 7), f.x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 3), f.z, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 11), f.wp[0].x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 3), f.wp[0].z, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 11), f.wp[1].x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 13), f.wp[1].z, 1e-5);
    // The leg offsets off the body are what a move may not change.
    for (f.route()) |q| try std.testing.expect(q.x - f.x == 4);

    // Nothing past `nwp` is touched, so an unpainted slot cannot drift into the route on the next paint.
    try std.testing.expectApproxEqAbs(@as(f32, 0), f.wp[2].x, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), f.wp[2].z, 1e-6);
}

test "A ROOM IS A POLYGON — inside, outside, and the shared corner a ray must cross exactly once" {
    var a = Arena{};
    a.setName("hall");
    // An L, so a convex test cannot pass by accident: the notch at (+x, +z) is OUTSIDE.
    const pts = [_][2]f32{ .{ -10, -10 }, .{ 10, -10 }, .{ 10, 0 }, .{ 0, 0 }, .{ 0, 10 }, .{ -10, 10 } };
    for (pts, 0..) |p, i| {
        a.vx[i] = p[0];
        a.vz[i] = p[1];
    }
    a.n = pts.len;

    try std.testing.expect(a.contains(-5, 0));
    try std.testing.expect(a.contains(5, -5));
    try std.testing.expect(a.contains(-5, 5));
    // THE NOTCH. A rect over the same corners would answer true here, which is the whole point of a polygon.
    try std.testing.expect(!a.contains(5, 5));
    try std.testing.expect(!a.contains(-11, 0));
    try std.testing.expect(!a.contains(0, 11));
    // A RAY THROUGH A VERTEX CROSSES ITS TWO EDGES AND MUST STILL COUNT ONCE: swept along the corner row, a
    // `<=` on both ends flips twice and every point outside reads as in.
    for ([_]f32{ -10, 0, 10 }) |z| {
        try std.testing.expect(!a.contains(-40, z));
        try std.testing.expect(!a.contains(40, z));
    }
    // Fewer than three corners bounds nothing rather than crashing on the wrap.
    var thin = Arena{ .n = 2 };
    try std.testing.expect(!thin.contains(0, 0));
    try std.testing.expectApproxEqAbs(@as(f32, 7.0), thin.hold(mathx.ground(7, 7), 1).x, 1e-4);
}

test "AND THE WALL STANDS A BODY BACK INSIDE IT — the blink's answer, since there is no segment to refuse" {
    var a = Arena{ .n = 4 };
    const pts = [_][2]f32{ .{ -20, -20 }, .{ 20, -20 }, .{ 20, 20 }, .{ -20, 20 } };
    for (pts, 0..) |p, i| {
        a.vx[i] = p[0];
        a.vz[i] = p[1];
    }
    const R: f32 = 0.6;
    const mid = mathx.ground(3, -4);
    try std.testing.expectApproxEqAbs(mid.x, a.hold(mid, R).x, 1e-5);
    try std.testing.expectApproxEqAbs(mid.z, a.hold(mid, R).z, 1e-5);

    const gone = a.hold(mathx.ground(33, 4), R);
    try std.testing.expect(a.contains(gone.x, gone.z));
    try std.testing.expectApproxEqAbs(@as(f32, 20.0 - R), gone.x, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), gone.z, 1e-4);

    const lean = a.hold(mathx.ground(-19.9, 0), R);
    try std.testing.expectApproxEqAbs(@as(f32, -20.0 + R), lean.x, 1e-4);

    // A corner and a point ON the line are the two cases with no single answer.
    const corner = a.hold(mathx.ground(26, 26), R);
    try std.testing.expect(a.contains(corner.x, corner.z));
    const onLine = a.hold(mathx.ground(20, 0), R);
    try std.testing.expect(a.contains(onLine.x, onLine.z));
    std.debug.print("\n  arena hold: out at x33 -> {d:.2}, on the line -> {d:.2}, corner -> ({d:.2}, {d:.2})\n", .{ gone.x, onLine.x, corner.x, corner.z });
}

test "AN ARENA ROUND-TRIPS WITH ITS SEAL, and a room with under three corners is a LOAD ERROR" {
    var m = Map{};
    m.setName("Rooms");
    var a = Arena{ .n = 4, .nboss = 2 };
    a.setName("mycelian_hall");
    a.boss[0] = .fungal_swordsman;
    a.boss[1] = .fungal_magus;
    const pts = [_][2]f32{ .{ -26, -14 }, .{ 26, -14 }, .{ 30, 12 }, .{ -30, 12 } };
    for (pts, 0..) |p, i| {
        a.vx[i] = p[0];
        a.vz[i] = p[1];
    }
    m.arenas[0] = a;
    // …and a second room that holds NOTHING, which is bounds with no fight in them.
    var open = Arena{ .n = 3, .nboss = 0 };
    open.setName("yard");
    open.vx = [_]f32{0} ** MAX_ARENA_VERTS;
    open.vz = [_]f32{0} ** MAX_ARENA_VERTS;
    open.vx[1] = 8;
    open.vz[2] = 8;
    m.arenas[1] = open;
    m.narenas = 2;

    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try write(&m, fbs.writer());
    const text = fbs.getWritten();
    // The seal is written even when it is the default — there is no stamped room, so a silent one holds nothing.
    try std.testing.expect(std.mem.indexOf(u8, text, "arena: mycelian_hall boss=fungal_swordsman,fungal_magus") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "arena: yard boss=-") != null);

    var back = Map{};
    var ln: usize = 0;
    try parse(text, &back, &ln);
    try std.testing.expectEqual(@as(usize, 2), back.narenas);
    try std.testing.expectEqualStrings("mycelian_hall", back.arenas[0].label());
    try std.testing.expectEqual(@as(usize, 4), back.arenas[0].verts());
    try std.testing.expectEqual(@as(usize, 2), back.arenas[0].seal().len);
    try std.testing.expectEqual(@as(usize, 0), back.arenas[1].seal().len);
    for (pts, 0..) |p, i| {
        try std.testing.expectApproxEqAbs(p[0], back.arenas[0].vx[i], 1e-3);
        try std.testing.expectApproxEqAbs(p[1], back.arenas[0].vz[i], 1e-3);
    }
    try std.testing.expectEqual(@as(?usize, 0), back.arenaIndexAt(0, 0));
    try std.testing.expectEqual(@as(?usize, null), back.arenaIndexAt(0, 200));

    // TWO CORNERS ARE A LINE, and a truncated row may not come up as a room one corner smaller than authored.
    var bad = Map{};
    ln = 0;
    try std.testing.expectError(ParseError.ShortArena, parse("version: 1\narena: thin boss=- 0 0 1 1\n", &bad, &ln));
    // …and an odd float is a missing field, not a corner at z=0.
    ln = 0;
    try std.testing.expectError(ParseError.MissingField, parse("version: 1\narena: odd boss=- 0 0 1 1 2\n", &bad, &ln));
}

test "EVERY SHIPPED ROOM AND THE GATE STANDING IN IT SEAL ON THE SAME NAMES" {
    // **THE ROOM'S SEAL AND THE DOOR'S ARE TWO COPIES, SO THEY ARE PINNED RATHER THAN TRUSTED.** A wall that
    // outlives its door locks you in a fight that is over; a door that outlives its wall is a room you walk
    // out of the back of. Both are silent, and neither fails any other test.
    var dir = std.fs.cwd().openDir(DIR, .{ .iterate = true }) catch return error.SkipZigTest;
    defer dir.close();
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    var rooms: usize = 0;
    var paired: usize = 0;
    var it = dir.iterate();
    while (try it.next()) |ent| {
        if (ent.kind != .file or !std.mem.endsWith(u8, ent.name, EXT)) continue;
        var path: [PATH_CAP]u8 = undefined;
        const p = try std.fmt.bufPrint(&path, DIR ++ "/{s}", .{ent.name});
        var ln: usize = 0;
        load(p, m, &ln) catch continue;
        for (m.arenas[0..m.narenas]) |*a| {
            rooms += 1;
            for (m.ops[0..m.nops]) |*o| {
                if (!props.info(o.kind).ward) continue;
                if (!a.onWall(o.x, o.z)) continue;
                paired += 1;
                try std.testing.expectEqualSlices(FoeKind, a.seal(), o.seal());
            }
        }
    }
    std.debug.print("\n  shipped rooms: {d}, each with a gate on its wall: {d}\n", .{ rooms, paired });
    try std.testing.expect(rooms > 0 and paired == rooms);
}

test "AND EVERY SHIPPED ROOM IS A ROOM — an outline that does not cross itself, with its own bosses inside it" {
    var dir = std.fs.cwd().openDir(DIR, .{ .iterate = true }) catch return error.SkipZigTest;
    defer dir.close();
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    var checked: usize = 0;
    var it = dir.iterate();
    while (try it.next()) |ent| {
        if (ent.kind != .file or !std.mem.endsWith(u8, ent.name, EXT)) continue;
        var path: [PATH_CAP]u8 = undefined;
        const p = try std.fmt.bufPrint(&path, DIR ++ "/{s}", .{ent.name});
        var ln: usize = 0;
        load(p, m, &ln) catch continue;
        for (m.arenas[0..m.narenas]) |*a| {
            // A FIGURE-OF-EIGHT holds nothing in its own middle, and it is drawn by HAND: nothing else catches it.
            try std.testing.expect(a.simple());
            for (a.seal()) |k| {
                var placed: usize = 0;
                var held: usize = 0;
                for (m.foes[0..m.nfoes]) |f| {
                    if (f.kind != k) continue;
                    placed += 1;
                    if (a.contains(f.x, f.z)) held += 1;
                }
                // A body a room seals on and does NOT stand in is a room that never lets go.
                if (placed > 0) try std.testing.expect(held > 0);
                checked += 1;
            }
            std.debug.print("\n  {s}: {s} — {d} corners, {d:.0} m to its nearest wall, middle ({d:.0}, {d:.0})", .{
                ent.name, a.label(), a.verts(), a.nearestWall(a.middle()).d, a.middle().x, a.middle().z,
            });
        }
    }
    std.debug.print("\n", .{});
    try std.testing.expect(checked > 0);
}

test "A FIGURE-OF-EIGHT IS NOT A ROOM, and adjacent corners touching is not a crossing" {
    var ok = Arena{ .n = 4 };
    const sq = [_][2]f32{ .{ -10, -10 }, .{ 10, -10 }, .{ 10, 10 }, .{ -10, 10 } };
    for (sq, 0..) |p, i| {
        ok.vx[i] = p[0];
        ok.vz[i] = p[1];
    }
    try std.testing.expect(ok.simple());

    // The same four corners with two of them swapped, which is the bow-tie a hand-drawn room makes.
    var bow = Arena{ .n = 4 };
    const tie = [_][2]f32{ .{ -10, -10 }, .{ 10, -10 }, .{ -10, 10 }, .{ 10, 10 } };
    for (tie, 0..) |p, i| {
        bow.vx[i] = p[0];
        bow.vz[i] = p[1];
    }
    try std.testing.expect(!bow.simple());
    // …and it is exactly the shape whose own middle answers FALSE, which is why it has to be refused.
    try std.testing.expect(!bow.contains(0, 0));
}

test "WHAT A ROOM COSTS A FRAME — the per-body wall test, counted rather than guessed" {
    var dir = std.fs.cwd().openDir(DIR, .{ .iterate = true }) catch return error.SkipZigTest;
    defer dir.close();
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    var ln: usize = 0;
    load(DIR ++ "/01_fallen_plain" ++ EXT, m, &ln) catch return error.SkipZigTest;
    if (m.narenas == 0) return error.SkipZigTest;
    const a = &m.arenas[0];
    const n = a.verts();
    // Every body pays `arenaIndexAt` (one `contains` per room) and, inside a SHUT one, a `hold`: a second
    // `contains` plus one segment projection per wall. `game` asks twice a frame — the step gate and the settle.
    const perOutside = m.narenas * n;
    const perInside = perOutside + n + n;
    std.debug.print("\n  room cost: {d} rooms x {d} walls — a body outside pays {d} crossings a call, one inside {d} + {d} projections; {d} bodies in it x2 calls = {d}\n", .{
        m.narenas, n, perOutside, perOutside + n, n, 6, 2 * 6 * perInside,
    });
    // The shape of the bill is what matters: LINEAR in the walls, and the common map pays nothing at all
    // because `narenas` is 0 and the loop never runs.
    try std.testing.expect(2 * 6 * perInside < 1000);
}

test "A MAP SAYS WHERE THE PLAYER STARTS, and one that does not says the old hard-coded spot" {
    var m = Map{};
    m.setName("Spawn");
    m.start = .{ .x = -195.5, .z = -137.25, .yaw = 65 };
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try write(&m, fbs.writer());
    const text = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, text, "start: -195.50 -137.25 65.0") != null);

    var back = Map{};
    var ln: usize = 0;
    try parse(text, &back, &ln);
    try std.testing.expectApproxEqAbs(@as(f32, -195.5), back.start.x, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, -137.25), back.start.z, 1e-3);
    try std.testing.expectApproxEqAbs(mathx.radians(65.0), back.start.facing(), 1e-4);

    // **A MAP WITH NO `start:` ROW COMES UP WHERE EVERY MAP USED TO** — (0, 4) facing south, which is what
    // `game.beginGame` hard-coded, so nothing shipped moves under this.
    var old = Map{};
    ln = 0;
    try parse("version: 1\nname: Old\n", &old, &ln);
    try std.testing.expectApproxEqAbs(@as(f32, 0), old.start.x, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 4), old.start.z, 1e-6);
    try std.testing.expectApproxEqAbs(std.math.pi, old.start.facing(), 1e-5);
}

test "AND EVERY SHIPPED MAP STARTS HIM SOMEWHERE INSIDE ITSELF" {
    var dir = std.fs.cwd().openDir(DIR, .{ .iterate = true }) catch return error.SkipZigTest;
    defer dir.close();
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    var n: usize = 0;
    var it = dir.iterate();
    while (try it.next()) |ent| {
        if (ent.kind != .file or !std.mem.endsWith(u8, ent.name, EXT)) continue;
        var path: [PATH_CAP]u8 = undefined;
        const p = try std.fmt.bufPrint(&path, DIR ++ "/{s}", .{ent.name});
        var ln: usize = 0;
        load(p, m, &ln) catch continue;
        // A start outside the world is a man who wakes up in the void, and it is one typo away at all times.
        try std.testing.expect(@abs(m.start.x) <= m.half and @abs(m.start.z) <= m.half);
        n += 1;
    }
    try std.testing.expect(n > 0);
}

test "WHAT THE ROOMS PANEL COSTS A FRAME — the op walk that finds a room's gate, timed" {
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    var ln: usize = 0;
    load(DIR ++ "/01_fallen_plain" ++ EXT, m, &ln) catch return error.SkipZigTest;
    if (m.narenas == 0) return error.SkipZigTest;
    const a = &m.arenas[0];
    var timer = try std.time.Timer.start();
    var hits: usize = 0;
    const ROUNDS = 240;
    for (0..ROUNDS) |_| {
        for (m.ops[0..m.nops]) |*o| {
            if (!props.info(o.kind).ward) continue;
            if (a.onWall(o.x, o.z)) hits += 1;
        }
    }
    const us = @as(f64, @floatFromInt(timer.read())) / 1000.0 / @as(f64, @floatFromInt(ROUNDS));
    std.debug.print("\n  rooms panel: one walk of {d} ops finds {d} gate(s) in {d:.1} us — {d:.3}% of a 16.7 ms frame\n", .{ m.nops, hits / ROUNDS, us, 100.0 * us / 16700.0 });
    try std.testing.expect(hits > 0);
}

test "A TRIGGER ON A NAME THE MAP NEVER DECLARED WRITES A NAME, NOT UNDEFINED MEMORY" {
    // The editor can add a `flag` condition to a map with no flags in it (`editor.drawScriptModal`), and the
    // name tables are `undefined` past their count — so the writer read whatever was in the slab and put it in
    // the file. `unset` parses straight back as a declared name, so the row survives the round trip.
    const m = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(m);
    m.* = .{};
    m.setName("Undeclared");
    var t = Trigger{};
    @memcpy(t.id[0..4], "trig");
    t.conds[0] = .{ .kind = .flag, .slot = 0, .on = true };
    t.conds[1] = .{ .kind = .counter, .slot = 7, .cmp = .ge, .n = 2 };
    t.nconds = 2;
    t.acts[0] = .{ .kind = .timer, .slot = 3, .v = 5 };
    t.nacts = 1;
    m.trigs[0] = t;
    m.ntrigs = 1;
    try std.testing.expectEqual(@as(usize, 0), m.nflags);

    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try write(m, fbs.writer());
    const text = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, text, "flag unset=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "counter unset >= 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "timer unset=5") != null);

    // …and it comes back as a real declared name rather than a load error.
    const back = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(back);
    var ln: usize = 0;
    try parse(text, back, &ln);
    try std.testing.expectEqual(@as(usize, 1), back.ntrigs);
    try std.testing.expect(back.nflags == 1 and back.ncounters == 1 and back.ntimers == 1);
    try std.testing.expectEqualStrings("unset", idText(&back.flagNames[0]));
}
