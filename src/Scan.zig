// Copyright (c) 2026 T1ckbase
// SPDX-License-Identifier: GPL-3.0-or-later

const std = @import("std");

const obs = @import("obs");

const Scan = @This();

pub const Error = error{
    InvalidTargetSize,
    StageSurfaceCreateFailed,
    TexRenderBeginFailed,
    StageSurfaceMapFailed,
};

clear_color: obs.vec4,
texrender: *obs.gs_texrender_t,
stagesurf: ?*obs.gs_stagesurf_t,
stage_width: u32,
stage_height: u32,

pub fn init() Scan {
    obs.obs_enter_graphics();
    defer obs.obs_leave_graphics();

    var clear_color: obs.vec4 = .{};
    obs.vec4_zero(&clear_color);

    return .{
        .clear_color = clear_color,
        .texrender = obs.gs_texrender_create(obs.GS_BGRA, obs.GS_ZS_NONE).?,
        .stagesurf = null,
        .stage_width = 0,
        .stage_height = 0,
    };
}

fn ensureStageSurface(self: *Scan, width: u32, height: u32) Error!void {
    if (self.stagesurf != null and self.stage_width == width and self.stage_height == height) {
        return;
    }

    const stagesurface = obs.gs_stagesurface_create(width, height, obs.GS_BGRA) orelse {
        return Error.StageSurfaceCreateFailed;
    };

    if (self.stagesurf) |sf| {
        obs.gs_stagesurface_destroy(sf);
    }

    self.stagesurf = stagesurface;
    self.stage_width = width;
    self.stage_height = height;
}

pub fn scan(self: *Scan, target: *obs.obs_source_t, sx: u32, sy: u32, sw: u32, sh: u32, mask_color: u24) Error!bool {
    const source_width = obs.obs_source_get_width(target);
    const source_height = obs.obs_source_get_height(target);
    if (source_width == 0 or source_height == 0) {
        return Error.InvalidTargetSize;
    }

    const scan_x: u32 = @min(sx, source_width);
    const scan_y: u32 = @min(sy, source_height);
    const scan_width: u32 = @min(sw, source_width - scan_x);
    const scan_height: u32 = @min(sh, source_height - scan_y);
    if (scan_width == 0 or scan_height == 0) return false;

    obs.gs_texrender_reset(self.texrender);

    if (obs.gs_texrender_begin(self.texrender, scan_width, scan_height)) {
        defer obs.gs_texrender_end(self.texrender);

        obs.gs_clear(obs.GS_CLEAR_COLOR, &self.clear_color, 0.0, 0);
        obs.gs_ortho(
            @floatFromInt(scan_x),
            @floatFromInt(scan_x + scan_width),
            @floatFromInt(scan_y),
            @floatFromInt(scan_y + scan_height),
            -100.0,
            100.0,
        );

        obs.gs_blend_state_push();
        obs.gs_blend_function(obs.GS_BLEND_ONE, obs.GS_BLEND_ZERO);

        obs.obs_source_video_render(target);

        obs.gs_blend_state_pop();
    } else {
        return Error.TexRenderBeginFailed;
    }

    try self.ensureStageSurface(scan_width, scan_height);

    obs.gs_stage_texture(self.stagesurf.?, obs.gs_texrender_get_texture(self.texrender));

    var data: [*c]u8 = null;
    var linesize: u32 = 0;

    if (obs.gs_stagesurface_map(self.stagesurf.?, &data, &linesize)) {
        defer obs.gs_stagesurface_unmap(self.stagesurf.?);

        for (0..scan_height) |y| {
            const row = data + y * linesize;
            for (0..scan_width) |x| {
                const px: *align(1) const u24 = @ptrCast(row + x * 4);
                if (px.* != mask_color) return true;
            }
        }

        return false;
    } else {
        return Error.StageSurfaceMapFailed;
    }
}

pub fn deinit(self: *Scan) void {
    obs.obs_enter_graphics();

    obs.gs_texrender_destroy(self.texrender);
    if (self.stagesurf) |stagesurf| {
        obs.gs_stagesurface_destroy(stagesurf);
    }

    obs.obs_leave_graphics();
    self.* = undefined;
}
