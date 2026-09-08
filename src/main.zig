const std = @import("std");
const game = @import("game.zig");
const bake = @import("core/bake.zig");
const wf = @import("world/worldfmt.zig");
const env = @import("world/env.zig");
const caves = @import("world/caves.zig");
const shots = @import("shots.zig");

pub fn main() void {
    const alloc = std.heap.c_allocator;
    const argv = std.process.argsAlloc(alloc) catch {
        game.run(.play);
        return;
    };
    defer std.process.argsFree(alloc, argv);

    if (argv.len >= 2 and std.mem.eql(u8, argv[1], "--bake")) {
        runBake(alloc, hasArg(argv, "--force")) catch |e| {
            std.debug.print("bake FAILED: {s}\n", .{@errorName(e)});
            std.process.exit(1);
        };
        return;
    }
    // DEV ONLY: dig every water dweller's pool on a map to the dweller floor and save it.
    if (argv.len >= 2 and std.mem.eql(u8, argv[1], "--fix-lurkers")) {
        const path = if (argv.len >= 3) argv[2] else wf.START_MAP;
        runFixLurkers(alloc, path) catch |e| {
            std.debug.print("fix-lurkers FAILED: {s}\n", .{@errorName(e)});
            std.process.exit(1);
        };
        return;
    }
    // DEV ONLY: drop every chamber on a map the land cannot roof, keep the largest one a body can walk, and open it.
    if (argv.len >= 2 and std.mem.eql(u8, argv[1], "--fix-caves")) {
        const path = if (argv.len >= 3) argv[2] else wf.START_MAP;
        runFixCaves(alloc, path, hasArg(argv, "--write")) catch |e| {
            std.debug.print("fix-caves FAILED: {s}\n", .{@errorName(e)});
            std.process.exit(1);
        };
        return;
    }
    // DEV ONLY: move a map into a bigger world without moving the land under it.
    if (argv.len >= 2 and std.mem.eql(u8, argv[1], "--grow")) {
        if (argv.len < 3) {
            std.debug.print("usage: --grow <map> [half] [--write]\n", .{});
            std.process.exit(1);
        }
        // No half: the load has already put an old map on today's lattice, and this just writes it back down.
        const half: f32 = if (argv.len >= 4 and argv[3].len > 0 and argv[3][0] != '-')
            std.fmt.parseFloat(f32, argv[3]) catch {
                std.debug.print("grow: {s} is not a number\n", .{argv[3]});
                std.process.exit(1);
            }
        else
            0;
        runGrow(alloc, argv[2], half, hasArg(argv, "--write")) catch |e| {
            std.debug.print("grow FAILED: {s}\n", .{@errorName(e)});
            std.process.exit(1);
        };
        return;
    }
    if (argv.len >= 2 and std.mem.eql(u8, argv[1], "--explode")) {
        const path = if (argv.len >= 3) argv[2] else wf.START_MAP;
        runExplode(alloc, path) catch |e| {
            std.debug.print("explode FAILED: {s}\n", .{@errorName(e)});
            std.process.exit(1);
        };
        return;
    }
    var i: usize = 1;
    while (i + 1 < argv.len) : (i += 1) {
        if (std.mem.eql(u8, argv[i], "--map")) {
            wf.setStartMap(argv[i + 1]);
            std.debug.print("MAP: {s}\n", .{argv[i + 1]});
            break;
        }
    }
    // DEV ONLY: run one stage of the shot harness. A full --shot is 3m38s, which is not an iteration loop.
    i = 1;
    while (i + 1 < argv.len) : (i += 1) {
        if (std.mem.eql(u8, argv[i], "--shot-only")) {
            shots.onlyStage = argv[i + 1];
            std.debug.print("SHOT STAGE: {s}\n", .{argv[i + 1]});
            break;
        }
    }
    game.dbgBright = hasArg(argv, "--bright");
    const mode: game.Mode = if (hasArg(argv, "--shot-props"))
        .props
    else if (hasArg(argv, "--shot-land"))
        .land
    else if (hasArg(argv, "--shot-art"))
        .art
    else if (hasArg(argv, "--shot"))
        .shots
    else
        .play;
    game.run(mode);
}

fn hasArg(argv: []const [:0]u8, want: []const u8) bool {
    for (argv[1..]) |a| {
        if (std.mem.eql(u8, a, want)) return true;
    }
    return false;
}

/// THE DOOR IS ONE-WAY AND IT HAS BEEN WALKED THROUGH: the bake emits the ORIGINAL code-authored regions over `START_MAP`, so run today it throws away every op the editor has put there since. `wf.save`'s trap is `is_test` only, so this flag refuses a map that already exists.
fn runBake(alloc: std.mem.Allocator, force: bool) !void {
    if (!force) {
        if (std.fs.cwd().access(wf.START_MAP, .{})) |_| {
            std.debug.print(
                "bake REFUSED: {s} already exists, and baking replaces it with the code-authored map.\n" ++
                    "  Move it aside, or pass --force if that is really what you want.\n",
                .{wf.START_MAP},
            );
            return error.PathAlreadyExists;
        } else |_| {}
    }
    const m = try alloc.create(wf.Map);
    defer alloc.destroy(m);
    bake.build(m);

    try wf.save(wf.START_MAP, m);

    const text = try std.fs.cwd().readFileAlloc(alloc, wf.START_MAP, wf.TEXT_CAP);
    defer alloc.free(text);
    const back = try alloc.create(wf.Map);
    defer alloc.destroy(back);
    var line: usize = 0;
    wf.parse(text, back, &line) catch |e| {
        std.debug.print("bake wrote a file it cannot read back: {s} at line {d}\n", .{ @errorName(e), line });
        return e;
    };
    std.debug.print(
        "baked {s} — {d} ops, {d} zones, {d} clearings ({d} bytes)\n",
        .{ wf.START_MAP, m.nops, m.nzones, m.nclearings, text.len },
    );
}

fn runFixLurkers(alloc: std.mem.Allocator, path: []const u8) !void {
    const m = try alloc.create(wf.Map);
    defer alloc.destroy(m);
    var line: usize = 0;
    try wf.load(path, m, &line);
    const e = try alloc.create(env.Env);
    defer alloc.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };
    const moved = env.Env.digPools(m, 5.0);
    e.uploadWater(m);
    e.adoptHeight(m);
    for (m.foes[0..m.nfoes]) |f| {
        if (f.kind != .fen_lurker) continue;
        std.debug.print("  fen lurker at {d:.2} {d:.2}: {d:.3} m of water\n", .{ f.x, f.z, e.wadeDepth(f.x, f.z) });
    }
    std.debug.print("{s}: {d} lattice points dug to {d:.2}\n", .{ path, moved, env.dwellerFloor() });
    if (moved > 0) try wf.save(path, m);
}

fn runExplode(alloc: std.mem.Allocator, path: []const u8) !void {
    const m = try alloc.create(wf.Map);
    defer alloc.destroy(m);
    var line: usize = 0;
    try wf.load(path, m, &line);
    const e = try alloc.create(env.Env);
    defer alloc.destroy(e);
    e.* = .{ .ground = undefined, .models = undefined };

    e.uploadWater(m);
    e.materialize(m);
    const props0 = e.propCount();
    const solids0 = e.solidCount();
    const lights0 = e.lightCount();
    const ops0 = m.nops;

    var s = m.nops;
    var broken: usize = 0;
    while (s > 0) {
        s -= 1;
        if (m.ops[s].op == .at) continue;
        _ = try e.explodeOp(m, s);
        broken += 1;
    }
    try wf.save(path, m);

    const back = try alloc.create(wf.Map);
    defer alloc.destroy(back);
    try wf.load(path, back, &line);
    e.uploadWater(back);
    e.materialize(back);
    std.debug.print(
        "exploded {s} — {d} ops ({d} groups) -> {d} ops\n  props {d} -> {d}, solids {d} -> {d}, lights {d} -> {d}\n",
        .{ path, ops0, broken, back.nops, props0, e.propCount(), solids0, e.solidCount(), lights0, e.lightCount() },
    );
    if (e.propCount() != props0 or e.solidCount() != solids0 or e.lightCount() != lights0) return error.MapMoved;
}

/// Rock thinner than this over a ceiling is not a roof, and what is under it is a crater with a lid.
const CAVE_ROOF_MIN: f32 = 1.0;
/// How wide the passage this cuts is. The editor's is the brush radius, so this one has no counterpart there.
const CAVE_PASSAGE_R: f32 = 2.6;
const CAVE_GRADE = caves.ENTRANCE_GRADE;
const CAVE_SINK = caves.ENTRANCE_SINK;
/// Ground at or under this is open flat, which is where a mouth may come out.
const CAVE_OPEN_LAND: f32 = 0.3;
/// How far the ground must STAY open past the first flat point, so a dimple on the hill is not mistaken for the plain.
const CAVE_OPEN_RUN: f32 = 8.0;

const CaveStat = struct {
    n: usize = 0,
    open: usize = 0,
    thin: usize = 0,
    cover: f32 = 1e9,
    head: f32 = 1e9,
    floorLo: f32 = 1e9,
    floorHi: f32 = -1e9,
};

fn caveStat(m: *const wf.Map) CaveStat {
    var s = CaveStat{};
    for (0..caves.N) |iz| {
        for (0..caves.N) |ix| {
            const i = iz * caves.N + ix;
            if (m.caveCov[i] < wf.CAVE_EDGE) continue;
            const p = caves.pointAt(m.half, ix, iz);
            const floor = wf.heightOf(m.caveFloor[i]);
            const roof = wf.heightOf(m.caveRoof[i]);
            const cover = m.heightAt(p[0], p[1]) - roof;
            s.n += 1;
            if (cover <= 0) s.open += 1;
            if (cover < CAVE_ROOF_MIN) s.thin += 1;
            s.cover = @min(s.cover, cover);
            s.head = @min(s.head, roof - floor);
            s.floorLo = @min(s.floorLo, floor);
            s.floorHi = @max(s.floorHi, floor);
        }
    }
    return s;
}

fn caveSay(tag: []const u8, s: CaveStat) void {
    if (s.n == 0) {
        std.debug.print("  {s}: nothing excavated\n", .{tag});
        return;
    }
    std.debug.print(
        "  {s}: {d} points, floor {d:.2}..{d:.2} m, least headroom {d:.2} m, thinnest roof {d:.2} m, {d} cut open to the sky, {d} under less than {d:.2} m of rock\n",
        .{ tag, s.n, s.floorLo, s.floorHi, s.head, s.cover, s.open, s.thin, CAVE_ROOF_MIN },
    );
}

fn caveFill(m: *wf.Map, i: usize) void {
    m.caveCov[i] = 0;
    m.caveFloor[i] = wf.HEIGHT_ZERO;
    m.caveRoof[i] = wf.HEIGHT_ZERO;
}

/// DEV ONLY: repair a hand-painted cave layer. A carve made with the floor plane left up at the hilltop lays a chamber in
/// the AIR. This drops those, keeps the largest chamber a body can walk end to end, cuts one entrance out to the nearest open ground, and proves the walk in before it writes anything.
fn runFixCaves(alloc: std.mem.Allocator, path: []const u8, write: bool) !void {
    const m = try alloc.create(wf.Map);
    defer alloc.destroy(m);
    var line: usize = 0;
    try wf.load(path, m, &line);
    std.debug.print("{s}\n", .{path});
    if (!m.anyCave()) {
        std.debug.print("  no cave layer\n", .{});
        return;
    }
    caveSay("before", caveStat(m));

    var dropped: usize = 0;
    for (0..caves.N) |iz| {
        for (0..caves.N) |ix| {
            const i = iz * caves.N + ix;
            if (m.caveCov[i] < wf.CAVE_EDGE) continue;
            const p = caves.pointAt(m.half, ix, iz);
            if (m.heightAt(p[0], p[1]) - wf.heightOf(m.caveRoof[i]) >= CAVE_ROOF_MIN) continue;
            caveFill(m, i);
            dropped += 1;
        }
    }
    std.debug.print("  dropped {d} points the land could not roof\n", .{dropped});

        // ONE CHAMBER: the largest run of points a body could walk between. A ledge left over a passage it cannot step up onto is as good as filled.
    const mark = try alloc.alloc(u32, caves.CELLS);
    defer alloc.free(mark);
    @memset(mark, 0);
    const stack = try alloc.alloc(u32, caves.CELLS);
    defer alloc.free(stack);
    var tag: u32 = 0;
    var best: usize = 0;
    var bestTag: u32 = 0;
    var parts: usize = 0;
    for (0..caves.CELLS) |seed| {
        if (m.caveCov[seed] < wf.CAVE_EDGE or mark[seed] != 0) continue;
        tag += 1;
        parts += 1;
        var n: usize = 0;
        var top: usize = 1;
        stack[0] = @intCast(seed);
        mark[seed] = tag;
        while (top > 0) {
            top -= 1;
            const i: usize = stack[top];
            n += 1;
            const ix = i % caves.N;
            const iz = i / caves.N;
            const floor = wf.heightOf(m.caveFloor[i]);
            const dirs = [4][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };
            for (dirs) |d| {
                const nx = @as(i32, @intCast(ix)) + d[0];
                const nz = @as(i32, @intCast(iz)) + d[1];
                if (nx < 0 or nz < 0 or nx >= caves.N or nz >= caves.N) continue;
                const j = @as(usize, @intCast(nz)) * caves.N + @as(usize, @intCast(nx));
                if (m.caveCov[j] < wf.CAVE_EDGE or mark[j] != 0) continue;
                if (@abs(wf.heightOf(m.caveFloor[j]) - floor) > wf.STEP_UP) continue;
                mark[j] = tag;
                stack[top] = @intCast(j);
                top += 1;
            }
        }
        if (n > best) {
            best = n;
            bestTag = tag;
        }
    }
    var orphans: usize = 0;
    for (0..caves.CELLS) |i| {
        if (m.caveCov[i] < wf.CAVE_EDGE or mark[i] == bestTag) continue;
        caveFill(m, i);
        orphans += 1;
    }
    std.debug.print("  {d} walkable pieces; kept the largest ({d} points), filled {d}\n", .{ parts, best, orphans });
    if (best == 0) return error.NothingLeft;

        // THE DEEP POINT: the most rock over it of anything left. The entrance is aimed at that, and the mouth is the nearest open ground to it.
    var deep: [2]f32 = .{ 0, 0 };
    var deepCover: f32 = -1e9;
    var deepFloor: f32 = 0;
    var deepHead: f32 = 0;
    for (0..caves.N) |iz| {
        for (0..caves.N) |ix| {
            const i = iz * caves.N + ix;
            if (mark[i] != bestTag or m.caveCov[i] < wf.CAVE_EDGE) continue;
            const p = caves.pointAt(m.half, ix, iz);
            const roof = wf.heightOf(m.caveRoof[i]);
            const cover = m.heightAt(p[0], p[1]) - roof;
            if (cover <= deepCover) continue;
            deepCover = cover;
            deep = p;
            deepFloor = wf.heightOf(m.caveFloor[i]);
            deepHead = roof - deepFloor;
        }
    }

    const BEARINGS: usize = 128;
    var mouth: [2]f32 = .{ 0, 0 };
    var runOut: f32 = 1e9;
    for (0..BEARINGS) |k| {
        const a = std.math.tau * @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(BEARINGS));
        const ux = @cos(a);
        const uz = @sin(a);
        var s: f32 = 4;
        while (s < 200) : (s += 0.5) {
            if (m.heightAt(deep[0] + ux * s, deep[1] + uz * s) > CAVE_OPEN_LAND) continue;
            var t: f32 = 0;
            var open = true;
            while (t <= CAVE_OPEN_RUN) : (t += 1) {
                if (m.heightAt(deep[0] + ux * (s + t), deep[1] + uz * (s + t)) > CAVE_OPEN_LAND) open = false;
            }
            if (!open) continue;
            if (s < runOut) {
                runOut = s;
                mouth = .{ deep[0] + ux * (s + CAVE_OPEN_RUN * 0.5), deep[1] + uz * (s + CAVE_OPEN_RUN * 0.5) };
            }
            break;
        }
    }
    if (runOut > 500) return error.NoOpenGround;
    std.debug.print(
        "  chamber floor {d:.2} m, headroom {d:.2} m, {d:.2} m of rock at its deepest ({d:.1},{d:.1}); nearest open ground {d:.1} m out, mouth at {d:.1},{d:.1}\n",
        .{ deepFloor, deepHead, deepCover, deep[0], deep[1], runOut, mouth[0], mouth[1] },
    );

    const head = @max(deepHead, caves.HEAD_MIN);
    const dx = deep[0] - mouth[0];
    const dz = deep[1] - mouth[1];
    const len = @sqrt(dx * dx + dz * dz);
    const ux = dx / len;
    const uz = dz / len;
    const start = m.heightAt(mouth[0], mouth[1]) - CAVE_SINK;
    var span: [4]usize = wf.EMPTY_SPAN;
    var s: f32 = 0;
    while (s <= len) : (s += caves.cellStep(m.half) * 0.5) {
        const floor = start - CAVE_GRADE * s;
        _ = caves.carve(caves.gridsOf(m), .{
            .px = mouth[0] + ux * s,
            .pz = mouth[1] + uz * s,
            .r = CAVE_PASSAGE_R,
            .floor = floor,
            .roof = floor + head,
            .dx = -CAVE_GRADE * ux,
            .dz = -CAVE_GRADE * uz,
            .floorMin = deepFloor,
        }, &span);
    }

    const f = caves.fieldsOf(m);
    const mouthLand = m.heightAt(mouth[0], mouth[1]);
    const mouthCell = caves.sampleAt(f, mouth[0], mouth[1]);
    var y = mouthLand;
    var worst: f32 = 0;
    var worstAt: [2]f32 = .{ 0, 0 };
    var under: usize = 0;
    var steps: usize = 0;
    var tight: f32 = 1e9;
    s = 0;
    while (s <= len) : (s += 0.5) {
        const px = mouth[0] + ux * s;
        const pz = mouth[1] + uz * s;
        const sup = caves.supportAt(f, m.heightAt(px, pz), px, pz, y);
        if (@abs(sup.y - y) > worst) {
            worst = @abs(sup.y - y);
            worstAt = .{ px, pz };
        }
        if (sup.surface == .cave) {
            under += 1;
            tight = @min(tight, caves.sampleAt(f, px, pz).headroom());
        }
        steps += 1;
        y = sup.y;
    }
    std.debug.print(
        "  mouth roof {d:.2} m against ground {d:.2} m; walk in {d} taps, {d} underground, tightest {d:.2} m, worst step {d:.3} m at {d:.1},{d:.1} (limit {d:.2})\n",
        .{ mouthCell.roof, mouthLand, steps, under, tight, worst, worstAt[0], worstAt[1], wf.STEP_UP },
    );
    caveSay("after", caveStat(m));
    if (worst > wf.STEP_UP) return error.WalkBlocked;
    if (mouthCell.roof < mouthLand) return error.MouthSealed;

    if (!write) {
        std.debug.print("  dry run — pass --write to save\n", .{});
        return;
    }
    try wf.save(path, m);
    std.debug.print("  saved\n", .{});
}

/// DEV ONLY: put a map in a bigger world and leave the land where it stands. Every grid is resampled from the old extent
/// onto the new one, so a hill keeps its world coordinates. Ops, spawns and rectangles are already world-space and are not touched.
fn runGrow(alloc: std.mem.Allocator, path: []const u8, want: f32, write: bool) !void {
    const m = try alloc.create(wf.Map);
    defer alloc.destroy(m);
    var line: usize = 0;
    try wf.load(path, m, &line);
    const was = m.half;
    const half = if (want > 0) want else was;
    std.debug.print("{s}: half {d:.2} -> {d:.2} m\n", .{ path, was, half });
    if (!(half > 0 and half <= wf.MAX_DECLARED_HALF)) return error.BadHalf;
    if (half < was) return error.WouldCropTheMap;

    const src = try alloc.create(wf.Map);
    defer alloc.destroy(src);
    src.* = m.*;
    const G = struct {
        dst: []u8,
        src: []const u8,
        n: usize,
        kind: wf.Lattice,
        smooth: bool,
    };
    const grids = [_]G{
        .{ .dst = &m.soil, .src = &src.soil, .n = wf.SOIL_N, .kind = .cell, .smooth = false },
        .{ .dst = &m.soilCov, .src = &src.soilCov, .n = wf.SOIL_N, .kind = .cell, .smooth = true },
        .{ .dst = &m.soilEdge, .src = &src.soilEdge, .n = wf.SOIL_N, .kind = .cell, .smooth = false },
        .{ .dst = &m.water, .src = &src.water, .n = wf.WATER_N, .kind = .cell, .smooth = true },
        .{ .dst = &m.waterEdge, .src = &src.waterEdge, .n = wf.WATER_N, .kind = .cell, .smooth = false },
        .{ .dst = &m.waterKind, .src = &src.waterKind, .n = wf.WATER_N, .kind = .cell, .smooth = false },
        .{ .dst = &m.height, .src = &src.height, .n = wf.HEIGHT_N, .kind = .point, .smooth = true },
        .{ .dst = &m.cliff, .src = &src.cliff, .n = wf.HEIGHT_N, .kind = .point, .smooth = false },
        .{ .dst = &m.caveCov, .src = &src.caveCov, .n = wf.CAVE_N, .kind = .point, .smooth = true },
        .{ .dst = &m.caveFloor, .src = &src.caveFloor, .n = wf.CAVE_N, .kind = .point, .smooth = false },
        .{ .dst = &m.caveRoof, .src = &src.caveRoof, .n = wf.CAVE_N, .kind = .point, .smooth = false },
    };
    for (grids) |g| wf.regrid(g.dst, g.n, half, g.src, g.n, was, g.kind, g.smooth);
        // The rim is CARRIED OUTWARD, so the margin repeats whatever the old edge held. Water and cave out there would be a moat and a tunnel nobody authored.
    var wetted: usize = 0;
    const wcell = 2 * half / @as(f32, @floatFromInt(wf.WATER_N));
    for (0..wf.WATER_N) |iz| {
        for (0..wf.WATER_N) |ix| {
            const p = [2]f32{ wf.cellCentre(half, wcell, ix), wf.cellCentre(half, wcell, iz) };
            if (@abs(p[0]) <= was and @abs(p[1]) <= was) continue;
            const i = iz * wf.WATER_N + ix;
            if (m.water[i] != 0) wetted += 1;
            m.water[i] = 0;
        }
    }
    var dug: usize = 0;
    for (0..wf.CAVE_N) |iz| {
        for (0..wf.CAVE_N) |ix| {
            const p = caves.pointAt(half, ix, iz);
            if (@abs(p[0]) <= was and @abs(p[1]) <= was) continue;
            const i = iz * wf.CAVE_N + ix;
            if (m.caveCov[i] >= wf.CAVE_EDGE) dug += 1;
            m.caveCov[i] = 0;
        }
    }
    m.half = half;

    var worst: f32 = 0;
    var worstAt: [2]f32 = .{ 0, 0 };
    var taps: usize = 0;
    var k: f32 = -was;
    while (k <= was) : (k += was / 32.0) {
        var j: f32 = -was;
        while (j <= was) : (j += was / 32.0) {
            const d = @abs(m.heightAt(k, j) - src.heightAt(k, j));
            if (d > worst) {
                worst = d;
                worstAt = .{ k, j };
            }
            taps += 1;
        }
    }
    std.debug.print(
        "  cell {d:.3} -> {d:.3} m, cave cell {d:.3} -> {d:.3} m; {d} taps over the old extent, worst height move {d:.3} m at {d:.1},{d:.1}\n",
        .{
            2 * was / @as(f32, @floatFromInt(wf.HEIGHT_N - 1)),
            2 * half / @as(f32, @floatFromInt(wf.HEIGHT_N - 1)),
            caves.cellStep(was),
            caves.cellStep(half),
            taps,
            worst,
            worstAt[0],
            worstAt[1],
        },
    );
    if (wetted > 0 or dug > 0) std.debug.print("  cleared {d} water cells and {d} cave points that the rim carried into the margin\n", .{ wetted, dug });
    if (worst > wf.HEIGHT_STEP) return error.LandMoved;

    if (!write) {
        std.debug.print("  dry run — pass --write to save\n", .{});
        return;
    }
    try wf.save(path, m);
    std.debug.print("  saved\n", .{});
}

test {
    _ = @import("play/hero.zig");
    _ = @import("core/anim.zig");
    _ = @import("core/camera.zig");
    _ = @import("core/mathx.zig");
    _ = @import("foes/frog.zig");
    _ = @import("foes/archer.zig");
    _ = @import("foes/ogre.zig");
    _ = @import("foes/knight.zig");
    _ = @import("foes/kobold.zig");
    _ = @import("foes/brood.zig");
    _ = @import("foes/warrior.zig");
    _ = @import("foes/shade.zig");
    _ = @import("foes/leechfly.zig");
    _ = @import("foes/rooted.zig");
    _ = @import("foes/shroom.zig");
    _ = @import("foes/delver.zig");
    _ = @import("foes/necro.zig");
    _ = @import("foes/fungaldeer.zig");
    _ = @import("foes/shroommage.zig");
    _ = @import("foes/sporegolem.zig");
    _ = @import("foes/fenlurker.zig");
    _ = @import("foes/skitterer.zig");
    _ = @import("foes/ancientpriest.zig");
    _ = @import("foes/hollow.zig");
    _ = @import("foes/slumberbloom.zig");
    _ = @import("foes/cinderwake.zig");
    _ = @import("foes/rotgorger.zig");
    _ = @import("foes/birchwight.zig");
    _ = @import("foes/salthusk.zig");
    _ = @import("foes/fishman.zig");
    _ = @import("foes/blinkbat.zig");
    _ = @import("props/propmarket.zig");
    _ = @import("props/propforge.zig");
    _ = @import("foes/wolf.zig");
    _ = @import("play/counter.zig");
    _ = @import("ui/counterui.zig");
    _ = @import("play/pickup.zig");
    _ = @import("play/award.zig");
    _ = @import("foes/foe.zig");
    _ = @import("foes/foestat.zig");
    _ = @import("foes/behave.zig");
    _ = @import("gfx/elemfx.zig");
    _ = @import("gfx/particleart.zig");
    _ = @import("props/proppalace.zig");
    _ = @import("play/combat.zig");
    _ = @import("play/stats.zig");
    _ = @import("play/item.zig");
    _ = @import("play/liquid.zig");
    _ = @import("foes/fungalduo.zig");
    _ = @import("foes/owlbear.zig");
    _ = @import("foes/druidess.zig");
    _ = @import("foes/mimic.zig");
    _ = @import("foes/mastodon.zig");
    _ = @import("foes/ent.zig");
    _ = @import("core/collision.zig");
    _ = @import("gfx/gfx.zig");
    _ = @import("world/daynight.zig");
    _ = @import("world/env.zig");
    _ = @import("props/props.zig");
    _ = @import("world/worldfmt.zig");
    _ = @import("world/caves.zig");
    _ = @import("world/spar.zig");
    _ = @import("world/trigger.zig");
    _ = @import("world/dialog.zig");
    _ = @import("foes/npc.zig");
    _ = @import("ui/editor.zig");
    _ = @import("core/audio.zig");
    _ = @import("ui/hud.zig");
    _ = @import("ui/book.zig");
    _ = @import("ui/mapart.zig");
    _ = @import("game.zig");
    _ = @import("core/bake.zig");
    _ = @import("play/chest.zig");
    _ = @import("play/rest.zig");
    _ = @import("play/drops.zig");
    _ = @import("world/weather.zig");
    _ = @import("play/souls.zig");
    _ = @import("play/passivetree.zig");
    _ = @import("play/tune.zig");
    _ = @import("core/rumble.zig");
    _ = @import("save.zig");
    _ = @import("ui/menu.zig");
    _ = @import("ui/objview.zig");
    _ = @import("ui/tuneui.zig");
    _ = @import("shots.zig");
    _ = @import("gfx/shaders.zig");
    _ = @import("ui/ui.zig");
    _ = @import("ui/uiart.zig");
    _ = @import("ui/icons.zig");
    _ = @import("ui/itemart.zig");
    _ = @import("props/propart.zig");
    _ = @import("props/propbuild.zig");
    _ = @import("props/propflora.zig");
    _ = @import("props/propfx.zig");
    _ = @import("props/proprock.zig");
    _ = @import("props/propruins.zig");
    _ = @import("props/propvillage.zig");
    _ = @import("props/propwood.zig");
    _ = @import("props/propbone.zig");
    _ = @import("props/propash.zig");
    _ = @import("props/propfungus.zig");
    _ = @import("props/propcoral.zig");
    _ = @import("props/propgold.zig");
    _ = @import("props/propember.zig");
    _ = @import("props/propdesert.zig");
}
