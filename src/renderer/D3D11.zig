const std = @import("std");
const builtin = @import("builtin");

const freetype = @import("freetype");

const D3D11Renderer = @This();

const pixel_shader_source = @embedFile("shaders/D3D11/pixel.hlsl");
const vertex_shader_source = @embedFile("shaders/D3D11/vertex.hlsl");

const pixel_shader_cso = @embedFile("shaders/D3D11/pixel.cso");
const vertex_shader_cso = @embedFile("shaders/D3D11/vertex.cso");

pub const ColorRGBA = packed struct { r: f32, g: f32, b: f32, a: f32 };

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

pub fn glyphToTexture(self: *D3D11Renderer, glyph: freetype.Glyph) !*d3d11.ID3D11Texture2D {
    const bitmap = &@as(freetype.c.FT_BitmapGlyph, @ptrCast(glyph.ft_glyph)).*.bitmap;

    const texture_desc: d3d11.D3D11_TEXTURE2D_DESC = .{
        .Width = @intCast(bitmap.width),
        .Height = @intCast(bitmap.rows),
        .MipLevels = 1,
        .ArraySize = 1,
        .Format = .R8_UNORM,
        .SampleDesc = .{ .Count = 1, .Quality = 0 },
        .BindFlags = .{ .SHADER_RESOURCE = 1 },
        .CPUAccessFlags = .{},
        .MiscFlags = .{},
        .Usage = .DEFAULT,
    };

    const init_data: d3d11.D3D11_SUBRESOURCE_DATA = .{
        .pSysMem = bitmap.buffer,
        .SysMemPitch = @intCast(bitmap.pitch),
        .SysMemSlicePitch = 0,
    };

    var texture: ?*d3d11.ID3D11Texture2D = null;

    const hresult = self.device.CreateTexture2D(&texture_desc, &init_data, @ptrCast(&texture));

    if (win32.zig.FAILED(hresult))
        win32.zig.panicHresult("CreateTexture2D", hresult);

    return texture.?;
}

pub fn drawTexture(self: *D3D11Renderer, texture: *const d3d11.ID3D11Texture2D, x: u32, y: u32) !void {
    _ = x; // autofix
    _ = y; // autofix

    const sampler_desc: d3d11.D3D11_SAMPLER_DESC = .{
        .Filter = .MIN_MAG_MIP_LINEAR,
        .AddressU = .WRAP,
        .AddressV = .WRAP,
        .AddressW = .WRAP,
        .MipLODBias = 0,
        .MaxAnisotropy = 1,
        .ComparisonFunc = .NEVER,
        .BorderColor = .{ 0.0, 0.0, 0.0, 0.0 },
        .MinLOD = 0.0,
        .MaxLOD = d3d11.D3D11_FLOAT32_MAX,
    };

    var sampler_state: *d3d11.ID3D11SamplerState = undefined;
    var hresult = self.device.CreateSamplerState(&sampler_desc, &sampler_state);

    if (win32.zig.FAILED(hresult))
        win32.zig.panicHresult("CreateSamplerState", hresult);

    var srv: *d3d11.ID3D11ShaderResourceView = undefined;
    const srv_desc: d3d11.D3D11_SHADER_RESOURCE_VIEW_DESC = .{
        .Format = .R8_UNORM,
        .ViewDimension = ._SRV_DIMENSION_TEXTURE2D,
        .Anonymous = .{
            .Texture2D = .{ .MipLevels = 1, .MostDetailedMip = 0 },
        },
    };

    self.context.IASetPrimitiveTopology(._PRIMITIVE_TOPOLOGY_TRIANGLELIST);

    hresult = self.device.CreateShaderResourceView(@constCast(@ptrCast(texture)), &srv_desc, &srv);
    if (win32.zig.FAILED(hresult))
        win32.zig.panicHresult("CreateShaderResourceView", hresult);

    self.context.VSSetShader(self.vertex_shader, null, 0);

    self.context.PSSetShader(self.pixel_shader, null, 0);

    self.context.PSSetShaderResources(0, 1, @ptrCast(&srv));
    self.context.PSSetSamplers(0, 1, @ptrCast(&sampler_state));
    self.context.Draw(4, 0);
}

test "test glyph rendering" {
    const allocator = std.heap.page_allocator;

    var ft_library = try freetype.Library.init(allocator);
    defer ft_library.deinit();

    const face = ft_library.face("C:\\windows\\Fonts\\arial.ttf", 32) catch |e| {
        std.log.err("freetype {}", .{e});
        return e;
    };
    defer face.deinit();

    const glyph = try face.getGlyph('a');
    defer glyph.deinit();

    var window: @import("../window.zig").Window = .{
        .height = 400,
        .width = 400,
        .title = "test drawTexture",
    };

    try window.init(allocator);
    defer window.deinit();

    const renderer = &window.renderer;

    const texture = try renderer.glyphToTexture(glyph);

    while (!window.exit) {
        window.pumpMessages();
        renderer.clearBuffer(.{ .r = 0.3, .g = 0.3, .b = 0.3, .a = 1 });
        try renderer.drawTexture(texture, 0, 0);
        renderer.presentBuffer();
    }
}
