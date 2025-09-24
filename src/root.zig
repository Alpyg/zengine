const std = @import("std");

pub const wgpu = @import("zgpu").wgpu;
pub const zflecs = @import("zflecs");
pub const zglfw = @import("zglfw");
pub const zgpu = @import("zgpu");
pub const zgui = @import("zgui");

pub const ecs = @import("ecs.zig");
pub const gfx = @import("gfx.zig");
pub const input = @import("input.zig");

pub const System = ecs.System;
pub const Query = ecs.Query;

pub var allocator: std.mem.Allocator = undefined;
pub var window: *zglfw.Window = undefined;
pub var gctx: *zgpu.GraphicsContext = undefined;

pub var encoder: wgpu.CommandEncoder = undefined;

pub var debug_texture: zgpu.TextureHandle = undefined;
pub var debug_texture_view: zgpu.TextureViewHandle = undefined;

pub var debug: bool = true;
pub var depth_texture: zgpu.TextureHandle = undefined;
pub var depth_texture_view: zgpu.TextureViewHandle = undefined;

test {
    _ = ecs;
}

pub fn create(
    comptime Components: type,
    comptime Systems: type,
) type {
    return struct {
        const Self = @This();
        const ECS = ecs.create(Components, Systems);

        ecs: ECS = undefined,

        pub fn init(allocator_: std.mem.Allocator) !Self {
            allocator = allocator_;

            try gfx.init();
            input.init(allocator);
            zgui.init(allocator);

            _ = zgui.io.addFontFromFile("assets/fonts/Roboto-Medium.ttf", 16.0);

            zgui.backend.init(
                window,
                gctx.device,
                @intFromEnum(zgpu.GraphicsContext.swapchain_format),
                @intFromEnum(wgpu.TextureFormat.undef),
            );

            zgui.io.setConfigFlags(zgui.ConfigFlags{ .dock_enable = true });
            zgui.getStyle().scaleAllSizes(1);

            gfx.refreshRenderTargets();

            return Self{
                .ecs = try ECS.init(),
            };
        }

        pub fn deinit(self: *Self) void {
            defer gfx.deinit();
            defer input.deinit();
            defer zgui.deinit();
            defer zgui.backend.deinit();
            defer self.ecs.deinit();
        }

        pub fn run(self: *Self) !void {
            zglfw.pollEvents();

            encoder = gctx.device.createCommandEncoder(null);
            defer encoder.release();

            _ = self.ecs.progress();

            const commands = encoder.finish(null);
            defer commands.release();
            gctx.submit(&.{commands});

            if (gctx.present() == .swap_chain_resized) gfx.refreshRenderTargets();
        }
    };
}
