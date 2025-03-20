const std = @import("std");
const win32 = @import("win32");
const builtin = @import("builtin");

const Pty = @This();

var pty_counter = std.atomic.Value(u32).init(0);
const is_windows = builtin.os.tag == .windows;

os_pty: if (is_windows) WinPty else PosixPty,
id: u32,

pub fn init(self: *Pty, options: PtyOptions) !void {
    try self.os_pty.init(options);
    self.id = pty_counter.fetchAdd(1, .acquire);
}

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
    height: u32 = 0,
    width: u32 = 0,
};

const WinPty = struct {
    stdin_write: std.os.windows.HANDLE,
    stdout_read: std.os.windows.HANDLE,
    h_pesudo_console: win32.system.console.HPCON,

    fn isInvaliedOrNull(handle: ?std.os.windows.HANDLE) bool {
        return handle == null or handle == std.os.windows.INVALID_HANDLE_VALUE;
    }

    fn init(self: *WinPty, options: PtyOptions) !void {
        var stdin_read: ?win32.foundation.HANDLE = undefined;
        var stdin_write: ?win32.foundation.HANDLE = undefined;
        var stdout_read: ?win32.foundation.HANDLE = undefined;
        var stdout_write: ?win32.foundation.HANDLE = undefined;
        var h_pesudo_console: ?win32.system.console.HPCON = undefined;

        if (win32.system.pipes.CreatePipe(&stdin_read, &stdin_write, null, 0) == 0 or isInvaliedOrNull(stdin_read) or isInvaliedOrNull(stdin_write)) {
            return error.PipeCreationFailed;
        }
        if (win32.system.pipes.CreatePipe(&stdout_read, &stdout_write, null, 0) == 0 or isInvaliedOrNull(stdout_read) or isInvaliedOrNull(stdout_write)) {
            return error.PipeCreationFailed;
        }

        // Creating Pty failing can't be handled
        const hresult = win32.system.console.CreatePseudoConsole(
            .{ .X = @intCast(options.width), .Y = @intCast(options.height) },
            stdin_read,
            stdout_write,
            0,
            &h_pesudo_console,
        );

        if (win32.zig.FAILED(hresult) or isInvaliedOrNull(h_pesudo_console)) {
            return error.CreatePseudoConsoleFailed;
        }

        self.h_pesudo_console = h_pesudo_console.?;
        self.stdin_write = stdin_write.?;
        self.stdout_read = stdout_read.?;
    }
};

const PosixPty = struct {
    master: std.posix.fd_t,
    slave: std.posix.fd_t,

    inline fn init(self: *PosixPty, options: PtyOptions) !void {
        const c = @cImport({
            @cInclude("sys/ioctl.h");
            @cInclude("pty.h");
        });

        var master: c_int = undefined;
        var slave: c_int = undefined;

        var ws: c.winsize = .{
            .ws_row = @intCast(options.height),
            .ws_col = @intCast(options.width),
            .ws_xpixel = 0,
            .ws_ypixel = 0,
        };

        if (c.openpty(&master, &slave, null, null, &ws) < 0) {
            return error.OpenPtyFailed;
        }

        errdefer {
            _ = std.posix.close(master);
            _ = std.posix.close(slave);
        }

        cloexec: {
            const flags = std.posix.fcntl(master, std.posix.F.GETFD, 0) catch {
                break :cloexec;
            };

            _ = std.posix.fcntl(
                master,
                std.posix.F.SETFD,
                flags | std.posix.FD_CLOEXEC,
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
    }
};

test {
    var pty: Pty = undefined;
    try pty.init(.{});

    // std.debug.print("{any}", .{pty});
}
