const std = @import("std");

// Consumer build for zig-soulslike: link the static raylib artifact built from C source
// by raylib-zig (Zig's bundled clang compiles it — no MSVC, no raylib.dll), and import
// the raylib + raygui Zig binding modules. Mirrors the zig-rts / zig-diablo wiring.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
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
