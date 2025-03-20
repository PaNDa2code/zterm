const std = @import("std");
const win32 = @import("win32");
const builtin = @import("builtin");

const Self = @This();

const page_size = (if (builtin.os.tag == .windows) 64 else 8) * 1024;

real_size: usize = 0,
buffer: []u8 = undefined,
start: usize = 0,
len: usize = 0,

pub const CreateError = error{
    VMemoryReserveFailed,
    VMemorySplitingFailed,
    VMemoryMappingFailed,
    CreatingPageMappingFailed,
    PageMappingFailed,
};

pub fn new(requsted_size: usize) !Self {
    var self = Self{};
    try self.init(if (requsted_size == 0) 1 else requsted_size);
    return self;
}

pub fn init(self: *Self, requsted_size: usize) CreateError!void {
    return if (builtin.os.tag == .windows) self.init_windows(requsted_size) else self.init_posix(requsted_size);
}

pub fn deinit(self: *Self) void {
    return if (builtin.os.tag == .windows) self.deinit_windows() else self.deinit_posix();
}

inline fn init_windows(self: *Self, requsted_size: usize) CreateError!void {
    const size = std.mem.alignForward(usize, requsted_size, 64 * 1024);

    const palce_holder = win32.system.memory.VirtualAlloc2(
        null,
        null,
        size * 2,
        .{ .RESERVE = 1, .RESERVE_PLACEHOLDER = 1 },
        @bitCast(win32.system.memory.PAGE_NOACCESS),
        null,
        0,
    );

    if (palce_holder == null) {
        return CreateError.VMemoryReserveFailed;
    }

    var flags: u32 = @intFromEnum(win32.system.memory.MEM_PRESERVE_PLACEHOLDER);
    flags |= @intFromEnum(win32.system.memory.MEM_RELEASE);

    if (std.os.windows.kernel32.VirtualFree(palce_holder, size, flags) == 0) {
        return CreateError.VMemorySplitingFailed;
    }

    const section = win32.system.memory.CreateFileMappingW(
        win32.foundation.INVALID_HANDLE_VALUE,
        null,
        .{ .PAGE_READWRITE = 1 },
        0,
        @intCast(size),
        null,
    );

    if (section == null or section == win32.foundation.INVALID_HANDLE_VALUE) {
        return CreateError.CreatingPageMappingFailed;
    }

    defer _ = win32.foundation.CloseHandle(section);

    const view1 = win32.system.memory.MapViewOfFile3(
        section,
        null,
        palce_holder,
        0,
        size,
        .{ .REPLACE_PLACEHOLDER = 1 },
        @bitCast(win32.system.memory.PAGE_READWRITE),
        null,
        0,
    );

    if (view1 == null) {
        return CreateError.VMemoryMappingFailed;
    }

    errdefer _ = win32.system.memory.UnmapViewOfFile(view1);

    const view2 = win32.system.memory.MapViewOfFile3(
        section,
        null,
        @ptrFromInt(@intFromPtr(palce_holder) + size),
        0,
        size,
        .{ .REPLACE_PLACEHOLDER = 1 },
        @bitCast(win32.system.memory.PAGE_READWRITE),
        null,
        0,
    );

    if (view2 == null) {
        return CreateError.VMemoryMappingFailed;
    }

    errdefer _ = win32.system.memory.UnmapViewOfFile(view2);

    self.buffer.ptr = @ptrCast(view1.?);
    self.buffer.len = size * 2;
    self.real_size = size;
}

inline fn init_posix(self: *Self, requsted_size: usize) CreateError!void {
    const size = std.mem.alignForward(usize, requsted_size, page_size);

    const place_holder = std.posix.mmap(
        null,
        size * 2,
        std.posix.PROT.NONE,
        .{ .ANONYMOUS = true, .TYPE = .PRIVATE },
        -1,
        0,
    ) catch {
        return CreateError.VMemoryReserveFailed;
    };

    errdefer std.posix.munmap(place_holder);

    const split_address: []u8 align(page_size) = place_holder[size..];
    std.posix.munmap(@alignCast(split_address));

    // using shm_open to work with both linux and macos
    const fd = std.c.shm_open("/ciruler_buffer_file", 2 | 64, 0x180);
    if (fd == -1) return CreateError.CreatingPageMappingFailed;
    defer _ = std.c.shm_unlink("/ciruler_buffer_file");

    _ = std.posix.ftruncate(fd, size) catch {
        return CreateError.CreatingPageMappingFailed;
    };

    const view1 = std.posix.mmap(
        @alignCast(place_holder.ptr),
        size,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED, .FIXED = true },
        fd,
        0,
    ) catch {
        return CreateError.VMemoryMappingFailed;
    };

    errdefer std.posix.munmap(view1);

    const view2 = std.posix.mmap(
        @alignCast(place_holder.ptr + size),
        size,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED, .FIXED = true },
        fd,
        0,
    ) catch {
        return CreateError.VMemoryMappingFailed;
    };

    errdefer std.posix.munmap(view2);

    self.buffer = view1.ptr[0 .. size * 2];
    self.real_size = size;
}

inline fn deinit_posix(self: *Self) void {
    if (self.buffer.len == 0 or self.real_size == 0) return;
    std.posix.munmap(@alignCast(self.buffer[0..self.real_size]));
    std.posix.munmap(@alignCast(self.buffer[self.real_size..]));
    self.buffer = &[_]u8{};
    self.real_size = 0;
}

inline fn deinit_windows(self: *Self) void {
    if (self.buffer.len == 0 or self.real_size == 0) return;
    _ = win32.system.memory.UnmapViewOfFile(self.buffer.ptr);
    _ = win32.system.memory.UnmapViewOfFile(self.buffer[self.real_size..].ptr);
}

fn write_commit(self: *Self, bytes_count: usize) void {
    self.len += bytes_count;
    if (self.len > self.real_size) {
        self.start = self.len - self.real_size;
        self.len = self.real_size;
    }
}

pub fn write(self: *Self, buffer: []const u8) anyerror!usize {
    @setRuntimeSafety(false);
    const bytes = @min(self.real_size, buffer.len);
    const write_start = self.start + self.len;
    const write_end = write_start + bytes;
    @memcpy(self.buffer[write_start..write_end], buffer[0..bytes]);
    self.write_commit(bytes);
    return bytes;
}

pub fn read(self: *Self, buffer: []u8) anyerror!usize {
    const bytes = @min(self.len, buffer.len);
    @memcpy(buffer[0..bytes], self.buffer[self.start..]);
    return bytes;
}

pub fn getReadableSlice(self: *const Self) []const u8 {
    return self.buffer[self.start..][0..self.len];
}

const Writer = std.io.GenericWriter(*Self, anyerror, write);
const Reader = std.io.GenericReader(*Self, anyerror, read);

pub fn writer(self: *Self) Writer {
    return .{ .context = self };
}

pub fn reader(self: *Self) Reader {
    return .{ .context = self };
}

test "ciruler buffer test writer" {
    var ciruler_buffer = try Self.new(0);
    defer ciruler_buffer.deinit();

    var ciruler_buffer_writer = ciruler_buffer.writer();
    // var ciruler_buffer_reader = ciruler_buffer.reader();

    const data = "0123456789ABCDEF";
    _ = try ciruler_buffer_writer.write(data);

    try std.testing.expectEqualSlices(u8, data, ciruler_buffer.getReadableSlice());
}
