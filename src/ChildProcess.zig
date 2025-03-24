const std = @import("std");
const win32 = @import("win32");
const builtin = @import("builtin");

const Wide = std.unicode.utf8ToUtf16LeStringLiteral;
const WideAlloc = std.unicode.utf8ToUtf16LeAllocZ;

const posix = std.posix;
const posix_c = @cImport({
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

id: switch (builtin.os.tag) {
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
        if (self.pty) |pty| pty.h_pesudo_console else null,
        @sizeOf(win32con.HPCON),
        null,
        null,
    ) == 0) {
        return error.UpdateProcThreadAttributeFailed;
    }

    if (self.pty) |pty| {
        self.stdin = .{ .handle = pty.master_write };
        self.stdout = .{ .handle = pty.master_read };
        self.stderr = .{ .handle = pty.master_read };
    }

    var proc_info = std.mem.zeroes(win32thread.PROCESS_INFORMATION);

    const path = try WideAlloc(arina, self.exe_path);
    const cwd = if (self.cwd) |cwd_path| (try WideAlloc(arina, cwd_path)).ptr else null;

    if (win32thread.CreateProcessW(
        path,
        null,
        null,
        null,
        0,
        win32thread.EXTENDED_STARTUPINFO_PRESENT,
        null,
        cwd,
        &startup_info_ex.StartupInfo,
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
    const pid = try posix.fork();
    if (pid != 0) {
        // this is the parant process
        self.id = pid;
        return;
    }
    const pathZ = try arina.dupeZ(u8, self.exe_path);
    var argsZ = try arina.allocSentinel(?[*:0]u8, self.args.len, null);
    const envZ = std.c.environ;

    for (self.args, 0..) |arg, i| {
        argsZ[i] = try arina.dupeZ(u8, arg);
    }

    if (self.pty) |pty| {
        self.stdin = .{ .handle = pty.master };
        self.stdout = .{ .handle = pty.master };
        self.stderr = .{ .handle = pty.master };
    }

    const fields = .{ "stdin", "stdout", "stderr" };
    const targets = .{ "STDIN_FILENO", "STDOUT_FILENO", "STDERR_FILENO" };

    inline for (fields, targets) |field, target| {
        if (@field(self, field)) |file| {
            const flags = try posix.fcntl(file.handle, posix.F.GETFD, 0);
            if (flags & posix.FD_CLOEXEC != 0) {
                _ = try posix.fcntl(
                    file.handle,
                    posix.F.SETFD,
                    flags & ~@as(u32, posix.FD_CLOEXEC),
                );
            }
            try posix.dup2(
                file.handle,
                @field(posix, target),
            );
        }
    }

    _ = posix.execveZ(pathZ, argsZ, envZ) catch null;

    return error.startFailed;
}

fn terminatePosix(self: *ChildProcess) void {
    _ = posix.kill(self.id, posix.SIG.TERM) catch {};
}

fn waitPosix(self: *ChildProcess) !void {
    _ = posix.waitpid(self.id, 0);
}

test "test ChildProcess" {
    var pty: Pty = undefined;
    try pty.open(.{});
    defer pty.close();

    var child: ChildProcess = .{
        .exe_path = "/bin/bash",
        .pty = &pty,
    };

    try child.start(std.testing.allocator);
    child.terminate();
}
