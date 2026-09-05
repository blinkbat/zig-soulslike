const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const collision = @import("../core/collision.zig");
const wf = @import("../world/worldfmt.zig");

const art = @import("propart.zig");
const ruins = @import("propruins.zig");
const build = @import("propbuild.zig");
const village = @import("propvillage.zig");
const rock = @import("proprock.zig");
const wood = @import("propwood.zig");
const flora = @import("propflora.zig");
const fx = @import("propfx.zig");
const bone = @import("propbone.zig");
const ash = @import("propash.zig");
const fungus = @import("propfungus.zig");
const coral = @import("propcoral.zig");
const gold = @import("propgold.zig");
const market = @import("propmarket.zig");
const forge = @import("propforge.zig");
const ember = @import("propember.zig");

const v3 = mathx.v3;


pub const Kind = enum(u8) {
    pillar,
    broken,
    block,
    arch,
    wall,
    tree,
    graves,
    sword,
    bonfire,
    tower,
    gate,
    rubble,
    banner,
    statue,
    chapel,
    watchtower,
    cottage,
    causeway,
    paving,
    cart,
    monolith,
    cliff,
    cliff2,
    cliff3,
    cliff4,
    cliff5,
    cliff6,
    boulder,
    rocks,
    stump,
    log,
    well,
    shrine,
    lantern,
    fence,
    barrels,
    woodpile,
    bones,
    sarcophagus,
    stairs,
    gibbet,
    cairn,
    chest,
    outcrop,
    scree,
    torch,
    brazier,
    campfire,
    campfire_lit,
    water,
    tuft,
    patch,
    shrub,
    flowers,
    reeds,
    glow,
    bush,
    bramble,
    fern,
    grasstall,
    clover,
    moss,
    mushrooms,
    nettles,
    thistle,
    foxglove,
    heather,
    gorse,
    cattails,
    lilypads,
    bracken,
    thicket,
    wildflowers,
    ivy,
    bigtree,
    bigtree2,
    bigtree3,
    willow,
    conifer,
    birch,
    snag,
    sapling,
    rib,
    rib2,
    rib3,
    ribarch,
    skull,
    vertebra,
    ashheap,
    ashdune,
    cinders,
    charspar,
    hoodoo,
    spire,
    balanced,
    fingers,
    obelisk,
    plinth,
    altar,
    rotlog,
    deadfall,
    capgiant,
    capgiant2,
    capgiant3,
    capcolossal,
    captower,
    hyphaarch,
    glowcluster,
    lampstalk,
    fleshfold,
    sporevent,
    glowvein,
    tubecoral,
    tubespire,
    fancoral,
    antlercoral,
    floatsac,
    floatshoal,
    hangcurtain,
    puffballs,
    deadfingers,
    crustfungus,
    shelfstack,
    brainknot,
    pipeclutch,
    coralcrust,
    shards,
    slabs,
    cobbles,
    whaleback,
    capcluster,
    bracket,
    glowcap,
    sporepod,
    // (`enumFromName`/`@tagName`), never by ordinal. What IS ordinal-locked is every `[NK]` table in this file: `INFO` is comptime-pinned row for row (`INFO[i].kind == i`), so a kind added anywhere but beside its own row is a compile error.
    giltarch,
    muqarnas,
    giltdome,
    minaret,
    jali,
    giltcolumn,
    giltbasin,
    giltfinial,
    giltleaf,
    marblefloor,
    marbleslab,
    marblestair,
    ashcrag,
    stalagmite,
    menhir,
    stonecarve,
    merchanthut,
    packstack,
    trestletable,
    goodsrack,
    awning,
    rugpile,
    scalepost,
    waterjars,
    hitchrail,
    pickup,
    foggate,
    ladder,
    anvil,
    forge,
    quenchtrough,
    toolrack,
    stairflight,
    illusory,
    emberrock,
    emberrocks,
    burningrock,
    cindercone,
    firespire,
    emberpillar,
    emberarch,
    basaltcolumns,
    crackedslab,
    magmavein,
    lavacrust,
    emberbed,
    scoria,
};


pub const Group = enum {
    ruins,
    gilt,
    buildings,
    village,
    treasure,
    rock,
    trees,
    fire,
    water,
    grass,
    flowers,
    brush,
    ferns,
    wetland,
    fungus,
    bone,
    ash,
    market,
    firelands,

    pub const N = @typeInfo(Group).@"enum".fields.len;

    pub fn label(g: Group) [:0]const u8 {
        return switch (g) {
            .ruins => "Ruins",
            .gilt => "Gilded Ruins",
            .buildings => "Buildings",
            .village => "Village",
            .treasure => "Treasure",
            .rock => "Rock",
            .trees => "Trees",
            .fire => "Fire",
            .water => "Water",
            .grass => "Grass",
            .flowers => "Flowers",
            .brush => "Brush",
            .ferns => "Ferns",
            .wetland => "Wetland",
            .fungus => "Fungus",
            .bone => "Great Bones",
            .ash => "Ashfall",
            .market => "Caravan",
            .firelands => "Firelands",
        };
    }
};

pub fn displayName(k: Kind) [:0]const u8 {
    return switch (k) {
        .pillar => "Column",
        .broken => "Snapped Column",
        .block => "Ruin Block",
        .arch => "Gate Arch",
        .wall => "Ruined Wall",
        .tree => "Dead Tree",
        .graves => "Graves",
        .sword => "Planted Sword",
        .bonfire => "Bonfire Camp",
        .tower => "Horizon Keep",
        .gate => "Colossal Gate",
        .rubble => "Rubble",
        .banner => "War Banner",
        .statue => "Sentinel Statue",
        .chapel => "Chapel",
        .watchtower => "Watchtower",
        .cottage => "Ruined House",
        .causeway => "Causeway",
        .paving => "Flagstones",
        .cart => "Broken Cart",
        .monolith => "Standing Stone",
        .cliff => "Cliff Face (Weathered)",
        .cliff2 => "Cliff Face (Blocky)",
        .cliff3 => "Cliff Face (Ragged)",
        .cliff4 => "Cliff Face (Ivied)",
        .cliff5 => "Cliff Face (Collapsed)",
        .cliff6 => "Cliff Face (Overgrown)",
        .boulder => "Boulder",
        .rocks => "Rock Cluster",
        .stump => "Stump",
        .log => "Fallen Log",
        .well => "Well",
        .shrine => "Wayside Shrine",
        .lantern => "Post Lantern",
        .fence => "Fence Run",
        .barrels => "Barrels",
        .woodpile => "Woodpile",
        .bones => "Old Bones",
        .sarcophagus => "Sarcophagus",
        .stairs => "Stair Fragment",
        .gibbet => "Gibbet Cage",
        .cairn => "Cairn",
        .chest => "Treasure Chest",
        .outcrop => "Bedrock Shelf",
        .scree => "Scree",
        .torch => "Iron Torch",
        .brazier => "Brazier",
        .campfire => "Extinguished Campfire",
        .campfire_lit => "Campfire",
        .water => "Water Sheet",
        .tuft => "Grass Tuft",
        .patch => "Grass Patch",
        .shrub => "Shrub",
        .flowers => "Flowers",
        .reeds => "Reeds",
        .glow => "Glowing Bloom",
        .bush => "Bush",
        .bramble => "Bramble",
        .fern => "Fern",
        .grasstall => "Tall Grass",
        .clover => "Clover Mat",
        .moss => "Moss",
        .mushrooms => "Mushrooms",
        .nettles => "Nettles",
        .thistle => "Thistle",
        .foxglove => "Foxglove",
        .heather => "Heather",
        .gorse => "Gorse",
        .cattails => "Bulrushes",
        .lilypads => "Lily Pads",
        .bracken => "Dead Bracken",
        .thicket => "Thicket",
        .wildflowers => "Wildflowers",
        .ivy => "Ivy",
        .bigtree => "Great Tree I",
        .bigtree2 => "Great Tree II",
        .bigtree3 => "Great Tree III",
        .willow => "Willow",
        .conifer => "Conifer",
        .birch => "Birch",
        .snag => "Dead Snag",
        .sapling => "Sapling",
        .rib => "Great Rib",
        .rib2 => "Great Rib (Bowed)",
        .rib3 => "Great Rib (Steep)",
        .ribarch => "Rib Arch",
        .skull => "Colossal Skull",
        .vertebra => "Great Vertebra",
        .ashheap => "Ash Heap",
        .ashdune => "Ash Dune",
        .cinders => "Cinder Crust",
        .charspar => "Charred Spar",
        .hoodoo => "Hoodoo",
        .spire => "Rock Spire",
        .balanced => "Balanced Rock",
        .fingers => "Split Slabs",
        .obelisk => "Obelisk",
        .plinth => "Empty Plinth",
        .altar => "Altar Stone",
        .rotlog => "Rotted Log",
        .deadfall => "Deadfall",
        .capgiant => "Great Cap (Broad)",
        .capgiant2 => "Great Cap (Parasol)",
        .capgiant3 => "Great Cap (Table)",
        .capcolossal => "Colossal Cap",
        .captower => "Cap Tower",
        .hyphaarch => "Hyphal Arch",
        .glowcluster => "Glow Knot",
        .lampstalk => "Lamp Stalk",
        .fleshfold => "Flesh Fold",
        .sporevent => "Spore Vent",
        .glowvein => "Glow Veins",
        .tubecoral => "Tube Sponges",
        .tubespire => "Tube Spire",
        .fancoral => "Coral Fan",
        .antlercoral => "Antler Coral",
        .floatsac => "Float Sac",
        .floatshoal => "Float Shoal",
        .hangcurtain => "Hanging Curtain",
        .puffballs => "Puffballs",
        .deadfingers => "Dead Fingers",
        .crustfungus => "Crust Fungus",
        .shelfstack => "Shelf Stack",
        .brainknot => "Brain Knot",
        .pipeclutch => "Pipe Clutch",
        .coralcrust => "Coral Crust",
        .shards => "Rock Shards",
        .slabs => "Shale Slabs",
        .cobbles => "Cobbles",
        .whaleback => "Whaleback",
        .capcluster => "Cap Cluster",
        .bracket => "Bracket Shelves",
        .glowcap => "Glowcap",
        .sporepod => "Spore Pods",
        .giltarch => "Gilded Gate",
        .muqarnas => "Muqarnas Block",
        .giltdome => "Split Dome",
        .minaret => "Broken Minaret",
        .jali => "Pierced Screen",
        .giltcolumn => "Gilded Column",
        .giltbasin => "Star Basin",
        .giltfinial => "Fallen Finial",
        .giltleaf => "Drift of Gold Leaf",
        .marblefloor => "Marble Paving",
        .marbleslab => "Broken Marble Block",
        .marblestair => "Marble Stair",
        .ashcrag => "Clinker Crag",
        .stalagmite => "Stalagmites",
        .menhir => "Raised Stone",
        .stonecarve => "Carved Stone",
        .merchanthut => "Merchant's Booth",
        .packstack => "Roped Freight",
        .trestletable => "Trestle Table",
        .goodsrack => "Goods Rack",
        .awning => "Awning",
        .rugpile => "Stacked Rugs",
        .scalepost => "Weighing Post",
        .waterjars => "Water Jars",
        .hitchrail => "Hitching Rail",
        .pickup => "Item",
        .foggate => "Fog Gate",
        .ladder => "Ladder",
        .anvil => "Anvil",
        .forge => "Forge",
        .quenchtrough => "Quench Trough",
        .toolrack => "Tool Rack",
        .stairflight => "Stair Flight",
        .illusory => "Illusory Wall",
        .emberrock => "Ember Boulder",
        .emberrocks => "Ember Rock Cluster",
        .burningrock => "Burning Rock",
        .cindercone => "Cinder Cone",
        .firespire => "Fire Spire",
        .emberpillar => "Riven Pillar",
        .emberarch => "Riven Arch",
        .basaltcolumns => "Basalt Columns",
        .crackedslab => "Cracked Slab",
        .magmavein => "Magma Veins",
        .lavacrust => "Lava Crust",
        .emberbed => "Ember Bed",
        .scoria => "Scoria",
    };
}

pub fn group(k: Kind) Group {
    return switch (k) {
        .pillar, .broken, .block, .arch, .wall,
        .statue, .monolith, .paving, .stairs, .rubble,
        .banner, .sword, .graves, .sarcophagus, .bones,
        .gibbet, .cairn,
        => .ruins,
        .chapel, .watchtower, .cottage, .tower, .gate, .causeway, .foggate, .ladder, .stairflight => .buildings,
        .obelisk, .plinth, .altar => .ruins,
        .well, .shrine, .lantern, .fence, .barrels, .woodpile, .cart, .bonfire => .village,
        .anvil, .quenchtrough, .toolrack => .village,
        .chest, .pickup => .treasure,
        .boulder, .rocks, .outcrop, .scree, .cliff, .cliff2, .cliff3, .cliff4, .cliff5, .cliff6, .stump, .log,
        .shards, .slabs, .cobbles, .whaleback,
        .hoodoo, .spire, .balanced, .fingers, .rotlog, .deadfall, .illusory,
        => .rock,
        .tree, .bigtree, .bigtree2, .bigtree3, .willow, .conifer, .birch, .snag, .sapling => .trees,
        .torch, .brazier, .campfire, .campfire_lit, .forge => .fire,
        .water => .water,
        .tuft, .patch, .grasstall, .clover, .moss => .grass,
        .flowers, .wildflowers, .foxglove, .thistle, .glow => .flowers,
        .shrub, .bush, .bramble, .thicket, .gorse, .heather, .nettles, .ivy => .brush,
        .fern, .bracken => .ferns,
        .reeds, .cattails, .lilypads => .wetland,
        .mushrooms, .capgiant, .capgiant2, .capgiant3, .capcolossal, .captower, .hyphaarch,
        .glowcluster, .lampstalk, .fleshfold, .sporevent, .glowvein, .capcluster, .bracket, .glowcap, .sporepod,
        .tubecoral, .tubespire, .fancoral, .antlercoral, .floatsac, .floatshoal, .hangcurtain,
        .puffballs, .deadfingers, .crustfungus, .shelfstack, .brainknot, .pipeclutch, .coralcrust => .fungus,
        .rib, .rib2, .rib3, .ribarch, .skull, .vertebra => .bone,
        .ashheap, .ashdune, .cinders, .charspar => .ash,
        .giltarch, .muqarnas, .giltdome, .minaret, .jali, .giltcolumn, .giltbasin, .giltfinial,
        .giltleaf, .marblefloor, .marbleslab, .marblestair => .gilt,
        .ashcrag, .stalagmite, .menhir, .stonecarve => .ash,
        .merchanthut, .packstack, .trestletable, .goodsrack, .awning,
        .rugpile, .scalepost, .waterjars, .hitchrail => .market,
        .emberrock, .emberrocks, .burningrock, .cindercone, .firespire, .emberpillar, .emberarch,
        .basaltcolumns, .crackedslab, .magmavein, .lavacrust, .emberbed, .scoria => .firelands,
    };
}

pub const Biome = enum {
    any,
    ruins,
    village,
    forest,
    rock,
    wetland,
    ash,
    bone,
    fungal,
    firelands,

    pub const N = @typeInfo(Biome).@"enum".fields.len;

    pub fn label(b: Biome) [:0]const u8 {
        return switch (b) {
            .any => "Anywhere",
            .ruins => "Ruins",
            .village => "Village",
            .forest => "Forest",
            .rock => "Rock",
            .wetland => "Wetland",
            .ash => "Ashfall",
            .bone => "Bonefield",
            .fungal => "Mycelian",
            .firelands => "Firelands",
        };
    }
};

pub fn biome(k: Kind) Biome {
    return switch (k) {
        .rubble, .chest, .pickup, .water, .foggate, .ladder, .stairflight, .illusory,
        .torch, .brazier, .campfire, .campfire_lit,
        .tuft, .patch, .shrub, .flowers, .glow, .grasstall, .clover,
        .thistle, .foxglove, .heather, .gorse, .wildflowers,
        => .any,

        .pillar, .broken, .block, .arch, .wall, .graves, .sword, .tower, .gate,
        .banner, .statue, .causeway, .paving, .monolith, .bones, .sarcophagus,
        .stairs, .gibbet, .cairn, .chapel, .watchtower, .obelisk, .plinth, .altar,
        => .ruins,

        .bonfire, .cottage, .cart, .well, .shrine, .lantern, .fence, .barrels, .woodpile => .village,
        .anvil, .forge, .quenchtrough, .toolrack => .village,

        .tree, .stump, .log, .bigtree, .bigtree2, .bigtree3, .willow, .conifer, .birch,
        .snag, .sapling, .rotlog, .deadfall,
        .bush, .bramble, .fern, .moss, .mushrooms, .nettles, .bracken, .thicket, .ivy,
        => .forest,

        .cliff, .cliff2, .cliff3, .cliff4, .cliff5, .cliff6,
        .boulder, .rocks, .outcrop, .scree, .hoodoo, .spire, .balanced, .fingers,
        .shards, .slabs, .cobbles, .whaleback,
        => .rock,

        .reeds, .cattails, .lilypads => .wetland,
        .ashheap, .ashdune, .cinders, .charspar,
        .ashcrag, .stalagmite, .menhir, .stonecarve,
        .giltarch, .muqarnas, .giltdome, .minaret, .jali, .giltcolumn, .giltbasin, .giltfinial,
        .giltleaf, .marblefloor, .marbleslab, .marblestair,
        .merchanthut, .packstack, .trestletable, .goodsrack, .awning,
        .rugpile, .scalepost, .waterjars, .hitchrail,
        => .ash,
        .rib, .rib2, .rib3, .ribarch, .skull, .vertebra => .bone,
        .capgiant, .capgiant2, .capgiant3, .capcolossal, .captower, .hyphaarch,
        .glowcluster, .lampstalk, .fleshfold, .sporevent, .glowvein,
        .tubecoral, .tubespire, .fancoral, .antlercoral, .floatsac, .floatshoal, .hangcurtain,
        .capcluster, .bracket, .glowcap, .sporepod,
        .puffballs, .deadfingers, .crustfungus, .shelfstack, .brainknot, .pipeclutch, .coralcrust,
        => .fungal,
        .emberrock, .emberrocks, .burningrock, .cindercone, .firespire, .emberpillar, .emberarch,
        .basaltcolumns, .crackedslab, .magmavein, .lavacrust, .emberbed, .scoria,
        => .firelands,
    };
}

pub fn inBiome(k: Kind, b: Biome) bool {
    const own = biome(k);
    return own == b or own == .any;
}

pub const IVY_HOSTS = [_]Kind{
    .wall,    .pillar,  .broken,     .block,  .arch,
    .statue,  .cottage, .chapel,     .watchtower, .stairs,
    .monolith, .obelisk, .plinth,    .altar,
};

pub fn ivyClimbs(k: Kind) bool {
    for (IVY_HOSTS) |h| {
        if (h == k) return true;
    }
    return false;
}

comptime {
    for (IVY_HOSTS) |k| {
        const b = biome(k);
        if (b != .ruins and b != .village) @compileError("props: ivy host `" ++ @tagName(k) ++ "` is not built stone");
    }
}

pub const NK = @typeInfo(Kind).@"enum".fields.len;

pub const Stock = enum { decor, props, interact };

pub fn holdsLoot(k: Kind) bool {
    return switch (k) {
        .chest, .pickup => true,
        else => false,
    };
}

pub fn stock(k: Kind) Stock {
    const nfo = info(k);
    if (nfo.flora) return .decor;
    if (nfo.interact) return .interact;
    return .props;
}

pub const FLORA_KINDS = kindsOn(.decor);
pub const SOLID_KINDS = kindsOn(.props);
pub const INTERACT_KINDS = kindsOn(.interact);

fn kindsOn(comptime s: Stock) [countOn(s)]Kind {
    @setEvalBranchQuota(30000);
    var out: [countOn(s)]Kind = undefined;
    var n = 0;
    for (0..NK) |i| {
        const k: Kind = @enumFromInt(i);
        if (stock(k) == s) {
            out[n] = k;
            n += 1;
        }
    }
    return out;
}

fn countOn(comptime s: Stock) usize {
    @setEvalBranchQuota(30000);
    var n: usize = 0;
    for (0..NK) |i| {
        if (stock(@enumFromInt(i)) == s) n += 1;
    }
    return n;
}

comptime {
    std.debug.assert(FLORA_KINDS.len + SOLID_KINDS.len + INTERACT_KINDS.len == NK);
    for (INFO) |row| std.debug.assert(!(row.interact and row.flora));
}
pub const Part = art.Part;

pub const Deck = art.Deck;
pub const Flight = art.Flight;

pub const LADDER_STANDOFF = build.LADDER_STANDOFF;

pub const HERO_R_HERE = art.HERO_R_HERE;
pub const TOWER_CLEAR = art.TOWER_CLEAR;
pub const TOWER_OUT = art.TOWER_R;

pub const Blocker = art.Blocker;

pub const LightSpec = struct {
    y: f32, // height of the flame above the prop's base (fires sit on the prop axis, so x/z are 0)
    col: rl.Vector3,
    radius: f32,
    flicker: f32 = 0.18,
};

pub const Info = struct {
    kind: Kind, // self-check: must equal its own row index (see the comptime block below)
    build: *const fn (rl.Shader) rl.Model,
    veil: ?*const fn (rl.Shader) rl.Model = null,
    stow: ?*const fn (rl.Shader) rl.Model = null,
    bound: f32,
    top: f32,
    view: f32,
    flora: bool = false,
    interact: bool = false,
    solid: bool = false,
    occl: []const Blocker = &.{},
    casts: bool = true,
    ward: bool = false,
    /// A wall that is not there: solid and sight-blocking until the hero's blade, roll or arrow touches it, then gone (`env.dispelIllusion`).
    illusion: bool = false,
    parts: []const Part = &.{},
    /// **METRES OF LOCAL HEIGHT ONE COPY OF THE MESH SPANS**, or 0 for everything else — one mesh, one draw.
    stack: f32 = 0,
    /// A stacked kind that is WALKED: its sections advance along −Z and its surface is a deck of treads.
    flight: ?Flight = null,
    decks: []const Deck = &.{},
    climb: bool = false,
    light: ?LightSpec = null,
    surf: collision.Surface = .stone,
};

const FAR: f32 = 400.0;

fn circleParts(comptime r: f32, comptime h: f32) []const Part {
    return &.{.{ .r = r, .h = h }};
}

/// The ring, and the two knee-high steps that stand off it.
const WATCH_PARTS = art.towerRing ++ [_]Part{
    .{ .ax = 4.20, .az = -4.55, .bx = 4.20, .bz = -4.55, .r = 0.50, .h = 0.9 },
    .{ .ax = 5.60, .az = 1.85, .bx = 5.60, .bz = 1.85, .r = 0.50, .h = 0.9 },
};

/// The gilt dome's wall: 24 segments on a 2.85 m ring (measured off its footprint map), the two at either end of z left out for the doors.
const DOME_SEGS: usize = 24;
const DOME_RING = blk: {
    var out: [DOME_SEGS - 4 + 3]Part = undefined;
    var n: usize = 0;
    for (0..DOME_SEGS) |i| {
        if (i == 5 or i == 6 or i == 17 or i == 18) continue;
        const a0 = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, DOME_SEGS);
        const a1 = std.math.tau * @as(f32, @floatFromInt(i + 1)) / @as(f32, DOME_SEGS);
        out[n] = .{ .ax = 2.85 * @cos(a0), .az = 2.85 * @sin(a0), .bx = 2.85 * @cos(a1), .bz = 2.85 * @sin(a1), .r = 0.35, .h = gold.DOME_DRUM };
        n += 1;
    }
    // The porch block before either door, and the pedestal inside.
    out[n] = .{ .ax = 0.05, .az = -2.75, .bx = 0.05, .bz = -2.75, .r = 0.50, .h = 1.2, .flat = true };
    out[n + 1] = .{ .ax = 0.05, .az = 2.75, .bx = 0.05, .bz = 2.75, .r = 0.50, .h = 1.2, .flat = true };
    out[n + 2] = .{ .ax = 0.50, .az = -0.27, .bx = 0.50, .bz = -0.27, .r = 0.30, .h = 1.5 };
    break :blk out;
};

const WATCH_DECKS = blk: {
    var out: [build.WATCH_STOREYS.len * 2]Deck = undefined;
    for (build.WATCH_STOREYS, 0..) |st, i| {
        out[i * 2] = .{ .r = art.TOWER_R, .y = st.top() };
        out[i * 2 + 1] = .{ .x = st.hx, .z = st.hz, .r = build.WATCH_HATCH_R, .y = st.top(), .hole = true };
    }
    break :blk out;
};

pub const WATCH_FLOORS = blk: {
    var out: [build.WATCH_STOREYS.len]f32 = undefined;
    for (build.WATCH_STOREYS, 0..) |st, i| out[i] = st.top();
    break :blk out;
};

/// The illusory wall is `cliff2`'s face, so it shares the row's dimensions.
const CLIFF2_BOUND: f32 = 17.0;
const CLIFF2_TOP: f32 = 14.0;
/// A coarse pair that keeps the rows' comptime checks honest; `partsOf` hands out the set fitted off the rock itself.
const cliffParts = [_]Part{
    .{ .ax = -5.4, .bx = 5.4, .r = 2.9, .h = 15.5 },
    .{ .ax = -2.2, .az = 2.1, .bx = 2.6, .bz = 2.4, .r = 2.2, .h = 15.5 },
};

/// THE COLLIDERS A KIND STANDS UP. A cliff's are fitted off its own rock (`rock.cliffColliders`, one capsule per lobe and boulder through the walk band); every other kind carries its row's. Nothing that builds or draws a collider reads `Info.parts` directly.
pub fn partsOf(k: Kind) []const Part {
    return switch (k) {
        .cliff => rock.cliffColliders(0),
        .cliff2, .illusory => rock.cliffColliders(1),
        .cliff3 => rock.cliffColliders(2),
        .cliff4 => rock.cliffColliders(3),
        .cliff5 => rock.cliffColliders(4),
        .cliff6 => rock.cliffColliders(5),
        else => info(k).parts,
    };
}
pub const FIT_CAP = rock.FIT_CAP;

pub const Audit = struct { pen: f32 = 0, over: f32 = 0, outside: f32 = 0, stone: usize = 0 };

/// Collider against mesh in the kind's own frame, through the walk band. `pen` is the deepest a body could stand inside the stone (a stone vertex's distance past every collider), `over` the farthest a collider's edge stands from any stone (an invisible wall), `outside` the share of stone vertices a collider does not cover.
/// The walk band the audit and the footprint map look through: a body's shins to its crown.
pub const AUDIT_LO: f32 = 0.25;
pub const AUDIT_HI: f32 = 1.75;

pub fn colliderAudit(pos: []const f32, uv2: []const f32, parts: []const Part) Audit {
    const LO = AUDIT_LO;
    const HI = AUDIT_HI;
    // Stone that stops under the step is stepped over, so it owes no collider.
    const STEP = wf.STEP_UP;
    var out = Audit{};
    const n = pos.len / 3;
    var past: usize = 0;
    // Every solid triangle that reaches the band and past the step, sampled at its corners, its edges' middles and its centre — a wall is one quad with no vertex at chest height.
    var tri: usize = 0;
    while (tri + 2 < n) : (tri += 3) {
        const ya = pos[tri * 3 + 1];
        const yb = pos[(tri + 1) * 3 + 1];
        const yc = pos[(tri + 2) * 3 + 1];
        const yt = @max(ya, @max(yb, yc));
        if (yt < STEP or @min(ya, @min(yb, yc)) > HI or !solidMat(uv2[tri * 2])) continue;
        // Only the slice of the triangle between the step and the crown counts: a facet of a boulder that runs from the ground to its belly is wider up there than where a body meets it.
        var poly: [8]rl.Vector3 = undefined;
        var np = clipBand(.{ v3(pos[tri * 3], ya, pos[tri * 3 + 2]), v3(pos[(tri + 1) * 3], yb, pos[(tri + 1) * 3 + 2]), v3(pos[(tri + 2) * 3], yc, pos[(tri + 2) * 3 + 2]) }, STEP, HI, &poly);
        if (np < 3) continue;
        var cx: f32 = 0;
        var cz: f32 = 0;
        for (poly[0..np]) |q| {
            cx += q.x;
            cz += q.z;
        }
        poly[np] = v3(cx / @as(f32, @floatFromInt(np)), 0, cz / @as(f32, @floatFromInt(np)));
        np += 1;
        for (poly[0..np]) |p| {
            out.stone += 1;
            var d: f32 = 1e9;
            for (parts) |pt| d = @min(d, partGap(p, pt));
            if (d > 0.05) past += 1;
            out.pen = @max(out.pen, d);
        }
    }
    if (out.stone > 0) out.outside = @as(f32, @floatFromInt(past)) / @as(f32, @floatFromInt(out.stone));
    if (out.stone == 0) out.pen = 0;
    for (parts) |pt| {
        var k: usize = 0;
        while (k < 32) : (k += 1) {
            const q = partRim(pt, @as(f32, @floatFromInt(k)) / 32.0);
            var d: f32 = 1e9;
            var t: usize = 0;
            while (t + 2 < n) : (t += 3) {
                const y0 = pos[t * 3 + 1];
                const y1 = pos[(t + 1) * 3 + 1];
                const y2 = pos[(t + 2) * 3 + 1];
                if (@max(y0, @max(y1, y2)) < LO or @min(y0, @min(y1, y2)) > HI or !solidMat(uv2[t * 2])) continue;
                d = @min(d, triGapXZ(q, v3(pos[t * 3], 0, pos[t * 3 + 2]), v3(pos[(t + 1) * 3], 0, pos[(t + 1) * 3 + 2]), v3(pos[(t + 2) * 3], 0, pos[(t + 2) * 3 + 2])));
                if (d <= 0) break;
            }
            if (d < 1e8) out.over = @max(out.over, d);
        }
    }
    return out;
}

/// The triangle cut to `lo <= y <= hi`, as up to seven points (Sutherland-Hodgman on y, twice). Returns how many were written.
fn clipBand(tri: [3]rl.Vector3, lo: f32, hi: f32, out: []rl.Vector3) usize {
    var a: [8]rl.Vector3 = undefined;
    const na: usize = 3;
    a[0] = tri[0];
    a[1] = tri[1];
    a[2] = tri[2];
    var b: [8]rl.Vector3 = undefined;
    var nb: usize = 0;
    // Keep y >= lo.
    for (0..na) |i| {
        const p = a[i];
        const q = a[(i + 1) % na];
        const pin = p.y >= lo;
        const qin = q.y >= lo;
        if (pin) {
            b[nb] = p;
            nb += 1;
        }
        if (pin != qin) {
            const t = (lo - p.y) / (q.y - p.y);
            b[nb] = v3(p.x + (q.x - p.x) * t, lo, p.z + (q.z - p.z) * t);
            nb += 1;
        }
    }
    // Keep y <= hi.
    var n: usize = 0;
    for (0..nb) |i| {
        const p = b[i];
        const q = b[(i + 1) % nb];
        const pin = p.y <= hi;
        const qin = q.y <= hi;
        if (pin) {
            out[n] = p;
            n += 1;
        }
        if (pin != qin) {
            const t = (hi - p.y) / (q.y - p.y);
            out[n] = v3(p.x + (q.x - p.x) * t, hi, p.z + (q.z - p.z) * t);
            n += 1;
        }
    }
    return n;
}

/// The materials a body walks into; cloth, plant, water, flame, smoke and hide are not stone. `m` is `Builder.matf`, the material id as the mesh carries it.
pub fn solidMat(m: f32) bool {
    const id: u32 = @intFromFloat(m + 0.5);
    if (id > @intFromEnum(gfx.Mat.gilt)) return false;
    return switch (@as(gfx.Mat, @enumFromInt(id))) {
        .plain, .stone, .wood, .steel, .marble, .bark, .gilt => true,
        else => false,
    };
}

/// The part as the solid it becomes at the origin, unscaled.
pub fn partSolid(pt: Part) collision.Solid {
    var s = collision.capsule(pt.ax, pt.az, pt.bx, pt.bz, pt.r);
    s.flat = pt.flat;
    return s;
}

/// Signed distance from a point to a part's edge in the kind's frame: past 0 is outside.
pub fn partGap(p: rl.Vector3, pt: Part) f32 {
    return collision.gap(p, partSolid(pt));
}

/// A point on the part's rim, `u` once around it: two straight sides and two caps.
fn partRim(pt: Part, u: f32) rl.Vector3 {
    const dx = pt.bx - pt.ax;
    const dz = pt.bz - pt.az;
    const l = @sqrt(dx * dx + dz * dz);
    if (pt.flat) {
        // A rectangle's four sides, `u` once around, in the frame `collision` walks itself.
        const fr = collision.frameOf(partSolid(pt));
        const t = u * 4.0;
        const side: usize = @intFromFloat(@floor(t));
        const f = t - @floor(t);
        const along: f32 = switch (side) {
            0 => -fr.hl + 2.0 * fr.hl * f,
            1 => fr.hl,
            2 => fr.hl - 2.0 * fr.hl * f,
            else => -fr.hl,
        };
        const across: f32 = switch (side) {
            0 => -pt.r,
            1 => -pt.r + 2.0 * pt.r * f,
            2 => pt.r,
            else => pt.r - 2.0 * pt.r * f,
        };
        return v3(fr.cx + fr.ux * along - fr.uz * across, 0, fr.cz + fr.uz * along + fr.ux * across);
    }
    if (l < 1e-4) {
        const a = u * std.math.tau;
        return v3(pt.ax + @cos(a) * pt.r, 0, pt.az + @sin(a) * pt.r);
    }
    const ux = dx / l;
    const uz = dz / l;
    const t = u * 4.0;
    if (t < 1.0) return v3(pt.ax + dx * t - uz * pt.r, 0, pt.az + dz * t + ux * pt.r);
    if (t < 2.0) {
        const a = (t - 1.0) * std.math.pi - std.math.pi * 0.5;
        return v3(pt.bx + (ux * @cos(a) - uz * @sin(a)) * pt.r, 0, pt.bz + (uz * @cos(a) + ux * @sin(a)) * pt.r);
    }
    if (t < 3.0) return v3(pt.bx - dx * (t - 2.0) + uz * pt.r, 0, pt.bz - dz * (t - 2.0) - ux * pt.r);
    const a = (t - 3.0) * std.math.pi + std.math.pi * 0.5;
    return v3(pt.ax + (ux * @cos(a) - uz * @sin(a)) * pt.r, 0, pt.az + (uz * @cos(a) + ux * @sin(a)) * pt.r);
}

/// Distance in XZ from `p` to the triangle `a b c`: 0 inside it.
pub fn triGapXZ(p: rl.Vector3, a: rl.Vector3, b: rl.Vector3, c: rl.Vector3) f32 {
    const s0 = (b.x - a.x) * (p.z - a.z) - (b.z - a.z) * (p.x - a.x);
    const s1 = (c.x - b.x) * (p.z - b.z) - (c.z - b.z) * (p.x - b.x);
    const s2 = (a.x - c.x) * (p.z - c.z) - (a.z - c.z) * (p.x - c.x);
    if ((s0 >= 0 and s1 >= 0 and s2 >= 0) or (s0 <= 0 and s1 <= 0 and s2 <= 0)) return 0;
    const d0 = mathx.distXZ(p, mathx.closestOnSegXZ(p, a, b));
    const d1 = mathx.distXZ(p, mathx.closestOnSegXZ(p, b, c));
    const d2 = mathx.distXZ(p, mathx.closestOnSegXZ(p, c, a));
    return @min(d0, @min(d1, d2));
}

pub const INFO = [NK]Info{
    // Every part below is sized off the kind's footprint map (`--shot-props` prints one per kind): the stone through the walk band, not a number that looked right.
    .{ .kind = .pillar, .build = ruins.pillarWhole, .bound = 6.2, .top = 5.8, .view = 240, .parts = circleParts(0.80, 5.8) },
    // The stump stands at (-0.3, 1.05) on a knee-high drum; a second drum lies to its west.
    .{ .kind = .broken, .build = ruins.pillarBroken, .bound = 3.6, .top = 3.3, .view = 200, .parts = &.{
        .{ .ax = -0.30, .az = 1.05, .bx = -0.30, .bz = 1.05, .r = 0.42, .h = 2.9 },
        .{ .ax = -0.10, .bx = -0.10, .r = 0.85, .h = 0.7 },
        .{ .ax = -1.35, .az = -0.40, .bx = -1.35, .bz = 0.05, .r = 0.30, .h = 0.6 },
    } },
    .{ .kind = .block, .build = ruins.blockMesh, .bound = 2.6, .top = 1.85, .view = 180, .solid = true, .parts = &.{.{ .ax = -0.40, .az = 0.02, .bx = 0.32, .bz = 0.02, .r = 0.78, .h = 1.65, .flat = true }} },
    .{ .kind = .arch, .build = ruins.archMesh, .bound = 7.9, .top = 7.2, .view = 260, .parts = &.{
        .{ .ax = -2.74, .az = -0.03, .bx = -2.74, .bz = -0.03, .r = 0.58, .h = 4.8 },
        .{ .ax = 2.74, .az = -0.03, .bx = 2.74, .bz = -0.03, .r = 0.58, .h = 4.8 },
        .{ .ax = -1.65, .az = -0.18, .bx = -1.65, .bz = -0.18, .r = 0.45, .h = 0.8 },
    } },
    .{ .kind = .wall, .build = ruins.wallMesh, .bound = 5.0, .top = 3.6, .view = 220, .solid = true, .parts = &.{.{ .ax = -3.55, .az = -0.01, .bx = 3.25, .bz = -0.01, .r = 0.37, .h = 3.0, .flat = true }} },
    .{ .kind = .tree, .build = wood.treeMesh, .bound = 5.3, .top = 4.9, .view = 240, .parts = circleParts(0.38, 3.6), .occl = &.{.{ .r = 0.90, .y1 = 4.3 }}, .surf = .wood },
    // Five stones, not one ring around nothing.
    .{ .kind = .graves, .build = ruins.gravesMesh, .bound = 2.3, .top = 1.05, .view = 150, .parts = &.{
        .{ .ax = -0.30, .az = -0.05, .bx = -0.30, .bz = -0.05, .r = 0.30, .h = 0.9 },
        .{ .ax = -0.40, .az = -0.87, .bx = -0.40, .bz = -0.87, .r = 0.30, .h = 0.9 },
        .{ .ax = 1.15, .az = -0.53, .bx = 1.15, .bz = -0.53, .r = 0.25, .h = 0.9 },
        .{ .ax = 1.65, .az = 0.40, .bx = 1.65, .bz = 0.40, .r = 0.20, .h = 0.9 },
        .{ .ax = 0.50, .az = 0.80, .bx = 0.50, .bz = 0.80, .r = 0.30, .h = 1.0 },
    } },
    .{ .kind = .sword, .build = ruins.swordMesh, .bound = 1.6, .top = 1.35, .view = 120 },
    .{ .kind = .bonfire, .build = ruins.bonfireMesh, .veil = ruins.bonfireVeilMesh, .stow = ruins.bonfireGuitarMesh, .bound = 7.2, .top = 5.4, .view = 300, .solid = true, .light = .{ .y = 0.45, .col = v3(0.86, 0.48, 0.18), .radius = 11.0, .flicker = 0.17 } },
    // A SQUARE keep, 7.7 m a side, with a buttress running out to +z. The 3.4 m disc left every corner 2 m in the open.
    .{ .kind = .tower, .build = ruins.towerMesh, .bound = 17.5, .top = 17.2, .view = FAR, .solid = true, .parts = &.{
        .{ .ax = -0.10, .az = 0.05, .bx = 0.10, .bz = 0.05, .r = 3.85, .h = 14.0, .flat = true },
        .{ .ax = 0.55, .az = 4.25, .bx = 2.85, .bz = 4.25, .r = 0.40, .h = 5.0, .flat = true },
        .{ .ax = 2.15, .az = 5.05, .bx = 2.65, .bz = 5.05, .r = 0.45, .h = 5.0, .flat = true },
        .{ .ax = 1.40, .az = 6.10, .bx = 2.10, .bz = 6.10, .r = 0.50, .h = 5.0, .flat = true },
        .{ .ax = 6.05, .az = 2.25, .bx = 6.05, .bz = 2.25, .r = 0.50, .h = 0.9 },
    } },
    // Two SQUARE towers, 5.9 m a side, and the fall between them: a heap and three standing pieces on the approach.
    .{ .kind = .gate, .build = ruins.gateMesh, .bound = 19.6, .top = 16.4, .view = FAR, .solid = true, .parts = &.{
        .{ .ax = -7.45, .az = -0.10, .bx = -7.45, .bz = -0.10, .r = 3.15, .h = 16.0, .flat = true },
        .{ .ax = 7.25, .az = -0.10, .bx = 7.25, .bz = -0.10, .r = 3.35, .h = 16.0, .flat = true },
        .{ .ax = -1.90, .az = -5.60, .bx = 0.10, .bz = -5.60, .r = 0.70, .h = 2.2 },
        .{ .ax = -1.70, .az = -4.00, .bx = -1.70, .bz = -2.80, .r = 0.75, .h = 2.2 },
        .{ .ax = 0.60, .az = -4.10, .bx = 0.60, .bz = -3.10, .r = 0.50, .h = 2.2 },
        .{ .ax = -1.60, .az = -1.30, .bx = -1.60, .bz = -0.80, .r = 0.70, .h = 2.0 },
        .{ .ax = -0.65, .az = -0.20, .bx = -0.65, .bz = -0.20, .r = 0.65, .h = 0.8 },
    } },
    .{ .kind = .rubble, .build = ruins.rubbleMesh, .bound = 1.4, .top = 0.4, .view = 130 },
    .{ .kind = .banner, .build = ruins.bannerMesh, .bound = 3.4, .top = 3.2, .view = 190 },
    .{ .kind = .statue, .build = ruins.statueMesh, .bound = 3.0, .top = 2.7, .view = 230, .parts = circleParts(0.90, 2.7) },
    // Walls are boxes so the corners are corners; the doorway is x -1.15..1.15; the font stands inside the door, the altar step runs the back.
    .{ .kind = .chapel, .build = build.chapelMesh, .bound = 9.5, .top = 6.6, .view = FAR, .solid = true, .parts = &.{
        .{ .ax = -2.6, .az = -3.2, .bx = -2.6, .bz = 3.2, .r = 0.42, .h = 4.4, .flat = true },
        .{ .ax = 2.45, .az = -3.2, .bx = 2.45, .bz = 3.2, .r = 0.55, .h = 4.4, .flat = true },
        .{ .ax = -2.6, .az = 3.6, .bx = 2.6, .bz = 3.6, .r = 0.42, .h = 4.4, .flat = true },
        .{ .ax = -2.6, .az = -3.55, .bx = -1.45, .bz = -3.55, .r = 0.42, .h = 4.4, .flat = true },
        .{ .ax = 1.45, .az = -3.65, .bx = 2.6, .bz = -3.65, .r = 0.50, .h = 4.4, .flat = true },
        .{ .ax = -1.40, .az = 2.75, .bx = 1.40, .bz = 2.75, .r = 0.55, .h = 1.1, .flat = true },
        .{ .ax = 1.55, .az = -1.90, .bx = 1.55, .bz = -1.90, .r = 0.40, .h = 1.6 },
        .{ .ax = 0.40, .az = -2.45, .bx = 1.00, .bz = -2.45, .r = 0.50, .h = 0.8, .flat = true },
        .{ .ax = -1.50, .az = -0.75, .bx = -0.70, .bz = -0.75, .r = 0.42, .h = 0.8, .flat = true },
        .{ .ax = -1.75, .az = -2.10, .bx = -1.75, .bz = -2.10, .r = 0.45, .h = 1.2, .flat = true },
        .{ .ax = -2.65, .az = 3.95, .bx = -2.65, .bz = 3.95, .r = 0.55, .h = 4.4, .flat = true },
        .{ .ax = 2.55, .az = 3.95, .bx = 2.55, .bz = 3.95, .r = 0.45, .h = 1.0, .flat = true },
        .{ .ax = -1.65, .az = 1.70, .bx = -1.65, .bz = 1.70, .r = 0.12, .h = 1.6 },
        .{ .ax = -1.90, .az = 1.91, .bx = -1.90, .bz = 1.91, .r = 0.12, .h = 1.6 },
        .{ .ax = 1.50, .az = -0.17, .bx = 1.50, .bz = -0.17, .r = 0.12, .h = 1.6 },
        .{ .ax = -1.42, .az = 1.88, .bx = -1.42, .bz = 1.88, .r = 0.12, .h = 1.6 },
        .{ .ax = 1.20, .az = 1.88, .bx = 1.20, .bz = 1.88, .r = 0.12, .h = 1.6 },
        .{ .ax = 1.42, .az = 2.10, .bx = 1.42, .bz = 2.10, .r = 0.12, .h = 1.6 },
    } },
    .{ .kind = .watchtower, .build = build.watchtowerMesh, .bound = 25.0, .top = build.WATCH_TOP, .view = FAR, .solid = true, .parts = &WATCH_PARTS, .decks = &WATCH_DECKS },
    // The door is x -0.6..0.6 on the -z wall; the wall to its right had no collider at all.
    .{ .kind = .cottage, .build = build.cottageMesh, .bound = 5.6, .top = 4.0, .view = 280, .solid = true, .parts = &.{
        .{ .ax = -2.3, .az = -1.56, .bx = -2.3, .bz = 1.56, .r = 0.34, .h = 2.6, .flat = true },
        .{ .ax = 2.3, .az = -1.56, .bx = 2.3, .bz = 1.56, .r = 0.34, .h = 2.6, .flat = true },
        .{ .ax = -1.96, .az = 1.9, .bx = 1.96, .bz = 1.9, .r = 0.34, .h = 3.4, .flat = true },
        .{ .ax = -2.3, .az = -1.9, .bx = -1.0, .bz = -1.9, .r = 0.34, .h = 1.2, .flat = true },
        .{ .ax = 0.95, .az = -1.9, .bx = 1.55, .bz = -1.9, .r = 0.34, .h = 1.2, .flat = true },
    }, .surf = .wood },
    .{ .kind = .causeway, .build = build.causewayMesh, .bound = 6.5, .top = 0.5, .view = 240, .solid = true, .parts = &.{
        .{ .ax = -5.0, .az = -1.45, .bx = 5.0, .bz = -1.45, .r = 0.20, .h = 0.5 },
        .{ .ax = -5.0, .az = 1.45, .bx = 5.0, .bz = 1.45, .r = 0.20, .h = 0.5 },
    } },
    .{ .kind = .paving, .build = build.pavingMesh, .bound = 3.2, .top = 0.15, .view = 150, .solid = true },
    // The bed, the two wheels, and the shaft standing off the -x end.
    .{ .kind = .cart, .build = village.cartMesh, .bound = 3.4, .top = 1.7, .view = 170, .parts = &.{
        .{ .ax = -0.60, .bx = 0.55, .r = 0.50, .h = 1.3, .flat = true },
        .{ .ax = -1.00, .az = -0.72, .bx = 0.90, .bz = -0.72, .r = 0.10, .h = 1.0, .flat = true },
        .{ .ax = -1.00, .az = 0.60, .bx = 0.90, .bz = 0.60, .r = 0.10, .h = 1.0, .flat = true },
        .{ .ax = -1.50, .az = 0.95, .bx = -0.45, .bz = 0.95, .r = 0.08, .h = 1.2, .flat = true },
        .{ .ax = 1.00, .az = 0.18, .bx = 2.10, .bz = 0.18, .r = 0.08, .h = 0.7, .flat = true },
    }, .surf = .wood },
    .{ .kind = .monolith, .build = rock.monolithMesh, .bound = 5.2, .top = 4.9, .view = FAR, .parts = circleParts(0.62, 4.6) },
    .{ .kind = .cliff, .build = rock.cliff1, .bound = 18.0, .top = 15.5, .view = FAR, .solid = true, .parts = &cliffParts },
    .{ .kind = .cliff2, .build = rock.cliff2, .bound = CLIFF2_BOUND, .top = CLIFF2_TOP, .view = FAR, .solid = true, .parts = &cliffParts },
    .{ .kind = .cliff3, .build = rock.cliff3, .bound = 19.0, .top = 16.8, .view = FAR, .solid = true, .parts = &cliffParts },
    .{ .kind = .cliff4, .build = rock.cliff4, .bound = 17.5, .top = 14.9, .view = FAR, .solid = true, .parts = &cliffParts },
    .{ .kind = .cliff5, .build = rock.cliff5, .bound = 17.0, .top = 13.3, .view = FAR, .solid = true, .parts = &cliffParts },
    .{ .kind = .cliff6, .build = rock.cliff6, .bound = 18.0, .top = 14.5, .view = FAR, .solid = true, .parts = &cliffParts },
    .{ .kind = .boulder, .build = rock.boulderMesh, .bound = 3.2, .top = 2.5, .view = 220, .parts = &.{.{ .ax = 0.08, .az = -0.20, .bx = 0.08, .bz = 0.15, .r = 1.00, .h = 2.3 }} },
    .{ .kind = .rocks, .build = rock.rocksMesh, .bound = 2.2, .top = 0.85, .view = 160 },
    .{ .kind = .stump, .build = wood.stumpMesh, .bound = 1.7, .top = 1.25, .view = 150, .parts = circleParts(0.46, 1.2), .surf = .wood },
    .{ .kind = .log, .build = wood.logMesh, .bound = 3.0, .top = 0.75, .view = 160, .parts = &.{.{ .ax = -1.9, .bx = 1.9, .r = 0.36, .h = 0.75 }}, .surf = .wood },
    .{ .kind = .well, .build = village.wellMesh, .bound = 2.6, .top = 2.4, .view = 240, .parts = circleParts(1.05, 1.15) },
    .{ .kind = .shrine, .build = village.shrineMesh, .bound = 2.8, .top = 2.5, .view = 240, .parts = circleParts(0.72, 1.9), .light = .{ .y = 1.20, .col = v3(0.56, 0.32, 0.13), .radius = 5.5, .flicker = 0.19 } },
    .{ .kind = .lantern, .build = village.lanternMesh, .bound = 3.4, .top = 3.1, .view = 230, .parts = circleParts(0.17, 3.0), .light = .{ .y = 2.62, .col = v3(1.05, 0.60, 0.25), .radius = 11.5, .flicker = 0.08 }, .surf = .metal },
    .{ .kind = .fence, .build = village.fenceMesh, .bound = 3.6, .top = 1.25, .view = 180, .parts = &.{.{ .ax = -3.0, .bx = 3.0, .r = 0.16, .h = 1.25 }}, .surf = .wood },
    // Three barrels, each its own.
    .{ .kind = .barrels, .build = village.barrelsMesh, .bound = 1.8, .top = 1.35, .view = 170, .parts = &.{
        .{ .ax = -0.75, .az = -0.45, .bx = -0.75, .bz = -0.45, .r = 0.34, .h = 1.2 },
        .{ .ax = 0.02, .az = 0.06, .bx = 0.02, .bz = 0.06, .r = 0.34, .h = 1.2 },
        .{ .ax = 0.55, .az = 0.30, .bx = 0.55, .bz = 0.30, .r = 0.28, .h = 0.6 },
        .{ .ax = -0.45, .az = 0.65, .bx = -0.45, .bz = 0.65, .r = 0.30, .h = 0.7 },
    }, .surf = .wood },
    .{ .kind = .woodpile, .build = village.woodpileMesh, .bound = 2.4, .top = 1.35, .view = 180, .parts = &.{.{ .ax = 0.02, .az = -0.20, .bx = 0.02, .bz = 0.15, .r = 0.72, .h = 1.3, .flat = true }}, .surf = .wood },
    .{ .kind = .bones, .build = village.bonesMesh, .bound = 1.6, .top = 0.55, .view = 140 },
    // The tomb lies west of its own origin, x -1.66..0.6.
    .{ .kind = .sarcophagus, .build = village.sarcophagusMesh, .bound = 2.4, .top = 1.05, .view = 200, .parts = &.{
        .{ .ax = -1.23, .az = 0.30, .bx = 0.27, .bz = 0.30, .r = 0.43, .h = 1.0, .flat = true },
        .{ .ax = 0.90, .az = 0.50, .bx = 1.50, .bz = 0.50, .r = 0.32, .h = 0.7, .flat = true },
        .{ .ax = -0.90, .az = -0.33, .bx = 0.80, .bz = -0.33, .r = 0.20, .h = 0.8, .flat = true },
    } },
    // Not a flight: a dressing you walk round, so the steps and the back wall are solid.
    .{ .kind = .stairs, .build = village.stairsMesh, .bound = 2.8, .top = 1.5, .view = 190, .parts = &.{
        .{ .ax = -0.65, .az = -0.06, .bx = -0.05, .bz = -0.06, .r = 0.69, .h = 1.4, .flat = true },
        .{ .ax = -1.40, .az = 0.85, .bx = 1.20, .bz = 0.85, .r = 0.15, .h = 1.4, .flat = true },
    } },
    .{ .kind = .gibbet, .build = village.gibbetMesh, .bound = 4.4, .top = 4.1, .view = 220, .parts = circleParts(0.24, 4.0), .surf = .wood },
    .{ .kind = .cairn, .build = rock.cairnMesh, .bound = 1.8, .top = 1.5, .view = 180, .parts = circleParts(0.52, 1.4) },
    .{ .kind = .chest, .build = village.chestMesh, .bound = 1.6, .top = village.CHEST_TOP + 0.34, .view = 150, .solid = true, .interact = true, .parts = &.{.{ .r = 0.56, .h = village.CHEST_HINGE_Y }}, .surf = .wood },
    .{ .kind = .outcrop, .build = rock.outcropMesh, .bound = 3.4, .top = 1.1, .view = 200, .parts = &.{.{ .ax = -1.0, .az = -0.30, .bx = 1.0, .bz = -0.30, .r = 0.80, .h = 1.05 }} },
    .{ .kind = .scree, .build = rock.screeMesh, .bound = 2.6, .top = 0.35, .view = 160 },
    .{ .kind = .torch, .build = fx.torchMesh, .bound = 2.6, .top = 2.35, .view = 200, .parts = circleParts(0.18, 2.0), .light = .{ .y = 1.98, .col = v3(0.64, 0.34, 0.13), .radius = 6.0, .flicker = 0.15 }, .surf = .metal },
    .{ .kind = .brazier, .build = fx.brazierMesh, .bound = 1.9, .top = 1.55, .view = 210, .parts = circleParts(0.50, 1.2), .light = .{ .y = 1.14, .col = v3(1.55, 0.84, 0.29), .radius = 16.0, .flicker = 0.13 }, .surf = .metal },
    .{ .kind = .campfire, .build = fx.deadCampfireMesh, .bound = 1.5, .top = 0.6, .view = 200, .parts = circleParts(0.45, 0.5), .surf = .stone },
    // …AND ONE YOU CAN SIT AT. `interact` shelves it under the editor's Interactables layer; `rest.isRestKind` is what makes it a bonfire.
    // THE BOUND AND THE VIEW ARE THE SMOKE'S NOW, NOT THE STONES': at 2.6/1.1 the column was culled the moment the hearth left frame. The bonfire's row is 7.2/5.4/300.
    .{ .kind = .campfire_lit, .build = fx.campfireMesh, .veil = fx.campfireVeilMesh, .stow = fx.campfireGuitarMesh, .bound = 5.6, .top = 4.2, .view = 300, .interact = true, .solid = true, .parts = circleParts(0.45, 0.5), .light = .{ .y = 0.52, .col = v3(1.05, 0.52, 0.17), .radius = 13.0, .flicker = 0.18 } },
    .{ .kind = .water, .build = fx.waterMesh, .bound = 30.0, .top = 0.1, .view = FAR, .solid = true, .casts = false },
    .{ .kind = .tuft, .build = flora.tuftMesh, .bound = 0.9, .top = 0.8, .view = 85, .flora = true, .casts = false },
    .{ .kind = .patch, .build = flora.patchMesh, .bound = 2.2, .top = 0.8, .view = 95, .flora = true, .casts = false },
    .{ .kind = .shrub, .build = flora.shrubMesh, .bound = 1.2, .top = 0.75, .view = 115, .flora = true, .casts = false },
    .{ .kind = .flowers, .build = flora.flowersMesh, .bound = 1.0, .top = 0.5, .view = 90, .flora = true, .casts = false },
    .{ .kind = .reeds, .build = flora.reedsMesh, .bound = 1.6, .top = 1.35, .view = 130, .flora = true, .casts = false },
    .{ .kind = .glow, .build = flora.glowMesh, .bound = 1.0, .top = 0.55, .view = 140, .flora = true, .casts = false },
    .{ .kind = .bush, .build = flora.bushMesh, .bound = 1.8, .top = 1.25, .view = 130, .flora = true, .casts = false },
    .{ .kind = .bramble, .build = flora.brambleMesh, .bound = 1.9, .top = 0.9, .view = 120, .flora = true, .casts = false },
    .{ .kind = .fern, .build = flora.fernMesh, .bound = 1.3, .top = 0.8, .view = 105, .flora = true, .casts = false },
    .{ .kind = .grasstall, .build = flora.grassTallMesh, .bound = 1.4, .top = 1.2, .view = 90, .flora = true, .casts = false },
    .{ .kind = .clover, .build = flora.cloverMesh, .bound = 1.5, .top = 0.22, .view = 58, .flora = true, .casts = false },
    .{ .kind = .moss, .build = flora.mossMesh, .bound = 1.7, .top = 0.18, .view = 58, .flora = true, .casts = false },
    .{ .kind = .mushrooms, .build = flora.mushroomsMesh, .bound = 0.9, .top = 0.45, .view = 62, .flora = true, .casts = false },
    .{ .kind = .nettles, .build = flora.nettlesMesh, .bound = 1.5, .top = 0.95, .view = 110, .flora = true, .casts = false },
    .{ .kind = .thistle, .build = flora.thistleMesh, .bound = 1.3, .top = 1.05, .view = 110, .flora = true, .casts = false },
    .{ .kind = .foxglove, .build = flora.foxgloveMesh, .bound = 1.6, .top = 1.3, .view = 120, .flora = true, .casts = false },
    .{ .kind = .heather, .build = flora.heatherMesh, .bound = 1.6, .top = 0.55, .view = 105, .flora = true, .casts = false },
    .{ .kind = .gorse, .build = flora.gorseMesh, .bound = 1.8, .top = 1.15, .view = 125, .flora = true, .casts = false },
    .{ .kind = .cattails, .build = flora.cattailsMesh, .bound = 2.0, .top = 1.75, .view = 140, .flora = true, .casts = false },
    .{ .kind = .lilypads, .build = flora.lilypadsMesh, .bound = 2.4, .top = 0.16, .view = 115, .flora = true, .casts = false },
    .{ .kind = .bracken, .build = flora.brackenMesh, .bound = 1.7, .top = 0.75, .view = 105, .flora = true, .casts = false },
    .{ .kind = .thicket, .build = flora.thicketMesh, .bound = 2.8, .top = 1.9, .view = 160, .flora = true, .casts = false },
    .{ .kind = .wildflowers, .build = flora.wildflowersMesh, .bound = 1.5, .top = 0.65, .view = 105, .flora = true, .casts = false },
    .{ .kind = .ivy, .build = flora.ivyMesh, .bound = 2.4, .top = 2.0, .view = 150, .flora = true, .casts = false },
    // BOLE THEN CROWN: one cylinder cannot be narrow at the foot and wide at the boughs. Sized off `bigTreeMesh`'s own numbers.
    // BOLE AND BUTTRESS ROOTS: each big tree throws six root flares a metre tall and half a metre out, at its own bearings.
    .{ .kind = .bigtree, .build = wood.bigTree1, .bound = 13.5, .top = 11.0, .view = FAR, .parts = &.{
        .{ .r = 0.95, .h = 6.0 },
        .{ .ax = -0.95, .az = -0.60, .bx = -1.50, .bz = -0.85, .r = 0.20, .h = 1.3 },
        .{ .ax = 0.85, .az = -0.70, .bx = 1.20, .bz = -1.00, .r = 0.20, .h = 1.3 },
        .{ .ax = 0.90, .az = 0.15, .bx = 1.40, .bz = 0.20, .r = 0.20, .h = 1.3 },
        .{ .ax = -0.95, .az = 0.40, .bx = -1.50, .bz = 0.45, .r = 0.20, .h = 1.3 },
        .{ .ax = 0.15, .az = -0.90, .bx = 0.15, .bz = -1.55, .r = 0.18, .h = 1.3 },
        .{ .ax = -0.25, .az = 0.90, .bx = -0.25, .bz = 1.25, .r = 0.18, .h = 1.3 },
        .{ .ax = 0.80, .az = 0.65, .bx = 1.30, .bz = 1.15, .r = 0.20, .h = 1.3 },
    }, .occl = &.{ .{ .r = 1.30, .y1 = 5.0 }, .{ .r = 4.80, .y0 = 4.5, .y1 = 11.0 } }, .surf = .wood },
    .{ .kind = .bigtree2, .build = wood.bigTree2, .bound = 13.0, .top = 8.5, .view = FAR, .parts = &.{
        .{ .r = 0.95, .h = 5.0 },
        .{ .ax = -0.90, .az = -0.45, .bx = -1.20, .bz = -0.50, .r = 0.20, .h = 1.3 },
        .{ .ax = -0.32, .az = -0.90, .bx = -0.32, .bz = -1.20, .r = 0.18, .h = 1.3 },
        .{ .ax = 0.48, .az = -0.90, .bx = 0.48, .bz = -1.10, .r = 0.18, .h = 1.3 },
        .{ .ax = 0.90, .az = 0.12, .bx = 1.20, .bz = 0.12, .r = 0.20, .h = 1.3 },
        .{ .ax = -0.90, .az = 0.18, .bx = -1.20, .bz = 0.18, .r = 0.20, .h = 1.3 },
        .{ .ax = -0.12, .az = 0.90, .bx = -0.12, .bz = 1.20, .r = 0.18, .h = 1.3 },
        .{ .ax = 0.65, .az = 0.75, .bx = 0.68, .bz = 1.00, .r = 0.16, .h = 1.3 },
    }, .occl = &.{ .{ .r = 1.30, .y1 = 3.4 }, .{ .r = 5.40, .y0 = 3.2, .y1 = 8.5 } }, .surf = .wood },
    .{ .kind = .bigtree3, .build = wood.bigTree3, .bound = 14.0, .top = 13.5, .view = FAR, .parts = &.{
        .{ .r = 0.90, .h = 6.5 },
        .{ .ax = -0.80, .az = -0.70, .bx = -1.15, .bz = -1.00, .r = 0.20, .h = 1.3 },
        .{ .ax = -0.40, .az = -0.90, .bx = -0.40, .bz = -1.15, .r = 0.18, .h = 1.3 },
        .{ .ax = 0.45, .az = -0.85, .bx = 0.45, .bz = -1.00, .r = 0.18, .h = 1.3 },
        .{ .ax = 0.90, .az = -0.05, .bx = 1.20, .bz = -0.05, .r = 0.20, .h = 1.3 },
        .{ .ax = -0.90, .az = 0.40, .bx = -1.15, .bz = 0.45, .r = 0.20, .h = 1.3 },
        .{ .ax = -0.42, .az = 0.90, .bx = -0.42, .bz = 1.15, .r = 0.18, .h = 1.3 },
        .{ .ax = 0.62, .az = 0.90, .bx = 0.62, .bz = 1.00, .r = 0.16, .h = 1.3 },
    }, .occl = &.{ .{ .r = 1.25, .y1 = 5.6 }, .{ .r = 3.60, .y0 = 5.4, .y1 = 13.5 } }, .surf = .wood },
    // The curtain HANGS: `willowMesh` drops its fronds to y 0.9 at a reach of 3.2, so the blocking mass starts near the ground and the bole inside it is beside the point.
    .{ .kind = .willow, .build = wood.willowMesh, .bound = 8.0, .top = 7.1, .view = 300, .parts = circleParts(0.72, 4.4), .occl = &.{ .{ .r = 0.90, .y1 = 3.4 }, .{ .r = 3.60, .y0 = 0.9, .y1 = 5.5 } }, .surf = .wood },
    // A CONE, in three steps: `coniferMesh` whorls from y 0.16H with `reach` 3.1 falling to a spire.
    .{ .kind = .conifer, .build = wood.coniferMesh, .bound = 12.5, .top = 12.0, .view = FAR, .parts = circleParts(0.58, 5.0), .occl = &.{ .{ .r = 0.70, .y1 = 1.6 }, .{ .r = 3.40, .y0 = 1.4, .y1 = 5.0 }, .{ .r = 1.80, .y0 = 5.0, .y1 = 9.0 } }, .surf = .wood },
    .{ .kind = .birch, .build = wood.birchMesh, .bound = 10.0, .top = 9.4, .view = 340, .parts = circleParts(0.44, 5.0), .occl = &.{ .{ .r = 0.55, .y1 = 3.9 }, .{ .r = 3.00, .y0 = 3.5, .y1 = 9.4 } }, .surf = .wood },
    .{ .kind = .snag, .build = wood.snagMesh, .bound = 8.2, .top = 7.8, .view = 320, .parts = &.{
        .{ .ax = -0.02, .az = -0.02, .bx = -0.02, .bz = -0.02, .r = 0.60, .h = 6.0 },
        .{ .ax = 0.55, .az = 0.10, .bx = 0.85, .bz = 0.15, .r = 0.12, .h = 0.8 },
        .{ .ax = -0.85, .az = -0.42, .bx = -0.55, .bz = -0.35, .r = 0.12, .h = 0.8 },
    }, .occl = &.{.{ .r = 0.75, .y1 = 7.0 }}, .surf = .wood },
    // A sapling CASTS (3 m of tree with no shadow reads as a decal) and so must not sway — the depth pass has no wind term.
    .{ .kind = .sapling, .build = wood.saplingMesh, .bound = 3.8, .top = 3.4, .view = 220, .parts = circleParts(0.16, 2.2), .surf = .wood },
    // `bound` and `top` are SOLVED off `propbone.ribPath` at comptime — the same walk the mesh is drawn from, so a retuned curl moves the sphere with the shaft. Typed by hand, the arch's keystone stood 0.29 m above the `top` it declared.
    .{ .kind = .rib, .build = bone.rib1, .bound = bone.ribBound(bone.RIB_TALL), .top = bone.ribTop(bone.RIB_TALL), .view = FAR, .parts = circleParts(0.62, 3.0), .occl = &.{ .{ .r = 0.90, .y1 = 4.0 }, .{ .x = 3.0, .r = 2.60, .y0 = 3.8, .y1 = bone.ribTop(bone.RIB_TALL) } } },
    .{ .kind = .rib2, .build = bone.rib2, .bound = bone.ribBound(bone.RIB_STOUT), .top = bone.ribTop(bone.RIB_STOUT), .view = FAR, .parts = circleParts(0.70, 2.6), .occl = &.{ .{ .r = 1.00, .y1 = 2.8 }, .{ .x = 2.6, .r = 2.20, .y0 = 2.6, .y1 = bone.ribTop(bone.RIB_STOUT) } } },
    .{ .kind = .rib3, .build = bone.rib3, .bound = bone.ribBound(bone.RIB_SPLIT), .top = bone.ribTop(bone.RIB_SPLIT), .view = FAR, .parts = circleParts(0.55, 3.2), .occl = &.{ .{ .r = 0.85, .y1 = 4.0 }, .{ .x = 1.6, .r = 1.60, .y0 = 3.8, .y1 = bone.ribTop(bone.RIB_SPLIT) } } },
    .{ .kind = .ribarch, .build = bone.ribArchMesh, .bound = bone.archBound(), .top = bone.archTop(), .view = FAR, .parts = &.{
        .{ .ax = -bone.ARCH_HALF, .bx = -bone.ARCH_HALF, .r = 0.75, .h = 2.6 },
        .{ .ax = bone.ARCH_HALF, .bx = bone.ARCH_HALF, .r = 0.75, .h = 2.6 },
    }, .occl = &.{ .{ .x = -bone.ARCH_HALF, .r = 1.10, .y1 = 4.2 }, .{ .x = bone.ARCH_HALF, .r = 1.10, .y1 = 4.2 } } },
    // The cranium, and the jaw lying off it to +z.
    .{ .kind = .skull, .build = bone.skullMesh, .bound = 3.9, .top = 2.3, .view = 300, .parts = &.{
        .{ .ax = -0.45, .az = -0.25, .bx = 0.55, .bz = -0.25, .r = 1.32, .h = 1.95 },
        .{ .ax = -1.50, .az = 1.30, .bx = 0.30, .bz = 1.30, .r = 0.32, .h = 1.2, .flat = true },
    } },
    .{ .kind = .vertebra, .build = bone.vertebraMesh, .bound = 2.9, .top = 2.5, .view = 220, .parts = &.{.{ .ax = 0.05, .bx = 0.05, .r = 0.88, .h = 1.60 }} },

    // A heap is walked OVER and a dune is walked ROUND — and the dune's collider is only 1.4 m tall against its own 2.2, so a look passes over the ridge a body cannot cross. That gap is the region's one idea.
    // THE DUNE RUNS ALONG Z; its collider ran along x for a long while.
    .{ .kind = .ashheap, .build = ash.ashHeapMesh, .bound = 2.0, .top = 0.80, .view = 150 },
    .{ .kind = .ashdune, .build = ash.ashDuneMesh, .bound = 5.8, .top = 2.20, .view = 250, .parts = &.{.{ .ax = -0.15, .az = -2.40, .bx = -0.15, .bz = 2.40, .r = 1.20, .h = 1.40 }} },
    .{ .kind = .cinders, .build = ash.cindersMesh, .bound = 1.6, .top = 0.25, .view = 130, .casts = false },
    .{ .kind = .charspar, .build = ash.charSparMesh, .bound = 5.9, .top = 5.50, .view = 300, .parts = &.{
        .{ .r = 0.44, .h = 4.0 },
        .{ .ax = 0.30, .az = -0.10, .bx = 0.80, .bz = -0.50, .r = 0.20, .h = 4.0 },
    }, .occl = &.{.{ .r = 0.70, .y1 = 5.4 }}, .surf = .wood },

    .{ .kind = .hoodoo, .build = rock.hoodooMesh, .bound = 6.4, .top = 5.90, .view = FAR, .parts = &.{.{ .ax = 0.03, .bx = 0.03, .r = 0.85, .h = 4.6 }}, .occl = &.{ .{ .r = 0.90, .y1 = 3.5 }, .{ .r = 1.45, .y0 = 3.4, .y1 = 5.8 } } },
    // The spire and the four boulders shed around its foot.
    .{ .kind = .spire, .build = rock.spireMesh, .bound = 10.2, .top = 9.40, .view = FAR, .parts = &.{
        .{ .az = 0.02, .bz = 0.02, .r = 1.22, .h = 7.0 },
        .{ .ax = 2.15, .az = -0.30, .bx = 2.15, .bz = -0.30, .r = 0.45, .h = 0.8 },
        .{ .ax = 1.20, .az = -1.35, .bx = 1.20, .bz = -1.35, .r = 0.40, .h = 0.8 },
        .{ .ax = 1.50, .az = 1.45, .bx = 1.50, .bz = 1.45, .r = 0.35, .h = 0.8 },
        .{ .ax = 0.85, .az = 0.70, .bx = 0.85, .bz = 0.70, .r = 0.25, .h = 0.7 },
    }, .occl = &.{.{ .r = 1.40, .y1 = 9.3 }} },
    .{ .kind = .balanced, .build = rock.balancedMesh, .bound = 4.6, .top = 4.10, .view = 320, .parts = &.{.{ .ax = 0.0, .bx = 0.62, .r = 1.10, .h = 2.30 }}, .occl = &.{.{ .x = 0.5, .r = 1.70, .y1 = 4.0 }} },
    .{ .kind = .fingers, .build = rock.fingersMesh, .bound = 5.6, .top = 4.80, .view = 320, .parts = &.{.{ .ax = -0.70, .az = -0.10, .bx = 2.60, .bz = -0.10, .r = 0.60, .h = 3.80 }}, .occl = &.{.{ .x = 0.4, .r = 1.90, .y1 = 4.7 }} },

    // A 2.1 m square plinth, and a fallen piece to its east.
    .{ .kind = .obelisk, .build = ruins.obeliskMesh, .bound = 9.2, .top = 8.70, .view = FAR, .parts = &.{
        .{ .ax = 0.06, .az = 0.01, .bx = 0.06, .bz = 0.01, .r = 1.04, .h = 7.0, .flat = true },
        .{ .ax = 2.35, .az = -0.80, .bx = 2.35, .bz = -0.80, .r = 0.35, .h = 0.7 },
    } },
    .{ .kind = .plinth, .build = ruins.plinthMesh, .bound = 2.8, .top = 2.60, .view = 210, .parts = &.{.{ .ax = -0.15, .az = -0.02, .bx = 0.17, .bz = -0.02, .r = 0.70, .h = 1.70, .flat = true }} },
    .{ .kind = .altar, .build = ruins.altarMesh, .bound = 2.9, .top = ruins.ALTAR_H, .view = 210, .parts = &.{.{ .ax = -0.70, .az = 0.02, .bx = 0.61, .bz = 0.02, .r = 0.63, .h = 1.05, .flat = true }} },

    .{ .kind = .rotlog, .build = wood.rotLogMesh, .bound = 3.2, .top = 0.95, .view = 175, .parts = &.{.{ .ax = -2.10, .bx = 2.10, .r = 0.40, .h = 0.85 }}, .surf = .wood },
    // The root mass, the trunk running to +x+z, and the limbs it threw.
    .{ .kind = .deadfall, .build = wood.deadfallMesh, .bound = 3.4, .top = 2.00, .view = 200, .parts = &.{
        .{ .ax = -0.55, .az = -0.35, .bx = -0.55, .bz = -0.35, .r = 1.05, .h = 1.6 },
        .{ .ax = 0.50, .az = 0.50, .bx = 1.30, .bz = 1.25, .r = 0.30, .h = 1.2 },
        .{ .ax = -1.85, .az = 0.0, .bx = -1.20, .bz = 0.0, .r = 0.18, .h = 1.2 },
        .{ .ax = -1.40, .az = -1.40, .bx = -0.90, .bz = -0.90, .r = 0.20, .h = 1.2 },
        .{ .ax = 0.90, .az = -0.60, .bx = 1.30, .bz = -0.90, .r = 0.20, .h = 1.2 },
    }, .surf = .wood },

    .{ .kind = .capgiant, .build = fungus.capGiantMesh, .bound = fungus.capBound(fungus.GIANT_BROAD), .top = fungus.capTop(fungus.GIANT_BROAD), .view = FAR, .parts = &fungus.capParts(fungus.GIANT_BROAD), .occl = &fungus.capOccl(fungus.GIANT_BROAD), .surf = .wood },
    .{ .kind = .capgiant2, .build = fungus.capGiant2Mesh, .bound = fungus.capBound(fungus.GIANT_TALL), .top = fungus.capTop(fungus.GIANT_TALL), .view = FAR, .parts = &fungus.capParts(fungus.GIANT_TALL), .occl = &fungus.capOccl(fungus.GIANT_TALL), .surf = .wood },
    .{ .kind = .capgiant3, .build = fungus.capGiant3Mesh, .bound = fungus.capBound(fungus.GIANT_TABLE), .top = fungus.capTop(fungus.GIANT_TABLE), .view = FAR, .parts = &fungus.capParts(fungus.GIANT_TABLE), .occl = &fungus.capOccl(fungus.GIANT_TABLE), .surf = .wood },
    .{ .kind = .capcolossal, .build = fungus.capColossalMesh, .bound = fungus.capBound(fungus.GIANT_COLOSSAL), .top = fungus.capTop(fungus.GIANT_COLOSSAL), .view = FAR, .parts = &fungus.capParts(fungus.GIANT_COLOSSAL), .occl = &fungus.capOccl(fungus.GIANT_COLOSSAL), .surf = .wood },
    .{ .kind = .captower, .build = fungus.capTowerMesh, .bound = 10.2, .top = 9.90, .view = FAR, .parts = circleParts(0.86, 8.4), .occl = &.{ .{ .r = 2.10, .y1 = 4.2 }, .{ .r = 1.30, .y0 = 4.0, .y1 = 9.8 } }, .surf = .wood },
    .{ .kind = .hyphaarch, .build = fungus.hyphaArchMesh, .bound = 6.6, .top = 5.90, .view = 340, .parts = &.{
        .{ .ax = -fungus.ARCH_SPAN * 0.5, .bx = -fungus.ARCH_SPAN * 0.5, .r = 0.60, .h = 2.40 },
        .{ .ax = fungus.ARCH_SPAN * 0.5, .bx = fungus.ARCH_SPAN * 0.5, .r = 0.60, .h = 2.40 },
    }, .occl = &.{ .{ .x = -fungus.ARCH_SPAN * 0.5, .r = 0.90, .y1 = 4.4 }, .{ .x = fungus.ARCH_SPAN * 0.5, .r = 0.90, .y1 = 4.4 } }, .surf = .wood },
    .{ .kind = .glowcluster, .build = fungus.glowClusterMesh, .bound = 2.0, .top = 1.80, .view = 220, .parts = circleParts(0.55, 1.10), .light = .{ .y = fungus.CLUSTER_LIGHT_Y, .col = v3(0.62, 0.26, 0.46), .radius = 6.5, .flicker = 0.04 }, .surf = .wood },
    .{ .kind = .lampstalk, .build = fungus.lampStalkMesh, .bound = 4.6, .top = 4.20, .view = 300, .parts = circleParts(0.26, 2.60), .light = .{ .y = fungus.LAMP_LIGHT_Y, .col = v3(0.70, 0.32, 0.52), .radius = 10.0, .flicker = 0.03 }, .surf = .wood },
    // No collider: a fold is ankle-high and you walk over it. It still casts, because a 1.4 m mass that lays no shadow reads as a decal.
    .{ .kind = .fleshfold, .build = fungus.fleshFoldMesh, .bound = 2.6, .top = 1.40, .view = 180 },
    .{ .kind = .sporevent, .build = fungus.sporeVentMesh, .bound = 4.0, .top = 3.70, .view = 260, .parts = circleParts(1.05, 3.40), .light = .{ .y = fungus.VENT_H - 0.40, .col = v3(0.46, 0.20, 0.36), .radius = 5.0, .flicker = 0.09 }, .surf = .wood },
    .{ .kind = .glowvein, .build = fungus.glowVeinMesh, .bound = 2.3, .top = 0.12, .view = 120, .flora = true, .casts = false },
    .{ .kind = .tubecoral, .build = coral.tubeCoralMesh, .bound = coral.TUBE_H + 0.30, .top = coral.TUBE_H + 0.10, .view = 240, .parts = circleParts(0.62, coral.TUBE_H * 0.9), .surf = .wood },
    .{ .kind = .tubespire, .build = coral.tubeSpireMesh, .bound = coral.SPIRE_H + 0.40, .top = coral.SPIRE_H + 0.20, .view = FAR, .parts = circleParts(0.80, coral.SPIRE_H * 0.94), .occl = &.{.{ .r = 1.10, .y1 = coral.SPIRE_H }}, .light = .{ .y = coral.SPIRE_LIGHT_Y, .col = v3(0.66, 0.30, 0.48), .radius = 9.0, .flicker = 0.05 }, .surf = .wood },
    .{ .kind = .fancoral, .build = coral.fanCoralMesh, .bound = coral.FAN_H + 0.40, .top = coral.FAN_H + 0.20, .view = 300, .parts = circleParts(0.34, 0.60), .surf = .wood },
    .{ .kind = .antlercoral, .build = coral.antlerCoralMesh, .bound = coral.ANTLER_H + 0.50, .top = coral.ANTLER_H + 0.30, .view = 260, .parts = circleParts(0.40, 0.90), .surf = .wood },
    .{ .kind = .floatsac, .build = coral.floatSacMesh, .bound = coral.FLOAT_Y + coral.FLOAT_R * 1.6, .top = coral.FLOAT_Y + coral.FLOAT_R * 1.3, .view = 320, .parts = circleParts(0.18, 0.30), .light = .{ .y = coral.FLOAT_LIGHT_Y, .col = v3(0.60, 0.28, 0.44), .radius = 8.0, .flicker = 0.06 }, .surf = .wood },
    .{ .kind = .floatshoal, .build = coral.floatShoalMesh, .bound = coral.SHOAL_TOP + 0.90, .top = coral.SHOAL_TOP + 0.60, .view = FAR, .parts = circleParts(0.30, 0.30), .light = .{ .y = coral.SHOAL_TOP * 0.72, .col = v3(0.58, 0.28, 0.46), .radius = 10.0, .flicker = 0.05 }, .surf = .wood },
    .{ .kind = .hangcurtain, .build = coral.hangCurtainMesh, .bound = coral.HANG_H + 0.60, .top = coral.HANG_H + 0.30, .view = 340, .parts = &.{.{ .ax = -coral.HANG_SPAN * 0.5, .az = 0, .bx = -coral.HANG_SPAN * 0.5, .bz = 0, .r = 0.34, .h = 1.30 }}, .light = .{ .y = coral.HANG_LIGHT_Y, .col = v3(0.62, 0.30, 0.50), .radius = 7.5, .flicker = 0.07 }, .surf = .wood },
    .{ .kind = .puffballs, .build = fungus.puffballsMesh, .bound = fungus.PUFF_R * 1.2, .top = 0.62, .view = 150, .parts = circleParts(0.30, 0.30), .surf = .wood },
    .{ .kind = .deadfingers, .build = fungus.deadFingersMesh, .bound = 0.62, .top = fungus.FINGER_H + 0.08, .view = 130 },
    .{ .kind = .crustfungus, .build = fungus.crustFungusMesh, .bound = fungus.CRUST_R * 1.1, .top = 0.12, .view = 140, .flora = true, .casts = false },
    .{ .kind = .shelfstack, .build = fungus.shelfStackMesh, .bound = fungus.SHELF_H + 0.20, .top = fungus.SHELF_H + 0.10, .view = 200, .parts = circleParts(0.20, 1.05), .surf = .wood },
    .{ .kind = .brainknot, .build = coral.brainKnotMesh, .bound = coral.BRAIN_R * 1.15, .top = coral.BRAIN_H + 0.06, .view = 170, .parts = circleParts(0.82, coral.BRAIN_H), .surf = .wood },
    .{ .kind = .pipeclutch, .build = coral.pipeClutchMesh, .bound = coral.CLUTCH_H + 0.20, .top = coral.CLUTCH_H + 0.10, .view = 160, .parts = circleParts(0.46, coral.CLUTCH_H * 0.8), .surf = .wood },
    .{ .kind = .coralcrust, .build = coral.coralCrustMesh, .bound = coral.CCRUST_R * 1.1, .top = 0.36, .view = 150, .flora = true, .casts = false },
    .{ .kind = .shards, .build = rock.shardsMesh, .bound = rock.SHARD_H + 0.35, .top = rock.SHARD_H + 0.06, .view = 170, .surf = .stone },
    .{ .kind = .slabs, .build = rock.slabsMesh, .bound = 1.35, .top = 0.32, .view = 160, .surf = .stone },
    .{ .kind = .cobbles, .build = rock.cobblesMesh, .bound = 1.30, .top = 0.24, .view = 140, .surf = .stone, .casts = false },
    .{ .kind = .whaleback, .build = rock.whalebackMesh, .bound = 2.45, .top = rock.WHALE_H + 0.10, .view = 240, .parts = &.{.{ .az = -1.20, .bz = 1.20, .r = 0.75, .h = rock.WHALE_H }}, .surf = .stone },
    .{ .kind = .capcluster, .build = fungus.capClusterMesh, .bound = 3.4, .top = 2.80, .view = 230, .parts = circleParts(0.75, 1.80), .occl = &.{.{ .r = 1.20, .y1 = 2.7 }}, .surf = .wood },
    .{ .kind = .bracket, .build = fungus.bracketMesh, .bound = 2.6, .top = 2.50, .view = 200, .parts = circleParts(0.45, 2.20), .surf = .wood },
    .{ .kind = .glowcap, .build = fungus.glowCapMesh, .bound = 3.0, .top = 2.90, .view = 260, .parts = circleParts(0.22, 2.00), .light = .{ .y = fungus.GLOW_LIGHT_Y, .col = v3(0.26, 0.62, 0.58), .radius = 7.5, .flicker = 0.05 }, .surf = .wood },
    .{ .kind = .sporepod, .build = fungus.sporePodMesh, .bound = 1.3, .top = 1.25, .view = 95, .flora = true, .casts = false },

    // Square piers, 1.3 m a side.
    .{ .kind = .giltarch, .build = gold.giltArchMesh, .bound = gold.ARCH_TOP + 0.6, .top = gold.ARCH_TOP, .view = FAR, .parts = &.{
        .{ .ax = -gold.ARCH_HALF, .az = -0.03, .bx = -gold.ARCH_HALF, .bz = -0.03, .r = 0.64, .h = gold.ARCH_SPRING, .flat = true },
        .{ .ax = gold.ARCH_HALF, .az = -0.03, .bx = gold.ARCH_HALF, .bz = -0.03, .r = 0.64, .h = gold.ARCH_SPRING, .flat = true },
    } },
    .{ .kind = .muqarnas, .build = gold.muqarnasBlockMesh, .bound = gold.MUQ_TOP + 0.9, .top = gold.MUQ_TOP, .view = 230, .parts = &.{.{ .ax = -0.12, .az = -0.30, .bx = 0.02, .bz = -0.30, .r = 0.83, .h = gold.MUQ_WALL, .flat = true }} },
    // A DRUM YOU WALK INTO: the wall is a ring 2.5..3.2 m out with a door at either end of z, so the collider is the ring, not the disc that sealed it.
    .{ .kind = .giltdome, .build = gold.giltDomeMesh, .bound = gold.DOME_R * 2.2, .top = gold.DOME_TOP, .view = FAR, .solid = true, .parts = &DOME_RING },
    // The square plinth is over the step, so it is the collider; the shaft stands inside it.
    .{ .kind = .minaret, .build = gold.minaretMesh, .bound = gold.MIN_TOP + 0.8, .top = gold.MIN_TOP, .view = FAR, .solid = true, .parts = &.{.{ .ax = -0.08, .az = 0.02, .bx = -0.08, .bz = 0.02, .r = 1.40, .h = gold.MIN_H * 0.92, .flat = true }} },
    .{ .kind = .jali, .build = gold.jaliScreenMesh, .bound = gold.JALI_W + 1.0, .top = gold.JALI_TOP, .view = 300, .solid = true, .parts = &.{
        .{ .ax = -gold.JALI_W * 0.5, .az = 0.05, .bx = gold.JALI_W * 0.5, .bz = 0.05, .r = 0.34, .h = gold.JALI_H, .flat = true },
        .{ .ax = -2.05, .az = 0.55, .bx = -2.05, .bz = 0.55, .r = 0.25, .h = gold.JALI_H, .flat = true },
        .{ .ax = 2.05, .az = 0.55, .bx = 2.05, .bz = 0.55, .r = 0.25, .h = gold.JALI_H, .flat = true },
    } },
    .{ .kind = .giltcolumn, .build = gold.giltColumnMesh, .bound = gold.COL_TOP + 0.5, .top = gold.COL_TOP, .view = 320, .parts = circleParts(0.52, gold.COL_H) },
    .{ .kind = .giltbasin, .build = gold.giltBasinMesh, .bound = gold.BASIN_R * 2.3, .top = gold.BASIN_TOP, .view = 200, .parts = circleParts(1.45, 0.90) },
    .{ .kind = .giltfinial, .build = gold.giltFinialMesh, .bound = 1.7, .top = gold.FINIAL_TOP, .view = 150 },
    .{ .kind = .giltleaf, .build = gold.giltLeafMesh, .bound = gold.LEAF_R * 1.25, .top = gold.LEAF_TOP, .view = 160 },
    .{ .kind = .marblefloor, .build = gold.marbleFloorMesh, .bound = gold.FLOOR_R * 1.45, .top = 0.10, .view = 200, .casts = false },
    .{ .kind = .marbleslab, .build = gold.marbleSlabMesh, .bound = 2.4, .top = gold.SLAB_TOP, .view = 190, .parts = &.{.{ .ax = -0.95, .bx = 1.00, .r = 0.52, .h = 0.90 }} },
    // Not a flight: the whole run z -2.9..0.4 is walked round.
    .{ .kind = .marblestair, .build = gold.marbleStairMesh, .bound = 3.6, .top = gold.STAIR_TOP + 0.10, .view = 260, .parts = &.{.{ .ax = 0.05, .az = -1.75, .bx = 0.05, .bz = -0.75, .r = 1.15, .h = gold.STAIR_TOP, .flat = true }} },

    .{ .kind = .ashcrag, .build = ash.ashCragMesh, .bound = ash.CRAG_TOP + 0.7, .top = ash.CRAG_TOP, .view = FAR, .parts = &.{.{ .ax = -0.75, .az = 0.10, .bx = 0.35, .bz = 0.10, .r = 1.55, .h = ash.CRAG_TOP * 0.86 }}, .occl = &.{.{ .r = 1.40, .y1 = ash.CRAG_TOP }} },
    .{ .kind = .stalagmite, .build = ash.stalagmiteMesh, .bound = ash.STAL_TOP + 0.40, .top = ash.STAL_TOP, .view = 200 },
    // The stone, and the mound heaped against its west side.
    .{ .kind = .menhir, .build = ash.menhirMesh, .bound = ash.MENHIR_TOP + 0.6, .top = ash.MENHIR_TOP, .view = FAR, .parts = &.{
        .{ .ax = -0.05, .az = -0.20, .bx = -0.05, .bz = -0.20, .r = 0.82, .h = ash.MENHIR_TOP * 0.90 },
        .{ .ax = -1.05, .bx = -1.05, .r = 0.40, .h = 0.8 },
    }, .occl = &.{.{ .r = 0.90, .y1 = ash.MENHIR_TOP }} },
    .{ .kind = .stonecarve, .build = ash.stoneCarveMesh, .bound = ash.CARVE_R * 1.6, .top = ash.CARVE_TOP, .view = 230, .parts = &.{.{ .ax = -0.30, .az = -0.05, .bx = 0.50, .bz = -0.05, .r = 0.95, .h = ash.CARVE_TOP * 0.88 }} },

    // A counter across the back and four posts; the sides are open. The old three walls stood on the wrong side of the stall.
    .{ .kind = .merchanthut, .build = market.merchantHutMesh, .bound = market.HUT_TOP + 0.6, .top = market.HUT_TOP, .view = FAR, .solid = true, .parts = &.{
        .{ .ax = -market.HUT_W * 0.53, .bx = market.HUT_W * 0.53, .az = -market.HUT_D * 0.5 + 0.10, .bz = -market.HUT_D * 0.5 + 0.10, .r = 0.22, .h = 1.00, .flat = true },
        .{ .ax = -market.HUT_W * 0.5, .bx = -market.HUT_W * 0.5, .az = -market.HUT_D * 0.5, .bz = -market.HUT_D * 0.5, .r = 0.10, .h = market.HUT_TOP },
        .{ .ax = market.HUT_W * 0.5, .bx = market.HUT_W * 0.5, .az = -market.HUT_D * 0.5, .bz = -market.HUT_D * 0.5, .r = 0.10, .h = market.HUT_TOP },
        .{ .ax = -market.HUT_W * 0.5, .bx = -market.HUT_W * 0.5, .az = market.HUT_D * 0.5, .bz = market.HUT_D * 0.5, .r = 0.10, .h = market.HUT_TOP },
        .{ .ax = market.HUT_W * 0.5, .bx = market.HUT_W * 0.5, .az = market.HUT_D * 0.5, .bz = market.HUT_D * 0.5, .r = 0.10, .h = market.HUT_TOP },
    } },
    .{ .kind = .packstack, .build = market.packStackMesh, .bound = market.PACK_R * 1.9, .top = market.PACK_TOP, .view = 220, .parts = circleParts(0.46, market.PACK_TOP * 0.88) },
    .{ .kind = .trestletable, .build = market.trestleTableMesh, .bound = market.TABLE_W * 1.15, .top = market.TABLE_TOP + 0.22, .view = 230, .parts = &.{.{ .ax = -market.TABLE_W * 0.42, .bx = market.TABLE_W * 0.42, .r = 0.40, .h = market.TABLE_TOP }} },
    .{ .kind = .goodsrack, .build = market.goodsRackMesh, .bound = market.RACK_TOP + 0.5, .top = market.RACK_TOP, .view = 320, .parts = &.{
        .{ .ax = -market.RACK_W * 0.5, .bx = -market.RACK_W * 0.5, .r = 0.42, .h = 1.60 },
        .{ .ax = market.RACK_W * 0.5, .bx = market.RACK_W * 0.5, .r = 0.42, .h = 1.60 },
    } },
    .{ .kind = .awning, .build = market.awningMesh, .bound = market.AWNING_TOP + 0.5, .top = market.AWNING_TOP, .view = 300, .parts = &.{
        .{ .ax = -market.AWNING_HW, .bx = -market.AWNING_HW, .az = -market.AWNING_HD, .bz = market.AWNING_HD, .r = 0.13, .h = 2.30 },
        .{ .ax = market.AWNING_HW, .bx = market.AWNING_HW, .az = -market.AWNING_HD, .bz = market.AWNING_HD, .r = 0.13, .h = 2.30 },
    } },
    .{ .kind = .rugpile, .build = market.rugPileMesh, .bound = market.RUGS_R * 1.6, .top = market.RUGS_TOP, .view = 180, .parts = circleParts(0.58, market.RUGS_TOP * 0.9) },
    // The post and the two feet of the scale beside it.
    .{ .kind = .scalepost, .build = market.scalePostMesh, .bound = market.SCALE_TOP + 0.5, .top = market.SCALE_TOP, .view = 280, .parts = &.{
        .{ .ax = 0.02, .az = 0.22, .bx = 0.02, .bz = 0.22, .r = 0.14, .h = market.SCALE_TOP * 0.82 },
        .{ .ax = -0.47, .az = 0.62, .bx = -0.47, .bz = 0.62, .r = 0.12, .h = 1.2 },
        .{ .ax = 0.37, .az = 0.62, .bx = 0.37, .bz = 0.62, .r = 0.12, .h = 1.2 },
    } },
    .{ .kind = .waterjars, .build = market.waterJarsMesh, .bound = market.JARS_R * 1.7, .top = market.JARS_TOP, .view = 200, .parts = &.{
        .{ .r = 0.52, .h = market.JARS_TOP * 0.85 },
        .{ .ax = 0.80, .az = 0.35, .bx = 0.80, .bz = 0.35, .r = 0.22, .h = 0.9 },
    } },
    .{ .kind = .hitchrail, .build = market.hitchRailMesh, .bound = market.HITCH_R * 1.5, .top = market.HITCH_TOP, .view = 260, .parts = &.{.{ .ax = -1.30, .bx = 1.30, .r = 0.16, .h = market.HITCH_TOP * 0.92 }} },

    .{ .kind = .pickup, .build = fx.pickupMesh, .bound = 1.9, .top = fx.PICKUP_TOP, .view = 190, .interact = true, .casts = false, .light = .{ .y = 0.30, .col = v3(0.86, 0.82, 0.58), .radius = 5.4, .flicker = 0.03 } },
    .{ .kind = .foggate, .build = fx.fogGateStoneMesh, .veil = fx.fogGateMesh, .bound = 5.4, .top = fx.FOG_H, .view = 320, .solid = true, .interact = true, .casts = false, .ward = true, .parts = &.{.{ .ax = -fx.FOG_W * 0.5, .bx = fx.FOG_W * 0.5, .r = fx.FOG_WARD_R, .h = fx.FOG_H }} },
    .{ .kind = .ladder, .build = build.ladderMesh, .bound = build.LADDER_SEG + 0.2, .top = build.LADDER_SEG, .view = 210, .stack = build.LADDER_SEG, .climb = true, .surf = .wood },
    .{ .kind = .anvil, .build = forge.anvilMesh, .bound = forge.ANVIL_R + 0.3, .top = forge.ANVIL_TOP, .view = 190, .parts = circleParts(forge.STUMP_R + 0.01, forge.ANVIL_TOP), .surf = .stone },
    .{ .kind = .forge, .build = forge.forgeMesh, .bound = forge.FORGE_R + 1.3, .top = forge.FORGE_TOP, .view = 300, .solid = true, .parts = &.{
        .{ .ax = -0.50, .az = -0.20, .bx = 0.45, .bz = -0.20, .r = 0.48, .h = 1.10, .flat = true },
    }, .light = .{ .y = forge.FORGE_LIGHT_Y, .col = v3(1.0, 0.52, 0.18), .radius = forge.FORGE_LIGHT_R, .flicker = 0.16 } },
    .{ .kind = .quenchtrough, .build = forge.quenchMesh, .bound = forge.QUENCH_R + 0.2, .top = forge.QUENCH_TOP, .view = 170, .parts = &.{.{ .ax = -0.62, .bx = 0.62, .r = 0.30, .h = forge.QUENCH_TOP }}, .surf = .wood },
    .{ .kind = .toolrack, .build = forge.toolRackMesh, .bound = forge.RACK_TOP + 0.6, .top = forge.RACK_TOP, .view = 220, .parts = &.{.{ .ax = -forge.RACK_HW, .bx = forge.RACK_HW, .r = 0.22, .h = forge.RACK_TOP * 0.9 }}, .surf = .wood },
    .{ .kind = .stairflight, .build = build.stairMesh, .bound = build.STAIR_RUN + 0.4, .top = build.STAIR_SEG, .view = 240, .stack = build.STAIR_SEG, .flight = .{ .run = build.STAIR_RUN, .halfW = build.STAIR_HALF, .treads = build.STAIR_TREADS }, .surf = .stone },
    .{ .kind = .illusory, .build = rock.illusoryMesh, .bound = CLIFF2_BOUND, .top = CLIFF2_TOP, .view = FAR, .solid = true, .illusion = true, .parts = &cliffParts },
    .{ .kind = .emberrock, .build = ember.emberRockMesh, .bound = ember.ROCK_R * 1.9, .top = ember.ROCK_TOP + 0.15, .view = 240, .parts = circleParts(ember.ROCK_R * 0.92, ember.ROCK_TOP * 0.90), .surf = .stone },
    .{ .kind = .emberrocks, .build = ember.emberRocksMesh, .bound = 2.3, .top = 0.95, .view = 170, .surf = .stone },
    .{ .kind = .burningrock, .build = ember.burningRockMesh, .bound = 2.7, .top = ember.BURN_TOP, .view = 260, .parts = circleParts(0.95, 1.30), .light = .{ .y = ember.BURN_LIGHT_Y, .col = v3(1.05, 0.50, 0.16), .radius = 9.0, .flicker = 0.18 }, .surf = .stone },
    .{ .kind = .cindercone, .build = ember.cinderConeMesh, .bound = ember.CONE_R * 1.8, .top = ember.CONE_TOP + 0.3, .view = 320, .parts = circleParts(1.85, 2.40), .occl = &.{.{ .r = 1.50, .y1 = ember.CONE_TOP }}, .light = .{ .y = ember.CONE_LIGHT_Y, .col = v3(1.0, 0.42, 0.12), .radius = 11.0, .flicker = 0.14 }, .surf = .stone },
    .{ .kind = .firespire, .build = ember.fireSpireMesh, .bound = ember.FIRE_SPIRE_H + 1.4, .top = ember.FIRE_SPIRE_H + 1.2, .view = FAR, .parts = circleParts(1.08, 6.5), .occl = &.{.{ .r = 1.40, .y1 = ember.FIRE_SPIRE_H }}, .light = .{ .y = ember.FIRE_SPIRE_LIGHT_Y, .col = v3(1.10, 0.48, 0.14), .radius = 14.0, .flicker = 0.16 }, .surf = .stone },
    .{ .kind = .emberpillar, .build = ember.emberPillarMesh, .bound = ember.PILLAR_H + 0.7, .top = ember.PILLAR_H + 0.30, .view = FAR, .parts = circleParts(ember.PILLAR_R + 0.04, ember.PILLAR_H * 0.96), .occl = &.{.{ .r = 0.85, .y1 = ember.PILLAR_H }}, .surf = .stone },
    .{ .kind = .emberarch, .build = ember.emberArchMesh, .bound = ember.ARCH_H + 0.6, .top = ember.ARCH_H, .view = FAR, .parts = &.{
        .{ .ax = -ember.ARCH_HALF, .bx = -ember.ARCH_HALF, .r = ember.ARCH_LEG_R + 0.04, .h = ember.ARCH_H * 0.68 },
        .{ .ax = ember.ARCH_HALF, .bx = ember.ARCH_HALF, .r = ember.ARCH_LEG_R + 0.04, .h = ember.ARCH_H * 0.68 },
    }, .surf = .stone },
    .{ .kind = .basaltcolumns, .build = ember.basaltColumnsMesh, .bound = ember.COLS_H + 0.5, .top = ember.COLS_H + 0.10, .view = 300, .parts = &.{.{ .ax = -0.90, .bx = 0.90, .r = 1.25, .h = ember.COLS_H * 0.82 }}, .occl = &.{.{ .r = 1.60, .y1 = ember.COLS_H }}, .surf = .stone },
    .{ .kind = .crackedslab, .build = ember.crackedSlabMesh, .bound = ember.SLAB_R * 1.55, .top = ember.SLAB_TOP, .view = 230, .parts = &.{.{ .ax = -0.95, .bx = 0.95, .r = 0.95, .h = 0.68 }}, .surf = .stone },
    .{ .kind = .magmavein, .build = ember.magmaVeinMesh, .bound = ember.VEIN_R + 0.3, .top = 0.12, .view = 130, .flora = true, .casts = false, .surf = .stone },
    .{ .kind = .lavacrust, .build = ember.lavaCrustMesh, .bound = ember.CRUST_R + 0.4, .top = 0.18, .view = 140, .flora = true, .casts = false, .surf = .stone },
    .{ .kind = .emberbed, .build = ember.emberBedMesh, .bound = ember.BED_R + 0.4, .top = 0.22, .view = 130, .flora = true, .casts = false, .surf = .stone },
    .{ .kind = .scoria, .build = ember.scoriaMesh, .bound = ember.SCORIA_R + 0.4, .top = 0.40, .view = 150, .flora = true, .casts = false, .surf = .stone },
};

pub fn info(k: Kind) *const Info {
    return &INFO[@intFromEnum(k)];
}

pub fn upright(k: Kind) bool {
    const nfo = info(k);
    return nfo.climb or nfo.stack > 0;
}

comptime {
    @setEvalBranchQuota(20000);
    for (INFO, 0..) |row, i| std.debug.assert(@intFromEnum(row.kind) == i);
    for (INFO) |row| std.debug.assert(row.bound >= row.top);
    for (INFO) |row| std.debug.assert(!(row.flora and row.casts));
    for (INFO) |row| {
        if (row.veil != null or row.stow != null) std.debug.assert(row.solid);
        std.debug.assert(!(row.solid and row.occl.len > 0));
        if (row.ward) std.debug.assert(row.parts.len > 0);
        if (row.illusion) std.debug.assert(row.solid and row.parts.len > 0);
        for (row.occl) |bl| {
            std.debug.assert(bl.y1 > bl.y0);
            std.debug.assert(bl.y1 <= row.top + 0.001);
            std.debug.assert(@sqrt(bl.x * bl.x + bl.z * bl.z) + bl.r <= row.bound + 0.001);
        }
        for (row.decks) |d| {
            std.debug.assert(d.y <= row.top + 0.001);
            std.debug.assert(@sqrt(d.x * d.x + d.z * d.z) + d.r <= row.bound + 0.001);
        }
    }
}

test "EVERY KIND IS FILED UNDER ONE KINGDOM, and `any` is not a dustbin" {
    var seen = [_]usize{0} ** Biome.N;
    for (0..NK) |i| seen[@intFromEnum(biome(@enumFromInt(i)))] += 1;
    for (seen, 0..) |n, b| {
        if (n == 0) std.debug.print("no kind is filed under {s}\n", .{Biome.label(@enumFromInt(b))});
        try std.testing.expect(n > 0);
    }
    const anyN = seen[@intFromEnum(Biome.any)];
    try std.testing.expect(anyN * 3 < NK);
    try std.testing.expect(inBiome(.rib, .bone) and inBiome(.tuft, .bone));
    try std.testing.expect(!inBiome(.rib, .fungal) and !inBiome(.capgiant, .ruins));
    try std.testing.expect(inBiome(.obelisk, .ruins) and inBiome(.rotlog, .forest));
}

test "every kind row sits at its own index and carries a mesh builder" {
    // The comptime block asserts the index match; this pins the table's SHAPE, so a half-added kind fails as a test rather than at first draw.
    try std.testing.expectEqual(@as(usize, NK), INFO.len);
    for (INFO) |row| try std.testing.expect(row.bound > 0 and row.view > 0);
}

test "collider parts stay inside their kind's bounding sphere" {
    for (INFO) |row| {
        for (partsOf(row.kind)) |part| {
            const ra = @sqrt(part.ax * part.ax + part.az * part.az) + part.r;
            const rb = @sqrt(part.bx * part.bx + part.bz * part.bz) + part.r;
            try std.testing.expect(@max(ra, rb) <= row.bound + 0.001);
        }
    }
}

test "A CLIFF'S COLLIDERS HUG ITS OWN ROCK — fitted off the masses, measured against the mesh" {
    std.debug.print("\n", .{});
    for (rock.CLIFF_PROPS, 0..) |row, i| {
        var b = rock.cliffBuildOpt(row.seed, row.kind, true, null);
        defer b.deinit();
        const parts = rock.cliffColliders(i);
        const a = colliderAudit(b.pos.items, b.uv2.items, parts);
        const coarse = colliderAudit(b.pos.items, b.uv2.items, &cliffParts);
        std.debug.print("  cliff{d}: {d} colliders — stone past them {d:.2} m ({d:.0}% of it), collider past the stone {d:.2} m; the old pair: {d:.2} m / {d:.0}% / {d:.2} m\n", .{
            i + 1, parts.len, a.pen, 100 * a.outside, a.over, coarse.pen, 100 * coarse.outside, coarse.over,
        });
        try std.testing.expect(parts.len >= 5);
        try std.testing.expect(a.pen < 0.5);
        try std.testing.expect(a.over < 0.6);
        try std.testing.expect(a.outside < 0.08);
        try std.testing.expect(a.over < coarse.over);
    }
}

test "the watchtower's doorway is a hole on the floor and wall at deck height" {
    try std.testing.expectEqual(@as(usize, art.TOWER_SIDES), art.towerRing.len);
    const halfArc = std.math.pi * @as(f32, @floatFromInt(art.TOWER_DOOR)) / @as(f32, art.TOWER_SIDES);
    var doors: usize = 0;
    for (art.towerRing) |part| {
        const bearing = @abs(std.math.atan2(part.ax, -part.az));
        if (part.y0 == 0) {
            try std.testing.expect(bearing > halfArc);
            continue;
        }
        doors += 1;
        try std.testing.expect(bearing < halfArc);
        try std.testing.expectEqual(art.TOWER_DOOR_HEAD, part.y0);
    }
    try std.testing.expectEqual(@as(usize, art.TOWER_DOOR), doors);
    try std.testing.expect(art.TOWER_DOOR_HEAD < build.WATCH_DECK_TOP);
}

test "EVERY STOREY OF THE WATCHTOWER CARRIES ITS OWN HATCH, and no two flights share a line" {
    var floors: usize = 0;
    var holes: usize = 0;
    for (WATCH_DECKS) |d| {
        if (d.hole) holes += 1 else floors += 1;
        var matched = false;
        for (WATCH_DECKS) |o| {
            if (o.hole != d.hole and o.y == d.y) matched = true;
        }
        try std.testing.expect(matched);
    }
    try std.testing.expectEqual(build.WATCH_STOREYS.len, floors);
    try std.testing.expectEqual(build.WATCH_STOREYS.len, holes);
    for (WATCH_DECKS, 0..) |d, i| {
        if (!d.hole) continue;
        for (WATCH_DECKS[i + 1 ..]) |o| {
            if (!o.hole) continue;
            const dx = d.x - o.x;
            const dz = d.z - o.z;
            try std.testing.expect(@sqrt(dx * dx + dz * dz) > 2.0 * build.WATCH_HATCH_R);
        }
    }
    try std.testing.expect(build.WATCH_ROOF_TOP <= info(.watchtower).top);
    std.debug.print("\n  watchtower: {d} floors, {d:.2} m to the roof, shaft clear to {d:.2} m of the axis\n", .{
        floors, build.WATCH_ROOF_TOP, TOWER_CLEAR,
    });
}

test "fires carry a light above their base and inside their own bound" {
    for (INFO) |row| {
        const l = row.light orelse continue;
        try std.testing.expect(l.y > 0 and l.y <= row.bound);
        try std.testing.expect(l.radius > 1.0);
        try std.testing.expect(l.flicker >= 0 and l.flicker < 1);
    }
}

pub const LIQUID_TONES = [gfx.LIQUID_N * 3]rl.Vector3{
    mathx.colVec(art.WATER_SHALLOW),  mathx.colVec(art.WATER_MID),  mathx.colVec(art.WATER_DEEP),
    mathx.colVec(art.OIL_SHALLOW),    mathx.colVec(art.OIL_MID),    mathx.colVec(art.OIL_DEEP),
    mathx.colVec(art.FUNGAL_SHALLOW), mathx.colVec(art.FUNGAL_MID), mathx.colVec(art.FUNGAL_DEEP),
    mathx.colVec(art.LAVA_SHALLOW),   mathx.colVec(art.LAVA_MID),   mathx.colVec(art.LAVA_DEEP),
};

/// what "too bright" is measured against. Pinned to the GLSL so the two cannot part company.
const BLOOM_GROUND = [3]f32{ 0.115 * 255.0, 0.055 * 255.0, 0.070 * 255.0 };
comptime {
    if (std.mem.indexOf(u8, @import("../gfx/shaders.zig").sceneFS, "vec3(0.115, 0.055, 0.070)") == null)
        @compileError("props: the fungal bloom's ground tone moved — BLOOM_GROUND is stale");
}

test "ONLY LAVA IS A LIGHT — no other pool may come back off the top of the screen" {
    // SOLVE IT, DO NOT GUESS IT (AGENTS.md): the fungal stew authored at 168/92/62 albedo is 255/205/172 through the chain — past the clip on red, and brighter on green and blue than lava's own crust.
    for (LIQUID_TONES[0 .. 3 * 3]) |tone| {
        for ([3]f32{ tone.x, tone.y, tone.z }) |ch| {
            try std.testing.expect(gfx.screenOf(ch * 255.0) < 250.0);
        }
    }
    const rim = LIQUID_TONES[6];
    const deep = LIQUID_TONES[8];
    var b: [3]f32 = undefined;
    for (BLOOM_GROUND, 0..) |g, i| b[i] = gfx.screenOf(g);
    std.debug.print(
        "\n  fungal pool: rim {d:.0}/{d:.0}/{d:.0}, deep {d:.0}/{d:.0}/{d:.0} on screen; the bloom it lies in is {d:.0}/{d:.0}/{d:.0}\n",
        .{
            gfx.screenOf(rim.x * 255.0),  gfx.screenOf(rim.y * 255.0),  gfx.screenOf(rim.z * 255.0),
            gfx.screenOf(deep.x * 255.0), gfx.screenOf(deep.y * 255.0), gfx.screenOf(deep.z * 255.0),
            b[0],                         b[1],                         b[2],
        },
    );
    try std.testing.expect(gfx.screenOf(rim.x * 255.0) < b[0] * 1.30);
    try std.testing.expect(gfx.screenOf(deep.x * 255.0) < b[0]);
    try std.testing.expect(rim.x > rim.y and rim.y >= rim.z);
    try std.testing.expect(rim.x > deep.x);
}
