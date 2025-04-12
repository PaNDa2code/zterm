const KeyboardEvent = @import("Keyboard.zig").KeyboardEvent;
const WindowResizeEvent = @import("window.zig").WindowResizeEvent;

pub const EventType = enum {
    Window,
    KeyboardInput,
    MouseInput,
    PtyIO,
};

pub const Event = union(EventType) {
    KeyBoardInput: KeyboardEvent,
    MouseInput: void,
    Window: WindowResizeEvent,
    PtyIO: void,
};
