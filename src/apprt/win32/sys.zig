//! Shared Win32 type declarations and extern functions used by both
//! App.zig and Window.zig.

const std = @import("std");

pub const BOOL = i32;
pub const UINT = u32;
pub const DWORD = u32;
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;
pub const HWND = std.os.windows.HWND;
pub const HINSTANCE = std.os.windows.HINSTANCE;
pub const HICON = ?*anyopaque;
pub const HCURSOR = ?*anyopaque;
pub const HBRUSH = ?*anyopaque;
pub const HDC = ?*anyopaque;
pub const HMENU = ?*anyopaque;
pub const ATOM = u16;
pub const LONG_PTR = isize;

pub const POINT = extern struct { x: i32, y: i32 };
pub const RECT = extern struct { left: i32, top: i32, right: i32, bottom: i32 };

pub const MSG = extern struct {
    hwnd: ?HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
};

pub const PAINTSTRUCT = extern struct {
    hdc: HDC,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]u8,
};

pub const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;

pub const WNDCLASSEXW = extern struct {
    cbSize: UINT,
    style: UINT,
    lpfnWndProc: WNDPROC,
    cbClsExtra: c_int,
    cbWndExtra: c_int,
    hInstance: ?HINSTANCE,
    hIcon: HICON,
    hCursor: HCURSOR,
    hbrBackground: HBRUSH,
    lpszMenuName: ?[*:0]const u16,
    lpszClassName: [*:0]const u16,
    hIconSm: HICON,
};

pub const MONITORINFO = extern struct {
    cbSize: DWORD,
    rcMonitor: RECT,
    rcWork: RECT,
    dwFlags: DWORD,
};

pub const COPYDATASTRUCT = extern struct {
    dwData: usize,
    cbData: u32,
    lpData: ?*const anyopaque,
};

// Window messages
pub const WM_CLOSE = 0x0010;
pub const WM_COPYDATA = 0x004A;
pub const WM_DESTROY = 0x0002;
pub const WM_PAINT = 0x000F;
pub const WM_ERASEBKGND = 0x0014;
pub const WM_SIZE = 0x0005;
pub const WM_KEYDOWN = 0x0100;
pub const WM_CHAR = 0x0102;
pub const WM_USER = 0x0400;
pub const WM_WAKEUP = WM_USER + 1;

// Window class styles
pub const CS_HREDRAW = 0x0002;
pub const CS_VREDRAW = 0x0001;
pub const CS_OWNDC = 0x0020;

// Window styles
pub const WS_OVERLAPPEDWINDOW = 0x00CF0000;
pub const WS_CAPTION_BIT: u32 = 0x00C00000;
pub const WS_EX_TOPMOST: i32 = 0x00000008;
pub const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));

// ShowWindow commands
pub const SW_SHOWNORMAL = 1;
pub const SW_MAXIMIZE: c_int = 3;
pub const SW_RESTORE: c_int = 9;

// GetWindowLong indices
pub const GWL_STYLE: c_int = -16;
pub const GWL_EXSTYLE: c_int = -20;
pub const GWLP_USERDATA: c_int = -21;
pub const WS_EX_LAYERED: u32 = 0x00080000;
pub const LWA_ALPHA: DWORD = 0x00000002;

pub const IDC_ARROW: ?[*:0]align(1) const u16 = @ptrFromInt(32512);

// Win32 API functions
pub extern "user32" fn RegisterClassExW(lpWndClass: *const WNDCLASSEXW) callconv(.winapi) ATOM;
pub extern "user32" fn CreateWindowExW(dwExStyle: DWORD, lpClassName: ?[*:0]const u16, lpWindowName: ?[*:0]const u16, dwStyle: DWORD, x: i32, y: i32, nWidth: i32, nHeight: i32, hWndParent: ?HWND, hMenu: HMENU, hInstance: ?HINSTANCE, lpParam: ?*anyopaque) callconv(.winapi) ?HWND;
pub extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: c_int) callconv(.winapi) BOOL;
pub extern "user32" fn UpdateWindow(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn DefWindowProcW(hWnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn GetMessageW(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.winapi) BOOL;
pub extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(.winapi) LRESULT;
pub extern "user32" fn PostMessageW(hWnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) BOOL;
pub extern "user32" fn SendMessageW(hWnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn PostQuitMessage(nExitCode: c_int) callconv(.winapi) void;
pub extern "user32" fn BeginPaint(hWnd: HWND, lpPaint: *PAINTSTRUCT) callconv(.winapi) HDC;
pub extern "user32" fn EndPaint(hWnd: HWND, lpPaint: *const PAINTSTRUCT) callconv(.winapi) BOOL;
pub extern "user32" fn LoadCursorW(hInstance: ?HINSTANCE, lpCursorName: ?[*:0]align(1) const u16) callconv(.winapi) HCURSOR;
pub extern "user32" fn LoadIconW(hInstance: ?HINSTANCE, lpIconName: ?[*:0]align(1) const u16) callconv(.winapi) HICON;
pub extern "user32" fn SetWindowLongPtrW(hWnd: HWND, nIndex: c_int, dwNewLong: LONG_PTR) callconv(.winapi) LONG_PTR;
pub extern "user32" fn GetWindowLongPtrW(hWnd: HWND, nIndex: c_int) callconv(.winapi) LONG_PTR;
pub extern "user32" fn GetClientRect(hWnd: HWND, lpRect: *RECT) callconv(.winapi) BOOL;
pub extern "user32" fn InvalidateRect(hWnd: ?HWND, lpRect: ?*const RECT, bErase: BOOL) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetModuleHandleW(lpModuleName: ?[*:0]const u16) callconv(.winapi) ?HINSTANCE;
pub extern "user32" fn GetKeyState(nVirtKey: c_int) callconv(.winapi) i16;
pub extern "user32" fn SetWindowTextW(hWnd: HWND, lpString: [*:0]const u16) callconv(.winapi) BOOL;
pub extern "user32" fn AdjustWindowRectEx(lpRect: *RECT, dwStyle: DWORD, bMenu: BOOL, dwExStyle: DWORD) callconv(.winapi) BOOL;
pub extern "user32" fn SetWindowPos(hWnd: HWND, hWndInsertAfter: ?HWND, x: i32, y: i32, cx: i32, cy: i32, uFlags: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn IsZoomed(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn GetWindowLongW(hWnd: HWND, nIndex: c_int) callconv(.winapi) i32;
pub extern "user32" fn SetWindowLongW(hWnd: HWND, nIndex: c_int, dwNewLong: i32) callconv(.winapi) i32;
pub extern "user32" fn SetLayeredWindowAttributes(hWnd: HWND, crKey: DWORD, bAlpha: u8, dwFlags: DWORD) callconv(.winapi) BOOL;
pub extern "user32" fn GetWindowRect(hWnd: HWND, lpRect: *RECT) callconv(.winapi) BOOL;
pub extern "user32" fn MonitorFromWindow(hWnd: HWND, dwFlags: DWORD) callconv(.winapi) ?*anyopaque;
pub extern "user32" fn GetMonitorInfoW(hMonitor: ?*anyopaque, lpmi: *MONITORINFO) callconv(.winapi) BOOL;
pub extern "user32" fn SetFocus(hWnd: HWND) callconv(.winapi) ?HWND;
pub extern "user32" fn GetDpiForWindow(hWnd: HWND) callconv(.winapi) UINT;
pub extern "shell32" fn ShellExecuteW(hwnd: ?HWND, lpOperation: ?[*:0]const u16, lpFile: [*:0]const u16, lpParameters: ?[*:0]const u16, lpDirectory: ?[*:0]const u16, nShowCmd: c_int) callconv(.winapi) ?*anyopaque;
pub extern "kernel32" fn CreateMutexW(lpMutexAttributes: ?*anyopaque, bInitialOwner: BOOL, lpName: [*:0]const u16) callconv(.winapi) ?*anyopaque;
pub extern "kernel32" fn ReleaseMutex(hMutex: ?*anyopaque) callconv(.winapi) BOOL;
pub extern "kernel32" fn CloseHandle(hObject: ?*anyopaque) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetLastError() callconv(.winapi) DWORD;
pub extern "user32" fn FindWindowW(lpClassName: ?[*:0]const u16, lpWindowName: ?[*:0]const u16) callconv(.winapi) ?HWND;

pub const ERROR_ALREADY_EXISTS: DWORD = 183;
/// Custom app message used for single-instance "open new window" notification.
pub const WM_APP_NEW_WINDOW: UINT = 0x8000 + 1; // WM_APP + 1

// Desktop Window Manager attributes. Windows 10 accepts dark-mode titlebar
// updates through DWMWA_USE_IMMERSIVE_DARK_MODE; Windows 11 adds system
// backdrop materials through DWMWA_SYSTEMBACKDROP_TYPE.
pub const DWMWA_USE_IMMERSIVE_DARK_MODE: DWORD = 20;
pub const DWMWA_BORDER_COLOR: DWORD = 34;
pub const DWMWA_CAPTION_COLOR: DWORD = 35;
pub const DWMWA_TEXT_COLOR: DWORD = 36;
pub const DWMWA_SYSTEMBACKDROP_TYPE: DWORD = 38;
pub const DWMWA_COLOR_NONE: DWORD = 0xFFFFFFFE;

pub const DWM_SYSTEMBACKDROP_TYPE = enum(DWORD) {
    auto = 0,
    none = 1,
    main_window = 2,
    transient_window = 3,
    tabbed_window = 4,
};

pub extern "dwmapi" fn DwmSetWindowAttribute(
    hwnd: HWND,
    dwAttribute: DWORD,
    pvAttribute: *const anyopaque,
    cbAttribute: DWORD,
) callconv(.winapi) i32;

pub const ACCENT_STATE = enum(i32) {
    disabled = 0,
    enable_gradient = 1,
    enable_transparent_gradient = 2,
    enable_blurbehind = 3,
    enable_acrylicblurbehind = 4,
    enable_hostbackdrop = 5,
};

pub fn accentStateForBlur(blur: anytype) ACCENT_STATE {
    return switch (blur) {
        .acrylic => .enable_acrylicblurbehind,
        .mica, .@"mica-alt" => .enable_hostbackdrop,
        .true => .enable_blurbehind,
        else => .disabled,
    };
}

pub const ACCENT_POLICY = extern struct {
    AccentState: ACCENT_STATE,
    AccentFlags: DWORD,
    GradientColor: DWORD,
    AnimationId: DWORD,
};

pub const AccentTint = struct {
    r: u8,
    g: u8,
    b: u8,
};

pub const WINDOWCOMPOSITIONATTRIBDATA = extern struct {
    Attrib: DWORD,
    pvData: *anyopaque,
    cbData: usize,
};

pub const WCA_ACCENT_POLICY: DWORD = 19;

pub extern "user32" fn SetWindowCompositionAttribute(
    hwnd: HWND,
    data: *WINDOWCOMPOSITIONATTRIBDATA,
) callconv(.winapi) BOOL;

pub fn setAccentPolicy(hwnd: HWND, state: ACCENT_STATE, opacity: f64, tint: ?AccentTint) void {
    var accent: ACCENT_POLICY = .{
        .AccentState = state,
        .AccentFlags = 2,
        .GradientColor = acrylicGradientColor(opacity, tint),
        .AnimationId = 0,
    };
    var data: WINDOWCOMPOSITIONATTRIBDATA = .{
        .Attrib = WCA_ACCENT_POLICY,
        .pvData = &accent,
        .cbData = @sizeOf(ACCENT_POLICY),
    };
    _ = SetWindowCompositionAttribute(hwnd, &data);
}

pub fn acrylicGradientColor(opacity: f64, tint: ?AccentTint) u32 {
    const alpha: u32 = @intFromFloat(@round(@max(0.0, @min(1.0, opacity)) * 255.0));
    const color = tint orelse AccentTint{ .r = 0, .g = 0, .b = 0 };
    return (alpha << 24) |
        (@as(u32, color.b) << 16) |
        (@as(u32, color.g) << 8) |
        @as(u32, color.r);
}
