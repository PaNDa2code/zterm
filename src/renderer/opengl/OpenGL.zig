// OpenGL renderer

threadlocal var gl_proc: gl.ProcTable = undefined;
threadlocal var gl_lib: DynamicLibrary = undefined;
threadlocal var gl_proc_is_loaded: bool = false;

context: OpenGLContext,
vertex_shader: gl.uint,
fragment_shader: gl.uint,
shader_program: gl.uint,
characters: [128]Character,
atlas: gl.uint,
window_height: u32,
window_width: u32,
VAO: gl.uint,
VBO: gl.uint,

fn getProc(name: [*:0]const u8) ?*const anyopaque {
    var p: ?*const anyopaque = null;

    p = OpenGLContext.glGetProcAddress(name);

    // https://www.khronos.org/opengl/wiki/Load_OpenGL_Functions
    if (p == null or
        builtin.os.tag == .windows and
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
        .linux => "libGL.so.1",
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

pub fn init(window: *Window, allocator: Allocator) !OpenGLRenderer {
    var self: OpenGLRenderer = undefined;
    self.context = try OpenGLContext.createOpenGLContext(window);

    if (!gl_proc_is_loaded)
        getProcTableOnce();

    self.window_height = window.height;
    self.window_width = window.width;

    // load_proc_once.call();

    self.vertex_shader = gl.CreateShader(gl.VERTEX_SHADER);
    gl_proc.ShaderSource(self.vertex_shader, 1, &.{@ptrCast(vertex_shader_source.ptr)}, null);

    self.fragment_shader = gl.CreateShader(gl.FRAGMENT_SHADER);
    gl_proc.ShaderSource(self.fragment_shader, 1, &.{@ptrCast(fragment_shader_source.ptr)}, null);

    gl_proc.CompileShader(self.vertex_shader);
    gl_proc.CompileShader(self.fragment_shader);

    self.shader_program = gl_proc.CreateProgram();
    gl_proc.AttachShader(self.shader_program, self.vertex_shader);
    gl_proc.AttachShader(self.shader_program, self.fragment_shader);
    gl_proc.LinkProgram(self.shader_program);

    gl_proc.DeleteShader(self.vertex_shader);
    gl_proc.DeleteShader(self.fragment_shader);

    try self.loadChars(allocator);

    var VAO: gl.uint = undefined;
    var VBO: gl.uint = undefined;
    gl.GenVertexArrays(1, @ptrCast(&VAO));
    gl.GenBuffers(1, @ptrCast(&VBO));
    gl.BindVertexArray(VAO);
    gl.BindBuffer(gl.ARRAY_BUFFER, VBO);
    gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(f32) * 6 * 4, null, gl.DYNAMIC_DRAW);
    gl.EnableVertexAttribArray(0);
    gl.VertexAttribPointer(0, 4, gl.FLOAT, gl.FALSE, 4 * @sizeOf(f32), 0);
    gl.BindBuffer(gl.ARRAY_BUFFER, 0);
    gl.BindVertexArray(0);

    self.VAO = VAO;
    self.VBO = VBO;

    return self;
}

pub fn deinit(self: *OpenGLRenderer, allocator: Allocator) void {
    _ = allocator;
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

pub fn loadChars(self: *OpenGLRenderer, allocator: Allocator) !void {
    const ft_library = try freetype.Library.init(allocator);
    defer ft_library.deinit();
    // const linux_ttf = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf";
    const win_ttf = "C:\\Users\\Panda\\Downloads\\dejavu-sans\\ttf\\DejaVuSans.ttf";
    const font_face = try ft_library.face(win_ttf, 24);
    defer font_face.deinit();

    var c: u8 = 20;

    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1);

    gl.Enable(gl.BLEND);
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    while (c < 128) : (c += 1) {
        const glyph = try font_face.getGlyph(c);
        defer glyph.deinit();

        var texture: gl.uint = 0;

        gl_proc.GenTextures(1, @ptrCast(&texture));
        gl_proc.BindTexture(gl.TEXTURE_2D, texture);

        gl_proc.TexImage2D(
            gl.TEXTURE_2D,
            0,
            gl.RED,
            @intCast(font_face.ft_face.*.glyph.*.bitmap.width),
            @intCast(font_face.ft_face.*.glyph.*.bitmap.rows),
            0,
            gl.RED,
            gl.UNSIGNED_BYTE,
            font_face.ft_face.*.glyph.*.bitmap.buffer,
        );

        gl_proc.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl_proc.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl_proc.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl_proc.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

        const character = Character{
            .texture_id = texture,
            .size = .{
                .x = @intCast(font_face.ft_face.*.glyph.*.bitmap.width),
                .y = @intCast(font_face.ft_face.*.glyph.*.bitmap.rows),
            },
            .bearing = .{
                .x = @intCast(font_face.ft_face.*.glyph.*.bitmap_left),
                .y = @intCast(font_face.ft_face.*.glyph.*.bitmap_top),
            },
            .advance = @intCast(font_face.ft_face.*.glyph.*.advance.x),
        };

        self.characters[@intCast(c)] = character;
    }
}

pub fn renaderText(self: *OpenGLRenderer, buffer: []const u8, x: u32, y: u32, color: ColorRGBA) void {
    gl.UseProgram(self.shader_program);
    gl.Uniform3f(gl.GetUniformLocation(self.shader_program, "textColor"), color.r, color.g, color.b);
    gl.ActiveTexture(gl.TEXTURE0);
    gl.BindVertexArray(self.VAO);

    const projection = math.makeOrtho2D(@floatFromInt(self.window_width), @floatFromInt(self.window_height));
    gl.UniformMatrix4fv(gl.GetUniformLocation(self.shader_program, "projection"), 1, gl.FALSE, @ptrCast(&projection));

    var _x: u32 = x;
    for (buffer) |c| {
        const ch = if (c < self.characters.len) self.characters[@intCast(c)] else continue;
        const xpos: f32 = @floatFromInt(@as(i32, @intCast(_x)) + ch.bearing.x);
        const ypos: f32 = @floatFromInt(@as(i32, @intCast(y)) - ch.size.y + ch.bearing.y);

        const w: f32 = @floatFromInt(ch.size.x);
        const h: f32 = @floatFromInt(ch.size.y);

        const vertices = [6]Vec4(f32){
            .{ .x = xpos, .y = ypos + h, .z = 0, .w = 0 },
            .{ .x = xpos, .y = ypos, .z = 0, .w = 1 },
            .{ .x = xpos + w, .y = ypos, .z = 1, .w = 1 },
            .{ .x = xpos, .y = ypos + h, .z = 0, .w = 0 },
            .{ .x = xpos + w, .y = ypos, .z = 1, .w = 1 },
            .{ .x = xpos + w, .y = ypos + h, .z = 1, .w = 0 },
        };

        gl.BindTexture(gl.TEXTURE_2D, @intCast(ch.texture_id));
        gl.BindBuffer(gl.ARRAY_BUFFER, self.VBO);
        gl.BufferSubData(gl.ARRAY_BUFFER, 0, @sizeOf(@TypeOf(vertices)), &vertices);
        gl.BindBuffer(gl.ARRAY_BUFFER, 0);
        gl.DrawArrays(gl.TRIANGLES, 0, 6);
        _x += (ch.advance >> 6);
    }
    gl.BindVertexArray(0);
    gl.BindTexture(gl.TEXTURE_2D, 0);
}

pub fn resize(self: *OpenGLRenderer, width: u32, height: u32) void {
    self.window_width = width;
    self.window_height = height;
}

const Character = packed struct {
    texture_id: u32,
    size: Vec2(i32),
    bearing: Vec2(i32),
    advance: u32,
};

const math = @import("../math.zig");
const Vec2 = math.Vec2;
const Vec4 = math.Vec4;

const OpenGLRenderer = @This();
const DynamicLibrary = @import("../../DynamicLibrary.zig");

const OpenGLContext = switch (builtin.os.tag) {
    .windows => @import("WGLContext.zig"),
    .linux => @import("GLXContext.zig"),
    else => void,
};

const std = @import("std");
const builtin = @import("builtin");
const gl = @import("gl");
const common = @import("../common.zig");
const ColorRGBA = common.ColorRGBA;
const Window = @import("../../window.zig").Window;
const freetype = @import("freetype");

const Allocator = std.mem.Allocator;
