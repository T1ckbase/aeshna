// Copyright (c) 2026 T1ckbase
// SPDX-License-Identifier: GPL-3.0-or-later

const std = @import("std");

const consts = @import("consts.zig");

pub const obs = @cImport({
    @cInclude("obs-module.h");
    @cInclude("util/base.h");
    @cInclude("util/platform.h");
});

pub const log = struct {
    pub fn info(comptime fmt: []const u8, args: anytype) void {
        logImpl(obs.LOG_INFO, fmt, args);
    }
    pub fn warn(comptime fmt: []const u8, args: anytype) void {
        logImpl(obs.LOG_WARNING, fmt, args);
    }
    pub fn err(comptime fmt: []const u8, args: anytype) void {
        logImpl(obs.LOG_ERROR, fmt, args);
    }
    pub fn debug(comptime fmt: []const u8, args: anytype) void {
        logImpl(obs.LOG_DEBUG, fmt, args);
    }

    fn logImpl(comptime level: c_int, comptime fmt: []const u8, args: anytype) void {
        var buf: [8192]u8 = undefined;

        var fbs = std.io.fixedBufferStream(buf[0 .. buf.len - 1]);
        fbs.writer().print("[" ++ consts.plugin_name ++ "] " ++ fmt, args) catch |e| switch (e) {
            error.NoSpaceLeft => {},
            else => return,
        };

        const written = fbs.getWritten();
        buf[written.len] = 0;
        const msg = buf[0..written.len :0];
        obs.blog(level, "%s", msg.ptr);
    }
};

var obs_module_pointer: ?*obs.obs_module_t = null;

export fn obs_module_set_pointer(module: ?*obs.obs_module_t) void {
    obs_module_pointer = module;
}

fn obs_current_module() ?*obs.obs_module_t {
    return obs_module_pointer;
}

export fn obs_module_ver() u32 {
    return obs.LIBOBS_API_VER;
}

var obs_module_lookup: ?*obs.lookup_t = null;

pub fn text(val: [*c]const u8) [*c]const u8 {
    var out: [*c]const u8 = val;
    _ = obs.text_lookup_getstr(obs_module_lookup, val, &out);
    return out;
}

export fn obs_module_get_string(val: [*c]const u8, out: [*c][*c]const u8) bool {
    return obs.text_lookup_getstr(obs_module_lookup, val, out);
}

export fn obs_module_set_locale(locale: [*:0]const u8) void {
    if (obs_module_lookup != null) {
        obs.text_lookup_destroy(obs_module_lookup);
    }

    obs_module_lookup = obs.obs_module_load_locale(obs_current_module(), consts.default_locale, locale);
}

export fn obs_module_free_locale() void {
    obs.text_lookup_destroy(obs_module_lookup);
    obs_module_lookup = null;
}
