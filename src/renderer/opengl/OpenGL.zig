const std = @import("std");
const gl = @import("gl");

const OpenGLRenderer = @This();
const DynamicLibrary = @import("../../DynamicLibrary.zig");
const OpenGLContext = @import("OpenGLContext.zig").OpenGLContext;

threadlocal var gl_proc: gl.ProcTable = undefined;
threadlocal var gl_lib: DynamicLibrary = undefined;
threadlocal var gl_proc_is_loaded: bool = false;
// threadlocal var load_proc_once = std.once(getProcTableOnce);

// proc_table: *gl.ProcTable,
context: OpenGLContext,
vertex_shader: gl.uint,
fragment_shader: gl.uint,

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

    if (!gl_proc.init(getProc)) {
        std.debug.panic("failed to load opengl proc table", .{});
    }

    gl.makeProcTableCurrent(&gl_proc);
}

const vertex_shader_source = @embedFile("shaders/vertex.glsl");
const fragment_shader_source = @embedFile("shaders/fragment.glsl");

pub fn init(window: *Window) !OpenGLRenderer {
    var self: OpenGLRenderer = undefined;
    self.context = try OpenGLContext.createOpenGLContext(window);

    if (!gl_proc_is_loaded)
        getProcTableOnce();

    // load_proc_once.call();

    self.vertex_shader = gl.CreateShader(gl.VERTEX_SHADER);
    gl_proc.ShaderSource(self.vertex_shader, 1, &.{@ptrCast(vertex_shader_source.ptr)}, null);

    self.fragment_shader = gl.CreateShader(gl.FRAGMENT_SHADER);
    gl_proc.ShaderSource(self.fragment_shader, 1, &.{@ptrCast(fragment_shader_source.ptr)}, null);

    gl_proc.CompileShader(self.vertex_shader);
    gl_proc.CompileShader(self.fragment_shader);

    return self;
}

pub fn deinit(self: *OpenGLRenderer) void {
    gl_lib.deinit();
    self.context.destory();
}

pub fn clearBuffer(self: *OpenGLRenderer, color: ColorRGBA) void {
    _ = self;
    gl_proc.ClearColor(color.r, color.g, color.b, color.a);
    gl_proc.Clear(gl.COLOR_BUFFER_BIT);
}

pub fn presentBuffer(self: *OpenGLRenderer) void {
    self.context.swapBuffers();
}

const common = @import("../common.zig");
const ColorRGBA = common.ColorRGBA;
const Window = @import("../../window.zig").Window;
