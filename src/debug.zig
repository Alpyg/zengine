const std = @import("std");

const zgui = @import("zgui");

const z = @import("root.zig");

const DebugModule = @This();

pub fn init(_: DebugModule, ecs: *z.Ecs) void {
    _ = ecs.registerEcs(DebugModule);
}

pub const DebugRender = z.System(&z.Phase.Ui, struct {
    pub fn run(
        res_gfx: z.Resource(z.Gfx),
        res_input: z.Resource(z.Input),
    ) void {
        const gfx = res_gfx.get();
        const input = res_input.getMut();

        if (!z.GuiModule.isFrameStarted()) return;

        if (input.getKey(.escape).just_pressed) {
            input.toggleCursor();
        }

        zgui.pushStyleVar1f(.{ .idx = zgui.StyleVar.window_rounding, .v = 0 });
        zgui.pushStyleVar2f(.{ .idx = zgui.StyleVar.window_padding, .v = .{ 0, 0 } });

        const main_viewport = zgui.getMainViewport();
        zgui.setNextWindowPos(.{ .x = 0, .y = 0 });
        zgui.setNextWindowSize(.{
            .w = @as(f32, @floatFromInt(gfx.swapchain_w)),
            .h = @as(f32, @floatFromInt(gfx.swapchain_h)),
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

pub const DebugUIViewportSystem = z.System(&z.Phase.Viewport, struct {
    pub fn run(
        r_gfx: z.Resource(z.Gfx),
        r_renderer: z.Resource(z.Renderer),
    ) void {
        if (!z.GuiModule.isFrameStarted()) return;

        const gfx = r_gfx.getMut();
        const renderer = r_renderer.getMut();

        if (zgui.begin("Viewport", .{})) {
            const avail = zgui.getContentRegionAvail();
            const width_f = @max(1.0, avail[0]);
            const height_f = @max(1.0, avail[1]);
            const width: u32 = @intFromFloat(width_f);
            const height: u32 = @intFromFloat(height_f);

            if (renderer.ensureSceneTarget(gfx, width, height)) {
                const binding = renderer.sceneBinding();
                const tex_ref = zgui.TextureRef{
                    .tex_data = null,
                    .tex_id = @fromBackingInt(@intCast(@intFromPtr(binding))),
                };

                zgui.image(tex_ref, .{ .w = width_f, .h = height_f });
            }
        }
        zgui.end();
    }
});
