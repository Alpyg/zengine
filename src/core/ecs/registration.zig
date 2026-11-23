//! Registration of ECS types.
//!
//! Implements the conventions documented on `Ecs.register`:
//! - `RESOURCE`      -> singleton resource
//! - `COMPONENT`     -> component, or a tag when zero-sized
//! - `phase` + `run` -> system
//! - `PHASE`         -> phase enum
//! - `EVENT_QUEUE`   -> event queue
//! - other structs   -> namespaces traversed recursively
//!
//! Everything a module registers is appended to the current scope so a hot
//! reload can tear it down again.

const std = @import("std");
const zflecs = @import("zflecs");

const ecs_mod = @import("../ecs.zig");
const Ecs = ecs_mod.Ecs;
const phases = @import("phases.zig");
const scopes = @import("scopes.zig");

/// Memory layout observed for a component at registration time.
pub const ComponentLayout = struct {
    size: usize,
    alignment: usize,
    layout_hash: u64,
};

/// Component layout registry. Persists across module reloads so a changed
/// component layout can be rejected instead of corrupting existing entity
/// data.
pub const Layouts = struct {
    /// Component name -> layout observed at registration.
    map: std.StringHashMapUnmanaged(ComponentLayout) = .{},
    /// Set when a module registration observed a component layout mismatch.
    conflict: bool = false,
};

/// Adds one system to the world and initializes its argument tuple.
pub fn registerSystem(self: *Ecs, comptime T: type) void {
    if (self.layouts.conflict) return;

    // System names are stable, so a type reachable from two namespaces (for
    // example `M.Module` and the namespace declaring `M`) must not be
    // registered twice: flecs rejects the duplicate entity name.
    if (zflecs.lookup(self.world, systemName(T).ptr) != 0) {
        std.log.debug("System `{s}` is already registered; skipping", .{@typeName(T)});
        return;
    }

    const phase = T.phaseEntity(self);
    const entity = zflecs.ADD_SYSTEM(self.world, systemName(T), phase, T.run);

    phases.trackSystem(self, phase, entity);
    scopes.addSystem(self, entity);

    if (@hasDecl(T, "init")) T.init(self);
    if (@hasDecl(T, "deinit")) scopes.addDeinit(self, scopes.systemDeinit(T));

    std.log.debug("Registered system `{s}`", .{@typeName(T)});
}

/// System name without path separators. Re-used across hot reloads so the old
/// system can be deleted and the new one registered under the same stable name.
fn systemName(comptime T: type) [:0]const u8 {
    return comptime std.fmt.comptimePrint("system_{x}", .{
        std.hash.Wyhash.hash(0, @typeName(T)),
    });
}

/// Stable summary of a component's memory layout, used to detect field
/// reorders/additions that keep the same size and alignment.
fn layoutHash(comptime T: type) u64 {
    return comptime blk: {
        var h = std.hash.Wyhash.init(0);
        h.update(@typeName(T));
        if (@typeInfo(T) == .@"struct") {
            const info = @typeInfo(T).@"struct";
            for (info.field_names, info.field_types) |name, FT| {
                h.update(name);
                const offset: usize = @offsetOf(T, name);
                h.update(std.mem.asBytes(&offset));
                h.update(@typeName(FT));
            }
        }
        break :blk h.final();
    };
}

/// Registers `T` as a component, or as a tag when it is zero-sized.
pub fn registerComponentType(self: *Ecs, comptime T: type) void {
    if (self.layouts.conflict) return;
    const size = @sizeOf(T);
    const alignment = @alignOf(T);
    const name = zflecs.typeName(T);
    const hash = layoutHash(T);

    // Keys must be owned: `@typeName(T)` points into the defining shared
    // object, which may be unloaded during hot reload.
    const owned_name = self.allocator.dupe(u8, name) catch @panic("oom");
    const gop = self.layouts.map.getOrPut(self.allocator, owned_name) catch @panic("oom");
    if (gop.found_existing) {
        self.allocator.free(owned_name);
        if (gop.value_ptr.size != size or
            gop.value_ptr.alignment != alignment or
            gop.value_ptr.layout_hash != hash)
        {
            std.log.err(
                "Component `{s}` changed layout (was {d}/{d}, now {d}/{d}); refusing hot reload",
                .{ name, gop.value_ptr.size, gop.value_ptr.alignment, size, alignment },
            );
            self.layouts.conflict = true;
            // Do not call into flecs with the new size: the existing component
            // was registered with the old layout and flecs aborts on mismatch.
            return;
        }
    } else {
        gop.value_ptr.* = .{ .size = size, .alignment = alignment, .layout_hash = hash };
    }

    if (size > 0) {
        zflecs.COMPONENT(self.world, T);
        std.log.debug("Registered component `{s}`", .{@typeName(T)});
    } else {
        zflecs.TAG(self.world, T);
        std.log.debug("Registered tag `{s}`", .{@typeName(T)});
    }
}

/// Registers the deinitializer/remover for a persistent resource value.
fn registerResourceCleanup(self: *Ecs, comptime T: type) void {
    if (@hasDecl(T, "deinit")) scopes.addResourceDeinit(self, scopes.resourceDeinit(T));
    scopes.addRemoval(self, scopes.singletonRemoval(T));
}

/// Stores a singleton resource and registers its deinitializer.
fn setResource(self: *Ecs, comptime T: type, value: T) void {
    if (self.layouts.conflict) return;
    zflecs.COMPONENT(self.world, T);
    _ = zflecs.singleton_set(self.world, T, value);
    registerResourceCleanup(self, T);

    std.log.debug("Registered resource `{s}`", .{@typeName(T)});
}

/// Creates the resource value (via `init(ecs)` when available) and stores it.
/// If the singleton already exists (for example after a hot reload), the value
/// is preserved and only its cleanup is re-registered.
fn registerResourceType(self: *Ecs, comptime T: type) void {
    registerComponentType(self, T);
    if (self.layouts.conflict) return;

    if (zflecs.singleton_get(self.world, T) != null) {
        registerResourceCleanup(self, T);
        return;
    }

    const value = if (@hasDecl(T, "init")) T.init(self) else T{};
    setResource(self, T, value);
}

/// Registers `T` using the conventions documented on `Ecs.register`.
/// Namespace types are traversed in two passes so resources/components/events
/// exist before any system argument tuple is initialized.
pub fn register(self: *Ecs, T: type) *Ecs {
    if (self.layouts.conflict) return self;
    switch (@typeInfo(T)) {
        .@"struct", .@"enum" => {},
        else => return self,
    }

    if (@hasDecl(T, "PHASE")) {
        const options = T.PHASE;
        if (@hasField(@TypeOf(options), "parent")) {
            _ = phases.registerPhaseSet(self, options.parent, T);
        } else {
            _ = phases.registerPhases(self, T);
        }
        return self;
    }

    if (isSystem(T)) {
        registerSystem(self, T);
        return self;
    }

    if (@hasDecl(T, "COMPONENT")) {
        registerComponentType(self, T);
        return self;
    }

    if (@hasDecl(T, "RESOURCE")) {
        registerResourceType(self, T);
        return self;
    }

    if (@hasDecl(T, "EVENT_QUEUE") and @hasDecl(T, "EventClearSystem")) {
        registerEvent(self, T);
        _ = register(self, T.EventClearSystem);
        return self;
    }

    if (@typeInfo(T) != .@"struct") return self;

    const decl_names = @typeInfo(T).@"struct".decl_names;

    // First pass: non-systems.
    inline for (decl_names) |decl_name| {
        const Child = @field(T, decl_name);
        if (@TypeOf(Child) != type) continue;
        // Skip the namespace's self alias (`const M = @This()`).
        if (Child == T) continue;
        if (!isSystem(Child)) _ = register(self, Child);
    }

    // Second pass: systems, in declaration order.
    inline for (decl_names) |decl_name| {
        const Child = @field(T, decl_name);
        if (@TypeOf(Child) != type) continue;
        if (Child == T) continue;
        if (isSystem(Child)) _ = register(self, Child);
    }

    return self;
}

/// Registers the deinitializer/remover for an event queue.
fn registerEventCleanup(self: *Ecs, comptime E: type) void {
    scopes.addResourceDeinit(self, scopes.eventDeinit(E));
    scopes.addRemoval(self, scopes.singletonRemoval(E));
}

/// Creates an `Event(T)` queue via `E.init(ecs)`. If one already exists (for
/// example after a hot reload), the data is preserved and only its cleanup is
/// re-registered.
fn registerEvent(self: *Ecs, comptime E: type) void {
    zflecs.COMPONENT(self.world, E);
    if (zflecs.singleton_get(self.world, E) != null) {
        registerEventCleanup(self, E);
        return;
    }

    _ = zflecs.singleton_set(self.world, E, E.init(self));
    registerEventCleanup(self, E);

    std.log.debug("Registered event `{s}`", .{@typeName(E)});
}

/// Inserts an already-constructed singleton value: a resource, an `Event(T)`
/// queue, or any non-empty struct. Resources and events get their
/// deinitializer/remover registered; if the singleton already exists, its value
/// is preserved and only the cleanup is re-registered.
pub fn insert(self: *Ecs, value: anytype) *Ecs {
    if (self.layouts.conflict) return self;
    const ValueType = @TypeOf(value);

    // A "type" passed as a value means the caller forgot to construct it
    // (or should have used `register`, which handles declared types).
    if (ValueType == type) {
        @compileError(
            "insert called with a type '" ++ @typeName(value) ++ "'. " ++
                "Use register(" ++ @typeName(value) ++ ") instead (it will create and init it), " ++
                "or pass an instance: insert(" ++ @typeName(value) ++ ".init(ecs)).",
        );
    }

    if (@sizeOf(ValueType) == 0) {
        @compileError(
            "insert called with a zero-sized type '" ++ @typeName(ValueType) ++
                "'. Use register (it will register a TAG) or pass a non-empty struct.",
        );
    }

    if (@hasDecl(ValueType, "EVENT_QUEUE")) {
        zflecs.COMPONENT(self.world, ValueType);
        if (zflecs.singleton_get(self.world, ValueType) == null) {
            _ = zflecs.singleton_set(self.world, ValueType, value);
        }
        registerEventCleanup(self, ValueType);
        return self;
    }

    if (hasResource(self, ValueType)) {
        registerResourceCleanup(self, ValueType);
        return self;
    }

    setResource(self, ValueType, value);

    return self;
}

/// Whether the singleton resource `T` is already registered.
pub fn hasResource(self: *Ecs, comptime T: type) bool {
    return zflecs.id(T) != 0 and zflecs.singleton_get(self.world, T) != null;
}

pub inline fn isSystem(comptime T: type) bool {
    return @hasDecl(T, "phase") and @hasDecl(T, "run");
}

/// Whether a registration observed a component layout mismatch.
pub fn hasConflict(self: *Ecs) bool {
    return self.layouts.conflict;
}

/// Clears a previous layout conflict, e.g. before attempting a hot reload.
pub fn clearConflict(self: *Ecs) void {
    self.layouts.conflict = false;
}

/// Frees the component layout registry.
pub fn deinit(self: *Ecs) void {
    var it = self.layouts.map.keyIterator();
    while (it.next()) |key| self.allocator.free(key.*);
    self.layouts.map.deinit(self.allocator);
}
