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
    // assign every `game.FOE_GROUPS` row's `Group.init(shader)` result, one field at a time; a Debug frame reserves every
    // temporary up front, so the reserve has to clear the largest group's `sizeOf` many times over. It
    // overflowed the default at boot when a group grew from 24 bodies to `worldfmt.MAX_FOES`. Windows COMMITS
    // stack lazily, so this is address space and not memory. **THE ROW COUNT MOVES IT TOO** — `game.zig`'s
    // "WHAT THE FRAME COSTS" measures 144.4 MB of slabs across 29 rows against this 192 MB, so a handful more
    // creatures wants this raised as surely as another `MAX_FOES` does.
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

    // DEV ONLY: `zig build test -Dtest-filter=knight` runs the tests whose name contains that, and skips the
    // rest — `shots.onlyStage`'s lever for the suite. The whole run is 1130 tests and a chunk of them rebuild
    // the entire shipped world or bake eighty synthesized voices, so an edit loop on one module was paying for
    // all of it. The roster check still walks the tree, so a filtered run cannot hide a module from it.
    const test_filter = b.option([]const u8, "test-filter", "Run only tests whose name contains this");
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = if (test_filter) |f| &.{f} else &.{},
    });
    unit_tests.linkLibrary(raylib_artifact);
    unit_tests.root_module.addImport("raylib", raylib);
    unit_tests.root_module.addAnonymousImport("campfire_wav", .{ .root_source_file = b.path("assets/campfire.wav") });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    checkTestRoster(b);
    test_step.dependOn(&run_tests.step);

    // DEV ONLY: `zig build check` type-checks and stops. `Step.Compile` passes `-fno-emit-bin` whenever
    // nothing asks for its binary, so no step here may install or run these two. Measured on this tree:
    // 1.4 s against 8.4 s, because sema is 1.4 s of a build and LLVM plus LLD are the other 7. The exe and
    // the test root are separate compilations — a `test { }` block's errors only surface in the second.
    const check_exe = b.addExecutable(.{
        .name = "check-exe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const check_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const check_step = b.step("check", "Type-check only — no codegen, no link, no binary");
    for ([_]*std.Build.Step.Compile{ check_exe, check_tests }) |c| {
        c.linkLibrary(raylib_artifact);
        c.root_module.addImport("raylib", raylib);
        c.root_module.addAnonymousImport("campfire_wav", .{ .root_source_file = b.path("assets/campfire.wav") });
        check_step.dependOn(&c.step);
    }
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
/// Bytes under which a `src/**/*.zig` is a truncation rather than a module — the smallest real one is
/// `play/liquid.zig` at 4293.
const MIN_SRC: u64 = 512;

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
        // **AND A MODULE NAMED BUT EMPTIED IS THE SAME FAILURE WITH NOTHING LEFT TO RUN.** `ui/editor.zig` was
        // truncated to 0 bytes and committed that way (c08f4f7): the roster still named it, this walk passed,
        // and the only complaint was `game.zig` asking a now-empty struct for `Editor`. The smallest real module
        // in the tree is 4.2 KB, so anything under `MIN_SRC` is a truncation and never something anyone wrote.
        const st = ent.dir.statFile(ent.basename) catch continue;
        if (st.size < MIN_SRC) std.debug.panic(
            "src/{s} is {d} bytes — that is a truncated file, not a module. Restore it " ++
                "(`git log --oneline -- src/{s}`, then `git show <rev>:src/{s}`) instead of building over it.",
            .{ slashed, st.size, slashed, slashed },
        );
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
