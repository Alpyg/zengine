const std = @import("std");

pub const zflecs = @import("zflecs");
pub const zsdl = @import("zsdl");
pub const zgui = @import("zgui");
pub const zmath = @import("zmath");
pub const zstbi = @import("zstbi");

// Ecs
pub const Ecs = @import("core/Ecs.zig");
pub const Assets = Ecs.Assets;
pub const Event = Ecs.Event;
pub const Parent = Ecs.Parent;
pub const Phase = Ecs.Phase;
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
pub const TimeModule = @import("modules/Time.zig");
pub const TransformModule = @import("modules/Transform.zig");

// Components and Resources
pub const Camera = CameraModule.Camera;
pub const Gfx = GfxModule.Gfx;
pub const GlobalTransform = TransformModule.GlobalTransform;
pub const Input = InputModule.Input;
pub const MainCamera = CameraModule.MainCamera;
pub const Name = TransformModule.Name;
pub const Time = TimeModule.Time;
pub const Transform = TransformModule.Transform;
pub const Material = @import("modules/render/material.zig").Material;
pub const Mesh = @import("modules/render/mesh.zig").Mesh;
pub const GpuMesh = @import("modules/render/mesh.zig").GpuMesh;
pub const RenderModule = @import("modules/Render.zig").RenderModule;
pub const MaterialPlugin = @import("modules/Render.zig").MaterialPlugin;
pub const MeshRef = @import("modules/Render.zig").MeshRef;
pub const MaterialRef = @import("modules/Render.zig").MaterialRef;
pub const Renderer = @import("modules/Render.zig").Renderer;
pub const RenderMeshes = @import("modules/Render.zig").RenderMeshes;

test {
    _ = Ecs;
}
