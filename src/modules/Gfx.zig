const std = @import("std");

const wgpu = @import("zgpu").wgpu;
const zsdl = @import("zsdl");

const z = @import("../root.zig");
const Ecs = z.Ecs;
const Pipeline = z.Pipeline;
const Resource = z.Resource;
const System = z.System;

const GfxModule = @This();

var window_name: [:0]const u8 = "ZEngine";

pub fn init(_: GfxModule, ecs: *Ecs) void {
    _ = ecs.registerEcs(GfxModule);
}

pub const Gfx = struct {
    pub const RESOURCE = {};

    window: *zsdl.Window = undefined,
    renderer: *zsdl.Renderer = undefined,

    allocator: std.mem.Allocator = undefined,

    pub fn init(ecs: *Ecs) Gfx {
        var self = Gfx{};
        zsdl.init(
            .{ .audio = true, .video = true },
        ) catch |err| std.debug.panic("Failed to init sdl: {any}", .{err});
        errdefer zsdl.quit();

        const num_drivers = zsdl.getNumGPUDrivers();
        std.log.info("Available GPU drivers: {d}", .{num_drivers});
        var i: i32 = 0;
        while (i < num_drivers) : (i += 1) {
            std.log.info("  Driver {d}: {s}", .{ i, zsdl.getGPUDriver(i) });
        }

        self.window = zsdl.Window.create(
            window_name,
            1280,
            720,
            .{ .vulkan = true },
        ) catch |err| std.debug.panic("Failed to init window: {any}", .{err});
        self.allocator = ecs.allocator;

        self.renderer = zsdl.Renderer.create(
            self.window,
            null,
        ) catch |err| std.debug.panic("Failed to init renderer: {any}", .{err});

        return self;
    }

    pub fn deinit(self: *Gfx) void {
        self.renderer.destroy();
        self.window.destroy();
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

// pub const PreRender = System(struct {
//     pub const phase = &Pipeline.PreRender;
//
//     pub fn run(res_gfx: Resource(Gfx)) void {
//         var gfx = res_gfx.getMut();
//
//         gfx.refreshRenderTargets();
//         gfx.encoder = gfx.gctx.device.createCommandEncoder(null);
//     }
// });

pub const Render = System(struct {
    pub const phase = &Pipeline.Last;

    pub fn run(res_gfx: Resource(Gfx)) void {
        var gfx = res_gfx.getMut();

        gfx.renderer.present();
    }
});
