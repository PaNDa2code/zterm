pub const Renderer = switch (@import("config").@"render-backend") {
    .OpenGL => @import("opengl/OpenGL.zig"),
    .D3D11 => @import("d3d11/D3D11.zig"),
    .Vulkan => {},
};
