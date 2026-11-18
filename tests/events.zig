const std = @import("std");
const z = @import("z");

test "events are delivered and cleared each frame" {
    const E = struct {
        pub const Ping = struct { id: u32 };
        pub const Pings = z.Event(Ping);

        pub const Received = struct {
            pub const RESOURCE = {};
            count: u32 = 0,
            sum: u32 = 0,
        };

        pub const Emit = z.System(z.Phase.first, struct {
            pub fn run(
                writer: Pings.Writer,
            ) void {
                var id: u32 = 1;
                while (id <= 3) : (id += 1) {
                    writer.send(.{ .id = id }) catch {};
                }
            }
        });

        pub const Read = z.System(z.Phase.update, struct {
            pub fn run(
                reader: Pings.Reader,
                received: z.Resource(*Received),
            ) void {
                while (reader.read()) |ping| {
                    received.count += 1;
                    received.sum += ping.id;
                }
            }
        });
    };

    var ecs = z.Ecs.init(std.testing.allocator);
    defer ecs.deinit();

    _ = ecs.registerModule(z.PhaseModule{})
        .registerEcs(E);

    ecs.progress();

    const received = z.zflecs.singleton_get(ecs.world, E.Received).?;
    try std.testing.expectEqual(@as(u32, 3), received.count);
    try std.testing.expectEqual(@as(u32, 6), received.sum);

    ecs.progress();
    try std.testing.expectEqual(@as(u32, 6), received.count);
    try std.testing.expectEqual(@as(u32, 12), received.sum);
}
