const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const collision = @import("collision.zig");
const props = @import("props.zig");
const wf = @import("worldfmt.zig");
const chestmod = @import("chest.zig");
const pickupmod = @import("pickup.zig");
const item = @import("item.zig");
const restmod = @import("rest.zig");

const v3 = mathx.v3;
const Kind = props.Kind;


pub const RIM_OUT: f32 = 6.0;
pub const PLAY_INSET: f32 = 2.0;
pub const MAX_HALF: f32 = GRID_HALF + CELL - RIM_OUT - CLIFF_BOUND;

comptime {
    std.debug.assert(MAX_HALF >= wf.MAX_DECLARED_HALF);
}
const CLIFF_BOUND: f32 = 18.0;
const GROUND_HALF: f32 = wf.DEFAULT_HALF + 220.0;

const MAX_PROPS = 24576;
const MAX_SOLIDS = 8192;
const MAX_SOLID_REFS = 4 * MAX_SOLIDS;
const MAX_LIGHTS = 192;
const MAX_DRESSED = 64;

// 40 a side = 640 m, covering a 280 m map's cliff ring (286 + 18 of cliff bound) with room over. The arrays
// are BSS and the per-frame cost is one loop of four plane tests, so 1,600 cells is not measurable.
const CELL: f32 = 16.0;
const GRID_N: usize = 40;
const GRID_SPAN: f32 = CELL * @as(f32, @floatFromInt(GRID_N));
const GRID_HALF: f32 = GRID_SPAN * 0.5;
const NCELL: usize = GRID_N * GRID_N;
const HALF_DIAG: f32 = @sqrt(0.5);
const CELL_CIRCUM: f32 = CELL * HALF_DIAG;

const SHADOW_BOX: f32 = gfx.SHADOW_ORTHO * HALF_DIAG;

const LIGHT_REACH: f32 = 90.0;

pub const OCCL_MAX = 64;
const OCCL_IN: f32 = 0.16;
const OCCL_OUT: f32 = 0.34;
const FADE_SOLID: f32 = 0.999;
const GL_ZERO: i32 = 0;
const GL_ONE: i32 = 1;
const GL_FUNC_ADD: i32 = 0x8006;
/// How fast the ramp runs where the value already sits: full speed across the middle, down to this share at
/// solid and at the floor. Never 0, or a fade would never leave either end.
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
/// A thinned occluder NEVER disappears: you must still be able to tell a tree is there.
const OCCL_FLOOR: f32 = 0.28;
const OCCL_MIN: f32 = 0.15;
const OCCL_FULL: f32 = 0.55;
/// The hero's own screen box, in metres — what "a share of him" is measured against.
const HERO_HALF_W: f32 = 0.42;
const HERO_HALF_H: f32 = 0.90;
/// How far past its own collider a standing mass still blocks the view. ONLY FOR KINDS WITH NO `occl`
/// LIST: a fixed skirt cannot describe a canopy, which is why the trees carry their own volumes.
const OCCL_SKIRT: f32 = 0.9;
const OCCL_GIRTH: f32 = 0.55;
/// **HOW TALL GROUND COVER HAS TO STAND BEFORE IT THINS AT ALL, in metres** — HIS WAIST, the rig's SPINE at
/// 0.640·H on the 1.8 m stature, written out for `WADE_MAX`'s reason. Flora is in the scan, but a tuft is
/// not, and coverage will not draw that line: a tuft up against the lens scores 0.54, over three times
/// `OCCL_MIN`, so ungated the commonest thing in the world ghosts round his boots every time the lens dips.
/// TESTED ON THE INSTANCE (`top * scale`), not the kind — the cover scatter stamps 0.72..1.38, and how tall
/// the thing standing there actually is the only question worth asking. At his HIP instead this let 316
/// scaled patches and 303 ferns back in, which is the grass it is here to keep out.
const OCCL_TALL: f32 = 1.15;
const OCCL_REACH: f32 = CELL;
const OCCL_DEPTH_BAND: f32 = 1.6;

pub const MAX_NEAR = 160;

const GROUND_Y: f32 = 0.01;

// The ground is a HEIGHTFIELD (`wf.Map.height`, 2.5 m lattice, sculpted in the editor).
const TCHUNK: usize = 16;
const TILES: usize = (wf.HEIGHT_N - 2) / (TCHUNK - 1) + 1;
const NTILES: usize = TILES * TILES;

/// How steep the ground may be and still be walked, as the TANGENT of the slope angle (rise over run). tan 40 deg
pub const MAX_SLOPE: f32 = 0.839;
pub const STEP_UP: f32 = 0.55;
pub const STEP_PROBE: f32 = 0.5;

/// HOW DEEP ANYTHING ON FOOT MAY WADE, in metres — CHEST HEIGHT (owner's call), the thorax at 0.760·H on
/// the 1.8 m rig. Past it the water is a WALL. Written out rather than read off `hero.H` because env sits
/// BELOW hero in the import graph and stays there.
pub const WADE_MAX: f32 = 1.37;

pub const HERO_R_PIN: f32 = 0.36;

fn digTone(metres: f32) f32 {
    return mathx.clampF(metres / WADE_MAX, 0, 1);
}

const WATER_Y: f32 = 0.055;

var scratchIn: [wf.WATER_CELLS]f32 = undefined;
var scratchOut: [wf.WATER_CELLS]f32 = undefined;

pub const WATER_FACET: f32 = 3.6;

fn coastWarp(e: wf.Edge, x: f32, z: f32) f32 {
    return switch (e) {
        // A shore you cannot find the edge of. No warp — the width is `coastBand`'s say, not this one's.
        .blend => 0,
        .natural => (vnoise2(x / 13.0, z / 13.0) - 0.5) * 4.4,
        .frayed => (vnoise2(x / 5.5 + 12.3, z / 5.5 - 7.1) - 0.5) * 3.0,
        .jagged => (vnoise2(x / 6.0 + 3.3, z / 6.0 + 9.9) - 0.5) * 7.0 +
            (vnoise2(x / 2.2 - 5.0, z / 2.2 + 4.0) - 0.5) * 2.6,
        .straight => 0,
        .tiled => tiledCoast(x, z),
        .scallop => (mathx.sinf(x * 0.34) + mathx.sinf(z * 0.34)) * 2.3,
        .speckle => (vnoise2(x / 3.0 + 21.0, z / 3.0 - 17.0) - 0.5) * 8.0 - 1.4,
    };
}

fn tiledCoast(x: f32, z: f32) f32 {
    const g = WATER_FACET;
    const sx = x / g - @floor(x / g);
    const sz = z / g - @floor(z / g);
    const dx = (0.5 - @abs(sx - 0.5)) * g;
    const dz = (0.5 - @abs(sz - 0.5)) * g;
    return -@min(dx, dz);
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

fn facetWater(field: *[wf.WATER_CELLS]u8, half: f32) void {
    const N = wf.WATER_N;
    if (!(half > 0)) return;
    const cell = 2 * half / @as(f32, @floatFromInt(N));
    const facet = @max(WATER_FACET, cell * 1.2);

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
    gone: bool = false,
    shrink: f32 = 1,
};

// A prop can stand OFF PLUMB: `lean` degrees toward `leanDir`, measured like every yaw here — (cos d, −sin d).

fn leanToward(dirDeg: f32) rl.Vector3 {
    const a = mathx.radians(dirDeg);
    return v3(mathx.cosf(a), 0, -mathx.sinf(a));
}

fn leanAxis(dirDeg: f32) rl.Vector3 {
    const d = leanToward(dirDeg);
    return v3(d.z, 0, -d.x);
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

const FIELD_FLOOR: f32 = 0.35;

const SOLID_PROBE_Y: f32 = 0.2;
const SOLID_PROBE_M: f32 = 0.35;
const SOLID_PROBE_R: f32 = 1.4;

pub fn groundY() f32 {
    return GROUND_Y;
}

// A fire's static description; the per-frame guttering is applied in uploadLights.
/// **A LIGHT BELONGS TO THE PROP THAT PLACED IT** (`prop`, an index into `props`). Placed at materialize time
/// with no back-reference, a pickup glow's own 5.4 m pool went on lighting the ground for the rest of the
/// session after the glow had been taken — the occluder's bug one pass along, and visible from every angle
/// rather than one. `lightOf` is where the ownership is read.
const WorldLight = struct { base: gfx.Light, flicker: f32, phase: f32, prop: u32 };

const Pool = struct { pos: rl.Vector3, radius: f32 };

const Index = struct {
    start: [NCELL + 1]u32 = [_]u32{0} ** (NCELL + 1),
    items: [MAX_PROPS]u32 = undefined,
    bound: [NCELL]f32 = [_]f32{0} ** NCELL,
    view: [NCELL]f32 = [_]f32{0} ** NCELL,
    top: [NCELL]f32 = [_]f32{0} ** NCELL,
    // …and the cell's VERTICAL extent: the per-cell reject is a sphere about the cell's centre, and a cell
    // whose props stand 20 m up a hill is nowhere near a sphere centred at y = 0.
    ylo: [NCELL]f32 = [_]f32{0} ** NCELL,
    yhi: [NCELL]f32 = [_]f32{0} ** NCELL,
};

pub const View = struct {
    pos: rl.Vector3,
    n: [4]rl.Vector3,

    pub fn fromCamera(cam: rl.Camera3D, aspect: f32) View {
        const fwd = mathx.normV(mathx.subV(cam.target, cam.position));
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
    view: View,
    sun: rl.Vector3,
};

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
    solid_buf: [MAX_SOLIDS]collision.Solid = undefined,
    nsolids: usize = 0,
    stx: Index = .{},
    flx: Index = .{},
    occl: [OCCL_MAX]u32 = undefined,
    noccl: usize = 0,
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
    heightField: [wf.HEIGHT_CELLS]u8 = [_]u8{wf.HEIGHT_ZERO} ** wf.HEIGHT_CELLS,
    heightHalf: f32 = wf.DEFAULT_HALF,
    heightAny: bool = false,
    tiles: [NTILES]rl.Model = undefined,
    tileBuilt: [NTILES]bool = [_]bool{false} ** NTILES,
    tileMid: [NTILES]rl.Vector3 = [_]rl.Vector3{mathx.zero3} ** NTILES,
    tileRad: [NTILES]f32 = [_]f32{0} ** NTILES,
    skirt: rl.Model = undefined,
    skirtBuilt: bool = false,
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
        self.noccl = 0;
        self.ndress = 0;
        self.nchests = 0;
        self.nrests = 0;
        self.stat_draws = 0;
        self.stat_cells = 0;
        self.stowed = false;
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
        if (x0 + 1 >= wf.HEIGHT_N or z0 + 1 >= wf.HEIGHT_N) return;
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
        for (m.water, 0..) |wet, i| {
            const wx = edge(i % N, m.half, cell) + cell * 0.5;
            const wz = edge(i / N, m.half, cell) + cell * 0.5;
            const shape: wf.Edge = @enumFromInt(@min(m.waterEdge[i], wf.Edge.N - 1));
            const sd = coastWarp(shape, wx, wz) + if (wet != 0)
                @max(0.0, (dIn[i] - 0.5) * cell)
            else
                -@max(0.0, (dOut[i] - 0.5) * cell);
            const enc: f32 = if (sd >= 0) blk: {
                const byShore = mathx.clampF(sd / gfx.WATER_DEEP_AT, 0, 1);
                const dug = WATER_Y - (GROUND_Y + m.heightAt(edge(i % N, m.half, cell), edge(i / N, m.half, cell)));
                break :blk shoreF + @max(byShore, digTone(dug)) * (255.0 - shoreF);
            } else blk: {
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
            rl.drawModelEx(self.waterSheet, self.waterMid, v3(0, 1, 0), 0, self.waterSpan, rl.Color.white);
            sc.setWaterSheet(false, undefined);
        }
    }

    pub fn materialize(self: *Env, m: *const wf.Map) void {
        self.nprops = 0;
        self.nsolids = 0;
        self.nlights = 0;
        self.npools = 0;
        self.noccl = 0;
        @memset(&self.sgrid_start, 0);

        var p = Placer{ .e = self, .m = m, .flat = !m.anyHeight() };
        for (m.slice(), 0..) |*o, i| {
            p.cur = @intCast(i);
            if (o.op != .cover) p.expand(o);
        }
        buildSolids(self);
        const beforeCover = self.nprops;
        for (m.slice(), 0..) |*o, i| {
            p.cur = @intCast(i);
            if (o.op == .cover) p.expand(o);
        }
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
        self.noccl = 0;
        self.props[0] = .{ .kind = kind, .pos = v3(0, 0, 0), .yaw = 0, .scale = 1.0, .op = 0 };
        self.nprops = 1;
        if (props.info(kind).light) |ls| {
            self.lights[0] = .{ .base = .{ .pos = v3(0, ls.y, 0), .col = ls.col, .radius = ls.radius }, .flicker = ls.flicker, .phase = 0, .prop = 0 };
            self.nlights = 1;
        }
        buildSolids(self);
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
                    if (!visit(ctx, self.solid_buf[self.sgrid_items[k]])) return;
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
        const Push = struct {
            at: rl.Vector3,
            r: f32,
            footY: f32,
            fn one(c: *@This(), s: collision.Solid) bool {
                if (c.footY >= s.h) return true;
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


    pub fn groundAt(self: *const Env, x: f32, z: f32) f32 {
        if (!self.heightAny) return GROUND_Y;
        return GROUND_Y + wf.sampleHeight(&self.heightField, self.heightHalf, x, z);
    }

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

    pub fn walkStep(self: *const Env, from: rl.Vector3, dir: rl.Vector3, dist: f32) rl.Vector3 {
        const to = v3(from.x + dir.x * dist, from.y, from.z + dir.z * dist);
        if (!self.heightAny or dist <= 0) return to;
        if (self.deepRefused(from.x, from.z, to.x, to.z)) return v3(from.x, from.y, from.z);
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

    pub fn flyStep(self: *const Env, from: rl.Vector3, dir: rl.Vector3, dist: f32, footY: f32) rl.Vector3 {
        const to = v3(from.x + dir.x * dist, from.y, from.z + dir.z * dist);
        if (!self.heightAny or dist <= 0) return to;
        if (self.groundAt(to.x, to.z) <= footY + STEP_UP) return to;
        return v3(from.x, from.y, from.z);
    }

    fn stepOk(self: *const Env, from: rl.Vector3, dir: rl.Vector3, dist: f32) bool {
        const probe = mathx.maxF(dist, STEP_PROBE);
        const h0 = self.groundAt(from.x, from.z);
        const h1 = self.groundAt(from.x + dir.x * probe, from.z + dir.z * probe);
        const rise = h1 - h0;
        return rise <= mathx.maxF(STEP_UP, MAX_SLOPE * probe);
    }

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
        const margin = (1.0 - mathx.clampF(inset, 0, 1)) * gfx.WATER_DEEP_AT;
        return self.paintedDepth(x, z) * gfx.WATER_DEEP_AT > margin + 0.01;
    }

    pub fn paintedDepth(self: *const Env, x: f32, z: f32) f32 {
        if (!self.waterAny) return 0;
        const i = wf.gridIndex(self.waterHalf, wf.WATER_N, x, z) orelse return 0;
        const v: f32 = @floatFromInt(self.waterField[i]);
        const shore: f32 = @floatFromInt(gfx.WATER_SHORE);
        if (v <= shore) return 0;
        return (v - shore) / (255.0 - shore);
    }

    pub fn wadeDepth(self: *const Env, x: f32, z: f32) f32 {
        if (self.paintedDepth(x, z) <= 0) return 0;
        return mathx.maxF(0, WATER_Y - self.groundAt(x, z));
    }

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
        for (self.props[0..self.nprops], 0..) |*pr, i| {
            const nfo = props.info(pr.kind);
            const sw = leanSwing(pr, nfo.top * pr.scale * 0.5);
            const c = v3(pr.pos.x + sw.x, pr.pos.y + nfo.top * pr.scale * 0.5, pr.pos.z + sw.z);
            const rad = @max(nfo.bound * pr.scale * 0.5, 0.35);
            const oc = mathx.subV(c, origin);
            const along = oc.x * dir.x + oc.y * dir.y + oc.z * dir.z;
            if (along <= 0 or along >= bestT) continue;
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
        if (self.skirtBuilt) self.skirt.materials[0].shader = sh;
    }

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

    pub fn resetStats(self: *Env) void {
        self.stat_draws = 0;
        self.stat_cells = 0;
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
            const mdl = self.veils[@intFromEnum(pr.kind)] orelse continue;
            const nfo = props.info(pr.kind);
            if (!view.visible(pr.pos, nfo.bound * pr.scale, nfo.view)) continue;
            self.stat_draws += 1;
            const sc = v3(pr.scale, pr.scale, pr.scale);
            rl.drawModelEx(mdl, pr.pos, v3(0, 1, 0), pr.yaw, sc, rl.Color.white);
        }
    }

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
                if (pr.gone) continue;
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

    fn drawProp(self: *const Env, pr: *const Prop) void {
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

    pub fn drawThinned(self: *Env, view: *const View) void {
        var order: [OCCL_MAX]u32 = undefined;
        var far: [OCCL_MAX]f32 = undefined;
        var n: usize = 0;
        for (self.occl[0..self.noccl]) |pi| {
            const pr = &self.props[pi];
            if (pr.gone) continue;
            if (pr.fade >= FADE_SOLID) continue;
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
        const k = 1.0 + wl.flicker * gutter(t, wl.phase);
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

// A flame's guttering, in [-1, 1]: three incommensurate rates so it never reads as a pulse.
fn gutter(t: f32, phase: f32) f32 {
    return 0.30 * mathx.sinf(t * 4.3 + phase) + 0.14 * mathx.sinf(t * 8.9 + phase * 2.3) + 0.56 * mathx.sinf(t * 1.7 + phase * 0.6);
}

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

fn tileOf(point: usize) usize {
    return @min(point / (TCHUNK - 1), TILES - 1);
}

fn cellCoord(w: f32) usize {
    return @intFromFloat(mathx.clampF((w + GRID_HALF) / CELL, 0, @floatFromInt(GRID_N - 1)));
}

fn cellOf(x: f32, z: f32) usize {
    return cellCoord(z) * GRID_N + cellCoord(x);
}

const PropFrame = struct {
    pr: *const Prop,
    c: f32,
    sn: f32,

    fn of(pr: *const Prop) PropFrame {
        const th = mathx.radians(pr.yaw);
        return .{ .pr = pr, .c = mathx.cosf(th), .sn = mathx.sinf(th) };
    }
    fn at(self: PropFrame, lx: f32, ly: f32, lz: f32) rl.Vector3 {
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

/// 0 (solid) .. 1 (as thin as it gets) — the deepest ask any of its masses makes. Three sources in order:
/// the kind's declared volumes, the COLLIDERS plus a skirt, and for a kind with neither a share of the
/// bound. A collider is sized for what you WALK INTO, and on a tree it is wrong by metres: a conifer's
/// 1.48 m cylinder against boughs that block the view at 3.8 m.
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
        thin = thinOf(eye, at, pr.pos, nfo.top * pr.scale, nfo.bound * pr.scale * OCCL_GIRTH);
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

/// Overlap of two boxes in the EYE'S TANGENT PLANE, before any FOV scale, so the answer is in fractions of
/// him. Distance to the sight line cannot answer it: a stump on the line covers his boots, a canopy fifteen
/// metres up covers nothing.
fn coverFrac(eye: rl.Vector3, at: rl.Vector3, foot: rl.Vector3, h: f32, r: f32) Cover {
    const toH = mathx.subV(at, eye);
    const dh = mathx.lenV(toH);
    if (dh < 0.5) return NO_COVER;
    const fwd = mathx.scaleV(toH, 1.0 / dh);
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
        if (props.info(kind).light) |ls| self.addLight(@intCast(self.e.nprops - 1), x, y, z, scale, ls, rng);
        if (kind == .water) {
            if (self.e.npools >= self.e.pools.len) @panic("env: water pool cap exceeded — raise Env.pools");
            self.e.pools[self.e.npools] = .{ .pos = v3(x, y, z), .radius = 13.0 * scale };
            self.e.npools += 1;
        }
    }

    fn addLight(self: *Placer, pi: u32, x: f32, y: f32, z: f32, scale: f32, ls: props.LightSpec, rng: *mathx.Rng) void {
        if (self.e.nlights >= MAX_LIGHTS) return;
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

    fn expand(self: *Placer, o: *const wf.Op) void {
        var rng = o.stream();
        self.lean = o.lean;
        self.leanDir = o.leanDir;
        self.leanExact = o.op == .at;
        switch (o.op) {
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

    fn belt(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        var i: i32 = 0;
        while (i < o.n) : (i += 1) {
            const x = rng.range(o.x, o.x1);
            const z = rng.range(o.z, o.z1);
            if (!self.accepts(o, x, z, rng)) continue;
            self.at(o.pick(rng), x, z, rng.range(0, 360), rng.range(o.sLo, o.sHi), rng);
        }
    }

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

    fn ring(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        var i: i32 = 0;
        while (i < o.n) : (i += 1) {
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
            switch (pr.kind) {
                .wall, .pillar, .broken, .block, .arch, .statue, .cottage, .chapel, .watchtower, .stairs, .monolith => {},
                else => continue,
            }
            if (pr.pos.x < o.x or pr.pos.x > o.x1 or pr.pos.z < o.z or pr.pos.z > o.z1) continue;
            if (rng.float() > o.chance) continue;
            const nfo = props.info(pr.kind);
            const a = rng.angle();
            const d = nfo.bound * pr.scale * rng.range(0.18, 0.42);
            self.at(o.kind, pr.pos.x + mathx.cosf(a) * d, pr.pos.z + mathx.sinf(a) * d, mathx.degrees(a), rng.range(o.sLo, o.sHi), rng);
        }
    }

    fn edge(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        if (o.r0 < 1e-4) return;
        const rim = self.m.half + RIM_OUT;
        var t: f32 = -rim;
        while (t <= rim) : (t += o.r0) {
            const jitter = rng.signed() * 1.6;
            self.at(o.pick(rng), t + jitter, -rim - rng.range(0, 2.5), 180 + rng.signed() * 7, ridge(o, t, rng), rng);
            self.at(o.pick(rng), t - jitter, rim + rng.range(0, 2.5), 0 + rng.signed() * 7, ridge(o, t + 91, rng), rng);
            self.at(o.pick(rng), rim + rng.range(0, 2.5), t + jitter, 90 + rng.signed() * 7, ridge(o, t + 213, rng), rng);
            self.at(o.pick(rng), -rim - rng.range(0, 2.5), t - jitter, 270 + rng.signed() * 7, ridge(o, t + 347, rng), rng);
        }
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
        const fr = PropFrame.of(pr);
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
    // A conifer's collider is a 0.58 m pole and its boughs reach 3.4 m, so a camera looking through the
    // branches scores nothing against the pole.
    const e = try std.testing.allocator.create(Env);
    defer std.testing.allocator.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    e.props[0] = .{ .kind = .conifer, .pos = v3(2.6, 0, 0), .yaw = 0, .scale = 1 };
    e.nprops = 1;
    fillIndex(e, &e.stx, false);
    const nfo = props.info(.conifer);
    const eye = v3(0, 2.2, -5);
    const hero = v3(0, 1.0, 3);

    // The colliders alone cannot see it at all.
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
        // …BUT THE GATE IS ON THE INSTANCE, NOT THE KIND: a bramble is knee-high at nominal scale and a
        // waist-high mass at 1.38, and what the player has to see past is the second one.
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
    const outside = SHADOW_BOX + 10.0;
    try std.testing.expect(castsInto(focus, v3(outside, 0, 0), 18.0, 15.5));
    try std.testing.expect(!castsInto(focus, v3(outside, 0, 0), 0.9, 0.8));
    try std.testing.expect(!castsInto(focus, v3(SHADOW_BOX + 60.0, 0, 0), 18.0, 15.5));
    try std.testing.expect(castsInto(focus, v3(SHADOW_BOX - 10.0, 0, 0), 0.2, 0.2));
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

    // A camera at a real boom height, the hero 4 m the far side of the trunk. SETTLED: what the geometry
    // asks for and what the picture has got to are two questions (`easeFades`).
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
    // A great trunk 2 m in front of him, dead on the line: most of him.
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
    // A jump may never travel WORSE than a step: a rise inside the walk's own allowance is taken from the
    // takeoff frame, feet still on the ground.
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

test "DEEP WATER READS DEEP — the sheet is darkened by the DIG, not by the shore alone" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    m.blank("Tarn");
    try std.testing.expect(m.paintWater(0, 0, 60, true, .natural));

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
    wf.load(wf.START_MAP, m, &line) catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest;
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
        if (o.op == .at) continue;
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
        if (e == error.FileNotFound) return error.SkipZigTest;
        return e;
    };
    var mothers: usize = 0;
    for (m.foes[0..m.nfoes]) |f| {
        if (f.kind == .brood_mother) mothers += 1;
    }
    try std.testing.expect(mothers > 0);
}

const PIN_PROPS: usize = 17535;
const PIN_SOLIDS: usize = 1798;
const PIN_LIGHTS: usize = 71;
const PIN_JERKY: usize = 2;

test "replaying the SHIPPED map produces a stable world" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    var line: usize = 0;
    wf.load(wf.START_MAP, m, &line) catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest;
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

    if (props0 != PIN_PROPS or solids0 != PIN_SOLIDS or lights0 != PIN_LIGHTS) {
        std.debug.print("\n  SHIPPED MAP MOVED - re-pin: props {d}, solids {d}, lights {d}\n", .{ props0, solids0, lights0 });
    }
    // THESE MOVING IS THE POINT OF PINNING THEM: re-pin only when the world was MEANT to change. Anything
    // touching the waterline shifts the shore scatter by up to half a facet (`facetWater` moved 196 props),
    // and `materialize` reads the OPS alone, so foe records cannot move any of the three.
    try std.testing.expectEqual(PIN_PROPS, props0);
    try std.testing.expectEqual(PIN_SOLIDS, solids0);
    // An item pickup is a LIGHT with no collider (`props.INFO`), so it moves this and `props0` but never
    // `solids0`. The map's three `campfire`s are the EXTINGUISHED kind; swapping one to `campfire_lit` in
    // the editor adds a light here and a rest site with it.
    try std.testing.expectEqual(PIN_LIGHTS, lights0);

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
    try std.testing.expectEqual(PIN_JERKY, jerky);
    try std.testing.expectEqual(@as(usize, 1), rings);

    var boxes: [chestmod.CAP]chestmod.Site = undefined;
    try std.testing.expectEqual(chestOps, e.chestSites(&boxes));
    var fires: [restmod.CAP]restmod.Site = undefined;
    try std.testing.expect(e.restSites(&fires) > 0);
}

test "A FEN LURKER IS POSTED IN WATER IT CAN ACTUALLY HIDE IN" {
    const fen = @import("fenlurker.zig");
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    var line: usize = 0;
    wf.load(wf.DIR ++ "/test_fenlurker" ++ wf.EXT, m, &line) catch return error.SkipZigTest;
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
    wf.load(wf.START_MAP, m, &line) catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest;
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

