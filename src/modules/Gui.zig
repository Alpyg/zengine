const wgpu = @import("zgpu").wgpu;
const zflecs = @import("zflecs");
const zgpu = @import("zgpu");
const zgui = @import("zgui");

const z = @import("../root.zig");
const Ecs = z.Ecs;
const Gfx = z.Gfx;
const Pipeline = z.Pipeline;
const Resource = z.Resource;
const System = z.System;

const GuiModule = @This();

pub fn init(_: GuiModule, ecs: *Ecs) void {
    zgui.init(z.allocator);

    _ = zgui.io.addFontFromFile("assets/fonts/Roboto-Medium.ttf", 16.0);

    const gfx: *const Gfx = zflecs.singleton_get(ecs.world, Gfx).?;

    zgui.backend.init(
        gfx.window,
        gfx.gctx.device,
        @intFromEnum(zgpu.GraphicsContext.swapchain_format),
        @intFromEnum(wgpu.TextureFormat.undef),
    );

    zgui.io.setConfigFlags(zgui.ConfigFlags{ .dock_enable = true });
    zgui.getStyle().scaleAllSizes(1);

    _ = ecs.registerEcs(GuiModule);
}

pub fn deinit(_: *Ecs) void {
    zgui.deinit();
    zgui.backend.deinit();
}

pub const PreRender = System(struct {
    pub const phase = &Pipeline.First;

    pub fn run(r_gfx: Resource(Gfx)) void {
        const gfx = r_gfx.get();

        zgui.backend.newFrame(
            gfx.gctx.swapchain_descriptor.width,
            gfx.gctx.swapchain_descriptor.height,
        );
    }
});

pub const Render = System(struct {
    pub const phase = &Pipeline.PostRender;

    pub fn run(r_gfx: Resource(Gfx)) void {
        const gfx = r_gfx.get();

        if (!gfx.debug) {
            zgui.endFrame();
            return;
        }

        const back_buffer_view = gfx.gctx.swapchain.getCurrentTextureView();
        defer back_buffer_view.release();

        const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
            .view = back_buffer_view,
            .load_op = .clear,
            .store_op = .store,
        }};
        const render_pass_info = wgpu.RenderPassDescriptor{
            .color_attachment_count = color_attachments.len,
            .color_attachments = &color_attachments,
        };
        const pass = gfx.encoder.beginRenderPass(render_pass_info);
        defer {
            pass.end();
            pass.release();
        }

        const size = gfx.getRenderTargetSize();
        pass.setViewport(
            0,
            0,
            @as(f32, @floatFromInt(gfx.gctx.swapchain_descriptor.width)),
            @as(f32, @floatFromInt(gfx.gctx.swapchain_descriptor.height)),
            0,
            1,
        );
        pass.setScissorRect(0, 0, size[0], size[1]);

        zgui.backend.draw(pass);
    }
});
