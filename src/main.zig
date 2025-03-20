const std = @import("std");
const builtin = @import("builtin");

const asni = @import("asni.zig");

const Pty = @import("pty.zig");
const CircularBuffer = @import("circular_buffer.zig");

pub fn main() !void {
    var circular_buffer = try CircularBuffer.new(64 * 1024);
    defer circular_buffer.deinit();

    std.debug.print("{x:02}", .{circular_buffer.buffer});
}

test "test all" {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Pty);
    std.testing.refAllDecls(CircularBuffer);
    std.testing.refAllDecls(asni);
}

pub const UNICODE = true;
