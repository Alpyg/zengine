const ecs = @import("z").zflecs;
const input = @import("z").input;

pub const InputSystem = struct {
    pub const name = "input system";
    pub const phase = &ecs.OnLoad;

    pub fn run(_: *ecs.iter_t) void {
        input.update();
    }
};
