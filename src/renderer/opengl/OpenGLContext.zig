// device_context: DeviceContext,
// opengl_rendering_context: OpenGLRenderingContext,
// window_handle: WindowHandle,

pub const OpenGLContext = switch (@import("builtin").os.tag) {
    .windows => @import("WGLContext.zig"),
    .linux => @import("GLXContext.zig"),
    else => void,
};
