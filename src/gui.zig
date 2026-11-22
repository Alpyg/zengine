//! Dear ImGui integration through zgui's SDL3 GPU backend.
//!
//! Frame lifecycle: `PreRender` starts the ImGui frame, `Ui`/`Viewport`
//! systems submit widgets, and `Render` draws the accumulated geometry into the
//! swapchain.

const zflecs = @import("zflecs");
const zsdl = @import("zsdl");
const zgui = @import("zgui");

const z = @import("root.zig");

/// True between `PreRender` and `Render` of the current frame.
var frame_started: bool = false;

/// Whether an ImGui frame is active. UI systems should skip work when false.
pub fn isFrameStarted() bool {
    return frame_started;
}

/// ImGui backend state. Initializing this resource sets up zgui, loads the UI
/// font and creates the SDL3 GPU backend, docking enabled by default.
pub const Gui = struct {
    pub const RESOURCE = {};

    /// Marker so the singleton is a non-zero-sized component.
    active: bool = true,

    pub fn init(ecs: *z.Ecs) Gui {
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

        return .{};
    }

    pub fn deinit(_: *Gui) void {
        zgui.backend.deinit();
        zgui.deinit();
    }
};

/// System: starts an ImGui frame sized to the swapchain. No frame is started
/// while the window is minimized (zero-sized swapchain).
pub const PreRender = z.System(z.Phase.pre_render, struct {
    pub fn run(gfx: z.Resource(z.Gfx)) void {
        if (gfx.swapchain_w == 0 or gfx.swapchain_h == 0) {
            frame_started = false;
            return;
        }

        zgui.backend.newFrame(gfx.swapchain_w, gfx.swapchain_h, 1.0);
        frame_started = true;
    }
});

/// System: renders the ImGui draw data into the swapchain, clearing it to dark
/// gray first.
pub const Render = z.System(z.PostRenderPhase.imgui, struct {
    pub fn run(gfx: z.Resource(z.Gfx)) void {
        if (!frame_started) return;
        frame_started = false;

        const cmd = gfx.cmd orelse return;

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
