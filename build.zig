const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zengine", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "zengine",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "z", .module = mod },
            },
        }),
    });
    b.installArtifact(exe);

    const zglfw_dep = b.dependency("zglfw", .{});
    mod.addImport("zglfw", zglfw_dep.module("root"));
    mod.linkLibrary(zglfw_dep.artifact("glfw"));

    @import("zgpu").addLibraryPathsTo(exe);

    const zgpu_dep = b.dependency("zgpu", .{});
    mod.addImport("zgpu", zgpu_dep.module("root"));
    mod.linkLibrary(zgpu_dep.artifact("zdawn"));

    const zgui_dep = b.dependency("zgui", .{
        .backend = .glfw_wgpu,
        .shared = false,
        .with_implot = true,
        .with_node_editor = true,
    });
    mod.addImport("zgui", zgui_dep.module("root"));
    mod.linkLibrary(zgui_dep.artifact("imgui"));

    const zmath_dep = b.dependency("zmath", .{});
    mod.addImport("zmath", zmath_dep.module("root"));

    const zpool_dep = b.dependency("zpool", .{});
    mod.addImport("zpool", zpool_dep.module("root"));

    const zflecs_dep = b.dependency("zflecs", .{});
    mod.addImport("zflecs", zflecs_dep.module("root"));
    mod.linkLibrary(zflecs_dep.artifact("flecs"));

    const zmesh_dep = b.dependency("zmesh", .{});
    mod.addImport("zmesh", zmesh_dep.module("root"));

    const zstbi_dep = b.dependency("zstbi", .{});
    mod.addImport("zstbi", zstbi_dep.module("root"));

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = mod,
    });
    @import("zgpu").addLibraryPathsTo(unit_tests);
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
