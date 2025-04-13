const std = @import("std");
const builtin = @import("builtin");

const ft = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
    @cInclude("freetype/ftmodapi.h");
});

const FreeType = @This();
const Allocator = std.mem.Allocator;

const DefualtFontsLocation = switch (builtin.os.tag) {
    .windows => "C:\\Windows\\Fonts",
    .linux => "/usr/share/fonts",
    else => "",
};

const default_ft_memory: ft.FT_MemoryRec_ = .{
    .user = null,
    .alloc = &ftAlloc,
    .free = &ftFree,
    .realloc = &ftRealloc,
};

allocator: Allocator = undefined,
ft_library: ft.FT_Library = null,
font_face: ft.FT_Face = null,
ft_memory_rec: ft.FT_MemoryRec_ = default_ft_memory,

pub fn init(self: *FreeType, allocator: Allocator) !void {
    self.* = .{};
    self.allocator = allocator;
    self.ft_memory_rec.user = &self.allocator;

    var ft_err: ft.FT_Error = 0;
    ft_err = ft.FT_New_Library(&self.ft_memory_rec, &self.ft_library);
    if (ft_err != 0) {
        const errstr = std.mem.span(ft.FT_Error_String(ft_err));
        std.log.err("FreeType {s}\n", .{errstr});
        return error.FTNewLibFailed;
    }
    ft.FT_Add_Default_Modules(self.ft_library);
}

pub fn setFont(self: *FreeType, font_path: []const u8) !void {
    var ft_err: ft.FT_Error = 0;

    const font_path_z: [:0]u8 =
        if (std.fs.path.isAbsolute(font_path))
            try std.fs.path.joinZ(self.allocator, &.{font_path})
        else
            try std.fs.path.joinZ(self.allocator, &.{ DefualtFontsLocation, font_path });

    defer self.allocator.free(font_path_z);

    ft_err = ft.FT_New_Face(self.ft_library, font_path_z.ptr, 0, &self.font_face);

    if (ft_err != 0) {
        std.log.err("FT_New_Face --> {s}", .{ft.FT_Error_String(ft_err)});
        self.font_face = null; // clear any garpage value
        return switch (ft_err) {
            ft.FT_Err_Cannot_Open_Resource => error.CantOpenFontFile,
            ft.FT_Err_Invalid_Argument => error.InvalidArgument,
            ft.FT_Err_Unknown_File_Format => error.UnkownFontFileFormat,
            ft.FT_Err_Invalid_File_Format => error.InvalidFontFileFormat,
            ft.FT_Err_Out_Of_Memory => error.OutOfMemory,
            else => error.Unexpcted,
        };
    }
}

pub const GlyphIter = struct {
    face: ft.FT_Face,
    char_code: c_ulong = 0,
    index: u32 = 0,

    fn init(face: ft.FT_Face) GlyphIter {
        var index: u32 = 0;
        const char_code = ft.FT_Get_First_Char(face, &index);
        return .{
            .face = face,
            .index = index,
            .char_code = char_code,
        };
    }

    pub fn next(self: *GlyphIter) ?*ft.FT_GlyphSlotRec {
        self.char_code = ft.FT_Get_Next_Char(self.face, self.char_code, &self.index);
        return if (self.index == 0)
            null
        else
            self.face.*.glyph;
    }
};

/// returns an iterator object (GlyphIter) to loop over the font glyphs.
pub fn glyphIter(self: *FreeType) GlyphIter {
    return GlyphIter.init(self.font_face);
}

pub fn deinit(self: *FreeType) void {
    _ = if (self.font_face) |face| ft.FT_Done_Face(face);
    _ = if (self.ft_library) |library| ft.FT_Done_Library(library);
}

// Writes the total size of the allocation into the beginning of the block_ptr
// (includeing the header size).
// Returns the slice after the size header.
fn addSizeHeader(block: []u8, header: usize) []u8 {
    std.mem.writeInt(usize, @ptrCast(block.ptr), header, .little);
    return block[@sizeOf(usize)..];
}

// Retrieves the full slice including the header, using the pointer returned to the user.
// The size is read from the header just before the actual data pointer.
fn getSizedSlice(ptr: *anyopaque) []u8 {
    const block_ptr: [*]u8 = @ptrFromInt(@intFromPtr(ptr) - @sizeOf(usize));
    const total_size = std.mem.readInt(usize, @ptrCast(block_ptr), .little);
    return block_ptr[0..total_size];
}

// Allocator callback for FreeType: allocates memory with extra space for the size header.
// Returns a pointer to the usable memory (after the header).
// TODO: Ensure returned pointer is properly aligned after offsetting for the size header.
fn ftAlloc(ft_memory: ft.FT_Memory, size: c_long) callconv(.c) ?*anyopaque {
    const allocator: *Allocator = @alignCast(@ptrCast(ft_memory.*.user));
    const total_size: usize = @intCast(size + @sizeOf(usize));
    const buffer = allocator.alloc(u8, total_size) catch return null;
    return addSizeHeader(buffer, total_size).ptr;
}

// Allocator callback for FreeType: frees memory previously allocated by ftAlloc.
// Retrieves the full slice including the size header and frees it.
fn ftFree(ft_memory: ft.FT_Memory, block_ptr: ?*anyopaque) callconv(.c) void {
    const allocator: *Allocator = @alignCast(@ptrCast(ft_memory.*.user));
    const block = getSizedSlice(block_ptr.?);
    allocator.free(block);
}

// Allocator callback for FreeType: reallocates memory, preserving data and updating the size header.
// Asserts that the original size matches what was stored, resizes the block, and rewrites the header.
fn ftRealloc(ft_memory: ft.FT_Memory, cur_size: c_long, new_size: c_long, block_ptr: ?*anyopaque) callconv(.c) ?*anyopaque {
    const allocator: *Allocator = @alignCast(@ptrCast(ft_memory.*.user));
    const old_block = getSizedSlice(block_ptr.?);
    std.debug.assert(old_block.len == cur_size + @sizeOf(usize));
    const new_total_size: usize = @intCast(new_size + @sizeOf(usize));
    const new_block = allocator.realloc(old_block, new_total_size) catch return null;
    return addSizeHeader(new_block, new_total_size).ptr;
}

test {}
