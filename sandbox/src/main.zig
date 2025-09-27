const std = @import("std");

const z = @import("z");
const Gfx = z.Gfx;
const Gui = z.Gui;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var app = z.Ecs.init(allocator);
    defer app.deinit();

    _ = app.registerModule(Gfx{})
        .registerModule(Gui{});

    app.run();
}
