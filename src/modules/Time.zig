const std = @import("std");

const wgpu = @import("zgpu").wgpu;
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const zgui = @import("zgui");
const zm = @import("zmath");

const z = @import("../root.zig");

const TimeModule = @This();

pub fn init(_: TimeModule, ecs: *z.Ecs) void {
    _ = ecs.registerResource(Components.Time{})
        .registerSystems(Systems);
}

pub const Components = struct {
    pub const Time = struct {
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
};

const Systems = struct {
    const zflecs = @import("zflecs");

    pub const UpdateTime = z.System(struct {
        pub const phase = &z.Pipeline.First;

        pub fn run(
            r_gfx: z.Resource(z.Gfx),
            r_time: z.Resource(Components.Time),
        ) void {
            const gfx = r_gfx.get();
            const time = r_time.getMut();

            inline for (@typeInfo(Components.Time).@"struct".fields) |field| {
                @field(time, field.name) = @field(gfx.gctx.stats, field.name);
            }
        }
    });
};
