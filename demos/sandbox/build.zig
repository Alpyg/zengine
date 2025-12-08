const std = @import("std");

pub const demo_name = "sandbox";

pub fn build(b: *std.Build, options: anytype, mod: anytype) *std.Build.Step.Compile {
    const cwd_path = b.pathJoin(&.{ "demos", demo_name });
    const src_path = b.pathJoin(&.{ cwd_path, "src" });
    const exe = b.addExecutable(.{
        .name = "sandbox",
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.pathJoin(&.{ src_path, demo_name ++ ".zig" })),
            .target = options.target,
            .optimize = options.optimize,
            .imports = &.{
                .{ .name = "z", .module = mod },
            },
        }),
    });

    return exe;
}
