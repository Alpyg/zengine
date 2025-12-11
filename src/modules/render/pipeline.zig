const std = @import("std");

const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zm = @import("zmath");

const z = @import("../../root.zig");
const mesh = @import("mesh.zig");

/// RenderPipeline for a given type.
pub const RenderPipeline = struct {
    pub const COMPONENT = {};
    const Self = @This();

    gctx: *zgpu.GraphicsContext,

    pipeline: zgpu.RenderPipelineHandle,
    bind_group: zgpu.BindGroupHandle,

    /// Initialize the pipeline.
    pub fn init(material: anytype) Self {
        const gctx = z.gctx;

        var vertex_attributes: [@TypeOf(material).VertexAttributes.len]wgpu.VertexAttribute = undefined;
        const vertex_buffers = [_]wgpu.VertexBufferLayout{createVertexBufferLayout(
            @TypeOf(material).VertexAttributes,
            &vertex_attributes,
        )};
        const color_targets = [_]wgpu.ColorTargetState{.{
            .format = zgpu.GraphicsContext.swapchain_format,
        }};

        const pipeline_descriptor = wgpu.RenderPipelineDescriptor{
            .vertex = .{
                .module = @field(material, "vs_module"),
                .entry_point = "vertex",
                .buffer_count = vertex_buffers.len,
                .buffers = &vertex_buffers,
            },
            .primitive = .{
                .front_face = .ccw,
                .cull_mode = .back,
                .topology = .triangle_list,
            },
            .depth_stencil = &wgpu.DepthStencilState{
                .format = .depth32_float,
                .depth_write_enabled = true,
                .depth_compare = .less,
            },
            .fragment = &.{
                .module = @field(material, "fs_module"),
                .entry_point = "fragment",
                .target_count = color_targets.len,
                .targets = &color_targets,
            },
        };

        const pipeline = gctx.createRenderPipeline(@field(material, "pipeline_layout"), pipeline_descriptor);

        return Self{
            .gctx = gctx,
            .pipeline = pipeline,
            .bind_group = @field(material, "bind_group"),
        };
    }

    /// Release the pipeline resources.
    pub fn deinit(self: *Self) void {
        defer z.gctx.releaseResource(self.pipeline);
    }

    pub fn createVertexBufferLayout(comptime v: []wgpu.VertexFormat, attributes: [*]wgpu.VertexAttribute) wgpu.VertexBufferLayout {
        var offset: u32 = 0;
        for (v, 0..) |format, i| {
            attributes[i] = wgpu.VertexAttribute{
                .format = format,
                .offset = offset,
                .shader_location = @intCast(i),
            };

            offset += vertexFormatSize(format);
        }
        return wgpu.VertexBufferLayout{
            .array_stride = offset,
            .attribute_count = v.len,
            .attributes = attributes,
        };
    }
};

inline fn vertexFormatSize(format: wgpu.VertexFormat) u32 {
    return switch (format) {
        .uint8x2 => @sizeOf([2]u8),
        .uint8x4 => @sizeOf([4]u8),

        .sint8x2 => @sizeOf([2]i8),
        .sint8x4 => @sizeOf([4]i8),

        .unorm8x2 => @sizeOf([2]u8),
        .unorm8x4 => @sizeOf([4]u8),

        .snorm8x2 => @sizeOf([2]i8),
        .snorm8x4 => @sizeOf([4]i8),

        .uint16x2 => @sizeOf([2]u16),
        .uint16x4 => @sizeOf([4]u16),

        .sint16x2 => @sizeOf([2]i16),
        .sint16x4 => @sizeOf([4]i16),

        .unorm16x2 => @sizeOf([2]u16),
        .unorm16x4 => @sizeOf([4]u16),

        .snorm16x2 => @sizeOf([2]i16),
        .snorm16x4 => @sizeOf([4]i16),

        .float16x2 => @sizeOf([2]f16),
        .float16x4 => @sizeOf([4]f16),

        .float32 => @sizeOf(f32),
        .float32x2 => @sizeOf([2]f32),
        .float32x3 => @sizeOf([3]f32),
        .float32x4 => @sizeOf([4]f32),

        .uint32 => @sizeOf(u32),
        .uint32x2 => @sizeOf([2]u32),
        .uint32x3 => @sizeOf([3]u32),
        .uint32x4 => @sizeOf([4]u32),

        .sint32 => @sizeOf(i32),
        .sint32x2 => @sizeOf([2]i32),
        .sint32x3 => @sizeOf([3]i32),
        .sint32x4 => @sizeOf([4]i32),

        else => unreachable,
    };
}
