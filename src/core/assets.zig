//! Asset collection backed by a zpool storage pool. Each asset type gets its
//! own `Assets(T)` singleton; consumers read assets through stable `Handle`s.

const std = @import("std");

const zpool = @import("zpool");

/// Singleton collection of `T` assets, injected into systems as a resource.
pub fn Assets(
    comptime T: type,
) type {
    const Pool = zpool.Pool(16, 16, T, T);

    return struct {
        pub const RESOURCE = {};

        const Self = @This();

        /// Generational handle to a stored asset. Comparing handles is safe
        /// across removals.
        pub const Handle = Pool.Handle;
        const Column = Pool.Column;
        const ColumnType = Pool.ColumnType;

        pool: Pool,

        /// Assets added since the last time a consumer drained the queue.
        /// The render module uses this to upload meshes without the demo
        /// having to know about GPU resources.
        pending: std.ArrayListUnmanaged(Handle) = .empty,

        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .pool = Pool.initMaxCapacity(allocator) catch @panic("oom"),
                .allocator = allocator,
            };
        }

        /// Releases all live assets (zpool calls `deinit` on them, if defined)
        /// and deinitializes the collection.
        pub fn deinit(self: *Self) void {
            self.pending.deinit(self.allocator);
            self.pool.deinit();
        }

        /// Adds an asset and queues its handle in `pending`.
        pub fn add(self: *Self, value: T) !Handle {
            const handle = try self.pool.add(value);
            errdefer _ = self.pool.removeIfLive(handle);

            try self.pending.append(self.allocator, handle);

            return handle;
        }

        /// Overwrites a live asset in place.
        pub fn set(self: *Self, handle: Handle, value: T) !void {
            try self.pool.setColumns(handle, value);
        }

        /// Removes an asset and drops its bookkeeping entries.
        pub fn remove(self: *Self, handle: Handle) !void {
            try self.pool.remove(handle);
            for (self.pending.items, 0..) |tracked, i| {
                if (tracked.id == handle.id) {
                    _ = self.pending.orderedRemove(i);
                    break;
                }
            }
        }

        /// Pops the next queued upload handle, or null when drained.
        pub fn popPending(self: *Self) ?Handle {
            return self.pending.pop();
        }

        pub fn getColumn(self: *Self, handle: Handle, comptime column: Column) !ColumnType(column) {
            return try self.pool.getColumn(handle, column);
        }

        pub fn getColumns(self: *Self, handle: Handle) !Pool.Columns {
            return try self.pool.getColumns(handle);
        }

        /// Like `getColumns`, but returns null for dead handles instead of an
        /// error.
        pub fn getColumnsIfLive(self: *Self, handle: Handle) ?Pool.Columns {
            return self.pool.getColumnsIfLive(handle);
        }
    };
}
