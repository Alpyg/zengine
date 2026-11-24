//! Editor demo UI: a fullscreen dockspace with `Main` and `Tool` tabs, plus
//! the `Viewport` window that displays the offscreen scene texture.
//!
//! This lives in the demo rather than the engine: zengine only exposes the
//! ImGui backend (`GuiModule`) and never builds UI of its own.

const z = @import("z");
const zgui = z.zgui;
const zsdl = z.zsdl;

/// System: clears the swapchain before the UI is drawn. The engine's ImGui
/// render pass uses `.load`, so the demo owns the background clear.
pub const ClearSwapchain = z.System(z.Phase.post_render, struct {
    pub fn run(
        gfx: z.Resource(z.Gfx),
        renderer: z.Resource(*z.Renderer),
    ) void {
        const cmd = gfx.cmd orelse return;
        const texture = gfx.swapchain_texture orelse return;

        var color_target = zsdl.GPUColorTargetInfo{
            .texture = texture,
            .mip_level = 0,
            .layer_or_depth_plane = 0,
            .clear_color = renderer.clear_color,
            .load_op = .clear,
            .store_op = .store,
            .cycle = true,
        };
        const render_pass = zsdl.beginGPURenderPass(cmd, @ptrCast(&color_target), 1, null);
        zsdl.endGPURenderPass(render_pass);
    }
});

/// System: toggles mouse-look on Escape and submits the editor dockspace.
/// `Dockspace` spans the window; `Main` and `Tool` are tabs inside it, each
/// hosting its own nested dockspace.
pub const DebugRender = z.System(z.Phase.pre_render, struct {
    pub fn run(
        gfx: z.Resource(z.Gfx),
        input: z.Resource(*z.Input),
    ) void {
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

/// System: draws the offscreen scene texture inside the `Viewport` window,
/// recreating the render target when the window size changes.
pub const DebugUIViewportSystem = z.System(z.Phase.render, struct {
    pub fn run(
        gfx: z.Resource(*z.Gfx),
        renderer: z.Resource(*z.Renderer),
    ) void {
        if (!z.GuiModule.isFrameStarted()) return;

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
