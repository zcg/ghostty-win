const std = @import("std");
const api = @import("api.zig");
const pipeline_mod = @import("Pipeline.zig");
const Pipeline = pipeline_mod.Pipeline;
const d3d11_buffer = @import("buffer.zig");
const d3d11_texture = @import("Texture.zig");
const d3d11_sampler = @import("Sampler.zig");
const Target = @import("Target.zig").Target;

/// A D3D11 render pass: binds pipeline, resources, and issues draw calls.
pub const RenderPass = struct {
    ctx: *api.ID3D11DeviceContext,
    rtv: *api.ID3D11RenderTargetView,
    width: u32,
    height: u32,
    default_sampler: ?*api.ID3D11SamplerState = null,

    pub const Options = struct {
        attachments: []const Attachment,

        pub const Attachment = struct {
            target: union(enum) {
                texture: d3d11_texture.Texture,
                target: Target,
            },
            clear_color: ?[4]f32 = null,
        };
    };

    pub const BeginOptions = struct {
        ctx: *api.ID3D11DeviceContext,
        rtv: *api.ID3D11RenderTargetView,
        width: u32,
        height: u32,
        clear_color: ?[4]f32 = null,
        default_sampler: ?*api.ID3D11SamplerState = null,
    };

    pub fn begin(opts: BeginOptions) RenderPass {
        const ctx = opts.ctx;

        // Set render target
        const rtv_arr = [_]?*api.ID3D11RenderTargetView{opts.rtv};
        ctx.omSetRenderTargets(1, &rtv_arr, null);

        // Clear if requested
        if (opts.clear_color) |cc| {
            ctx.clearRenderTargetView(opts.rtv, &cc);
        }

        const viewports = [_]api.D3D11_VIEWPORT{api.D3D11_VIEWPORT{
            .top_left_x = 0.0,
            .top_left_y = 0.0,
            .width = @floatFromInt(opts.width),
            .height = @floatFromInt(opts.height),
            .min_depth = 0.0,
            .max_depth = 1.0,
        }};
        ctx.rsSetViewports(1, &viewports);

        return .{
            .ctx = ctx,
            .rtv = opts.rtv,
            .width = opts.width,
            .height = opts.height,
            .default_sampler = opts.default_sampler,
        };
    }

    pub fn step(self: *RenderPass, s: Step) void {
        if (s.draw.instance_count == 0) return;
        const ctx = self.ctx;

        // Set pipeline state
        ctx.vsSetShader(s.pipeline.vertex_shader, null, 0);
        ctx.psSetShader(s.pipeline.pixel_shader, null, 0);
        ctx.iaSetInputLayout(s.pipeline.input_layout);
        ctx.omSetBlendState(s.pipeline.blend_state, null, 0xFFFFFFFF);
        ctx.rsSetState(s.pipeline.rasterizer_state);

        // Set primitive topology
        const topology: api.D3D11_PRIMITIVE_TOPOLOGY = switch (s.draw.type) {
            .triangle => .trianglelist,
            .triangle_strip => .trianglestrip,
            .instanced => .trianglestrip,
        };
        ctx.iaSetPrimitiveTopology(topology);

        // Bind uniforms buffer to slot 0 (cbuffer register b0)
        if (s.uniforms) |buf| {
            const cb_arr = [_]*api.ID3D11Buffer{buf.ptr};
            ctx.vsSetConstantBuffers(0, 1, @ptrCast(&cb_arr));
            ctx.psSetConstantBuffers(0, 1, @ptrCast(&cb_arr));
        }

        // Bind textures first: textures[i] -> SRV slot t[i]
        const num_textures = s.textures.len;
        for (s.textures, 0..) |tex, i| {
            if (tex) |t| {
                const srv_arr = [_]?*api.ID3D11ShaderResourceView{t.srv};
                ctx.psSetShaderResources(@intCast(i), 1, &srv_arr);
                ctx.vsSetShaderResources(@intCast(i), 1, &srv_arr);
            }
        }

        // Bind buffers: slot 0 as vertex buffer (IA), slots 1+ as SRV (PS + VS)
        if (s.buffers.len > 0) {
            // Bind slot 0 as vertex buffer if present
            if (s.buffers[0]) |b| {
                const vb_arr = [_]*api.ID3D11Buffer{b.ptr};
                var strides = [_]api.UINT{b.stride};
                var offsets = [_]api.UINT{0};
                ctx.iaSetVertexBuffers(0, 1, &vb_arr, &strides, &offsets);
            }

            // Bind slots 1+ as shader resource views to both PS and VS.
            // SRV slots start after texture slots to avoid overlap.
            for (s.buffers[1..], 0..) |opt_b, i| {
                if (opt_b) |b| {
                    if (b.srv) |srv| {
                        const srv_arr = [_]?*api.ID3D11ShaderResourceView{srv};
                        const slot: api.UINT = @intCast(num_textures + i);
                        ctx.psSetShaderResources(slot, 1, &srv_arr);
                        ctx.vsSetShaderResources(slot, 1, &srv_arr);
                    }
                }
            }
        }

        // Bind samplers. If step provides none but textures are used,
        // fall back to the default sampler so that Texture2D.Sample()
        // in the pixel shader has valid sampler state.
        if (s.samplers.len > 0) {
            for (s.samplers, 0..) |samp, i| {
                if (samp) |s_| {
                    const samp_arr = [_]*api.ID3D11SamplerState{s_.sampler};
                    ctx.psSetSamplers(@intCast(i), 1, @ptrCast(&samp_arr));
                }
            }
        } else if (s.textures.len > 0) {
            if (self.default_sampler) |ds| {
                const samp_arr = [_]*api.ID3D11SamplerState{ds};
                ctx.psSetSamplers(0, 1, @ptrCast(&samp_arr));
            }
        }

        // Issue draw call
        ctx.drawInstanced(
            @intCast(s.draw.vertex_count),
            @intCast(s.draw.instance_count),
            0,
            0,
        );
    }

    pub fn complete(self: *RenderPass) void {
        _ = self;
    }

    pub const Step = struct {
        pipeline: Pipeline,
        uniforms: ?d3d11_buffer.BufferHandle = null,
        buffers: []const ?d3d11_buffer.BufferHandle = &.{},
        textures: []const ?d3d11_texture.Texture = &.{},
        samplers: []const ?d3d11_sampler.Sampler = &.{},
        draw: Draw,
    };

    pub const Draw = struct {
        type: enum { triangle, triangle_strip, instanced },
        vertex_count: usize,
        instance_count: usize = 1,
    };
};
