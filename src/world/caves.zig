const std = @import("std");
const mathx = @import("../core/mathx.zig");
const wf = @import("worldfmt.zig");
const NL = "\n";

/// Where the cave bench is written; `wf.save` panics under `is_test` on anything but `worlds/test_*.world`.
pub const BENCH_PATH = wf.DIR ++ "/test_caves" ++ wf.EXT;

pub const N = wf.CAVE_N;
pub const CELLS = wf.CAVE_CELLS;

pub const EDGE = wf.CAVE_EDGE;

/// THE ENTRANCE TOOL'S OWN NUMBERS, and they live here because two things cut one: the editor's Entrance brush and
/// `--fix-caves`. An entrance floor falls this much per metre run — well inside `wf.MAX_SLOPE`, so the grade it
/// lays is walkable without the author solving one.
pub const ENTRANCE_GRADE: f32 = 0.5;
/// How far under the ground an entrance starts, so the first step in is a step and not a drop.
pub const ENTRANCE_SINK: f32 = 0.25;
/// The least headroom a chamber may be given, in metres.
pub const HEAD_MIN: f32 = 2.0;
/// Rock thinner than this over a ceiling is not a roof. `--fix-caves` drops what has less; the editor's Fit lays a floor that leaves exactly this much.
pub const ROOF_MIN: f32 = 1.0;

/// The floor a body stands on, and WHICH world it stands in. Height alone cannot tell the hillside from the chamber under it.
pub const Surface = enum(u8) { land, cave };

pub const Support = struct { y: f32, surface: Surface };

/// Solid rock, the sky's air, or the air a carve left.
pub const Space = enum(u8) { rock, sky, cave };

pub fn cellStep(half: f32) f32 {
    return 2 * half / @as(f32, @floatFromInt(N - 1));
}

pub fn pointAt(half: f32, ix: usize, iz: usize) [2]f32 {
    const step = cellStep(half);
    return .{ -half + @as(f32, @floatFromInt(ix)) * step, -half + @as(f32, @floatFromInt(iz)) * step };
}

const Lerp = struct {
    i00: usize,
    i10: usize,
    i01: usize,
    i11: usize,
    tx: f32,
    tz: f32,

    fn of(half: f32, px: f32, pz: f32) Lerp {
        const last: f32 = @floatFromInt(N - 1);
        const step = cellStep(half);
        const fx = mathx.clampF((px + half) / step, 0, last);
        const fz = mathx.clampF((pz + half) / step, 0, last);
        const x0: usize = @intFromFloat(@floor(fx));
        const z0: usize = @intFromFloat(@floor(fz));
        const x1 = @min(x0 + 1, N - 1);
        const z1 = @min(z0 + 1, N - 1);
        return .{
            .i00 = z0 * N + x0,
            .i10 = z0 * N + x1,
            .i01 = z1 * N + x0,
            .i11 = z1 * N + x1,
            .tx = fx - @floor(fx),
            .tz = fz - @floor(fz),
        };
    }

    fn cov(self: Lerp, field: []const u8) f32 {
        const a = mathx.lerpF(covF(field[self.i00]), covF(field[self.i10]), self.tx);
        const b = mathx.lerpF(covF(field[self.i01]), covF(field[self.i11]), self.tx);
        return mathx.lerpF(a, b, self.tz);
    }

    fn hgt(self: Lerp, f: Fields, field: []const u8, base: f32) f32 {
        const a = mathx.lerpF(ghostHeight(f, field, self.i00), ghostHeight(f, field, self.i10), self.tx);
        const b = mathx.lerpF(ghostHeight(f, field, self.i01), ghostHeight(f, field, self.i11), self.tx);
        return base + mathx.lerpF(a, b, self.tz);
    }
};

fn covF(v: u8) f32 {
    return @as(f32, @floatFromInt(v)) / 255.0;
}

fn covByte(v: f32) u8 {
    return @intFromFloat(mathx.clampF(@round(v * 255.0), 0, 255));
}

pub const EDGE_F: f32 = covF(EDGE);

pub const Sample = struct {
    open: f32,
    floor: f32,
    roof: f32,

    pub fn hollow(self: Sample) bool {
        return self.open >= EDGE_F and self.roof > self.floor;
    }

    pub fn headroom(self: Sample) f32 {
        return self.roof - self.floor;
    }
};

pub const Fields = struct {
    cov: []const u8,
    floor: []const u8,
    roof: []const u8,
    half: f32,
    any: bool,
    /// The datum the floor and roof bytes are measured from. The map holds them the way it holds terrain height; `env` reads them in world Y.
    base: f32 = 0,
};

/// Coverage alone — a quarter of the reads `sampleAt` costs, and it is the only one a ray march or a sight line needs to reject a point.
pub fn openAt(f: Fields, px: f32, pz: f32) f32 {
    if (!f.any) return 0;
    return Lerp.of(f.half, px, pz).cov(f.cov);
}

pub fn sampleAt(f: Fields, px: f32, pz: f32) Sample {
    if (!f.any) return .{ .open = 0, .floor = 0, .roof = 0 };
    const l = Lerp.of(f.half, px, pz);
    return .{ .open = l.cov(f.cov), .floor = l.hgt(f, f.floor, f.base), .roof = l.hgt(f, f.roof, f.base) };
}

fn ghostHeight(f: Fields, field: []const u8, i: usize) f32 {
    if (f.cov[i] != 0) return wf.caveH(field[i]);
    const ix = i % N;
    const iz = i / N;
    var best = i;
    for (iz -| 1..@min(iz + 2, N)) |z| {
        for (ix -| 1..@min(ix + 2, N)) |x| {
            const j = z * N + x;
            if (f.cov[j] > f.cov[best]) best = j;
        }
    }
    return wf.caveH(field[best]);
}

/// THE FLOOR UNDER A BODY, decided by the CEILING: feet under a chamber's roof are in the chamber, and there is no walking up onto the hill through it. Feet at or over the roof are out on the land.
pub fn supportAt(f: Fields, land: f32, px: f32, pz: f32, fromY: f32) Support {
    // Rock is the common answer under a body as much as along a sight line (`spaceAt`), and coverage alone settles it:
    // `ghostHeight`'s ghost fill scans a 3x3 per corner where a point is unpainted, and this runs per body per frame.
    if (openAt(f, px, pz) < EDGE_F) return .{ .y = land, .surface = .land };
    const s = sampleAt(f, px, pz);
    if (!s.hollow() or fromY >= s.roof) return .{ .y = land, .surface = .land };
    return .{ .y = s.floor, .surface = .cave };
}

pub fn spaceAt(f: Fields, land: f32, px: f32, py: f32, pz: f32) Space {
    if (py > land) return .sky;
    // Rock is the common answer along a sight line, and coverage alone settles it.
    if (openAt(f, px, pz) < EDGE_F) return .rock;
    const s = sampleAt(f, px, pz);
    if (!s.hollow()) return .rock;
    if (py >= s.floor and py <= s.roof) return .cave;
    return .rock;
}

/// Metres of rock over a ceiling before the inside is fully sheltered — the mouth's own daylight reaches this far in.
pub const SHELTER_FADE: f32 = 2.0;
/// How far ABOVE a ceiling the shelter has faded out. Below the roof it is already full: keyed to the ceiling itself it fades out on the very surface it shades.
pub const SHELTER_LID: f32 = 0.75;
/// What the coverage is multiplied by before the clamp, so the shelter is FULL at the contour rather than at 1.
pub const SHELTER_CONTOUR: f32 = 2.0;

/// 1 under solid roof, 0 out under the sky. **THE FRAGMENT SHADER RUNS THIS SAME ARITHMETIC** (`shelterAt`
/// in `shaders.zig`, off a field `env.cutShelter` has already multiplied by the rock over the ceiling), and
/// the two cannot drift apart: this one decides which lights reach a fragment that one shades.
/// **ONE DELIBERATE DIFFERENCE:** `env.cutShelterAt` dilates the coverage over a 3×3 before baking, because the
/// texture is BILINEAR and a field going hard to 0 outside the contour steps at every mouth. That is filtering,
/// not the predicate — a body one cell outside a chamber is out under the sky and this must keep saying so.
pub fn shelterAt(f: Fields, land: f32, px: f32, py: f32, pz: f32) f32 {
    const s = sampleAt(f, px, pz);
    if (!s.hollow()) return 0;
    const thick = land - s.roof;
    if (thick <= 0) return 0;
    const cov = s.open * mathx.clampF(thick / SHELTER_FADE, 0, 1);
    const lid = mathx.clampF((s.roof - py) / SHELTER_LID + 1.0, 0, 1);
    return lid * mathx.clampF(cov * SHELTER_CONTOUR, 0, 1);
}

pub const Brush = struct {
    px: f32,
    pz: f32,
    r: f32,
    floor: f32,
    roof: f32,
    from: ?[2]f32 = null,
    preserve: bool = false,
    vault: bool = false,
    floorMax: f32 = 1e9,
    /// The floor's SLOPE, in metres per metre. A graded stroke writes the same height into a cell however many stamps cover it, so overlapping stamps cannot walk the floor down under themselves.
    dx: f32 = 0,
    dz: f32 = 0,
    /// How deep the grade is allowed to reach.
    floorMin: f32 = -1e9,

    fn floorAt(self: Brush, x: f32, z: f32) f32 {
        return mathx.clampF(self.floor + self.dx * (x - self.px) + self.dz * (z - self.pz), self.floorMin, self.floorMax);
    }
};

pub const Grids = struct {
    cov: []u8,
    floor: []u8,
    roof: []u8,
    half: f32,
};

/// A brush narrower than half a cell would fall between the lattice points and paint nothing.
fn brushR(half: f32, r: f32) f32 {
    return mathx.maxF(r, cellStep(half) * 0.5);
}

fn strokeSpan(g: Grids, b: Brush, out: *[4]usize) ?[4]usize {
    const step = cellStep(g.half);
    const r = brushR(g.half, b.r) + step;
    out.* = wf.EMPTY_SPAN;
    const sp = wf.sweptSpan(b.from orelse .{ b.px, b.pz }, .{ b.px, b.pz }, r, g.half, step, N) orelse return null;
    out.* = sp;
    return sp;
}

/// The brush's own width is the PASSAGE width: full coverage to one cell short of the rim, and only that last cell feathers.
fn falloff(step: f32, r: f32, d: f32) f32 {
    const feather = @min(step, r * 0.5);
    return mathx.smoothstep(r + feather * 0.5, r - feather * 0.5, d);
}

fn brushDistance(b: Brush, p: [2]f32) f32 {
    return mathx.segNearXZ(p, b.from orelse .{ b.px, b.pz }, .{ b.px, b.pz }).d;
}

/// A SCULPT'S FEATHER IS NOT A CARVE'S — a carve eases over its rim alone so a passage keeps its walls, a sculpt eases
/// over most of the disc (`Map.sculptTo`'s shape). The share is here rather than at the floor and the roof, which had it twice.
const SCULPT_FEATHER: f32 = 0.15;

fn sculptFall(r: f32, d: f32) f32 {
    return mathx.smoothstep(r, r * SCULPT_FEATHER, d);
}

pub fn carve(g: Grids, b: Brush, out: *[4]usize) bool {
    const sp = strokeSpan(g, b, out) orelse return false;
    const step = cellStep(g.half);
    const r = brushR(g.half, b.r);
    const head = b.roof - b.floor;
    var changed = false;
    var iz = sp[1];
    while (iz <= sp[3]) : (iz += 1) {
        var ix = sp[0];
        while (ix <= sp[2]) : (ix += 1) {
            const p = pointAt(g.half, ix, iz);
            const d = brushDistance(b, p);
            const fall = falloff(step, r, d);
            if (fall <= 0) continue;
            const i = iz * N + ix;
            const was = g.cov[i];
            const cov = covByte(@max(covF(was), fall));
            // A cell the stroke OPENS takes the stroke's heights outright; one already open blends, so a passage joining a chamber does not yank its floor.
            const fresh = was < EDGE;
            const want = b.floorAt(p[0], p[1]);
            const arch = if (b.vault) mathx.clampF(head - HEAD_MIN, 0, 0.8) * mathx.clampF(d * d / (r * r), 0, 1) else 0;
            const wantF = wf.caveByte(mathx.clampF(want, wf.CAVE_H_MIN, wf.CAVE_H_MAX));
            const wantR = wf.caveByte(mathx.clampF(want + head - arch, wf.CAVE_H_MIN, wf.CAVE_H_MAX));
            const nf = if (fresh) wantF else if (b.preserve) g.floor[i] else wf.caveByte(mathx.lerpF(wf.caveH(g.floor[i]), want, fall));
            const nr = if (fresh) wantR else if (b.preserve) @max(g.roof[i], wantR) else wf.caveByte(mathx.lerpF(wf.caveH(g.roof[i]), want + head - arch, fall));
            if (cov != was or nf != g.floor[i] or nr != g.roof[i]) changed = true;
            g.cov[i] = cov;
            g.floor[i] = nf;
            g.roof[i] = nr;
        }
    }
    return changed;
}

pub fn fill(g: Grids, b: Brush, out: *[4]usize) bool {
    const sp = strokeSpan(g, b, out) orelse return false;
    const step = cellStep(g.half);
    const r = brushR(g.half, b.r);
    var changed = false;
    var iz = sp[1];
    while (iz <= sp[3]) : (iz += 1) {
        var ix = sp[0];
        while (ix <= sp[2]) : (ix += 1) {
            const p = pointAt(g.half, ix, iz);
            const d = brushDistance(b, p);
            const fall = falloff(step, r, d);
            if (fall <= 0) continue;
            const i = iz * N + ix;
            const cov = covByte(@min(covF(g.cov[i]), 1.0 - fall));
            if (cov != g.cov[i]) {
                g.cov[i] = cov;
                changed = true;
            }
        }
    }
    return changed;
}

pub fn fieldsOf(m: *const wf.Map) Fields {
    return .{ .cov = &m.caveCov, .floor = &m.caveFloor, .roof = &m.caveRoof, .half = m.half, .any = m.anyCave() };
}

pub fn gridsOf(m: *wf.Map) Grids {
    return .{ .cov = &m.caveCov, .floor = &m.caveFloor, .roof = &m.caveRoof, .half = m.half };
}

/// A brush's own grids read back as a sample field, at the DATUM: a sculpt is mid-stroke, so `anyCave` is not asked.
pub fn fieldsOfGrids(g: Grids) Fields {
    return .{ .cov = g.cov, .floor = g.floor, .roof = g.roof, .half = g.half, .any = true };
}

pub const MAX_PTS: usize = 8;

/// A polygon inside one cave cell, in unit-cell coordinates, wound the way the terrain quad winds. `wall[i]` marks the edge from `pts[i]` as a CONTOUR CHORD — the one the rock face is built on.
pub const Shape = struct {
    pts: [MAX_PTS][2]f32 = undefined,
    wall: [MAX_PTS]bool = [_]bool{false} ** MAX_PTS,
    n: usize = 0,
};

/// The cell cut in two by the contour: the air, and the rock. THE SAME CROSSING POINTS SERVE BOTH, so the mouth of a cave and the hill it opens through share their vertices.
pub const Cell = struct {
    open: [2]Shape = .{ .{}, .{} },
    nopen: usize = 0,
    rock: [2]Shape = .{ .{}, .{} },
    nrock: usize = 0,
};

fn isOpen(v: f32) bool {
    return v >= EDGE_F;
}

fn crossT(a: f32, b: f32) f32 {
    const d = b - a;
    if (@abs(d) < 1e-6) return 0.5;
    return mathx.clampF((EDGE_F - a) / d, 0, 1);
}

fn corner(k: usize) [2]f32 {
    return .{ wf.CLIFF_RING[k][0], wf.CLIFF_RING[k][1] };
}

fn edgePoint(c: [4]f32, k: usize) [2]f32 {
    const k1 = (k + 1) % 4;
    const t = crossT(c[k], c[k1]);
    const a = corner(k);
    const b = corner(k1);
    return .{ a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t };
}

fn ringWalk(c: [4]f32, want: bool, out: *Shape) void {
    var isX: [MAX_PTS]bool = [_]bool{false} ** MAX_PTS;
    out.n = 0;
    for (0..4) |k| {
        const k1 = (k + 1) % 4;
        const ina = isOpen(c[k]) == want;
        const inb = isOpen(c[k1]) == want;
        if (ina) {
            out.pts[out.n] = corner(k);
            isX[out.n] = false;
            out.n += 1;
        }
        if (ina != inb) {
            out.pts[out.n] = edgePoint(c, k);
            isX[out.n] = true;
            out.n += 1;
        }
    }
    for (0..out.n) |i| out.wall[i] = isX[i] and isX[(i + 1) % out.n];
}

fn cornerWedge(c: [4]f32, k: usize, out: *Shape) void {
    out.n = 3;
    out.pts[0] = edgePoint(c, (k + 3) % 4);
    out.pts[1] = corner(k);
    out.pts[2] = edgePoint(c, k);
    out.wall = [_]bool{false} ** MAX_PTS;
    out.wall[2] = true;
}

fn wholeCell(out: *Shape) void {
    out.n = 4;
    for (0..4) |k| out.pts[k] = corner(k);
    out.wall = [_]bool{false} ** MAX_PTS;
}

/// `c` is coverage at the cell's four corners in `wf.CLIFF_RING` order; `centre` is the cell's own middle, which is what decides a SADDLE — two passages crossing at a corner either join or pass as two.
pub fn cellShapes(c: [4]f32, centre: f32) Cell {
    var out = Cell{};
    var n: usize = 0;
    for (c) |v| {
        if (isOpen(v)) n += 1;
    }
    if (n == 0) {
        wholeCell(&out.rock[0]);
        out.nrock = 1;
        return out;
    }
    if (n == 4) {
        wholeCell(&out.open[0]);
        out.nopen = 1;
        return out;
    }
    const saddle = n == 2 and isOpen(c[0]) == isOpen(c[2]) and isOpen(c[1]) == isOpen(c[3]);
    if (saddle) {
        const joined = isOpen(centre);
        const openK: usize = if (isOpen(c[0])) 0 else 1;
        if (joined) {
            ringWalk(c, true, &out.open[0]);
            out.nopen = 1;
            cornerWedge(c, openK + 1, &out.rock[0]);
            cornerWedge(c, openK + 3, &out.rock[1]);
            out.nrock = 2;
        } else {
            cornerWedge(c, openK, &out.open[0]);
            cornerWedge(c, openK + 2, &out.open[1]);
            out.nopen = 2;
            ringWalk(c, false, &out.rock[0]);
            out.nrock = 1;
        }
        return out;
    }
    ringWalk(c, true, &out.open[0]);
    out.nopen = 1;
    ringWalk(c, false, &out.rock[0]);
    out.nrock = 1;
    return out;
}

/// The coverage, floor and roof at one lattice point, for a mesher walking cells.
pub fn covAt(f: Fields, ix: usize, iz: usize) f32 {
    return covF(f.cov[iz * N + ix]);
}

pub fn floorAtPoint(f: Fields, ix: usize, iz: usize) f32 {
    return f.base + ghostHeight(f, f.floor, iz * N + ix);
}

pub fn roofAtPoint(f: Fields, ix: usize, iz: usize) f32 {
    return f.base + ghostHeight(f, f.roof, iz * N + ix);
}

pub fn bilerp(v: [4]f32, u: f32, w: f32) f32 {
    // `wf.CLIFF_RING` order: 00, 01, 11, 10.
    const a = mathx.lerpF(v[0], v[3], u);
    const b = mathx.lerpF(v[1], v[2], u);
    return mathx.lerpF(a, b, w);
}

/// Which way the air THINS. A wall underground is a coverage gradient, not a terrain one, so a body slides along the rock instead of along the hill over its head.
pub fn covGrad(f: Fields, px: f32, pz: f32) [2]f32 {
    if (!f.any) return .{ 0, 0 };
    const step = cellStep(f.half);
    const l = Lerp.of(f.half, px - step, pz).cov(f.cov);
    const r = Lerp.of(f.half, px + step, pz).cov(f.cov);
    const b = Lerp.of(f.half, px, pz - step).cov(f.cov);
    const n = Lerp.of(f.half, px, pz + step).cov(f.cov);
    return .{ (r - l) / (2 * step), (n - b) / (2 * step) };
}

/// Whether a body of this girth and stature has room. A passage a creature cannot fit through refuses it — no input is read to decide that, only its own size.
pub fn roomAt(f: Fields, px: f32, pz: f32, radius: f32, stature: f32) bool {
    const taps = [_][2]f32{ .{ 0, 0 }, .{ radius, 0 }, .{ -radius, 0 }, .{ 0, radius }, .{ 0, -radius } };
    for (taps) |o| {
        const s = sampleAt(f, px + o[0], pz + o[1]);
        if (!s.hollow()) return false;
        if (s.headroom() < stature) return false;
    }
    return true;
}

/// WHERE A POSTED BODY STANDS: the chamber floor for a row marked `under`, and the land for every row that is not. A cave that has been filled in since gives the land back rather than dropping the body through the world.
pub fn homeY(m: *const wf.Map, px: f32, pz: f32, under: bool) f32 {
    const land = m.heightAt(px, pz);
    if (!under) return land;
    const s = sampleAt(fieldsOf(m), px, pz);
    return if (s.hollow()) s.floor else land;
}

/// The floor that roofs `head` of room under ground at `land` with `ROOF_MIN` of rock over it, on the height lattice's own step so the carve lands where the panel says.
pub fn fitFloor(land: f32, head: f32) f32 {
    const want = @floor((land - ROOF_MIN - head) / wf.HEIGHT_STEP) * wf.HEIGHT_STEP;
    return mathx.clampF(want, wf.CAVE_H_MIN, wf.CAVE_H_MAX);
}

/// A ceiling this far under the land still counts as up through it. The MESHER does not read it: `env.CaveCell.hasOpening`
/// tests the roof against the hill at the shape's own corners, so a mouth is cut where the surfaces actually cross.
pub const MOUTH_SLACK: f32 = 0.02;

/// FOUR-CONNECTED, which is what a body walking a passage is: `--fix-caves`'s components and the editor's walk-in both step this way.
pub const STEP4 = [4][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };

/// A MOUTH: an excavated point whose ceiling has come up through the hill. No flag decides it and none can — the roof against the land is the whole test, and it is what the terrain is cut to.
pub fn mouthAt(f: Fields, land: f32, px: f32, pz: f32) bool {
    const s = sampleAt(f, px, pz);
    return s.hollow() and s.roof + MOUTH_SLACK >= land;
}

/// What a whole cave layer is: how much of it is excavated, how many points open to the sky, and how much of it a body could actually walk to from one of those.
pub const Reach = struct {
    open: usize = 0,
    mouths: usize = 0,
    walkable: usize = 0,

    pub fn sealed(self: Reach) bool {
        return self.open > 0 and self.mouths == 0;
    }

    /// Excavated points a body cannot reach from any mouth — a chamber that is there but cannot be got into.
    pub fn stranded(self: Reach) usize {
        return self.open - self.walkable;
    }
};

/// THE WALK IN, ANSWERED OFF THE GRID: flood the excavated points from EVERY mouth at once, four-connected and only
/// between floors within one step. It is the walk `--fix-caves` proves before it writes, asked of a map that is still
/// being carved — a chamber the flood never reaches is sealed however open it looks from above. `land` answers `groundAt`.
/// `mark` and `queue` are the caller's scratch, `CELLS` long; the editor keeps them at file scope, since a `Map` is megabytes and these are not.
pub fn reachOut(f: Fields, land: anytype, mark: []u8, queue: []u32) Reach {
    var r = Reach{};
    if (!f.any) return r;
    @memset(mark, 0);
    var head: usize = 0;
    var tail: usize = 0;
    for (0..N) |iz| {
        for (0..N) |ix| {
            const i = iz * N + ix;
            if (f.cov[i] < EDGE) continue;
            r.open += 1;
            const p = pointAt(f.half, ix, iz);
            if (!mouthAt(f, land.groundAt(p[0], p[1]), p[0], p[1])) continue;
            r.mouths += 1;
            mark[i] = 1;
            queue[tail] = @intCast(i);
            tail += 1;
        }
    }
    while (head < tail) {
        const i: usize = queue[head];
        head += 1;
        r.walkable += 1;
        const ix = i % N;
        const iz = i / N;
        const floor = wf.caveH(f.floor[i]);
        for (STEP4) |d| {
            const nx = @as(i32, @intCast(ix)) + d[0];
            const nz = @as(i32, @intCast(iz)) + d[1];
            if (nx < 0 or nz < 0 or nx >= N or nz >= N) continue;
            const j = @as(usize, @intCast(nz)) * N + @as(usize, @intCast(nx));
            if (f.cov[j] < EDGE or mark[j] != 0) continue;
            if (@abs(wf.caveH(f.floor[j]) - floor) > wf.STEP_UP) continue;
            mark[j] = 1;
            queue[tail] = @intCast(j);
            tail += 1;
        }
    }
    return r;
}

pub const PICK_STEP: f32 = 0.35;
pub const PICK_REACH: f32 = 400.0;

pub const Pick = struct { x: f32, y: f32, z: f32, surface: Surface };

/// WHERE A RAY LANDS WITH THE HILL TAKEN OFF EVERY CHAMBER — the editor's Underground level. The land where it still
/// stands; where the cell under it is excavated the hill is not there to be hit, so the ray falls through onto the
/// chamber floor. Rock met from INSIDE a chamber is a wall, answered at the floor's edge. `land` answers `groundAt`.
pub fn pickUnder(f: Fields, land: anytype, origin: [3]f32, dir: [3]f32, reach: f32) ?Pick {
    var prev = origin;
    var inside: ?f32 = null;
    var s: f32 = PICK_STEP;
    while (s < reach) : (s += PICK_STEP) {
        const p = [3]f32{ origin[0] + dir[0] * s, origin[1] + dir[1] * s, origin[2] + dir[2] * s };
        const g = land.groundAt(p[0], p[2]);
        if (p[1] > g) {
            inside = null;
            prev = p;
            continue;
        }
        if (!(f.any and openAt(f, p[0], p[2]) >= EDGE_F)) {
            if (inside) |floor| return .{ .x = prev[0], .y = floor, .z = prev[2], .surface = .cave };
            const q = refine(land, f, prev, p, .land);
            return .{ .x = q[0], .y = land.groundAt(q[0], q[2]), .z = q[2], .surface = .land };
        }
        const c = sampleAt(f, p[0], p[2]);
        if (!c.hollow()) {
            const q = refine(land, f, prev, p, .land);
            return .{ .x = q[0], .y = land.groundAt(q[0], q[2]), .z = q[2], .surface = .land };
        }
        if (p[1] <= c.floor) {
            const q = refine(land, f, prev, p, .cave);
            return .{ .x = q[0], .y = sampleAt(f, q[0], q[2]).floor, .z = q[2], .surface = .cave };
        }
        if (p[1] <= c.roof) inside = c.floor;
        prev = p;
    }
    return null;
}

/// Bisect the crossing between two samples: of the land, or of a chamber floor.
fn refine(land: anytype, f: Fields, a: [3]f32, b: [3]f32, want: Surface) [3]f32 {
    var lo = a;
    var hi = b;
    for (0..12) |_| {
        const mid = [3]f32{ (lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5, (lo[2] + hi[2]) * 0.5 };
        const under = switch (want) {
            .land => mid[1] <= land.groundAt(mid[0], mid[2]),
            .cave => mid[1] <= sampleAt(f, mid[0], mid[2]).floor,
        };
        if (under) hi = mid else lo = mid;
    }
    return hi;
}

/// THE GROUND LAYER'S FOUR SCULPTS ON THE CHAMBER FLOOR. Rock keeps its floor byte (it means nothing there, and a
/// smooth may not read it); a point is never lifted to within `HEAD_MIN` of its own roof; the feather is `Map.sculptTo`'s.
pub fn sculpt(g: Grids, px: f32, pz: f32, radius: f32, mode: wf.Sculpt, amount: f32, out: *[4]usize) bool {
    const sp = strokeSpan(g, .{ .px = px, .pz = pz, .r = radius, .floor = 0, .roof = 0 }, out) orelse return false;
    const r = brushR(g.half, radius);
    const target = flattenTarget(g, px, pz, r, sp);
    var before: [N]f32 = undefined;
    var above: [N]f32 = undefined;
    var changed = false;
    var iz = sp[1];
    while (iz <= sp[3]) : (iz += 1) {
        if (mode == .smooth) {
            if (iz == sp[1]) {
                if (iz > 0) {
                    for (0..N) |ix| above[ix] = wf.caveH(g.floor[(iz - 1) * N + ix]);
                }
            } else above = before;
            for (0..N) |ix| before[ix] = wf.caveH(g.floor[iz * N + ix]);
        }
        var ix = sp[0];
        while (ix <= sp[2]) : (ix += 1) {
            const i = iz * N + ix;
            if (g.cov[i] < EDGE) continue;
            const p = pointAt(g.half, ix, iz);
            const dx = p[0] - px;
            const dz = p[1] - pz;
            const d = @sqrt(dx * dx + dz * dz);
            if (d > r) continue;
            const fall = sculptFall(r, d);
            const cur = wf.caveH(g.floor[i]);
            const want = switch (mode) {
                .raise => cur + amount * fall,
                .lower => cur - amount * fall,
                .flatten => mathx.lerpF(cur, target, mathx.clampF(amount, 0, 1) * fall),
                .smooth => blk: {
                    var sum: f32 = 0;
                    var n: f32 = 0;
                    if (ix > 0 and g.cov[i - 1] >= EDGE) {
                        sum += before[ix - 1];
                        n += 1;
                    }
                    if (ix + 1 < N and g.cov[i + 1] >= EDGE) {
                        sum += before[ix + 1];
                        n += 1;
                    }
                    if (iz > 0 and g.cov[i - N] >= EDGE) {
                        sum += above[ix];
                        n += 1;
                    }
                    if (iz + 1 < N and g.cov[i + N] >= EDGE) {
                        sum += wf.caveH(g.floor[i + N]);
                        n += 1;
                    }
                    if (n == 0) break :blk cur;
                    break :blk mathx.lerpF(cur, sum / n, mathx.clampF(amount, 0, 1) * fall);
                },
            };
            const cap = mathx.maxF(cur, wf.caveH(g.roof[i]) - HEAD_MIN);
            const nb = wf.caveByte(mathx.clampF(mathx.minF(want, cap), wf.CAVE_H_MIN, wf.CAVE_H_MAX));
            if (nb == g.floor[i]) continue;
            g.floor[i] = nb;
            changed = true;
        }
    }
    return changed;
}

/// ROOF UP AND ROOF DOWN — the ceiling's own pair, because headroom was set at carve time and only a re-carve could
/// change it. The ceiling never comes down inside `HEAD_MIN` of its own floor and never goes up inside `ROOF_MIN` of the
/// hill, so one stroke cannot crush a passage shut and the other cannot punch a crater through the top. A roof the hill
/// has ALREADY thinned past that is left where it is rather than dragged down by the cap.
pub fn sculptRoof(g: Grids, m: *const wf.Map, px: f32, pz: f32, radius: f32, up: bool, amount: f32, out: *[4]usize) bool {
    const sp = strokeSpan(g, .{ .px = px, .pz = pz, .r = radius, .floor = 0, .roof = 0 }, out) orelse return false;
    const r = brushR(g.half, radius);
    var changed = false;
    var iz = sp[1];
    while (iz <= sp[3]) : (iz += 1) {
        var ix = sp[0];
        while (ix <= sp[2]) : (ix += 1) {
            const i = iz * N + ix;
            if (g.cov[i] < EDGE) continue;
            const p = pointAt(g.half, ix, iz);
            const dx = p[0] - px;
            const dz = p[1] - pz;
            const d = @sqrt(dx * dx + dz * dz);
            if (d > r) continue;
            const fall = sculptFall(r, d);
            const cur = wf.caveH(g.roof[i]);
            const hi = mathx.maxF(m.heightAt(p[0], p[1]) - ROOF_MIN, cur);
            const lo = mathx.minF(wf.caveH(g.floor[i]) + HEAD_MIN, hi);
            const want = if (up) cur + amount * fall else cur - amount * fall;
            const nb = wf.caveByte(mathx.clampF(mathx.clampF(want, lo, hi), wf.CAVE_H_MIN, wf.CAVE_H_MAX));
            if (nb == g.roof[i]) continue;
            g.roof[i] = nb;
            changed = true;
        }
    }
    return changed;
}

/// Flat levels toward the floor under the brush's centre; over rock, toward the mean floor of the open points it covers.
fn flattenTarget(g: Grids, px: f32, pz: f32, r: f32, sp: [4]usize) f32 {
    const l = Lerp.of(g.half, px, pz);
    if (l.cov(g.cov) >= EDGE_F) return l.hgt(fieldsOfGrids(g), g.floor, 0);
    var sum: f32 = 0;
    var n: f32 = 0;
    var iz = sp[1];
    while (iz <= sp[3]) : (iz += 1) {
        var ix = sp[0];
        while (ix <= sp[2]) : (ix += 1) {
            const i = iz * N + ix;
            if (g.cov[i] < EDGE) continue;
            const p = pointAt(g.half, ix, iz);
            const dx = p[0] - px;
            const dz = p[1] - pz;
            if (dx * dx + dz * dz > r * r) continue;
            sum += wf.caveH(g.floor[i]);
            n += 1;
        }
    }
    return if (n > 0) sum / n else 0;
}

test "terrain editor: fast cave strokes stay connected, keep their width and preserve a sculpted floor" {
    const m = try wf.testMap(std.testing.allocator, wf.TEST_HEAD);
    defer std.testing.allocator.destroy(m);
    var span: [4]usize = undefined;
    const brush = Brush{ .px = 25, .pz = 18, .from = .{ -25, -18 }, .r = 3, .floor = -5, .roof = -1.5, .vault = true, .preserve = true };
    try std.testing.expect(carve(gridsOf(m), brush, &span));
    const f = fieldsOf(m);
    for (0..101) |i| {
        const t = @as(f32, @floatFromInt(i)) / 100;
        const x = -25 + 50 * t;
        const z = -18 + 36 * t;
        const s = sampleAt(f, x, z);
        try std.testing.expect(s.hollow());
        try std.testing.expectApproxEqAbs(@as(f32, -5), s.floor, 0.001);
        try std.testing.expect(s.headroom() >= HEAD_MIN);
    }
    _ = sculpt(gridsOf(m), 0, 0, 2, .lower, 0.5, &span);
    const before = sampleAt(fieldsOf(m), 0, 0).floor;
    _ = carve(gridsOf(m), brush, &span);
    try std.testing.expectApproxEqAbs(before, sampleAt(fieldsOf(m), 0, 0).floor, 0.001);
    var erase = brush;
    erase.r = 4;
    try std.testing.expect(fill(gridsOf(m), erase, &span));
    try std.testing.expect(!sampleAt(fieldsOf(m), 0, 0).hollow());
}

test "terrain editor: unpainted cave corners do not pull a deep chamber back to the datum" {
    const m = try wf.testMap(std.testing.allocator, wf.TEST_HEAD);
    defer std.testing.allocator.destroy(m);
    var span: [4]usize = undefined;
    _ = carve(gridsOf(m), .{ .px = 0, .pz = 0, .r = 6, .floor = -10, .roof = -6 }, &span);
    const f = fieldsOf(m);
    for (0..360) |i| {
        const a = @as(f32, @floatFromInt(i)) * std.math.pi / 180;
        const s = sampleAt(f, mathx.cosf(a) * 5.8, mathx.sinf(a) * 5.8);
        if (!s.hollow()) continue;
        try std.testing.expectApproxEqAbs(@as(f32, -10), s.floor, 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, -6), s.roof, 0.001);
    }
}

pub const bench = struct {
    pub const FLOOR: f32 = -3.0;
    pub const HEAD: f32 = 3.0;
    pub const LOW_HEAD: f32 = 2.2;
    pub const HILL: f32 = 8.0;
    /// The mouth is out on the flat, east of the hill.
    pub const MOUTH = [2]f32{ 30, 16 };
    pub const CHAMBER = [2]f32{ 0, 0 };
    /// The bend, so a foe has to steer around a corner rather than down a tube.
    pub const BEND = [2]f32{ 13, 2 };
    pub const PASSAGE_R: f32 = 2.6;
    pub const CHAMBER_R: f32 = 11.0;

    fn stroke(m: *wf.Map, a: [2]f32, b: [2]f32, r: f32, floor: f32, head: f32) void {
        var span: [4]usize = wf.EMPTY_SPAN;
        const dx = b[0] - a[0];
        const dz = b[1] - a[1];
        const len = @sqrt(dx * dx + dz * dz);
        const step = cellStep(m.half) * 0.5;
        var s: f32 = 0;
        while (s <= len) : (s += step) {
            const u = if (len > 0) s / len else 0;
            _ = carve(gridsOf(m), .{
                .px = a[0] + dx * u,
                .pz = a[1] + dz * u,
                .r = r,
                .floor = floor,
                .roof = floor + head,
            }, &span);
        }
    }

    /// The editor's Entrance tool, walked in code: the floor grades down from the ground the stroke began on, and the hill opens by itself wherever it stands lower than the ceiling.
    /// The bench is the THIRD thing that cuts a mouth, so it takes the same grade and sink the editor's brush and `--fix-caves` do.
    fn entrance(m: *wf.Map, from: [2]f32, to: [2]f32, r: f32, head: f32) void {
        const grade = ENTRANCE_GRADE;
        var span: [4]usize = wf.EMPTY_SPAN;
        const dx = to[0] - from[0];
        const dz = to[1] - from[1];
        const len = @sqrt(dx * dx + dz * dz);
        if (len < 1e-4) return;
        const ux = dx / len;
        const uz = dz / len;
        const start = m.heightAt(from[0], from[1]) - ENTRANCE_SINK;
        const step = cellStep(m.half) * 0.5;
        var s: f32 = 0;
        while (s <= len) : (s += step) {
            const px = from[0] + ux * s;
            const pz = from[1] + uz * s;
            _ = carve(gridsOf(m), .{
                .px = px,
                .pz = pz,
                .r = r,
                .floor = start - grade * s,
                .roof = start - grade * s + head,
                .dx = -grade * ux,
                .dz = -grade * uz,
                .floorMin = FLOOR,
            }, &span);
        }
    }

    pub fn author(m: *wf.Map) void {
        m.blank("test caves");
        var span: [4]usize = wf.EMPTY_SPAN;
        // One hill, wide enough that the passage runs out from under it before the mouth.
        _ = m.sculpt(CHAMBER[0], CHAMBER[1], 30, .raise, HILL, &span);
        _ = m.sculpt(CHAMBER[0], CHAMBER[1], 18, .raise, 2.0, &span);

        stroke(m, CHAMBER, CHAMBER, CHAMBER_R, FLOOR, HEAD);
        stroke(m, CHAMBER, BEND, PASSAGE_R, FLOOR, HEAD);
        // The low stretch: the same passage with the ceiling brought down.
        stroke(m, BEND, .{ 20, 8 }, PASSAGE_R, FLOOR, LOW_HEAD);
        entrance(m, MOUTH, .{ 20, 8 }, PASSAGE_R, HEAD);

        // A LIGHT IN THE CHAMBER AND ONE AT THE MOUTH: the chamber's is the only thing down there that lights anything.
        _ = m.add(.{ .op = .at, .kind = .campfire_lit, .x = CHAMBER[0] + 3, .z = CHAMBER[1] + 2, .under = true }) catch {};
        _ = m.add(.{ .op = .at, .kind = .brazier, .x = 24, .z = 1, .under = true }) catch {};
        _ = m.add(.{ .op = .at, .kind = .campfire_lit, .x = MOUTH[0] + 4, .z = MOUTH[1] + 3 }) catch {};
        _ = m.add(.{ .op = .at, .kind = .boulder, .x = MOUTH[0] + 2, .z = MOUTH[1] - 5 }) catch {};

        m.start = .{ .x = MOUTH[0] + 6, .z = MOUTH[1], .yaw = 270 };
    }
};

test "the cave lattice halves the terrain's spacing, and the ring pays for it in megabytes" {
    const half = wf.DEFAULT_HALF;
    const land = wf.heightStepFor(half);
    const cave = cellStep(half);
    std.debug.print(
        "\ncave lattice: {d}^2 cells at {d:.3} m (terrain {d}^2 at {d:.3} m)\n",
        .{ N, cave, wf.HEIGHT_N, land },
    );
    std.debug.print(
        "cave grids: {d} KB per map, {d:.1} MB across the 24-slot undo ring\n",
        .{ 3 * CELLS / 1024, @as(f32, @floatFromInt(24 * 3 * CELLS)) / (1024.0 * 1024.0) },
    );
    std.debug.print("Op is {d} B, Map is now {d} KB\n", .{ @sizeOf(wf.Op), @sizeOf(wf.Map) / 1024 });
    try std.testing.expect(cave < land);
}

test "a cave carve puts one body on the hill and one in the chamber at the SAME xz" {
    const m = std.testing.allocator.create(wf.Map) catch unreachable;
    defer std.testing.allocator.destroy(m);
    m.* = .{};
    m.blank("bench");
    var span: [4]usize = undefined;
    _ = m.sculpt(0, 0, 40, .raise, 8, &span);
    _ = carve(gridsOf(m), .{ .px = 0, .pz = 0, .r = 6, .floor = -2, .roof = 1 }, &span);

    const f = fieldsOf(m);
    const land = m.heightAt(0, 0);
    try std.testing.expect(land > 6);

    const onHill = supportAt(f, land, 0, 0, land);
    try std.testing.expectEqual(Surface.land, onHill.surface);
    try std.testing.expectApproxEqAbs(land, onHill.y, 0.01);

    const inCave = supportAt(f, land, 0, 0, -2);
    try std.testing.expectEqual(Surface.cave, inCave.surface);
    try std.testing.expectApproxEqAbs(-2, inCave.y, wf.HEIGHT_STEP);

    try std.testing.expectEqual(Space.cave, spaceAt(f, land, 0, 0, 0));
    try std.testing.expectEqual(Space.rock, spaceAt(f, land, 0, 4, 0));
    try std.testing.expectEqual(Space.sky, spaceAt(f, land, 0, land + 2, 0));
    try std.testing.expectEqual(Space.rock, spaceAt(f, land, 30, 0, 30));
}

test "fill puts the rock back and the floor under it goes with it" {
    const m = std.testing.allocator.create(wf.Map) catch unreachable;
    defer std.testing.allocator.destroy(m);
    m.* = .{};
    m.blank("bench");
    var span: [4]usize = undefined;
    _ = m.sculpt(0, 0, 40, .raise, 8, &span);
    _ = carve(gridsOf(m), .{ .px = 0, .pz = 0, .r = 8, .floor = -2, .roof = 1 }, &span);
    try std.testing.expect(m.anyCave());

    const land = m.heightAt(0, 0);
    try std.testing.expectEqual(Surface.cave, supportAt(fieldsOf(m), land, 0, 0, -2).surface);

    _ = fill(gridsOf(m), .{ .px = 0, .pz = 0, .r = 12, .floor = 0, .roof = 0 }, &span);
    try std.testing.expect(!m.anyCave());
    try std.testing.expectEqual(Surface.land, supportAt(fieldsOf(m), land, 0, 0, -2).surface);
}

test "a carved map round-trips through the writer, and a map with no cave writes no record" {
    const m = std.testing.allocator.create(wf.Map) catch unreachable;
    defer std.testing.allocator.destroy(m);
    m.* = .{};
    m.blank("bench");

    const buf = try std.testing.allocator.alloc(u8, 4 << 20);
    defer std.testing.allocator.free(buf);
    var fbs = std.io.fixedBufferStream(buf);
    try wf.write(m, fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "cave:") == null);

    var span: [4]usize = undefined;
    _ = m.sculpt(0, 0, 40, .raise, 8, &span);
    _ = carve(gridsOf(m), .{ .px = 4, .pz = -3, .r = 7, .floor = -1.5, .roof = 1.25 }, &span);

    fbs.reset();
    try wf.write(m, fbs.writer());
    const text = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, text, "cave:") != null);

    const back = std.testing.allocator.create(wf.Map) catch unreachable;
    defer std.testing.allocator.destroy(back);
    var line: usize = 0;
    try wf.parse(text, back, &line);
    try std.testing.expectEqualSlices(u8, &m.caveCov, &back.caveCov);
    try std.testing.expectEqualSlices(u8, &m.caveFloor, &back.caveFloor);
    try std.testing.expectEqualSlices(u8, &m.caveRoof, &back.caveRoof);

    const land = m.heightAt(4, -3);
    try std.testing.expectEqual(
        supportAt(fieldsOf(m), land, 4, -3, -1.5).surface,
        supportAt(fieldsOf(back), land, 4, -3, -1.5).surface,
    );
}

test "the bench: a hill you can walk over, a chamber under it, and a mouth out on the flat" {
    const m = std.testing.allocator.create(wf.Map) catch unreachable;
    defer std.testing.allocator.destroy(m);
    m.* = .{};
    bench.author(m);
    const f = fieldsOf(m);

    const hill = m.heightAt(bench.CHAMBER[0], bench.CHAMBER[1]);
    const room = sampleAt(f, bench.CHAMBER[0], bench.CHAMBER[1]);
    std.debug.print(
        "\nbench: hill {d:.2} m, chamber floor {d:.2} m, roof {d:.2} m, {d:.2} m of rock over it\n",
        .{ hill, room.floor, room.roof, hill - room.roof },
    );
    try std.testing.expect(room.hollow());
    try std.testing.expect(hill - room.roof > 2.0);

    try std.testing.expectEqual(Surface.land, supportAt(f, hill, bench.CHAMBER[0], bench.CHAMBER[1], hill).surface);
    try std.testing.expectEqual(Surface.cave, supportAt(f, hill, bench.CHAMBER[0], bench.CHAMBER[1], room.floor).surface);

    const mouth = sampleAt(f, bench.MOUTH[0], bench.MOUTH[1]);
    const mouthLand = m.heightAt(bench.MOUTH[0], bench.MOUTH[1]);
    std.debug.print("bench: mouth roof {d:.2} m against ground {d:.2} m\n", .{ mouth.roof, mouthLand });
    try std.testing.expect(mouth.roof >= mouthLand);
    try std.testing.expect(room.roof < hill);
}

test "the bench walks: every metre from the mouth to the chamber has a floor, and none of it climbs a wall" {
    const m = std.testing.allocator.create(wf.Map) catch unreachable;
    defer std.testing.allocator.destroy(m);
    m.* = .{};
    bench.author(m);
    const f = fieldsOf(m);

    const route = [_][2]f32{
        bench.MOUTH,
        .{ 20, 8 },
        bench.BEND,
        bench.CHAMBER,
    };
    var y: f32 = m.heightAt(bench.MOUTH[0], bench.MOUTH[1]);
    var worst: f32 = 0;
    var worstAt: [2]f32 = .{ 0, 0 };
    var underground: usize = 0;
    var steps: usize = 0;
    for (route[0 .. route.len - 1], route[1..]) |a, b| {
        const dx = b[0] - a[0];
        const dz = b[1] - a[1];
        const len = @sqrt(dx * dx + dz * dz);
        var s: f32 = 0;
        while (s <= len) : (s += 0.5) {
            const u = s / len;
            const px = a[0] + dx * u;
            const pz = a[1] + dz * u;
            const sup = supportAt(f, m.heightAt(px, pz), px, pz, y);
            if (@abs(sup.y - y) > worst) {
                worst = @abs(sup.y - y);
                worstAt = .{ px, pz };
            }
            if (sup.surface == .cave) underground += 1;
            steps += 1;
            y = sup.y;
        }
    }
    std.debug.print("bench walk: {d} taps, {d} underground, worst step {d:.3} m at {d:.1},{d:.1} (limit {d:.2})\n", .{ steps, underground, worst, worstAt[0], worstAt[1], wf.STEP_UP });
    try std.testing.expect(underground > steps / 2);
    try std.testing.expect(worst <= wf.STEP_UP);
}

test "THE WALK IN IS ANSWERED OFF THE GRID: the bench reaches its own mouth, and a chamber with no mouth is SEALED" {
    const m = std.testing.allocator.create(wf.Map) catch unreachable;
    defer std.testing.allocator.destroy(m);
    m.* = .{};
    bench.author(m);
    const mark = std.testing.allocator.alloc(u8, CELLS) catch unreachable;
    defer std.testing.allocator.free(mark);
    const queue = std.testing.allocator.alloc(u32, CELLS) catch unreachable;
    defer std.testing.allocator.free(queue);

    const land = MapLand{ .m = m };
    const open = reachOut(fieldsOf(m), land, mark, queue);
    std.debug.print(
        "\nbench reach: {d} points excavated, {d} at a mouth, {d} walkable to the outside, {d} stranded\n",
        .{ open.open, open.mouths, open.walkable, open.stranded() },
    );
    try std.testing.expect(open.open > 0);
    try std.testing.expect(!open.sealed());
    try std.testing.expect(open.mouths > 0);
    // The bench is ONE chamber and ONE passage out of it, so every excavated point is on the walk.
    try std.testing.expectEqual(open.open, open.walkable);

    // A chamber alone under a hill with nothing cut out to it: excavated, and nothing walks into it.
    const s = std.testing.allocator.create(wf.Map) catch unreachable;
    defer std.testing.allocator.destroy(s);
    s.* = .{};
    s.blank("sealed");
    var span: [4]usize = undefined;
    for (0..12) |_| _ = s.sculpt(0, 0, 40, .raise, 1.0, &span);
    _ = carve(gridsOf(s), .{ .px = 0, .pz = 0, .r = 8, .floor = -4, .roof = -1 }, &span);
    const shut = reachOut(fieldsOf(s), MapLand{ .m = s }, mark, queue);
    std.debug.print("sealed: {d} points excavated, {d} at a mouth, {d} walkable\n", .{ shut.open, shut.mouths, shut.walkable });
    try std.testing.expect(shut.open > 0);
    try std.testing.expect(shut.sealed());
    try std.testing.expectEqual(@as(usize, 0), shut.walkable);
    try std.testing.expectEqual(shut.open, shut.stranded());
}

test "THE WALK-IN FLOOD IS A REBUILD'S WORK AND NOT A FRAME'S - timed over the bench" {
    const m = std.testing.allocator.create(wf.Map) catch unreachable;
    defer std.testing.allocator.destroy(m);
    m.* = .{};
    bench.author(m);
    const mark = std.testing.allocator.alloc(u8, CELLS) catch unreachable;
    defer std.testing.allocator.free(mark);
    const queue = std.testing.allocator.alloc(u32, CELLS) catch unreachable;
    defer std.testing.allocator.free(queue);
    const land = MapLand{ .m = m };
    const f = fieldsOf(m);

    const RUNS: usize = 20;
    var t0 = try std.time.Timer.start();
    var seen: usize = 0;
    for (0..RUNS) |_| seen += reachOut(f, land, mark, queue).walkable;
    const each = t0.read() / RUNS;
    std.debug.print("\nwalk-in flood: {d} us over {d} lattice points ({d} walkable)\n", .{ each / 1000, CELLS, seen / RUNS });
    // A rebuild already replays the whole op list and re-tiles the terrain; this may not be the expensive half of it.
    try std.testing.expect(each < 15 * std.time.ns_per_ms);
}

test "THE ROOF PAIR CANNOT SHUT A PASSAGE OR PUNCH THROUGH THE HILL - it stops at HEAD_MIN and at ROOF_MIN" {
    const m = std.testing.allocator.create(wf.Map) catch unreachable;
    defer std.testing.allocator.destroy(m);
    m.* = .{};
    bench.author(m);
    const at = bench.CHAMBER;
    const was = sampleAt(fieldsOf(m), at[0], at[1]);
    const hill = m.heightAt(at[0], at[1]);
    var span: [4]usize = undefined;

    // Twenty full-strength strokes UP: the ceiling climbs and then stops with ROOF_MIN of rock still over it.
    for (0..20) |_| _ = sculptRoof(gridsOf(m), m, at[0], at[1], 6, true, 1.0, &span);
    const up = sampleAt(fieldsOf(m), at[0], at[1]);
    std.debug.print(
        "\nroof up: {d:.2} -> {d:.2} m under a hill at {d:.2} m, {d:.2} m of rock left (floor {d:.2} m)\n",
        .{ was.roof, up.roof, hill, hill - up.roof, up.floor },
    );
    try std.testing.expect(up.roof > was.roof);
    try std.testing.expect(hill - up.roof >= ROOF_MIN - wf.HEIGHT_STEP);
    try std.testing.expect(up.roof < hill);

    // Twenty DOWN: it falls and then stops with HEAD_MIN of room still under it.
    for (0..20) |_| _ = sculptRoof(gridsOf(m), m, at[0], at[1], 6, false, 1.0, &span);
    const down = sampleAt(fieldsOf(m), at[0], at[1]);
    std.debug.print("roof down: {d:.2} -> {d:.2} m over a floor at {d:.2} m, {d:.2} m of room left\n", .{ up.roof, down.roof, down.floor, down.headroom() });
    try std.testing.expect(down.roof < up.roof);
    try std.testing.expect(down.hollow());
    try std.testing.expect(down.headroom() >= HEAD_MIN - wf.HEIGHT_STEP);
}

test "a body too tall for the low stretch is refused it, and one that fits is not" {
    const m = std.testing.allocator.create(wf.Map) catch unreachable;
    defer std.testing.allocator.destroy(m);
    m.* = .{};
    bench.author(m);
    const f = fieldsOf(m);
    const low = [2]f32{ 17, 5 };
    const s = sampleAt(f, low[0], low[1]);
    std.debug.print("bench low stretch: {d:.2} m of room\n", .{s.headroom()});
    try std.testing.expect(roomAt(f, low[0], low[1], 0.36, 1.8));
    try std.testing.expect(!roomAt(f, low[0], low[1], 0.36, 3.0));
}

test "the bench is written to worlds/test_caves.world" {
    const m = std.testing.allocator.create(wf.Map) catch unreachable;
    defer std.testing.allocator.destroy(m);
    m.* = .{};
    bench.author(m);
    try wf.save(BENCH_PATH, m);

    const text = try std.fs.cwd().readFileAlloc(std.testing.allocator, BENCH_PATH, 8 << 20);
    defer std.testing.allocator.free(text);
    const back = std.testing.allocator.create(wf.Map) catch unreachable;
    defer std.testing.allocator.destroy(back);
    var line: usize = 0;
    try wf.parse(text, back, &line);
    try std.testing.expectEqualSlices(u8, &m.caveCov, &back.caveCov);
    std.debug.print("bench file: {d} KB" ++ NL, .{text.len / 1024});
}

test "a carve on FLAT ground still opens: the chamber is there and the hill over it is not" {
    const m = std.testing.allocator.create(wf.Map) catch unreachable;
    defer std.testing.allocator.destroy(m);
    m.* = .{};
    m.blank("flat");
    try std.testing.expect(!m.anyHeight());

    var span: [4]usize = undefined;
    _ = carve(gridsOf(m), .{ .px = 0, .pz = 0, .r = 6, .floor = -4, .roof = -1 }, &span);
    const f = fieldsOf(m);
    const land = m.heightAt(0, 0);
    const s = sampleAt(f, 0, 0);
    std.debug.print("flat carve: ground {d:.2} m, chamber {d:.2} to {d:.2} m, {d:.2} m of rock over it" ++ NL, .{ land, s.floor, s.roof, land - s.roof });
    try std.testing.expectEqual(Surface.cave, supportAt(f, land, 0, 0, -4).surface);
    try std.testing.expectEqual(Surface.land, supportAt(f, land, 0, 0, land).surface);
    try std.testing.expect(land - s.roof > 0.9);
}

/// A map standing in for `env` under the pick: `groundAt` is the land, as the editor's `Env` answers it.
const MapLand = struct {
    m: *const wf.Map,
    fn groundAt(self: MapLand, x: f32, z: f32) f32 {
        return self.m.heightAt(x, z);
    }
};

fn hillWithChamber(m: *wf.Map) void {
    m.* = .{};
    m.blank("pick");
    var span: [4]usize = undefined;
    _ = m.sculpt(0, 0, 40, .raise, 8, &span);
    _ = carve(gridsOf(m), .{ .px = 0, .pz = 0, .r = 6, .floor = -2, .roof = 1 }, &span);
}

test "THE UNDERGROUND PICK FALLS THROUGH THE CUT-AWAY HILL ONTO THE FLOOR, and lands on the hill where it still stands" {
    const m = std.testing.allocator.create(wf.Map) catch unreachable;
    defer std.testing.allocator.destroy(m);
    hillWithChamber(m);
    const f = fieldsOf(m);
    const land = MapLand{ .m = m };
    const down = [3]f32{ 0, -1, 0 };

    const inRoom = pickUnder(f, land, .{ 0, 30, 0 }, down, PICK_REACH) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(Surface.cave, inRoom.surface);
    try std.testing.expectApproxEqAbs(@as(f32, -2), inRoom.y, wf.HEIGHT_STEP);

    const onHill = pickUnder(f, land, .{ 0, 30, -20 }, down, PICK_REACH) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(Surface.land, onHill.surface);
    try std.testing.expectApproxEqAbs(m.heightAt(0, -20), onHill.y, 0.05);
    try std.testing.expect(onHill.y > 1);

    // A glancing ray meets the un-carved flank of the hill before it can reach the chamber behind it.
    const from = [3]f32{ 30, 3, 0 };
    const to = [3]f32{ 0, -2, 0 };
    const dl = @sqrt(30.0 * 30.0 + 5.0 * 5.0);
    const flank = pickUnder(f, land, from, .{ (to[0] - from[0]) / dl, (to[1] - from[1]) / dl, 0 }, PICK_REACH) orelse return error.TestUnexpectedResult;
    std.debug.print("\nunderground pick: room floor {d:.2} m, hill {d:.2} m, glancing ray stopped on the flank at x {d:.1} (chamber edge 6)\n", .{ inRoom.y, onHill.y, flank.x });
    try std.testing.expectEqual(Surface.land, flank.surface);
    try std.testing.expect(flank.x > 6);

    // The same rays with no cave on the map are plain land hits.
    const bare = std.testing.allocator.create(wf.Map) catch unreachable;
    defer std.testing.allocator.destroy(bare);
    bare.* = .{};
    bare.blank("bare");
    var span: [4]usize = undefined;
    _ = bare.sculpt(0, 0, 40, .raise, 8, &span);
    const top = pickUnder(fieldsOf(bare), MapLand{ .m = bare }, .{ 0, 30, 0 }, down, PICK_REACH) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(Surface.land, top.surface);
    try std.testing.expectApproxEqAbs(bare.heightAt(0, 0), top.y, 0.05);
}

test "the floor sculpt moves open points only, never lifts one into its own roof, and lowers freely" {
    const m = std.testing.allocator.create(wf.Map) catch unreachable;
    defer std.testing.allocator.destroy(m);
    hillWithChamber(m);
    var span: [4]usize = undefined;
    const rockBefore = m.caveFloor[0];

    try std.testing.expect(sculpt(gridsOf(m), 0, 0, 3, .raise, 0.5, &span));
    var s = sampleAt(fieldsOf(m), 0, 0);
    try std.testing.expectApproxEqAbs(@as(f32, -1.5), s.floor, wf.HEIGHT_STEP);

    _ = sculpt(gridsOf(m), 0, 0, 3, .raise, 10, &span);
    s = sampleAt(fieldsOf(m), 0, 0);
    try std.testing.expectApproxEqAbs(s.roof - HEAD_MIN, s.floor, wf.HEIGHT_STEP);
    try std.testing.expect(s.hollow());

    _ = sculpt(gridsOf(m), 0, 0, 3, .lower, 4, &span);
    s = sampleAt(fieldsOf(m), 0, 0);
    try std.testing.expectApproxEqAbs(s.roof - HEAD_MIN - 4, s.floor, wf.HEIGHT_STEP);
    std.debug.print("floor sculpt: capped at {d:.2} m under a {d:.2} m roof, then lowered to {d:.2} m ({d:.2} m of room)\n", .{ s.roof - HEAD_MIN, s.roof, s.floor, s.headroom() });

    try std.testing.expectEqual(rockBefore, m.caveFloor[0]);
    try std.testing.expect(!sculpt(gridsOf(m), 100, 100, 3, .raise, 1, &span));
}

/// The largest riser between neighbouring open lattice points along the row through z = 0, between two x.
fn seamStep(m: *const wf.Map, x0: f32, x1: f32) f32 {
    const f = fieldsOf(m);
    const step = cellStep(m.half);
    const iz: usize = @intFromFloat(@round((0 + m.half) / step));
    const a: usize = @intFromFloat(@floor((x0 + m.half) / step));
    const b: usize = @intFromFloat(@ceil((x1 + m.half) / step));
    var worst: f32 = 0;
    var ix = a;
    while (ix < b) : (ix += 1) {
        if (covAt(f, ix, iz) < EDGE_F or covAt(f, ix + 1, iz) < EDGE_F) continue;
        worst = @max(worst, @abs(floorAtPoint(f, ix + 1, iz) - floorAtPoint(f, ix, iz)));
    }
    return worst;
}

test "smooth pulls a terrace seam together and flat levels toward the floor under the brush" {
    const m = std.testing.allocator.create(wf.Map) catch unreachable;
    defer std.testing.allocator.destroy(m);
    m.* = .{};
    m.blank("terraces");
    var span: [4]usize = undefined;
    _ = m.sculpt(0, 0, 40, .raise, 8, &span);
    _ = carve(gridsOf(m), .{ .px = -3, .pz = 0, .r = 6, .floor = -2, .roof = 1 }, &span);
    _ = carve(gridsOf(m), .{ .px = 3, .pz = 0, .r = 6, .floor = -4, .roof = 1 }, &span);
    const f = fieldsOf(m);
    try std.testing.expectApproxEqAbs(@as(f32, -2), sampleAt(f, -5, 0).floor, wf.HEIGHT_STEP);
    try std.testing.expectApproxEqAbs(@as(f32, -4), sampleAt(f, 0, 0).floor, wf.HEIGHT_STEP);

    const before = seamStep(m, -6, 2);
    for (0..8) |_| _ = sculpt(gridsOf(m), -2.5, 0, 4, .smooth, 0.9, &span);
    const after = seamStep(m, -6, 2);
    std.debug.print("smooth: the seam's tallest riser {d:.2} m -> {d:.2} m (a step is {d:.2} m; walkable under {d:.2})\n", .{ before, after, wf.HEIGHT_STEP, wf.STEP_UP });
    try std.testing.expect(after < before);
    try std.testing.expectApproxEqAbs(@as(f32, -2), sampleAt(f, -5, 0).floor, wf.HEIGHT_STEP);

    _ = sculpt(gridsOf(m), -3.5, 0, 5, .flatten, 1, &span);
    const levelled = sampleAt(f, 0, 0).floor;
    std.debug.print("flat toward {d:.2} m: the -4 m point at the disc's reach is now {d:.2} m\n", .{ sampleAt(f, -3.5, 0).floor, levelled });
    try std.testing.expect(levelled > -4 + wf.HEIGHT_STEP * 0.5);
}

test "fit lays the floor ROOF_MIN of rock under the hill, on the height step" {
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), fitFloor(8.0, 3.0), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 4.25), fitFloor(8.1, 2.8), 1e-5);
    try std.testing.expectEqual(wf.CAVE_H_MIN, fitFloor(-100, 3));
    const land: f32 = 8.1;
    const head: f32 = 2.8;
    try std.testing.expect(land - (fitFloor(land, head) + head) >= ROOF_MIN);
}

