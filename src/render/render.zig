//! Render subsystem entry point: re-exports materials, meshes and the render
//! module so the rest of the engine can import a single file.

/// Graphics pipeline template (see `material.zig`).
pub const material = @import("material.zig");
pub const Material = material.Material;

/// CPU/GPU mesh representation (see `mesh.zig`).
pub const mesh = @import("mesh.zig");
pub const GpuMesh = mesh.GpuMesh;
pub const Mesh = mesh.Mesh;
pub const MeshFor = mesh.MeshFor;

/// Render resources, systems and per-material plugins (see `render_module.zig`).
pub const render_module = @import("render_module.zig");
pub const MaterialPlugin = render_module.MaterialPlugin;
pub const MaterialRef = render_module.MaterialRef;
pub const MeshRef = render_module.MeshRef;
pub const RenderMeshes = render_module.RenderMeshes;
pub const RenderModule = render_module.RenderModule;
pub const Renderer = render_module.Renderer;
pub const RenderPhase = render_module.RenderPhase;
