const std = @import("std");

const zpool = @import("zpool");

pub fn Assets(
    comptime index_bits: u8,
    comptime cycle_bits: u8,
    comptime T: type,
) type {
    const Pool = zpool.Pool(
        index_bits,
        cycle_bits,
        *T,
        T,
    );

    return struct {
        const Self = @This();

        pub const Handle = Pool.Handle;

        pool: Pool,

        pub fn init(allocator: std.mem.Allocator) !Self {
            return Self{
                .pool = try Pool.initMaxCapacity(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.pool.deinit();
        }

        pub fn add(self: *Self, value: T) !Handle {
            return try self.pool.add(value);
        }

        pub fn set(self: *Self, handle: Handle, value: T) !void {
            try self.pool.setColumns(handle, value);
        }

        pub fn remove(self: *Self, handle: Handle) !void {
            try self.pool.remove(handle);
        }

        pub fn setColumn(self: *Self, handle: Handle, column: Pool.Column, value: Pool.ColumnType(column)) !void {
            try self.pool.setColumn(handle, column, value);
        }

        pub fn getColumn(self: *Self, handle: Handle, column: Pool.Column) !Pool.Columns {
            try self.pool.getColumns(handle, column);
        }

        pub fn getColumns(self: *Self, handle: Handle) !Pool.Columns {
            try self.pool.getColumns(handle);
        }
    };
}
