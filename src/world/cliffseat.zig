//! SEATING A PREMADE CLIFF AGAINST A CUT. The terrain owns the drop and the walkable top; a `cliff*` prop is only
//! the cliffside stood in front of the wall. Local −z is the piece's FRONT (out over the low ground), +z runs into
//! the hill (`proprock.cliffBuildOpt`: talus at z −2.1..−0.7, strata at `back − 1.20`).
const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const props = @import("../props/props.zig");
const proprock = @import("../props/proprock.zig");
const wf = @import("worldfmt.zig");
const envmod = @import("env.zig");

const v3 = mathx.v3;
const Env = envmod.Env;
const Prop = envmod.Prop;

/// 0.25 m: the finest gap the height encoding can even write, so it is the honest bar for "seated". Anything tighter would red a lip the file cannot hold.
pub const TOL: f32 = wf.HEIGHT_STEP;

/// Local metres between the stations a piece is read at, along its run and up its face.
const STATION: f32 = 0.5;
/// How fine the skyline is scanned for a column's top.
const SKY_STEP: f32 = 0.1;
/// Either side of a found crossing: a cut steps the whole drop inside this, a ramp does not.
const STEP_PROBE: f32 = 0.02;
const BISECT: u32 = 26;

/// The land as the seat reads it — the editor's live map or the world's copy — both through `wf.sampleHeight`, in the MAP's height (a prop's `pos.y`).
pub const Ground = union(enum) {
    map: *const wf.Map,
    env: *const Env,

    pub fn at(self: Ground, x: f32, z: f32) f32 {
        return switch (self) {
            .map => |m| m.heightAt(x, z),
            .env => |e| e.groundAt(x, z) - envmod.groundY(),
        };
    }

    pub fn cell(self: Ground) f32 {
        return switch (self) {
            .map => |m| m.heightStep(),
            .env => |e| 2 * e.heightHalf / @as(f32, @floatFromInt(wf.HEIGHT_N - 1)),
        };
    }
};

/// One row's seating geometry in its own unscaled frame, read once off `proprock.cliffShape`.
pub const Piece = struct {
    /// The seat plane: the deepest front over the whole face (`cliffSeatZ`), so a cut here leaves no lobe buried.
    seat: f32,
    /// The lowest point of the skyline across the run: a lip here is covered along the whole run and the taller summits crest over it.
    top: f32,
    /// The run is summit to summit; past it the stone tapers and the next piece takes over.
    run0: f32,
    run1: f32,
    x0: f32,
    x1: f32,
    front: f32,
    back: f32,
    height: f32,
    /// How far the rock stands in front of the seat plane where it is covered, and how much of the run's face is not covered at all.
    proudMean: f32,
    proudMax: f32,
    bare: f32,
};

var pieceStore: [proprock.CLIFF_PROPS.len]Piece = undefined;
var pieceDone: [proprock.CLIFF_PROPS.len]bool = [_]bool{false} ** proprock.CLIFF_PROPS.len;

pub fn pieceOf(row: usize) *const Piece {
    if (!pieceDone[row]) {
        pieceStore[row] = measure(proprock.cliffShape(row));
        pieceDone[row] = true;
    }
    return &pieceStore[row];
}

fn measure(sh: *const proprock.CliffShape) Piece {
    const bs = sh.bodies();
    var p = Piece{
        .seat = -1e9,
        .top = 1e9,
        .run0 = 1e9,
        .run1 = -1e9,
        .x0 = sh.lo.x,
        .x1 = sh.hi.x,
        .front = sh.lo.z,
        .back = sh.hi.z,
        .height = sh.hi.y,
        .proudMean = 0,
        .proudMax = 0,
        .bare = 0,
    };
    for (sh.masses.sky[0..sh.masses.nsky]) |b| {
        p.run0 = @min(p.run0, b.x);
        p.run1 = @max(p.run1, b.x);
    }
    var x = p.x0 + STATION * 0.5;
    while (x < p.x1) : (x += STATION) {
        var y = STATION * 0.5;
        while (y < p.height) : (y += STATION) {
            if (proprock.cliffSeatZ(bs, x, y, STATION * 0.5, STATION * 0.5)) |z| p.seat = @max(p.seat, z);
        }
    }
    x = p.run0;
    while (x <= p.run1 + 1e-4) : (x += STATION) {
        var y = p.height;
        while (y > 0) : (y -= SKY_STEP) {
            if (proprock.cliffFaceZ(bs, x, y) != null) break;
        }
        p.top = @min(p.top, y);
    }
    var covered: u32 = 0;
    var total: u32 = 0;
    var sum: f32 = 0;
    x = p.run0;
    while (x <= p.run1 + 1e-4) : (x += STATION) {
        var y = STATION * 0.5;
        while (y < p.top) : (y += STATION) {
            total += 1;
            const fz = proprock.cliffFaceZ(bs, x, y) orelse continue;
            covered += 1;
            const proud = p.seat - fz;
            sum += proud;
            p.proudMax = @max(p.proudMax, proud);
        }
    }
    if (covered > 0) p.proudMean = sum / @as(f32, @floatFromInt(covered));
    if (total > 0) p.bare = 1.0 - @as(f32, @floatFromInt(covered)) / @as(f32, @floatFromInt(total));
    return p;
}

/// A placed piece's frame: world from local (metres, scaled) and back.
const Frame = struct {
    pr: *const Prop,
    c: f32,
    sn: f32,

    fn of(pr: *const Prop) Frame {
        const th = mathx.radians(pr.yaw);
        return .{ .pr = pr, .c = mathx.cosf(th), .sn = mathx.sinf(th) };
    }
    /// `lx`,`lz` in UNSCALED local metres.
    fn world(self: Frame, lx: f32, lz: f32) [2]f32 {
        const s = self.pr.scale;
        return .{ self.pr.pos.x + s * (lx * self.c + lz * self.sn), self.pr.pos.z + s * (-lx * self.sn + lz * self.c) };
    }
    /// Local in WORLD metres along the piece's axes (scale applied), so a lattice point is tested against scaled extents.
    fn local(self: Frame, wx: f32, wz: f32) [2]f32 {
        const dx = wx - self.pr.pos.x;
        const dz = wz - self.pr.pos.z;
        return .{ self.c * dx - self.sn * dz, self.sn * dx + self.c * dz };
    }
    /// The outward normal: local −z in the world.
    fn normal(self: Frame) [2]f32 {
        return .{ -self.sn, -self.c };
    }
};

pub const Cut = struct {
    /// Signed metres along the outward normal from the probe point to the crossing.
    t: f32,
    hi: f32,
    lo: f32,
};

/// Where the land steps across a line through (`px`,`pz`) along the normal, within `reach` either way. Bisects `Ground` between a high-side and a low-side probe, then refuses a crossing the land does not STEP at: a ramp is not a cut.
pub fn cutAcross(g: Ground, px: f32, pz: f32, nx: f32, nz: f32, reach: f32) ?Cut {
    const minDrop = wf.cliffMinDrop(g.cell());
    const hHi = g.at(px - nx * reach, pz - nz * reach);
    const hLo = g.at(px + nx * reach, pz + nz * reach);
    if (hHi - hLo < minDrop) return null;
    const mid = (hHi + hLo) * 0.5;
    var a: f32 = -reach;
    var b: f32 = reach;
    var i: u32 = 0;
    while (i < BISECT) : (i += 1) {
        const t = (a + b) * 0.5;
        if (g.at(px + nx * t, pz + nz * t) >= mid) a = t else b = t;
    }
    const t = (a + b) * 0.5;
    const stepHi = g.at(px + nx * (t - STEP_PROBE), pz + nz * (t - STEP_PROBE));
    const stepLo = g.at(px + nx * (t + STEP_PROBE), pz + nz * (t + STEP_PROBE));
    if (stepHi - stepLo < minDrop) return null;
    return .{ .t = t, .hi = stepHi, .lo = stepLo };
}

/// How a placed piece sits against the land, in metres, read at stations across its run.
pub const Seat = struct {
    row: usize,
    stations: u32 = 0,
    /// Stations where no cut runs behind the piece: nothing to hang it on.
    missing: u32 = 0,
    /// The cut against the seat plane, worst station, signed: positive is a wall standing BEHIND the rock (a slot), negative a piece buried in the hill.
    setback: f32 = 0,
    meanSetback: f32 = 0,
    /// The lip above the rock's top: positive is bare wall showing over the piece.
    over: f32 = 0,
    /// The piece's foot above the low ground: positive is daylight under it.
    under: f32 = 0,
    drop: f32 = 0,

    pub fn cut(self: Seat) bool {
        return self.stations > 0 and self.missing == 0;
    }
    pub fn worst(self: Seat) f32 {
        return @max(@abs(self.setback), @max(self.over, self.under));
    }
    pub fn ok(self: Seat) bool {
        return self.cut() and self.worst() <= TOL;
    }
};

pub fn seatOf(g: Ground, pr: *const Prop) ?Seat {
    const row = props.cliffRow(pr.kind) orelse return null;
    const pc = pieceOf(row);
    const fr = Frame.of(pr);
    const n = fr.normal();
    const s = pr.scale;
    const reach = (pc.back - pc.front) * s;
    const topY = pr.pos.y + pc.top * s;
    var out = Seat{ .row = row, .drop = 1e9 };
    var sum: f32 = 0;
    var x = pc.run0;
    while (x <= pc.run1 + 1e-4) : (x += STATION) {
        out.stations += 1;
        const seatAt = fr.world(x, pc.seat);
        const toe = fr.world(x, pc.front);
        const under = pr.pos.y - g.at(toe[0], toe[1]);
        out.under = @max(out.under, under);
        const ct = cutAcross(g, seatAt[0], seatAt[1], n[0], n[1], reach) orelse {
            out.missing += 1;
            continue;
        };
        const setback = -ct.t;
        sum += setback;
        if (@abs(setback) > @abs(out.setback)) out.setback = setback;
        out.over = @max(out.over, ct.hi - topY);
        out.drop = @min(out.drop, ct.hi - ct.lo);
    }
    const found = out.stations - out.missing;
    if (found > 0) out.meanSetback = sum / @as(f32, @floatFromInt(found));
    if (out.drop > 1e8) out.drop = 0;
    return out;
}

/// The cut through a placed piece as its colliders need it: local z (scaled metres from the origin, +z into the hill) and the lip's height. Null where no cut runs behind the piece's middle.
pub const CutZ = struct { z: f32, lip: f32 };

pub fn cutOf(g: Ground, pr: *const Prop) ?CutZ {
    const row = props.cliffRow(pr.kind) orelse return null;
    const pc = pieceOf(row);
    const fr = Frame.of(pr);
    const n = fr.normal();
    const mid = (pc.run0 + pc.run1) * 0.5;
    const at = fr.world(mid, pc.seat);
    const ct = cutAcross(g, at[0], at[1], n[0], n[1], (pc.back - pc.front) * pr.scale) orelse return null;
    return .{ .z = pc.seat * pr.scale - ct.t, .lip = ct.hi };
}

pub const Conform = struct {
    changed: bool = false,
    /// Metres the piece was walked along its normal so the seat plane lands on the cut the lattice could actually draw.
    slid: f32 = 0,
    foot: f32 = 0,
    lip: f32 = 0,
};

/// THE LAND BENDS TO THE PIECE. Inside the piece's own rectangle every lattice point in front of the seat plane goes to the foot and every point behind it to the top, and each cell the plane crosses is painted `CLIFF_FACE` — one line, two heights, no feather. The lattice can only draw the cut at cell-edge midpoints, so the piece is then walked along its normal by the mean residual and left where the seat is exact.
pub fn conform(m: *wf.Map, pr: *const Prop, span: *[4]usize) Conform {
    var out = Conform{};
    span.* = wf.EMPTY_SPAN;
    const row = props.cliffRow(pr.kind) orelse return out;
    const pc = pieceOf(row);
    const fr = Frame.of(pr);
    const s = pr.scale;
    const cell = m.heightStep();
    const cutZ = pc.seat * s;
    out.foot = wf.heightOf(wf.heightByte(mathx.clampF(pr.pos.y, wf.HEIGHT_MIN, wf.HEIGHT_MAX)));
    out.lip = wf.heightOf(wf.heightByte(mathx.clampF(pr.pos.y + pc.top * s, wf.HEIGHT_MIN, wf.HEIGHT_MAX)));
    const footB = wf.heightByte(out.foot);
    const lipB = wf.heightByte(out.lip);

    const lx0 = pc.x0 * s - cell;
    const lx1 = pc.x1 * s + cell;
    const lz0 = pc.front * s - cell;
    const lz1 = cutZ + 2 * cell;
    var wx0: f32 = 1e9;
    var wx1: f32 = -1e9;
    var wz0: f32 = 1e9;
    var wz1: f32 = -1e9;
    for ([_][2]f32{ .{ lx0, lz0 }, .{ lx1, lz0 }, .{ lx0, lz1 }, .{ lx1, lz1 } }) |c| {
        const w = fr.world(c[0] / s, c[1] / s);
        wx0 = @min(wx0, w[0]);
        wx1 = @max(wx1, w[0]);
        wz0 = @min(wz0, w[1]);
        wz1 = @max(wz1, w[1]);
    }
    const xs = wf.pointSpan((wx0 + wx1) * 0.5, (wx1 - wx0) * 0.5, m.half, cell, wf.HEIGHT_N) orelse return out;
    const zs = wf.pointSpan((wz0 + wz1) * 0.5, (wz1 - wz0) * 0.5, m.half, cell, wf.HEIGHT_N) orelse return out;
    span.* = .{ xs[0], zs[0], xs[1], zs[1] };

    const Side = enum { out, low, high };
    var iz = zs[0];
    while (iz <= zs[1]) : (iz += 1) {
        var ix = xs[0];
        while (ix <= xs[1]) : (ix += 1) {
            const side = sideOf(fr, m, ix, iz, lx0, lx1, lz0, lz1, cutZ, Side);
            if (side == .out) continue;
            const i = iz * wf.HEIGHT_N + ix;
            const want = if (side == .high) lipB else footB;
            if (m.height[i] != want) {
                m.height[i] = want;
                out.changed = true;
            }
        }
    }
    iz = zs[0];
    while (iz <= zs[1] and iz + 1 < wf.HEIGHT_N) : (iz += 1) {
        var ix = xs[0];
        while (ix <= xs[1] and ix + 1 < wf.HEIGHT_N) : (ix += 1) {
            var lows: u8 = 0;
            var highs: u8 = 0;
            for (wf.RING_STEP) |st| {
                switch (sideOf(fr, m, ix + st[0], iz + st[1], lx0, lx1, lz0, lz1, cutZ, Side)) {
                    .out => {},
                    .low => lows += 1,
                    .high => highs += 1,
                }
            }
            if (lows + highs < 4 or lows == 0 or highs == 0) continue;
            const i = iz * wf.HEIGHT_N + ix;
            if (m.cliff[i] != wf.CLIFF_FACE) {
                m.cliff[i] = wf.CLIFF_FACE;
                out.changed = true;
            }
        }
    }

    if (pr.op < m.nops and m.ops[pr.op].op == .at) {
        if (seatOf(.{ .map = m }, pr)) |st| {
            if (st.cut()) {
                const n = fr.normal();
                const ox = pr.pos.x - n[0] * st.meanSetback;
                const oz = pr.pos.z - n[1] * st.meanSetback;
                if (@abs(m.heightAt(ox, oz) - out.foot) <= TOL) {
                    m.ops[pr.op].x = ox;
                    m.ops[pr.op].z = oz;
                    out.slid = st.meanSetback;
                    out.changed = out.changed or @abs(out.slid) > 1e-6;
                }
            }
        }
    }
    return out;
}

/// Does this placed piece's stone stand over the point — the cut behind it is already dressed, so `env.faceStamp` puts no rock there.
pub fn covers(pr: *const Prop, x: f32, z: f32) bool {
    const row = props.cliffRow(pr.kind) orelse return false;
    const pc = pieceOf(row);
    const l = Frame.of(pr).local(x, z);
    const s = pr.scale;
    return l[0] >= pc.x0 * s and l[0] <= pc.x1 * s and l[1] >= pc.front * s and l[1] <= pc.back * s;
}

/// THE DROP A ROW'S PIECE COVERS AT THIS SCALE, floored to `HEIGHT_STEP`: a lip here is at or under the rock's top, so `over` is zero by construction and the encoding can write it.
pub fn rise(row: usize, scale: f32) f32 {
    return @floor(pieceOf(row).top * scale / wf.HEIGHT_STEP) * wf.HEIGHT_STEP;
}

pub const Rect = struct { x0: f32, z0: f32, x1: f32, z1: f32 };

/// Where the cuts actually land: the lattice draws a rim halfway between the last point outside and the first point inside, so a piece is seated on THESE lines, not on the dragged ones.
pub const Rim = struct { x0: f32, z0: f32, x1: f32, z1: f32, level: f32 };

/// ONE FLAT LEVEL INSIDE A RECTANGLE AND A CUT ROUND IT. Every lattice point inside goes to `target` and every cell the edge crosses is painted `CLIFF_FACE`; the plateau brush hands a height above the ground it started on, the indent brush one below. Straight rims on the lattice's own lines, no feather.
pub fn terrace(m: *wf.Map, r: Rect, target: f32, span: *[4]usize) ?Rim {
    span.* = wf.EMPTY_SPAN;
    const cell = m.heightStep();
    const xs = wf.pointSpan((r.x0 + r.x1) * 0.5, (r.x1 - r.x0) * 0.5, m.half, cell, wf.HEIGHT_N) orelse return null;
    const zs = wf.pointSpan((r.z0 + r.z1) * 0.5, (r.z1 - r.z0) * 0.5, m.half, cell, wf.HEIGHT_N) orelse return null;
    if (xs[0] == 0 or zs[0] == 0 or xs[1] + 1 >= wf.HEIGHT_N or zs[1] + 1 >= wf.HEIGHT_N) return null;
    const want = wf.heightByte(mathx.clampF(target, wf.HEIGHT_MIN, wf.HEIGHT_MAX));
    var iz = zs[0];
    while (iz <= zs[1]) : (iz += 1) {
        var ix = xs[0];
        while (ix <= xs[1]) : (ix += 1) m.height[iz * wf.HEIGHT_N + ix] = want;
    }
    iz = zs[0] - 1;
    while (iz <= zs[1]) : (iz += 1) {
        var ix = xs[0] - 1;
        while (ix <= xs[1]) : (ix += 1) {
            const inside = ix >= xs[0] and ix < xs[1] and iz >= zs[0] and iz < zs[1];
            if (!inside) m.cliff[iz * wf.HEIGHT_N + ix] = wf.CLIFF_FACE;
        }
    }
    span.* = .{ xs[0] - 1, zs[0] - 1, xs[1] + 1, zs[1] + 1 };
    const lo = m.heightPoint(xs[0], zs[0]);
    const hi = m.heightPoint(xs[1], zs[1]);
    return .{
        .x0 = lo[0] - cell * 0.5,
        .z0 = lo[1] - cell * 0.5,
        .x1 = hi[0] + cell * 0.5,
        .z1 = hi[1] + cell * 0.5,
        .level = wf.heightOf(want),
    };
}

fn sideOf(fr: Frame, m: *const wf.Map, ix: usize, iz: usize, lx0: f32, lx1: f32, lz0: f32, lz1: f32, cutZ: f32, comptime Side: type) Side {
    const p = m.heightPoint(ix, iz);
    const l = fr.local(p[0], p[1]);
    if (l[0] < lx0 or l[0] > lx1 or l[1] < lz0 or l[1] > lz1) return .out;
    return if (l[1] >= cutZ) .high else .low;
}

// ---------------------------------------------------------------------------------------------------------------------

const BENCH = wf.DIR ++ "/test_cliffseat" ++ wf.EXT;
const BENCH_HALF: f32 = 107.4;
const BENCH_DROP: f32 = 6.0;
const BENCH_WALL_X: f32 = 12.0;

fn benchMap() !*wf.Map {
    const m = try wf.testMap(std.testing.allocator, wf.TEST_HEAD ++
        \\name: Cliff Seat Bench
        \\half: 107.4
        \\start: 0.00 4.00 180.0
        \\at: cliff 10.5 0 90 0.45
        \\at: cliff3 10.5 24 90 0.5
        \\
    );
    const cell = m.heightStep();
    for (0..wf.HEIGHT_N) |iz| {
        for (0..wf.HEIGHT_N) |ix| {
            const p = m.heightPoint(ix, iz);
            if (p[0] >= BENCH_WALL_X and @abs(p[1]) < 40) m.height[iz * wf.HEIGHT_N + ix] = wf.heightByte(BENCH_DROP);
        }
    }
    for (0..wf.HEIGHT_N - 1) |iz| {
        for (0..wf.HEIGHT_N - 1) |ix| {
            const p = m.heightPoint(ix, iz);
            if (p[0] >= BENCH_WALL_X - cell - 1e-3 and p[0] < BENCH_WALL_X) m.cliff[iz * wf.HEIGHT_N + ix] = wf.CLIFF_FACE;
        }
    }
    return m;
}

fn benchEnv(m: *const wf.Map) !*Env {
    const e = try std.testing.allocator.create(Env);
    e.* = .{ .ground = undefined, .models = undefined };
    e.adoptHeight(m);
    e.materialize(m);
    return e;
}

fn firstCliff(e: *const Env, kind: props.Kind) !*const Prop {
    for (e.placed()) |*pr| {
        if (pr.kind == kind) return pr;
    }
    return error.TestUnexpectedResult;
}

test "EVERY PLACEABLE CLIFF HAS A SEAT IN FRONT OF ITS ORIGIN — the piece plants on the low ground, never on the lip it seats against" {
    std.debug.print("\n  cliff seats (local metres, scale 1; tolerance {d:.2} m = HEIGHT_STEP):\n", .{TOL});
    for (0..proprock.CLIFF_PROPS.len) |row| {
        const pc = pieceOf(row);
        std.debug.print("    cliff{d}: seat z {d:.2}, top {d:.2} of {d:.2}, run {d:.1}..{d:.1} ({d:.1} m), stone {d:.1}..{d:.1} x {d:.1}..{d:.1} z; proud {d:.2} m mean {d:.2} max, bare {d:.0}%\n", .{
            row + 1, pc.seat, pc.top, pc.height, pc.run0, pc.run1, pc.run1 - pc.run0, pc.x0, pc.x1, pc.front, pc.back, pc.proudMean, pc.proudMax, pc.bare * 100,
        });
        try std.testing.expect(pc.seat > 0);
        try std.testing.expect(pc.top > 0 and pc.top <= pc.height);
        try std.testing.expect(pc.run1 - pc.run0 > 2 * STATION);
        try std.testing.expect(pc.front < pc.seat and pc.seat < pc.back);
    }
}

test "A RAW PLACEMENT READS RED IN METRES AND THE CONFORM BRUSH SEATS IT GREEN — the bench, before and after" {
    const m = try benchMap();
    defer std.testing.allocator.destroy(m);
    std.fs.cwd().access(BENCH, .{}) catch |err| {
        if (err != error.FileNotFound) return err;
        try wf.save(BENCH, m);
    };
    const e = try benchEnv(m);
    defer std.testing.allocator.destroy(e);
    const cell = m.heightStep();

    const raw = try firstCliff(e, .cliff);
    const before = seatOf(.{ .env = e }, raw) orelse return error.TestUnexpectedResult;
    std.debug.print("\n  cliff seat bench: cell {d:.3} m, wall at x {d:.1}, drop {d:.1} m\n", .{ cell, BENCH_WALL_X, BENCH_DROP });
    std.debug.print("    raw cliff at x {d:.2} scale {d:.2}: {d} stations, {d} without a cut, setback {d:.2} m, over {d:.2} m, under {d:.2} m -> worst {d:.2} m\n", .{
        raw.pos.x, raw.scale, before.stations, before.missing, before.setback, before.over, before.under, before.worst(),
    });
    try std.testing.expect(before.cut());
    try std.testing.expect(!before.ok());
    try std.testing.expect(before.worst() > TOL);
    try std.testing.expectApproxEqAbs(BENCH_DROP, before.drop, TOL);

    const seatMap = seatOf(.{ .map = m }, raw) orelse return error.TestUnexpectedResult;
    try std.testing.expectApproxEqAbs(before.setback, seatMap.setback, 1e-3);
    try std.testing.expectApproxEqAbs(before.over, seatMap.over, 1e-3);

    var span: [4]usize = wf.EMPTY_SPAN;
    const r = conform(m, raw, &span);
    try std.testing.expect(r.changed);
    try std.testing.expect(span[0] <= span[2] and span[1] <= span[3]);
    e.adoptHeight(m);
    e.materialize(m);
    const seated = try firstCliff(e, .cliff);
    const after = seatOf(.{ .env = e }, seated) orelse return error.TestUnexpectedResult;
    std.debug.print("    conformed: foot {d:.2} m, lip {d:.2} m (top {d:.2} m), piece slid {d:.3} m; setback {d:.3} m, over {d:.3} m, under {d:.3} m -> worst {d:.3} m\n", .{
        r.foot, r.lip, seated.pos.y + pieceOf(after.row).top * seated.scale, r.slid, after.setback, after.over, after.under, after.worst(),
    });
    try std.testing.expect(after.cut());
    try std.testing.expect(after.ok());
    try std.testing.expectApproxEqAbs(r.foot, seated.pos.y, 1e-4);
    try std.testing.expect(@abs(r.slid) <= cell * 0.5 + 1e-3);

    const pc = pieceOf(after.row);
    const fr = Frame.of(seated);
    var x = pc.run0;
    var worstLip: f32 = 0;
    var worstFoot: f32 = 0;
    while (x <= pc.run1 + 1e-4) : (x += STATION) {
        const behind = fr.world(x, pc.seat + 1.5 * cell / seated.scale);
        const toe = fr.world(x, pc.front);
        worstLip = @max(worstLip, @abs(m.heightAt(behind[0], behind[1]) - r.lip));
        worstFoot = @max(worstFoot, @abs(m.heightAt(toe[0], toe[1]) - r.foot));
    }
    std.debug.print("    the plateau behind the seat is level to {d:.3} m and the ground under the toe to {d:.3} m\n", .{ worstLip, worstFoot });
    try std.testing.expect(worstLip < 1e-3 and worstFoot < 1e-3);

    const again = conform(m, seated, &span);
    try std.testing.expect(@abs(again.slid) <= TOL);
}

fn terraceCase(row: usize, s: f32, indent: bool) !void {
    const m = try wf.testMap(std.testing.allocator, wf.TEST_HEAD ++ "half: 107.4\n");
    defer std.testing.allocator.destroy(m);
    const base: f32 = 0.0;
    const pc = pieceOf(row);
    const want = rise(row, s);
    var span: [4]usize = wf.EMPTY_SPAN;
    const rim = terrace(m, .{ .x0 = -15, .z0 = -15, .x1 = 15, .z1 = 15 }, if (indent) base - want else base + want, &span) orelse return error.TestUnexpectedResult;
    try std.testing.expectApproxEqAbs(if (indent) base - want else base + want, rim.level, 1e-5);
    try std.testing.expectApproxEqAbs(@round(want / wf.HEIGHT_STEP) * wf.HEIGHT_STEP, want, 1e-5);
    try std.testing.expect(want <= pc.top * s and pc.top * s - want < wf.HEIGHT_STEP);

    var o = wf.defaults(.at);
    o.kind = @enumFromInt(@intFromEnum(props.Kind.cliff) + row);
    o.scale = s;
    o.z = 0;
    if (indent) {
        o.x = rim.x0 + pc.seat * s;
        o.yaw = 270;
    } else {
        o.x = rim.x0 - pc.seat * s;
        o.yaw = 90;
    }
    _ = try m.add(o);
    const e = try benchEnv(m);
    defer std.testing.allocator.destroy(e);
    const pr = try firstCliff(e, o.kind);
    const st = seatOf(.{ .env = e }, pr) orelse return error.TestUnexpectedResult;
    std.debug.print("    {s} cliff{d} scale {d:.2}: rise {d:.2} m (rock {d:.2} m), rim x {d:.3}, foot {d:.2} m; setback {d:.4} m, over {d:.3} m, under {d:.3} m -> {s}\n", .{
        if (indent) "indent " else "plateau", row + 1, s, want, pc.top * s, rim.x0, pr.pos.y, st.setback, st.over, st.under, if (st.ok()) "green" else "RED",
    });
    try std.testing.expect(st.cut());
    try std.testing.expectEqual(@as(f32, 0), st.over);
    try std.testing.expectEqual(@as(f32, 0), st.under);
    try std.testing.expect(@abs(st.setback) < 1e-3);
    try std.testing.expect(st.ok());
    try std.testing.expectApproxEqAbs(if (indent) base - want else base, pr.pos.y, 1e-5);
    try std.testing.expectApproxEqAbs(want, st.drop, 1e-3);
}

test "A PLATEAU OR INDENT AT A ROW'S HEIGHT SEATS THAT ROW'S PIECE GREEN ON THE FIRST TRY — over and under zero by construction, before any conform" {
    std.debug.print("\n  terraces sized off the pieces (tolerance {d:.2} m):\n", .{TOL});
    for ([_]f32{ 1.0, 0.45 }) |s| {
        for (0..proprock.CLIFF_PROPS.len) |row| {
            try terraceCase(row, s, false);
            try terraceCase(row, s, true);
        }
    }
}

test "A TERRACE RIM IS A STRAIGHT LINE ON THE LATTICE — one level inside, the cut on one line, so a piece SEATS anywhere along it" {
    const m = try wf.testMap(std.testing.allocator, wf.TEST_HEAD ++ "half: 107.4\n");
    defer std.testing.allocator.destroy(m);
    var span: [4]usize = wf.EMPTY_SPAN;
    const rim = terrace(m, .{ .x0 = -10.2, .z0 = -7.7, .x1 = 9.1, .z1 = 6.3 }, 4.0, &span) orelse return error.TestUnexpectedResult;
    const g = Ground{ .map = m };
    var x: f32 = rim.x0 + 0.3;
    var worst: f32 = 0;
    while (x < rim.x1 - 0.3) : (x += 0.25) {
        var z: f32 = rim.z0 + 0.3;
        while (z < rim.z1 - 0.3) : (z += 0.25) worst = @max(worst, @abs(g.at(x, z) - rim.level));
    }
    try std.testing.expect(worst < 1e-4);
    var stations: u32 = 0;
    var wander: f32 = 0;
    var z: f32 = rim.z0 + 1.0;
    while (z < rim.z1 - 1.0) : (z += 0.5) {
        const ct = cutAcross(g, rim.x0, z, -1, 0, 3.0) orelse return error.TestUnexpectedResult;
        wander = @max(wander, @abs(ct.t));
        stations += 1;
    }
    std.debug.print("\n  terrace rim: inside level to {d:.5} m; west cut wanders {d:.5} m off x {d:.3} over {d} stations\n", .{ worst, wander, rim.x0, stations });
    try std.testing.expect(wander < 1e-3);
}

test "A SEATED PIECE COLLIDES AS THE ROCK IN FRONT OF THE CUT AND NOTHING ELSE — no walk-through below, no invisible wall on the plateau" {
    const m = try benchMap();
    defer std.testing.allocator.destroy(m);
    const e = try benchEnv(m);
    defer std.testing.allocator.destroy(e);
    const raw = try firstCliff(e, .cliff);
    const loose = props.partsOf(raw.kind).len;
    var span: [4]usize = wf.EMPTY_SPAN;
    _ = conform(m, raw, &span);
    e.adoptHeight(m);
    e.materialize(m);
    const pr = try firstCliff(e, .cliff);
    const ct = cutOf(.{ .env = e }, pr) orelse return error.TestUnexpectedResult;
    const pc = pieceOf(props.cliffRow(pr.kind).?);
    const fr = Frame.of(pr);
    const n = fr.normal();
    const R: f32 = 0.35;

    var stopped: u32 = 0;
    var walked: u32 = 0;
    var shortest: f32 = 1e9;
    var x = pc.run0;
    while (x <= pc.run1 + 1e-4) : (x += STATION) {
        const start = fr.world(x, pc.front - 3.0);
        var p = v3(start[0], pr.pos.y, start[1]);
        var steps: u32 = 0;
        while (steps < 400) : (steps += 1) {
            const q = v3(p.x - n[0] * 0.05, p.y, p.z - n[1] * 0.05);
            const r = e.resolveActor(q, R, e.groundAt(q.x, q.z));
            if (mathx.distXZ(r, p) < 1e-4) break;
            p = r;
            p.y = e.groundAt(p.x, p.z);
        }
        walked += 1;
        const l = fr.local(p.x, p.z);
        const short = ct.z - l[1];
        shortest = @min(shortest, short);
        if (short > R) stopped += 1;
    }
    std.debug.print("\n  seated cliff colliders: {d} loose capsules -> {d} solids; walked into at {d} stations, stopped short of the cut at {d}, nearest approach {d:.2} m\n", .{
        loose, e.solidCount(), walked, stopped, shortest,
    });
    try std.testing.expect(shortest > 0);

    var pushed: u32 = 0;
    var lz = ct.z + 0.5;
    while (lz < pc.back * pr.scale) : (lz += 0.5) {
        x = pc.x0;
        while (x <= pc.x1) : (x += STATION) {
            const w = fr.world(x, lz / pr.scale);
            const p = v3(w[0], ct.lip, w[1]);
            const r = e.resolveActor(p, R, ct.lip);
            if (mathx.distXZ(r, p) > 1e-4) pushed += 1;
        }
    }
    std.debug.print("    on the plateau over the buried lobes: {d} of the probes met a collider\n", .{pushed});
    try std.testing.expectEqual(@as(u32, 0), pushed);
}

test "THE AUTOMATIC FACE STEPS ASIDE FOR A PLACED PIECE — `covers` is true along the cut behind the stone and false past its ends" {
    const m = try benchMap();
    defer std.testing.allocator.destroy(m);
    const e = try benchEnv(m);
    defer std.testing.allocator.destroy(e);
    const pr = try firstCliff(e, .cliff);
    const pc = pieceOf(props.cliffRow(pr.kind).?);
    const fr = Frame.of(pr);
    var x = pc.run0;
    while (x <= pc.run1) : (x += STATION) {
        const on = fr.world(x, pc.seat);
        try std.testing.expect(covers(pr, on[0], on[1]));
    }
    const past = fr.world(pc.x1 + 1.0, pc.seat);
    const far = fr.world(0, pc.back + 1.0);
    try std.testing.expect(!covers(pr, past[0], past[1]));
    try std.testing.expect(!covers(pr, far[0], far[1]));
}

test "A FREESTANDING CLIFF KEEPS ITS FITTED COLLIDERS — no cut, no clipping" {
    const m = try wf.testMap(std.testing.allocator, wf.TEST_HEAD ++ "at: cliff2 0 0 30 1\n");
    defer std.testing.allocator.destroy(m);
    const e = try benchEnv(m);
    defer std.testing.allocator.destroy(e);
    const pr = try firstCliff(e, .cliff2);
    try std.testing.expect(seatOf(.{ .env = e }, pr) != null);
    try std.testing.expect(!seatOf(.{ .env = e }, pr).?.cut());
    try std.testing.expect(cutOf(.{ .env = e }, pr) == null);
    try std.testing.expectEqual(props.partsOf(.cliff2).len, e.solidCount());
}
