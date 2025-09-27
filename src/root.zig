const std = @import("std");

pub const wgpu = @import("zgpu").wgpu;
pub const zflecs = @import("zflecs");
pub const zglfw = @import("zglfw");
pub const zgpu = @import("zgpu");
pub const zgui = @import("zgui");

pub const Ecs = @import("Ecs.zig");
pub const Gfx = @import("Gfx.zig");
pub const Gui = @import("Gui.zig");
pub const Pipeline = @import("Ecs.zig").Pipeline;
pub const Query = @import("Ecs.zig").Query;
pub const Resource = @import("Ecs.zig").Resource;
pub const System = @import("Ecs.zig").System;
pub const Input = @import("Input.zig");

pub var allocator: std.mem.Allocator = undefined;

test {
    _ = Ecs;
}
