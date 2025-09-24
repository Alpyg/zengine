const std = @import("std");

const z = @import("z");

const Game = z.create(
    @import("ecs/components.zig"),
    @import("ecs/systems.zig"),
);

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var game = try Game.init(allocator);
    defer game.deinit();

    while (!z.window.shouldClose()) {
        try game.run();
    }
}
