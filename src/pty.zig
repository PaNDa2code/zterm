const std = @import("std");
const win32 = @import("win32");
const builtin = @import("builtin");

const os = builtin.os.tag;

pub const ShellEnum = enum {
    cmd,
    pws,
    bash,
    zsh,
    defualt,

    fn toString(self: ShellEnum) []const u8 {
        return switch (self) {
            .cmd => "cmd",
            .pws => "powershell",
            .bash => "bash",
            .zsh => "zsh",
            else => {},
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

pub const Pty = if (os == .windows) WinPty else PosixPty;

const WinPty = struct {
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
    const HANDLE = win32fnd.HANDLE;
    const HPCON = win32con.HPCON;

    /// child pipe sides
    slave_read: HANDLE,
    slave_write: HANDLE,

    /// terminal pipe sides
    master_read: HANDLE,
    master_write: HANDLE,

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
        // no need to terminate the sub process, closing the HPCON will do.

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
    const posix = std.posix;

    pub const Fd = posix.fd_t;

    master: Fd,
    slave: Fd,
    size: struct { height: u16, width: u16 },
    id: u32,

    const openpty = @import("openpty");

    pub fn open(self: *PosixPty, options: PtyOptions) !void {
        var master: i32 = undefined;
        var slave: i32 = undefined;

        var ws: posix.winsize = .{
            .row = @intCast(options.size.height),
            .col = @intCast(options.size.width),
            .xpixel = 0,
            .ypixel = 0,
        };

        try openpty.openpty(&master, &slave, null, null, null, &ws);

        errdefer {
            _ = posix.close(master);
            _ = posix.close(slave);
        }

        self.master = master;
        self.slave = slave;
    }

    pub fn close(self: *PosixPty) void {
        posix.close(self.master);
        // TODO: this is closed by the child process starting
        // posix.close(self.slave);
    }

    pub fn resize(self: *PosixPty, size: PtySize) !void {
        const ws: posix.winsize = .{
            .row = size.height,
            .col = size.width,
            .xpixel = 0,
            .ypixel = 0,
        };

        if (std.os.linux.ioctl(self.master, 0x5414, &ws) < 0) {
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
