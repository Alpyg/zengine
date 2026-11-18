//! Compile-time query builder on top of flecs.
//!
//! `Query(Components, Filters)` describes which components to fetch and which
//! filters to apply. Components listed directly are required; `?T` makes them
//! optional. `Filters` accepts `With(T)`, `Without(T)` and `Parent(T)`.
//!
//! A component expression controls mutability:
//! - `Component`  yields `*const Component`
//! - `*Component` yields `*Component`
//! - `?Component` / `?*Component` behave the same way with an optional result.

const std = @import("std");

const z = @import("../root.zig");
const zflecs = @import("zflecs");

pub fn Query(comptime Components: anytype, comptime Filters: anytype) type {
    assertIsTuple(@TypeOf(Components));
    assertIsTuple(@TypeOf(Filters));

    const components_info = @typeInfo(@TypeOf(Components)).@"struct";
    const filters_info = @typeInfo(@TypeOf(Filters)).@"struct";

    if (components_info.field_names.len == 0) {
        @compileError("Expected at least one component in query");
    }

    const component_count = components_info.field_names.len;
    comptime var ComponentTypes: [component_count]type = undefined;
    comptime var Mutable: [component_count]bool = undefined;
    comptime var Optional: [component_count]bool = undefined;

    inline for (components_info.field_names, 0..) |component_name, i| {
        const field = parseQueryField(@field(Components, component_name));
        ComponentTypes[i] = field.component;
        Mutable[i] = field.mutable;
        Optional[i] = field.optional;
    }
    const Iter = QueryIter(ComponentTypes, Mutable, Optional);

    return struct {
        const Self = @This();

        world: *zflecs.world_t = undefined,
        query: *zflecs.query_t = undefined,

        pub fn init(world: *zflecs.world_t) Self {
            var terms: [32]zflecs.term_t = @splat(.{});
            var count: usize = 0;

            inline for (components_info.field_names) |component_name| {
                const T = @field(Components, component_name);
                terms[count] = parseQueryTypeTerm(T);
                count += 1;
            }

            inline for (filters_info.field_names) |filter_name| {
                const T = @field(Filters, filter_name);
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

        /// Starts a new iteration from the first matching table.
        pub fn iter(self: *const Self) Iter {
            return Iter.init(self.world, self.query);
        }
    };
}

const QueryField = struct {
    component: type,
    mutable: bool,
    optional: bool,
};

fn parseQueryField(comptime T: type) QueryField {
    const info = @typeInfo(T);

    const optional = info == .optional;
    var c = if (optional) @typeInfo(T).optional.child else T;

    while (@typeInfo(c) == .@"struct" and @hasDecl(c, "Inner")) {
        c = c.Inner;
    }

    var mutable = false;
    if (@typeInfo(c) == .pointer) {
        const ptr = @typeInfo(c).pointer;
        if (ptr.size != .one) {
            @compileError("Expected a single-item pointer component, got " ++ @typeName(c));
        }
        mutable = !ptr.attrs.@"const";
        c = ptr.child;
    }

    return .{ .component = c, .mutable = mutable, .optional = optional };
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

fn unwrapOptional(comptime T: type) type {
    return if (@typeInfo(T) == .optional) @typeInfo(T).optional.child else T;
}

fn baseComponent(comptime T: type) type {
    const info = @typeInfo(T);
    if (info == .optional) return baseComponent(info.optional.child);
    if (info == .pointer) return baseComponent(info.pointer.child);
    if (info == .@"struct" and @hasDecl(T, "Inner")) return baseComponent(T.Inner);
    return T;
}

fn parseQueryTypeTerm(comptime T: type) zflecs.term_t {
    const field = parseQueryField(T);
    const base = unwrapOptional(T);

    var term = if (@typeInfo(base) == .@"struct" and @hasDecl(base, "term"))
        base.term()
    else
        zflecs.term_t{ .id = zflecs.id(field.component) };

    term.inout = if (field.mutable or field.optional) .InOut else .In;
    if (field.optional) term.oper = .Optional;

    return term;
}

/// Filter: the entity must have component `C`.
pub fn With(comptime C: type) type {
    return struct {
        pub const Inner = C;
        pub fn term() zflecs.term_t {
            return zflecs.term_t{
                .id = zflecs.id(baseComponent(C)),
                .inout = .In,
            };
        }
    };
}

/// Filter: the entity must not have component `C`.
pub fn Without(comptime C: type) type {
    return struct {
        pub const Inner = C;
        pub fn term() zflecs.term_t {
            return zflecs.term_t{
                .id = zflecs.id(baseComponent(C)),
                .inout = .InOutNone,
                .oper = .Not,
            };
        }
    };
}

/// Filter: also fetch component `C` from the entity's parent (`ChildOf`
/// cascade).
pub fn Parent(comptime C: type) type {
    return struct {
        pub const Inner = C;
        pub fn term() zflecs.term_t {
            return zflecs.term_t{
                .id = zflecs.id(baseComponent(C)),
                .inout = .In,
                .src = .{ .id = zflecs.Cascade },
                .trav = zflecs.ChildOf,
            };
        }
    };
}

/// Iterator over the tables matched by a `Query`. `next` returns a pointer per
/// component; with several components it returns a tuple of pointers.
fn QueryIter(
    comptime QueryTypes: anytype,
    comptime Mutable: [QueryTypes.len]bool,
    comptime Optional: [QueryTypes.len]bool,
) type {
    const component_count = QueryTypes.len;

    comptime var TableTypes: [component_count]type = undefined;
    comptime var PointerTypes: [component_count]type = undefined;

    inline for (QueryTypes, 0..) |T, i| {
        TableTypes[i] = if (Optional[i]) ?[]T else []T;
        PointerTypes[i] = if (Optional[i])
            (if (Mutable[i]) ?*T else ?*const T)
        else
            (if (Mutable[i]) *T else *const T);
    }

    const ComponentsTable = @Tuple(&TableTypes);
    const Components = if (component_count > 1) @Tuple(&PointerTypes) else PointerTypes[0];

    return struct {
        const Self = @This();

        it: zflecs.iter_t,
        index: usize = 0,
        tables: ComponentsTable = undefined,
        started: bool = false,
        finished: bool = false,

        pub fn init(world: *zflecs.world_t, query: *zflecs.query_t) Self {
            const it = zflecs.query_iter(world, query);
            return Self{ .it = it };
        }

        /// Finalizes the underlying flecs iterator. Called automatically when
        /// iteration is exhausted; call it manually if you break out early.
        pub fn deinit(self: *Self) void {
            if (self.finished) return;
            // Trivial cached queries finalize themselves inside `query_next`
            // and clear the query pointer.
            if (@intFromPtr(self.it.query) != 0) zflecs.iter_fini(&self.it);
            self.finished = true;
        }

        /// Number of entities in the current table.
        pub fn count(self: *Self) usize {
            return self.it.count();
        }

        /// Advances to the next entity, or null when all tables are exhausted.
        pub fn next(self: *Self) ?Components {
            if (self.finished) return null;

            if (!self.started or self.index >= self.firstTableLen()) {
                if (!zflecs.query_next(&self.it)) {
                    self.deinit();
                    return null;
                }
                self.index = 0;

                inline for (QueryTypes, 0..) |T, i| {
                    self.tables[i] = zflecs.field(&self.it, T, i) orelse &.{};
                }
                self.started = true;
            }

            defer self.index += 1;

            var components: Components = undefined;

            if (component_count == 1) {
                if (comptime Optional[0]) {
                    components = if (self.index < self.tables[0].?.len)
                        &self.tables[0].?[self.index]
                    else
                        null;
                } else {
                    components = &self.tables[0][self.index];
                }
            } else {
                inline for (QueryTypes, 0..) |_, col| {
                    if (comptime Optional[col]) {
                        components[col] = if (self.index < self.tables[col].?.len)
                            &self.tables[col].?[self.index]
                        else
                            null;
                    } else {
                        components[col] = &self.tables[col][self.index];
                    }
                }
            }

            return components;
        }

        fn firstTableLen(self: *const Self) usize {
            if (comptime Optional[0]) {
                const table = self.tables[0] orelse return 0;
                return table.len;
            } else {
                return self.tables[0].len;
            }
        }
    };
}
