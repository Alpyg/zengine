const std = @import("std");
const z = @import("z");

test "queries expose the correct mutability and values" {
    const E = struct {
        pub const Pos = struct {
            pub const COMPONENT = {};
            x: i32 = 0,
        };
        pub const Vel = struct {
            pub const COMPONENT = {};
            x: i32 = 0,
        };
        pub const Tag = struct {
            pub const COMPONENT = {};
        };
    };

    var ecs = z.Ecs.init(std.testing.allocator);
    defer ecs.deinit();

    _ = ecs.register(E);

    const a = ecs.new("a");
    _ = ecs.add(a, .{ E.Pos{ .x = 1 }, E.Vel{ .x = 10 }, E.Tag{} });
    const b = ecs.new("b");
    _ = ecs.add(b, .{ E.Pos{ .x = 2 }, E.Vel{ .x = 20 } });
    const c = ecs.new("c");
    _ = ecs.add(c, E.Vel{ .x = 30 });

    var q = z.Query(.{ *E.Pos, E.Vel }, .{}).init(ecs.world);
    defer q.deinit();

    var it = q.iter();
    var seen: usize = 0;
    while (it.next()) |row| {
        const pos: *E.Pos = row[0];
        const vel: *const E.Vel = row[1];
        pos.x += vel.x;
        seen += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), seen);

    var tagged = z.Query(.{*E.Pos}, .{z.With(E.Tag)}).init(ecs.world);
    defer tagged.deinit();
    var tagged_it = tagged.iter();
    var tagged_count: usize = 0;
    while (tagged_it.next()) |pos| {
        const p: *E.Pos = pos;
        try std.testing.expectEqual(@as(i32, 11), p.x);
        tagged_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), tagged_count);

    var untagged = z.Query(.{*E.Pos}, .{z.Without(E.Tag)}).init(ecs.world);
    defer untagged.deinit();
    var untagged_it = untagged.iter();
    var untagged_count: usize = 0;
    while (untagged_it.next()) |pos| {
        const p: *E.Pos = pos;
        try std.testing.expectEqual(@as(i32, 22), p.x);
        untagged_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), untagged_count);

    var optional = z.Query(.{ ?E.Pos, E.Vel }, .{}).init(ecs.world);
    defer optional.deinit();
    var optional_it = optional.iter();
    var rows: usize = 0;
    while (optional_it.next()) |row| {
        const pos: ?*const E.Pos = row[0];
        _ = row[1];
        if (pos) |p| {
            try std.testing.expect(p.x > 0);
        }
        rows += 1;
    }
    try std.testing.expect(rows >= 2);
}
