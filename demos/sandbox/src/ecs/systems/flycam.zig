const std = @import("std");

const z = @import("z");
const zm = z.zmath;

pub const FlycamController = struct {
    speed: f32 = 2.0,
    sensitivity: f32 = 0.002,
};

pub const Systems = struct {
    pub const FlycamControls = z.System(struct {
        pub const phase = &z.Pipeline.PreRender;

        pub fn run(
            r_input: z.Resource(z.Input),
            r_time: z.Resource(z.Time),
            q_flycam: z.Query(.{ z.Transform, FlycamController }, .{}),
        ) void {
            const input = r_input.get();
            const time = r_time.get();

            if (!input.isCursorDisabled()) return;

            var flycam_it = q_flycam.iter();
            var transform: *z.Transform, const controller: *FlycamController = flycam_it.next() orelse return;

            var forward = transform.forward();
            forward[1] = 0;
            forward = zm.normalize3(forward);

            var right = transform.right();
            right[1] = 0;
            right = zm.normalize3(right);

            const up = zm.Vec{ 0, 1, 0, 0 };

            var move = zm.Vec{ 0, 0, 0, 0 };
            if (input.getKey(.w).pressed) move += forward;
            if (input.getKey(.s).pressed) move -= forward;
            if (input.getKey(.a).pressed) move -= right;
            if (input.getKey(.d).pressed) move += right;
            if (input.getKey(.e).pressed) move += up;
            if (input.getKey(.q).pressed) move -= up;
            move = zm.normalize3(move);

            if (!zm.any(zm.isNan(move), 3)) {
                var speed = controller.speed;
                if (input.getKey(.left_shift).pressed) speed *= 1.5;

                transform.translation += move * zm.splat(zm.Vec, time.delta_time * speed);
            }

            var angles = zm.quatToRollPitchYaw(transform.rotation);

            const d_mouse = input.getMouseDelta();
            angles[1] -= d_mouse[0] * controller.sensitivity; // yaw
            angles[0] -= d_mouse[1] * controller.sensitivity; // pitch
            angles[0] = std.math.clamp(angles[0], -std.math.pi / 2.0 + 0.1, std.math.pi / 2.0 - 0.1);

            transform.rotation = zm.normalize4(zm.quatFromRollPitchYaw(angles[0], angles[1], angles[2]));
        }
    });

    pub const DebugMovementSystem = z.System(struct {
        pub const phase = &z.Pipeline.Update;

        const zgui = z.zgui;

        pub fn run(
            q_flycam: z.Query(.{ z.Transform, FlycamController }, .{}),
        ) void {
            var flycam_it = q_flycam.iter();
            var transform: *z.Transform, const controller: *FlycamController = flycam_it.next() orelse return;

            if (zgui.begin("Main", .{})) {
                if (zgui.begin("Inspector", .{})) {
                    zgui.labelText("##Transform", "Transform", .{});

                    var rotation_euler = zm.loadArr3(zm.quatToRollPitchYaw(transform.rotation));

                    _ = zgui.inputFloat3("Position", .{ .v = @ptrCast(&transform.translation) });
                    _ = zgui.inputFloat3("Rotation", .{ .v = @ptrCast(&rotation_euler) });
                    _ = zgui.inputFloat3("Scale", .{ .v = @ptrCast(&transform.scale) });

                    transform.rotation = zm.quatFromRollPitchYaw(rotation_euler[0], rotation_euler[1], rotation_euler[2]);

                    _ = zgui.inputFloat("Speed", .{ .v = @ptrCast(&controller.speed) });
                    _ = zgui.inputFloat("Sensitivity", .{ .v = @ptrCast(&controller.sensitivity) });
                }
                zgui.end();
            }
            zgui.end();
        }
    });
};
