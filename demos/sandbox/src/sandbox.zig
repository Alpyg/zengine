const std = @import("std");

const z = @import("z");
const zm = z.zmath;

pub const e = @import("ecs/ecs.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var app = z.Ecs.init(allocator);
    defer app.deinit();

    _ = app.registerModule(z.PhaseModule{})
        .registerModule(z.GfxModule{})
        .registerModule(z.TimeModule{})
        .registerModule(z.GuiModule{})
        .registerModule(z.InputModule{})
        .registerModule(z.TransformModule{})
        .registerModule(z.RenderModule{})
        .registerModule(z.DebugModule{})
        .registerModule(z.CameraModule{})
        .registerModule(z.MaterialPlugin(TestMaterial){})
        .registerEcs(@This());

    app.run();
}

pub const TestMaterial = z.Material(
    z.shaders.shader,
    struct { object_to_clip: zm.Mat },
);

pub const Setup = z.System(z.Phase.first, struct {
    var done: bool = false;

    pub fn run(
        ecs: *z.Ecs,
        gfx: z.Resource(*z.Gfx),
        materials: z.Resource(*z.Assets(TestMaterial)),
        meshes: z.Resource(*z.Assets(z.Mesh)),
    ) void {
        if (done) return;

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

        const material = TestMaterial.init(gfx, .{ .object_to_clip = zm.identity() }) catch |err|
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

        done = true;
    }
});
