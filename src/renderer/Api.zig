/// A simple, backend-agnostic graphics API facade.
/// This struct provides a unified interface to multiple rendering backends
/// (e.g., OpenGL, D3D11) selected at compile time via the `render-backend` option.
/// It abstracts backend-specific implementations behind a consistent API surface.

const config = @import("config");
const common = @import("common.zig");

const RendererApi = @This();

const ColorRGBA = common.ColorRGBA;

const RenderBackend = switch (config.@"render-backend") {
    .OpenGL => @import("opengl/OpenGl.zig"),
    .D3D11 => @import("d3d11/D3D11.zig"),
    else => unreachable,
};

base: RenderBackend,

pub inline fn init(hwnd: *anyopaque) !RendererApi {
    return .{ .base = try RenderBackend.init(@ptrCast(hwnd)) };
}

pub inline fn deinit(self: *RendererApi) void {
    self.base.deinit();
}

pub inline fn clearBuffer(self: *RendererApi, color: ColorRGBA) void {
    self.base.clearBuffer(color);
}

pub inline fn presentBuffer(self: *RendererApi) void {
    self.base.presentBuffer();
}
