const std = @import("std");

const Pipeline = @import("z").Pipeline;
const Resource = @import("z").Resource;
const System = @import("z").System;
const wgpu = @import("z").wgpu;
const z = @import("z");
const zflecs = @import("z").zflecs;
const zgui = @import("z").zgui;

pub const DebugToggleSystem = System(struct {
    pub const phase = &Pipeline.PreRender;

    var cursor_disabled: bool = false;

    pub fn run(res_gfx: Resource(z.Gfx)) void {
        const gfx = res_gfx.get();
        // if (input.getKey(.escape).just_pressed) {
        //     // z.debug = !z.debug;
        //     // gfx.refreshRenderTargets();
        //     input.toggleCursor();
        // }

        zgui.backend.newFrame(
            gfx.gctx.swapchain_descriptor.width,
            gfx.gctx.swapchain_descriptor.height,
        );

        zgui.pushStyleVar1f(.{ .idx = zgui.StyleVar.window_rounding, .v = 0 });
        zgui.pushStyleVar2f(.{ .idx = zgui.StyleVar.window_padding, .v = .{ 0, 0 } });

        const main_viewport = zgui.getMainViewport();
        zgui.setNextWindowPos(.{ .x = 0, .y = 0 });
        zgui.setNextWindowSize(.{
            .w = @as(f32, @floatFromInt(gfx.gctx.swapchain_descriptor.width)),
            .h = @as(f32, @floatFromInt(gfx.gctx.swapchain_descriptor.height)),
        });
        zgui.setNextWindowViewport(main_viewport.getId());

        if (zgui.begin("Dockspace", .{
            .flags = .{
                .no_title_bar = true,
                .no_collapse = true,
                .no_resize = true,
                .no_move = true,
                .no_bring_to_front_on_focus = true,
                .no_nav_focus = true,
                .menu_bar = true,
            },
        })) {
            _ = zgui.DockSpace("Dockspace", .{ 0, 0 }, .{});
        }
        zgui.end();

        if (zgui.begin("Main", .{})) {
            _ = zgui.DockSpace("MainDockspace", .{ 0, 0 }, .{});
        }
        zgui.end();

        if (zgui.begin("Block", .{})) {
            _ = zgui.DockSpace("BlockDockspace", .{ 0, 0 }, .{});
        }
        zgui.end();

        zgui.popStyleVar(.{ .count = 2 });
    }
});

pub const DebugUIViewportSystem = System(struct {
    pub const phase = &Pipeline.Render;

    pub fn run(res_gfx: Resource(z.Gfx)) void {
        const gfx = res_gfx.get();

        if (zgui.begin("Main", .{})) {
            if (zgui.begin("Viewport", .{})) {
                const avail = zgui.getContentRegionAvail();

                const tex_id = gfx.gctx.lookupResource(gfx.debug_texture_view).?;
                zgui.image(tex_id, .{ .w = avail[0], .h = avail[1] });
            }
            zgui.end();
        }
        zgui.end();
    }
});

pub const DebugUIRenderSystem = System(struct {
    pub const phase = &Pipeline.PostRender;

    pub fn run(res_gfx: Resource(z.Gfx)) void {
        const gfx = res_gfx.get();

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
