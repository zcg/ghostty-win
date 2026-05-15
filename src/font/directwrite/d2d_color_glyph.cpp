#include <d2d1_3.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <dwrite_3.h>
#include <string.h>

template <typename T>
static void release_if(T* value) {
    if (value != nullptr) {
        value->Release();
    }
}

extern "C" HRESULT ghostty_dwrite_render_color_glyph_d2d(
    const DWRITE_GLYPH_RUN* glyph_run,
    FLOAT dpi_x,
    FLOAT dpi_y,
    FLOAT baseline_origin_x,
    FLOAT baseline_origin_y,
    DWRITE_MEASURING_MODE measuring_mode,
    UINT32 width,
    UINT32 height,
    void* out_pixels,
    UINT32 out_stride,
    UINT32* used_device_context7
) {
    if (used_device_context7 != nullptr) {
        *used_device_context7 = 0;
    }
    if (glyph_run == nullptr || out_pixels == nullptr || width == 0 || height == 0 || out_stride < width * 4) {
        return E_INVALIDARG;
    }

    const D3D_FEATURE_LEVEL feature_levels[] = {
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1,
        D3D_FEATURE_LEVEL_10_0,
    };

    ID3D11Device* d3d_device = nullptr;
    ID3D11DeviceContext* d3d_context = nullptr;
    D3D_FEATURE_LEVEL selected_level = D3D_FEATURE_LEVEL_11_0;

    HRESULT hr = D3D11CreateDevice(
        nullptr,
        D3D_DRIVER_TYPE_HARDWARE,
        nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT,
        feature_levels,
        ARRAYSIZE(feature_levels),
        D3D11_SDK_VERSION,
        &d3d_device,
        &selected_level,
        &d3d_context
    );
    if (FAILED(hr)) {
        hr = D3D11CreateDevice(
            nullptr,
            D3D_DRIVER_TYPE_WARP,
            nullptr,
            D3D11_CREATE_DEVICE_BGRA_SUPPORT,
            feature_levels,
            ARRAYSIZE(feature_levels),
            D3D11_SDK_VERSION,
            &d3d_device,
            &selected_level,
            &d3d_context
        );
        if (FAILED(hr)) {
            return hr;
        }
    }

    D3D11_TEXTURE2D_DESC render_desc = {};
    render_desc.Width = width;
    render_desc.Height = height;
    render_desc.MipLevels = 1;
    render_desc.ArraySize = 1;
    render_desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    render_desc.SampleDesc.Count = 1;
    render_desc.Usage = D3D11_USAGE_DEFAULT;
    render_desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;

    ID3D11Texture2D* render_texture = nullptr;
    hr = d3d_device->CreateTexture2D(&render_desc, nullptr, &render_texture);
    if (FAILED(hr)) {
        release_if(d3d_context);
        release_if(d3d_device);
        return hr;
    }

    IDXGIDevice* dxgi_device = nullptr;
    hr = d3d_device->QueryInterface(__uuidof(IDXGIDevice), reinterpret_cast<void**>(&dxgi_device));
    if (FAILED(hr)) {
        release_if(render_texture);
        release_if(d3d_context);
        release_if(d3d_device);
        return hr;
    }

    D2D1_FACTORY_OPTIONS factory_options = {};
    ID2D1Factory1* d2d_factory = nullptr;
    hr = D2D1CreateFactory(
        D2D1_FACTORY_TYPE_SINGLE_THREADED,
        __uuidof(ID2D1Factory1),
        &factory_options,
        reinterpret_cast<void**>(&d2d_factory)
    );
    if (FAILED(hr)) {
        release_if(dxgi_device);
        release_if(render_texture);
        release_if(d3d_context);
        release_if(d3d_device);
        return hr;
    }

    ID2D1Device* d2d_device = nullptr;
    hr = d2d_factory->CreateDevice(dxgi_device, &d2d_device);
    if (FAILED(hr)) {
        release_if(d2d_factory);
        release_if(dxgi_device);
        release_if(render_texture);
        release_if(d3d_context);
        release_if(d3d_device);
        return hr;
    }

    ID2D1DeviceContext* d2d_context = nullptr;
    hr = d2d_device->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE, &d2d_context);
    if (FAILED(hr)) {
        release_if(d2d_device);
        release_if(d2d_factory);
        release_if(dxgi_device);
        release_if(render_texture);
        release_if(d3d_context);
        release_if(d3d_device);
        return hr;
    }

    ID2D1DeviceContext7* d2d_context7 = nullptr;
    hr = d2d_context->QueryInterface(__uuidof(ID2D1DeviceContext7), reinterpret_cast<void**>(&d2d_context7));
    if (FAILED(hr)) {
        release_if(d2d_context);
        release_if(d2d_device);
        release_if(d2d_factory);
        release_if(dxgi_device);
        release_if(render_texture);
        release_if(d3d_context);
        release_if(d3d_device);
        return hr;
    }
    if (used_device_context7 != nullptr) {
        *used_device_context7 = 1;
    }

    IDXGISurface* surface = nullptr;
    hr = render_texture->QueryInterface(__uuidof(IDXGISurface), reinterpret_cast<void**>(&surface));
    if (FAILED(hr)) {
        release_if(d2d_context7);
        release_if(d2d_context);
        release_if(d2d_device);
        release_if(d2d_factory);
        release_if(dxgi_device);
        release_if(render_texture);
        release_if(d3d_context);
        release_if(d3d_device);
        return hr;
    }

    const D2D1_BITMAP_PROPERTIES1 bitmap_props = D2D1::BitmapProperties1(
        D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW,
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED),
        96.0f,
        96.0f
    );

    ID2D1Bitmap1* target_bitmap = nullptr;
    hr = d2d_context->CreateBitmapFromDxgiSurface(surface, &bitmap_props, &target_bitmap);
    if (FAILED(hr)) {
        release_if(surface);
        release_if(d2d_context7);
        release_if(d2d_context);
        release_if(d2d_device);
        release_if(d2d_factory);
        release_if(dxgi_device);
        release_if(render_texture);
        release_if(d3d_context);
        release_if(d3d_device);
        return hr;
    }

    ID2D1SolidColorBrush* foreground_brush = nullptr;
    hr = d2d_context->CreateSolidColorBrush(D2D1::ColorF(D2D1::ColorF::White, 1.0f), &foreground_brush);
    if (FAILED(hr)) {
        release_if(target_bitmap);
        release_if(surface);
        release_if(d2d_context7);
        release_if(d2d_context);
        release_if(d2d_device);
        release_if(d2d_factory);
        release_if(dxgi_device);
        release_if(render_texture);
        release_if(d3d_context);
        release_if(d3d_device);
        return hr;
    }

    d2d_context->SetTarget(target_bitmap);
    DWRITE_GLYPH_RUN d2d_glyph_run = *glyph_run;
    d2d_glyph_run.fontEmSize = glyph_run->fontEmSize * (dpi_y / 96.0f);

    d2d_context->SetDpi(96.0f, 96.0f);
    d2d_context->BeginDraw();
    d2d_context->Clear(D2D1::ColorF(0, 0.0f));
    d2d_context7->DrawGlyphRunWithColorSupport(
        D2D1::Point2F(baseline_origin_x, baseline_origin_y),
        &d2d_glyph_run,
        nullptr,
        foreground_brush,
        nullptr,
        0,
        measuring_mode,
        D2D1_COLOR_BITMAP_GLYPH_SNAP_OPTION_DEFAULT
    );
    hr = d2d_context->EndDraw();
    if (FAILED(hr)) {
        release_if(foreground_brush);
        release_if(target_bitmap);
        release_if(surface);
        release_if(d2d_context7);
        release_if(d2d_context);
        release_if(d2d_device);
        release_if(d2d_factory);
        release_if(dxgi_device);
        release_if(render_texture);
        release_if(d3d_context);
        release_if(d3d_device);
        return hr;
    }

    D3D11_TEXTURE2D_DESC staging_desc = render_desc;
    staging_desc.Usage = D3D11_USAGE_STAGING;
    staging_desc.BindFlags = 0;
    staging_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;

    ID3D11Texture2D* staging_texture = nullptr;
    hr = d3d_device->CreateTexture2D(&staging_desc, nullptr, &staging_texture);
    if (FAILED(hr)) {
        release_if(foreground_brush);
        release_if(target_bitmap);
        release_if(surface);
        release_if(d2d_context7);
        release_if(d2d_context);
        release_if(d2d_device);
        release_if(d2d_factory);
        release_if(dxgi_device);
        release_if(render_texture);
        release_if(d3d_context);
        release_if(d3d_device);
        return hr;
    }

    d3d_context->CopyResource(staging_texture, render_texture);

    D3D11_MAPPED_SUBRESOURCE mapped = {};
    hr = d3d_context->Map(staging_texture, 0, D3D11_MAP_READ, 0, &mapped);
    if (SUCCEEDED(hr)) {
        unsigned char* dst = static_cast<unsigned char*>(out_pixels);
        const unsigned char* src = static_cast<const unsigned char*>(mapped.pData);
        for (UINT32 y = 0; y < height; y++) {
            memcpy(
                dst + static_cast<size_t>(y) * out_stride,
                src + static_cast<size_t>(y) * mapped.RowPitch,
                static_cast<size_t>(width) * 4
            );
        }
        d3d_context->Unmap(staging_texture, 0);
    }

    release_if(staging_texture);
    release_if(foreground_brush);
    release_if(target_bitmap);
    release_if(surface);
    release_if(d2d_context7);
    release_if(d2d_context);
    release_if(d2d_device);
    release_if(d2d_factory);
    release_if(dxgi_device);
    release_if(render_texture);
    release_if(d3d_context);
    release_if(d3d_device);
    return hr;
}
