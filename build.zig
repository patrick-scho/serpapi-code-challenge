const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // common exe options for exe and check steps
    const exe_options = std.Build.ExecutableOptions{
        .name = "main",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    };

    // executable step
    const exe = b.addExecutable(exe_options);
    exe.use_llvm = true;
    b.installArtifact(exe);

    // run step
    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run application");
    run_step.dependOn(&run_exe.step);

    // test step
    const test_step = b.step("test", "Run unit tests");
    const unit_test = b.addTest(.{
        .root_module = exe_options.root_module,
    });
    unit_test.use_llvm = true;
    b.installArtifact(unit_test);
    const run_unit_test = b.addRunArtifact(unit_test);
    test_step.dependOn(&run_unit_test.step);

    // check step for LSP
    const exe_check = b.addExecutable(exe_options);
    const check_step = b.step("check", "Check if foo compiles");
    check_step.dependOn(&exe_check.step);
}
