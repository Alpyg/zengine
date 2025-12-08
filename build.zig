const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const options = .{
        .target = target,
        .optimize = optimize,
    };

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
        .target = options.target,
        .optimize = options.optimize,
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

    buildExamples(b, options, mod);
}

pub const Examples = struct {
    pub const sandbox = @import("demos/sandbox/build.zig");
};

pub fn buildExamples(b: *std.Build, options: anytype, mod: anytype) void {
    inline for (comptime std.meta.declarations(Examples)) |d| {
        _ = buildExe(
            b,
            options,
            @field(Examples, d.name),
            mod,
        );
    }
}

fn buildExe(b: *std.Build, options: anytype, example: anytype, mod: anytype) *std.Build.Step.Compile {
    const exe = example.build(b, options, mod);

    const install_exe = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_exe.step);
    b.step(example.demo_name, "Build '" ++ example.demo_name ++ "' demo").dependOn(&install_exe.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(&install_exe.step);
    b.step(example.demo_name ++ "-run", "Run '" ++ example.demo_name ++ "' demo").dependOn(&run_cmd.step);

    return exe;
}
