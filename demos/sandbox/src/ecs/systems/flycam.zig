const std = @import("std");

const z = @import("z");
const zgui = z.zgui;
const zm = z.zmath;

pub const FlycamController = struct {
    pub const COMPONENT = {};

    speed: f32 = 2.0,
    sensitivity: f32 = 0.002,
};

pub const FlycamControls = z.System(z.Phase.update, struct {
    pub fn run(
        input: z.Resource(z.Input),
        time: z.Resource(z.Time),
        q_flycam: z.Query(.{ *z.Transform, FlycamController }, .{}),
    ) void {
        if (!input.isCursorDisabled()) return;

        var flycam_it = q_flycam.iter();
        defer flycam_it.deinit();
        var transform: *z.Transform, const controller: *const FlycamController = flycam_it.next() orelse return;

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
            if (input.getKey(.lshift).pressed) speed *= 1.5;

            transform.translation += move * zm.splat(zm.Vec, time.delta_time * speed);
        }

        var pitch, var yaw, _ = zm.quatToRollPitchYaw(transform.rotation);

        const d_mouse = input.getMouseDelta();
        yaw -= d_mouse[0] * controller.sensitivity; // yaw
        pitch -= d_mouse[1] * controller.sensitivity; // pitch
        pitch = std.math.clamp(pitch, -std.math.pi / 2.0 + 0.1, std.math.pi / 2.0 - 0.1);

        transform.rotation = zm.quatFromRollPitchYaw(pitch, yaw, 0);
    }
});

pub const DebugMovementSystem = z.System(z.Phase.pre_render, struct {
    pub fn run(
        q_flycam: z.Query(.{ *z.Transform, *z.GlobalTransform, *FlycamController }, .{}),
    ) void {
        var flycam_it = q_flycam.iter();
        defer flycam_it.deinit();
        var transform: *z.Transform, var global: *z.GlobalTransform, var controller: *FlycamController = flycam_it.next() orelse return;

        if (!z.GuiModule.isFrameStarted()) return;

        if (zgui.begin("Inspector", .{})) {
            zgui.labelText("##Transform", "Transform", .{});

            var rotation_euler = zm.loadArr3(zm.quatToRollPitchYaw(transform.rotation));

            _ = zgui.inputFloat4("Position", .{ .v = @ptrCast(&transform.translation) });
            _ = zgui.inputFloat4("Rotation", .{ .v = @ptrCast(&rotation_euler) });
            _ = zgui.inputFloat4("Scale", .{ .v = @ptrCast(&transform.scale) });

            transform.rotation = zm.quatFromRollPitchYaw(rotation_euler[0], rotation_euler[1], rotation_euler[2]);

            _ = zgui.inputFloat("Speed", .{ .v = @ptrCast(&controller.speed) });
            _ = zgui.inputFloat("Sensitivity", .{ .v = @ptrCast(&controller.sensitivity) });

            var global_rotation_euler = zm.loadArr3(zm.quatToRollPitchYaw(global.rotation()));

            var global_position = global.translation();
            var global_scale = global.scale();
            _ = zgui.inputFloat4("G Position", .{ .v = @ptrCast(&global_position) });
            _ = zgui.inputFloat4("G Rotation", .{ .v = @ptrCast(&global_rotation_euler) });
            _ = zgui.inputFloat4("G Scale", .{ .v = @ptrCast(&global_scale) });
        }
        zgui.end();
    }
});
