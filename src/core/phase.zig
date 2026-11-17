//! Frame phases. Each phase is a flecs entity, chained with `DependsOn` so
//! flecs runs systems in pipeline order. `Phase.init` must run before systems
//! are registered.

const zflecs = @import("zflecs");

const Ecs = @import("ecs.zig");

/// Input polling and asset setup.
pub var First: zflecs.entity_t = undefined;

/// Start of the simulation phases.
pub var PreUpdate: zflecs.entity_t = undefined;

/// Start of the fixed-timestep phases.
pub var FixedFirst: zflecs.entity_t = undefined;
pub var FixedPreUpdate: zflecs.entity_t = undefined;
pub var FixedUpdate: zflecs.entity_t = undefined;
pub var FixedPostUpdate: zflecs.entity_t = undefined;
pub var FixedLast: zflecs.entity_t = undefined;

/// Variable-timestep gameplay update.
pub var Update: zflecs.entity_t = undefined;
pub var PostUpdate: zflecs.entity_t = undefined;

/// GPU frame acquisition.
pub var Acquire: zflecs.entity_t = undefined;

/// Start of ImGui submission.
pub var PreRender: zflecs.entity_t = undefined;

/// ImGui windows (dockspace, inspectors).
pub var Ui: zflecs.entity_t = undefined;

/// ImGui windows that need render targets.
pub var Viewport: zflecs.entity_t = undefined;

/// Camera and render-target preparation.
pub var PrepareScene: zflecs.entity_t = undefined;

/// Scene render pass begin.
pub var RenderBegin: zflecs.entity_t = undefined;

/// Draw calls.
pub var Render: zflecs.entity_t = undefined;

/// Scene render pass end.
pub var RenderEnd: zflecs.entity_t = undefined;

/// ImGui rendering and swapchain presentation.
pub var PostRender: zflecs.entity_t = undefined;

/// Event cleanup and command-buffer submission.
pub var Last: zflecs.entity_t = undefined;

pub fn init(ecs: *Ecs) void {
    _ = ecs.registerPhase(&First, null)
        .registerPhase(&PreUpdate, First)
        .registerPhase(&FixedFirst, PreUpdate)
        .registerPhase(&FixedPreUpdate, FixedFirst)
        .registerPhase(&FixedUpdate, FixedPreUpdate)
        .registerPhase(&FixedPostUpdate, FixedUpdate)
        .registerPhase(&FixedLast, FixedPostUpdate)
        .registerPhase(&Update, FixedLast)
        .registerPhase(&PostUpdate, Update)
        .registerPhase(&Acquire, PostUpdate)
        .registerPhase(&PreRender, Acquire)
        .registerPhase(&Ui, PreRender)
        .registerPhase(&Viewport, Ui)
        .registerPhase(&PrepareScene, Viewport)
        .registerPhase(&RenderBegin, PrepareScene)
        .registerPhase(&Render, RenderBegin)
        .registerPhase(&RenderEnd, Render)
        .registerPhase(&PostRender, RenderEnd)
        .registerPhase(&Last, PostRender);
}
