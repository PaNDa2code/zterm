//! Allows Vulkan to use Zig's memory management via plug-in style callbacks.
//! Provides a `VkAllocationCallbacks` using Zig's `Allocator`.

// TODO: store allocation data without extra map
const Record = struct {
    size: usize,
    alignment: std.mem.Alignment,
};
const RecordMap = std.AutoHashMapUnmanaged(usize, Record);

const VkMemInterface = @This();

allocator: Allocator,
record_map: RecordMap = .{},

pub fn create(allocator: Allocator) VkMemInterface {
    return .{
        .allocator = allocator,
    };
}

pub fn destroy(self: *VkMemInterface) void {
    // var iter = self.record_map.iterator();
    // while (iter.next()) |entry| {
    //     const ptr: [*]u8 = @ptrFromInt(entry.key_ptr.*);
    //     const block = ptr[0..entry.value_ptr.size];
    //     self.allocator.vtable.free(
    //         self.allocator.ptr,
    //         block,
    //         entry.value_ptr.alignment,
    //         @returnAddress(),
    //     );
    // }
    self.record_map.deinit(self.allocator);
}

pub fn vkAllocatorCallbacks(self: *VkMemInterface) vk.AllocationCallbacks {
    return .{
        .p_user_data = self,
        .pfn_allocation = VkMemInterface.vkAlloc,
        .pfn_reallocation = VkMemInterface.vkRealloc,
        .pfn_free = VkMemInterface.vkFree,
    };
}

fn allocAndRecord(
    allocator: Allocator,
    record_map: *RecordMap,
    size: usize,
    alignment: std.mem.Alignment,
) ?[*]u8 {
    const buf = allocator.vtable.alloc(allocator.ptr, size, alignment, @returnAddress()) orelse return null;
    record_map.put(
        allocator,
        @intFromPtr(buf),
        .{ .size = size, .alignment = alignment },
    ) catch {
        allocator.vtable.free(allocator.ptr, buf[0..size], alignment, @returnAddress());
        return null;
    };
    return buf;
}

fn freeRecored(
    allocator: Allocator,
    record_map: *RecordMap,
    ptr: *anyopaque,
) void {
    const record_entry = record_map.fetchRemove(@intFromPtr(ptr)) orelse return;
    const block = @as([*]u8, @ptrCast(ptr))[0..record_entry.value.size];
    allocator.vtable.free(allocator.ptr, block, record_entry.value.alignment, @returnAddress());
}

fn vkAlloc(
    p_user_data: ?*anyopaque,
    size: usize,
    alignment: usize,
    allocation_scope: vk.SystemAllocationScope,
) callconv(.c) ?*anyopaque {
    _ = allocation_scope;
    if (p_user_data == null or size == 0)
        return null;

    const vk_allocator: *VkMemInterface = @alignCast(@ptrCast(p_user_data.?));

    const alignment_enum = std.mem.Alignment.fromByteUnits(alignment);

    return VkMemInterface.allocAndRecord(vk_allocator.allocator, &vk_allocator.record_map, size, alignment_enum);
}

fn vkFree(
    p_user_data: ?*anyopaque,
    memory: ?*anyopaque,
) callconv(.c) void {
    if (p_user_data == null or memory == null)
        return;

    const vk_allocator: *VkMemInterface = @alignCast(@ptrCast(p_user_data));
    VkMemInterface.freeRecored(vk_allocator.allocator, &vk_allocator.record_map, memory.?);
}

fn vkRealloc(
    p_user_data: ?*anyopaque,
    p_original: ?*anyopaque,
    size: usize,
    alignment: usize,
    allocation_scope: vk.SystemAllocationScope,
) callconv(.c) ?*anyopaque {
    _ = allocation_scope;
    if (p_user_data == null or p_original == null or size == 0)
        return null;

    const vk_allocator: *VkMemInterface = @alignCast(@ptrCast(p_user_data));
    const allocator = vk_allocator.allocator;

    const old_record_ptr = vk_allocator.record_map.getPtr(@intFromPtr(p_original.?)) orelse return null;
    const new_alignment = std.mem.Alignment.fromByteUnits(alignment);
    const old_block = @as([*]u8, @ptrCast(p_original.?))[0..old_record_ptr.size];

    var new: ?[*]u8 = null;

    if (allocator.vtable.resize(
        allocator.ptr,
        old_block,
        new_alignment,
        size,
        @returnAddress(),
    )) {
        new = old_block.ptr;
        old_record_ptr.size = size;
        old_record_ptr.alignment = new_alignment;
    }

    if (new == null) {
        new = VkMemInterface.allocAndRecord(allocator, &vk_allocator.record_map, size, new_alignment);

        const bytes_to_copy = @min(size, old_block.len);
        @memcpy(new.?[0..bytes_to_copy], old_block[0..bytes_to_copy]);

        VkMemInterface.freeRecored(allocator, &vk_allocator.record_map, p_original.?);
    }

    return new;
}

const std = @import("std");
const vk = @import("vulkan");
const Allocator = std.mem.Allocator;
