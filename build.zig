const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const target_os = target.result.os.tag;
    const options = b.addOptions();
    const window_system_option = b.option(WindowSystem, "window-system", "Window system or library");
    const render_backend_option = b.option(RenderBackend, "render-backend", "Select the graphics backend to use for rendering");

    const window_system: WindowSystem = window_system_option orelse
        switch (target_os) {
            .windows => .Win32,
            .linux => .Xcb, // Use xcb as defulat for now
            else => @panic("target os not supported yet"),
        };

    // Moving towards making vulkan the defulat renderer
    const render_backend: RenderBackend = render_backend_option orelse .Vulkan;

    // Add final values to the source code exposed options
    options.addOption(WindowSystem, "window-system", window_system);
    options.addOption(RenderBackend, "render-backend", render_backend);


    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const vtparse = b.dependency("vtparse", .{
        .target = target,
        .optimize = optimize,
    });
    const vtparse_mod = vtparse.module("vtparse");

    const freetype = b.dependency("zig_freetype2", .{
        .target = target,
        .optimize = optimize,
    });
    const freetype_mod = freetype.module("zig_freetype2");

    switch (target.result.os.tag) {
        .windows => {
            const win32 = b.dependency("zigwin32", .{});
            const win32_mod = win32.module("win32");
            exe_mod.addImport("win32", win32_mod);
        },
        .linux => {
            const zig_openpty = b.dependency("zig_openpty", .{});
            const openpty_mod = zig_openpty.module("openpty");
            exe_mod.addImport("openpty", openpty_mod);
        },
        else => @panic("os not supported yet"),
    }

    exe_mod.addImport("vtparse", vtparse_mod);
    exe_mod.addImport("freetype", freetype_mod);

    switch (render_backend) {
        .OpenGL => {
            const gl_bindings = @import("zigglgen").generateBindingsModule(b, .{
                .api = .gl,
                .version = .@"4.0",
                .profile = .core,
                .extensions = &.{},
            });
            exe_mod.addImport("gl", gl_bindings);
            if (target_os == .linux)
                exe_mod.linkSystemLibrary("GLX", .{});
        },
        .Vulkan => {
            const vulkan = b.dependency("vulkan", .{
                .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
            });

            const vulkan_mod = vulkan.module("vulkan-zig");
            exe_mod.addImport("vulkan", vulkan_mod);
        },
        .D3D11 => {},
    }

    switch (window_system) {
        .Win32 => {},
        .Xlib => {
            exe_mod.linkSystemLibrary("X11", .{});
        },
        .Xcb => {
            exe_mod.linkSystemLibrary("xcb", .{});
        },
    }

    const exe = b.addExecutable(.{
        .name = "cross_pty",
        .root_module = exe_mod,
        .linkage = if (target.result.abi == .musl) .static else .dynamic,
    });

    exe.link_gc_sections = true;
    exe.root_module.addOptions("build_options", options);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

const RenderBackend = enum {
    D3D11,
    OpenGL,
    Vulkan,
};

const WindowSystem = enum {
    Win32,
    Xlib,
    Xcb,
};

const Config = struct {
    window_system: WindowSystem,
    render_backend: RenderBackend,
};
