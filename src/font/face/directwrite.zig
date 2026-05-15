const std = @import("std");
const builtin = @import("builtin");
const assert = @import("../../quirks.zig").inlineAssert;
const Allocator = std.mem.Allocator;
const harfbuzz = @import("harfbuzz");
const font = @import("../main.zig");
const opentype = @import("../opentype.zig");
const quirks = @import("../../quirks.zig");
const dw = @import("../directwrite/api.zig");

const log = std.log.scoped(.font_face);

extern "c" fn ghostty_dwrite_render_color_glyph_d2d(
    glyph_run: *const dw.DWRITE_GLYPH_RUN,
    dpi_x: f32,
    dpi_y: f32,
    baseline_origin_x: f32,
    baseline_origin_y: f32,
    measuring_mode: dw.DWRITE_MEASURING_MODE,
    width: dw.UINT32,
    height: dw.UINT32,
    out_pixels: *anyopaque,
    out_stride: dw.UINT32,
    used_device_context7: *dw.UINT32,
) callconv(.c) dw.HRESULT;

/// Module-level cached DirectWrite factory. Thread-safe via mutex.
var g_factory: ?*dw.IDWriteFactory = null;
var g_factory_mutex: std.Thread.Mutex = .{};

fn getFactory() !*dw.IDWriteFactory {
    g_factory_mutex.lock();
    defer g_factory_mutex.unlock();
    if (g_factory) |f| {
        _ = f.addRef();
        return f;
    }
    var factory_raw: *anyopaque = undefined;
    // Prefer IDWriteFactory4 so Windows 10/11 color glyph APIs are available,
    // while keeping older factory interfaces as fallbacks.
    var hr = dw.DWriteCreateFactory(.shared, &dw.IID_IDWriteFactory4, &factory_raw);
    if (hr != dw.S_OK) {
        hr = dw.DWriteCreateFactory(.shared, &dw.IID_IDWriteFactory2, &factory_raw);
    }
    if (hr != dw.S_OK) {
        hr = dw.DWriteCreateFactory(.shared, &dw.IID_IDWriteFactory1, &factory_raw);
    }
    if (hr != dw.S_OK) return error.FactoryCreationFailed;
    const factory: *dw.IDWriteFactory = @ptrCast(@alignCast(factory_raw));
    g_factory = factory;
    // The caller will release, but we also keep one ref in the cache.
    // So addRef twice: one for cache, one for caller.
    _ = factory.addRef();
    return factory;
}

pub const Face = struct {
    /// DirectWrite font object (null for memory-loaded fonts)
    font: ?*dw.IDWriteFont,

    /// DirectWrite font face object
    font_face: *dw.IDWriteFontFace,

    /// HarfBuzz font for shaping
    hb_font: harfbuzz.Font,

    /// HarfBuzz face
    hb_face: harfbuzz.Face,

    /// Current size
    size: font.face.DesiredSize,

    /// Color glyph state
    color: ?ColorState = null,

    /// Synthetic styles
    synthetic: packed struct {
        bold: bool = false,
        italic: bool = false,
    } = .{},

    /// Quirks
    quirks_disable_default_font_features: bool = false,

    /// Initialize from memory (embedded font). Not yet implemented for DirectWrite.
    /// Initialize from memory (embedded font). Writes to a temporary file
    /// and loads via DirectWrite's file-based API.
    pub fn init(
        lib: font.Library,
        source: [:0]const u8,
        opts: font.face.Options,
    ) !Face {
        _ = lib;

        const factory = try getFactory();
        defer _ = factory.release();

        // Use TEMP environment variable for temp directory
        const tmp_dir = std.process.getEnvVarOwned(std.heap.page_allocator, "TEMP") catch "C:\\Windows\\Temp";
        defer std.heap.page_allocator.free(tmp_dir);

        // Open temp directory for file operations
        var tmp_dir_handle = std.fs.openDirAbsolute(tmp_dir, .{}) catch {
            log.warn("failed to open temp dir: {s}", .{tmp_dir});
            return error.FontInitFailure;
        };
        defer tmp_dir_handle.close();

        // Build temp file name using source pointer as unique ID
        var tmp_name_buf: [64]u8 = undefined;
        const tmp_file_name = std.fmt.bufPrint(
            &tmp_name_buf,
            "ghostty_font_{x}.ttf",
            .{@intFromPtr(source.ptr)},
        ) catch {
            log.warn("failed to format temp file name", .{});
            return error.FontInitFailure;
        };

        {
            // Delete existing file if it exists (may be locked from previous run)
            tmp_dir_handle.deleteFile(tmp_file_name) catch {};
            const file = tmp_dir_handle.createFile(tmp_file_name, .{ .truncate = true }) catch return error.FontInitFailure;
            defer file.close();
            file.writeAll(source) catch return error.FontInitFailure;
        }

        // Build full path for DirectWrite (needs absolute path)
        var tmp_path_buf: [260]u8 = undefined;
        const tmp_file_path = std.fmt.bufPrint(
            &tmp_path_buf,
            "{s}\\{s}",
            .{ tmp_dir, tmp_file_name },
        ) catch {
            log.warn("failed to format temp file path", .{});
            return error.FontInitFailure;
        };

        // Convert path to UTF-16
        var wpath: [260:0]u16 = undefined;
        const wpath_len = std.unicode.utf8ToUtf16Le(&wpath, tmp_file_path) catch {
            log.warn("failed to convert temp path to UTF-16", .{});
            return error.FontInitFailure;
        };
        wpath[wpath_len] = 0;

        // Create font file reference
        var font_file: *dw.IDWriteFontFile = undefined;
        const hr = factory.createFontFileReference(&wpath, null, &font_file);
        if (hr != dw.S_OK) {
            log.warn("createFontFileReference failed hr=0x{X:0>8}", .{@as(u32, @bitCast(hr))});
            return error.FontInitFailure;
        }
        errdefer _ = font_file.release();

        // Analyze the font file
        var is_supported: dw.BOOL = dw.FALSE;
        var file_type: dw.DWRITE_FONT_FACE_TYPE = .unknown;
        var num_faces: dw.UINT32 = 0;
        var face_type: dw.DWRITE_FONT_FACE_TYPE = .unknown;
        const hr2 = font_file.analyze(&is_supported, &file_type, &num_faces, &face_type);
        if (hr2 != dw.S_OK or is_supported == dw.FALSE) return error.FontInitFailure;

        // Create font face (use face_type, not file_type, since file_type may be
        // .truetype_collection even for single-face fonts)
        var font_face: *dw.IDWriteFontFace = undefined;
        const hr3 = factory.createFontFace(
            face_type,
            1,
            @ptrCast(&font_file),
            0,
            .{},
            &font_face,
        );
        if (hr3 != dw.S_OK) return error.FontInitFailure;
        errdefer _ = font_face.release();

        // We need to release font_file here since CreateFontFace doesn't take ownership
        _ = font_file.release();

        // Create HarfBuzz face
        var hb_face = try createHBFace(font_face);
        errdefer hb_face.destroy();

        var hb_font = try harfbuzz.Font.create(hb_face);
        errdefer hb_font.destroy();

        // Set scale
        const pixels: opentype.sfnt.F26Dot6 = .from(opts.size.pixels());
        hb_font.setScale(@bitCast(pixels), @bitCast(pixels));

        // Check for color glyphs
        const color: ?ColorState = try ColorState.init(font_face);
        errdefer if (color) |v| v.deinit();

        var result: Face = .{
            .font = null,
            .font_face = font_face,
            .hb_font = hb_font,
            .hb_face = hb_face,
            .size = opts.size,
            .color = color,
        };
        result.quirks_disable_default_font_features = quirks.disableDefaultFontFeatures(&result);

        return result;
    }

    /// Initialize from an IDWriteFont (discovery path)
    pub fn initFontCopy(base: *dw.IDWriteFont, opts: font.face.Options) !Face {
        // Create font face from the font
        var font_face: *dw.IDWriteFontFace = undefined;
        const hr = base.createFontFace(&font_face);
        if (hr != dw.S_OK) return error.FontInitFailure;
        errdefer _ = font_face.release();

        return try initFont(base, font_face, opts);
    }

    /// Initialize with an existing font and font face. Takes ownership
    /// of both references (caller should have addRef'd if needed).
    pub fn initFont(
        font_dw: *dw.IDWriteFont,
        font_face: *dw.IDWriteFontFace,
        opts: font.face.Options,
    ) !Face {
        // Retain the font because we store it
        _ = font_dw.addRef();
        errdefer _ = font_dw.release();

        // Create HarfBuzz face via font table callbacks
        var hb_face = try createHBFace(font_face);
        errdefer hb_face.destroy();

        var hb_font = try harfbuzz.Font.create(hb_face);
        errdefer hb_font.destroy();

        // Set scale
        const pixels: opentype.sfnt.F26Dot6 = .from(opts.size.pixels());
        hb_font.setScale(@bitCast(pixels), @bitCast(pixels));

        // Check for color glyphs
        const color: ?ColorState = try ColorState.init(font_face);
        errdefer if (color) |v| v.deinit();

        var result: Face = .{
            .font = font_dw,
            .font_face = font_face,
            .hb_font = hb_font,
            .hb_face = hb_face,
            .size = opts.size,
            .color = color,
        };
        result.quirks_disable_default_font_features = quirks.disableDefaultFontFeatures(&result);

        return result;
    }

    fn createHBFace(face: *dw.IDWriteFontFace) !harfbuzz.Face {
        const c = harfbuzz.c;

        const getTableCallback = struct {
            pub fn callback(
                hb_face_: ?*c.hb_face_t,
                tag: c.hb_tag_t,
                user_data: ?*anyopaque,
            ) callconv(.c) ?*c.hb_blob_t {
                _ = hb_face_;
                const dw_face: *dw.IDWriteFontFace = @ptrCast(@alignCast(user_data.?));

                var table_data: ?*anyopaque = null;
                var table_size: dw.UINT32 = 0;
                var table_context: ?*anyopaque = null;
                var exists: dw.BOOL = dw.FALSE;

                // DirectWrite expects tags in little-endian byte order,
                // but HarfBuzz passes them in big-endian. Swap before calling.
                const tag_le = @byteSwap(tag);
                const hr = dw_face.tryGetFontTable(tag_le, &table_data, &table_size, &table_context, &exists);
                const tag_str = [4]u8{ @truncate(tag >> 24), @truncate(tag >> 16), @truncate(tag >> 8), @truncate(tag) };
                log.debug("hb table: {s} tag_be=0x{X} tag_le=0x{X} hr=0x{X} exists={} size={}", .{ &tag_str, tag, tag_le, @as(u32, @bitCast(hr)), exists, table_size });
                if (hr != dw.S_OK or exists == dw.FALSE or table_data == null or table_size == 0) {
                    return null;
                }
                defer _ = dw_face.releaseFontTable(table_context);

                const data_ptr: [*]const u8 = @ptrCast(table_data.?);
                return c.hb_blob_create_or_fail(
                    data_ptr,
                    table_size,
                    c.HB_MEMORY_MODE_DUPLICATE,
                    null,
                    null,
                );
            }
        }.callback;

        const destroyCallback = struct {
            pub fn callback(user_data: ?*anyopaque) callconv(.c) void {
                _ = user_data;
            }
        }.callback;

        const handle = c.hb_face_create_for_tables(getTableCallback, face, destroyCallback);
        return harfbuzz.Face{ .handle = handle.? };
    }

    pub fn deinit(self: *Face) void {
        if (self.font) |f| _ = f.release();
        _ = self.font_face.release();
        self.hb_font.destroy();
        self.hb_face.destroy();
        if (self.color) |v| v.deinit();
        self.* = undefined;
    }

    pub fn syntheticItalic(self: *const Face, opts: font.face.Options) !Face {
        return try self.createWithSimulations(.{ .oblique = true }, opts);
    }

    pub fn syntheticBold(self: *const Face, opts: font.face.Options) !Face {
        return try self.createWithSimulations(.{ .bold = true }, opts);
    }

    fn createWithSimulations(self: *const Face, sims: dw.DWRITE_FONT_SIMULATIONS, opts: font.face.Options) !Face {
        // Get the font file(s) from the current face
        var num_files: dw.UINT32 = 0;
        const hr = self.font_face.getFiles(&num_files, null);
        if (hr != dw.S_OK and hr != dw.E_NOT_SUFFICIENT_BUFFER) return error.FontInitFailure;

        const files = try std.heap.page_allocator.alloc(*dw.IDWriteFontFile, num_files);
        defer std.heap.page_allocator.free(files);

        var num_files2: dw.UINT32 = num_files;
        const hr2 = self.font_face.getFiles(&num_files2, @ptrCast(files.ptr));
        if (hr2 != dw.S_OK) return error.FontInitFailure;

        // Get face index and type
        const face_index = self.font_face.getIndex();
        const face_type = self.font_face.getType();

        const factory = try getFactory();
        defer _ = factory.release();

        // Create new font face with simulations
        var new_face: *dw.IDWriteFontFace = undefined;
        const hr3 = factory.createFontFace(
            @enumFromInt(face_type),
            num_files,
            files.ptr,
            face_index,
            sims,
            &new_face,
        );
        if (hr3 != dw.S_OK) return error.FontInitFailure;
        errdefer _ = new_face.release();

        // Release the file references we got
        for (files) |f| {
            _ = f.release();
        }

        // For discovered fonts, we need to get the IDWriteFont from the new face
        // For memory fonts, font is null
        var new_font: ?*dw.IDWriteFont = null;
        if (self.font) |_| {
            // Try to get the font from system collection
            var collection: *dw.IDWriteFontCollection = undefined;
            const hr4 = factory.getSystemFontCollection(&collection, dw.FALSE);
            if (hr4 == dw.S_OK) {
                defer _ = collection.release();
                var font_ptr: *dw.IDWriteFont = undefined;
                const hr5 = collection.getFontFromFontFace(new_face, &font_ptr);
                if (hr5 == dw.S_OK) new_font = font_ptr;
            }
        }
        errdefer {
            if (new_font) |f| _ = f.release();
        }

        // Create HarfBuzz face
        var hb_face = try createHBFace(new_face);
        errdefer hb_face.destroy();

        var hb_font = try harfbuzz.Font.create(hb_face);
        errdefer hb_font.destroy();

        const pixels: opentype.sfnt.F26Dot6 = .from(opts.size.pixels());
        hb_font.setScale(@bitCast(pixels), @bitCast(pixels));

        const color: ?ColorState = try ColorState.init(new_face);
        errdefer if (color) |v| v.deinit();

        var result: Face = .{
            .font = new_font,
            .font_face = new_face,
            .hb_font = hb_font,
            .hb_face = hb_face,
            .size = opts.size,
            .color = color,
            .synthetic = .{
                .bold = sims.bold,
                .italic = sims.oblique,
            },
        };
        result.quirks_disable_default_font_features = quirks.disableDefaultFontFeatures(&result);

        return result;
    }

    pub fn name(self: *const Face, buf: []u8) Allocator.Error![]const u8 {
        const font_dw = self.font orelse return "embedded";
        var names: *dw.IDWriteLocalizedStrings = undefined;
        const hr = font_dw.getFaceNames(&names);
        if (hr != dw.S_OK) return error.OutOfMemory;
        defer _ = names.release();

        // Try to find "en-us" locale
        var index: dw.UINT32 = 0;
        var exists: dw.BOOL = dw.FALSE;
        _ = names.findLocaleName(L("en-us"), &index, &exists);
        if (exists == dw.FALSE) index = 0;

        var len: dw.UINT32 = 0;
        const hr2 = names.getStringLength(index, &len);
        if (hr2 != dw.S_OK) return error.OutOfMemory;

        // Convert UTF-16 to UTF-8
        var wbuf: [256:0]u16 = undefined;
        if (len + 1 > wbuf.len) return error.OutOfMemory;

        const hr3 = names.getString(index, &wbuf, len + 1);
        if (hr3 != dw.S_OK) return error.OutOfMemory;

        const len_utf8 = std.unicode.utf16LeToUtf8(buf, wbuf[0..len :0]) catch return error.OutOfMemory;
        return buf[0..len_utf8];
    }

    pub fn setSize(self: *Face, opts: font.face.Options) !void {
        self.size = opts.size;
        const pixels: opentype.sfnt.F26Dot6 = .from(opts.size.pixels());
        self.hb_font.setScale(@bitCast(pixels), @bitCast(pixels));
    }

    pub fn setVariations(
        self: *Face,
        vs: []const font.face.Variation,
        opts: font.face.Options,
    ) !void {
        _ = self;
        _ = opts;
        if (vs.len == 0) return;
        // DirectWrite variable font support requires IDWriteFontFace5 (Win10 1809+).
        // The harfbuzz Zig bindings don't currently expose hb_font_set_variations.
        // For now, variable fonts are not supported on the DirectWrite backend.
        log.warn("variable font variations not yet supported on DirectWrite backend", .{});
        return;
    }

    pub fn hasColor(self: *const Face) bool {
        return self.color != null;
    }

    pub fn isColorGlyph(self: *const Face, glyph_id: u32) bool {
        const c = self.color orelse return false;
        return c.isColorGlyph(glyph_id);
    }

    pub fn glyphIndex(self: Face, cp: u32) ?u32 {
        // DirectWrite's GetGlyphIndices accepts UTF-32 code points directly.
        var code_points = [_]dw.UINT32{@intCast(cp)};
        var glyph_index: dw.UINT16 = 0;
        const hr = self.font_face.getGlyphIndices(
            &code_points,
            1,
            @ptrCast(&glyph_index),
        );
        if (hr != dw.S_OK) return null;
        if (glyph_index == 0) return null;

        return glyph_index;
    }

    pub fn renderGlyph(
        self: Face,
        alloc: Allocator,
        atlas: *font.Atlas,
        glyph_index: u32,
        opts: font.face.RenderOptions,
    ) !font.Glyph {
        const factory = try getFactory();
        defer _ = factory.release();

        // Get font metrics for scaling
        var font_metrics: dw.DWRITE_FONT_METRICS = undefined;
        self.font_face.getMetrics(&font_metrics);
        const units_per_em: f64 = @floatFromInt(font_metrics.design_units_per_em);
        const px_per_em: f64 = self.size.pixels();
        const px_per_unit: f64 = px_per_em / units_per_em;

        // Get design metrics for the glyph to compute advance
        var glyph_metrics: dw.DWRITE_GLYPH_METRICS = undefined;
        const glyph_id_u16: dw.UINT16 = @intCast(glyph_index);
        const hr = self.font_face.getDesignGlyphMetrics(
            @ptrCast(&glyph_id_u16),
            1,
            @ptrCast(&glyph_metrics),
            dw.FALSE,
        );
        if (hr != dw.S_OK) return error.GlyphMetricsFailed;

        // Compute the glyph bounding box in design units, then convert to pixels.
        // DirectWrite design units: origin at baseline, +Y up.
        const glyph_left: f64 = @as(f64, @floatFromInt(glyph_metrics.left_side_bearing)) * px_per_unit;
        const glyph_advance: f64 = @as(f64, @floatFromInt(glyph_metrics.advance_width)) * px_per_unit;
        const glyph_right = glyph_left + glyph_advance;

        // Ascent/descent from font metrics
        const ascent_px: f64 = @as(f64, @floatFromInt(font_metrics.ascent)) * px_per_unit;
        const descent_px: f64 = @as(f64, @floatFromInt(font_metrics.descent)) * px_per_unit;

        // Estimate bounding rect. GlyphRunAnalysis will give us the precise bounds.
        const estimated_width = glyph_right - glyph_left;
        const estimated_height = ascent_px + descent_px;

        // Apply constraints if any
        const metrics = opts.grid_metrics;
        const cell_width: f64 = @floatFromInt(metrics.cell_width);
        const cell_baseline: f64 = @floatFromInt(metrics.cell_baseline);

        const constrained = opts.constraint.constrain(
            .{
                .width = estimated_width,
                .height = estimated_height,
                .x = glyph_left,
                .y = ascent_px - cell_baseline,
            },
            metrics,
            opts.constraint_width,
        );

        var x = constrained.x;
        const y = constrained.y;
        const width = constrained.width;
        const height = constrained.height;

        // Center glyphs within the cell if cell width > face width
        if (opts.constraint.size != .stretch) {
            const dx = (cell_width - metrics.face_width) / 2;
            x += dx;
            if (dx < 0) {
                x -= @trunc(dx);
            }
        }

        // Round to whole pixels for the atlas allocation
        const px_width = @as(u32, @intFromFloat(@ceil(width + (x - @floor(x)))));
        const px_height = @as(u32, @intFromFloat(@ceil(height + (y - @floor(y)))));

        if (px_width == 0 or px_height == 0) {
            return font.Glyph{
                .width = 0,
                .height = 0,
                .offset_x = 0,
                .offset_y = 0,
                .atlas_x = 0,
                .atlas_y = 0,
            };
        }

        // Create glyph run for analysis. Use the constrained baseline position.
        // DirectWrite font_em_size expects DIPs (1 DIP = 1/96 inch), not points (1 pt = 1/72 inch).
        const em_size_dips = self.size.points * 96.0 / 72.0;
        // Some DirectWrite APIs require non-null glyph_advances even for single glyphs.
        var glyph_advance_for_run: f32 = 0;
        const glyph_run = dw.DWRITE_GLYPH_RUN{
            .font_face = @ptrCast(self.font_face),
            .font_em_size = em_size_dips,
            .glyph_count = 1,
            .glyph_indices = @ptrCast(&glyph_id_u16),
            .glyph_advances = @ptrCast(&glyph_advance_for_run),
            .glyph_offsets = null,
            .is_sideways = dw.FALSE,
            .bidi_level = 0,
        };

        // Try Direct2D color glyph rendering for BGRA atlas. DirectWrite gives
        // glyph analysis and color font data; Direct2D performs COLR v1 drawing.
        if (atlas.format == .bgra) {
            log.info(
                "directwrite bgra glyph render start glyph={} em_size={d:.3} ppd={d:.3} advance={d:.3} color_state={}",
                .{ glyph_index, em_size_dips, @as(f32, @floatFromInt(self.size.xdpi)) / 96.0, glyph_advance_for_run, self.color != null },
            );
            if (try self.renderColorGlyphD2D(alloc, factory, atlas, &glyph_run, metrics)) |glyph| {
                log.info("directwrite bgra glyph render d2d success glyph={} result={}", .{ glyph_index, glyph });
                return glyph;
            }
            log.warn("directwrite bgra glyph render d2d failed glyph={}, falling back to monochrome outline", .{glyph_index});
        }

        var analysis: *dw.IDWriteGlyphRunAnalysis = undefined;
        const hr2 = factory.createGlyphRunAnalysis(
            &glyph_run,
            @as(f32, @floatFromInt(self.size.xdpi)) / 96.0, // pixels_per_dip
            null,
            .aliased,
            .natural,
            0.0, // baseline_origin_x
            0.0, // baseline_origin_y: origin at baseline
            &analysis,
        );
        if (hr2 != dw.S_OK) return error.GlyphAnalysisFailed;
        defer _ = analysis.release();

        // Get precise alpha texture bounds
        var bounds: dw.RECT = undefined;
        const hr3 = analysis.getAlphaTextureBounds(.aliased, &bounds);
        if (hr3 != dw.S_OK) return error.GlyphBoundsFailed;

        const tex_width = bounds.width();
        const tex_height = bounds.height();

        if (tex_width <= 0 or tex_height <= 0) {
            return font.Glyph{
                .width = 0,
                .height = 0,
                .offset_x = 0,
                .offset_y = 0,
                .atlas_x = 0,
                .atlas_y = 0,
            };
        }

        // Create alpha texture data
        const buf_size = @as(dw.UINT32, @intCast(tex_width * tex_height));
        const alpha_buf = try alloc.alloc(u8, buf_size);
        defer alloc.free(alpha_buf);

        const hr4 = analysis.createAlphaTexture(
            .aliased,
            &bounds,
            alpha_buf.ptr,
            buf_size,
        );
        if (hr4 != dw.S_OK) return error.GlyphTextureFailed;

        // Reserve space in atlas
        const reg = try atlas.reserve(alloc, @intCast(tex_width), @intCast(tex_height));

        // DirectWrite CreateAlphaTexture returns single-channel alpha.
        // If the target atlas expects BGRA (color atlas for emoji), expand.
        switch (atlas.format) {
            .grayscale => atlas.set(reg, alpha_buf),
            .bgra => {
                const bgra_size = @as(usize, @intCast(tex_width)) * @as(usize, @intCast(tex_height)) * 4;
                const bgra_buf = try alloc.alloc(u8, bgra_size);
                defer alloc.free(bgra_buf);
                var i: usize = 0;
                while (i < alpha_buf.len) : (i += 1) {
                    const a = alpha_buf[i];
                    bgra_buf[i * 4 + 0] = a; // B
                    bgra_buf[i * 4 + 1] = a; // G
                    bgra_buf[i * 4 + 2] = a; // R
                    bgra_buf[i * 4 + 3] = a; // A
                }
                atlas.set(reg, bgra_buf);
            },
            .bgr => {
                const bgr_size = @as(usize, @intCast(tex_width)) * @as(usize, @intCast(tex_height)) * 3;
                const bgr_buf = try alloc.alloc(u8, bgr_size);
                defer alloc.free(bgr_buf);
                var i: usize = 0;
                while (i < alpha_buf.len) : (i += 1) {
                    const a = alpha_buf[i];
                    bgr_buf[i * 3 + 0] = a; // B
                    bgr_buf[i * 3 + 1] = a; // G
                    bgr_buf[i * 3 + 2] = a; // R
                }
                atlas.set(reg, bgr_buf);
            },
        }

        // offset_x: distance from left edge of cell to left edge of glyph
        // offset_y: distance from bottom of cell to top of glyph's bounding box
        const offset_x: i32 = @intCast(bounds.left);
        const offset_y: i32 = @as(i32, @intCast(metrics.cell_baseline)) - @as(i32, @intCast(bounds.top));

        return font.Glyph{
            .width = @intCast(tex_width),
            .height = @intCast(tex_height),
            .offset_x = offset_x,
            .offset_y = offset_y,
            .atlas_x = reg.x,
            .atlas_y = reg.y,
        };
    }

    fn renderColorGlyphD2D(
        self: Face,
        alloc: Allocator,
        factory: *dw.IDWriteFactory,
        atlas: *font.Atlas,
        glyph_run: *const dw.DWRITE_GLYPH_RUN,
        metrics: font.Metrics,
    ) !?font.Glyph {
        const pixels_per_dip = @as(f32, @floatFromInt(self.size.ydpi)) / 96.0;
        var analysis: *dw.IDWriteGlyphRunAnalysis = undefined;
        const hr_analysis = factory.createGlyphRunAnalysis(
            glyph_run,
            pixels_per_dip,
            null,
            .aliased,
            .natural,
            0.0,
            0.0,
            &analysis,
        );
        if (hr_analysis != dw.S_OK) {
            log.warn("directwrite color bitmap CreateGlyphRunAnalysis failed hr=0x{X:0>8}", .{@as(u32, @bitCast(hr_analysis))});
            return null;
        }
        defer _ = analysis.release();

        var bounds: dw.RECT = undefined;
        const hr_bounds = analysis.getAlphaTextureBounds(.aliased, &bounds);
        if (hr_bounds != dw.S_OK) {
            log.warn("directwrite color bitmap GetAlphaTextureBounds failed hr=0x{X:0>8}", .{@as(u32, @bitCast(hr_bounds))});
            return null;
        }

        const width_i32 = bounds.width();
        const height_i32 = bounds.height();
        if (width_i32 <= 0 or height_i32 <= 0) {
            log.warn("directwrite color bitmap empty alpha bounds bounds={},{},{},{}", .{ bounds.left, bounds.top, bounds.right, bounds.bottom });
            return null;
        }

        const width: u32 = @intCast(width_i32);
        const height: u32 = @intCast(height_i32);
        const padding: u32 = 4;
        const surface_width = width + padding * 2;
        const surface_height = height + padding * 2;

        const pixel_count = @as(usize, surface_width) * @as(usize, surface_height);
        const bitmap_bytes = try alloc.alloc(u8, pixel_count * 4);
        defer alloc.free(bitmap_bytes);
        @memset(bitmap_bytes, 0);

        var used_device_context7: dw.UINT32 = 0;
        const dpi_x = @as(f32, @floatFromInt(self.size.xdpi));
        const dpi_y = @as(f32, @floatFromInt(self.size.ydpi));
        const origin_x = @as(f32, @floatFromInt(padding)) - @as(f32, @floatFromInt(bounds.left));
        const origin_y = @as(f32, @floatFromInt(padding)) - @as(f32, @floatFromInt(bounds.top));
        const hr_d2d = ghostty_dwrite_render_color_glyph_d2d(
            glyph_run,
            dpi_x,
            dpi_y,
            origin_x,
            origin_y,
            .natural,
            surface_width,
            surface_height,
            bitmap_bytes.ptr,
            surface_width * 4,
            &used_device_context7,
        );

        log.info("directwrite color d2d draw glyph={} hr=0x{X:0>8} target7={} ppd={d:.3} bounds={},{},{},{} origin={d:.3},{d:.3} surface={}x{}", .{
            glyph_run.glyph_indices[0],
            @as(u32, @bitCast(hr_d2d)),
            used_device_context7,
            pixels_per_dip,
            bounds.left,
            bounds.top,
            bounds.right,
            bounds.bottom,
            origin_x,
            origin_y,
            surface_width,
            surface_height,
        });
        if (hr_d2d != dw.S_OK) {
            return null;
        }

        var min_x: u32 = surface_width;
        var min_y: u32 = surface_height;
        var max_x: u32 = 0;
        var max_y: u32 = 0;
        var found = false;
        var colored_pixels: u32 = 0;
        var whiteish_pixels: u32 = 0;

        var yy: u32 = 0;
        while (yy < surface_height) : (yy += 1) {
            var xx: u32 = 0;
            while (xx < surface_width) : (xx += 1) {
                const idx = (@as(usize, yy) * surface_width + xx) * 4;
                if (bitmap_bytes[idx + 3] == 0) continue;
                found = true;
                const b = bitmap_bytes[idx + 0];
                const g = bitmap_bytes[idx + 1];
                const r = bitmap_bytes[idx + 2];
                const max_channel = @max(r, @max(g, b));
                const min_channel = @min(r, @min(g, b));
                if (max_channel > 80 and max_channel - min_channel > 24) colored_pixels += 1;
                if (r > 200 and g > 200 and b > 200) whiteish_pixels += 1;
                min_x = @min(min_x, xx);
                min_y = @min(min_y, yy);
                max_x = @max(max_x, xx + 1);
                max_y = @max(max_y, yy + 1);
            }
        }

        log.info("directwrite color d2d scan found={} colored={} whiteish={} bounds={},{},{},{}", .{
            found,
            colored_pixels,
            whiteish_pixels,
            min_x,
            min_y,
            max_x,
            max_y,
        });

        if (!found or min_x >= max_x or min_y >= max_y) return null;
        const out_width = max_x - min_x;
        const out_height = max_y - min_y;
        const out = try alloc.alloc(u8, @as(usize, out_width) * @as(usize, out_height) * 4);
        defer alloc.free(out);

        yy = 0;
        while (yy < out_height) : (yy += 1) {
            const src_offset = (@as(usize, min_y + yy) * surface_width + min_x) * 4;
            const dst_offset = @as(usize, yy) * out_width * 4;
            @memcpy(out[dst_offset .. dst_offset + @as(usize, out_width) * 4], bitmap_bytes[src_offset .. src_offset + @as(usize, out_width) * 4]);
        }

        const reg = try atlas.reserve(alloc, out_width, out_height);
        atlas.set(reg, out);

        return font.Glyph{
            .width = out_width,
            .height = out_height,
            .offset_x = bounds.left + @as(i32, @intCast(min_x)) - @as(i32, @intCast(padding)),
            .offset_y = @as(i32, @intCast(metrics.cell_baseline)) -
                (bounds.top + @as(i32, @intCast(min_y)) - @as(i32, @intCast(padding))),
            .atlas_x = reg.x,
            .atlas_y = reg.y,
        };
    }

    pub fn getMetrics(self: *Face) font.Metrics.FaceMetrics {
        // Get DirectWrite font metrics (design units)
        var dw_metrics: dw.DWRITE_FONT_METRICS = undefined;
        self.font_face.getMetrics(&dw_metrics);

        const units_per_em: f64 = @floatFromInt(dw_metrics.design_units_per_em);
        const px_per_em: f64 = self.size.pixels();
        const px_per_unit: f64 = px_per_em / units_per_em;

        // Read OpenType tables for richer metrics
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        const hhea_: ?opentype.Hhea = hhea: {
            const data = self.copyTable(alloc, "hhea") catch break :hhea null;
            if (data) |d| {
                break :hhea opentype.Hhea.init(d) catch |err| {
                    log.warn("error parsing hhea table: {}", .{err});
                    break :hhea null;
                };
            }
            break :hhea null;
        };

        const os2_: ?opentype.OS2 = os2: {
            const data = self.copyTable(alloc, "OS/2") catch break :os2 null;
            if (data) |d| {
                break :os2 opentype.OS2.init(d) catch |err| {
                    log.warn("error parsing OS/2 table: {}", .{err});
                    break :os2 null;
                };
            }
            break :os2 null;
        };

        const post_: ?opentype.Post = post: {
            const data = self.copyTable(alloc, "post") catch break :post null;
            if (data) |d| {
                break :post opentype.Post.init(d) catch |err| {
                    log.warn("error parsing post table: {}", .{err});
                    break :post null;
                };
            }
            break :post null;
        };

        // Vertical metrics: prefer hhea > OS/2 sTypo > OS/2 win > DirectWrite
        const ascent: f64, const descent: f64, const line_gap: f64 = vertical: {
            const hhea = hhea_ orelse break :vertical .{
                @as(f64, @floatFromInt(dw_metrics.ascent)) * px_per_unit,
                @as(f64, @floatFromInt(dw_metrics.descent)) * px_per_unit,
                @as(f64, @floatFromInt(dw_metrics.line_gap)) * px_per_unit,
            };

            const hhea_ascent: f64 = @floatFromInt(hhea.ascender);
            const hhea_descent: f64 = @floatFromInt(hhea.descender);
            const hhea_line_gap: f64 = @floatFromInt(hhea.lineGap);

            const os2 = os2_ orelse break :vertical .{
                hhea_ascent * px_per_unit,
                hhea_descent * px_per_unit,
                hhea_line_gap * px_per_unit,
            };

            if (os2.fsSelection.use_typo_metrics) break :vertical .{
                @as(f64, @floatFromInt(os2.sTypoAscender)) * px_per_unit,
                @as(f64, @floatFromInt(os2.sTypoDescender)) * px_per_unit,
                @as(f64, @floatFromInt(os2.sTypoLineGap)) * px_per_unit,
            };

            if (hhea.ascender != 0 or hhea.descender != 0) break :vertical .{
                hhea_ascent * px_per_unit,
                hhea_descent * px_per_unit,
                hhea_line_gap * px_per_unit,
            };

            if (os2.sTypoAscender != 0 or os2.sTypoDescender != 0) break :vertical .{
                @as(f64, @floatFromInt(os2.sTypoAscender)) * px_per_unit,
                @as(f64, @floatFromInt(os2.sTypoDescender)) * px_per_unit,
                @as(f64, @floatFromInt(os2.sTypoLineGap)) * px_per_unit,
            };

            break :vertical .{
                @as(f64, @floatFromInt(os2.usWinAscent)) * px_per_unit,
                -@as(f64, @floatFromInt(os2.usWinDescent)) * px_per_unit,
                0.0,
            };
        };

        // Underline metrics from post table or DirectWrite
        const underline_position, const underline_thickness = ul: {
            const post = post_ orelse break :ul .{
                @as(f64, @floatFromInt(dw_metrics.underline_position)) * px_per_unit,
                @as(f64, @floatFromInt(dw_metrics.underline_thickness)) * px_per_unit,
            };

            if (post.underlineThickness == 0) break :ul .{ null, null };

            break :ul .{
                @as(f64, @floatFromInt(post.underlinePosition)) * px_per_unit,
                @as(f64, @floatFromInt(post.underlineThickness)) * px_per_unit,
            };
        };

        // Strikethrough metrics from OS/2 table or DirectWrite
        const strikethrough_position, const strikethrough_thickness = st: {
            const os2 = os2_ orelse break :st .{
                @as(f64, @floatFromInt(dw_metrics.strikethrough_position)) * px_per_unit,
                @as(f64, @floatFromInt(dw_metrics.strikethrough_thickness)) * px_per_unit,
            };

            if (os2.yStrikeoutSize == 0) break :st .{ null, null };

            break :st .{
                @as(f64, @floatFromInt(os2.yStrikeoutPosition)) * px_per_unit,
                @as(f64, @floatFromInt(os2.yStrikeoutSize)) * px_per_unit,
            };
        };

        // Cap height and ex height
        const cap_height: ?f64, const ex_height: ?f64 = heights: {
            const os2 = os2_ orelse break :heights .{
                if (dw_metrics.cap_height > 0)
                    @as(f64, @floatFromInt(dw_metrics.cap_height)) * px_per_unit
                else
                    null,
                if (dw_metrics.x_height > 0)
                    @as(f64, @floatFromInt(dw_metrics.x_height)) * px_per_unit
                else
                    null,
            };

            break :heights .{
                if (os2.sCapHeight) |v| @as(f64, @floatFromInt(v)) * px_per_unit else null,
                if (os2.sxHeight) |v| @as(f64, @floatFromInt(v)) * px_per_unit else null,
            };
        };

        // Measure ASCII characters for cell width
        const cell_width: f64, const ascii_height: ?f64 = measurements: {
            var max_advance: f64 = 0;
            var code_points: [95]dw.UINT32 = undefined;
            var glyphs: [95]dw.UINT16 = undefined;

            var i: u32 = 32;
            while (i < 127) : (i += 1) {
                code_points[i - 32] = i;
            }

            const hr = self.font_face.getGlyphIndices(
                &code_points,
                95,
                &glyphs,
            );
            if (hr != dw.S_OK) break :measurements .{ 8.0, null };

            var glyph_metrics: [95]dw.DWRITE_GLYPH_METRICS = undefined;
            const hr2 = self.font_face.getDesignGlyphMetrics(
                &glyphs,
                95,
                &glyph_metrics,
                dw.FALSE,
            );
            if (hr2 != dw.S_OK) break :measurements .{ 8.0, null };

            for (glyph_metrics) |gm| {
                const advance: f64 = @as(f64, @floatFromInt(gm.advance_width)) * px_per_unit;
                max_advance = @max(max_advance, advance);
            }

            break :measurements .{ max_advance, null };
        };

        // Measure "水" for ic_width
        const ic_width: ?f64 = ic: {
            const glyph = self.glyphIndex('水') orelse break :ic null;
            var glyphs = [1]dw.UINT16{@intCast(glyph)};
            var gm: [1]dw.DWRITE_GLYPH_METRICS = undefined;
            const hr = self.font_face.getDesignGlyphMetrics(
                &glyphs,
                1,
                &gm,
                dw.FALSE,
            );
            if (hr != dw.S_OK) break :ic null;

            break :ic @as(f64, @floatFromInt(gm[0].advance_width)) * px_per_unit;
        };

        return .{
            .px_per_em = px_per_em,
            .cell_width = cell_width,
            .ascent = ascent,
            .descent = descent,
            .line_gap = line_gap,
            .underline_position = underline_position,
            .underline_thickness = underline_thickness,
            .strikethrough_position = strikethrough_position,
            .strikethrough_thickness = strikethrough_thickness,
            .cap_height = cap_height,
            .ex_height = ex_height,
            .ascii_height = ascii_height,
            .ic_width = ic_width,
        };
    }

    pub fn copyTable(
        self: Face,
        alloc: Allocator,
        tag: *const [4]u8,
    ) Allocator.Error!?[]u8 {
        const tag_u32 = @as(u32, tag[0]) |
            (@as(u32, tag[1]) << 8) |
            (@as(u32, tag[2]) << 16) |
            (@as(u32, tag[3]) << 24);

        var table_data: ?*anyopaque = null;
        var table_size: dw.UINT32 = 0;
        var table_context: ?*anyopaque = null;
        var exists: dw.BOOL = dw.FALSE;

        const hr = self.font_face.tryGetFontTable(tag_u32, &table_data, &table_size, &table_context, &exists);
        log.debug("copyTable: {s} tag=0x{X:0>8} hr=0x{X} exists={} size={}", .{ tag, tag_u32, @as(u32, @bitCast(hr)), exists, table_size });
        if (hr != dw.S_OK or exists == dw.FALSE or table_data == null or table_size == 0) {
            return null;
        }
        defer _ = self.font_face.releaseFontTable(table_context);

        const buf = try alloc.alloc(u8, table_size);
        errdefer alloc.free(buf);

        const ptr: [*]const u8 = @ptrCast(table_data.?);
        @memcpy(buf, ptr[0..table_size]);

        return buf;
    }
};

/// Color state for detecting color glyphs
const ColorState = struct {
    sbix: bool,
    colr: bool,
    svg: ?opentype.SVG,
    svg_data: ?[]const u8,

    pub const Error = error{ InvalidSVGTable, OutOfMemory };

    pub fn init(face: *dw.IDWriteFontFace) Error!?ColorState {
        // Check for sbix table
        const sbix = hasTable(face, "sbix");

        // Check for COLR table (Windows color glyph layers)
        const colr = hasTable(face, "COLR");

        // Check for SVG table
        const svg = svg: {
            const table = try getTableData(face, "SVG ");
            if (table) |data| {
                const svg_ = opentype.SVG.init(data) catch |err| {
                    return switch (err) {
                        error.EndOfStream,
                        error.SVGVersionNotSupported,
                        => error.InvalidSVGTable,
                    };
                };
                break :svg .{ .svg = svg_, .data = data };
            }
            break :svg null;
        };

        return .{
            .sbix = sbix,
            .colr = colr,
            .svg = if (svg) |v| v.svg else null,
            .svg_data = if (svg) |v| v.data else null,
        };
    }

    pub fn deinit(self: *const ColorState) void {
        // svg_data points to font table memory which is managed by DirectWrite
        _ = self;
    }

    pub fn isColorGlyph(self: *const ColorState, glyph_id: u32) bool {
        const glyph_u16 = std.math.cast(u16, glyph_id) orelse return false;
        if (self.sbix) return true;
        if (self.colr) return true;
        if (self.svg) |svg| {
            if (svg.hasGlyph(glyph_u16)) return true;
        }
        return false;
    }
};

fn hasTable(face: *dw.IDWriteFontFace, tag_str: *const [4:0]u8) bool {
    const tag_u32 = @as(u32, tag_str[0]) |
        (@as(u32, tag_str[1]) << 8) |
        (@as(u32, tag_str[2]) << 16) |
        (@as(u32, tag_str[3]) << 24);

    var table_data: ?*anyopaque = null;
    var table_size: dw.UINT32 = 0;
    var table_context: ?*anyopaque = null;
    var exists: dw.BOOL = dw.FALSE;

    const hr = face.tryGetFontTable(tag_u32, &table_data, &table_size, &table_context, &exists);
    if (hr == dw.S_OK and exists == dw.TRUE and table_context != null) {
        _ = face.releaseFontTable(table_context);
    }

    return exists == dw.TRUE;
}

fn getTableData(face: *dw.IDWriteFontFace, tag_str: *const [4:0]u8) !?[]const u8 {
    const tag_u32 = @as(u32, tag_str[0]) |
        (@as(u32, tag_str[1]) << 8) |
        (@as(u32, tag_str[2]) << 16) |
        (@as(u32, tag_str[3]) << 24);

    var table_data: ?*anyopaque = null;
    var table_size: dw.UINT32 = 0;
    var table_context: ?*anyopaque = null;
    var exists: dw.BOOL = dw.FALSE;

    const hr = face.tryGetFontTable(tag_u32, &table_data, &table_size, &table_context, &exists);
    if (hr != dw.S_OK or exists == dw.FALSE or table_data == null or table_size == 0) {
        return null;
    }

    // Note: we can't copy here without an allocator, so we return the raw pointer.
    // The caller must not call releaseFontTable until done with the data.
    const ptr: [*]const u8 = @ptrCast(table_data.?);
    return ptr[0..table_size];
}

// Helper to create UTF-16 string literals at comptime
fn L(comptime s: []const u8) [:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(s);
}
