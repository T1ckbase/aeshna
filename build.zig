// Copyright (c) 2026 T1ckbase
// SPDX-License-Identifier: GPL-3.0-or-later

const std = @import("std");

const manifest = @import("build.zig.zon");
const name: []const u8 = @tagName(manifest.name);

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86_64,
            .os_tag = .windows,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    // if (target.result.os.tag != .windows or target.result.cpu.arch != .x86_64) {
    //     std.debug.panic("{s} only supports windows-x86_64 targets (got {s}-{s})", .{
    //         name,
    //         @tagName(target.result.os.tag),
    //         @tagName(target.result.cpu.arch),
    //     });
    // }

    const obs_studio = b.dependency("obs_studio", .{});
    const obs_studio_windows = b.dependency("obs_studio_windows", .{});

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

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.addWriteFiles().add("obs.h",
            \\#include <obs-module.h>
            \\#include <util/base.h>
            \\#include <util/dstr.h>
            \\#include <util/platform.h>
        ),
        .target = target,
        .optimize = optimize,
    });
    translate_c.addIncludePath(obs_studio.path("libobs"));
    translate_c.addConfigHeader(obs_config);

    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .imports = &.{
            .{
                .name = "build.zig.zon",
                .module = b.createModule(.{
                    .root_source_file = b.path("build.zig.zon"),
                    .target = target,
                    .optimize = optimize,
                }),
            },
            .{
                .name = "obs",
                .module = translate_c.createModule(),
            },
        },
        .target = target,
        .optimize = optimize,
        .strip = optimize != .Debug,
        // .link_libc = true,
    });
    // mod.addIncludePath(obs.path("libobs"));
    // mod.addConfigHeader(obs_config);
    mod.addLibraryPath(obs_studio_windows.path("bin/64bit"));
    mod.linkSystemLibrary("obs", .{});

    const plugin = b.addLibrary(.{
        .name = name,
        .root_module = mod,
        .linkage = .dynamic,
    });
    b.getInstallStep().dependOn(&b.addInstallArtifact(plugin, .{
        .dest_dir = .{ .override = .{ .custom = b.pathJoin(&.{ name, "bin", "64bit" }) } },
    }).step);
    b.installDirectory(.{
        .source_dir = b.path("data"),
        .install_dir = .prefix,
        .install_subdir = b.pathJoin(&.{ name, "data" }),
    });

    const plugin_check = b.addLibrary(.{
        .name = "check",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const check_step = b.step("check", "Check if code compiles");
    check_step.dependOn(&plugin_check.step);
}
