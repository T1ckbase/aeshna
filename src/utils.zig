// Copyright (c) 2026 T1ckbase
// SPDX-License-Identifier: GPL-3.0-or-later

const std = @import("std");
const windows = std.os.windows;

pub const CURSOR_SHOWING = 0x00000001;
pub const CURSORINFO = extern struct {
    cbSize: windows.DWORD,
    flags: windows.DWORD,
    hCursor: windows.HCURSOR,
    ptScreenPos: windows.POINT,
};

pub const INPUT_MOUSE = 0;
pub const INPUT_KEYBOARD = 1;
pub const INPUT_HARDWARE = 2;

pub const KEYEVENTF_KEYUP = 0x0002;
pub const VK_SPACE: windows.WORD = 0x20;

pub const MOUSEINPUT = extern struct {
    dx: windows.LONG,
    dy: windows.LONG,
    mouseData: windows.DWORD,
    dwFlags: windows.DWORD,
    time: windows.DWORD,
    dwExtraInfo: windows.ULONG_PTR,
};

pub const KEYBDINPUT = extern struct {
    wVk: windows.WORD,
    wScan: windows.WORD,
    dwFlags: windows.DWORD,
    time: windows.DWORD,
    dwExtraInfo: windows.ULONG_PTR,
};

pub const HARDWAREINPUT = extern struct {
    uMsg: windows.DWORD,
    wParamL: windows.WORD,
    wParamH: windows.WORD,
};

const INPUT = extern struct {
    type: windows.DWORD,
    u: extern union {
        mi: MOUSEINPUT,
        ki: KEYBDINPUT,
        hi: HARDWAREINPUT,
    },
};

extern "user32" fn GetCursorInfo(pci: ?*CURSORINFO) callconv(.winapi) windows.BOOL;
extern "user32" fn SendInput(cInputs: windows.UINT, pInputs: [*]const INPUT, cbSize: c_int) callconv(.winapi) windows.UINT;

pub fn isCursorShowing() !bool {
    var ci: CURSORINFO = undefined;
    ci.cbSize = @sizeOf(CURSORINFO);

    if (GetCursorInfo(&ci) == windows.FALSE) {
        return windows.unexpectedError(windows.GetLastError());
    }

    return (ci.flags & CURSOR_SHOWING) == 1;
}

// pub fn click() void {
//     press(VK_SPACE);
//     release(VK_SPACE);
// }

pub fn press(vk: windows.WORD) void {
    sendKeyboardInput(vk, 0);
}

pub fn release(vk: windows.WORD) void {
    sendKeyboardInput(vk, KEYEVENTF_KEYUP);
}

fn sendKeyboardInput(vk: windows.WORD, flags: windows.DWORD) void {
    var inputs = [1]INPUT{.{
        .type = INPUT_KEYBOARD,
        .u = .{
            .ki = .{
                .wVk = vk,
                .wScan = 0,
                .dwFlags = flags,
                .time = 0,
                .dwExtraInfo = 0,
            },
        },
    }};

    _ = SendInput(1, &inputs, @sizeOf(INPUT));
}
