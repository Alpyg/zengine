const std = @import("std");

const zsdl = @import("zsdl");
const zm = @import("zmath");

const z = @import("../root.zig");

const TimeModule = @This();

pub fn init(_: TimeModule, ecs: *z.Ecs) void {
    _ = ecs.registerEcs(TimeModule);
}

pub const Time = struct {
    pub const RESOURCE = {};

    time: f64 = 0.0,
    delta_time: f32 = 0.0,
    fps_counter: u32 = 0,
    fps: f64 = 0.0,
    average_cpu_time: f64 = 0.0,
    previous_time: f64 = 0.0,
    fps_refresh_time: f64 = 0.0,
    cpu_frame_number: u64 = 0,
    gpu_frame_number: u64 = 0,
};

pub const UpdateTime = z.System(&z.Phase.First, struct {
    pub fn run(r_time: z.Resource(Time)) void {
        var time = r_time.getMut();

        const now_ns = zsdl.getTicksNS();
        const now: f64 = @floatFromInt(now_ns);
        const prev = time.previous_time;
        time.previous_time = now;

        if (prev == 0.0) {
            time.fps_refresh_time = now;
            return;
        }

        const dt_ns = now - prev;
        time.delta_time = @floatCast(dt_ns / 1_000_000_000.0);
        time.time += time.delta_time;

        time.fps_counter += 1;
        const fps_dt = (now - time.fps_refresh_time) / 1_000_000_000.0;
        if (fps_dt >= 0.1) {
            time.fps = @as(f64, @floatFromInt(time.fps_counter)) / fps_dt;
            time.fps_counter = 0;
            time.fps_refresh_time = now;
        }

        const alpha = 0.1;
        if (time.average_cpu_time == 0.0) {
            time.average_cpu_time = time.delta_time;
        } else {
            time.average_cpu_time =
                time.average_cpu_time * (1.0 - alpha) + @as(f64, time.delta_time) * alpha;
        }

        time.cpu_frame_number +%= 1;
    }
});
