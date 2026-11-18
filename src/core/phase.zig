//! Frame phases and system sets.
//!
//! `Phase` is a plain enum of top-level pipeline phases, auto-registered through
//! its `PHASE` marker. Custom sets use the same marker with a parent:
//! `pub const PHASE = .{ .parent = Phase.update };`. All phase enums are stored
//! through the same `PhaseStorage` API; each value maps to a flecs phase entity,
//! owned per world.

const std = @import("std");

const zflecs = @import("zflecs");

const Ecs = @import("ecs.zig");

pub const Phase = enum(u8) {
    pub const PHASE = .{};

    /// Input polling and asset setup.
    first,
    pre_update,
    /// Variable-timestep gameplay update.
    update,
    post_update,
    /// Camera preparation and ImGui frame setup/UI submission.
    pre_render,
    /// Main render phase.
    render,
    /// Command-buffer submission.
    post_render,
    /// Cleanup: end-of-frame event queues and transient GPU resources.
    last,
};

/// Per-world entity table for a phase enum (top-level `Phase` or a custom set).
/// The caller fills the entities; `get` validates that the table was
/// initialized for the `Ecs` being used.
pub fn PhaseStorage(comptime S: type) type {
    const count = @typeInfo(S).@"enum".field_names.len;

    return struct {
        pub var entities: [count]zflecs.entity_t = @splat(0);
        pub var world_id: u64 = 0;

        fn indexOf(comptime value: S) usize {
            inline for (std.meta.tags(S), 0..) |v, i| {
                if (v == value) return i;
            }
            unreachable;
        }

        /// Marks the table as belonging to `ecs`. Entities are filled by the
        /// caller.
        pub fn begin(ecs: anytype) void {
            world_id = ecs.id;
        }

        /// Stores the entity for `value`.
        pub fn set(comptime value: S, phase_entity: zflecs.entity_t) void {
            entities[indexOf(value)] = phase_entity;
        }

        /// Entity for `value`. Panics if the table was not initialized for this
        /// world.
        pub fn get(ecs: anytype, comptime value: S) zflecs.entity_t {
            if (world_id != ecs.id) {
                @panic("phase '" ++ @typeName(S) ++
                    "' is not registered for this world; initialize it before use");
            }
            return entities[indexOf(value)];
        }
    };
}

/// Module: registers the default `Phase` enum in the world.
pub const PhaseModule = struct {
    pub fn init(_: PhaseModule, ecs: *Ecs) void {
        _ = ecs.registerEcs(Phase);
    }
};

pub inline fn entity(ecs: anytype, comptime phase: Phase) zflecs.entity_t {
    return PhaseStorage(Phase).get(ecs, phase);
}

/// Next top-level phase, or null for `last`.
pub fn next(phase: Phase) ?Phase {
    const count = @typeInfo(Phase).@"enum".field_names.len;
    const i = @backingInt(phase) + 1;
    return if (i >= count) null else @fromBackingInt(@intCast(i));
}

/// Resolves a top-level phase or a custom set value to its entity, using the
/// same storage API for both.
pub inline fn resolve(ecs: anytype, comptime phase: anytype) zflecs.entity_t {
    return PhaseStorage(@TypeOf(phase)).get(ecs, phase);
}
