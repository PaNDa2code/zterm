const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = b.addOptions();

    const options_desc = .{
        .{ RenderBackend, "render-backend", "Select the graphics backend to use for rendering", .OpenGL },
    };

    inline for (@typeInfo(@TypeOf(options_desc)).@"struct".fields) |field| {
        const T = @field(options_desc, field.name).@"0";
        const name = @field(options_desc, field.name).@"1";
        const description = @field(options_desc, field.name).@"2";
        const defult_value = @field(options_desc, field.name).@"3";
        options.addOption(T, name, b.option(T, name, description) orelse defult_value);
    }

    const zig_openpty = b.dependency("zig_openpty", .{});
    const openpty_mod = zig_openpty.module("openpty");

    const win32 = b.dependency("zigwin32", .{});
    const win32_mod = win32.module("win32");

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

    const gl_bindings = @import("zigglgen").generateBindingsModule(b, .{
        .api = .gl,
        .version = .@"4.0",
        .profile = .core,
        .extensions = &.{},
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("win32", win32_mod);
    exe_mod.addImport("openpty", openpty_mod);
    exe_mod.addImport("vtparse", vtparse_mod);
    exe_mod.addImport("freetype", freetype_mod);
    exe_mod.addImport("gl", gl_bindings);
    if (target.result.os.tag == .linux) exe_mod.linkSystemLibrary("X11", .{});

    const exe = b.addExecutable(.{
        .name = "cross_pty",
        .root_module = exe_mod,
        .linkage = if (target.result.abi == .musl) .static else .dynamic,
    });

    exe.link_gc_sections = true;
    exe.root_module.addOptions("config", options);

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
