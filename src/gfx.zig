const std = @import("std");

const zsdl = @import("zsdl");

const z = @import("root.zig");

const GfxModule = @This();

var window_name: [:0]const u8 = "ZEngine";

pub fn init(_: GfxModule, ecs: *z.Ecs) void {
    _ = ecs.registerEcs(GfxModule);
}

pub const Gfx = struct {
    pub const RESOURCE = {};

    pub const depth_format: zsdl.GPUTextureFormat = .d32_float;

    device: *zsdl.GPUDevice = undefined,
    window: *zsdl.Window = undefined,

    cmd: ?*zsdl.GPUCommandBuffer = null,

    swapchain_texture: ?*zsdl.GPUTexture = null,
    swapchain_format: zsdl.GPUTextureFormat = undefined,
    swapchain_w: u32 = 0,
    swapchain_h: u32 = 0,

    /// Transfer buffers used by asset uploads. They cannot be released until
    /// the command buffer that references them has been submitted.
    deferred_transfer_buffers: std.ArrayListUnmanaged(*zsdl.GPUTransferBuffer) = .empty,

    debug: bool = false,

    allocator: std.mem.Allocator = undefined,

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

        _ = ecs.registerResource(self);

        return self;
    }

    pub fn deinit(self: *Gfx) void {
        zsdl.waitForGPUIdle(self.device) catch {};
        self.releaseDeferredTransfers();
        self.deferred_transfer_buffers.deinit(self.allocator);

        zsdl.releaseWindowFromGPUDevice(self.device, self.window);
        zsdl.destroyWindow(self.window);
        zsdl.destroyGPUDevice(self.device);
        zsdl.quit();
    }

    pub fn deferTransferBuffer(self: *Gfx, buffer: *zsdl.GPUTransferBuffer) !void {
        try self.deferred_transfer_buffers.append(self.allocator, buffer);
    }

    pub fn releaseDeferredTransfers(self: *Gfx) void {
        for (self.deferred_transfer_buffers.items) |buffer| {
            zsdl.releaseGPUTransferBuffer(self.device, buffer);
        }
        self.deferred_transfer_buffers.clearRetainingCapacity();
    }
};

pub const PreRender = z.System(&z.Phase.Acquire, struct {
    pub fn run(res_gfx: z.Resource(Gfx)) void {
        var gfx = res_gfx.getMut();

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

pub const Render = z.System(&z.Phase.Last, struct {
    pub fn run(res_gfx: z.Resource(z.Gfx)) void {
        var gfx = res_gfx.getMut();

        const cmd = gfx.cmd orelse return;

        _ = zsdl.submitGPUCommandBuffer(cmd) catch {
            std.debug.panic("Could not submit GPU Command Buffer: {s}", .{zsdl.getError().?});
        };

        gfx.releaseDeferredTransfers();
        gfx.cmd = null;
        gfx.swapchain_texture = null;
    }
});
