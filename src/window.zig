const std = @import("std");
const win32 = @import("win32");
const builtin = @import("builtin");

const os = builtin.os.tag;
const Allocator = std.mem.Allocator;

pub const Window = switch (os) {
    .windows => Win32Window,
    .linux => X11Window,
    else => {},
};

pub const WindowResizeEvent = struct {
    new_height: u32,
    new_width: u32,
};

const Win32Window = struct {
    const utf8ToUtf16LeStringLiteral = std.unicode.utf8ToUtf16LeStringLiteral;
    const utf8ToUtf16LeAllocZ = std.unicode.utf8ToUtf16LeAllocZ;

    const win32fnd = win32.foundation;
    const win32wm = win32.ui.windows_and_messaging;
    const win32dwm = win32.graphics.dwm;
    const win32loader = win32.system.library_loader;

    const HANDLE = win32fnd.HANDLE;
    const HWND = win32fnd.HWND;
    const LRESULT = win32fnd.LRESULT;
    const WPARAM = win32fnd.WPARAM;
    const LPARAM = win32fnd.LPARAM;

    const RendererApi = @import("renderer/root.zig").Renderer;

    exit: bool = false,
    hwnd: HWND = undefined,
    title: []const u8,
    height: u32,
    width: u32,
    renderer: RendererApi = undefined,

    pub fn new(title: []const u8, height: u32, width: u32) Window {
        return .{
            .title = title,
            .height = height,
            .width = width,
        };
    }

    pub fn open(self: *Window, allocator: Allocator) !void {
        const class_name = try utf8ToUtf16LeAllocZ(allocator, self.title);
        defer allocator.free(class_name);

        var window_class = std.mem.zeroes(win32wm.WNDCLASSW);
        window_class.lpszClassName = class_name;
        window_class.hInstance = win32loader.GetModuleHandleW(null);
        window_class.lpfnWndProc = &WindowProcSetup;
        window_class.style = .{ .OWNDC = 1, .VREDRAW = 1, .HREDRAW = 1 };

        _ = win32wm.RegisterClassW(&window_class);

        const window_name = try utf8ToUtf16LeAllocZ(allocator, self.title);
        defer allocator.free(window_name);

        const hwnd = win32wm.CreateWindowExW(
            .{},
            class_name,
            window_name,
            win32wm.WS_OVERLAPPEDWINDOW,
            win32wm.CW_USEDEFAULT,
            win32wm.CW_USEDEFAULT,
            @bitCast(self.width),
            @bitCast(self.height),
            null,
            null,
            window_class.hInstance,
            self,
        ) orelse return error.CreateWindowFailed;

        // const menu = win32wm.CreateMenu() orelse return error.CreateMenuFailed;
        // const menu_bar = win32wm.CreateMenu() orelse return error.CreateMenuFailed;
        // _ = win32wm.AppendMenuW(menu, win32wm.MF_STRING, 1, utf8ToUtf16LeStringLiteral("&New"));
        // _ = win32wm.AppendMenuW(menu, win32wm.MF_STRING, 2, utf8ToUtf16LeStringLiteral("&Close"));
        // _ = win32wm.AppendMenuW(menu_bar, win32wm.MF_POPUP, @intFromPtr(menu), utf8ToUtf16LeStringLiteral("&File"));
        // _ = win32wm.SetMenu(hwnd, menu_bar);

        const darkmode: u32 = 1;

        _ = win32dwm.DwmSetWindowAttribute(
            hwnd,
            win32dwm.DWMWA_USE_IMMERSIVE_DARK_MODE,
            &darkmode,
            @sizeOf(u32),
        );

        self.hwnd = hwnd;

        self.renderer = try RendererApi.init(self, allocator);

        _ = win32wm.ShowWindow(hwnd, .{ .SHOWNORMAL = 1 });
    }

    pub fn close(self: *Window) void {
        self.renderer.deinit();
    }

    pub fn resize(self: *Window, height: u32, width: u32) !void {
        self.height = height;
        self.width = width;
    }

    fn WindowProcSetup(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT {
        if (msg != win32wm.WM_NCCREATE) {
            return win32wm.DefWindowProcW(hwnd, msg, wparam, lparam);
        }
        const p_create: *const win32wm.CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(lparam)));
        const self: *Window = @ptrCast(@alignCast(p_create.lpCreateParams));

        _ = win32wm.SetWindowLongPtrW(hwnd, .P_USERDATA, @bitCast(@intFromPtr(self)));
        _ = win32wm.SetWindowLongPtrW(hwnd, .P_WNDPROC, @bitCast(@intFromPtr(&WindowProcWrapper)));

        return self.WindowProc(hwnd, msg, wparam, lparam);
    }
    fn WindowProcWrapper(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT {
        const self: *Window = @ptrFromInt(@as(usize, @bitCast(win32wm.GetWindowLongPtrW(hwnd, .P_USERDATA))));
        return self.WindowProc(hwnd, msg, wparam, lparam);
    }
    fn WindowProc(self: *Window, hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) LRESULT {
        switch (msg) {
            win32wm.WM_DESTROY => {
                self.exit = true;
                win32wm.PostQuitMessage(0);
                return 0;
            },
            win32wm.WM_KEYDOWN, win32wm.WM_SYSKEYDOWN => {
                if (wparam == @intFromEnum(win32.ui.input.keyboard_and_mouse.VK_ESCAPE)) {
                    win32wm.PostQuitMessage(0);
                }
                return 0;
            },
            win32wm.WM_SIZING => {
                return 0;
            },
            win32wm.WM_ENTERSIZEMOVE => {
                return win32wm.SendMessageW(hwnd, win32wm.WM_SETREDRAW, 0, 0);
            },
            win32wm.WM_EXITSIZEMOVE => {
                return win32wm.SendMessageW(hwnd, win32wm.WM_SETREDRAW, 1, 0);
            },
            win32wm.WM_ERASEBKGND => {
                return 0;
            },
            win32wm.WM_SIZE => {
                const lp: usize = @as(usize, @bitCast(lparam));
                const width: u32 = @intCast(lp & 0xFFFF);
                const height: u32 = @intCast((lp >> 16) & 0xFFFF);
                self.resize(height, width) catch return -1;
                return 0;
            },
            else => return win32wm.DefWindowProcW(hwnd, msg, wparam, lparam),
        }
    }

    pub fn messageLoop(self: *Window) void {
        while (!self.exit) {
            self.pumpMessages();
        }
    }

    pub fn pumpMessages(self: *Window) void {
        var msg: win32wm.MSG = undefined;

        while (win32wm.PeekMessageW(&msg, null, 0, 0, .{ .REMOVE = 1 }) != 0) {
            if (msg.message == win32wm.WM_QUIT) {
                self.exit = true;
                return;
            }

            _ = win32wm.TranslateMessage(&msg);
            _ = win32wm.DispatchMessageW(&msg);
        }
    }
};

const X11Window = struct {
    const x11 = @cImport({
        @cInclude("X11/Xlib.h");
        @cInclude("X11/keysym.h");
    });

    const RendererApi = @import("renderer/root.zig").Renderer;

    socket: i32 = undefined,
    title: []const u8,
    height: u32,
    width: u32,
    display: *x11.Display = undefined,
    s: c_int = undefined,
    w: c_ulong = undefined,
    renderer: RendererApi = undefined,

    exit: bool = false,
    wm_delete_window: c_ulong = 0,

    pub fn new(title: []const u8, height: u32, width: u32) Window {
        return .{
            .title = title,
            .height = height,
            .width = width,
        };
    }

    pub fn open(self: *Window, allocator: Allocator) !void {
        const display = x11.XOpenDisplay(null);
        const screen = x11.DefaultScreen(display);

        self.display = display.?;
        self.s = screen;

        // x11 window is created inside opengl context creator
        self.renderer = try RendererApi.init(self, allocator);

        const name = try std.fmt.allocPrintZ(allocator, "{s}", .{self.title});
        _ = x11.XStoreName(@ptrCast(display), self.w, name.ptr);
        allocator.free(name);

        var wm_delete_window = x11.XInternAtom(@ptrCast(self.display), "WM_DELETE_WINDOW", 0);
        _ = x11.XSetWMProtocols(@ptrCast(self.display), self.w, &wm_delete_window, 1);

        self.wm_delete_window = wm_delete_window;
    }

    pub fn messageLoop(self: *Window) void {
        while (!self.exit) {
            self.pumpMessages();
        }
    }

    pub fn pumpMessages(self: *Window) void {
        var event: x11.XEvent = undefined;
        const pending = x11.XPending(self.display);
        var i: c_int = 0;
        while (i < pending) : (i += 1) {
            _ = x11.XNextEvent(self.display, &event);

            if (event.type == x11.KeyPress and
                x11.XLookupKeysym(@constCast(&event.xkey), 0) == x11.XK_Escape)
            {
                self.exit = true;
                break;
            }

            if (event.type == x11.ClientMessage and
                event.xclient.data.l[0] == self.wm_delete_window)
            {
                self.exit = true;
                break;
            }
        }
    }

    pub fn close(self: *Window, allocator: Allocator) void {
        self.renderer.deinit(allocator);
        _ = x11.XDestroyWindow(@ptrCast(self.display), self.w);
        _ = x11.XCloseDisplay(@ptrCast(self.display));
    }
};
