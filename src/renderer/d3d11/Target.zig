const api = @import("api.zig");

/// A D3D11 off-screen render target (Texture2D + RTV).
pub const Target = struct {
    texture: *api.ID3D11Texture2D,
    rtv: *api.ID3D11RenderTargetView,
    width: u32,
    height: u32,

    pub fn init(device: *api.ID3D11Device, width: u32, height: u32, format: api.DXGI_FORMAT) !Target {
        const desc = api.D3D11_TEXTURE2D_DESC{
            .width = width,
            .height = height,
            .mip_levels = 1,
            .array_size = 1,
            .format = format,
            .sample_desc = .{ .count = 1, .quality = 0 },
            .usage = .default,
            .bind_flags = .{ .render_target = true, .shader_resource = true },
            .cpu_access_flags = .{},
            .misc_flags = .{},
        };

        var texture: *api.ID3D11Texture2D = undefined;
        const tex_hr = device.createTexture2D(&desc, null, &texture);
        if (tex_hr != api.S_OK) return error.TargetCreateFailed;

        const rtv_desc = api.D3D11_RENDER_TARGET_VIEW_DESC{
            .format = format,
            .view_dimension = .texture2d,
            .texture2D = .{ .mip_slice = 0 },
        };

        var rtv: *api.ID3D11RenderTargetView = undefined;
        const rtv_hr = device.createRenderTargetView(
            @ptrCast(texture),
            &rtv_desc,
            &rtv,
        );
        if (rtv_hr != api.S_OK) {
            _ = api.releaseCOM(@ptrCast(texture));
            return error.RTVCreateFailed;
        }

        return .{
            .texture = texture,
            .rtv = rtv,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: Target) void {
        _ = api.releaseCOM(@ptrCast(self.rtv));
        _ = api.releaseCOM(@ptrCast(self.texture));
    }
};

pub const TargetError = error{
    TargetCreateFailed,
    RTVCreateFailed,
};
