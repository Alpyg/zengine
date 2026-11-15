const std = @import("std");

const wgpu = @import("wgpu");
const zflecs = @import("zflecs");
const zgui = @import("zgui");

const z = @import("../root.zig");

const DebugModule = @This();

pub fn init(_: DebugModule, ecs: *z.Ecs) void {
    _ = ecs.registerEcs(DebugModule);
}

pub const DebugRender = z.System(&z.Pipeline.First, struct {
    pub fn run(
        res_gfx: z.Resource(z.Gfx),
        res_input: z.Resource(z.Input),
    ) void {
        const gfx = res_gfx.get();
        const input = res_input.getMut();

        if (input.getKey(.escape).just_pressed) {
            input.toggleCursor();
        }

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
            _ = zgui.dockSpace("Dockspace", .{ 0, 0 }, .{});
        }
        zgui.end();

        if (zgui.begin("Main", .{})) {
            _ = zgui.dockSpace("MainDockspace", .{ 0, 0 }, .{});
        }
        zgui.end();

        if (zgui.begin("Tool", .{})) {
            _ = zgui.dockSpace("ToolDockspace", .{ 0, 0 }, .{});
        }
        zgui.end();

        zgui.popStyleVar(.{ .count = 2 });
    }
});

pub const DebugUIViewportSystem = z.System(&z.Pipeline.Render, struct {
    pub fn run(res_gfx: z.Resource(z.Gfx)) void {
        const gfx = res_gfx.get();

        if (zgui.begin("Main", .{})) {
            if (zgui.begin("Viewport", .{})) {
                const avail = zgui.getContentRegionAvail();

                const tex_id = gfx.gctx.lookupResource(gfx.debug_texture_view).?;
                const tex_ref = zgui.TextureRef{ .tex_data = null, .tex_id = @fromBackingInt(@intCast(@intFromPtr(tex_id))) };
                zgui.image(tex_ref, .{ .w = avail[0], .h = avail[1] });
            }
            zgui.end();
        }
        zgui.end();
    }
});
