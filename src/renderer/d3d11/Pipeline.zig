const std = @import("std");
const Allocator = std.mem.Allocator;
const api = @import("api.zig");

const log = std.log.scoped(.d3d11);

/// A D3D11 pipeline: vertex shader + pixel shader + input layout + blend state + rasterizer state.
pub const Pipeline = struct {
    vertex_shader: *api.ID3D11VertexShader,
    pixel_shader: *api.ID3D11PixelShader,
    input_layout: ?*api.ID3D11InputLayout,
    blend_state: *api.ID3D11BlendState,
    rasterizer_state: *api.ID3D11RasterizerState,

    pub fn init(
        device: *api.ID3D11Device,
        vs_bytecode: []const u8,
        ps_bytecode: []const u8,
        input_elements: ?[]const api.D3D11_INPUT_ELEMENT_DESC,
        blend: bool,
    ) !Pipeline {
        // Create vertex shader
        var vertex_shader: *api.ID3D11VertexShader = undefined;
        const vs_hr = device.createVertexShader(
            vs_bytecode.ptr,
            vs_bytecode.len,
            null,
            &vertex_shader,
        );
        if (vs_hr != api.S_OK) return error.VertexShaderCreateFailed;

        // Create pixel shader
        var pixel_shader: *api.ID3D11PixelShader = undefined;
        const ps_hr = device.createPixelShader(
            ps_bytecode.ptr,
            ps_bytecode.len,
            null,
            &pixel_shader,
        );
        if (ps_hr != api.S_OK) {
            _ = api.releaseCOM(@ptrCast(vertex_shader));
            return error.PixelShaderCreateFailed;
        }

        // Create blend state
        const blend_desc = api.D3D11_BLEND_DESC{
            .alpha_to_coverage_enable = 0,
            .independent_blend_enable = 0,
            .render_target = [1]api.D3D11_RENDER_TARGET_BLEND_DESC{.{
                .blend_enable = if (blend) 1 else 0,
                .src_blend = .one,
                .dest_blend = .inv_src_alpha,
                .blend_op = .add,
                .src_blend_alpha = .one,
                .dest_blend_alpha = .inv_src_alpha,
                .blend_op_alpha = .add,
                .render_target_write_enable = .{ .red = true, .green = true, .blue = true, .alpha = true },
            }} ++ [_]api.D3D11_RENDER_TARGET_BLEND_DESC{.{
                .blend_enable = 0,
                .src_blend = .one,
                .dest_blend = .zero,
                .blend_op = .add,
                .src_blend_alpha = .one,
                .dest_blend_alpha = .zero,
                .blend_op_alpha = .add,
                .render_target_write_enable = .{ .red = true, .green = true, .blue = true, .alpha = true },
            }} ** 7,
        };

        var blend_state: *api.ID3D11BlendState = undefined;
        const bs_hr = device.createBlendState(&blend_desc, &blend_state);
        if (bs_hr != api.S_OK) {
            _ = api.releaseCOM(@ptrCast(pixel_shader));
            _ = api.releaseCOM(@ptrCast(vertex_shader));
            return error.BlendStateCreateFailed;
        }

        // Create rasterizer state
        const raster_desc = api.D3D11_RASTERIZER_DESC{
            .fill_mode = .solid,
            .cull_mode = .none,
            .front_counter_clockwise = 0,
            .depth_bias = 0,
            .depth_bias_clamp = 0.0,
            .slope_scaled_depth_bias = 0.0,
            .depth_clip_enable = 1,
            .scissor_enable = 0,
            .multisample_enable = 0,
            .antialiased_line_enable = 0,
        };

        var rasterizer_state: *api.ID3D11RasterizerState = undefined;
        const rs_hr = device.createRasterizerState(&raster_desc, &rasterizer_state);
        if (rs_hr != api.S_OK) {
            _ = api.releaseCOM(@ptrCast(blend_state));
            _ = api.releaseCOM(@ptrCast(pixel_shader));
            _ = api.releaseCOM(@ptrCast(vertex_shader));
            return error.RasterizerStateCreateFailed;
        }

        // Create input layout if elements are provided
        var input_layout: ?*api.ID3D11InputLayout = null;
        if (input_elements) |elements| {
            var layout: *api.ID3D11InputLayout = undefined;
            const il_hr = device.createInputLayout(
                elements.ptr,
                @intCast(elements.len),
                vs_bytecode.ptr,
                vs_bytecode.len,
                &layout,
            );
            if (il_hr == api.S_OK) {
                input_layout = layout;
            } else {
                log.err("createInputLayout failed: hr=0x{X:0>8}", .{@as(u32, @bitCast(il_hr))});
                _ = api.releaseCOM(@ptrCast(rasterizer_state));
                _ = api.releaseCOM(@ptrCast(blend_state));
                _ = api.releaseCOM(@ptrCast(pixel_shader));
                _ = api.releaseCOM(@ptrCast(vertex_shader));
                return error.InputLayoutCreateFailed;
            }
        }

        return .{
            .vertex_shader = vertex_shader,
            .pixel_shader = pixel_shader,
            .input_layout = input_layout,
            .blend_state = blend_state,
            .rasterizer_state = rasterizer_state,
        };
    }

    pub fn deinit(self: Pipeline) void {
        if (self.input_layout) |il| {
            _ = api.releaseCOM(@ptrCast(il));
        }
        _ = api.releaseCOM(@ptrCast(self.rasterizer_state));
        _ = api.releaseCOM(@ptrCast(self.blend_state));
        _ = api.releaseCOM(@ptrCast(self.pixel_shader));
        _ = api.releaseCOM(@ptrCast(self.vertex_shader));
    }
};

pub const PipelineError = error{
    VertexShaderCreateFailed,
    PixelShaderCreateFailed,
    BlendStateCreateFailed,
    RasterizerStateCreateFailed,
    InputLayoutCreateFailed,
};
