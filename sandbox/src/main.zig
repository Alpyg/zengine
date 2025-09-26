const std = @import("std");

const z = @import("z");
const Gfx = z.Gfx;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    z.allocator = allocator;

    var app = z.Ecs.init();
    defer app.deinit();

    _ = app.registerModule(Gfx{});

    app.run();
}
