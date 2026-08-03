const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const collision = @import("collision.zig");

// THE MESH FILES.
const art = @import("propart.zig");
const ruins = @import("propruins.zig");
const build = @import("propbuild.zig");
const village = @import("propvillage.zig");
const rock = @import("proprock.zig");
const wood = @import("propwood.zig");
const flora = @import("propflora.zig");
const fx = @import("propfx.zig");

const v3 = mathx.v3;


// Append new kinds at the END of their section.
pub const Kind = enum(u8) {
    // ruined kingdom — the original set
    pillar,
    broken, // a snapped column
    block,
    arch,
    wall,
    tree, // dead tree
    graves,
    sword,
    grace, // the BONFIRE CAMP — the tag is the world files' word, not a description (see ruins.graceMesh)
    tower, // colossal horizon keep
    gate, // colossal horizon gate
    rubble,
    banner,
    statue,
    // structures you move through / around
    chapel, // ROOFED + enterable: the torchlit interior
    watchtower, // ROOFED + enterable: masonry drum with a door
    cottage, // ruined shell, open to the sky
    causeway, // low stone crossing over the tarn's shallows
    paving, // a worn flagstone patch
    cart, // a broken wagon
    monolith, // standing stone
    cliff, // the world's rock wall (six variants — see CLIFFS)
    cliff2,
    cliff3,
    cliff4,
    cliff5,
    cliff6,
    // rock + wood litter
    boulder,
    rocks,
    stump,
    log,
    // village + wayside dressing — the things that say people lived here
    well,
    shrine, // a wayside shrine, candles still lit (carries a light)
    lantern, // a post lantern (carries a light)
    fence,
    barrels,
    woodpile,
    bones,
    sarcophagus,
    stairs, // a fragment of stone stair going nowhere
    gibbet, // a hanging cage on a post
    cairn,
    /// THE TREASURE CHEST — the one prop with a moving part and the only one that HOLDS anything.
    chest,
    // more rock
    outcrop, // a low shelf of bedrock breaking the turf
    scree,
    // fire (each carries a gfx.Light)
    torch, // standing iron torch — interiors
    brazier, // wide fire bowl on a tripod
    campfire, // stone ring + crossed logs
    water, // the tarn surface
    // FLORA (non-casters, wind-swayed)
    tuft,
    patch,
    shrub,
    flowers,
    reeds,
    glow,
    bush,
    bramble,
    fern,
    grasstall, // a tall, full clump — the workhorse of a lush meadow
    clover, // a low broad-leaf mat
    moss, // a damp patch creeping over the ground
    mushrooms,
    nettles,
    thistle,
    foxglove, // tall flowering spires
    heather, // low purple heath — the downs
    gorse, // spiny, yellow-flowered
    cattails, // bulrushes with brown heads — the water margin
    lilypads, // floating, on the tarn
    bracken, // dead brown fern, collapsed
    thicket, // a dense tangle of brush, chest high
    wildflowers, // a mixed-colour drift
    ivy, // a creeper mound, for the feet of ruins
    // big flora — casters, no sway (a swaying caster desyncs from the shadow map)
    bigtree,
    bigtree2,
    bigtree3,
    willow,
    conifer, // a dark spire — the skyline's punctuation
    birch, // pale slender trunk, light airy crown
    snag, // a tall dead trunk, stripped bare
    sapling,
};


/// The shelves the editor's palette is divided into.
pub const Group = enum {
    ruins,
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

    pub const N = @typeInfo(Group).@"enum".fields.len;

    pub fn label(g: Group) [:0]const u8 {
        return switch (g) {
            .ruins => "Ruins",
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
        };
    }
};

/// The name shown in the editor.
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
        .grace => "Bonfire Camp",
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
        .campfire => "Campfire",
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
    };
}

pub fn group(k: Kind) Group {
    return switch (k) {
        .pillar, .broken, .block, .arch, .wall, .statue, .monolith, .paving, .stairs, .rubble, .banner, .sword, .graves, .sarcophagus, .bones, .gibbet, .cairn => .ruins,
        .chapel, .watchtower, .cottage, .tower, .gate, .causeway => .buildings,
        .well, .shrine, .lantern, .fence, .barrels, .woodpile, .cart, .grace => .village,
        .chest => .treasure,
        .boulder, .rocks, .outcrop, .scree, .cliff, .cliff2, .cliff3, .cliff4, .cliff5, .cliff6, .stump, .log => .rock,
        .tree, .bigtree, .bigtree2, .bigtree3, .willow, .conifer, .birch, .snag, .sapling => .trees,
        .torch, .brazier, .campfire => .fire,
        .water => .water,
        .tuft, .patch, .grasstall, .clover, .moss => .grass,
        .flowers, .wildflowers, .foxglove, .thistle, .glow => .flowers,
        .shrub, .bush, .bramble, .thicket, .gorse, .heather, .nettles, .ivy => .brush,
        .fern, .bracken => .ferns,
        .reeds, .cattails, .lilypads => .wetland,
        .mushrooms => .fungus,
    };
}

pub const CLIFFS = [_]Kind{ .cliff, .cliff2, .cliff3, .cliff4, .cliff5, .cliff6 };

pub const NK = @typeInfo(Kind).@"enum".fields.len;

pub const Stock = enum { decor, props, interact };

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
    var n: usize = 0;
    for (0..NK) |i| {
        if (stock(@enumFromInt(i)) == s) n += 1;
    }
    return n;
}

comptime {
    std.debug.assert(FLORA_KINDS.len + SOLID_KINDS.len + INTERACT_KINDS.len == NK);
    // …and the two flags must not both be set, since `stock` resolves flora first and the kind would silently shelve as Decor.
    for (INFO) |row| std.debug.assert(!(row.interact and row.flora));
}
pub const Part = art.Part;

/// A fire this kind carries: a gfx.Light at a local offset.
pub const LightSpec = struct {
    y: f32, // height of the flame above the prop's base (fires sit on the prop axis, so x/z are 0)
    col: rl.Vector3, // colour * intensity, pre-gamma like every other colour here
    radius: f32,
    flicker: f32 = 0.18,
};

pub const Info = struct {
    kind: Kind, // self-check: must equal its own row index (see the comptime block below)
    build: *const fn (rl.Shader) rl.Model,
    veil: ?*const fn (rl.Shader) rl.Model = null,
    /// A STOWABLE PART: an ordinary caster in its own model, so the game can take it away.
    stow: ?*const fn (rl.Shader) rl.Model = null,
    bound: f32,
    /// Mesh top height.
    top: f32,
    /// Beyond this many world units the instance stops being drawn.
    view: f32,
    flora: bool = false,
    interact: bool = false,
    /// MAY THIN OUT WHEN IT STANDS IN THE CAMERA'S WAY — trunks, canopies, shafts, the things you
    /// lose the fight behind. Buildings, walls and cliffs are deliberately NOT in it: losing sight of
    /// the hero behind architecture is the geometry doing its job, and ER keeps those solid too.
    fades: bool = false,
    /// Included in the sun depth pass.
    casts: bool = true,
    parts: []const Part = &.{},
    light: ?LightSpec = null,
    surf: collision.Surface = .stone,
};

const FAR: f32 = 400.0;

fn circleParts(comptime r: f32, comptime h: f32) []const Part {
    return &.{.{ .r = r, .h = h }};
}

const cliffParts = [_]Part{
    .{ .ax = -5.4, .bx = 5.4, .r = 2.9, .h = 15.5 },
    .{ .ax = -2.2, .az = 2.1, .bx = 2.6, .bz = 2.4, .r = 2.2, .h = 15.5 },
};

pub const INFO = [NK]Info{
    .{ .kind = .pillar, .build = ruins.pillarWhole, .bound = 6.2, .top = 5.8, .view = 240, .fades = true, .parts = circleParts(0.80, 5.8) },
    .{ .kind = .broken, .build = ruins.pillarBroken, .bound = 3.6, .top = 3.3, .view = 200, .fades = true, .parts = circleParts(0.80, 2.9) },
    .{ .kind = .block, .build = ruins.blockMesh, .bound = 2.6, .top = 1.85, .view = 180, .parts = &.{.{ .ax = -0.35, .bx = 0.35, .r = 0.80, .h = 1.65 }} },
    .{ .kind = .arch, .build = ruins.archMesh, .bound = 7.9, .top = 7.2, .view = 260, .fades = true, .parts = &.{
        .{ .ax = -2.7, .bx = -2.7, .r = 0.78, .h = 4.8 },
        .{ .ax = 2.7, .bx = 2.7, .r = 0.78, .h = 4.8 },
    } },
    .{ .kind = .wall, .build = ruins.wallMesh, .bound = 5.0, .top = 3.6, .view = 220, .parts = &.{.{ .ax = -2.8, .bx = 2.8, .r = 0.60, .h = 3.0 }} },
    .{ .kind = .tree, .build = wood.treeMesh, .bound = 5.3, .top = 4.9, .view = 240, .fades = true, .parts = circleParts(0.38, 3.6), .surf = .wood },
    .{ .kind = .graves, .build = ruins.gravesMesh, .bound = 2.3, .top = 1.05, .view = 150, .parts = circleParts(0.80, 0.9) },
    .{ .kind = .sword, .build = ruins.swordMesh, .bound = 1.6, .top = 1.35, .view = 120 },
    .{ .kind = .grace, .build = ruins.graceMesh, .veil = ruins.graceVeilMesh, .stow = ruins.graceGuitarMesh, .bound = 7.2, .top = 5.4, .view = 300, .light = .{ .y = 0.45, .col = v3(0.86, 0.48, 0.18), .radius = 11.0, .flicker = 0.17 } },
    .{ .kind = .tower, .build = ruins.towerMesh, .bound = 17.5, .top = 17.2, .view = FAR, .parts = circleParts(3.40, 14.0) },
    .{ .kind = .gate, .build = ruins.gateMesh, .bound = 19.6, .top = 16.4, .view = FAR, .parts = &.{
        .{ .ax = -7.5, .bx = -7.5, .r = 3.20, .h = 16.0 },
        .{ .ax = 7.5, .bx = 7.5, .r = 3.20, .h = 16.0 },
    } },
    .{ .kind = .rubble, .build = ruins.rubbleMesh, .bound = 1.4, .top = 0.4, .view = 130 },
    .{ .kind = .banner, .build = ruins.bannerMesh, .bound = 3.4, .top = 3.2, .view = 190 },
    .{ .kind = .statue, .build = ruins.statueMesh, .bound = 3.0, .top = 2.7, .view = 230, .parts = circleParts(0.90, 2.7) },
    // half.
    .{ .kind = .chapel, .build = build.chapelMesh, .bound = 9.5, .top = 6.6, .view = FAR, .parts = &.{
        .{ .ax = -2.6, .az = -3.6, .bx = -2.6, .bz = 3.6, .r = 0.42, .h = 4.4 }, // west wall
        .{ .ax = 2.6, .az = -3.6, .bx = 2.6, .bz = 3.6, .r = 0.42, .h = 4.4 }, // east wall
        .{ .ax = -2.6, .az = 3.6, .bx = 2.6, .bz = 3.6, .r = 0.42, .h = 4.4 }, // north (altar) wall
        .{ .ax = -2.6, .az = -3.6, .bx = -1.15, .bz = -3.6, .r = 0.42, .h = 4.4 }, // south wall, west of the door
        .{ .ax = 1.15, .az = -3.6, .bx = 2.6, .bz = -3.6, .r = 0.42, .h = 4.4 },
        .{ .ax = -1.5, .az = 2.9, .bx = 1.5, .bz = 2.9, .r = 0.55, .h = 1.1 }, // the altar
    } },
    .{ .kind = .watchtower, .build = build.watchtowerMesh, .bound = 13.0, .top = 12.4, .view = FAR, .parts = &art.towerRing },
    .{ .kind = .cottage, .build = build.cottageMesh, .bound = 5.6, .top = 4.0, .view = 280, .parts = &.{
        .{ .ax = -2.3, .az = -1.9, .bx = -2.3, .bz = 1.9, .r = 0.34, .h = 2.6 },
        .{ .ax = 2.3, .az = -1.9, .bx = 2.3, .bz = 1.9, .r = 0.34, .h = 2.6 },
        .{ .ax = -2.3, .az = 1.9, .bx = 2.3, .bz = 1.9, .r = 0.34, .h = 3.4 },
        .{ .ax = -2.3, .az = -1.9, .bx = -0.95, .bz = -1.9, .r = 0.34, .h = 1.2 }, // collapsed to knee height
    }, .surf = .wood },
    // The causeway: you WALK it, so only its kerbs are solid — low enough that arrows arc over.
    .{ .kind = .causeway, .build = build.causewayMesh, .bound = 6.5, .top = 0.5, .view = 240, .parts = &.{
        .{ .ax = -5.0, .az = -1.45, .bx = 5.0, .bz = -1.45, .r = 0.20, .h = 0.5 },
        .{ .ax = -5.0, .az = 1.45, .bx = 5.0, .bz = 1.45, .r = 0.20, .h = 0.5 },
    } },
    .{ .kind = .paving, .build = build.pavingMesh, .bound = 3.2, .top = 0.15, .view = 150 },
    .{ .kind = .cart, .build = village.cartMesh, .bound = 3.4, .top = 1.7, .view = 170, .parts = &.{.{ .ax = -1.1, .bx = 1.1, .r = 0.55, .h = 1.3 }}, .surf = .wood },
    .{ .kind = .monolith, .build = rock.monolithMesh, .bound = 5.2, .top = 4.9, .view = FAR, .parts = circleParts(0.62, 4.6) },
    .{ .kind = .cliff, .build = rock.cliff1, .bound = 18.0, .top = 15.5, .view = FAR, .parts = &cliffParts },
    .{ .kind = .cliff2, .build = rock.cliff2, .bound = 17.0, .top = 14.0, .view = FAR, .parts = &cliffParts },
    .{ .kind = .cliff3, .build = rock.cliff3, .bound = 19.0, .top = 16.8, .view = FAR, .parts = &cliffParts },
    .{ .kind = .cliff4, .build = rock.cliff4, .bound = 17.5, .top = 14.9, .view = FAR, .parts = &cliffParts },
    .{ .kind = .cliff5, .build = rock.cliff5, .bound = 17.0, .top = 13.3, .view = FAR, .parts = &cliffParts },
    .{ .kind = .cliff6, .build = rock.cliff6, .bound = 18.0, .top = 14.5, .view = FAR, .parts = &cliffParts },
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
    .{ .kind = .chest, .build = village.chestMesh, .bound = 1.6, .top = village.CHEST_TOP + 0.34, .view = 150, .interact = true, .parts = &.{.{ .r = 0.56, .h = village.CHEST_HINGE_Y }}, .surf = .wood },
    .{ .kind = .outcrop, .build = rock.outcropMesh, .bound = 3.4, .top = 1.1, .view = 200, .parts = &.{.{ .ax = -1.4, .bx = 1.4, .r = 1.1, .h = 1.05 }} },
    .{ .kind = .scree, .build = rock.screeMesh, .bound = 2.6, .top = 0.35, .view = 160 },
    .{ .kind = .torch, .build = fx.torchMesh, .bound = 2.6, .top = 2.35, .view = 200, .parts = circleParts(0.18, 2.0), .light = .{ .y = 1.98, .col = v3(0.64, 0.34, 0.13), .radius = 6.0, .flicker = 0.15 }, .surf = .metal },
    .{ .kind = .brazier, .build = fx.brazierMesh, .bound = 1.9, .top = 1.55, .view = 210, .parts = circleParts(0.50, 1.2), .light = .{ .y = 1.14, .col = v3(1.55, 0.84, 0.29), .radius = 16.0, .flicker = 0.13 }, .surf = .metal },
    .{ .kind = .campfire, .build = fx.campfireMesh, .bound = 1.5, .top = 1.0, .view = 200, .parts = circleParts(0.45, 0.5), .light = .{ .y = 0.52, .col = v3(1.05, 0.52, 0.17), .radius = 13.0, .flicker = 0.18 } },
    .{ .kind = .water, .build = fx.waterMesh, .bound = 30.0, .top = 0.1, .view = FAR, .casts = false },
    .{ .kind = .tuft, .build = flora.tuftMesh, .bound = 0.9, .top = 0.8, .view = 85, .flora = true, .casts = false },
    .{ .kind = .patch, .build = flora.patchMesh, .bound = 2.2, .top = 0.8, .view = 95, .flora = true, .casts = false },
    .{ .kind = .shrub, .build = flora.shrubMesh, .bound = 1.2, .top = 0.75, .view = 115, .flora = true, .casts = false },
    .{ .kind = .flowers, .build = flora.flowersMesh, .bound = 1.0, .top = 0.5, .view = 90, .flora = true, .casts = false },
    .{ .kind = .reeds, .build = flora.reedsMesh, .bound = 1.6, .top = 1.35, .view = 130, .flora = true, .casts = false },
    .{ .kind = .glow, .build = flora.glowMesh, .bound = 1.0, .top = 0.55, .view = 140, .flora = true, .casts = false },
    .{ .kind = .bush, .build = flora.bushMesh, .bound = 1.8, .top = 1.25, .view = 130, .flora = true, .casts = false },
    .{ .kind = .bramble, .build = flora.brambleMesh, .bound = 1.9, .top = 0.9, .view = 120, .flora = true, .casts = false },
    .{ .kind = .fern, .build = flora.fernMesh, .bound = 1.3, .top = 0.8, .view = 105, .flora = true, .casts = false },
    // shadow-map entry (thin geometry sparkles in it) and all of it sways.
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
    .{ .kind = .bigtree, .build = wood.bigTree1, .bound = 13.5, .top = 11.0, .view = FAR, .fades = true, .parts = circleParts(0.95, 6.0), .surf = .wood },
    .{ .kind = .bigtree2, .build = wood.bigTree2, .bound = 13.0, .top = 8.5, .view = FAR, .fades = true, .parts = circleParts(0.95, 5.0), .surf = .wood },
    .{ .kind = .bigtree3, .build = wood.bigTree3, .bound = 14.0, .top = 13.5, .view = FAR, .fades = true, .parts = circleParts(0.90, 6.5), .surf = .wood },
    .{ .kind = .willow, .build = wood.willowMesh, .bound = 8.0, .top = 7.1, .view = 300, .fades = true, .parts = circleParts(0.72, 4.4), .surf = .wood },
    .{ .kind = .conifer, .build = wood.coniferMesh, .bound = 12.5, .top = 12.0, .view = FAR, .fades = true, .parts = circleParts(0.58, 5.0), .surf = .wood },
    .{ .kind = .birch, .build = wood.birchMesh, .bound = 10.0, .top = 9.4, .view = 340, .fades = true, .parts = circleParts(0.44, 5.0), .surf = .wood },
    .{ .kind = .snag, .build = wood.snagMesh, .bound = 8.2, .top = 7.8, .view = 320, .fades = true, .parts = circleParts(0.42, 6.0), .surf = .wood },
    // A sapling CASTS (it is 3 m of tree, and a 3 m thing with no shadow reads as a decal) and so must not sway — the depth pass has no wind term.
    .{ .kind = .sapling, .build = wood.saplingMesh, .bound = 3.8, .top = 3.4, .view = 220, .parts = circleParts(0.16, 2.2), .surf = .wood },
};

pub fn info(k: Kind) *const Info {
    return &INFO[@intFromEnum(k)];
}

comptime {
    for (INFO, 0..) |row, i| std.debug.assert(@intFromEnum(row.kind) == i);
    // A bound smaller than the mesh pops geometry at the frustum edge; catch the obvious cases.
    for (INFO) |row| std.debug.assert(row.bound >= row.top);
    for (INFO) |row| std.debug.assert(!(row.flora and row.casts)); // flora must stay out of the shadow map
    // A STOW RIDES THE VEIL LIST.
    for (INFO) |row| std.debug.assert(!(row.stow != null and row.veil == null));
}

test "every kind row sits at its own index and carries a mesh builder" {
    // The comptime block already asserts the index match; this pins the table's SHAPE so a half-added kind (enum extended, table not) fails as a test rather than at first draw.
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

test "the watchtower's collider ring leaves exactly one doorway gap" {
    try std.testing.expectEqual(@as(usize, art.TOWER_SIDES - art.TOWER_DOOR), art.towerRing.len);
    for (art.towerRing) |part| try std.testing.expect(part.az > -art.TOWER_R * 0.85);
}

test "fires carry a light above their base and inside their own bound" {
    for (INFO) |row| {
        const l = row.light orelse continue;
        try std.testing.expect(l.y > 0 and l.y <= row.bound);
        try std.testing.expect(l.radius > 1.0);
        try std.testing.expect(l.flicker >= 0 and l.flicker < 1);
    }
}

pub const WATER_TONES = [3]rl.Vector3{ linear(art.WATER_SHALLOW), linear(art.WATER_MID), linear(art.WATER_DEEP) };

fn linear(c: rl.Color) rl.Vector3 {
    const f = 1.0 / 255.0;
    return v3(@as(f32, @floatFromInt(c.r)) * f, @as(f32, @floatFromInt(c.g)) * f, @as(f32, @floatFromInt(c.b)) * f);
}
