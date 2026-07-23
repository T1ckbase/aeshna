// Copyright (c) 2026 T1ckbase
// SPDX-License-Identifier: GPL-3.0-or-later

const builtin = @import("builtin");
const obs = @import("obs");

pub const State = enum {
    press,
    release,
};

pub const Error = error{
    UnsupportedKey,
    SendInputFailed,
    UnsupportedPlatform,
};

pub fn isSupported(key: obs.obs_key_t) bool {
    return switch (builtin.os.tag) {
        .windows => @import("KeyPressWindows.zig").isSupported(key),
        else => false,
    };
}

pub fn send(key: obs.obs_key_t, state: State) Error!void {
    return switch (builtin.os.tag) {
        .windows => @import("KeyPressWindows.zig").send(key, state == .press),
        else => error.UnsupportedPlatform,
    };
}
