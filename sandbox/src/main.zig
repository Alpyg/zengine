const std = @import("std");

const z = @import("z");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    z.allocator = allocator;

    var app = z.Ecs.init();
    defer app.deinit();

    _ = app.registerModule(z.Gfx{})
        .registerModule(z.Gui{})
        .registerModule(z.Input{})
        .registerSystems(@import("ecs/systems/debug.zig"));

    app.run();
}
