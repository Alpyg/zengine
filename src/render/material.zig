//! Material template: a graphics pipeline built from a compiled shader struct
//! plus the per-draw uniform values pushed to the GPU. Vertex layout and
//! uniform block layout are derived from types at comptime and validated
//! against the shader's reflected layout.

const std = @import("std");

const zsdl = @import("zsdl");

const z = @import("../root.zig");

/// A material: a graphics pipeline + the per-draw resources (uniforms) it pushes.
///
/// - `S`: a compiled shader struct from the generated `shaders` module. It must
///   expose `spv`, `vertex`, `fragment`, `uniform_block` and `bindings`, which
///   the build-time Slang reflection generates.
/// - `T`: struct of uniforms pushed for each draw. Validated against the
///   reflected uniform block at comptime.
/// - `V`: vertex layout *type* — a named struct whose fields carry
///   `zsdl.GPUVertexElementFormat` as default values, e.g.
///   `struct { position: [][3]f32, color: [][3]f32 }`.
///   The GPU layout (pitch, offsets, locations) is derived from `V` at
///   comptime, so `init` takes no layout argument.
pub fn Material(comptime S: type, comptime T: type, comptime V: type) type {
    const uniforms_info = @typeInfo(T).@"struct";
    const attrs_info = @typeInfo(V).@"struct";

    comptime {
        if (!@hasDecl(S, "spv") or !@hasDecl(S, "vertex") or
            !@hasDecl(S, "fragment") or !@hasDecl(S, "uniform_block"))
        {
            @compileError("Material expects a compiled shader struct from the generated `shaders` module");
        }

        if (S.vertex.num_uniform_buffers > 1 or S.fragment.num_uniform_buffers > 1) {
            @compileError("Material supports at most one uniform buffer per stage (push slot 0)");
        }

        if (S.uniform_block.fields.len != uniforms_info.field_names.len) {
            @compileError("Material uniform struct field count does not match the shader's reflected uniform block");
        }
    }

    // --- comptime validation of the uniform struct against reflection ---
    comptime {
        var offset: u32 = 0;
        for (uniforms_info.field_names, uniforms_info.field_types, 0..) |name, FT, i| {
            const reflected = S.uniform_block.fields[i];

            if (!std.mem.eql(u8, reflected.name, name)) {
                @compileError("Material uniform field '" ++ name ++
                    "' does not match shader reflection (expected '" ++ reflected.name ++ "')");
            }

            const aligned = std.mem.alignForward(u32, offset, @alignOf(FT));
            if (aligned != offset) {
                @compileError("Material uniform field '" ++ name ++
                    "' is not naturally aligned in the uniform block");
            }
            if (reflected.offset != offset) {
                @compileError("Material uniform field '" ++ name ++
                    "' offset does not match shader reflection");
            }
            if (reflected.size != @sizeOf(FT)) {
                @compileError("Material uniform field '" ++ name ++
                    "' size does not match shader reflection");
            }

            validateFieldType(name, FT, reflected);

            offset += @sizeOf(FT);
        }

        if (S.uniform_block.size != offset) {
            @compileError("Material uniform struct size does not match the shader's reflected block size");
        }
        if (offset > 65536) {
            @compileError("Material uniform block exceeds 64 KiB");
        }
    }

    comptime {
        var uniform_buffers: u32 = 0;
        for (S.bindings) |binding| {
            if (std.mem.eql(u8, binding.category, "constant_buffer")) {
                uniform_buffers += 1;
                if (binding.binding != 0) {
                    @compileError("Material uniform buffer must be at binding 0");
                }
                if (binding.set != 1 and binding.set != 3) {
                    @compileError("Material uniform buffer must be in set 1 (vertex) or set 3 (fragment)");
                }
            }
        }
        if (uniform_buffers == 0 and S.uniform_block.fields.len != 0) {
            @compileError("Material uniform block is not reflected as a shader binding");
        }
    }
    comptime {
        const fmt_info = @typeInfo(@TypeOf(V.formats)).@"struct";
        if (fmt_info.field_names.len != attrs_info.field_names.len)
            @compileError("Material vertex layout formats count must match struct field count");
        for (attrs_info.field_names) |name| {
            if (!@hasField(@TypeOf(V.formats), name))
                @compileError("Material vertex layout formats missing field '" ++ name ++ "'");
        }
    }

    // --- comptime vertex layout derivation from V ---

    const AttrDesc = struct {
        format: zsdl.GPUVertexElementFormat,
        offset: u32,
        elem_size: u32,
    };
    const formats = V.formats;
    const attr_count = attrs_info.field_names.len;
    const descs: [attr_count]AttrDesc = comptime blk: {
        var tmp: [attr_count]AttrDesc = undefined;
        var off: u32 = 0;
        for (attrs_info.field_names, attrs_info.field_types, 0..) |name, FT, i| {
            const fmt = @field(formats, name);
            const ElemT = std.meta.Elem(FT);
            const sz: u32 = @sizeOf(ElemT);
            tmp[i] = .{ .format = fmt, .offset = off, .elem_size = sz };
            off += sz;
        }
        break :blk tmp;
    };

    const stride: u32 = comptime blk: {
        var s: u32 = 0;
        for (descs) |d| s += d.elem_size;
        break :blk s;
    };

    const gpu_attrs: [attr_count]zsdl.GPUVertexAttribute = comptime blk: {
        var a: [attr_count]zsdl.GPUVertexAttribute = undefined;
        for (descs, 0..) |d, i| {
            a[i] = .{
                .location = i,
                .buffer_slot = 0,
                .format = d.format,
                .offset = d.offset,
            };
        }
        break :blk a;
    };

    const gpu_vb_desc: [1]zsdl.GPUVertexBufferDescription = .{
        .{
            .slot = 0,
            .pitch = stride,
            .input_rate = .vertex,
        },
    };

    return struct {
        const Self = @This();

        pub const Uniforms = T;
        pub const VertexAttributes = V;
        pub const vertex_stride = stride;

        /// Graphics pipeline created from the shader pair and vertex layout.
        pipeline: *zsdl.GPUGraphicsPipeline,
        vertex_shader: *zsdl.GPUShader,
        fragment_shader: *zsdl.GPUShader,

        /// CPU-side mirror of the pushed uniform data.
        uniforms: T,

        /// Device used to release the pipeline and shaders.
        device: *zsdl.GPUDevice,

        /// Build the pipeline. The vertex layout is derived from `V` at comptime;
        /// the only runtime input is the uniform values.
        pub fn init(gfx: *z.Gfx, material: T) !Self {
            const vs = try zsdl.createGPUShader(gfx.device, &.{
                .stage = .vertex,
                .entrypoint = "vertex",
                .format = .{ .spirv = true },
                .code_size = @intCast(S.spv.len),
                .code = @ptrCast(S.spv.ptr),
                .num_samplers = @max(S.vertex.num_textures, S.vertex.num_samplers),
                .num_storage_buffers = S.vertex.num_storage_buffers,
                .num_storage_textures = S.vertex.num_storage_textures,
                .num_uniform_buffers = S.vertex.num_uniform_buffers,
            });
            errdefer zsdl.releaseGPUShader(gfx.device, vs);

            const fs = try zsdl.createGPUShader(gfx.device, &.{
                .stage = .fragment,
                .entrypoint = "fragment",
                .format = .{ .spirv = true },
                .code_size = @intCast(S.spv.len),
                .code = @ptrCast(S.spv.ptr),
                .num_samplers = @max(S.fragment.num_textures, S.fragment.num_samplers),
                .num_storage_buffers = S.fragment.num_storage_buffers,
                .num_storage_textures = S.fragment.num_storage_textures,
                .num_uniform_buffers = S.fragment.num_uniform_buffers,
            });
            errdefer zsdl.releaseGPUShader(gfx.device, fs);

            const color_targets = [_]zsdl.GPUColorTargetDescription{.{
                .format = gfx.swapchain_format,
                .blend_state = .{
                    .enable_blend = false,
                    .enable_color_write_mask = false,
                    .color_write_mask = .{},
                    .src_color_blendfactor = .one,
                    .dst_color_blendfactor = .zero,
                    .color_blend_op = .add,
                    .src_alpha_blendfactor = .one,
                    .dst_alpha_blendfactor = .zero,
                    .alpha_blend_op = .add,
                },
            }};
            const vertex_input_state = zsdl.GPUVertexInputState{
                .vertex_buffer_descriptions = &gpu_vb_desc,
                .num_vertex_buffers = 1,
                .vertex_attributes = &gpu_attrs,
                .num_vertex_attributes = attr_count,
            };

            const pipeline_info = zsdl.GPUGraphicsPipelineCreateInfo{
                .vertex_shader = vs,
                .fragment_shader = fs,
                .vertex_input_state = vertex_input_state,
                .primitive_type = .trianglelist,
                .rasterizer_state = .{
                    .fill_mode = .fill,
                    .cull_mode = .none,
                    .front_face = .counter_clockwise,
                    .depth_bias_constant_factor = 1.0,
                    .depth_bias_clamp = 1.0,
                    .depth_bias_slope_factor = 1.0,
                    .enable_depth_bias = false,
                    .enable_depth_clip = true,
                },
                .multisample_state = .{
                    .sample_count = .samplecount_1,
                },
                .depth_stencil_state = .{
                    .compare_op = .less,
                    .back_stencil_state = .{
                        .fail_op = .zero,
                        .pass_op = .replace,
                        .depth_fail_op = .zero,
                        .compare_op = .less,
                    },
                    .front_stencil_state = .{
                        .fail_op = .zero,
                        .pass_op = .replace,
                        .depth_fail_op = .zero,
                        .compare_op = .less,
                    },
                    .compare_mask = 0,
                    .write_mask = 0,
                    .enable_depth_test = true,
                    .enable_depth_write = true,
                    .enable_stencil_test = false,
                },
                .target_info = .{
                    .color_target_descriptions = &color_targets,
                    .num_color_targets = color_targets.len,
                    .depth_stencil_format = z.Gfx.depth_format,
                    .has_depth_stencil_target = true,
                },
            };
            const pipeline = zsdl.createGPUGraphicsPipeline(gfx.device, &pipeline_info) catch
                return error.PipelineCreationFailed;
            errdefer zsdl.releaseGPUGraphicsPipeline(gfx.device, pipeline);

            return .{
                .pipeline = pipeline,
                .vertex_shader = vs,
                .fragment_shader = fs,
                .uniforms = material,
                .device = gfx.device,
            };
        }

        /// `*Self` because zpool calls `deinit()` on the stored field slot.
        pub fn deinit(self: *Self) void {
            zsdl.releaseGPUGraphicsPipeline(self.device, self.pipeline);
            zsdl.releaseGPUShader(self.device, self.fragment_shader);
            zsdl.releaseGPUShader(self.device, self.vertex_shader);
        }

        /// Push `self.uniforms` into the uniform slots declared by the shader.
        /// `*const Self` so it can be called on a copy from the asset pool.
        pub fn flush(self: *const Self, cmd: *zsdl.GPUCommandBuffer) void {
            self.pushUniforms(cmd);
        }

        pub fn pushUniforms(self: *const Self, cmd: *zsdl.GPUCommandBuffer) void {
            const bytes: *const anyopaque = @ptrCast(&self.uniforms);
            const len: u32 = @intCast(@sizeOf(T));

            if (S.vertex.num_uniform_buffers > 0)
                zsdl.pushGPUVertexUniformData(cmd, 0, bytes, len);
            if (S.fragment.num_uniform_buffers > 0)
                zsdl.pushGPUFragmentUniformData(cmd, 0, bytes, len);
        }

        /// Bind the pipeline on the given render pass.
        pub fn bind(self: *const Self, pass: *zsdl.GPURenderPass) void {
            zsdl.bindGPUGraphicsPipeline(pass, self.pipeline);
        }
    };
}

/// Best-effort check that a Zig uniform field matches the reflected Slang type.
fn validateFieldType(comptime name: []const u8, comptime FT: type, comptime reflected: anytype) void {
    const info = @typeInfo(FT);

    if (info == .array) {
        const child = info.array.child;
        if (@typeInfo(child) == .vector) {
            const vec = @typeInfo(child).vector;
            if (!std.mem.eql(u8, reflected.kind, "matrix")) {
                @compileError("Material uniform field '" ++ name ++ "' is a matrix, but the shader reflects '" ++ reflected.kind ++ "'");
            }
            if (reflected.rows != info.array.len or reflected.columns != vec.len) {
                @compileError("Material uniform field '" ++ name ++ "' matrix dimensions do not match shader reflection");
            }
            if (expectedScalarName(vec.child)) |scalar| {
                if (!std.mem.eql(u8, reflected.scalar, scalar)) {
                    @compileError("Material uniform field '" ++ name ++ "' scalar type does not match shader reflection");
                }
            }
            return;
        }
    }

    if (info == .vector) {
        if (!std.mem.eql(u8, reflected.kind, "vector")) {
            @compileError("Material uniform field '" ++ name ++ "' is a vector, but the shader reflects '" ++ reflected.kind ++ "'");
        }
        if (expectedScalarName(info.vector.child)) |scalar| {
            if (!std.mem.eql(u8, reflected.scalar, scalar)) {
                @compileError("Material uniform field '" ++ name ++ "' scalar type does not match shader reflection");
            }
        }
        return;
    }

    if (expectedScalarName(FT)) |scalar| {
        if (!std.mem.eql(u8, reflected.kind, "scalar")) {
            @compileError("Material uniform field '" ++ name ++ "' is a scalar, but the shader reflects '" ++ reflected.kind ++ "'");
        }
        if (!std.mem.eql(u8, reflected.scalar, scalar)) {
            @compileError("Material uniform field '" ++ name ++ "' scalar type does not match shader reflection");
        }
    }
}

fn expectedScalarName(comptime T: type) ?[]const u8 {
    return switch (@typeInfo(T)) {
        .float => |f| switch (f.bits) {
            16 => "float16",
            32 => "float32",
            64 => "float64",
            else => null,
        },
        .int => |i| switch (i.bits) {
            8 => if (i.signedness == .signed) "int8" else "uint8",
            16 => if (i.signedness == .signed) "int16" else "uint16",
            32 => if (i.signedness == .signed) "int32" else "uint32",
            64 => if (i.signedness == .signed) "int64" else "uint64",
            else => null,
        },
        .bool => "bool",
        else => null,
    };
}
