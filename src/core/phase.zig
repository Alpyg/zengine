//! Frame phases and system sets.
//!
//! `Phase` is a plain enum of top-level pipeline phases, auto-registered through
//! its `PHASE` marker. Custom sets use the same marker with a parent:
//! `pub const PHASE = .{ .parent = Phase.update };`. Each value maps to a named
//! phase entity in the flecs world, shared by every module in that world.
//!
//! `Phase.startup` runs once: its systems are disabled after the first
//! `Ecs.progress`, making it the place for one-time setup without a `done` flag.

const std = @import("std");

const zflecs = @import("zflecs");

pub const Phase = enum(u8) {
    pub const PHASE = .{};

    /// Runs once on first frame. Disabled afterwards.
    startup,
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

/// Stable, world-level name for one phase value. Phase entities are stored in
/// the flecs world (not in per-type globals) so that separately compiled
/// modules - including hot-reloaded shared libraries - resolve the same
/// entities. The type name enters through a hash so the result is a single
/// flecs name (no `.' path separators) and is identical in every DSO.
pub fn phaseName(comptime S: type, comptime value: S) [:0]const u8 {
    return comptime std.fmt.comptimePrint("phase_{x}_{s}", .{
        std.hash.Wyhash.hash(0, @typeName(S)),
        @tagName(value),
    });
}

/// Resolves one phase value to its entity. Panics if the phase was not
/// registered for this world.
pub inline fn phaseEntity(ecs: anytype, comptime S: type, comptime value: S) zflecs.entity_t {
    const phase_entity = zflecs.lookup(ecs.world, phaseName(S, value).ptr);
    if (phase_entity == 0) {
        @panic("phase '" ++ @typeName(S) ++ "." ++ @tagName(value) ++
            "' is not registered for this world; initialize it before use");
    }
    return phase_entity;
}

pub inline fn entity(ecs: anytype, comptime phase: Phase) zflecs.entity_t {
    return phaseEntity(ecs, Phase, phase);
}

/// Next top-level phase, or null for `last`.
pub fn next(phase: Phase) ?Phase {
    const count = @typeInfo(Phase).@"enum".field_names.len;
    const i = @backingInt(phase) + 1;
    return if (i >= count) null else @fromBackingInt(@intCast(i));
}

/// Resolves a top-level phase or a custom set value to its entity.
pub inline fn resolve(ecs: anytype, comptime phase: anytype) zflecs.entity_t {
    return phaseEntity(ecs, @TypeOf(phase), phase);
}
