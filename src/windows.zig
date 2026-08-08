// Copyright (c) 2026 T1ckbase
// SPDX-License-Identifier: GPL-3.0-or-later

const std = @import("std");
const windows = std.os.windows;

pub const WORD = windows.WORD;
pub const DWORD = windows.DWORD;
pub const UINT = windows.UINT;

pub const TRUE = windows.TRUE;
pub const FALSE = windows.FALSE;

pub const GetLastError = windows.GetLastError;
pub const unexpectedError = windows.unexpectedError;

pub const Win32Error = windows.Win32Error;

pub const CURSOR_SHOWING = 0x00000001;
pub const CURSORINFO = extern struct {
    cbSize: windows.DWORD,
    flags: windows.DWORD,
    hCursor: windows.HCURSOR,
    ptScreenPos: windows.POINT,
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
pub const MOUSEEVENTF_LEFTDOWN: windows.DWORD = 0x0002;
pub const MOUSEEVENTF_LEFTUP: windows.DWORD = 0x0004;
pub const MOUSEEVENTF_RIGHTDOWN: windows.DWORD = 0x0008;
pub const MOUSEEVENTF_RIGHTUP: windows.DWORD = 0x0010;
pub const MOUSEEVENTF_MIDDLEDOWN: windows.DWORD = 0x0020;
pub const MOUSEEVENTF_MIDDLEUP: windows.DWORD = 0x0040;
pub const MOUSEEVENTF_XDOWN: windows.DWORD = 0x0080;
pub const MOUSEEVENTF_XUP: windows.DWORD = 0x0100;
pub const XBUTTON1: windows.DWORD = 0x0001;
pub const XBUTTON2: windows.DWORD = 0x0002;
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

pub extern "user32" fn GetCursorInfo(pci: ?*CURSORINFO) callconv(.winapi) windows.BOOL;

pub const MAPVK_VK_TO_VSC_EX: windows.UINT = 4;
pub extern "user32" fn MapVirtualKeyW(uCode: windows.UINT, uMapType: windows.UINT) callconv(.winapi) windows.UINT;

pub extern "user32" fn SendInput(cInputs: windows.UINT, pInputs: [*]const INPUT, cbSize: windows.INT) callconv(.winapi) windows.UINT;
