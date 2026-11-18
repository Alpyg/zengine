const std = @import("std");
const z = @import("z");

test "resource pointers enforce const and mutable access" {
    const E = struct {
        const Counter = struct {
            pub const RESOURCE = {};
            value: u32 = 0,

            pub fn init(_: *z.Ecs) @This() {
                return .{};
            }
        };

        const Seen = struct {
            pub const RESOURCE = {};
            value: u32 = 0,
        };

        const Bump = z.System(z.Phase.update, struct {
            pub fn run(counter: z.Resource(*Counter)) void {
                counter.value += 1;
            }
        });

        const Copy = z.System(z.Phase.post_update, struct {
            pub fn run(counter: z.Resource(Counter), seen: z.Resource(*Seen)) void {
                seen.value = counter.value;
            }
        });
    };

    comptime {
        if (z.Resource(E.Counter) != *const E.Counter)
            @compileError("Resource(T) must resolve to *const T");
        if (z.Resource(*E.Counter) != *E.Counter)
            @compileError("Resource(*T) must resolve to *T");
        if (z.Resource(*const E.Counter) != *const E.Counter)
            @compileError("Resource(*const T) must resolve to *const T");
    }

    var ecs = z.Ecs.init(std.testing.allocator);
    defer ecs.deinit();

    _ = ecs.registerModule(z.PhaseModule{})
        .registerEcs(E);
    ecs.progress();
    const counter = z.zflecs.singleton_get(ecs.world, E.Counter).?;
    const seen = z.zflecs.singleton_get(ecs.world, E.Seen).?;
    try std.testing.expectEqual(@as(u32, 1), counter.value);
    try std.testing.expectEqual(@as(u32, 1), seen.value);

    ecs.progress();
    try std.testing.expectEqual(@as(u32, 2), counter.value);
    try std.testing.expectEqual(@as(u32, 2), seen.value);
}
