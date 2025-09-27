const zflecs = @import("zflecs");

const Ecs = @import("../Ecs.zig");

pub var First: zflecs.entity_t = undefined;

pub var PreUpdate: zflecs.entity_t = undefined;
pub var StateTransition: zflecs.entity_t = undefined;

pub var FixedFirst: zflecs.entity_t = undefined;
pub var FixedPreUpdate: zflecs.entity_t = undefined;
pub var FixedUpdate: zflecs.entity_t = undefined;
pub var FixedPostUpdate: zflecs.entity_t = undefined;
pub var FixedLast: zflecs.entity_t = undefined;

pub var Update: zflecs.entity_t = undefined;
pub var PostUpdate: zflecs.entity_t = undefined;

pub var PreRender: zflecs.entity_t = undefined;
pub var Render: zflecs.entity_t = undefined;
pub var PostRender: zflecs.entity_t = undefined;

pub var Last: zflecs.entity_t = undefined;

pub fn init(ecs: *Ecs) void {
    _ = ecs.registerPipeline(&First, null)
        .registerPipeline(&PreUpdate, First)
        .registerPipeline(&StateTransition, PreUpdate)
        .registerPipeline(&FixedFirst, StateTransition)
        .registerPipeline(&FixedPreUpdate, FixedFirst)
        .registerPipeline(&FixedUpdate, FixedPreUpdate)
        .registerPipeline(&FixedPostUpdate, FixedUpdate)
        .registerPipeline(&FixedLast, FixedPostUpdate)
        .registerPipeline(&Update, FixedLast)
        .registerPipeline(&PostUpdate, Update)
        .registerPipeline(&PreRender, PostUpdate)
        .registerPipeline(&Render, PreRender)
        .registerPipeline(&PostRender, Render)
        .registerPipeline(&Last, PostRender);
}
