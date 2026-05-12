//! D3D11 renderer backend for Ghostty on Windows.
//!
//! This implements the GraphicsAPI interface required by GenericRenderer,
//! using Direct3D 11 with DXGI swap chain for presentation.
//!
//! All swap chains use CreateSwapChainForComposition + DirectComposition,
//! which provides a unified alpha-capable presentation path. This enables
//! DWM backdrop effects (Acrylic/Mica/Mica Alt) to show through when
//! background-opacity < 1.0, and also works correctly for opaque windows.

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const build_config = @import("../build_config.zig");
const apprt = @import("../apprt.zig");
const configpkg = @import("../config.zig");
const font = @import("../font/main.zig");
const renderer = @import("../renderer.zig");
const shadertoy = @import("shadertoy.zig");

const api = @import("d3d11/api.zig");
const d3d11_buffer = @import("d3d11/buffer.zig");
const d3d11_texture = @import("d3d11/Texture.zig");
const d3d11_sampler = @import("d3d11/Sampler.zig");

const log = std.log.scoped(.d3d11_renderer);

pub const GraphicsAPI = D3D11;
pub const Target = @import("d3d11/Target.zig").Target;
pub const Frame = @import("d3d11/Frame.zig").Frame;
pub const RenderPass = @import("d3d11/RenderPass.zig").RenderPass;
pub const Pipeline = @import("d3d11/Pipeline.zig").Pipeline;
pub const Buffer = @import("d3d11/buffer.zig").Buffer;
pub const Sampler = @import("d3d11/Sampler.zig").Sampler;
pub const Texture = d3d11_texture.Texture;
pub const shaders = @import("d3d11/shaders.zig");

pub const custom_shader_target: shadertoy.Target = .hlsl;
pub const custom_shader_y_is_down = true; // D3D Y-axis is top-down
pub const swap_chain_count = 2; // Double buffering for flip model

const D3D11 = @This();

// Device and context
device: *api.ID3D11Device,
device_context: *api.ID3D11DeviceContext,

// Swap chain for the current surface (always composition-based)
swap_chain: ?*api.IDXGISwapChain1 = null,

// Back buffer from the swap chain
back_buffer: ?*api.ID3D11Texture2D = null,

// Blending config
blending: configpkg.Config.AlphaBlending,

// Surface HWND for reading client area size
hwnd: ?*anyopaque = null,

// Track whether threadEnter has successfully initialized DComp resources.
// This prevents re-creation after threadExit cleaned them up (deinit path).
dcomp_exited: bool = false,

// DirectComposition objects (always present — unified path)
dcomp_device: ?*api.IDCompositionDevice = null,
dcomp_target: ?*api.IDCompositionTarget = null,
dcomp_visual: ?*api.IDCompositionVisual = null,

// Last presented target (for re-presenting)
last_target: ?Target = null,

// Default sampler for textures (auto-bound when step() omits samplers)
default_sampler: Sampler,

// Allocator
alloc: Allocator,

pub fn init(alloc: Allocator, opts: renderer.Options) !D3D11 {
    // Create D3D11 device
    var device: *api.ID3D11Device = undefined;
    var feature_level: api.D3D_FEATURE_LEVEL = undefined;
    var device_context: *api.ID3D11DeviceContext = undefined;

    const hr = api.D3D11CreateDevice(
        null, // Default adapter
        .hardware,
        null, // No software rasterizer
        .{}, // No creation flags
        null, // Default feature levels
        0,
        7, // D3D11_SDK_VERSION
        &device,
        &feature_level,
        &device_context,
    );

    if (hr != api.S_OK) {
        log.err("D3D11CreateDevice failed: 0x{X:0>8}", .{@as(u32, @bitCast(hr))});
        return error.DeviceCreateFailed;
    }

    log.info("D3D11 device created, feature level: {s}", .{
        switch (feature_level) {
            .@"11_0" => "11.0",
            .@"11_1" => "11.1",
            .@"12_0" => "12.0",
            .@"12_1" => "12.1",
            else => "unknown",
        },
    });

    const default_sampler = try Sampler.init(samplerOptionsInternal(device));
    errdefer default_sampler.deinit();

    return .{
        .alloc = alloc,
        .device = device,
        .device_context = device_context,
        .swap_chain = null,
        .back_buffer = null,
        .blending = opts.config.blending,
        .default_sampler = default_sampler,
    };
}

fn samplerOptionsInternal(device: *api.ID3D11Device) Sampler.Options {
    return .{
        .device = device,
        .filter = .min_mag_mip_linear,
        .address_u = .clamp,
        .address_v = .clamp,
        .address_w = .clamp,
    };
}

pub fn deinit(self: *D3D11) void {
    if (self.dcomp_visual) |v| _ = api.releaseCOM(@ptrCast(v));
    if (self.dcomp_target) |t| _ = api.releaseCOM(@ptrCast(t));
    if (self.dcomp_device) |d| _ = api.releaseCOM(@ptrCast(d));
    if (self.back_buffer) |bb| _ = api.releaseCOM(@ptrCast(bb));
    if (self.swap_chain) |sc| _ = api.releaseCOM(@ptrCast(sc));
    self.default_sampler.deinit();
    _ = api.releaseCOM(@ptrCast(self.device_context));
    _ = api.releaseCOM(@ptrCast(self.device));
}

/// Called from the main thread during surface initialization.
/// For D3D11, this is a no-op. Swap chain creation is deferred to threadEnter.
pub fn surfaceInit(surface: *apprt.Surface) !void {
    _ = surface;
}

/// Called from the main thread after surface init, before render thread starts.
pub fn finalizeSurfaceInit(self: *const D3D11, surface: *apprt.Surface) !void {
    _ = self;
    _ = surface;
}

/// Called when the render thread enters. Creates the composition swap chain
/// and DirectComposition visual tree for the surface HWND.
/// Note: self is *const due to GenericRenderer's calling convention, but we
/// need to mutate fields. This is safe because the render thread has exclusive
/// access at this point.
///
/// This may be called multiple times: once from the render thread on startup,
/// and again from the main thread after the render thread exits (so that
/// deinit() can safely access GPU resources). On the second call, dcomp_exited
/// will be true (set by threadExit), so we skip re-creation — deinit() only
/// needs the device/context.
pub fn threadEnter(self: *const D3D11, surface: *apprt.Surface) !void {
    const mutable_self = @constCast(self);
    if (build_config.app_runtime != .win32) return;
    const win32_surface: *apprt.win32.Surface = surface;

    // If DComp resources are already set up (initial call succeeded and
    // threadExit hasn't been called yet), nothing to do.
    if (self.swap_chain != null) return;

    // If threadExit already ran, this is a re-entry from the main thread
    // during Surface.deinit(). No point re-creating resources that will
    // be immediately deinit'd.
    if (self.dcomp_exited) {
        log.info("threadEnter: skipping DComp/swap chain creation (re-entry after threadExit)", .{});
        mutable_self.hwnd = win32_surface.hwnd;
        return;
    }

    // First call: all fields are null, dcomp_exited is false.
    // Proceed with normal initialization.
    mutable_self.hwnd = win32_surface.hwnd;

    // Get the DXGI device from the D3D11 device via QueryInterface.
    var dxgi_device: *api.IDXGIDevice = undefined;
    const qi_hr = self.device.queryInterface(
        &api.IID_IDXGIDevice,
        @ptrCast(&dxgi_device),
    );
    if (qi_hr != api.S_OK) {
        log.err("QueryInterface for IDXGIDevice failed: 0x{X:0>8}", .{@as(u32, @bitCast(qi_hr))});
        return error.DXGIDeviceNotFound;
    }
    defer _ = dxgi_device.vtable.release(dxgi_device);

    // Get the adapter from the DXGI device
    var adapter: *api.IDXGIAdapter = undefined;
    const adapter_hr = dxgi_device.getAdapter(&adapter);
    if (adapter_hr != api.S_OK) {
        log.err("GetAdapter failed: 0x{X:0>8}", .{@as(u32, @bitCast(adapter_hr))});
        return error.AdapterNotFound;
    }
    defer _ = adapter.vtable.release(adapter);

    // Get the parent factory from the adapter
    var factory_raw: *anyopaque = undefined;
    const factory_hr = adapter.getParent(&api.IID_IDXGIFactory2, &factory_raw);
    if (factory_hr != api.S_OK) {
        log.err("GetParent for IDXGIFactory2 failed: 0x{X:0>8}", .{@as(u32, @bitCast(factory_hr))});
        return error.FactoryCreateFailed;
    }
    const factory: *api.IDXGIFactory2 = @ptrCast(@alignCast(factory_raw));
    defer _ = api.releaseCOM(@ptrCast(factory));

    // === Create DirectComposition device ===
    var dcomp_device_raw: ?*anyopaque = undefined;
    const dcomp_hr = api.DCompositionCreateDevice(
        @ptrCast(dxgi_device),
        &api.IID_IDCompositionDevice,
        &dcomp_device_raw,
    );
    if (dcomp_hr != api.S_OK) {
        log.err("DCompositionCreateDevice failed: 0x{X:0>8}", .{@as(u32, @bitCast(dcomp_hr))});
        return error.DCompCreateFailed;
    }
    mutable_self.dcomp_device = @ptrCast(@alignCast(dcomp_device_raw.?));

    // === Create composition target for the HWND ===
    var dcomp_target: *api.IDCompositionTarget = undefined;
    const target_hr = mutable_self.dcomp_device.?.createTargetForHwnd(win32_surface.hwnd, 1, &dcomp_target);
    if (target_hr != api.S_OK) {
        log.err("CreateTargetForHwnd failed: 0x{X:0>8}", .{@as(u32, @bitCast(target_hr))});
        return error.DCompTargetCreateFailed;
    }
    mutable_self.dcomp_target = dcomp_target;

    // === Create a visual for the swap chain ===
    var dcomp_visual: *api.IDCompositionVisual = undefined;
    const visual_hr = mutable_self.dcomp_device.?.createVisual(&dcomp_visual);
    if (visual_hr != api.S_OK) {
        log.err("CreateVisual failed: 0x{X:0>8}", .{@as(u32, @bitCast(visual_hr))});
        return error.DCompVisualCreateFailed;
    }
    mutable_self.dcomp_visual = dcomp_visual;

    // === Create the composition swap chain ===
    // Always use premultiplied alpha so DWM backdrop effects can show through
    // when the renderer outputs alpha < 1.0 in the background. For opaque
    // windows (alpha = 1.0 everywhere), this is equivalent to an opaque swap chain.
    // Note: Composition swap chains don't auto-derive size from HWND,
    // so we read the current surface size.
    // Save HWND for later resize detection
    mutable_self.hwnd = win32_surface.hwnd;

    const swap_width: u32 = if (win32_surface.width > 0) @intCast(win32_surface.width) else 1;
    const swap_height: u32 = if (win32_surface.height > 0) @intCast(win32_surface.height) else 1;

    var swap_chain_desc = api.DXGI_SWAP_CHAIN_DESC1{
        .width = swap_width,
        .height = swap_height,
        .format = .b8g8r8a8_unorm,
        .stereo = 0,
        .sample_desc = .{ .count = 1, .quality = 0 },
        .buffer_usage = api.DXGI_USAGE_RENDER_TARGET_OUTPUT,
        .buffer_count = 2,
        .scaling = .stretch,
        .swap_effect = .flip_sequential,
        .alpha_mode = .premultiplied,
        .flags = 0,
    };

    var swap_chain: *api.IDXGISwapChain1 = undefined;
    const sc_hr = factory.createSwapChainForComposition(
        @ptrCast(self.device),
        &swap_chain_desc,
        null,
        &swap_chain,
    );
    if (sc_hr != api.S_OK) {
        log.err("CreateSwapChainForComposition failed: 0x{X:0>8}", .{@as(u32, @bitCast(sc_hr))});
        return error.SwapChainCreateFailed;
    }
    mutable_self.swap_chain = swap_chain;

    const content_hr = dcomp_visual.setContent(@ptrCast(swap_chain));
    if (content_hr != api.S_OK) {
        log.err("Visual::SetContent failed: 0x{X:0>8}", .{@as(u32, @bitCast(content_hr))});
        return error.DCompSetContentFailed;
    }

    // Set the visual as the root of the composition target
    const root_hr = dcomp_target.setRoot(dcomp_visual);
    if (root_hr != api.S_OK) {
        log.err("Target::SetRoot failed: 0x{X:0>8}", .{@as(u32, @bitCast(root_hr))});
        return error.DCompSetRootFailed;
    }

    // Commit the composition
    const commit_hr = mutable_self.dcomp_device.?.commit();
    if (commit_hr != api.S_OK) {
        log.err("DComp::Commit failed: 0x{X:0>8}", .{@as(u32, @bitCast(commit_hr))});
        return error.DCompCommitFailed;
    }

    // Get the back buffer from the swap chain
    var back_buffer_raw: ?*anyopaque = undefined;
    const bb_hr = swap_chain.getBuffer(0, &api.IID_ID3D11Texture2D, &back_buffer_raw);
    if (bb_hr != api.S_OK) {
        log.err("GetBuffer failed: 0x{X:0>8}", .{@as(u32, @bitCast(bb_hr))});
        return error.BackBufferGetFailed;
    }
    mutable_self.back_buffer = @ptrCast(@alignCast(back_buffer_raw.?));

    log.info("Composition swap chain created ({}x{})", .{ swap_width, swap_height });
}

/// Called when the render thread exits.
/// Clean up per-thread GPU state so that the main thread can safely
/// call deinit() afterwards without DComp asynchronously accessing
/// freed resources.
pub fn threadExit(self: *const D3D11) void {
    const mutable_self = @constCast(self);
    log.info("D3D11 threadExit: cleaning up render thread resources", .{});

    // Unbind all GPU state to ensure nothing references our resources.
    // Use ClearState for thoroughness — it unbinds everything (shaders,
    // buffers, views, samplers, etc.), not just RTV/SRV.
    self.device_context.clearState();

    // Flush GPU to ensure all pending work completes before we release resources
    self.device_context.flush();

    // Detach the swap chain from the DComp visual before releasing anything.
    // This prevents DComp from trying to read from the swap chain after release.
    if (self.dcomp_visual) |visual| {
        _ = visual.setContent(null);
    }
    // Commit the DComp change so DWM stops referencing our swap chain
    if (self.dcomp_device) |dev| {
        _ = dev.commit();
    }

    // Release DComp objects (visual → target → device, reverse creation order)
    if (self.dcomp_visual) |v| {
        _ = api.releaseCOM(@ptrCast(v));
        mutable_self.dcomp_visual = null;
    }
    if (self.dcomp_target) |t| {
        _ = api.releaseCOM(@ptrCast(t));
        mutable_self.dcomp_target = null;
    }
    if (self.dcomp_device) |d| {
        _ = api.releaseCOM(@ptrCast(d));
        mutable_self.dcomp_device = null;
    }

    // Release swap chain and back buffer
    if (self.back_buffer) |bb| {
        _ = api.releaseCOM(@ptrCast(bb));
        mutable_self.back_buffer = null;
    }
    if (self.swap_chain) |sc| {
        _ = api.releaseCOM(@ptrCast(sc));
        mutable_self.swap_chain = null;
    }

    log.info("D3D11 threadExit: render thread cleanup complete", .{});

    // Mark that threadExit has run, so the next threadEnter call
    // (from main thread during Surface.deinit) won't try to re-create
    // DComp resources.
    mutable_self.dcomp_exited = true;
}

/// Actions taken before `drawFrame` begins.
pub fn drawFrameStart(self: *D3D11) void {
    _ = self;
}

/// Actions taken after `drawFrame` is done.
pub fn drawFrameEnd(self: *D3D11) void {
    // Clear all device context state after each frame to prevent stale
    // references from accumulating. This is especially important for
    // D3D11 where bound RTVs/SRVs can reference swap chain buffers.
    self.device_context.clearState();
}

pub fn prepareHostRecreate(self: *const D3D11) void {
    const mutable_self = @constCast(self);
    mutable_self.dcomp_exited = false;
}

// One-shot diagnostic flag for first present
var diag_logged = std.atomic.Value(bool).init(false);

pub fn initShaders(self: *const D3D11, alloc: Allocator, custom_shaders: []const [:0]const u8) !shaders.Shaders {
    return shaders.Shaders.init(self.device, alloc, custom_shaders);
}

pub fn surfaceSize(self: *D3D11) !struct { width: u32, height: u32 } {
    // Read from the HWND for the most up-to-date size.
    if (self.hwnd) |hwnd| {
        var rect: api.RECT = undefined;
        if (api.GetClientRect(hwnd, &rect) != 0) {
            const w: u32 = @intCast(@max(1, rect.right - rect.left));
            const h: u32 = @intCast(@max(1, rect.bottom - rect.top));
            if (w > 0 and h > 0) {
                return .{ .width = w, .height = h };
            }
        }
    }
    const sc = self.swap_chain orelse return error.SwapChainNotReady;
    var desc: api.DXGI_SWAP_CHAIN_DESC1 = undefined;
    const hr = sc.getDesc1(&desc);
    if (hr != api.S_OK) return error.SwapChainDescFailed;
    return .{ .width = desc.width, .height = desc.height };
}

pub fn initTarget(self: *const D3D11, width: usize, height: usize) !Target {
    return Target.init(self.device, @intCast(width), @intCast(height), .b8g8r8a8_unorm);
}

pub fn resizeSwapChain(self: *const D3D11, width: u32, height: u32) !void {
    const mutable_self = @constCast(self);
    const sc = self.swap_chain orelse return error.SwapChainNotReady;

    // Check if resize is actually needed
    var desc: api.DXGI_SWAP_CHAIN_DESC1 = undefined;
    if (sc.getDesc1(&desc) == api.S_OK) {
        if (desc.width == width and desc.height == height) return;
    }

    if (self.hwnd) |hwnd| {
        var rect: api.RECT = undefined;
        if (api.GetClientRect(hwnd, &rect) != 0) {
            log.debug("resizeSwapChain hwnd_client={}x{} swap={}x{} target={}x{}", .{
                @max(0, rect.right - rect.left),
                @max(0, rect.bottom - rect.top),
                desc.width,
                desc.height,
                width,
                height,
            });
        }
    }

    log.info("Resizing swap chain: {}x{} -> {}x{}", .{ desc.width, desc.height, width, height });

    // Step 1: Detach the swap chain from DComp visual BEFORE clearing state.
    // DComp holds internal references to swap chain buffers. We must release
    // those references before ResizeBuffers can succeed.
    if (self.dcomp_visual) |visual| {
        _ = visual.setContent(null);
    }
    if (self.dcomp_device) |dev| {
        _ = dev.commit();
    }

    // Step 2: Clear ALL device context state. This unbinds every resource —
    // shaders, vertex buffers, index buffers, constant buffers, shader resources,
    // render targets, samplers, input layouts, etc. Windows Terminal does this
    // before ResizeBuffers and it's the only reliable way to ensure no stale
    // references to swap chain buffers remain bound.
    self.device_context.clearState();

    // Step 3: Flush and wait for GPU to finish all pending work
    self.device_context.flush();

    // Step 4: Release the old back buffer COM reference
    if (self.back_buffer) |bb| {
        _ = api.releaseCOM(@ptrCast(bb));
        mutable_self.back_buffer = null;
    }

    // Step 5: Resize the swap chain buffers
    const resize_hr = sc.resizeBuffers(0, width, height, .b8g8r8a8_unorm, 0);
    if (resize_hr != api.S_OK) {
        log.err("ResizeBuffers failed: 0x{X:0>8}", .{@as(u32, @bitCast(resize_hr))});
        // Try to re-attach the swap chain to DComp even on failure
        if (self.dcomp_visual) |visual| {
            _ = visual.setContent(@ptrCast(sc));
        }
        if (self.dcomp_device) |dev| {
            _ = dev.commit();
        }
        // back_buffer is null — subsequent present() will return SwapChainNotReady
        // rather than attempting copyResource with mismatched sizes.
        return error.PresentFailed;
    }

    // Step 6: Re-acquire the back buffer
    var back_buffer_raw: ?*anyopaque = undefined;
    const bb_hr = sc.getBuffer(0, &api.IID_ID3D11Texture2D, &back_buffer_raw);
    if (bb_hr != api.S_OK) {
        log.err("GetBuffer after resize failed: 0x{X:0>8}", .{@as(u32, @bitCast(bb_hr))});
        if (self.dcomp_visual) |visual| {
            _ = visual.setContent(@ptrCast(sc));
        }
        if (self.dcomp_device) |dev| {
            _ = dev.commit();
        }
        return error.BackBufferGetFailed;
    }
    mutable_self.back_buffer = @ptrCast(@alignCast(back_buffer_raw.?));

    // Step 7: Re-attach the swap chain to the DComp visual
    if (self.dcomp_visual) |visual| {
        const content_hr = visual.setContent(@ptrCast(sc));
        if (content_hr != api.S_OK) {
            log.warn("DComp visual setContent after resize failed: 0x{X:0>8}", .{@as(u32, @bitCast(content_hr))});
        }
    }
    if (self.dcomp_device) |dev| {
        _ = dev.commit();
    }

    log.info("Swap chain resized to {}x{}", .{ width, height });
}

pub fn present(self: *D3D11, target: Target) !void {
    const sc = self.swap_chain orelse return error.SwapChainNotReady;
    const bb = self.back_buffer orelse return error.SwapChainNotReady;

    // Safety check: if target and back buffer sizes don't match, skip this frame.
    // copyResource with mismatched sizes causes undefined GPU behavior (TDR, crash).
    // This can happen if resizeSwapChain failed but drawFrame continued.
    if (target.width == 0 or target.height == 0) return;
    var sc_desc: api.DXGI_SWAP_CHAIN_DESC1 = undefined;
    if (sc.getDesc1(&sc_desc) == api.S_OK) {
        if (sc_desc.width != target.width or sc_desc.height != target.height) {
            log.warn("present: size mismatch, skipping frame (target={}x{} swap={}x{})", .{
                target.width, target.height, sc_desc.width, sc_desc.height,
            });
            return;
        }
    }

    // Copy the off-screen target to the swap chain back buffer
    self.device_context.copyResource(
        @ptrCast(bb),
        @ptrCast(target.texture),
    );

    // Present: sync_interval=0 means no VSync, flags=0
    const hr = sc.present(0, 0);
    // HRESULT error check: high bit set indicates failure
    if (@as(u32, @bitCast(hr)) & 0x80000000 != 0) {
        if (hr == api.DXGI_ERROR_DEVICE_REMOVED or hr == api.DXGI_ERROR_DEVICE_RESET) {
            log.err("Device lost during present: 0x{X:0>8}", .{@as(u32, @bitCast(hr))});
        } else {
            log.err("Present failed: 0x{X:0>8}", .{@as(u32, @bitCast(hr))});
        }
        return error.PresentFailed;
    }

    // Track last presented target for re-presenting unchanged frames.
    @constCast(self).last_target = target;
}

pub fn presentLastTarget(self: *D3D11) !void {
    if (self.last_target) |target| {
        try self.present(target);
    }
}

pub fn beginFrame(self: *const D3D11, renderer_ptr: *renderer.Renderer, target: *Target) !Frame {
    return Frame.begin(@constCast(self), renderer_ptr, target);
}

// ============================================================================
// Buffer Options
// ============================================================================

pub fn bufferOptions(self: *const D3D11) d3d11_buffer.Options {
    return .{
        .device = self.device,
        .device_context = self.device_context,
        .usage = .default,
        .bind_flags = .{ .vertex_buffer = true },
    };
}

pub fn uniformBufferOptions(self: *const D3D11) d3d11_buffer.Options {
    return .{
        .device = self.device,
        .device_context = self.device_context,
        .usage = .default,
        .cpu_access_flags = .{},
        .bind_flags = .{ .constant_buffer = true },
    };
}

pub fn instanceBufferOptions(self: *const D3D11) d3d11_buffer.Options {
    return .{
        .device = self.device,
        .device_context = self.device_context,
        .usage = .default,
        .cpu_access_flags = .{},
        .bind_flags = .{ .vertex_buffer = true },
    };
}

pub fn fgBufferOptions(self: *const D3D11) d3d11_buffer.Options {
    return .{
        .device = self.device,
        .device_context = self.device_context,
        .usage = .default,
        .bind_flags = .{ .vertex_buffer = true },
    };
}

pub fn bgBufferOptions(self: *const D3D11) d3d11_buffer.Options {
    return .{
        .device = self.device,
        .device_context = self.device_context,
        .usage = .default,
        .bind_flags = .{ .shader_resource = true },
        .misc_flags = .{ .buffer_structured = true },
        .structure_byte_stride = 4, // StructuredBuffer<uint> = 4 bytes per element
    };
}

pub fn imageBufferOptions(self: *const D3D11) d3d11_buffer.Options {
    return .{
        .device = self.device,
        .device_context = self.device_context,
        .usage = .default,
        .cpu_access_flags = .{},
        .bind_flags = .{ .vertex_buffer = true },
    };
}

pub fn bgImageBufferOptions(self: *const D3D11) d3d11_buffer.Options {
    return .{
        .device = self.device,
        .device_context = self.device_context,
        .usage = .default,
        .cpu_access_flags = .{},
        .bind_flags = .{ .vertex_buffer = true },
    };
}

// ============================================================================
// Texture Options
// ============================================================================

pub fn textureOptions(self: *const D3D11) d3d11_texture.Texture.Options {
    return .{
        .device = self.device,
        .device_context = self.device_context,
        .format = .b8g8r8a8_unorm,
        .bind_flags = .{ .shader_resource = true },
    };
}

pub fn samplerOptions(self: *const D3D11) d3d11_sampler.Sampler.Options {
    return .{
        .device = self.device,
        .filter = .min_mag_mip_linear,
        .address_u = .clamp,
        .address_v = .clamp,
        .address_w = .clamp,
    };
}

pub const ImageTextureFormat = enum {
    gray,
    rgba,
    bgra,
};

pub fn imageTextureOptions(self: *const D3D11, format: ImageTextureFormat, srgb: bool) d3d11_texture.Texture.Options {
    _ = srgb;
    return .{
        .device = self.device,
        .device_context = self.device_context,
        .format = switch (format) {
            .gray => .r8_unorm,
            .rgba => .r8g8b8a8_unorm,
            .bgra => .b8g8r8a8_unorm,
        },
        .bind_flags = .{ .shader_resource = true },
    };
}

pub fn initAtlasTexture(self: *const D3D11, atlas: *const font.Atlas) !d3d11_texture.Texture {
    const format: api.DXGI_FORMAT = switch (atlas.format) {
        .grayscale => .r8_unorm,
        .bgra => .b8g8r8a8_unorm,
        else => @panic("unsupported atlas format for D3D11 texture"),
    };

    const desc = api.D3D11_TEXTURE2D_DESC{
        .width = atlas.size,
        .height = atlas.size,
        .mip_levels = 1,
        .array_size = 1,
        .format = format,
        .sample_desc = .{ .count = 1, .quality = 0 },
        .usage = .default,
        .bind_flags = .{ .shader_resource = true },
        .cpu_access_flags = .{},
        .misc_flags = .{},
    };

    return d3d11_texture.Texture.initWithDesc(self.device, self.device_context, &desc, null);
}
