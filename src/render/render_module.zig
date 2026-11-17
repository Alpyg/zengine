//! Render module: GPU mesh cache, offscreen scene target, scene pass systems
//! and the per-material draw systems.
//!
//! `RenderModule` registers the shared resources and the upload/pass systems;
//! `MaterialPlugin(M)` adds the assets and draw system for one material type.

const std = @import("std");

const zsdl = @import("zsdl");
const zm = @import("zmath");

const z = @import("../root.zig");

pub const Mesh = z.Mesh;
pub const GpuMesh = z.GpuMesh;
pub const Material = z.Material;

pub const RenderModule = @This();

/// Component referring to a CPU mesh asset. The render module uploads it once
/// the asset appears in `Assets(Mesh)`.
pub const MeshRef = struct {
    pub const COMPONENT = {};
    handle: z.Assets(Mesh).Handle,
};

/// Component referring to a material asset of type `M`.
pub fn MaterialRef(comptime M: type) type {
    return struct {
        pub const COMPONENT = {};
        handle: z.Assets(M).Handle,
    };
}

/// GPU-side meshes, keyed by the full asset handle id (index + cycle).
pub const RenderMeshes = struct {
    pub const RESOURCE = {};

    map: std.AutoHashMapUnmanaged(u64, GpuMesh) = .{},
    allocator: std.mem.Allocator,

    pub fn init(ecs: *z.Ecs) RenderMeshes {
        return .{ .allocator = ecs.allocator };
    }

    pub fn deinit(self: *RenderMeshes, device: *zsdl.GPUDevice) void {
        var it = self.map.valueIterator();
        while (it.next()) |gpu| {
            zsdl.releaseGPUBuffer(device, gpu.vertex_buffer);
            zsdl.releaseGPUBuffer(device, gpu.index_buffer);
        }
        self.map.deinit(self.allocator);
    }

    pub fn get(self: *RenderMeshes, handle: z.Assets(Mesh).Handle) ?*GpuMesh {
        return self.map.getPtr(handle.id);
    }

    pub fn contains(self: *const RenderMeshes, handle: z.Assets(Mesh).Handle) bool {
        return self.map.contains(handle.id);
    }

    pub fn put(self: *RenderMeshes, handle: z.Assets(Mesh).Handle, gpu: GpuMesh) !void {
        try self.map.put(self.allocator, handle.id, gpu);
    }
};

/// Frame-level render state shared by all material systems.
pub const Renderer = struct {
    pub const RESOURCE = {};

    pass: ?*zsdl.GPURenderPass = null,

    /// Offscreen color target that ImGui displays inside the scene viewport.
    scene_color: ?*zsdl.GPUTexture = null,
    /// Depth target for the offscreen scene pass.
    scene_depth: ?*zsdl.GPUTexture = null,
    scene_w: u32 = 0,
    scene_h: u32 = 0,

    scene_sampler: ?*zsdl.GPUSampler = null,
    /// Stable storage for the ImGui texture id. The SDL3 GPU backend treats
    /// ImTextureID as a pointer to an SDL_GPUTextureSamplerBinding.
    scene_binding: *zsdl.GPUTextureSamplerBinding,

    clear_color: zsdl.FColor = .{ .r = 0.05, .g = 0.05, .b = 0.08, .a = 1.0 },

    allocator: std.mem.Allocator,

    pub fn init(ecs: *z.Ecs) Renderer {
        const binding = ecs.allocator.create(zsdl.GPUTextureSamplerBinding) catch @panic("OOM");
        binding.* = .{
            .texture = undefined,
            .sampler = undefined,
        };

        return .{
            .scene_binding = binding,
            .allocator = ecs.allocator,
        };
    }

    pub fn deinit(self: *Renderer, device: *zsdl.GPUDevice) void {
        if (self.scene_color) |texture| {
            zsdl.releaseGPUTexture(device, texture);
            self.scene_color = null;
        }
        if (self.scene_depth) |texture| {
            zsdl.releaseGPUTexture(device, texture);
            self.scene_depth = null;
        }
        if (self.scene_sampler) |sampler| {
            zsdl.releaseGPUSampler(device, sampler);
            self.scene_sampler = null;
        }
        self.allocator.destroy(self.scene_binding);
    }

    /// Binding passed to ImGui as the texture id for the scene image.
    pub fn sceneBinding(self: *Renderer) *zsdl.GPUTextureSamplerBinding {
        return self.scene_binding;
    }

    fn ensureSampler(self: *Renderer, gfx: *z.Gfx) bool {
        if (self.scene_sampler != null) return true;

        self.scene_sampler = zsdl.createGPUSampler(gfx.device, &.{
            .min_filter = .linear,
            .mag_filter = .linear,
            .mipmap_mode = .linear,
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
            .mip_lod_bias = 0,
            .max_anisotropy = 1,
            .compare_op = .never,
            .min_lod = 0,
            .max_lod = 0,
            .enable_anisotropy = false,
            .enable_compare = false,
        }) catch {
            std.log.err("createGPUSampler(scene) failed: {s}", .{zsdl.getError() orelse "unknown"});
            return false;
        };

        return true;
    }

    /// Creates or recreates the offscreen color/depth targets when the size
    /// changes. Returns false on allocation failure or a zero-sized viewport.
    pub fn ensureSceneTarget(self: *Renderer, gfx: *z.Gfx, width: u32, height: u32) bool {
        if (width == 0 or height == 0) return false;

        if (self.scene_color != null and
            self.scene_depth != null and
            self.scene_w == width and
            self.scene_h == height)
        {
            return true;
        }

        if (self.scene_color) |texture| {
            zsdl.releaseGPUTexture(gfx.device, texture);
            self.scene_color = null;
        }
        if (self.scene_depth) |texture| {
            zsdl.releaseGPUTexture(gfx.device, texture);
            self.scene_depth = null;
        }

        const color = zsdl.createGPUTexture(gfx.device, &.{
            .type = .texturetype_2d,
            .format = gfx.swapchain_format,
            .usage = .{ .color_target = true, .sampler = true },
            .width = width,
            .height = height,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = .samplecount_1,
        }) catch {
            std.log.err("createGPUTexture(scene color) failed: {s}", .{zsdl.getError() orelse "unknown"});
            return false;
        };

        const depth = zsdl.createGPUTexture(gfx.device, &.{
            .type = .texturetype_2d,
            .format = z.Gfx.depth_format,
            .usage = .{ .depth_stencil_target = true },
            .width = width,
            .height = height,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = .samplecount_1,
        }) catch {
            std.log.err("createGPUTexture(scene depth) failed: {s}", .{zsdl.getError() orelse "unknown"});
            zsdl.releaseGPUTexture(gfx.device, color);
            return false;
        };

        if (!self.ensureSampler(gfx)) {
            zsdl.releaseGPUTexture(gfx.device, color);
            zsdl.releaseGPUTexture(gfx.device, depth);
            return false;
        }

        self.scene_color = color;
        self.scene_depth = depth;
        self.scene_w = width;
        self.scene_h = height;

        self.scene_binding.texture = color;
        self.scene_binding.sampler = self.scene_sampler.?;

        return true;
    }

    /// Begins the scene render pass into the offscreen targets. Returns false
    /// if the targets or command buffer are not ready.
    pub fn begin(self: *Renderer, gfx: *z.Gfx) bool {
        const color = self.scene_color orelse return false;
        const depth = self.scene_depth orelse return false;
        if (self.scene_w == 0 or self.scene_h == 0) return false;
        const cmd = gfx.cmd orelse return false;

        const color_targets = [_]zsdl.GPUColorTargetInfo{.{
            .texture = color,
            .mip_level = 0,
            .layer_or_depth_plane = 0,
            .clear_color = self.clear_color,
            .load_op = .clear,
            .store_op = .store,
            .cycle = true,
        }};

        const depth_target = zsdl.GPUDepthStencilTargetInfo{
            .texture = depth,
            .clear_depth = 1.0,
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .cycle = true,
            .clear_stencil = 0,
        };

        self.pass = zsdl.beginGPURenderPass(cmd, &color_targets, color_targets.len, &depth_target);
        return true;
    }

    /// Ends the scene render pass, if one is active.
    pub fn end(self: *Renderer) void {
        if (self.pass) |pass| {
            zsdl.endGPURenderPass(pass);
            self.pass = null;
        }
    }
};

/// Uploads any mesh assets added to `Assets(Mesh)`.
pub const UploadSetupMeshes = z.System(&z.Phase.PreRender, struct {
    pub fn run(
        r_gfx: z.Resource(z.Gfx),
        r_meshes: z.Resource(z.Assets(Mesh)),
        r_render_meshes: z.Resource(RenderMeshes),
    ) void {
        const gfx = r_gfx.getMut();
        const meshes = r_meshes.getMut();
        const render_meshes = r_render_meshes.getMut();

        const cmd = gfx.cmd orelse return;

        while (meshes.popPending()) |handle| {
            if (render_meshes.contains(handle)) continue;

            const mesh = meshes.getColumnsIfLive(handle) orelse continue;
            const gpu = mesh.upload(gfx, cmd) catch |err| {
                std.log.err("Failed to upload mesh: {s}", .{@errorName(err)});
                continue;
            };

            render_meshes.put(handle, gpu) catch @panic("OOM");
        }
    }
});

/// System: opens the scene render pass into the offscreen target.
pub const BeginScene = z.System(&z.Phase.RenderBegin, struct {
    pub fn run(
        r_gfx: z.Resource(z.Gfx),
        r_renderer: z.Resource(Renderer),
    ) void {
        _ = r_renderer.getMut().begin(r_gfx.getMut());
    }
});

/// System: closes the scene render pass.
pub const EndScene = z.System(&z.Phase.RenderEnd, struct {
    pub fn run(r_renderer: z.Resource(Renderer)) void {
        r_renderer.getMut().end();
    }
});

/// Draws every entity that has a `MeshRef` and a `MaterialRef(M)`.
pub fn DrawMaterial(comptime M: type) type {
    return z.System(&z.Phase.Render, struct {
        pub fn run(
            r_gfx: z.Resource(z.Gfx),
            r_materials: z.Resource(z.Assets(M)),
            r_render_meshes: z.Resource(RenderMeshes),
            r_renderer: z.Resource(Renderer),
            q_camera: z.Query(.{ z.Camera, z.GlobalTransform }, .{}),
            q: z.Query(.{ z.GlobalTransform, MeshRef, MaterialRef(M) }, .{}),
        ) void {
            const gfx = r_gfx.get();
            const materials = r_materials.getMut();
            const render_meshes = r_render_meshes.getMut();
            const renderer = r_renderer.getMut();

            const cmd = gfx.cmd orelse return;
            const pass = renderer.pass orelse return;

            var camera_it = q_camera.iter();
            const camera_tuple = camera_it.next() orelse return;
            const camera: *z.Camera = camera_tuple[0];

            var it = q.iter();
            while (it.next()) |obj| {
                const transform: *z.GlobalTransform = obj[0];
                const mesh_ref: *MeshRef = obj[1];
                const material_ref: *MaterialRef(M) = obj[2];

                const gpu_mesh = render_meshes.get(mesh_ref.handle) orelse continue;

                if (@hasDecl(M, "vertex_stride") and gpu_mesh.vertex_stride != M.vertex_stride) {
                    std.log.warn("Mesh/material vertex stride mismatch; skipping draw", .{});
                    continue;
                }

                const object_to_clip = zm.transpose(zm.mul(transform.transform, camera.world_clip));

                if (@hasField(M.Uniforms, "object_to_clip")) {
                    var uniforms = materials.pool.getColumnAssumeLive(material_ref.handle, .uniforms);
                    @field(uniforms, "object_to_clip") = object_to_clip;
                    materials.pool.setColumnAssumeLive(material_ref.handle, .uniforms, uniforms);
                }

                const material = materials.pool.getColumnsAssumeLive(material_ref.handle);
                material.bind(pass);
                material.pushUniforms(cmd);

                const vertex_bindings = [_]zsdl.GPUBufferBinding{.{
                    .buffer = gpu_mesh.vertex_buffer,
                    .offset = 0,
                }};
                const index_binding = zsdl.GPUBufferBinding{
                    .buffer = gpu_mesh.index_buffer,
                    .offset = 0,
                };

                zsdl.bindGPUVertexBuffers(pass, 0, &vertex_bindings, 1);
                zsdl.bindGPUIndexBuffer(pass, &index_binding, .size_32bit);
                zsdl.drawGPUIndexedPrimitives(pass, gpu_mesh.index_count, 1, 0, 0, 0);
            }
        }
    });
}

/// Registers the mesh/material/renderer resources and the shared render
/// systems.
pub fn init(_: RenderModule, ecs: *z.Ecs) void {
    if (!ecs.hasResource(z.Assets(Mesh)))
        _ = ecs.registerResource(z.Assets(Mesh).init(ecs.allocator));
    if (!ecs.hasResource(RenderMeshes))
        _ = ecs.registerResource(RenderMeshes.init(ecs));
    if (!ecs.hasResource(Renderer))
        _ = ecs.registerResource(Renderer.init(ecs));

    _ = ecs.registerEcs(MeshRef);
    _ = ecs.registerEcs(UploadSetupMeshes);
    _ = ecs.registerEcs(BeginScene);
    _ = ecs.registerEcs(EndScene);
}

/// Module factory that registers the asset collection for material type `M`,
/// its `MaterialRef(M)` component and the matching draw system.
pub fn MaterialPlugin(comptime M: type) type {
    return struct {
        pub fn init(_: @This(), ecs: *z.Ecs) void {
            if (!ecs.hasResource(z.Assets(M)))
                _ = ecs.registerResource(z.Assets(M).init(ecs.allocator));

            _ = ecs.registerEcs(MaterialRef(M));
            _ = ecs.registerEcs(DrawMaterial(M));
        }
    };
}
