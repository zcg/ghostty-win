const std = @import("std");
const builtin = @import("builtin");
const build_config = @import("build_config.zig");

/// See build_config.ExeEntrypoint for why we do this.
const entrypoint = switch (build_config.exe_entrypoint) {
    .ghostty => @import("main_ghostty.zig"),
    .helpgen => @import("helpgen.zig"),
    .mdgen_ghostty_1 => @import("build/mdgen/main_ghostty_1.zig"),
    .mdgen_ghostty_5 => @import("build/mdgen/main_ghostty_5.zig"),
    .webgen_config => @import("build/webgen/main_config.zig"),
    .webgen_actions => @import("build/webgen/main_actions.zig"),
    .webgen_commands => @import("build/webgen/main_commands.zig"),
};

/// The main entrypoint for the program.
pub const main = entrypoint.main;

/// Standard options such as logger overrides.
pub const std_options: std.Options = if (@hasDecl(entrypoint, "std_options"))
    entrypoint.std_options
else
    .{};

// On Windows with MSVC ABI, the MSVC CRT startup code (pulled in by C++
// static libraries) expects a WinMain symbol. We export a stub that calls
// the standard main function. Zig's own startup code handles the real
// entry point; this only satisfies the linker.
comptime {
    if (builtin.os.tag == .windows and builtin.abi == .msvc) {
        @export(&winMainStub, .{ .name = "WinMain" });
    }
}

fn winMainStub(
    instance: std.os.windows.HINSTANCE,
    prev_instance: ?std.os.windows.HINSTANCE,
    cmd_line: ?std.os.windows.LPWSTR,
    cmd_show: std.os.windows.INT,
) callconv(.winapi) std.os.windows.INT {
    _ = prev_instance;
    _ = cmd_line;
    _ = cmd_show;
    _ = instance;

    // If MSVC CRT's startup code calls us (instead of Zig's wWinMainCRTStartup),
    // we need to actually run the program. Call main directly.
    entrypoint.main() catch |err| {
        std.log.err("fatal error: {}", .{err});
        return 1;
    };
    return 0;
}

test {
    _ = entrypoint;
}
