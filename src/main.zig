const std = @import("std");
const builtin = @import("builtin");

const ChildProcess = @import("ChildProcess.zig");
const CircularBuffer = @import("CircularBuffer.zig");
const Pty = @import("pty.zig").Pty;
const Window = @import("window.zig").Window;
const freetype = @import("freetype");

pub fn main() !void {
    std.debug.print("\x1Bc", .{}); // clear the terminal for debuging
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const ft_library = try freetype.Library.init(allocator);
    defer ft_library.deinit();

    var window = Window{ .height = 600, .width = 800, .title = "HelloWorld" };
    try window.init(allocator);
    std.debug.print("Done", .{});
    window.messageLoop();
}

test "test all" {
    // std.testing.refAllDecls(CircularBuffer);
    // std.testing.refAllDecls(ChildProcess);
    // std.testing.refAllDecls(Pty);
    // std.testing.refAllDecls(Window);
    // std.testing.refAllDecls(freetype);
    std.testing.refAllDecls(@import("DynamicLibrary.zig"));
    // std.testing.refAllDecls(@import("renderer/opengl/OpenGl.zig"));
}

pub const UNICODE = true;
