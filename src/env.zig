const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const collision = @import("collision.zig");
const props = @import("props.zig");
const wf = @import("worldfmt.zig");
const chestmod = @import("chest.zig"); // for `Site` alone — env finds the boxes, chest.zig runs them
const pickupmod = @import("pickup.zig"); // …and the glows, on exactly the same terms
const item = @import("item.zig"); // …and for what a box is carrying, which only its own test reads
const restmod = @import("rest.zig");

const v3 = mathx.v3;
const Kind = props.Kind;


// THE WORLD'S SIZE IS THE MAP'S (`wf.Map.half`), never a constant here.
pub const RIM_OUT: f32 = 6.0;
pub const PLAY_INSET: f32 = 2.0;
/// The largest `half` the grid can index without cells clamping together.
pub const MAX_HALF: f32 = GRID_HALF + CELL - RIM_OUT - CLIFF_BOUND;

comptime {
    // …AND THE LOADER REFUSES ANYTHING BIGGER.
    std.debug.assert(MAX_HALF >= wf.MAX_DECLARED_HALF);
}
/// The cliff mesh's own bounding radius, which sticks out past the rim it is placed on.
const CLIFF_BOUND: f32 = 18.0;
const GROUND_HALF: f32 = wf.DEFAULT_HALF + 220.0;

const MAX_PROPS = 24576;
const MAX_SOLIDS = 8192;
const MAX_SOLID_REFS = 4 * MAX_SOLIDS; // a long solid's bbox spans several cells, one ref each
const MAX_LIGHTS = 192; // fires in the world; gfx.MAX_LIGHTS of them reach the GPU per frame
const MAX_DRESSED = 64; // instances carrying a veil and/or a stow — see Env.dressItems

// 40 a side = 640 m, covering a 280 m map's cliff ring (286 + 18 of cliff bound) with room over. The arrays
// are BSS and the per-frame cost is one loop of four plane tests, so 1,600 cells is not measurable.
const CELL: f32 = 16.0;
const GRID_N: usize = 40;
const GRID_SPAN: f32 = CELL * @as(f32, @floatFromInt(GRID_N));
const GRID_HALF: f32 = GRID_SPAN * 0.5;
const NCELL: usize = GRID_N * GRID_N;
// Turns a square's half-width into the radius of the sphere enclosing it.
const HALF_DIAG: f32 = @sqrt(0.5);
const CELL_CIRCUM: f32 = CELL * HALF_DIAG; // centre-to-corner of a cell, for sphere tests

const SHADOW_BOX: f32 = gfx.SHADOW_ORTHO * HALF_DIAG;

const LIGHT_REACH: f32 = 90.0;

// THE OCCLUDERS — the props the camera has to see the hero THROUGH, thinned by the shader's sieve.
/// How many instances the fade can have IN FLIGHT — the ones thinning plus the ones easing back, which is
/// why it is larger than any sight line needs. Full, and the THINNEST ASK TAKES A SLOT OFF SOMETHING STILL
/// SOLID (`wantFade`): first-come at 16 meant the trunk squarely over his head lost to the cell walk.
pub const OCCL_MAX = 64;
/// Seconds to reach the thinness the geometry is asking for, and to come back from it. OUT IS SLOWER on
/// purpose: a trunk hardening back to solid over the hero is the uglier half of the transition, and the
/// eye forgives a lag in getting out of the way far more readily than a pop into it.
const OCCL_IN: f32 = 0.16;
const OCCL_OUT: f32 = 0.34;
/// Where a fade is near enough to solid to go down the opaque path: the blend is indistinguishable there and
/// the prop is better off writing depth like everything else. Below it, `drawThinned` owns it.
const FADE_SOLID: f32 = 0.999;
// Raw GL factors for `drawThinned`'s depth-only pass; rlgl takes them unwrapped.
const GL_ZERO: i32 = 0;
const GL_ONE: i32 = 1;
const GL_FUNC_ADD: i32 = 0x8006;
/// How fast the ramp runs where the value already sits: full speed across the middle of the travel, down to
/// this share of it at solid and at the floor. Never 0, or a fade would never leave either end.
const EASE_ENDS = 0.3;
fn easeAt(u: f64) f64 {
    return EASE_ENDS + (1.0 - EASE_ENDS) * 4.0 * u * (1.0 - u);
}
fn easeShape(fade: f32) f32 {
    return @floatCast(easeAt(mathx.clampF((fade - OCCL_FLOOR) / (1.0 - OCCL_FLOOR), 0, 1)));
}
/// …scaled so a full traverse still takes OCCL_IN / OCCL_OUT: the mean of 1/shape over the travel.
const EASE_NORM: f32 = blk: {
    @setEvalBranchQuota(40000);
    const N = 4096;
    var acc: f64 = 0;
    for (0..N) |i| acc += 1.0 / easeAt((@as(f64, @floatFromInt(i)) + 0.5) / N);
    break :blk @floatCast(acc / N);
};
/// A thinned occluder NEVER disappears: you must still be able to tell a tree is there.
const OCCL_FLOOR: f32 = 0.28;
/// HOW MUCH OF HIM IT HAS TO HIDE BEFORE IT THINS AT ALL (owner's rule). A COVERAGE FIGURE AND NOTHING
/// ELSE: with the depth ramp multiplied in first, a mass right in front of him was discounted under the
/// threshold and stayed solid at the one moment it was in the way.
const OCCL_MIN: f32 = 0.15;
/// …and where it is as thin as it gets. Between the two it eases on its own as the camera swings,
/// which is what leaves the whole thing stateless.
const OCCL_FULL: f32 = 0.55;
/// The hero's own screen box, in metres — what "a share of him" is measured against.
const HERO_HALF_W: f32 = 0.42;
const HERO_HALF_H: f32 = 0.90;
/// How far past its own collider a standing mass still blocks the view — the bark it does not collide
/// with and the slack that keeps the fade from snapping on at the edge. ONLY FOR KINDS WITH NO `occl`
/// LIST: a fixed skirt cannot describe a canopy, which is why the trees carry their own volumes now.
const OCCL_SKIRT: f32 = 0.9;
/// …and the fallback for a fadeable kind with NO colliders: a share of its bound, since the bound is a
/// canopy's whole spread and a leaf nine metres off the sight line is not in the way of anything.
const OCCL_GIRTH: f32 = 0.55;
/// How far outside the sight line's own box an occluder's centre can sit — one cell covers the widest
/// canopy in the table at any scale the editor is likely to stamp.
const OCCL_REACH: f32 = CELL;
/// Metres in front of him over which a mass stops being in the way — a BAND, not a plane. Cut at his depth
/// exactly, a trunk the camera walks past goes fully thinned to fully solid in one frame, right over him.
const OCCL_DEPTH_BAND: f32 = 1.6;

pub const MAX_NEAR = 160;

const GROUND_Y: f32 = 0.01;

// The ground is a HEIGHTFIELD (`wf.Map.height`, 2.5 m lattice, sculpted in the editor).
const TCHUNK: usize = 16;
/// Tiles per axis, rounded up so the last one carries the remainder.
const TILES: usize = (wf.HEIGHT_N - 2) / (TCHUNK - 1) + 1;
const NTILES: usize = TILES * TILES;

/// How steep the ground may be and still be walked, as the TANGENT of the slope angle (rise over run). tan 40 deg
pub const MAX_SLOPE: f32 = 0.839;
pub const STEP_UP: f32 = 0.55;
/// The fixed distance the walkable test looks AHEAD, and the reason the rule is frame-rate independent.
pub const STEP_PROBE: f32 = 0.5;

/// HOW DEEP ANYTHING ON FOOT MAY WADE, in metres — CHEST HEIGHT (owner's call), the thorax at 0.760·H on
/// the 1.8 m rig. Past it the water is a WALL: there is no swimming and no drowning yet. Written out rather
/// than read off `hero.H` because env sits BELOW hero in the import graph and stays there.
pub const WADE_MAX: f32 = 1.37;

/// `foe.HERO_R`, written out for `WADE_MAX`'s reason and PINNED in `game.zig`, which can see both ends.
pub const HERO_R_PIN: f32 = 0.36;

/// …AND THE COLOUR IS THE ONLY WARNING HE GETS, so it is DERIVED from that wall rather than set beside it.
/// Dug depth in metres → 0..1 of the shallow→deep ramp, reaching the deep tone exactly at `WADE_MAX`, so the
/// darkest water on the map is precisely the water he cannot walk into.
fn digTone(metres: f32) f32 {
    return mathx.clampF(metres / WADE_MAX, 0, 1);
}

const WATER_Y: f32 = 0.055;

// The distance transform's two working grids.
var scratchIn: [wf.WATER_CELLS]f32 = undefined;
var scratchOut: [wf.WATER_CELLS]f32 = undefined;

/// **HOW BIG A FACET OF COASTLINE IS, in metres**, and it is bounded at BOTH ends. Under about a field cell
/// there is nothing left to straighten; over about five the planar fit dips under the waterline mid-marsh,
/// and at 7 the tarn came apart into disconnected puddles.
pub const WATER_FACET: f32 = 3.6;

/// **HOW FAR THIS SHAPE MOVES THE WATERLINE AT THIS POINT, in metres**, positive pushing the water outward.
/// The coast's own share of `wf.Edge`, and it is the same eight names the soil uses because they are the
/// same eight questions — but the answers are a coastline's, not a floor's.
///
/// **NOTHING UNDER ABOUT 0.7 m DOES ANYTHING.** The distance transform is quantised to whole cells, so no
/// cell is nearer the line than half a cell (1.25 m here) and a warp smaller than that can never flip one.
/// That is why these are metres and not the soil's sub-metre wobbles.
fn coastWarp(e: wf.Edge, x: f32, z: f32) f32 {
    return switch (e) {
        // A shore you cannot find the edge of. No warp — the width is `coastBand`'s say, not this one's.
        .blend => 0,
        // What a lake does on its own: a slow wander, a couple of metres either way.
        .natural => (vnoise2(x / 13.0, z / 13.0) - 0.5) * 4.4,
        // Reeds and shallows picking at it — quicker, and it only ever eats INTO the land.
        .frayed => (vnoise2(x / 5.5 + 12.3, z / 5.5 - 7.1) - 0.5) * 3.0,
        // A torn rocky shore: fast and deep, two octaves so it has both bays and bites.
        .jagged => (vnoise2(x / 6.0 + 3.3, z / 6.0 + 9.9) - 0.5) * 7.0 +
            (vnoise2(x / 2.2 - 5.0, z / 2.2 + 4.0) - 0.5) * 2.6,
        // Built: the line is exactly where it was painted.
        .straight => 0,
        // …and the same line taken to the grid, which is what a dock or a harbour wall runs on.
        .tiled => tiledCoast(x, z),
        // Regular bays, the one shape here that is deliberate rather than noisy.
        .scallop => (mathx.sinf(x * 0.34) + mathx.sinf(z * 0.34)) * 2.3,
        // A boggy fringe that breaks into separate pools — the tarn's own look, made authorable. The
        // high-frequency term is what detaches them, and it is why this is the one shape that may
        // legitimately disconnect water where every other one must not.
        .speckle => (vnoise2(x / 3.0 + 21.0, z / 3.0 - 17.0) - 0.5) * 8.0 - 1.4,
    };
}

/// The tiled coast snaps the waterline onto the lattice `facetWater` already works in, so a dock's edge and
/// the facets around it are the same grid rather than two that nearly agree.
fn tiledCoast(x: f32, z: f32) f32 {
    const g = WATER_FACET;
    const sx = x / g - @floor(x / g);
    const sz = z / g - @floor(z / g);
    // Distance to the nearer lattice line on each axis, pushed to whichever is closer — the line lands ON
    // the lattice instead of wherever the painted disc happened to stop.
    const dx = (0.5 - @abs(sx - 0.5)) * g;
    const dz = (0.5 - @abs(sz - 0.5)) * g;
    return -@min(dx, dz);
}

/// **HOW WIDE THE WET SAND IS**, as a multiple of `gfx.WATER_WET_OUT`. The shape's second say, and the only
/// thing that separates `blend` from `straight` — both leave the line alone and differ entirely in how far
/// the ground around it reads as soaked.
fn coastBand(e: wf.Edge) f32 {
    return switch (e) {
        .blend => 3.2, // a marsh margin: metres of ground that is neither
        .natural => 1.0,
        .frayed => 1.6,
        .jagged => 0.55, // rock does not soak
        .straight => 0.3, // a built bank, near enough dry to the edge
        .tiled => 0.3,
        .scallop => 1.2, // a beach
        .speckle => 2.2, // bog
    };
}

/// **THE COAST IS FACETED, NOT SMOOTHED** (owner: more of a low poly look). A bilinear field's iso-contour
/// is a CURVE; resampled onto a TRIANGULAR lattice the field is piecewise PLANAR, and a planar contour
/// inside a triangle is a STRAIGHT LINE — so the waterline comes out a polyline with corners.
///
/// **BAKED INTO THE FIELD, NOT DONE IN THE SHADER.** One field feeds the sheet, the wet sand and
/// `waterDepthAt`'s wading, so faceting in the fragment shader would be a coast you SEE in one place and
/// WALK INTO in another, up to half a facet apart.
fn facetWater(field: *[wf.WATER_CELLS]u8, half: f32) void {
    const N = wf.WATER_N;
    if (!(half > 0)) return;
    const cell = 2 * half / @as(f32, @floatFromInt(N));
    // A lattice finer than the field it samples straightens nothing, so this is a floor and not a taste.
    const facet = @max(WATER_FACET, cell * 1.2);

    // The ORIGINAL field has to survive the whole pass — every cell reads three lattice corners, and a
    // corner may sit in a cell this loop has already rewritten. `scratchIn` is free by now: the distance
    // transform it carried was spent in the encode loop above.
    const out = &scratchIn;
    for (0..N) |cz| {
        for (0..N) |cx| {
            const wx = -half + (@as(f32, @floatFromInt(cx)) + 0.5) * cell;
            const wz = -half + (@as(f32, @floatFromInt(cz)) + 0.5) * cell;
            const sx = wx / facet;
            const sz = wz / facet;
            const bx = @floor(sx);
            const bz = @floor(sz);
            const fx = sx - bx;
            const fz = sz - bz;
            // TWO TRIANGLES PER LATTICE SQUARE. Which one the point is in decides its three corners, and
            // the diagonal between them is what puts a CORNER in the coastline rather than a bend.
            var wa: f32 = undefined;
            var wb: f32 = undefined;
            var wc: f32 = undefined;
            var c0: [2]f32 = undefined;
            var c1: [2]f32 = undefined;
            var c2: [2]f32 = undefined;
            if (fx + fz > 1.0) {
                c0 = .{ 1, 0 };
                c1 = .{ 0, 1 };
                c2 = .{ 1, 1 };
                wa = 1 - fz;
                wb = 1 - fx;
                wc = fx + fz - 1;
            } else {
                c0 = .{ 0, 0 };
                c1 = .{ 1, 0 };
                c2 = .{ 0, 1 };
                wa = 1 - fx - fz;
                wb = fx;
                wc = fz;
            }
            const va = sampleField(field, half, cell, (bx + c0[0]) * facet, (bz + c0[1]) * facet);
            const vb = sampleField(field, half, cell, (bx + c1[0]) * facet, (bz + c1[1]) * facet);
            const vc = sampleField(field, half, cell, (bx + c2[0]) * facet, (bz + c2[1]) * facet);
            out[cz * N + cx] = wa * va + wb * vb + wc * vc;
        }
    }
    for (field, out) |*dst, v| dst.* = mathx.u8f(v);
}

/// Bilinear, not nearest: the lattice corners are arbitrary world positions rather than cell centres, and
/// nearest-sampling puts the field's own 2.5 m staircase back into what this pass exists to remove.
fn sampleField(field: *const [wf.WATER_CELLS]u8, half: f32, cell: f32, wx: f32, wz: f32) f32 {
    const N = wf.WATER_N;
    const maxI: f32 = @floatFromInt(N - 1);
    const tx = mathx.clampF((wx + half) / cell - 0.5, 0, maxI);
    const tz = mathx.clampF((wz + half) / cell - 0.5, 0, maxI);
    const x0: usize = @intFromFloat(@floor(tx));
    const z0: usize = @intFromFloat(@floor(tz));
    const x1 = @min(x0 + 1, N - 1);
    const z1 = @min(z0 + 1, N - 1);
    const ux = tx - @floor(tx);
    const uz = tz - @floor(tz);
    const v00: f32 = @floatFromInt(field[z0 * N + x0]);
    const v10: f32 = @floatFromInt(field[z0 * N + x1]);
    const v01: f32 = @floatFromInt(field[z1 * N + x0]);
    const v11: f32 = @floatFromInt(field[z1 * N + x1]);
    return mathx.lerpF(mathx.lerpF(v00, v10, ux), mathx.lerpF(v01, v11, ux), uz);
}

// `fade`/`fadeTo` are the only fields here the frame writes: how solid this instance IS and how solid the
// sight line wants it to be, both 1 unless it is standing between the lens and the hero (see markOccluders).
const Prop = struct {
    kind: Kind,
    pos: rl.Vector3,
    yaw: f32,
    scale: f32,
    lean: f32 = 0,
    leanDir: f32 = 0,
    op: u16 = 0,
    fade: f32 = 1,
    fadeTo: f32 = 1,
    /// **TAKEN OUT OF THE WORLD AT RUNTIME** — the item pickup alone today (`game.hidePickups`), and the ONE
    /// way a prop can stop existing without the world being re-materialized under it. A flag rather than a
    /// removal because every op index and every runtime site list is keyed to this array's ORDER.
    ///
    /// It sits beside `fade`, which the draw loop already tests per prop, so the cost is one bool compare where
    /// there was already a float one.
    gone: bool = false,
    /// …and HOW MUCH OF ITS SIZE IS LEFT, for a prop that is going. **SEPARATE FROM `scale`, which is the
    /// AUTHORED figure the op placed it at**: written into `scale` instead, the shrink was read straight back
    /// out by `pickupSites` as the site's own scale, so a glow taken in play and then looked at in the editor
    /// came home permanently shrunken — the fade compounding into the authoring.
    shrink: f32 = 1,
};

// A prop can stand OFF PLUMB: `lean` degrees toward `leanDir`, measured like every yaw here — (cos d, −sin d).

/// The world direction a lean tips TOWARD.
fn leanToward(dirDeg: f32) rl.Vector3 {
    const a = mathx.radians(dirDeg);
    return v3(mathx.cosf(a), 0, -mathx.sinf(a));
}

fn leanAxis(dirDeg: f32) rl.Vector3 {
    const d = leanToward(dirDeg);
    return v3(d.z, 0, -d.x);
}

/// How far sideways a point `up` metres up a leaning prop's axis ends up, as a world offset.
pub fn leanOffsetAt(lean: f32, dirDeg: f32, up: f32) rl.Vector3 {
    if (lean == 0) return mathx.zero3;
    const s = mathx.sinf(mathx.radians(lean)) * up;
    const d = leanToward(dirDeg);
    return v3(d.x * s, 0, d.z * s);
}

fn leanSwing(pr: *const Prop, up: f32) rl.Vector3 {
    return leanOffsetAt(pr.lean, pr.leanDir, up);
}

const FIELD_FLOOR: f32 = 0.35;

const SOLID_PROBE_Y: f32 = 0.2; // ankle height — under a causeway kerb's top, inside a wall's
const SOLID_PROBE_M: f32 = 0.35;
const SOLID_PROBE_R: f32 = 1.4;

/// The ground plane's height, for anything that has to draw ON it (the editor's gizmos).
pub fn groundY() f32 {
    return GROUND_Y;
}

// A fire's static description; the per-frame guttering is applied in uploadLights.
const WorldLight = struct { base: gfx.Light, flicker: f32, phase: f32 };

const Pool = struct { pos: rl.Vector3, radius: f32 };

// One CSR spatial index over a subset of the prop list.
const Index = struct {
    start: [NCELL + 1]u32 = [_]u32{0} ** (NCELL + 1),
    items: [MAX_PROPS]u32 = undefined,
    bound: [NCELL]f32 = [_]f32{0} ** NCELL, // max scaled bounding radius in the cell
    view: [NCELL]f32 = [_]f32{0} ** NCELL, // max view distance in the cell
    top: [NCELL]f32 = [_]f32{0} ** NCELL, // max scaled top height (shadow reach)
    // …and the cell's VERTICAL extent: the per-cell reject is a sphere about the cell's centre, and a cell
    // whose props stand 20 m up a hill is nowhere near a sphere centred at y = 0.
    ylo: [NCELL]f32 = [_]f32{0} ** NCELL,
    yhi: [NCELL]f32 = [_]f32{0} ** NCELL,
};

/// The camera's four frustum SIDE planes, all through the eye point, plus that point.
pub const View = struct {
    pos: rl.Vector3,
    n: [4]rl.Vector3, // inward normals: left, right, top, bottom

    pub fn fromCamera(cam: rl.Camera3D, aspect: f32) View {
        const fwd = mathx.normV(mathx.subV(cam.target, cam.position));
        // This camera's screen-right is world −X looking down +Z, so (right, up, fwd) is not the handedness
        // you would assume.
        const right = mathx.normV(cross(fwd, cam.up));
        const up = cross(right, fwd);
        // A couple of degrees of slack: a plane hugging the frustum exactly pops a prop whose authored
        // `bound` is a touch tight.
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
        const far = maxDist + rad;
        if (d.x * d.x + d.y * d.y + d.z * d.z > far * far) return false;
        for (self.n) |nn| {
            if (nn.x * d.x + nn.y * d.y + nn.z * d.z < -rad) return false;
        }
        return true;
    }
};

pub const Cull = union(enum) {
    /// The lit pass: the camera frustum + each kind's own view distance.
    view: View,
    /// The sun depth pass: the hero-tracking focus point of the shadow ortho box.
    sun: rl.Vector3,
};

pub const Env = struct {
    ground: rl.Model,
    models: [props.NK]rl.Model,
    veils: [props.NK]?rl.Model = [_]?rl.Model{null} ** props.NK,
    stows: [props.NK]?rl.Model = [_]?rl.Model{null} ** props.NK,
    stowed: bool = false,
    /// Every instance carrying a SECOND mesh — a veil, a stow, or both. ONE list: keying the stow pass off
    /// the veil list made "has a stow" mean "has a veil", so a kind given one without the other never drew.
    dressItems: [MAX_DRESSED]u32 = undefined,
    ndress: usize = 0,
    chestItems: [chestmod.CAP]u32 = undefined,
    nchests: usize = 0,
    /// …and the ITEM PICKUPS, its own list for the chests' reason: a second thing that holds loot is a second
    /// runtime list, and keying one off the other would make "is a pickup" mean "is a chest".
    pickupItems: [pickupmod.CAP]u32 = undefined,
    npickups: usize = 0,
    restItems: [restmod.CAP]u32 = undefined,
    nrests: usize = 0,
    // Kept so painted soil reaches its shader without threading a Scene pointer through every editor call.
    scene: ?*gfx.Scene = null,
    props: [MAX_PROPS]Prop = undefined,
    nprops: usize = 0,
    solid_buf: [MAX_SOLIDS]collision.Solid = undefined,
    nsolids: usize = 0,
    stx: Index = .{},
    flx: Index = .{},
    // This frame's thinned occluders, kept only so the next frame can hand them back solid.
    occl: [OCCL_MAX]u32 = undefined,
    noccl: usize = 0,
    // Solid grid: refs into solid_buf, a solid appearing in every cell its footprint touches.
    sgrid_start: [NCELL + 1]u32 = [_]u32{0} ** (NCELL + 1),
    sgrid_items: [MAX_SOLID_REFS]u32 = undefined,
    lights: [MAX_LIGHTS]WorldLight = undefined,
    nlights: usize = 0,
    pools: [8]Pool = undefined,
    npools: usize = 0,
    waterSheet: rl.Model = undefined,
    waterField: [wf.WATER_CELLS]u8 = [_]u8{gfx.WATER_SHORE} ** wf.WATER_CELLS,
    waterAny: bool = false,
    waterHalf: f32 = 0,
    waterMid: rl.Vector3 = mathx.zero3,
    waterSpan: rl.Vector3 = mathx.zero3,
    /// THE SCULPTED GROUND: the live copy of the map's height lattice, and the mesh built from it.
    heightField: [wf.HEIGHT_CELLS]u8 = [_]u8{wf.HEIGHT_ZERO} ** wf.HEIGHT_CELLS,
    heightHalf: f32 = wf.DEFAULT_HALF,
    heightAny: bool = false,
    /// One model per terrain tile, plus the SKIRT that carries the ground out to the haze.
    tiles: [NTILES]rl.Model = undefined,
    tileBuilt: [NTILES]bool = [_]bool{false} ** NTILES,
    /// Each tile's bounding sphere, for the draw cull: centre and radius in world space.
    tileMid: [NTILES]rl.Vector3 = [_]rl.Vector3{mathx.zero3} ** NTILES,
    tileRad: [NTILES]f32 = [_]f32{0} ** NTILES,
    skirt: rl.Model = undefined,
    skirtBuilt: bool = false,
    // Per-frame culling counters, surfaced by the debug Stats overlay.
    stat_draws: u32 = 0,
    stat_cells: u32 = 0,

    pub fn build(self: *Env, scene: *gfx.Scene) void {
        self.scene = scene;
        const shader = scene.shader;
        // Indexed by kind so the array and the kinds cannot drift out of lockstep.
        for (&self.models, props.INFO) |*m, row| m.* = row.build(shader);
        for (&self.veils, props.INFO) |*m, row| m.* = if (row.veil) |mesh| mesh(shader) else null;
        for (&self.stows, props.INFO) |*m, row| m.* = if (row.stow) |mesh| mesh(shader) else null;
        self.ground = terrain(shader, GROUND_HALF);
        self.waterSheet = waterQuad(shader, GROUND_HALF);
        self.nprops = 0;
        self.nsolids = 0;
        self.nlights = 0;
        self.npools = 0;
        // Game is built in place from a raw allocation, so a field's DEFAULT never runs and every count has
        // to be said HERE — an undefined `noccl` hands the mark list heap garbage to index with.
        self.noccl = 0;
        self.ndress = 0;
        self.nchests = 0;
        self.nrests = 0;
        self.stat_draws = 0;
        self.stat_cells = 0;
        self.stowed = false;
        // …and the water flags, which are BOOLS: raw heap bytes are illegal behaviour to read, not merely a
        // wrong answer, and `uploadWater` is the only other thing that ever writes them.
        self.waterAny = false;
        self.waterHalf = 0;
        @memset(&self.sgrid_start, 0);
        self.tileBuilt = [_]bool{false} ** NTILES;
        self.tileRad = [_]f32{0} ** NTILES;
        self.tileMid = [_]rl.Vector3{mathx.zero3} ** NTILES;
        self.skirtBuilt = false;
        self.heightField = [_]u8{wf.HEIGHT_ZERO} ** wf.HEIGHT_CELLS;
        self.heightHalf = wf.DEFAULT_HALF;
        self.heightAny = false;
    }

    pub fn uploadSoil(self: *Env, m: *const wf.Map) void {
        if (self.scene) |sc| sc.setSoil(&m.soil, &m.soilCov, &m.soilEdge, m.half);
    }

    pub fn uploadHeight(self: *Env, m: *const wf.Map) void {
        self.heightField = m.height;
        self.heightHalf = m.half;
        self.heightAny = m.anyHeight();
        self.rebuildTerrain();
    }

    pub fn sculptHeight(self: *Env, m: *const wf.Map, span: [4]usize) void {
        self.heightField = m.height;
        self.heightHalf = m.half;
        const wasAny = self.heightAny;
        self.heightAny = m.anyHeight();
        if (wasAny != self.heightAny) return self.rebuildTerrain();
        if (!self.heightAny) return;
        if (span[0] > span[2] or span[1] > span[3]) return; // the stroke missed the grid
        const lo = tileOf(if (span[0] > 0) span[0] - 1 else 0);
        const hi = tileOf(@min(span[2] + 1, wf.HEIGHT_N - 1));
        const zlo = tileOf(if (span[1] > 0) span[1] - 1 else 0);
        const zhi = tileOf(@min(span[3] + 1, wf.HEIGHT_N - 1));
        var tz = zlo;
        while (tz <= zhi) : (tz += 1) {
            var tx = lo;
            while (tx <= hi) : (tx += 1) self.buildTile(tz * TILES + tx);
        }
        // …AND THE SKIRT ONLY IF THE STROKE REACHED THE RIM.
        if (span[0] == 0 or span[1] == 0 or span[2] >= wf.HEIGHT_N - 1 or span[3] >= wf.HEIGHT_N - 1) self.buildSkirt();
    }

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
                // Wound the way `quad` winds a floor (a→b→c→d anticlockwise from above), or raylib culls
                // the ground and you look straight through the world.
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
            // North (−Z) and south (+Z) runs, then west/east — each wound to face UP like the tiles.
            b.quadSmooth(v3(a, self.pointY(i, 0), -half), v3(c, self.pointY(i + 1, 0), -half), v3(c, 0, -out), v3(a, 0, -out), up, up, up, up, rl.Color.white);
            b.quadSmooth(v3(a, 0, out), v3(c, 0, out), v3(c, self.pointY(i + 1, n), half), v3(a, self.pointY(i, n), half), up, up, up, up, rl.Color.white);
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

    /// The surface normal AT a lattice point, from the field's central differences.
    fn pointNormal(self: *const Env, ix: usize, iz: usize) rl.Vector3 {
        const step = 2 * self.heightHalf / @as(f32, @floatFromInt(wf.HEIGHT_N - 1));
        const xm = self.pointY(if (ix > 0) ix - 1 else 0, iz);
        const xp = self.pointY(ix + 1, iz);
        const zm = self.pointY(ix, if (iz > 0) iz - 1 else 0);
        const zp = self.pointY(ix, iz + 1);
        const xSpan: f32 = if (ix > 0 and ix + 1 < wf.HEIGHT_N) 2.0 else 1.0;
        const zSpan: f32 = if (iz > 0 and iz + 1 < wf.HEIGHT_N) 2.0 else 1.0;
        const dx = (xp - xm) / (step * xSpan);
        const dz = (zp - zm) / (step * zSpan);
        return mathx.normV(v3(-dx, 1.0, -dz));
    }

    pub fn uploadWater(self: *Env, m: *const wf.Map) void {
        const N = wf.WATER_N;
        self.waterAny = m.anyWater();
        self.waterHalf = m.half;
        if (!self.waterAny) {
            @memset(&self.waterField, 0);
            if (self.scene) |sc| sc.setWater(&self.waterField, m.half, false);
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
        // ONE cell width for the whole function.
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
        // `dIn` counts cells to the nearest DRY cell, `dOut` to the nearest WET one.
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
        const shoreF: f32 = @floatFromInt(gfx.WATER_SHORE);
        for (m.water, 0..) |wet, i| {
            const wx = edge(i % N, m.half, cell) + cell * 0.5;
            const wz = edge(i / N, m.half, cell) + cell * 0.5;
            const shape: wf.Edge = @enumFromInt(@min(m.waterEdge[i], wf.Edge.N - 1));
            // **ONE SIGNED DISTANCE, POSITIVE INTO THE WATER**, which is what lets a coast shape move the
            // line BOTH ways: as two branches keyed off the painted bit, a wet cell's encode floors at the
            // shore however much you take off it.
            const sd = coastWarp(shape, wx, wz) + if (wet != 0)
                @max(0.0, (dIn[i] - 0.5) * cell)
            else
                -@max(0.0, (dOut[i] - 0.5) * cell);
            const enc: f32 = if (sd >= 0) blk: {
                // HOW FAR INSIDE THE SHORE it is…
                const byShore = mathx.clampF(sd / gfx.WATER_DEEP_AT, 0, 1);
                // …AND HOW FAR DOWN THE GROUND WAS DUG, whichever reads deeper: a hole cut hard against the
                // bank is deep water at once, where the distance ramp alone painted it a pale shallow.
                // OFF THE **MAP**, NOT `self.heightField`: `uploadWater` runs BEFORE `uploadHeight` at both
                // call sites, so env's own copy is still the last world's.
                const dug = WATER_Y - (GROUND_Y + m.heightAt(edge(i % N, m.half, cell), edge(i / N, m.half, cell)));
                break :blk shoreF + @max(byShore, digTone(dug)) * (255.0 - shoreF);
            } else blk: {
                // …AND THE WET SAND OUTSIDE IT, whose WIDTH is the shape's second say. A blended margin is
                // a marsh you cannot find the edge of; a built embankment has none at all.
                break :blk shoreF * (1.0 - mathx.clampF(-sd / (gfx.WATER_WET_OUT * coastBand(shape)), 0, 1));
            };
            self.waterField[i] = mathx.u8f(enc);
        }
        facetWater(&self.waterField, m.half);
        if (self.scene) |sc| sc.setWater(&self.waterField, m.half, true);
    }

    pub fn drawWater(self: *Env) void {
        if (!self.waterAny) return;
        if (self.scene) |sc| {
            sc.setWaterSheet(true, props.WATER_TONES);
            // Scaled to the painted extent (Y left at 1 so the surface height is untouched).
            rl.drawModelEx(self.waterSheet, self.waterMid, v3(0, 1, 0), 0, self.waterSpan, rl.Color.white);
            sc.setWaterSheet(false, undefined);
        }
    }

    pub fn materialize(self: *Env, m: *const wf.Map) void {
        self.nprops = 0;
        self.nsolids = 0;
        self.nlights = 0;
        self.npools = 0;
        self.noccl = 0; // …and the in-flight fades, whose indices mean nothing in the world about to replace them
        // …AND THE SOLID GRID, EMPTIED, before anything queries it.
        @memset(&self.sgrid_start, 0);

        var p = Placer{ .e = self, .m = m, .flat = !m.anyHeight() };
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
        // …and REBUILD it only if the cover pass actually laid down a collider.
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

    pub fn stageOne(self: *Env, kind: Kind) void {
        self.nprops = 0;
        self.nsolids = 0;
        self.nlights = 0;
        self.npools = 0;
        self.noccl = 0; // …and the in-flight fades, for `materialize`'s reason: these are indices into the world being replaced
        self.props[0] = .{ .kind = kind, .pos = v3(0, 0, 0), .yaw = 0, .scale = 1.0, .op = 0 };
        self.nprops = 1;
        if (props.info(kind).light) |ls| {
            self.lights[0] = .{ .base = .{ .pos = v3(0, ls.y, 0), .col = ls.col, .radius = ls.radius }, .flicker = ls.flicker, .phase = 0 };
            self.nlights = 1;
        }
        buildSolids(self);
        indexProps(self);
    }


    /// Sets how solid each prop in the eye→hero line OUGHT to be (`pr.fadeTo`); `easeFades` walks what
    /// actually draws toward it. The target is a pure function of the sight line — only the CATCHING UP is
    /// remembered, which is the difference between a fade and a switch.
    ///
    /// WALKS `stx` ONLY, so flora never thins. ~270 props run `thinFor` and ~600 `coverFrac` a frame. A
    /// distance-to-the-sight-line reject in front of it is DELIBERATELY absent: it would drift against
    /// `coverFrac`'s own.
    pub fn markOccluders(self: *Env, eye: rl.Vector3, at: rl.Vector3, dt: f32) void {
        // Everything in flight is asked to come BACK; the scan below re-asks for whatever is still in the way.
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
                var k = self.stx.start[c];
                while (k < self.stx.start[c + 1]) : (k += 1) {
                    const pi = self.stx.items[k];
                    const pr = &self.props[pi];
                    const nfo = props.info(pr.kind);
                    if (nfo.solid) continue;
                    const thin = thinFor(pr, nfo, eye, at);
                    if (thin <= 0) continue;
                    self.wantFade(pi, mathx.lerpF(1.0, OCCL_FLOOR, thin));
                }
            }
        }
        self.easeFades(dt);
    }

    /// Ask one instance to be `to` solid, enlisting it if it is not in flight already. Two parts of the same
    /// prop can ask (an arch's piers are separate colliders), and the THINNER ask wins.
    ///
    /// FULL, AND THE SLOT COMES OFF SOMETHING STILL SOLID: first-come left the trunk over his head solid.
    /// An entry already off solid cannot be dropped — nothing outside this list is ticked, so it would
    /// strand thin or JUMP.
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
        const w = worst orelse return; // every slot is mid-travel: none of them is spendable
        const victim = self.occl[w];
        if (self.props[victim].fadeTo <= to) return; // everything spendable is thinner than this ask
        self.props[victim].fade = 1;
        self.props[victim].fadeTo = 1;
        self.props[pi].fadeTo = to;
        self.occl[w] = pi;
    }

    /// The ONLY thing the fade remembers. THE RATE IS SHAPED, NOT CONSTANT: a fixed rate reads as a step at
    /// both ends. `easeShape` is a pure function of where the value sits — `fadeTo` moves under it every
    /// frame, so an ease anchored to a start point would crawl.
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
                self.occl[i] = self.occl[self.noccl]; // swap the last one down into the hole
                continue;
            }
            i += 1;
        }
    }

    /// The nearest instance to `p` CARRYING AN OCCLUDER VOLUME OF ITS OWN — the trees, and the shot harness
    /// wants one because they are the only masses big enough to photograph the fade against. "Anything that
    /// may thin" is now most of the table and would hand it a cairn.
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

    /// EVERY SOLID IN THE CELLS AN XZ BOX TOUCHES; `visit` returns false to stop the walk. A solid whose
    /// footprint spans two visited cells is handed over twice.
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
                    if (!visit(ctx, self.solid_buf[self.sgrid_items[k]])) return;
                }
            }
        }
    }

    /// The solids that could touch a circle of radius `r` about `p`, written into `out`.
    pub fn nearSolids(self: *const Env, p: rl.Vector3, r: f32, out: []collision.Solid) []const collision.Solid {
        const Take = struct {
            out: []collision.Solid,
            n: usize = 0,
            fn one(c: *@This(), s: collision.Solid) bool {
                if (c.n >= c.out.len) return false; // MAX_NEAR is sized well past the densest cell
                c.out[c.n] = s;
                c.n += 1;
                return true;
            }
        };
        var take = Take{ .out = out };
        self.eachSolid(p.x - r, p.z - r, p.x + r, p.z + r, &take, Take.one);
        return out[0..take.n];
    }

    /// Walked over the grid's own cells rather than through `nearSolids`, which TRUNCATES at `MAX_NEAR` —
    /// over a twenty-metre sight line it would drop the wall it was asked about and answer "yes".
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

    /// PUSH AN ACTOR OUT OF THE WORLD'S SOLIDS. The grid is WALKED, not copied: this runs for the hero,
    /// every live foe and every wanderer EVERY FRAME, and `nearSolids` paid a ~6 KB stack frame per body
    /// AND truncates at `MAX_NEAR`, where a dropped capsule is a walk-through wall.
    ///
    /// `footY` IS THE WORLD HEIGHT OF ITS FEET, because a solid only blocks up to its own top (`Solid.h`).
    /// A WALL IS STILL A WALL AT ANY ALTITUDE — the jump's apex is `hero.JUMP_APEX` and a wall's `h` is
    /// metres above it; what changes is that a knee-high collider stops being one. NO `STEP_UP` ALLOWANCE
    /// unlike `flyStep`, or a man standing still walks through low rubble.
    pub fn resolveActor(self: *const Env, p: rl.Vector3, r: f32, footY: f32) rl.Vector3 {
        const Push = struct {
            at: rl.Vector3,
            r: f32,
            footY: f32,
            fn one(c: *@This(), s: collision.Solid) bool {
                if (c.footY >= s.h) return true; // over the top of it — see the note above
                c.at = collision.pushOut(c.at, c.r, s);
                return true;
            }
        };
        const q = r + 1.0;
        var push = Push{ .at = p, .r = r, .footY = footY };
        self.eachSolid(p.x - q, p.z - q, p.x + q, p.z + q, &push, Push.one);
        if (push.at.x == p.x and push.at.z == p.z) return push.at;
        self.eachSolid(p.x - q, p.z - q, p.x + q, p.z + q, &push, Push.one);
        return push.at;
    }


    /// The ground's world Y under a point — the datum plus whatever the map was sculpted to.
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

    pub fn slopeAlong(self: *const Env, x: f32, z: f32, dir: rl.Vector3) f32 {
        const g = self.gradAt(x, z);
        return g[0] * dir.x + g[1] * dir.z;
    }

    pub fn walkableAt(self: *const Env, x: f32, z: f32) bool {
        return self.slopeAt(x, z) <= MAX_SLOPE;
    }

    /// THE TRAVERSAL RULE, and the whole of it. Returns XZ; the caller grounds Y.
    pub fn walkStep(self: *const Env, from: rl.Vector3, dir: rl.Vector3, dist: f32) rl.Vector3 {
        const to = v3(from.x + dir.x * dist, from.y, from.z + dir.z * dist);
        if (!self.heightAny or dist <= 0) return to;
        // A HOLD, not the slope's slide, which is why it is not folded in below.
        if (self.deepRefused(from.x, from.z, to.x, to.z)) return v3(from.x, from.y, from.z);
        if (self.stepOk(from, dir, dist)) return to;
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
        const slide = v3(from.x + tx / tl * dist, from.y, from.z + tz / tl * dist);
        if (self.stepOk(from, v3(tx / tl, 0, tz / tl), dist)) return slide;
        return v3(from.x, from.y, from.z);
    }

    /// THE SAME RULE FOR SOMETHING WITH ITS FEET OFF THE GROUND, and it lives here rather than at the jump for
    /// `walkStep`'s reason: traversal is decided in one file. A man in the air asks a different question of the
    /// terrain — not "may I climb this" but "am I over it" — so what replaces the riser rule is his own FEET
    /// (`footY`, a WORLD height). Ground standing higher than they are is a wall.
    ///
    /// Without it a jump at a cliff carries him into the cliff's own footprint, `game.groundActor` lifts him up
    /// three metres of it, and the ledge nobody could walk up has been climbed by pressing A at it.
    ///
    /// PLUS THE WALK'S OWN ALLOWANCE: on the takeoff frame his feet are still at the ground he left, so a bare
    /// comparison stalls a jump against the gentle rise that same jump exists to clear. A jump may never travel
    /// WORSE than a step. Deep water is not asked here — `deepRefused` is that rule and `game.gateHeroWater`
    /// asks it after every branch including this one.
    pub fn flyStep(self: *const Env, from: rl.Vector3, dir: rl.Vector3, dist: f32, footY: f32) rl.Vector3 {
        const to = v3(from.x + dir.x * dist, from.y, from.z + dir.z * dist);
        if (!self.heightAny or dist <= 0) return to;
        if (self.groundAt(to.x, to.z) <= footY + STEP_UP) return to;
        return v3(from.x, from.y, from.z);
    }

    /// Is the ground `probe` metres along `dir` a step this actor may take?
    fn stepOk(self: *const Env, from: rl.Vector3, dir: rl.Vector3, dist: f32) bool {
        const probe = mathx.maxF(dist, STEP_PROBE);
        const h0 = self.groundAt(from.x, from.z);
        const h1 = self.groundAt(from.x + dir.x * probe, from.z + dir.z * probe);
        const rise = h1 - h0;
        return rise <= mathx.maxF(STEP_UP, MAX_SLOPE * probe);
    }

    /// Where a ray meets the ground — the editor's cursor, and anything else aiming at the terrain.
    pub fn rayGround(self: *const Env, origin: rl.Vector3, dir: rl.Vector3) ?rl.Vector3 {
        if (!self.heightAny) {
            if (@abs(dir.y) < 1e-6) return null;
            const t = (GROUND_Y - origin.y) / dir.y;
            if (t <= 0) return null;
            return v3(origin.x + dir.x * t, GROUND_Y, origin.z + dir.z * t);
        }
        const step = 2 * self.heightHalf / @as(f32, @floatFromInt(wf.HEIGHT_N - 1));
        const horiz = @sqrt(dir.x * dir.x + dir.z * dir.z);
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
        // …and the PAINTED water, off the same field the shader draws.
        const margin = (1.0 - mathx.clampF(inset, 0, 1)) * gfx.WATER_DEEP_AT;
        return self.paintedDepth(x, z) * gfx.WATER_DEEP_AT > margin + 0.01;
    }

    /// How deep the painted water is at a point: 0 dry, 1 as deep as the field ramps (gfx.WATER_DEEP_AT metres from the shore).
    pub fn paintedDepth(self: *const Env, x: f32, z: f32) f32 {
        if (!self.waterAny) return 0;
        // The MAP's own sampler over env's copy of the field — one rule for both owners (`wf.gridIndex`).
        const i = wf.gridIndex(self.waterHalf, wf.WATER_N, x, z) orelse return 0;
        const v: f32 = @floatFromInt(self.waterField[i]);
        const shore: f32 = @floatFromInt(gfx.WATER_SHORE);
        if (v <= shore) return 0;
        return (v - shore) / (255.0 - shore);
    }

    /// In METRES — what wading reads. A different question from `paintedDepth`, which is a distance from
    /// the shore and says nothing about the dig.
    pub fn wadeDepth(self: *const Env, x: f32, z: f32) f32 {
        if (self.paintedDepth(x, z) <= 0) return 0;
        return mathx.maxF(0, WATER_Y - self.groundAt(x, z));
    }

    /// DEEP WATER IS A WALL — ONE rule with two callers, `walkStep` and `game.gateHeroWater` (the post-step
    /// gate over committed moves that travel by `mathx.stepXZ`). As a copy at each they had drifted at the
    /// boundary.
    ///
    /// A refusal of its own rather than a clause in `stepOk`: you walk DOWN into a basin, and the rise rule
    /// lets every downhill step through by design. GETTING OUT IS NEVER HELD — only a move coming out
    /// DEEPER is refused, or anything that leapt in is trapped on a flat bottom.
    pub fn deepRefused(self: *const Env, fromX: f32, fromZ: f32, toX: f32, toZ: f32) bool {
        const deep = self.wadeDepth(toX, toZ);
        return deep > WADE_MAX and deep > self.wadeDepth(fromX, fromZ);
    }


    pub fn pickIf(
        self: *const Env,
        origin: rl.Vector3,
        dir: rl.Vector3,
        ctx: anytype,
        comptime accept: fn (@TypeOf(ctx), u16) bool,
    ) ?usize {
        var best: ?usize = null;
        var bestT: f32 = std.math.floatMax(f32);
        // THE RAY REJECTS FIRST, THE PREDICATE SECOND: `accept` reads the OP the prop came from, a random
        // index into a quarter-megabyte table — a cache miss per prop, 17,000 times a frame while Select
        // is armed, for a question the ray makes moot for all but a handful.
        for (self.props[0..self.nprops], 0..) |*pr, i| {
            const nfo = props.info(pr.kind);
            const sw = leanSwing(pr, nfo.top * pr.scale * 0.5);
            const c = v3(pr.pos.x + sw.x, pr.pos.y + nfo.top * pr.scale * 0.5, pr.pos.z + sw.z);
            const rad = @max(nfo.bound * pr.scale * 0.5, 0.35);
            const oc = mathx.subV(c, origin);
            const along = oc.x * dir.x + oc.y * dir.y + oc.z * dir.z;
            if (along <= 0 or along >= bestT) continue; // behind the eye, or already beaten
            const perp2 = (oc.x * oc.x + oc.y * oc.y + oc.z * oc.z) - along * along;
            if (perp2 > rad * rad) continue;
            if (accept(ctx, pr.op)) {
                bestT = along;
                best = i;
            }
        }
        return best;
    }

    pub fn model(self: *const Env, kind: Kind) rl.Model {
        return self.models[@intFromEnum(kind)];
    }

    pub fn veil(self: *const Env, kind: Kind) ?rl.Model {
        return self.veils[@intFromEnum(kind)];
    }

    pub fn setShader(self: *Env, sh: rl.Shader) void {
        self.ground.materials[0].shader = sh;
        for (&self.models) |*m| m.materials[0].shader = sh;
        // The stows too — they ARE casters, so they go through the depth pass with the rest.
        for (&self.stows) |*m| {
            if (m.*) |*s| s.materials[0].shader = sh;
        }
        // The terrain tiles too — NOT for the depth pass, which never draws them, but so a shader SWAP
        // reaches them: `rl.unloadModel` would take the scene shader with it.
        for (self.tiles[0..], self.tileBuilt[0..]) |*t, built| {
            if (built) t.materials[0].shader = sh;
        }
        if (self.skirtBuilt) self.skirt.materials[0].shader = sh;
    }

    /// Terrain receives shadows but doesn't cast; drawn separately with groundMode on.
    pub fn drawGround(self: *Env, view: ?*const View) void {
        if (!self.heightAny) {
            rl.drawModel(self.ground, mathx.zero3, 1.0, rl.Color.white);
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
            const bound = nfo.bound * pr.scale;
            switch (cull) {
                .view => |*vw| if (!vw.visible(pr.pos, bound, nfo.view)) continue,
                .sun => |focus| if (!castsInto(focus, pr.pos, bound, nfo.top * pr.scale)) continue,
            }
            const sc = v3(pr.scale, pr.scale, pr.scale);
            rl.drawModelEx(mdl, pr.pos, v3(0, 1, 0), pr.yaw, sc, rl.Color.white);
        }
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

    /// EVERY CHEST THAT WAS ACTUALLY PLACED, in prop order — off the list `indexProps` settled, not a fresh sweep of the world (the editor asks every frame).
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
    /// **HOW A TAKEN PICKUP LEAVES THE WORLD.** `i` indexes the pickup list, which is the same order
    /// `pickupSites` handed out — both walk `pickupItems`, so the runtime glow and its prop are the same slot.
    /// `scale` carries the shrink and `gone` ends it, so the picture is the fade and not a blink.
    pub fn setPickupDraw(self: *Env, i: usize, left: f32, gone: bool) void {
        if (i >= self.npickups) return;
        const pr = &self.props[self.pickupItems[i]];
        pr.shrink = mathx.clampF(left, 0, 1);
        pr.gone = gone;
    }
    /// …AND EVERY ITEM PICKUP, on exactly the same terms.
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

    /// THE VEILS — today the bonfire's smoke column, and it must come after EVERY opaque pass.
    pub fn drawVeils(self: *Env, view: *const View) void {
        for (self.dressItems[0..self.ndress]) |pi| {
            const pr = &self.props[pi];
            const mdl = self.veils[@intFromEnum(pr.kind)] orelse continue;
            const nfo = props.info(pr.kind);
            if (!view.visible(pr.pos, nfo.bound * pr.scale, nfo.view)) continue;
            self.stat_draws += 1;
            const sc = v3(pr.scale, pr.scale, pr.scale);
            rl.drawModelEx(mdl, pr.pos, v3(0, 1, 0), pr.yaw, sc, rl.Color.white);
        }
    }

    // Walk one index cell by cell, rejecting whole cells before touching their props.
    fn drawIndexed(self: *Env, idx: *const Index, cull: Cull) void {
        const casters_only = cull == .sun;
        var c: usize = 0;
        while (c < NCELL) : (c += 1) {
            if (idx.start[c] == idx.start[c + 1]) continue;
            var centre = cellCentre(c);
            // Lifted onto the cell's own props: with elevation the cell is a slab tens of metres off the
            // datum, and a sphere at y = 0 rejects a hilltop you are looking straight at.
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
                if (pr.gone) continue; // taken out of the world — see `Prop.gone`
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
                if (!casters_only and pr.fade < FADE_SOLID) continue; // held back for `drawThinned`
                self.stat_draws += 1;
                // **A PROP ON ITS WAY OUT THINS AS WELL AS SHRINKING** (owner: have items fade when you pick
                // them up). The shrink on its own is a glow getting SMALLER at full brightness, which the eye
                // reads as one moving away rather than one going out. `shrink` is 1 for everything else in the
                // world, so this is the same branch `fade` above already costs, and `setFade` is the scene
                // shader's alone — the sun pass must not push it (`drawCasters`' own note).
                if (!casters_only and pr.shrink < 1.0) {
                    if (self.scene) |s| s.setFade(pr.shrink);
                    rl.gl.rlDisableDepthMask();
                    self.drawProp(pr);
                    rl.gl.rlEnableDepthMask();
                    if (self.scene) |s| s.setFade(1);
                } else {
                    self.drawProp(pr);
                }
            }
        }
    }

    fn drawProp(self: *const Env, pr: *const Prop) void {
        // `shrink` is 1 for every prop that is not on its way out, so this is the authored scale everywhere
        // except the handful of glows that have just been taken.
        const s = pr.scale * pr.shrink;
        const sc = v3(s, s, s);
        if (pr.lean == 0) {
            rl.drawModelEx(self.models[@intFromEnum(pr.kind)], pr.pos, v3(0, 1, 0), pr.yaw, sc, rl.Color.white);
            return;
        }
        var mdl = self.models[@intFromEnum(pr.kind)];
        mdl.transform = rl.math.matrixRotateY(mathx.radians(pr.yaw));
        rl.drawModelEx(mdl, pr.pos, leanAxis(pr.leanDir), pr.lean, sc, rl.Color.white);
    }

    /// AFTER EVERY OPAQUE THING AND BACK TO FRONT. A thinned prop draws with the depth MASK OFF, so drawn
    /// in cell order the hero composited at FULL opacity straight over it — an instant reveal wearing a
    /// fade. Drawn last, the tree's alpha mattes HIM, so the reveal IS the ramp.
    ///
    /// LIT PASS ONLY — the depth shader has no alpha, and a see-through tree still blocks the sun.
    pub fn drawThinned(self: *Env, view: *const View) void {
        var order: [OCCL_MAX]u32 = undefined;
        var far: [OCCL_MAX]f32 = undefined;
        var n: usize = 0;
        for (self.occl[0..self.noccl]) |pi| {
            const pr = &self.props[pi];
            if (pr.fade >= FADE_SOLID) continue; // it drew solid with everything else
            const nfo = props.info(pr.kind);
            if (!view.visible(pr.pos, nfo.bound * pr.scale, nfo.view)) continue;
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
        rl.gl.rlSetBlendFactors(GL_ZERO, GL_ONE, GL_FUNC_ADD);
        for (order[0..n]) |pi| {
            const pr = &self.props[pi];
            self.stat_draws += 2;
            // ONE LAYER PER PIXEL: roots, boughs and the far side of a bole stack three or four surfaces
            // along the ray and the alpha COMPOUNDS. Each prop lays down its own depth first with the
            // colour buffer held, and the pass after draws under LEQUAL, which only the nearest satisfies.
            rl.gl.rlSetBlendMode(@intFromEnum(rl.gl.rlBlendMode.rl_blend_custom));
            self.drawProp(pr);
            rl.gl.rlSetBlendMode(@intFromEnum(rl.gl.rlBlendMode.rl_blend_alpha));
            rl.gl.rlDisableDepthMask();
            if (self.scene) |s| s.setFade(pr.fade);
            self.drawProp(pr);
            rl.gl.rlEnableDepthMask();
        }
        if (self.scene) |s| s.setFade(1);
    }

    /// This frame's torch/fire lights: the gfx.MAX_LIGHTS nearest the camera whose pool is actually ON SCREEN.
    ///
    /// `reserved` are lights that are NOT in the world — the wand in his hand (`hero.wandLight`), a
    /// necromancer's rune ring (`necro.Rite.markLights`). They get RESERVED slots rather than joining the
    /// contest, so a brazier the player stands beside cannot evict the spell he just cast or the mark he is
    /// standing on. **NEVER MORE THAN HALF THE RACK, THOUGH**: a field with several casters on it would
    /// otherwise put out every fire in the world to light their own marks. Past the half the caller's ORDER
    /// decides, which is why it hands them over most-important first.
    pub fn uploadLights(self: *const Env, scene: *gfx.Scene, view: *const View, t: f32, reserved: []const gfx.Light) void {
        comptime std.debug.assert(gfx.MAX_LIGHTS > 1); // the reserved slots have to leave the world at least one
        var picked: [gfx.MAX_LIGHTS]gfx.Light = undefined;
        var dist: [gfx.MAX_LIGHTS]f32 = undefined;
        const keep = @min(reserved.len, gfx.MAX_LIGHTS / 2);
        const cap = picked.len - keep;
        var n: usize = 0;
        for (self.lights[0..self.nlights]) |wl| {
            if (!view.visible(wl.base.pos, wl.base.radius, LIGHT_REACH)) continue;
            const d2 = mathx.dist2XZ(wl.base.pos, view.pos);
            const k = 1.0 + wl.flicker * gutter(t, wl.phase);
            const lit = gfx.Light{
                .pos = wl.base.pos,
                .col = mathx.scaleV(wl.base.col, mathx.maxF(k, 0.05)),
                .radius = wl.base.radius,
            };
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

// A flame's guttering, in [-1, 1]: three incommensurate rates so it never reads as a pulse.
fn gutter(t: f32, phase: f32) f32 {
    return 0.30 * mathx.sinf(t * 4.3 + phase) + 0.14 * mathx.sinf(t * 8.9 + phase * 2.3) + 0.56 * mathx.sinf(t * 1.7 + phase * 0.6);
}

/// …AND THE REACH MOVES WITH THE SUN NOW (`gfx.sunReach`, written once a frame by `gfx.Scene.setHour`). It was
/// a comptime constant off the one authored sun; with a sun that climbs and sets, a fixed reach either culls a
/// low evening caster whose shadow genuinely crosses the box, or accepts the whole world at noon to avoid it.
/// `daynight` floors the casting altitude, which is what keeps this bounded rather than cot(0).
fn castsInto(focus: rl.Vector3, pos: rl.Vector3, bound: f32, top: f32) bool {
    const reach = SHADOW_BOX + bound + top * gfx.sunReach;
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

// Height lattice point → the terrain tile that owns it.
fn tileOf(point: usize) usize {
    return @min(point / (TCHUNK - 1), TILES - 1);
}

// World coordinate → grid column/row, clamped so anything outside lands in the edge cell.
fn cellCoord(w: f32) usize {
    // CLAMPED IN FLOAT, BEFORE THE CAST.
    return @intFromFloat(mathx.clampF((w + GRID_HALF) / CELL, 0, @floatFromInt(GRID_N - 1)));
}

fn cellOf(x: f32, z: f32) usize {
    return cellCoord(z) * GRID_N + cellCoord(x);
}

/// ONE INSTANCE'S LOCAL→WORLD TURN, with the yaw's sine and cosine taken ONCE — `partFoot` and
/// `blockerFoot` re-derived the trig per PART, per prop, per frame inside the occluder scan.
const PropFrame = struct {
    pr: *const Prop,
    c: f32,
    sn: f32,

    fn of(pr: *const Prop) PropFrame {
        const th = mathx.radians(pr.yaw);
        return .{ .pr = pr, .c = mathx.cosf(th), .sn = mathx.sinf(th) };
    }
    /// A point authored at (lx, ly, lz) in the prop's own frame, in world space.
    fn at(self: PropFrame, lx: f32, ly: f32, lz: f32) rl.Vector3 {
        const s = self.pr.scale;
        return v3(
            self.pr.pos.x + s * (lx * self.c + lz * self.sn),
            self.pr.pos.y + ly * s,
            self.pr.pos.z + s * (-lx * self.sn + lz * self.c),
        );
    }
    /// The FOOT of one collider part's centre line — the same turn, at the prop's own base.
    fn partFoot(self: PropFrame, part: props.Part) rl.Vector3 {
        return self.at((part.ax + part.bx) * 0.5, 0, (part.az + part.bz) * 0.5);
    }
    /// …and the foot of one occluder volume, which carries its own start height.
    fn blockerFoot(self: PropFrame, bl: props.Blocker) rl.Vector3 {
        return self.at(bl.x, bl.y0, bl.z);
    }
};

/// 0 (solid) .. 1 (as thin as it gets) — the deepest ask any of its masses makes. Three sources in order:
/// the kind's declared volumes, the COLLIDERS plus a skirt, and for a kind with neither a share of the
/// bound. A collider is sized for what you WALK INTO, and on a tree it is wrong by metres: a conifer's
/// 1.48 m cylinder against boughs that block the view at 3.8 m.
fn thinFor(pr: *const Prop, nfo: *const props.Info, eye: rl.Vector3, at: rl.Vector3) f32 {
    var thin: f32 = 0;
    const fr = PropFrame.of(pr); // the yaw's trig ONCE per prop, not once per mass
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
        thin = thinOf(eye, at, pr.pos, nfo.top * pr.scale, nfo.bound * pr.scale * OCCL_GIRTH);
    }
    return thin;
}

/// THE TWO QUESTIONS STAY APART. How much of him it hides decides WHETHER it thins; how far in front of him
/// it stands scales HOW FAR. Multiplied together before the threshold — which is what `coverFrac` used to
/// return — a mass a metre in front of him had its coverage discounted below `OCCL_MIN` and never thinned.
fn thinOf(eye: rl.Vector3, at: rl.Vector3, foot: rl.Vector3, h: f32, r: f32) f32 {
    const c = coverFrac(eye, at, foot, h, r);
    if (c.cover <= OCCL_MIN) return 0;
    return mathx.smoothstep(OCCL_MIN, OCCL_FULL, c.cover) * c.ahead;
}

const Cover = struct {
    cover: f32, // share of him the mass hides, 0..1
    ahead: f32, // …and how much of the way in front of him it stands, over OCCL_DEPTH_BAND
};
const NO_COVER = Cover{ .cover = 0, .ahead = 0 };

/// Overlap of two boxes in the EYE'S TANGENT PLANE, before any FOV scale, so the answer is in fractions of
/// him. Distance to the sight line cannot answer it: a stump on the line covers his boots, a canopy fifteen
/// metres up covers nothing.
fn coverFrac(eye: rl.Vector3, at: rl.Vector3, foot: rl.Vector3, h: f32, r: f32) Cover {
    const toH = mathx.subV(at, eye);
    const dh = mathx.lenV(toH);
    if (dh < 0.5) return NO_COVER;
    const fwd = mathx.scaleV(toH, 1.0 / dh);
    // Screen-right, taken horizontal: the roll is always zero here, and a camera looking straight down
    // has no "in front of" to speak of.
    var right = v3(fwd.z, 0, -fwd.x);
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
        if (z[i] < 0.15) z[i] = 0.15; // an end behind the lens still has the other end in front of it
        u[i] = (d.x * right.x + d.y * right.y + d.z * right.z) / z[i];
        vv[i] = (d.x * up.x + d.y * up.y + d.z * up.z) / z[i];
    }
    const zm = (z[0] + z[1]) * 0.5;
    const ahead = mathx.clampF((dh - zm) / OCCL_DEPTH_BAND, 0, 1); // behind him: not in the way of anything
    if (ahead <= 0) return NO_COVER;
    // The hero's own box, centred on the sight line because that is where the camera is aiming.
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

// Flat ground plane as one big white quad — the scene shader's terrainAlbedo owns the look.
fn terrain(shader: rl.Shader, half: f32) rl.Model {
    var b = gfx.Builder.init();
    b.quad(v3(-half, GROUND_Y, -half), v3(-half, GROUND_Y, half), v3(half, GROUND_Y, half), v3(half, GROUND_Y, -half), v3(0, 1, 0), rl.Color.white);
    return b.toModel(shader);
}

/// THE PAINTED WATER SHEET: one world-spanning quad on the `.water` material.
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
    cur: u16 = 0, // the op being expanded, stamped onto every prop it places
    // Held here rather than threaded through `at`, or every scatter grows a parameter it never uses.
    lean: f32 = 0,
    leanDir: f32 = 0,
    leanExact: bool = false,

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
        // NOTHING is drawn from `rng` unless the op actually asked for a lean.
        var lean: f32 = 0;
        var leanDir: f32 = self.leanDir;
        if (self.lean != 0) {
            if (self.leanExact) {
                lean = self.lean;
            } else {
                lean = self.lean * rng.range(0.15, 1.0);
                leanDir = rng.range(0, 360);
            }
        }
        self.e.props[self.e.nprops] = .{ .kind = kind, .pos = v3(x, y, z), .yaw = yaw, .scale = scale, .lean = lean, .leanDir = leanDir, .op = self.cur };
        self.e.nprops += 1;
        if (props.info(kind).light) |ls| self.addLight(x, y, z, scale, ls, rng);
        if (kind == .water) {
            // An init-time PANIC, like MAX_PROPS/MAX_SOLIDS — never a silent drop.
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

    fn accepts(self: *Placer, o: *const wf.Op, x: f32, z: f32, rng: *mathx.Rng) bool {
        if (self.rejects(o, x, z)) return false;
        // The cover field, mixed toward 1 so structures THIN where the flora does without vanishing.
        if (o.field and rng.float() > FIELD_FLOOR + (1.0 - FIELD_FLOOR) * coverField(x, z)) return false;
        if (o.gAxis != .none and rng.float() > o.gradAt(x, z)) return false;
        return true;
    }

    /// The shared rejection test every scatter runs a candidate through.
    fn rejects(self: *Placer, o: *const wf.Op, x: f32, z: f32) bool {
        if (o.avoid.runway and self.m.onRunway(x, z)) return true;
        if (o.avoid.water and self.e.inWater(x, z, 1.04)) return true;
        if (o.avoid.clear and self.m.inClearing(x, z)) return true;
        // Don't grow through the world: the solid grid already knows what is here.
        if (o.avoid.solid and self.blockedHere(x, z)) return true;
        return false;
    }

    fn blockedHere(self: *Placer, x: f32, z: f32) bool {
        return self.e.blockedNear(v3(x, self.groundY(x, z) + SOLID_PROBE_Y, z), SOLID_PROBE_M, SOLID_PROBE_R);
    }

    fn expand(self: *Placer, o: *const wf.Op) void {
        var rng = o.stream();
        self.lean = o.lean;
        self.leanDir = o.leanDir;
        self.leanExact = o.op == .at;
        switch (o.op) {
            // `r1` IS THE LIFT here, not a radius — see the note at `wf.Op.r1`. It is how a lantern hangs off
            // an arch or a prop sits on a ledge, and it is the only op that reads the field that way.
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

    // A scattered belt in a box.
    fn belt(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        var i: i32 = 0;
        while (i < o.n) : (i += 1) {
            const x = rng.range(o.x, o.x1);
            const z = rng.range(o.z, o.z1);
            if (!self.accepts(o, x, z, rng)) continue;
            self.at(o.pick(rng), x, z, rng.range(0, 360), rng.range(o.sLo, o.sHi), rng);
        }
    }

    // An annulus scatter: shorelines, reed beds, talus, drowned ruin.
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

    // A broken run from a→b: segments laid nose to tail, `chance` of each surviving.
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

    // Sow a climber at the FEET of the stonework already standing inside a box.
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

    fn edge(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        if (o.r0 < 1e-4) return;
        const rim = self.m.half + RIM_OUT; // the rock wall stands just outside the movement clamp
        var t: f32 = -rim;
        while (t <= rim) : (t += o.r0) {
            const jitter = rng.signed() * 1.6;
            self.at(o.pick(rng), t + jitter, -rim - rng.range(0, 2.5), 180 + rng.signed() * 7, ridge(o, t, rng), rng);
            self.at(o.pick(rng), t - jitter, rim + rng.range(0, 2.5), 0 + rng.signed() * 7, ridge(o, t + 91, rng), rng);
            self.at(o.pick(rng), rim + rng.range(0, 2.5), t + jitter, 90 + rng.signed() * 7, ridge(o, t + 213, rng), rng);
            self.at(o.pick(rng), -rim - rng.range(0, 2.5), t - jitter, 270 + rng.signed() * 7, ridge(o, t + 347, rng), rng);
        }
        // Talus and scrub spilling off the feet of the walls, so the base isn't a clean line.
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

    fn ridge(o: *const wf.Op, along: f32, rng: *mathx.Rng) f32 {
        const mid = (o.sLo + o.sHi) * 0.5;
        const amp = (o.sHi - o.sLo) * 0.5;
        return mid + amp * (0.62 * mathx.sinf(along * 0.070) + 0.31 * mathx.sinf(along * 0.170 + 1.9)) + rng.signed() * amp * 0.16;
    }

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
                if (self.e.inWater(x, z, 0.97)) continue;
                if (self.m.onRunway(x, z)) continue;
                // The grid, walked IN PLACE — see `blockedNear`.
                if (self.blockedHere(x, z)) continue;
                const kind = zone.pick(rng) orelse continue;
                self.at(kind, x, z, rng.range(0, 360), rng.range(o.sLo, o.sHi), rng);
            }
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
    for (e.props[0..e.nprops]) |*pr| {
        const nfo = props.info(pr.kind);
        const s = pr.scale;
        const fr = PropFrame.of(pr); // the SAME local→world turn the occluder scan makes
        for (nfo.parts) |part| {
            if (e.nsolids >= MAX_SOLIDS) @panic("env: MAX_SOLIDS exceeded — raise the cap");
            const a = fr.at(part.ax, 0, part.az);
            const b = fr.at(part.bx, 0, part.bz);
            var sol = collision.capsule(a.x, a.z, b.x, b.z, part.r * s);
            sol.h = pr.pos.y + part.h * s;
            sol.surf = nfo.surf;
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

// The cells a solid's expanded footprint covers.
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

fn indexProps(e: *Env) void {
    fillIndex(e, &e.stx, false);
    fillIndex(e, &e.flx, true);
    e.ndress = 0;
    e.nchests = 0;
    e.npickups = 0;
    e.nrests = 0;
    for (e.props[0..e.nprops], 0..) |*pr, pi| {
        const i: u32 = @intCast(pi);
        const nfo = props.info(pr.kind);
        // Caps PANIC like MAX_PROPS — a silently unregistered chest is a box that draws but never opens.
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
        // SEEDED FROM THE CELL'S OWN FIRST PROP, not from the datum: seeded at 0, a cell of props twenty
        // metres up a hill reports the span 0..20, and its cull sphere grows ten metres.
        const first = cursor[c] == idx.start[c];
        idx.items[cursor[c]] = @intCast(pi);
        cursor[c] += 1;
        idx.bound[c] = mathx.maxF(idx.bound[c], nfo.bound * pr.scale);
        idx.view[c] = mathx.maxF(idx.view[c], nfo.view);
        idx.top[c] = mathx.maxF(idx.top[c], nfo.top * pr.scale);
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
        try std.testing.expect(vw.visible(ahead, 0.5, 250));
        const wide = mathx.addV(ahead, mathx.scaleV(mathx.normV(cross(h, v3(0, 1, 0))), 30));
        try std.testing.expect(!vw.visible(wide, 0.5, 100));
        try std.testing.expect(vw.visible(wide, 26.0, 100));
    }
}

test "the culler accepts the full width of the screen, not just the axis" {
    // A prop at the horizontal edge of a 16:10 45-deg-vertical frustum must survive: too tight an angle
    // silently thins the sides of every frame.
    const vw = viewLooking(v3(0, 0, 0), v3(0, 0, 1));
    const hf = std.math.atan(@tan(mathx.radians(45.0) * 0.5) * 1.6);
    const edge = v3(@tan(hf * 0.94) * 40.0, 0, 40); // 94% of the way to the edge, dead centre vertically
    try std.testing.expect(vw.visible(edge, 0.0, 100));
    try std.testing.expect(vw.visible(v3(-edge.x, 0, edge.z), 0.0, 100));
}

test "A CANOPY HIDES HIM AND THE TRUNK IT HANGS OFF DOES NOT — the occluder volume is not the collider" {
    // The whole of the original complaint: a conifer's collider is a 0.58 m pole, its boughs reach 3.4 m,
    // and a camera looking through the branches scored nothing against the pole and left the tree solid.
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.props[0] = .{ .kind = .conifer, .pos = v3(2.6, 0, 0), .yaw = 0, .scale = 1 };
    e.nprops = 1;
    fillIndex(e, &e.stx, false);
    const nfo = props.info(.conifer);
    const eye = v3(0, 2.2, -5);
    const hero = v3(0, 1.0, 3);

    // The colliders alone — what the fade used to be handed — cannot see it at all.
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
    // The flag reads `solid`, so the DEFAULT is the fade. As an opt-in `fades` every row written afterwards
    // stayed solid without anyone deciding it should — boulders, statues, lanterns, saplings.
    for ([_]props.Kind{ .wall, .tower, .gate, .chapel, .cottage, .watchtower, .cliff, .cliff4 }) |k| {
        try std.testing.expect(props.info(k).solid);
    }
    // …AND SO IS ANYTHING DRAWN IN MORE THAN ONE PIECE: the bonfire's veil goes down `drawVeils` and the
    // chest's LID down `chest.Chests.draw`, and neither path carries `setFade`.
    for ([_]props.Kind{ .bonfire, .chest }) |k| {
        try std.testing.expect(props.info(k).solid);
    }
    for ([_]props.Kind{ .boulder, .statue, .monolith, .lantern, .gibbet, .sapling, .conifer, .bigtree }) |k| {
        try std.testing.expect(!props.info(k).solid);
    }
}

test "a FULL occluder list gives its slots to what hides him most, not to what the cell walk reached first" {
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    // Fill every slot with a barely-thinning ask, then let one deep ask in.
    for (0..OCCL_MAX) |i| {
        e.props[i] = .{ .kind = .snag, .pos = v3(@floatFromInt(i), 0, 0), .yaw = 0, .scale = 1 };
        e.wantFade(@intCast(i), 0.98);
    }
    try std.testing.expectEqual(@as(usize, OCCL_MAX), e.noccl);
    e.props[OCCL_MAX] = .{ .kind = .snag, .pos = v3(0, 0, 9), .yaw = 0, .scale = 1 };
    e.wantFade(OCCL_MAX, OCCL_FLOOR);
    try std.testing.expectApproxEqAbs(OCCL_FLOOR, e.props[OCCL_MAX].fadeTo, 1e-5);
    try std.testing.expectEqual(@as(usize, OCCL_MAX), e.noccl); // it took a slot, it did not grow the list
    // …and the one it evicted is back to solid rather than stranded thin with nothing ticking it.
    var evicted: usize = 0;
    for (0..OCCL_MAX) |i| {
        if (e.props[i].fadeTo >= 1.0) evicted += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), evicted);
    // A shallower ask against a full list of deeper ones changes nothing.
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
    e.easeFades(1.0 / 60.0); // every slot has now LEFT solid, so none of them is spendable
    for (e.occl[0..e.noccl]) |pi| try std.testing.expect(e.props[pi].fade < FADE_SOLID);
    e.props[OCCL_MAX] = .{ .kind = .snag, .pos = v3(0, 0, 9), .yaw = 0, .scale = 1 };
    e.wantFade(OCCL_MAX, OCCL_FLOOR);
    try std.testing.expectEqual(@as(f32, 1), e.props[OCCL_MAX].fadeTo); // the deepest ask there is, refused…
    try std.testing.expectEqual(OCCL_MAX, e.noccl);
    for (e.occl[0..e.noccl]) |pi| try std.testing.expect(e.props[pi].fade < FADE_SOLID); // …and nobody jumped
}

test "the shadow cull keeps a distant TALL caster whose shadow still reaches the box" {
    const focus = v3(0, 0, 0);
    const outside = SHADOW_BOX + 10.0; // just beyond the box's own corner
    try std.testing.expect(castsInto(focus, v3(outside, 0, 0), 18.0, 15.5));
    try std.testing.expect(!castsInto(focus, v3(outside, 0, 0), 0.9, 0.8));
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

test "the sight line thins the tree standing in it, and only that tree" {
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.props[0] = .{ .kind = .bigtree, .pos = v3(0, 0, 0), .yaw = 0, .scale = 1 };
    e.props[1] = .{ .kind = .cottage, .pos = v3(0, 0, 0), .yaw = 0, .scale = 1 }; // architecture, same spot
    e.props[2] = .{ .kind = .bigtree, .pos = v3(0, 0, 40), .yaw = 0, .scale = 1 }; // past the far end of the line
    e.nprops = 3;
    fillIndex(e, &e.stx, false);

    // A camera at a real boom height, the hero 4 m the far side of the trunk. SETTLED, since what the
    // geometry asks for and what the picture has got to are two different questions (see easeFades).
    const eyeY: f32 = 2.2;
    e.markOccluders(v3(0, eyeY, -4), v3(0, 1.0, 4), 10.0);
    try std.testing.expectApproxEqAbs(OCCL_FLOOR, e.props[0].fade, 0.001); // squarely in front of him
    try std.testing.expectEqual(@as(f32, 1), e.props[1].fade); // you never see through a wall
    try std.testing.expectEqual(@as(f32, 1), e.props[2].fade); // nor through what is behind you
    // A line looking PAST it: the trunk is still within a metre of the sight line, and covers so little
    // of him that it has no business fading — the rule is what it hides, not how near it stands.
    e.markOccluders(v3(2.6, eyeY, -4), v3(2.6, 1.0, 4), 10.0);
    try std.testing.expectEqual(@as(f32, 1), e.props[0].fade);
    try std.testing.expectEqual(@as(usize, 0), e.noccl); // …and discharged, which is what the list is for
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
    try std.testing.expectApproxEqAbs(OCCL_FLOOR, e.props[0].fade, 0.001); // arrived, and pinned there
    e.markOccluders(eye, hero, step);
    try std.testing.expectApproxEqAbs(OCCL_FLOOR, e.props[0].fade, 0.001);

    const clear = v3(60, 2.2, -4);
    e.markOccluders(clear, v3(60, 1.0, 4), step);
    try std.testing.expect(e.props[0].fade > OCCL_FLOOR and e.props[0].fade < 1.0);
    try std.testing.expect(e.props[0].fade - OCCL_FLOOR < 1.0 - e.props[0].fade); // …a smaller first step out than in
    try std.testing.expectEqual(@as(usize, 1), e.noccl); // still in flight, so still being ticked
    t = step;
    while (t < OCCL_OUT + step) : (t += step) e.markOccluders(clear, v3(60, 1.0, 4), step);
    try std.testing.expectEqual(@as(f32, 1), e.props[0].fade); // exactly solid, not 0.997
    try std.testing.expectEqual(@as(usize, 0), e.noccl);
}

test "an occluder passing HIS depth eases out instead of snapping" {
    // The old rule cut at the plane through him: level with him it was fully thinned and a centimetre
    // past it fully solid, in one frame, right over the hero.
    const eye = v3(0, 2.2, -6);
    const hero = v3(0, 1.0, 0);
    const wide = 1.85;
    var prev = thinOf(eye, hero, v3(0, 0, -2.0), 6.0, wide); // well in front: as thin as it goes
    try std.testing.expect(prev > 0.99);
    for (1..19) |k| { // …walked in 20 cm steps from in front of him to well past him
        const z = -2.0 + 0.2 * @as(f32, @floatFromInt(k));
        const now = thinOf(eye, hero, v3(0, 0, z), 6.0, wide);
        try std.testing.expect(now <= prev + 1e-4); // monotone down…
        try std.testing.expect(prev - now < 0.2); // …in steps far too small to read as a pop
        prev = now;
    }
    try std.testing.expectApproxEqAbs(@as(f32, 0), prev, 1e-4); // past him: nothing
}

test "what covers him thins, what merely stands near the sight line does not" {
    const eye = v3(0, 2.2, -6);
    const hero = v3(0, 1.0, 0);
    // A great trunk 2 m in front of him, dead on the line: most of him.
    try std.testing.expect(coverFrac(eye, hero, v3(0, 0, -2), 6.0, 1.85).cover > OCCL_FULL);
    try std.testing.expect(coverFrac(eye, hero, v3(3.0, 0, -2), 6.0, 1.85).cover < OCCL_MIN);
    try std.testing.expect(coverFrac(eye, hero, v3(0, 0, -2), 0.5, 0.6).cover < OCCL_MIN);
    // Something chest-high across the line takes a real share of him without hiding him — the case the
    // ramp between the two thresholds exists for.
    const part = coverFrac(eye, hero, v3(0, 0, -2), 1.3, 1.85).cover;
    try std.testing.expect(part > OCCL_MIN and part < OCCL_FULL);
    try std.testing.expectEqual(@as(f32, 0), coverFrac(eye, hero, v3(0, 0, 4), 6.0, 1.85).cover);
}

test "COVERAGE ALONE OPENS THE GATE — the depth ramp scales the answer, it does not veto it" {
    // Fused into one number, a mass close in front of him had its coverage discounted under OCCL_MIN and
    // stayed solid at the one moment it was most in the way. It must thin, just not all the way.
    const eye = v3(0, 2.2, -6);
    const hero = v3(0, 1.0, 0);
    const near = v3(0, 0, -0.7); // inside OCCL_DEPTH_BAND of him, dead on the line
    try std.testing.expect(coverFrac(eye, hero, near, 6.0, 1.85).cover > OCCL_FULL);
    const a = coverFrac(eye, hero, near, 6.0, 1.85).ahead;
    try std.testing.expect(a > 0 and a < 1); // partway through the band
    const t = thinOf(eye, hero, near, 6.0, 1.85);
    try std.testing.expect(t > 0 and t < 1);
    try std.testing.expectApproxEqAbs(a, t, 1e-4); // full coverage, so the thinning IS the ramp
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
    // Straight through it, from far enough out that a fixed-size `nearSolids` copy would have dropped it.
    try std.testing.expect(!e.sees(v3(0, eye, -22), v3(0, eye, 22)));
    try std.testing.expect(!e.sees(v3(0, eye, -3), v3(0, eye, 3)));
    // Along it, and past its ends — the wall is a segment, not a plane.
    try std.testing.expect(e.sees(v3(-20, eye, -3), v3(20, eye, -3)));
    try std.testing.expect(e.sees(v3(40, eye, -22), v3(40, eye, 22)));
    // An empty world hides nothing.
    e.nprops = 0;
    buildSolids(e);
    try std.testing.expect(e.sees(v3(0, eye, -22), v3(0, eye, 22)));
}

// A test Env is ~1 MB of flat arrays, so these allocate one rather than putting it on the stack.
fn envWithRamp(rise: f32) !*Env {
    const e = try std.testing.allocator.create(Env);
    e.* = .{ .ground = undefined, .models = undefined };
    e.heightHalf = wf.DEFAULT_HALF;
    e.heightAny = true;
    // Height rises with x at `rise` metres per metre — a uniform slope, so the expected answer at any point is arithmetic rather than a lookup.
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
        const down = e.walkStep(v3(0, 0, 0), v3(-1, 0, 0), 0.1);
        try std.testing.expectApproxEqAbs(@as(f32, -0.1), down.x, 1e-4);
        const across = e.walkStep(v3(0, 0, 0), mathx.normV(v3(1, 0, 1)), 0.1);
        try std.testing.expect(@abs(across.z - 0.1) < 0.02); // kept the step's LENGTH along z
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
    const at = v3(-1.0, 0, 0); // a metre short of the face, on the low side
    const east = v3(1, 0, 0);
    const foot = e.groundAt(at.x, at.z);
    // On the deck and at the top of an ordinary jump alike, three metres of rock is still three metres of rock:
    // without this the hop lands ON the wall and `groundActor` hands him the climb.
    try std.testing.expectApproxEqAbs(at.x, e.flyStep(at, east, 2.0, foot).x, 1e-4);
    try std.testing.expectApproxEqAbs(at.x, e.flyStep(at, east, 2.0, foot + 1.0).x, 1e-4);
    // …and once his feet are genuinely over it, he crosses.
    try std.testing.expect(e.flyStep(at, east, 2.0, foot + WALL).x > at.x);
    // A jump may never travel WORSE than a step: a rise inside the walk's own allowance is taken from the
    // takeoff frame, feet still on the ground.
    const low = try envWithRamp(0.30);
    defer std.testing.allocator.destroy(low);
    const g0 = low.groundAt(0, 0);
    try std.testing.expect(low.flyStep(v3(0, 0, 0), east, 0.5, g0).x > 0.4);
}

test "A JUMP CLEARS A LOW COLLIDER AND A WALL IS STILL A WALL — the push-out reads `Solid.h`" {
    // The owner's report: jumping did not get him over low obstacles. `buildSolids` has always stamped each
    // collider's blocking height and `blocksPoint`/`blocksSight` have always honoured it — the PUSH-OUT was
    // the one consumer that did not, so a man at the top of his arc was shouldered off a fallen log.
    const HR = HERO_R_PIN; // the hero's own footprint, pinned to `foe.HERO_R` in game.zig
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };

    // A LOG: one capsule along X, blocking to 0.75 m — under the jump's 1.0 m apex.
    e.props[0] = .{ .kind = .log, .pos = v3(0, 0, 0), .yaw = 0, .scale = 1, .op = 0 };
    e.nprops = 1;
    buildSolids(e);
    const logTop = props.info(.log).parts[0].h;
    const at = v3(0, 0, 0.2); // stood in it, needing 2 × HR of clearance
    try std.testing.expect(e.resolveActor(at, HR, 0).z > 0.5); // on the deck it is in the way…
    // …and off the ground above its top it is not, to the bit.
    try std.testing.expectEqual(at.z, e.resolveActor(at, HR, logTop).z);
    try std.testing.expectEqual(at.z, e.resolveActor(at, HR, 0.9).z);
    // JUST UNDER the top is still a collider: the rule is the feet, not "airborne".
    try std.testing.expect(e.resolveActor(at, HR, logTop - 0.05).z > 0.5);

    // A WALL blocks to 3.0 m, which no jump in this game reaches, so the law survives intact.
    e.props[0] = .{ .kind = .wall, .pos = v3(0, 0, 0), .yaw = 0, .scale = 1, .op = 0 };
    buildSolids(e);
    try std.testing.expect(props.info(.wall).parts[0].h > 3.0 * logTop);
    try std.testing.expect(e.resolveActor(at, HR, 0.9).z > 0.5);

    // …AND THE HEIGHT IS A WORLD ONE, so a collider standing on a bank is not cleared by a jump taken below it.
    e.props[0] = .{ .kind = .log, .pos = v3(0, 2.0, 0), .yaw = 0, .scale = 1, .op = 0 };
    buildSolids(e);
    try std.testing.expect(e.resolveActor(at, HR, 0.9).z > 0.5);
}

test "a SLIGHT STEP is always taken, however steep the face carrying it" {
    // The owner's ask, and the other half of the anti-jank story: a low ledge is a step, not a wall.
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
    try std.testing.expect(e.groundAt(q.x, q.z) - GROUND_Y < 0.01); // still on the lower terrace
}

/// A SHELVING BEACH, painted wet edge to edge: the ground falls away with +x at `fall` metres per metre, so
/// the water gets steadily deeper and the bank is WALKABLE in both directions. That is the point — a dug
/// step would be a cliff, and the slope rule would stop him for reasons that have nothing to do with water.
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
    @memset(&e.waterField, 255); // wet everywhere, so only the DIG decides how deep it is
    return e;
}

test "DEEP WATER IS A WALL — waist-deep is waded, over the waist is refused, and wading OUT never is" {
    const e = try envWithBeach(0.25); // 14 deg of shelf: walkable, so only the water can refuse anything
    defer std.testing.allocator.destroy(e);
    try std.testing.expect(e.walkableAt(4, 0));

    // He wades in until it is over the waist, and no further, however long he pushes.
    var p = v3(-2.0, 0, 0);
    var i: usize = 0;
    while (i < 600) : (i += 1) p = e.walkStep(p, v3(1, 0, 0), 6.0 / 60.0);
    try std.testing.expect(e.wadeDepth(p.x, p.z) <= WADE_MAX);
    try std.testing.expect(p.x > 2.0); // …and he got properly wet on the way: this is a wall, not a fence

    // THE WALL IS THE WATER'S, not the shelf's: unpainted, the identical ground is walked straight down.
    e.waterAny = false;
    var q = v3(-2.0, 0, 0);
    i = 0;
    while (i < 600) : (i += 1) q = e.walkStep(q, v3(1, 0, 0), 6.0 / 60.0);
    try std.testing.expect(q.x > p.x + 10.0);

    // DROPPED IN IT (a playtest spawn, or a leap — a jump never asks this): every step toward the bank is
    // taken, or the gate that keeps him out would pin him in.
    e.waterAny = true;
    var r = v3(20.0, 0, 0);
    try std.testing.expect(e.wadeDepth(r.x, r.z) > WADE_MAX);
    i = 0;
    while (i < 600) : (i += 1) r = e.walkStep(r, v3(-1, 0, 0), 6.0 / 60.0);
    try std.testing.expect(e.wadeDepth(r.x, r.z) <= WADE_MAX);
}

test "DEEP WATER READS DEEP — the sheet is darkened by the DIG, not by the shore alone" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    m.blank("Tarn");
    try std.testing.expect(m.paintWater(0, 0, 60, true, .natural));

    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.uploadWater(m);
    // A CELL HARD AGAINST THE BANK, which is the whole case: out in the middle the shore ramp has already
    // saturated and there is nothing left for a dig to say.
    const RIM = v3(56, 0, 0);
    const flat = e.paintedDepth(RIM.x, RIM.z);
    try std.testing.expect(flat > 0 and flat < 0.6); // wet, and nowhere near the deep tone

    // …now cut a hole in it, well past the wade cap, and the same cell has to come back deeper.
    var span: [4]usize = undefined;
    try std.testing.expect(m.sculpt(RIM.x, RIM.z, 10, .lower, 3.0, &span));
    e.uploadWater(m);
    try std.testing.expect(e.paintedDepth(RIM.x, RIM.z) > flat + 0.2);

    // …and the ramp tops out AT the wall, so the darkest water is exactly the water he is refused.
    try std.testing.expectApproxEqAbs(@as(f32, 1), digTone(WADE_MAX), 1e-6);
    try std.testing.expect(digTone(WADE_MAX * 0.5) < 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 1), digTone(WADE_MAX * 4.0), 1e-6); // and stays there
    try std.testing.expectApproxEqAbs(@as(f32, 0), digTone(-1.0), 1e-6); // ground standing proud is not water
}

test "the wade cap is the CHEST" {
    try std.testing.expect(WADE_MAX > 1.3 and WADE_MAX < 1.45); // the thorax on the 1.8 m rig is 1.368
    try std.testing.expect(WADE_MAX > STEP_UP); // …and deeper than a step is tall, or a kerb would refuse
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
    const flatT = (GROUND_Y - 60.0) / -0.5; // the plane answer for the ray below
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
    try std.testing.expect(lo <= 0.02); // somewhere is bare
    try std.testing.expect(hi >= 1.15); // somewhere is choked
    const mean = sum / n;
    try std.testing.expect(mean > 0.45 and mean < 0.80);
}

test "the SHIPPED map parses, and its zones cover every reachable position" {
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
    try std.testing.expect(RIM_OUT > 0);
    // CLIFF_BOUND is a hand-copied mirror of the mesh's own bound, because MAX_HALF has to be a comptime value and `props.info` is a runtime lookup.
    try std.testing.expectApproxEqAbs(CLIFF_BOUND, props.info(.cliff).bound, 1e-4);
    try std.testing.expect(wf.DEFAULT_HALF <= MAX_HALF);
    try std.testing.expect(GROUND_HALF > wf.DEFAULT_HALF + 200);
}

test "THE BROOD ARENA LOADS — a scratch map is only useful if it is known to still parse" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    var line: usize = 0;
    wf.load(wf.DIR ++ "/02_brood_arena" ++ wf.EXT, m, &line) catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest; // run from another cwd
        return e;
    };
    var mothers: usize = 0;
    for (m.foes[0..m.nfoes]) |f| {
        if (f.kind == .brood_mother) mothers += 1;
    }
    try std.testing.expect(mothers > 0);
}

test "replaying the SHIPPED map produces a stable world" {
    // That `materialize` expands the real map, and expands it the SAME way every time.
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

    // 17761 BEFORE THE COAST WAS FACETED (`facetWater`), then 17565. Scatter refuses to place in water, so
    // straightening the waterline moves it by up to half a facet and the props along every shore follow it —
    // 196 of them, about 1%. This number moving is the POINT of pinning it; it may only be re-pinned when the
    // world was meant to change. The BONE KNIGHT'S ground was the last such change: the ruin east of the
    // graves gained a torch line, a rock belt and its cliffs, and lost the watchtower and two cottages that
    // stood in it. 17594/1854 was written for that edit but never matched the map saved beside it — these are
    // the counts the shipped file actually replays to. `materialize` reads the OPS alone, so foe records
    // (the delver's three) cannot move either figure.
    // …and 17323 since the NECROMANCER'S ground was authored west of the graves: two cliffs, a chest and the
    // encounter itself (a necromancer with two archers and a shieldman to raise), plus two more delvers east.
    // …then 17329 for the six `pickup` glows scattered over the map — one prop each, and `props.INFO`'s row
    // gives that kind `.casts = false` with no collider, so `solids0` does not move with it and `lights0` does.
    try std.testing.expectEqual(@as(usize, 17329), props0);
    try std.testing.expectEqual(@as(usize, 1754), solids0); // …and their colliders with them (was 1749, 1827, 1848)
    // The map's three `campfire`s are the EXTINGUISHED kind and carry no light. Swap one to
    // `campfire_lit` in the editor and this goes up by one — and gains a rest site with it.
    // 46 since the Bone Knight's ruin was lit: seven torches went in round it and one came out with the
    // watchtower that used to stand there. 52 with the six pickup glows: an item on the ground is a LIGHT
    // (`props.INFO`'s `pickup` row), which is how you find one across a field.
    try std.testing.expectEqual(@as(usize, 52), lights0);

    var jerky: usize = 0;
    var rings: usize = 0;
    var chestOps: usize = 0;
    for (m.ops[0..m.nops]) |*op| {
        if (op.kind != .chest) continue;
        chestOps += 1;
        for (op.loot[0..op.nloot]) |it| {
            if (it == .mushroom_jerky) jerky += 1;
            if (item.bindsSouls(it)) rings += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), jerky);
    // …AND ONE BINDING RING IN THE WORLD, which is the whole of what makes it worth anything: it is the one
    // death you get to refuse, and a box that refilled with them would be a death you never have to take.
    try std.testing.expectEqual(@as(usize, 1), rings);

    var boxes: [chestmod.CAP]chestmod.Site = undefined;
    try std.testing.expectEqual(chestOps, e.chestSites(&boxes));
    var fires: [restmod.CAP]restmod.Site = undefined;
    try std.testing.expect(e.restSites(&fires) > 0);
}

test "EVERY SHIPPED MAP LOADS AND MATERIALIZES, not just the one the game starts on" {
    // A test arena nobody boots into is a file that rots: the shipped plain is the only map with a build-time
    // guard, so an op renamed under `02`/`03` would surface as a PANIC in the editor's Open dialog months
    // later. WALKED OFF THE DIRECTORY, not off a list, which silently stops covering the map you add next.
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
        try std.testing.expect(e.propCount() > 0);
        seen += 1;
    }
    try std.testing.expect(seen >= 3); // the plain and the two arenas, at least — or the walk found nothing
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
    try std.testing.expectEqual(m.nfoes, shields + blades); // and nothing else, or it is not a test zone

    // …AND A LIT CAMPFIRE IS A PLACE TO SIT. The court posts one of each campfire on purpose: the cold
    // one must stay dressing, and the lit one must come back as a real rest site with the bonfire.
    e.* = .{ .ground = undefined, .models = undefined };
    e.materialize(m);
    var sites: [restmod.CAP]restmod.Site = undefined;
    try std.testing.expectEqual(@as(usize, 2), e.restSites(&sites)); // the bonfire AND the campfire
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
    wf.load(wf.START_MAP, m, &line) catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest; // run from another cwd
        return e;
    };
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
    // …and a SCULPTED map must not take the shortcut, or the whole world plants at the datum.
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

