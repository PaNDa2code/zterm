instance: vk.Instance,
physical_device: vk.PhysicalDevice, // GPU
device: vk.Device, // GPU drivers
swap_chain: vk.SwapchainKHR,
surface: vk.SurfaceKHR, // Window surface
base_dispatch: vk.BaseDispatch,
instance_dispatch: vk.InstanceDispatch,
device_dispatch: vk.DeviceDispatch,
window_height: u32,
window_width: u32,

const VulkanRenderer = @This();

pub fn init(window: *Window, allocator: Allocator) !VulkanRenderer {
    const app_info = vk.ApplicationInfo{
        .p_application_name = "zterm",

        .application_version = 0,
        .api_version = @bitCast(vk.HEADER_VERSION_COMPLETE),

        .p_engine_name = "no_engine",
        .engine_version = 0,
    };

    const win32_exts = [_][*:0]const u8{
        "VK_KHR_win32_surface",
    };

    const xlib_exts = [_][*:0]const u8{
        "VK_KHR_xlib_surface",
        "VK_EXT_acquire_xlib_display",
    };

    const extensions = [_][*:0]const u8{
        "VK_KHR_surface",
    } ++ switch (os_tag) {
        .windows => win32_exts,
        .linux => xlib_exts,
        else => {},
    };

    const inst_info = vk.InstanceCreateInfo{
        .p_application_info = &app_info,
        .enabled_extension_count = extensions.len,
        .pp_enabled_extension_names = &extensions,
    };

    const vkb = vk.BaseWrapper.load(baseGetInstanceProcAddress);

    const instance = try vkb.createInstance(&inst_info, null);

    const vki = vk.InstanceWrapper.load(instance, vkb.dispatch.vkGetInstanceProcAddr.?);
    errdefer vki.destroyInstance(instance, null);

    var surface: vk.SurfaceKHR = .null_handle;

    switch (@import("builtin").os.tag) {
        .windows => {
            const surface_info: vk.Win32SurfaceCreateInfoKHR = .{
                .hwnd = @ptrCast(window.hwnd),
                .hinstance = window.h_instance,
            };
            surface = try vki.createWin32SurfaceKHR(instance, &surface_info, null);
        },
        .linux => {
            const surface_info: vk.XlibSurfaceCreateInfoKHR = .{
                .window = window.w,
                .dpy = @ptrCast(window.display),
            };
            surface = try vki.createXlibSurfaceKHR(instance, &surface_info, null);
        },
        else => {},
    }

    var physical_devices_count: u32 = 0;
    _ = try vki.enumeratePhysicalDevices(instance, &physical_devices_count, null);

    std.log.info("Vulkan detected {} GPUs", .{physical_devices_count});

    const physical_devices = try allocator.alloc(vk.PhysicalDevice, physical_devices_count);
    defer allocator.free(physical_devices);

    _ = try vki.enumeratePhysicalDevices(instance, &physical_devices_count, physical_devices.ptr);

    for (physical_devices, 0..) |pd, i| {
        const props = vki.getPhysicalDeviceProperties(pd);
        std.log.info("GPU{}: {s}", .{ i, props.device_name });
        const api_version: vk.Version = @bitCast(props.api_version);
        std.log.info("API version: {}.{}.{}.{}", .{ api_version.major, api_version.minor, api_version.patch, api_version.variant });
    }

    const queue_create_info: vk.DeviceQueueCreateInfo = .{
        .queue_family_index = 0,
        .queue_count = 1,
        .p_queue_priorities = &.{1},
    };

    const ext = [_][*:0]const u8{
        "VK_KHR_swapchain",
    };

    const device_create_info: vk.DeviceCreateInfo = .{
        .queue_create_info_count = 1,
        .p_queue_create_infos = &.{queue_create_info},
        .enabled_extension_count = ext.len,
        .pp_enabled_extension_names = &ext,
    };

    const device = try vki.createDevice(physical_devices[0], &device_create_info, null);

    const vkd = vk.DeviceWrapper.load(device, vki.dispatch.vkGetDeviceProcAddr.?);

    const caps: vk.SurfaceCapabilitiesKHR =
        try vki.getPhysicalDeviceSurfaceCapabilitiesKHR(physical_devices[0], surface);

    const swap_chain_extent: vk.Extent2D =
        if (caps.current_extent.width == -1 or caps.current_extent.height == -1)
            .{
                .highet = window.height,
                .width = window.width,
            }
        else
            caps.current_extent;

    var present_modes_count: u32 = 0;

    _ = try vki.getPhysicalDeviceSurfacePresentModesKHR(
        physical_devices[0],
        surface,
        &present_modes_count,
        null,
    );

    const present_modes = try allocator.alloc(vk.PresentModeKHR, present_modes_count);
    defer allocator.free(present_modes);

    _ = try vki.getPhysicalDeviceSurfacePresentModesKHR(
        physical_devices[0],
        surface,
        &present_modes_count,
        present_modes.ptr,
    );

    var present_mode: vk.PresentModeKHR = .fifo_khr;

    for (present_modes) |mode| {
        if (mode == .mailbox_khr) {
            present_mode = .mailbox_khr;
            break;
        }
        if (mode == .immediate_khr)
            present_mode = .immediate_khr;
    }

    std.debug.assert(caps.max_image_count >= 1);

    var image_count = caps.min_image_count + 1;

    if (caps.max_image_count < image_count)
        image_count = caps.max_image_count;

    const swap_chain_create_info: vk.SwapchainCreateInfoKHR = .{
        .surface = surface,
        .min_image_count = image_count,
        .image_format = .r8g8b8a8_unorm,
        .image_color_space = .srgb_nonlinear_khr,
        .image_extent = swap_chain_extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true },
        .image_sharing_mode = .exclusive,
        .queue_family_index_count = 1,
        .p_queue_family_indices = &.{0},
        .pre_transform = .{ .identity_bit_khr = true },
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = present_mode,
        .clipped = 0,
    };

    const swap_chain = try vkd.createSwapchainKHR(device, &swap_chain_create_info, null);

    return .{
        .swap_chain = swap_chain,
        .device = device,
        .instance = instance,
        .physical_device = physical_devices[0],
        .surface = surface,
        .base_dispatch = vkb.dispatch,
        .instance_dispatch = vki.dispatch,
        .device_dispatch = vkd.dispatch,
        .window_height = window.height,
        .window_width = window.width,
    };
}

fn setImageLayout(
    cmd_buffer: vk.CommandBuffer,
    image: vk.Image,
    aspects: vk.ImageAspectFlags,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
) !void {
    _ = cmd_buffer;
    var src_access_mask: vk.AccessFlags = .{};
    var dst_access_mask: vk.AccessFlags = .{};

    switch (old_layout) {
        .preinitialized => {
            src_access_mask.host_write_bit = true;
            src_access_mask.host_read_bit = true;
        },
        .attachment_optimal => {
            src_access_mask.color_attachment_write_bit = true;
        },
        .depth_stentcil_attachment_optimal => {
            src_access_mask.depth_stencil_attachment_write_bit = true;
        },
        .shader_read_only_optimal => {
            src_access_mask.shader_read_bit = true;
        },
        else => {},
    }

    switch (new_layout) {
        .transfer_dst_optimal => {
            dst_access_mask.transfer_write_bit = true;
        },
        .transfer_src_optimal => {
            src_access_mask.transfer_read_bit = true;
            dst_access_mask.transfer_read_bit = true;
        },
        .attachment_optimal => {
            dst_access_mask.color_attachment_write_bit = true;
            src_access_mask.transfer_read_bit = true;
        },
        .depth_stencil_attachment_optimal => {
            dst_access_mask.depth_stencil_attachment_write_bit = true;
        },
        .shader_read_only_optimal => {
            src_access_mask.host_write_bit = true;
            src_access_mask.transfer_write_bit = true;
            dst_access_mask.shader_read_bit = true;
        },
        else => {},
    }
    const image_barriar: vk.ImageMemoryBarrier = .{
        .old_layout = old_layout,
        .new_layout = new_layout,
        .src_access_mask = src_access_mask,
        .dst_access_mask = dst_access_mask,
        .image = image,
        .subresource_range = .{
            .aspect_mask = aspects,
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    };

    _ = image_barriar;
}

fn baseGetInstanceProcAddress(_: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction {
    const vk_lib = DynamicLibrary.init("vulkan-1") catch return null;
    return @ptrCast(vk_lib.getProcAddress(procname));
}

pub fn deinit(self: *VulkanRenderer) void {
    const vki: vk.InstanceWrapper = .{ .dispatch = self.instance_dispatch };
    const vkd: vk.DeviceWrapper = .{ .dispatch = self.device_dispatch };

    vkd.destroySwapchainKHR(self.device, self.swap_chain, null);
    vkd.destroyDevice(self.device, null);

    vki.destroySurfaceKHR(self.instance, self.surface, null);
    vki.destroyInstance(self.instance, null);
}

pub fn clearBuffer(self: *VulkanRenderer, color: ColorRGBA) void {
    _ = self;
    _ = color;
}

pub fn presentBuffer(self: *VulkanRenderer) void {
    _ = self;
}

pub fn renaderText(self: *VulkanRenderer, buffer: []const u8, x: u32, y: u32, color: ColorRGBA) void {
    _ = self;
    _ = buffer;
    _ = x;
    _ = y;
    _ = color;
}

const std = @import("std");
const builtin = @import("builtin");
const os_tag = builtin.os.tag;
const vk = @import("vulkan");
const common = @import("../common.zig");
const Window = @import("../../window.zig").Window;
const Allocator = std.mem.Allocator;
const ColorRGBA = common.ColorRGBA;
const DynamicLibrary = @import("../../DynamicLibrary.zig");
const VkMemInterface = @import("VkMemInterface.zig");
