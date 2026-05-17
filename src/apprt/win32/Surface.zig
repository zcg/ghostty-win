/// Win32 surface - represents a terminal surface within a window.
/// Manages the native child window and provides the interface
/// expected by CoreSurface.
const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const apprt = @import("../../apprt.zig");
const configpkg = @import("../../config.zig");
const CoreSurface = @import("../../Surface.zig");
const CoreApp = @import("../../App.zig");
const terminal = @import("../../terminal/main.zig");
const build_config = @import("../../build_config.zig");
const sys = @import("sys.zig");

const log = std.log.scoped(.win32_surface);

// Win32 types
const HWND = std.os.windows.HWND;
const HINSTANCE = std.os.windows.HINSTANCE;
const BOOL = i32;
const UINT = u32;
const HDC = ?*anyopaque;
const HGLRC = ?*anyopaque;
const RECT = extern struct { left: i32, top: i32, right: i32, bottom: i32 };
const PAINTSTRUCT = extern struct {
    hdc: HDC,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]u8,
};

const OpenGL = if (build_config.renderer == .opengl) struct {
    const PIXELFORMATDESCRIPTOR = extern struct {
        nSize: u16,
        nVersion: u16,
        dwFlags: u32,
        iPixelType: u8,
        cColorBits: u8,
        cRedBits: u8,
        cRedShift: u8,
        cGreenBits: u8,
        cGreenShift: u8,
        cBlueBits: u8,
        cBlueShift: u8,
        cAlphaBits: u8,
        cAlphaShift: u8,
        cAccumBits: u8,
        cAccumRedBits: u8,
        cAccumGreenBits: u8,
        cAccumBlueBits: u8,
        cAccumAlphaBits: u8,
        cDepthBits: u8,
        cStencilBits: u8,
        cAuxBuffers: u8,
        iLayerType: u8,
        bReserved: u8,
        dwLayerMask: u32,
        dwVisibleMask: u32,
        dwDamageMask: u32,
    };

    const PFD_DRAW_TO_WINDOW = 0x00000004;
    const PFD_SUPPORT_OPENGL = 0x00000020;
    const PFD_DOUBLEBUFFER = 0x00000001;
    const PFD_TYPE_RGBA = 0;
    const PFD_MAIN_PLANE = 0;

    extern "gdi32" fn ChoosePixelFormat(hdc: HDC, ppfd: *const PIXELFORMATDESCRIPTOR) callconv(.winapi) c_int;
    extern "gdi32" fn SetPixelFormat(hdc: HDC, format: c_int, ppfd: *const PIXELFORMATDESCRIPTOR) callconv(.winapi) BOOL;
    extern "gdi32" fn SwapBuffers(hdc: HDC) callconv(.winapi) BOOL;
    extern "opengl32" fn wglCreateContext(hdc: HDC) callconv(.winapi) HGLRC;
    extern "opengl32" fn wglDeleteContext(hglrc: HGLRC) callconv(.winapi) BOOL;
    extern "opengl32" fn wglMakeCurrent(hdc: HDC, hglrc: HGLRC) callconv(.winapi) BOOL;
    extern "opengl32" fn wglGetProcAddress(lpszProc: [*:0]const u8) callconv(.winapi) ?*const anyopaque;
    extern "opengl32" fn glViewport(x: i32, y: i32, width: i32, height: i32) callconv(.winapi) void;
} else struct {};

extern "user32" fn GetDC(hWnd: ?HWND) callconv(.winapi) HDC;
extern "user32" fn ReleaseDC(hWnd: ?HWND, hDC: HDC) callconv(.winapi) c_int;
extern "user32" fn InvalidateRect(hWnd: ?HWND, lpRect: ?*const std.os.windows.RECT, bErase: BOOL) callconv(.winapi) BOOL;
extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: c_int) callconv(.winapi) BOOL;
extern "user32" fn SetWindowPos(hWnd: HWND, hWndInsertAfter: ?HWND, x: i32, y: i32, cx: i32, cy: i32, uFlags: UINT) callconv(.winapi) BOOL;
extern "user32" fn BeginPaint(hWnd: HWND, lpPaint: *PAINTSTRUCT) callconv(.winapi) HDC;
extern "user32" fn EndPaint(hWnd: HWND, lpPaint: *const PAINTSTRUCT) callconv(.winapi) BOOL;
extern "user32" fn SetTimer(hWnd: ?HWND, nIDEvent: usize, uElapse: UINT, lpTimerFunc: ?*const anyopaque) callconv(.winapi) usize;
extern "user32" fn KillTimer(hWnd: ?HWND, uIDEvent: usize) callconv(.winapi) BOOL;
extern "user32" fn FillRect(hDC: ?*anyopaque, lprc: *const RECT, hbr: ?*anyopaque) callconv(.winapi) c_int;
extern "gdi32" fn CreateSolidBrush(color: u32) callconv(.winapi) ?*anyopaque;
extern "gdi32" fn DeleteObject(ho: ?*anyopaque) callconv(.winapi) BOOL;
extern "user32" fn SetCapture(hWnd: HWND) callconv(.winapi) ?HWND;
extern "user32" fn ReleaseCapture() callconv(.winapi) BOOL;
extern "user32" fn ClientToScreen(hWnd: HWND, lpPoint: *sys.POINT) callconv(.winapi) BOOL;

// Clipboard API
const HANDLE = ?*anyopaque;
extern "user32" fn OpenClipboard(hWndNewOwner: ?HWND) callconv(.winapi) BOOL;
extern "user32" fn CloseClipboard() callconv(.winapi) BOOL;
extern "user32" fn EmptyClipboard() callconv(.winapi) BOOL;
extern "user32" fn GetClipboardData(uFormat: UINT) callconv(.winapi) HANDLE;
extern "user32" fn SetClipboardData(uFormat: UINT, hMem: HANDLE) callconv(.winapi) HANDLE;
extern "kernel32" fn GlobalAlloc(uFlags: UINT, dwBytes: usize) callconv(.winapi) HANDLE;
extern "kernel32" fn GlobalFree(hMem: HANDLE) callconv(.winapi) HANDLE;
extern "kernel32" fn GlobalLock(hMem: HANDLE) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GlobalUnlock(hMem: HANDLE) callconv(.winapi) BOOL;

/// The window this surface belongs to.
hwnd: HWND,

/// Pointer back to the App.
app: ?*App = null,

/// Pointer back to the Window that contains this Surface.
window: ?*Window = null,

/// GDI device context.
hdc: HDC = null,

/// OpenGL rendering context, only used by legacy OpenGL builds.
hglrc: HGLRC = null,

/// The core surface, if initialized.
core_surface: ?*CoreSurface = null,

/// Window dimensions.
width: u32 = 800,
height: u32 = 600,

/// Last known cursor position in client pixels.
cursor_pos: apprt.CursorPos = .{ .x = 0, .y = 0 },

/// Pending high surrogate from WM_CHAR.
pending_high_surrogate: ?u16 = null,

/// UTF-8 window title cache for title reporting.
title_buf: [1024:0]u8 = [_:0]u8{0} ** 1024,
progress_hwnd: ?HWND = null,
progress_visible: bool = false,
progress_state: terminal.osc.Command.ProgressReport.State = .remove,
progress_value: ?u8 = null,
progress_phase: u8 = 0,
scrollbar_hwnd: ?HWND = null,
scrollbar_drag: ?ScrollbarDrag = null,
scrollbar_hovered: bool = false,
scrollbar_tracking_leave: bool = false,
layout_x: i32 = 0,
layout_y: i32 = 0,
layout_w: i32 = 0,
layout_h: i32 = 0,
last_renderer_w: u32 = 0,
last_renderer_h: u32 = 0,
pending_core_resize_w: u32 = 0,
pending_core_resize_h: u32 = 0,
scrollbar: terminal.Scrollbar = .zero,

const App = @import("App.zig");
const Window = @import("Window.zig");
const ProgressState = terminal.osc.Command.ProgressReport.State;
const progress_overlay_height: i32 = 12;
const progress_timeout_ms: UINT = 15_000;
const progress_pulse_ms: UINT = 120;
const progress_timeout_timer_id: usize = 1;
const progress_pulse_timer_id: usize = 2;
const SW_HIDE: c_int = 0;
const SW_SHOWNORMAL: c_int = 1;
const WM_PAINT: UINT = 0x000F;
const WM_TIMER: UINT = 0x0113;
const WM_ERASEBKGND: UINT = 0x0014;
const WM_SETCURSOR: UINT = 0x0020;
const WM_NCHITTEST: UINT = 0x0084;
const WM_MOUSEMOVE: UINT = 0x0200;
const WM_LBUTTONDOWN: UINT = 0x0201;
const WM_LBUTTONUP: UINT = 0x0202;
const WM_MOUSEWHEEL: UINT = 0x020A;
const WM_CAPTURECHANGED: UINT = 0x0215;
const HWND_TOP: ?HWND = @ptrFromInt(@as(usize, @bitCast(@as(isize, 0))));
const SWP_NOACTIVATE: UINT = 0x0010;
const SWP_SHOWWINDOW: UINT = 0x0040;
const HTTRANSPARENT: isize = -1;
const scrollbar_margin: i32 = 2;
const scrollbar_control_w: i32 = 16;
const scrollbar_thumb_min_h: i32 = 28;
const scrollbar_idle_thumb_w: i32 = 6;
const scrollbar_hover_thumb_w: i32 = 12;
const scrollbar_wheel_rows: usize = 3;
const WHEEL_DELTA: i32 = 120;
var progress_class_registered: bool = false;
var scrollbar_class_registered: bool = false;

const ScrollbarDrag = struct {
    grab_y: i32,
};

pub fn core(self: *Self) *CoreSurface {
    return self.core_surface.?;
}

pub fn rtApp(self: *Self) *App {
    return self.app.?;
}

pub fn init(self: *Self, parent: HWND, app: *App) !void {
    self.* = .{ .hwnd = undefined, .app = app };

    // Create a child window for this surface.
    const class_name = std.unicode.utf8ToUtf16LeStringLiteral("GhosttySurface");

    // Ensure the surface window class is registered (idempotent).
    try registerSurfaceClass();

    var rect: RECT = undefined;
    _ = GetClientRect(parent, &rect);
    const cw: i32 = rect.right - rect.left;
    const ch: i32 = rect.bottom - rect.top;

    const hinstance = GetModuleHandleW(null);
    const WS_CHILD: u32 = 0x40000000;
    const WS_VISIBLE: u32 = 0x10000000;
    const WS_CLIPCHILDREN: u32 = 0x02000000;
    const child = CreateWindowExW(
        0,
        class_name,
        null,
        WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN,
        0,
        0,
        cw,
        ch,
        parent,
        null,
        hinstance,
        null,
    ) orelse return error.Win32Error;

    self.hwnd = child;
    self.width = @intCast(@max(1, cw));
    self.height = @intCast(@max(1, ch));
    self.applyBackgroundEffect();

    // Store self pointer on the child window for message handling
    _ = SetWindowLongPtrW(child, GWLP_USERDATA, @bitCast(@intFromPtr(self)));
    try self.createProgressOverlay();

    if (comptime build_config.renderer == .opengl) {
        try self.initOpenGL();
    }
}

pub fn applyBackgroundEffect(self: *Self) void {
    const app = self.app orelse return;
    const window = self.window orelse return;
    const blur = app.config.@"background-blur";
    if (blur == .false) {
        sys.setAccentPolicy(self.hwnd, .disabled, 0, .{ .r = 0, .g = 0, .b = 0 });
        return;
    }
    if (window.dwm_backdrop_supported and blur != .transparent) {
        sys.setAccentPolicy(self.hwnd, .disabled, 0, .{ .r = 0, .g = 0, .b = 0 });
        return;
    }
    sys.setAccentPolicy(
        self.hwnd,
        sys.accentStateForBlur(blur),
        app.config.@"background-opacity",
        .{
            .r = app.config.background.r,
            .g = app.config.background.g,
            .b = app.config.background.b,
        },
    );
}

var surface_class_registered: bool = false;

fn registerSurfaceClass() !void {
    if (surface_class_registered) return;
    const class_name = std.unicode.utf8ToUtf16LeStringLiteral("GhosttySurface");
    const hinstance = GetModuleHandleW(null);
    const CS_HREDRAW: u32 = 0x0002;
    const CS_VREDRAW: u32 = 0x0001;
    const CS_OWNDC: u32 = 0x0020;
    var wc: WNDCLASSEXW = std.mem.zeroes(WNDCLASSEXW);
    wc.cbSize = @sizeOf(WNDCLASSEXW);
    wc.style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC;
    wc.lpfnWndProc = surfaceWndProc;
    wc.hInstance = hinstance;
    wc.hCursor = LoadCursorW(null, @ptrFromInt(32512));
    wc.lpszClassName = class_name;
    if (RegisterClassExW(&wc) == 0) return error.Win32Error;
    surface_class_registered = true;
}

fn surfaceWndProc(hwnd: HWND, msg: u32, wparam: usize, lparam: isize) callconv(.winapi) isize {
    const ptr = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
    if (ptr == 0) return DefWindowProcW(hwnd, msg, wparam, lparam);
    const self: *Self = @ptrFromInt(@as(usize, @bitCast(ptr)));
    const app = self.app orelse return DefWindowProcW(hwnd, msg, wparam, lparam);
    return App.surfaceDispatch(app, self, hwnd, msg, wparam, lparam);
}

fn scrollbarWndProc(hwnd: HWND, msg: u32, wparam: usize, lparam: isize) callconv(.winapi) isize {
    const ptr = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
    if (ptr == 0) return DefWindowProcW(hwnd, msg, wparam, lparam);
    const self: *Self = @ptrFromInt(@as(usize, @bitCast(ptr)));
    return self.handleScrollbarMessage(hwnd, msg, wparam, lparam);
}

fn progressWndProc(hwnd: HWND, msg: u32, wparam: usize, lparam: isize) callconv(.winapi) isize {
    const ptr = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
    if (ptr == 0) return DefWindowProcW(hwnd, msg, wparam, lparam);
    const self: *Self = @ptrFromInt(@as(usize, @bitCast(ptr)));
    switch (msg) {
        WM_PAINT => {
            self.paintProgress(hwnd);
            return 0;
        },
        WM_TIMER => {
            switch (wparam) {
                progress_timeout_timer_id => {
                    self.hideProgressOverlay();
                    return 0;
                },
                progress_pulse_timer_id => {
                    self.progress_phase +%= 1;
                    _ = InvalidateRect(hwnd, null, 0);
                    return 0;
                },
                else => {},
            }
        },
        else => {},
    }
    return DefWindowProcW(hwnd, msg, wparam, lparam);
}

pub fn deinit(self: *Self) void {
    self.hideProgressOverlay();
    if (self.scrollbar_hwnd) |hwnd| {
        _ = SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
        _ = DestroyWindow(hwnd);
        self.scrollbar_hwnd = null;
    }
    if (self.progress_hwnd) |hwnd| {
        _ = SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
        _ = DestroyWindow(hwnd);
        self.progress_hwnd = null;
    }
    if (self.core_surface) |surface| {
        surface.deinit();
        // core_surface is allocated by CoreApp, freed there
    }
    if (comptime build_config.renderer == .opengl) {
        if (self.hglrc != null) {
            _ = OpenGL.wglMakeCurrent(null, null);
            _ = OpenGL.wglDeleteContext(self.hglrc);
        }
    }
    if (self.hdc != null) {
        _ = ReleaseDC(self.hwnd, self.hdc);
        self.hdc = null;
    }
    _ = SetWindowLongPtrW(self.hwnd, GWLP_USERDATA, 0);
    _ = DestroyWindow(self.hwnd);
}

fn initOpenGL(self: *Self) !void {
    self.hdc = GetDC(self.hwnd);
    if (self.hdc == null) {
        log.err("GetDC failed", .{});
        return error.Win32Error;
    }

    var pfd: OpenGL.PIXELFORMATDESCRIPTOR = std.mem.zeroes(OpenGL.PIXELFORMATDESCRIPTOR);
    pfd.nSize = @sizeOf(OpenGL.PIXELFORMATDESCRIPTOR);
    pfd.nVersion = 1;
    pfd.dwFlags = OpenGL.PFD_DRAW_TO_WINDOW | OpenGL.PFD_SUPPORT_OPENGL | OpenGL.PFD_DOUBLEBUFFER;
    pfd.iPixelType = OpenGL.PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    pfd.cDepthBits = 24;
    pfd.cStencilBits = 8;
    pfd.iLayerType = OpenGL.PFD_MAIN_PLANE;

    const pixel_format = OpenGL.ChoosePixelFormat(self.hdc, &pfd);
    if (pixel_format == 0) {
        log.err("ChoosePixelFormat failed", .{});
        return error.Win32Error;
    }

    if (OpenGL.SetPixelFormat(self.hdc, pixel_format, &pfd) == 0) {
        log.err("SetPixelFormat failed", .{});
        return error.Win32Error;
    }

    self.hglrc = OpenGL.wglCreateContext(self.hdc);
    if (self.hglrc == null) {
        log.err("wglCreateContext failed", .{});
        return error.Win32Error;
    }

    if (OpenGL.wglMakeCurrent(self.hdc, self.hglrc) == 0) {
        log.err("wglMakeCurrent failed", .{});
        return error.Win32Error;
    }

    // Set initial viewport to client area
    var client_rect: RECT = std.mem.zeroes(RECT);
    if (GetClientRect(self.hwnd, &client_rect) != 0) {
        self.width = @intCast(client_rect.right - client_rect.left);
        self.height = @intCast(client_rect.bottom - client_rect.top);
    }
    OpenGL.glViewport(0, 0, @intCast(self.width), @intCast(self.height));

    log.info("WGL OpenGL context created, client area {}x{}", .{ self.width, self.height });
}

extern "user32" fn GetClientRect(hWnd: HWND, lpRect: *RECT) callconv(.winapi) BOOL;
extern "user32" fn CreateWindowExW(dwExStyle: u32, lpClassName: ?[*:0]const u16, lpWindowName: ?[*:0]const u16, dwStyle: u32, x: i32, y: i32, nWidth: i32, nHeight: i32, hWndParent: ?HWND, hMenu: ?*anyopaque, hInstance: ?*anyopaque, lpParam: ?*anyopaque) callconv(.winapi) ?HWND;
extern "user32" fn RegisterClassExW(lpWndClass: *const WNDCLASSEXW) callconv(.winapi) u16;
extern "user32" fn DefWindowProcW(hWnd: HWND, msg: u32, wParam: usize, lParam: isize) callconv(.winapi) isize;
extern "user32" fn SetWindowLongPtrW(hWnd: HWND, nIndex: i32, dwNewLong: isize) callconv(.winapi) isize;
extern "user32" fn GetWindowLongPtrW(hWnd: HWND, nIndex: i32) callconv(.winapi) isize;
extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.winapi) BOOL;
extern "user32" fn UpdateWindow(hWnd: HWND) callconv(.winapi) BOOL;
extern "kernel32" fn GetModuleHandleW(lpModuleName: ?[*:0]const u16) callconv(.winapi) ?*anyopaque;
const GWLP_USERDATA: i32 = -21;

const WNDCLASSEXW = extern struct {
    cbSize: u32,
    style: u32,
    lpfnWndProc: *const fn (HWND, u32, usize, isize) callconv(.winapi) isize,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: ?*anyopaque,
    hIcon: ?*anyopaque,
    hCursor: ?*anyopaque,
    hbrBackground: ?*anyopaque,
    lpszMenuName: ?[*:0]const u16,
    lpszClassName: ?[*:0]const u16,
    hIconSm: ?*anyopaque,
};

pub fn swapBuffers(self: *Self) void {
    if (comptime build_config.renderer != .opengl) return;
    if (self.hdc != null) {
        _ = OpenGL.SwapBuffers(self.hdc);
    }
}

fn createProgressOverlay(self: *Self) !void {
    try registerProgressClass();
    const hwnd = CreateWindowExW(
        0,
        std.unicode.utf8ToUtf16LeStringLiteral("GhosttyProgressOverlay"),
        null,
        0x40000000,
        0,
        0,
        0,
        progress_overlay_height,
        self.hwnd,
        null,
        GetModuleHandleW(null),
        null,
    ) orelse return error.Win32Error;
    self.progress_hwnd = hwnd;
    _ = SetWindowLongPtrW(hwnd, GWLP_USERDATA, @bitCast(@intFromPtr(self)));
}

fn createScrollbarOverlay(self: *Self) !void {
    try registerScrollbarClass();
    const WS_CHILD: u32 = 0x40000000;
    const WS_CLIPSIBLINGS: u32 = 0x04000000;
    const hwnd = CreateWindowExW(
        0,
        std.unicode.utf8ToUtf16LeStringLiteral("GhosttyScrollbar"),
        null,
        WS_CHILD | WS_CLIPSIBLINGS,
        0,
        0,
        scrollbar_control_w,
        @max(1, self.layout_h),
        self.hwnd,
        null,
        GetModuleHandleW(null),
        null,
    ) orelse return error.Win32Error;
    self.scrollbar_hwnd = hwnd;
    _ = SetWindowLongPtrW(hwnd, GWLP_USERDATA, @bitCast(@intFromPtr(self)));
    self.updateScrollbarOverlayRect();
}

fn registerScrollbarClass() !void {
    if (scrollbar_class_registered) return;
    const class_name = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyScrollbar");
    const hinstance = GetModuleHandleW(null);
    var wc: WNDCLASSEXW = std.mem.zeroes(WNDCLASSEXW);
    wc.cbSize = @sizeOf(WNDCLASSEXW);
    wc.style = 0x0002 | 0x0001;
    wc.lpfnWndProc = scrollbarWndProc;
    wc.hInstance = hinstance;
    wc.hCursor = LoadCursorW(null, @ptrFromInt(32512));
    wc.lpszClassName = class_name;
    if (RegisterClassExW(&wc) == 0) return error.Win32Error;
    scrollbar_class_registered = true;
}

fn registerProgressClass() !void {
    if (progress_class_registered) return;
    const class_name = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyProgressOverlay");
    const hinstance = GetModuleHandleW(null);
    var wc: WNDCLASSEXW = std.mem.zeroes(WNDCLASSEXW);
    wc.cbSize = @sizeOf(WNDCLASSEXW);
    wc.style = 0x0002 | 0x0001;
    wc.lpfnWndProc = progressWndProc;
    wc.hInstance = hinstance;
    wc.hCursor = LoadCursorW(null, @ptrFromInt(32512));
    wc.lpszClassName = class_name;
    if (RegisterClassExW(&wc) == 0) return error.Win32Error;
    progress_class_registered = true;
}

/// Disable VSync via WGL extension for lower input latency.
pub fn disableVSync(_: *Self) void {
    if (comptime build_config.renderer != .opengl) return;
    const func: ?*const fn (i32) callconv(.winapi) i32 = @ptrCast(OpenGL.wglGetProcAddress("wglSwapIntervalEXT"));
    if (func) |setInterval| {
        _ = setInterval(0);
    }
}

/// Set the mouse cursor shape. Called from performAction.
pub fn setMouseShape(self: *Self, shape: @import("../../terminal/main.zig").MouseShape) void {
    _ = self;
    const cursor_name: ?[*:0]align(1) const u16 = switch (shape) {
        .text, .vertical_text, .cell => @ptrFromInt(32513), // IDC_IBEAM
        .pointer => @ptrFromInt(32649), // IDC_HAND
        .wait, .progress => @ptrFromInt(32514), // IDC_WAIT
        .crosshair => @ptrFromInt(32515), // IDC_CROSS
        .not_allowed, .no_drop => @ptrFromInt(32648), // IDC_NO
        .move, .all_scroll => @ptrFromInt(32646), // IDC_SIZEALL
        .ns_resize, .n_resize, .s_resize, .row_resize => @ptrFromInt(32645), // IDC_SIZENS
        .ew_resize, .e_resize, .w_resize, .col_resize => @ptrFromInt(32644), // IDC_SIZEWE
        .nesw_resize, .ne_resize, .sw_resize => @ptrFromInt(32643), // IDC_SIZENESW
        .nwse_resize, .nw_resize, .se_resize => @ptrFromInt(32642), // IDC_SIZENWSE
        .help => @ptrFromInt(32651), // IDC_HELP
        else => @ptrFromInt(32512), // IDC_ARROW
    };
    const cursor = LoadCursorW(null, cursor_name);
    _ = SetCursor(cursor);
}

pub fn setMouseVisibility(self: *Self, visible: bool) void {
    _ = self;
    _ = ShowCursor(if (visible) 1 else 0);
}

extern "user32" fn LoadCursorW(hInstance: ?*anyopaque, lpCursorName: ?[*:0]align(1) const u16) callconv(.winapi) ?*anyopaque;
extern "user32" fn SetCursor(hCursor: ?*anyopaque) callconv(.winapi) ?*anyopaque;
extern "user32" fn ShowCursor(bShow: i32) callconv(.winapi) i32;

/// Update the OpenGL viewport to match the current window size.
/// Called from the renderer thread before each frame.
pub fn updateViewport(self: *Self) void {
    if (comptime build_config.renderer != .opengl) return;
    OpenGL.glViewport(0, 0, @intCast(self.width), @intCast(self.height));
}

/// Make the WGL context current on the calling thread.
pub fn makeContextCurrent(self: *Self) void {
    if (comptime build_config.renderer != .opengl) return;
    if (self.hdc != null and self.hglrc != null) {
        _ = OpenGL.wglMakeCurrent(self.hdc, self.hglrc);
    }
}

/// Release the WGL context from the calling thread.
pub fn releaseContext() void {
    if (comptime build_config.renderer != .opengl) return;
    _ = OpenGL.wglMakeCurrent(null, null);
}

/// Release context from the main thread before handing off to renderer thread.
pub fn releaseMainThreadContext(self: *Self) void {
    _ = self;
    if (comptime build_config.renderer != .opengl) return;
    _ = OpenGL.wglMakeCurrent(null, null);
}

pub fn setLayoutRect(self: *Self, x: i32, y: i32, w: i32, h: i32) void {
    self.layout_x = x;
    self.layout_y = y;
    self.layout_w = w;
    self.layout_h = h;
    self.updateProgressOverlayRect();
    self.updateScrollbarOverlayRect();
}

pub fn syncRendererSize(self: *Self, core_surface: *CoreSurface, width: u32, height: u32, force: bool) void {
    if (width == 0 or height == 0) return;
    if (!force and self.last_renderer_w == width and self.last_renderer_h == height) return;

    self.last_renderer_w = width;
    self.last_renderer_h = height;
    var size = core_surface.size;
    size.screen = .{ .width = width, .height = height };
    _ = core_surface.renderer_thread.mailbox.push(.{
        .resize = size,
    }, .{ .forever = {} });
}

pub fn notePendingCoreResize(self: *Self, width: u32, height: u32) void {
    self.pending_core_resize_w = width;
    self.pending_core_resize_h = height;
}

pub fn commitCoreResize(self: *Self) void {
    if (self.pending_core_resize_w == 0 or self.pending_core_resize_h == 0) return;
    const width = self.pending_core_resize_w;
    const height = self.pending_core_resize_h;
    self.pending_core_resize_w = 0;
    self.pending_core_resize_h = 0;
    const core_surface = self.core_surface orelse return;
    core_surface.sizeCallback(.{
        .width = width,
        .height = height,
    }) catch |err| log.err("deferred size callback error: {}", .{err});
    self.syncRendererSize(core_surface, width, height, true);
}

pub fn setScrollbar(self: *Self, scrollbar: terminal.Scrollbar) void {
    self.scrollbar = scrollbar;
    self.updateScrollbarOverlayRect();
    self.invalidateScrollbarVisual();
}

pub fn refreshScrollbarOverlay(self: *Self) void {
    self.updateScrollbarOverlayRect();
}

pub fn hideScrollbarOverlay(self: *Self) void {
    self.scrollbar_drag = null;
    self.scrollbar_hovered = false;
    self.scrollbar_tracking_leave = false;
    if (self.scrollbar_hwnd) |hwnd| _ = ShowWindow(hwnd, SW_HIDE);
}

pub fn hasScrollbar(self: *const Self) bool {
    return self.scrollbar.total > self.scrollbar.len and self.scrollbar.total != 0;
}

pub fn scrollbarHitTest(self: *const Self, x: i32, y: i32) bool {
    _ = self;
    _ = x;
    _ = y;
    return false;
}

pub fn scrollbarInteractionHitTest(self: *const Self, x: i32, y: i32) bool {
    if (!self.hasScrollbar()) return false;
    const track = self.scrollbarTrackRect();
    return x >= track.left and x < track.right and y >= track.top and y < track.bottom;
}

pub fn scrollbarWindowHitTest(self: *const Self, x: i32, y: i32) bool {
    if (!self.hasScrollbar()) return false;
    const local_x = x - self.layout_x;
    const local_y = y - self.layout_y;
    return self.scrollbarInteractionHitTest(local_x, local_y);
}

fn scrollbarTrackRect(self: *const Self) RECT {
    const h = if (self.layout_h > 0) self.layout_h else @as(i32, @intCast(self.height));
    const left = self.scrollbarControlLeft();
    const right = self.scrollbarControlRight();
    return .{
        .left = left,
        .top = scrollbar_margin,
        .right = right,
        .bottom = @max(scrollbar_margin, h - scrollbar_margin),
    };
}

fn scrollbarControlLeft(self: *const Self) i32 {
    return @max(0, self.scrollbarControlRight() - scrollbar_control_w);
}

fn scrollbarControlRight(self: *const Self) i32 {
    const w = if (self.layout_w > 0) self.layout_w else @as(i32, @intCast(self.width));
    return @max(0, w - self.scrollbarResizeGutter());
}

pub fn scrollbarResizeGutter(self: *const Self) i32 {
    _ = self;
    return 0;
}

fn scrollToScrollbarOffset(self: *Self, target: usize) void {
    const core_surface = self.core_surface orelse return;
    core_surface.renderer_state.mutex.lock();
    core_surface.io.terminal.screens.active.scroll(.{ .row = target });
    core_surface.renderer_state.mutex.unlock();
    core_surface.refreshCallback() catch |err| log.warn("scrollbar drag render failed err={}", .{err});
}

fn updateScrollbarOverlayRect(self: *Self) void {
    const hwnd = self.scrollbar_hwnd orelse return;
    if (self.window) |window| {
        if (window.in_window_resize) {
            self.hideScrollbarOverlay();
            return;
        }
    }
    if (!self.hasScrollbar() or self.layout_w <= scrollbar_control_w or self.layout_h <= 0) {
        self.hideScrollbarOverlay();
        return;
    }
    const track = self.scrollbarTrackRect();
    const width = @max(1, track.right - track.left);
    const height = @max(1, track.bottom - track.top);
    const flags = SWP_NOACTIVATE | SWP_SHOWWINDOW;
    _ = SetWindowPos(hwnd, HWND_TOP, track.left, track.top, width, height, flags);
    self.invalidateScrollbar();
    _ = UpdateWindow(hwnd);
}

fn invalidateScrollbar(self: *Self) void {
    if (self.scrollbar_hwnd) |hwnd| {
        _ = InvalidateRect(hwnd, null, 0);
    }
    self.invalidateScrollbarVisual();
}

fn invalidateScrollbarVisual(self: *Self) void {
    _ = InvalidateRect(self.hwnd, null, 0);
    const core_surface = self.core_surface orelse return;
    core_surface.refreshCallback() catch |err| log.warn("scrollbar render refresh failed err={}", .{err});
}

pub fn isScrollbarDragging(self: *const Self) bool {
    return self.scrollbar_drag != null;
}

pub fn scrollbarDrawHovered(self: *const Self) bool {
    return self.scrollbar_hovered or self.scrollbar_drag != null;
}

pub fn clearScrollbarHover(self: *Self) void {
    if (self.scrollbar_drag != null or !self.scrollbar_hovered) return;
    self.scrollbar_hovered = false;
    self.invalidateScrollbar();
}

pub fn handleScrollbarMouseMove(self: *Self, y: i32) void {
    if (self.scrollbar_drag != null) {
        self.scrollbarDragTo(y);
        return;
    }
    if (!self.scrollbar_hovered) {
        self.scrollbar_hovered = true;
        self.invalidateScrollbar();
    }
}

pub fn handleScrollbarMouseDown(self: *Self, hwnd: HWND, y: i32) void {
    if (!self.hasScrollbar()) return;
    const thumb = self.scrollbarThumbRect();
    if (y >= thumb.top and y < thumb.bottom) {
        self.scrollbar_drag = .{ .grab_y = y - thumb.top };
        self.scrollbar_hovered = true;
        _ = SetCapture(hwnd);
        self.invalidateScrollbar();
    } else if (y < thumb.top) {
        self.scrollbarApplyOffset(self.scrollbar.offset -| self.scrollbar.len);
    } else {
        self.scrollbarApplyOffset(self.scrollbar.offset + self.scrollbar.len);
    }
}

pub fn handleScrollbarMouseUp(self: *Self) bool {
    if (self.scrollbar_drag == null) return false;
    self.scrollbar_drag = null;
    _ = ReleaseCapture();
    self.invalidateScrollbar();
    return true;
}

pub fn handleScrollbarWheel(self: *Self, wparam: usize) bool {
    if (!self.hasScrollbar()) return false;
    const delta = wheelDelta(wparam);
    const steps_i32 = @max(1, @divTrunc(@abs(delta), WHEEL_DELTA));
    const rows: usize = @intCast(steps_i32 * @as(i32, @intCast(scrollbar_wheel_rows)));
    if (delta > 0) {
        self.scrollbarApplyOffset(self.scrollbar.offset -| rows);
    } else if (delta < 0) {
        self.scrollbarApplyOffset(self.scrollbar.offset + rows);
    }
    return true;
}

fn handleScrollbarMessage(self: *Self, hwnd: HWND, msg: u32, wparam: usize, lparam: isize) isize {
    switch (msg) {
        WM_NCHITTEST => {
            if (self.scrollbarResizeHit(lparam)) return HTTRANSPARENT;
            return sys.HTCLIENT;
        },
        WM_ERASEBKGND => return 1,
        WM_PAINT => {
            self.paintScrollbar(hwnd);
            return 0;
        },
        WM_SETCURSOR => {
            const cursor = LoadCursorW(null, @ptrFromInt(32512));
            _ = SetCursor(cursor);
            return 1;
        },
        WM_MOUSEMOVE => {
            const y = lparamY(lparam);
            if (self.scrollbar_drag != null) {
                self.scrollbarDragTo(y);
                return 0;
            }
            if (!self.scrollbar_hovered) {
                self.scrollbar_hovered = true;
                self.invalidateScrollbar();
            }
            self.trackScrollbarMouseLeave(hwnd);
            return 0;
        },
        sys.WM_MOUSELEAVE => {
            self.scrollbar_tracking_leave = false;
            if (self.scrollbar_drag == null and self.scrollbar_hovered) {
                self.scrollbar_hovered = false;
                self.invalidateScrollbar();
            }
            return 0;
        },
        WM_LBUTTONDOWN => {
            if (self.forwardResizeDrag(hwnd, lparam)) return 0;
            if (!self.hasScrollbar()) return 0;
            const y = lparamY(lparam);
            const thumb = self.scrollbarThumbRect();
            if (y >= thumb.top and y < thumb.bottom) {
                self.scrollbar_drag = .{ .grab_y = y - thumb.top };
                self.scrollbar_hovered = true;
                _ = SetCapture(hwnd);
                self.invalidateScrollbar();
            } else if (y < thumb.top) {
                self.scrollbarApplyOffset(self.scrollbar.offset -| self.scrollbar.len);
            } else {
                self.scrollbarApplyOffset(self.scrollbar.offset + self.scrollbar.len);
            }
            return 0;
        },
        WM_LBUTTONUP => {
            if (self.scrollbar_drag != null) {
                self.scrollbar_drag = null;
                _ = ReleaseCapture();
                self.invalidateScrollbar();
            }
            return 0;
        },
        WM_CAPTURECHANGED => {
            if (self.scrollbar_drag != null) {
                self.scrollbar_drag = null;
                self.invalidateScrollbar();
            }
            return 0;
        },
        WM_MOUSEWHEEL => {
            if (!self.hasScrollbar()) return 0;
            const delta = wheelDelta(wparam);
            const steps_i32 = @max(1, @divTrunc(@abs(delta), WHEEL_DELTA));
            const rows: usize = @intCast(steps_i32 * @as(i32, @intCast(scrollbar_wheel_rows)));
            if (delta > 0) {
                self.scrollbarApplyOffset(self.scrollbar.offset -| rows);
            } else if (delta < 0) {
                self.scrollbarApplyOffset(self.scrollbar.offset + rows);
            }
            return 0;
        },
        else => return DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

fn trackScrollbarMouseLeave(self: *Self, hwnd: HWND) void {
    if (self.scrollbar_tracking_leave) return;
    var tme: sys.TRACKMOUSEEVENT = .{
        .cbSize = @sizeOf(sys.TRACKMOUSEEVENT),
        .dwFlags = sys.TME_LEAVE,
        .hwndTrack = hwnd,
        .dwHoverTime = 0,
    };
    if (sys.TrackMouseEvent(&tme) != 0) self.scrollbar_tracking_leave = true;
}

fn paintScrollbar(self: *Self, hwnd: HWND) void {
    var ps: PAINTSTRUCT = std.mem.zeroes(PAINTSTRUCT);
    const hdc = BeginPaint(hwnd, &ps);
    defer _ = EndPaint(hwnd, &ps);

    var rect: RECT = std.mem.zeroes(RECT);
    _ = GetClientRect(hwnd, &rect);
    fillRectColor(hdc, rect, 0x002C2C2C);

    if (!self.hasScrollbar()) return;
    const thumb = self.scrollbarThumbRect();
    if (thumb.bottom <= thumb.top or thumb.right <= thumb.left) return;

    const color: u32 = if (self.scrollbar_drag != null)
        0x00F0F0F0
    else if (self.scrollbar_hovered)
        0x00D0D0D0
    else
        0x00A8A8A8;
    fillRectColor(hdc, thumb, color);
}

fn fillRectColor(hdc: HDC, rect: RECT, color: u32) void {
    const brush = CreateSolidBrush(color);
    if (brush != null) {
        _ = FillRect(hdc, &rect, brush);
        _ = DeleteObject(brush);
    }
}

fn scrollbarThumbRect(self: *const Self) RECT {
    var rect: RECT = .{ .left = 0, .top = 0, .right = scrollbar_control_w, .bottom = @max(1, self.layout_h - scrollbar_margin * 2) };
    if (self.scrollbar_hwnd) |hwnd| _ = GetClientRect(hwnd, &rect);

    const track_h = @max(1, rect.bottom - rect.top);
    const total_f: f32 = @floatFromInt(self.scrollbar.total);
    const len_f: f32 = @floatFromInt(self.scrollbar.len);
    const visible_ratio = if (self.scrollbar.total == 0) 1.0 else @min(1.0, len_f / total_f);
    const thumb_h: i32 = @max(scrollbar_thumb_min_h, @as(i32, @intFromFloat(@as(f32, @floatFromInt(track_h)) * visible_ratio)));
    const travel = @max(0, track_h - thumb_h);
    const max_offset = self.maxScrollbarOffset();
    const offset_ratio: f32 = if (max_offset == 0) 0.0 else @as(f32, @floatFromInt(self.scrollbar.offset)) / @as(f32, @floatFromInt(max_offset));
    const top = rect.top + @as(i32, @intFromFloat(@as(f32, @floatFromInt(travel)) * @min(1.0, offset_ratio)));
    const thumb_w = if (self.scrollbar_hovered or self.scrollbar_drag != null) scrollbar_hover_thumb_w else scrollbar_idle_thumb_w;
    const right = rect.right - 2;
    return .{
        .left = @max(rect.left, right - thumb_w),
        .top = top,
        .right = right,
        .bottom = @min(rect.bottom, top + thumb_h),
    };
}

fn scrollbarDragTo(self: *Self, y: i32) void {
    const drag = self.scrollbar_drag orelse return;
    var rect: RECT = .{ .left = 0, .top = 0, .right = scrollbar_control_w, .bottom = @max(1, self.layout_h - scrollbar_margin * 2) };
    if (self.scrollbar_hwnd) |hwnd| _ = GetClientRect(hwnd, &rect);
    const thumb = self.scrollbarThumbRect();
    const thumb_h = @max(1, thumb.bottom - thumb.top);
    const travel = @max(1, (rect.bottom - rect.top) - thumb_h);
    const raw_top = std.math.clamp(y - drag.grab_y - rect.top, 0, travel);
    const ratio = @as(f32, @floatFromInt(raw_top)) / @as(f32, @floatFromInt(travel));
    const target_f = ratio * @as(f32, @floatFromInt(self.maxScrollbarOffset()));
    self.scrollbarApplyOffset(@intFromFloat(target_f + 0.5));
}

fn scrollbarResizeHit(self: *Self, lparam: isize) bool {
    const window = self.window orelse return false;
    const hit = window.hitTestPoint(signExtendLowWord(lparam), signExtendHighWord(lparam));
    return window.isResizeHit(hit);
}

fn forwardResizeDrag(self: *Self, hwnd: HWND, lparam: isize) bool {
    const window = self.window orelse return false;
    const top_hwnd = window.hwnd orelse return false;
    var pt: sys.POINT = .{ .x = lparamX(lparam), .y = lparamY(lparam) };
    if (ClientToScreen(hwnd, &pt) == 0) return false;
    const hit = window.hitTestPoint(pt.x, pt.y);
    if (!window.isResizeHit(hit)) return false;
    _ = ReleaseCapture();
    _ = sys.SendMessageW(top_hwnd, sys.WM_NCLBUTTONDOWN, @intCast(hit), packMousePoint(pt.x, pt.y));
    return true;
}

fn scrollbarApplyOffset(self: *Self, target: usize) void {
    const offset = @min(target, self.maxScrollbarOffset());
    if (offset == self.scrollbar.offset) return;
    self.scrollbar.offset = offset;
    self.invalidateScrollbar();
    self.scrollToScrollbarOffset(offset);
}

fn maxScrollbarOffset(self: *const Self) usize {
    if (self.scrollbar.total <= self.scrollbar.len) return 0;
    return self.scrollbar.total - self.scrollbar.len;
}

fn lparamX(lparam: isize) i32 {
    return @as(i16, @bitCast(@as(u16, @truncate(@as(usize, @bitCast(lparam))))));
}

fn lparamY(lparam: isize) i32 {
    return @as(i16, @bitCast(@as(u16, @truncate(@as(usize, @bitCast(lparam)) >> 16))));
}

fn wheelDelta(wparam: usize) i32 {
    return @as(i16, @bitCast(@as(u16, @truncate(wparam >> 16))));
}

fn signExtendLowWord(value: isize) i32 {
    return @as(i16, @bitCast(@as(u16, @truncate(@as(usize, @bitCast(value))))));
}

fn signExtendHighWord(value: isize) i32 {
    return @as(i16, @bitCast(@as(u16, @truncate(@as(usize, @bitCast(value)) >> 16))));
}

fn packMousePoint(x: i32, y: i32) isize {
    const lo: u16 = @bitCast(@as(i16, @truncate(x)));
    const hi: u16 = @bitCast(@as(i16, @truncate(y)));
    const value: u32 = @as(u32, lo) | (@as(u32, hi) << 16);
    return @bitCast(@as(usize, value));
}

pub fn setVisible(self: *Self, visible: bool) void {
    _ = ShowWindow(self.hwnd, if (visible) SW_SHOWNORMAL else SW_HIDE);
    if (self.progress_hwnd) |hwnd| {
        _ = ShowWindow(hwnd, if (visible and self.progress_visible) SW_SHOWNORMAL else SW_HIDE);
    }
    if (visible) {
        self.updateScrollbarOverlayRect();
    } else if (self.scrollbar_hwnd) |hwnd| {
        _ = ShowWindow(hwnd, SW_HIDE);
    }
}

pub fn setProgressReport(self: *Self, value: terminal.osc.Command.ProgressReport) void {
    const app = self.app orelse return;
    if (!app.config.@"progress-style") {
        self.hideProgressOverlay();
        return;
    }

    self.stopProgressTimers();
    switch (value.state) {
        .remove => {
            self.hideProgressOverlay();
            return;
        },
        .set, .@"error", .pause, .indeterminate => {
            self.progress_state = value.state;
            self.progress_value = value.progress;
            self.progress_phase = 0;
            self.progress_visible = true;
            if (value.state == .indeterminate or ((value.state == .set or value.state == .@"error") and value.progress == null)) {
                _ = SetTimer(self.progress_hwnd, progress_pulse_timer_id, progress_pulse_ms, null);
            }
            _ = SetTimer(self.progress_hwnd, progress_timeout_timer_id, progress_timeout_ms, null);
            self.updateProgressOverlayRect();
            if (self.progress_hwnd) |hwnd| {
                _ = ShowWindow(hwnd, SW_SHOWNORMAL);
                _ = InvalidateRect(hwnd, null, 0);
            }
        },
    }
}

fn hideProgressOverlay(self: *Self) void {
    self.stopProgressTimers();
    self.progress_visible = false;
    self.progress_state = .remove;
    self.progress_value = null;
    if (self.progress_hwnd) |hwnd| _ = ShowWindow(hwnd, SW_HIDE);
}

fn stopProgressTimers(self: *Self) void {
    if (self.progress_hwnd) |hwnd| {
        _ = KillTimer(hwnd, progress_timeout_timer_id);
        _ = KillTimer(hwnd, progress_pulse_timer_id);
    }
}

fn updateProgressOverlayRect(self: *Self) void {
    const hwnd = self.progress_hwnd orelse return;
    if (!self.progress_visible or self.layout_w <= 0) {
        _ = ShowWindow(hwnd, SW_HIDE);
        return;
    }
    _ = SetWindowPos(hwnd, null, 0, 0, self.layout_w, progress_overlay_height, 0x0004);
}

fn paintProgress(self: *Self, hwnd: HWND) void {
    var ps: PAINTSTRUCT = std.mem.zeroes(PAINTSTRUCT);
    const hdc = BeginPaint(hwnd, &ps);
    defer _ = EndPaint(hwnd, &ps);

    var rect: RECT = std.mem.zeroes(RECT);
    _ = GetClientRect(hwnd, &rect);

    const trough = CreateSolidBrush(0x00C8C8C8);
    if (trough != null) {
        _ = FillRect(hdc, &rect, trough);
        _ = DeleteObject(trough);
    }

    var fill = rect;
    switch (self.progress_state) {
        .indeterminate => {
            const span = @max(24, @divTrunc(rect.right - rect.left, 4));
            const travel = @max(1, (rect.right - rect.left) + span);
            const start = @mod(@as(i32, self.progress_phase) * 6, travel) - span;
            fill.left = std.math.clamp(start, rect.left, rect.right);
            fill.right = std.math.clamp(start + span, rect.left, rect.right);
        },
        .set, .@"error", .pause => {
            const progress: u8 = self.progress_value orelse if (self.progress_state == .pause) @as(u8, 100) else @as(u8, 0);
            fill.right = rect.left + @divTrunc((rect.right - rect.left) * progress, 100);
        },
        .remove => return,
    }
    if (fill.right <= fill.left) return;

    const brush = CreateSolidBrush(switch (self.progress_state) {
        .@"error" => 0x002020E0,
        else => 0x0000A0FF,
    });
    if (brush != null) {
        _ = FillRect(hdc, &fill, brush);
        _ = DeleteObject(brush);
    }
}

// --- Interface methods required by CoreSurface ---

pub fn getContentScale(self: *const Self) !apprt.ContentScale {
    const dpi = GetDpiForWindow(self.hwnd);
    if (dpi == 0) return .{ .x = 1.0, .y = 1.0 };
    const scale: f32 = @as(f32, @floatFromInt(dpi)) / 96.0;
    return .{ .x = scale, .y = scale };
}

extern "user32" fn GetDpiForWindow(hWnd: HWND) callconv(.winapi) u32;

pub fn getSize(self: *const Self) !apprt.SurfaceSize {
    return .{
        .width = self.width,
        .height = self.height,
    };
}

pub fn getCursorPos(self: *const Self) !apprt.CursorPos {
    return self.cursor_pos;
}

pub fn getTitle(self: *Self) ?[:0]const u8 {
    const window = self.window orelse return null;
    const hwnd = window.hwnd orelse return null;

    var title_utf16: [512]u16 = undefined;
    const len = GetWindowTextW(hwnd, &title_utf16, title_utf16.len);
    if (len <= 0) return null;

    const title_slice: []const u16 = title_utf16[0..@intCast(len)];
    const out_len = std.unicode.utf16LeToUtf8(self.title_buf[0 .. self.title_buf.len - 1], title_slice) catch
        return null;
    self.title_buf[out_len] = 0;
    return self.title_buf[0..out_len :0];
}

pub fn close(self: *Self, process_active: bool) void {
    _ = process_active; // Core already gated on needsConfirmQuit
    // Ask the window to remove this surface from the tree, destroying the
    // child window. If this is the last surface in the last window, the
    // app will quit.
    if (self.window) |window| {
        window.closeSurface(self);
    } else {
        PostQuitMessage(0);
    }
}

extern "user32" fn MessageBoxW(hWnd: ?HWND, lpText: [*:0]const u16, lpCaption: [*:0]const u16, uType: u32) callconv(.winapi) c_int;
extern "user32" fn PostQuitMessage(nExitCode: c_int) callconv(.winapi) void;
extern "user32" fn GetWindowTextW(hWnd: HWND, lpString: [*]u16, nMaxCount: c_int) callconv(.winapi) c_int;

pub fn supportsClipboard(_: *Self, _: apprt.Clipboard) bool {
    // Windows has only one clipboard; alias selection/primary to standard.
    return true;
}

pub fn clipboardRequest(
    self: *Self,
    _: apprt.Clipboard,
    req: apprt.ClipboardRequest,
) !bool {
    const surface = self.core_surface orelse return false;

    // Try to read text from the Win32 clipboard synchronously
    if (OpenClipboard(self.hwnd) == 0) return false;
    defer _ = CloseClipboard();

    const CF_UNICODETEXT: UINT = 13;
    const handle = GetClipboardData(CF_UNICODETEXT);
    if (handle == null) return false;

    const ptr: ?[*:0]const u16 = @ptrCast(@alignCast(GlobalLock(handle)));
    if (ptr == null) return false;
    defer _ = GlobalUnlock(handle);

    // Convert UTF-16 to UTF-8
    const alloc = if (self.app) |app| app.alloc else std.heap.page_allocator;
    const utf8 = std.unicode.utf16LeToUtf8AllocZ(alloc, std.mem.span(ptr.?)) catch return false;
    defer alloc.free(utf8);

    try surface.completeClipboardRequest(req, utf8, true);
    return true;
}

pub fn setClipboard(
    self: *Self,
    _: apprt.Clipboard,
    contents: []const apprt.ClipboardContent,
    _: bool,
) !void {
    if (contents.len == 0) return;

    const text = contents[0].data;
    const alloc = if (self.app) |app| app.alloc else std.heap.page_allocator;

    // Convert UTF-8 to UTF-16
    const utf16 = try std.unicode.utf8ToUtf16LeAllocZ(alloc, text);
    defer alloc.free(utf16);

    const byte_len = (utf16.len + 1) * 2; // include null terminator
    const GMEM_MOVEABLE: UINT = 0x0002;
    const hmem = GlobalAlloc(GMEM_MOVEABLE, byte_len);
    if (hmem == null) return;

    const dst: ?[*]u16 = @ptrCast(@alignCast(GlobalLock(hmem)));
    if (dst == null) {
        _ = GlobalFree(hmem);
        return;
    }
    @memcpy(dst.?[0..utf16.len], utf16);
    dst.?[utf16.len] = 0;
    _ = GlobalUnlock(hmem);

    if (OpenClipboard(self.hwnd) == 0) {
        _ = GlobalFree(hmem);
        return;
    }
    _ = EmptyClipboard();
    const CF_UNICODETEXT: UINT = 13;
    _ = SetClipboardData(CF_UNICODETEXT, hmem);
    _ = CloseClipboard();
}

pub fn defaultTermioEnv(self: *Self) !std.process.EnvMap {
    const alloc = if (self.app) |app| app.alloc else std.heap.page_allocator;
    return try @import("../../os/main.zig").getEnvMap(alloc);
}

pub fn redrawInspector(self: *Self) void {
    _ = InvalidateRect(self.hwnd, null, 0);
}
