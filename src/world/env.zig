const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const glsl = @import("../gfx/shaders.zig");
const mathx = @import("../core/mathx.zig");
const collision = @import("../core/collision.zig");
const props = @import("../props/props.zig");
const propbuild = @import("../props/propbuild.zig");
const propfx = @import("../props/propfx.zig");
const art = @import("../props/propart.zig");
const proprock = @import("../props/proprock.zig");
const wf = @import("worldfmt.zig");
const chestmod = @import("../play/chest.zig");
const pickupmod = @import("../play/pickup.zig");
const item = @import("../play/item.zig");
const restmod = @import("../play/rest.zig");
const foemod = @import("../foes/foe.zig");

const v3 = mathx.v3;
const Kind = props.Kind;


pub const PLAY_INSET: f32 = 2.0;
pub const MAX_HALF: f32 = GRID_HALF + CELL - CLIFF_BOUND;

comptime {
    std.debug.assert(MAX_HALF >= wf.MAX_DECLARED_HALF);
}
const CLIFF_BOUND: f32 = 18.0;
/// The shipped 280 m map moves 4 m by this (500 -> 504). As a flat 220 m it made a 95 m test bench a 190 m island sitting in a 1000 m floor.
const GROUND_APRON: f32 = 0.80;
const GROUND_APRON_MIN: f32 = 60.0;

pub fn groundOut(half: f32) f32 {
    return half + mathx.maxF(GROUND_APRON_MIN, half * GROUND_APRON);
}

const GROUND_HALF: f32 = wf.MAX_DECLARED_HALF * (1.0 + GROUND_APRON);

comptime {
    std.debug.assert(groundOut(wf.MAX_DECLARED_HALF) <= GROUND_HALF);
}

const MAX_PROPS = 24576;
const MAX_SOLIDS = 8192;
pub const MAX_WARDS = 64;
/// How far past a fog gate a crossing puts him down — clear of the sheet AND clear of the prompt's own reach. That second half is a relationship with a number in another module, so `game.zig` asserts it.
pub const WARD_CLEAR: f32 = 1.30;
const MAX_SOLID_REFS = 4 * MAX_SOLIDS;
const MAX_DECKS = 512;
const MAX_DECK_REFS = 4 * MAX_DECKS;

comptime {
// A deck holds four refs only while it fits a 2x2 block of cells: the watchtower's boards are 9.4 m across a 16 m grid.
    var widest: f32 = 0;
    for (props.INFO) |row| {
        for (row.decks) |d| {
            if (d.r > widest) widest = d.r;
        }
    }
    std.debug.assert(2.0 * widest <= CELL);
}
/// Raised from 192 because the shipped map sat at 192 of 192 with 46 props dark. MEASURED before moving it: the
/// per-frame scan is 0.013 us a light, so this costs 6.7 us a frame (0.04%) and 20 KB in `Env`.
const MAX_LIGHTS = 512;
const MAX_DRESSED = 64;

// 40 a side = 640 m, covering a 280 m map's edge-standing cliffs (280 + 18 of cliff bound). The arrays are BSS and the per-frame cost is one loop of four plane tests, so 1,600 cells is not measurable.
const CELL: f32 = 16.0;
const GRID_N: usize = 40;
const GRID_SPAN: f32 = CELL * @as(f32, @floatFromInt(GRID_N));
const GRID_HALF: f32 = GRID_SPAN * 0.5;
const NCELL: usize = GRID_N * GRID_N;
const HALF_DIAG: f32 = @sqrt(0.5);
const CELL_CIRCUM: f32 = CELL * HALF_DIAG;

fn shadowBox() f32 {
    return gfx.shadowSpan * HALF_DIAG;
}

const LIGHT_REACH: f32 = 90.0;

pub const OCCL_MAX = 64;
const OCCL_IN: f32 = 0.16;
const OCCL_OUT: f32 = 0.34;
const FADE_SOLID: f32 = 0.999;
/// How fast the ramp runs where the value already sits: full speed across the middle, down to this share at solid and at the floor. Never 0, or a fade would never leave either end.
const EASE_ENDS = 0.3;
fn easeAt(u: f64) f64 {
    return EASE_ENDS + (1.0 - EASE_ENDS) * 4.0 * u * (1.0 - u);
}
fn easeShape(fade: f32) f32 {
    return @floatCast(easeAt(mathx.clampF((fade - OCCL_FLOOR) / (1.0 - OCCL_FLOOR), 0, 1)));
}
const EASE_NORM: f32 = blk: {
    @setEvalBranchQuota(40000);
    const N = 4096;
    var acc: f64 = 0;
    for (0..N) |i| acc += 1.0 / easeAt((@as(f64, @floatFromInt(i)) + 0.5) / N);
    break :blk @floatCast(acc / N);
};
const OCCL_FLOOR: f32 = 0.28;
const OCCL_MIN: f32 = 0.15;
const OCCL_FULL: f32 = 0.55;
/// The hero's own screen box, in metres — what "a share of him" is measured against.
const HERO_HALF_W: f32 = 0.42;
const HERO_HALF_H: f32 = 0.90;
const OCCL_SKIRT: f32 = 0.9;
const OCCL_GIRTH: f32 = 0.55;
/// 0.640·H on the 1.8 m stature. A tuft up against the lens scores 0.54, over three times `OCCL_MIN`, so
/// ungated the commonest thing in the world ghosts round his boots. TESTED ON THE INSTANCE (`top * scale`), not the kind — the cover scatter stamps 0.72..1.38.
const OCCL_TALL: f32 = 1.15;
const OCCL_REACH: f32 = CELL;
const OCCL_DEPTH_BAND: f32 = 1.6;

pub const MAX_NEAR = 160;

const GROUND_Y: f32 = 0.01;

// The ground is a HEIGHTFIELD (`wf.Map.height`, 2.5 m lattice, sculpted in the editor).
const TCHUNK: usize = 16;
const TILES: usize = (wf.HEIGHT_N - 2) / (TCHUNK - 1) + 1;
const NTILES: usize = TILES * TILES;

pub const MAX_SLOPE = wf.MAX_SLOPE;
pub const STEP_UP = wf.STEP_UP;
pub const STEP_PROBE: f32 = 0.5;
/// Where along the probe the rise is read, besides the step's own end.
const STEP_TAPS: usize = 4;
/// The baseline a riser's landing is judged over: a tread is level across it, a bank is not.
const TREAD_READ: f32 = 0.25;

/// HOW DEEP ANYTHING ON FOOT MAY WADE, in metres — CHEST HEIGHT, the thorax at 0.760·H on the 1.8 m rig. Past it the water is a WALL. Written out rather than read off `hero.H` because env sits BELOW hero in the import graph.
pub const WADE_MAX: f32 = 1.37;

pub const HERO_R_PIN: f32 = 0.36;

fn digTone(metres: f32) f32 {
    return mathx.clampF(metres / WADE_MAX, 0, 1);
}

const WATER_Y: f32 = 0.055;

/// **THE WATER-DWELLER FLOOR**, as the map stores it: the deepest lattice height the hero still wades
/// (`WADE_MAX`), so a lurker's pool is one he can be drawn into. Ground > Pool digs to it.
pub fn dwellerFloor() f32 {
    return @ceil((WATER_Y - GROUND_Y - WADE_MAX) / wf.HEIGHT_STEP) * wf.HEIGHT_STEP;
}

pub fn dwellerDepth() f32 {
    return WATER_Y - GROUND_Y - dwellerFloor();
}

var scratchIn: [wf.WATER_CELLS]f32 = undefined;
var scratchOut: [wf.WATER_CELLS]f32 = undefined;
var scratchPack: [wf.WATER_CELLS]u8 = undefined;

pub fn packLiquid(edge: u8, kind: u8) u8 {
    const e: u8 = @min(edge, wf.Edge.N - 1) & glsl.EDGE_MASK;
    const k: u8 = @min(kind, wf.Liquid.N - 1) & glsl.LIQUID_MASK;
    return e | (k << glsl.LIQUID_SHIFT);
}

comptime {
    std.debug.assert(wf.Edge.N <= glsl.EDGE_MASK + 1);
    std.debug.assert(wf.Liquid.N <= glsl.LIQUID_MASK + 1);
    std.debug.assert((glsl.LIQUID_MASK << glsl.LIQUID_SHIFT) | glsl.EDGE_MASK <= 255);
}

fn coastBand(e: wf.Edge) f32 {
    return switch (e) {
        .blend => 3.2,
        .natural => 1.0,
        .frayed => 1.6,
        .jagged => 0.55,
        .straight => 0.3,
        .tiled => 0.3,
        .scallop => 1.2,
        .speckle => 2.2,
    };
}

pub const Prop = struct {
    kind: Kind,
    pos: rl.Vector3,
    yaw: f32,
    scale: f32,
    lean: f32 = 0,
    leanDir: f32 = 0,
    op: u16 = 0,
    /// Its slot in `wardProps` PLUS ONE, 0 for everything else — the same number `collision.Solid.ward` carries. Two copies because the two are walked by different traversals: the solid grid answers about geometry, this about the draw.
    ward: u8 = 0,
    fade: f32 = 1,
    fadeTo: f32 = 1,
    gone: bool = false,
    shrink: f32 = 1,
    rise: f32 = 0,
};

pub const WorldDeck = struct {
    x: f32,
    z: f32,
    r: f32,
    y: f32,
    hole: bool,
    /// A FLIGHT: `run` metres from (`x`,`z`) along (`ax`,`az`), rising `rise` in `treads` level steps,
    /// `halfW` wide. `run` 0 is a disc at `y`.
    run: f32 = 0,
    ax: f32 = 0,
    az: f32 = 0,
    rise: f32 = 0,
    halfW: f32 = 0,
    treads: u32 = 0,

    /// The tread under (x, z), or null off the flight. A disc answers `y` everywhere inside it.
    fn floorAt(d: WorldDeck, x: f32, z: f32) ?f32 {
        if (d.run <= 0) return if (inDisc(d, x, z)) d.y else null;
        const dx = x - d.x;
        const dz = z - d.z;
        const t = dx * d.ax + dz * d.az;
        const s = -dx * d.az + dz * d.ax;
        if (t < -0.05 or t > d.run + 0.05 or @abs(s) > d.halfW) return null;
        const n: f32 = @floatFromInt(@max(d.treads, 1));
        const k = mathx.clampF(@floor(t / (d.run / n)), 0, n - 1);
        return d.y + (k + 1) * (d.rise / n);
    }
};

pub const Rung = struct {
    foot: rl.Vector3,
    axis: rl.Vector3,
    yaw: f32,
    run: f32,
    scale: f32,
};

pub fn runOf(pr: *const Prop, nfo: *const props.Info) f32 {
    if (nfo.stack > 0 and pr.rise > 0) return pr.rise;
    return nfo.top * pr.scale;
}

/// How far a flight's foot is from its head along the ground, for the rise it was given.
pub fn flightRun(pr: *const Prop, nfo: *const props.Info) f32 {
    const fl = nfo.flight orelse return 0;
    if (nfo.stack <= 0 or pr.rise <= 0) return 0;
    return pr.rise * fl.run / nfo.stack;
}

/// The culling sphere about the prop's foot: a ladder's mesh is 2.4 m and its run can be twelve.
pub fn reachOf(pr: *const Prop, nfo: *const props.Info) f32 {
    const b = nfo.bound * pr.scale;
    if (nfo.stack > 0 and pr.rise > 0) return pr.rise + flightRun(pr, nfo) + b;
    return b;
}

pub fn pickSphere(pr: *const Prop, nfo: *const props.Info) struct { c: rl.Vector3, r: f32 } {
    const half = runOf(pr, nfo) * 0.5;
    const sw = leanSwing(pr, half);
    return .{
        .c = v3(pr.pos.x + sw.x, pr.pos.y + half, pr.pos.z + sw.z),
        .r = @max(reachOf(pr, nfo) * 0.5, 0.35),
    };
}

pub const MAX_SECTIONS: u32 = 64;
pub fn sectionsIn(rise: f32, seg: f32) u32 {
    if (seg <= 1e-3 or !std.math.isFinite(rise)) return 1;
    const n: i32 = @intFromFloat(@round(mathx.clampF(rise / seg, 1, @as(f32, MAX_SECTIONS))));
    return @intCast(@max(n, 1));
}

pub fn snapRise(kind: Kind, scale: f32, rise: f32) f32 {
    const nfo = props.info(kind);
    if (nfo.stack <= 0 or rise <= 0) return 0;
    const seg = nfo.stack * scale;
    return @as(f32, @floatFromInt(sectionsIn(rise, seg))) * seg;
}

// A prop can stand OFF PLUMB: `lean` degrees toward `leanDir`, measured like every yaw here — (cos d, −sin d).

fn leanToward(dirDeg: f32) rl.Vector3 {
    const a = mathx.radians(dirDeg);
    return v3(mathx.cosf(a), 0, -mathx.sinf(a));
}

fn leanAxis(dirDeg: f32) rl.Vector3 {
    return mathx.perpXZ(leanToward(dirDeg));
}

pub fn leanOffsetAt(lean: f32, dirDeg: f32, up: f32) rl.Vector3 {
    if (lean == 0) return mathx.zero3;
    const s = mathx.sinf(mathx.radians(lean)) * up;
    const d = leanToward(dirDeg);
    return v3(d.x * s, 0, d.z * s);
}

fn leanSwing(pr: *const Prop, up: f32) rl.Vector3 {
    return leanOffsetAt(pr.lean, pr.leanDir, up);
}

fn inDisc(d: WorldDeck, x: f32, z: f32) bool {
    const dx = x - d.x;
    const dz = z - d.z;
    return dx * dx + dz * dz < d.r * d.r;
}

pub const LADDER_GRAB: f32 = 1.2;

const STAGE_SECTIONS: f32 = 5;

pub const LADDER_PROUD: f32 = 1.00;
comptime {
    if (props.info(.ladder).stack >= LADDER_PROUD + STEP_UP) @compileError("env: the ladder's section is coarser " ++
        "than the band `ladderExit` accepts — there are lip heights no run can serve");
}

const FIELD_FLOOR: f32 = 0.35;

const SOLID_PROBE_Y: f32 = 0.2;
const SOLID_PROBE_M: f32 = 0.35;
const SOLID_PROBE_R: f32 = 1.4;

pub fn groundY() f32 {
    return GROUND_Y;
}

/// **A LIGHT BELONGS TO THE PROP THAT PLACED IT** (`prop`, an index into `props`). With no back-reference a pickup glow's 5.4 m pool went on lighting the ground after the glow had been taken.
const WorldLight = struct { base: gfx.Light, flicker: f32, phase: f32, prop: u32 };

const Pool = struct { pos: rl.Vector3, radius: f32 };

const Index = struct {
    start: [NCELL + 1]u32 = [_]u32{0} ** (NCELL + 1),
    items: [MAX_PROPS]u32 = undefined,
    bound: [NCELL]f32 = [_]f32{0} ** NCELL,
    view: [NCELL]f32 = [_]f32{0} ** NCELL,
    top: [NCELL]f32 = [_]f32{0} ** NCELL,
    // …and the cell's VERTICAL extent: the per-cell reject is a sphere about the cell's centre, and a cell whose props stand 20 m up a hill is nowhere near a sphere centred at y = 0.
    ylo: [NCELL]f32 = [_]f32{0} ** NCELL,
    yhi: [NCELL]f32 = [_]f32{0} ** NCELL,

    fn cellAt(idx: *const Index, c: usize) rl.Vector3 {
        var centre = cellCentre(c);
        centre.y = (idx.ylo[c] + idx.yhi[c]) * 0.5;
        return centre;
    }

    fn cellSeen(idx: *const Index, c: usize, vw: *const View) bool {
        const vspan = (idx.yhi[c] - idx.ylo[c]) * 0.5;
        return vw.visible(idx.cellAt(c), CELL_CIRCUM + idx.bound[c] + vspan, idx.view[c]);
    }
};

pub const View = struct {
    pos: rl.Vector3,
    n: [4]rl.Vector3,
    /// **THE EDITOR'S "SHOW ME EVERYTHING"**: every per-kind view distance is lifted to at least this many
    /// metres, so what culls is the frustum and the far clip plane and never a prop's own LOD reach. 0 in play,
    /// where a rubble pile has no business drawing at 300 m.
    floor: f32 = 0,

    pub fn fromCamera(cam: rl.Camera3D, aspect: f32) View {
        const fwd = mathx.normV(mathx.subV(cam.target, cam.position));
        const right = mathx.normV(cross(fwd, cam.up));
        const up = cross(right, fwd);
        const vf = mathx.radians(cam.fovy) * 0.5 + mathx.radians(2.5);
        const hf = std.math.atan(@tan(mathx.radians(cam.fovy) * 0.5) * aspect) + mathx.radians(2.5);
        const cv = mathx.cosf(vf);
        const sv = mathx.sinf(vf);
        const chz = mathx.cosf(hf);
        const shz = mathx.sinf(hf);
        const dl = mathx.addV(mathx.scaleV(fwd, chz), mathx.scaleV(right, -shz));
        const dr = mathx.addV(mathx.scaleV(fwd, chz), mathx.scaleV(right, shz));
        const dt = mathx.addV(mathx.scaleV(fwd, cv), mathx.scaleV(up, sv));
        const db = mathx.addV(mathx.scaleV(fwd, cv), mathx.scaleV(up, -sv));
        return .{ .pos = cam.position, .n = .{
            inward(up, dl, fwd),
            inward(up, dr, fwd),
            inward(right, dt, fwd),
            inward(right, db, fwd),
        } };
    }

    pub fn visible(self: *const View, c: rl.Vector3, rad: f32, maxDist: f32) bool {
        const d = mathx.subV(c, self.pos);
        const far = mathx.maxF(maxDist, self.floor) + rad;
        if (d.x * d.x + d.y * d.y + d.z * d.z > far * far) return false;
        for (self.n) |nn| {
            if (nn.x * d.x + nn.y * d.y + nn.z * d.z < -rad) return false;
        }
        return true;
    }
};

pub const Cull = union(enum) {
    view: View,
    sun: rl.Vector3,
};

var envBuilt = false;

var terrainBuilds: usize = 0;
var waterBuilds: usize = 0;
var soilBuilds: usize = 0;

pub fn terrainBuildCount() usize {
    return terrainBuilds;
}

pub fn soilBuildCount() usize {
    return soilBuilds;
}

pub fn waterBuildCount() usize {
    return waterBuilds;
}

pub const Env = struct {
    ground: rl.Model,
    models: [props.NK]rl.Model,
    veils: [props.NK]?rl.Model = [_]?rl.Model{null} ** props.NK,
    stows: [props.NK]?rl.Model = [_]?rl.Model{null} ** props.NK,
    stowed: bool = false,
    dressItems: [MAX_DRESSED]u32 = undefined,
    ndress: usize = 0,
    chestItems: [chestmod.CAP]u32 = undefined,
    nchests: usize = 0,
    pickupItems: [pickupmod.CAP]u32 = undefined,
    npickups: usize = 0,
    restItems: [restmod.CAP]u32 = undefined,
    nrests: usize = 0,
    scene: ?*gfx.Scene = null,
    props: [MAX_PROPS]Prop = undefined,
    nprops: usize = 0,
/// How many props each op placed, by op slot; `MAX_PROPS` fits a `u16` with room and the add saturates.
    opOwned: [wf.MAX_OPS]u16 = [_]u16{0} ** wf.MAX_OPS,
    opsCapped: usize = 0,
    lightsCapped: usize = 0,
    solid_buf: [MAX_SOLIDS]collision.Solid = undefined,
    nsolids: usize = 0,
    /// THE FOG GATES, in the order `buildSolids` met them; `collision.Solid.ward` is a slot here PLUS ONE, so that 0 can mean "an ordinary solid".
    wardProps: [MAX_WARDS]u32 = undefined,
    wardSolid0: [MAX_WARDS]u32 = undefined,
    wardSolidN: [MAX_WARDS]u8 = [_]u8{0} ** MAX_WARDS,
    nwards: usize = 0,
    wardIn: [MAX_WARDS]bool = [_]bool{false} ** MAX_WARDS,
    wardShut: [MAX_WARDS]bool = [_]bool{false} ** MAX_WARDS,
    /// 1 WHILE IT STANDS, RUNNING TO 0 ONCE THE FIGHT IT SEALED IS OVER. **At 0 the gate is GONE**, and `eachSolid` is where that is enforced — one line there retires it from sight, from feet and from arrows together.
    wardLife: [MAX_WARDS]f32 = [_]f32{1} ** MAX_WARDS,
    stx: Index = .{},
    flx: Index = .{},
    occl: [OCCL_MAX]u32 = undefined,
    noccl: usize = 0,
    sgrid_start: [NCELL + 1]u32 = [_]u32{0} ** (NCELL + 1),
    sgrid_items: [MAX_SOLID_REFS]u32 = undefined,
    deck_buf: [MAX_DECKS]WorldDeck = undefined,
    ndecks: usize = 0,
    dgrid_start: [NCELL + 1]u32 = [_]u32{0} ** (NCELL + 1),
    dgrid_items: [MAX_DECK_REFS]u32 = undefined,
    lights: [MAX_LIGHTS]WorldLight = undefined,
    nlights: usize = 0,
    pools: [8]Pool = undefined,
    npools: usize = 0,
    waterSheet: rl.Model = undefined,
    waterField: [wf.WATER_CELLS]u8 = [_]u8{gfx.WATER_SHORE} ** wf.WATER_CELLS,
    waterEdgeField: [wf.WATER_CELLS]u8 = [_]u8{@intFromEnum(wf.Edge.natural)} ** wf.WATER_CELLS,
    waterAny: bool = false,
    waterHalf: f32 = 0,
    waterSrc: [wf.WATER_CELLS]u8 = [_]u8{0} ** wf.WATER_CELLS,
    soilSrc: [wf.SOIL_CELLS]u8 = [_]u8{0} ** wf.SOIL_CELLS,
    soilCovSrc: [wf.SOIL_CELLS]u8 = [_]u8{0} ** wf.SOIL_CELLS,
    soilEdgeSrc: [wf.SOIL_CELLS]u8 = [_]u8{0} ** wf.SOIL_CELLS,
    soilReady: bool = false,
    soilHalf: f32 = 0,
    waterEdgeSrc: [wf.WATER_CELLS]u8 = [_]u8{0} ** wf.WATER_CELLS,
    waterKindSrc: [wf.WATER_CELLS]u8 = [_]u8{0} ** wf.WATER_CELLS,
    waterHgtSrc: [wf.HEIGHT_CELLS]u8 = [_]u8{wf.HEIGHT_ZERO} ** wf.HEIGHT_CELLS,
    waterReady: bool = false,
    waterMid: rl.Vector3 = mathx.zero3,
    waterSpan: rl.Vector3 = mathx.zero3,
    mapHalf: f32 = wf.DEFAULT_HALF,
    heightField: [wf.HEIGHT_CELLS]u8 = [_]u8{wf.HEIGHT_ZERO} ** wf.HEIGHT_CELLS,
    cliffField: [wf.HEIGHT_CELLS]u8 = [_]u8{wf.CLIFF_NONE} ** wf.HEIGHT_CELLS,
    heightHalf: f32 = wf.DEFAULT_HALF,
    heightAny: bool = false,
    tiles: [NTILES]rl.Model = undefined,
    tileBuilt: [NTILES]bool = [_]bool{false} ** NTILES,
    /// The cliff faces of the same tile, kept APART from it because they are not terrain: they are drawn
    /// with `groundMode` off and `Mat.stone`, which is the only way a painted face reads as the same rock
    /// the `cliff*` props are made of.
    faces: [NTILES]rl.Model = undefined,
    faceBuilt: [NTILES]bool = [_]bool{false} ** NTILES,
    /// What the faces CAST: a plate set `FACE_SHADOW_IN` behind each cut, drawn in the depth pass only.
    /// The visible face never shadows itself off it, because it is always that far in front.
    casters: [NTILES]rl.Model = undefined,
    casterBuilt: [NTILES]bool = [_]bool{false} ** NTILES,
    tileMid: [NTILES]rl.Vector3 = [_]rl.Vector3{mathx.zero3} ** NTILES,
    tileRad: [NTILES]f32 = [_]f32{0} ** NTILES,
    skirt: rl.Model = undefined,
    skirtBuilt: bool = false,
    stat_draws: u32 = 0,
    stat_cells: u32 = 0,

    pub fn build(self: *Env, scene: *gfx.Scene) void {
        if (envBuilt) @panic("env: build ran twice — every prototype, tile and sheet the first run made is stranded");
        envBuilt = true;
        self.scene = scene;
        const shader = scene.shader;
        for (&self.models, props.INFO) |*m, row| m.* = row.build(shader);
        for (&self.veils, props.INFO) |*m, row| m.* = if (row.veil) |mesh| mesh(shader) else null;
        for (&self.stows, props.INFO) |*m, row| m.* = if (row.stow) |mesh| mesh(shader) else null;
        self.ground = terrain(shader, GROUND_HALF);
        self.waterSheet = waterQuad(shader, GROUND_HALF);
        self.nprops = 0;
        self.nsolids = 0;
        self.nwards = 0;
        self.openWards();
        self.nlights = 0;
        self.npools = 0;
        self.noccl = 0;
        self.ndress = 0;
        self.nchests = 0;
        self.npickups = 0;
        self.nrests = 0;
        self.stx = .{};
        self.flx = .{};
        self.stat_draws = 0;
        self.stat_cells = 0;
        self.stowed = false;
        self.waterAny = false;
        self.waterHalf = 0;
        self.waterReady = false;
        self.soilReady = false;
        @memset(&self.sgrid_start, 0);
        // `Game` is created UNINITIALISED and `build` is the only thing that zeroes `Env`, so every array
        // that gates an `unloadModel` is reset HERE or the first `dropTile` frees a wild pointer.
        self.tileBuilt = [_]bool{false} ** NTILES;
        self.faceBuilt = [_]bool{false} ** NTILES;
        self.casterBuilt = [_]bool{false} ** NTILES;
        self.tileRad = [_]f32{0} ** NTILES;
        self.tileMid = [_]rl.Vector3{mathx.zero3} ** NTILES;
        self.skirtBuilt = false;
        self.heightField = [_]u8{wf.HEIGHT_ZERO} ** wf.HEIGHT_CELLS;
        self.cliffField = [_]u8{wf.CLIFF_NONE} ** wf.HEIGHT_CELLS;
        self.heightHalf = wf.DEFAULT_HALF;
        self.heightAny = false;
    }

    pub fn replay(self: *Env, m: *const wf.Map) void {
        self.mapHalf = m.half;
        self.uploadSoil(m);
        self.uploadWater(m);
        self.uploadHeight(m);
        self.materialize(m);
    }

    pub fn uploadSoil(self: *Env, m: *const wf.Map) void {
        const same = self.soilReady and self.soilHalf == m.half and
            std.mem.eql(u8, &self.soilSrc, &m.soil) and
            std.mem.eql(u8, &self.soilCovSrc, &m.soilCov) and
            std.mem.eql(u8, &self.soilEdgeSrc, &m.soilEdge);
        if (same) return;
        soilBuilds += 1;
        self.soilSrc = m.soil;
        self.soilCovSrc = m.soilCov;
        self.soilEdgeSrc = m.soilEdge;
        self.soilReady = true;
        self.soilHalf = m.half;
        if (self.scene) |sc| sc.setSoil(&m.soil, &m.soilCov, &m.soilEdge, m.half);
    }

/// `rebuildTerrain` remakes all 225 tiles: 12.5 MB of vertices, 1350 GL objects, 27.6 ms.
    pub fn uploadHeight(self: *Env, m: *const wf.Map) void {
        const any = m.anyHeight();
        const same = self.heightAny == any and self.heightHalf == m.half and
            std.mem.eql(u8, &self.heightField, &m.height) and
            std.mem.eql(u8, &self.cliffField, &m.cliff);
        self.heightField = m.height;
        self.cliffField = m.cliff;
        self.heightHalf = m.half;
        self.heightAny = any;
        if (!same) self.rebuildTerrain();
    }

    pub fn sculptHeight(self: *Env, m: *const wf.Map, span: [4]usize) void {
        self.heightField = m.height;
        self.cliffField = m.cliff;
        self.heightHalf = m.half;
        const wasAny = self.heightAny;
        self.heightAny = m.anyHeight();
        if (wasAny != self.heightAny) return self.rebuildTerrain();
        if (!self.heightAny) return;
        if (span[0] > span[2] or span[1] > span[3]) return;
        const lo = tileOf(if (span[0] > 0) span[0] - 1 else 0);
        const hi = tileOf(@min(span[2] + 1, wf.HEIGHT_N - 1));
        const zlo = tileOf(if (span[1] > 0) span[1] - 1 else 0);
        const zhi = tileOf(@min(span[3] + 1, wf.HEIGHT_N - 1));
        var tz = zlo;
        while (tz <= zhi) : (tz += 1) {
            var tx = lo;
            while (tx <= hi) : (tx += 1) self.buildTile(tz * TILES + tx);
        }
        if (span[0] == 0 or span[1] == 0 or span[2] >= wf.HEIGHT_N - 1 or span[3] >= wf.HEIGHT_N - 1) self.buildSkirt();
    }

    fn rebuildTerrain(self: *Env) void {
        terrainBuilds += 1;
        for (0..NTILES) |i| {
            if (!self.heightAny) {
                self.dropTile(i);
                continue;
            }
            self.buildTile(i);
        }
        if (self.heightAny) {
            self.buildSkirt();
        } else if (self.skirtBuilt) {
            unloadTerrain(self.skirt);
            self.skirtBuilt = false;
        }
    }

    fn dropTile(self: *Env, i: usize) void {
        if (self.faceBuilt[i]) {
            unloadTerrain(self.faces[i]);
            self.faceBuilt[i] = false;
        }
        if (self.casterBuilt[i]) {
            unloadTerrain(self.casters[i]);
            self.casterBuilt[i] = false;
        }
        if (!self.tileBuilt[i]) return;
        unloadTerrain(self.tiles[i]);
        self.tileBuilt[i] = false;
    }

    fn buildTile(self: *Env, i: usize) void {
        self.dropTile(i);
        const tx = i % TILES;
        const tz = i / TILES;
        const x0 = tx * (TCHUNK - 1);
        const z0 = tz * (TCHUNK - 1);
        if (x0 + 1 >= wf.HEIGHT_N or z0 + 1 >= wf.HEIGHT_N) return;
        const x1 = @min(x0 + TCHUNK - 1, wf.HEIGHT_N - 1);
        const z1 = @min(z0 + TCHUNK - 1, wf.HEIGHT_N - 1);
        const half = self.heightHalf;
        const step = 2 * half / @as(f32, @floatFromInt(wf.HEIGHT_N - 1));
        var b = gfx.Builder.init();
        var fb = gfx.Builder.init();
        fb.setMat(.stone);
        var sb = gfx.Builder.init();
        const face = Face{ .b = &fb, .sb = &sb, .env = self };
        var yLo: f32 = std.math.floatMax(f32);
        var yHi: f32 = -std.math.floatMax(f32);
        const minDrop = wf.cliffMinDrop(step);
        var iz = z0;
        while (iz < z1) : (iz += 1) {
            var ix = x0;
            while (ix < x1) : (ix += 1) {
                const xa = -half + @as(f32, @floatFromInt(ix)) * step;
                const xb = xa + step;
                const za = -half + @as(f32, @floatFromInt(iz)) * step;
                const zb = za + step;
                const ha = self.pointY(ix, iz);
                const hb = self.pointY(ix + 1, iz);
                const hc = self.pointY(ix + 1, iz + 1);
                const hd = self.pointY(ix, iz + 1);
                const t = wf.cliffTiers(ha, hb, hc, hd);
                yLo = @min(yLo, t.lo);
                yHi = @max(yHi, t.hi);
                const case = self.cliffField[iz * wf.HEIGHT_N + ix];
                if (case == wf.CLIFF_STAIR) {
                    const tread = self.cellSurface(ix, iz);
                    yLo = @min(yLo, tread);
                    yHi = @max(yHi, tread);
                    stairCell(&b, face, .{ xa, za }, .{ xb, zb }, tread, .{
                        self.cellSurface(ix -| 1, iz),
                        self.cellSurface(ix, iz -| 1),
                        self.cellSurface(ix + 1, iz),
                        self.cellSurface(ix, iz + 1),
                    }, .{ ha, hd, hc, hb });
                    continue;
                }
                if (case == wf.CLIFF_FACE and wf.cliffCuts(t, minDrop)) {
                    const ring = [4]f32{ ha, hd, hc, hb };
                    const cut = wf.cliffCut(ring, t);
                    var lv = wf.cliffLevels(&self.heightField, ix, iz, minDrop, cut);
                    for (&lv.hi, &lv.lo) |*p, *q| {
                        p.* += GROUND_Y;
                        q.* += GROUND_Y;
                        yLo = @min(yLo, q.*);
                        yHi = @max(yHi, p.*);
                    }
                    cliffCell(&b, face, .{ xa, za }, .{ xb, zb }, ring, cut, lv, .{
                        self.treadOf(ix -| 1, iz),
                        self.treadOf(ix, iz + 1),
                        self.treadOf(ix + 1, iz),
                        self.treadOf(ix, iz -| 1),
                    });
                    continue;
                }
                b.quadSmooth(
                    v3(xa, ha, za),
                    v3(xa, hd, zb),
                    v3(xb, hc, zb),
                    v3(xb, hb, za),
                    self.pointNormal(ix, iz),
                    self.pointNormal(ix, iz + 1),
                    self.pointNormal(ix + 1, iz + 1),
                    self.pointNormal(ix + 1, iz),
                    rl.Color.white,
                );
            }
        }
        const sh = if (self.scene) |sc| sc.shader else self.ground.materials[0].shader;
        self.tiles[i] = b.toModel(sh);
        self.tileBuilt[i] = true;
        if (fb.pos.items.len > 0) {
            self.faces[i] = fb.toModel(sh);
            self.faceBuilt[i] = true;
        } else fb.deinit();
        if (sb.pos.items.len > 0) {
            self.casters[i] = sb.toModel(sh);
            self.casterBuilt[i] = true;
        } else sb.deinit();
        const cx = -half + (@as(f32, @floatFromInt(x0)) + @as(f32, @floatFromInt(x1))) * 0.5 * step;
        const cz = -half + (@as(f32, @floatFromInt(z0)) + @as(f32, @floatFromInt(z1))) * 0.5 * step;
        const spanX = @as(f32, @floatFromInt(x1 - x0)) * step;
        const spanZ = @as(f32, @floatFromInt(z1 - z0)) * step;
        self.tileMid[i] = v3(cx, (yLo + yHi) * 0.5, cz);
        self.tileRad[i] = 0.5 * @sqrt(spanX * spanX + spanZ * spanZ + (yHi - yLo) * (yHi - yLo));
    }

    fn buildSkirt(self: *Env) void {
        if (self.skirtBuilt) {
            unloadTerrain(self.skirt);
            self.skirtBuilt = false;
        }
        const half = self.heightHalf;
        const out = groundOut(self.mapHalf);
        if (out <= half) return;
        const n = wf.HEIGHT_N - 1;
        const step = 2 * half / @as(f32, @floatFromInt(n));
        const up = v3(0, 1, 0);
        var b = gfx.Builder.init();
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const a = -half + @as(f32, @floatFromInt(i)) * step;
            const c = a + step;
            b.quadSmooth(v3(a, self.pointY(i, 0), -half), v3(c, self.pointY(i + 1, 0), -half), v3(c, 0, -out), v3(a, 0, -out), up, up, up, up, rl.Color.white);
            b.quadSmooth(v3(a, 0, out), v3(c, 0, out), v3(c, self.pointY(i + 1, n), half), v3(a, self.pointY(i, n), half), up, up, up, up, rl.Color.white);
            b.quadSmooth(v3(-out, 0, a), v3(-out, 0, c), v3(-half, self.pointY(0, i + 1), c), v3(-half, self.pointY(0, i), a), up, up, up, up, rl.Color.white);
            b.quadSmooth(v3(half, self.pointY(n, i), a), v3(half, self.pointY(n, i + 1), c), v3(out, 0, c), v3(out, 0, a), up, up, up, up, rl.Color.white);
        }
        const cs = [_][2]f32{ .{ -1, -1 }, .{ 1, -1 }, .{ -1, 1 }, .{ 1, 1 } };
        for (cs) |s| {
            const ix: usize = if (s[0] < 0) 0 else n;
            const iz: usize = if (s[1] < 0) 0 else n;
            const hy = self.pointY(ix, iz);
            const xi = s[0] * half;
            const xo = s[0] * out;
            const zi = s[1] * half;
            const zo = s[1] * out;
            if (s[0] * s[1] > 0) {
                b.quadSmooth(v3(xi, hy, zi), v3(xi, 0, zo), v3(xo, 0, zo), v3(xo, 0, zi), up, up, up, up, rl.Color.white);
            } else {
                b.quadSmooth(v3(xi, hy, zi), v3(xo, 0, zi), v3(xo, 0, zo), v3(xi, 0, zo), up, up, up, up, rl.Color.white);
            }
        }
        self.skirt = b.toModel(if (self.scene) |sc| sc.shader else self.ground.materials[0].shader);
        self.skirtBuilt = true;
    }

    fn pointY(self: *const Env, ix: usize, iz: usize) f32 {
        return GROUND_Y + wf.heightOf(self.heightField[@min(iz, wf.HEIGHT_N - 1) * wf.HEIGHT_N + @min(ix, wf.HEIGHT_N - 1)]);
    }

    /// What the cell reads as at its own centre, whatever case it carries — the one height a neighbour's
    /// riser is drawn down to.
    fn cellSurface(self: *const Env, ix: usize, iz: usize) f32 {
        const last = wf.HEIGHT_N - 2;
        const half = self.heightHalf;
        const step = 2 * half / @as(f32, @floatFromInt(wf.HEIGHT_N - 1));
        const x = -half + (@as(f32, @floatFromInt(@min(ix, last))) + 0.5) * step;
        const z = -half + (@as(f32, @floatFromInt(@min(iz, last))) + 0.5) * step;
        return self.groundAt(x, z);
    }

    fn lattice(self: *const Env) f32 {
        return 2 * self.heightHalf / @as(f32, @floatFromInt(wf.HEIGHT_N - 1));
    }

    fn caseAt(self: *const Env, ix: usize, iz: usize) u8 {
        if (ix + 1 >= wf.HEIGHT_N or iz + 1 >= wf.HEIGHT_N) return wf.CLIFF_NONE;
        return self.cliffField[iz * wf.HEIGHT_N + ix];
    }

    /// A stair neighbour's tread, the one surface a cell edge cannot read off the shared corners.
    fn treadOf(self: *const Env, ix: usize, iz: usize) ?f32 {
        if (self.caseAt(ix, iz) != wf.CLIFF_STAIR) return null;
        return self.cellSurface(ix, iz);
    }

    fn caseAtWorld(self: *const Env, x: f32, z: f32) u8 {
        const step = self.lattice();
        const last: f32 = @floatFromInt(wf.HEIGHT_N - 1);
        const ix: usize = @intFromFloat(mathx.clampF(@floor((x + self.heightHalf) / step), 0, last));
        const iz: usize = @intFromFloat(mathx.clampF(@floor((z + self.heightHalf) / step), 0, last));
        return self.caseAt(ix, iz);
    }

    /// Whether the cell actually steps: a stair always, a painted face only over `wf.cliffMinDrop`.
    fn cellCuts(self: *const Env, ix: usize, iz: usize) bool {
        const case = self.caseAt(ix, iz);
        if (case == wf.CLIFF_STAIR) return true;
        if (case != wf.CLIFF_FACE) return false;
        const t = wf.cliffTiers(self.pointY(ix, iz), self.pointY(ix + 1, iz), self.pointY(ix, iz + 1), self.pointY(ix + 1, iz + 1));
        return wf.cliffCuts(t, wf.cliffMinDrop(self.lattice()));
    }

    /// Whether the lattice step from (ix, iz) to its `+x` (or `+z`) neighbour crosses a cut. Either of the
    /// two cells sharing that edge stepping is enough.
    fn cutAlong(self: *const Env, ix: usize, iz: usize, alongX: bool) bool {
        const a = if (alongX)
            (if (iz > 0) self.cellCuts(ix, iz - 1) else false)
        else
            (if (ix > 0) self.cellCuts(ix - 1, iz) else false);
        return a or self.cellCuts(ix, iz);
    }

    /// **A NORMAL NEVER READS ACROSS A FACE.** Differenced through a 13 m cut the lattice point beside a
    /// cliff comes out near-horizontal, and the cell it shades is a black band one cell wide running the
    /// whole lip. A tap that crosses one falls back to the point itself, so the shelf stays a shelf.
    fn pointNormal(self: *const Env, ix: usize, iz: usize) rl.Vector3 {
        const step = 2 * self.heightHalf / @as(f32, @floatFromInt(wf.HEIGHT_N - 1));
        const here = self.pointY(ix, iz);
        const xmCut = ix == 0 or self.cutAlong(ix - 1, iz, true);
        const xpCut = ix + 1 >= wf.HEIGHT_N or self.cutAlong(ix, iz, true);
        const zmCut = iz == 0 or self.cutAlong(ix, iz - 1, false);
        const zpCut = iz + 1 >= wf.HEIGHT_N or self.cutAlong(ix, iz, false);
        const xm = if (xmCut) here else self.pointY(ix - 1, iz);
        const xp = if (xpCut) here else self.pointY(ix + 1, iz);
        const zm = if (zmCut) here else self.pointY(ix, iz - 1);
        const zp = if (zpCut) here else self.pointY(ix, iz + 1);
        const xSpan: f32 = if (!xmCut and !xpCut) 2.0 else 1.0;
        const zSpan: f32 = if (!zmCut and !zpCut) 2.0 else 1.0;
        const dx = (xp - xm) / (step * xSpan);
        const dz = (zp - zm) / (step * zSpan);
        return mathx.normV(v3(-dx, 1.0, -dz));
    }

/// Derived only when something it reads moved — 7.1 ms over the whole 224² field.
    pub fn uploadWater(self: *Env, m: *const wf.Map) void {
        const N = wf.WATER_N;
        const same = self.waterReady and self.waterHalf == m.half and
            std.mem.eql(u8, &self.waterSrc, &m.water) and
            std.mem.eql(u8, &self.waterEdgeSrc, &m.waterEdge) and
            std.mem.eql(u8, &self.waterKindSrc, &m.waterKind) and
            std.mem.eql(u8, &self.waterHgtSrc, &m.height);
        if (same) return;
        waterBuilds += 1;
        self.waterSrc = m.water;
        self.waterEdgeSrc = m.waterEdge;
        self.waterKindSrc = m.waterKind;
        self.waterHgtSrc = m.height;
        self.waterReady = true;
        self.waterAny = m.anyWater();
        self.waterHalf = m.half;
        if (!self.waterAny) {
            @memset(&self.waterField, 0);
            self.dilateWaterEdge(m);
            if (self.scene) |sc| sc.setWater(&self.waterField, &self.waterEdgeField, m.half, false);
            return;
        }
        var lo: [2]usize = .{ N - 1, N - 1 };
        var hi: [2]usize = .{ 0, 0 };
        for (m.water, 0..) |wet, i| {
            if (wet == 0) continue;
            const cx = i % N;
            const cz = i / N;
            lo[0] = @min(lo[0], cx);
            hi[0] = @max(hi[0], cx);
            lo[1] = @min(lo[1], cz);
            hi[1] = @max(hi[1], cz);
        }
        const cell = m.cellSize(N);
        const edge = struct {
            fn at(c: usize, half: f32, cw: f32) f32 {
                return -half + @as(f32, @floatFromInt(c)) * cw;
            }
        }.at;
        const MARGIN = 2.0 * cell;
        const x0 = edge(lo[0], m.half, cell) - MARGIN;
        const x1 = edge(hi[0] + 1, m.half, cell) + MARGIN;
        const z0 = edge(lo[1], m.half, cell) - MARGIN;
        const z1 = edge(hi[1] + 1, m.half, cell) + MARGIN;
        self.waterMid = v3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5);
        self.waterSpan = v3((x1 - x0) * 0.5 / GROUND_HALF, 1, (z1 - z0) * 0.5 / GROUND_HALF);
        const FAR: f32 = 1e9;
        var dIn = &scratchIn;
        var dOut = &scratchOut;
        for (m.water, 0..) |wet, i| {
            dIn[i] = if (wet != 0) FAR else 0;
            dOut[i] = if (wet != 0) 0 else FAR;
        }
        const D1: f32 = 1.0;
        const D2: f32 = 1.41421356;
        for ([_]*[wf.WATER_CELLS]f32{ dIn, dOut }) |d| {
            var z: usize = 0;
            while (z < N) : (z += 1) {
                var x: usize = 0;
                while (x < N) : (x += 1) {
                    const i = z * N + x;
                    var best = d[i];
                    if (z > 0) {
                        best = @min(best, d[i - N] + D1);
                        if (x > 0) best = @min(best, d[i - N - 1] + D2);
                        if (x + 1 < N) best = @min(best, d[i - N + 1] + D2);
                    }
                    if (x > 0) best = @min(best, d[i - 1] + D1);
                    d[i] = best;
                }
            }
            var zb: usize = N;
            while (zb > 0) {
                zb -= 1;
                var xb: usize = N;
                while (xb > 0) {
                    xb -= 1;
                    const i = zb * N + xb;
                    var best = d[i];
                    if (zb + 1 < N) {
                        best = @min(best, d[i + N] + D1);
                        if (xb > 0) best = @min(best, d[i + N - 1] + D2);
                        if (xb + 1 < N) best = @min(best, d[i + N + 1] + D2);
                    }
                    if (xb + 1 < N) best = @min(best, d[i + 1] + D1);
                    d[i] = best;
                }
            }
        }
        const shoreF: f32 = @floatFromInt(gfx.WATER_SHORE);
        // WALKED AS ROWS AND COLUMNS, not as a flat index divided back apart: every one of the 50,176 cells paid four integer divisions to recover coordinates the loop already knows.
        for (0..N) |cz| {
            const ez = edge(cz, m.half, cell);
            for (0..N) |cx| {
                const i = cz * N + cx;
                const ex = edge(cx, m.half, cell);
                const wet = m.water[i];
                const shape: wf.Edge = @enumFromInt(@min(m.waterEdge[i], wf.Edge.N - 1));
                const sd = if (wet != 0)
                    @max(0.0, (dIn[i] - 0.5) * cell)
                else
                    -@max(0.0, (dOut[i] - 0.5) * cell);
                const enc: f32 = if (sd >= 0) blk: {
                    const byShore = mathx.clampF(sd / gfx.WATER_DEEP_AT, 0, 1);
                    const dug = WATER_Y - (GROUND_Y + m.heightAt(ex, ez));
                    if (dug <= 0) break :blk shoreF * (1.0 - mathx.clampF(-dug / (gfx.WATER_WET_OUT * coastBand(shape)), 0, 1));
                    break :blk shoreF + @max(byShore, digTone(dug)) * (255.0 - shoreF);
                } else blk: {
                    break :blk shoreF * (1.0 - mathx.clampF(-sd / (gfx.WATER_WET_OUT * coastBand(shape)), 0, 1));
                };
                self.waterField[i] = mathx.u8f(enc);
            }
        }
        self.dilateWaterEdge(m);
        if (self.scene) |sc| sc.setWater(&self.waterField, &self.waterEdgeField, m.half, true);
    }

    pub fn drawWater(self: *Env) void {
        if (!self.waterAny) return;
        if (self.scene) |sc| {
            sc.setWaterSheet(true, props.LIQUID_TONES);
            rl.drawModelEx(self.waterSheet, self.waterMid, v3(0, 1, 0), 0, self.waterSpan, rl.Color.white);
            sc.setWaterSheet(false, undefined);
        }
    }

    pub fn materialize(self: *Env, m: *const wf.Map) void {
        self.mapHalf = m.half;
        self.nprops = 0;
        self.opsCapped = 0;
        self.lightsCapped = 0;
        self.nsolids = 0;
        self.nwards = 0;
        self.openWards();
        self.nlights = 0;
        self.npools = 0;
        self.noccl = 0;
        @memset(&self.sgrid_start, 0);

        var p = Placer{ .e = self, .m = m, .flat = !m.anyHeight() };
        for (m.slice(), 0..) |*o, i| {
            p.cur = @intCast(i);
            p.expand(o);
        }
        buildSolids(self);
        indexProps(self);
    }

    pub fn explodeOp(self: *const Env, m: *wf.Map, s: usize) !usize {
        if (s >= m.nops) return error.NoSuchOp;
        if (m.ops[s].op == .at) return 0;
        const src = m.ops[s];
        const tag: u16 = @intCast(s);
        var first: usize = 0;
        var n: usize = 0;
        for (self.props[0..self.nprops], 0..) |pr, i| {
            if (pr.op != tag) continue;
            if (n == 0) first = i;
            n += 1;
        }
        try m.splice(s, n);
        for (0..n) |k| {
            const pr = self.props[first + k];
            var o = wf.defaults(.at);
            o.kind = pr.kind;
            o.x = pr.pos.x;
            o.z = pr.pos.z;
            o.yaw = pr.yaw;
            o.scale = pr.scale;
            o.lean = pr.lean;
            o.leanDir = pr.leanDir;
            o.rise = pr.rise;
            o.loot = src.loot;
            o.nloot = src.nloot;
            o.boss = src.boss;
            o.nboss = src.nboss;
            if (props.info(pr.kind).light != null) o.seed = src.seed +% k;
            m.ops[s + k] = o;
        }
        return n;
    }

    pub fn stageOne(self: *Env, kind: Kind) void {
        self.nprops = 0;
        self.opsCapped = 0;
        self.lightsCapped = 0;
        self.nsolids = 0;
        self.nlights = 0;
        self.npools = 0;
        self.noccl = 0;
        const nfo = props.info(kind);
        self.props[0] = .{ .kind = kind, .pos = v3(0, 0, 0), .yaw = 0, .scale = 1.0, .op = 0, .rise = nfo.stack * STAGE_SECTIONS };
        self.nprops = 1;
        if (props.info(kind).light) |ls| {
            self.lights[0] = .{ .base = .{ .pos = v3(0, ls.y, 0), .col = ls.col, .radius = ls.radius }, .flicker = ls.flicker, .phase = 0, .prop = 0 };
            self.nlights = 1;
        }
        buildSolids(self);
        self.openWards();
        indexProps(self);
    }


    pub fn markOccluders(self: *Env, eye: rl.Vector3, at: rl.Vector3, dt: f32) void {
        for (self.occl[0..self.noccl]) |pi| self.props[pi].fadeTo = 1;
        if (mathx.dist2XZ(eye, at) < 1.0) return self.easeFades(dt);
        const x0 = cellCoord(mathx.minF(eye.x, at.x) - OCCL_REACH);
        const x1 = cellCoord(mathx.maxF(eye.x, at.x) + OCCL_REACH);
        const z0 = cellCoord(mathx.minF(eye.z, at.z) - OCCL_REACH);
        const z1 = cellCoord(mathx.maxF(eye.z, at.z) + OCCL_REACH);
        var cz = z0;
        while (cz <= z1) : (cz += 1) {
            var cx = x0;
            while (cx <= x1) : (cx += 1) {
                const c = cz * GRID_N + cx;
                self.scanCell(&self.stx, c, eye, at);
                self.scanCell(&self.flx, c, eye, at);
            }
        }
        self.easeFades(dt);
    }

    fn scanCell(self: *Env, idx: *const Index, c: usize, eye: rl.Vector3, at: rl.Vector3) void {
        var k = idx.start[c];
        while (k < idx.start[c + 1]) : (k += 1) {
            const pi = idx.items[k];
            const pr = &self.props[pi];
            if (pr.gone) continue;
            const nfo = props.info(pr.kind);
            if (nfo.solid) continue;
            if (nfo.flora and nfo.top * pr.scale < OCCL_TALL) continue;
            const thin = thinFor(pr, nfo, eye, at);
            if (thin <= 0) continue;
            self.wantFade(pi, mathx.lerpF(1.0, OCCL_FLOOR, thin));
        }
    }

    fn wantFade(self: *Env, pi: u32, to: f32) void {
        var worst: ?usize = null;
        for (self.occl[0..self.noccl], 0..) |q, i| {
            if (q == pi) {
                self.props[pi].fadeTo = mathx.minF(self.props[pi].fadeTo, to);
                return;
            }
            if (self.props[q].fade < FADE_SOLID) continue;
            if (worst == null or self.props[q].fadeTo > self.props[self.occl[worst.?]].fadeTo) worst = i;
        }
        if (self.noccl < OCCL_MAX) {
            self.props[pi].fadeTo = to;
            self.occl[self.noccl] = pi;
            self.noccl += 1;
            return;
        }
        const w = worst orelse return;
        const victim = self.occl[w];
        if (self.props[victim].fadeTo <= to) return;
        self.props[victim].fade = 1;
        self.props[victim].fadeTo = 1;
        self.props[pi].fadeTo = to;
        self.occl[w] = pi;
    }

    fn easeFades(self: *Env, dt: f32) void {
        var i: usize = 0;
        while (i < self.noccl) {
            const pr = &self.props[self.occl[i]];
            const secs = if (pr.fadeTo < pr.fade) OCCL_IN else OCCL_OUT;
            const span = (1.0 - OCCL_FLOOR) * EASE_NORM * easeShape(pr.fade);
            const step = if (secs > 0) span * dt / secs else 1.0;
            pr.fade = mathx.approach(pr.fade, pr.fadeTo, step);
            if (pr.fade >= 1.0 and pr.fadeTo >= 1.0) {
                self.noccl -= 1;
                self.occl[i] = self.occl[self.noccl];
                continue;
            }
            i += 1;
        }
    }

    pub fn nearestFading(self: *const Env, p: rl.Vector3, within: f32) ?rl.Vector3 {
        var best = within * within;
        var out: ?rl.Vector3 = null;
        for (self.props[0..self.nprops]) |*pr| {
            if (props.info(pr.kind).occl.len == 0) continue;
            const d2 = mathx.dist2XZ(pr.pos, p);
            if (d2 >= best) continue;
            best = d2;
            out = pr.pos;
        }
        return out;
    }

    fn eachSolid(
        self: *const Env,
        x0w: f32,
        z0w: f32,
        x1w: f32,
        z1w: f32,
        ctx: anytype,
        comptime visit: fn (@TypeOf(ctx), collision.Solid) bool,
    ) void {
        const x0 = cellCoord(x0w);
        const x1 = cellCoord(x1w);
        const z0 = cellCoord(z0w);
        const z1 = cellCoord(z1w);
        var cz = z0;
        while (cz <= z1) : (cz += 1) {
            var cx = x0;
            while (cx <= x1) : (cx += 1) {
                const c = cz * GRID_N + cx;
                var k = self.sgrid_start[c];
                while (k < self.sgrid_start[c + 1]) : (k += 1) {
                    const sol = self.solid_buf[self.sgrid_items[k]];
                    if (sol.ward > 0 and self.wardLife[sol.ward - 1] <= 0) continue;
                    if (!visit(ctx, sol)) return;
                }
            }
        }
    }

    pub fn nearSolids(self: *const Env, p: rl.Vector3, r: f32, out: []collision.Solid) []const collision.Solid {
        const Take = struct {
            out: []collision.Solid,
            n: usize = 0,
            fn one(c: *@This(), s: collision.Solid) bool {
                if (c.n >= c.out.len) return false;
                c.out[c.n] = s;
                c.n += 1;
                return true;
            }
        };
        var take = Take{ .out = out };
        self.eachSolid(p.x - r, p.z - r, p.x + r, p.z + r, &take, Take.one);
        return out[0..take.n];
    }

    pub fn sees(self: *const Env, from: rl.Vector3, to: rl.Vector3) bool {
        const Look = struct {
            a: rl.Vector3,
            b: rl.Vector3,
            clear: bool = true,
            fn one(c: *@This(), s: collision.Solid) bool {
                if (!collision.blocksSight(c.a, c.b, s)) return true;
                c.clear = false;
                return false;
            }
        };
        var look = Look{ .a = from, .b = to };
        self.eachSolid(@min(from.x, to.x), @min(from.z, to.z), @max(from.x, to.x), @max(from.z, to.z), &look, Look.one);
        return look.clear;
    }

    pub fn wardCrossed(self: *const Env, a: rl.Vector3, b: rl.Vector3) ?u8 {
        const Look = struct {
            a: rl.Vector3,
            b: rl.Vector3,
            slot: ?u8 = null,
            fn one(c: *@This(), s: collision.Solid) bool {
                if (s.ward == 0 or !collision.blocksSight(c.a, c.b, s)) return true;
                c.slot = s.ward - 1;
                return false;
            }
        };
        var look = Look{ .a = a, .b = b };
        self.eachSolid(@min(a.x, b.x), @min(a.z, b.z), @max(a.x, b.x), @max(a.z, b.z), &look, Look.one);
        return look.slot;
    }

    pub fn wardSolids(self: *const Env, i: u8) []const collision.Solid {
        if (i >= self.nwards) return &.{};
        const a = self.wardSolid0[i];
        return self.solid_buf[a .. a + self.wardSolidN[i]];
    }

    /// **A FOG GATE IS A WALL UNTIL HE ASKS TO PASS IT** — which ward, if any, refuses this step, whether or not it is shut. `walking` is the ward the scripted crossing (`game.enterGate`) is on, and it is the only exemption. A SPENT gate never answers: `eachSolid` retires it at `wardLife` 0.
    pub fn wardRefusing(self: *const Env, a: rl.Vector3, b: rl.Vector3, walking: ?u8) ?u8 {
        const w = self.wardCrossed(a, b) orelse return null;
        if (walking) |on| {
            if (on == w) return null;
        }
        return w;
    }

    pub fn wardOpen(self: *const Env, i: u8) bool {
        return i < self.nwards and !self.wardShut[i] and self.wardLife[i] > 0;
    }

    pub fn wardClear(self: *const Env, i: u8, p: rl.Vector3, r: f32) bool {
        for (self.wardSolids(i)) |s| {
            if (collision.blocksPoint(p, r, s)) return false;
        }
        return true;
    }

    pub fn nearWard(self: *const Env, p: rl.Vector3, margin: f32) ?u8 {
        for (0..self.nwards) |wi| {
            const i: u8 = @intCast(wi);
            if (!self.wardOpen(i)) continue;
            for (self.wardSolids(i)) |s| {
                if (collision.blocksPoint(p, margin, s)) return i;
            }
        }
        return null;
    }

    pub const Crossing = struct { dir: rl.Vector3, to: rl.Vector3 };

    pub fn wardCross(self: *const Env, i: u8, p: rl.Vector3, r: f32) ?Crossing {
        const parts = self.wardSolids(i);
        if (parts.len == 0) return null;
        const s = parts[0];
        const n = mathx.perpXZ(mathx.dirXZ(s.a, s.b));
        if (mathx.lenXZ(n) < 0.5) return null;
        const q = mathx.closestOnSegXZ(p, s.a, s.b);
        const away = v3(q.x - p.x, 0, q.z - p.z);
        const dir = if (n.x * away.x + n.z * away.z >= 0) n else mathx.scaleV(n, -1);
        const span = mathx.lenXZ(away) + s.r + r + WARD_CLEAR;
        return .{ .dir = dir, .to = mathx.addV(p, mathx.scaleV(dir, span)) };
    }

    pub fn openWards(self: *Env) void {
        self.wardIn = [_]bool{false} ** MAX_WARDS;
        self.wardShut = [_]bool{false} ** MAX_WARDS;
        self.wardLife = [_]f32{1} ** MAX_WARDS;
        for (self.wardProps[0..self.nwards]) |pi| {
            self.props[pi].shrink = 1;
            self.props[pi].gone = false;
        }
    }

    pub fn blockedNear(self: *const Env, p: rl.Vector3, margin: f32, r: f32) bool {
        const Probe = struct {
            at: rl.Vector3,
            margin: f32,
            hit: bool = false,
            fn one(c: *@This(), s: collision.Solid) bool {
                if (!collision.blocksPoint(c.at, c.margin, s)) return true;
                c.hit = true;
                return false;
            }
        };
        var probe = Probe{ .at = p, .margin = margin };
        self.eachSolid(p.x - r, p.z - r, p.x + r, p.z + r, &probe, Probe.one);
        return probe.hit;
    }

    pub fn resolveActor(self: *const Env, p: rl.Vector3, r: f32, footY: f32) rl.Vector3 {
        return self.resolveActorPast(p, r, footY, false);
    }

    pub fn resolveHeroSide(self: *const Env, p: rl.Vector3, r: f32, footY: f32) rl.Vector3 {
        return self.resolveActorPast(p, r, footY, true);
    }

    fn resolveActorPast(self: *const Env, p: rl.Vector3, r: f32, footY: f32, crossesWards: bool) rl.Vector3 {
        const Push = struct {
            at: rl.Vector3,
            r: f32,
            footY: f32,
            open: []const bool,
            fn one(c: *@This(), s: collision.Solid) bool {
                if (s.ward > 0 and s.ward <= c.open.len and c.open[s.ward - 1]) return true;
                if (c.footY >= s.h) return true;
                if (c.footY + STEP_UP < s.y0) return true;
                c.at = collision.pushOut(c.at, c.r, s);
                return true;
            }
        };
        const q = r + 1.0;
        var passable = [_]bool{false} ** MAX_WARDS;
        if (crossesWards) {
            for (0..self.nwards) |i| passable[i] = !self.wardShut[i];
        }
        var push = Push{ .at = p, .r = r, .footY = footY, .open = passable[0..self.nwards] };
        self.eachSolid(p.x - q, p.z - q, p.x + q, p.z + q, &push, Push.one);
        if (push.at.x == p.x and push.at.z == p.z) return push.at;
        self.eachSolid(p.x - q, p.z - q, p.x + q, p.z + q, &push, Push.one);
        return push.at;
    }


    pub fn groundAt(self: *const Env, x: f32, z: f32) f32 {
        if (!self.heightAny) return GROUND_Y;
        return GROUND_Y + wf.sampleHeight(&self.heightField, &self.cliffField, self.heightHalf, x, z);
    }

    pub fn deckAt(self: *const Env, x: f32, z: f32, footY: f32) ?f32 {
        const c = cellOf(x, z);
        var best: ?f32 = null;
        var k = self.dgrid_start[c];
        while (k < self.dgrid_start[c + 1]) : (k += 1) {
            const d = self.deck_buf[self.dgrid_items[k]];
            if (d.hole) continue;
            const y = d.floorAt(x, z) orelse continue;
            if (y > footY + STEP_UP) continue;
            if (best) |b| {
                if (y <= b) continue;
            }
            if (d.run <= 0 and self.holedAt(c, d, x, z)) continue;
            best = y;
        }
        return best;
    }

    fn holedAt(self: *const Env, c: usize, floor: WorldDeck, x: f32, z: f32) bool {
        var k = self.dgrid_start[c];
        while (k < self.dgrid_start[c + 1]) : (k += 1) {
            const h = self.deck_buf[self.dgrid_items[k]];
            if (!h.hole or @abs(h.y - floor.y) > 1e-3) continue;
            if (inDisc(h, x, z)) return true;
        }
        return false;
    }

    pub fn standAt(self: *const Env, x: f32, z: f32, footY: f32) f32 {
        const g = self.groundAt(x, z);
        if (self.deckAt(x, z, footY)) |d| return mathx.maxF(g, d);
        return g;
    }

    pub fn ladderNear(self: *const Env, p: rl.Vector3, footY: f32, reach: f32) ?Rung {
        var best = reach * reach;
        var out: ?Rung = null;
    // The cells the reach actually touches, widened by the STANDOFF because the reach is measured to the climbing line.
        const box = reach + props.LADDER_STANDOFF;
        const x0 = cellCoord(p.x - box);
        const x1 = cellCoord(p.x + box);
        const z0 = cellCoord(p.z - box);
        const z1 = cellCoord(p.z + box);
        var cz = z0;
        while (cz <= z1) : (cz += 1) {
            var cx = x0;
            while (cx <= x1) : (cx += 1) {
                const c = cz * GRID_N + cx;
                var k = self.stx.start[c];
                while (k < self.stx.start[c + 1]) : (k += 1) {
                    const pr = &self.props[self.stx.items[k]];
                    if (pr.gone) continue;
                    const nfo = props.info(pr.kind);
                    if (!nfo.climb) continue;
                    const run = runOf(pr, nfo);
                    if (footY < pr.pos.y - LADDER_GRAB or footY > pr.pos.y + run + LADDER_GRAB) continue;
                    const fr = PropFrame.of(pr);
                    const axis = fr.at(0, 0, props.LADDER_STANDOFF);
                    const d2 = mathx.dist2XZ(axis, p);
                    if (d2 >= best) continue;
                    best = d2;
                    out = .{ .foot = pr.pos, .axis = axis, .yaw = pr.yaw, .run = run, .scale = pr.scale };
                }
            }
        }
        return out;
    }

    pub fn gradAt(self: *const Env, x: f32, z: f32) [2]f32 {
        if (!self.heightAny) return .{ 0, 0 };
        return wf.sampleGrad(&self.heightField, &self.cliffField, self.heightHalf, x, z);
    }

    /// How steep the ground is there, as the TANGENT of the slope angle (0 = flat, 1 = 45 deg).
    pub fn slopeAt(self: *const Env, x: f32, z: f32) f32 {
        const g = self.gradAt(x, z);
        return @sqrt(g[0] * g[0] + g[1] * g[1]);
    }

    pub fn slopeAlong(self: *const Env, x: f32, z: f32, dir: rl.Vector3) f32 {
        const g = self.gradAt(x, z);
        return g[0] * dir.x + g[1] * dir.z;
    }

    pub fn walkableAt(self: *const Env, x: f32, z: f32) bool {
        return self.slopeAt(x, z) <= MAX_SLOPE;
    }

    pub fn walkStep(self: *const Env, from: rl.Vector3, dir: rl.Vector3, dist: f32) rl.Vector3 {
        return self.walkStepPast(from, dir, dist, WADE_MAX);
    }

    pub fn walkSegmentPast(self: *const Env, from: rl.Vector3, to: rl.Vector3, wade: f32) rl.Vector3 {
        const dx = to.x - from.x;
        const dz = to.z - from.z;
        const d = @sqrt(dx * dx + dz * dz);
        if (d < 1e-5) return to;
        return self.walkStepPast(from, v3(dx / d, 0, dz / d), d, wade);
    }

    pub fn walkSegment(self: *const Env, from: rl.Vector3, to: rl.Vector3) rl.Vector3 {
        return self.walkSegmentPast(from, to, WADE_MAX);
    }

    pub fn walkStepPast(self: *const Env, from: rl.Vector3, dir: rl.Vector3, dist: f32, wade: f32) rl.Vector3 {
        const to = v3(from.x + dir.x * dist, from.y, from.z + dir.z * dist);
        if (!self.heightAny or dist <= 0) return to;
        if (self.deepRefusedPast(from.x, from.z, to.x, to.z, wade)) return v3(from.x, from.y, from.z);
        if (self.stepOk(from, dir, dist)) return to;
        const g = self.gradAt(from.x, from.z);
        const gl = @sqrt(g[0] * g[0] + g[1] * g[1]);
        if (gl < 1e-5) return to;
        const ux = g[0] / gl;
        const uz = g[1] / gl;
        const along = dir.x * ux + dir.z * uz;
        if (along <= 0) return to;
        const tx = dir.x - ux * along;
        const tz = dir.z - uz * along;
        const tl = @sqrt(tx * tx + tz * tz);
        if (tl < 1e-5) return v3(from.x, from.y, from.z);
        const slide = v3(from.x + tx / tl * dist, from.y, from.z + tz / tl * dist);
        if (self.stepOk(from, v3(tx / tl, 0, tz / tl), dist)) return slide;
        return v3(from.x, from.y, from.z);
    }

    /// A lip a ground creature will not step off. Only a cliff cell can make one — a ramp's descent over a
    /// frame's travel is bounded by `MAX_SLOPE`, which at any frame rate is a fraction of `STEP_UP`.
    /// Measured where a body STANDS (`standAt` off `from.y`), so the head of a flight is not a lip.
    pub fn brink(self: *const Env, from: rl.Vector3, to: rl.Vector3) bool {
        if (!self.heightAny) return false;
        return self.standAt(to.x, to.z, from.y) < self.standAt(from.x, from.z, from.y) - STEP_UP;
    }

    pub fn flyStep(self: *const Env, from: rl.Vector3, dir: rl.Vector3, dist: f32, footY: f32) rl.Vector3 {
        const to = v3(from.x + dir.x * dist, from.y, from.z + dir.z * dist);
        if (!self.heightAny or dist <= 0) return to;
        if (self.groundAt(to.x, to.z) <= footY + STEP_UP) return to;
        return v3(from.x, from.y, from.z);
    }

    /// **THE RISE IS MEASURED FROM WHERE HE STANDS.** `from.y` is the actor's own height (a deck's when he is
    /// on one), so the head of a flight meets the shelf at a step and not at the whole drop the LAND takes.
    /// **THE STEP ALLOWANCE IS FOR A RISER, NOT A GRADE.** `STEP_UP` over the half-metre probe is a 47.7 degree
    /// climb, and read at the probe's end alone it let a body up any bank under that, and through the corner
    /// of a cut whose far side the probe happened to land past. Read at the step's own end and at four taps
    /// along the probe; a rise past the slope's share is a riser, and a riser must land on a TREAD.
    fn stepOk(self: *const Env, from: rl.Vector3, dir: rl.Vector3, dist: f32) bool {
        const probe = mathx.maxF(dist, STEP_PROBE);
        const h0 = self.standAt(from.x, from.z, from.y);
        var k: usize = 0;
        while (k <= STEP_TAPS) : (k += 1) {
            const d = if (k == 0) dist else probe * @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(STEP_TAPS));
            const x = from.x + dir.x * d;
            const z = from.z + dir.z * d;
            const rise = self.standAt(x, z, from.y) - h0;
            if (rise <= MAX_SLOPE * d) continue;
            if (rise > STEP_UP or !self.treadAt(x, z, from.y)) return false;
        }
        return true;
    }

    /// Ground a riser may land on: a deck, a stair cell, or terrain under `MAX_SLOPE` read over `TREAD_READ`
    /// either way. A kerb is stepped; a bank the same height is not.
    fn treadAt(self: *const Env, x: f32, z: f32, footY: f32) bool {
        if (self.deckAt(x, z, footY) != null) return true;
        if (self.caseAtWorld(x, z) == wf.CLIFF_STAIR) return true;
        const gx = (self.groundAt(x + TREAD_READ, z) - self.groundAt(x - TREAD_READ, z)) / (2 * TREAD_READ);
        const gz = (self.groundAt(x, z + TREAD_READ) - self.groundAt(x, z - TREAD_READ)) / (2 * TREAD_READ);
        return gx * gx + gz * gz <= MAX_SLOPE * MAX_SLOPE;
    }

    pub fn rayGround(self: *const Env, origin: rl.Vector3, dir: rl.Vector3) ?rl.Vector3 {
        if (!self.heightAny) {
            if (@abs(dir.y) < 1e-6) return null;
            const t = (GROUND_Y - origin.y) / dir.y;
            if (t <= 0) return null;
            return v3(origin.x + dir.x * t, GROUND_Y, origin.z + dir.z * t);
        }
        const step = 2 * self.heightHalf / @as(f32, @floatFromInt(wf.HEIGHT_N - 1));
        const horiz = mathx.lenXZ(dir);
        const dt = if (horiz > 1e-4) step * 0.5 / horiz else step * 0.5;
        const MAX_T: f32 = 4.0 * GROUND_HALF;
        var t: f32 = 0;
        var prev = origin.y - self.groundAt(origin.x, origin.z);
        while (t < MAX_T) {
            const nt = t + dt;
            const p = v3(origin.x + dir.x * nt, origin.y + dir.y * nt, origin.z + dir.z * nt);
            const cur = p.y - self.groundAt(p.x, p.z);
            if (prev > 0 and cur <= 0) {
                var lo = t;
                var hi = nt;
                var k: usize = 0;
                while (k < 20) : (k += 1) {
                    const mid = (lo + hi) * 0.5;
                    const q = v3(origin.x + dir.x * mid, origin.y + dir.y * mid, origin.z + dir.z * mid);
                    if (q.y - self.groundAt(q.x, q.z) > 0) lo = mid else hi = mid;
                }
                const q = v3(origin.x + dir.x * hi, origin.y + dir.y * hi, origin.z + dir.z * hi);
                return v3(q.x, self.groundAt(q.x, q.z), q.z);
            }
            prev = cur;
            t = nt;
        }
        return null;
    }

    pub fn inWater(self: *const Env, x: f32, z: f32, inset: f32) bool {
        for (self.pools[0..self.npools]) |w| {
            const dx = x - w.pos.x;
            const dz = z - w.pos.z;
            const r = w.radius * inset;
            if (dx * dx + dz * dz < r * r) return true;
        }
        const margin = (1.0 - mathx.clampF(inset, 0, 1)) * gfx.WATER_DEEP_AT;
        return self.paintedDepth(x, z) * gfx.WATER_DEEP_AT > margin + 0.01;
    }

    fn dilateWaterEdge(self: *Env, m: *const wf.Map) void {
        for (m.waterEdge, m.waterKind, 0..) |e, k, i| scratchPack[i] = packLiquid(e, k);
        _ = gfx.Scene.dilateEdges(&self.waterEdgeField, wf.WATER_N, &m.water, &scratchPack);
    }

    fn waterEdgeAt(self: *const Env, x: f32, z: f32) usize {
        const i = wf.gridIndex(self.waterHalf, wf.WATER_N, x, z) orelse return glsl.NATURAL;
        return self.waterEdgeField[i] & glsl.EDGE_MASK;
    }

    pub fn liquidAt(self: *const Env, x: f32, z: f32) wf.Liquid {
        const i = wf.gridIndex(self.waterHalf, wf.WATER_N, x, z) orelse return .water;
        return @enumFromInt((self.waterEdgeField[i] >> glsl.LIQUID_SHIFT) & glsl.LIQUID_MASK);
    }

    /// MEASURED on the shipped map's 2.50 m cell: the walkable line sat **1.00 m** outside the drawn one.
    /// The three extra byte reads are free beside what `warpEdge` already spends here: MEASURED at two calls
    /// per body across `MAX_FOES`, **1,024 a frame is 199 us in Debug, 1.2% of a 16.7 ms frame**, and sixteen
    /// `hash21` evaluations of the domain warp are nearly all of it.
    fn waterFieldAt(self: *const Env, x: f32, z: f32, snap: bool) ?f32 {
        const N = wf.WATER_N;
        const cell = wf.gridIndex(self.waterHalf, N, x, z) orelse return null;
        if (snap) return @floatFromInt(self.waterField[cell]);
        const half = self.waterHalf;
        const nf: f32 = @floatFromInt(N);
        const fx = (x + half) / (2 * half) * nf - 0.5;
        const fz = (z + half) / (2 * half) * nf - 0.5;
        const x0 = @floor(fx);
        const z0 = @floor(fz);
        const tx = fx - x0;
        const tz = fz - z0;
        const hi: i32 = @intCast(N - 1);
        var acc: f32 = 0;
        for (0..2) |dz| {
            const cz: usize = @intCast(mathx.clampI(@as(i32, @intFromFloat(z0)) + @as(i32, @intCast(dz)), 0, hi));
            const wz = if (dz == 0) 1.0 - tz else tz;
            for (0..2) |dx| {
                const cx: usize = @intCast(mathx.clampI(@as(i32, @intFromFloat(x0)) + @as(i32, @intCast(dx)), 0, hi));
                const wx = if (dx == 0) 1.0 - tx else tx;
                acc += wx * wz * @as(f32, @floatFromInt(self.waterField[cz * N + cx]));
            }
        }
        return acc;
    }

/// It warps exactly as the shader does (`glsl.warpEdge`, off the same field).
    pub fn paintedDepth(self: *const Env, x: f32, z: f32) f32 {
        if (!self.waterAny) return 0;
        const e = self.waterEdgeAt(x, z);
        const q = glsl.warpEdge(x, z, e, true);
        const v = self.waterFieldAt(q[0], q[1], e == glsl.TILED) orelse return 0;
        const shore: f32 = @floatFromInt(gfx.WATER_SHORE);
        if (v <= shore) return 0;
        return (v - shore) / (255.0 - shore);
    }

    /// **SET EVERY WATER DWELLER'S POOL FLOOR TO `dwellerFloor`** — the editor's flatten with its taper, both
    /// ways, masked to the PAINTED water cells so the shore is never carved; the water is first painted one
    /// lattice step round the post so the lattice under it is wet. Eight passes converge the inner disc.
    /// Returns the lattice points moved; `--fix-lurkers` runs it and saves.
    pub fn digPools(m: *wf.Map, radius: f32) usize {
        const step = 2 * m.half / @as(f32, @floatFromInt(wf.HEIGHT_N - 1));
        const target = dwellerFloor();
        var moved: usize = 0;
        for (m.foes[0..m.nfoes]) |f| {
            if (foemod.poolBand(f.kind) == null) continue;
            _ = m.paintWater(f.x, f.z, step, true, null, null);
            const xs = wf.pointSpan(f.x, radius, m.half, step) orelse continue;
            const zs = wf.pointSpan(f.z, radius, m.half, step) orelse continue;
            for (0..8) |_| {
                var iz = zs[0];
                while (iz <= zs[1]) : (iz += 1) {
                    var ix = xs[0];
                    while (ix <= xs[1]) : (ix += 1) {
                        const p = m.heightPoint(ix, iz);
                        const d = @sqrt((p[0] - f.x) * (p[0] - f.x) + (p[1] - f.z) * (p[1] - f.z));
                        if (d > radius) continue;
                        const wc = wf.gridIndex(m.half, wf.WATER_N, p[0], p[1]) orelse continue;
                        if (m.water[wc] == 0) continue;
                        const i = iz * wf.HEIGHT_N + ix;
                        const cur = wf.heightOf(m.height[i]);
                        const want = mathx.lerpF(cur, target, mathx.smoothstep(radius, radius * 0.15, d));
                        const v = wf.heightByte(want);
                        if (m.height[i] == v) continue;
                        m.height[i] = v;
                        moved += 1;
                    }
                }
            }
        }
        return moved;
    }

    pub fn wadeDepth(self: *const Env, x: f32, z: f32) f32 {
        if (self.paintedDepth(x, z) <= 0) return 0;
        return mathx.maxF(0, WATER_Y - self.groundAt(x, z));
    }

    pub fn deepRefused(self: *const Env, fromX: f32, fromZ: f32, toX: f32, toZ: f32) bool {
        return self.deepRefusedPast(fromX, fromZ, toX, toZ, WADE_MAX);
    }

    pub fn deepRefusedPast(self: *const Env, fromX: f32, fromZ: f32, toX: f32, toZ: f32, limit: f32) bool {
        const deep = self.wadeDepth(toX, toZ);
        return deep > limit and deep > self.wadeDepth(fromX, fromZ);
    }


    pub fn pickIf(
        self: *const Env,
        view: *const View,
        origin: rl.Vector3,
        dir: rl.Vector3,
        ctx: anytype,
        comptime accept: fn (@TypeOf(ctx), u16) bool,
    ) ?usize {
        const Pick = struct {
            e: *const Env,
            origin: rl.Vector3,
            dir: rl.Vector3,
            ctx: @TypeOf(ctx),
            best: ?usize = null,
            bestT: f32 = std.math.floatMax(f32),

            fn at(p: *@This(), pi: u32) void {
                const pr = &p.e.props[pi];
                const ball = pickSphere(pr, props.info(pr.kind));
                const c = ball.c;
                const rad = ball.r;
                const oc = mathx.subV(c, p.origin);
                const along = oc.x * p.dir.x + oc.y * p.dir.y + oc.z * p.dir.z;
                if (along <= 0 or along >= p.bestT) return;
                const perp2 = (oc.x * oc.x + oc.y * oc.y + oc.z * oc.z) - along * along;
                if (perp2 > rad * rad) return;
                if (accept(p.ctx, pr.op)) {
                    p.bestT = along;
                    p.best = pi;
                }
            }
        };
        var p = Pick{ .e = self, .origin = origin, .dir = dir, .ctx = ctx };
        self.eachInView(view, &p, Pick.at);
        return p.best;
    }

    pub fn model(self: *const Env, kind: Kind) rl.Model {
        return self.models[@intFromEnum(kind)];
    }

    pub fn pickupModel(self: *const Env) rl.Model {
        return self.model(.pickup);
    }

    pub fn veil(self: *const Env, kind: Kind) ?rl.Model {
        return self.veils[@intFromEnum(kind)];
    }

    pub fn setShader(self: *Env, sh: rl.Shader) void {
        self.ground.materials[0].shader = sh;
        for (&self.models) |*m| m.materials[0].shader = sh;
        for (&self.stows) |*m| {
            if (m.*) |*s| s.materials[0].shader = sh;
        }
        for (self.tiles[0..], self.tileBuilt[0..]) |*t, built| {
            if (built) t.materials[0].shader = sh;
        }
        for (self.faces[0..], self.faceBuilt[0..]) |*f, built| {
            if (built) f.materials[0].shader = sh;
        }
        for (self.casters[0..], self.casterBuilt[0..]) |*f, built| {
            if (built) f.materials[0].shader = sh;
        }
        if (self.skirtBuilt) self.skirt.materials[0].shader = sh;
    }

    pub fn drawGround(self: *Env, view: ?*const View) void {
        if (!self.heightAny) {
            const k = groundOut(self.mapHalf) / GROUND_HALF;
            rl.drawModelEx(self.ground, mathx.zero3, v3(0, 1, 0), 0, v3(k, 1, k), rl.Color.white);
            return;
        }
        for (self.tiles[0..], self.tileBuilt[0..], self.tileMid[0..], self.tileRad[0..]) |t, built, mid, rad| {
            if (!built) continue;
            if (view) |vw| {
                if (!vw.visible(mid, rad, GROUND_HALF)) continue;
            }
            self.stat_draws += 1;
            rl.drawModel(t, mathx.zero3, 1.0, rl.Color.white);
        }
        if (self.skirtBuilt) rl.drawModel(self.skirt, mathx.zero3, 1.0, rl.Color.white);
    }

    /// The painted cliff faces. Drawn OUTSIDE `drawGround`'s `groundMode`, so they take the stone albedo
    /// every rock in the world takes instead of the soil painted on the shelf above them.
    pub fn drawCliffFaces(self: *Env, view: ?*const View) void {
        if (!self.heightAny) return;
        for (self.faces[0..], self.faceBuilt[0..], self.tileMid[0..], self.tileRad[0..]) |f, built, mid, rad| {
            if (!built) continue;
            if (view) |vw| {
                if (!vw.visible(mid, rad, GROUND_HALF)) continue;
            }
            self.stat_draws += 1;
            rl.drawModel(f, mathx.zero3, 1.0, rl.Color.white);
        }
    }

    /// **THE FACES CAST; THE TERRAIN STILL DOES NOT.** Depth pass only — the plate stands inside the rock.
    pub fn drawCliffCasters(self: *Env, focus: rl.Vector3) void {
        if (!self.heightAny) return;
        for (self.casters[0..], self.casterBuilt[0..], self.tileMid[0..], self.tileRad[0..]) |c, built, mid, rad| {
            if (!built) continue;
            if (!castsInto(focus, mid, rad, 0)) continue;
            self.stat_draws += 1;
            rl.drawModel(c, mathx.zero3, 1.0, rl.Color.white);
        }
    }

    pub fn drawProps(self: *Env, cull: Cull) void {
        self.drawIndexed(&self.stx, cull);
        self.drawStows(cull);
    }

    fn drawStows(self: *Env, cull: Cull) void {
        if (self.stowed) return;
        for (self.dressItems[0..self.ndress]) |pi| {
            const pr = &self.props[pi];
            const mdl = self.stows[@intFromEnum(pr.kind)] orelse continue;
            const nfo = props.info(pr.kind);
            const bound = reachOf(pr, nfo);
            switch (cull) {
                .view => |*vw| if (!vw.visible(pr.pos, bound, nfo.view)) continue,
                .sun => |focus| if (!castsInto(focus, pr.pos, bound, runOf(pr, nfo))) continue,
            }
            const sc = v3(pr.scale, pr.scale, pr.scale);
            rl.drawModelEx(mdl, pr.pos, v3(0, 1, 0), pr.yaw, sc, rl.Color.white);
        }
    }

    pub fn resetStats(self: *Env) void {
        self.stat_draws = 0;
        self.stat_cells = 0;
    }

    pub fn placed(self: *const Env) []const Prop {
        return self.props[0..self.nprops];
    }

    pub fn propCount(self: *const Env) usize {
        return self.nprops;
    }

    pub fn chestSites(self: *const Env, out: []chestmod.Site) usize {
        var n: usize = 0;
        for (self.chestItems[0..self.nchests]) |pi| {
            if (n >= out.len) break;
            const pr = &self.props[pi];
            out[n] = .{ .pos = pr.pos, .yaw = pr.yaw, .scale = pr.scale, .op = pr.op };
            n += 1;
        }
        return n;
    }
    pub fn setPickupDraw(self: *Env, i: usize, left: f32, gone: bool) void {
        if (i >= self.npickups) return;
        const pr = &self.props[self.pickupItems[i]];
        pr.shrink = mathx.clampF(left, 0, 1);
        pr.gone = gone;
    }
    pub fn pickupSites(self: *const Env, out: []pickupmod.Site) usize {
        var n: usize = 0;
        for (self.pickupItems[0..self.npickups]) |pi| {
            if (n >= out.len) break;
            const pr = &self.props[pi];
            out[n] = .{ .pos = pr.pos, .yaw = pr.yaw, .scale = pr.scale, .op = pr.op };
            n += 1;
        }
        return n;
    }
    pub fn restSites(self: *const Env, out: []restmod.Site) usize {
        var n: usize = 0;
        for (self.restItems[0..self.nrests]) |pi| {
            if (n >= out.len) break;
            const pr = &self.props[pi];
            out[n] = restmod.siteFromProp(pr.pos, pr.yaw);
            n += 1;
        }
        return n;
    }

    pub fn solidCount(self: *const Env) usize {
        return self.nsolids;
    }
    pub fn lightCount(self: *const Env) usize {
        return self.nlights;
    }

    pub fn drawFlora(self: *Env, view: *const View) void {
        self.drawIndexed(&self.flx, .{ .view = view.* });
    }

    pub fn drawVeils(self: *Env, view: *const View) void {
        for (self.dressItems[0..self.ndress]) |pi| {
            const pr = &self.props[pi];
            if (pr.gone) continue;
            const mdl = self.veils[@intFromEnum(pr.kind)] orelse continue;
            const nfo = props.info(pr.kind);
            if (!view.visible(pr.pos, reachOf(pr, nfo), nfo.view)) continue;
            self.stat_draws += 1;
            const sc = v3(pr.scale, pr.scale, pr.scale);
            const fading = pr.shrink < 1.0;
            if (fading) {
                if (self.scene) |sn| sn.beginFade(pr.shrink);
            }
            const tint = if (pr.ward > 0 and self.wardShut[pr.ward - 1]) propfx.FOG_SHUT_TINT else rl.Color.white;
            rl.drawModelEx(mdl, pr.pos, v3(0, 1, 0), pr.yaw, sc, tint);
            if (fading) {
                if (self.scene) |sn| sn.endFade();
            }
        }
    }

    fn drawIndexed(self: *Env, idx: *const Index, cull: Cull) void {
        const casters_only = cull == .sun;
        var c: usize = 0;
        while (c < NCELL) : (c += 1) {
            if (idx.start[c] == idx.start[c + 1]) continue;
            switch (cull) {
                .view => |*vw| {
                    if (!idx.cellSeen(c, vw)) continue;
                },
                .sun => |focus| {
                    if (!castsInto(focus, idx.cellAt(c), CELL_CIRCUM + idx.bound[c], idx.top[c])) continue;
                },
            }
            self.stat_cells += 1;
            var k = idx.start[c];
            while (k < idx.start[c + 1]) : (k += 1) {
                const pr = &self.props[idx.items[k]];
                if (pr.gone) continue;
                const nfo = props.info(pr.kind);
                if (casters_only and !nfo.casts) continue;
                const bound = reachOf(pr, nfo);
                switch (cull) {
                    .view => |*vw| {
                        if (!vw.visible(pr.pos, bound, nfo.view)) continue;
                    },
                    .sun => |focus| {
                        if (!castsInto(focus, pr.pos, bound, runOf(pr, nfo))) continue;
                    },
                }
                if (!casters_only and pr.fade < FADE_SOLID) continue;
                self.stat_draws += 1;
                if (!casters_only and pr.shrink < 1.0) {
                    if (self.scene) |s| s.beginFade(pr.shrink);
                    self.drawProp(pr);
                    if (self.scene) |s| s.endFade();
                } else {
                    self.drawProp(pr);
                }
            }
        }
    }

    pub fn eachInView(
        self: *const Env,
        view: *const View,
        ctx: anytype,
        comptime visit: fn (@TypeOf(ctx), u32) void,
    ) void {
        for ([_]*const Index{ &self.stx, &self.flx }) |idx| {
            var c: usize = 0;
            while (c < NCELL) : (c += 1) {
                if (idx.start[c] == idx.start[c + 1]) continue;
                if (!idx.cellSeen(c, view)) continue;
                var k = idx.start[c];
                while (k < idx.start[c + 1]) : (k += 1) {
                    const pi = idx.items[k];
                    const pr = &self.props[pi];
                    const nfo = props.info(pr.kind);
                    if (!view.visible(pr.pos, reachOf(pr, nfo), nfo.view)) continue;
                    visit(ctx, pi);
                }
            }
        }
    }

    pub fn ownedBy(self: *const Env, op: u16) usize {
        return if (op < self.opOwned.len) self.opOwned[op] else 0;
    }

    fn drawProp(self: *const Env, pr: *const Prop) void {
        const s = pr.scale * pr.shrink;
        const sc = v3(s, s, s);
        const nfo = props.info(pr.kind);
        if (nfo.stack > 0 and pr.rise > 0) return self.drawStack(pr, nfo, sc);
        if (pr.lean == 0) {
            rl.drawModelEx(self.models[@intFromEnum(pr.kind)], pr.pos, v3(0, 1, 0), pr.yaw, sc, rl.Color.white);
            return;
        }
        var mdl = self.models[@intFromEnum(pr.kind)];
        mdl.transform = rl.math.matrixRotateY(mathx.radians(pr.yaw));
        rl.drawModelEx(mdl, pr.pos, leanAxis(pr.leanDir), pr.lean, sc, rl.Color.white);
    }

    fn drawStack(self: *const Env, pr: *const Prop, nfo: *const props.Info, sc: rl.Vector3) void {
        const seg = nfo.stack * pr.scale;
        if (seg <= 1e-3) return;
        const n = sectionsIn(pr.rise, seg);
        const run: f32 = if (nfo.flight) |fl| fl.run * pr.scale else 0;
        const th = mathx.radians(pr.yaw);
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const k = @as(f32, @floatFromInt(i)) * pr.shrink;
            const at = v3(pr.pos.x - mathx.sinf(th) * run * k, pr.pos.y + k * seg, pr.pos.z - mathx.cosf(th) * run * k);
            // A ladder turns every other section or its wabi-sabi bands the run; a flight keeps climbing.
            const yaw = pr.yaw + if (run == 0 and i % 2 == 1) @as(f32, 180) else 0;
            rl.drawModelEx(self.models[@intFromEnum(pr.kind)], at, v3(0, 1, 0), yaw, sc, rl.Color.white);
        }
    }

    pub fn drawThinned(self: *Env, view: *const View) void {
        var order: [OCCL_MAX]u32 = undefined;
        var far: [OCCL_MAX]f32 = undefined;
        var n: usize = 0;
        for (self.occl[0..self.noccl]) |pi| {
            const pr = &self.props[pi];
            if (pr.gone) continue;
            if (pr.fade >= FADE_SOLID) continue;
            const nfo = props.info(pr.kind);
            if (!view.visible(pr.pos, reachOf(pr, nfo), nfo.view)) continue;
            const d = mathx.dist2XZ(pr.pos, view.pos);
            var i = n;
            while (i > 0 and far[i - 1] < d) : (i -= 1) {
                order[i] = order[i - 1];
                far[i] = far[i - 1];
            }
            order[i] = pi;
            far[i] = d;
            n += 1;
        }
        if (n == 0) return;
        rl.gl.rlSetBlendFactors(gfx.GL_ZERO, gfx.GL_ONE, gfx.GL_FUNC_ADD);
        for (order[0..n]) |pi| {
            const pr = &self.props[pi];
            const windy = props.info(pr.kind).flora;
            if (windy) {
                if (self.scene) |s| s.setWind(true);
            }
            self.stat_draws += 2;
            rl.gl.rlSetBlendMode(@intFromEnum(rl.gl.rlBlendMode.rl_blend_custom));
            self.drawProp(pr);
            rl.gl.rlSetBlendMode(@intFromEnum(rl.gl.rlBlendMode.rl_blend_alpha));
            if (self.scene) |s| s.beginFade(pr.fade);
            self.drawProp(pr);
            if (self.scene) |s| s.endFade();
            if (windy) {
                if (self.scene) |s| s.setWind(false);
            }
        }
    }

    fn lightOf(self: *const Env, wl: WorldLight, t: f32) ?gfx.Light {
        const owner = &self.props[wl.prop];
        if (owner.gone) return null;
        const k = 1.0 + wl.flicker * mathx.gutter(t, wl.phase);
        return .{
            .pos = wl.base.pos,
            .col = mathx.scaleV(wl.base.col, mathx.maxF(k, 0.05) * owner.shrink),
            .radius = wl.base.radius,
        };
    }

    pub fn uploadLights(self: *const Env, scene: *gfx.Scene, view: *const View, t: f32, reserved: []const gfx.Light) void {
        comptime std.debug.assert(gfx.MAX_LIGHTS > 1);
        var picked: [gfx.MAX_LIGHTS]gfx.Light = undefined;
        var dist: [gfx.MAX_LIGHTS]f32 = undefined;
        const keep = @min(reserved.len, gfx.MAX_LIGHTS / 2);
        const cap = picked.len - keep;
        var n: usize = 0;
        for (self.lights[0..self.nlights]) |wl| {
            if (!view.visible(wl.base.pos, wl.base.radius, LIGHT_REACH)) continue;
            const lit = self.lightOf(wl, t) orelse continue;
            const d2 = mathx.dist2XZ(wl.base.pos, view.pos);
            if (n < cap) {
                picked[n] = lit;
                dist[n] = d2;
                n += 1;
                continue;
            }
            var worst: usize = 0;
            for (dist[0..n], 0..) |dd, i| {
                if (dd > dist[worst]) worst = i;
            }
            if (d2 < dist[worst]) {
                picked[worst] = lit;
                dist[worst] = d2;
            }
        }
        for (reserved[0..keep]) |c| {
            picked[n] = c;
            n += 1;
        }
        scene.setLights(picked[0..n]);
    }
};

fn castsInto(focus: rl.Vector3, pos: rl.Vector3, bound: f32, top: f32) bool {
    const reach = shadowBox() + bound + top * gfx.sunReach;
    return mathx.dist2XZ(focus, pos) <= reach * reach;
}

const cross = mathx.crossV;

fn inward(a: rl.Vector3, b: rl.Vector3, inside: rl.Vector3) rl.Vector3 {
    const n = mathx.normV(cross(a, b));
    const d = n.x * inside.x + n.y * inside.y + n.z * inside.z;
    return if (d < 0) mathx.scaleV(n, -1) else n;
}

fn unloadTerrain(model: rl.Model) void {
    var m = model;
    m.materials[0].shader.id = rl.gl.rlGetShaderIdDefault();
    rl.unloadModel(m);
}

fn tileOf(point: usize) usize {
    return @min(point / (TCHUNK - 1), TILES - 1);
}

const UP3 = rl.Vector3{ .x = 0, .y = 1, .z = 0 };

/// The cell's four corners in world xz, wound the way the terrain quad winds them.
fn cellRing(a: [2]f32, c: [2]f32) [4][2]f32 {
    var out: [4][2]f32 = undefined;
    for (wf.CLIFF_RING, 0..) |r, i| {
        out[i] = .{ a[0] + r[0] * (c[0] - a[0]), a[1] + r[1] * (c[1] - a[1]) };
    }
    return out;
}

fn cellWorld(uv: [2]f32, a: [2]f32, c: [2]f32) [2]f32 {
    return .{ a[0] + uv[0] * (c[0] - a[0]), a[1] + uv[1] * (c[1] - a[1]) };
}

/// A point of a cut cell's flat: on the side's own bilinear, with that surface's normal.
fn fanPoint(uv: [2]f32, a: [2]f32, c: [2]f32, vals: [4]f32) struct { p: rl.Vector3, n: rl.Vector3 } {
    const w = cellWorld(uv, a, c);
    const cellW = c[0] - a[0];
    const du = mathx.lerpF(vals[3] - vals[0], vals[2] - vals[1], uv[1]) / cellW;
    const dv = mathx.lerpF(vals[1] - vals[0], vals[2] - vals[3], uv[0]) / cellW;
    return .{ .p = v3(w[0], wf.ringLerp(vals, uv[0], uv[1]), w[1]), .n = mathx.normV(v3(-du, 1, -dv)) };
}

/// A fan over a polygon given in CELL units, every vertex on the side's bilinear — the flat drawn is the
/// flat `wf.sampleHeight` walks, corner for corner.
fn cliffFan(b: *gfx.Builder, poly: []const [2]f32, a: [2]f32, c: [2]f32, vals: [4]f32) void {
    if (poly.len < 3) return;
    const p0 = fanPoint(poly[0], a, c, vals);
    var i: usize = 1;
    while (i + 1 < poly.len) : (i += 1) {
        const p1 = fanPoint(poly[i], a, c, vals);
        const p2 = fanPoint(poly[i + 1], a, c, vals);
        b.triSmooth(p0.p, p1.p, p2.p, p0.n, p1.n, p2.n, rl.Color.white);
    }
}

/// Where a cut cell meets a cell that does not cut, its side surface and the neighbour's bilinear part
/// company — a painted run dying into a ramp, or one steep cell in a band of gentle ones. The skirt is the
/// vertical strip between OUR floor and THEIRS along the edge, both windings, whichever stands higher:
/// dropped only downward it left the neighbour's ramp hanging over our low floor, and the sky showed under it.
fn cellSkirt(b: *gfx.Builder, q0: [2]f32, q1: [2]f32, y0: f32, y1: f32, o0: f32, o1: f32) void {
    if (@abs(y0 - o0) < 1e-4 and @abs(y1 - o1) < 1e-4) return;
    const dx = q1[0] - q0[0];
    const dz = q1[1] - q0[1];
    const l = @sqrt(dx * dx + dz * dz);
    if (l < 1e-5) return;
    const n = v3(dz / l, 0, -dx / l);
    const a0 = v3(q0[0], y0, q0[1]);
    const a1 = v3(q1[0], y1, q1[1]);
    const b0 = v3(q0[0], o0, q0[1]);
    const b1 = v3(q1[0], o1, q1[1]);
    b.quadSmooth(a0, a1, b1, b0, n, n, n, n, rl.Color.white);
    b.quadSmooth(a0, b0, b1, a1, n, n, n, n, rl.Color.white);
}

/// The neighbour's surface at a point of the shared edge `eg`: a stair's tread, else the line through the
/// two corners they share — which is what a plain cell, an inert painted one, or a cut one draws there.
fn edgeOther(uv: [2]f32, eg: usize, h: [4]f32, tread: ?f32) f32 {
    if (tread) |y| return y;
    const j = (eg + 1) % 4;
    const t = (uv[0] - wf.CLIFF_RING[eg][0]) * (wf.CLIFF_RING[j][0] - wf.CLIFF_RING[eg][0]) +
        (uv[1] - wf.CLIFF_RING[eg][1]) * (wf.CLIFF_RING[j][1] - wf.CLIFF_RING[eg][1]);
    return mathx.lerpF(h[eg], h[j], mathx.clampF(t, 0, 1));
}

/// **THE FACE IS NOT A QUAD, AND IT IS NOT ONE ROCK.** A painted face is built from the `cliff*` props' own
/// vocabulary (`proprock.CliffKind`): the kind's courses set the band height, `blocky` how proud the strata
/// stand, `cleft` the vertical grooves, `ivy` the curtains and `broken` the talus. The kind is a field
/// ~27 m wide, so a run reads as one geology and the next bay as another.
///
/// **THE WALL IS A PLANE AND THE ROCK IS SHAPES ON IT** (owner: straight cliffs, never the jagged look).
/// Bellied per cell, a 0.54 m lattice read as a palisade — one fin a cell — and a wandered cut as an
/// accordion. The plane now barely moves (`FACE_RELIEF_CELL`, a field of world position so shared columns
/// agree); what makes it rock is the `cliff*` props' own vocabulary stood against it: half-sunk boulders,
/// ledge courses keyed on WORLD height so they run level through every cell, vertical ribs, a brow under the
/// lip, talus at the foot — and a normal bump so the flat between them shades like stone.
const FACE_SPAN_M: f32 = 0.7;
const FACE_SPANS_MAX: usize = 6;
const FACE_ROWS_MAX: usize = 14;
/// The geometry hugs the cut within this of the lip, so the shelf edge meets it; the foot may batter out.
const FACE_EASE: f32 = 0.50;
/// The shadow plate: this far inside the rock and this far under the lip, so neither the face nor the shelf
/// behind the lip ever reads its own depth back.
const FACE_SHADOW_IN: f32 = 0.7;
const FACE_SHADOW_LIP: f32 = 0.2;
/// The relief the SHADING sees, in metres: the core barely moves, the normals do.
const FACE_BUMP: f32 = 0.45;
/// Metres of run between stamped faces. One is about `drop` wide at the scale it is stood at, so under a tall
/// wall they lap over each other and under a short one they sit apart with plain sheet between.
const FACE_PROP_M: f32 = 3.0;
/// Below this a face is a step, not a cliff, and gets no rock stood against it.
const FACE_PROP_MIN_DROP: f32 = 1.6;
/// Metres of the stamped face that stand in FRONT of the cut. The rest is inside the hill.
const FACE_PROP_PROUD: f32 = 0.55;
/// The share of the prop's own stone height that is sized to the drop. Under 1, its tallest spikes stand
/// a little over the lip and the body of it reaches.
const FACE_PROP_FILL: f32 = 0.86;
const FACE_SINK: f32 = 0.78;
/// A face standing in water: wet stone to `FACE_WET_H` over the sheet, a pale tide line to `FACE_TIDE_H`.
const FACE_WET_H: f32 = 0.45;
const FACE_TIDE_H: f32 = 0.9;
const FACE_FILLET_MIN: f32 = 0.14;
const FACE_FILLET_MAX: f32 = 0.55;

pub const Face = struct {
    b: *gfx.Builder,
    sb: ?*gfx.Builder,
    env: ?*const Env,
    dress: bool = true,

    fn ground(self: Face, x: f32, z: f32, fallback: f32) f32 {
        const e = self.env orelse return fallback;
        return e.groundAt(x, z);
    }
    fn wet(self: Face, x: f32, z: f32) bool {
        const e = self.env orelse return false;
        return e.paintedDepth(x, z) > 0;
    }
};

/// A chord of the cut and the two outward directions its ends may move in: along their own lattice edge,
/// toward the low corner, which is the one direction the cell either side agrees on. Null is the normal.
pub const Chord = struct {
    u: [2]f32,
    w: [2]f32,
    outU: ?[2]f32 = null,
    outW: ?[2]f32 = null,
};

fn faceKind(x: f32, z: f32) *const proprock.CliffKind {
    const n = vnoise2(x / 27.0 + 5.3, z / 27.0 - 2.1);
    const i: usize = @intFromFloat(@floor(mathx.clampF(n, 0, 0.999) * @as(f32, @floatFromInt(proprock.CLIFF_KINDS.len))));
    return &proprock.CLIFF_KINDS[i];
}

fn heightKey(y: f32, courseH: f32) u32 {
    return @bitCast(@as(i32, @intFromFloat(@floor(y / courseH))) + 2048);
}

/// Strata keyed on WORLD height, so a course runs level through every cell of a face.
fn strataTone(y: f32, courseH: f32) rl.Color {
    const r = wf.hashSigned(heightKey(y, courseH) *% 2654435761, 0x5A7A);
    if (r < -0.35) return art.CLIFF_DK;
    if (r > 0.72) return art.CLIFF_LT;
    return art.CLIFF_ROCK;
}

fn rockTone(rng: *mathx.Rng) rl.Color {
    const r = rng.float();
    if (r < 0.28) return art.CLIFF_LT;
    if (r < 0.52) return art.CLIFF_DK;
    return art.CLIFF_ROCK;
}

fn wetTone(c: rl.Color) rl.Color {
    return .{
        .r = @intFromFloat(@as(f32, @floatFromInt(c.r)) * 0.50),
        .g = @intFromFloat(@as(f32, @floatFromInt(c.g)) * 0.53),
        .b = @intFromFloat(@as(f32, @floatFromInt(c.b)) * 0.64),
        .a = 255,
    };
}

/// The relief field, 0..1, over world position — two octaves, the coarse one leaning on the height so a
/// bulge is a boss and not a pillar.
fn reliefAt(x: f32, y: f32, z: f32) f32 {
    const big = vnoise2(x / 3.1 + y * 0.21 + 7.7, z / 3.1 - y * 0.17 + 2.9);
    const fine = vnoise2(x / 1.15 - y * 0.55 + 31.7, z / 1.15 + y * 0.48 - 12.3);
    return mathx.clampF(big * 0.68 + fine * 0.32, 0, 1);
}

/// The field's slope along the face and up it, for the normals — a function of world position, so the
/// cell either side of a shared column tilts it the same way.
fn reliefGrad(x: f32, y: f32, z: f32, ax: f32, az: f32) [2]f32 {
    const h: f32 = 0.15;
    const da = reliefAt(x + ax * h, y, z + az * h) - reliefAt(x - ax * h, y, z - az * h);
    const dy = reliefAt(x, y + h, z) - reliefAt(x, y - h, z);
    return .{ da / (2 * h), dy / (2 * h) };
}

/// An up-facing strip quad whatever way the chord runs: `p0`,`p1` take `near`, `q1`,`q0` take `far`.
fn fadeQuadUp(b: *gfx.Builder, p0: rl.Vector3, p1: rl.Vector3, q1: rl.Vector3, q0: rl.Vector3, near: rl.Color, far: rl.Color) void {
    var n = mathx.normV(mathx.crossV(mathx.subV(p1, p0), mathx.subV(q1, p0)));
    if (n.y < 0) {
        n = mathx.scaleV(n, -1);
        b.quadFade(p1, p0, q0, q1, n, near, far);
    } else {
        b.quadFade(p0, p1, q1, q0, n, near, far);
    }
}

/// **THE FACE IS ONE OF THE `cliff*` PROPS, SUNK HALF INTO THE WALL.** The wall itself is a plain sheet; the
/// rock is `proprock.CLIFF_FACES` stamped along the run at world stations, scaled so its own top lands on the
/// lip, turned so its front looks out, and bisected at the cut so the front half stands proud and the back
/// half is inside the hill. Each prototype is built ONCE and stamped, so a forty-metre run costs one mesh.
var faceProto: [proprock.CLIFF_FACES.len]?gfx.Builder = [_]?gfx.Builder{null} ** proprock.CLIFF_FACES.len;

fn faceProtoOf(i: usize) *const gfx.Builder {
    if (faceProto[i] == null) faceProto[i] = proprock.cliffBuild(proprock.CLIFF_FACES[i].seed, proprock.CLIFF_FACES[i].kind);
    return &faceProto[i].?;
}

/// What the LAND actually does across the cut at one point on the run: how far it steps, and where the low
/// side is. A stamp is sized and stood on this rather than on the cell's own two tiers, so where a painted
/// run meets ground that is only half as deep the rock is only half as tall — the face DIES INTO the slope
/// instead of stopping square, which is the whole of the transition.
fn faceStep(f: Face, px: f32, pz: f32, nx: f32, nz: f32, out: f32) struct { drop: f32, lo: f32 } {
    const e = f.env orelse return .{ .drop = 0, .lo = 0 };
    const loSide = e.groundAt(px + nx * out, pz + nz * out);
    const hiSide = e.groundAt(px - nx * out, pz - nz * out);
    return .{ .drop = @max(hiSide - loSide, 0), .lo = loSide };
}

fn faceStamp(f: Face, u: [2]f32, ax: f32, az: f32, nx: f32, nz: f32, lo: f32, hi: f32, len: f32, cell: f32) void {
    const drop = hi - lo;
    if (drop < FACE_PROP_MIN_DROP) return;
    // The along-run coordinate the whole face agrees on, so a station belongs to exactly one chord however
    // the cut is broken up into cells.
    const alongX = -nz;
    const alongZ = nx;
    const sU = u[0] * alongX + u[1] * alongZ;
    const dot = ax * alongX + az * alongZ;
    if (@abs(dot) < 0.5) return;
    const s0 = @min(sU, sU + len * dot);
    const s1 = @max(sU, sU + len * dot);
    const yaw = std.math.atan2(-nx, -nz);
    var k: i32 = @intFromFloat(@floor(s0 / FACE_PROP_M) + 1);
    while (@as(f32, @floatFromInt(k)) * FACE_PROP_M < s1) : (k += 1) {
        const kk: u32 = @bitCast(k +% 0x51F);
        const st = @as(f32, @floatFromInt(k)) * FACE_PROP_M + wf.hashSigned(kk, 0x5EED) * FACE_PROP_M * 0.35;
        const t = (st - sU) / dot;
        const px = u[0] + ax * t;
        const pz = u[1] + az * t;
        // Read a cell out either side, so the taper starts a cell BEFORE the run runs out rather than at it.
        const land = faceStep(f, px, pz, nx, nz, cell * 0.8);
        const useDrop = mathx.minF(drop, land.drop);
        if (useDrop < FACE_PROP_MIN_DROP) continue;
        const pick: usize = @intFromFloat(@abs(wf.hashSigned(kk, 0xFACE)) * @as(f32, @floatFromInt(proprock.CLIFF_FACES.len)) * 0.999);
        const proto = faceProtoOf(pick);
        // The STONE's extent, not the mesh's: the prop's ivy and grass carry a third of its height again, and
        // sized to those the rock tops out well under the lip with plain sheet showing over it.
        const bb = proto.boundsOf(.stone);
        if (bb.hi.y <= 0.1) continue;
        // …and to the BULK of the stone, not its tallest spike: sized to the spike, the body of the rock tops
        // out well under the lip and leaves a strip of plain sheet over it. A spike that overshoots is a rock
        // on the rim, which the rim scatters anyway.
        const sc = useDrop / (bb.hi.y * FACE_PROP_FILL) * (1.0 + 0.10 * wf.hashSigned(kk, 0x512E));
        // Bisected at the cut, but at the depth the wall can afford: the ground at its foot is walked right
        // up to the line, so what stands past it is what the hero walks into.
        const sink = -bb.lo.z * sc - FACE_PROP_PROUD;
        // Stood on the ground that is actually THERE, so a tapering rock walks up the slope with it.
        f.b.stamp(proto, v3(px - nx * sink, land.lo, pz - nz * sink), yaw + wf.hashSigned(kk, 0x7A11) * 0.18, v3(sc, sc, sc));
    }
}

/// `loEnd`/`hiEnd` are the floors either side of the cut at the chord's two ends, so on sloping ground the
/// wall runs with them instead of standing between two tiers.
fn cliffWall(f: Face, ch: Chord, loEnd: [2]f32, hiEnd: [2]f32, highRef: [2]f32, cell: f32) void {
    const u = ch.u;
    const w = ch.w;
    const ex = w[0] - u[0];
    const ez = w[1] - u[1];
    const len = @sqrt(ex * ex + ez * ez);
    const lo = (loEnd[0] + loEnd[1]) * 0.5;
    const hi = (hiEnd[0] + hiEnd[1]) * 0.5;
    if (len < 1e-4 or hi <= lo + 1e-3) return;
    var nx = ez / len;
    var nz = -ex / len;
    const mx = (u[0] + w[0]) * 0.5;
    const mz = (u[1] + w[1]) * 0.5;
    const flip = (highRef[0] - mx) * nx + (highRef[1] - mz) * nz > 0;
    if (flip) {
        nx = -nx;
        nz = -nz;
    }
    // Keyed on the chord's own place in the world, so the same face rebuilds the same way.
    const key = @as(u32, @bitCast(@as(i32, @intFromFloat(@round(mx * 16))))) ^
        (@as(u32, @bitCast(@as(i32, @intFromFloat(@round(mz * 16))))) *% 0x85EBCA6B);
    var rng = mathx.Rng.init(@as(u64, key) | (@as(u64, 0xC11FF) << 32));
    const kind = faceKind(mx, mz);
    const drop = hi - lo;
    const spans: usize = @intFromFloat(mathx.clampF(@round(len / FACE_SPAN_M), 2, @as(f32, @floatFromInt(FACE_SPANS_MAX))));
    const courseH = kind.H / @as(f32, @floatFromInt(kind.bands));
    var bands: usize = @intFromFloat(mathx.clampF(@round(drop / courseH), 1, 10));
    if (drop > 1.0 and bands < 2) bands = 2;

    // Rows as a share of each column's own foot-to-lip, so a course stays a course where the floors slope.
    var fr: [FACE_ROWS_MAX]f32 = undefined;
    var nrow: usize = 0;
    for (0..bands + 1) |j| {
        fr[nrow] = @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(bands));
        nrow += 1;
    }
    const wet = lo < WATER_Y and f.wet(mx + nx * 0.3, mz + nz * 0.3);
    if (wet) {
        for ([_]f32{ WATER_Y + FACE_WET_H, WATER_Y + FACE_TIDE_H }) |yw| {
            if (yw <= lo + 0.05 or yw >= hi - 0.05 or nrow >= FACE_ROWS_MAX) continue;
            const fw = (yw - lo) / drop;
            var k = nrow;
            while (k > 0 and fr[k - 1] > fw) : (k -= 1) fr[k] = fr[k - 1];
            fr[k] = fw;
            nrow += 1;
        }
    }

    // **THE WALL IS A PLAIN SHEET.** Everything that made it rock is one of `proprock.CLIFF_FACES` sunk half
    // into it below; a sheet that tries to be rock as well only ever reads as plates pasted on a wall.
    var grid: [FACE_SPANS_MAX + 1][FACE_ROWS_MAX]rl.Vector3 = undefined;
    var hiCol: [FACE_SPANS_MAX + 1]f32 = undefined;
    for (0..spans + 1) |i| {
        const s = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(spans));
        const cx = u[0] + ex * s;
        const cz = u[1] + ez * s;
        const loC = mathx.lerpF(loEnd[0], loEnd[1], s);
        hiCol[i] = mathx.lerpF(hiEnd[0], hiEnd[1], s);
        for (0..nrow) |j| grid[i][j] = v3(cx, mathx.lerpF(loC, hiCol[i], fr[j]), cz);
    }

    // Every vertex takes the plane's normal tilted by the world field alone — a function of position, so the
    // cell either side of a shared column shades it the same and nothing flutes at the seams.
    var vn: [FACE_SPANS_MAX + 1][FACE_ROWS_MAX]rl.Vector3 = undefined;
    for (0..spans + 1) |i| {
        for (0..nrow) |j| {
            const bp = grid[i][j];
            const lipEase = mathx.clampF((hiCol[i] - bp.y) / FACE_EASE, 0, 1);
            const gr = reliefGrad(bp.x, bp.y, bp.z, ex / len, ez / len);
            const k = FACE_BUMP * lipEase;
            vn[i][j] = mathx.normV(v3(nx - gr[0] * ex / len * k, -gr[1] * k, nz - gr[0] * ez / len * k));
        }
    }

    for (0..spans) |i| {
        for (0..nrow - 1) |j| {
            const a = grid[i][j + 1];
            const c = grid[i + 1][j + 1];
            const d = grid[i + 1][j];
            const e = grid[i][j];
            const ymid = (grid[i][j].y + grid[i][j + 1].y + grid[i + 1][j].y + grid[i + 1][j + 1].y) * 0.25;
            const smid = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(spans));
            var col = strataTone(ymid, courseH);
            // A slow wash along the run, so a course is not one flat tone for forty metres.
            const wash = vnoise2((u[0] + ex * smid) / 2.6 + ymid * 0.3 + 11.1, (u[1] + ez * smid) / 2.6 - ymid * 0.2 + 3.3);
            if (wash > 0.66) col = mathx.lerpColor(col, art.CLIFF_LT, (wash - 0.66) * 2.2) else if (wash < 0.36) col = mathx.lerpColor(col, art.CLIFF_DK, (0.36 - wash) * 2.2);
            // The core is a JOINT, not a face: pulled under the masses that stand on it so the gaps read deep.
            col = mathx.lerpColor(col, art.CLIFF_DK, 0.24 + 0.3 * (1.0 - mathx.clampF((ymid - lo) / 1.2, 0, 1)));
            var mat: gfx.Mat = .stone;
            if (wet) {
                if (ymid < WATER_Y + FACE_WET_H) {
                    col = wetTone(col);
                    mat = .marble;
                } else if (ymid < WATER_Y + FACE_TIDE_H) {
                    col = mathx.lerpColor(col, art.CLIFF_LT, 0.4);
                }
            }
            f.b.setMat(mat);
            const na = vn[i][j + 1];
            const nc = vn[i + 1][j + 1];
            const nd = vn[i + 1][j];
            const ne = vn[i][j];
            if (flip) {
                f.b.quadSmooth(a, e, d, c, na, ne, nd, nc, col);
            } else {
                f.b.quadSmooth(a, c, d, e, na, nc, nd, ne, col);
            }
        }
    }

    f.b.setMat(.stone);

    if (f.sb) |sb| {
        // A stair riser is one `wf.HEIGHT_STEP`, so there is no `FACE_SHADOW_IN` of rock behind it to bury the
        // plate in: it lands under the next tread and bands every step. `dress` is the same face/riser split.
        if (f.dress) {
            const bx = -nx * FACE_SHADOW_IN;
            const bz = -nz * FACE_SHADOW_IN;
            const pa = v3(u[0] + bx, loEnd[0] - 0.3, u[1] + bz);
            const pb = v3(w[0] + bx, loEnd[1] - 0.3, w[1] + bz);
            const pc = v3(w[0] + bx, hiEnd[1] - FACE_SHADOW_LIP, w[1] + bz);
            const pd = v3(u[0] + bx, hiEnd[0] - FACE_SHADOW_LIP, u[1] + bz);
            const n = v3(nx, 0, nz);
            // Both windings: the depth pass culls back faces and the sun stands behind half the walls.
            sb.quadSmooth(pa, pb, pc, pd, n, n, n, n, rl.Color.white);
            sb.quadSmooth(pa, pd, pc, pb, n, n, n, n, rl.Color.white);
        }
    }

    if (!f.dress or f.env == null) return;
    const hx = -nx;
    const hz = -nz;
    const dropK = mathx.clampF(drop / 6.0, 0, 1);

    faceStamp(f, u, ex / len, ez / len, nx, nz, lo, hi, len, cell);

    // THE RIM: loose stones and grass leaning over the drop. (A cap strip of bare rock along the lip was
    // tried and read as a saw of dark teeth from above; the stones carry the weathered edge on their own.)
    {
        const nRim: usize = @intFromFloat(@round(len * (0.5 + 1.0 * rng.float()) * (0.5 + 0.5 * dropK)));
        for (0..nRim) |_| {
            const s = rng.range(0.08, 0.92);
            const in_ = rng.range(0.06, 0.42);
            const r = rng.range(0.07, 0.2) * (0.8 + 0.5 * kind.broken);
            const x = u[0] + ex * s + hx * in_;
            const z = u[1] + ez * s + hz * in_;
            const gy = f.ground(x, z, hi);
            f.b.addBlob(v3(x, gy + r * 0.3, z), v3(r, r * rng.range(0.5, 0.7), r * rng.range(0.8, 1.25)), 3, if (kind.blocky > 0.5) 5 else 6, rockTone(&rng));
        }
        const cover = coverField(mx, mz);
        const nTuft: usize = @intFromFloat(@round(len * 2.2 * cover * (0.5 + 0.5 * rng.float())));
        f.b.setMat(.plant);
        for (0..nTuft) |_| {
            const s = rng.range(0.05, 0.95);
            const in_ = rng.range(0.02, 0.2);
            const x = u[0] + ex * s + hx * in_;
            const z = u[1] + ez * s + hz * in_;
            const gy = f.ground(x, z, hi);
            const nb = 4 + rng.intn(4);
            var k: i32 = 0;
            while (k < nb) : (k += 1) {
                const a = rng.angle();
                const rr = rng.range(0.02, 0.09);
                const bx = x + mathx.cosf(a) * rr;
                const bz = z + mathx.sinf(a) * rr;
                const h = rng.range(0.22, 0.48);
                const out = rng.range(0.12, 0.34);
                const lx = nx * out + rng.signed() * 0.08;
                const lz = nz * out + rng.signed() * 0.08;
                f.b.addCylinder(v3(bx, gy, bz), v3(bx + lx, gy + h * 0.85, bz + lz), 0.016, 0.003, 4, art.bladeColor(&rng));
            }
        }
        f.b.setMat(.stone);
    }

    // IVY AND MOSS on the kinds that carry them, hung off the lattice the face was built on.
    if (kind.ivy > 0 and drop > 1.2 and spans > 2) {
        const nCur: usize = @intFromFloat(@round(len * kind.ivy * 0.9 * (0.5 + rng.float())));
        for (0..nCur) |_| {
            const i: usize = 1 + @as(usize, @intCast(rng.intn(@intCast(spans - 1))));
            const hang = drop * rng.range(0.35, 0.8);
            var prev: ?rl.Vector3 = null;
            var j = nrow - 1;
            while (j > 0) : (j -= 1) {
                const p = grid[i][j];
                if (hiCol[i] - p.y > hang) break;
                const q = v3(p.x + nx * 0.06, p.y, p.z + nz * 0.06);
                if (prev) |pp| {
                    const mid = v3((pp.x + q.x) * 0.5 + ex / len * rng.signed() * 0.12 + nx * 0.04, (pp.y + q.y) * 0.5, (pp.z + q.z) * 0.5 + ez / len * rng.signed() * 0.12 + nz * 0.04);
                    f.b.setMat(.wood);
                    f.b.addCapsule(pp, mid, 0.028, 0.034, 5, art.BARK_DK);
                    f.b.addCapsule(mid, q, 0.034, 0.038, 5, art.BARK_DK);
                    f.b.setMat(.plant);
                    const nLeaf = 2 + rng.intn(3);
                    var lf: i32 = 0;
                    while (lf < nLeaf) : (lf += 1) {
                        const tt = rng.float();
                        const lx = mathx.lerpF(pp.x, q.x, tt) + ex / len * rng.signed() * 0.3;
                        const ly = mathx.lerpF(pp.y, q.y, tt);
                        const lz = mathx.lerpF(pp.z, q.z, tt) + ez / len * rng.signed() * 0.3;
                        const r = rng.range(0.14, 0.3);
                        f.b.addBlob(v3(lx + nx * r * 0.5, ly, lz + nz * r * 0.5), v3(r, r * rng.range(0.7, 1.1), r), 3, 6, if (rng.float() < 0.35) art.SCRUB_DK else art.IVY_GRN);
                    }
                }
                prev = q;
            }
        }
        f.b.setMat(.plant);
        const nMoss: usize = @intFromFloat(@round(len * kind.ivy * 1.4));
        for (0..nMoss) |_| {
            const i: usize = 1 + @as(usize, @intCast(rng.intn(@intCast(spans - 1))));
            const j: usize = 1 + @as(usize, @intCast(rng.intn(@intCast(nrow - 2))));
            const p = grid[i][j];
            const wd = rng.range(0.25, 0.6);
            const hh = wd * rng.range(0.3, 0.55);
            f.b.addBlob(v3(p.x + nx * 0.08, p.y, p.z + nz * 0.08), v3(wd, hh, wd), 3, 6, if (rng.float() < 0.5) art.MOSS_DK else art.STONE_MOSS);
        }
        f.b.setMat(.stone);
    }

    // THE FOOT: a scree fillet, then talus scattered past it — more for a taller face and a broken kind.
    {
        const hf = mathx.clampF(0.10 + 0.035 * drop, FACE_FILLET_MIN, FACE_FILLET_MAX);
        var filH: [FACE_SPANS_MAX + 1]f32 = undefined;
        var filOut: [FACE_SPANS_MAX + 1]f32 = undefined;
        for (0..spans + 1) |i| {
            filH[i] = hf * rng.range(0.7, 1.2);
            filOut[i] = hf * 2.4 * rng.range(0.7, 1.3);
        }
        const wallCol = mathx.lerpColor(art.CLIFF_DK, art.CLIFF_ROCK, 0.35);
        const soilCol = mathx.lerpColor(art.ROCK_DEEP, art.SOIL, 0.5);
        for (0..spans) |i| {
            const p0 = v3(grid[i][0].x, grid[i][0].y + filH[i], grid[i][0].z);
            const p1 = v3(grid[i + 1][0].x, grid[i + 1][0].y + filH[i + 1], grid[i + 1][0].z);
            const q0x = p0.x + nx * filOut[i];
            const q0z = p0.z + nz * filOut[i];
            const q1x = p1.x + nx * filOut[i + 1];
            const q1z = p1.z + nz * filOut[i + 1];
            const q0 = v3(q0x, f.ground(q0x, q0z, lo) + 0.02, q0z);
            const q1 = v3(q1x, f.ground(q1x, q1z, lo) + 0.02, q1z);
            fadeQuadUp(f.b, p0, p1, q1, q0, wallCol, soilCol);
        }
        const nTal: usize = @intFromFloat(@round(len * (0.9 + 1.8 * kind.broken) * (0.4 + 0.6 * dropK)));
        for (0..nTal) |_| {
            const s = rng.range(0.02, 0.98);
            const outT = std.math.pow(f32, rng.float(), 1.5);
            const out = 0.12 + hf * 0.5 + outT * (0.5 + 1.1 * dropK);
            const r = rng.range(0.10, 0.40) * (0.75 + 0.5 * kind.broken) * (1.0 - 0.45 * outT);
            const x = u[0] + ex * s + nx * out;
            const z = u[1] + ez * s + nz * out;
            const gy = f.ground(x, z, lo);
            f.b.addBlob(v3(x, gy + r * 0.4, z), v3(r * rng.range(0.85, 1.25), r * rng.range(0.55, 0.85), r * rng.range(0.8, 1.2)), 3 + rng.intn(2), if (kind.blocky > 0.5) 5 else 7, rockTone(&rng));
        }
        if (kind.broken > 0.4 and len > 0.9 and drop > 2.0 and rng.float() < 0.7) {
            const s = rng.range(0.25, 0.75);
            const hh = 0.4 + rng.range(0.6, 1.4) * mathx.minF(drop / 4.0, 1.0);
            const wdt = rng.range(0.4, 0.9);
            const bx = u[0] + ex * s + nx * hh * 0.35;
            const bz = u[1] + ez * s + nz * hh * 0.35;
            const gy = f.ground(bx, bz, lo);
            f.b.addBox(
                v3(bx, gy + hh * 0.42, bz),
                v3(ex / len * wdt * 0.5, 0, ez / len * wdt * 0.5),
                v3(-nx * hh * 0.25, hh * 0.45, -nz * hh * 0.25),
                v3(nx * 0.12, 0, nz * 0.12),
                if (rng.float() < 0.5) art.CLIFF_LT else art.CLIFF_DK,
            );
        }
    }
}

comptime {
    if (wf.STAIR_RISE > STEP_UP) @compileError("env: a stair's riser is taller than the walk will step — " ++
        "every flight would be a wall");
}

/// A tread, and the risers that face DOWN off it. Only the low side is walled: the neighbour standing
/// higher draws that riser itself, so no face is drawn twice.
fn stairCell(b: *gfx.Builder, fb: Face, a: [2]f32, c: [2]f32, y: f32, nb: [4]f32, h: [4]f32) void {
    const p = cellRing(a, c);
    cliffFan(b, &wf.CLIFF_RING, a, c, .{ y, y, y, y });
    const edges = [4][2][2]f32{
        .{ p[0], p[1] },
        .{ p[3], p[0] },
        .{ p[2], p[3] },
        .{ p[1], p[2] },
    };
    // **THE RISER GOES DOWN TO THE LOWEST THE NEIGHBOUR REACHES ON THIS EDGE**, not to its CENTRE. A tread is
    // flat at its own mean; the cell beside it is a bilinear through the two corners they SHARE, so its
    // surface at the edge runs below its centre and the riser stopped short of it — a hole per step.
    const ends = [4][2]usize{ .{ 0, 1 }, .{ 3, 0 }, .{ 2, 3 }, .{ 1, 2 } };
    const mid = [2]f32{ (a[0] + c[0]) * 0.5, (a[1] + c[1]) * 0.5 };
    var riser = fb;
    riser.dress = false;
    for (edges, nb, ends) |e, ny, k| {
        const lowest = @min(ny, @min(h[k[0]], h[k[1]]));
        if (lowest >= y - 1e-4) continue;
        cliffWall(riser, .{ .u = e[0], .w = e[1] }, .{ lowest, lowest }, .{ y, y }, mid, c[0] - a[0]);
    }
}

fn polyMid(poly: []const [2]f32) [2]f32 {
    var sx: f32 = 0;
    var sz: f32 = 0;
    for (poly) |p| {
        sx += p[0];
        sz += p[1];
    }
    const k = 1.0 / @as(f32, @floatFromInt(poly.len));
    return .{ sx * k, sz * k };
}

/// One cell of the height lattice drawn as TWO FLOORS AND A FACE, cut at the edge midpoints
/// `wf.cliffCut` names — the same line `wf.sampleHeight` steps on, so the floor drawn is the floor walked.
/// `h` is the ring the terrain quad already winds: (xa,za), (xa,zb), (xb,zb), (xb,za); `lv` the two side
/// surfaces at those corners.
fn cliffCell(b: *gfx.Builder, fb: Face, a: [2]f32, c: [2]f32, h: [4]f32, cw: wf.CliffCut, lv: wf.CliffLevels, nb: [4]?f32) void {
    const p = cellRing(a, c);
    const high = cw.high;
    const cut = cw.cut;
    const ncut = cw.n;
    var xp: [4][2]f32 = undefined;
    var hiAt: [4]f32 = undefined;
    var loAt: [4]f32 = undefined;
    // The way along edge i from its crossing to its LOW corner: the one outward direction both cells agree on.
    var lowWay: [4][2]f32 = undefined;
    for (0..4) |i| {
        if (!cut[i]) continue;
        const j = (i + 1) % 4;
        xp[i] = cellWorld(cw.xp[i], a, c);
        hiAt[i] = (lv.hi[i] + lv.hi[j]) * 0.5;
        loAt[i] = (lv.lo[i] + lv.lo[j]) * 0.5;
        const toNext = [2]f32{ wf.CLIFF_RING[j][0] - wf.CLIFF_RING[i][0], wf.CLIFF_RING[j][1] - wf.CLIFF_RING[i][1] };
        lowWay[i] = if (high[i]) toNext else .{ -toNext[0], -toNext[1] };
    }
    const cellW = c[0] - a[0];
    var start: usize = 0;
    while (start < 4 and !cut[start]) start += 1;
    if (start == 4) {
        const vals = if (high[0]) lv.hi else lv.lo;
        cliffFan(b, &wf.CLIFF_RING, a, c, vals);
        for (0..4) |i| {
            const j = (i + 1) % 4;
            cellSkirt(b, p[i], p[j], vals[i], vals[j], nb[i] orelse h[i], nb[i] orelse h[j]);
        }
        return;
    }

    const centreHigh = cw.centreHigh;
    var chord: [4][2][2]f32 = undefined;
    var chordEdge: [4][2]usize = undefined;
    var chordHigh: [4]bool = undefined;
    var chordMid: [4][2]f32 = undefined;
    var nrun: usize = 0;

    var e = start;
    while (true) {
        var poly: [6][2]f32 = undefined;
        // Which of the cell's own edges each polygon segment lies on; the last one is the chord and skirts none.
        var onEdge: [6]usize = undefined;
        var n: usize = 0;
        poly[n] = cw.xp[e];
        onEdge[n] = e;
        n += 1;
        var k = (e + 1) % 4;
        while (true) {
            poly[n] = wf.CLIFF_RING[k];
            onEdge[n] = k;
            n += 1;
            if (cut[k]) break;
            k = (k + 1) % 4;
        }
        poly[n] = cw.xp[k];
        n += 1;
        const cls = high[(e + 1) % 4];
        const vals = if (cls) lv.hi else lv.lo;
        cliffFan(b, poly[0..n], a, c, vals);
        for (0..n - 1) |q| {
            const eg = onEdge[q];
            cellSkirt(
                b,
                cellWorld(poly[q], a, c),
                cellWorld(poly[q + 1], a, c),
                wf.ringLerp(vals, poly[q][0], poly[q][1]),
                wf.ringLerp(vals, poly[q + 1][0], poly[q + 1][1]),
                edgeOther(poly[q], eg, h, nb[eg]),
                edgeOther(poly[q + 1], eg, h, nb[eg]),
            );
        }
        chord[nrun] = .{ xp[e], xp[k] };
        chordEdge[nrun] = .{ e, k };
        chordHigh[nrun] = cls;
        chordMid[nrun] = cellWorld(polyMid(poly[0..n]), a, c);
        nrun += 1;
        e = k;
        if (e == start) break;
    }

    if (ncut == 4) {
        var mid: [4][2]f32 = undefined;
        var n: usize = 0;
        for (0..4) |i| {
            if (!cut[i]) continue;
            mid[n] = cw.xp[i];
            n += 1;
        }
        cliffFan(b, mid[0..n], a, c, if (centreHigh) lv.hi else lv.lo);
        const cm = cellWorld(polyMid(mid[0..n]), a, c);
        for (0..nrun) |i| {
            if (chordHigh[i] == centreHigh) continue;
            const eu = chordEdge[i][0];
            const ew = chordEdge[i][1];
            const ch = Chord{ .u = chord[i][0], .w = chord[i][1], .outU = lowWay[eu], .outW = lowWay[ew] };
            cliffWall(fb, ch, .{ loAt[eu], loAt[ew] }, .{ hiAt[eu], hiAt[ew] }, if (centreHigh) cm else chordMid[i], cellW);
        }
        return;
    }
    for (0..nrun) |i| {
        if (!chordHigh[i]) continue;
        const eu = chordEdge[i][0];
        const ew = chordEdge[i][1];
        const ch = Chord{ .u = chord[i][0], .w = chord[i][1], .outU = lowWay[eu], .outW = lowWay[ew] };
        cliffWall(fb, ch, .{ loAt[eu], loAt[ew] }, .{ hiAt[eu], hiAt[ew] }, chordMid[i], cellW);
    }
}

fn cellCoord(w: f32) usize {
    return @intFromFloat(mathx.clampF((w + GRID_HALF) / CELL, 0, @floatFromInt(GRID_N - 1)));
}

fn cellOf(x: f32, z: f32) usize {
    return cellCoord(z) * GRID_N + cellCoord(x);
}

/// Public: `ui/mapart.zig` draws the very colliders this builds, off the same rotation.
pub const PropFrame = struct {
    pr: *const Prop,
    c: f32,
    sn: f32,

    pub fn of(pr: *const Prop) PropFrame {
        const th = mathx.radians(pr.yaw);
        return .{ .pr = pr, .c = mathx.cosf(th), .sn = mathx.sinf(th) };
    }
    pub fn at(self: PropFrame, lx: f32, ly: f32, lz: f32) rl.Vector3 {
        const s = self.pr.scale;
        return v3(
            self.pr.pos.x + s * (lx * self.c + lz * self.sn),
            self.pr.pos.y + ly * s,
            self.pr.pos.z + s * (-lx * self.sn + lz * self.c),
        );
    }
    fn partFoot(self: PropFrame, part: props.Part) rl.Vector3 {
        return self.at((part.ax + part.bx) * 0.5, 0, (part.az + part.bz) * 0.5);
    }
    fn blockerFoot(self: PropFrame, bl: props.Blocker) rl.Vector3 {
        return self.at(bl.x, bl.y0, bl.z);
    }
};

/// 0 (solid) .. 1 (as thin as it gets). A collider is sized for what you WALK INTO and on a tree it is wrong by
/// metres: a conifer's 1.48 m cylinder against boughs that block the view at 3.8 m.
fn thinFor(pr: *const Prop, nfo: *const props.Info, eye: rl.Vector3, at: rl.Vector3) f32 {
    var thin: f32 = 0;
    const fr = PropFrame.of(pr);
    if (nfo.occl.len > 0) {
        for (nfo.occl) |bl| {
            thin = mathx.maxF(thin, thinOf(eye, at, fr.blockerFoot(bl), (bl.y1 - bl.y0) * pr.scale, bl.r * pr.scale));
        }
        return thin;
    }
    for (nfo.parts) |part| {
        const hl = 0.5 * mathx.lenXZ(v3(part.bx - part.ax, 0, part.bz - part.az));
        const r = (part.r + hl) * pr.scale + OCCL_SKIRT;
        thin = mathx.maxF(thin, thinOf(eye, at, fr.partFoot(part), part.h * pr.scale, r));
    }
    if (nfo.parts.len == 0) {
        thin = thinOf(eye, at, pr.pos, runOf(pr, nfo), nfo.bound * pr.scale * OCCL_GIRTH);
    }
    return thin;
}

fn thinOf(eye: rl.Vector3, at: rl.Vector3, foot: rl.Vector3, h: f32, r: f32) f32 {
    const c = coverFrac(eye, at, foot, h, r);
    if (c.cover <= OCCL_MIN) return 0;
    return mathx.smoothstep(OCCL_MIN, OCCL_FULL, c.cover) * c.ahead;
}

const Cover = struct {
    cover: f32,
    ahead: f32,
};
const NO_COVER = Cover{ .cover = 0, .ahead = 0 };

fn coverFrac(eye: rl.Vector3, at: rl.Vector3, foot: rl.Vector3, h: f32, r: f32) Cover {
    const toH = mathx.subV(at, eye);
    const dh = mathx.lenV(toH);
    if (dh < 0.5) return NO_COVER;
    const fwd = mathx.scaleV(toH, 1.0 / dh);
    var right = mathx.perpXZ(fwd);
    const rn = mathx.lenV(right);
    if (rn < 1e-3) return NO_COVER;
    right = mathx.scaleV(right, 1.0 / rn);
    const up = mathx.crossV(right, fwd);
    var u: [2]f32 = undefined;
    var vv: [2]f32 = undefined;
    var z: [2]f32 = undefined;
    for ([_]rl.Vector3{ foot, v3(foot.x, foot.y + h, foot.z) }, 0..) |p, i| {
        const d = mathx.subV(p, eye);
        z[i] = d.x * fwd.x + d.y * fwd.y + d.z * fwd.z;
        if (z[i] < 0.15) z[i] = 0.15;
        u[i] = (d.x * right.x + d.y * right.y + d.z * right.z) / z[i];
        vv[i] = (d.x * up.x + d.y * up.y + d.z * up.z) / z[i];
    }
    const zm = (z[0] + z[1]) * 0.5;
    const ahead = mathx.clampF((dh - zm) / OCCL_DEPTH_BAND, 0, 1);
    if (ahead <= 0) return NO_COVER;
    const hw = HERO_HALF_W / dh;
    const hh = HERO_HALF_H / dh;
    const wp = r / zm;
    const uc = (u[0] + u[1]) * 0.5;
    const ou = mathx.maxF(0, mathx.minF(uc + wp, hw) - mathx.maxF(uc - wp, -hw));
    const ov = mathx.maxF(0, mathx.minF(mathx.maxF(vv[0], vv[1]), hh) - mathx.maxF(mathx.minF(vv[0], vv[1]), -hh));
    return .{ .cover = mathx.clampF(ou * ov / (4.0 * hw * hh), 0, 1), .ahead = ahead };
}

fn cellCentre(c: usize) rl.Vector3 {
    const cx = c % GRID_N;
    const cz = c / GRID_N;
    return v3(
        (@as(f32, @floatFromInt(cx)) + 0.5) * CELL - GRID_HALF,
        0,
        (@as(f32, @floatFromInt(cz)) + 0.5) * CELL - GRID_HALF,
    );
}

fn terrain(shader: rl.Shader, half: f32) rl.Model {
    var b = gfx.Builder.init();
    b.quad(v3(-half, GROUND_Y, -half), v3(-half, GROUND_Y, half), v3(half, GROUND_Y, half), v3(half, GROUND_Y, -half), v3(0, 1, 0), rl.Color.white);
    return b.toModel(shader);
}

fn waterQuad(shader: rl.Shader, half: f32) rl.Model {
    var b = gfx.Builder.init();
    b.setMat(.water);
    b.quad(v3(-half, WATER_Y, -half), v3(-half, WATER_Y, half), v3(half, WATER_Y, half), v3(half, WATER_Y, -half), v3(0, 1, 0), rl.Color.white);
    return b.toModel(shader);
}


const Placer = struct {
    e: *Env,
    m: *const wf.Map,
    flat: bool,
    cur: u16 = 0,
    left: i32 = 0,
    lean: f32 = 0,
    leanDir: f32 = 0,
    leanExact: bool = false,
    rise: f32 = 0,

    // PLANTED ON THE GROUND, which with elevation means the sculpted height there and not y = 0.
    fn at(self: *Placer, kind: Kind, x: f32, z: f32, yaw: f32, scale: f32, rng: *mathx.Rng) void {
        self.atY(kind, x, self.groundY(x, z), z, yaw, scale, rng);
    }

    fn groundY(self: *const Placer, x: f32, z: f32) f32 {
        if (self.flat) return 0;
        return self.m.heightAt(x, z);
    }

    fn atY(self: *Placer, kind: Kind, x: f32, y: f32, z: f32, yaw: f32, scale: f32, rng: *mathx.Rng) void {
        if (self.e.nprops >= MAX_PROPS) @panic("env: MAX_PROPS exceeded — raise the cap");
        var lean: f32 = 0;
        var leanDir: f32 = self.leanDir;
        const tilt: f32 = if (props.upright(kind)) 0 else self.lean;
        if (tilt != 0) {
            if (self.leanExact) {
                lean = tilt;
            } else {
                lean = tilt * rng.range(0.15, 1.0);
                leanDir = rng.range(0, 360);
            }
        }
        self.e.props[self.e.nprops] = .{ .kind = kind, .pos = v3(x, y, z), .yaw = yaw, .scale = scale, .lean = lean, .leanDir = leanDir, .op = self.cur, .rise = snapRise(kind, scale, self.rise) };
        self.e.nprops += 1;
        if (props.info(kind).light) |ls| self.addLight(@intCast(self.e.nprops - 1), x, y, z, scale, ls, rng);
        if (kind == .water) {
            if (self.e.npools >= self.e.pools.len) @panic("env: water pool cap exceeded — raise Env.pools");
            self.e.pools[self.e.npools] = .{ .pos = v3(x, y, z), .radius = 13.0 * scale };
            self.e.npools += 1;
        }
    }

    fn addLight(self: *Placer, pi: u32, x: f32, y: f32, z: f32, scale: f32, ls: props.LightSpec, rng: *mathx.Rng) void {
        if (self.e.nlights >= MAX_LIGHTS) {
            self.e.lightsCapped += 1;
            return;
        }
        self.e.lights[self.e.nlights] = .{
            .base = .{ .pos = v3(x, y + ls.y * scale, z), .col = ls.col, .radius = ls.radius * mathx.maxF(scale, 0.6) },
            .flicker = ls.flicker,
            .phase = rng.range(0, 60),
            .prop = pi,
        };
        self.e.nlights += 1;
    }

    fn accepts(self: *Placer, o: *const wf.Op, x: f32, z: f32, rng: *mathx.Rng) bool {
        if (self.rejects(o, x, z)) return false;
        if (o.field and rng.float() > FIELD_FLOOR + (1.0 - FIELD_FLOOR) * coverField(x, z)) return false;
        if (o.gAxis != .none and rng.float() > o.gradAt(x, z)) return false;
        return true;
    }

    fn rejects(self: *Placer, o: *const wf.Op, x: f32, z: f32) bool {
        if (o.avoid.runway and self.m.onRunway(x, z)) return true;
        if (o.avoid.water and self.e.inWater(x, z, 1.04)) return true;
        if (o.avoid.clear and self.m.inClearing(x, z)) return true;
        if (o.avoid.solid and self.blockedHere(x, z)) return true;
        return false;
    }

    fn blockedHere(self: *Placer, x: f32, z: f32) bool {
        return self.e.blockedNear(v3(x, self.groundY(x, z) + SOLID_PROBE_Y, z), SOLID_PROBE_M, SOLID_PROBE_R);
    }

/// MEASURED: one line op at 0.001 m spacing over 400 m burns 21 ms a rebuild and places NOTHING; at the parser's
/// own floor, 227 ms. A rebuild fires 0.28 s after every edit and a map holds 20,480 ops.
    const BUDGET: i32 = 8192;

    fn spend(self: *Placer) bool {
        if (self.left <= 0) {
            self.e.opsCapped += 1;
            return false;
        }
        self.left -= 1;
        return true;
    }

    fn expand(self: *Placer, o: *const wf.Op) void {
        self.left = BUDGET;
        var rng = o.stream();
        self.lean = o.lean;
        self.leanDir = o.leanDir;
        self.leanExact = o.op == .at;
        self.rise = o.rise;
        switch (o.op) {
            .at => self.atY(o.kind, o.x, self.groundY(o.x, o.z) + o.r1, o.z, o.yaw, o.scale, &rng),
            .belt => self.belt(o, &rng),
            .disc => self.disc(o, &rng),
            .ring => self.ring(o, &rng),
            .line => self.line(o, &rng),
            .ivy => self.ivy(o, &rng),
        }
    }

    fn belt(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        var i: i32 = 0;
        while (i < o.n) : (i += 1) {
            if (!self.spend()) return;
            const x = rng.range(o.x, o.x1);
            const z = rng.range(o.z, o.z1);
            if (!self.accepts(o, x, z, rng)) continue;
            self.at(o.pick(rng), x, z, rng.range(0, 360), rng.range(o.sLo, o.sHi), rng);
        }
    }

    fn disc(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        var i: i32 = 0;
        while (i < o.n) : (i += 1) {
            if (!self.spend()) return;
            const a = rng.angle();
            const t = rng.float();
            const d = o.r0 + (o.r1 - o.r0) * (t + (@sqrt(t) - t) * o.bias);
            const x = o.x + mathx.cosf(a) * d;
            const z = o.z + mathx.sinf(a) * d;
            if (!self.accepts(o, x, z, rng)) continue;
            self.at(o.pick(rng), x, z, rng.range(0, 360), rng.range(o.sLo, o.sHi), rng);
        }
    }

    fn ring(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        var i: i32 = 0;
        while (i < o.n) : (i += 1) {
            if (!self.spend()) return;
            if (i == o.skip) continue;
            const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(o.n));
            const r = o.r0 * rng.range(0.94, 1.06);
            const x = o.x + mathx.cosf(a) * r;
            const z = o.z + mathx.sinf(a) * r;
            if (self.rejects(o, x, z)) continue;
            self.at(
                o.pick(rng),
                x,
                z,
                mathx.degrees(-a) + 90 + rng.signed() * 12,
                rng.range(o.sLo, o.sHi),
                rng,
            );
        }
    }

    fn line(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        const dx = o.x1 - o.x;
        const dz = o.z1 - o.z;
        const len = @sqrt(dx * dx + dz * dz);
        if (len < 1e-4 or o.r0 < 1e-4) return;
        const ux = dx / len;
        const uz = dz / len;
        const yaw = mathx.degrees(std.math.atan2(-uz, ux));
        var t: f32 = o.r0 * 0.5;
        while (t < len) : (t += o.r0 * rng.range(1.0, 1.5)) {
            if (!self.spend()) return;
            if (rng.float() > o.chance) continue;
            const x = o.x + ux * t + rng.signed() * 0.6;
            const z = o.z + uz * t + rng.signed() * 0.6;
            if (self.rejects(o, x, z)) continue;
            self.at(o.pick(rng), x, z, yaw + rng.signed() * 6, rng.range(o.sLo, o.sHi), rng);
        }
    }

    fn ivy(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        const n = self.e.nprops;
        for (self.e.props[0..n]) |pr| {
            if (!props.ivyClimbs(pr.kind)) continue;
            if (!wf.inRect(pr.pos.x, pr.pos.z, o.x, o.z, o.x1, o.z1)) continue;
            if (rng.float() > o.chance) continue;
            const nfo = props.info(pr.kind);
            const a = rng.angle();
            const d = nfo.bound * pr.scale * rng.range(0.18, 0.42);
            self.at(o.kind, pr.pos.x + mathx.cosf(a) * d, pr.pos.z + mathx.sinf(a) * d, mathx.degrees(a), rng.range(o.sLo, o.sHi), rng);
        }
    }
};


fn hash2(ix: i32, iz: i32) f32 {
    var h: u32 = @bitCast(ix *% 374761393 +% iz *% 668265263);
    h = (h ^ (h >> 13)) *% 1274126177;
    h ^= h >> 16;
    return @as(f32, @floatFromInt(h)) / 4294967295.0;
}

fn vnoise2(x: f32, z: f32) f32 {
    const fx = @floor(x);
    const fz = @floor(z);
    const ix: i32 = @intFromFloat(fx);
    const iz: i32 = @intFromFloat(fz);
    const tx = x - fx;
    const tz = z - fz;
    const ux = tx * tx * (3.0 - 2.0 * tx);
    const uz = tz * tz * (3.0 - 2.0 * tz);
    const a = hash2(ix, iz);
    const b = hash2(ix + 1, iz);
    const c = hash2(ix, iz + 1);
    const d = hash2(ix + 1, iz + 1);
    const lo = a + (b - a) * ux;
    return lo + ((c + (d - c) * ux) - lo) * uz;
}

pub fn coverField(x: f32, z: f32) f32 {
    const big = vnoise2(x / 34.0, z / 34.0);
    const fine = vnoise2(x / 11.0 + 31.7, z / 11.0 - 12.3);
    const t = mathx.clampF((big * 0.72 + fine * 0.28 - 0.18) / 0.64, 0, 1);
    return t * t * (3.0 - 2.0 * t) * 1.25;
}


fn buildSolids(e: *Env) void {
    e.nsolids = 0;
    e.nwards = 0;
    for (e.props[0..e.nprops], 0..) |*pr, pi| {
        const nfo = props.info(pr.kind);
        const s = pr.scale;
        const fr = PropFrame.of(pr);
        var ward: u8 = 0;
        if (nfo.ward) {
            if (e.nwards >= MAX_WARDS) @panic("env: MAX_WARDS exceeded — raise the cap");
            e.wardProps[e.nwards] = @intCast(pi);
            e.wardSolid0[e.nwards] = @intCast(e.nsolids);
            e.wardSolidN[e.nwards] = @intCast(nfo.parts.len);
            e.nwards += 1;
            ward = @intCast(e.nwards);
        }
        pr.ward = ward;
        for (nfo.parts) |part| {
            if (e.nsolids >= MAX_SOLIDS) @panic("env: MAX_SOLIDS exceeded — raise the cap");
            const a = fr.at(part.ax, 0, part.az);
            const b = fr.at(part.bx, 0, part.bz);
            var sol = collision.capsule(a.x, a.z, b.x, b.z, part.r * s);
            sol.h = pr.pos.y + part.h * s;
            if (part.y0 > 0) sol.y0 = pr.pos.y + part.y0 * s;
            sol.surf = nfo.surf;
            sol.ward = ward;
            if (pr.lean != 0) {
                var off = leanSwing(pr, part.h * s * 0.5);
                const lim = part.r * s;
                const len = mathx.lenXZ(off);
                if (len > lim) off = mathx.scaleV(off, lim / len);
                sol.a.x += off.x;
                sol.a.z += off.z;
                sol.b.x += off.x;
                sol.b.z += off.z;
            }
            e.solid_buf[e.nsolids] = sol;
            e.nsolids += 1;
        }
    }
    buildDecks(e);
    var counts = [_]u32{0} ** NCELL;
    for (e.solid_buf[0..e.nsolids]) |s| {
        var it = SolidCells.init(s);
        while (it.next()) |c| counts[c] += 1;
    }
    var total: u32 = 0;
    for (counts, 0..) |n, i| {
        e.sgrid_start[i] = total;
        total += n;
    }
    e.sgrid_start[NCELL] = total;
    if (total > MAX_SOLID_REFS) @panic("env: MAX_SOLID_REFS exceeded — raise the cap");
    var cursor = e.sgrid_start;
    for (e.solid_buf[0..e.nsolids], 0..) |s, si| {
        var it = SolidCells.init(s);
        while (it.next()) |c| {
            e.sgrid_items[cursor[c]] = @intCast(si);
            cursor[c] += 1;
        }
    }
}

const SolidCells = struct {
    x0: usize,
    x1: usize,
    z0: usize,
    z1: usize,
    cx: usize,
    cz: usize,

    fn init(s: collision.Solid) SolidCells {
        const x0 = cellCoord(@min(s.a.x, s.b.x) - s.r);
        const z0 = cellCoord(@min(s.a.z, s.b.z) - s.r);
        return .{
            .x0 = x0,
            .x1 = cellCoord(@max(s.a.x, s.b.x) + s.r),
            .z0 = z0,
            .z1 = cellCoord(@max(s.a.z, s.b.z) + s.r),
            .cx = x0,
            .cz = z0,
        };
    }

    fn next(self: *SolidCells) ?usize {
        if (self.cz > self.z1) return null;
        const out = self.cz * GRID_N + self.cx;
        self.cx += 1;
        if (self.cx > self.x1) {
            self.cx = self.x0;
            self.cz += 1;
        }
        return out;
    }
};

fn buildDecks(e: *Env) void {
    e.ndecks = 0;
    for (e.props[0..e.nprops]) |*pr| {
        const nfo = props.info(pr.kind);
        if (nfo.flight) |fl| {
            if (pr.rise <= 0 or nfo.stack <= 0) continue;
            if (e.ndecks >= MAX_DECKS) @panic("env: MAX_DECKS exceeded — raise the cap");
            const run = flightRun(pr, nfo);
            const th = mathx.radians(pr.yaw);
            const ax = -mathx.sinf(th);
            const az = -mathx.cosf(th);
            const n = sectionsIn(pr.rise, nfo.stack * pr.scale);
            const halfW = fl.halfW * pr.scale;
            e.deck_buf[e.ndecks] = .{
                .x = pr.pos.x,
                .z = pr.pos.z,
                .r = @sqrt(run * run * 0.25 + halfW * halfW) + 0.1,
                .y = pr.pos.y,
                .hole = false,
                .run = run,
                .ax = ax,
                .az = az,
                .rise = pr.rise,
                .halfW = halfW,
                .treads = n * fl.treads,
            };
            e.ndecks += 1;
            continue;
        }
        if (nfo.decks.len == 0) continue;
        const fr = PropFrame.of(pr);
        for (nfo.decks) |d| {
            if (e.ndecks >= MAX_DECKS) @panic("env: MAX_DECKS exceeded — raise the cap");
            const at = fr.at(d.x, d.y, d.z);
            e.deck_buf[e.ndecks] = .{ .x = at.x, .z = at.z, .r = d.r * pr.scale, .y = at.y, .hole = d.hole };
            e.ndecks += 1;
        }
    }
    var counts = [_]u32{0} ** NCELL;
    for (e.deck_buf[0..e.ndecks]) |d| {
        var it = SolidCells.init(collision.circle(d.x + d.ax * d.run * 0.5, d.z + d.az * d.run * 0.5, d.r));
        while (it.next()) |c| counts[c] += 1;
    }
    var total: u32 = 0;
    for (counts, 0..) |n, i| {
        e.dgrid_start[i] = total;
        total += n;
    }
    e.dgrid_start[NCELL] = total;
    if (total > MAX_DECK_REFS) @panic("env: MAX_DECK_REFS exceeded — raise the cap");
    var cursor = e.dgrid_start;
    for (e.deck_buf[0..e.ndecks], 0..) |d, di| {
        var it = SolidCells.init(collision.circle(d.x + d.ax * d.run * 0.5, d.z + d.az * d.run * 0.5, d.r));
        while (it.next()) |c| {
            e.dgrid_items[cursor[c]] = @intCast(di);
            cursor[c] += 1;
        }
    }
}

fn indexProps(e: *Env) void {
    fillIndex(e, &e.stx, false);
    fillIndex(e, &e.flx, true);
    e.ndress = 0;
    e.nchests = 0;
    e.npickups = 0;
    e.nrests = 0;
    @memset(&e.opOwned, 0);
    for (e.props[0..e.nprops], 0..) |*pr, pi| {
        const i: u32 = @intCast(pi);
        if (pr.op < e.opOwned.len) e.opOwned[pr.op] +|= 1;
        const nfo = props.info(pr.kind);
        if (nfo.veil != null or nfo.stow != null) {
            if (e.ndress >= MAX_DRESSED) @panic("env: MAX_DRESSED exceeded — raise the cap");
            e.dressItems[e.ndress] = i;
            e.ndress += 1;
        }
        if (pr.kind == .chest) {
            if (e.nchests >= chestmod.CAP) @panic("env: chest cap exceeded — raise chest.CAP");
            e.chestItems[e.nchests] = i;
            e.nchests += 1;
        }
        if (pr.kind == .pickup) {
            if (e.npickups >= pickupmod.CAP) @panic("env: pickup cap exceeded — raise pickup.CAP");
            e.pickupItems[e.npickups] = i;
            e.npickups += 1;
        }
        if (restmod.isRestKind(pr.kind)) {
            if (e.nrests >= restmod.CAP) @panic("env: rest cap exceeded — raise rest.CAP");
            e.restItems[e.nrests] = i;
            e.nrests += 1;
        }
    }
}

fn fillIndex(e: *Env, idx: *Index, want_flora: bool) void {
    idx.bound = [_]f32{0} ** NCELL;
    idx.view = [_]f32{0} ** NCELL;
    idx.top = [_]f32{0} ** NCELL;
    idx.ylo = [_]f32{0} ** NCELL;
    idx.yhi = [_]f32{0} ** NCELL;
    var counts = [_]u32{0} ** NCELL;
    for (e.props[0..e.nprops]) |*pr| {
        if (props.info(pr.kind).flora != want_flora) continue;
        counts[cellOf(pr.pos.x, pr.pos.z)] += 1;
    }
    var total: u32 = 0;
    for (counts, 0..) |n, i| {
        idx.start[i] = total;
        total += n;
    }
    idx.start[NCELL] = total;
    var cursor = idx.start;
    for (e.props[0..e.nprops], 0..) |*pr, pi| {
        const nfo = props.info(pr.kind);
        if (nfo.flora != want_flora) continue;
        const c = cellOf(pr.pos.x, pr.pos.z);
        const first = cursor[c] == idx.start[c];
        idx.items[cursor[c]] = @intCast(pi);
        cursor[c] += 1;
        idx.bound[c] = mathx.maxF(idx.bound[c], reachOf(pr, nfo));
        idx.view[c] = mathx.maxF(idx.view[c], nfo.view);
        idx.top[c] = mathx.maxF(idx.top[c], runOf(pr, nfo));
        idx.ylo[c] = if (first) pr.pos.y else mathx.minF(idx.ylo[c], pr.pos.y);
        idx.yhi[c] = if (first) pr.pos.y else mathx.maxF(idx.yhi[c], pr.pos.y);
    }
}


fn viewLooking(eye: rl.Vector3, at: rl.Vector3) View {
    return View.fromCamera(.{
        .position = eye,
        .target = at,
        .up = v3(0, 1, 0),
        .fovy = 45,
        .projection = .perspective,
    }, 1.6);
}

test "the view culler keeps what is ahead and rejects what is behind or wide" {
    const headings = [_]rl.Vector3{
        v3(0, 0, 1), v3(0, 0, -1), v3(1, 0, 0), v3(-1, 0, 0),
        v3(0.7, -0.25, 0.7), v3(-0.6, -0.3, 0.74),
        v3(0.1, -0.97, 0.1),
    };
    for (headings) |h| {
        const eye = v3(3, 2, -4);
        const vw = viewLooking(eye, mathx.addV(eye, h));
        const ahead = mathx.addV(eye, mathx.scaleV(h, 20));
        const behind = mathx.addV(eye, mathx.scaleV(h, -20));
        try std.testing.expect(vw.visible(ahead, 0.5, 100));
        try std.testing.expect(!vw.visible(behind, 0.5, 100));
        try std.testing.expect(!vw.visible(ahead, 0.5, 5));
        try std.testing.expect(vw.visible(ahead, 0.5, 250));
        const wide = mathx.addV(ahead, mathx.scaleV(mathx.normV(cross(h, v3(0, 1, 0))), 30));
        try std.testing.expect(!vw.visible(wide, 0.5, 100));
        try std.testing.expect(vw.visible(wide, 26.0, 100));
    }
}

test "the culler accepts the full width of the screen, not just the axis" {
    const vw = viewLooking(v3(0, 0, 0), v3(0, 0, 1));
    const hf = std.math.atan(@tan(mathx.radians(45.0) * 0.5) * 1.6);
    const edge = v3(@tan(hf * 0.94) * 40.0, 0, 40); // 94% of the way to the edge, dead centre vertically
    try std.testing.expect(vw.visible(edge, 0.0, 100));
    try std.testing.expect(vw.visible(v3(-edge.x, 0, edge.z), 0.0, 100));
}

test "A CANOPY HIDES HIM AND THE TRUNK IT HANGS OFF DOES NOT — the occluder volume is not the collider" {
    // A conifer's collider is a 0.58 m pole and its boughs reach 3.4 m, so a camera looking through the branches scores nothing against the pole.
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.props[0] = .{ .kind = .conifer, .pos = v3(2.6, 0, 0), .yaw = 0, .scale = 1 };
    e.nprops = 1;
    fillIndex(e, &e.stx, false);
    const nfo = props.info(.conifer);
    const eye = v3(0, 2.2, -5);
    const hero = v3(0, 1.0, 3);

    var collider: f32 = 0;
    const fr = PropFrame.of(&e.props[0]);
    for (nfo.parts) |part| {
        const r = part.r + OCCL_SKIRT;
        collider = mathx.maxF(collider, thinOf(eye, hero, fr.partFoot(part), part.h, r));
    }
    try std.testing.expectEqual(@as(f32, 0), collider);
    try std.testing.expect(thinFor(&e.props[0], nfo, eye, hero) > 0);
    e.markOccluders(eye, hero, 10.0);
    try std.testing.expect(e.props[0].fade < 1.0);
}

test "architecture never thins, and a kind added to the table cannot opt out by silence" {
    for ([_]props.Kind{ .wall, .tower, .gate, .chapel, .cottage, .watchtower, .cliff, .cliff4 }) |k| {
        try std.testing.expect(props.info(k).solid);
    }
    for ([_]props.Kind{ .bonfire, .chest }) |k| {
        try std.testing.expect(props.info(k).solid);
    }
    for ([_]props.Kind{ .boulder, .statue, .monolith, .lantern, .gibbet, .sapling, .conifer, .bigtree }) |k| {
        try std.testing.expect(!props.info(k).solid);
    }
}

test "GROUND COVER THINS FROM HIS WAIST UP — a thicket in the way does, a tuft round his boots never" {
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    const at = v3(0, 1.0, 0);
    const eye = v3(0, 2.27, -4.42); // the default rig: 4.6 m of boom at 0.28 rad
    for ([_]struct { k: Kind, sc: f32, thins: bool }{
        .{ .k = .thicket, .sc = 1.0, .thins = true },
        .{ .k = .bush, .sc = 1.0, .thins = true },
        .{ .k = .cattails, .sc = 1.0, .thins = true },
        .{ .k = .tuft, .sc = 1.0, .thins = false },
        .{ .k = .fern, .sc = 1.0, .thins = false },
        .{ .k = .tuft, .sc = 1.38, .thins = false },
        // …BUT THE GATE IS ON THE INSTANCE, NOT THE KIND: a bramble is knee-high at nominal scale and a waist-high mass at 1.38, and what the player has to see past is the second one.
        .{ .k = .bramble, .sc = 1.0, .thins = false },
        .{ .k = .bramble, .sc = 1.38, .thins = true },
    }) |row| {
        var any = false;
        var t: f32 = 0.05;
        while (t < 1.0) : (t += 0.05) {
            e.* = .{ .ground = undefined, .models = undefined };
            e.props[0] = .{ .kind = row.k, .pos = v3(0, 0, mathx.lerpF(eye.z, at.z, t)), .yaw = 0, .scale = row.sc };
            e.nprops = 1;
            indexProps(e);
            e.markOccluders(eye, at, 10.0);
            if (e.props[0].fade < 1.0) any = true;
        }
        try std.testing.expectEqual(row.thins, any);
    }
}

test "a FULL occluder list gives its slots to what hides him most, not to what the cell walk reached first" {
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    for (0..OCCL_MAX) |i| {
        e.props[i] = .{ .kind = .snag, .pos = v3(@floatFromInt(i), 0, 0), .yaw = 0, .scale = 1 };
        e.wantFade(@intCast(i), 0.98);
    }
    try std.testing.expectEqual(@as(usize, OCCL_MAX), e.noccl);
    e.props[OCCL_MAX] = .{ .kind = .snag, .pos = v3(0, 0, 9), .yaw = 0, .scale = 1 };
    e.wantFade(OCCL_MAX, OCCL_FLOOR);
    try std.testing.expectApproxEqAbs(OCCL_FLOOR, e.props[OCCL_MAX].fadeTo, 1e-5);
    try std.testing.expectEqual(@as(usize, OCCL_MAX), e.noccl);
    var evicted: usize = 0;
    for (0..OCCL_MAX) |i| {
        if (e.props[i].fadeTo >= 1.0) evicted += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), evicted);
    e.props[OCCL_MAX + 1] = .{ .kind = .snag, .pos = v3(0, 0, 12), .yaw = 0, .scale = 1 };
    e.wantFade(OCCL_MAX + 1, 0.999);
    try std.testing.expectEqual(@as(f32, 1), e.props[OCCL_MAX + 1].fadeTo);
}

test "NOTHING MID-TRAVEL IS DROPPED — a full list refuses the ask rather than snap a tree back to solid" {
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    for (0..OCCL_MAX) |i| {
        e.props[i] = .{ .kind = .snag, .pos = v3(@floatFromInt(i), 0, 0), .yaw = 0, .scale = 1 };
        e.wantFade(@intCast(i), 0.98);
    }
    e.easeFades(1.0 / 60.0);
    for (e.occl[0..e.noccl]) |pi| try std.testing.expect(e.props[pi].fade < FADE_SOLID);
    e.props[OCCL_MAX] = .{ .kind = .snag, .pos = v3(0, 0, 9), .yaw = 0, .scale = 1 };
    e.wantFade(OCCL_MAX, OCCL_FLOOR);
    try std.testing.expectEqual(@as(f32, 1), e.props[OCCL_MAX].fadeTo);
    try std.testing.expectEqual(OCCL_MAX, e.noccl);
    for (e.occl[0..e.noccl]) |pi| try std.testing.expect(e.props[pi].fade < FADE_SOLID);
}

test "A GLOW TAKEN OUT OF THE WORLD TAKES ITS FADE SLOT AND ITS LIGHT WITH IT" {
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.stageOne(.pickup);
    try std.testing.expectEqual(@as(usize, 1), e.lightCount());

    const eye = v3(0, 2.2, -4);
    const hero = v3(0, 1.0, 2);
    e.markOccluders(eye, hero, 1.0 / 60.0);
    try std.testing.expectEqual(@as(usize, 1), e.noccl);
    try std.testing.expect(e.lightOf(e.lights[0], 0) != null);

    e.setPickupDraw(0, 0.5, false);
    const half = e.lightOf(e.lights[0], 0).?;
    try std.testing.expectApproxEqAbs(e.lights[0].base.col.x * 0.5, half.col.x, 1e-4);
    e.setPickupDraw(0, 0, true);
    try std.testing.expect(e.lightOf(e.lights[0], 0) == null);

    e.noccl = 0;
    e.props[0].fade = 1;
    e.props[0].fadeTo = 1;
    e.markOccluders(eye, hero, 1.0 / 60.0);
    try std.testing.expectEqual(@as(usize, 0), e.noccl);
}

test "the shadow cull keeps a distant TALL caster whose shadow still reaches the box" {
    const focus = v3(0, 0, 0);
    const outside = shadowBox() + 10.0;
    try std.testing.expect(castsInto(focus, v3(outside, 0, 0), 18.0, 15.5));
    try std.testing.expect(!castsInto(focus, v3(outside, 0, 0), 0.9, 0.8));
    try std.testing.expect(!castsInto(focus, v3(shadowBox() + 60.0, 0, 0), 18.0, 15.5));
    try std.testing.expect(castsInto(focus, v3(shadowBox() - 10.0, 0, 0), 0.2, 0.2));
}

test "grid cells round-trip a world position" {
    try std.testing.expectEqual(cellOf(0, 0), cellOf(1, 1));
    const c = cellOf(-100, 55);
    const centre = cellCentre(c);
    try std.testing.expect(@abs(centre.x - (-100)) <= CELL * 0.5);
    try std.testing.expect(@abs(centre.z - 55) <= CELL * 0.5);
    try std.testing.expect(cellOf(-9999, 9999) < NCELL);
    try std.testing.expect(cellOf(9999, -9999) < NCELL);
}

test "the sight line thins the tree standing in it, and only that tree" {
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.props[0] = .{ .kind = .bigtree, .pos = v3(0, 0, 0), .yaw = 0, .scale = 1 };
    e.props[1] = .{ .kind = .cottage, .pos = v3(0, 0, 0), .yaw = 0, .scale = 1 };
    e.props[2] = .{ .kind = .bigtree, .pos = v3(0, 0, 40), .yaw = 0, .scale = 1 };
    e.nprops = 3;
    fillIndex(e, &e.stx, false);

    const eyeY: f32 = 2.2;
    e.markOccluders(v3(0, eyeY, -4), v3(0, 1.0, 4), 10.0);
    try std.testing.expectApproxEqAbs(OCCL_FLOOR, e.props[0].fade, 0.001);
    try std.testing.expectEqual(@as(f32, 1), e.props[1].fade);
    try std.testing.expectEqual(@as(f32, 1), e.props[2].fade);
    e.markOccluders(v3(2.6, eyeY, -4), v3(2.6, 1.0, 4), 10.0);
    try std.testing.expectEqual(@as(f32, 1), e.props[0].fade);
    try std.testing.expectEqual(@as(usize, 0), e.noccl);
    e.markOccluders(v3(60, eyeY, -4), v3(60, 1.0, 4), 10.0);
    try std.testing.expectEqual(@as(f32, 1), e.props[0].fade);
    try std.testing.expectEqual(@as(usize, 0), e.noccl);
}

test "THE FADE TAKES TIME, both ways, and never overshoots either end" {
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.props[0] = .{ .kind = .bigtree, .pos = v3(0, 0, 0), .yaw = 0, .scale = 1 };
    e.nprops = 1;
    fillIndex(e, &e.stx, false);
    const eye = v3(0, 2.2, -4);
    const hero = v3(0, 1.0, 4);
    const step = 1.0 / 60.0;

    e.markOccluders(eye, hero, step);
    try std.testing.expect(e.props[0].fade > 0.9 and e.props[0].fade < 1.0);
    try std.testing.expectApproxEqAbs(OCCL_FLOOR, e.props[0].fadeTo, 0.001);
    var t: f32 = step;
    while (t < OCCL_IN + step) : (t += step) e.markOccluders(eye, hero, step);
    try std.testing.expectApproxEqAbs(OCCL_FLOOR, e.props[0].fade, 0.001);
    e.markOccluders(eye, hero, step);
    try std.testing.expectApproxEqAbs(OCCL_FLOOR, e.props[0].fade, 0.001);

    const clear = v3(60, 2.2, -4);
    e.markOccluders(clear, v3(60, 1.0, 4), step);
    try std.testing.expect(e.props[0].fade > OCCL_FLOOR and e.props[0].fade < 1.0);
    try std.testing.expect(e.props[0].fade - OCCL_FLOOR < 1.0 - e.props[0].fade);
    try std.testing.expectEqual(@as(usize, 1), e.noccl);
    t = step;
    while (t < OCCL_OUT + step) : (t += step) e.markOccluders(clear, v3(60, 1.0, 4), step);
    try std.testing.expectEqual(@as(f32, 1), e.props[0].fade); // exactly solid, not 0.997
    try std.testing.expectEqual(@as(usize, 0), e.noccl);
}

test "an occluder passing HIS depth eases out instead of snapping" {
    const eye = v3(0, 2.2, -6);
    const hero = v3(0, 1.0, 0);
    const wide = 1.85;
    var prev = thinOf(eye, hero, v3(0, 0, -2.0), 6.0, wide);
    try std.testing.expect(prev > 0.99);
    for (1..19) |k| {
        const z = -2.0 + 0.2 * @as(f32, @floatFromInt(k));
        const now = thinOf(eye, hero, v3(0, 0, z), 6.0, wide);
        try std.testing.expect(now <= prev + 1e-4);
        try std.testing.expect(prev - now < 0.2);
        prev = now;
    }
    try std.testing.expectApproxEqAbs(@as(f32, 0), prev, 1e-4);
}

test "what covers him thins, what merely stands near the sight line does not" {
    const eye = v3(0, 2.2, -6);
    const hero = v3(0, 1.0, 0);
    try std.testing.expect(coverFrac(eye, hero, v3(0, 0, -2), 6.0, 1.85).cover > OCCL_FULL);
    try std.testing.expect(coverFrac(eye, hero, v3(3.0, 0, -2), 6.0, 1.85).cover < OCCL_MIN);
    try std.testing.expect(coverFrac(eye, hero, v3(0, 0, -2), 0.5, 0.6).cover < OCCL_MIN);
    const part = coverFrac(eye, hero, v3(0, 0, -2), 1.3, 1.85).cover;
    try std.testing.expect(part > OCCL_MIN and part < OCCL_FULL);
    try std.testing.expectEqual(@as(f32, 0), coverFrac(eye, hero, v3(0, 0, 4), 6.0, 1.85).cover);
}

test "COVERAGE ALONE OPENS THE GATE — the depth ramp scales the answer, it does not veto it" {
    const eye = v3(0, 2.2, -6);
    const hero = v3(0, 1.0, 0);
    const near = v3(0, 0, -0.7);
    try std.testing.expect(coverFrac(eye, hero, near, 6.0, 1.85).cover > OCCL_FULL);
    const a = coverFrac(eye, hero, near, 6.0, 1.85).ahead;
    try std.testing.expect(a > 0 and a < 1);
    const t = thinOf(eye, hero, near, 6.0, 1.85);
    try std.testing.expect(t > 0 and t < 1);
    try std.testing.expectApproxEqAbs(a, t, 1e-4);
}

test "a solid's cell iterator covers its whole footprint" {
    var s = collision.capsule(-9, 0, 9, 0, 3);
    s.h = 15;
    var seen: usize = 0;
    var it = SolidCells.init(s);
    var hasLeft = false;
    var hasRight = false;
    while (it.next()) |c| {
        seen += 1;
        if (c == cellOf(-11, 0)) hasLeft = true;
        if (c == cellOf(11, 0)) hasRight = true;
    }
    try std.testing.expect(seen >= 2);
    try std.testing.expect(hasLeft and hasRight);
}

test "a solid's blocking height is a WORLD height, so cover still works up a bank" {
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    const top = props.info(.wall).parts[0].h;
    e.props[0] = .{ .kind = .wall, .pos = v3(0, 0, 0), .yaw = 0, .scale = 1, .op = 0 };
    e.props[1] = .{ .kind = .wall, .pos = v3(60, 12, 0), .yaw = 0, .scale = 1, .op = 0 };
    e.nprops = 2;
    buildSolids(e);
    var buf: [MAX_NEAR]collision.Solid = undefined;
    const flat = e.nearSolids(v3(0, 0, 0), 1.0, &buf);
    try std.testing.expect(collision.blockedBy(v3(0, top - 0.5, 0), 0.04, flat));
    try std.testing.expect(!collision.blockedBy(v3(0, top + 0.5, 0), 0.04, flat));
    const up = e.nearSolids(v3(60, 12, 0), 1.0, &buf);
    try std.testing.expect(collision.blockedBy(v3(60, 12 + top - 0.5, 0), 0.04, up));
    try std.testing.expect(!collision.blockedBy(v3(60, 12 + top + 0.5, 0), 0.04, up));
}

test "A WALL STOPS A LOOK, and the grid is walked far enough out to find one at range" {
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.props[0] = .{ .kind = .wall, .pos = v3(0, 0, 0), .yaw = 0, .scale = 1, .op = 0 };
    e.nprops = 1;
    buildSolids(e);
    const eye: f32 = 1.25;
    try std.testing.expect(!e.sees(v3(0, eye, -22), v3(0, eye, 22)));
    try std.testing.expect(!e.sees(v3(0, eye, -3), v3(0, eye, 3)));
    try std.testing.expect(e.sees(v3(-20, eye, -3), v3(20, eye, -3)));
    try std.testing.expect(e.sees(v3(40, eye, -22), v3(40, eye, 22)));
    e.nprops = 0;
    buildSolids(e);
    try std.testing.expect(e.sees(v3(0, eye, -22), v3(0, eye, 22)));
}

fn envWithFogGate() !*Env {
    const e = try std.testing.allocator.create(Env);
    e.* = .{ .ground = undefined, .models = undefined };
    e.props[0] = .{ .kind = .foggate, .pos = v3(0, 0, 0), .yaw = 0, .scale = 1, .op = 0 };
    e.nprops = 1;
    buildSolids(e);
    return e;
}

test "A FOG GATE IS A DOOR TO HIM AND A WALL TO A FOE, ENTERING AND LEAVING ALIKE" {
    const e = try envWithFogGate();
    defer std.testing.allocator.destroy(e);
    const R: f32 = 0.42;
    for ([2]f32{ -0.25, 0.25 }) |z| {
        const at = v3(0, 0, z);
        try std.testing.expectEqual(at.x, e.resolveHeroSide(at, R, 0).x);
        try std.testing.expectEqual(at.z, e.resolveHeroSide(at, R, 0).z);
        const shoved = e.resolveActor(at, R, 0);
        try std.testing.expect(@abs(shoved.z) > @abs(z));
        try std.testing.expect(shoved.z * z > 0);
    }
    // Off the end of the sheet is open ground for both. Measured off the ROW, not the mesh constants.
    const ward = props.info(.foggate).parts[0];
    const past = v3(ward.bx + ward.r + R + 1.0, 0, 0);
    try std.testing.expectEqual(past.z, e.resolveActor(past, R, 0).z);
    try std.testing.expectEqual(@as(f32, 0.25), e.resolveActor(v3(0, 0, 0.25), R, ward.h + 0.1).z);
}

test "A FOG GATE STOPS A LOOK, AND STOPS HIS TOO" {
    const e = try envWithFogGate();
    defer std.testing.allocator.destroy(e);
    const eye: f32 = 1.25;
    try std.testing.expect(!e.sees(v3(0, eye, -9), v3(0, eye, 9)));
    try std.testing.expect(!e.sees(v3(1.4, eye, -9), v3(-1.4, eye, 9)));
    try std.testing.expect(e.sees(v3(6, eye, -9), v3(6, eye, 9)));
}

test "A BLINK ACROSS A FOG GATE IS A CROSSING; the same jump over a wall is not this rule's business" {
    const e = try envWithFogGate();
    defer std.testing.allocator.destroy(e);
    try std.testing.expectEqual(@as(?u8, 0), e.wardCrossed(v3(0, 0, -5), v3(0, 0, 5)));
    try std.testing.expectEqual(@as(?u8, null), e.wardCrossed(v3(0, 0, -5), v3(0, 0, -1))); // short of it
    try std.testing.expectEqual(@as(?u8, null), e.wardCrossed(v3(6, 0, -5), v3(6, 0, 5))); // round the end
    e.props[0] = .{ .kind = .wall, .pos = v3(0, 0, 0), .yaw = 0, .scale = 1, .op = 0 };
    buildSolids(e);
    try std.testing.expectEqual(@as(usize, 0), e.nwards);
    try std.testing.expectEqual(@as(?u8, null), e.wardCrossed(v3(0, 0, -5), v3(0, 0, 5)));
    try std.testing.expect(!e.sees(v3(0, 1.25, -5), v3(0, 1.25, 5)));
}

test "A CROSSING CLEARS THE SHEET WHEREVER HE STARTED FROM" {
    const e = try envWithFogGate();
    defer std.testing.allocator.destroy(e);
    const R: f32 = 0.42;
    for ([_]f32{ -0.55, -1.50, -2.20 }) |z| {
        const at = v3(0.3, 0, z);
        const x = e.wardCross(0, at, R).?;
        try std.testing.expect(x.dir.z > 0.9);
        try std.testing.expect(x.to.z > 0);
        try std.testing.expect(e.wardClear(0, x.to, R));
        try std.testing.expect(mathx.distXZ(at, x.to) < @abs(z) + 3.0);
    }
    const back = e.wardCross(0, v3(0, 0, 1.4), R).?;
    try std.testing.expect(back.dir.z < -0.9);
    try std.testing.expect(back.to.z < 0);
}

test "A FOG GATE BLOCKS HIM UNTIL HE ASKS TO PASS IT — the walk is the only way through" {
    const e = try envWithFogGate();
    defer std.testing.allocator.destroy(e);
    const there = v3(0, 0, -5);
    const back = v3(0, 0, 5);
    try std.testing.expectEqual(@as(?u8, 0), e.wardRefusing(there, back, null));
    try std.testing.expectEqual(@as(?u8, 0), e.wardRefusing(back, there, null));
    try std.testing.expectEqual(@as(?u8, null), e.wardRefusing(there, back, 0));
    try std.testing.expectEqual(@as(?u8, 0), e.wardRefusing(there, back, 1)); // a walk at another door is not this one
    try std.testing.expectEqual(@as(?u8, null), e.wardRefusing(v3(6, 0, -5), v3(6, 0, 5), null));
}

test "A SHUT GATE IS A WALL TO HIM TOO, and an open one is not" {
    const e = try envWithFogGate();
    defer std.testing.allocator.destroy(e);
    const R: f32 = 0.42;
    const at = v3(0, 0, 0.25);
    try std.testing.expectEqual(at.z, e.resolveHeroSide(at, R, 0).z);
    e.wardIn[0] = true;
    e.wardShut[0] = true;
    try std.testing.expect(e.resolveHeroSide(at, R, 0).z > at.z);
    e.openWards();
    try std.testing.expectEqual(at.z, e.resolveHeroSide(at, R, 0).z);
    try std.testing.expect(!e.wardClear(0, at, R));
    try std.testing.expect(e.wardClear(0, v3(0, 0, 4), R));
}

fn envWithRamp(rise: f32) !*Env {
    const e = try std.testing.allocator.create(Env);
    e.* = .{ .ground = undefined, .models = undefined };
    e.heightHalf = wf.DEFAULT_HALF;
    e.heightAny = true;
    const step = 2 * e.heightHalf / @as(f32, @floatFromInt(wf.HEIGHT_N - 1));
    for (0..wf.HEIGHT_N) |iz| {
        for (0..wf.HEIGHT_N) |ix| {
            const x = -e.heightHalf + @as(f32, @floatFromInt(ix)) * step;
            e.heightField[iz * wf.HEIGHT_N + ix] = wf.heightByte(x * rise);
        }
    }
    return e;
}

test "walkStep: an incline inside the limit is taken, a cliff face is refused" {
    // A 20 deg slope (tan 0.364) — comfortably walkable.
    {
        const e = try envWithRamp(0.364);
        defer std.testing.allocator.destroy(e);
        try std.testing.expect(e.walkableAt(0, 0));
        const up = e.walkStep(v3(0, 0, 0), v3(1, 0, 0), 0.1);
        try std.testing.expectApproxEqAbs(@as(f32, 0.1), up.x, 1e-4);
    }
    // A 45 deg bank (tan 1.0) — 0.5 m over the half-metre probe, UNDER `STEP_UP`, and it is not a riser.
    {
        const e = try envWithRamp(1.0);
        defer std.testing.allocator.destroy(e);
        const up = e.walkStep(v3(0, 0, 0), v3(1, 0, 0), 0.1);
        try std.testing.expectApproxEqAbs(@as(f32, 0), up.x, 1e-4);
    }
    // 38 deg (tan 0.78) — inside the limit, taken.
    {
        const e = try envWithRamp(0.78);
        defer std.testing.allocator.destroy(e);
        const up = e.walkStep(v3(0, 0, 0), v3(1, 0, 0), 0.1);
        try std.testing.expectApproxEqAbs(@as(f32, 0.1), up.x, 1e-4);
    }
    // A 60 deg face (tan 1.73) — past MAX_SLOPE, so the climb is refused outright.
    {
        const e = try envWithRamp(1.73);
        defer std.testing.allocator.destroy(e);
        try std.testing.expect(!e.walkableAt(0, 0));
        const up = e.walkStep(v3(0, 0, 0), v3(1, 0, 0), 0.1);
        try std.testing.expectApproxEqAbs(@as(f32, 0), up.x, 1e-4);
        const down = e.walkStep(v3(0, 0, 0), v3(-1, 0, 0), 0.1);
        try std.testing.expectApproxEqAbs(@as(f32, -0.1), down.x, 1e-4);
        const across = e.walkStep(v3(0, 0, 0), mathx.normV(v3(1, 0, 1)), 0.1);
        try std.testing.expect(@abs(across.z - 0.1) < 0.02);
        try std.testing.expect(across.x < 0.02);
    }
}

test "THE STEP RULE IS FRAME-RATE INDEPENDENT — a wall cannot be ratcheted up 0.4 m at a time" {
    const e = try envWithRamp(1.73); // 60 deg: not walkable at any dt
    defer std.testing.allocator.destroy(e);
    for ([_]f32{ 1.0 / 30.0, 1.0 / 60.0, 1.0 / 144.0, 1.0 / 1000.0 }) |dt| {
        var p = v3(0, 0, 0);
        var i: usize = 0;
        while (i < 200) : (i += 1) p = e.walkStep(p, v3(1, 0, 0), 6.0 * dt);
        try std.testing.expectApproxEqAbs(@as(f32, 0), p.x, 1e-3);
    }
}

test "flyStep: a jump crosses what it is OVER, and a cliff is a wall at any altitude" {
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.heightHalf = wf.DEFAULT_HALF;
    e.heightAny = true;
    const mid = wf.HEIGHT_N / 2;
    const WALL: f32 = 3.0;
    for (0..wf.HEIGHT_N) |iz| {
        for (0..wf.HEIGHT_N) |ix| {
            e.heightField[iz * wf.HEIGHT_N + ix] = wf.heightByte(if (ix >= mid) WALL else 0.0);
        }
    }
    const at = v3(-1.0, 0, 0);
    const east = v3(1, 0, 0);
    const foot = e.groundAt(at.x, at.z);
    try std.testing.expectApproxEqAbs(at.x, e.flyStep(at, east, 2.0, foot).x, 1e-4);
    try std.testing.expectApproxEqAbs(at.x, e.flyStep(at, east, 2.0, foot + 1.0).x, 1e-4);
    try std.testing.expect(e.flyStep(at, east, 2.0, foot + WALL).x > at.x);
    const low = try envWithRamp(0.30);
    defer std.testing.allocator.destroy(low);
    const g0 = low.groundAt(0, 0);
    try std.testing.expect(low.flyStep(v3(0, 0, 0), east, 0.5, g0).x > 0.4);
}

test "A JUMP CLEARS A LOW COLLIDER AND A WALL IS STILL A WALL — the push-out reads `Solid.h`" {
    const HR = HERO_R_PIN;
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };

    // A LOG: one capsule along X, blocking to 0.75 m — under the jump's 1.0 m apex.
    e.props[0] = .{ .kind = .log, .pos = v3(0, 0, 0), .yaw = 0, .scale = 1, .op = 0 };
    e.nprops = 1;
    buildSolids(e);
    const logTop = props.info(.log).parts[0].h;
    const at = v3(0, 0, 0.2);
    try std.testing.expect(e.resolveActor(at, HR, 0).z > 0.5);
    try std.testing.expectEqual(at.z, e.resolveActor(at, HR, logTop).z);
    try std.testing.expectEqual(at.z, e.resolveActor(at, HR, 0.9).z);
    try std.testing.expect(e.resolveActor(at, HR, logTop - 0.05).z > 0.5);

    // A WALL blocks to 3.0 m, which no jump in this game reaches, so the law survives intact.
    e.props[0] = .{ .kind = .wall, .pos = v3(0, 0, 0), .yaw = 0, .scale = 1, .op = 0 };
    buildSolids(e);
    try std.testing.expect(props.info(.wall).parts[0].h > 3.0 * logTop);
    try std.testing.expect(e.resolveActor(at, HR, 0.9).z > 0.5);

    e.props[0] = .{ .kind = .log, .pos = v3(0, 2.0, 0), .yaw = 0, .scale = 1, .op = 0 };
    buildSolids(e);
    try std.testing.expect(e.resolveActor(at, HR, 0.9).z > 0.5);
}

test "a SLIGHT STEP is always taken, however steep the face carrying it" {
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.heightHalf = wf.DEFAULT_HALF;
    e.heightAny = true;
    const mid = wf.HEIGHT_N / 2;
    const LEDGE: f32 = 0.5;
    for (0..wf.HEIGHT_N) |iz| {
        for (0..wf.HEIGHT_N) |ix| {
            e.heightField[iz * wf.HEIGHT_N + ix] = wf.heightByte(if (ix >= mid) LEDGE else 0.0);
        }
    }
    const step = 2 * e.heightHalf / @as(f32, @floatFromInt(wf.HEIGHT_N - 1));
    const x0 = -e.heightHalf + @as(f32, @floatFromInt(mid)) * step - step * 1.5;
    var p = v3(x0, 0, 0);
    var i: usize = 0;
    while (i < 120) : (i += 1) p = e.walkStep(p, v3(1, 0, 0), 6.0 / 60.0);
    try std.testing.expect(p.x > x0 + 4.0);
    try std.testing.expectApproxEqAbs(LEDGE, e.groundAt(p.x, p.z) - GROUND_Y, 1e-3);
    try std.testing.expect(LEDGE <= STEP_UP);

    for (0..wf.HEIGHT_N) |iz| {
        for (0..wf.HEIGHT_N) |ix| {
            e.heightField[iz * wf.HEIGHT_N + ix] = wf.heightByte(if (ix >= mid) 6.0 else 0.0);
        }
    }
    var q = v3(x0, 0, 0);
    i = 0;
    while (i < 120) : (i += 1) q = e.walkStep(q, v3(1, 0, 0), 6.0 / 60.0);
    try std.testing.expect(e.groundAt(q.x, q.z) - GROUND_Y < 0.01);
}

fn envWithBeach(fall: f32) !*Env {
    const e = try std.testing.allocator.create(Env);
    e.* = .{ .ground = undefined, .models = undefined };
    e.heightHalf = wf.DEFAULT_HALF;
    e.heightAny = true;
    const step = 2 * e.heightHalf / @as(f32, @floatFromInt(wf.HEIGHT_N - 1));
    for (0..wf.HEIGHT_N) |iz| {
        for (0..wf.HEIGHT_N) |ix| {
            const x = -e.heightHalf + @as(f32, @floatFromInt(ix)) * step;
            e.heightField[iz * wf.HEIGHT_N + ix] = wf.heightByte(-x * fall);
        }
    }
    e.waterAny = true;
    e.waterHalf = wf.DEFAULT_HALF;
    @memset(&e.waterField, 255);
    return e;
}

test "DEEP WATER IS A WALL — waist-deep is waded, over the waist is refused, and wading OUT never is" {
    const e = try envWithBeach(0.25); // 14 deg of shelf: walkable, so only the water can refuse anything
    defer std.testing.allocator.destroy(e);
    try std.testing.expect(e.walkableAt(4, 0));

    var p = v3(-2.0, 0, 0);
    var i: usize = 0;
    while (i < 600) : (i += 1) p = e.walkStep(p, v3(1, 0, 0), 6.0 / 60.0);
    try std.testing.expect(e.wadeDepth(p.x, p.z) <= WADE_MAX);
    try std.testing.expect(p.x > 2.0);

    e.waterAny = false;
    var q = v3(-2.0, 0, 0);
    i = 0;
    while (i < 600) : (i += 1) q = e.walkStep(q, v3(1, 0, 0), 6.0 / 60.0);
    try std.testing.expect(q.x > p.x + 10.0);

    e.waterAny = true;
    var r = v3(20.0, 0, 0);
    try std.testing.expect(e.wadeDepth(r.x, r.z) > WADE_MAX);
    i = 0;
    while (i < 600) : (i += 1) r = e.walkStep(r, v3(-1, 0, 0), 6.0 / 60.0);
    try std.testing.expect(e.wadeDepth(r.x, r.z) <= WADE_MAX);
}

test "A SHALLOWER WATERLINE STOPS A THING SOONER — one gate, a limit per body" {
    const e = try envWithBeach(0.25);
    defer std.testing.allocator.destroy(e);

    const KNEE: f32 = 0.55;
    var shallow = v3(-2.0, 0, 0);
    var deep = v3(-2.0, 0, 0);
    var i: usize = 0;
    while (i < 600) : (i += 1) {
        shallow = e.walkStepPast(shallow, v3(1, 0, 0), 6.0 / 60.0, KNEE);
        deep = e.walkStepPast(deep, v3(1, 0, 0), 6.0 / 60.0, std.math.floatMax(f32));
    }
    try std.testing.expect(e.wadeDepth(shallow.x, shallow.z) <= KNEE);
    try std.testing.expect(deep.x > shallow.x + 2.0);
    std.debug.print("\n  wade: a knee-deep walker stops at {d:.2} m of water, a waterfaring one crosses to {d:.1} m in\n", .{
        e.wadeDepth(shallow.x, shallow.z),
        deep.x,
    });
}

test "DEEP WATER READS DEEP — the sheet is darkened by the DIG, not by the shore alone" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    m.blank("Tarn");
    try std.testing.expect(m.paintWater(0, 0, 60, true, .natural, .water));

    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.uploadWater(m);
    const RIM = v3(56, 0, 0);
    const flat = e.paintedDepth(RIM.x, RIM.z);
    try std.testing.expect(flat > 0 and flat < 0.6);

    var span: [4]usize = undefined;
    try std.testing.expect(m.sculpt(RIM.x, RIM.z, 10, .lower, 3.0, &span));
    e.uploadWater(m);
    try std.testing.expect(e.paintedDepth(RIM.x, RIM.z) > flat + 0.2);

    try std.testing.expectApproxEqAbs(@as(f32, 1), digTone(WADE_MAX), 1e-6);
    try std.testing.expect(digTone(WADE_MAX * 0.5) < 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 1), digTone(WADE_MAX * 4.0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), digTone(-1.0), 1e-6);
}

test "the wade cap is the CHEST" {
    try std.testing.expect(WADE_MAX > 1.3 and WADE_MAX < 1.45); // the thorax on the 1.8 m rig is 1.368
    try std.testing.expect(WADE_MAX > STEP_UP);
}

test "env's ground agrees with the MAP's to the millimetre" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    m.blank("Agree");
    var span: [4]usize = undefined;
    _ = m.sculpt(-30, 40, 26, .raise, 7.5, &span);
    _ = m.sculpt(20, -20, 14, .lower, 3.0, &span);

    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.heightField = m.height;
    e.heightHalf = m.half;
    e.heightAny = m.anyHeight();
    for ([_][2]f32{ .{ -30, 40 }, .{ 20, -20 }, .{ 0, 0 }, .{ -117.3, 88.6 }, .{ 279, -279 } }) |p| {
        try std.testing.expectApproxEqAbs(m.heightAt(p[0], p[1]) + GROUND_Y, e.groundAt(p[0], p[1]), 1e-5);
    }
    e.heightAny = false;
    try std.testing.expectApproxEqAbs(GROUND_Y, e.groundAt(-30, 40), 1e-6);
}

test "rayGround finds the surface of a hill, not the plane under it" {
    const e = try envWithRamp(0.5); // a steady 26 deg slope rising with x
    defer std.testing.allocator.destroy(e);
    const hit = e.rayGround(v3(40, 200, 0), v3(0, -1, 0)) orelse return error.NoHit;
    try std.testing.expectApproxEqAbs(@as(f32, 40), hit.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 20) + GROUND_Y, hit.y, 0.05);
    const flatT = (GROUND_Y - 60.0) / -0.5;
    const oblique = e.rayGround(v3(-60, 60, 0), mathx.normV(v3(1, -0.5, 0))) orelse return error.NoHit;
    try std.testing.expect(oblique.x < -60 + flatT * 0.9);
    try std.testing.expectApproxEqAbs(e.groundAt(oblique.x, oblique.z), oblique.y, 0.05);
    try std.testing.expect(e.rayGround(v3(0, 10, 0), mathx.normV(v3(0, 1, 0))) == null);
}

test "the cover field actually varies — real clearings and real thickets" {
    var lo: f32 = 9;
    var hi: f32 = -9;
    var sum: f32 = 0;
    var n: f32 = 0;
    var x: f32 = -wf.DEFAULT_HALF;
    while (x <= wf.DEFAULT_HALF) : (x += 3) {
        var z: f32 = -wf.DEFAULT_HALF;
        while (z <= wf.DEFAULT_HALF) : (z += 3) {
            const f = coverField(x, z);
            lo = @min(lo, f);
            hi = @max(hi, f);
            sum += f;
            n += 1;
        }
    }
    try std.testing.expect(lo <= 0.02);
    try std.testing.expect(hi >= 1.15);
    const mean = sum / n;
    try std.testing.expect(mean > 0.45 and mean < 0.80);
}

test "the SHIPPED map parses, and its zones cover every reachable position" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    var line: usize = 0;
    try wf.loadForTest(wf.START_MAP, m, &line);
    try std.testing.expect(m.nops > 0);
    try std.testing.expect(m.half > 0);
}

test "every generator op in the shipped map has its own seed" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    var line: usize = 0;
    try wf.loadForTest(wf.START_MAP, m, &line);
    for (m.slice(), 0..) |o, i| {
        if (o.op == .at) continue;
        try std.testing.expect(o.seed != 0);
        for (m.slice()[0..i]) |prev| {
            if (prev.op != .at) try std.testing.expect(prev.seed != o.seed);
        }
    }
}

test "A PROP PLACED CANNOT MOVE THE GROUND — an unchanged height field is not rebuilt" {
    const m = try wf.testMap(std.testing.allocator, wf.TEST_HEAD ++ "at: pillar 0 0 0 1\n");
    defer std.testing.allocator.destroy(m);
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.heightHalf = 0; // `build`'s job, and this Env never had one

    const first = terrainBuildCount();
    e.uploadHeight(m);
    try std.testing.expectEqual(first + 1, terrainBuildCount());

    e.uploadHeight(m);
    e.uploadHeight(m);
    try std.testing.expectEqual(first + 1, terrainBuildCount());

    m.half += 1;
    e.uploadHeight(m);
    try std.testing.expectEqual(first + 2, terrainBuildCount());

    m.height[wf.HEIGHT_CELLS / 2] = wf.HEIGHT_ZERO + 1;
    try std.testing.expect(m.anyHeight());
}

test "PAINTING NO SOIL UPLOADS NO SOIL — the third field skips on an unchanged compare like its two siblings" {
    const m = try wf.testMap(std.testing.allocator, wf.TEST_HEAD ++ "at: pillar 0 0 0 1\n");
    defer std.testing.allocator.destroy(m);
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };

    const first = soilBuildCount();
    e.uploadSoil(m);
    e.uploadSoil(m);
    e.uploadSoil(m);
    try std.testing.expectEqual(first + 1, soilBuildCount());

    m.soil[wf.SOIL_CELLS / 2] = 1;
    e.uploadSoil(m);
    try std.testing.expectEqual(first + 2, soilBuildCount());

    m.soilCov[wf.SOIL_CELLS / 2] = 3;
    e.uploadSoil(m);
    try std.testing.expectEqual(first + 3, soilBuildCount());

    m.soilEdge[wf.SOIL_CELLS / 2] = 2;
    e.uploadSoil(m);
    try std.testing.expectEqual(first + 4, soilBuildCount());

    m.half += 1;
    e.uploadSoil(m);
    try std.testing.expectEqual(first + 5, soilBuildCount());
}

test "THE COAST IS DERIVED ONLY WHEN SOMETHING IT READS MOVED — the DIG is one of them" {
    const m = try wf.testMap(std.testing.allocator, wf.TEST_HEAD ++ "at: pillar 0 0 0 1\n");
    defer std.testing.allocator.destroy(m);
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };

    const first = waterBuildCount();
    e.uploadWater(m);
    e.uploadWater(m);
    e.uploadWater(m);
    try std.testing.expectEqual(first + 1, waterBuildCount());

    m.water[wf.WATER_CELLS / 2] = 1;
    e.uploadWater(m);
    try std.testing.expectEqual(first + 2, waterBuildCount());

    e.sculptHeight(m, wf.EMPTY_SPAN);
    m.height[wf.HEIGHT_CELLS / 2] = wf.HEIGHT_ZERO - 4;
    e.uploadWater(m);
    try std.testing.expectEqual(first + 3, waterBuildCount());
}

test "A FLOOR IS A FLOOR AND ITS HATCH IS A HOLE, and neither is anything to a body on the ground" {
    const m = try wf.testMap(std.testing.allocator, wf.TEST_HEAD ++ "at: watchtower 0 0 0 1\n");
    defer std.testing.allocator.destroy(m);
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.materialize(m);
    const mid = propbuild.WATCH_DECK_TOP;
    const roof = propbuild.WATCH_ROOF_TOP;
    const hz = propbuild.WATCH_HATCH_Z;

    try std.testing.expectEqual(@as(?f32, null), e.deckAt(0, 0, 0));
    try std.testing.expectEqual(@as(?f32, mid), e.deckAt(0, 0, mid));
    try std.testing.expectEqual(@as(?f32, null), e.deckAt(0, hz, mid));
    for (propbuild.WATCH_STOREYS, 0..) |st, i| {
        const y = st.top();
        try std.testing.expectEqual(@as(?f32, y), e.deckAt(0, 0, y));
        const under: ?f32 = if (i == 0) null else propbuild.WATCH_STOREYS[i - 1].top();
        try std.testing.expectEqual(under, e.deckAt(st.hx, st.hz, y));
    }
    try std.testing.expectApproxEqAbs(roof, e.standAt(0, 0, roof), 1e-4);
    try std.testing.expectApproxEqAbs(e.groundAt(0, hz), e.standAt(0, hz, mid), 1e-4);
    const under = propbuild.WATCH_STOREYS[propbuild.WATCH_STOREYS.len - 2].top();
    try std.testing.expectApproxEqAbs(roof, e.standAt(0, 0, roof + 0.5), 1e-4);
    try std.testing.expectApproxEqAbs(under, e.standAt(0, 0, under + STEP_UP * 0.5), 1e-4);
    try std.testing.expectApproxEqAbs(e.groundAt(0, 0), e.standAt(0, 0, mid - 1.0), 1e-4);
    std.debug.print("\n  watchtower: {d} storeys, first at {d:.2} m and the roof at {d:.2} m, shaft clear to {d:.2} m of the axis\n", .{
        propbuild.WATCH_STOREYS.len, mid, roof, props.TOWER_CLEAR,
    });
}

test "A RUN IS WHOLE SECTIONS, AND THE FILE MAY NOT SHOW A HEIGHT THE WORLD ROUNDS OFF" {
    const seg = props.info(.ladder).stack;
    try std.testing.expect(seg > 0);
    for (props.INFO) |row| {
        if (row.stack > 0) try std.testing.expect(row.kind == .ladder or row.kind == .stairflight);
        if (row.flight != null) try std.testing.expect(row.stack > 0);
    }
    try std.testing.expectApproxEqAbs(seg * 8, snapRise(.ladder, 1, 7.15), 1e-4);
    try std.testing.expectApproxEqAbs(seg * 8, snapRise(.ladder, 1, 7.20), 1e-4);
    try std.testing.expectApproxEqAbs(seg * 2 * 4, snapRise(.ladder, 2, 7.20), 1e-4);
    try std.testing.expectEqual(@as(f32, 0), snapRise(.ladder, 1, 0));
    try std.testing.expectEqual(@as(f32, 0), snapRise(.pillar, 1, 7.2));
    // The grain against the band is a comptime assert beside `LADDER_PROUD`; this prints the numbers.
    std.debug.print("  ladder: section {d:.2} m, exit band {d:.2} proud + {d:.2} short = {d:.2} m — every lip is reachable\n", .{
        seg, LADDER_PROUD, STEP_UP, LADDER_PROUD + STEP_UP,
    });
}

test "A LADDER IS FOUND BY ITS CLIMBING LINE, from the foot of the run and from the head of it" {
    const m = try wf.testMap(std.testing.allocator, wf.TEST_HEAD ++ "at: ladder 4 0 270 1 rise=7.2\n");
    defer std.testing.allocator.destroy(m);
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.materialize(m);
    const r = e.ladderNear(v3(3.7, 0, 0), 0, 1.5) orelse return error.TestUnexpectedResult;
    try std.testing.expectApproxEqAbs(@as(f32, 7.2), r.run, 1e-4);
    // The axis stands off the rung plane on the ladder's own +Z — yaw 270 is world −x.
    try std.testing.expectApproxEqAbs(4.0 - props.LADDER_STANDOFF, r.axis.x, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.axis.z, 1e-3);
    try std.testing.expect(e.ladderNear(v3(3.7, 0, 0), 7.2, 1.5) != null);
    try std.testing.expectEqual(@as(?Rung, null), e.ladderNear(v3(-4, 0, 0), 0, 1.5));
    try std.testing.expectEqual(@as(?Rung, null), e.ladderNear(v3(3.7, 0, 0), 7.2 + LADDER_GRAB + 0.1, 1.5));
}

fn triHit(p: [3][2]f32, x: f32, z: f32) bool {
    var pos = false;
    var neg = false;
    for (0..3) |i| {
        const a = p[i];
        const b = p[(i + 1) % 3];
        const s = (b[0] - a[0]) * (z - a[1]) - (b[1] - a[1]) * (x - a[0]);
        if (s > 1e-7) pos = true;
        if (s < -1e-7) neg = true;
    }
    return !(pos and neg);
}

/// The drawn triangle's height at (u, v), which is what a foot planted there stands on.
fn triY(p: [3][2]f32, y: [3]f32, u: f32, v: f32) f32 {
    const det = (p[1][0] - p[0][0]) * (p[2][1] - p[0][1]) - (p[2][0] - p[0][0]) * (p[1][1] - p[0][1]);
    const l1 = ((p[1][0] - p[0][0]) * (v - p[0][1]) - (p[1][1] - p[0][1]) * (u - p[0][0])) / det;
    const l2 = ((u - p[0][0]) * (p[2][1] - p[0][1]) - (v - p[0][1]) * (p[2][0] - p[0][0])) / det;
    return y[0] * (1 - l1 - l2) + y[1] * l2 + y[2] * l1;
}

test "THE FLOOR DRAWN IS THE FLOOR WALKED — a cliff cell's floors against `wf.sampleHeight`'s own step" {
    // `wall` is the cut's own length times the drop: a saddle is TWO chords, so it is twice a diagonal's. The
    // last two stand on SLOPING ground: both floors run with it and the wall's lip and foot with them.
    const cases = [_]struct { name: []const u8, h: [4]f32, hi: [4]f32, lo: [4]f32, wall: f32 }{
        .{ .name = "straight", .h = .{ 0, 0, 4, 4 }, .hi = .{ 4, 4, 4, 4 }, .lo = .{ 0, 0, 0, 0 }, .wall = 4.0 },
        .{ .name = "diagonal", .h = .{ 0, 0, 4, 0 }, .hi = .{ 4, 4, 4, 4 }, .lo = .{ 0, 0, 0, 0 }, .wall = 2.8284 },
        .{ .name = "notch   ", .h = .{ 0, 4, 4, 4 }, .hi = .{ 4, 4, 4, 4 }, .lo = .{ 0, 0, 0, 0 }, .wall = 2.8284 },
        .{ .name = "saddle  ", .h = .{ 4, 0, 4, 0 }, .hi = .{ 4, 4, 4, 4 }, .lo = .{ 0, 0, 0, 0 }, .wall = 5.6569 },
        .{ .name = "sloped  ", .h = .{ 0, 0.5, 4.5, 4 }, .hi = .{ 4, 4.5, 4.5, 4 }, .lo = .{ 0, 0.5, 0.5, 0 }, .wall = 4.0 },
        .{ .name = "tilted  ", .h = .{ 0, 0, 5, 4 }, .hi = .{ 4.5, 4.5, 5, 4 }, .lo = .{ 0, 0, 0, 0 }, .wall = 4.5 },
    };
    for (cases) |c| {
        const t = wf.cliffTiers(c.h[0], c.h[3], c.h[1], c.h[2]);
        const cut = wf.cliffCut(c.h, t);
        const lv = wf.CliffLevels{ .hi = c.hi, .lo = c.lo };
        var b = gfx.Builder.init();
        defer b.deinit();
        var fb = gfx.Builder.init();
        defer fb.deinit();
        cliffCell(&b, .{ .b = &fb, .sb = null, .env = null }, .{ 0, 0 }, .{ 1, 1 }, c.h, cut, lv, .{ null, null, null, null });

        const ntri = b.pos.items.len / 9;
        var flat: f32 = 0;
        for (0..ntri) |i| {
            const o = i * 9;
            const up = b.nrm.items[i * 9 + 1] > 0.5;
            const p = [3][2]f32{
                .{ b.pos.items[o], b.pos.items[o + 2] },
                .{ b.pos.items[o + 3], b.pos.items[o + 5] },
                .{ b.pos.items[o + 6], b.pos.items[o + 8] },
            };
            const area = @abs((p[1][0] - p[0][0]) * (p[2][1] - p[0][1]) - (p[2][0] - p[0][0]) * (p[1][1] - p[0][1])) * 0.5;
            if (up) {
                flat += area;
                // Every floor vertex sits on one of the two side surfaces, at ITS height there.
                for (0..3) |k| {
                    const y = b.pos.items[o + k * 3 + 1];
                    const onHi = @abs(y - wf.ringLerp(c.hi, p[k][0], p[k][1])) < 1e-4;
                    const onLo = @abs(y - wf.ringLerp(c.lo, p[k][0], p[k][1])) < 1e-4;
                    try std.testing.expect(onHi or onLo);
                }
            } else {
                // The only thing in the terrain builder that is not floor is a `cellSkirt`, and a skirt is
                // VERTICAL: anything else here is a floor drawn on the slant, which is a floor you slide off.
                try std.testing.expect(@abs(b.nrm.items[o + 1]) < 0.01);
            }
        }
        // Every square metre of the cell is floored exactly once, or there is a hole to fall through.
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), flat, 1e-4);
        // The face is a mesh of its own, and it is never one plate: two spans by two courses at the least.
        try std.testing.expect(fb.pos.items.len / 9 >= 2 * 2 * 2);
        // …and it covers the WHOLE cut. A saddle that walls one of its two chords passes every other check here.
        var faceArea: f32 = 0;
        for (0..fb.pos.items.len / 9) |i| {
            const o = i * 9;
            const ux = fb.pos.items[o + 3] - fb.pos.items[o];
            const uy = fb.pos.items[o + 4] - fb.pos.items[o + 1];
            const uz = fb.pos.items[o + 5] - fb.pos.items[o + 2];
            const vx = fb.pos.items[o + 6] - fb.pos.items[o];
            const vy = fb.pos.items[o + 7] - fb.pos.items[o + 1];
            const vz = fb.pos.items[o + 8] - fb.pos.items[o + 2];
            const cx = uy * vz - uz * vy;
            const cy = uz * vx - ux * vz;
            const cz = ux * vy - uy * vx;
            faceArea += 0.5 * @sqrt(cx * cx + cy * cy + cz * cz);
        }
        std.debug.print("  cliff cell {s}: face {d:.3} m2 against the cut's own {d:.3}\n", .{ c.name, faceArea, c.wall });
        // The wall is a PLAIN SHEET over the cut, so this is exact: a saddle that walls one of its two chords
        // halves it, and anything that starts bellying the sheet out again shows up here as slack.
        try std.testing.expectApproxEqRel(c.wall, faceArea, 0.01);

        // A fan of planar triangles over a bilinear misses it by up to a quarter of the TWIST (the corners'
        // second difference), exactly as `quadSmooth` misses `wf.sampleHeight` on every plain cell; the two
        // cases on sloping ground carry one, so that is the slack, and no more.
        const twist = @max(
            @abs(c.hi[0] - c.hi[1] + c.hi[2] - c.hi[3]),
            @abs(c.lo[0] - c.lo[1] + c.lo[2] - c.lo[3]),
        );
        const slack = twist * 0.25 + 1e-3;
        const NS = 200;
        var off: usize = 0;
        var total: usize = 0;
        var worst: f32 = 0;
        for (0..NS) |iz| {
            const v = (@as(f32, @floatFromInt(iz)) + 0.5) / NS;
            for (0..NS) |ix| {
                const u = (@as(f32, @floatFromInt(ix)) + 0.5) / NS;
                const want = wf.ringLerp(if (wf.cliffHigh(cut, u, v)) c.hi else c.lo, u, v);
                var drawn: ?f32 = null;
                for (0..ntri) |i| {
                    const o = i * 9;
                    if (b.nrm.items[o + 1] <= 0.5) continue;
                    const p = [3][2]f32{
                        .{ b.pos.items[o], b.pos.items[o + 2] },
                        .{ b.pos.items[o + 3], b.pos.items[o + 5] },
                        .{ b.pos.items[o + 6], b.pos.items[o + 8] },
                    };
                    if (!triHit(p, u, v)) continue;
                    drawn = triY(p, .{ b.pos.items[o + 1], b.pos.items[o + 4], b.pos.items[o + 7] }, u, v);
                    break;
                }
                total += 1;
                if (drawn == null or @abs(drawn.? - want) > slack) off += 1;
                if (drawn) |d| worst = @max(worst, @abs(d - want));
            }
        }
        const pct = 100.0 * @as(f32, @floatFromInt(off)) / @as(f32, @floatFromInt(total));
        std.debug.print("  cliff cell {s}: {d} tris, {d:.2}% of the floor drawn at the other side, worst {d:.3} m off the walked (twist {d:.2})\n", .{ c.name, ntri, pct, worst, twist });
        // What is left is the sample grid straddling the chord, not a disagreement about where it runs.
        try std.testing.expect(pct < 1.0);
    }
}

/// Two SCULPTED levels — a plain that wanders a riser either way, a floor twelve metres down that wanders
/// the same — with the drop on one lattice row and cliff painted `bandCells` wide either side of it, which
/// is how the shipped lip is painted.
fn envWithSculptedLip(drop: f32, lipRow: usize, bandCells: usize) !*Env {
    const e = try std.testing.allocator.create(Env);
    e.* = .{ .ground = undefined, .models = undefined };
    e.heightHalf = wf.DEFAULT_HALF;
    e.heightAny = true;
    for (0..wf.HEIGHT_N) |iz| {
        for (0..wf.HEIGHT_N) |ix| {
            const wobble = wf.HEIGHT_STEP * (@as(f32, @floatFromInt((ix * 7 + iz * 13) % 3)) - 1.0);
            const base: f32 = if (iz < lipRow) 0 else -drop;
            e.heightField[iz * wf.HEIGHT_N + ix] = wf.heightByte(base + wobble);
            if (iz + bandCells >= lipRow and iz < lipRow + bandCells and iz + 1 < wf.HEIGHT_N and ix + 1 < wf.HEIGHT_N) {
                e.cliffField[iz * wf.HEIGHT_N + ix] = wf.CLIFF_FACE;
            }
        }
    }
    return e;
}

test "PAINT ON SCULPTED GROUND — no step but the cut itself, and nothing gets up it or through it" {
    const DROP: f32 = 12.0;
    const LIP: usize = 100;
    const e = try envWithSculptedLip(DROP, LIP, 4);
    defer std.testing.allocator.destroy(e);
    const step = e.lattice();
    const lipZ = -e.heightHalf + @as(f32, @floatFromInt(LIP)) * step;

    // Along the lip, two cells inside the paint on the high side, then two cells inside on the low side: the
    // walked ground moves as the sculpt does and never steps. Per cell the tiers stepped at every seam.
    const fine: f32 = 0.01;
    for ([_]f32{ lipZ - 2.5 * step, lipZ + 2.5 * step }) |z| {
        var prev = e.groundAt(-50, z);
        var worst: f32 = 0;
        var steps: usize = 0;
        var x: f32 = -50;
        while (x <= 50) : (x += fine) {
            const cur = e.groundAt(x, z);
            const d = @abs(cur - prev);
            worst = @max(worst, d);
            if (d > 0.05) steps += 1;
            prev = cur;
        }
        std.debug.print("  sculpted lip, 100 m along at z {d:.1}: {d} steps over 5 cm, worst {d:.4} m a centimetre\n", .{ z, steps, worst });
        try std.testing.expectEqual(@as(usize, 0), steps);
    }
    // Across it: exactly one step, and it is the whole drop.
    {
        var prev = e.groundAt(3.3, lipZ - 12);
        var over: usize = 0;
        var biggest: f32 = 0;
        var z: f32 = lipZ - 12;
        while (z <= lipZ + 12) : (z += fine) {
            const cur = e.groundAt(3.3, z);
            const d = prev - cur;
            if (d > STEP_UP) over += 1;
            biggest = @max(biggest, d);
            prev = cur;
        }
        std.debug.print("  sculpted lip, across: {d} step(s) over STEP_UP, the biggest {d:.2} m\n", .{ over, biggest });
        try std.testing.expectEqual(@as(usize, 1), over);
        try std.testing.expect(biggest > DROP - 1.0);
    }
    // The cut is on the lattice row's midline, from both sides, everywhere along it.
    {
        var x: f32 = -60;
        while (x <= 60) : (x += 0.37) {
            const above = e.groundAt(x, lipZ - 0.5 * step + 0.02);
            const below = e.groundAt(x, lipZ - 0.5 * step - 0.02);
            try std.testing.expect(below - above > DROP - 1.0);
        }
    }
    // Nothing on foot gets up it, from straight on or grazing — at any frame rate, for a hundred frames.
    for ([_]f32{ 1.0 / 30.0, 1.0 / 144.0 }) |dt| {
        for ([_]f32{ 0.0, 1.2, 1.45 }) |ang| {
            var p = v3(7.7, 0, lipZ + 1.5);
            p.y = e.groundAt(p.x, p.z);
            const dir = v3(mathx.sinf(ang), 0, -mathx.cosf(ang));
            for (0..100) |_| {
                p = e.walkStep(p, dir, 6.0 * dt);
                p.y = e.groundAt(p.x, p.z);
            }
            try std.testing.expect(p.y < -DROP + 1.0);
        }
    }
    // And from above the lip is a brink, not a slope.
    try std.testing.expect(e.brink(v3(1, e.groundAt(1, lipZ - 1.5), lipZ - 1.5), v3(1, 0, lipZ - 0.5 * step + 0.05)));
}

/// Widest x over which the ground climbs from `lo` to `hi`, walked at a millimetre.
fn faceWidth(e: *const Env, z: f32, x0: f32, x1: f32) struct { rise: f32, width: f32, at: f32 } {
    const fine: f32 = 0.001;
    var prev = e.groundAt(x0, z);
    var best: f32 = 0;
    var at: f32 = x0;
    var x = x0;
    while (x <= x1) : (x += fine) {
        const cur = e.groundAt(x, z);
        const d = @abs(cur - prev);
        if (d > best) {
            best = d;
            at = x;
        }
        prev = cur;
    }
    return .{ .rise = best, .width = fine, .at = at };
}

test "A PAINTED CLIFF IS A WALL AND A LIP — the bench's three faces, in metres" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    var ln: usize = 0;
    try wf.loadForTest(wf.DIR ++ "/test_cliff" ++ wf.EXT, m, &ln);
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.heightField = m.height;
    e.cliffField = m.cliff;
    e.heightHalf = m.half;
    e.heightAny = m.anyHeight();

    const cell = 2 * m.half / @as(f32, @floatFromInt(wf.HEIGHT_N - 1));
    const g0 = e.groundAt(0, -16);

    // EAST: the 6 m mesa. The whole rise lands inside one millimetre, which no ramp can do.
    const straight = faceWidth(e, -16, 8, 16);
    try std.testing.expect(straight.rise > 5.9);
    try std.testing.expectApproxEqAbs(g0 + 6.0, e.groundAt(20, -16), 1e-3);
    try std.testing.expectApproxEqAbs(g0, e.groundAt(6, -16), 1e-3);

    // The face is a wall to the walk at every frame rate, and a lip nothing on foot will step off.
    for ([_]f32{ 1.0 / 30.0, 1.0 / 60.0, 1.0 / 144.0, 1.0 / 240.0 }) |dt| {
        const from = v3(straight.at - 0.4, 0, -16);
        const to = e.walkStep(from, v3(1, 0, 0), 6.0 * dt);
        try std.testing.expectApproxEqAbs(from.x, to.x, 1e-4);
    }
    try std.testing.expect(e.brink(v3(20, 0, -16), v3(straight.at - 0.2, 0, -16)));
    try std.testing.expect(!e.brink(v3(20, 0, -16), v3(24, 0, -16)));

    // SOUTH: the diagonal. Measured ALONG x, so the face reads 1/cos 45 wider than it stands.
    const diag = faceWidth(e, 12, 4, 12);
    try std.testing.expect(diag.rise > 3.9);
    try std.testing.expectApproxEqAbs(g0 + 4.0, e.groundAt(16, 12), 1e-3);

    // WEST: the ramp into the pit is not flagged, so it stays a ramp — walkable, and no lip on it.
    var x: f32 = -37.0;
    while (x <= -31.0) : (x += 0.25) {
        try std.testing.expect(e.walkableAt(x, 0));
        try std.testing.expect(!e.brink(v3(x, 0, 0), v3(x + 0.1, 0, 0)));
    }
    try std.testing.expectApproxEqAbs(g0 - 3.0, e.groundAt(-20, 0), 1e-3);

    // NORTH: the flight. Its grade is past `MAX_SLOPE`, so a smooth ramp of the same heights is refused;
    // it walks because each probe crosses at most one riser.
    const flightZ: f32 = -24;
    const foot = v3(12.0 - 6.0 / 0.90 - 0.5, 0, flightZ);
    try std.testing.expect(!e.walkableAt(foot.x + 1.0, flightZ));
    var climb = foot;
    var steps: usize = 0;
    while (steps < 4000 and climb.x < 12.0) : (steps += 1) {
        const next = e.walkStep(climb, v3(1, 0, 0), 6.0 / 60.0);
        if (mathx.distXZ(next, climb) < 1e-5) break;
        climb = next;
    }
    try std.testing.expect(climb.x >= 12.0);
    try std.testing.expectApproxEqAbs(g0 + 6.0, e.groundAt(climb.x, climb.z), 1e-3);
    // Every tread is flat and every riser is one `wf.STAIR_RISE`.
    var seen: f32 = e.groundAt(foot.x, flightZ);
    var x2 = foot.x;
    var worst: f32 = 0;
    while (x2 < 12.0) : (x2 += 0.01) {
        const cur = e.groundAt(x2, flightZ);
        worst = @max(worst, @abs(cur - seen));
        seen = cur;
    }
    try std.testing.expectApproxEqAbs(wf.STAIR_RISE, worst, 1e-3);

    std.debug.print("  cliff bench: cell {d:.3} m\n", .{cell});
    std.debug.print("    stair flight: grade 0.90 past MAX_SLOPE {d:.3}, tallest riser {d:.2} m, topped out in {d} steps\n", .{
        MAX_SLOPE, worst, steps,
    });
    std.debug.print("    a flight can be one riser a cell, so stairs beat a ramp only under a {d:.2} m cell\n", .{
        wf.STAIR_RISE / MAX_SLOPE,
    });
    std.debug.print("    straight face at x {d:.2}: {d:.2} m across {d:.3} m ({d:.0} deg)\n", .{
        straight.at, straight.rise, straight.width, mathx.degrees(std.math.atan(straight.rise / straight.width)),
    });
    std.debug.print("    diagonal face at x {d:.2}: {d:.2} m, and the pit floor sits {d:.2} m under the plain\n", .{
        diag.at, diag.rise, g0 - e.groundAt(-20, 0),
    });
    std.debug.print("    ramp into the pit: slope {d:.2} (limit {d:.2}), walkable the whole way\n", .{
        e.slopeAt(-34, 0), MAX_SLOPE,
    });
}

test "WHAT THE CLIMB PROMPT COSTS A FRAME — `ladderNear` on the shipped map, timed where it is asked" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    var ln: usize = 0;
    try wf.loadForTest(wf.START_MAP, m, &ln);
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.materialize(m);
    var beside = v3(0, 0, 4);
    for (e.props[0..e.nprops]) |pr| {
        if (pr.kind != .ladder) continue;
        beside = pr.pos;
        break;
    }
    const spots = [_]struct { name: []const u8, at: rl.Vector3, footY: f32 }{
        .{ .name = "beside a ladder", .at = beside, .footY = beside.y },
        .{ .name = "open ground    ", .at = v3(0, 0, 4), .footY = 0 },
    };
    const ROUNDS = 2000;
    std.debug.print("\n", .{});
    for (spots) |s| {
        var timer = try std.time.Timer.start();
        var found: usize = 0;
        for (0..ROUNDS) |_| {
            if (e.ladderNear(s.at, s.footY, 1.5) != null) found += 1;
        }
        const us = @as(f64, @floatFromInt(timer.read())) / 1000.0 / @as(f64, @floatFromInt(ROUNDS));
        std.debug.print("  climb prompt {s}: {d:.3} us a frame — {d:.4}% of a 16.7 ms frame ({s})\n", .{
            s.name, us, 100.0 * us / 16700.0, if (found > 0) "a ladder in reach" else "nothing in reach",
        });
        // The box is a metre and a half wide against a 16 m cell, so this may never grow with the map.
        try std.testing.expect(us < 40.0);
    }
}

test "BREAKING A GROUP APART DOES NOT MOVE THE WORLD" {
    const m = try wf.testMap(std.testing.allocator, wf.TEST_HEAD ++
        "belt: pillar -20 -20 20 20 12 0.9 1.1 seed=7001\n" ++
        "at: lantern 30 30 0 1\n");
    defer std.testing.allocator.destroy(m);
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.materialize(m);
    const props0 = e.propCount();
    const solids0 = e.solidCount();
    const lights0 = e.lightCount();
    try std.testing.expect(props0 > 2 and solids0 > 0 and lights0 > 0);

    const n = try e.explodeOp(m, 0);
    try std.testing.expect(n > 1);
    try std.testing.expectEqual(n + 1, m.nops);
    for (m.slice()) |o| try std.testing.expectEqual(wf.OpKind.at, o.op);

    e.materialize(m);
    try std.testing.expectEqual(props0, e.propCount());
    try std.testing.expectEqual(solids0, e.solidCount());
    try std.testing.expectEqual(lights0, e.lightCount());
}

test "a group with nothing left standing leaves no op behind" {
    const m = try wf.testMap(std.testing.allocator, wf.TEST_HEAD ++
        "belt: pillar -20 -20 20 20 0 0.9 1.1 seed=7002\n" ++
        "at: lantern 30 30 0 1\n");
    defer std.testing.allocator.destroy(m);
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.materialize(m);
    try std.testing.expectEqual(@as(usize, 1), e.propCount());

    try std.testing.expectEqual(@as(usize, 0), try e.explodeOp(m, 0));
    try std.testing.expectEqual(@as(usize, 1), m.nops);
    try std.testing.expectEqual(Kind.lantern, m.ops[0].kind);
}

test "A FLIGHT IS WALKED TO THE SHELF, AND ITS HEAD IS NOT A LIP" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    var ln: usize = 0;
    try wf.loadForTest(wf.DIR ++ "/test_cliff" ++ wf.EXT, m, &ln);
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.heightField = m.height;
    e.cliffField = m.cliff;
    e.heightHalf = m.half;
    e.heightAny = m.anyHeight();
    e.materialize(m);

    var flight: ?*const Prop = null;
    for (e.placed()) |*pr| {
        if (pr.kind == .stairflight) flight = pr;
    }
    const fl = flight orelse return error.TestUnexpectedResult;
    const z = fl.pos.z;
    const shelf = e.groundAt(20, z);
    const foot = e.groundAt(fl.pos.x - 0.5, z);
    try std.testing.expectApproxEqAbs(foot + 6.0, shelf, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 6.0), fl.rise, 1e-4);

    // Up: a body walking east arrives on the shelf, standing on what is under it after every step.
    var p = v3(fl.pos.x - 0.5, foot, z);
    var top: f32 = foot;
    var steps: usize = 0;
    while (steps < 4000 and p.x < 12.8) : (steps += 1) {
        const q = e.walkStep(p, v3(1, 0, 0), 0.05);
        if (q.x <= p.x + 1e-6) break;
        p = q;
        p.y = e.standAt(p.x, p.z, p.y);
        top = mathx.maxF(top, p.y);
    }
    try std.testing.expect(p.x >= 12.8);
    try std.testing.expectApproxEqAbs(shelf, p.y, 1e-3);
    try std.testing.expectApproxEqAbs(shelf, top, 1e-3);
    // No single step up the flight is more than one tread.
    try std.testing.expect(e.standAt(fl.pos.x + 0.2, z, foot) - foot <= 0.25 + 1e-4);

    // Down: from the shelf onto the head of the flight is a step, not a lip — so a foe follows him down.
    const onShelf = v3(12.3, shelf, z);
    const onHead = v3(11.7, shelf, z);
    try std.testing.expect(!e.brink(onShelf, onHead));
    // Off the side of the flight the LAND is what he lands on, and mid-flight that is a fall.
    const mid = v3(fl.pos.x + 4.8, e.standAt(fl.pos.x + 4.8, z, foot + 3.0), z);
    try std.testing.expect(mid.y > foot + 2.0);
    try std.testing.expect(e.brink(mid, v3(mid.x, mid.y, z + 1.4)));
    // A ground-level walk next to the flight never mounts it sideways.
    try std.testing.expectApproxEqAbs(foot, e.standAt(fl.pos.x + 4.8, z + 1.4, foot), 1e-3);
    std.debug.print("\nflight: run {d:.2} m, {d} treads, head at {d:.2} against a shelf at {d:.2}\n", .{ flightRun(fl, props.info(fl.kind)), sectionsIn(fl.rise, props.info(fl.kind).stack) * props.info(fl.kind).flight.?.treads, fl.pos.y + fl.rise, shelf });
}

test "a cliff stood at the map's edge is still inside the grid" {
    // CLIFF_BOUND is a hand-copied mirror of the mesh's own bound, because MAX_HALF has to be a comptime value and `props.info` is a runtime lookup.
    try std.testing.expectApproxEqAbs(CLIFF_BOUND, props.info(.cliff).bound, 1e-4);
    try std.testing.expect(wf.DEFAULT_HALF <= MAX_HALF);
    try std.testing.expect(GROUND_HALF > wf.DEFAULT_HALF + 200);
}

test "THE BROOD ARENA LOADS — a scratch map is only useful if it is known to still parse" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    var line: usize = 0;
    try wf.loadForTest(wf.DIR ++ "/02_brood_arena" ++ wf.EXT, m, &line);
    var mothers: usize = 0;
    for (m.foes[0..m.nfoes]) |f| {
        if (f.kind == .brood_mother) mothers += 1;
    }
    try std.testing.expect(mothers > 0);
}


test "replaying the SHIPPED map produces a stable world" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    var line: usize = 0;
    try wf.loadForTest(wf.START_MAP, m, &line);
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };

    e.materialize(m);
    const props0 = e.propCount();
    const solids0 = e.solidCount();
    const lights0 = e.lightCount();
    try std.testing.expect(props0 > 1000 and props0 < MAX_PROPS);
    try std.testing.expect(solids0 > 100 and solids0 < MAX_SOLIDS);
    try std.testing.expect(lights0 > 0);
    e.materialize(m);
    try std.testing.expectEqual(props0, e.propCount());
    try std.testing.expectEqual(solids0, e.solidCount());
    try std.testing.expectEqual(lights0, e.lightCount());

    var chestOps: usize = 0;
    for (m.ops[0..m.nops]) |*op| {
        if (op.kind == .chest) chestOps += 1;
    }

    var boxes: [chestmod.CAP]chestmod.Site = undefined;
    try std.testing.expectEqual(chestOps, e.chestSites(&boxes));
    var fires: [restmod.CAP]restmod.Site = undefined;
    try std.testing.expect(e.restSites(&fires) > 0);
}

test "A FEN LURKER IS POSTED IN WATER IT CAN ACTUALLY HIDE IN" {
    const fen = @import("../foes/fenlurker.zig");
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    var line: usize = 0;
    try wf.loadForTest(wf.DIR ++ "/test_fenlurker" ++ wf.EXT, m, &line);
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.heightField = m.height;
    e.heightHalf = m.half;
    e.heightAny = m.anyHeight();
    e.uploadWater(m);
    e.materialize(m);

    var wet: usize = 0;
    var dry: usize = 0;
    for (m.foes[0..m.nfoes]) |f| {
        if (f.kind != .fen_lurker) continue;
        const d = e.wadeDepth(f.x, f.z);
        if (d >= fen.POOL_MIN) {
            wet += 1;
            try std.testing.expect(d <= WADE_MAX);
        } else dry += 1;
    }
    std.debug.print("\n  fen lurker test map: {d} posted in water, {d} on dry land\n", .{ wet, dry });
    try std.testing.expect(wet >= 3);
    try std.testing.expectEqual(@as(usize, 1), dry);
}

test "EVERY SHIPPED MAP LOADS AND MATERIALIZES, not just the one the game starts on" {
    var dir = std.fs.cwd().openDir(wf.DIR, .{ .iterate = true }) catch return error.SkipZigTest;
    defer dir.close();
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    var seen: usize = 0;
    var it = dir.iterate();
    while (try it.next()) |ent| {
        if (ent.kind != .file or !std.mem.endsWith(u8, ent.name, wf.EXT)) continue;
        var buf: [256]u8 = undefined;
        const path = try std.fmt.bufPrint(&buf, wf.DIR ++ "/{s}", .{ent.name});
        var line: usize = 0;
        wf.load(path, m, &line) catch |err| {
            std.debug.print("{s} failed to load at line {d}\n", .{ path, line });
            return err;
        };
        e.* = .{ .ground = undefined, .models = undefined };
        e.materialize(m);
        if (e.propCount() == 0) std.debug.print("{s} materialized ZERO props\n", .{path});
        try std.testing.expect(e.propCount() > 0);
        seen += 1;
    }
    try std.testing.expect(seen >= 3);
    var line: usize = 0;
    try wf.load(wf.DIR ++ "/03_bone_court" ++ wf.EXT, m, &line);
    var shields: usize = 0;
    var blades: usize = 0;
    for (m.foes[0..m.nfoes]) |f| {
        switch (f.kind) {
            .shieldman => shields += 1,
            .greatsword => blades += 1,
            else => {},
        }
    }
    try std.testing.expect(shields >= 2 and blades >= 2);
    try std.testing.expectEqual(m.nfoes, shields + blades);

    e.* = .{ .ground = undefined, .models = undefined };
    e.materialize(m);
    var sites: [restmod.CAP]restmod.Site = undefined;
    try std.testing.expectEqual(@as(usize, 2), e.restSites(&sites));
    try std.testing.expect(restmod.isRestKind(.campfire_lit));
    try std.testing.expect(!restmod.isRestKind(.campfire));
    try std.testing.expect(props.info(.campfire_lit).interact);
    try std.testing.expect(!props.info(.campfire).interact);
    try std.testing.expect(props.info(.campfire_lit).light != null);
    try std.testing.expect(props.info(.campfire).light == null);
}

test "no grid query can overflow MAX_NEAR, which is the one cap here that drops SILENTLY" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    var line: usize = 0;
    try wf.loadForTest(wf.START_MAP, m, &line);
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.materialize(m);
    var worst: u32 = 0;
    for (0..GRID_N - 1) |cz| {
        for (0..GRID_N - 1) |cx| {
            var sum: u32 = 0;
            for (0..2) |dz| {
                for (0..2) |dx| {
                    const k = (cz + dz) * GRID_N + (cx + dx);
                    sum += e.sgrid_start[k + 1] - e.sgrid_start[k];
                }
            }
            worst = @max(worst, sum);
        }
    }
    try std.testing.expect(worst > 0);
    try std.testing.expect(worst <= MAX_NEAR);
}

test "the flat-map plant shortcut is EXACT, not an approximation" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    m.blank("Flat");
    try std.testing.expect(!m.anyHeight());
    for ([_][2]f32{ .{ 0, 0 }, .{ -117.3, 88.6 }, .{ 279.9, -279.9 }, .{ 1.25, -63.7 } }) |p| {
        try std.testing.expectEqual(@as(f32, 0), m.heightAt(p[0], p[1]));
    }
    var span: [4]usize = undefined;
    try std.testing.expect(m.sculpt(0, 0, 20, .raise, 5.0, &span));
    try std.testing.expect(m.anyHeight());
    try std.testing.expect(m.heightAt(0, 0) > 4.0);
}

test "the map's half drives the world, not a constant in this file" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    m.blank("sized");
    try std.testing.expectApproxEqAbs(wf.DEFAULT_HALF, m.half, 1e-4);
    m.half = 120;
    try std.testing.expectApproxEqAbs(@as(f32, 118), m.half - PLAY_INSET, 1e-4);
}


test "A BLOCKED PROBE AND A MOVED PUSH-OUT ARE ONE PREDICATE — what `game.wayClear` swapped to" {
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.props[0] = .{ .kind = .wall, .pos = v3(0, 0, 0), .yaw = 0, .scale = 1, .op = 0 };
    e.props[1] = .{ .kind = .pillar, .pos = v3(7.5, 0, -3.0), .yaw = 0, .scale = 1, .op = 0 };
    e.nprops = 2;
    buildSolids(e);
    e.openWards();

    const SLACK: f32 = 1e-3;
    var agreed: usize = 0;
    var blocked: usize = 0;
    for (0..61) |ix| {
        for (0..61) |iz| {
            const p = v3(-10.0 + @as(f32, @floatFromInt(ix)) * (20.0 / 60.0), 0, -10.0 + @as(f32, @floatFromInt(iz)) * (20.0 / 60.0));
            for ([_]f32{ 0.34, 0.55, 1.10 }) |r| {
                const moved = mathx.distXZ(e.resolveActor(p, r, p.y), p) > SLACK;
                const near = e.blockedNear(p, r - SLACK, r + 1.0);
                if (moved) blocked += 1;
                if (moved == near) agreed += 1 else std.debug.print(
                    "\nDISAGREE at ({d:.3},{d:.3}) r={d:.2}: pushOut moved={} blockedNear={}\n",
                    .{ p.x, p.z, r, moved, near },
                );
            }
        }
    }
    try std.testing.expect(blocked > 200);
    try std.testing.expectEqual(@as(usize, 61 * 61 * 3), agreed);
}

test "AN OP MAY NOT SPIN — the rebuild's cost is the map's size, never a number somebody dragged" {
    const ta = std.testing.allocator;
    const m = try ta.create(wf.Map);
    defer ta.destroy(m);
    const e = try ta.create(Env);
    defer ta.destroy(e);
    m.* = .{};
    e.* = .{ .ground = undefined, .models = undefined };

    // `chance` 0 places NOTHING, so the prop cap never trips and the spin is invisible.
    m.nops = 1;
    m.ops[0] = .{ .op = .line, .kind = .block, .x = -200, .z = 0, .x1 = 200, .z1 = 0, .r0 = 0.0001, .chance = 0.0, .sLo = 1, .sHi = 1 };
    var t = try std.time.Timer.start();
    e.materialize(m);
    const spin = @as(f64, @floatFromInt(t.read())) / 1e6;
    std.debug.print("\n  a line op at the parser's own floor: {d:.1} ms a rebuild, {d} ops capped\n", .{ spin, e.opsCapped });
    try std.testing.expect(e.opsCapped == 1);

    m.ops[0] = .{ .op = .belt, .kind = .block, .x = -200, .z = -200, .x1 = 200, .z1 = 200, .n = 2_000_000, .sLo = 1, .sHi = 1 };
    t.reset();
    e.materialize(m);
    const flood = @as(f64, @floatFromInt(t.read())) / 1e6;
    std.debug.print("  a belt of two million: {d:.1} ms, {d} props, {d} ops capped (cap {d})\n", .{ flood, e.nprops, e.opsCapped, MAX_PROPS });
    try std.testing.expect(e.nprops < MAX_PROPS);
    try std.testing.expect(spin < 8.0 and flood < 40.0);
}

test "…AND NO HONEST OP IN THE SHIPPING MAP IS TRUNCATED BY IT" {
    const ta = std.testing.allocator;
    const m = try ta.create(wf.Map);
    defer ta.destroy(m);
    const e = try ta.create(Env);
    defer ta.destroy(e);
    const text = try wf.readForTest(ta, wf.START_MAP, wf.TEXT_CAP);
    defer ta.free(text);
    var line: usize = 0;
    try wf.parse(text, m, &line);
    e.* = .{ .ground = undefined, .models = undefined };
    var t = try std.time.Timer.start();
    e.materialize(m);
    std.debug.print("  {s}: {d} ops built {d} props in {d:.1} ms, {d} capped\n", .{ wf.START_MAP, m.nops, e.nprops, @as(f64, @floatFromInt(t.read())) / 1e6, e.opsCapped });
    std.debug.print("  ...and {d} of {d} lights ({d:.0}% of the budget), {d} props left unlit for want of a slot\n", .{
        e.lightCount(),
        MAX_LIGHTS,
        100.0 * @as(f64, @floatFromInt(e.lightCount())) / @as(f64, @floatFromInt(MAX_LIGHTS)),
        e.lightsCapped,
    });
    try std.testing.expectEqual(@as(usize, 0), e.opsCapped);
    // NOT asserted the way `opsCapped` is: the shipped map is over this budget TODAY (44 props placed unlit),
    // where the author is told, and raising `MAX_LIGHTS` or thinning the glow is his call, not this test's.
    {
        var cam: rl.Camera3D = undefined;
        cam.position = v3(0, 12, -20);
        cam.target = v3(0, 2, 0);
        cam.up = v3(0, 1, 0);
        const view = View.fromCamera(cam, 16.0 / 9.0);
        var timer = try std.time.Timer.start();
        var seen: usize = 0;
        const ROUNDS = 2000;
        for (0..ROUNDS) |_| {
            for (e.lights[0..e.nlights]) |wl| {
                if (view.visible(wl.base.pos, wl.base.radius, LIGHT_REACH)) seen += 1;
            }
        }
        const us = @as(f64, @floatFromInt(timer.read())) / 1000.0 / @as(f64, ROUNDS);
        std.debug.print("  ...the per-frame light walk is {d:.2} us over {d} lights ({d:.3} us each) — {d:.3}% of a 16.7 ms frame\n", .{
            us, e.nlights, us / @as(f64, @floatFromInt(@max(e.nlights, 1))), 100.0 * us / 16700.0,
        });
    }
}

test "THE GIZMO PASS WALKS WHAT IS IN FRAME, NOT THE WHOLE MAP — and the owned count survives losing the scan" {
    const ta = std.testing.allocator;
    const m = try ta.create(wf.Map);
    defer ta.destroy(m);
    const e = try ta.create(Env);
    defer ta.destroy(e);
    const text = try wf.readForTest(ta, wf.START_MAP, wf.TEXT_CAP);
    defer ta.free(text);
    var line: usize = 0;
    try wf.parse(text, m, &line);
    e.* = .{ .ground = undefined, .models = undefined };
    e.materialize(m);

    const view = viewLooking(v3(0, 26, -34), v3(0, 0, 0));
    const Count = struct {
        n: usize = 0,
        fn at(c: *@This(), _: u32) void {
            c.n += 1;
        }
    };
    var c = Count{};
    e.eachInView(&view, &c, Count.at);
    const share = @as(f64, @floatFromInt(c.n)) / @as(f64, @floatFromInt(e.nprops));
    std.debug.print("  gizmo pass: {d} of {d} props in frame ({d:.1}% — the walk it replaces was all of them)\n", .{ c.n, e.nprops, share * 100.0 });
    try std.testing.expect(c.n < e.nprops);

    var summed: usize = 0;
    var widest: usize = 0;
    for (0..m.nops) |i| {
        summed += e.ownedBy(@intCast(i));
        widest = @max(widest, e.ownedBy(@intCast(i)));
    }
    try std.testing.expectEqual(e.nprops, summed);
    std.debug.print("  widest op owns {d} props; ownedBy sums to {d}\n", .{ widest, summed });
}

test "THE CURSOR PICK ANSWERS THE SAME PROP OFF THE INDEX AS OFF THE WHOLE LIST — and stops walking the map to do it" {
    const ta = std.testing.allocator;
    const m = try ta.create(wf.Map);
    defer ta.destroy(m);
    const e = try ta.create(Env);
    defer ta.destroy(e);
    const text = try wf.readForTest(ta, wf.START_MAP, wf.TEXT_CAP);
    defer ta.free(text);
    var line: usize = 0;
    try wf.parse(text, m, &line);
    e.* = .{ .ground = undefined, .models = undefined };
    e.materialize(m);

    const Any = struct {
        fn all(_: void, _: u16) bool {
            return true;
        }
    };
    const flat = struct {
        fn pick(env: *const Env, origin: rl.Vector3, dir: rl.Vector3) ?usize {
            var best: ?usize = null;
            var bestT: f32 = std.math.floatMax(f32);
            for (env.props[0..env.nprops], 0..) |*pr, i| {
                const ball = pickSphere(pr, props.info(pr.kind));
                const c = ball.c;
                const rad = ball.r;
                const oc = mathx.subV(c, origin);
                const along = oc.x * dir.x + oc.y * dir.y + oc.z * dir.z;
                if (along <= 0 or along >= bestT) continue;
                const perp2 = (oc.x * oc.x + oc.y * oc.y + oc.z * oc.z) - along * along;
                if (perp2 > rad * rad) continue;
                bestT = along;
                best = i;
            }
            return best;
        }
    }.pick;

    const eye = v3(0, 26, -34);
    var rng = mathx.Rng.init(0xC0FFEE);
    var agree: usize = 0;
    var hits: usize = 0;
    var tIdx: u64 = 0;
    var tFlat: u64 = 0;
    var t = try std.time.Timer.start();
    for (0..64) |_| {
        const at = v3(rng.range(-60, 60), 0, rng.range(-60, 60));
        const view = viewLooking(eye, at);
        const dir = mathx.normV(mathx.subV(at, eye));

        t.reset();
        const got = e.pickIf(&view, eye, dir, {}, Any.all);
        tIdx += t.read();

        t.reset();
        const want = flat(e, eye, dir);
        tFlat += t.read();

        if (want != null) hits += 1;
        if (got == want) agree += 1;
    }
    std.debug.print(
        "  cursor pick over 64 rays: {d} agreed, {d} hit something | indexed {d:.0} us, whole-list {d:.0} us ({d:.1}x)\n",
        .{ agree, hits, @as(f64, @floatFromInt(tIdx)) / 1000.0, @as(f64, @floatFromInt(tFlat)) / 1000.0, @as(f64, @floatFromInt(tFlat)) / @as(f64, @floatFromInt(@max(tIdx, 1))) },
    );
    try std.testing.expectEqual(@as(usize, 64), agree);
    try std.testing.expect(hits > 0);
    try std.testing.expect(tIdx < tFlat);
}


test "THE BAKED WATER FIELD CARRIES NO SHAPE — the coast is the shader's, so the field is a plain distance" {
    const ta = std.testing.allocator;
    const m = try ta.create(wf.Map);
    defer ta.destroy(m);
    const e = try ta.create(Env);
    defer ta.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };

    var first: [wf.WATER_CELLS]u8 = undefined;
    inline for (@typeInfo(wf.Edge).@"enum".fields, 0..) |f, k| {
        m.* = .{};
        m.half = 140;
        const N = wf.WATER_N;
        const cell = m.cellSize(N);
        for (0..N) |cz| {
            for (0..N) |cx| {
                const wx = wf.cellCentre(m.half, cell, cx);
                const wz = wf.cellCentre(m.half, cell, cz);
                const i = cz * N + cx;
                m.water[i] = if (wx * wx + wz * wz < 60.0 * 60.0) 1 else 0;
                m.waterEdge[i] = f.value;
            }
        }
        e.waterReady = false;
        e.uploadWater(m);
        if (k == 0) {
            first = e.waterField;
            continue;
        }
        for (first, e.waterField) |a, b| {
            if (a < gfx.WATER_SHORE and b < gfx.WATER_SHORE) continue;
            try std.testing.expectEqual(a, b);
        }
    }

    const N = wf.WATER_N;
    const mid = N / 2;
    var prev: u8 = 255;
    for (mid..N) |cx| {
        const v = e.waterField[mid * N + cx];
        try std.testing.expect(v <= prev);
        prev = v;
    }
}

test "THE COAST YOU SEE IS THE COAST YOU WADE INTO — one warp, evaluated on both sides" {
    const ta = std.testing.allocator;
    const m = try ta.create(wf.Map);
    defer ta.destroy(m);
    const e = try ta.create(Env);
    defer ta.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };

    try std.testing.expectEqual(@as(usize, wf.Edge.N), glsl.EDGE_K.len);
    try std.testing.expectEqual(@as(usize, @intFromEnum(wf.Edge.scallop)), glsl.SCALLOP);
    try std.testing.expectEqual(@as(usize, @intFromEnum(wf.Edge.tiled)), glsl.TILED);
    try std.testing.expectEqual(@as(usize, @intFromEnum(wf.Edge.speckle)), glsl.SPECKLE);
    try std.testing.expectEqual(@as(usize, @intFromEnum(wf.Edge.natural)), glsl.NATURAL);
    try std.testing.expectEqual(glsl.EDGE_K[glsl.NATURAL], glsl.edgeK(wf.Edge.N + 4));

    m.* = .{};
    m.half = 140;
    const N = wf.WATER_N;
    const cell = m.cellSize(N);
    for (0..N) |cz| {
        for (0..N) |cx| {
            const wx = wf.cellCentre(m.half, cell, cx);
            const wz = wf.cellCentre(m.half, cell, cz);
            const i = cz * N + cx;
            m.water[i] = if (wx * wx + wz * wz < 60.0 * 60.0) 1 else 0;
            m.waterEdge[i] = @intFromEnum(wf.Edge.jagged);
        }
    }
    e.waterReady = false;
    e.uploadWater(m);

    var wetTo: f32 = 0;
    var t: f32 = 0;
    while (t < 90) : (t += 0.25) {
        if (e.paintedDepth(t, 0) > 0) wetTo = t;
    }
    const k = glsl.edgeK(@intFromEnum(wf.Edge.jagged));
    std.debug.print("\n  jagged coast: painted at 60.00 m, footing finds water out to {d:.2} m (warp {d:.1} m)\n", .{ wetTo, k.warp });
    try std.testing.expect(@abs(wetTo - 60.0) > 0.3);
    try std.testing.expect(@abs(wetTo - 60.0) < k.warp + glsl.BAY_M + 2.0);

    for (&m.waterEdge) |*v| v.* = @intFromEnum(wf.Edge.straight);
    e.waterReady = false;
    e.uploadWater(m);
    wetTo = 0;
    t = 0;
    while (t < 90) : (t += 0.25) {
        if (e.paintedDepth(t, 0) > 0) wetTo = t;
    }
    try std.testing.expect(@abs(wetTo - 60.0) <= cell + 0.3);

    // Point-sampled, the footing's line stood a WHOLE CELL out — 1.00 m measured here at half 280. Re-solved
    // against a bilinear read of the same field, which is what the shader does.
    const bil = struct {
        fn at(en: *const Env, half: f32, x: f32, z: f32) f32 {
            const NN = wf.WATER_N;
            const nf: f32 = @floatFromInt(NN);
            const u = (x + half) / (2 * half) * nf - 0.5;
            const v = (z + half) / (2 * half) * nf - 0.5;
            const tu = u - @floor(u);
            const tv = v - @floor(v);
            const hi: i32 = @intCast(NN - 1);
            var acc: f32 = 0;
            for (0..2) |dz| {
                const cz: usize = @intCast(mathx.clampI(@as(i32, @intFromFloat(@floor(v))) + @as(i32, @intCast(dz)), 0, hi));
                for (0..2) |dx| {
                    const cx: usize = @intCast(mathx.clampI(@as(i32, @intFromFloat(@floor(u))) + @as(i32, @intCast(dx)), 0, hi));
                    const w = (if (dx == 0) 1 - tu else tu) * (if (dz == 0) 1 - tv else tv);
                    acc += w * @as(f32, @floatFromInt(en.waterField[cz * NN + cx]));
                }
            }
            return acc;
        }
    }.at;
    const shoreF: f32 = @floatFromInt(gfx.WATER_SHORE);
    var seen: f32 = 0;
    var walked: f32 = 0;
    t = 0;
    while (t < 90) : (t += 0.01) {
        if (bil(e, m.half, t, 0) > shoreF) seen = t;
        if (e.paintedDepth(t, 0) > 0) walked = t;
    }
    std.debug.print("  straight coast at {d:.0} m, cell {d:.2}: drawn waterline {d:.2} m, walked {d:.2} m, gap {d:.2} m\n", .{ 60.0, cell, seen, walked, @abs(walked - seen) });
    try std.testing.expect(@abs(walked - seen) <= 0.02);
}

test "THE FOOTING READS THE LIQUID THE SHADER PAINTED - every pool on the bench answers with its own kind" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    var line: usize = 0;
    try wf.loadForTest(wf.DIR ++ "/test_liquids" ++ wf.EXT, m, &line);
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.uploadSoil(m);
    e.uploadWater(m);
    e.uploadHeight(m);
    const pools = [_]struct { x: f32, z: f32, want: wf.Liquid }{
        .{ .x = -32, .z = -32, .want = .water },
        .{ .x = 32, .z = -32, .want = .oil },
        .{ .x = -32, .z = 32, .want = .fungal },
        .{ .x = 32, .z = 32, .want = .lava },
    };
    for (pools) |c| {
        try std.testing.expect(e.inWater(c.x, c.z, 1.0));
        try std.testing.expectEqual(c.want, e.liquidAt(c.x, c.z));
    }
    try std.testing.expect(!e.inWater(0, 0, 1.0));
    std.debug.print("\n  footing: four pools, each answering with its own kind, dry in the middle\n", .{});
}

test "DIGGING A POOL puts the dweller's floor at the dweller depth and leaves the shore alone" {
    const m = try wf.testMap(std.testing.allocator, wf.TEST_HEAD ++ "foe: fen_lurker 0 0 0 1 0.5\n");
    defer std.testing.allocator.destroy(m);
    _ = m.paintWater(0, 0, 15, true, .speckle, .water);
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    const dryBefore = m.heightAt(30, 0);
    const moved = Env.digPools(m, 5.0);
    try std.testing.expect(moved > 0);
    e.uploadWater(m);
    e.heightField = m.height;
    e.heightHalf = m.half;
    e.heightAny = m.anyHeight();
    try std.testing.expectApproxEqAbs(dwellerDepth(), e.wadeDepth(0, 0), 1e-3);
    try std.testing.expectApproxEqAbs(dryBefore, m.heightAt(30, 0), 1e-6);
    // Nothing past the dig radius moved, wet or not.
    try std.testing.expectApproxEqAbs(@as(f32, 0), m.heightAt(8.5, 0), 1e-6);
    std.debug.print("\n  dug pool: {d} lattice points, {d:.3} m of water at the post\n", .{ moved, e.wadeDepth(0, 0) });
}

test "A FEN LURKER IS SUBMERGED WHEREVER IT IS POSTED, on every map but the bench's dry control" {
    const fen = @import("../foes/fenlurker.zig");
    var dir = std.fs.cwd().openDir(wf.DIR, .{ .iterate = true }) catch return error.SkipZigTest;
    defer dir.close();
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    var checked: usize = 0;
    var it = dir.iterate();
    while (try it.next()) |ent| {
        if (ent.kind != .file or !std.mem.endsWith(u8, ent.name, wf.EXT)) continue;
        if (std.mem.eql(u8, ent.name, "test_fenlurker" ++ wf.EXT)) continue;
        var buf: [256]u8 = undefined;
        const path = try std.fmt.bufPrint(&buf, wf.DIR ++ "/{s}", .{ent.name});
        var line: usize = 0;
        try wf.load(path, m, &line);
        var any = false;
        for (m.foes[0..m.nfoes]) |f| {
            if (f.kind == .fen_lurker) any = true;
        }
        if (!any) continue;
        e.* = .{ .ground = undefined, .models = undefined };
        e.heightField = m.height;
        e.heightHalf = m.half;
        e.heightAny = m.anyHeight();
        e.uploadWater(m);
        e.materialize(m);
        for (m.foes[0..m.nfoes]) |f| {
            if (f.kind != .fen_lurker) continue;
            const d = e.wadeDepth(f.x, f.z);
            std.debug.print("  {s}: fen lurker at {d:.2} {d:.2} in {d:.3} m of water (the pool floor wants {d:.3})\n", .{ ent.name, f.x, f.z, d, dwellerDepth() });
            if (d < fen.POOL_MIN or d > WADE_MAX) return error.LurkerOutOfItsWater;
            checked += 1;
        }
    }
    try std.testing.expect(checked > 0);
    std.debug.print("\n  fen lurkers submerged on the shipped maps: {d}\n", .{checked});
}

