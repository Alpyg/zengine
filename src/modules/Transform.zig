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
}

pub const Components = struct {
    pub const Transform = struct {
        const Self = @This();

        translation: zm.Vec = .{ 0, 0, 0, 1 },
        rotation: zm.Quat = zm.qidentity(),
        scale: zm.Vec = .{ 1, 1, 1, 1 },

        pub inline fn mat(self: *const Self) zm.Mat {
            const T = zm.translationV(self.translation);
            const R = zm.quatToMat(self.rotation);
            const S = zm.scalingV(self.scale);

            return zm.mul(zm.mul(T, R), S);
        }

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

        pub fn run(q: Query(.{ z.Transform, z.GlobalTransform, ?Parent(z.GlobalTransform) }, .{})) void {
            var it = q.iter();
            var i: usize = 0;
            while (it.next()) |t| : (i += 1) {
                const transform = t[0];
                const global = t[1];
                const parent = t[2];

                if (parent) |p| {
                    global.transform = zm.mul(p.transform, transform.mat());
                } else {
                    global.transform = transform.mat();
                }
            }
        }
    });
};
