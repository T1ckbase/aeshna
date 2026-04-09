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

extern "user32" fn GetCursorInfo(pci: *CURSORINFO) callconv(.winapi) windows.BOOL;
extern "user32" fn SendInput(cInputs: windows.UINT, pInputs: [*]const INPUT, cbSize: c_int) callconv(.winapi) windows.UINT;

pub fn isCursorShowing() !bool {
    var ci: CURSORINFO = undefined;
    ci.cbSize = @sizeOf(CURSORINFO);

    if (GetCursorInfo(&ci) == windows.FALSE) {
        return windows.unexpectedError(windows.GetLastError());
    }

    return (ci.flags & CURSOR_SHOWING) != 0;
}

pub fn click() void {
    var inputs = [2]INPUT{
        .{
            .type = INPUT_KEYBOARD,
            .u = .{
                .ki = .{
                    .wVk = 0x20,
                    .wScan = 0,
                    .dwFlags = 0,
                    .time = 0,
                    .dwExtraInfo = 0,
                },
            },
        },
        .{
            .type = INPUT_KEYBOARD,
            .u = .{
                .ki = .{
                    .wVk = 0x20,
                    .wScan = 0,
                    .dwFlags = KEYEVENTF_KEYUP,
                    .time = 0,
                    .dwExtraInfo = 0,
                },
            },
        },
    };

    const sent = SendInput(2, &inputs, @sizeOf(INPUT));
    _ = sent;

    // if (sent != 2) {
    //     return windows.unexpectedError(windows.GetLastError());
    //     // std.debug.print("Failed to send keystrokes, error code: {any}\n", .{err});
    // }
}
