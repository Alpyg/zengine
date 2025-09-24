const ecs = @import("z").zflecs;
const input = @import("z").input;

const System = @import("z").System;

pub const InputSystem = System(struct {
    pub const name = "input system";
    pub const phase = &ecs.OnLoad;

    pub fn run() void {
        input.update();
    }
});
