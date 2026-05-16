const std = @import("std");
const windows = std.os.windows;

pub const HRESULT = windows.HRESULT;
pub const HWND = windows.HWND;
pub const BOOL = i32;
pub const GUID = windows.GUID;

pub inline fn succeeded(hr: HRESULT) bool {
    return hr >= 0;
}

pub inline fn failed(hr: HRESULT) bool {
    return hr < 0;
}

pub const IUnknown = extern union {
    pub const VTable = extern struct {
        QueryInterface: *const fn (*const IUnknown, *const GUID, **anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*const IUnknown) callconv(.winapi) u32,
        Release: *const fn (*const IUnknown) callconv(.winapi) u32,
    };

    vtable: *const VTable,

    pub fn QueryInterface(self: *const IUnknown, iid: *const GUID, out: **anyopaque) HRESULT {
        return self.vtable.QueryInterface(self, iid, out);
    }

    pub fn Release(self: *const IUnknown) u32 {
        return self.vtable.Release(self);
    }
};

pub const D2D_COLOR_F = extern struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

pub const D2D_RECT_F = extern struct {
    left: f32,
    top: f32,
    right: f32,
    bottom: f32,
};

pub const D2D_SIZE_F = extern struct {
    width: f32,
    height: f32,
};

pub const D2D_SIZE_U = extern struct {
    width: u32,
    height: u32,
};

pub const D2D_POINT_2F = extern struct {
    x: f32,
    y: f32,
};

pub const DXGI_FORMAT = enum(u32) {
    UNKNOWN = 0,
    B8G8R8A8_UNORM = 87,
};

pub const D2D1_ALPHA_MODE = enum(u32) {
    UNKNOWN = 0,
    PREMULTIPLIED = 1,
    STRAIGHT = 2,
    IGNORE = 3,
};

pub const D2D1_PIXEL_FORMAT = extern struct {
    format: DXGI_FORMAT,
    alphaMode: D2D1_ALPHA_MODE,
};

pub const D2D1_RENDER_TARGET_TYPE = enum(u32) {
    DEFAULT = 0,
    SOFTWARE = 1,
    HARDWARE = 2,
};

pub const D2D1_FEATURE_LEVEL = enum(u32) {
    DEFAULT = 0,
};

pub const D2D1_RENDER_TARGET_USAGE = packed struct(u32) {
    FORCE_BITMAP_REMOTING: u1 = 0,
    GDI_COMPATIBLE: u1 = 0,
    _padding: u30 = 0,
};

pub const D2D1_PRESENT_OPTIONS = packed struct(u32) {
    RETAIN_CONTENTS: u1 = 0,
    IMMEDIATELY: u1 = 0,
    _padding: u30 = 0,
};

pub const D2D1_RENDER_TARGET_PROPERTIES = extern struct {
    type: D2D1_RENDER_TARGET_TYPE,
    pixelFormat: D2D1_PIXEL_FORMAT,
    dpiX: f32,
    dpiY: f32,
    usage: D2D1_RENDER_TARGET_USAGE,
    minLevel: D2D1_FEATURE_LEVEL,
};

pub const D2D1_HWND_RENDER_TARGET_PROPERTIES = extern struct {
    hwnd: ?HWND,
    pixelSize: D2D_SIZE_U,
    presentOptions: D2D1_PRESENT_OPTIONS,
};

pub const D2D1_FACTORY_TYPE = enum(u32) {
    SINGLE_THREADED = 0,
    MULTI_THREADED = 1,
};

pub const D2D1_DEBUG_LEVEL = enum(u32) {
    NONE = 0,
    ERROR = 1,
    WARNING = 2,
    INFORMATION = 3,
};

pub const D2D1_FACTORY_OPTIONS = extern struct {
    debugLevel: D2D1_DEBUG_LEVEL,
};

pub const D2D1_ANTIALIAS_MODE = enum(u32) {
    PER_PRIMITIVE = 0,
    ALIASED = 1,
};

pub const D2D1_TEXT_ANTIALIAS_MODE = enum(u32) {
    DEFAULT = 0,
    CLEARTYPE = 1,
    GRAYSCALE = 2,
    ALIASED = 3,
};

pub const D2D1_DRAW_TEXT_OPTIONS = packed struct(u32) {
    NO_SNAP: u1 = 0,
    CLIP: u1 = 0,
    ENABLE_COLOR_FONT: u1 = 0,
    DISABLE_COLOR_BITMAP_SNAPPING: u1 = 0,
    _padding: u28 = 0,
};

pub const DWRITE_MEASURING_MODE = enum(i32) {
    NATURAL = 0,
    GDI_CLASSIC = 1,
    GDI_NATURAL = 2,
};

pub const DWRITE_FACTORY_TYPE = enum(i32) {
    SHARED = 0,
    ISOLATED = 1,
};

pub const DWRITE_FONT_WEIGHT = enum(i32) {
    NORMAL = 400,
    BOLD = 700,
};

pub const DWRITE_FONT_STYLE = enum(i32) {
    NORMAL = 0,
    OBLIQUE = 1,
    ITALIC = 2,
};

pub const DWRITE_FONT_STRETCH = enum(i32) {
    NORMAL = 5,
};

pub const DWRITE_TEXT_ALIGNMENT = enum(i32) {
    LEADING = 0,
    TRAILING = 1,
    CENTER = 2,
    JUSTIFIED = 3,
};

pub const DWRITE_PARAGRAPH_ALIGNMENT = enum(i32) {
    NEAR = 0,
    FAR = 1,
    CENTER = 2,
};

pub const DWRITE_WORD_WRAPPING = enum(i32) {
    WRAP = 0,
    NO_WRAP = 1,
};

pub const DWRITE_FONT_METRICS = extern struct {
    designUnitsPerEm: u16,
    ascent: u16,
    descent: u16,
    lineGap: i16,
    capHeight: u16,
    xHeight: u16,
    underlinePosition: i16,
    underlineThickness: u16,
    strikethroughPosition: i16,
    strikethroughThickness: u16,
};

pub const DWRITE_GLYPH_METRICS = extern struct {
    leftSideBearing: i32,
    advanceWidth: u32,
    rightSideBearing: i32,
    topSideBearing: i32,
    advanceHeight: u32,
    bottomSideBearing: i32,
    verticalOriginY: i32,
};

pub const DWRITE_TEXT_METRICS = extern struct {
    left: f32,
    top: f32,
    width: f32,
    widthIncludingTrailingWhitespace: f32,
    height: f32,
    layoutWidth: f32,
    layoutHeight: f32,
    maxBidiReorderingDepth: u32,
    lineCount: u32,
};

pub const IDWriteTextFormat = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        SetTextAlignment: *const fn (*const IDWriteTextFormat, DWRITE_TEXT_ALIGNMENT) callconv(.winapi) HRESULT,
        SetParagraphAlignment: *const fn (*const IDWriteTextFormat, DWRITE_PARAGRAPH_ALIGNMENT) callconv(.winapi) HRESULT,
        SetWordWrapping: *const fn (*const IDWriteTextFormat, DWRITE_WORD_WRAPPING) callconv(.winapi) HRESULT,
        SetReadingDirection: *const anyopaque,
        SetFlowDirection: *const anyopaque,
        SetIncrementalTabStop: *const anyopaque,
        SetTrimming: *const anyopaque,
        SetLineSpacing: *const anyopaque,
    };

    vtable: *const VTable,
    IUnknown: IUnknown,

    pub fn SetTextAlignment(self: *const IDWriteTextFormat, value: DWRITE_TEXT_ALIGNMENT) HRESULT {
        return self.vtable.SetTextAlignment(self, value);
    }

    pub fn SetParagraphAlignment(self: *const IDWriteTextFormat, value: DWRITE_PARAGRAPH_ALIGNMENT) HRESULT {
        return self.vtable.SetParagraphAlignment(self, value);
    }

    pub fn SetWordWrapping(self: *const IDWriteTextFormat, value: DWRITE_WORD_WRAPPING) HRESULT {
        return self.vtable.SetWordWrapping(self, value);
    }
};

pub const IDWriteFontCollection = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        GetFontFamilyCount: *const fn (*const IDWriteFontCollection) callconv(.winapi) u32,
        GetFontFamily: *const fn (*const IDWriteFontCollection, u32, **IDWriteFontFamily) callconv(.winapi) HRESULT,
        FindFamilyName: *const fn (*const IDWriteFontCollection, ?[*:0]const u16, ?*u32, ?*BOOL) callconv(.winapi) HRESULT,
        GetFontFromFontFace: *const anyopaque,
    };

    vtable: *const VTable,
    IUnknown: IUnknown,

    pub fn GetFontFamilyCount(self: *const IDWriteFontCollection) u32 {
        return self.vtable.GetFontFamilyCount(self);
    }

    pub fn FindFamilyName(
        self: *const IDWriteFontCollection,
        familyName: ?[*:0]const u16,
        index: ?*u32,
        exists: ?*BOOL,
    ) HRESULT {
        return self.vtable.FindFamilyName(self, familyName, index, exists);
    }

    pub fn GetFontFamily(
        self: *const IDWriteFontCollection,
        index: u32,
        fontFamily: **IDWriteFontFamily,
    ) HRESULT {
        return self.vtable.GetFontFamily(self, index, fontFamily);
    }
};

pub const IDWriteFontCollectionLoader = opaque {};
pub const IDWriteFontFile = opaque {};
pub const IDWriteFontFileLoader = opaque {};
pub const IDWriteFontFace = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        GetType: *const anyopaque,
        GetFiles: *const anyopaque,
        GetIndex: *const anyopaque,
        GetSimulations: *const anyopaque,
        IsSymbolFont: *const anyopaque,
        GetMetrics: *const anyopaque,
        GetGlyphCount: *const anyopaque,
        GetDesignGlyphMetrics: *const fn (*const IDWriteFontFace, [*]const u16, u32, [*]DWRITE_GLYPH_METRICS, BOOL) callconv(.winapi) HRESULT,
        GetGlyphIndices: *const fn (*const IDWriteFontFace, [*]const u32, u32, [*]u16) callconv(.winapi) HRESULT,
    };

    vtable: *const VTable,
    IUnknown: IUnknown,

    pub fn GetGlyphIndices(
        self: *const IDWriteFontFace,
        codePoints: [*]const u32,
        codePointCount: u32,
        glyphIndices: [*]u16,
    ) HRESULT {
        return self.vtable.GetGlyphIndices(self, codePoints, codePointCount, glyphIndices);
    }

    pub fn GetDesignGlyphMetrics(
        self: *const IDWriteFontFace,
        glyphIndices: [*]const u16,
        glyphCount: u32,
        glyphMetrics: [*]DWRITE_GLYPH_METRICS,
        isSideways: BOOL,
    ) HRESULT {
        return self.vtable.GetDesignGlyphMetrics(self, glyphIndices, glyphCount, glyphMetrics, isSideways);
    }
};

pub const IDWriteLocalizedStrings = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        GetCount: *const fn (*const IDWriteLocalizedStrings) callconv(.winapi) u32,
        FindLocaleName: *const fn (*const IDWriteLocalizedStrings, ?[*:0]const u16, ?*u32, ?*BOOL) callconv(.winapi) HRESULT,
        GetLocaleNameLength: *const fn (*const IDWriteLocalizedStrings, u32, ?*u32) callconv(.winapi) HRESULT,
        GetLocaleName: *const fn (*const IDWriteLocalizedStrings, u32, [*:0]u16, u32) callconv(.winapi) HRESULT,
        GetStringLength: *const fn (*const IDWriteLocalizedStrings, u32, ?*u32) callconv(.winapi) HRESULT,
        GetString: *const fn (*const IDWriteLocalizedStrings, u32, [*:0]u16, u32) callconv(.winapi) HRESULT,
    };

    vtable: *const VTable,
    IUnknown: IUnknown,

    pub fn GetCount(self: *const IDWriteLocalizedStrings) u32 {
        return self.vtable.GetCount(self);
    }

    pub fn FindLocaleName(
        self: *const IDWriteLocalizedStrings,
        localeName: ?[*:0]const u16,
        index: ?*u32,
        exists: ?*BOOL,
    ) HRESULT {
        return self.vtable.FindLocaleName(self, localeName, index, exists);
    }

    pub fn GetStringLength(
        self: *const IDWriteLocalizedStrings,
        index: u32,
        length: ?*u32,
    ) HRESULT {
        return self.vtable.GetStringLength(self, index, length);
    }

    pub fn GetString(
        self: *const IDWriteLocalizedStrings,
        index: u32,
        stringBuffer: [*:0]u16,
        size: u32,
    ) HRESULT {
        return self.vtable.GetString(self, index, stringBuffer, size);
    }
};

pub const IDWriteFontList = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        GetFontCollection: *const fn (*const IDWriteFontList, **IDWriteFontCollection) callconv(.winapi) HRESULT,
        GetFontCount: *const fn (*const IDWriteFontList) callconv(.winapi) u32,
        GetFont: *const fn (*const IDWriteFontList, u32, **IDWriteFont) callconv(.winapi) HRESULT,
    };

    vtable: *const VTable,
    IUnknown: IUnknown,

    pub fn GetFontCount(self: *const IDWriteFontList) u32 {
        return self.vtable.GetFontCount(self);
    }

    pub fn GetFont(
        self: *const IDWriteFontList,
        index: u32,
        font_: **IDWriteFont,
    ) HRESULT {
        return self.vtable.GetFont(self, index, font_);
    }
};

pub const IDWriteFontFamily = extern union {
    pub const VTable = extern struct {
        base: IDWriteFontList.VTable,
        GetFamilyNames: *const fn (*const IDWriteFontFamily, **IDWriteLocalizedStrings) callconv(.winapi) HRESULT,
        GetFirstMatchingFont: *const fn (
            *const IDWriteFontFamily,
            DWRITE_FONT_WEIGHT,
            DWRITE_FONT_STRETCH,
            DWRITE_FONT_STYLE,
            **IDWriteFont,
        ) callconv(.winapi) HRESULT,
        GetMatchingFonts: *const anyopaque,
    };

    vtable: *const VTable,
    IDWriteFontList: IDWriteFontList,
    IUnknown: IUnknown,

    pub fn GetFamilyNames(
        self: *const IDWriteFontFamily,
        names: **IDWriteLocalizedStrings,
    ) HRESULT {
        return self.vtable.GetFamilyNames(self, names);
    }

    pub fn GetFirstMatchingFont(
        self: *const IDWriteFontFamily,
        weight: DWRITE_FONT_WEIGHT,
        stretch: DWRITE_FONT_STRETCH,
        style: DWRITE_FONT_STYLE,
        matchingFont: **IDWriteFont,
    ) HRESULT {
        return self.vtable.GetFirstMatchingFont(self, weight, stretch, style, matchingFont);
    }
};

pub const IDWriteFont = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        GetFontFamily: *const anyopaque,
        GetWeight: *const anyopaque,
        GetStretch: *const anyopaque,
        GetStyle: *const anyopaque,
        IsSymbolFont: *const anyopaque,
        GetFaceNames: *const fn (*const IDWriteFont, **IDWriteLocalizedStrings) callconv(.winapi) HRESULT,
        GetInformationalStrings: *const anyopaque,
        GetSimulations: *const anyopaque,
        GetMetrics: *const fn (*const IDWriteFont, ?*DWRITE_FONT_METRICS) callconv(.winapi) void,
        HasCharacter: *const anyopaque,
        CreateFontFace: *const fn (*const IDWriteFont, **IDWriteFontFace) callconv(.winapi) HRESULT,
    };

    vtable: *const VTable,
    IUnknown: IUnknown,

    pub fn GetFaceNames(
        self: *const IDWriteFont,
        names: **IDWriteLocalizedStrings,
    ) HRESULT {
        return self.vtable.GetFaceNames(self, names);
    }

    pub fn GetMetrics(self: *const IDWriteFont, fontMetrics: ?*DWRITE_FONT_METRICS) void {
        self.vtable.GetMetrics(self, fontMetrics);
    }

    pub fn CreateFontFace(self: *const IDWriteFont, fontFace: **IDWriteFontFace) HRESULT {
        return self.vtable.CreateFontFace(self, fontFace);
    }
};

pub const IDWriteRenderingParams = opaque {};
pub const IDWriteGdiInterop = opaque {};
pub const IDWriteTypography = opaque {};
pub const IDWriteInlineObject = opaque {};
pub const IDWriteTextLayout = extern union {
    pub const VTable = extern struct {
        base: IDWriteTextFormat.VTable,
        SetMaxWidth: *const anyopaque,
        SetMaxHeight: *const anyopaque,
        SetFontCollection: *const anyopaque,
        SetFontFamilyName: *const anyopaque,
        SetFontWeight: *const anyopaque,
        SetFontStyle: *const anyopaque,
        SetFontStretch: *const anyopaque,
        SetFontSize: *const anyopaque,
        SetUnderline: *const anyopaque,
        SetStrikethrough: *const anyopaque,
        SetDrawingEffect: *const anyopaque,
        SetInlineObject: *const anyopaque,
        SetTypography: *const anyopaque,
        SetLocaleName: *const anyopaque,
        GetMaxWidth: *const anyopaque,
        GetMaxHeight: *const anyopaque,
        GetFontCollection: *const anyopaque,
        GetFontFamilyNameLength: *const anyopaque,
        GetFontFamilyName: *const anyopaque,
        GetFontWeight: *const anyopaque,
        GetFontStyle: *const anyopaque,
        GetFontStretch: *const anyopaque,
        GetFontSize: *const anyopaque,
        GetUnderline: *const anyopaque,
        GetStrikethrough: *const anyopaque,
        GetDrawingEffect: *const anyopaque,
        GetInlineObject: *const anyopaque,
        GetTypography: *const anyopaque,
        GetLocaleNameLength: *const anyopaque,
        GetLocaleName: *const anyopaque,
        Draw: *const anyopaque,
        GetLineMetrics: *const anyopaque,
        GetMetrics: *const fn (*const IDWriteTextLayout, ?*DWRITE_TEXT_METRICS) callconv(.winapi) HRESULT,
    };

    vtable: *const VTable,
    IDWriteTextFormat: IDWriteTextFormat,
    IUnknown: IUnknown,

    pub fn GetMetrics(self: *const IDWriteTextLayout, textMetrics: ?*DWRITE_TEXT_METRICS) HRESULT {
        return self.vtable.GetMetrics(self, textMetrics);
    }
};
pub const IDWriteTextAnalyzer = opaque {};
pub const IDWriteNumberSubstitution = opaque {};
pub const IDWriteGlyphRunAnalysis = opaque {};
pub const FILETIME = opaque {};
pub const HMONITOR = ?*anyopaque;
pub const DWRITE_PIXEL_GEOMETRY = enum(i32) { FLAT = 0 };
pub const DWRITE_RENDERING_MODE = enum(i32) { DEFAULT = 0 };
pub const DWRITE_FONT_FACE_TYPE = enum(i32) { UNKNOWN = 6 };
pub const DWRITE_FONT_SIMULATIONS = packed struct(u32) { BOLD: u1 = 0, OBLIQUE: u1 = 0, _padding: u30 = 0 };
pub const DWRITE_MATRIX = extern struct { m11: f32, m12: f32, m21: f32, m22: f32, dx: f32, dy: f32 };
pub const DWRITE_NUMBER_SUBSTITUTION_METHOD = enum(i32) { FROM_CULTURE = 0 };
pub const DWRITE_FONT_PROPERTY = opaque {};

pub const IDWriteFontSet = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
    };

    vtable: *const VTable,
    IUnknown: IUnknown,
};

pub const IDWriteFontFaceReference = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
    };

    vtable: *const VTable,
    IUnknown: IUnknown,
};

pub const IDWriteFontCollection1 = extern union {
    pub const VTable = extern struct {
        base: IDWriteFontCollection.VTable,
        GetFontSet: *const anyopaque,
        GetFontFamily: *const anyopaque,
    };

    vtable: *const VTable,
    IDWriteFontCollection: IDWriteFontCollection,
    IUnknown: IUnknown,

    pub fn fontCollection(self: *IDWriteFontCollection1) *IDWriteFontCollection {
        return @ptrCast(self);
    }
};

pub const IDWriteFontSetBuilder = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        AddFontFaceReferenceWithProperties: *const anyopaque,
        AddFontFaceReferenceDefault: *const fn (*const IDWriteFontSetBuilder, ?*IDWriteFontFaceReference) callconv(.winapi) HRESULT,
        AddFontSet: *const anyopaque,
        CreateFontSet: *const fn (*const IDWriteFontSetBuilder, **IDWriteFontSet) callconv(.winapi) HRESULT,
    };

    vtable: *const VTable,
    IUnknown: IUnknown,

    pub fn AddFontFaceReferenceDefault(self: *const IDWriteFontSetBuilder, fontFaceReference: ?*IDWriteFontFaceReference) HRESULT {
        return self.vtable.AddFontFaceReferenceDefault(self, fontFaceReference);
    }

    pub fn CreateFontSet(self: *const IDWriteFontSetBuilder, fontSet: **IDWriteFontSet) HRESULT {
        return self.vtable.CreateFontSet(self, fontSet);
    }
};

pub const IDWriteFactory = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        GetSystemFontCollection: *const fn (*const IDWriteFactory, **IDWriteFontCollection, BOOL) callconv(.winapi) HRESULT,
        CreateCustomFontCollection: *const anyopaque,
        RegisterFontCollectionLoader: *const anyopaque,
        UnregisterFontCollectionLoader: *const anyopaque,
        CreateFontFileReference: *const anyopaque,
        CreateCustomFontFileReference: *const anyopaque,
        CreateFontFace: *const anyopaque,
        CreateRenderingParams: *const anyopaque,
        CreateMonitorRenderingParams: *const anyopaque,
        CreateCustomRenderingParams: *const anyopaque,
        RegisterFontFileLoader: *const anyopaque,
        UnregisterFontFileLoader: *const anyopaque,
        CreateTextFormat: *const fn (
            *const IDWriteFactory,
            ?[*:0]const u16,
            ?*IDWriteFontCollection,
            DWRITE_FONT_WEIGHT,
            DWRITE_FONT_STYLE,
            DWRITE_FONT_STRETCH,
            f32,
            ?[*:0]const u16,
            **IDWriteTextFormat,
        ) callconv(.winapi) HRESULT,
        CreateTypography: *const anyopaque,
        GetGdiInterop: *const anyopaque,
        CreateTextLayout: *const fn (
            *const IDWriteFactory,
            [*:0]const u16,
            u32,
            ?*IDWriteTextFormat,
            f32,
            f32,
            **IDWriteTextLayout,
        ) callconv(.winapi) HRESULT,
    };

    vtable: *const VTable,
    IUnknown: IUnknown,

    pub fn GetSystemFontCollection(
        self: *const IDWriteFactory,
        fontCollection: **IDWriteFontCollection,
        checkForUpdates: BOOL,
    ) HRESULT {
        return self.vtable.GetSystemFontCollection(self, fontCollection, checkForUpdates);
    }

    pub fn CreateTextFormat(
        self: *const IDWriteFactory,
        fontFamilyName: ?[*:0]const u16,
        fontCollection: ?*IDWriteFontCollection,
        fontWeight: DWRITE_FONT_WEIGHT,
        fontStyle: DWRITE_FONT_STYLE,
        fontStretch: DWRITE_FONT_STRETCH,
        fontSize: f32,
        localeName: ?[*:0]const u16,
        textFormat: **IDWriteTextFormat,
    ) HRESULT {
        return self.vtable.CreateTextFormat(
            self,
            fontFamilyName,
            fontCollection,
            fontWeight,
            fontStyle,
            fontStretch,
            fontSize,
            localeName,
            textFormat,
        );
    }

    pub fn CreateTextLayout(
        self: *const IDWriteFactory,
        string: [*:0]const u16,
        stringLength: u32,
        textFormat: ?*IDWriteTextFormat,
        maxWidth: f32,
        maxHeight: f32,
        textLayout: **IDWriteTextLayout,
    ) HRESULT {
        return self.vtable.CreateTextLayout(
            self,
            string,
            stringLength,
            textFormat,
            maxWidth,
            maxHeight,
            textLayout,
        );
    }
};

pub const IDWriteFactory1 = extern union {
    pub const VTable = extern struct {
        base: IDWriteFactory.VTable,
        GetEudcFontCollection: *const anyopaque,
        CreateCustomRenderingParams: *const anyopaque,
    };

    vtable: *const VTable,
    IDWriteFactory: IDWriteFactory,
    IUnknown: IUnknown,
};

pub const IDWriteFactory2 = extern union {
    pub const VTable = extern struct {
        base: IDWriteFactory1.VTable,
        GetSystemFontFallback: *const anyopaque,
        CreateFontFallbackBuilder: *const anyopaque,
        TranslateColorGlyphRun: *const anyopaque,
        CreateCustomRenderingParams: *const anyopaque,
        CreateGlyphRunAnalysis: *const anyopaque,
    };

    vtable: *const VTable,
    IDWriteFactory1: IDWriteFactory1,
    IDWriteFactory: IDWriteFactory,
    IUnknown: IUnknown,
};

pub const IDWriteFactory3 = extern union {
    pub const VTable = extern struct {
        base: IDWriteFactory2.VTable,
        CreateGlyphRunAnalysis: *const anyopaque,
        CreateCustomRenderingParams: *const anyopaque,
        CreateFontFaceReferenceFile: *const anyopaque,
        CreateFontFaceReferencePath: *const fn (*const IDWriteFactory3, ?[*:0]const u16, ?*const FILETIME, u32, DWRITE_FONT_SIMULATIONS, **IDWriteFontFaceReference) callconv(.winapi) HRESULT,
        GetSystemFontSet: *const anyopaque,
        CreateFontSetBuilder: *const fn (*const IDWriteFactory3, **IDWriteFontSetBuilder) callconv(.winapi) HRESULT,
        CreateFontCollectionFromFontSet: *const fn (*const IDWriteFactory3, ?*IDWriteFontSet, **IDWriteFontCollection1) callconv(.winapi) HRESULT,
        GetSystemFontCollection: *const anyopaque,
        GetFontDownloadQueue: *const anyopaque,
    };

    vtable: *const VTable,
    IDWriteFactory2: IDWriteFactory2,
    IDWriteFactory1: IDWriteFactory1,
    IDWriteFactory: IDWriteFactory,
    IUnknown: IUnknown,

    pub fn CreateFontFaceReferencePath(
        self: *const IDWriteFactory3,
        filePath: ?[*:0]const u16,
        lastWriteTime: ?*const FILETIME,
        faceIndex: u32,
        fontSimulations: DWRITE_FONT_SIMULATIONS,
        fontFaceReference: **IDWriteFontFaceReference,
    ) HRESULT {
        return self.vtable.CreateFontFaceReferencePath(self, filePath, lastWriteTime, faceIndex, fontSimulations, fontFaceReference);
    }

    pub fn CreateFontSetBuilder(self: *const IDWriteFactory3, fontSetBuilder: **IDWriteFontSetBuilder) HRESULT {
        return self.vtable.CreateFontSetBuilder(self, fontSetBuilder);
    }

    pub fn CreateFontCollectionFromFontSet(
        self: *const IDWriteFactory3,
        fontSet: ?*IDWriteFontSet,
        fontCollection: **IDWriteFontCollection1,
    ) HRESULT {
        return self.vtable.CreateFontCollectionFromFontSet(self, fontSet, fontCollection);
    }
};

pub const ID2D1Resource = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        GetFactory: *const fn (*const ID2D1Resource, **ID2D1Factory) callconv(.winapi) void,
    };

    vtable: *const VTable,
    IUnknown: IUnknown,
};

pub const ID2D1Bitmap = opaque {};
pub const ID2D1BitmapBrush = opaque {};
pub const ID2D1GradientStopCollection = opaque {};
pub const ID2D1LinearGradientBrush = opaque {};
pub const ID2D1RadialGradientBrush = opaque {};
pub const ID2D1BitmapRenderTarget = opaque {};
pub const ID2D1Layer = opaque {};
pub const ID2D1Mesh = opaque {};
pub const ID2D1StrokeStyle = opaque {};
pub const ID2D1DrawingStateBlock = opaque {};
pub const ID2D1Geometry = opaque {};

pub const D2D_MATRIX_3X2_F = extern struct {
    m11: f32,
    m12: f32,
    m21: f32,
    m22: f32,
    dx: f32,
    dy: f32,
};

pub const ID2D1Brush = extern union {
    pub const VTable = extern struct {
        base: ID2D1Resource.VTable,
        SetOpacity: *const anyopaque,
        SetTransform: *const anyopaque,
        GetOpacity: *const anyopaque,
        GetTransform: *const anyopaque,
    };

    vtable: *const VTable,
    ID2D1Resource: ID2D1Resource,
    IUnknown: IUnknown,
};

pub const ID2D1SolidColorBrush = extern union {
    pub const VTable = extern struct {
        base: ID2D1Brush.VTable,
        SetColor: *const fn (*const ID2D1SolidColorBrush, ?*const D2D_COLOR_F) callconv(.winapi) void,
        GetColor: *const anyopaque,
    };

    vtable: *const VTable,
    ID2D1Brush: ID2D1Brush,
    ID2D1Resource: ID2D1Resource,
    IUnknown: IUnknown,

    pub fn SetColor(self: *const ID2D1SolidColorBrush, color: ?*const D2D_COLOR_F) void {
        self.vtable.SetColor(self, color);
    }
};

pub const ID2D1RenderTarget = extern union {
    pub const VTable = extern struct {
        base: ID2D1Resource.VTable,
        CreateBitmap: *const anyopaque,
        CreateBitmapFromWicBitmap: *const anyopaque,
        CreateSharedBitmap: *const anyopaque,
        CreateBitmapBrush: *const anyopaque,
        CreateSolidColorBrush: *const fn (*const ID2D1RenderTarget, ?*const D2D_COLOR_F, ?*const anyopaque, **ID2D1SolidColorBrush) callconv(.winapi) HRESULT,
        CreateGradientStopCollection: *const anyopaque,
        CreateLinearGradientBrush: *const anyopaque,
        CreateRadialGradientBrush: *const anyopaque,
        CreateCompatibleRenderTarget: *const anyopaque,
        CreateLayer: *const anyopaque,
        CreateMesh: *const anyopaque,
        DrawLine: *const anyopaque,
        DrawRectangle: *const fn (*const ID2D1RenderTarget, ?*const D2D_RECT_F, ?*ID2D1Brush, f32, ?*ID2D1StrokeStyle) callconv(.winapi) void,
        FillRectangle: *const fn (*const ID2D1RenderTarget, ?*const D2D_RECT_F, ?*ID2D1Brush) callconv(.winapi) void,
        DrawRoundedRectangle: *const anyopaque,
        FillRoundedRectangle: *const anyopaque,
        DrawEllipse: *const anyopaque,
        FillEllipse: *const anyopaque,
        DrawGeometry: *const anyopaque,
        FillGeometry: *const anyopaque,
        FillMesh: *const anyopaque,
        FillOpacityMask: *const anyopaque,
        DrawBitmap: *const anyopaque,
        DrawText: *const fn (*const ID2D1RenderTarget, [*:0]const u16, u32, ?*IDWriteTextFormat, ?*const D2D_RECT_F, ?*ID2D1Brush, D2D1_DRAW_TEXT_OPTIONS, DWRITE_MEASURING_MODE) callconv(.winapi) void,
        DrawTextLayout: *const fn (*const ID2D1RenderTarget, D2D_POINT_2F, ?*IDWriteTextLayout, ?*ID2D1Brush, D2D1_DRAW_TEXT_OPTIONS) callconv(.winapi) void,
        DrawGlyphRun: *const anyopaque,
        SetTransform: *const fn (*const ID2D1RenderTarget, ?*const D2D_MATRIX_3X2_F) callconv(.winapi) void,
        GetTransform: *const anyopaque,
        SetAntialiasMode: *const fn (*const ID2D1RenderTarget, D2D1_ANTIALIAS_MODE) callconv(.winapi) void,
        GetAntialiasMode: *const anyopaque,
        SetTextAntialiasMode: *const fn (*const ID2D1RenderTarget, D2D1_TEXT_ANTIALIAS_MODE) callconv(.winapi) void,
        GetTextAntialiasMode: *const anyopaque,
        SetTextRenderingParams: *const anyopaque,
        GetTextRenderingParams: *const anyopaque,
        SetTags: *const anyopaque,
        GetTags: *const anyopaque,
        PushLayer: *const anyopaque,
        PopLayer: *const anyopaque,
        Flush: *const anyopaque,
        SaveDrawingState: *const anyopaque,
        RestoreDrawingState: *const anyopaque,
        PushAxisAlignedClip: *const fn (*const ID2D1RenderTarget, ?*const D2D_RECT_F, D2D1_ANTIALIAS_MODE) callconv(.winapi) void,
        PopAxisAlignedClip: *const fn (*const ID2D1RenderTarget) callconv(.winapi) void,
        Clear: *const fn (*const ID2D1RenderTarget, ?*const D2D_COLOR_F) callconv(.winapi) void,
        BeginDraw: *const fn (*const ID2D1RenderTarget) callconv(.winapi) void,
        EndDraw: *const fn (*const ID2D1RenderTarget, ?*u64, ?*u64) callconv(.winapi) HRESULT,
        GetPixelFormat: *const anyopaque,
        SetDpi: *const anyopaque,
        GetDpi: *const anyopaque,
        GetSize: *const anyopaque,
        GetPixelSize: *const anyopaque,
        GetMaximumBitmapSize: *const anyopaque,
        IsSupported: *const anyopaque,
    };

    vtable: *const VTable,
    ID2D1Resource: ID2D1Resource,
    IUnknown: IUnknown,

    pub fn CreateSolidColorBrush(self: *const ID2D1RenderTarget, color: ?*const D2D_COLOR_F, brush: **ID2D1SolidColorBrush) HRESULT {
        return self.vtable.CreateSolidColorBrush(self, color, null, brush);
    }

    pub fn FillRectangle(self: *const ID2D1RenderTarget, rect: ?*const D2D_RECT_F, brush: ?*ID2D1Brush) void {
        self.vtable.FillRectangle(self, rect, brush);
    }

    pub fn DrawRectangle(self: *const ID2D1RenderTarget, rect: ?*const D2D_RECT_F, brush: ?*ID2D1Brush, stroke_width: f32) void {
        self.vtable.DrawRectangle(self, rect, brush, stroke_width, null);
    }

    pub fn DrawText(
        self: *const ID2D1RenderTarget,
        string: [*:0]const u16,
        len: u32,
        format: ?*IDWriteTextFormat,
        rect: ?*const D2D_RECT_F,
        brush: ?*ID2D1Brush,
        options: D2D1_DRAW_TEXT_OPTIONS,
    ) void {
        self.vtable.DrawText(
            self,
            string,
            len,
            format,
            rect,
            brush,
            options,
            .NATURAL,
        );
    }

    pub fn DrawTextLayout(
        self: *const ID2D1RenderTarget,
        origin: D2D_POINT_2F,
        textLayout: ?*IDWriteTextLayout,
        brush: ?*ID2D1Brush,
        options: D2D1_DRAW_TEXT_OPTIONS,
    ) void {
        self.vtable.DrawTextLayout(self, origin, textLayout, brush, options);
    }

    pub fn SetTransform(self: *const ID2D1RenderTarget, transform: ?*const D2D_MATRIX_3X2_F) void {
        self.vtable.SetTransform(self, transform);
    }

    pub fn SetTextAntialiasMode(self: *const ID2D1RenderTarget, mode: D2D1_TEXT_ANTIALIAS_MODE) void {
        self.vtable.SetTextAntialiasMode(self, mode);
    }

    pub fn PushAxisAlignedClip(self: *const ID2D1RenderTarget, clipRect: ?*const D2D_RECT_F, antialiasMode: D2D1_ANTIALIAS_MODE) void {
        self.vtable.PushAxisAlignedClip(self, clipRect, antialiasMode);
    }

    pub fn PopAxisAlignedClip(self: *const ID2D1RenderTarget) void {
        self.vtable.PopAxisAlignedClip(self);
    }

    pub fn Clear(self: *const ID2D1RenderTarget, color: ?*const D2D_COLOR_F) void {
        self.vtable.Clear(self, color);
    }

    pub fn BeginDraw(self: *const ID2D1RenderTarget) void {
        self.vtable.BeginDraw(self);
    }

    pub fn EndDraw(self: *const ID2D1RenderTarget) HRESULT {
        return self.vtable.EndDraw(self, null, null);
    }
};

pub const ID2D1HwndRenderTarget = extern union {
    pub const VTable = extern struct {
        base: ID2D1RenderTarget.VTable,
        CheckWindowState: *const anyopaque,
        Resize: *const fn (*const ID2D1HwndRenderTarget, ?*const D2D_SIZE_U) callconv(.winapi) HRESULT,
        GetHwnd: *const anyopaque,
    };

    vtable: *const VTable,
    IUnknown: IUnknown,
    ID2D1Resource: ID2D1Resource,
    ID2D1RenderTarget: ID2D1RenderTarget,

    pub fn renderTarget(self: *ID2D1HwndRenderTarget) *ID2D1RenderTarget {
        return @ptrCast(self);
    }

    pub fn Resize(self: *const ID2D1HwndRenderTarget, size: ?*const D2D_SIZE_U) HRESULT {
        return self.vtable.Resize(self, size);
    }
};

pub const ID2D1Factory = extern union {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        ReloadSystemMetrics: *const anyopaque,
        GetDesktopDpi: *const anyopaque,
        CreateRectangleGeometry: *const anyopaque,
        CreateRoundedRectangleGeometry: *const anyopaque,
        CreateEllipseGeometry: *const anyopaque,
        CreateGeometryGroup: *const anyopaque,
        CreateTransformedGeometry: *const anyopaque,
        CreatePathGeometry: *const anyopaque,
        CreateStrokeStyle: *const anyopaque,
        CreateDrawingStateBlock: *const anyopaque,
        CreateWicBitmapRenderTarget: *const anyopaque,
        CreateHwndRenderTarget: *const fn (*const ID2D1Factory, ?*const D2D1_RENDER_TARGET_PROPERTIES, ?*const D2D1_HWND_RENDER_TARGET_PROPERTIES, **ID2D1HwndRenderTarget) callconv(.winapi) HRESULT,
    };

    vtable: *const VTable,
    IUnknown: IUnknown,

    pub fn CreateHwndRenderTarget(
        self: *const ID2D1Factory,
        renderTargetProperties: ?*const D2D1_RENDER_TARGET_PROPERTIES,
        hwndRenderTargetProperties: ?*const D2D1_HWND_RENDER_TARGET_PROPERTIES,
        hwndRenderTarget: **ID2D1HwndRenderTarget,
    ) HRESULT {
        return self.vtable.CreateHwndRenderTarget(
            self,
            renderTargetProperties,
            hwndRenderTargetProperties,
            hwndRenderTarget,
        );
    }
};

pub const IID_ID2D1Factory = GUID.parse("{06152247-6f50-465a-9245-118bfd3b6007}");
pub const IID_IDWriteFactory = GUID.parse("{b859ee5a-d838-4b5b-a2e8-1adc7d93db48}");
pub const IID_IDWriteFactory3 = GUID.parse("{9a1b41c3-d3bb-466a-87fc-fe67556a3b65}");

pub extern "d2d1" fn D2D1CreateFactory(
    factoryType: D2D1_FACTORY_TYPE,
    riid: ?*const GUID,
    pFactoryOptions: ?*const D2D1_FACTORY_OPTIONS,
    ppIFactory: **anyopaque,
) callconv(.winapi) HRESULT;

pub extern "dwrite" fn DWriteCreateFactory(
    factoryType: DWRITE_FACTORY_TYPE,
    iid: ?*const GUID,
    factory: **IUnknown,
) callconv(.winapi) HRESULT;
