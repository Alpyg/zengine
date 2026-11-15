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
                .cull_mode = .none,
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

    pub fn createVertexBufferLayout(v: []wgpu.VertexFormat, attributes: [*]wgpu.VertexAttribute) wgpu.VertexBufferLayout {
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
    return @sizeOf(mesh.vertexFormatToType(format));
}
