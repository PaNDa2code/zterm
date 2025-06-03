const KeyboardEvent = @import("Keyboard.zig").KeyboardEvent;
const WindowResizeEvent = @import("window.zig").WindowResizeEvent;

pub const EventType = enum {
    Window,
    KeyboardInput,
    MouseInput,
    PtyIO,
};

pub const Event = union(EventType) {
    Window: WindowResizeEvent,
    KeyboardInput: KeyboardEvent,
    MouseInput: void,
    PtyIO: void,
};
