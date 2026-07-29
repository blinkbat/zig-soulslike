const std = @import("std");
const game = @import("game.zig");

// Entry point. Default launches the game; `--shot` renders headless (window hidden) and
// writes walk-cycle PNGs to shots/ for offline visual checks.
pub fn main() void {
    const alloc = std.heap.c_allocator;
    const argv = std.process.argsAlloc(alloc) catch {
        game.run(false);
        return;
    };
    defer std.process.argsFree(alloc, argv);

    const shot = argv.len >= 2 and std.mem.eql(u8, argv[1], "--shot");
    game.run(shot);
}

// EVERY module carrying tests must be named here. Zig only collects tests from files the test
// ROOT reaches, and this is the root: env.zig and props.zig hang off game.zig alone, so leaving
// them out silently dropped 12 tests — including the culler sweep that exists because "a culler
// bug looks like an EMPTY WORLD" and the INFO table's index/collider checks.
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
}
