//! C ABI shared between the engine host and dynamically loaded modules.
//!
//! Modules are ordinary Zig code compiled against the same engine source and
//! compiler version. Only the small descriptor below crosses the shared-library
//! boundary; everything else is passed as an opaque `*anyopaque`.

const std = @import("std");
const builtin = @import("builtin");
const zflecs = @import("zflecs");

pub const ABI_VERSION: u32 = 1;
pub const ENGINE_VERSION = "0.0.1";

pub const ModuleDesc = extern struct {
    abi_version: u32,
    engine_version: [*:0]const u8,
    zig_version: [*:0]const u8,
    target: [*:0]const u8,
    optimize: [*:0]const u8,
    name: [*:0]const u8,
    init: *const fn (ecs: *anyopaque) callconv(.c) void,
    pre_reload: ?*const fn (ecs: *anyopaque) callconv(.c) void,
    deinit: ?*const fn (ecs: *anyopaque) callconv(.c) void,
};

fn cstr(comptime s: []const u8) [*:0]const u8 {
    return std.fmt.comptimePrint("{s}", .{s});
}

pub fn targetString() [*:0]const u8 {
    return std.fmt.comptimePrint("{s}-{s}", .{
        @tagName(builtin.cpu.arch),
        @tagName(builtin.os.tag),
    });
}

/// Builds the descriptor for module namespace `M`.
///
/// `M` may declare:
/// - `pub fn init(ecs: *Ecs) void`          (default: `ecs.register(M)`)
/// - `pub fn preReload(ecs: *Ecs) void`     (optional, called before teardown)
/// - `pub fn deinit(ecs: *Ecs) void`        (optional, non-ECS cleanup)
pub fn descriptor(comptime Ecs: type, comptime M: type) *const ModuleDesc {
    return &ModuleDesc{
        .abi_version = ABI_VERSION,
        .engine_version = cstr(ENGINE_VERSION),
        .zig_version = cstr(builtin.zig_version_string),
        .target = targetString(),
        .optimize = cstr(@tagName(builtin.mode)),
        .name = cstr(@typeName(M)),
        .init = struct {
            fn call(ecs: *anyopaque) callconv(.c) void {
                // Each shared object gets its own copy of the flecs globals.
                // Initialize their OS API before touching the host's world.
                zflecs.os_init();

                const e: *Ecs = @ptrCast(@alignCast(ecs));
                if (@hasDecl(M, "init")) {
                    M.init(e);
                } else {
                    _ = e.register(M);
                }
            }
        }.call,
        .pre_reload = if (@hasDecl(M, "preReload")) struct {
            fn call(ecs: *anyopaque) callconv(.c) void {
                const e: *Ecs = @ptrCast(@alignCast(ecs));
                M.preReload(e);
            }
        }.call else null,
        .deinit = if (@hasDecl(M, "deinit")) struct {
            fn call(ecs: *anyopaque) callconv(.c) void {
                const e: *Ecs = @ptrCast(@alignCast(ecs));
                M.deinit(e);
            }
        }.call else null,
    };
}
