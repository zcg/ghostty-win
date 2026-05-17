//! A single top-level Win32 window. Each Window owns one HWND and a set of
//! tabs. Every tab owns its own split tree and active surface state.
const Window = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const apprt = @import("../../apprt.zig");
const configpkg = @import("../../config.zig");
const CoreSurface = @import("../../Surface.zig");
const Surface = @import("Surface.zig");
const SplitTree = @import("SplitTree.zig");
const d2d = @import("d2d.zig");
const sys = @import("sys.zig");

const App = @import("App.zig");

const HWND = sys.HWND;
const RECT = sys.RECT;
const BOOL = sys.BOOL;
const UINT = sys.UINT;
const DWORD = sys.DWORD;
const LPARAM = sys.LPARAM;
const WPARAM = sys.WPARAM;
const LRESULT = sys.LRESULT;
const HDC = ?*anyopaque;

const ClientInset = struct {
    left: i32 = 0,
    top: i32 = 0,
    right: i32 = 0,
    bottom: i32 = 0,
};

const WS_CHILD: u32 = 0x40000000;
const WS_VISIBLE: u32 = 0x10000000;
const WM_PAINT: UINT = 0x000F;
const WM_LBUTTONDOWN: UINT = 0x0201;
const WM_LBUTTONUP: UINT = 0x0202;
const WM_RBUTTONDOWN: UINT = 0x0204;
const WM_MOUSEMOVE: UINT = 0x0200;
const WM_CAPTURECHANGED: UINT = 0x0215;
const WM_SETCURSOR: UINT = 0x0020;
const WM_NCHITTEST: UINT = 0x0084;
pub const WM_ENTERSIZEMOVE: UINT = 0x0231;
pub const WM_EXITSIZEMOVE: UINT = 0x0232;
const SW_HIDE: c_int = 0;
const TOP_BAR_HEIGHT: i32 = 46;
const DIVIDER_THICKNESS: i32 = 10;
const TOPLEVEL_STYLE: DWORD = sys.WS_OVERLAPPED | sys.WS_THICKFRAME | sys.WS_MINIMIZEBOX | sys.WS_MAXIMIZEBOX;
const CUSTOM_TAB_WIDTH: i32 = 360;
const NEW_TAB_WIDTH: i32 = 44;
const DROPDOWN_WIDTH: i32 = 38;
const WINDOW_BUTTON_WIDTH: i32 = 46;
const WINDOW_BUTTON_COUNT: i32 = 3;
const TAB_START_X: i32 = 10;
const TAB_TOP: i32 = 8;
const TAB_BOTTOM: i32 = 45;
const TAB_GAP: i32 = 1;
const TAB_CLOSE_WIDTH: i32 = 34;
const MIN_TAB_WIDTH: i32 = 100;
const TAB_TEXT_MARGIN_LEFT: i32 = 16;
const TAB_TEXT_MARGIN_RIGHT: i32 = 8;
const COMPACT_WIDTH: i32 = 90;
const TITLE_MIN_WIDTH: i32 = 100;
const TITLE_MAX_WIDTH: i32 = 350;

const TabWidthMode = enum {
    equal,
    compact,
    title,
};
const TAB_ACTION_TOP: i32 = 7;
const TITLE_ICON_SIZE: f32 = 12.0;
const TITLE_BUTTON_HIT_HEIGHT: i32 = TOP_BAR_HEIGHT;
const TITLE_HOVER_ALPHA: f32 = 0.24;
const TITLE_PRESSED_ALPHA: f32 = 0.34;
const CLOSE_HOVER: configpkg.Config.Color = .{ .r = 232, .g = 17, .b = 35 };
const CLOSE_PRESSED: configpkg.Config.Color = .{ .r = 184, .g = 14, .b = 28 };
const IDC_SIZEWE = @as(?[*:0]align(1) const u16, @ptrFromInt(32644));
const IDC_SIZENS = @as(?[*:0]align(1) const u16, @ptrFromInt(32645));

const HWND_TOP: ?HWND = @ptrFromInt(@as(usize, @bitCast(@as(isize, 0))));
const SWP_NOACTIVATE: UINT = 0x0010;

extern "gdi32" fn CreateSolidBrush(color: u32) callconv(.winapi) ?*anyopaque;
extern "gdi32" fn DeleteObject(ho: ?*anyopaque) callconv(.winapi) BOOL;
extern "user32" fn FillRect(hDC: ?*anyopaque, lprc: *const RECT, hbr: ?*anyopaque) callconv(.winapi) c_int;
extern "user32" fn SetCapture(hWnd: HWND) callconv(.winapi) ?HWND;
extern "user32" fn ReleaseCapture() callconv(.winapi) BOOL;
extern "user32" fn SetCursor(hCursor: sys.HCURSOR) callconv(.winapi) sys.HCURSOR;
extern "user32" fn ScreenToClient(hWnd: HWND, lpPoint: *sys.POINT) callconv(.winapi) BOOL;

var divider_class_registered: bool = false;
var title_bar_class_registered: bool = false;

const TitleIcon = enum {
    close_tab,
    new_tab,
    dropdown,
    minimize,
    maximize,
    restore,
    close_window,

    fn text(self: TitleIcon) []const u16 {
        return switch (self) {
            .close_tab, .close_window => &comptime utf16Icon(0xE8BB),
            .new_tab => &comptime utf16Icon(0xE710),
            .dropdown => &comptime utf16Icon(0xE70D),
            .minimize => &comptime utf16Icon(0xE921),
            .maximize => &comptime utf16Icon(0xE922),
            .restore => &comptime utf16Icon(0xE923),
        };
    }
};

const ProfileMenuCommand = enum(u16) {
    default = 1,
    cmd = 2,
    powershell = 3,
    pwsh = 4,
};

const TitleHit = union(enum) {
    none,
    drag,
    window_minimize,
    window_maximize,
    window_close,
    tab: usize,
    tab_close: usize,
    new_tab,
    dropdown,

    fn eql(a: TitleHit, b: TitleHit) bool {
        return switch (a) {
            .none => b == .none,
            .drag => b == .drag,
            .window_minimize => b == .window_minimize,
            .window_maximize => b == .window_maximize,
            .window_close => b == .window_close,
            .tab => |idx| b == .tab and b.tab == idx,
            .tab_close => |idx| b == .tab_close and b.tab_close == idx,
            .new_tab => b == .new_tab,
            .dropdown => b == .dropdown,
        };
    }
};

fn utf16Icon(comptime codepoint: u21) [1:0]u16 {
    return .{@intCast(codepoint)};
}

const TitleBarState = struct {
    hwnd: HWND,
    window: *Window,
    target: ?*d2d.ID2D1HwndRenderTarget = null,
    d2d_factory: ?*d2d.ID2D1Factory = null,
    dwrite_factory: ?*d2d.IDWriteFactory = null,
    text_format: ?*d2d.IDWriteTextFormat = null,
    tab_text_format: ?*d2d.IDWriteTextFormat = null,
    icon_format: ?*d2d.IDWriteTextFormat = null,
    hover: TitleHit = .none,
    pressed: TitleHit = .none,
    tracking_mouse_leave: bool = false,
    tracking_nc_mouse_leave: bool = false,

    fn handleMessage(self: *TitleBarState, hwnd: HWND, msg: UINT, wparam: WPARAM, lparam: LPARAM) LRESULT {
        switch (msg) {
            WM_PAINT => {
                self.paint(hwnd);
                return 0;
            },
            sys.WM_ERASEBKGND => return 1,
            sys.WM_SIZE => {
                self.resizeFromClient(hwnd);
                _ = sys.InvalidateRect(hwnd, null, 0);
                return 0;
            },
            WM_NCHITTEST => return self.hitTestTitleBar(lparam),
            WM_LBUTTONDOWN => {
                const hit = self.hitTestClient(lparamX(lparam), lparamY(lparam));
                self.pressed = hit;
                self.hover = hit;
                _ = sys.InvalidateRect(hwnd, null, 0);
                if (!self.activatePressedOnMouseUp(hit)) {
                    self.pressed = .none;
                    _ = sys.PostMessageW(self.window.hwnd.?, sys.WM_NCLBUTTONDOWN, @intCast(sys.HTCAPTION), 0);
                }
                return 0;
            },
            WM_LBUTTONUP => {
                const hit = self.hitTestClient(lparamX(lparam), lparamY(lparam));
                const pressed = self.pressed;
                self.pressed = .none;
                if (pressed.eql(hit)) self.performHit(hit);
                _ = sys.InvalidateRect(hwnd, null, 0);
                return 0;
            },
            WM_RBUTTONDOWN => {
                const hit = self.hitTestClient(lparamX(lparam), lparamY(lparam));
                switch (hit) {
                    .tab => |idx| self.showTabContextMenu(idx, lparamX(lparam), lparamY(lparam)),
                    else => {},
                }
                return 0;
            },
            WM_MOUSEMOVE => {
                const hit = self.hitTestClient(lparamX(lparam), lparamY(lparam));
                if (!self.hover.eql(hit)) {
                    self.hover = hit;
                    _ = sys.InvalidateRect(hwnd, null, 0);
                }
                self.trackMouseLeave();
                return 0;
            },
            sys.WM_NCMOUSEMOVE => {
                const hit = @as(LRESULT, @intCast(wparam));
                self.updateNonClientHover(hit);
                self.trackNonClientMouseLeave();
                return 0;
            },
            sys.WM_MOUSELEAVE => {
                self.tracking_mouse_leave = false;
                self.hover = .none;
                self.pressed = .none;
                _ = sys.InvalidateRect(hwnd, null, 0);
                return 0;
            },
            sys.WM_NCMOUSELEAVE => {
                self.tracking_nc_mouse_leave = false;
                self.hover = .none;
                self.pressed = .none;
                _ = sys.InvalidateRect(hwnd, null, 0);
                return 0;
            },
            sys.WM_NCLBUTTONDOWN => {
                const nc_hit = @as(LRESULT, @intCast(wparam));
                switch (nc_hit) {
                    sys.HTMINBUTTON => {
                        self.pressed = .window_minimize;
                        self.hover = .window_minimize;
                        _ = sys.InvalidateRect(hwnd, null, 0);
                        self.performHit(.window_minimize);
                        return 0;
                    },
                    sys.HTMAXBUTTON => {
                        self.pressed = .window_maximize;
                        self.hover = .window_maximize;
                        _ = sys.InvalidateRect(hwnd, null, 0);
                        self.performHit(.window_maximize);
                        return 0;
                    },
                    else => {},
                }
                return sys.DefWindowProcW(hwnd, msg, wparam, lparam);
            },
            sys.WM_NCLBUTTONUP => {
                self.pressed = .none;
                switch (@as(LRESULT, @intCast(wparam))) {
                    sys.HTMINBUTTON, sys.HTMAXBUTTON => _ = sys.InvalidateRect(hwnd, null, 0),
                    else => {},
                }
                return 0;
            },
            else => return sys.DefWindowProcW(hwnd, msg, wparam, lparam),
        }
    }

    fn activatePressedOnMouseUp(_: *TitleBarState, hit: TitleHit) bool {
        return switch (hit) {
            .drag, .none => false,
            else => true,
        };
    }

    fn hitTestTitleBar(self: *TitleBarState, lparam: LPARAM) LRESULT {
        const hwnd = self.window.hwnd orelse return sys.HTCLIENT;
        var rect: RECT = std.mem.zeroes(RECT);
        if (sys.GetWindowRect(hwnd, &rect) == 0) return sys.HTCLIENT;

        const x: i32 = signExtendLowWord(lparam);
        const y: i32 = signExtendHighWord(lparam);
        const button_area_left = rect.right - WINDOW_BUTTON_WIDTH * WINDOW_BUTTON_COUNT;
        if (x >= button_area_left and y < rect.top + TITLE_BUTTON_HIT_HEIGHT) {
            const idx = @divTrunc(x - button_area_left, WINDOW_BUTTON_WIDTH);
            return switch (idx) {
                0 => sys.HTMINBUTTON,
                1 => sys.HTMAXBUTTON,
                else => sys.HTCLIENT,
            };
        }

        return sys.HTCLIENT;
    }

    fn hitTestClient(self: *TitleBarState, x: i32, y: i32) TitleHit {
        const window = self.window;
        const hwnd = window.hwnd orelse return .none;
        var rect: RECT = std.mem.zeroes(RECT);
        if (sys.GetClientRect(hwnd, &rect) == 0) return .none;
        if (y < 0 or y >= window.tabClientHeight()) return .none;

        const button_area_left = rect.right - WINDOW_BUTTON_WIDTH * WINDOW_BUTTON_COUNT;
        if (x >= button_area_left) {
            const idx = @divTrunc(x - button_area_left, WINDOW_BUTTON_WIDTH);
            return switch (idx) {
                0 => .window_minimize,
                1 => .window_maximize,
                else => .window_close,
            };
        }

        const tab_count = window.tabs.items.len;
        const controls_right = button_area_left;
        const max_right = controls_right - NEW_TAB_WIDTH - DROPDOWN_WIDTH - 12;
        const available_width = max_right - TAB_START_X;
        const tw = tabWidth(tab_count, available_width);
        const format = self.tab_text_format orelse return .none;
        const factory = self.dwrite_factory orelse return .none;
        const mode = window.tab_width_mode;

        var tab_x: i32 = TAB_START_X;
        for (window.tabs.items, 0..) |tab, i| {
            if (tab_x >= max_right) break;
            const width = switch (mode) {
                .equal => @min(tw, max_right - tab_x),
                .compact => @min(COMPACT_WIDTH, max_right - tab_x),
                .title => blk: {
                    const text_w = measureTabTextWidth(factory, format, tab.title, window.app.alloc);
                    const desired = text_w + TAB_TEXT_MARGIN_LEFT + TAB_CLOSE_WIDTH + TAB_TEXT_MARGIN_RIGHT;
                    break :blk @min(@max(TITLE_MIN_WIDTH, desired), TITLE_MAX_WIDTH, max_right - tab_x);
                },
            };
            if (x >= tab_x and x < tab_x + width) {
                if (x >= tab_x + width - TAB_CLOSE_WIDTH) return .{ .tab_close = i };
                return .{ .tab = i };
            }
            tab_x += width + TAB_GAP;
        }

        if (x >= tab_x + 6 and x < tab_x + NEW_TAB_WIDTH) return .new_tab;
        if (x >= tab_x + NEW_TAB_WIDTH and x < tab_x + NEW_TAB_WIDTH + DROPDOWN_WIDTH) return .dropdown;
        return .drag;
    }

    fn performHit(self: *TitleBarState, hit: TitleHit) void {
        const window = self.window;
        const hwnd = window.hwnd orelse return;
        switch (hit) {
            .window_minimize => window.minimize(),
            .window_maximize => window.toggleMaximize(),
            .window_close => window.closeFromTitleBar(),
            .tab => |idx| window.activateTab(idx) catch {},
            .tab_close => |idx| _ = sys.PostMessageW(hwnd, sys.WM_APP_CLOSE_TAB, idx, 0),
            .new_tab => _ = sys.PostMessageW(hwnd, sys.WM_APP_NEW_TAB, 0, 0),
            .dropdown => window.showNewTabMenuFromTitleBar(),
            .drag, .none => {},
        }
    }

    fn showTabContextMenu(self: *TitleBarState, tab_index: usize, client_x: i32, client_y: i32) void {
        const menu = sys.CreatePopupMenu() orelse return;
        defer _ = sys.DestroyMenu(menu);

        const rename_label = std.unicode.utf8ToUtf16LeStringLiteral("Rename");
        const close_label = std.unicode.utf8ToUtf16LeStringLiteral("Close Tab");
        const sep_label = std.unicode.utf8ToUtf16LeStringLiteral("");
        const none_label = std.unicode.utf8ToUtf16LeStringLiteral("No Color");
        const red_label = std.unicode.utf8ToUtf16LeStringLiteral("Red");
        const green_label = std.unicode.utf8ToUtf16LeStringLiteral("Green");
        const blue_label = std.unicode.utf8ToUtf16LeStringLiteral("Blue");
        const yellow_label = std.unicode.utf8ToUtf16LeStringLiteral("Yellow");
        const purple_label = std.unicode.utf8ToUtf16LeStringLiteral("Purple");
        const orange_label = std.unicode.utf8ToUtf16LeStringLiteral("Orange");

        _ = sys.AppendMenuW(menu, sys.MF_STRING, 1, rename_label.ptr);
        _ = sys.AppendMenuW(menu, sys.MF_STRING, 2, close_label.ptr);
        _ = sys.AppendMenuW(menu, sys.MF_SEPARATOR, 0, sep_label.ptr);
        _ = sys.AppendMenuW(menu, sys.MF_STRING, 10, none_label.ptr);
        _ = sys.AppendMenuW(menu, sys.MF_STRING, 11, red_label.ptr);
        _ = sys.AppendMenuW(menu, sys.MF_STRING, 12, green_label.ptr);
        _ = sys.AppendMenuW(menu, sys.MF_STRING, 13, blue_label.ptr);
        _ = sys.AppendMenuW(menu, sys.MF_STRING, 14, yellow_label.ptr);
        _ = sys.AppendMenuW(menu, sys.MF_STRING, 15, purple_label.ptr);
        _ = sys.AppendMenuW(menu, sys.MF_STRING, 16, orange_label.ptr);

        var pt: sys.POINT = .{ .x = client_x, .y = client_y };
        _ = sys.ClientToScreen(self.hwnd, &pt);

        const cmd = sys.TrackPopupMenu(menu, sys.TPM_RETURNCMD | sys.TPM_LEFTALIGN | sys.TPM_TOPALIGN, pt.x, pt.y, 0, self.hwnd, null);
        const window = self.window;
        if (window.tabs.items.len <= tab_index) return;
        switch (cmd) {
            1 => {
                window.activateTab(tab_index) catch {};
                const core = window.tabs.items[tab_index].primary_surface.core_surface orelse return;
                _ = window.app.performAction(.{ .surface = core }, .prompt_title, .tab) catch {};
            },
            2 => {
                if (window.hwnd) |hwnd| {
                    _ = sys.PostMessageW(hwnd, sys.WM_APP_CLOSE_TAB, tab_index, 0);
                }
            },
            10 => window.setTabColor(tab_index, null),
            11 => window.setTabColor(tab_index, .{ .r = 255, .g = 80, .b = 80 }),
            12 => window.setTabColor(tab_index, .{ .r = 80, .g = 200, .b = 80 }),
            13 => window.setTabColor(tab_index, .{ .r = 80, .g = 130, .b = 255 }),
            14 => window.setTabColor(tab_index, .{ .r = 230, .g = 200, .b = 80 }),
            15 => window.setTabColor(tab_index, .{ .r = 180, .g = 100, .b = 220 }),
            16 => window.setTabColor(tab_index, .{ .r = 230, .g = 140, .b = 60 }),
            else => {},
        }
    }

    fn trackMouseLeave(self: *TitleBarState) void {
        if (self.tracking_mouse_leave) return;
        var event: sys.TRACKMOUSEEVENT = .{
            .cbSize = @sizeOf(sys.TRACKMOUSEEVENT),
            .dwFlags = sys.TME_LEAVE,
            .hwndTrack = self.hwnd,
            .dwHoverTime = 0,
        };
        if (sys.TrackMouseEvent(&event) != 0) self.tracking_mouse_leave = true;
    }

    fn trackNonClientMouseLeave(self: *TitleBarState) void {
        if (self.tracking_nc_mouse_leave) return;
        var event: sys.TRACKMOUSEEVENT = .{
            .cbSize = @sizeOf(sys.TRACKMOUSEEVENT),
            .dwFlags = sys.TME_LEAVE | sys.TME_NONCLIENT,
            .hwndTrack = self.hwnd,
            .dwHoverTime = 0,
        };
        if (sys.TrackMouseEvent(&event) != 0) self.tracking_nc_mouse_leave = true;
    }

    fn updateNonClientHover(self: *TitleBarState, hit: LRESULT) void {
        const next = hitForNcButton(hit);
        if (!self.hover.eql(next)) {
            self.hover = next;
            _ = sys.InvalidateRect(self.hwnd, null, 0);
        }
    }

    fn paint(self: *TitleBarState, hwnd: HWND) void {
        var ps: sys.PAINTSTRUCT = std.mem.zeroes(sys.PAINTSTRUCT);
        _ = sys.BeginPaint(hwnd, &ps);
        defer _ = sys.EndPaint(hwnd, &ps);

        self.render() catch {
            self.releaseDeviceResources();
        };
    }

    fn render(self: *TitleBarState) !void {
        try self.ensureResources();
        const target = (self.target orelse return error.Direct2DTargetUnavailable).renderTarget();
        _ = self.text_format orelse return error.DirectWriteTextFormatUnavailable;
        const tab_format = self.tab_text_format orelse return error.DirectWriteTextFormatUnavailable;
        const icon_format = self.icon_format orelse return error.DirectWriteTextFormatUnavailable;
        const window = self.window;

        var client: RECT = std.mem.zeroes(RECT);
        if (sys.GetClientRect(self.hwnd, &client) == 0) return;

        target.BeginDraw();
        const transparent: d2d.D2D_COLOR_F = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
        target.Clear(&transparent);

        const bar_bg = blendColor(window.app.config.background, window.app.config.foreground, 0.12);
        const bg_alpha: f32 = switch (window.app.config.@"background-blur") {
            .acrylic, .mica, .@"mica-alt", .true => 0.22,
            .false, .transparent => 0.92,
            else => 0.92,
        };
        const bg_brush = try d2dBrush(target, d2dColor(bar_bg, bg_alpha));
        defer releaseCom(bg_brush);
        var full_rect = rectF(client.left, client.top, client.right, client.bottom);
        target.FillRectangle(&full_rect, @ptrCast(bg_brush));

        const text_brush = try d2dBrush(target, d2dColor(window.app.config.foreground, 1.0));
        defer releaseCom(text_brush);
        const divider_color = blendColor(window.app.config.background, window.app.config.foreground, 0.32);
        const divider_brush = try d2dBrush(target, d2dColor(divider_color, 0.46));
        defer releaseCom(divider_brush);
        var divider_rect = rectF(client.left, client.bottom - 1, client.right, client.bottom);
        target.FillRectangle(&divider_rect, @ptrCast(divider_brush));

        const button_area_w = WINDOW_BUTTON_WIDTH * WINDOW_BUTTON_COUNT;
        const controls_right = client.right - button_area_w;
        self.drawTabs(target, tab_format, icon_format, @ptrCast(text_brush), controls_right) catch {};
        self.drawIconButton(target, icon_format, @ptrCast(text_brush), client.right - button_area_w, 0, WINDOW_BUTTON_WIDTH, TOP_BAR_HEIGHT, .minimize, .window_minimize);
        self.drawIconButton(
            target,
            icon_format,
            @ptrCast(text_brush),
            client.right - WINDOW_BUTTON_WIDTH * 2,
            0,
            WINDOW_BUTTON_WIDTH,
            TOP_BAR_HEIGHT,
            if (sys.IsZoomed(window.hwnd.?) != 0) .restore else .maximize,
            .window_maximize,
        );
        self.drawIconButton(target, icon_format, @ptrCast(text_brush), client.right - WINDOW_BUTTON_WIDTH, 0, WINDOW_BUTTON_WIDTH, TOP_BAR_HEIGHT, .close_window, .window_close);

        const hr = target.EndDraw();
        if (d2d.failed(hr)) return error.Direct2DDrawFailed;
    }

    fn drawTabs(
        self: *TitleBarState,
        target: *d2d.ID2D1RenderTarget,
        format: *d2d.IDWriteTextFormat,
        icon_format: *d2d.IDWriteTextFormat,
        text_brush: *d2d.ID2D1Brush,
        controls_right: i32,
    ) !void {
        const window = self.window;
        const tab_count = window.tabs.items.len;
        if (tab_count == 0) return;

        const max_right = controls_right - NEW_TAB_WIDTH - DROPDOWN_WIDTH - 12;
        const available_width = max_right - TAB_START_X;
        const tw = tabWidth(tab_count, available_width);
        const factory = self.dwrite_factory orelse return;
        const mode = window.tab_width_mode;

        var x: i32 = TAB_START_X;
        for (window.tabs.items, 0..) |tab, i| {
            if (x >= max_right) break;

            const width = switch (mode) {
                .equal => @min(tw, max_right - x),
                .compact => @min(COMPACT_WIDTH, max_right - x),
                .title => blk: {
                    const text_w = measureTabTextWidth(factory, format, tab.title, window.app.alloc);
                    const desired = text_w + TAB_TEXT_MARGIN_LEFT + TAB_CLOSE_WIDTH + TAB_TEXT_MARGIN_RIGHT;
                    break :blk @min(@max(TITLE_MIN_WIDTH, desired), TITLE_MAX_WIDTH, max_right - x);
                },
            };

            const selected = i == window.current_tab;
            const bg: configpkg.Config.Color = if (tab.color) |c|
                if (selected) c else blendColor(c, window.app.config.foreground, 0.10)
            else
                if (selected)
                    blendColor(window.app.config.background, window.app.config.foreground, 0.26)
                else
                    blendColor(window.app.config.background, window.app.config.foreground, 0.08);
            const bg_alpha: f32 = if (tab.color != null)
                if (selected) 0.85 else 0.50
            else
                if (selected) 0.76 else 0.34;
            const brush = try d2dBrush(target, d2dColor(bg, bg_alpha));
            defer releaseCom(brush);
            var tab_rect = rectF(x, TAB_TOP, x + width, TAB_BOTTOM);
            target.FillRectangle(&tab_rect, @ptrCast(brush));

            var text_rect = rectF(x + TAB_TEXT_MARGIN_LEFT, TAB_TOP, x + width - TAB_CLOSE_WIDTH - TAB_TEXT_MARGIN_RIGHT, TAB_BOTTOM);

            const title_to_draw = switch (mode) {
                .equal, .title => blk_title: {
                    if (mode == .title) {
                        const text_avail = width - TAB_TEXT_MARGIN_LEFT - TAB_CLOSE_WIDTH - TAB_TEXT_MARGIN_RIGHT;
                        const text_w = measureTabTextWidth(factory, format, tab.title, window.app.alloc);
                        if (text_w > text_avail) {
                            break :blk_title try truncateTabTitle(window.app.alloc, tab.title, text_avail, text_w);
                        }
                    }
                    break :blk_title tab.title;
                },
                .compact => try compactTitle(tab.title, window.app.alloc),
            };
            const needs_free = (mode == .title and title_to_draw.ptr != tab.title.ptr) or mode == .compact;
            defer if (needs_free) window.app.alloc.free(title_to_draw);

            const utf16 = try std.unicode.utf8ToUtf16LeAllocZ(window.app.alloc, title_to_draw);
            defer window.app.alloc.free(utf16);
            target.DrawText(utf16.ptr, @intCast(utf16.len), format, &text_rect, text_brush, .{ .CLIP = 1 });

            self.drawIconButton(target, icon_format, text_brush, x + width - 32, 11, 24, 24, .close_tab, .{ .tab_close = i });
            x += width + TAB_GAP;
        }

        self.drawIconButton(target, icon_format, text_brush, x + 5, TAB_ACTION_TOP, NEW_TAB_WIDTH - 10, TOP_BAR_HEIGHT - TAB_ACTION_TOP, .new_tab, .new_tab);
        self.drawIconButton(target, icon_format, text_brush, x + NEW_TAB_WIDTH, TAB_ACTION_TOP, DROPDOWN_WIDTH - 8, TOP_BAR_HEIGHT - TAB_ACTION_TOP, .dropdown, .dropdown);
    }

    fn drawIconButton(
        self: *TitleBarState,
        target: *d2d.ID2D1RenderTarget,
        format: *d2d.IDWriteTextFormat,
        text_brush: *d2d.ID2D1Brush,
        x: i32,
        y: i32,
        w: i32,
        h: i32,
        icon: TitleIcon,
        hit: TitleHit,
    ) void {
        if (self.buttonBackground(hit)) |bg| {
            const brush = d2dBrush(target, bg.color) catch return;
            defer releaseCom(brush);
            var bg_rect = rectF(x, y, x + w, y + h);
            target.FillRectangle(&bg_rect, @ptrCast(brush));
        }
        var r = rectF(x, y, x + w, y + h);
        const text = icon.text();
        target.DrawText(@ptrCast(text.ptr), @intCast(text.len), format, &r, text_brush, .{ .CLIP = 1 });
    }

    fn buttonBackground(self: *const TitleBarState, hit: TitleHit) ?struct { color: d2d.D2D_COLOR_F } {
        const pressed = self.pressed.eql(hit);
        const hovered = self.hover.eql(hit);
        if (!pressed and !hovered) return null;

        if (hit.eql(.window_close)) {
            return .{ .color = d2dColor(if (pressed) CLOSE_PRESSED else CLOSE_HOVER, 1.0) };
        }

        const foreground = self.window.app.config.foreground;
        const background = self.window.app.config.background;
        const color = blendColor(background, foreground, if (pressed) 0.72 else 0.58);
        return .{ .color = d2dColor(color, if (pressed) TITLE_PRESSED_ALPHA else TITLE_HOVER_ALPHA) };
    }

    fn ensureResources(self: *TitleBarState) !void {
        if (self.d2d_factory == null) {
            var raw_d2d: *anyopaque = undefined;
            const hr = d2d.D2D1CreateFactory(.SINGLE_THREADED, &d2d.IID_ID2D1Factory, null, &raw_d2d);
            if (d2d.failed(hr)) return error.Direct2DUnavailable;
            self.d2d_factory = @ptrCast(@alignCast(raw_d2d));
        }
        if (self.dwrite_factory == null) {
            var raw_dwrite: *d2d.IUnknown = undefined;
            const hr = d2d.DWriteCreateFactory(.SHARED, &d2d.IID_IDWriteFactory, &raw_dwrite);
            if (d2d.failed(hr)) return error.DirectWriteUnavailable;
            self.dwrite_factory = @ptrCast(@alignCast(raw_dwrite));
        }
        if (self.text_format == null) {
            const factory = self.dwrite_factory orelse return error.DirectWriteUnavailable;
            self.text_format = try createTextFormat(factory, "Segoe UI", 13.0, .CENTER);
        }
        if (self.tab_text_format == null) {
            const factory = self.dwrite_factory orelse return error.DirectWriteUnavailable;
            self.tab_text_format = try createTextFormat(factory, "Segoe UI", 13.0, .LEADING);
        }
        if (self.icon_format == null) {
            const factory = self.dwrite_factory orelse return error.DirectWriteUnavailable;
            self.icon_format = createTextFormat(factory, "Segoe Fluent Icons", TITLE_ICON_SIZE, .CENTER) catch
                try createTextFormat(factory, "Segoe MDL2 Assets", TITLE_ICON_SIZE, .CENTER);
        }
        if (self.target == null) {
            try self.createRenderTarget();
        }
    }

    fn createRenderTarget(self: *TitleBarState) !void {
        const factory = self.d2d_factory orelse return error.Direct2DUnavailable;
        var rect: RECT = std.mem.zeroes(RECT);
        if (sys.GetClientRect(self.hwnd, &rect) == 0) return error.Direct2DTargetUnavailable;
        var rt_props: d2d.D2D1_RENDER_TARGET_PROPERTIES = .{
            .type = .DEFAULT,
            .pixelFormat = .{
                .format = .B8G8R8A8_UNORM,
                .alphaMode = .PREMULTIPLIED,
            },
            .dpiX = 96,
            .dpiY = 96,
            .usage = .{},
            .minLevel = .DEFAULT,
        };
        var hwnd_props: d2d.D2D1_HWND_RENDER_TARGET_PROPERTIES = .{
            .hwnd = self.hwnd,
            .pixelSize = .{
                .width = @intCast(@max(1, rect.right - rect.left)),
                .height = @intCast(@max(1, rect.bottom - rect.top)),
            },
            .presentOptions = .{},
        };
        var target: *d2d.ID2D1HwndRenderTarget = undefined;
        const hr = factory.CreateHwndRenderTarget(&rt_props, &hwnd_props, &target);
        if (d2d.failed(hr)) return error.Direct2DTargetUnavailable;
        target.renderTarget().SetTextAntialiasMode(.GRAYSCALE);
        self.target = target;
    }

    fn resizeFromClient(self: *TitleBarState, hwnd: HWND) void {
        if (self.target) |target| {
            var rect: RECT = std.mem.zeroes(RECT);
            if (sys.GetClientRect(hwnd, &rect) == 0) return;
            const size: d2d.D2D_SIZE_U = .{
                .width = @intCast(@max(1, rect.right - rect.left)),
                .height = @intCast(@max(1, rect.bottom - rect.top)),
            };
            if (d2d.failed(target.Resize(&size))) {
                self.releaseDeviceResources();
            }
        }
    }

    fn releaseDeviceResources(self: *TitleBarState) void {
        releaseCom(self.target);
        self.target = null;
    }

    fn hitForNcButton(hit: LRESULT) TitleHit {
        return switch (hit) {
            sys.HTMINBUTTON => .window_minimize,
            sys.HTMAXBUTTON => .window_maximize,
            else => .none,
        };
    }
};

const DividerState = struct {
    hwnd: HWND,
    window: *Window,
    node: *SplitTree.Node,
    direction: SplitTree.Direction,
    rect: SplitTree.Rect,
    bounds: SplitTree.Rect,
    active: bool = false,
};

const DividerDrag = struct {
    divider: *DividerState,
};

pub const CreateOptions = struct {
    command: ?configpkg.Command = null,
    working_directory: ?configpkg.WorkingDirectory = null,
    title: ?[:0]const u8 = null,
    quick_terminal: bool = false,

    pub const none: @This() = .{};

    pub fn deinit(self: *@This(), alloc: Allocator) void {
        if (self.command) |cmd| cmd.deinit(alloc);
        if (self.working_directory) |wd| switch (wd) {
            .path => |path| alloc.free(path),
            else => {},
        };
        if (self.title) |title| alloc.free(title);
        self.* = .{};
    }
};

const TabState = struct {
    primary_surface: *Surface,
    tree: SplitTree,
    focused_surface: ?*Surface = null,
    title: [:0]const u8,
    color: ?configpkg.Config.Color = null,
};

app: *App,
hwnd: ?HWND = null,
title_bar: ?TitleBarState = null,
primary_surface: *Surface,
tree: ?SplitTree = null,
focused_surface: ?*Surface = null,
surface_initialized: bool = false,
tabs: std.ArrayListUnmanaged(TabState) = .{},
current_tab: usize = 0,
tab_width_mode: TabWidthMode = .equal,
fullscreen: FullscreenState = .{},
quick_terminal: bool = false,
dividers: std.ArrayListUnmanaged(*DividerState) = .{},
drag: ?DividerDrag = null,
in_window_resize: bool = false,
pending_core_resize: bool = false,
pending_window_relayout: bool = false,
/// Tracks whether DWMWA_SYSTEMBACKDROP_TYPE is supported on this OS.
/// When false (e.g. Windows 10), we fall back to SetWindowCompositionAttribute.
dwm_backdrop_supported: bool = true,

const FullscreenState = struct {
    active: bool = false,
    style: i32 = 0,
    ex_style: i32 = 0,
    rect: RECT = std.mem.zeroes(RECT),
};

pub fn create(alloc: Allocator, app: *App, opts: CreateOptions) !*Window {
    const self = try alloc.create(Window);
    errdefer alloc.destroy(self);

    self.* = .{
        .app = app,
        .primary_surface = undefined,
        .quick_terminal = opts.quick_terminal,
    };

    try self.createHwnd(opts.title);
    errdefer {
        if (self.hwnd) |h| _ = sys.DestroyWindow(h);
    }
    self.applyWindowEffects();

    _ = sys.SetWindowLongPtrW(self.hwnd.?, sys.GWLP_USERDATA, @bitCast(@intFromPtr(self)));
    try self.createTitleBar();

    _ = try self.insertTab(0, opts, true);
    if (self.quick_terminal) self.applyQuickTerminalLayout() else self.applyConfiguredWindowSize();
    self.relayout();

    if (self.focused_surface) |surface| {
        _ = sys.SetFocus(surface.hwnd);
        if (surface.core_surface) |core| {
            core.colorSchemeCallback(app.detectColorScheme()) catch {};
        }
    }

    return self;
}

pub fn deinit(self: *Window) void {
    self.destroyDividers();
    self.destroyTitleBar();
    self.syncActiveTabFromWindow();
    for (self.tabs.items) |*tab| self.deinitTab(tab);
    self.tabs.deinit(self.app.alloc);
    self.tree = null;
    self.surface_initialized = false;
    if (self.hwnd) |hwnd| {
        _ = sys.DestroyWindow(hwnd);
        self.hwnd = null;
    }
}

fn createHwnd(self: *Window, title_override: ?[:0]const u8) !void {
    const class_name = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyWindow");
    const hinstance = sys.GetModuleHandleW(null);
    const wc: sys.WNDCLASSEXW = .{
        .cbSize = @sizeOf(sys.WNDCLASSEXW),
        .style = sys.CS_HREDRAW | sys.CS_VREDRAW | sys.CS_OWNDC,
        .lpfnWndProc = App.wndProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = hinstance,
        .hIcon = sys.LoadIconW(hinstance, @ptrFromInt(1)),
        .hCursor = sys.LoadCursorW(null, sys.IDC_ARROW),
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = class_name,
        .hIconSm = sys.LoadIconW(hinstance, @ptrFromInt(1)),
    };
    _ = sys.RegisterClassExW(&wc);

    const title = if (title_override) |title_utf8|
        try std.unicode.utf8ToUtf16LeAllocZ(self.app.alloc, title_utf8)
    else
        null;
    defer if (title) |v| self.app.alloc.free(v);

    self.hwnd = sys.CreateWindowExW(
        if (self.quick_terminal) @intCast(sys.WS_EX_TOPMOST) else 0,
        class_name,
        if (title) |v| v.ptr else std.unicode.utf8ToUtf16LeStringLiteral("Ghostty"),
        TOPLEVEL_STYLE,
        sys.CW_USEDEFAULT,
        sys.CW_USEDEFAULT,
        900,
        650,
        null,
        null,
        hinstance,
        null,
    );
    if (self.hwnd == null) return error.Win32Error;
    _ = sys.ShowWindow(self.hwnd.?, sys.SW_SHOWNORMAL);
    _ = sys.UpdateWindow(self.hwnd.?);
}

pub fn applyWindowEffects(self: *Window) void {
    const hwnd = self.hwnd orelse return;

    // Clear any lingering SetWindowCompositionAttribute state before
    // applying new effects. The accent policy is sticky across calls.
    sys.setAccentPolicy(
        hwnd,
        .disabled,
        0,
        .{ .r = 0, .g = 0, .b = 0 },
    );

    // Extend DWM frame into client area so DWM renders backdrop behind
    // the entire window. Required for all Fluent Design effects.
    // When disabling, reset margins to 0 so DWM stops drawing glass.
    switch (self.app.config.@"background-blur") {
        .true, .acrylic, .mica, .@"mica-alt" => {
            const margins: sys.MARGINS = .{
                .cxLeftWidth = -1,
                .cxRightWidth = -1,
                .cyTopHeight = -1,
                .cyBottomHeight = -1,
            };
            _ = sys.DwmExtendFrameIntoClientArea(hwnd, &margins);
        },
        else => {
            const margins: sys.MARGINS = .{
                .cxLeftWidth = 0,
                .cxRightWidth = 0,
                .cyTopHeight = 0,
                .cyBottomHeight = 0,
            };
            _ = sys.DwmExtendFrameIntoClientArea(hwnd, &margins);
        },
    }

    const dark_mode: u32 = switch (self.app.config.@"window-theme") {
        .dark => 1,
        .light => 0,
        .auto, .system, .ghostty => switch (self.app.detectColorScheme()) {
            .dark => 1,
            .light => 0,
        },
    };
    _ = sys.DwmSetWindowAttribute(
        hwnd,
        sys.DWMWA_USE_IMMERSIVE_DARK_MODE,
        &dark_mode,
        @sizeOf(@TypeOf(dark_mode)),
    );

    const backdrop: sys.DWM_SYSTEMBACKDROP_TYPE = switch (self.app.config.@"background-blur") {
        .true, .acrylic => .transient_window,
        .mica => .main_window,
        .@"mica-alt" => .tabbed_window,
        else => .none,
    };
    const result = sys.DwmSetWindowAttribute(
        hwnd,
        sys.DWMWA_SYSTEMBACKDROP_TYPE,
        &backdrop,
        @sizeOf(@TypeOf(backdrop)),
    );
    if (result == 0) {
        self.dwm_backdrop_supported = true;
    } else {
        // DWMWA_SYSTEMBACKDROP_TYPE not supported (Windows 10 or older).
        // Keep the extended frame and fall back to SetWindowCompositionAttribute.
        self.dwm_backdrop_supported = false;
        sys.setAccentPolicy(
            hwnd,
            sys.accentStateForBlur(self.app.config.@"background-blur"),
            self.app.config.@"background-opacity",
            .{
                .r = self.app.config.background.r,
                .g = self.app.config.background.g,
                .b = self.app.config.background.b,
            },
        );
    }

    const corner: sys.DWM_WINDOW_CORNER_PREFERENCE = .round;
    _ = sys.DwmSetWindowAttribute(
        hwnd,
        sys.DWMWA_WINDOW_CORNER_PREFERENCE,
        &corner,
        @sizeOf(@TypeOf(corner)),
    );

    const caption_color: u32 = switch (self.app.config.@"background-blur") {
        .false => bgrColor(self.app.config.background),
        else => sys.DWMWA_COLOR_DEFAULT,
    };
    _ = sys.DwmSetWindowAttribute(
        hwnd,
        sys.DWMWA_CAPTION_COLOR,
        &caption_color,
        @sizeOf(@TypeOf(caption_color)),
    );

    const border_color: u32 = switch (self.app.config.@"background-blur") {
        .false => bgrColor(self.app.config.background),
        else => sys.DWMWA_COLOR_NONE,
    };
    _ = sys.DwmSetWindowAttribute(
        hwnd,
        sys.DWMWA_BORDER_COLOR,
        &border_color,
        @sizeOf(@TypeOf(border_color)),
    );

    const text_color: u32 = bgrColor(self.app.config.foreground);
    _ = sys.DwmSetWindowAttribute(
        hwnd,
        sys.DWMWA_TEXT_COLOR,
        &text_color,
        @sizeOf(@TypeOf(text_color)),
    );

    // Pure transparency (no blur) uses SetWindowCompositionAttribute
    // directly rather than DWM backdrop API.
    if (self.app.config.@"background-blur" == .transparent) {
        sys.setAccentPolicy(
            hwnd,
            .enable_transparent_gradient,
            self.app.config.@"background-opacity",
            .{
                .r = self.app.config.background.r,
                .g = self.app.config.background.g,
                .b = self.app.config.background.b,
            },
        );
    }

    self.applyTitleBarEffects();
    self.applySurfaceWindowEffects();
}

fn applyTitleBarEffects(self: *Window) void {
    if (self.title_bar) |bar| {
        const blur = self.app.config.@"background-blur";
        if (blur != .false and (!self.dwm_backdrop_supported or blur == .transparent)) {
            sys.setAccentPolicy(
                bar.hwnd,
                sys.accentStateForBlur(blur),
                self.app.config.@"background-opacity",
                .{
                    .r = self.app.config.background.r,
                    .g = self.app.config.background.g,
                    .b = self.app.config.background.b,
                },
            );
        } else {
            sys.setAccentPolicy(
                bar.hwnd,
                .disabled,
                0,
                .{ .r = 0, .g = 0, .b = 0 },
            );
        }
        _ = sys.InvalidateRect(bar.hwnd, null, 0);
    }
}

fn applySurfaceWindowEffects(self: *Window) void {
    for (self.tabs.items) |*tab| {
        var leaves: [64]*Surface = undefined;
        for (tabLeaves(tab, &leaves)) |surface| surface.applyBackgroundEffect();
    }
}

fn bgrColor(color: configpkg.Config.Color) u32 {
    return (@as(u32, color.b) << 16) |
        (@as(u32, color.g) << 8) |
        @as(u32, color.r);
}

fn blendColor(a: configpkg.Config.Color, b: configpkg.Config.Color, amount: f32) configpkg.Config.Color {
    return .{
        .r = blendChannel(a.r, b.r, amount),
        .g = blendChannel(a.g, b.g, amount),
        .b = blendChannel(a.b, b.b, amount),
    };
}

fn blendChannel(a: u8, b: u8, amount: f32) u8 {
    const af: f32 = @floatFromInt(a);
    const bf: f32 = @floatFromInt(b);
    return @intFromFloat(@round(af + (bf - af) * amount));
}

fn releaseCom(value: anytype) void {
    switch (@typeInfo(@TypeOf(value))) {
        .optional => if (value) |ptr| releaseComPtr(ptr),
        .pointer => releaseComPtr(value),
        else => @compileError("releaseCom expects a COM pointer or optional COM pointer"),
    }
}

fn releaseComPtr(ptr: anytype) void {
    const unknown: *d2d.IUnknown = @ptrCast(@alignCast(ptr));
    _ = unknown.Release();
}

fn createTextFormat(
    factory: *d2d.IDWriteFactory,
    comptime family: []const u8,
    size: f32,
    alignment: d2d.DWRITE_TEXT_ALIGNMENT,
) !*d2d.IDWriteTextFormat {
    var format: *d2d.IDWriteTextFormat = undefined;
    const hr = factory.CreateTextFormat(
        std.unicode.utf8ToUtf16LeStringLiteral(family),
        null,
        .NORMAL,
        .NORMAL,
        .NORMAL,
        size,
        std.unicode.utf8ToUtf16LeStringLiteral("en-us"),
        &format,
    );
    if (d2d.failed(hr)) return error.DirectWriteTextFormatUnavailable;
    _ = format.SetTextAlignment(alignment);
    _ = format.SetParagraphAlignment(.CENTER);
    _ = format.SetWordWrapping(.NO_WRAP);
    return format;
}

fn createTitleBar(self: *Window) !void {
    const parent = self.hwnd orelse return error.Win32Error;
    try registerTitleBarClass();
    const hwnd = sys.CreateWindowExW(
        0,
        std.unicode.utf8ToUtf16LeStringLiteral("GhosttyTitleBar"),
        null,
        WS_CHILD | WS_VISIBLE,
        0,
        0,
        0,
        TOP_BAR_HEIGHT,
        parent,
        null,
        sys.GetModuleHandleW(null),
        null,
    ) orelse return error.Win32Error;
    self.title_bar = .{ .hwnd = hwnd, .window = self };
    _ = sys.SetWindowLongPtrW(hwnd, sys.GWLP_USERDATA, @bitCast(@intFromPtr(&self.title_bar.?)));
    self.applyTitleBarEffects();
}

fn destroyTitleBar(self: *Window) void {
    if (self.title_bar) |*bar| {
        bar.releaseDeviceResources();
        releaseCom(bar.icon_format);
        bar.icon_format = null;
        releaseCom(bar.tab_text_format);
        bar.tab_text_format = null;
        releaseCom(bar.text_format);
        bar.text_format = null;
        releaseCom(bar.dwrite_factory);
        bar.dwrite_factory = null;
        releaseCom(bar.d2d_factory);
        bar.d2d_factory = null;
        _ = sys.DestroyWindow(bar.hwnd);
        self.title_bar = null;
    }
}

fn registerTitleBarClass() !void {
    if (title_bar_class_registered) return;
    const class_name = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyTitleBar");
    const hinstance = sys.GetModuleHandleW(null);
    const wc: sys.WNDCLASSEXW = .{
        .cbSize = @sizeOf(sys.WNDCLASSEXW),
        .style = sys.CS_HREDRAW | sys.CS_VREDRAW,
        .lpfnWndProc = titleBarWndProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = hinstance,
        .hIcon = null,
        .hCursor = sys.LoadCursorW(null, sys.IDC_ARROW),
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = class_name,
        .hIconSm = null,
    };
    if (sys.RegisterClassExW(&wc) == 0) return error.Win32Error;
    title_bar_class_registered = true;
}

fn titleBarWndProc(hwnd: HWND, msg: UINT, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT {
    const ptr = sys.GetWindowLongPtrW(hwnd, sys.GWLP_USERDATA);
    if (ptr == 0) return sys.DefWindowProcW(hwnd, msg, wparam, lparam);
    const bar: *TitleBarState = @ptrFromInt(@as(usize, @bitCast(ptr)));
    return bar.handleMessage(hwnd, msg, wparam, lparam);
}

fn d2dColor(color: configpkg.Config.Color, alpha: f32) d2d.D2D_COLOR_F {
    return .{
        .r = @as(f32, @floatFromInt(color.r)) / 255.0,
        .g = @as(f32, @floatFromInt(color.g)) / 255.0,
        .b = @as(f32, @floatFromInt(color.b)) / 255.0,
        .a = alpha,
    };
}

fn d2dBrush(target: *d2d.ID2D1RenderTarget, color: d2d.D2D_COLOR_F) !*d2d.ID2D1SolidColorBrush {
    var mutable_color = color;
    var brush: *d2d.ID2D1SolidColorBrush = undefined;
    const hr = target.CreateSolidColorBrush(&mutable_color, &brush);
    if (d2d.failed(hr)) return error.Direct2DBrushUnavailable;
    return brush;
}

fn rectF(left: i32, top: i32, right: i32, bottom: i32) d2d.D2D_RECT_F {
    return .{
        .left = @floatFromInt(left),
        .top = @floatFromInt(top),
        .right = @floatFromInt(right),
        .bottom = @floatFromInt(bottom),
    };
}

fn registerDividerClass() !void {
    if (divider_class_registered) return;
    const class_name = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyDivider");
    const hinstance = sys.GetModuleHandleW(null);
    const wc: sys.WNDCLASSEXW = .{
        .cbSize = @sizeOf(sys.WNDCLASSEXW),
        .style = sys.CS_HREDRAW | sys.CS_VREDRAW,
        .lpfnWndProc = dividerWndProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = hinstance,
        .hIcon = null,
        .hCursor = sys.LoadCursorW(null, sys.IDC_ARROW),
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = class_name,
        .hIconSm = null,
    };
    if (sys.RegisterClassExW(&wc) == 0) return error.Win32Error;
    divider_class_registered = true;
}

fn dividerWndProc(hwnd: HWND, msg: UINT, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT {
    const ptr = sys.GetWindowLongPtrW(hwnd, sys.GWLP_USERDATA);
    if (ptr == 0) return sys.DefWindowProcW(hwnd, msg, wparam, lparam);
    const divider: *DividerState = @ptrFromInt(@as(usize, @bitCast(ptr)));
    return divider.window.handleDividerMessage(divider, hwnd, msg, wparam, lparam);
}

fn destroyDividers(self: *Window) void {
    if (self.drag != null) {
        _ = ReleaseCapture();
        self.drag = null;
    }
    for (self.dividers.items) |divider| {
        _ = sys.DestroyWindow(divider.hwnd);
        self.app.alloc.destroy(divider);
    }
    self.dividers.deinit(self.app.alloc);
}

pub fn paintTopBar(self: *Window, hwnd: HWND) void {
    _ = self;
    var ps: sys.PAINTSTRUCT = std.mem.zeroes(sys.PAINTSTRUCT);
    _ = sys.BeginPaint(hwnd, &ps);
    _ = sys.EndPaint(hwnd, &ps);
}

fn minimize(self: *Window) void {
    const hwnd = self.hwnd orelse return;
    self.invalidateTopBar();
    _ = sys.ShowWindow(hwnd, sys.SW_MINIMIZE);
}

fn toggleMaximize(self: *Window) void {
    const hwnd = self.hwnd orelse return;
    self.invalidateTopBar();
    _ = sys.ShowWindow(hwnd, if (sys.IsZoomed(hwnd) != 0) sys.SW_RESTORE else sys.SW_MAXIMIZE);
    self.relayout();
    self.invalidateTopBar();
}

fn closeFromTitleBar(self: *Window) void {
    const hwnd = self.hwnd orelse return;
    _ = sys.SendMessageW(hwnd, sys.WM_SYSCOMMAND, sys.SC_CLOSE, 0);
}

fn handleTabBarClick(self: *Window, x: i32, y: i32) bool {
    const hwnd = self.hwnd orelse return false;
    var rect: RECT = std.mem.zeroes(RECT);
    if (sys.GetClientRect(hwnd, &rect) == 0) return false;
    if (y < 0 or y >= self.tabClientHeight()) return false;

    const button_area_left = rect.right - WINDOW_BUTTON_WIDTH * WINDOW_BUTTON_COUNT;
    if (x >= button_area_left) {
        const idx = @divTrunc(x - button_area_left, WINDOW_BUTTON_WIDTH);
        switch (idx) {
            0 => _ = sys.ShowWindow(hwnd, sys.SW_MINIMIZE),
            1 => _ = sys.ShowWindow(hwnd, if (sys.IsZoomed(hwnd) != 0) sys.SW_RESTORE else sys.SW_MAXIMIZE),
            else => _ = sys.PostMessageW(hwnd, sys.WM_CLOSE, 0, 0),
        }
        return true;
    }

    const controls_right = button_area_left;
    var tab_x: i32 = TAB_START_X;
    for (self.tabs.items, 0..) |_, i| {
        const max_right = controls_right - NEW_TAB_WIDTH - DROPDOWN_WIDTH - 12;
        if (tab_x >= max_right) break;
        const width = @min(CUSTOM_TAB_WIDTH, max_right - tab_x);
        if (x >= tab_x and x < tab_x + width) {
            if (x >= tab_x + width - TAB_CLOSE_WIDTH) {
                _ = sys.PostMessageW(hwnd, sys.WM_APP_CLOSE_TAB, i, 0);
            } else {
                self.activateTab(i) catch {};
            }
            return true;
        }
        tab_x += width + TAB_GAP;
    }

    if (x >= tab_x + 6 and x < tab_x + NEW_TAB_WIDTH) {
        _ = sys.PostMessageW(hwnd, sys.WM_APP_NEW_TAB, 0, 0);
        return true;
    }
    if (x >= tab_x + NEW_TAB_WIDTH and x < tab_x + NEW_TAB_WIDTH + DROPDOWN_WIDTH) {
        self.showNewTabMenu(tab_x + NEW_TAB_WIDTH, TOP_BAR_HEIGHT);
        return true;
    }
    return false;
}

fn showNewTabMenuFromTitleBar(self: *Window) void {
    const hwnd = self.hwnd orelse return;
    var rect: RECT = std.mem.zeroes(RECT);
    if (sys.GetClientRect(hwnd, &rect) == 0) return;

    const controls_right = rect.right - WINDOW_BUTTON_WIDTH * WINDOW_BUTTON_COUNT;
    var tab_x: i32 = TAB_START_X;
    for (self.tabs.items) |_| {
        const max_right = controls_right - NEW_TAB_WIDTH - DROPDOWN_WIDTH - 12;
        if (tab_x >= max_right) break;
        const width = @min(CUSTOM_TAB_WIDTH, max_right - tab_x);
        tab_x += width + TAB_GAP;
    }

    self.showNewTabMenu(tab_x + NEW_TAB_WIDTH, TOP_BAR_HEIGHT);
}

fn showNewTabMenu(self: *Window, x: i32, y: i32) void {
    const hwnd = self.hwnd orelse return;
    const menu = sys.CreatePopupMenu() orelse return;
    defer _ = sys.DestroyMenu(menu);

    _ = sys.AppendMenuW(menu, sys.MF_STRING, @intFromEnum(ProfileMenuCommand.default), std.unicode.utf8ToUtf16LeStringLiteral("Default"));
    _ = sys.AppendMenuW(menu, sys.MF_SEPARATOR, 0, null);
    _ = sys.AppendMenuW(menu, sys.MF_STRING, @intFromEnum(ProfileMenuCommand.cmd), std.unicode.utf8ToUtf16LeStringLiteral("Command Prompt"));
    _ = sys.AppendMenuW(menu, sys.MF_STRING, @intFromEnum(ProfileMenuCommand.powershell), std.unicode.utf8ToUtf16LeStringLiteral("Windows PowerShell"));
    if (commandExists(std.unicode.utf8ToUtf16LeStringLiteral("C:\\Program Files\\PowerShell\\7\\pwsh.exe"))) {
        _ = sys.AppendMenuW(menu, sys.MF_STRING, @intFromEnum(ProfileMenuCommand.pwsh), std.unicode.utf8ToUtf16LeStringLiteral("PowerShell 7"));
    }

    var pt: sys.POINT = .{ .x = x, .y = y };
    if (self.title_bar) |bar| {
        if (sys.ClientToScreen(bar.hwnd, &pt) == 0) return;
    } else if (sys.ClientToScreen(hwnd, &pt) == 0) return;

    const cmd = sys.TrackPopupMenu(
        menu,
        sys.TPM_RETURNCMD | sys.TPM_LEFTALIGN | sys.TPM_TOPALIGN,
        pt.x,
        pt.y,
        0,
        hwnd,
        null,
    );
    if (cmd != 0) _ = sys.PostMessageW(hwnd, sys.WM_APP_NEW_PROFILE_TAB, cmd, 0);
}

fn commandExists(path: [*:0]const u16) bool {
    return sys.GetFileAttributesW(path) != sys.INVALID_FILE_ATTRIBUTES;
}

fn ensureDividerCount(self: *Window, count: usize) !void {
    try registerDividerClass();
    while (self.dividers.items.len < count) {
        const divider = try self.app.alloc.create(DividerState);
        errdefer self.app.alloc.destroy(divider);
        const hwnd = sys.CreateWindowExW(
            0,
            std.unicode.utf8ToUtf16LeStringLiteral("GhosttyDivider"),
            null,
            WS_CHILD | WS_VISIBLE,
            0,
            0,
            0,
            0,
            self.hwnd,
            null,
            sys.GetModuleHandleW(null),
            null,
        ) orelse return error.Win32Error;
        divider.* = .{
            .hwnd = hwnd,
            .window = self,
            .node = undefined,
            .direction = .horizontal,
            .rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
            .bounds = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
        };
        _ = sys.SetWindowLongPtrW(hwnd, sys.GWLP_USERDATA, @bitCast(@intFromPtr(divider)));
        try self.dividers.append(self.app.alloc, divider);
    }
}

fn updateDividers(self: *Window, bounds: SplitTree.Rect) void {
    const tree = &(self.tree orelse {
        self.hideAllDividers();
        return;
    });
    var buf: [64]SplitTree.DividerRect = undefined;
    const count = tree.collectDividerRects(bounds, &buf);
    self.ensureDividerCount(count) catch return;

    for (self.dividers.items, 0..) |divider, i| {
        if (i >= count) {
            divider.active = false;
            _ = sys.ShowWindow(divider.hwnd, SW_HIDE);
            continue;
        }
        const info = buf[i];
        divider.node = info.node;
        divider.direction = info.direction;
        divider.rect = info.rect;
        divider.bounds = info.bounds;
        divider.active = true;
        _ = sys.SetWindowPos(
            divider.hwnd,
            null,
            info.rect.x,
            info.rect.y,
            info.rect.w,
            info.rect.h,
            0x0004,
        );
        _ = sys.ShowWindow(divider.hwnd, sys.SW_SHOWNORMAL);
        _ = sys.InvalidateRect(divider.hwnd, null, 1);
    }
}

fn hideAllDividers(self: *Window) void {
    for (self.dividers.items) |divider| {
        divider.active = false;
        _ = sys.ShowWindow(divider.hwnd, SW_HIDE);
    }
}

fn adjustDividerRatio(self: *Window, divider: *DividerState, lparam: LPARAM) void {
    const sp = switch (divider.node.*) {
        .split => |*sp| sp,
        else => return,
    };
    const x: i32 = @as(i16, @truncate(lparam & 0xFFFF));
    const y: i32 = @as(i16, @truncate((lparam >> 16) & 0xFFFF));
    const new_ratio: f32 = switch (divider.direction) {
        .horizontal => blk: {
            if (divider.bounds.w <= DIVIDER_THICKNESS) break :blk sp.ratio;
            const absolute_x = divider.rect.x + x;
            const offset = std.math.clamp(absolute_x - divider.bounds.x, 0, divider.bounds.w);
            break :blk @as(f32, @floatFromInt(offset)) / @as(f32, @floatFromInt(divider.bounds.w));
        },
        .vertical => blk: {
            if (divider.bounds.h <= DIVIDER_THICKNESS) break :blk sp.ratio;
            const absolute_y = divider.rect.y + y;
            const offset = std.math.clamp(absolute_y - divider.bounds.y, 0, divider.bounds.h);
            break :blk @as(f32, @floatFromInt(offset)) / @as(f32, @floatFromInt(divider.bounds.h));
        },
    };
    sp.ratio = std.math.clamp(new_ratio, 0.1, 0.9);
    self.relayout();
}

fn handleDividerMessage(self: *Window, divider: *DividerState, hwnd: HWND, msg: UINT, wparam: WPARAM, lparam: LPARAM) LRESULT {
    switch (msg) {
        WM_PAINT => {
            var ps: sys.PAINTSTRUCT = std.mem.zeroes(sys.PAINTSTRUCT);
            const hdc = sys.BeginPaint(hwnd, &ps);
            var rect: RECT = std.mem.zeroes(RECT);
            _ = sys.GetClientRect(hwnd, &rect);
            const bg_brush = CreateSolidBrush(0x00E4E4E4);
            if (bg_brush != null) {
                _ = FillRect(hdc, &rect, bg_brush);
                _ = DeleteObject(bg_brush);
            }
            var line_rect = rect;
            if (divider.direction == .horizontal) {
                line_rect.left = @divTrunc(rect.right - rect.left - 2, 2);
                line_rect.right = line_rect.left + 2;
            } else {
                line_rect.top = @divTrunc(rect.bottom - rect.top - 2, 2);
                line_rect.bottom = line_rect.top + 2;
            }
            const line_brush = CreateSolidBrush(0x00858585);
            if (line_brush != null) {
                _ = FillRect(hdc, &line_rect, line_brush);
                _ = DeleteObject(line_brush);
            }
            _ = sys.EndPaint(hwnd, &ps);
            return 0;
        },
        WM_SETCURSOR => {
            _ = SetCursor(sys.LoadCursorW(
                null,
                if (divider.direction == .horizontal) IDC_SIZEWE else IDC_SIZENS,
            ));
            return 1;
        },
        WM_LBUTTONDOWN => {
            self.drag = .{ .divider = divider };
            _ = SetCapture(hwnd);
            self.adjustDividerRatio(divider, lparam);
            return 0;
        },
        WM_MOUSEMOVE => {
            if (self.drag) |drag| {
                if (drag.divider == divider) self.adjustDividerRatio(divider, lparam);
            }
            return 0;
        },
        WM_LBUTTONUP, WM_CAPTURECHANGED => {
            if (self.drag) |drag| {
                if (drag.divider == divider) {
                    self.drag = null;
                    _ = ReleaseCapture();
                }
            }
            return 0;
        },
        else => return sys.DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

fn makeTabTitle(self: *Window, requested: ?[:0]const u8, index: usize) ![:0]const u8 {
    if (requested) |title| return try self.app.alloc.dupeZ(u8, title);
    return try std.fmt.allocPrintSentinel(self.app.alloc, "Tab {d}", .{index + 1}, 0);
}

fn insertTab(self: *Window, raw_index: usize, opts: CreateOptions, select: bool) !usize {
    const alloc = self.app.alloc;
    const surface = try alloc.create(Surface);
    errdefer alloc.destroy(surface);
    surface.* = .{ .hwnd = undefined };

    try surface.init(self.hwnd.?, self.app);
    surface.window = self;
    errdefer surface.deinit();

    try self.initCoreSurface(surface, opts);
    errdefer {
        if (surface.core_surface) |core| {
            core.deinit();
            alloc.destroy(core);
            surface.core_surface = null;
        }
    }

    const tab: TabState = .{
        .primary_surface = surface,
        .tree = try SplitTree.initLeaf(alloc, surface),
        .focused_surface = surface,
        .title = try self.makeTabTitle(opts.title, raw_index),
    };
    errdefer alloc.free(tab.title);

    const index = @min(raw_index, self.tabs.items.len);
    if (self.tabs.items.len > 0) self.syncActiveTabFromWindow();
    try self.tabs.insert(alloc, index, tab);

    if (self.tabs.items.len == 1) {
        self.current_tab = 0;
        self.loadActiveTabIntoWindow();
    } else if (index <= self.current_tab and !select) {
        self.current_tab += 1;
    }

    self.rebuildTabControl();
    self.updateTabVisibility();

    if (select or self.tabs.items.len == 1) {
        try self.activateTab(index);
    } else {
        self.hideTabSurfaces(&self.tabs.items[index]);
        self.invalidateTopBar();
    }

    return index;
}

fn deinitTab(self: *Window, tab: *TabState) void {
    var leaves: [64]*Surface = undefined;
    const count = tab.tree.collectLeaves(&leaves);
    for (leaves[0..count]) |surface| {
        self.app.core_app.deleteSurface(surface);
        if (surface.core_surface) |core| {
            core.deinit();
            self.app.alloc.destroy(core);
            surface.core_surface = null;
        }
        surface.deinit();
        self.app.alloc.destroy(surface);
    }
    tab.tree.deinit(self.app.alloc);
    self.app.alloc.free(tab.title);
}

fn syncActiveTabFromWindow(self: *Window) void {
    if (self.tabs.items.len == 0 or self.current_tab >= self.tabs.items.len) return;
    const tab = &self.tabs.items[self.current_tab];
    tab.primary_surface = self.primary_surface;
    tab.tree = self.tree orelse return;
    tab.focused_surface = self.focused_surface orelse self.primary_surface;
}

fn loadActiveTabIntoWindow(self: *Window) void {
    const tab = &self.tabs.items[self.current_tab];
    self.primary_surface = tab.primary_surface;
    self.tree = tab.tree;
    self.focused_surface = tab.focused_surface orelse tab.primary_surface;
    self.surface_initialized = true;
}

fn activeTab(self: *Window) ?*TabState {
    if (self.tabs.items.len == 0 or self.current_tab >= self.tabs.items.len) return null;
    return &self.tabs.items[self.current_tab];
}

pub fn getFocusedSurface(self: *Window) ?*Surface {
    return self.focused_surface orelse if (self.tabs.items.len > 0) self.primary_surface else null;
}

pub fn getActiveTabTitle(self: *Window) ?[:0]const u8 {
    const tab = self.activeTab() orelse return null;
    return tab.title;
}

pub fn setActiveTabTitle(self: *Window, title: [:0]const u8) !void {
    const tab = self.activeTab() orelse return;
    self.app.alloc.free(tab.title);
    tab.title = try self.app.alloc.dupeZ(u8, title);
    self.updateTabControlTitle(self.current_tab);
}

pub fn setTabTitle(self: *Window, tab_index: usize, title: [:0]const u8) !void {
    if (tab_index >= self.tabs.items.len) return;
    const tab = &self.tabs.items[tab_index];
    self.app.alloc.free(tab.title);
    tab.title = try self.app.alloc.dupeZ(u8, title);
    self.updateTabControlTitle(tab_index);
}

pub fn setTabColor(self: *Window, tab_index: usize, color: ?configpkg.Config.Color) void {
    if (tab_index >= self.tabs.items.len) return;
    self.tabs.items[tab_index].color = color;
    self.invalidateTopBar();
}

fn updateTabVisibility(self: *Window) void {
    self.invalidateTopBar();
}

fn tabClientHeight(_: *Window) i32 {
    return TOP_BAR_HEIGHT;
}

fn tabWidth(tab_count: usize, available_width: i32) i32 {
    if (tab_count == 0) return CUSTOM_TAB_WIDTH;
    const total_gap = @max(0, @as(i32, @intCast(tab_count)) - 1) * TAB_GAP;
    const max_total_width = @as(i32, @intCast(tab_count)) * CUSTOM_TAB_WIDTH + total_gap;
    if (max_total_width <= available_width) return CUSTOM_TAB_WIDTH;
    const w = @divTrunc(available_width - total_gap, @as(i32, @intCast(tab_count)));
    return @max(MIN_TAB_WIDTH, w);
}

fn measureTabTextWidth(
    factory: *d2d.IDWriteFactory,
    format: *d2d.IDWriteTextFormat,
    title: [:0]const u8,
    alloc: Allocator,
) i32 {
    const utf16 = std.unicode.utf8ToUtf16LeAllocZ(alloc, title) catch return 0;
    defer alloc.free(utf16);

    var layout: *d2d.IDWriteTextLayout = undefined;
    const hr = factory.CreateTextLayout(
        utf16.ptr,
        @intCast(utf16.len),
        format,
        10000.0,
        100.0,
        &layout,
    );
    if (d2d.failed(hr)) return 0;
    defer _ = layout.IUnknown.Release();

    var metrics: d2d.DWRITE_TEXT_METRICS = undefined;
    const hr2 = layout.GetMetrics(&metrics);
    if (d2d.failed(hr2)) return 0;

    return @intFromFloat(@ceil(metrics.widthIncludingTrailingWhitespace));
}

fn truncateTabTitle(
    alloc: Allocator,
    title: [:0]const u8,
    max_width: i32,
    text_width: i32,
) Allocator.Error![:0]u8 {
    if (text_width <= max_width or title.len <= 3) {
        return alloc.dupeZ(u8, title);
    }
    const ratio = @as(f32, @floatFromInt(max_width - 15)) / @as(f32, @floatFromInt(text_width));
    const keep = @max(1, @as(usize, @intFromFloat(@floor(@as(f32, @floatFromInt(title.len)) * ratio))));
    const truncated = try std.fmt.allocPrint(alloc, "{s}...", .{title[0..keep]});
    defer alloc.free(truncated);
    return alloc.dupeZ(u8, truncated);
}

fn compactTitle(title: [:0]const u8, alloc: Allocator) Allocator.Error![:0]u8 {
    const has_path_sep = std.mem.indexOfAny(u8, title, "/\\") != null;
    const name = if (has_path_sep) std.fs.path.basename(title) else title;
    const name_no_ext = if (std.mem.lastIndexOf(u8, name, ".")) |idx| name[0..idx] else name;
    const first_word = if (std.mem.indexOf(u8, name_no_ext, " ")) |idx| name_no_ext[0..idx] else name_no_ext;
    return try alloc.dupeZ(u8, first_word);
}

fn invalidateTopBar(self: *Window) void {
    if (self.title_bar) |bar| _ = sys.InvalidateRect(bar.hwnd, null, 0);
}

fn tabLeaves(tab: *TabState, buf: []*Surface) []const *Surface {
    const count = tab.tree.collectLeaves(buf);
    return buf[0..count];
}

fn hideTabSurfaces(_: *Window, tab: *TabState) void {
    var leaves: [64]*Surface = undefined;
    for (tabLeaves(tab, &leaves)) |surface| {
        surface.setVisible(false);
    }
}

fn showTabSurfaces(_: *Window, tab: *TabState) void {
    var leaves: [64]*Surface = undefined;
    for (tabLeaves(tab, &leaves)) |surface| {
        surface.setVisible(true);
    }
}

fn rebuildTabControl(self: *Window) void {
    self.invalidateTopBar();
}

fn updateTabControlTitle(self: *Window, index: usize) void {
    _ = index;
    self.invalidateTopBar();
}

fn activateTab(self: *Window, index: usize) !void {
    if (self.tabs.items.len == 0 or index >= self.tabs.items.len) return;
    if (index == self.current_tab and self.tree != null) {
        self.invalidateTopBar();
        self.relayout();
        if (self.focused_surface) |surface| _ = sys.SetFocus(surface.hwnd);
        return;
    }

    if (self.tabs.items.len > 0 and self.tree != null and self.current_tab < self.tabs.items.len) {
        self.syncActiveTabFromWindow();
        self.hideTabSurfaces(&self.tabs.items[self.current_tab]);
    }

    self.current_tab = index;
    self.loadActiveTabIntoWindow();
    self.showTabSurfaces(&self.tabs.items[self.current_tab]);
    self.relayout();
    self.invalidateTopBar();
    if (self.focused_surface) |surface| _ = sys.SetFocus(surface.hwnd);
}

pub fn findTabIndexForSurface(self: *Window, surface: *Surface) ?usize {
    if (self.tabs.items.len == 0) return null;
    if (self.tree) |tree| {
        if (tree.findLeaf(surface) != null and self.current_tab < self.tabs.items.len) return self.current_tab;
    }
    for (self.tabs.items, 0..) |tab, i| {
        if (i == self.current_tab and self.tree != null) continue;
        if (tab.tree.findLeaf(surface) != null) return i;
    }
    return null;
}

fn closeTabAt(self: *Window, index: usize) void {
    if (index >= self.tabs.items.len) return;
    if (self.tabs.items.len <= 1) {
        if (self.hwnd) |hwnd| _ = sys.PostMessageW(hwnd, sys.WM_CLOSE, 0, 0);
        return;
    }
    const was_current = index == self.current_tab;
    if (self.tabs.items.len > 0 and self.tree != null and self.current_tab < self.tabs.items.len) {
        self.syncActiveTabFromWindow();
    }

    if (was_current) {
        self.tree = null;
        self.focused_surface = null;
        self.surface_initialized = false;
    } else {
        self.hideTabSurfaces(&self.tabs.items[index]);
    }

    var tab = self.tabs.orderedRemove(index);
    self.deinitTab(&tab);
    self.invalidateTopBar();

    if (self.tabs.items.len == 0) {
        self.tree = null;
        self.focused_surface = null;
        self.surface_initialized = false;
        self.app.closeWindow(self);
        return;
    }

    if (index < self.current_tab or self.current_tab >= self.tabs.items.len) {
        self.current_tab = if (self.current_tab == 0) 0 else self.current_tab - 1;
    }

    if (was_current) {
        // Rebind window state to the newly active tab before rebuilding the
        // tab control so any reentrant messages do not see a freed surface.
        self.loadActiveTabIntoWindow();
        // The newly active tab's surfaces may have been hidden by a prior tab
        // switch.  Make them visible now so the window is not blank.
        self.showTabSurfaces(&self.tabs.items[self.current_tab]);
    }

    self.updateTabVisibility();
    self.rebuildTabControl();
    if (was_current) {
        self.activateTab(self.current_tab) catch {};
    } else {
        self.relayout();
        if (self.focused_surface) |surface| _ = sys.SetFocus(surface.hwnd);
    }
}

fn closeEmptyTabAt(self: *Window, index: usize) void {
    if (index >= self.tabs.items.len) return;
    const was_current = index == self.current_tab;

    if (self.tabs.items.len > 0 and self.tree != null and self.current_tab < self.tabs.items.len) {
        self.syncActiveTabFromWindow();
    }

    if (was_current) {
        self.tree = null;
        self.focused_surface = null;
        self.surface_initialized = false;
    } else {
        self.hideTabSurfaces(&self.tabs.items[index]);
    }

    const tab = self.tabs.orderedRemove(index);
    self.app.alloc.free(tab.title);

    if (self.tabs.items.len == 0) {
        self.app.closeWindow(self);
        return;
    }

    if (index < self.current_tab or self.current_tab >= self.tabs.items.len) {
        self.current_tab = if (self.current_tab == 0) 0 else self.current_tab - 1;
    }

    if (was_current) {
        // Rebind window state to the newly active tab before rebuilding the
        // tab control so any reentrant messages do not see a freed surface.
        self.loadActiveTabIntoWindow();
        // The newly active tab's surfaces may have been hidden by a prior tab
        // switch.  Make them visible now so the window is not blank.
        self.showTabSurfaces(&self.tabs.items[self.current_tab]);
    }

    self.updateTabVisibility();
    self.rebuildTabControl();
    if (was_current) {
        self.activateTab(self.current_tab) catch {};
    } else {
        self.relayout();
        if (self.focused_surface) |surface| _ = sys.SetFocus(surface.hwnd);
    }
}

pub fn closeTab(self: *Window, mode: apprt.action.CloseTabMode) void {
    if (self.tabs.items.len == 0) return;
    switch (mode) {
        .this => self.closeTabAt(self.current_tab),
        .other => {
            var i = self.tabs.items.len;
            while (i > 0) {
                i -= 1;
                if (i == self.current_tab) continue;
                self.closeTabAt(i);
            }
        },
        .right => {
            var i = self.tabs.items.len;
            while (i > self.current_tab + 1) {
                i -= 1;
                self.closeTabAt(i);
            }
        },
    }
}

pub fn moveTab(self: *Window, amount: isize) bool {
    if (self.tabs.items.len <= 1 or amount == 0) return false;
    self.syncActiveTabFromWindow();
    const old_idx = self.current_tab;
    var desired: isize = @intCast(old_idx);
    desired = std.math.clamp(desired + amount, 0, @as(isize, @intCast(self.tabs.items.len - 1)));
    const new_idx: usize = @intCast(desired);
    if (new_idx == old_idx) return false;
    const moved = self.tabs.orderedRemove(old_idx);
    self.tabs.insert(self.app.alloc, new_idx, moved) catch return false;
    self.current_tab = new_idx;
    self.rebuildTabControl();
    self.activateTab(new_idx) catch {};
    return true;
}

pub fn gotoTab(self: *Window, target: apprt.action.GotoTab) bool {
    if (self.tabs.items.len == 0) return false;
    const idx: usize = switch (target) {
        .previous => (self.current_tab + self.tabs.items.len - 1) % self.tabs.items.len,
        .next => (self.current_tab + 1) % self.tabs.items.len,
        .last => self.tabs.items.len - 1,
        else => blk: {
            const raw: i32 = @intFromEnum(target);
            if (raw < 0) break :blk self.current_tab;
            break :blk @min(@as(usize, @intCast(raw)), self.tabs.items.len - 1);
        },
    };
    self.activateTab(idx) catch return false;
    return true;
}

pub fn focusSurface(self: *Window, surface: *Surface) void {
    const idx = self.findTabIndexForSurface(surface) orelse return;
    if (idx != self.current_tab) self.activateTab(idx) catch return;
    self.focused_surface = surface;
    if (self.current_tab < self.tabs.items.len) {
        self.tabs.items[self.current_tab].focused_surface = surface;
    }
}

pub fn initCoreSurface(self: *Window, surface: *Surface, opts: CreateOptions) !void {
    const alloc = self.app.alloc;
    const core = try alloc.create(CoreSurface);
    errdefer alloc.destroy(core);

    try self.app.core_app.addSurface(surface);
    errdefer self.app.core_app.deleteSurface(surface);

    var config = try apprt.surface.newConfig(self.app.core_app, self.app.config, .window);
    defer config.deinit();

    if (opts.command) |cmd| config.command = try cmd.clone(alloc);
    if (opts.working_directory) |wd| config.@"working-directory" = try wd.clone(alloc);
    if (opts.title) |title| config.title = try alloc.dupeZ(u8, title);

    try core.init(alloc, &config, self.app.core_app, self.app, surface);
    errdefer core.deinit();
    surface.core_surface = core;
}

pub fn applyConfiguredWindowSize(self: *Window) void {
    const cfg_w = if (self.app.config.@"window-width" > 0) self.app.config.@"window-width" else 80;
    const cfg_h = if (self.app.config.@"window-height" > 0) self.app.config.@"window-height" else 24;
    const hwnd = self.hwnd orelse return;
    const core = self.primary_surface.core_surface orelse return;

    const cell_width = core.size.cell.width;
    const cell_height = core.size.cell.height;
    if (cell_width == 0 or cell_height == 0) return;

    const w: i32 = @intCast(@max(10, cfg_w) * cell_width);
    const h: i32 = @intCast(@as(i32, @intCast(@max(4, cfg_h) * cell_height)) + self.tabClientHeight());

    var rect: RECT = .{ .left = 0, .top = 0, .right = w, .bottom = h };
    _ = sys.AdjustWindowRectEx(&rect, TOPLEVEL_STYLE, 0, 0);
    _ = sys.SetWindowPos(hwnd, null, 0, 0, rect.right - rect.left, rect.bottom - rect.top, 0x0002 | 0x0004);
}

pub fn applyQuickTerminalLayout(self: *Window) void {
    const hwnd = self.hwnd orelse return;
    var mi: sys.MONITORINFO = std.mem.zeroes(sys.MONITORINFO);
    mi.cbSize = @sizeOf(sys.MONITORINFO);
    const monitor = sys.MonitorFromWindow(hwnd, 2);
    if (sys.GetMonitorInfoW(monitor, &mi) == 0) return;

    const dims: configpkg.Config.QuickTerminalSize.Dimensions = .{
        .width = @intCast(mi.rcWork.right - mi.rcWork.left),
        .height = @intCast(mi.rcWork.bottom - mi.rcWork.top),
    };
    const size = self.app.config.@"quick-terminal-size".calculate(
        self.app.config.@"quick-terminal-position",
        dims,
    );

    const width: i32 = @intCast(size.width);
    const height: i32 = @intCast(size.height);
    const work_w = mi.rcWork.right - mi.rcWork.left;
    const work_h = mi.rcWork.bottom - mi.rcWork.top;
    const origin: struct { x: i32, y: i32 } = switch (self.app.config.@"quick-terminal-position") {
        .top => .{ .x = mi.rcWork.left + @divTrunc(work_w - width, 2), .y = mi.rcWork.top },
        .bottom => .{ .x = mi.rcWork.left + @divTrunc(work_w - width, 2), .y = mi.rcWork.bottom - height },
        .left => .{ .x = mi.rcWork.left, .y = mi.rcWork.top + @divTrunc(work_h - height, 2) },
        .right => .{ .x = mi.rcWork.right - width, .y = mi.rcWork.top + @divTrunc(work_h - height, 2) },
        .center => .{
            .x = mi.rcWork.left + @divTrunc(work_w - width, 2),
            .y = mi.rcWork.top + @divTrunc(work_h - height, 2),
        },
    };

    _ = sys.SetWindowPos(hwnd, @ptrFromInt(@as(usize, @bitCast(@as(isize, -1)))), origin.x, origin.y, width, height, 0x0004);
}

pub fn relayout(self: *Window) void {
    const tree = &(self.tree orelse return);
    const hwnd = self.hwnd orelse return;
    var rect: RECT = std.mem.zeroes(RECT);
    if (sys.GetClientRect(hwnd, &rect) == 0) return;
    self.invalidateTopBar();
    const tab_h = self.tabClientHeight();
    const inset = self.visibleClientInset();
    const client_w = rect.right - rect.left;
    const client_h = rect.bottom - rect.top;
    const visible_w = @max(1, client_w - inset.left - inset.right);
    const visible_h = @max(tab_h + 1, client_h - inset.top - inset.bottom);
    if (self.title_bar) |bar| {
        _ = sys.SetWindowPos(
            bar.hwnd,
            HWND_TOP,
            inset.left,
            inset.top,
            visible_w,
            tab_h,
            SWP_NOACTIVATE,
        );
    }
    const bounds = SplitTree.Rect{
        .x = inset.left,
        .y = inset.top + tab_h,
        .w = visible_w,
        .h = @max(1, visible_h - tab_h),
    };
    tree.layout(bounds, relayoutCb);
    self.updateDividers(bounds);
}

pub fn beginWindowResize(self: *Window) void {
    self.in_window_resize = true;
    self.pending_core_resize = false;
    self.pending_window_relayout = false;
    self.hideVisibleScrollbars();
}

pub fn endWindowResize(self: *Window) void {
    self.in_window_resize = false;
    if (self.pending_window_relayout) {
        self.pending_window_relayout = false;
        self.relayout();
    }
    if (self.pending_core_resize) {
        self.pending_core_resize = false;
        self.commitVisibleSurfaceSizes();
    }
    self.refreshVisibleScrollbars();
    self.forceFullRedraw();
}

pub fn deferCoreResize(self: *Window) bool {
    if (!self.in_window_resize) return false;
    self.pending_core_resize = true;
    return true;
}

pub fn deferWindowRelayout(self: *Window) bool {
    if (!self.in_window_resize) return false;
    self.pending_window_relayout = true;
    return true;
}

fn commitVisibleSurfaceSizes(self: *Window) void {
    const tree = &(self.tree orelse return);
    var leaves: [64]*Surface = undefined;
    const count = tree.collectLeaves(&leaves);
    for (leaves[0..count]) |surface| {
        surface.commitCoreResize();
    }
}

fn hideVisibleScrollbars(self: *Window) void {
    const tree = &(self.tree orelse return);
    var leaves: [64]*Surface = undefined;
    const count = tree.collectLeaves(&leaves);
    for (leaves[0..count]) |surface| {
        surface.hideScrollbarOverlay();
    }
}

fn refreshVisibleScrollbars(self: *Window) void {
    const tree = &(self.tree orelse return);
    var leaves: [64]*Surface = undefined;
    const count = tree.collectLeaves(&leaves);
    for (leaves[0..count]) |surface| {
        surface.refreshScrollbarOverlay();
    }
}

pub fn forceFullRedraw(self: *Window) void {
    const hwnd = self.hwnd orelse return;
    _ = sys.RedrawWindow(
        hwnd,
        null,
        null,
        sys.RDW_INVALIDATE | sys.RDW_ERASE | sys.RDW_ALLCHILDREN | sys.RDW_UPDATENOW,
    );
}

fn visibleClientInset(self: *Window) ClientInset {
    const hwnd = self.hwnd orelse return .{};
    if (self.fullscreen.active or sys.IsZoomed(hwnd) == 0) return .{};

    return .{
        .left = resizeBorderX(),
        .top = resizeBorderY(),
        .right = resizeBorderX(),
        .bottom = resizeBorderY(),
    };
}

fn relayoutCb(surface: *Surface, rect: SplitTree.Rect) void {
    surface.setLayoutRect(rect.x, rect.y, rect.w, rect.h);
    _ = sys.SetWindowPos(surface.hwnd, null, rect.x, rect.y, rect.w, rect.h, 0x0004);
}

pub fn newTab(self: *Window, opts: CreateOptions) !void {
    const insert_at = if (self.tabs.items.len == 0) 0 else self.current_tab + 1;
    _ = try self.insertTab(insert_at, opts, true);
}

fn newProfileTab(self: *Window, command: ProfileMenuCommand) !void {
    var opts = try self.createProfileOptions(command);
    defer opts.deinit(self.app.alloc);
    try self.newTab(opts);
}

fn createProfileOptions(self: *Window, command: ProfileMenuCommand) !CreateOptions {
    return switch (command) {
        .default => .none,
        .cmd => try self.createDirectCommandOptions(&.{"cmd.exe"}),
        .powershell => try self.createDirectCommandOptions(&.{"powershell.exe"}),
        .pwsh => try self.createDirectCommandOptions(&.{"C:\\Program Files\\PowerShell\\7\\pwsh.exe"}),
    };
}

fn createDirectCommandOptions(self: *Window, args: []const []const u8) !CreateOptions {
    const alloc = self.app.alloc;
    const direct = try alloc.alloc([:0]const u8, args.len);
    errdefer alloc.free(direct);
    for (args, 0..) |arg, i| {
        direct[i] = try alloc.dupeZ(u8, arg);
    }
    return .{ .command = .{ .direct = direct } };
}

pub fn newSplit(self: *Window, existing: *Surface, dir: apprt.action.SplitDirection) !void {
    const tree = &(self.tree orelse return error.NoTree);
    const alloc = self.app.alloc;

    const new_surface = try alloc.create(Surface);
    errdefer alloc.destroy(new_surface);
    new_surface.* = .{ .hwnd = undefined };

    try new_surface.init(self.hwnd.?, self.app);
    new_surface.window = self;
    errdefer new_surface.deinit();

    try self.initCoreSurface(new_surface, .none);
    errdefer {
        if (new_surface.core_surface) |core| {
            core.deinit();
            alloc.destroy(core);
        }
    }

    const split_dir: SplitTree.Direction = switch (dir) {
        .right, .left => .horizontal,
        .down, .up => .vertical,
    };
    const after = dir == .right or dir == .down;
    try tree.split(alloc, existing, new_surface, split_dir, after);

    self.focused_surface = new_surface;
    if (self.current_tab < self.tabs.items.len) {
        self.tabs.items[self.current_tab].focused_surface = new_surface;
    }
    _ = sys.SetFocus(new_surface.hwnd);
    self.relayout();
}

pub fn closeSurface(self: *Window, surface: *Surface) void {
    const tab_idx = self.findTabIndexForSurface(surface) orelse return;
    const use_active = tab_idx == self.current_tab and self.tree != null;
    var tree_copy = if (use_active) self.tree.? else self.tabs.items[tab_idx].tree;
    const tree = &tree_copy;
    const alloc = self.app.alloc;

    self.app.core_app.deleteSurface(surface);
    if (surface.core_surface) |core| {
        core.deinit();
        alloc.destroy(core);
        surface.core_surface = null;
    }
    surface.deinit();

    const result = tree.removeLeaf(alloc, surface);
    alloc.destroy(surface);

    if (result.empty) {
        self.closeEmptyTabAt(tab_idx);
        return;
    }

    if (use_active) {
        self.tree = tree_copy;
        self.focused_surface = result.focus;
        if (self.current_tab < self.tabs.items.len) {
            self.tabs.items[self.current_tab].focused_surface = result.focus;
        }
        if (result.focus) |focus| _ = sys.SetFocus(focus.hwnd);
        self.relayout();
    } else {
        self.tabs.items[tab_idx].tree = tree_copy;
        self.tabs.items[tab_idx].focused_surface = result.focus;
    }
}

pub fn gotoSplit(self: *Window, target: apprt.action.GotoSplit) void {
    const tree = &(self.tree orelse return);
    const current = self.focused_surface orelse return;

    var buf: [32]SplitTree.LeafRect = undefined;
    const hwnd = self.hwnd orelse return;
    var cr: RECT = std.mem.zeroes(RECT);
    if (sys.GetClientRect(hwnd, &cr) == 0) return;
    const bounds: SplitTree.Rect = .{
        .x = 0,
        .y = self.tabClientHeight(),
        .w = cr.right - cr.left,
        .h = cr.bottom - cr.top - self.tabClientHeight(),
    };
    const count = tree.collectLeafRects(bounds, &buf);
    if (count == 0) return;

    var current_idx: usize = 0;
    for (buf[0..count], 0..) |lr, i| {
        if (lr.surface == current) {
            current_idx = i;
            break;
        }
    }

    const next_idx: usize = switch (target) {
        .next => (current_idx + 1) % count,
        .previous => (current_idx + count - 1) % count,
        .up, .down, .left, .right => blk: {
            const cur = buf[current_idx].rect;
            const cx = cur.x + @divTrunc(cur.w, 2);
            const cy = cur.y + @divTrunc(cur.h, 2);
            var best: ?usize = null;
            var best_dist: i64 = std.math.maxInt(i64);
            for (buf[0..count], 0..) |lr, i| {
                if (i == current_idx) continue;
                const lx = lr.rect.x + @divTrunc(lr.rect.w, 2);
                const ly = lr.rect.y + @divTrunc(lr.rect.h, 2);
                const in_direction = switch (target) {
                    .up => ly < cy,
                    .down => ly > cy,
                    .left => lx < cx,
                    .right => lx > cx,
                    else => false,
                };
                if (!in_direction) continue;
                const dx: i64 = @as(i64, lx) - @as(i64, cx);
                const dy: i64 = @as(i64, ly) - @as(i64, cy);
                const dist = dx * dx + dy * dy;
                if (dist < best_dist) {
                    best_dist = dist;
                    best = i;
                }
            }
            break :blk best orelse return;
        },
    };

    const new_focus = buf[next_idx].surface;
    self.focused_surface = new_focus;
    if (self.current_tab < self.tabs.items.len) self.tabs.items[self.current_tab].focused_surface = new_focus;
    _ = sys.SetFocus(new_focus.hwnd);
}

pub fn equalizeSplits(self: *Window) void {
    const tree = &(self.tree orelse return);
    equalizeNode(tree.root);
    self.relayout();
}

fn equalizeNode(node: *SplitTree.Node) void {
    switch (node.*) {
        .leaf => {},
        .split => |*sp| {
            sp.ratio = 0.5;
            equalizeNode(sp.children[0]);
            equalizeNode(sp.children[1]);
        },
    }
}

pub fn resizeSplit(self: *Window, req: apprt.action.ResizeSplit) void {
    const tree = &(self.tree orelse return);
    const current = self.focused_surface orelse return;
    const want_horizontal = req.direction == .left or req.direction == .right;
    const grow = req.direction == .right or req.direction == .down;

    var path: [32]*SplitTree.Node = undefined;
    var path_len: usize = 0;
    if (!findPath(tree.root, current, &path, &path_len)) return;

    var i = path_len;
    while (i > 0) {
        i -= 1;
        const node = path[i];
        const sp = switch (node.*) {
            .split => |*v| v,
            .leaf => continue,
        };
        const matches = switch (sp.direction) {
            .horizontal => want_horizontal,
            .vertical => !want_horizontal,
        };
        if (!matches) continue;

        const first_contains = containsLeaf(sp.children[0], current);
        const delta: f32 = @as(f32, @floatFromInt(req.amount)) / 400.0;
        var new_ratio = sp.ratio;
        if (first_contains) {
            new_ratio += if (grow) delta else -delta;
        } else {
            new_ratio += if (grow) -delta else delta;
        }
        sp.ratio = std.math.clamp(new_ratio, 0.1, 0.9);
        self.relayout();
        return;
    }
}

fn findPath(node: *SplitTree.Node, target: *Surface, path: []*SplitTree.Node, len: *usize) bool {
    if (len.* >= path.len) return false;
    path[len.*] = node;
    len.* += 1;
    switch (node.*) {
        .leaf => |s| if (s == target) return true,
        .split => |sp| {
            if (findPath(sp.children[0], target, path, len)) return true;
            if (findPath(sp.children[1], target, path, len)) return true;
        },
    }
    len.* -= 1;
    return false;
}

fn containsLeaf(node: *SplitTree.Node, target: *Surface) bool {
    return switch (node.*) {
        .leaf => |s| s == target,
        .split => |sp| containsLeaf(sp.children[0], target) or containsLeaf(sp.children[1], target),
    };
}

pub fn handleTopLevelMessage(self: *Window, msg: UINT, wparam: WPARAM, lparam: LPARAM) ?LRESULT {
    switch (msg) {
        sys.WM_NCCALCSIZE => return 0,
        sys.WM_NCHITTEST => return self.hitTestTopLevel(lparam),
        sys.WM_APP_CLOSE_TAB => {
            self.closeTabAt(wparam);
            return 0;
        },
        sys.WM_APP_NEW_TAB => {
            self.newTab(.none) catch {};
            return 0;
        },
        sys.WM_APP_NEW_PROFILE_TAB => {
            self.newProfileTab(@enumFromInt(@as(u16, @intCast(wparam)))) catch {};
            return 0;
        },
        WM_PAINT => {
            self.paintTopBar(self.hwnd orelse return 0);
            return 0;
        },
        sys.WM_NCLBUTTONUP => {
            switch (@as(LRESULT, @intCast(wparam))) {
                sys.HTMINBUTTON => {
                    self.minimize();
                    return 0;
                },
                sys.HTMAXBUTTON => {
                    self.toggleMaximize();
                    return 0;
                },
                else => {},
            }
        },
        WM_LBUTTONDOWN => {
            return 0;
        },
        else => {},
    }
    return null;
}

pub fn hitTestTopLevel(self: *Window, lparam: LPARAM) LRESULT {
    return self.hitTestPoint(signExtendLowWord(lparam), signExtendHighWord(lparam));
}

pub fn isResizeHit(_: *Window, hit: LRESULT) bool {
    return switch (hit) {
        sys.HTLEFT,
        sys.HTRIGHT,
        sys.HTTOP,
        sys.HTTOPLEFT,
        sys.HTTOPRIGHT,
        sys.HTBOTTOM,
        sys.HTBOTTOMLEFT,
        sys.HTBOTTOMRIGHT,
        => true,
        else => false,
    };
}

pub fn rightResizeGutter(self: *Window) i32 {
    const hwnd = self.hwnd orelse return 0;
    if (self.fullscreen.active or sys.IsZoomed(hwnd) != 0) return 0;
    return resizeBorderX();
}

pub fn hitTestPoint(self: *Window, x: i32, y: i32) LRESULT {
    const hwnd = self.hwnd orelse return sys.HTCLIENT;

    var rect: RECT = std.mem.zeroes(RECT);
    if (sys.GetWindowRect(hwnd, &rect) == 0) return sys.HTCLIENT;

    const border_x = resizeBorderX();
    const border_y = resizeBorderY();

    if (!self.fullscreen.active and sys.IsZoomed(hwnd) == 0) {
        const left = x >= rect.left and x < rect.left + border_x;
        const right = x < rect.right and x >= rect.right - border_x;
        const top = y >= rect.top and y < rect.top + border_y;
        const bottom = y < rect.bottom and y >= rect.bottom - border_y;

        if (top and left) return sys.HTTOPLEFT;
        if (top and right) return sys.HTTOPRIGHT;
        if (bottom and left) return sys.HTBOTTOMLEFT;
        if (bottom and right) return sys.HTBOTTOMRIGHT;
        if (top) return sys.HTTOP;
        if (bottom) return sys.HTBOTTOM;
        if (left) return sys.HTLEFT;
        if (right) return sys.HTRIGHT;
    }

    if (self.hitTestScrollbarScreenPoint(hwnd, x, y)) return sys.HTCLIENT;

    if (y < rect.top + self.tabClientHeight()) {
        const button_area_left = rect.right - WINDOW_BUTTON_WIDTH * WINDOW_BUTTON_COUNT;
        if (x >= button_area_left and y < rect.top + TITLE_BUTTON_HIT_HEIGHT) {
            const idx = @divTrunc(x - button_area_left, WINDOW_BUTTON_WIDTH);
            return switch (idx) {
                0 => sys.HTMINBUTTON,
                1 => sys.HTMAXBUTTON,
                else => sys.HTCLIENT,
            };
        }
        return sys.HTCAPTION;
    }
    return sys.HTCLIENT;
}

fn hitTestScrollbarScreenPoint(self: *Window, hwnd: HWND, x: i32, y: i32) bool {
    const tree = &(self.tree orelse return false);
    var pt: sys.POINT = .{ .x = x, .y = y };
    if (ScreenToClient(hwnd, &pt) == 0) return false;

    var leaves: [64]*Surface = undefined;
    const count = tree.collectLeaves(&leaves);
    for (leaves[0..count]) |surface| {
        if (surface.scrollbarWindowHitTest(pt.x, pt.y)) return true;
    }
    return false;
}

fn resizeBorderX() i32 {
    return @max(sys.GetSystemMetrics(sys.SM_CXFRAME) + sys.GetSystemMetrics(sys.SM_CXPADDEDBORDER), 8);
}

fn resizeBorderY() i32 {
    return @max(sys.GetSystemMetrics(sys.SM_CYFRAME) + sys.GetSystemMetrics(sys.SM_CXPADDEDBORDER), 8);
}

fn lparamX(value: LPARAM) i32 {
    return signExtendLowWord(value);
}

fn lparamY(value: LPARAM) i32 {
    return signExtendHighWord(value);
}

fn signExtendLowWord(value: LPARAM) i32 {
    return @as(i16, @bitCast(@as(u16, @truncate(@as(usize, @bitCast(value))))));
}

fn signExtendHighWord(value: LPARAM) i32 {
    return @as(i16, @bitCast(@as(u16, @truncate(@as(usize, @bitCast(value)) >> 16))));
}

pub fn toggleFullscreen(self: *Window) void {
    const hwnd = self.hwnd orelse return;
    if (self.fullscreen.active) {
        _ = sys.SetWindowLongW(hwnd, sys.GWL_STYLE, self.fullscreen.style);
        _ = sys.SetWindowLongW(hwnd, sys.GWL_EXSTYLE, self.fullscreen.ex_style);
        _ = sys.SetWindowPos(
            hwnd,
            null,
            self.fullscreen.rect.left,
            self.fullscreen.rect.top,
            self.fullscreen.rect.right - self.fullscreen.rect.left,
            self.fullscreen.rect.bottom - self.fullscreen.rect.top,
            0x0020 | 0x0004,
        );
        self.fullscreen.active = false;
    } else {
        self.fullscreen.style = @intCast(sys.GetWindowLongW(hwnd, sys.GWL_STYLE));
        self.fullscreen.ex_style = @intCast(sys.GetWindowLongW(hwnd, sys.GWL_EXSTYLE));
        _ = sys.GetWindowRect(hwnd, &self.fullscreen.rect);

        var mi: sys.MONITORINFO = std.mem.zeroes(sys.MONITORINFO);
        mi.cbSize = @sizeOf(sys.MONITORINFO);
        const monitor = sys.MonitorFromWindow(hwnd, 2);
        if (sys.GetMonitorInfoW(monitor, &mi) == 0) return;

        const new_style = self.fullscreen.style & ~@as(i32, @bitCast(@as(u32, sys.WS_OVERLAPPEDWINDOW)));
        _ = sys.SetWindowLongW(hwnd, sys.GWL_STYLE, new_style);
        _ = sys.SetWindowPos(
            hwnd,
            null,
            mi.rcMonitor.left,
            mi.rcMonitor.top,
            mi.rcMonitor.right - mi.rcMonitor.left,
            mi.rcMonitor.bottom - mi.rcMonitor.top,
            0x0020 | 0x0004,
        );
        self.fullscreen.active = true;
    }
}
