//! World lifetime and the frame loop.
//!
//! Owns `Ecs.init`/`deinit`, the `progress`/`run`/`quit` loop entry points and
//! termination-signal handling.

const std = @import("std");
const builtin = @import("builtin");

const zflecs = @import("zflecs");

const z = @import("../../root.zig");
const ecs_mod = @import("../ecs.zig");
const Ecs = ecs_mod.Ecs;
const phases = @import("phases.zig");
const registration = @import("registration.zig");
const scopes = @import("scopes.zig");

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

/// Creates the world and registers image loading. The default phases are
/// registered by `z.Phase` (or any type carrying a `PHASE` marker), which must
/// be registered before systems.
pub fn init(allocator: std.mem.Allocator) *Ecs {
    const self = allocator.create(Ecs) catch @panic("oom");
    self.* = .{
        .allocator = allocator,
        .world = zflecs.init(),
        .id = next_world_id.fetchAdd(1, .monotonic),
    };
    scopes.init(self);

    z.zstbi.init(allocator) catch @panic("zstbi init fail");
    return self;
}

/// Runs registered deinitializers in reverse scope and registration order, then
/// destroys the flecs world and the `Ecs` allocation.
pub fn deinit(self: *Ecs) void {
    scopes.deinit(self);
    registration.deinit(self);
    phases.deinit(self);

    z.zstbi.deinit();
    _ = zflecs.fini(self.world);
    self.allocator.destroy(self);
}

/// Runs one frame: all systems in phase order. The `pre_progress` hook runs
/// first, at a safe point before flecs starts iterating. After the first frame
/// the `startup` phase is disabled so its systems run exactly once.
pub fn progress(self: *Ecs) void {
    if (self.pre_progress) |hook| hook(self, self.pre_progress_ctx);
    _ = zflecs.progress(self.world, 0);
    phases.finishStartup(self);
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
