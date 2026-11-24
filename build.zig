const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const options = .{
        .target = target,
        .optimize = optimize,
    };

    const zsdl_dep = b.dependency("zsdl", options);
    const zflecs_dep = b.dependency("zflecs", options);
    const zgui_dep = b.dependency("zgui", .{
        .target = options.target,
        .optimize = options.optimize,
        .backend = .sdl3_gpu,
        .shared = false,
        .with_implot = true,
        .with_node_editor = true,
    });
    const zmath_dep = b.dependency("zmath", options);
    const zpool_dep = b.dependency("zpool", options);
    const zstbi_dep = b.dependency("zstbi", options);

    const flecs = zflecs_dep.artifact("flecs");
    const imgui = zgui_dep.artifact("imgui");
    if (options.target.result.abi == .android) {
        const libc_file = androidLibCFile(b);
        flecs.setLibCFile(libc_file);
        flecs.root_module.pic = true;
        imgui.setLibCFile(libc_file);
        imgui.root_module.pic = true;
    }
    b.getInstallStep().dependOn(&b.addInstallArtifact(flecs, .{}).step);
    b.getInstallStep().dependOn(&b.addInstallArtifact(imgui, .{}).step);

    const shaders_path = b.option(
        []const u8,
        "shaders_path",
        "Directory containing zengine's .slang shader sources",
    ) orelse "src/shaders";

    const shader_compiler = buildShaderCompiler(b);
    const shaders_mod = compileShaders(b, shader_compiler, shaders_path, options.target, options.optimize, "shaders");

    var root_imports: std.ArrayList(std.Build.Module.Import) = .empty;
    root_imports.append(b.allocator, .{ .name = "zsdl", .module = zsdl_dep.module("zsdl3") }) catch @panic("oom");
    root_imports.append(b.allocator, .{ .name = "zflecs", .module = zflecs_dep.module("root") }) catch @panic("oom");
    root_imports.append(b.allocator, .{ .name = "zgui", .module = zgui_dep.module("root") }) catch @panic("oom");
    root_imports.append(b.allocator, .{ .name = "zmath", .module = zmath_dep.module("root") }) catch @panic("oom");
    root_imports.append(b.allocator, .{ .name = "zpool", .module = zpool_dep.module("root") }) catch @panic("oom");
    root_imports.append(b.allocator, .{ .name = "zstbi", .module = zstbi_dep.module("root") }) catch @panic("oom");
    root_imports.append(b.allocator, .{ .name = "shaders", .module = shaders_mod }) catch @panic("oom");

    const mod = b.addModule("root", .{
        .root_source_file = b.path("src/root.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .strip = false,
        .imports = root_imports.items,
    });
    const hot_mod = b.addModule("hot", .{
        .root_source_file = b.path("src/hot/loader.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "z", .module = mod },
        },
    });

    const engine_deps = .{
        .flecs = flecs,
        .imgui = imgui,
        .hot = hot_mod,
    };

    const test_mod = b.addModule("root_test", .{
        .root_source_file = b.path("src/root.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .strip = false,
        .imports = root_imports.items,
    });

    const unit_tests = b.addTest(.{
        .root_module = test_mod,
    });
    linkEngineDeps(unit_tests, engine_deps);
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/root.zig"),
            .target = options.target,
            .optimize = options.optimize,
            .imports = &.{
                .{ .name = "z", .module = mod },
            },
        }),
    });
    linkEngineDeps(integration_tests, engine_deps);
    const run_integration_tests = b.addRunArtifact(integration_tests);

    const test_step = b.step("test", "Run unit and integration tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_integration_tests.step);

    buildExamples(b, options, mod, engine_deps);
}

fn linkEngineDeps(step: *std.Build.Step.Compile, deps: anytype) void {
    step.root_module.linkSystemLibrary("sdl3", .{});
    step.root_module.linkLibrary(deps.flecs);
    step.root_module.linkLibrary(deps.imgui);
}

fn androidLibCFile(b: *std.Build) std.Build.LazyPath {
    const ndk = b.graph.environ_map.get("ANDROID_NDK_ROOT") orelse
        @panic("ANDROID_NDK_ROOT is not set; build Android targets inside the devenv shell");
    const sysroot = b.pathJoin(&.{
        ndk,
        "toolchains/llvm/prebuilt/linux-x86_64/sysroot",
    });
    const libdir = b.pathJoin(&.{ sysroot, "usr/lib/aarch64-linux-android/26" });
    return b.addWriteFiles().add("zengine-android-libc.txt", b.fmt(
        "include_dir={s}/usr/include\n" ++
            "sys_include_dir={s}/usr/include/aarch64-linux-android\n" ++
            "cc_dir={s}\n" ++
            "crt_dir={s}\n" ++
            "msvc_lib_dir=\n" ++
            "kernel32_lib_dir=\n" ++
            "darwin_sdk_dir=\n",
        .{ sysroot, sysroot, libdir, libdir },
    ));
}

pub const Examples = struct {
    pub const sandbox = @import("demos/sandbox/build.zig");
    pub const hotmod = @import("demos/hotmod/build.zig");
};

pub fn buildExamples(b: *std.Build, options: anytype, mod: anytype, deps: anytype) void {
    const examples = @typeInfo(Examples).@"struct".decl_names;
    inline for (examples) |example| {
        _ = buildExe(b, @field(Examples, example), options, mod, deps);
    }
}

fn buildExe(
    b: *std.Build,
    example: anytype,
    options: anytype,
    mod: anytype,
    deps: anytype,
) *std.Build.Step.Compile {
    const exe = example.build(b, options, mod, deps);
    linkEngineDeps(exe, deps);

    const install_exe = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_exe.step);
    b.step(example.demo_name, "Build '" ++ example.demo_name ++ "' demo").dependOn(&install_exe.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(&install_exe.step);
    b.step(example.demo_name ++ "-run", "Run '" ++ example.demo_name ++ "' demo").dependOn(&run_cmd.step);

    return exe;
}

fn buildShaderCompiler(b: *std.Build) *std.Build.Step.Compile {
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
    b.getInstallStep().dependOn(&b.addInstallArtifact(compiler, .{}).step);
    return compiler;
}

/// Compiles every `.slang` file in `shaders_path` into a module named
/// `module_name`, resolved relative to the build passed in.
fn compileShaders(
    b: *std.Build,
    compiler: *std.Build.Step.Compile,
    shaders_path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Optimize,
    comptime module_name: []const u8,
) *std.Build.Module {
    var dir = b.root.openDir(b.graph.io, shaders_path, .{ .iterate = true }) catch |err| {
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

    const shaders_zig = files.add(b.fmt("{s}.zig", .{module_name}), generated.items);

    return b.addModule(module_name, .{
        .root_source_file = shaders_zig,
        .target = target,
        .optimize = optimize,
    });
}

/// Public build helper for consuming apps.
///
/// Call it from the app's `build.zig`:
///
/// ```zig
/// const zengine_build = @import("zengine");
/// const shaders = zengine_build.buildShaders(b, engine, "src/shaders", target, optimize);
/// ```
///
/// `engine` is the `b.dependency("zengine", ...)` value. The returned module
/// contains one declaration per `.slang` file in `shaders_path`, resolved
/// relative to the app's build root.
pub fn buildShaders(
    b: *std.Build,
    engine: *std.Build.Dependency,
    shaders_path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Optimize,
) *std.Build.Module {
    const compiler = engine.artifact("zslang-shaderc");
    return compileShaders(b, compiler, shaders_path, target, optimize, "app_shaders");
}
