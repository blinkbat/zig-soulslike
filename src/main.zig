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
    const mode: game.Mode = if (argv.len >= 2 and std.mem.eql(u8, argv[1], "--shot-props"))
        .props
    else if (argv.len >= 2 and std.mem.eql(u8, argv[1], "--shot"))
        .shots
    else
        .play;
    game.run(mode);
}

fn runBake(alloc: std.mem.Allocator) !void {
    const m = try alloc.create(wf.Map); // ~600 KB of flat arrays: too big for the stack
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

// EVERY module in `src/` is named here, and `build.zig`'s `checkTestRoster` FAILS THE BUILD if one is not.
// A module missing from this block compiles, ships, and reports "all tests passed" while every test it
// carries goes unrun — `shade.zig` went in with seventeen of them and the suite total did not move. Naming a
// module that would have been pulled in anyway costs nothing; leaving one out costs the whole file.
test {
    _ = @import("hero.zig");
    _ = @import("camera.zig");
    _ = @import("mathx.zig");
    _ = @import("frog.zig");
    _ = @import("archer.zig");
    _ = @import("ogre.zig");
    _ = @import("kobold.zig");
    _ = @import("brood.zig");
    _ = @import("warrior.zig");
    _ = @import("shade.zig");
    _ = @import("leechfly.zig"); // THE FIRST FLYER — its height is the whole creature, so the tests are about that
    _ = @import("rooted.zig"); // THE TREE THAT ISN`T — a fixture, so the tests are about its rings
    _ = @import("shroom.zig"); // THE SPORELING — the trip's roll and the cloud's metronome
    _ = @import("foe.zig");
    _ = @import("combat.zig");
    _ = @import("stats.zig");
    _ = @import("item.zig");
    _ = @import("collision.zig");
    _ = @import("gfx.zig"); // the mesh `Builder` is pure CPU, and addRoundBox has invariants worth pinning
    _ = @import("env.zig");
    _ = @import("props.zig");
    _ = @import("worldfmt.zig");
    _ = @import("trigger.zig"); // THE TRIGGER MACHINE — conditions, actions, switches, counters, timers
    _ = @import("dialog.zig");
    _ = @import("npc.zig");
    _ = @import("editor.zig"); // hangs off game.zig, which this root does not reach for tests
    _ = @import("audio.zig");
    _ = @import("hud.zig"); // the word wrap the character book's descriptions are laid out with
    _ = @import("book.zig");
    // …AND game.zig ITSELF, which this list said was unreachable and then never named.
    _ = @import("game.zig");
    _ = @import("chest.zig");
    _ = @import("rest.zig");
    _ = @import("rumble.zig");
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
