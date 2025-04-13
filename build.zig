const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    // const zig_openpty = b.dependency("zig_openpty", .{});
    // const openpty_mod = zig_openpty.module("openpty");

    const win32 = b.dependency("zigwin32", .{});
    const win32_mod = win32.module("win32");

    const vtparse = b.dependency("vtparse", .{});
    const vtparse_mod = vtparse.module("vtparse");

    const c_freetype = b.dependency("freetype", .{});
    const freetype = blk: {
        const freetype = b.addStaticLibrary(.{
            .name = "freetype2",
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });

        freetype.addCSourceFiles(.{
            .files = ft2_srcs,
            .flags = ft2_flags,
            .root = c_freetype.path("."),
        });

        const ftsys =
            switch (target.result.os.tag) {
                .windows => "builds/windows/ftsystem.c",
                .macos, .linux => "builds/unix/ftsystem.c",
                else => "src/base/ftsystem.c",
            };

        freetype.addCSourceFile(.{
            .file = c_freetype.path(ftsys),
            .flags = ft2_flags,
        });

        if (optimize == .Debug) {
            const ftdbg: []const []const u8 =
                switch (target.result.os.tag) {
                    .windows => &.{ "builds/windows/ftdebug.c", "src/base/ftver.rc" },
                    else => &.{"src/base/ftdebug.c"},
                };

            freetype.addCSourceFiles(.{
                .files = ftdbg,
                .flags = ft2_flags,
                .root = c_freetype.path("."),
            });
        }

        freetype.addIncludePath(c_freetype.path("include/"));

        break :blk freetype;
    };

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("win32", win32_mod);
    // exe_mod.addImport("openpty", openpty_mod);
    exe_mod.addImport("vtparse", vtparse_mod);

    exe_mod.addIncludePath(c_freetype.path("include/"));
    exe_mod.linkLibrary(freetype);

    const exe = b.addExecutable(.{
        .name = "cross_pty",
        .root_module = exe_mod,
        .linkage = if (target.result.abi == .musl) .static else .dynamic,
    });

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

const ft2_srcs: []const []const u8 = &.{
    "src/autofit/autofit.c",
    "src/base/ftbase.c",
    "src/base/ftbbox.c",
    "src/base/ftbdf.c",
    "src/base/ftbitmap.c",
    "src/base/ftcid.c",
    "src/base/ftfstype.c",
    "src/base/ftgasp.c",
    "src/base/ftglyph.c",
    "src/base/ftgxval.c",
    "src/base/ftinit.c",
    "src/base/ftmm.c",
    "src/base/ftotval.c",
    "src/base/ftpatent.c",
    "src/base/ftpfr.c",
    "src/base/ftstroke.c",
    "src/base/ftsynth.c",
    // "src/base/ftsystem.c", // we will provide our own primitives
    "src/base/fttype1.c",
    "src/base/ftwinfnt.c",
    "src/bdf/bdf.c",
    "src/bzip2/ftbzip2.c",
    "src/cache/ftcache.c",
    "src/cff/cff.c",
    "src/cid/type1cid.c",
    "src/gzip/ftgzip.c",
    "src/lzw/ftlzw.c",
    "src/pcf/pcf.c",
    "src/pfr/pfr.c",
    "src/psaux/psaux.c",
    "src/pshinter/pshinter.c",
    "src/psnames/psnames.c",
    "src/raster/raster.c",
    "src/sdf/sdf.c",
    "src/sfnt/sfnt.c",
    "src/smooth/smooth.c",
    "src/svg/svg.c",
    "src/truetype/truetype.c",
    "src/type1/type1.c",
    "src/type42/type42.c",
    "src/winfonts/winfnt.c",
};

const ft2_flags: []const []const u8 = &.{
    "-DFT2_BUILD_LIBRARY",
    "-DFT_CONFIG_OPTION_ERROR_STRINGS",
};
