const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Action = @import("ghostty.zig").Action;
const args = @import("args.zig");
const font = @import("../font/main.zig");
const d2d = if (builtin.os.tag == .windows) @import("../apprt/win32/d2d.zig") else void;

const log = std.log.scoped(.list_fonts);

pub const Options = struct {
    /// This is set by the CLI parser for deinit.
    _arena: ?ArenaAllocator = null,

    /// The font family to search for. If this is set, then only fonts
    /// matching this family will be listed.
    family: ?[:0]const u8 = null,

    /// The style name to search for.
    style: ?[:0]const u8 = null,

    /// Font styles to search for. If this is set, then only fonts that
    /// match the given styles will be listed.
    bold: bool = false,
    italic: bool = false,

    pub fn deinit(self: *Options) void {
        if (self._arena) |arena| arena.deinit();
        self.* = undefined;
    }

    /// Enables "-h" and "--help" to work.
    pub fn help(self: Options) !void {
        _ = self;
        return Action.help_error;
    }
};

/// The `list-fonts` command is used to list all the available fonts for
/// Ghostty. This uses the exact same font discovery mechanism Ghostty uses to
/// find fonts to use.
///
/// When executed with no arguments, this will list all available fonts, sorted
/// by family name, then font name. If a family name is given with `--family`,
/// the sorting will be disabled and the results instead will be shown in the
/// same priority order Ghostty would use to pick a font.
///
/// Flags:
///
///   * `--bold`: Filter results to specific bold styles. It is not guaranteed
///     that only those styles are returned. They are only prioritized.
///
///   * `--italic`: Filter results to specific italic styles. It is not guaranteed
///     that only those styles are returned. They are only prioritized.
///
///   * `--style`: Filter results based on the style string advertised by a font.
///     It is not guaranteed that only those styles are returned. They are only
///     prioritized.
///
///   * `--family`: Filter results to a specific font family. The family handling
///     is identical to the `font-family` set of Ghostty configuration values, so
///     this can be used to debug why your desired font may not be loading.
pub fn run(alloc: Allocator) !u8 {
    var iter = try args.argsIterator(alloc);
    defer iter.deinit();
    return try runArgs(alloc, &iter);
}

fn runArgs(alloc_gpa: Allocator, argsIter: anytype) !u8 {
    var config: Options = .{};
    defer config.deinit();
    try args.parse(Options, alloc_gpa, &config, argsIter);

    // Use an arena for all our memory allocs
    var arena = ArenaAllocator.init(alloc_gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Its possible to build Ghostty without font discovery!
    if (comptime font.Discover == void) {
        // On Windows, query DirectWrite directly. Native Windows builds do
        // not include FreeType or fontconfig.
        if (comptime builtin.os.tag == .windows) {
            return try listWindowsFonts(alloc_gpa, alloc, config);
        }

        var buffer: [1024]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&buffer);
        const stderr = &stderr_writer.interface;
        try stderr.print(
            \\Ghostty was built without a font discovery mechanism. This is a compile-time
            \\option. Please review how Ghostty was built from source, contact the
            \\maintainer to enable a font discovery mechanism, and try again.
        ,
            .{},
        );
        try stderr.flush();
        return 1;
    }

    var buffer: [2048]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &stdout_writer.interface;

    // We'll be putting our fonts into a list categorized by family
    // so it is easier to read the output.
    var families: std.ArrayList([]const u8) = .empty;
    var map: std.StringHashMap(std.ArrayListUnmanaged([]const u8)) = .init(alloc);

    // Look up all available fonts
    var disco = font.Discover.init();
    defer disco.deinit();
    var disco_it = try disco.discover(alloc, .{
        .family = config.family,
        .style = config.style,
        .bold = config.bold,
        .italic = config.italic,
        .monospace = config.family == null,
    });
    defer disco_it.deinit();
    while (try disco_it.next()) |face| {
        var buf: [1024]u8 = undefined;

        const family_buf = face.familyName(&buf) catch |err| {
            log.err("failed to get font family name: {}", .{err});
            continue;
        };
        const family = try alloc.dupe(u8, family_buf);

        const full_name_buf = face.name(&buf) catch |err| {
            log.err("failed to get font name: {}", .{err});
            continue;
        };
        const full_name = try alloc.dupe(u8, full_name_buf);

        const gop = try map.getOrPut(family);
        if (!gop.found_existing) {
            try families.append(alloc, family);
            gop.value_ptr.* = .{};
        }
        try gop.value_ptr.append(alloc, full_name);
    }

    // Sort our keys.
    if (config.family == null) {
        std.mem.sortUnstable([]const u8, families.items, {}, struct {
            fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
                return std.mem.order(u8, lhs, rhs) == .lt;
            }
        }.lessThan);
    }

    // Output each
    for (families.items) |family| {
        const list = map.get(family) orelse continue;
        if (list.items.len == 0) continue;
        if (config.family == null) {
            std.mem.sortUnstable([]const u8, list.items, {}, struct {
                fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
                    return std.mem.order(u8, lhs, rhs) == .lt;
                }
            }.lessThan);
        }

        try stdout.print("{s}\n", .{family});
        for (list.items) |item| try stdout.print("  {s}\n", .{item});
        try stdout.print("\n", .{});
    }

    try stdout.flush();
    return 0;
}

/// List fonts on Windows through DirectWrite so this command follows the
/// native Windows font backend.
fn listWindowsFonts(alloc_gpa: Allocator, alloc: Allocator, config: Options) !u8 {
    _ = alloc_gpa;

    var buffer: [2048]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &stdout_writer.interface;

    var families: std.ArrayList([]const u8) = .empty;
    var map: std.StringHashMap(std.ArrayListUnmanaged([]const u8)) = .init(alloc);

    var factory_unknown: *d2d.IUnknown = undefined;
    if (d2d.failed(d2d.DWriteCreateFactory(
        .SHARED,
        &d2d.IID_IDWriteFactory,
        &factory_unknown,
    ))) return error.DirectWriteUnavailable;
    const factory: *d2d.IDWriteFactory = @ptrCast(@alignCast(factory_unknown));
    defer releaseCom(factory);

    var collection: *d2d.IDWriteFontCollection = undefined;
    if (d2d.failed(factory.GetSystemFontCollection(&collection, 0))) {
        return error.DirectWriteUnavailable;
    }
    defer releaseCom(collection);

    const family_count = collection.GetFontFamilyCount();
    for (0..family_count) |family_index_usize| {
        const family_index: u32 = @intCast(family_index_usize);
        var family_ptr: *d2d.IDWriteFontFamily = undefined;
        if (d2d.failed(collection.GetFontFamily(family_index, &family_ptr))) continue;
        defer releaseCom(family_ptr);

        var family_names: *d2d.IDWriteLocalizedStrings = undefined;
        if (d2d.failed(family_ptr.GetFamilyNames(&family_names))) continue;
        defer releaseCom(family_names);

        const family = localizedStringUtf8(alloc, family_names) catch continue;
        if (config.family) |filter| {
            if (std.ascii.indexOfIgnoreCase(family, filter) == null) continue;
        }

        const gop = try map.getOrPut(family);
        if (!gop.found_existing) {
            try families.append(alloc, family);
            gop.value_ptr.* = .{};
        }

        const family_list: *const d2d.IDWriteFontList = @ptrCast(@alignCast(family_ptr));
        const font_count = family_list.GetFontCount();
        for (0..font_count) |font_index_usize| {
            const font_index: u32 = @intCast(font_index_usize);
            var dwrite_font: *d2d.IDWriteFont = undefined;
            if (d2d.failed(family_list.GetFont(font_index, &dwrite_font))) continue;
            defer releaseCom(dwrite_font);

            var face_names: *d2d.IDWriteLocalizedStrings = undefined;
            if (d2d.failed(dwrite_font.GetFaceNames(&face_names))) continue;
            defer releaseCom(face_names);

            const face_name = localizedStringUtf8(alloc, face_names) catch continue;
            if (!matchesWindowsFontFilters(face_name, config)) continue;

            const full_name = try std.fmt.allocPrint(alloc, "{s} {s}", .{ family, face_name });
            try gop.value_ptr.append(alloc, full_name);
        }
    }

    // Sort families
    std.mem.sortUnstable([]const u8, families.items, {}, struct {
        fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.order(u8, lhs, rhs) == .lt;
        }
    }.lessThan);

    for (families.items) |family| {
        const list = map.get(family) orelse continue;
        if (list.items.len == 0) continue;
        try stdout.print("{s}\n", .{family});
        for (list.items) |item| try stdout.print("  {s}\n", .{item});
        try stdout.print("\n", .{});
    }

    try stdout.flush();
    return 0;
}

fn matchesWindowsFontFilters(face_name: []const u8, config: Options) bool {
    if (config.style) |style| {
        if (std.ascii.indexOfIgnoreCase(face_name, style) == null) return false;
    }

    if (config.bold) {
        if (std.ascii.indexOfIgnoreCase(face_name, "bold") == null) return false;
    }

    if (config.italic) {
        const has_italic = std.ascii.indexOfIgnoreCase(face_name, "italic") != null or
            std.ascii.indexOfIgnoreCase(face_name, "oblique") != null;
        if (!has_italic) return false;
    }

    return true;
}

fn localizedStringUtf8(
    alloc: Allocator,
    strings: *const d2d.IDWriteLocalizedStrings,
) ![]const u8 {
    const index = findLocalizedStringIndex(strings);
    var len: u32 = 0;
    if (d2d.failed(strings.GetStringLength(index, &len))) return error.DirectWriteUnavailable;

    const buf = try alloc.allocSentinel(u16, len, 0);
    if (d2d.failed(strings.GetString(index, buf.ptr, len + 1))) return error.DirectWriteUnavailable;
    return try std.unicode.utf16LeToUtf8Alloc(alloc, buf[0..len]);
}

fn findLocalizedStringIndex(strings: *const d2d.IDWriteLocalizedStrings) u32 {
    const count = strings.GetCount();
    if (count == 0) return 0;

    const locale = std.unicode.utf8ToUtf16LeStringLiteral("en-us");
    var index: u32 = 0;
    var exists: d2d.BOOL = 0;
    if (d2d.succeeded(strings.FindLocaleName(locale, &index, &exists)) and exists != 0) {
        return index;
    }

    return 0;
}

fn releaseCom(value: anytype) void {
    const unknown: *d2d.IUnknown = @ptrCast(@alignCast(value));
    _ = unknown.Release();
}
