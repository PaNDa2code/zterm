const std = @import("std");
const builtin = @import("builtin");

const asni = @import("asni.zig");
const keyboard = @import("keyboard.zig");
const pty = @import("pty.zig");

const CircularBuffer = @import("CircularBuffer.zig");
const Pty = pty.Pty;
const ChildProcess = @import("ChildProcess.zig");

pub fn main() !void {
    var pty_seisson: Pty = undefined;
    try pty_seisson.open(.{});
    defer pty_seisson.close();

    // var circular_buffer = try CircularBuffer.new(64 * 1024);
    // defer circular_buffer.deinit();
}

test "test all" {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(pty);
    std.testing.refAllDecls(CircularBuffer);
    std.testing.refAllDecls(ChildProcess);
    std.testing.refAllDecls(asni);
}

pub const UNICODE = true;
