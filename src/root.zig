const std = @import("std");

pub const wgpu = @import("zgpu").wgpu;
pub const zflecs = @import("zflecs");
pub const zglfw = @import("zglfw");
pub const zgpu = @import("zgpu");
pub const zgui = @import("zgui");
pub const zmath = @import("zmath");

// Ecs
pub const Ecs = @import("ecs/Ecs.zig");
pub const Parent = Ecs.Parent;
pub const Pipeline = Ecs.Pipeline;
pub const Query = Ecs.Query;
pub const Resource = Ecs.Resource;
pub const System = Ecs.System;
pub const With = Ecs.With;
pub const Without = Ecs.Without;

// Modules
pub const CameraModule = @import("modules/Camera.zig");
pub const DebugModule = @import("modules/Debug.zig");
pub const GfxModule = @import("modules/Gfx.zig");
pub const GuiModule = @import("modules/Gui.zig");
pub const InputModule = @import("modules/Input.zig");
pub const RenderModule = @import("modules/Render.zig");
pub const TimeModule = @import("modules/Time.zig");
pub const TransformModule = @import("modules/Transform.zig");

// Components and Resources
pub const Camera = CameraModule.Camera;
pub const Gfx = GfxModule.Gfx;
pub const GlobalTransform = TransformModule.GlobalTransform;
pub const Input = InputModule.Input;
pub const MainCamera = CameraModule.MainCamera;
pub const Name = TransformModule.Name;
pub const RenderPipeline = RenderModule.RenderPipeline;
pub const StandardMaterial = RenderModule.StandardMaterial;
pub const Time = TimeModule.Time;
pub const Transform = TransformModule.Transform;
pub const TriangleMesh = RenderModule.TriangleMesh;

pub var allocator: std.mem.Allocator = undefined;
pub var gctx: *zgpu.GraphicsContext = undefined;

test {
    _ = Ecs;
}
