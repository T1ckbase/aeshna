// Copyright (c) 2026 T1ckbase
// SPDX-License-Identifier: GPL-3.0-or-later

const std = @import("std");

const obs = @import("obs");

const utils = @import("utils.zig");

const KeyStroke = @import("./KeyStroke.zig");
const KeyPress = @import("KeyPress.zig");

const Aeshna = @This();

mask_color: u24,
key_stroke: KeyStroke,
capture_width: u32,
capture_height: u32,
cursor_hidden_only: bool,
// capture_offset_x: i32,
// capture_offset_y: i32,

context: *obs.obs_source_t,
hold_hotkey: obs.obs_hotkey_id,
is_active: std.atomic.Value(bool),

texrender: *obs.gs_texrender_t,
stagesurface: ?*obs.gs_stagesurf_t,
stage_width: u32,
stage_height: u32,

pub fn create(context: *obs.obs_source_t) ?*Aeshna {
    const ptr = obs.bzalloc(@sizeOf(Aeshna)).?;
    const filter: *Aeshna = @ptrCast(@alignCast(ptr));

    obs.obs_enter_graphics();
    defer obs.obs_leave_graphics();

    const texrender = obs.gs_texrender_create(obs.GS_BGRA, obs.GS_ZS_NONE) orelse {
        obs.bfree(ptr);
        std.log.err("failed to create render texrender", .{});
        return null;
    };

    filter.* = .{
        .mask_color = 0x000000,
        .key_stroke = .init(@intCast(obs.OBS_KEY_SPACE), null, null),
        .capture_width = 12,
        .capture_height = 12,
        .cursor_hidden_only = true,
        // .capture_offset_x = 0,
        // .capture_offset_y = 0,

        .context = context,
        .hold_hotkey = obs.OBS_INVALID_HOTKEY_ID,
        .is_active = .init(false),

        .texrender = texrender,
        .stagesurface = null,
        .stage_width = 0,
        .stage_height = 0,
    };

    return filter;
}

pub fn update(self: *Aeshna, settings: *obs.obs_data_t) void {
    const mask_bits: u64 = @bitCast(obs.obs_data_get_int(settings, "mask_color"));
    self.mask_color = @truncate(mask_bits & 0x00ffffff);

    const hold_duration_ms_raw = obs.obs_data_get_int(settings, "hold_duration_ms");
    const throttle_raw = obs.obs_data_get_int(settings, "throttle_ms");
    const width_raw = obs.obs_data_get_int(settings, "capture_width");
    const height_raw = obs.obs_data_get_int(settings, "capture_height");
    // const capture_offset_x = obs.obs_data_get_int(settings, "capture_offset_x");
    // const capture_offset_y = obs.obs_data_get_int(settings, "capture_offset_y");

    self.key_stroke.key = keyFromRaw(obs.obs_data_get_int(settings, "send_key")) orelse @intCast(obs.OBS_KEY_SPACE);
    self.key_stroke.hold_duration_ms = @intCast(std.math.clamp(hold_duration_ms_raw, 0, 1000));
    self.key_stroke.throttle_ms = @intCast(std.math.clamp(throttle_raw, 0, 1000));
    self.capture_width = @intCast(std.math.clamp(width_raw, 2, 2048));
    self.capture_height = @intCast(std.math.clamp(height_raw, 2, 2048));
    self.cursor_hidden_only = obs.obs_data_get_bool(settings, "cursor_hidden_only");
    // self.capture_offset_x = @intCast(std.math.clamp(capture_offset_x, -2048, 2048));
    // self.capture_offset_y = @intCast(std.math.clamp(capture_offset_y, -2048, 2048));
}

pub fn destroy(self: *Aeshna) void {
    self.key_stroke.release();

    obs.obs_enter_graphics();

    if (self.stagesurface) |stagesurface| {
        obs.gs_stagesurface_destroy(stagesurface);
    }
    obs.gs_texrender_destroy(self.texrender);

    obs.obs_leave_graphics();

    obs.bfree(self);
}

pub fn defaults(settings: *obs.obs_data_t) void {
    obs.obs_data_set_default_int(settings, "mask_color", 0x000000);
    obs.obs_data_set_default_int(settings, "send_key", @intCast(obs.OBS_KEY_SPACE));
    obs.obs_data_set_default_int(settings, "hold_duration_ms", 25);
    obs.obs_data_set_default_int(settings, "throttle_ms", 200);
    obs.obs_data_set_default_int(settings, "capture_width", 12);
    obs.obs_data_set_default_int(settings, "capture_height", 12);
    obs.obs_data_set_default_bool(settings, "cursor_hidden_only", true);
    // obs.obs_data_set_default_int(settings, "capture_offset_x", 0);
    // obs.obs_data_set_default_int(settings, "capture_offset_y", 0);
}

pub fn properties() ?*obs.obs_properties_t {
    const props = obs.obs_properties_create() orelse return null;

    _ = obs.obs_properties_add_color(props, "mask_color", "Mask color");
    const send_key = obs.obs_properties_add_list(
        props,
        "send_key",
        "Send key",
        obs.OBS_COMBO_TYPE_LIST,
        obs.OBS_COMBO_FORMAT_INT,
    ) orelse {
        obs.obs_properties_destroy(props);
        return null;
    };
    addSupportedKeys(send_key);
    _ = obs.obs_properties_add_int_slider(props, "hold_duration_ms", "Hold duration (ms)", 0, 1000, 1);
    _ = obs.obs_properties_add_int_slider(props, "throttle_ms", "Throttle (ms)", 0, 1000, 1);
    _ = obs.obs_properties_add_int_slider(props, "capture_width", "Capture width", 2, 2048, 1);
    _ = obs.obs_properties_add_int_slider(props, "capture_height", "Capture height", 2, 2048, 1);
    _ = obs.obs_properties_add_bool(props, "cursor_hidden_only", "Cursor hidden only");
    // _ = obs.obs_properties_add_int_slider(props, "capture_offset_x", "Capture offset x", -2048, 2048, 1);
    // _ = obs.obs_properties_add_int_slider(props, "capture_offset_y", "Capture offset y", -2048, 2048, 1);

    return props;
}

fn keyFromRaw(raw: c_longlong) ?obs.obs_key_t {
    if (raw < 0 or raw >= @as(c_longlong, obs.OBS_KEY_LAST_VALUE)) return null;

    const key: obs.obs_key_t = @intCast(raw);
    return if (KeyPress.isSupported(key)) key else null;
}

fn addSupportedKeys(property: *obs.obs_property_t) void {
    const last_key: obs.obs_key_t = @intCast(obs.OBS_KEY_LAST_VALUE);

    for (0..last_key) |i| {
        const key: obs.obs_key_t = @intCast(i);

        if (!KeyPress.isSupported(key)) continue;

        var label: obs.struct_dstr = .{};
        obs.obs_key_to_str(key, &label);
        defer obs.dstr_free(&label);

        if (label.len == 0) continue;
        _ = obs.obs_property_list_add_int(property, label.array, @intCast(key));
    }
}

pub fn tick(self: *Aeshna) void {
    self.key_stroke.poll(obs.os_gettime_ns());
}

pub fn render(self: *Aeshna) void {
    obs.obs_source_skip_video_filter(self.context);

    const found = self.capture() orelse {
        std.log.debug("capture skipped", .{});
        return;
    };

    if (found) {
        self.key_stroke.trigger(obs.os_gettime_ns());
    }
}

pub fn add(self: *Aeshna, parent: *obs.obs_source_t) void {
    self.hold_hotkey = obs.obs_hotkey_register_source(parent, "Aeshna.Hold", "Aeshna: Triggerbot (Hold)", holdHotkey, self);
    if (self.hold_hotkey == obs.OBS_INVALID_HOTKEY_ID) {
        std.log.err("hotkey registration failed", .{});
        return;
    }
}

fn holdHotkey(data: ?*anyopaque, _: obs.obs_hotkey_id, _: ?*obs.obs_hotkey_t, pressed: bool) callconv(.c) void {
    const self: *Aeshna = @ptrCast(@alignCast(data.?));
    self.is_active.store(pressed, .monotonic);
}

fn ensureStageSurface(self: *Aeshna, source_width: u32, source_height: u32) bool {
    if (self.stagesurface != null and self.stage_width == source_width and self.stage_height == source_height) {
        return true;
    }

    if (self.stagesurface) |stagesurface| {
        obs.gs_stagesurface_destroy(stagesurface);
        self.stagesurface = null;
    }

    self.stagesurface = obs.gs_stagesurface_create(source_width, source_height, obs.GS_BGRA) orelse {
        std.log.err("failed to create stage surface for {}x{}", .{ source_width, source_height });
        self.stage_width = 0;
        self.stage_height = 0;
        return false;
    };

    self.stage_width = source_width;
    self.stage_height = source_height;
    return true;
}

fn capture(self: *Aeshna) ?bool {
    const target = obs.obs_filter_get_target(self.context) orelse return null;
    _ = obs.obs_filter_get_parent(self.context) orelse return null;

    if (self.cursor_hidden_only and utils.isCursorShowing() catch return null) return null;

    if (!self.is_active.load(.monotonic)) return null;

    const source_width = obs.obs_source_get_base_width(target);
    const source_height = obs.obs_source_get_base_height(target);
    if (source_width == 0 or source_height == 0) return null;

    if (self.capture_width > source_width or self.capture_height > source_height) return null;

    const start_x = (source_width - self.capture_width) / 2;
    const start_y = (source_height - self.capture_height) / 2;

    obs.gs_texrender_reset(self.texrender);
    if (!obs.gs_texrender_begin(self.texrender, self.capture_width, self.capture_height)) return null;

    var clear_color: obs.vec4 = undefined;
    obs.vec4_zero(&clear_color);
    obs.gs_clear(obs.GS_CLEAR_COLOR, &clear_color, 0.0, 0);
    obs.gs_ortho(
        @floatFromInt(start_x),
        @floatFromInt(start_x + self.capture_width),
        @floatFromInt(start_y),
        @floatFromInt(start_y + self.capture_height),
        -100.0,
        100.0,
    );

    obs.gs_blend_state_push();
    obs.gs_blend_function(obs.GS_BLEND_ONE, obs.GS_BLEND_ZERO);

    obs.obs_source_video_render(target);

    obs.gs_blend_state_pop();
    obs.gs_texrender_end(self.texrender);

    if (!self.ensureStageSurface(self.capture_width, self.capture_height)) return null;

    obs.gs_stage_texture(self.stagesurface.?, obs.gs_texrender_get_texture(self.texrender));

    var data: [*c]u8 = null;
    var linesize: u32 = 0;

    if (!obs.gs_stagesurface_map(self.stagesurface.?, &data, &linesize)) return null;
    defer obs.gs_stagesurface_unmap(self.stagesurface.?);

    const b: u8 = @truncate((self.mask_color >> 16) & 0xFF);
    const g: u8 = @truncate((self.mask_color >> 8) & 0xFF);
    const r: u8 = @truncate(self.mask_color & 0xFF);

    for (0..self.capture_height) |y| {
        const row = data + y * linesize;
        for (0..self.capture_width) |x| {
            const px = row + x * 4;
            // if (px[0] == b and px[1] == g and px[2] == r) return true; // test
            if (px[0] != b or px[1] != g or px[2] != r) return true;
        }
    }
    return false;
}
