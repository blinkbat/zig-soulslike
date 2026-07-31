const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const collision = @import("collision.zig");
const props = @import("props.zig");
const wf = @import("worldfmt.zig");
const chestmod = @import("chest.zig"); // for `Site` alone — env finds the boxes, chest.zig runs them

const v3 = mathx.v3;
const Kind = props.Kind;

// ── THE WORLD ── a golden-hour plain ringed by cliffs, holding five regions that each read
// differently the moment you walk in: the fallen AVENUE you start on (centre/south), the FALLEN CITY
// with its torchlit chapel and watchtowers (north), the wadeable TARN (east), the OLD WOOD (west), the
// open WINDSWEPT DOWNS (south). See the map file for what's in each.
//
// It is DATA — `worlds/*.world`, an ordered list of authoring ops (worldfmt.zig) that `materialize`
// replays into the prop list below. This file authors nothing; it loads, indexes, culls and draws.
// Every scatter runs off ITS OWN seeded Rng (one per op, not one per world), so the world is identical
// every launch and editing one scatter cannot re-roll its neighbours.
//
// PERFORMANCE — the whole point of the structure below, since most of thousands of props are behind you
// or lost in haze:
//   1. A UNIFORM GRID indexes every prop by cell (CSR: one items array + per-cell spans, no
//      allocation). Two indexes, structures and flora, so each pass walks only its own and each cell
//      carries the maxima that pass needs.
//   2. The LIT PASS culls per CELL first (four frustum side planes + the cell's max view distance),
//      then per prop. A rejected cell is 30 props never touched.
//   3. The DEPTH PASS culls by SHADOW REACH, not camera distance: at this sun elevation a caster throws
//      its shadow ~1.5x its height sideways, so a prop matters iff its footprint plus that reach can
//      touch the sun's ortho box. A naive distance cull clips real shadows.
//   4. COLLISION and ARROW FLIGHT query the same grid instead of scanning every solid.

// THE WORLD'S SIZE IS THE MAP'S (`wf.Map.half`), not a constant here. It was once both, and the copy in
// this file was the one that counted — the movement clamp read it, so a map could declare any `half:` and
// the hero still stopped at 158 with the cliffs visibly further out. The only compile-time size left is
// the CEILING the fixed grid can index.
/// How far outside the playable bounds the rock wall stands.
pub const RIM_OUT: f32 = 6.0;
/// How far INSIDE the map's half the movement clamp sits, so the hero stops short of the rock rather
/// than clipping into it.
pub const PLAY_INSET: f32 = 2.0;
/// The largest `half` the grid can index without cells clamping together. Past it the culling still
/// WORKS but degrades: everything beyond piles into the boundary cells, and a cell that can't be
/// rejected is thirty props tested one by one. Derived, so raising GRID_N re-checks the assertions.
pub const MAX_HALF: f32 = GRID_HALF + CELL - RIM_OUT - CLIFF_BOUND;
/// The cliff mesh's own bounding radius, which sticks out past the rim it is placed on.
const CLIFF_BOUND: f32 = 18.0;
// The ground QUAD runs far past the bounds so terrain dissolves into full haze with no visible plane
// edge from anywhere. It must clear the farthest the player can stand PLUS the distance haze goes fully
// opaque (~3/HAZE_DENSITY), or the edge shows at the world's corners. One quad: free.
const GROUND_HALF: f32 = wf.DEFAULT_HALF + 220.0;

// Storage caps, all fixed: Env is one flat block inside the heap-allocated Game and never allocates.
// Overflowing any is an init-time PANIC, never a silent drop — a dropped collider is a walk-through wall
// and a dropped prop is a hole in the world.
const MAX_PROPS = 24576;
const MAX_SOLIDS = 8192;
const MAX_SOLID_REFS = 4 * MAX_SOLIDS; // a long solid's bbox spans several cells, one ref each
const MAX_LIGHTS = 192; // fires in the world; gfx.MAX_LIGHTS of them reach the GPU per frame

// CELL is a compromise: small enough to be a meaningful cull unit, large enough that walking every cell
// per pass stays trivial. 40 a side = 640 m, covering a 280 m map's cliff ring (286 + 18 of cliff bound)
// with room over — the arrays are BSS and the per-frame cost is one loop of four plane tests, so 1,600
// cells is not measurable next to the prop work it saves. See MAX_HALF: that is what this really sets.
const CELL: f32 = 16.0;
const GRID_N: usize = 40;
const GRID_SPAN: f32 = CELL * @as(f32, @floatFromInt(GRID_N));
const GRID_HALF: f32 = GRID_SPAN * 0.5;
const NCELL: usize = GRID_N * GRID_N;
// Turns a square's half-width into the radius of the sphere enclosing it. Named because it appears twice
// (cell circumradius and the shadow box's) and 0.70711 twice reads like two unrelated magic numbers.
const HALF_DIAG: f32 = @sqrt(0.5);
const CELL_CIRCUM: f32 = CELL * HALF_DIAG; // centre-to-corner of a cell, for sphere tests

// Horizontal distance a shadow travels per unit of caster height, derived from THE one sun direction so
// retuning the light can't leave it stale.
const SUN_REACH: f32 = @sqrt(gfx.SUN_DIR.x * gfx.SUN_DIR.x + gfx.SUN_DIR.z * gfx.SUN_DIR.z) / gfx.SUN_DIR.y;
// Half-diagonal of the sun's ortho box: a caster outside this plus its reach cannot put a single texel
// into the shadow map.
const SHADOW_BOX: f32 = gfx.SHADOW_ORTHO * HALF_DIAG;

// How far a fire's pool of light still reads. Kept at the OLD accept distance, so `uploadLights`' frustum
// cull changes only WHICH lights are dropped (the off-screen ones), never how far a visible one reaches.
const LIGHT_REACH: f32 = 90.0;

// Largest number of solids one grid query can hand back. The densest 16 m cell (a watchtower's
// 11-collider drum plus spill) holds well under 30, and a query straddles at most four.
pub const MAX_NEAR = 160;

// The ground sits a HAIR ABOVE Y=0, where soles and prop bases are authored, so content is
// planted-to-slightly-embedded and nothing ever reads as FLOATING. The old −0.05 put it BELOW the feet
// and floated everything ~2 in; owner's call is that a tiny foot clip beats any float. Off exact 0 so
// coplanar faces don't z-fight, and tiny enough (~1 cm) that the embed is imperceptible.
//
// With elevation this became the DATUM the sculpted field is measured from, not the ground's height:
// `groundAt` is this plus the map's height at that point, and a flat map still puts every surface
// exactly where it was.
const GROUND_Y: f32 = 0.01;

// ── ELEVATION ──────────────────────────────────────────────────────────────────────────
// The ground is a HEIGHTFIELD now (`wf.Map.height`, 2.5 m lattice, sculpted in the editor). Three
// things follow from that, and all three are why this is not just a taller quad:
//
//  1. THE MESH IS CHUNKED. One world-spanning mesh is 100k triangles that must be REBUILT while a
//     sculpt brush is dragging — 13 MB of vertex churn per frame, i.e. a slideshow. Split into
//     `TCHUNK`-cell tiles, a stroke rebuilds the two or three tiles it touched and the rest of the
//     terrain is not looked at. The tiles are also the cull unit for drawing.
//  2. NOTHING SAMPLES THE MAP DIRECTLY. Env keeps its own copy of the field (`heightField`), pushed
//     by `uploadHeight`, exactly like the soil and water it sits beside — so gameplay stands on the
//     field the visible mesh was built from and can never read a half-edited grid.
//  3. A FLAT MAP COSTS NOTHING. `heightAny` is false until something is sculpted, and then the whole
//     terrain is the ONE original quad again: same draw, same mesh, byte-identical world.
/// Height lattice points per terrain chunk. 16 points = 15 quads = 37.5 m of ground per tile, giving
/// 15x15 tiles over a 224-point field — a rebuild of ~450 quads per brush frame, and a cull unit
/// comfortably smaller than the view distance.
const TCHUNK: usize = 16;
/// Tiles per axis, rounded up so the last one carries the remainder. Fixed at comptime because the
/// lattice is a fixed size whatever the map's `half` is.
const TILES: usize = (wf.HEIGHT_N - 2) / (TCHUNK - 1) + 1;
const NTILES: usize = TILES * TILES;

/// How steep the ground may be and still be walked, as the TANGENT of the slope angle (rise over run).
/// tan 40 deg — ER's own limit is in this region, and it is the angle at which a scramble stops being a
/// walk. Above it the uphill part of a move is refused (see `walkStep`).
pub const MAX_SLOPE: f32 = 0.839;
/// A rise this small is ALWAYS steppable, however steep the face carrying it — the "slight step" rule.
/// Two things need it. A low ledge or terrace lip is otherwise a wall, since a half-metre rise across
/// half a metre is 45 deg of slope; and a hero walking along the FOOT of a cliff samples the cliff's own
/// gradient and would be held a metre off it by an invisible wall.
///
/// SIZED TO THE ENCODING, not picked: heights quantise to `wf.HEIGHT_STEP` (0.25 m), so the ledges that
/// can actually exist are 0.25, 0.50, 0.75… A limit of 0.55 makes "up to two steps" walkable with
/// headroom to spare and three steps a wall, which is a rule you can author against. It is also mid-shin
/// on an H=1.8 hero, which is about what a person steps up without thinking.
pub const STEP_UP: f32 = 0.55;
/// The fixed distance the walkable test looks AHEAD, and the reason the rule is frame-rate independent.
/// Measured against the frame's own travel instead, a 60 Hz hero moving 6 cm a frame would be allowed
/// STEP_UP for every one of those 6 cm — i.e. he would ratchet up a vertical cliff at 27 m/s. Looking a
/// fixed half-metre ahead asks the same question of the terrain however fast time is running.
pub const STEP_PROBE: f32 = 0.5;

/// The painted sheet's surface height — the same ankle-deep 0.055 the authored water prop uses, so a
/// painted lake and a placed one wade identically and cannot z-fight where they meet.
const WATER_Y: f32 = 0.055;

// The distance transform's two working grids. FILE SCOPE, not on Env and not on the stack: 200 KB of
// f32 per grid is far too much for a stack frame, and they hold nothing between calls — every cell is
// written before it is read (see uploadWater).
var scratchIn: [wf.WATER_CELLS]f32 = undefined;
var scratchOut: [wf.WATER_CELLS]f32 = undefined;

// `op` is the map op that placed this instance — what lets a click on a rock select the generator that
// grew it. Without it only literals would be selectable, and generators are most of the world.
// `lean`/`leanDir` TIP the instance off plumb (see the LEAN block below); 0 is plumb and costs nothing.
const Prop = struct { kind: Kind, pos: rl.Vector3, yaw: f32, scale: f32, lean: f32 = 0, leanDir: f32 = 0, op: u16 = 0 };

// ── LEAN ───────────────────────────────────────────────────────────────────────────────
// A prop can stand OFF PLUMB: `lean` degrees, tipped toward the compass direction `leanDir`, which is
// measured the same way as every yaw here (direction (cos d, −sin d) — see the yaw note in `line`).
//
// The tilt turns about the prop's GROUND ORIGIN, so its base stays planted where it was placed. That
// is also why nothing below inflates a culling bound: `info.bound` is a sphere about that same origin
// (and `bound >= top` is asserted in props), so rotating the mesh inside it leaves it enclosed.

/// The world direction a lean tips TOWARD.
fn leanToward(dirDeg: f32) rl.Vector3 {
    const a = mathx.radians(dirDeg);
    return v3(mathx.cosf(a), 0, -mathx.sinf(a));
}

/// The rotation AXIS for that lean: horizontal and square to the tip direction, signed so a POSITIVE
/// angle about it carries the top over the way `leanToward` points (right-hand rule, which is what
/// raylib's MatrixRotate builds).
fn leanAxis(dirDeg: f32) rl.Vector3 {
    const d = leanToward(dirDeg);
    return v3(d.z, 0, -d.x);
}

/// How far sideways a point `up` metres up a leaning prop's axis ends up, as a world offset. PUBLIC
/// because the editor's selection marker has to tip with the prop it is marking, and a second copy of
/// this trig over there is exactly how a marker ends up pointing somewhere the prop doesn't.
pub fn leanOffsetAt(lean: f32, dirDeg: f32, up: f32) rl.Vector3 {
    if (lean == 0) return mathx.zero3;
    const s = mathx.sinf(mathx.radians(lean)) * up;
    const d = leanToward(dirDeg);
    return v3(d.x * s, 0, d.z * s);
}

fn leanSwing(pr: Prop, up: f32) rl.Vector3 {
    return leanOffsetAt(pr.lean, pr.leanDir, up);
}

/// The cover field's gate FLOOR: a scatter that respects the field still places this fraction of its
/// attempts in a total clearing, so a clearing THINS what stands in it without emptying it. Named because
/// belt and disc both read it and a drift between the two would be invisible in the world.
const FIELD_FLOOR: f32 = 0.35;

// THE "may something grow here" PROBE, in one place: the `avoid.solid` test and the ground cover's own are
// the same question, and were the same three literals written twice. A drift would show as flora growing
// through walls in one scatter and not the other, with nothing to say which was wrong.
const SOLID_PROBE_Y: f32 = 0.2; // ankle height — under a causeway kerb's top, inside a wall's
const SOLID_PROBE_M: f32 = 0.35; // …a clump's own half-width, so leaves don't poke through masonry
const SOLID_PROBE_R: f32 = 1.4; // …and how far out the grid is asked for candidates

/// The ground plane's height, for anything that has to draw ON it (the editor's gizmos).
pub fn groundY() f32 {
    return GROUND_Y;
}

// A fire's static description; the per-frame guttering is applied in uploadLights.
const WorldLight = struct { base: gfx.Light, flicker: f32, phase: f32 };

// A water sheet, remembered so the scatter doesn't grow grass in the middle of the lake and
// so future systems (wading FX, sound) have somewhere to ask.
const Pool = struct { pos: rl.Vector3, radius: f32 };

// One CSR spatial index over a subset of the prop list. `items` holds prop indices grouped by
// cell; `start[c]..start[c+1]` is cell c's run. The three per-cell maxima let a whole cell be
// accepted or rejected before any prop in it is looked at.
const Index = struct {
    start: [NCELL + 1]u32 = [_]u32{0} ** (NCELL + 1),
    items: [MAX_PROPS]u32 = undefined,
    bound: [NCELL]f32 = [_]f32{0} ** NCELL, // max scaled bounding radius in the cell
    view: [NCELL]f32 = [_]f32{0} ** NCELL, // max view distance in the cell
    top: [NCELL]f32 = [_]f32{0} ** NCELL, // max scaled top height (shadow reach)
    // …and the cell's VERTICAL extent, which only matters with elevation and matters absolutely then:
    // the per-cell reject is a sphere about the cell's centre, and a cell whose props stand 20 m up a
    // hill is nowhere near a sphere centred at y = 0. Under-sized here, a whole hillside's worth of
    // props vanishes from the frame — the failure mode AGENTS.md files under "a culler bug looks like
    // an empty world". Flat maps fold to 0 and cost the two extra floats and nothing else.
    ylo: [NCELL]f32 = [_]f32{0} ** NCELL,
    yhi: [NCELL]f32 = [_]f32{0} ** NCELL,
};

/// The camera's four frustum SIDE planes, all through the eye point, plus that point. Near and far are
/// handled by the per-kind view distance instead, which is stricter and cheaper. Built from the camera
/// BASIS rather than by extracting planes from a view-projection matrix: same result, none of raylib's
/// row/column-major ambiguity, and it unit-tests with a pencil.
pub const View = struct {
    pos: rl.Vector3,
    n: [4]rl.Vector3, // inward normals: left, right, top, bottom

    pub fn fromCamera(cam: rl.Camera3D, aspect: f32) View {
        const fwd = mathx.normV(mathx.subV(cam.target, cam.position));
        // NB this camera's screen-right is world −X looking down +Z (AGENTS.md's strafe-sign invariant),
        // so (right, up, fwd) is not the handedness you'd assume. The plane normals are therefore
        // sign-corrected against `fwd` rather than derived from an assumed one — the first version
        // assumed, and culled the ENTIRE world.
        const right = mathx.normV(cross(fwd, cam.up));
        const up = cross(right, fwd);
        // A couple of degrees of slack: a plane that hugs the frustum exactly pops a prop whose authored
        // `bound` is a touch tight, and the slack costs a few draws.
        const vf = mathx.radians(cam.fovy) * 0.5 + mathx.radians(2.5);
        const hf = std.math.atan(@tan(mathx.radians(cam.fovy) * 0.5) * aspect) + mathx.radians(2.5);
        const cv = mathx.cosf(vf);
        const sv = mathx.sinf(vf);
        const chz = mathx.cosf(hf);
        const shz = mathx.sinf(hf);
        // Each boundary DIRECTION (a ray along one edge of the frustum's cross-section), then
        // the plane it spans with the axis it hinges about.
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

    /// Is the sphere (c, rad) worth drawing — inside all four side planes and within maxDist?
    pub fn visible(self: *const View, c: rl.Vector3, rad: f32, maxDist: f32) bool {
        const d = mathx.subV(c, self.pos);
        const far = maxDist + rad;
        if (d.x * d.x + d.y * d.y + d.z * d.z > far * far) return false;
        for (self.n) |nn| {
            if (nn.x * d.x + nn.y * d.y + nn.z * d.z < -rad) return false;
        }
        return true;
    }
};

/// Which set of props a draw call wants, and the test that decides.
pub const Cull = union(enum) {
    /// The lit pass: the camera frustum + each kind's own view distance.
    view: View,
    /// The sun depth pass: the hero-tracking focus point of the shadow ortho box.
    sun: rl.Vector3,
};

pub const Env = struct {
    ground: rl.Model,
    models: [props.NK]rl.Model,
    // The scene this world draws through, kept so the painted soil can be pushed to its shader
    // without threading a Scene pointer through every editor call that touches the map.
    scene: ?*gfx.Scene = null,
    props: [MAX_PROPS]Prop = undefined,
    nprops: usize = 0,
    solid_buf: [MAX_SOLIDS]collision.Solid = undefined,
    nsolids: usize = 0,
    // Structures and flora are indexed separately: the two draw passes then share nothing and
    // neither pays to skip the other's props.
    stx: Index = .{},
    flx: Index = .{},
    // Solid grid: refs into solid_buf, a solid appearing in every cell its footprint touches.
    sgrid_start: [NCELL + 1]u32 = [_]u32{0} ** (NCELL + 1),
    sgrid_items: [MAX_SOLID_REFS]u32 = undefined,
    lights: [MAX_LIGHTS]WorldLight = undefined,
    nlights: usize = 0,
    pools: [8]Pool = undefined,
    npools: usize = 0,
    /// THE PAINTED WATER: the sheet drawn over the whole world, and the signed field that decides where
    /// it exists (see uploadWater). `waterAny` is false for a map with nothing painted, and then neither
    /// is touched — the shipped map's authored `water` props are a separate, still-supported thing.
    waterSheet: rl.Model = undefined,
    waterField: [wf.WATER_CELLS]u8 = [_]u8{gfx.WATER_SHORE} ** wf.WATER_CELLS,
    waterAny: bool = false,
    waterHalf: f32 = 0,
    /// Where the painted water actually IS: the sheet is drawn at this centre, scaled by this fraction
    /// of the world quad, so a pond costs a pond's worth of fill instead of a full screen of it.
    waterMid: rl.Vector3 = mathx.zero3,
    waterSpan: rl.Vector3 = mathx.zero3,
    /// THE SCULPTED GROUND: the live copy of the map's height lattice, and the mesh built from it.
    /// `heightAny` false means the map is flat and `ground` (the one quad) draws instead of the tiles —
    /// so an unsculpted world is exactly the world that existed before elevation.
    heightField: [wf.HEIGHT_CELLS]u8 = [_]u8{wf.HEIGHT_ZERO} ** wf.HEIGHT_CELLS,
    heightHalf: f32 = wf.DEFAULT_HALF,
    heightAny: bool = false,
    /// One model per terrain tile, plus the SKIRT that carries the ground out to the haze. `built`
    /// tracks which tiles hold a live mesh, because they are unloaded and rebuilt as you sculpt and a
    /// stale handle here is a double free.
    tiles: [NTILES]rl.Model = undefined,
    tileBuilt: [NTILES]bool = [_]bool{false} ** NTILES,
    /// Each tile's bounding sphere, for the draw cull: centre and radius in world space.
    tileMid: [NTILES]rl.Vector3 = [_]rl.Vector3{mathx.zero3} ** NTILES,
    tileRad: [NTILES]f32 = [_]f32{0} ** NTILES,
    skirt: rl.Model = undefined,
    skirtBuilt: bool = false,
    // Per-frame culling counters, surfaced by the debug Stats overlay. The whole expansion rests
    // on the claim that a world of thousands of props costs a few hundred draws, and this is what
    // makes that claim CHECKABLE while playing instead of a thing I asserted once in a comment.
    stat_draws: u32 = 0,
    stat_cells: u32 = 0,

    /// Load the meshes ONCE. Separate from `materialize` because the models outlive every edit:
    /// the editor re-materializes the world on each change, and rebuilding every procedural mesh in
    /// `props.INFO` to move one rock would stall for a second every time. (Said without a count on
    /// purpose — the number here was "77" for three kinds' worth of history.)
    pub fn build(self: *Env, scene: *gfx.Scene) void {
        self.scene = scene;
        const shader = scene.shader;
        // Index each mesh by its own kind so the array and the kinds can't drift out of
        // lockstep (props.INFO's comptime block already pins the table; this pins the models).
        for (&self.models, props.INFO) |*m, row| m.* = row.build(shader);
        self.ground = terrain(shader, GROUND_HALF);
        self.waterSheet = waterQuad(shader, GROUND_HALF);
        self.nprops = 0;
        self.nsolids = 0;
        self.nlights = 0;
        self.npools = 0;
        // THE TERRAIN TILES START EMPTY, said explicitly. Env is built IN PLACE inside a heap-allocated
        // Game, so these fields' struct-literal defaults never run and `tileBuilt` would be raw heap
        // bytes — a true byte there sends `dropTile` into `unloadModel` on a garbage handle, which is a
        // free() of whatever the allocator last had there. Same trap `fillIndex` and `materialize`
        // document for their arrays; this one crashes rather than looking wrong.
        self.tileBuilt = [_]bool{false} ** NTILES;
        self.tileRad = [_]f32{0} ** NTILES;
        self.tileMid = [_]rl.Vector3{mathx.zero3} ** NTILES;
        self.skirtBuilt = false;
        self.heightField = [_]u8{wf.HEIGHT_ZERO} ** wf.HEIGHT_CELLS;
        self.heightHalf = wf.DEFAULT_HALF;
        self.heightAny = false;
    }

    /// Push the map's painted soil to the terrain shader. Separate from `materialize` on
    /// purpose: nothing about the prop list depends on the paint, so a brush stroke re-uploads
    /// 4 KB instead of re-expanding eight thousand props.
    pub fn uploadSoil(self: *Env, m: *const wf.Map) void {
        if (self.scene) |sc| sc.setSoil(&m.soil, m.half);
    }

    /// TAKE THE MAP'S SCULPTED GROUND and build the terrain from it: copy the field, then rebuild every
    /// tile. Call it on load and after any wholesale change (undo, a new map); a BRUSH calls
    /// `sculptHeight` instead, which rebuilds only what it touched.
    ///
    /// This has to run BEFORE `materialize`, because every prop is planted at the ground height under
    /// it — replay the ops against a stale field and the whole world stands at the old elevation.
    pub fn uploadHeight(self: *Env, m: *const wf.Map) void {
        self.heightField = m.height;
        self.heightHalf = m.half;
        self.heightAny = m.anyHeight();
        self.rebuildTerrain();
    }

    /// A SCULPT STROKE: take the map's field again but rebuild only the tiles the brush's lattice rect
    /// (`wf.Map.sculpt`'s `out`) actually reached. This is what makes dragging the raise brush
    /// interactive — a full rebuild is ~100k triangles of Builder work every frame the mouse moves.
    pub fn sculptHeight(self: *Env, m: *const wf.Map, span: [4]usize) void {
        self.heightField = m.height;
        self.heightHalf = m.half;
        const wasAny = self.heightAny;
        self.heightAny = m.anyHeight();
        // First sculpt on a flat map, or the last undo back to flat: the whole terrain changes
        // representation (quad ↔ tiles), so there is nothing partial about it.
        if (wasAny != self.heightAny) return self.rebuildTerrain();
        if (!self.heightAny) return;
        if (span[0] > span[2] or span[1] > span[3]) return; // the stroke missed the grid
        // A tile shares its edge points with its neighbour, so a point at a seam belongs to BOTH: the
        // range is widened by one point either way or a stroke on a boundary leaves a visible crack.
        const lo = tileOf(if (span[0] > 0) span[0] - 1 else 0);
        const hi = tileOf(@min(span[2] + 1, wf.HEIGHT_N - 1));
        const zlo = tileOf(if (span[1] > 0) span[1] - 1 else 0);
        const zhi = tileOf(@min(span[3] + 1, wf.HEIGHT_N - 1));
        var tz = zlo;
        while (tz <= zhi) : (tz += 1) {
            var tx = lo;
            while (tx <= hi) : (tx += 1) self.buildTile(tz * TILES + tx);
        }
        self.buildSkirt(); // its inner edge follows the terrain's rim, which a stroke there moves
    }

    /// Drop and rebuild every terrain tile (and the skirt) from the live field. Unloads first: these
    /// meshes are the one geometry in the game that is genuinely transient — props are prototypes that
    /// live for the whole program, terrain is re-authored under you.
    fn rebuildTerrain(self: *Env) void {
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
        if (!self.tileBuilt[i]) return;
        unloadTerrain(self.tiles[i]);
        self.tileBuilt[i] = false;
    }

    /// ONE TERRAIN TILE: the quads between lattice points [x0..x1] x [z0..z1], with SHARED per-point
    /// normals so the surface reads smooth across a tile and across the seam into the next one (the
    /// normal at a point is computed from the FIELD, not from this tile's triangles, which is what lets
    /// two independently-built tiles agree at their shared edge).
    fn buildTile(self: *Env, i: usize) void {
        self.dropTile(i);
        const tx = i % TILES;
        const tz = i / TILES;
        const x0 = tx * (TCHUNK - 1);
        const z0 = tz * (TCHUNK - 1);
        if (x0 + 1 >= wf.HEIGHT_N or z0 + 1 >= wf.HEIGHT_N) return; // a degenerate last tile
        const x1 = @min(x0 + TCHUNK - 1, wf.HEIGHT_N - 1);
        const z1 = @min(z0 + TCHUNK - 1, wf.HEIGHT_N - 1);
        const half = self.heightHalf;
        const step = 2 * half / @as(f32, @floatFromInt(wf.HEIGHT_N - 1));
        var b = gfx.Builder.init();
        var yLo: f32 = std.math.floatMax(f32);
        var yHi: f32 = -std.math.floatMax(f32);
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
                yLo = @min(yLo, @min(@min(ha, hb), @min(hc, hd)));
                yHi = @max(yHi, @max(@max(ha, hb), @max(hc, hd)));
                // Wound the way `quad` winds a floor (a→b→c→d anticlockwise seen from above), or
                // raylib culls the ground and you look straight through the world.
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
        self.tiles[i] = b.toModel(if (self.scene) |sc| sc.shader else self.ground.materials[0].shader);
        self.tileBuilt[i] = true;
        // The cull sphere about the tile's real extent, vertical span included — a tile 20 m up is not
        // where a flat-bottomed bound would say it is.
        const cx = -half + (@as(f32, @floatFromInt(x0)) + @as(f32, @floatFromInt(x1))) * 0.5 * step;
        const cz = -half + (@as(f32, @floatFromInt(z0)) + @as(f32, @floatFromInt(z1))) * 0.5 * step;
        const spanX = @as(f32, @floatFromInt(x1 - x0)) * step;
        const spanZ = @as(f32, @floatFromInt(z1 - z0)) * step;
        self.tileMid[i] = v3(cx, (yLo + yHi) * 0.5, cz);
        self.tileRad[i] = 0.5 * @sqrt(spanX * spanX + spanZ * spanZ + (yHi - yLo) * (yHi - yLo));
    }

    /// THE SKIRT: a ring of ground from the height field's rim out to the haze, so a sculpted world
    /// still dissolves into distance with no visible plane edge (the flat map's one big quad does this
    /// job by simply being enormous). Its INNER edge follows the terrain's own border heights, so there
    /// is no step at the seam; its outer edge lies at the datum, far enough out that the transition is
    /// behind the cliff ring and inside full haze.
    fn buildSkirt(self: *Env) void {
        if (self.skirtBuilt) {
            unloadTerrain(self.skirt);
            self.skirtBuilt = false;
        }
        const half = self.heightHalf;
        const out = GROUND_HALF;
        if (out <= half) return;
        const n = wf.HEIGHT_N - 1;
        const step = 2 * half / @as(f32, @floatFromInt(n));
        const up = v3(0, 1, 0);
        var b = gfx.Builder.init();
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const a = -half + @as(f32, @floatFromInt(i)) * step;
            const c = a + step;
            // North (−Z) and south (+Z) runs, then west/east. Each quad's inner edge takes the two
            // border heights it spans; the outer corners sit at the datum.
            b.quadSmooth(v3(a, self.pointY(i, 0), -half), v3(a, 0, -out), v3(c, 0, -out), v3(c, self.pointY(i + 1, 0), -half), up, up, up, up, rl.Color.white);
            b.quadSmooth(v3(a, 0, out), v3(a, self.pointY(i, n), half), v3(c, self.pointY(i + 1, n), half), v3(c, 0, out), up, up, up, up, rl.Color.white);
            b.quadSmooth(v3(-out, 0, a), v3(-out, 0, c), v3(-half, self.pointY(0, i + 1), c), v3(-half, self.pointY(0, i), a), up, up, up, up, rl.Color.white);
            b.quadSmooth(v3(half, self.pointY(n, i), a), v3(half, self.pointY(n, i + 1), c), v3(out, 0, c), v3(out, 0, a), up, up, up, up, rl.Color.white);
        }
        // …and the four corner squares the runs leave open.
        const cs = [_][2]f32{ .{ -1, -1 }, .{ 1, -1 }, .{ -1, 1 }, .{ 1, 1 } };
        for (cs) |s| {
            const ix: usize = if (s[0] < 0) 0 else n;
            const iz: usize = if (s[1] < 0) 0 else n;
            const hy = self.pointY(ix, iz);
            const xi = s[0] * half;
            const xo = s[0] * out;
            const zi = s[1] * half;
            const zo = s[1] * out;
            // Wound off the inner corner outward in a fixed order and flipped by the quadrant's sign
            // product, so all four faces point UP (a corner built by one recipe faces down in two of
            // the four quadrants, and a downward-facing patch of ground is simply not there).
            if (s[0] * s[1] > 0) {
                b.quadSmooth(v3(xi, hy, zi), v3(xi, 0, zo), v3(xo, 0, zo), v3(xo, 0, zi), up, up, up, up, rl.Color.white);
            } else {
                b.quadSmooth(v3(xi, hy, zi), v3(xo, 0, zi), v3(xo, 0, zo), v3(xi, 0, zo), up, up, up, up, rl.Color.white);
            }
        }
        self.skirt = b.toModel(if (self.scene) |sc| sc.shader else self.ground.materials[0].shader);
        self.skirtBuilt = true;
    }

    /// The world Y of one lattice point — the mesh's own corner height, datum included.
    fn pointY(self: *const Env, ix: usize, iz: usize) f32 {
        return GROUND_Y + wf.heightOf(self.heightField[@min(iz, wf.HEIGHT_N - 1) * wf.HEIGHT_N + @min(ix, wf.HEIGHT_N - 1)]);
    }

    /// The surface normal AT a lattice point, from the field's central differences. Taken from the
    /// FIELD rather than from adjacent triangle faces so two tiles meeting at a seam compute the same
    /// normal on both sides — otherwise every tile boundary is a visible crease.
    fn pointNormal(self: *const Env, ix: usize, iz: usize) rl.Vector3 {
        const step = 2 * self.heightHalf / @as(f32, @floatFromInt(wf.HEIGHT_N - 1));
        const xm = self.pointY(if (ix > 0) ix - 1 else 0, iz);
        const xp = self.pointY(ix + 1, iz);
        const zm = self.pointY(ix, if (iz > 0) iz - 1 else 0);
        const zp = self.pointY(ix, iz + 1);
        // A one-sided difference at the rim spans one step, not two: dividing by 2·step there would
        // halve the edge's slope and put a soft lip round the whole map.
        const xSpan: f32 = if (ix > 0 and ix + 1 < wf.HEIGHT_N) 2.0 else 1.0;
        const zSpan: f32 = if (iz > 0 and iz + 1 < wf.HEIGHT_N) 2.0 else 1.0;
        const dx = (xp - xm) / (step * xSpan);
        const dz = (zp - zm) / (step * zSpan);
        return mathx.normV(v3(-dx, 1.0, -dz));
    }

    /// TURN THE PAINTED MASK INTO A SHORE. This is the whole "no manual blending" claim, and it is a
    /// SIGNED DISTANCE TRANSFORM: measure every cell's distance to the nearest cell of the other kind,
    /// then encode wet cells above the waterline byte and dry ones below it. The shader reads that one
    /// field for three separate things (where the sheet exists, how deep it looks, and how far the wet
    /// sand reaches), so a coast, its shallows and its beach can never disagree with each other.
    ///
    /// Two passes of a chamfer transform, forward then backward — exact enough that no eye can tell it
    /// from a Euclidean one at 2.5 m cells, and it is ~100k adds over the whole world, so a brush
    /// stroke can call this on every frame it moves.
    pub fn uploadWater(self: *Env, m: *const wf.Map) void {
        const N = wf.WATER_N;
        self.waterAny = m.anyWater();
        self.waterHalf = m.half;
        if (!self.waterAny) {
            @memset(&self.waterField, 0);
            if (self.scene) |sc| sc.setWater(&self.waterField, m.half, false);
            return;
        }
        // THE PAINTED EXTENT, so the sheet can be drawn at the size of the water instead of the size of
        // the world. It is one quad either way, but a world-spanning one is a FULL-SCREEN fill through
        // the scene shader every frame — a bilinear field fetch and a discard for every pixel of dry
        // land on screen — to draw a pond in one corner. Two cells of margin so the shader's soft edge
        // has somewhere to fade.
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
        // ONE cell width for the whole function. It was computed twice under two names (`cellW` for
        // the painted extent, `cellM` for the encode) — the same expression, so the two could only
        // ever agree, which is exactly why nobody would notice if one of them stopped.
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
        // `dIn` counts cells to the nearest DRY cell, `dOut` to the nearest WET one. Held in cell units
        // (a float is plenty and keeps the chamfer readable); FAR is any distance past what either ramp
        // can use, so the interior of a big lake stops accumulating.
        const FAR: f32 = 1e9;
        var dIn = &scratchIn;
        var dOut = &scratchOut;
        for (m.water, 0..) |wet, i| {
            dIn[i] = if (wet != 0) FAR else 0;
            dOut[i] = if (wet != 0) 0 else FAR;
        }
        // The two chamfer weights: 1 straight, √2 diagonal.
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
        // ENCODE. Half a cell is subtracted from both distances so the WATERLINE lands on the boundary
        // between a wet cell and a dry one rather than at a wet cell's centre — without it a painted
        // lake reads half a cell too big and the beach starts inside the water.
        const shoreF: f32 = @floatFromInt(gfx.WATER_SHORE);
        for (m.water, 0..) |wet, i| {
            const enc: f32 = if (wet != 0) blk: {
                const metres = @max(0.0, (dIn[i] - 0.5) * cell);
                break :blk shoreF + mathx.clampF(metres / gfx.WATER_DEEP_AT, 0, 1) * (255.0 - shoreF);
            } else blk: {
                const metres = @max(0.0, (dOut[i] - 0.5) * cell);
                break :blk shoreF * (1.0 - mathx.clampF(metres / gfx.WATER_WET_OUT, 0, 1));
            };
            self.waterField[i] = mathx.u8f(enc);
        }
        if (self.scene) |sc| sc.setWater(&self.waterField, m.half, true);
    }

    /// The painted sheet, drawn with the field driving its colour. Called from the lit pass only — it is
    /// not a shadow caster (a flat sheet at ankle height throws nothing worth the depth-pass draw).
    pub fn drawWater(self: *Env) void {
        if (!self.waterAny) return;
        if (self.scene) |sc| {
            // The sheet's three tones come from the PROP PALETTE, so a painted lake and the authored
            // water prop beside it are the same water by construction rather than by coincidence.
            sc.setWaterSheet(true, props.waterTones());
            // Scaled to the painted extent (Y left at 1 so the surface height is untouched). The shape
            // inside it is still the shader's business — this only stops the quad covering the map.
            rl.drawModelEx(self.waterSheet, self.waterMid, v3(0, 1, 0), 0, self.waterSpan, rl.Color.white);
            sc.setWaterSheet(false, undefined);
        }
    }

    /// Turn a map into the world, IN PLACE — not an `init()` returning a value, since Env is ~450 KB of
    /// flat arrays and a by-value return would copy that through the stack twice.
    ///
    /// Re-entrant on purpose: this is what the editor calls after every edit, so the edited map IS the
    /// live preview. Everything it touches is reset at the top; nothing accumulates.
    pub fn materialize(self: *Env, m: *const wf.Map) void {
        self.nprops = 0;
        self.nsolids = 0;
        self.nlights = 0;
        self.npools = 0;
        // …AND THE SOLID GRID, EMPTIED, before anything queries it. The first op loop below runs
        // `avoid.solid` candidates through `blockedNear`, which walks `sgrid_start[c]..[c+1]` — and
        // `buildSolids`, the only writer of those spans, does not run until after that loop. Env is
        // built IN PLACE inside a heap-allocated Game, so its struct-literal default for this array
        // never runs (the same trap `fillIndex` documents for Index's per-cell maxima): on the very
        // first materialize those spans were raw heap bytes, so `sgrid_items[k]` / `solid_buf[..]`
        // indexed out of range — a bounds panic in Debug, arbitrary reads in ReleaseFast. Zeroing
        // `sgrid_start` is the whole fix: every span is then empty, so `sgrid_items` is never read.
        // It only takes a scatter with "solids" ticked (the properties panel offers it on every op)
        // to reach; the shipped map sets it on `cover` alone, which runs after the grid is built.
        @memset(&self.sgrid_start, 0);

        var p = Placer{ .e = self, .m = m };
        // Everything except the ground cover, in file order — later ops read what earlier ones
        // placed (ivy climbs standing stone; a belt rejects water already poured).
        for (m.slice(), 0..) |*o, i| {
            p.cur = @intCast(i);
            if (o.op != .cover) p.expand(o);
        }
        // …then the solid grid, because the cover scatter asks it where it may grow…
        buildSolids(self);
        const beforeCover = self.nprops;
        for (m.slice(), 0..) |*o, i| {
            p.cur = @intCast(i);
            if (o.op == .cover) p.expand(o);
        }
        // …and REBUILD it only if the cover pass actually laid down a collider. A stale grid is
        // a walk-through wall, so this cannot simply be skipped — but ground cover is flora,
        // and flora has no footprint, so in every real map the answer is no and the second full
        // pass over ~8k props was pure waste on a path the editor runs on every edit.
        var coverIsSolid = false;
        for (self.props[beforeCover..self.nprops]) |pr| {
            if (props.info(pr.kind).parts.len > 0) {
                coverIsSolid = true;
                break;
            }
        }
        if (coverIsSolid) buildSolids(self);
        indexProps(self);
    }

    /// DEV HARNESS ONLY (`--shot-props`): stage exactly ONE prop at the origin on bare ground —
    /// plus its light, if the kind carries one — and index it, so every kind can be photographed
    /// in isolation. Same reset discipline as `materialize`: nothing accumulates across calls.
    pub fn stageOne(self: *Env, kind: Kind) void {
        self.nprops = 0;
        self.nsolids = 0;
        self.nlights = 0;
        self.npools = 0;
        self.props[0] = .{ .kind = kind, .pos = v3(0, 0, 0), .yaw = 0, .scale = 1.0, .op = 0 };
        self.nprops = 1;
        if (props.info(kind).light) |ls| {
            self.lights[0] = .{ .base = .{ .pos = v3(0, ls.y, 0), .col = ls.col, .radius = ls.radius }, .flicker = ls.flicker, .phase = 0 };
            self.nlights = 1;
        }
        buildSolids(self);
        indexProps(self);
    }

    // (A `solids()` accessor handing back the WHOLE list lived here and had no caller — the "tests,
    // tooling" its doc claimed it was for never materialized, and every real path goes through
    // `nearSolids` / `blockedNear` / `resolveActor` on purpose. Kept as a note rather than as a
    // public function nobody reaches for but somebody eventually would: `solid_buf[0..nsolids]` is
    // one line to write when a tool actually needs it, and until then it is a footgun with a
    // docstring. `solidCount()` still reports the number for the debug overlay.)

    /// The solids that could touch a circle of radius `r` about `p`, written into `out`.
    /// Conservative: it may hand back a few extra (cell granularity), never fewer.
    pub fn nearSolids(self: *const Env, p: rl.Vector3, r: f32, out: []collision.Solid) []const collision.Solid {
        var n: usize = 0;
        const lo = cellCoord(p.x - r);
        const hi = cellCoord(p.x + r);
        const zlo = cellCoord(p.z - r);
        const zhi = cellCoord(p.z + r);
        var cz = zlo;
        while (cz <= zhi) : (cz += 1) {
            var cx = lo;
            while (cx <= hi) : (cx += 1) {
                const c = cz * GRID_N + cx;
                var k = self.sgrid_start[c];
                while (k < self.sgrid_start[c + 1]) : (k += 1) {
                    if (n >= out.len) return out[0..n]; // MAX_NEAR is sized well past the densest cell
                    out[n] = self.solid_buf[self.sgrid_items[k]];
                    n += 1;
                }
            }
        }
        return out[0..n];
    }

    /// Is `p` blocked by any solid near it? The COPY-FREE counterpart of `nearSolids` +
    /// `collision.blockedBy`, for callers that only want the yes/no — same cells, same `blocksPoint`,
    /// same margin, but tested in place and short-circuited on the first hit.
    ///
    /// PERFORMANCE, on the one path where it counts: `nearSolids` COPIES every candidate solid (32 bytes)
    /// into the caller's buffer, and the ground cover asks this once per LATTICE CANDIDATE — ~29,000
    /// queries on the shipped map, each copying out ~30 solids, so ~28 MB of memcpy per `materialize`
    /// discarded after one bool. The editor re-materializes at REBUILD_HZ while a dial is held.
    ///
    /// It also has no MAX_NEAR ceiling to truncate at, which can only turn a MISSED blocker into a found
    /// one — and in practice neither happens, since the 160-slot cap was never reached.
    pub fn blockedNear(self: *const Env, p: rl.Vector3, margin: f32, r: f32) bool {
        const x0 = cellCoord(p.x - r);
        const x1 = cellCoord(p.x + r);
        const z0 = cellCoord(p.z - r);
        const z1 = cellCoord(p.z + r);
        var cz = z0;
        while (cz <= z1) : (cz += 1) {
            var cx = x0;
            while (cx <= x1) : (cx += 1) {
                const c = cz * GRID_N + cx;
                var k = self.sgrid_start[c];
                while (k < self.sgrid_start[c + 1]) : (k += 1) {
                    if (collision.blocksPoint(p, margin, self.solid_buf[self.sgrid_items[k]])) return true;
                }
            }
        }
        return false;
    }

    /// Push an actor's footprint out of the nearby world solids (the grid-local counterpart of
    /// collision.resolve).
    pub fn resolveActor(self: *const Env, p: rl.Vector3, r: f32) rl.Vector3 {
        var buf: [MAX_NEAR]collision.Solid = undefined;
        return collision.resolve(p, r, self.nearSolids(p, r + 1.0, &buf));
    }

    // ── STANDING ON THE GROUND ─────────────────────────────────────────────────────────
    // Everything that touches the earth reads these three: the hero, every foe, arrows, prop
    // planting, the editor's cursor and its camera. They are the only readers of `heightField`
    // outside the mesh builder, so the world you stand on and the world you see are one field.

    /// The ground's world Y under a point — the datum plus whatever the map was sculpted to. On a flat
    /// map this is exactly `GROUND_Y`, so nothing that used to sit at 0.01 has moved.
    pub fn groundAt(self: *const Env, x: f32, z: f32) f32 {
        if (!self.heightAny) return GROUND_Y;
        return GROUND_Y + wf.sampleHeight(&self.heightField, self.heightHalf, x, z);
    }

    /// The ground GRADIENT there — (dh/dx, dh/dz), metres of rise per metre travelled.
    pub fn gradAt(self: *const Env, x: f32, z: f32) [2]f32 {
        if (!self.heightAny) return .{ 0, 0 };
        return wf.sampleGrad(&self.heightField, self.heightHalf, x, z);
    }

    /// How steep the ground is there, as the TANGENT of the slope angle (0 = flat, 1 = 45 deg).
    pub fn slopeAt(self: *const Env, x: f32, z: f32) f32 {
        const g = self.gradAt(x, z);
        return @sqrt(g[0] * g[0] + g[1] * g[1]);
    }

    /// How much the ground rises along `dir` — the slope an actor FACING that way is climbing (negative
    /// descending). Signed, unlike `slopeAt`, which is why the hero's lean reads uphill from downhill.
    pub fn slopeAlong(self: *const Env, x: f32, z: f32, dir: rl.Vector3) f32 {
        const g = self.gradAt(x, z);
        return g[0] * dir.x + g[1] * dir.z;
    }

    /// CAN AN ACTOR STAND HERE — is the ground walkable rather than a cliff face? The one question the
    /// slope limit answers, kept separate from `walkStep` so a spawn/teleport can ask it too.
    pub fn walkableAt(self: *const Env, x: f32, z: f32) bool {
        return self.slopeAt(x, z) <= MAX_SLOPE;
    }

    /// THE TRAVERSAL RULE, and the whole of it: take a step from `from` along `dir` for `dist` metres and
    /// return where the actor actually ends up (XZ; the caller grounds Y).
    ///
    /// Walkable if EITHER of two things is true, measured over a FIXED lookahead (`STEP_PROBE`) rather
    /// than over this frame's travel — see that constant for why the frame's own distance cannot be used:
    ///
    ///   * the rise ahead is under `STEP_UP` — a kerb, a terrace lip, a step. Always allowed, whatever
    ///     the face's angle, which is also what stops the foot of a cliff wearing an invisible wall.
    ///   * or the rise is within what `MAX_SLOPE` would give over that distance — an incline.
    ///
    /// A refused step is not a stop: the UPHILL COMPONENT is removed and what is left of the move is
    /// taken. So walking into a cliff at an angle slides you along it, straight on holds you still, and
    /// nothing about the input is dropped — the ground simply refuses to be climbed.
    pub fn walkStep(self: *const Env, from: rl.Vector3, dir: rl.Vector3, dist: f32) rl.Vector3 {
        const to = v3(from.x + dir.x * dist, from.y, from.z + dir.z * dist);
        if (!self.heightAny or dist <= 0) return to;
        if (self.stepOk(from, dir, dist)) return to;
        // The horizontal direction the ground rises fastest, and what is left of the move once its
        // uphill part is taken out. A step straight at the face leaves nothing and the actor holds.
        const g = self.gradAt(from.x, from.z);
        const gl = @sqrt(g[0] * g[0] + g[1] * g[1]);
        if (gl < 1e-5) return to;
        const ux = g[0] / gl;
        const uz = g[1] / gl;
        const along = dir.x * ux + dir.z * uz;
        if (along <= 0) return to; // already heading down or across it — never refuse that
        const tx = dir.x - ux * along;
        const tz = dir.z - uz * along;
        const tl = @sqrt(tx * tx + tz * tz);
        if (tl < 1e-5) return v3(from.x, from.y, from.z);
        // The tangent keeps the step's LENGTH, not just its direction, so sliding along a wall travels
        // at walking pace instead of quietly slowing to nothing as you square up to it.
        const slide = v3(from.x + tx / tl * dist, from.y, from.z + tz / tl * dist);
        // …and it has to be walkable itself, or a tangent that runs onto a steeper part of the same
        // face would let you climb it sideways.
        if (self.stepOk(from, v3(tx / tl, 0, tz / tl), dist)) return slide;
        return v3(from.x, from.y, from.z);
    }

    /// Is the ground `probe` metres along `dir` a step this actor may take? See `walkStep`.
    fn stepOk(self: *const Env, from: rl.Vector3, dir: rl.Vector3, dist: f32) bool {
        const probe = mathx.maxF(dist, STEP_PROBE);
        const h0 = self.groundAt(from.x, from.z);
        const h1 = self.groundAt(from.x + dir.x * probe, from.z + dir.z * probe);
        const rise = h1 - h0;
        return rise <= mathx.maxF(STEP_UP, MAX_SLOPE * probe);
    }

    /// Where a ray meets the ground — the editor's cursor, and anything else aiming at the terrain.
    /// Marched rather than solved: the surface is a bilinear patchwork, so there is no closed form, and
    /// a march that steps a fraction of a lattice cell cannot skip a ridge. Refined by bisection once a
    /// crossing is bracketed, so the answer is exact to a centimetre.
    ///
    /// Falls back to the flat plane solve when nothing is sculpted, which is both faster and exactly
    /// what the editor did before.
    pub fn rayGround(self: *const Env, origin: rl.Vector3, dir: rl.Vector3) ?rl.Vector3 {
        if (!self.heightAny) {
            if (@abs(dir.y) < 1e-6) return null;
            const t = (GROUND_Y - origin.y) / dir.y;
            if (t <= 0) return null;
            return v3(origin.x + dir.x * t, GROUND_Y, origin.z + dir.z * t);
        }
        const step = 2 * self.heightHalf / @as(f32, @floatFromInt(wf.HEIGHT_N - 1));
        const horiz = @sqrt(dir.x * dir.x + dir.z * dir.z);
        // Advance half a lattice cell of GROUND distance per step (or a fixed slab when looking almost
        // straight down, where the horizontal march is nearly zero and would never terminate).
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

    /// Water depth-ish test: is this ground position inside a pool? (Nothing blocks there —
    /// the tarn is wadeable by design — but the scatter uses it, and wading FX will too.)
    pub fn inWater(self: *const Env, x: f32, z: f32, inset: f32) bool {
        for (self.pools[0..self.npools]) |w| {
            const dx = x - w.pos.x;
            const dz = z - w.pos.z;
            const r = w.radius * inset;
            if (dx * dx + dz * dz < r * r) return true;
        }
        // …and the PAINTED water, off the same field the shader draws. The field is a DISTANCE, so
        // `inset` (a radius multiplier for a pool) becomes a SHORELINE MARGIN here: under 1 it holds the
        // answer back from the last foot of shallows, at or over 1 it takes any water at all.
        const margin = (1.0 - mathx.clampF(inset, 0, 1)) * gfx.WATER_DEEP_AT;
        return self.paintedDepth(x, z) * gfx.WATER_DEEP_AT > margin + 0.01;
    }

    /// How deep the painted water is at a point: 0 dry, 1 as deep as the field ramps (gfx.WATER_DEEP_AT
    /// metres from the shore). The one reader of the field outside the shader — wading, the scatter's
    /// water test, and anything later that needs to know it is standing in a lake.
    pub fn paintedDepth(self: *const Env, x: f32, z: f32) f32 {
        if (!self.waterAny or self.waterHalf <= 0) return 0;
        const N = wf.WATER_N;
        const t = (x + self.waterHalf) / (2 * self.waterHalf);
        const u = (z + self.waterHalf) / (2 * self.waterHalf);
        if (t < 0 or t >= 1 or u < 0 or u >= 1) return 0;
        const cx: usize = @min(@as(usize, @intFromFloat(t * @as(f32, @floatFromInt(N)))), N - 1);
        const cz: usize = @min(@as(usize, @intFromFloat(u * @as(f32, @floatFromInt(N)))), N - 1);
        const v: f32 = @floatFromInt(self.waterField[cz * N + cx]);
        const shore: f32 = @floatFromInt(gfx.WATER_SHORE);
        if (v <= shore) return 0;
        return (v - shore) / (255.0 - shore);
    }

    /// The prop a ray hits first — the editor's world picking. A plain linear ray/sphere sweep: ~8k
    /// spheres on a CLICK is nothing, and going through the grid would mean walking cells in ray order for
    /// no measurable gain. Each sphere is centred half way up its mesh, not on its ground origin, so a
    /// click on a tower's parapet picks the tower and not the weed at its foot.
    pub fn pick(self: *const Env, origin: rl.Vector3, dir: rl.Vector3) ?usize {
        return self.pickIf(origin, dir, {}, struct {
            fn all(_: void, _: u16) bool {
                return true;
            }
        }.all);
    }

    /// `pick`, but only over the props whose OP the predicate accepts. The filter has to be INSIDE the
    /// sweep: rejecting after the nearest hit has won makes a fern under a tree unpickable, because the
    /// tree's bigger sphere takes the ray and is then thrown away — which reads as the Decor layer
    /// refusing to select anything in a wood.
    pub fn pickIf(
        self: *const Env,
        origin: rl.Vector3,
        dir: rl.Vector3,
        ctx: anytype,
        comptime accept: fn (@TypeOf(ctx), u16) bool,
    ) ?usize {
        var best: ?usize = null;
        var bestT: f32 = std.math.floatMax(f32);
        for (self.props[0..self.nprops], 0..) |pr, i| {
            if (!accept(ctx, pr.op)) continue;
            const nfo = props.info(pr.kind);
            // Half way up the mesh — and half way up its LEAN when it has one, so a click lands on a
            // tipped tree where you SEE it rather than where it would have stood plumb.
            const sw = leanSwing(pr, nfo.top * pr.scale * 0.5);
            const c = v3(pr.pos.x + sw.x, pr.pos.y + nfo.top * pr.scale * 0.5, pr.pos.z + sw.z);
            const rad = @max(nfo.bound * pr.scale * 0.5, 0.35);
            const oc = mathx.subV(c, origin);
            const along = oc.x * dir.x + oc.y * dir.y + oc.z * dir.z;
            if (along <= 0) continue; // behind the eye
            const perp2 = (oc.x * oc.x + oc.y * oc.y + oc.z * oc.z) - along * along;
            if (perp2 > rad * rad) continue;
            if (along < bestT) {
                bestT = along;
                best = i;
            }
        }
        return best;
    }

    /// One kind's built model. The editor's object viewer draws these on their own, off-screen — and it
    /// has to be THIS model, the one the world draws, or the viewer is judging a second copy of the
    /// mesh that nobody plays.
    pub fn model(self: *const Env, kind: Kind) rl.Model {
        return self.models[@intFromEnum(kind)];
    }

    pub fn setShader(self: *Env, sh: rl.Shader) void {
        self.ground.materials[0].shader = sh;
        for (&self.models) |*m| m.materials[0].shader = sh;
        // The terrain tiles too, or the depth pass leaves them on the scene shader. They are not
        // casters today (see drawGround), so this only matters if that ever changes — but a caster set
        // that half-swaps its shaders is precisely the drift `setCasterShaders` exists to prevent.
        for (self.tiles[0..], self.tileBuilt[0..]) |*t, built| {
            if (built) t.materials[0].shader = sh;
        }
        if (self.skirtBuilt) self.skirt.materials[0].shader = sh;
    }

    /// Terrain receives shadows but doesn't cast; drawn separately with groundMode on.
    ///
    /// SCULPTED GROUND IS TILED and culled per tile — one world-spanning heightfield mesh is ~100k
    /// triangles, most of them behind you. A FLAT map draws the single original quad instead, which is
    /// cheaper than any number of tiles and is why nothing changed for the shipped world.
    ///
    /// The terrain still does NOT cast: a hill therefore shades by its own normal but throws no shadow
    /// across the ground behind it. Self-shadowing a heightfield off a 108 m ortho box invites acne
    /// everywhere the surface grazes the sun, and that is a worse artefact than a missing hill shadow.
    pub fn drawGround(self: *Env, view: ?*const View) void {
        if (!self.heightAny) {
            rl.drawModel(self.ground, mathx.zero3, 1.0, rl.Color.white);
            return;
        }
        for (self.tiles[0..], self.tileBuilt[0..], self.tileMid[0..], self.tileRad[0..]) |t, built, mid, rad| {
            if (!built) continue;
            // The terrain has no per-kind view distance to cull by, so the frustum sides alone decide;
            // GROUND_HALF is past the haze's own opacity, i.e. "everything in front of you".
            if (view) |vw| {
                if (!vw.visible(mid, rad, GROUND_HALF)) continue;
            }
            self.stat_draws += 1;
            rl.drawModel(t, mathx.zero3, 1.0, rl.Color.white);
        }
        if (self.skirtBuilt) rl.drawModel(self.skirt, mathx.zero3, 1.0, rl.Color.white);
    }

    /// The stone/structure props — the shadow casters, drawn in BOTH passes through this ONE
    /// function so their transforms can never drift between the depth pass and the lit pass
    /// (only the SET differs, which is the whole point of culling).
    pub fn drawProps(self: *Env, cull: Cull) void {
        self.drawIndexed(&self.stx, cull);
    }

    /// Zero the culling counters — call once at the top of the frame, before either pass.
    pub fn resetStats(self: *Env) void {
        self.stat_draws = 0;
        self.stat_cells = 0;
    }

    /// Props in the world, for the debug overlay (the denominator for stat_draws).
    pub fn propCount(self: *const Env) usize {
        return self.nprops;
    }

    /// EVERY CHEST THAT WAS ACTUALLY PLACED, in prop order. Filled here rather than read back off the ops
    /// because a prop's final position is env's answer, not the op's: it is planted at the terrain height
    /// under it, and a scatter could place several from one line. Returns how many were written; the
    /// caller's array is the cap (`chest.CAP`) and the overflow is dropped, like `foe.resetGroup`'s.
    pub fn chestSites(self: *const Env, out: []chestmod.Site) usize {
        var n: usize = 0;
        for (self.props[0..self.nprops]) |pr| {
            if (pr.kind != .chest) continue;
            if (n >= out.len) break;
            out[n] = .{ .pos = pr.pos, .yaw = pr.yaw, .scale = pr.scale, .op = pr.op };
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

    /// The flora — non-casters (thin blades sparkle in a shadow map), drawn only in the lit
    /// pass with the wind term on.
    pub fn drawFlora(self: *Env, view: *const View) void {
        self.drawIndexed(&self.flx, .{ .view = view.* });
    }

    // Walk one index cell by cell, rejecting whole cells before touching their props.
    fn drawIndexed(self: *Env, idx: *const Index, cull: Cull) void {
        // The depth pass wants CASTERS only; the lit pass wants everything, non-casters (the
        // water sheet) included — skipping them there would simply delete the tarn.
        const casters_only = cull == .sun;
        var c: usize = 0;
        while (c < NCELL) : (c += 1) {
            if (idx.start[c] == idx.start[c + 1]) continue;
            var centre = cellCentre(c);
            // Lifted onto the cell's own props (see Index.ylo/yhi): with terrain elevation the cell is a
            // slab that can sit tens of metres off the datum, and testing a sphere at y = 0 against the
            // frustum rejects a hilltop you are looking straight at.
            centre.y = (idx.ylo[c] + idx.yhi[c]) * 0.5;
            const vspan = (idx.yhi[c] - idx.ylo[c]) * 0.5;
            switch (cull) {
                .view => |*vw| {
                    if (!vw.visible(centre, CELL_CIRCUM + idx.bound[c] + vspan, idx.view[c])) continue;
                },
                .sun => |focus| {
                    if (!castsInto(focus, centre, CELL_CIRCUM + idx.bound[c], idx.top[c])) continue;
                },
            }
            self.stat_cells += 1;
            var k = idx.start[c];
            while (k < idx.start[c + 1]) : (k += 1) {
                const pr = &self.props[idx.items[k]];
                const nfo = props.info(pr.kind);
                if (casters_only and !nfo.casts) continue;
                const bound = nfo.bound * pr.scale;
                switch (cull) {
                    .view => |*vw| {
                        if (!vw.visible(pr.pos, bound, nfo.view)) continue;
                    },
                    .sun => |focus| {
                        if (!castsInto(focus, pr.pos, bound, nfo.top * pr.scale)) continue;
                    },
                }
                self.stat_draws += 1;
                const sc = v3(pr.scale, pr.scale, pr.scale);
                if (pr.lean == 0) {
                    rl.drawModelEx(self.models[@intFromEnum(pr.kind)], pr.pos, v3(0, 1, 0), pr.yaw, sc, rl.Color.white);
                } else {
                    // A LEANING instance needs two rotations, and raylib's DrawModelEx only takes one —
                    // so the YAW rides in the model transform (applied FIRST, in the mesh's own space)
                    // and the LEAN is the axis-angle it does take: the prop spins on its base, then tips
                    // over toward leanDir in WORLD space. The uniform scale between them commutes with
                    // both, so the order costs nothing. The model is copied by value, so this cannot
                    // leak a transform onto the next instance of the same kind.
                    var mdl = self.models[@intFromEnum(pr.kind)];
                    mdl.transform = rl.math.matrixRotateY(mathx.radians(pr.yaw));
                    rl.drawModelEx(mdl, pr.pos, leanAxis(pr.leanDir), pr.lean, sc, rl.Color.white);
                }
            }
        }
    }

    /// This frame's torch/fire lights: the gfx.MAX_LIGHTS nearest the camera whose pool is actually ON
    /// SCREEN, guttering applied. The world holds far more than the shader can; the dropped ones are
    /// furthest away, where a light contributes nothing.
    ///
    /// THE FRUSTUM TEST IS A PERFORMANCE FIX. This used to accept any fire within `radius + 90` of the
    /// eye — in the Fallen City that is every fire in the region, so `nLights` saturated every frame.
    /// `pointLights` runs per FRAGMENT unconditionally, so the full-screen terrain pass alone evaluated
    /// ~16M loop iterations for lights mostly BEHIND the camera. Tested against the same frustum the prop
    /// culler uses, with the light's own radius as the sphere: a torch lights its room the instant you
    /// look at it and costs nothing when you don't.
    pub fn uploadLights(self: *const Env, scene: *gfx.Scene, view: *const View, t: f32) void {
        var picked: [gfx.MAX_LIGHTS]gfx.Light = undefined;
        var dist: [gfx.MAX_LIGHTS]f32 = undefined;
        var n: usize = 0;
        for (self.lights[0..self.nlights]) |wl| {
            // Off screen → it lights nothing you can see. The distance cap is unchanged from the
            // old bound, so nothing that WAS lit stops being lit; only the off-screen ones go.
            if (!view.visible(wl.base.pos, wl.base.radius, LIGHT_REACH)) continue;
            const d2 = mathx.dist2XZ(wl.base.pos, view.pos);
            const k = 1.0 + wl.flicker * gutter(t, wl.phase);
            const lit = gfx.Light{
                .pos = wl.base.pos,
                .col = mathx.scaleV(wl.base.col, mathx.maxF(k, 0.05)),
                .radius = wl.base.radius,
            };
            if (n < picked.len) {
                picked[n] = lit;
                dist[n] = d2;
                n += 1;
                continue;
            }
            // Full: replace the furthest, if this one is nearer.
            var worst: usize = 0;
            for (dist[0..n], 0..) |dd, i| {
                if (dd > dist[worst]) worst = i;
            }
            if (d2 < dist[worst]) {
                picked[worst] = lit;
                dist[worst] = d2;
            }
        }
        scene.setLights(picked[0..n]);
    }
};

// A flame's guttering, in [-1, 1]: three incommensurate rates so it never reads as a pulse.
//
// SOFTENED AND SLOWED (owner's call). The old weights were front-loaded onto 9.1 and 19.7 rad/s —
// 1.4 and 3.1 Hz — which is a STROBE, not a fire: at that rate a pool of light reads as a fault in
// the renderer rather than as something burning. The energy moved to the slow term, so what a room
// does now is BREATHE, with only a little chop riding on top. A real fire's light varies mostly on
// the half-second, which is also slow enough that the eye reads it as warmth instead of flicker.
fn gutter(t: f32, phase: f32) f32 {
    return 0.30 * mathx.sinf(t * 4.3 + phase) + 0.14 * mathx.sinf(t * 8.9 + phase * 2.3) + 0.56 * mathx.sinf(t * 1.7 + phase * 0.6);
}

// Does a caster at `pos` (bounding radius `bound`, height `top`) reach the sun's ortho box
// around `focus`? Distance is XZ-only: the box tracks the hero on the ground plane.
fn castsInto(focus: rl.Vector3, pos: rl.Vector3, bound: f32, top: f32) bool {
    const reach = SHADOW_BOX + bound + top * SUN_REACH;
    return mathx.dist2XZ(focus, pos) <= reach * reach;
}

fn cross(a: rl.Vector3, b: rl.Vector3) rl.Vector3 {
    return v3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}

// The unit normal of the plane spanned by `a` and `b`, flipped to point to the side `inside`
// is on. Used for the frustum's side planes with `inside` = the camera forward, which is by
// construction strictly within all four of them — so the sign is DERIVED rather than assumed,
// and a basis whose handedness surprises you can no longer invert the whole culler.
fn inward(a: rl.Vector3, b: rl.Vector3, inside: rl.Vector3) rl.Vector3 {
    const n = mathx.normV(cross(a, b));
    const d = n.x * inside.x + n.y * inside.y + n.z * inside.z;
    return if (d < 0) mathx.scaleV(n, -1) else n;
}

/// DROP A TERRAIN MESH, and the ONE safe way to do it. The terrain is the only geometry in the game that
/// is ever unloaded (every prop is a permanent prototype — AGENTS.md says not to unload those, and this
/// is why): raylib's `UnloadModel` calls `UnloadMaterial`, which UNLOADS THE MATERIAL'S SHADER. The
/// shader on a tile is the SCENE shader every other draw in the frame uses, so unloading one tile
/// deleted the program out from under the whole renderer and freed its uniform table — and the next tile
/// freed the same pointer again. That is a heap corruption at exit and a dead renderer before it, and
/// the symptom is an exit code with no stack in it.
///
/// Pointing the material at raylib's DEFAULT shader first makes `UnloadMaterial` skip it (it never
/// unloads the default, nor the default texture), while the mesh's own VBOs and CPU arrays still go —
/// so this frees everything a rebuild should and nothing it shouldn't.
fn unloadTerrain(model: rl.Model) void {
    var m = model;
    m.materials[0].shader.id = rl.gl.rlGetShaderIdDefault();
    rl.unloadModel(m);
}

// Height lattice point → the terrain tile that owns it. Tiles overlap by one point (they share their
// edges), so a point on a seam answers with the LOWER tile and callers that care widen their range by
// a point either side — see `sculptHeight`.
fn tileOf(point: usize) usize {
    return @min(point / (TCHUNK - 1), TILES - 1);
}

// World coordinate → grid column/row, clamped so anything outside the grid lands in the edge
// cell rather than indexing out of bounds (the cliff ring sits near the limit by design).
fn cellCoord(w: f32) usize {
    // CLAMPED IN FLOAT, BEFORE THE CAST. The old version cast first and clamped after, so the promise
    // in the comment above only held for values `@intFromFloat` could represent: a NaN passes both
    // `<=` and `>=` and would reach the cast (illegal behaviour, not cell 0), and so would anything
    // past usize's range. `clampF` pins NaN to `lo`, which is the edge cell this is documented to give.
    return @intFromFloat(mathx.clampF((w + GRID_HALF) / CELL, 0, @floatFromInt(GRID_N - 1)));
}

fn cellOf(x: f32, z: f32) usize {
    return cellCoord(z) * GRID_N + cellCoord(x);
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

// Flat ground plane as one big white quad — the scene shader's terrainAlbedo owns the look.
fn terrain(shader: rl.Shader, half: f32) rl.Model {
    var b = gfx.Builder.init();
    b.quad(v3(-half, GROUND_Y, -half), v3(-half, GROUND_Y, half), v3(half, GROUND_Y, half), v3(half, GROUND_Y, -half), v3(0, 1, 0), rl.Color.white);
    return b.toModel(shader);
}

/// THE PAINTED WATER SHEET: one world-spanning quad on the `.water` material. It has no shape of its
/// own — the shader DISCARDS every fragment the field says is dry (see `waterSheet` there), so a lake
/// of any outline costs this one quad and needs no mesh built for its coastline. Two triangles is also
/// why the shore can be re-painted at interactive speed: nothing is rebuilt, one texture is re-uploaded.
fn waterQuad(shader: rl.Shader, half: f32) rl.Model {
    var b = gfx.Builder.init();
    b.setMat(.water);
    b.quad(v3(-half, WATER_Y, -half), v3(-half, WATER_Y, half), v3(half, WATER_Y, half), v3(half, WATER_Y, -half), v3(0, 1, 0), rl.Color.white);
    return b.toModel(shader);
}

// ── placement: REPLAYING A MAP ─────────────────────────────────────────────────────────
// The world was once authored here as five paragraphs of Zig; it lives in a MAP FILE now, and this is the
// other half of that — the expansion of each op into props. Two rules:
//
//   ORDER IS MEANING. Ops run in file order because later ones read what earlier ones placed: `ivy` only
//   climbs stonework already standing, a belt only rejects water already poured, and `cover` needs the
//   solid grid built. Nothing here may reorder.
//
//   EACH OP DRAWS FROM ITS OWN STREAM (`op.stream()`), never a shared one — what keeps an edit local (see
//   worldfmt.zig's header), and why this file holds no world seed: there are 277 of them instead.

const Placer = struct {
    e: *Env,
    m: *const wf.Map,
    cur: u16 = 0, // the op being expanded, stamped onto every prop it places
    // The LEAN the op being expanded asks for, held here rather than threaded through `at` — every
    // scatter would otherwise grow a parameter it does nothing with. `exact` is the `at` op: a literal
    // leans exactly as authored, while a scatter rolls each instance its own amount and direction.
    lean: f32 = 0,
    leanDir: f32 = 0,
    leanExact: bool = false,

    // PLANTED ON THE GROUND, which with elevation means the sculpted height there and not y = 0. Prop
    // bases are authored at their own local zero, so this one line is what stands the whole world on the
    // terrain — and why `uploadHeight` must run before `materialize`.
    //
    // The height is taken at the prop's ORIGIN only. A wide base on a slope therefore buries one edge
    // and lifts the other, which is the right trade at this pitch: the alternative is tilting props to
    // the ground normal, and a leaning wall or a tipped chapel is a much louder error than a plinth with
    // one corner in the dirt. Steep ground is for looking at, not for building on.
    fn at(self: *Placer, kind: Kind, x: f32, z: f32, yaw: f32, scale: f32, rng: *mathx.Rng) void {
        self.atY(kind, x, self.groundY(x, z), z, yaw, scale, rng);
    }

    /// The sculpted ground height for a prop about to be placed — read off the MAP being replayed, not
    /// off `env.groundAt`, because `materialize` may be running before the field has been uploaded (the
    /// `--shot-props` harness stages props with no map at all). Minus the datum: prop Y is measured from
    /// the same zero soles are.
    fn groundY(self: *const Placer, x: f32, z: f32) f32 {
        return self.m.heightAt(x, z);
    }

    // With an explicit Y — water (staggering overlapping sheets out of z-fighting) and the ground plant
    // above.
    fn atY(self: *Placer, kind: Kind, x: f32, y: f32, z: f32, yaw: f32, scale: f32, rng: *mathx.Rng) void {
        if (self.e.nprops >= MAX_PROPS) @panic("env: MAX_PROPS exceeded — raise the cap");
        // NOTHING is drawn from `rng` unless the op actually asked for a lean. Every existing world's
        // arrangement IS that stream, so an unconditional roll here would reshuffle the whole map (and
        // fail the pinned-instance-count test) the moment this field appeared.
        var lean: f32 = 0;
        var leanDir: f32 = self.leanDir;
        if (self.lean != 0) {
            if (self.leanExact) {
                lean = self.lean;
            } else {
                // A dial as a MAXIMUM: never dead plumb (authored variation is the point) and reaching
                // the full figure at the top, each instance falling its own way.
                lean = self.lean * rng.range(0.15, 1.0);
                leanDir = rng.range(0, 360);
            }
        }
        self.e.props[self.e.nprops] = .{ .kind = kind, .pos = v3(x, y, z), .yaw = yaw, .scale = scale, .lean = lean, .leanDir = leanDir, .op = self.cur };
        self.e.nprops += 1;
        if (props.info(kind).light) |ls| self.addLight(x, y, z, scale, ls, rng);
        if (kind == .water) {
            // An init-time PANIC, like MAX_PROPS/MAX_SOLIDS — never a silent drop. A dropped pool
            // makes `inWater` lie about that sheet, and the flora scatter then grows grass and
            // brambles out in the middle of the lake.
            if (self.e.npools >= self.e.pools.len) @panic("env: water pool cap exceeded — raise Env.pools");
            self.e.pools[self.e.npools] = .{ .pos = v3(x, y, z), .radius = 13.0 * scale };
            self.e.npools += 1;
        }
    }

    fn addLight(self: *Placer, x: f32, y: f32, z: f32, scale: f32, ls: props.LightSpec, rng: *mathx.Rng) void {
        if (self.e.nlights >= MAX_LIGHTS) return; // fires past the cap simply don't light — never a crash
        self.e.lights[self.e.nlights] = .{
            .base = .{ .pos = v3(x, y + ls.y * scale, z), .col = ls.col, .radius = ls.radius * mathx.maxF(scale, 0.6) },
            .flicker = ls.flicker,
            .phase = rng.range(0, 60), // every flame guttering on its own beat
        };
        self.e.nlights += 1;
    }

    /// The full accept test for one scatter candidate: the op's `avoid` set, then the cover
    /// field, then any density gradient. ONE function because belt and disc had the same three
    /// clauses written out separately, and the cover-field literal drifting between the two
    /// would be invisible — one scatter quietly thinning at a different rate than its neighbour.
    fn accepts(self: *Placer, o: *const wf.Op, x: f32, z: f32, rng: *mathx.Rng) bool {
        if (self.rejects(o, x, z)) return false;
        // The cover field, mixed toward 1 so structures THIN where the flora does without
        // vanishing. Same field the ground cover uses, so a clearing is a clearing for
        // everything standing in it.
        if (o.field and rng.float() > FIELD_FLOOR + (1.0 - FIELD_FLOOR) * coverField(x, z)) return false;
        if (o.gAxis != .none and rng.float() > o.gradAt(x, z)) return false;
        return true;
    }

    /// The shared rejection test every scatter runs a candidate through. Which clauses apply is
    /// the op's own `avoid` set, so lilies can float on the water that grass must keep off.
    fn rejects(self: *Placer, o: *const wf.Op, x: f32, z: f32) bool {
        if (o.avoid.runway and self.m.onRunway(x, z)) return true;
        if (o.avoid.water and self.e.inWater(x, z, 1.04)) return true;
        if (o.avoid.clear and self.m.inClearing(x, z)) return true;
        if (o.avoid.solid) {
            // Don't grow through the world: the solid grid already knows what is here. Through
            // `blockedNear`, which walks the grid in place — a scatter asks this per candidate and
            // only wants the bool, so copying the cells' solids out first was pure waste.
            if (self.e.blockedNear(v3(x, SOLID_PROBE_Y, z), SOLID_PROBE_M, SOLID_PROBE_R)) return true;
        }
        return false;
    }

    fn expand(self: *Placer, o: *const wf.Op) void {
        var rng = o.stream();
        self.lean = o.lean;
        self.leanDir = o.leanDir;
        self.leanExact = o.op == .at;
        switch (o.op) {
            // `r1` on a literal is a Y OFFSET ABOVE THE GROUND, not an absolute height — the only user
            // is the authored water sheet, staggering overlapping pools out of z-fighting, and an
            // absolute would leave a tarn hanging in the air over a raised valley floor. Every existing
            // map leaves it 0, so every existing prop simply plants.
            .at => self.atY(o.kind, o.x, self.groundY(o.x, o.z) + o.r1, o.z, o.yaw, o.scale, &rng),
            .belt => self.belt(o, &rng),
            .disc => self.disc(o, &rng),
            .ring => self.ring(o, &rng),
            .line => self.line(o, &rng),
            .ivy => self.ivy(o, &rng),
            .edge => self.edge(o, &rng),
            .cover => self.cover(o, &rng),
        }
    }

    // A scattered belt in a box. `n` is an ATTEMPT count, not a guarantee — rejection keeps the
    // world honest, and the clumping it leaves keeps a region from looking sown.
    fn belt(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        var i: i32 = 0;
        while (i < o.n) : (i += 1) {
            const x = rng.range(o.x, o.x1);
            const z = rng.range(o.z, o.z1);
            if (!self.accepts(o, x, z, rng)) continue;
            self.at(o.pick(rng), x, z, rng.range(0, 360), rng.range(o.sLo, o.sHi), rng);
        }
    }

    // An annulus scatter: shorelines, reed beds, talus, drowned ruin. `bias` bends the radial
    // distribution toward area-uniform, which packs a raft in around its rootstock.
    fn disc(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        var i: i32 = 0;
        while (i < o.n) : (i += 1) {
            const a = rng.angle();
            const t = rng.float();
            const d = o.r0 + (o.r1 - o.r0) * (t + (@sqrt(t) - t) * o.bias);
            const x = o.x + mathx.cosf(a) * d;
            const z = o.z + mathx.sinf(a) * d;
            if (!self.accepts(o, x, z, rng)) continue;
            self.at(o.pick(rng), x, z, rng.range(0, 360), rng.range(o.sLo, o.sHi), rng);
        }
    }

    // A ring of props about a centre — henges, stone circles, camps.
    fn ring(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        var i: i32 = 0;
        while (i < o.n) : (i += 1) {
            if (i == o.skip) continue; // the gap: a ring with every stone present reads as a fence
            const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(o.n));
            const r = o.r0 * rng.range(0.94, 1.06);
            const x = o.x + mathx.cosf(a) * r;
            const z = o.z + mathx.sinf(a) * r;
            if (self.rejects(o, x, z)) continue;
            self.at(
                o.pick(rng),
                x,
                z,
                mathx.degrees(-a) + 90 + rng.signed() * 12, // faces the centre, roughly
                rng.range(o.sLo, o.sHi),
                rng,
            );
        }
    }

    // A broken run from a→b: segments laid nose to tail, `chance` of each surviving. Both the
    // city's perimeter and the processional colonnade are this — one is a wall and one is a
    // row of columns, and the only difference is the kind mix and the spacing.
    fn line(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        const dx = o.x1 - o.x;
        const dz = o.z1 - o.z;
        const len = @sqrt(dx * dx + dz * dz);
        if (len < 1e-4 or o.r0 < 1e-4) return; // a zero-length or zero-step run would spin forever
        const ux = dx / len;
        const uz = dz / len;
        const yaw = mathx.degrees(std.math.atan2(-uz, ux)); // local +X is (cos yaw, −sin yaw)
        var t: f32 = o.r0 * 0.5;
        while (t < len) : (t += o.r0 * rng.range(1.0, 1.5)) {
            if (rng.float() > o.chance) continue; // a collapsed stretch
            const x = o.x + ux * t + rng.signed() * 0.6;
            const z = o.z + uz * t + rng.signed() * 0.6;
            if (self.rejects(o, x, z)) continue;
            self.at(o.pick(rng), x, z, yaw + rng.signed() * 6, rng.range(o.sLo, o.sHi), rng);
        }
    }

    // Sow a climber at the FEET of the stonework already standing inside a box. Ivy climbs: its
    // runners only make sense with a wall behind them, so this walks the props that are THERE
    // rather than scattering over ground — which is why op order matters.
    fn ivy(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        const n = self.e.nprops; // snapshot: the ivy we add must not seed more ivy
        for (self.e.props[0..n]) |pr| {
            switch (pr.kind) {
                .wall, .pillar, .broken, .block, .arch, .statue, .cottage, .chapel, .watchtower, .stairs, .monolith => {},
                else => continue,
            }
            if (pr.pos.x < o.x or pr.pos.x > o.x1 or pr.pos.z < o.z or pr.pos.z > o.z1) continue;
            if (rng.float() > o.chance) continue;
            const nfo = props.info(pr.kind);
            // Hug the base: just outside the prop's own footprint, so the runners lie against it.
            const a = rng.angle();
            const d = nfo.bound * pr.scale * rng.range(0.18, 0.42);
            self.at(o.kind, pr.pos.x + mathx.cosf(a) * d, pr.pos.z + mathx.sinf(a) * d, mathx.degrees(a), rng.range(o.sLo, o.sHi), rng);
        }
    }

    // ── THE EDGE: a cliff wall right round the world ────────────────────────────────────
    // The movement clamp sits just inside a rock face, so the world's edge reads as terrain rather than an
    // invisible wall in open grass. Each segment's detailed face is its local −Z, so each side takes the
    // yaw turning that face INWARD (north 180, south 0, east 90, west 270). The step is a DEEP overlap
    // against a 10.4 m segment — what turns a row of separate rocks into one continuous escarpment.
    fn edge(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        if (o.r0 < 1e-4) return;
        // Through RIM_OUT, not a literal 6.0: that constant IS this offset (it says so) and it also
        // feeds MAX_HALF, so a copy here lets the grid's ceiling stop describing the ring it is
        // sized for — silently, since the world still looks fine right up to the edge cells.
        const rim = self.m.half + RIM_OUT; // the rock wall stands just outside the movement clamp
        var t: f32 = -rim;
        while (t <= rim) : (t += o.r0) {
            const jitter = rng.signed() * 1.6;
            self.at(o.pick(rng), t + jitter, -rim - rng.range(0, 2.5), 180 + rng.signed() * 7, self.ridge(o, t, rng), rng);
            self.at(o.pick(rng), t - jitter, rim + rng.range(0, 2.5), 0 + rng.signed() * 7, self.ridge(o, t + 91, rng), rng);
            self.at(o.pick(rng), rim + rng.range(0, 2.5), t + jitter, 90 + rng.signed() * 7, self.ridge(o, t + 213, rng), rng);
            self.at(o.pick(rng), -rim - rng.range(0, 2.5), t - jitter, 270 + rng.signed() * 7, self.ridge(o, t + 347, rng), rng);
        }
        // Talus and scrub spilling off the feet of the walls, so the base isn't a clean line.
        // Kept INSIDE half−4: the cliff mesh has its own talus reaching ~4 m in, and a boulder
        // dropped into that shows as a wrong-coloured lump growing out of the rock.
        var i: i32 = 0;
        while (i < o.n) : (i += 1) {
            const along = rng.range(-rim, rim);
            const off = rng.range(self.m.half - 20, self.m.half - 4);
            const pos: [2]f32 = switch (rng.intn(4)) {
                0 => .{ along, -off },
                1 => .{ along, off },
                2 => .{ off, along },
                else => .{ -off, along },
            };
            const kind: Kind = if (rng.float() < 0.45) .boulder else if (rng.float() < 0.7) .rocks else .bush;
            self.at(kind, pos[0], pos[1], rng.range(0, 360), rng.range(0.8, 1.5), rng);
        }
    }

    // Segment scale as a function of WHERE ALONG the wall it sits: two long sines (~90 m and
    // ~37 m) plus a little noise. Purely random per-segment scale gives the crest hedge-trimmer
    // jitter; summed long waves read as topography — headlands and saddles you see coming.
    fn ridge(self: *Placer, o: *const wf.Op, along: f32, rng: *mathx.Rng) f32 {
        _ = self;
        const mid = (o.sLo + o.sHi) * 0.5;
        const amp = (o.sHi - o.sLo) * 0.5;
        return mid + amp * (0.62 * mathx.sinf(along * 0.070) + 0.31 * mathx.sinf(along * 0.170 + 1.9)) + rng.signed() * amp * 0.16;
    }

    // ── the seeded ground cover ─────────────────────────────────────────────────────────
    // A stratified scatter over the whole world: one candidate per LATTICE cell at a jittered
    // position, so coverage is even without the O(n·m) rejection sampling the small world used.
    // Kind follows the ZONE it lands in; DENSITY follows that zone's peak times the cover field.
    fn cover(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        const pitch = o.r0;
        if (pitch < 0.1) return;
        const half = self.m.half;
        const n: i32 = @intFromFloat(@ceil(2 * half / pitch));
        var iz: i32 = 0;
        while (iz < n) : (iz += 1) {
            var ix: i32 = 0;
            while (ix < n) : (ix += 1) {
                const bx = -half + (@as(f32, @floatFromInt(ix)) + 0.5) * pitch;
                const bz = -half + (@as(f32, @floatFromInt(iz)) + 0.5) * pitch;
                const x = bx + rng.signed() * pitch * 0.48;
                const z = bz + rng.signed() * pitch * 0.48;
                const zone = self.m.zoneAt(x, z) orelse continue;
                if (rng.float() > zone.density * coverField(x, z)) continue;
                if (self.m.inClearing(x, z)) continue;
                // Water uses a TIGHTER inset than a belt's: reeds may stand at the rim, but
                // nothing grows mid-lake.
                if (self.e.inWater(x, z, 0.97)) continue;
                if (self.m.onRunway(x, z)) continue;
                // The grid, walked IN PLACE — see `blockedNear`. This is the ~29,000-candidate loop
                // whose copying it exists to delete, and it is deliberately LAST: every cheaper
                // rejection above (the density gate alone drops ~a third) is a query never made.
                if (self.e.blockedNear(v3(x, SOLID_PROBE_Y, z), SOLID_PROBE_M, SOLID_PROBE_R)) continue;
                // A mix-less zone grows nothing (the accessor says so rather than indexing an
                // `undefined` slot — see wf.Zone.pick).
                const kind = zone.pick(rng) orelse continue;
                self.at(kind, x, z, rng.range(0, 360), rng.range(o.sLo, o.sHi), rng);
            }
        }
    }
};

// (A `localToWorld` helper lived here and had NO caller: `buildSolids` carries the prop-local →
// world transform itself, and deliberately, because it hoists the one cos/sin per INSTANCE across
// all of that kind's parts rather than per part. bake.zig keeps its own copy for the same
// convention — local +X → (cos, −sin), local +Z → (sin, cos) — and that one is live.)

// ── THE COVER FIELD (owner's law: vary the density, a lot) ─────────────────────────────
// A per-region density CONSTANT gives every square metre the same cover, and the result is a carpet:
// uniformly thick, nowhere to walk, nothing to notice. Real ground has clearings you can see across and
// thickets you go round, and that difference is what makes a plain read as a place, not a texture.
//
// So the region number is the PEAK and this field scales it: two octaves of value noise (~34 m clearings,
// broken up at ~11 m) pushed toward the extremes so it spends its time near 0 or near 1 rather than
// pooling in the middle. Mean ~0.62, which is also the overall thin-out. The SAME field drives the
// structure belts, so a clearing is a clearing for everything standing in it.
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

// ── the indexes ────────────────────────────────────────────────────────────────────────

// Footprint colliders for every solid prop: each kind's local Part list, rotated by the
// instance yaw and scaled. Each solid carries its part's own TOP height, so arrows thunk into
// a chapel wall but arc clean over a causeway kerb.
fn buildSolids(e: *Env) void {
    // RESET, so this is idempotent: materialize runs it twice (once for the cover scatter to
    // query, once after, in case a later op added colliders) and an appending version silently
    // doubled every footprint in the world.
    e.nsolids = 0;
    for (e.props[0..e.nprops]) |pr| {
        const nfo = props.info(pr.kind);
        const s = pr.scale;
        const th = mathx.radians(pr.yaw);
        const c = mathx.cosf(th);
        const sn = mathx.sinf(th);
        for (nfo.parts) |part| {
            if (e.nsolids >= MAX_SOLIDS) @panic("env: MAX_SOLIDS exceeded — raise the cap");
            var sol = collision.capsule(
                pr.pos.x + s * (part.ax * c + part.az * sn),
                pr.pos.z + s * (-part.ax * sn + part.az * c),
                pr.pos.x + s * (part.bx * c + part.bz * sn),
                pr.pos.z + s * (-part.bx * sn + part.bz * c),
                part.r * s,
            );
            sol.h = part.h * s;
            sol.surf = nfo.surf; // …and what it is made of, for whatever hits it (see collision.Surface)
            // A LEANING prop's footprint goes WITH it, or you bump into air beside a tipped trunk and
            // walk through the trunk itself. Push-out is 2D — ONE footprint for the whole height — so it
            // sits where the tilt puts the collider's MID height, and the shift is capped at the part's
            // own radius so a footprint can never wander off the mass it belongs to.
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
    // CSR over the cells each solid's footprint touches (counting sort, two passes).
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

// The cells a solid's expanded footprint covers. Insertion by BBOX (not just the centre) is
// what makes nearSolids exact-enough: a query can then never miss a solid it overlaps.
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

// Bucket every prop into its cell, twice: once into the structure index, once into the flora
// index. Same counting-sort shape as the solid grid.
fn indexProps(e: *Env) void {
    fillIndex(e, &e.stx, false);
    fillIndex(e, &e.flx, true);
}

fn fillIndex(e: *Env, idx: *Index, want_flora: bool) void {
    // ZERO the per-cell maxima first: they are `max`-folded below so they must start low, and they do NOT
    // arrive zeroed — Env is built IN PLACE inside a Game from `alloc.create`, so `Index`'s struct-literal
    // defaults never run and these three arrays are raw heap bytes. MEASURED, a ReleaseFast build without
    // these lines still culled to the same 985 draws / 204 cells, so the garbage folded away harmlessly —
    // but that is luck: a garbage-HIGH view/bound makes the per-cell reject always pass, silently
    // disabling the first and cheapest culling stage. Empty cells are safe either way, since drawIndexed
    // skips them before reading any maximum.
    idx.bound = [_]f32{0} ** NCELL;
    idx.view = [_]f32{0} ** NCELL;
    idx.top = [_]f32{0} ** NCELL;
    // The vertical extent folds the OTHER way (a min and a max about the datum), so it starts at the
    // datum rather than at zero-the-sentinel — an empty cell then has an empty span, not a 20 m one.
    idx.ylo = [_]f32{0} ** NCELL;
    idx.yhi = [_]f32{0} ** NCELL;
    var counts = [_]u32{0} ** NCELL;
    for (e.props[0..e.nprops]) |pr| {
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
    for (e.props[0..e.nprops], 0..) |pr, pi| {
        const nfo = props.info(pr.kind);
        if (nfo.flora != want_flora) continue;
        const c = cellOf(pr.pos.x, pr.pos.z);
        idx.items[cursor[c]] = @intCast(pi);
        cursor[c] += 1;
        idx.bound[c] = mathx.maxF(idx.bound[c], nfo.bound * pr.scale);
        idx.view[c] = mathx.maxF(idx.view[c], nfo.view);
        idx.top[c] = mathx.maxF(idx.top[c], nfo.top * pr.scale);
        idx.ylo[c] = mathx.minF(idx.ylo[c], pr.pos.y);
        idx.yhi[c] = mathx.maxF(idx.yhi[c], pr.pos.y);
    }
}

// ── tests ──────────────────────────────────────────────────────────────────────────────
// These cover the pure geometry — the culler and the grid — which is where a silent mistake
// costs the most (a prop that vanishes on screen, or a wall you walk through). They need no
// GPU, so they run under `zig build test`.

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
    // EVERY orientation, because the first version of fromCamera assumed a handedness for the
    // camera basis, was right for the pencil-and-paper case and inverted for the real one — and
    // an inverted culler draws an EMPTY WORLD. A test that only checks one heading cannot see
    // that: the +Z case below is precisely the one that used to pass while the game was blank.
    const headings = [_]rl.Vector3{
        v3(0, 0, 1), v3(0, 0, -1), v3(1, 0, 0), v3(-1, 0, 0), // the four cardinals
        v3(0.7, -0.25, 0.7), v3(-0.6, -0.3, 0.74), // pitched down, like the real over-shoulder rig
        v3(0.1, -0.97, 0.1), // near-straight-down, like the top-down attack shot
    };
    for (headings) |h| {
        const eye = v3(3, 2, -4); // deliberately not the origin
        const vw = viewLooking(eye, mathx.addV(eye, h));
        const ahead = mathx.addV(eye, mathx.scaleV(h, 20));
        const behind = mathx.addV(eye, mathx.scaleV(h, -20));
        try std.testing.expect(vw.visible(ahead, 0.5, 100)); // dead ahead
        try std.testing.expect(!vw.visible(behind, 0.5, 100)); // straight behind
        try std.testing.expect(!vw.visible(ahead, 0.5, 5)); // ahead but past the view distance
        try std.testing.expect(vw.visible(ahead, 0.5, 250)); // …same prop, longer view distance
        // A colossus centred outside the frustum still has geometry inside it — the case a
        // naive centre-point test drops, which shows as a cliff face popping at the screen edge.
        const wide = mathx.addV(ahead, mathx.scaleV(mathx.normV(cross(h, v3(0, 1, 0))), 30));
        try std.testing.expect(!vw.visible(wide, 0.5, 100));
        try std.testing.expect(vw.visible(wide, 26.0, 100));
    }
}

test "the culler accepts the full width of the screen, not just the axis" {
    // A prop out at the horizontal edge of a 16:10 45-deg-vertical frustum must survive: too
    // tight a horizontal angle silently thins the sides of every frame.
    const vw = viewLooking(v3(0, 0, 0), v3(0, 0, 1));
    const hf = std.math.atan(@tan(mathx.radians(45.0) * 0.5) * 1.6);
    const edge = v3(@tan(hf * 0.94) * 40.0, 0, 40); // 94% of the way to the edge, dead centre vertically
    try std.testing.expect(vw.visible(edge, 0.0, 100));
    try std.testing.expect(vw.visible(v3(-edge.x, 0, edge.z), 0.0, 100)); // …and the other side
}

test "the shadow cull keeps a distant TALL caster whose shadow still reaches the box" {
    const focus = v3(0, 0, 0);
    // Distances DERIVED from SHADOW_BOX, not literals: this said "60 m out" when SHADOW_ORTHO was 44
    // (half-diagonal ~31 m). At 108 the half-diagonal is ~76 m, so 60 m is INSIDE the box and even a grass
    // tuft there casts into it — the literal quietly stopped meaning "outside" and the assertion inverted.
    const outside = SHADOW_BOX + 10.0; // just beyond the box's own corner
    // A 15 m cliff out there is outside the box, but at this sun elevation its shadow travels
    // ~23 m — plus its own bulk, that reaches in. Dropping it (which a plain distance cull
    // would) deletes a real shadow from the frame.
    try std.testing.expect(castsInto(focus, v3(outside, 0, 0), 18.0, 15.5));
    // A grass-height prop the same distance out cannot possibly reach.
    try std.testing.expect(!castsInto(focus, v3(outside, 0, 0), 0.9, 0.8));
    // …and a tall one far enough out is genuinely irrelevant.
    try std.testing.expect(!castsInto(focus, v3(SHADOW_BOX + 60.0, 0, 0), 18.0, 15.5));
    // The sanity floor the whole cull rests on: anything INSIDE the box casts, whatever its size.
    try std.testing.expect(castsInto(focus, v3(SHADOW_BOX - 10.0, 0, 0), 0.2, 0.2));
}

test "grid cells round-trip a world position" {
    try std.testing.expectEqual(cellOf(0, 0), cellOf(1, 1)); // same cell, CELL is 16
    const c = cellOf(-100, 55);
    const centre = cellCentre(c);
    try std.testing.expect(@abs(centre.x - (-100)) <= CELL * 0.5);
    try std.testing.expect(@abs(centre.z - 55) <= CELL * 0.5);
    // Out-of-grid positions clamp into the edge cell instead of indexing off the end.
    try std.testing.expect(cellOf(-9999, 9999) < NCELL);
    try std.testing.expect(cellOf(9999, -9999) < NCELL);
}

test "a solid's cell iterator covers its whole footprint" {
    // A cliff-sized capsule spanning a cell boundary must be inserted into every cell it
    // touches, or a query from the neighbouring cell misses it and you walk through rock.
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

// ── ELEVATION ──────────────────────────────────────────────────────────────────────────
// A test Env is ~1 MB of flat arrays, so these allocate one rather than putting it on the stack. Only
// the height field is filled in: nothing below touches props, the grid or the GPU.
fn envWithRamp(rise: f32) !*Env {
    const e = try std.testing.allocator.create(Env);
    e.* = .{ .ground = undefined, .models = undefined };
    e.heightHalf = wf.DEFAULT_HALF;
    e.heightAny = true;
    // Height rises with x at `rise` metres per metre — a uniform slope, so the expected answer at any
    // point is arithmetic rather than a lookup.
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
        try std.testing.expectApproxEqAbs(@as(f32, 0.1), up.x, 1e-4); // the whole step happened
    }
    // A 60 deg face (tan 1.73) — past MAX_SLOPE, so the climb is refused outright.
    {
        const e = try envWithRamp(1.73);
        defer std.testing.allocator.destroy(e);
        try std.testing.expect(!e.walkableAt(0, 0));
        const up = e.walkStep(v3(0, 0, 0), v3(1, 0, 0), 0.1);
        try std.testing.expectApproxEqAbs(@as(f32, 0), up.x, 1e-4);
        // …but DOWNHILL is never refused. A rule that blocked both would trap an actor who somehow
        // ended up on a cliff, which is what a spawn on one is.
        const down = e.walkStep(v3(0, 0, 0), v3(-1, 0, 0), 0.1);
        try std.testing.expectApproxEqAbs(@as(f32, -0.1), down.x, 1e-4);
        // …and ACROSS the face slides at full pace rather than sticking: walking into a cliff at an
        // angle has to leave you moving, or a hillside reads as a set of invisible corners.
        const across = e.walkStep(v3(0, 0, 0), mathx.normV(v3(1, 0, 1)), 0.1);
        try std.testing.expect(@abs(across.z - 0.1) < 0.02); // kept the step's LENGTH along z
        try std.testing.expect(across.x < 0.02); // …and gave up the uphill part of it
    }
}

test "THE STEP RULE IS FRAME-RATE INDEPENDENT — a wall cannot be ratcheted up 0.4 m at a time" {
    // THE bug this exists for. `STEP_UP` says a rise under 0.45 m is always steppable, and measured
    // against the FRAME'S OWN travel that is true of every 1 mm step a 240 fps hero takes into a
    // vertical cliff — so he would climb it at tens of metres a second, faster the better the machine.
    // The fixed `STEP_PROBE` lookahead is the fix, and this pins it across four frame rates.
    const e = try envWithRamp(1.73); // 60 deg: not walkable at any dt
    defer std.testing.allocator.destroy(e);
    for ([_]f32{ 1.0 / 30.0, 1.0 / 60.0, 1.0 / 144.0, 1.0 / 1000.0 }) |dt| {
        var p = v3(0, 0, 0);
        var i: usize = 0;
        while (i < 200) : (i += 1) p = e.walkStep(p, v3(1, 0, 0), 6.0 * dt);
        try std.testing.expectApproxEqAbs(@as(f32, 0), p.x, 1e-3);
    }
}

test "a SLIGHT STEP is always taken, however steep the face carrying it" {
    // The owner's ask, and the other half of the anti-jank story: a low ledge is a step, not a wall. Two
    // terraces with a single riser between them, authored at 0.5 m — two quantisation steps, which is the
    // tallest ledge STEP_UP is meant to let through.
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
    const x0 = -e.heightHalf + @as(f32, @floatFromInt(mid)) * step - step * 1.5; // just short of the lip
    var p = v3(x0, 0, 0);
    var i: usize = 0;
    while (i < 120) : (i += 1) p = e.walkStep(p, v3(1, 0, 0), 6.0 / 60.0);
    try std.testing.expect(p.x > x0 + 4.0); // he is well past it
    try std.testing.expectApproxEqAbs(LEDGE, e.groundAt(p.x, p.z) - GROUND_Y, 1e-3); // …and UP it
    // …and it is `STEP_UP` doing the work, not the slope limit having a lucky day: the riser is one
    // lattice cell, so as a pure gradient question it is right on the edge, and a rule that only asked
    // about slope would hold at the lip depending on where in the cell the probe landed.
    try std.testing.expect(LEDGE <= STEP_UP);

    // A THREE-STEP ledge (0.75 m) is a wall. This is the other side of the same number, and what stops
    // "always steppable" from quietly meaning "climbs anything one riser at a time".
    for (0..wf.HEIGHT_N) |iz| {
        for (0..wf.HEIGHT_N) |ix| {
            e.heightField[iz * wf.HEIGHT_N + ix] = wf.heightByte(if (ix >= mid) 6.0 else 0.0);
        }
    }
    var q = v3(x0, 0, 0);
    i = 0;
    while (i < 120) : (i += 1) q = e.walkStep(q, v3(1, 0, 0), 6.0 / 60.0);
    try std.testing.expect(e.groundAt(q.x, q.z) - GROUND_Y < 0.01); // still on the lower terrace
}

test "env's ground agrees with the MAP's to the millimetre" {
    // Two owners, one field: the map holds what the editor sculpts, env holds the copy the terrain mesh
    // was built from and every actor stands on. They share `wf.sampleHeight` precisely so a hero cannot
    // walk a centimetre off the mesh he can see — this is that claim, checked.
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
        // env adds the DATUM (the 1 cm the old flat plane sat at) and the map does not, which is the
        // only difference there may ever be between them.
        try std.testing.expectApproxEqAbs(m.heightAt(p[0], p[1]) + GROUND_Y, e.groundAt(p[0], p[1]), 1e-5);
    }
    // A FLAT map is the old world exactly: the datum, everywhere, with no field consulted at all.
    e.heightAny = false;
    try std.testing.expectApproxEqAbs(GROUND_Y, e.groundAt(-30, 40), 1e-6);
}

test "rayGround finds the surface of a hill, not the plane under it" {
    // The editor aims every click with this. On sculpted ground a plane solve lands metres from where
    // the pointer is looking, which reads as the whole editor having gone out of register.
    const e = try envWithRamp(0.5); // a steady 26 deg slope rising with x
    defer std.testing.allocator.destroy(e);
    // Straight down from high above a point 40 m along the ramp: the hit must be that point, at its own
    // height (40 * 0.5 = 20 m, plus the datum).
    const hit = e.rayGround(v3(40, 200, 0), v3(0, -1, 0)) orelse return error.NoHit;
    try std.testing.expectApproxEqAbs(@as(f32, 40), hit.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 20) + GROUND_Y, hit.y, 0.05);
    // An OBLIQUE ray hits the near face of the slope, so its x is short of where the flat-plane solve
    // would have put it — that difference IS the bug this fixes.
    const flatT = (GROUND_Y - 60.0) / -0.5; // the plane answer for the ray below
    const oblique = e.rayGround(v3(-60, 60, 0), mathx.normV(v3(1, -0.5, 0))) orelse return error.NoHit;
    try std.testing.expect(oblique.x < -60 + flatT * 0.9);
    try std.testing.expectApproxEqAbs(e.groundAt(oblique.x, oblique.z), oblique.y, 0.05);
    // Aimed at the sky: nothing, rather than a point behind the eye.
    try std.testing.expect(e.rayGround(v3(0, 10, 0), mathx.normV(v3(0, 1, 0))) == null);
}

test "the cover field actually varies — real clearings and real thickets" {
    // The point of the field is VARIANCE. A field that never dips near zero has no clearings in
    // it and a field that never reaches its peak has no thickets, and either way the world goes
    // back to being one uniform carpet — which is the exact thing this replaced.
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
    try std.testing.expect(lo <= 0.02); // somewhere is bare
    try std.testing.expect(hi >= 1.15); // somewhere is choked
    const mean = sum / n;
    try std.testing.expect(mean > 0.45 and mean < 0.80); // …and it is not secretly a constant
}

test "the SHIPPED map parses, and its zones cover every reachable position" {
    // Against the real file, not a fixture. The map IS the world now, so a map that fails to
    // parse is a game that starts in a void — and this is the cheapest place to find out, well
    // before a launch. Every point inside the playable bounds must resolve to a zone with a
    // non-empty flora mix and a plausible density; a gap is a bald patch you can walk to.
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    var line: usize = 0;
    wf.load(wf.START_MAP, m, &line) catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest; // run from another cwd
        std.debug.print("{s} failed to parse at line {d}\n", .{ wf.START_MAP, line });
        return e;
    };
    try std.testing.expect(m.nops > 0);

    var x: f32 = -m.half;
    while (x <= m.half) : (x += 7) {
        var z: f32 = -m.half;
        while (z <= m.half) : (z += 7) {
            const zone = m.zoneAt(x, z) orelse return error.NoZone;
            try std.testing.expect(zone.nmix > 0);
            try std.testing.expect(zone.density > 0.1 and zone.density <= 1.0);
            for (zone.mix[0..zone.nmix]) |k| try std.testing.expect(props.info(k).flora);
        }
    }
}

test "every generator op in the shipped map has its own seed" {
    // Two ops sharing a seed AND a shape would place the same instances twice, and a seed left
    // at zero is an op nobody gave a stream to. Both are silent — the world just looks subtly
    // repetitive — so they are asserted rather than eyeballed.
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    var line: usize = 0;
    wf.load(wf.START_MAP, m, &line) catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest;
        return e;
    };
    for (m.slice(), 0..) |o, i| {
        if (o.op == .at) continue; // literals draw nothing
        try std.testing.expect(o.seed != 0);
        for (m.slice()[0..i]) |prev| {
            if (prev.op != .at) try std.testing.expect(prev.seed != o.seed);
        }
    }
}

test "the cliff ring stands outside the movement clamp, and inside the grid" {
    // PLAY_HALF (game.zig) insets the map's half; the rock must be beyond that or the player is
    // stopped by air with the cliff still ahead of them.
    try std.testing.expect(RIM_OUT > 0);
    // CLIFF_BOUND is a hand-copied mirror of the mesh's own bound, because MAX_HALF has to be a
    // comptime value and `props.info` is a runtime lookup. Pin them together or the ceiling
    // silently stops matching the rock it is sized for.
    try std.testing.expectApproxEqAbs(CLIFF_BOUND, props.info(.cliff).bound, 1e-4);
    // The DEFAULT map must fit inside what the grid can index, or everything past the boundary
    // piles into the edge cells and a cell that cannot be rejected is thirty props tested one by
    // one — the culling still works, it just stops being cheap.
    try std.testing.expect(wf.DEFAULT_HALF <= MAX_HALF);
    // …and the ground quad has to clear the far corner plus the haze reach, or the plane's own
    // edge shows as a hard line under the sky from the corners of the world.
    try std.testing.expect(GROUND_HALF > wf.DEFAULT_HALF + 200);
}

test "replaying the SHIPPED map produces a stable world" {
    // That `materialize` expands the real map, and expands it the SAME way every time. It is pure array
    // work (the models are never touched), so a heap Env with undefined meshes replays it fine.
    //
    // COUNTS are pinned because the scatter is a chain of rejections and any change to one moves the prop
    // list silently — "the world is unchanged" has to be checkable rather than argued. Re-materializing
    // must also be IDEMPOTENT: the editor runs this on every edit, and `buildSolids` resetting is what
    // stops it doubling every collider in the world.
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    var line: usize = 0;
    wf.load(wf.START_MAP, m, &line) catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest; // run from another cwd
        return e;
    };
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

    // …and the numbers themselves, so a scatter that quietly gains or loses instances is a failing
    // test rather than something you notice in a screenshot months later. Update them DELIBERATELY,
    // together with whatever map or placement change moved them.
    //
    // RE-PINNED (17292/1836/34 → 17253/1859/37) after they were found STALE: the props rework that
    // added kinds and re-measured bounds moved all three and left this test red, and a permanently
    // failing pin cannot catch the NEXT drift — which is the only thing it is for. Both directions
    // are consistent with that change: more kinds carrying colliders and fires (solids +23, lights
    // +3), and different bounds changing how many scatter candidates the solid probe rejects
    // (props −39). If you move them again, move these with it in the same commit.
    //
    // RE-PINNED TWICE MORE for THE MAP changing under it, not the code — the owner edits it while playing
    // (two cliff4s and a lean, then a chest). `git diff worlds/` BEFORE suspecting the engine: a world
    // edit's numbers add up (two cliffs = +4 solids, exactly two `cliffParts`), a code fault's do not.
    try std.testing.expectEqual(@as(usize, 17205), props0);
    try std.testing.expectEqual(@as(usize, 1864), solids0);
    try std.testing.expectEqual(@as(usize, 37), lights0);
}

test "the map's half drives the world, not a constant in this file" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    m.blank("sized");
    // `blank` writes the default, and a map that says something else is obeyed. This is the
    // regression that mattered: the clamp used to be comptime, so a resized map moved its cliffs
    // and its ground cover and left the hero walled in at the old bound.
    try std.testing.expectApproxEqAbs(wf.DEFAULT_HALF, m.half, 1e-4);
    m.half = 120;
    try std.testing.expectApproxEqAbs(@as(f32, 118), m.half - PLAY_INSET, 1e-4);
}

