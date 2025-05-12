const std = @import("std");
const gl = @import("gl");

const OpenGLRenderer = @This();
const DynamicLibrary = @import("../../DynamicLibrary.zig");

threadlocal var porc: gl.ProcTable = undefined;
threadlocal var gl_lib: DynamicLibrary = undefined;
threadlocal var load_proc_once = std.once(getProcTableOnce);

proc_table: *gl.ProcTable,
deivce_context: *anyopaque,

fn getProc(name: [*:0]const u8) ?*const anyopaque {
    var p: ?*const anyopaque = null;

    p = @import("win32").graphics.open_gl.wglGetProcAddress(name);

    // zig fmt: off
    // https://www.khronos.org/opengl/wiki/Load_OpenGL_Functions
    if (p == null 
        or @intFromPtr(p) == 1 
        or @intFromPtr(p) == 2 
        or @intFromPtr(p) == 3 
        or @as(isize, @bitCast(@intFromPtr(p))) == -1) 
    {
        p = gl_lib.getProcAddress(name);
    }
    // zig fmt: on

    return p;
}

fn getProcTableOnce() void {
    if (!porc.init(getProc)) {
        std.debug.panic("failed to load opengl proc table", .{});
    }

    gl.makeProcTableCurrent(&porc);
}

pub fn init(hwnd: *anyopaque) !OpenGLRenderer {
    var self: OpenGLRenderer = undefined;
    self.deivce_context = try @import("context.zig").createOpenGLContextWin(@ptrCast(hwnd));
    gl_lib = try DynamicLibrary.init("opengl32.dll");
    load_proc_once.call();
    self.proc_table = &porc;
    return self;
}

pub fn deinit(self: *OpenGLRenderer) void {
    _ = self;
}

pub fn clearBuffer(self: *OpenGLRenderer, color: ColorRGBA) void {
    self.proc_table.ClearColor(color.r, color.g, color.b, color.a);
    self.proc_table.Clear(gl.COLOR_BUFFER_BIT);
}

pub fn presentBuffer(self: *OpenGLRenderer) void {
    _ = @import("win32").graphics.open_gl.SwapBuffers(@ptrCast(self.deivce_context));
}

const common = @import("../common.zig");
const ColorRGBA = common.ColorRGBA;
