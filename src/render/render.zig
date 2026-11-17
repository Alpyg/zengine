pub const material = @import("material.zig");
pub const Material = material.Material;

pub const mesh = @import("mesh.zig");
pub const GpuMesh = mesh.GpuMesh;
pub const Mesh = mesh.Mesh;

pub const render_module = @import("render_module.zig");
pub const MaterialPlugin = render_module.MaterialPlugin;
pub const MaterialRef = render_module.MaterialRef;
pub const MeshRef = render_module.MeshRef;
pub const RenderMeshes = render_module.RenderMeshes;
pub const RenderModule = render_module.RenderModule;
pub const Renderer = render_module.Renderer;
