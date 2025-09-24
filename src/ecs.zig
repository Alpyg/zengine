const std = @import("std");

const zflecs = @import("zflecs");

const z = @import("root.zig");
const Query = @import("ecs/query.zig").Query;
const With = @import("ecs/query.zig").With;
const Without = @import("ecs/query.zig").Without;

pub fn create(comptime Components: type, comptime Systems: type) type {
    return struct {
        const Self = @This();

        world: *zflecs.world_t = undefined,

        pub fn init() !Self {
            var self = Self{ .world = zflecs.init() };

            try registerComponents(&self, Components);
            try registerSystems(&self, Systems);

            return self;
        }

        pub fn deinit(self: *Self) void {
            deinitSystems(Systems);

            _ = zflecs.fini(self.world);
        }

        pub fn progress(self: *Self) void {
            _ = zflecs.progress(self.world, 0);
        }

        pub fn new(self: *Self, name: [:0]const u8) zflecs.entity_t {
            return zflecs.new_entity(self.world, name);
        }

        pub fn add(self: *Self, entity: zflecs.entity_t, components: anytype) void {
            const components_info = @typeInfo(@TypeOf(components));
            if (components_info != .@"struct" and components_info != .type) {
                @compileError("Expected struct, tuple or type component value");
            }

            if (components_info == .type) {
                self.add(entity, components);
            } else if (components_info.@"struct".is_tuple) {
                inline for (components_info.@"struct".fields) |field| {
                    const component = @field(components, field.name);
                    self.addComponent(entity, component);
                }
            }
        }

        pub fn addComponent(self: *Self, entity: zflecs.entity_t, component: anytype) void {
            if (@sizeOf(@TypeOf(component)) == 0) {
                zflecs.add(self.world, entity, component);
            } else {
                _ = zflecs.set(self.world, entity, @TypeOf(component), component);
            }
        }

        fn registerComponents(self: *Self, comptime T: type) !void {
            const decls = @typeInfo(T).@"struct".decls;
            inline for (decls) |decl| {
                const Child = @field(T, decl.name);
                if (@TypeOf(Child) == type) {
                    if (@sizeOf(Child) > 0) {
                        zflecs.COMPONENT(self.world, Child);
                        std.log.debug("Registered component `{s}`", .{decl.name});
                    } else {
                        zflecs.TAG(self.world, Child);
                        std.log.debug("Registered tag `{s}`", .{decl.name});
                    }
                }
            }
        }

        fn registerSystems(self: *Self, comptime T: type) !void {
            if (isSystem(T)) {
                _ = zflecs.ADD_SYSTEM(self.world, T.name, T.phase.*, T.run);
                std.log.debug("Registered system `{s}`", .{T.name});

                if (@hasDecl(T, "init")) try T.init(self.world);
            } else {
                const decls = @typeInfo(T).@"struct".decls;
                inline for (decls) |decl| {
                    const Child = @field(T, decl.name);
                    if (@TypeOf(Child) != type) continue;

                    try registerSystems(self, Child);
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

pub fn System(comptime S: anytype) type {
    if (!@hasDecl(S, "name")) @compileError("Expected system to have a name declaration");
    if (!@hasDecl(S, "phase")) @compileError("Expected system to have a phase declaration");

    const param_types = @typeInfo(@TypeOf(S.run)).@"fn".params;

    return struct {
        pub const name = S.name;
        pub const phase = S.phase;

        const ArgsTupleType = std.meta.ArgsTuple(@TypeOf(S.run));
        var args_tuple: ArgsTupleType = undefined;

        pub fn init(w: *zflecs.world_t) !void {
            inline for (param_types, 0..) |param, i| {
                if (@typeInfo(param.type.?) != .@"struct" or !@hasDecl(param.type.?, "init")) {
                    continue;
                }

                args_tuple[i] = try param.type.?.init(w);
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

    var ecs = try ECS.init();
    defer ecs.deinit();

    const entity = ecs.new("Test Entity");
    _ = ecs.add(entity, Components.Counter{});

    const entity_tagged = ecs.new("Test Entity Tagged");
    _ = ecs.add(entity_tagged, .{ Components.Counter{}, Components.Tag });

    const iterations = 5;
    for (0..iterations) |_| {
        ecs.progress();
    }

    var counter_q = try Query(.{Components.Counter}, .{Without(Components.Tag)}).init(ecs.world);
    var counter_it = counter_q.iter();
    while (counter_it.next()) |counter| {
        try expect(counter.value == iterations);
    }

    var tag_q = try Query(.{Components.Counter}, .{With(Components.Tag)}).init(ecs.world);
    var tag_it = tag_q.iter();
    while (tag_it.next()) |tag| {
        try expect(tag.value == iterations * 2);
    }
}
