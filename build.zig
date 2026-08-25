const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
        .linux_display_backend = .X11,
    });
    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    const exe = b.addExecutable(.{
        .name = "zig-soulslike",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    // **STARTUP BUILDS THE FOE GROUPS BY VALUE, AND THEY ARE BIG.** `game.init` and `objview.ensureChars` both
    // assign twenty-one `Group.init(shader)` results, one field at a time; a Debug frame reserves every
    // temporary up front, so the reserve has to clear the largest group's `sizeOf` many times over. It
    // overflowed the default at boot when a group grew from 24 bodies to `worldfmt.MAX_FOES`. Windows COMMITS
    // stack lazily, so this is address space and not memory. Raising `MAX_FOES` again means raising this.
    exe.stack_size = 192 * 1024 * 1024;
    exe.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);
    exe.root_module.addAnonymousImport("campfire_wav", .{ .root_source_file = b.path("assets/campfire.wav") });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Build and run zig-soulslike");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unit_tests.linkLibrary(raylib_artifact);
    unit_tests.root_module.addImport("raylib", raylib);
    unit_tests.root_module.addAnonymousImport("campfire_wav", .{ .root_source_file = b.path("assets/campfire.wav") });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    checkTestRoster(b);
    test_step.dependOn(&run_tests.step);
}

/// THE TEST ROSTER IS A LOCKSTEP LIST, AND NOTHING WAS CHECKING IT. `main.zig`'s `test { _ = @import(…) }`
/// block is what pulls a module's tests into the binary — a module missing from it compiles, ships and reports
/// "all tests passed" while every test it carries goes unrun. `shade.zig` went in with seventeen of them and
/// the suite total did not move; two were failing.
///
/// A comptime assert cannot see the filesystem, so the check lives HERE. Every `src/**/*.zig` must be named in
/// that block, by the path `main.zig` imports it as (`foes/knight.zig`).
///
/// **AND IT IS SCOPED TO THE BLOCK, NOT TO THE FILE.** Searching the whole of `main.zig` counted the ORDINARY
/// imports at the top of it, so `bake.zig` passed this check while a top-level import pulls no tests in.
fn checkTestRoster(b: *std.Build) void {
    const file = b.build_root.handle.readFileAlloc(b.allocator, "src/main.zig", 1 << 20) catch return;
    const at = std.mem.indexOf(u8, file, "\ntest {") orelse
        std.debug.panic("src/main.zig has no `test {{` block — the whole suite hangs off it", .{});
    const root = file[at..];
    var dir = b.build_root.handle.openDir("src", .{ .iterate = true }) catch return;
    defer dir.close();
    // WALKED, not iterated: `src` is in subdirectories now, and a flat `iterate` sees four files and passes every module in them silently unrun — the exact failure this check exists for.
    var it = dir.walk(b.allocator) catch return;
    defer it.deinit();
    while (it.next() catch null) |ent| {
        if (ent.kind != .file or !std.mem.endsWith(u8, ent.path, ".zig")) continue;
        if (std.mem.eql(u8, ent.path, "main.zig")) continue;
        // The roster names a module by the path `main.zig` imports it as, which on Windows comes back off the walker with backslashes.
        const slashed = b.allocator.dupe(u8, ent.path) catch return;
        std.mem.replaceScalar(u8, slashed, '\\', '/');
        const want = b.fmt("@import(\"{s}\")", .{slashed});
        if (std.mem.indexOf(u8, root, want) == null) {
            std.debug.panic(
                "src/main.zig's test block does not name {s} — every module carrying tests must be there, " ++
                    "or its tests are silently never compiled. Add `_ = {s};`.",
                .{ slashed, want },
            );
        }
    }
}
