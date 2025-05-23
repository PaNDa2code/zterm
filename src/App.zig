window: Window,
pty: Pty,
buffer: CircularBuffer,
child: ChildProcess,
// vt_parser: VTParser,
allocator: Allocator,

const App = @This();

pub fn new(allocator: Allocator) App {
    return .{
        .window = Window.new(allocator, "zterm", 600, 800),
        .allocator = allocator,
        // .vt_parser = VTParser.init(cb),
        .child = .{ .exe_path = "bash" },
        .pty = undefined,
        .buffer = undefined,
    };
}

pub fn start(self: *App) !void {
    var arina = std.heap.ArenaAllocator.init(self.allocator);
    defer arina.deinit();

    try self.window.open();
    try self.buffer.init(1024 * 64);
    try self.pty.open(.{});
    try self.child.start(arina.allocator(), &self.pty);
}

pub fn loop(self: *App) void {
    self.window.messageLoop();
}

pub fn exit(self: *App) void {
    self.window.close();
    self.child.terminate();
    self.buffer.deinit();
    self.pty.close();
}

const Window = @import("window.zig").Window;
const Pty = @import("pty.zig").Pty;
const CircularBuffer = @import("CircularBuffer.zig");
const ChildProcess = @import("ChildProcess.zig");
const VTParser = vtparse.VTParser;
const Allocator = std.mem.Allocator;

const std = @import("std");
const config = @import("config");
const vtparse = @import("vtparse");
