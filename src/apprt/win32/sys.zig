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
pub const WM_SIZE = 0x0005;
pub const WM_KEYDOWN = 0x0100;
pub const WM_KEYUP = 0x0101;
pub const WM_CHAR = 0x0102;
pub const WM_SYSKEYDOWN = 0x0104;
pub const WM_SYSKEYUP = 0x0105;
pub const WM_SYSCHAR = 0x0106;
pub const WM_UNICHAR = 0x0109;
pub const UNICODE_NOCHAR = 0xFFFF;
pub const WM_USER = 0x0400;
pub const WM_WAKEUP = WM_USER + 1;

// Virtual-key codes
pub const VK_BACK = 0x08;
pub const VK_TAB = 0x09;
pub const VK_RETURN = 0x0D;
pub const VK_SHIFT = 0x10;
pub const VK_CONTROL = 0x11;
pub const VK_MENU = 0x12;
pub const VK_PAUSE = 0x13;
pub const VK_CAPITAL = 0x14;
pub const VK_ESCAPE = 0x1B;
pub const VK_SPACE = 0x20;
pub const VK_PRIOR = 0x21;
pub const VK_NEXT = 0x22;
pub const VK_END = 0x23;
pub const VK_HOME = 0x24;
pub const VK_LEFT = 0x25;
pub const VK_UP = 0x26;
pub const VK_RIGHT = 0x27;
pub const VK_DOWN = 0x28;
pub const VK_INSERT = 0x2D;
pub const VK_DELETE = 0x2E;
pub const VK_LWIN = 0x5B;
pub const VK_RWIN = 0x5C;
pub const VK_NUMLOCK = 0x90;
pub const VK_SCROLL = 0x91;
pub const VK_LSHIFT = 0xA0;
pub const VK_RSHIFT = 0xA1;
pub const VK_LCONTROL = 0xA2;
pub const VK_RCONTROL = 0xA3;
pub const VK_LMENU = 0xA4;
pub const VK_RMENU = 0xA5;

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

// ============================================================================
// DWM (Desktop Window Manager) API for backdrop effects
// ============================================================================

pub const DWMWA_USE_IMMERSIVE_DARK_MODE: DWORD = 20;
pub const DWMWA_SYSTEMBACKDROP_TYPE: DWORD = 38;

pub const DWM_SYSTEMBACKDROP_TYPE = enum(DWORD) {
    auto = 0,
    none = 1,
    main_window = 2, // Mica
    transient_window = 3, // Acrylic
    tabbed_window = 4, // Mica Alt
};

pub const MARGINS = extern struct {
    cxLeftWidth: c_int,
    cxRightWidth: c_int,
    cyTopHeight: c_int,
    cyBottomHeight: c_int,
};

pub extern "dwmapi" fn DwmSetWindowAttribute(
    hwnd: HWND,
    dwAttribute: DWORD,
    pvAttribute: *const anyopaque,
    cbAttribute: DWORD,
) callconv(.winapi) c_int;

pub extern "dwmapi" fn DwmExtendFrameIntoClientArea(
    hwnd: HWND,
    pMarInset: *const MARGINS,
) callconv(.winapi) c_int;

// SetWindowCompositionAttribute for Win10 acrylic fallback
pub const WINDOWCOMPOSITIONATTRIB = enum(DWORD) {
    accent_policy = 19,
};

pub const ACCENT_STATE = enum(DWORD) {
    accent_enable_acrylicblurbehind = 4,
};

pub const ACCENT_POLICY = extern struct {
    nAccentState: ACCENT_STATE,
    nColor: DWORD,
    nAnimationId: DWORD,
    dwFlags: DWORD,
};

pub const WINDOWCOMPOSITIONATTRIBDATA = extern struct {
    nAttrib: WINDOWCOMPOSITIONATTRIB,
    pData: ?*anyopaque,
    ulDataSize: usize,
};

pub extern "user32" fn SetWindowCompositionAttribute(
    hwnd: HWND,
    pData: *WINDOWCOMPOSITIONATTRIBDATA,
) callconv(.winapi) c_int;
