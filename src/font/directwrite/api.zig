//! DirectWrite COM interface declarations for Zig.
//!
//! This file provides Zig bindings for the DirectWrite APIs needed
//! by the DirectWrite font backend. COM interfaces are declared using
//! extern structs with vtable pointer fields.

const std = @import("std");

pub const HRESULT = i32;
pub const S_OK: HRESULT = 0;
pub const S_FALSE: HRESULT = 1;
pub const E_FAIL: HRESULT = @bitCast(@as(u32, 0x80004005));
pub const E_INVALIDARG: HRESULT = @bitCast(@as(u32, 0x80070057));
pub const E_OUTOFMEMORY: HRESULT = @bitCast(@as(u32, 0x8007000E));
pub const E_NOTIMPL: HRESULT = @bitCast(@as(u32, 0x80004001));
pub const E_NOT_SUFFICIENT_BUFFER: HRESULT = @bitCast(@as(u32, 0x8007007A));

pub const BOOL = c_int;
pub const TRUE: BOOL = 1;
pub const FALSE: BOOL = 0;

pub const UINT = c_uint;
pub const UINT16 = c_ushort;
pub const UINT32 = c_uint;
pub const INT = c_int;
pub const INT16 = c_short;
pub const INT32 = c_int;
pub const FLOAT = f32;
pub const WCHAR = u16;
pub const LPCWSTR = [*:0]const WCHAR;
pub const LPWSTR = [*:0]WCHAR;
pub const SIZE_T = usize;

pub const GUID = extern struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,

    pub fn init(a: u32, b: u16, c: u16, d8: [8]u8) GUID {
        return .{ .data1 = a, .data2 = b, .data3 = c, .data4 = d8 };
    }
};

// ============================================================================
// IUnknown
// ============================================================================

pub const IUnknown = extern struct {
    vtable: *const IUnknownVTable,

    pub fn queryInterface(self: *IUnknown, riid: *const GUID, out: *?*anyopaque) HRESULT {
        return self.vtable.QueryInterface(self, riid, out);
    }

    pub fn addRef(self: *IUnknown) u32 {
        return self.vtable.AddRef(self);
    }

    pub fn release(self: *IUnknown) u32 {
        return self.vtable.Release(self);
    }
};

pub const IUnknownVTable = extern struct {
    QueryInterface: *const fn (*IUnknown, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*IUnknown) callconv(.winapi) u32,
    Release: *const fn (*IUnknown) callconv(.winapi) u32,
};

// ============================================================================
// Enums
// ============================================================================

pub const DWRITE_FACTORY_TYPE = enum(c_int) {
    shared = 0,
    isolated = 1,
};

pub const DWRITE_FONT_WEIGHT = enum(c_int) {
    thin = 100,
    extra_light = 200,
    light = 300,
    semi_light = 350,
    normal = 400,
    medium = 500,
    semi_bold = 600,
    bold = 700,
    extra_bold = 800,
    black = 900,
    extra_black = 950,
};

pub const DWRITE_FONT_STYLE = enum(c_int) {
    normal = 0,
    oblique = 1,
    italic = 2,
};

pub const DWRITE_FONT_STRETCH = enum(c_int) {
    undefined = 0,
    ultra_condensed = 1,
    extra_condensed = 2,
    condensed = 3,
    semi_condensed = 4,
    normal = 5,
    semi_expanded = 6,
    expanded = 7,
    extra_expanded = 8,
    ultra_expanded = 9,
};

pub const DWRITE_FONT_FACE_TYPE = enum(c_int) {
    cff = 0,
    truetype = 1,
    truetype_collection = 2,
    type1 = 3,
    vector = 4,
    bitmap = 5,
    unknown = 6,
    raw_cff = 7,
    truetype_full = 8,
};

pub const DWRITE_RENDERING_MODE = enum(c_int) {
    default = 0,
    aliased = 1,
    gdi_classic = 2,
    gdi_natural = 3,
    natural = 4,
    natural_symmetric = 5,
    outline = 6,
};

pub const DWRITE_MEASURING_MODE = enum(c_int) {
    natural = 0,
    gdi_classic = 1,
    gdi_natural = 2,
};

pub const DWRITE_TEXTURE_TYPE = enum(c_int) {
    aliased = 0,
    cleartype_3x1 = 1,
};

pub const DWRITE_READING_DIRECTION = enum(c_int) {
    left_to_right = 0,
    right_to_left = 1,
    top_to_bottom = 2,
    bottom_to_top = 3,
};

pub const DWRITE_FLOW_DIRECTION = enum(c_int) {
    top_to_bottom = 0,
};

pub const DWRITE_BREAK_CONDITION = enum(c_int) {
    neutral = 0,
    can_break = 1,
    may_not_break = 2,
    must_break = 3,
};

pub const DWRITE_FONT_SIMULATIONS = packed struct(u32) {
    bold: bool = false,
    oblique: bool = false,
    _pad: u30 = 0,
};

pub const DWRITE_PIXEL_GEOMETRY = enum(c_int) {
    flat = 0,
    rgb = 1,
    bgr = 2,
};

// ============================================================================
// Structures
// ============================================================================

pub const DWRITE_FONT_METRICS = extern struct {
    design_units_per_em: UINT16,
    ascent: UINT16,
    descent: UINT16,
    line_gap: INT16,
    cap_height: UINT16,
    x_height: UINT16,
    underline_position: INT16,
    underline_thickness: UINT16,
    strikethrough_position: INT16,
    strikethrough_thickness: UINT16,
};

pub const DWRITE_GLYPH_METRICS = extern struct {
    left_side_bearing: INT32,
    advance_width: UINT32,
    right_side_bearing: INT32,
    top_side_bearing: INT32,
    advance_height: UINT32,
    bottom_side_bearing: INT32,
    vertical_origin_y: INT32,
};

pub const DWRITE_GLYPH_OFFSET = extern struct {
    advance_offset: f32,
    ascender_offset: f32,
};

pub const DWRITE_GLYPH_RUN = extern struct {
    font_face: *IDWriteFontFace,
    font_em_size: f32,
    glyph_count: UINT32,
    glyph_indices: [*]const UINT16,
    glyph_advances: ?[*]const f32,
    glyph_offsets: ?[*]const DWRITE_GLYPH_OFFSET,
    is_sideways: BOOL,
    bidi_level: UINT32,
};

pub const DWRITE_MATRIX = extern struct {
    m11: f32,
    m12: f32,
    m21: f32,
    m22: f32,
    dx: f32,
    dy: f32,
};

pub const DWRITE_TRIMMING = extern struct {
    granularity: c_int,
    delimiter: UINT32,
    delimiter_count: UINT32,
};

// ============================================================================
// IDWriteFactory
// ============================================================================

pub const IDWriteFontFile = extern struct {
    vtable: *const IDWriteFontFileVTable,

    pub fn queryInterface(self: *IDWriteFontFile, riid: *const GUID, out: *?*anyopaque) HRESULT {
        return self.vtable.QueryInterface(self, riid, out);
    }

    pub fn addRef(self: *IDWriteFontFile) u32 {
        return self.vtable.AddRef(self);
    }

    pub fn release(self: *IDWriteFontFile) u32 {
        return self.vtable.Release(self);
    }

    pub fn getReferenceKey(self: *IDWriteFontFile, key: *?*const anyopaque, size: *UINT32) HRESULT {
        return self.vtable.GetReferenceKey(self, key, size);
    }

    pub fn getLoader(self: *IDWriteFontFile, out: **anyopaque) HRESULT {
        return self.vtable.GetLoader(self, out);
    }

    pub fn analyze(self: *IDWriteFontFile, isSupported: *BOOL, fileType: *DWRITE_FONT_FACE_TYPE, numFaces: *UINT32, faceType: *DWRITE_FONT_FACE_TYPE) HRESULT {
        return self.vtable.Analyze(self, isSupported, fileType, numFaces, faceType);
    }
};

pub const IDWriteFontFileVTable = extern struct {
    // IUnknown
    QueryInterface: *const fn (*IDWriteFontFile, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*IDWriteFontFile) callconv(.winapi) u32,
    Release: *const fn (*IDWriteFontFile) callconv(.winapi) u32,
    // IDWriteFontFile
    GetReferenceKey: *const fn (*IDWriteFontFile, *?*const anyopaque, *UINT32) callconv(.winapi) HRESULT,
    GetLoader: *const fn (*IDWriteFontFile, **anyopaque) callconv(.winapi) HRESULT,
    Analyze: *const fn (*IDWriteFontFile, *BOOL, *DWRITE_FONT_FACE_TYPE, *UINT32, *DWRITE_FONT_FACE_TYPE) callconv(.winapi) HRESULT,
};

pub const IDWriteFactory = extern struct {
    vtable: *const IDWriteFactoryVTable,

    pub fn queryInterface(self: *IDWriteFactory, riid: *const GUID, out: *?*anyopaque) HRESULT {
        return self.vtable.QueryInterface(self, riid, out);
    }

    pub fn addRef(self: *IDWriteFactory) u32 {
        return self.vtable.AddRef(self);
    }

    pub fn release(self: *IDWriteFactory) u32 {
        return self.vtable.Release(self);
    }

    pub fn getSystemFontCollection(self: *IDWriteFactory, out: **IDWriteFontCollection, check_for_updates: BOOL) HRESULT {
        return self.vtable.GetSystemFontCollection(self, out, check_for_updates);
    }

    pub fn createFontFileReference(self: *IDWriteFactory, filePath: LPCWSTR, lastWriteTime: ?*const anyopaque, out: **IDWriteFontFile) HRESULT {
        return self.vtable.CreateFontFileReference(self, filePath, lastWriteTime, out);
    }

    pub fn createFontFace(
        self: *IDWriteFactory,
        fontFaceType: DWRITE_FONT_FACE_TYPE,
        numberOfFiles: UINT32,
        fontFiles: [*]const *IDWriteFontFile,
        faceIndex: UINT32,
        fontFaceSimulationFlags: DWRITE_FONT_SIMULATIONS,
        out: **IDWriteFontFace,
    ) HRESULT {
        return self.vtable.CreateFontFace(self, fontFaceType, numberOfFiles, fontFiles, faceIndex, fontFaceSimulationFlags, out);
    }

    pub fn createCustomRenderingParams(
        self: *IDWriteFactory,
        gamma: f32,
        enhanced_contrast: f32,
        clear_type_level: f32,
        pixel_geometry: DWRITE_PIXEL_GEOMETRY,
        rendering_mode: DWRITE_RENDERING_MODE,
        out: **IDWriteRenderingParams,
    ) HRESULT {
        return self.vtable.CreateCustomRenderingParams(self, gamma, enhanced_contrast, clear_type_level, pixel_geometry, rendering_mode, out);
    }

    pub fn createGlyphRunAnalysis(
        self: *IDWriteFactory,
        glyph_run: *const DWRITE_GLYPH_RUN,
        pixels_per_dip: f32,
        transform: ?*const DWRITE_MATRIX,
        rendering_mode: DWRITE_RENDERING_MODE,
        measuring_mode: DWRITE_MEASURING_MODE,
        baseline_origin_x: f32,
        baseline_origin_y: f32,
        out: **IDWriteGlyphRunAnalysis,
    ) HRESULT {
        return self.vtable.CreateGlyphRunAnalysis(self, glyph_run, pixels_per_dip, transform, rendering_mode, measuring_mode, baseline_origin_x, baseline_origin_y, out);
    }
};

pub const IDWriteFactoryVTable = extern struct {
    // IUnknown (0-2)
    QueryInterface: *const fn (*IDWriteFactory, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*IDWriteFactory) callconv(.winapi) u32,
    Release: *const fn (*IDWriteFactory) callconv(.winapi) u32,
    // IDWriteFactory
    GetSystemFontCollection: *const fn (*IDWriteFactory, **IDWriteFontCollection, BOOL) callconv(.winapi) HRESULT,
    CreateCustomFontCollection: *const fn (*IDWriteFactory) callconv(.winapi) HRESULT,
    RegisterFontCollectionLoader: *const fn (*IDWriteFactory) callconv(.winapi) HRESULT,
    UnregisterFontCollectionLoader: *const fn (*IDWriteFactory) callconv(.winapi) HRESULT,
    CreateFontFileReference: *const fn (*IDWriteFactory, LPCWSTR, ?*const anyopaque, **IDWriteFontFile) callconv(.winapi) HRESULT,
    CreateCustomFontFileReference: *const fn (*IDWriteFactory) callconv(.winapi) HRESULT,
    CreateFontFace: *const fn (*IDWriteFactory, DWRITE_FONT_FACE_TYPE, UINT32, [*]const *IDWriteFontFile, UINT32, DWRITE_FONT_SIMULATIONS, **IDWriteFontFace) callconv(.winapi) HRESULT,
    CreateRenderingParams: *const fn (*IDWriteFactory, **IDWriteRenderingParams) callconv(.winapi) HRESULT,
    CreateMonitorRenderingParams: *const fn (*IDWriteFactory) callconv(.winapi) HRESULT,
    CreateCustomRenderingParams: *const fn (*IDWriteFactory, f32, f32, f32, DWRITE_PIXEL_GEOMETRY, DWRITE_RENDERING_MODE, **IDWriteRenderingParams) callconv(.winapi) HRESULT,
    RegisterFontFileLoader: *const fn (*IDWriteFactory) callconv(.winapi) HRESULT,
    UnregisterFontFileLoader: *const fn (*IDWriteFactory) callconv(.winapi) HRESULT,
    CreateTextFormat: *const fn (*IDWriteFactory) callconv(.winapi) HRESULT,
    CreateTypography: *const fn (*IDWriteFactory) callconv(.winapi) HRESULT,
    GetGdiInterop: *const fn (*IDWriteFactory) callconv(.winapi) HRESULT,
    CreateTextLayout: *const fn (*IDWriteFactory) callconv(.winapi) HRESULT,
    CreateGdiCompatibleTextLayout: *const fn (*IDWriteFactory) callconv(.winapi) HRESULT,
    CreateEllipsisTrimmingSign: *const fn (*IDWriteFactory) callconv(.winapi) HRESULT,
    CreateTextAnalyzer: *const fn (*IDWriteFactory, **IDWriteTextAnalyzer) callconv(.winapi) HRESULT,
    CreateNumberSubstitution: *const fn (*IDWriteFactory) callconv(.winapi) HRESULT,
    CreateGlyphRunAnalysis: *const fn (*IDWriteFactory, *const DWRITE_GLYPH_RUN, f32, ?*const DWRITE_MATRIX, DWRITE_RENDERING_MODE, DWRITE_MEASURING_MODE, f32, f32, **IDWriteGlyphRunAnalysis) callconv(.winapi) HRESULT,
};

// ============================================================================
// IDWriteFontCollection
// ============================================================================

pub const IDWriteFontCollection = extern struct {
    vtable: *const IDWriteFontCollectionVTable,

    pub fn queryInterface(self: *IDWriteFontCollection, riid: *const GUID, out: *?*anyopaque) HRESULT {
        return self.vtable.QueryInterface(self, riid, out);
    }

    pub fn addRef(self: *IDWriteFontCollection) u32 {
        return self.vtable.AddRef(self);
    }

    pub fn release(self: *IDWriteFontCollection) u32 {
        return self.vtable.Release(self);
    }

    pub fn getFontFamilyCount(self: *IDWriteFontCollection) UINT32 {
        return self.vtable.GetFontFamilyCount(self);
    }

    pub fn getFontFamily(self: *IDWriteFontCollection, index: UINT32, out: **IDWriteFontFamily) HRESULT {
        return self.vtable.GetFontFamily(self, index, out);
    }

    pub fn findFamilyName(self: *IDWriteFontCollection, family_name: LPCWSTR, index: *UINT32, exists: *BOOL) HRESULT {
        return self.vtable.FindFamilyName(self, family_name, index, exists);
    }

    pub fn getFontFromFontFace(self: *IDWriteFontCollection, font_face: *IDWriteFontFace, out: **IDWriteFont) HRESULT {
        return self.vtable.GetFontFromFontFace(self, font_face, out);
    }
};

pub const IDWriteFontCollectionVTable = extern struct {
    // IUnknown
    QueryInterface: *const fn (*IDWriteFontCollection, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*IDWriteFontCollection) callconv(.winapi) u32,
    Release: *const fn (*IDWriteFontCollection) callconv(.winapi) u32,
    // IDWriteFontCollection
    GetFontFamilyCount: *const fn (*IDWriteFontCollection) callconv(.winapi) UINT32,
    GetFontFamily: *const fn (*IDWriteFontCollection, UINT32, **IDWriteFontFamily) callconv(.winapi) HRESULT,
    FindFamilyName: *const fn (*IDWriteFontCollection, LPCWSTR, *UINT32, *BOOL) callconv(.winapi) HRESULT,
    GetFontFromFontFace: *const fn (*IDWriteFontCollection, *IDWriteFontFace, **IDWriteFont) callconv(.winapi) HRESULT,
};

// ============================================================================
// IDWriteFontFamily
// ============================================================================

pub const IDWriteFontFamily = extern struct {
    vtable: *const IDWriteFontFamilyVTable,

    pub fn queryInterface(self: *IDWriteFontFamily, riid: *const GUID, out: *?*anyopaque) HRESULT {
        return self.vtable.QueryInterface(self, riid, out);
    }

    pub fn addRef(self: *IDWriteFontFamily) u32 {
        return self.vtable.AddRef(self);
    }

    pub fn release(self: *IDWriteFontFamily) u32 {
        return self.vtable.Release(self);
    }

    pub fn getFontCollection(self: *IDWriteFontFamily, out: **IDWriteFontCollection) HRESULT {
        return self.vtable.GetFontCollection(self, out);
    }

    pub fn getFontCount(self: *IDWriteFontFamily) UINT32 {
        return self.vtable.GetFontCount(self);
    }

    pub fn getFont(self: *IDWriteFontFamily, index: UINT32, out: **IDWriteFont) HRESULT {
        return self.vtable.GetFont(self, index, out);
    }

    pub fn getFamilyNames(self: *IDWriteFontFamily, out: **IDWriteLocalizedStrings) HRESULT {
        return self.vtable.GetFamilyNames(self, out);
    }

    pub fn getFirstMatchingFont(
        self: *IDWriteFontFamily,
        weight: DWRITE_FONT_WEIGHT,
        stretch: DWRITE_FONT_STRETCH,
        style: DWRITE_FONT_STYLE,
        out: **IDWriteFont,
    ) HRESULT {
        return self.vtable.GetFirstMatchingFont(self, weight, stretch, style, out);
    }

    pub fn getMatchingFonts(
        self: *IDWriteFontFamily,
        weight: DWRITE_FONT_WEIGHT,
        stretch: DWRITE_FONT_STRETCH,
        style: DWRITE_FONT_STYLE,
        out: **IDWriteFontList,
    ) HRESULT {
        return self.vtable.GetMatchingFonts(self, weight, stretch, style, out);
    }
};

pub const IDWriteFontFamilyVTable = extern struct {
    // IUnknown
    QueryInterface: *const fn (*IDWriteFontFamily, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*IDWriteFontFamily) callconv(.winapi) u32,
    Release: *const fn (*IDWriteFontFamily) callconv(.winapi) u32,
    // IDWriteFontList (base)
    GetFontCollection: *const fn (*IDWriteFontFamily, **IDWriteFontCollection) callconv(.winapi) HRESULT,
    GetFontCount: *const fn (*IDWriteFontFamily) callconv(.winapi) UINT32,
    GetFont: *const fn (*IDWriteFontFamily, UINT32, **IDWriteFont) callconv(.winapi) HRESULT,
    // IDWriteFontFamily
    GetFamilyNames: *const fn (*IDWriteFontFamily, **IDWriteLocalizedStrings) callconv(.winapi) HRESULT,
    GetFirstMatchingFont: *const fn (*IDWriteFontFamily, DWRITE_FONT_WEIGHT, DWRITE_FONT_STRETCH, DWRITE_FONT_STYLE, **IDWriteFont) callconv(.winapi) HRESULT,
    GetMatchingFonts: *const fn (*IDWriteFontFamily, DWRITE_FONT_WEIGHT, DWRITE_FONT_STRETCH, DWRITE_FONT_STYLE, **IDWriteFontList) callconv(.winapi) HRESULT,
};

// ============================================================================
// IDWriteFontList
// ============================================================================

pub const IDWriteFontList = extern struct {
    vtable: *const IDWriteFontListVTable,

    pub fn queryInterface(self: *IDWriteFontList, riid: *const GUID, out: *?*anyopaque) HRESULT {
        return self.vtable.QueryInterface(self, riid, out);
    }

    pub fn addRef(self: *IDWriteFontList) u32 {
        return self.vtable.AddRef(self);
    }

    pub fn release(self: *IDWriteFontList) u32 {
        return self.vtable.Release(self);
    }

    pub fn getFontCollection(self: *IDWriteFontList, out: **IDWriteFontCollection) HRESULT {
        return self.vtable.GetFontCollection(self, out);
    }

    pub fn getFontCount(self: *IDWriteFontList) UINT32 {
        return self.vtable.GetFontCount(self);
    }

    pub fn getFont(self: *IDWriteFontList, index: UINT32, out: **IDWriteFont) HRESULT {
        return self.vtable.GetFont(self, index, out);
    }
};

pub const IDWriteFontListVTable = extern struct {
    // IUnknown
    QueryInterface: *const fn (*IDWriteFontList, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*IDWriteFontList) callconv(.winapi) u32,
    Release: *const fn (*IDWriteFontList) callconv(.winapi) u32,
    // IDWriteFontList
    GetFontCollection: *const fn (*IDWriteFontList, **IDWriteFontCollection) callconv(.winapi) HRESULT,
    GetFontCount: *const fn (*IDWriteFontList) callconv(.winapi) UINT32,
    GetFont: *const fn (*IDWriteFontList, UINT32, **IDWriteFont) callconv(.winapi) HRESULT,
};

// ============================================================================
// IDWriteFont
// ============================================================================

pub const IDWriteFont = extern struct {
    vtable: *const IDWriteFontVTable,

    pub fn queryInterface(self: *IDWriteFont, riid: *const GUID, out: *?*anyopaque) HRESULT {
        return self.vtable.QueryInterface(self, riid, out);
    }

    pub fn addRef(self: *IDWriteFont) u32 {
        return self.vtable.AddRef(self);
    }

    pub fn release(self: *IDWriteFont) u32 {
        return self.vtable.Release(self);
    }

    pub fn getFontFamily(self: *IDWriteFont, out: **IDWriteFontFamily) HRESULT {
        return self.vtable.GetFontFamily(self, out);
    }

    pub fn getWeight(self: *IDWriteFont) DWRITE_FONT_WEIGHT {
        return self.vtable.GetWeight(self);
    }

    pub fn getStretch(self: *IDWriteFont) DWRITE_FONT_STRETCH {
        return self.vtable.GetStretch(self);
    }

    pub fn getStyle(self: *IDWriteFont) DWRITE_FONT_STYLE {
        return self.vtable.GetStyle(self);
    }

    pub fn isSymbolFont(self: *IDWriteFont) BOOL {
        return self.vtable.IsSymbolFont(self);
    }

    pub fn getFaceNames(self: *IDWriteFont, out: **IDWriteLocalizedStrings) HRESULT {
        return self.vtable.GetFaceNames(self, out);
    }

    pub fn createFontFace(self: *IDWriteFont, out: **IDWriteFontFace) HRESULT {
        return self.vtable.CreateFontFace(self, out);
    }

    pub fn hasCharacter(self: *IDWriteFont, unicode_value: UINT32, exists: *BOOL) HRESULT {
        return self.vtable.HasCharacter(self, unicode_value, exists);
    }
};

const FontFn = *const fn (*IDWriteFont) callconv(.winapi) HRESULT;

pub const IDWriteFontVTable = extern struct {
    // IUnknown
    QueryInterface: *const fn (*IDWriteFont, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*IDWriteFont) callconv(.winapi) u32,
    Release: *const fn (*IDWriteFont) callconv(.winapi) u32,
    // IDWriteFont
    GetFontFamily: *const fn (*IDWriteFont, **IDWriteFontFamily) callconv(.winapi) HRESULT,
    GetWeight: *const fn (*IDWriteFont) callconv(.winapi) DWRITE_FONT_WEIGHT,
    GetStretch: *const fn (*IDWriteFont) callconv(.winapi) DWRITE_FONT_STRETCH,
    GetStyle: *const fn (*IDWriteFont) callconv(.winapi) DWRITE_FONT_STYLE,
    IsSymbolFont: *const fn (*IDWriteFont) callconv(.winapi) BOOL,
    GetFaceNames: *const fn (*IDWriteFont, **IDWriteLocalizedStrings) callconv(.winapi) HRESULT,
    GetInformationalStrings: FontFn,
    GetSimulations: *const fn (*IDWriteFont) callconv(.winapi) DWRITE_FONT_SIMULATIONS,
    GetMetrics: *const fn (*IDWriteFont, *DWRITE_FONT_METRICS) callconv(.winapi) void,
    HasCharacter: *const fn (*IDWriteFont, UINT32, *BOOL) callconv(.winapi) HRESULT,
    CreateFontFace: *const fn (*IDWriteFont, **IDWriteFontFace) callconv(.winapi) HRESULT,
};

// ============================================================================
// IDWriteFontFace
// ============================================================================

pub const IDWriteFontFace = extern struct {
    vtable: *const IDWriteFontFaceVTable,

    pub fn queryInterface(self: *IDWriteFontFace, riid: *const GUID, out: *?*anyopaque) HRESULT {
        return self.vtable.QueryInterface(self, riid, out);
    }

    pub fn addRef(self: *IDWriteFontFace) u32 {
        return self.vtable.AddRef(self);
    }

    pub fn release(self: *IDWriteFontFace) u32 {
        return self.vtable.Release(self);
    }

    pub fn getType(self: *IDWriteFontFace) c_int {
        return self.vtable.GetType(self);
    }

    pub fn getFiles(self: *IDWriteFontFace, number_of_files: *UINT32, font_files: ?[*]*anyopaque) HRESULT {
        return self.vtable.GetFiles(self, number_of_files, font_files);
    }

    pub fn getIndex(self: *IDWriteFontFace) UINT32 {
        return self.vtable.GetIndex(self);
    }

    pub fn getSimulations(self: *IDWriteFontFace) DWRITE_FONT_SIMULATIONS {
        return self.vtable.GetSimulations(self);
    }

    pub fn isSymbolFont(self: *IDWriteFontFace) BOOL {
        return self.vtable.IsSymbolFont(self);
    }

    pub fn getMetrics(self: *IDWriteFontFace, metrics: *DWRITE_FONT_METRICS) void {
        return self.vtable.GetMetrics(self, metrics);
    }

    pub fn getGlyphCount(self: *IDWriteFontFace) UINT16 {
        return self.vtable.GetGlyphCount(self);
    }

    pub fn getDesignGlyphMetrics(self: *IDWriteFontFace, glyph_indices: [*]const UINT16, glyph_count: UINT32, metrics: [*]DWRITE_GLYPH_METRICS, is_sideways: BOOL) HRESULT {
        return self.vtable.GetDesignGlyphMetrics(self, glyph_indices, glyph_count, metrics, is_sideways);
    }

    pub fn getGlyphIndices(self: *IDWriteFontFace, code_points: [*]const UINT32, code_point_count: UINT32, glyph_indices: [*]UINT16) HRESULT {
        return self.vtable.GetGlyphIndices(self, code_points, code_point_count, glyph_indices);
    }

    pub fn tryGetFontTable(self: *IDWriteFontFace, open_type_table_tag: UINT32, table_data: *?*anyopaque, table_size: *UINT32, table_context: *?*anyopaque, exists: *BOOL) HRESULT {
        return self.vtable.TryGetFontTable(self, open_type_table_tag, table_data, table_size, table_context, exists);
    }

    pub fn releaseFontTable(self: *IDWriteFontFace, table_context: ?*anyopaque) void {
        return self.vtable.ReleaseFontTable(self, table_context);
    }

    pub fn getGlyphRunOutline(self: *IDWriteFontFace, em_size: f32, glyph_indices: [*]const UINT16, glyph_advances: ?[*]const f32, glyph_offsets: ?[*]const DWRITE_GLYPH_OFFSET, glyph_count: UINT32, is_sideways: BOOL, is_right_to_left: BOOL, geometry_sink: *anyopaque) HRESULT {
        return self.vtable.GetGlyphRunOutline(self, em_size, glyph_indices, glyph_advances, glyph_offsets, glyph_count, is_sideways, is_right_to_left, geometry_sink);
    }

    pub fn getRecommendedRenderingMode(self: *IDWriteFontFace, em_size: f32, pixels_per_dip: f32, measuring_mode: DWRITE_MEASURING_MODE, rendering_params: *IDWriteRenderingParams, rendering_mode: *DWRITE_RENDERING_MODE) HRESULT {
        return self.vtable.GetRecommendedRenderingMode(self, em_size, pixels_per_dip, measuring_mode, rendering_params, rendering_mode);
    }

    pub fn getGdiCompatibleMetrics(self: *IDWriteFontFace, em_size: f32, pixels_per_dip: f32, transform: ?*const DWRITE_MATRIX, metrics: *DWRITE_FONT_METRICS) HRESULT {
        return self.vtable.GetGdiCompatibleMetrics(self, em_size, pixels_per_dip, transform, metrics);
    }

    pub fn getGdiCompatibleGlyphMetrics(self: *IDWriteFontFace, em_size: f32, pixels_per_dip: f32, transform: ?*const DWRITE_MATRIX, use_gdi_natural: BOOL, glyph_indices: [*]const UINT16, glyph_count: UINT32, metrics: [*]DWRITE_GLYPH_METRICS, is_sideways: BOOL) HRESULT {
        return self.vtable.GetGdiCompatibleGlyphMetrics(self, em_size, pixels_per_dip, transform, use_gdi_natural, glyph_indices, glyph_count, metrics, is_sideways);
    }
};

const FontFaceFn = *const fn (*IDWriteFontFace) callconv(.winapi) HRESULT;

pub const IDWriteFontFaceVTable = extern struct {
    // IUnknown
    QueryInterface: *const fn (*IDWriteFontFace, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*IDWriteFontFace) callconv(.winapi) u32,
    Release: *const fn (*IDWriteFontFace) callconv(.winapi) u32,
    // IDWriteFontFace
    GetType: *const fn (*IDWriteFontFace) callconv(.winapi) c_int,
    GetFiles: *const fn (*IDWriteFontFace, *UINT32, ?[*]*anyopaque) callconv(.winapi) HRESULT,
    GetIndex: *const fn (*IDWriteFontFace) callconv(.winapi) UINT32,
    GetSimulations: *const fn (*IDWriteFontFace) callconv(.winapi) DWRITE_FONT_SIMULATIONS,
    IsSymbolFont: *const fn (*IDWriteFontFace) callconv(.winapi) BOOL,
    GetMetrics: *const fn (*IDWriteFontFace, *DWRITE_FONT_METRICS) callconv(.winapi) void,
    GetGlyphCount: *const fn (*IDWriteFontFace) callconv(.winapi) UINT16,
    GetDesignGlyphMetrics: *const fn (*IDWriteFontFace, [*]const UINT16, UINT32, [*]DWRITE_GLYPH_METRICS, BOOL) callconv(.winapi) HRESULT,
    GetGlyphIndices: *const fn (*IDWriteFontFace, [*]const UINT32, UINT32, [*]UINT16) callconv(.winapi) HRESULT,
    TryGetFontTable: *const fn (*IDWriteFontFace, UINT32, *?*anyopaque, *UINT32, *?*anyopaque, *BOOL) callconv(.winapi) HRESULT,
    ReleaseFontTable: *const fn (*IDWriteFontFace, ?*anyopaque) callconv(.winapi) void,
    GetGlyphRunOutline: *const fn (*IDWriteFontFace, f32, [*]const UINT16, ?[*]const f32, ?[*]const DWRITE_GLYPH_OFFSET, UINT32, BOOL, BOOL, *anyopaque) callconv(.winapi) HRESULT,
    GetRecommendedRenderingMode: *const fn (*IDWriteFontFace, f32, f32, DWRITE_MEASURING_MODE, *IDWriteRenderingParams, *DWRITE_RENDERING_MODE) callconv(.winapi) HRESULT,
    GetGdiCompatibleMetrics: *const fn (*IDWriteFontFace, f32, f32, ?*const DWRITE_MATRIX, *DWRITE_FONT_METRICS) callconv(.winapi) HRESULT,
    GetGdiCompatibleGlyphMetrics: *const fn (*IDWriteFontFace, f32, f32, ?*const DWRITE_MATRIX, BOOL, [*]const UINT16, UINT32, [*]DWRITE_GLYPH_METRICS, BOOL) callconv(.winapi) HRESULT,
};

// ============================================================================
// IDWriteLocalizedStrings
// ============================================================================

pub const IDWriteLocalizedStrings = extern struct {
    vtable: *const IDWriteLocalizedStringsVTable,

    pub fn queryInterface(self: *IDWriteLocalizedStrings, riid: *const GUID, out: *?*anyopaque) HRESULT {
        return self.vtable.QueryInterface(self, riid, out);
    }

    pub fn addRef(self: *IDWriteLocalizedStrings) u32 {
        return self.vtable.AddRef(self);
    }

    pub fn release(self: *IDWriteLocalizedStrings) u32 {
        return self.vtable.Release(self);
    }

    pub fn getCount(self: *IDWriteLocalizedStrings) UINT32 {
        return self.vtable.GetCount(self);
    }

    pub fn findLocaleName(self: *IDWriteLocalizedStrings, locale_name: LPCWSTR, index: *UINT32, exists: *BOOL) HRESULT {
        return self.vtable.FindLocaleName(self, locale_name, index, exists);
    }

    pub fn getLocaleNameLength(self: *IDWriteLocalizedStrings, index: UINT32, length: *UINT32) HRESULT {
        return self.vtable.GetLocaleNameLength(self, index, length);
    }

    pub fn getLocaleName(self: *IDWriteLocalizedStrings, index: UINT32, locale_name: LPWSTR, size: UINT32) HRESULT {
        return self.vtable.GetLocaleName(self, index, locale_name, size);
    }

    pub fn getStringLength(self: *IDWriteLocalizedStrings, index: UINT32, length: *UINT32) HRESULT {
        return self.vtable.GetStringLength(self, index, length);
    }

    pub fn getString(self: *IDWriteLocalizedStrings, index: UINT32, string: LPWSTR, size: UINT32) HRESULT {
        return self.vtable.GetString(self, index, string, size);
    }
};

pub const IDWriteLocalizedStringsVTable = extern struct {
    // IUnknown
    QueryInterface: *const fn (*IDWriteLocalizedStrings, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*IDWriteLocalizedStrings) callconv(.winapi) u32,
    Release: *const fn (*IDWriteLocalizedStrings) callconv(.winapi) u32,
    // IDWriteLocalizedStrings
    GetCount: *const fn (*IDWriteLocalizedStrings) callconv(.winapi) UINT32,
    FindLocaleName: *const fn (*IDWriteLocalizedStrings, LPCWSTR, *UINT32, *BOOL) callconv(.winapi) HRESULT,
    GetLocaleNameLength: *const fn (*IDWriteLocalizedStrings, UINT32, *UINT32) callconv(.winapi) HRESULT,
    GetLocaleName: *const fn (*IDWriteLocalizedStrings, UINT32, LPWSTR, UINT32) callconv(.winapi) HRESULT,
    GetStringLength: *const fn (*IDWriteLocalizedStrings, UINT32, *UINT32) callconv(.winapi) HRESULT,
    GetString: *const fn (*IDWriteLocalizedStrings, UINT32, LPWSTR, UINT32) callconv(.winapi) HRESULT,
};

// ============================================================================
// IDWriteRenderingParams
// ============================================================================

pub const IDWriteRenderingParams = extern struct {
    vtable: *const IDWriteRenderingParamsVTable,

    pub fn queryInterface(self: *IDWriteRenderingParams, riid: *const GUID, out: *?*anyopaque) HRESULT {
        return self.vtable.QueryInterface(self, riid, out);
    }

    pub fn addRef(self: *IDWriteRenderingParams) u32 {
        return self.vtable.AddRef(self);
    }

    pub fn release(self: *IDWriteRenderingParams) u32 {
        return self.vtable.Release(self);
    }

    pub fn getGamma(self: *IDWriteRenderingParams) f32 {
        return self.vtable.GetGamma(self);
    }

    pub fn getEnhancedContrast(self: *IDWriteRenderingParams) f32 {
        return self.vtable.GetEnhancedContrast(self);
    }

    pub fn getClearTypeLevel(self: *IDWriteRenderingParams) f32 {
        return self.vtable.GetClearTypeLevel(self);
    }

    pub fn getPixelGeometry(self: *IDWriteRenderingParams) DWRITE_PIXEL_GEOMETRY {
        return self.vtable.GetPixelGeometry(self);
    }

    pub fn getRenderingMode(self: *IDWriteRenderingParams) DWRITE_RENDERING_MODE {
        return self.vtable.GetRenderingMode(self);
    }
};

pub const IDWriteRenderingParamsVTable = extern struct {
    // IUnknown
    QueryInterface: *const fn (*IDWriteRenderingParams, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*IDWriteRenderingParams) callconv(.winapi) u32,
    Release: *const fn (*IDWriteRenderingParams) callconv(.winapi) u32,
    // IDWriteRenderingParams
    GetGamma: *const fn (*IDWriteRenderingParams) callconv(.winapi) f32,
    GetEnhancedContrast: *const fn (*IDWriteRenderingParams) callconv(.winapi) f32,
    GetClearTypeLevel: *const fn (*IDWriteRenderingParams) callconv(.winapi) f32,
    GetPixelGeometry: *const fn (*IDWriteRenderingParams) callconv(.winapi) DWRITE_PIXEL_GEOMETRY,
    GetRenderingMode: *const fn (*IDWriteRenderingParams) callconv(.winapi) DWRITE_RENDERING_MODE,
};

// ============================================================================
// IDWriteGlyphRunAnalysis
// ============================================================================

pub const IDWriteGlyphRunAnalysis = extern struct {
    vtable: *const IDWriteGlyphRunAnalysisVTable,

    pub fn queryInterface(self: *IDWriteGlyphRunAnalysis, riid: *const GUID, out: *?*anyopaque) HRESULT {
        return self.vtable.QueryInterface(self, riid, out);
    }

    pub fn addRef(self: *IDWriteGlyphRunAnalysis) u32 {
        return self.vtable.AddRef(self);
    }

    pub fn release(self: *IDWriteGlyphRunAnalysis) u32 {
        return self.vtable.Release(self);
    }

    pub fn getAlphaTextureBounds(self: *IDWriteGlyphRunAnalysis, texture_type: DWRITE_TEXTURE_TYPE, bounds: *RECT) HRESULT {
        return self.vtable.GetAlphaTextureBounds(self, texture_type, bounds);
    }

    pub fn createAlphaTexture(self: *IDWriteGlyphRunAnalysis, texture_type: DWRITE_TEXTURE_TYPE, bounds: *const RECT, alpha_values: [*]u8, buffer_size: UINT32) HRESULT {
        return self.vtable.CreateAlphaTexture(self, texture_type, bounds, alpha_values, buffer_size);
    }
};

pub const IDWriteGlyphRunAnalysisVTable = extern struct {
    // IUnknown
    QueryInterface: *const fn (*IDWriteGlyphRunAnalysis, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*IDWriteGlyphRunAnalysis) callconv(.winapi) u32,
    Release: *const fn (*IDWriteGlyphRunAnalysis) callconv(.winapi) u32,
    // IDWriteGlyphRunAnalysis
    GetAlphaTextureBounds: *const fn (*IDWriteGlyphRunAnalysis, DWRITE_TEXTURE_TYPE, *RECT) callconv(.winapi) HRESULT,
    CreateAlphaTexture: *const fn (*IDWriteGlyphRunAnalysis, DWRITE_TEXTURE_TYPE, *const RECT, [*]u8, UINT32) callconv(.winapi) HRESULT,
    GetAlphaBlendParams: *const fn (*IDWriteGlyphRunAnalysis, *IDWriteRenderingParams, *f32, *f32, *f32) callconv(.winapi) HRESULT,
};

// ============================================================================
// IDWriteTextAnalyzer
// ============================================================================

pub const IDWriteTextAnalyzer = extern struct {
    vtable: *const IDWriteTextAnalyzerVTable,

    pub fn queryInterface(self: *IDWriteTextAnalyzer, riid: *const GUID, out: *?*anyopaque) HRESULT {
        return self.vtable.QueryInterface(self, riid, out);
    }

    pub fn addRef(self: *IDWriteTextAnalyzer) u32 {
        return self.vtable.AddRef(self);
    }

    pub fn release(self: *IDWriteTextAnalyzer) u32 {
        return self.vtable.Release(self);
    }

    pub fn analyzeScript(self: *IDWriteTextAnalyzer, source: *IDWriteTextAnalysisSource, text_position: UINT32, text_length: UINT32, sink: *IDWriteTextAnalysisSink) HRESULT {
        return self.vtable.AnalyzeScript(self, source, text_position, text_length, sink);
    }

    pub fn getGlyphs(
        self: *IDWriteTextAnalyzer,
        text: [*]const WCHAR,
        text_length: UINT32,
        font_face: *IDWriteFontFace,
        is_sideways: BOOL,
        is_right_to_left: BOOL,
        script_analysis: *const anyopaque,
        locale_name: ?LPCWSTR,
        number_substitution: ?*anyopaque,
        features: ?*const anyopaque,
        feature_range_lengths: ?[*]const UINT32,
        feature_ranges: UINT32,
        max_glyph_count: UINT32,
        cluster_map: [*]UINT16,
        text_props: [*]anyopaque,
        glyph_indices: [*]UINT16,
        glyph_props: [*]anyopaque,
        actual_glyph_count: *UINT32,
    ) HRESULT {
        return self.vtable.GetGlyphs(self, text, text_length, font_face, is_sideways, is_right_to_left, script_analysis, locale_name, number_substitution, features, feature_range_lengths, feature_ranges, max_glyph_count, cluster_map, text_props, glyph_indices, glyph_props, actual_glyph_count);
    }

    pub fn getGlyphPlacements(
        self: *IDWriteTextAnalyzer,
        text: [*]const WCHAR,
        cluster_map: [*]const UINT16,
        text_props: [*]anyopaque,
        text_length: UINT32,
        glyph_indices: [*]const UINT16,
        glyph_props: [*]const anyopaque,
        glyph_count: UINT32,
        font_face: *IDWriteFontFace,
        font_em_size: f32,
        is_sideways: BOOL,
        is_right_to_left: BOOL,
        script_analysis: *const anyopaque,
        locale_name: ?LPCWSTR,
        features: ?*const anyopaque,
        feature_range_lengths: ?[*]const UINT32,
        feature_ranges: UINT32,
        glyph_advances: [*]f32,
        glyph_offsets: [*]DWRITE_GLYPH_OFFSET,
    ) HRESULT {
        return self.vtable.GetGlyphPlacements(self, text, cluster_map, text_props, text_length, glyph_indices, glyph_props, glyph_count, font_face, font_em_size, is_sideways, is_right_to_left, script_analysis, locale_name, features, feature_range_lengths, feature_ranges, glyph_advances, glyph_offsets);
    }
};

const TextAnalyzerFn = *const fn (*IDWriteTextAnalyzer) callconv(.winapi) HRESULT;

pub const IDWriteTextAnalyzerVTable = extern struct {
    // IUnknown
    QueryInterface: *const fn (*IDWriteTextAnalyzer, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*IDWriteTextAnalyzer) callconv(.winapi) u32,
    Release: *const fn (*IDWriteTextAnalyzer) callconv(.winapi) u32,
    // IDWriteTextAnalyzer
    AnalyzeScript: *const fn (*IDWriteTextAnalyzer, *IDWriteTextAnalysisSource, UINT32, UINT32, *IDWriteTextAnalysisSink) callconv(.winapi) HRESULT,
    AnalyzeBidi: TextAnalyzerFn,
    AnalyzeNumberSubstitution: TextAnalyzerFn,
    AnalyzeLineBreakpoints: TextAnalyzerFn,
    GetGlyphs: *const anyopaque,
    GetGlyphPlacements: *const anyopaque,
    GetGdiCompatibleGlyphPlacements: TextAnalyzerFn,
};

// ============================================================================
// IDWriteTextAnalysisSource (callback interface)
// ============================================================================

pub const IDWriteTextAnalysisSource = extern struct {
    vtable: *const IDWriteTextAnalysisSourceVTable,
};

pub const IDWriteTextAnalysisSourceVTable = extern struct {
    // IUnknown
    QueryInterface: *const fn (*IDWriteTextAnalysisSource, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*IDWriteTextAnalysisSource) callconv(.winapi) u32,
    Release: *const fn (*IDWriteTextAnalysisSource) callconv(.winapi) u32,
    // IDWriteTextAnalysisSource
    GetTextAtPosition: *const fn (*IDWriteTextAnalysisSource, UINT32, *LPCWSTR, *UINT32) callconv(.winapi) HRESULT,
    GetTextBeforePosition: *const fn (*IDWriteTextAnalysisSource, UINT32, *LPCWSTR, *UINT32) callconv(.winapi) HRESULT,
    GetParagraphReadingDirection: *const fn (*IDWriteTextAnalysisSource) callconv(.winapi) DWRITE_READING_DIRECTION,
    GetLocaleName: *const fn (*IDWriteTextAnalysisSource, UINT32, *UINT32, *LPCWSTR) callconv(.winapi) HRESULT,
    GetNumberSubstitution: *const fn (*IDWriteTextAnalysisSource, UINT32, *UINT32, *?*anyopaque) callconv(.winapi) HRESULT,
};

// ============================================================================
// IDWriteTextAnalysisSink (callback interface)
// ============================================================================

pub const IDWriteTextAnalysisSink = extern struct {
    vtable: *const IDWriteTextAnalysisSinkVTable,
};

pub const IDWriteTextAnalysisSinkVTable = extern struct {
    // IUnknown
    QueryInterface: *const fn (*IDWriteTextAnalysisSink, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*IDWriteTextAnalysisSink) callconv(.winapi) u32,
    Release: *const fn (*IDWriteTextAnalysisSink) callconv(.winapi) u32,
    // IDWriteTextAnalysisSink
    SetScriptAnalysis: *const fn (*IDWriteTextAnalysisSink, UINT32, UINT32, *const anyopaque) callconv(.winapi) HRESULT,
    SetLineBreakpoints: *const fn (*IDWriteTextAnalysisSink, UINT32, UINT32, *const anyopaque) callconv(.winapi) HRESULT,
    SetBidiLevel: *const fn (*IDWriteTextAnalysisSink, UINT32, UINT32, UINT32, UINT32) callconv(.winapi) HRESULT,
    SetNumberSubstitution: *const fn (*IDWriteTextAnalysisSink, UINT32, UINT32, *const anyopaque) callconv(.winapi) HRESULT,
};

// ============================================================================
// RECT
// ============================================================================

pub const RECT = extern struct {
    left: c_long,
    top: c_long,
    right: c_long,
    bottom: c_long,

    pub fn width(self: RECT) c_long {
        return self.right - self.left;
    }

    pub fn height(self: RECT) c_long {
        return self.bottom - self.top;
    }
};

// ============================================================================
// GUIDs
// ============================================================================

pub const IID_IDWriteFactory = GUID.init(0xb859ee5a, 0xdb15, 0x450c, .{ 0x8d, 0x96, 0xfb, 0x16, 0x96, 0x64, 0x14, 0x48 });
pub const IID_IDWriteFactory1 = GUID.init(0x30572f99, 0xdac6, 0x41db, .{ 0xa1, 0x6e, 0x04, 0x86, 0x30, 0x7e, 0x60, 0x6a });

// ============================================================================
// Entry Point
// ============================================================================

pub extern "dwrite" fn DWriteCreateFactory(
    factory_type: DWRITE_FACTORY_TYPE,
    iid: *const GUID,
    factory: **anyopaque,
) callconv(.winapi) HRESULT;
