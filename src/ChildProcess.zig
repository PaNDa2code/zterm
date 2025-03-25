const std = @import("std");
const win32 = @import("win32");
const builtin = @import("builtin");

const Wide = std.unicode.utf8ToUtf16LeStringLiteral;
const WideAlloc = std.unicode.utf8ToUtf16LeAllocZ;

const posix = std.posix;
const posix_c = @cImport({
    @cInclude("unistd.h");
    @cInclude("sys/ioctl.h");
    @cInclude("pty.h");
});

const win32con = win32.system.console;
const win32fnd = win32.foundation;
const win32pipe = win32.system.pipes;
const win32sec = win32.security;
const win32thread = win32.system.threading;
const win32fs = win32.storage.file_system;
const win32mem = win32.system.memory;

const Pty = @import("pty.zig").Pty;
const ChildProcess = @This();

const File = std.fs.File;
const Allocator = std.mem.Allocator;

const os = builtin.os.tag;

id: switch (os) {
    .windows => win32fnd.HANDLE,
    .macos, .linux => posix.pid_t,
    else => @compileError("os is not supported"),
} = undefined,

exe_path: []const u8,
args: []const []const u8 = &.{""},
env_map: ?std.hash_map.StringHashMap([]const u8) = null,
cwd: ?[]const u8 = null,

stdin: ?File = null,
stdout: ?File = null,
stderr: ?File = null,

pty: ?*Pty = null,

pub fn start(self: *ChildProcess, allocator: Allocator) !void {
    var arina = std.heap.ArenaAllocator.init(allocator);
    defer arina.deinit();

    const arina_allocator = arina.allocator();

    return switch (builtin.os.tag) {
        .windows => self.startWindows(arina_allocator),
        .linux, .macos => self.startPosix(arina_allocator),
        else => @compileError("os is not supported"),
    };
}

pub fn terminate(self: *ChildProcess) void {
    switch (builtin.os.tag) {
        .windows => self.terminateWindows(),
        .linux, .macos => self.terminatePosix(),
        else => @compileError("os is not supported"),
    }
}

pub fn wait(self: *ChildProcess) !void {
    return switch (builtin.os.tag) {
        .windows => self.waitWindows(),
        .linux, .macos => self.waitPosix(),
        else => @compileError("os is not supported"),
    };
}

fn startWindows(self: *ChildProcess, arina: Allocator) !void {
    var startup_info_ex = std.mem.zeroes(win32thread.STARTUPINFOEXW);
    startup_info_ex.StartupInfo.cb = @sizeOf(win32thread.STARTUPINFOEXW);

    if (self.pty) |pty| {
        var bytes_required: usize = 0;
        // ignored becuse it always fails
        _ = win32thread.InitializeProcThreadAttributeList(null, 1, 0, &bytes_required);

        const buffer = try arina.alloc(u8, bytes_required);

        startup_info_ex.lpAttributeList = @ptrCast(buffer.ptr);

        if (win32thread.InitializeProcThreadAttributeList(startup_info_ex.lpAttributeList, 1, 0, &bytes_required) == 0) {
            return error.InitializeProcThreadAttributeListFailed;
        }

        if (win32thread.UpdateProcThreadAttribute(
            startup_info_ex.lpAttributeList,
            0,
            win32thread.PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
            pty.h_pesudo_console,
            @sizeOf(win32con.HPCON),
            null,
            null,
        ) == 0) {
            return error.UpdateProcThreadAttributeFailed;
        }
        self.stdin = .{ .handle = pty.master_write };
        self.stdout = .{ .handle = pty.master_read };
        self.stderr = .{ .handle = pty.master_read };
    }

    var proc_info = std.mem.zeroes(win32thread.PROCESS_INFORMATION);

    const path = try findPathAlloc(arina, self.exe_path);
    const path_absolute = try std.fs.realpathAlloc(arina, path orelse self.exe_path);
    const path_absoluteW = try WideAlloc(arina, path_absolute);

    const cwd = if (self.cwd) |cwd_path| (try WideAlloc(arina, cwd_path)).ptr else null;

    var env_block: ?*anyopaque = null;
    if (self.env_map) |envmap| {
        var buffer = std.ArrayList(u8).init(arina);
        var writer = buffer.writer();

        var it = envmap.iterator();
        while (it.next()) |entry| {
            try writer.print("{}={}\x00", .{ entry.key_ptr, entry.value_ptr });
        }
        try writer.writeByte(0);
        env_block = buffer.items.ptr;
    }

    if (win32thread.CreateProcessW(
        path_absoluteW.ptr,
        null,
        null,
        null,
        0,
        if (self.pty != null) .{ .EXTENDED_STARTUPINFO_PRESENT = 1 } else .{},
        env_block,
        cwd,
        if (self.pty != null) &startup_info_ex.StartupInfo else null,
        &proc_info,
    ) == 0) {
        return error.CreateProcessWFailed;
    }

    self.id = proc_info.hProcess.?;
}

fn terminateWindows(self: *ChildProcess) void {
    _ = win32thread.TerminateProcess(self.id, 0);
}

fn waitWindows(self: *ChildProcess) !void {
    if (win32thread.WaitForSingleObject(self.id, std.math.maxInt(u32)) != 0) {
        return error.WatingFailed;
    }
}

fn startPosix(self: *ChildProcess, arina: std.mem.Allocator) !void {
    const slave_fd = self.pty.?.slave;
    const master_fd = self.pty.?.master;

    const path = try findPathAlloc(arina, self.exe_path);
    const path_absolute = try std.fs.realpathAlloc(arina, path orelse self.exe_path);
    std.debug.print("\npath_absolute = {s}\n", .{path_absolute});
    const pathZ = try arina.dupeZ(u8, path_absolute);
    const argsZ = try arina.allocSentinel(?[*:0]u8, self.args.len, null);
    for (self.args, 0..) |arg, i| {
        argsZ[i] = try arina.dupeZ(u8, arg);
    }

    const envZ: [*:null]?[*:0]u8 = if (self.env_map) |env_map| envz: {
        const envZ = try arina.allocSentinel(?[*:0]u8, env_map.count(), null);
        var it = env_map.iterator();
        var i: usize = 0;
        while (it.next()) |entry| : (i += 1) {
            envZ[i] = try std.fmt.allocPrintZ(
                arina,
                "{s}={s}",
                .{ entry.key_ptr, entry.value_ptr },
            );
        }
        break :envz envZ.ptr;
    } else std.c.environ;

    const pid = try posix.fork();

    if (pid != 0) {
        self.stdin = .{ .handle = master_fd };
        self.stdout = .{ .handle = master_fd };
        self.stderr = .{ .handle = master_fd };
        posix.close(slave_fd);
        return;
    }

    _ = posix_c.setsid();
    _ = posix_c.ioctl(slave_fd, posix_c.TIOCSCTTY, @as(usize, 0));

    try posix.dup2(slave_fd, posix.STDIN_FILENO);
    try posix.dup2(slave_fd, posix.STDOUT_FILENO);
    try posix.dup2(slave_fd, posix.STDERR_FILENO);

    posix.close(master_fd);
    posix.close(slave_fd);

    posix.execveZ(pathZ, argsZ, envZ) catch {
        posix.exit(127);
    };
}

fn terminatePosix(self: *ChildProcess) void {
    _ = posix.kill(self.id, posix.SIG.TERM) catch {};
}

fn waitPosix(self: *ChildProcess) !void {
    _ = posix.waitpid(self.id, 0);
}

fn findPathAlloc(allocator: Allocator, exe: []const u8) !?[]const u8 {
    const sep = std.fs.path.sep;
    const delimiter = std.fs.path.delimiter;

    const PATH = switch (os) {
        .windows => getpathblock: {
            const win_path = std.process.getenvW(Wide("PATH")) orelse return null;
            const path = try std.unicode.utf16LeToUtf8AllocZ(allocator, win_path[0..]);
            break :getpathblock path;
        },
        else => posix.getenvZ("PATH") orelse return null,
    };

    defer if (os == .windows) allocator.free(PATH);

    var it = std.mem.tokenizeScalar(u8, PATH, delimiter);
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    while (it.next()) |search_path| {
        const path_len = search_path.len + exe.len + 1;
        @memcpy(path_buf[0..search_path.len], search_path);
        path_buf[search_path.len] = sep;
        @memcpy(path_buf[search_path.len + 1 ..][0..exe.len], exe);
        path_buf[path_len] = 0;
        const full_path = path_buf[0..path_len :0];
        const file = std.fs.cwd().openFile(full_path, .{}) catch |err| {
            switch (err) {
                error.FileNotFound => continue,
                error.AccessDenied => continue,
                else => {
                    return err;
                },
            }
        };
        defer file.close();
        const stat = try file.stat();
        if (stat.kind != .directory and (os == .windows or stat.mode & 0o0111 != 0)) {
            return try allocator.dupe(u8, full_path);
        }
    }

    return null;
}

test "test ChildProcess" {
    var pty: Pty = undefined;
    try pty.open(.{});
    defer pty.close();

    var child: ChildProcess = .{
        .exe_path = if (os == .windows) "cmd" else "bash",
        .pty = &pty,
        .args = &.{},
    };

    try child.start(std.testing.allocator);
    defer child.terminate();

    var child_stdin = child.stdin.?;
    var child_stdout = child.stdout.?;

    try child_stdin.writeAll("echo HelloWorld\n");

    var buffer: [1024]u8 = undefined;
    _ = try child_stdout.read(&buffer);
}
