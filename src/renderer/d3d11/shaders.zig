const std = @import("std");
const Allocator = std.mem.Allocator;
const math = @import("../../math.zig");
const api = @import("api.zig");
const pipeline_mod = @import("Pipeline.zig");
const Pipeline = pipeline_mod.Pipeline;

const log = std.log.scoped(.d3d11);

/// Pipeline names matching generic.zig's expected field names.
const pipeline_names = [_][:0]const u8{
    "bg_color",
    "cell_bg",
    "cell_text",
    "image",
    "bg_image",
};

/// Comptime-generated struct with one Pipeline field per pipeline name.
const PipelineCollection = t: {
    var fields: [pipeline_names.len]std.builtin.Type.StructField = undefined;
    for (pipeline_names, 0..) |name, i| {
        fields[i] = .{
            .name = name,
            .type = Pipeline,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(Pipeline),
        };
    }
    break :t @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
};

/// Shader management and type definitions for D3D11.
pub const Shaders = struct {
    /// Collection of available render pipelines.
    pipelines: PipelineCollection,

    /// Custom shaders to run against the final drawable texture.
    post_pipelines: []const Pipeline = &.{},

    /// Set to true when deinited, if you try to deinit a defunct set
    /// of shaders it will just be ignored, to prevent double-free.
    defunct: bool = false,

    pub fn init(device: *api.ID3D11Device, alloc: Allocator, custom_shaders: []const [:0]const u8) !Shaders {
        _ = alloc;
        _ = custom_shaders;

        var shaders: Shaders = .{
            .pipelines = undefined,
        };

        // Compile and create all pipelines. If any fails, clean up and return error.
        shaders.pipelines.bg_color = compileBgColor(device) catch |err| {
            log.err("failed to compile bg_color shader: {}", .{err});
            return error.ShaderNotImplemented;
        };
        errdefer shaders.pipelines.bg_color.deinit();

        shaders.pipelines.cell_bg = compileCellBg(device) catch |err| {
            log.err("failed to compile cell_bg shader: {}", .{err});
            shaders.pipelines.bg_color.deinit();
            return error.ShaderNotImplemented;
        };
        errdefer shaders.pipelines.cell_bg.deinit();

        shaders.pipelines.cell_text = compileCellText(device) catch |err| {
            log.err("failed to compile cell_text shader: {}", .{err});
            shaders.pipelines.bg_color.deinit();
            shaders.pipelines.cell_bg.deinit();
            return error.ShaderNotImplemented;
        };
        errdefer shaders.pipelines.cell_text.deinit();

        shaders.pipelines.image = compileImage(device) catch |err| {
            log.err("failed to compile image shader: {}", .{err});
            shaders.pipelines.bg_color.deinit();
            shaders.pipelines.cell_bg.deinit();
            shaders.pipelines.cell_text.deinit();
            return error.ShaderNotImplemented;
        };
        errdefer shaders.pipelines.image.deinit();

        shaders.pipelines.bg_image = compileBgImage(device) catch |err| {
            log.err("failed to compile bg_image shader: {}", .{err});
            shaders.pipelines.bg_color.deinit();
            shaders.pipelines.cell_bg.deinit();
            shaders.pipelines.cell_text.deinit();
            shaders.pipelines.image.deinit();
            return error.ShaderNotImplemented;
        };

        return shaders;
    }

    pub fn deinit(self: *Shaders, alloc: Allocator) void {
        _ = alloc;
        if (self.defunct) return;
        self.defunct = true;

        inline for (pipeline_names) |name| {
            @field(self.pipelines, name).deinit();
        }

        for (self.post_pipelines) |p| {
            p.deinit();
        }
    }
};

// ============================================================================
// Shader compilation helpers
// ============================================================================

/// Compile an HLSL shader source string using D3DCompile.
/// Returns the bytecode blob. Caller must release the blob.
fn compileHlsl(
    source: [:0]const u8,
    source_name: [:0]const u8,
    entrypoint: [:0]const u8,
    target: [:0]const u8,
) !*api.ID3DBlob {
    var code_blob: ?*anyopaque = null;
    var error_blob: ?*anyopaque = null;

    const hr = api.D3DCompile(
        source.ptr,
        source.len,
        source_name.ptr,
        null,
        null,
        entrypoint.ptr,
        target.ptr,
        SHADER_COMPILE_FLAGS,
        0,
        @ptrCast(&code_blob),
        @ptrCast(&error_blob),
    );

    if (error_blob) |blob| {
        const typed: *api.ID3DBlob = @ptrCast(@alignCast(blob));
        const msg_ptr = typed.vtable.getBufferPointer(typed);
        const msg_len = typed.vtable.getBufferSize(typed);
        if (msg_ptr) |ptr| {
            const msg_bytes: [*]const u8 = @ptrCast(ptr);
            const msg = msg_bytes[0..msg_len];
            // D3DCompile returns warnings in the error blob even on success.
            // Use warn level for warnings, err level for actual errors.
            if (hr == api.S_OK) {
                log.warn("shader compile warning ({s}): {s}", .{ source_name, msg });
            } else {
                log.err("shader compile error ({s}): {s}", .{ source_name, msg });
            }
        }
        _ = api.releaseCOM(blob);
    }

    if (hr != api.S_OK) {
        log.err("D3DCompile failed for {s}, hr=0x{X}", .{ source_name, @as(u32, @bitCast(hr)) });
        return error.ShaderNotImplemented;
    }

    return @ptrCast(@alignCast(code_blob.?));
}

/// Extract bytecode slice from an ID3DBlob.
fn blobBytecode(blob: *api.ID3DBlob) []const u8 {
    const ptr = blob.vtable.getBufferPointer(blob) orelse return &.{};
    const len = blob.vtable.getBufferSize(blob);
    const bytes: [*]const u8 = @ptrCast(ptr);
    return bytes[0..len];
}

const D3DCOMPILE_DEBUG: api.UINT = 0x00000001;
const D3DCOMPILE_OPTIMIZATION_LEVEL3: api.UINT = 1 << 15; // 0x8000
const D3DCOMPILE_ENABLE_STRICTNESS: api.UINT = 1 << 4; // 0x10
// Use optimization level 3 for release builds
const SHADER_COMPILE_FLAGS: api.UINT = D3DCOMPILE_OPTIMIZATION_LEVEL3;

// ============================================================================
// Individual pipeline compilation functions
// ============================================================================

fn compileBgColor(device: *api.ID3D11Device) !Pipeline {
    const vs_blob = try compileHlsl(bg_color_vs, "bg_color.vs", "main", "vs_5_0");
    defer _ = api.releaseCOM(@ptrCast(vs_blob));
    const ps_blob = try compileHlsl(bg_color_ps, "bg_color.ps", "main", "ps_5_0");
    defer _ = api.releaseCOM(@ptrCast(ps_blob));

    const vs_bytecode = blobBytecode(vs_blob);
    const ps_bytecode = blobBytecode(ps_blob);

    return Pipeline.init(device, vs_bytecode, ps_bytecode, null, false);
}

fn compileCellBg(device: *api.ID3D11Device) !Pipeline {
    const vs_blob = try compileHlsl(cell_bg_vs, "cell_bg.vs", "main", "vs_5_0");
    defer _ = api.releaseCOM(@ptrCast(vs_blob));
    const ps_blob = try compileHlsl(cell_bg_ps, "cell_bg.ps", "main", "ps_5_0");
    defer _ = api.releaseCOM(@ptrCast(ps_blob));

    const vs_bytecode = blobBytecode(vs_blob);
    const ps_bytecode = blobBytecode(ps_blob);

    return Pipeline.init(device, vs_bytecode, ps_bytecode, null, true);
}

fn compileCellText(device: *api.ID3D11Device) !Pipeline {
    const vs_blob = try compileHlsl(cell_text_vs, "cell_text.vs", "main", "vs_5_0");
    defer _ = api.releaseCOM(@ptrCast(vs_blob));
    const ps_blob = try compileHlsl(cell_text_ps, "cell_text.ps", "main", "ps_5_0");
    defer _ = api.releaseCOM(@ptrCast(ps_blob));

    const vs_bytecode = blobBytecode(vs_blob);
    const ps_bytecode = blobBytecode(ps_blob);

    // Input layout for CellText - all per-instance
    const input_elements = [_]api.D3D11_INPUT_ELEMENT_DESC{
        .{
            .semantic_name = "TEXCOORD",
            .semantic_index = 0,
            .format = .r32g32_uint, // glyph_pos: [2]u32
            .input_slot = 0,
            .aligned_byte_offset = 0,
            .input_slot_class = .per_instance_data,
            .instance_data_step_rate = 1,
        },
        .{
            .semantic_name = "TEXCOORD",
            .semantic_index = 1,
            .format = .r32g32_uint, // glyph_size: [2]u32
            .input_slot = 0,
            .aligned_byte_offset = 8,
            .input_slot_class = .per_instance_data,
            .instance_data_step_rate = 1,
        },
        .{
            .semantic_name = "TEXCOORD",
            .semantic_index = 2,
            .format = .r16g16_sint, // bearings: [2]i16
            .input_slot = 0,
            .aligned_byte_offset = 16,
            .input_slot_class = .per_instance_data,
            .instance_data_step_rate = 1,
        },
        .{
            .semantic_name = "TEXCOORD",
            .semantic_index = 3,
            .format = .r16g16_uint, // grid_pos: [2]u16
            .input_slot = 0,
            .aligned_byte_offset = 20,
            .input_slot_class = .per_instance_data,
            .instance_data_step_rate = 1,
        },
        .{
            .semantic_name = "COLOR",
            .semantic_index = 0,
            .format = .r8g8b8a8_uint, // color: [4]u8
            .input_slot = 0,
            .aligned_byte_offset = 24,
            .input_slot_class = .per_instance_data,
            .instance_data_step_rate = 1,
        },
        .{
            .semantic_name = "TEXCOORD",
            .semantic_index = 4,
            .format = .r8g8_uint, // atlas + bools: [2]u8 at offsets 28,29
            .input_slot = 0,
            .aligned_byte_offset = 28,
            .input_slot_class = .per_instance_data,
            .instance_data_step_rate = 1,
        },
    };

    return Pipeline.init(device, vs_bytecode, ps_bytecode, &input_elements, true);
}

fn compileImage(device: *api.ID3D11Device) !Pipeline {
    const vs_blob = try compileHlsl(image_vs, "image.vs", "main", "vs_5_0");
    defer _ = api.releaseCOM(@ptrCast(vs_blob));
    const ps_blob = try compileHlsl(image_ps, "image.ps", "main", "ps_5_0");
    defer _ = api.releaseCOM(@ptrCast(ps_blob));

    const vs_bytecode = blobBytecode(vs_blob);
    const ps_bytecode = blobBytecode(ps_blob);

    // Input layout for Image - all per-instance
    const input_elements = [_]api.D3D11_INPUT_ELEMENT_DESC{
        .{
            .semantic_name = "POSITION",
            .semantic_index = 0,
            .format = .r32g32_float, // grid_pos: [2]f32
            .input_slot = 0,
            .aligned_byte_offset = 0,
            .input_slot_class = .per_instance_data,
            .instance_data_step_rate = 1,
        },
        .{
            .semantic_name = "TEXCOORD",
            .semantic_index = 0,
            .format = .r32g32_float, // cell_offset: [2]f32
            .input_slot = 0,
            .aligned_byte_offset = 8,
            .input_slot_class = .per_instance_data,
            .instance_data_step_rate = 1,
        },
        .{
            .semantic_name = "TEXCOORD",
            .semantic_index = 1,
            .format = .r32g32b32a32_float, // source_rect: [4]f32
            .input_slot = 0,
            .aligned_byte_offset = 16,
            .input_slot_class = .per_instance_data,
            .instance_data_step_rate = 1,
        },
        .{
            .semantic_name = "TEXCOORD",
            .semantic_index = 2,
            .format = .r32g32_float, // dest_size: [2]f32
            .input_slot = 0,
            .aligned_byte_offset = 32,
            .input_slot_class = .per_instance_data,
            .instance_data_step_rate = 1,
        },
    };

    return Pipeline.init(device, vs_bytecode, ps_bytecode, &input_elements, true);
}

fn compileBgImage(device: *api.ID3D11Device) !Pipeline {
    const vs_blob = try compileHlsl(bg_image_vs, "bg_image.vs", "main", "vs_5_0");
    defer _ = api.releaseCOM(@ptrCast(vs_blob));
    const ps_blob = try compileHlsl(bg_image_ps, "bg_image.ps", "main", "ps_5_0");
    defer _ = api.releaseCOM(@ptrCast(ps_blob));

    const vs_bytecode = blobBytecode(vs_blob);
    const ps_bytecode = blobBytecode(ps_blob);

    // Input layout for BgImage - all per-instance
    const input_elements = [_]api.D3D11_INPUT_ELEMENT_DESC{
        .{
            .semantic_name = "TEXCOORD",
            .semantic_index = 0,
            .format = .r32_float, // opacity: f32
            .input_slot = 0,
            .aligned_byte_offset = 0,
            .input_slot_class = .per_instance_data,
            .instance_data_step_rate = 1,
        },
        .{
            .semantic_name = "TEXCOORD",
            .semantic_index = 1,
            .format = .r8_uint, // info: u8
            .input_slot = 0,
            .aligned_byte_offset = 4,
            .input_slot_class = .per_instance_data,
            .instance_data_step_rate = 1,
        },
    };

    return Pipeline.init(device, vs_bytecode, ps_bytecode, &input_elements, true);
}

// ============================================================================
// Uniform and vertex types - must match the generic renderer's expectations
// and the HLSL cbuffer layout
// ============================================================================

/// PaddingExtend bit mask: order LSB first: left, right, up, down
pub const PaddingExtend = packed struct(u32) {
    left: bool = false,
    right: bool = false,
    up: bool = false,
    down: bool = false,
    _pad: u28 = 0,
};

/// Uniforms struct - must match the Globals cbuffer in common.hlsli
/// and the GenericRenderer's expected field layout.
/// Total size is padded to 144 bytes (9 x 16-byte cbuffer registers).
pub const Uniforms = extern struct {
    projection_matrix: math.Mat align(16),
    screen_size: [2]f32 align(8),
    cell_size: [2]f32 align(8),
    grid_size: [2]u16 align(4),
    grid_padding: [4]f32 align(16),
    padding_extend: PaddingExtend align(4),
    min_contrast: f32 align(4),
    cursor_pos: [2]u16 align(4),
    cursor_color: [4]u8 align(4),
    bg_color: [4]u8 align(4),
    bools: Bools align(4),
    _cbuffer_padding: [8]u8 align(8) = @splat(0),

    const Bools = packed struct(u32) {
        cursor_wide: bool = false,
        use_display_p3: bool = false,
        use_linear_blending: bool = false,
        use_linear_correction: bool = false,
        _padding: u28 = 0,
    };
};

/// Cell text vertex data - must match GenericRenderer's CellText expectations.
/// Total size is padded to 32 bytes so that the D3D11 vertex buffer stride
/// is a multiple of 4 (D3D11 IASetVertexBuffers requires this).
pub const CellText = extern struct {
    glyph_pos: [2]u32 align(8) = .{ 0, 0 },
    glyph_size: [2]u32 align(8) = .{ 0, 0 },
    bearings: [2]i16 align(4) = .{ 0, 0 },
    grid_pos: [2]u16 align(4),
    color: [4]u8 align(4),
    atlas: Atlas align(1),
    bools: packed struct(u8) {
        no_min_contrast: bool = false,
        is_cursor_glyph: bool = false,
        _padding: u6 = 0,
    } align(1) = .{},
    _d3d11_stride_padding: [2]u8 = @splat(0),

    pub const Atlas = enum(u8) {
        grayscale = 0,
        color = 1,
    };

    comptime {
        // D3D11 IASetVertexBuffers stride must be a multiple of 4
        if (@sizeOf(CellText) % 4 != 0) {
            @compileError("CellText size must be a multiple of 4 for D3D11");
        }
    }
};

/// Cell background data - 4 bytes per cell (BGRA).
pub const CellBg = [4]u8;

/// Image vertex data - must match ImageVSInput in image.vs.hlsl.
pub const Image = extern struct {
    grid_pos: [2]f32 align(4),
    cell_offset: [2]f32 align(4),
    source_rect: [4]f32 align(4),
    dest_size: [2]f32 align(4),
};

/// Background image vertex data - must match BgImageVSInput in bg_image.vs.hlsl.
pub const BgImage = extern struct {
    opacity: f32 align(4),
    info: Info align(1),

    pub const Info = packed struct(u8) {
        position: Position,
        fit: Fit,
        repeat: bool,
        _padding: u1 = 0,

        pub const Position = enum(u4) {
            tl = 0,
            tc = 1,
            tr = 2,
            ml = 3,
            mc = 4,
            mr = 5,
            bl = 6,
            bc = 7,
            br = 8,
        };

        pub const Fit = enum(u2) {
            contain = 0,
            cover = 1,
            stretch = 2,
            none = 3,
        };
    };
};

pub const ShaderError = error{ShaderNotImplemented};

// ============================================================================
// HLSL Shader Source Code
// ============================================================================
//
// HLSL cbuffer layout must exactly match the Zig Uniforms struct memory layout.
//
// Zig Uniforms layout (extern struct with explicit alignments):
//   offset   0: projection_matrix  [4]F32x4     64 bytes  align(16)
//   offset  64: screen_size        [2]f32         8 bytes  align(8)
//   offset  72: cell_size          [2]f32         8 bytes  align(8)
//   offset  80: grid_size          [2]u16         4 bytes  align(4)
//   offset  84: <padding>                         4 bytes  (for grid_padding align(16))
//   offset  96: grid_padding       [4]f32        16 bytes  align(16)
//   offset 112: padding_extend     packed u32     4 bytes  align(4)
//   offset 116: min_contrast       f32            4 bytes  align(4)
//   offset 120: cursor_pos         [2]u16         4 bytes  align(4)
//   offset 124: cursor_color       [4]u8          4 bytes  align(4)
//   offset 128: bg_color           [4]u8          4 bytes  align(4)
//   offset 132: bools              packed u32     4 bytes  align(4)
//   total: 136 bytes, padded to 144 (9 x 16-byte cbuffer registers)
//
// In HLSL cbuffer packing rules:
// - Each register is 16 bytes (4 x 32-bit components)
// - A variable cannot straddle a register boundary
// - float2 = 8 bytes, uint = 4 bytes, float4 = 16 bytes
// - Two float2's pack into one register; two uint's pack into one register half

/// Common cbuffer definition shared by all shaders.
/// Uses packed uint fields to match the Zig layout exactly.
const hlsl_globals_cbuffer =
    \\cbuffer Globals : register(b0)
    \\{
    \\    float4x4 projection_matrix;  // regs 0-3 (offset 0-63)
    \\    float2 screen_size;                    // reg 4.x,y (offset 64-71)
    \\    float2 cell_size;                      // reg 4.z,w (offset 72-79)
    \\    uint grid_size_packed_2u16;            // reg 5.x (offset 80, two u16 packed)
    \\    uint _pad80;                           // reg 5.y (offset 84, padding)
    \\    float4 grid_padding;                   // reg 6 (offset 96, forced to new reg by align(16))
    \\    uint padding_extend;                   // reg 7.x (offset 112)
    \\    float min_contrast;                    // reg 7.y (offset 116)
    \\    uint cursor_pos_packed_2u16;           // reg 7.z (offset 120, two u16 packed)
    \\    uint cursor_color_packed_4u8;          // reg 7.w (offset 124, four u8 packed)
    \\    uint bg_color_packed_4u8;              // reg 8.x (offset 128)
    \\    uint bools;                            // reg 8.y (offset 132)
    \\};
;

/// Common HLSL utility functions for unpacking packed values and color operations.
const hlsl_common_utils =
    \\// Bools masks
    \\#define CURSOR_WIDE         1u
    \\#define USE_DISPLAY_P3     2u
    \\#define USE_LINEAR_BLENDING 4u
    \\#define USE_LINEAR_CORRECTION 8u
    \\
    \\// Padding extend masks
    \\#define EXTEND_LEFT   1u
    \\#define EXTEND_RIGHT  2u
    \\#define EXTEND_UP     4u
    \\#define EXTEND_DOWN   8u
    \\
    \\// Unpack a packed uint into 4 bytes (LSB first, little-endian)
    \\uint4 unpack4u8(uint packed)
    \\{
    \\    return uint4(
    \\        (packed >> 0u) & 0xFFu,
    \\        (packed >> 8u) & 0xFFu,
    \\        (packed >> 16u) & 0xFFu,
    \\        (packed >> 24u) & 0xFFu
    \\    );
    \\}
    \\
    \\// Unpack a packed uint into 2 x u16 (LSB first, little-endian)
    \\uint2 unpack2u16(uint packed)
    \\{
    \\    return uint2(
    \\        (packed >> 0u) & 0xFFFFu,
    \\        (packed >> 16u) & 0xFFFFu
    \\    );
    \\}
    \\
    \\float linearize_channel(float v)
    \\{
    \\    return (v <= 0.04045) ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4);
    \\}
    \\
    \\float4 linearize(float4 srgb)
    \\{
    \\    return float4(linearize_channel(srgb.r), linearize_channel(srgb.g),
    \\                  linearize_channel(srgb.b), srgb.a);
    \\}
    \\
    \\float unlinearize_channel(float v)
    \\{
    \\    return (v <= 0.0031308) ? v * 12.92 : pow(v, 1.0 / 2.4) * 1.055 - 0.055;
    \\}
    \\
    \\float4 unlinearize(float4 lin)
    \\{
    \\    return float4(unlinearize_channel(lin.r), unlinearize_channel(lin.g),
    \\                  unlinearize_channel(lin.b), lin.a);
    \\}
    \\
    \\float luminance(float3 color)
    \\{
    \\    return dot(color, float3(0.2126, 0.7152, 0.0722));
    \\}
    \\
    \\float contrast_ratio_val(float3 c1, float3 c2)
    \\{
    \\    float l1 = luminance(c1) + 0.05;
    \\    float l2 = luminance(c2) + 0.05;
    \\    return max(l1, l2) / min(l1, l2);
    \\}
    \\
    \\float4 contrasted_color(float min_ratio, float4 fg, float4 bg)
    \\{
    \\    float ratio = contrast_ratio_val(fg.rgb, bg.rgb);
    \\    if (ratio < min_ratio) {
    \\        float wr = contrast_ratio_val(float3(1, 1, 1), bg.rgb);
    \\        float br = contrast_ratio_val(float3(0, 0, 0), bg.rgb);
    \\        if (wr > br)
    \\            return float4(1, 1, 1, 1);
    \\        else
    \\            return float4(0, 0, 0, 1);
    \\    }
    \\    return fg;
    \\}
    \\
    \\// Load a 4-byte packed RGBA color, linearize if needed, premultiply
    \\float4 load_color(uint4 in_color, bool linear)
    \\{
    \\    float4 color = float4(in_color.x, in_color.y, in_color.z, in_color.w) / 255.0;
    \\    if (linear)
    \\        color = linearize(color);
    \\    color.rgb *= color.a;
    \\    return color;
    \\}
;

// ============================================================================
// bg_color shaders - full-screen triangle, no vertex input, no blend
// ============================================================================

const bg_color_vs =
    \\// bg_color vertex shader - full-screen triangle
    \\float4 main(uint vid : SV_VertexID) : SV_Position
    \\{
    \\    float x = (vid == 2) ? 3.0 : -1.0;
    \\    float y = (vid == 0) ? -3.0 : 1.0;
    \\    return float4(x, y, 1.0, 1.0);
    \\}
;

const bg_color_ps =
    \\// bg_color pixel shader - solid background color
    \\cbuffer Globals : register(b0)
    \\{
    \\    float4x4 projection_matrix;
    \\    float2 screen_size;
    \\    float2 cell_size;
    \\    uint grid_size_packed_2u16;
    \\    uint _pad80;
    \\    float4 grid_padding;
    \\    uint padding_extend;
    \\    float min_contrast;
    \\    uint cursor_pos_packed_2u16;
    \\    uint cursor_color_packed_4u8;
    \\    uint bg_color_packed_4u8;
    \\    uint bools;
    \\};
    \\
    \\#define USE_LINEAR_BLENDING 4u
    \\
    \\float4 main(float4 pos : SV_Position) : SV_Target
    \\{
    \\    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0;
    \\    uint4 u_bg = uint4(
    \\        (bg_color_packed_4u8 >> 0u) & 0xFFu,
    \\        (bg_color_packed_4u8 >> 8u) & 0xFFu,
    \\        (bg_color_packed_4u8 >> 16u) & 0xFFu,
    \\        (bg_color_packed_4u8 >> 24u) & 0xFFu
    \\    );
    \\    float4 color = float4(u_bg.x, u_bg.y, u_bg.z, u_bg.w) / 255.0;
    \\    if (use_linear_blending) {
    \\        color.r = (color.r <= 0.04045) ? color.r / 12.92 : pow((color.r + 0.055) / 1.055, 2.4);
    \\        color.g = (color.g <= 0.04045) ? color.g / 12.92 : pow((color.g + 0.055) / 1.055, 2.4);
    \\        color.b = (color.b <= 0.04045) ? color.b / 12.92 : pow((color.b + 0.055) / 1.055, 2.4);
    \\    }
    \\    color.rgb *= color.a;
    \\    return color;
    \\}
;

// ============================================================================
// cell_bg shaders - full-screen triangle, blend enabled, SRV buffer
// ============================================================================

const cell_bg_vs =
    \\// cell_bg vertex shader - full-screen triangle
    \\float4 main(uint vid : SV_VertexID) : SV_Position
    \\{
    \\    float x = (vid == 2) ? 3.0 : -1.0;
    \\    float y = (vid == 0) ? -3.0 : 1.0;
    \\    return float4(x, y, 1.0, 1.0);
    \\}
;

const cell_bg_ps =
    \\// cell_bg pixel shader - per-cell background colors from buffer
    \\cbuffer Globals : register(b0)
    \\{
    \\    float4x4 projection_matrix;
    \\    float2 screen_size;
    \\    float2 cell_size;
    \\    uint grid_size_packed_2u16;
    \\    uint _pad80;
    \\    float4 grid_padding;
    \\    uint padding_extend;
    \\    float min_contrast;
    \\    uint cursor_pos_packed_2u16;
    \\    uint cursor_color_packed_4u8;
    \\    uint bg_color_packed_4u8;
    \\    uint bools;
    \\};
    \\
    \\#define USE_LINEAR_BLENDING 4u
    \\#define EXTEND_LEFT   1u
    \\#define EXTEND_RIGHT  2u
    \\#define EXTEND_UP     4u
    \\#define EXTEND_DOWN   8u
    \\
    \\// Cell background colors as a structured buffer (SRV, register t0)
    \\StructuredBuffer<uint> bg_cells : register(t0);
    \\
    \\float linearize_channel(float v)
    \\{
    \\    return (v <= 0.04045) ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4);
    \\}
    \\
    \\float4 main(float4 pos : SV_Position) : SV_Target
    \\{
    \\    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0;
    \\    uint2 grid_size = uint2(
    \\        (grid_size_packed_2u16 >> 0u) & 0xFFFFu,
    \\        (grid_size_packed_2u16 >> 16u) & 0xFFFFu
    \\    );
    \\
    \\    // Compute grid position from pixel position.
    \\    // In D3D11, SV_Position has origin at top-left, y increases downward.
    \\    int grid_x = int(floor((pos.x - grid_padding.x) / cell_size.x));
    \\    int grid_y = int(floor((pos.y - grid_padding.y) / cell_size.y));
    \\
    \\    // Handle padding extend
    \\    if (grid_x < 0) {
    \\        if ((padding_extend & EXTEND_LEFT) != 0)
    \\            grid_x = 0;
    \\        else
    \\            return float4(0, 0, 0, 0);
    \\    } else if (grid_x > int(grid_size.x) - 1) {
    \\        if ((padding_extend & EXTEND_RIGHT) != 0)
    \\            grid_x = int(grid_size.x) - 1;
    \\        else
    \\            return float4(0, 0, 0, 0);
    \\    }
    \\
    \\    if (grid_y < 0) {
    \\        if ((padding_extend & EXTEND_UP) != 0)
    \\            grid_y = 0;
    \\        else
    \\            return float4(0, 0, 0, 0);
    \\    } else if (grid_y > int(grid_size.y) - 1) {
    \\        if ((padding_extend & EXTEND_DOWN) != 0)
    \\            grid_y = int(grid_size.y) - 1;
    \\        else
    \\            return float4(0, 0, 0, 0);
    \\    }
    \\
    \\    uint cell_index = uint(grid_y) * grid_size.x + uint(grid_x);
    \\    uint packed = bg_cells[cell_index];
    \\
    \\    uint4 u_color = uint4(
    \\        (packed >> 0u) & 0xFFu,
    \\        (packed >> 8u) & 0xFFu,
    \\        (packed >> 16u) & 0xFFu,
    \\        (packed >> 24u) & 0xFFu
    \\    );
    \\
    \\    float4 color = float4(u_color.x, u_color.y, u_color.z, u_color.w) / 255.0;
    \\    if (use_linear_blending)
    \\        color = float4(linearize_channel(color.r), linearize_channel(color.g),
    \\                       linearize_channel(color.b), color.a);
    \\    color.rgb *= color.a;
    \\
    \\    return color;
    \\}
;

// ============================================================================
// cell_text shaders - instanced rendering, per-instance vertex input, blend
// ============================================================================

const cell_text_vs =
    \\// cell_text vertex shader - instanced quad per glyph
    \\cbuffer Globals : register(b0)
    \\{
    \\    float4x4 projection_matrix;
    \\    float2 screen_size;
    \\    float2 cell_size;
    \\    uint grid_size_packed_2u16;
    \\    uint _pad80;
    \\    float4 grid_padding;
    \\    uint padding_extend;
    \\    float min_contrast;
    \\    uint cursor_pos_packed_2u16;
    \\    uint cursor_color_packed_4u8;
    \\    uint bg_color_packed_4u8;
    \\    uint bools;
    \\};
    \\
    \\#define CURSOR_WIDE 1u
    \\#define USE_LINEAR_BLENDING 4u
    \\#define NO_MIN_CONTRAST 1u
    \\#define IS_CURSOR_GLYPH 2u
    \\#define ATLAS_GRAYSCALE 0u
    \\#define ATLAS_COLOR 1u
    \\
    \\StructuredBuffer<uint> bg_cells : register(t2);
    \\
    \\float linearize_channel(float v)
    \\{
    \\    return (v <= 0.04045) ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4);
    \\}
    \\
    \\float4 linearize(float4 srgb)
    \\{
    \\    return float4(linearize_channel(srgb.r), linearize_channel(srgb.g),
    \\                  linearize_channel(srgb.b), srgb.a);
    \\}
    \\
    \\float luminance(float3 color)
    \\{
    \\    return dot(color, float3(0.2126, 0.7152, 0.0722));
    \\}
    \\
    \\float contrast_ratio_val(float3 c1, float3 c2)
    \\{
    \\    float l1 = luminance(c1) + 0.05;
    \\    float l2 = luminance(c2) + 0.05;
    \\    return max(l1, l2) / min(l1, l2);
    \\}
    \\
    \\float4 contrasted_color(float min_ratio, float4 fg, float4 bg)
    \\{
    \\    float ratio = contrast_ratio_val(fg.rgb, bg.rgb);
    \\    if (ratio < min_ratio) {
    \\        float wr = contrast_ratio_val(float3(1, 1, 1), bg.rgb);
    \\        float br = contrast_ratio_val(float3(0, 0, 0), bg.rgb);
    \\        if (wr > br)
    \\            return float4(1, 1, 1, 1);
    \\        else
    \\            return float4(0, 0, 0, 1);
    \\    }
    \\    return fg;
    \\}
    \\
    \\// Per-instance input from input assembler
    \\struct VS_INPUT
    \\{
    \\    uint2 glyph_pos   : TEXCOORD0;
    \\    uint2 glyph_size  : TEXCOORD1;
    \\    int2  bearings    : TEXCOORD2;
    \\    uint2 grid_pos    : TEXCOORD3;
    \\    uint4 color       : COLOR0;
    \\    uint2 atlas_and_bools : TEXCOORD4; // x=atlas, y=bools
    \\};
    \\
    \\struct VS_OUTPUT
    \\{
    \\    float4 position  : SV_Position;
    \\    uint   atlas     : TEXCOORD0;
    \\    float4 color     : TEXCOORD1;
    \\    float4 bg_col    : TEXCOORD2;
    \\    float2 tex_coord : TEXCOORD3;
    \\};
    \\
    \\VS_OUTPUT main(VS_INPUT input, uint vid : SV_VertexID)
    \\{
    \\    VS_OUTPUT output;
    \\
    \\    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0;
    \\    bool cursor_wide = (bools & CURSOR_WIDE) != 0;
    \\    uint2 grid_size = uint2(
    \\        (grid_size_packed_2u16 >> 0u) & 0xFFFFu,
    \\        (grid_size_packed_2u16 >> 16u) & 0xFFFFu
    \\    );
    \\    uint2 cursor_pos = uint2(
    \\        (cursor_pos_packed_2u16 >> 0u) & 0xFFFFu,
    \\        (cursor_pos_packed_2u16 >> 16u) & 0xFFFFu
    \\    );
    \\
    \\    // Compute cell position from grid coords
    \\    float2 cell_pos = cell_size * float2(input.grid_pos.x, input.grid_pos.y);
    \\
    \\    // Determine corner from vertex ID (triangle strip, 4 vertices)
    \\    float2 corner;
    \\    corner.x = float(vid == 1 || vid == 3);
    \\    corner.y = float(vid == 2 || vid == 3);
    \\
    \\    // Compute offset and size
    \\    float2 size = float2(input.glyph_size.x, input.glyph_size.y);
    \\    float2 offset = float2(input.bearings.x, input.bearings.y);
    \\    offset.y = cell_size.y - offset.y;
    \\
    \\    // Final position
    \\    cell_pos = cell_pos + size * corner + offset;
    \\    output.position = mul(projection_matrix, float4(cell_pos, 0.0, 1.0));
    \\
    \\    // Texture coordinate in pixels (not normalized)
    \\    output.tex_coord = float2(input.glyph_pos.x, input.glyph_pos.y) + float2(input.glyph_size.x, input.glyph_size.y) * corner;
    \\
    \\    uint atlas = input.atlas_and_bools.x;
    \\    uint glyph_bools = input.atlas_and_bools.y;
    \\    output.atlas = atlas;
    \\
    \\    // Load foreground color (always linearized)
    \\    float4 color = float4(input.color.x, input.color.y, input.color.z, input.color.w) / 255.0;
    \\    color = linearize(color);
    \\    color.rgb *= color.a;
    \\    output.color = color;
    \\
    \\    // Load background color from the bg_cells buffer
    \\    uint cell_index = input.grid_pos.y * grid_size.x + input.grid_pos.x;
    \\    uint packed_bg = bg_cells[cell_index];
    \\    uint4 u_bg = uint4(
    \\        (packed_bg >> 0u) & 0xFFu,
    \\        (packed_bg >> 8u) & 0xFFu,
    \\        (packed_bg >> 16u) & 0xFFu,
    \\        (packed_bg >> 24u) & 0xFFu
    \\    );
    \\    float4 cell_bg_col = float4(u_bg.x, u_bg.y, u_bg.z, u_bg.w) / 255.0;
    \\    cell_bg_col = linearize(cell_bg_col);
    \\    cell_bg_col.rgb *= cell_bg_col.a;
    \\
    \\    // Blend with global bg color
    \\    uint4 u_global_bg = uint4(
    \\        (bg_color_packed_4u8 >> 0u) & 0xFFu,
    \\        (bg_color_packed_4u8 >> 8u) & 0xFFu,
    \\        (bg_color_packed_4u8 >> 16u) & 0xFFu,
    \\        (bg_color_packed_4u8 >> 24u) & 0xFFu
    \\    );
    \\    float4 global_bg = float4(u_global_bg.x, u_global_bg.y, u_global_bg.z, u_global_bg.w) / 255.0;
    \\    global_bg = linearize(global_bg);
    \\    global_bg.rgb *= global_bg.a;
    \\
    \\    cell_bg_col = cell_bg_col + global_bg * (1.0 - cell_bg_col.a);
    \\    output.bg_col = cell_bg_col;
    \\
    \\    // Minimum contrast check
    \\    if (min_contrast > 1.0 && (glyph_bools & NO_MIN_CONTRAST) == 0) {
    \\        output.color = contrasted_color(min_contrast, output.color, output.bg_col);
    \\    }
    \\
    \\    // Cursor color check
    \\    bool is_cursor_pos = ((input.grid_pos.x == cursor_pos.x) ||
    \\        (cursor_wide && (input.grid_pos.x == (cursor_pos.x + 1)))) &&
    \\        (input.grid_pos.y == cursor_pos.y);
    \\    if ((glyph_bools & IS_CURSOR_GLYPH) == 0 && is_cursor_pos) {
    \\        uint4 u_cursor = uint4(
    \\            (cursor_color_packed_4u8 >> 0u) & 0xFFu,
    \\            (cursor_color_packed_4u8 >> 8u) & 0xFFu,
    \\            (cursor_color_packed_4u8 >> 16u) & 0xFFu,
    \\            (cursor_color_packed_4u8 >> 24u) & 0xFFu
    \\        );
    \\        float4 cursor_col = float4(u_cursor.x, u_cursor.y, u_cursor.z, u_cursor.w) / 255.0;
    \\        if (use_linear_blending)
    \\            cursor_col = linearize(cursor_col);
    \\        cursor_col.rgb *= cursor_col.a;
    \\        output.color = cursor_col;
    \\    }
    \\
    \\    return output;
    \\}
;

const cell_text_ps =
    \\// cell_text pixel shader - sample from atlas textures
    \\cbuffer Globals : register(b0)
    \\{
    \\    float4x4 projection_matrix;
    \\    float2 screen_size;
    \\    float2 cell_size;
    \\    uint grid_size_packed_2u16;
    \\    uint _pad80;
    \\    float4 grid_padding;
    \\    uint padding_extend;
    \\    float min_contrast;
    \\    uint cursor_pos_packed_2u16;
    \\    uint cursor_color_packed_4u8;
    \\    uint bg_color_packed_4u8;
    \\    uint bools;
    \\};
    \\
    \\#define USE_LINEAR_BLENDING 4u
    \\#define USE_LINEAR_CORRECTION 8u
    \\#define ATLAS_GRAYSCALE 0u
    \\#define ATLAS_COLOR 1u
    \\
    \\Texture2D<float>   atlas_grayscale : register(t0);
    \\Texture2D<float4>  atlas_color     : register(t1);
    \\SamplerState       atlas_sampler   : register(s0);
    \\
    \\float unlinearize_channel(float v)
    \\{
    \\    return (v <= 0.0031308) ? v * 12.92 : pow(v, 1.0 / 2.4) * 1.055 - 0.055;
    \\}
    \\
    \\float luminance(float3 color)
    \\{
    \\    return dot(color, float3(0.2126, 0.7152, 0.0722));
    \\}
    \\
    \\float linearize_channel(float v)
    \\{
    \\    return (v <= 0.04045) ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4);
    \\}
    \\
    \\struct PS_INPUT
    \\{
    \\    float4 position  : SV_Position;
    \\    uint   atlas     : TEXCOORD0;
    \\    float4 color     : TEXCOORD1;
    \\    float4 bg_col    : TEXCOORD2;
    \\    float2 tex_coord : TEXCOORD3;
    \\};
    \\
    \\float4 main(PS_INPUT input) : SV_Target
    \\{
    \\    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0;
    \\    bool use_linear_correction = (bools & USE_LINEAR_CORRECTION) != 0;
    \\
    \\    if (input.atlas == ATLAS_COLOR) {
    \\        // Color atlas - sample with normalized coordinates
    \\        uint2 ts;
    \\        atlas_color.GetDimensions(ts.x, ts.y);
    \\        float2 norm_tc = input.tex_coord / float2(ts.x, ts.y);
    \\        float4 color = atlas_color.Sample(atlas_sampler, norm_tc);
    \\        // Color emoji: data is already premultiplied sRGB BGRA, return directly
    \\        return color;
    \\    }
    \\
    \\    // Grayscale atlas
    \\    {
    \\        float4 color = input.color;
    \\
    \\        if (!use_linear_blending) {
    \\            if (color.a > 0.0) {
    \\                color.rgb /= color.a;
    \\                color = float4(unlinearize_channel(color.r), unlinearize_channel(color.g),
    \\                               unlinearize_channel(color.b), color.a);
    \\                color.rgb *= color.a;
    \\            }
    \\        }
    \\
    \\        // Fetch alpha mask (normalized coordinates)
    \\        uint2 ts;
    \\        atlas_grayscale.GetDimensions(ts.x, ts.y);
    \\        float2 norm_tc = input.tex_coord / float2(ts.x, ts.y);
    \\        float a = atlas_grayscale.Sample(atlas_sampler, norm_tc);
    \\
    \\        // Linear blending weight correction
    \\        if (use_linear_correction) {
    \\            float4 bg = input.bg_col;
    \\            float fg_l = luminance(color.rgb);
    \\            float bg_l = luminance(bg.rgb);
    \\            if (abs(fg_l - bg_l) > 0.001) {
    \\                float blend_l = linearize_channel(unlinearize_channel(fg_l) * a + unlinearize_channel(bg_l) * (1.0 - a));
    \\                a = clamp((blend_l - bg_l) / (fg_l - bg_l), 0.0, 1.0);
    \\            }
    \\        }
    \\
    \\        color *= a;
    \\        return color;
    \\    }
    \\}
;

// ============================================================================
// image shaders - instanced rendering, per-instance vertex input, blend
// ============================================================================

const image_vs =
    \\// image vertex shader - instanced quad per image
    \\cbuffer Globals : register(b0)
    \\{
    \\    float4x4 projection_matrix;
    \\    float2 screen_size;
    \\    float2 cell_size;
    \\    uint grid_size_packed_2u16;
    \\    uint _pad80;
    \\    float4 grid_padding;
    \\    uint padding_extend;
    \\    float min_contrast;
    \\    uint cursor_pos_packed_2u16;
    \\    uint cursor_color_packed_4u8;
    \\    uint bg_color_packed_4u8;
    \\    uint bools;
    \\};
    \\
    \\Texture2D<float4> image_tex : register(t0);
    \\SamplerState image_sampler : register(s0);
    \\
    \\struct VS_INPUT
    \\{
    \\    float2 grid_pos     : POSITION0;
    \\    float2 cell_offset  : TEXCOORD0;
    \\    float4 source_rect  : TEXCOORD1;
    \\    float2 dest_size    : TEXCOORD2;
    \\};
    \\
    \\struct VS_OUTPUT
    \\{
    \\    float4 position  : SV_Position;
    \\    float2 tex_coord : TEXCOORD0;
    \\};
    \\
    \\VS_OUTPUT main(VS_INPUT input, uint vid : SV_VertexID)
    \\{
    \\    VS_OUTPUT output;
    \\
    \\    // Corner from vertex ID (triangle strip, 4 vertices)
    \\    float2 corner;
    \\    corner.x = float(vid == 1 || vid == 3);
    \\    corner.y = float(vid == 2 || vid == 3);
    \\
    \\    // Texture coordinates
    \\    output.tex_coord = input.source_rect.xy + input.source_rect.zw * corner;
    \\
    \\    // Normalize texture coordinates
    \\    uint2 tex_size;
    \\    image_tex.GetDimensions(tex_size.x, tex_size.y);
    \\    output.tex_coord /= float2(tex_size.x, tex_size.y);
    \\
    \\    // Position
    \\    float2 image_pos = cell_size * input.grid_pos + input.cell_offset;
    \\    image_pos += input.dest_size * corner;
    \\    output.position = mul(projection_matrix, float4(image_pos, 1.0, 1.0));
    \\
    \\    return output;
    \\}
;

const image_ps =
    \\// image pixel shader - sample image texture
    \\cbuffer Globals : register(b0)
    \\{
    \\    float4x4 projection_matrix;
    \\    float2 screen_size;
    \\    float2 cell_size;
    \\    uint grid_size_packed_2u16;
    \\    uint _pad80;
    \\    float4 grid_padding;
    \\    uint padding_extend;
    \\    float min_contrast;
    \\    uint cursor_pos_packed_2u16;
    \\    uint cursor_color_packed_4u8;
    \\    uint bg_color_packed_4u8;
    \\    uint bools;
    \\};
    \\
    \\#define USE_LINEAR_BLENDING 4u
    \\
    \\Texture2D<float4> image_tex : register(t0);
    \\SamplerState image_sampler : register(s0);
    \\
    \\float unlinearize_channel(float v)
    \\{
    \\    return (v <= 0.0031308) ? v * 12.92 : pow(v, 1.0 / 2.4) * 1.055 - 0.055;
    \\}
    \\
    \\struct PS_INPUT
    \\{
    \\    float4 position  : SV_Position;
    \\    float2 tex_coord : TEXCOORD0;
    \\};
    \\
    \\float4 main(PS_INPUT input) : SV_Target
    \\{
    \\    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0;
    \\
    \\    float4 rgba = image_tex.Sample(image_sampler, input.tex_coord);
    \\
    \\    if (!use_linear_blending) {
    \\        rgba = float4(unlinearize_channel(rgba.r), unlinearize_channel(rgba.g),
    \\                      unlinearize_channel(rgba.b), rgba.a);
    \\    }
    \\
    \\    rgba.rgb *= rgba.a;
    \\
    \\    return rgba;
    \\}
;

// ============================================================================
// bg_image shaders - full-screen triangle with per-instance data, blend
// ============================================================================

const bg_image_vs =
    \\// bg_image vertex shader - full-screen triangle with per-instance data
    \\cbuffer Globals : register(b0)
    \\{
    \\    float4x4 projection_matrix;
    \\    float2 screen_size;
    \\    float2 cell_size;
    \\    uint grid_size_packed_2u16;
    \\    uint _pad80;
    \\    float4 grid_padding;
    \\    uint padding_extend;
    \\    float min_contrast;
    \\    uint cursor_pos_packed_2u16;
    \\    uint cursor_color_packed_4u8;
    \\    uint bg_color_packed_4u8;
    \\    uint bools;
    \\};
    \\
    \\#define USE_LINEAR_BLENDING 4u
    \\
    \\#define BG_IMAGE_POSITION 15u
    \\#define BG_IMAGE_TL 0u
    \\#define BG_IMAGE_TC 1u
    \\#define BG_IMAGE_TR 2u
    \\#define BG_IMAGE_ML 3u
    \\#define BG_IMAGE_MC 4u
    \\#define BG_IMAGE_MR 5u
    \\#define BG_IMAGE_BL 6u
    \\#define BG_IMAGE_BC 7u
    \\#define BG_IMAGE_BR 8u
    \\
    \\#define BG_IMAGE_FIT   (3u << 4u)
    \\#define BG_IMAGE_CONTAIN (0u << 4u)
    \\#define BG_IMAGE_COVER   (1u << 4u)
    \\#define BG_IMAGE_STRETCH (2u << 4u)
    \\#define BG_IMAGE_NO_FIT  (3u << 4u)
    \\
    \\#define BG_IMAGE_REPEAT (1u << 6u)
    \\
    \\Texture2D<float4> image_tex : register(t0);
    \\SamplerState image_sampler : register(s0);
    \\
    \\float linearize_channel(float v)
    \\{
    \\    return (v <= 0.04045) ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4);
    \\}
    \\
    \\struct VS_INPUT
    \\{
    \\    float in_opacity : TEXCOORD0;
    \\    uint  in_info    : TEXCOORD1;
    \\};
    \\
    \\struct VS_OUTPUT
    \\{
    \\    float4 position  : SV_Position;
    \\    float4 bg_col    : TEXCOORD0;
    \\    float2 offset    : TEXCOORD1;
    \\    float2 scale     : TEXCOORD2;
    \\    float  opacity   : TEXCOORD3;
    \\    uint   repeat    : TEXCOORD4;
    \\};
    \\
    \\VS_OUTPUT main(VS_INPUT input, uint vid : SV_VertexID)
    \\{
    \\    VS_OUTPUT output;
    \\    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0;
    \\
    \\    // Full-screen triangle
    \\    float x = (vid == 2) ? 3.0 : -1.0;
    \\    float y = (vid == 0) ? -3.0 : 1.0;
    \\    output.position = float4(x, y, 1.0, 1.0);
    \\
    \\    output.opacity = input.in_opacity;
    \\    output.repeat = input.in_info & BG_IMAGE_REPEAT;
    \\
    \\    // Get texture size
    \\    uint2 tex_size;
    \\    image_tex.GetDimensions(tex_size.x, tex_size.y);
    \\    float2 tex_size_f = float2(tex_size.x, tex_size.y);
    \\
    \\    // Determine destination size based on fit mode
    \\    float2 dest_size = tex_size_f;
    \\    uint fit = input.in_info & BG_IMAGE_FIT;
    \\    if (fit == BG_IMAGE_CONTAIN) {
    \\        float s = min(screen_size.x / tex_size_f.x, screen_size.y / tex_size_f.y);
    \\        dest_size = tex_size_f * s;
    \\    } else if (fit == BG_IMAGE_COVER) {
    \\        float s = max(screen_size.x / tex_size_f.x, screen_size.y / tex_size_f.y);
    \\        dest_size = tex_size_f * s;
    \\    } else if (fit == BG_IMAGE_STRETCH) {
    \\        dest_size = screen_size;
    \\    }
    \\    // else BG_IMAGE_NO_FIT: dest_size = tex_size_f (already set)
    \\
    \\    // Determine offset based on position
    \\    float2 start = float2(0.0, 0.0);
    \\    float2 mid = (screen_size - dest_size) / 2.0;
    \\    float2 end = screen_size - dest_size;
    \\
    \\    float2 dest_offset = mid;
    \\    uint pos = input.in_info & BG_IMAGE_POSITION;
    \\    if (pos == BG_IMAGE_TL)      dest_offset = float2(start.x, start.y);
    \\    else if (pos == BG_IMAGE_TC) dest_offset = float2(mid.x, start.y);
    \\    else if (pos == BG_IMAGE_TR) dest_offset = float2(end.x, start.y);
    \\    else if (pos == BG_IMAGE_ML) dest_offset = float2(start.x, mid.y);
    \\    else if (pos == BG_IMAGE_MC) dest_offset = float2(mid.x, mid.y);
    \\    else if (pos == BG_IMAGE_MR) dest_offset = float2(end.x, mid.y);
    \\    else if (pos == BG_IMAGE_BL) dest_offset = float2(start.x, end.y);
    \\    else if (pos == BG_IMAGE_BC) dest_offset = float2(mid.x, end.y);
    \\    else if (pos == BG_IMAGE_BR) dest_offset = float2(end.x, end.y);
    \\
    \\    output.offset = dest_offset;
    \\    output.scale = tex_size_f / dest_size;
    \\
    \\    // Load bg color
    \\    uint4 u_bg = uint4(
    \\        (bg_color_packed_4u8 >> 0u) & 0xFFu,
    \\        (bg_color_packed_4u8 >> 8u) & 0xFFu,
    \\        (bg_color_packed_4u8 >> 16u) & 0xFFu,
    \\        (bg_color_packed_4u8 >> 24u) & 0xFFu
    \\    );
    \\    float4 bg_col = float4(u_bg.x, u_bg.y, u_bg.z, u_bg.w) / 255.0;
    \\    if (use_linear_blending)
    \\        bg_col = float4(linearize_channel(bg_col.r), linearize_channel(bg_col.g),
    \\                         linearize_channel(bg_col.b), bg_col.a);
    \\    bg_col.rgb *= bg_col.a;
    \\    // Use fully opaque bg color with separate alpha
    \\    output.bg_col = float4(bg_col.rgb, float(u_bg.a) / 255.0);
    \\
    \\    return output;
    \\}
;

const bg_image_ps =
    \\// bg_image pixel shader - sample background image
    \\cbuffer Globals : register(b0)
    \\{
    \\    float4x4 projection_matrix;
    \\    float2 screen_size;
    \\    float2 cell_size;
    \\    uint grid_size_packed_2u16;
    \\    uint _pad80;
    \\    float4 grid_padding;
    \\    uint padding_extend;
    \\    float min_contrast;
    \\    uint cursor_pos_packed_2u16;
    \\    uint cursor_color_packed_4u8;
    \\    uint bg_color_packed_4u8;
    \\    uint bools;
    \\};
    \\
    \\#define USE_LINEAR_BLENDING 4u
    \\
    \\Texture2D<float4> image_tex : register(t0);
    \\SamplerState image_sampler : register(s0);
    \\
    \\float unlinearize_channel(float v)
    \\{
    \\    return (v <= 0.0031308) ? v * 12.92 : pow(v, 1.0 / 2.4) * 1.055 - 0.055;
    \\}
    \\
    \\struct PS_INPUT
    \\{
    \\    float4 position  : SV_Position;
    \\    float4 bg_col    : TEXCOORD0;
    \\    float2 offset    : TEXCOORD1;
    \\    float2 scale     : TEXCOORD2;
    \\    float  opacity   : TEXCOORD3;
    \\    uint   repeat    : TEXCOORD4;
    \\};
    \\
    \\float4 main(PS_INPUT input) : SV_Target
    \\{
    \\    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0;
    \\
    \\    // Compute texture coordinate from screen position
    \\    float2 tex_coord = (input.position.xy - input.offset) * input.scale;
    \\
    \\    uint2 tex_size;
    \\    image_tex.GetDimensions(tex_size.x, tex_size.y);
    \\    float2 tex_size_f = float2(tex_size.x, tex_size.y);
    \\
    \\    // Handle repeat
    \\    if (input.repeat != 0u) {
    \\        tex_coord = fmod(fmod(tex_coord, tex_size_f) + tex_size_f, tex_size_f);
    \\    }
    \\
    \\    float4 rgba;
    \\    // Out of bounds check
    \\    if (tex_coord.x < 0.0 || tex_coord.y < 0.0 ||
    \\        tex_coord.x >= tex_size_f.x || tex_coord.y >= tex_size_f.y)
    \\    {
    \\        rgba = float4(0, 0, 0, 0);
    \\    } else {
    \\        rgba = image_tex.Sample(image_sampler, tex_coord / tex_size_f);
    \\        if (!use_linear_blending) {
    \\            rgba = float4(unlinearize_channel(rgba.r), unlinearize_channel(rgba.g),
    \\                          unlinearize_channel(rgba.b), rgba.a);
    \\        }
    \\        rgba.rgb *= rgba.a;
    \\    }
    \\
    \\    // Multiply by opacity, capped at 1.0 / bg_color.a
    \\    rgba *= min(input.opacity, 1.0 / input.bg_col.a);
    \\
    \\    // Blend onto fully opaque version of bg color
    \\    rgba += max(float4(0, 0, 0, 0), float4(input.bg_col.rgb, 1.0) * (1.0 - rgba.a));
    \\
    \\    // Multiply by bg color alpha
    \\    rgba *= input.bg_col.a;
    \\
    \\    return rgba;
    \\}
;
