const zflecs = @import("zflecs");

const Ecs = @import("Ecs.zig");

pub var First: zflecs.entity_t = undefined;

pub var PreUpdate: zflecs.entity_t = undefined;

pub var FixedFirst: zflecs.entity_t = undefined;
pub var FixedPreUpdate: zflecs.entity_t = undefined;
pub var FixedUpdate: zflecs.entity_t = undefined;
pub var FixedPostUpdate: zflecs.entity_t = undefined;
pub var FixedLast: zflecs.entity_t = undefined;

pub var Update: zflecs.entity_t = undefined;
pub var PostUpdate: zflecs.entity_t = undefined;

pub var Acquire: zflecs.entity_t = undefined;
pub var PreRender: zflecs.entity_t = undefined;
pub var Ui: zflecs.entity_t = undefined;
pub var Viewport: zflecs.entity_t = undefined;
pub var PrepareScene: zflecs.entity_t = undefined;
pub var RenderBegin: zflecs.entity_t = undefined;
pub var Render: zflecs.entity_t = undefined;
pub var RenderEnd: zflecs.entity_t = undefined;
pub var PostRender: zflecs.entity_t = undefined;

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
