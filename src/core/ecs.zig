//! ECS facade over flecs. Owns the world, registers modules/components/
//! resources/events/systems, and drives the frame loop with `progress`/`run`.
//!
//! Registration conventions:
//! - a type with `RESOURCE` is a singleton resource; `init(ecs)` is called once
//! - a type with `COMPONENT` is a component, or a tag when it is zero-sized
//! - a type with `stage` + `run` is a system (`System(...)` produces these)
//! - a type with `EVENT_QUEUE` comes from `Event(T)`
//! - any other struct is treated as a namespace and its declarations are
//!   registered recursively (non-systems first, then systems)

const std = @import("std");
const builtin = @import("builtin");

const zflecs = @import("zflecs");

const z = @import("../root.zig");
const phase_module = @import("phase.zig");
pub const Assets = @import("assets.zig").Assets;
pub const Event = @import("event.zig").Event;
pub const Parent = @import("query.zig").Parent;
pub const Phase = phase_module.Phase;
pub const PhaseModule = phase_module.PhaseModule;
pub const Query = @import("query.zig").Query;
pub const Resource = @import("resource.zig").Resource;
pub const System = @import("system.zig").System;
pub const With = @import("query.zig").With;
pub const Without = @import("query.zig").Without;

const Ecs = @This();

/// Monotonic world generation, used to invalidate per-world caches.
var next_world_id = std.atomic.Value(u64).init(1);

/// Set by the SIGINT/SIGTERM handler.
var signal_exit_requested = std.atomic.Value(bool).init(false);

fn handleSignal(_: std.posix.SIG) callconv(.c) void {
    signal_exit_requested.store(true, .release);
}

fn installSignalHandlers() void {
    if (comptime builtin.os.tag == .windows) return;

    var action = std.posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };

    std.posix.sigaction(std.posix.SIG.INT, &action, null);
    std.posix.sigaction(std.posix.SIG.TERM, &action, null);
}

allocator: std.mem.Allocator = undefined,

/// Underlying flecs world.
world: *zflecs.world_t = undefined,

/// Unique per-world generation. Caches (phases, sets) are rebuilt when it
/// changes.
id: u64 = 0,

/// Set by `quit`; checked by `run`.
should_exit: bool = false,

/// Deinitializers, called in reverse registration order by `deinit`.
deinit_fns: std.ArrayListUnmanaged(*const fn (*Ecs) void) = .empty,

/// Creates the world and registers image loading. The default phases are
/// registered by `z.PhaseModule`, which must be registered before systems.
pub fn init(allocator: std.mem.Allocator) *Ecs {
    const self = allocator.create(Ecs) catch @panic("oom");
    self.* = .{
        .allocator = allocator,
        .world = zflecs.init(),
        .id = next_world_id.fetchAdd(1, .monotonic),
    };

    z.zstbi.init(allocator) catch @panic("shouldn't fail");
    return self;
}

/// Runs registered deinitializers in reverse order, then destroys the flecs
/// world and the `Ecs` allocation.
pub fn deinit(self: *Ecs) void {
    var i = self.deinit_fns.items.len;
    while (i > 0) {
        i -= 1;
        self.deinit_fns.items[i](self);
    }
    self.deinit_fns.deinit(self.allocator);

    z.zstbi.deinit();
    _ = zflecs.fini(self.world);
    self.allocator.destroy(self);
}

fn addDeinit(self: *Ecs, f: *const fn (*Ecs) void) void {
    self.deinit_fns.append(self.allocator, f) catch @panic("oom");
}

fn systemDeinit(comptime T: type) *const fn (*Ecs) void {
    return struct {
        fn run(_: *Ecs) void {
            T.deinit();
        }
    }.run;
}

fn resourceDeinit(comptime T: type) *const fn (*Ecs) void {
    return struct {
        fn run(ecs: *Ecs) void {
            if (comptime @hasDecl(T, "deinit")) {
                const resource = zflecs.singleton_get_mut(ecs.world, T) orelse return;
                const Fn = @TypeOf(T.deinit);

                if (comptime Fn == fn (*T) void) {
                    T.deinit(resource);
                } else if (comptime Fn == fn (*T, *Ecs) void) {
                    T.deinit(resource, ecs);
                } else {
                    @compileError("Resource `" ++ @typeName(T) ++
                        "` deinit must be `fn (*Self) void` or `fn (*Self, *Ecs) void`");
                }
            }
        }
    }.run;
}

fn eventDeinit(comptime E: type) *const fn (*Ecs) void {
    return struct {
        fn run(ecs: *Ecs) void {
            const event = zflecs.singleton_get_mut(ecs.world, E) orelse return;
            event.deinit(ecs.allocator);
        }
    }.run;
}

fn moduleDeinit(comptime M: type) *const fn (*Ecs) void {
    return struct {
        fn run(ecs: *Ecs) void {
            M.deinit(ecs);
        }
    }.run;
}

/// Runs one frame: all systems in phase order.
pub fn progress(self: *Ecs) void {
    _ = zflecs.progress(self.world, 0);
}

/// Runs frames until `quit` is called or a termination signal arrives.
pub fn run(self: *Ecs) void {
    installSignalHandlers();

    while (!self.should_exit and !signal_exit_requested.load(.acquire)) {
        self.progress();
    }
}

/// Requests that `run` stop after the current frame.
pub fn quit(self: *Ecs) void {
    self.should_exit = true;
}

/// Creates an entity with a debug name.
pub fn new(self: *Ecs, name: [:0]const u8) zflecs.entity_t {
    return zflecs.new_entity(self.world, name);
}

/// Adds one or more components. Accepts a component value, a component type
/// (for zero-sized tags), or a tuple of either.
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

/// Adds one system to the world and initializes its argument tuple.
fn registerSystem(self: *Ecs, comptime T: type) void {
    _ = zflecs.ADD_SYSTEM(self.world, @typeName(T), T.stageEntity(self), T.run);

    if (@hasDecl(T, "init")) T.init(self);
    if (@hasDecl(T, "deinit")) self.addDeinit(systemDeinit(T));

    std.log.debug("Registered system `{s}`", .{@typeName(T)});
}

/// Registers `T` as a component, or as a tag when it is zero-sized.
fn registerComponentType(self: *Ecs, comptime T: type) void {
    if (@sizeOf(T) > 0) {
        zflecs.COMPONENT(self.world, T);
        std.log.debug("Registered component `{s}`", .{@typeName(T)});
    } else {
        zflecs.TAG(self.world, T);
        std.log.debug("Registered tag `{s}`", .{@typeName(T)});
    }
}

/// Stores a singleton resource and registers its deinitializer.
fn setResource(self: *Ecs, comptime T: type, value: T) void {
    zflecs.COMPONENT(self.world, T);
    _ = zflecs.singleton_set(self.world, T, value);
    if (@hasDecl(T, "deinit")) self.addDeinit(resourceDeinit(T));

    std.log.debug("Registered resource `{s}`", .{@typeName(T)});
}

/// Creates the resource value (via `init(ecs)` when available) and stores it.
fn registerResourceType(self: *Ecs, comptime T: type) void {
    if (self.hasResource(T)) return;

    const value = if (@hasDecl(T, "init")) T.init(self) else T{};
    self.setResource(T, value);
}

/// Registers `T` using the conventions documented at the top of this file.
/// Namespace types are traversed in two passes so resources/components/events
/// exist before any system argument tuple is initialized.
pub fn registerEcs(self: *Ecs, T: type) *Ecs {
    if (isSystem(T)) {
        self.registerSystem(T);
        return self;
    }

    if (@hasDecl(T, "COMPONENT")) {
        self.registerComponentType(T);
        return self;
    }

    if (@hasDecl(T, "RESOURCE")) {
        self.registerResourceType(T);
        return self;
    }

    if (@hasDecl(T, "EVENT_QUEUE")) {
        _ = self.registerEvent(T);
        if (@hasDecl(T, "EventClearSystem")) _ = self.registerEcs(T.EventClearSystem);
        return self;
    }

    if (@typeInfo(T) != .@"struct") return self;

    const decl_names = @typeInfo(T).@"struct".decl_names;

    // First pass: non-systems.
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

/// Instantiates a module and calls its `init(module, ecs)`. If the module
/// declares `deinit(ecs: *Ecs)`, it is called from `Ecs.deinit` in reverse
/// registration order.
pub fn registerModule(self: *Ecs, module: anytype) *Ecs {
    const ModuleType = @TypeOf(module);

    if (@hasDecl(ModuleType, "init")) {
        ModuleType.init(module, self);
    } else {
        @compileError("Module should have an init method");
    }

    if (@hasDecl(ModuleType, "deinit")) {
        if (comptime @TypeOf(ModuleType.deinit) != fn (*Ecs) void) {
            @compileError("Module `" ++ @typeName(ModuleType) ++
                "` deinit must be `fn (*Ecs) void`");
        }
        self.addDeinit(moduleDeinit(ModuleType));
    }

    return self;
}

/// Registers an `Event(T)` queue as a singleton.
pub fn registerEvent(self: *Ecs, E: type) *Ecs {
    zflecs.COMPONENT(self.world, E);
    if (zflecs.singleton_get(self.world, E) != null) return self;
    _ = zflecs.singleton_set(self.world, E, E.init(self));
    self.addDeinit(eventDeinit(E));

    std.log.debug("Registered event `{s}`", .{@typeName(E)});

    return self;
}

/// Registers an already-constructed singleton resource. No-op if one exists.
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

    if (self.hasResource(ResourceType)) return self;

    self.setResource(ResourceType, resource);

    return self;
}

/// Whether the singleton resource `T` is already registered.
pub fn hasResource(self: *Ecs, comptime T: type) bool {
    return zflecs.id(T) != 0 and zflecs.singleton_get(self.world, T) != null;
}

/// Registers every type declaration of `T` as a component or tag.
pub fn registerComponents(self: *Ecs, comptime T: type) *Ecs {
    inline for (@typeInfo(T).@"struct".decl_names) |decl_name| {
        const Child = @field(T, decl_name);
        if (@TypeOf(Child) == type) self.registerComponentType(Child);
    }

    return self;
}

/// Registers every system found in the declarations of `T`.
pub fn registerSystems(self: *Ecs, comptime T: type) *Ecs {
    if (isSystem(T)) {
        self.registerSystem(T);
        return self;
    }

    if (@typeInfo(T) != .@"struct") return self;

    inline for (@typeInfo(T).@"struct".decl_names) |decl_name| {
        const Child = @field(T, decl_name);
        if (@TypeOf(Child) != type) continue;
        _ = self.registerSystems(Child);
    }

    return self;
}

/// Creates a phase entity and chains it after `depends_on` (if any).
pub fn registerPhase(self: *Ecs, phase: *zflecs.entity_t, depends_on: ?zflecs.entity_t) *Ecs {
    phase.* = zflecs.new_w_id(self.world, zflecs.Phase);

    if (depends_on) |depended_on| {
        zflecs.add_pair(self.world, phase.*, zflecs.DependsOn, depended_on);
    }

    return self;
}

/// Creates one phase entity per enum value, chained after `parent` when given.
/// Returns the last entity in the chain, or `parent` when the enum is empty.
fn registerPhaseChain(self: *Ecs, comptime S: type, parent: ?zflecs.entity_t) ?zflecs.entity_t {
    const Storage = phase_module.PhaseStorage(S);
    Storage.begin(self);

    var prev = parent;
    inline for (@typeInfo(S).@"enum".field_names) |name| {
        const value = comptime @field(S, name);
        var e: zflecs.entity_t = undefined;
        _ = self.registerPhase(&e, prev);
        Storage.set(value, e);
        prev = e;
    }

    return prev;
}

/// Registers every value of the phase enum `S` as a top-level flecs phase,
/// chained in declaration order. Returns `self` for chaining.
pub fn registerPhases(self: *Ecs, comptime S: type) *Ecs {
    comptime assertEnum(S, "registerPhases");

    _ = self.registerPhaseChain(S, null);

    std.log.debug("Registered phases `{s}`", .{@typeName(S)});
    return self;
}

/// Registers every value of the set enum `S` as a subphase of `phase`, chained
/// in declaration order. Must be called before registering systems that use the
/// set. Returns `self` for chaining.
pub fn registerPhaseSet(self: *Ecs, comptime phase: Phase, comptime S: type) *Ecs {
    comptime assertEnum(S, "registerPhaseSet");

    const parent = phase_module.entity(self, phase);
    const last = self.registerPhaseChain(S, parent);

    // Keep the set inside the parent phase's slot.
    if (last) |last_entity| {
        if (comptime phase_module.next(phase)) |next_phase| {
            zflecs.add_pair(self.world, phase_module.entity(self, next_phase), zflecs.DependsOn, last_entity);
        }
    }

    std.log.debug("Registered phase set `{s}`", .{@typeName(S)});
    return self;
}

fn assertEnum(comptime S: type, comptime caller: []const u8) void {
    if (@typeInfo(S) != .@"enum") {
        @compileError(caller ++ " expects an enum type, got " ++ @typeName(S));
    }
}

/// Enables or disables a top-level phase, an entire set enum, or a single set
/// value. Disabling cascades to nested systems/phases through `DependsOn`.
pub fn setStageEnabled(self: *Ecs, comptime stage: anytype, enabled: bool) void {
    const T = @TypeOf(stage);
    if (T == Phase) {
        zflecs.enable(self.world, phase_module.entity(self, stage), enabled);
    } else if (T == type) {
        const Storage = phase_module.PhaseStorage(stage);
        inline for (@typeInfo(stage).@"enum".field_names) |name| {
            const value = comptime @field(stage, name);
            zflecs.enable(self.world, Storage.get(self, value), enabled);
        }
    } else {
        zflecs.enable(self.world, phase_module.resolve(self, stage), enabled);
    }
}

inline fn isSystem(comptime T: type) bool {
    return @hasDecl(T, "stage") and @hasDecl(T, "run");
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
            pub const TestSystem = System(Phase.update, struct {
                pub fn run(
                    q_counter: Query(.{*Components.Counter}, .{Without(Components.Tag)}),
                    q_counters: Query(.{ *Components.Counter, *Components.Counter2 }, .{Without(Components.Tag)}),
                    q_counter_tag: Query(.{*Components.Counter}, .{With(Components.Tag)}),
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

    _ = ecs.registerModule(phase_module.PhaseModule{});
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

test "registerPhaseSet chains values under a phase" {
    var ecs = Ecs.init(std.testing.allocator);
    defer ecs.deinit();

    _ = ecs.registerModule(phase_module.PhaseModule{});

    const Set = enum { a, b, c };
    _ = ecs.registerPhaseSet(Phase.update, Set);

    const a = phase_module.PhaseStorage(Set).get(ecs, .a);
    const b = phase_module.PhaseStorage(Set).get(ecs, .b);
    const c = phase_module.PhaseStorage(Set).get(ecs, .c);

    try std.testing.expect(a != 0 and b != 0 and c != 0);
    try std.testing.expect(zflecs.has_pair(ecs.world, a, zflecs.DependsOn, phase_module.entity(ecs, Phase.update)));
    try std.testing.expect(zflecs.has_pair(ecs.world, b, zflecs.DependsOn, a));
    try std.testing.expect(zflecs.has_pair(ecs.world, c, zflecs.DependsOn, b));

    const next_phase = comptime phase_module.next(Phase.update).?;
    try std.testing.expect(zflecs.has_pair(ecs.world, phase_module.entity(ecs, next_phase), zflecs.DependsOn, c));

    const SetSystem = System(Set.b, struct {
        pub fn run() void {}
    });
    try std.testing.expectEqual(b, SetSystem.stageEntity(ecs));

    ecs.setStageEnabled(Phase.update, true);
    ecs.setStageEnabled(Set, true);
    ecs.setStageEnabled(Set.b, false);
    ecs.setStageEnabled(Set.b, true);
}

test "Ecs.deinit runs module, resource and event deinit" {
    const State = struct {
        var resource_deinited: bool = false;
        var module_deinited: bool = false;
    };

    const TestResource = struct {
        value: u32 = 0,
        pub const RESOURCE = {};
        pub fn init(_: *Ecs) @This() {
            return .{};
        }
        pub fn deinit(_: *@This()) void {
            State.resource_deinited = true;
        }
    };

    const Ev = Event(u32);

    const Module = struct {
        pub fn init(_: @This(), ecs: *Ecs) void {
            _ = ecs.registerEcs(TestResource);
            _ = ecs.registerEvent(Ev);
        }
        pub fn deinit(_: *Ecs) void {
            State.module_deinited = true;
        }
    };

    var ecs = Ecs.init(std.testing.allocator);
    _ = ecs.registerModule(Module{});
    ecs.deinit();

    try std.testing.expect(State.resource_deinited);
    try std.testing.expect(State.module_deinited);
}

test "query mutability follows pointer syntax" {
    const A = struct {
        pub const COMPONENT = {};
        value: u32 = 0,
    };
    const B = struct {
        pub const COMPONENT = {};
        value: u32 = 0,
    };

    var ecs = Ecs.init(std.testing.allocator);
    defer ecs.deinit();

    _ = ecs.registerEcs(A);
    _ = ecs.registerEcs(B);

    const e1 = ecs.new("e1");
    _ = ecs.add(e1, .{ A{}, B{} });
    const e2 = ecs.new("e2");
    _ = ecs.add(e2, B{});

    var q = Query(.{ *A, B }, .{}).init(ecs.world);
    defer q.deinit();
    var it = q.iter();
    while (it.next()) |row| {
        const a: *A = row[0];
        const b: *const B = row[1];
        a.value += 1;
        try std.testing.expectEqual(@as(u32, 0), b.value);
    }

    var q_optional = Query(.{ ?A, B }, .{}).init(ecs.world);
    defer q_optional.deinit();
    var optional_it = q_optional.iter();
    while (optional_it.next()) |row| {
        const a: ?*const A = row[0];
        _ = row[1];
        if (a) |value| {
            try std.testing.expectEqual(@as(u32, 1), value.value);
        } else {}
    }
}

test "Resource resolves to const or mutable pointers" {
    const TestRes = struct {
        pub const RESOURCE = {};
        value: u32 = 0,
    };

    try std.testing.expect(comptime Resource(TestRes) == *const TestRes);
    try std.testing.expect(comptime Resource(*TestRes) == *TestRes);
    try std.testing.expect(comptime Resource(*const TestRes) == *const TestRes);
}
