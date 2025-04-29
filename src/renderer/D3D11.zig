const std = @import("std");
const builtin = @import("builtin");

const freetype = @import("freetype");

const D3D11Renderer = @This();

const pixel_shader_source = @embedFile("shaders/D3D11/pixel.hlsl");
const vertex_shader_source = @embedFile("shaders/D3D11/vertex.hlsl");

const pixel_shader_cso = @embedFile("shaders/D3D11/pixel.cso");
const vertex_shader_cso = @embedFile("shaders/D3D11/vertex.cso");

pub const ColorRGBA = struct { r: f32, g: f32, b: f32, a: f32 };

pub const Red = ColorRGBA{ .r = 1, .g = 0, .b = 0, .a = 1 };
pub const Green = ColorRGBA{ .r = 0, .g = 1, .b = 0, .a = 1 };
pub const Blue = ColorRGBA{ .r = 0, .g = 0, .b = 1, .a = 1 };
pub const White = ColorRGBA{ .r = 1, .g = 1, .b = 1, .a = 1 };
pub const Black = ColorRGBA{ .r = 0, .g = 0, .b = 0, .a = 1 };
pub const Gray = ColorRGBA{ .r = 0.3, .g = 0.3, .b = 0.3, .a = 1 };

const Vertex2D = struct { x: f32, y: f32 };

const Allocator = std.mem.Allocator;

const win32 = @import("win32");
const foundation = win32.foundation;
const d3d11 = win32.graphics.direct3d11;
const dxgi = win32.graphics.dxgi;
const hlsl = win32.graphics.hlsl;

const HWND = foundation.HWND;
const ID3D11Device = d3d11.ID3D11Device;
const ID3D11DeviceContext = d3d11.ID3D11DeviceContext;
const ID3D11RenderTargetView = d3d11.ID3D11RenderTargetView;
const ID3D11VertexShader = d3d11.ID3D11VertexShader;
const ID3D11PixelShader = d3d11.ID3D11PixelShader;
const IDXGIInfoQueue = dxgi.IDXGIInfoQueue;
const IDXGISwapChain = dxgi.IDXGISwapChain;

device: *ID3D11Device = undefined,
context: *ID3D11DeviceContext = undefined,
swap_chain: *IDXGISwapChain = undefined,
render_target_view: *ID3D11RenderTargetView = undefined,
vertex_shader: *ID3D11VertexShader = undefined,
pixel_shader: *ID3D11PixelShader = undefined,

// TODO: Replace manual HRESULT checks with proper Zig error unions and error sets when supported.
pub fn init(hwnd: HWND) !D3D11Renderer {
    var self: D3D11Renderer = .{};

    const sd = dxgi.DXGI_SWAP_CHAIN_DESC{
        .BufferDesc = .{
            .Format = .B8G8R8A8_UNORM,
            .Scaling = .UNSPECIFIED,
            .ScanlineOrdering = .UNSPECIFIED,
            .RefreshRate = .{
                .Denominator = 0,
                .Numerator = 0,
            },
            .Height = 0,
            .Width = 0,
        },
        .BufferUsage = dxgi.DXGI_USAGE_RENDER_TARGET_OUTPUT,
        .BufferCount = 1,
        .OutputWindow = hwnd,
        .Flags = 0,
        .SwapEffect = .DISCARD,
        .SampleDesc = .{ .Count = 1, .Quality = 0 },
        .Windowed = 1,
    };

    var hresult: i32 = 0;

    hresult = d3d11.D3D11CreateDeviceAndSwapChain(
        null,
        .HARDWARE,
        null,
        .{},
        null,
        0,
        d3d11.D3D11_SDK_VERSION,
        &sd,
        &self.swap_chain,
        &self.device,
        null,
        &self.context,
    );

    if (win32.zig.FAILED(hresult))
        win32.zig.panicHresult("D3D11CreateDeviceAndSwapChain", hresult);

    var backBuffer: *d3d11.ID3D11Resource = undefined;

    hresult = self.swap_chain.GetBuffer(0, d3d11.IID_ID3D11Resource, @ptrCast(&backBuffer));

    if (win32.zig.FAILED(hresult))
        win32.zig.panicHresult("GetBuffer", hresult);

    defer _ = backBuffer.IUnknown.Release();

    hresult = self.device.CreateRenderTargetView(
        backBuffer,
        null,
        &self.render_target_view,
    );

    if (win32.zig.FAILED(hresult))
        win32.zig.panicHresult("CreateRenderTargetView", hresult);

    hresult = self.device.CreateVertexShader(
        vertex_shader_cso,
        vertex_shader_cso.len,
        null,
        &self.vertex_shader,
    );

    if (win32.zig.FAILED(hresult))
        win32.zig.panicHresult("CreateVertexShader", hresult);

    hresult = self.device.CreatePixelShader(
        pixel_shader_cso,
        pixel_shader_cso.len,
        null,
        &self.pixel_shader,
    );

    if (win32.zig.FAILED(hresult))
        win32.zig.panicHresult("CreatePixelShader", hresult);

    return self;
}

pub fn deinit(self: *D3D11Renderer) void {
    _ = self.swap_chain.IUnknown.Release();
    _ = self.context.IUnknown.Release();
    _ = self.device.IUnknown.Release();
    _ = self.render_target_view.IUnknown.Release();
}

pub fn clearBuffer(self: *D3D11Renderer, color: ColorRGBA) void {
    self.context.ClearRenderTargetView(self.render_target_view, &color.r);
}

pub fn presentBuffer(self: *D3D11Renderer) void {
    _ = self.swap_chain.Present(1, 0);
}

pub fn drawTestTriagnle(self: *D3D11Renderer) void {
    const vertices = [_]Vertex2D{
        .{ .x = 0, .y = 0.5 },
        .{ .x = 0.5, .y = -0.5 },
        .{ .x = -0.5, .y = -0.5 },
    };

    const stride: u32 = @sizeOf(Vertex2D);
    const offset: u32 = 0;

    const buffer_desc: d3d11.D3D11_BUFFER_DESC = .{
        .Usage = .DEFAULT,
        .BindFlags = .{ .VERTEX_BUFFER = 1 },
        .ByteWidth = @sizeOf(Vertex2D) * vertices.len,
        .StructureByteStride = @sizeOf(Vertex2D),
        .MiscFlags = .{},
        .CPUAccessFlags = .{},
    };

    const buffer_init_data: d3d11.D3D11_SUBRESOURCE_DATA = .{
        .pSysMem = &vertices,
        .SysMemPitch = 0,
        .SysMemSlicePitch = 0,
    };

    var vertex_buffer: *d3d11.ID3D11Buffer = undefined;
    var hresult = self.device.CreateBuffer(&buffer_desc, &buffer_init_data, &vertex_buffer);
    defer _ = vertex_buffer.IUnknown.Release();

    if (win32.zig.FAILED(hresult))
        win32.zig.panicHresult("CreateBuffer", hresult);

    var input_layout: *d3d11.ID3D11InputLayout = undefined;
    const input_layout_descs = [_]d3d11.D3D11_INPUT_ELEMENT_DESC{
        .{
            .SemanticName = "Position",
            .SemanticIndex = 0,
            .Format = .R32G32_FLOAT,
            .InputSlot = 0,
            .AlignedByteOffset = 0,
            .InputSlotClass = .VERTEX_DATA,
            .InstanceDataStepRate = 0,
        },
    };

    hresult = self.device.CreateInputLayout(
        &input_layout_descs,
        input_layout_descs.len,
        vertex_shader_cso,
        vertex_shader_cso.len,
        &input_layout,
    );

    if (win32.zig.FAILED(hresult))
        win32.zig.panicHresult("CreateInputLayout", hresult);

    defer _ = input_layout.IUnknown.Release();

    const view_port: d3d11.D3D11_VIEWPORT = .{
        .Height = 400,
        .Width = 400,
        .MaxDepth = 1,
        .MinDepth = 0,
        .TopLeftX = 0,
        .TopLeftY = 0,
    };
    self.context.RSSetViewports(1, @ptrCast(&view_port));

    self.context.IASetInputLayout(input_layout);

    self.context.PSSetShader(self.pixel_shader, null, 0);
    self.context.VSSetShader(self.vertex_shader, null, 0);

    self.context.OMSetRenderTargets(1, @ptrCast(&self.render_target_view), null);

    self.context.IASetVertexBuffers(
        0,
        1,
        @ptrCast(&vertex_buffer),
        @ptrCast(&stride),
        @ptrCast(&offset),
    );

    self.context.IASetPrimitiveTopology(._PRIMITIVE_TOPOLOGY_TRIANGLELIST);

    self.context.Draw(3, 0);
}

test "test triangle rendering" {
    const allocator = std.testing.allocator;

    var window: @import("../window.zig").Window = .{
        .height = 400,
        .width = 400,
        .title = "test drawTexture",
    };

    try window.init(allocator);
    defer window.deinit();

    const renderer = &window.renderer;

    while (!window.exit) {
        window.pumpMessages();
        renderer.clearBuffer(Black);
        renderer.drawTestTriagnle();
        renderer.presentBuffer();
    }
}

test "test glyph rendering" {
    // const allocator = std.testing.allocator;
    //
    // var ft_library = try freetype.Library.init(allocator);
    // defer ft_library.deinit();
    //
    // const face = ft_library.face("C:\\windows\\Fonts\\arial.ttf", 32) catch |e| {
    //     std.log.err("freetype {}", .{e});
    //     return e;
    // };
    // defer face.deinit();
    //
    // const glyph = try face.getGlyph('a');
    // defer glyph.deinit();
}
