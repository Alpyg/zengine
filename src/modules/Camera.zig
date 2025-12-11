const std = @import("std");

const wgui = @import("zgpu").wgpu;
const zflecs = @import("zflecs");
const zm = @import("zmath");

const z = @import("../root.zig");
const Ecs = z.Ecs;
const Parent = z.Parent;
const Pipeline = z.Pipeline;
const Query = z.Query;
const Resource = z.Resource;
const System = z.System;

const CameraModule = @This();

pub fn init(_: CameraModule, ecs: *Ecs) void {
    _ = ecs.registerEcs(CameraModule);
}

pub const MainCamera = struct {
    pub const COMPONENT = {};
};
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
    pub fn calculate_matrices(self: *Self, transform: *const z.Transform, aspect_ratio: f32) void {
        self.world_view = zm.inverse(
            zm.mul(
                zm.mul(
                    zm.quatToMat(transform.rotation),
                    zm.translationV(transform.translation),
                ),
                zm.scalingV(transform.scale),
            ),
        );

        self.view_clip = zm.perspectiveFovRh(
            self.v_fov,
            aspect_ratio,
            self.z_near,
            self.z_far,
        );

        self.world_clip = zm.mul(self.world_view, self.view_clip);
    }
};

pub const UpdateCameraMatricesSystem = System(struct {
    pub const phase = &Pipeline.PreRender;

    pub fn run(
        gctx: Resource(z.Gfx),
        q_camera: Query(.{ z.Camera, z.GlobalTransform }, .{}),
    ) void {
        const size = gctx.get().getRenderTargetSize();

        var camera_it = q_camera.iter();
        while (camera_it.next()) |camera_tuple| {
            var camera: *z.Camera, const transform: *z.GlobalTransform = camera_tuple;
            camera.calculate_matrices(
                &z.Transform{
                    .translation = transform.translation(),
                    .rotation = transform.rotation(),
                    .scale = transform.scale(),
                },
                @as(f32, @floatFromInt(size[0])) / @as(f32, @floatFromInt(size[1])),
            );
        }
    }
});
