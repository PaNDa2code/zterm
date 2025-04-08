const std = @import("std");
const builtin = @import("builtin");

const ChildProcess = @import("ChildProcess.zig");
const CircularBuffer = @import("CircularBuffer.zig");
const Pty = @import("pty.zig").Pty;
const Window = @import("window.zig").Window;

pub fn main() !void {
    var window: Window = .{ .height = 600, .width = 800, .title = "zig_terminal" };
    try window.init(std.heap.page_allocator);
    window.messageLoop();
}

test "test all" {
    std.testing.refAllDecls(@import("parser.zig"));
}

pub const UNICODE = true;
