const std = @import("std");
const z = @import("z");

var scope_deinit_calls: u32 = 0;

test "Ecs.register recurses through namespaces and runs resource deinit" {
    const State = struct {
        var resource_deinited: bool = false;
    };

    const Namespace = struct {
        pub const TestResource = struct {
            value: u32 = 0,
            pub const RESOURCE = {};

            pub fn init(_: *z.Ecs) @This() {
                return .{};
            }

            pub fn deinit(_: *@This()) void {
                State.resource_deinited = true;
            }
        };

        pub const Bump = z.System(z.Phase.update, struct {
            pub fn run(resource: z.Resource(*TestResource)) void {
                resource.value += 1;
            }
        });
    };

    var ecs = z.Ecs.init(std.testing.allocator);
    _ = ecs.register(z.Phase);
    _ = ecs.register(Namespace);

    ecs.progress();
    try std.testing.expectEqual(
        @as(u32, 1),
        z.zflecs.singleton_get(ecs.world, Namespace.TestResource).?.value,
    );

    ecs.deinit();
    try std.testing.expect(State.resource_deinited);
}

test "module scope teardown removes systems, resources and deinit state" {
    const E = struct {
        const Counter = struct {
            pub const RESOURCE = {};
            value: u32 = 0,

            pub fn init(_: *z.Ecs) @This() {
                return .{};
            }

            pub fn deinit(_: *@This()) void {
                scope_deinit_calls += 1;
            }
        };

        const Bump = z.System(z.Phase.update, struct {
            pub fn run(counter: z.Resource(*Counter)) void {
                counter.value += 1;
            }
        });
    };

    scope_deinit_calls = 0;

    var ecs = z.Ecs.init(std.testing.allocator);
    defer ecs.deinit();

    _ = ecs.register(z.Phase);

    const handle = ecs.beginModule("test_mod");
    _ = ecs.register(E.Counter);
    _ = ecs.register(E.Bump);
    ecs.endModule();

    ecs.progress();
    try std.testing.expectEqual(@as(u32, 1), z.zflecs.singleton_get(ecs.world, E.Counter).?.value);

    ecs.deinitModule(handle, .unload);
    try std.testing.expectEqual(@as(u32, 1), scope_deinit_calls);
    try std.testing.expect(!ecs.hasResource(E.Counter));

    // Reloading the same module re-initializes the resource from scratch.
    const second = ecs.beginModule("test_mod");
    _ = ecs.register(E.Counter);
    _ = ecs.register(E.Bump);
    ecs.endModule();
    ecs.progress();
    try std.testing.expectEqual(@as(u32, 1), z.zflecs.singleton_get(ecs.world, E.Counter).?.value);
    ecs.deinitModule(second, .unload);
}

test "Ecs.add accepts a single component value" {
    const C = struct {
        pub const COMPONENT = {};
        value: u32 = 0,
    };

    var ecs = z.Ecs.init(std.testing.allocator);
    defer ecs.deinit();

    _ = ecs.register(C);

    const entity = ecs.new("e");
    _ = ecs.add(entity, C{ .value = 7 });

    const got = z.zflecs.get(ecs.world, entity, C);
    try std.testing.expect(got != null);
    try std.testing.expectEqual(@as(u32, 7), got.?.value);
}

test "resources persist across a hot reload teardown" {
    const Res = struct {
        pub const RESOURCE = {};
        value: u32 = 0,

        pub fn init(_: *z.Ecs) @This() {
            return .{};
        }
    };

    const Bump = z.System(z.Phase.update, struct {
        pub fn run(res: z.Resource(*Res)) void {
            res.value += 1;
        }
    });

    var ecs = z.Ecs.init(std.testing.allocator);
    defer ecs.deinit();

    _ = ecs.register(z.Phase);

    const handle = ecs.beginModule("persistent");
    _ = ecs.register(Res);
    _ = ecs.register(Bump);
    ecs.endModule();

    ecs.progress();
    try std.testing.expectEqual(@as(u32, 1), z.zflecs.singleton_get(ecs.world, Res).?.value);

    // Reload teardown keeps the resource value.
    ecs.deinitModule(handle, .reload);
    try std.testing.expectEqual(@as(u32, 1), z.zflecs.singleton_get(ecs.world, Res).?.value);

    // The next version re-registers the resource and its systems.
    const second = ecs.beginModule("persistent");
    _ = ecs.register(Res);
    _ = ecs.register(Bump);
    ecs.endModule();

    ecs.progress();
    try std.testing.expectEqual(@as(u32, 2), z.zflecs.singleton_get(ecs.world, Res).?.value);

    // Final unload removes it.
    ecs.deinitModule(second, .unload);
    try std.testing.expect(!ecs.hasResource(Res));
}
