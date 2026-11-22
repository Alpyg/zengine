# Game engine based on zig-gamedev libraries

## ECS

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

## Hot-reloadable modules

`demos/hotmod` is a minimal example. The host loads
`zig-out/lib/libhotmod.so` and swaps it whenever the file changes.

```sh
zig build hotmod-run       # terminal 1
zig build hotmod-module    # terminal 2, after each edit
# or:
watchexec -c -r -e zig -- zig build hotmod-module
```

Rules for a hot-reloadable module:

- Persistent state must live in the ECS world (entities, components,
  resources), never in module globals. The loader disables and deletes the
  module's systems and removes its resources before unloading the library.
- The module must be built with the same Zig version, target, and optimization
  mode as the host. These are checked when the library is loaded.
- Component layouts must not change while hot reloading. A changed `size` or
  `align` aborts the reload and rolls back to the previous version.
- Implement `pub fn preReload(ecs: *z.Ecs) void` to release external resources
  (threads, file handles, GPU handles) before the library is unloaded.

A module exports one entry point:

```zig
const desc = z.hot.descriptor(z.Ecs, MyModule);

export fn zengine_module_v1() *const z.hot.ModuleDesc {
    return desc;
}
```

The host can also scope registrations manually with `Ecs.beginModule` /
`Ecs.endModule` and tear them down with `Ecs.deinitModule`.
