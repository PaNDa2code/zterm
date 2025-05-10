const std = @import("std");
const builtin = @import("builtin");
const win32 = @import("win32");

const ErrDebugInfo = @import("ErrDebugInfo.zig");

const HresultDebugInfo = @This();

base: ErrDebugInfo,

const mode = builtin.mode;

pub fn create(hresult: i32, depth: usize) HresultDebugInfo {
    return .{
        .base = ErrDebugInfo.create(@bitCast(hresult), null, depth + 1),
    };
}

pub fn src(self: *const HresultDebugInfo) ?ErrDebugInfo.Src {
    if (mode != .Debug)
        @compileError("HresultDebugInfo src method is not callable in release mode");
    return self.base.src();
}

pub fn what(self: *const HresultDebugInfo, writer: std.io.AnyWriter) !void {
    const hresult = self.base.error_code.?;
    const code: win32.foundation.WIN32_ERROR = @enumFromInt(hresult & 0xFFFF);
    try writer.print("{s:<15}{?s}\n", .{
        "Error:",
        code.tagName(),
    });
    try self.base.what(writer);

    try writer.print("{s:<15}{s}\n", .{ "discretion:", code });
}

pub fn dump(self: *const HresultDebugInfo) void {
    const stderr = std.io.getStdErr().writer().any();
    self.what(stderr) catch unreachable;
}

pub fn messageBox(self: *const HresultDebugInfo) void {
    var buffer: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(buffer[0..]);
    const writer = stream.writer().any();
    self.what(writer) catch {};
    writer.writeByte(0) catch {};
    _ = win32.ui.windows_and_messaging.MessageBoxA(null, @ptrCast(&buffer), "hresult error", .{ .ICONHAND = 1 });
}

pub fn checkHresult(hresult: i32) !void {
    if (hresult >= 0)
        return;
    const hr_dbg = HresultDebugInfo.create(hresult, 1);
    if (mode == .Debug) hr_dbg.dump() else hr_dbg.messageBox();
    return error.HResultError;
}

// fn func1() !void {
//     const writer = std.io.getStdErr().writer().any();
//
//     func2() catch {
//         const hrdbg = HresultDebugInfo.create(@bitCast(@as(u32, 0x80070006)), 0);
//         hrdbg.what(writer) catch unreachable;
//     };
// }
//
// fn func2() !void {
//     try func3();
// }
//
// fn func3() !void {
//     return error.Unexpected;
// }
//
// test {
//     try func1();
// }
