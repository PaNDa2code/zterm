const std = @import("std");
const builtin = @import("builtin");
const config = @import("config");

const App = @import("App.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = App.new(allocator);
    try app.start();

    app.loop();
}

pub const UNICODE = true;
