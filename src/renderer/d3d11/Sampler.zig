const api = @import("api.zig");

/// A D3D11 sampler state.
pub const Sampler = struct {
    sampler: *api.ID3D11SamplerState,

    pub const Options = struct {
        device: *api.ID3D11Device,
        filter: api.D3D11_FILTER = .min_mag_mip_point,
        address_u: api.D3D11_TEXTURE_ADDRESS_MODE = .clamp,
        address_v: api.D3D11_TEXTURE_ADDRESS_MODE = .clamp,
        address_w: api.D3D11_TEXTURE_ADDRESS_MODE = .clamp,
        min_lod: f32 = -3.402823466e+38,
        max_lod: f32 = 3.402823466e+38,
    };

    pub fn init(opts: Options) !Sampler {
        const desc = api.D3D11_SAMPLER_DESC{
            .filter = opts.filter,
            .address_u = opts.address_u,
            .address_v = opts.address_v,
            .address_w = opts.address_w,
            .mip_lod_bias = 0.0,
            .max_anisotropy = 1,
            .comparison_func = .never,
            .border_color = .{ 0.0, 0.0, 0.0, 0.0 },
            .min_lod = opts.min_lod,
            .max_lod = opts.max_lod,
        };

        var sampler: *api.ID3D11SamplerState = undefined;
        const hr = opts.device.createSamplerState(&desc, &sampler);
        if (hr != api.S_OK) return error.SamplerCreateFailed;

        return .{ .sampler = sampler };
    }

    pub fn deinit(self: Sampler) void {
        _ = api.releaseCOM(@ptrCast(self.sampler));
    }
};

pub const SamplerError = error{SamplerCreateFailed};
