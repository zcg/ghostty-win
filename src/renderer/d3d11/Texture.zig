const std = @import("std");
const api = @import("api.zig");

const log = std.log.scoped(.d3d11);

/// A D3D11 texture on the GPU.
pub const Texture = struct {
    texture: *api.ID3D11Texture2D,
    srv: *api.ID3D11ShaderResourceView,
    rtv: ?*api.ID3D11RenderTargetView = null,
    width: u32,
    height: u32,
    format: api.DXGI_FORMAT,
    ctx: *api.ID3D11DeviceContext,

    pub const Error = error{
        TextureCreateFailed,
        SRVCreateFailed,
    };

    pub const Options = struct {
        device: *api.ID3D11Device,
        device_context: *api.ID3D11DeviceContext,
        format: api.DXGI_FORMAT = .b8g8r8a8_unorm,
        usage: api.D3D11_USAGE = .default,
        bind_flags: api.D3D11_BIND_FLAG = .{ .shader_resource = true },
        cpu_access_flags: api.D3D11_CPU_ACCESS_FLAG = .{},
        misc_flags: api.D3D11_RESOURCE_MISC_FLAG = .{},
    };

    pub fn init(opts: Options, width: usize, height: usize, data: ?[]const u8) !Texture {
        _ = data;
        const desc = api.D3D11_TEXTURE2D_DESC{
            .width = @intCast(width),
            .height = @intCast(height),
            .mip_levels = 1,
            .array_size = 1,
            .format = opts.format,
            .sample_desc = .{ .count = 1, .quality = 0 },
            .usage = opts.usage,
            .bind_flags = opts.bind_flags,
            .cpu_access_flags = opts.cpu_access_flags,
            .misc_flags = opts.misc_flags,
        };
        return initWithDesc(opts.device, opts.device_context, &desc, null);
    }

    pub fn initWithDesc(device: *api.ID3D11Device, device_context: *api.ID3D11DeviceContext, desc: *const api.D3D11_TEXTURE2D_DESC, init_data: ?*const api.D3D11_SUBRESOURCE_DATA) !Texture {
        var texture: *api.ID3D11Texture2D = undefined;
        const hr = device.createTexture2D(desc, init_data, &texture);
        if (hr != api.S_OK) return error.TextureCreateFailed;

        // Create shader resource view
        const srv_desc = api.D3D11_SHADER_RESOURCE_VIEW_DESC{
            .format = desc.format,
            .view_dimension = .texture2d,
            .u = .{ .texture2D = .{ .most_detailed_mip = 0, .mip_levels = desc.mip_levels } },
        };

        var srv: *api.ID3D11ShaderResourceView = undefined;
        const srv_hr = device.createShaderResourceView(
            @ptrCast(texture),
            &srv_desc,
            &srv,
        );
        if (srv_hr != api.S_OK) {
            _ = api.releaseCOM(@ptrCast(texture));
            return error.SRVCreateFailed;
        }

        return .{
            .texture = texture,
            .srv = srv,
            .width = desc.width,
            .height = desc.height,
            .format = desc.format,
            .ctx = device_context,
        };
    }

    pub fn deinit(self: Texture) void {
        _ = api.releaseCOM(@ptrCast(self.srv));
        _ = api.releaseCOM(@ptrCast(self.texture));
    }

    /// Replace a region of the texture with new data.
    pub fn replaceRegion(self: *Texture, x: u32, y: u32, w: u32, h: u32, data: []const u8) !void {
        const box = api.D3D11_BOX{
            .left = x,
            .top = y,
            .front = 0,
            .right = x + w,
            .bottom = y + h,
            .back = 1,
        };
        const bpp: u32 = switch (self.format) {
            .r8_unorm => 1,
            .b8g8r8a8_unorm => 4,
            .r8g8b8a8_unorm => 4,
            else => 4, // fallback
        };
        self.ctx.updateSubresource(
            @ptrCast(self.texture),
            0,
            &box,
            @ptrCast(data.ptr),
            @intCast(w * bpp),
            0,
        );
    }
};
