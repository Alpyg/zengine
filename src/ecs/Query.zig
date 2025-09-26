const std = @import("std");

const zflecs = @import("zflecs");

pub fn Query(comptime Components: anytype, comptime Filters: anytype) type {
    assertIsTuple(@TypeOf(Components));
    assertIsTuple(@TypeOf(Filters));

    const components_info = @typeInfo(@TypeOf(Components)).@"struct";
    const filters_info = @typeInfo(@TypeOf(Filters)).@"struct";

    if (components_info.fields.len == 0) {
        @compileError("Expected at least one component in query ");
    }

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

        pub fn init(world: *zflecs.world_t) Self {
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
                .query = zflecs.query_init(world, &.{ .terms = terms }) catch |err| std.debug.panic("Failed to initialize query: {}", .{err}),
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

fn assertIsTuple(comptime T: anytype) void {
    const info = @typeInfo(T);
    if (info != .@"struct" or info.@"struct".is_tuple == false) {
        @compileError("Expected a tuple type");
    }
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
