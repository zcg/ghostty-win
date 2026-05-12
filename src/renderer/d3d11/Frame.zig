const std = @import("std");
const api = @import("api.zig");
const renderpass_mod = @import("RenderPass.zig");
const RenderPass = renderpass_mod.RenderPass;
const target_mod = @import("Target.zig");
const Target = target_mod.Target;

const D3D11 = @import("../D3D11.zig");
const renderer = @import("../../renderer.zig");
const Health = renderer.Health;

const log = std.log.scoped(.d3d11);

/// A D3D11 frame: creates render passes and presents when complete.
pub const Frame = struct {
    renderer: *D3D11,
    generic_renderer: *renderer.Renderer,
    target: *Target,
    health: Health = .healthy,

    pub fn begin(d3d11: *D3D11, generic_renderer: *renderer.Renderer, target: *Target) Frame {
        return .{
            .renderer = d3d11,
            .generic_renderer = generic_renderer,
            .target = target,
        };
    }

    pub fn renderPass(self: *Frame, attachments: []const RenderPass.Options.Attachment) RenderPass {
        // Use the first attachment's target as our render target
        const attachment = if (attachments.len > 0) attachments[0] else {
            @panic("D3D11 renderPass requires at least one attachment");
        };

        const rtv = switch (attachment.target) {
            .target => |t| t.rtv,
            .texture => |tex| tex.rtv orelse self.target.rtv,
        };

        return RenderPass.begin(.{
            .ctx = self.renderer.device_context,
            .rtv = rtv,
            .width = self.target.width,
            .height = self.target.height,
            .clear_color = attachment.clear_color,
            .default_sampler = self.renderer.default_sampler.sampler,
        });
    }

    pub fn complete(self: *Frame, sync: bool) void {
        _ = sync;

        // Present the target via the renderer's present method
        self.renderer.present(self.target.*) catch |err| {
            log.err("failed to present render target: err={}", .{err});
            self.health = .unhealthy;
        };

        // Release the swap chain semaphore so the next frame can begin.
        // Without this, the rendering thread blocks permanently after 2 frames.
        self.generic_renderer.frameCompleted(self.health);
    }
};
