const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zglfw_dep = b.dependency("zglfw", .{});
    const zgpu_dep = b.dependency("zgpu", .{});
    const zflecs_dep = b.dependency("zflecs", .{});
    const zgui_dep = b.dependency("zgui", .{
        .backend = .glfw_wgpu,
        .shared = false,
        .with_implot = true,
        .with_node_editor = true,
    });
    const zmath_dep = b.dependency("zmath", .{});
    const zpool_dep = b.dependency("zpool", .{});
    const zstbi_dep = b.dependency("zstbi", .{});
    const zmesh_dep = b.dependency("zmesh", .{});

    const mod = b.addModule("root", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zglfw", .module = zglfw_dep.module("root") },
            .{ .name = "zgpu", .module = zgpu_dep.module("root") },
            .{ .name = "zflecs", .module = zflecs_dep.module("root") },
            .{ .name = "zgui", .module = zgui_dep.module("root") },
            .{ .name = "zmath", .module = zmath_dep.module("root") },
            .{ .name = "zpool", .module = zpool_dep.module("root") },
            .{ .name = "zmesh", .module = zmesh_dep.module("root") },
            .{ .name = "zstbi", .module = zstbi_dep.module("root") },
        },
    });

    mod.linkLibrary(zglfw_dep.artifact("glfw"));
    mod.linkLibrary(zgpu_dep.artifact("zdawn"));
    mod.linkLibrary(zflecs_dep.artifact("flecs"));
    mod.linkLibrary(zgui_dep.artifact("imgui"));

    const unit_tests = b.addTest(.{
        .root_module = mod,
    });
    @import("zgpu").addLibraryPathsTo(unit_tests);
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
