const std = @import("std");

const zflecs = @import("zflecs");

pub fn System(phase: *zflecs.entity_t, comptime S: anytype) type {
    const param_types = @typeInfo(@TypeOf(S.run)).@"fn".param_types;

    return struct {
        pub const Name = @typeName(S);
        pub const Phase = phase;

        const ArgsTupleType = std.meta.ArgsTuple(@TypeOf(S.run));
        var args_tuple: ArgsTupleType = undefined;

        pub fn init(w: *zflecs.world_t) void {
            inline for (param_types, 0..) |param_type, i| {
                if (@typeInfo(param_type.?) != .@"struct" or !@hasDecl(param_type.?, "init")) {
                    continue;
                }

                args_tuple[i] = param_type.?.init(w);
            }
        }

        pub fn deinit() void {
            const fields = @typeInfo(ArgsTupleType).@"struct";
            inline for (fields.field_names, fields.types) |arg_name, arg_type| {
                if (@typeInfo(arg_type) == .@"struct" and @hasDecl(arg_type, "deinit")) {
                    @field(args_tuple, arg_name).deinit();
                }
            }
        }

        pub fn run(_: *zflecs.iter_t) void {
            @call(.auto, S.run, args_tuple);
        }
    };
}
