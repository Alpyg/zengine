//! Entity helpers.

const zflecs = @import("zflecs");

const ecs_mod = @import("../ecs.zig");
const Ecs = ecs_mod.Ecs;

/// Creates an entity with a debug name.
pub fn new(self: *Ecs, name: [:0]const u8) zflecs.entity_t {
    return zflecs.new_entity(self.world, name);
}

/// Adds one or more components. Accepts a component value, a component type
/// (for zero-sized tags), or a tuple of either.
pub fn add(self: *Ecs, entity: zflecs.entity_t, components: anytype) *Ecs {
    const components_info = @typeInfo(@TypeOf(components));
    if (components_info != .@"struct" and components_info != .type) {
        @compileError("Expected struct, tuple or type component value");
    }

    if (components_info == .type) {
        addComponent(self, entity, components{});
    } else if (components_info.@"struct".is_tuple) {
        inline for (components_info.@"struct".field_names) |field_name| {
            const component = @field(components, field_name);
            addComponent(self, entity, component);
        }
    } else {
        addComponent(self, entity, components);
    }

    return self;
}

fn addComponent(self: *Ecs, entity: zflecs.entity_t, component: anytype) void {
    if (@sizeOf(@TypeOf(component)) == 0) {
        zflecs.add(self.world, entity, @TypeOf(component));
    } else {
        _ = zflecs.set(self.world, entity, @TypeOf(component), component);
    }
}
