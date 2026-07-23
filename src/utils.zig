// Copyright (c) 2026 T1ckbase
// SPDX-License-Identifier: GPL-3.0-or-later

const std = @import("std");
const windows = @import("windows.zig");

pub fn isCursorShowing() !bool {
    var ci: windows.CURSORINFO = undefined;
    ci.cbSize = @sizeOf(windows.CURSORINFO);

    if (windows.GetCursorInfo(&ci) == windows.FALSE) {
        return windows.unexpectedError(windows.GetLastError());
    }

    return (ci.flags & windows.CURSOR_SHOWING) != 0;
}
