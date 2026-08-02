const std = @import("std");
const rl = @import("raylib");
const hud = @import("hud.zig");
const mathx = @import("mathx.zig");
const props = @import("props.zig");
const ui = @import("ui.zig");
const wf = @import("worldfmt.zig");
const envmod = @import("env.zig");
const gfx = @import("gfx.zig");
const objview = @import("objview.zig");
const item = @import("item.zig"); // the chest-contents dialog
const sfx = @import("audio.zig"); // the jukebox

const Kind = props.Kind;
const v3 = mathx.v3;

// EDITOR — an in-game scene over the live world.

const LOOK_SENS: f32 = 0.0032;
const UNDO_CAP: usize = 24;
const DRAG_PX = ui.DRAG_PX; // the shared click-vs-drag threshold (see there)
const SNAP: f32 = 1.0; // grid pitch when snap is on
/// How long a held dial must go QUIET before the world re-expands. A DEBOUNCE, not a throttle: at 5 Hz a stepper on key-repeat re-materialized all 17k props five times a second, and every one of those was thrown away by the next nudge. The gizmo reads the MAP, so the dial still answers instantly (see `drawOpGizmo`) — it is only the expansion that waits, and `endGesture` flushes it on release so the world always settles on the value you let go of.
const REBUILD_QUIET: f32 = 0.9;

/// How often the held eraser may remove something — its own rate, not the rebuild's.
const ERASE_HZ: f32 = 5.0;
/// …and how far the cursor must travel between two removals.
const ERASE_STEP: f32 = 0.6;
/// Most instance markers drawn for one selected generator.
const MAX_MARKERS: usize = 500;

/// WHAT THE CURSOR IS OVER in SELECT mode — the thing a click would take, lit before you click it.
const Hover = union(enum) { none, prop: usize, foe: usize };

/// Most things one marquee can hold, and most one clipboard can carry.
const MAX_MARKED: usize = 512;

/// The one wording for a full map, said by every path that can hit the cap.
const FULL_MSG = "map is full — worldfmt.MAX_OPS reached";

/// How far east a Duplicate lands from its original, so the copy isn't hidden under it.
const DUPE_OFFSET: f32 = 6.0;

/// Ground a Focus frames around a single literal prop, which has no extent of its own to measure.
const AT_SPAN: f32 = 6.0;

/// PEAK density a freshly dragged zone starts at — the same value `wf.Map.blank`'s fallback zone uses, so a zone you draw on a new map matches the ground it replaced instead of jumping.
const NEW_ZONE_DENSITY: f32 = 0.7;

/// How near the cursor has to be to a foe spawn to count as ON it.
const FOE_PICK_R: f32 = 1.6;

// Undo ring at file scope: a Map is ~386 KB (measured — the figure here said 230 KB, from before `soilCov` and the height lattice were added) and 24 of them is ~9.1 MB, which belongs in BSS rather than inside Game (~1.7 MB of Env alone) or on an allocator this codebase otherwise avoids. Three quarters of a snapshot is the four painted grids, and most edits touch none of them — if the ring ever has to shrink, DEPTH is the dial, not the snapshot.
var undoRing: [UNDO_CAP]wf.Map = undefined;
var undoBase: usize = 0; // ring slot of the OLDEST live snapshot
var undoN: usize = 0; // how many snapshots are live
var undoAt: usize = 0; // how far back we have stepped (0 = at the newest)

/// Snapshot `i` counting from the oldest, 0 <= i < undoN (or i == undoN, the slot about to be written).
fn undoSlot(i: usize) *wf.Map {
    return &undoRing[(undoBase + i) % UNDO_CAP];
}

/// Forget everything banked.
fn undoReset() void {
    undoBase = 0;
    undoN = 0;
    undoAt = 0;
}

/// Make room for one more snapshot when the ring is already full: the oldest is dropped.
fn undoDropOldest() void {
    undoBase = (undoBase + 1) % UNDO_CAP;
    undoN -= 1;
}

// THE CLIPBOARD, at file scope for the same reason and for one more: it deliberately OUTLIVES a map load, so you can copy a stand of trees out of one map and paste it into another.
var clipOps: [MAX_MARKED]wf.Op = undefined;
var nClipOps: usize = 0;
var clipFoes: [MAX_MARKED]wf.Foe = undefined;
var nClipFoes: usize = 0;

var listing: wf.Listing = .{};


pub const Layer = enum(u8) {
    ground,
    cover,
    decor,
    props,
    interact,
    units,

    pub const N = @typeInfo(Layer).@"enum".fields.len;

    fn label(l: Layer) [:0]const u8 {
        return switch (l) {
            .ground => "Ground",
            .cover => "Cover",
            .decor => "Decor",
            .props => "Props",
            .interact => "Interactables",
            .units => "Units",
        };
    }

    /// THE LAYERS WHOSE CONTENT IS OPS.
    fn opLayer(l: Layer) bool {
        return switch (l) {
            .decor, .props, .interact => true,
            .ground, .cover, .units => false,
        };
    }
};

const layerTips = [Layer.N][:0]const u8{
    "SHAPE the land and paint the soil under everything (Tab cycles layers)",
    "The flora carpet: zone density and the clearings it keeps out of",
    "Growing things — ferns, grass, bramble, reeds",
    "Standing things — stone, timber, fire, water",
    "Things the player OPENS — chests, and what is in them (right-click > Items…)",
    "Foe spawns",
};

// Brush tables.
const groundBrushes = [_][:0]const u8{ "Raise", "Lower", "Smooth", "Flat", "dirt", "turf", "stone", "silt", "ash", "moss", "Water", "Erase" };
const coverBrushes = [_][:0]const u8{ "Clearing", "Zone", "Erase" };
const decorBrushes = [_][:0]const u8{ "Single", "Patch", "Scatter", "Erase" };
const propBrushes = [_][:0]const u8{ "Stamp", "Row", "Ring", "Cluster", "Ivy", "Erase" };
// INTERACTABLES place ONE AT A TIME, and deliberately have no scatter: a chest's contents are the op's own (`Op.loot`), so a generator would put the identical list in every box it grew.
const interactBrushes = [_][:0]const u8{ "Stamp", "Erase" };
// THE FOES' REAL NAMES, off `wf.foeName` — not their enum tags.
const unitBrushes = blk: {
    const N = @typeInfo(wf.FoeKind).@"enum".fields.len;
    var out: [N + 1][:0]const u8 = undefined;
    for (0..N) |i| out[i] = wf.foeName(@enumFromInt(i));
    out[N] = "Erase";
    break :blk out;
};

/// Where the SOIL ids start in `groundBrushes`, since the sculpt tools now come first.
const GROUND_SOIL_0: usize = 4;

/// SMOOTH and FLATTEN take a 0..1 blend where raise/lower take metres, so they need their own scale off the one `sculptRate` dial.
const SCULPT_EVEN: f32 = 0.5;

/// How many brushes the number keys reach — 1..9.
const DIGIT_KEYS: usize = 9;

// The three sculpt swatches (literal screen values, like every other chrome colour — see ui.zig): earth lifted, earth cut away, and the neutral grey shared by the two tools that even ground out.
const RAISE_SWATCH = ui.col(126, 100, 62, 255);
const LOWER_SWATCH = ui.col(74, 60, 44, 255);
const EVEN_SWATCH = ui.col(96, 100, 104, 255);

const groundTips = [_][:0]const u8{
    "Hold and sweep to RAISE the ground — [ ] sets the brush size, and the panel sets how hard",
    "Hold and sweep to dig the ground DOWN",
    "Hold and sweep to SMOOTH what you sculpted — this is what turns a lump into a slope you can walk",
    "Hold and sweep to FLATTEN toward the height you started the stroke on — terraces, pads, roads",
    "Trodden dirt — a path worn through ([ ] sets radius)",
    "Green turf",
    "Stone, flagged or scoured bare",
    "Pale silt, the tarn's margin",
    "Ash and burnt ground",
    "Deep moss",
    "Hold and sweep to flood — depth, shore and wet sand are all worked out from the outline",
    "Hold and sweep to unpaint soil AND water. It leaves the sculpted SHAPE alone",
};
const coverTips = [_][:0]const u8{
    "Drag a circle nothing grows in",
    "Drag a rectangle the ground cover grows differently inside",
    "Hold and sweep to remove the zones and clearings you cross",
};
const decorTips = [_][:0]const u8{
    "Click to place ONE plant, exactly there",
    "Drag from the centre out for a round patch",
    "Drag a rectangle to sow a scattered belt inside it",
    "Hold and sweep to remove the ops that grew the plants you cross",
};
const propTips = [_][:0]const u8{
    "Click to stamp one prop, exactly there",
    "Drag a line for a broken run laid nose to tail",
    "Drag from the centre out for an evenly spaced circle",
    "Drag from the centre out for a scattered ring-shaped band",
    "Drag a box to sow ivy at the feet of the stone already standing in it",
    "Hold and sweep to remove the ops that placed the props you cross",
};
const interactTips = [_][:0]const u8{
    "Click to place one, exactly there — then right-click it > Items… to fill it",
    "Hold and sweep to remove the ones you cross",
};
const unitTips = [_][:0]const u8{
    "Post a gaping toad",
    "Post a skeletal archer",
    "Post the one-eyed ogre",
    "Post a kobold berserker — two axes, a wild flurry, then a long opening",
    "Post a kobold priest — no attack, heals the hurt one; break the cast",
    "Post a kobold slinger — stones at range, teeth up close",
    "Hold and sweep to remove spawns ([ ] sets radius)",
};

fn layerIcon(l: Layer) ui.Icon {
    return switch (l) {
        .ground => .ground,
        .cover => .cover,
        .decor => .decor,
        .props => .props,
        .interact => .interact,
        .units => .units,
    };
}

// Ground has no icon list — its brushes ARE colours, and `soilSwatch` is a truer icon for "moss" than any glyph (the four sculpt tools take a swatch too, tinted by what they do to the land).
const coverIcons = [_]ui.Icon{ .clearing, .zone, .erase };
const decorIcons = [_]ui.Icon{ .single, .patch, .scatter, .erase };
const propIcons = [_]ui.Icon{ .stamp, .row, .ring, .cluster, .ivy, .erase };
const interactIcons = [_]ui.Icon{ .stamp, .erase };
const unitIcons = [_]ui.Icon{ .toad, .archer, .ogre, .berserker, .priest, .slinger, .erase };

comptime {
    std.debug.assert(coverIcons.len == coverBrushes.len);
    std.debug.assert(decorIcons.len == decorBrushes.len);
    std.debug.assert(propIcons.len == propBrushes.len);
    std.debug.assert(interactIcons.len == interactBrushes.len);
    std.debug.assert(unitIcons.len == unitBrushes.len);
}

/// A SECTION HEADING to draw above brush `i`, or null for "no break here".
fn brushSectionFor(l: Layer, i: usize) ?[:0]const u8 {
    if (l != .ground) return null;
    if (i == 0) return "shape";
    if (i == GROUND_SOIL_0) return "surface";
    return null;
}

/// The icons for a layer's brush strip, or null for GROUND, whose caller draws swatches instead.
fn brushIconsFor(l: Layer) ?[]const ui.Icon {
    return switch (l) {
        .ground => null,
        .cover => &coverIcons,
        .decor => &decorIcons,
        .props => &propIcons,
        .interact => &interactIcons,
        .units => &unitIcons,
    };
}

fn brushesFor(l: Layer) []const [:0]const u8 {
    return switch (l) {
        .ground => &groundBrushes,
        .cover => &coverBrushes,
        .decor => &decorBrushes,
        .props => &propBrushes,
        .interact => &interactBrushes,
        .units => &unitBrushes,
    };
}

fn brushTipsFor(l: Layer) []const [:0]const u8 {
    return switch (l) {
        .ground => &groundTips,
        .cover => &coverTips,
        .decor => &decorTips,
        .props => &propTips,
        .interact => &interactTips,
        .units => &unitTips,
    };
}

comptime {
    std.debug.assert(layerTips.len == Layer.N);
    std.debug.assert(groundTips.len == groundBrushes.len);
    std.debug.assert(coverTips.len == coverBrushes.len);
    std.debug.assert(decorTips.len == decorBrushes.len);
    std.debug.assert(propTips.len == propBrushes.len);
    std.debug.assert(interactTips.len == interactBrushes.len);
    std.debug.assert(unitTips.len == unitBrushes.len);
    // The ground brushes carry the soil ids AS A RUN starting at GROUND_SOIL_0 (so soil id 1 = .dirt is the brush at that index), with the four sculpt tools ahead of them and WATER + the eraser behind.
    std.debug.assert(groundBrushes.len == GROUND_SOIL_0 + (wf.Soil.N - 1) + 2);
    for (0..wf.Soil.N - 1) |i| {
        std.debug.assert(std.mem.eql(u8, groundBrushes[GROUND_SOIL_0 + i], @tagName(@as(wf.Soil, @enumFromInt(i + 1)))));
    }
    // …and the four sculpt brushes ARE `wf.Sculpt`'s modes, in its order, so `GroundBrush` can be turned straight into one.
    const sculptN = @typeInfo(wf.Sculpt).@"enum".fields.len;
    std.debug.assert(GROUND_SOIL_0 == sculptN);
    // …and the unit brushes ARE the foe kinds in order, plus the eraser.
    std.debug.assert(unitBrushes.len == @typeInfo(wf.FoeKind).@"enum".fields.len + 1);
    for (0..@typeInfo(wf.FoeKind).@"enum".fields.len) |i| {
        const tag = @tagName(@as(wf.FoeKind, @enumFromInt(i)));
        // (The LABELS are `wf.foeName` by construction now, so there is nothing left to pin there.) …but THEIR ICONS still are, by NAME and not just by count.
        std.debug.assert(std.mem.eql(u8, @tagName(unitIcons[i]), tag));
    }
}

// Positional brush indices, matching the tables above.
pub const GroundBrush = enum { raise, lower, smooth, flat, dirt, turf, stone, silt, ash, moss, water, erase };
const CoverBrush = enum { clearing, zone, erase };
/// PUBLIC for the same reason `GroundBrush` is: the `--shot` harness arms brushes BY NAME.
pub const DecorBrush = enum { single, patch, scatter, erase };
const PropBrush = enum { stamp, row, ring, cluster, ivy, erase };
const InteractBrush = enum { stamp, erase };
const UnitBrush = enum { toad, archer, ogre, berserker, priest, slinger, erase };

comptime {
    // Every brush enum pinned to the table it indexes, case-insensitively so "Erase"/"Zone" read the way a button should while the tag stays Zig-shaped.
    pinBrushes(CoverBrush, &coverBrushes);
    pinBrushes(DecorBrush, &decorBrushes);
    pinBrushes(PropBrush, &propBrushes);
    pinBrushes(InteractBrush, &interactBrushes);
    pinBrushes(GroundBrush, &groundBrushes);
    // UNITS ARE PINNED TO `wf.FoeKind` INSTEAD, and that is the stronger statement of the two: its labels are the foes' real NAMES now (`wf.foeName`), so a label-to-tag comparison would only be asserting that "Giant Toad" is spelled "toad" — which is exactly what this layer stopped doing.
    const foeFields = @typeInfo(wf.FoeKind).@"enum".fields;
    const unitFields = @typeInfo(UnitBrush).@"enum".fields;
    if (unitFields.len != foeFields.len + 1) @compileError("editor: UnitBrush is not the foe kinds plus an eraser");
    for (foeFields, unitFields[0..foeFields.len]) |f, u| {
        if (!std.mem.eql(u8, f.name, u.name)) @compileError("editor: UnitBrush." ++ u.name ++ " is not wf.FoeKind." ++ f.name);
    }
    if (!std.mem.eql(u8, unitFields[unitFields.len - 1].name, "erase")) @compileError("editor: UnitBrush must end in `erase`");
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
    // The eraser is always LAST, which is what `erasing()` reads off the index.
    if (!std.mem.eql(u8, fields[fields.len - 1].name, "erase")) @compileError("editor: " ++ @typeName(E) ++ " must end in `erase`");
}

// THE KIND PALETTES live in props.zig now, beside the INFO table they are derived from — the object viewer needs the same lists, and a second comptime copy of "which shelf is this on" is how a fern ends up offered under Ruins in one place and not the other.
const floraKinds = props.FLORA_KINDS;
const solidKinds = props.SOLID_KINDS;
const interactKinds = props.INTERACT_KINDS;

/// The kinds an op layer stocks.
fn kindPool(l: Layer) ?[]const Kind {
    return switch (l) {
        .decor => &floraKinds,
        .props => &solidKinds,
        .interact => &interactKinds,
        .ground, .cover, .units => null,
    };
}

/// Which GROUP shelves each stocked layer has anything on, resolved at COMPTIME because `props.INFO` is comptime and so is the answer — not a per-frame scan of every kind to settle a question that cannot change at runtime.
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

/// The FIRST shelf a layer stocks — where the group chips land when you arrive on a layer whose current shelf it has nothing on.
fn firstGroup(l: Layer) props.Group {
    for (0..props.Group.N) |g| {
        if (layerGroups[@intFromEnum(l)][g]) return @enumFromInt(g);
    }
    return .ruins;
}

/// Does this layer have any kind on that shelf?
fn layerHasGroup(l: Layer, g: props.Group) bool {
    return layerGroups[@intFromEnum(l)][@intFromEnum(g)];
}

/// Which layer owns a given op — what the filtered list shows and what a click can select.
fn layerOf(o: *const wf.Op) Layer {
    return switch (o.op) {
        .cover => .cover,
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

/// Which dialog owns the screen.
pub const Modal = enum { none, new_map, open_map, save_as, confirm, objects, loot, jukebox };

// It exists for the same reason the object viewer does: a sound you can only hear by making the game produce it is a sound you retune by playing the game until it happens.
const VOICE_NAMES = blk: {
    const fields = @typeInfo(sfx.Id).@"enum".fields;
    var out: [fields.len][:0]const u8 = undefined;
    for (fields, 0..) |f, i| out[i] = f.name;
    break :blk out;
};

// The jukebox panel, as ONE set of numbers: the modal is sized from them and so is the scroll maths that keeps a key-moved selection on screen (`ui.listRows`), which is why the list height is a name and not a literal in two expressions.
const JUKE_W: i32 = 620;
const JUKE_H: i32 = 520;
const JUKE_LIST_W: i32 = 300;
const JUKE_LIST_H: i32 = JUKE_H - 150;

/// What a confirm is standing in FRONT of: an unsaved map is about to be thrown away, and this is what happens once you say so.
pub const Pending = enum { none, new, open, leave };

/// An axis-aligned XZ rect with its corners sorted.
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

/// Which ops carry a SECOND corner — the ones whose shape is a rect or a run, so a move has to take (x1, z1) along and an anchor is the middle rather than the near end.
fn hasSpan(k: wf.OpKind) bool {
    return switch (k) {
        .belt, .ivy, .line => true,
        else => false,
    };
}

/// Where an op sits, for marquee hit-testing and for translating a paste.
fn opAnchor(o: *const wf.Op) rl.Vector3 {
    if (hasSpan(o.op)) return v3((o.x + o.x1) * 0.5, 0, (o.z + o.z1) * 0.5);
    return v3(o.x, 0, o.z);
}

/// Move an op bodily.
fn translateOp(o: *wf.Op, dx: f32, dz: f32) void {
    o.x += dx;
    o.z += dz;
    if (hasSpan(o.op)) {
        o.x1 += dx;
        o.z1 += dz;
    }
}

/// Can this op be copied, moved or deleted?
fn isMovable(o: *const wf.Op) bool {
    return o.op != .cover and o.op != .edge;
}

/// What an erase stroke says when it finds nothing of the active layer under the cursor.
fn eraseMiss(l: Layer) [:0]const u8 {
    return switch (l) {
        .ground => "",
        .cover => "nothing here (the last zone is the fallback and stays)",
        .units => "no spawn inside the brush",
        .decor, .props, .interact => "nothing in this layer here",
    };
}

/// A held erase stroke.
const Wipe = struct {
    on: bool = false,
    at: rl.Vector3 = mathx.zero3, // ground point of the last removal, for the travel gate
    t: f32 = 0, // seconds since the last removal, for the rate gate
    n: usize = 0, // things removed so far this stroke
};


pub const Editor = struct {
    on: bool = false,
    cam: rl.Camera3D = undefined,
    /// THE WORLD, for the questions the cursor and the camera have to ask the TERRAIN — where a ray meets sculpted ground, how high the ground under the focus is.
    world: ?*const envmod.Env = null,
    // ORBIT state: a focus point on the ground, and the eye swung around it.
    focus: rl.Vector3 = mathx.zero3,
    yaw: f32 = 0,
    pitch: f32 = -0.7,
    dist: f32 = 28,
    panning: bool = false,
    panGrab: rl.Vector3 = mathx.zero3, // the ground point the pan grabbed

    /// SELECT MODE — OFF by default.
    selecting: bool = false,
    layer: Layer = .props,
    /// Each layer remembers the brush you left it on — switching to Decor to sow a fern and back should not silently rearm the eraser you were last using on Props.
    brush: [Layer.N]usize = [_]usize{0} ** Layer.N,
    decorKind: Kind = .fern,
    propKind: Kind = .pillar,
    interactKind: Kind = .chest,
    groupSel: props.Group = .ruins, // which palette shelf is open
    radius: f32 = 6.0,
    /// HOW STRONGLY A SOIL STROKE COVERS.
    soilOpacity: f32 = 1.0,
    snap: bool = false,

    sel: ?usize = null, // selected op
    selFoe: ?usize = null, // selected foe spawn (Units layer)
    dirty: bool = false,

    kindScroll: i32 = 0,

    dragging: bool = false,
    dragFrom: rl.Vector3 = mathx.zero3,
    dragTo: rl.Vector3 = mathx.zero3,
    painting: bool = false, // a soil stroke in progress (one undo step for the whole stroke)
    /// …and whether that stroke has moved WATER, which is the one paint the prop scatter cares about: consumed on release to re-sow the world once instead of 60 times a second (see the ground path).
    wetStroke: bool = false,
    /// …and whether it has moved the GROUND, which every prop cares about even more: they are planted at the height under them, so a sculpt stroke has to re-materialize the world when it ends or the trees you just raised a hill under are still standing at the old level.
    heightStroke: bool = false,
    /// How hard the sculpt brushes bite, in METRES A SECOND at the centre of the stroke.
    sculptRate: f32 = 3.0,
    wipe: Wipe = .{}, // a held ERASE stroke, likewise one undo step
    rmbDown: bool = false,
    rmbTravel: f32 = 0, // pixels the right button has moved while held
    menuOpen: bool = false,
    menuAt: rl.Vector2 = .{ .x = 0, .y = 0 },
    rebuildDue: bool = false, // a coalesced rebuild is owed (see requestRebuild)
    rebuildT: f32 = 0,

    // MARQUEE selection.
    marked: [MAX_MARKED]usize = undefined,
    nMarked: usize = 0,
    marquee: bool = false, // Shift+drag box in progress
    /// What the cursor is over THIS FRAME while Select is armed (see `Hover`).
    hover: Hover = .none,
    moving: bool = false, // dragging the marked set bodily
    moveFrom: rl.Vector3 = mathx.zero3,

    // File dialogs.
    modal: Modal = .none,
    pending: Pending = .none,
    /// THE OBJECT VIEWER's own state (gallery page, shelf, per-kind pose).
    objects: objview.State = .{},
    /// THE JUKEBOX's own state, outliving its modal for the same reason the viewer's does: you close it to go and look at the thing the sound belongs to, and it should still be on that voice.
    juke: usize = 0,
    jukeScroll: i32 = 0,
    /// Audition IN THE WORLD (at the camera's focus, so the distance is `dist` and you can hear a voice's `reach` fall off by zooming out) rather than at the ear.
    jukeWorld: bool = false,
    nameBuf: [wf.NAME_CAP]u8 = undefined,
    nameLen: usize = 0,
    fileSel: usize = 0,
    fileScroll: i32 = 0,
    /// The map this editor is writing to.
    path: [wf.PATH_CAP]u8 = undefined,
    pathLen: usize = 0,
    hotFrame: bool = false, // chrome owned the pointer LAST frame (gates world clicks)
    editing: bool = false, // mid-gesture on a properties widget (one undo step per gesture)
    /// How many instances the selected op OWNS, and how many of them `draw3D` got a marker onto before MAX_MARKERS stopped it.
    selOwned: usize = 0,
    selMarked: usize = 0,

    status: [ui.MSG_CAP]u8 = undefined,
    statusLen: usize = 0,
    statusT: f32 = 0,

    /// IS THE JUKEBOX AUDITIONING?
    pub fn auditioning(self: *const Editor) bool {
        return self.modal == .jukebox;
    }

    /// UP/DOWN walk the bank and audition as they go, SPACE replays.
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

    /// Scroll the selected row back into view.
    fn jukeReveal(self: *Editor) void {
        const rows = ui.listRows(JUKE_LIST_H);
        const sel: i32 = @intCast(self.juke);
        if (sel < self.jukeScroll) self.jukeScroll = sel;
        if (sel > self.jukeScroll + rows - 1) self.jukeScroll = sel - rows + 1;
    }

    /// Play the selected voice — at the ear, or out at the focus so its distance falloff and pan are the real ones.
    fn jukePlay(self: *Editor) void {
        if (self.juke >= VOICE_NAMES.len) return;
        const id: sfx.Id = @enumFromInt(self.juke);
        if (self.jukeWorld) sfx.world(id, self.focus) else sfx.play(id);
        // ASCII only — the HUD atlas has no glyph for a musical note and would draw tofu.
        self.sayFmt("played {s}", .{VOICE_NAMES[self.juke]});
    }

    /// Enter the editor, parking the camera above wherever the hero is standing.
    pub fn enter(self: *Editor, at: rl.Vector3) void {
        self.on = true;
        self.yaw = 0;
        self.pitch = -0.7;
        self.dist = 28;
        // Straight off the hero's own feet, which already carry the ground height under him — no need to ask the terrain, and `world` is not set until the first `update` anyway.
        self.focus = v3(at.x, at.y, at.z);
        self.cam = .{
            .position = at,
            .target = at,
            .up = v3(0, 1, 0),
            .fovy = 55,
            .projection = .perspective,
        };
        self.applyCam();
        self.selecting = false; // a brush is armed on entry: left click paints
        self.panning = false;
        self.dragging = false;
        self.painting = false;
        self.wipe = .{};
        self.menuOpen = false;
        self.marquee = false;
        self.moving = false;
        self.nMarked = 0;
        self.modal = .none;
        self.pending = .none;
        // Every held-button latch, or a button still down from the menu click that got us here arrives as a gesture already in progress over a world the editor has just re-aimed.
        self.rmbDown = false;
        self.rmbTravel = 0;
        self.hotFrame = false;
        self.editing = false;
        // The path is set ONCE and then belongs to Open / Save-As.
        if (self.pathLen == 0) self.setPath(wf.START_MAP);
        undoReset();
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
    /// Is the active brush this layer's eraser?
    fn erasing(self: *const Editor) bool {
        return self.brushIdx() == brushesFor(self.layer).len - 1;
    }
    /// The armed kind for the ACTIVE layer, as a pointer so the palette can set the same field the placement path reads.
    fn kindSlot(self: *Editor) *Kind {
        return switch (self.layer) {
            .decor => &self.decorKind,
            .interact => &self.interactKind,
            .ground, .cover, .props, .units => &self.propKind,
        };
    }
    fn kindForLayer(self: *const Editor) Kind {
        return switch (self.layer) {
            .decor => self.decorKind,
            .interact => self.interactKind,
            .ground, .cover, .props, .units => self.propKind,
        };
    }

    /// THE ONE WAY TO CHANGE LAYER.
    pub fn setLayer(self: *Editor, l: Layer) void {
        // THE MARKED SET DOES NOT CROSS LAYERS.
        if (self.layer != l) self.nMarked = 0;
        self.layer = l;
        if (l.opLayer() and !layerHasGroup(l, self.groupSel)) self.groupSel = firstGroup(l);
    }


    fn forward(self: *const Editor) rl.Vector3 {
        const cp = mathx.cosf(self.pitch);
        return v3(mathx.sinf(self.yaw) * cp, mathx.sinf(self.pitch), mathx.cosf(self.yaw) * cp);
    }

    // Screen-right = cross(forward, up), which for this codebase's convention (looking +Z at yaw 0) is world −X, matching camera.rightXZ's invariant.
    fn right(self: *const Editor) rl.Vector3 {
        const f = self.forward();
        return mathx.normV(v3(-f.z, 0, f.x));
    }

    /// Rebuild the camera from the orbit state.
    fn applyCam(self: *Editor) void {
        const f = self.forward();
        self.cam.target = self.focus;
        self.cam.position = mathx.addV(self.focus, mathx.scaleV(f, -self.dist));
        // Never let the eye go under the terrain — the world simply vanishes and the way back out is not obvious.
        self.cam.position.y = @max(self.cam.position.y, self.groundHeight(self.cam.position.x, self.cam.position.z) + 0.6);
    }

    fn orbitCam(self: *Editor, dt: f32) void {
        _ = dt;
        // RIGHT-DRAG ROTATES, RIGHT-CLICK is the context menu / deselect.
        if (rl.isMouseButtonPressed(.right)) {
            self.rmbDown = true;
            self.rmbTravel = 0;
        }
        if (self.rmbDown and rl.isMouseButtonDown(.right)) {
            const d = rl.getMouseDelta();
            self.rmbTravel += @abs(d.x) + @abs(d.y);
            if (self.rmbTravel > DRAG_PX) {
                self.yaw -= d.x * LOOK_SENS;
                // Clamped off the poles: at dead vertical the yaw axis degenerates and the map spins under you, and past it the world is upside down.
                self.pitch = mathx.clampF(self.pitch - d.y * LOOK_SENS, -1.45, -0.06);
            }
        }
        // Release is handled by worldMouse, which knows whether the click hit anything.

        // WHEEL ZOOMS — a proportional dolly, so one notch covers the same fraction of the remaining distance whether you are on a fern or looking at the whole map.
        const wheel = rl.getMouseWheelMove();
        if (wheel != 0 and !self.hotFrame) {
            self.dist = mathx.clampF(self.dist * (1.0 - wheel * 0.12), 2.0, 420.0);
        }

        // WASD and the ARROWS pan, same as dragging.
        const step = self.dist * 0.02;
        const gf = self.groundForward();
        const r = self.right();
        if (rl.isKeyDown(.w) or rl.isKeyDown(.up)) self.focus = mathx.addV(self.focus, mathx.scaleV(gf, step));
        if (rl.isKeyDown(.s) or rl.isKeyDown(.down)) self.focus = mathx.addV(self.focus, mathx.scaleV(gf, -step));
        if (rl.isKeyDown(.d) or rl.isKeyDown(.right)) self.focus = mathx.addV(self.focus, mathx.scaleV(r, step));
        if (rl.isKeyDown(.a) or rl.isKeyDown(.left)) self.focus = mathx.addV(self.focus, mathx.scaleV(r, -step));
        self.focusToGround(); // …and the focus rides the ground it just panned over
        self.applyCam();
    }

    /// The camera's heading flattened onto the ground — the "forward" a pan should use, since the eye is pitched down and its true forward mostly points at the floor.
    fn groundForward(self: *const Editor) rl.Vector3 {
        const f = self.forward();
        const l = @sqrt(f.x * f.x + f.z * f.z);
        if (l < 1e-5) return v3(0, 0, 1);
        return v3(f.x / l, 0, f.z / l);
    }

    /// Drag the ground itself.
    fn dragPan(self: *Editor) void {
        const now = self.groundAt() orelse return;
        // XZ only: the grab point and the point now under the cursor sit at DIFFERENT terrain heights on a sculpted map, and feeding that difference into the focus makes a pan across a hill climb.
        self.focus.x += self.panGrab.x - now.x;
        self.focus.z += self.panGrab.z - now.z;
        self.focusToGround();
        self.applyCam();
    }

    /// Where the cursor meets the GROUND — the sculpted surface, not a plane — or null when it is aimed at the sky.
    pub fn groundAt(self: *const Editor) ?rl.Vector3 {
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
            p.y = self.groundHeight(p.x, p.z); // …re-read, or a snapped point hangs off the slope
        }
        return p;
    }

    /// The ground's height at a world XZ — the editor's own thin wrapper, so a null world (a headless harness, a first frame) answers with the flat datum instead of needing a check at every use.
    pub fn groundHeight(self: *const Editor, x: f32, z: f32) f32 {
        if (self.world) |w| return w.groundAt(x, z);
        return envmod.groundY();
    }

    /// Drop the camera's focus onto the ground under it.
    fn focusToGround(self: *Editor) void {
        self.focus.y = self.groundHeight(self.focus.x, self.focus.z);
    }


    /// Snapshot the map BEFORE a mutation.
    pub fn bank(self: *Editor, m: *const wf.Map) void {
        // A new edit after stepping back discards the redo tail, like every other editor.
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
        // Step back one: keep the CURRENT state at the far end so redo has somewhere to go.
        if (undoAt == 0) {
            if (undoN == UNDO_CAP) undoDropOldest();
            undoSlot(undoN).* = m.*;
            undoN += 1;
            undoAt = 1;
        }
        undoAt += 1;
        m.* = undoSlot(undoN - undoAt).*;
        self.clampSel(m);
        return true;
    }

    fn redo(self: *Editor, m: *wf.Map) bool {
        if (undoAt <= 1) return false;
        undoAt -= 1;
        m.* = undoSlot(undoN - undoAt).*;
        self.clampSel(m);
        return true;
    }

    /// The index space just moved under us (a removal shifted everything after it down, or an undo swapped the whole document): repair what points into it.
    fn clampSel(self: *Editor, m: *const wf.Map) void {
        _ = m;
        self.sel = null;
        self.selFoe = null;
        self.nMarked = 0;
    }

    /// Re-derive the camera after the shot harness pokes the orbit state directly.
    pub fn applyCamForShot(self: *Editor) void {
        self.applyCam();
    }

    /// `focusOn` for the shot harness, which has no click to trigger it.
    pub fn focusOnForShot(self: *Editor, m: *const wf.Map, i: usize) void {
        self.focusOn(m, i);
    }

    /// Marquee + Open, for the shot harness — the same entry points a drag and Ctrl+O reach.
    pub fn selectForShot(self: *Editor, m: *const wf.Map, a: rl.Vector3, b: rl.Vector3) void {
        self.marqueeSelect(m, a, b);
    }

    pub fn openForShot(self: *Editor) void {
        listing.scan();
        self.fileSel = 0;
        self.fileScroll = 0;
        self.modal = .open_map;
    }

    /// Put the JUKEBOX up for the shot harness, parked on one voice.
    pub fn soundsForShot(self: *Editor, id: sfx.Id) void {
        self.modal = .jukebox;
        self.menuOpen = false;
        self.juke = @intFromEnum(id);
        self.jukeReveal(); // …and scrolled to, or the capture is of a list with no visible selection
    }

    /// Put the OBJECT VIEWER up for the shot harness: the gallery on a shelf, or one object filling it.
    pub fn objectsForShot(self: *Editor, shelf: objview.Shelf, page: i32, one: ?Kind) void {
        self.modal = .objects;
        self.objects.shelf = shelf;
        self.objects.page = page;
        self.objects.open = one;
        self.objects.grabbed = null;
    }

    /// Fly to an op.
    fn focusOn(self: *Editor, m: *const wf.Map, i: usize) void {
        if (i >= m.nops) return;
        const o = m.ops[i];
        const span = switch (o.op) {
            .belt, .ivy => @max(@abs(o.x1 - o.x), @abs(o.z1 - o.z)),
            .disc => o.r1 * 2,
            .ring => o.r0 * 2,
            .line => mathx.distXZ(v3(o.x, 0, o.z), v3(o.x1, 0, o.z1)),
            .at => AT_SPAN,
            .edge, .cover => m.half,
        };
        // The world-wide ops have no place of their own, so they frame the map's middle; everything else is centred by the same anchor the marquee and a paste use.
        const c = if (isMovable(&o)) opAnchor(&o) else mathx.zero3;
        self.lookAtGround(c.x, c.z, span);
    }

    // Frame a patch of ground `span` across, capped well inside the haze — framing a 250 m belt by its full extent puts the eye so far back that every prop is past its own view distance and all you get is fog with markers in it.
    fn lookAtGround(self: *Editor, cx: f32, cz: f32, span: f32) void {
        self.dist = mathx.clampF(span * 0.8 + 12, 14, 150);
        self.pitch = if (span > 90) -1.05 else -0.72;
        self.yaw = 0;
        self.focus = mathx.ground(cx, cz);
        self.focusToGround(); // …onto the ground there, or flying to a hilltop parks the orbit inside it
        self.applyCam();
    }


    pub fn update(self: *Editor, m: *wf.Map, env: *envmod.Env, dt: f32) Action {
        // THE WORLD, for the terrain questions the cursor and camera ask — see `Editor.world`.
        self.world = env;
        self.statusT = @max(0, self.statusT - dt);
        self.wipe.t += dt; // the held eraser's rate gate
        self.tickRebuild(m, env, dt); // service any rebuild a held widget coalesced

        // A MODAL owns everything: no camera, no brushes, no shortcuts behind it, and the only input it leaves alive is Esc.
        if (self.modal != .none) {
            // …and it CANCELS any gesture in flight.
            self.rmbDown = false;
            self.rmbTravel = 0;
            self.panning = false;
            self.dragging = false;
            self.marquee = false;
            self.moving = false;
            // …and the HOVER goes with them, for exactly the same reason: it is recomputed in `worldMouse`, which does not run under a modal, so it would LATCH — a box left lit behind the dialog, pointing at whatever the cursor happened to be over when the dialog opened.
            self.hover = .none;
            if (self.wipe.on) self.wipeEnd();
            // The jukebox is the one modal with a keyboard of its own (step + replay).
            if (self.modal == .jukebox) self.jukeKeys();
            if (rl.isKeyPressed(.escape)) {
                // ESC BACKS OUT ONE LEVEL, and the object viewer has two of them: the big single-object view falls back to the gallery, and only then does the gallery let go of the screen.
                if (!(self.modal == .objects and objview.back(&self.objects))) {
                    self.modal = .none;
                    self.pending = .none;
                }
            }
            return .none;
        }
        self.orbitCam(dt);
        // THE EARS ARE WHERE THE EDITOR'S CAMERA IS.
        sfx.listen(self.cam.position, self.right());
        // Serviced here rather than in commitPending, because leaving is the game loop's call.
        if (self.pending == .leave) {
            self.pending = .none;
            return .leave;
        }

        const ctrl = rl.isKeyDown(.left_control) or rl.isKeyDown(.right_control);
        const shift = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
        if (ctrl and rl.isKeyPressed(.s)) {
            if (shift) {
                self.nameLen = 0;
                self.menuOpen = false; // a dialog never opens on top of a live context menu
                self.modal = .save_as;
            } else self.saveNow(m);
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
            // Select everything in the ACTIVE layer — a marquee over the whole map.
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
        // ESC BACKS OUT ONE LEVEL, and SELECT MODE is what one level up IS (owner's rule): "back out and let me grab something", then "back out fully".
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

        // Tab cycles LAYERS; the digits pick a brush inside the layer (diablo's grammar, which is StarEdit's).
        if (rl.isKeyPressed(.tab)) {
            const back = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
            const cur = @intFromEnum(self.layer);
            const next = if (back) (cur + Layer.N - 1) % Layer.N else (cur + 1) % Layer.N;
            self.setLayer(@enumFromInt(next));
            self.sayFmt("{s}", .{self.layer.label()});
        }
        const digits = [_]rl.KeyboardKey{ .one, .two, .three, .four, .five, .six, .seven, .eight, .nine };
        for (digits, 0..) |k, i| {
            if (rl.isKeyPressed(k) and i < brushesFor(self.layer).len) {
                self.setBrush(i);
                self.selecting = false; // arming a brush hands the left button to it
            }
        }
        if (rl.isKeyPressed(.g)) {
            self.snap = !self.snap;
            self.sayFmt("grid snap {s}", .{if (self.snap) "on" else "off"});
        }
        if (rl.isKeyPressed(.left_bracket)) self.radius = mathx.clampF(self.radius - 1, 1, 60);
        if (rl.isKeyPressed(.right_bracket)) self.radius = mathx.clampF(self.radius + 1, 1, 60);
        if (rl.isKeyPressed(.r)) self.rerollSel(m, env);
        // Delete takes the whole marked set when there is one, and falls back to the single selection otherwise — so Del always means "remove what is highlighted".
        if (rl.isKeyPressed(.delete)) {
            if (self.nMarked > 0) self.deleteMarked(m, env) else self.deleteSel(m, env);
        }

        // ALWAYS called.
        self.worldMouse(m, env, dt);
        return .none;
    }

    /// Re-derive EVERYTHING the map feeds — props and painted soil.
    fn rebuild(self: *Editor, m: *const wf.Map, env: *envmod.Env) void {
        self.rebuildDue = false;
        self.rebuildT = 0;
        // THE PAINTED FIELDS FIRST, then the props.
        env.uploadSoil(m);
        env.uploadWater(m);
        // …and the SCULPTED GROUND, which `materialize` needs even harder than the water: every prop is planted at the ground height under it, so a stale field stands the whole world at the old elevation.
        env.uploadHeight(m);
        env.materialize(m);
    }

    /// Ask for a rebuild, DEBOUNCED — see `REBUILD_QUIET`, which is the distinction this used to say the opposite of.
    fn requestRebuild(self: *Editor) void {
        self.rebuildDue = true;
        self.rebuildT = 0; // …and RESTART the quiet clock, so a held dial costs ONE expansion instead of one per tick
    }

    fn tickRebuild(self: *Editor, m: *const wf.Map, env: *envmod.Env, dt: f32) void {
        if (!self.rebuildDue) return;
        self.rebuildT += dt;
        if (self.rebuildT >= REBUILD_QUIET) self.rebuild(m, env);
    }

    /// Called when a widget gesture ends: flush any coalesced rebuild immediately, so the world always settles on the value you let go of.
    fn endGesture(self: *Editor, m: *const wf.Map, env: *envmod.Env) void {
        self.editing = false;
        if (self.rebuildDue) self.rebuild(m, env);
    }

    /// Bank ONE undo step for a gesture in progress, from the pre-edit value the widget has already overwritten.
    fn bankGesture(self: *Editor, comptime T: type, m: *wf.Map, target: *T, before: T) void {
        if (self.editing) return;
        const live = target.*;
        target.* = before;
        self.bank(m);
        target.* = live;
        self.editing = true;
    }

    // THE CONTROL SCHEME (owner's, verbatim): click an object select it right-click an object its context menu right-click nothing deselect left-drag pan the map right-drag rotate wheel zoom WASD / arrows pan Enter confirm, Esc back — to SELECT mode, then to the menu (see the Esc ladder in `update`) SELECT MODE is what lets the left button mean "select" at all: with a brush armed it paints, and the two cannot share it.
    fn worldMouse(self: *Editor, m: *wf.Map, env: *envmod.Env, dt: f32) void {
        // CHROME OWNS THE POINTER — but only for STARTING something.
        const blocked = self.hotFrame or self.menuOpen;
        const ground = self.groundAt();

        // the thing itself (see drawOverlay).
        self.hover = if (self.selecting and !blocked) self.hoverInLayer(m, env) else .none;

        // A HELD STROKE ENDS THE MOMENT THE BUTTON IS UP, whatever branch is live: its own branch can be skipped mid-stroke (Shift hands the button to the marquee), and a stroke left latched would let the next press erase from under a panel — the same shape of bug as the right button latching.
        if (self.wipe.on and !rl.isMouseButtonDown(.left)) self.wipeEnd();
        // …and so does a GROUND STROKE, for the same reason and with a worse consequence than a stuck flag: its own release handler is inside the `.ground` branch below, which is skipped the moment you Tab to another layer (or Esc into Select) mid-sweep — so `painting` latched on and, worse, `wetStroke`/`heightStroke` never got to fire the RE-SOW that a water or sculpt stroke owes the world.
        if (self.painting and !rl.isMouseButtonDown(.left)) self.endPaint(m, env);
        // …and a SHAPE DRAG commits the same way.
        if (self.dragging and !rl.isMouseButtonDown(.left)) {
            if (ground) |g| self.dragTo = g;
            self.dragging = false;
            self.commitDrag(m, env);
        }
        // …and so do the two MARQUEE gestures, for the same reason and one more.
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
        if (self.rmbDown) return; // mid-rotate: the left button is not listened to

        if (self.panning) {
            self.dragPan();
            if (rl.isMouseButtonReleased(.left)) self.panning = false;
            return;
        }

        // GROUND is a true paint layer: hold and sweep, one undo step for the whole stroke.
        if (self.layer == .ground and !self.selecting) {
            if (rl.isMouseButtonDown(.left) and (self.painting or !blocked)) {
                if (ground) |g| {
                    if (!self.painting) {
                        self.bank(m);
                        self.painting = true;
                    }
                    // WATER is its own grid, and the eraser wipes BOTH — a stroke that lifted the soil and left the lake would be an eraser that only half worked, on the one layer where you can see straight through what it missed.
                    switch (@as(GroundBrush, @enumFromInt(self.brushIdx()))) {
                        // SCULPTING the land.
                        .raise, .lower, .smooth, .flat => |b| {
                            const mode: wf.Sculpt = switch (b) {
                                .raise => .raise,
                                .lower => .lower,
                                .smooth => .smooth,
                                else => .flatten,
                            };
                            const amt: f32 = switch (mode) {
                                // Metres a second for the two that move the ground…
                                .raise, .lower => self.sculptRate * dt,
                                // …and a 0..1 blend per second for the two that even it out.
                                else => mathx.minF(self.sculptRate * dt * SCULPT_EVEN, 0.9),
                            };
                            var span: [4]usize = wf.EMPTY_SPAN;
                            if (m.sculpt(g.x, g.z, self.radius, mode, amt, &span)) {
                                // The MESH first (so what you see is what you just did), then the world ON it — but only on the release: re-expanding 17k props every frame of a drag is a slideshow, the same reason a water stroke waits.
                                env.sculptHeight(m, span);
                                self.heightStroke = true;
                            }
                        },
                        .water => if (m.paintWater(g.x, g.z, self.radius, true)) {
                            env.uploadWater(m);
                            self.wetStroke = true;
                        },
                        .erase => {
                            // Opacity is not passed: an eraser clears outright (see `paintSoil`).
                            if (m.paintSoil(g.x, g.z, self.radius, .none, 1)) env.uploadSoil(m);
                            if (m.paintWater(g.x, g.z, self.radius, false)) {
                                env.uploadWater(m);
                                self.wetStroke = true;
                            }
                        },
                        else => {
                            const id: wf.Soil = @enumFromInt(self.brushIdx() - GROUND_SOIL_0 + 1);
                            if (m.paintSoil(g.x, g.z, self.radius, id, self.soilOpacity)) env.uploadSoil(m);
                        },
                    }
                }
            } else if (self.painting and rl.isMouseButtonReleased(.left)) {
                self.endPaint(m, env);
            }
            return;
        }

        const shift = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);

        // SHIFT+DRAG is the marquee, on every layer that has things to select; dragging INSIDE an existing selection moves the whole set, StarEdit-style.
        if (self.marquee or self.moving) {
            if (ground) |g| self.dragTo = g;
            return;
        }

        // THE ERASER IS A HELD BRUSH, like the soil one: press and sweep and everything you cross goes, as ONE undo step.
        if (self.erasing() and !self.selecting and !shift) {
            // The release is handled above, so this only has to service the held button.
            if (rl.isMouseButtonDown(.left) and (self.wipe.on or !blocked)) {
                if (ground) |g| self.wipeStep(m, env, g);
            }
            return;
        }

        if (rl.isMouseButtonPressed(.left)) {
            if (blocked) return; // a NEW gesture needs the pointer on the world, not on a panel
            if (shift and self.layer != .ground) {
                if (ground) |g| {
                    self.marquee = true;
                    self.dragFrom = g;
                    self.dragTo = g;
                }
                return;
            }
            // SELECT MODE: a click takes what is under the cursor; a click on nothing starts a pan.
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
            // A BRUSH IS ARMED, SO THE BRUSH ACTS — always, wherever the cursor is.
            switch (self.layer) {
                .units => {
                    if (ground) |g| self.addFoe(m, g);
                },
                .cover, .decor, .props, .interact => {
                    if (ground) |g| {
                        self.dragging = true;
                        self.dragFrom = g;
                        self.dragTo = g;
                    }
                },
                .ground => unreachable,
            }
            return;
        }
        // A live drag just tracks the cursor; the COMMIT is handled at the top of this function, where the release lands whatever branch is live this frame.
        if (self.dragging) {
            if (ground) |g| self.dragTo = g;
        }
    }

    /// End a ground stroke.
    fn endPaint(self: *Editor, m: *const wf.Map, env: *envmod.Env) void {
        self.painting = false;
        if (self.wetStroke or self.heightStroke) {
            self.wetStroke = false;
            self.heightStroke = false;
            self.rebuild(m, env);
        }
    }

    /// The ray under the cursor, normalized — every pick starts here.
    fn cursorRay(self: *const Editor) rl.Ray {
        const ray = rl.getScreenToWorldRay(rl.getMousePosition(), self.cam);
        return .{ .position = ray.position, .direction = mathx.normV(ray.direction) };
    }

    /// A pick filter.
    const OpFilter = struct {
        ed: *const Editor,
        m: *const wf.Map,
        /// Placed by an op the ACTIVE layer owns.
        fn inLayer(f: OpFilter, op: u16) bool {
            const i: usize = op;
            return i < f.m.nops and layerOf(&f.m.ops[i]) == f.ed.layer;
        }
    };

    fn filter(self: *const Editor, m: *const wf.Map) OpFilter {
        return .{ .ed = self, .m = m };
    }

    /// Is the cursor over something in the marked set?
    fn overMarked(self: *Editor, m: *const wf.Map, env: *envmod.Env) bool {
        if (self.layer == .units) {
            const g = self.groundAt() orelse return false;
            for (self.marked[0..self.nMarked]) |i| {
                if (i >= m.nfoes) continue;
                const f = m.foes[i];
                if (mathx.dist2XZ(v3(f.x, 0, f.z), g) < FOE_PICK_R * FOE_PICK_R) return true;
            }
            return false;
        }
        // The LAYER filter goes through the sweep, then membership is tested on the winner alone.
        const ray = self.cursorRay();
        const pi = env.pickIf(ray.position, ray.direction, self.filter(m), OpFilter.inLayer) orelse return false;
        return self.isMarked(env.props[pi].op);
    }

    /// Pick something in the ACTIVE layer only.
    fn hoverInLayer(self: *Editor, m: *wf.Map, env: *envmod.Env) Hover {
        if (self.layer.opLayer()) {
            const ray = self.cursorRay();
            if (env.pickIf(ray.position, ray.direction, self.filter(m), OpFilter.inLayer)) |pi| return .{ .prop = pi };
            return .none;
        }
        if (self.layer == .units) {
            // A spawn has no mesh for a ray to hit, so it is found by PROXIMITY on the ground — NEAREST inside the marker's own footprint, not the first one in the table.
            const g = self.groundAt() orelse return .none;
            var best: ?usize = null;
            var bestD2: f32 = FOE_PICK_R * FOE_PICK_R;
            for (m.foes[0..m.nfoes], 0..) |f, i| {
                const d2 = mathx.dist2XZ(v3(f.x, 0, f.z), g);
                if (d2 < bestD2) {
                    bestD2 = d2;
                    best = i;
                }
            }
            return if (best) |i| .{ .foe = i } else .none;
        }
        return .none;
    }

    /// TAKE what the cursor is over.
    fn pickInLayer(self: *Editor, m: *wf.Map, env: *envmod.Env) bool {
        switch (self.hoverInLayer(m, env)) {
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
        if (self.layer == .cover) {
            const g = self.groundAt() orelse return false;
            for (m.clearings[0..m.nclearings], 0..) |c, i| {
                if (mathx.dist2XZ(v3(c.x, 0, c.z), g) < c.r * c.r) {
                    self.sel = null;
                    self.sayFmt("clearing {d} — r {d:.0}", .{ i, c.r });
                    // FALSE on purpose, though it did name something: a clearing has no op, and "selected" is what opens the context menu — whose every row would then be a no-op reading as a menu that does nothing.
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

        if (self.layer == .cover) {
            // BANK PER BRANCH, after its cap check.
            switch (@as(CoverBrush, @enumFromInt(self.brushIdx()))) {
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
                    @memcpy(z.name[0..3], "new");
                    // Seed its mix from whatever already grows in the middle of the box, so a fresh zone starts as the ground it replaced rather than as bare earth.
                    if (m.zoneAt((z.x + z.x1) * 0.5, (z.z + z.z1) * 0.5)) |src| {
                        z.mix = src.mix;
                        z.nmix = src.nmix;
                    }
                    // A new zone goes in FRONT: zones resolve first-match-wins, so appending would put it behind the world-wide fallback and it would never match.
                    std.mem.copyBackwards(wf.Zone, m.zones[1 .. m.nzones + 1], m.zones[0..m.nzones]);
                    m.zones[0] = z;
                    m.nzones += 1;
                    self.say("+zone");
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
                // Unreachable through the press path (the eraser is handled before a drag ever starts), but a brush swapped mid-drag lands here and must place nothing.
                .erase => return,
            }
            self.rebuild(m, env);
            return;
        }

        var o = wf.defaults(.at);
        o.kind = self.kindForLayer();
        if (self.layer == .decor) {
            switch (@as(DecorBrush, @enumFromInt(self.brushIdx()))) {
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
            }
        } else if (self.layer == .interact) {
            // Its OWN brush enum, not PropBrush: the two strips share a `stamp` at index 0 and nothing else, so decoded as a PropBrush this layer's eraser would read as `row` and lay a line.
            switch (@as(InteractBrush, @enumFromInt(self.brushIdx()))) {
                .stamp => {
                    o.x = a.x;
                    o.z = a.z;
                    o.yaw = 0;
                    o.scale = 1;
                },
                .erase => return,
            }
        } else {
            switch (@as(PropBrush, @enumFromInt(self.brushIdx()))) {
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
                    o.kind = .ivy; // the ivy op sows the climber itself, not the palette's pick
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
            }
        }

        // Checked BEFORE the bank, so a drag onto a full map costs neither an undo step nor a dirty flag for the op it could not add.
        if (m.nops >= wf.MAX_OPS) {
            self.say(FULL_MSG);
            return;
        }
        self.bank(m);
        const idx = m.add(o) catch {
            self.say(FULL_MSG);
            return;
        };
        const at = self.sinkBeforeCover(m, idx);
        self.sel = at;
        self.selFoe = null;
        self.rebuild(m, env);
        self.sayFmt("+{s} {s} #{d}", .{ @tagName(o.op), @tagName(o.kind), at });
    }

    /// Square metres of ground one scattered instance is worth when the editor sizes a fresh belt or disc from the box you dragged.
    const AREA_PER_INSTANCE: f32 = 9.0;
    /// Instance count a fresh belt or disc is clamped into.
    const FRESH_N_LO: f32 = 4;
    const FRESH_N_HI: f32 = 900;
    /// Floors for the radius a drag measures, so a click that barely moves still makes a shape with an inside rather than a zero-radius op that places nothing and can't be grabbed.
    const MIN_CLEARING_R: f32 = 2.0;
    const MIN_BRUSH_R: f32 = 1.0;

    fn rectBelt(self: *Editor, m: *const wf.Map, a: rl.Vector3, b: rl.Vector3) wf.Op {
        var o = wf.defaults(.belt);
        o.kind = self.kindForLayer();
        const box = normRect(a, b);
        o.x = box.x0;
        o.z = box.z0;
        o.x1 = box.x1;
        o.z1 = box.z1;
        // Count scaled to the AREA, so a big box isn't sparse and a small one isn't a mat.
        const area = (o.x1 - o.x) * (o.z1 - o.z);
        o.n = @intFromFloat(mathx.clampF(area / AREA_PER_INSTANCE, FRESH_N_LO, FRESH_N_HI));
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
        const area = std.math.pi * o.r1 * o.r1;
        o.n = @intFromFloat(mathx.clampF(area / AREA_PER_INSTANCE, FRESH_N_LO, FRESH_N_HI));
        o.bias = 0.5;
        o.seed = self.freshSeed(m);
        return o;
    }

    // A seed no other op is using, so a new scatter never mirrors an existing one.
    fn freshSeed(self: *Editor, m: *const wf.Map) u64 {
        _ = self;
        var s: u64 = 1000;
        // BY POINTER: an `Op` carries a 24-kind mix and an 8-item loot list, so a by-value walk memcpy'd a couple of hundred kilobytes to read one u64 out of each.
        for (m.slice()) |*o| s = @max(s, o.seed);
        return s + 1;
    }

    fn addFoe(self: *Editor, m: *wf.Map, at: rl.Vector3) void {
        // The eraser sits one PAST the last foe kind (see `pinBrushes`), so with it armed the cast below is an out-of-range enum rather than an odd spawn. `worldMouse` routes the eraser elsewhere before it gets here, but that is an ordering of guards in another function, not a property of this one.
        if (self.erasing()) return;
        if (m.nfoes >= wf.MAX_FOES) {
            self.say("foe cap reached");
            return;
        }
        self.bank(m);
        const kind: wf.FoeKind = @enumFromInt(self.brushIdx());
        // A varied seed per spawn, else a knot placed in one session breathes as one body.
        const seed = @as(f32, @floatFromInt((m.nfoes * 37) % 100)) / 100.0;
        m.foes[m.nfoes] = .{ .kind = kind, .x = at.x, .z = at.z, .yaw = 0, .scale = 1, .seed = seed };
        self.selFoe = m.nfoes;
        m.nfoes += 1;
        self.sayFmt("+{s} ({d:.0}, {d:.0})", .{ wf.foeName(kind), at.x, at.z });
    }

    /// ONE tick of the held eraser: remove at most one thing, and only when the cursor has TRAVELLED since the last removal and the rate gate has elapsed.
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
            // Said on the stroke's FIRST frame only — a sweep across empty ground would otherwise strobe the status line with a miss every eighth of a second.
            self.say(eraseMiss(self.layer));
        }
    }

    /// End a held erase stroke, reporting the tally when it took more than the one thing whose own message is already on the status line.
    fn wipeEnd(self: *Editor) void {
        if (self.wipe.n > 1) self.sayFmt("erased {d}", .{self.wipe.n});
        self.wipe.on = false;
    }

    /// Bank the ONE undo step a held stroke gets, on the first thing it actually removes.
    fn bankStroke(self: *Editor, m: *wf.Map) void {
        if (self.wipe.n == 0) self.bank(m);
    }

    /// The scoped eraser: it can only ever remove things belonging to the ACTIVE layer.
    fn eraseAt(self: *Editor, m: *wf.Map, env: *envmod.Env, g: rl.Vector3) bool {
        switch (self.layer) {
            .ground => {}, // the soil brush erases by painting `.none`; nothing to remove here
            .units => {
                var i: usize = m.nfoes;
                while (i > 0) : (i -= 1) {
                    const f = m.foes[i - 1];
                    if (mathx.dist2XZ(v3(f.x, 0, f.z), g) > self.radius * self.radius) continue;
                    self.bankStroke(m);
                    std.mem.copyForwards(wf.Foe, m.foes[i - 1 .. m.nfoes - 1], m.foes[i..m.nfoes]);
                    m.nfoes -= 1;
                    self.selFoe = null;
                    self.clampSel(m); // the spawn indices just shifted — see there
                    self.sayFmt("-foe ({d:.0}, {d:.0})", .{ f.x, f.z });
                    return true;
                }
            },
            .cover => {
                for (m.clearings[0..m.nclearings], 0..) |c, i| {
                    if (mathx.dist2XZ(v3(c.x, 0, c.z), g) > c.r * c.r) continue;
                    self.bankStroke(m);
                    std.mem.copyForwards(wf.Clearing, m.clearings[i .. m.nclearings - 1], m.clearings[i + 1 .. m.nclearings]);
                    m.nclearings -= 1;
                    self.rebuild(m, env);
                    self.say("-clearing");
                    return true;
                }
                // Then zones — but never the LAST one, which is the world's fallback: without it `zoneAt` has nothing to return and the whole ground cover disappears.
                var i: usize = 0;
                while (i + 1 < m.nzones) : (i += 1) {
                    if (!m.zones[i].contains(g.x, g.z)) continue;
                    self.bankStroke(m);
                    std.mem.copyForwards(wf.Zone, m.zones[i .. m.nzones - 1], m.zones[i + 1 .. m.nzones]);
                    m.nzones -= 1;
                    self.rebuild(m, env);
                    self.say("-zone");
                    return true;
                }
            },
            .decor, .props, .interact => {
                // `pickInLayer` SELECTS what it finds, which is what the erase then removes — but a world-wide op (the rim) can't be removed, and leaving it selected means a sweep across the cliffs silently retargets the properties panel onto something the stroke declined to touch.
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
        self.sayFmt("re-rolled #{d} — seed {d}", .{ s, m.ops[s].seed });
    }

    fn deleteSel(self: *Editor, m: *wf.Map, env: *envmod.Env) void {
        if (self.layer == .units) {
            const f = self.selFoe orelse return;
            if (f >= m.nfoes) return;
            self.bank(m);
            std.mem.copyForwards(wf.Foe, m.foes[f .. m.nfoes - 1], m.foes[f + 1 .. m.nfoes]);
            m.nfoes -= 1;
            self.selFoe = null;
            self.clampSel(m); // the spawn indices just shifted — see there
            self.say("-foe");
            return;
        }
        const s = self.sel orelse return;
        if (s >= m.nops) return;
        // The world-wide ops are the ground cover and the map's rim: there is exactly one of each, and deleting the cover makes a map its own loader rejects.
        if (!isMovable(&m.ops[s])) {
            self.sayFmt("the {s} op is the whole world's — it cannot be deleted", .{@tagName(m.ops[s].op)});
            return;
        }
        self.bank(m);
        self.removeOp(m, env, s);
    }

    /// Drop op `s` and re-derive the world.
    fn removeOp(self: *Editor, m: *wf.Map, env: *envmod.Env, s: usize) void {
        m.remove(s);
        self.clampSel(m);
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
        // Offset so the copy isn't hidden under the original, through `translateOp`, which knows which kinds carry a second corner.
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

    /// Collect everything of the ACTIVE layer inside the dragged box.
    fn marqueeSelect(self: *Editor, m: *const wf.Map, a: rl.Vector3, b: rl.Vector3) void {
        const box = normRect(a, b);
        self.nMarked = 0;
        if (self.layer == .units) {
            for (m.foes[0..m.nfoes], 0..) |f, i| {
                if (box.holds(f.x, f.z)) self.mark(i);
            }
            self.selFoe = if (self.nMarked > 0) self.marked[0] else null;
            self.sel = null; // the two selections are layer-exclusive; leaving the other set
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

    /// The centre of the marked set, which a copy is stored relative to and a move measures from.
    fn markedCentre(self: *const Editor, m: *const wf.Map) rl.Vector3 {
        if (self.nMarked == 0) return mathx.zero3;
        var sx: f32 = 0;
        var sz: f32 = 0;
        // Counted as they are SUMMED, not off `nMarked`: the loop skips an index the map has since shrunk past, and dividing by the full mark count then drags the anchor toward the origin — a paste that lands nowhere near what was copied.
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
        // LAYER-SCOPED, and `marked` is why it has to be: it holds OP indices on Decor/Props and FOE indices on Units, so pasting a stand of trees while Units was live marked op indices that the next Del or drag then read as spawns and cut the wrong things.
        const onUnits = self.layer == .units;
        const nOps: usize = if (onUnits) 0 else nClipOps;
        const nFoes: usize = if (onUnits) nClipFoes else 0;
        if (nOps == 0 and nFoes == 0) {
            if (onUnits) self.say("clipboard holds ops — paste them on an object layer") else self.say("clipboard holds spawns — paste them on Units");
            return;
        }
        self.bank(m);
        self.nMarked = 0;
        // Seeds handed out from ONE scan, then incremented. freshSeed rescans every op, so calling it per item made a 500-op paste quadratic in the map size.
        var seed = self.freshSeed(m);
        for (clipOps[0..nOps]) |src| {
            var o = src;
            translateOp(&o, at.x, at.z);
            // A pasted generator gets its OWN seed.
            if (o.op != .at) {
                o.seed = seed;
                seed += 1;
            }
            const idx = m.add(o) catch {
                self.say(FULL_MSG);
                break;
            };
            self.mark(self.sinkBeforeCover(m, idx));
        }
        for (clipFoes[0..nFoes]) |src| {
            if (m.nfoes >= wf.MAX_FOES) {
                self.say("foe cap reached");
                break;
            }
            var f = src;
            f.x += at.x;
            f.z += at.z;
            m.foes[m.nfoes] = f;
            self.mark(m.nfoes);
            m.nfoes += 1;
        }
        self.rebuild(m, env);
        self.sayFmt("pasted {d}", .{nOps + nFoes});
    }

    fn deleteMarked(self: *Editor, m: *wf.Map, env: *envmod.Env) void {
        if (self.nMarked == 0) return;
        self.bank(m);
        // Remove HIGH INDEX FIRST: every removal shifts everything after it down, so deleting in ascending order makes each later index point at the wrong thing.
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
        self.nMarked = 0;
        self.sel = null;
        self.selFoe = null;
        self.rebuild(m, env);
        self.sayFmt("deleted {d}", .{removed});
    }

    /// Sink a freshly added op back past the cover scatter and RETURN WHERE IT LANDED.
    fn sinkBeforeCover(self: *Editor, m: *wf.Map, idx: usize) usize {
        _ = self;
        var at = idx;
        while (at > 0 and m.ops[at - 1].op == .cover) : (at -= 1) m.reorder(at, at - 1);
        return at;
    }


    /// Route an action that would DISCARD unsaved work through a confirm first.
    fn request(self: *Editor, what: Pending) void {
        self.menuOpen = false; // a keyboard shortcut can raise a dialog over an open menu
        if (!self.dirty) {
            self.commitPending(what);
            return;
        }
        self.pending = what;
        self.modal = .confirm;
    }

    fn commitPending(self: *Editor, what: Pending) void {
        // Only `leave` stays pending, because leaving is the game loop's call; the other two are handled here, and leaving them latched would strand a stale intent the next confirm inherits.
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

    /// Adopt a map that has just REPLACED the one being edited: nothing selected, nothing marked, an empty undo ring — its snapshots belong to a document that is gone, and stepping into one restores a world nobody asked for — and the props re-derived.
    fn adopt(self: *Editor, m: *const wf.Map, env: *envmod.Env, isDirty: bool) void {
        self.sel = null;
        self.selFoe = null;
        self.nMarked = 0;
        self.dirty = isDirty;
        undoReset();
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
        self.sayFmt("opened {s} — {d} ops", .{ p, m.nops });
    }

    fn doNew(self: *Editor, m: *wf.Map, env: *envmod.Env) void {
        const name = if (self.nameLen > 0) self.nameBuf[0..self.nameLen] else "untitled";
        m.blank(name);
        var buf: [wf.PATH_CAP]u8 = undefined;
        self.setPath(wf.pathFor(&buf, name));
        // A new map is DIRTY from the start: it exists only in memory, and telling the user otherwise invites them to leave without ever writing it.
        self.adopt(m, env, true);
        self.sayFmt("new map \"{s}\" — save it to keep it", .{name});
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

    fn saveNow(self: *Editor, m: *const wf.Map) void {
        wf.save(self.curPath(), m) catch |e| {
            self.sayFmt("SAVE FAILED: {s}", .{@errorName(e)});
            return;
        };
        self.dirty = false;
        self.sayFmt("saved {s} — {d} ops", .{ self.curPath(), m.nops });
    }


    pub fn draw3D(self: *Editor, m: *const wf.Map, env: *const envmod.Env) void {
        gizmoWorld = env; // every wireframe below rides the ground — see liftAt
        // A LIFT above the ground now, not an absolute height.
        const y: f32 = 0.05;
        // The map border stays a flat box: it is the world's EXTENT, not a thing standing on the ground, and a border that dipped into every valley would read as another op's outline.
        rl.drawCubeWires(v3(0, envmod.groundY() + y, 0), m.half * 2, 0.02, m.half * 2, ui.alpha(ui.TRIM, 90));
        outline(m.runway.x, m.runway.z, m.runway.x1, m.runway.z1, y, ui.alpha(ui.HOT, 70));

        // OTHER LAYERS DRAW DIM.
        const coverA: u8 = if (self.layer == .cover) 200 else 45;
        for (m.zones[0..m.nzones]) |*z| {
            // The world-spanning fallback zone has no meaningful outline to draw.
            if (z.x1 - z.x > m.half * 3) continue;
            outline(z.x, z.z, z.x1, z.z1, y, ui.alpha(ui.TRIM, coverA));
        }
        for (m.clearings[0..m.nclearings]) |c| ringXZ(c.x, c.z, c.r, y, ui.alpha(ui.HOT, coverA));

        const unitA: u8 = if (self.layer == .units) 235 else 70;
        for (m.foes[0..m.nfoes], 0..) |f, i| {
            const sel = self.layer == .units and self.selFoe == i;
            const col = if (sel) ui.HOT else ui.alpha(foeSwatch(f.kind), unitA);
            // …standing on the ground, like the foe it marks: a spawn table stores x/z only, so a box drawn at the datum floats over a valley and buries itself in a hill.
            const at = liftAt(f.x, f.z, y + FOE_BOX_H * 0.5);
            rl.drawCubeWires(at, FOE_BOX_W, FOE_BOX_H, FOE_BOX_W, col);
        }

        // The SELECTED op: its own shape, plus a marker on every instance it placed.
        self.selOwned = 0;
        self.selMarked = 0;
        if (self.sel) |s| {
            if (s < m.nops and self.layer.opLayer()) {
                drawOpGizmo(&m.ops[s], y);
                for (env.props[0..env.nprops]) |pr| {
                    if (pr.op != s) continue;
                    self.selOwned += 1;
                    if (self.selMarked >= MAX_MARKERS) continue; // capped — reported, never silent
                    self.selMarked += 1;
                    const nfo = props.info(pr.kind);
                    const h = @max(nfo.top * pr.scale, 0.4);
                    // The marker TIPS with a leaning instance (its own trig, from env, so the two can never disagree): a plumb column beside a tilted trunk reads as marking the ground.
                    const sw = envmod.leanOffsetAt(pr.lean, pr.leanDir, h * 0.5);
                    rl.drawCubeWires(v3(pr.pos.x + sw.x, pr.pos.y + h * 0.5, pr.pos.z + sw.z), 0.3, h, 0.3, ui.HOT);
                }
            }
        }

        // THE MARKED SET, boxed.
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
        // three so it sits over the selection and the marked set: it is the only one of them that answers a question about the NEXT action rather than the last one.
        switch (self.hover) {
            .none => {},
            .prop => |pi| {
                if (pi < env.nprops) {
                    const pr = env.props[pi];
                    const nfo = props.info(pr.kind);
                    const h = @max(nfo.top * pr.scale, 0.4);
                    const w = @max(nfo.bound * pr.scale, 0.3) * 1.6;
                    // Tipped with a leaning instance, off env's own trig — a plumb box beside a tilted trunk reads as highlighting the ground next to it (see the sel marker).
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

        // The marquee box, and the live offset while dragging the set.
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

        // The drag in progress, drawn as the op it is about to become.
        if (self.dragging) {
            const a = self.dragFrom;
            const b = self.dragTo;
            const rad = mathx.distXZ(a, b);
            const box = normRect(a, b);
            if (self.layer == .cover) {
                switch (@as(CoverBrush, @enumFromInt(self.brushIdx()))) {
                    .zone => outlineOf(box, y, ui.HOT),
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
            // INTERACTABLES place one thing at a point — there is no shape for a drag to preview.
        }

        // THE BRUSH under the cursor, at its real radius — a paint brush whose size you can only read off a number in the status bar is a brush you have to guess with.
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
            // A HEADING SPOKE, because a circle cannot show yaw. This is the cheap live answer the debounced rebuild leaves you without: it reads the OP, so it swings on the frame you press the stepper while the props behind it are still standing at the old angle.
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
        .edge, .cover => {}, // world-wide: their gizmo would be the whole map border
    }
}

const FOE_BOX_W: f32 = 0.9; // a posted spawn, roughly a body's footprint
const FOE_BOX_H: f32 = 1.8; // …and a body's height (the hero's stature)
const MARK_BOX_W: f32 = 1.4; // the same spawn once it is in the marked set: a size bigger
const MARK_BOX_H: f32 = 2.0;
const MARK_RING_R: f32 = 1.8; // marked op anchors, and their ghosts while the set is dragged
const MARK_RING_SEG: i32 = 12; // coarse on purpose — see ringSeg
const GIZMO_R: f32 = 1.2; // one literal prop's own gizmo
const GIZMO_SPOKE: f32 = GIZMO_R * 1.9; // …and how far its heading spoke reaches past the ring
const CURSOR_R: f32 = 0.9; // the plain cursor ring, where no brush radius applies

/// Marker colours per foe kind — a green toad, bone-pale archer, orange-lit ogre, and the kobold warband on ONE dust-brown hue so a pack reads as a pack at a glance, separated only by value (the berserker brightest, the priest gold-lit, the slinger dark).
fn foeSwatch(k: wf.FoeKind) rl.Color {
    return switch (k) {
        .toad => ui.col(120, 200, 110, 255),
        .archer => ui.col(210, 205, 180, 255),
        .ogre => ui.col(220, 140, 90, 255),
        .berserker => ui.col(206, 150, 96, 255),
        .priest => ui.col(228, 190, 104, 255), // …the gold it casts with
        .slinger => ui.col(152, 116, 78, 255),
    };
}

// The `y` these take is a LIFT ABOVE THE GROUND, sampled per vertex — never an absolute height.
var gizmoWorld: ?*const envmod.Env = null;

/// A gizmo vertex: `lift` metres above the ground at (x, z).
fn liftAt(x: f32, z: f32, lift: f32) rl.Vector3 {
    if (gizmoWorld) |w| return v3(x, w.groundAt(x, z) + lift, z);
    return v3(x, envmod.groundY() + lift, z);
}

/// A line whose ENDS ride the ground.
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

/// A ring at a chosen resolution.
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
/// Inset from a panel edge to the text inside it.
const CHROME_PAD: i32 = 10;
/// Clear space the status bar keeps between its left run and its right-aligned readout.
const GUTTER: i32 = 30;
const COORD_LIM: f32 = 400;
/// Ceiling on a scatter's ATTEMPT count (belt, disc).
const COUNT_MAX: i32 = 4000;
/// Positions a `ring` may have.
const RING_N_MAX: i32 = 64;
/// How far off plumb a prop may be tipped.
const LEAN_LIM: f32 = 40;

/// ONE row pitch for every stacked row in the chrome.
const ROW_H: i32 = ui.ROW_H;
/// Extra drop under a slider, which draws its bar BELOW its label and so is taller than a row.
const SLIDER_DROP: i32 = 20;

/// `scene` is here for the OBJECT VIEWER alone: its thumbnails are the world's own models drawn off-screen through the world's own shader, and that is the only way a preview can be trusted to look like the game.
pub fn drawOverlay(ed: *Editor, m: *wf.Map, env: *envmod.Env, scene: *gfx.Scene, t: f32) void {
    ed.world = env; // …the status readout and the gizmos ask the terrain too (see Editor.world)
    const sw = rl.getScreenWidth();
    const sh = rl.getScreenHeight();
    var ctx = ui.Ctx.begin(t);

    // A MODAL — or the context menu — OWNS THE POINTER, and the chrome it sits over is drawn FIRST.
    const overlaid = ed.modal != .none or ed.menuOpen;
    if (overlaid) ctx.setLive(false);

    drawTopBar(ed, m, env, &ctx, sw);
    drawSide(ed, &ctx, sh);
    drawProperties(ed, m, env, &ctx, sw, sh);
    drawMinimap(ed, m, &ctx, sw, sh);
    drawStatus(ed, m, env, &ctx, sw, sh);
    if (overlaid) ctx.setLive(true);
    if (ed.modal != .none) {
        drawModal(ed, m, env, scene, &ctx);
    } else if (ed.menuOpen) {
        drawContextMenu(ed, m, env, &ctx);
    }
    ui.drawTip(&ctx);

    // The gate for NEXT frame's world clicks.
    ed.hotFrame = ctx.anyHot;
}

/// A left-to-right run of buttons along the top bar.
const BarRow = struct {
    ctx: *ui.Ctx,
    x: i32,

    const GAP: i32 = 4;
    const PAD: i32 = 18; // label inset, so a button is never tight around its text

    fn button(r: *BarRow, label: [:0]const u8, active: bool, tip: [:0]const u8) bool {
        const w = hud.monoW(label, hud.MONO) + PAD;
        defer r.x += w + GAP;
        return ui.buttonTip(r.ctx, ui.rect(r.x, 5, w, BAR_H - 10), label, hud.MONO, active, tip);
    }

    /// A LAYER: picture AND name.
    fn layer(r: *BarRow, ic: ui.Icon, label: [:0]const u8, active: bool, tip: [:0]const u8) bool {
        const w = ui.iconButtonW(label, hud.MONO);
        defer r.x += w + GAP;
        const rect = ui.rect(r.x, 5, w, BAR_H - 10);
        ui.tipFor(r.ctx, rect, tip);
        return ui.iconButton(r.ctx, rect, ic, label, hud.MONO, active);
    }

    /// A VERB: picture only, square, explained on hover.
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
    inline for (@typeInfo(Layer).@"enum".fields) |f| {
        const l: Layer = @enumFromInt(f.value);
        if (row.layer(layerIcon(l), l.label(), ed.layer == l, layerTips[f.value])) ed.setLayer(l);
    }
    row.gap(14); // the layer strip and the file buttons are different kinds of thing
    if (row.verb(.new, "New — start an empty map (Ctrl+N)")) ed.request(.new);
    if (row.verb(.open, "Open — a map from worlds/ (Ctrl+O)")) ed.request(.open);
    if (row.verb(.save, "Save — write the map to disk (Ctrl+S)")) ed.saveNow(m);
    if (row.verb(.saveas, "Save As — write it under a new name (Ctrl+Shift+S)")) {
        ed.nameLen = 0;
        ed.modal = .save_as;
    }
    if (row.verb(.reload, "Reload — throw away every unsaved change and re-read the file")) {
        var line: usize = 0;
        wf.load(ed.curPath(), m, &line) catch |e| {
            ed.sayFmt("RELOAD FAILED: {s} (line {d})", .{ @errorName(e), line });
            return;
        };
        ed.adopt(m, env, false);
        ed.say("reloaded from disk");
    }
    row.gap(10); // …and undo/redo are a pair apart from the file verbs
    if (row.verb(.undo, "Undo (Ctrl+Z)")) {
        if (ed.undo(m)) ed.rebuild(m, env);
    }
    if (row.verb(.redo, "Redo (Ctrl+Y)")) {
        if (ed.redo(m)) ed.rebuild(m, env);
    }
    row.gap(10);
    if (row.button("Objects", ed.modal == .objects, "Object viewer — every model in a gallery; click one to turn it over")) {
        ed.menuOpen = false;
        ed.modal = .objects;
    }
    // …and its counterpart for the EARS.
    if (row.button("Sounds", ed.modal == .jukebox, "Jukebox — play any sound in the bank on demand")) {
        ed.menuOpen = false;
        ed.modal = .jukebox;
    }

    // Just the UNSAVED marker up here.
    if (ed.dirty) hud.mono("*", row.x + 8, 8, hud.MONO, ui.HOT);
}

// The active layer's BRUSH strip, its kind palette (Decor/Props only), and the op list filtered to this layer.
fn drawSide(ed: *Editor, ctx: *ui.Ctx, sh: i32) void {
    ui.panel(ctx, ui.rect(0, BAR_H, SIDE_W, sh - BAR_H - STATUS_H), null);
    var y: i32 = BAR_H + 8;

    // SELECT sits above the brushes and outside them: it is the mode where the left button picks things instead of painting them, and it is what makes "click an object to select it" possible at all.
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
        // The DIGIT ONLY WHERE THERE IS ONE.
        const s = if (i < DIGIT_KEYS) (std.fmt.bufPrintZ(&lab, "{d} {s}", .{ i + 1, b }) catch b) else b;
        const r = ui.rect(8, y, SIDE_W - 16, ROW_H - 4);
        ui.tipFor(ctx, r, tips[i]);
        const on = !ed.selecting and ed.brushIdx() == i;
        const hit = if (glyphs) |g|
            ui.iconButton(ctx, r, g[i], s, hud.MONO, on)
        else
            // GROUND: the swatch IS the icon.
            (if (i + 1 == brushes.len)
                ui.iconButton(ctx, r, .erase, s, hud.MONO, on)
            else switch (@as(GroundBrush, @enumFromInt(i))) {
                // THE SCULPT TOOLS get swatches too, so the strip stays one kind of thing: earth going up, earth going down, and two greys for the two that even it out.
                .raise => ui.swatchButton(ctx, r, RAISE_SWATCH, s, hud.MONO, on),
                .lower => ui.swatchButton(ctx, r, LOWER_SWATCH, s, hud.MONO, on),
                .smooth, .flat => ui.swatchButton(ctx, r, EVEN_SWATCH, s, hud.MONO, on),
                // WATER is not a soil id, so it has no swatch in that table — it gets the tarn's own chrome colour, the same one the minimap draws it in (see WATER_SWATCH).
                .water => ui.swatchButton(ctx, r, WATER_SWATCH, s, hud.MONO, on),
                else => ui.swatchButton(ctx, r, soilSwatch(@enumFromInt(i - GROUND_SOIL_0 + 1)), s, hud.MONO, on),
            });
        if (hit) {
            ed.setBrush(i);
            ed.selecting = false; // arming a brush hands the left button to it
        }
        y += ROW_H;
    }
    y += 6;

    // The kind palette, filtered TWICE: to the layer's own stock (Decor sows the flora, Props stand the rest up, Interactables open), then to the chosen GROUP.
    if (kindPool(ed.layer)) |pool| {
        hud.mono("GROUP", 10, y, hud.MONO, ui.alpha(ui.TRIM, 235));
        y += ROW_H;
        // Only the groups this layer actually has stock in — Props has no Ferns shelf, and an empty shelf is a dead button that teaches you nothing.
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
        // Collapse to the visible shelf, keeping a map back to the real kind.
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
        // The palette gets the whole rest of the panel — clamped at zero, because on a short window the arithmetic goes negative and a rectangle with negative height draws inside-out over the panel above it.
        const listH = @max(0, sh - y - STATUS_H - 8);
        // THE PALETTE ARMS THE BRUSH, and that is ALL it does (owner's call): a click in a chooser must not edit the document.
        if (ui.list(ctx, ui.rect(8, y, SIDE_W - 16, listH), labels[0..n], selIdx, &ed.kindScroll)) |i| {
            ed.kindSlot().* = kinds[i];
        }
    }
}


fn drawProperties(ed: *Editor, m: *wf.Map, env: *envmod.Env, ctx: *ui.Ctx, sw: i32, sh: i32) void {
    const x0 = sw - PROP_W;
    ui.panel(ctx, ui.rect(x0, BAR_H, PROP_W, sh - BAR_H - STATUS_H), null);
    const x = x0 + 10;
    const w = PROP_W - 20;
    var y = BAR_H + 8;

    // GROUND and UNITS have no op to edit — they get their own inspectors.
    if (ed.layer == .ground) {
        // THE PANEL REPORTS THE GRID THE ARMED BRUSH ACTUALLY WORKS ON.
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
        // THE BLEND DIAL, and only on the soil brush — the sculpt tools have their own strength and the water mask is one bit wide, so neither has an opacity to offer.
        if (!sculpting and !wet) {
            _ = ui.slider(ctx, x, y, w, "opacity", &ed.soilOpacity, 0, 1);
            y += ROW_H + SLIDER_DROP;
        }
        if (sculpting) {
            _ = ui.slider(ctx, x, y, w, "strength", &ed.sculptRate, 0.5, 12);
            y += ROW_H + SLIDER_DROP;
            // WHAT THE GROUND IS DOING UNDER THE CURSOR, which is the whole readout a sculptor needs: how high it is, how steep, and — the number that matters — whether the hero could walk there.
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
                ed.rebuild(m, env); // props are planted at the ground height, so levelling re-plants them
                ed.say("ground levelled");
            }
            return;
        }
        // COUNTED EVERY FRAME, and left that way DELIBERATELY: this is a full scan of the armed brush's grid — 12,544 bytes for the soil, 50,176 for the water — to print one number.
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
            // The two numbers that explain what the brush is deciding FOR you.
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
                ed.rebuild(m, env); // the flora scatter reads `inWater`, so draining re-sows the bed
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
        changed = ui.stepperF(ctx, x, y, w, "scale", &fo.scale, 0.02, 0.5, 2) or changed;
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

    if (ed.layer == .cover) {
        hud.mono("ZONES", x, y, hud.MONO, ui.TITLE);
        y += ROW_H + 4;
        var changed = false;
        // Snapshot BEFORE any slider runs, so the gesture's undo step can be banked from the pre-edit densities — the earlier version only raised `dirty` and left zone edits as the one mutation in the editor that Ctrl+Z could not take back.
        var before: [wf.MAX_ZONES]f32 = undefined;
        for (m.zones[0..m.nzones], 0..) |*z, i| before[i] = z.density;
        for (m.zones[0..m.nzones], 0..) |*z, i| {
            var zb: [48]u8 = undefined;
            const lab = std.fmt.bufPrintZ(&zb, "{d} {s}", .{ i, z.label() }) catch "?";
            changed = ui.slider(ctx, x, y, w, lab, &z.density, 0, 1) or changed;
            y += ROW_H + SLIDER_DROP;
        }
        y += 6;
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

    // DECOR / PROPS: the selected op's dials.
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
    // STRAIGHT TO THE MODEL from the thing you just clicked in the world — the fix-a-prop loop starts with "what IS this and why does it look wrong", and the answer is the viewer, not the dials.
    if (o.op != .cover and ui.buttonTip(ctx, ui.rect(x + w - 74, y - 2, 74, 22), "view", hud.MONO, false, "Open this kind in the object viewer")) {
        ed.objects.show(o.kind);
        ed.modal = .objects;
        return;
    }
    y += ROW_H;
    // WHAT THIS OP ACTUALLY GREW, and honestly: a scatter's `count` is an ATTEMPT count, so the number of instances it owns is always lower and is the only thing that tells you whether a density dial did anything.
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
            changed = ui.stepperF(ctx, x, y, w, "x", &o.x, 0.5, -COORD_LIM, COORD_LIM) or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "z", &o.z, 0.5, -COORD_LIM, COORD_LIM) or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "yaw", &o.yaw, 5, -360, 720) or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "scale", &o.scale, 0.05, 0.1, 4) or changed;
            y += ROW_H;
            // OFF PLUMB, exactly as dialled: how far it tips, and which way it falls.
            changed = ui.stepperF(ctx, x, y, w, "lean", &o.lean, 1, 0, LEAN_LIM) or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "lean dir", &o.leanDir, 15, -360, 720) or changed;
            y += ROW_H;
        },
        .belt, .ivy => {
            changed = ui.stepperF(ctx, x, y, w, "x0", &o.x, 1, -COORD_LIM, COORD_LIM) or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "z0", &o.z, 1, -COORD_LIM, COORD_LIM) or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "x1", &o.x1, 1, -COORD_LIM, COORD_LIM) or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "z1", &o.z1, 1, -COORD_LIM, COORD_LIM) or changed;
            y += ROW_H;
            if (o.op == .belt) {
                changed = ui.stepperI(ctx, x, y, w, "count", &o.n, 5, 0, COUNT_MAX) or changed;
                y += ROW_H;
            } else {
                changed = ui.slider(ctx, x, y, w, "take", &o.chance, 0, 1) or changed;
                y += ROW_H + SLIDER_DROP;
            }
        },
        .disc => {
            changed = ui.stepperF(ctx, x, y, w, "x", &o.x, 1, -COORD_LIM, COORD_LIM) or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "z", &o.z, 1, -COORD_LIM, COORD_LIM) or changed;
            y += ROW_H;
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
            changed = ui.stepperF(ctx, x, y, w, "x", &o.x, 1, -COORD_LIM, COORD_LIM) or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "z", &o.z, 1, -COORD_LIM, COORD_LIM) or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "radius", &o.r0, 0.5, 0.5, 200) or changed;
            y += ROW_H;
            changed = ui.stepperI(ctx, x, y, w, "count", &o.n, 1, 2, RING_N_MAX) or changed;
            y += ROW_H;
            // -1 is "no gap"; the top is the last position a ring of RING_N_MAX can have.
            changed = ui.stepperI(ctx, x, y, w, "gap at", &o.skip, 1, -1, RING_N_MAX - 1) or changed;
            y += ROW_H;
        },
        .line => {
            changed = ui.stepperF(ctx, x, y, w, "x0", &o.x, 1, -COORD_LIM, COORD_LIM) or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "z0", &o.z, 1, -COORD_LIM, COORD_LIM) or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "x1", &o.x1, 1, -COORD_LIM, COORD_LIM) or changed;
            y += ROW_H;
            changed = ui.stepperF(ctx, x, y, w, "z1", &o.z1, 1, -COORD_LIM, COORD_LIM) or changed;
            y += ROW_H;
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
        .cover => {},
    }

    if (o.op != .at) {
        changed = ui.stepperF(ctx, x, y, w, "scale lo", &o.sLo, 0.05, 0.1, 3) or changed;
        y += ROW_H;
        changed = ui.stepperF(ctx, x, y, w, "scale hi", &o.sHi, 0.05, 0.1, 3) or changed;
        y += ROW_H;
        if (o.sHi < o.sLo) o.sHi = o.sLo; // an inverted band silently places nothing
        // A scatter's lean is a CEILING, not a setting: each instance rolls its own amount up to this and its own direction, because a stand of trees all tipped the same way reads as a storm.
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
        }
    }

    // Order matters (ivy climbs what came before it), so moving an op is a real operation.
    if (ui.buttonTip(ctx, ui.rect(x, y, 44, 24), "up", hud.MONO, false, "Run EARLIER — order decides what later ops can see")) {
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

// The whole map at a glance: the painted soil, then everything standing on it, then where you are.
fn drawMinimap(ed: *Editor, m: *const wf.Map, ctx: *ui.Ctx, sw: i32, sh: i32) void {
    const x0 = sw - PROP_W - MINI_W - 8;
    const y0 = sh - STATUS_H - MINI_W - 8;
    const r = ui.rect(x0, y0, MINI_W, MINI_W);
    ui.panel(ctx, r, null);
    const inner: f32 = @floatFromInt(MINI_W - 8);
    const px = x0 + 4;
    const py = y0 + 4;
    rl.drawRectangle(px, py, MINI_W - 8, MINI_W - 8, ui.col(18, 20, 14, 255));

    // Painted soil first, as the backdrop — RUN-LENGTHED along each row.
    const cellPx = inner / @as(f32, @floatFromInt(wf.SOIL_N));
    for (0..wf.SOIL_N) |cz| {
        const row = m.soil[cz * wf.SOIL_N ..][0..wf.SOIL_N];
        var cx: usize = 0;
        while (cx < wf.SOIL_N) {
            const id = row[cx];
            if (id == 0) {
                cx += 1;
                continue;
            }
            var run: usize = 1;
            while (cx + run < wf.SOIL_N and row[cx + run] == id) run += 1;
            rl.drawRectangleRec(.{
                .x = @as(f32, @floatFromInt(px)) + @as(f32, @floatFromInt(cx)) * cellPx,
                .y = @as(f32, @floatFromInt(py)) + @as(f32, @floatFromInt(cz)) * cellPx,
                .width = @ceil(@as(f32, @floatFromInt(run)) * cellPx),
                .height = @ceil(cellPx),
            }, soilSwatch(@enumFromInt(id)));
            cx += run;
        }
    }
    // …then the RELIEF, as a hillshade: raised ground lightens, dug ground darkens, and the SLOPE darkens on top of that so a bank has an edge you can see.
    if (m.anyHeight()) {
        const RN: usize = 56; // …one shade block per four lattice points
        const rCellPx = inner / @as(f32, @floatFromInt(RN));
        const stride = wf.HEIGHT_N / RN;
        for (0..RN) |cz| {
            for (0..RN) |cx| {
                const i = (cz * stride) * wf.HEIGHT_N + cx * stride;
                const h = wf.heightOf(m.height[i]);
                if (@abs(h) < wf.HEIGHT_STEP) continue; // ground at the datum: leave the soil showing
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
    // …then the WATER over it, run-lengthed the same way.
    const wCellPx = inner / @as(f32, @floatFromInt(wf.WATER_N));
    for (0..wf.WATER_N) |cz| {
        const row = m.water[cz * wf.WATER_N ..][0..wf.WATER_N];
        var cx: usize = 0;
        while (cx < wf.WATER_N) {
            if (row[cx] == 0) {
                cx += 1;
                continue;
            }
            var run: usize = 1;
            while (cx + run < wf.WATER_N and row[cx + run] != 0) run += 1;
            rl.drawRectangleRec(.{
                .x = @as(f32, @floatFromInt(px)) + @as(f32, @floatFromInt(cx)) * wCellPx,
                .y = @as(f32, @floatFromInt(py)) + @as(f32, @floatFromInt(cz)) * wCellPx,
                .width = @ceil(@as(f32, @floatFromInt(run)) * wCellPx),
                .height = @ceil(wCellPx),
            }, WATER_SWATCH);
            cx += run;
        }
    }

    const toMini = struct {
        fn f(wx: f32, wz: f32, half: f32, ox: i32, oy: i32, span: f32) rl.Vector2 {
            return .{
                .x = @as(f32, @floatFromInt(ox)) + (wx + half) / (2 * half) * span,
                .y = @as(f32, @floatFromInt(oy)) + (wz + half) / (2 * half) * span,
            };
        }
    }.f;

    // Every op that has a place, as a dot; the active layer's at full strength.
    for (m.ops[0..m.nops]) |*o| {
        if (o.op == .cover or o.op == .edge) continue;
        const p = toMini(o.x, o.z, m.half, px, py, inner);
        const mine = layerOf(o) == ed.layer;
        const col = if (layerOf(o) == .decor) ui.col(96, 132, 70, if (mine) 235 else 70) else ui.col(168, 156, 130, if (mine) 235 else 70);
        rl.drawRectangleV(.{ .x = p.x - 1, .y = p.y - 1 }, .{ .x = 2, .y = 2 }, col);
    }
    for (m.foes[0..m.nfoes]) |f| {
        const p = toMini(f.x, f.z, m.half, px, py, inner);
        rl.drawCircleV(p, 2.5, ui.col(220, 120, 90, if (ed.layer == .units) 255 else 110));
    }
    // Where the camera is and which way it looks.
    const cp = toMini(ed.cam.position.x, ed.cam.position.z, m.half, px, py, inner);
    const f = ed.forward();
    rl.drawLineV(cp, .{ .x = cp.x + f.x * 12, .y = cp.y + f.z * 12 }, ui.HOT);
    rl.drawCircleV(cp, 3, ui.HOT);

    if (ctx.pressed and rl.checkCollisionPointRec(ctx.mouse, r)) {
        const t = (ctx.mouse.x - @as(f32, @floatFromInt(px))) / inner;
        const u = (ctx.mouse.y - @as(f32, @floatFromInt(py))) / inner;
        ed.lookAtGround(-m.half + t * 2 * m.half, -m.half + u * 2 * m.half, 60);
    }
    ui.tipFor(ctx, r, "Click to fly there");
}

/// HOW WATER READS IN THE CHROME — the brush swatch and the minimap, which are the only two places the editor draws the stuff as a flat colour.
const WATER_SWATCH = ui.col(32, 55, 62, 255);

fn soilSwatch(s: wf.Soil) rl.Color {
    return switch (s) {
        .none => ui.col(0, 0, 0, 0),
        .dirt => ui.col(112, 92, 64, 255),
        .turf => ui.col(70, 96, 44, 255),
        .stone => ui.col(122, 124, 120, 255),
        .silt => ui.col(146, 128, 88, 255),
        .ash => ui.col(62, 58, 54, 255),
        .moss => ui.col(52, 78, 40, 255),
    };
}

fn drawStatus(ed: *Editor, m: *const wf.Map, env: *const envmod.Env, ctx: *ui.Ctx, sw: i32, sh: i32) void {
    ui.panel(ctx, ui.rect(0, sh - STATUS_H, sw, STATUS_H), null);
    const ty = sh - STATUS_H + 5;

    // RIGHT FIRST, so the left side knows how much room is actually left.
    var buf: [200]u8 = undefined;
    const g = ed.groundAt() orelse mathx.zero3;
    // THE CURSOR'S HEIGHT rides beside its x/z, and only on a sculpted map: it is the number you are working to while shaping ground, and on a flat one it would be a column of 0.0 for ever.
    var hbuf: [24]u8 = undefined;
    const hs: [:0]const u8 = if (m.anyHeight())
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

    // LEFT, fitted into whatever is left over.
    const room = rightX - GUTTER; // px the left side may use before it touches the readout
    if (ed.statusT > 0 and ed.statusLen > 0) {
        // Truncated to fit, not just clipped: a message is authored text and can be any length, and the readout it would otherwise overdraw is the more useful of the two.
        var msg: [ui.MSG_CAP]u8 = undefined;
        var len = @min(ed.statusLen, msg.len - 1);
        @memcpy(msg[0..len], ed.status[0..len]);
        while (len > 4) {
            msg[len] = 0;
            if (CHROME_PAD + hud.monoW(msg[0..len :0], hud.MONO) <= room) break;
            len -= 1;
        }
        msg[len] = 0;
        hud.mono(msg[0..len :0], CHROME_PAD, ty, hud.MONO, ui.HOT);
        return;
    }
    // SHIFT+LMB DRAG IS IN HERE NOW, and its absence is worth recording: the marquee has worked on every op layer since it was written, was drawn while you dragged it, and was still asked for as a missing feature — because nothing on screen ever said it existed.
    const cribs = [_][:0]const u8{
        "LMB brush   Shift+LMB drag marquee   RMB menu / deselect, drag rotates   wheel zoom   WASD+arrows pan   Tab layer   Esc back",
        "LMB brush   Shift+LMB marquee   RMB menu, drag rotates   wheel zoom   WASD+arrows pan   Tab layer   Esc back",
        "LMB brush   Shift+LMB marquee   RMB menu/rotate   wheel zoom   WASD pan   Tab layer",
        "LMB brush   Shift marquee   Tab layer   Esc back",
    };
    for (cribs) |c| {
        if (CHROME_PAD + hud.monoW(c, hud.MONO) <= room) {
            hud.mono(c, CHROME_PAD, ty, hud.MONO, ui.alpha(ui.LABEL, 200));
            return;
        }
    }
}

// New / Open / Save-As, plus the confirm that stands in front of anything which would throw away unsaved work.

fn drawModal(ed: *Editor, m: *wf.Map, env: *envmod.Env, scene: *gfx.Scene, ctx: *ui.Ctx) void {
    // ENTER CONFIRMS, everywhere.
    const alt = rl.isKeyDown(.left_alt) or rl.isKeyDown(.right_alt);
    const confirm = rl.isKeyPressed(.enter) and !alt;
    switch (ed.modal) {
        .none => {},
        .confirm => {
            const box = ui.beginModal(ctx, 460, 170, "Unsaved changes");
            const y = box.y + 62;
            var buf: [wf.PATH_CAP + 40]u8 = undefined;
            const s = std.fmt.bufPrintZ(&buf, "{s} has unsaved edits.", .{ed.curPath()}) catch "";
            hud.mono(s, box.x + 24, y, hud.MONO, ui.VALUE);
            const by = box.y + 170 - 44;
            if (ui.button(ctx, ui.rect(box.x + 24, by, 120, 28), "Save first", hud.MONO, false) or confirm) {
                ed.saveNow(m);
                const what = ed.pending;
                ed.modal = .none;
                ed.commitPending(what);
                return;
            }
            if (ui.button(ctx, ui.rect(box.x + 154, by, 120, 28), "Discard", hud.MONO, false)) {
                const what = ed.pending;
                ed.dirty = false; // the discard IS the decision; don't ask twice
                ed.modal = .none;
                ed.commitPending(what);
                return;
            }
            if (ui.button(ctx, ui.rect(box.x + 300, by, 120, 28), "Cancel", hud.MONO, false)) {
                ed.modal = .none;
                ed.pending = .none;
            }
        },
        // op's `loot` list (weight by repetition, like `mix`), so this dialog reads and writes the map directly and there is nothing to apply or cancel: the edit is the edit, exactly as the properties panel's steppers work.
        .loot => {
            const rows: i32 = @intCast(item.NK);
            const box = ui.beginModal(ctx, 470, 96 + rows * 26 + 44, "Chest contents");
            const op: ?usize = if (ed.sel) |s| (if (s < m.nops and m.ops[s].kind == .chest) s else null) else null;
            if (op == null) {
                ed.modal = .none; // the selection went away under it
                return;
            }
            const o = &m.ops[op.?];
            var buf: [48]u8 = undefined;
            const total = std.fmt.bufPrintZ(&buf, "{d} / {d} items", .{ o.nloot, wf.MAX_LOOT }) catch "";
            hud.mono(total, box.x + 24, box.y + 58, hud.MONO, ui.LABEL);
            var i: usize = 0;
            while (i < item.NK) : (i += 1) {
                const k: item.Kind = @enumFromInt(i);
                const y = box.y + 84 + @as(i32, @intCast(i)) * 26;
                hud.mono(item.displayName(k), box.x + 24, y + 5, hud.MONO, ui.VALUE);
                const n = lootCount(o, k);
                var nbuf: [8]u8 = undefined;
                const ns = std.fmt.bufPrintZ(&nbuf, "{d}", .{n}) catch "0";
                hud.mono(ns, box.x + 340, y + 5, hud.MONO, if (n > 0) ui.VALUE else ui.LABEL);
                if (ui.button(ctx, ui.rect(box.x + 368, y, 24, 22), "-", hud.MONO, false)) {
                    lootRemove(o, k);
                    ed.dirty = true;
                }
                if (ui.button(ctx, ui.rect(box.x + 396, y, 24, 22), "+", hud.MONO, false)) {
                    lootAdd(o, k);
                    ed.dirty = true;
                }
            }
            if (ui.button(ctx, ui.rect(box.x + 24, box.y + 84 + rows * 26 + 8, 120, 28), "Done", hud.MONO, false) or confirm) {
                ed.modal = .none;
            }
        },
        // Deliberately not a tree or a search box: the enum is already ordered by FAMILY, so scrolling it is scrolling the creatures, and forty-odd rows is a list you look down, not one you query.
        .jukebox => {
            const box = ui.beginModal(ctx, JUKE_W, JUKE_H, "Sounds");
            if (ui.list(ctx, ui.rect(box.x + 20, box.y + 56, JUKE_LIST_W, JUKE_LIST_H), &VOICE_NAMES, ed.juke, &ed.jukeScroll)) |i| {
                ed.juke = i;
                ed.jukePlay(); // a click IS the audition — this is a listen tool, not a chooser
            }
            // The selected voice's own numbers, which are the ones you would be retuning.
            const nfo = sfx.voiceInfo(@enumFromInt(@min(ed.juke, VOICE_NAMES.len - 1)));
            const cx = box.x + 40 + JUKE_LIST_W;
            var cy = box.y + 56;
            var buf: [96]u8 = undefined;
            hud.mono(VOICE_NAMES[@min(ed.juke, VOICE_NAMES.len - 1)], cx, cy, hud.MONO, ui.TITLE);
            cy += ROW_H + 6;
            const rows = [_][:0]const u8{ "gain", "reach", "takes", "poly", "pitch jit", "level jit", "submix" };
            inline for (rows, 0..) |label, ri| {
                const val: [:0]const u8 = switch (ri) {
                    0 => std.fmt.bufPrintZ(&buf, "{d:.2}", .{nfo.gain}) catch "",
                    1 => std.fmt.bufPrintZ(&buf, "{d:.0} m", .{nfo.reach}) catch "",
                    2 => std.fmt.bufPrintZ(&buf, "{d}", .{nfo.vars}) catch "",
                    3 => std.fmt.bufPrintZ(&buf, "{d}", .{nfo.poly}) catch "",
                    4 => std.fmt.bufPrintZ(&buf, "{d:.2}", .{nfo.jit}) catch "",
                    5 => std.fmt.bufPrintZ(&buf, "{d:.2}", .{nfo.vjit}) catch "",
                    else => @tagName(nfo.mix),
                };
                hud.mono(label, cx, cy, hud.MONO, ui.LABEL);
                hud.mono(val, cx + 130, cy, hud.MONO, ui.VALUE);
                cy += ROW_H;
            }
            cy += 10;
            // WHERE it plays from.
            _ = ui.checkbox(ctx, cx, cy, "play out in the world", &ed.jukeWorld);
            cy += ROW_H;
            const ds = if (ed.jukeWorld)
                (std.fmt.bufPrintZ(&buf, "at the focus, {d:.0} m out - zoom to move it", .{ed.dist}) catch "")
            else
                "at the ear";
            hud.mono(ds, cx, cy, hud.MONO, ui.alpha(ui.LABEL, 170));
            const by = box.y + JUKE_H - 44;
            if (ui.button(ctx, ui.rect(box.x + 20, by, 150, 28), "Play again", hud.MONO, false) or confirm) ed.jukePlay();
            if (ui.button(ctx, ui.rect(box.x + 180, by, 120, 28), "Done", hud.MONO, false)) ed.modal = .none;
            hud.mono("up / down step and play, space replays", box.x + 320, by + 6, hud.MONO, ui.alpha(ui.LABEL, 150));
        },
        .new_map, .save_as => {
            const isNew = ed.modal == .new_map;
            const box = ui.beginModal(ctx, 460, 180, if (isNew) "New map" else "Save map as");
            hud.mono("name", box.x + 24, box.y + 58, hud.MONO, ui.LABEL);
            ui.textField(ctx, ui.rect(box.x + 24, box.y + 82, 412, 30), &ed.nameBuf, &ed.nameLen, true);
            // Show the path it will actually land on, so a name full of punctuation doesn't produce a file somewhere surprising.
            var buf: [wf.PATH_CAP]u8 = undefined;
            const p = wf.pathFor(&buf, ed.nameBuf[0..ed.nameLen]);
            var pz: [wf.PATH_CAP + 4]u8 = undefined;
            const ps = std.fmt.bufPrintZ(&pz, "{s}", .{p}) catch "";
            hud.mono(ps, box.x + 24, box.y + 118, hud.MONO, ui.alpha(ui.LABEL, 190));
            const by = box.y + 180 - 44;
            const go = ui.button(ctx, ui.rect(box.x + 24, by, 130, 28), if (isNew) "Create" else "Save", hud.MONO, false);
            if (go or confirm) {
                ed.modal = .none;
                if (isNew) ed.doNew(m, env) else ed.doSaveAs(m);
                return;
            }
            if (ui.button(ctx, ui.rect(box.x + 164, by, 120, 28), "Cancel", hud.MONO, false)) ed.modal = .none;
        },
        .open_map => {
            const box = ui.beginModal(ctx, 460, 380, "Open map");
            var labels: [wf.MAX_FILES][:0]const u8 = undefined;
            for (0..listing.n) |i| labels[i] = listing.name(i);
            if (listing.n == 0) {
                hud.mono("no maps in worlds/", box.x + 24, box.y + 62, hud.MONO, ui.LABEL);
            } else if (ui.list(ctx, ui.rect(box.x + 24, box.y + 54, 412, 258), labels[0..listing.n], ed.fileSel, &ed.fileScroll)) |i| {
                ed.fileSel = i;
            }
            const by = box.y + 380 - 44;
            if ((ui.button(ctx, ui.rect(box.x + 24, by, 130, 28), "Open", hud.MONO, false) or confirm) and listing.n > 0) {
                ed.modal = .none;
                ed.doOpen(m, env, ed.fileSel);
                return;
            }
            if (ui.button(ctx, ui.rect(box.x + 164, by, 120, 28), "Cancel", hud.MONO, false)) ed.modal = .none;
        },
        // THE OBJECT VIEWER owns its own two levels (gallery / one object) inside this one modal slot — see objview.zig.
        .objects => {
            if (!objview.draw(&ed.objects, env, scene, ctx)) ed.modal = .none;
        },
    }
}

// RIGHT-CLICK menu on the selection — the operations you reach for often enough that hunting them in the properties panel is friction.
const MenuItem = enum { view, loot, focus, reroll, duplicate, delete, close };

const menuRows = [_]struct { act: MenuItem, label: [:0]const u8 }{
    // `view` gets its label FILLED IN at draw time with the kind's own name — "View Dead Tree…", not "View…", because the row is about one specific model and the point is knowing which.
    .{ .act = .view, .label = "View…" },
    // …and ITEMS is live only on a chest (see `menuEnabled`) — the one prop that HOLDS anything, so the one prop with contents to edit.
    .{ .act = .loot, .label = "Items…" },
    .{ .act = .focus, .label = "Focus" },
    .{ .act = .reroll, .label = "Re-roll" },
    .{ .act = .duplicate, .label = "Duplicate" },
    .{ .act = .delete, .label = "Delete" },
    .{ .act = .close, .label = "Close" },
};

const MENU_W: i32 = 150; // the FLOOR; the menu grows to fit its widest row (see drawContextMenu)
const MENU_EDGE: i32 = 4; // clear space kept between the menu and the screen edge

/// Can this row do anything to what is selected right now?

fn lootCount(o: *const wf.Op, k: item.Kind) u8 {
    var n: u8 = 0;
    for (o.loot[0..o.nloot]) |it| {
        if (it == k) n += 1;
    }
    return n;
}

fn lootAdd(o: *wf.Op, k: item.Kind) void {
    if (o.nloot >= wf.MAX_LOOT) return; // full: the counter above says so, so this needs no complaint
    o.loot[o.nloot] = k;
    o.nloot += 1;
}

fn lootRemove(o: *wf.Op, k: item.Kind) void {
    var i: u8 = 0;
    while (i < o.nloot) : (i += 1) {
        if (o.loot[i] != k) continue;
        o.loot[i] = o.loot[o.nloot - 1]; // swap the last one down — order carries no meaning here
        o.nloot -= 1;
        return;
    }
}

fn menuEnabled(ed: *const Editor, m: *const wf.Map, act: MenuItem) bool {
    const op: ?usize = if (ed.sel) |s| (if (s < m.nops) s else null) else null;
    return switch (act) {
        .close => true,
        .focus => op != null,
        // The ground COVER op places from a zone's mix rather than from a kind of its own, so there is no one model for this row to open.
        .view => if (op) |s| m.ops[s].op != .cover else false,
        // Only a LITERAL chest has contents to edit.
        .loot => if (op) |s| (m.ops[s].op == .at and m.ops[s].kind == .chest) else false,
        .reroll, .duplicate => if (op) |s| isMovable(&m.ops[s]) else false,
        .delete => op != null or (ed.layer == .units and ed.selFoe != null),
    };
}

/// The `view` row's label, naming the model it opens.
fn viewLabel(ed: *const Editor, m: *const wf.Map, buf: []u8) [:0]const u8 {
    const s = ed.sel orelse return "View…";
    if (s >= m.nops or m.ops[s].op == .cover) return "View…";
    return std.fmt.bufPrintZ(buf, "View {s}…", .{props.displayName(m.ops[s].kind)}) catch "View…";
}

fn drawContextMenu(ed: *Editor, m: *wf.Map, env: *envmod.Env, ctx: *ui.Ctx) void {
    const menuH: i32 = ROW_H * @as(i32, @intCast(menuRows.len)) + 6;
    // The menu SIZES ITSELF to its widest row: the view row carries a model's display name, and "View Woodcutter's Cottage…" is twice the width of "Duplicate".
    var lbuf: [64]u8 = undefined;
    const viewRow = viewLabel(ed, m, &lbuf);
    var menuW: i32 = MENU_W;
    for (menuRows) |row| {
        const label = if (row.act == .view) viewRow else row.label;
        menuW = @max(menuW, hud.monoW(label, hud.MONO) + 26);
    }
    // BOTH axes come from where the menu was OPENED, never the live cursor: anchoring x to ctx.mouse slid the panel sideways under the pointer as you reached for a row.
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
            // Straight into the object viewer on this op's kind — the "why does this thing look wrong" question, answered where you asked it.
            .view => if (ed.sel) |s| {
                if (s < m.nops) {
                    ed.objects.show(m.ops[s].kind);
                    ed.modal = .objects;
                }
            },
            .loot => ed.modal = .loot,
            .focus => if (ed.sel) |s| ed.focusOn(m, s),
            .reroll => ed.rerollSel(m, env),
            .duplicate => ed.duplicateSel(m, env),
            .delete => ed.deleteSel(m, env),
            .close => {},
        }
        return;
    }
    // A click anywhere else dismisses it.
    if (ctx.pressed and !rl.checkCollisionPointRec(ctx.mouse, box)) ed.menuOpen = false;
}


/// A bare Env for the erase tests.
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

    // HOLDING STILL: the first tick takes the spawn under the brush, and no amount of further time on the same spot takes another.
    ed.wipeStep(m, env, v3(0, 0, 0));
    try std.testing.expectEqual(@as(usize, 3), m.nfoes);
    for (0..30) |_| {
        ed.wipe.t = 1.0; // rate gate wide open; only the travel gate is under test
        ed.wipeStep(m, env, v3(0, 0, 0));
    }
    try std.testing.expectEqual(@as(usize, 3), m.nfoes);

    // SWEEPING: moving onto each of the others takes them, one per step.
    for ([_]f32{ 4, 8, 12 }) |x| {
        ed.wipe.t = 1.0;
        ed.wipeStep(m, env, v3(x, 0, 0));
    }
    try std.testing.expectEqual(@as(usize, 0), m.nfoes);

    // ONE undo step for the whole stroke, and it restores every spawn — four separate steps would have filled a sixth of the ring and made the sweep four Ctrl+Zs to take back.
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

    // Travelled far enough but the rate gate has not elapsed: the second spawn survives.
    ed.wipeStep(m, env, v3(0, 0, 0));
    try std.testing.expectEqual(@as(usize, 1), m.nfoes);
    ed.wipe.t = 0;
    ed.wipeStep(m, env, v3(6, 0, 0));
    try std.testing.expectEqual(@as(usize, 1), m.nfoes);
    ed.wipe.t = 1.0 / ERASE_HZ;
    ed.wipeStep(m, env, v3(6, 0, 0));
    try std.testing.expectEqual(@as(usize, 0), m.nfoes);

    // A stroke over empty ground banks nothing and leaves the map clean — the editor must not ask you to save a sweep that removed nothing.
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
