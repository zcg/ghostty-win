const std = @import("std");
const Allocator = std.mem.Allocator;
const api = @import("api.zig");

const log = std.log.scoped(.d3d11);

/// A handle to a D3D11 buffer that optionally includes its shader resource view.
/// This is the type exposed as the `buffer` field of Buffer(T), so that
/// generic.zig can pass it into RenderPass.Step.buffers and the render pass
/// can access both the raw buffer and the SRV.
pub const BufferHandle = struct {
    ptr: *api.ID3D11Buffer,
    srv: ?*api.ID3D11ShaderResourceView = null,
    stride: api.UINT = 0,
};

/// Options for initializing a buffer.
pub const Options = struct {
    device: *api.ID3D11Device,
    device_context: *api.ID3D11DeviceContext,
    usage: api.D3D11_USAGE = .default,
    cpu_access_flags: api.D3D11_CPU_ACCESS_FLAG = .{},
    bind_flags: api.D3D11_BIND_FLAG = .{},
    misc_flags: api.D3D11_RESOURCE_MISC_FLAG = .{},
    /// Stride for structured buffers. Set to @sizeOf(T) for StructuredBuffer<T>.
    structure_byte_stride: api.UINT = 0,
};

/// D3D11 GPU buffer for a certain set of equal types.
pub fn Buffer(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Underlying D3D11 buffer handle (includes optional SRV and stride).
        buffer: BufferHandle,

        /// Options this buffer was allocated with.
        opts: Options,

        /// Current allocated length of the data store.
        /// Note this is the number of `T`s, not the size in bytes.
        len: usize,

        /// Device context for operations.
        ctx: *api.ID3D11DeviceContext,

        /// Initialize a buffer with the given length pre-allocated.
        pub fn init(opts: Options, len: usize) !Self {
            // Pre-allocate large buffers to avoid reallocation during resize.
            // AMD drivers crash when buffers are released while the GPU is
            // still using them from a previous frame.
            const min_len = if (opts.bind_flags.constant_buffer) len else @max(len, 16384);
            const alloc_len = min_len;

            // D3D11 constant buffers must have byte_width as a multiple of 16
            const raw_size = alloc_len * @sizeOf(T);
            const aligned_size = if (opts.bind_flags.constant_buffer)
                std.mem.alignForward(usize, raw_size, 16)
            else
                raw_size;

            const desc = api.D3D11_BUFFER_DESC{
                .byte_width = @intCast(aligned_size),
                .usage = opts.usage,
                .bind_flags = opts.bind_flags,
                .cpu_access_flags = opts.cpu_access_flags,
                .misc_flags = opts.misc_flags,
                .structure_byte_stride = opts.structure_byte_stride,
            };

            var buf: *api.ID3D11Buffer = undefined;
            const hr = opts.device.createBuffer(&desc, null, &buf);
            if (hr != api.S_OK) {
                log.err("createBuffer failed: hr=0x{X:0>8} byte_width={} usage={} bind_flags={any} cpu_access={any}", .{
                    @as(u32, @bitCast(hr)), aligned_size, opts.usage, opts.bind_flags, opts.cpu_access_flags,
                });
                return error.BufferCreateFailed;
            }

            // Create SRV if shader_resource bind flag is set
            var srv: ?*api.ID3D11ShaderResourceView = null;
            if (opts.bind_flags.shader_resource) {
                const srv_desc = api.D3D11_SHADER_RESOURCE_VIEW_DESC{
                    .format = .unknown,
                    .view_dimension = .buffer,
                    .u = .{ .buffer = .{
                        .element_offset = 0,
                        .element_width = @intCast(alloc_len),
                    } },
                };
                var srv_raw: *api.ID3D11ShaderResourceView = undefined;
                const srv_hr = opts.device.createShaderResourceView(
                    @ptrCast(buf),
                    &srv_desc,
                    &srv_raw,
                );
                if (srv_hr == api.S_OK) {
                    srv = srv_raw;
                } else {
                    log.err("createShaderResourceView failed: hr=0x{X:0>8} view_dim={} element_width={}", .{
                        @as(u32, @bitCast(srv_hr)), srv_desc.view_dimension, srv_desc.u.buffer.element_width,
                    });
                }
            }

            return .{
                .buffer = .{
                    .ptr = buf,
                    .srv = srv,
                    .stride = @intCast(@sizeOf(T)),
                },
                .opts = opts,
                .len = alloc_len,
                .ctx = opts.device_context,
            };
        }

        /// Init the buffer filled with the given data.
        pub fn initFill(opts: Options, data: []const T) !Self {
            const desc = api.D3D11_BUFFER_DESC{
                .byte_width = @intCast(data.len * @sizeOf(T)),
                .usage = opts.usage,
                .bind_flags = opts.bind_flags,
                .cpu_access_flags = opts.cpu_access_flags,
                .misc_flags = opts.misc_flags,
                .structure_byte_stride = opts.structure_byte_stride,
            };

            const init_data = api.D3D11_SUBRESOURCE_DATA{
                .p_sys_mem = @ptrCast(data.ptr),
                .sys_mem_pitch = 0,
                .sys_mem_slice_pitch = 0,
            };

            var buf: *api.ID3D11Buffer = undefined;
            const hr = opts.device.createBuffer(&desc, &init_data, &buf);
            if (hr != api.S_OK) return error.BufferCreateFailed;

            // Create SRV if shader_resource bind flag is set
            var srv: ?*api.ID3D11ShaderResourceView = null;
            if (opts.bind_flags.shader_resource) {
                const srv_desc = api.D3D11_SHADER_RESOURCE_VIEW_DESC{
                    .format = .unknown,
                    .view_dimension = .buffer,
                    .u = .{ .buffer = .{
                        .element_offset = 0,
                        .element_width = @intCast(data.len),
                    } },
                };
                var srv_raw: *api.ID3D11ShaderResourceView = undefined;
                const srv_hr = opts.device.createShaderResourceView(
                    @ptrCast(buf),
                    &srv_desc,
                    &srv_raw,
                );
                if (srv_hr == api.S_OK) {
                    srv = srv_raw;
                } else {
                    log.err("createShaderResourceView failed: hr=0x{X:0>8} view_dim={} element_width={}", .{
                        @as(u32, @bitCast(srv_hr)), srv_desc.view_dimension, srv_desc.u.buffer.element_width,
                    });
                }
            }

            return .{
                .buffer = .{
                    .ptr = buf,
                    .srv = srv,
                    .stride = @intCast(@sizeOf(T)),
                },
                .opts = opts,
                .len = data.len,
                .ctx = opts.device_context,
            };
        }

        pub fn deinit(self: Self) void {
            if (self.buffer.srv) |s| {
                _ = api.releaseCOM(@ptrCast(s));
            }
            _ = api.releaseCOM(@ptrCast(self.buffer.ptr));
        }

        /// Sync new contents to the buffer using UpdateSubresource.
        /// If data exceeds buffer size, the buffer is reallocated.
        pub fn sync(self: *Self, data: []const T) !void {
            // If we need more space, reallocate the buffer (like OpenGL does).
            if (data.len > self.len) {
                const new_len = data.len * 2;
                // Release old buffer and SRV
                if (self.buffer.srv) |s| {
                    _ = api.releaseCOM(@ptrCast(s));
                    self.buffer.srv = null;
                }
                _ = api.releaseCOM(@ptrCast(self.buffer.ptr));

                // Create new buffer with larger size
                const aligned_size = if (self.opts.bind_flags.constant_buffer)
                    std.mem.alignForward(usize, new_len * @sizeOf(T), 16)
                else
                    new_len * @sizeOf(T);

                const desc = api.D3D11_BUFFER_DESC{
                    .byte_width = @intCast(aligned_size),
                    .usage = self.opts.usage,
                    .bind_flags = self.opts.bind_flags,
                    .cpu_access_flags = self.opts.cpu_access_flags,
                    .misc_flags = self.opts.misc_flags,
                    .structure_byte_stride = self.opts.structure_byte_stride,
                };

                var buf: *api.ID3D11Buffer = undefined;
                const hr = self.opts.device.createBuffer(&desc, null, &buf);
                if (hr != api.S_OK) {
                    log.err("buffer realloc failed: hr=0x{X:0>8}", .{@as(u32, @bitCast(hr))});
                    return error.BufferCreateFailed;
                }
                self.buffer.ptr = buf;

                // Recreate SRV if needed
                if (self.opts.bind_flags.shader_resource) {
                    var srv: ?*api.ID3D11ShaderResourceView = null;
                    const srv_desc = api.D3D11_SHADER_RESOURCE_VIEW_DESC{
                        .format = .unknown,
                        .view_dimension = .buffer,
                        .u = .{ .buffer = .{
                            .element_offset = 0,
                            .element_width = @intCast(new_len),
                        } },
                    };
                    var srv_raw: *api.ID3D11ShaderResourceView = undefined;
                    const srv_hr = self.opts.device.createShaderResourceView(
                        @ptrCast(buf),
                        &srv_desc,
                        &srv_raw,
                    );
                    if (srv_hr == api.S_OK) {
                        srv = srv_raw;
                    }
                    self.buffer.srv = srv;
                }

                self.len = new_len;
            }

            // Update only the portion we have data for.
            // Note: constant buffers must be updated with pDstBox = null
            // (D3D11 requires full CB updates). For other buffer types,
            // we use a BOX to avoid reading beyond data.len.
            if (self.opts.bind_flags.constant_buffer) {
                self.ctx.updateSubresource(
                    @ptrCast(self.buffer.ptr),
                    0,
                    null,
                    data.ptr,
                    0,
                    0,
                );
            } else {
                const box = api.D3D11_BOX{
                    .left = 0,
                    .top = 0,
                    .front = 0,
                    .right = @intCast(data.len * @sizeOf(T)),
                    .bottom = 1,
                    .back = 1,
                };
                // For buffers, SrcRowPitch and SrcDepthPitch must be 0.
                self.ctx.updateSubresource(
                    @ptrCast(self.buffer.ptr),
                    0,
                    &box,
                    data.ptr,
                    0,
                    0,
                );
            }
        }

        /// Sync using Map/Unmap for dynamic buffers.
        pub fn syncMap(self: *Self, data: []const T) !void {
            var mapped: api.D3D11_MAPPED_SUBRESOURCE = undefined;
            const hr = self.ctx.map(
                @ptrCast(self.buffer.ptr),
                0,
                .write_discard,
                0,
                &mapped,
            );
            if (hr != api.S_OK) return error.MapFailed;
            defer self.ctx.unmap(@ptrCast(self.buffer.ptr), 0);

            const copy_len = @min(data.len, self.len);
            const dst: [*]T = @ptrCast(@alignCast(mapped.pData orelse return error.NullPointer));
            @memcpy(dst[0..copy_len], data[0..copy_len]);
        }

        /// Like Buffer.sync but takes data from an array of ArrayLists.
        /// If total data exceeds buffer size, the buffer is reallocated.
        pub fn syncFromArrayLists(self: *Self, lists: []const std.ArrayListUnmanaged(T)) !usize {
            var total_len: usize = 0;
            for (lists) |list| {
                total_len += list.items.len;
            }

            if (total_len > self.len) {
                const new_len = total_len * 2;
                if (self.buffer.srv) |s| {
                    _ = api.releaseCOM(@ptrCast(s));
                    self.buffer.srv = null;
                }
                _ = api.releaseCOM(@ptrCast(self.buffer.ptr));

                const aligned_size = if (self.opts.bind_flags.constant_buffer)
                    std.mem.alignForward(usize, new_len * @sizeOf(T), 16)
                else
                    new_len * @sizeOf(T);

                const desc = api.D3D11_BUFFER_DESC{
                    .byte_width = @intCast(aligned_size),
                    .usage = self.opts.usage,
                    .bind_flags = self.opts.bind_flags,
                    .cpu_access_flags = self.opts.cpu_access_flags,
                    .misc_flags = self.opts.misc_flags,
                    .structure_byte_stride = self.opts.structure_byte_stride,
                };

                var buf: *api.ID3D11Buffer = undefined;
                const hr = self.opts.device.createBuffer(&desc, null, &buf);
                if (hr != api.S_OK) return error.BufferCreateFailed;
                self.buffer.ptr = buf;

                if (self.opts.bind_flags.shader_resource) {
                    var srv_raw: *api.ID3D11ShaderResourceView = undefined;
                    const srv_desc = api.D3D11_SHADER_RESOURCE_VIEW_DESC{
                        .format = .unknown,
                        .view_dimension = .buffer,
                        .u = .{ .buffer = .{
                            .element_offset = 0,
                            .element_width = @intCast(new_len),
                        } },
                    };
                    const srv_hr = self.opts.device.createShaderResourceView(
                        @ptrCast(buf),
                        &srv_desc,
                        &srv_raw,
                    );
                    if (srv_hr == api.S_OK) {
                        self.buffer.srv = srv_raw;
                    }
                }
                self.len = new_len;
            }

            if (self.opts.usage == .dynamic) {
                var mapped: api.D3D11_MAPPED_SUBRESOURCE = undefined;
                const hr = self.ctx.map(
                    @ptrCast(self.buffer.ptr),
                    0,
                    .write_discard,
                    0,
                    &mapped,
                );
                if (hr != api.S_OK) return error.MapFailed;
                defer self.ctx.unmap(@ptrCast(self.buffer.ptr), 0);

                const dst: [*]T = @ptrCast(@alignCast(mapped.pData orelse return error.NullPointer));
                var offset: usize = 0;
                for (lists) |list| {
                    @memcpy(dst[offset .. offset + list.items.len], list.items);
                    offset += list.items.len;
                }
            } else {
                var offset: usize = 0;
                for (lists) |list| {
                    if (list.items.len == 0) continue;
                    const byte_offset = offset * @sizeOf(T);
                    const byte_size = list.items.len * @sizeOf(T);

                    const box = api.D3D11_BOX{
                        .left = @intCast(byte_offset),
                        .top = 0,
                        .front = 0,
                        .right = @intCast(byte_offset + byte_size),
                        .bottom = 1,
                        .back = 1,
                    };
                    // For buffers, SrcRowPitch and SrcDepthPitch must be 0.
                    self.ctx.updateSubresource(
                        @ptrCast(self.buffer.ptr),
                        0,
                        &box,
                        list.items.ptr,
                        0,
                        0,
                    );
                    offset += list.items.len;
                }
            }

            return total_len;
        }
    };
}
