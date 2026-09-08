const std = @import("std");
const mathx = @import("../core/mathx.zig");
const wf = @import("worldfmt.zig");
const NL = "\n";

/// Where the cave bench is written; `wf.save` panics under `is_test` on anything but `worlds/test_*.world`.
pub const BENCH_PATH = wf.DIR ++ "/test_caves.world";

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

    fn hgt(self: Lerp, field: []const u8, base: f32) f32 {
        const a = mathx.lerpF(wf.heightOf(field[self.i00]), wf.heightOf(field[self.i10]), self.tx);
        const b = mathx.lerpF(wf.heightOf(field[self.i01]), wf.heightOf(field[self.i11]), self.tx);
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
    return .{ .open = l.cov(f.cov), .floor = l.hgt(f.floor, f.base), .roof = l.hgt(f.roof, f.base) };
}

/// THE FLOOR UNDER A BODY, decided by the CEILING: feet under a chamber's roof are in the chamber, and there is no walking up onto the hill through it. Feet at or over the roof are out on the land.
pub fn supportAt(f: Fields, land: f32, px: f32, pz: f32, fromY: f32) Support {
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
    /// The floor's SLOPE, in metres per metre. A graded stroke writes the same height into a cell however many stamps cover it, so overlapping stamps cannot walk the floor down under themselves.
    dx: f32 = 0,
    dz: f32 = 0,
    /// How deep the grade is allowed to reach.
    floorMin: f32 = -1e9,

    fn floorAt(self: Brush, x: f32, z: f32) f32 {
        return mathx.maxF(self.floor + self.dx * (x - self.px) + self.dz * (z - self.pz), self.floorMin);
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
    const r = brushR(g.half, b.r);
    out.* = wf.EMPTY_SPAN;
    const xs = wf.pointSpan(b.px, r, g.half, step, N) orelse return null;
    const zs = wf.pointSpan(b.pz, r, g.half, step, N) orelse return null;
    out.* = .{ xs[0], zs[0], xs[1], zs[1] };
    return .{ xs[0], zs[0], xs[1], zs[1] };
}

/// The brush's own width is the PASSAGE width: full coverage to one cell short of the rim, and only that last cell feathers.
fn falloff(step: f32, r: f32, d: f32) f32 {
    const feather = @min(step, r * 0.5);
    return mathx.smoothstep(r, r - feather, d);
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
            const dx = p[0] - b.px;
            const dz = p[1] - b.pz;
            const d = @sqrt(dx * dx + dz * dz);
            if (d > r) continue;
            const fall = falloff(step, r, d);
            if (fall <= 0) continue;
            const i = iz * N + ix;
            const was = g.cov[i];
            const cov = covByte(@max(covF(was), fall));
            // A cell the stroke OPENS takes the stroke's heights outright; one already open blends, so a passage joining a chamber does not yank its floor.
            const fresh = was < EDGE;
            const want = b.floorAt(p[0], p[1]);
            const wantF = wf.heightByte(mathx.clampF(want, wf.HEIGHT_MIN, wf.HEIGHT_MAX));
            const wantR = wf.heightByte(mathx.clampF(want + head, wf.HEIGHT_MIN, wf.HEIGHT_MAX));
            const nf = if (fresh) wantF else wf.heightByte(mathx.lerpF(wf.heightOf(g.floor[i]), want, fall));
            const nr = if (fresh) wantR else wf.heightByte(mathx.lerpF(wf.heightOf(g.roof[i]), want + head, fall));
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
            const dx = p[0] - b.px;
            const dz = p[1] - b.pz;
            const d = @sqrt(dx * dx + dz * dz);
            if (d > r) continue;
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
    return f.base + wf.heightOf(f.floor[iz * N + ix]);
}

pub fn roofAtPoint(f: Fields, ix: usize, iz: usize) f32 {
    return f.base + wf.heightOf(f.roof[iz * N + ix]);
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


/// THE BENCH: a hill with a chamber under it, a bent passage out to a mouth on the flat, and a low stretch on the way. Authored here so the editor, the tests and the shot harness all stand on the same map.
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
    fn entrance(m: *wf.Map, from: [2]f32, to: [2]f32, r: f32, head: f32, grade: f32, sink: f32) void {
        var span: [4]usize = wf.EMPTY_SPAN;
        const dx = to[0] - from[0];
        const dz = to[1] - from[1];
        const len = @sqrt(dx * dx + dz * dz);
        if (len < 1e-4) return;
        const ux = dx / len;
        const uz = dz / len;
        const start = m.heightAt(from[0], from[1]) - sink;
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
        entrance(m, MOUTH, .{ 20, 8 }, PASSAGE_R, HEAD, 0.5, 0.25);

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
    const land = 2 * half / @as(f32, @floatFromInt(wf.HEIGHT_N - 1));
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
