const zflecs = @import("zflecs");

pub fn Resource(comptime R: type) type {
    return struct {
        const Self = @This();

        resource: *R,

        pub fn init(world: *zflecs.world_t) Self {
            return Self{ .resource = zflecs.singleton_get_mut(world, R).? };
        }

        pub fn get(self: *const Self) *const R {
            return self.resource;
        }

        pub fn getMut(self: *const Self) *R {
            return self.resource;
        }
    };
}
