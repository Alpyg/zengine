//! Frame-rate limiting: target FPS and the pacing system that enforces it.

const zsdl = @import("zsdl");

const z = @import("root.zig");

/// SDL's precise delay is not exposed by zsdl yet. It sleeps for most of the
/// duration and spins for the remainder, avoiding whole-millisecond rounding.
extern fn SDL_DelayPrecise(ns: u64) void;

pub const Fps = struct {
    pub const RESOURCE = {};

    /// Target frames per second. Set to `0` (or a negative value) to disable
    /// the limiter.
    target: f64 = 60.0,

    /// Frame deadline from the previous update, in SDL ticks (nanoseconds).
    /// `0` until the limiter has seen its first frame.
    previous_time: f64 = 0.0,
};

/// System: sleeps at the end of the frame until the target frame time has
/// elapsed, capping the frame rate at `Fps.target`.
pub const LimitFps = z.System(z.Phase.last, struct {
    pub fn run(fps: z.Resource(*Fps)) void {
        if (fps.target <= 0.0) return;

        const target_ns = 1_000_000_000.0 / fps.target;
        const now: f64 = @floatFromInt(zsdl.getTicksNS());

        if (fps.previous_time == 0.0) {
            fps.previous_time = now;
            return;
        }

        // Schedule against the previous deadline instead of the wake time so
        // sleep overshoot is compensated for on the next frame.
        const deadline = fps.previous_time + target_ns;
        if (now < deadline) {
            SDL_DelayPrecise(@intFromFloat(deadline - now));
            fps.previous_time = deadline;
        } else {
            fps.previous_time = now;
        }
    }
});
