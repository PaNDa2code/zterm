const KeyboardEvent = @import("Keyboard.zig").KeyboardEvent;
const WindowResizeEvent = @import("window.zig").WindowResizeEvent;

pub const EventType = enum {
    WindowResize,
    KeyBoardInput,
    MouseInput,
    PtyIO,
};

pub const Event = union(EventType) {
    KeyBoardInput: KeyboardEvent,
    MouseInput: void,
    WindowResize: WindowResizeEvent,
    PtyIO: void,
};
