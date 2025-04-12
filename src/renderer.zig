const std = @import("std");
const builtin = @import("builtin");

pub const ColorRGBA = packed struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

const Allocator = std.mem.Allocator;

pub const D3D11Renderer = struct {
    const win32 = @import("win32");
    const foundation = win32.foundation;
    const d3d11 = win32.graphics.direct3d11;
    const dxgi = win32.graphics.dxgi;

    const HWND = foundation.HWND;
    const ID3D11Device = d3d11.ID3D11Device;
    const ID3D11DeviceContext = d3d11.ID3D11DeviceContext;
    const ID3D11RenderTargetView = d3d11.ID3D11RenderTargetView;
    const IDXGIInfoQueue = dxgi.IDXGIInfoQueue;
    const IDXGISwapChain = dxgi.IDXGISwapChain;

    device: *ID3D11Device = undefined,
    context: *ID3D11DeviceContext = undefined,
    swap_chain: *IDXGISwapChain = undefined,
    render_target_view: *ID3D11RenderTargetView = undefined,

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
};
