//! Runtime loader for dynamic engine modules. Watches the build output and
//! swaps modules at frame boundaries.
//!
//! For hot reload to be sound a module must not keep persistent state in its
//! own globals: all state must live in the `Ecs` world (entities, components,
//! resources). The loader tears down everything registered inside the module's
//! `Ecs` scope before unloading the library.

const std = @import("std");
const builtin = @import("builtin");

const z = @import("z");
const abi = z.hot;

pub const Module = struct {
    lib: std.DynLib,
    desc: *const abi.ModuleDesc,
    handle: z.Ecs.ModuleHandle = 0,
    /// Build output that is watched for changes. Empty for a prepared module.
    source: []u8 = &.{},
    /// Private copy that is actually loaded (avoids locks on the build output).
    cache: []u8,
    mtime: i96 = 0,
    generation: u32,
    needs_reload: bool = false,
};

pub const LoadedModule = Module;

const Prepared = Module;

pub const Loader = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    cache_dir: []u8,
    modules: std.ArrayListUnmanaged(LoadedModule) = .empty,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, cache_dir: []const u8) !Loader {
        try std.Io.Dir.cwd().createDirPath(io, cache_dir);
        return .{
            .allocator = allocator,
            .io = io,
            .cache_dir = try allocator.dupe(u8, cache_dir),
        };
    }

    pub fn deinit(self: *Loader, ecs: *z.Ecs) void {
        var i = self.modules.items.len;
        while (i > 0) {
            i -= 1;
            self.unloadIndex(ecs, i);
        }
        self.modules.deinit(self.allocator);
        self.allocator.free(self.cache_dir);
    }

    /// Installs the frame-start hook used to apply pending reloads outside of
    /// a flecs iteration.
    pub fn install(self: *Loader, ecs: *z.Ecs) void {
        ecs.pre_progress = hook;
        ecs.pre_progress_ctx = self;
    }

    fn hook(ecs: *z.Ecs, ctx: ?*anyopaque) void {
        const self: *Loader = @ptrCast(@alignCast(ctx orelse return));
        self.poll();
        self.processPending(ecs);
    }

    /// Loads `source_path` and registers the module. The source file is copied
    /// to the loader's cache before being opened.
    pub fn load(self: *Loader, ecs: *z.Ecs, source_path: []const u8) !void {
        const source = try self.allocator.dupe(u8, source_path);
        errdefer self.allocator.free(source);

        var prepared = try self.prepare(source, 0, source);
        errdefer {
            prepared.lib.close();
            self.allocator.free(prepared.cache);
        }

        const handle = try self.initPrepared(ecs, &prepared, .unload);
        prepared.handle = handle;
        prepared.source = source;
        try self.modules.append(self.allocator, prepared);

        std.log.info("Loaded module `{s}` from {s}", .{ std.mem.span(prepared.desc.name), source });
    }

    /// Checks source modification times. Cheap; safe to call every frame.
    pub fn poll(self: *Loader) void {
        for (self.modules.items) |*module| {
            const stat = std.Io.Dir.cwd().statFile(self.io, module.source, .{}) catch continue;
            if (stat.mtime.nanoseconds != module.mtime) module.needs_reload = true;
        }
    }

    /// Applies pending reloads. Must be called at a frame boundary, before
    /// flecs starts iterating (see `install`).
    pub fn processPending(self: *Loader, ecs: *z.Ecs) void {
        var i: usize = 0;
        while (i < self.modules.items.len) {
            if (self.modules.items[i].needs_reload) {
                self.modules.items[i].needs_reload = false;
                // On a failed rollback the module is removed and the element
                // at `i` is now a different module, so do not advance.
                if (!self.reloadIndex(ecs, i)) continue;
            }
            i += 1;
        }
    }

    fn reloadIndex(self: *Loader, ecs: *z.Ecs, i: usize) bool {
        const module = &self.modules.items[i];
        const prev_cache = module.cache;
        const prev_generation = module.generation;

        var prepared = self.prepare(module.source, prev_generation + 1, module.source) catch |err| {
            std.log.err("Hot reload of `{s}` failed to load: {s}", .{
                module.source,
                @errorName(err),
            });
            self.markSourceSeen(module);
            return true;
        };

        // Tear down the old generation only after the new library has been
        // opened and validated.
        if (module.desc.pre_reload) |f| f(@ptrCast(ecs));
        ecs.deinitModule(module.handle, .reload);
        if (module.desc.deinit) |f| f(@ptrCast(ecs));
        module.lib.close();

        const handle = self.initPrepared(ecs, &prepared, .reload) catch |err| {
            std.log.err("Hot reload of `{s}` failed during init: {s}; rolling back", .{
                module.source,
                @errorName(err),
            });
            prepared.lib.close();
            self.allocator.free(prepared.cache);
            const alive = self.rollbackIndex(ecs, i, prev_cache, prev_generation);
            if (alive) self.markSourceSeen(module);
            return alive;
        };

        self.allocator.free(prev_cache);
        prepared.handle = handle;
        prepared.source = module.source;
        module.* = prepared;

        std.log.info("Reloaded module `{s}` (generation {d})", .{
            std.mem.span(prepared.desc.name),
            prepared.generation,
        });
        return true;
    }

    fn rollbackIndex(
        self: *Loader,
        ecs: *z.Ecs,
        i: usize,
        prev_cache: []u8,
        prev_generation: u32,
    ) bool {
        const module = &self.modules.items[i];

        var rolled = self.prepare(prev_cache, prev_generation, null) catch |err| {
            std.log.err("Could not restore previous module `{s}`: {s}; module is now unloaded", .{
                module.source,
                @errorName(err),
            });
            self.allocator.free(prev_cache);
            self.allocator.free(module.source);
            _ = self.modules.swapRemove(i);
            return false;
        };

        const handle = self.initPrepared(ecs, &rolled, .reload) catch |err| {
            std.log.err("Could not restore previous module `{s}`: {s}; module is now unloaded", .{
                module.source,
                @errorName(err),
            });
            rolled.lib.close();
            self.allocator.free(rolled.cache);
            self.allocator.free(prev_cache);
            self.allocator.free(module.source);
            _ = self.modules.swapRemove(i);
            return false;
        };

        rolled.handle = handle;
        rolled.source = module.source;
        module.* = rolled;
        self.allocator.free(prev_cache);
        return true;
    }

    fn unloadIndex(self: *Loader, ecs: *z.Ecs, i: usize) void {
        const module = &self.modules.items[i];

        if (module.desc.pre_reload) |f| f(@ptrCast(ecs));
        ecs.deinitModule(module.handle, .unload);
        if (module.desc.deinit) |f| f(@ptrCast(ecs));
        module.lib.close();

        self.allocator.free(module.source);
        self.allocator.free(module.cache);
        _ = self.modules.swapRemove(i);
    }

    fn initPrepared(
        self: *Loader,
        ecs: *z.Ecs,
        prepared: *const Prepared,
        failure_teardown: z.Ecs.Teardown,
    ) !z.Ecs.ModuleHandle {
        _ = self;
        ecs.clearComponentConflict();
        const handle = ecs.beginModule(std.mem.span(prepared.desc.name));
        errdefer ecs.deinitModule(handle, failure_teardown);

        prepared.desc.init(@ptrCast(ecs));
        ecs.endModule();

        if (ecs.hasComponentConflict()) return error.ComponentLayoutChanged;
        return handle;
    }

    /// Records the current source mtime so a failed reload is not retried until
    /// the file changes again.
    fn markSourceSeen(self: *Loader, module: *LoadedModule) void {
        const stat = std.Io.Dir.cwd().statFile(self.io, module.source, .{}) catch return;
        module.mtime = stat.mtime.nanoseconds;
    }

    /// Opens a module. When `copy_from` is set, that build output is copied to
    /// the cache first; otherwise `path` is already a cached library.
    fn prepare(
        self: *Loader,
        path: []const u8,
        generation: u32,
        copy_from: ?[]const u8,
    ) !Prepared {
        var cache: []u8 = undefined;
        var mtime: i96 = 0;

        if (copy_from) |source| {
            const base = std.fs.path.basename(source);
            cache = try std.fmt.allocPrint(
                self.allocator,
                "{s}/{s}.{d}.so",
                .{ self.cache_dir, base, generation },
            );
            errdefer self.allocator.free(cache);

            const cwd = std.Io.Dir.cwd();
            try cwd.createDirPath(self.io, self.cache_dir);
            try cwd.copyFile(source, cwd, cache, self.io, .{});
            const stat = try cwd.statFile(self.io, source, .{});
            mtime = stat.mtime.nanoseconds;
        } else {
            cache = try self.allocator.dupe(u8, path);
            errdefer self.allocator.free(cache);
        }

        var prepared = try self.openValidated(cache, generation);
        prepared.cache = cache;
        prepared.mtime = mtime;
        return prepared;
    }

    fn openValidated(self: *Loader, path: []const u8, generation: u32) !Prepared {
        _ = self;
        var lib = try std.DynLib.open(path);
        errdefer lib.close();

        const entry = lib.lookup(
            *const fn () callconv(.c) *const abi.ModuleDesc,
            "zengine_module_v1",
        ) orelse return error.MissingEntryPoint;

        const desc = entry();
        try validate(desc);

        return .{
            .lib = lib,
            .desc = desc,
            .cache = &.{}, // filled by the caller
            .mtime = 0,
            .generation = generation,
        };
    }
};

fn validate(desc: *const abi.ModuleDesc) !void {
    if (desc.abi_version != abi.ABI_VERSION) return error.AbiMismatch;
    if (!std.mem.eql(u8, std.mem.span(desc.zig_version), builtin.zig_version_string))
        return error.ZigVersionMismatch;
    if (!std.mem.eql(u8, std.mem.span(desc.target), std.mem.span(abi.targetString())))
        return error.TargetMismatch;
    if (!std.mem.eql(u8, std.mem.span(desc.optimize), @tagName(builtin.mode)))
        return error.OptimizeMismatch;
    if (!std.mem.eql(u8, std.mem.span(desc.engine_version), abi.ENGINE_VERSION))
        return error.EngineVersionMismatch;
}
