//! Meshes: CPU-side interleaved vertex/index data and GPU buffers. `Mesh.from`
//! packs attributes into an interleaved layout; `upload` copies the data into
//! vertex/index buffers through a transfer buffer.

const std = @import("std");

const zsdl = @import("zsdl");

const z = @import("../root.zig");

/// GPU buffers backing a mesh plus the counts and stride needed to draw it.
pub const GpuMesh = struct {
    vertex_buffer: *zsdl.GPUBuffer,
    index_buffer: *zsdl.GPUBuffer,
    vertex_count: u32,
    index_count: u32,
    vertex_stride: u32,
};

/// CPU-side mesh data, owned by `Assets(Mesh)`.
pub const Mesh = struct {
    /// Interleaved vertex bytes (one row per vertex).
    vertex_data: []u8,
    /// 32-bit index bytes.
    index_data: []u8,

    vertex_count: usize,
    index_count: usize,
    /// Bytes per interleaved vertex.
    vertex_stride: u32,

    allocator: std.mem.Allocator,

    pub fn deinit(self: *Mesh) void {
        self.allocator.free(self.vertex_data);
        self.allocator.free(self.index_data);
    }

    /// Build a Mesh from a tuple of `.{ format, slice }` pairs and an index array.
    ///
    /// The data may be passed as a slice or as a pointer to an array:
    ///
    /// ```zig
    /// const mesh = try Mesh.from(allocator, .{
    ///     .{ .float3, &[_][3]f32{ .{0,0,0}, .{1,0,0}, .{0,1,0} } },
    ///     .{ .float3, &[_][3]f32{ .{1,0,0}, .{0,1,0}, .{0,0,1} } },
    /// }, &[_]u32{ 0, 1, 2 });
    /// ```
    pub fn from(
        allocator: std.mem.Allocator,
        attributes: anytype,
        indices: []const u32,
    ) !Mesh {
        const A = @TypeOf(attributes);
        const info = @typeInfo(A).@"struct";

        if (!info.is_tuple)
            @compileError("Mesh.from: attributes must be a tuple of .{ format, slice } pairs");

        const attr_count = info.field_names.len;
        if (attr_count == 0) return error.NoAttributes;

        const first_pair = @field(attributes, info.field_names[0]);
        const first_items = attributeSlice(first_pair[1]);
        const vertex_count: u32 = @intCast(first_items.len);

        inline for (info.field_names[1..]) |name| {
            const pair = @field(attributes, name);
            const items = attributeSlice(pair[1]);
            if (items.len != first_items.len) {
                std.debug.panic(
                    "Mesh.from: attribute {s} has {d} elements, expected {d}",
                    .{ name, items.len, first_items.len },
                );
            }
        }

        const stride = comptime blk: {
            var s: u32 = 0;
            for (info.field_types) |FT| {
                const pair_info = @typeInfo(FT).@"struct";
                if (!pair_info.is_tuple or pair_info.field_types.len != 2)
                    @compileError("Mesh.from: each attribute must be .{ format, slice }, got " ++ @typeName(FT));

                const SliceT = pair_info.field_types[1];
                const ElemT = std.meta.Elem(SliceT);
                s += @sizeOf(ElemT);
            }
            break :blk s;
        };

        const vertex_data = try allocator.alloc(u8, @as(usize, stride) * vertex_count);
        errdefer allocator.free(vertex_data);

        const index_data = try allocator.alloc(u8, indices.len * @sizeOf(u32));
        errdefer allocator.free(index_data);

        var offset: u32 = 0;
        inline for (info.field_names) |name| {
            const pair = @field(attributes, name);
            const items = attributeSlice(pair[1]);
            const ElemT = std.meta.Elem(@TypeOf(pair[1]));
            const elem_size: u32 = @sizeOf(ElemT);

            for (items, 0..) |v, vi| {
                const dst = vertex_data[vi * stride + offset ..][0..elem_size];
                const src = @as([elem_size]u8, @bitCast(v));
                @memcpy(dst, &src);
            }

            offset += elem_size;
        }

        @memcpy(index_data, std.mem.sliceAsBytes(indices));

        return .{
            .vertex_data = vertex_data,
            .index_data = index_data,
            .vertex_count = vertex_count,
            .index_count = indices.len,
            .vertex_stride = stride,
            .allocator = allocator,
        };
    }

    /// Uploads the CPU data into new vertex/index buffers using `cmd`.
    /// The transfer buffer is deferred on `gfx` until submission.
    pub fn upload(self: *const Mesh, gfx: *z.Gfx, cmd: *zsdl.GPUCommandBuffer) !GpuMesh {
        const vertex_buffer = zsdl.createGPUBuffer(gfx.device, &.{
            .usage = .{ .vertex = true },
            .size = @intCast(self.vertex_data.len),
        }) catch |err| {
            std.log.err("createGPUBuffer(vertex) failed: {s}", .{zsdl.getError() orelse "unknown"});
            return err;
        };
        errdefer zsdl.releaseGPUBuffer(gfx.device, vertex_buffer);

        const index_buffer = zsdl.createGPUBuffer(gfx.device, &.{
            .usage = .{ .index = true },
            .size = @intCast(self.index_data.len),
        }) catch |err| {
            std.log.err("createGPUBuffer(index) failed: {s}", .{zsdl.getError() orelse "unknown"});
            return err;
        };
        errdefer zsdl.releaseGPUBuffer(gfx.device, index_buffer);

        const total_size: u32 = @intCast(self.vertex_data.len + self.index_data.len);
        const transfer_buffer = zsdl.createGPUTransferBuffer(gfx.device, &.{
            .usage = .upload,
            .size = total_size,
        }) catch |err| {
            std.log.err("createGPUTransferBuffer failed: {s}", .{zsdl.getError() orelse "unknown"});
            return err;
        };
        errdefer zsdl.releaseGPUTransferBuffer(gfx.device, transfer_buffer);

        const mapped = zsdl.mapGPUTransferBuffer(gfx.device, transfer_buffer, false) catch |err| {
            std.log.err("mapGPUTransferBuffer failed: {s}", .{zsdl.getError() orelse "unknown"});
            return err;
        };
        const mapped_bytes: [*]u8 = @ptrCast(mapped);
        @memcpy(mapped_bytes[0..self.vertex_data.len], self.vertex_data);
        @memcpy(mapped_bytes[self.vertex_data.len..][0..self.index_data.len], self.index_data);
        zsdl.unmapGPUTransferBuffer(gfx.device, transfer_buffer);

        const copy_pass = zsdl.beginGPUCopyPass(cmd);

        zsdl.uploadToGPUBuffer(copy_pass, &.{
            .transfer_buffer = transfer_buffer,
            .offset = 0,
        }, &.{
            .buffer = vertex_buffer,
            .offset = 0,
            .size = @intCast(self.vertex_data.len),
        }, false);

        zsdl.uploadToGPUBuffer(copy_pass, &.{
            .transfer_buffer = transfer_buffer,
            .offset = @intCast(self.vertex_data.len),
        }, &.{
            .buffer = index_buffer,
            .offset = 0,
            .size = @intCast(self.index_data.len),
        }, false);

        zsdl.endGPUCopyPass(copy_pass);

        // The transfer buffer must stay alive until the command buffer has
        // been submitted. Gfx releases these after submission.
        try gfx.deferTransferBuffer(transfer_buffer);

        return .{
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .vertex_count = @intCast(self.vertex_count),
            .index_count = @intCast(self.index_count),
            .vertex_stride = self.vertex_stride,
        };
    }
};

fn attributeSlice(data: anytype) []const std.meta.Elem(@TypeOf(data)) {
    return data;
}

test "Mesh.from interleaves vertex attributes" {
    const positions = [_][3]f32{
        .{ 0.0, 0.5, 0.0 },
        .{ -0.5, -0.5, 0.0 },
        .{ 0.5, -0.5, 0.0 },
    };
    const colors = [_][3]f32{
        .{ 1.0, 0.0, 0.0 },
        .{ 0.0, 1.0, 0.0 },
        .{ 0.0, 0.0, 1.0 },
    };

    var mesh = try Mesh.from(std.testing.allocator, .{
        .{ .float3, &positions },
        .{ .float3, &colors },
    }, &[_]u32{ 0, 1, 2 });
    defer mesh.deinit();

    try std.testing.expectEqual(@as(usize, 3), mesh.vertex_count);
    try std.testing.expectEqual(@as(usize, 3), mesh.index_count);
    try std.testing.expectEqual(@as(u32, 24), mesh.vertex_stride);

    const floats: [*]const f32 = @ptrCast(@alignCast(mesh.vertex_data.ptr));
    try std.testing.expectEqual(@as(f32, 0.0), floats[0]);
    try std.testing.expectEqual(@as(f32, 0.5), floats[1]);
    try std.testing.expectEqual(@as(f32, 1.0), floats[3]);
}

/// Build an interleaved mesh from one slice per reflected vertex input.
///
/// `attributes` must be a struct whose fields match the shader input names,
/// e.g. `.{ .position = positions, .color = colors }`.
pub fn fromAttributes(
    allocator: std.mem.Allocator,
    comptime layout: anytype,
    comptime stride: u32,
    attributes: anytype,
    indices: []const u32,
) !Mesh {
    const A = @TypeOf(attributes);
    if (@typeInfo(A) != .@"struct") {
        @compileError("Mesh attributes must be a struct of named slices");
    }
    if (comptime layout.len == 0) return error.NoAttributes;

    inline for (layout) |input| {
        if (!@hasField(A, input.name)) {
            @compileError("Missing mesh attribute '" ++ input.name ++ "' required by the shader");
        }
    }

    const first_items = attributeSlice(@field(attributes, layout[0].name));
    const vertex_count = first_items.len;

    inline for (layout, 0..) |input, i| {
        if (i == 0) continue;
        const items = attributeSlice(@field(attributes, input.name));
        if (items.len != vertex_count) {
            std.debug.panic(
                "Mesh attribute '{s}' has {d} elements, expected {d}",
                .{ input.name, items.len, vertex_count },
            );
        }
    }

    const vertex_data = try allocator.alloc(u8, @as(usize, stride) * vertex_count);
    errdefer allocator.free(vertex_data);

    const index_data = try allocator.alloc(u8, indices.len * @sizeOf(u32));
    errdefer allocator.free(index_data);

    inline for (layout) |input| {
        const items = attributeSlice(@field(attributes, input.name));
        const ElemT = std.meta.Elem(@TypeOf(items));
        const size = @sizeOf(ElemT);

        if (size != input.size) {
            @compileError("Mesh attribute '" ++ input.name ++ "' size does not match shader reflection");
        }

        for (items, 0..) |value, vi| {
            const dst = vertex_data[vi * stride + input.offset ..][0..size];
            @memcpy(dst, std.mem.asBytes(&value));
        }
    }

    @memcpy(index_data, std.mem.sliceAsBytes(indices));

    return .{
        .vertex_data = vertex_data,
        .index_data = index_data,
        .vertex_count = vertex_count,
        .index_count = indices.len,
        .vertex_stride = stride,
        .allocator = allocator,
    };
}

/// Mesh helper for a compiled shader. `Vertex` is generated from the shader's
/// reflected vertex inputs, and `from` accepts one named slice per input.
pub fn MeshFor(comptime S: type) type {
    comptime {
        if (!@hasDecl(S, "Vertex") or !@hasDecl(S, "vertex_inputs") or
            !@hasDecl(S, "vertex_stride"))
        {
            @compileError("MeshFor expects a compiled shader struct with vertex reflection");
        }
    }

    return struct {
        pub const Vertex = S.Vertex;

        pub fn from(allocator: std.mem.Allocator, attributes: anytype, indices: []const u32) !Mesh {
            return fromAttributes(allocator, S.vertex_inputs, S.vertex_stride, attributes, indices);
        }
    };
}
