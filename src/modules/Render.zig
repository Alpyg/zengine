const std = @import("std");

const wgpu = @import("zgpu").wgpu;
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const zgui = @import("zgui");
const zm = @import("zmath");

const z = @import("../root.zig");

pub const Material = @import("render/material.zig").Material;
pub const Mesh = @import("render/mesh.zig").Mesh;
pub const RenderPipeline = @import("render/pipeline.zig").RenderPipeline;

const RenderModule = @This();

pub fn init(_: RenderModule, ecs: *z.Ecs) void {
    _ = ecs.registerComponents(Components)
        .registerSystems(Systems);
}

pub const Components = struct {
    pub const TriangleMesh = Mesh(.{
        .position = wgpu.VertexFormat.float32x3,
        .color = wgpu.VertexFormat.float32x3,
    });

    pub const StandardMaterial = Material(
        "standard.wgsl",
        struct {
            object_to_clip: zm.Mat,
        },
        @constCast(&[_]wgpu.VertexFormat{
            .float32x3,
            .float32x3,
        }),
    );

    pub const RenderPipeline = @import("render/pipeline.zig").RenderPipeline;
};

const Systems = struct {
    const zflecs = @import("zflecs");

    pub const Render = z.System(struct {
        pub const phase = &z.Pipeline.Render;

        pub fn run(
            r_gfx: z.Resource(z.Gfx),
            q_camera: z.Query(.{z.Camera, z.GlobalTransform}, .{}),
            q: z.Query(.{z.GlobalTransform, z.TriangleMesh, z.RenderPipeline}, .{}),
        ) void {
            const gfx = r_gfx.get();

            const back_buffer_view = gfx.getRenderTarget();

            var camera_it = q_camera.iter();
            const camera = (camera_it.next() orelse return)[0];

            var it = q.iter();
            while (it.next()) |obj| {
                const transform: *z.GlobalTransform, const mesh: *z.TriangleMesh, const render_pipeline: *z.RenderPipeline = obj;


                const vb_info = gfx.gctx.lookupResourceInfo(mesh.vertex_buffer) orelse continue;
                const ib_info = gfx.gctx.lookupResourceInfo(mesh.index_buffer) orelse continue;
                const pipeline = gfx.gctx.lookupResource(render_pipeline.pipeline) orelse continue;
                const bind_group = gfx.gctx.lookupResource(render_pipeline.bind_group) orelse continue;
                const depth_view = gfx.gctx.lookupResource(gfx.depth_texture_view) orelse continue;

                const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                    .view = back_buffer_view,
                    .load_op = .clear,
                    .store_op = .store,
                }};
                const depth_attachment = wgpu.RenderPassDepthStencilAttachment{
                    .view = depth_view,
                    .depth_load_op = .clear,
                    .depth_store_op = .store,
                    .depth_clear_value = 1.0,
                };
                const render_pass_info = wgpu.RenderPassDescriptor{
                    .color_attachment_count = color_attachments.len,
                    .color_attachments = &color_attachments,
                    .depth_stencil_attachment = &depth_attachment,
                };
                const pass = gfx.encoder.beginRenderPass(render_pass_info);
                defer {
                    pass.end();
                    pass.release();
                }

                pass.setVertexBuffer(0, vb_info.gpuobj.?, 0, vb_info.size);
                pass.setIndexBuffer(ib_info.gpuobj.?, .uint32, 0, ib_info.size);
                pass.setPipeline(pipeline);

                const transform_mat = zm.mul(
                    zm.mul(
                        zm.translationV(transform.translation()),
                        zm.quatToMat(transform.rotation()),
                    ),
                    zm.scalingV(transform.scale()),
                );
                const object_to_clip = zm.mul(transform_mat, camera.world_clip);

                const mem = gfx.gctx.uniformsAllocate(zm.Mat, 1);
                mem.slice[0] = zm.transpose(object_to_clip);

                pass.setBindGroup(0, bind_group, &.{mem.offset});
                pass.drawIndexed(mesh.index_count, 1, 0, 0, 0);
            }
        }
    });
};
