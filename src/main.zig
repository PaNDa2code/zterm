const std = @import("std");
const builtin = @import("builtin");

const ChildProcess = @import("ChildProcess.zig");
const CircularBuffer = @import("CircularBuffer.zig");
const Pty = @import("pty.zig").Pty;
const Window = @import("window.zig").Window;
const FreeType = @import("FreeType.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var free_type: FreeType = undefined;
    try free_type.init(allocator);
    defer free_type.deinit();

    try free_type.setFont("arial.ttf");
    var glyph_iter = free_type.glyphIter();

    while (glyph_iter.next()) |_| {
        std.log.debug("glyph = {c}", .{@as(u8, @truncate(glyph_iter.char_code))});
    }
}

test "test all" {
    std.testing.refAllDecls(CircularBuffer);
    std.testing.refAllDecls(ChildProcess);
    std.testing.refAllDecls(Pty);
    std.testing.refAllDecls(Window);
    std.testing.refAllDecls(FreeType);
}

pub const UNICODE = true;
