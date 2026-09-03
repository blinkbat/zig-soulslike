const std = @import("std");
const rl = @import("raylib");
const hud = @import("hud.zig");
const mathx = @import("../core/mathx.zig");
const props = @import("../props/props.zig");
const ui = @import("ui.zig");
const mapart = @import("mapart.zig");
const wf = @import("../world/worldfmt.zig");
const dialogmod = @import("../world/dialog.zig");
const envmod = @import("../world/env.zig");
const gfx = @import("../gfx/gfx.zig");
const daynight = @import("../world/daynight.zig");
const objview = @import("objview.zig");
const tuneui = @import("tuneui.zig");
const tunemod = @import("../play/tune.zig");
const item = @import("../play/item.zig");
const combat = @import("../play/combat.zig");
const restmod = @import("../play/rest.zig");
const liquidmod = @import("../play/liquid.zig");
const sfx = @import("../core/audio.zig");
const foemod = @import("../foes/foe.zig");
const cameramod = @import("../core/camera.zig");

const Kind = props.Kind;
const v3 = mathx.v3;


const LOOK_SENS: f32 = cameramod.LOOK_SENS;

/// **THE WINDOW THE PANELS HAVE TO FIT, READ AND NOT COPIED.** `game.SCREEN_H` is the authority (AGENTS.md);
/// two fit tests carried their own `800` and would have kept passing against a window that had moved.
const SCREEN_H: i32 = @import("../game.zig").SCREEN_H;
const UNDO_CAP: usize = 24;
const DRAG_PX = ui.DRAG_PX;
const SNAP: f32 = 1.0;
const REBUILD_QUIET: f32 = 0.28;

const ERASE_HZ: f32 = 5.0;
const ERASE_STEP: f32 = 0.6;
const MAX_MARKERS: usize = 500;

const WATER_EDGE: wf.Edge = .speckle;

const Unit = union(enum) { foe: usize, npc: usize };
const Hover = union(enum) { none, prop: usize, foe: usize, npc: usize };

const NFOE_KIND = @typeInfo(wf.FoeKind).@"enum".fields.len;
const NNPC_KIND = @typeInfo(wf.NpcKind).@"enum".fields.len;

const MAX_MARKED: usize = 512;

const FULL_MSG = "map is full - worldfmt.MAX_OPS reached";
const FOES_FULL_MSG = "foe cap reached";
const FOLK_FULL_MSG = "folk cap reached";

const DUPE_OFFSET: f32 = 6.0;

const AT_SPAN: f32 = 6.0;

const NEW_ZONE_DENSITY: f32 = 0.7;

const FOE_PICK_R: f32 = 1.6;

// File scope: BSS, not inside Game and not on an allocator — a `Map` is megabytes and the ring is `UNDO_CAP` of them.
var undoRing: [UNDO_CAP]wf.Map = undefined;
var undoBase: usize = 0;
var undoN: usize = 0;
var undoAt: usize = 0;

fn undoSlot(i: usize) *wf.Map {
    return &undoRing[(undoBase + i) % UNDO_CAP];
}

fn undoReset() void {
    undoBase = 0;
    undoN = 0;
    undoAt = 0;
}

fn undoDropOldest() void {
    undoBase = (undoBase + 1) % UNDO_CAP;
    undoN -= 1;
}

var clipOps: [MAX_MARKED]wf.Op = undefined;
var nClipOps: usize = 0;
var clipFoes: [MAX_MARKED]wf.Foe = undefined;
var nClipFoes: usize = 0;

var listing: wf.Listing = .{};


pub const Layer = enum(u8) {
    ground,
    locations,
    decor,
    props,
    interact,
    units,

    pub const N = @typeInfo(Layer).@"enum".fields.len;

    fn label(l: Layer) [:0]const u8 {
        return switch (l) {
            .ground => "Ground",
            .locations => "Locations",
            .decor => "Decor",
            .props => "Props",
            .interact => "Interactables",
            .units => "Units",
        };
    }

    fn opLayer(l: Layer) bool {
        return switch (l) {
            .decor, .props, .interact => true,
            .ground, .locations, .units => false,
        };
    }
};

const layerTips = [Layer.N][:0]const u8{
    "Shape the land and paint the soil (Tab cycles layers)",
    "Zone density and the clearings it keeps out of",
    "Small accoutrements - plants, but also cobbles, shards and scree",
    "Props - stone, timber, fire, water",
    "Chests (right-click > Items...) and the fog gate",
    "Creatures and folk (the Foes tab files creatures by kingdom)",
};

const groundBrushes = [_][:0]const u8{
    "Raise",
    "Lower",
    "Smooth",
    "Flat",
    "dirt",
    "turf",
    "stone",
    "silt",
    "ash",
    "moss",
    "bone",
    "cinder",
    "spore",
    "bloom",
    "Water",
    "Oil",
    "Fungal",
    "Lava",
    "Erase",
};
const locationBrushes = [_][:0]const u8{ "Clearing", "Zone", "Location", "Arena", "Erase" };
const decorBrushes = [_][:0]const u8{ "Single", "Patch", "Scatter", "Erase" };
const propBrushes = [_][:0]const u8{ "Stamp", "Row", "Ring", "Cluster", "Ivy", "Erase" };
const interactBrushes = [_][:0]const u8{ "Stamp", "Erase" };
const unitBrushes = blk: {
    var out: [NFOE_KIND + NNPC_KIND + 1][:0]const u8 = undefined;
    for (0..NFOE_KIND) |i| out[i] = wf.foeName(@enumFromInt(i));
    for (0..NNPC_KIND) |i| out[NFOE_KIND + i] = wf.npcName(@enumFromInt(i));
    out[NFOE_KIND + NNPC_KIND] = "Erase";
    break :blk out;
};

const UnitTab = enum {
    foes,
    folk,

    pub const N = @typeInfo(UnitTab).@"enum".fields.len;

    pub fn label(t: UnitTab) [:0]const u8 {
        return switch (t) {
            .foes => "Foes",
            .folk => "Folk",
        };
    }
};

const unitTabTips = [UnitTab.N][:0]const u8{
    "Creatures, filed by the kingdom they read as standing in",
    "Bodies that talk - give one a `dlg=` in the file and it says something",
};

const foeBiomes = blk: {
    var t = [_]bool{false} ** props.Biome.N;
    for (0..NFOE_KIND) |i| {
        const b = foemod.homeOf(@as(wf.FoeKind, @enumFromInt(i)));
        if (b != .any) t[@intFromEnum(b)] = true;
    }
    break :blk t;
};

const FIRST_FOE_BIOME: props.Biome = blk: {
    for (foeBiomes, 0..) |has, i| {
        if (has) break :blk @enumFromInt(i);
    }
    @compileError("editor: no kingdom holds a creature");
};

const MAX_BRUSHES: usize = blk: {
    var most: usize = 0;
    for (0..Layer.N) |i| most = @max(most, brushesFor(@enumFromInt(i)).len);
    break :blk most;
};

const GROUND_SOIL_0: usize = @typeInfo(wf.Sculpt).@"enum".fields.len;

const SCULPT_EVEN: f32 = 0.5;

const DIGIT_KEYS: usize = 9;

const RAISE_SWATCH = ui.col(126, 100, 62, 255);
const LOWER_SWATCH = ui.col(74, 60, 44, 255);
const EVEN_SWATCH = ui.col(96, 100, 104, 255);

const groundTips = [_][:0]const u8{
    "Sweep to raise. [ ] sets size, the panel sets strength",
    "Sweep to lower",
    "Sweep to smooth a lump into a walkable slope",
    "Sweep to flatten toward the height the stroke started on",
    "[ ] sets radius",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "Sweep to flood. Depth, shore and wet sand come off the outline",
    "Tar. Wades like water; bubbles mound and pop. No status",
    "Fungal soup. Wades like water and builds POISON while you stand in it",
    "Molten rock. Wades like water, builds BURNING and bites every second",
    "Sweep to unpaint soil and water. Leaves the sculpted shape",
};
const locationTips = [_][:0]const u8{
    "Drag a circle nothing grows in",
    "Drag a rectangle with its own cover density",
    "Drag a NAMED rectangle. Triggers find it by name; carries its own weather",
    "CLICK EACH CORNER of a boss room; Enter or the first corner closes it, Backspace undoes one, Esc drops it. Then Select and drag its corners",
    "Sweep to erase",
};
const decorTips = [_][:0]const u8{
    "Click to place one",
    "Drag out for a round patch",
    "Drag a rectangle for a scattered belt",
    "Sweep to erase",
};
const propTips = [_][:0]const u8{
    "Click to stamp one",
    "Drag a line for a run, nose to tail",
    "Drag out for an even circle",
    "Drag out for a scattered ring",
    "Drag a box to sow ivy on the stone inside it",
    "Sweep to erase",
};
const interactTips = [_][:0]const u8{
    "Click to place. Right-click > Items... to fill",
    "Sweep to erase",
};
const foeTips = [NFOE_KIND][:0]const u8{
    "",
    "",
    "",
    "Two axes, a wild flurry, then a long opening",
    "No attack, heals the hurt one; break the cast",
    "Stones at range, teeth up close",
    "Slow, spits acid pools, lays up to three sacs",
    "Fast, one hit kills it, leaps",
    "Hatches on its own clock unless you cut it open",
    "Blocks what comes at his front; break the guard, then punish",
    "A long diagonal slam you cannot interrupt; walk out of it",
    "Drains focus up close, wisps at range, teleports when threatened",
    "Flyer. Heals off what it drains, and zooms out of sword reach",
    "Disguised as a snag. Eyes open before its reach does; never moves",
    "Flings itself and bursts a poison spore cloud. Sometimes it trips instead",
    "Unbreakable shield across his front. Work round the side; stand behind him and he falls on you",
    "Travels underground as a moving mound, then bursts up under your feet. Cannot be locked on while down",
    "Skeletons near it stop dissolving and get raised. Also lays a delayed ice ring",
    "Keeps its distance. The flower RISES, then spits spores that HANG before they home. Cornered, it gores",
    "Lobs slow bouncing fireballs. Backing away stays in the bounce line; go sideways",
    "Place in water. Surfaces when you wade; cannot leave water or be hit while down",
    "Very tough against steel, weak to fire and lightning. Slams forward at anyone who backs off",
    "A ribcage on its ribs. Fastest thing on foot; one long vertical slice you can walk out of",
    "No melee. Raises skitterers from bare earth far off, breathes cold up close. Weak to fire",
    "High HP, no armour, feeble bite. Rings the bell on its back and the camp comes; weak to lightning",
    "A shade twice over, slower. Its grip leaves a STUPOR: thin focus and dragged feet. Stand off it",
    "Never moves, never strikes. Swells, then vents SLEEP over 5 m. Walk out of the ring",
    "The ground it walks over stays BURNING. Slower than your run. Fireproof; cold is the answer",
    "EATS THE DEAD to heal, its own kin included. Head down it is wide open. Weak to fire",
    "Slow, high poise. SET IT ALIGHT and it dies in 15 s — half again as fast, and it lights the next one",
    "Frail, feeble. Killing it lights a 0.85 s fuse and it SHATTERS over 3.2 m. They chain",
    "Two-handed trident. The longest common reach in the game; one slow thrust down a line",
    "Throws a NET that takes your feet for 1.35 s — exactly one thrust. Cannot throw it up close",
    "No blow at all. Heals the whole band off its own bars. Softest body, biggest purse: kill it first",
    "Blinks onto your flank, one bite, gone. A bite that LANDS heals it — block it, or stagger the drink off it",
    "Half of the DUO. Fast, lunges to close, poisoned longsword, and he jumps back to come at you again",
    "The other half. Keeps its distance, sprouts BUNCHES that swell and burst, throws chaos orbs, and DISSOLVES when pressed",
    "A carving until you walk close. It wakes, rakes and slams, and hops back to fan stone quills down its own bearing",
};
const npcTips = [NNPC_KIND][:0]const u8{
    "Talks. Roams its own leash, carries a staff. Give it a `dlg=` in the file to say anything",
    "Talks. Camel-humanoid trader; the caravan props are its own family",
    "Talks. A tree, and a smith: hulking, bowed, hammering. Stand him at an Anvil and the forge props are his",
};
const ERASE_UNIT_TIP: [:0]const u8 = "Sweep to erase ([ ] sets radius)";
const unitTips = blk: {
    var out: [NFOE_KIND + NNPC_KIND + 1][:0]const u8 = undefined;
    for (foeTips, 0..) |t, i| out[i] = t;
    for (npcTips, 0..) |t, i| out[NFOE_KIND + i] = t;
    out[NFOE_KIND + NNPC_KIND] = ERASE_UNIT_TIP;
    break :blk out;
};

fn layerIcon(l: Layer) ui.Icon {
    return switch (l) {
        .ground => .ground,
        .locations => .locations,
        .decor => .decor,
        .props => .props,
        .interact => .interact,
        .units => .units,
    };
}

const locationIcons = [_]ui.Icon{ .clearing, .zone, .location, .arena, .erase };
const decorIcons = [_]ui.Icon{ .single, .patch, .scatter, .erase };
const propIcons = [_]ui.Icon{ .stamp, .row, .ring, .cluster, .ivy, .erase };
const interactIcons = [_]ui.Icon{ .stamp, .erase };
const unitIcons = [_]ui.Icon{
    .toad,
    .archer,
    .ogre,
    .berserker,
    .priest,
    .slinger,
    .brood_mother,
    .broodling,
    .brood_sac,
    .shieldman,
    .greatsword,
    .shade,
    .leechfly,
    .rooted,
    .shroom,
    .bone_knight,
    .delver,
    .necromancer,
    .fungal_deer,
    .mushroom_mage,
    .fen_lurker,
    .spore_golem,
    .bone_skitterer,
    .ancient_priest,
    .tolling_hollow,
    .mourner,
    .slumber_bloom,
    .cinder_wake,
    .rotgorger,
    .birchwight,
    .salt_husk,
    .fish_spearman,
    .fish_netter,
    .fish_shaman,
    .blinkbat,
    .fungal_swordsman,
    .fungal_magus,
    .owlbear,
    .wanderer,
    .merchant,
    .smith,
    .erase,
};

comptime {
    pinIcons(LocationBrush, &locationIcons);
    pinIcons(DecorBrush, &decorIcons);
    pinIcons(PropBrush, &propIcons);
    pinIcons(InteractBrush, &interactIcons);
    pinIcons(UnitBrush, &unitIcons);
    std.debug.assert(locationIcons.len == locationBrushes.len);
    std.debug.assert(decorIcons.len == decorBrushes.len);
    std.debug.assert(propIcons.len == propBrushes.len);
    std.debug.assert(interactIcons.len == interactBrushes.len);
    std.debug.assert(unitIcons.len == unitBrushes.len);
    std.debug.assert(groundTips.len == groundBrushes.len);
    std.debug.assert(locationTips.len == locationBrushes.len);
    std.debug.assert(decorTips.len == decorBrushes.len);
    std.debug.assert(propTips.len == propBrushes.len);
    std.debug.assert(interactTips.len == interactBrushes.len);
    std.debug.assert(unitTips.len == unitBrushes.len);
}

fn brushShown(ed: *const Editor, i: usize) bool {
    if (ed.layer != .units) return true;
    if (i + 1 == unitBrushes.len) return true;
    if (i >= NFOE_KIND) return ed.unitTab == .folk;
    return ed.unitTab == .foes and foemod.atHome(@enumFromInt(i), ed.foeBiome);
}

fn visibleBrushes(ed: *const Editor, out: []usize) []const usize {
    var n: usize = 0;
    for (0..brushesFor(ed.layer).len) |i| {
        if (!brushShown(ed, i)) continue;
        out[n] = i;
        n += 1;
    }
    return out[0..n];
}

fn armFirstShown(ed: *Editor) void {
    if (brushShown(ed, ed.brushIdx())) return;
    var buf: [MAX_BRUSHES]usize = undefined;
    const shown = visibleBrushes(ed, &buf);
    if (shown.len > 0) ed.setBrush(shown[0]);
}

fn brushSectionFor(l: Layer, i: usize) ?[:0]const u8 {
    if (l != .ground) return null;
    if (i == 0) return "shape";
    if (i == GROUND_SOIL_0) return "surface";
    return null;
}

fn brushIconsFor(l: Layer) ?[]const ui.Icon {
    return switch (l) {
        .ground => null,
        .locations => &locationIcons,
        .decor => &decorIcons,
        .props => &propIcons,
        .interact => &interactIcons,
        .units => &unitIcons,
    };
}

fn brushesFor(l: Layer) []const [:0]const u8 {
    return switch (l) {
        .ground => &groundBrushes,
        .locations => &locationBrushes,
        .decor => &decorBrushes,
        .props => &propBrushes,
        .interact => &interactBrushes,
        .units => &unitBrushes,
    };
}

fn brushTipsFor(l: Layer) []const [:0]const u8 {
    return switch (l) {
        .ground => &groundTips,
        .locations => &locationTips,
        .decor => &decorTips,
        .props => &propTips,
        .interact => &interactTips,
        .units => &unitTips,
    };
}

comptime {
    std.debug.assert(layerTips.len == Layer.N);
    std.debug.assert(groundBrushes.len == GROUND_SOIL_0 + (wf.Soil.N - 1) + wf.Liquid.N + 1);
    for (0..wf.Liquid.N) |i| {
        std.debug.assert(liquidOf(@enumFromInt(GROUND_SOIL_0 + wf.Soil.N - 1 + i)).? == @as(wf.Liquid, @enumFromInt(i)));
    }
    for (0..wf.Soil.N - 1) |i| {
        const b: GroundBrush = @enumFromInt(GROUND_SOIL_0 + i);
        std.debug.assert(soilOf(b).? == @as(wf.Soil, @enumFromInt(i + 1)));
        std.debug.assert(std.mem.eql(u8, groundBrushes[GROUND_SOIL_0 + i], @tagName(soilOf(b).?)));
    }
    std.debug.assert(unitBrushes.len == NFOE_KIND + NNPC_KIND + 1);
    for (0..NFOE_KIND) |i| {
        const tag = @tagName(@as(wf.FoeKind, @enumFromInt(i)));
        std.debug.assert(std.mem.eql(u8, @tagName(unitIcons[i]), tag));
    }
    for (0..NNPC_KIND) |i| {
        const tag = @tagName(@as(wf.NpcKind, @enumFromInt(i)));
        std.debug.assert(std.mem.eql(u8, @tagName(unitIcons[NFOE_KIND + i]), tag));
    }
}

pub const GroundBrush = enum { raise, lower, smooth, flat, dirt, turf, stone, silt, ash, moss, bone, cinder, spore, bloom, water, oil, fungal, lava, erase };

fn soilOf(b: GroundBrush) ?wf.Soil {
    const i = @intFromEnum(b);
    if (i < GROUND_SOIL_0 or i >= GROUND_SOIL_0 + wf.Soil.N - 1) return null;
    return @enumFromInt(i - GROUND_SOIL_0 + 1);
}

fn liquidOf(b: GroundBrush) ?wf.Liquid {
    return switch (b) {
        .water => .water,
        .oil => .oil,
        .fungal => .fungal,
        .lava => .lava,
        else => null,
    };
}
const LocationBrush = enum { clearing, zone, location, arena, erase };
pub const DecorBrush = enum { single, patch, scatter, erase };
const PropBrush = enum { stamp, row, ring, cluster, ivy, erase };
const InteractBrush = enum { stamp, erase };
const UnitBrush = enum {
    toad,
    archer,
    ogre,
    berserker,
    priest,
    slinger,
    brood_mother,
    broodling,
    brood_sac,
    shieldman,
    greatsword,
    shade,
    leechfly,
    rooted,
    shroom,
    bone_knight,
    delver,
    necromancer,
    fungal_deer,
    mushroom_mage,
    fen_lurker,
    spore_golem,
    bone_skitterer,
    ancient_priest,
    tolling_hollow,
    mourner,
    slumber_bloom,
    cinder_wake,
    rotgorger,
    birchwight,
    salt_husk,
    fish_spearman,
    fish_netter,
    fish_shaman,
    blinkbat,
    fungal_swordsman,
    fungal_magus,
    owlbear,
    wanderer,
    merchant,
    smith,
    erase,
};

comptime {
    pinBrushes(LocationBrush, &locationBrushes);
    pinBrushes(DecorBrush, &decorBrushes);
    pinBrushes(PropBrush, &propBrushes);
    pinBrushes(InteractBrush, &interactBrushes);
    pinBrushes(GroundBrush, &groundBrushes);
    const foeFields = @typeInfo(wf.FoeKind).@"enum".fields;
    const npcFields = @typeInfo(wf.NpcKind).@"enum".fields;
    const unitFields = @typeInfo(UnitBrush).@"enum".fields;
    if (unitFields.len != foeFields.len + npcFields.len + 1) @compileError("editor: UnitBrush is not the foe kinds, then the npc kinds, then an eraser");
    for (foeFields, unitFields[0..foeFields.len]) |f, u| {
        if (!std.mem.eql(u8, f.name, u.name)) @compileError("editor: UnitBrush." ++ u.name ++ " is not wf.FoeKind." ++ f.name);
    }
    for (npcFields, unitFields[foeFields.len..][0..npcFields.len]) |f, u| {
        if (!std.mem.eql(u8, f.name, u.name)) @compileError("editor: UnitBrush." ++ u.name ++ " is not wf.NpcKind." ++ f.name);
    }
    if (!std.mem.eql(u8, unitFields[unitFields.len - 1].name, "erase")) @compileError("editor: UnitBrush must end in `erase`");
}

fn pinIcons(comptime E: type, comptime row: []const ui.Icon) void {
    const fields = @typeInfo(E).@"enum".fields;
    if (fields.len != row.len) @compileError("editor: " ++ @typeName(E) ++ " and its icon row are different lengths");
    for (fields, row) |f, ic| {
        if (!std.mem.eql(u8, f.name, @tagName(ic))) {
            @compileError("editor: icon " ++ @tagName(ic) ++ " is not " ++ @typeName(E) ++ "." ++ f.name);
        }
    }
}

fn pinBrushes(comptime E: type, comptime names: []const [:0]const u8) void {
    const fields = @typeInfo(E).@"enum".fields;
    if (fields.len != names.len) @compileError("editor: " ++ @typeName(E) ++ " and its brush table are different lengths");
    for (fields, names) |f, n| {
        if (f.name.len != n.len) @compileError("editor: brush " ++ n ++ " does not match " ++ @typeName(E) ++ "." ++ f.name);
        for (f.name, n) |a, b| {
            if (a != std.ascii.toLower(b)) @compileError("editor: brush " ++ n ++ " does not match " ++ @typeName(E) ++ "." ++ f.name);
        }
    }
    if (!std.mem.eql(u8, fields[fields.len - 1].name, "erase")) @compileError("editor: " ++ @typeName(E) ++ " must end in `erase`");
}

const floraKinds = props.FLORA_KINDS;
const solidKinds = props.SOLID_KINDS;
const interactKinds = props.INTERACT_KINDS;

fn kindPool(l: Layer) ?[]const Kind {
    return switch (l) {
        .decor => &floraKinds,
        .props => &solidKinds,
        .interact => &interactKinds,
        .ground, .locations, .units => null,
    };
}

const layerGroups = blk: {
    var t = [_][@typeInfo(props.Group).@"enum".fields.len]bool{
        [_]bool{false} ** @typeInfo(props.Group).@"enum".fields.len,
    } ** Layer.N;
    for (0..Layer.N) |i| {
        const l: Layer = @enumFromInt(i);
        const pool = kindPool(l) orelse continue;
        for (pool) |k| t[i][@intFromEnum(props.group(k))] = true;
    }
    break :blk t;
};

fn firstGroup(l: Layer) props.Group {
    for (0..props.Group.N) |g| {
        if (layerGroups[@intFromEnum(l)][g]) return @enumFromInt(g);
    }
    return .ruins;
}

fn layerHasGroup(l: Layer, g: props.Group) bool {
    return layerGroups[@intFromEnum(l)][@intFromEnum(g)];
}

const MIX_COLS: i32 = 3;
const MIX_GROUPS = blk: {
    var n = 0;
    for (0..props.Group.N) |g| {
        if (layerHasGroup(.decor, @enumFromInt(g))) n += 1;
    }
    var out: [n]props.Group = undefined;
    var w = 0;
    for (0..props.Group.N) |g| {
        if (!layerHasGroup(.decor, @enumFromInt(g))) continue;
        out[w] = @enumFromInt(g);
        w += 1;
    }
    break :blk out;
};
const MIX_TAB_ROWS: i32 = (@as(i32, @intCast(MIX_GROUPS.len)) + MIX_COLS - 1) / MIX_COLS;
const FIRST_MIX_GROUP: props.Group = MIX_GROUPS[0];

fn layerOf(o: *const wf.Op) Layer {
    return switch (o.op) {
        .ivy => .props,
        else => switch (props.stock(o.kind)) {
            .decor => .decor,
            .props => .props,
            .interact => .interact,
        },
    };
}

pub const Action = enum { none, leave, playtest };

pub const Modal = enum { none, new_map, open_map, save_as, confirm, objects, loot, boss, jukebox, stats, world, zonemix, script, talk, options };

const VOICE_NAMES = sfx.NAMES;

const JUKE_W: i32 = 1010;
const JUKE_H: i32 = 560;
const JUKE_LIST_W: i32 = 300;
const JUKE_LIST_H: i32 = JUKE_H - 150;
const JUKE_COL_W: i32 = JUKE_W - JUKE_LIST_W - RACK_W - 80;

const LIST_W: i32 = 470;

const DLG_PAD: i32 = 24;
const DLG_BTN_H: i32 = 28;
const DLG_FOOT: i32 = 44;
const TAB_H: i32 = 26;
const LOOT_ROW_H: i32 = 26;
const LOOT_TOP: i32 = 84;

pub const Pending = enum { none, new, open, leave };

const Rect = struct {
    x0: f32,
    z0: f32,
    x1: f32,
    z1: f32,

    fn holds(r: Rect, px: f32, pz: f32) bool {
        return px >= r.x0 and px <= r.x1 and pz >= r.z0 and pz <= r.z1;
    }
};

/// A stepper is 102 px of furniture before it is anything else (`ui.stepper`: two 20 px buttons and a 62 px
/// readout). Handed less it lays its minus button out to the LEFT of the x it was given.
const STEP_MIN_W: i32 = 112;

/// Walks the whole op list, once a frame: MEASURED at 22.8 us over `01_fallen_plain`'s 16,637 ops, 0.14% of a
/// 16.7 ms frame in Debug.
fn gateOnWall(m: *const wf.Map, a: *const wf.Arena) ?*const wf.Op {
    for (m.ops[0..m.nops]) |*o| {
        if (props.info(o.kind).ward and a.onWall(o.x, o.z)) return o;
    }
    return null;
}

const KB_TAG: u8 = 20;
const KB_ARENA_NAME = ui.ddId(KB_TAG, 1, 0);
const KB_LOC_NAME = ui.ddId(KB_TAG, 2, 0);
const KB_ZONE_NAME = ui.ddId(KB_TAG, 3, 0);
const KB_TRIG_ID = ui.ddId(KB_TAG, 4, 0);
const KB_FILE_NAME = ui.ddId(KB_TAG, 5, 0);
const KB_TALK_SAY = ui.ddId(KB_TAG, 6, 0);
const KB_TALK_WHO = ui.ddId(KB_TAG, 8, 0);
fn kbTalkRow(i: usize) u32 {
    return ui.ddId(KB_TAG, 7, i);
}

fn nameField(ed: *Editor, ctx: *ui.Ctx, x: i32, y: i32, w: i32, buf: []u8, len: *usize, cur: []const u8, id: u32, eligible: bool, tip: [:0]const u8) ?[]const u8 {
    const focused = ui.textField(ctx, ui.rect(x, y, w, 26), buf, len, id, eligible, tip);
    if (focused) ed.textFocus = true;
    for (buf[0..len.*]) |*ch| {
        if (ch.* == ' ' or ch.* == '#') ch.* = '_';
    }
    if (!focused) return null;
    const typed = buf[0..len.*];
    if (std.mem.eql(u8, typed, cur)) return null;
    return typed;
}

const MAX_SLOT_ROWS: usize = 32;
const GOLD_LIM: i32 = 5000;
const GOLD_STEP: i32 = 25;
/// Metres of run a stacking kind may be given; `env.MAX_SECTIONS` is the hard stop behind it.
const RISE_LIM: f32 = 24.0;
/// Metres an `at` may be lifted off or bedded into the ground.
const LIFT_LIM: f32 = 12.0;

fn aiTip(a: wf.FoeAi) [:0]const u8 {
    return switch (a) {
        .hold => "Stands on its post and fights whatever comes into its ring",
        .roam => "Wanders about its post, leashed to it",
        .roam_free => "Wanders and does not go home",
        .patrol => "Walks the route below, leg to leg",
    };
}

/// Smallest a clearing may be dragged or stepped down to, in metres.
const MIN_CLEARING_R: f32 = 2.0;

/// The payload is WHICH HANDLE: a rect's corner 0..3 in `(x,z) (x1,z) (x1,z1) (x,z1)` order, a room's corner
/// index, or the clearing's rim. `null` — and `false` for the clearing — is the BODY.
const Grab = union(enum) {
    arena: ?u8,
    zone: ?u8,
    loc: ?u8,
    clearing: bool,
};

fn rectCorner(x: f32, z: f32, x1: f32, z1: f32, i: u8) rl.Vector3 {
    return switch (i & 3) {
        0 => mathx.ground(x, z),
        1 => mathx.ground(x1, z),
        2 => mathx.ground(x1, z1),
        else => mathx.ground(x, z1),
    };
}

fn normRect(a: rl.Vector3, b: rl.Vector3) Rect {
    return .{
        .x0 = @min(a.x, b.x),
        .z0 = @min(a.z, b.z),
        .x1 = @max(a.x, b.x),
        .z1 = @max(a.z, b.z),
    };
}

fn hasSpan(k: wf.OpKind) bool {
    return switch (k) {
        .belt, .ivy, .line => true,
        else => false,
    };
}

fn opAnchor(o: *const wf.Op) rl.Vector3 {
    if (hasSpan(o.op)) return v3((o.x + o.x1) * 0.5, 0, (o.z + o.z1) * 0.5);
    return v3(o.x, 0, o.z);
}

fn translateOp(o: *wf.Op, dx: f32, dz: f32) void {
    o.x += dx;
    o.z += dz;
    if (hasSpan(o.op)) {
        o.x1 += dx;
        o.z1 += dz;
    }
}

fn eraseMiss(l: Layer) [:0]const u8 {
    return switch (l) {
        .ground => "",
        .locations => "nothing here (the last zone is the fallback and stays)",
        .units => "no spawn inside the brush",
        .decor, .props, .interact => "nothing in this layer here",
    };
}

const Wipe = struct {
    on: bool = false,
    at: rl.Vector3 = mathx.zero3,
    t: f32 = 0,
    n: usize = 0,
};


pub const Editor = struct {
    on: bool = false,
    cam: rl.Camera3D = undefined,
    world: ?*const envmod.Env = null,
    focus: rl.Vector3 = mathx.zero3,
    yaw: f32 = 0,
    pitch: f32 = -0.7,
    dist: f32 = 28,
    panning: bool = false,
    panGrab: rl.Vector3 = mathx.zero3,

    selecting: bool = false,
    layer: Layer = .props,
    shown: [Layer.N]bool = [_]bool{true} ** Layer.N,
    showWeather: bool = false,
    showFog: bool = true,
    showShadows: bool = false,
    brush: [Layer.N]usize = [_]usize{0} ** Layer.N,
    decorKind: Kind = .fern,
    propKind: Kind = .pillar,
    interactKind: Kind = .chest,
    groupSel: props.Group = .ruins,
    unitTab: UnitTab = .foes,
    foeBiome: props.Biome = FIRST_FOE_BIOME,
    radius: f32 = 6.0,
    soilOpacity: f32 = 1.0,
    brushEdge: wf.Edge = .natural,
    snap: bool = false,

    sel: ?usize = null,
    selUnit: ?Unit = null,
    dirty: bool = false,
    mapGen: u32 = 0,
    folkDue: bool = false,
    folkT: f32 = 0,
    miniGen: u64 = 0,

    kindScroll: i32 = 0,

    cursor: ?rl.Vector3 = null,

    dragging: bool = false,
    dragFrom: rl.Vector3 = mathx.zero3,
    dragTo: rl.Vector3 = mathx.zero3,
    painting: bool = false,
    wetStroke: bool = false,
    heightStroke: bool = false,
    sculptRate: f32 = 3.0,
    wipe: Wipe = .{},
    rmbDown: bool = false,
    rmbTravel: f32 = 0,
    menuOpen: bool = false,
    menuAt: rl.Vector2 = .{ .x = 0, .y = 0 },
    rebuildDue: bool = false,
    rebuildT: f32 = 0,

    marked: [MAX_MARKED]usize = undefined,
    nMarked: usize = 0,
    marquee: bool = false,
    hover: Hover = .none,
    hoverLive: bool = false,
    moving: bool = false,
    moveFrom: rl.Vector3 = mathx.zero3,

    modal: Modal = .none,
    pending: Pending = .none,
    objects: objview.State = .{},
    stats: tuneui.State = .{},
    juke: usize = 0,
    jukeScroll: i32 = 0,
    jukeWorld: bool = false,
    rackMix: sfx.Submix = .combat,
    rackOnVoice: bool = false,
    zoneSel: ?usize = null,
    locSel: ?usize = null,
    arenaSel: ?usize = null,
    clearSel: ?usize = null,
    grab: ?Grab = null,
    grabLive: bool = false,
    grabFrom: rl.Vector3 = mathx.zero3,
    grabBanked: bool = false,
    routing: bool = false,
    trigSel: ?usize = null,
    slotLabels: [MAX_SLOT_ROWS][wf.ID_CAP]u8 = undefined,
    trigNameBuf: [wf.ID_CAP]u8 = [_]u8{0} ** wf.ID_CAP,
    trigNameLen: usize = 0,
    trigScroll: i32 = 0,
    lineBuf: [96]u8 = [_]u8{0} ** 96,
    lineLen: usize = 0,
    arenaNameBuf: [wf.NAME_CAP]u8 = [_]u8{0} ** wf.NAME_CAP,
    arenaNameLen: usize = 0,
    locNameBuf: [wf.NAME_CAP]u8 = [_]u8{0} ** wf.NAME_CAP,
    locNameLen: usize = 0,
    pendX: [wf.MAX_ARENA_VERTS]f32 = [_]f32{0} ** wf.MAX_ARENA_VERTS,
    pendZ: [wf.MAX_ARENA_VERTS]f32 = [_]f32{0} ** wf.MAX_ARENA_VERTS,
    nPend: u8 = 0,
    lootTab: item.Class = .tool,
    mixTab: props.Group = FIRST_MIX_GROUP,
    talkNpc: ?usize = null,
    talkDlg: u16 = wf.NO_DIALOG,
    talkFlat: bool = true,
    talkSay: [wf.TALK_SAY_CAP + 1]u8 = [_]u8{0} ** (wf.TALK_SAY_CAP + 1),
    talkSayLen: usize = 0,
    talkWho: [wf.TALK_LABEL_CAP + 1]u8 = [_]u8{0} ** (wf.TALK_LABEL_CAP + 1),
    talkWhoLen: usize = 0,
    talkRow: [wf.MAX_CHOICES][wf.TALK_LABEL_CAP + 1]u8 = [_][wf.TALK_LABEL_CAP + 1]u8{[_]u8{0} ** (wf.TALK_LABEL_CAP + 1)} ** wf.MAX_CHOICES,
    talkRowLen: [wf.MAX_CHOICES]usize = [_]usize{0} ** wf.MAX_CHOICES,
    talkDoes: [wf.MAX_CHOICES]wf.Does = [_]wf.Does{.leave} ** wf.MAX_CHOICES,
    talkRows: usize = 0,
    zoneNameLen: usize = 0,
    zoneNameBuf: [wf.NAME_CAP]u8 = [_]u8{0} ** wf.NAME_CAP,
    textFocus: bool = false,
    nameBuf: [wf.NAME_CAP]u8 = undefined,
    nameLen: usize = 0,
    fileSel: usize = 0,
    fileScroll: i32 = 0,
    path: [wf.PATH_CAP]u8 = undefined,
    pathLen: usize = 0,
    hotFrame: bool = false,
    wasOverlaid: bool = false,
    editing: bool = false,
    selOwned: usize = 0,
    selMarked: usize = 0,

    status: [ui.MSG_CAP]u8 = undefined,
    statusLen: usize = 0,
    statusT: f32 = 0,

    pub fn auditioning(self: *const Editor) bool {
        return self.modal == .jukebox;
    }

    fn jukeKeys(self: *Editor) void {
        var moved = false;
        if (rl.isKeyPressed(.down) and self.juke + 1 < VOICE_NAMES.len) {
            self.juke += 1;
            moved = true;
        }
        if (rl.isKeyPressed(.up) and self.juke > 0) {
            self.juke -= 1;
            moved = true;
        }
        if (moved) {
            self.jukeReveal();
            self.jukePlay();
        }
        if (rl.isKeyPressed(.space)) self.jukePlay();
    }

    fn jukeReveal(self: *Editor) void {
        const rows = ui.listRows(JUKE_LIST_H);
        const sel: i32 = @intCast(self.juke);
        if (sel < self.jukeScroll) self.jukeScroll = sel;
        if (sel > self.jukeScroll + rows - 1) self.jukeScroll = sel - rows + 1;
    }

    fn jukePlay(self: *Editor) void {
        if (self.juke >= VOICE_NAMES.len) return;
        const id: sfx.Id = @enumFromInt(self.juke);
        if (self.jukeWorld) sfx.world(id, self.focus) else sfx.play(id);
        self.sayFmt("played {s}", .{VOICE_NAMES[self.juke]});
    }

    pub fn enter(self: *Editor, at: rl.Vector3) void {
        self.on = true;
        self.yaw = 0;
        self.pitch = -0.7;
        self.dist = 28;
        self.focus = v3(at.x, at.y, at.z);
        self.cam = .{
            .position = at,
            .target = at,
            .up = v3(0, 1, 0),
            .fovy = 55,
            .projection = .perspective,
        };
        self.applyCam();
        self.selecting = false;
        self.panning = false;
        self.dragging = false;
        self.painting = false;
        self.wetStroke = false;
        self.heightStroke = false;
        self.hover = .none;
        self.hoverLive = false;
        self.wipe = .{};
        self.menuOpen = false;
        self.marquee = false;
        self.moving = false;
        self.showWeather = false;
        self.dropSelection();
        self.dropPendingRoom();
        self.modal = .none;
        self.pending = .none;
        self.rmbDown = false;
        self.rmbTravel = 0;
        self.hotFrame = false;
        self.editing = false;
        if (self.pathLen == 0) self.setPath(wf.START_MAP);
        undoReset();
        self.touchFolk();
        self.say("Editor ready");
    }

    fn setPath(self: *Editor, p: []const u8) void {
        const n = @min(p.len, self.path.len - 1);
        @memcpy(self.path[0..n], p[0..n]);
        self.path[n] = 0;
        self.pathLen = n;
    }

    fn curPath(self: *const Editor) []const u8 {
        return self.path[0..self.pathLen];
    }

    pub fn say(self: *Editor, msg: []const u8) void {
        const n = @min(msg.len, self.status.len - 1);
        @memcpy(self.status[0..n], msg[0..n]);
        self.statusLen = n;
        self.statusT = 5.0;
    }

    fn sayFmt(self: *Editor, comptime fmt: []const u8, args: anytype) void {
        var buf: [ui.MSG_CAP]u8 = undefined;
        self.say(std.fmt.bufPrint(&buf, fmt, args) catch fmt);
    }

    fn brushIdx(self: *const Editor) usize {
        return self.brush[@intFromEnum(self.layer)];
    }
    fn setBrush(self: *Editor, i: usize) void {
        self.brush[@intFromEnum(self.layer)] = @min(i, brushesFor(self.layer).len - 1);
    }
    fn erasing(self: *const Editor) bool {
        return self.brushIdx() == brushesFor(self.layer).len - 1;
    }
    fn kindSlot(self: *Editor) *Kind {
        return switch (self.layer) {
            .decor => &self.decorKind,
            .interact => &self.interactKind,
            .ground, .locations, .props, .units => &self.propKind,
        };
    }
    fn kindForLayer(self: *const Editor) Kind {
        return switch (self.layer) {
            .decor => self.decorKind,
            .interact => self.interactKind,
            .ground, .locations, .props, .units => self.propKind,
        };
    }

    pub fn setLayer(self: *Editor, l: Layer) void {
        if (self.dragging or self.painting or self.wipe.on) return;
        if (self.layer != l) self.nMarked = 0;
        self.layer = l;
        if (l.opLayer() and !layerHasGroup(l, self.groupSel)) self.groupSel = firstGroup(l);
        if (l == .units) self.showArmedUnit();
    }

    fn showArmedUnit(self: *Editor) void {
        const i = self.brush[@intFromEnum(Layer.units)];
        if (i + 1 == unitBrushes.len) return;
        if (i >= NFOE_KIND) {
            self.unitTab = .folk;
            return;
        }
        self.unitTab = .foes;
        const home = foemod.homeOf(@enumFromInt(i));
        if (home != .any) self.foeBiome = home;
    }


    fn forward(self: *const Editor) rl.Vector3 {
        const cp = mathx.cosf(self.pitch);
        return v3(mathx.sinf(self.yaw) * cp, mathx.sinf(self.pitch), mathx.cosf(self.yaw) * cp);
    }

    fn right(self: *const Editor) rl.Vector3 {
        const f = self.forward();
        return mathx.normV(v3(-f.z, 0, f.x));
    }

    fn applyCam(self: *Editor) void {
        const f = self.forward();
        self.cam.target = self.focus;
        self.cam.position = mathx.addV(self.focus, mathx.scaleV(f, -self.dist));
        self.cam.position.y = @max(self.cam.position.y, self.groundHeight(self.cam.position.x, self.cam.position.z) + 0.6);
    }

    fn orbitCam(self: *Editor, ctrl: bool) void {
        if (rl.isMouseButtonPressed(.right)) {
            self.rmbDown = true;
            self.rmbTravel = 0;
        }
        if (self.rmbDown and rl.isMouseButtonDown(.right)) {
            const d = rl.getMouseDelta();
            self.rmbTravel += @abs(d.x) + @abs(d.y);
            if (self.rmbTravel > DRAG_PX) {
                self.yaw -= d.x * LOOK_SENS;
                self.pitch = mathx.clampF(self.pitch - d.y * LOOK_SENS, -1.45, -0.06);
            }
        }

        const wheel = rl.getMouseWheelMove();
        if (wheel != 0 and !self.hotFrame) {
            self.dist = mathx.clampF(self.dist * (1.0 - wheel * 0.12), 2.0, 900.0);
        }

        if (!ctrl and !self.textFocus) {
            const step = self.dist * 0.02;
            const gf = self.groundForward();
            const r = self.right();
            if (rl.isKeyDown(.w) or rl.isKeyDown(.up)) self.focus = mathx.addV(self.focus, mathx.scaleV(gf, step));
            if (rl.isKeyDown(.s) or rl.isKeyDown(.down)) self.focus = mathx.addV(self.focus, mathx.scaleV(gf, -step));
            if (rl.isKeyDown(.d) or rl.isKeyDown(.right)) self.focus = mathx.addV(self.focus, mathx.scaleV(r, step));
            if (rl.isKeyDown(.a) or rl.isKeyDown(.left)) self.focus = mathx.addV(self.focus, mathx.scaleV(r, -step));
        }
        self.focusToGround();
        self.applyCam();
    }

    fn groundForward(self: *const Editor) rl.Vector3 {
        const f = self.forward();
        const l = mathx.lenXZ(f);
        if (l < 1e-5) return v3(0, 0, 1);
        return v3(f.x / l, 0, f.z / l);
    }

    fn dragPan(self: *Editor) void {
        const now = self.groundAt() orelse return;
        self.focus.x += self.panGrab.x - now.x;
        self.focus.z += self.panGrab.z - now.z;
        self.focusToGround();
        self.applyCam();
        self.resolveCursor();
    }

    /// Where the cursor meets the ground, resolved once for THIS frame: `env.rayGround` is a march over the height lattice, some 1600 bilinear samples for a ray that never lands, and five sites ask it a frame.
    pub fn groundAt(self: *const Editor) ?rl.Vector3 {
        return self.cursor;
    }

    fn resolveCursor(self: *Editor) void {
        self.cursor = self.traceGround();
    }

    fn traceGround(self: *const Editor) ?rl.Vector3 {
        const ray = rl.getScreenToWorldRay(rl.getMousePosition(), self.cam);
        if (ray.direction.y > -1e-4) return null;
        var p = blk: {
            if (self.world) |w| break :blk w.rayGround(ray.position, ray.direction) orelse return null;
            const t = (envmod.groundY() - ray.position.y) / ray.direction.y;
            if (t <= 0) return null;
            break :blk mathx.addV(ray.position, mathx.scaleV(ray.direction, t));
        };
        if (self.snap) {
            p.x = @round(p.x / SNAP) * SNAP;
            p.z = @round(p.z / SNAP) * SNAP;
            p.y = self.groundHeight(p.x, p.z);
        }
        return p;
    }

    pub fn groundHeight(self: *const Editor, x: f32, z: f32) f32 {
        if (self.world) |w| return w.groundAt(x, z);
        return envmod.groundY();
    }

    fn focusToGround(self: *Editor) void {
        self.focus.y = self.groundHeight(self.focus.x, self.focus.z);
    }


    pub fn bank(self: *Editor, m: *const wf.Map) void {
        if (undoAt > 0) {
            undoN -= undoAt;
            undoAt = 0;
        }
        if (undoN == UNDO_CAP) undoDropOldest();
        undoSlot(undoN).* = m.*;
        undoN += 1;
        self.dirty = true;
        self.miniGen +%= 1;
    }

    fn undo(self: *Editor, m: *wf.Map) bool {
        if (undoN == 0 or undoAt >= undoN) return false;
        if (undoAt == 0) {
            if (undoN == UNDO_CAP) undoDropOldest();
            undoSlot(undoN).* = m.*;
            undoN += 1;
            undoAt = 1;
        }
        undoAt += 1;
        m.* = undoSlot(undoN - undoAt).*;
        self.dropSelection();
        self.dropPendingRoom();
        self.touchFolk();
        return true;
    }

    fn redo(self: *Editor, m: *wf.Map) bool {
        if (undoAt <= 1) return false;
        undoAt -= 1;
        m.* = undoSlot(undoN - undoAt).*;
        self.dropSelection();
        self.dropPendingRoom();
        self.touchFolk();
        return true;
    }

    fn touchFolk(self: *Editor) void {
        self.mapGen +%= 1;
        self.miniGen +%= 1;
    }

    fn requestFolk(self: *Editor) void {
        self.folkDue = true;
        self.folkT = 0;
    }

    fn tickFolk(self: *Editor, dt: f32) void {
        if (!self.folkDue) return;
        self.folkT += dt;
        if (self.folkT < REBUILD_QUIET) return;
        self.folkDue = false;
        self.folkT = 0;
        self.touchFolk();
    }

    fn dropSelection(self: *Editor) void {
        self.sel = null;
        self.selUnit = null;
        self.nMarked = 0;
        self.zoneSel = null;
        self.locSel = null;
        self.arenaSel = null;
        self.clearSel = null;
        self.grab = null;
        self.grabLive = false;
        self.routing = false;
    }

    fn dropPendingRoom(self: *Editor) void {
        self.nPend = 0;
    }

    pub fn applyCamForShot(self: *Editor) void {
        self.applyCam();
        self.resolveCursor();
    }

    pub fn focusOnForShot(self: *Editor, m: *const wf.Map, i: usize) void {
        self.focusOn(m, i);
    }

    pub fn selectArenaForShot(self: *Editor, m: *const wf.Map, i: usize, grabbed: ?u8) void {
        self.selectArena(m, i);
        self.grab = if (grabbed) |v| .{ .arena = v } else null;
        self.grabLive = false;
    }

    fn grabbedVert(self: *const Editor) ?u8 {
        const g = self.grab orelse return null;
        return switch (g) {
            .arena => |v| v,
            else => null,
        };
    }

    pub fn trigSelForShot(self: *const Editor) ?usize {
        return self.trigSel;
    }

    pub fn openScriptForShot(self: *Editor, m: *const wf.Map) void {
        self.modal = .script;
        if (m.ntrigs > 0) self.selectTrig(m, 0);
    }

    pub fn selectForShot(self: *Editor, m: *const wf.Map, a: rl.Vector3, b: rl.Vector3) void {
        self.marqueeSelect(m, a, b);
    }

    pub fn unitsForShot(self: *Editor, tab: UnitTab, home: props.Biome) void {
        self.layer = .units;
        self.unitTab = tab;
        if (foeBiomes[@intFromEnum(home)]) self.foeBiome = home;
        self.selecting = false;
        self.setBrush(0);
        armFirstShown(self);
    }

    pub fn openForShot(self: *Editor) void {
        listing.scan();
        self.fileSel = 0;
        self.fileScroll = 0;
        self.modal = .open_map;
    }

    pub fn worldForShot(self: *Editor) void {
        self.menuOpen = false;
        self.modal = .world;
    }
    pub fn optionsForShot(self: *Editor) void {
        self.menuOpen = false;
        self.modal = .options;
    }
    pub fn talkForShot(self: *Editor, m: *wf.Map, rec: usize) void {
        self.menuOpen = false;
        openTalk(self, m, rec);
    }
    pub fn talkIsFlatForShot(self: *const Editor) bool {
        return self.talkFlat;
    }
    pub fn zoneMixForShot(self: *Editor, m: *const wf.Map, i: usize) void {
        self.selectZone(m, i);
        self.menuOpen = false;
        self.modal = .zonemix;
    }
    pub fn closeModalForShot(self: *Editor) void {
        self.modal = .none;
    }
    pub fn gradientForShot(self: *Editor, m: *wf.Map, i: usize) void {
        if (i >= m.nops) return;
        const o = &m.ops[i];
        self.setLayer(layerOf(o));
        self.sel = i;
        o.gAxis = .x;
        o.gA = @min(o.x, o.x1);
        o.gB = @max(o.x, o.x1);
        if (o.gB - o.gA < 1.0) o.gB = o.gA + 1.0;
        o.gFloor = 0.25;
    }

    pub fn statsForShot(self: *Editor, tableName: []const u8, row: usize) void {
        self.modal = .stats;
        self.menuOpen = false;
        self.stats = .{};
        for (tunemod.TABLES, 0..) |tb, i| {
            if (std.mem.eql(u8, tb.name, tableName)) self.stats.tab = i;
        }
        self.stats.row = @min(row, tunemod.TABLES[self.stats.tab].n - 1);
    }

    pub fn statsPickForShot(self: *Editor, c: usize) void {
        tuneui.openPickForShot(self.stats.tab, self.stats.row, c);
    }

    pub fn statsTabForShot(self: *const Editor) usize {
        return self.stats.tab;
    }

    pub fn itemForShot(self: *Editor, k: item.Kind) void {
        self.modal = .objects;
        self.menuOpen = false;
        self.objects.mode = .icons;
        self.objects.openIcon = objview.itemSlot(k);
    }

    pub fn soundsForShot(self: *Editor, id: sfx.Id) void {
        self.modal = .jukebox;
        self.menuOpen = false;
        self.juke = @intFromEnum(id);
        self.jukeReveal();
    }

    pub fn charForShot(self: *Editor, k: wf.FoeKind) void {
        self.modal = .objects;
        self.objects.mode = .chars;
        self.objects.openChar = objview.charSlot(k);
        self.objects.grabbed = null;
    }

    pub fn objectsForShot(self: *Editor, shelf: objview.Shelf, page: i32, one: ?Kind) void {
        self.modal = .objects;
        self.objects.shelf = shelf;
        self.objects.page = page;
        self.objects.open = one;
        self.objects.grabbed = null;
    }

    fn focusOn(self: *Editor, m: *const wf.Map, i: usize) void {
        if (i >= m.nops) return;
        const o = m.ops[i];
        const span = switch (o.op) {
            .belt, .ivy => @max(@abs(o.x1 - o.x), @abs(o.z1 - o.z)),
            .disc => o.r1 * 2,
            .ring => o.r0 * 2,
            .line => mathx.distXZ(v3(o.x, 0, o.z), v3(o.x1, 0, o.z1)),
            .at => AT_SPAN,
        };
        const c = opAnchor(&o);
        self.lookAtGround(c.x, c.z, span);
    }

    fn lookAtGround(self: *Editor, cx: f32, cz: f32, span: f32) void {
        self.dist = mathx.clampF(span * 0.8 + 12, 14, 150);
        self.pitch = if (span > 90) -1.05 else -0.72;
        self.yaw = 0;
        self.focus = mathx.ground(cx, cz);
        self.focusToGround();
        self.applyCam();
        self.resolveCursor();
    }


    pub fn update(self: *Editor, m: *wf.Map, env: *envmod.Env, day: *daynight.Clock, dt: f32) Action {
        self.world = env;
        self.statusT = @max(0, self.statusT - dt);
        self.wipe.t += dt;
        self.tickRebuild(m, env, dt);

        if (self.modal != .none) {
            self.rmbDown = false;
            self.rmbTravel = 0;
            self.panning = false;
            self.dragging = false;
            self.marquee = false;
            self.moving = false;
            self.hover = .none;
            self.hoverLive = false;
            self.resolveCursor();
            if (self.wipe.on) self.wipeEnd();
            if (self.modal == .jukebox) self.jukeKeys();
            if (rl.isKeyPressed(.escape)) {
                if (!(self.modal == .objects and objview.back(&self.objects))) {
                    self.modal = .none;
                    self.pending = .none;
                }
            }
            return .none;
        }
        const ctrl = rl.isKeyDown(.left_control) or rl.isKeyDown(.right_control);
        const shift = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
        self.orbitCam(ctrl);
        self.resolveCursor();
        sfx.listen(self.cam.position, self.right());
        if (self.pending == .leave) {
            self.pending = .none;
            return .leave;
        }

        if (ctrl and rl.isKeyPressed(.s)) {
            if (shift) {
                self.nameLen = 0;
                self.menuOpen = false;
                self.modal = .save_as;
            } else _ = self.saveNow(m);
            return .none;
        }
        if (ctrl and rl.isKeyPressed(.n)) {
            self.request(.new);
            return .none;
        }
        if (ctrl and rl.isKeyPressed(.o)) {
            self.request(.open);
            return .none;
        }
        if (ctrl and rl.isKeyPressed(.c)) {
            self.copyMarked(m, env, false);
            return .none;
        }
        if (ctrl and rl.isKeyPressed(.x)) {
            self.copyMarked(m, env, true);
            return .none;
        }
        if (ctrl and rl.isKeyPressed(.v)) {
            self.paste(m, env);
            return .none;
        }
        if (ctrl and rl.isKeyPressed(.a)) {
            const far = m.half * 4;
            self.marqueeSelect(m, v3(-far, 0, -far), v3(far, 0, far));
            return .none;
        }
        if (ctrl and rl.isKeyPressed(.z)) {
            if (self.undo(m)) {
                self.rebuild(m, env);
                self.say("Undo");
            }
            return .none;
        }
        if (ctrl and rl.isKeyPressed(.y)) {
            if (self.redo(m)) {
                self.rebuild(m, env);
                self.say("Redo");
            }
            return .none;
        }
        if (self.arenaSel != null and self.layer == .locations) {
            if (rl.isKeyPressed(.insert)) {
                self.splitLongestWall(m);
                return .none;
            }
            if (rl.isKeyPressed(.delete) and self.grabbedVert() != null) {
                self.dropCorner(m);
                return .none;
            }
        }
        if (self.nPend > 0) {
            if (rl.isKeyPressed(.enter)) {
                self.closeArena(m);
                return .none;
            }
            if (rl.isKeyPressed(.backspace)) {
                self.nPend -= 1;
                self.sayFmt("{d} corners", .{self.nPend});
                return .none;
            }
            if (rl.isKeyPressed(.escape)) {
                self.nPend = 0;
                self.say("room dropped");
                return .none;
            }
        }
        if (rl.isKeyPressed(.escape)) {
            if (self.menuOpen) {
                self.menuOpen = false;
                return .none;
            }
            if (!self.selecting) {
                self.selecting = true;
                self.say("select");
                return .none;
            }
            if (self.sel != null or self.selUnit != null or self.nMarked > 0) {
                self.sel = null;
                self.selUnit = null;
                self.nMarked = 0;
                self.say("deselect");
                return .none;
            }
            self.request(.leave);
            return .none;
        }
        if (rl.isKeyPressed(.f5)) return .playtest;

        if (!self.textFocus) {
            if (rl.isKeyPressed(.tab)) {
                const back = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
                const cur = @intFromEnum(self.layer);
                const next = if (back) (cur + Layer.N - 1) % Layer.N else (cur + 1) % Layer.N;
                self.setLayer(@enumFromInt(next));
                self.sayFmt("{s}", .{self.layer.label()});
            }
            const digits = [_]rl.KeyboardKey{ .one, .two, .three, .four, .five, .six, .seven, .eight, .nine };
            var seen: [MAX_BRUSHES]usize = undefined;
            const shown = visibleBrushes(self, &seen);
            for (digits, 0..) |k, i| {
                if (rl.isKeyPressed(k) and i < shown.len and
                    !self.dragging and !self.painting and !self.wipe.on)
                {
                    self.setBrush(shown[i]);
                    self.selecting = false;
                }
            }
            if (rl.isKeyPressed(.g)) {
                self.snap = !self.snap;
                self.sayFmt("grid snap {s}", .{if (self.snap) "on" else "off"});
            }
            if (rl.isKeyPressed(.left_bracket)) self.radius = mathx.clampF(self.radius - 1, 1, 60);
            if (rl.isKeyPressed(.right_bracket)) self.radius = mathx.clampF(self.radius + 1, 1, 60);
            {
                const fast = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
                const rate: f32 = if (fast) EDIT_HOUR_FAST else EDIT_HOUR_RATE;
                if (rl.isKeyDown(.comma)) day.nudge(-rate * dt);
                if (rl.isKeyDown(.period)) day.nudge(rate * dt);
                if (rl.isKeyPressed(.comma) or rl.isKeyPressed(.period)) {
                    var buf: [8]u8 = undefined;
                    self.sayFmt("{s} {s}", .{ daynight.clockText(day.hour, &buf), daynight.phaseName(day.hour) });
                }
            }
            if (rl.isKeyPressed(.r)) self.rerollSel(m, env);
            if (rl.isKeyPressed(.delete)) {
                if (self.nMarked > 0) self.deleteMarked(m, env) else self.deleteSel(m, env);
            }
        }

        self.worldMouse(m, env, dt);
        return .none;
    }

    fn rebuild(self: *Editor, m: *const wf.Map, env: *envmod.Env) void {
        self.rebuildDue = false;
        self.rebuildT = 0;
        self.miniGen +%= 1;
        env.replay(m);
    }

    fn requestRebuild(self: *Editor) void {
        self.rebuildDue = true;
        self.rebuildT = 0;
    }

    fn tickRebuild(self: *Editor, m: *const wf.Map, env: *envmod.Env, dt: f32) void {
        self.tickFolk(dt);
        if (!self.rebuildDue) return;
        self.rebuildT += dt;
        if (self.rebuildT >= REBUILD_QUIET) self.rebuild(m, env);
    }

    fn endGesture(self: *Editor) void {
        self.editing = false;
    }

    pub fn flushRebuild(self: *Editor, m: *const wf.Map, env: *envmod.Env) void {
        if (self.painting) self.endPaint(m, env);
        if (self.rebuildDue) self.rebuild(m, env);
    }

    fn selectZone(self: *Editor, m: *const wf.Map, i: usize) void {
        self.clearRegionSel();
        self.zoneSel = i;
        self.zoneNameBuf = [_]u8{0} ** wf.NAME_CAP;
        self.zoneNameLen = 0;
        if (i >= m.nzones) return;
        const lab = m.zones[i].label();
        self.zoneNameLen = @min(lab.len, wf.NAME_CAP - 1);
        @memcpy(self.zoneNameBuf[0..self.zoneNameLen], lab[0..self.zoneNameLen]);
    }

    fn bankWorld(self: *Editor, m: *wf.Map, half: f32, runway: wf.Runway) void {
        if (self.editing) return;
        const liveHalf = m.half;
        const liveRun = m.runway;
        m.half = half;
        m.runway = runway;
        self.bank(m);
        m.half = liveHalf;
        m.runway = liveRun;
        self.editing = true;
    }

    fn bankGesture(self: *Editor, comptime T: type, m: *wf.Map, target: *T, before: T) void {
        if (self.editing) return;
        const live = target.*;
        target.* = before;
        self.bank(m);
        target.* = live;
        self.editing = true;
    }

    fn worldMouse(self: *Editor, m: *wf.Map, env: *envmod.Env, dt: f32) void {
        const blocked = self.hotFrame or self.menuOpen;
        const ground = self.groundAt();

        self.hoverLive = self.selecting and !blocked;
        self.hover = if (self.hoverLive) self.hoverInLayer(m, env) else .none;

        if (self.wipe.on and !rl.isMouseButtonDown(.left)) self.wipeEnd();
        if (self.painting and !rl.isMouseButtonDown(.left)) self.endPaint(m, env);
        if (self.dragging and !rl.isMouseButtonDown(.left)) {
            if (ground) |g| self.dragTo = g;
            self.dragging = false;
            self.commitDrag(m, env);
        }
        if ((self.marquee or self.moving) and !rl.isMouseButtonDown(.left)) {
            if (ground) |g| self.dragTo = g;
            if (self.marquee) {
                self.marquee = false;
                self.marqueeSelect(m, self.dragFrom, self.dragTo);
            } else {
                self.moving = false;
                self.moveMarked(m, env, self.dragTo.x - self.moveFrom.x, self.dragTo.z - self.moveFrom.z);
            }
        }

        if (rl.isMouseButtonReleased(.right)) {
            const wasClick = self.rmbDown and self.rmbTravel <= DRAG_PX;
            self.rmbDown = false;
            if (wasClick and !blocked) {
                if (self.pickInLayer(m, env)) {
                    self.menuOpen = true;
                    self.menuAt = rl.getMousePosition();
                } else {
                    self.sel = null;
                    self.selUnit = null;
                    self.nMarked = 0;
                }
            }
            return;
        }
        if (self.rmbDown) return;

        if (self.panning) {
            self.dragPan();
            if (rl.isMouseButtonReleased(.left)) self.panning = false;
            return;
        }

        if (self.grabLive) {
            if (rl.isMouseButtonDown(.left)) {
                if (ground) |g| self.dragRegion(m, g);
            }
            if (!rl.isMouseButtonDown(.left)) {
                self.grabLive = false;
                if (self.grabBanked) self.rebuild(m, env);
            }
            return;
        }

        if (self.layer == .ground and !self.selecting) {
            if (rl.isMouseButtonDown(.left) and (self.painting or !blocked)) {
                if (ground) |g| {
                    if (!self.painting) {
                        self.bank(m);
                        self.painting = true;
                    }
                    switch (@as(GroundBrush, @enumFromInt(self.brushIdx()))) {
                        .raise, .lower, .smooth, .flat => |b| {
                            const mode: wf.Sculpt = switch (b) {
                                .raise => .raise,
                                .lower => .lower,
                                .smooth => .smooth,
                                else => .flatten,
                            };
                            const amt: f32 = switch (mode) {
                                .raise, .lower => self.sculptRate * dt,
                                else => mathx.minF(self.sculptRate * dt * SCULPT_EVEN, 0.9),
                            };
                            var span: [4]usize = wf.EMPTY_SPAN;
                            if (m.sculpt(g.x, g.z, self.radius, mode, amt, &span)) {
                                env.sculptHeight(m, span);
                                self.heightStroke = true;
                            }
                        },
                        .water, .oil, .fungal, .lava => |b| if (m.paintWater(g.x, g.z, self.radius, true, WATER_EDGE, liquidOf(b))) {
                            env.uploadWater(m);
                            self.wetStroke = true;
                        },
                        .erase => {
                            if (m.paintSoil(g.x, g.z, self.radius, .none, 1, null)) env.uploadSoil(m);
                            if (m.paintWater(g.x, g.z, self.radius, false, null, .water)) {
                                env.uploadWater(m);
                                self.wetStroke = true;
                            }
                        },
                        else => |b| {
                            const id = soilOf(b) orelse unreachable;
                            if (m.paintSoil(g.x, g.z, self.radius, id, self.soilOpacity, self.brushEdge)) env.uploadSoil(m);
                        },
                    }
                }
            } else if (self.painting and rl.isMouseButtonReleased(.left)) {
                self.endPaint(m, env);
            }
            return;
        }

        const shift = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);

        if (self.marquee or self.moving) {
            if (ground) |g| self.dragTo = g;
            return;
        }

        if (self.erasing() and !self.selecting and !shift) {
            if (rl.isMouseButtonDown(.left) and (self.wipe.on or !blocked)) {
                if (ground) |g| self.wipeStep(m, env, g);
            }
            return;
        }

        if (rl.isMouseButtonPressed(.left)) {
            if (blocked) return;
            if (shift and self.layer != .ground) {
                if (ground) |g| {
                    self.marquee = true;
                    self.dragFrom = g;
                    self.dragTo = g;
                }
                return;
            }
            if (self.selecting) {
                if (self.nMarked > 0 and self.overMarked(m, env)) {
                    if (ground) |g| {
                        self.moving = true;
                        self.moveFrom = g;
                        self.dragTo = g;
                    }
                    return;
                }
                if (self.pickInLayer(m, env)) {
                    if (self.grab != null) {
                        if (ground) |g| {
                            self.grabLive = true;
                            self.grabBanked = false;
                            self.grabFrom = g;
                        }
                    }
                    return;
                }
                if (ground) |g| {
                    self.panning = true;
                    self.panGrab = g;
                }
                return;
            }
            if (self.layer == .locations and self.brushIdx() == @intFromEnum(LocationBrush.arena)) {
                if (ground) |g| self.arenaCorner(m, g);
                return;
            }
            if (self.routing) {
                if (ground) |g| self.layLeg(m, g);
                return;
            }
            switch (self.layer) {
                .units => {
                    if (ground) |g| self.addUnit(m, g);
                },
                .locations, .decor, .props, .interact => {
                    if (ground) |g| {
                        self.dragging = true;
                        self.dragFrom = g;
                        self.dragTo = g;
                    }
                },
                .ground => @panic("editor: ground layer reached the op placer"),
            }
            return;
        }
        if (self.dragging) {
            if (ground) |g| self.dragTo = g;
        }
    }

    fn endPaint(self: *Editor, m: *const wf.Map, env: *envmod.Env) void {
        self.painting = false;
        if (self.wetStroke or self.heightStroke) {
            self.wetStroke = false;
            self.heightStroke = false;
            self.rebuild(m, env);
        }
    }

    fn cursorRay(self: *const Editor) rl.Ray {
        const ray = rl.getScreenToWorldRay(rl.getMousePosition(), self.cam);
        return .{ .position = ray.position, .direction = mathx.normV(ray.direction) };
    }

    fn camView(self: *const Editor) envmod.View {
        const aspect = @as(f32, @floatFromInt(rl.getScreenWidth())) / @as(f32, @floatFromInt(rl.getScreenHeight()));
        return envmod.View.fromCamera(self.cam, aspect);
    }

    const OpFilter = struct {
        ed: *const Editor,
        m: *const wf.Map,
        fn inLayer(f: OpFilter, op: u16) bool {
            const i: usize = op;
            return i < f.m.nops and layerOf(&f.m.ops[i]) == f.ed.layer;
        }
    };

    fn filter(self: *const Editor, m: *const wf.Map) OpFilter {
        return .{ .ed = self, .m = m };
    }

    fn overMarked(self: *Editor, m: *wf.Map, env: *envmod.Env) bool {
        if (self.layer == .units) {
            const g = self.groundAt() orelse return false;
            for (self.marked[0..self.nMarked]) |i| {
                if (i >= m.nfoes) continue;
                const f = m.foes[i];
                if (mathx.dist2XZ(v3(f.x, 0, f.z), g) < FOE_PICK_R * FOE_PICK_R) return true;
            }
            return false;
        }
        return switch (self.underCursor(m, env)) {
            .prop => |pi| self.isMarked(env.props[pi].op),
            .foe, .npc, .none => false,
        };
    }

    fn underCursor(self: *Editor, m: *wf.Map, env: *envmod.Env) Hover {
        if (self.hoverLive) return self.hover;
        return self.hoverInLayer(m, env);
    }

    fn hoverInLayer(self: *Editor, m: *wf.Map, env: *envmod.Env) Hover {
        if (self.layer.opLayer()) {
            const ray = self.cursorRay();
            const view = self.camView();
            if (env.pickIf(&view, ray.position, ray.direction, self.filter(m), OpFilter.inLayer)) |pi| return .{ .prop = pi };
            return .none;
        }
        if (self.layer == .units) {
            const g = self.groundAt() orelse return .none;
            var near = mathx.Nearest.within(FOE_PICK_R);
            for (m.foes[0..m.nfoes], 0..) |f, i| near.offer(i, v3(f.x, 0, f.z), g);
            for (m.npcs[0..m.nnpcs], 0..) |nn, i| near.offer(wf.MAX_FOES + i, v3(nn.x, 0, nn.z), g);
            const w = near.best orelse return .none;
            return if (w >= wf.MAX_FOES) .{ .npc = w - wf.MAX_FOES } else .{ .foe = w };
        }
        return .none;
    }

    fn pickInLayer(self: *Editor, m: *wf.Map, env: *envmod.Env) bool {
        switch (self.underCursor(m, env)) {
            .prop => |pi| {
                const o = env.props[pi].op;
                self.sel = o;
                self.selUnit = null;
                const op = m.ops[o];
                self.sayFmt("#{d} {s} {s}", .{ o, @tagName(op.op), @tagName(op.kind) });
                return true;
            },
            .foe => |i| {
                self.selUnit = .{ .foe = i };
                self.sel = null;
                self.sayFmt("#{d} {s}", .{ i, wf.foeName(m.foes[i].kind) });
                return true;
            },
            .npc => |i| {
                self.selUnit = .{ .npc = i };
                self.sel = null;
                self.sayFmt("#{d} {s}", .{ i, wf.npcName(m.npcs[i].kind) });
                return true;
            },
            .none => {},
        }
        if (self.layer == .locations) return self.pickRegion(m);
        return false;
    }

    fn pickRegion(self: *Editor, m: *wf.Map) bool {
        const g = self.groundAt() orelse return false;
        if (self.arenaSel) |ai| {
            if (ai < m.narenas) {
                if (nearestCorner(&m.arenas[ai], g)) |vi| {
                    self.grab = .{ .arena = vi };
                    self.sayFmt("corner {d} of {s}", .{ vi, m.arenas[ai].label() });
                    return true;
                }
            }
        }
        if (self.zoneSel) |zi| {
            if (zi < m.nzones and !m.isFallbackZone(zi)) {
                const z = &m.zones[zi];
                if (rectHandle(z.x, z.z, z.x1, z.z1, g)) |ci| {
                    self.grab = .{ .zone = ci };
                    self.sayFmt("corner {d} of {s}", .{ ci, z.label() });
                    return true;
                }
            }
        }
        if (self.locSel) |li| {
            if (li < m.nlocations) {
                const l = &m.locations[li];
                if (rectHandle(l.x, l.z, l.x1, l.z1, g)) |ci| {
                    self.grab = .{ .loc = ci };
                    self.sayFmt("corner {d} of {s}", .{ ci, l.label() });
                    return true;
                }
            }
        }
        if (self.clearSel) |ci| {
            if (ci < m.nclearings) {
                const c = m.clearings[ci];
                const d = mathx.distXZ(mathx.ground(c.x, c.z), g);
                // The rim is the outer HALF, not a band: at `HANDLE_R` 2.5 a band reaches the middle of any circle under 5 m across.
                if (@abs(d - c.r) <= HANDLE_R and d >= c.r * 0.5) {
                    self.grab = .{ .clearing = true };
                    self.sayFmt("clearing r {d:.0} - drag to resize", .{c.r});
                    return true;
                }
            }
        }
        for (m.arenas[0..m.narenas], 0..) |*a, i| {
            if (!a.contains(g.x, g.z)) continue;
            self.selectArena(m, i);
            self.grab = .{ .arena = null };
            self.sayFmt("{s} - {d} corners, drag to move", .{ a.label(), a.verts() });
            return true;
        }
        for (m.clearings[0..m.nclearings], 0..) |c, i| {
            if (mathx.dist2XZ(mathx.ground(c.x, c.z), g) > c.r * c.r) continue;
            self.selectClearing(i);
            self.grab = .{ .clearing = false };
            self.sayFmt("clearing {d} - r {d:.0}, drag to move", .{ i, c.r });
            return true;
        }
        for (m.locations[0..m.nlocations], 0..) |*l, i| {
            if (!l.contains(g.x, g.z)) continue;
            self.selectLocation(m, i);
            self.grab = .{ .loc = null };
            self.sayFmt("{s} - drag to move", .{l.label()});
            return true;
        }
        for (m.zones[0..m.nzones], 0..) |*z, i| {
            if (m.isFallbackZone(i) or !z.contains(g.x, g.z)) continue;
            self.selectZone(m, i);
            self.grab = .{ .zone = null };
            self.sayFmt("{s} - drag to move", .{z.label()});
            return true;
        }
        return false;
    }

    fn rectHandle(x: f32, z: f32, x1: f32, z1: f32, at: rl.Vector3) ?u8 {
        var best: ?u8 = null;
        var bd = HANDLE_R * HANDLE_R;
        for (0..4) |i| {
            const c = rectCorner(x, z, x1, z1, @intCast(i));
            const d = mathx.dist2XZ(at, c);
            if (d > bd) continue;
            bd = d;
            best = @intCast(i);
        }
        return best;
    }

    fn commitDrag(self: *Editor, m: *wf.Map, env: *envmod.Env) void {
        const a = self.dragFrom;
        const b = self.dragTo;
        const span = mathx.distXZ(a, b);

        if (self.layer == .locations) {
            switch (@as(LocationBrush, @enumFromInt(self.brushIdx()))) {
                .zone => {
                    if (m.nzones >= wf.MAX_ZONES) {
                        self.say("zone cap reached");
                        return;
                    }
                    self.bank(m);
                    const box = normRect(a, b);
                    var z = wf.Zone{
                        .x = box.x0,
                        .z = box.z0,
                        .x1 = box.x1,
                        .z1 = box.z1,
                        .density = NEW_ZONE_DENSITY,
                    };
                    z.setName("new");
                    if (m.zoneAt((z.x + z.x1) * 0.5, (z.z + z.z1) * 0.5)) |src| {
                        z.mix = src.mix;
                        z.nmix = src.nmix;
                    }
                    std.mem.copyBackwards(wf.Zone, m.zones[1 .. m.nzones + 1], m.zones[0..m.nzones]);
                    m.zones[0] = z;
                    m.nzones += 1;
                    self.zoneSel = null;
                    self.say("+zone");
                },
                .location => {
                    if (m.nlocations >= wf.MAX_LOCATIONS) {
                        self.say("location cap reached");
                        return;
                    }
                    self.bank(m);
                    const box = normRect(a, b);
                    var l = wf.Location{ .x = box.x0, .z = box.z0, .x1 = box.x1, .z1 = box.z1 };
                    var nbuf: [wf.NAME_CAP]u8 = undefined;
                    l.setName(std.fmt.bufPrint(&nbuf, "loc{d}", .{m.nlocations + 1}) catch "loc");
                    std.mem.copyBackwards(wf.Location, m.locations[1 .. m.nlocations + 1], m.locations[0..m.nlocations]);
                    m.locations[0] = l;
                    m.nlocations += 1;
                    self.locSel = 0;
                    self.sayFmt("+{s}", .{m.locations[0].label()});
                },
                .clearing => {
                    if (m.nclearings >= wf.MAX_CLEARINGS) {
                        self.say("clearing cap reached");
                        return;
                    }
                    self.bank(m);
                    const r = @max(span, MIN_CLEARING_R);
                    m.clearings[m.nclearings] = .{ .x = a.x, .z = a.z, .r = r };
                    m.nclearings += 1;
                    self.sayFmt("+clearing r {d:.0}", .{r});
                },
                .arena => return,
                .erase => return,
            }
            self.rebuild(m, env);
            return;
        }

        var o = wf.defaults(.at);
        o.kind = self.kindForLayer();
        o.rise = props.info(o.kind).stack * 4.0;
        switch (self.layer) {
            .ground, .units => return,
            .locations => @panic("editor: locations layer reached the op placer"),
            .decor => switch (@as(DecorBrush, @enumFromInt(self.brushIdx()))) {
                .single => {
                    o.x = a.x;
                    o.z = a.z;
                    o.yaw = 0;
                    o.scale = 1;
                },
                .scatter => {
                    o = self.rectBelt(m, a, b);
                },
                .patch => {
                    o = self.discOp(m, a, span);
                },
                .erase => return,
            },
            .interact => switch (@as(InteractBrush, @enumFromInt(self.brushIdx()))) {
                .stamp => {
                    o.x = a.x;
                    o.z = a.z;
                    o.yaw = 0;
                    o.scale = 1;
                },
                .erase => return,
            },
            .props => switch (@as(PropBrush, @enumFromInt(self.brushIdx()))) {
                .stamp => {
                    o.x = a.x;
                    o.z = a.z;
                    o.yaw = 0;
                    o.scale = 1;
                },
                .row => {
                    o = wf.defaults(.line);
                    o.kind = self.propKind;
                    o.x = a.x;
                    o.z = a.z;
                    o.x1 = b.x;
                    o.z1 = b.z;
                    o.r0 = @max(props.info(self.propKind).bound * 1.2, 2.0);
                    o.seed = self.freshSeed(m);
                },
                .ring => {
                    o = wf.defaults(.ring);
                    o.kind = self.propKind;
                    o.x = a.x;
                    o.z = a.z;
                    o.r0 = @max(span, MIN_BRUSH_R);
                    o.n = 9;
                    o.skip = 4; // the gap, so a fresh ring never reads as a fence
                    o.seed = self.freshSeed(m);
                },
                .cluster => {
                    o = self.discOp(m, a, span);
                },
                .ivy => {
                    o = wf.defaults(.ivy);
                    o.kind = .ivy;
                    const box = normRect(a, b);
                    o.x = box.x0;
                    o.z = box.z0;
                    o.x1 = box.x1;
                    o.z1 = box.z1;
                    o.sLo = 0.85;
                    o.sHi = 1.5;
                    o.seed = self.freshSeed(m);
                },
                .erase => return,
            },
        }

        if (m.nops >= wf.MAX_OPS) {
            self.say(FULL_MSG);
            return;
        }
        self.bank(m);
        const idx = m.add(o) catch {
            self.say(FULL_MSG);
            return;
        };
        const at = idx;
        self.sel = at;
        self.selUnit = null;
        self.rebuild(m, env);
        self.sayFmt("+{s} {s} #{d}", .{ @tagName(o.op), @tagName(o.kind), at });
    }

    const AREA_PER_INSTANCE: f32 = 9.0;
    const FRESH_N_LO: f32 = 4;
    const FRESH_N_HI: f32 = 900;
    const MIN_BRUSH_R: f32 = 1.0;

    fn countForArea(area: f32) i32 {
        return @intFromFloat(mathx.clampF(area / AREA_PER_INSTANCE, FRESH_N_LO, FRESH_N_HI));
    }

    fn rectBelt(self: *Editor, m: *const wf.Map, a: rl.Vector3, b: rl.Vector3) wf.Op {
        var o = wf.defaults(.belt);
        o.kind = self.kindForLayer();
        const box = normRect(a, b);
        o.x = box.x0;
        o.z = box.z0;
        o.x1 = box.x1;
        o.z1 = box.z1;
        o.n = countForArea((o.x1 - o.x) * (o.z1 - o.z));
        o.seed = self.freshSeed(m);
        return o;
    }

    fn discOp(self: *Editor, m: *const wf.Map, centre: rl.Vector3, span: f32) wf.Op {
        var o = wf.defaults(.disc);
        o.kind = self.kindForLayer();
        o.x = centre.x;
        o.z = centre.z;
        o.r0 = 0;
        o.r1 = @max(span, MIN_BRUSH_R);
        o.n = countForArea(std.math.pi * o.r1 * o.r1);
        o.bias = 0.5;
        o.seed = self.freshSeed(m);
        return o;
    }

    fn freshSeed(self: *Editor, m: *const wf.Map) u64 {
        _ = self;
        var s: u64 = 1000;
        for (m.slice()) |*o| s = @max(s, o.seed);
        return s + 1;
    }

    fn nearestCorner(a: *const wf.Arena, at: rl.Vector3) ?u8 {
        var best: ?u8 = null;
        var bd = ARENA_CLOSE_R * ARENA_CLOSE_R;
        for (0..a.verts()) |i| {
            const d = mathx.dist2XZ(at, mathx.ground(a.vx[i], a.vz[i]));
            if (d > bd) continue;
            bd = d;
            best = @intCast(i);
        }
        return best;
    }

    fn clearRegionSel(self: *Editor) void {
        self.zoneSel = null;
        self.locSel = null;
        self.clearSel = null;
        self.arenaSel = null;
        self.grab = null;
        self.grabLive = false;
    }

    fn selectArena(self: *Editor, m: *const wf.Map, i: usize) void {
        self.clearRegionSel();
        self.arenaSel = i;
        self.arenaNameBuf = [_]u8{0} ** wf.NAME_CAP;
        self.arenaNameLen = 0;
        if (i >= m.narenas) return;
        const lab = m.arenas[i].label();
        self.arenaNameLen = @min(lab.len, wf.NAME_CAP - 1);
        @memcpy(self.arenaNameBuf[0..self.arenaNameLen], lab[0..self.arenaNameLen]);
    }

    fn dragRegion(self: *Editor, m: *wf.Map, to: rl.Vector3) void {
        const g = self.grab orelse return;
        if (mathx.distXZ(to, self.grabFrom) < 1e-4) return;
        if (!self.grabBanked) {
            self.bank(m);
            self.grabBanked = true;
        }
        const dx = to.x - self.grabFrom.x;
        const dz = to.z - self.grabFrom.z;
        switch (g) {
            .arena => |vi| {
                const ai = self.arenaSel orelse return;
                if (ai >= m.narenas) return;
                const a = &m.arenas[ai];
                if (vi) |v| {
                    if (v >= a.verts()) return;
                    a.vx[v] = to.x;
                    a.vz[v] = to.z;
                } else for (0..a.verts()) |i| {
                    a.vx[i] += dx;
                    a.vz[i] += dz;
                }
            },
            .zone => |ci| {
                const zi = self.zoneSel orelse return;
                if (zi >= m.nzones or m.isFallbackZone(zi)) return;
                const z = &m.zones[zi];
                if (dragRect(&z.x, &z.z, &z.x1, &z.z1, ci, to, dx, dz)) |now| self.grab = .{ .zone = now };
            },
            .loc => |ci| {
                const li = self.locSel orelse return;
                if (li >= m.nlocations) return;
                const l = &m.locations[li];
                if (dragRect(&l.x, &l.z, &l.x1, &l.z1, ci, to, dx, dz)) |now| self.grab = .{ .loc = now };
            },
            .clearing => |rim| {
                const ci = self.clearSel orelse return;
                if (ci >= m.nclearings) return;
                const c = &m.clearings[ci];
                if (rim) {
                    c.r = @max(mathx.distXZ(mathx.ground(c.x, c.z), to), MIN_CLEARING_R);
                } else {
                    c.x += dx;
                    c.z += dz;
                }
            },
        }
        self.grabFrom = to;
        self.dirty = true;
        self.requestRebuild();
    }

    fn dragRect(x: *f32, z: *f32, x1: *f32, z1: *f32, ci: ?u8, to: rl.Vector3, dx: f32, dz: f32) ?u8 {
        if (ci) |c| {
            switch (c & 3) {
                0 => {
                    x.* = to.x;
                    z.* = to.z;
                },
                1 => {
                    x1.* = to.x;
                    z.* = to.z;
                },
                2 => {
                    x1.* = to.x;
                    z1.* = to.z;
                },
                else => {
                    x.* = to.x;
                    z1.* = to.z;
                },
            }
            const nx = @min(x.*, x1.*);
            const nz = @min(z.*, z1.*);
            const nx1 = @max(x.*, x1.*);
            const nz1 = @max(z.*, z1.*);
            x.* = nx;
            z.* = nz;
            x1.* = nx1;
            z1.* = nz1;
            const ex: u8 = if (to.x > nx1 - 1e-4) 1 else 0;
            const ez: u8 = if (to.z > nz1 - 1e-4) 1 else 0;
            return switch ((ez << 1) | ex) {
                0 => 0,
                1 => 1,
                3 => 2,
                else => 3,
            };
        }
        x.* += dx;
        z.* += dz;
        x1.* += dx;
        z1.* += dz;
        return null;
    }

    fn layLeg(self: *Editor, m: *wf.Map, at: rl.Vector3) void {
        const su = self.selUnit orelse {
            self.routing = false;
            return;
        };
        const fi = switch (su) {
            .foe => |i| i,
            .npc => {
                self.routing = false;
                return;
            },
        };
        if (fi >= m.nfoes) {
            self.routing = false;
            return;
        }
        const f = &m.foes[fi];
        if (f.nwp >= wf.MAX_WP) {
            self.sayFmt("a route takes {d} legs", .{wf.MAX_WP});
            self.routing = false;
            return;
        }
        f.wp[f.nwp] = .{ .x = at.x, .z = at.z };
        f.nwp += 1;
        self.dirty = true;
        self.sayFmt("leg {d} of {d}", .{ f.nwp, wf.MAX_WP });
    }

    fn selectTrig(self: *Editor, m: *const wf.Map, i: usize) void {
        self.trigSel = i;
        self.trigNameBuf = [_]u8{0} ** wf.ID_CAP;
        self.trigNameLen = 0;
        if (i >= m.ntrigs) return;
        const lab = m.trigs[i].label();
        self.trigNameLen = @min(lab.len, wf.ID_CAP - 1);
        @memcpy(self.trigNameBuf[0..self.trigNameLen], lab[0..self.trigNameLen]);
    }

    fn selectClearing(self: *Editor, i: usize) void {
        self.clearRegionSel();
        self.clearSel = i;
    }

    fn selectLocation(self: *Editor, m: *const wf.Map, i: usize) void {
        self.clearRegionSel();
        self.locSel = i;
        self.locNameBuf = [_]u8{0} ** wf.NAME_CAP;
        self.locNameLen = 0;
        if (i >= m.nlocations) return;
        const lab = m.locations[i].label();
        self.locNameLen = @min(lab.len, wf.NAME_CAP - 1);
        @memcpy(self.locNameBuf[0..self.locNameLen], lab[0..self.locNameLen]);
    }

    fn dropCorner(self: *Editor, m: *wf.Map) void {
        const ai = self.arenaSel orelse return;
        if (ai >= m.narenas) return;
        const a = &m.arenas[ai];
        const vi = self.grabbedVert() orelse return;
        if (a.verts() <= 3) {
            self.say("a room needs three corners");
            return;
        }
        if (vi >= a.verts()) return;
        self.bank(m);
        var i: usize = vi;
        while (i + 1 < a.verts()) : (i += 1) {
            a.vx[i] = a.vx[i + 1];
            a.vz[i] = a.vz[i + 1];
        }
        a.n -= 1;
        self.grab = null;
        self.sayFmt("{d} corners", .{a.verts()});
    }

    fn splitLongestWall(self: *Editor, m: *wf.Map) void {
        const ai = self.arenaSel orelse return;
        if (ai >= m.narenas) return;
        const a = &m.arenas[ai];
        const n = a.verts();
        if (n >= wf.MAX_ARENA_VERTS) {
            self.sayFmt("a room takes {d} corners", .{wf.MAX_ARENA_VERTS});
            return;
        }
        var at: usize = 0;
        var best: f32 = -1;
        for (0..n) |i| {
            const j = (i + 1) % n;
            const d = mathx.distXZ(mathx.ground(a.vx[i], a.vz[i]), mathx.ground(a.vx[j], a.vz[j]));
            if (d <= best) continue;
            best = d;
            at = i;
        }
        self.bank(m);
        const j = (at + 1) % n;
        const mx = (a.vx[at] + a.vx[j]) * 0.5;
        const mz = (a.vz[at] + a.vz[j]) * 0.5;
        var i: usize = n;
        while (i > at + 1) : (i -= 1) {
            a.vx[i] = a.vx[i - 1];
            a.vz[i] = a.vz[i - 1];
        }
        a.vx[at + 1] = mx;
        a.vz[at + 1] = mz;
        a.n += 1;
        self.grab = .{ .arena = @intCast(at + 1) };
        self.grabLive = false;
        self.sayFmt("+corner on the {d:.0} m wall", .{best});
    }

    fn sealFromGate(self: *Editor, m: *wf.Map) bool {
        const ai = self.arenaSel orelse return false;
        if (ai >= m.narenas) return false;
        const a = &m.arenas[ai];
        const o = gateOnWall(m, a) orelse return false;
        self.bank(m);
        a.boss = o.boss;
        a.nboss = o.nboss;
        self.dirty = true;
        return true;
    }

    const HANDLE_R: f32 = ARENA_CLOSE_R;

    /// How near the first corner closes the run, in metres — forgiving, because the camera is usually wide.
    const ARENA_CLOSE_R: f32 = 2.5;

    fn arenaCorner(self: *Editor, m: *wf.Map, at: rl.Vector3) void {
        if (self.nPend >= 3 and mathx.distXZ(at, mathx.ground(self.pendX[0], self.pendZ[0])) <= ARENA_CLOSE_R) {
            self.closeArena(m);
            return;
        }
        if (self.nPend >= wf.MAX_ARENA_VERTS) {
            self.sayFmt("a room takes {d} corners", .{wf.MAX_ARENA_VERTS});
            return;
        }
        self.pendX[self.nPend] = at.x;
        self.pendZ[self.nPend] = at.z;
        self.nPend += 1;
        self.sayFmt("corner {d} - Enter closes, Esc drops", .{self.nPend});
    }

    fn closeArena(self: *Editor, m: *wf.Map) void {
        if (self.nPend < 3) {
            self.say("a room needs three corners");
            return;
        }
        if (m.narenas >= wf.MAX_ARENAS) {
            self.say("arena cap reached");
            self.nPend = 0;
            return;
        }
        self.bank(m);
        var a = wf.Arena{ .n = self.nPend, .nboss = 0 };
        a.vx = self.pendX;
        a.vz = self.pendZ;
        var nbuf: [wf.NAME_CAP]u8 = undefined;
        a.setName(std.fmt.bufPrint(&nbuf, "arena{d}", .{m.narenas + 1}) catch "arena");
        if (gateOnWall(m, &a)) |o| {
            a.boss = o.boss;
            a.nboss = o.nboss;
        }
        std.mem.copyBackwards(wf.Arena, m.arenas[1 .. m.narenas + 1], m.arenas[0..m.narenas]);
        m.arenas[0] = a;
        m.narenas += 1;
        self.arenaSel = 0;
        if (a.nboss == 0) {
            self.sayFmt("+{s} ({d} corners) - NO GATE ON ITS WALL, so it holds nothing", .{ m.arenas[0].label(), a.n });
        } else {
            self.sayFmt("+{s} ({d} corners) sealed on {s}", .{ m.arenas[0].label(), a.n, @tagName(a.boss[0]) });
        }
        self.nPend = 0;
    }

    fn addUnit(self: *Editor, m: *wf.Map, at: rl.Vector3) void {
        if (self.erasing()) return;
        const bi = self.brushIdx();
        if (bi >= NFOE_KIND) {
            if (m.nnpcs >= wf.MAX_NPCS) {
                self.say(FOLK_FULL_MSG);
                return;
            }
            const kind: wf.NpcKind = @enumFromInt(bi - NFOE_KIND);
            self.bank(m);
            const seed = @as(f32, @floatFromInt((m.nnpcs * 53) % 100)) / 100.0;
            m.npcs[m.nnpcs] = .{ .kind = kind, .x = at.x, .z = at.z, .yaw = 0, .scale = 1, .seed = seed };
            self.selUnit = .{ .npc = m.nnpcs };
            m.nnpcs += 1;
            self.touchFolk();
            self.sayFmt("+{s} ({d:.0}, {d:.0})", .{ wf.npcName(kind), at.x, at.z });
            return;
        }
        if (m.nfoes >= wf.MAX_FOES) {
            self.say(FOES_FULL_MSG);
            return;
        }
        const kind: wf.FoeKind = @enumFromInt(bi);
        self.bank(m);
        const seed = @as(f32, @floatFromInt((m.nfoes * 37) % 100)) / 100.0;
        m.foes[m.nfoes] = .{ .kind = kind, .x = at.x, .z = at.z, .yaw = 0, .scale = 1, .seed = seed };
        self.selUnit = .{ .foe = m.nfoes };
        m.nfoes += 1;
        self.sayFmt("+{s} ({d:.0}, {d:.0})", .{ wf.foeName(kind), at.x, at.z });
    }

    fn wipeStep(self: *Editor, m: *wf.Map, env: *envmod.Env, g: rl.Vector3) void {
        const first = !self.wipe.on;
        if (first) {
            self.wipe = .{ .on = true, .at = g };
        } else {
            if (self.wipe.t < 1.0 / ERASE_HZ) return;
            if (mathx.dist2XZ(g, self.wipe.at) < ERASE_STEP * ERASE_STEP) return;
        }
        self.wipe.at = g;
        self.wipe.t = 0;
        if (self.eraseAt(m, env, g)) {
            self.wipe.n += 1;
        } else if (first) {
            self.say(eraseMiss(self.layer));
        }
    }

    fn wipeEnd(self: *Editor) void {
        if (self.wipe.n > 1) self.sayFmt("erased {d}", .{self.wipe.n});
        if (self.wipe.n > 0) self.miniGen +%= 1;
        self.wipe.on = false;
    }

    fn bankStroke(self: *Editor, m: *wf.Map) void {
        if (self.wipe.n == 0) self.bank(m);
    }

    fn eraseAt(self: *Editor, m: *wf.Map, env: *envmod.Env, g: rl.Vector3) bool {
        switch (self.layer) {
            .ground => {},
            .units => {
                var i: usize = m.nfoes;
                while (i > 0) : (i -= 1) {
                    const f = m.foes[i - 1];
                    if (mathx.dist2XZ(v3(f.x, 0, f.z), g) > self.radius * self.radius) continue;
                    self.bankStroke(m);
                    std.mem.copyForwards(wf.Foe, m.foes[i - 1 .. m.nfoes - 1], m.foes[i..m.nfoes]);
                    m.nfoes -= 1;
                    self.dropSelection();
                    self.sayFmt("-foe ({d:.0}, {d:.0})", .{ f.x, f.z });
                    return true;
                }
                var j: usize = m.nnpcs;
                while (j > 0) : (j -= 1) {
                    const nn = m.npcs[j - 1];
                    if (mathx.dist2XZ(v3(nn.x, 0, nn.z), g) > self.radius * self.radius) continue;
                    self.bankStroke(m);
                    const gone = self.removeFolk(m, j - 1);
                    if (gone.conds > 0) {
                        self.sayFmt("-npc; {d} `near` condition(s) now never", .{gone.conds});
                    } else if (gone.freed) {
                        self.sayFmt("-npc and its conversation ({d:.0}, {d:.0})", .{ nn.x, nn.z });
                    } else {
                        self.sayFmt("-npc ({d:.0}, {d:.0})", .{ nn.x, nn.z });
                    }
                    return true;
                }
            },
            .locations => {
                var ai: usize = 0;
                while (ai < m.narenas) : (ai += 1) {
                    if (!m.arenas[ai].contains(g.x, g.z)) continue;
                    self.bankStroke(m);
                    std.mem.copyForwards(wf.Arena, m.arenas[ai .. m.narenas - 1], m.arenas[ai + 1 .. m.narenas]);
                    m.narenas -= 1;
                    self.arenaSel = null;
                    self.rebuild(m, env);
                    self.say("-arena");
                    return true;
                }
                for (m.clearings[0..m.nclearings], 0..) |c, i| {
                    if (mathx.dist2XZ(v3(c.x, 0, c.z), g) > c.r * c.r) continue;
                    self.bankStroke(m);
                    std.mem.copyForwards(wf.Clearing, m.clearings[i .. m.nclearings - 1], m.clearings[i + 1 .. m.nclearings]);
                    m.nclearings -= 1;
                    self.rebuild(m, env);
                    self.say("-clearing");
                    return true;
                }
                var li: usize = 0;
                while (li < m.nlocations) : (li += 1) {
                    if (!m.locations[li].contains(g.x, g.z)) continue;
                    self.bankStroke(m);
                    std.mem.copyForwards(wf.Location, m.locations[li .. m.nlocations - 1], m.locations[li + 1 .. m.nlocations]);
                    m.nlocations -= 1;
                    self.locSel = null;
                    self.rebuild(m, env);
                    self.say("-location");
                    return true;
                }
                var i: usize = 0;
                while (i < m.nzones) : (i += 1) {
                    if (m.isFallbackZone(i)) continue;
                    if (!m.zones[i].contains(g.x, g.z)) continue;
                    self.bankStroke(m);
                    std.mem.copyForwards(wf.Zone, m.zones[i .. m.nzones - 1], m.zones[i + 1 .. m.nzones]);
                    m.nzones -= 1;
                    self.zoneSel = null;
                    self.rebuild(m, env);
                    self.say("-zone");
                    return true;
                }
            },
            .decor, .props, .interact => {
                const was = self.sel;
                if (!self.pickInLayer(m, env)) return false;
                const s = self.sel orelse return false;
                if (s >= m.nops) {
                    self.sel = was;
                    return false;
                }
                self.bankStroke(m);
                self.removeOp(m, env, s);
                return true;
            },
        }
        return false;
    }

    fn rerollSel(self: *Editor, m: *wf.Map, env: *envmod.Env) void {
        const s = self.sel orelse return;
        if (s >= m.nops or m.ops[s].op == .at) return;
        self.bank(m);
        m.ops[s].seed = self.freshSeed(m);
        self.rebuild(m, env);
        self.sayFmt("re-rolled #{d} - seed {d}", .{ s, m.ops[s].seed });
    }

    fn explodeSel(self: *Editor, m: *wf.Map, env: *envmod.Env) void {
        const s = self.sel orelse return;
        if (s >= m.nops or m.ops[s].op == .at) return;
        if (self.rebuildDue) self.rebuild(m, env);
        self.bank(m);
        const n = env.explodeOp(m, s) catch {
            self.say(FULL_MSG);
            return;
        };
        self.dropSelection();
        self.rebuild(m, env);
        self.sayFmt("broke apart into {d}", .{n});
    }

    const FolkGone = struct { conds: usize, freed: bool };

    fn removeFolk(self: *Editor, m: *wf.Map, i: usize) FolkGone {
        const doomed = m.npcs[i].dlg;
        const broke = wf.removeNpc(m, i);
        const freed = doomed != wf.NO_DIALOG and wf.removeDialog(m, doomed);
        self.touchFolk();
        self.dropSelection();
        return .{ .conds = broke.conds, .freed = freed };
    }

    fn deleteSel(self: *Editor, m: *wf.Map, env: *envmod.Env) void {
        if (self.layer == .units) {
            switch (self.selUnit orelse return) {
                .foe => |f| {
                    if (f >= m.nfoes) return;
                    self.bank(m);
                    std.mem.copyForwards(wf.Foe, m.foes[f .. m.nfoes - 1], m.foes[f + 1 .. m.nfoes]);
                    m.nfoes -= 1;
                },
                .npc => |i| {
                    if (i >= m.nnpcs) return;
                    self.bank(m);
                    const gone = self.removeFolk(m, i);
                    if (gone.conds > 0) {
                        self.sayFmt("-unit; {d} `near` condition(s) now never", .{gone.conds});
                    } else if (gone.freed) {
                        self.say("-unit and its conversation");
                    } else {
                        self.say("-unit");
                    }
                    return;
                },
            }
            self.dropSelection();
            self.say("-unit");
            return;
        }
        const s = self.sel orelse return;
        if (s >= m.nops) return;
        self.bank(m);
        self.removeOp(m, env, s);
    }

    fn removeOp(self: *Editor, m: *wf.Map, env: *envmod.Env, s: usize) void {
        m.remove(s);
        self.dropSelection();
        self.rebuild(m, env);
        self.sayFmt("deleted op #{d}", .{s});
    }

    fn duplicateSel(self: *Editor, m: *wf.Map, env: *envmod.Env) void {
        const s = self.sel orelse return;
        if (s >= m.nops) return;
        if (m.nops >= wf.MAX_OPS) {
            self.say(FULL_MSG);
            return;
        }
        self.bank(m);
        var o = m.ops[s];
        o.seed = self.freshSeed(m);
        translateOp(&o, DUPE_OFFSET, 0);
        const idx = m.add(o) catch return;
        self.sel = idx;
        self.rebuild(m, env);
        self.sayFmt("duplicated #{d} -> #{d}", .{ s, idx });
    }


    fn isMarked(self: *const Editor, i: usize) bool {
        for (self.marked[0..self.nMarked]) |v| {
            if (v == i) return true;
        }
        return false;
    }

    fn mark(self: *Editor, i: usize) void {
        if (self.nMarked >= MAX_MARKED or self.isMarked(i)) return;
        self.marked[self.nMarked] = i;
        self.nMarked += 1;
    }

    fn marqueeSelect(self: *Editor, m: *const wf.Map, a: rl.Vector3, b: rl.Vector3) void {
        const box = normRect(a, b);
        self.nMarked = 0;
        if (self.layer == .units) {
            for (m.foes[0..m.nfoes], 0..) |f, i| {
                if (box.holds(f.x, f.z)) self.mark(i);
            }
            self.selUnit = if (self.nMarked > 0) Unit{ .foe = self.marked[0] } else null;
            self.sel = null;
        } else if (self.layer.opLayer()) {
            for (m.ops[0..m.nops], 0..) |*o, i| {
                if (layerOf(o) != self.layer) continue;
                const p = opAnchor(o);
                if (box.holds(p.x, p.z)) self.mark(i);
            }
            self.sel = if (self.nMarked > 0) self.marked[0] else null;
            self.selUnit = null;
        }
        self.sayFmt("{d} selected", .{self.nMarked});
    }

    fn markedCentre(self: *const Editor, m: *const wf.Map) rl.Vector3 {
        if (self.nMarked == 0) return mathx.zero3;
        var sx: f32 = 0;
        var sz: f32 = 0;
        var n: usize = 0;
        for (self.marked[0..self.nMarked]) |i| {
            if (self.layer == .units) {
                if (i >= m.nfoes) continue;
                sx += m.foes[i].x;
                sz += m.foes[i].z;
            } else {
                if (i >= m.nops) continue;
                const p = opAnchor(&m.ops[i]);
                sx += p.x;
                sz += p.z;
            }
            n += 1;
        }
        if (n == 0) return mathx.zero3;
        const nf: f32 = @floatFromInt(n);
        return v3(sx / nf, 0, sz / nf);
    }

    fn moveMarked(self: *Editor, m: *wf.Map, env: *envmod.Env, dx: f32, dz: f32) void {
        if (self.nMarked == 0 or (dx == 0 and dz == 0)) return;
        self.bank(m);
        for (self.marked[0..self.nMarked]) |i| {
            if (self.layer == .units) {
                if (i >= m.nfoes) continue;
                m.foes[i].translate(dx, dz);
            } else {
                if (i >= m.nops) continue;
                translateOp(&m.ops[i], dx, dz);
            }
        }
        self.rebuild(m, env);
        self.sayFmt("moved {d} by ({d:.1}, {d:.1})", .{ self.nMarked, dx, dz });
    }


    fn copyMarked(self: *Editor, m: *wf.Map, env: *envmod.Env, cut: bool) void {
        if (self.nMarked == 0) {
            self.say("nothing selected");
            return;
        }
        const c = self.markedCentre(m);
        nClipOps = 0;
        nClipFoes = 0;
        for (self.marked[0..self.nMarked]) |i| {
            if (self.layer == .units) {
                if (i >= m.nfoes or nClipFoes >= MAX_MARKED) continue;
                var f = m.foes[i];
                f.translate(-c.x, -c.z);
                clipFoes[nClipFoes] = f;
                nClipFoes += 1;
            } else {
                if (i >= m.nops or nClipOps >= MAX_MARKED) continue;
                var o = m.ops[i];
                translateOp(&o, -c.x, -c.z);
                clipOps[nClipOps] = o;
                nClipOps += 1;
            }
        }
        self.sayFmt("{s} {d}", .{ if (cut) "cut" else "copied", nClipOps + nClipFoes });
        if (cut) self.deleteMarked(m, env);
    }

    fn paste(self: *Editor, m: *wf.Map, env: *envmod.Env) void {
        const at = self.groundAt() orelse return;
        if (nClipOps == 0 and nClipFoes == 0) {
            self.say("clipboard is empty");
            return;
        }
        const onUnits = self.layer == .units;
        const nOps: usize = if (onUnits) 0 else nClipOps;
        const nFoes: usize = if (onUnits) nClipFoes else 0;
        if (nOps == 0 and nFoes == 0) {
            if (onUnits) self.say("clipboard holds ops - paste them on an object layer") else self.say("clipboard holds spawns - paste them on Units");
            return;
        }
        if (nOps > 0 and m.nops >= wf.MAX_OPS) {
            self.say(FULL_MSG);
            return;
        }
        if (nFoes > 0 and m.nfoes >= wf.MAX_FOES) {
            self.say(FOES_FULL_MSG);
            return;
        }
        self.bank(m);
        self.nMarked = 0;
        var seed = self.freshSeed(m);
        var landed: usize = 0;
        for (clipOps[0..nOps]) |src| {
            var o = src;
            translateOp(&o, at.x, at.z);
            if (o.op != .at) {
                o.seed = seed;
                seed += 1;
            }
            const idx = m.add(o) catch {
                self.say(FULL_MSG);
                break;
            };
            self.mark(idx);
            landed += 1;
        }
        for (clipFoes[0..nFoes]) |src| {
            if (m.nfoes >= wf.MAX_FOES) {
                self.say(FOES_FULL_MSG);
                break;
            }
            var f = src;
            f.translate(at.x, at.z);
            m.foes[m.nfoes] = f;
            self.mark(m.nfoes);
            m.nfoes += 1;
            landed += 1;
        }
        self.rebuild(m, env);
        const want = nOps + nFoes;
        if (landed == want) {
            self.sayFmt("pasted {d}", .{landed});
        } else if (landed > 0) {
            self.sayFmt("pasted {d} of {d} - cap reached", .{ landed, want });
        }
    }

    fn deleteMarked(self: *Editor, m: *wf.Map, env: *envmod.Env) void {
        if (self.nMarked == 0) return;
        self.bank(m);
        var idx: [MAX_MARKED]usize = undefined;
        @memcpy(idx[0..self.nMarked], self.marked[0..self.nMarked]);
        std.mem.sort(usize, idx[0..self.nMarked], {}, std.sort.desc(usize));
        var removed: usize = 0;
        for (idx[0..self.nMarked]) |i| {
            if (self.layer == .units) {
                if (i >= m.nfoes) continue;
                std.mem.copyForwards(wf.Foe, m.foes[i .. m.nfoes - 1], m.foes[i + 1 .. m.nfoes]);
                m.nfoes -= 1;
            } else {
                if (i >= m.nops) continue;
                m.remove(i);
            }
            removed += 1;
        }
        self.dropSelection();
        self.rebuild(m, env);
        self.sayFmt("deleted {d}", .{removed});
    }



    fn request(self: *Editor, what: Pending) void {
        self.menuOpen = false;
        if (!self.dirty) {
            self.commitPending(what);
            return;
        }
        self.pending = what;
        self.modal = .confirm;
    }

    fn commitPending(self: *Editor, what: Pending) void {
        self.pending = if (what == .leave) .leave else .none;
        switch (what) {
            .none => {},
            .new => {
                self.nameLen = 0;
                self.modal = .new_map;
            },
            .open => {
                listing.scan();
                self.fileSel = 0;
                self.fileScroll = 0;
                self.modal = .open_map;
            },
            .leave => self.modal = .none,
        }
    }

    fn adopt(self: *Editor, m: *const wf.Map, env: *envmod.Env, isDirty: bool) void {
        self.dropSelection();
        self.dirty = isDirty;
        undoReset();
        self.touchFolk();
        self.rebuild(m, env);
    }

    fn doOpen(self: *Editor, m: *wf.Map, env: *envmod.Env, i: usize) void {
        if (i >= listing.n) return;
        var buf: [wf.PATH_CAP]u8 = undefined;
        const p = std.fmt.bufPrint(&buf, "{s}/{s}", .{ wf.DIR, listing.name(i) }) catch return;
        var line: usize = 0;
        wf.load(p, m, &line) catch |e| {
            self.sayFmt("OPEN FAILED: {s} (line {d})", .{ @errorName(e), line });
            return;
        };
        self.setPath(p);
        self.adopt(m, env, false);
        self.sayFmt("opened {s} - {d} ops", .{ p, m.nops });
    }

    fn doNew(self: *Editor, m: *wf.Map, env: *envmod.Env) void {
        const name = if (self.nameLen > 0) self.nameBuf[0..self.nameLen] else "untitled";
        m.blank(name);
        var buf: [wf.PATH_CAP]u8 = undefined;
        self.setPath(wf.pathFor(&buf, name));
        self.adopt(m, env, true);
        self.sayFmt("new map \"{s}\" - save it to keep it", .{name});
    }

    fn doSaveAs(self: *Editor, m: *wf.Map) void {
        const name = if (self.nameLen > 0) self.nameBuf[0..self.nameLen] else m.label();
        var buf: [wf.PATH_CAP]u8 = undefined;
        const p = wf.pathFor(&buf, name);
        wf.save(p, m) catch |e| {
            self.sayFmt("SAVE FAILED: {s}", .{@errorName(e)});
            return;
        };
        m.setName(name);
        self.setPath(p);
        self.dirty = false;
        self.sayFmt("saved {s}", .{p});
    }

    fn saveNow(self: *Editor, m: *const wf.Map) bool {
        wf.save(self.curPath(), m) catch |e| {
            self.sayFmt("SAVE FAILED: {s}", .{@errorName(e)});
            return false;
        };
        self.dirty = false;
        self.sayFmt("saved {s} - {d} ops", .{ self.curPath(), m.nops });
        return true;
    }


    pub fn visible(self: *const Editor, l: Layer) bool {
        return self.layer == l or self.shown[@intFromEnum(l)];
    }

    var barFitFor: i32 = -1;
    var barFit = false;

    fn barWide(sw: i32) bool {
        if (barFitFor == sw) return barFit;
        const step = BarRow.GAP;
        const sq = BAR_H - 10;
        var w: i32 = 8;
        inline for (@typeInfo(Layer).@"enum".fields) |f| {
            const l: Layer = @enumFromInt(f.value);
            w += ui.layerButtonW(l.label(), hud.MONO) + step;
        }
        w += 14 + 7 * (sq + step) + 10 + 10; // the seven verbs and the gaps that group them
        inline for (.{ "Objects", "World", "Script", "Sounds", "Options" }) |lab| {
            w += hud.monoW(lab, hud.MONO) + BarRow.PAD + step;
        }
        barFitFor = sw;
        barFit = w + DIRTY_W <= sw;
        return barFit;
    }

    const DIRTY_W: i32 = 20;

    fn drawRectHandles(self: *const Editor, x: f32, z: f32, x1: f32, z1: f32, y: f32, comptime which: std.meta.Tag(Grab)) void {
        for (0..4) |i| {
            const c = rectCorner(x, z, x1, z1, @intCast(i));
            const held = if (self.grab) |g| blk: {
                if (g != which) break :blk false;
                const v: ?u8 = switch (g) {
                    .zone => |c2| c2,
                    .loc => |c2| c2,
                    else => null,
                };
                break :blk v != null and v.? == @as(u8, @intCast(i));
            } else false;
            handlePost(c.x, c.z, y, held);
        }
    }

    pub fn draw3D(self: *Editor, m: *const wf.Map, env: *const envmod.Env) void {
        gizmoWorld = env;
        const y: f32 = 0.05;
        rl.drawCubeWires(v3(0, envmod.groundY() + y, 0), m.half * 2, 0.02, m.half * 2, ui.alpha(ui.TRIM, 90));
        outline(m.runway.x, m.runway.z, m.runway.x1, m.runway.z1, y, ui.alpha(ui.HOT, 70));

        const locA: u8 = if (self.layer == .locations) 200 else 45;
        if (self.visible(.locations)) {
            for (m.zones[0..m.nzones]) |*z| {
                if (z.x1 - z.x > m.half * 3) continue;
                outline(z.x, z.z, z.x1, z.z1, y, ui.alpha(ui.TRIM, locA));
            }
            for (m.clearings[0..m.nclearings]) |c| ringXZ(c.x, c.z, c.r, y, ui.alpha(ui.HOT, locA));
        }
        if (self.visible(.locations)) {
            for (m.locations[0..m.nlocations], 0..) |*l, i| {
                const on = self.locSel == i;
                const col = if (l.hasWeather()) ui.LIVE else ui.TRIM;
                outline(l.x, l.z, l.x1, l.z1, y + 0.02, ui.alpha(if (on) ui.HOT else col, if (self.layer == .locations) 220 else 55));
                if (on) self.drawRectHandles(l.x, l.z, l.x1, l.z1, y, .loc);
            }
            if (self.zoneSel) |zi| {
                if (zi < m.nzones and !m.isFallbackZone(zi)) {
                    const z = &m.zones[zi];
                    outline(z.x, z.z, z.x1, z.z1, y + 0.02, ui.HOT);
                    self.drawRectHandles(z.x, z.z, z.x1, z.z1, y, .zone);
                }
            }
            if (self.clearSel) |ci| {
                if (ci < m.nclearings) {
                    const c = m.clearings[ci];
                    ringXZ(c.x, c.z, c.r, y + 0.02, ui.HOT);
                    const rimGrab = if (self.grab) |g| g == .clearing and g.clearing else false;
                    handlePost(c.x + c.r, c.z, y, rimGrab);
                    handlePost(c.x, c.z, y, false);
                }
            }
        }

        if (self.visible(.locations)) {
            for (m.arenas[0..m.narenas], 0..) |*a, i| {
                const on = self.arenaSel == i;
                const col = if (on) ui.HOT else if (a.seal().len > 0) ui.LIVE else ui.TRIM;
                const wall = ui.alpha(col, if (self.layer == .locations) 235 else 60);
                const n = a.verts();
                for (0..n) |vi| {
                    const vj = (vi + 1) % n;
                    arenaWall(a.vx[vi], a.vz[vi], a.vx[vj], a.vz[vj], y + 0.03, wall);
                    const held = on and self.grabbedVert() != null and self.grabbedVert().? == vi;
                    const ph: f32 = if (held) ARENA_PIN_H * 1.6 else ARENA_PIN_H;
                    const pw: f32 = if (held) ARENA_PIN_W * 1.7 else ARENA_PIN_W;
                    rl.drawCubeWires(liftAt(a.vx[vi], a.vz[vi], y + ph * 0.5), pw, ph, pw, if (held) ui.LIVE else wall);
                }
            }
        }
        if (self.nPend > 0) {
            for (0..self.nPend) |vi| {
                if (vi + 1 < self.nPend) arenaWall(self.pendX[vi], self.pendZ[vi], self.pendX[vi + 1], self.pendZ[vi + 1], y + 0.04, ui.HOT);
                rl.drawCubeWires(liftAt(self.pendX[vi], self.pendZ[vi], y + ARENA_PIN_H * 0.5), ARENA_PIN_W, ARENA_PIN_H, ARENA_PIN_W, ui.HOT);
            }
            if (self.nPend >= 3) groundLine(self.pendX[self.nPend - 1], self.pendZ[self.nPend - 1], self.pendX[0], self.pendZ[0], y + 0.04, ui.alpha(ui.HOT, 90));
        }

        {
            const sp = m.start.at();
            const dir = mathx.headingDir(m.start.facing());
            handlePost(sp.x, sp.z, y, false);
            ringXZ(sp.x, sp.z, 1.4, y + 0.02, ui.LIVE);
            groundLine(sp.x, sp.z, sp.x + dir.x * 4.0, sp.z + dir.z * 4.0, y + 0.05, ui.LIVE);
        }

        const unitA: u8 = if (self.layer == .units) 235 else 70;
        if (self.visible(.units)) {
            for (m.foes[0..m.nfoes], 0..) |f, i| {
                const sel = self.layer == .units and self.selUnit != null and self.selUnit.? == .foe and self.selUnit.?.foe == i;
                const ordered = f.ai != .hold;
                const col = if (sel) ui.HOT else if (ordered) ui.alpha(ui.LIVE, unitA) else ui.alpha(foeSwatch(f.kind), unitA);
                const at = liftAt(f.x, f.z, y + FOE_BOX_H * 0.5);
                rl.drawCubeWires(at, FOE_BOX_W, FOE_BOX_H, FOE_BOX_W, col);
                if (ordered and self.layer == .units and f.ai == .roam) {
                    ringXZ(f.x, f.z, foemod.ROAM_R, y + 0.02, ui.alpha(ui.LIVE, if (sel) 190 else 70));
                }
                const route = f.route();
                if (!sel or route.len == 0) continue;
                var prev = mathx.ground(f.x, f.z);
                for (route) |q| {
                    const p = mathx.ground(q.x, q.z);
                    groundLine(prev.x, prev.z, p.x, p.z, y + 0.05, ui.LIVE);
                    handlePost(p.x, p.z, y, false);
                    prev = p;
                }
                if (route.len > 1) groundLine(prev.x, prev.z, f.x, f.z, y + 0.05, ui.alpha(ui.LIVE, 110));
            }
        }

        self.selOwned = 0;
        self.selMarked = 0;
        if (self.sel) |s| {
            if (s < m.nops and self.layer.opLayer()) {
                drawOpGizmo(&m.ops[s], y);
                self.selOwned = env.ownedBy(@intCast(s));
                const view = self.camView();
                const Mark = struct {
                    ed: *Editor,
                    e: *const envmod.Env,
                    op: u16,
                    fn at(c: *@This(), pi: u32) void {
                        const pr = &c.e.props[pi];
                        if (pr.op != c.op or c.ed.selMarked >= MAX_MARKERS) return;
                        c.ed.selMarked += 1;
                        const nfo = props.info(pr.kind);
                        const h = @max(envmod.runOf(pr, nfo), 0.4);
                        const sw = envmod.leanOffsetAt(pr.lean, pr.leanDir, h * 0.5);
                        rl.drawCubeWires(v3(pr.pos.x + sw.x, pr.pos.y + h * 0.5, pr.pos.z + sw.z), 0.3, h, 0.3, ui.HOT);
                    }
                };
                var mk = Mark{ .ed = self, .e = env, .op = @intCast(s) };
                env.eachInView(&view, &mk, Mark.at);
            }
        }

        for (self.marked[0..self.nMarked]) |i| {
            if (self.layer == .units) {
                if (i >= m.nfoes) continue;
                const f = m.foes[i];
                rl.drawCubeWires(liftAt(f.x, f.z, y + MARK_BOX_H * 0.5), MARK_BOX_W, MARK_BOX_H, MARK_BOX_W, ui.TRIM);
            } else {
                if (i >= m.nops) continue;
                const p = opAnchor(&m.ops[i]);
                ringSeg(p.x, p.z, MARK_RING_R, y, ui.TRIM, MARK_RING_SEG);
            }
        }
        switch (self.hover) {
            .none => {},
            .prop => |pi| {
                if (pi < env.nprops) {
                    const pr = env.props[pi];
                    const nfo = props.info(pr.kind);
                    const h = @max(envmod.runOf(&pr, nfo), 0.4);
                    const w = @max(nfo.bound * pr.scale, 0.3) * 1.6;
                    const sw = envmod.leanOffsetAt(pr.lean, pr.leanDir, h * 0.5);
                    rl.drawCubeWires(v3(pr.pos.x + sw.x, pr.pos.y + h * 0.5, pr.pos.z + sw.z), w, h, w, ui.HOT);
                }
            },
            .foe => |i| {
                if (i < m.nfoes) {
                    const f = m.foes[i];
                    rl.drawCubeWires(liftAt(f.x, f.z, y + MARK_BOX_H * 0.5), MARK_BOX_W * 1.2, MARK_BOX_H * 1.1, MARK_BOX_W * 1.2, ui.HOT);
                }
            },
            .npc => |i| {
                if (i < m.nnpcs) {
                    const nn = m.npcs[i];
                    rl.drawCubeWires(liftAt(nn.x, nn.z, y + MARK_BOX_H * 0.5), MARK_BOX_W * 1.2, MARK_BOX_H * 1.1, MARK_BOX_W * 1.2, ui.HOT);
                }
            },
        }

        if (self.marquee) {
            outlineOf(normRect(self.dragFrom, self.dragTo), y, ui.HOT);
        }
        if (self.moving) {
            const dx = self.dragTo.x - self.moveFrom.x;
            const dz = self.dragTo.z - self.moveFrom.z;
            groundLine(self.moveFrom.x, self.moveFrom.z, self.dragTo.x, self.dragTo.z, y, ui.HOT);
            for (self.marked[0..self.nMarked]) |i| {
                if (self.layer == .units) {
                    if (i >= m.nfoes) continue;
                    ringSeg(m.foes[i].x + dx, m.foes[i].z + dz, GIZMO_R, y, ui.HOT, MARK_RING_SEG);
                } else {
                    if (i >= m.nops) continue;
                    const p = opAnchor(&m.ops[i]);
                    ringSeg(p.x + dx, p.z + dz, MARK_RING_R, y, ui.HOT, MARK_RING_SEG);
                }
            }
        }

        if (self.dragging) {
            const a = self.dragFrom;
            const b = self.dragTo;
            const rad = mathx.distXZ(a, b);
            const box = normRect(a, b);
            if (self.layer == .locations) {
                switch (@as(LocationBrush, @enumFromInt(self.brushIdx()))) {
                    .zone, .location => outlineOf(box, y, ui.HOT),
                    .clearing => ringXZ(a.x, a.z, rad, y, ui.HOT),
                    .arena, .erase => {},
                }
            } else if (self.layer == .decor) {
                switch (@as(DecorBrush, @enumFromInt(self.brushIdx()))) {
                    .scatter => outlineOf(box, y, ui.HOT),
                    .patch => ringXZ(a.x, a.z, rad, y, ui.HOT),
                    .single, .erase => {},
                }
            } else if (self.layer == .props) {
                switch (@as(PropBrush, @enumFromInt(self.brushIdx()))) {
                    .row => groundLine(a.x, a.z, b.x, b.z, y, ui.HOT),
                    .ring, .cluster => ringXZ(a.x, a.z, rad, y, ui.HOT),
                    .ivy => outlineOf(box, y, ui.HOT),
                    .stamp, .erase => {},
                }
            }
        }

        if (self.groundAt()) |g| {
            const showRadius = self.layer == .ground or (self.erasing() and self.layer == .units);
            if (showRadius) {
                ringXZ(g.x, g.z, self.radius, y, ui.HOT);
                ringXZ(g.x, g.z, self.radius * 0.5, y, ui.alpha(ui.HOT, 90));
            } else {
                ringXZ(g.x, g.z, CURSOR_R, y, ui.alpha(ui.HOT, 200));
            }
        }
    }
};

fn drawOpGizmo(o: *const wf.Op, y: f32) void {
    switch (o.op) {
        .at => {
            ringXZ(o.x, o.z, GIZMO_R, y, ui.HOT);
            const d = mathx.headingDir(mathx.radians(o.yaw));
            groundLine(o.x, o.z, o.x + d.x * GIZMO_SPOKE, o.z + d.z * GIZMO_SPOKE, y, ui.HOT);
        },
        .belt, .ivy => outline(o.x, o.z, o.x1, o.z1, y, ui.HOT),
        .disc => {
            ringXZ(o.x, o.z, o.r1, y, ui.HOT);
            if (o.r0 > 0.05) ringXZ(o.x, o.z, o.r0, y, ui.alpha(ui.HOT, 130));
        },
        .ring => ringXZ(o.x, o.z, o.r0, y, ui.HOT),
        .line => groundLine(o.x, o.z, o.x1, o.z1, y, ui.HOT),
    }
}

const FOE_BOX_W: f32 = 0.9;
const FOE_BOX_H: f32 = 1.8;
const MARK_BOX_W: f32 = 1.4;
const MARK_BOX_H: f32 = 2.0;
const MARK_RING_R: f32 = 1.8;
const MARK_RING_SEG: i32 = 12;
const GIZMO_R: f32 = 1.2;
const GIZMO_SPOKE: f32 = GIZMO_R * 1.9;
const CURSOR_R: f32 = 0.9;

fn foeSwatch(k: wf.FoeKind) rl.Color {
    return switch (k) {
        .toad => ui.col(120, 200, 110, 255),
        .archer => ui.col(210, 205, 180, 255),
        .ogre => ui.col(220, 140, 90, 255),
        .berserker => ui.col(206, 150, 96, 255),
        .priest => ui.col(228, 190, 104, 255),
        .slinger => ui.col(152, 116, 78, 255),
        .brood_mother => ui.col(146, 186, 84, 255),
        .broodling => ui.col(104, 132, 68, 255),
        .brood_sac => ui.col(190, 208, 130, 255),
        .shieldman => ui.col(176, 178, 190, 255),
        .greatsword => ui.col(214, 216, 232, 255),
        .shade => ui.col(138, 116, 208, 255),
        .mourner => ui.col(174, 162, 194, 255),
        .slumber_bloom => ui.col(142, 152, 212, 255),
        .cinder_wake => ui.col(226, 116, 52, 255),
        .rotgorger => ui.col(148, 132, 86, 255),
        .birchwight => ui.col(206, 202, 190, 255),
        .salt_husk => ui.col(226, 228, 220, 255),
        .fish_spearman => ui.col(96, 132, 112, 255),
        .fish_netter => ui.col(120, 156, 138, 255),
        .fish_shaman => ui.col(158, 186, 150, 255),
        .owlbear => ui.col(150, 148, 142, 255),
        .blinkbat => ui.col(170, 108, 176, 255),
        .fungal_swordsman => ui.col(196, 176, 132, 255),
        .fungal_magus => ui.col(112, 140, 96, 255),
        .leechfly => ui.col(196, 66, 58, 255),
        .rooted => ui.col(140, 96, 52, 255),
        .shroom => ui.col(214, 130, 118, 255),
        .bone_knight => ui.col(228, 132, 62, 255),
        .delver => ui.col(150, 118, 78, 255),
        .necromancer => ui.col(126, 196, 224, 255),
        .fungal_deer => ui.col(226, 138, 196, 255),
        .mushroom_mage => ui.col(238, 152, 66, 255),
        .spore_golem => ui.col(214, 96, 132, 255),
        .fen_lurker => ui.col(78, 200, 186, 255),
        .bone_skitterer => ui.col(232, 228, 206, 255),
        .ancient_priest => ui.col(180, 148, 72, 255),
        .tolling_hollow => ui.col(150, 132, 78, 255),
    };
}

var gizmoWorld: ?*const envmod.Env = null;

fn liftAt(x: f32, z: f32, lift: f32) rl.Vector3 {
    if (gizmoWorld) |w| return v3(x, w.groundAt(x, z) + lift, z);
    return v3(x, envmod.groundY() + lift, z);
}

fn handlePost(x: f32, z: f32, y: f32, held: bool) void {
    const h: f32 = if (held) ARENA_PIN_H * 1.6 else ARENA_PIN_H;
    const w: f32 = if (held) ARENA_PIN_W * 1.7 else ARENA_PIN_W;
    rl.drawCubeWires(liftAt(x, z, y + h * 0.5), w, h, w, if (held) ui.LIVE else ui.HOT);
}

fn arenaWall(x0: f32, z0: f32, x1: f32, z1: f32, lift: f32, col: rl.Color) void {
    const SEG = GROUND_SEG;
    const top = ui.alpha(col, @intFromFloat(@as(f32, @floatFromInt(col.a)) * 0.55));
    var i: i32 = 0;
    while (i <= SEG) : (i += 1) {
        const t0 = @as(f32, @floatFromInt(i)) / SEG;
        const x = mathx.lerpF(x0, x1, t0);
        const z = mathx.lerpF(z0, z1, t0);
        rl.drawLine3D(liftAt(x, z, lift), liftAt(x, z, lift + ARENA_WALL_H), if (@mod(i, 3) == 0) col else top);
        if (i == SEG) break;
        const t1 = @as(f32, @floatFromInt(i + 1)) / SEG;
        const x1s = mathx.lerpF(x0, x1, t1);
        const z1s = mathx.lerpF(z0, z1, t1);
        rl.drawLine3D(liftAt(x, z, lift), liftAt(x1s, z1s, lift), col);
        rl.drawLine3D(liftAt(x, z, lift + ARENA_WALL_H), liftAt(x1s, z1s, lift + ARENA_WALL_H), top);
    }
}

const GROUND_SEG: i32 = 12;

fn groundLine(x0: f32, z0: f32, x1: f32, z1: f32, lift: f32, col: rl.Color) void {
    const SEG = GROUND_SEG;
    var i: i32 = 0;
    while (i < SEG) : (i += 1) {
        const t0 = @as(f32, @floatFromInt(i)) / SEG;
        const t1 = @as(f32, @floatFromInt(i + 1)) / SEG;
        rl.drawLine3D(
            liftAt(mathx.lerpF(x0, x1, t0), mathx.lerpF(z0, z1, t0), lift),
            liftAt(mathx.lerpF(x0, x1, t1), mathx.lerpF(z0, z1, t1), lift),
            col,
        );
    }
}

/// The post at each corner of a room, and the height its wall is drawn to — metres.
const ARENA_PIN_W: f32 = 0.9;
const ARENA_PIN_H: f32 = 3.2;
const ARENA_WALL_H: f32 = 4.5;

fn outlineOf(r: Rect, y: f32, col: rl.Color) void {
    outline(r.x0, r.z0, r.x1, r.z1, y, col);
}

fn outline(x0: f32, z0: f32, x1: f32, z1: f32, y: f32, col: rl.Color) void {
    groundLine(x0, z0, x1, z0, y, col);
    groundLine(x1, z0, x1, z1, y, col);
    groundLine(x1, z1, x0, z1, y, col);
    groundLine(x0, z1, x0, z0, y, col);
}

fn ringXZ(cx: f32, cz: f32, r: f32, y: f32, col: rl.Color) void {
    ringSeg(cx, cz, r, y, col, 48);
}

fn ringSeg(cx: f32, cz: f32, r: f32, y: f32, col: rl.Color, seg: i32) void {
    if (r < 0.02) return;
    var i: i32 = 0;
    while (i < seg) : (i += 1) {
        const a0 = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(seg));
        const a1 = std.math.tau * @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(seg));
        rl.drawLine3D(
            liftAt(cx + mathx.cosf(a0) * r, cz + mathx.sinf(a0) * r, y),
            liftAt(cx + mathx.cosf(a1) * r, cz + mathx.sinf(a1) * r, y),
            col,
        );
    }
}


const BAR_H: i32 = 34;
const SIDE_W: i32 = 268;
const PROP_W: i32 = 300;
const STATUS_H: i32 = 28;
const MINI_W: i32 = 190;
const CHROME_PAD: i32 = 10;
const GUTTER: i32 = 30;
const COORD_LIM: f32 = 400;
const COUNT_MAX: i32 = 4000;
const RING_N_MAX: i32 = 64;
const LEAN_LIM: f32 = 40;

fn edgeTip(e: wf.Edge, wet: bool) [:0]const u8 {
    if (wet) return switch (e) {
        .blend => "A margin you cannot find the edge of. Metres of ground that is neither",
        .natural => "What a lake does on its own. A slow wander either side of the line",
        .frayed => "Quicker, shallower. Reeds and shallows picking at the bank",
        .jagged => "A torn rocky shore, deep and fast. Bays and bites, and it does not soak",
        .straight => "The line exactly where you painted it, and dry to the edge. A built bank",
        .tiled => "The line taken to the grid. A dock, a harbour wall",
        .scallop => "Regular bays. A beach rather than a bank",
        .speckle => "A bog: the fringe breaks into separate pools. The ONE shape allowed to disconnect water",
    };
    return switch (e) {
        .blend => "No line. Dissolves over metres",
        .natural => "Soft, wandering boundary",
        .frayed => "Light, quick wander",
        .jagged => "Deep, quick, torn",
        .straight => "Cut where you painted it. No wander",
        .tiled => "Snapped to the grid, so every edge runs on an axis",
        .scallop => "A repeating wave instead of noise",
        .speckle => "Breaks into detached flecks before it ends",
    };
}

const ROW_H: i32 = ui.ROW_H;
const SLIDER_DROP: i32 = 20;

pub fn drawOverlay(ed: *Editor, m: *wf.Map, env: *envmod.Env, scene: *gfx.Scene, day: *daynight.Clock, t: f32) void {
    ed.world = env;
    ed.resolveCursor();
    const sw = rl.getScreenWidth();
    const sh = rl.getScreenHeight();
    var ctx = ui.Ctx.begin(t);

    const overlaid = ed.modal != .none or ed.menuOpen;
    if (overlaid) ctx.setLive(false);

    drawTopBar(ed, m, env, &ctx, sw);
    drawSide(ed, &ctx, sh);
    drawProperties(ed, m, env, &ctx, sw, sh);
    drawMinimap(ed, m, env, &ctx, sw, sh);
    drawStatus(ed, m, env, &ctx, sw, sh);
    if (overlaid) ctx.setLive(true);
    if (ed.modal != .none) {
        drawModal(ed, m, env, scene, day, &ctx);
    } else if (ed.menuOpen) {
        drawContextMenu(ed, m, env, &ctx);
    }
    ui.endDropdowns();
    ui.drawTip(&ctx);

    // THE EDGE, NOT THE STATE: closing on every un-overlaid frame wiped `openId` before the next frame could
    // draw the list, so the properties panel's own dropdown (the NPC's `says`) opened for zero frames.
    if (ed.wasOverlaid and !overlaid) ui.closeDropdown();
    ed.wasOverlaid = overlaid;
    ed.hotFrame = ctx.anyHot or ui.dropdownOpen();
}

const BarRow = struct {
    ctx: *ui.Ctx,
    x: i32,

    const GAP: i32 = 3;
    const PAD: i32 = 18;

    fn button(r: *BarRow, label: [:0]const u8, active: bool, tip: [:0]const u8) bool {
        const w = hud.monoW(label, hud.MONO) + PAD;
        defer r.x += w + GAP;
        return ui.button(r.ctx, ui.rect(r.x, 5, w, BAR_H - 10), label, hud.MONO, active, tip);
    }

    fn layer(r: *BarRow, ic: ui.Icon, label: [:0]const u8, active: bool, shown: bool, tip: [:0]const u8) ui.LayerHit {
        const w = ui.layerButtonW(label, hud.MONO);
        defer r.x += w + GAP;
        const rect = ui.rect(r.x, 5, w, BAR_H - 10);
        ui.tipFor(r.ctx, rect, tip);
        return ui.layerButton(r.ctx, rect, ic, label, hud.MONO, active, shown);
    }

    fn verb(r: *BarRow, ic: ui.Icon, tip: [:0]const u8) bool {
        const w = BAR_H - 10;
        defer r.x += w + GAP;
        return ui.iconOnly(r.ctx, ui.rect(r.x, 5, w, w), ic, false, tip);
    }

    fn gap(r: *BarRow, px: i32) void {
        r.x += px;
    }
};

fn drawTopBar(ed: *Editor, m: *wf.Map, env: *envmod.Env, ctx: *ui.Ctx, sw: i32) void {
    ui.panel(ctx, ui.rect(0, 0, sw, BAR_H), null);
    var row = BarRow{ .ctx = ctx, .x = 8 };
    const named = Editor.barWide(sw);
    inline for (@typeInfo(Layer).@"enum".fields) |f| {
        const l: Layer = @enumFromInt(f.value);
        switch (row.layer(layerIcon(l), if (named) l.label() else "", ed.layer == l, ed.shown[f.value], layerTips[f.value])) {
            .select => ed.setLayer(l),
            .toggle => ed.shown[f.value] = !ed.shown[f.value],
            .none => {},
        }
    }
    row.gap(14);
    if (row.verb(.new, "New - start an empty map (Ctrl+N)")) ed.request(.new);
    if (row.verb(.open, "Open - a map from worlds/ (Ctrl+O)")) ed.request(.open);
    if (row.verb(.save, "Save - write the map to disk (Ctrl+S)")) _ = ed.saveNow(m);
    if (row.verb(.saveas, "Save As - write it under a new name (Ctrl+Shift+S)")) {
        ed.nameLen = 0;
        ed.modal = .save_as;
    }
    if (row.verb(.reload, "Reload - throw away every unsaved change and re-read the file")) {
        var line: usize = 0;
        if (wf.load(ed.curPath(), m, &line)) |_| {
            ed.adopt(m, env, false);
            ed.say("reloaded from disk");
        } else |e| {
            ed.sayFmt("RELOAD FAILED: {s} (line {d})", .{ @errorName(e), line });
        }
    }
    row.gap(10);
    if (row.verb(.undo, "Undo (Ctrl+Z)")) {
        if (ed.undo(m)) ed.rebuild(m, env);
    }
    if (row.verb(.redo, "Redo (Ctrl+Y)")) {
        if (ed.redo(m)) ed.rebuild(m, env);
    }
    row.gap(10);
    if (row.button("Objects", ed.modal == .objects, "Object viewer - every model in a gallery; click one to turn it over")) {
        ed.menuOpen = false;
        ed.modal = .objects;
    }
    if (row.button("World", ed.modal == .world, "The map itself - its size and the runway")) {
        ed.menuOpen = false;
        ed.modal = .world;
    }
    if (row.button("Script", ed.modal == .script, "Triggers - the conditions and actions the map runs on. SC1's, and the one layer the editor could never author")) {
        ed.menuOpen = false;
        ed.modal = .script;
        if (ed.trigSel == null and m.ntrigs > 0) ed.selectTrig(m, 0);
    }
    if (row.button("Stats", ed.modal == .stats, "The stats bench - every table-able number in the game, and a revert on each one")) {
        ed.menuOpen = false;
        ed.modal = .stats;
    }
    if (row.button("Sounds", ed.modal == .jukebox, "Jukebox - play any sound in the bank on demand")) {
        ed.menuOpen = false;
        ed.modal = .jukebox;
    }
    if (row.button("Options", ed.modal == .options, "Editor Options - what the viewport shows and how the brush lands. None of it touches the map")) {
        ed.menuOpen = false;
        ed.modal = .options;
    }

    if (ed.dirty) hud.mono("*", row.x + 8, 8, hud.MONO, ui.HOT);
}

fn drawRoomsPanel(ed: *Editor, ctx: *ui.Ctx, m: *wf.Map, x: i32, y0: i32, w: i32) i32 {
    var y = y0;
    var hb: [40]u8 = undefined;
    hud.mono(std.fmt.bufPrintZ(&hb, "ROOMS ({d})", .{m.narenas}) catch "ROOMS", x, y, hud.MONO, ui.TITLE);
    y += ROW_H + 4;
    if (m.narenas == 0) {
        hud.mono("none - pick the Arena", x, y, hud.MONO, ui.alpha(ui.LABEL, 160));
        y += hud.monoLineH(hud.MONO);
        hud.mono("brush and click corners", x, y, hud.MONO, ui.alpha(ui.LABEL, 160));
        return y + ROW_H + 6;
    }
    for (m.arenas[0..m.narenas], 0..) |*a, i| {
        var lb: [56]u8 = undefined;
        const on = ed.arenaSel == i;
        const lab = std.fmt.bufPrintZ(&lb, "{s} ({d})", .{ a.label(), a.verts() }) catch "?";
        if (ui.button(ctx, ui.rect(x, y, w, 22), lab, hud.MONO, on, "Select this room. Then drag its corners, or drag inside it to move the whole thing")) {
            if (on) ed.arenaSel = null else ed.selectArena(m, i);
            ed.grab = null;
        }
        y += ROW_H;
    }
    y += 4;
    const ai = ed.arenaSel orelse return y + 2;
    if (ai >= m.narenas) return y + 2;
    const a = &m.arenas[ai];

    hud.mono("name", x, y, hud.MONO, ui.LABEL);
    y += hud.monoLineH(hud.MONO) + 2;
    if (nameField(ed, ctx, x, y, w, &ed.arenaNameBuf, &ed.arenaNameLen, a.label(), KB_ARENA_NAME, ed.modal == .none, "The room's name as the map file stores it. Spaces and # become _")) |typed| {
        ed.bank(m);
        a.setName(typed);
        ed.dirty = true;
    }
    y += 32;

    var sb: [96]u8 = undefined;
    if (a.seal().len == 0) {
        hud.mono("holds nothing", x, y, hud.MONO, ui.HOT);
    } else {
        var n: usize = 0;
        var line: [96]u8 = undefined;
        for (a.seal()) |k| {
            const t = @tagName(k);
            if (n + t.len + 1 >= line.len) break;
            if (n > 0) {
                line[n] = ',';
                n += 1;
            }
            @memcpy(line[n .. n + t.len], t);
            n += t.len;
        }
        hud.mono(std.fmt.bufPrintZ(&sb, "{s}", .{line[0..n]}) catch "?", x, y, hud.MONO, ui.LIVE);
    }
    y += ROW_H;

    var offered: [wf.MAX_SEAL * 4]wf.FoeKind = undefined;
    var non: usize = 0;
    for (m.foes[0..m.nfoes]) |f| {
        if (!a.contains(f.x, f.z)) continue;
        if (!foemod.isBoss(f.kind) and !a.sealsOn(f.kind)) continue;
        var seen = false;
        for (offered[0..non]) |o| {
            if (o == f.kind) seen = true;
        }
        if (seen or non >= offered.len) continue;
        offered[non] = f.kind;
        non += 1;
    }
    if (non == 0) {
        hud.mono("no boss inside it", x, y, hud.MONO, ui.alpha(ui.LABEL, 160));
        y += ROW_H;
    } else {
        var usedW: i32 = 0;
        for (offered[0..non]) |k| {
            var cb: [40]u8 = undefined;
            const on = a.sealsOn(k);
            const lab = std.fmt.bufPrintZ(&cb, "{s}", .{wf.foeName(k)}) catch "?";
            if (ui.chip(ctx, x + 4, y, lab, on, &usedW, "Hold the room until this creature is dead")) {
                ed.bank(m);
                if (!on and a.nboss >= wf.MAX_SEAL) ed.sayFmt("a seal takes {d} names", .{wf.MAX_SEAL});
                sealToggle(a, k);
                ed.dirty = true;
            }
            y += ROW_H;
        }
    }

    if (ui.button(ctx, ui.rect(x, y, w, 22), "seal from gate", hud.MONO, false, "Copy the seal off the fog gate standing in this room's wall - the one way the two cannot disagree")) {
        if (!ed.sealFromGate(m)) ed.say("no fog gate on this room's wall");
    }
    y += ROW_H;

    if (!a.simple()) {
        hud.mono("outline crosses itself", x, y, hud.MONO, ui.HOT);
        y += ROW_H;
    }
    if (gateOnWall(m, a) == null) {
        hud.mono("no gate on its wall", x, y, hud.MONO, ui.HOT);
        y += ROW_H;
    }

    const half = @divTrunc(w - 6, 2);
    if (ui.button(ctx, ui.rect(x, y, half, 22), "+ corner", hud.MONO, false, "Split the longest wall (Insert)")) ed.splitLongestWall(m);
    if (ui.button(ctx, ui.rect(x + half + 6, y, half, 22), "- corner", hud.MONO, false, "Remove the corner under the cursor (Delete)")) ed.dropCorner(m);
    y += ROW_H;
    if (ui.button(ctx, ui.rect(x, y, w, 22), "delete room", hud.MONO, false, "Throw this room away. Its walls and its gate stay where they are")) {
        ed.bank(m);
        std.mem.copyForwards(wf.Arena, m.arenas[ai .. m.narenas - 1], m.arenas[ai + 1 .. m.narenas]);
        m.narenas -= 1;
        ed.arenaSel = null;
        ed.grab = null;
        ed.dirty = true;
        ed.say("-room");
    }
    return y + ROW_H + 6;
}

fn drawSide(ed: *Editor, ctx: *ui.Ctx, sh: i32) void {
    ui.panel(ctx, ui.rect(0, BAR_H, SIDE_W, sh - BAR_H - STATUS_H), null);
    var y: i32 = BAR_H + 8;

    const selR = ui.rect(8, y, SIDE_W - 16, ROW_H - 2);
    if (ui.iconButton(ctx, selR, .select, "Select", hud.MONO, ed.selecting, "Left-click picks objects; left-drag pans the map (Esc)")) {
        ed.selecting = true;
    }
    y += ROW_H + 8;

    hud.mono("BRUSH", 10, y, hud.MONO, ui.alpha(ui.TRIM, 235));
    y += ROW_H;
    if (ed.layer == .units) y = drawUnitTabs(ed, ctx, y);
    const brushes = brushesFor(ed.layer);
    const tips = brushTipsFor(ed.layer);
    const glyphs = brushIconsFor(ed.layer);
    var slot: usize = 0;
    for (brushes, 0..) |b, i| {
        if (!brushShown(ed, i)) continue;
        defer slot += 1;
        if (brushSectionFor(ed.layer, i)) |sec| {
            hud.mono(sec, 18, y, hud.MONO, ui.alpha(ui.LABEL, 150));
            y += hud.monoLineH(hud.MONO);
        }
        var lab: [40]u8 = undefined;
        const s = if (slot < DIGIT_KEYS) (std.fmt.bufPrintZ(&lab, "{d} {s}", .{ slot + 1, b }) catch b) else b;
        const r = ui.rect(8, y, SIDE_W - 16, ROW_H - 4);
        const on = !ed.selecting and ed.brushIdx() == i;
        const hit = if (glyphs) |g|
            ui.iconButton(ctx, r, g[i], s, hud.MONO, on, tips[i])
        else
            (if (i + 1 == brushes.len)
                ui.iconButton(ctx, r, .erase, s, hud.MONO, on, tips[i])
            else switch (@as(GroundBrush, @enumFromInt(i))) {
                .raise => ui.swatchButton(ctx, r, RAISE_SWATCH, s, hud.MONO, on, tips[i]),
                .lower => ui.swatchButton(ctx, r, LOWER_SWATCH, s, hud.MONO, on, tips[i]),
                .smooth, .flat => ui.swatchButton(ctx, r, EVEN_SWATCH, s, hud.MONO, on, tips[i]),
                .water, .oil, .fungal, .lava => |lq| ui.swatchButton(ctx, r, mapart.liquidSwatch(liquidOf(lq).?), s, hud.MONO, on, tips[i]),
                else => |sl| ui.swatchButton(ctx, r, soilSwatch(soilOf(sl) orelse .none), s, hud.MONO, on, tips[i]),
            });
        if (hit) {
            ed.setBrush(i);
            ed.selecting = false;
        }
        y += ROW_H;
    }
    y += 6;

    if (kindPool(ed.layer)) |pool| {
        hud.mono("GROUP", 10, y, hud.MONO, ui.alpha(ui.TRIM, 235));
        y += ROW_H;
        var chipX: i32 = 8;
        var chipY = y;
        inline for (@typeInfo(props.Group).@"enum".fields) |gf| {
            const gp: props.Group = @enumFromInt(gf.value);
            if (layerHasGroup(ed.layer, gp)) {
                var used: i32 = 0;
                const on = ed.groupSel == gp;
                if (chipX > 8 and chipX + hud.monoW(gp.label(), hud.MONO) + 22 > SIDE_W - 8) {
                    chipX = 8;
                    chipY += 28;
                }
                if (ui.chip(ctx, chipX, chipY, gp.label(), on, &used, "Narrow the KIND list to this family")) ed.groupSel = gp;
                chipX += used;
            }
        }
        y = chipY + 34;

        hud.mono("KIND", 10, y, hud.MONO, ui.alpha(ui.TRIM, 235));
        y += ROW_H;
        var labels: [props.NK][:0]const u8 = undefined;
        var kinds: [props.NK]Kind = undefined;
        var n: usize = 0;
        for (pool) |k| {
            if (props.group(k) != ed.groupSel) continue;
            labels[n] = props.displayName(k);
            kinds[n] = k;
            n += 1;
        }
        const cur = ed.kindForLayer();
        var selIdx: usize = std.math.maxInt(usize);
        for (kinds[0..n], 0..) |k, i| {
            if (k == cur) selIdx = i;
        }
        const listH = @max(0, sh - y - STATUS_H - 8);
        if (ui.list(ctx, ui.rect(8, y, SIDE_W - 16, listH), labels[0..n], selIdx, &ed.kindScroll, "What the brush places. The GROUP chips above narrow this list")) |i| {
            ed.kindSlot().* = kinds[i];
        }
    }
}


fn drawUnitTabs(ed: *Editor, ctx: *ui.Ctx, y0: i32) i32 {
    var y = y0;
    var labels: [UnitTab.N][:0]const u8 = undefined;
    inline for (0..UnitTab.N) |i| labels[i] = (@as(UnitTab, @enumFromInt(i))).label();
    if (ui.tabs(ctx, 8, y, SIDE_W - 16, &labels, @intFromEnum(ed.unitTab), &unitTabTips)) |hit| {
        ed.unitTab = @enumFromInt(hit);
        armFirstShown(ed);
    }
    y += ui.TAB_H + 6;
    if (ed.unitTab != .foes) return y;

    var chipX: i32 = 8;
    inline for (@typeInfo(props.Biome).@"enum".fields) |bf| {
        const b: props.Biome = @enumFromInt(bf.value);
        if (foeBiomes[bf.value]) {
            var used: i32 = 0;
            if (chipX > 8 and chipX + hud.monoW(b.label(), hud.MONO) + 22 > SIDE_W - 8) {
                chipX = 8;
                y += 28;
            }
            if (ui.chip(ctx, chipX, y, b.label(), ed.foeBiome == b, &used, "Narrow the creature list to this kingdom")) {
                ed.foeBiome = b;
                armFirstShown(ed);
            }
            chipX += used;
        }
    }
    return y + 34;
}

fn coordRow(ctx: *ui.Ctx, x: i32, y: *i32, w: i32, label: [:0]const u8, v: *f32, step: f32) bool {
    defer y.* += ROW_H;
    return ui.stepperF(ctx, x, y.*, w, label, v, step, -COORD_LIM, COORD_LIM, "Where this op sits, in world metres. Drag it in the world instead if you would rather");
}

fn centreRows(ctx: *ui.Ctx, x: i32, y: *i32, w: i32, o: *wf.Op, step: f32) bool {
    var ch = coordRow(ctx, x, y, w, "x", &o.x, step);
    ch = coordRow(ctx, x, y, w, "z", &o.z, step) or ch;
    return ch;
}

fn spanRows(ctx: *ui.Ctx, x: i32, y: *i32, w: i32, o: *wf.Op) bool {
    var ch = coordRow(ctx, x, y, w, "x0", &o.x, 1);
    ch = coordRow(ctx, x, y, w, "z0", &o.z, 1) or ch;
    ch = coordRow(ctx, x, y, w, "x1", &o.x1, 1) or ch;
    ch = coordRow(ctx, x, y, w, "z1", &o.z1, 1) or ch;
    return ch;
}

fn gradientRows(ctx: *ui.Ctx, x: i32, y: *i32, w: i32, o: *wf.Op) bool {
    var ch = false;
    hud.mono("density gradient", x, y.*, hud.MONO, ui.alpha(ui.TRIM, 220));
    y.* += hud.monoLineH(hud.MONO);
    var cx = x;
    inline for (@typeInfo(wf.Axis).@"enum".fields) |fld| {
        const ax: wf.Axis = @enumFromInt(fld.value);
        var usedW: i32 = 0;
        const lab: [:0]const u8 = switch (ax) {
            .none => "off",
            .x => "along x",
            .z => "along z",
        };
        if (ui.chip(ctx, cx, y.*, lab, o.gAxis == ax, &usedW, "Thin the scatter from one end to the other along this axis. Off spreads it evenly") and o.gAxis != ax) {
            o.gAxis = ax;
            if (ax != .none and o.gA == o.gB) {
                o.gA = if (ax == .x) @min(o.x, o.x1) else @min(o.z, o.z1);
                o.gB = if (ax == .x) @max(o.x, o.x1) else @max(o.z, o.z1);
                if (o.gB - o.gA < 1.0) o.gB = o.gA + 1.0;
            }
            ch = true;
        }
        cx += usedW;
    }
    y.* += ROW_H + 4;
    if (o.gAxis == .none) return ch;
    ch = ui.stepperF(ctx, x, y.*, w, "from", &o.gA, 1, -COORD_LIM, COORD_LIM, "The FULL end of the fade, in world metres") or ch;
    y.* += ROW_H;
    ch = ui.stepperF(ctx, x, y.*, w, "to", &o.gB, 1, -COORD_LIM, COORD_LIM, "The THIN end of the fade, in world metres") or ch;
    y.* += ROW_H;
    ch = ui.slider(ctx, x, y.*, w, "thin end", &o.gFloor, 0, 1, "What share survives at the thin end. 0 fades to nothing, 1 is no fade at all") or ch;
    y.* += ROW_H + SLIDER_DROP;
    return ch;
}

fn drawProperties(ed: *Editor, m: *wf.Map, env: *envmod.Env, ctx: *ui.Ctx, sw: i32, sh: i32) void {
    ed.textFocus = false;
    const x0 = sw - PROP_W;
    ui.panel(ctx, ui.rect(x0, BAR_H, PROP_W, sh - BAR_H - STATUS_H), null);
    const x = x0 + 10;
    const w = PROP_W - 20;
    var y = BAR_H + 8;

    if (ed.layer == .ground) {
        const brush = @as(GroundBrush, @enumFromInt(ed.brushIdx()));
        const liquid = liquidOf(brush);
        const wet = liquid != null;
        const sculpting = switch (brush) {
            .raise, .lower, .smooth, .flat => true,
            else => false,
        };
        const title: [:0]const u8 = if (sculpting) "SCULPT" else if (liquid) |l| switch (l) {
            .water => "WATER BRUSH",
            .oil => "OIL BRUSH",
            .fungal => "FUNGAL BRUSH",
            .lava => "LAVA BRUSH",
        } else "SOIL BRUSH";
        hud.mono(title, x, y, hud.MONO, ui.TITLE);
        y += ROW_H + 4;
        _ = ui.slider(ctx, x, y, w, "radius", &ed.radius, 1, 60, "How wide the brush bites, in metres");
        y += ROW_H + SLIDER_DROP;
        if (!sculpting and !wet) {
            _ = ui.slider(ctx, x, y, w, "opacity", &ed.soilOpacity, 0, 1, "How much a stroke lays down. Under 1 blends with what is already there, so a pass builds up");
            y += ROW_H + SLIDER_DROP;
        }
        if (!sculpting) {
            hud.mono(if (wet) "coast" else "edge", x, y, hud.MONO, ui.LABEL);
            y += ROW_H;
            if (wet) {
                ui.disabled(ctx, ui.rect(x, y, w, ROW_H), WATER_EDGE.label(), hud.MONO, edgeTip(WATER_EDGE, true));
                y += ROW_H + 6;
            } else {
                const EDGE_COLS = 4;
                const cellW = @divTrunc(w - (EDGE_COLS - 1) * 4, EDGE_COLS);
                for (0..wf.Edge.N) |i| {
                    const e: wf.Edge = @enumFromInt(i);
                    const col: i32 = @intCast(i % EDGE_COLS);
                    const row: i32 = @intCast(i / EDGE_COLS);
                    const r = ui.rect(x + col * (cellW + 4), y + row * (ROW_H + 4), cellW, ROW_H);
                    if (ui.button(ctx, r, e.label(), hud.MONO, ed.brushEdge == e, edgeTip(e, wet))) ed.brushEdge = e;
                }
                y += 2 * (ROW_H + 4) + 6;
            }
        }
        if (sculpting) {
            _ = ui.slider(ctx, x, y, w, "strength", &ed.sculptRate, 0.5, 12, "How fast raise, lower and smooth move the ground under the brush");
            y += ROW_H + SLIDER_DROP;
            var hbuf: [96]u8 = undefined;
            const at = ed.groundAt() orelse mathx.zero3;
            const slope = mathx.degrees(std.math.atan(env.slopeAt(at.x, at.z)));
            const hs = std.fmt.bufPrintZ(&hbuf, "here {d:.2} m   slope {d:.0} deg", .{ at.y - envmod.groundY(), slope }) catch "";
            hud.mono(hs, x, y, hud.MONO, ui.LABEL);
            y += ROW_H;
            const walk = env.walkableAt(at.x, at.z);
            const limit = mathx.degrees(std.math.atan(envmod.MAX_SLOPE));
            const ws = if (walk)
                std.fmt.bufPrintZ(&hbuf, "walkable (limit {d:.0} deg)", .{limit}) catch ""
            else
                std.fmt.bufPrintZ(&hbuf, "TOO STEEP to walk (over {d:.0} deg)", .{limit}) catch "";
            hud.mono(ws, x, y, hud.MONO, if (walk) ui.alpha(ui.LABEL, 190) else ui.HOT);
            y += ROW_H;
            const rs = std.fmt.bufPrintZ(&hbuf, "range {d:.0}..{d:.0} m, {d:.2} m steps", .{ wf.HEIGHT_MIN, wf.HEIGHT_MAX, wf.HEIGHT_STEP }) catch "";
            hud.mono(rs, x, y, hud.MONO, ui.alpha(ui.LABEL, 160));
            y += ROW_H;
            const ss = std.fmt.bufPrintZ(&hbuf, "steps up to {d:.2} m for free", .{envmod.STEP_UP}) catch "";
            hud.mono(ss, x, y, hud.MONO, ui.alpha(ui.LABEL, 160));
            y += ROW_H + 10;
            if (ui.button(ctx, ui.rect(x, y, w, 24), "level the map", hud.MONO, false, "Flatten the whole world back to zero. Undoable")) {
                ed.bank(m);
                m.height = [_]u8{wf.HEIGHT_ZERO} ** wf.HEIGHT_CELLS;
                ed.rebuild(m, env);
                ed.say("ground levelled");
            }
            return;
        }
        var painted: usize = 0;
        if (liquid) |l| {
            const want: u8 = @intFromEnum(l);
            for (m.water, m.waterKind) |v, k| {
                if (v != 0 and k == want) painted += 1;
            }
        } else {
            for (m.soil) |v| {
                if (v != 0) painted += 1;
            }
        }
        var buf: [64]u8 = undefined;
        const total = if (wet) wf.WATER_CELLS else wf.SOIL_CELLS;
        const s = std.fmt.bufPrintZ(&buf, "{d} of {d} cells", .{ painted, total }) catch "";
        hud.mono(s, x, y, hud.MONO, ui.LABEL);
        y += ROW_H;
        const n: usize = if (wet) wf.WATER_N else wf.SOIL_N;
        const cell = m.cellSize(n);
        const s2 = std.fmt.bufPrintZ(&buf, "cell {d:.1} m", .{cell}) catch "";
        hud.mono(s2, x, y, hud.MONO, ui.LABEL);
        y += ROW_H;
        if (liquid) |l| {
            const s3 = std.fmt.bufPrintZ(&buf, "deep at {d:.0} m in", .{gfx.WATER_DEEP_AT}) catch "";
            hud.mono(s3, x, y, hud.MONO, ui.alpha(ui.LABEL, 190));
            y += ROW_H;
            const s4 = std.fmt.bufPrintZ(&buf, "wet sand {d:.1} m out", .{gfx.WATER_WET_OUT}) catch "";
            hud.mono(s4, x, y, hud.MONO, ui.alpha(ui.LABEL, 190));
            y += ROW_H;
            const soak = liquidmod.soakOf(l);
            const s5: [:0]const u8 = if (soak) |sk|
                (std.fmt.bufPrintZ(&buf, "{s} {d:.0}/s{s}", .{
                    combat.ailRow(sk.ail).name,
                    sk.build,
                    if (sk.dpsFrac > 0) " + damage" else "",
                }) catch "")
            else
                "no status";
            hud.mono(s5, x, y, hud.MONO, if (soak == null) ui.alpha(ui.LABEL, 150) else ui.HOT);
            y += ROW_H;
        }
        y += 10;
        const clearLabel: [:0]const u8 = if (wet) "drain the map" else "clear all paint";
        const clearTip: [:0]const u8 = if (wet) "Wipe every painted pool, of every liquid" else "Unpaint the whole map";
        if (ui.button(ctx, ui.rect(x, y, w, 24), clearLabel, hud.MONO, false, clearTip)) {
            ed.bank(m);
            if (wet) {
                m.water = [_]u8{0} ** wf.WATER_CELLS;
                m.waterKind = [_]u8{@intFromEnum(wf.Liquid.water)} ** wf.WATER_CELLS;
                ed.rebuild(m, env);
                ed.say("liquid cleared");
            } else {
                m.soil = [_]u8{0} ** wf.SOIL_CELLS;
                m.soilCov = [_]u8{wf.COV_FULL} ** wf.SOIL_CELLS;
                env.uploadSoil(m);
                ed.say("paint cleared");
            }
        }
        return;
    }

    if (ed.layer == .units) {
        hud.mono("SPAWNS", x, y, hud.MONO, ui.TITLE);
        y += ROW_H + 4;
        const which = ed.selUnit orelse {
            var buf: [64]u8 = undefined;
            const s = std.fmt.bufPrintZ(&buf, "{d} foes, {d} folk", .{ m.nfoes, m.nnpcs }) catch "";
            hud.mono(s, x, y, hud.MONO, ui.LABEL);
            y += ROW_H;
            hud.mono("click one to edit it", x, y, hud.MONO, ui.alpha(ui.LABEL, 160));
            return;
        };
        switch (which) {
            .foe => |f| {
                if (f >= m.nfoes) return;
                const fo = &m.foes[f];
                var head: [48]u8 = undefined;
                const title = std.fmt.bufPrintZ(&head, "#{d} {s}", .{ f, @tagName(fo.kind) }) catch "";
                hud.mono(title, x, y, hud.MONO, ui.TITLE);
                y += ROW_H + 4;
                var changed = false;
                const before = fo.*;
                changed = ui.stepperF(ctx, x, y, w, "x", &fo.x, 0.5, -COORD_LIM, COORD_LIM, "Where it stands, east-west. Its patrol route moves with it") or changed;
                y += ROW_H;
                changed = ui.stepperF(ctx, x, y, w, "z", &fo.z, 0.5, -COORD_LIM, COORD_LIM, "Where it stands, north-south. Its patrol route moves with it") or changed;
                fo.moveRoute(fo.x - before.x, fo.z - before.z);
                y += ROW_H;
                changed = ui.stepperF(ctx, x, y, w, "yaw", &fo.yaw, 15, -360, 720, "Which way it faces when the level starts, in degrees") or changed;
                y += ROW_H;
                changed = ui.stepperF(ctx, x, y, w, "scale", &fo.scale, 0.02, wf.FOE_SCALE_LO, wf.FOE_SCALE_HI, "How big this one is. Reach, health and the weight of its blows all read it") or changed;
                y += ROW_H;
                changed = ui.stepperF(ctx, x, y, w, "phase", &fo.seed, 0.05, 0, 1, "Its own seed - where in its idle it starts, and the wabi-sabi in its body. Two side by side should not match") or changed;
                y += ROW_H;
                hud.mono("orders", x, y, hud.MONO, ui.LABEL);
                y += hud.monoLineH(hud.MONO) + 2;
                var aiW: i32 = 0;
                var aiX = x;
                inline for (@typeInfo(wf.FoeAi).@"enum".fields) |af| {
                    const a: wf.FoeAi = @enumFromInt(af.value);
                    defer aiX += aiW;
                    if (ui.chip(ctx, aiX, y, @tagName(a), fo.ai == a, &aiW, aiTip(a))) {
                        ed.bank(m);
                        ed.editing = true;
                        fo.ai = a;
                        changed = true;
                    }
                }
                y += ROW_H + 4;
                var wb: [56]u8 = undefined;
                const wlab = std.fmt.bufPrintZ(&wb, "route: {d} of {d} legs", .{ fo.route().len, wf.MAX_WP }) catch "";
                hud.mono(wlab, x, y, hud.MONO, if (fo.ai == .patrol and fo.nwp == 0) ui.HOT else ui.LABEL);
                y += ROW_H;
                const half2 = @divTrunc(w - 6, 2);
                if (ui.button(ctx, ui.rect(x, y, half2, 22), if (ed.routing) "stop laying" else "lay route", hud.MONO, ed.routing, "Click the ground to drop each leg of the patrol. Click here again when you are done")) {
                    ed.routing = !ed.routing;
                    if (ed.routing) {
                        ed.bank(m);
                        ed.editing = true;
                        fo.nwp = 0;
                        fo.ai = .patrol;
                        changed = true;
                        ed.say("click the ground for each leg");
                    }
                }
                if (ui.button(ctx, ui.rect(x + half2 + 6, y, half2, 22), "clear route", hud.MONO, false, "Throw the legs away. The body keeps its orders")) {
                    ed.bank(m);
                    ed.editing = true;
                    fo.nwp = 0;
                    ed.routing = false;
                    changed = true;
                }
                y += ROW_H + 6;
                if (ui.button(ctx, ui.rect(x, y, 80, 24), "delete", hud.MONO, false, "Remove this spawn (Del)")) {
                    ed.deleteSel(m, env);
                    return;
                }
                if (changed) {
                    ed.bankGesture(wf.Foe, m, fo, before);
                } else if (!ctx.down) ed.endGesture();
            },
            .npc => |i| {
                if (i >= m.nnpcs) return;
                const np = &m.npcs[i];
                var head: [48]u8 = undefined;
                const title = std.fmt.bufPrintZ(&head, "#{d} {s}", .{ i, @tagName(np.kind) }) catch "";
                hud.mono(title, x, y, hud.MONO, ui.TITLE);
                y += ROW_H + 4;
                var changed = false;
                const before = np.*;
                changed = ui.stepperF(ctx, x, y, w, "x", &np.x, 0.5, -COORD_LIM, COORD_LIM, "Where the body stands, east-west") or changed;
                y += ROW_H;
                changed = ui.stepperF(ctx, x, y, w, "z", &np.z, 0.5, -COORD_LIM, COORD_LIM, "Where the body stands, north-south") or changed;
                y += ROW_H;
                changed = ui.stepperF(ctx, x, y, w, "yaw", &np.yaw, 15, -360, 720, "Which way it faces, in degrees") or changed;
                y += ROW_H;
                changed = ui.stepperF(ctx, x, y, w, "scale", &np.scale, 0.02, wf.FOE_SCALE_LO, wf.FOE_SCALE_HI, "How big this one is") or changed;
                y += ROW_H;
                changed = ui.stepperF(ctx, x, y, w, "phase", &np.seed, 0.05, 0, 1, "Its own seed - where in its idle it starts, and the wabi-sabi in its body") or changed;
                y += ROW_H;
                changed = ui.stepperF(ctx, x, y, w, "roam", &np.roam, 0.5, 0, wf.NPC_ROAM_MAX, "How far it wanders from this post, in metres. At 0 it stands still") or changed;
                y += ROW_H;
                hud.mono("says", x, y + 4, hud.MONO, ui.LABEL);
                {
                    const shown = @min(m.ndialogs, MAX_SLOT_ROWS);
                    var labels: [MAX_SLOT_ROWS + 1][:0]const u8 = undefined;
                    labels[0] = "(nothing)";
                    for (0..shown) |di| {
                        const lbl = m.dialogs[di].label();
                        const cap = @min(lbl.len, wf.ID_CAP - 1);
                        @memcpy(ed.slotLabels[di][0..cap], lbl[0..cap]);
                        ed.slotLabels[di][cap] = 0;
                        labels[di + 1] = ed.slotLabels[di][0..cap :0];
                    }
                    const sel: usize = if (np.dlg == wf.NO_DIALOG or np.dlg >= shown) 0 else @as(usize, np.dlg) + 1;
                    if (ui.dropdown(ctx, ui.rect(x + 44, y, w - 44 - 60, 20), ui.ddId(15, i, 0), labels[0 .. shown + 1], sel, "Which conversation this body opens when he is spoken to")) |pick| {
                        ed.bank(m);
                        ed.editing = true;
                        np.dlg = if (pick == 0) wf.NO_DIALOG else @intCast(pick - 1);
                        np.dlgRef = if (pick == 0) wf.Span{} else (m.addText(m.dialogs[pick - 1].label()) catch blk: {
                            ed.say("the map's text arena is full");
                            break :blk wf.Span{};
                        });
                        changed = true;
                        ed.requestFolk();
                    }
                    if (ui.button(ctx, ui.rect(x + w - 56, y, 56, 20), "talk...", hud.MONO, ed.modal == .talk, "Write what this body says, and which counter a line opens")) {
                        openTalk(ed, m, i);
                        return;
                    }
                }
                y += ROW_H + 6;
                if (ui.button(ctx, ui.rect(x, y, 80, 24), "delete", hud.MONO, false, "Remove this body (Del)")) {
                    ed.deleteSel(m, env);
                    return;
                }
                if (changed) {
                    ed.bankGesture(wf.Npc, m, np, before);
                    ed.requestFolk();
                } else if (!ctx.down) ed.endGesture();
            },
        }
        return;
    }

    if (ed.layer == .locations) {
        if (m.nlocations > 0) {
            hud.mono("LOCATIONS", x, y, hud.MONO, ui.TITLE);
            y += ROW_H + 4;
            var lchanged = false;
            for (m.locations[0..m.nlocations], 0..) |*l, i| {
                var lb: [56]u8 = undefined;
                const on = ed.locSel == i;
                const lab = std.fmt.bufPrintZ(&lb, "{s}{s}", .{ l.label(), if (l.hasWeather()) " *" else "" }) catch "?";
                if (ui.button(ctx, ui.rect(x, y, w, 22), lab, hud.MONO, on, "Select this location - a * means it carries weather. Drag it or its corners in the world")) {
                    if (on) ed.locSel = null else ed.selectLocation(m, i);
                    ed.grab = null;
                }
                y += ROW_H;
                if (!on) continue;
                const lbefore = l.*;
                hud.mono("name", x, y, hud.MONO, ui.LABEL);
                y += hud.monoLineH(hud.MONO) + 2;
                if (nameField(ed, ctx, x, y, w, &ed.locNameBuf, &ed.locNameLen, l.label(), KB_LOC_NAME, ed.modal == .none, "The name triggers find this region by. Spaces and # become _")) |typed| {
                    ed.bank(m);
                    ed.editing = true;
                    l.setName(typed);
                    lchanged = true;
                }
                y += 32;
                var wet = l.wet orelse 0;
                var fog = l.fog orelse 0;
                var spore = l.spore orelse 0;
                var has = l.hasWeather();
                var usedW: i32 = 0;
                if (ui.chip(ctx, x + 8, y, "weather", has, &usedW, "Give this region its own sky. OFF is not the same as dry - it leaves the world's own storm alone")) {
                    has = !has;
                    l.wet = if (has) wet else null;
                    l.fog = if (has) fog else null;
                    l.spore = if (has) spore else null;
                    lchanged = true;
                }
                y += ROW_H;
                if (has) {
                    if (ui.slider(ctx, x + 8, y, w - 16, "wet", &wet, 0, 1, "How hard it rains here. 0 is dry whatever the world clock is doing")) {
                        l.wet = wet;
                        lchanged = true;
                    }
                    y += ROW_H + SLIDER_DROP;
                    if (ui.slider(ctx, x + 8, y, w - 16, "fog", &fog, 0, 1, "How thick the air is here")) {
                        l.fog = fog;
                        lchanged = true;
                    }
                    y += ROW_H + SLIDER_DROP;
                    if (ui.slider(ctx, x + 8, y, w - 16, "spore", &spore, 0, 1, "How much sporefall drifts here")) {
                        l.spore = spore;
                        lchanged = true;
                    }
                    y += ROW_H + SLIDER_DROP;
                    if (ui.slider(ctx, x + 8, y, w - 16, "blend s", &l.blend, 0, 30, "Seconds to cross-fade into this region's sky as he walks in. A region is never a switch")) lchanged = true;
                    y += ROW_H + SLIDER_DROP;
                }
                if (lchanged) ed.bankGesture(wf.Location, m, l, lbefore);
            }
            if (lchanged) ed.dirty = true;
            y += 6;
        }
        y = drawRoomsPanel(ed, ctx, m, x, y, w);
        hud.mono("ZONES", x, y, hud.MONO, ui.TITLE);
        y += ROW_H + 4;
        var changed = false;
        var before: [wf.MAX_ZONES]f32 = undefined;
        for (m.zones[0..m.nzones], 0..) |*z, i| before[i] = z.density;
        for (m.zones[0..m.nzones], 0..) |*z, i| {
            var zb: [48]u8 = undefined;
            const lab = std.fmt.bufPrintZ(&zb, "{d} {s} ({d})", .{ i, z.label(), z.nmix }) catch "?";
            changed = ui.slider(ctx, x, y, w - 34, lab, &z.density, 0, 1, "How thickly this zone grows. The cover field thins it further in clearings") or changed;
            if (ui.button(ctx, ui.rect(x + w - 30, y + 14, 30, 22), "...", hud.MONO, ed.zoneSel == i, "Name this zone and choose what grows in it")) {
                ed.selectZone(m, i);
                ed.modal = .zonemix;
            }
            y += ROW_H + SLIDER_DROP;
        }
        y += 6;
        if (ed.zoneSel) |zi| {
            if (zi < m.nzones) {
                hud.mono("name", x, y, hud.MONO, ui.LABEL);
                y += hud.monoLineH(hud.MONO) + 2;
                if (nameField(ed, ctx, x, y, w, &ed.zoneNameBuf, &ed.zoneNameLen, m.zones[zi].label(), KB_ZONE_NAME, ed.modal == .none, "The zone's name as the map file stores it. Spaces and # become _")) |typed| {
                    ed.bank(m);
                    m.zones[zi].setName(typed);
                }
                y += 32;
            }
        }
        var cb: [64]u8 = undefined;
        const cs = std.fmt.bufPrintZ(&cb, "CLEARINGS ({d})", .{m.nclearings}) catch "";
        hud.mono(cs, x, y, hud.MONO, ui.TITLE);
        y += ROW_H + 4;
        for (m.clearings[0..m.nclearings], 0..) |*c, i| {
            var rb: [48]u8 = undefined;
            const on = ed.clearSel == i;
            const lab = std.fmt.bufPrintZ(&rb, "{d}  r {d:.0}  ({d:.0}, {d:.0})", .{ i, c.r, c.x, c.z }) catch "?";
            if (ui.button(ctx, ui.rect(x, y, w, 22), lab, hud.MONO, on, "Select this clearing. Drag its middle to move it, or its rim to resize it")) {
                if (on) ed.clearSel = null else ed.selectClearing(i);
                ed.grab = null;
            }
            y += ROW_H;
            if (!on) continue;
            if (ui.stepperF(ctx, x + 8, y, w - 16, "radius", &c.r, 1, MIN_CLEARING_R, 200, "How wide the open ground is, in metres")) {
                ed.bank(m);
                ed.requestRebuild();
                ed.dirty = true;
            }
            y += ROW_H;
            if (ui.button(ctx, ui.rect(x + 8, y, w - 16, 22), "delete clearing", hud.MONO, false, "Remove it - the ground it was holding open grows back")) {
                ed.bank(m);
                std.mem.copyForwards(wf.Clearing, m.clearings[i .. m.nclearings - 1], m.clearings[i + 1 .. m.nclearings]);
                m.nclearings -= 1;
                ed.clearSel = null;
                ed.requestRebuild();
                ed.dirty = true;
            }
            y += ROW_H;
            break;
        }
        if (changed) {
            if (!ed.editing) {
                var live: [wf.MAX_ZONES]f32 = undefined;
                for (m.zones[0..m.nzones], 0..) |*z, i| {
                    live[i] = z.density;
                    z.density = before[i];
                }
                ed.bank(m);
                for (m.zones[0..m.nzones], 0..) |*z, i| z.density = live[i];
                ed.editing = true;
            }
            ed.requestRebuild();
        } else if (!ctx.down) ed.endGesture();
        return;
    }

    if (ed.layer == .interact) {
        const left = unfilledCount(ed, m);
        var eb: [40]u8 = undefined;
        const lab = if (left > 0)
            std.fmt.bufPrintZ(&eb, "next empty ({d})", .{left}) catch "next empty"
        else
            "all filled";
        if (ui.button(ctx, ui.rect(x, y, w, 24), lab, hud.MONO, false, "Centre on the next chest or item with nothing in it, wrapping round the map. Right-click it and pick Items... to fill it")) {
            goToUnfilled(ed, m);
            return;
        }
        y += ROW_H + 6;
    }

    const s = ed.sel orelse {
        hud.mono("nothing selected", x, y, hud.MONO, ui.LABEL);
        y += ROW_H;
        hud.mono("click something in", x, y, hud.MONO, ui.alpha(ui.LABEL, 160));
        y += ROW_H;
        hud.mono("this layer to edit it", x, y, hud.MONO, ui.alpha(ui.LABEL, 160));
        return;
    };
    if (s >= m.nops) return;
    const o = &m.ops[s];
    if (layerOf(o) != ed.layer) {
        hud.mono("selection is on", x, y, hud.MONO, ui.LABEL);
        y += ROW_H;
        hud.mono("another layer", x, y, hud.MONO, ui.LABEL);
        return;
    }

    var head: [48]u8 = undefined;
    const title = std.fmt.bufPrintZ(&head, "#{d} {s}", .{ s, @tagName(o.op) }) catch "";
    hud.mono(title, x, y, hud.MONO, ui.TITLE);
    if (ui.button(ctx, ui.rect(x + w - 74, y - 2, 74, 22), "view", hud.MONO, false, "Open this kind in the object viewer")) {
        ed.objects.show(o.kind);
        ed.modal = .objects;
        return;
    }
    y += ROW_H;
    var own: [56]u8 = undefined;
    const owned = if (ed.selOwned > ed.selMarked)
        std.fmt.bufPrintZ(&own, "{d} instances ({d} marked)", .{ ed.selOwned, ed.selMarked }) catch ""
    else
        std.fmt.bufPrintZ(&own, "{d} instances", .{ed.selOwned}) catch "";
    hud.mono(owned, x, y, hud.MONO, ui.alpha(ui.LABEL, if (ed.selOwned > ed.selMarked) 255 else 170));
    y += ROW_H + 4;

    var changed = false;
    const before = o.*;

    switch (o.op) {
        .at => {
            changed = centreRows(ctx, x, &y, w, o, 0.5) or changed;
            changed = ui.stepperF(ctx, x, y, w, "yaw", &o.yaw, 5, -360, 720, "Which way the piece faces, in degrees") or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "scale", &o.scale, 0.05, 0.1, 4, "How big the piece is, as a multiple of its authored size") or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "lean", &o.lean, 1, 0, LEAN_LIM, "Degrees off plumb. Nothing dead stands straight") or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "lean dir", &o.leanDir, 15, -360, 720, "Which way it leans, in degrees") or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "lift", &o.r1, 0.1, -LIFT_LIM, LIFT_LIM, "Metres off the ground it sits. Negative beds it in, which is how a boulder half-buried in a slope is authored") or changed;
            y += ROW_H;
            const seg = props.info(o.kind).stack * o.scale;
            if (seg > 0) {
                changed = ui.stepperF(ctx, x, y, w, "rise", &o.rise, seg, seg, RISE_LIM, "How far up it runs, in metres. One step is one section - the rungs keep their spacing however tall it gets") or changed;
                y += ROW_H;
            }
        },
        .belt, .ivy => {
            changed = spanRows(ctx, x, &y, w, o) or changed;
            if (o.op == .belt) {
                changed = ui.stepperI(ctx, x, y, w, "count", &o.n, 5, 0, COUNT_MAX, "How many to try to place. Rejected candidates still cost time, so this is an ASK and not a promise") or changed;
                y += ROW_H;
            } else {
                changed = ui.slider(ctx, x, y, w, "take", &o.chance, 0, 1, "What share of the candidates actually stand. Under 1 is what stops a belt reading as a fence") or changed;
                y += ROW_H + SLIDER_DROP;
            }
        },
        .disc => {
            changed = centreRows(ctx, x, &y, w, o, 1) or changed;
            changed = ui.stepperF(ctx, x, y, w, "inner", &o.r0, 0.5, 0, 200, "Hole in the middle, in metres. 0 fills the disc") or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "outer", &o.r1, 0.5, 0, 200, "How far out it reaches, in metres") or changed;
            y += ROW_H;
            changed = ui.stepperI(ctx, x, y, w, "count", &o.n, 5, 0, COUNT_MAX, "How many to try to place") or changed;
            y += ROW_H;
            changed = ui.slider(ctx, x, y, w, "centre bias", &o.bias, 0, 1, "Pull them toward the middle. 0 spreads evenly across the disc") or changed;
            y += ROW_H + SLIDER_DROP;
        },
        .ring => {
            changed = centreRows(ctx, x, &y, w, o, 1) or changed;
            changed = ui.stepperF(ctx, x, y, w, "radius", &o.r0, 0.5, 0.5, 200, "How wide the ring stands, in metres") or changed;
            y += ROW_H;
            changed = ui.stepperI(ctx, x, y, w, "count", &o.n, 1, 2, RING_N_MAX, "How many stand in the ring, spaced evenly") or changed;
            y += ROW_H;
            changed = ui.stepperI(ctx, x, y, w, "gap at", &o.skip, 1, -1, RING_N_MAX - 1, "Leave one place empty, so the ring has a way in. -1 closes it") or changed;
            y += ROW_H;
        },
        .line => {
            changed = spanRows(ctx, x, &y, w, o) or changed;
            changed = ui.stepperF(ctx, x, y, w, "step", &o.r0, 0.25, 0.5, 40, "Metres between one and the next along the row") or changed;
            y += ROW_H;
            changed = ui.slider(ctx, x, y, w, "stands", &o.chance, 0, 1, "What share of the places along the row are actually filled. Under 1 is what makes a ruin a ruin") or changed;
            y += ROW_H + SLIDER_DROP;
        },
    }

    if (o.op != .at) {
        changed = ui.stepperF(ctx, x, y, w, "scale lo", &o.sLo, 0.05, 0.1, 3, "Smallest of the batch. Equal to scale hi means every one is the same size, which reads as fake") or changed;
        y += ROW_H;
        changed = ui.stepperF(ctx, x, y, w, "scale hi", &o.sHi, 0.05, 0.1, 3, "Largest of the batch") or changed;
        y += ROW_H;
        if (changed and o.sHi < o.sLo) o.sHi = o.sLo;
        changed = ui.stepperF(ctx, x, y, w, "lean max", &o.lean, 1, 0, LEAN_LIM, "How far off plumb any one of them may lean, in degrees") or changed;
        y += ROW_H;
        var sb: [40]u8 = undefined;
        const seedLab = std.fmt.bufPrintZ(&sb, "seed {d}", .{o.seed}) catch "";
        hud.mono(seedLab, x, y + 4, hud.MONO, ui.LABEL);
        if (ui.button(ctx, ui.rect(x + w - 90, y, 90, 24), "re-roll", hud.MONO, false, "A different arrangement, same meaning (R)")) {
            ed.rerollSel(m, env);
            return;
        }
        y += ROW_H + 6;
        if (ui.button(ctx, ui.rect(x, y, w, 24), "break apart", hud.MONO, false, "One op per instance, so a single one can be moved or deleted. No way back but undo")) {
            ed.explodeSel(m, env);
            return;
        }
        y += ROW_H + 6;

        hud.mono("keeps off", x, y, hud.MONO, ui.alpha(ui.TRIM, 220));
        y += hud.monoLineH(hud.MONO);
        changed = ui.checkbox(ctx, x, y, "runway", &o.avoid.runway, "Keep clear of the runway - the corridor the player starts in") or changed;
        y += 22;
        changed = ui.checkbox(ctx, x, y, "water", &o.avoid.water, "Keep out of painted water") or changed;
        y += 22;
        changed = ui.checkbox(ctx, x, y, "clearings", &o.avoid.clear, "Keep out of the clearings - the circles that hold open ground") or changed;
        y += 22;
        changed = ui.checkbox(ctx, x, y, "solids", &o.avoid.solid, "Do not stand inside anything already placed") or changed;
        y += 22;
        if (o.op == .belt or o.op == .disc) {
            changed = ui.checkbox(ctx, x, y, "cover field", &o.field, "Thin the scatter by the world's own cover noise, so it drops to nothing in clearings. On by default for a belt") or changed;
            y += 26;
            changed = gradientRows(ctx, x, &y, w, o) or changed;
        }
    }

    if (ui.button(ctx, ui.rect(x, y, 44, 24), "up", hud.MONO, false, "Run EARLIER - order decides what later ops can see")) {
        if (s > 0) {
            ed.bank(m);
            m.reorder(s, s - 1);
            ed.sel = s - 1;
            ed.rebuild(m, env);
        }
        return;
    }
    if (ui.button(ctx, ui.rect(x + 48, y, 60, 24), "down", hud.MONO, false, "Run LATER")) {
        if (s + 1 < m.nops) {
            ed.bank(m);
            m.reorder(s, s + 1);
            ed.sel = s + 1;
            ed.rebuild(m, env);
        }
        return;
    }
    if (ui.button(ctx, ui.rect(x + w - 80, y, 80, 24), "delete", hud.MONO, false, "Remove this op (Del)")) {
        ed.deleteSel(m, env);
        return;
    }

    if (changed) {
        ed.bankGesture(wf.Op, m, o, before);
        ed.requestRebuild();
    } else if (!ctx.down) {
        ed.endGesture();
    }
}

fn drawMinimap(ed: *Editor, m: *const wf.Map, env: *const envmod.Env, ctx: *ui.Ctx, sw: i32, sh: i32) void {
    const x0 = sw - PROP_W - MINI_W - 8;
    const y0 = sh - STATUS_H - MINI_W - 8;
    const r = ui.rect(x0, y0, MINI_W, MINI_W);
    ui.panel(ctx, r, null);
    const inner: f32 = @floatFromInt(MINI_W - 8);
    const px = x0 + 4;
    const py = y0 + 4;

    blitMinimap(ed, m, env, px, py, inner);

    const cp = mapart.toFlat(
        mathx.clampF(ed.cam.position.x, -m.half, m.half),
        mathx.clampF(ed.cam.position.z, -m.half, m.half),
        m.half,
        px,
        py,
        inner,
    );
    const f = ed.forward();
    rl.drawLineV(cp, .{ .x = cp.x + f.x * 12, .y = cp.y + f.z * 12 }, ui.HOT);
    rl.drawCircleV(cp, 3, ui.HOT);

    if (ctx.pressed and rl.checkCollisionPointRec(ctx.mouse, r)) {
        const t = mathx.clampF((ctx.mouse.x - @as(f32, @floatFromInt(px))) / inner, 0, 1);
        const u = mathx.clampF((ctx.mouse.y - @as(f32, @floatFromInt(py))) / inner, 0, 1);
        ed.lookAtGround(-m.half + t * 2 * m.half, -m.half + u * 2 * m.half, 60);
    }
    ui.tipFor(ctx, r, "Click to fly there");
}

/// Painted on change, not per frame: one rectangle per op, and `01_fallen_plain` stands at 16,563 of them —
/// measured, they collapse only 1.33x onto the 182x182 face.
var miniRT: ?rl.RenderTexture2D = null;
var miniPainted: u64 = std.math.maxInt(u64);
var miniLayer: Layer = .ground;
var miniOf: [wf.NAME_CAP]u8 = [_]u8{0} ** wf.NAME_CAP;
var miniHalf: f32 = 0;

pub fn unloadMinimap() void {
    if (miniRT) |t| rl.unloadRenderTexture(t);
    miniRT = null;
    miniPainted = std.math.maxInt(u64);
}

fn blitMinimap(ed: *Editor, m: *const wf.Map, env: *const envmod.Env, px: i32, py: i32, inner: f32) void {
    const side: i32 = MINI_W - 8;
    if (miniRT == null) miniRT = rl.loadRenderTexture(side, side) catch null;
    const rt = miniRT orelse return paintMinimap(m, env, px, py, inner);

    const swapped = !std.mem.eql(u8, &miniOf, &m.name) or miniHalf != m.half;
    if (miniPainted != ed.miniGen or miniLayer != ed.layer or swapped) {
        miniPainted = ed.miniGen;
        miniLayer = ed.layer;
        miniOf = m.name;
        miniHalf = m.half;
        rl.beginTextureMode(rt);
        paintMinimap(m, env, 0, 0, inner);
        rl.endTextureMode();
    }
    // A straight copy, not a blend: raylib blends the target's OWN alpha by `SRC_ALPHA` like the colour, and
    // blending that back over the panel multiplies the face a second time — measured, 49/765 darker over 78% of it.
    rl.gl.rlSetBlendFactors(gfx.GL_ONE, gfx.GL_ZERO, gfx.GL_FUNC_ADD);
    rl.beginBlendMode(.custom);
    // A render texture reads bottom-up, so the source height is negative.
    rl.drawTextureRec(
        rt.texture,
        .{ .x = 0, .y = 0, .width = @floatFromInt(side), .height = @floatFromInt(-side) },
        .{ .x = @floatFromInt(px), .y = @floatFromInt(py) },
        rl.Color.white,
    );
    rl.endBlendMode();
}

fn paintMinimap(m: *const wf.Map, env: *const envmod.Env, px: i32, py: i32, inner: f32) void {
    rl.drawRectangle(px, py, MINI_W - 8, MINI_W - 8, mapart.GROUND);

    for (m.water, m.waterKind, 0..) |wet, k, i| miniLiquid[i] = if (wet != 0) k + 1 else 0;
    mapart.blitField(miniLiquid[0..], wf.WATER_N, px, py, inner, mapart.liquidByte);

    for (env.placed()) |*pr| {
        if (pr.gone or mapart.markFor(pr.kind) != .water) continue;
        if (!mapart.onFlat(pr.pos.x, pr.pos.z, m.half)) continue;
        const p = mapart.toFlat(pr.pos.x, pr.pos.z, m.half, px, py, inner);
        rl.drawCircleV(p, props.info(pr.kind).bound * pr.scale * inner / (2.0 * m.half), mapart.liquidSwatch(.water));
    }

    for ([_]mapart.Mark{ .tree, .wall }) |want| {
        for (env.placed()) |*pr| {
            if (pr.gone) continue;
            const mark = mapart.markFor(pr.kind) orelse continue;
            if (mark != want) continue;
            if (!mapart.onFlat(pr.pos.x, pr.pos.z, m.half)) continue;
            const p = mapart.toFlat(pr.pos.x, pr.pos.z, m.half, px, py, inner);
            switch (mark) {
                .tree => rl.drawRectangleV(.{ .x = p.x - 0.5, .y = p.y - 0.5 }, .{ .x = 1.5, .y = 1.5 }, MINI_TREE),
                .wall => {
                    const wpx = mathx.maxF(mapart.widthFor(pr.kind) * pr.scale * inner / (2.0 * m.half), 2.0);
                    rl.drawRectangleV(.{ .x = p.x - wpx * 0.5, .y = p.y - wpx * 0.5 }, .{ .x = wpx, .y = wpx }, mapart.WALL);
                },
                .fire, .water => {},
            }
        }
    }
    for (env.placed()) |*pr| {
        if (pr.gone or !restmod.isRestKind(pr.kind)) continue;
        if (!mapart.onFlat(pr.pos.x, pr.pos.z, m.half)) continue;
        const p = mapart.toFlat(pr.pos.x, pr.pos.z, m.half, px, py, inner);
        rl.drawCircleV(p, 3.0, MINI_FIRE_HALO);
        rl.drawCircleV(p, 1.5, MINI_FIRE);
    }
    for (m.foes[0..m.nfoes]) |f| {
        if (!mapart.onFlat(f.x, f.z, m.half)) continue;
        const p = mapart.toFlat(f.x, f.z, m.half, px, py, inner);
        rl.drawCircleV(p, 1.5, MINI_FOE);
    }
}

const MINI_TREE = ui.col(74, 106, 56, 190);
const MINI_FIRE = ui.col(255, 220, 150, 255);
const MINI_FIRE_HALO = ui.col(236, 132, 46, 120);
const MINI_FOE = ui.col(232, 58, 44, 255);

/// `wf.Liquid` PLUS ONE per painted cell, 0 where the sheet is dry — `blitField` reads 0 as "nothing here", so
/// water (ordinal 0) needs the shift to be drawn at all.
var miniLiquid: [wf.WATER_CELLS]u8 = [_]u8{0} ** wf.WATER_CELLS;


fn soilSwatch(s: wf.Soil) rl.Color {
    return switch (s) {
        .none => ui.col(0, 0, 0, 0),
        .dirt => ui.col(112, 92, 64, 255),
        .turf => ui.col(70, 96, 44, 255),
        .stone => ui.col(122, 124, 120, 255),
        .silt => ui.col(146, 128, 88, 255),
        .ash => ui.col(62, 58, 54, 255),
        .moss => ui.col(52, 78, 40, 255),
        .bone => ui.col(168, 160, 138, 255),
        .cinder => ui.col(58, 42, 36, 255),
        .spore => ui.col(74, 62, 84, 255),
        .bloom => ui.col(150, 96, 112, 255),
    };
}

fn drawStatus(ed: *Editor, m: *const wf.Map, env: *const envmod.Env, ctx: *ui.Ctx, sw: i32, sh: i32) void {
    ui.panel(ctx, ui.rect(0, sh - STATUS_H, sw, STATUS_H), null);
    const ty = sh - STATUS_H + 5;

    var buf: [200]u8 = undefined;
    const g = ed.groundAt() orelse mathx.zero3;
    var hbuf: [24]u8 = undefined;
    const hs: [:0]const u8 = if (env.heightAny)
        (std.fmt.bufPrintZ(&hbuf, ",{d:.1}m", .{g.y - envmod.groundY()}) catch "")
    else
        "";
    const right = std.fmt.bufPrintZ(&buf, "{s}{s} {d}ops {d}props {d}drawn   {s}  {d:.0},{d:.0}{s}  r{d:.0}{s}", .{
        m.label(),
        if (ed.dirty) "*" else "",
        m.nops,
        env.nprops,
        env.stat_draws,
        ed.layer.label(),
        g.x,
        g.z,
        hs,
        ed.radius,
        if (ed.snap) "  SNAP" else "",
    }) catch "";
    const rightX = sw - hud.monoW(right, hud.MONO) - CHROME_PAD;
    hud.mono(right, rightX, ty, hud.MONO, if (ed.dirty) ui.HOT else ui.LABEL);

    var capBuf: [56]u8 = undefined;
    if (env.opsCapped > 0 or env.lightsCapped > 0) {
        const cap = if (env.opsCapped > 0)
            std.fmt.bufPrintZ(&capBuf, "{d} ops hit the budget", .{env.opsCapped}) catch ""
        else
            std.fmt.bufPrintZ(&capBuf, "{d} props left UNLIT (light cap)", .{env.lightsCapped}) catch "";
        hud.mono(cap, rightX - hud.monoW(cap, hud.MONO) - GUTTER, ty, hud.MONO, ui.HOT);
    }

    const room = rightX - GUTTER;
    if (ed.statusT > 0 and ed.statusLen > 0) {
        var msg: [ui.MSG_CAP]u8 = undefined;
        var len = @min(ed.statusLen, msg.len - 1);
        @memcpy(msg[0..len], ed.status[0..len]);
        const adv = hud.monoW("M", hud.MONO);
        if (adv > 0) {
            const fits: usize = @intCast(@max(0, @divTrunc(room - CHROME_PAD, adv)));
            len = @min(len, @max(fits, 4));
        }
        msg[len] = 0;
        hud.mono(msg[0..len :0], CHROME_PAD, ty, hud.MONO, ui.HOT);
        return;
    }
    for (CRIBS, 0..) |c, i| {
        if (cribW[i] < 0) cribW[i] = hud.monoW(c, hud.MONO);
        if (CHROME_PAD + cribW[i] <= room) {
            hud.mono(c, CHROME_PAD, ty, hud.MONO, ui.alpha(ui.LABEL, 200));
            return;
        }
    }
}

const EDIT_HOUR_RATE: f32 = 6.0;
const EDIT_HOUR_FAST: f32 = 24.0;

const CRIBS = [_][:0]const u8{
    "LMB brush   Shift+LMB marquee   RMB menu / deselect, drag rotates   wheel zoom   WASD+arrows pan   Tab layer   Ctrl+Z/Y undo   Ctrl+C/X/V copy   Ctrl+A all   Del delete   R re-roll   G grid   [ ] size   ,/. time   Ctrl+S save   F5 play   Esc back",
    "LMB brush   Shift+LMB marquee   RMB menu/rotate   wheel zoom   WASD pan   Tab layer   Ctrl+Z undo   Ctrl+C/V copy   Del delete   G grid   [ ] size   ,/. time   F5 play   Esc back",
    "LMB brush   Shift+LMB marquee   RMB menu/rotate   wheel zoom   WASD pan   Tab layer   Ctrl+Z undo   Del delete   G grid   F5 play",
    "LMB brush   Shift+LMB marquee   RMB menu, drag rotates   wheel zoom   WASD pan   Tab layer   ,/. time",
    "LMB brush   Shift+LMB marquee   RMB menu/rotate   wheel zoom   WASD pan   Tab layer",
    "LMB brush   Shift marquee   Tab layer   Esc back",
};
var cribW = [_]i32{-1} ** CRIBS.len;


fn drawModal(ed: *Editor, m: *wf.Map, env: *envmod.Env, scene: *gfx.Scene, day: *daynight.Clock, ctx: *ui.Ctx) void {
    const alt = rl.isKeyDown(.left_alt) or rl.isKeyDown(.right_alt);
    const confirm = rl.isKeyPressed(.enter) and !alt;
    switch (ed.modal) {
        .none => {},
        .confirm => {
            const box = ui.beginModal(ctx, 460, 170, "Unsaved changes");
            const y = box.y + 62;
            var buf: [wf.PATH_CAP + 40]u8 = undefined;
            const s = std.fmt.bufPrintZ(&buf, "{s} has unsaved edits.", .{ed.curPath()}) catch "";
            hud.mono(s, box.x + DLG_PAD, y, hud.MONO, ui.VALUE);
            const by = box.y + box.h - DLG_FOOT;
            if (ui.button(ctx, ui.rect(box.x + DLG_PAD, by, 120, DLG_BTN_H), "Save first", hud.MONO, false, "Write the file, then go on with what you asked for (Enter)") or confirm) {
                if (ed.saveNow(m)) {
                    const what = ed.pending;
                    ed.modal = .none;
                    ed.commitPending(what);
                }
                return;
            }
            if (ui.button(ctx, ui.rect(box.x + 154, by, 120, DLG_BTN_H), "Discard", hud.MONO, false, "Throw the edits away and go on")) {
                const what = ed.pending;
                ed.dirty = false;
                ed.modal = .none;
                ed.commitPending(what);
                return;
            }
            if (ui.button(ctx, ui.rect(box.x + 300, by, 120, DLG_BTN_H), "Cancel", hud.MONO, false, "Stay here and keep editing (Esc)")) {
                ed.modal = .none;
                ed.pending = .none;
            }
        },
        .loot => {
            const sPre = lootOp(ed, m) orelse {
                ed.modal = .none;
                return;
            };
            var shown: [item.NK]item.Kind = undefined;
            var nshown: usize = 0;
            for (0..item.NK) |ki| {
                const k: item.Kind = @enumFromInt(ki);
                if (item.class(k) != ed.lootTab) continue;
                shown[nshown] = k;
                nshown += 1;
            }
            const rows: i32 = @intCast(@max(nshown, 1));
            const title: [:0]const u8 = if (m.ops[sPre].kind == .chest) "Chest contents" else "Item contents";
            const box = ui.beginModal(ctx, LIST_W, LOOT_TOP + TAB_H + rows * LOOT_ROW_H + 8 + DLG_FOOT, title);
            const s = sPre;
            const o = &m.ops[s];
            var buf: [48]u8 = undefined;
            const total = std.fmt.bufPrintZ(&buf, "{d} / {d} items", .{ o.nloot, wf.MAX_LOOT }) catch "";
            hud.mono(total, box.x + DLG_PAD, box.y + 58, hud.MONO, ui.LABEL);

            const CLASSES = [_]item.Class{ .tool, .gear, .material, .treasure, .key };
            comptime {
                for (@typeInfo(item.Class).@"enum".fields) |f| {
                    var found = false;
                    for (CLASSES) |c| {
                        if (@intFromEnum(c) == f.value) found = true;
                    }
                    if (!found) @compileError("editor: the loot modal has no tab for item.Class." ++ f.name);
                }
                if (CLASSES.len != @typeInfo(item.Class).@"enum".fields.len) @compileError("editor: the loot modal names a class twice");
            }
            const tabW: i32 = @divTrunc(box.w - DLG_PAD * 2, @as(i32, CLASSES.len));
            for (CLASSES, 0..) |c, ci| {
                var tb: [24]u8 = undefined;
                var carried: u8 = 0;
                for (o.loot[0..o.nloot]) |it| {
                    if (item.class(it) == c) carried += 1;
                }
                const lab = if (carried > 0)
                    std.fmt.bufPrintZ(&tb, "{s} *", .{c.label()}) catch c.label()
                else
                    c.label();
                const r = ui.rect(box.x + DLG_PAD + @as(i32, @intCast(ci)) * tabW, box.y + LOOT_TOP, tabW - 3, TAB_H - 4);
                if (ui.button(ctx, r, lab, hud.MONO, ed.lootTab == c, "Show this shelf - a * means this container already holds one")) ed.lootTab = c;
            }

            for (shown[0..nshown], 0..) |k, row| {
                const y = box.y + LOOT_TOP + TAB_H + @as(i32, @intCast(row)) * LOOT_ROW_H;
                hud.mono(item.displayName(k), box.x + DLG_PAD, y + 5, hud.MONO, ui.VALUE);
                var ebuf: [item.EFFECT_BUF]u8 = undefined;
                var tbuf: [item.EFFECT_BUF + 32]u8 = undefined;
                const tip = std.fmt.bufPrintZ(&tbuf, "{s}  -  {s}", .{ item.class(k).label(), item.effect(k, &ebuf) }) catch item.effect(k, &ebuf);
                ui.tipFor(ctx, ui.rect(box.x + DLG_PAD, y, 360 - DLG_PAD, LOOT_ROW_H), tip);
                const n = lootCount(o, k);
                var nbuf: [8]u8 = undefined;
                const ns = std.fmt.bufPrintZ(&nbuf, "{d}", .{n}) catch "0";
                hud.mono(ns, box.x + 340, y + 5, hud.MONO, if (n > 0) ui.VALUE else ui.LABEL);
                if (ui.button(ctx, ui.rect(box.x + 368, y, 24, 22), "-", hud.MONO, false, "One fewer of this item in the container") and n > 0) {
                    ed.bank(m);
                    lootRemove(o, k);
                }
                if (ui.button(ctx, ui.rect(box.x + 396, y, 24, 22), "+", hud.MONO, false, "One more of this item. A container holds eight kinds") and o.nloot < wf.MAX_LOOT) {
                    ed.bank(m);
                    lootAdd(o, k);
                }
            }
            var coin: i32 = @intCast(@min(o.gold, GOLD_LIM));
            if (ui.stepperI(ctx, box.x + DLG_PAD, box.y + box.h - DLG_FOOT - ROW_H - 6, 420, "gold", &coin, GOLD_STEP, 0, GOLD_LIM, "Coin in this container. It goes straight into his purse on opening, and is not one of the eight item kinds")) {
                ed.bank(m);
                o.gold = @intCast(@max(coin, 0));
            }
            if (ui.button(ctx, ui.rect(box.x + DLG_PAD, box.y + box.h - DLG_FOOT, 120, DLG_BTN_H), "Done", hud.MONO, false, "Close it - every change is already applied (Enter)") or confirm) {
                ed.modal = .none;
            }
        },
        .boss => {
            const sPre = bossOp(ed, m) orelse {
                ed.modal = .none;
                return;
            };
            const o = &m.ops[sPre];
            var offer: [NFOE_KIND]wf.FoeKind = undefined;
            var non: usize = 0;
            for (0..NFOE_KIND) |ki| {
                const k: wf.FoeKind = @enumFromInt(ki);
                if (!foemod.isBoss(k) and !o.sealsOn(k)) continue;
                offer[non] = k;
                non += 1;
            }
            const rows: i32 = @intCast(non + 1);
            const box = ui.beginModal(ctx, LIST_W, LOOT_TOP + rows * LOOT_ROW_H + 8 + DLG_FOOT, "Sealed until these die");
            var sb: [96]u8 = undefined;
            hud.mono(
                std.fmt.bufPrintZ(&sb, "He walks through once, then nothing does until all {d} are dead", .{o.nboss}) catch "",
                box.x + DLG_PAD,
                box.y + 58,
                hud.MONO,
                ui.LABEL,
            );
            var i: usize = 0;
            while (i < rows) : (i += 1) {
                const pick: ?wf.FoeKind = if (i == 0) null else offer[i - 1];
                const y = box.y + LOOT_TOP + @as(i32, @intCast(i)) * LOOT_ROW_H;
                const label: [:0]const u8 = if (pick) |k| wf.foeName(k) else "Never shuts";
                const on = if (pick) |k| o.sealsOn(k) else o.nboss == 0;
                hud.mono(label, box.x + DLG_PAD, y + 5, hud.MONO, if (on) ui.VALUE else ui.LABEL);
                if (ui.button(ctx, ui.rect(box.x + 368, y, 52, 22), if (on) "on" else "add", hud.MONO, on, "Name this creature on the gate. It holds while ANY name still stands - a duo is two. The top row empties it back to an ordinary doorway")) {
                    ed.bank(m);
                    if (pick) |k| sealToggle(o, k) else o.nboss = 0;
                }
            }
            if (ui.button(ctx, ui.rect(box.x + DLG_PAD, box.y + box.h - DLG_FOOT, 120, DLG_BTN_H), "Done", hud.MONO, false, "Close it - every change is already applied (Enter)") or confirm) {
                ed.modal = .none;
            }
        },
        .zonemix => {
            const zi = ed.zoneSel orelse {
                ed.modal = .none;
                return;
            };
            if (zi >= m.nzones) {
                ed.modal = .none;
                return;
            }
            const z = &m.zones[zi];
            var shown: [props.FLORA_KINDS.len]Kind = undefined;
            var nshown: usize = 0;
            for (props.FLORA_KINDS) |k| {
                if (props.group(k) != ed.mixTab) continue;
                shown[nshown] = k;
                nshown += 1;
            }
            const rows: i32 = @intCast(@max(nshown, 1));
            const box = ui.beginModal(ctx, LIST_W, LOOT_TOP + MIX_TAB_ROWS * TAB_H + rows * LOOT_ROW_H + 8 + DLG_FOOT, "What grows here");
            var hb: [64]u8 = undefined;
            hud.mono(
                std.fmt.bufPrintZ(&hb, "{s} - {d} / {d} picks", .{ z.label(), z.nmix, wf.MAX_MIX }) catch "",
                box.x + DLG_PAD,
                box.y + 58,
                hud.MONO,
                ui.LABEL,
            );

            const tabW: i32 = @divTrunc(box.w - DLG_PAD * 2 - (MIX_COLS - 1) * 3, MIX_COLS);
            for (MIX_GROUPS, 0..) |g, gi| {
                var carried: u8 = 0;
                for (z.mix[0..z.nmix]) |k| {
                    if (props.group(k) == g) carried += 1;
                }
                var tb: [24]u8 = undefined;
                const lab = if (carried > 0) (std.fmt.bufPrintZ(&tb, "{s} *", .{g.label()}) catch g.label()) else g.label();
                const slot: i32 = @intCast(gi);
                const col = @mod(slot, MIX_COLS);
                const row = @divTrunc(slot, MIX_COLS);
                const r = ui.rect(box.x + DLG_PAD + col * (tabW + 3), box.y + LOOT_TOP + row * TAB_H, tabW, TAB_H - 4);
                if (ui.button(ctx, r, lab, hud.MONO, ed.mixTab == g, "Show this family - a * means the zone already grows one")) ed.mixTab = g;
            }

            const listTop = box.y + LOOT_TOP + MIX_TAB_ROWS * TAB_H;
            for (shown[0..nshown], 0..) |k, i| {
                const y = listTop + @as(i32, @intCast(i)) * LOOT_ROW_H;
                const n = mixCount(z, k);
                hud.mono(props.displayName(k), box.x + DLG_PAD, y + 5, hud.MONO, if (n > 0) ui.VALUE else ui.LABEL);
                var nbuf: [8]u8 = undefined;
                hud.mono(std.fmt.bufPrintZ(&nbuf, "{d}", .{n}) catch "0", box.x + 340, y + 5, hud.MONO, if (n > 0) ui.VALUE else ui.LABEL);
                if (ui.button(ctx, ui.rect(box.x + 368, y, 24, 22), "-", hud.MONO, false, "One fewer share of this plant in the zone's mix") and n > 0) {
                    ed.bank(m);
                    mixRemove(z, k);
                    ed.requestRebuild();
                }
                if (ui.button(ctx, ui.rect(box.x + 396, y, 24, 22), "+", hud.MONO, false, "One more share. The mix is WEIGHTS against each other, not counts") and z.nmix < wf.MAX_MIX) {
                    ed.bank(m);
                    mixAdd(z, k);
                    ed.requestRebuild();
                }
            }
            if (ui.button(ctx, ui.rect(box.x + DLG_PAD, box.y + box.h - DLG_FOOT, 120, DLG_BTN_H), "Done", hud.MONO, false, "Close it - every change is already applied (Enter)") or confirm) {
                ed.modal = .none;
            }
        },
        .script => drawScriptModal(ed, ctx, m, confirm),
        .talk => {
            drawTalkModal(ed, ctx, m);
            if (confirm and ed.modal == .talk) {
                commitTalk(ed, m);
                ed.modal = .none;
            }
        },
        .options => drawOptionsModal(ed, ctx),
        .world => {
            const box = ui.beginModal(ctx, WORLD_W, WORLD_H, "World");
            const x = box.x + DLG_PAD;
            const w = WORLD_W - DLG_PAD * 2;
            var y = box.y + 56;
            var changed = false;
            const before = wf.Runway{ .x = m.runway.x, .z = m.runway.z, .x1 = m.runway.x1, .z1 = m.runway.z1 };
            const halfBefore = m.half;

            hud.mono("SIZE", x, y, hud.MONO, ui.TITLE);
            y += ROW_H + 4;
            changed = ui.stepperF(ctx, x, y, w, "half extent", &m.half, 5, 40, wf.MAX_DECLARED_HALF, "Half the map's width in metres, so 100 is a 200 m square. The play area sits inside it") or changed;
            y += ROW_H;
            var hb: [72]u8 = undefined;
            hud.mono(
                std.fmt.bufPrintZ(&hb, "{d:.0} m across - every scatter re-expands", .{m.half * 2}) catch "",
                x,
                y,
                hud.MONO,
                ui.alpha(ui.LABEL, 170),
            );
            y += ROW_H + 10;

            hud.mono("RUNWAY", x, y, hud.MONO, ui.TITLE);
            y += ROW_H + 4;
            hud.mono("the lane kept clear of anything that avoids it", x, y, hud.MONO, ui.alpha(ui.LABEL, 170));
            y += hud.monoLineH(hud.MONO) + 4;
            changed = ui.stepperF(ctx, x, y, w, "x0", &m.runway.x, 0.5, -COORD_LIM, COORD_LIM, "West edge of the runway - the corridor scatters keep clear of") or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "z0", &m.runway.z, 0.5, -COORD_LIM, COORD_LIM, "South edge of the runway") or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "x1", &m.runway.x1, 0.5, -COORD_LIM, COORD_LIM, "East edge of the runway") or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "z1", &m.runway.z1, 0.5, -COORD_LIM, COORD_LIM, "North edge of the runway") or changed;
            y += ROW_H + 8;
            hud.mono("START", x, y, hud.MONO, ui.TITLE);
            y += ROW_H;
            hud.mono("where the player stands up in a new game", x, y, hud.MONO, ui.alpha(ui.LABEL, 170));
            y += hud.monoLineH(hud.MONO) + 4;
            changed = ui.stepperF(ctx, x, y, w, "start x", &m.start.x, 0.5, -COORD_LIM, COORD_LIM, "Where he stands up, east-west") or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "start z", &m.start.z, 0.5, -COORD_LIM, COORD_LIM, "Where he stands up, north-south") or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "start yaw", &m.start.yaw, 15, -360, 720, "Which way he faces, in degrees. 180 is south, which is what every map used to get") or changed;
            y += ROW_H;
            if (ui.button(ctx, ui.rect(x, y, w, 24), "put it under the cursor", hud.MONO, false, "Take the start from where the mouse is standing in the world")) {
                if (ed.groundAt()) |g2| {
                    m.start.x = g2.x;
                    m.start.z = g2.z;
                    changed = true;
                }
            }
            y += ROW_H + 10;

            hud.mono("LIGHT", x, y, hud.MONO, ui.TITLE);
            y += ROW_H + 4;
            var cb: [10]u8 = undefined;
            var lb: [80]u8 = undefined;
            hud.mono(
                std.fmt.bufPrintZ(&lb, "{s}  {s}", .{
                    daynight.clockTextZ(day.hour, &cb),
                    daynight.phaseName(day.hour),
                }) catch "",
                x,
                y,
                hud.MONO,
                ui.alpha(ui.LABEL, 190),
            );
            y += hud.monoLineH(hud.MONO);
            hud.mono("',' '.' scrub, Shift for hours", x, y, hud.MONO, ui.alpha(ui.LABEL, 190));
            y += hud.monoLineH(hud.MONO) + 4;
            var hourNow = day.hour;
            if (ui.stepperF(ctx, x, y, w, "hour", &hourNow, HOUR_STEP, 0, 24, "The world clock, for looking at your map under a different sun. Not saved with the map")) day.set(hourNow);
            y += ROW_H;
            {
                const cols: i32 = @intCast(HOUR_MARKS.len);
                const bw: i32 = @divTrunc(w - (cols - 1) * 6, cols);
                for (HOUR_MARKS, 0..) |mk, i| {
                    const bx = x + @as(i32, @intCast(i)) * (bw + 6);
                    const on = @abs(day.hour - mk.at) < HOUR_STEP * 0.5;
                    if (ui.button(ctx, ui.rect(bx, y, bw, 24), mk.name, hud.MONO, on, mk.tip)) day.set(mk.at);
                }
                y += ROW_H + 10;
            }

            if (changed) {
                ed.bankWorld(m, halfBefore, before);
                ed.rebuild(m, env);
            } else if (!ctx.down) ed.endGesture();

            if (ui.button(ctx, ui.rect(box.x + DLG_PAD, box.y + box.h - DLG_FOOT, 120, DLG_BTN_H), "Done", hud.MONO, false, "Close it - every change is already applied (Enter)") or confirm) {
                ed.modal = .none;
            }
        },
        .stats => {
            if (!tuneui.panel(&ed.stats, ctx)) ed.modal = .none;
        },
        .jukebox => {
            const box = ui.beginModal(ctx, JUKE_W, JUKE_H, "Sounds");
            if (ui.list(ctx, ui.rect(box.x + 20, box.y + 56, JUKE_LIST_W, JUKE_LIST_H), &VOICE_NAMES, ed.juke, &ed.jukeScroll, "Every voice in the game. Click one to hear it")) |i| {
                ed.juke = i;
                ed.jukePlay();
            }
            const vid: sfx.Id = @enumFromInt(@min(ed.juke, VOICE_NAMES.len - 1));
            const nfo = sfx.voiceInfo(vid);
            const cx = box.x + 40 + JUKE_LIST_W;
            var cy = box.y + 56;
            var buf: [96]u8 = undefined;
            hud.mono(VOICE_NAMES[@min(ed.juke, VOICE_NAMES.len - 1)], cx, cy, hud.MONO, ui.TITLE);
            const edited = sfx.voiceEdited(vid);
            if (edited) hud.mono("EDITED", cx + JUKE_COL_W - 60, cy, hud.MONO, ui.HOT);
            cy += ROW_H + 6;
            inline for (@typeInfo(sfx.Dial).@"enum".fields) |dfld| {
                const d: sfx.Dial = @enumFromInt(dfld.value);
                const spec = sfx.dialSpec(d);
                var v = sfx.dialOf(vid, d);
                if (ui.slider(ctx, cx, cy, JUKE_COL_W, spec.name, &v, spec.lo, spec.hi, spec.tip)) sfx.setDial(vid, d, v);
                cy += RACK_ROW;
            }
            cy += 4;
            const shape = std.fmt.bufPrintZ(&buf, "{d} takes x {d} voices, {s}", .{ nfo.vars, nfo.poly, @tagName(nfo.mix) }) catch "";
            hud.mono(shape, cx, cy, hud.MONO, ui.alpha(ui.LABEL, 170));
            cy += ROW_H + 6;
            _ = ui.checkbox(ctx, cx, cy, "play out in the world", &ed.jukeWorld, "Play it positioned at the focus, with distance and pan, instead of flat in your ear");
            cy += ROW_H;
            const ds = if (ed.jukeWorld)
                (std.fmt.bufPrintZ(&buf, "at the focus, {d:.0} m out - zoom to move it", .{ed.dist}) catch "")
            else
                "at the ear";
            hud.mono(ds, cx, cy, hud.MONO, ui.alpha(ui.LABEL, 170));
            cy += ROW_H + 8;
            if (ui.button(ctx, ui.rect(cx, cy, 150, 22), "Revert voice", hud.MONO, !edited, "Back to the numbers in the code - the originals are never overwritten")) {
                sfx.revertVoice(vid);
                ed.jukePlay();
            }
            if (ui.button(ctx, ui.rect(cx + 158, cy, 130, 22), "Revert all", hud.MONO, !sfx.anyVoiceEdited(), "Every voice in the game back to the code")) sfx.revertAllVoices();
            rackPanel(ed, ctx, box.x + JUKE_W - RACK_W - 20, box.y + 56, vid);

            const by = box.y + box.h - DLG_FOOT;
            if (ui.button(ctx, ui.rect(box.x + 20, by, 150, DLG_BTN_H), "Play again", hud.MONO, false, "Hear the selected voice again (Enter)") or confirm) ed.jukePlay();
            if (ui.button(ctx, ui.rect(box.x + 180, by, 120, DLG_BTN_H), "Save", hud.MONO, false, "Write the edited voices over settings.cfg")) {
                sfx.saveSettings();
                ed.say("sounds saved");
            }
            if (ui.button(ctx, ui.rect(box.x + 310, by, 120, DLG_BTN_H), "Done", hud.MONO, false, "Close the sound bench. Edited voices stay edited until you revert them")) {
                sfx.saveSettings();
                ed.modal = .none;
            }
            hud.mono("up / down step and play, space replays", box.x + 450, by + 6, hud.MONO, ui.alpha(ui.LABEL, 150));
        },
        .new_map, .save_as => {
            const isNew = ed.modal == .new_map;
            const box = ui.beginModal(ctx, 460, 180, if (isNew) "New map" else "Save map as");
            hud.mono("name", box.x + DLG_PAD, box.y + 58, hud.MONO, ui.LABEL);
            _ = ui.textField(ctx, ui.rect(box.x + DLG_PAD, box.y + 82, 412, 30), &ed.nameBuf, &ed.nameLen, KB_FILE_NAME, true, "The file name. It lands in worlds/ with .world on the end");
            var buf: [wf.PATH_CAP]u8 = undefined;
            const p = wf.pathFor(&buf, ed.nameBuf[0..ed.nameLen]);
            var pz: [wf.PATH_CAP + 4]u8 = undefined;
            const ps = std.fmt.bufPrintZ(&pz, "{s}", .{p}) catch "";
            hud.mono(ps, box.x + DLG_PAD, box.y + 118, hud.MONO, ui.alpha(ui.LABEL, 190));
            const by = box.y + box.h - DLG_FOOT;
            const go = ui.button(ctx, ui.rect(box.x + DLG_PAD, by, 130, DLG_BTN_H), if (isNew) "Create" else "Save", hud.MONO, false, "Write it and open it (Enter)");
            if (go or confirm) {
                ed.modal = .none;
                if (isNew) ed.doNew(m, env) else ed.doSaveAs(m);
                return;
            }
            if (ui.button(ctx, ui.rect(box.x + 164, by, 120, DLG_BTN_H), "Cancel", hud.MONO, false, "Close without doing it (Esc)")) ed.modal = .none;
        },
        .open_map => {
            const box = ui.beginModal(ctx, 460, 380, "Open map");
            var labels: [wf.MAX_FILES][:0]const u8 = undefined;
            for (0..listing.n) |i| labels[i] = listing.name(i);
            if (listing.n == 0) {
                hud.mono("no maps in worlds/", box.x + DLG_PAD, box.y + 62, hud.MONO, ui.LABEL);
            } else if (ui.list(ctx, ui.rect(box.x + DLG_PAD, box.y + 54, 412, 258), labels[0..listing.n], ed.fileSel, &ed.fileScroll, "The maps in worlds/. Click one, then Open")) |i| {
                ed.fileSel = i;
            }
            const by = box.y + box.h - DLG_FOOT;
            if ((ui.button(ctx, ui.rect(box.x + DLG_PAD, by, 130, DLG_BTN_H), "Open", hud.MONO, false, "Load this map. Unsaved edits are asked about first (Enter)") or confirm) and listing.n > 0) {
                ed.modal = .none;
                ed.doOpen(m, env, ed.fileSel);
                return;
            }
            if (ui.button(ctx, ui.rect(box.x + 164, by, 120, DLG_BTN_H), "Cancel", hud.MONO, false, "Close without doing it (Esc)")) ed.modal = .none;
        },
        .objects => {
            if (!objview.draw(&ed.objects, env, scene, ctx)) ed.modal = .none;
        },
    }
}

const MenuItem = enum { view, loot, boss, focus, reroll, explode, duplicate, delete, close };

const menuRows = [_]struct { act: MenuItem, label: [:0]const u8, tip: [:0]const u8 }{
    .{ .act = .view, .label = "View...", .tip = "Open this kind alone in the object viewer" },
    .{ .act = .loot, .label = "Items...", .tip = "What this container holds when it is opened" },
    .{ .act = .boss, .label = "Sealed by...", .tip = "Which creatures must die before this gate opens - name every body in the fight" },
    .{ .act = .focus, .label = "Focus", .tip = "Put the camera on it (F)" },
    .{ .act = .reroll, .label = "Re-roll", .tip = "A different arrangement, same meaning (R)" },
    .{ .act = .explode, .label = "Break apart", .tip = "One op per instance, so a single one can be moved or deleted. No way back but undo" },
    .{ .act = .duplicate, .label = "Duplicate", .tip = "A copy beside it, ready to drag" },
    .{ .act = .delete, .label = "Delete", .tip = "Remove it (Del)" },
    .{ .act = .close, .label = "Close", .tip = "Shut this menu (Esc)" },
};

fn menuWhy(act: MenuItem) [:0]const u8 {
    return switch (act) {
        .close => "",
        .focus, .view, .reroll, .duplicate, .delete => "Select an object first",
        .loot => "Select a container - a chest, or something that can hold items",
        .boss => "Select a fog gate",
        .explode => "Select a group op - a belt, a scatter, a ring or a row. A single placement has nothing to break apart",
    };
}

const MENU_W: i32 = 150;
const MENU_EDGE: i32 = 4;


fn lootOp(ed: *const Editor, m: *const wf.Map) ?usize {
    const s = ed.sel orelse return null;
    if (s >= m.nops) return null;
    return if (isContainer(&m.ops[s])) s else null;
}

fn isContainer(o: *const wf.Op) bool {
    return o.op == .at and props.holdsLoot(o.kind);
}

fn unfilledContainer(o: *const wf.Op) bool {
    return isContainer(o) and o.nloot == 0 and o.gold == 0;
}

fn countUnfilled(m: *const wf.Map) usize {
    var n: usize = 0;
    for (m.ops[0..m.nops]) |*o| {
        if (unfilledContainer(o)) n += 1;
    }
    return n;
}

/// MEASURED over the format's 20,480 ops: 78.9 us a frame walked, 0.002 us held. Every container edit banks
/// first, so `miniGen` is an exact stamp.
var unfilledAt: u64 = std.math.maxInt(u64);
var unfilledOps: usize = std.math.maxInt(usize);
var unfilledWas: usize = 0;

fn unfilledCount(ed: *const Editor, m: *const wf.Map) usize {
    if (unfilledAt == ed.miniGen and unfilledOps == m.nops) return unfilledWas;
    unfilledAt = ed.miniGen;
    unfilledOps = m.nops;
    unfilledWas = countUnfilled(m);
    return unfilledWas;
}

fn nextUnfilled(ed: *const Editor, m: *const wf.Map) ?usize {
    if (m.nops == 0) return null;
    const from = if (ed.sel) |s| (s + 1) % m.nops else 0;
    for (0..m.nops) |k| {
        const i = (from + k) % m.nops;
        if (unfilledContainer(&m.ops[i])) return i;
    }
    return null;
}

fn goToUnfilled(ed: *Editor, m: *const wf.Map) void {
    const i = nextUnfilled(ed, m) orelse {
        ed.say("every chest and item on the map holds something");
        return;
    };
    ed.dropSelection();
    ed.setLayer(layerOf(&m.ops[i]));
    ed.selecting = true;
    ed.sel = i;
    ed.focusOn(m, i);
    ed.sayFmt("#{d} {s} - {d} still empty", .{ i, @tagName(m.ops[i].kind), countUnfilled(m) });
}

fn sealToggle(o: anytype, k: wf.FoeKind) void {
    for (o.seal(), 0..) |s, i| {
        if (s != k) continue;
        var j = i;
        while (j + 1 < o.nboss) : (j += 1) o.boss[j] = o.boss[j + 1];
        o.nboss -= 1;
        return;
    }
    if (o.nboss >= wf.MAX_SEAL) return;
    o.boss[o.nboss] = k;
    o.nboss += 1;
}

fn bossOp(ed: *const Editor, m: *const wf.Map) ?usize {
    const s = ed.sel orelse return null;
    if (s >= m.nops) return null;
    return if (m.ops[s].op == .at and props.info(m.ops[s].kind).ward) s else null;
}

fn groupOp(ed: *const Editor, m: *const wf.Map) ?usize {
    const s = ed.sel orelse return null;
    if (s >= m.nops) return null;
    return if (m.ops[s].op == .at) null else s;
}

fn lootCount(o: *const wf.Op, k: item.Kind) u8 {
    var n: u8 = 0;
    for (o.loot[0..o.nloot]) |it| {
        if (it == k) n += 1;
    }
    return n;
}

fn mixCount(z: *const wf.Zone, k: Kind) u8 {
    var n: u8 = 0;
    for (z.mix[0..z.nmix]) |it| {
        if (it == k) n += 1;
    }
    return n;
}

fn mixAdd(z: *wf.Zone, k: Kind) void {
    if (z.nmix >= wf.MAX_MIX) return;
    z.mix[z.nmix] = k;
    z.nmix += 1;
}

fn mixRemove(z: *wf.Zone, k: Kind) void {
    var i: u8 = 0;
    while (i < z.nmix) : (i += 1) {
        if (z.mix[i] != k) continue;
        z.mix[i] = z.mix[z.nmix - 1];
        z.nmix -= 1;
        return;
    }
}

fn lootAdd(o: *wf.Op, k: item.Kind) void {
    if (o.nloot >= wf.MAX_LOOT) return;
    o.loot[o.nloot] = k;
    o.nloot += 1;
}

fn lootRemove(o: *wf.Op, k: item.Kind) void {
    var i: u8 = 0;
    while (i < o.nloot) : (i += 1) {
        if (o.loot[i] != k) continue;
        o.loot[i] = o.loot[o.nloot - 1];
        o.nloot -= 1;
        return;
    }
}

const RACK_W: i32 = 356;
const RACK_GAP: i32 = 14;

const SCRIPT_W: i32 = 780;
const SCRIPT_H: i32 = 610;


const COND_NAMES = blk: {
    var out: [@typeInfo(wf.CondKind).@"enum".fields.len][:0]const u8 = undefined;
    for (&out, 0..) |*o, i| o.* = condName(@enumFromInt(i));
    break :blk out;
};

const ACT_NAMES = blk: {
    var out: [@typeInfo(wf.ActKind).@"enum".fields.len][:0]const u8 = undefined;
    for (&out, 0..) |*o, i| o.* = actName(@enumFromInt(i));
    break :blk out;
};

fn condName(k: wf.CondKind) [:0]const u8 {
    return switch (k) {
        .always => "always",
        .never => "never",
        .flag => "switch",
        .counter => "counter",
        .timer => "timer",
        .elapsed => "seconds elapsed",
        .region => "inside region",
        .near => "near an npc",
        .talked => "has spoken to",
        .deaths => "kind has died",
        .alive => "kind still alive",
    };
}

fn actName(k: wf.ActKind) [:0]const u8 {
    return switch (k) {
        .dialog => "conversation",
        .text => "banner line",
        .flag => "set a switch",
        .counter => "change counter",
        .timer => "start a timer",
        .wait => "wait n seconds",
        .preserve => "may fire again",
        .shop => "open trader",
        .smithy => "open smithy",
    };
}

fn condTip(k: wf.CondKind) [:0]const u8 {
    return switch (k) {
        .always => "Fires every time it is asked",
        .never => "Never fires - the way to park a trigger without deleting it",
        .flag => "A named switch is on or off",
        .counter => "A named counter compares against a number",
        .timer => "A named timer has finished, or is still running",
        .elapsed => "Seconds since the map started",
        .region => "He is standing inside this rectangle",
        .near => "He is within r metres of an NPC",
        .talked => "He has had this conversation",
        .deaths => "How many of a kind have died",
        .alive => "How many of a kind are still standing",
    };
}

fn actTip(k: wf.ActKind) [:0]const u8 {
    return switch (k) {
        .dialog => "Open a conversation",
        .text => "Put one line on the banner",
        .flag => "Set, clear or flip a named switch",
        .counter => "Set, add to or subtract from a named counter",
        .timer => "Start a named timer running for n seconds",
        .wait => "Hold this trigger for n seconds before the next action",
        .preserve => "Run again next time - without this a trigger fires once",
        .shop => "Open the TRADING counter - buy and sell with gold (put this on the caravaneer)",
        .smithy => "Open the SMITHY - stones and gold to put a tier on a weapon (put this on the smith)",
    };
}


const OPT_W: i32 = 420;
const OPT_ROWS: i32 = 4;
const OPT_H: i32 = 56 + OPT_ROWS * (ROW_H + hud.monoLineH(hud.MONO) + 8) + 3 * (ROW_H + 6) + DLG_FOOT;

fn drawOptionsModal(ed: *Editor, ctx: *ui.Ctx) void {
    const box = ui.beginModal(ctx, OPT_W, OPT_H, "Editor Options");
    const x = box.x + DLG_PAD;
    var y = box.y + 56;

    hud.mono("VIEW", x, y, hud.MONO, ui.TITLE);
    y += ROW_H + 4;

    _ = ui.checkbox(ctx, x, y, "distance fog", &ed.showFog, "The clear-air haze the world is sized for. Off, everything out to its view distance draws at full contrast and the far edge of a 560 m map reads as a wall of props");
    y += ROW_H;
    hud.mono("the far falloff - on, and cheaper to look at", x + 24, y, hud.MONO, ui.alpha(ui.LABEL, 160));
    y += hud.monoLineH(hud.MONO) + 8;

    _ = ui.checkbox(ctx, x, y, "weather", &ed.showWeather, "Rain, mist and sporefall. Off on entry: it is the one overlay that hides the ground you came in to sculpt");
    y += ROW_H;
    hud.mono("needs the Locations eye open too", x + 24, y, hud.MONO, ui.alpha(ui.LABEL, 160));
    y += hud.monoLineH(hud.MONO) + 8;

    _ = ui.checkbox(ctx, x, y, "cast shadows", &ed.showShadows, "The sun's own depth pass. Off in here: it draws every caster in the box a second time, and the box opens as you pull back");
    y += ROW_H;
    hud.mono("off - the second pass over every caster", x + 24, y, hud.MONO, ui.alpha(ui.LABEL, 160));
    y += hud.monoLineH(hud.MONO) + 8;

    hud.mono("BRUSH", x, y, hud.MONO, ui.TITLE);
    y += ROW_H + 4;
    _ = ui.checkbox(ctx, x, y, "grid snap", &ed.snap, "Land every placement on the whole metre (G)");
    y += ROW_H;
    hud.mono("G toggles it from the map as well", x + 24, y, hud.MONO, ui.alpha(ui.LABEL, 160));

    if (ui.button(ctx, ui.rect(box.x + box.w - DLG_PAD - 110, box.y + box.h - DLG_FOOT, 110, DLG_BTN_H), "Close", hud.MONO, false, "Back to the map (Esc)")) ed.modal = .none;
}


comptime {
    // `openTalk` copies a node in AT the format's cap and `ui.textField` writes the terminator at `len`, so a
    // buffer merely as wide as the cap is a write one past its end.
    const E = Editor{};
    if (E.talkSay.len <= wf.TALK_SAY_CAP) @compileError("editor: talkSay must be wider than wf.TALK_SAY_CAP");
    if (E.talkWho.len <= wf.TALK_LABEL_CAP) @compileError("editor: talkWho must be wider than wf.TALK_LABEL_CAP");
    if (E.talkRow[0].len <= wf.TALK_LABEL_CAP) @compileError("editor: talkRow must be wider than wf.TALK_LABEL_CAP");
}

fn openTalk(ed: *Editor, m: *wf.Map, rec: usize) void {
    if (rec >= m.nnpcs) return;
    const np = &m.npcs[rec];
    ed.talkNpc = rec;
    ed.talkRows = 0;
    ed.talkSayLen = 0;
    ed.talkWhoLen = 0;
    ed.talkFlat = true;
    const synth = np.dlg != wf.NO_DIALOG and np.dlg < m.ndialogs and m.dialogs[np.dlg].synth;
    ed.talkDlg = if (synth) wf.NO_DIALOG else np.dlg;

    var t = wf.Talk{};
    if (np.dlg == wf.NO_DIALOG) {
        wf.seedTalk(np.kind, &t);
    } else {
        t = wf.readTalk(m, np.dlg) orelse {
            ed.talkFlat = false;
            ed.modal = .talk;
            return;
        };
    }
    ed.talkSayLen = t.line().len;
    @memcpy(ed.talkSay[0..ed.talkSayLen], t.line());
    ed.talkWhoLen = t.speaker().len;
    @memcpy(ed.talkWho[0..ed.talkWhoLen], t.speaker());
    ed.talkRows = t.nrows;
    for (0..t.nrows) |i| {
        ed.talkRowLen[i] = t.rows[i].label().len;
        @memcpy(ed.talkRow[i][0..ed.talkRowLen[i]], t.rows[i].label());
        ed.talkDoes[i] = t.rows[i].does;
    }
    ed.modal = .talk;
}

fn commitTalk(ed: *Editor, m: *wf.Map) void {
    if (!ed.talkFlat) return;
    const rec = ed.talkNpc orelse return;
    if (rec >= m.nnpcs) return;
    const np = &m.npcs[rec];

    var t = wf.Talk{};
    t.setLine(ed.talkSay[0..ed.talkSayLen]);
    t.setSpeaker(ed.talkWho[0..ed.talkWhoLen]);
    for (0..ed.talkRows) |i| {
        if (ed.talkRowLen[i] == 0) continue;
        t.rows[t.nrows] = .{ .does = ed.talkDoes[i] };
        t.rows[t.nrows].setLabel(ed.talkRow[i][0..ed.talkRowLen[i]]);
        t.nrows += 1;
    }

    ed.bank(m);
    if (ed.talkDlg == wf.NO_DIALOG) {
        var nb: [wf.ID_CAP]u8 = undefined;
        const name = wf.freeDialogName(m, &nb, np.kind);
        const di = wf.addTalk(m, name, &t) catch {
            ed.sayFmt("this map already holds {d} conversations", .{wf.MAX_DIALOGS});
            return;
        };
        np.dlgRef = m.addText(name) catch {
            _ = wf.removeDialog(m, di);
            ed.say("the map's text arena is full");
            return;
        };
        np.dlg = di;
        ed.talkDlg = di;
    } else {
        wf.writeTalk(m, ed.talkDlg, &t) catch {
            ed.say("this map has no room left for conversation lines");
            return;
        };
    }
    ed.dirty = true;
    ed.requestFolk();
}

const TALK_W: i32 = 700;
const TALK_ROW_H: i32 = 30;
const DOES_W: i32 = 190;
const TALK_PREVIEW_LINES: usize = 7;

fn talkPreviewSize() i32 {
    const w = TALK_W - DLG_PAD * 2 - 12;
    return @max(10, @min(hud.BODY, @divTrunc(hud.BODY * w, @max(dialogmod.innerWidth(), 1))));
}

fn talkModalH(rows: usize) i32 {
    return DLG_PAD * 2 + 34 + 26 + 32 + 30 + 26 + @as(i32, @intCast(rows + 1)) * TALK_ROW_H + DLG_FOOT + 18 +
        @as(i32, @intCast(TALK_PREVIEW_LINES)) * hud.lineH(talkPreviewSize()) + 20;
}

fn talkNoticeH() i32 {
    return DLG_PAD * 2 + 34 + 26 + ROW_H * 2 + DLG_FOOT;
}

const DOES_NAMES = blk: {
    const n = @typeInfo(wf.Does).@"enum".fields.len;
    var out: [n][:0]const u8 = undefined;
    for (0..n) |i| out[i] = @as(wf.Does, @enumFromInt(i)).label();
    break :blk out;
};

fn drawTalkModal(ed: *Editor, ctx: *ui.Ctx, m: *wf.Map) void {
    const rec = ed.talkNpc orelse {
        ed.modal = .none;
        return;
    };
    if (rec >= m.nnpcs) {
        ed.modal = .none;
        return;
    }
    const np = &m.npcs[rec];
    const box = ui.beginModal(ctx, TALK_W, if (ed.talkFlat) talkModalH(ed.talkRows) else talkNoticeH(), "Conversation");
    const x = box.x + DLG_PAD;
    const w = TALK_W - DLG_PAD * 2;
    var y = box.y + DLG_PAD + 30;

    var head: [96]u8 = undefined;
    const who = std.fmt.bufPrintZ(&head, "#{d} {s} - {s}", .{
        rec,
        wf.npcName(np.kind),
        if (np.dlg < m.ndialogs) m.dialogs[np.dlg].label() else "(new)",
    }) catch "";
    hud.mono(who, x, y, hud.MONO, ui.LABEL);
    if (np.dlg != wf.NO_DIALOG) {
        var users: usize = 0;
        for (m.npcSlice()) |*q| {
            if (q.dlg == np.dlg) users += 1;
        }
        if (users > 1) {
            var sb: [80]u8 = undefined;
            const shared = std.fmt.bufPrintZ(&sb, "{d} bodies share this - editing changes all of them", .{users}) catch "";
            hud.mono(shared, x + w - hud.monoW(shared, hud.MONO), y, hud.MONO, ui.alpha(ui.HOT, 220));
        }
    }
    y += 26;

    if (!ed.talkFlat) {
        hud.mono("This one is a tree with more than one node.", x, y, hud.MONO, ui.VALUE);
        y += ROW_H;
        hud.mono("The panel would flatten it, so it edits in the .world file.", x, y, hud.MONO, ui.alpha(ui.LABEL, 190));
        if (ui.button(ctx, ui.rect(box.x + box.w - DLG_PAD - 110, box.y + box.h - DLG_FOOT, 110, DLG_BTN_H), "Close", hud.MONO, false, "Leave it alone (Esc)")) ed.modal = .none;
        return;
    }

    hud.mono("called", x, y, hud.MONO, ui.LABEL);
    var fb2: [72]u8 = undefined;
    const fallback = std.fmt.bufPrintZ(&fb2, "blank = {s}", .{if (np.call.len > 0) m.spanText(np.call) else wf.npcName(np.kind)}) catch "";
    hud.mono(fallback, x + w - hud.monoW(fallback, hud.MONO), y, hud.MONO, ui.alpha(ui.LABEL, 150));
    y += hud.monoLineH(hud.MONO) + 2;
    _ = ui.textField(ctx, ui.rect(x, y, w, 26), &ed.talkWho, &ed.talkWhoLen, KB_TALK_WHO, true, "The name drawn over the panel. Leave it blank to use the body's own");
    y += 32;

    hud.mono("says", x, y, hud.MONO, ui.LABEL);
    var cb: [32]u8 = undefined;
    const count = std.fmt.bufPrintZ(&cb, "{d}/{d}", .{ ed.talkSayLen, wf.TALK_SAY_CAP }) catch "";
    hud.mono(count, x + w - hud.monoW(count, hud.MONO), y, hud.MONO, ui.alpha(ui.LABEL, 170));
    y += hud.monoLineH(hud.MONO) + 2;
    _ = ui.textField(ctx, ui.rect(x, y, w, 26), &ed.talkSay, &ed.talkSayLen, KB_TALK_SAY, true, "The line this body opens with");
    y += 30;

    {
        const playW = dialogmod.innerWidth();
        var wrapBuf: [wf.TALK_SAY_CAP * 2]u8 = undefined;
        var rows: [TALK_PREVIEW_LINES + 4][:0]const u8 = undefined;
        const lines = hud.wrap(ed.talkSay[0..ed.talkSayLen], hud.BODY, playW, &wrapBuf, &rows);
        const small = talkPreviewSize();
        const step = hud.lineH(small);
        const boxH = @as(i32, @intCast(TALK_PREVIEW_LINES)) * step + 8;
        ui.panel(ctx, ui.rect(x, y, w, boxH), null);
        for (lines, 0..) |ln, li| {
            const over = li >= TALK_PREVIEW_LINES;
            hud.text(ln, x + 6, y + 4 + @as(i32, @intCast(li)) * step, small, if (over) ui.HOT else ui.VALUE);
            if (over) break;
        }
        if (lines.len > TALK_PREVIEW_LINES) {
            var ob: [72]u8 = undefined;
            const over = std.fmt.bufPrintZ(&ob, "{d} lines - the plate shows {d} and drops the rest", .{ lines.len, TALK_PREVIEW_LINES }) catch "";
            hud.mono(over, x + w - hud.monoW(over, hud.MONO) - 6, y - hud.monoLineH(hud.MONO) - 2, hud.MONO, ui.HOT);
        }
        y += boxH + 12;
    }

    hud.mono("and offers", x, y, hud.MONO, ui.LABEL);
    y += hud.monoLineH(hud.MONO) + 4;

    var drop: ?usize = null;
    for (0..ed.talkRows) |i| {
        const ry = y + @as(i32, @intCast(i)) * TALK_ROW_H;
        const labW = w - DOES_W - 34;
        _ = ui.textField(ctx, ui.rect(x, ry, labW, 24), &ed.talkRow[i], &ed.talkRowLen[i], kbTalkRow(i), true, "What the player says");
        if (ui.dropdown(ctx, ui.rect(x + labW + 6, ry + 2, DOES_W, 20), ui.ddId(16, rec, i), &DOES_NAMES, @intFromEnum(ed.talkDoes[i]), "What pressing this line does")) |pick| {
            ed.talkDoes[i] = @enumFromInt(pick);
        }
        if (ui.button(ctx, ui.rect(x + w - 24, ry, 24, 24), "x", hud.MONO, false, "Take this line off")) drop = i;
    }
    if (drop) |d| {
        var k = d;
        while (k + 1 < ed.talkRows) : (k += 1) {
            ed.talkRow[k] = ed.talkRow[k + 1];
            ed.talkRowLen[k] = ed.talkRowLen[k + 1];
            ed.talkDoes[k] = ed.talkDoes[k + 1];
        }
        ed.talkRows -= 1;
        ed.talkRowLen[ed.talkRows] = 0;
        ed.talkDoes[ed.talkRows] = .leave;
    }
    y += @as(i32, @intCast(ed.talkRows)) * TALK_ROW_H;

    if (ed.talkRows < wf.MAX_CHOICES) {
        if (ui.button(ctx, ui.rect(x, y, 110, 24), "+ line", hud.MONO, false, "Offer one more line")) {
            ed.talkRowLen[ed.talkRows] = 0;
            ed.talkDoes[ed.talkRows] = .leave;
            ed.talkRows += 1;
        }
    } else {
        var fb: [56]u8 = undefined;
        const full = std.fmt.bufPrintZ(&fb, "{d} lines is the most a panel offers", .{wf.MAX_CHOICES}) catch "";
        hud.mono(full, x, y + 5, hud.MONO, ui.alpha(ui.LABEL, 160));
    }

    const by = box.y + box.h - DLG_FOOT;
    if (ui.button(ctx, ui.rect(x, by, 120, DLG_BTN_H), "Done", hud.MONO, false, "Write it into the map (Enter)")) {
        commitTalk(ed, m);
        ed.modal = .none;
        return;
    }
    if (ui.button(ctx, ui.rect(x + 134, by, 120, DLG_BTN_H), "Cancel", hud.MONO, false, "Leave the conversation as it was (Esc)")) ed.modal = .none;
}

fn drawScriptModal(ed: *Editor, ctx: *ui.Ctx, m: *wf.Map, confirm: bool) void {
    const box = ui.beginModal(ctx, SCRIPT_W, SCRIPT_H, "Script");
    const x = box.x + DLG_PAD;
    const listW: i32 = 200;
    var y = box.y + DLG_PAD + 26;

    var hb: [48]u8 = undefined;
    hud.mono(std.fmt.bufPrintZ(&hb, "TRIGGERS {d}/{d}", .{ m.ntrigs, wf.MAX_TRIGGERS }) catch "", x, y, hud.MONO, ui.TITLE);
    y += ROW_H + 2;
    if (ui.button(ctx, ui.rect(x, y, listW, 22), "+ new trigger", hud.MONO, false, "Add one. It starts as `always` with no actions, which does nothing until you give it some")) {
        if (m.ntrigs < wf.MAX_TRIGGERS) {
            ed.bank(m);
            var t = wf.Trigger{};
            var nb: [wf.ID_CAP]u8 = undefined;
            const nm = std.fmt.bufPrint(&nb, "trig{d}", .{m.ntrigs + 1}) catch "trig";
            @memcpy(t.id[0..@min(nm.len, wf.ID_CAP)], nm[0..@min(nm.len, wf.ID_CAP)]);
            t.conds[0] = .{ .kind = .always };
            t.nconds = 1;
            t.nacts = 0;
            m.trigs[m.ntrigs] = t;
            m.ntrigs += 1;
            ed.selectTrig(m, m.ntrigs - 1);
            ed.dirty = true;
        } else ed.say("trigger cap reached");
    }
    y += ROW_H + 4;
    for (m.trigs[0..m.ntrigs], 0..) |*t, i| {
        var lb: [40]u8 = undefined;
        const on = ed.trigSel == i;
        const lab = std.fmt.bufPrintZ(&lb, "{s}{s}", .{ t.label(), if (t.wip) " ~" else "" }) catch "?";
        if (ui.button(ctx, ui.rect(x, y, listW, 22), lab, hud.MONO, on, "Select this trigger. A ~ means it is parked")) {
            if (on) ed.trigSel = null else ed.selectTrig(m, i);
        }
        y += ROW_H;
    }

    const rx = x + listW + DLG_PAD;
    const rw = SCRIPT_W - listW - DLG_PAD * 3;
    var ry = box.y + DLG_PAD + 26;
    const ti = ed.trigSel orelse {
        hud.mono("no trigger selected", rx, ry, hud.MONO, ui.LABEL);
        scriptDone(ed, ctx, box, confirm);
        return;
    };
    if (ti >= m.ntrigs) {
        ed.trigSel = null;
        scriptDone(ed, ctx, box, confirm);
        return;
    }
    const t = &m.trigs[ti];

    hud.mono("id", rx, ry, hud.MONO, ui.LABEL);
    ry += hud.monoLineH(hud.MONO) + 2;
    if (nameField(ed, ctx, rx, ry, rw, &ed.trigNameBuf, &ed.trigNameLen, t.label(), KB_TRIG_ID, ed.modal == .script, "What this trigger is called. Spaces and # become _")) |typed| {
        ed.bank(m);
        t.id = [_]u8{0} ** wf.ID_CAP;
        @memcpy(t.id[0..@min(typed.len, wf.ID_CAP)], typed[0..@min(typed.len, wf.ID_CAP)]);
        ed.dirty = true;
    }
    ry += 32;
    var flagW: i32 = 0;
    var chipX = rx;
    if (ui.chip(ctx, chipX, ry, "once", t.once, &flagW, "Fires once and stops. Off, it fires every time its conditions hold")) {
        ed.bank(m);
        t.once = !t.once;
        ed.dirty = true;
    }
    chipX += flagW;
    if (ui.chip(ctx, chipX, ry, "parked", t.wip, &flagW, "Kept in the file and never run")) {
        ed.bank(m);
        t.wip = !t.wip;
        ed.dirty = true;
    }
    ry += ROW_H;
    const priBefore = t.pri;
    if (ui.stepperI(ctx, rx, ry, rw, "priority", &t.pri, 1, -99, 99, "Higher runs first when two are ready on the same frame")) {
        ed.bankGesture(i32, m, &t.pri, priBefore);
    } else if (!ctx.down) ed.endGesture();
    ry += ROW_H + 8;

    var cb: [40]u8 = undefined;
    hud.mono(std.fmt.bufPrintZ(&cb, "WHEN {d}/{d}", .{ t.nconds, wf.MAX_CONDS }) catch "", rx, ry, hud.MONO, ui.TITLE);
    if (ui.button(ctx, ui.rect(rx + rw - 28, ry - 2, 28, 20), "+", hud.MONO, false, "Add a condition. Every one of them has to hold")) {
        if (t.nconds < wf.MAX_CONDS) {
            ed.bank(m);
            t.conds[t.nconds] = .{ .kind = .always };
            t.nconds += 1;
            ed.dirty = true;
        }
    }
    ry += ROW_H;
    var ci: usize = 0;
    while (ci < t.nconds) {
        const c = &t.conds[ci];
        if (ui.dropdown(ctx, ui.rect(rx, ry, 148, 20), ui.ddId(1, ed.trigSel orelse 0, ci), &COND_NAMES, @intFromEnum(c.kind), condTip(c.kind))) |pick| {
            ed.bank(m);
            c.kind = @enumFromInt(pick);
            ed.dirty = true;
        }
        if (condFields(ed, ctx, m, c, rx + 154, ry, rw - 154 - 26)) ed.dirty = true;
        if (ui.button(ctx, ui.rect(rx + rw - 22, ry, 22, 20), "x", hud.MONO, false, "Remove this condition")) {
            ed.bank(m);
            std.mem.copyForwards(wf.Cond, t.conds[ci .. t.nconds - 1], t.conds[ci + 1 .. t.nconds]);
            t.nconds -= 1;
            ed.dirty = true;
            continue;
        }
        ry += ROW_H;
        ci += 1;
    }
    ry += 8;

    var ab: [40]u8 = undefined;
    hud.mono(std.fmt.bufPrintZ(&ab, "DO {d}/{d}", .{ t.nacts, wf.MAX_ACTS }) catch "", rx, ry, hud.MONO, ui.TITLE);
    if (ui.button(ctx, ui.rect(rx + rw - 28, ry - 2, 28, 20), "+", hud.MONO, false, "Add an action. They run in order")) {
        if (t.nacts < wf.MAX_ACTS) {
            ed.bank(m);
            t.acts[t.nacts] = .{ .kind = .preserve };
            t.nacts += 1;
            ed.dirty = true;
        }
    }
    ry += ROW_H;
    var an: usize = 0;
    while (an < t.nacts) {
        const a = &t.acts[an];
        if (ui.dropdown(ctx, ui.rect(rx, ry, 148, 20), ui.ddId(2, ed.trigSel orelse 0, an), &ACT_NAMES, @intFromEnum(a.kind), actTip(a.kind))) |pick| {
            ed.bank(m);
            a.kind = @enumFromInt(pick);
            ed.dirty = true;
        }
        if (actFields(ed, ctx, m, a, rx + 154, ry, rw - 154 - 26)) ed.dirty = true;
        const tall = a.kind == .text;
        if (ui.button(ctx, ui.rect(rx + rw - 22, ry, 22, 20), "x", hud.MONO, false, "Remove this action")) {
            ed.bank(m);
            std.mem.copyForwards(wf.Act, t.acts[an .. t.nacts - 1], t.acts[an + 1 .. t.nacts]);
            t.nacts -= 1;
            ed.dirty = true;
            continue;
        }
        ry += if (tall) ROW_H + 26 else ROW_H;
        an += 1;
    }
    ry += 8;

    if (t.nacts == 0) {
        hud.mono("no actions - this does nothing", rx, ry, hud.MONO, ui.HOT);
        ry += ROW_H;
    }
    if (ui.button(ctx, ui.rect(rx, ry, 140, 22), "delete trigger", hud.MONO, false, "Throw this trigger away")) {
        ed.bank(m);
        std.mem.copyForwards(wf.Trigger, m.trigs[ti .. m.ntrigs - 1], m.trigs[ti + 1 .. m.ntrigs]);
        m.ntrigs -= 1;
        ed.trigSel = null;
        ed.dirty = true;
    }
    scriptDone(ed, ctx, box, confirm);
}

fn scriptDone(ed: *Editor, ctx: *ui.Ctx, box: ui.ModalBox, confirm: bool) void {
    if (ui.button(ctx, ui.rect(box.x + DLG_PAD, box.y + box.h - DLG_FOOT, 120, DLG_BTN_H), "Done", hud.MONO, false, "Close it - every change is already applied (Enter)") or confirm) {
        ed.modal = .none;
        ed.textFocus = false;
    }
}

fn slotRow(ed: *Editor, ctx: *ui.Ctx, m: *wf.Map, slot: *u16, table: []const wf.Id, n: usize, x: i32, y: i32, w: i32, comptime what: []const u8) bool {
    const shown = @min(n, MAX_SLOT_ROWS);
    var labels: [MAX_SLOT_ROWS + 1][:0]const u8 = undefined;
    for (0..shown) |i| {
        const txt = wf.idText(&table[i]);
        const cap = @min(txt.len, wf.ID_CAP - 1);
        @memcpy(ed.slotLabels[i][0..cap], txt[0..cap]);
        ed.slotLabels[i][cap] = 0;
        labels[i] = ed.slotLabels[i][0..cap :0];
    }
    labels[shown] = "new " ++ what ++ "...";
    const tag: u8 = if (comptime std.mem.eql(u8, what, "flag")) 3 else if (comptime std.mem.eql(u8, what, "counter")) 4 else 5;
    const sel: usize = if (slot.* < shown) slot.* else shown;
    const pick = ui.dropdown(ctx, ui.rect(x, y, @min(w, 132), 20), ui.ddId(tag, ed.trigSel orelse 0, @intFromPtr(slot) & 0xfff), labels[0 .. shown + 1], sel, "Pick one of the " ++ what ++ "s this map declares, or coin a new one") orelse return false;
    ed.bank(m);
    if (pick >= shown) {
        slot.* = coinName(ed, m, what) orelse return false;
        return true;
    }
    slot.* = @intCast(pick);
    return true;
}

fn coinName(ed: *Editor, m: *wf.Map, comptime what: []const u8) ?u16 {
    var nb: [wf.ID_CAP]u8 = undefined;
    var i: usize = 1;
    while (i < 100) : (i += 1) {
        const nm = std.fmt.bufPrint(&nb, what ++ "{d}", .{i}) catch return null;
        const got = (if (comptime std.mem.eql(u8, what, "flag"))
            m.internFlag(nm)
        else if (comptime std.mem.eql(u8, what, "counter"))
            m.internCounter(nm)
        else
            m.internTimer(nm)) catch {
            ed.say("the map's " ++ what ++ " table is full");
            return null;
        };
        ed.dirty = true;
        ed.sayFmt("+{s}", .{nm});
        return got;
    }
    return null;
}

const ON_OFF_NAMES = [_][:0]const u8{ "is off", "is on" };
const TIMER_NAMES = [_][:0]const u8{ "is running", "has finished" };

fn npcRow(ed: *Editor, ctx: *ui.Ctx, m: *wf.Map, slot: *u16, x: i32, y: i32, w: i32) bool {
    if (m.nnpcs == 0) {
        hud.mono("no folk on this map", x, y + 3, hud.MONO, ui.alpha(ui.LABEL, 160));
        return false;
    }
    const shown = @min(m.nnpcs, MAX_SLOT_ROWS);
    var labels: [MAX_SLOT_ROWS][:0]const u8 = undefined;
    for (0..shown) |i| {
        const nm = wf.npcName(m.npcs[i].kind);
        const txt = std.fmt.bufPrint(&ed.slotLabels[i], "{d} {s}", .{ i, nm }) catch nm;
        const cap = @min(txt.len, wf.ID_CAP - 1);
        ed.slotLabels[i][cap] = 0;
        labels[i] = ed.slotLabels[i][0..cap :0];
    }
    const sel: usize = @min(slot.*, shown - 1);
    const pick = ui.dropdown(ctx, ui.rect(x, y, w, 20), ui.ddId(14, ed.trigSel orelse 0, @intFromPtr(slot) & 0xfff), labels[0..shown], sel, "Which body he has to come near") orelse return false;
    ed.bank(m);
    slot.* = @intCast(pick);
    return true;
}

const COUNTOP_NAMES = blk: {
    var out: [@typeInfo(wf.Countop).@"enum".fields.len][:0]const u8 = undefined;
    for (&out, 0..) |*o, i| {
        const c: wf.Countop = @enumFromInt(i);
        o.* = switch (c) {
            .set => "set to",
            .add => "add",
            .sub => "take",
        };
    }
    break :blk out;
};

const SETOP_NAMES = blk: {
    var out: [@typeInfo(wf.Setop).@"enum".fields.len][:0]const u8 = undefined;
    for (&out, 0..) |*o, i| {
        const c: wf.Setop = @enumFromInt(i);
        o.* = switch (c) {
            .off => "clear it",
            .on => "set it",
            .flip => "flip it",
        };
    }
    break :blk out;
};

const CMP_NAMES = blk: {
    var out: [@typeInfo(wf.Cmp).@"enum".fields.len][:0]const u8 = undefined;
    for (&out, 0..) |*o, i| {
        const c: wf.Cmp = @enumFromInt(i);
        o.* = switch (c) {
            .lt => "is under",
            .le => "is at most",
            .eq => "is exactly",
            .ge => "is at least",
            .gt => "is over",
        };
    }
    break :blk out;
};

fn cmpRow(ed: *Editor, ctx: *ui.Ctx, m: *wf.Map, cmp: *wf.Cmp, x: i32, y: i32) bool {
    const pick = ui.dropdown(ctx, ui.rect(x, y, 96, 20), ui.ddId(6, ed.trigSel orelse 0, @intFromPtr(cmp) & 0xfff), &CMP_NAMES, @intFromEnum(cmp.*), "How the two are compared") orelse return false;
    ed.bank(m);
    cmp.* = @enumFromInt(pick);
    return true;
}

fn foeRow(ed: *Editor, ctx: *ui.Ctx, m: *wf.Map, k: *wf.FoeKind, x: i32, y: i32, w: i32) bool {
    const pick = ui.dropdown(ctx, ui.rect(x, y, @min(w, 176), 20), ui.ddId(7, ed.trigSel orelse 0, @intFromPtr(k) & 0xfff), &unitBrushes, @intFromEnum(k.*), "Which creature this counts") orelse return false;
    ed.bank(m);
    if (pick < NFOE_KIND) {
        k.* = @enumFromInt(pick);
        return true;
    }
    return false;
}

fn dialogRow(ed: *Editor, ctx: *ui.Ctx, m: *wf.Map, span: *wf.Span, x: i32, y: i32, w: i32, tag: u8) bool {
    if (m.ndialogs == 0) {
        hud.mono("no conversations in this map", x, y + 3, hud.MONO, ui.alpha(ui.LABEL, 160));
        return false;
    }
    const shown = @min(m.ndialogs, MAX_SLOT_ROWS);
    var labels: [MAX_SLOT_ROWS][:0]const u8 = undefined;
    const txt = m.spanText(span.*);
    var sel: usize = 0;
    for (0..shown) |i| {
        const lbl = m.dialogs[i].label();
        const cap = @min(lbl.len, wf.ID_CAP - 1);
        @memcpy(ed.slotLabels[i][0..cap], lbl[0..cap]);
        ed.slotLabels[i][cap] = 0;
        labels[i] = ed.slotLabels[i][0..cap :0];
        if (std.mem.eql(u8, lbl, txt)) sel = i;
    }
    const pick = ui.dropdown(ctx, ui.rect(x, y, @min(w, 200), 20), ui.ddId(tag, ed.trigSel orelse 0, @intFromPtr(span) & 0xfff), labels[0..shown], sel, "Pick one of the conversations this map declares") orelse return false;
    ed.bank(m);
    span.* = m.addText(m.dialogs[pick].label()) catch {
        ed.say("the map's text arena is full");
        return false;
    };
    return true;
}

fn condFields(ed: *Editor, ctx: *ui.Ctx, m: *wf.Map, c: *wf.Cond, x: i32, y: i32, w: i32) bool {
    var hit = false;
    switch (c.kind) {
        .always, .never => hud.mono("-", x, y + 3, hud.MONO, ui.alpha(ui.LABEL, 140)),
        .flag => {
            hit = slotRow(ed, ctx, m, &c.slot, &m.flagNames, m.nflags, x, y, w - 60, "flag") or hit;
            if (ui.dropdown(ctx, ui.rect(x + 138, y, 74, 20), ui.ddId(12, ed.trigSel orelse 0, @intFromPtr(c) & 0xfff), &ON_OFF_NAMES, @intFromBool(c.on), "Which way the switch has to be")) |pick| {
                ed.bank(m);
                c.on = pick == 1;
                hit = true;
            }
        },
        .counter => {
            hit = slotRow(ed, ctx, m, &c.slot, &m.counterNames, m.ncounters, x, y, w - 110, "counter") or hit;
            hit = cmpRow(ed, ctx, m, &c.cmp, x + 124, y) or hit;
            hit = ui.stepperI(ctx, x + 168, y, @max(w - 172, STEP_MIN_W), "", &c.n, 1, -9999, 9999, "The number it is compared against") or hit;
        },
        .timer => {
            hit = slotRow(ed, ctx, m, &c.slot, &m.timerNames, m.ntimers, x, y, w - 60, "timer") or hit;
            if (ui.dropdown(ctx, ui.rect(x + 138, y, 88, 20), ui.ddId(13, ed.trigSel orelse 0, @intFromPtr(c) & 0xfff), &TIMER_NAMES, @intFromBool(c.on), "Whether it has finished or is still counting")) |pick| {
                ed.bank(m);
                c.on = pick == 1;
                hit = true;
            }
        },
        .elapsed => {
            hit = cmpRow(ed, ctx, m, &c.cmp, x, y) or hit;
            hit = ui.stepperF(ctx, x + 46, y, @max(w - 50, STEP_MIN_W), "s", &c.r, 1, 0, 36000, "Seconds since the map started") or hit;
        },
        .region => {
            var rb: [48]u8 = undefined;
            hud.mono(std.fmt.bufPrintZ(&rb, "{d:.0},{d:.0} to {d:.0},{d:.0}", .{ c.x, c.z, c.x1, c.z1 }) catch "", x, y + 3, hud.MONO, ui.alpha(ui.LABEL, 200));
            if (ui.button(ctx, ui.rect(x + w - 76, y, 76, 20), "from loc", hud.MONO, false, "Take the rectangle from the selected Location, so the two cannot drift apart")) {
                if (ed.locSel) |li| {
                    if (li < m.nlocations) {
                        ed.bank(m);
                        const l = m.locations[li];
                        c.x = l.x;
                        c.z = l.z;
                        c.x1 = l.x1;
                        c.z1 = l.z1;
                        hit = true;
                    }
                } else ed.say("select a Location first");
            }
        },
        .near => {
            hit = npcRow(ed, ctx, m, &c.slot, x, y, 150) or hit;
            hit = ui.stepperF(ctx, x + 156, y, @max(w - 160, STEP_MIN_W), "r", &c.r, 0.5, 0.5, 200, "How near he has to come, in metres") or hit;
        },
        .talked => hit = dialogRow(ed, ctx, m, &c.ref, x, y, w, 11) or hit,
        .deaths, .alive => {
            hit = foeRow(ed, ctx, m, &c.foe, x, y, w - 120) or hit;
            hit = cmpRow(ed, ctx, m, &c.cmp, x + 154, y) or hit;
            hit = ui.stepperI(ctx, x + 198, y, @max(w - 202, STEP_MIN_W), "", &c.n, 1, 0, 9999, "How many") or hit;
        },
    }
    return hit;
}

fn actFields(ed: *Editor, ctx: *ui.Ctx, m: *wf.Map, a: *wf.Act, x: i32, y: i32, w: i32) bool {
    var hit = false;
    switch (a.kind) {
        .preserve, .shop, .smithy => hud.mono("-", x, y + 3, hud.MONO, ui.alpha(ui.LABEL, 140)),
        .dialog => hit = dialogRow(ed, ctx, m, &a.ref, x, y, w, 8) or hit,
        .text => {
            const txt = m.spanText(a.line);
            var tb: [64]u8 = undefined;
            hud.mono(std.fmt.bufPrintZ(&tb, "{s}", .{if (txt.len > 0) txt else "(empty banner)"}) catch "", x, y + 3, hud.MONO, ui.alpha(ui.LABEL, 200));
            _ = ui.textField(ctx, ui.rect(x, y + 22, @max(w - 60, 90), 24), &ed.lineBuf, &ed.lineLen, ui.ddId(KB_TAG, 6, @intFromPtr(a) & 0xfff), true, "Type a REPLACEMENT line here, then press set. The line it carries now is shown above");
            if (ui.button(ctx, ui.rect(x + @max(w - 56, 94), y + 22, 56, 24), "set", hud.MONO, false, "Write it into the map")) {
                ed.bank(m);
                a.line = m.addText(ed.lineBuf[0..ed.lineLen]) catch blk: {
                    ed.say("the map's text arena is full");
                    break :blk a.line;
                };
                hit = true;
            }
        },
        .flag => {
            hit = slotRow(ed, ctx, m, &a.slot, &m.flagNames, m.nflags, x, y, w - 80, "flag") or hit;
            var sw: i32 = 0;
            _ = &sw;
            if (ui.dropdown(ctx, ui.rect(x + 138, y, 78, 20), ui.ddId(10, ed.trigSel orelse 0, @intFromPtr(a) & 0xfff), &SETOP_NAMES, @intFromEnum(a.setop), "Set it, clear it, or flip whatever it was")) |pick| {
                ed.bank(m);
                a.setop = @enumFromInt(pick);
                hit = true;
            }
        },
        .counter => {
            hit = slotRow(ed, ctx, m, &a.slot, &m.counterNames, m.ncounters, x, y, w - 120, "counter") or hit;
            var sw: i32 = 0;
            _ = &sw;
            if (ui.dropdown(ctx, ui.rect(x + 138, y, 74, 20), ui.ddId(9, ed.trigSel orelse 0, @intFromPtr(a) & 0xfff), &COUNTOP_NAMES, @intFromEnum(a.countop), "Set it, add to it, or take from it")) |pick| {
                ed.bank(m);
                a.countop = @enumFromInt(pick);
                hit = true;
            }
            hit = ui.stepperI(ctx, x + 218, y, @max(w - 222, STEP_MIN_W), "", &a.n, 1, -9999, 9999, "By how much") or hit;
        },
        .timer => {
            hit = slotRow(ed, ctx, m, &a.slot, &m.timerNames, m.ntimers, x, y, w - 100, "timer") or hit;
            hit = ui.stepperF(ctx, x + 124, y, @max(w - 128, STEP_MIN_W), "s", &a.v, 0.5, 0, 3600, "How long it runs for, in seconds") or hit;
        },
        .wait => {
            hit = ui.stepperF(ctx, x, y, @max(@min(w, 140), STEP_MIN_W), "s", &a.v, 0.25, 0, 600, "Seconds held before the next action") or hit;
        },
    }
    return hit;
}

const WORLD_W: i32 = 420;
const WORLD_H: i32 = 56 + 16 * ROW_H + 4 * hud.monoLineH(hud.MONO) + 62 + DLG_FOOT;

const HOUR_STEP: f32 = 0.25;
/// THE HOURS WORTH AUTHORING AT. The anchor is not negotiable — every albedo in the game was measured under it.
const HourMark = struct { name: [:0]const u8, at: f32, tip: [:0]const u8 };
const HOUR_MARKS = [_]HourMark{
    .{ .name = "Dawn", .at = 6.5, .tip = "First light - the coldest key in the day" },
    .{ .name = "Noon", .at = 12.0, .tip = "Overhead and white: the hour with no long shadows to hide a gap" },
    .{ .name = "Anchor", .at = daynight.SHOT_HOUR, .tip = "The golden hour every albedo in the game was measured under (--shot pins it)" },
    .{ .name = "Night", .at = 0.5, .tip = "Moonlight - what the fires have to carry" },
};

fn rackPanel(ed: *Editor, ctx: *ui.Ctx, x: i32, y0: i32, voice: ?sfx.Id) void {
    var y = y0;
    hud.mono("FILTER RACK", x, y, hud.MONO, ui.TITLE);
    y += ROW_H + 4;

    var cx = x;
    inline for (@typeInfo(sfx.Submix).@"enum".fields) |fld| {
        const mx: sfx.Submix = @enumFromInt(fld.value);
        var usedW: i32 = 0;
        if (ui.chip(ctx, cx, y, @tagName(mx), !ed.rackOnVoice and ed.rackMix == mx, &usedW, "Filter this whole family of sounds. The same three families as the game's own volume sliders")) {
            ed.rackMix = mx;
            ed.rackOnVoice = false;
        }
        cx += usedW;
    }
    if (voice != null) {
        var usedW: i32 = 0;
        if (ui.chip(ctx, cx, y, "this voice", ed.rackOnVoice, &usedW, "Filter only the selected voice, on TOP of whatever its family is already doing")) ed.rackOnVoice = true;
    } else ed.rackOnVoice = false;
    y += ROW_H + 8;

    const onVoice = ed.rackOnVoice and voice != null;
    const vid = voice orelse sfx.Id.menu_move;
    const colW = (RACK_W - RACK_GAP) / 2;
    const perCol = (sfx.AFX_COUNT + 1) / 2;
    const vals = if (onVoice) sfx.voiceFxValues(vid) else sfx.fxValues(ed.rackMix);
    for (0..sfx.AFX_COUNT) |i| {
        var v = vals[i];
        const lab = sfx.AFX_NAMES[i];
        const cxx = x + @as(i32, @intCast(i / perCol)) * (colW + RACK_GAP);
        const cyy = y + @as(i32, @intCast(i % perCol)) * RACK_ROW;
        if (ui.slider(ctx, cxx, cyy, colW, lab, &v, 0, 1, sfx.AFX_TIPS[i])) {
            if (onVoice) sfx.setVoiceFx(vid, i, v) else sfx.setFx(ed.rackMix, i, v);
        }
    }
    y += @as(i32, @intCast(perCol)) * RACK_ROW + 6;
    const PRESETS = [_]struct { n: [:0]const u8, p: []const sfx.FxPreset }{
        .{ .n = "Vinyl", .p = &sfx.FX_VINYL },
        .{ .n = "AM Radio", .p = &sfx.FX_RADIO },
        .{ .n = "Worn Tape", .p = &sfx.FX_TAPE },
        .{ .n = "Crushed", .p = &sfx.FX_CRUSHED },
        .{ .n = "Broken", .p = &sfx.FX_BROKEN },
    };
    inline for (PRESETS, 0..) |pre, i| {
        const bx = x + @as(i32, @intCast(i % 2)) * (RACK_W / 2 + 4);
        const by = y + @as(i32, @intCast(i / 2)) * 26;
        if (ui.button(ctx, ui.rect(bx, by, RACK_W / 2 - 4, 22), pre.n, hud.MONO, false, "Load this preset into the rack, over whatever is set now")) {
            if (onVoice) sfx.applyVoiceFxPreset(vid, pre.p) else sfx.applyFxPreset(ed.rackMix, pre.p);
        }
    }
    y += 26 * 3 + 4;
    const dflt: [:0]const u8 = if (onVoice)
        "This voice adds nothing of its own - the family's rack still applies"
    else
        "Back to the house sound (worn tape)";
    if (ui.button(ctx, ui.rect(x, y, RACK_W / 2 - 4, 22), "Default", hud.MONO, false, dflt)) {
        if (onVoice) sfx.voiceFxOff(vid) else sfx.resetFx(ed.rackMix);
    }
    if (ui.button(ctx, ui.rect(x + RACK_W / 2 + 4, y, RACK_W / 2 - 4, 22), "All Off", hud.MONO, false, "Every dial to zero - drier than the game ships")) {
        if (onVoice) sfx.voiceFxOff(vid) else sfx.allFxOff(ed.rackMix);
    }
    y += ROW_H + 4;
    hud.mono(
        if (sfx.fxPending()) "re-rendering..." else if (onVoice) "baked, not mixed - a dial re-renders this voice" else "baked, not mixed - a dial re-renders the family",
        x,
        y,
        hud.MONO,
        ui.alpha(ui.LABEL, if (sfx.fxPending()) 220 else 150),
    );
}

/// A slider is a label line plus a 12 px bar plus its seat: at 30 the bars sat on the next label.
const RACK_ROW: i32 = ui.ROW_H + 14;

fn menuEnabled(ed: *const Editor, m: *const wf.Map, act: MenuItem) bool {
    const op: ?usize = if (ed.sel) |s| (if (s < m.nops) s else null) else null;
    return switch (act) {
        .close => true,
        .focus => op != null,
        .view => op != null,
        .loot => lootOp(ed, m) != null,
        .boss => bossOp(ed, m) != null,
        .reroll, .duplicate => op != null,
        .explode => groupOp(ed, m) != null,
        .delete => op != null or (ed.layer == .units and ed.selUnit != null),
    };
}

fn viewLabel(ed: *const Editor, m: *const wf.Map, buf: []u8) [:0]const u8 {
    const s = ed.sel orelse return "View...";
    if (s >= m.nops) return "View...";
    return std.fmt.bufPrintZ(buf, "View {s}...", .{props.displayName(m.ops[s].kind)}) catch "View...";
}

fn drawContextMenu(ed: *Editor, m: *wf.Map, env: *envmod.Env, ctx: *ui.Ctx) void {
    const menuH: i32 = ROW_H * @as(i32, @intCast(menuRows.len)) + 6;
    var lbuf: [64]u8 = undefined;
    const viewRow = viewLabel(ed, m, &lbuf);
    var menuW: i32 = MENU_W;
    for (menuRows) |row| {
        const label = if (row.act == .view) viewRow else row.label;
        menuW = @max(menuW, hud.monoW(label, hud.MONO) + 26);
    }
    const x: i32 = @intFromFloat(@min(ed.menuAt.x, @as(f32, @floatFromInt(rl.getScreenWidth() - menuW - MENU_EDGE))));
    const y: i32 = @intFromFloat(@min(ed.menuAt.y, @as(f32, @floatFromInt(rl.getScreenHeight() - menuH - MENU_EDGE))));
    const box = ui.rect(x, y, menuW, menuH);
    ui.panel(ctx, box, null);
    for (menuRows, 0..) |row, i| {
        const label = if (row.act == .view) viewRow else row.label;
        const r = ui.rect(x + 3, y + 3 + @as(i32, @intCast(i)) * ROW_H, menuW - 6, ROW_H - 2);
        if (!menuEnabled(ed, m, row.act)) {
            ui.disabled(ctx, r, label, hud.MONO, menuWhy(row.act));
            continue;
        }
        if (!ui.button(ctx, r, label, hud.MONO, false, row.tip)) continue;
        ed.menuOpen = false;
        switch (row.act) {
            .view => if (ed.sel) |s| {
                if (s < m.nops) {
                    ed.objects.show(m.ops[s].kind);
                    ed.modal = .objects;
                }
            },
            .loot => ed.modal = .loot,
            .boss => ed.modal = .boss,
            .focus => if (ed.sel) |s| ed.focusOn(m, s),
            .reroll => ed.rerollSel(m, env),
            .explode => ed.explodeSel(m, env),
            .duplicate => ed.duplicateSel(m, env),
            .delete => ed.deleteSel(m, env),
            .close => {},
        }
        return;
    }
    if (ctx.pressed and !rl.checkCollisionPointRec(ctx.mouse, box)) ed.menuOpen = false;
}


fn testEnv(alloc: std.mem.Allocator) !*envmod.Env {
    const e = try alloc.create(envmod.Env);
    e.* = .{ .ground = undefined, .models = undefined };
    return e;
}

test "a held eraser sweeps, and holding still erases exactly once" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    const env = try testEnv(std.testing.allocator);
    defer std.testing.allocator.destroy(env);
    m.blank("erase");
    for (0..4) |i| {
        m.foes[i] = .{ .kind = .toad, .x = @as(f32, @floatFromInt(i)) * 4.0, .z = 0 };
    }
    m.nfoes = 4;

    var ed = Editor{};
    ed.layer = .units;
    ed.radius = 1.5; // smaller than the 4 m spacing, so one brush covers one spawn
    undoReset();

    ed.wipeStep(m, env, v3(0, 0, 0));
    try std.testing.expectEqual(@as(usize, 3), m.nfoes);
    for (0..30) |_| {
        ed.wipe.t = 1.0;
        ed.wipeStep(m, env, v3(0, 0, 0));
    }
    try std.testing.expectEqual(@as(usize, 3), m.nfoes);

    for ([_]f32{ 4, 8, 12 }) |x| {
        ed.wipe.t = 1.0;
        ed.wipeStep(m, env, v3(x, 0, 0));
    }
    try std.testing.expectEqual(@as(usize, 0), m.nfoes);

    try std.testing.expectEqual(@as(usize, 1), undoN);
    ed.wipeEnd();
    try std.testing.expect(ed.undo(m));
    try std.testing.expectEqual(@as(usize, 4), m.nfoes);
}

test "the rate gate paces a sweep, and an empty sweep costs no undo step" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    const env = try testEnv(std.testing.allocator);
    defer std.testing.allocator.destroy(env);
    m.blank("erase");
    m.foes[0] = .{ .kind = .toad, .x = 0, .z = 0 };
    m.foes[1] = .{ .kind = .toad, .x = 6, .z = 0 };
    m.nfoes = 2;

    var ed = Editor{};
    ed.layer = .units;
    ed.radius = 1.5;
    undoReset();

    ed.wipeStep(m, env, v3(0, 0, 0));
    try std.testing.expectEqual(@as(usize, 1), m.nfoes);
    ed.wipe.t = 0;
    ed.wipeStep(m, env, v3(6, 0, 0));
    try std.testing.expectEqual(@as(usize, 1), m.nfoes);
    ed.wipe.t = 1.0 / ERASE_HZ;
    ed.wipeStep(m, env, v3(6, 0, 0));
    try std.testing.expectEqual(@as(usize, 0), m.nfoes);

    undoReset();
    var idle = Editor{};
    idle.layer = .units;
    idle.radius = 1.5;
    idle.wipeStep(m, env, v3(200, 0, 200));
    idle.wipe.t = 1.0;
    idle.wipeStep(m, env, v3(240, 0, 240));
    try std.testing.expectEqual(@as(usize, 0), undoN);
    try std.testing.expect(!idle.dirty);
}


test "THE UNITS PALETTE SPLITS AT `NFOE_KIND` — a creature on one side, a body that talks on the other" {
    try std.testing.expectEqual(unitBrushes.len, NFOE_KIND + NNPC_KIND + 1);
    try std.testing.expectEqualStrings(wf.foeName(@enumFromInt(0)), unitBrushes[0]);
    try std.testing.expectEqualStrings(wf.foeName(@enumFromInt(NFOE_KIND - 1)), unitBrushes[NFOE_KIND - 1]);
    try std.testing.expectEqualStrings(wf.npcName(.wanderer), unitBrushes[NFOE_KIND]);
    try std.testing.expectEqualStrings(wf.npcName(.merchant), unitBrushes[NFOE_KIND + 1]);
    try std.testing.expectEqualStrings("Erase", unitBrushes[unitBrushes.len - 1]);
}

test "EVERY UNIT IS REACHABLE FROM EXACTLY ONE TAB, and the tallest list now fits the panel" {
    var ed = Editor{};
    ed.layer = .units;
    var buf: [MAX_BRUSHES]usize = undefined;

    var reach = [_]usize{0} ** unitBrushes.len;
    var tallest: usize = 0;
    for (0..UnitTab.N) |t| {
        ed.unitTab = @enumFromInt(t);
        for (0..props.Biome.N) |b| {
            if (ed.unitTab == .foes and !foeBiomes[b]) continue;
            ed.foeBiome = @enumFromInt(b);
            const shown = visibleBrushes(&ed, &buf);
            for (shown) |i| reach[i] += 1;
            tallest = @max(tallest, shown.len);
            try std.testing.expectEqual(unitBrushes.len - 1, shown[shown.len - 1]);
            if (ed.unitTab == .folk) break;
        }
    }
    const kingdoms = blk: {
        var n: usize = 0;
        for (foeBiomes) |h| n += @intFromBool(h);
        break :blk n;
    };
    for (reach[0 .. unitBrushes.len - 1], 0..) |n, i| {
        const want: usize = if (i < NFOE_KIND and foemod.homeOf(@enumFromInt(i)) == .any) kingdoms else 1;
        if (n == want) continue;
        std.debug.print("\n  {s} is shown by {d} lists, wanted {d}\n", .{ unitBrushes[i], n, want });
        return error.TestUnexpectedResult;
    }
    try std.testing.expectEqual(kingdoms + 1, reach[unitBrushes.len - 1]);

    const panel = SCREEN_H - BAR_H - STATUS_H;
    const rows0 = 8 + (ROW_H + 8) + ROW_H;
    const was = @as(i32, @intCast(unitBrushes.len)) * ROW_H;
    const head = ui.TAB_H + 6 + 28 * @as(i32, @intCast((kingdoms + 1) / 2)) + 34;
    const now = head + @as(i32, @intCast(tallest)) * ROW_H;
    std.debug.print("\n  units palette: was {d} px of rows in a {d} px panel; tallest tab is now {d} rows, {d} px\n", .{ rows0 + was, panel, tallest, rows0 + now });
    try std.testing.expect(rows0 + was > panel);
    try std.testing.expect(rows0 + now <= panel);
}

test "EVERY LIST MODAL FITS THE WINDOW IT OPENS IN" {
    const foot = 8 + DLG_FOOT;

    var bosses: usize = 0;
    for (0..NFOE_KIND) |i| {
        if (foemod.isBoss(@enumFromInt(i))) bosses += 1;
    }
    const sealRows: i32 = @intCast(bosses + wf.MAX_SEAL + 1);
    const sealH = LOOT_TOP + sealRows * LOOT_ROW_H + foot;

    var tallest: usize = 0;
    var counted: usize = 0;
    for (MIX_GROUPS) |g| {
        var n: usize = 0;
        for (props.FLORA_KINDS) |k| {
            if (props.group(k) == g) n += 1;
        }
        try std.testing.expect(n > 0);
        counted += n;
        tallest = @max(tallest, n);
    }
    try std.testing.expectEqual(props.FLORA_KINDS.len, counted);
    const mixH = LOOT_TOP + MIX_TAB_ROWS * TAB_H + @as(i32, @intCast(tallest)) * LOOT_ROW_H + foot;

    std.debug.print(
        "\n  gate seal: {d} bosses -> {d} px (was {d}); zone mix: {d} shelves, tallest {d} -> {d} px (was {d}); window {d}\n",
        .{
            bosses,                                                                        sealH,
            LOOT_TOP + (NFOE_KIND + 1) * LOOT_ROW_H + foot,                                MIX_GROUPS.len,
            tallest,                                                                       mixH,
            LOOT_TOP + @as(i32, @intCast(props.FLORA_KINDS.len)) * LOOT_ROW_H + foot,       SCREEN_H,
        },
    );
    try std.testing.expect(sealH <= SCREEN_H);
    try std.testing.expect(mixH <= SCREEN_H);
    try std.testing.expect(LOOT_TOP + (NFOE_KIND + 1) * LOOT_ROW_H + foot > SCREEN_H);
    try std.testing.expect(LOOT_TOP + @as(i32, @intCast(props.FLORA_KINDS.len)) * LOOT_ROW_H + foot > SCREEN_H);
}

test "the units layer POSTS and ERASES both kinds, and the eraser does not care which" {
    undoReset();
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    const env = try testEnv(std.testing.allocator);
    defer std.testing.allocator.destroy(env);
    m.blank("folk");
    var ed = Editor{};
    ed.layer = .units;
    ed.radius = 2.0;

    ed.setBrush(0);
    ed.addUnit(m, v3(0, 0, 0));
    ed.setBrush(NFOE_KIND + 1);
    ed.addUnit(m, v3(4, 0, 0));
    try std.testing.expectEqual(@as(usize, 1), m.nfoes);
    try std.testing.expectEqual(@as(usize, 1), m.nnpcs);
    try std.testing.expectEqual(wf.NpcKind.merchant, m.npcs[0].kind);
    try std.testing.expect(ed.selUnit != null and ed.selUnit.? == .npc);

    try std.testing.expect(ed.eraseAt(m, env, v3(4, 0, 0)));
    try std.testing.expectEqual(@as(usize, 0), m.nnpcs);
    try std.testing.expectEqual(@as(usize, 1), m.nfoes);
    try std.testing.expect(ed.eraseAt(m, env, v3(0, 0, 0)));
    try std.testing.expectEqual(@as(usize, 0), m.nfoes);
}

test "THE ERASER TAKES A BODY OFF THROUGH THE FORMAT — the watch on the one above it follows it down" {
    undoReset();
    const alloc = std.testing.allocator;
    const m = try wf.testMap(alloc, wf.TEST_HEAD ++
        \\dlg: hi
        \\  node: root
        \\  say: Ho.
        \\  then: end
        \\npc: wanderer 0.00 0.00 0.0 1.00 0.00 dlg=hi
        \\npc: merchant 20.00 0.00 0.0 1.00 0.00
        \\trig: watch
        \\  when: near npc=1 r=3.0
        \\  do: flag met=1
    );
    defer alloc.destroy(m);
    const env = try testEnv(alloc);
    defer alloc.destroy(env);
    var ed = Editor{};
    ed.layer = .units;
    ed.radius = 2.0;

    try std.testing.expectEqual(@as(u16, 1), m.trigs[0].conds[0].slot);
    const dialogsWas = m.ndialogs;
    try std.testing.expect(ed.eraseAt(m, env, v3(0, 0, 0)));
    try std.testing.expectEqual(@as(usize, 1), m.nnpcs);
    try std.testing.expectEqual(wf.NpcKind.merchant, m.npcs[0].kind);
    try std.testing.expectEqual(wf.CondKind.near, m.trigs[0].conds[0].kind);
    try std.testing.expectEqual(@as(u16, 0), m.trigs[0].conds[0].slot);
    try std.testing.expectEqual(dialogsWas - 1, m.ndialogs);
    try std.testing.expect(m.npcs[0].dlg < m.ndialogs);
}

test "THE MINIMAP'S HELD FACE IS REPAINTED BY EVERY HAND THAT MOVES IT" {
    undoReset();
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    const env = try testEnv(std.testing.allocator);
    defer std.testing.allocator.destroy(env);
    m.blank("mini");
    var ed = Editor{};

    ed.layer = .props;
    ed.radius = 2.0;
    var last = ed.miniGen;
    ed.addUnit(m, v3(0, 0, 0));
    try std.testing.expect(ed.miniGen != last);

    last = ed.miniGen;
    ed.layer = .units;
    ed.setBrush(0);
    ed.addUnit(m, v3(6, 0, 0));
    try std.testing.expect(ed.miniGen != last);

    last = ed.miniGen;
    try std.testing.expect(ed.eraseAt(m, env, v3(6, 0, 0)));
    try std.testing.expect(ed.miniGen != last);

    last = ed.miniGen;
    try std.testing.expect(ed.undo(m));
    try std.testing.expect(ed.miniGen != last);

    last = ed.miniGen;
    ed.rebuild(m, env);
    try std.testing.expect(ed.miniGen != last);
}

test "THE SWEEP FINDS EVERY CONTAINER NOBODY HAS FILLED, and rounds the map rather than sitting on one" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    m.blank("loot");

    const rows = [_]struct { kind: props.Kind, nloot: u8, gold: u32 }{
        .{ .kind = .chest, .nloot = 2, .gold = 0 },
        .{ .kind = .pickup, .nloot = 0, .gold = 0 },
        .{ .kind = .pillar, .nloot = 0, .gold = 0 },
        .{ .kind = .chest, .nloot = 0, .gold = 40 },
        .{ .kind = .pickup, .nloot = 0, .gold = 0 },
    };
    for (rows, 0..) |r, i| {
        var o = wf.defaults(.at);
        o.kind = r.kind;
        o.x = @as(f32, @floatFromInt(i)) * 10.0;
        o.nloot = r.nloot;
        o.gold = r.gold;
        for (0..r.nloot) |k| o.loot[k] = .mushroom_jerky;
        _ = try m.add(o);
    }
    try std.testing.expectEqual(@as(usize, 2), countUnfilled(m));

    var ed = Editor{};
    try std.testing.expectEqual(@as(?usize, 1), nextUnfilled(&ed, m));
    ed.sel = 1;
    try std.testing.expectEqual(@as(?usize, 4), nextUnfilled(&ed, m));
    ed.sel = 4;
    try std.testing.expectEqual(@as(?usize, 1), nextUnfilled(&ed, m));

    m.ops[1].gold = 5;
    ed.sel = null;
    try std.testing.expectEqual(@as(usize, 1), countUnfilled(m));
    try std.testing.expectEqual(@as(?usize, 4), nextUnfilled(&ed, m));
    m.ops[4].nloot = 1;
    try std.testing.expectEqual(@as(usize, 0), countUnfilled(m));
    try std.testing.expectEqual(@as(?usize, null), nextUnfilled(&ed, m));
}

test "going to an empty container selects it, brings the layer with it and puts the eye on it" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    m.blank("goto");
    var full = wf.defaults(.at);
    full.kind = .chest;
    full.x = -60;
    full.nloot = 1;
    full.loot[0] = .mushroom_jerky;
    _ = try m.add(full);
    var empty = wf.defaults(.at);
    empty.kind = .pickup;
    empty.x = 42;
    empty.z = -18;
    _ = try m.add(empty);

    var ed = Editor{};
    ed.layer = .props;
    ed.focus = mathx.ground(300, 300);
    goToUnfilled(&ed, m);
    try std.testing.expectEqual(@as(?usize, 1), ed.sel);
    try std.testing.expectEqual(Layer.interact, ed.layer);
    try std.testing.expectApproxEqAbs(@as(f32, 42), ed.focus.x, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, -18), ed.focus.z, 1e-3);
    std.debug.print("\n  empty container sweep: eye on ({d:.1}, {d:.1}) at {d:.1} m, {d} left to fill\n", .{
        ed.focus.x, ed.focus.z, ed.dist, countUnfilled(m),
    });

    m.ops[1].nloot = 1;
    ed.focus = mathx.ground(7, 7);
    goToUnfilled(&ed, m);
    try std.testing.expectApproxEqAbs(@as(f32, 7), ed.focus.x, 1e-3);
}

test "THE COUNT IS HELD, AND AN EDIT MOVES IT — a stale label sends the author to a chest he already filled" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    m.blank("held");
    var o = wf.defaults(.at);
    o.kind = .chest;
    _ = try m.add(o);
    _ = try m.add(o);
    var ed = Editor{};
    try std.testing.expectEqual(@as(usize, 2), unfilledCount(&ed, m));
    // Filled WITHOUT banking, so a cache is entitled to be stale here.
    m.ops[0].gold = 40;
    try std.testing.expectEqual(@as(usize, 2), unfilledCount(&ed, m));
    ed.bank(m);
    try std.testing.expectEqual(@as(usize, 1), unfilledCount(&ed, m));
    try std.testing.expectEqual(countUnfilled(m), unfilledCount(&ed, m));
}

test "WHAT THE EMPTY-CONTAINER COUNT COSTS A FRAME — the button's label is a walk of every op" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    m.blank("cost");
    var o = wf.defaults(.at);
    o.kind = .pickup;
    while (m.nops < wf.MAX_OPS) _ = try m.add(o);

    const ROUNDS = 200;
    var timer = try std.time.Timer.start();
    var sink: usize = 0;
    for (0..ROUNDS) |_| sink += countUnfilled(m);
    const raw = @as(f64, @floatFromInt(timer.read())) / 1000.0 / @as(f64, @floatFromInt(ROUNDS));
    try std.testing.expectEqual(wf.MAX_OPS * ROUNDS, sink);

    var ed = Editor{};
    _ = unfilledCount(&ed, m);
    timer.reset();
    for (0..ROUNDS) |_| sink += unfilledCount(&ed, m);
    const held = @as(f64, @floatFromInt(timer.read())) / 1000.0 / @as(f64, @floatFromInt(ROUNDS));
    std.debug.print("\n  empty-container count over {d} ops: {d:.2} us a frame walked ({d:.3}% of a 16.7 ms frame), {d:.3} us held\n", .{
        m.nops, raw, raw / 16700.0 * 100.0, held,
    });
    try std.testing.expect(held < raw);
}
