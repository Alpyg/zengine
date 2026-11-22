//! Camera component and the system that derives its matrices from the world
//! transform.

const std = @import("std");

const zm = @import("zmath");

const z = @import("root.zig");

/// Component: perspective camera parameters and derived matrices.
pub const Camera = struct {
    pub const COMPONENT = {};
    const Self = @This();

    /// Vertical field of view in radians.
    v_fov: f32 = 0.25 * std.math.pi,

    /// Near clipping plane distance.
    z_near: f32 = 0.001,

    /// Far clipping plane distance.
    z_far: f32 = 200.0,

    /// Transforms world-space coordinates to view (camera) space.
    /// Typically the inverse of the camera's world transform matrix.
    world_view: zm.Mat = undefined,

    /// Transforms view-space coordinates to clip-space using a perspective projection.
    /// Based on the vertical FOV, aspect ratio and near/far clip planes.
    view_clip: zm.Mat = undefined,

    /// Full transformation from world-space to clip-space:
    /// world_clip = world_view * view_clip
    world_clip: zm.Mat = undefined,

    /// Recomputes all camera matrices based on the given transform and viewport size.
    /// - `transform`: The camera's world transform (position + orientation).
    /// - `aspect_ratio`: Framebuffer aspect ratio.
    pub fn calculate_matrices(self: *Self, transform: *const z.GlobalTransform, aspect_ratio: f32) void {
        self.world_view = zm.inverse(transform.transform);

        self.view_clip = zm.perspectiveFovRh(
            self.v_fov,
            aspect_ratio,
            self.z_near,
            self.z_far,
        );

        self.world_clip = zm.mul(self.world_view, self.view_clip);
    }
};

/// System: updates every camera's matrices from its world transform and the
/// current scene viewport aspect ratio.
pub const UpdateCameraMatricesSystem = z.System(z.Phase.pre_render, struct {
    pub fn run(
        renderer: z.Resource(z.Renderer),
        q_camera: z.Query(.{ *z.Camera, z.GlobalTransform }, .{}),
    ) void {
        if (renderer.scene_w == 0 or renderer.scene_h == 0) return;

        const aspect_ratio =
            @as(f32, @floatFromInt(renderer.scene_w)) /
            @as(f32, @floatFromInt(renderer.scene_h));

        var camera_it = q_camera.iter();
        while (camera_it.next()) |camera_tuple| {
            var camera: *z.Camera, const transform: *const z.GlobalTransform = camera_tuple;
            camera.calculate_matrices(transform, aspect_ratio);
        }
    }
});
