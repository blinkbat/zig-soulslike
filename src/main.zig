const std = @import("std");
const game = @import("game.zig");
const bake = @import("core/bake.zig");
const wf = @import("world/worldfmt.zig");

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
    var i: usize = 1;
    while (i + 1 < argv.len) : (i += 1) {
        if (std.mem.eql(u8, argv[i], "--map")) {
            wf.setStartMap(argv[i + 1]);
            std.debug.print("MAP: {s}\n", .{argv[i + 1]});
            break;
        }
    }
    const mode: game.Mode = if (hasArg(argv, "--shot-props"))
        .props
    else if (hasArg(argv, "--shot-land"))
        .land
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

    const text = try std.fs.cwd().readFileAlloc(alloc, wf.START_MAP, 1 << 22);
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
    _ = @import("foes/ravager.zig");
    _ = @import("foes/shroommage.zig");
    _ = @import("foes/sporegolem.zig");
    _ = @import("foes/fenlurker.zig");
    _ = @import("foes/skitterer.zig");
    _ = @import("foes/ancientpriest.zig");
    _ = @import("foes/hollow.zig");
    _ = @import("foes/wolf.zig");
    _ = @import("play/pickup.zig");
    _ = @import("play/award.zig");
    _ = @import("foes/foe.zig");
    _ = @import("foes/behave.zig");
    _ = @import("gfx/elemfx.zig");
    _ = @import("play/combat.zig");
    _ = @import("play/stats.zig");
    _ = @import("play/item.zig");
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
    _ = @import("game.zig");
    _ = @import("core/bake.zig");
    _ = @import("play/chest.zig");
    _ = @import("play/rest.zig");
    _ = @import("play/drops.zig");
    _ = @import("world/weather.zig");
    _ = @import("play/souls.zig");
    _ = @import("play/passivetree.zig");
    _ = @import("core/rumble.zig");
    _ = @import("save.zig");
    _ = @import("ui/menu.zig");
    _ = @import("ui/objview.zig");
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
