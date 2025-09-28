const std = @import("std");

const zflecs = @import("zflecs");

pub const Pipeline = @import("ecs/Pipeline.zig");
pub const Parent = @import("ecs/query.zig").Parent;
pub const Query = @import("ecs/query.zig").Query;
pub const With = @import("ecs/query.zig").With;
pub const Without = @import("ecs/query.zig").Without;
pub const Resource = @import("ecs/resource.zig").Resource;
pub const System = @import("ecs/system.zig").System;
const z = @import("root.zig");

const Ecs = @This();

world: *zflecs.world_t = undefined,

pub fn init() Ecs {
    var self = Ecs{ .world = zflecs.init() };

    Pipeline.init(&self);

    return self;
}

pub fn deinit(self: *Ecs) void {
    _ = zflecs.fini(self.world);
}

pub fn progress(self: *Ecs) void {
    _ = zflecs.progress(self.world, 0);
}

pub fn run(self: *Ecs) void {
    while (true) {
        self.progress();
    }
}

pub fn new(self: *Ecs, name: [:0]const u8) zflecs.entity_t {
    return zflecs.new_entity(self.world, name);
}

pub fn add(self: *Ecs, entity: zflecs.entity_t, components: anytype) *Ecs {
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

    return self;
}

fn addComponent(self: *Ecs, entity: zflecs.entity_t, component: anytype) void {
    if (@sizeOf(@TypeOf(component)) == 0) {
        zflecs.add(self.world, entity, component);
    } else {
        _ = zflecs.set(self.world, entity, @TypeOf(component), component);
    }
}

pub fn registerModule(self: *Ecs, module: anytype) *Ecs {
    const ModuleType = @TypeOf(module);

    if (@hasDecl(ModuleType, "init")) {
        ModuleType.init(module, self);
    } else {
        @compileError("Module should have an init method");
    }

    return self;
}

pub fn registerResource(self: *Ecs, resource: anytype) *Ecs {
    const ResourceType = @TypeOf(resource);

    zflecs.COMPONENT(self.world, ResourceType);
    _ = zflecs.singleton_set(self.world, ResourceType, resource);

    return self;
}

pub fn registerComponents(self: *Ecs, comptime T: type) *Ecs {
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

    return self;
}

inline fn isSystem(comptime T: type) bool {
    return @hasDecl(T, "phase") and @hasDecl(T, "run");
}

pub fn registerSystems(self: *Ecs, comptime T: type) *Ecs {
    if (isSystem(T)) {
        _ = zflecs.ADD_SYSTEM(self.world, @typeName(T), T.phase.*, T.run);
        std.log.debug("Registered system `{s}`", .{@typeName(T)});

        if (@hasDecl(T, "init")) T.init(self.world);
    } else {
        const decls = @typeInfo(T).@"struct".decls;
        inline for (decls) |decl| {
            const Child = @field(T, decl.name);
            if (@TypeOf(Child) != type) continue;

            _ = registerSystems(self, Child);
        }
    }

    return self;
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

pub fn registerPipeline(self: *Ecs, phase: *zflecs.entity_t, depends_on: ?zflecs.entity_t) *Ecs {
    phase.* = zflecs.new_w_id(self.world, zflecs.Phase);

    if (depends_on) |depended_on| {
        zflecs.add_pair(self.world, phase.*, zflecs.DependsOn, depended_on);
    }

    return self;
}

test "ecs system" {
    const expect = std.testing.expect;

    const Module = struct {
        const Self = @This();

        pub fn init(_: Self, ecs: *Ecs) void {
            _ = ecs.registerComponents(Components)
                .registerSystems(Systems);
        }

        const Components = struct {
            pub const Counter = struct { value: usize = 0 };
            pub const Tag = struct {};
        };

        const Systems = struct {
            pub const TestSystem = System(struct {
                pub const phase = &Pipeline.Update;

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
    };

    var ecs = Ecs.init();
    defer ecs.deinit();

    _ = ecs.registerModule(Module{});

    const entity = ecs.new("Test Entity");
    _ = ecs.add(entity, Module.Components.Counter{});

    const entity_tagged = ecs.new("Test Entity Tagged");
    _ = ecs.add(entity_tagged, .{ Module.Components.Counter{}, Module.Components.Tag });

    const iterations = 5;
    for (0..iterations) |_| {
        ecs.progress();
    }

    var counter_q = Query(.{Module.Components.Counter}, .{Without(Module.Components.Tag)}).init(ecs.world);
    var counter_it = counter_q.iter();
    while (counter_it.next()) |counter| {
        try expect(counter.value == iterations);
    }

    var tag_q = Query(.{Module.Components.Counter}, .{With(Module.Components.Tag)}).init(ecs.world);
    var tag_it = tag_q.iter();
    while (tag_it.next()) |tag| {
        try expect(tag.value == iterations * 2);
    }
}
