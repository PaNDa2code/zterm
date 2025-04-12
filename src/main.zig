const std = @import("std");
const builtin = @import("builtin");

const ChildProcess = @import("ChildProcess.zig");
const CircularBuffer = @import("CircularBuffer.zig");
const Pty = @import("pty.zig").Pty;
const Window = @import("window.zig").Window;
const Font = @import("font.zig");

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    var window = Window.new(allocator, "zig term", 600, 800);
    try window.init();
    window.messageLoop();
}

test "test all" {
    std.testing.refAllDecls(CircularBuffer);
    // std.testing.refAllDecls(ChildProcess);
    std.testing.refAllDecls(Pty);
    std.testing.refAllDecls(Window);
    std.testing.refAllDecls(Font);
}

pub const UNICODE = true;
