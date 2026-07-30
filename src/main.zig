const std = @import("std");
const game = @import("game.zig");
const bake = @import("bake.zig");
const wf = @import("worldfmt.zig");

// Entry point. Default launches the game; `--shot` renders headless into shots/ for offline visual
// checks; `--bake` re-emits the first map from bake.zig and exits (a one-way door — see that file).
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

    try std.fs.cwd().makePath("worlds");
    var f = try std.fs.cwd().createFile("worlds/01_fallen_plain.world", .{});
    defer f.close();
    var buf = std.io.bufferedWriter(f.writer());
    try wf.write(m, buf.writer());
    try buf.flush();

    // Re-read what was just written: a bake that emits a file the loader rejects is worse than one
    // that fails, because the failure surfaces later as an empty world.
    const text = try std.fs.cwd().readFileAlloc(alloc, "worlds/01_fallen_plain.world", 1 << 22);
    defer alloc.free(text);
    const back = try alloc.create(wf.Map);
    defer alloc.destroy(back);
    var line: usize = 0;
    wf.parse(text, back, &line) catch |e| {
        std.debug.print("bake wrote a file it cannot read back: {s} at line {d}\n", .{ @errorName(e), line });
        return e;
    };
    std.debug.print(
        "baked worlds/01_fallen_plain.world — {d} ops, {d} zones, {d} clearings ({d} bytes)\n",
        .{ m.nops, m.nzones, m.nclearings, text.len },
    );
}

// EVERY module carrying tests must be named here — Zig only collects from files the test ROOT reaches,
// and this is the root. env.zig and props.zig hang off game.zig alone, so leaving them out silently
// dropped 12 tests, the culler sweep and the INFO table's checks among them.
test {
    _ = @import("hero.zig");
    _ = @import("camera.zig");
    _ = @import("mathx.zig");
    _ = @import("frog.zig");
    _ = @import("archer.zig");
    _ = @import("ogre.zig");
    _ = @import("foe.zig");
    _ = @import("combat.zig");
    _ = @import("collision.zig");
    _ = @import("env.zig");
    _ = @import("props.zig");
    _ = @import("worldfmt.zig");
    _ = @import("editor.zig"); // hangs off game.zig, which this root does not reach for tests
    _ = @import("audio.zig"); // …likewise: the sound bank's synthesis tests need no device
}
