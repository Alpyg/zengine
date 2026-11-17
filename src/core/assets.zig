const std = @import("std");

const zpool = @import("zpool");

pub fn Assets(
    comptime T: type,
) type {
    const Pool = zpool.Pool(16, 16, T, T);

    return struct {
        pub const RESOURCE = {};

        const Self = @This();

        pub const Handle = Pool.Handle;
        const Column = Pool.Column;
        const ColumnType = Pool.ColumnType;

        pool: Pool,

        /// Handles that have been added and not removed yet. zpool does not
        /// expose iteration, so the asset collection keeps its own list for
        /// cleanup and for subsystems that need to walk all assets.
        handles: std.ArrayListUnmanaged(Handle) = .empty,

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

        pub fn deinit(self: *Self) void {
            for (self.handles.items) |handle| {
                if (self.pool.getColumnsIfLive(handle)) |value| {
                    if (@hasDecl(T, "deinit")) {
                        var owned = value;
                        owned.deinit();
                    }
                }
            }
            self.handles.deinit(self.allocator);
            self.pending.deinit(self.allocator);
            self.pool.deinit();
        }

        pub fn add(self: *Self, value: T) !Handle {
            const handle = try self.pool.add(value);
            errdefer _ = self.pool.removeIfLive(handle);

            try self.handles.append(self.allocator, handle);
            errdefer _ = self.handles.pop();

            try self.pending.append(self.allocator, handle);

            return handle;
        }

        pub fn set(self: *Self, handle: Handle, value: T) !void {
            try self.pool.setColumns(handle, value);
        }

        pub fn remove(self: *Self, handle: Handle) !void {
            try self.pool.remove(handle);
            for (self.handles.items, 0..) |tracked, i| {
                if (tracked.id == handle.id) {
                    _ = self.handles.orderedRemove(i);
                    break;
                }
            }
            for (self.pending.items, 0..) |tracked, i| {
                if (tracked.id == handle.id) {
                    _ = self.pending.orderedRemove(i);
                    break;
                }
            }
        }

        pub fn popPending(self: *Self) ?Handle {
            return self.pending.pop();
        }

        pub fn getColumn(self: *Self, handle: Handle, comptime column: Column) !ColumnType(column) {
            return try self.pool.getColumn(handle, column);
        }

        pub fn getColumns(self: *Self, handle: Handle) !Pool.Columns {
            return try self.pool.getColumns(handle);
        }

        pub fn getColumnsIfLive(self: *Self, handle: Handle) ?Pool.Columns {
            return self.pool.getColumnsIfLive(handle);
        }
    };
}
