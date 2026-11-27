const std = @import("std");

const z = @import("z");
const zm = z.zmath;

pub const e = @import("ecs/ecs.zig");
pub const editor = @import("editor.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var app = z.Ecs.init(allocator);
    defer app.deinit();

    _ = app.register(z.Phase)
        .register(z.GfxModule)
        .register(z.TimeModule)
        .register(z.FpsModule)
        .register(z.GuiModule)
        .register(z.InputModule)
        .register(z.TransformModule)
        .register(z.RenderModule)
        .register(editor)
        .register(z.CameraModule)
        .register(@This());

    app.run();
}

pub const TestMaterial = z.Material(z.shaders.shader);

pub const Setup = z.System(z.Phase.startup, struct {
    pub fn run(
        ecs: *z.Ecs,
        gfx: z.Resource(*z.Gfx),
        materials: z.Resource(*z.Assets(TestMaterial)),
        meshes: z.Resource(*z.Assets(z.Mesh)),
    ) void {
        const player = ecs.new("Player");
        _ = ecs.add(player, .{
            z.Name{ .value = "Player" },
            z.Transform.from_mat(zm.inverse(zm.lookAtRh(
                zm.f32x4(0.0, 0.0, 5.0, 1.0),
                zm.f32x4(0.0, 0.0, 0.0, 1.0),
                zm.f32x4(0.0, 1.0, 0.0, 0.0),
            ))),
            z.GlobalTransform{},
            e.flycam.FlycamController{},
            z.Camera{},
        });

        const material = TestMaterial.init(gfx, .{}) catch |err|
            std.debug.panic("material init failed: {s}", .{@errorName(err)});
        const material_handle = materials.add(material) catch @panic("OOM");

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

        const mesh = z.MeshFor(z.shaders.shader).from(
            ecs.allocator,
            .{ .position = &positions, .color = &colors },
            &[_]u32{ 0, 1, 2 },
        ) catch @panic("mesh creation failed");
        const mesh_handle = meshes.add(mesh) catch @panic("OOM");

        const triangle = ecs.new("Triangle");
        _ = ecs.add(triangle, .{
            z.MeshRef{ .handle = mesh_handle },
            z.MaterialRef(TestMaterial){ .handle = material_handle },
            z.Transform{},
            z.GlobalTransform{},
        });
    }
});
