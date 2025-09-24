const std = @import("std");
const z = @import("z");

const game = z.create(
    @import("ecs/components.zig"),
    @import("ecs/systems.zig"),
);

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    try game.init(allocator);
    defer game.deinit();

    // const entity = z.zflecs.new_entity(z.world, "Test Entity");
    // _ = z.zflecs.set(z.world, entity, Components.Counter, .{});

    while (!z.window.shouldClose()) {
        try game.run();
    }
}
