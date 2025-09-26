const std = @import("std");

const zflecs = @import("zflecs");

pub fn System(comptime S: anytype) type {
    if (!@hasDecl(S, "phase")) @compileError("Expected system to have a phase declaration");

    const param_types = @typeInfo(@TypeOf(S.run)).@"fn".params;

    return struct {
        pub const name = S.name;
        pub const phase = S.phase;

        const ArgsTupleType = std.meta.ArgsTuple(@TypeOf(S.run));
        var args_tuple: ArgsTupleType = undefined;

        pub fn init(w: *zflecs.world_t) void {
            inline for (param_types, 0..) |param, i| {
                if (@typeInfo(param.type.?) != .@"struct" or !@hasDecl(param.type.?, "init")) {
                    continue;
                }

                args_tuple[i] = param.type.?.init(w);
            }
        }

        pub fn deinit() void {
            inline for (@typeInfo(ArgsTupleType).@"struct".fields) |arg| {
                if (@typeInfo(arg.type) == .@"struct" and @hasDecl(arg.type, "deinit")) {
                    @field(args_tuple, arg.name).deinit();
                }
            }
        }

        pub fn run(_: *zflecs.iter_t) void {
            @call(.auto, S.run, args_tuple);
        }
    };
}
