const std = @import("std");
const z = @import("z");

test "MeshFor interleaves named attribute arrays from shader reflection" {
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

    var mesh = try z.MeshFor(z.shaders.shader).from(
        std.testing.allocator,
        .{ .position = &positions, .color = &colors },
        &[_]u32{ 0, 1, 2 },
    );
    defer mesh.deinit();

    try std.testing.expectEqual(@as(u32, 24), mesh.vertex_stride);
    try std.testing.expectEqual(@as(usize, 3), mesh.vertex_count);
    try std.testing.expectEqual(@as(usize, 3), mesh.index_count);
    try std.testing.expectEqual(@as(usize, 24 * 3), mesh.vertex_data.len);
    try std.testing.expectEqual(@as(usize, 4 * 3), mesh.index_data.len);

    const floats: [*]const f32 = @ptrCast(@alignCast(mesh.vertex_data.ptr));
    // vertex 0: position at offset 0, color at offset 12
    try std.testing.expectEqual(@as(f32, 0.0), floats[0]);
    try std.testing.expectEqual(@as(f32, 0.5), floats[1]);
    try std.testing.expectEqual(@as(f32, 1.0), floats[3]);
    // vertex 1 position starts at float 6
    try std.testing.expectEqual(@as(f32, -0.5), floats[6]);
}
