//! Phase registration and enabling.
//!
//! Top-level `Phase` values and custom set enums are both stored as named
//! entities in the flecs world. `phase.zig` owns the name scheme and lookup;
//! this file owns registration and enable/disable behavior.

const std = @import("std");
const zflecs = @import("zflecs");

const ecs_mod = @import("../ecs.zig");
const Ecs = ecs_mod.Ecs;
const phase_module = @import("../phase.zig");
const Phase = phase_module.Phase;

/// System entities grouped by their phase or set value. Used by
/// `setPhaseEnabled` to disable set membership without breaking phase order.
pub const PhaseSystems = struct {
    map: std.AutoHashMapUnmanaged(zflecs.entity_t, std.ArrayListUnmanaged(zflecs.entity_t)) = .{},
    /// Set after the first frame, once the startup phase has been disabled.
    startup_done: bool = false,
};

/// Records `system` under its scheduling entity so it can be enabled/disabled
/// with its phase or set.
pub fn trackSystem(self: *Ecs, phase_entity: zflecs.entity_t, system: zflecs.entity_t) void {
    const gop = self.phase_systems.map.getOrPut(self.allocator, phase_entity) catch @panic("oom");
    if (!gop.found_existing) gop.value_ptr.* = .empty;
    gop.value_ptr.append(self.allocator, system) catch @panic("oom");

    // A startup system registered after the first frame cannot run its "once":
    // keep it disabled so it never becomes a per-frame system.
    if (self.phase_systems.startup_done) {
        const startup = zflecs.lookup(
            self.world,
            phase_module.phaseName(Phase, .startup).ptr,
        );
        if (startup == phase_entity) zflecs.enable(self.world, system, false);
    }
}

/// Removes `entity` from its phase group, if tracked.
pub fn forgetSystem(self: *Ecs, entity: zflecs.entity_t) void {
    var it = self.phase_systems.map.valueIterator();
    while (it.next()) |systems| {
        if (std.mem.indexOfScalar(zflecs.entity_t, systems.items, entity)) |idx| {
            _ = systems.swapRemove(idx);
            break;
        }
    }
}

/// Frees every phase group.
pub fn deinit(self: *Ecs) void {
    var it = self.phase_systems.map.valueIterator();
    while (it.next()) |systems| systems.deinit(self.allocator);
    self.phase_systems.map.deinit(self.allocator);
}

/// Creates a named phase entity and chains it after `depends_on` (if any).
fn registerPhase(
    self: *Ecs,
    phase: *zflecs.entity_t,
    name: [:0]const u8,
    depends_on: ?zflecs.entity_t,
) *Ecs {
    phase.* = zflecs.entity_init(self.world, &.{
        .name = name.ptr,
        .use_low_id = true,
    });
    zflecs.add_id(self.world, phase.*, zflecs.Phase);

    if (depends_on) |depended_on| {
        zflecs.add_pair(self.world, phase.*, zflecs.DependsOn, depended_on);
    }

    return self;
}

/// Creates one phase entity per enum value, chained after `parent` when given.
/// Returns the last entity in the chain, or `parent` when the enum is empty.
fn registerPhaseChain(self: *Ecs, comptime S: type, parent: ?zflecs.entity_t) ?zflecs.entity_t {
    var prev = parent;
    inline for (@typeInfo(S).@"enum".field_names) |field_name| {
        const value = comptime @field(S, field_name);
        var e: zflecs.entity_t = undefined;
        _ = registerPhase(self, &e, phase_module.phaseName(S, value), prev);
        prev = e;
    }

    return prev;
}

/// Registers every value of the phase enum `S` as a top-level flecs phase,
/// chained in declaration order. Returns `self` for chaining.
pub fn registerPhases(self: *Ecs, comptime S: type) *Ecs {
    comptime assertEnum(S, "registerPhases");

    _ = registerPhaseChain(self, S, null);

    std.log.debug("Registered phases `{s}`", .{@typeName(S)});
    return self;
}

/// Registers every value of the set enum `S` as a subphase of `phase`, chained
/// in declaration order. Must be called before registering systems that use the
/// set. Returns `self` for chaining.
pub fn registerPhaseSet(self: *Ecs, comptime phase: Phase, comptime S: type) *Ecs {
    comptime assertEnum(S, "registerPhaseSet");

    const parent = phase_module.entity(self, phase);
    const last = registerPhaseChain(self, S, parent);

    // Keep the set inside the parent phase's slot. Disabling a set value skips
    // its systems (and later values), but not this phase dependency.
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

/// Disables the startup phase's systems after the first frame so they run
/// exactly once. The phase entity stays enabled: later phases depend on it, and
/// disabling it would deactivate the whole pipeline. No-op if the phase was
/// never registered.
pub fn finishStartup(self: *Ecs) void {
    if (self.phase_systems.startup_done) return;
    self.phase_systems.startup_done = true;

    const startup = zflecs.lookup(
        self.world,
        phase_module.phaseName(Phase, .startup).ptr,
    );
    if (startup != 0) setSystemsEnabled(self, startup, false);
}

/// Enables or disables a top-level phase, an entire set enum, or a single set
/// value. Top-level phases disable their dependency subtree; set values disable
/// their systems (and later values in the same set) without disabling the
/// phases that depend on the set. `Phase.startup` is special-cased: only its
/// systems are toggled so the rest of the pipeline stays active.
pub fn setPhaseEnabled(self: *Ecs, comptime phase: anytype, enabled: bool) void {
    const T = @TypeOf(phase);
    if (T == Phase) {
        if (phase == .startup) {
            // `startup` sits in the phase chain, so toggling the phase entity
            // would also deactivate every phase chained after it. Toggle its
            // systems instead; re-enabling asks for one more run before they
            // are disabled again.
            self.phase_systems.startup_done = !enabled;
            setSystemsEnabled(self, phase_module.entity(self, phase), enabled);
            return;
        }
        zflecs.enable(self.world, phase_module.entity(self, phase), enabled);
    } else if (T == type) {
        setPhaseEnumSystemsEnabled(self, phase, 0, enabled);
    } else {
        setPhaseEnumSystemsEnabled(self, T, enumIndex(T, phase), enabled);
    }
}

fn setPhaseEnumSystemsEnabled(self: *Ecs, comptime S: type, comptime start: usize, enabled: bool) void {
    inline for (@typeInfo(S).@"enum".field_names, 0..) |name, i| {
        if (comptime i >= start) {
            const value = comptime @field(S, name);
            setSystemsEnabled(self, phase_module.phaseEntity(self, S, value), enabled);
        }
    }
}

fn setSystemsEnabled(self: *Ecs, phase_entity: zflecs.entity_t, enabled: bool) void {
    const systems = self.phase_systems.map.getPtr(phase_entity) orelse return;
    for (systems.items) |system| zflecs.enable(self.world, system, enabled);
}

fn enumIndex(comptime S: type, comptime value: S) usize {
    inline for (@typeInfo(S).@"enum".field_names, 0..) |name, i| {
        if (@field(S, name) == value) return i;
    }
    unreachable;
}
