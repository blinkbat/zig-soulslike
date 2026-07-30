const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// ── PROPS ── every static thing in the world: one procedural mesh per KIND, plus ONE table
// (`INFO`) holding everything else the engine needs per kind. env.zig places instances; nothing
// outside this file knows what a `cliff` is.
//
// A kind is ONE ROW. The old layout spread it across four places (a K_* constant, a models[]
// slot, an arm of a collider switch, a `>= K_TUFT` flora threshold) and forgetting one failed
// SILENTLY — a walk-through wall, a sparkling shadow. Miss a field now and the build stops.
//
// House style: WABI-SABI (every mesh grows from a seeded Rng, so builds stay deterministic
// while sizes/leans/gaps drift) and FLESH IS ROUND (blob/capsule for organic mass; cube/box for
// masonry, iron, timber, cloth).

// ── palettes ── pre-gamma DARK: the shader's hot key (*1.72) plus its 1/2.2 gamma lift turns
// any mid value into poured concrete wherever a big face takes the low sun square on.
pub const STONE = rgba(58, 55, 49, 255); // ruin masonry: ochre-grey mineral, not builders' slab
pub const STONE_LT = rgba(73, 70, 62, 255);
pub const STONE_DK = rgba(38, 36, 32, 255);
pub const STONE_MOSS = rgba(52, 58, 40, 255);
// The packed core behind every facing. Only ever glimpsed through a joint, so darker than any
// facing stone: a gap must read as DEPTH, never as a hole through to the sky.
const MORTAR = rgba(36, 33, 29, 255);
// MARBLE — dressed stone, against STONE's rubble masonry. Cooler and a touch paler, and the
// shader does the rest (gfx.Mat.marble veins it and gives it the only gloss besides steel and
// water). That polish is what says one of them was built with money.
const MARBLE = rgba(54, 54, 52, 255);
const MARBLE_LT = rgba(70, 70, 68, 255); // capitals, abaci, an altar top
const MARBLE_DK = rgba(34, 34, 34, 255); // in shade, or where the soot and rain got in
// Living rock: colder and greyer than ruin masonry, and DARKER than feels right on the swatch.
// A cliff face is a huge mass taking the low sun almost square on, and the scene shader's hot key
// plus its gamma lift turned the first (70,66,62) version chalk white from 40 m away.
const CLIFF_ROCK = rgba(47, 45, 42, 255);
const CLIFF_DK = rgba(31, 30, 28, 255);
const CLIFF_LT = rgba(62, 59, 55, 255);
// For rock you stand NEXT to (boulders, field stones). Darker again than the cliff set, which is
// only ever seen through 40 m of haze — up close that same value comes back as a pale pillow.
const ROCK_DEEP = rgba(23, 22, 21, 255);
// The city's old road surface. Darker than STONE for the same reason, plus one of its own: paving
// is a thing you half-notice underfoot, and at STONE's value it read as sheets of paper thrown
// across the grass.
const PAVE = rgba(32, 31, 27, 255);
const PAVE_DK = rgba(22, 21, 19, 255);
const PAVE_LT = rgba(41, 40, 35, 255); // the crown of a sett, worn smooth by feet and cartwheels
const SOIL = rgba(28, 23, 17, 255); // the dirt showing through where the road has lost its stones
const BARK = rgba(36, 29, 22, 255);
const BARK_DK = rgba(26, 21, 17, 255);
const BARK_LIVE = rgba(44, 36, 27, 255); // a living trunk reads a touch warmer than a dead one
// For BIG barrels only. The wider a smooth mass is, the more of it takes the sun square on, and
// the scene shader's hot key plus its 1/2.2 gamma lift then flattens a mid-dark albedo to pale
// beige — a great tree's bole needs to start nearly black to come back as bark.
const BARK_OLD = rgba(22, 17, 13, 255);
const IRON = rgba(30, 28, 26, 255);
const STEEL = rgba(100, 106, 116, 255);
const BRASS = rgba(122, 92, 40, 255);
const TIMBER = rgba(48, 37, 25, 255);
const TIMBER_DK = rgba(33, 26, 18, 255);
const THATCH = rgba(74, 60, 30, 255);
const THATCH_DK = rgba(52, 42, 22, 255);
// Emissive (vertex alpha < 255 = self-lit): the grace ember, its wisp, and every flame.
const EMBER = rgba(240, 162, 58, 40);
const WISP = rgba(250, 196, 110, 120);
// Eased DOWN across the board (owner: all flames a bit more subtle). These ride the EMISSIVE
// channel, which the scene shader takes to `base*1.35` — so a near-white core at 255 came back
// blown out and a fire was the loudest thing on any screen it appeared in. Same hues, same
// core→mid→tip ramp, less glare; the light each fire casts is unchanged.
const FLAME_CORE = rgba(226, 190, 128, 25); // pale heart of a torch — no longer near-WHITE
const FLAME_MID = rgba(214, 138, 48, 40);
const FLAME_TIP = rgba(176, 82, 24, 90); // the cooler, more transparent-reading tongue
const COAL = rgba(196, 78, 22, 70);
const CLOTH = rgba(76, 20, 12, 255); // faded war-banner crimson (matches the hero's cape)
const CLOTH_DK = rgba(48, 14, 10, 255); // …in the folds, and where the rain got into it
const CLOTH_SUN = rgba(96, 46, 32, 255); // …and at the frayed hem, where the sun ate the dye out

// Plant palette (pre-gamma dark) — Limgrave gold over scrub green.
const GRASS_GOLD = rgba(96, 76, 34, 255);
const GRASS_DRY = rgba(78, 64, 30, 255);
const GRASS_GRN = rgba(50, 56, 28, 255);
const SCRUB = rgba(38, 46, 26, 255);
const SCRUB_DK = rgba(28, 34, 20, 255);
const STEM = rgba(44, 54, 28, 255);
const PETAL = rgba(210, 196, 152, 255);
const SEED = rgba(118, 94, 46, 255);
const PETAL_GLOW = rgba(242, 206, 118, 200); // slight emissive — kin to the grace ember
// Canopy foliage: deep and unlit-looking in the mass, gold-touched where the sun catches it.
const LEAF_DK = rgba(26, 34, 20, 255);
const LEAF = rgba(36, 45, 24, 255);
const LEAF_LT = rgba(52, 58, 28, 255);
const LEAF_GOLD = rgba(74, 66, 30, 255);
const LEAF_PALE = rgba(58, 64, 34, 255); // willow: silvered, thirstier green
const BERRY = rgba(58, 14, 18, 255);
// The lush layer: a meadow needs more than gold grass, so there are damp greens, a couple of
// flower hues, and the browns of things that have died back. All pre-gamma dark, as ever.
const LEAF_DAMP = rgba(30, 44, 26, 255); // shade-grown: greener and cooler than the sunlit gold
const CLOVER_GRN = rgba(40, 54, 30, 255);
const MOSS_SOFT = rgba(44, 56, 32, 255);
const MOSS_DK = rgba(30, 40, 24, 255);
// Dead fern, collapsed. Kept DARK: at (84,60,30) the gamma lift turned patches of it into sheets
// of bright gold lying on the forest floor, which pulled the eye straight to the litter layer.
const BRACKEN_BRN = rgba(50, 35, 19, 255);
const NETTLE = rgba(34, 48, 26, 255);
const PURPLE = rgba(72, 44, 76, 255); // thistle / foxglove / heather bloom
const PURPLE_DK = rgba(50, 30, 56, 255);
const GORSE_GOLD = rgba(126, 100, 28, 255); // the only genuinely bright flower out here
const PETAL_WHITE = rgba(196, 190, 168, 255);
const PETAL_BLUE = rgba(96, 108, 140, 255);
const CAP_BROWN = rgba(88, 60, 40, 255); // mushroom cap
const CAP_PALE = rgba(126, 116, 96, 255);
const LILY_GRN = rgba(46, 60, 34, 255);
const IVY_GRN = rgba(28, 40, 24, 255);
const NEEDLE = rgba(23, 33, 25, 255); // conifer: the darkest green in the world
const NEEDLE_LT = rgba(34, 44, 28, 255);
const BIRCH_BARK = rgba(104, 100, 90, 255); // pale, and the only tree you can pick out at distance
const BIRCH_SCAR = rgba(44, 42, 38, 255);
const BONE = rgba(108, 104, 92, 255);
const RUST = rgba(58, 38, 24, 255);
// BONFIRE ASH — the palest albedo in the world, and deliberately so. Everything else out here is
// authored near-black because the shader's hot key plus the gamma lift turn mid values pale; ash is
// the one material that WANTS to come back pale, because a grey pat of it in a ring of stones is
// what finds your eye across a hundred metres of golden plain. That is the bonfire's whole job, and
// it is done by albedo, not by the light. Still kept well under mid grey: at 126 the lift took it
// to 237 and the pit read as spilled paint.
const ASH = rgba(78, 74, 70, 255);
const ASH_LT = rgba(96, 92, 86, 255); // where it has been raked over, or a fresh drift
const ASH_DK = rgba(46, 43, 40, 255); // wet, or trodden into the kerb
// The tarn: dark peat-water in the middle, silted a little paler at the rim. The RIPPLES and
// the sun glitter are the shader's (gfx.Mat.water); these are only what's suspended in it.
// Authored DARK on purpose — the first pass was three times this bright and the lake read as
// milky ice, because a water surface gets nearly all of its light from the specular, not the
// albedo. And the deep→shallow spread is kept narrow: the sheet is a fan of flat-shaded quads,
// so a wide gradient shows up as concentric BANDS rather than as depth.
const WATER_DEEP = rgba(13, 19, 21, 255);
const WATER_MID = rgba(18, 25, 26, 255);
const WATER_SHALLOW = rgba(30, 35, 31, 255);
const WATER_MUD = rgba(40, 35, 25, 255); // the wet margin the sheet sits in

// ── the kinds ──────────────────────────────────────────────────────────────────────────
// Append new kinds at the END of their section. Nothing depends on the numeric order (the
// draw split reads `flora`/`casts`, not an index threshold), but keeping the sections
// grouped keeps the table readable.
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
    grace, // the grace ember
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
    cliff4, // …ivy-laced: creeper curtains down the face, moss packed into the seams
    cliff5, // …collapsed: a gully torn out of it, fresh rock at the scar, the apron at its foot
    cliff6, // …both — an old collapse gone green
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
    // more rock
    outcrop, // a low shelf of bedrock breaking the turf
    scree,
    // fire (each carries a gfx.Light)
    torch, // standing iron torch — interiors
    brazier, // wide fire bowl on a tripod
    campfire, // stone ring + crossed logs
    // water
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

// ── EDITOR PRESENTATION ── what a kind is CALLED and what shelf it lives on. Enum tags are
// terse identifiers ("tree", "birch", "broken"), which is right in code and useless in a
// palette: you cannot tell a dead tree from a birch, or a snapped column from a whole one.
//
// Written as EXHAUSTIVE SWITCHES rather than a parallel table. A switch with no `else` is
// checked by the compiler, so adding a Kind is a build error until it has been named and
// filed — the same guarantee INFO's comptime block gives, without a second array to keep in
// lockstep with the first.

/// The shelves the editor's palette is divided into. Ordered as they appear in the UI.
pub const Group = enum {
    ruins,
    buildings,
    village,
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

/// The name shown in the editor. Says what the thing IS, not what the identifier is.
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
        .grace => "Grace Ember",
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
        // Named for the CHARACTER each one carries, not numbered: the palette's job is to say
        // what the thing is, and "Cliff Face II" tells you nothing about which rock you are
        // about to stand up.
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

/// Which shelf a kind sits on in the palette.
pub fn group(k: Kind) Group {
    return switch (k) {
        .pillar, .broken, .block, .arch, .wall, .statue, .monolith, .paving, .stairs, .rubble, .banner, .sword, .graves, .sarcophagus, .bones, .gibbet, .cairn => .ruins,
        .chapel, .watchtower, .cottage, .tower, .gate, .causeway => .buildings,
        .well, .shrine, .lantern, .fence, .barrels, .woodpile, .cart, .grace => .village,
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

/// The great-tree variants as a set, so placement code mixes them instead of naming one.
pub const BIG_TREES = [_]Kind{ .bigtree, .bigtree2, .bigtree3 };
/// …and the cliff variants, as a SET, for the rock that rings the world and the arc round the start
/// bowl. SIX of them: an `edge` op repeats a segment every few metres for well over a kilometre, and
/// the more characters that alternate along it the further the eye has to travel before it finds the
/// repeat. What any one map draws from the set is the MAP's business — the shipped rim mixes the
/// first three and stands 4-6 up as literals in the start arc, where their surfaces can be read.
/// `Map.blank` seeds a fresh rim from the whole set.
pub const CLIFFS = [_]Kind{ .cliff, .cliff2, .cliff3, .cliff4, .cliff5, .cliff6 };

pub const NK = @typeInfo(Kind).@"enum".fields.len;

/// One footprint collider in the kind's LOCAL space (a capsule a→b with radius r; a==b is a
/// plain circle). env rotates by the instance yaw and multiplies by its scale. `h` is the
/// piece's own top height — what makes arrow COVER work (a shot clears a low kerb but thunks
/// into a chapel wall), so it is per-part, not per-kind.
pub const Part = struct { ax: f32 = 0, az: f32 = 0, bx: f32 = 0, bz: f32 = 0, r: f32, h: f32 };

/// A fire this kind carries: a gfx.Light at a local offset. `flicker` is the fraction of the
/// intensity that guttering swings (0 = a steady glow, 0.3 = a live flame).
pub const LightSpec = struct {
    y: f32, // height of the flame above the prop's base (fires sit on the prop axis, so x/z are 0)
    col: rl.Vector3, // colour * intensity, pre-gamma like every other colour here
    radius: f32,
    flicker: f32 = 0.18,
};

pub const Info = struct {
    kind: Kind, // self-check: must equal its own row index (see the comptime block below)
    build: *const fn (rl.Shader) rl.Model,
    /// Radius of a sphere about the prop's GROUND ORIGIN that encloses the whole mesh — the
    /// culling bound. Generous is fine (a too-SMALL one pops geometry in and out at the frustum
    /// edge, which is the only failure that shows).
    bound: f32,
    /// Mesh top height. Feeds the sun-reach shadow cull (a caster this tall throws its shadow
    /// ~1.5x its height at the golden-hour sun elevation) — colliders carry their own `h`.
    top: f32,
    /// Beyond this many world units the instance stops being drawn. Set it where the haze has
    /// already swallowed the thing, or it visibly pops. `FAR` = never cull (out at the clip plane).
    view: f32,
    /// Drawn in the flora pass: NOT in the shadow map (thin blades sparkle in it) and swayed by
    /// the shader's wind term.
    flora: bool = false,
    /// Included in the sun depth pass. Flora never is; nor is the water sheet (a flat film has
    /// no shadow to give) — everything else casts.
    casts: bool = true,
    parts: []const Part = &.{},
    light: ?LightSpec = null,
};

/// "Never distance-cull this" — past the camera's far clip plane, so only the frustum can
/// reject it. The colossal landmarks (cliffs, the horizon gate, great trees) use it: they are
/// the things that tell you how big the world is.
const FAR: f32 = 400.0;

fn circleParts(comptime r: f32, comptime h: f32) []const Part {
    return &.{.{ .r = r, .h = h }};
}

// Shared by all three cliff variants: a long capsule down the face plus one bulge, sized to the
// rock MASS rather than to any one variant's crest (they differ only in height and seed).
const cliffParts = [_]Part{
    .{ .ax = -5.4, .bx = 5.4, .r = 2.9, .h = 15.5 },
    .{ .ax = -2.2, .az = 2.1, .bx = 2.6, .bz = 2.4, .r = 2.2, .h = 15.5 },
};

pub const INFO = [NK]Info{
    .{ .kind = .pillar, .build = pillarWhole, .bound = 6.2, .top = 5.8, .view = 240, .parts = circleParts(0.80, 5.8) },
    .{ .kind = .broken, .build = pillarBroken, .bound = 3.6, .top = 3.3, .view = 200, .parts = circleParts(0.80, 2.9) },
    .{ .kind = .block, .build = blockMesh, .bound = 2.6, .top = 1.85, .view = 180, .parts = &.{.{ .ax = -0.35, .bx = 0.35, .r = 0.80, .h = 1.65 }} },
    .{ .kind = .arch, .build = archMesh, .bound = 7.9, .top = 7.2, .view = 260, .parts = &.{
        .{ .ax = -2.7, .bx = -2.7, .r = 0.78, .h = 4.8 },
        .{ .ax = 2.7, .bx = 2.7, .r = 0.78, .h = 4.8 },
    } },
    .{ .kind = .wall, .build = wallMesh, .bound = 5.0, .top = 3.6, .view = 220, .parts = &.{.{ .ax = -2.8, .bx = 2.8, .r = 0.60, .h = 3.0 }} },
    .{ .kind = .tree, .build = treeMesh, .bound = 5.3, .top = 4.9, .view = 240, .parts = circleParts(0.38, 3.6) },
    .{ .kind = .graves, .build = gravesMesh, .bound = 2.3, .top = 1.05, .view = 150, .parts = circleParts(0.80, 0.9) },
    .{ .kind = .sword, .build = swordMesh, .bound = 1.6, .top = 1.35, .view = 120 },
    // A BONFIRE now, not an ember in a bowl — so its light is a fire's: warmer, brighter, and it
    // GUTTERS (0.10 was an ember's steady glow, and the flame above it is no longer standing still).
    .{ .kind = .grace, .build = graceMesh, .bound = 1.9, .top = 1.6, .view = 300, .light = .{ .y = 0.45, .col = v3(0.58, 0.32, 0.12), .radius = 8.0, .flicker = 0.26 } },
    .{ .kind = .tower, .build = towerMesh, .bound = 17.5, .top = 17.2, .view = FAR, .parts = circleParts(3.40, 14.0) },
    .{ .kind = .gate, .build = gateMesh, .bound = 19.6, .top = 16.4, .view = FAR, .parts = &.{
        .{ .ax = -7.5, .bx = -7.5, .r = 3.20, .h = 16.0 },
        .{ .ax = 7.5, .bx = 7.5, .r = 3.20, .h = 16.0 },
    } },
    .{ .kind = .rubble, .build = rubbleMesh, .bound = 1.4, .top = 0.4, .view = 130 },
    .{ .kind = .banner, .build = bannerMesh, .bound = 3.4, .top = 3.2, .view = 190 },
    .{ .kind = .statue, .build = statueMesh, .bound = 3.0, .top = 2.7, .view = 230, .parts = circleParts(0.90, 2.7) },
    // ── the chapel: 5 x 7 m nave, walls 4.4 high, DOORWAY on local −Z, roofed over the north
    // half. Colliders are the four walls split around that doorway plus the two interior
    // column rows, so you walk in and the stone still stops arrows.
    .{ .kind = .chapel, .build = chapelMesh, .bound = 9.5, .top = 6.6, .view = FAR, .parts = &.{
        .{ .ax = -2.6, .az = -3.6, .bx = -2.6, .bz = 3.6, .r = 0.42, .h = 4.4 }, // west wall
        .{ .ax = 2.6, .az = -3.6, .bx = 2.6, .bz = 3.6, .r = 0.42, .h = 4.4 }, // east wall
        .{ .ax = -2.6, .az = 3.6, .bx = 2.6, .bz = 3.6, .r = 0.42, .h = 4.4 }, // north (altar) wall
        .{ .ax = -2.6, .az = -3.6, .bx = -1.15, .bz = -3.6, .r = 0.42, .h = 4.4 }, // south wall, west of the door
        .{ .ax = 1.15, .az = -3.6, .bx = 2.6, .bz = -3.6, .r = 0.42, .h = 4.4 }, // …and east of it
        .{ .ax = -1.5, .az = 2.9, .bx = 1.5, .bz = 2.9, .r = 0.55, .h = 1.1 }, // the altar
    } },
    // The watchtower drum: a ring of small colliders with a gap at the door (collision is
    // capsules-only, so a hollow round tower is approximated by its own masonry).
    .{ .kind = .watchtower, .build = watchtowerMesh, .bound = 13.0, .top = 12.4, .view = FAR, .parts = &towerRing },
    .{ .kind = .cottage, .build = cottageMesh, .bound = 5.6, .top = 4.0, .view = 280, .parts = &.{
        .{ .ax = -2.3, .az = -1.9, .bx = -2.3, .bz = 1.9, .r = 0.34, .h = 2.6 },
        .{ .ax = 2.3, .az = -1.9, .bx = 2.3, .bz = 1.9, .r = 0.34, .h = 2.6 },
        .{ .ax = -2.3, .az = 1.9, .bx = 2.3, .bz = 1.9, .r = 0.34, .h = 3.4 },
        .{ .ax = -2.3, .az = -1.9, .bx = -0.95, .bz = -1.9, .r = 0.34, .h = 1.2 }, // collapsed to knee height
    } },
    // The causeway: you WALK it, so only its kerbs are solid — low enough that arrows arc over.
    .{ .kind = .causeway, .build = causewayMesh, .bound = 6.5, .top = 0.5, .view = 240, .parts = &.{
        .{ .ax = -5.0, .az = -1.45, .bx = 5.0, .bz = -1.45, .r = 0.20, .h = 0.5 },
        .{ .ax = -5.0, .az = 1.45, .bx = 5.0, .bz = 1.45, .r = 0.20, .h = 0.5 },
    } },
    .{ .kind = .paving, .build = pavingMesh, .bound = 3.2, .top = 0.15, .view = 150 },
    .{ .kind = .cart, .build = cartMesh, .bound = 3.4, .top = 1.7, .view = 170, .parts = &.{.{ .ax = -1.1, .bx = 1.1, .r = 0.55, .h = 1.3 }} },
    .{ .kind = .monolith, .build = monolithMesh, .bound = 5.2, .top = 4.9, .view = FAR, .parts = circleParts(0.62, 4.6) },
    // THREE cliff variants, for the same reason the great trees have three: the ring repeats a
    // segment every 6.5 m (the shipped map's `edge` step) for 1.3 km, and one silhouette repeated at
    // that pitch reads as a periodic TOOTHED pattern along the horizon — unmistakably manufactured.
    .{ .kind = .cliff, .build = cliff1, .bound = 18.0, .top = 15.5, .view = FAR, .parts = &cliffParts },
    .{ .kind = .cliff2, .build = cliff2, .bound = 17.0, .top = 14.0, .view = FAR, .parts = &cliffParts },
    .{ .kind = .cliff3, .build = cliff3, .bound = 19.0, .top = 16.8, .view = FAR, .parts = &cliffParts },
    // …and three MORE, because six characters alternating along the rim (and around the start
    // arc) is what pushes the repeat past where the eye looks for it. `top` tracks ~1.15x the
    // variant's own H, like the three above; the bound stays generous — the collapsed one throws
    // its rubble apron a good 6 m clear of the face, and a too-small bound pops it at the frustum
    // edge. All three share `cliffParts`, which is sized to the rock MASS and not to any one
    // variant's crest, so a shorter face is still a solid face.
    .{ .kind = .cliff4, .build = cliff4, .bound = 17.5, .top = 14.9, .view = FAR, .parts = &cliffParts },
    .{ .kind = .cliff5, .build = cliff5, .bound = 17.0, .top = 13.3, .view = FAR, .parts = &cliffParts },
    .{ .kind = .cliff6, .build = cliff6, .bound = 18.0, .top = 14.5, .view = FAR, .parts = &cliffParts },
    .{ .kind = .boulder, .build = boulderMesh, .bound = 3.2, .top = 2.5, .view = 220, .parts = circleParts(1.15, 2.3) },
    .{ .kind = .rocks, .build = rocksMesh, .bound = 2.2, .top = 0.85, .view = 160 },
    .{ .kind = .stump, .build = stumpMesh, .bound = 1.7, .top = 1.25, .view = 150, .parts = circleParts(0.46, 1.2) },
    .{ .kind = .log, .build = logMesh, .bound = 3.0, .top = 0.75, .view = 160, .parts = &.{.{ .ax = -1.9, .bx = 1.9, .r = 0.36, .h = 0.75 }} },
    // ── village + wayside dressing ──
    .{ .kind = .well, .build = wellMesh, .bound = 2.6, .top = 2.4, .view = 240, .parts = circleParts(1.05, 1.15) },
    .{ .kind = .shrine, .build = shrineMesh, .bound = 2.8, .top = 2.5, .view = 240, .parts = circleParts(0.72, 1.9), .light = .{ .y = 1.20, .col = v3(0.40, 0.22, 0.09), .radius = 5.0, .flicker = 0.30 } },
    .{ .kind = .lantern, .build = lanternMesh, .bound = 3.4, .top = 3.1, .view = 230, .parts = circleParts(0.17, 3.0), .light = .{ .y = 2.62, .col = v3(0.46, 0.28, 0.12), .radius = 8.0, .flicker = 0.12 } },
    .{ .kind = .fence, .build = fenceMesh, .bound = 3.6, .top = 1.25, .view = 180, .parts = &.{.{ .ax = -3.0, .bx = 3.0, .r = 0.16, .h = 1.25 }} },
    .{ .kind = .barrels, .build = barrelsMesh, .bound = 1.8, .top = 1.35, .view = 170, .parts = circleParts(0.78, 1.2) },
    .{ .kind = .woodpile, .build = woodpileMesh, .bound = 2.4, .top = 1.35, .view = 180, .parts = &.{.{ .ax = -1.25, .bx = 1.25, .r = 0.62, .h = 1.3 }} },
    .{ .kind = .bones, .build = bonesMesh, .bound = 1.6, .top = 0.55, .view = 140 },
    .{ .kind = .sarcophagus, .build = sarcophagusMesh, .bound = 2.4, .top = 1.05, .view = 200, .parts = &.{.{ .ax = -0.95, .bx = 0.95, .r = 0.72, .h = 1.0 }} },
    .{ .kind = .stairs, .build = stairsMesh, .bound = 2.8, .top = 1.5, .view = 190, .parts = &.{.{ .ax = -1.3, .bx = 1.3, .r = 0.95, .h = 1.4 }} },
    .{ .kind = .gibbet, .build = gibbetMesh, .bound = 4.4, .top = 4.1, .view = 220, .parts = circleParts(0.24, 4.0) },
    .{ .kind = .cairn, .build = cairnMesh, .bound = 1.8, .top = 1.5, .view = 180, .parts = circleParts(0.52, 1.4) },
    // ── more rock ──
    .{ .kind = .outcrop, .build = outcropMesh, .bound = 3.4, .top = 1.1, .view = 200, .parts = &.{.{ .ax = -1.4, .bx = 1.4, .r = 1.1, .h = 1.05 }} },
    .{ .kind = .scree, .build = screeMesh, .bound = 2.6, .top = 0.35, .view = 160 },
    // Fire INTENSITIES are deliberately modest. At ~1.0 four torches in one room summed past the
    // sun's own key and flattened the chapel interior to a uniform warm beige — a lit room with no
    // form left in it. A fire should pool: bright at the flame, falling off into darkness.
    // …and their RADII are small. A 9 m torch inside a 5x7 m chapel reaches every surface in the
    // room from every corner, so four of them summed to a flat uniform wash no matter how dim each
    // one was. 6 m makes each torch a POOL with darkness between them, which is the whole point.
    .{ .kind = .torch, .build = torchMesh, .bound = 2.6, .top = 2.35, .view = 200, .parts = circleParts(0.18, 2.0), .light = .{ .y = 1.98, .col = v3(0.62, 0.33, 0.12), .radius = 6.0, .flicker = 0.22 } },
    .{ .kind = .brazier, .build = brazierMesh, .bound = 1.9, .top = 1.55, .view = 210, .parts = circleParts(0.50, 1.2), .light = .{ .y = 1.14, .col = v3(0.70, 0.38, 0.13), .radius = 13.0, .flicker = 0.20 } },
    .{ .kind = .campfire, .build = campfireMesh, .bound = 1.5, .top = 1.0, .view = 200, .parts = circleParts(0.45, 0.5), .light = .{ .y = 0.52, .col = v3(0.72, 0.35, 0.11), .radius = 11.0, .flicker = 0.28 } },
    // The tarn sheet: wadeable (no parts — owner's call, there is no swim and an invisible wall
    // on open water feels worse than shallow water) and NOT a caster (a flat film casts nothing,
    // and putting it in the shadow map would only shadow the lakebed it is sitting on).
    .{ .kind = .water, .build = waterMesh, .bound = 30.0, .top = 0.1, .view = FAR, .casts = false },
    // ── flora ──
    .{ .kind = .tuft, .build = tuftMesh, .bound = 0.9, .top = 0.8, .view = 85, .flora = true, .casts = false },
    .{ .kind = .patch, .build = patchMesh, .bound = 2.2, .top = 0.8, .view = 95, .flora = true, .casts = false },
    .{ .kind = .shrub, .build = shrubMesh, .bound = 1.2, .top = 0.75, .view = 115, .flora = true, .casts = false },
    .{ .kind = .flowers, .build = flowersMesh, .bound = 1.0, .top = 0.5, .view = 90, .flora = true, .casts = false },
    .{ .kind = .reeds, .build = reedsMesh, .bound = 1.6, .top = 1.35, .view = 130, .flora = true, .casts = false },
    .{ .kind = .glow, .build = glowMesh, .bound = 1.0, .top = 0.55, .view = 140, .flora = true, .casts = false },
    .{ .kind = .bush, .build = bushMesh, .bound = 1.8, .top = 1.25, .view = 130, .flora = true, .casts = false },
    .{ .kind = .bramble, .build = brambleMesh, .bound = 1.9, .top = 0.9, .view = 120, .flora = true, .casts = false },
    .{ .kind = .fern, .build = fernMesh, .bound = 1.3, .top = 0.8, .view = 105, .flora = true, .casts = false },
    // ── the lush layer ── the ground cover that turns a field into a meadow. All flora: no
    // shadow-map entry (thin geometry sparkles in it) and all of it sways.
    // GROUND-HUGGERS get SHORT view distances. They are the bulk of a lush world by count, and a
    // 20 cm mat contributes nothing past 60 m but costs a draw call all the same — trimming these
    // is where the density budget comes from.
    .{ .kind = .grasstall, .build = grassTallMesh, .bound = 1.4, .top = 1.2, .view = 90, .flora = true, .casts = false },
    .{ .kind = .clover, .build = cloverMesh, .bound = 1.5, .top = 0.22, .view = 58, .flora = true, .casts = false },
    .{ .kind = .moss, .build = mossMesh, .bound = 1.7, .top = 0.18, .view = 58, .flora = true, .casts = false },
    .{ .kind = .mushrooms, .build = mushroomsMesh, .bound = 0.9, .top = 0.45, .view = 62, .flora = true, .casts = false },
    .{ .kind = .nettles, .build = nettlesMesh, .bound = 1.5, .top = 0.95, .view = 110, .flora = true, .casts = false },
    .{ .kind = .thistle, .build = thistleMesh, .bound = 1.3, .top = 1.05, .view = 110, .flora = true, .casts = false },
    .{ .kind = .foxglove, .build = foxgloveMesh, .bound = 1.6, .top = 1.3, .view = 120, .flora = true, .casts = false },
    .{ .kind = .heather, .build = heatherMesh, .bound = 1.6, .top = 0.55, .view = 105, .flora = true, .casts = false },
    .{ .kind = .gorse, .build = gorseMesh, .bound = 1.8, .top = 1.15, .view = 125, .flora = true, .casts = false },
    .{ .kind = .cattails, .build = cattailsMesh, .bound = 2.0, .top = 1.75, .view = 140, .flora = true, .casts = false },
    .{ .kind = .lilypads, .build = lilypadsMesh, .bound = 2.4, .top = 0.16, .view = 115, .flora = true, .casts = false },
    .{ .kind = .bracken, .build = brackenMesh, .bound = 1.7, .top = 0.75, .view = 105, .flora = true, .casts = false },
    .{ .kind = .thicket, .build = thicketMesh, .bound = 2.8, .top = 1.9, .view = 160, .flora = true, .casts = false },
    .{ .kind = .wildflowers, .build = wildflowersMesh, .bound = 1.5, .top = 0.65, .view = 105, .flora = true, .casts = false },
    .{ .kind = .ivy, .build = ivyMesh, .bound = 2.4, .top = 2.0, .view = 150, .flora = true, .casts = false },
    // Great trees CAST (they are half the western skyline) and therefore do NOT sway — the
    // depth pass has no wind term, so a swaying caster's shadow would crawl away from it.
    // Three variants: one mesh repeated sixty times across a wood reads as sixty copies.
    .{ .kind = .bigtree, .build = bigTree1, .bound = 13.5, .top = 11.0, .view = FAR, .parts = circleParts(0.95, 6.0) },
    .{ .kind = .bigtree2, .build = bigTree2, .bound = 13.0, .top = 8.5, .view = FAR, .parts = circleParts(0.95, 5.0) },
    .{ .kind = .bigtree3, .build = bigTree3, .bound = 14.0, .top = 13.5, .view = FAR, .parts = circleParts(0.90, 6.5) },
    .{ .kind = .willow, .build = willowMesh, .bound = 8.0, .top = 7.1, .view = 300, .parts = circleParts(0.72, 4.4) },
    .{ .kind = .conifer, .build = coniferMesh, .bound = 12.5, .top = 12.0, .view = FAR, .parts = circleParts(0.58, 5.0) },
    .{ .kind = .birch, .build = birchMesh, .bound = 10.0, .top = 9.4, .view = 340, .parts = circleParts(0.44, 5.0) },
    .{ .kind = .snag, .build = snagMesh, .bound = 8.2, .top = 7.8, .view = 320, .parts = circleParts(0.42, 6.0) },
    // A sapling CASTS (it is 3 m of tree, and a 3 m thing with no shadow reads as a decal) and so
    // must not sway — the depth pass has no wind term.
    .{ .kind = .sapling, .build = saplingMesh, .bound = 3.8, .top = 3.4, .view = 220, .parts = circleParts(0.16, 2.2) },
};

pub fn info(k: Kind) *const Info {
    return &INFO[@intFromEnum(k)];
}

comptime {
    // Every row must sit at its own kind's index — a positional table silently desyncs the
    // moment either side is reordered, and the symptom (a chapel with a grass tuft's colliders)
    // is far from the cause.
    for (INFO, 0..) |row, i| std.debug.assert(@intFromEnum(row.kind) == i);
    // A bound smaller than the mesh pops geometry at the frustum edge; catch the obvious cases.
    for (INFO) |row| std.debug.assert(row.bound >= row.top);
    for (INFO) |row| std.debug.assert(!(row.flora and row.casts)); // flora must stay out of the shadow map
}

// The watchtower's collider ring: 11 of 14 positions around the drum, the other 3 left open as
// the doorway. Generated so it can't drift from the masonry the mesh actually lays down (both
// read TOWER_R / TOWER_SIDES / TOWER_DOOR).
const TOWER_R: f32 = 2.35; // wall centre-line radius
const TOWER_SIDES: i32 = 14;
const TOWER_DOOR: i32 = 3; // masonry columns omitted for the door, centred on local −Z (index 0)
const towerRing = blk: {
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
fn towerDoorway(i: i32) bool {
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
const Course = struct {
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

fn courseInto(bb: *Builder, r: *mathx.Rng, ax: f32, az: f32, bx: f32, bz: f32, spec: Course) void {
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
fn courseStack(bb: *Builder, r: *mathx.Rng, cx: f32, y0: f32, cz: f32, w: f32, d: f32, ch: f32, n: i32, taper: f32) f32 {
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
            // course being the darkest stone was a zebra. Now it only tends dark.
            if (@mod(i, 2) == 0 and r.float() < 0.55) STONE_DK else if (r.float() < 0.16) STONE_LT else STONE,
        );
        y += ch;
    }
    return y;
}

/// Alternating corner QUOINS up an edge — long/short blocks tying two faces together. What
/// stops a course-stacked mass reading as a stack of pancakes.
fn quoinsInto(bb: *Builder, r: *mathx.Rng, cx: f32, cz: f32, y0: f32, ch: f32, n: i32, big: f32, small: f32) void {
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
fn lichenInto(bb: *Builder, r: *mathx.Rng, c: rl.Vector3, ext: rl.Vector3, n: i32) void {
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
fn chipsInto(bb: *Builder, r: *mathx.Rng, cx: f32, cz: f32, spread: f32, lo: f32, hi: f32, n: i32) void {
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
fn crackInto(bb: *Builder, a: rl.Vector3, dir: rl.Vector3, side: rl.Vector3, len: f32, w: f32, into: f32) void {
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

// ── the original ruined-kingdom set ────────────────────────────────────────────────────

fn pillarWhole(shader: rl.Shader) rl.Model {
    return pillarMesh(shader, false);
}
fn pillarBroken(shader: rl.Shader) rl.Model {
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
fn pillarMesh(shader: rl.Shader, broken: bool) rl.Model {
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
fn blockMesh(shader: rl.Shader) rl.Model {
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
fn archMesh(shader: rl.Shader) rl.Model {
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
    lichenInto(&b, &rng, v3(rng.signed() * 1.6, spring + px * 0.55, 0.0), v3(0.5, 0.5, 0.03), 4); // the damp soffit
    return b.toModel(shader);
}

// A ruined WALL run — the city perimeter and the downs' boundaries, so more of these are drawn
// than of anything else built by hand. Laid course by course over a packed core, in THREE spans
// of different height so the top line BREAKS: one shoulder-high with a surviving merlon, one
// worn to waist, one collapsed to a stub. A wall with a level top is a fence.
fn wallMesh(shader: rl.Shader) rl.Model {
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

// A DEAD TREE — the Lands Between silhouette against the haze, and the most repeated tree in
// the world. Everything it has is SILHOUETTE, because it has no leaves to hide behind: a bent
// bole with the bark peeling, a split up one side, branches that fork TWICE (fork once and it
// reads as a garden fork stuck in the ground), bracket fungus, and a root flare lifted on one
// side where the ground gave.
fn treeMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4806);
    b.setMat(.wood);
    const bend = v3(rng.range(0.08, 0.24), 0, rng.signed() * 0.14);
    const j1 = v3(bend.x, 1.70, bend.z);
    const j2 = v3(bend.x * 2.8, 3.05, bend.z * 2.4);
    b.addCapsule(v3(0, 0, 0), j1, 0.26, 0.165, 8, BARK);
    b.addCapsule(j1, j2, 0.165, 0.095, 7, BARK);
    b.addCapsule(j2, v3(j2.x + rng.signed() * 0.3, 4.05, j2.z + rng.signed() * 0.25), 0.095, 0.012, 6, BARK_DK); // the snapped leader
    // PEELING BARK: slim strips up the bole, a couple standing away from it. Those vertical
    // breaks are what stop the trunk reading as a smooth dowel under the low sun.
    var s: i32 = 0;
    while (s < 7) : (s += 1) {
        const a = rng.angle();
        const y0 = rng.range(0.05, 1.1);
        const y1 = y0 + rng.range(0.5, 1.5);
        const r0 = 0.235 - 0.055 * y0;
        const r1 = 0.235 - 0.055 * y1;
        const lift: f32 = if (rng.float() < 0.3) rng.range(0.04, 0.10) else 0.0; // one has come away
        b.addCylinder(
            v3(bend.x * (y0 / 1.7) + mathx.cosf(a) * (r0 + lift), y0, bend.z * (y0 / 1.7) + mathx.sinf(a) * (r0 + lift)),
            v3(bend.x * (y1 / 1.7) + mathx.cosf(a + rng.signed() * 0.2) * (r1 + lift * 1.6), y1, bend.z * (y1 / 1.7) + mathx.sinf(a + rng.signed() * 0.2) * (r1 + lift * 1.6)),
            rng.range(0.030, 0.055),
            rng.range(0.018, 0.040),
            4,
            if (rng.float() < 0.45) BARK_DK else BARK_OLD,
        );
    }
    // A SPLIT up the heartwood, and the hollow where a limb rotted out of it.
    crackInto(&b, v3(mathx.cosf(1.9) * 0.22, 0.30, mathx.sinf(1.9) * 0.22), v3(0.06, 0.99, 0.02), v3(-mathx.sinf(1.9), 0, mathx.cosf(1.9)), rng.range(0.9, 1.5), 0.026, 0.05);
    b.setMat(.wood);
    b.addBlob(v3(bend.x * 0.7 + 0.20, 1.25, bend.z * 0.7 - 0.06), v3(0.09, 0.14, 0.09), 3, 6, IRON); // the rot hollow, dark
    // BRANCHES, each forking again — six primaries off the two joints, two or three twigs each.
    var br: i32 = 0;
    while (br < 6) : (br += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(br)) / 6.0 + rng.signed() * 0.6;
        const from = if (rng.float() < 0.45) j1 else j2;
        const out = rng.range(0.8, 1.55);
        const up = rng.range(0.5, 1.15);
        const tip = v3(from.x + mathx.cosf(a) * out, from.y + up, from.z + mathx.sinf(a) * out);
        b.addCapsule(from, tip, rng.range(0.055, 0.085), rng.range(0.014, 0.026), 5, BARK_DK);
        const nt: i32 = 2 + rng.intn(2);
        var t: i32 = 0;
        while (t < nt) : (t += 1) {
            const ta = a + rng.signed() * 1.3;
            const tl = rng.range(0.35, 0.85);
            b.addCapsule(
                v3(from.x + (tip.x - from.x) * rng.range(0.5, 0.9), from.y + (tip.y - from.y) * rng.range(0.5, 0.9), from.z + (tip.z - from.z) * rng.range(0.5, 0.9)),
                v3(tip.x + mathx.cosf(ta) * tl, tip.y + rng.range(0.1, 0.65), tip.z + mathx.sinf(ta) * tl),
                0.026,
                0.006,
                4,
                BARK_DK,
            );
        }
    }
    // ROOT FLARE: five roots splaying onto the ground, one LIFTED where the earth gave under it.
    var r: i32 = 0;
    while (r < 5) : (r += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(r)) / 5.0 + rng.signed() * 0.35;
        const d = rng.range(0.42, 0.72);
        const heave: f32 = if (r == 2) rng.range(0.14, 0.26) else 0.0;
        b.addCapsule(v3(0, 0.26, 0), v3(mathx.cosf(a) * d, 0.02 + heave, mathx.sinf(a) * d), rng.range(0.09, 0.13), rng.range(0.025, 0.05), 5, BARK);
    }
    // BRACKET FUNGUS on the shaded side: a dead trunk with fungus has been dead for years; one
    // without has been dead since Tuesday.
    b.setMat(.plant);
    const fa = rng.angle();
    b.addBlob(v3(mathx.cosf(fa) * 0.24, rng.range(0.7, 1.5), mathx.sinf(fa) * 0.24), v3(0.17, 0.035, 0.14), 3, 6, CAP_BROWN);
    b.addBlob(v3(mathx.cosf(fa + 0.5) * 0.21, rng.range(0.4, 1.0), mathx.sinf(fa + 0.5) * 0.21), v3(0.11, 0.028, 0.10), 3, 5, CAP_PALE);
    lichenInto(&b, &rng, v3(mathx.cosf(fa + 3.0) * 0.20, rng.range(0.5, 1.6), mathx.sinf(fa + 3.0) * 0.20), v3(0.10, 0.34, 0.10), 3);
    tuftInto(&b, &rng, rng.signed() * 0.8, rng.signed() * 0.8, 0.8);
    tuftInto(&b, &rng, rng.signed() * 1.0, rng.signed() * 1.0, 0.62);
    return b.toModel(shader);
}

// A GRAVE CLUSTER — a family plot the wood took back. Six markers of FOUR kinds (round-topped
// headstone, a cross with an arm gone, a ledger slab sunk into the turf, a stumpy footstone),
// each leaning its own way and sunk to its own depth. What sells a graveyard is that no two
// stones share a shape or an angle; matched slabs read as a municipal cemetery.
fn gravesMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4807);
    const spots = [_][2]f32{ .{ 0, 0 }, .{ 0.95, -0.55 }, .{ -0.85, 0.42 }, .{ 1.62, 0.38 }, .{ -0.35, -0.95 }, .{ 0.55, 0.95 } };
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
    lichenInto(&b, &rng, v3(rng.signed() * 0.7, rng.range(0.2, 0.55), rng.signed() * 0.5), v3(0.13, 0.12, 0.02), 4);
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
fn swordMesh(shader: rl.Shader) rl.Model {
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
fn graceMesh(shader: rl.Shader) rl.Model {
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
fn towerMesh(shader: rl.Shader) rl.Model {
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
fn gateMesh(shader: rl.Shader) rl.Model {
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
fn bannerMesh(shader: rl.Shader) rl.Model {
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
fn statueMesh(shader: rl.Shader) rl.Model {
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
fn rubbleMesh(shader: rl.Shader) rl.Model {
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
    // Two angular pieces that broke recently enough to still have corners on them.
    var g: i32 = 0;
    while (g < 2) : (g += 1) {
        const a = rng.angle();
        const d = rng.range(0.3, 0.9);
        const s = rng.range(0.16, 0.30);
        b.addBox(
            v3(mathx.cosf(a) * d, s * 0.55, mathx.sinf(a) * d),
            v3(s, rng.signed() * 0.12, 0.03),
            v3(rng.signed() * 0.1, s * 0.62, 0),
            v3(0, 0, s * rng.range(0.6, 1.1)),
            STONE,
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
const CliffKind = struct {
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

fn cliff1(shader: rl.Shader) rl.Model {
    return cliffMesh(shader, 90210, CLIFF_ROUND);
}
fn cliff2(shader: rl.Shader) rl.Model {
    return cliffMesh(shader, 90277, CLIFF_BLOCKY);
}
fn cliff3(shader: rl.Shader) rl.Model {
    return cliffMesh(shader, 90341, CLIFF_RAGGED);
}
fn cliff4(shader: rl.Shader) rl.Model {
    return cliffMesh(shader, 90407, CLIFF_IVIED);
}
fn cliff5(shader: rl.Shader) rl.Model {
    return cliffMesh(shader, 90473, CLIFF_SHATTERED);
}
fn cliff6(shader: rl.Shader) rl.Model {
    return cliffMesh(shader, 90539, CLIFF_OVERGROWN);
}

/// One rock body of a cliff segment — an ellipsoid, as `addBlob` builds it.
const CliffBody = struct { x: f32, y: f32, z: f32, rx: f32, ry: f32, rz: f32 };

/// The FRONTMOST rock surface at (x, y): the smallest z any of the segment's bodies reaches there,
/// or null when no body covers the point at all — in which case nothing gets placed, which is the
/// whole point. This is what lets the creeper follow the rock's curve and the collapse scar sit ON
/// the face instead of both being hung on a guessed depth plane.
///
/// `q <= 0.04` skips a body the point is outside of, and also the very rim of one, where the
/// ellipsoid is edge-on: the surface there is nearly parallel to the view and anything anchored to
/// it reads as sticking out sideways.
fn cliffFaceZ(bs: []const CliffBody, x: f32, y: f32) ?f32 {
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
fn cliffSeatZ(bs: []const CliffBody, x: f32, y: f32, halfW: f32, halfH: f32) ?f32 {
    var back = cliffFaceZ(bs, x, y) orelse return null;
    for ([_]f32{ -1, 0, 1 }) |dx| {
        for ([_]f32{ -1, 0, 1 }) |dy| {
            const z = cliffFaceZ(bs, x + dx * halfW, y + dy * halfH) orelse continue;
            if (z > back) back = z;
        }
    }
    return back;
}

fn cliffMesh(shader: rl.Shader, seed: u64, k: CliffKind) rl.Model {
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
fn boulderMesh(shader: rl.Shader) rl.Model {
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
fn rocksMesh(shader: rl.Shader) rl.Model {
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
fn monolithMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(606);
    b.setMat(.stone);
    const lean = v3(rng.signed() * 0.30, 4.55, rng.signed() * 0.24);
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
    // Carved bands: three shallow inset courses, unevenly spaced (a mason's hand, not a ruler).
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const t = 0.28 + 0.22 * @as(f32, @floatFromInt(i)) + rng.signed() * 0.03;
        b.addBox(v3(lean.x * t, lean.y * t, lean.z * t), v3(0.60, 0, 0), v3(0, 0.055, 0), v3(0, 0, 0.42), CLIFF_DK);
    }
    b.setMat(.plant);
    b.addBlob(v3(lean.x * 0.25 - 0.42, 0.75, lean.z * 0.25), v3(0.16, 0.55, 0.30), 3, 5, STONE_MOSS); // lichen streak
    b.addBlob(v3(0, 0.10, 0), v3(0.85, 0.10, 0.75), 3, 6, SCRUB_DK); // grass swallowing the base
    return b.toModel(shader);
}

// ── TIMBER ──

// A broken stump: splintered barrel, a couple of standing splinters, root flare, and a
// mossy cap where the heartwood is rotting out.
fn stumpMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(313);
    b.setMat(.wood);
    b.addCapsule(v3(0, 0, 0), v3(rng.signed() * 0.08, 1.05, rng.signed() * 0.08), 0.46, 0.40, 8, BARK);
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.12, 0.32);
        b.addBox(
            v3(mathx.cosf(a) * d, 1.12 + rng.range(0.0, 0.13), mathx.sinf(a) * d),
            v3(rng.range(0.05, 0.12), 0, 0),
            v3(rng.signed() * 0.05, rng.range(0.06, 0.20), rng.signed() * 0.05),
            v3(0, 0, rng.range(0.05, 0.11)),
            BARK_DK,
        );
    }
    var r: i32 = 0;
    while (r < 4) : (r += 1) {
        const a = rng.angle();
        b.addCapsule(v3(0, 0.30, 0), v3(mathx.cosf(a) * 0.72, 0.02, mathx.sinf(a) * 0.72), 0.15, 0.05, 5, BARK);
    }
    b.setMat(.plant);
    b.addBlob(v3(0, 1.06, 0), v3(0.34, 0.09, 0.32), 3, 6, STONE_MOSS);
    return b.toModel(shader);
}

// A fallen trunk gone over in some old storm: one long tapered barrel lying along local X,
// stubs of snapped branches, a torn root plate at the butt, moss along the upper face.
fn logMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(818);
    b.setMat(.wood);
    b.addCapsule(v3(-1.85, 0.36, rng.signed() * 0.1), v3(1.9, 0.30, rng.signed() * 0.12), 0.36, 0.25, 8, BARK);
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const x = rng.range(-1.5, 1.6);
        const a = rng.angle();
        b.addCapsule(v3(x, 0.34, 0), v3(x + rng.signed() * 0.35, 0.34 + @abs(mathx.sinf(a)) * 0.45, mathx.cosf(a) * 0.62), 0.075, 0.02, 5, BARK_DK);
    }
    // The root plate: a torn disc of roots and clung earth standing up at the butt end.
    var r: i32 = 0;
    while (r < 5) : (r += 1) {
        const a = rng.angle();
        b.addCapsule(v3(-1.85, 0.34, 0), v3(-2.05 + rng.signed() * 0.1, 0.34 + mathx.sinf(a) * 0.55, mathx.cosf(a) * 0.55), 0.10, 0.03, 5, BARK_DK);
    }
    b.setMat(.plant);
    b.addBlob(v3(rng.range(-1.0, 0.6), 0.62, 0), v3(0.55, 0.10, 0.24), 3, 6, STONE_MOSS);
    b.addBlob(v3(rng.range(0.2, 1.4), 0.60, 0.05), v3(0.34, 0.09, 0.22), 3, 6, SCRUB_DK);
    tuftInto(&b, &rng, rng.range(-1.2, 1.2), rng.signed() * 0.55, 0.7);
    return b.toModel(shader);
}

// ── STRUCTURES YOU ENTER ── these are the reason point lights exist: a roof stops the sun
// dead, and without a torch inside the room is a black hole.

// A ruined wayside CHAPEL: 5 x 7 m nave with a doorway in the south wall, window openings
// down both sides, an altar at the north end, two rows of stub columns, and a broken roof
// that still covers the northern half — so the altar end sits in real darkness and the
// torches (placed as separate props by env) are what let you see it.
fn chapelMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(5150);
    b.setMat(.stone);
    const hw: f32 = 2.6; // wall centre-lines
    const hl: f32 = 3.6;
    const wt: f32 = 0.42; // wall half-thickness
    const wh: f32 = 4.4; // wall height

    // Flagstone floor, a hair proud of the terrain so the interior reads as a built surface.
    b.addCube(v3(0, 0.06, 0), v3(2 * hw + 0.5, 0.12, 2 * hl + 0.5), STONE_DK);
    var fx: i32 = 0;
    while (fx < 4) : (fx += 1) {
        var fz: i32 = 0;
        while (fz < 6) : (fz += 1) {
            const x = (@as(f32, @floatFromInt(fx)) - 1.5) * 1.28;
            const z = (@as(f32, @floatFromInt(fz)) - 2.5) * 1.20;
            if (rng.float() < 0.18) continue; // stones lifted / lost
            b.addCube(v3(x + rng.signed() * 0.05, 0.13, z + rng.signed() * 0.05), v3(rng.range(1.0, 1.2), 0.06, rng.range(0.95, 1.14)), if (rng.float() < 0.4) STONE else STONE_DK);
        }
    }
    // The four walls, laid course by course by the shared masonry builder (`courseInto`).
    // South wall with the DOORWAY (a 2.3 m opening, full height to a lintel at 2.9).
    courseInto(&b, &rng, -hw, -hl, hw, -hl, .{ .thick = wt, .height = wh, .gapLo = -1.15, .gapHi = 1.15, .sillY = -0.1, .headY = 2.9 });
    b.addCube(v3(0, 3.05, -hl), v3(2.9, 0.30, 2 * wt + 0.06), STONE_LT); // door lintel
    // North (altar) wall, unbroken but for a high slot window.
    courseInto(&b, &rng, -hw, hl, hw, hl, .{ .thick = wt, .height = wh, .gapLo = -0.45, .gapHi = 0.45, .sillY = 2.5, .headY = 3.7 });
    // Side walls, each with a window opening set off-centre from the other (wabi-sabi).
    courseInto(&b, &rng, -hw, -hl, -hw, hl, .{ .thick = wt, .height = wh, .gapLo = -0.7, .gapHi = 0.8, .sillY = 1.5, .headY = 3.1 });
    courseInto(&b, &rng, hw, -hl, hw, hl, .{ .thick = wt, .height = wh, .gapLo = 0.2, .gapHi = 1.7, .sillY = 1.6, .headY = 3.2 });
    // Corner quoins tie the runs together (four bare wall ends read as a flat-pack kit).
    for ([_]f32{ -hw, hw }) |cx| {
        for ([_]f32{ -hl, hl }) |cz| {
            var c: i32 = 0;
            while (c < 5) : (c += 1) {
                const yy = 0.3 + @as(f32, @floatFromInt(c)) * 0.95;
                if (yy > wh) break;
                b.addCube(v3(cx, yy, cz), v3(1.0 + rng.signed() * 0.06, 0.62, 1.0 + rng.signed() * 0.06), if (@mod(c, 2) == 0) STONE else STONE_DK);
            }
        }
    }
    // The ROOF over the northern half only: rafters plus sloped slabs, with the southern
    // rafters left bare and snapped. This is what makes the altar end dark.
    var rf: i32 = 0;
    while (rf < 7) : (rf += 1) {
        const z = -hl + 0.55 + @as(f32, @floatFromInt(rf)) * 1.05;
        b.setMat(.wood);
        b.addBox(v3(0, wh + 0.55, z), v3(hw + 0.15, -0.42, 0), v3(0, 0.10, 0), v3(0, 0, 0.10), TIMBER_DK); // a rafter, both slopes
        b.addBox(v3(0, wh + 0.55, z), v3(hw + 0.15, 0.42, 0), v3(0, 0.10, 0), v3(0, 0, 0.10), TIMBER_DK);
        if (z < -1.3) continue; // the south end has lost its covering; the altar two thirds keeps it
        b.setMat(.stone);
        for ([_]f32{ -1, 1 }) |sgn| {
            b.addBox(
                v3(sgn * (hw * 0.52), wh + 0.30, z),
                v3(sgn * hw * 0.56, 0.48, 0),
                v3(0, 0.09, 0),
                v3(0, 0, 0.55 * rng.range(0.94, 1.04)),
                if (rng.float() < 0.3) STONE_DK else STONE,
            );
        }
    }
    b.setMat(.stone);
    // The altar: a heavy slab on two blocks, chipped, with a stone bowl worn hollow.
    b.addCube(v3(0, 0.55, 2.9), v3(2.5, 0.85, 1.0), STONE_DK);
    b.addCube(v3(0, 1.02, 2.9), v3(2.9, 0.20, 1.25), STONE_LT);
    b.addCylinder(v3(0.65, 1.12, 2.9), v3(0.65, 1.34, 2.9), 0.26, 0.30, 8, STONE);
    b.addCube(v3(-0.75, 1.20, 2.86), v3(0.35, 0.16, 0.35), STONE_DK); // a fallen fragment on the mensa
    // Two rows of stub columns down the nave — most snapped, one still carrying a capital.
    for ([_]f32{ -1.55, 1.55 }) |cx| {
        var ci: i32 = 0;
        while (ci < 3) : (ci += 1) {
            const z = -1.9 + @as(f32, @floatFromInt(ci)) * 1.9;
            const h = rng.range(1.1, 2.4);
            b.addCylinder(v3(cx, 0.16, z), v3(cx + rng.signed() * 0.04, 0.16 + h, z), 0.24, 0.21, 8, STONE);
            if (rng.float() < 0.4) b.addCube(v3(cx, 0.16 + h + 0.08, z), v3(0.6, 0.16, 0.6), STONE_LT);
        }
    }
    // Fallen masonry across the floor, and the roof slabs that came down with it.
    var d: i32 = 0;
    while (d < 9) : (d += 1) {
        const x = rng.range(-hw + 0.5, hw - 0.5);
        const z = rng.range(-hl + 0.6, hl - 0.8);
        const s = rng.range(0.22, 0.62);
        b.addBox(v3(x, 0.16 + s * 0.4, z), v3(s, 0, rng.signed() * 0.1), v3(rng.signed() * 0.08, s * 0.42, 0), v3(0, 0, s * rng.range(0.5, 1.0)), if (rng.float() < 0.4) STONE_MOSS else STONE_DK);
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, -1.9, -2.6, 0.8); // grass coming up through the floor
    tuftInto(&b, &rng, 2.0, 0.4, 0.7);
    return b.toModel(shader);
}

// A WATCHTOWER: a masonry drum you can walk into, built as real courses of blocks (a bare
// cylinder is a shell — from inside you would see straight through its culled back faces),
// with a doorway on local −Z, arrow slits above, a timber floor overhead that keeps the
// ground room dark, and a broken crenellated crown.
fn watchtowerMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(7788);
    b.setMat(.stone);
    const sides: i32 = TOWER_SIDES;
    const R: f32 = TOWER_R;
    const courses: i32 = 15;
    const ch: f32 = 0.76;
    // A block on the drum at angle `a`: its RADIAL axis is (sin a, 0, −cos a) — the direction of
    // the position itself — and its TANGENTIAL axis must be perpendicular to that, which is
    // (cos a, 0, sin a). Getting the tangent's z sign wrong (an easy −sin a) makes every block a
    // SKEWED parallelepiped instead of a masonry unit, and the drum ends up with gaps you can see
    // daylight through. addBox happily builds the skewed version, so nothing complains.
    const radial = struct {
        fn v(a: f32, len: f32) rl.Vector3 {
            return v3(mathx.sinf(a) * len, 0, -mathx.cosf(a) * len);
        }
    }.v;
    const tangent = struct {
        fn v(a: f32, len: f32) rl.Vector3 {
            return v3(mathx.cosf(a) * len, 0, mathx.sinf(a) * len);
        }
    }.v;
    // Splayed plinth — a tower that meets the ground at a right angle reads as pasted on.
    var p: i32 = 0;
    while (p < sides) : (p += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(p)) / @as(f32, @floatFromInt(sides));
        const base = radial(a, R + 0.28);
        b.addBox(v3(base.x, 0.22, base.z), tangent(a, 0.58), v3(0, 0.22, 0), radial(a, 0.42), STONE_DK);
    }
    // THE CORE: wide dark blocks bedded inside the facing, offset half a block so the joints
    // never line up. Without it every gap in the drum shows daylight — or the far wall of the
    // room — and the tower reads as a palisade of loose stones.
    var cr: i32 = 0;
    while (cr < 12) : (cr += 1) {
        var ci: i32 = 0;
        while (ci < sides) : (ci += 1) {
            if (cr < 4 and towerDoorway(ci)) continue; // the core dodges the doorway too
            const a = std.math.tau * (@as(f32, @floatFromInt(ci)) + 0.5) / @as(f32, @floatFromInt(sides));
            const at = radial(a, R);
            b.addBox(
                v3(at.x, 0.44 + (@as(f32, @floatFromInt(cr)) + 0.5) * ch * 1.25, at.z),
                tangent(a, std.math.tau * R / @as(f32, @floatFromInt(sides)) * 0.80),
                v3(0, ch * 0.66, 0),
                radial(a, 0.24),
                MORTAR,
            );
        }
    }
    var c: i32 = 0;
    while (c < courses) : (c += 1) {
        const yc = 0.44 + (@as(f32, @floatFromInt(c)) + 0.5) * ch;
        // Alternate courses are rotated half a block so the joints stagger like real masonry.
        const skew: f32 = if (@mod(c, 2) == 0) 0.0 else 0.5;
        // Above the 12th course the crown is broken — blocks go missing in runs.
        const crumble: f32 = if (c >= 12) 0.42 else 0.03;
        var i: i32 = 0;
        while (i < sides) : (i += 1) {
            const fi = @as(f32, @floatFromInt(i)) + skew;
            const a = std.math.tau * fi / @as(f32, @floatFromInt(sides));
            // The DOORWAY: three columns omitted for the lowest four courses. Tested on the
            // UNSKEWED index so the opening keeps straight jambs course to course.
            if (c < 4 and towerDoorway(i)) continue;
            // Arrow slits: single columns omitted at two heights, on two different bearings.
            if ((c == 7 or c == 8) and (i == 2 or i == 9)) continue;
            if (rng.float() < crumble) continue;
            const at = radial(a, R);
            const bw = (std.math.tau * R / @as(f32, @floatFromInt(sides))) * rng.range(1.24, 1.52); // blocks OVERLAP their slot
            b.addBox(
                v3(at.x, yc + rng.signed() * 0.02, at.z),
                tangent(a, bw * 0.5),
                v3(0, ch * 0.5 * rng.range(0.95, 1.02), 0),
                radial(a, 0.34),
                if (rng.float() < 0.22) STONE_LT else if (rng.float() < 0.35) STONE_DK else STONE,
            );
        }
    }
    // Door lintel + jambs, so the opening reads as built rather than as missing blocks.
    b.addBox(v3(0, 3.55, -R), v3(1.30, 0, 0), v3(0, 0.28, 0), v3(0, 0, 0.42), STONE_LT);
    for ([_]f32{ -1.18, 1.18 }) |jx| b.addBox(v3(jx, 1.85, -R), v3(0.22, 0, 0), v3(0, 1.85, 0), v3(0, 0, 0.40), STONE_DK);
    // Ground-floor slab + the timber floor overhead (the roof of the dark room).
    b.addCylinder(v3(0, 0.02, 0), v3(0, 0.16, 0), R + 0.1, R + 0.1, sides, STONE_DK);
    b.setMat(.wood);
    var pl: i32 = 0;
    while (pl < 8) : (pl += 1) {
        const x = (@as(f32, @floatFromInt(pl)) - 3.5) * 0.60;
        const halfSpan = @sqrt(@max(R * R - x * x, 0.04));
        if (rng.float() < 0.16) continue; // planks fallen through
        b.addCube(v3(x, 4.62, 0), v3(0.56, 0.14, halfSpan * 2.0), if (@mod(pl, 2) == 0) TIMBER else TIMBER_DK);
    }
    b.addCylinder(v3(0, 4.42, 0), v3(0, 4.54, 0), R * 0.94, R * 0.94, sides, TIMBER_DK); // ring beam
    b.setMat(.stone);
    // Crenellations on the surviving arc of the crown.
    var m: i32 = 0;
    while (m < sides) : (m += 1) {
        if (rng.float() < 0.45) continue;
        const a = std.math.tau * @as(f32, @floatFromInt(m)) / @as(f32, @floatFromInt(sides));
        const at = radial(a, R);
        const h = rng.range(0.4, 0.95);
        b.addBox(v3(at.x, 11.9 + h * 0.5, at.z), tangent(a, 0.42), v3(0, h * 0.5, 0), radial(a, 0.34), STONE_DK);
    }
    // Spill of collapsed masonry heaped against one flank.
    var s: i32 = 0;
    while (s < 7) : (s += 1) {
        const a = rng.range(0.6, 2.0);
        const d = rng.range(R + 0.2, R + 1.9);
        const r = rng.range(0.20, 0.55);
        b.addBlob(v3(mathx.sinf(a) * d, r * 0.6, -mathx.cosf(a) * d), v3(r, r * 0.7, r), 3, 5, if (rng.float() < 0.4) STONE_MOSS else STONE_DK);
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, R + 1.0, 0.8, 0.85);
    return b.toModel(shader);
}

// A COTTAGE gone to ruin: three standing walls of rough field stone (the fourth fallen to
// knee height), a gable end, the charred stubs of roof timbers, a chimney breast still
// standing proud, and shreds of thatch caught on the purlins.
fn cottageMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2626);
    b.setMat(.stone);
    const hw: f32 = 2.3;
    const hl: f32 = 1.9;
    // Field-stone walls: rounded stones bedded in a packed core, not cut blocks. The CORE goes
    // first (see the packed-stone note above `courseInto`) or the gaps between rounded stones
    // show daylight; stones then overlap their slot ~35% so they bed instead of butting.
    const run = struct {
        fn go(bb: *Builder, r: *mathx.Rng, ax: f32, az: f32, bx: f32, bz: f32, height: f32, gapLo: f32, gapHi: f32) void {
            const dx = bx - ax;
            const dz = bz - az;
            const L = @sqrt(dx * dx + dz * dz);
            const ux = dx / L;
            const uz = dz / L;
            const openTop: f32 = @min(2.05, height);
            // Substrate, split around the opening: below the sill height it flanks the gap.
            for ([_][2]f32{ .{ -L * 0.5, gapLo }, .{ gapHi, L * 0.5 } }) |sp| {
                const w = @min(sp[1], L * 0.5) - @max(sp[0], -L * 0.5);
                if (w <= 0.02) continue;
                const mid = (@max(sp[0], -L * 0.5) + @min(sp[1], L * 0.5)) * 0.5;
                bb.addBox(
                    v3(ax + ux * (L * 0.5 + mid), openTop * 0.5, az + uz * (L * 0.5 + mid)),
                    v3(ux * w * 0.5, 0, uz * w * 0.5),
                    v3(0, openTop * 0.5, 0),
                    v3(-uz * 0.17, 0, ux * 0.17),
                    MORTAR,
                );
            }
            if (height > openTop + 0.02) { // …and spans the full run above the opening
                bb.addBox(
                    v3(ax + ux * L * 0.5, (openTop + height) * 0.5, az + uz * L * 0.5),
                    v3(ux * L * 0.5, 0, uz * L * 0.5),
                    v3(0, (height - openTop) * 0.5, 0),
                    v3(-uz * 0.17, 0, ux * 0.17),
                    MORTAR,
                );
            }
            var y: f32 = 0.05;
            while (y < height) {
                const ch = r.range(0.24, 0.36);
                var t: f32 = 0.04;
                while (t < 0.98) {
                    const w = r.range(0.26, 0.46);
                    const s = (t - 0.5) * L;
                    if (!(s > gapLo and s < gapHi and y < 2.05)) {
                        bb.addBlob(
                            v3(ax + ux * t * L + r.signed() * 0.04, y + ch * 0.5, az + uz * t * L + r.signed() * 0.04),
                            v3(@abs(ux) * w * 0.68 + @abs(uz) * 0.22 + 0.07, ch * 0.62, @abs(uz) * w * 0.68 + @abs(ux) * 0.22 + 0.07),
                            3,
                            5,
                            if (r.float() < 0.3) STONE_LT else if (r.float() < 0.45) STONE_MOSS else STONE,
                        );
                    }
                    t += w / L * 0.72; // stones OVERLAP; a butted row seams round each one
                }
                y += ch * 0.78;
            }
        }
    }.go;
    run(&b, &rng, -hw, hl, hw, hl, 2.55, 9, 9); // back wall, no opening
    run(&b, &rng, -hw, -hl, -hw, hl, 2.55, -0.4, 0.7); // west wall, window
    run(&b, &rng, hw, -hl, hw, hl, 2.55, 9, 9); // east wall
    run(&b, &rng, -hw, -hl, hw, -hl, 1.15, -0.85, 0.85); // front wall, tumbled + a doorway gap
    // Gable: the back wall carries up to a peak.
    var g: i32 = 0;
    while (g < 5) : (g += 1) {
        const t = @as(f32, @floatFromInt(g)) / 5.0;
        b.addCube(v3(0, 2.6 + t * 1.2, hl), v3((2 * hw) * (1.0 - t) * 0.92, 0.3, 0.42), if (@mod(g, 2) == 0) STONE else STONE_DK);
    }
    // Chimney breast on the gable end, its stack broken off short.
    b.addCube(v3(1.35, 1.7, hl + 0.34), v3(1.1, 3.4, 0.62), STONE_DK);
    b.addCube(v3(1.35, 3.55, hl + 0.34), v3(0.86, 0.5, 0.5), STONE);
    b.addCube(v3(1.35, 0.55, hl - 0.1), v3(0.72, 1.1, 0.5), IRON); // the sooted hearth opening
    // Roof timbers: a ridge and a few surviving rafters, charred.
    b.setMat(.wood);
    b.addCapsule(v3(0, 3.66, hl - 0.1), v3(0, 3.30, -hl + 0.6), 0.10, 0.08, 6, TIMBER_DK);
    var rf: i32 = 0;
    while (rf < 5) : (rf += 1) {
        if (rng.float() < 0.3) continue;
        const z = hl - 0.3 - @as(f32, @floatFromInt(rf)) * 0.85;
        const sgn: f32 = if (@mod(rf, 2) == 0) 1 else -1;
        b.addCapsule(v3(0, 3.5, z), v3(sgn * hw * rng.range(0.7, 1.02), rng.range(2.1, 2.7), z + rng.signed() * 0.2), 0.075, 0.055, 5, TIMBER_DK);
    }
    // Thatch shreds still caught up there — organic, so blobs, not slabs.
    var th: i32 = 0;
    while (th < 5) : (th += 1) {
        b.addBlob(
            v3(rng.range(-1.5, 1.5), rng.range(2.6, 3.3), rng.range(-0.4, hl - 0.2)),
            v3(rng.range(0.3, 0.7), 0.14, rng.range(0.2, 0.45)),
            3,
            5,
            if (rng.float() < 0.5) THATCH else THATCH_DK,
        );
    }
    b.setMat(.stone);
    var d: i32 = 0;
    while (d < 8) : (d += 1) {
        const r = rng.range(0.16, 0.38);
        b.addBlob(v3(rng.range(-hw, hw), r * 0.6, rng.range(-hl - 1.2, hl)), v3(r, r * 0.7, r), 3, 5, if (rng.float() < 0.4) STONE_MOSS else STONE_DK);
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.range(-1.6, 1.6), rng.range(-1.4, 1.2), 0.9);
    tuftInto(&b, &rng, rng.range(-1.6, 1.6), rng.range(-1.4, 1.2), 0.75);
    return b.toModel(shader);
}

// A low stone CAUSEWAY over the tarn's shallows — flat flagstones a hand's breadth above the
// water with kerbs either side, worn, subsiding, one span collapsed into a gap you stride
// over. Deliberately NOT an arched bridge: the world is a flat plane and the hero walks at
// y=0, so a raised deck would be a lie you could walk through.
fn causewayMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3939);
    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 14) : (i += 1) {
        const x = -5.0 + (@as(f32, @floatFromInt(i)) + 0.5) * (10.0 / 14.0);
        if (i == 8 or i == 9) continue; // the collapsed span
        const sink = if (i == 7 or i == 10) rng.range(0.02, 0.06) else 0.0; // slabs slumping toward the gap
        b.addBox(
            v3(x, 0.14 - sink, rng.signed() * 0.05),
            v3(0.36 * rng.range(0.9, 1.1), rng.signed() * 0.012, 0),
            v3(0, 0.13, rng.signed() * 0.02),
            v3(0, 0, 1.35 * rng.range(0.95, 1.02)),
            if (rng.float() < 0.3) STONE_LT else if (rng.float() < 0.5) STONE_MOSS else STONE,
        );
    }
    // Kerb stones, gappy — a few knocked into the water.
    for ([_]f32{ -1.45, 1.45 }) |z| {
        var k: i32 = 0;
        while (k < 16) : (k += 1) {
            if (rng.float() < 0.22) continue;
            const x = -5.0 + (@as(f32, @floatFromInt(k)) + 0.5) * (10.0 / 16.0);
            b.addBox(v3(x, 0.30, z + rng.signed() * 0.04), v3(0.30, rng.signed() * 0.02, 0), v3(0, rng.range(0.14, 0.22), 0), v3(0, 0, 0.22), if (rng.float() < 0.35) STONE_DK else STONE);
        }
    }
    // Fallen kerb + pier stones lying in the shallows around the gap.
    var f: i32 = 0;
    while (f < 6) : (f += 1) {
        const r = rng.range(0.16, 0.34);
        b.addBlob(v3(rng.range(-1.0, 2.4), r * 0.5, rng.range(-2.2, 2.2)), v3(r, r * 0.6, r * 1.1), 3, 5, STONE_DK);
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.range(-4.5, 4.5), 1.75, 0.7); // weeds in the kerb joints
    tuftInto(&b, &rng, rng.range(-4.5, 4.5), -1.75, 0.6);
    return b.toModel(shader);
}

// A patch of worn PAVING — the city's old road surface coming through the grass. Flat, cheap,
// and it is what stops the ruins reading as props dropped on a lawn.
//
// Kept DARK and TIGHT on purpose: the first pass used bright stone spaced out over 2.5 m and
// read as scattered white litter dropped on the field rather than as a buried surface. Paving
// is a road you can just make out, not a feature.
fn pavingMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(1234);
    // THE ROAD BED first — packed earth the setts are laid INTO. Without it the gaps are lit
    // grass, every sett reads as a tile dropped on a lawn, and a street looks like spilled
    // paper. (Packed stone has a substrate; a road is packed stone laid flat.)
    b.setMat(.stone);
    b.addCylinder(v3(0, 0.006, 0), v3(0, 0.020, 0), 2.35, 2.20, 14, SOIL);
    // Worn hollows of bare bed the setts skip round — a road with no holes in it is a road
    // somebody is maintaining.
    var holes: [3][3]f32 = undefined;
    for (&holes) |*h| {
        const a = rng.angle();
        const d = rng.range(0.4, 1.7);
        h.* = .{ mathx.cosf(a) * d, mathx.sinf(a) * d, rng.range(0.30, 0.62) };
    }
    // A ROAD IS LAID, NOT SCATTERED. A random-angle strew of flat boxes reads as tiles dropped
    // on a lawn whatever their size or colour, because every stone shows four edges at its own
    // angle and the eye counts TILES instead of seeing a SURFACE. The fix is the LAYING: a
    // lattice of courses, each row offset half a pitch like brickwork, every sett on the patch's
    // axes with a few degrees of wander. Wabi-sabi still lives in the sizes, cants, tone and the
    // ones that are missing — but the COURSES have to be there, or it is gravel.
    const PITCH: f32 = 0.30;
    const HALFN: i32 = 8; // cells each way from centre — covers the 2.2 m disc
    var gz: i32 = -HALFN;
    while (gz <= HALFN) : (gz += 1) {
        const rowOff: f32 = if (@mod(gz, 2) == 0) 0 else PITCH * 0.5; // the running bond
        var gx: i32 = -HALFN;
        while (gx <= HALFN) : (gx += 1) {
            const px = @as(f32, @floatFromInt(gx)) * PITCH + rowOff + rng.signed() * 0.035;
            const pz = @as(f32, @floatFromInt(gz)) * PITCH + rng.signed() * 0.035;
            if (px * px + pz * pz > 2.2 * 2.2) continue; // keep the patch round
            var lost = rng.float() < 0.07; // the odd sett prised out
            for (holes) |h| {
                const dx = px - h[0];
                const dz = pz - h[1];
                if (dx * dx + dz * dz < h[2] * h[2]) lost = true;
            }
            if (lost) continue;
            const w = PITCH * rng.range(1.02, 1.20); // butted, then some — the joint is a shadow
            const l = PITCH * rng.range(0.95, 1.25);
            const wob = rng.signed() * 0.09; // a few degrees of wander off the course line
            // Setts CANT: frost does not leave a road level, and those tilts are what catch the
            // low sun and make it read as a surface at all.
            b.addBox(
                v3(px, rng.range(0.010, 0.026), pz),
                v3(w * 0.5, rng.signed() * 0.012, wob * w * 0.5),
                v3(0, 0.020, 0),
                v3(-wob * l * 0.5, rng.signed() * 0.010, l * 0.5),
                if (rng.float() < 0.14) STONE_MOSS else if (rng.float() < 0.3) SOIL else if (rng.float() < 0.5) PAVE_LT else if (rng.float() < 0.75) PAVE_DK else PAVE,
            );
        }
    }
    // A CART RUT — two grooves of polished stone; the detail that says road, not floor.
    const ra = rng.angle();
    for ([_]f32{ -0.42, 0.42 }) |o| {
        var r: i32 = 0;
        while (r < 7) : (r += 1) {
            const t = (@as(f32, @floatFromInt(r)) - 3.0) * 0.60;
            b.addBox(
                v3(mathx.cosf(ra) * t - mathx.sinf(ra) * o, 0.026, mathx.sinf(ra) * t + mathx.cosf(ra) * o),
                v3(mathx.cosf(ra) * 0.32, 0, mathx.sinf(ra) * 0.32),
                v3(0, 0.005, 0),
                v3(-mathx.sinf(ra) * 0.11, 0, mathx.cosf(ra) * 0.11),
                PAVE_LT,
            );
        }
    }
    // KERB stones at the edge — the scale break that stops one grain size everywhere.
    var k: i32 = 0;
    while (k < 3) : (k += 1) {
        const a = rng.angle();
        b.addBox(
            v3(mathx.cosf(a) * 2.05, 0.038, mathx.sinf(a) * 2.05),
            v3(mathx.cosf(a + 1.57) * 0.42, rng.signed() * 0.015, mathx.sinf(a + 1.57) * 0.42),
            v3(0, 0.038, 0),
            v3(mathx.cosf(a) * 0.14, 0, mathx.sinf(a) * 0.14),
            if (rng.float() < 0.4) STONE_DK else PAVE,
        );
    }
    b.setMat(.plant);
    // Grass and moss through the joints, and thickest in the holes where the bed is exposed.
    for (holes) |h| tuftInto(&b, &rng, h[0], h[1], 0.5);
    lichenInto(&b, &rng, v3(rng.signed() * 1.5, 0.045, rng.signed() * 1.5), v3(0.42, 0.012, 0.38), 4);
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 1.8, rng.signed() * 1.8, 0.55);
    tuftInto(&b, &rng, rng.signed() * 1.8, rng.signed() * 1.8, 0.45);
    return b.toModel(shader);
}

// A broken CART: two spoked wheels (one collapsed flat), a plank bed dropped on its axle,
// a snapped draught shaft in the air. Somebody was leaving when this happened.
fn cartMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(4747);
    b.setMat(.wood);
    // The bed, tipped: planks along local X, one end down on the ground.
    var pl: i32 = 0;
    while (pl < 6) : (pl += 1) {
        const z = (@as(f32, @floatFromInt(pl)) - 2.5) * 0.28;
        if (rng.float() < 0.15) continue;
        b.addBox(v3(0, 0.72 + rng.signed() * 0.02, z), v3(1.05, -0.20, 0), v3(0, 0.055, 0), v3(0, 0, 0.13), if (@mod(pl, 2) == 0) TIMBER else TIMBER_DK);
    }
    b.addCapsule(v3(-1.05, 0.60, 0), v3(1.05, 0.44, 0), 0.09, 0.08, 6, TIMBER_DK); // axle beam
    b.addCapsule(v3(1.0, 0.50, 0.1), v3(2.15, 0.95, 0.25), 0.075, 0.05, 5, TIMBER_DK); // shaft, snapped upward
    // Wheels: a rim of short chords + spokes. One stands, one has folded flat.
    const wheel = struct {
        fn go(bb: *Builder, cx: f32, cy: f32, cz: f32, rad: f32, flat: bool, r: *mathx.Rng) void {
            const seg: i32 = 10;
            var i: i32 = 0;
            while (i < seg) : (i += 1) {
                const a0 = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(seg));
                const a1 = std.math.tau * @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(seg));
                if (r.float() < 0.12) continue; // a missing felloe
                const p0 = if (flat) v3(cx + mathx.cosf(a0) * rad, cy, cz + mathx.sinf(a0) * rad) else v3(cx + mathx.cosf(a0) * rad, cy + mathx.sinf(a0) * rad, cz);
                const p1 = if (flat) v3(cx + mathx.cosf(a1) * rad, cy, cz + mathx.sinf(a1) * rad) else v3(cx + mathx.cosf(a1) * rad, cy + mathx.sinf(a1) * rad, cz);
                bb.addCapsule(p0, p1, 0.075, 0.075, 5, BARK_DK);
                if (@mod(i, 2) == 0) bb.addCapsule(v3(cx, cy, cz), p0, 0.035, 0.028, 4, TIMBER_DK); // spoke
            }
        }
    }.go;
    wheel(&b, -0.9, 0.62, 0.95, 0.60, false, &rng);
    wheel(&b, 0.85, 0.09, -1.0, 0.58, true, &rng);
    b.setMat(.cloth);
    b.addBlob(v3(0.2, 0.86, 0.2), v3(0.45, 0.10, 0.35), 3, 5, CLOTH); // a rag of cargo cover
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 1.2, rng.signed() * 1.2, 0.7);
    return b.toModel(shader);
}

// ── VILLAGE + WAYSIDE DRESSING ── the small things that say people lived here. None of them are
// landmarks; their whole job is to be found, so they are cheap, low, and scattered.

// A WELL: a drum of field stone, a timber windlass on two posts, a rope, and a bucket lying on
// the coping where somebody left it.
fn wellMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2101);
    b.setMat(.stone);
    // The drum: a core cylinder faced with rounded stones in three overlapping courses. A bare
    // cylinder reads as a pipe; stones alone leak daylight at every joint.
    b.addCylinder(v3(0, 0.02, 0), v3(0, 1.04, 0), 0.80, 0.80, 12, MORTAR);
    var c: i32 = 0;
    while (c < 3) : (c += 1) {
        const y = 0.16 + @as(f32, @floatFromInt(c)) * 0.30;
        const n: i32 = 12;
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = std.math.tau * (@as(f32, @floatFromInt(i)) + (if (@mod(c, 2) == 0) @as(f32, 0) else 0.5)) / @as(f32, @floatFromInt(n));
            const r = rng.range(0.20, 0.28); // wide enough that neighbours bed into each other
            b.addBlob(v3(mathx.cosf(a) * 0.84, y, mathx.sinf(a) * 0.84), v3(r, 0.21, r), 3, 5, if (rng.float() < 0.3) STONE_LT else if (rng.float() < 0.5) STONE_MOSS else STONE);
        }
    }
    b.addCylinder(v3(0, 1.02, 0), v3(0, 1.10, 0), 0.98, 0.98, 12, STONE_DK); // coping ring
    b.addCylinder(v3(0, 0.0, 0), v3(0, 0.06, 0), 0.70, 0.70, 12, IRON); // the dark of the shaft
    b.setMat(.wood);
    for ([_]f32{ -0.78, 0.78 }) |px| {
        b.addCapsule(v3(px, 1.0, 0), v3(px + rng.signed() * 0.05, 2.05, rng.signed() * 0.05), 0.085, 0.07, 6, TIMBER_DK);
    }
    b.addCapsule(v3(-0.9, 2.02, 0), v3(0.9, 2.06, 0), 0.075, 0.075, 6, TIMBER); // the windlass barrel
    b.addBox(v3(0.95, 2.04, 0.16), v3(0.03, 0, 0), v3(0, 0.02, 0.18), v3(0, 0.16, 0), TIMBER_DK); // crank handle
    b.addCapsule(v3(0.2, 2.0, 0), v3(0.2, 1.25, 0.02), 0.018, 0.018, 4, BARK_DK); // rope
    // The bucket, on the coping.
    b.addCylinder(v3(0.55, 1.10, 0.55), v3(0.55, 1.38, 0.55), 0.17, 0.19, 8, TIMBER);
    b.addDome(v3(0.55, 1.10, 0.55), v3(0, -1, 0), 0.17, 8, TIMBER_DK);
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 1.3, rng.signed() * 1.3, 0.8);
    b.addBlob(v3(0.9, 1.06, -0.4), v3(0.3, 0.08, 0.25), 3, 5, MOSS_SOFT);
    return b.toModel(shader);
}

// A wayside SHRINE: a small gabled stone housing on a plinth holding a worn figure, with candle
// stubs burning on its step. Carries a light — the smallest fire in the world.
fn shrineMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2102);
    b.setMat(.stone);
    b.addCube(v3(0, 0.14, 0), v3(1.5, 0.28, 1.2), STONE_DK); // plinth
    b.addCube(v3(0, 0.36, 0), v3(1.2, 0.18, 0.95), STONE);
    // The housing: two side walls, a back, and a gable — open to the front (local −Z).
    for ([_]f32{ -0.44, 0.44 }) |sx| b.addCube(v3(sx, 1.05, 0.06), v3(0.22, 1.2, 0.82), STONE);
    b.addCube(v3(0, 1.05, 0.42), v3(1.1, 1.2, 0.2), STONE_DK);
    var g: i32 = 0;
    while (g < 4) : (g += 1) {
        const t = @as(f32, @floatFromInt(g)) / 4.0;
        b.addCube(v3(0, 1.70 + t * 0.42, 0.06), v3(1.15 * (1.0 - t * 0.75), 0.16, 0.9 * (1.0 - t * 0.2)), if (@mod(g, 2) == 0) STONE else STONE_DK);
    }
    // The figure inside: a small hooded form, face lost.
    b.addCylinder(v3(0, 0.46, 0.06), v3(rng.signed() * 0.03, 1.24, 0.06), 0.26, 0.17, 8, STONE_LT);
    b.addBlob(v3(0, 1.34, 0.06), v3(0.17, 0.19, 0.17), 4, 7, STONE);
    b.setMat(.plain);
    // Candle stubs on the step, guttering.
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const x = -0.34 + @as(f32, @floatFromInt(i)) * 0.34;
        const h = rng.range(0.09, 0.17);
        b.setMat(.cloth);
        b.addCylinder(v3(x, 0.45, -0.34), v3(x, 0.45 + h, -0.34), 0.035, 0.032, 6, PETAL_WHITE);
        // A candle flame is a teardrop and already the right shape — it only wanted to MOVE. The
        // datum is this candle's OWN wick (the stubs are unequal), so each of the three gutters on
        // its own tiny amplitude instead of the three swaying together off a shared height.
        b.setMat(.flame);
        b.setAnimY(0.45 + h);
        b.addBlob(v3(x, 0.45 + h + 0.035, -0.34), v3(0.022, 0.045, 0.022), 3, 5, FLAME_CORE);
        b.addBlob(v3(x, 0.45 + h + 0.085, -0.34), v3(0.014, 0.035, 0.014), 3, 5, FLAME_TIP);
        b.setAnimY(0);
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 1.0, rng.signed() * 0.9, 0.7);
    b.addBlob(v3(rng.signed() * 0.7, 0.42, -0.5), v3(0.2, 0.07, 0.16), 3, 5, MOSS_SOFT);
    return b.toModel(shader);
}

// A post LANTERN: an iron cage on a hooked pole, lit. Marks a road at a distance the way a torch
// can't — it stands above the grass.
fn lanternMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2103);
    b.setMat(.stone);
    b.addBlob(v3(0, 0.12, 0), v3(0.34, 0.13, 0.32), 3, 6, STONE_DK); // a stone pad at the foot
    b.setMat(.wood);
    b.addCapsule(v3(0, 0.06, 0), v3(rng.signed() * 0.08, 2.78, rng.signed() * 0.08), 0.075, 0.055, 6, TIMBER_DK);
    b.setMat(.steel);
    b.addCapsule(v3(0.02, 2.76, 0), v3(0.30, 2.86, 0), 0.03, 0.024, 5, IRON); // the hook arm
    b.addCapsule(v3(0.30, 2.86, 0), v3(0.30, 2.74, 0), 0.02, 0.02, 4, IRON);
    // The cage: four uprights + two hoops + a little roof.
    var u: i32 = 0;
    while (u < 4) : (u += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(u)) / 4.0 + 0.4;
        b.addCapsule(v3(0.30 + mathx.cosf(a) * 0.12, 2.44, mathx.sinf(a) * 0.12), v3(0.30 + mathx.cosf(a) * 0.12, 2.74, mathx.sinf(a) * 0.12), 0.017, 0.017, 4, IRON);
    }
    b.addCylinder(v3(0.30, 2.42, 0), v3(0.30, 2.47, 0), 0.14, 0.14, 8, IRON);
    b.addCylinder(v3(0.30, 2.74, 0), v3(0.30, 2.80, 0), 0.16, 0.11, 8, IRON);
    b.addDome(v3(0.30, 2.80, 0), v3(0, 1, 0), 0.11, 8, IRON);
    // `.flame` + setAnimY, NOT flameInto: this flame is the right shape already and it lives inside
    // a 0.11 cage, where five tapered spires would poke straight through the ironwork. What it was
    // missing is the MOTION — on `.plain` it was the one fire in the world standing perfectly still.
    // Its height above the wick is small, so the shared writhe moves it proportionally little, which
    // is exactly what a sheltered flame in a housing does.
    b.setMat(.flame);
    b.setAnimY(2.48); // the wick, not the prop's base — the datum the writhe measures from
    b.addBlob(v3(0.30, 2.56, 0), v3(0.075, 0.10, 0.075), 4, 7, FLAME_CORE);
    b.addBlob(v3(0.30, 2.66, 0), v3(0.045, 0.07, 0.045), 3, 6, FLAME_MID);
    b.setAnimY(0);
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 0.5, rng.signed() * 0.5, 0.75);
    return b.toModel(shader);
}

// A FENCE run: split posts driven at uneven depths with two rails, several posts leaning or gone.
fn fenceMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2104);
    b.setMat(.wood);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const x = -3.0 + @as(f32, @floatFromInt(i)) * 1.0;
        if (rng.float() < 0.14) continue; // a post pulled out or rotted away
        const h = rng.range(0.85, 1.22);
        b.addCapsule(v3(x, 0, rng.signed() * 0.05), v3(x + rng.signed() * 0.16, h, rng.signed() * 0.14), 0.075, 0.06, 5, TIMBER_DK);
    }
    // Rails, in broken lengths rather than one continuous run.
    var r: i32 = 0;
    while (r < 2) : (r += 1) {
        const y = 0.48 + @as(f32, @floatFromInt(r)) * 0.36;
        var x: f32 = -3.0;
        while (x < 2.9) {
            const seg = rng.range(0.9, 2.1);
            if (rng.float() > 0.22) {
                b.addBox(v3(x + seg * 0.5, y + rng.signed() * 0.04, 0), v3(seg * 0.5, rng.signed() * 0.03, 0), v3(0, 0.045, 0), v3(0, 0, 0.035), if (rng.float() < 0.5) TIMBER else TIMBER_DK);
            }
            x += seg + rng.range(0.05, 0.35);
        }
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.range(-2.6, 2.6), rng.signed() * 0.3, 0.85);
    tuftInto(&b, &rng, rng.range(-2.6, 2.6), rng.signed() * 0.3, 0.7);
    return b.toModel(shader);
}

// BARRELS and crates, stacked and spilled. Staves are individual, so the barrels read as coopered
// rather than as cylinders.
fn barrelsMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2105);
    const barrel = struct {
        fn go(bb: *Builder, r: *mathx.Rng, cx: f32, cz: f32, tilt: f32, h: f32) void {
            const staves: i32 = 10;
            var i: i32 = 0;
            while (i < staves) : (i += 1) {
                const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(staves));
                const rr = 0.30;
                bb.setMat(.wood);
                bb.addCapsule(
                    v3(cx + mathx.cosf(a) * rr * 0.86, 0.02, cz + mathx.sinf(a) * rr * 0.86),
                    v3(cx + mathx.cosf(a) * rr * 0.86 + tilt, h, cz + mathx.sinf(a) * rr * 0.86),
                    0.055,
                    0.05,
                    4,
                    if (r.float() < 0.4) TIMBER else TIMBER_DK,
                );
            }
            bb.setMat(.steel);
            for ([_]f32{ 0.2, 0.78 }) |t| {
                bb.addCylinder(v3(cx + tilt * t, h * t, cz), v3(cx + tilt * t, h * t + 0.05, cz), 0.33, 0.33, 10, RUST);
            }
            bb.setMat(.wood);
            bb.addCylinder(v3(cx + tilt, h - 0.03, cz), v3(cx + tilt, h, cz), 0.29, 0.29, 10, TIMBER_DK); // the head
        }
    }.go;
    barrel(&b, &rng, 0, 0, 0.02, 0.82);
    barrel(&b, &rng, 0.62, 0.28, -0.04, 0.76);
    barrel(&b, &rng, -0.35, 0.66, 0.05, 0.70);
    // A crate, and one broken open.
    b.setMat(.wood);
    b.addCube(v3(-0.75, 0.26, -0.45), v3(0.62, 0.52, 0.58), TIMBER_DK);
    var p: i32 = 0;
    while (p < 4) : (p += 1) {
        const y = 0.08 + @as(f32, @floatFromInt(p)) * 0.14;
        b.addCube(v3(-0.75, y, -0.75), v3(0.64, 0.055, 0.03), TIMBER);
    }
    b.addBox(v3(0.55, 0.10, -0.72), v3(0.34, 0.06, 0), v3(0, 0.05, 0), v3(0, 0, 0.28), TIMBER); // a lid slid off
    b.setMat(.cloth);
    b.addBlob(v3(-0.2, 0.18, -0.9), v3(0.3, 0.16, 0.22), 3, 6, THATCH_DK); // a spilled sack
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 1.1, rng.signed() * 1.1, 0.7);
    return b.toModel(shader);
}

// A WOODPILE: split billets stacked in courses under a sagging cover, with a few fallen off.
fn woodpileMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2106);
    b.setMat(.wood);
    var c: i32 = 0;
    while (c < 5) : (c += 1) {
        const y = 0.11 + @as(f32, @floatFromInt(c)) * 0.21;
        const halfW = 1.15 - @as(f32, @floatFromInt(c)) * 0.10;
        var z: f32 = -halfW;
        while (z < halfW) {
            const d = rng.range(0.17, 0.24);
            if (rng.float() > 0.10) {
                b.addCapsule(v3(-0.55 + rng.signed() * 0.06, y, z), v3(0.55 + rng.signed() * 0.06, y + rng.signed() * 0.03, z), d * 0.5, d * 0.5, 5, if (rng.float() < 0.35) BARK_DK else if (rng.float() < 0.6) TIMBER else TIMBER_DK);
            }
            z += d;
        }
    }
    var f: i32 = 0;
    while (f < 4) : (f += 1) {
        const a = rng.angle();
        const d = rng.range(1.2, 1.9);
        b.addCapsule(v3(mathx.cosf(a) * d, 0.10, mathx.sinf(a) * d), v3(mathx.cosf(a) * d + rng.signed() * 0.5, 0.10, mathx.sinf(a) * d + rng.signed() * 0.5), 0.095, 0.085, 5, TIMBER_DK);
    }
    b.setMat(.cloth);
    b.addBlob(v3(0, 1.16, 0), v3(0.85, 0.10, 0.75), 3, 6, THATCH_DK); // a sagging cover
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 1.4, rng.signed() * 1.4, 0.75);
    return b.toModel(shader);
}

// BONES: a scatter of ribs, long bones and a skull, half sunk in the turf. Souls games put these
// where something went wrong, so they read as a WARNING more than as decoration.
fn bonesMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2107);
    b.setMat(.plain);
    // A skull: cranium plus a jaw slipped off it.
    b.addBlob(v3(0, 0.14, 0), v3(0.16, 0.15, 0.19), 4, 7, BONE);
    b.addBlob(v3(0, 0.09, -0.17), v3(0.11, 0.07, 0.09), 3, 6, BONE);
    b.addBlob(v3(0.14, 0.05, -0.22), v3(0.09, 0.04, 0.10), 3, 5, BONE);
    // Ribs, curved: two capsules each.
    var r: i32 = 0;
    while (r < 6) : (r += 1) {
        const z = 0.34 + @as(f32, @floatFromInt(r)) * 0.13;
        const sgn: f32 = if (@mod(r, 2) == 0) 1 else -1;
        const w = rng.range(0.18, 0.28);
        b.addCapsule(v3(0, 0.06, z), v3(sgn * w, 0.13, z + rng.signed() * 0.04), 0.022, 0.018, 4, BONE);
        b.addCapsule(v3(sgn * w, 0.13, z), v3(sgn * w * 1.35, 0.05, z + rng.signed() * 0.06), 0.018, 0.014, 4, BONE);
    }
    b.addCapsule(v3(0, 0.05, 0.28), v3(0, 0.05, 1.12), 0.035, 0.028, 5, BONE); // spine
    var l: i32 = 0;
    while (l < 4) : (l += 1) {
        const a = rng.angle();
        const d = rng.range(0.3, 1.0);
        const len = rng.range(0.25, 0.45);
        b.addCapsule(
            v3(mathx.cosf(a) * d, 0.045, mathx.sinf(a) * d + 0.5),
            v3(mathx.cosf(a) * d + mathx.cosf(a + 1.2) * len, 0.05, mathx.sinf(a) * d + 0.5 + mathx.sinf(a + 1.2) * len),
            0.03,
            0.036,
            5,
            BONE,
        );
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 0.9, 0.5 + rng.signed() * 0.9, 0.7);
    return b.toModel(shader);
}

// A stone SARCOPHAGUS with its lid shoved aside — whatever was in it isn't now.
fn sarcophagusMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2108);
    b.setMat(.stone);
    b.addCube(v3(0, 0.10, 0), v3(2.1, 0.20, 1.05), STONE_DK); // base slab
    // The chest: four walls, so the inside is a real void you can see into.
    b.addCube(v3(0, 0.52, 0.44), v3(1.9, 0.64, 0.16), STONE);
    b.addCube(v3(0, 0.52, -0.44), v3(1.9, 0.64, 0.16), STONE);
    b.addCube(v3(0.87, 0.52, 0), v3(0.16, 0.64, 0.75), STONE);
    b.addCube(v3(-0.87, 0.52, 0), v3(0.16, 0.64, 0.75), STONE);
    b.addCube(v3(0, 0.24, 0), v3(1.6, 0.10, 0.6), IRON); // the dark floor of it
    // The lid, dragged off and canted against the side.
    b.addBox(v3(-0.35, 0.92, 0.30), v3(1.0, 0.10, 0), v3(-0.04, 0.11, 0), v3(0, 0, 0.5), STONE_LT);
    b.addBox(v3(1.35, 0.30, 0.5), v3(0.55, 0.42, 0), v3(0.16, 0.20, 0), v3(0, 0, 0.42), STONE_DK); // …a broken end on the ground
    // A worn effigy line down the lid, and moss where the rain sits.
    b.addBox(v3(-0.35, 1.00, 0.30), v3(0.7, 0.07, 0), v3(0, 0.03, 0), v3(0, 0, 0.10), STONE_MOSS);
    b.setMat(.plant);
    b.addBlob(v3(rng.signed() * 0.6, 0.98, -0.2), v3(0.35, 0.07, 0.22), 3, 6, MOSS_SOFT);
    tuftInto(&b, &rng, rng.range(-1.6, 1.6), rng.signed() * 1.0, 0.8);
    return b.toModel(shader);
}

// A fragment of STONE STAIR going nowhere — four or five treads and the stub of the wall that
// carried them. Cheap ruin storytelling: it implies a storey that is gone.
fn stairsMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2109);
    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 6) : (i += 1) {
        const t = @as(f32, @floatFromInt(i));
        const y = 0.14 + t * 0.24;
        const x = -1.1 + t * 0.42;
        const w = 1.5 - t * 0.10;
        if (i == 5 and rng.float() < 0.5) continue; // the top tread often gone
        b.addBox(
            v3(x, y, rng.signed() * 0.03),
            v3(0.28, rng.signed() * 0.012, 0),
            v3(0, 0.12, 0),
            v3(0, 0, w * 0.5),
            if (rng.float() < 0.28) STONE_LT else if (rng.float() < 0.5) STONE_MOSS else STONE,
        );
    }
    // The stub wall the flight was built against.
    b.addCube(v3(-0.2, 0.55, 0.86), v3(2.6, 1.1, 0.34), STONE_DK);
    b.addCube(v3(0.9, 1.25, 0.86), v3(0.7, 0.4, 0.30), STONE); // a surviving upstand
    var d: i32 = 0;
    while (d < 5) : (d += 1) {
        const r = rng.range(0.14, 0.30);
        b.addBlob(v3(rng.range(-1.6, 1.6), r * 0.6, rng.range(-1.2, 0.4)), v3(r, r * 0.7, r), 3, 5, STONE_DK);
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.range(-1.3, 1.3), rng.range(-0.8, 0.4), 0.8);
    b.addBlob(v3(rng.range(-1.0, 1.0), 0.30, 0.5), v3(0.3, 0.08, 0.2), 3, 5, MOSS_SOFT);
    return b.toModel(shader);
}

// A GIBBET: an iron cage on a leaning post, hanging empty, chain and all. Grim wayside furniture —
// the thing you see before you understand what the road is for.
fn gibbetMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(2110);
    b.setMat(.stone);
    b.addBlob(v3(0, 0.14, 0), v3(0.44, 0.15, 0.40), 3, 6, STONE_DK);
    b.setMat(.wood);
    const lean = rng.signed() * 0.22;
    b.addCapsule(v3(0, 0.05, 0), v3(lean, 3.85, lean * 0.4), 0.115, 0.085, 6, TIMBER_DK); // post
    b.addCapsule(v3(lean, 3.78, lean * 0.4), v3(lean + 1.05, 3.92, lean * 0.4), 0.075, 0.055, 5, TIMBER_DK); // arm
    b.addCapsule(v3(lean + 0.1, 3.30, lean * 0.4), v3(lean + 0.62, 3.86, lean * 0.4), 0.05, 0.04, 4, TIMBER_DK); // brace
    b.setMat(.steel);
    // Chain: a short run of alternating links, hanging straight.
    var k: i32 = 0;
    while (k < 4) : (k += 1) {
        const y = 3.86 - @as(f32, @floatFromInt(k)) * 0.11;
        b.addCylinder(v3(lean + 1.0, y, 0), v3(lean + 1.0, y - 0.09, 0), 0.035, 0.035, 5, RUST);
    }
    // The cage: uprights bowed outward, three hoops, and a spiked base.
    const cx = lean + 1.0;
    const top: f32 = 3.42;
    var u: i32 = 0;
    while (u < 6) : (u += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(u)) / 6.0;
        b.addCapsule(v3(cx + mathx.cosf(a) * 0.08, top, mathx.sinf(a) * 0.08), v3(cx + mathx.cosf(a) * 0.30, top - 0.55, mathx.sinf(a) * 0.30), 0.022, 0.026, 4, RUST);
        b.addCapsule(v3(cx + mathx.cosf(a) * 0.30, top - 0.55, mathx.sinf(a) * 0.30), v3(cx + mathx.cosf(a) * 0.20, top - 1.25, mathx.sinf(a) * 0.20), 0.026, 0.022, 4, RUST);
    }
    for ([_]f32{ 0.0, -0.55, -1.25 }) |dy| {
        const rr: f32 = if (dy < -0.3) 0.26 else 0.20;
        b.addCylinder(v3(cx, top + dy, 0), v3(cx, top + dy + 0.04, 0), rr, rr, 8, RUST);
    }
    b.addCylinder(v3(cx, top - 1.28, 0), v3(cx, top - 1.22, 0), 0.20, 0.20, 8, IRON);
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 0.8, rng.signed() * 0.8, 0.8);
    return b.toModel(shader);
}

// A CAIRN: field stones stacked by hand, largest at the bottom, leaning as they rise. A waymarker
// somebody built, which is why it is the one pile of rocks in the world that looks deliberate.
fn cairnMesh(shader: rl.Shader) rl.Model {
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
fn outcropMesh(shader: rl.Shader) rl.Model {
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
fn screeMesh(shader: rl.Shader) rl.Model {
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

// ── FIRE ── each of these carries a gfx.Light (see INFO). The flame itself is EMISSIVE
// geometry (vertex alpha < 255) so it burns through shadow and haze; the light is what puts
// that fire onto the walls, the floor and the hero.

// One flame: emissive TONGUES, not a cone. The geometry is opaque (there is no alpha blending in
// this pipeline), so a fire has to read from its SILHOUETTE — which means tall narrow lobes at
// uneven heights and leans, mostly orange, with only a small hot heart. Built as a fat stack of
// near-white blobs it read as a traffic cone: the pale core was the biggest thing in it.
fn flameInto(b: *Builder, rng: *mathx.Rng, cx: f32, cy: f32, cz: f32, s: f32) void {
    // `.flame` gets two things `.plain` could not: the vertex shader's WRITHE (so the thing
    // actually moves — the light has been guttering since it was written, over a flame standing
    // perfectly still) and no surface grain at all, which is what the old comment here asked for.
    // `setAnimY(cy)` is what tells the shader where the fuel is, so the coals hold still while the
    // tongues dance; both are STICKY, so both are put back at the end.
    b.setMat(.flame);
    b.setAnimY(cy);
    // THE HEART: a small, low pool at the fuel. Small on purpose — a big pale core is what made an
    // earlier version read as a traffic cone.
    b.addBlob(v3(cx, cy + 0.015 * s, cz), v3(0.125 * s, 0.050 * s, 0.125 * s), 3, 9, COAL);
    b.addBlob(v3(cx, cy + 0.065 * s, cz), v3(0.050 * s, 0.060 * s, 0.050 * s), 3, 8, FLAME_CORE);
    // TONGUES: TAPERED SPIRES, not stacked blobs. A capsule with ra > rb is a smooth cone with
    // rounded ends, which is the shape of a flame tongue — two fat blobs one on top of the other is
    // the shape of a snowman, and at six sides their facet folds were most of what read as crumpled
    // paper once the vertex writhe started bending them.
    //
    // FIVE, at unequal heights, each in TWO segments so the spire can bend on its way up (a
    // straight one is a spike). Narrow relative to their height: the silhouette is the whole read.
    var t: i32 = 0;
    while (t < 5) : (t += 1) {
        const a = rng.angle();
        const off = rng.range(0.01, 0.070) * s;
        const h = rng.range(0.20, 0.60) * s; // the tallest tongue sets the flame's height
        const w = rng.range(0.030, 0.055) * s; // …and they stay NARROW relative to it
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
            w * 0.74,
            7,
            if (t == 0) FLAME_MID else if (rng.float() < 0.55) FLAME_MID else FLAME_TIP,
        );
        b.addCapsule(v3(mx, y0 + h * 0.52, mz), v3(tx, y0 + h, tz), w * 0.72, w * 0.12, 6, FLAME_TIP);
    }
    // …and a few loose EMBERS drifting off the top.
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const r = rng.range(0.010, 0.022) * s;
        b.addBlob(v3(cx + rng.signed() * 0.14 * s, cy + rng.range(0.45, 0.95) * s, cz + rng.signed() * 0.14 * s), v3(r, r, r), 3, 5, WISP);
    }
    b.setAnimY(0); // sticky, like setMat — hand the Builder back the way it was found
}

// A standing iron TORCH: three splayed feet, a twisted shaft, a cage of iron straps holding
// the pitch head, and the flame above it. Tall enough to light a room from the wall.
fn torchMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(9001);
    b.setMat(.steel);
    var f: i32 = 0;
    while (f < 3) : (f += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(f)) / 3.0 + 0.4;
        b.addCapsule(v3(0, 0.30, 0), v3(mathx.cosf(a) * 0.34, 0.015, mathx.sinf(a) * 0.34), 0.045, 0.03, 5, IRON);
    }
    b.addCapsule(v3(0, 0.12, 0), v3(rng.signed() * 0.04, 1.72, rng.signed() * 0.04), 0.055, 0.042, 6, IRON); // shaft
    // The basket: four uprights curving out, plus two hoops.
    var u: i32 = 0;
    while (u < 4) : (u += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(u)) / 4.0;
        b.addCapsule(v3(mathx.cosf(a) * 0.07, 1.68, mathx.sinf(a) * 0.07), v3(mathx.cosf(a) * 0.17, 2.02, mathx.sinf(a) * 0.17), 0.022, 0.016, 4, IRON);
    }
    b.addCylinder(v3(0, 1.74, 0), v3(0, 1.79, 0), 0.115, 0.115, 8, IRON);
    b.addCylinder(v3(0, 1.96, 0), v3(0, 2.00, 0), 0.165, 0.165, 8, IRON);
    b.setMat(.wood);
    b.addBlob(v3(0, 1.82, 0), v3(0.11, 0.10, 0.11), 3, 6, BARK_DK); // the pitch-soaked bundle
    flameInto(&b, &rng, 0, 1.90, 0, 1.0);
    return b.toModel(shader);
}

// A BRAZIER: a wide iron bowl on three raking legs, banked coals under a broad flame — the
// biggest of the fires, for a courtyard or a gateway.
fn brazierMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(9002);
    b.setMat(.steel);
    var f: i32 = 0;
    while (f < 3) : (f += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(f)) / 3.0 + 0.7;
        b.addCapsule(v3(mathx.cosf(a) * 0.44, 0.02, mathx.sinf(a) * 0.44), v3(mathx.cosf(a) * 0.16, 0.88, mathx.sinf(a) * 0.16), 0.055, 0.04, 5, IRON);
        b.addCapsule(v3(mathx.cosf(a) * 0.30, 0.42, mathx.sinf(a) * 0.30), v3(mathx.cosf(a + 2.09) * 0.30, 0.42, mathx.sinf(a + 2.09) * 0.30), 0.022, 0.022, 4, IRON); // cross-brace
    }
    b.addCylinder(v3(0, 0.86, 0), v3(0, 1.04, 0), 0.34, 0.54, 10, IRON); // the bowl
    b.addCylinder(v3(0, 1.02, 0), v3(0, 1.08, 0), 0.55, 0.55, 10, STEEL); // rolled rim
    b.addDome(v3(0, 0.86, 0), v3(0, -1, 0), 0.34, 10, IRON); // closes the bowl's underside
    b.setMat(.plain);
    b.addBlob(v3(0, 1.00, 0), v3(0.44, 0.10, 0.44), 3, 8, COAL); // banked coals
    flameInto(&b, &rng, 0, 1.06, 0, 1.45);
    flameInto(&b, &rng, 0.16, 1.02, -0.12, 0.85); // a second tongue off-centre — fire is not symmetric
    return b.toModel(shader);
}

// A CAMPFIRE: a ring of hearth stones, crossed half-burnt logs, embers between them, and a
// low flame. Somebody camped in the wood and did not come back for it.
fn campfireMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(9003);
    b.setMat(.stone);
    var i: i32 = 0;
    while (i < 9) : (i += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / 9.0 + rng.signed() * 0.15;
        const d = rng.range(0.52, 0.66);
        const r = rng.range(0.13, 0.23);
        b.addBlob(v3(mathx.cosf(a) * d, r * 0.72, mathx.sinf(a) * d), v3(r, r * 0.8, r * 1.1), 3, 6, if (rng.float() < 0.4) CLIFF_LT else CLIFF_ROCK);
    }
    b.setMat(.wood);
    var l: i32 = 0;
    while (l < 4) : (l += 1) {
        const a = rng.angle();
        const lift = rng.range(0.10, 0.30);
        b.addCapsule(
            v3(mathx.cosf(a) * 0.55, 0.10, mathx.sinf(a) * 0.55),
            v3(mathx.cosf(a + 3.0) * 0.30, lift, mathx.sinf(a + 3.0) * 0.30),
            0.085,
            0.06,
            5,
            if (rng.float() < 0.5) BARK_DK else IRON, // half of them burnt to char
        );
    }
    b.setMat(.plain);
    b.addBlob(v3(0, 0.06, 0), v3(0.34, 0.06, 0.34), 3, 7, COAL); // the ember bed
    flameInto(&b, &rng, 0, 0.10, 0, 1.15);
    flameInto(&b, &rng, -0.13, 0.08, 0.10, 0.7);
    return b.toModel(shader);
}

// ── WATER ── the tarn's surface: a flat irregular sheet. Everything that makes it read as
// water is in the shader (gfx.Mat.water — animated ripple normals, the shattered sun streak,
// a sky reflection at grazing angles); the MESH only supplies the outline and the silt
// gradient, dark in the middle and pale where it shallows out at the rim.
//
// SCALE 1 is a ~13 m radius pool; env scales instances up for the big tarn.
fn waterMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(5555);
    const SEG = 30;
    const RINGS = 5;
    const Y = 0.055; // a hair over env.GROUND_Y — you wade in ankle-deep
    const MUD_Y = 0.030; // …and the wet margin sits BETWEEN the two, so nothing z-fights
    // An irregular shoreline: per-spoke radius wobble, smoothed by averaging neighbours so
    // the outline undulates in bays instead of jittering vertex to vertex.
    var rad: [SEG]f32 = undefined;
    for (&rad) |*r| r.* = rng.range(0.78, 1.0);
    var smooth: [SEG]f32 = undefined;
    for (0..SEG) |i| {
        const a = rad[(i + SEG - 1) % SEG];
        const c = rad[i];
        const d = rad[(i + 1) % SEG];
        smooth[i] = (a + 2 * c + d) * 0.25;
    }
    // A flat annulus of `SEG` quads between two radii, at height `y`. Used for the water sheet
    // AND for the wet mud margin under its rim.
    //
    // WINDING: inner@a0 → inner@a1 → outer@a1 → outer@a0, which is the order whose right-hand
    // normal points UP. Sweeping outward first instead (the obvious way to write it) faces the
    // whole sheet at the LAKEBED, raylib culls it, and the tarn is simply not there — which is
    // exactly what the first version of this did.
    const band = struct {
        fn go(bb: *Builder, w: *const [SEG]f32, r0: f32, r1: f32, y: f32, col: rl.Color) void {
            var i: usize = 0;
            while (i < SEG) : (i += 1) {
                const j = (i + 1) % SEG;
                const a0 = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, SEG);
                const a1 = std.math.tau * @as(f32, @floatFromInt(i + 1)) / @as(f32, SEG);
                const at = struct {
                    fn p(ang: f32, r: f32, ww: f32, yy: f32) rl.Vector3 {
                        return v3(mathx.cosf(ang) * r * ww, yy, mathx.sinf(ang) * r * ww);
                    }
                }.p;
                // The innermost ring collapses to the centre, so its quad is a triangle (the
                // duplicated corner contributes a zero-area tri — harmless, and it keeps ONE
                // code path for the whole sheet).
                const w0 = if (r0 <= 0.001) 1.0 else w[i];
                const w1 = if (r0 <= 0.001) 1.0 else w[j];
                bb.quad(at(a0, r0, w0, y), at(a1, r0, w1, y), at(a1, r1, w[j], y), at(a0, r1, w[i], y), v3(0, 1, 0), col);
            }
        }
    }.go;

    // The WET MARGIN first, a little wider than the sheet and a little lower: dark saturated
    // mud that the water's edge dies into, so the shoreline isn't a hard line ruled across dry
    // grass. Stone material, not water — it doesn't ripple, it's just soaked.
    b.setMat(.stone);
    band(&b, &smooth, 12.4, 14.3, MUD_Y, WATER_MUD);

    b.setMat(.water);
    const ringT = [RINGS + 1]f32{ 0.0, 0.30, 0.55, 0.75, 0.90, 1.0 };
    const ringC = [RINGS + 1]rl.Color{ WATER_DEEP, WATER_DEEP, WATER_DEEP, WATER_MID, WATER_MID, WATER_SHALLOW };
    var ring: usize = 0;
    while (ring < RINGS) : (ring += 1) {
        band(&b, &smooth, 13.0 * ringT[ring], 13.0 * ringT[ring + 1], Y, mathx.lerpColor(ringC[ring], ringC[ring + 1], 0.5));
    }
    return b.toModel(shader);
}

// ── FLORA ── all plant meshes are grown from one seeded Rng (deterministic builds),
// blades as 4-sided tapered cylinders leaning off vertical, bases on Y=0. Flora are
// NON-casters (see Info.casts) — excluded from the shadow map so thin blades don't sparkle —
// and they SWAY via the scene shader's height-based wind term (gfx.setWind).

// One grass blade: a thin 4-sided tapered cylinder leaning outward.
fn blade(b: *Builder, x: f32, z: f32, h: f32, lx: f32, lz: f32, r: f32, col: rl.Color) void {
    b.addCylinder(v3(x, 0, z), v3(x + lx, h, z + lz), r, 0.003, 4, col);
}

fn bladeColor(rng: *mathx.Rng) rl.Color {
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
fn tuftMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plant);
    var rng = mathx.Rng.init(11);
    tuftInto(&b, &rng, 0, 0, 1.0);
    return b.toModel(shader);
}

// A wide swathe: several clumps strewn across ~2.5 m.
fn patchMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plant);
    var rng = mathx.Rng.init(23);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.2, 1.25);
        tuftInto(&b, &rng, mathx.cosf(a) * d, mathx.sinf(a) * d, rng.range(0.7, 1.1));
    }
    return b.toModel(shader);
}

// A low scrub bush: a rounded mound of many small leafy lobes (overlapping fat little
// tapered cylinders, domed — fuller/taller toward the middle), a couple of bare twigs
// poking through, grass at the skirt. Reads as a shrub, not a stack of boxes.
fn shrubMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plant);
    var rng = mathx.Rng.init(37);
    var i: i32 = 0;
    while (i < 14) : (i += 1) {
        const a = rng.angle();
        const rr = rng.range(0.0, 0.36);
        const x = mathx.cosf(a) * rr;
        const z = mathx.sinf(a) * rr;
        const base = rng.range(0.02, 0.14);
        const lobeR = rng.range(0.11, 0.20) * (1.0 - 0.5 * rr / 0.36); // fuller toward the centre
        const top = base + lobeR * rng.range(1.5, 2.4) * (1.0 - 0.4 * rr / 0.36); // domed profile
        const col = if (rng.float() < 0.5) SCRUB else SCRUB_DK;
        // a fat, short, slightly-leaning tapered cylinder = one rounded leafy lobe
        b.addCylinder(v3(x, base, z), v3(x + rng.signed() * 0.05, top, z + rng.signed() * 0.05), lobeR, lobeR * 0.45, 6, col);
    }
    b.addCylinder(v3(0.06, 0.0, 0.03), v3(0.20, 0.54, 0.12), 0.018, 0.004, 4, BARK_DK); // bare twigs poking through
    b.addCylinder(v3(-0.05, 0.0, -0.02), v3(-0.24, 0.48, -0.20), 0.018, 0.004, 4, BARK_DK);
    tuftInto(&b, &rng, 0.30, -0.30, 0.7); // grass at the skirt
    return b.toModel(shader);
}

// Pale erdleaf-like blooms nodding over a grass clump.
fn flowersMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plant);
    var rng = mathx.Rng.init(53);
    tuftInto(&b, &rng, 0, 0, 0.8);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.05, 0.30);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const h = rng.range(0.26, 0.44);
        b.addCylinder(v3(x, 0, z), v3(x, h, z), 0.009, 0.005, 4, STEM);
        b.addCube(v3(x, h + 0.02, z), v3(0.07, 0.05, 0.07), PETAL); // fatter bloom — reads at distance
    }
    return b.toModel(shader);
}

// Tall dry sedge, seed heads riding the tips.
fn reedsMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plant);
    var rng = mathx.Rng.init(71);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.03, 0.22);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const la = rng.angle();
        const lean = rng.range(0.05, 0.16);
        const h = rng.range(0.75, 1.25);
        const lx = mathx.cosf(la) * lean;
        const lz = mathx.sinf(la) * lean;
        blade(&b, x, z, h, lx, lz, 0.016, if (rng.float() < 0.7) GRASS_DRY else GRASS_GOLD);
        b.addCube(v3(x + lx, h + 0.03, z + lz), v3(0.038, 0.13, 0.038), SEED); // fuller seed head
    }
    return b.toModel(shader);
}

// Grace-side blooms: taller pale flowers with a faint emissive glow.
fn glowMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plant);
    var rng = mathx.Rng.init(89);
    tuftInto(&b, &rng, 0, 0, 0.75);
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.06, 0.2);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const h = rng.range(0.32, 0.5);
        b.addCylinder(v3(x, 0, z), v3(x, h, z), 0.008, 0.005, 4, STEM);
        b.addCube(v3(x, h + 0.025, z), v3(0.05, 0.04, 0.05), PETAL_GLOW);
    }
    return b.toModel(shader);
}

// A BUSH — bigger and rounder than the scrub shrub: a dome of overlapping leaf masses on a
// few woody stems, the crown catching gold where the sun would hit it. Blobs, not cylinders:
// this one has real volume and the old lobe trick reads as a bundle of sticks at this size.
fn bushMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(6161);
    b.setMat(.wood);
    var s: i32 = 0;
    while (s < 4) : (s += 1) {
        const a = rng.angle();
        b.addCapsule(v3(0, 0.0, 0), v3(mathx.cosf(a) * 0.28, rng.range(0.35, 0.6), mathx.sinf(a) * 0.28), 0.045, 0.025, 5, BARK_DK);
    }
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 16) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.62);
        const t = d / 0.62;
        const r = rng.range(0.20, 0.34) * (1.0 - 0.30 * t); // fuller in the middle, thinning at the edge
        const y = rng.range(0.30, 0.88) * (1.0 - 0.30 * t);
        const col = if (i == 0 or rng.float() < 0.22) LEAF_GOLD else if (rng.float() < 0.5) LEAF else LEAF_DK;
        b.addBlob(v3(mathx.cosf(a) * d, y, mathx.sinf(a) * d), v3(r, r * rng.range(0.62, 0.9), r * rng.range(0.85, 1.15)), 4, 7, col);
    }
    tuftInto(&b, &rng, rng.signed() * 0.55, rng.signed() * 0.55, 0.7);
    return b.toModel(shader);
}

// A BRAMBLE tangle: thin arcing canes crossing each other every which way, small dark
// leaves clustered along them, a few berries. Low, wide and unwelcoming — the wood's floor.
fn brambleMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(6262);
    // Canes stay LOW and mostly buried in leaf: at full height with bare dark stems they read as
    // a black spiky star on the grass — visual noise rather than undergrowth.
    b.setMat(.wood);
    var i: i32 = 0;
    while (i < 10) : (i += 1) {
        const a = rng.angle();
        const d0 = rng.range(0.0, 0.45);
        const x0 = mathx.cosf(a) * d0;
        const z0 = mathx.sinf(a) * d0;
        const arc = rng.range(0.5, 0.95);
        const b2 = a + rng.signed() * 1.5;
        // Each cane rises then falls back to the ground — two segments make the arch.
        const apex = v3(x0 + mathx.cosf(b2) * arc * 0.5, rng.range(0.24, 0.46), z0 + mathx.sinf(b2) * arc * 0.5);
        b.addCapsule(v3(x0, 0.02, z0), apex, 0.030, 0.024, 4, BARK_DK);
        b.addCapsule(apex, v3(x0 + mathx.cosf(b2) * arc, 0.03, z0 + mathx.sinf(b2) * arc), 0.024, 0.016, 4, BARK_DK);
    }
    // MANY SMALL leaves, not few big ones. At r ~0.2 with 3x5 tessellation each leaf mass was a
    // 40 cm pentagonal PLATE, and a scaled-up bramble read as a heap of green hexagons on the
    // grass. Leaves are leaf-sized; the mass comes from the count.
    b.setMat(.plant);
    var l: i32 = 0;
    while (l < 44) : (l += 1) {
        const a = rng.angle();
        const d = rng.range(0.05, 0.95);
        const r = rng.range(0.065, 0.125);
        b.addBlob(v3(mathx.cosf(a) * d, rng.range(0.06, 0.42), mathx.sinf(a) * d), v3(r, r * 0.8, r * 1.1), 3, 6, if (rng.float() < 0.6) LEAF_DK else LEAF);
    }
    var be: i32 = 0;
    while (be < 6) : (be += 1) {
        const a = rng.angle();
        const d = rng.range(0.2, 0.8);
        b.addBlob(v3(mathx.cosf(a) * d, rng.range(0.18, 0.48), mathx.sinf(a) * d), v3(0.028, 0.028, 0.028), 3, 5, BERRY);
    }
    return b.toModel(shader);
}

// A FERN clump: arching fronds — a long tapered midrib with leaflets stepped down both
// sides, shrinking toward the tip. Woodland floor cover under the big trees.
fn fernMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(6363);
    b.setMat(.plant);
    var f: i32 = 0;
    while (f < 7) : (f += 1) {
        const a = rng.angle();
        const reach = rng.range(0.45, 0.78);
        const rise = rng.range(0.42, 0.72);
        const ux = mathx.cosf(a);
        const uz = mathx.sinf(a);
        const tip = v3(ux * reach, rise * 0.72, uz * reach);
        b.addCylinder(v3(0, 0.03, 0), tip, 0.020, 0.005, 4, STEM);
        const nl: i32 = 5 + rng.intn(3);
        var l: i32 = 0;
        while (l < nl) : (l += 1) {
            const t = (@as(f32, @floatFromInt(l)) + 1.0) / (@as(f32, @floatFromInt(nl)) + 1.0);
            // The frond arches: it climbs fast then flattens out (sqrt-ish), so height is not linear in t.
            const y = 0.03 + rise * @sqrt(t) * 0.72;
            const px = ux * reach * t;
            const pz = uz * reach * t;
            const leafLen = rng.range(0.10, 0.19) * (1.0 - 0.55 * t);
            for ([_]f32{ -1, 1 }) |sgn| {
                // Leaflets have real THICKNESS and sit a little above the midrib. At 1.4 cm they
                // were flat plates, and a fern seen from anywhere above eye level read as a green
                // grid lying on the grass rather than as a plant.
                b.addBlob(
                    v3(px - uz * sgn * leafLen, y + 0.035, pz + ux * sgn * leafLen),
                    v3(@abs(uz) * leafLen + 0.03, 0.055, @abs(ux) * leafLen + 0.03),
                    3,
                    5,
                    if (rng.float() < 0.35) GRASS_GRN else if (rng.float() < 0.6) LEAF_LT else SCRUB,
                );
            }
        }
    }
    tuftInto(&b, &rng, rng.signed() * 0.4, rng.signed() * 0.4, 0.55);
    return b.toModel(shader);
}

// ── THE LUSH LAYER ── the ground cover that turns a field into a meadow. All of it is flora:
// non-casting (thin geometry sparkles in a shadow map) and wind-swayed. These are the props the
// scatter leans on hardest, so they are kept CHEAP — a few dozen tris each, no capsules where a
// tapered 4-sided cylinder will do.

// A TALL grass clump — the meadow's workhorse. Twice a `tuft`'s height and far fuller, with the
// blades fanning from a tight base so it reads as one plant rather than a handful of spikes.
fn grassTallMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3001);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 22) : (i += 1) {
        const a = rng.angle();
        const rr = rng.range(0.0, 0.09);
        const x = mathx.cosf(a) * rr;
        const z = mathx.sinf(a) * rr;
        const la = rng.angle();
        const lean = rng.range(0.10, 0.42);
        const h = rng.range(0.55, 1.10);
        blade(&b, x, z, h, mathx.cosf(la) * lean, mathx.sinf(la) * lean, 0.020, if (rng.float() < 0.35) GRASS_GRN else bladeColor(&rng));
    }
    // A few seed stalks over the top, which is what gives a clump its outline at distance.
    var s: i32 = 0;
    while (s < 3) : (s += 1) {
        const la = rng.angle();
        const lean = rng.range(0.05, 0.16);
        const h = rng.range(0.95, 1.18);
        blade(&b, 0, 0, h, mathx.cosf(la) * lean, mathx.sinf(la) * lean, 0.013, GRASS_DRY);
        b.addCube(v3(mathx.cosf(la) * lean, h, mathx.sinf(la) * lean), v3(0.032, 0.11, 0.032), SEED);
    }
    return b.toModel(shader);
}

// A CLOVER mat: broad low trefoil leaves on short stems, hugging the ground. Fills the gaps
// between taller things so the soil stops showing through.
fn cloverMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3002);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 20) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.72) * @sqrt(rng.float());
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const h = rng.range(0.05, 0.13);
        b.addCylinder(v3(x, 0, z), v3(x, h, z), 0.008, 0.006, 4, STEM);
        // Three leaflets per stem, which is what makes it read as clover and not as pebbles.
        var l: i32 = 0;
        while (l < 3) : (l += 1) {
            const la = a + std.math.tau * @as(f32, @floatFromInt(l)) / 3.0 + rng.signed() * 0.3;
            const lr = rng.range(0.035, 0.058);
            b.addBlob(v3(x + mathx.cosf(la) * lr, h + 0.006, z + mathx.sinf(la) * lr), v3(lr, 0.010, lr), 3, 5, if (rng.float() < 0.4) CLOVER_GRN else LEAF_DAMP);
        }
    }
    var f: i32 = 0;
    while (f < 3) : (f += 1) {
        const a = rng.angle();
        const d = rng.range(0.1, 0.6);
        b.addBlob(v3(mathx.cosf(a) * d, 0.155, mathx.sinf(a) * d), v3(0.032, 0.030, 0.032), 3, 5, PETAL_WHITE); // clover heads
    }
    return b.toModel(shader);
}

// A MOSS patch: a damp low swell of soft green creeping over the ground, a couple of shades of it.
fn mossMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3003);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 9) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.85) * @sqrt(rng.float());
        const r = rng.range(0.22, 0.48) * (1.0 - 0.3 * d);
        b.addBlob(v3(mathx.cosf(a) * d, rng.range(0.02, 0.06), mathx.sinf(a) * d), v3(r, rng.range(0.035, 0.075), r * rng.range(0.8, 1.2)), 3, 6, if (rng.float() < 0.45) MOSS_DK else MOSS_SOFT);
    }
    // A handful of tiny upright shoots, so it isn't a flat decal from ground level.
    var s: i32 = 0;
    while (s < 8) : (s += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.7);
        blade(&b, mathx.cosf(a) * d, mathx.sinf(a) * d, rng.range(0.06, 0.13), 0, 0, 0.008, MOSS_SOFT);
    }
    return b.toModel(shader);
}

// MUSHROOMS: a cluster of caps of differing ages on the wood's floor — domed, pale-stalked, a
// couple flattened out and one still a button.
fn mushroomsMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3004);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 8) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.34);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const h = rng.range(0.07, 0.28);
        const capR = rng.range(0.045, 0.135) * (0.5 + 0.6 * h / 0.28); // older = taller AND broader
        b.addCylinder(v3(x, 0, z), v3(x + rng.signed() * 0.02, h, z + rng.signed() * 0.02), capR * 0.30, capR * 0.24, 5, CAP_PALE);
        // The cap: a squashed dome, flatter the older it is.
        b.addBlob(v3(x + rng.signed() * 0.02, h + capR * 0.22, z + rng.signed() * 0.02), v3(capR, capR * rng.range(0.42, 0.72), capR), 3, 6, if (rng.float() < 0.6) CAP_BROWN else CAP_PALE);
    }
    b.addBlob(v3(0, 0.02, 0), v3(0.36, 0.035, 0.32), 3, 6, MOSS_DK); // the damp patch they came up in
    return b.toModel(shader);
}

// NETTLES: a dense bed of upright stems with paired leaves all the way up. Reads as something you
// would rather walk around.
fn nettlesMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3005);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 11) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.5);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const h = rng.range(0.45, 0.88);
        b.addCylinder(v3(x, 0, z), v3(x + rng.signed() * 0.07, h, z + rng.signed() * 0.07), 0.013, 0.008, 4, NETTLE);
        // Leaves are BROAD and have thickness, and there are more of them: at 1.4 cm thick and half
        // this width the plant read as a bare stick with antennae on it, not as foliage.
        const pairs: i32 = 4 + rng.intn(3);
        var p: i32 = 0;
        while (p < pairs) : (p += 1) {
            const t = (@as(f32, @floatFromInt(p)) + 0.8) / (@as(f32, @floatFromInt(pairs)) + 0.4);
            const y = h * t;
            const la = a + rng.signed() * 0.8 + @as(f32, @floatFromInt(p)) * 1.1; // leaves spiral up the stem
            const ll = rng.range(0.085, 0.145) * (1.0 - 0.35 * t);
            for ([_]f32{ -1, 1 }) |sgn| {
                b.addBlob(v3(x + mathx.cosf(la) * sgn * ll, y, z + mathx.sinf(la) * sgn * ll), v3(ll * 0.9, 0.032, ll * 0.72), 3, 6, if (rng.float() < 0.4) LEAF_DAMP else NETTLE);
            }
        }
    }
    return b.toModel(shader);
}

// THISTLE: spined stems, deep-cut leaves at the base, and purple heads on top. The one prickly
// thing that flowers.
fn thistleMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3006);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.26);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const h = rng.range(0.55, 0.98);
        const tipX = x + rng.signed() * 0.09;
        const tipZ = z + rng.signed() * 0.09;
        b.addCylinder(v3(x, 0, z), v3(tipX, h, tipZ), 0.017, 0.011, 4, SCRUB);
        // The head: a green cup with a purple tuft out of it.
        b.addBlob(v3(tipX, h + 0.03, tipZ), v3(0.038, 0.045, 0.038), 3, 6, SCRUB_DK);
        b.addBlob(v3(tipX, h + 0.095, tipZ), v3(0.040, 0.052, 0.040), 3, 6, if (rng.float() < 0.7) PURPLE else PURPLE_DK);
        // Spiny basal leaves: long, deep-cut, splayed low. Built as a tapered blade PLUS a broader
        // flat lobe, because a bare tapered cylinder on its own reads as a spike sticking out of
        // the ground rather than as a leaf.
        var l: i32 = 0;
        while (l < 5) : (l += 1) {
            const la = rng.angle();
            const ll = rng.range(0.14, 0.28);
            const ty = rng.range(0.06, 0.16);
            b.addCylinder(v3(x, 0.03, z), v3(x + mathx.cosf(la) * ll, ty, z + mathx.sinf(la) * ll), 0.030, 0.006, 4, SCRUB);
            b.addBlob(v3(x + mathx.cosf(la) * ll * 0.55, ty * 0.6 + 0.02, z + mathx.sinf(la) * ll * 0.55), v3(ll * 0.34, 0.022, ll * 0.34), 3, 5, if (rng.float() < 0.5) SCRUB else SCRUB_DK);
        }
    }
    return b.toModel(shader);
}

// FOXGLOVE: tall one-sided spires of bells, tallest flowers in the meadow. They punctuate the
// scatter — a vertical accent among all the mounds.
fn foxgloveMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3007);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.22);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const h = rng.range(0.75, 1.22);
        const lean = rng.range(0.04, 0.14);
        const la = rng.angle();
        const lx = mathx.cosf(la) * lean;
        const lz = mathx.sinf(la) * lean;
        b.addCylinder(v3(x, 0, z), v3(x + lx, h, z + lz), 0.016, 0.009, 4, STEM);
        // Bells down the top half of the spire, hanging on ONE side (that's the flower's tell),
        // biggest at the bottom.
        const nb: i32 = 5 + rng.intn(3);
        var f: i32 = 0;
        while (f < nb) : (f += 1) {
            const t = 0.42 + 0.55 * (@as(f32, @floatFromInt(f)) / @as(f32, @floatFromInt(nb)));
            const br = rng.range(0.030, 0.052) * (1.3 - 0.6 * t);
            const bx = x + lx * t + mathx.cosf(la) * 0.045;
            const bz = z + lz * t + mathx.sinf(la) * 0.045;
            b.addBlob(v3(bx, h * t, bz), v3(br, br * 1.35, br), 3, 6, if (rng.float() < 0.75) PURPLE else PURPLE_DK);
        }
        var lf: i32 = 0;
        while (lf < 3) : (lf += 1) {
            const bla = rng.angle();
            const ll = rng.range(0.09, 0.16);
            b.addBlob(v3(x + mathx.cosf(bla) * ll, rng.range(0.05, 0.18), z + mathx.sinf(bla) * ll), v3(ll * 0.8, 0.016, ll * 0.45), 3, 5, LEAF_DAMP);
        }
    }
    return b.toModel(shader);
}

// HEATHER: a low woody mat of tiny leaves with a purple-brown flush over it. The downs' signature —
// wide, ankle-high, and never green.
fn heatherMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3008);
    b.setMat(.wood);
    var s: i32 = 0;
    while (s < 7) : (s += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.6);
        b.addCapsule(v3(0, 0.02, 0), v3(mathx.cosf(a) * d, rng.range(0.10, 0.22), mathx.sinf(a) * d), 0.018, 0.010, 4, BARK_DK);
    }
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 26) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.82) * @sqrt(rng.float());
        const r = rng.range(0.07, 0.15) * (1.0 - 0.25 * d);
        const y = rng.range(0.09, 0.34) * (1.0 - 0.35 * d);
        // Two thirds foliage, one third bloom — a heath in flower, not a bed of flowers.
        const col = if (rng.float() < 0.34) (if (rng.float() < 0.6) PURPLE else PURPLE_DK) else if (rng.float() < 0.5) SCRUB_DK else BRACKEN_BRN;
        b.addBlob(v3(mathx.cosf(a) * d, y, mathx.sinf(a) * d), v3(r, r * 0.7, r * rng.range(0.85, 1.15)), 3, 5, col);
    }
    return b.toModel(shader);
}

// GORSE: a spiny dome, half bare thorn and half hard yellow bloom. The brightest thing growing in
// the world, so it is used sparingly.
fn gorseMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3009);
    b.setMat(.wood);
    var s: i32 = 0;
    while (s < 16) : (s += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.5);
        const h = rng.range(0.35, 0.95) * (1.0 - 0.4 * d);
        b.addCylinder(v3(mathx.cosf(a) * d, 0.0, mathx.sinf(a) * d), v3(mathx.cosf(a) * d * 1.5, h, mathx.sinf(a) * d * 1.5), 0.022, 0.004, 4, SCRUB_DK); // a thorn
    }
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 18) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.62);
        const r = rng.range(0.09, 0.17) * (1.0 - 0.25 * d);
        const y = rng.range(0.14, 0.78) * (1.0 - 0.3 * d);
        b.addBlob(v3(mathx.cosf(a) * d, y, mathx.sinf(a) * d), v3(r, r * 0.8, r), 3, 6, if (rng.float() < 0.42) GORSE_GOLD else if (rng.float() < 0.6) SCRUB else SCRUB_DK);
    }
    return b.toModel(shader);
}

// CATTAILS: bulrushes — straight blades and the brown sausage heads on stiff stems. For the water
// margin, where the softer reeds already are.
fn cattailsMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3010);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 9) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.02, 0.30);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const la = rng.angle();
        const lean = rng.range(0.03, 0.13);
        const h = rng.range(0.9, 1.55);
        blade(&b, x, z, h, mathx.cosf(la) * lean, mathx.sinf(la) * lean, 0.022, if (rng.float() < 0.5) GRASS_GRN else GRASS_DRY);
        // Only some blades carry a head — a bed of them all in flower looks planted.
        if (rng.float() < 0.55) {
            const sx = x + mathx.cosf(la) * lean * 0.6;
            const sz = z + mathx.sinf(la) * lean * 0.6;
            const sh = h * rng.range(0.85, 1.05);
            b.addCylinder(v3(x, 0, z), v3(sx, sh, sz), 0.014, 0.012, 4, STEM);
            b.addBlob(v3(sx, sh + 0.10, sz), v3(0.032, 0.115, 0.032), 3, 6, CAP_BROWN);
            b.addCylinder(v3(sx, sh + 0.21, sz), v3(sx, sh + 0.30, sz), 0.010, 0.003, 4, STEM); // the spike above it
        }
    }
    return b.toModel(shader);
}

// LILY PADS: flat discs floating with a notch cut out of each, a couple of white blooms among
// them. Sits ON the tarn — env places these inside the water's rim.
fn lilypadsMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3011);
    b.setMat(.plant);
    const Y: f32 = 0.075; // just above the water sheet's own 0.055
    var i: i32 = 0;
    while (i < 16) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 1.7) * @sqrt(rng.float());
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        // Pads are BIG — a real lily pad is a couple of hand-spans across, and at the old
        // 0.16..0.34 m they were a few pixels of speckle on the water from any useful height.
        const r = rng.range(0.30, 0.58);
        // The pad, as a very flattened blob (a disc with thickness reads better on water than a
        // zero-thickness quad, which vanishes edge-on).
        b.addBlob(v3(x, Y, z), v3(r, 0.016, r * rng.range(0.88, 1.1)), 3, 7, if (rng.float() < 0.35) LEAF_DAMP else LILY_GRN);
        if (rng.float() < 0.22) {
            b.addBlob(v3(x + rng.signed() * 0.08, Y + 0.055, z + rng.signed() * 0.08), v3(0.055, 0.045, 0.055), 3, 6, PETAL_WHITE);
            b.addBlob(v3(x + rng.signed() * 0.08, Y + 0.085, z + rng.signed() * 0.08), v3(0.028, 0.030, 0.028), 3, 5, PETAL);
        }
    }
    return b.toModel(shader);
}

// BRACKEN: last year's ferns, collapsed and rust-brown. Dead growth is what stops a wood floor
// looking like a garden.
fn brackenMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3012);
    b.setMat(.plant);
    var f: i32 = 0;
    while (f < 9) : (f += 1) {
        const a = rng.angle();
        const reach = rng.range(0.35, 0.85);
        const ux = mathx.cosf(a);
        const uz = mathx.sinf(a);
        // Collapsed: it rises barely at all and then lies over.
        const rise = rng.range(0.12, 0.36);
        b.addCylinder(v3(0, 0.03, 0), v3(ux * reach, rise, uz * reach), 0.018, 0.006, 4, BRACKEN_BRN);
        const nl: i32 = 4 + rng.intn(3);
        var l: i32 = 0;
        while (l < nl) : (l += 1) {
            const t = (@as(f32, @floatFromInt(l)) + 1.0) / (@as(f32, @floatFromInt(nl)) + 1.0);
            const y = 0.03 + rise * @sqrt(t) * 0.85;
            const ll = rng.range(0.06, 0.13) * (1.0 - 0.5 * t);
            for ([_]f32{ -1, 1 }) |sgn| {
                b.addBlob(v3(ux * reach * t - uz * sgn * ll, y, uz * reach * t + ux * sgn * ll), v3(@abs(uz) * ll + 0.022, 0.030, @abs(ux) * ll + 0.022), 3, 5, if (rng.float() < 0.6) BRACKEN_BRN else SCRUB_DK);
            }
        }
    }
    return b.toModel(shader);
}

// A THICKET: chest-high tangled brush — the densest single flora prop, for filling the wood's
// middle distance where individual plants stop reading.
fn thicketMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3013);
    b.setMat(.wood);
    var s: i32 = 0;
    while (s < 14) : (s += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.7);
        const h = rng.range(0.7, 1.6);
        b.addCapsule(
            v3(mathx.cosf(a) * d, 0.0, mathx.sinf(a) * d),
            v3(mathx.cosf(a) * d + rng.signed() * 0.5, h, mathx.sinf(a) * d + rng.signed() * 0.5),
            rng.range(0.030, 0.055),
            0.015,
            4,
            if (rng.float() < 0.5) BARK_DK else BARK,
        );
    }
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 30) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 1.0) * @sqrt(rng.float());
        const r = rng.range(0.14, 0.30) * (1.0 - 0.25 * d);
        const y = rng.range(0.20, 1.45) * (1.0 - 0.22 * d);
        const col = if (rng.float() < 0.15) LEAF_GOLD else if (rng.float() < 0.45) LEAF_DK else if (rng.float() < 0.7) LEAF else LEAF_DAMP;
        b.addBlob(v3(mathx.cosf(a) * d, y, mathx.sinf(a) * d), v3(r, r * rng.range(0.6, 0.9), r * rng.range(0.85, 1.2)), 4, 6, col);
    }
    tuftInto(&b, &rng, rng.signed() * 0.9, rng.signed() * 0.9, 0.85);
    return b.toModel(shader);
}

// WILDFLOWERS: a mixed drift — white, blue and pale heads on thin stems over grass. Several hues
// in ONE prop, because a scatter that places one colour at a time reads as a planted bed.
fn wildflowersMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3014);
    b.setMat(.plant);
    tuftInto(&b, &rng, 0, 0, 0.9);
    tuftInto(&b, &rng, rng.signed() * 0.5, rng.signed() * 0.5, 0.7);
    var i: i32 = 0;
    while (i < 16) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.05, 0.72);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const h = rng.range(0.22, 0.55);
        const lean = rng.range(0.0, 0.07);
        const la = rng.angle();
        const tx = x + mathx.cosf(la) * lean;
        const tz = z + mathx.sinf(la) * lean;
        b.addCylinder(v3(x, 0, z), v3(tx, h, tz), 0.009, 0.005, 4, STEM);
        const roll = rng.float();
        const col = if (roll < 0.38) PETAL_WHITE else if (roll < 0.62) PETAL_BLUE else if (roll < 0.82) PETAL else PURPLE;
        // A little corolla of petals rather than one cube — at this size it costs 5 blobs and
        // reads as a flower instead of a coloured speck.
        const pr = rng.range(0.024, 0.040);
        b.addBlob(v3(tx, h + 0.012, tz), v3(pr * 0.5, 0.012, pr * 0.5), 3, 5, SEED);
        var p: i32 = 0;
        while (p < 5) : (p += 1) {
            const pa = std.math.tau * @as(f32, @floatFromInt(p)) / 5.0 + rng.signed() * 0.2;
            b.addBlob(v3(tx + mathx.cosf(pa) * pr, h + 0.014, tz + mathx.sinf(pa) * pr), v3(pr * 0.72, 0.010, pr * 0.72), 3, 5, col);
        }
    }
    return b.toModel(shader);
}

// IVY: a creeper mound with runners climbing out of it. env sets these at the feet of walls and
// columns, where the runners read as going UP the stone.
fn ivyMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(3015);
    b.setMat(.plant);
    // The mound at the base.
    var m: i32 = 0;
    while (m < 10) : (m += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.65);
        const r = rng.range(0.16, 0.32) * (1.0 - 0.25 * d);
        b.addBlob(v3(mathx.cosf(a) * d, rng.range(0.06, 0.30), mathx.sinf(a) * d), v3(r, r * 0.6, r), 3, 6, if (rng.float() < 0.5) IVY_GRN else LEAF_DK);
    }
    // Runners: near-vertical stems with leaves stepped up them, all leaning the same way (they
    // are climbing something).
    const face = rng.angle();
    var s: i32 = 0;
    while (s < 5) : (s += 1) {
        const x0 = mathx.cosf(face) * rng.range(0.1, 0.5) + rng.signed() * 0.2;
        const z0 = mathx.sinf(face) * rng.range(0.1, 0.5) + rng.signed() * 0.2;
        const h = rng.range(0.7, 1.85);
        b.addCylinder(v3(x0, 0.05, z0), v3(x0 + rng.signed() * 0.12, h, z0 + rng.signed() * 0.12), 0.016, 0.008, 4, BARK_DK);
        const nl: i32 = 4 + rng.intn(4);
        var l: i32 = 0;
        while (l < nl) : (l += 1) {
            const t = (@as(f32, @floatFromInt(l)) + 0.6) / @as(f32, @floatFromInt(nl));
            const la = rng.angle();
            const lr = rng.range(0.055, 0.10);
            b.addBlob(v3(x0 + mathx.cosf(la) * lr, h * t, z0 + mathx.sinf(la) * lr), v3(lr, 0.018, lr * 0.9), 3, 5, if (rng.float() < 0.4) LEAF_DK else IVY_GRN);
        }
    }
    return b.toModel(shader);
}

// ── GREAT TREES ── the Old Wood's skyline. Casters (so they lay long raking shadows across
// the plain) and therefore rigid: the depth pass has no wind term, so a swaying caster's
// shadow crawls away from its trunk.

// One great tree's proportions. THREE variants exist (bigtree / bigtree2 / bigtree3) because
// this is the most repeated large prop in the world: with a single mesh, a wood of sixty trees
// is sixty copies of the same silhouette, and yaw + scale do not hide that. Different seeds
// alone would do it, but varying the PROPORTIONS as well gives the wood a species mix.
const TreeSpec = struct {
    seed: u64,
    trunk: f32, // height of the fork — the shorter this is, the more the canopy sits ON the tree
    spread: f32, // bough reach multiplier
    lift: f32, // how much the boughs climb as they reach out (low = a spreading oak, high = a poplar)
    gold: f32, // fraction of canopy masses that catch the sun
};

fn bigTree1(shader: rl.Shader) rl.Model {
    return bigTreeMesh(shader, .{ .seed = 7001, .trunk = 4.5, .spread = 1.0, .lift = 0.55, .gold = 0.30 });
}
fn bigTree2(shader: rl.Shader) rl.Model {
    return bigTreeMesh(shader, .{ .seed = 7011, .trunk = 3.4, .spread = 1.22, .lift = 0.30, .gold = 0.42 }); // squat + broad
}
fn bigTree3(shader: rl.Shader) rl.Model {
    return bigTreeMesh(shader, .{ .seed = 7023, .trunk = 5.6, .spread = 0.82, .lift = 0.85, .gold = 0.22 }); // tall + narrow
}

// A soft, LUMPY canopy mass — many interpenetrating blobs on a rough ellipsoid shell rather
// than one big flattened dome. The dome version read as a MUSHROOM: a bare trunk with a plate
// on top, because a single blob has a smooth silhouette and nothing hangs down between the
// boughs. Masses on the underside are darker (self-shadowed), the sunward crown is gold.
fn canopyInto(b: *Builder, rng: *mathx.Rng, cx: f32, cy: f32, cz: f32, rx: f32, ry: f32, gold: f32, n: i32) void {
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        // Distribute over the SHELL, biased outward, so the mass is hollow-ish and its
        // silhouette is made of many bumps instead of one curve. Masses are LARGE relative to
        // that shell (0.34..0.56 of it) so they interpenetrate into one body: at half this size
        // the canopy read as a cluster of separate BUBBLES hanging in the air.
        const a = rng.angle();
        const t = rng.range(0.30, 0.88);
        const yt = rng.signed(); // -1 = underside, +1 = crown
        const rr = rx * t;
        const px = cx + mathx.cosf(a) * rr;
        const pz = cz + mathx.sinf(a) * rr;
        const py = cy + yt * ry * (1.0 - 0.45 * t);
        const size = rx * rng.range(0.34, 0.56) * (1.0 - 0.20 * t);
        const col = if (yt > 0.35 and rng.float() < gold) LEAF_GOLD else if (yt > 0.0) (if (rng.float() < 0.4) LEAF_LT else LEAF) else if (rng.float() < 0.55) LEAF_DK else LEAF;
        b.addBlob(v3(px, py, pz), v3(size, size * rng.range(0.62, 0.92), size * rng.range(0.82, 1.18)), 5, 7, col);
    }
}

// A GREAT TREE: buttressed root flare, a trunk that leans and forks LOW, boughs reaching out
// and up, and a canopy of interpenetrating foliage masses that clothes those boughs all the way
// in — deep and near-black underneath, gold on the crown where the low sun rakes it. One bough
// is dead and bare (the wabi-sabi break in an otherwise full crown).
fn bigTreeMesh(shader: rl.Shader, spec: TreeSpec) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(spec.seed);
    b.setMat(.wood);
    const leanX = rng.signed() * 0.55;
    const leanZ = rng.signed() * 0.45;
    // Buttress roots: fat capsules splaying from the trunk foot out onto the ground.
    var r: i32 = 0;
    while (r < 7) : (r += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(r)) / 7.0 + rng.signed() * 0.3;
        const d = rng.range(1.1, 1.9);
        b.addCapsule(v3(0, 0.85, 0), v3(mathx.cosf(a) * d, 0.04, mathx.sinf(a) * d), rng.range(0.20, 0.34), rng.range(0.06, 0.12), 6, BARK);
    }
    // Trunk in three lengths, narrowing and drifting off vertical. BARK_OLD, not BARK: a 2 m
    // barrel taking the sun face-on comes back a pale flat beige after the shader's hot key and
    // gamma lift (AGENTS.md: author dark colours near-black, and a big smooth mass needs it most).
    const t1 = v3(leanX * 0.3, spec.trunk * 0.42, leanZ * 0.3);
    const t2 = v3(leanX * 0.7, spec.trunk * 0.78, leanZ * 0.7);
    const fork = v3(leanX, spec.trunk, leanZ);
    b.addCapsule(v3(0, 0.0, 0), t1, 0.95, 0.80, 9, BARK_OLD);
    b.addCapsule(t1, t2, 0.80, 0.62, 9, BARK_OLD);
    b.addCapsule(t2, fork, 0.62, 0.48, 8, BARK);
    // Bark RIDGES: slim darker capsules running up the barrel. Without them the trunk is one
    // smooth lit cylinder and reads as plastic however dark you make it — the form needs breaks.
    //
    // Same correction as the column's flutes (see RELIEF IS SUBTLE): these were 4-SIDED rods, so
    // square bars, and at radius 0.15 sitting as far out as 0.92 of a ~0.93 barrel they stood a
    // FIFTH of the trunk's radius clear of its flats — more proud than the flutes were. Bark is a
    // texture you read at two metres, not a set of battens. Thinner, seated further in so the rod
    // is mostly buried, 6-sided so there is no square corner running the whole height.
    var rb: i32 = 0;
    while (rb < 9) : (rb += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(rb)) / 9.0 + rng.signed() * 0.2;
        const r0 = rng.range(0.70, 0.83);
        const y0 = rng.range(0.0, 0.6);
        const y1 = rng.range(0.65, 1.0) * spec.trunk;
        b.addCapsule(
            v3(mathx.cosf(a) * r0, y0, mathx.sinf(a) * r0),
            v3(mathx.cosf(a + rng.signed() * 0.25) * r0 * 0.72, y1, mathx.sinf(a + rng.signed() * 0.25) * r0 * 0.72),
            rng.range(0.05, 0.10),
            rng.range(0.03, 0.065),
            6,
            if (rng.float() < 0.5) BARK_DK else BARK_OLD,
        );
    }
    // Boughs: six reaching out from the fork zone at wide, uneven bearings.
    const NB = 6;
    var tips: [NB]rl.Vector3 = undefined;
    var i: i32 = 0;
    while (i < NB) : (i += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, NB) + rng.signed() * 0.5;
        const out = rng.range(2.6, 4.4) * spec.spread;
        const up = out * spec.lift * rng.range(0.8, 1.25);
        const base = if (rng.float() < 0.45) t2 else fork;
        const mid = v3(base.x + mathx.cosf(a) * out * 0.45, base.y + up * 0.6, base.z + mathx.sinf(a) * out * 0.45);
        const tip = v3(base.x + mathx.cosf(a) * out, base.y + up, base.z + mathx.sinf(a) * out);
        b.addCapsule(base, mid, 0.34, 0.24, 7, BARK);
        b.addCapsule(mid, tip, 0.24, 0.11, 6, BARK_LIVE);
        // Twiggy sub-branches off each bough, so the canopy has something inside it.
        var s: i32 = 0;
        while (s < 3) : (s += 1) {
            const sa = a + rng.signed() * 1.1;
            const sl = rng.range(0.7, 1.5);
            b.addCapsule(mid, v3(mid.x + mathx.cosf(sa) * sl, mid.y + rng.range(0.4, 1.1), mid.z + mathx.sinf(sa) * sl), 0.09, 0.03, 5, BARK_DK);
        }
        tips[@intCast(i)] = tip;
    }
    // One dead bough, bare and clawing.
    const da = rng.angle();
    b.addCapsule(t2, v3(t2.x + mathx.cosf(da) * 3.4 * spec.spread, t2.y + 0.9, t2.z + mathx.sinf(da) * 3.4), 0.26, 0.05, 6, BARK_DK);

    // THE CANOPY, in three layers so the silhouette is lumpy from every side:
    b.setMat(.plant);
    const crownY = spec.trunk + 2.5 * spec.lift + 1.5;
    const crownR = 3.7 * spec.spread;
    //   1. foliage CLOTHING each bough — this is what removes the bare-trunk/plate-on-top read
    i = 0;
    while (i < NB) : (i += 1) {
        const tip = tips[@intCast(i)];
        const mid = v3((tip.x + fork.x) * 0.5, (tip.y + fork.y) * 0.5 + 0.3, (tip.z + fork.z) * 0.5);
        canopyInto(&b, &rng, tip.x, tip.y + 0.5, tip.z, 1.7 * spec.spread, 1.1, spec.gold, 5);
        canopyInto(&b, &rng, mid.x, mid.y, mid.z, 1.35 * spec.spread, 0.95, spec.gold * 0.5, 3);
    }
    //   2. the main mass over the whole crown
    canopyInto(&b, &rng, leanX * 1.1, crownY, leanZ * 1.1, crownR, 1.9, spec.gold, 16);
    //   3. a gold-touched top, where the sun actually lands
    canopyInto(&b, &rng, leanX * 1.2, crownY + 1.5, leanZ * 1.2, crownR * 0.55, 0.9, 0.85, 5);
    var g: i32 = 0;
    while (g < 4) : (g += 1) {
        const a = rng.angle();
        const d = rng.range(1.2, 2.3);
        tuftInto(&b, &rng, mathx.cosf(a) * d, mathx.sinf(a) * d, rng.range(0.7, 1.0));
    }
    return b.toModel(shader);
}

// A WILLOW at the water's edge: short thick bole, boughs that go UP then break and pour back
// down, with narrow pale foliage strung along the falls. Silvered green — thirstier than the
// wood's oaks.
fn willowMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(7002);
    b.setMat(.wood);
    var r: i32 = 0;
    while (r < 5) : (r += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(r)) / 5.0 + rng.signed() * 0.3;
        b.addCapsule(v3(0, 0.6, 0), v3(mathx.cosf(a) * 1.0, 0.03, mathx.sinf(a) * 1.0), 0.16, 0.06, 5, BARK);
    }
    const crown = v3(rng.signed() * 0.35, 3.4, rng.signed() * 0.3);
    b.addCapsule(v3(0, 0, 0), v3(crown.x * 0.5, 1.8, crown.z * 0.5), 0.70, 0.52, 8, BARK_OLD);
    b.addCapsule(v3(crown.x * 0.5, 1.8, crown.z * 0.5), crown, 0.52, 0.34, 7, BARK);
    // Six boughs up-and-over, each ending well out and DOWN — the willow's whole read.
    const NB = 6;
    var i: i32 = 0;
    while (i < NB) : (i += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, NB) + rng.signed() * 0.35;
        const out = rng.range(2.0, 3.2);
        const top = v3(crown.x + mathx.cosf(a) * out * 0.55, crown.y + rng.range(0.9, 1.7), crown.z + mathx.sinf(a) * out * 0.55);
        const fallTo = v3(crown.x + mathx.cosf(a) * out, rng.range(0.9, 2.1), crown.z + mathx.sinf(a) * out);
        b.addCapsule(crown, top, 0.28, 0.18, 6, BARK);
        b.addCapsule(top, fallTo, 0.18, 0.07, 5, BARK_LIVE);
        // The curtain: narrow foliage masses strung DOWN the fall, plus a few whips below it.
        b.setMat(.plant);
        var c: i32 = 0;
        while (c < 4) : (c += 1) {
            const t = (@as(f32, @floatFromInt(c)) + 0.5) / 4.0;
            const px = top.x + (fallTo.x - top.x) * t;
            const pz = top.z + (fallTo.z - top.z) * t;
            const py = top.y + (fallTo.y - top.y) * t;
            const rr = rng.range(0.55, 0.95);
            b.addBlob(v3(px, py - 0.25, pz), v3(rr * 0.7, rr * 1.25, rr * 0.7), 4, 6, if (rng.float() < 0.45) LEAF_PALE else LEAF);
        }
        var w: i32 = 0;
        while (w < 3) : (w += 1) {
            const wx = fallTo.x + rng.signed() * 0.5;
            const wz = fallTo.z + rng.signed() * 0.5;
            b.addCylinder(v3(wx, fallTo.y - 0.1, wz), v3(wx + rng.signed() * 0.2, rng.range(0.15, 0.7), wz + rng.signed() * 0.2), 0.035, 0.008, 4, LEAF_PALE);
        }
        b.setMat(.wood);
    }
    b.setMat(.plant);
    b.addBlob(crown, v3(1.9, 1.15, 1.85), 5, 8, LEAF_DK); // the dense heart of the crown
    var g: i32 = 0;
    while (g < 3) : (g += 1) {
        const a = rng.angle();
        tuftInto(&b, &rng, mathx.cosf(a) * rng.range(0.9, 1.6), mathx.sinf(a) * rng.range(0.9, 1.6), 0.85);
    }
    return b.toModel(shader);
}

// A CONIFER: a dark spire. Whorls of drooping branch fans stepping in as they rise, over a bare
// straight bole. It exists for the SKYLINE — a wood of nothing but broad round crowns has no
// punctuation in it, and one spire per dozen oaks fixes that.
fn coniferMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(7101);
    b.setMat(.wood);
    const H: f32 = rng.range(9.5, 11.5);
    b.addCapsule(v3(0, 0, 0), v3(rng.signed() * 0.25, H * 0.55, rng.signed() * 0.2), 0.52, 0.32, 8, BARK_OLD);
    b.addCapsule(v3(rng.signed() * 0.25, H * 0.55, rng.signed() * 0.2), v3(rng.signed() * 0.3, H, rng.signed() * 0.25), 0.32, 0.05, 7, BARK_DK);
    var r: i32 = 0;
    while (r < 5) : (r += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(r)) / 5.0;
        b.addCapsule(v3(0, 0.5, 0), v3(mathx.cosf(a) * 0.85, 0.03, mathx.sinf(a) * 0.85), 0.13, 0.05, 5, BARK);
    }
    // Whorls: each one a ring of fans, narrowing with height. Branches DROOP (the tips sit below
    // where they leave the trunk) — that downward sweep is the whole silhouette of a conifer.
    b.setMat(.plant);
    // MANY whorls, closely spaced, and each fan wide enough to reach the one above it. At 13 well-
    // separated whorls the tree read as a PAGODA — a stack of discrete tiers with air between them.
    // A conifer's silhouette is a continuous ragged cone, so the tiers have to overlap.
    const whorls: i32 = 22;
    var w: i32 = 0;
    while (w < whorls) : (w += 1) {
        const t = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(whorls - 1));
        const y = H * (0.16 + 0.84 * t);
        const reach = (3.1 * (1.0 - t * 0.86)) * rng.range(0.86, 1.14);
        const nf: i32 = @max(3, @as(i32, @intFromFloat(6.0 * (1.0 - t * 0.5))));
        var f: i32 = 0;
        while (f < nf) : (f += 1) {
            const a = std.math.tau * @as(f32, @floatFromInt(f)) / @as(f32, @floatFromInt(nf)) + @as(f32, @floatFromInt(w)) * 0.7;
            const px = mathx.cosf(a) * reach;
            const pz = mathx.sinf(a) * reach;
            b.setMat(.wood);
            b.addCapsule(v3(0, y, 0), v3(px, y - reach * 0.22, pz), 0.055, 0.02, 4, BARK_DK);
            b.setMat(.plant);
            // Two masses per fan, the outer one lower — a drooping bough of needles. Deliberately
            // TALL enough (0.22 of reach) to meet the whorl above and close the cone.
            b.addBlob(v3(px * 0.55, y - reach * 0.08, pz * 0.55), v3(reach * 0.42, reach * 0.22, reach * 0.42), 3, 6, if (rng.float() < 0.28) NEEDLE_LT else NEEDLE);
            b.addBlob(v3(px * 0.92, y - reach * 0.20, pz * 0.92), v3(reach * 0.32, reach * 0.17, reach * 0.32), 3, 6, NEEDLE);
        }
    }
    b.addBlob(v3(0, H * 0.99, 0), v3(0.34, 0.65, 0.34), 3, 6, NEEDLE); // the leader
    var g: i32 = 0;
    while (g < 3) : (g += 1) {
        const a = rng.angle();
        tuftInto(&b, &rng, mathx.cosf(a) * rng.range(0.9, 1.7), mathx.sinf(a) * rng.range(0.9, 1.7), 0.75);
    }
    return b.toModel(shader);
}

// A BIRCH: a slender PALE trunk with dark scars, and a light open crown. The only tree you can
// pick out by colour at distance, so it reads as a different species from across the plain.
fn birchMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(7102);
    b.setMat(.wood);
    const H: f32 = rng.range(7.0, 8.6);
    const lean = rng.signed() * 0.5;
    const mid = v3(lean * 0.4, H * 0.5, rng.signed() * 0.3);
    const fork = v3(lean, H * 0.72, rng.signed() * 0.4);
    b.addCapsule(v3(0, 0, 0), mid, 0.30, 0.24, 8, BIRCH_BARK);
    b.addCapsule(mid, fork, 0.24, 0.17, 7, BIRCH_BARK);
    // The scars: short dark bands round the trunk, which is what makes it read as birch and not
    // as a dead pale stick.
    var s: i32 = 0;
    while (s < 12) : (s += 1) {
        const t = rng.range(0.05, 0.70);
        const a = rng.angle();
        const yy = H * t;
        const rr = 0.30 - 0.13 * t;
        b.addBlob(v3(lean * t * 0.55 + mathx.cosf(a) * rr * 0.85, yy, mathx.sinf(a) * rr * 0.85), v3(rr * rng.range(0.25, 0.6), rng.range(0.025, 0.06), rr * rng.range(0.25, 0.6)), 3, 5, BIRCH_SCAR);
    }
    // Branches: fine, ascending, and few — a birch crown is airy, you see sky through it.
    b.setMat(.plant);
    const NB = 7;
    var i: i32 = 0;
    while (i < NB) : (i += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, NB) + rng.signed() * 0.5;
        const out = rng.range(1.4, 2.6);
        const up = rng.range(1.0, 2.2);
        const base = if (rng.float() < 0.4) mid else fork;
        const tip = v3(base.x + mathx.cosf(a) * out, base.y + up, base.z + mathx.sinf(a) * out);
        b.setMat(.wood);
        b.addCapsule(base, tip, 0.09, 0.025, 5, BIRCH_SCAR);
        b.setMat(.plant);
        var c: i32 = 0;
        while (c < 3) : (c += 1) {
            const rr = rng.range(0.55, 0.95);
            b.addBlob(
                v3(tip.x + rng.signed() * 0.7, tip.y + rng.range(-0.3, 0.7), tip.z + rng.signed() * 0.7),
                v3(rr, rr * rng.range(0.6, 0.9), rr * rng.range(0.85, 1.15)),
                4,
                6,
                if (rng.float() < 0.42) LEAF_GOLD else if (rng.float() < 0.6) LEAF_LT else LEAF,
            );
        }
    }
    canopyInto(&b, &rng, lean, H * 0.94, 0, 2.0, 1.1, 0.5, 8);
    var g: i32 = 0;
    while (g < 3) : (g += 1) tuftInto(&b, &rng, rng.signed() * 1.3, rng.signed() * 1.3, 0.8);
    return b.toModel(shader);
}

// A SNAG: a tall dead trunk stripped of bark and branches, snapped off jagged at the top. Pure
// silhouette — the thing a wood needs so its skyline isn't uniformly alive.
fn snagMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(7103);
    b.setMat(.wood);
    const H: f32 = rng.range(6.0, 7.6);
    const lean = rng.signed() * 0.4;
    b.addCapsule(v3(0, 0, 0), v3(lean * 0.5, H * 0.6, lean * 0.3), 0.55, 0.36, 8, BARK_OLD);
    b.addCapsule(v3(lean * 0.5, H * 0.6, lean * 0.3), v3(lean, H, lean * 0.6), 0.36, 0.26, 7, BARK_DK);
    // The snapped crown: splinters of unequal length standing up out of the break.
    var s: i32 = 0;
    while (s < 5) : (s += 1) {
        const a = rng.angle();
        const d = rng.range(0.05, 0.22);
        b.addCapsule(
            v3(lean + mathx.cosf(a) * d, H, lean * 0.6 + mathx.sinf(a) * d),
            v3(lean + mathx.cosf(a) * d * 1.8, H + rng.range(0.25, 0.95), lean * 0.6 + mathx.sinf(a) * d * 1.8),
            rng.range(0.06, 0.14),
            0.015,
            4,
            BARK_DK,
        );
    }
    // A couple of broken limb stubs, and one long bare branch still on.
    var l: i32 = 0;
    while (l < 4) : (l += 1) {
        const a = rng.angle();
        const y = rng.range(H * 0.35, H * 0.9);
        b.addCapsule(v3(lean * 0.4, y, lean * 0.2), v3(lean * 0.4 + mathx.cosf(a) * rng.range(0.5, 1.1), y + rng.range(-0.1, 0.45), lean * 0.2 + mathx.sinf(a) * rng.range(0.5, 1.1)), 0.10, 0.03, 4, BARK_DK);
    }
    const ba = rng.angle();
    b.addCapsule(v3(lean * 0.5, H * 0.7, lean * 0.3), v3(lean * 0.5 + mathx.cosf(ba) * 2.6, H * 0.85, lean * 0.3 + mathx.sinf(ba) * 2.6), 0.16, 0.03, 5, BARK_DK);
    var r: i32 = 0;
    while (r < 5) : (r += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(r)) / 5.0 + rng.signed() * 0.3;
        b.addCapsule(v3(0, 0.5, 0), v3(mathx.cosf(a) * rng.range(0.7, 1.2), 0.03, mathx.sinf(a) * rng.range(0.7, 1.2)), 0.15, 0.05, 5, BARK_OLD);
    }
    b.setMat(.plant);
    b.addBlob(v3(rng.signed() * 0.3, rng.range(0.6, 2.2), rng.signed() * 0.5), v3(0.28, 0.35, 0.24), 3, 6, MOSS_DK); // moss up the weather side
    var g: i32 = 0;
    while (g < 3) : (g += 1) tuftInto(&b, &rng, rng.signed() * 1.2, rng.signed() * 1.2, 0.85);
    return b.toModel(shader);
}

// A SAPLING: a young tree, a couple of whippy stems and a thin crown. Fills the gap between a bush
// and a great tree — a wood with no young trees in it reads as scenery rather than as a forest.
fn saplingMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(7104);
    b.setMat(.wood);
    const H: f32 = rng.range(2.2, 3.1);
    const nstems: i32 = 1 + rng.intn(2);
    var st: i32 = 0;
    while (st < nstems) : (st += 1) {
        const a = rng.angle();
        const off = if (st == 0) @as(f32, 0) else rng.range(0.08, 0.22);
        const x0 = mathx.cosf(a) * off;
        const z0 = mathx.sinf(a) * off;
        const h = H * (if (st == 0) @as(f32, 1.0) else rng.range(0.6, 0.9));
        const tipX = x0 + rng.signed() * 0.30;
        const tipZ = z0 + rng.signed() * 0.30;
        b.addCapsule(v3(x0, 0, z0), v3(tipX, h, tipZ), 0.075, 0.028, 6, BARK);
        // Side twigs, and a small crown of leaf masses on top.
        var tw: i32 = 0;
        while (tw < 4) : (tw += 1) {
            const t = rng.range(0.35, 0.95);
            const ta = rng.angle();
            const tl = rng.range(0.25, 0.6);
            const bx = x0 + (tipX - x0) * t;
            const bz = z0 + (tipZ - z0) * t;
            b.addCapsule(v3(bx, h * t, bz), v3(bx + mathx.cosf(ta) * tl, h * t + rng.range(0.15, 0.45), bz + mathx.sinf(ta) * tl), 0.028, 0.010, 4, BARK_DK);
        }
        // The crown starts LOW on the stem and is made of many small masses. Seven big blobs on the
        // top third made a lollipop; a young tree is leafy most of the way down.
        b.setMat(.plant);
        var c: i32 = 0;
        while (c < 16) : (c += 1) {
            const ca = rng.angle();
            const cd = rng.range(0.0, 0.62);
            const rr = rng.range(0.15, 0.28);
            b.addBlob(
                v3(x0 + (tipX - x0) * 0.7 + mathx.cosf(ca) * cd, h * rng.range(0.34, 1.02), z0 + (tipZ - z0) * 0.7 + mathx.sinf(ca) * cd),
                v3(rr, rr * rng.range(0.6, 0.9), rr * rng.range(0.85, 1.15)),
                4,
                6,
                if (rng.float() < 0.25) LEAF_GOLD else if (rng.float() < 0.5) LEAF_LT else if (rng.float() < 0.75) LEAF else LEAF_DAMP,
            );
        }
        b.setMat(.wood);
    }
    b.setMat(.plant);
    tuftInto(&b, &rng, rng.signed() * 0.5, rng.signed() * 0.5, 0.8);
    return b.toModel(shader);
}

test "every kind row sits at its own index and carries a mesh builder" {
    // The comptime block already asserts the index match; this pins the table's SHAPE so a
    // half-added kind (enum extended, table not) fails as a test rather than at first draw.
    try std.testing.expectEqual(@as(usize, NK), INFO.len);
    for (INFO) |row| try std.testing.expect(row.bound > 0 and row.view > 0);
}

test "collider parts stay inside their kind's bounding sphere" {
    // A part reaching past `bound` means the culling sphere doesn't contain the thing the
    // player can actually bump into — geometry would pop while still blocking movement.
    for (INFO) |row| {
        for (row.parts) |part| {
            const ra = @sqrt(part.ax * part.ax + part.az * part.az) + part.r;
            const rb = @sqrt(part.bx * part.bx + part.bz * part.bz) + part.r;
            try std.testing.expect(@max(ra, rb) <= row.bound + 0.001);
        }
    }
}

test "the watchtower's collider ring leaves exactly one doorway gap" {
    try std.testing.expectEqual(@as(usize, TOWER_SIDES - TOWER_DOOR), towerRing.len);
    // The gap must face local −Z (a tower placed at yaw 0 is entered from the south), so no
    // ring collider may sit on the −Z side of the drum's centre line.
    for (towerRing) |part| try std.testing.expect(part.az > -TOWER_R * 0.85);
}

test "fires carry a light above their base and inside their own bound" {
    for (INFO) |row| {
        const l = row.light orelse continue;
        try std.testing.expect(l.y > 0 and l.y <= row.bound);
        try std.testing.expect(l.radius > 1.0);
        try std.testing.expect(l.flicker >= 0 and l.flicker < 1);
    }
}
