const std = @import("std");

const zglfw = @import("zglfw");

const z = @import("root.zig");

pub const Key = zglfw.Key;
pub const Mouse = zglfw.MouseButton;

var key_states: std.AutoHashMap(Key, InputState) = undefined;
var mouse_states: std.AutoHashMap(Mouse, InputState) = undefined;

var cursor_disabled: bool = false;
var cursor_position: [2]f32 = undefined;
var mouse_delta: [2]f32 = undefined;

pub fn init(allocator: std.mem.Allocator) void {
    key_states = std.AutoHashMap(Key, InputState).init(allocator);
    mouse_states = std.AutoHashMap(Mouse, InputState).init(allocator);
    cursor_position = .{ 0, 0 };
    mouse_delta = .{ 0, 0 };
}

pub fn deinit() void {
    key_states.deinit();
    mouse_states.deinit();
    cursor_position = undefined;
    mouse_delta = undefined;
}

pub fn update() void {
    inline for (@typeInfo(Key).@"enum".fields) |key_field| {
        const key = @as(Key, @enumFromInt(key_field.value));
        const is_down = zglfw.getKey(z.window, key) == .press;

        const gop = key_states.getOrPut(key) catch return;
        const was_down = if (gop.found_existing) gop.value_ptr.pressed else false;

        gop.value_ptr.* = InputState{
            .pressed = is_down,
            .just_pressed = is_down and !was_down,
            .just_released = !is_down and was_down,
        };
    }

    inline for (@typeInfo(Mouse).@"enum".fields) |button_field| {
        const button = @as(Mouse, @enumFromInt(button_field.value));
        const is_down = zglfw.getMouseButton(z.window, button) == .press;

        const gop = mouse_states.getOrPut(button) catch return;
        const was_down = if (gop.found_existing) gop.value_ptr.pressed else false;

        gop.value_ptr.* = InputState{
            .pressed = is_down,
            .just_pressed = is_down and !was_down,
            .just_released = !is_down and was_down,
        };
    }

    var new_mouse = [2]f64{ 0, 0 };
    zglfw.getCursorPos(z.window, &new_mouse[0], &new_mouse[1]);

    mouse_delta[0] = (@as(f32, @floatCast(new_mouse[0])) - cursor_position[0]);
    mouse_delta[1] = (@as(f32, @floatCast(new_mouse[1])) - cursor_position[1]);

    cursor_position[0] = @as(f32, @floatCast(new_mouse[0]));
    cursor_position[1] = @as(f32, @floatCast(new_mouse[1]));
}

pub fn getKey(key: Key) InputState {
    return key_states.get(key).?;
}

pub fn getButton(button: Mouse) InputState {
    return mouse_states.get(button).?;
}

pub fn getCursorPos() [2]f32 {
    return cursor_position;
}

pub fn getMouseDelta() [2]f32 {
    return mouse_delta;
}

pub fn isCursorDisabled() bool {
    return cursor_disabled;
}

pub fn toggleCursor() void {
    if (cursor_disabled) {
        zglfw.setInputMode(z.window, .cursor, .normal) catch {};
    } else {
        zglfw.setInputMode(z.window, .cursor, .disabled) catch {};
    }
    cursor_disabled = !cursor_disabled;
}

pub const InputState = packed struct {
    pressed: bool,
    just_pressed: bool,
    just_released: bool,
};
