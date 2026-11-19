//! Build-time Slang -> SPIR-V compiler with reflection.
//!
//! Usage: zslang-shaderc <input.slang> <output.spv> <output.meta.zig>
//!
//! Compiles a single Slang module (all `[shader(...)]` entry points) into one
//! SPIR-V blob and emits a Zig metadata struct describing the entry points,
//! resource counts, bindings and uniform block layout.

const std = @import("std");

const slang = @import("slang");

const max_source_bytes = 1 << 20;

const StageInfo = struct {
    num_uniform_buffers: u32 = 0,
    num_textures: u32 = 0,
    num_samplers: u32 = 0,
    num_storage_buffers: u32 = 0,
    num_storage_textures: u32 = 0,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var args = try init.minimal.args.iterateAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // program name
    const input_path = args.next() orelse return usage();
    const spv_path = args.next() orelse return usage();
    const meta_path = args.next() orelse return usage();

    const source = try std.Io.Dir.cwd().readFileAllocOptions(
        init.io,
        input_path,
        allocator,
        .limited(max_source_bytes),
        .of(u8),
        0,
    );
    defer allocator.free(source);

    const global = try slang.GlobalSession.create();
    defer global.deinit();

    var diag: slang.Diagnostics = .{};
    defer diag.deinit();

    const program = slang.util.compileAndLinkProgram(
        allocator,
        global,
        .{
            .source = source,
            .module_name = "shader",
            .path = input_path,
            .format = .spirv,
            // Must match how `DrawMaterial` uploads `object_to_clip`.
            .matrix_layout = .row_major,
        },
        &diag,
    ) catch |err| {
        std.debug.print("shader compilation failed ({s}):\n{s}\n", .{ @errorName(err), diag.text() });
        return err;
    };
    defer program.deinit();

    const code = program.getTargetCode(&diag) catch |err| {
        std.debug.print("target code generation failed ({s}):\n{s}\n", .{ @errorName(err), diag.text() });
        return err;
    };
    defer code.deinit();

    const layout = program.getLayout(&diag) catch |err| {
        std.debug.print("reflection failed ({s}):\n{s}\n", .{ @errorName(err), diag.text() });
        return err;
    };

    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = spv_path,
        .data = code.bytes(),
    });

    var vertex_info: ?StageInfo = null;
    var fragment_info: ?StageInfo = null;
    var vertex_ep: ?slang.EntryPoint = null;

    var i: u32 = 0;
    while (i < layout.entryPointCount()) : (i += 1) {
        const ep = layout.entryPointByIndex(i) orelse continue;
        switch (ep.stage()) {
            .vertex => {
                vertex_info = stageInfo(layout);
                vertex_ep = ep;
            },
            .fragment => fragment_info = stageInfo(layout),
            else => {},
        }
    }

    const vertex = vertex_info orelse {
        std.debug.print("shader has no vertex entry point\n", .{});
        return error.MissingEntryPoint;
    };
    const fragment = fragment_info orelse {
        std.debug.print("shader has no fragment entry point\n", .{});
        return error.MissingEntryPoint;
    };

    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const w = &out.writer;

    const spv_name = std.fs.path.basename(spv_path);
    try w.writeAll("pub const spv = @embedFile(");
    try w.printStringEscaped(spv_name);
    try w.writeAll(");\n\n");

    try writeStage(w, "vertex", vertex);
    try writeStage(w, "fragment", fragment);

    if (vertex_ep) |ep| {
        try writeVertexInputs(w, ep);
    } else {
        try w.writeAll("pub const vertex_stride = 0;\npub const vertex_inputs = .{};\n\n");
    }

    if (findUniformBlock(layout)) |block| {
        try writeUniformBlock(w, block);
    } else {
        try w.writeAll("pub const uniform_block = .{ .name = \"\", .size = 0, .fields = .{} };\n\n");
    }

    try writeBindings(w, layout);

    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = meta_path,
        .data = out.written(),
    });
}

/// Slang reflection does not attribute global resources to a stage, so every
/// global resource is reported for both stages. This is conservative: SDL gets
/// the correct descriptor counts, including unused slots.
fn stageInfo(layout: slang.ProgramLayout) StageInfo {
    var info = StageInfo{};

    var i: u32 = 0;
    while (i < layout.parameterCount()) : (i += 1) {
        const p = layout.parameterByIndex(i) orelse continue;
        const tl = p.typeLayout() orelse continue;

        if (tl.kind() == .constant_buffer) {
            info.num_uniform_buffers += 1;
            continue;
        }

        switch (p.category()) {
            .shader_resource => info.num_textures += 1,
            .sampler_state => info.num_samplers += 1,
            .unordered_access => {
                if (tl.kind() == .shader_storage_buffer) {
                    info.num_storage_buffers += 1;
                } else {
                    info.num_storage_textures += 1;
                }
            },
            else => {},
        }
    }

    return info;
}

fn findUniformBlock(layout: slang.ProgramLayout) ?slang.VariableLayout {
    var i: u32 = 0;
    while (i < layout.parameterCount()) : (i += 1) {
        const p = layout.parameterByIndex(i) orelse continue;
        const tl = p.typeLayout() orelse continue;
        if (tl.kind() == .constant_buffer) return p;
    }
    return null;
}

fn writeStage(w: *std.Io.Writer, name: []const u8, info: StageInfo) !void {
    try w.print("pub const {s} = .{{\n    .num_uniform_buffers = {d},\n    .num_textures = {d},\n    .num_samplers = {d},\n" ++
        "    .num_storage_buffers = {d},\n    .num_storage_textures = {d},\n}};\n\n", .{
        name,
        info.num_uniform_buffers,
        info.num_textures,
        info.num_samplers,
        info.num_storage_buffers,
        info.num_storage_textures,
    });
}

fn writeUniformBlock(w: *std.Io.Writer, block: slang.VariableLayout) !void {
    const tl = block.typeLayout() orelse return;
    const elem = tl.elementTypeLayout() orelse tl;

    try w.writeAll("pub const uniform_block = .{\n    .name = ");
    try w.printStringEscaped(elem.name());
    try w.print(",\n    .size = {d},\n    .fields = .{{\n", .{elem.size(.uniform)});

    var i: u32 = 0;
    while (i < elem.fieldCount()) : (i += 1) {
        const field = elem.fieldByIndex(i) orelse continue;
        const ft = field.typeLayout() orelse continue;

        try w.writeAll("        .{ .name = ");
        try w.printStringEscaped(field.name());
        try w.print(
            ", .offset = {d}, .size = {d}, .kind = ",
            .{ field.offset(.uniform), ft.size(.uniform) },
        );
        try w.printStringEscaped(kindName(ft.kind()));
        try w.writeAll(", .scalar = ");
        try w.printStringEscaped(scalarName(ft.scalarType()));
        try w.print(
            ", .rows = {d}, .columns = {d}, .elements = {d} }},\n",
            .{ ft.rowCount(), ft.columnCount(), ft.elementCount() },
        );
    }

    try w.writeAll("    },\n};\n\n");
}

fn writeBindings(w: *std.Io.Writer, layout: slang.ProgramLayout) !void {
    try w.writeAll("pub const bindings = .{\n");

    var i: u32 = 0;
    while (i < layout.parameterCount()) : (i += 1) {
        const p = layout.parameterByIndex(i) orelse continue;
        const tl = p.typeLayout() orelse continue;

        const category = if (tl.kind() == .constant_buffer)
            "constant_buffer"
        else switch (p.category()) {
            .shader_resource => "shader_resource",
            .sampler_state => "sampler_state",
            .unordered_access => "unordered_access",
            .push_constant_buffer => "push_constant_buffer",
            else => continue,
        };

        const size = if (tl.kind() == .constant_buffer)
            (tl.elementTypeLayout() orelse tl).size(.uniform)
        else
            tl.size(p.category());

        try w.writeAll("    .{ .name = ");
        try w.printStringEscaped(p.name());
        try w.writeAll(", .category = ");
        try w.printStringEscaped(category);
        try w.print(
            ", .set = {d}, .binding = {d}, .size = {d} }},\n",
            .{ p.bindingSpace(), p.bindingIndex(), size },
        );
    }

    try w.writeAll("};\n");
}

fn kindName(k: slang.TypeKind) []const u8 {
    return switch (k) {
        .structure => "structure",
        .array => "array",
        .matrix => "matrix",
        .vector => "vector",
        .scalar => "scalar",
        .constant_buffer => "constant_buffer",
        .resource => "resource",
        .sampler_state => "sampler_state",
        .texture_buffer => "texture_buffer",
        .shader_storage_buffer => "shader_storage_buffer",
        .parameter_block => "parameter_block",
        else => "other",
    };
}

fn scalarName(s: slang.ScalarType) []const u8 {
    return switch (s) {
        .bool => "bool",
        .int32 => "int32",
        .uint32 => "uint32",
        .int64 => "int64",
        .uint64 => "uint64",
        .float16 => "float16",
        .float32 => "float32",
        .float64 => "float64",
        .int8 => "int8",
        .uint8 => "uint8",
        .int16 => "int16",
        .uint16 => "uint16",
        .intptr => "intptr",
        .uintptr => "uintptr",
        else => "other",
    };
}

fn usage() error{InvalidArguments} {
    std.debug.print("usage: zslang-shaderc <input.slang> <output.spv> <output.meta.zig>\n", .{});
    return error.InvalidArguments;
}

const VertexInput = struct {
    name: []const u8,
    location: u32,
    format: []const u8,
    zig_type: []const u8,
    offset: usize,
    size: usize,
};

fn writeVertexInputs(w: *std.Io.Writer, ep: slang.EntryPoint) !void {
    var inputs: [32]VertexInput = undefined;
    var count: usize = 0;
    var stride: usize = 0;

    var pidx: u32 = 0;
    while (pidx < ep.parameterCount()) : (pidx += 1) {
        const param = ep.parameterByIndex(pidx) orelse continue;
        if (param.category() != .varying_input) continue;

        const tl = param.typeLayout() orelse continue;
        if (tl.kind() == .structure) {
            var fidx: u32 = 0;
            while (fidx < tl.fieldCount()) : (fidx += 1) {
                const field = tl.fieldByIndex(fidx) orelse continue;
                const ft = field.typeLayout() orelse continue;
                const info = formatInfo(ft) orelse {
                    std.debug.print("unsupported vertex input type for '{s}'\n", .{field.name()});
                    return error.UnsupportedVertexInput;
                };
                const location = field.bindingIndex();
                const offset = stride;
                const size = info.size;
                inputs[count] = .{
                    .name = field.name(),
                    .location = location,
                    .format = info.format,
                    .zig_type = info.zig_type,
                    .offset = offset,
                    .size = size,
                };
                count += 1;
                stride = @max(stride, offset + size);
            }
        } else {
            const info = formatInfo(tl) orelse return error.UnsupportedVertexInput;
            const location = param.bindingIndex();
            const offset = stride;
            const size = info.size;
            inputs[count] = .{
                .name = param.name(),
                .location = location,
                .format = info.format,
                .zig_type = info.zig_type,
                .offset = offset,
                .size = size,
            };
            count += 1;
            stride = @max(stride, offset + size);
        }
    }

    try w.print("pub const vertex_stride = {d};\n", .{stride});
    try w.writeAll("pub const vertex_inputs = .{\n");
    for (inputs[0..count]) |input| {
        try w.writeAll("    .{ .name = ");
        try w.printStringEscaped(input.name);
        try w.print(", .location = {d}, .format = ", .{input.location});
        try w.printStringEscaped(input.format);
        try w.print(", .offset = {d}, .size = {d} }},\n", .{ input.offset, input.size });
    }
    try w.writeAll("};\n\n");

    try w.writeAll("pub const Vertex = struct {\n");
    for (inputs[0..count]) |input| {
        try w.writeAll("    @\"");
        try w.writeAll(input.name);
        try w.writeAll("\": ");
        try w.writeAll(input.zig_type);
        try w.writeAll(",\n");
    }
    try w.writeAll("};\n\n");
}

const FormatInfo = struct { format: []const u8, zig_type: []const u8, size: u32 };

fn formatInfo(ft: slang.TypeLayout) ?FormatInfo {
    const n = switch (ft.kind()) {
        .scalar => 1,
        .vector => ft.columnCount(),
        else => return null,
    };

    const fmt = switch (n) {
        1 => switch (ft.scalarType()) {
            .float32 => "float",
            .uint32 => "uint",
            .int32 => "int",
            else => return null,
        },
        2 => switch (ft.scalarType()) {
            .float32 => "float2",
            .uint32 => "uint2",
            .int32 => "int2",
            else => return null,
        },
        3 => switch (ft.scalarType()) {
            .float32 => "float3",
            .uint32 => "uint3",
            .int32 => "int3",
            else => return null,
        },
        4 => switch (ft.scalarType()) {
            .float32 => "float4",
            .uint32 => "uint4",
            .int32 => "int4",
            else => return null,
        },
        else => return null,
    };

    const zig = switch (n) {
        1 => switch (ft.scalarType()) {
            .float32 => "f32",
            .uint32 => "u32",
            .int32 => "i32",
            else => return null,
        },
        2 => switch (ft.scalarType()) {
            .float32 => "[2]f32",
            .uint32 => "[2]u32",
            .int32 => "[2]i32",
            else => return null,
        },
        3 => switch (ft.scalarType()) {
            .float32 => "[3]f32",
            .uint32 => "[3]u32",
            .int32 => "[3]i32",
            else => return null,
        },
        4 => switch (ft.scalarType()) {
            .float32 => "[4]f32",
            .uint32 => "[4]u32",
            .int32 => "[4]i32",
            else => return null,
        },
        else => return null,
    };

    const scalar_size: u32 = switch (ft.scalarType()) {
        .float32, .uint32, .int32 => 4,
        else => return null,
    };

    return .{ .format = fmt, .zig_type = zig, .size = scalar_size * @as(u32, @intCast(n)) };
}
