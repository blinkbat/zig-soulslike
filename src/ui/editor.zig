const std = @import("std");
const rl = @import("raylib");
const hud = @import("hud.zig");
const mathx = @import("../core/mathx.zig");
const props = @import("../props/props.zig");
const ui = @import("ui.zig");
const wf = @import("../world/worldfmt.zig");
const envmod = @import("../world/env.zig");
const gfx = @import("../gfx/gfx.zig");
const daynight = @import("../world/daynight.zig");
const objview = @import("objview.zig");
const item = @import("../play/item.zig");
const sfx = @import("../core/audio.zig");

const Kind = props.Kind;
const v3 = mathx.v3;


const LOOK_SENS: f32 = 0.0032;
const UNDO_CAP: usize = 24;
const DRAG_PX = ui.DRAG_PX;
const SNAP: f32 = 1.0;
const REBUILD_QUIET: f32 = 0.28;

const ERASE_HZ: f32 = 5.0;
const ERASE_STEP: f32 = 0.6;
const MAX_MARKERS: usize = 500;

const Hover = union(enum) { none, prop: usize, foe: usize };

const MAX_MARKED: usize = 512;

const FULL_MSG = "map is full - worldfmt.MAX_OPS reached";
const FOES_FULL_MSG = "foe cap reached";

const DUPE_OFFSET: f32 = 6.0;

const AT_SPAN: f32 = 6.0;

const NEW_ZONE_DENSITY: f32 = 0.7;

const FOE_PICK_R: f32 = 1.6;

// File scope: a Map is ~477 KB, so 24 of them is ~11.2 MB — BSS, not inside Game and not on an allocator.
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
    "Plants",
    "Props - stone, timber, fire, water",
    "Chests (right-click > Items...) and the fog gate",
    "Foe spawns",
};

/// **TWO SECTIONS IN ONE LIST, and the split is `GROUND_SOIL_0`** — the sculpt tools first (pinned to
/// `wf.Sculpt`), then one row per `wf.Soil` past the first, then Water and the eraser. Laid out to SHOW the
/// seam: the index arithmetic either side of it is why this list cannot simply be appended to.
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
    "Erase",
};
const locationBrushes = [_][:0]const u8{ "Clearing", "Zone", "Location", "Erase" };
const decorBrushes = [_][:0]const u8{ "Single", "Patch", "Scatter", "Erase" };
const propBrushes = [_][:0]const u8{ "Stamp", "Row", "Ring", "Cluster", "Ivy", "Erase" };
const interactBrushes = [_][:0]const u8{ "Stamp", "Erase" };
const unitBrushes = blk: {
    const N = @typeInfo(wf.FoeKind).@"enum".fields.len;
    var out: [N + 1][:0]const u8 = undefined;
    for (0..N) |i| out[i] = wf.foeName(@enumFromInt(i));
    out[N] = "Erase";
    break :blk out;
};

const GROUND_SOIL_0: usize = @typeInfo(wf.Sculpt).@"enum".fields.len;

const SCULPT_EVEN: f32 = 0.5;

const DIGIT_KEYS: usize = 9;

const RAISE_SWATCH = ui.col(126, 100, 62, 255);
const LOWER_SWATCH = ui.col(74, 60, 44, 255);
const EVEN_SWATCH = ui.col(96, 100, 104, 255);

// THE SOIL ROWS CARRY NO TIP: `groundBrushes` already names each one, and a tooltip that repeats the label
// is a hover that costs a read and says nothing.
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
    "Sweep to unpaint soil and water. Leaves the sculpted shape",
};
const locationTips = [_][:0]const u8{
    "Drag a circle nothing grows in",
    "Drag a rectangle with its own cover density",
    "Drag a NAMED rectangle. Triggers find it by name; carries its own weather",
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
const unitTips = [_][:0]const u8{
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
    "The bloom OPENS before it leaps",
    "Lobs slow bouncing fireballs. Backing away stays in the bounce line; go sideways",
    "Place in water. Surfaces when you wade; cannot leave water or be hit while down",
    "Very tough against steel, weak to fire and lightning. Slams forward at anyone who backs off",
    "Sweep to erase ([ ] sets radius)",
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

const locationIcons = [_]ui.Icon{ .clearing, .zone, .location, .erase };
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
    .florid_ravager,
    .mushroom_mage,
    .fen_lurker,
    .spore_golem,
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
    std.debug.assert(groundTips.len == groundBrushes.len);
    std.debug.assert(locationTips.len == locationBrushes.len);
    std.debug.assert(decorTips.len == decorBrushes.len);
    std.debug.assert(propTips.len == propBrushes.len);
    std.debug.assert(interactTips.len == interactBrushes.len);
    std.debug.assert(unitTips.len == unitBrushes.len);
    std.debug.assert(groundBrushes.len == GROUND_SOIL_0 + (wf.Soil.N - 1) + 2);
    for (0..wf.Soil.N - 1) |i| {
        std.debug.assert(std.mem.eql(u8, groundBrushes[GROUND_SOIL_0 + i], @tagName(@as(wf.Soil, @enumFromInt(i + 1)))));
    }
    // …and the sculpt half needs no count assert of its own now: `GROUND_SOIL_0` IS `wf.Sculpt`'s length.
    // The NAMES are not tag-for-tag there (`Flat` is `wf.Sculpt.flatten`), which is why only the soils are
    // pinned by tag above.
    // …and the unit brushes ARE the foe kinds in order, plus the eraser.
    std.debug.assert(unitBrushes.len == @typeInfo(wf.FoeKind).@"enum".fields.len + 1);
    for (0..@typeInfo(wf.FoeKind).@"enum".fields.len) |i| {
        const tag = @tagName(@as(wf.FoeKind, @enumFromInt(i)));
        std.debug.assert(std.mem.eql(u8, @tagName(unitIcons[i]), tag));
    }
}

pub const GroundBrush = enum { raise, lower, smooth, flat, dirt, turf, stone, silt, ash, moss, bone, cinder, spore, bloom, water, erase };
const LocationBrush = enum { clearing, zone, location, erase };
pub const DecorBrush = enum { single, patch, scatter, erase };
const PropBrush = enum { stamp, row, ring, cluster, ivy, erase };
const InteractBrush = enum { stamp, erase };
/// **`wf.FoeKind`'S OWN TAGS, IN ITS OWN ORDER, PLUS `erase`** — pinned name-for-name by the comptime block
/// below, so a creature APPENDED to that enum is appended here and nowhere else has to be touched.
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
    florid_ravager,
    mushroom_mage,
    fen_lurker,
    spore_golem,
    erase,
};

comptime {
    pinBrushes(LocationBrush, &locationBrushes);
    pinBrushes(DecorBrush, &decorBrushes);
    pinBrushes(PropBrush, &propBrushes);
    pinBrushes(InteractBrush, &interactBrushes);
    pinBrushes(GroundBrush, &groundBrushes);
    const foeFields = @typeInfo(wf.FoeKind).@"enum".fields;
    const unitFields = @typeInfo(UnitBrush).@"enum".fields;
    if (unitFields.len != foeFields.len + 1) @compileError("editor: UnitBrush is not the foe kinds plus an eraser");
    for (foeFields, unitFields[0..foeFields.len]) |f, u| {
        if (!std.mem.eql(u8, f.name, u.name)) @compileError("editor: UnitBrush." ++ u.name ++ " is not wf.FoeKind." ++ f.name);
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

fn layerOf(o: *const wf.Op) Layer {
    return switch (o.op) {
        .ivy => .props,
        .edge => .props,
        else => switch (props.stock(o.kind)) {
            .decor => .decor,
            .props => .props,
            .interact => .interact,
        },
    };
}

pub const Action = enum { none, leave, playtest };

pub const Modal = enum { none, new_map, open_map, save_as, confirm, objects, loot, boss, jukebox, world, zonemix };

/// The bench lists off the AUDIO module's own table (`sfx.NAMES`), which `settings.cfg` is already keyed on.
/// A second comptime walk over `sfx.Id` here was the same list built twice, and the one it has to agree with
/// is the one the save writes.
const VOICE_NAMES = sfx.NAMES;

const JUKE_W: i32 = 1010;
const JUKE_H: i32 = 560;
const JUKE_LIST_W: i32 = 300;
const JUKE_LIST_H: i32 = JUKE_H - 150;
/// The bench column between the list and the rack, MEASURED off the modal rather than picked: the rack is
/// pinned to the right edge, so this is whatever is left after both gutters.
const JUKE_COL_W: i32 = JUKE_W - JUKE_LIST_W - RACK_W - 80;

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

fn isMovable(o: *const wf.Op) bool {
    return o.op != .edge;
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
    /// **WHAT IS ON SCREEN, WHICH IS NOT WHAT IS SELECTED.** One eye per layer plus the sky's own, and the
    /// two axes stay independent on purpose: you hide the wood to place a wall under it and the Props layer is
    /// still the one your brush is on. Hiding is a VIEW and never touches the map, so nothing here is saved,
    /// nothing is undoable and a hidden layer still parses, still builds and still spawns.
    shown: [Layer.N]bool = [_]bool{true} ** Layer.N,
    /// The rain, the mist and the sporefall — not a layer, because it is not a thing the map places in a
    /// rectangle. It is the one overlay that hides the GROUND you are trying to sculpt.
    showWeather: bool = true,
    brush: [Layer.N]usize = [_]usize{0} ** Layer.N,
    decorKind: Kind = .fern,
    propKind: Kind = .pillar,
    interactKind: Kind = .chest,
    groupSel: props.Group = .ruins,
    radius: f32 = 6.0,
    soilOpacity: f32 = 1.0,
    brushEdge: wf.Edge = .natural,
    snap: bool = false,

    sel: ?usize = null,
    selFoe: ?usize = null,
    dirty: bool = false,
    /// BUMPED WHENEVER THE MAP IS REPLACED WHOLESALE — entering, and every Open / New / Reload. What the game
    /// watches to know its copy of the tables the editor cannot author (the folk) has gone stale, without
    /// re-deriving them every frame.
    mapGen: u32 = 0,

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
    juke: usize = 0,
    jukeScroll: i32 = 0,
    jukeWorld: bool = false,
    rackMix: sfx.Submix = .combat,
    rackOnVoice: bool = false,
    /// WHICH ZONE the name field and the mix modal are editing. A zone is not an `Op`, so it cannot ride
    /// `sel` — and its mix was the one thing in the whole format the editor could only ever INHERIT.
    zoneSel: ?usize = null,
    locSel: ?usize = null,
    lootTab: item.Class = .tool,
    zoneNameLen: usize = 0,
    zoneNameBuf: [wf.NAME_CAP]u8 = [_]u8{0} ** wf.NAME_CAP,
    /// The zone name field owns the keyboard while it is on screen — set by the draw pass, read by
    /// `update` a frame later, so w/a/s/d, digits, g/r, Tab and Delete type letters instead of firing.
    textFocus: bool = false,
    nameBuf: [wf.NAME_CAP]u8 = undefined,
    nameLen: usize = 0,
    fileSel: usize = 0,
    fileScroll: i32 = 0,
    path: [wf.PATH_CAP]u8 = undefined,
    pathLen: usize = 0,
    hotFrame: bool = false,
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
        self.dropSelection();
        self.modal = .none;
        self.pending = .none;
        self.rmbDown = false;
        self.rmbTravel = 0;
        self.hotFrame = false;
        self.editing = false;
        if (self.pathLen == 0) self.setPath(wf.START_MAP);
        undoReset();
        self.mapGen +%= 1;
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
            self.dist = mathx.clampF(self.dist * (1.0 - wheel * 0.12), 2.0, 420.0);
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
        const l = @sqrt(f.x * f.x + f.z * f.z);
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

    /// Where the cursor meets the ground, as resolved for THIS frame. `env.rayGround` is a MARCH over the
    /// height lattice — a ray that never lands walks some 1600 bilinear samples — and five sites ask it a
    /// frame; the pointer cannot move inside one.
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
        return true;
    }

    fn redo(self: *Editor, m: *wf.Map) bool {
        if (undoAt <= 1) return false;
        undoAt -= 1;
        m.* = undoSlot(undoN - undoAt).*;
        self.dropSelection();
        return true;
    }

    fn dropSelection(self: *Editor) void {
        self.sel = null;
        self.selFoe = null;
        self.nMarked = 0;
        self.zoneSel = null;
        self.locSel = null;
    }

    pub fn applyCamForShot(self: *Editor) void {
        self.applyCam();
        self.resolveCursor();
    }

    pub fn focusOnForShot(self: *Editor, m: *const wf.Map, i: usize) void {
        self.focusOn(m, i);
    }

    pub fn selectForShot(self: *Editor, m: *const wf.Map, a: rl.Vector3, b: rl.Vector3) void {
        self.marqueeSelect(m, a, b);
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

    pub fn soundsForShot(self: *Editor, id: sfx.Id) void {
        self.modal = .jukebox;
        self.menuOpen = false;
        self.juke = @intFromEnum(id);
        self.jukeReveal();
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
            .edge => m.half,
        };
        const c = if (isMovable(&o)) opAnchor(&o) else mathx.zero3;
        self.lookAtGround(c.x, c.z, span);
    }

    // Capped well inside the haze: framing a 250 m belt by its full extent puts the eye so far back that
    // every prop is past its own view distance and all you get is fog with markers in it.
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
            if (self.sel != null or self.selFoe != null or self.nMarked > 0) {
                self.sel = null;
                self.selFoe = null;
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
            for (digits, 0..) |k, i| {
                if (rl.isKeyPressed(k) and i < brushesFor(self.layer).len and
                    !self.dragging and !self.painting and !self.wipe.on)
                {
                    self.setBrush(i);
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
        env.uploadSoil(m);
        env.uploadWater(m);
        env.uploadHeight(m);
        env.materialize(m);
    }

    fn requestRebuild(self: *Editor) void {
        self.rebuildDue = true;
        self.rebuildT = 0;
    }

    fn tickRebuild(self: *Editor, m: *const wf.Map, env: *envmod.Env, dt: f32) void {
        if (!self.rebuildDue) return;
        self.rebuildT += dt;
        if (self.rebuildT >= REBUILD_QUIET) self.rebuild(m, env);
    }

    fn endGesture(self: *Editor, _: *const wf.Map, _: *envmod.Env) void {
        self.editing = false;
    }

    pub fn flushRebuild(self: *Editor, m: *const wf.Map, env: *envmod.Env) void {
        if (self.painting) self.endPaint(m, env);
        if (self.rebuildDue) self.rebuild(m, env);
    }

    fn selectZone(self: *Editor, m: *const wf.Map, i: usize) void {
        self.zoneSel = i;
        self.zoneNameBuf = [_]u8{0} ** wf.NAME_CAP;
        self.zoneNameLen = 0;
        if (i >= m.nzones) return;
        const lab = m.zones[i].label();
        self.zoneNameLen = @min(lab.len, wf.NAME_CAP - 1);
        @memcpy(self.zoneNameBuf[0..self.zoneNameLen], lab[0..self.zoneNameLen]);
    }

    /// The World panel edits two UNRELATED fields of the map itself, so it cannot use `bankGesture`'s
    /// single-target trick: it puts both back, banks, and restores the live pair. Same contract otherwise —
    /// one undo step per gesture, closed by `endGesture` when the mouse lets go.
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
                    self.selFoe = null;
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
                        .water => if (m.paintWater(g.x, g.z, self.radius, true, self.brushEdge)) {
                            env.uploadWater(m);
                            self.wetStroke = true;
                        },
                        .erase => {
                            if (m.paintSoil(g.x, g.z, self.radius, .none, 1, null)) env.uploadSoil(m);
                            if (m.paintWater(g.x, g.z, self.radius, false, null)) {
                                env.uploadWater(m);
                                self.wetStroke = true;
                            }
                        },
                        else => {
                            const id: wf.Soil = @enumFromInt(self.brushIdx() - GROUND_SOIL_0 + 1);
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
                if (self.pickInLayer(m, env)) return;
                if (ground) |g| {
                    self.panning = true;
                    self.panGrab = g;
                }
                return;
            }
            switch (self.layer) {
                .units => {
                    if (ground) |g| self.addFoe(m, g);
                },
                .locations, .decor, .props, .interact => {
                    if (ground) |g| {
                        self.dragging = true;
                        self.dragFrom = g;
                        self.dragTo = g;
                    }
                },
                // Guarded above (the ground layer paints and returns); a message beats UB in Release.
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
            .foe, .none => false,
        };
    }

    fn underCursor(self: *Editor, m: *wf.Map, env: *envmod.Env) Hover {
        if (self.hoverLive) return self.hover;
        return self.hoverInLayer(m, env);
    }

    fn hoverInLayer(self: *Editor, m: *wf.Map, env: *envmod.Env) Hover {
        if (self.layer.opLayer()) {
            const ray = self.cursorRay();
            if (env.pickIf(ray.position, ray.direction, self.filter(m), OpFilter.inLayer)) |pi| return .{ .prop = pi };
            return .none;
        }
        if (self.layer == .units) {
            const g = self.groundAt() orelse return .none;
            var near = mathx.Nearest.within(FOE_PICK_R);
            for (m.foes[0..m.nfoes], 0..) |f, i| near.offer(i, v3(f.x, 0, f.z), g);
            return if (near.best) |i| .{ .foe = i } else .none;
        }
        return .none;
    }

    fn pickInLayer(self: *Editor, m: *wf.Map, env: *envmod.Env) bool {
        switch (self.underCursor(m, env)) {
            .prop => |pi| {
                const o = env.props[pi].op;
                self.sel = o;
                self.selFoe = null;
                const op = m.ops[o];
                self.sayFmt("#{d} {s} {s}", .{ o, @tagName(op.op), @tagName(op.kind) });
                return true;
            },
            .foe => |i| {
                self.selFoe = i;
                self.sel = null;
                self.sayFmt("#{d} {s}", .{ i, wf.foeName(m.foes[i].kind) });
                return true;
            },
            .none => {},
        }
        if (self.layer == .locations) {
            const g = self.groundAt() orelse return false;
            for (m.clearings[0..m.nclearings], 0..) |c, i| {
                if (mathx.dist2XZ(v3(c.x, 0, c.z), g) < c.r * c.r) {
                    self.sel = null;
                    self.sayFmt("clearing {d} - r {d:.0}", .{ i, c.r });
                    return false;
                }
            }
        }
        return false;
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
                    // PREPENDED, and that IS the overlap rule: `locationAt` takes the first match, so the
                    // one you painted last is the one that answers. Any other order makes the rectangle you
                    // can see disagree with the rectangle that fires.
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
                .erase => return,
            }
            self.rebuild(m, env);
            return;
        }

        var o = wf.defaults(.at);
        o.kind = self.kindForLayer();
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
        self.selFoe = null;
        self.rebuild(m, env);
        self.sayFmt("+{s} {s} #{d}", .{ @tagName(o.op), @tagName(o.kind), at });
    }

    const AREA_PER_INSTANCE: f32 = 9.0;
    const FRESH_N_LO: f32 = 4;
    const FRESH_N_HI: f32 = 900;
    const MIN_CLEARING_R: f32 = 2.0;
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

    fn addFoe(self: *Editor, m: *wf.Map, at: rl.Vector3) void {
        if (self.erasing()) return;
        if (m.nfoes >= wf.MAX_FOES) {
            self.say(FOES_FULL_MSG);
            return;
        }
        const kind: wf.FoeKind = @enumFromInt(self.brushIdx());
        self.bank(m);
        const seed = @as(f32, @floatFromInt((m.nfoes * 37) % 100)) / 100.0;
        m.foes[m.nfoes] = .{ .kind = kind, .x = at.x, .z = at.z, .yaw = 0, .scale = 1, .seed = seed };
        self.selFoe = m.nfoes;
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
            },
            .locations => {
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
                if (s >= m.nops or !isMovable(&m.ops[s])) {
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

    fn deleteSel(self: *Editor, m: *wf.Map, env: *envmod.Env) void {
        if (self.layer == .units) {
            const f = self.selFoe orelse return;
            if (f >= m.nfoes) return;
            self.bank(m);
            std.mem.copyForwards(wf.Foe, m.foes[f .. m.nfoes - 1], m.foes[f + 1 .. m.nfoes]);
            m.nfoes -= 1;
            self.dropSelection();
            self.say("-foe");
            return;
        }
        const s = self.sel orelse return;
        if (s >= m.nops) return;
        if (!isMovable(&m.ops[s])) {
            self.sayFmt("the {s} op is the whole world's - it cannot be deleted", .{@tagName(m.ops[s].op)});
            return;
        }
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
        if (s >= m.nops or !isMovable(&m.ops[s])) return;
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
            self.selFoe = if (self.nMarked > 0) self.marked[0] else null;
            self.sel = null;
            // would show a properties panel for something this marquee cannot touch
        } else if (self.layer.opLayer()) {
            for (m.ops[0..m.nops], 0..) |*o, i| {
                if (layerOf(o) != self.layer or !isMovable(o)) continue;
                const p = opAnchor(o);
                if (box.holds(p.x, p.z)) self.mark(i);
            }
            self.sel = if (self.nMarked > 0) self.marked[0] else null;
            self.selFoe = null;
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
                m.foes[i].x += dx;
                m.foes[i].z += dz;
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
                f.x -= c.x;
                f.z -= c.z;
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
            f.x += at.x;
            f.z += at.z;
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
                if (i >= m.nops or !isMovable(&m.ops[i])) continue;
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
        self.mapGen +%= 1;
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


    /// **THE LAYER YOU ARE STANDING ON IS ALWAYS VISIBLE**, whatever its eye says. Hiding the layer your brush
    /// is on would leave you painting into a layer you cannot see — the cursor, the marquee and the selection
    /// gizmos would all be drawing for something invisible, which is a way to lose work rather than a view.
    /// The eye stays as you left it, so selecting away restores the hidden state.
    pub fn visible(self: *const Editor, l: Layer) bool {
        return self.layer == l or self.shown[@intFromEnum(l)];
    }

    /// **DOES THE TOP STRIP FIT WITH ITS LAYER NAMES SPELLED OUT.** Measured, not guessed at: `BarRow`'s own
    /// widths for the layers, plus the same arithmetic for the fixed tail that follows them, so a label added
    /// or a verb added is answered here rather than discovered as a clipped button on the right-hand edge.
    fn barWide(self: *const Editor, sw: i32) bool {
        _ = self;
        const step = BarRow.GAP;
        const sq = BAR_H - 10;
        var w: i32 = 8;
        inline for (@typeInfo(Layer).@"enum".fields) |f| {
            const l: Layer = @enumFromInt(f.value);
            w += ui.layerButtonW(l.label(), hud.MONO) + step;
        }
        w += 6 + sq + step; // the weather eye
        w += 14 + 7 * (sq + step) + 10 + 10; // the seven verbs and the gaps that group them
        inline for (.{ "Objects", "World", "Sounds" }) |lab| {
            w += hud.monoW(lab, hud.MONO) + BarRow.PAD + step;
        }
        return w + DIRTY_W <= sw;
    }

    /// Room for the unsaved-changes `*` that `drawTopBar` sets down past the last button.
    const DIRTY_W: i32 = 20;

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
        // A weather region reads GOLD and a plain one reads cool, so you can see at a glance which
        // rectangles are doing something to the sky.
        if (self.visible(.locations)) {
            for (m.locations[0..m.nlocations], 0..) |*l, i| {
                const on = self.locSel == i;
                const col = if (l.hasWeather()) ui.LIVE else ui.TRIM;
                outline(l.x, l.z, l.x1, l.z1, y + 0.02, ui.alpha(if (on) ui.HOT else col, if (self.layer == .locations) 220 else 55));
            }
        }

        const unitA: u8 = if (self.layer == .units) 235 else 70;
        if (self.visible(.units)) {
            for (m.foes[0..m.nfoes], 0..) |f, i| {
                const sel = self.layer == .units and self.selFoe == i;
                const col = if (sel) ui.HOT else ui.alpha(foeSwatch(f.kind), unitA);
                const at = liftAt(f.x, f.z, y + FOE_BOX_H * 0.5);
                rl.drawCubeWires(at, FOE_BOX_W, FOE_BOX_H, FOE_BOX_W, col);
            }
        }

        self.selOwned = 0;
        self.selMarked = 0;
        if (self.sel) |s| {
            if (s < m.nops and self.layer.opLayer()) {
                drawOpGizmo(&m.ops[s], y);
                // MEASURED AND LEFT: a whole-list walk (~17k props, ~1 MB) every frame something is
                // selected. A binary search over `materialize`'s op order would find the run in ~14 steps,
                // but that buys the gizmo pass a dependence on the placer's append order.
                for (env.props[0..env.nprops]) |pr| {
                    if (pr.op != s) continue;
                    self.selOwned += 1;
                    if (self.selMarked >= MAX_MARKERS) continue;
                    self.selMarked += 1;
                    const nfo = props.info(pr.kind);
                    const h = @max(nfo.top * pr.scale, 0.4);
                    const sw = envmod.leanOffsetAt(pr.lean, pr.leanDir, h * 0.5);
                    rl.drawCubeWires(v3(pr.pos.x + sw.x, pr.pos.y + h * 0.5, pr.pos.z + sw.z), 0.3, h, 0.3, ui.HOT);
                }
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
                    const h = @max(nfo.top * pr.scale, 0.4);
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
                    .erase => {},
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
            // A HEADING SPOKE, because a circle cannot show yaw.
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
        .edge => {},
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
        .leechfly => ui.col(196, 66, 58, 255),
        .rooted => ui.col(140, 96, 52, 255),
        .shroom => ui.col(214, 130, 118, 255),
        .bone_knight => ui.col(228, 132, 62, 255),
        .delver => ui.col(150, 118, 78, 255),
        .necromancer => ui.col(126, 196, 224, 255),
        .florid_ravager => ui.col(226, 138, 196, 255),
        .mushroom_mage => ui.col(238, 152, 66, 255),
        .spore_golem => ui.col(214, 96, 132, 255),
        .fen_lurker => ui.col(78, 200, 186, 255),
    };
}

var gizmoWorld: ?*const envmod.Env = null;

fn liftAt(x: f32, z: f32, lift: f32) rl.Vector3 {
    if (gizmoWorld) |w| return v3(x, w.groundAt(x, z) + lift, z);
    return v3(x, envmod.groundY() + lift, z);
}

fn groundLine(x0: f32, z0: f32, x1: f32, z1: f32, lift: f32, col: rl.Color) void {
    const SEG = 12;
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
    ui.drawTip(&ctx);

    ed.hotFrame = ctx.anyHot;
}

const BarRow = struct {
    ctx: *ui.Ctx,
    x: i32,

    const GAP: i32 = 3;
    const PAD: i32 = 18;

    fn button(r: *BarRow, label: [:0]const u8, active: bool, tip: [:0]const u8) bool {
        const w = hud.monoW(label, hud.MONO) + PAD;
        defer r.x += w + GAP;
        return ui.buttonTip(r.ctx, ui.rect(r.x, 5, w, BAR_H - 10), label, hud.MONO, active, tip);
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

    /// THE SKY'S OWN EYE — a lone one, because the weather is not a layer and has no label to ride inside.
    fn eye(r: *BarRow, on: bool, tip: [:0]const u8) bool {
        const w = BAR_H - 10;
        defer r.x += w + GAP;
        return ui.iconOnly(r.ctx, ui.rect(r.x, 5, w, w), if (on) .eye else .eyeOff, !on, tip);
    }

    fn gap(r: *BarRow, px: i32) void {
        r.x += px;
    }
};

fn drawTopBar(ed: *Editor, m: *wf.Map, env: *envmod.Env, ctx: *ui.Ctx, sw: i32) void {
    ui.panel(ctx, ui.rect(0, 0, sw, BAR_H), null);
    var row = BarRow{ .ctx = ctx, .x = 8 };
    // **THE STRIP MEASURES ITSELF AND DROPS THE LABELS RATHER THAN RUN OFF THE WINDOW.** The eyes cost
    // `EYE_SLOT` apiece and pushed `Sounds` off the right-hand edge at 1280 — and a bar whose last button is
    // unreachable is worse than one whose names are in the tooltips. `barWide` is the one place the decision
    // is made, so the widths the layout uses and the widths it measured cannot disagree.
    const named = ed.barWide(sw);
    inline for (@typeInfo(Layer).@"enum".fields) |f| {
        const l: Layer = @enumFromInt(f.value);
        switch (row.layer(layerIcon(l), if (named) l.label() else "", ed.layer == l, ed.shown[f.value], layerTips[f.value])) {
            .select => ed.setLayer(l),
            .toggle => ed.shown[f.value] = !ed.shown[f.value],
            .none => {},
        }
    }
    row.gap(6);
    if (row.eye(ed.showWeather, if (ed.showWeather)
        "Hide the weather - rain, mist and sporefall, so you can see the ground"
    else
        "Show the weather"))
    {
        ed.showWeather = !ed.showWeather;
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
        // A failed load leaves `m` untouched (`wf.load` parses into scratch first) — and must not take the rest
        // of the bar with it, or the frame it fails on has no undo, no Objects and no chrome to claim the pointer.
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
    if (row.button("World", ed.modal == .world, "The map itself - its size, the runway, and the cliff rim")) {
        ed.menuOpen = false;
        ed.modal = .world;
    }
    if (row.button("Sounds", ed.modal == .jukebox, "Jukebox - play any sound in the bank on demand")) {
        ed.menuOpen = false;
        ed.modal = .jukebox;
    }

    if (ed.dirty) hud.mono("*", row.x + 8, 8, hud.MONO, ui.HOT);
}

fn drawSide(ed: *Editor, ctx: *ui.Ctx, sh: i32) void {
    ui.panel(ctx, ui.rect(0, BAR_H, SIDE_W, sh - BAR_H - STATUS_H), null);
    var y: i32 = BAR_H + 8;

    const selR = ui.rect(8, y, SIDE_W - 16, ROW_H - 2);
    ui.tipFor(ctx, selR, "Left-click picks objects; left-drag pans the map (Esc)");
    if (ui.iconButton(ctx, selR, .select, "Select", hud.MONO, ed.selecting)) {
        ed.selecting = true;
    }
    y += ROW_H + 8;

    hud.mono("BRUSH", 10, y, hud.MONO, ui.alpha(ui.TRIM, 235));
    y += ROW_H;
    const brushes = brushesFor(ed.layer);
    const tips = brushTipsFor(ed.layer);
    const glyphs = brushIconsFor(ed.layer);
    for (brushes, 0..) |b, i| {
        if (brushSectionFor(ed.layer, i)) |sec| {
            hud.mono(sec, 18, y, hud.MONO, ui.alpha(ui.LABEL, 150));
            y += hud.monoLineH(hud.MONO);
        }
        var lab: [40]u8 = undefined;
        const s = if (i < DIGIT_KEYS) (std.fmt.bufPrintZ(&lab, "{d} {s}", .{ i + 1, b }) catch b) else b;
        const r = ui.rect(8, y, SIDE_W - 16, ROW_H - 4);
        ui.tipFor(ctx, r, tips[i]);
        const on = !ed.selecting and ed.brushIdx() == i;
        const hit = if (glyphs) |g|
            ui.iconButton(ctx, r, g[i], s, hud.MONO, on)
        else
            (if (i + 1 == brushes.len)
                ui.iconButton(ctx, r, .erase, s, hud.MONO, on)
            else switch (@as(GroundBrush, @enumFromInt(i))) {
                .raise => ui.swatchButton(ctx, r, RAISE_SWATCH, s, hud.MONO, on),
                .lower => ui.swatchButton(ctx, r, LOWER_SWATCH, s, hud.MONO, on),
                .smooth, .flat => ui.swatchButton(ctx, r, EVEN_SWATCH, s, hud.MONO, on),
                .water => ui.swatchButton(ctx, r, WATER_SWATCH, s, hud.MONO, on),
                else => ui.swatchButton(ctx, r, soilSwatch(@enumFromInt(i - GROUND_SOIL_0 + 1)), s, hud.MONO, on),
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
                if (ui.chip(ctx, chipX, chipY, gp.label(), on, &used)) ed.groupSel = gp;
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
        if (ui.list(ctx, ui.rect(8, y, SIDE_W - 16, listH), labels[0..n], selIdx, &ed.kindScroll)) |i| {
            ed.kindSlot().* = kinds[i];
        }
    }
}


fn coordRow(ctx: *ui.Ctx, x: i32, y: *i32, w: i32, label: [:0]const u8, v: *f32, step: f32) bool {
    defer y.* += ROW_H;
    return ui.stepperF(ctx, x, y.*, w, label, v, step, -COORD_LIM, COORD_LIM);
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
        if (ui.chip(ctx, cx, y.*, lab, o.gAxis == ax, &usedW) and o.gAxis != ax) {
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
    ch = ui.stepperF(ctx, x, y.*, w, "from", &o.gA, 1, -COORD_LIM, COORD_LIM) or ch;
    y.* += ROW_H;
    ch = ui.stepperF(ctx, x, y.*, w, "to", &o.gB, 1, -COORD_LIM, COORD_LIM) or ch;
    y.* += ROW_H;
    ch = ui.slider(ctx, x, y.*, w, "thin end", &o.gFloor, 0, 1) or ch;
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
        const wet = brush == .water;
        const sculpting = switch (brush) {
            .raise, .lower, .smooth, .flat => true,
            else => false,
        };
        hud.mono(if (sculpting) "SCULPT" else if (wet) "WATER BRUSH" else "SOIL BRUSH", x, y, hud.MONO, ui.TITLE);
        y += ROW_H + 4;
        _ = ui.slider(ctx, x, y, w, "radius", &ed.radius, 1, 60);
        y += ROW_H + SLIDER_DROP;
        if (!sculpting and !wet) {
            _ = ui.slider(ctx, x, y, w, "opacity", &ed.soilOpacity, 0, 1);
            y += ROW_H + SLIDER_DROP;
        }
        if (!sculpting) {
            hud.mono(if (wet) "coast" else "edge", x, y, hud.MONO, ui.LABEL);
            y += ROW_H;
            const EDGE_COLS = 4;
            const cellW = @divTrunc(w - (EDGE_COLS - 1) * 4, EDGE_COLS);
            for (0..wf.Edge.N) |i| {
                const e: wf.Edge = @enumFromInt(i);
                const col: i32 = @intCast(i % EDGE_COLS);
                const row: i32 = @intCast(i / EDGE_COLS);
                const r = ui.rect(x + col * (cellW + 4), y + row * (ROW_H + 4), cellW, ROW_H);
                if (ui.buttonTip(ctx, r, e.label(), hud.MONO, ed.brushEdge == e, edgeTip(e, wet))) ed.brushEdge = e;
            }
            y += 2 * (ROW_H + 4) + 6;
        }
        if (sculpting) {
            _ = ui.slider(ctx, x, y, w, "strength", &ed.sculptRate, 0.5, 12);
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
            if (ui.buttonTip(ctx, ui.rect(x, y, w, 24), "level the map", hud.MONO, false, "Flatten the whole world back to zero. Undoable")) {
                ed.bank(m);
                m.height = [_]u8{wf.HEIGHT_ZERO} ** wf.HEIGHT_CELLS;
                ed.rebuild(m, env);
                ed.say("ground levelled");
            }
            return;
        }
        // A full scan of the armed brush's grid every frame (12,544 bytes soil / 50,176 water) to print one
        // number — measured, and deliberately left.
        var painted: usize = 0;
        if (wet) {
            for (m.water) |v| {
                if (v != 0) painted += 1;
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
        if (wet) {
            const s3 = std.fmt.bufPrintZ(&buf, "deep at {d:.0} m in", .{gfx.WATER_DEEP_AT}) catch "";
            hud.mono(s3, x, y, hud.MONO, ui.alpha(ui.LABEL, 190));
            y += ROW_H;
            const s4 = std.fmt.bufPrintZ(&buf, "wet sand {d:.1} m out", .{gfx.WATER_WET_OUT}) catch "";
            hud.mono(s4, x, y, hud.MONO, ui.alpha(ui.LABEL, 190));
            y += ROW_H;
        }
        y += 10;
        const clearLabel: [:0]const u8 = if (wet) "drain the map" else "clear all paint";
        const clearTip: [:0]const u8 = if (wet) "Wipe every painted lake" else "Unpaint the whole map";
        if (ui.buttonTip(ctx, ui.rect(x, y, w, 24), clearLabel, hud.MONO, false, clearTip)) {
            ed.bank(m);
            if (wet) {
                m.water = [_]u8{0} ** wf.WATER_CELLS;
                ed.rebuild(m, env);
                ed.say("water cleared");
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
        const f = ed.selFoe orelse {
            var buf: [64]u8 = undefined;
            const s = std.fmt.bufPrintZ(&buf, "{d} posted", .{m.nfoes}) catch "";
            hud.mono(s, x, y, hud.MONO, ui.LABEL);
            y += ROW_H;
            hud.mono("click one to edit it", x, y, hud.MONO, ui.alpha(ui.LABEL, 160));
            return;
        };
        if (f >= m.nfoes) return;
        const fo = &m.foes[f];
        var head: [48]u8 = undefined;
        const title = std.fmt.bufPrintZ(&head, "#{d} {s}", .{ f, @tagName(fo.kind) }) catch "";
        hud.mono(title, x, y, hud.MONO, ui.TITLE);
        y += ROW_H + 4;
        var changed = false;
        const before = fo.*;
        changed = ui.stepperF(ctx, x, y, w, "x", &fo.x, 0.5, -COORD_LIM, COORD_LIM) or changed;
        y += ROW_H;
        changed = ui.stepperF(ctx, x, y, w, "z", &fo.z, 0.5, -COORD_LIM, COORD_LIM) or changed;
        y += ROW_H;
        changed = ui.stepperF(ctx, x, y, w, "yaw", &fo.yaw, 15, -360, 720) or changed;
        y += ROW_H;
        changed = ui.stepperF(ctx, x, y, w, "scale", &fo.scale, 0.02, wf.FOE_SCALE_LO, wf.FOE_SCALE_HI) or changed;
        y += ROW_H;
        changed = ui.stepperF(ctx, x, y, w, "phase", &fo.seed, 0.05, 0, 1) or changed;
        y += ROW_H + 6;
        if (ui.buttonTip(ctx, ui.rect(x, y, 80, 24), "delete", hud.MONO, false, "Remove this spawn (Del)")) {
            ed.deleteSel(m, env);
            return;
        }
        if (changed) {
            ed.bankGesture(wf.Foe, m, fo, before);
        } else if (!ctx.down) ed.endGesture(m, env);
        return;
    }

    if (ed.layer == .locations) {
        // **THE LOCATIONS FIRST, because they are the ones that do something.** Weather is per location and
        // the ONE sky cross-fades toward whichever one he is standing in (`game.settleSky`), so these three
        // dials are the whole of a weather region: how wet, how thick, and how long it takes to arrive.
        if (m.nlocations > 0) {
            hud.mono("LOCATIONS", x, y, hud.MONO, ui.TITLE);
            y += ROW_H + 4;
            var lchanged = false;
            const lbefore = m.locations;
            for (m.locations[0..m.nlocations], 0..) |*l, i| {
                var lb: [56]u8 = undefined;
                const on = ed.locSel == i;
                const lab = std.fmt.bufPrintZ(&lb, "{s}{s}", .{ l.label(), if (l.hasWeather()) " *" else "" }) catch "?";
                if (ui.buttonTip(ctx, ui.rect(x, y, w, 22), lab, hud.MONO, on, "Select this location - a * means it carries weather")) {
                    ed.locSel = if (on) null else i;
                }
                y += ROW_H;
                if (!on) continue;
                // A location with NO opinion leaves the world's own storm alone, which is not the same as
                // one that says "dry": the toggle is the difference and it has to be explicit.
                var wet = l.wet orelse 0;
                var fog = l.fog orelse 0;
                var spore = l.spore orelse 0;
                var has = l.hasWeather();
                var usedW: i32 = 0;
                if (ui.chip(ctx, x + 8, y, "weather", has, &usedW)) {
                    has = !has;
                    l.wet = if (has) wet else null;
                    l.fog = if (has) fog else null;
                    l.spore = if (has) spore else null;
                    lchanged = true;
                }
                y += ROW_H;
                if (has) {
                    if (ui.slider(ctx, x + 8, y, w - 16, "wet", &wet, 0, 1)) {
                        l.wet = wet;
                        lchanged = true;
                    }
                    y += ROW_H + SLIDER_DROP;
                    if (ui.slider(ctx, x + 8, y, w - 16, "fog", &fog, 0, 1)) {
                        l.fog = fog;
                        lchanged = true;
                    }
                    y += ROW_H + SLIDER_DROP;
                    if (ui.slider(ctx, x + 8, y, w - 16, "spore", &spore, 0, 1)) {
                        l.spore = spore;
                        lchanged = true;
                    }
                    y += ROW_H + SLIDER_DROP;
                    if (ui.slider(ctx, x + 8, y, w - 16, "blend s", &l.blend, 0, 30)) lchanged = true;
                    y += ROW_H + SLIDER_DROP;
                }
            }
            if (lchanged) {
                ed.dirty = true;
                _ = lbefore;
            }
            y += 6;
        }
        hud.mono("ZONES", x, y, hud.MONO, ui.TITLE);
        y += ROW_H + 4;
        var changed = false;
        var before: [wf.MAX_ZONES]f32 = undefined;
        for (m.zones[0..m.nzones], 0..) |*z, i| before[i] = z.density;
        for (m.zones[0..m.nzones], 0..) |*z, i| {
            var zb: [48]u8 = undefined;
            const lab = std.fmt.bufPrintZ(&zb, "{d} {s} ({d})", .{ i, z.label(), z.nmix }) catch "?";
            changed = ui.slider(ctx, x, y, w - 34, lab, &z.density, 0, 1) or changed;
            // …and the way IN to the two things a zone carries that nothing here could reach: its NAME and
            // the MIX it grows. Its own button, so it cannot fight the slider for the same click.
            if (ui.buttonTip(ctx, ui.rect(x + w - 30, y + 14, 30, 22), "...", hud.MONO, ed.zoneSel == i, "Name this zone and choose what grows in it")) {
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
                const focused = ed.modal == .none;
                ed.textFocus = focused;
                ui.textField(ctx, ui.rect(x, y, w, 26), &ed.zoneNameBuf, &ed.zoneNameLen, focused);
                for (ed.zoneNameBuf[0..ed.zoneNameLen]) |*ch| {
                    if (ch.* == ' ' or ch.* == '#') ch.* = '_';
                }
                const typed = ed.zoneNameBuf[0..ed.zoneNameLen];
                if (focused and !std.mem.eql(u8, typed, m.zones[zi].label())) {
                    ed.bank(m);
                    m.zones[zi].setName(typed);
                }
                y += 32;
            }
        }
        var cb: [64]u8 = undefined;
        const cs = std.fmt.bufPrintZ(&cb, "{d} clearings", .{m.nclearings}) catch "";
        hud.mono(cs, x, y, hud.MONO, ui.LABEL);
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
        } else if (!ctx.down) ed.endGesture(m, env);
        return;
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
    if (ui.buttonTip(ctx, ui.rect(x + w - 74, y - 2, 74, 22), "view", hud.MONO, false, "Open this kind in the object viewer")) {
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
            changed = ui.stepperF(ctx, x, y, w, "yaw", &o.yaw, 5, -360, 720) or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "scale", &o.scale, 0.05, 0.1, 4) or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "lean", &o.lean, 1, 0, LEAN_LIM) or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "lean dir", &o.leanDir, 15, -360, 720) or changed;
            y += ROW_H;
        },
        .belt, .ivy => {
            changed = spanRows(ctx, x, &y, w, o) or changed;
            if (o.op == .belt) {
                changed = ui.stepperI(ctx, x, y, w, "count", &o.n, 5, 0, COUNT_MAX) or changed;
                y += ROW_H;
            } else {
                changed = ui.slider(ctx, x, y, w, "take", &o.chance, 0, 1) or changed;
                y += ROW_H + SLIDER_DROP;
            }
        },
        .disc => {
            changed = centreRows(ctx, x, &y, w, o, 1) or changed;
            changed = ui.stepperF(ctx, x, y, w, "inner", &o.r0, 0.5, 0, 200) or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "outer", &o.r1, 0.5, 0, 200) or changed;
            y += ROW_H;
            changed = ui.stepperI(ctx, x, y, w, "count", &o.n, 5, 0, COUNT_MAX) or changed;
            y += ROW_H;
            changed = ui.slider(ctx, x, y, w, "centre bias", &o.bias, 0, 1) or changed;
            y += ROW_H + SLIDER_DROP;
        },
        .ring => {
            changed = centreRows(ctx, x, &y, w, o, 1) or changed;
            changed = ui.stepperF(ctx, x, y, w, "radius", &o.r0, 0.5, 0.5, 200) or changed;
            y += ROW_H;
            changed = ui.stepperI(ctx, x, y, w, "count", &o.n, 1, 2, RING_N_MAX) or changed;
            y += ROW_H;
            changed = ui.stepperI(ctx, x, y, w, "gap at", &o.skip, 1, -1, RING_N_MAX - 1) or changed;
            y += ROW_H;
        },
        .line => {
            changed = spanRows(ctx, x, &y, w, o) or changed;
            changed = ui.stepperF(ctx, x, y, w, "step", &o.r0, 0.25, 0.5, 40) or changed;
            y += ROW_H;
            changed = ui.slider(ctx, x, y, w, "stands", &o.chance, 0, 1) or changed;
            y += ROW_H + SLIDER_DROP;
        },
        .edge => {
            changed = ui.stepperF(ctx, x, y, w, "step", &o.r0, 0.25, 1, 20) or changed;
            y += ROW_H;
            changed = ui.stepperI(ctx, x, y, w, "talus", &o.n, 5, 0, 600) or changed;
            y += ROW_H;
        },
    }

    if (o.op != .at) {
        changed = ui.stepperF(ctx, x, y, w, "scale lo", &o.sLo, 0.05, 0.1, 3) or changed;
        y += ROW_H;
        changed = ui.stepperF(ctx, x, y, w, "scale hi", &o.sHi, 0.05, 0.1, 3) or changed;
        y += ROW_H;
        if (changed and o.sHi < o.sLo) o.sHi = o.sLo;
        changed = ui.stepperF(ctx, x, y, w, "lean max", &o.lean, 1, 0, LEAN_LIM) or changed;
        y += ROW_H;
        var sb: [40]u8 = undefined;
        const seedLab = std.fmt.bufPrintZ(&sb, "seed {d}", .{o.seed}) catch "";
        hud.mono(seedLab, x, y + 4, hud.MONO, ui.LABEL);
        if (ui.buttonTip(ctx, ui.rect(x + w - 90, y, 90, 24), "re-roll", hud.MONO, false, "A different arrangement, same meaning (R)")) {
            ed.rerollSel(m, env);
            return;
        }
        y += ROW_H + 6;

        hud.mono("keeps off", x, y, hud.MONO, ui.alpha(ui.TRIM, 220));
        y += hud.monoLineH(hud.MONO);
        changed = ui.checkbox(ctx, x, y, "runway", &o.avoid.runway) or changed;
        y += 22;
        changed = ui.checkbox(ctx, x, y, "water", &o.avoid.water) or changed;
        y += 22;
        changed = ui.checkbox(ctx, x, y, "clearings", &o.avoid.clear) or changed;
        y += 22;
        changed = ui.checkbox(ctx, x, y, "solids", &o.avoid.solid) or changed;
        y += 22;
        if (o.op == .belt or o.op == .disc) {
            changed = ui.checkbox(ctx, x, y, "cover field", &o.field) or changed;
            y += 26;
            changed = gradientRows(ctx, x, &y, w, o) or changed;
        }
    }

    if (ui.buttonTip(ctx, ui.rect(x, y, 44, 24), "up", hud.MONO, false, "Run EARLIER - order decides what later ops can see")) {
        if (s > 0) {
            ed.bank(m);
            m.reorder(s, s - 1);
            ed.sel = s - 1;
            ed.rebuild(m, env);
        }
        return;
    }
    if (ui.buttonTip(ctx, ui.rect(x + 48, y, 60, 24), "down", hud.MONO, false, "Run LATER")) {
        if (s + 1 < m.nops) {
            ed.bank(m);
            m.reorder(s, s + 1);
            ed.sel = s + 1;
            ed.rebuild(m, env);
        }
        return;
    }
    if (ui.buttonTip(ctx, ui.rect(x + w - 80, y, 80, 24), "delete", hud.MONO, false, "Remove this op (Del)")) {
        ed.deleteSel(m, env);
        return;
    }

    if (changed) {
        ed.bankGesture(wf.Op, m, o, before);
        ed.requestRebuild();
    } else if (!ctx.down) {
        ed.endGesture(m, env);
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
    rl.drawRectangle(px, py, MINI_W - 8, MINI_W - 8, ui.col(18, 20, 14, 255));

    blitField(m.soil[0..], wf.SOIL_N, px, py, inner, null);
    if (env.heightAny) {
        const rCellPx = inner / @as(f32, @floatFromInt(RELIEF_N));
        for (0..RELIEF_N) |cz| {
            for (0..RELIEF_N) |cx| {
                const i = (cz * RELIEF_STRIDE) * wf.HEIGHT_N + cx * RELIEF_STRIDE;
                const h = wf.heightOf(m.height[i]);
                if (@abs(h) < wf.HEIGHT_STEP) continue;
                // Saturating at ±12 m, which is a hill you would notice; past that it is just white.
                const k = mathx.clampF(h / 12.0, -1, 1);
                const a: u8 = mathx.u8f(@abs(k) * 150.0);
                const col = if (k > 0) ui.col(236, 226, 200, a) else ui.col(18, 14, 10, a);
                rl.drawRectangleRec(.{
                    .x = @as(f32, @floatFromInt(px)) + @as(f32, @floatFromInt(cx)) * rCellPx,
                    .y = @as(f32, @floatFromInt(py)) + @as(f32, @floatFromInt(cz)) * rCellPx,
                    .width = @ceil(rCellPx),
                    .height = @ceil(rCellPx),
                }, col);
            }
        }
    }
    blitField(m.water[0..], wf.WATER_N, px, py, inner, WATER_SWATCH);

    const toMini = struct {
        fn f(wx: f32, wz: f32, half: f32, ox: i32, oy: i32, span: f32) rl.Vector2 {
            return .{
                .x = @as(f32, @floatFromInt(ox)) + (wx + half) / (2 * half) * span,
                .y = @as(f32, @floatFromInt(oy)) + (wz + half) / (2 * half) * span,
            };
        }
    }.f;

    const onMap = struct {
        fn f(wx: f32, wz: f32, half: f32) bool {
            return @abs(wx) <= half and @abs(wz) <= half;
        }
    }.f;

    for (m.ops[0..m.nops]) |*o| {
        if (o.op == .edge) continue;
        if (!onMap(o.x, o.z, m.half)) continue;
        const p = toMini(o.x, o.z, m.half, px, py, inner);
        const mine = layerOf(o) == ed.layer;
        const col = if (layerOf(o) == .decor) ui.col(96, 132, 70, if (mine) 235 else 70) else ui.col(168, 156, 130, if (mine) 235 else 70);
        rl.drawRectangleV(.{ .x = p.x - 1, .y = p.y - 1 }, .{ .x = 2, .y = 2 }, col);
    }
    for (m.foes[0..m.nfoes]) |f| {
        if (!onMap(f.x, f.z, m.half)) continue;
        const p = toMini(f.x, f.z, m.half, px, py, inner);
        rl.drawCircleV(p, 2.5, ui.col(220, 120, 90, if (ed.layer == .units) 255 else 110));
    }
    const cp = toMini(
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

const WATER_SWATCH = ui.col(32, 55, 62, 255);

const RELIEF_N: usize = 56;
const RELIEF_STRIDE: usize = wf.HEIGHT_N / RELIEF_N;
comptime {
    std.debug.assert(RELIEF_N * RELIEF_STRIDE == wf.HEIGHT_N);
}

fn blitField(cells: []const u8, n: usize, px: i32, py: i32, inner: f32, paint: ?rl.Color) void {
    // Both callers pass a comptime grid width, so this cannot fire today — it is here because the same
    // shape (a divide by a caller's count) was a live crash in `book.rowStep`, reached through a picker
    // whose candidate list came back empty. A third caller with a runtime `n` is one line away from it.
    if (n == 0) return;
    const cellPx = inner / @as(f32, @floatFromInt(n));
    for (0..n) |cz| {
        const row = cells[cz * n ..][0..n];
        var cx: usize = 0;
        while (cx < n) {
            const id = row[cx];
            if (id == 0) {
                cx += 1;
                continue;
            }
            var run: usize = 1;
            while (cx + run < n and (if (paint == null) row[cx + run] == id else row[cx + run] != 0)) run += 1;
            rl.drawRectangleRec(.{
                .x = @as(f32, @floatFromInt(px)) + @as(f32, @floatFromInt(cx)) * cellPx,
                .y = @as(f32, @floatFromInt(py)) + @as(f32, @floatFromInt(cz)) * cellPx,
                .width = @ceil(@as(f32, @floatFromInt(run)) * cellPx),
                .height = @ceil(cellPx),
            }, paint orelse soilSwatch(@enumFromInt(id)));
            cx += run;
        }
    }
}

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
    // MEASURED ONCE: four compile-time literals against a size that never moves, re-measured every frame.
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
    "LMB brush   Shift+LMB drag marquee   RMB menu / deselect, drag rotates   wheel zoom   WASD+arrows pan   Tab layer   ,/. time   Esc back",
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
            if (ui.button(ctx, ui.rect(box.x + DLG_PAD, by, 120, DLG_BTN_H), "Save first", hud.MONO, false) or confirm) {
                if (ed.saveNow(m)) {
                    const what = ed.pending;
                    ed.modal = .none;
                    ed.commitPending(what);
                }
                return;
            }
            if (ui.button(ctx, ui.rect(box.x + 154, by, 120, DLG_BTN_H), "Discard", hud.MONO, false)) {
                const what = ed.pending;
                ed.dirty = false;
                ed.modal = .none;
                ed.commitPending(what);
                return;
            }
            if (ui.button(ctx, ui.rect(box.x + 300, by, 120, DLG_BTN_H), "Cancel", hud.MONO, false)) {
                ed.modal = .none;
                ed.pending = .none;
            }
        },
        .loot => {
            // **TABBED BY CLASS** (owner: organize the item menus by type). Thirty-seven items in one column
            // ran off the bottom of a 1080 screen and was unreadable besides — `item.Class` is the shelf a
            // thing belongs on and it already exists, so the picker uses it rather than inventing an order.
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
            const box = ui.beginModal(ctx, 470, LOOT_TOP + TAB_H + rows * LOOT_ROW_H + 8 + DLG_FOOT, title);
            const s = sPre;
            const o = &m.ops[s];
            var buf: [48]u8 = undefined;
            const total = std.fmt.bufPrintZ(&buf, "{d} / {d} items", .{ o.nloot, wf.MAX_LOOT }) catch "";
            hud.mono(total, box.x + DLG_PAD, box.y + 58, hud.MONO, ui.LABEL);

            // The tabs. A class carrying something already in this container is marked, so you can find what
            // you put in without walking every shelf.
            const CLASSES = [_]item.Class{ .tool, .gear, .material, .treasure, .key };
            const tabW: i32 = @divTrunc(470 - DLG_PAD * 2, @as(i32, CLASSES.len));
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
                const r = ui.rect(box.x + DLG_PAD + @as(i32, @intCast(ci)) * tabW, box.y + LOOT_TOP - TAB_H, tabW - 3, TAB_H - 4);
                if (ui.buttonTip(ctx, r, lab, hud.MONO, ed.lootTab == c, "Show this shelf - a * means this container already holds one")) ed.lootTab = c;
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
                if (ui.button(ctx, ui.rect(box.x + 368, y, 24, 22), "-", hud.MONO, false) and n > 0) {
                    ed.bank(m);
                    lootRemove(o, k);
                }
                if (ui.button(ctx, ui.rect(box.x + 396, y, 24, 22), "+", hud.MONO, false) and o.nloot < wf.MAX_LOOT) {
                    ed.bank(m);
                    lootAdd(o, k);
                }
            }
            if (ui.button(ctx, ui.rect(box.x + DLG_PAD, box.y + box.h - DLG_FOOT, 120, DLG_BTN_H), "Done", hud.MONO, false) or confirm) {
                ed.modal = .none;
            }
        },
        .boss => {
            const NF = @typeInfo(wf.FoeKind).@"enum".fields.len;
            const rows: i32 = NF + 1;
            const sPre = bossOp(ed, m) orelse {
                ed.modal = .none;
                return;
            };
            const box = ui.beginModal(ctx, 470, LOOT_TOP + rows * LOOT_ROW_H + 8 + DLG_FOOT, "Sealed until this dies");
            const o = &m.ops[sPre];
            hud.mono(
                "He walks through it once, then nothing does until this is dead",
                box.x + DLG_PAD,
                box.y + 58,
                hud.MONO,
                ui.LABEL,
            );
            // Row 0 is the OPT-OUT, and it has to exist: a gate with no boss is an ordinary doorway, which is
            // what a gate hung anywhere but an arena mouth needs to be.
            var i: usize = 0;
            while (i < rows) : (i += 1) {
                const pick: ?wf.FoeKind = if (i == 0) null else @enumFromInt(i - 1);
                const y = box.y + LOOT_TOP + @as(i32, @intCast(i)) * LOOT_ROW_H;
                const label: [:0]const u8 = if (pick) |k| wf.foeName(k) else "Never shuts";
                const on = wf.eqlBoss(o.boss, pick);
                hud.mono(label, box.x + DLG_PAD, y + 5, hud.MONO, if (on) ui.VALUE else ui.LABEL);
                if (ui.button(ctx, ui.rect(box.x + 368, y, 52, 22), if (on) "set" else "pick", hud.MONO, on) and !on) {
                    ed.bank(m);
                    o.boss = pick;
                }
            }
            if (ui.button(ctx, ui.rect(box.x + DLG_PAD, box.y + box.h - DLG_FOOT, 120, DLG_BTN_H), "Done", hud.MONO, false) or confirm) {
                ed.modal = .none;
            }
        },
        .zonemix => {
            const rows: i32 = @intCast(props.FLORA_KINDS.len);
            const box = ui.beginModal(ctx, 470, LOOT_TOP + rows * LOOT_ROW_H + 8 + DLG_FOOT, "What grows here");
            const zi = ed.zoneSel orelse {
                ed.modal = .none;
                return;
            };
            if (zi >= m.nzones) {
                ed.modal = .none;
                return;
            }
            const z = &m.zones[zi];
            var hb: [64]u8 = undefined;
            hud.mono(
                std.fmt.bufPrintZ(&hb, "{s} - {d} / {d} picks", .{ z.label(), z.nmix, wf.MAX_MIX }) catch "",
                box.x + DLG_PAD,
                box.y + 58,
                hud.MONO,
                ui.LABEL,
            );
            for (props.FLORA_KINDS, 0..) |k, i| {
                const y = box.y + LOOT_TOP + @as(i32, @intCast(i)) * LOOT_ROW_H;
                const n = mixCount(z, k);
                hud.mono(props.displayName(k), box.x + DLG_PAD, y + 5, hud.MONO, if (n > 0) ui.VALUE else ui.LABEL);
                var nbuf: [8]u8 = undefined;
                hud.mono(std.fmt.bufPrintZ(&nbuf, "{d}", .{n}) catch "0", box.x + 340, y + 5, hud.MONO, if (n > 0) ui.VALUE else ui.LABEL);
                if (ui.button(ctx, ui.rect(box.x + 368, y, 24, 22), "-", hud.MONO, false) and n > 0) {
                    ed.bank(m);
                    mixRemove(z, k);
                    ed.requestRebuild();
                }
                if (ui.button(ctx, ui.rect(box.x + 396, y, 24, 22), "+", hud.MONO, false) and z.nmix < wf.MAX_MIX) {
                    ed.bank(m);
                    mixAdd(z, k);
                    ed.requestRebuild();
                }
            }
            if (ui.button(ctx, ui.rect(box.x + DLG_PAD, box.y + box.h - DLG_FOOT, 120, DLG_BTN_H), "Done", hud.MONO, false) or confirm) {
                ed.modal = .none;
            }
        },
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
            changed = ui.stepperF(ctx, x, y, w, "half extent", &m.half, 5, 40, wf.MAX_DECLARED_HALF) or changed;
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
            changed = ui.stepperF(ctx, x, y, w, "x0", &m.runway.x, 0.5, -COORD_LIM, COORD_LIM) or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "z0", &m.runway.z, 0.5, -COORD_LIM, COORD_LIM) or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "x1", &m.runway.x1, 0.5, -COORD_LIM, COORD_LIM) or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "z1", &m.runway.z1, 0.5, -COORD_LIM, COORD_LIM) or changed;
            y += ROW_H + 10;

            // **THE HOUR, WHERE YOU CAN FIND IT** (owner: add way to change time of day in editor — world menu).
            // `,`/`.` have scrubbed it since the editor had a clock, and a shortcut nobody is told about is a
            // feature nobody has: the world's LIGHT is a property of the world, so it belongs on this card
            // beside its size. The keys stay, and the crib names them — the editor is AGENTS.md's one
            // keyboard exception, and sweeping the day is still the gesture the stepper cannot be.
            hud.mono("LIGHT", x, y, hud.MONO, ui.TITLE);
            y += ROW_H + 4;
            var cb: [10]u8 = undefined;
            var lb: [80]u8 = undefined;
            hud.mono(
                std.fmt.bufPrintZ(&lb, "{s}  {s}  -  ',' '.' scrub, Shift for hours", .{
                    daynight.clockTextZ(day.hour, &cb),
                    daynight.phaseName(day.hour),
                }) catch "",
                x,
                y,
                hud.MONO,
                ui.alpha(ui.LABEL, 190),
            );
            y += hud.monoLineH(hud.MONO) + 4;
            var hourNow = day.hour;
            if (ui.stepperF(ctx, x, y, w, "hour", &hourNow, HOUR_STEP, 0, 24)) day.set(hourNow);
            y += ROW_H;
            {
                const bw: i32 = @divTrunc(w - 3 * 6, 4);
                for (HOUR_MARKS, 0..) |mk, i| {
                    const bx = x + @as(i32, @intCast(i)) * (bw + 6);
                    const on = @abs(day.hour - mk.at) < HOUR_STEP * 0.5;
                    if (ui.buttonTip(ctx, ui.rect(bx, y, bw, 24), mk.name, hud.MONO, on, mk.tip)) day.set(mk.at);
                }
                y += ROW_H + 10;
            }

            hud.mono("RIM", x, y, hud.MONO, ui.TITLE);
            y += ROW_H + 4;
            var rims: usize = 0;
            for (m.slice()) |*o| {
                if (o.op == .edge) rims += 1;
            }
            var rb: [64]u8 = undefined;
            hud.mono(
                std.fmt.bufPrintZ(&rb, "{d} cliff rim op{s} in the world", .{ rims, if (rims == 1) "" else "s" }) catch "",
                x,
                y,
                hud.MONO,
                ui.alpha(ui.LABEL, 170),
            );
            y += hud.monoLineH(hud.MONO) + 6;
            if (ui.buttonTip(ctx, ui.rect(x, y, 190, 24), "Add cliff rim", hud.MONO, false, "A ring of cliffs round the world's edge - what a new map is given, and the one op no brush could make")) {
                if (m.nops >= wf.MAX_OPS) {
                    ed.say(FULL_MSG);
                } else {
                    ed.bank(m);
                    if (m.add(freshRim(ed, m))) |_| {
                        ed.rebuild(m, env);
                        ed.say("+rim");
                    } else |_| ed.say(FULL_MSG);
                }
            }

            if (changed) {
                ed.bankWorld(m, halfBefore, before);
                // A size change moves the painted grids as well as the props, so it is the FULL rebuild and
                // not just a re-materialize: `half` is what every one of those uploads is measured in.
                ed.rebuild(m, env);
            } else if (!ctx.down) ed.endGesture(m, env);

            if (ui.button(ctx, ui.rect(box.x + DLG_PAD, box.y + box.h - DLG_FOOT, 120, DLG_BTN_H), "Done", hud.MONO, false) or confirm) {
                ed.modal = .none;
            }
        },
        .jukebox => {
            const box = ui.beginModal(ctx, JUKE_W, JUKE_H, "Sounds");
            if (ui.list(ctx, ui.rect(box.x + 20, box.y + 56, JUKE_LIST_W, JUKE_LIST_H), &VOICE_NAMES, ed.juke, &ed.jukeScroll)) |i| {
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
            // THE DIALS THEMSELVES, not a readout of them. Each answers under the finger — none of these
            // re-renders the take, which is what separates them from the rack below.
            inline for (@typeInfo(sfx.Dial).@"enum".fields) |dfld| {
                const d: sfx.Dial = @enumFromInt(dfld.value);
                const spec = sfx.dialSpec(d);
                var v = sfx.dialOf(vid, d);
                if (ui.slider(ctx, cx, cy, JUKE_COL_W, spec.name, &v, spec.lo, spec.hi)) sfx.setDial(vid, d, v);
                cy += RACK_ROW;
            }
            cy += 4;
            // …and what a row IS rather than how it sounds: `vars` and `poly` size the alias table that
            // frees it, so they are not on the bench at all (`audio.live`).
            const shape = std.fmt.bufPrintZ(&buf, "{d} takes x {d} voices, {s}", .{ nfo.vars, nfo.poly, @tagName(nfo.mix) }) catch "";
            hud.mono(shape, cx, cy, hud.MONO, ui.alpha(ui.LABEL, 170));
            cy += ROW_H + 6;
            _ = ui.checkbox(ctx, cx, cy, "play out in the world", &ed.jukeWorld);
            cy += ROW_H;
            const ds = if (ed.jukeWorld)
                (std.fmt.bufPrintZ(&buf, "at the focus, {d:.0} m out - zoom to move it", .{ed.dist}) catch "")
            else
                "at the ear";
            hud.mono(ds, cx, cy, hud.MONO, ui.alpha(ui.LABEL, 170));
            cy += ROW_H + 8;
            if (ui.buttonTip(ctx, ui.rect(cx, cy, 150, 22), "Revert voice", hud.MONO, !edited, "Back to the numbers in the code - the originals are never overwritten")) {
                sfx.revertVoice(vid);
                ed.jukePlay();
            }
            if (ui.buttonTip(ctx, ui.rect(cx + 158, cy, 130, 22), "Revert all", hud.MONO, !sfx.anyVoiceEdited(), "Every voice in the game back to the code")) sfx.revertAllVoices();
            rackPanel(ed, ctx, box.x + JUKE_W - RACK_W - 20, box.y + 56, vid);

            const by = box.y + box.h - DLG_FOOT;
            if (ui.button(ctx, ui.rect(box.x + 20, by, 150, DLG_BTN_H), "Play again", hud.MONO, false) or confirm) ed.jukePlay();
            if (ui.buttonTip(ctx, ui.rect(box.x + 180, by, 120, DLG_BTN_H), "Save", hud.MONO, false, "Write the edited voices over settings.cfg")) {
                sfx.saveSettings();
                ed.say("sounds saved");
            }
            if (ui.button(ctx, ui.rect(box.x + 310, by, 120, DLG_BTN_H), "Done", hud.MONO, false)) {
                sfx.saveSettings();
                ed.modal = .none;
            }
            hud.mono("up / down step and play, space replays", box.x + 450, by + 6, hud.MONO, ui.alpha(ui.LABEL, 150));
        },
        .new_map, .save_as => {
            const isNew = ed.modal == .new_map;
            const box = ui.beginModal(ctx, 460, 180, if (isNew) "New map" else "Save map as");
            hud.mono("name", box.x + DLG_PAD, box.y + 58, hud.MONO, ui.LABEL);
            ui.textField(ctx, ui.rect(box.x + DLG_PAD, box.y + 82, 412, 30), &ed.nameBuf, &ed.nameLen, true);
            var buf: [wf.PATH_CAP]u8 = undefined;
            const p = wf.pathFor(&buf, ed.nameBuf[0..ed.nameLen]);
            var pz: [wf.PATH_CAP + 4]u8 = undefined;
            const ps = std.fmt.bufPrintZ(&pz, "{s}", .{p}) catch "";
            hud.mono(ps, box.x + DLG_PAD, box.y + 118, hud.MONO, ui.alpha(ui.LABEL, 190));
            const by = box.y + box.h - DLG_FOOT;
            const go = ui.button(ctx, ui.rect(box.x + DLG_PAD, by, 130, DLG_BTN_H), if (isNew) "Create" else "Save", hud.MONO, false);
            if (go or confirm) {
                ed.modal = .none;
                if (isNew) ed.doNew(m, env) else ed.doSaveAs(m);
                return;
            }
            if (ui.button(ctx, ui.rect(box.x + 164, by, 120, DLG_BTN_H), "Cancel", hud.MONO, false)) ed.modal = .none;
        },
        .open_map => {
            const box = ui.beginModal(ctx, 460, 380, "Open map");
            var labels: [wf.MAX_FILES][:0]const u8 = undefined;
            for (0..listing.n) |i| labels[i] = listing.name(i);
            if (listing.n == 0) {
                hud.mono("no maps in worlds/", box.x + DLG_PAD, box.y + 62, hud.MONO, ui.LABEL);
            } else if (ui.list(ctx, ui.rect(box.x + DLG_PAD, box.y + 54, 412, 258), labels[0..listing.n], ed.fileSel, &ed.fileScroll)) |i| {
                ed.fileSel = i;
            }
            const by = box.y + box.h - DLG_FOOT;
            if ((ui.button(ctx, ui.rect(box.x + DLG_PAD, by, 130, DLG_BTN_H), "Open", hud.MONO, false) or confirm) and listing.n > 0) {
                ed.modal = .none;
                ed.doOpen(m, env, ed.fileSel);
                return;
            }
            if (ui.button(ctx, ui.rect(box.x + 164, by, 120, DLG_BTN_H), "Cancel", hud.MONO, false)) ed.modal = .none;
        },
        .objects => {
            if (!objview.draw(&ed.objects, env, scene, ctx)) ed.modal = .none;
        },
    }
}

const MenuItem = enum { view, loot, boss, focus, reroll, duplicate, delete, close };

const menuRows = [_]struct { act: MenuItem, label: [:0]const u8 }{
    .{ .act = .view, .label = "View..." },
    .{ .act = .loot, .label = "Items..." },
    .{ .act = .boss, .label = "Sealed by..." },
    .{ .act = .focus, .label = "Focus" },
    .{ .act = .reroll, .label = "Re-roll" },
    .{ .act = .duplicate, .label = "Duplicate" },
    .{ .act = .delete, .label = "Delete" },
    .{ .act = .close, .label = "Close" },
};

const MENU_W: i32 = 150;
const MENU_EDGE: i32 = 4;


fn lootOp(ed: *const Editor, m: *const wf.Map) ?usize {
    const s = ed.sel orelse return null;
    if (s >= m.nops) return null;
    return if (m.ops[s].op == .at and props.holdsLoot(m.ops[s].kind)) s else null;
}

/// A GATE'S SEAL IS EDITED WHERE ITS LOOT WOULD BE, and it is offered on the same test the mechanic reads
/// (`props.Info.ward`) rather than on the kind by name, so a second ward kind gets the panel for free.
fn bossOp(ed: *const Editor, m: *const wf.Map) ?usize {
    const s = ed.sel orelse return null;
    if (s >= m.nops) return null;
    return if (m.ops[s].op == .at and props.info(m.ops[s].kind).ward) s else null;
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

const WORLD_W: i32 = 420;
const WORLD_H: i32 = 470 + 96;

const HOUR_STEP: f32 = 0.25;
/// THE HOURS WORTH AUTHORING AT. The anchor is not negotiable (every albedo in the game was measured under
/// it); the other three are the lights a belt of flora has to survive.
const HourMark = struct { name: [:0]const u8, at: f32, tip: [:0]const u8 };
const HOUR_MARKS = [_]HourMark{
    .{ .name = "Dawn", .at = 6.5, .tip = "First light - the coldest key in the day" },
    .{ .name = "Noon", .at = 12.0, .tip = "Overhead and white: the hour with no long shadows to hide a gap" },
    .{ .name = "Anchor", .at = daynight.SHOT_HOUR, .tip = "The golden hour every albedo in the game was measured under (--shot pins it)" },
    .{ .name = "Night", .at = 0.5, .tip = "Moonlight - what the fires have to carry" },
};

fn freshRim(ed: *Editor, m: *const wf.Map) wf.Op {
    var rim = wf.Map.defaultRim();
    rim.seed = ed.freshSeed(m);
    return rim;
}

/// The eleven dials, over either a FAMILY or the ONE VOICE the bench has selected. Same rack both ways on
/// purpose: a filter that behaved differently depending on whose it was would be two things sharing a name.
fn rackPanel(ed: *Editor, ctx: *ui.Ctx, x: i32, y0: i32, voice: ?sfx.Id) void {
    var y = y0;
    hud.mono("FILTER RACK", x, y, hud.MONO, ui.TITLE);
    y += ROW_H + 4;

    // WHOSE rack. The same three families, in the same order, as the volume sliders in the game's options —
    // "which slider moves this" and "which rack filters it" must never disagree — plus, on the bench, the
    // selected voice itself, which is filtered on TOP of its family.
    var cx = x;
    inline for (@typeInfo(sfx.Submix).@"enum".fields) |fld| {
        const mx: sfx.Submix = @enumFromInt(fld.value);
        var usedW: i32 = 0;
        if (ui.chip(ctx, cx, y, @tagName(mx), !ed.rackOnVoice and ed.rackMix == mx, &usedW)) {
            ed.rackMix = mx;
            ed.rackOnVoice = false;
        }
        cx += usedW;
    }
    if (voice != null) {
        var usedW: i32 = 0;
        if (ui.chip(ctx, cx, y, "this voice", ed.rackOnVoice, &usedW)) ed.rackOnVoice = true;
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
        if (ui.slider(ctx, cxx, cyy, colW, lab, &v, 0, 1)) {
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
        if (ui.button(ctx, ui.rect(bx, by, RACK_W / 2 - 4, 22), pre.n, hud.MONO, false)) {
            if (onVoice) sfx.applyVoiceFxPreset(vid, pre.p) else sfx.applyFxPreset(ed.rackMix, pre.p);
        }
    }
    y += 26 * 3 + 4;
    // A VOICE'S OWN DEFAULT IS OFF, and the caption has to say so. Its rack is applied ON TOP of the
    // family's, so "the house sound" is what the family is already giving it — the two buttons genuinely do
    // one thing here, and a tip promising a preset the press does not apply is the lie worth fixing.
    const dflt: [:0]const u8 = if (onVoice)
        "This voice adds nothing of its own - the family's rack still applies"
    else
        "Back to the house sound (worn tape)";
    if (ui.buttonTip(ctx, ui.rect(x, y, RACK_W / 2 - 4, 22), "Default", hud.MONO, false, dflt)) {
        if (onVoice) sfx.voiceFxOff(vid) else sfx.resetFx(ed.rackMix);
    }
    if (ui.buttonTip(ctx, ui.rect(x + RACK_W / 2 + 4, y, RACK_W / 2 - 4, 22), "All Off", hud.MONO, false, "Every dial to zero - drier than the game ships")) {
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

/// A slider is a LABEL LINE plus a 12 px bar plus its seat, so the row has to clear both — at 30 the bars
/// sat on the next label. MEASURED off `ui.slider`'s own layout rather than guessed.
const RACK_ROW: i32 = ui.ROW_H + 14;

fn menuEnabled(ed: *const Editor, m: *const wf.Map, act: MenuItem) bool {
    const op: ?usize = if (ed.sel) |s| (if (s < m.nops) s else null) else null;
    return switch (act) {
        .close => true,
        .focus => op != null,
        .view => op != null,
        .loot => lootOp(ed, m) != null,
        .boss => bossOp(ed, m) != null,
        .reroll, .duplicate => if (op) |s| isMovable(&m.ops[s]) else false,
        .delete => op != null or (ed.layer == .units and ed.selFoe != null),
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
            ui.disabled(ctx, r, label, hud.MONO);
            continue;
        }
        if (!ui.button(ctx, r, label, hud.MONO, false)) continue;
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
    // Four spawns in a row, 4 m apart, well outside one brush of each other.
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

