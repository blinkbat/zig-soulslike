const std = @import("std");

// Consumer build for zig-soulslike: link the static raylib artifact built from C source
// by raylib-zig (Zig's bundled clang compiles it — no MSVC, no raylib.dll), and import
// the raylib + raygui Zig binding modules. Mirrors the zig-rts / zig-diablo wiring.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // X11, NOT WAYLAND, on Linux — and this is what makes a Linux build possible from a Windows box at
    // all. raylib's default there is `Both`, and Wayland means running `wayland-scanner` to generate
    // protocol glue, which is a LINUX HOST BINARY: cross-compiling panics with "`wayland-scanner` not
    // found" before it reaches a single line of this game's code. X11 needs no codegen step, and every
    // Wayland desktop ships XWayland, so an X11 binary runs on both.
    //
    // Windows and macOS ignore the option entirely, so it is set unconditionally rather than behind a
    // target test — one build that cross-compiles is worth more than a branch nobody exercises.
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
        .linux_display_backend = .X11,
    });
    const raylib = raylib_dep.module("raylib"); // Zig bindings
    const raygui = raylib_dep.module("raygui"); // GUI bindings (may be unused)
    const raylib_artifact = raylib_dep.artifact("raylib"); // static C library

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
    exe.root_module.addImport("raygui", raygui);
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
    unit_tests.root_module.addImport("raygui", raygui);
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
