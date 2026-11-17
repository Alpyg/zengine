//! Wraps a plain `run` function into a flecs system with pre-bound arguments.
//!
//! At registration time `init` walks the function's parameters and fills a
//! static argument tuple: `*Ecs` and `*world_t` are passed through, while any
//! other parameter type with an `init(world)` method (resources, queries,
//! event writers) is initialized once. The generated `run` simply forwards the
//! stored tuple to the user function.

const std = @import("std");

const zflecs = @import("zflecs");

pub fn System(phase: *zflecs.entity_t, comptime S: anytype) type {
    const param_types = @typeInfo(@TypeOf(S.run)).@"fn".param_types;

    return struct {
        pub const Name = @typeName(S);
        pub const Phase = phase;

        const ArgsTupleType = std.meta.ArgsTuple(@TypeOf(S.run));
        var args_tuple: ArgsTupleType = undefined;

        /// Initializes the argument tuple. Called once by `Ecs.registerEcs`.
        pub fn init(ecs: anytype) void {
            inline for (param_types, 0..) |param_type, i| {
                const pt = param_type orelse continue;

                // Systems may ask for the owning `*z.Ecs` or the raw flecs world.
                // Everything else is initialized through its own `init(world)`
                // (e.g. `Resource(T)`, `Query(...)`, `Event(T).Writer`).
                if (pt == @TypeOf(ecs)) {
                    args_tuple[i] = ecs;
                } else if (pt == @TypeOf(ecs.world)) {
                    args_tuple[i] = ecs.world;
                } else if (@typeInfo(pt) == .@"struct" and @hasDecl(pt, "init")) {
                    args_tuple[i] = pt.init(ecs.world);
                }
            }
        }

        /// Deinitializes any argument type that exposes `deinit`.
        pub fn deinit() void {
            const fields = @typeInfo(ArgsTupleType).@"struct";
            inline for (fields.field_names, fields.field_types) |arg_name, arg_type| {
                if (@typeInfo(arg_type) == .@"struct" and @hasDecl(arg_type, "deinit")) {
                    @field(args_tuple, arg_name).deinit();
                }
            }
        }

        /// Flecs system entry point.
        pub fn run(_: *zflecs.iter_t) void {
            @call(.auto, S.run, args_tuple);
        }
    };
}
