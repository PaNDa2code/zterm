const std = @import("std");
const builtin = @import("builtin");

const asni = @import("asni.zig");
const keyboard = @import("keyboard.zig");

const CircularBuffer = @import("CircularBuffer.zig");
const Pty = @import("pty.zig").Pty;
const ChildProcess = @import("ChildProcess.zig");

pub fn main() !void {
    var pty: Pty = undefined;
    try pty.open(.{});
    defer pty.close();

    var child: ChildProcess = .{
        .exe_path = "zsh",
        .pty = &pty,
        .args = &.{},
    };

    try child.start(std.heap.c_allocator);
    defer child.terminate();

    var stdin = child.stdin.?;
    var stdout = child.stdout.?;

    _ = try stdin.write("echo HelloWorld\n");

    while (true) {
        var buffer: [1024]u8 = undefined;
        const len = try stdout.read(&buffer);
        if (len > 0) {
            std.debug.print("len<{}>: {x:02}<end>\n", .{ len, buffer[0..len] });
        }
    }
}

test "test all" {
    std.testing.refAllDecls(@This());
}

pub const UNICODE = true;
