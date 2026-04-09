const std = @import("std");
const consts = @import("src/consts.zig");

const plugin_name = consts.plugin_name;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86_64,
            .os_tag = .windows,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    if (target.result.os.tag != .windows or target.result.cpu.arch != .x86_64) {
        std.debug.panic("{s} only supports windows-x86_64 targets (got {s}-{s})", .{
            plugin_name,
            @tagName(target.result.os.tag),
            @tagName(target.result.cpu.arch),
        });
    }

    const obs_dep = b.dependency("obs_studio", .{});
    const obs_rt = b.dependency("obs_windows_runtime", .{});

    const obs_config = b.addConfigHeader(.{
        .style = .blank,
        .include_path = "obsconfig.h",
    }, .{
        .OBS_DATA_PATH = "../../data",
        .OBS_PLUGIN_PATH = "../../obs-plugins/64bit",
        .OBS_PLUGIN_DESTINATION = "obs-plugins/64bit",
        .OBS_RELEASE_CANDIDATE = 0,
        .OBS_BETA = 0,
    });

    const mod = b.addModule("obs_plugin_zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .strip = optimize != .Debug,
    });
    mod.addIncludePath(obs_dep.path("libobs"));
    mod.addConfigHeader(obs_config);
    mod.addLibraryPath(obs_rt.path("bin/64bit"));
    mod.linkSystemLibrary("obs", .{});

    const build_zig_zon = b.createModule(.{
        .root_source_file = b.path("build.zig.zon"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("build.zig.zon", build_zig_zon);

    const plugin = b.addLibrary(.{
        .name = plugin_name,
        .root_module = mod,
        .linkage = .dynamic,
    });
    b.getInstallStep().dependOn(&b.addInstallArtifact(plugin, .{
        .dest_dir = .{ .override = .{ .custom = b.pathJoin(&.{ plugin_name, "bin", "64bit" }) } },
    }).step);
    b.installDirectory(.{
        .source_dir = b.path("data"),
        .install_dir = .prefix,
        .install_subdir = b.pathJoin(&.{ plugin_name, "data" }),
    });

    const plugin_check = b.addLibrary(.{
        .name = plugin_name,
        .root_module = mod,
        .linkage = .dynamic,
    });

    const check_step = b.step("check", "Check if plugin compiles");
    check_step.dependOn(&plugin_check.step);
}
