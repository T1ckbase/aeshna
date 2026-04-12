// Copyright (c) 2026 T1ckbase
// SPDX-License-Identifier: GPL-3.0-or-later

const std = @import("std");
const module = @import("obs_module.zig");
const obs = module.obs;
const utils = @import("utils.zig");

pub const Aeshna = struct {
    const Self = @This();

    mask_color: u24,
    virtual_key_code: u16,
    throttle_ms: u32,
    click_hold_ms: u32,
    capture_width: u32,
    capture_height: u32,
    // capture_offset_x: i32,
    // capture_offset_y: i32,

    context: *obs.obs_source_t,
    activate_hotkey_id: obs.obs_hotkey_id,
    hotkeys_loaded: bool,
    is_active: std.atomic.Value(bool),
    last_trigger_at_ns: u64,
    is_pressing: bool,
    release_at_ns: u64,

    texrender: *obs.gs_texrender_t,
    stagesurface: ?*obs.gs_stagesurf_t,
    stage_width: u32,
    stage_height: u32,

    pub fn create(context: *obs.obs_source_t) ?*Self {
        const ptr = obs.bzalloc(@sizeOf(Self)).?;
        const filter: *Self = @ptrCast(@alignCast(ptr));

        obs.obs_enter_graphics();
        defer obs.obs_leave_graphics();

        const texrender = obs.gs_texrender_create(obs.GS_BGRA, obs.GS_ZS_NONE) orelse {
            obs.bfree(ptr);
            module.log.err("failed to create render texrender", .{});
            return null;
        };

        filter.* = .{
            .mask_color = 0x000000,
            .virtual_key_code = utils.VK_SPACE,
            .throttle_ms = 200,
            .click_hold_ms = 25,
            .capture_width = 12,
            .capture_height = 12,
            // .capture_offset_x = 0,
            // .capture_offset_y = 0,

            .context = context,
            .activate_hotkey_id = obs.OBS_INVALID_HOTKEY_ID,
            .hotkeys_loaded = false,
            .is_active = std.atomic.Value(bool).init(false),
            .last_trigger_at_ns = 0,
            .is_pressing = false,
            .release_at_ns = 0,

            .texrender = texrender,
            .stagesurface = null,
            .stage_width = 0,
            .stage_height = 0,
        };

        return filter;
    }

    pub fn update(self: *Self, settings: *obs.obs_data_t) void {
        const mask_bits: u64 = @bitCast(obs.obs_data_get_int(settings, "mask_color"));
        self.mask_color = @truncate(mask_bits & 0x00ffffff);

        const virtual_key_raw = obs.obs_data_get_int(settings, "virtual_key_code");
        const throttle_raw = obs.obs_data_get_int(settings, "throttle_ms");
        const click_hold_raw = obs.obs_data_get_int(settings, "click_hold_ms");
        const width_raw = obs.obs_data_get_int(settings, "capture_width");
        const height_raw = obs.obs_data_get_int(settings, "capture_height");
        // const capture_offset_x = obs.obs_data_get_int(settings, "capture_offset_x");
        // const capture_offset_y = obs.obs_data_get_int(settings, "capture_offset_y");

        self.virtual_key_code = @intCast(std.math.clamp(virtual_key_raw, 1, 254));
        self.throttle_ms = @intCast(std.math.clamp(throttle_raw, 0, 1000));
        self.click_hold_ms = @intCast(std.math.clamp(click_hold_raw, 0, 1000));
        self.capture_width = @intCast(std.math.clamp(width_raw, 2, 2048));
        self.capture_height = @intCast(std.math.clamp(height_raw, 2, 2048));
        // self.capture_offset_x = @intCast(std.math.clamp(capture_offset_x, -2048, 2048));
        // self.capture_offset_y = @intCast(std.math.clamp(capture_offset_y, -2048, 2048));
    }

    pub fn destroy(self: *Self) void {
        if (self.activate_hotkey_id != obs.OBS_INVALID_HOTKEY_ID) {
            obs.obs_hotkey_unregister(self.activate_hotkey_id);
        }

        if (self.is_pressing) {
            utils.release(self.virtual_key_code);
            self.is_pressing = false;
            self.release_at_ns = 0;
        }

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
        obs.obs_data_set_default_int(settings, "virtual_key_code", utils.VK_SPACE);
        obs.obs_data_set_default_int(settings, "throttle_ms", 200);
        obs.obs_data_set_default_int(settings, "click_hold_ms", 25);
        obs.obs_data_set_default_int(settings, "capture_width", 12);
        obs.obs_data_set_default_int(settings, "capture_height", 12);
        // obs.obs_data_set_default_int(settings, "capture_offset_x", 0);
        // obs.obs_data_set_default_int(settings, "capture_offset_y", 0);
    }

    pub fn properties() *obs.obs_properties_t {
        const props = obs.obs_properties_create() orelse unreachable;

        _ = obs.obs_properties_add_color(props, "mask_color", "Mask color");
        _ = obs.obs_properties_add_int(props, "virtual_key_code", "Virtual-Key Code", 1, 254, 1);
        _ = obs.obs_properties_add_int_slider(props, "throttle_ms", "Throttle (ms)", 0, 1000, 1);
        _ = obs.obs_properties_add_int_slider(props, "click_hold_ms", "Click hold (ms)", 0, 1000, 1);
        _ = obs.obs_properties_add_int_slider(props, "capture_width", "Capture width", 2, 2048, 1);
        _ = obs.obs_properties_add_int_slider(props, "capture_height", "Capture height", 2, 2048, 1);
        // _ = obs.obs_properties_add_int_slider(props, "capture_offset_x", "Capture offset x", -2048, 2048, 1);
        // _ = obs.obs_properties_add_int_slider(props, "capture_offset_y", "Capture offset y", -2048, 2048, 1);

        return props;
    }

    pub fn tick(self: *Self) void {
        self.tryRegisterHotkeys();
        self.processPendingRelease();
    }

    pub fn render(self: *Self) void {
        obs.obs_source_skip_video_filter(self.context);

        const found = self.capture2() orelse {
            // module.log.warn("capture skipped", .{});
            return;
        };

        if (found) {
            self.tryPress();
        }
    }

    fn tryPress(self: *Self) void {
        const now: u64 = @intCast(obs.os_gettime_ns());

        if (self.is_pressing) return;

        const throttle_ns = @as(u64, self.throttle_ms) * std.time.ns_per_ms;
        if (throttle_ns != 0 and self.last_trigger_at_ns != 0 and now - self.last_trigger_at_ns < throttle_ns) {
            return;
        }

        utils.press(self.virtual_key_code);

        self.last_trigger_at_ns = now;
        self.is_pressing = true;
        self.release_at_ns = now + @as(u64, self.click_hold_ms) * std.time.ns_per_ms;

        if (self.click_hold_ms == 0) {
            utils.release(self.virtual_key_code);
            self.is_pressing = false;
            self.release_at_ns = 0;
        }
    }

    fn processPendingRelease(self: *Self) void {
        if (!self.is_pressing) return;

        const now: u64 = @intCast(obs.os_gettime_ns());
        if (now < self.release_at_ns) return;

        utils.release(self.virtual_key_code);
        self.is_pressing = false;
        self.release_at_ns = 0;
    }

    fn activateHotkeyHandler(data: ?*anyopaque, _: obs.obs_hotkey_id, _: ?*obs.obs_hotkey_t, pressed: bool) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(data orelse return));
        self.is_active.store(pressed, .monotonic);
    }

    fn tryRegisterHotkeys(self: *Self) void {
        if (self.hotkeys_loaded) return;

        const parent = obs.obs_filter_get_parent(self.context) orelse return;

        const activate_hotkey_id = obs.obs_hotkey_register_source(parent, "Aeshna.Activate", "Aeshna: Triggerbot (Hold)", activateHotkeyHandler, self);
        if (activate_hotkey_id == obs.OBS_INVALID_HOTKEY_ID) {
            module.log.err("hotkey registration failed", .{});
            return;
        }

        self.activate_hotkey_id = activate_hotkey_id;
        self.hotkeys_loaded = true;
    }

    fn ensureStageSurface(self: *Self, source_width: u32, source_height: u32) bool {
        if (self.stagesurface != null and self.stage_width == source_width and self.stage_height == source_height) {
            return true;
        }

        if (self.stagesurface) |stagesurface| {
            obs.gs_stagesurface_destroy(stagesurface);
            self.stagesurface = null;
        }

        self.stagesurface = obs.gs_stagesurface_create(source_width, source_height, obs.GS_BGRA) orelse {
            module.log.err("failed to create stage surface for {}x{}", .{ source_width, source_height });
            self.stage_width = 0;
            self.stage_height = 0;
            return false;
        };

        self.stage_width = source_width;
        self.stage_height = source_height;
        return true;
    }

    fn capture(self: *Self) ?bool {
        const target = obs.obs_filter_get_target(self.context) orelse return null;
        _ = obs.obs_filter_get_parent(self.context) orelse return null;

        if (!self.is_active.load(.monotonic)) return null;

        // check if the cursor is showing

        const source_width = obs.obs_source_get_base_width(target);
        const source_height = obs.obs_source_get_base_height(target);
        if (source_width == 0 or source_height == 0) return null;

        if (self.capture_width > source_width or self.capture_height > source_height) return null;

        obs.gs_texrender_reset(self.texrender);
        if (!obs.gs_texrender_begin(self.texrender, source_width, source_height)) return null;

        var clear_color: obs.vec4 = undefined;
        obs.vec4_zero(&clear_color);
        obs.gs_clear(obs.GS_CLEAR_COLOR, &clear_color, 0.0, 0);
        obs.gs_ortho(0.0, @floatFromInt(source_width), 0.0, @floatFromInt(source_height), -100.0, 100.0);

        obs.gs_blend_state_push();
        obs.gs_blend_function(obs.GS_BLEND_ONE, obs.GS_BLEND_ZERO);

        obs.obs_source_video_render(target);

        obs.gs_blend_state_pop();
        obs.gs_texrender_end(self.texrender);

        if (!self.ensureStageSurface(source_width, source_height)) return null;

        obs.gs_stage_texture(self.stagesurface.?, obs.gs_texrender_get_texture(self.texrender));

        var data: [*c]u8 = null;
        var linesize: u32 = 0;

        if (!obs.gs_stagesurface_map(self.stagesurface.?, &data, &linesize)) return null;
        defer obs.gs_stagesurface_unmap(self.stagesurface.?);

        // ignore offsets for now
        const start_x = (source_width - self.capture_width) / 2;
        const start_y = (source_height - self.capture_height) / 2;
        for (start_y..start_y + self.capture_height) |y| {
            const row = data + y * linesize;
            for (start_x..start_x + self.capture_width) |x| {
                const px = row + x * 4;
                const color = (@as(u24, px[0]) << 16) | (@as(u24, px[1]) << 8) | (@as(u24, px[2])); // BGR
                if (color == self.mask_color) return true;
            }
        }
        return false;
    }

    fn capture2(self: *Self) ?bool {
        const target = obs.obs_filter_get_target(self.context) orelse return null;
        _ = obs.obs_filter_get_parent(self.context) orelse return null;

        if (utils.isCursorShowing() catch return null) return null;

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
};
