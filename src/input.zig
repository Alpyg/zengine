const std = @import("std");

const zflecs = @import("zflecs");
const zsdl = @import("zsdl");
pub const Key = zsdl.Scancode;
pub const Mouse = enum(u8) { left = 1, middle = 2, right = 3, x1 = 4, x2 = 5 };

const z = @import("root.zig");

const InputModule = @This();

pub fn init(_: InputModule, ecs: *z.Ecs) void {
    _ = ecs.registerEcs(InputModule);
}

pub const Input = struct {
    pub const RESOURCE = {};

    key_states: std.AutoHashMap(Key, InputState) = undefined,
    mouse_states: std.AutoHashMap(Mouse, InputState) = undefined,

    cursor_disabled: bool = false,
    cursor_position: [2]f32 = undefined,
    mouse_delta: [2]f32 = undefined,

    gfx: *const z.Gfx = undefined,

    pub fn init(ecs: *z.Ecs) Input {
        _ = ecs.registerEvent(z.Event(KeyEvent))
            .registerEvent(z.Event(MouseButtonEvent))
            .registerEvent(z.Event(MouseMotionEvent));

        return Input{
            .key_states = std.AutoHashMap(Key, InputState).init(ecs.allocator),
            .mouse_states = std.AutoHashMap(Mouse, InputState).init(ecs.allocator),
            .cursor_position = .{ 0, 0 },
            .mouse_delta = .{ 0, 0 },
            .gfx = zflecs.singleton_get(ecs.world, z.Gfx).?,
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
            zsdl.hideCursor() catch {};
        } else {
            zsdl.showCursor() catch {};
        }
        self.cursor_disabled = !self.cursor_disabled;
    }
};

pub const InputState = packed struct {
    pressed: bool = false,
    just_pressed: bool = false,
    just_released: bool = false,
};

pub const KeyEvent = struct {
    key: zsdl.Scancode,
    kind: Kind,

    pub const Kind = enum { pressed, released };
};

pub const MouseButtonEvent = struct {
    button: Mouse,
    kind: Kind,

    pub const Kind = enum { pressed, released };
};

pub const MouseMotionEvent = struct {
    delta: [2]f32,
    position: [2]f32,
};

pub const LoadInput = z.System(&z.Phase.First, struct {
    pub fn run(
        ecs: *z.Ecs,
        res_input: z.Resource(Input),
        key_writer: z.Event(KeyEvent).Writer,
        button_writer: z.Event(MouseButtonEvent).Writer,
        motion_writer: z.Event(MouseMotionEvent).Writer,
    ) void {
        var input = res_input.getMut();

        var event: zsdl.Event = undefined;
        while (zsdl.pollEvent(&event)) {
            switch (event.type) {
                .quit => ecs.quit(),
                else => {},
            }
        }

        const kb = zsdl.getKeyboardState();
        inline for (@typeInfo(Key).@"enum".field_names) |field_name| {
            const scancode = @field(Key, field_name);
            const idx = @backingInt(scancode);
            const is_down = if (idx < kb.len) kb[idx] else false;

            const gop = input.key_states.getOrPut(scancode) catch return;
            const was = if (gop.found_existing) gop.value_ptr.pressed else false;

            const just_pressed = is_down and !was;
            const just_released = !is_down and was;

            gop.value_ptr.* = .{
                .pressed = is_down,
                .just_pressed = just_pressed,
                .just_released = just_released,
            };

            if (just_pressed) {
                key_writer.send(.{ .key = scancode, .kind = .pressed }) catch {};
            }
            if (just_released) {
                key_writer.send(.{ .key = scancode, .kind = .released }) catch {};
            }
        }

        var mx: f32 = 0;
        var my: f32 = 0;
        const button_mask: u32 = zsdl.getMouseState(&mx, &my);
        inline for (@typeInfo(Mouse).@"enum".field_names) |field_name| {
            const button: Mouse = @field(Mouse, field_name);
            const bit = @as(u32, 1) << (@backingInt(button) - 1);
            const is_down = (button_mask & bit) != 0;

            const gop = input.mouse_states.getOrPut(button) catch return;
            const was = if (gop.found_existing) gop.value_ptr.pressed else false;

            const just_pressed = is_down and !was;
            const just_released = !is_down and was;

            gop.value_ptr.* = .{
                .pressed = is_down,
                .just_pressed = just_pressed,
                .just_released = just_released,
            };

            if (just_pressed) {
                button_writer.send(.{ .button = button, .kind = .pressed }) catch {};
            }
            if (just_released) {
                button_writer.send(.{ .button = button, .kind = .released }) catch {};
            }
        }

        input.mouse_delta[0] = mx - input.cursor_position[0];
        input.mouse_delta[1] = my - input.cursor_position[1];
        input.cursor_position[0] = mx;
        input.cursor_position[1] = my;

        if (input.mouse_delta[0] != 0 or input.mouse_delta[1] != 0) {
            motion_writer.send(.{
                .delta = input.mouse_delta,
                .position = input.cursor_position,
            }) catch {};
        }
    }
});

pub const InputEventClearSystem = z.System(&z.Phase.Last, struct {
    pub fn run(
        key: z.Event(KeyEvent).Writer,
        button: z.Event(MouseButtonEvent).Writer,
        motion: z.Event(MouseMotionEvent).Writer,
    ) void {
        key.clear();
        button.clear();
        motion.clear();
    }
});
