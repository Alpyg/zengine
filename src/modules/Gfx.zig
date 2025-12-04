const std = @import("std");

const wgpu = @import("zgpu").wgpu;
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const zgui = @import("zgui");

const z = @import("../root.zig");
const Ecs = z.Ecs;
const Pipeline = z.Pipeline;
const Resource = z.Resource;
const System = z.System;

const GfxModule = @This();

window_name: [:0]const u8 = "ZEngine",

pub fn init(self: GfxModule, ecs: *Ecs) void {
    const gfx = Gfx.init(self);

    _ = ecs.registerResource(gfx)
        .registerResource(gfx.gctx)
        .registerSystems(Systems);
}

pub const Gfx = struct {
    window: *zglfw.Window = undefined,
    gctx: *zgpu.GraphicsContext = undefined,

    encoder: wgpu.CommandEncoder = undefined,

    debug_texture: zgpu.TextureHandle = undefined,
    debug_texture_view: zgpu.TextureViewHandle = undefined,

    debug: bool = true,
    depth_texture: zgpu.TextureHandle = undefined,
    depth_texture_view: zgpu.TextureViewHandle = undefined,

    pub fn init(module: GfxModule) Gfx {
        var self = Gfx{};
        zglfw.init() catch @panic("Failed to init glfw");

        zglfw.windowHint(.client_api, .no_api);
        self.window = zglfw.Window.create(1280, 720, module.window_name, null) catch @panic("Failed to init window");

        const gctx = zgpu.GraphicsContext.create(
            z.allocator,
            .{
                .window = self.window,
                .fn_getTime = @ptrCast(&zglfw.getTime),
                .fn_getFramebufferSize = @ptrCast(&zglfw.Window.getFramebufferSize),
                .fn_getWin32Window = @ptrCast(&zglfw.getWin32Window),
                .fn_getX11Display = @ptrCast(&zglfw.getX11Display),
                .fn_getX11Window = @ptrCast(&zglfw.getX11Window),
                .fn_getWaylandDisplay = @ptrCast(&zglfw.getWaylandDisplay),
                .fn_getWaylandSurface = @ptrCast(&zglfw.getWaylandWindow),
                .fn_getCocoaWindow = @ptrCast(&zglfw.getCocoaWindow),
            },
            .{},
        ) catch @panic("Failed to initialize graphics context");
        errdefer gctx.destroy(z.allocator);

        self.gctx = gctx;
        self.refreshRenderTargets();
        z.gctx = gctx;

        return self;
    }

    pub fn deinit(self: *Gfx) void {
        self.gctx.destroy(z.allocator);
        zglfw.terminate();
    }

    pub fn getRenderTarget(self: *const Gfx) wgpu.TextureView {
        if (self.debug) {
            return self.gctx.lookupResource(self.debug_texture_view).?;
        }
        return self.gctx.swapchain.getCurrentTextureView();
    }

    pub fn getRenderTargetSize(self: *const Gfx) [2]u32 {
        if (self.debug) {
            const avail = blk: {
                defer zgui.end();
                if (zgui.begin("Main", .{})) {
                    defer zgui.end();
                    if (zgui.begin("Viewport", .{})) {
                        break :blk zgui.getWindowSize();
                    }
                }
                break :blk .{ 0, 0 };
            };
            return .{
                @as(u32, @intFromFloat(avail[0])),
                @as(u32, @intFromFloat(avail[1])),
            };
        }
        return .{
            self.gctx.swapchain_descriptor.width,
            self.gctx.swapchain_descriptor.height,
        };
    }

    pub fn refreshRenderTargets(self: *Gfx) void {
        self.gctx.releaseResource(self.depth_texture_view);
        self.gctx.destroyResource(self.depth_texture);
        self.depth_texture = self.gctx.createTexture(.{
            .usage = .{ .render_attachment = true },
            .dimension = .tdim_2d,
            .size = .{
                .width = self.gctx.swapchain_descriptor.width,
                .height = self.gctx.swapchain_descriptor.height,
                .depth_or_array_layers = 1,
            },
            .format = .depth32_float,
            .mip_level_count = 1,
            .sample_count = 1,
        });
        self.depth_texture_view = self.gctx.createTextureView(self.depth_texture, .{});

        self.gctx.releaseResource(self.debug_texture_view);
        self.gctx.destroyResource(self.debug_texture);
        self.debug_texture = self.gctx.createTexture(.{
            .usage = .{ .render_attachment = true, .texture_binding = true },
            .dimension = .tdim_2d,
            .size = .{
                .width = self.gctx.swapchain_descriptor.width,
                .height = self.gctx.swapchain_descriptor.height,
            },
            .format = .bgra8_unorm,
        });

        self.debug_texture_view = self.gctx.createTextureView(self.debug_texture, .{});
    }
};

const Systems = struct {
    const zflecs = @import("zflecs");

    pub const PreRender = System(struct {
        pub const phase = &Pipeline.PreRender;

        pub fn run(res_gfx: Resource(Gfx)) void {
            var gfx = res_gfx.getMut();

            gfx.refreshRenderTargets();
            gfx.encoder = gfx.gctx.device.createCommandEncoder(null);
        }
    });

    pub const Render = System(struct {
        pub const phase = &Pipeline.Last;

        pub fn run(res_gfx: Resource(Gfx)) void {
            var gfx = res_gfx.getMut();

            _ = gfx.gctx.swapchain.getCurrentTextureView(); // Prevent error when nothing is rendered

            const commands = gfx.encoder.finish(null);
            defer commands.release();
            gfx.gctx.submit(&.{commands});

            if (gfx.gctx.present() == .swap_chain_resized) gfx.refreshRenderTargets();
            gfx.encoder.release();
        }
    });
};
