//! Typed handle to a singleton resource, injected into systems as an argument.

const zflecs = @import("zflecs");

/// Wrapper around a singleton component `R`. A system can request
/// `Resource(R)` and will receive the current singleton value.
pub fn Resource(comptime R: type) type {
    return struct {
        const Self = @This();
        pub const RESOURCE = {};

        resource: *R,

        pub fn init(world: *zflecs.world_t) Self {
            return Self{ .resource = zflecs.singleton_get_mut(world, R).? };
        }

        /// Read-only access.
        pub fn get(self: *const Self) *const R {
            return self.resource;
        }

        /// Mutable access.
        pub fn getMut(self: *const Self) *R {
            return self.resource;
        }
    };
}
