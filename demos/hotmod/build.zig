const std = @import("std");

pub const demo_name = "hotmod";

pub fn build(
    b: *std.Build,
    options: anytype,
    mod: anytype,
    deps: anytype,
) *std.Build.Step.Compile {
    const src = b.pathJoin(&.{ "demos", demo_name, "src" });

    // Hot-reloadable module. The host watches this shared object.
    const module_mod = b.createModule(.{
        .root_source_file = b.path(b.pathJoin(&.{ src, "mod.zig" })),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "z", .module = mod },
        },
    });
    const module_lib = b.addLibrary(.{
        .name = "hotmod",
        .linkage = .dynamic,
        .root_module = module_mod,
    });
    module_lib.root_module.linkSystemLibrary("sdl3", .{});
    module_lib.root_module.linkLibrary(deps.flecs);

    const install_module = b.addInstallArtifact(module_lib, .{});
    b.getInstallStep().dependOn(&install_module.step);
    b.step(demo_name ++ "-module", "Build only the hot-reloadable module")
        .dependOn(&install_module.step);

    // The host loads modules through the shared runtime loader.
    const exe = b.addExecutable(.{
        .name = demo_name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.pathJoin(&.{ src, "host.zig" })),
            .target = options.target,
            .optimize = options.optimize,
            .strip = false,
            .imports = &.{
                .{ .name = "z", .module = mod },
                .{ .name = "hot", .module = deps.hot },
            },
        }),
    });

    // The host cannot run until the module exists on disk.
    exe.step.dependOn(&install_module.step);

    return exe;
}
