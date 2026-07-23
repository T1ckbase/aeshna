// Copyright (c) 2026 T1ckbase
// SPDX-License-Identifier: GPL-3.0-or-later

const std = @import("std");
const obs = @import("obs");

const KeyPress = @import("KeyPress.zig");

const KeyStroke = @This();

key: obs.obs_key_t,
hold_duration_ms: u64,
throttle_ms: u64,

pressed_key: ?obs.obs_key_t = null,
last_trigger_ns: u64 = 0,

pub fn init(key: obs.obs_key_t, hold_duration_ms: ?u64, throttle_ms: ?u64) KeyStroke {
    return .{
        .key = key,
        .hold_duration_ms = hold_duration_ms orelse 20,
        .throttle_ms = throttle_ms orelse 200,
    };
}

pub fn trigger(self: *KeyStroke, now_ns: u64) void {
    if (self.pressed_key != null) return;

    const throttle_ns = self.throttle_ms * std.time.ns_per_ms;
    if (now_ns -| self.last_trigger_ns < throttle_ns) return;

    self.last_trigger_ns = now_ns;
    KeyPress.send(self.key, .press) catch |err| {
        std.log.warn("failed to press configured key: {}", .{err});
        return;
    };

    self.pressed_key = self.key;
}

pub fn poll(self: *KeyStroke, now_ns: u64) void {
    if (self.pressed_key == null) return;

    const hold_at_least_ns = self.hold_duration_ms * std.time.ns_per_ms;
    if (now_ns -| self.last_trigger_ns > hold_at_least_ns) {
        self.release();
    }
}

pub fn release(self: *KeyStroke) void {
    const key = self.pressed_key orelse return;
    self.pressed_key = null;

    KeyPress.send(key, .release) catch |err| {
        std.log.warn("failed to release configured key: {}", .{err});
    };
}
