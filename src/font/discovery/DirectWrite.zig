const std = @import("std");
const Allocator = std.mem.Allocator;
const font = @import("../main.zig");
const DeferredFace = @import("../main.zig").DeferredFace;
const Variation = @import("../main.zig").face.Variation;
const dw = @import("../directwrite/api.zig");

const log = std.log.scoped(.discovery);

pub const DirectWrite = struct {
    factory: *dw.IDWriteFactory,

    pub fn init() !DirectWrite {
        var factory_raw: *anyopaque = undefined;
        // On Windows 8+, DWriteCreateFactory may require IDWriteFactory1.
        const hr = dw.DWriteCreateFactory(
            .shared,
            &dw.IID_IDWriteFactory1,
            &factory_raw,
        );
        if (hr != dw.S_OK) return error.FontDiscoveryFailed;

        const factory: *dw.IDWriteFactory = @ptrCast(@alignCast(factory_raw));

        return .{ .factory = factory };
    }

    pub fn deinit(self: *DirectWrite) void {
        _ = self.factory.release();
        self.* = undefined;
    }

    pub fn discover(
        self: *const DirectWrite,
        alloc: Allocator,
        desc: font.Descriptor,
    ) !DiscoverIterator {
        // Get system font collection
        var collection: *dw.IDWriteFontCollection = undefined;
        const hr = self.factory.getSystemFontCollection(&collection, dw.FALSE);
        if (hr != dw.S_OK) return error.FontDiscoveryFailed;
        errdefer _ = collection.release();

        const family = desc.family orelse "";

        if (family.len > 0) {
            // Specific family lookup
            return try discoverFamily(self, alloc, desc, collection, family);
        }

        // Enumerate all families when no family name is given
        const family_count = collection.getFontFamilyCount();

        // First pass: count total fonts across all families
        var total_fonts: usize = 0;
        var f_idx: u32 = 0;
        while (f_idx < family_count) : (f_idx += 1) {
            var font_family: *dw.IDWriteFontFamily = undefined;
            if (collection.getFontFamily(f_idx, &font_family) != dw.S_OK) continue;
            defer _ = font_family.release();

            var font_list: *dw.IDWriteFontList = undefined;
            const weight: dw.DWRITE_FONT_WEIGHT = if (desc.bold) .bold else .normal;
            const style: dw.DWRITE_FONT_STYLE = if (desc.italic) .italic else .normal;
            const stretch: dw.DWRITE_FONT_STRETCH = .normal;
            if (font_family.getMatchingFonts(weight, stretch, style, &font_list) != dw.S_OK) continue;
            defer _ = font_list.release();

            total_fonts += font_list.getFontCount();
        }

        // Second pass: collect all fonts
        var temp = try alloc.alloc(ScoredFont, total_fonts);
        defer alloc.free(temp);

        var valid_count: usize = 0;
        f_idx = 0;
        while (f_idx < family_count) : (f_idx += 1) {
            var font_family: *dw.IDWriteFontFamily = undefined;
            if (collection.getFontFamily(f_idx, &font_family) != dw.S_OK) continue;
            defer _ = font_family.release();

            var font_list: *dw.IDWriteFontList = undefined;
            const weight: dw.DWRITE_FONT_WEIGHT = if (desc.bold) .bold else .normal;
            const style: dw.DWRITE_FONT_STYLE = if (desc.italic) .italic else .normal;
            const stretch: dw.DWRITE_FONT_STRETCH = .normal;
            if (font_family.getMatchingFonts(weight, stretch, style, &font_list) != dw.S_OK) continue;
            defer _ = font_list.release();

            const count = font_list.getFontCount();
            var i: u32 = 0;
            while (i < count) : (i += 1) {
                var font_dw: *dw.IDWriteFont = undefined;
                const hr5 = font_list.getFont(i, &font_dw);
                if (hr5 != dw.S_OK) continue;

                // If we have a specific codepoint, filter fonts that don't have it
                if (desc.codepoint > 0) {
                    var has_char: dw.BOOL = dw.FALSE;
                    const hr_char = font_dw.hasCharacter(desc.codepoint, &has_char);
                    if (hr_char != dw.S_OK or has_char == dw.FALSE) {
                        _ = font_dw.release();
                        continue;
                    }
                }

                // Compute score for sorting
                const score = scoreFont(font_dw, &desc);

                temp[valid_count] = .{
                    .font = font_dw,
                    .score = score,
                };
                valid_count += 1;
            }
        }

        _ = collection.release();

        // Sort by score (higher score = better match = earlier in list)
        std.mem.sortUnstable(ScoredFont, temp[0..valid_count], &desc, struct {
            fn lessThan(_: *const font.Descriptor, lhs: ScoredFont, rhs: ScoredFont) bool {
                return lhs.score.int() > rhs.score.int();
            }
        }.lessThan);

        // Copy sorted fonts to result array
        const fonts = try alloc.alloc(*dw.IDWriteFont, valid_count);
        errdefer {
            for (fonts) |fnt| {
                _ = fnt.release();
            }
            alloc.free(fonts);
        }

        for (0..valid_count) |j| {
            fonts[j] = temp[j].font;
        }

        return DiscoverIterator{
            .alloc = alloc,
            .fonts = fonts,
            .variations = desc.variations,
            .i = 0,
            .desc = desc,
        };
    }

    fn discoverFamily(
        self: *const DirectWrite,
        alloc: Allocator,
        desc: font.Descriptor,
        collection: *dw.IDWriteFontCollection,
        family: []const u8,
    ) !DiscoverIterator {
        _ = self;

        // Convert family name to UTF-16
        var family_name_w: [256:0]u16 = undefined;
        const family_len = std.unicode.utf8ToUtf16Le(&family_name_w, family) catch {
            _ = collection.release();
            return error.FontDiscoveryFailed;
        };
        family_name_w[family_len] = 0;

        // Find the family
        var family_index: dw.UINT32 = 0;
        var family_exists: dw.BOOL = dw.FALSE;
        const hr2 = collection.findFamilyName(&family_name_w, &family_index, &family_exists);
        if (hr2 != dw.S_OK or family_exists == dw.FALSE) {
            // Family not found, return empty iterator
            _ = collection.release();
            return DiscoverIterator{
                .alloc = alloc,
                .fonts = &.{},
                .variations = desc.variations,
                .i = 0,
                .desc = desc,
            };
        }

        // Get the font family
        var font_family: *dw.IDWriteFontFamily = undefined;
        const hr3 = collection.getFontFamily(family_index, &font_family);
        if (hr3 != dw.S_OK) {
            _ = collection.release();
            return error.FontDiscoveryFailed;
        }
        errdefer _ = font_family.release();

        // Get matching fonts based on weight/style.
        const weight: dw.DWRITE_FONT_WEIGHT = if (desc.bold) .bold else .normal;
        const style: dw.DWRITE_FONT_STYLE = if (desc.italic) .italic else .normal;
        const stretch: dw.DWRITE_FONT_STRETCH = .normal;

        var font_list: *dw.IDWriteFontList = undefined;
        const hr4 = font_family.getMatchingFonts(weight, stretch, style, &font_list);
        _ = font_family.release();
        if (hr4 != dw.S_OK) {
            _ = collection.release();
            return error.FontDiscoveryFailed;
        }
        errdefer _ = font_list.release();

        // Collect all matching fonts into a temporary array with their scores
        const count = font_list.getFontCount();
        var temp = try alloc.alloc(ScoredFont, count);
        defer alloc.free(temp);

        var valid_count: usize = 0;
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            var font_dw: *dw.IDWriteFont = undefined;
            const hr5 = font_list.getFont(i, &font_dw);
            if (hr5 != dw.S_OK) continue;

            // If we have a specific codepoint, filter fonts that don't have it
            if (desc.codepoint > 0) {
                var has_char: dw.BOOL = dw.FALSE;
                const hr_char = font_dw.hasCharacter(desc.codepoint, &has_char);
                if (hr_char != dw.S_OK or has_char == dw.FALSE) {
                    _ = font_dw.release();
                    continue;
                }
            }

            // Compute score for sorting
            const score = scoreFont(font_dw, &desc);

            temp[valid_count] = .{
                .font = font_dw,
                .score = score,
            };
            valid_count += 1;
        }

        _ = font_list.release();
        _ = collection.release();

        // Sort by score (higher score = better match = earlier in list)
        std.mem.sortUnstable(ScoredFont, temp[0..valid_count], &desc, struct {
            fn lessThan(_: *const font.Descriptor, lhs: ScoredFont, rhs: ScoredFont) bool {
                return lhs.score.int() > rhs.score.int();
            }
        }.lessThan);

        // Copy sorted fonts to result array (already addRef'd from getFont)
        const fonts = try alloc.alloc(*dw.IDWriteFont, valid_count);
        errdefer {
            for (fonts) |fnt| {
                _ = fnt.release();
            }
            alloc.free(fonts);
        }

        for (0..valid_count) |j| {
            fonts[j] = temp[j].font;
        }

        return DiscoverIterator{
            .alloc = alloc,
            .fonts = fonts,
            .variations = desc.variations,
            .i = 0,
            .desc = desc,
        };
    }

    pub fn discoverFallback(
        self: *const DirectWrite,
        alloc: Allocator,
        collection_: *font.Collection,
        desc: font.Descriptor,
    ) !DiscoverIterator {
        _ = collection_;
        // For now, delegate to discover with codepoint prioritization.
        // TODO: use IDWriteFontFallback::MapCharacters for better fallback (requires IDWriteFactory2+)
        return try self.discover(alloc, desc);
    }

    /// A font with its sorting score.
    const ScoredFont = struct {
        font: *dw.IDWriteFont,
        score: Score,
    };

    /// Sorting score for font matching. Higher is better.
    /// Fields are ordered from least to most significant (packed struct).
    const Score = packed struct {
        const Backing = @typeInfo(@This()).@"struct".backing_integer.?;

        /// Number of glyphs in the font. More glyphs = slightly better.
        glyph_count: u16 = 0,
        /// Whether the font weight exactly matches the descriptor.
        weight_match: bool = false,
        /// Whether the font style exactly matches the descriptor.
        style_match: bool = false,
        /// Whether the font is monospace.
        monospace: bool = false,
        /// If searching for a codepoint, whether this font has it.
        codepoint: bool = false,

        pub fn int(self: Score) Backing {
            return @bitCast(self);
        }
    };

    fn scoreFont(font_dw: *dw.IDWriteFont, desc: *const font.Descriptor) Score {
        var score: Score = .{};

        // Get font properties
        const font_weight = font_dw.getWeight();
        const font_style = font_dw.getStyle();

        // Check codepoint if requested
        if (desc.codepoint > 0) {
            var has_char: dw.BOOL = dw.FALSE;
            _ = font_dw.hasCharacter(desc.codepoint, &has_char);
            score.codepoint = has_char == dw.TRUE;
        }

        // Check weight match
        const desired_weight: dw.DWRITE_FONT_WEIGHT = if (desc.bold) .bold else .normal;
        score.weight_match = font_weight == desired_weight;

        // Check style match
        const desired_style: dw.DWRITE_FONT_STYLE = if (desc.italic) .italic else .normal;
        score.style_match = font_style == desired_style;

        // Try to get glyph count via font face (best effort)
        if (glyphCount: {
            var font_face: *dw.IDWriteFontFace = undefined;
            const hr = font_dw.createFontFace(&font_face);
            if (hr != dw.S_OK) break :glyphCount null;
            defer _ = font_face.release();

            const count = font_face.getGlyphCount();
            break :glyphCount count;
        }) |count| {
            score.glyph_count = std.math.cast(u16, count) orelse std.math.maxInt(u16);
        }

        return score;
    }

    pub const DiscoverIterator = struct {
        alloc: Allocator,
        fonts: []*dw.IDWriteFont,
        variations: []const Variation,
        i: usize,
        desc: font.Descriptor,

        pub fn deinit(self: *DiscoverIterator) void {
            for (self.fonts) |fnt| {
                _ = fnt.release();
            }
            self.alloc.free(self.fonts);
            self.* = undefined;
        }

        pub fn next(self: *DiscoverIterator) !?DeferredFace {
            if (self.i >= self.fonts.len) return null;

            const font_dw = self.fonts[self.i];
            // Retain because the iterator will release on deinit, but the
            // DeferredFace also needs to own its reference.
            _ = font_dw.addRef();

            defer self.i += 1;

            return DeferredFace{
                .dw = .{
                    .font = font_dw,
                    .variations = self.variations,
                },
            };
        }
    };
};

test "directwrite discovery" {
    if (font.options.backend != .directwrite_harfbuzz) return error.SkipZigTest;

    const testing = std.testing;
    const alloc = testing.allocator;

    var dwrite = DirectWrite.init() catch |err| {
        log.warn("failed to create DirectWrite factory, skipping test err={}", .{err});
        return error.SkipZigTest;
    };
    defer dwrite.deinit();

    // Discover a common monospace font family
    var it = try dwrite.discover(alloc, .{ .family = "Consolas", .size = 12 });
    defer it.deinit();

    var face = (try it.next()) orelse {
        // Consolas may not be available on all systems; skip if not found
        return error.SkipZigTest;
    };
    defer face.deinit();

    // Verify we can get a name
    var buf: [1024]u8 = undefined;
    const name = try face.name(&buf);
    try testing.expect(name.len > 0);
}

test "directwrite discovery codepoint" {
    if (font.options.backend != .directwrite_harfbuzz) return error.SkipZigTest;

    const testing = std.testing;
    const alloc = testing.allocator;

    var dwrite = DirectWrite.init() catch |err| {
        log.warn("failed to create DirectWrite factory, skipping test err={}", .{err});
        return error.SkipZigTest;
    };
    defer dwrite.deinit();

    // Discover a font that supports 'A'
    var it = try dwrite.discover(alloc, .{ .codepoint = 'A', .size = 12 });
    defer it.deinit();

    var face = (try it.next()) orelse return error.SkipZigTest;
    defer face.deinit();

    try testing.expect(face.hasCodepoint('A', null));
}
