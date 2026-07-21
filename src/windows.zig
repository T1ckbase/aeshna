// Copyright (c) 2026 T1ckbase
// SPDX-License-Identifier: GPL-3.0-or-later

const std = @import("std");
const windows = std.os.windows;

pub const BOOL = c_int;
pub const TRUE = 1;
pub const FALSE = 0;

pub const POINT = extern struct {
    x: windows.LONG,
    y: windows.LONG,
};

pub const CURSOR_SHOWING: windows.DWORD = 0x00000001;
pub const CURSORINFO = extern struct {
    cbSize: windows.DWORD,
    flags: windows.DWORD,
    hCursor: windows.HCURSOR,
    ptScreenPos: POINT,
};

pub const MOUSEINPUT = extern struct {
    dx: windows.LONG,
    dy: windows.LONG,
    mouseData: windows.DWORD,
    dwFlags: windows.DWORD,
    time: windows.DWORD,
    dwExtraInfo: windows.ULONG_PTR,
};

pub const VK_SPACE: windows.WORD = 0x20;

pub const KEYEVENTF_EXTENDEDKEY: windows.DWORD = 0x0001;
pub const KEYEVENTF_KEYUP: windows.DWORD = 0x0002;
pub const KEYEVENTF_SCANCODE: windows.DWORD = 0x0008;
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

pub const INPUT_MOUSE: windows.DWORD = 0;
pub const INPUT_KEYBOARD: windows.DWORD = 1;
pub const INPUT_HARDWARE: windows.DWORD = 2;
pub const INPUT = extern struct {
    type: windows.DWORD,
    u: extern union {
        mi: MOUSEINPUT,
        ki: KEYBDINPUT,
        hi: HARDWAREINPUT,
    },
};

pub extern "user32" fn GetCursorInfo(pci: ?*CURSORINFO) callconv(.winapi) BOOL;

pub const MAPVK_VK_TO_VSC_EX: windows.UINT = 4;
pub extern "user32" fn MapVirtualKeyW(uCode: windows.UINT, uMapType: windows.UINT) callconv(.winapi) windows.UINT;

pub extern "user32" fn SendInput(cInputs: windows.UINT, pInputs: [*]const INPUT, cbSize: c_int) callconv(.winapi) windows.UINT;
