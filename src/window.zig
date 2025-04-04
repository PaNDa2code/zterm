const std = @import("std");
const win32 = @import("win32");
const builtin = @import("builtin");

const os = builtin.os.tag;

pub const Window = if (os == .windows) Win32Window else X11Window;

const Win32Window = struct {
    const L = std.unicode.utf8ToUtf16LeStringLiteral;
    const W = std.unicode.utf8ToUtf16LeAllocZ;

    const win32con = win32.system.console;
    const win32fnd = win32.foundation;
    const win32pipe = win32.system.pipes;
    const win32sec = win32.security;
    const win32thread = win32.system.threading;
    const win32storeage = win32.storage;
    const win32fs = win32storeage.file_system;
    const win32mem = win32.system.memory;
    const win32wm = win32.ui.windows_and_messaging;
    const win32dwm = win32.graphics.dwm;
    const win32loader = win32.system.library_loader;

    const HANDLE = win32fnd.HANDLE;
    const HPCON = win32con.HPCON;
    const HWND = win32fnd.HWND;
    const LRESULT = win32fnd.LRESULT;
    const WPARAM = win32fnd.WPARAM;
    const LPARAM = win32fnd.LPARAM;

    hwnd: HWND = undefined,
    title: []const u8 = undefined,
    hight: u32,
    width: u32,

    pub fn init(self: *Win32Window) !void {
        const class_name = L("WindowClass");

        const window_class: win32wm.WNDCLASSW = .{
            .lpszClassName = class_name,
            .hInstance = win32loader.GetModuleHandle(null),
            .lpfnWndProc = &WindowProcSetup,
            .style = .{},
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hbrBackground = null,
            .hCursor = null,
            .hIcon = null,
            .lpszMenuName = null,
        };

        _ = win32wm.RegisterClassW(&window_class);

        const hwnd = win32wm.CreateWindowExW(
            .{},
            class_name,
            L("terminal"),
            win32wm.WS_OVERLAPPED,
            win32wm.CW_USEDEFAULT,
            win32wm.CW_USEDEFAULT,
            @bitCast(self.width),
            @bitCast(self.hight),
            null,
            null,
            window_class.hInstance,
            self,
        ) orelse return error.CreateWindowFailed;

        // const menu = win32wm.CreateMenu() orelse return error.CreateMenuFailed;
        // const menu_bar = win32wm.CreateMenu() orelse return error.CreateMenuFailed;
        // _ = win32wm.AppendMenuW(menu, win32wm.MF_STRING, 1, L("New"));
        // _ = win32wm.AppendMenuW(menu, win32wm.MF_STRING, 2, L("Close"));
        // _ = win32wm.AppendMenuW(menu_bar, win32wm.MF_POPUP, @intFromPtr(menu), L("&File"));
        // _ = win32wm.SetMenu(hwnd, menu_bar);

        const darkmode: u32 = 1;

        _ = win32dwm.DwmSetWindowAttribute(
            hwnd,
            win32dwm.DWMWA_USE_IMMERSIVE_DARK_MODE,
            &darkmode,
            @sizeOf(u32),
        );

        _ = win32wm.ShowWindow(hwnd, .{ .SHOWNORMAL = 1 });
        self.hwnd = hwnd;
    }
    fn WindowProcSetup(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT {
        if (msg != win32wm.WM_NCCREATE) {
            return win32wm.DefWindowProc(hwnd, msg, wparam, lparam);
        }
        const p_create: *const win32wm.CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(lparam)));
        const self: *Win32Window = @ptrCast(@alignCast(p_create.lpCreateParams));

        _ = win32wm.SetWindowLongPtr(hwnd, .P_USERDATA, @bitCast(@intFromPtr(self)));
        _ = win32wm.SetWindowLongPtr(hwnd, .P_WNDPROC, @bitCast(@intFromPtr(&WindowProcWrapper)));

        return self.WindowProc(hwnd, msg, wparam, lparam);
    }
    fn WindowProcWrapper(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT {
        const self: *Win32Window = @ptrFromInt(@as(usize, @bitCast(win32wm.GetWindowLongPtr(hwnd, .P_USERDATA))));
        return self.WindowProc(hwnd, msg, wparam, lparam);
    }
    fn WindowProc(self: *Win32Window, hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) LRESULT {
        _ = self; // autofix
        switch (msg) {
            win32wm.WM_DESTROY => {
                win32wm.PostQuitMessage(0);
                return 0;
            },
            win32wm.WM_KEYDOWN, win32wm.WM_SYSKEYDOWN => {
                if (wparam == @intFromEnum(win32.ui.input.keyboard_and_mouse.VK_ESCAPE)) {
                    win32wm.PostQuitMessage(0);
                }
                return 0;
            },
            win32wm.WM_SIZE => {
                return 0;
            },
            else => return win32wm.DefWindowProcW(hwnd, msg, wparam, lparam),
        }
    }

    pub fn messageLoop(self: *Win32Window) void {
        _ = self; // autofix
        var msg: win32wm.MSG = undefined;
        while (true) {
            if (win32wm.PeekMessageW(&msg, null, 0, 0, .{ .REMOVE = 1 }) > 0) {
                if (msg.message == win32wm.WM_QUIT)
                    break;
                _ = win32wm.TranslateMessage(&msg);
                _ = win32wm.DispatchMessage(&msg);
            }
        }
    }
};

const X11Window = struct {
    socket: i32,
    pub fn init(self: *X11Window) !void {
        _ = self;
    }

    pub fn messageLoop(self: *X11Window) void {
        _ = self;
    }
};
