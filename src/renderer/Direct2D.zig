const Direct2D = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const apprt = @import("../apprt.zig");
const configpkg = @import("../config.zig");
const font = @import("../font/main.zig");
const inputpkg = @import("../input.zig");
const renderer = @import("../renderer.zig");
const renderer_link = @import("link.zig");
const terminal = @import("../terminal/main.zig");
const d2d = @import("../apprt/win32/d2d.zig");

const log = std.log.scoped(.direct2d_renderer);

alloc: Allocator,
rt_surface: *apprt.Surface,
surface_mailbox: apprt.surface.Mailbox,
font_grid: *font.SharedGrid,
size: renderer.Size,
config: DerivedConfig,
terminal_state: terminal.RenderState = .empty,
target: ?*d2d.ID2D1HwndRenderTarget = null,
d2d_factory: ?*d2d.ID2D1Factory = null,
dwrite_factory: ?*d2d.IDWriteFactory = null,
text_formats: TextFormats = .{},
text_layout_cache: TextLayoutCache = .{},
text_buf: std.ArrayListUnmanaged(u16) = .empty,
cursor_style: ?renderer.CursorStyle = null,
preedit: ?renderer.State.Preedit = null,
links: terminal.RenderState.CellSet = .empty,
scrollbar: terminal.Scrollbar = .zero,
scrollbar_dirty: bool = false,
last_bottom_node: ?usize = null,
last_bottom_y: terminal.size.CellCountInt = 0,
focused: bool = true,
visible: bool = true,
search_matches: ?renderer.Message.SearchMatches = null,
search_selected_match: ?renderer.Message.SearchMatch = null,
search_matches_dirty: bool = false,

pub const DerivedConfig = struct {
    arena: ArenaAllocator,
    @"font-family": configpkg.RepeatableString,
    font_size: f32,
    background: terminal.color.RGB,
    background_opacity: f64,
    background_opacity_cells: bool,
    foreground: terminal.color.RGB,
    bold_color: ?terminal.Style.BoldColor,
    cursor_color: ?configpkg.Config.TerminalColor,
    cursor_opacity: f64,
    cursor_text: ?configpkg.Config.TerminalColor,
    selection_background: ?configpkg.Config.TerminalColor,
    selection_foreground: ?configpkg.Config.TerminalColor,
    search_background: configpkg.Config.TerminalColor,
    search_foreground: configpkg.Config.TerminalColor,
    search_selected_background: configpkg.Config.TerminalColor,
    search_selected_foreground: configpkg.Config.TerminalColor,
    faint_opacity: u8,
    links: renderer_link.Set,
    background_blur: configpkg.Config.BackgroundBlur,
    scrollbar: configpkg.Config.Scrollbar,
    scroll_to_bottom_on_output: bool,

    pub fn init(alloc_gpa: Allocator, config: *const configpkg.Config) !DerivedConfig {
        var arena = ArenaAllocator.init(alloc_gpa);
        errdefer arena.deinit();
        const alloc = arena.allocator();
        var links = try renderer_link.Set.fromConfig(
            alloc,
            config.link.links.items,
        );
        errdefer links.deinit(alloc);

        return .{
            .arena = arena,
            .@"font-family" = try config.@"font-family".clone(alloc),
            .font_size = config.@"font-size",
            .background = config.background.toTerminalRGB(),
            .background_opacity = @max(0, @min(1, config.@"background-opacity")),
            .background_opacity_cells = config.@"background-opacity-cells",
            .foreground = config.foreground.toTerminalRGB(),
            .bold_color = if (config.@"bold-color") |b| b.toTerminal() else null,
            .cursor_color = config.@"cursor-color",
            .cursor_opacity = @max(0, @min(1, config.@"cursor-opacity")),
            .cursor_text = config.@"cursor-text",
            .selection_background = config.@"selection-background",
            .selection_foreground = config.@"selection-foreground",
            .search_background = config.@"search-background",
            .search_foreground = config.@"search-foreground",
            .search_selected_background = config.@"search-selected-background",
            .search_selected_foreground = config.@"search-selected-foreground",
            .faint_opacity = @intFromFloat(@ceil(config.@"faint-opacity" * 255)),
            .links = links,
            .background_blur = config.@"background-blur",
            .scrollbar = config.scrollbar,
            .scroll_to_bottom_on_output = config.@"scroll-to-bottom".output,
        };
    }

    pub fn deinit(self: *DerivedConfig) void {
        const alloc = self.arena.allocator();
        self.links.deinit(alloc);
        self.arena.deinit();
    }
};

const TextFormats = struct {
    regular: ?*d2d.IDWriteTextFormat = null,
    bold: ?*d2d.IDWriteTextFormat = null,
    italic: ?*d2d.IDWriteTextFormat = null,
    bold_italic: ?*d2d.IDWriteTextFormat = null,
    emoji: ?*d2d.IDWriteTextFormat = null,

    fn get(self: *const TextFormats, style: terminal.Style) ?*d2d.IDWriteTextFormat {
        if (style.flags.bold and style.flags.italic) return self.bold_italic;
        if (style.flags.bold) return self.bold;
        if (style.flags.italic) return self.italic;
        return self.regular;
    }

    fn release(self: *TextFormats) void {
        releaseCom(self.regular);
        releaseCom(self.bold);
        releaseCom(self.italic);
        releaseCom(self.bold_italic);
        releaseCom(self.emoji);
        self.* = .{};
    }
};

const HighlightTag = enum(u8) {
    search_match,
    search_match_selected,
};

const SelectionKind = enum {
    false,
    selection,
    search,
    search_selected,
};

const CellColors = struct {
    bg: ?terminal.color.RGB,
    bg_alpha: f32,
    fg: terminal.color.RGB,
    fg_alpha: f32,
};

const TextLayoutCache = struct {
    const max_entries = 512;

    entries: std.ArrayListUnmanaged(Entry) = .empty,

    const Entry = struct {
        format: usize,
        width: u32,
        height: u32,
        text: []u16,
        layout: *d2d.IDWriteTextLayout,
        metrics: d2d.DWRITE_TEXT_METRICS,
    };

    fn deinit(self: *TextLayoutCache, alloc: Allocator) void {
        self.clear(alloc);
        self.entries.deinit(alloc);
    }

    fn clear(self: *TextLayoutCache, alloc: Allocator) void {
        for (self.entries.items) |entry| {
            releaseCom(entry.layout);
            alloc.free(entry.text);
        }
        self.entries.clearRetainingCapacity();
    }

    fn find(
        self: *TextLayoutCache,
        format: *d2d.IDWriteTextFormat,
        text: []const u16,
        width: u32,
        height: u32,
    ) ?*Entry {
        const format_key = @intFromPtr(format);
        for (self.entries.items) |*entry| {
            if (entry.format == format_key and
                entry.width == width and
                entry.height == height and
                std.mem.eql(u16, entry.text, text))
            {
                return entry;
            }
        }
        return null;
    }
};

pub fn init(alloc: Allocator, options: renderer.Options) !Direct2D {
    var result: Direct2D = .{
        .alloc = alloc,
        .rt_surface = options.rt_surface,
        .surface_mailbox = options.surface_mailbox,
        .font_grid = options.font_grid,
        .size = options.size,
        .config = options.config,
    };
    errdefer result.deinit();

    try result.initFactories();
    try result.recreateTextFormat();
    return result;
}

pub fn deinit(self: *Direct2D) void {
    if (self.search_matches) |*m| m.arena.deinit();
    if (self.search_selected_match) |*m| m.arena.deinit();
    if (self.preedit) |*p| p.deinit(self.alloc);
    self.links.deinit(self.alloc);
    self.text_buf.deinit(self.alloc);
    self.text_layout_cache.deinit(self.alloc);
    self.terminal_state.deinit(self.alloc);
    self.releaseDeviceResources();
    self.text_formats.release();
    releaseCom(self.dwrite_factory);
    releaseCom(self.d2d_factory);
    self.config.deinit();
}

pub fn surfaceInit(surface: *apprt.Surface) !void {
    _ = surface;
}

pub fn finalizeSurfaceInit(self: *Direct2D, surface: *apprt.Surface) !void {
    _ = self;
    _ = surface;
}

pub fn threadEnter(self: *Direct2D, surface: *apprt.Surface) !void {
    _ = surface;
    try self.ensureTarget();
}

pub fn threadExit(self: *Direct2D) void {
    _ = self;
}

pub fn hasVsync(self: *const Direct2D) bool {
    _ = self;
    return false;
}

pub fn hasAnimations(self: *const Direct2D) bool {
    _ = self;
    return false;
}

pub fn setVisible(self: *Direct2D, visible: bool) void {
    self.visible = visible;
}

pub fn setFocus(self: *Direct2D, focus: bool) !void {
    self.focused = focus;
    self.cursor_style = renderer.cursorStyle(&self.terminal_state, .{
        .focused = self.focused,
        .blink_visible = true,
    });
}

pub fn setFontGrid(self: *Direct2D, grid: *font.SharedGrid) void {
    self.font_grid = grid;
    self.recreateTextFormat() catch |err| {
        log.warn("failed to recreate DirectWrite text formats after font grid change err={}", .{err});
    };
}

pub fn setScreenSize(self: *Direct2D, size: renderer.Size) void {
    self.size = size;
    if (self.target) |target| {
        if (size.screen.width == 0 or size.screen.height == 0) return;
        var pixel_size: d2d.D2D_SIZE_U = .{
            .width = @max(1, size.screen.width),
            .height = @max(1, size.screen.height),
        };
        if (d2d.failed(target.Resize(&pixel_size))) {
            self.releaseDeviceResources();
        }
    }
}

pub fn changeConfig(self: *Direct2D, config: *DerivedConfig) !void {
    self.config.deinit();
    self.config = config.*;
    config.* = undefined;
    try self.recreateTextFormat();
}

pub fn updateFrame(
    self: *Direct2D,
    state: *renderer.State,
    cursor_blink_visible: bool,
) Allocator.Error!void {
    const critical = critical: {
        state.mutex.lock();
        defer state.mutex.unlock();

        if (state.terminal.modes.get(.synchronized_output)) return;

        if (self.config.scroll_to_bottom_on_output) {
            if (state.terminal.screens.active.pages.getBottomRight(.screen)) |br| {
                self.last_bottom_node = @intFromPtr(br.node);
                self.last_bottom_y = br.y;
            }
            state.terminal.scrollViewport(.bottom);
        }

        try self.terminal_state.update(self.alloc, state.terminal);
        const scrollbar = state.terminal.screens.active.pages.scrollbar();
        break :critical .{
            .preedit = if (state.preedit) |p| try p.clone(self.alloc) else null,
            .mouse_point = state.mouse.point,
            .mouse_mods = state.mouse.mods,
            .scrollbar = scrollbar,
        };
    };

    if (self.preedit) |*p| p.deinit(self.alloc);
    self.preedit = critical.preedit;

    self.cursor_style = renderer.cursorStyle(&self.terminal_state, .{
        .preedit = critical.preedit != null,
        .focused = self.focused,
        .blink_visible = cursor_blink_visible,
    });

    try self.updateLinks(critical.mouse_point, critical.mouse_mods);
    try self.updateSearchHighlights();

    if (!self.scrollbar.eql(critical.scrollbar)) {
        self.scrollbar = critical.scrollbar;
        self.scrollbar_dirty = true;
    }

    self.terminal_state.dirty = .false;
}

fn updateLinks(
    self: *Direct2D,
    mouse_point: ?terminal.point.Coordinate,
    mouse_mods: inputpkg.Mods,
) Allocator.Error!void {
    self.links.clearRetainingCapacity();

    if (mouse_point) |vp| {
        if (mouse_mods.equal(inputpkg.ctrlOrSuper(.{}))) {
            var osc8 = try self.terminal_state.linkCells(self.alloc, vp);
            defer osc8.deinit(self.alloc);
            var it = osc8.iterator();
            while (it.next()) |entry| {
                try self.links.put(self.alloc, entry.key_ptr.*, {});
            }
        }
    }

    self.config.links.renderCellMap(
        self.alloc,
        &self.links,
        &self.terminal_state,
        mouse_point,
        mouse_mods,
    ) catch |err| {
        log.warn("error searching for regex links err={}", .{err});
    };
}

fn updateSearchHighlights(self: *Direct2D) Allocator.Error!void {
    if (!self.search_matches_dirty and self.terminal_state.dirty == .false) return;
    self.search_matches_dirty = false;

    const row_data = self.terminal_state.row_data.slice();
    var any_dirty = false;
    for (
        row_data.items(.highlights),
        row_data.items(.dirty),
    ) |*highlights, *dirty| {
        if (highlights.items.len > 0) {
            highlights.clearRetainingCapacity();
            dirty.* = true;
            any_dirty = true;
        }
    }
    if (any_dirty and self.terminal_state.dirty == .false) {
        self.terminal_state.dirty = .partial;
    }

    if (self.search_selected_match) |m| {
        try self.terminal_state.updateHighlightsFlattened(
            self.alloc,
            @intFromEnum(HighlightTag.search_match_selected),
            &.{m.match},
        );
    }

    if (self.search_matches) |m| {
        try self.terminal_state.updateHighlightsFlattened(
            self.alloc,
            @intFromEnum(HighlightTag.search_match),
            m.matches,
        );
    }
}

pub fn drawFrame(self: *Direct2D, sync: bool) !void {
    _ = sync;
    if (!self.visible) return;

    try self.ensureTarget();
    const target = self.target orelse return;
    const render_target = target.renderTarget();

    defer if (self.scrollbar_dirty) {
        if (self.surface_mailbox.push(.{
            .scrollbar = self.scrollbar,
        }, .instant) > 0) self.scrollbar_dirty = false;
    };

    render_target.BeginDraw();
    self.clear(render_target);
    self.drawCells(render_target) catch |err| {
        _ = render_target.EndDraw();
        return err;
    };
    self.drawPreedit(render_target) catch |err| {
        _ = render_target.EndDraw();
        return err;
    };
    self.drawCursor(render_target) catch |err| {
        _ = render_target.EndDraw();
        return err;
    };
    self.drawScrollbar(render_target) catch |err| {
        _ = render_target.EndDraw();
        return err;
    };

    const hr = render_target.EndDraw();
    if (d2d.failed(hr)) {
        self.releaseDeviceResources();
        log.warn("Direct2D EndDraw failed hr=0x{x}", .{@as(u32, @bitCast(hr))});
    }
}

fn initFactories(self: *Direct2D) !void {
    var raw_d2d: *anyopaque = undefined;
    const d2d_hr = d2d.D2D1CreateFactory(
        .SINGLE_THREADED,
        &d2d.IID_ID2D1Factory,
        null,
        &raw_d2d,
    );
    if (d2d.failed(d2d_hr)) return error.Direct2DUnavailable;
    self.d2d_factory = @ptrCast(@alignCast(raw_d2d));

    var raw_dwrite: *d2d.IUnknown = undefined;
    const dwrite_hr = d2d.DWriteCreateFactory(
        .SHARED,
        &d2d.IID_IDWriteFactory,
        &raw_dwrite,
    );
    if (d2d.failed(dwrite_hr)) return error.DirectWriteUnavailable;
    self.dwrite_factory = @ptrCast(@alignCast(raw_dwrite));
}

fn ensureTarget(self: *Direct2D) !void {
    if (self.target != null) return;

    const factory = self.d2d_factory orelse return error.Direct2DUnavailable;
    var rt_props: d2d.D2D1_RENDER_TARGET_PROPERTIES = .{
        .type = .DEFAULT,
        .pixelFormat = .{
            .format = .B8G8R8A8_UNORM,
            .alphaMode = if (self.usesTransparentBackground()) .PREMULTIPLIED else .IGNORE,
        },
        .dpiX = 96,
        .dpiY = 96,
        .usage = .{},
        .minLevel = .DEFAULT,
    };
    var hwnd_props: d2d.D2D1_HWND_RENDER_TARGET_PROPERTIES = .{
        .hwnd = self.rt_surface.hwnd,
        .pixelSize = .{
            .width = @max(1, self.size.screen.width),
            .height = @max(1, self.size.screen.height),
        },
        .presentOptions = .{
            .RETAIN_CONTENTS = 0,
            .IMMEDIATELY = 1,
        },
    };

    var target: *d2d.ID2D1HwndRenderTarget = undefined;
    const hr = factory.CreateHwndRenderTarget(&rt_props, &hwnd_props, &target);
    if (d2d.failed(hr)) return error.Direct2DTargetUnavailable;
    errdefer releaseCom(target);

    const render_target = target.renderTarget();
    render_target.SetTextAntialiasMode(if (self.usesTransparentBackground()) .GRAYSCALE else .CLEARTYPE);

    self.target = target;
}

fn recreateTextFormat(self: *Direct2D) !void {
    self.text_layout_cache.clear(self.alloc);
    self.text_formats.release();

    if (self.dwrite_factory == null) return error.DirectWriteUnavailable;
    const font_choice = try self.fontChoice();
    defer self.alloc.free(font_choice.family_utf16);
    const locale = std.unicode.utf8ToUtf16LeStringLiteral("en-us");

    self.text_formats.regular = try self.createTextFormat(font_choice, locale, .NORMAL, .NORMAL);
    errdefer self.text_formats.release();
    self.text_formats.bold = try self.createTextFormat(font_choice, locale, .BOLD, .NORMAL);
    self.text_formats.italic = try self.createTextFormat(font_choice, locale, .NORMAL, .ITALIC);
    self.text_formats.bold_italic = try self.createTextFormat(font_choice, locale, .BOLD, .ITALIC);

    const emoji_choice: FontChoice = .{
        .family_utf16 = try std.unicode.utf8ToUtf16LeAllocZ(self.alloc, "Segoe UI Emoji"),
    };
    defer self.alloc.free(emoji_choice.family_utf16);
    self.text_formats.emoji = try self.createTextFormat(emoji_choice, locale, .NORMAL, .NORMAL);
}

fn createTextFormat(
    self: *Direct2D,
    font_choice: FontChoice,
    locale: ?[*:0]const u16,
    weight: d2d.DWRITE_FONT_WEIGHT,
    style: d2d.DWRITE_FONT_STYLE,
) !*d2d.IDWriteTextFormat {
    const factory = self.dwrite_factory orelse return error.DirectWriteUnavailable;
    var format: *d2d.IDWriteTextFormat = undefined;
    const hr = factory.CreateTextFormat(
        font_choice.family_utf16.ptr,
        null,
        weight,
        style,
        .NORMAL,
        self.fontSizeDips(),
        locale,
        &format,
    );
    if (d2d.failed(hr)) return error.DirectWriteTextFormatUnavailable;
    errdefer releaseCom(format);

    _ = format.SetTextAlignment(.LEADING);
    _ = format.SetParagraphAlignment(.NEAR);
    _ = format.SetWordWrapping(.NO_WRAP);
    return format;
}

const FontChoice = struct {
    family_utf16: [:0]u16,
};

fn fontChoice(self: *Direct2D) !FontChoice {
    if (self.config.@"font-family".list.items.len > 0) {
        const configured = self.config.@"font-family".list.items[0];
        const family_utf16 = try std.unicode.utf8ToUtf16LeAllocZ(self.alloc, configured);

        return .{
            .family_utf16 = family_utf16,
        };
    }

    return .{
        .family_utf16 = try std.unicode.utf8ToUtf16LeAllocZ(self.alloc, "JetBrains Mono"),
    };
}

fn systemFontExists(self: *Direct2D, family: ?[*:0]const u16) !bool {
    const factory = self.dwrite_factory orelse return error.DirectWriteUnavailable;
    var collection: *d2d.IDWriteFontCollection = undefined;
    const hr = factory.GetSystemFontCollection(&collection, 0);
    if (d2d.failed(hr)) return false;
    defer releaseCom(collection);

    var index: u32 = 0;
    var exists: d2d.BOOL = 0;
    const find_hr = collection.FindFamilyName(family, &index, &exists);
    if (d2d.failed(find_hr)) return false;
    return exists != 0;
}

fn fontSizeDips(self: *const Direct2D) f32 {
    if (self.font_grid.resolver.collection.load_options) |load_options| {
        return @max(1.0, load_options.size.pixels());
    }
    return @max(1.0, self.config.font_size * 96.0 / 72.0);
}

fn clear(self: *Direct2D, target: *d2d.ID2D1RenderTarget) void {
    var color = colorF(self.config.background, self.backgroundClearOpacity());
    target.Clear(&color);
}

fn usesTransparentBackground(self: *const Direct2D) bool {
    return self.config.background_opacity < 1.0 or switch (self.config.background_blur) {
        .false => false,
        else => true,
    };
}

fn backgroundClearOpacity(self: *const Direct2D) f32 {
    if (!self.usesTransparentBackground()) return 1.0;
    const opacity: f32 = @floatCast(self.config.background_opacity);
    return switch (self.config.background_blur) {
        .false => opacity,
        else => @max(0.08, opacity * 0.35),
    };
}

fn drawScrollbar(self: *Direct2D, target: *d2d.ID2D1RenderTarget) !void {
    if (self.config.scrollbar == .never) return;
    if (self.rt_surface.window) |window| {
        if (window.in_window_resize) return;
    }
    if (self.scrollbar.total <= self.scrollbar.len or self.scrollbar.total == 0) return;

    const screen_w: f32 = @floatFromInt(self.size.screen.width);
    const screen_h: f32 = @floatFromInt(self.size.screen.height);
    if (screen_w <= 0 or screen_h <= 0) return;

    const control_w: f32 = 16.0;
    const margin: f32 = 2.0;
    const hovered = self.rt_surface.scrollbarDrawHovered();
    const thumb_w: f32 = if (hovered) 12.0 else 6.0;
    const gutter: f32 = @floatFromInt(self.rt_surface.scrollbarResizeGutter());
    const track_right = @max(0.0, screen_w - gutter);
    if (track_right <= 0.0) return;
    const right = @max(0.0, track_right - 2.0);
    const track_left = @max(0.0, track_right - control_w);

    var track: d2d.D2D_RECT_F = .{
        .left = track_left,
        .top = 0,
        .right = track_right,
        .bottom = screen_h,
    };
    try fillRectangle(target, &track, .{ .r = 0.18, .g = 0.18, .b = 0.18, .a = 0.52 });

    const track_h = @max(1.0, screen_h - margin * 2.0);
    const visible_ratio = @min(1.0, @as(f32, @floatFromInt(self.scrollbar.len)) / @as(f32, @floatFromInt(self.scrollbar.total)));
    const thumb_h = @max(28.0, track_h * visible_ratio);
    const travel = @max(0.0, track_h - thumb_h);
    const max_offset = self.scrollbar.total - self.scrollbar.len;
    const offset_ratio: f32 = if (max_offset == 0) 0.0 else @as(f32, @floatFromInt(self.scrollbar.offset)) / @as(f32, @floatFromInt(max_offset));
    const top = margin + travel * @min(1.0, offset_ratio);
    var thumb: d2d.D2D_RECT_F = .{
        .left = right - thumb_w,
        .top = top,
        .right = right,
        .bottom = @min(screen_h - margin, top + thumb_h),
    };
    const thumb_alpha: f32 = if (hovered) 0.92 else 0.72;
    try fillRectangle(target, &thumb, .{ .r = 0.86, .g = 0.86, .b = 0.86, .a = thumb_alpha });
}

fn selectedKind(
    cell: terminal.page.Cell,
    x: usize,
    selection: ?[2]terminal.size.CellCountInt,
    highlights: *const std.ArrayList(terminal.RenderState.Highlight),
) SelectionKind {
    const x_compare: terminal.size.CellCountInt = @intCast(if (cell.wide == .spacer_tail) x -| 1 else x);
    if (selection) |sel| {
        if (x_compare >= sel[0] and x_compare <= sel[1]) return .selection;
    }

    for (highlights.items) |hl| {
        if (x_compare >= hl.range[0] and x_compare <= hl.range[1]) {
            const tag: HighlightTag = @enumFromInt(hl.tag);
            return switch (tag) {
                .search_match => .search,
                .search_match_selected => .search_selected,
            };
        }
    }

    return .false;
}

fn cellColors(
    self: *const Direct2D,
    cell: *const terminal.page.Cell,
    style: terminal.Style,
    selected: SelectionKind,
) CellColors {
    const state = &self.terminal_state;
    const bg_style = style.bg(cell, &state.colors.palette);
    const fg_style = style.fg(.{
        .default = state.colors.foreground,
        .palette = &state.colors.palette,
        .bold = self.config.bold_color,
    });

    const bg = switch (selected) {
        .selection => if (self.config.selection_background) |v|
            resolveCellColor(v, style, cell, fg_style, bg_style, state.colors.background)
        else
            state.colors.foreground,

        .search => resolveCellColor(
            self.config.search_background,
            style,
            cell,
            fg_style,
            bg_style,
            state.colors.background,
        ),

        .search_selected => resolveCellColor(
            self.config.search_selected_background,
            style,
            cell,
            fg_style,
            bg_style,
            state.colors.background,
        ),

        .false => if (style.flags.inverse != isCovering(cell.codepoint()))
            fg_style
        else
            bg_style,
    };

    const fg = fg: {
        const final_bg = bg_style orelse state.colors.background;
        break :fg switch (selected) {
            .selection => if (self.config.selection_foreground) |v|
                resolveCellColor(v, style, cell, fg_style, bg_style, state.colors.background)
            else
                state.colors.background,

            .search => resolveCellColor(
                self.config.search_foreground,
                style,
                cell,
                fg_style,
                bg_style,
                state.colors.background,
            ),

            .search_selected => resolveCellColor(
                self.config.search_selected_foreground,
                style,
                cell,
                fg_style,
                bg_style,
                state.colors.background,
            ),

            .false => if (style.flags.inverse) final_bg else fg_style,
        };
    };

    const bg_alpha: f32 = switch (selected) {
        .selection,
        .search,
        .search_selected,
        => 1.0,
        .false => bg_alpha: {
            if (style.flags.inverse) break :bg_alpha 1.0;
            if (self.config.background_opacity_cells and bg_style != null) {
                break :bg_alpha @floatCast(self.config.background_opacity);
            }
            if (bg_style != null) break :bg_alpha 1.0;
            break :bg_alpha 0.0;
        },
    };

    return .{
        .bg = if (bg_alpha > 0.0) bg orelse state.colors.background else null,
        .bg_alpha = bg_alpha,
        .fg = fg,
        .fg_alpha = if (style.flags.faint)
            @as(f32, @floatFromInt(self.config.faint_opacity)) / 255.0
        else
            1.0,
    };
}

fn resolveCellColor(
    color: configpkg.Config.TerminalColor,
    style: terminal.Style,
    cell: *const terminal.page.Cell,
    fg_style: terminal.color.RGB,
    bg_style: ?terminal.color.RGB,
    default_bg: terminal.color.RGB,
) terminal.color.RGB {
    _ = cell;
    return switch (color) {
        .color => |v| v.toTerminalRGB(),
        .@"cell-foreground" => if (style.flags.inverse)
            bg_style orelse default_bg
        else
            fg_style,
        .@"cell-background" => if (style.flags.inverse)
            fg_style
        else
            bg_style orelse default_bg,
    };
}

fn resolveCursorColor(
    self: *const Direct2D,
    style: terminal.Style,
    cell: *const terminal.page.Cell,
) terminal.color.RGB {
    if (self.terminal_state.colors.cursor) |v| return v;
    if (self.config.cursor_color) |v| {
        const fg_style = style.fg(.{
            .default = self.terminal_state.colors.foreground,
            .palette = &self.terminal_state.colors.palette,
            .bold = self.config.bold_color,
        });
        const bg_style = style.bg(cell, &self.terminal_state.colors.palette);
        return resolveCellColor(v, style, cell, fg_style, bg_style, self.terminal_state.colors.background);
    }
    return self.terminal_state.colors.foreground;
}

fn resolveCursorTextColor(
    self: *const Direct2D,
    style: terminal.Style,
    cell: *const terminal.page.Cell,
) terminal.color.RGB {
    const fg_style = style.fg(.{
        .default = self.terminal_state.colors.foreground,
        .palette = &self.terminal_state.colors.palette,
        .bold = self.config.bold_color,
    });
    const bg_style = style.bg(cell, &self.terminal_state.colors.palette);
    if (self.config.cursor_text) |v| {
        return resolveCellColor(v, style, cell, fg_style, bg_style, self.terminal_state.colors.background);
    }
    return self.terminal_state.colors.background;
}

fn isCovering(cp: u21) bool {
    return switch (cp) {
        0x2580...0x259F,
        0xE0B0...0xE0D7,
        => true,
        else => false,
    };
}

fn drawCells(self: *Direct2D, target: *d2d.ID2D1RenderTarget) !void {
    const cell_w: f32 = @floatFromInt(self.size.cell.width);
    const cell_h: f32 = @floatFromInt(self.size.cell.height);
    const pad_l: f32 = @floatFromInt(self.size.padding.left);
    const pad_t: f32 = @floatFromInt(self.size.padding.top);
    const state = &self.terminal_state;
    const palette = &state.colors.palette;

    const rows = state.row_data.slice();
    for (0..state.rows) |y| {
        const selection = rows.items(.selection)[y];
        const highlights = rows.items(.highlights)[y];
        const cells = rows.items(.cells)[y].slice();
        const raw_cells = cells.items(.raw);
        const styles = cells.items(.style);
        const graphemes = cells.items(.grapheme);
        var skip_text_until: usize = 0;
        for (raw_cells, 0..) |cell, x| {
            if (cell.wide == .spacer_tail) continue;

            const style: terminal.Style = if (cell.hasStyling()) styles[x] else .{};
            const selected = selectedKind(cell, x, selection, &highlights);
            const colors = cellColors(self, &cell, style, selected);

            const left = pad_l + @as(f32, @floatFromInt(x)) * cell_w;
            const top = pad_t + @as(f32, @floatFromInt(y)) * cell_h;
            const right = left + cell_w * @as(f32, @floatFromInt(cell.gridWidth()));
            const bottom = top + cell_h;
            var rect: d2d.D2D_RECT_F = .{
                .left = left,
                .top = top,
                .right = right,
                .bottom = bottom,
            };

            if (colors.bg) |bg| {
                const bg_color = colorF(bg, colors.bg_alpha);
                try fillRectangle(target, &rect, bg_color);
            }

            if (!cell.hasText()) continue;
            if (style.flags.invisible) continue;
            if (x < skip_text_until) continue;

            const underline = underline: {
                if (self.links.contains(.{
                    .x = @intCast(x),
                    .y = @intCast(y),
                })) {
                    break :underline if (style.flags.underline == .single)
                        terminal.Attribute.Underline.double
                    else
                        terminal.Attribute.Underline.single;
                }
                break :underline style.flags.underline;
            };

            if (underline != .none) try drawUnderline(
                target,
                rect,
                underline,
                colorF(style.underlineColor(palette) orelse colors.fg, colors.fg_alpha),
                cell_h,
            );
            if (style.flags.overline) try drawLineRect(
                target,
                .{ .left = rect.left, .top = rect.top, .right = rect.right, .bottom = rect.top + lineThickness(cell_h) },
                colorF(colors.fg, colors.fg_alpha),
            );

            if (asciiRunLen(self, raw_cells, styles, graphemes, x, selection, &highlights, style)) |run_len| {
                const run_text = try self.asciiRunTextUtf16(raw_cells[x .. x + run_len]);
                const run_rect: d2d.D2D_RECT_F = .{
                    .left = rect.left,
                    .top = rect.top,
                    .right = rect.left + cell_w * @as(f32, @floatFromInt(run_len)),
                    .bottom = rect.bottom,
                };
                const text_format = self.text_formats.get(style) orelse return error.DirectWriteTextFormatUnavailable;
                try drawText(
                    target,
                    run_text.ptr,
                    @intCast(run_text.len),
                    text_format,
                    &run_rect,
                    colorF(colors.fg, colors.fg_alpha),
                    false,
                );
                skip_text_until = x + run_len;
                continue;
            }

            const text = try self.cellTextUtf16(
                &cell,
                if (cell.hasGrapheme()) graphemes[x] else null,
            );
            const special_text = cellTextNeedsExpandedRect(text);
            const format = if (cellTextHasEmoji(text))
                self.text_formats.emoji orelse self.text_formats.get(style)
            else
                self.text_formats.get(style);
            const text_format = format orelse return error.DirectWriteTextFormatUnavailable;
            if (special_text) {
                try self.drawTextLayoutCached(
                    target,
                    text,
                    text_format,
                    &rect,
                    colorF(colors.fg, colors.fg_alpha),
                );
            } else {
                const text_rect = rect;
                try drawText(
                    target,
                    text.ptr,
                    @intCast(text.len),
                    text_format,
                    &text_rect,
                    colorF(colors.fg, colors.fg_alpha),
                    true,
                );
            }

            if (style.flags.strikethrough) try drawLineRect(
                target,
                .{
                    .left = rect.left,
                    .top = rect.top + cell_h * 0.55,
                    .right = rect.right,
                    .bottom = rect.top + cell_h * 0.55 + lineThickness(cell_h),
                },
                colorF(colors.fg, colors.fg_alpha),
            );
        }
    }
}

fn asciiRunLen(
    self: *Direct2D,
    raw_cells: []const terminal.page.Cell,
    styles: []const terminal.Style,
    graphemes: []const []const u21,
    start: usize,
    selection: ?[2]terminal.size.CellCountInt,
    highlights: *const std.ArrayList(terminal.RenderState.Highlight),
    style: terminal.Style,
) ?usize {
    var len: usize = 0;
    while (start + len < raw_cells.len) : (len += 1) {
        const i = start + len;
        const cell = raw_cells[i];
        if (!isAsciiRunCell(cell, graphemes[i])) break;
        if (selectedKind(cell, i, selection, highlights) != .false) break;
        const cell_style: terminal.Style = if (cell.hasStyling()) styles[i] else .{};
        if (!std.meta.eql(cell_style, style)) break;
        if (cellColors(self, &cell, cell_style, .false).bg != null) break;
        if (cell_style.flags.underline != .none or
            cell_style.flags.overline or
            cell_style.flags.strikethrough)
        {
            break;
        }
    }

    if (len > 1) return len;
    return null;
}

fn isAsciiRunCell(cell: terminal.page.Cell, graphemes: []const u21) bool {
    if (graphemes.len != 0) return false;
    if (!cell.hasText()) return false;
    if (cell.wide != .narrow) return false;
    const cp = cell.codepoint();
    return cp >= 0x20 and cp <= 0x7E;
}

fn asciiRunTextUtf16(self: *Direct2D, cells: []const terminal.page.Cell) ![:0]const u16 {
    self.text_buf.clearRetainingCapacity();
    for (cells) |cell| {
        try appendCodepointUtf16(&self.text_buf, self.alloc, cell.codepoint());
    }
    try self.text_buf.append(self.alloc, 0);
    return self.text_buf.items[0 .. self.text_buf.items.len - 1 :0];
}

fn drawCursor(self: *Direct2D, target: *d2d.ID2D1RenderTarget) !void {
    const viewport = self.terminal_state.cursor.viewport orelse return;
    const cursor_style = self.cursor_style orelse return;

    const cell_w: f32 = @floatFromInt(self.size.cell.width);
    const cell_h: f32 = @floatFromInt(self.size.cell.height);
    const cursor_cell = self.terminal_state.cursor.cell;
    const cursor_x = if (viewport.wide_tail) viewport.x -| 1 else viewport.x;
    const cursor_w = if (viewport.wide_tail or cursor_cell.wide == .wide)
        cell_w * 2
    else
        cell_w;
    const left = @as(f32, @floatFromInt(self.size.padding.left)) +
        @as(f32, @floatFromInt(cursor_x)) * cell_w;
    const top = @as(f32, @floatFromInt(self.size.padding.top)) +
        @as(f32, @floatFromInt(viewport.y)) * cell_h;

    var rect: d2d.D2D_RECT_F = switch (cursor_style) {
        .bar => .{ .left = left, .top = top, .right = left + 2, .bottom = top + cell_h },
        .underline => .{ .left = left, .top = top + cell_h - 2, .right = left + cursor_w, .bottom = top + cell_h },
        .block,
        .block_hollow,
        .lock,
        => .{ .left = left, .top = top, .right = left + cursor_w, .bottom = top + cell_h },
    };

    const cursor_cell_style = self.terminal_state.cursor.style;
    const cursor_rgb = resolveCursorColor(self, cursor_cell_style, &cursor_cell);

    const color = colorF(cursor_rgb, @floatCast(self.config.cursor_opacity));
    switch (cursor_style) {
        .block_hollow => try drawRectangle(target, &rect, color, 1.0),
        .block,
        .bar,
        .underline,
        .lock,
        => try fillRectangle(target, &rect, color),
    }

    if (cursor_style == .lock) {
        const text = try self.codepointTextUtf16(0xF023);
        const format = (if (cellTextHasEmoji(text)) self.text_formats.emoji else self.text_formats.regular) orelse
            return error.DirectWriteTextFormatUnavailable;
        const text_rect = expandedTextRect(rect, cell_w, cell_h);
        try drawText(
            target,
            text.ptr,
            @intCast(text.len),
            format,
            &text_rect,
            colorF(resolveCursorTextColor(self, cursor_cell_style, &cursor_cell), 1.0),
            false,
        );
        return;
    }

    if (cursor_style == .block and cursor_cell.hasText()) {
        const text_color = resolveCursorTextColor(self, cursor_cell_style, &cursor_cell);
        const text = try self.cursorTextUtf16();
        const format = (if (cellTextHasEmoji(text)) self.text_formats.emoji else self.text_formats.get(cursor_cell_style)) orelse
            return error.DirectWriteTextFormatUnavailable;
        const special_text = cellTextNeedsExpandedRect(text);
        if (special_text) {
            try self.drawTextLayoutCached(
                target,
                text,
                format,
                &rect,
                colorF(text_color, 1.0),
            );
        } else {
            const text_rect = rect;
            try drawText(target, text.ptr, @intCast(text.len), format, &text_rect, colorF(text_color, 1.0), true);
        }
    }
}

fn drawPreedit(self: *Direct2D, target: *d2d.ID2D1RenderTarget) !void {
    const preedit = self.preedit orelse return;
    const viewport = self.terminal_state.cursor.viewport orelse return;
    const format = self.text_formats.regular orelse return error.DirectWriteTextFormatUnavailable;
    if (preedit.codepoints.len == 0) return;

    const range = preedit.range(viewport.x, self.terminal_state.cols -| 1);
    const cell_w: f32 = @floatFromInt(self.size.cell.width);
    const cell_h: f32 = @floatFromInt(self.size.cell.height);
    var x = range.start;
    for (preedit.codepoints[range.cp_offset..]) |cp| {
        const left = @as(f32, @floatFromInt(self.size.padding.left)) + @as(f32, @floatFromInt(x)) * cell_w;
        const top = @as(f32, @floatFromInt(self.size.padding.top)) + @as(f32, @floatFromInt(viewport.y)) * cell_h;
        const width = cell_w * if (cp.wide) @as(f32, 2) else @as(f32, 1);
        const rect: d2d.D2D_RECT_F = .{
            .left = left,
            .top = top,
            .right = left + width,
            .bottom = top + cell_h,
        };
        const text = try self.codepointTextUtf16(cp.codepoint);
        const special_text = cellTextNeedsExpandedRect(text);
        const text_format = (if (cellTextHasEmoji(text)) self.text_formats.emoji else format) orelse
            return error.DirectWriteTextFormatUnavailable;
        if (special_text) {
            try self.drawTextLayoutCached(
                target,
                text,
                text_format,
                &rect,
                colorF(self.terminal_state.colors.foreground, 1.0),
            );
        } else {
            const text_rect = rect;
            try drawText(
                target,
                text.ptr,
                @intCast(text.len),
                text_format,
                &text_rect,
                colorF(self.terminal_state.colors.foreground, 1.0),
                true,
            );
        }
        try drawUnderline(
            target,
            rect,
            .single,
            colorF(self.terminal_state.colors.foreground, 1.0),
            cell_h,
        );
        x += if (cp.wide) 2 else 1;
    }
}

fn appendCodepointUtf16(buf: *std.ArrayListUnmanaged(u16), alloc: Allocator, cp: u21) !void {
    if (cp == 0) return;
    if (cp <= 0xFFFF) {
        if (std.unicode.utf16IsHighSurrogate(@intCast(cp)) or
            std.unicode.utf16IsLowSurrogate(@intCast(cp)))
        {
            return;
        }
        try buf.append(alloc, @intCast(cp));
        return;
    }

    const value: u32 = @as(u32, cp) - 0x10000;
    try buf.append(alloc, @intCast(0xD800 + (value >> 10)));
    try buf.append(alloc, @intCast(0xDC00 + (value & 0x3FF)));
}

fn cellTextUtf16(
    self: *Direct2D,
    cell: *const terminal.page.Cell,
    graphemes: ?[]const u21,
) ![:0]const u16 {
    self.text_buf.clearRetainingCapacity();
    try appendCodepointUtf16(&self.text_buf, self.alloc, cell.codepoint());
    if (graphemes) |g| {
        for (g) |cp| {
            try appendCodepointUtf16(&self.text_buf, self.alloc, cp);
        }
    }
    try self.text_buf.append(self.alloc, 0);
    return self.text_buf.items[0 .. self.text_buf.items.len - 1 :0];
}

fn cursorTextUtf16(self: *Direct2D) ![:0]const u16 {
    self.text_buf.clearRetainingCapacity();
    const cell = &self.terminal_state.cursor.cell;
    try appendCodepointUtf16(&self.text_buf, self.alloc, cell.codepoint());
    try self.text_buf.append(self.alloc, 0);
    return self.text_buf.items[0 .. self.text_buf.items.len - 1 :0];
}

fn codepointTextUtf16(self: *Direct2D, cp: u21) ![:0]const u16 {
    self.text_buf.clearRetainingCapacity();
    try appendCodepointUtf16(&self.text_buf, self.alloc, cp);
    try self.text_buf.append(self.alloc, 0);
    return self.text_buf.items[0 .. self.text_buf.items.len - 1 :0];
}

fn cellTextHasEmoji(text: []const u16) bool {
    var i: usize = 0;
    while (i < text.len) {
        const unit = text[i];
        const cp: u21 = cp: {
            if (std.unicode.utf16IsHighSurrogate(unit) and i + 1 < text.len) {
                const pair = [_]u16{ unit, text[i + 1] };
                i += 2;
                break :cp std.unicode.utf16DecodeSurrogatePair(&pair) catch continue;
            }
            i += 1;
            break :cp @intCast(unit);
        };

        if (cp == 0x200D or cp == 0xFE0F) return true;
        if (cp >= 0x1F000 and cp <= 0x1FAFF) return true;
        if (cp >= 0x2600 and cp <= 0x27BF) return true;
    }

    return false;
}

fn cellTextNeedsExpandedRect(text: []const u16) bool {
    var i: usize = 0;
    while (i < text.len) {
        const unit = text[i];
        const cp: u21 = cp: {
            if (std.unicode.utf16IsHighSurrogate(unit) and i + 1 < text.len) {
                const pair = [_]u16{ unit, text[i + 1] };
                i += 2;
                break :cp std.unicode.utf16DecodeSurrogatePair(&pair) catch continue;
            }
            i += 1;
            break :cp @intCast(unit);
        };
        if (cp >= 0x80) return true;
    }

    return false;
}

fn expandedTextRect(rect: d2d.D2D_RECT_F, cell_w: f32, cell_h: f32) d2d.D2D_RECT_F {
    return .{
        .left = rect.left - @max(1.0, cell_w * 0.06),
        .top = rect.top - @max(2.0, cell_h * 0.18),
        .right = rect.right + @max(1.0, cell_w * 0.06),
        .bottom = rect.bottom + @max(2.0, cell_h * 0.22),
    };
}

fn colorF(rgb: terminal.color.RGB, opacity: f32) d2d.D2D_COLOR_F {
    return .{
        .r = @as(f32, @floatFromInt(rgb.r)) / 255.0,
        .g = @as(f32, @floatFromInt(rgb.g)) / 255.0,
        .b = @as(f32, @floatFromInt(rgb.b)) / 255.0,
        .a = opacity,
    };
}

fn fillRectangle(
    target: *d2d.ID2D1RenderTarget,
    rect: *const d2d.D2D_RECT_F,
    color: d2d.D2D_COLOR_F,
) !void {
    const brush = try solidColorBrush(target, color);
    defer releaseCom(brush);

    const brush_base: *d2d.ID2D1Brush = @ptrCast(brush);
    target.FillRectangle(rect, brush_base);
}

fn drawRectangle(
    target: *d2d.ID2D1RenderTarget,
    rect: *const d2d.D2D_RECT_F,
    color: d2d.D2D_COLOR_F,
    stroke_width: f32,
) !void {
    const brush = try solidColorBrush(target, color);
    defer releaseCom(brush);

    const brush_base: *d2d.ID2D1Brush = @ptrCast(brush);
    target.DrawRectangle(rect, brush_base, stroke_width);
}

fn drawLineRect(
    target: *d2d.ID2D1RenderTarget,
    rect: d2d.D2D_RECT_F,
    color: d2d.D2D_COLOR_F,
) !void {
    var mutable = rect;
    try fillRectangle(target, &mutable, color);
}

fn drawUnderline(
    target: *d2d.ID2D1RenderTarget,
    rect: d2d.D2D_RECT_F,
    style: terminal.Attribute.Underline,
    color: d2d.D2D_COLOR_F,
    cell_h: f32,
) !void {
    const thickness = lineThickness(cell_h);
    const bottom = rect.bottom - thickness;
    switch (style) {
        .none => {},
        .single => try drawLineRect(target, .{
            .left = rect.left,
            .top = bottom,
            .right = rect.right,
            .bottom = rect.bottom,
        }, color),
        .double => {
            try drawLineRect(target, .{
                .left = rect.left,
                .top = bottom,
                .right = rect.right,
                .bottom = rect.bottom,
            }, color);
            try drawLineRect(target, .{
                .left = rect.left,
                .top = bottom - thickness * 2,
                .right = rect.right,
                .bottom = bottom - thickness,
            }, color);
        },
        .dotted => {
            var x = rect.left;
            const dot = thickness * 1.5;
            const gap = dot;
            while (x < rect.right) : (x += dot + gap) {
                var dot_rect: d2d.D2D_RECT_F = .{
                    .left = x,
                    .top = bottom,
                    .right = @min(x + dot, rect.right),
                    .bottom = rect.bottom,
                };
                try fillRectangle(target, &dot_rect, color);
            }
        },
        .dashed => {
            var x = rect.left;
            const dash = @max(thickness * 4, 3);
            const gap = @max(thickness * 2, 2);
            while (x < rect.right) : (x += dash + gap) {
                var dash_rect: d2d.D2D_RECT_F = .{
                    .left = x,
                    .top = bottom,
                    .right = @min(x + dash, rect.right),
                    .bottom = rect.bottom,
                };
                try fillRectangle(target, &dash_rect, color);
            }
        },
        .curly => {
            var x = rect.left;
            const step = @max(thickness * 2, 2);
            var up = false;
            while (x < rect.right) : ({
                x += step;
                up = !up;
            }) {
                const y = if (up) bottom - thickness else bottom;
                var wave_rect: d2d.D2D_RECT_F = .{
                    .left = x,
                    .top = y,
                    .right = @min(x + step, rect.right),
                    .bottom = y + thickness,
                };
                try fillRectangle(target, &wave_rect, color);
            }
        },
    }
}

fn drawText(
    target: *d2d.ID2D1RenderTarget,
    text: [*:0]const u16,
    text_len: u32,
    format: *d2d.IDWriteTextFormat,
    rect: *const d2d.D2D_RECT_F,
    color: d2d.D2D_COLOR_F,
    expanded: bool,
) !void {
    const brush = try solidColorBrush(target, color);
    defer releaseCom(brush);

    const brush_base: *d2d.ID2D1Brush = @ptrCast(brush);
    target.DrawText(
        text,
        text_len,
        format,
        rect,
        brush_base,
        if (expanded)
            .{ .ENABLE_COLOR_FONT = 1 }
        else
            .{ .CLIP = 1, .ENABLE_COLOR_FONT = 1 },
    );
}

fn drawTextLayoutCached(
    self: *Direct2D,
    target: *d2d.ID2D1RenderTarget,
    text: [:0]const u16,
    format: *d2d.IDWriteTextFormat,
    rect: *const d2d.D2D_RECT_F,
    color: d2d.D2D_COLOR_F,
) !void {
    const entry = try self.getTextLayout(format, text);
    const brush = try solidColorBrush(target, color);
    defer releaseCom(brush);

    const brush_base: *d2d.ID2D1Brush = @ptrCast(brush);
    const origin: d2d.D2D_POINT_2F = .{
        .x = rect.left,
        .y = rect.top,
    };

    target.DrawTextLayout(
        origin,
        entry.layout,
        brush_base,
        .{ .ENABLE_COLOR_FONT = 1 },
    );
}

fn getTextLayout(
    self: *Direct2D,
    format: *d2d.IDWriteTextFormat,
    text: [:0]const u16,
) !*TextLayoutCache.Entry {
    const layout_width: u32 = @intFromFloat(@ceil(@max(1.0, @as(f32, @floatFromInt(self.size.cell.width)) * 2.0)));
    const layout_height: u32 = @intFromFloat(@ceil(@max(1.0, @as(f32, @floatFromInt(self.size.cell.height)))));
    if (self.text_layout_cache.find(format, text, layout_width, layout_height)) |entry| return entry;

    if (self.text_layout_cache.entries.items.len >= TextLayoutCache.max_entries) {
        self.text_layout_cache.clear(self.alloc);
    }

    const factory = self.dwrite_factory orelse return error.DirectWriteUnavailable;
    const text_copy = try self.alloc.dupe(u16, text);
    errdefer self.alloc.free(text_copy);

    var layout: *d2d.IDWriteTextLayout = undefined;
    const hr = factory.CreateTextLayout(
        text.ptr,
        @intCast(text.len),
        format,
        @floatFromInt(layout_width),
        @floatFromInt(layout_height),
        &layout,
    );
    if (d2d.failed(hr)) return error.DirectWriteTextLayoutUnavailable;
    errdefer releaseCom(layout);

    var metrics: d2d.DWRITE_TEXT_METRICS = undefined;
    if (d2d.failed(layout.GetMetrics(&metrics))) return error.DirectWriteTextLayoutUnavailable;

    try self.text_layout_cache.entries.append(self.alloc, .{
        .format = @intFromPtr(format),
        .width = layout_width,
        .height = layout_height,
        .text = text_copy,
        .layout = layout,
        .metrics = metrics,
    });
    return &self.text_layout_cache.entries.items[self.text_layout_cache.entries.items.len - 1];
}

fn lineThickness(cell_h: f32) f32 {
    return @max(1.0, @round(cell_h / 14.0));
}

fn solidColorBrush(
    target: *d2d.ID2D1RenderTarget,
    color: d2d.D2D_COLOR_F,
) !*d2d.ID2D1SolidColorBrush {
    var mutable_color = color;
    var brush: *d2d.ID2D1SolidColorBrush = undefined;
    const hr = target.CreateSolidColorBrush(&mutable_color, &brush);
    if (d2d.failed(hr)) return error.Direct2DBrushUnavailable;
    return brush;
}

fn releaseDeviceResources(self: *Direct2D) void {
    releaseCom(self.target);
    self.target = null;
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
