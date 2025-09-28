const std = @import("std");

const z = @import("z");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    z.allocator = allocator;

    var app = z.Ecs.init();
    defer app.deinit();

    _ = app.registerModule(z.GfxModule{})
        .registerModule(z.GuiModule{})
        .registerModule(z.InputModule{})
        .registerModule(z.TransformModule{})
        .registerModule(z.DebugModule{});

    app.run();
}
