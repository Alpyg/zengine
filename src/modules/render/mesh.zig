const std = @import("std");
const assert = std.debug.assert;

const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;

const z = @import("../../root.zig");

pub const VertexBuffers = struct {
    vertex: zgpu.BufferHandle,
    index: zgpu.BufferHandle,
};

pub fn Mesh(comptime attribute_formats: anytype) type {
    const attribute_fields = comptime @typeInfo(@TypeOf(attribute_formats)).@"struct".fields;

    var mesh_attributes: [attribute_fields.len]std.builtin.Type.StructField = undefined;
    inline for (attribute_fields, 0..) |field, i| {
        mesh_attributes[i] = std.builtin.Type.StructField{
            .name = field.name,
            .type = vertexFormatToType(field.defaultValue().?),
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = field.alignment,
        };
    }

    const AttributeData = @Type(.{
        .@"struct" = std.builtin.Type.Struct{
            .layout = .auto,
            .fields = &mesh_attributes,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });

    return struct {
        pub const COMPONENT = {};
        const Self = @This();
        pub const Attributes = AttributeData;

        vertex_attributes: [attribute_fields.len]wgpu.VertexAttribute = undefined,
        vertex_buffer_layout: ?wgpu.VertexBufferLayout = undefined,

        vertex_buffer: zgpu.BufferHandle = undefined,
        index_buffer: zgpu.BufferHandle = undefined,

        vertex_count: u32 = 0,
        index_count: u32 = 0,

        pub fn init(attributes: Attributes, indices: []u32) Self {
            var self = Self{};
            self.initBuffers(attributes, indices);
            return self;
        }

        fn initBuffers(self: *Self, attributes: Attributes, indices: []u32) void {
            const gctx = z.gctx;

            const vertex_size = sum: {
                var sum: u32 = 0;
                const fields = comptime @typeInfo(Attributes).@"struct".fields;
                inline for (fields) |field| {
                    sum += vertexFormatTypeSize(field.type);
                }
                break :sum sum;
            };

            const vertex_count = blk: {
                const fields = @typeInfo(Attributes).@"struct".fields;
                if (fields.len == 0) break :blk 0;
                const field = @field(attributes, fields[0].name);
                break :blk field.len;
            };

            const vertex_buffer = gctx.createBuffer(.{
                .usage = .{ .copy_dst = true, .vertex = true },
                .size = vertex_size * vertex_count,
            });

            const index_buffer = gctx.createBuffer(.{
                .usage = .{ .copy_dst = true, .index = true },
                .size = indices.len * @sizeOf(u32),
            });

            var offset: u32 = 0;
            var vertex_data = z.allocator.alloc(u8, vertex_size * vertex_count) catch unreachable;
            defer z.allocator.free(vertex_data);

            inline for (attribute_fields) |field| {
                const field_value = @field(attributes, field.name);
                if (field_value.len > 0) {
                    for (field_value, 0..) |value, i| {
                        const dst = vertex_data[i * vertex_size + offset .. i * vertex_size + offset + @sizeOf(@TypeOf(field_value[0]))];
                        const src = @as([@sizeOf(@TypeOf(field_value[0]))]u8, @bitCast(value))[0..];
                        @memcpy(dst, src);
                    }
                    offset += @sizeOf(@TypeOf(field_value[0]));
                }
            }

            gctx.queue.writeBuffer(
                gctx.lookupResource(vertex_buffer).?,
                0,
                u8,
                vertex_data[0..],
            );
            gctx.queue.writeBuffer(
                gctx.lookupResource(index_buffer).?,
                0,
                u32,
                indices[0..],
            );

            self.vertex_buffer = vertex_buffer;
            self.vertex_count = @intCast(vertex_count);
            self.index_buffer = index_buffer;
            self.index_count = @intCast(indices.len);
        }

        pub fn deinit(self: *Self) void {
            z.gctx.releaseResource(self.vertex_buffer);
            z.gctx.releaseResource(self.index_buffer);
        }
    };
}

fn vertexFormatToType(format: wgpu.VertexFormat) type {
    return switch (format) {
        .uint8x2 => [][2]u8,
        .uint8x4 => [][4]u8,

        .sint8x2 => [][2]i8,
        .sint8x4 => [][4]i8,

        .unorm8x2 => [][2]u8,
        .unorm8x4 => [][4]u8,

        .snorm8x2 => [][2]i8,
        .snorm8x4 => [][4]i8,

        .uint16x2 => [][2]u16,
        .uint16x4 => [][4]u16,

        .sint16x2 => [][2]i16,
        .sint16x4 => [][4]i16,

        .unorm16x2 => [][2]u16,
        .unorm16x4 => [][4]u16,

        .snorm16x2 => [][2]i16,
        .snorm16x4 => [][4]i16,

        .float16x2 => [][2]f16,
        .float16x4 => [][4]f16,

        .float32 => []f32,
        .float32x2 => [][2]f32,
        .float32x3 => [][3]f32,
        .float32x4 => [][4]f32,

        .uint32 => []u32,
        .uint32x2 => [][2]u32,
        .uint32x3 => [][3]u32,
        .uint32x4 => [][4]u32,

        .sint32 => []i32,
        .sint32x2 => [][2]i32,
        .sint32x3 => [][3]i32,
        .sint32x4 => [][4]i32,

        else => unreachable,
    };
}

fn vertexFormatTypeSize(format: anytype) u32 {
    switch (@typeInfo(format)) {
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice) {
                return @sizeOf(ptr_info.child);
            } else {
                return @sizeOf(format);
            }
        },
        else => {
            return @sizeOf(format);
        },
    }
}
