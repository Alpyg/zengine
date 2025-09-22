const std = @import("std");

const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zm = @import("zmath");

const z = @import("../root.zig");

/// RenderPipeline for a given type.
pub fn Material(comptime shader: []const u8, comptime T: type, comptime V: anytype) type {
    const fields = comptime @typeInfo(T).@"struct".fields;

    return struct {
        const Self = @This();
        pub const VertexAttributes = V;

        gctx: *zgpu.GraphicsContext,

        pipeline_layout: zgpu.PipelineLayoutHandle,
        bind_group: zgpu.BindGroupHandle,

        vs_module: wgpu.ShaderModule,
        fs_module: wgpu.ShaderModule,

        material: T,

        /// Initialize the pipeline.
        pub fn init(material: T) Self {
            const gctx = z.gctx;

            const vs_module = zgpu.createWgslShaderModule(gctx.device, @embedFile("../../shaders/" ++ shader), "vs");
            const fs_module = zgpu.createWgslShaderModule(gctx.device, @embedFile("../../shaders/" ++ shader), "fs");

            var offset: u32 = 0;
            var bind_group_entries: [fields.len]zgpu.BindGroupEntryInfo = undefined;
            var bind_group_layout_entries: [fields.len]wgpu.BindGroupLayoutEntry = undefined;
            inline for (fields, 0..) |field, i| {
                const value = @field(material, field.name);
                switch (field.type) {
                    zgpu.TextureViewHandle => {
                        bind_group_entries[i] = .{
                            .binding = i,
                            .texture_view_handle = value,
                        };
                        bind_group_layout_entries[i] = zgpu.textureEntry(i, .{ .fragment = true }, .float, .tvdim_2d, false);
                    },
                    zgpu.SamplerHandle => {
                        bind_group_entries[i] = .{
                            .binding = i,
                            .sampler_handle = value,
                        };
                        bind_group_layout_entries[i] = zgpu.samplerEntry(i, .{ .fragment = true }, .filtering);
                    },

                    zgpu.BufferHandle => {
                        const buffer_size = gctx.lookupResource(value).?.getSize();
                        bind_group_entries[i] = .{
                            .binding = i,
                            .buffer_handle = value,
                            .offset = 0,
                            .size = buffer_size,
                        };
                        bind_group_layout_entries[i] = zgpu.bufferEntry(i, .{ .vertex = true }, .read_only_storage, false, 0);
                    },
                    else => {
                        bind_group_entries[i] = .{
                            .binding = i,
                            .buffer_handle = gctx.uniforms.buffer,
                            .offset = 0,
                            .size = @sizeOf(field.type),
                        };
                        bind_group_layout_entries[i] = zgpu.bufferEntry(i, .{ .vertex = true }, .uniform, true, 0);
                    },
                }
                offset += @sizeOf(field.type);
            }

            const bind_group_layout = gctx.createBindGroupLayout(&bind_group_layout_entries);
            defer gctx.releaseResource(bind_group_layout);

            const bind_group = gctx.createBindGroup(bind_group_layout, &bind_group_entries);
            const pipeline_layout = gctx.createPipelineLayout(&.{bind_group_layout});

            return Self{
                .gctx = gctx,
                .pipeline_layout = pipeline_layout,
                .bind_group = bind_group,
                .vs_module = vs_module,
                .fs_module = fs_module,
                .material = material,
            };
        }

        /// Release the pipeline resources.
        pub fn deinit(self: *Self) void {
            defer self.vs_module.release();
            defer self.fs_module.release();
            defer self.gctx.releaseResource(self.bind_group);
            defer self.gctx.releaseResource(self.pipeline_layout);
        }
    };
}
