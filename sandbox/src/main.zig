const std = @import("std");


const z = @import("z");
const zm = z.zmath;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    z.allocator = allocator;

    var app = z.Ecs.init();
    defer app.deinit();

    _ = app.registerModule(z.GfxModule{})
        .registerModule(z.TimeModule{})
        .registerModule(z.GuiModule{})
        .registerModule(z.InputModule{})
        .registerModule(z.TransformModule{})
        .registerModule(z.DebugModule{})
        .registerModule(z.CameraModule{})
        .registerModule(z.RenderModule{});

    setup(&app);

    app.run();
}

fn setup(app: *z.Ecs) void{
    const player = app.new("Player");
    _ = app.add(player, .{
        z.Name{ .value = "Player" },
        z.Camera{},
        z.Transform.from_mat(zm.inverse(zm.lookAtRh(
            zm.f32x4(0.0, 0.0, 5.0, 1.0),
            zm.f32x4(0.0, 0.0, 0.0, 1.0),
            zm.f32x4(0.0, 1.0, 0.0, 0.0),
        ))),
        z.GlobalTransform{},
    });

    const material = z.StandardMaterial.init(.{
        .object_to_clip = zm.identity(),
    });

    const triangle = app.new("Triangle");
    _ = app.add(triangle, .{
        z.TriangleMesh.init(
            .{
                .position = @constCast(&[_][3]f32{
                    .{ 0.0, 0.5, 0.0 },
                    .{ -0.5, -0.5, 0.0 },
                    .{ 0.5, -0.5, 0.0 },
                }),
                .color = @constCast(&[_][3]f32{
                    .{ 1.0, 0.0, 0.0 },
                    .{ 0.0, 1.0, 0.0 },
                    .{ 0.0, 0.0, 1.0 },
                }),
            },
            @constCast(&[_]u32{ 0, 1, 2 }),
        ),
        z.Transform{},
        z.GlobalTransform{},
        z.RenderPipeline.init(material),
    });
}
