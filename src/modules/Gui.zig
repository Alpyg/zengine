const std = @import("std");

const zflecs = @import("zflecs");
const zsdl = @import("zsdl");
const zgui = @import("zgui");

const z = @import("../root.zig");

const GuiModule = @This();

pub fn init(_: GuiModule, ecs: *z.Ecs) void {
    zgui.init(ecs.allocator);

    _ = zgui.io.addFontFromFile("assets/fonts/Roboto-Medium.ttf", 16.0);

    const gfx: *const z.Gfx = zflecs.singleton_get(ecs.world, z.Gfx).?;

    zgui.backend.init(
        gfx.window,
        .{
            .device = gfx.device,
            .color_target_format = @backingInt(gfx.swapchain_format),
            .msaa_samples = 0,
        },
    );

    zgui.io.setConfigFlags(zgui.ConfigFlags{ .dock_enable = true });
    zgui.getStyle().scaleAllSizes(1);

    _ = ecs.registerEcs(GuiModule);
}

pub fn deinit(_: *z.Ecs) void {
    zgui.backend.deinit();
    zgui.deinit();
}

pub const PreRender = z.System(&z.Pipeline.First, struct {
    pub fn run(r_gfx: z.Resource(z.Gfx)) void {
        const gfx = r_gfx.get();

        zgui.backend.newFrame(gfx.swapchain_w, gfx.swapchain_h, 1.0);
    }
});

pub const Render = z.System(&z.Pipeline.PostRender, struct {
    pub fn run(res_gfx: z.Resource(z.Gfx)) void {
        const gfx = res_gfx.getMut();

        const cmd = gfx.cmd orelse {
            std.debug.panic("No GPU Command Buffer acquired", .{});
        };

        zgui.render();

        if (gfx.swapchain_texture) |swapchain_tex| {
            var color_target = zsdl.GPUColorTargetInfo{
                .texture = swapchain_tex,
                .mip_level = 0,
                .layer_or_depth_plane = 0,
                .clear_color = .{ .r = 0.1, .g = 0.1, .b = 0.1, .a = 1.0 },
                .load_op = .clear,
                .store_op = .store,
                .cycle = true,
            };
            zgui.backend.prepareDrawData(cmd);
            const render_pass = zsdl.beginGPURenderPass(
                cmd,
                @ptrCast(&color_target),
                1,
                null,
            );
            defer zsdl.endGPURenderPass(render_pass);

            zgui.backend.renderDrawData(cmd, render_pass, null);
        }
    }
});
