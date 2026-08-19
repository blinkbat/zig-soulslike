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
/// block is what pulls a module's tests into the binary — a module missing from it compiles, ships and
/// reports "all tests passed" while every test it carries goes unrun. `shade.zig` went in with seventeen of
/// them and the suite total did not move; two were failing.
///
/// A comptime assert cannot see the filesystem, so the check lives HERE, where the build runs on the host
/// and can simply read the directory. Every `src/*.zig` must be named in that block or the build fails with
/// the name of the one that is not.
///
/// **AND IT IS SCOPED TO THE BLOCK, NOT TO THE FILE.** Searching the whole of `main.zig` counted the
/// ORDINARY imports at the top of it, so `bake.zig` — imported there for `--bake` — passed this check while
/// a top-level import pulls no tests in: a failing test planted in it ran nowhere and the suite said OK.
fn checkTestRoster(b: *std.Build) void {
    const file = b.build_root.handle.readFileAlloc(b.allocator, "src/main.zig", 1 << 20) catch return;
    const at = std.mem.indexOf(u8, file, "\ntest {") orelse
        std.debug.panic("src/main.zig has no `test {{` block — the whole suite hangs off it", .{});
    const root = file[at..];
    var dir = b.build_root.handle.openDir("src", .{ .iterate = true }) catch return;
    defer dir.close();
    var it = dir.iterate();
    while (it.next() catch null) |ent| {
        if (ent.kind != .file or !std.mem.endsWith(u8, ent.name, ".zig")) continue;
        if (std.mem.eql(u8, ent.name, "main.zig")) continue;
        const want = b.fmt("@import(\"{s}\")", .{ent.name});
        if (std.mem.indexOf(u8, root, want) == null) {
            std.debug.panic(
                "src/main.zig's test block does not name {s} — every module carrying tests must be there, " ++
                    "or its tests are silently never compiled. Add `_ = {s};`.",
                .{ ent.name, want },
            );
        }
    }
}
