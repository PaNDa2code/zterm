const std = @import("std");
const builtin = @import("builtin");
const config = @import("config");

const App = @import("App.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = App.new(allocator);
    try app.start();
    defer app.exit();

    app.loop();
}

pub const UNICODE = true;

test {
    std.testing.refAllDecls(@import("ChildProcess.zig"));
    std.testing.refAllDecls(@import("CircularBuffer.zig"));
    std.testing.refAllDecls(@import("DynamicLibrary.zig"));
    std.testing.refAllDecls(@import("EventLoop.zig"));
    std.testing.refAllDecls(@import("Keyboard.zig"));
    std.testing.refAllDecls(@import("parser.zig"));
    std.testing.refAllDecls(@import("pty.zig"));
    std.testing.refAllDecls(@import("window.zig"));
}
