// Copyright (c) 2026 T1ckbase
// SPDX-License-Identifier: GPL-3.0-or-later

const std = @import("std");
const manifest = @import("build.zig.zon");
const module = @import("obs_module.zig");
const obs = module.obs;
const aeshna = @import("aeshna.zig");

const Aeshna = aeshna.Aeshna;

fn aeshna_filter_get_name(_: ?*anyopaque) callconv(.c) [*c]const u8 {
    return "Aeshna";
}

fn aeshna_filter_create(setting: ?*obs.obs_data_t, context: ?*obs.obs_source_t) callconv(.c) ?*anyopaque {
    const filter = Aeshna.create(context.?) orelse {
        module.log.err("Failed to create Aeshna filter", .{});
        return null;
    };

    aeshna_filter_update(filter, setting);
    return filter;
}

fn aeshna_filter_destroy(data: ?*anyopaque) callconv(.c) void {
    const filter: *Aeshna = @ptrCast(@alignCast(data orelse return));

    filter.destroy();
}

fn aeshna_filter_update(data: ?*anyopaque, settings: ?*obs.obs_data_t) callconv(.c) void {
    const filter: *Aeshna = @ptrCast(@alignCast(data orelse return));

    filter.update(settings orelse return);
}

fn aeshna_filter_defaults(settings: ?*obs.obs_data_t) callconv(.c) void {
    Aeshna.defaults(settings orelse return);
}

fn aeshna_filter_properties(_: ?*anyopaque) callconv(.c) *obs.obs_properties_t {
    return Aeshna.properties();
}

fn aeshna_filter_tick(data: ?*anyopaque, _: f32) callconv(.c) void {
    const filter: *Aeshna = @ptrCast(@alignCast(data orelse return));

    filter.tick();
}

fn aeshna_filter_render(data: ?*anyopaque, _: ?*obs.gs_effect_t) callconv(.c) void {
    const filter: *Aeshna = @ptrCast(@alignCast(data orelse return));

    filter.render();
}

const aeshna_filter = obs.obs_source_info{
    .id = "aeshna_filter",
    .type = obs.OBS_SOURCE_TYPE_FILTER,
    .output_flags = obs.OBS_SOURCE_VIDEO | obs.OBS_SOURCE_DO_NOT_DUPLICATE,
    .get_name = aeshna_filter_get_name,
    .create = aeshna_filter_create,
    .destroy = aeshna_filter_destroy,
    .update = aeshna_filter_update,
    .get_defaults = aeshna_filter_defaults,
    .get_properties = aeshna_filter_properties,
    .video_tick = aeshna_filter_tick,
    .video_render = aeshna_filter_render,
};

export fn obs_module_load() bool {
    module.log.info("plugin loaded successfully (version {s})", .{manifest.version});

    obs.obs_register_source_s(&aeshna_filter, @sizeOf(obs.obs_source_info));
    return true;
}

export fn obs_module_unload() void {
    module.log.info("plugin unloaded", .{});
}
