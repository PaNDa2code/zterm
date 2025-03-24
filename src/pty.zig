const std = @import("std");
const win32 = @import("win32");
const builtin = @import("builtin");

const L = std.unicode.utf8ToUtf16LeStringLiteral;
const W = std.unicode.utf8ToUtf16LeAllocZ;

const posix = std.posix;
const win32con = win32.system.console;
const win32fnd = win32.foundation;
const win32pipe = win32.system.pipes;
const win32sec = win32.security;
const win32thread = win32.system.threading;
const win32storeage = win32.storage;
const win32fs = win32storeage.file_system;
const win32mem = win32.system.memory;

var pty_counter = std.atomic.Value(u32).init(0);
const is_windows = builtin.os.tag == .windows;

pub const ShellEnum = enum {
    cmd,
    pws,
    bash,
    zsh,

    fn toString(self: ShellEnum) []const u8 {
        return switch (self) {
            .cmd => "cmd",
            .pws => "powershell",
            .bash => "bash",
            .zsh => "zsh",
        };
    }
};

pub const PtyOptions = struct {
    shell: ?ShellEnum = null,
    shell_args: ?[]const u8 = null,
    async_io: bool = false,
    size: PtySize = .{ .height = 600, .width = 800 },
};

pub const PtySize = packed struct {
    width: u16,
    height: u16,
};

pub const Pty = if (is_windows) WinPty else PosixPty;

const WinPty = struct {
    pub const Fd = HANDLE;

    const HANDLE = win32fnd.HANDLE;
    const HPCON = win32con.HPCON;

    /// child pipe sides
    slave_read: Fd,
    slave_write: Fd,

    /// terminal pipe sides
    master_read: Fd,
    master_write: Fd,

    h_pesudo_console: HPCON,

    size: struct { height: u16, width: u16 },
    id: u32,

    fn isInvaliedOrNull(handle: ?win32fnd.HANDLE) bool {
        return handle == null or handle == win32fnd.INVALID_HANDLE_VALUE;
    }

    pub fn open(self: *WinPty, options: PtyOptions) !void {
        var stdin_read: ?HANDLE = undefined;
        var stdin_write: ?HANDLE = undefined;
        var stdout_read: ?HANDLE = undefined;
        var stdout_write: ?HANDLE = undefined;
        var h_pesudo_console: ?HPCON = undefined;

        if (win32pipe.CreatePipe(&stdin_read, &stdin_write, null, 0) == 0 or isInvaliedOrNull(stdin_read) or isInvaliedOrNull(stdin_write)) {
            return error.PipeCreationFailed;
        }
        if (win32pipe.CreatePipe(&stdout_read, &stdout_write, null, 0) == 0 or isInvaliedOrNull(stdout_read) or isInvaliedOrNull(stdout_write)) {
            return error.PipeCreationFailed;
        }

        // Creating Pty failing can't be handled
        const hresult = win32con.CreatePseudoConsole(
            .{ .X = @intCast(options.size.width), .Y = @intCast(options.size.height) },
            stdin_read,
            stdout_write,
            0,
            &h_pesudo_console,
        );

        if (win32.zig.FAILED(hresult) or isInvaliedOrNull(h_pesudo_console)) {
            return error.CreatePseudoConsoleFailed;
        }

        self.h_pesudo_console = h_pesudo_console.?;
        self.master_write = stdin_write.?;
        self.master_read = stdout_read.?;
        self.slave_write = stdout_write.?;
        self.slave_read = stdin_read.?;
    }

    pub fn close(self: *WinPty) void {
        // no need to terminate the sub process, closing the PTY will do.

        // need to drain the communication pipes before calling ClosePseudoConsole
        var bytes_avalable: u32 = 0;
        var bytes_left: u32 = 0;
        var bytes_read: u32 = 0;

        while (win32pipe.PeekNamedPipe(self.master_read, null, 0, null, &bytes_avalable, &bytes_left) != 0 and bytes_avalable > 0) {
            var buffer: [1024]u8 = undefined;
            const to_read = @min(buffer.len, bytes_avalable);
            _ = win32fs.ReadFile(self.master_read, &buffer, to_read, &bytes_read, null);
        }

        win32con.ClosePseudoConsole(self.h_pesudo_console);
    }

    pub fn resize(self: *WinPty, size: PtySize) !void {
        const hresult = win32con.ResizePseudoConsole(self.h_pesudo_console, @bitCast(size));
        if (hresult < 0) {
            return error.PtyResizeFailed;
        }
    }
};

const PosixPty = struct {
    pub const Fd = posix.fd_t;

    master: Fd,
    slave: Fd,
    size: struct { height: u16, width: u16 },
    id: u32,

    const c = @cImport({
        @cInclude("sys/ioctl.h");
        @cInclude("pty.h");
    });

    pub fn open(self: *PosixPty, options: PtyOptions) !void {
        var master: c_int = undefined;
        var slave: c_int = undefined;

        var ws: c.winsize = .{
            .ws_row = @intCast(options.size.height),
            .ws_col = @intCast(options.size.width),
            .ws_xpixel = 0,
            .ws_ypixel = 0,
        };

        if (c.openpty(&master, &slave, null, null, &ws) < 0) {
            return error.OpenPtyFailed;
        }

        errdefer {
            _ = posix.close(master);
            _ = posix.close(slave);
        }

        cloexec: {
            const flags = posix.fcntl(master, posix.F.GETFD, 0) catch {
                break :cloexec;
            };

            _ = posix.fcntl(
                master,
                posix.F.SETFD,
                flags | posix.FD_CLOEXEC,
            ) catch {
                break :cloexec;
            };
        }
        var attrs: c.termios = undefined;
        if (c.tcgetattr(master, &attrs) != 0)
            return error.OpenptyFailed;
        attrs.c_iflag |= c.IUTF8;
        if (c.tcsetattr(master, c.TCSANOW, &attrs) != 0)
            return error.OpenptyFailed;

        self.master = master;
        self.slave = slave;
        self.id = pty_counter.fetchAdd(1, .acquire);
    }

    pub fn close(self: *PosixPty) void {
        posix.close(self.master);
        posix.close(self.slave);
    }

    pub fn resize(self: *PosixPty, size: PtySize) !void {
        const ws: c.winsize = .{
            .ws_row = size.height,
            .ws_col = size.width,
            .ws_xpixel = 0,
            .ws_ypixel = 0,
        };

        if (c.ioctl(self.master, c.TIOCSWINSZ, &ws) < 0) {
            return error.PtyResizeFailed;
        }
    }
};

test {
    var pty: Pty = undefined;
    try pty.open(.{});
    // closing pty will make a deadlock
    // defer pty.close();
}
