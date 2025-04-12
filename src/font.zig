const std = @import("std");
const ft = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
    @cInclude("freetype/ftmodapi.h");
});

const Font = @This();

const Allocator = std.mem.Allocator;
const FT_Library = ft.FT_Library;
const FT_Face = ft.FT_Face;
const FT_MemoryRec = ft.FT_MemoryRec_;
const FT_Memory = ft.FT_Memory;

allocator: Allocator,
ft_library: FT_Library,
font_face: FT_Face,
ft_memory_rec: FT_MemoryRec,

fn addSizeHeader(block: []u8, header: usize) []u8 {
    std.mem.writeInt(usize, @ptrCast(block.ptr), header, .little);
    return block[@sizeOf(usize)..];
}

fn getSizedSlice(ptr: *anyopaque) []u8 {
    const block_ptr: [*]u8 = @ptrFromInt(@intFromPtr(ptr) - @sizeOf(usize));
    const total_size = std.mem.readInt(usize, @ptrCast(block_ptr), .little);
    return block_ptr[0..total_size];
}

fn ftAlloc(ft_memory: FT_Memory, size: c_long) callconv(.c) ?*anyopaque {
    const allocator: *Allocator = @alignCast(@ptrCast(ft_memory.*.user));
    const total_size: usize = @intCast(size + @sizeOf(usize));
    const buffer = allocator.alloc(u8, total_size) catch return null;
    return addSizeHeader(buffer, total_size).ptr;
}

fn ftFree(ft_memory: FT_Memory, block_ptr: ?*anyopaque) callconv(.c) void {
    const allocator: *Allocator = @alignCast(@ptrCast(ft_memory.*.user));
    const block = getSizedSlice(block_ptr.?);
    allocator.free(block);
}

fn ftRealloc(ft_memory: FT_Memory, cur_size: c_long, new_size: c_long, block_ptr: ?*anyopaque) callconv(.c) ?*anyopaque {
    const allocator: *Allocator = @alignCast(@ptrCast(ft_memory.*.user));
    const old_block = getSizedSlice(block_ptr.?);
    std.debug.assert(old_block.len == cur_size + @sizeOf(usize));
    const new_total_size: usize = @intCast(new_size + @sizeOf(usize));
    const new_block = allocator.realloc(old_block, new_total_size) catch return null;
    return addSizeHeader(new_block, new_total_size).ptr;
}

pub fn init(self: *Font, allocator: Allocator) !void {
    self.allocator = allocator;
    self.ft_memory_rec = .{
        .user = &self.allocator,
        .alloc = &ftAlloc,
        .free = &ftFree,
        .realloc = &ftRealloc,
    };

    var err: ft.FT_Error = 0;
    err = ft.FT_New_Library(&self.ft_memory_rec, &self.ft_library);
    if (err != 0) {
        const errstr = std.mem.span(ft.FT_Error_String(err));
        std.debug.print("FreeType {s}\n", .{errstr});
        return error.FTNewLibFailed;
    }
    ft.FT_Add_Default_Modules(self.ft_library);
}

pub fn deinit(self: *Font) void {
    _ = ft.FT_Done_Library(self.ft_library);
}

test {
    var font: Font = undefined;
    try font.init(std.testing.allocator);
    defer font.deinit();
}
