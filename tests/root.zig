//! Integration test entry point. Each file uses the engine exactly like a
//! consuming game: `@import("z")` only.

test {
    _ = @import("ecs.zig");
    _ = @import("events.zig");
    _ = @import("meshes.zig");
    _ = @import("phases.zig");
    _ = @import("queries.zig");
    _ = @import("resources.zig");
}
