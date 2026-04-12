const std = @import("std");
const module = @import("obs_module.zig");
const obs = module.obs;
const utils = @import("utils.zig");
const manifest = @import("build.zig.zon");

const Setting = struct {
    pub const ENABLED = "enabled";
    pub const MASK_COLOR = "mask_color";
    pub const THROTTLE_MS = "throttle_ms";
    pub const OFFSET_ENABLED = "offset_enabled";
    pub const OFFSET_X = "offset_x";
    pub const OFFSET_Y = "offset_y";
    pub const CAPTURE_WIDTH = "capture_width";
    pub const CAPTURE_HEIGHT = "capture_height";
};

const bgra_bytes_per_pixel: usize = 4;
const capture_allocator = std.heap.page_allocator;

const CaptureRect = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
};

const AeshnaConfig = struct {
    enabled: bool,
    mask_color: c_longlong,
    throttle_ms: u32,
    offset_enabled: bool,
    offset_x: i32,
    offset_y: i32,
    capture_width: u32,
    capture_height: u32,

    fn init() AeshnaConfig {
        return .{
            .enabled = true,
            .mask_color = 0x0,
            .throttle_ms = 100,
            .offset_enabled = false,
            .offset_x = 0,
            .offset_y = 0,
            .capture_width = 6,
            .capture_height = 6,
        };
    }

    fn load(self: *AeshnaConfig, settings: *obs.obs_data_t) void {
        self.enabled = obs.obs_data_get_bool(settings, Setting.ENABLED);
        self.mask_color = obs.obs_data_get_int(settings, Setting.MASK_COLOR);

        const throttle_value = obs.obs_data_get_int(settings, Setting.THROTTLE_MS);
        self.throttle_ms = @intCast(if (throttle_value > 0) throttle_value else 0);

        self.offset_enabled = obs.obs_data_get_bool(settings, Setting.OFFSET_ENABLED);
        self.offset_x = @intCast(obs.obs_data_get_int(settings, Setting.OFFSET_X));
        self.offset_y = @intCast(obs.obs_data_get_int(settings, Setting.OFFSET_Y));

        const requested_width = obs.obs_data_get_int(settings, Setting.CAPTURE_WIDTH);
        const requested_height = obs.obs_data_get_int(settings, Setting.CAPTURE_HEIGHT);
        self.capture_width = @intCast(if (requested_width > 0) requested_width else 1);
        self.capture_height = @intCast(if (requested_height > 0) requested_height else 1);
    }

    fn setDefaults(settings: *obs.obs_data_t) void {
        obs.obs_data_set_default_bool(settings, Setting.ENABLED, true);
        obs.obs_data_set_default_int(settings, Setting.MASK_COLOR, 0x0);
        obs.obs_data_set_default_int(settings, Setting.THROTTLE_MS, 100);
        obs.obs_data_set_default_bool(settings, Setting.OFFSET_ENABLED, false);
        obs.obs_data_set_default_int(settings, Setting.OFFSET_X, 0);
        obs.obs_data_set_default_int(settings, Setting.OFFSET_Y, 0);
        obs.obs_data_set_default_int(settings, Setting.CAPTURE_WIDTH, 6);
        obs.obs_data_set_default_int(settings, Setting.CAPTURE_HEIGHT, 6);
    }

    fn addProperties(props: *obs.obs_properties_t) void {
        _ = obs.obs_properties_add_bool(props, Setting.ENABLED, "Enabled");
        _ = obs.obs_properties_add_color(props, Setting.MASK_COLOR, "Mask color");
        _ = obs.obs_properties_add_int(props, Setting.THROTTLE_MS, "Throttle (ms)", 0, 1000, 1);
        _ = obs.obs_properties_add_bool(props, Setting.OFFSET_ENABLED, "Offset from center");
        _ = obs.obs_properties_add_int(props, Setting.OFFSET_X, "Offset X", -4096, 4096, 1);
        _ = obs.obs_properties_add_int(props, Setting.OFFSET_Y, "Offset Y", -4096, 4096, 1);
        _ = obs.obs_properties_add_int(props, Setting.CAPTURE_WIDTH, "Capture width", 1, 4096, 1);
        _ = obs.obs_properties_add_int(props, Setting.CAPTURE_HEIGHT, "Capture height", 1, 4096, 1);
    }

    fn getCaptureRect(self: *const AeshnaConfig, source_width: u32, source_height: u32) ?CaptureRect {
        if (source_width == 0 or source_height == 0) return null;

        const width = @min(self.capture_width, source_width);
        const height = @min(self.capture_height, source_height);
        if (width == 0 or height == 0) return null;

        const centered_x = (source_width - width) / 2;
        const centered_y = (source_height - height) / 2;

        return .{
            .x = if (self.offset_enabled)
                clampCaptureStart(centered_x, source_width - width, self.offset_x)
            else
                centered_x,
            .y = if (self.offset_enabled)
                clampCaptureStart(centered_y, source_height - height, self.offset_y)
            else
                centered_y,
            .width = width,
            .height = height,
        };
    }
};

const AeshnaRuntime = struct {
    last_trigger_at_ns: u64,
    hotkey_active: obs.obs_hotkey_id,
    hotkeys_loaded: bool,
    active: std.atomic.Value(bool),

    texrender: *obs.gs_texrender_t,
    stagesurface: ?*obs.gs_stagesurf_t,
    stage_width: u32,
    stage_height: u32,

    capture_buffer: std.ArrayListUnmanaged(u8),
    capture_stride: u32,
    captured_width: u32,
    captured_height: u32,

    fn init(texrender: *obs.gs_texrender_t) AeshnaRuntime {
        return .{
            .last_trigger_at_ns = 0,
            .hotkey_active = obs.OBS_INVALID_HOTKEY_ID,
            .hotkeys_loaded = false,
            .active = std.atomic.Value(bool).init(false),
            .texrender = texrender,
            .stagesurface = null,
            .stage_width = 0,
            .stage_height = 0,
            .capture_buffer = .{},
            .capture_stride = 0,
            .captured_width = 0,
            .captured_height = 0,
        };
    }

    fn ensureStageSurface(self: *AeshnaRuntime, source_width: u32, source_height: u32) bool {
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

    fn ensureCaptureBuffer(self: *AeshnaRuntime, capture_width: u32, capture_height: u32) bool {
        const capture_width_usize: usize = @intCast(capture_width);
        const capture_height_usize: usize = @intCast(capture_height);
        const stride = capture_width_usize * bgra_bytes_per_pixel;
        const total_bytes = stride * capture_height_usize;

        self.capture_buffer.resize(capture_allocator, total_bytes) catch {
            module.log.err("failed to resize capture buffer to {} bytes", .{total_bytes});
            return false;
        };

        self.capture_stride = @intCast(stride);
        self.captured_width = capture_width;
        self.captured_height = capture_height;
        return true;
    }

    fn destroyGraphics(self: *AeshnaRuntime) void {
        if (self.stagesurface) |stagesurface| {
            obs.gs_stagesurface_destroy(stagesurface);
            self.stagesurface = null;
        }

        obs.gs_texrender_destroy(self.texrender);
    }

    fn deinit(self: *AeshnaRuntime) void {
        self.capture_buffer.deinit(capture_allocator);
    }
};

const AeshnaFilterData = struct {
    context: *obs.obs_source_t,
    cfg: AeshnaConfig,
    rt: AeshnaRuntime,
};

fn clampCaptureStart(center_start: u32, max_start: u32, offset: i32) u32 {
    const center_start_i64: i64 = @intCast(center_start);
    const max_start_i64: i64 = @intCast(max_start);
    const offset_i64: i64 = @intCast(offset);
    const start = center_start_i64 + offset_i64;

    if (start <= 0) return 0;
    if (start >= max_start_i64) return max_start;

    return @intCast(start);
}

fn pixelMatchesMask(cfg: *const AeshnaConfig, pixel: []const u8) bool {
    const mask_color: u32 = @intCast(cfg.mask_color);
    const mask_r: u8 = @intCast(mask_color & 0xff);
    const mask_g: u8 = @intCast((mask_color >> 8) & 0xff);
    const mask_b: u8 = @intCast((mask_color >> 16) & 0xff);

    return pixel[0] == mask_b and pixel[1] == mask_g and pixel[2] == mask_r;
}

fn copyCaptureRegion(runtime: *AeshnaRuntime, capture_rect: CaptureRect, data: [*c]u8, linesize: u32) bool {
    if (!runtime.ensureCaptureBuffer(capture_rect.width, capture_rect.height)) return false;

    const mapped: [*]const u8 = @ptrCast(data);
    const source_stride: usize = @intCast(linesize);
    const capture_x: usize = @intCast(capture_rect.x);
    const capture_y: usize = @intCast(capture_rect.y);
    const capture_width: usize = @intCast(capture_rect.width);
    const capture_height: usize = @intCast(capture_rect.height);
    const row_bytes = capture_width * bgra_bytes_per_pixel;
    const dest_stride: usize = @intCast(runtime.capture_stride);

    var row: usize = 0;
    while (row < capture_height) : (row += 1) {
        const src_offset = ((capture_y + row) * source_stride) + (capture_x * bgra_bytes_per_pixel);
        const dst_offset = row * dest_stride;
        const src = mapped[src_offset .. src_offset + row_bytes];
        const dst = runtime.capture_buffer.items[dst_offset .. dst_offset + row_bytes];
        @memcpy(dst, src);
    }

    return true;
}

fn captureContainsTriggerColor(cfg: *const AeshnaConfig, runtime: *const AeshnaRuntime) bool {
    const stride: usize = @intCast(runtime.capture_stride);
    const width: usize = @intCast(runtime.captured_width);
    const height: usize = @intCast(runtime.captured_height);
    const row_bytes = width * bgra_bytes_per_pixel;

    var row: usize = 0;
    while (row < height) : (row += 1) {
        const row_start = row * stride;
        const pixels = runtime.capture_buffer.items[row_start .. row_start + row_bytes];

        var pixel_offset: usize = 0;
        while (pixel_offset < row_bytes) : (pixel_offset += bgra_bytes_per_pixel) {
            if (!pixelMatchesMask(cfg, pixels[pixel_offset .. pixel_offset + bgra_bytes_per_pixel])) {
                return true;
            }
        }
    }

    return false;
}

fn tryTrigger(filter: *AeshnaFilterData, found_trigger_pixel: bool) void {
    if (!found_trigger_pixel) return;

    const now: u64 = obs.os_gettime_ns();
    const throttle_ns = @as(u64, filter.cfg.throttle_ms) * std.time.ns_per_ms;
    if (throttle_ns != 0 and filter.rt.last_trigger_at_ns != 0 and now - filter.rt.last_trigger_at_ns < throttle_ns) {
        return;
    }

    filter.rt.last_trigger_at_ns = now;
    // TODO: synthesize the click/input event here.
}

fn renderTargetTexture(runtime: *AeshnaRuntime, target: *obs.obs_source_t, parent: *obs.obs_source_t, source_width: u32, source_height: u32) ?*obs.gs_texture_t {
    obs.gs_texrender_reset(runtime.texrender);

    obs.gs_blend_state_push();
    defer obs.gs_blend_state_pop();
    obs.gs_blend_function(obs.GS_BLEND_ONE, obs.GS_BLEND_ZERO);

    if (!obs.gs_texrender_begin(runtime.texrender, source_width, source_height)) return null;

    var clear_color: obs.vec4 = undefined;
    obs.vec4_zero(&clear_color);
    obs.gs_clear(obs.GS_CLEAR_COLOR, &clear_color, 0.0, 0);
    obs.gs_ortho(0.0, @floatFromInt(source_width), 0.0, @floatFromInt(source_height), -100.0, 100.0);

    const parent_flags = obs.obs_source_get_output_flags(parent);
    const custom_draw = (parent_flags & obs.OBS_SOURCE_CUSTOM_DRAW) != 0;
    const async = (parent_flags & obs.OBS_SOURCE_ASYNC) != 0;

    if (target == parent and !custom_draw and !async) {
        obs.obs_source_default_render(target);
    } else {
        obs.obs_source_video_render(target);
    }

    obs.gs_texrender_end(runtime.texrender);
    return obs.gs_texrender_get_texture(runtime.texrender);
}

fn drawPassThroughTexture(texture: *obs.gs_texture_t, effect: ?*obs.gs_effect_t, source_width: u32, source_height: u32) void {
    const draw_effect = effect orelse (obs.obs_get_base_effect(obs.OBS_EFFECT_DEFAULT) orelse return);
    const image = obs.gs_effect_get_param_by_name(draw_effect, "image") orelse return;
    const linear_srgb = obs.gs_get_linear_srgb();
    const previous_srgb = obs.gs_framebuffer_srgb_enabled();

    obs.gs_enable_framebuffer_srgb(linear_srgb);
    defer obs.gs_enable_framebuffer_srgb(previous_srgb);

    if (linear_srgb) {
        obs.gs_effect_set_texture_srgb(image, texture);
    } else {
        obs.gs_effect_set_texture(image, texture);
    }

    while (obs.gs_effect_loop(draw_effect, "Draw")) {
        obs.gs_draw_sprite(texture, 0, source_width, source_height);
    }
}

fn tryRegisterHotkeys(filter: *AeshnaFilterData) void {
    if (filter.rt.hotkeys_loaded) return;

    const parent = obs.obs_filter_get_parent(filter.context);
    if (parent == null) {
        module.log.info("parent not ready yet", .{});
        return;
    }

    const hotkey_id = obs.obs_hotkey_register_source(parent, "Aeshna.Activate", "Hold to Activate", hotkey_active, filter);
    if (hotkey_id == obs.OBS_INVALID_HOTKEY_ID) {
        module.log.err("hotkey registration failed", .{});
        return;
    }

    filter.rt.hotkey_active = hotkey_id;
    filter.rt.hotkeys_loaded = true;
}

fn hotkey_active(data: ?*anyopaque, _: obs.obs_hotkey_id, _: ?*obs.obs_hotkey_t, pressed: bool) callconv(.c) void {
    const ptr = data orelse return;
    const filter: *AeshnaFilterData = @ptrCast(@alignCast(ptr));

    filter.rt.active.store(pressed, .seq_cst);
    // module.log.info("Status: {s}", .{if (pressed) "down" else "up"});
}

fn aeshna_filter_get_name(_: ?*anyopaque) callconv(.c) [*c]const u8 {
    return "Aeshna";
}

fn aeshna_filter_create(setting: ?*obs.obs_data_t, context: ?*obs.obs_source_t) callconv(.c) ?*anyopaque {
    const ctx = context orelse return null;

    const ptr = obs.bzalloc(@sizeOf(AeshnaFilterData)) orelse {
        module.log.err("failed to allocate filter data", .{});
        return null;
    };

    const filter: *AeshnaFilterData = @ptrCast(@alignCast(ptr));

    obs.obs_enter_graphics();
    defer obs.obs_leave_graphics();

    const texrender = obs.gs_texrender_create(obs.GS_BGRA, obs.GS_ZS_NONE) orelse {
        obs.bfree(ptr);
        module.log.err("failed to create render texrender", .{});
        return null;
    };

    filter.* = .{
        .context = ctx,
        .cfg = AeshnaConfig.init(),
        .rt = AeshnaRuntime.init(texrender),
    };

    aeshna_filter_update(ptr, setting);
    return filter;
}

fn aeshna_filter_destroy(data: ?*anyopaque) callconv(.c) void {
    const ptr = data orelse return;
    const filter: *AeshnaFilterData = @ptrCast(@alignCast(ptr));

    if (filter.rt.hotkey_active != obs.OBS_INVALID_HOTKEY_ID) {
        obs.obs_hotkey_unregister(filter.rt.hotkey_active);
    }

    obs.obs_enter_graphics();
    filter.rt.destroyGraphics();
    obs.obs_leave_graphics();

    filter.rt.deinit();
    obs.bfree(ptr);
}

fn aeshna_filter_update(data: ?*anyopaque, settings: ?*obs.obs_data_t) callconv(.c) void {
    const ptr = data orelse return;
    const filter: *AeshnaFilterData = @ptrCast(@alignCast(ptr));
    const obs_settings = settings orelse return;

    filter.cfg.load(obs_settings);
}

fn aeshna_filter_defaults(settings: ?*obs.obs_data_t) callconv(.c) void {
    const obs_settings = settings orelse return;
    AeshnaConfig.setDefaults(obs_settings);
}

fn aeshna_filter_properties(_: ?*anyopaque) callconv(.c) *obs.obs_properties_t {
    const props = obs.obs_properties_create() orelse unreachable;
    AeshnaConfig.addProperties(props);
    return props;
}

fn aeshna_filter_render(data: ?*anyopaque, effect: ?*obs.gs_effect_t) callconv(.c) void {
    const ptr = data orelse return;
    const filter: *AeshnaFilterData = @ptrCast(@alignCast(ptr));

    const target: *obs.obs_source_t = obs.obs_filter_get_target(filter.context) orelse {
        obs.obs_source_skip_video_filter(filter.context);
        return;
    };
    const parent: *obs.obs_source_t = obs.obs_filter_get_parent(filter.context) orelse {
        obs.obs_source_skip_video_filter(filter.context);
        return;
    };

    if (!filter.cfg.enabled or !filter.rt.active.load(.seq_cst)) {
        obs.obs_source_skip_video_filter(filter.context);
        return;
    }

    const source_width = obs.obs_source_get_base_width(target);
    const source_height = obs.obs_source_get_base_height(target);
    if (source_width == 0 or source_height == 0) {
        obs.obs_source_skip_video_filter(filter.context);
        return;
    }

    const texture = renderTargetTexture(&filter.rt, target, parent, source_width, source_height) orelse {
        obs.obs_source_skip_video_filter(filter.context);
        return;
    };

    if (filter.rt.ensureStageSurface(source_width, source_height)) {
        obs.gs_stage_texture(filter.rt.stagesurface.?, texture);

        if (filter.cfg.getCaptureRect(source_width, source_height)) |capture_rect| {
            var mapped_data: [*c]u8 = null;
            var mapped_linesize: u32 = 0;

            if (obs.gs_stagesurface_map(filter.rt.stagesurface.?, &mapped_data, &mapped_linesize)) {
                const copied = copyCaptureRegion(&filter.rt, capture_rect, mapped_data, mapped_linesize);
                obs.gs_stagesurface_unmap(filter.rt.stagesurface.?);

                if (copied) {
                    tryTrigger(filter, captureContainsTriggerColor(&filter.cfg, &filter.rt));
                }
            }
        }
    }

    drawPassThroughTexture(texture, effect, source_width, source_height);
    // Future overlays should draw here so they do not affect the captured pixels.
}

fn aeshna_filter_tick(data: ?*anyopaque, _: f32) callconv(.c) void {
    const ptr = data orelse return;
    const filter: *AeshnaFilterData = @ptrCast(@alignCast(ptr));

    tryRegisterHotkeys(filter);
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
    _ = utils;
    module.log.info("plugin loaded successfully (version {s})", .{manifest.version});
    obs.obs_register_source_s(&aeshna_filter, @sizeOf(obs.obs_source_info));
    return true;
}

export fn obs_module_unload() void {
    module.log.info("plugin unloaded", .{});
}
