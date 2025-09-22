const std = @import("std");

const zpool = @import("zpool");

pub fn Assets(
    comptime index_bits: u8,
    comptime cycle_bits: u8,
    comptime TResource: type,
    comptime TColumns: type,
) type {
    const Pool = zpool.Pool(
        index_bits,
        cycle_bits,
        TResource,
        TColumns,
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

        pub fn add(self: *Self, value: TColumns) !Handle {
            const handle: Handle = try self.pool.add(value);

            return handle;
        }

        pub fn remove(self: *Self, handle: Handle) !void {
            try self.pool.remove(handle);
        }

        pub fn setColumns(self: *Self, handle: Handle, value: TColumns) !void {
            try self.pool.setColumns(handle, value);
        }

        pub fn setColumn(self: *Self, handle: Handle, column: Pool.Column, value: Pool.ColumnType(column)) !void {
            try self.pool.setColumn(handle, column, value);
        }

        pub fn getColumns(self: *Self, handle: Handle) !Pool.Columns {
            try self.pool.getColumns(handle);
        }

        pub fn getColumn(self: *Self, handle: Handle, column: Pool.Column) !Pool.Columns {
            try self.pool.getColumns(handle, column);
        }
    };
}
