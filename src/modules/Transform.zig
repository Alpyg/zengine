const std = @import("std");

const wgui = @import("zgpu").wgpu;
const zflecs = @import("zflecs");
const zgui = @import("zgui");
const zm = @import("zmath");

const z = @import("../root.zig");
const Ecs = z.Ecs;
const Parent = z.Parent;
const Pipeline = z.Pipeline;
const Query = z.Query;
const Resource = z.Resource;
const System = z.System;

const TransformModule = @This();

pub fn init(_: TransformModule, ecs: *Ecs) void {
    _ = ecs.registerComponents(Components)
        .registerSystems(Systems);

    const parent = ecs.new("Test Parent");
    _ = ecs.add(parent, .{
        Components.Name{ .value = "Parent" },
        Components.Transform{ .translation = .{ 1, 2, 3, 0 } },
        Components.GlobalTransform{ .transform = zm.identity() },
    });

    const child = ecs.new("Test Child");
    _ = ecs.add(child, .{
        Components.Name{ .value = "Child" },
        Components.Transform{ .translation = .{ 3, 2, 1, 0 } },
        Components.GlobalTransform{},
    });
    zflecs.add_pair(ecs.world, child, zflecs.ChildOf, parent);
}

pub const Components = struct {
    pub const Transform = struct {
        const Self = @This();

        translation: zm.Vec = .{ 0, 0, 0, 1 },
        rotation: zm.Quat = zm.qidentity(),
        scale: zm.Vec = .{ 1, 1, 1, 1 },

        pub inline fn from_mat(m: zm.Mat) Self {
            const scale = zm.f32x4(
                zm.length3(m[0])[0],
                zm.length3(m[1])[0],
                zm.length3(m[2])[0],
                0.0,
            );

            const rotation_mat = zm.Mat{
                m[0] / zm.splat(zm.Vec, scale[0]),
                m[1] / zm.splat(zm.Vec, scale[1]),
                m[2] / zm.splat(zm.Vec, scale[2]),
                .{ 0, 0, 0, 1 },
            };

            return Self{
                .translation = m[3],
                .rotation = zm.quatFromMat(rotation_mat),
                .scale = scale,
            };
        }

        pub inline fn forward(self: *const Self) zm.Vec {
            return -zm.normalize3(zm.rotate(self.rotation, zm.Vec{ 0, 0, 1, 0 }));
        }

        pub inline fn right(self: *const Self) zm.Vec {
            return zm.normalize3(zm.rotate(self.rotation, zm.Vec{ 1, 0, 0, 0 }));
        }

        pub inline fn up(self: *const Self) zm.Vec {
            return zm.normalize3(zm.rotate(self.rotation, zm.Vec{ 0, 1, 0, 0 }));
        }

        pub inline fn getYawPitch(self: *const Self) [2]f32 {
            const yaw_pitch = [2]f32{ 0, 0 };

            zm.quatToAxisAngle(self.rotation, zm.Vec{ 0, 1, 0, 0 }, &yaw_pitch);
            zm.quatToAxisAngle(self.rotation, zm.Vec{ 1, 0, 0, 0 }, &yaw_pitch[1]);

            return yaw_pitch;
        }
    };
    pub const GlobalTransform = struct {
        const Self = @This();

        transform: zm.Mat = undefined,

        pub inline fn translation(self: *const Self) zm.Vec {
            return self.transform[3];
        }

        pub inline fn rotation(self: *const Self) zm.Vec {
            const s = self.scale();
            const rotation_mat = zm.Mat{
                self.transform[0] / zm.splat(zm.Vec, s[0]),
                self.transform[1] / zm.splat(zm.Vec, s[1]),
                self.transform[2] / zm.splat(zm.Vec, s[2]),
                .{ 0, 0, 0, 1 },
            };
            return zm.quatFromMat(rotation_mat);
        }

        pub inline fn scale(self: *const Self) zm.Vec {
            return zm.f32x4(
                zm.length3(self.transform[0])[0],
                zm.length3(self.transform[1])[0],
                zm.length3(self.transform[2])[0],
                0.0,
            );
        }
    };

    pub const Name = struct { value: []const u8 };
};

const Systems = struct {
    pub const PropagateParentTransform = System(struct {
        pub const phase = &Pipeline.PostUpdate;

        pub fn run(q: Query(.{ Components.Transform, Components.GlobalTransform, ?Parent(Components.GlobalTransform) }, .{})) void {
            var it = q.iter();
            var i: usize = 0;
            while (it.next()) |t| : (i += 1) {
                const transform = t[0];
                const global = t[1];

                if (t[2]) |parent| {
                    std.log.info("\n\n{any} {any} {any}\n\n", .{ transform, global, parent });
                } else {
                    std.log.info("\n\n{any} {any}\n\n", .{ transform, global });
                }
            }
        }
    });
};
