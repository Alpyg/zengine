//! Registration scopes and teardown.
//!
//! A scope is an ordered undo log for everything a module registers: its
//! systems, its Zig deinitializers, and the typed removers for its singleton
//! resources and events. Scopes are host-side bookkeeping; flecs owns the
//! entities themselves.
//!
//! Index 0 is the root scope (host registrations). `beginModule` allocates a
//! scope, `deinitModule` tears one down. Components and entity data are not
//! part of a scope: they persist across module reloads.

const std = @import("std");
const zflecs = @import("zflecs");

const ecs_mod = @import("../ecs.zig");
const Ecs = ecs_mod.Ecs;
const phases = @import("phases.zig");

pub const Handle = u32;

/// How a module scope is being torn down.
/// - `reload` keeps components, resources and events so the next version can
///   take them over.
/// - `unload` also runs resource/event deinitializers and removes their
///   singletons.
pub const Teardown = enum { reload, unload };

pub const Entry = struct {
    name: []const u8 = "root",
    systems: std.ArrayListUnmanaged(zflecs.entity_t) = .empty,
    deinit_fns: std.ArrayListUnmanaged(*const fn (*Ecs) void) = .empty,
    /// Resource/event deinitializers. Kept separate from `deinit_fns` so a
    /// reload can preserve the values.
    resource_deinit_fns: std.ArrayListUnmanaged(*const fn (*Ecs) void) = .empty,
    /// Typed removers for singleton resources and events, run only on unload.
    removals: std.ArrayListUnmanaged(*const fn (*Ecs) void) = .empty,
};

/// Scope table owned by the world. Index 0 is the root scope (host
/// registrations); additional slots are created per dynamically loaded module
/// and can be torn down independently for hot reload. A `null` slot is
/// reclaimed and reused by the next `beginModule`.
pub const Scopes = struct {
    slots: std.ArrayListUnmanaged(?Entry) = .empty,
    /// Scope receiving new registrations. Always 0 outside `beginModule`.
    current: Handle = 0,
};

/// Creates the root scope.
pub fn init(self: *Ecs) void {
    self.scopes.slots.append(self.allocator, .{
        .name = self.allocator.dupe(u8, "root") catch @panic("oom"),
    }) catch @panic("oom");
}

/// Tears down every active scope (running deinitializers and removers), then
/// frees the scope table.
pub fn deinit(self: *Ecs) void {
    var i = self.scopes.slots.items.len;
    while (i > 0) {
        i -= 1;
        if (self.scopes.slots.items[i] != null) deinitScope(self, @intCast(i), .unload);
    }
    self.scopes.slots.deinit(self.allocator);
}

pub fn addDeinit(self: *Ecs, f: *const fn (*Ecs) void) void {
    currentEntry(self).deinit_fns.append(self.allocator, f) catch @panic("oom");
}

pub fn addSystem(self: *Ecs, entity: zflecs.entity_t) void {
    currentEntry(self).systems.append(self.allocator, entity) catch @panic("oom");
}

pub fn addRemoval(self: *Ecs, f: *const fn (*Ecs) void) void {
    currentEntry(self).removals.append(self.allocator, f) catch @panic("oom");
}

pub fn addResourceDeinit(self: *Ecs, f: *const fn (*Ecs) void) void {
    currentEntry(self).resource_deinit_fns.append(self.allocator, f) catch @panic("oom");
}

fn currentEntry(self: *Ecs) *Entry {
    return if (self.scopes.slots.items[self.scopes.current]) |*s|
        s
    else
        @panic("registration scope is not active");
}

/// Starts a registration scope. Everything registered until `endModule` is
/// tracked so it can be torn down without touching other modules.
pub fn beginModule(self: *Ecs, name: []const u8) Handle {
    var handle: Handle = 0;
    for (self.scopes.slots.items, 0..) |slot, i| {
        if (i != 0 and slot == null) {
            handle = @intCast(i);
            break;
        }
    }
    if (handle == 0) {
        handle = @intCast(self.scopes.slots.items.len);
        self.scopes.slots.append(self.allocator, null) catch @panic("oom");
    }

    self.scopes.slots.items[handle] = .{
        .name = self.allocator.dupe(u8, name) catch @panic("oom"),
    };
    self.scopes.current = handle;
    return handle;
}

/// Ends the current registration scope.
pub fn endModule(self: *Ecs) void {
    self.scopes.current = 0;
}

/// Tears down everything registered by `handle`. On `reload`, systems and their
/// deinitializers are removed but components, resources and events persist for
/// the next version. On `unload`, resource/event deinitializers run and their
/// singletons are removed as well.
pub fn deinitModule(self: *Ecs, handle: Handle, teardown: Teardown) void {
    if (handle == 0 or handle >= self.scopes.slots.items.len) return;
    if (self.scopes.slots.items[handle] == null) return;
    deinitScope(self, handle, teardown);
}

pub fn deinitScope(self: *Ecs, handle: Handle, teardown: Teardown) void {
    const slot = &self.scopes.slots.items[handle];
    const scope_value = if (slot.*) |*s| s else return;

    // Stop scheduling this module's systems before running user teardown.
    for (scope_value.systems.items) |system| {
        zflecs.enable(self.world, system, false);
    }

    var i = scope_value.deinit_fns.items.len;
    while (i > 0) {
        i -= 1;
        scope_value.deinit_fns.items[i](self);
    }

    if (teardown == .unload) {
        i = scope_value.resource_deinit_fns.items.len;
        while (i > 0) {
            i -= 1;
            scope_value.resource_deinit_fns.items[i](self);
        }
    }

    for (scope_value.systems.items) |system| removeSystem(self, system);

    if (teardown == .unload) {
        for (scope_value.removals.items) |remove| remove(self);
    }

    scope_value.systems.deinit(self.allocator);
    scope_value.deinit_fns.deinit(self.allocator);
    scope_value.resource_deinit_fns.deinit(self.allocator);
    scope_value.removals.deinit(self.allocator);
    self.allocator.free(scope_value.name);
    slot.* = null;
}

fn removeSystem(self: *Ecs, entity: zflecs.entity_t) void {
    phases.forgetSystem(self, entity);
    zflecs.delete(self.world, entity);
}

pub fn systemDeinit(comptime T: type) *const fn (*Ecs) void {
    return struct {
        fn run(_: *Ecs) void {
            T.deinit();
        }
    }.run;
}

pub fn resourceDeinit(comptime T: type) *const fn (*Ecs) void {
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

pub fn eventDeinit(comptime E: type) *const fn (*Ecs) void {
    return struct {
        fn run(ecs: *Ecs) void {
            const event = zflecs.singleton_get_mut(ecs.world, E) orelse return;
            event.deinit(ecs.allocator);
        }
    }.run;
}

pub fn singletonRemoval(comptime T: type) *const fn (*Ecs) void {
    return struct {
        fn run(ecs: *Ecs) void {
            zflecs.singleton_remove(ecs.world, T);
        }
    }.run;
}
