const std = @import("std");
const builtin = @import("builtin");

const ChildProcess = @import("ChildProcess.zig");
const CircularBuffer = @import("CircularBuffer.zig");
const Pty = @import("pty.zig").Pty;
const Window = @import("window.zig").Window;

pub fn main() !void {
    var window: Window = .{ .hight = 600, .width = 800 };
    try window.init();
    window.messageLoop();
    // var pty: Pty = undefined;
    // try pty.open(.{});
    // defer pty.close();

    // var child: ChildProcess = .{
    //     .exe_path = if (builtin.os.tag == .windows) "cmd" else "zsh",
    //     .args = &.{},
    // };

    // try child.start(std.heap.page_allocator, &pty);
    // defer child.terminate();
    //
    // var stdin = child.stdin.?;
    // var stdout = child.stdout.?;

    // _ = try stdin.writeAll("echo HelloWorld\r\n");

    // while (true) {
    //     var buffer: [1024]u8 = undefined;
    //     const len = try stdout.read(&buffer);
    //     if (len > 0) {
    //         const formatter = std.fmt.fmtSliceEscapeLower(buffer[0..len]);
    //         std.debug.print("{x}", .{formatter});
    //     }
    // }
}

test "test all" {
    std.testing.refAllDecls(@import("parser.zig"));
}

pub const UNICODE = true;
