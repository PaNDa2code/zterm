const std = @import("std");
const builtin = @import("builtin");
const config = @import("config");

const ChildProcess = @import("ChildProcess.zig");
const CircularBuffer = @import("CircularBuffer.zig");
const Pty = @import("pty.zig").Pty;
const Window = @import("window.zig").Window;
const freetype = @import("freetype");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const ft_library = try freetype.Library.init(allocator);
    defer ft_library.deinit();

    var window = Window.new(allocator, "zterm: " ++ @tagName(config.@"render-backend"), 600, 800);
    try window.open();
    defer window.close();

    window.messageLoop();
}

test "test all" {
    std.testing.refAllDecls(CircularBuffer);
    std.testing.refAllDecls(ChildProcess);
    std.testing.refAllDecls(Pty);
    std.testing.refAllDecls(Window);
    std.testing.refAllDecls(freetype);
    std.testing.refAllDecls(@import("DynamicLibrary.zig"));
    std.testing.refAllDecls(@import("renderer/opengl/OpenGL.zig"));
}

pub const UNICODE = true;
