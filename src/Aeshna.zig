// Copyright (c) 2026 T1ckbase
// SPDX-License-Identifier: GPL-3.0-or-later

const std = @import("std");

const obs = @import("obs");

const utils = @import("utils.zig");

const KeyStroke = @import("./KeyStroke.zig");
const KeyPress = @import("KeyPress.zig");
const Scan = @import("Scan.zig");

const Aeshna = @This();

mask_color: u24,
key_stroke: KeyStroke,
scan_width: u32,
scan_height: u32,
cursor_hidden_only: bool,
// capture_offset_x: i32,
// capture_offset_y: i32,

context: *obs.obs_source_t,
hold_hotkey: obs.obs_hotkey_id,
is_active: std.atomic.Value(bool),

scan: Scan,

pub fn create(context: *obs.obs_source_t) *Aeshna {
    const ptr = obs.bzalloc(@sizeOf(Aeshna)).?;
    const filter: *Aeshna = @ptrCast(@alignCast(ptr));

    filter.* = .{
        .mask_color = 0x000000,
        .key_stroke = .init(@intCast(obs.OBS_KEY_SPACE), null, null),
        .scan_width = 12,
        .scan_height = 12,
        .cursor_hidden_only = true,
        // .capture_offset_x = 0,
        // .capture_offset_y = 0,

        .context = context,
        .hold_hotkey = obs.OBS_INVALID_HOTKEY_ID,
        .is_active = .init(false),

        .scan = Scan.init(),
    };

    return filter;
}

pub fn update(self: *Aeshna, settings: *obs.obs_data_t) void {
    const mask_bits: u64 = @bitCast(obs.obs_data_get_int(settings, "mask_color"));
    const r: u8 = @truncate(mask_bits);
    const g: u8 = @truncate(mask_bits >> 8);
    const b: u8 = @truncate(mask_bits >> 16);
    self.mask_color = (@as(u24, r) << 16) | (@as(u24, g) << 8) | @as(u24, b); // 0xRRGGBB

    const hold_duration_ms_raw = obs.obs_data_get_int(settings, "hold_duration_ms");
    const throttle_raw = obs.obs_data_get_int(settings, "throttle_ms");
    const width_raw = obs.obs_data_get_int(settings, "scan_width");
    const height_raw = obs.obs_data_get_int(settings, "scan_height");
    // const capture_offset_x = obs.obs_data_get_int(settings, "capture_offset_x");
    // const capture_offset_y = obs.obs_data_get_int(settings, "capture_offset_y");

    self.key_stroke.key = keyFromRaw(obs.obs_data_get_int(settings, "send_key")) orelse @intCast(obs.OBS_KEY_SPACE);
    self.key_stroke.hold_duration_ms = @intCast(std.math.clamp(hold_duration_ms_raw, 0, 1000));
    self.key_stroke.throttle_ms = @intCast(std.math.clamp(throttle_raw, 0, 1000));
    self.scan_width = @intCast(std.math.clamp(width_raw, 1, 128));
    self.scan_height = @intCast(std.math.clamp(height_raw, 1, 128));
    self.cursor_hidden_only = obs.obs_data_get_bool(settings, "cursor_hidden_only");
    // self.capture_offset_x = @intCast(std.math.clamp(capture_offset_x, -2048, 2048));
    // self.capture_offset_y = @intCast(std.math.clamp(capture_offset_y, -2048, 2048));
}

pub fn destroy(self: *Aeshna) void {
    self.key_stroke.release();
    self.scan.deinit();
    obs.bfree(self);
    self.* = undefined;
}

pub fn defaults(settings: *obs.obs_data_t) void {
    obs.obs_data_set_default_int(settings, "mask_color", 0x000000);
    obs.obs_data_set_default_int(settings, "send_key", @intCast(obs.OBS_KEY_SPACE));
    obs.obs_data_set_default_int(settings, "hold_duration_ms", 25);
    obs.obs_data_set_default_int(settings, "throttle_ms", 200);
    obs.obs_data_set_default_int(settings, "scan_width", 12);
    obs.obs_data_set_default_int(settings, "scan_height", 12);
    obs.obs_data_set_default_bool(settings, "cursor_hidden_only", true);
    // obs.obs_data_set_default_int(settings, "capture_offset_x", 0);
    // obs.obs_data_set_default_int(settings, "capture_offset_y", 0);
}

pub fn properties() ?*obs.obs_properties_t {
    const props = obs.obs_properties_create().?;

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
    _ = obs.obs_properties_add_int_slider(props, "scan_width", "Scan width", 1, 128, 1);
    _ = obs.obs_properties_add_int_slider(props, "scan_height", "Scan height", 1, 128, 1);
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

pub fn render(self: *Aeshna) !void {
    obs.obs_source_skip_video_filter(self.context);

    const target = obs.obs_filter_get_target(self.context) orelse return;
    _ = obs.obs_filter_get_parent(self.context) orelse return;

    if (self.cursor_hidden_only and utils.isCursorShowing() catch return) return;

    if (!self.is_active.load(.monotonic)) return;

    const source_width = obs.obs_source_get_base_width(target);
    const source_height = obs.obs_source_get_base_height(target);
    if (source_width == 0 or source_height == 0) return;

    if (self.scan_width > source_width or self.scan_height > source_height) return;

    const x = (source_width - self.scan_width) / 2;
    const y = (source_height - self.scan_height) / 2;

    const found = try self.scan.scan(target, x, y, self.scan_width, self.scan_height, self.mask_color);

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
