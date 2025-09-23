const std = @import("std");
const z = @import("z");

const game = z.create(
    struct {
        pub const Counter = usize;
    },
    @import("ecs/systems.zig"),
);

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    try game.init(allocator);
    defer game.deinit();

    while (!z.window.shouldClose()) {
        try game.run();
    }
}
