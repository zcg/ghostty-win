//! D3D11/DXGI COM interface declarations for Zig.
//!
//! This file provides Zig bindings for the Direct3D 11 and DXGI APIs needed
//! by the D3D11 renderer backend. COM interfaces are declared using extern
//! structs with vtable pointer fields.

const std = @import("std");

pub const HRESULT = i32;
pub const S_OK: HRESULT = 0;
pub const S_FALSE: HRESULT = 1;
pub const E_FAIL: HRESULT = @bitCast(@as(u32, 0x80004005));
pub const E_INVALIDARG: HRESULT = @bitCast(@as(u32, 0x80070057));
pub const E_OUTOFMEMORY: HRESULT = @bitCast(@as(u32, 0x8007000E));
pub const DXGI_ERROR_INVALID_CALL: HRESULT = @bitCast(@as(u32, 0x887A0001));
pub const DXGI_ERROR_DEVICE_REMOVED: HRESULT = @bitCast(@as(u32, 0x887A0005));
pub const DXGI_ERROR_DEVICE_RESET: HRESULT = @bitCast(@as(u32, 0x887A0007));
pub const DXGI_ERROR_WAS_STILL_DRAWING: HRESULT = @bitCast(@as(u32, 0x887A000A));

pub const BOOL = c_int;
pub const TRUE: BOOL = 1;
pub const FALSE: BOOL = 0;

pub const UINT = c_uint;
pub const INT = c_int;
pub const DWORD = c_ulong;
pub const FLOAT = f32;
pub const SIZE_T = usize;
pub const LARGE_INTEGER = i64;
pub const LPCWSTR = [*:0]const u16;
pub const HANDLE = ?*anyopaque;
pub const HWND = ?*anyopaque;
pub const HMODULE = ?*anyopaque;
pub const REFGUID = *const GUID;

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
// DXGI Format
// ============================================================================

pub const DXGI_FORMAT = enum(c_uint) {
    unknown = 0,
    r32g32b32a32_typeless = 1,
    r32g32b32a32_float = 2,
    r32g32b32a32_uint = 3,
    r32g32b32a32_sint = 4,
    r32g32b32_typeless = 5,
    r32g32b32_float = 6,
    r32g32b32_uint = 7,
    r32g32b32_sint = 8,
    r16g16b16a16_typeless = 9,
    r16g16b16a16_float = 10,
    r16g16b16a16_unorm = 11,
    r16g16b16a16_uint = 12,
    r16g16b16a16_snorm = 13,
    r16g16b16a16_sint = 14,
    r32g32_typeless = 15,
    r32g32_float = 16,
    r32g32_uint = 17,
    r32g32_sint = 18,
    r32g8x24_typeless = 19,
    d32_float_s8x24_uint = 20,
    r32_float_x8x24_typeless = 21,
    x32_typeless_g8x24_uint = 22,
    r10g10b10a2_typeless = 23,
    r10g10b10a2_unorm = 24,
    r10g10b10a2_uint = 25,
    r11g11b10_float = 26,
    r8g8b8a8_typeless = 27,
    r8g8b8a8_unorm = 28,
    r8g8b8a8_unorm_srgb = 29,
    r8g8b8a8_uint = 30,
    r8g8b8a8_snorm = 31,
    r8g8b8a8_sint = 32,
    r16g16_typeless = 33,
    r16g16_float = 34,
    r16g16_unorm = 35,
    r16g16_uint = 36,
    r16g16_snorm = 37,
    r16g16_sint = 38,
    r32_typeless = 39,
    d32_float = 40,
    r32_float = 41,
    r32_uint = 42,
    r32_sint = 43,
    r24g8_typeless = 44,
    d24_unorm_s8_uint = 45,
    r24_unorm_x8_typeless = 46,
    x24_typeless_g8_uint = 47,
    r8g8_typeless = 48,
    r8g8_unorm = 49,
    r8g8_uint = 50,
    r8g8_snorm = 51,
    r8g8_sint = 52,
    r16_typeless = 53,
    r16_float = 54,
    d16_unorm = 55,
    r16_unorm = 56,
    r16_uint = 57,
    r16_snorm = 58,
    r16_sint = 59,
    r8_typeless = 60,
    r8_unorm = 61,
    r8_uint = 62,
    r8_snorm = 63,
    r8_sint = 64,
    a8_unorm = 65,
    r1_unorm = 66,
    r9g9b9e5_sharedexp = 67,
    r8g8_b8g8_unorm = 68,
    g8r8_g8b8_unorm = 69,
    bc1_typeless = 70,
    bc1_unorm = 71,
    bc1_unorm_srgb = 72,
    bc2_typeless = 73,
    bc2_unorm = 74,
    bc2_unorm_srgb = 75,
    bc3_typeless = 76,
    bc3_unorm = 77,
    bc3_unorm_srgb = 78,
    bc4_typeless = 79,
    bc4_unorm = 80,
    bc4_snorm = 81,
    bc5_typeless = 82,
    bc5_unorm = 83,
    bc5_snorm = 84,
    b5g6r5_unorm = 85,
    b5g5r5a1_unorm = 86,
    b8g8r8a8_unorm = 87,
    b8g8r8x8_unorm = 88,
    r10g10b10_xr_bias_a2_unorm = 89,
    b8g8r8a8_typeless = 90,
    b8g8r8a8_unorm_srgb = 91,
    b8g8r8x8_typeless = 92,
    b8g8r8x8_unorm_srgb = 93,
    bc6h_typeless = 94,
    bc6h_uf16 = 95,
    bc6h_sf16 = 96,
    bc7_typeless = 97,
    bc7_unorm = 98,
    bc7_unorm_srgb = 99,
    ayuv = 100,
    y410 = 101,
    y416 = 102,
    nv12 = 103,
    p010 = 104,
    p016 = 105,
    y210 = 106,
    y216 = 107,
    nv11 = 108,
    p208 = 109,
    v208 = 110,
    v408 = 111,
    //_ENUM_TYPE_FORCE_UINT = 0xFFFFFFFF,
};

// ============================================================================
// DXGI Swap Chain
// ============================================================================

pub const DXGI_SWAP_EFFECT = enum(c_uint) {
    discard = 0,
    sequential = 1,
    flip_sequential = 3,
    flip_discard = 4,
};

pub const DXGI_ALPHA_MODE = enum(c_uint) {
    unspecified = 0,
    premultiplied = 1,
    straight = 2,
    ignore = 3,
};

pub const DXGI_SWAP_CHAIN_FLAG = packed struct(c_uint) {
    non_prerotated: bool = false,
    allow_mode_switch: bool = false,
    gdi_compatible: bool = false,
    _pad3: u1 = 0,
    _pad4: u1 = 0,
    _pad5: u1 = 0,
    display_only: bool = false,
    _pad7: u1 = 0,
    _pad8: u1 = 0,
    _pad9: u1 = 0,
    _pad10: u1 = 0,
    _pad11: u1 = 0,
    _pad12: u1 = 0,
    _pad13: u1 = 0,
    _pad14: u1 = 0,
    _pad15: u1 = 0,
    _pad16: u1 = 0,
    _pad17: u1 = 0,
    _pad18: u1 = 0,
    _pad19: u1 = 0,
    _pad20: u1 = 0,
    _pad21: u1 = 0,
    _pad22: u1 = 0,
    _pad23: u1 = 0,
    allow_tearing: bool = false,
    _pad25: u1 = 0,
    _pad26: u1 = 0,
    _pad27: u1 = 0,
    _pad28: u1 = 0,
    _pad29: u1 = 0,
    _pad30: u1 = 0,
    _pad31: u1 = 0,
};

pub const DXGI_SWAP_CHAIN_DESC1 = extern struct {
    width: UINT,
    height: UINT,
    format: DXGI_FORMAT,
    stereo: BOOL,
    sample_desc: DXGI_SAMPLE_DESC,
    buffer_usage: DXGI_USAGE,
    buffer_count: UINT,
    scaling: DXGI_SCALING,
    swap_effect: DXGI_SWAP_EFFECT,
    alpha_mode: DXGI_ALPHA_MODE,
    flags: UINT,
};

pub const DXGI_SAMPLE_DESC = extern struct {
    count: UINT,
    quality: UINT,
};

pub const DXGI_USAGE = UINT;
pub const DXGI_USAGE_SHADER_INPUT: DXGI_USAGE = 1 << 4;
pub const DXGI_USAGE_RENDER_TARGET_OUTPUT: DXGI_USAGE = 1 << 5;
pub const DXGI_USAGE_BACK_BUFFER: DXGI_USAGE = 1 << 6;
pub const DXGI_USAGE_SHARED: DXGI_USAGE = 1 << 7;
pub const DXGI_USAGE_READ_ONLY: DXGI_USAGE = 1 << 8;
pub const DXGI_USAGE_DISCARD_ON_PRESENT: DXGI_USAGE = 1 << 9;
pub const DXGI_USAGE_UNORDERED_ACCESS: DXGI_USAGE = 1 << 10;

pub const DXGI_SCALING = enum(c_uint) {
    stretch = 0,
    none = 1,
    aspect_ratio_stretch = 2,
};

pub const DXGI_PRESENT_FLAGS = UINT;
pub const DXGI_PRESENT_TEST: DXGI_PRESENT_FLAGS = 0x00000001;
pub const DXGI_PRESENT_ALLOW_TEARING: DXGI_PRESENT_FLAGS = 512;

pub const DXGI_SWAP_CHAIN_FULLSCREEN_DESC = extern struct {
    refresh_rate: DXGI_RATIONAL,
    scanline_ordering: DXGI_MODE_SCANLINE_ORDER,
    scaling: DXGI_MODE_SCALING,
    windowed: BOOL,
};

pub const DXGI_RATIONAL = extern struct {
    numerator: UINT,
    denominator: UINT,
};

pub const DXGI_MODE_SCANLINE_ORDER = enum(c_uint) {
    unspecified = 0,
    progressive = 1,
    upper_field_first = 2,
    lower_field_first = 3,
};

pub const DXGI_MODE_SCALING = enum(c_uint) {
    unspecified = 0,
    centered = 1,
    stretched = 2,
};

// ============================================================================
// D3D11 Enums
// ============================================================================

pub const D3D_DRIVER_TYPE = enum(c_uint) {
    unknown = 0,
    hardware = 1,
    reference = 2,
    null = 3,
    software = 4,
    warp = 5,
};

pub const D3D11_CREATE_DEVICE_FLAG = packed struct(c_uint) {
    singlethreaded: bool = false,
    debug: bool = false,
    switch_to_ref: bool = false,
    prevent_internal_threading_optimizations: bool = false,
    bgg_support: bool = false,
    prevent_altering_layer_settings_from_registry: bool = false,
    _pad6: u1 = 0,
    _pad7: u1 = 0,
    _pad8: u1 = 0,
    _pad9: u1 = 0,
    _pad10: u1 = 0,
    _pad11: u1 = 0,
    _pad12: u1 = 0,
    _pad13: u1 = 0,
    _pad14: u1 = 0,
    _pad15: u1 = 0,
    _pad16: u1 = 0,
    _pad17: u1 = 0,
    _pad18: u1 = 0,
    _pad19: u1 = 0,
    _pad20: u1 = 0,
    _pad21: u1 = 0,
    _pad22: u1 = 0,
    _pad23: u1 = 0,
    _pad24: u1 = 0,
    _pad25: u1 = 0,
    _pad26: u1 = 0,
    _pad27: u1 = 0,
    _pad28: u1 = 0,
    _pad29: u1 = 0,
    _pad30: u1 = 0,
    _pad31: u1 = 0,
};

pub const D3D11_USAGE = enum(c_uint) {
    default = 0,
    immutable = 1,
    dynamic = 2,
    staging = 3,
};

pub const D3D11_BIND_FLAG = packed struct(c_uint) {
    vertex_buffer: bool = false,     // bit 0  = 0x1
    index_buffer: bool = false,      // bit 1  = 0x2
    constant_buffer: bool = false,   // bit 2  = 0x4
    shader_resource: bool = false,   // bit 3  = 0x8
    stream_output: bool = false,     // bit 4  = 0x10
    render_target: bool = false,     // bit 5  = 0x20
    depth_stencil: bool = false,     // bit 6  = 0x40
    unordered_access: bool = false,  // bit 7  = 0x80
    _pad8: u1 = 0,                   // bit 8  (unused gap)
    decoder: bool = false,           // bit 9  = 0x200
    video_encoder: bool = false,     // bit 10 = 0x400
    _pad11: u21 = 0,
};

pub const D3D11_CPU_ACCESS_FLAG = packed struct(c_uint) {
    _pad0: u16 = 0,
    write: bool = false, // bit 16 = 0x10000
    read: bool = false,  // bit 17 = 0x20000
    _pad18: u14 = 0,
};

pub const D3D11_RESOURCE_MISC_FLAG = packed struct(c_uint) {
    generate_mips: bool = false,            // bit 0  = 0x1
    shared: bool = false,                   // bit 1  = 0x2
    texturecube: bool = false,              // bit 2  = 0x4
    _pad3: u1 = 0,                          // bit 3  (unused gap)
    drawindirect_args: bool = false,        // bit 4  = 0x10
    buffer_allow_raw_views: bool = false,   // bit 5  = 0x20
    buffer_structured: bool = false,        // bit 6  = 0x40
    resource_clamp: bool = false,           // bit 7  = 0x80
    shared_keyedmutex: bool = false,        // bit 8  = 0x100
    _pad9: u1 = 0,                          // bit 9  (unused gap)
    gdi_compatible: bool = false,           // bit 10 = 0x200
    _pad11: u1 = 0,                         // bit 11 (unused gap)
    shared_nt_handle: bool = false,         // bit 12 = 0x800 (note: not 0x400)
    _pad13: u1 = 0,
    _pad14: u1 = 0,
    _pad15: u1 = 0,
    _pad16: u1 = 0,
    _pad17: u1 = 0,
    _pad18: u1 = 0,
    _pad19: u1 = 0,
    _pad20: u1 = 0,
    _pad21: u1 = 0,
    _pad22: u1 = 0,
    _pad23: u1 = 0,
    _pad24: u1 = 0,
    _pad25: u1 = 0,
    _pad26: u1 = 0,
    _pad27: u1 = 0,
    _pad28: u1 = 0,
    _pad29: u1 = 0,
    _pad30: u1 = 0,
    _pad31: u1 = 0,
};

pub const D3D11_PRIMITIVE_TOPOLOGY = enum(c_uint) {
    undefined = 0,
    pointlist = 1,
    linelist = 2,
    linestrip = 3,
    trianglelist = 4,
    trianglestrip = 5,
    linelist_adj = 10,
    linestrip_adj = 11,
    trianglelist_adj = 12,
    trianglestrip_adj = 13,
};

pub const D3D11_INPUT_CLASSIFICATION = enum(c_uint) {
    per_vertex_data = 0,
    per_instance_data = 1,
};

pub const D3D11_TEXTURE_ADDRESS_MODE = enum(c_uint) {
    wrap = 1,
    mirror = 2,
    clamp = 3,
    border = 4,
    mirror_once = 5,
};

pub const D3D11_FILTER = enum(c_uint) {
    min_mag_mip_point = 0,
    min_mag_point_mip_linear = 0x1,
    min_point_mag_linear_mip_point = 0x4,
    min_point_mag_mip_linear = 0x5,
    min_linear_mag_mip_point = 0x10,
    min_linear_mag_point_mip_linear = 0x11,
    min_mag_linear_mip_point = 0x14,
    min_mag_mip_linear = 0x15,
    anisotropic = 0x55,
    comparison_min_mag_mip_point = 0x80,
    comparison_min_mag_point_mip_linear = 0x81,
    comparison_min_point_mag_linear_mip_point = 0x84,
    comparison_min_point_mag_mip_linear = 0x85,
    comparison_min_linear_mag_mip_point = 0x90,
    comparison_min_linear_mag_point_mip_linear = 0x91,
    comparison_min_mag_linear_mip_point = 0x94,
    comparison_min_mag_mip_linear = 0x95,
    comparison_anisotropic = 0xd5,
};

pub const D3D11_COMPARISON_FUNC = enum(c_uint) {
    never = 1,
    less = 2,
    equal = 3,
    less_equal = 4,
    greater = 5,
    not_equal = 6,
    greater_equal = 7,
    always = 8,
};

pub const D3D11_FILL_MODE = enum(c_uint) {
    wireframe = 2,
    solid = 3,
};

pub const D3D11_CULL_MODE = enum(c_uint) {
    none = 1,
    front = 2,
    back = 3,
};

pub const D3D11_BLEND = enum(c_uint) {
    zero = 1,
    one = 2,
    src_color = 3,
    inv_src_color = 4,
    src_alpha = 5,
    inv_src_alpha = 6,
    dest_alpha = 7,
    inv_dest_alpha = 8,
    dest_color = 9,
    inv_dest_color = 10,
    src_alpha_sat = 11,
    blend_factor = 14,
    inv_blend_factor = 15,
    src1_color = 16,
    inv_src1_color = 17,
    src1_alpha = 18,
    inv_src1_alpha = 19,
};

pub const D3D11_BLEND_OP = enum(c_uint) {
    add = 1,
    subtract = 2,
    rev_subtract = 3,
    min = 4,
    max = 5,
};

pub const D3D11_COLOR_WRITE_ENABLE = packed struct(c_uint) {
    red: bool = true,
    green: bool = true,
    blue: bool = true,
    alpha: bool = true,
    _pad4: u1 = 0,
    _pad5: u1 = 0,
    _pad6: u1 = 0,
    _pad7: u1 = 0,
    _pad8: u1 = 0,
    _pad9: u1 = 0,
    _pad10: u1 = 0,
    _pad11: u1 = 0,
    _pad12: u1 = 0,
    _pad13: u1 = 0,
    _pad14: u1 = 0,
    _pad15: u1 = 0,
    _pad16: u1 = 0,
    _pad17: u1 = 0,
    _pad18: u1 = 0,
    _pad19: u1 = 0,
    _pad20: u1 = 0,
    _pad21: u1 = 0,
    _pad22: u1 = 0,
    _pad23: u1 = 0,
    _pad24: u1 = 0,
    _pad25: u1 = 0,
    _pad26: u1 = 0,
    _pad27: u1 = 0,
    _pad28: u1 = 0,
    _pad29: u1 = 0,
    _pad30: u1 = 0,
    _pad31: u1 = 0,
};

pub const D3D11_MAP = enum(c_uint) {
    read = 1,
    write = 2,
    read_write = 3,
    write_discard = 4,
    write_no_overwrite = 5,
};

// ============================================================================
// D3D11 Descriptor Structures
// ============================================================================

pub const D3D11_BUFFER_DESC = extern struct {
    byte_width: UINT,
    usage: D3D11_USAGE,
    bind_flags: D3D11_BIND_FLAG,
    cpu_access_flags: D3D11_CPU_ACCESS_FLAG,
    misc_flags: D3D11_RESOURCE_MISC_FLAG,
    structure_byte_stride: UINT,
};

pub const D3D11_TEXTURE2D_DESC = extern struct {
    width: UINT,
    height: UINT,
    mip_levels: UINT,
    array_size: UINT,
    format: DXGI_FORMAT,
    sample_desc: DXGI_SAMPLE_DESC,
    usage: D3D11_USAGE,
    bind_flags: D3D11_BIND_FLAG,
    cpu_access_flags: D3D11_CPU_ACCESS_FLAG,
    misc_flags: D3D11_RESOURCE_MISC_FLAG,
};

pub const D3D11_SAMPLER_DESC = extern struct {
    filter: D3D11_FILTER,
    address_u: D3D11_TEXTURE_ADDRESS_MODE,
    address_v: D3D11_TEXTURE_ADDRESS_MODE,
    address_w: D3D11_TEXTURE_ADDRESS_MODE,
    mip_lod_bias: FLOAT,
    max_anisotropy: UINT,
    comparison_func: D3D11_COMPARISON_FUNC,
    border_color: [4]FLOAT,
    min_lod: FLOAT,
    max_lod: FLOAT,
};

pub const D3D11_RASTERIZER_DESC = extern struct {
    fill_mode: D3D11_FILL_MODE,
    cull_mode: D3D11_CULL_MODE,
    front_counter_clockwise: BOOL,
    depth_bias: c_int,
    depth_bias_clamp: FLOAT,
    slope_scaled_depth_bias: FLOAT,
    depth_clip_enable: BOOL,
    scissor_enable: BOOL,
    multisample_enable: BOOL,
    antialiased_line_enable: BOOL,
};

pub const D3D11_RENDER_TARGET_BLEND_DESC = extern struct {
    blend_enable: BOOL,
    src_blend: D3D11_BLEND,
    dest_blend: D3D11_BLEND,
    blend_op: D3D11_BLEND_OP,
    src_blend_alpha: D3D11_BLEND,
    dest_blend_alpha: D3D11_BLEND,
    blend_op_alpha: D3D11_BLEND_OP,
    render_target_write_enable: D3D11_COLOR_WRITE_ENABLE,
};

pub const D3D11_BLEND_DESC = extern struct {
    alpha_to_coverage_enable: BOOL,
    independent_blend_enable: BOOL,
    render_target: [8]D3D11_RENDER_TARGET_BLEND_DESC,
};

pub const D3D11_VIEWPORT = extern struct {
    top_left_x: FLOAT,
    top_left_y: FLOAT,
    width: FLOAT,
    height: FLOAT,
    min_depth: FLOAT,
    max_depth: FLOAT,
};

pub const D3D11_INPUT_ELEMENT_DESC = extern struct {
    semantic_name: [*:0]const u8,
    semantic_index: UINT,
    format: DXGI_FORMAT,
    input_slot: UINT,
    aligned_byte_offset: UINT,
    input_slot_class: D3D11_INPUT_CLASSIFICATION,
    instance_data_step_rate: UINT,
};

pub const D3D11_SUBRESOURCE_DATA = extern struct {
    p_sys_mem: ?*const anyopaque,
    sys_mem_pitch: UINT,
    sys_mem_slice_pitch: UINT,
};

pub const D3D11_MAPPED_SUBRESOURCE = extern struct {
    pData: ?*anyopaque,
    row_pitch: UINT,
    depth_pitch: UINT,
};

pub const D3D11_DEPTH_STENCIL_DESC = extern struct {
    depth_enable: BOOL,
    depth_write_mask: D3D11_DEPTH_WRITE_MASK,
    depth_func: D3D11_COMPARISON_FUNC,
    stencil_enable: BOOL,
    stencil_read_mask: u8,
    stencil_write_mask: u8,
    front_face: D3D11_DEPTH_STENCILOP_DESC,
    back_face: D3D11_DEPTH_STENCILOP_DESC,
};

pub const D3D11_DEPTH_WRITE_MASK = enum(c_uint) {
    zero = 0,
    all = 1,
};

pub const D3D11_STENCIL_OP = enum(c_uint) {
    keep = 1,
    zero = 2,
    replace = 3,
    incr_sat = 4,
    decr_sat = 5,
    invert = 6,
    incr = 7,
    decr = 8,
};

pub const D3D11_DEPTH_STENCILOP_DESC = extern struct {
    stencil_fail_op: D3D11_STENCIL_OP,
    stencil_depth_fail_op: D3D11_STENCIL_OP,
    stencil_pass_op: D3D11_STENCIL_OP,
    stencil_func: D3D11_COMPARISON_FUNC,
};

pub const D3D11_BUFFER_SRV = extern struct {
    element_offset: UINT = 0,
    element_width: UINT = 0,
};

pub const D3D11_SHADER_RESOURCE_VIEW_DESC = extern struct {
    format: DXGI_FORMAT,
    view_dimension: D3D11_SRV_DIMENSION,
    u: extern union {
        buffer: D3D11_BUFFER_SRV,
        texture2D: D3D11_TEX2D_SRV,
    },
};

pub const D3D11_SRV_DIMENSION = enum(c_uint) {
    unknown = 0,
    buffer = 1,
    texture1d = 2,
    texture1darray = 3,
    texture2d = 4,
    texture2darray = 5,
    texture2dms = 6,
    texture2dmsarray = 7,
    texture3d = 8,
    texturecube = 9,
    texturecubearray = 10,
    bufferex = 11,
};

pub const D3D11_TEX2D_SRV = extern struct {
    most_detailed_mip: UINT,
    mip_levels: UINT,
};

pub const D3D11_RENDER_TARGET_VIEW_DESC = extern struct {
    format: DXGI_FORMAT,
    view_dimension: D3D11_RTV_DIMENSION,
    texture2D: D3D11_TEX2D_RTV,
};

pub const D3D11_RTV_DIMENSION = enum(c_uint) {
    unknown = 0,
    buffer = 1,
    texture1d = 2,
    texture1darray = 3,
    texture2d = 4,
    texture2darray = 5,
    texture2dms = 6,
    texture2dmsarray = 7,
    texture3d = 8,
};

pub const D3D11_TEX2D_RTV = extern struct {
    mip_slice: UINT,
};

// ============================================================================
// COM Interface Base
// ============================================================================

pub const IUnknown = extern struct {
    vtable: *const IUnknownVTable,

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
// D3D11 Device
// ============================================================================

pub const ID3D11Device = extern struct {
    vtable: *const ID3D11DeviceVTable,

    pub fn queryInterface(self: *ID3D11Device, riid: *const GUID, out: *?*anyopaque) HRESULT {
        return self.vtable.QueryInterface(self, riid, out);
    }

    pub fn createBuffer(self: *ID3D11Device, desc: *const D3D11_BUFFER_DESC, init_data: ?*const D3D11_SUBRESOURCE_DATA, out: **ID3D11Buffer) HRESULT {
        return self.vtable.CreateBuffer(self, desc, init_data, out);
    }

    pub fn createTexture2D(self: *ID3D11Device, desc: *const D3D11_TEXTURE2D_DESC, init_data: ?*const D3D11_SUBRESOURCE_DATA, out: **ID3D11Texture2D) HRESULT {
        return self.vtable.CreateTexture2D(self, desc, init_data, out);
    }

    pub fn createVertexShader(self: *ID3D11Device, bytecode: *const anyopaque, bytecode_len: SIZE_T, class_linkage: ?*ID3D11ClassLinkage, out: **ID3D11VertexShader) HRESULT {
        return self.vtable.CreateVertexShader(self, bytecode, bytecode_len, class_linkage, out);
    }

    pub fn createPixelShader(self: *ID3D11Device, bytecode: *const anyopaque, bytecode_len: SIZE_T, class_linkage: ?*ID3D11ClassLinkage, out: **ID3D11PixelShader) HRESULT {
        return self.vtable.CreatePixelShader(self, bytecode, bytecode_len, class_linkage, out);
    }

    pub fn createInputLayout(self: *ID3D11Device, desc: [*]const D3D11_INPUT_ELEMENT_DESC, num_elements: UINT, bytecode: *const anyopaque, bytecode_len: SIZE_T, out: **ID3D11InputLayout) HRESULT {
        return self.vtable.CreateInputLayout(self, desc, num_elements, bytecode, bytecode_len, out);
    }

    pub fn createRenderTargetView(self: *ID3D11Device, resource: *ID3D11Resource, desc: ?*const D3D11_RENDER_TARGET_VIEW_DESC, out: **ID3D11RenderTargetView) HRESULT {
        return self.vtable.CreateRenderTargetView(self, resource, desc, out);
    }

    pub fn createShaderResourceView(self: *ID3D11Device, resource: *ID3D11Resource, desc: ?*const D3D11_SHADER_RESOURCE_VIEW_DESC, out: **ID3D11ShaderResourceView) HRESULT {
        return self.vtable.CreateShaderResourceView(self, resource, desc, out);
    }

    pub fn createSamplerState(self: *ID3D11Device, desc: *const D3D11_SAMPLER_DESC, out: **ID3D11SamplerState) HRESULT {
        return self.vtable.CreateSamplerState(self, desc, out);
    }

    pub fn createBlendState(self: *ID3D11Device, desc: *const D3D11_BLEND_DESC, out: **ID3D11BlendState) HRESULT {
        return self.vtable.CreateBlendState(self, desc, out);
    }

    pub fn createRasterizerState(self: *ID3D11Device, desc: *const D3D11_RASTERIZER_DESC, out: **ID3D11RasterizerState) HRESULT {
        return self.vtable.CreateRasterizerState(self, desc, out);
    }

    pub fn createDepthStencilState(self: *ID3D11Device, desc: *const D3D11_DEPTH_STENCIL_DESC, out: **ID3D11DepthStencilState) HRESULT {
        return self.vtable.CreateDepthStencilState(self, desc, out);
    }

    pub fn immediateContext(self: *ID3D11Device) *ID3D11DeviceContext {
        var ctx: *ID3D11DeviceContext = undefined;
        self.vtable.GetImmediateContext(self, &ctx);
        return ctx;
    }
};

// Stub for ClassLinkage (not used)
pub const ID3D11ClassLinkage = opaque {};

pub const ID3D11DeviceVTable = extern struct {
    // IUnknown (0-2)
    QueryInterface: *const fn (*ID3D11Device, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*ID3D11Device) callconv(.winapi) u32,
    Release: *const fn (*ID3D11Device) callconv(.winapi) u32,
    // ID3D11Device (3+)
    CreateBuffer: *const fn (*ID3D11Device, *const D3D11_BUFFER_DESC, ?*const D3D11_SUBRESOURCE_DATA, **ID3D11Buffer) callconv(.winapi) HRESULT,
    CreateTexture1D: *const fn (*ID3D11Device, *const anyopaque, ?*const anyopaque, **anyopaque) callconv(.winapi) HRESULT,
    CreateTexture2D: *const fn (*ID3D11Device, *const D3D11_TEXTURE2D_DESC, ?*const D3D11_SUBRESOURCE_DATA, **ID3D11Texture2D) callconv(.winapi) HRESULT,
    CreateTexture3D: *const fn (*ID3D11Device, *const anyopaque, ?*const anyopaque, **anyopaque) callconv(.winapi) HRESULT,
    CreateShaderResourceView: *const fn (*ID3D11Device, *ID3D11Resource, ?*const D3D11_SHADER_RESOURCE_VIEW_DESC, **ID3D11ShaderResourceView) callconv(.winapi) HRESULT,
    CreateUnorderedAccessView: *const fn (*ID3D11Device, *anyopaque, ?*const anyopaque, **anyopaque) callconv(.winapi) HRESULT,
    CreateRenderTargetView: *const fn (*ID3D11Device, *ID3D11Resource, ?*const D3D11_RENDER_TARGET_VIEW_DESC, **ID3D11RenderTargetView) callconv(.winapi) HRESULT,
    CreateDepthStencilView: *const fn (*ID3D11Device, *anyopaque, ?*const anyopaque, **anyopaque) callconv(.winapi) HRESULT,
    CreateInputLayout: *const fn (*ID3D11Device, [*]const D3D11_INPUT_ELEMENT_DESC, UINT, *const anyopaque, SIZE_T, **ID3D11InputLayout) callconv(.winapi) HRESULT,
    CreateVertexShader: *const fn (*ID3D11Device, *const anyopaque, SIZE_T, ?*ID3D11ClassLinkage, **ID3D11VertexShader) callconv(.winapi) HRESULT,
    CreateGeometryShader: *const fn (*ID3D11Device, *const anyopaque, SIZE_T, ?*anyopaque, **anyopaque) callconv(.winapi) HRESULT,
    CreateGeometryShaderWithStreamOutput: *const fn (*ID3D11Device, *const anyopaque, SIZE_T, ?*const anyopaque, UINT, *const UINT, UINT, UINT, ?*anyopaque, **anyopaque) callconv(.winapi) HRESULT,
    CreatePixelShader: *const fn (*ID3D11Device, *const anyopaque, SIZE_T, ?*ID3D11ClassLinkage, **ID3D11PixelShader) callconv(.winapi) HRESULT,
    CreateHullShader: *const fn (*ID3D11Device, *const anyopaque, SIZE_T, ?*anyopaque, **anyopaque) callconv(.winapi) HRESULT,
    CreateDomainShader: *const fn (*ID3D11Device, *const anyopaque, SIZE_T, ?*anyopaque, **anyopaque) callconv(.winapi) HRESULT,
    CreateComputeShader: *const fn (*ID3D11Device, *const anyopaque, SIZE_T, ?*anyopaque, **anyopaque) callconv(.winapi) HRESULT,
    CreateClassLinkage: *const fn (*ID3D11Device, **ID3D11ClassLinkage) callconv(.winapi) HRESULT,
    CreateBlendState: *const fn (*ID3D11Device, *const D3D11_BLEND_DESC, **ID3D11BlendState) callconv(.winapi) HRESULT,
    CreateDepthStencilState: *const fn (*ID3D11Device, *const D3D11_DEPTH_STENCIL_DESC, **ID3D11DepthStencilState) callconv(.winapi) HRESULT,
    CreateRasterizerState: *const fn (*ID3D11Device, *const D3D11_RASTERIZER_DESC, **ID3D11RasterizerState) callconv(.winapi) HRESULT,
    CreateSamplerState: *const fn (*ID3D11Device, *const D3D11_SAMPLER_DESC, **ID3D11SamplerState) callconv(.winapi) HRESULT,
    CreateQuery: *const fn (*ID3D11Device, *const anyopaque, **anyopaque) callconv(.winapi) HRESULT,
    CreatePredicate: *const fn (*ID3D11Device, *const anyopaque, **anyopaque) callconv(.winapi) HRESULT,
    CreateCounter: *const fn (*ID3D11Device, *const D3D11_COUNTER_DESC, **anyopaque) callconv(.winapi) HRESULT,
    CreateDeferredContext: *const fn (*ID3D11Device, UINT, **ID3D11DeviceContext) callconv(.winapi) HRESULT,
    OpenSharedResource: *const fn (*ID3D11Device, HANDLE, *const GUID, **anyopaque) callconv(.winapi) HRESULT,
    CheckFormatSupport: *const fn (*ID3D11Device, DXGI_FORMAT, *UINT) callconv(.winapi) HRESULT,
    CheckMultisampleQualityLevels: *const fn (*ID3D11Device, DXGI_FORMAT, UINT, *UINT) callconv(.winapi) HRESULT,
    CheckCounterInfo: *const fn (*ID3D11Device, *D3D11_COUNTER_INFO) callconv(.winapi) void,
    CheckCounter: *const fn (*ID3D11Device, *const D3D11_COUNTER_DESC, *D3D11_COUNTER_TYPE, *UINT, [*:0]u8, *UINT) callconv(.winapi) HRESULT,
    CheckFeatureSupport: *const fn (*ID3D11Device, D3D11_FEATURE, *anyopaque, UINT) callconv(.winapi) HRESULT,
    GetPrivateData: *const fn (*ID3D11Device, *const GUID, *UINT, ?*anyopaque) callconv(.winapi) HRESULT,
    SetPrivateData: *const fn (*ID3D11Device, *const GUID, UINT, ?*const anyopaque) callconv(.winapi) HRESULT,
    SetPrivateDataInterface: *const fn (*ID3D11Device, *const GUID, ?*const IUnknown) callconv(.winapi) HRESULT,
    GetFeatureLevel: *const fn (*ID3D11Device) callconv(.winapi) D3D_FEATURE_LEVEL,
    GetCreationFlags: *const fn (*ID3D11Device) callconv(.winapi) u32,
    GetDeviceRemovedReason: *const fn (*ID3D11Device) callconv(.winapi) HRESULT,
    GetImmediateContext: *const fn (*ID3D11Device, **ID3D11DeviceContext) callconv(.winapi) void,
    SetExceptionMode: *const fn (*ID3D11Device, UINT) callconv(.winapi) HRESULT,
    GetExceptionMode: *const fn (*ID3D11Device) callconv(.winapi) UINT,
};

// Stubs for D3D11 types we don't use directly
pub const D3D_FEATURE_LEVEL = enum(c_uint) {
    @"9_1" = 0x9100,
    @"9_2" = 0x9200,
    @"9_3" = 0x9300,
    @"10_0" = 0xA000,
    @"10_1" = 0xA100,
    @"11_0" = 0xB000,
    @"11_1" = 0xB100,
    @"12_0" = 0xC000,
    @"12_1" = 0xC100,
};

pub const D3D11_COUNTER_INFO = extern struct {
    last_device_returned_counter: u32,
    num_simultaneous_counters: u32,
    num_detectable_parallel_units: u8,
};

pub const D3D11_COUNTER_DESC = extern struct {
    counter: u32,
    misc_flags: u32,
};

pub const D3D11_COUNTER_TYPE = enum(c_uint) {
    floating_point = 0,
    unsigned_int = 1,
    signed_int = 2,
};

pub const D3D11_FEATURE = enum(c_uint) {
    threading = 0,
    doubles = 1,
    format_support = 2,
    format_support2 = 3,
    d3d10_x_hardware_options = 4,
    d3d11_basic_options = 5,
    d3d11_basic_options1 = 6,
    d3d11_basic_options2 = 7,
    d3d11_basic_options3 = 8,
    d3d11_basic_options4 = 9,
    d3d11_options = 10,
    d3d11_options1 = 11,
    d3d11_options2 = 12,
    d3d11_options3 = 13,
    d3d11_options4 = 14,
    shadowing = 15,
    gpu_virtual_address_support = 16,
    d3d11_options5 = 17,
    displayable = 18,
};

// ============================================================================
// D3D11 Device Context
// ============================================================================

pub const ID3D11DeviceContext = extern struct {
    vtable: *const ID3D11DeviceContextVTable,

    pub fn map(self: *ID3D11DeviceContext, resource: *ID3D11Resource, subresource: UINT, map_type: D3D11_MAP, map_flags: UINT, out: *D3D11_MAPPED_SUBRESOURCE) HRESULT {
        return self.vtable.Map(self, resource, subresource, map_type, map_flags, out);
    }

    pub fn unmap(self: *ID3D11DeviceContext, resource: *ID3D11Resource, subresource: UINT) void {
        self.vtable.Unmap(self, resource, subresource);
    }

    pub fn updateSubresource(self: *ID3D11DeviceContext, dst: *ID3D11Resource, dst_subresource: UINT, dst_box: ?*const D3D11_BOX, src: *const anyopaque, src_row_pitch: UINT, src_depth_pitch: UINT) void {
        self.vtable.UpdateSubresource(self, dst, dst_subresource, dst_box, src, src_row_pitch, src_depth_pitch);
    }

    pub fn iaSetInputLayout(self: *ID3D11DeviceContext, layout: ?*ID3D11InputLayout) void {
        self.vtable.IASetInputLayout(self, layout);
    }

    pub fn iaSetVertexBuffers(self: *ID3D11DeviceContext, start_slot: UINT, num_buffers: UINT, buffers: [*]const *ID3D11Buffer, strides: [*]const UINT, offsets: [*]const UINT) void {
        self.vtable.IASetVertexBuffers(self, start_slot, num_buffers, buffers, strides, offsets);
    }

    pub fn iaSetPrimitiveTopology(self: *ID3D11DeviceContext, topology: D3D11_PRIMITIVE_TOPOLOGY) void {
        self.vtable.IASetPrimitiveTopology(self, topology);
    }

    pub fn vsSetShader(self: *ID3D11DeviceContext, shader: ?*ID3D11VertexShader, class_instances: ?[*]const *ID3D11ClassInstance, num_class_instances: UINT) void {
        self.vtable.VSSetShader(self, shader, class_instances, num_class_instances);
    }

    pub fn vsSetConstantBuffers(self: *ID3D11DeviceContext, start_slot: UINT, num_buffers: UINT, buffers: [*]const *ID3D11Buffer) void {
        self.vtable.VSSetConstantBuffers(self, start_slot, num_buffers, buffers);
    }

    pub fn vsSetShaderResources(self: *ID3D11DeviceContext, start_slot: UINT, num_views: UINT, views: [*]const ?*ID3D11ShaderResourceView) void {
        self.vtable.VSSetShaderResources(self, start_slot, num_views, views);
    }

    pub fn psSetShader(self: *ID3D11DeviceContext, shader: ?*ID3D11PixelShader, class_instances: ?[*]const *ID3D11ClassInstance, num_class_instances: UINT) void {
        self.vtable.PSSetShader(self, shader, class_instances, num_class_instances);
    }

    pub fn psSetConstantBuffers(self: *ID3D11DeviceContext, start_slot: UINT, num_buffers: UINT, buffers: [*]const *ID3D11Buffer) void {
        self.vtable.PSSetConstantBuffers(self, start_slot, num_buffers, buffers);
    }

    pub fn psSetShaderResources(self: *ID3D11DeviceContext, start_slot: UINT, num_views: UINT, views: [*]const ?*ID3D11ShaderResourceView) void {
        self.vtable.PSSetShaderResources(self, start_slot, num_views, views);
    }

    pub fn psSetSamplers(self: *ID3D11DeviceContext, start_slot: UINT, num_samplers: UINT, samplers: [*]const *ID3D11SamplerState) void {
        self.vtable.PSSetSamplers(self, start_slot, num_samplers, samplers);
    }

    pub fn omSetRenderTargets(self: *ID3D11DeviceContext, num_views: UINT, views: ?[*]const ?*ID3D11RenderTargetView, depth_stencil: ?*ID3D11DepthStencilView) void {
        self.vtable.OMSetRenderTargets(self, num_views, if (views) |v| v else null, depth_stencil);
    }

    pub fn omSetBlendState(self: *ID3D11DeviceContext, blend_state: ?*ID3D11BlendState, blend_factor: ?*const [4]FLOAT, sample_mask: UINT) void {
        self.vtable.OMSetBlendState(self, blend_state, blend_factor, sample_mask);
    }

    pub fn rsSetState(self: *ID3D11DeviceContext, state: ?*ID3D11RasterizerState) void {
        self.vtable.RSSetState(self, state);
    }

    pub fn rsSetViewports(self: *ID3D11DeviceContext, num_viewports: UINT, viewports: [*]const D3D11_VIEWPORT) void {
        self.vtable.RSSetViewports(self, num_viewports, viewports);
    }

    pub fn drawInstanced(self: *ID3D11DeviceContext, vertex_count_per_instance: UINT, instance_count: UINT, start_vertex_location: UINT, start_instance_location: UINT) void {
        self.vtable.DrawInstanced(self, vertex_count_per_instance, instance_count, start_vertex_location, start_instance_location);
    }

    pub fn clearRenderTargetView(self: *ID3D11DeviceContext, view: *ID3D11RenderTargetView, color: *const [4]FLOAT) void {
        self.vtable.ClearRenderTargetView(self, view, color);
    }

    pub fn copyResource(self: *ID3D11DeviceContext, dst: *ID3D11Resource, src: *ID3D11Resource) void {
        self.vtable.CopyResource(self, dst, src);
    }

    pub fn copySubresourceRegion(self: *ID3D11DeviceContext, dst: *ID3D11Resource, dst_subresource: UINT, dst_x: UINT, dst_y: UINT, dst_z: UINT, src: *ID3D11Resource, src_subresource: UINT, src_box: ?*const D3D11_BOX) void {
        self.vtable.CopySubresourceRegion(self, dst, dst_subresource, dst_x, dst_y, dst_z, src, src_subresource, src_box);
    }

    pub fn flush(self: *ID3D11DeviceContext) void {
        self.vtable.Flush(self);
    }

    /// Clear all bound resources (shaders, buffers, views, samplers, etc).
    /// Equivalent to ID3D11DeviceContext::ClearState().
    /// Required before ResizeBuffers to ensure no references to swap chain buffers remain.
    pub fn clearState(self: *ID3D11DeviceContext) void {
        self.vtable.ClearState(self);
    }
};

// More stubs
pub const ID3D11ClassInstance = opaque {};
pub const ID3D11DepthStencilView = opaque {};
pub const D3D11_BOX = extern struct {
    left: UINT,
    top: UINT,
    front: UINT,
    right: UINT,
    bottom: UINT,
    back: UINT,
};

pub const RECT = extern struct {
    left: c_long,
    top: c_long,
    right: c_long,
    bottom: c_long,
};

// VTable for ID3D11DeviceContext - exact COM vtable order
// Placeholder type for methods we don't call directly
const CtxFn = *const fn (*ID3D11DeviceContext) callconv(.winapi) void;
pub const ID3D11DeviceContextVTable = extern struct {
    // IUnknown (0-2)
    QueryInterface: *const fn (*ID3D11DeviceContext, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*ID3D11DeviceContext) callconv(.winapi) u32,
    Release: *const fn (*ID3D11DeviceContext) callconv(.winapi) u32,
    // ID3D11DeviceChild (3-6)
    GetDevice: *const fn (*ID3D11DeviceContext, **ID3D11Device) callconv(.winapi) void,
    GetPrivateData: CtxFn,
    SetPrivateData: CtxFn,
    SetPrivateDataInterface: CtxFn,
    // ID3D11DeviceContext (7+)
    VSSetConstantBuffers: *const fn (*ID3D11DeviceContext, UINT, UINT, [*]const *ID3D11Buffer) callconv(.winapi) void,
    PSSetShaderResources: *const fn (*ID3D11DeviceContext, UINT, UINT, [*]const ?*ID3D11ShaderResourceView) callconv(.winapi) void,
    PSSetShader: *const fn (*ID3D11DeviceContext, ?*ID3D11PixelShader, ?[*]const *ID3D11ClassInstance, UINT) callconv(.winapi) void,
    PSSetSamplers: *const fn (*ID3D11DeviceContext, UINT, UINT, [*]const *ID3D11SamplerState) callconv(.winapi) void,
    VSSetShader: *const fn (*ID3D11DeviceContext, ?*ID3D11VertexShader, ?[*]const *ID3D11ClassInstance, UINT) callconv(.winapi) void,
    DrawIndexed: CtxFn,
    Draw: *const fn (*ID3D11DeviceContext, UINT, UINT) callconv(.winapi) void,
    Map: *const fn (*ID3D11DeviceContext, *ID3D11Resource, UINT, D3D11_MAP, UINT, *D3D11_MAPPED_SUBRESOURCE) callconv(.winapi) HRESULT,
    Unmap: *const fn (*ID3D11DeviceContext, *ID3D11Resource, UINT) callconv(.winapi) void,
    PSSetConstantBuffers: *const fn (*ID3D11DeviceContext, UINT, UINT, [*]const *ID3D11Buffer) callconv(.winapi) void,
    IASetInputLayout: *const fn (*ID3D11DeviceContext, ?*ID3D11InputLayout) callconv(.winapi) void,
    IASetVertexBuffers: *const fn (*ID3D11DeviceContext, UINT, UINT, [*]const *ID3D11Buffer, [*]const UINT, [*]const UINT) callconv(.winapi) void,
    IASetIndexBuffer: CtxFn,
    DrawIndexedInstanced: CtxFn,
    DrawInstanced: *const fn (*ID3D11DeviceContext, UINT, UINT, UINT, UINT) callconv(.winapi) void,
    GSSetConstantBuffers: CtxFn,
    GSSetShader: CtxFn,
    IASetPrimitiveTopology: *const fn (*ID3D11DeviceContext, D3D11_PRIMITIVE_TOPOLOGY) callconv(.winapi) void,
    VSSetShaderResources: *const fn (*ID3D11DeviceContext, UINT, UINT, [*]const ?*ID3D11ShaderResourceView) callconv(.winapi) void,
    VSSetSamplers: CtxFn,
    Begin_: CtxFn,
    End_: CtxFn,
    GetData: CtxFn,
    SetPredication: CtxFn,
    GSSetShaderResources: CtxFn,
    GSSetSamplers: CtxFn,
    OMSetRenderTargets: *const fn (*ID3D11DeviceContext, UINT, ?[*]const ?*ID3D11RenderTargetView, ?*ID3D11DepthStencilView) callconv(.winapi) void,
    OMSetRenderTargetsAndUnorderedAccessViews: CtxFn,
    OMSetBlendState: *const fn (*ID3D11DeviceContext, ?*ID3D11BlendState, ?*const [4]FLOAT, UINT) callconv(.winapi) void,
    OMSetDepthStencilState: CtxFn,
    SOSetTargets: CtxFn,
    DrawAuto: CtxFn,
    DrawIndexedInstancedIndirect: CtxFn,
    DrawInstancedIndirect: CtxFn,
    Dispatch: CtxFn,
    DispatchIndirect: CtxFn,
    RSSetState: *const fn (*ID3D11DeviceContext, ?*ID3D11RasterizerState) callconv(.winapi) void,
    RSSetViewports: *const fn (*ID3D11DeviceContext, UINT, [*]const D3D11_VIEWPORT) callconv(.winapi) void,
    RSSetScissorRects: CtxFn,
    CopySubresourceRegion: *const fn (*ID3D11DeviceContext, *ID3D11Resource, UINT, UINT, UINT, UINT, *ID3D11Resource, UINT, ?*const D3D11_BOX) callconv(.winapi) void,
    CopyResource: *const fn (*ID3D11DeviceContext, *ID3D11Resource, *ID3D11Resource) callconv(.winapi) void,
    UpdateSubresource: *const fn (*ID3D11DeviceContext, *ID3D11Resource, UINT, ?*const D3D11_BOX, *const anyopaque, UINT, UINT) callconv(.winapi) void,
    CopyStructureCount: CtxFn,
    ClearRenderTargetView: *const fn (*ID3D11DeviceContext, *ID3D11RenderTargetView, *const [4]FLOAT) callconv(.winapi) void,
    ClearUnorderedAccessViewUint: CtxFn,
    ClearUnorderedAccessViewFloat: CtxFn,
    ClearDepthStencilView: CtxFn,
    GenerateMips: CtxFn,
    SetResourceMinLOD: CtxFn,
    GetResourceMinLOD: CtxFn,
    ResolveSubresource: CtxFn,
    ExecuteCommandList: CtxFn,
    HSSetShaderResources: CtxFn,
    HSSetShader: CtxFn,
    HSSetSamplers: CtxFn,
    HSSetConstantBuffers: CtxFn,
    DSSetShaderResources: CtxFn,
    DSSetShader: CtxFn,
    DSSetSamplers: CtxFn,
    DSSetConstantBuffers: CtxFn,
    CSSetShaderResources: CtxFn,
    CSSetUnorderedAccessViews: CtxFn,
    CSSetShader: CtxFn,
    CSSetSamplers: CtxFn,
    CSSetConstantBuffers: CtxFn,
    VSGetConstantBuffers: CtxFn,
    VSGetShaderResources: CtxFn,
    VSGetSamplers: CtxFn,
    VSGetShader: CtxFn,
    PSGetShaderResources: CtxFn,
    PSGetShader: CtxFn,
    PSGetSamplers: CtxFn,
    PSGetConstantBuffers: CtxFn,
    IAGetInputLayout: CtxFn,
    IAGetVertexBuffers: CtxFn,
    IAGetIndexBuffer: CtxFn,
    GSGetConstantBuffers: CtxFn,
    GSGetShader: CtxFn,
    GSGetShaderResources: CtxFn,
    GSGetSamplers: CtxFn,
    IAGetPrimitiveTopology: CtxFn,
    GetPredication: CtxFn,
    GSGetOutputTopology: CtxFn,
    OMGetRenderTargets: CtxFn,
    OMGetRenderTargetsAndUnorderedAccessViews: CtxFn,
    OMGetBlendState: CtxFn,
    OMGetDepthStencilState: CtxFn,
    SOGetTargets: CtxFn,
    RSGetState: CtxFn,
    RSGetViewports: CtxFn,
    RSGetScissorRects: CtxFn,
    HSGetShaderResources: CtxFn,
    HSGetShader: CtxFn,
    HSGetSamplers: CtxFn,
    HSGetConstantBuffers: CtxFn,
    DSGetShaderResources: CtxFn,
    DSGetShader: CtxFn,
    DSGetSamplers: CtxFn,
    DSGetConstantBuffers: CtxFn,
    CSGetShaderResources: CtxFn,
    CSGetUnorderedAccessViews: CtxFn,
    CSGetShader: CtxFn,
    CSGetSamplers: CtxFn,
    CSGetConstantBuffers: CtxFn,
    ClearState: CtxFn,
    Flush: *const fn (*ID3D11DeviceContext) callconv(.winapi) void,
    GetType: CtxFn,
    GetContextFlags: CtxFn,
    FinishCommandList: CtxFn,
};

// ============================================================================
// D3D11 Resource (base type)
// ============================================================================

pub const ID3D11Resource = extern struct {
    vtable: *const ID3D11ResourceVTable,
};

pub const ID3D11ResourceVTable = extern struct {
    queryInterface: *const fn (*ID3D11Resource, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    addRef: *const fn (*ID3D11Resource) callconv(.winapi) u32,
    release: *const fn (*ID3D11Resource) callconv(.winapi) u32,
    // DeviceChild methods (stubs)
    getDevice: *const fn (*ID3D11Resource, **ID3D11Device) callconv(.winapi) void,
    getPrivateData: *const fn (*ID3D11Resource, *const GUID, *UINT, ?*anyopaque) callconv(.winapi) HRESULT,
    setPrivateData: *const fn (*ID3D11Resource, *const GUID, UINT, ?*const anyopaque) callconv(.winapi) HRESULT,
    setPrivateDataInterface: *const fn (*ID3D11Resource, *const GUID, ?*const IUnknown) callconv(.winapi) HRESULT,
    // Resource methods
    getType: *const fn (*ID3D11Resource, *D3D11_RESOURCE_DIMENSION) callconv(.winapi) void,
    setEvictionPriority: *const fn (*ID3D11Resource, UINT) callconv(.winapi) void,
    getEvictionPriority: *const fn (*ID3D11Resource) callconv(.winapi) UINT,
};

pub const D3D11_RESOURCE_DIMENSION = enum(c_uint) {
    unknown = 0,
    buffer = 1,
    texture1d = 2,
    texture2d = 3,
    texture3d = 4,
};

// ============================================================================
// D3D11 Concrete Types
// ============================================================================

pub const ID3D11Buffer = extern struct {
    vtable: *const ID3D11BufferVTable,
};

pub const ID3D11BufferVTable = extern struct {
    queryInterface: *const fn (*ID3D11Buffer, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    addRef: *const fn (*ID3D11Buffer) callconv(.winapi) u32,
    release: *const fn (*ID3D11Buffer) callconv(.winapi) u32,
    // DeviceChild
    getDevice: *const fn (*ID3D11Buffer, **ID3D11Device) callconv(.winapi) void,
    getPrivateData: *const fn (*ID3D11Buffer, *const GUID, *UINT, ?*anyopaque) callconv(.winapi) HRESULT,
    setPrivateData: *const fn (*ID3D11Buffer, *const GUID, UINT, ?*const anyopaque) callconv(.winapi) HRESULT,
    setPrivateDataInterface: *const fn (*ID3D11Buffer, *const GUID, ?*const IUnknown) callconv(.winapi) HRESULT,
    // Resource
    getType: *const fn (*ID3D11Buffer, *D3D11_RESOURCE_DIMENSION) callconv(.winapi) void,
    setEvictionPriority: *const fn (*ID3D11Buffer, UINT) callconv(.winapi) void,
    getEvictionPriority: *const fn (*ID3D11Buffer) callconv(.winapi) UINT,
    // Buffer
    getDesc: *const fn (*ID3D11Buffer, *D3D11_BUFFER_DESC) callconv(.winapi) void,
};

pub const ID3D11Texture2D = extern struct {
    vtable: *const ID3D11Texture2DVTable,
};

pub const ID3D11Texture2DVTable = extern struct {
    queryInterface: *const fn (*ID3D11Texture2D, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    addRef: *const fn (*ID3D11Texture2D) callconv(.winapi) u32,
    release: *const fn (*ID3D11Texture2D) callconv(.winapi) u32,
    // DeviceChild
    getDevice: *const fn (*ID3D11Texture2D, **ID3D11Device) callconv(.winapi) void,
    getPrivateData: *const fn (*ID3D11Texture2D, *const GUID, *UINT, ?*anyopaque) callconv(.winapi) HRESULT,
    setPrivateData: *const fn (*ID3D11Texture2D, *const GUID, UINT, ?*const anyopaque) callconv(.winapi) HRESULT,
    setPrivateDataInterface: *const fn (*ID3D11Texture2D, *const GUID, ?*const IUnknown) callconv(.winapi) HRESULT,
    // Resource
    getType: *const fn (*ID3D11Texture2D, *D3D11_RESOURCE_DIMENSION) callconv(.winapi) void,
    setEvictionPriority: *const fn (*ID3D11Texture2D, UINT) callconv(.winapi) void,
    getEvictionPriority: *const fn (*ID3D11Texture2D) callconv(.winapi) UINT,
    // Texture2D
    getDesc: *const fn (*ID3D11Texture2D, *D3D11_TEXTURE2D_DESC) callconv(.winapi) void,
};

pub const ID3D11VertexShader = extern struct {
    vtable: *const IUnknownVTable,
};
pub const ID3D11PixelShader = extern struct {
    vtable: *const IUnknownVTable,
};
pub const ID3D11InputLayout = extern struct {
    vtable: *const IUnknownVTable,
};
pub const ID3D11SamplerState = extern struct {
    vtable: *const IUnknownVTable,
};
pub const ID3D11RasterizerState = extern struct {
    vtable: *const IUnknownVTable,
};
pub const ID3D11BlendState = extern struct {
    vtable: *const IUnknownVTable,
};
pub const ID3D11DepthStencilState = extern struct {
    vtable: *const IUnknownVTable,
};
pub const ID3D11RenderTargetView = extern struct {
    vtable: *const IUnknownVTable,
};
pub const ID3D11ShaderResourceView = extern struct {
    vtable: *const IUnknownVTable,
};

// Helper to cast concrete types to ID3D11Resource
pub fn resourceFromTexture2D(tex: *ID3D11Texture2D) *ID3D11Resource {
    return @ptrCast(tex);
}

pub fn resourceFromBuffer(buf: *ID3D11Buffer) *ID3D11Resource {
    return @ptrCast(buf);
}

pub fn resourceFromTexture2DConst(tex: *const ID3D11Texture2D) *const ID3D11Resource {
    return @ptrCast(tex);
}

/// Release a COM object by casting to IUnknown and calling Release.
pub fn releaseCOM(obj: *anyopaque) u32 {
    const unknown: *IUnknown = @ptrCast(@alignCast(obj));
    return unknown.vtable.Release(unknown);
}

// ============================================================================
// DXGI Factory and Swap Chain
// ============================================================================

pub const IDXGIFactory2 = extern struct {
    vtable: *const IDXGIFactory2VTable,

    pub fn createSwapChainForHwnd(self: *IDXGIFactory2, device: ?*IUnknown, hwnd: HWND, desc: *const DXGI_SWAP_CHAIN_DESC1, fullscreen_desc: ?*const DXGI_SWAP_CHAIN_FULLSCREEN_DESC, restrict_to_output: ?*IDXGIOutput, out: **IDXGISwapChain1) HRESULT {
        return self.vtable.createSwapChainForHwnd(self, device, hwnd, desc, fullscreen_desc, restrict_to_output, out);
    }

    pub fn createSwapChainForComposition(self: *IDXGIFactory2, device: ?*IUnknown, desc: *const DXGI_SWAP_CHAIN_DESC1, restrict_to_output: ?*IDXGIOutput, out: **IDXGISwapChain1) HRESULT {
        return self.vtable.createSwapChainForComposition(self, device, desc, restrict_to_output, out);
    }
};

pub const IDXGIOutput = opaque {};

pub const IDXGIFactory2VTable = extern struct {
    // IDXGIObject
    queryInterface: *const fn (*IDXGIFactory2, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    addRef: *const fn (*IDXGIFactory2) callconv(.winapi) u32,
    release: *const fn (*IDXGIFactory2) callconv(.winapi) u32,
    setPrivateData: *const fn (*IDXGIFactory2, *const GUID, UINT, *const anyopaque) callconv(.winapi) HRESULT,
    setPrivateDataInterface: *const fn (*IDXGIFactory2, *const GUID, *const IUnknown) callconv(.winapi) HRESULT,
    getPrivateData: *const fn (*IDXGIFactory2, *const GUID, *UINT, ?*anyopaque) callconv(.winapi) HRESULT,
    getParent: *const fn (*IDXGIFactory2, *const GUID, **anyopaque) callconv(.winapi) HRESULT,
    // IDXGIFactory
    enumAdapters: *const fn (*IDXGIFactory2, UINT, **anyopaque) callconv(.winapi) HRESULT,
    makeWindowAssociation: *const fn (*IDXGIFactory2, HWND, UINT) callconv(.winapi) HRESULT,
    getWindowAssociation: *const fn (*IDXGIFactory2, *HWND) callconv(.winapi) HRESULT,
    createSwapChain: *const fn (*IDXGIFactory2, *IUnknown, *const anyopaque, **anyopaque) callconv(.winapi) HRESULT,
    createSoftwareAdapter: *const fn (*IDXGIFactory2, HMODULE, **anyopaque) callconv(.winapi) HRESULT,
    // IDXGIFactory1
    enumAdapters1: *const fn (*IDXGIFactory2, UINT, **anyopaque) callconv(.winapi) HRESULT,
    isCurrent: *const fn (*IDXGIFactory2) callconv(.winapi) BOOL,
    // IDXGIFactory2
    isWindowedStereoEnabled: *const fn (*IDXGIFactory2) callconv(.winapi) BOOL,
    createSwapChainForHwnd: *const fn (*IDXGIFactory2, ?*IUnknown, HWND, *const DXGI_SWAP_CHAIN_DESC1, ?*const DXGI_SWAP_CHAIN_FULLSCREEN_DESC, ?*IDXGIOutput, **IDXGISwapChain1) callconv(.winapi) HRESULT,
    createSwapChainForCoreWindow: *const fn (*IDXGIFactory2, ?*IUnknown, *IUnknown, *const DXGI_SWAP_CHAIN_DESC1, ?*IDXGIOutput, **IDXGISwapChain1) callconv(.winapi) HRESULT,
    getSharedResourceAdapterLuid: *const fn (*IDXGIFactory2, HANDLE, *anyopaque) callconv(.winapi) HRESULT,
    registerStereoStatusWindow: *const fn (*IDXGIFactory2, HWND, UINT, *u32) callconv(.winapi) HRESULT,
    registerStereoStatusEvent: *const fn (*IDXGIFactory2, HANDLE, *u32) callconv(.winapi) HRESULT,
    unregisterStereoStatus: *const fn (*IDXGIFactory2, u32) callconv(.winapi) void,
    registerOcclusionStatusWindow: *const fn (*IDXGIFactory2, HWND, UINT, *u32) callconv(.winapi) HRESULT,
    registerOcclusionStatusEvent: *const fn (*IDXGIFactory2, HANDLE, *u32) callconv(.winapi) HRESULT,
    unregisterOcclusionStatus: *const fn (*IDXGIFactory2, u32) callconv(.winapi) void,
    // IDXGIFactory2 (last method)
    createSwapChainForComposition: *const fn (*IDXGIFactory2, ?*IUnknown, ?*const DXGI_SWAP_CHAIN_DESC1, ?*IDXGIOutput, **IDXGISwapChain1) callconv(.winapi) HRESULT,
};

pub const IDXGISwapChain1 = extern struct {
    vtable: *const IDXGISwapChain1VTable,

    pub fn present(self: *IDXGISwapChain1, sync_interval: UINT, flags: UINT) HRESULT {
        return self.vtable.present(self, sync_interval, flags);
    }

    pub fn getBuffer(self: *IDXGISwapChain1, index: UINT, riid: *const GUID, out: *?*anyopaque) HRESULT {
        return self.vtable.getBuffer(self, index, riid, out);
    }

    pub fn resizeBuffers(self: *IDXGISwapChain1, buffer_count: UINT, width: UINT, height: UINT, new_format: DXGI_FORMAT, flags: UINT) HRESULT {
        return self.vtable.resizeBuffers(self, buffer_count, width, height, new_format, flags);
    }

    pub fn getDesc1(self: *IDXGISwapChain1, desc: *DXGI_SWAP_CHAIN_DESC1) HRESULT {
        return self.vtable.getDesc1(self, desc);
    }
};

pub const IDXGISwapChain1VTable = extern struct {
    // IDXGIObject
    queryInterface: *const fn (*IDXGISwapChain1, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    addRef: *const fn (*IDXGISwapChain1) callconv(.winapi) u32,
    release: *const fn (*IDXGISwapChain1) callconv(.winapi) u32,
    setPrivateData: *const fn (*IDXGISwapChain1, *const GUID, UINT, *const anyopaque) callconv(.winapi) HRESULT,
    setPrivateDataInterface: *const fn (*IDXGISwapChain1, *const GUID, *const IUnknown) callconv(.winapi) HRESULT,
    getPrivateData: *const fn (*IDXGISwapChain1, *const GUID, *UINT, ?*anyopaque) callconv(.winapi) HRESULT,
    getParent: *const fn (*IDXGISwapChain1, *const GUID, **anyopaque) callconv(.winapi) HRESULT,
    // IDXGIDeviceSubObject
    getDevice: *const fn (*IDXGISwapChain1, *const GUID, **anyopaque) callconv(.winapi) HRESULT,
    // IDXGISwapChain
    present: *const fn (*IDXGISwapChain1, UINT, UINT) callconv(.winapi) HRESULT,
    getBuffer: *const fn (*IDXGISwapChain1, UINT, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    setFullscreenState: *const fn (*IDXGISwapChain1, BOOL, ?*IDXGIOutput) callconv(.winapi) HRESULT,
    getFullscreenState: *const fn (*IDXGISwapChain1, *BOOL, *?*IDXGIOutput) callconv(.winapi) HRESULT,
    getDesc: *const fn (*IDXGISwapChain1, *anyopaque) callconv(.winapi) HRESULT,
    resizeBuffers: *const fn (*IDXGISwapChain1, UINT, UINT, UINT, DXGI_FORMAT, UINT) callconv(.winapi) HRESULT,
    resizeTarget: *const fn (*IDXGISwapChain1, *const anyopaque) callconv(.winapi) HRESULT,
    getContainingOutput: *const fn (*IDXGISwapChain1, **IDXGIOutput) callconv(.winapi) HRESULT,
    getFrameStatistics: *const fn (*IDXGISwapChain1, *anyopaque) callconv(.winapi) HRESULT,
    getLastPresentCount: *const fn (*IDXGISwapChain1, *UINT) callconv(.winapi) HRESULT,
    // IDXGISwapChain1
    getDesc1: *const fn (*IDXGISwapChain1, *DXGI_SWAP_CHAIN_DESC1) callconv(.winapi) HRESULT,
    getFullscreenDesc: *const fn (*IDXGISwapChain1, *DXGI_SWAP_CHAIN_FULLSCREEN_DESC) callconv(.winapi) HRESULT,
    getHwnd: *const fn (*IDXGISwapChain1, *HWND) callconv(.winapi) HRESULT,
    getCoreWindow: *const fn (*IDXGISwapChain1, *const GUID, **anyopaque) callconv(.winapi) HRESULT,
    present1: *const fn (*IDXGISwapChain1, UINT, UINT, *const anyopaque) callconv(.winapi) HRESULT,
    isTemporaryMonoSupported: *const fn (*IDXGISwapChain1) callconv(.winapi) BOOL,
    getRestrictToOutput: *const fn (*IDXGISwapChain1, **IDXGIOutput) callconv(.winapi) HRESULT,
    setBackgroundColor: *const fn (*IDXGISwapChain1, *const anyopaque) callconv(.winapi) HRESULT,
    getBackgroundColor: *const fn (*IDXGISwapChain1, *anyopaque) callconv(.winapi) HRESULT,
    setRotation: *const fn (*IDXGISwapChain1, *const anyopaque) callconv(.winapi) HRESULT,
    getRotation: *const fn (*IDXGISwapChain1, *anyopaque) callconv(.winapi) HRESULT,
};

// ============================================================================
// GUIDs
// ============================================================================

pub const IID_ID3D11Texture2D = GUID.init(0x6f15aaf2, 0xd208, 0x4e89, .{ 0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c });
pub const IID_IDXGIFactory2 = GUID.init(0x50c83a1c, 0xe072, 0x4c48, .{ 0x87, 0xb0, 0x36, 0x30, 0xfa, 0x36, 0xa6, 0xd0 });
pub const IID_IDXGISwapChain1 = GUID.init(0x790a45f7, 0x0d42, 0x4876, .{ 0x98, 0x3a, 0x0a, 0x55, 0xcf, 0xe6, 0xf6, 0xaa });
pub const IID_IDXGIDevice = GUID.init(0x54ec77fa, 0x1377, 0x44e6, .{ 0x8c, 0x32, 0x88, 0xfd, 0x5f, 0x44, 0xc8, 0x4c });
pub const IID_IDXGIAdapter = GUID.init(0x2411e7e1, 0x12ac, 0x4ccf, .{ 0xbd, 0x14, 0x97, 0x98, 0xe8, 0x53, 0x36, 0xd6 });
pub const IID_IDXGIFactory1 = GUID.init(0x770aae78, 0xf26f, 0x4dba, .{ 0xa8, 0x29, 0x25, 0x3c, 0x83, 0xd1, 0xb3, 0x87 });

// ============================================================================
// IDXGIDevice - used to get the adapter from the D3D11 device
// ============================================================================

pub const IDXGIDevice = extern struct {
    vtable: *const IDXGIDeviceVTable,

    pub fn getAdapter(self: *IDXGIDevice, out: **IDXGIAdapter) HRESULT {
        return self.vtable.getAdapter(self, out);
    }
};

pub const IDXGIDeviceVTable = extern struct {
    // IUnknown
    queryInterface: *const fn (*IDXGIDevice, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    addRef: *const fn (*IDXGIDevice) callconv(.winapi) u32,
    release: *const fn (*IDXGIDevice) callconv(.winapi) u32,
    // IDXGIObject
    setPrivateData: *const fn (*IDXGIDevice, *const GUID, UINT, *const anyopaque) callconv(.winapi) HRESULT,
    setPrivateDataInterface: *const fn (*IDXGIDevice, *const GUID, *const IUnknown) callconv(.winapi) HRESULT,
    getPrivateData: *const fn (*IDXGIDevice, *const GUID, *UINT, ?*anyopaque) callconv(.winapi) HRESULT,
    getParent: *const fn (*IDXGIDevice, *const GUID, **anyopaque) callconv(.winapi) HRESULT,
    // IDXGIDevice
    getAdapter: *const fn (*IDXGIDevice, **IDXGIAdapter) callconv(.winapi) HRESULT,
    createSurface: *const fn (*IDXGIDevice, *const anyopaque, UINT, UINT, *const anyopaque, **anyopaque) callconv(.winapi) HRESULT,
    queryResourceResidency: *const fn (*IDXGIDevice, **const anyopaque, *HRESULT, UINT) callconv(.winapi) HRESULT,
    setGPUThreadPriority: *const fn (*IDXGIDevice, INT) callconv(.winapi) HRESULT,
    getGPUThreadPriority: *const fn (*IDXGIDevice, *INT) callconv(.winapi) HRESULT,
};

// ============================================================================
// IDXGIAdapter - used to get the parent factory from the adapter
// ============================================================================

pub const IDXGIAdapter = extern struct {
    vtable: *const IDXGIAdapterVTable,

    pub fn getParent(self: *IDXGIAdapter, riid: *const GUID, out: **anyopaque) HRESULT {
        return self.vtable.getParent(self, riid, out);
    }
};

pub const IDXGIAdapterVTable = extern struct {
    // IUnknown
    queryInterface: *const fn (*IDXGIAdapter, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    addRef: *const fn (*IDXGIAdapter) callconv(.winapi) u32,
    release: *const fn (*IDXGIAdapter) callconv(.winapi) u32,
    // IDXGIObject
    setPrivateData: *const fn (*IDXGIAdapter, *const GUID, UINT, *const anyopaque) callconv(.winapi) HRESULT,
    setPrivateDataInterface: *const fn (*IDXGIAdapter, *const GUID, *const IUnknown) callconv(.winapi) HRESULT,
    getPrivateData: *const fn (*IDXGIAdapter, *const GUID, *UINT, ?*anyopaque) callconv(.winapi) HRESULT,
    getParent: *const fn (*IDXGIAdapter, *const GUID, **anyopaque) callconv(.winapi) HRESULT,
    // IDXGIAdapter
    enumOutputs: *const fn (*IDXGIAdapter, UINT, **anyopaque) callconv(.winapi) HRESULT,
    getDesc: *const fn (*IDXGIAdapter, *anyopaque) callconv(.winapi) HRESULT,
    checkInterfaceSupport: *const fn (*IDXGIAdapter, *const GUID, *LARGE_INTEGER) callconv(.winapi) HRESULT,
};

// ============================================================================
// External Functions
// ============================================================================

pub extern "d3d11" fn D3D11CreateDevice(
    adapter: ?*anyopaque,
    driver_type: D3D_DRIVER_TYPE,
    software: HMODULE,
    flags: D3D11_CREATE_DEVICE_FLAG,
    p_feature_levels: ?[*]const D3D_FEATURE_LEVEL,
    feature_levels: UINT,
    sdk_version: UINT,
    out_device: ?**ID3D11Device,
    out_feature_level: ?*D3D_FEATURE_LEVEL,
    out_context: ?**ID3D11DeviceContext,
) callconv(.winapi) HRESULT;

pub extern "dxgi" fn CreateDXGIFactory2(
    flags: UINT,
    riid: REFGUID,
    out: *?*anyopaque,
) callconv(.winapi) HRESULT;

pub const ID3DBlob = extern struct {
    vtable: *const ID3DBlobVTable,

    pub fn getBufferPointer(self: *ID3DBlob) ?*anyopaque {
        return self.vtable.getBufferPointer(self);
    }

    pub fn getBufferSize(self: *ID3DBlob) SIZE_T {
        return self.vtable.getBufferSize(self);
    }
};

pub const ID3DBlobVTable = extern struct {
    queryInterface: *const fn (*ID3DBlob, *const GUID, **anyopaque) callconv(.winapi) HRESULT,
    addRef: *const fn (*ID3DBlob) callconv(.winapi) c_uint,
    release: *const fn (*ID3DBlob) callconv(.winapi) c_uint,
    getBufferPointer: *const fn (*ID3DBlob) callconv(.winapi) ?*anyopaque,
    getBufferSize: *const fn (*ID3DBlob) callconv(.winapi) SIZE_T,
};

pub extern "d3dcompiler" fn D3DCompile(
    src_data: ?*const anyopaque,
    src_data_size: SIZE_T,
    source_name: ?[*:0]const u8,
    defines: ?*const anyopaque,
    include: ?*const anyopaque,
    entrypoint: [*:0]const u8,
    target: [*:0]const u8,
    flags1: UINT,
    flags2: UINT,
    out_code: ?**anyopaque,
    out_msgs: ?**anyopaque,
) callconv(.winapi) HRESULT;

// ============================================================================
// DirectComposition (dcomp.dll)
// ============================================================================

pub const IDCompositionDevice = extern struct {
    vtable: *const IDCompositionDeviceVTable,

    pub fn createTargetForHwnd(self: *IDCompositionDevice, hwnd: HWND, topmost: BOOL, out: **IDCompositionTarget) HRESULT {
        return self.vtable.createTargetForHwnd(self, hwnd, topmost, out);
    }

    pub fn createVisual(self: *IDCompositionDevice, out: **IDCompositionVisual) HRESULT {
        return self.vtable.createVisual(self, out);
    }

    pub fn commit(self: *IDCompositionDevice) HRESULT {
        return self.vtable.commit(self);
    }
};

pub const IDCompositionDeviceVTable = extern struct {
    // IUnknown
    queryInterface: *const fn (*IDCompositionDevice, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    addRef: *const fn (*IDCompositionDevice) callconv(.winapi) u32,
    release: *const fn (*IDCompositionDevice) callconv(.winapi) u32,
    // IDCompositionDevice
    commit: *const fn (*IDCompositionDevice) callconv(.winapi) HRESULT,
    waitForCommitCompletion: *const fn (*IDCompositionDevice) callconv(.winapi) void,
    getFrameStatistics: *const fn (*IDCompositionDevice, *anyopaque) callconv(.winapi) HRESULT,
    createTargetForHwnd: *const fn (*IDCompositionDevice, HWND, BOOL, **IDCompositionTarget) callconv(.winapi) HRESULT,
    createVisual: *const fn (*IDCompositionDevice, **IDCompositionVisual) callconv(.winapi) HRESULT,
};

pub const IID_IDCompositionDevice = GUID.init(0xc37ea93a, 0xe7aa, 0x450d, .{ 0xb1, 0x6f, 0x97, 0x46, 0xcb, 0x04, 0x07, 0xf3 });

pub const IDCompositionTarget = extern struct {
    vtable: *const IDCompositionTargetVTable,

    pub fn setRoot(self: *IDCompositionTarget, visual: *IDCompositionVisual) HRESULT {
        return self.vtable.setRoot(self, visual);
    }
};

pub const IDCompositionTargetVTable = extern struct {
    // IUnknown
    queryInterface: *const fn (*IDCompositionTarget, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    addRef: *const fn (*IDCompositionTarget) callconv(.winapi) u32,
    release: *const fn (*IDCompositionTarget) callconv(.winapi) u32,
    // IDCompositionTarget
    setRoot: *const fn (*IDCompositionTarget, *IDCompositionVisual) callconv(.winapi) HRESULT,
};

pub const IDCompositionVisual = extern struct {
    vtable: *const IDCompositionVisualVTable,

    pub fn setOffsetX(self: *IDCompositionVisual, value: f32) HRESULT {
        return self.vtable.setOffsetX(self, value);
    }

    pub fn setOffsetY(self: *IDCompositionVisual, value: f32) HRESULT {
        return self.vtable.setOffsetY(self, value);
    }

    pub fn setContent(self: *IDCompositionVisual, content: ?*IUnknown) HRESULT {
        return self.vtable.setContent(self, content);
    }

    pub fn addVisual(
        self: *IDCompositionVisual,
        visual: *IDCompositionVisual,
        insert_above: BOOL,
        reference_visual: ?*IDCompositionVisual,
    ) HRESULT {
        return self.vtable.addVisual(self, visual, insert_above, reference_visual);
    }

    pub fn removeVisual(self: *IDCompositionVisual, visual: *IDCompositionVisual) HRESULT {
        return self.vtable.removeVisual(self, visual);
    }
};

pub const IDCompositionVisualVTable = extern struct {
    // IUnknown (0-2)
    queryInterface: *const fn (*IDCompositionVisual, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    addRef: *const fn (*IDCompositionVisual) callconv(.winapi) u32,
    release: *const fn (*IDCompositionVisual) callconv(.winapi) u32,
    // IDCompositionVisual (3-19)
    // SetOffsetX has two overloads — each gets its own vtable slot
    setOffsetX: *const fn (*IDCompositionVisual, f32) callconv(.winapi) HRESULT,
    setOffsetXAnimated: *const fn (*IDCompositionVisual, *anyopaque) callconv(.winapi) HRESULT,
    // SetOffsetY has two overloads
    setOffsetY: *const fn (*IDCompositionVisual, f32) callconv(.winapi) HRESULT,
    setOffsetYAnimated: *const fn (*IDCompositionVisual, *anyopaque) callconv(.winapi) HRESULT,
    // SetTransform has two overloads
    setTransform: *const fn (*IDCompositionVisual, *const anyopaque) callconv(.winapi) HRESULT,
    setTransformAnimated: *const fn (*IDCompositionVisual, *anyopaque) callconv(.winapi) HRESULT,
    setTransformParent: *const fn (*IDCompositionVisual, ?*IDCompositionVisual) callconv(.winapi) HRESULT,
    setEffect: *const fn (*IDCompositionVisual, *anyopaque) callconv(.winapi) HRESULT,
    setBitmapInterpolationMode: *const fn (*IDCompositionVisual, u32) callconv(.winapi) HRESULT,
    setBorderMode: *const fn (*IDCompositionVisual, u32) callconv(.winapi) HRESULT,
    // SetClip has two overloads
    setClip: *const fn (*IDCompositionVisual, *const anyopaque) callconv(.winapi) HRESULT,
    setClipAnimated: *const fn (*IDCompositionVisual, *anyopaque) callconv(.winapi) HRESULT,
    setContent: *const fn (*IDCompositionVisual, ?*IUnknown) callconv(.winapi) HRESULT,
    addVisual: *const fn (*IDCompositionVisual, *IDCompositionVisual, BOOL, ?*IDCompositionVisual) callconv(.winapi) HRESULT,
    removeVisual: *const fn (*IDCompositionVisual, *IDCompositionVisual) callconv(.winapi) HRESULT,
    removeAllVisuals: *const fn (*IDCompositionVisual) callconv(.winapi) HRESULT,
    setCompositeMode: *const fn (*IDCompositionVisual, u32) callconv(.winapi) HRESULT,
};

pub extern "dcomp" fn DCompositionCreateDevice(
    dxgi_device: ?*IUnknown,
    iid: REFGUID,
    out: *?*anyopaque,
) callconv(.winapi) HRESULT;

pub extern "user32" fn GetClientRect(
    hWnd: HWND,
    lpRect: *RECT,
) callconv(.winapi) BOOL;
