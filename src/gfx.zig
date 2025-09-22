const std = @import("std");

const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");

pub const Material = @import("gfx/material.zig").Material;
pub const Mesh = @import("gfx/mesh.zig").Mesh;
pub const RenderPipeline = @import("gfx/pipeline.zig").RenderPipeline;

const z = @import("root.zig");

pub fn init() !void {
    try zglfw.init();

    zglfw.windowHint(.client_api, .no_api);
    z.window = try zglfw.Window.create(1280, 720, "ZEngine", null);

    const gctx = try zgpu.GraphicsContext.create(
        z.allocator,
        .{
            .window = z.window,
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
    );
    errdefer {
        z.gctx.destroy(z.allocator);
    }

    errdefer gctx.destroy(z.state.allocator);
    z.gctx = gctx;
}

pub fn deinit() void {
    defer zglfw.terminate();
    defer z.gctx.destroy(z.allocator);
}

pub fn getRenderTarget() wgpu.TextureView {
    if (z.debug) {
        return z.gctx.lookupResource(z.debug_texture_view).?;
    }
    return z.gctx.swapchain.getCurrentTextureView();
}

pub fn getRenderTargetSize() [2]u32 {
    if (z.debug) {
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
        z.gctx.swapchain_descriptor.width,
        z.gctx.swapchain_descriptor.height,
    };
}

pub fn refreshRenderTargets() void {
    z.gctx.releaseResource(z.depth_texture_view);
    z.gctx.destroyResource(z.depth_texture);
    z.depth_texture = z.gctx.createTexture(.{
        .usage = .{ .render_attachment = true },
        .dimension = .tdim_2d,
        .size = .{
            .width = z.gctx.swapchain_descriptor.width,
            .height = z.gctx.swapchain_descriptor.height,
            .depth_or_array_layers = 1,
        },
        .format = .depth32_float,
        .mip_level_count = 1,
        .sample_count = 1,
    });
    z.depth_texture_view = z.gctx.createTextureView(z.depth_texture, .{});

    z.gctx.releaseResource(z.debug_texture_view);
    z.gctx.destroyResource(z.debug_texture);
    z.debug_texture = z.gctx.createTexture(.{
        .usage = .{ .render_attachment = true, .texture_binding = true },
        .dimension = .tdim_2d,
        .size = .{
            .width = z.gctx.swapchain_descriptor.width,
            .height = z.gctx.swapchain_descriptor.height,
        },
        .format = .bgra8_unorm,
    });

    z.debug_texture_view = z.gctx.createTextureView(z.debug_texture, .{});
}
