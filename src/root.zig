//! Public API surface. Re-exports the vendored libraries, the ECS, the engine
//! modules and their components/resources so demos can `@import("z")` only.

const std = @import("std");

pub const zflecs = @import("zflecs");
pub const zsdl = @import("zsdl");
pub const zgui = @import("zgui");
pub const zmath = @import("zmath");
pub const zstbi = @import("zstbi");

/// Compile-time embedded SPIR-V shaders
pub const shaders = @import("shaders");

// Ecs
pub const Ecs = @import("core/ecs.zig");
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
pub const CameraModule = @import("camera.zig");
pub const DebugModule = @import("debug.zig");
pub const GfxModule = @import("gfx.zig");
pub const GuiModule = @import("gui.zig");
pub const InputModule = @import("input.zig");
pub const PhaseModule = Ecs.PhaseModule;
pub const TimeModule = @import("time.zig");
pub const TransformModule = @import("transform.zig");

// Components and Resources
pub const Camera = CameraModule.Camera;
pub const Gfx = GfxModule.Gfx;
pub const PostRenderPhase = GfxModule.PostRenderPhase;
pub const GlobalTransform = TransformModule.GlobalTransform;
pub const Input = InputModule.Input;
pub const MainCamera = CameraModule.MainCamera;
pub const Name = TransformModule.Name;
pub const Time = TimeModule.Time;
pub const Transform = TransformModule.Transform;

const render = @import("render/render.zig");
pub const Material = render.material.Material;
pub const GpuMesh = render.mesh.GpuMesh;
pub const Mesh = render.mesh.Mesh;
pub const MaterialPlugin = render.render_module.MaterialPlugin;
pub const MaterialRef = render.render_module.MaterialRef;
pub const MeshRef = render.render_module.MeshRef;
pub const RenderMeshes = render.render_module.RenderMeshes;
pub const RenderModule = render.render_module.RenderModule;
pub const RenderPhase = render.render_module.RenderPhase;
pub const Renderer = render.render_module.Renderer;

test {
    _ = Ecs;
}
