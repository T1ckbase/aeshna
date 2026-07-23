// Copyright (c) 2026 T1ckbase
// SPDX-License-Identifier: GPL-3.0-or-later

const std = @import("std");

const manifest = @import("build.zig.zon");
const obs = @import("obs");

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const log_level = switch (level) {
        .err => obs.LOG_ERROR,
        .warn => obs.LOG_WARNING,
        .info => obs.LOG_INFO,
        .debug => obs.LOG_DEBUG,
    };
    const scope_prefix = if (scope == .default) "" else "[" ++ @tagName(scope) ++ "]";

    var buf: [8192]u8 = undefined;

    const msg = std.fmt.bufPrintZ(
        &buf,
        "[" ++ @tagName(manifest.name) ++ "]" ++ scope_prefix ++ " " ++ format,
        args,
    ) catch |e| switch (e) {
        error.NoSpaceLeft => blk: {
            buf[buf.len - 1] = 0;
            break :blk buf[0 .. buf.len - 1 :0];
        },
        else => return,
    };

    obs.blog(log_level, "%s", msg.ptr);
}
