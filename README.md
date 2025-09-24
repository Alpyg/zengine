## Game engine based on zig-gamedev libraries

### ECS

Implements a simple Bevy-like query system

Will recursively search and register components and systems inside the module passed to the `ecs.create`

```zig
const std = @import("std");

const z = @import("z");
const zflecs = z.zflecs;
const System = z.System;
const Query = z.Query;

const Components = struct {
    pub const Counter = struct { value: usize = 0 };
    pub const Tag = struct { value: usize = 0 };
};

const Systems = struct {
    pub const TestSystem = System(struct {
        pub const name = "test system";
        pub const phase = &zflecs.OnLoad;

        pub fn run(
            q_counter: Query(.{Components.Counter}, .{}),
            q_tag: Query(.{Components.Tag}, .{}),
        ) void {
            var counter_it = q_counter.iter();
            while (counter_it.next()) |counter| {
                counter[0].value += 1;
            }

            var tag_it = q_tag.iter();
            while (tag_it.next()) |tag| {
                tag[0].value += 2;
            }
        }
    });
};

pub fn main() !void {
    const ECS = z.ecs.create(Components, Systems);

    try ECS.init();
    defer ECS.deinit();

    const entity = zflecs.new_entity(z.world, "Test Entity");
    _ = zflecs.set(z.world, entity, Components.Counter, .{});

    const entity_tagged = zflecs.new_entity(z.world, "Test Entity Tagged");
    _ = zflecs.set(z.world, entity_tagged, Components.Counter, .{});
    _ = zflecs.set(z.world, entity_tagged, Components.Tag, .{});

    const iterations = 5;
    for (0..iterations) |_| {
        ECS.progress();
    }

    var counter_q = try Query(.{Components.Counter}, .{}).init(z.world);
    var counter_it = counter_q.iter();
    while (counter_it.next()) |counter| {
        std.log.info("Counter {}", .{counter[0].value});
    }

    var tag_q = try Query(.{Components.Tag}, .{}).init(z.world);
    var tag_it = tag_q.iter();
    while (tag_it.next()) |tag| {
        std.log.info("Tag {}", .{tag[0].value});
    }
}
```
