const std = @import("std");
const gl = @import("gl");

const OpenGLRenderer = @This();
const DynamicLibrary = @import("../../DynamicLibrary.zig");
const OpenGLContext = @import("OpenGLContext.zig").OpenGLContext;

threadlocal var porc: gl.ProcTable = undefined;
threadlocal var gl_lib: DynamicLibrary = undefined;
threadlocal var load_proc_once = std.once(getProcTableOnce);

proc_table: *gl.ProcTable,
context: OpenGLContext,

fn getProc(name: [*:0]const u8) ?*const anyopaque {
    var p: ?*const anyopaque = null;

    p = OpenGLContext.glGetProcAddress(name);

    // https://www.khronos.org/opengl/wiki/Load_OpenGL_Functions
    if (p == null or
        @import("builtin").os.tag == .windows and
            (p == @as(?*const anyopaque, @ptrFromInt(1)) or
                p == @as(?*const anyopaque, @ptrFromInt(2)) or
                p == @as(?*const anyopaque, @ptrFromInt(3)) or
                p == @as(?*const anyopaque, @ptrFromInt(@as(usize, @bitCast(@as(isize, -1)))))))
    {
        p = gl_lib.getProcAddress(name);
    }

    return p;
}

fn getProcTableOnce() void {
    const shared_lib_name = switch (@import("builtin").os.tag) {
        .windows => "opengl32",
        .linux, .macos => "libGL.so.1",
        else => {},
    };

    gl_lib = DynamicLibrary.init(shared_lib_name) catch unreachable;

    if (!porc.init(getProc)) {
        std.debug.panic("failed to load opengl proc table", .{});
    }

    gl.makeProcTableCurrent(&porc);
}

pub fn init(window: *Window) !OpenGLRenderer {
    var self: OpenGLRenderer = undefined;
    self.context = try OpenGLContext.createOpenGLContext(window);
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
    self.context.swapBuffers();
}

const common = @import("../common.zig");
const ColorRGBA = common.ColorRGBA;
const Window = @import("../../window.zig").Window;
