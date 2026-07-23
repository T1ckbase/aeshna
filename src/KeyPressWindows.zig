// Copyright (c) 2026 T1ckbase
// SPDX-License-Identifier: GPL-3.0-or-later

const obs = @import("obs");
const windows = @import("windows.zig");

const Error = error{
    UnsupportedKey,
    SendInputFailed,
};

const mouse1: obs.obs_key_t = @intCast(obs.OBS_KEY_MOUSE1);
const mouse2: obs.obs_key_t = @intCast(obs.OBS_KEY_MOUSE2);
const mouse3: obs.obs_key_t = @intCast(obs.OBS_KEY_MOUSE3);
const mouse4: obs.obs_key_t = @intCast(obs.OBS_KEY_MOUSE4);
const mouse5: obs.obs_key_t = @intCast(obs.OBS_KEY_MOUSE5);

pub fn isSupported(key: obs.obs_key_t) bool {
    return isMouseKey(key) or scanCodeForKey(key) != null;
}

pub fn send(key: obs.obs_key_t, pressed: bool) Error!void {
    if (isMouseKey(key)) return sendMouse(key, pressed);

    const scan_code = scanCodeForKey(key) orelse return error.UnsupportedKey;
    var flags: windows.DWORD = windows.KEYEVENTF_SCANCODE;
    if (!pressed) flags |= windows.KEYEVENTF_KEYUP;
    if ((scan_code & 0xFF00) == 0xE000) flags |= windows.KEYEVENTF_EXTENDEDKEY;

    const input = windows.INPUT{
        .type = windows.INPUT_KEYBOARD,
        .u = .{ .ki = .{
            .wVk = 0,
            .wScan = @truncate(scan_code),
            .dwFlags = flags,
            .time = 0,
            .dwExtraInfo = 0,
        } },
    };
    return submit(input);
}

fn isMouseKey(key: obs.obs_key_t) bool {
    return key >= mouse1 and key <= mouse5;
}

fn scanCodeForKey(key: obs.obs_key_t) ?windows.UINT {
    const virtual_key = obs.obs_key_to_virtual_key(key);
    if (virtual_key == 0) return null;

    const scan_code = windows.MapVirtualKeyW(@intCast(virtual_key), windows.MAPVK_VK_TO_VSC_EX);
    return if (scan_code == 0) null else scan_code;
}

fn sendMouse(key: obs.obs_key_t, pressed: bool) Error!void {
    const flags: windows.DWORD = switch (key) {
        mouse1 => if (pressed) windows.MOUSEEVENTF_LEFTDOWN else windows.MOUSEEVENTF_LEFTUP,
        mouse2 => if (pressed) windows.MOUSEEVENTF_RIGHTDOWN else windows.MOUSEEVENTF_RIGHTUP,
        mouse3 => if (pressed) windows.MOUSEEVENTF_MIDDLEDOWN else windows.MOUSEEVENTF_MIDDLEUP,
        mouse4 => if (pressed) windows.MOUSEEVENTF_XDOWN else windows.MOUSEEVENTF_XUP,
        mouse5 => if (pressed) windows.MOUSEEVENTF_XDOWN else windows.MOUSEEVENTF_XUP,
        else => return error.UnsupportedKey,
    };
    const data: windows.DWORD = switch (key) {
        mouse4 => windows.XBUTTON1,
        mouse5 => windows.XBUTTON2,
        else => 0,
    };
    const input = windows.INPUT{
        .type = windows.INPUT_MOUSE,
        .u = .{ .mi = .{
            .dx = 0,
            .dy = 0,
            .mouseData = data,
            .dwFlags = flags,
            .time = 0,
            .dwExtraInfo = 0,
        } },
    };
    return submit(input);
}

fn submit(input: windows.INPUT) Error!void {
    var inputs = [_]windows.INPUT{input};
    if (windows.SendInput(1, &inputs, @sizeOf(windows.INPUT)) != 1) {
        return error.SendInputFailed;
    }
}
