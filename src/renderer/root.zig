pub const RendererApi = switch (@import("build_options").@"render-backend") {
    .OpenGL => @import("opengl/OpenGL.zig"),
    .D3D11 => @import("d3d11/D3D11.zig"),
    .Vulkan => @import("vulkan/Vulkan.zig"),
};

pub const vtable = RendererApi.vtable;
