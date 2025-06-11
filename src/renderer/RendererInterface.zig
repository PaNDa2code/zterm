//! Interface object for rendering
//! - To profived a stable interface object for rendering
//! - For runtime api compatibility

ctx: *anyopaque = undefined,
vtaple: VTaple = vtable,

const RendererInterface = @This();

pub const VTaple = struct {
    init: *const fn (window: *Window, allocator: std.mem.Allocator) anyerror!*anyopaque,
    deinit: *const fn (*anyopaque, allocator: std.mem.Allocator) void,
    clearBuffer: *const fn (*anyopaque, color: ColorRGBA) void,
    presentBuffer: *const fn (*anyopaque) void,
    renaderText: *const fn (*anyopaque, buffer: []const u8, x: u32, y: u32, color: ColorRGBA) void,
};

pub fn init(self: *RendererInterface, window: *Window, allocator: std.mem.Allocator) !void {
    @branchHint(.unlikely);
    self.ctx = try self.vtaple.init(window, allocator);
}

pub fn deinit(self: *RendererInterface, allocator: std.mem.Allocator) void {
    @branchHint(.unlikely);
    self.vtaple.deinit(self.ctx, allocator);
}

pub fn clearBuffer(self: *RendererInterface, color: ColorRGBA) void {
    @branchHint(.likely);
    self.vtaple.clearBuffer(self.ctx, color);
}

pub fn presentBuffer(self: *RendererInterface) void {
    @branchHint(.likely);
    self.vtaple.presentBuffer(self.ctx);
}

pub fn renaderText(self: *RendererInterface, buffer: []const u8, x: u32, y: u32, color: ColorRGBA) void {
    @branchHint(.likely);
    self.vtaple.renaderText(self.ctx, buffer, x, y, color);
}

const std = @import("std");
const common = @import("common.zig");
const ColorRGBA = common.ColorRGBA;
const vtable = @import("root.zig").vtable;
const Window = @import("../window.zig").Window;
