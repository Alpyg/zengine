const std = @import("std");

const zsdl = @import("zsdl");

const z = @import("../root.zig");

const GfxModule = @This();

var window_name: [:0]const u8 = "ZEngine";

pub fn init(_: GfxModule, ecs: *z.Ecs) void {
    _ = ecs.registerEcs(GfxModule);
}

pub const Gfx = struct {
    pub const RESOURCE = {};

    device: *zsdl.GPUDevice = undefined,
    window: *zsdl.Window = undefined,

    cmd: ?*zsdl.GPUCommandBuffer = undefined,

    swapchain_texture: ?*zsdl.GPUTexture = undefined,
    swapchain_format: zsdl.GPUTextureFormat = undefined,
    swapchain_w: u32 = undefined,
    swapchain_h: u32 = undefined,

    debug: bool = false,

    pub fn init(ecs: *z.Ecs) Gfx {
        var self = Gfx{};

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
        self.cmd = zsdl.acquireGPUCommandBuffer(self.device) catch {
            std.debug.panic("Failed to aquire GPU Command Buffer: {s}", .{zsdl.getError().?});
        };
        zsdl.waitAndAcquireGPUSwapchainTexture(
            self.cmd.?,
            self.window,
            &self.swapchain_texture,
            &self.swapchain_w,
            &self.swapchain_h,
        ) catch {
            std.debug.panic("Could not acquire swapchain: {s}", .{zsdl.getError().?});
        };
        self.swapchain_format = zsdl.getGPUSwapchainTextureFormat(self.device, self.window);

        _ = ecs.registerResource(self);

        return self;
    }

    pub fn deinit(self: *Gfx) void {
        zsdl.releaseWindowFromGPUDevice(self.device, self.window);
        zsdl.destroyWindow(self.window);
        zsdl.destroyGPUDevice(self.device);
        zsdl.quit();
    }

    // pub fn getRenderTarget(self: *const Gfx) wgpu.TextureView {
    //     if (self.debug) {
    //         return self.gctx.lookupResource(self.debug_texture_view).?;
    //     }
    //     return self.gctx.swapchain.getCurrentTextureView();
    // }
    //
    // pub fn getRenderTargetSize(self: *const Gfx) [2]u32 {
    //     if (self.debug) {
    //         const avail = blk: {
    //             defer zgui.end();
    //             if (zgui.begin("Main", .{})) {
    //                 defer zgui.end();
    //                 if (zgui.begin("Viewport", .{})) {
    //                     break :blk zgui.getWindowSize();
    //                 }
    //             }
    //             break :blk .{ 0, 0 };
    //         };
    //         return .{
    //             @as(u32, @intFromFloat(avail[0])),
    //             @as(u32, @intFromFloat(avail[1])),
    //         };
    //     }
    //     return .{
    //         self.gctx.swapchain_descriptor.width,
    //         self.gctx.swapchain_descriptor.height,
    //     };
    // }
    //
    // pub fn refreshRenderTargets(self: *Gfx) void {
    //     self.gctx.releaseResource(self.depth_texture_view);
    //     self.gctx.destroyResource(self.depth_texture);
    //     self.depth_texture = self.gctx.createTexture(.{
    //         .usage = .{ .render_attachment = true },
    //         .dimension = .tdim_2d,
    //         .size = .{
    //             .width = self.gctx.swapchain_descriptor.width,
    //             .height = self.gctx.swapchain_descriptor.height,
    //             .depth_or_array_layers = 1,
    //         },
    //         .format = .depth32_float,
    //         .mip_level_count = 1,
    //         .sample_count = 1,
    //     });
    //     self.depth_texture_view = self.gctx.createTextureView(self.depth_texture, .{});
    //
    //     self.gctx.releaseResource(self.debug_texture_view);
    //     self.gctx.destroyResource(self.debug_texture);
    //     self.debug_texture = self.gctx.createTexture(.{
    //         .usage = .{ .render_attachment = true, .texture_binding = true },
    //         .dimension = .tdim_2d,
    //         .size = .{
    //             .width = self.gctx.swapchain_descriptor.width,
    //             .height = self.gctx.swapchain_descriptor.height,
    //         },
    //         .format = .bgra8_unorm,
    //     });
    //
    //     self.debug_texture_view = self.gctx.createTextureView(self.debug_texture, .{});
    // }
};

pub const PreRender = z.System(&z.Pipeline.PreRender, struct {
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

pub const Render = z.System(&z.Pipeline.Last, struct {
    pub fn run(res_gfx: z.Resource(z.Gfx)) void {
        var gfx = res_gfx.getMut();

        const cmd = gfx.cmd orelse {
            std.debug.panic("No GPU Command Buffer acquired", .{});
        };

        _ = zsdl.submitGPUCommandBuffer(cmd) catch {
            std.debug.panic("Could not submit GPU Command Buffer: {s}", .{zsdl.getError().?});
        };

        gfx.cmd = null;
        gfx.swapchain_texture = null;
    }
});
