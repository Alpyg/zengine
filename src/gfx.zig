//! SDL3 GPU context: owns the device, window, swapchain and the per-frame
//! command buffer. One command buffer is acquired in `Phase.pre_render`, drawn into
//! during `Phase.render`, submitted in `Phase.post_render` and cleaned up in
//! `Phase.last`.

const std = @import("std");

const zsdl = @import("zsdl");

const z = @import("root.zig");

const GfxModule = @This();

var window_name: [:0]const u8 = "ZEngine";

/// Subphases inside `Phase.post_render`, chained in this order.
pub const PostRenderPhase = enum {
    /// ImGui draw-data encoding into the swapchain.
    imgui,
    /// Command-buffer submission.
    submit,
};

pub fn init(_: GfxModule, ecs: *z.Ecs) void {
    _ = ecs.registerPhaseSet(z.Phase.post_render, PostRenderPhase);
    _ = ecs.registerEcs(GfxModule);
}

pub const Gfx = struct {
    pub const RESOURCE = {};

    /// Format used by all depth-stencil targets.
    pub const depth_format: zsdl.GPUTextureFormat = .d32_float;

    device: *zsdl.GPUDevice = undefined,
    window: *zsdl.Window = undefined,

    /// Command buffer for the current frame; null between frames.
    cmd: ?*zsdl.GPUCommandBuffer = null,

    /// Swapchain texture acquired for the current frame.
    swapchain_texture: ?*zsdl.GPUTexture = null,
    swapchain_format: zsdl.GPUTextureFormat = undefined,
    swapchain_w: u32 = 0,
    swapchain_h: u32 = 0,

    /// Transfer buffers used by asset uploads. They cannot be released until
    /// the command buffer that references them has been submitted.
    deferred_transfer_buffers: std.ArrayListUnmanaged(*zsdl.GPUTransferBuffer) = .empty,

    /// Reserved debug flag; currently unused.
    debug: bool = false,

    allocator: std.mem.Allocator = undefined,

    /// Initializes SDL, creates the GPU device and window, claims the window
    /// for the device and registers this as a resource.
    pub fn init(ecs: *z.Ecs) Gfx {
        var self = Gfx{};
        self.allocator = ecs.allocator;

        zsdl.init(.{ .audio = true, .video = true }) catch {
            std.debug.panic("Failed to init sdl: {any}", .{zsdl.getError().?});
        };
        errdefer zsdl.quit();

        const num_drivers = zsdl.getNumGPUDrivers();
        std.log.info("Available GPU drivers: {d}", .{num_drivers});
        var i: i32 = 0;
        while (i < num_drivers) : (i += 1) {
            std.log.info("  Driver {d}: {s}", .{ i, zsdl.getGPUDriver(i) });
        }

        self.device = zsdl.createGPUDevice(.{ .spirv = true }, true, null) catch {
            std.debug.panic("Failed to init Device: {s}", .{zsdl.getError().?});
        };
        self.window = zsdl.createWindow(window_name, 1280, 720, .{ .vulkan = true }) catch {
            std.debug.panic("Failed to init Window: {s}", .{zsdl.getError().?});
        };
        zsdl.claimWindowForGPUDevice(self.device, self.window) catch {
            std.debug.panic("Failed to claim Window for Device: {s}", .{zsdl.getError().?});
        };

        self.swapchain_format = zsdl.getGPUSwapchainTextureFormat(self.device, self.window);

        return self;
    }

    /// Waits for the GPU to go idle, releases deferred transfers and destroys
    /// the window, device and SDL.
    pub fn deinit(self: *Gfx) void {
        zsdl.waitForGPUIdle(self.device) catch {};
        self.releaseDeferredTransfers();
        self.deferred_transfer_buffers.deinit(self.allocator);

        zsdl.releaseWindowFromGPUDevice(self.device, self.window);
        zsdl.destroyWindow(self.window);
        zsdl.destroyGPUDevice(self.device);
        zsdl.quit();
    }

    /// Keeps an upload buffer alive until the current command buffer is
    /// submitted.
    pub fn deferTransferBuffer(self: *Gfx, buffer: *zsdl.GPUTransferBuffer) !void {
        try self.deferred_transfer_buffers.append(self.allocator, buffer);
    }

    /// Releases all deferred transfer buffers. Called after submission.
    pub fn releaseDeferredTransfers(self: *Gfx) void {
        for (self.deferred_transfer_buffers.items) |buffer| {
            zsdl.releaseGPUTransferBuffer(self.device, buffer);
        }
        self.deferred_transfer_buffers.clearRetainingCapacity();
    }
};

/// System: acquires the frame's command buffer and swapchain texture. Skipped
/// swapchain acquisition (e.g. minimized window) yields a zero-sized swapchain.
pub const PreRender = z.System(z.Phase.pre_render, struct {
    pub fn run(gfx: z.Resource(*Gfx)) void {
        gfx.cmd = zsdl.acquireGPUCommandBuffer(gfx.device) catch {
            std.debug.panic("Could not acquire GPU Command Buffer: {s}", .{zsdl.getError().?});
        };

        zsdl.waitAndAcquireGPUSwapchainTexture(
            gfx.cmd.?,
            gfx.window,
            &gfx.swapchain_texture,
            &gfx.swapchain_w,
            &gfx.swapchain_h,
        ) catch {
            std.debug.panic("Could not acquire swapchain: {s}", .{zsdl.getError().?});
        };
    }
});

/// System: submits the frame's command buffer.
pub const Render = z.System(PostRenderPhase.submit, struct {
    pub fn run(gfx: z.Resource(z.Gfx)) void {
        const cmd = gfx.cmd orelse return;

        _ = zsdl.submitGPUCommandBuffer(cmd) catch {
            std.debug.panic("Could not submit GPU Command Buffer: {s}", .{zsdl.getError().?});
        };
    }
});

/// System: end-of-frame cleanup. Releases deferred transfer buffers and clears
/// per-frame GPU state.
pub const Cleanup = z.System(z.Phase.last, struct {
    pub fn run(gfx: z.Resource(*z.Gfx)) void {
        gfx.releaseDeferredTransfers();
        gfx.cmd = null;
        gfx.swapchain_texture = null;
    }
});
