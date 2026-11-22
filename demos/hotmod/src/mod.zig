//! Hot-reloadable gameplay module.
//!
//! State lives in the ECS world (the `Spinner` entity and its `Spin`
//! component), so it survives reloads. Rebuild with `zig build hotmod-module`
//! and the running host swaps this code in.

const std = @import("std");

const z = @import("z");

const HotMod = @This();

/// Edit this value and rebuild to see the new rate take effect without
/// resetting the accumulator.
const spin_speed: f32 = 0.01;

pub const Spin = struct {
    pub const COMPONENT = {};
    value: f32 = 0,
};

pub const Systems = struct {
    pub const Tick = z.System(z.Phase.update, struct {
        pub fn run(q: z.Query(.{*Spin}, .{})) void {
            var it = q.iter();
            while (it.next()) |spin| {
                const before = spin.value;
                spin.value += spin_speed;

                if (@floor(before) != @floor(spin.value)) {
                    std.log.info("spin = {d:.2} (speed {d:.3})", .{ spin.value, spin_speed });
                }
            }
        }
    });
};

const Mod = struct {
    pub fn init(ecs: *z.Ecs) void {
        _ = ecs.register(HotMod);

        // Idempotent across reloads: the entity persists, so the accumulator
        // keeps its value while the system code is replaced.
        if (z.zflecs.lookup(ecs.world, "Spinner") == 0) {
            const entity = ecs.new("Spinner");
            _ = ecs.add(entity, .{Spin{}});
        }
    }
};

const desc = z.hot.descriptor(z.Ecs, Mod);

export fn zengine_module_v1() *const z.hot.ModuleDesc {
    return desc;
}
