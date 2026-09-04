const std = @import("std");
const game = @import("game.zig");
const bake = @import("core/bake.zig");
const wf = @import("world/worldfmt.zig");
const env = @import("world/env.zig");
const shots = @import("shots.zig");

pub fn main() void {
    const alloc = std.heap.c_allocator;
    const argv = std.process.argsAlloc(alloc) catch {
        game.run(.play);
        return;
    };
    defer std.process.argsFree(alloc, argv);

    if (argv.len >= 2 and std.mem.eql(u8, argv[1], "--bake")) {
        runBake(alloc) catch |e| {
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

fn runBake(alloc: std.mem.Allocator) !void {
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
    e.heightField = m.height;
    e.heightHalf = m.half;
    e.heightAny = m.anyHeight();
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
    _ = @import("play/combat.zig");
    _ = @import("play/stats.zig");
    _ = @import("play/item.zig");
    _ = @import("play/liquid.zig");
    _ = @import("foes/fungalduo.zig");
    _ = @import("foes/owlbear.zig");
    _ = @import("core/collision.zig");
    _ = @import("gfx/gfx.zig");
    _ = @import("world/daynight.zig");
    _ = @import("world/env.zig");
    _ = @import("props/props.zig");
    _ = @import("world/worldfmt.zig");
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
}
