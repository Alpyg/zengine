const std = @import("std");

const zflecs = @import("zflecs");

const z = @import("root.zig");

pub fn create(comptime Components: type, comptime Systems: type) type {
    return struct {
        pub fn init() !void {
            z.world = zflecs.init();

            try registerComponents(Components);
            try registerSystems(Systems);
        }

        pub fn deinit() void {
            deinitSystems(Systems);

            _ = zflecs.fini(z.world);
        }

        pub fn progress() void {
            _ = zflecs.progress(z.world, 0);
        }

        fn registerComponents(comptime T: type) !void {
            const decls = @typeInfo(T).@"struct".decls;
            inline for (decls) |decl| {
                const Child = @field(T, decl.name);
                if (@TypeOf(Child) == type) {
                    if (@sizeOf(Child) > 0) {
                        zflecs.COMPONENT(z.world, Child);
                        std.log.debug("registered component `{s}`", .{decl.name});
                    } else {
                        zflecs.TAG(z.world, Child);
                        std.log.debug("registered tag `{s}`", .{decl.name});
                    }
                }
            }
        }

        fn registerSystems(comptime T: type) !void {
            if (isSystem(T)) {
                _ = zflecs.ADD_SYSTEM(z.world, T.name, T.phase.*, T.run);
                std.log.debug("registered system `{s}`", .{T.name});

                if (@hasDecl(T, "init")) try T.init(z.world);
            } else {
                const decls = @typeInfo(T).@"struct".decls;
                inline for (decls) |decl| {
                    const Child = @field(T, decl.name);
                    if (@TypeOf(Child) != type) continue;

                    try registerSystems(Child);
                }
            }
        }

        // const system_fn = fn () void;

        // fn Run(comptime T: type) type {
        //     return struct {
        //         fn run(w: *zflecs.world_t) void {
        //             // @compileLog(T.run);
        //             T.run(w);
        //         }
        //     };
        // }

        fn deinitSystems(comptime T: type) void {
            if (isSystem(T)) {
                if (@hasDecl(T, "deinit")) T.deinit();
            } else {
                const decls = @typeInfo(T).@"struct".decls;
                inline for (decls) |decl| {
                    const Child = @field(T, decl.name);
                    if (@TypeOf(Child) != type) continue;

                    deinitSystems(Child);
                }
            }
        }

        inline fn isSystem(comptime T: type) bool {
            return @hasDecl(T, "name") and @hasDecl(T, "phase") and @hasDecl(T, "run");
        }
    };
}

pub fn Query(comptime Components: anytype, comptime Filters: anytype) type {
    assertIsTuple(@TypeOf(Components));
    assertIsTuple(@TypeOf(Filters));

    const components_info = @typeInfo(@TypeOf(Components)).@"struct";
    const filters_info = @typeInfo(@TypeOf(Filters)).@"struct";

    return struct {
        query: *zflecs.query_t = undefined,
        world: *zflecs.world_t = undefined,

        pub fn init(self: *@This(), world: *zflecs.world_t) !void {
            var terms: [32]zflecs.term_t = [_]zflecs.term_t{.{}} ** zflecs.FLECS_TERM_COUNT_MAX;
            var count: usize = 0;

            inline for (components_info.fields) |component| {
                terms[count] = zflecs.term_t{ .id = zflecs.id(component.type) };
                count += 1;
            }

            inline for (filters_info.fields) |filter| {
                terms[count] = filter.toTerm();
                count += 1;
            }

            self.query = try zflecs.query_init(world, &.{ .terms = terms });
            self.world = world;
        }

        pub fn deinit(self: *@This()) void {
            zflecs.query_fini(self.query);
        }

        pub fn iter(self: *@This()) zflecs.iter_t {
            return zflecs.query_iter(self.world, self.query);
        }
    };
}

pub const With = zflecs.With;
pub const Without = zflecs.Without;

fn assertIsTuple(comptime T: anytype) void {
    const info = @typeInfo(T);
    if (info != .@"struct" or info.@"struct".is_tuple == false) {
        @compileError("expected a tuple type");
    }
}

test "ecs system" {
    const expect = std.testing.expect;

    const Components = struct {
        pub const Counter = usize;
        pub const Tag = usize;
    };

    const Systems = struct {
        pub const TestSystem = struct {
            pub const name = "test system";
            pub const phase = &zflecs.OnLoad;

            var init_called: bool = false;
            var run_called: bool = false;
            var deinit_called: bool = false;

            var counter_query: *zflecs.query_t = undefined;

            pub fn init(world: *zflecs.world_t) !void {
                var counter_terms: [32]zflecs.term_t = [_]zflecs.term_t{.{}} ** zflecs.FLECS_TERM_COUNT_MAX;
                counter_terms[0] = zflecs.term_t{ .id = zflecs.id(Components.Counter) };
                counter_query = try zflecs.query_init(world, &.{ .terms = counter_terms });

                init_called = true;
            }

            pub fn deinit() void {
                // counter_query.deinit();
                zflecs.query_fini(counter_query);

                deinit_called = true;
            }

            pub fn run(_: *zflecs.iter_t) void {
                var counter_it = zflecs.query_iter(z.world, counter_query);
                while (zflecs.iter_next(&counter_it)) {
                    const counters = zflecs.field(&counter_it, Components.Counter, 0).?;
                    for (counters) |*counter| {
                        counter.* += 1;
                    }
                }

                run_called = true;
            }
        };
    };

    const ECS = create(Components, Systems);

    try ECS.init();
    try expect(Systems.TestSystem.init_called);

    const entity = zflecs.new_entity(z.world, "Test Entity");
    _ = zflecs.set(z.world, entity, Components.Counter, 0);

    // const entity_tagged = zflecs.new_entity(z.world, "Test Entity Tagged");
    // _ = zflecs.set(z.world, entity_tagged, Components.Counter, 0);
    // _ = zflecs.set(z.world, entity_tagged, Components.Tag, 0);

    const iterations = 5;
    for (0..iterations) |_| {
        ECS.progress();
    }
    try expect(Systems.TestSystem.run_called);

    var counter_it = zflecs.query_iter(z.world, Systems.TestSystem.counter_query);
    while (zflecs.iter_next(&counter_it)) {
        const counters = zflecs.field(&counter_it, Components.Counter, 0).?;
        for (counters) |counter| {
            try expect(counter == iterations);
        }
    }

    ECS.deinit();
    try expect(Systems.TestSystem.deinit_called);
}
