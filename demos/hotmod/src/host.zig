//! Minimal host for the hot-reloading demo. Registers only the phase module,
//! then loads `libhotmod.so` and keeps reloading it as it is rebuilt.

const std = @import("std");

const z = @import("z");
const hot = @import("hot");

pub fn main(init: std.process.Init) !void {
    var app = z.Ecs.init(init.gpa);
    defer app.deinit();

    _ = app.register(z.Phase);

    var loader = try hot.Loader.init(init.gpa, init.io, "mods/.cache");
    defer loader.deinit(app);

    loader.install(app);
    try loader.load(app, "zig-out/lib/libhotmod.so");

    std.log.info("hotmod running; edit demos/hotmod/src/mod.zig and run `zig build hotmod-module`", .{});

    while (!app.should_exit) {
        app.progress();
        init.io.sleep(.fromMilliseconds(8), .boot) catch {};
    }
}
