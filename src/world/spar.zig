const std = @import("std");
const wf = @import("worldfmt.zig");
const env = @import("env.zig");
const foemod = @import("../foes/foe.zig");

/// Where the room is written when a test or the harness needs it on disk; the editor names the same file.
pub const PATH = wf.DIR ++ "/test_spar.world";

/// The floor's radius — 42 m across, which is room enough for the mastodon to charge and turn.
pub const R: f32 = 21.0;
/// The wall. Past `env.STEP_UP` and past `MAX_SLOPE` at this lattice, so neither he nor the creature can leave.
const WALL_H: f32 = 7.0;
/// How fast the wall climbs out of the floor, in metres per metre. ONE cell of the rise already clears `env.STEP_UP` (1.44 m against 0.55), which is what makes it a cut and not a ramp.
const WALL_GRADE: f32 = 3.0;
/// A map this size gives an 0.48 m lattice — five times the shipped map's resolution, and it rebuilds in a blink.
const HALF: f32 = 96.0;

const HERO_AT: f32 = R * 0.55;
const FOE_AT: f32 = -R * 0.55;
const RIM_LIGHTS: usize = 8;
/// Water dwellers need their own band; the pool is the middle of the floor so the fight is still in the open.
const POOL_R: f32 = 8.0;

/// ONE CREATURE, ONE ROOM, NOTHING ELSE. Built in memory from the kind alone — no file, and nothing of his own map in it.
pub fn author(m: *wf.Map, kind: wf.FoeKind) void {
    m.blank("spar");
    var nbuf: [wf.NAME_CAP]u8 = undefined;
    m.setName(std.fmt.bufPrint(&nbuf, "spar - {s}", .{wf.foeName(kind)}) catch "spar");
    m.half = HALF;

    // WRITTEN, NOT BRUSHED: the sculpt brush feathers over its whole radius, so a flatten wide enough to level
    // the floor levels the wall with it. The floor here is EXACTLY flat and the wall goes past `STEP_UP` in one cell.
    const pool = foemod.poolBand(kind) != null;
    const floorY: f32 = if (pool) env.dwellerFloor() else 0;
    for (0..wf.HEIGHT_N) |iz| {
        for (0..wf.HEIGHT_N) |ix| {
            const p = m.heightPoint(ix, iz);
            const d = @sqrt(p[0] * p[0] + p[1] * p[1]);
            const y = if (d <= R)
                (if (pool and d <= POOL_R) floorY else 0)
            else
                @min(WALL_H, (d - R) * WALL_GRADE);
            m.height[iz * wf.HEIGHT_N + ix] = wf.heightByte(y);
        }
    }
    var span: [4]usize = undefined;
    _ = m.paintCliff(0, 0, R + 4, wf.CLIFF_FACE, &span);
    _ = m.paintCliff(0, 0, R - 2, wf.CLIFF_NONE, &span);
    if (pool) _ = m.paintWater(0, 0, POOL_R, true, .speckle, .water);

    for (0..RIM_LIGHTS) |i| {
        const a = 2.0 * std.math.pi * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(RIM_LIGHTS));
        _ = m.add(.{
            .op = .at,
            .kind = .brazier,
            .x = @cos(a) * (R - 1.5),
            .z = @sin(a) * (R - 1.5),
        }) catch {};
    }
    // A GATE ON THE WALL IS WHAT MAKES IT A ROOM: it seals the fight behind him and is gone once the thing is
    // dead, which is the same contract every boss room in the game keeps.
    _ = m.add(.{
        .op = .at,
        .kind = .foggate,
        .x = 0,
        .z = R,
        .yaw = 0,
        .boss = [_]wf.FoeKind{kind} ** wf.MAX_SEAL,
        .nboss = 1,
    }) catch {};

    // THE FIRE IS THE RETRY: resting rehomes the creature at full health, which is the whole loop of a fight test.
    _ = m.add(.{ .op = .at, .kind = .campfire_lit, .x = 0, .z = HERO_AT + 5 }) catch {};

    // A DWELLER STANDS IN THE POOL THIS DUG. Posted at `FOE_AT` it was 3.55 m outside a `POOL_R` band, which is
    // the placement `foe.poolBand` exists to refuse.
    const foeZ: f32 = if (pool) 0 else FOE_AT;
    m.foes[0] = .{ .kind = kind, .x = 0, .z = foeZ, .yaw = 0, .scale = 1, .seed = 0.5, .ai = .hold, .when = .any };
    m.nfoes = 1;

    var a = wf.Arena{};
    a.setName("spar");
    a.boss = [_]wf.FoeKind{kind} ** wf.MAX_SEAL;
    a.nboss = 1;
    const verts = @min(wf.MAX_ARENA_VERTS, 20);
    for (0..verts) |i| {
        const t = 2.0 * std.math.pi * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(verts));
        a.vx[i] = @cos(t) * R;
        a.vz[i] = @sin(t) * R;
    }
    a.n = @intCast(verts);
    m.arenas[0] = a;
    m.narenas = 1;

    m.start = .{ .x = 0, .z = HERO_AT, .yaw = 180 };
}

test "the sparring room is walled, lit, and holds exactly the one creature asked for" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);

    author(m, .bone_knight);
    try std.testing.expectEqual(@as(usize, 1), m.nfoes);
    try std.testing.expectEqual(wf.FoeKind.bone_knight, m.foes[0].kind);
    try std.testing.expectEqual(wf.FoeWhen.any, m.foes[0].window());
    try std.testing.expect(m.anyHeight() and m.anyCliff());

    const mid = m.heightAt(0, 0);
    try std.testing.expectApproxEqAbs(mid, m.heightAt(0, HERO_AT), wf.HEIGHT_STEP);
    try std.testing.expectApproxEqAbs(mid, m.heightAt(0, FOE_AT), wf.HEIGHT_STEP);
    var worst: f32 = 1e9;
    for (0..16) |i| {
        const t = 2.0 * std.math.pi * @as(f32, @floatFromInt(i)) / 16.0;
        const rise = m.heightAt(@cos(t) * (R + 6), @sin(t) * (R + 6)) - mid;
        worst = @min(worst, rise);
    }
    std.debug.print(
        "\nspar room: {d:.0} m across, floor {d:.2} m, wall {d:.2} m over it at its LOWEST, {d} braziers\n",
        .{ 2 * R, mid, worst, RIM_LIGHTS },
    );
    try std.testing.expect(worst > env.STEP_UP);

    author(m, .fen_lurker);
    try std.testing.expect(m.anyWater());
    const wet = m.foes[0];
    const cell = wf.gridIndex(m.half, wf.WATER_N, wet.x, wet.z) orelse return error.PostOffTheMap;
    const deep = env.dwellerDepth();
    std.debug.print("lurker posted at {d:.1},{d:.1} in {d:.2} m of water (wants {d:.2}-{d:.2})\n", .{
        wet.x, wet.z, deep, foemod.poolBand(.fen_lurker).?[0], foemod.poolBand(.fen_lurker).?[1],
    });
    try std.testing.expect(m.water[cell] > 0);
    try std.testing.expectApproxEqAbs(env.dwellerFloor(), m.heightAt(wet.x, wet.z), 1e-4);
    const band = foemod.poolBand(.fen_lurker).?;
    try std.testing.expect(deep >= band[0] and deep <= band[1]);

    author(m, .toad);
    try std.testing.expect(!m.anyWater());
}

test "the room round-trips through the writer, so the shot harness can be pointed at one" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    author(m, .bone_knight);
    try wf.save(PATH, m);

    const text = try std.fs.cwd().readFileAlloc(std.testing.allocator, PATH, 8 << 20);
    defer std.testing.allocator.free(text);
    const back = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(back);
    var line: usize = 0;
    try wf.parse(text, back, &line);
    try std.testing.expectEqual(m.nfoes, back.nfoes);
    try std.testing.expectEqual(m.narenas, back.narenas);
    try std.testing.expect(m.arenas[0].onWall(0, R));
    try std.testing.expectEqual(wf.FoeKind.bone_knight, m.arenas[0].boss[0]);
    try std.testing.expectEqualSlices(wf.Hgt, &m.height, &back.height);
    std.debug.print("spar file: {d} KB, {d} ops, start ({d:.0}, {d:.0})\n", .{ text.len / 1024, back.nops, back.start.x, back.start.z });
}
