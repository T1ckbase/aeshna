// Copyright (c) 2026 T1ckbase
// SPDX-License-Identifier: GPL-3.0-or-later

const std = @import("std");
const builtin = @import("builtin");

const manifest = @import("build.zig.zon");
const obs = @import("obs");

const aeshna_filter = @import("aeshna_filter.zig").aeshna_filter;

pub const std_options: std.Options = .{
    .log_level = if (builtin.mode == .Debug) .debug else .info,
    .logFn = @import("./logging.zig").logFn,
};

const default_locale = "en-US";

var obs_module_pointer: ?*obs.obs_module_t = null;

export fn obs_module_set_pointer(module: ?*obs.obs_module_t) void {
    obs_module_pointer = module;
}

pub fn obsCurrentModule() ?*obs.obs_module_t {
    return obs_module_pointer;
}

export fn obs_module_ver() u32 {
    return obs.LIBOBS_API_VER;
}

var obs_module_lookup: ?*obs.lookup_t = null;

pub fn obsModuleText(val: [*:0]const u8) [*c]const u8 {
    var out: [*c]const u8 = val;
    _ = obs.text_lookup_getstr(obs_module_lookup, val, &out);
    return out;
}

export fn obs_module_get_string(val: [*c]const u8, out: [*c][*c]const u8) bool {
    return obs.text_lookup_getstr(obs_module_lookup, val, out);
}

export fn obs_module_set_locale(locale: [*c]const u8) void {
    if (obs_module_lookup != null)
        obs.text_lookup_destroy(obs_module_lookup);

    obs_module_lookup = obs.obs_module_load_locale(obsCurrentModule(), default_locale, locale);
}

export fn obs_module_free_locale() void {
    obs.text_lookup_destroy(obs_module_lookup);
    obs_module_lookup = null;
}

export fn obs_module_load() bool {
    std.log.info("plugin loaded successfully (version {s})", .{manifest.version});
    std.log.info("obs version: '{s}'", .{obs.obs_get_version_string()});

    obs.obs_register_source_s(&aeshna_filter, @sizeOf(obs.obs_source_info));
    return true;
}

export fn obs_module_unload() void {
    std.log.info("plugin unloaded", .{});
}

export fn obs_module_author() [*:0]const u8 {
    return "T1ckbase";
}

export fn obs_module_name() [*:0]const u8 {
    return @tagName(manifest.name);
}
