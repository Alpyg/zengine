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
                const T = @field(Components, component.name);
                terms[count] = zflecs.term_t{ .id = zflecs.id(T) };
                count += 1;
            }

            inline for (filters_info.fields) |filter| {
                _ = filter; // autofix
                // const T = @field(Components, filter.name);
                // terms[count] = filter.toTerm();
                // count += 1;
            }

            self.query = try zflecs.query_init(world, &.{ .terms = terms });
            self.world = world;
        }

        pub fn deinit(self: *@This()) void {
            zflecs.query_fini(self.query);
            self.query = undefined;
        }

        pub fn iter(self: *@This()) zflecs.iter_t {
            return zflecs.query_iter(self.world, self.query);
        }
    };
}

pub fn System(comptime S: anytype) type {
    if (!@hasDecl(S, "name")) @compileError("expected system to have a name declaration");
    if (!@hasDecl(S, "phase")) @compileError("expected system to have a phase declaration");

    const param_types = @typeInfo(@TypeOf(S.run)).@"fn".params;

    return struct {
        pub const name = S.name;
        pub const phase = S.phase;

        const ArgsTupleType = std.meta.ArgsTuple(@TypeOf(S.run));
        var args_tuple: ArgsTupleType = undefined;

        pub fn init(world: *zflecs.world_t) !void {
            inline for (param_types, 0..) |param, i| {
                const Param = param.type.?;
                var param_: Param = .{};
                try param_.init(world);

                args_tuple[i] = param_;
            }
        }

        pub fn deinit() void {
            inline for (@typeInfo(ArgsTupleType).@"struct".fields) |arg| {
                if (@hasDecl(arg.type, "deinit")) @field(args_tuple, arg.name).deinit();
            }
        }

        pub fn run(_: *zflecs.iter_t) void {
            @call(.auto, S.run, args_tuple);
        }
    };
}

fn assertIsTuple(comptime T: anytype) void {
    const info = @typeInfo(T);
    if (info != .@"struct" or info.@"struct".is_tuple == false) {
        @compileError("expected a tuple type");
    }
}

test "ecs system" {
    const expect = std.testing.expect;

    const Components = struct {
        pub const Counter = struct { value: usize = 0 };
        pub const Tag = struct {};
    };

    const Systems = struct {
        pub const TestSystem = System(struct {
            pub const name = "test system";
            pub const phase = &zflecs.OnLoad;

            pub fn run(query: Query(.{Components.Counter}, .{})) void {
                var q = query;
                var counter_it = q.iter();
                while (zflecs.iter_next(&counter_it)) {
                    const counters = zflecs.field(&counter_it, Components.Counter, 0).?;
                    for (counters) |*counter| {
                        counter.*.value += 1;
                    }
                }
            }
        });
    };

    const ECS = create(Components, Systems);

    try ECS.init();

    const entity = zflecs.new_entity(z.world, "Test Entity");
    _ = zflecs.set(z.world, entity, Components.Counter, .{});

    // const entity_tagged = zflecs.new_entity(z.world, "Test Entity Tagged");
    // _ = zflecs.set(z.world, entity_tagged, Components.Counter, 0);
    // _ = zflecs.set(z.world, entity_tagged, Components.Tag, 0);

    const iterations = 5;
    for (0..iterations) |_| {
        ECS.progress();
    }

    var counter_it = zflecs.query_iter(z.world, Systems.TestSystem.args_tuple[0].query);
    while (zflecs.iter_next(&counter_it)) {
        const counters = zflecs.field(&counter_it, Components.Counter, 0).?;
        for (counters) |counter| {
            try expect(counter.value == iterations);
        }
    }

    ECS.deinit();
}
