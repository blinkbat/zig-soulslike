const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const collision = @import("../core/collision.zig");

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
        .hoodoo, .spire, .balanced, .fingers, .rotlog, .deadfall,
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
        };
    }
};

pub fn biome(k: Kind) Biome {
    return switch (k) {
        .rubble, .chest, .pickup, .water, .foggate, .ladder, .stairflight,
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

const cliffParts = [_]Part{
    .{ .ax = -5.4, .bx = 5.4, .r = 2.9, .h = 15.5 },
    .{ .ax = -2.2, .az = 2.1, .bx = 2.6, .bz = 2.4, .r = 2.2, .h = 15.5 },
};

pub const INFO = [NK]Info{
    .{ .kind = .pillar, .build = ruins.pillarWhole, .bound = 6.2, .top = 5.8, .view = 240, .parts = circleParts(0.80, 5.8) },
    .{ .kind = .broken, .build = ruins.pillarBroken, .bound = 3.6, .top = 3.3, .view = 200, .parts = circleParts(0.80, 2.9) },
    .{ .kind = .block, .build = ruins.blockMesh, .bound = 2.6, .top = 1.85, .view = 180, .solid = true, .parts = &.{.{ .ax = -0.35, .bx = 0.35, .r = 0.80, .h = 1.65 }} },
    .{ .kind = .arch, .build = ruins.archMesh, .bound = 7.9, .top = 7.2, .view = 260, .parts = &.{
        .{ .ax = -2.7, .bx = -2.7, .r = 0.78, .h = 4.8 },
        .{ .ax = 2.7, .bx = 2.7, .r = 0.78, .h = 4.8 },
    } },
    .{ .kind = .wall, .build = ruins.wallMesh, .bound = 5.0, .top = 3.6, .view = 220, .solid = true, .parts = &.{.{ .ax = -2.8, .bx = 2.8, .r = 0.60, .h = 3.0 }} },
    .{ .kind = .tree, .build = wood.treeMesh, .bound = 5.3, .top = 4.9, .view = 240, .parts = circleParts(0.38, 3.6), .occl = &.{.{ .r = 0.90, .y1 = 4.3 }}, .surf = .wood },
    .{ .kind = .graves, .build = ruins.gravesMesh, .bound = 2.3, .top = 1.05, .view = 150, .parts = circleParts(0.80, 0.9) },
    .{ .kind = .sword, .build = ruins.swordMesh, .bound = 1.6, .top = 1.35, .view = 120 },
    .{ .kind = .bonfire, .build = ruins.bonfireMesh, .veil = ruins.bonfireVeilMesh, .stow = ruins.bonfireGuitarMesh, .bound = 7.2, .top = 5.4, .view = 300, .solid = true, .light = .{ .y = 0.45, .col = v3(0.86, 0.48, 0.18), .radius = 11.0, .flicker = 0.17 } },
    .{ .kind = .tower, .build = ruins.towerMesh, .bound = 17.5, .top = 17.2, .view = FAR, .solid = true, .parts = circleParts(3.40, 14.0) },
    .{ .kind = .gate, .build = ruins.gateMesh, .bound = 19.6, .top = 16.4, .view = FAR, .solid = true, .parts = &.{
        .{ .ax = -7.5, .bx = -7.5, .r = 3.20, .h = 16.0 },
        .{ .ax = 7.5, .bx = 7.5, .r = 3.20, .h = 16.0 },
    } },
    .{ .kind = .rubble, .build = ruins.rubbleMesh, .bound = 1.4, .top = 0.4, .view = 130 },
    .{ .kind = .banner, .build = ruins.bannerMesh, .bound = 3.4, .top = 3.2, .view = 190 },
    .{ .kind = .statue, .build = ruins.statueMesh, .bound = 3.0, .top = 2.7, .view = 230, .parts = circleParts(0.90, 2.7) },
    .{ .kind = .chapel, .build = build.chapelMesh, .bound = 9.5, .top = 6.6, .view = FAR, .solid = true, .parts = &.{
        .{ .ax = -2.6, .az = -3.6, .bx = -2.6, .bz = 3.6, .r = 0.42, .h = 4.4 },
        .{ .ax = 2.6, .az = -3.6, .bx = 2.6, .bz = 3.6, .r = 0.42, .h = 4.4 },
        .{ .ax = -2.6, .az = 3.6, .bx = 2.6, .bz = 3.6, .r = 0.42, .h = 4.4 },
        .{ .ax = -2.6, .az = -3.6, .bx = -1.15, .bz = -3.6, .r = 0.42, .h = 4.4 },
        .{ .ax = 1.15, .az = -3.6, .bx = 2.6, .bz = -3.6, .r = 0.42, .h = 4.4 },
        .{ .ax = -1.5, .az = 2.9, .bx = 1.5, .bz = 2.9, .r = 0.55, .h = 1.1 },
    } },
    .{ .kind = .watchtower, .build = build.watchtowerMesh, .bound = 25.0, .top = build.WATCH_TOP, .view = FAR, .solid = true, .parts = &art.towerRing, .decks = &WATCH_DECKS },
    .{ .kind = .cottage, .build = build.cottageMesh, .bound = 5.6, .top = 4.0, .view = 280, .solid = true, .parts = &.{
        .{ .ax = -2.3, .az = -1.9, .bx = -2.3, .bz = 1.9, .r = 0.34, .h = 2.6 },
        .{ .ax = 2.3, .az = -1.9, .bx = 2.3, .bz = 1.9, .r = 0.34, .h = 2.6 },
        .{ .ax = -2.3, .az = 1.9, .bx = 2.3, .bz = 1.9, .r = 0.34, .h = 3.4 },
        .{ .ax = -2.3, .az = -1.9, .bx = -0.95, .bz = -1.9, .r = 0.34, .h = 1.2 },
    }, .surf = .wood },
    .{ .kind = .causeway, .build = build.causewayMesh, .bound = 6.5, .top = 0.5, .view = 240, .solid = true, .parts = &.{
        .{ .ax = -5.0, .az = -1.45, .bx = 5.0, .bz = -1.45, .r = 0.20, .h = 0.5 },
        .{ .ax = -5.0, .az = 1.45, .bx = 5.0, .bz = 1.45, .r = 0.20, .h = 0.5 },
    } },
    .{ .kind = .paving, .build = build.pavingMesh, .bound = 3.2, .top = 0.15, .view = 150, .solid = true },
    .{ .kind = .cart, .build = village.cartMesh, .bound = 3.4, .top = 1.7, .view = 170, .parts = &.{.{ .ax = -1.1, .bx = 1.1, .r = 0.55, .h = 1.3 }}, .surf = .wood },
    .{ .kind = .monolith, .build = rock.monolithMesh, .bound = 5.2, .top = 4.9, .view = FAR, .parts = circleParts(0.62, 4.6) },
    .{ .kind = .cliff, .build = rock.cliff1, .bound = 18.0, .top = 15.5, .view = FAR, .solid = true, .parts = &cliffParts },
    .{ .kind = .cliff2, .build = rock.cliff2, .bound = 17.0, .top = 14.0, .view = FAR, .solid = true, .parts = &cliffParts },
    .{ .kind = .cliff3, .build = rock.cliff3, .bound = 19.0, .top = 16.8, .view = FAR, .solid = true, .parts = &cliffParts },
    .{ .kind = .cliff4, .build = rock.cliff4, .bound = 17.5, .top = 14.9, .view = FAR, .solid = true, .parts = &cliffParts },
    .{ .kind = .cliff5, .build = rock.cliff5, .bound = 17.0, .top = 13.3, .view = FAR, .solid = true, .parts = &cliffParts },
    .{ .kind = .cliff6, .build = rock.cliff6, .bound = 18.0, .top = 14.5, .view = FAR, .solid = true, .parts = &cliffParts },
    .{ .kind = .boulder, .build = rock.boulderMesh, .bound = 3.2, .top = 2.5, .view = 220, .parts = circleParts(1.15, 2.3) },
    .{ .kind = .rocks, .build = rock.rocksMesh, .bound = 2.2, .top = 0.85, .view = 160 },
    .{ .kind = .stump, .build = wood.stumpMesh, .bound = 1.7, .top = 1.25, .view = 150, .parts = circleParts(0.46, 1.2), .surf = .wood },
    .{ .kind = .log, .build = wood.logMesh, .bound = 3.0, .top = 0.75, .view = 160, .parts = &.{.{ .ax = -1.9, .bx = 1.9, .r = 0.36, .h = 0.75 }}, .surf = .wood },
    .{ .kind = .well, .build = village.wellMesh, .bound = 2.6, .top = 2.4, .view = 240, .parts = circleParts(1.05, 1.15) },
    .{ .kind = .shrine, .build = village.shrineMesh, .bound = 2.8, .top = 2.5, .view = 240, .parts = circleParts(0.72, 1.9), .light = .{ .y = 1.20, .col = v3(0.56, 0.32, 0.13), .radius = 5.5, .flicker = 0.19 } },
    .{ .kind = .lantern, .build = village.lanternMesh, .bound = 3.4, .top = 3.1, .view = 230, .parts = circleParts(0.17, 3.0), .light = .{ .y = 2.62, .col = v3(1.05, 0.60, 0.25), .radius = 11.5, .flicker = 0.08 }, .surf = .metal },
    .{ .kind = .fence, .build = village.fenceMesh, .bound = 3.6, .top = 1.25, .view = 180, .parts = &.{.{ .ax = -3.0, .bx = 3.0, .r = 0.16, .h = 1.25 }}, .surf = .wood },
    .{ .kind = .barrels, .build = village.barrelsMesh, .bound = 1.8, .top = 1.35, .view = 170, .parts = circleParts(0.78, 1.2), .surf = .wood },
    .{ .kind = .woodpile, .build = village.woodpileMesh, .bound = 2.4, .top = 1.35, .view = 180, .parts = &.{.{ .ax = -1.25, .bx = 1.25, .r = 0.62, .h = 1.3 }}, .surf = .wood },
    .{ .kind = .bones, .build = village.bonesMesh, .bound = 1.6, .top = 0.55, .view = 140 },
    .{ .kind = .sarcophagus, .build = village.sarcophagusMesh, .bound = 2.4, .top = 1.05, .view = 200, .parts = &.{.{ .ax = -0.95, .bx = 0.95, .r = 0.72, .h = 1.0 }} },
    .{ .kind = .stairs, .build = village.stairsMesh, .bound = 2.8, .top = 1.5, .view = 190, .parts = &.{.{ .ax = -1.3, .bx = 1.3, .r = 0.95, .h = 1.4 }} },
    .{ .kind = .gibbet, .build = village.gibbetMesh, .bound = 4.4, .top = 4.1, .view = 220, .parts = circleParts(0.24, 4.0), .surf = .wood },
    .{ .kind = .cairn, .build = rock.cairnMesh, .bound = 1.8, .top = 1.5, .view = 180, .parts = circleParts(0.52, 1.4) },
    .{ .kind = .chest, .build = village.chestMesh, .bound = 1.6, .top = village.CHEST_TOP + 0.34, .view = 150, .solid = true, .interact = true, .parts = &.{.{ .r = 0.56, .h = village.CHEST_HINGE_Y }}, .surf = .wood },
    .{ .kind = .outcrop, .build = rock.outcropMesh, .bound = 3.4, .top = 1.1, .view = 200, .parts = &.{.{ .ax = -1.4, .bx = 1.4, .r = 1.1, .h = 1.05 }} },
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
    .{ .kind = .bigtree, .build = wood.bigTree1, .bound = 13.5, .top = 11.0, .view = FAR, .parts = circleParts(0.95, 6.0), .occl = &.{ .{ .r = 1.30, .y1 = 5.0 }, .{ .r = 4.80, .y0 = 4.5, .y1 = 11.0 } }, .surf = .wood },
    .{ .kind = .bigtree2, .build = wood.bigTree2, .bound = 13.0, .top = 8.5, .view = FAR, .parts = circleParts(0.95, 5.0), .occl = &.{ .{ .r = 1.30, .y1 = 3.4 }, .{ .r = 5.40, .y0 = 3.2, .y1 = 8.5 } }, .surf = .wood },
    .{ .kind = .bigtree3, .build = wood.bigTree3, .bound = 14.0, .top = 13.5, .view = FAR, .parts = circleParts(0.90, 6.5), .occl = &.{ .{ .r = 1.25, .y1 = 5.6 }, .{ .r = 3.60, .y0 = 5.4, .y1 = 13.5 } }, .surf = .wood },
    // The curtain HANGS: `willowMesh` drops its fronds to y 0.9 at a reach of 3.2, so the blocking mass starts near the ground and the bole inside it is beside the point.
    .{ .kind = .willow, .build = wood.willowMesh, .bound = 8.0, .top = 7.1, .view = 300, .parts = circleParts(0.72, 4.4), .occl = &.{ .{ .r = 0.90, .y1 = 3.4 }, .{ .r = 3.60, .y0 = 0.9, .y1 = 5.5 } }, .surf = .wood },
    // A CONE, in three steps: `coniferMesh` whorls from y 0.16H with `reach` 3.1 falling to a spire.
    .{ .kind = .conifer, .build = wood.coniferMesh, .bound = 12.5, .top = 12.0, .view = FAR, .parts = circleParts(0.58, 5.0), .occl = &.{ .{ .r = 0.70, .y1 = 1.6 }, .{ .r = 3.40, .y0 = 1.4, .y1 = 5.0 }, .{ .r = 1.80, .y0 = 5.0, .y1 = 9.0 } }, .surf = .wood },
    .{ .kind = .birch, .build = wood.birchMesh, .bound = 10.0, .top = 9.4, .view = 340, .parts = circleParts(0.44, 5.0), .occl = &.{ .{ .r = 0.55, .y1 = 3.9 }, .{ .r = 3.00, .y0 = 3.5, .y1 = 9.4 } }, .surf = .wood },
    .{ .kind = .snag, .build = wood.snagMesh, .bound = 8.2, .top = 7.8, .view = 320, .parts = circleParts(0.42, 6.0), .occl = &.{.{ .r = 0.75, .y1 = 7.0 }}, .surf = .wood },
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
    .{ .kind = .skull, .build = bone.skullMesh, .bound = 3.9, .top = 2.3, .view = 300, .parts = &.{.{ .ax = -0.60, .bx = 1.60, .r = 1.05, .h = 1.95 }} },
    .{ .kind = .vertebra, .build = bone.vertebraMesh, .bound = 2.9, .top = 2.5, .view = 220, .parts = circleParts(0.85, 1.60) },

    // A heap is walked OVER and a dune is walked ROUND — and the dune's collider is only 1.4 m tall against its own 2.2, so a look passes over the ridge a body cannot cross. That gap is the region's one idea.
    .{ .kind = .ashheap, .build = ash.ashHeapMesh, .bound = 2.0, .top = 0.80, .view = 150 },
    .{ .kind = .ashdune, .build = ash.ashDuneMesh, .bound = 5.8, .top = 2.20, .view = 250, .parts = &.{.{ .ax = -2.40, .bx = 2.40, .r = 1.20, .h = 1.40 }} },
    .{ .kind = .cinders, .build = ash.cindersMesh, .bound = 1.6, .top = 0.25, .view = 130, .casts = false },
    .{ .kind = .charspar, .build = ash.charSparMesh, .bound = 5.9, .top = 5.50, .view = 300, .parts = circleParts(0.44, 4.0), .occl = &.{.{ .r = 0.70, .y1 = 5.4 }}, .surf = .wood },

    .{ .kind = .hoodoo, .build = rock.hoodooMesh, .bound = 6.4, .top = 5.90, .view = FAR, .parts = circleParts(0.60, 4.6), .occl = &.{ .{ .r = 0.90, .y1 = 3.5 }, .{ .r = 1.45, .y0 = 3.4, .y1 = 5.8 } } },
    .{ .kind = .spire, .build = rock.spireMesh, .bound = 10.2, .top = 9.40, .view = FAR, .parts = circleParts(1.10, 7.0), .occl = &.{.{ .r = 1.40, .y1 = 9.3 }} },
    .{ .kind = .balanced, .build = rock.balancedMesh, .bound = 4.6, .top = 4.10, .view = 320, .parts = &.{.{ .ax = 0.0, .bx = 0.62, .r = 1.10, .h = 2.30 }}, .occl = &.{.{ .x = 0.5, .r = 1.70, .y1 = 4.0 }} },
    .{ .kind = .fingers, .build = rock.fingersMesh, .bound = 5.6, .top = 4.80, .view = 320, .parts = &.{.{ .ax = -0.90, .bx = 1.70, .r = 0.60, .h = 3.80 }}, .occl = &.{.{ .x = 0.4, .r = 1.90, .y1 = 4.7 }} },

    .{ .kind = .obelisk, .build = ruins.obeliskMesh, .bound = 9.2, .top = 8.70, .view = FAR, .parts = circleParts(0.85, 7.0) },
    .{ .kind = .plinth, .build = ruins.plinthMesh, .bound = 2.8, .top = 2.60, .view = 210, .parts = &.{.{ .ax = -0.30, .bx = 0.30, .r = 0.85, .h = 1.70 }} },
    .{ .kind = .altar, .build = ruins.altarMesh, .bound = 2.9, .top = ruins.ALTAR_H, .view = 210, .parts = &.{.{ .ax = -1.35, .bx = 1.35, .r = 0.68, .h = 1.05 }} },

    .{ .kind = .rotlog, .build = wood.rotLogMesh, .bound = 3.2, .top = 0.95, .view = 175, .parts = &.{.{ .ax = -2.10, .bx = 2.10, .r = 0.40, .h = 0.85 }}, .surf = .wood },
    .{ .kind = .deadfall, .build = wood.deadfallMesh, .bound = 3.4, .top = 2.00, .view = 200, .parts = circleParts(1.10, 1.60), .surf = .wood },

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
    .{ .kind = .whaleback, .build = rock.whalebackMesh, .bound = 2.45, .top = rock.WHALE_H + 0.10, .view = 240, .parts = circleParts(0.90, rock.WHALE_H), .surf = .stone },
    .{ .kind = .capcluster, .build = fungus.capClusterMesh, .bound = 3.4, .top = 2.80, .view = 230, .parts = circleParts(0.75, 1.80), .occl = &.{.{ .r = 1.20, .y1 = 2.7 }}, .surf = .wood },
    .{ .kind = .bracket, .build = fungus.bracketMesh, .bound = 2.6, .top = 2.50, .view = 200, .parts = circleParts(0.45, 2.20), .surf = .wood },
    .{ .kind = .glowcap, .build = fungus.glowCapMesh, .bound = 3.0, .top = 2.90, .view = 260, .parts = circleParts(0.22, 2.00), .light = .{ .y = fungus.GLOW_LIGHT_Y, .col = v3(0.26, 0.62, 0.58), .radius = 7.5, .flicker = 0.05 }, .surf = .wood },
    .{ .kind = .sporepod, .build = fungus.sporePodMesh, .bound = 1.3, .top = 1.25, .view = 95, .flora = true, .casts = false },

    .{ .kind = .giltarch, .build = gold.giltArchMesh, .bound = gold.ARCH_TOP + 0.6, .top = gold.ARCH_TOP, .view = FAR, .parts = &.{
        .{ .ax = -gold.ARCH_HALF, .bx = -gold.ARCH_HALF, .r = 0.66, .h = gold.ARCH_SPRING },
        .{ .ax = gold.ARCH_HALF, .bx = gold.ARCH_HALF, .r = 0.66, .h = gold.ARCH_SPRING },
    } },
    .{ .kind = .muqarnas, .build = gold.muqarnasBlockMesh, .bound = gold.MUQ_TOP + 0.9, .top = gold.MUQ_TOP, .view = 230, .parts = &.{.{ .ax = -gold.MUQ_W * 0.5, .bx = gold.MUQ_W * 0.5, .r = 0.40, .h = gold.MUQ_WALL }} },
    .{ .kind = .giltdome, .build = gold.giltDomeMesh, .bound = gold.DOME_R * 2.2, .top = gold.DOME_TOP, .view = FAR, .solid = true, .parts = circleParts(gold.DOME_R * 0.92, gold.DOME_DRUM) },
    .{ .kind = .minaret, .build = gold.minaretMesh, .bound = gold.MIN_TOP + 0.8, .top = gold.MIN_TOP, .view = FAR, .solid = true, .parts = circleParts(gold.MIN_R * 1.25, gold.MIN_H * 0.92) },
    .{ .kind = .jali, .build = gold.jaliScreenMesh, .bound = gold.JALI_W + 1.0, .top = gold.JALI_TOP, .view = 300, .solid = true, .parts = &.{.{ .ax = -gold.JALI_W * 0.5, .bx = gold.JALI_W * 0.5, .r = 0.34, .h = gold.JALI_H }} },
    .{ .kind = .giltcolumn, .build = gold.giltColumnMesh, .bound = gold.COL_TOP + 0.5, .top = gold.COL_TOP, .view = 320, .parts = circleParts(0.52, gold.COL_H) },
    .{ .kind = .giltbasin, .build = gold.giltBasinMesh, .bound = gold.BASIN_R * 2.3, .top = gold.BASIN_TOP, .view = 200, .parts = circleParts(gold.BASIN_R * 0.80, 0.50) },
    .{ .kind = .giltfinial, .build = gold.giltFinialMesh, .bound = 1.7, .top = gold.FINIAL_TOP, .view = 150 },
    .{ .kind = .giltleaf, .build = gold.giltLeafMesh, .bound = gold.LEAF_R * 1.25, .top = gold.LEAF_TOP, .view = 160 },
    .{ .kind = .marblefloor, .build = gold.marbleFloorMesh, .bound = gold.FLOOR_R * 1.45, .top = 0.10, .view = 200, .casts = false },
    .{ .kind = .marbleslab, .build = gold.marbleSlabMesh, .bound = 2.4, .top = gold.SLAB_TOP, .view = 190, .parts = &.{.{ .ax = -0.95, .bx = 1.00, .r = 0.52, .h = 0.90 }} },
    .{ .kind = .marblestair, .build = gold.marbleStairMesh, .bound = 3.6, .top = gold.STAIR_TOP + 0.10, .view = 260, .parts = &.{.{ .ax = -gold.STAIR_W * 0.4, .bx = gold.STAIR_W * 0.4, .az = -1.05, .bz = 0.20, .r = 0.60, .h = gold.STAIR_TOP }} },

    .{ .kind = .ashcrag, .build = ash.ashCragMesh, .bound = ash.CRAG_TOP + 0.7, .top = ash.CRAG_TOP, .view = FAR, .parts = circleParts(0.95, ash.CRAG_TOP * 0.86), .occl = &.{.{ .r = 1.40, .y1 = ash.CRAG_TOP }} },
    .{ .kind = .stalagmite, .build = ash.stalagmiteMesh, .bound = ash.STAL_TOP + 0.40, .top = ash.STAL_TOP, .view = 200 },
    .{ .kind = .menhir, .build = ash.menhirMesh, .bound = ash.MENHIR_TOP + 0.6, .top = ash.MENHIR_TOP, .view = FAR, .parts = circleParts(0.62, ash.MENHIR_TOP * 0.90), .occl = &.{.{ .r = 0.90, .y1 = ash.MENHIR_TOP }} },
    .{ .kind = .stonecarve, .build = ash.stoneCarveMesh, .bound = ash.CARVE_R * 1.6, .top = ash.CARVE_TOP, .view = 230, .parts = circleParts(ash.CARVE_R * 0.80, ash.CARVE_TOP * 0.88) },

    .{ .kind = .merchanthut, .build = market.merchantHutMesh, .bound = market.HUT_TOP + 0.6, .top = market.HUT_TOP, .view = FAR, .solid = true, .parts = &.{
        .{ .ax = -market.HUT_W * 0.5, .bx = market.HUT_W * 0.5, .az = market.HUT_D * 0.5, .bz = market.HUT_D * 0.5, .r = 0.34, .h = 1.90 },
        .{ .ax = -market.HUT_W * 0.5, .bx = -market.HUT_W * 0.5, .az = -market.HUT_D * 0.5, .bz = market.HUT_D * 0.5, .r = 0.34, .h = 1.90 },
        .{ .ax = market.HUT_W * 0.5, .bx = market.HUT_W * 0.5, .az = -market.HUT_D * 0.5, .bz = market.HUT_D * 0.5, .r = 0.34, .h = 1.90 },
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
    .{ .kind = .scalepost, .build = market.scalePostMesh, .bound = market.SCALE_TOP + 0.5, .top = market.SCALE_TOP, .view = 280, .parts = circleParts(0.30, market.SCALE_TOP * 0.82) },
    .{ .kind = .waterjars, .build = market.waterJarsMesh, .bound = market.JARS_R * 1.7, .top = market.JARS_TOP, .view = 200, .parts = circleParts(0.52, market.JARS_TOP * 0.85) },
    .{ .kind = .hitchrail, .build = market.hitchRailMesh, .bound = market.HITCH_R * 1.5, .top = market.HITCH_TOP, .view = 260, .parts = &.{.{ .ax = -1.30, .bx = 1.30, .r = 0.16, .h = market.HITCH_TOP * 0.92 }} },

    .{ .kind = .pickup, .build = fx.pickupMesh, .bound = 1.9, .top = fx.PICKUP_TOP, .view = 190, .interact = true, .casts = false, .light = .{ .y = 0.30, .col = v3(0.86, 0.82, 0.58), .radius = 5.4, .flicker = 0.03 } },
    .{ .kind = .foggate, .build = fx.fogGateStoneMesh, .veil = fx.fogGateMesh, .bound = 5.4, .top = fx.FOG_H, .view = 320, .solid = true, .interact = true, .casts = false, .ward = true, .parts = &.{.{ .ax = -fx.FOG_W * 0.5, .bx = fx.FOG_W * 0.5, .r = fx.FOG_WARD_R, .h = fx.FOG_H }} },
    .{ .kind = .ladder, .build = build.ladderMesh, .bound = build.LADDER_SEG + 0.2, .top = build.LADDER_SEG, .view = 210, .stack = build.LADDER_SEG, .climb = true, .surf = .wood },
    .{ .kind = .anvil, .build = forge.anvilMesh, .bound = forge.ANVIL_R + 0.3, .top = forge.ANVIL_TOP, .view = 190, .parts = circleParts(forge.STUMP_R + 0.01, forge.ANVIL_TOP), .surf = .stone },
    .{ .kind = .forge, .build = forge.forgeMesh, .bound = forge.FORGE_R + 1.3, .top = forge.FORGE_TOP, .view = 300, .solid = true, .parts = &.{
        .{ .ax = -0.72, .bx = 0.72, .r = 0.62, .h = 1.10 },
    }, .light = .{ .y = forge.FORGE_LIGHT_Y, .col = v3(1.0, 0.52, 0.18), .radius = forge.FORGE_LIGHT_R, .flicker = 0.16 } },
    .{ .kind = .quenchtrough, .build = forge.quenchMesh, .bound = forge.QUENCH_R + 0.2, .top = forge.QUENCH_TOP, .view = 170, .parts = &.{.{ .ax = -0.62, .bx = 0.62, .r = 0.30, .h = forge.QUENCH_TOP }}, .surf = .wood },
    .{ .kind = .toolrack, .build = forge.toolRackMesh, .bound = forge.RACK_TOP + 0.6, .top = forge.RACK_TOP, .view = 220, .parts = &.{.{ .ax = -forge.RACK_HW, .bx = forge.RACK_HW, .r = 0.22, .h = forge.RACK_TOP * 0.9 }}, .surf = .wood },
    .{ .kind = .stairflight, .build = build.stairMesh, .bound = build.STAIR_RUN + 0.4, .top = build.STAIR_SEG, .view = 240, .stack = build.STAIR_SEG, .flight = .{ .run = build.STAIR_RUN, .halfW = build.STAIR_HALF, .treads = build.STAIR_TREADS }, .surf = .stone },
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
        for (row.parts) |part| {
            const ra = @sqrt(part.ax * part.ax + part.az * part.az) + part.r;
            const rb = @sqrt(part.bx * part.bx + part.bz * part.bz) + part.r;
            try std.testing.expect(@max(ra, rb) <= row.bound + 0.001);
        }
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
