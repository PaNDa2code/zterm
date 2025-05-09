const std = @import("std");
const builtin = @import("builtin");

const mode = builtin.mode;

const DebugErrorInfo = @This();

pub const Src = struct {
    file: []const u8,
    func: []const u8,
    line: u64,
};

caller_address: usize,
error_code: ?u32,
error_tag: ?anyerror,

pub fn create(error_code: ?u32, error_tag: ?anyerror, depth: usize) DebugErrorInfo {
    const stack_trace: *std.builtin.StackTrace = @errorReturnTrace() orelse undefined;

    std.debug.captureStackTrace(@returnAddress(), stack_trace);
    const caller_address = stack_trace.instruction_addresses[depth];

    return .{
        .caller_address = caller_address,
        .error_code = error_code,
        .error_tag = error_tag,
    };
}

pub fn src(self: *const DebugErrorInfo) ?Src {
    const debug_info = std.debug.getSelfDebugInfo() catch unreachable;

    const allocator = debug_info.allocator;

    const mod = debug_info.getModuleForAddress(self.caller_address) catch undefined;
    // defer mod.deinit(allocator);

    const sym = mod.getSymbolAtAddress(allocator, self.caller_address) catch undefined;
    const loc = sym.source_location orelse return null;

    return .{
        .file = loc.file_name,
        .line = loc.line,
        .func = sym.name,
    };
}

pub fn what(self: *const DebugErrorInfo, writer: std.io.AnyWriter) !void {
    const source = self.src();

    if (self.error_tag) |tag| {
        try writer.print("{s:<15}{!}\n", .{ "Error:", tag });
    }

    if (self.error_code) |code| {
        try writer.print("{s:<15}0x{x:08}\n", .{ "Code:", code });
    }

    if (source) |s| {
        try writer.print("{s:<15}{s}\n", .{ "File:", s.file });
        try writer.print("{s:<15}{d}\n", .{ "Line:", s.line });
        try writer.print("{s:<15}{s}\n", .{ "Function:", s.func });
    }
}

fn func1() !void {
    const allocator = std.testing.allocator;
    var vector = std.ArrayList(u8).init(allocator);
    defer vector.deinit();

    const writer = vector.writer().any();

    func2() catch |err| {
        const base = DebugErrorInfo.create(1, err, 0);
        base.what(writer) catch unreachable;
    };

    std.debug.print("{s}", .{vector.items});
}

fn func2() !void {
    try func3();
}

fn func3() !void {
    return error.Unexpected;
}

test {
    try func1();
}
