const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const options = .{
        .target = target,
        .optimize = optimize,
    };

    const zsdl_dep = b.dependency("zsdl", .{});
    const zgpu_dep = b.dependency("zgpu", .{});
    const zflecs_dep = b.dependency("zflecs", .{});
    const zgui_dep = b.dependency("zgui", .{
        .backend = .sdl3_gpu,
        .shared = false,
        .with_implot = true,
        .with_node_editor = true,
    });
    const zmath_dep = b.dependency("zmath", .{});
    const zpool_dep = b.dependency("zpool", .{});
    const zstbi_dep = b.dependency("zstbi", .{});
    const zmesh_dep = b.dependency("zmesh", .{});

    // Directory holding the `.slang` shaders. Each file is compiled to SPIR-V
    // at build time and exposed as a field on the generated `shaders` module.
    const shaders_path = b.option(
        []const u8,
        "shaders_path",
        "Directory containing .slang shader sources",
    ) orelse "src/shaders";

    const shaders_mod = buildShaders(b, shaders_path, options);

    const mod = b.addModule("root", .{
        .root_source_file = b.path("src/root.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .strip = false,
        .imports = &.{
            .{ .name = "zsdl", .module = zsdl_dep.module("zsdl3") },
            .{ .name = "zgpu", .module = zgpu_dep.module("root") },
            .{ .name = "zflecs", .module = zflecs_dep.module("root") },
            .{ .name = "zgui", .module = zgui_dep.module("root") },
            .{ .name = "zmath", .module = zmath_dep.module("root") },
            .{ .name = "zpool", .module = zpool_dep.module("root") },
            .{ .name = "zmesh", .module = zmesh_dep.module("root") },
            .{ .name = "zstbi", .module = zstbi_dep.module("root") },
            .{ .name = "shaders", .module = shaders_mod },
        },
    });
    mod.linkSystemLibrary("sdl3", .{});
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
    const examples = @typeInfo(Examples).@"struct".decl_names;
    inline for (examples) |example| {
        _ = buildExe(b, @field(Examples, example), options, mod);
    }
}

fn buildExe(b: *std.Build, example: anytype, options: anytype, mod: anytype) *std.Build.Step.Compile {
    const exe = example.build(b, options, mod);

    const install_exe = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_exe.step);
    b.step(example.demo_name, "Build '" ++ example.demo_name ++ "' demo").dependOn(&install_exe.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(&install_exe.step);
    b.step(example.demo_name ++ "-run", "Run '" ++ example.demo_name ++ "' demo").dependOn(&run_cmd.step);

    return exe;
}

/// Compiles every `.slang` file in `shaders_path` to SPIR-V and returns a
/// module exposing each one as `pub const <file_stem> = @embedFile(...)`.
fn buildShaders(b: *std.Build, shaders_path: []const u8, options: anytype) *std.Build.Module {
    const zslang_dep = b.dependency("zslang", .{
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    });

    const compiler = b.addExecutable(.{
        .name = "zslang-shaderc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/shader_compiler.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "slang", .module = zslang_dep.module("slang") },
            },
        }),
    });

    var dir = std.Io.Dir.cwd().openDir(b.graph.io, shaders_path, .{ .iterate = true }) catch |err| {
        std.debug.panic("failed to open shader directory '{s}': {s}", .{ shaders_path, @errorName(err) });
    };
    defer dir.close(b.graph.io);

    var names: std.ArrayList([]const u8) = .empty;
    var it = dir.iterate();
    while (it.next(b.graph.io) catch |err| {
        std.debug.panic("failed to list shader directory '{s}': {s}", .{ shaders_path, @errorName(err) });
    }) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".slang")) {
            names.append(b.allocator, b.dupe(entry.name)) catch @panic("oom");
        }
    }

    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lessThan);

    const files = b.addWriteFiles();
    var generated: std.ArrayList(u8) = .empty;

    for (names.items) |name| {
        const stem = name[0 .. name.len - ".slang".len];
        if (!std.zig.isValidId(stem)) {
            std.debug.panic("shader file '{s}' must have a valid Zig identifier stem", .{name});
        }

        const run = b.addRunArtifact(compiler);
        run.addFileArg(b.path(b.pathJoin(&.{ shaders_path, name })));
        const spv = run.addOutputFileArg(b.fmt("{s}.spv", .{stem}));
        const meta = run.addOutputFileArg(b.fmt("{s}.meta.zig", .{stem}));
        _ = files.addCopyFile(spv, b.fmt("{s}.spv", .{stem}));
        _ = files.addCopyFile(meta, b.fmt("{s}.meta.zig", .{stem}));

        generated.appendSlice(b.allocator, b.fmt("pub const {s} = @import(\"{s}.meta.zig\");\n", .{ stem, stem })) catch
            @panic("oom");
    }

    const shaders_zig = files.add("shaders.zig", generated.items);

    return b.addModule("shaders", .{
        .root_source_file = shaders_zig,
        .target = options.target,
        .optimize = options.optimize,
    });
}
