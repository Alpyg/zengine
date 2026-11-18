//! Frame timing: elapsed time, delta time and frame-rate statistics.

const std = @import("std");

const zsdl = @import("zsdl");
const zm = @import("zmath");

const z = @import("root.zig");

const TimeModule = @This();

pub fn init(_: TimeModule, ecs: *z.Ecs) void {
    _ = ecs.registerEcs(TimeModule);
}

pub const Time = struct {
    pub const RESOURCE = {};

    /// Total elapsed time in seconds.
    time: f64 = 0.0,

    /// Seconds since the previous update.
    delta_time: f32 = 0.0,

    /// Frames counted in the current FPS window.
    fps_counter: u32 = 0,

    /// Frames per second over the latest window.
    fps: f64 = 0.0,

    /// Exponentially smoothed CPU frame time in seconds.
    average_cpu_time: f64 = 0.0,

    /// Timestamp of the previous update, in SDL ticks (nanoseconds).
    previous_time: f64 = 0.0,

    /// Start timestamp of the current FPS window, in nanoseconds.
    fps_refresh_time: f64 = 0.0,

    /// Number of update ticks processed.
    cpu_frame_number: u64 = 0,

    /// GPU submit counter. Currently unused.
    gpu_frame_number: u64 = 0,
};

/// System: advances `Time` once per frame from SDL's clock.
pub const UpdateTime = z.System(z.Phase.first, struct {
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
