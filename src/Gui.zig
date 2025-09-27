const wgpu = @import("zgpu").wgpu;
const zflecs = @import("zflecs");
const zgpu = @import("zgpu");
const zgui = @import("zgui");

const z = @import("root.zig");
const Ecs = z.Ecs;
const Gfx = z.Gfx;
const Resource = z.Resource;
const System = z.System;

pub fn init(ecs: *Ecs) void {
    zgui.init(ecs.allocator);

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

    _ = ecs.registerSystems(Systems);
}

pub fn deinit(_: *Ecs) void {
    zgui.deinit();
    zgui.backend.deinit();
}

const Systems = struct {
    pub const PreRender = System(struct {
        pub const phase = &zflecs.PreUpdate;

        pub fn run(r_gfx: Resource(Gfx)) void {
            const gfx = r_gfx.get();

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

    pub const Render = System(struct {
        pub const phase = &zflecs.OnStore;

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
};
