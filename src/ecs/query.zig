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

    comptime var ComponentTypes: [components_info.fields.len]type = undefined;
    inline for (components_info.fields, 0..) |component, i| {
        const T = @field(Components, component.name);

        ComponentTypes[i] = parseQueryType(T);
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
                terms[count] = parseQueryTypeTerm(T);
                count += 1;
            }

            inline for (filters_info.fields) |filter| {
                const T = @field(Filters, filter.name);
                assertImplsTerm(T);

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

fn assertIsTuple(comptime T: type) void {
    const info = @typeInfo(T);
    if (info != .@"struct" or info.@"struct".is_tuple == false) {
        @compileError("Expected a tuple type");
    }
}

fn assertImplsTerm(comptime T: type) void {
    if (@typeInfo(T) != .optional and !@hasDecl(T, "term"))
        @compileError("Filter does not implement term()");
}

fn parseQueryTypeTerm(comptime T: type) zflecs.term_t {
    const info = @typeInfo(T);

    const optional = info == .optional;
    const C = if (optional) @typeInfo(T).optional.child else T;

    var term = if (@hasDecl(C, "term")) C.term() else switch (@typeInfo(C)) {
        .pointer => |p| zflecs.term_t{ .id = zflecs.id(p.child) },
        .@"struct" => zflecs.term_t{ .id = zflecs.id(T) },
        else => @compileError("Expected pointer, struct or pointer type"),
    };

    if (optional) term.oper = .Optional;

    return term;
}

fn parseQueryType(comptime T: type) type {
    const info = @typeInfo(T);

    const optional = info == .optional;
    var C = if (optional) @typeInfo(T).optional.child else T;

    C = if (@hasDecl(C, "Component")) C.Component else C;

    if (optional) {
        return ?C;
    } else {
        return C;
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

pub fn Parent(comptime T: type) type {
    return struct {
        const Component = T;
        pub fn term() zflecs.term_t {
            return zflecs.term_t{
                .id = zflecs.id(T),
                .inout = .In,
                .src = .{ .id = zflecs.Cascade },
                .trav = zflecs.ChildOf,
            };
        }
    };
}

fn QueryIter(comptime QueryTypes: anytype) type {
    comptime var TableTypes: [QueryTypes.len]type = undefined;
    comptime var ComponentTypes: [QueryTypes.len]type = undefined;
    inline for (QueryTypes, 0..) |T, i| {
        switch (@typeInfo(T)) {
            .pointer => |p| {
                TableTypes[i] = []p.child;
                ComponentTypes[i] = *p.child;
            },
            .@"struct" => {
                TableTypes[i] = []T;
                ComponentTypes[i] = *T;
            },
            .optional => |p| {
                TableTypes[i] = ?[]p.child;
                ComponentTypes[i] = ?*p.child;
            },
            else => @compileError("Expected struct, pointer or optional component"),
        }
    }
    const ComponentsTable = std.meta.Tuple(&TableTypes);
    const Components = if (QueryTypes.len > 1)
        std.meta.Tuple(&ComponentTypes)
    else
        *@typeInfo(TableTypes[0]).pointer.child;

    // @compileLog(ComponentTypes);
    // @compileLog(ComponentsTable);
    // @compileLog(Components);
    // @compileLog(0);

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

                inline for (QueryTypes, 0..) |T, i| {
                    switch (@typeInfo(T)) {
                        .pointer => |p| self.tables[i] = zflecs.field(&self.it, p.child, i) orelse &.{},
                        .optional => |p| self.tables[i] = zflecs.field(&self.it, p.child, i) orelse &.{},
                        .@"struct" => self.tables[i] = zflecs.field(&self.it, T, i) orelse &.{},
                        else => @compileError("Expected struct, pointer or optional component"),
                    }
                }
            }

            defer self.index += 1;

            var components: Components = undefined;
            inline for (QueryTypes, 0..) |T, col| {
                if (QueryTypes.len > 1) {
                    switch (@typeInfo(T)) {
                        .optional => {
                            if (self.index < self.tables[col].?.len) {
                                components[col] = &self.tables[col].?[self.index];
                            } else {
                                components[col] = null;
                            }
                        },
                        .@"struct" => {
                            if (self.index < self.tables[col].len) {
                                components[col] = &self.tables[col][self.index];
                            }
                        },
                        else => @compileError("Expected struct, pointer or optional component"),
                    }
                } else {
                    components = &self.tables[col][self.index];
                }
            }

            return components;
        }
    };
}
