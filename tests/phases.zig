const std = @import("std");
const z = @import("z");

const Trace = struct {
    pub const RESOURCE = {};

    items: [16][]const u8 = undefined,
    len: usize = 0,

    pub fn init(_: *z.Ecs) Trace {
        return .{};
    }

    fn push(self: *Trace, item: []const u8) void {
        self.items[self.len] = item;
        self.len += 1;
    }

    fn reset(self: *Trace) void {
        self.len = 0;
    }
};

test "phases and subphases run in order" {
    const E = struct {
        const Set = enum {
            pub const PHASE = .{ .parent = z.Phase.update };

            a,
            b,
        };

    const Systems = struct {
        pub const First = z.System(z.Phase.first, struct {
            pub fn run(trace: z.Resource(*Trace)) void {
                trace.push("first");
            }
        });
        pub const Update = z.System(z.Phase.update, struct {
            pub fn run(trace: z.Resource(*Trace)) void {
                trace.push("update");
            }
        });
        pub const SetA = z.System(Set.a, struct {
            pub fn run(trace: z.Resource(*Trace)) void {
                trace.push("a");
            }
        });
        pub const SetB = z.System(Set.b, struct {
            pub fn run(trace: z.Resource(*Trace)) void {
                trace.push("b");
            }
        });
        pub const Last = z.System(z.Phase.last, struct {
            pub fn run(trace: z.Resource(*Trace)) void {
                trace.push("last");
            }
        });
    };

    var ecs = z.Ecs.init(std.testing.allocator);
    defer ecs.deinit();

    _ = ecs.registerModule(z.PhaseModule{})
        .registerEcs(E);

    ecs.progress();

    const trace = z.zflecs.singleton_get(ecs.world, Trace).?;
    for (trace.items[0..trace.len]) |item| std.debug.print("{s} ", .{item});
    std.debug.print("\n", .{});
    const expected = [_][]const u8{ "first", "update", "a", "b", "last" };
    try std.testing.expectEqualSlices([]const u8, &expected, trace.items[0..trace.len]);

    // Disabling a set value skips that value and everything chained after it,
    // but must not disable the top-level phases that follow.
    z.zflecs.singleton_get_mut(ecs.world, Trace).?.reset();
    ecs.setPhaseEnabled(E.Set.a, false);
    ecs.progress();
    const expected_without_a = [_][]const u8{ "first", "update", "last" };
    try std.testing.expectEqualSlices([]const u8, &expected_without_a, trace.items[0..trace.len]);

    // A top-level phase with no dependents can be disabled independently.
    ecs.setPhaseEnabled(E.Set, true);
    z.zflecs.singleton_get_mut(ecs.world, Trace).?.reset();
    ecs.setPhaseEnabled(z.Phase.last, false);
    ecs.progress();
    const expected_without_last = [_][]const u8{ "first", "update", "a", "b" };
    try std.testing.expectEqualSlices([]const u8, &expected_without_last, trace.items[0..trace.len]);
    ecs.setPhaseEnabled(z.Phase.last, true);
}
