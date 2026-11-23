//! Material template: a graphics pipeline built from a compiled shader struct
//! plus the per-draw uniform values pushed to the GPU. Vertex layout and
//! uniform block layout are derived from types at comptime and validated
//! against the shader's reflected layout.

const std = @import("std");

const zsdl = @import("zsdl");

const z = @import("../root.zig");
const render_module = @import("render_module.zig");

/// A material: a graphics pipeline + the per-draw resources (uniforms) it pushes.
///
/// - `S`: a compiled shader struct from the generated `shaders` module. It must
///   expose `spv`, `vertex`, `fragment`, `uniform_block`, `bindings`,
///   `vertex_inputs`, `vertex_stride` and `Vertex`, which the build-time Slang
///   reflection generates.
///
/// The uniform struct is generated from `S.uniform_block`, so field names and
/// layout come from the shader itself. The GPU vertex layout is taken from the
/// shader's reflected vertex inputs, so no separate vertex-layout argument is
/// needed.
pub fn Material(comptime S: type) type {
    comptime {
        if (!@hasDecl(S, "spv") or !@hasDecl(S, "vertex") or
            !@hasDecl(S, "fragment") or !@hasDecl(S, "uniform_block") or
            !@hasDecl(S, "vertex_inputs") or !@hasDecl(S, "vertex_stride"))
        {
            @compileError("Material expects a compiled shader struct from the generated `shaders` module");
        }

        if (S.vertex.num_uniform_buffers > 1 or S.fragment.num_uniform_buffers > 1) {
            @compileError("Material supports at most one uniform buffer per stage (push slot 0)");
        }
    }

    const UniformsType = uniformStruct(S);

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
    // --- comptime vertex layout derivation from the shader reflection ---
    const attr_count = S.vertex_inputs.len;
    const gpu_attrs: [attr_count]zsdl.GPUVertexAttribute = comptime blk: {
        var a: [attr_count]zsdl.GPUVertexAttribute = undefined;
        for (S.vertex_inputs, 0..) |input, i| {
            a[i] = .{
                .location = input.location,
                .buffer_slot = 0,
                .format = parseVertexFormat(input.format),
                .offset = input.offset,
            };
        }
        break :blk a;
    };

    const gpu_vb_desc: [1]zsdl.GPUVertexBufferDescription = .{
        .{
            .slot = 0,
            .pitch = S.vertex_stride,
            .input_rate = .vertex,
        },
    };

    return struct {
        const Self = @This();

        pub const Uniforms = UniformsType;
        pub const vertex_stride = S.vertex_stride;

        /// Namespace registered with `ecs.register(...)`: the material asset
        /// pool, the `MaterialRef` component and the draw system for this
        /// material type.
        pub const Module = struct {
            /// Ensures the material asset collection exists.
            pub const Assets = struct {
                pub const RESOURCE = {};

                /// Marker so the singleton is a non-zero-sized component.
                active: bool = true,

                pub fn init(ecs: *z.Ecs) @This() {
                    if (!ecs.hasResource(z.Assets(Self)))
                        _ = ecs.insert(z.Assets(Self).init(ecs.allocator));
                    return .{};
                }
            };

            /// Component: reference to a material handle.
            pub const Ref = render_module.MaterialRef(Self);

            /// System: draws entities using this material.
            pub const Draw = render_module.DrawMaterial(Self);
        };

        /// Graphics pipeline created from the shader pair and vertex layout.
        pipeline: *zsdl.GPUGraphicsPipeline,
        vertex_shader: *zsdl.GPUShader,
        fragment_shader: *zsdl.GPUShader,

        /// CPU-side mirror of the pushed uniform data.
        uniforms: Uniforms,

        /// Device used to release the pipeline and shaders.
        device: *zsdl.GPUDevice,

        /// Build the pipeline. The vertex layout is derived from the shader's
        /// reflection; the only runtime input is the uniform values.
        pub fn init(gfx: *z.Gfx, material: Uniforms) !Self {
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

        pub fn pushUniforms(self: *const Self, cmd: *zsdl.GPUCommandBuffer) void {
            const bytes: *const anyopaque = @ptrCast(&self.uniforms);
            const len: u32 = @intCast(@sizeOf(Uniforms));

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

/// Builds the CPU-side uniform struct from the shader's reflected block: field
/// names, types and offsets are all taken from Slang. Layouts that need padding
/// beyond natural field alignment are rejected for now.
fn uniformStruct(comptime S: type) type {
    const fields = S.uniform_block.fields;
    if (fields.len == 0) return struct {};

    var names: [fields.len][:0]const u8 = undefined;
    var types: [fields.len]type = undefined;
    var attrs: [fields.len]std.builtin.Type.Struct.FieldAttributes = undefined;

    var offset: usize = 0;
    inline for (fields, 0..) |field, i| {
        const FT = uniformFieldType(field);

        if (field.offset != offset) {
            @compileError("Uniform field '" ++ field.name ++
                "' needs explicit padding, which Material does not support yet");
        }
        if (field.size != @sizeOf(FT)) {
            @compileError("Uniform field '" ++ field.name ++
                "' reflected size does not match the generated Zig type");
        }

        names[i] = std.fmt.comptimePrint("{s}", .{field.name});
        types[i] = FT;
        attrs[i] = .{ .default_value_ptr = zeroDefaultPtr(FT) };
        offset += @sizeOf(FT);
    }

    if (offset != S.uniform_block.size) {
        @compileError("Uniform block size does not match its reflected fields");
    }
    if (offset > 65536) {
        @compileError("Material uniform block exceeds 64 KiB");
    }

    const U = @Struct(.auto, null, &names, &types, &attrs);

    comptime {
        for (fields, 0..) |field, i| {
            if (@offsetOf(U, names[i]) != field.offset) {
                @compileError("Generated uniform field '" ++ field.name ++
                    "' does not land at its reflected offset");
            }
        }
    }

    return U;
}

fn uniformFieldType(comptime field: anytype) type {
    const Scalar = uniformScalarType(field.scalar);

    if (std.mem.eql(u8, field.kind, "scalar")) return Scalar;

    if (std.mem.eql(u8, field.kind, "vector")) {
        const n: usize = @intCast(field.columns);
        if (n < 1 or n > 4) {
            @compileError("Material does not support uniform vectors wider than 4 components");
        }
        const V = @Vector(n, Scalar);
        return if (@sizeOf(V) == field.size) V else [n]Scalar;
    }

    if (std.mem.eql(u8, field.kind, "matrix")) {
        const rows: usize = @intCast(field.rows);
        const cols: usize = @intCast(field.columns);
        if (rows < 1 or rows > 4 or cols < 1 or cols > 4) {
            @compileError("Material does not support uniform matrices larger than 4x4");
        }
        const Row = @Vector(cols, Scalar);
        if (rows * @sizeOf(Row) == field.size) return [rows]Row;
        return [rows][cols]Scalar;
    }

    @compileError("Material does not support reflected uniform field kind '" ++ field.kind ++ "'");
}

fn uniformScalarType(comptime name: []const u8) type {
    if (std.mem.eql(u8, name, "bool")) return bool;
    if (std.mem.eql(u8, name, "float16")) return f16;
    if (std.mem.eql(u8, name, "float32")) return f32;
    if (std.mem.eql(u8, name, "float64")) return f64;
    if (std.mem.eql(u8, name, "int8")) return i8;
    if (std.mem.eql(u8, name, "int16")) return i16;
    if (std.mem.eql(u8, name, "int32")) return i32;
    if (std.mem.eql(u8, name, "int64")) return i64;
    if (std.mem.eql(u8, name, "uint8")) return u8;
    if (std.mem.eql(u8, name, "uint16")) return u16;
    if (std.mem.eql(u8, name, "uint32")) return u32;
    if (std.mem.eql(u8, name, "uint64")) return u64;
    @compileError("Material does not support reflected uniform scalar '" ++ name ++ "'");
}

/// Default value for a generated field, so callers can supply only the uniforms
/// they care about at material creation.
fn zeroDefaultPtr(comptime T: type) ?*const anyopaque {
    const value: T = std.mem.zeroes(T);
    return @ptrCast(&value);
}

fn parseVertexFormat(comptime name: []const u8) zsdl.GPUVertexElementFormat {
    if (std.mem.eql(u8, name, "float")) return .float;
    if (std.mem.eql(u8, name, "float2")) return .float2;
    if (std.mem.eql(u8, name, "float3")) return .float3;
    if (std.mem.eql(u8, name, "float4")) return .float4;
    if (std.mem.eql(u8, name, "int")) return .int;
    if (std.mem.eql(u8, name, "int2")) return .int2;
    if (std.mem.eql(u8, name, "int3")) return .int3;
    if (std.mem.eql(u8, name, "int4")) return .int4;
    if (std.mem.eql(u8, name, "uint")) return .uint;
    if (std.mem.eql(u8, name, "uint2")) return .uint2;
    if (std.mem.eql(u8, name, "uint3")) return .uint3;
    if (std.mem.eql(u8, name, "uint4")) return .uint4;
    @compileError("Unsupported reflected vertex format: " ++ name);
}

test "uniform struct is generated from shader reflection" {
    const S = struct {
        pub const uniform_block = .{
            .name = "Uniforms",
            .size = 68,
            .fields = .{
                .{ .name = "object_to_clip", .offset = 0, .size = 64, .kind = "matrix", .scalar = "float32", .rows = 4, .columns = 4, .elements = 1 },
                .{ .name = "tint", .offset = 64, .size = 4, .kind = "scalar", .scalar = "float32", .rows = 1, .columns = 1, .elements = 1 },
            },
        };
    };

    const U = uniformStruct(S);

    comptime {
        std.debug.assert(@sizeOf(U) == 68);
        std.debug.assert(@offsetOf(U, "object_to_clip") == 0);
        std.debug.assert(@offsetOf(U, "tint") == 64);
        std.debug.assert(@FieldType(U, "object_to_clip") == [4]@Vector(4, f32));
        std.debug.assert(@FieldType(U, "tint") == f32);
    }

    const value: U = .{ .object_to_clip = undefined, .tint = 1.0 };
    try std.testing.expectEqual(@as(f32, 1.0), value.tint);
}
