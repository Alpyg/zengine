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
                        std.log.debug("Registered component `{s}`", .{decl.name});
                    } else {
                        zflecs.TAG(z.world, Child);
                        std.log.debug("Registered tag `{s}`", .{decl.name});
                    }
                }
            }
        }

        fn registerSystems(comptime T: type) !void {
            if (isSystem(T)) {
                _ = zflecs.ADD_SYSTEM(z.world, T.name, T.phase.*, T.run);
                std.log.debug("Registered system `{s}`", .{T.name});

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

    var ComponentTypes: [components_info.fields.len]type = undefined;
    inline for (components_info.fields, 0..) |component, i| {
        const T = @field(Components, component.name);

        switch (@typeInfo(T)) {
            .pointer => |p| ComponentTypes[i] = []p.child,
            .@"struct" => ComponentTypes[i] = []T,
            else => @compileError("Expected struct, pointer or optional component"),
        }
    }
    const Iter = QueryIter(ComponentTypes);

    return struct {
        const Self = @This();

        world: *zflecs.world_t = undefined,
        query: *zflecs.query_t = undefined,

        pub fn init(world: *zflecs.world_t) !Self {
            var terms: [32]zflecs.term_t = [_]zflecs.term_t{.{}} ** zflecs.FLECS_TERM_COUNT_MAX;
            var count: usize = 0;

            inline for (components_info.fields) |component| {
                const T = @field(Components, component.name);
                const inout = if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.is_const) .InOut else .In;
                switch (@typeInfo(T)) {
                    .pointer => |p| terms[count] = zflecs.term_t{ .id = zflecs.id(p.child), .inout = inout },
                    .@"struct" => terms[count] = zflecs.term_t{ .id = zflecs.id(T), .inout = inout },
                    else => @compileError("Expected struct, pointer or optional component"),
                }
                count += 1;
            }

            inline for (filters_info.fields) |filter| {
                const T = @field(Filters, filter.name);
                terms[count] = T.term();
                count += 1;
            }

            return Self{
                .world = world,
                .query = try zflecs.query_init(world, &.{ .terms = terms }),
            };
        }

        pub fn deinit(self: *Self) void {
            zflecs.query_fini(self.query);
            self.query = undefined;
        }

        pub fn iter(self: *const Self) Iter {
            return Iter.init(self.world, self.query);
        }
    };
}

pub fn With(comptime Component: type) type {
    return struct {
        pub fn term() zflecs.term_t {
            return zflecs.term_t{ .id = zflecs.id(Component), .inout = .In };
        }
    };
}

pub fn Without(comptime Component: type) type {
    return struct {
        pub fn term() zflecs.term_t {
            return zflecs.term_t{ .id = zflecs.id(Component), .inout = .InOutNone, .oper = .Not };
        }
    };
}

fn QueryIter(comptime ComponentTypes: anytype) type {
    var ComponentsType: [ComponentTypes.len]type = undefined;
    inline for (ComponentTypes, 0..) |T, i| {
        switch (@typeInfo(T)) {
            .pointer => |p| ComponentsType[i] = *p.child,
            .@"struct" => ComponentsType[i] = *T,
            else => @compileError("Expected struct, pointer or optional component"),
        }
    }
    const ComponentsTable = std.meta.Tuple(&ComponentTypes);
    const Components = if (ComponentTypes.len > 1) std.meta.Tuple(&ComponentsType) else ComponentsType[0];

    return struct {
        const Self = @This();

        it: zflecs.iter_t,
        index: usize = 0,
        tables: ComponentsTable = undefined,

        pub fn init(world: *zflecs.world_t, query: *zflecs.query_t) Self {
            return Self{ .it = zflecs.query_iter(world, query) };
        }

        pub fn count(self: *Self) usize {
            return self.it.count();
        }

        pub fn next(self: *Self) ?Components {
            if (self.index >= self.tables[0].len) {
                if (!zflecs.iter_next(&self.it)) return null;
                self.index = 0;

                inline for (ComponentTypes, 0..) |T, i| {
                    switch (@typeInfo(T)) {
                        .pointer => |p| self.tables[i] = zflecs.field(&self.it, p.child, i).?,
                        .@"struct" => self.tables[i] = zflecs.field(&self.it, T, i).?,
                        else => @compileError("Expected struct, pointer or optional component"),
                    }
                }
            }

            defer self.index += 1;

            var components: Components = undefined;
            inline for (0..ComponentTypes.len) |col| {
                if (ComponentTypes.len > 1) {
                    components[col] = &self.tables[col][self.index];
                } else {
                    components = &self.tables[col][self.index];
                }
            }

            return components;
        }
    };
}

pub fn System(comptime S: anytype) type {
    if (!@hasDecl(S, "name")) @compileError("Expected system to have a name declaration");
    if (!@hasDecl(S, "phase")) @compileError("Expected system to have a phase declaration");

    const param_types = @typeInfo(@TypeOf(S.run)).@"fn".params;

    return struct {
        pub const name = S.name;
        pub const phase = S.phase;

        const ArgsTupleType = std.meta.ArgsTuple(@TypeOf(S.run));
        var args_tuple: ArgsTupleType = undefined;

        pub fn init(world: *zflecs.world_t) !void {
            inline for (param_types, 0..) |param, i| {
                if (@typeInfo(param.type.?) != .@"struct" or !@hasDecl(param.type.?, "init")) {
                    continue;
                }

                args_tuple[i] = try param.type.?.init(world);
            }
        }

        pub fn deinit() void {
            inline for (@typeInfo(ArgsTupleType).@"struct".fields) |arg| {
                if (@typeInfo(arg.type) == .@"struct" and @hasDecl(arg.type, "deinit")) {
                    @field(args_tuple, arg.name).deinit();
                }
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
        @compileError("Expected a tuple type");
    }
}

test "ecs system" {
    const expect = std.testing.expect;

    const Components = struct {
        pub const Counter = struct { value: usize = 0 };
        pub const Tag = struct { value: usize = 0 };
    };

    const Systems = struct {
        pub const TestSystem = System(struct {
            pub const name = "test system";
            pub const phase = &zflecs.OnLoad;

            pub fn run(
                q_counter: Query(.{Components.Counter}, .{Without(Components.Tag)}),
                q_counter_tag: Query(.{Components.Counter}, .{With(Components.Tag)}),
            ) void {
                var counter_it = q_counter.iter();
                while (counter_it.next()) |counter| {
                    counter.value += 1;
                }

                var counter_tag_it = q_counter_tag.iter();
                while (counter_tag_it.next()) |counter_tag| {
                    counter_tag.value += 2;
                }
            }
        });
    };

    const ECS = create(Components, Systems);

    try ECS.init();
    defer ECS.deinit();

    const entity = zflecs.new_entity(z.world, "Test Entity");
    _ = zflecs.set(z.world, entity, Components.Counter, .{});

    const entity_tagged = zflecs.new_entity(z.world, "Test Entity Tagged");
    _ = zflecs.set(z.world, entity_tagged, Components.Counter, .{});
    _ = zflecs.set(z.world, entity_tagged, Components.Tag, .{});

    const iterations = 5;
    for (0..iterations) |_| {
        ECS.progress();
    }

    var counter_q = try Query(.{Components.Counter}, .{Without(Components.Tag)}).init(z.world);
    var counter_it = counter_q.iter();
    while (counter_it.next()) |counter| {
        try expect(counter.value == iterations);
    }

    var tag_q = try Query(.{Components.Counter}, .{With(Components.Tag)}).init(z.world);
    var tag_it = tag_q.iter();
    while (tag_it.next()) |tag| {
        try expect(tag.value == iterations * 2);
    }
}
