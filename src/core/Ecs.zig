const std = @import("std");

const zflecs = @import("zflecs");

const z = @import("../root.zig");
pub const Assets = @import("assets.zig").Assets;
pub const Event = @import("event.zig").Event;
pub const Parent = @import("query.zig").Parent;
pub const Phase = @import("phase.zig");
pub const Query = @import("query.zig").Query;
pub const Resource = @import("resource.zig").Resource;
pub const System = @import("system.zig").System;
pub const With = @import("query.zig").With;
pub const Without = @import("query.zig").Without;

const Ecs = @This();

allocator: std.mem.Allocator = undefined,
world: *zflecs.world_t = undefined,

pub fn init(allocator: std.mem.Allocator) *Ecs {
    const self = allocator.create(Ecs) catch @panic("oom");
    self.* = .{ .allocator = allocator, .world = zflecs.init() };

    Phase.init(self);
    z.zstbi.init(allocator) catch @panic("shouldn't fail");
    return self;
}

pub fn deinit(self: *Ecs) void {
    _ = zflecs.fini(self.world);
    self.allocator.destroy(self);
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
        self.addComponent(entity, components{});
    } else if (components_info.@"struct".is_tuple) {
        inline for (components_info.@"struct".field_names) |field_name| {
            const component = @field(components, field_name);
            self.addComponent(entity, component);
        }
    }

    return self;
}

fn addComponent(self: *Ecs, entity: zflecs.entity_t, component: anytype) void {
    if (@sizeOf(@TypeOf(component)) == 0) {
        zflecs.add(self.world, entity, @TypeOf(component));
    } else {
        _ = zflecs.set(self.world, entity, @TypeOf(component), component);
    }
}

pub fn registerEcs(self: *Ecs, T: type) *Ecs {
    if (isSystem(T)) {
        _ = zflecs.ADD_SYSTEM(self.world, @typeName(T), T.Phase.*, T.run);
        std.log.debug("Registered system `{s}`", .{@typeName(T)});

        if (@hasDecl(T, "init")) T.init(self);
        return self;
    }

    if (@hasDecl(T, "COMPONENT")) {
        if (@sizeOf(T) > 0) {
            zflecs.COMPONENT(self.world, T);
            std.log.debug("Registered component `{s}`", .{@typeName(T)});
        } else {
            zflecs.TAG(self.world, T);
            std.log.debug("Registered tag `{s}`", .{@typeName(T)});
        }
        return self;
    }

    if (@hasDecl(T, "RESOURCE")) {
        zflecs.COMPONENT(self.world, T);
        if (zflecs.singleton_get(self.world, T) != null) return self;

        const resource = if (@hasDecl(T, "init"))
            T.init(self)
        else
            T{};

        _ = zflecs.singleton_set(self.world, T, resource);

        std.log.debug("Registered resource `{s}`", .{@typeName(T)});
        return self;
    }

    if (@hasDecl(T, "EVENT")) {
        _ = self.registerEvent(z.Event(T));
        std.log.debug("Registered event `{s}`", .{@typeName(T)});
        return self;
    }

    if (@typeInfo(T) != .@"struct") return self;

    const decl_names = @typeInfo(T).@"struct".decl_names;

    // First pass: components, resources and events. This guarantees that all
    // resources exist before any system's argument tuple is initialized.
    inline for (decl_names) |decl_name| {
        const Child = @field(T, decl_name);
        if (@TypeOf(Child) != type) continue;
        if (!isSystem(Child)) _ = self.registerEcs(Child);
    }

    // Second pass: systems, in declaration order.
    inline for (decl_names) |decl_name| {
        const Child = @field(T, decl_name);
        if (@TypeOf(Child) != type) continue;
        if (isSystem(Child)) _ = self.registerEcs(Child);
    }

    return self;
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

pub fn registerEvent(self: *Ecs, E: type) *Ecs {
    zflecs.COMPONENT(self.world, E);
    _ = zflecs.singleton_set(self.world, E, E.init(self));

    std.log.debug("Registered event `{s}`", .{@typeName(E)});

    return self;
}

pub fn registerResource(self: *Ecs, resource: anytype) *Ecs {
    const ResourceType = @TypeOf(resource);

    // A "type" passed as a value means the caller forgot to call `.init(ecs)`
    // (or should have used `registerEcs`, which handles `RESOURCE` types).
    if (ResourceType == type) {
        @compileError(
            "registerResource called with a type '" ++ @typeName(resource) ++ "'. " ++
                "Use registerEcs(" ++ @typeName(resource) ++ ") instead (it will call init(ecs)), " ++
                "or pass an instance: registerResource(try " ++ @typeName(resource) ++ ".init(ecs)).",
        );
    }

    if (@sizeOf(ResourceType) == 0) {
        @compileError(
            "registerResource called with a zero-sized type '" ++ @typeName(ResourceType) ++
                "'. Use registerEcs (it will register a TAG) or pass a non-empty struct.",
        );
    }

    if (zflecs.id(ResourceType) != 0 and zflecs.singleton_get(self.world, ResourceType) != null)
        return self;

    zflecs.COMPONENT(self.world, ResourceType);
    _ = zflecs.singleton_set(self.world, ResourceType, resource);

    return self;
}

pub fn hasResource(self: *Ecs, comptime T: type) bool {
    return zflecs.id(T) != 0 and zflecs.singleton_get(self.world, T) != null;
}

pub fn registerComponents(self: *Ecs, comptime T: type) *Ecs {
    const decl_names = @typeInfo(T).@"struct".decl_names;
    inline for (decl_names) |decl_name| {
        const Child = @field(T, decl_name);
        if (@TypeOf(Child) == type) {
            if (@sizeOf(Child) > 0) {
                zflecs.COMPONENT(self.world, Child);
                std.log.debug("Registered component `{s}`", .{decl_name});
            } else {
                zflecs.TAG(self.world, Child);
                std.log.debug("Registered tag `{s}`", .{decl_name});
            }
        }
    }

    return self;
}

pub fn registerSystems(self: *Ecs, comptime T: type) *Ecs {
    if (isSystem(T)) {
        _ = zflecs.ADD_SYSTEM(self.world, @typeName(T), T.Phase.*, T.run);
        std.log.debug("Registered system `{s}`", .{@typeName(T)});

        if (@hasDecl(T, "init")) T.init(self);
    } else {
        const decl_names = @typeInfo(T).@"struct".decl_names;
        inline for (decl_names) |decl_name| {
            const Child = @field(T, decl_name);
            if (@TypeOf(Child) != type) continue;

            _ = registerSystems(self, Child);
        }
    }

    return self;
}

pub fn registerPhase(self: *Ecs, phase: *zflecs.entity_t, depends_on: ?zflecs.entity_t) *Ecs {
    phase.* = zflecs.new_w_id(self.world, zflecs.Phase);

    if (depends_on) |depended_on| {
        zflecs.add_pair(self.world, phase.*, zflecs.DependsOn, depended_on);
    }

    return self;
}

inline fn isSystem(comptime T: type) bool {
    return @hasDecl(T, "Phase") and @hasDecl(T, "run");
}

fn deinitSystems(comptime T: type) void {
    if (isSystem(T)) {
        if (@hasDecl(T, "deinit")) T.deinit();
    } else {
        const decl_names = @typeInfo(T).@"struct".decl_names;
        inline for (decl_names) |decl_name| {
            const Child = @field(T, decl_name);
            if (@TypeOf(Child) != type) continue;

            deinitSystems(Child);
        }
    }
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
            pub const Counter2 = struct { value: usize = 0 };
            pub const Tag = struct {};
        };

        const Systems = struct {
            pub const TestSystem = System(&Phase.Update, struct {
                pub fn run(
                    q_counter: Query(.{Components.Counter}, .{Without(Components.Tag)}),
                    q_counters: Query(.{ Components.Counter, Components.Counter2 }, .{Without(Components.Tag)}),
                    q_counter_tag: Query(.{Components.Counter}, .{With(Components.Tag)}),
                ) void {
                    var counter_it = q_counter.iter();
                    while (counter_it.next()) |counter| {
                        counter.value += 1;
                    }

                    var counter_its = q_counters.iter();
                    while (counter_its.next()) |counters| {
                        var counter1, var counter2 = counters;
                        counter1.value += 1;
                        counter2.value += 2;
                    }

                    var counter_tag_it = q_counter_tag.iter();
                    while (counter_tag_it.next()) |counter_tag| {
                        counter_tag.value += 2;
                    }
                }
            });
        };
    };

    var ecs = Ecs.init(std.testing.allocator);
    defer ecs.deinit();

    _ = ecs.registerModule(Module{});

    const entity = ecs.new("Test Entity");
    _ = ecs.add(entity, Module.Components.Counter{});

    const entity_tagged = ecs.new("Test Entity Tagged");
    _ = ecs.add(entity_tagged, .{ Module.Components.Counter{}, Module.Components.Tag{} });

    const iterations = 5;
    for (0..iterations) |_| {
        ecs.progress();
    }

    var counter_q = Query(.{Module.Components.Counter}, .{Without(Module.Components.Tag)}).init(ecs.world);
    defer counter_q.deinit();
    var counter_it = counter_q.iter();
    while (counter_it.next()) |counter| {
        try expect(counter.value == iterations);
    }

    var counters_q = Query(.{ Module.Components.Counter, Module.Components.Counter2 }, .{Without(Module.Components.Tag)}).init(ecs.world);
    defer counters_q.deinit();
    var counters_it = counters_q.iter();
    while (counters_it.next()) |counters| {
        const counter1, const counter2 = counters;
        try expect(counter1.value == iterations);
        try expect(counter2.value == iterations * 2);
    }

    var tag_q = Query(.{Module.Components.Counter}, .{With(Module.Components.Tag)}).init(ecs.world);
    defer tag_q.deinit();
    var tag_it = tag_q.iter();
    while (tag_it.next()) |tag| {
        try expect(tag.value == iterations * 2);
    }
}
