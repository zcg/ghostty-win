const std = @import("std");
const Allocator = std.mem.Allocator;
const font = @import("../main.zig");
const d2d = @import("../../apprt/win32/d2d.zig");
const opentype = @import("../opentype/sfnt.zig");
const head = @import("../opentype/head.zig");
const hhea = @import("../opentype/hhea.zig");
const os2 = @import("../opentype/os2.zig");
const post = @import("../opentype/post.zig");

pub const Face = struct {
    size: font.face.DesiredSize,
    metrics: font.Metrics.FaceMetrics,
    name_buf: [:0]const u8,

    pub fn init(
        lib: font.Library,
        source: [:0]const u8,
        opts: font.face.Options,
    ) !Face {
        _ = lib;
        return .{
            .size = opts.size,
            .metrics = metricsFromOpenType(source, opts.size) orelse metricsFromSize(opts.size),
            .name_buf = "DirectWrite Embedded",
        };
    }

    pub fn initNamed(
        name_: [:0]const u8,
        size: font.face.DesiredSize,
    ) Face {
        return .{
            .size = size,
            .metrics = metricsFromDirectWrite(name_, size) orelse metricsFromSize(size),
            .name_buf = name_,
        };
    }

    pub fn deinit(self: *Face) void {
        self.* = undefined;
    }

    pub fn name(self: *const Face, buf: []u8) Allocator.Error![]const u8 {
        _ = buf;
        return self.name_buf;
    }

    pub fn setSize(self: *Face, opts: font.face.Options) !void {
        self.size = opts.size;
        self.metrics = metricsFromDirectWrite(self.name_buf, opts.size) orelse metricsFromSize(opts.size);
    }

    pub fn setVariations(
        self: *Face,
        variations: []const font.face.Variation,
        opts: font.face.Options,
    ) !void {
        _ = variations;
        try self.setSize(opts);
    }

    pub fn glyphIndex(self: Face, cp: u32) ?u32 {
        _ = self;
        if (cp == 0) return null;
        if (cp > 0x10FFFF) return null;
        return cp;
    }

    pub fn hasColor(self: *const Face) bool {
        _ = self;
        return true;
    }

    pub fn isColorGlyph(self: *const Face, glyph_id: u32) bool {
        _ = self;
        return glyph_id >= 0x1F000;
    }

    pub fn getMetrics(self: *Face) font.Metrics.FaceMetrics {
        return self.metrics;
    }

    pub fn renderGlyph(
        self: Face,
        alloc: Allocator,
        atlas: *font.Atlas,
        glyph_index: u32,
        opts: font.face.RenderOptions,
    ) !font.Glyph {
        _ = self;
        _ = alloc;
        _ = atlas;
        _ = glyph_index;
        _ = opts;
        return .{
            .width = 0,
            .height = 0,
            .offset_x = 0,
            .offset_y = 0,
            .atlas_x = 0,
            .atlas_y = 0,
        };
    }

    pub fn copyTable(self: Face, alloc: Allocator, tag: *const [4]u8) !?[]u8 {
        _ = self;
        _ = alloc;
        _ = tag;
        return null;
    }

    fn metricsFromSize(size: font.face.DesiredSize) font.Metrics.FaceMetrics {
        const px = @max(size.pixels(), 1.0);
        return .{
            .px_per_em = px,
            .cell_width = @max(px * 0.5, 1.0),
            .ascent = px * 0.95,
            .descent = -(px * 0.25),
            .line_gap = px * 0.12,
            .underline_position = -(px * 0.12),
            .underline_thickness = @max(px / 14.0, 1.0),
            .strikethrough_position = px * 0.28,
            .strikethrough_thickness = @max(px / 14.0, 1.0),
            .cap_height = px * 0.7,
            .ex_height = px * 0.5,
            .ascii_height = px,
            .ic_width = px,
        };
    }

    fn metricsFromOpenType(
        source: []const u8,
        size: font.face.DesiredSize,
    ) ?font.Metrics.FaceMetrics {
        var sfnt_font = opentype.SFNT.init(source, std.heap.page_allocator) catch return null;
        defer sfnt_font.deinit(std.heap.page_allocator);

        const head_table = head.Head.init(sfnt_font.getTable("head") orelse return null) catch return null;
        const hhea_table = hhea.Hhea.init(sfnt_font.getTable("hhea") orelse return null) catch return null;
        const os2_table = if (sfnt_font.getTable("OS/2")) |table|
            os2.OS2.init(table) catch null
        else
            null;
        const post_table = if (sfnt_font.getTable("post")) |table|
            post.Post.init(table) catch null
        else
            null;

        if (head_table.unitsPerEm == 0) return null;
        const px = @max(size.pixels(), 1.0);
        const scale = px / @as(f32, @floatFromInt(head_table.unitsPerEm));

        const ascent_units: f32, const descent_units: f32, const line_gap_units: f32 = if (os2_table) |table| .{
            @floatFromInt(table.sTypoAscender),
            @floatFromInt(table.sTypoDescender),
            @floatFromInt(table.sTypoLineGap),
        } else .{
            @floatFromInt(hhea_table.ascender),
            @floatFromInt(hhea_table.descender),
            @floatFromInt(hhea_table.lineGap),
        };

        const underline_position: f32, const underline_thickness: f32 = if (post_table) |table| .{
            @floatFromInt(table.underlinePosition),
            @floatFromInt(table.underlineThickness),
        } else .{
            descent_units * 0.5,
            @max(@as(f32, @floatFromInt(head_table.unitsPerEm)) / 14.0, 1.0),
        };

        const cell_width = @as(f32, @floatFromInt(hhea_table.advanceWidthMax)) * scale;
        const ascent = ascent_units * scale;
        const descent = descent_units * scale;
        const line_gap = line_gap_units * scale;
        const cap_height = if (os2_table) |table|
            if (table.sCapHeight) |value| @as(f32, @floatFromInt(value)) * scale else px * 0.7
        else
            px * 0.7;
        const ex_height = if (os2_table) |table|
            if (table.sxHeight) |value| @as(f32, @floatFromInt(value)) * scale else px * 0.5
        else
            px * 0.5;

        return .{
            .px_per_em = px,
            .cell_width = @max(cell_width, 1.0),
            .ascent = ascent,
            .descent = descent,
            .line_gap = line_gap,
            .underline_position = underline_position * scale,
            .underline_thickness = @max(underline_thickness * scale, 1.0),
            .strikethrough_position = px * 0.28,
            .strikethrough_thickness = @max(px / 14.0, 1.0),
            .cap_height = cap_height,
            .ex_height = ex_height,
            .ascii_height = ascent - descent + line_gap,
            .ic_width = px,
        };
    }

    fn metricsFromDirectWrite(
        family_name: [:0]const u8,
        size: font.face.DesiredSize,
    ) ?font.Metrics.FaceMetrics {
        var factory_unknown: *d2d.IUnknown = undefined;
        if (d2d.failed(d2d.DWriteCreateFactory(
            .SHARED,
            &d2d.IID_IDWriteFactory,
            &factory_unknown,
        ))) return null;
        const factory: *d2d.IDWriteFactory = @ptrCast(@alignCast(factory_unknown));
        defer releaseCom(factory);

        var collection: *d2d.IDWriteFontCollection = undefined;
        if (d2d.failed(factory.GetSystemFontCollection(&collection, 0))) return null;
        defer releaseCom(collection);

        var family_buf: [256:0]u16 = [_:0]u16{0} ** 256;
        const family_len = std.unicode.utf8ToUtf16Le(family_buf[0 .. family_buf.len - 1], family_name) catch return null;
        family_buf[family_len] = 0;

        var family_index: u32 = 0;
        var exists: d2d.BOOL = 0;
        if (d2d.failed(collection.FindFamilyName(family_buf[0..family_len :0].ptr, &family_index, &exists))) return null;
        if (exists == 0) return null;

        var family: *d2d.IDWriteFontFamily = undefined;
        if (d2d.failed(collection.GetFontFamily(family_index, &family))) return null;
        defer releaseCom(family);

        var dwrite_font: *d2d.IDWriteFont = undefined;
        if (d2d.failed(family.GetFirstMatchingFont(
            .NORMAL,
            .NORMAL,
            .NORMAL,
            &dwrite_font,
        ))) return null;
        defer releaseCom(dwrite_font);

        var metrics: d2d.DWRITE_FONT_METRICS = undefined;
        dwrite_font.GetMetrics(&metrics);
        if (metrics.designUnitsPerEm == 0) return null;

        const measured_cell_width = measuredCellWidth(dwrite_font, size, metrics.designUnitsPerEm);
        return metricsFromDWriteMetrics(size, metrics, measured_cell_width);
    }

    fn measuredCellWidth(
        dwrite_font: *d2d.IDWriteFont,
        size: font.face.DesiredSize,
        design_units_per_em: u16,
    ) ?f64 {
        var face: *d2d.IDWriteFontFace = undefined;
        if (d2d.failed(dwrite_font.CreateFontFace(&face))) return null;
        defer releaseCom(face);

        var codepoints: [95]u32 = undefined;
        for (&codepoints, 0..) |*cp, i| cp.* = 0x20 + @as(u32, @intCast(i));

        var glyphs: [codepoints.len]u16 = undefined;
        if (d2d.failed(face.GetGlyphIndices(&codepoints, codepoints.len, &glyphs))) return null;

        var glyph_metrics: [codepoints.len]d2d.DWRITE_GLYPH_METRICS = undefined;
        if (d2d.failed(face.GetDesignGlyphMetrics(&glyphs, glyphs.len, &glyph_metrics, 0))) return null;

        var max_advance: u32 = 0;
        for (glyph_metrics) |m| {
            max_advance = @max(max_advance, m.advanceWidth);
        }
        if (max_advance == 0) return null;

        const px: f64 = @floatCast(@max(size.pixels(), 1.0));
        const scale = px / @as(f64, @floatFromInt(design_units_per_em));
        return @as(f64, @floatFromInt(max_advance)) * scale;
    }

    fn metricsFromDWriteMetrics(
        size: font.face.DesiredSize,
        metrics: d2d.DWRITE_FONT_METRICS,
        measured_cell_width: ?f64,
    ) font.Metrics.FaceMetrics {
        const px = @max(size.pixels(), 1.0);
        const scale = px / @as(f32, @floatFromInt(metrics.designUnitsPerEm));
        const ascent = @as(f32, @floatFromInt(metrics.ascent)) * scale;
        const descent = -@as(f32, @floatFromInt(metrics.descent)) * scale;
        const line_gap = @as(f32, @floatFromInt(metrics.lineGap)) * scale;
        return .{
            .px_per_em = px,
            .cell_width = measured_cell_width orelse @max(px * 0.5, 1.0),
            .ascent = ascent,
            .descent = descent,
            .line_gap = line_gap,
            .underline_position = @as(f32, @floatFromInt(metrics.underlinePosition)) * scale,
            .underline_thickness = @max(@as(f32, @floatFromInt(metrics.underlineThickness)) * scale, 1.0),
            .strikethrough_position = @as(f32, @floatFromInt(metrics.strikethroughPosition)) * scale,
            .strikethrough_thickness = @max(@as(f32, @floatFromInt(metrics.strikethroughThickness)) * scale, 1.0),
            .cap_height = @as(f32, @floatFromInt(metrics.capHeight)) * scale,
            .ex_height = @as(f32, @floatFromInt(metrics.xHeight)) * scale,
            .ascii_height = ascent - descent + line_gap,
            .ic_width = px,
        };
    }

    fn releaseCom(value: anytype) void {
        const unknown: *d2d.IUnknown = @ptrCast(@alignCast(value));
        _ = unknown.Release();
    }
};
