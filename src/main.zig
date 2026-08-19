const std = @import("std");
const game = @import("game.zig");
const bake = @import("bake.zig");
const wf = @import("worldfmt.zig");

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
    _ = @import("hero.zig");
    _ = @import("anim.zig");
    _ = @import("camera.zig");
    _ = @import("mathx.zig");
    _ = @import("frog.zig");
    _ = @import("archer.zig");
    _ = @import("ogre.zig");
    _ = @import("kobold.zig");
    _ = @import("brood.zig");
    _ = @import("warrior.zig");
    _ = @import("shade.zig");
    _ = @import("leechfly.zig");
    _ = @import("rooted.zig");
    _ = @import("shroom.zig");
    _ = @import("knight.zig");
    _ = @import("delver.zig");
    _ = @import("necro.zig");
    _ = @import("ravager.zig");
    _ = @import("shroommage.zig");
    _ = @import("fenlurker.zig");
    _ = @import("wolf.zig");
    _ = @import("pickup.zig");
    _ = @import("award.zig");
    _ = @import("foe.zig");
    _ = @import("behave.zig");
    _ = @import("elemfx.zig");
    _ = @import("combat.zig");
    _ = @import("stats.zig");
    _ = @import("item.zig");
    _ = @import("collision.zig");
    _ = @import("gfx.zig");
    _ = @import("daynight.zig");
    _ = @import("env.zig");
    _ = @import("props.zig");
    _ = @import("worldfmt.zig");
    _ = @import("trigger.zig");
    _ = @import("dialog.zig");
    _ = @import("npc.zig");
    _ = @import("editor.zig");
    _ = @import("audio.zig");
    _ = @import("hud.zig");
    _ = @import("book.zig");
    _ = @import("game.zig");
    _ = @import("bake.zig");
    _ = @import("chest.zig");
    _ = @import("rest.zig");
    _ = @import("drops.zig");
    _ = @import("weather.zig");
    _ = @import("souls.zig");
    _ = @import("passivetree.zig");
    _ = @import("rumble.zig");
    _ = @import("save.zig");
    _ = @import("menu.zig");
    _ = @import("objview.zig");
    _ = @import("shots.zig");
    _ = @import("shaders.zig");
    _ = @import("ui.zig");
    _ = @import("uiart.zig");
    _ = @import("icons.zig");
    _ = @import("itemart.zig");
    _ = @import("propart.zig");
    _ = @import("propbuild.zig");
    _ = @import("propflora.zig");
    _ = @import("propfx.zig");
    _ = @import("proprock.zig");
    _ = @import("propruins.zig");
    _ = @import("propvillage.zig");
    _ = @import("propwood.zig");
}
