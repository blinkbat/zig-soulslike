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

test {
    _ = @import("hero.zig");
    _ = @import("camera.zig");
    _ = @import("mathx.zig");
}
