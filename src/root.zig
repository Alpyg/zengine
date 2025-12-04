const std = @import("std");

pub const wgpu = @import("zgpu").wgpu;
pub const zflecs = @import("zflecs");
pub const zglfw = @import("zglfw");
pub const zgpu = @import("zgpu");
pub const zgui = @import("zgui");
pub const zmath = @import("zmath");

// Ecs
pub const Ecs = @import("Ecs.zig");
pub const Parent = @import("Ecs.zig").Parent;
pub const Pipeline = @import("Ecs.zig").Pipeline;
pub const Query = @import("Ecs.zig").Query;
pub const Resource = @import("Ecs.zig").Resource;
pub const System = @import("Ecs.zig").System;
pub const With = @import("Ecs.zig").With;
pub const Without = @import("Ecs.zig").Without;

// Modules
pub const CameraModule = @import("modules/Camera.zig");
pub const DebugModule = @import("modules/Debug.zig");
pub const GfxModule = @import("modules/Gfx.zig");
pub const GuiModule = @import("modules/Gui.zig");
pub const InputModule = @import("modules/Input.zig");
pub const RenderModule = @import("modules/Render.zig");
pub const RenderPipeline = RenderModule.RenderPipeline;
pub const TransformModule = @import("modules/Transform.zig");

// Components and Resources
pub const Camera = CameraModule.Components.Camera;
pub const Gfx = GfxModule.Gfx;
pub const GlobalTransform = TransformModule.Components.GlobalTransform;
pub const Input = InputModule.Input;
pub const Name = TransformModule.Components.Name;
pub const StandardMaterial= RenderModule.Components.StandardMaterial;
pub const Transform = TransformModule.Components.Transform;
pub const TriangleMesh = RenderModule.Components.TriangleMesh;

pub var allocator: std.mem.Allocator = undefined;
pub var gctx: *zgpu.GraphicsContext = undefined;

test {
    _ = Ecs;
}
