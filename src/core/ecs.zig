//! ECS facade over flecs. Owns the world and its per-world state, and exposes
//! the engine-facing interface.
//!
//! Registration conventions (implemented in `ecs/registration.zig`):
//! - a type with `RESOURCE` is a singleton resource; `init(ecs)` is called once
//! - a type with `COMPONENT` is a component, or a tag when it is zero-sized
//! - a type with `phase` + `run` is a system (produced by `System(...)`)
//! - a type with `PHASE` is a phase enum; `.{ .parent = Phase.x }` registers it
//!   as a set under `x`, while `.{ }` registers a top-level phase chain
//! - a type with `EVENT_QUEUE` comes from `Event(T)`
//! - any other struct is treated as a namespace and its declarations are
//!   registered recursively (non-systems first, then systems)
//!
//! This file only holds the state every part needs and forwards the public API
//! to the implementation modules in `ecs/`:
//! - `lifecycle.zig`    world lifetime and the frame loop
//! - `scopes.zig`       registration scopes and teardown
//! - `registration.zig` ECS type registration
//! - `phases.zig`       phase registration and enabling
//! - `entities.zig`     entity helpers

const std = @import("std");

const zflecs = @import("zflecs");

const entities = @import("ecs/entities.zig");
const lifecycle = @import("ecs/lifecycle.zig");
const phases = @import("ecs/phases.zig");
const registration = @import("ecs/registration.zig");
const scopes_mod = @import("ecs/scopes.zig");

pub const Assets = @import("assets.zig").Assets;
pub const Event = @import("event.zig").Event;
pub const Parent = @import("query.zig").Parent;
pub const Phase = @import("phase.zig").Phase;
pub const Query = @import("query.zig").Query;
pub const Resource = @import("resource.zig").Resource;
pub const System = @import("system.zig").System;
pub const With = @import("query.zig").With;
pub const Without = @import("query.zig").Without;

pub const Ecs = @This();

pub const ModuleHandle = scopes_mod.Handle;
pub const ModuleScope = scopes_mod.Entry;
pub const Teardown = scopes_mod.Teardown;
pub const ComponentLayout = registration.ComponentLayout;

allocator: std.mem.Allocator = undefined,

/// Underlying flecs world.
world: *zflecs.world_t = undefined,

/// Unique per-world generation. Caches (phases, sets) are rebuilt when it
/// changes.
id: u64 = 0,

/// Set by `quit`; checked by `run`.
should_exit: bool = false,

/// Called at the start of every `progress`, before flecs runs any system.
/// Dynamic-module loaders use this to apply pending reloads at a frame
/// boundary instead of in the middle of an iteration.
pre_progress: ?*const fn (*Ecs, ?*anyopaque) void = null,
pre_progress_ctx: ?*anyopaque = null,

/// Registration scope table (root scope plus one slot per loaded module).
scopes: scopes_mod.Scopes = .{},

/// Component layout registry, used to reject layout changes on hot reload.
layouts: registration.Layouts = .{},

/// System entities grouped by their phase or set value.
phase_systems: phases.PhaseSystems = .{},

// -------------------------------------------------------------------------
// World lifetime and frame loop (implemented in `ecs/lifecycle.zig`)
// -------------------------------------------------------------------------

/// Creates the world and registers image loading. The default phases are
/// registered by `z.Phase`, which must be registered before systems.
pub const init = lifecycle.init;

/// Runs registered deinitializers in reverse scope and registration order, then
/// destroys the flecs world and the `Ecs` allocation.
pub const deinit = lifecycle.deinit;

/// Runs one frame: all systems in phase order. The `pre_progress` hook runs
/// first, at a safe point before flecs starts iterating.
pub const progress = lifecycle.progress;

/// Runs frames until `quit` is called or a termination signal arrives.
pub const run = lifecycle.run;

/// Requests that `run` stop after the current frame.
pub const quit = lifecycle.quit;

// -------------------------------------------------------------------------
// Entities (implemented in `ecs/entities.zig`)
// -------------------------------------------------------------------------

/// Creates an entity with a debug name.
pub const new = entities.new;

/// Adds one or more components. Accepts a component value, a component type
/// (for zero-sized tags), or a tuple of either.
pub const add = entities.add;

// -------------------------------------------------------------------------
// Registration scopes (implemented in `ecs/scopes.zig`)
// -------------------------------------------------------------------------

/// Starts a registration scope. Everything registered until `endModule` is
/// tracked so it can be torn down without touching other modules.
pub const beginModule = scopes_mod.beginModule;

/// Ends the current registration scope.
pub const endModule = scopes_mod.endModule;

/// Tears down everything registered by `handle`. `.reload` preserves
/// components/resources for the next version; `.unload` removes them too.
pub const deinitModule = scopes_mod.deinitModule;

// -------------------------------------------------------------------------
// ECS type registration (implemented in `ecs/registration.zig`)
// -------------------------------------------------------------------------

/// Registers `T` using the conventions documented at the top of this file:
/// resources and events are created through their `init(ecs)`, components and
/// tags are registered, and namespaces are traversed recursively.
pub const register = registration.register;

/// Inserts an already-constructed singleton value: a resource, an `Event(T)`
/// queue, or any non-empty struct. Existing values are preserved and only their
/// cleanup is re-registered.
pub const insert = registration.insert;

/// Whether the singleton resource `T` is already registered.
pub const hasResource = registration.hasResource;

/// Whether a registration observed a component layout mismatch.
pub const hasComponentConflict = registration.hasConflict;

/// Clears a previous layout conflict, e.g. before attempting a hot reload.
pub const clearComponentConflict = registration.clearConflict;

// -------------------------------------------------------------------------
// Phases (implemented in `ecs/phases.zig`)
// -------------------------------------------------------------------------

/// Enables or disables a top-level phase, an entire set enum, or a single set
/// value.
pub const setPhaseEnabled = phases.setPhaseEnabled;
