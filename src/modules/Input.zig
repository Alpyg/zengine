const std = @import("std");

const zflecs = @import("zflecs");
const zglfw = @import("zglfw");
pub const Key = zglfw.Key;
pub const Mouse = zglfw.MouseButton;

const z = @import("../root.zig");
const Ecs = z.Ecs;
const Gfx = z.Gfx;
const Pipeline = z.Pipeline;
const Resource = z.Resource;
const System = z.System;

const InputModule = @This();

pub fn init(_: InputModule, ecs: *Ecs) void {
    _ = ecs.registerResource(Input.init(ecs))
        .registerEcs(InputModule);
}

pub const Input = struct {
    key_states: std.AutoHashMap(Key, InputState) = undefined,
    mouse_states: std.AutoHashMap(Mouse, InputState) = undefined,

    cursor_disabled: bool = false,
    cursor_position: [2]f32 = undefined,
    mouse_delta: [2]f32 = undefined,

    gfx: *const Gfx = undefined,

    pub fn init(ecs: *Ecs) Input {
        return Input{
            .key_states = std.AutoHashMap(Key, InputState).init(z.allocator),
            .mouse_states = std.AutoHashMap(Mouse, InputState).init(z.allocator),
            .cursor_position = .{ 0, 0 },
            .mouse_delta = .{ 0, 0 },
            .gfx = zflecs.singleton_get(ecs.world, Gfx).?,
        };
    }

    pub fn deinit(self: *Input) void {
        self.key_states.deinit();
        self.mouse_states.deinit();
        self.cursor_position = undefined;
        self.mouse_delta = undefined;
    }

    pub fn getKey(self: *const Input, key: Key) InputState {
        return self.key_states.get(key).?;
    }

    pub fn getButton(self: *const Input, button: Mouse) InputState {
        return self.mouse_states.get(button).?;
    }

    pub fn getCursorPos(self: *const Input) [2]f32 {
        return self.cursor_position;
    }

    pub fn getMouseDelta(self: *const Input) [2]f32 {
        return self.mouse_delta;
    }

    pub fn isCursorDisabled(self: *const Input) bool {
        return self.cursor_disabled;
    }

    pub fn toggleCursor(self: *Input) void {
        if (self.cursor_disabled) {
            zglfw.setInputMode(self.gfx.window, .cursor, .normal) catch {};
        } else {
            zglfw.setInputMode(self.gfx.window, .cursor, .disabled) catch {};
        }
        self.cursor_disabled = !self.cursor_disabled;
    }
};

pub const InputState = packed struct {
    pressed: bool = false,
    just_pressed: bool = false,
    just_released: bool = false,
};

pub const LoadInput = System(struct {
    pub const phase = &Pipeline.First;

    pub fn run(res_gfx: Resource(Gfx), res_input: Resource(Input)) void {
        zglfw.pollEvents();

        const gfx = res_gfx.get();
        var input = res_input.getMut();

        inline for (@typeInfo(Key).@"enum".fields) |key_field| {
            const key = @as(Key, @enumFromInt(key_field.value));
            const is_down = zglfw.getKey(gfx.window, key) == .press;

            const gop = input.key_states.getOrPut(key) catch return;
            const was_down = if (gop.found_existing) gop.value_ptr.pressed else false;

            gop.value_ptr.* = InputState{
                .pressed = is_down,
                .just_pressed = is_down and !was_down,
                .just_released = !is_down and was_down,
            };
        }

        inline for (@typeInfo(Mouse).@"enum".fields) |button_field| {
            const button = @as(Mouse, @enumFromInt(button_field.value));
            const is_down = zglfw.getMouseButton(gfx.window, button) == .press;

            const gop = input.mouse_states.getOrPut(button) catch return;
            const was_down = if (gop.found_existing) gop.value_ptr.pressed else false;

            gop.value_ptr.* = InputState{
                .pressed = is_down,
                .just_pressed = is_down and !was_down,
                .just_released = !is_down and was_down,
            };
        }

        var new_mouse = [2]f64{ 0, 0 };
        zglfw.getCursorPos(gfx.window, &new_mouse[0], &new_mouse[1]);

        input.mouse_delta[0] = (@as(f32, @floatCast(new_mouse[0])) - input.cursor_position[0]);
        input.mouse_delta[1] = (@as(f32, @floatCast(new_mouse[1])) - input.cursor_position[1]);

        input.cursor_position[0] = @as(f32, @floatCast(new_mouse[0]));
        input.cursor_position[1] = @as(f32, @floatCast(new_mouse[1]));
    }
});
