const std = @import("std");

const zsdl = @import("zsdl");

const z = @import("../../root.zig");

pub const ShaderSrc = struct {
    /// Compiled SPIR-V bytes for the vertex stage.
    vertex: []const u8,
    /// Compiled SPIR-V bytes for the fragment stage.
    fragment: []const u8,
    /// Entry point names inside the SPIR-V modules.
    vertex_entry: [:0]const u8 = "main",
    fragment_entry: [:0]const u8 = "main",
    /// Number of uniform buffers declared by each stage.
    /// SDL3 SPIR-V conventions: vertex uniforms use set 1, fragment uniforms
    /// use set 3. Push slots are indexed from zero.
    vertex_uniform_buffers: u32 = 1,
    fragment_uniform_buffers: u32 = 0,
};

/// A material: a graphics pipeline + the per-draw resources (uniforms) it pushes.
///
/// - `src`: compiled shader bytes (SPIR-V)
/// - `T`:   struct of uniforms pushed for each draw
/// - `V`:   vertex layout *type* — a named struct whose fields carry
///          `zsdl.GPUVertexElementFormat` as default values, e.g.
///          `struct { position: [][3]f32, color: [][3]f32 }`.
///          The GPU layout (pitch, offsets, locations) is derived from `V` at
///          comptime, so `init` takes no layout argument.
pub fn Material(comptime src: ShaderSrc, comptime T: type, comptime V: type) type {
    const uniforms_info = @typeInfo(T).@"struct";
    const attrs_info = @typeInfo(V).@"struct";

    // --- comptime validation of the uniform struct (std140) ---
    comptime {
        var offset: u32 = 0;
        for (uniforms_info.field_names, uniforms_info.field_types) |name, FT| {
            const aligned = std.mem.alignForward(u32, offset, @alignOf(FT));
            if (aligned != offset)
                @compileError("Material uniform field '" ++ name ++
                    "' is not naturally aligned in the uniform block");
            offset += @sizeOf(FT);
        }
        if (offset > 65536)
            @compileError("Material uniform block exceeds 64 KiB");
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

        pipeline: *zsdl.GPUGraphicsPipeline,
        vertex_shader: *zsdl.GPUShader,
        fragment_shader: *zsdl.GPUShader,

        /// CPU-side mirror of the pushed uniform data.
        uniforms: T,

        device: *zsdl.GPUDevice,

        /// Build the pipeline. The vertex layout is derived from `V` at comptime;
        /// the only runtime input is the uniform values.
        pub fn init(gfx: *z.Gfx, material: T) !Self {
            const vs = try zsdl.createGPUShader(gfx.device, &.{
                .stage = .vertex,
                .entrypoint = src.vertex_entry.ptr,
                .format = .{ .spirv = true },
                .code_size = @intCast(src.vertex.len),
                .code = @ptrCast(src.vertex.ptr),
                .num_samplers = 0,
                .num_storage_buffers = 0,
                .num_storage_textures = 0,
                .num_uniform_buffers = src.vertex_uniform_buffers,
            });
            errdefer zsdl.releaseGPUShader(gfx.device, vs);

            const fs = try zsdl.createGPUShader(gfx.device, &.{
                .stage = .fragment,
                .entrypoint = src.fragment_entry.ptr,
                .format = .{ .spirv = true },
                .code_size = @intCast(src.fragment.len),
                .code = @ptrCast(src.fragment.ptr),
                .num_samplers = 0,
                .num_storage_buffers = 0,
                .num_storage_textures = 0,
                .num_uniform_buffers = src.fragment_uniform_buffers,
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

        /// Push `self.uniforms` into the shader uniform slots.
        /// `*const Self` so it can be called on a copy from the asset pool.
        pub fn flush(self: *const Self, cmd: *zsdl.GPUCommandBuffer) void {
            self.pushUniforms(cmd);
        }

        pub fn pushUniforms(self: *const Self, cmd: *zsdl.GPUCommandBuffer) void {
            const bytes: *const anyopaque = @ptrCast(&self.uniforms);
            const len: u32 = @intCast(@sizeOf(T));
            zsdl.pushGPUVertexUniformData(cmd, 0, bytes, len);
            if (src.fragment_uniform_buffers > 0)
                zsdl.pushGPUFragmentUniformData(cmd, 0, bytes, len);
        }

        /// Bind the pipeline on the given render pass.
        pub fn bind(self: *const Self, pass: *zsdl.GPURenderPass) void {
            zsdl.bindGPUGraphicsPipeline(pass, self.pipeline);
        }
    };
}
