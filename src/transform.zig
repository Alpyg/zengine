//! Local and world-space transforms for the ECS.
//!
//! `Transform` stores an entity's position, rotation and scale relative to its
//! parent (or to the world when it has no parent). `GlobalTransform` caches the
//! resulting world-space matrix, which is recomputed once per frame by
//! `PropagateParentTransform` and consumed by rendering and camera systems.
//!
//! Vectors follow zmath's row-vector convention: a point is transformed as
//! `p' = p * S * R * T`, so the composed local matrix is `S * R * T`. The
//! engine uses a right-handed basis where -Z is forward, +X is right and +Y is
//! up.

const zm = @import("zmath");

const z = @import("root.zig");

const TransformModule = @This();

pub fn init(_: TransformModule, ecs: *z.Ecs) void {
    _ = ecs.registerEcs(TransformModule);
}

/// Component: local transform, relative to its parent.
pub const Transform = struct {
    pub const COMPONENT = {};
    const Self = @This();

    /// Position in parent space.
    translation: zm.Vec = .{ 0, 0, 0, 1 },

    /// Orientation as a unit quaternion.
    rotation: zm.Quat = zm.qidentity(),

    /// Non-uniform scale. Negative scale is not supported by `from_mat`.
    scale: zm.Vec = .{ 1, 1, 1, 1 },

    /// Composes the local-to-parent matrix `S * R * T`.
    pub inline fn mat(self: *const Self) zm.Mat {
        const T = zm.translationV(self.translation);
        const R = zm.quatToMat(self.rotation);
        const S = zm.scalingV(self.scale);

        return zm.mul(S, zm.mul(R, T));
    }

    /// Decomposes a TRS matrix into a `Transform`.
    ///
    /// The scale is read as the length of each of the first three basis rows,
    /// and the translation is read from the last row (`m[3]`). The matrix must
    /// not contain shear, and all scale components must be positive.
    pub inline fn from_mat(m: zm.Mat) Self {
        const scale = zm.f32x4(
            zm.length3(m[0])[0],
            zm.length3(m[1])[0],
            zm.length3(m[2])[0],
            0.0,
        );

        const rotation_mat = zm.Mat{
            m[0] / zm.splat(zm.Vec, scale[0]),
            m[1] / zm.splat(zm.Vec, scale[1]),
            m[2] / zm.splat(zm.Vec, scale[2]),
            .{ 0, 0, 0, 1 },
        };

        return Self{
            .translation = m[3],
            .rotation = zm.quatFromMat(rotation_mat),
            .scale = scale,
        };
    }

    /// Normalized -Z axis of the rotated frame: the direction the entity faces
    /// in parent space. Scale is not applied.
    pub inline fn forward(self: *const Self) zm.Vec {
        return -zm.normalize3(zm.rotate(self.rotation, zm.Vec{ 0, 0, 1, 0 }));
    }

    /// Normalized +X axis of the rotated frame: the entity's right direction in
    /// parent space. Scale is not applied.
    pub inline fn right(self: *const Self) zm.Vec {
        return zm.normalize3(zm.rotate(self.rotation, zm.Vec{ 1, 0, 0, 0 }));
    }

    /// Normalized +Y axis of the rotated frame: the entity's up direction in
    /// parent space. Scale is not applied.
    pub inline fn up(self: *const Self) zm.Vec {
        return zm.normalize3(zm.rotate(self.rotation, zm.Vec{ 0, 1, 0, 0 }));
    }
};

/// Component: an entity's cached world-space transform.
///
/// Written by `PropagateParentTransform`; treated as read-only by consumers
/// such as the renderer and camera. The matrix is a full TRS world matrix, so
/// the accessors decompose it on demand.
pub const GlobalTransform = struct {
    /// Marks this struct as a component for `ecs.registerEcs`.
    pub const COMPONENT = {};
    const Self = @This();

    /// World-space TRS matrix. Holds no meaningful value until
    /// `PropagateParentTransform` has run at least once.
    transform: zm.Mat = undefined,

    /// World-space position, taken from the matrix's translation row.
    pub inline fn translation(self: *const Self) zm.Vec {
        return self.transform[3];
    }

    /// World-space orientation, extracted from the matrix with the scale
    /// removed. The result is a quaternion even though it is returned as a
    /// `zm.Vec` (zmath's quaternion type). Assumes a matrix without shear and
    /// with positive scale.
    pub inline fn rotation(self: *const Self) zm.Vec {
        const s = self.scale();
        const rotation_mat = zm.Mat{
            self.transform[0] / zm.splat(zm.Vec, s[0]),
            self.transform[1] / zm.splat(zm.Vec, s[1]),
            self.transform[2] / zm.splat(zm.Vec, s[2]),
            .{ 0, 0, 0, 1 },
        };
        return zm.quatFromMat(rotation_mat);
    }

    /// World-space scale, taken as the length of each of the first three basis
    /// rows.
    pub inline fn scale(self: *const Self) zm.Vec {
        return zm.f32x4(
            zm.length3(self.transform[0])[0],
            zm.length3(self.transform[1])[0],
            zm.length3(self.transform[2])[0],
            0.0,
        );
    }

    /// Normalized world-space -Z axis (forward direction).
    pub inline fn forward(self: *const Self) zm.Vec {
        return -zm.normalize3(self.transform[2]);
    }

    /// Normalized world-space +X axis (right direction).
    pub inline fn right(self: *const Self) zm.Vec {
        return zm.normalize3(self.transform[0]);
    }

    /// Normalized world-space +Y axis (up direction).
    pub inline fn up(self: *const Self) zm.Vec {
        return zm.normalize3(self.transform[1]);
    }
};

/// Component: human-readable name attached to an entity.
pub const Name = struct {
    pub const COMPONENT = {};

    /// Borrowed string. The caller must keep the backing memory alive for as
    /// long as the entity holds this component.
    value: []const u8,
};

/// System: recomputes each entity's `GlobalTransform` from its `Transform`
/// and, when present, its parent's `GlobalTransform`.
///
/// Runs in `Phase.post_update`, after gameplay systems have updated local
/// transforms and before rendering reads world transforms. The parent is
/// reached through zflecs' `ChildOf` cascade, so the value used is the parent's
/// `GlobalTransform` as it exists at that point in the iteration; in deep
/// hierarchies a parent that is visited after its children may only settle on
/// the following frame.
pub const PropagateParentTransform = z.System(z.Phase.post_update, struct {
    pub fn run(q: z.Query(.{ z.Transform, *z.GlobalTransform, ?z.Parent(z.GlobalTransform) }, .{})) void {
        var it = q.iter();
        var i: usize = 0;
        while (it.next()) |transforms| : (i += 1) {
            const transform: *const z.Transform, var global: *z.GlobalTransform, const parent: ?*const z.GlobalTransform = transforms;

            if (parent) |p| {
                global.transform = zm.mul(p.transform, transform.mat());
            } else {
                global.transform = transform.mat();
            }
        }
    }
});
