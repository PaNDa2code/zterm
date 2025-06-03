const std = @import("std");
const builtin = @import("builtin");
const win32 = @import("win32");

const Keyboard = @This();

const Allocator = std.mem.Allocator;

pub const keyboard_key_count = 256;
// Can be stored in AVX register (YMMx)
pub const KeyboardState = std.bit_set.IntegerBitSet(keyboard_key_count);

pub const KeyboardEventType = enum {
    Press,
    Release,
};

pub const KeyboardEvent = struct {
    type: KeyboardEventType,
    code: u8,
};

const KeyboardEventQueue = std.ArrayList(KeyboardEvent);

event_queue: KeyboardEventQueue,
state: KeyboardState,
auto_repeat_enabled: bool,

pub fn init(allocator: Allocator) Keyboard {
    return .{
        .event_queue = KeyboardEventQueue.init(allocator),
        .state = KeyboardState.initEmpty(),
        .auto_repeat_enabled = false,
    };
}

pub fn pushEvent(self: *Keyboard, event: KeyboardEvent) !void {
    try self.event_queue.append(event);
    switch (event.type) {
        .Press => self.state.set(event.code),
        .Release => self.state.unset(event.code),
    }
}

pub fn popEvent(self: *Keyboard) ?KeyboardEvent {
    return self.event_queue.pop();
}

pub fn keyIsPressed(self: *Keyboard, key_code: u8) bool {
    return self.state.isSet(key_code);
}

const shortcuts: []const KeyboardState = {};
