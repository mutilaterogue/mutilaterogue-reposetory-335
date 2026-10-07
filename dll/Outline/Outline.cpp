#include <Outline/Outline.hpp>
#include <Outline/OutlineShaders.hpp>

#include <Client/ClientServices.hpp>
#include <Client/FrameScript.hpp>
#include <Data/Enums.hpp>
#include <GameObjects/CGObject.hpp>
#include <Misc/InlineHook.hpp>

#include <Windows.h>
#include <d3d9.h>

#include <cstdio>
#include <cstring>
#include <vector>

// Stage 2: the outline.
//  1. When the client draws a batch of an outlined model, the same DrawIndexedPrimitive is issued once more right
//     after it into our mask texture (screen sized), with a flat pixel shader: the silhouette in its color.
//     Every state (bones, buffers, camera) is the client's own at that moment; no M2 / Gx function is called twice.
//  2. After the 3D scene (0x4F9240) one full-screen pass over the screen: the mask sampled around every pixel (the
//     halo) minus the mask at that pixel -> a soft rim around the silhouettes, alpha blended. Then the mask is cleared.
// Gx keeps a cache of the device states and the device can't be read back: everything Gx sends that we touch is
// copied as it goes (device vtable hooks) and put back from that copy after our draws.

namespace
{
    // ---------------------------------------------------------------- client addresses (12340)
    constexpr uintptr_t ADDR_M2_DRAW_BATCH  = 0x8203B0;    // void __thiscall (batch*)
    constexpr uintptr_t ADDR_WORLD_RENDER   = 0x4F9240;    // inside the world render function, after the 3D scene

    constexpr uintptr_t ADDR_GX_DEVICE      = 0xC5DF88;    // CGxDevice*
    constexpr uint32_t  GX_API_OFFSET       = 0x1B4;       // 1, 2 - Direct3D
    constexpr uint32_t  GX_D3DDEVICE_OFFSET = 0x397C;      // IDirect3DDevice9*

    constexpr uintptr_t ADDR_TARGET_GUID    = 0xBD07B0;
    constexpr uintptr_t ADDR_MOUSEOVER_GUID = 0xBD07A0;
    constexpr uintptr_t ADDR_OBJECT_PTR     = 0x4D4DB0;    // ClntObjMgrObjectPtr(guid, typeMask, file, line)

    // the batch record (this of 0x8203B0)
    constexpr uint32_t BATCH_MATERIAL      = 0x50;         // -> [0] blend mode, [8] flags
    constexpr uint32_t BATCH_MODEL         = 0x60;         // CM2Model*
    constexpr uint32_t MODEL_PARENT        = 0x48;         // CM2Model* the model is attached to
    constexpr uint32_t MAX_BLEND_MODE      = 2;            // opaque / alpha key (no blended, additive...)

    // the look
    constexpr float ALPHA_GAIN_HIGH = 1.0f / 3.0f;         // 16 samples
    constexpr float ALPHA_GAIN_LOW  = 1.0f / 2.0f;         // 8 samples
    constexpr float STRENGTH        = 1.0f;

    struct Target
    {
        void* Model = nullptr;
        float Color[4] = {};
    };

    // OutlineDebug()
    struct Stats
    {
        uint32_t Installed = 0;             // bits: 1 batch, 2 world render, 4 device
        uint32_t WorldRenders = 0;
        uint32_t BatchDraws = 0;
        uint32_t Targets = 0;               // models picked for this frame
        uint32_t TargetBatches = 0;         // their batches in the last frame
        uint32_t Silhouettes = 0;           // silhouette draw calls in the last frame
        uint32_t GxApi = 0;
        uint32_t Error = 0;                 // 1 no device, 2 flat ps, 3 mask texture, 4 quad buffer, 5 outline ps, 6 low ps, 7 quad vs, 8 declaration
        uint32_t Composites = 0;            // full-screen passes done
    } s_stats;
    uint32_t s_frameBatches = 0;
    uint32_t s_frameSilhouettes = 0;

    // OutlineMode(bits): 1 - no silhouettes, 2 - no full-screen pass, 4 - low quality (8 samples),
    //  8 - stage 1: the silhouettes straight on the screen, no depth test
    uint32_t s_mode = 0;

    std::vector<Target> s_targets;
    Target const* s_currentTarget = nullptr;    // set while the client draws a batch of an outlined model

    // our device objects
    IDirect3DPixelShader9* s_flatShader = nullptr;
    IDirect3DPixelShader9* s_outlineShader = nullptr;
    IDirect3DPixelShader9* s_outlineLowShader = nullptr;
    IDirect3DVertexShader9* s_quadShader = nullptr;
    IDirect3DVertexDeclaration9* s_quadDeclaration = nullptr;
    IDirect3DVertexBuffer9* s_quadBuffer = nullptr;     // managed: survives a device reset
    IDirect3DTexture9* s_mask = nullptr;                // default pool: released before a device reset
    IDirect3DSurface9* s_maskSurface = nullptr;
    UINT s_maskWidth = 0, s_maskHeight = 0;
    bool s_maskDirty = false;                           // something was drawn into it since the last clear

    struct QuadVertex
    {
        float X, Y, Z, W;
        float U, V;
    };

    // ---------------------------------------------------------------- code hooks
    // jmp over the first 5 bytes; the original is called with them put back
    struct RawHook
    {
        uintptr_t Target = 0;
        uint8_t Original[5] = {};
        uint8_t Patch[5] = {};

        bool Install(uintptr_t target, void* detour)
        {
            DWORD old = 0;
            if (!VirtualProtect(reinterpret_cast<void*>(target), 5, PAGE_EXECUTE_READWRITE, &old))
                return false;
            Target = target;
            memcpy(Original, reinterpret_cast<void*>(target), 5);
            Patch[0] = 0xE9;
            *reinterpret_cast<int32_t*>(Patch + 1) = static_cast<int32_t>(reinterpret_cast<uintptr_t>(detour) - (target + 5));
            Repatch();
            return true;
        }

        void Unpatch()
        {
            memcpy(reinterpret_cast<void*>(Target), Original, 5);
            FlushInstructionCache(GetCurrentProcess(), reinterpret_cast<void*>(Target), 5);
        }

        void Repatch()
        {
            memcpy(reinterpret_cast<void*>(Target), Patch, 5);
            FlushInstructionCache(GetCurrentProcess(), reinterpret_cast<void*>(Target), 5);
        }
    };

    RawHook s_hookDrawBatch;

    // ---------------------------------------------------------------- targets
    IDirect3DDevice9* GetD3DDevice()
    {
        uint8_t* gx = *reinterpret_cast<uint8_t**>(ADDR_GX_DEVICE);
        if (!gx)
            return nullptr;
        s_stats.GxApi = *reinterpret_cast<uint32_t*>(gx + GX_API_OFFSET);
        if (s_stats.GxApi != 1 && s_stats.GxApi != 2)
            return nullptr;
        return *reinterpret_cast<IDirect3DDevice9**>(gx + GX_D3DDEVICE_OFFSET);
    }

    CGObject* FindUnit(WoWGUID guid)
    {
        if (!guid)
            return nullptr;
        return reinterpret_cast<CGObject* (__cdecl*)(WoWGUID, uint32_t, const char*, int32_t)>(ADDR_OBJECT_PTR)(guid, TYPEMASK_UNIT, nullptr, 0);
    }

    void AddTarget(WoWGUID guid, float r, float g, float b)
    {
        CGObject* object = FindUnit(guid);
        if (!object || !object->m_model)
            return;
        for (Target& target : s_targets)
            if (target.Model == object->m_model)
                return;     // the target wins over the mouseover
        Target target;
        target.Model = object->m_model;
        target.Color[0] = r;
        target.Color[1] = g;
        target.Color[2] = b;
        target.Color[3] = 1.0f;
        s_targets.push_back(target);
    }

    // the models of the next frame (stage 2: the target red, the mouseover yellow)
    void CollectTargets()
    {
        s_targets.clear();
        AddTarget(*reinterpret_cast<WoWGUID*>(ADDR_TARGET_GUID), 1.0f, 0.2f, 0.2f);
        AddTarget(*reinterpret_cast<WoWGUID*>(ADDR_MOUSEOVER_GUID), 1.0f, 0.9f, 0.3f);
        s_stats.Targets = static_cast<uint32_t>(s_targets.size());
    }

    // the outlined model the batch belongs to (itself or an attachment of it)
    Target const* FindTarget(uint8_t* batch)
    {
        uint8_t* material = *reinterpret_cast<uint8_t**>(batch + BATCH_MATERIAL);
        if (!material || *reinterpret_cast<uint32_t*>(material) > MAX_BLEND_MODE || (material[8] & 1))
            return nullptr;
        void* model = *reinterpret_cast<void**>(batch + BATCH_MODEL);
        for (int depth = 0; model && depth < 8; ++depth)
        {
            for (Target const& target : s_targets)
                if (target.Model == model)
                    return &target;
            model = *reinterpret_cast<void**>(static_cast<uint8_t*>(model) + MODEL_PARENT);
        }
        return nullptr;
    }

    // ---------------------------------------------------------------- the device: what Gx sends, copied
    enum VtableIndex : uint32_t
    {
        VT_RESET                = 16,
        VT_SET_VIEWPORT         = 47,
        VT_SET_RENDER_STATE     = 57,
        VT_SET_TEXTURE          = 65,
        VT_SET_SAMPLER_STATE    = 69,
        VT_DRAW_INDEXED         = 82,
        VT_SET_VERTEX_DECL      = 87,
        VT_SET_FVF              = 89,
        VT_SET_VERTEX_SHADER    = 92,
        VT_SET_STREAM_SOURCE    = 100,
        VT_SET_PIXEL_SHADER     = 107,
        VT_SET_PS_CONSTANT_F    = 109,
    };
    constexpr uint32_t SHADOW_PS_REGISTERS = 2;     // c0, c1: the ones we use
    constexpr uint32_t SHADOW_SAMPLER_STATES = 14;

    typedef HRESULT (__stdcall* ResetFn)(IDirect3DDevice9*, D3DPRESENT_PARAMETERS*);
    typedef HRESULT (__stdcall* SetViewportFn)(IDirect3DDevice9*, const D3DVIEWPORT9*);
    typedef HRESULT (__stdcall* SetRenderStateFn)(IDirect3DDevice9*, D3DRENDERSTATETYPE, DWORD);
    typedef HRESULT (__stdcall* SetTextureFn)(IDirect3DDevice9*, DWORD, IDirect3DBaseTexture9*);
    typedef HRESULT (__stdcall* SetSamplerStateFn)(IDirect3DDevice9*, DWORD, D3DSAMPLERSTATETYPE, DWORD);
    typedef HRESULT (__stdcall* DrawIndexedPrimitiveFn)(IDirect3DDevice9*, D3DPRIMITIVETYPE, INT, UINT, UINT, UINT, UINT);
    typedef HRESULT (__stdcall* SetVertexDeclarationFn)(IDirect3DDevice9*, IDirect3DVertexDeclaration9*);
    typedef HRESULT (__stdcall* SetFVFFn)(IDirect3DDevice9*, DWORD);
    typedef HRESULT (__stdcall* SetVertexShaderFn)(IDirect3DDevice9*, IDirect3DVertexShader9*);
    typedef HRESULT (__stdcall* SetStreamSourceFn)(IDirect3DDevice9*, UINT, IDirect3DVertexBuffer9*, UINT, UINT);
    typedef HRESULT (__stdcall* SetPixelShaderFn)(IDirect3DDevice9*, IDirect3DPixelShader9*);
    typedef HRESULT (__stdcall* SetShaderConstantFFn)(IDirect3DDevice9*, UINT, const float*, UINT);

    ResetFn s_reset = nullptr;
    SetViewportFn s_setViewport = nullptr;
    SetRenderStateFn s_setRenderState = nullptr;
    SetTextureFn s_setTexture = nullptr;
    SetSamplerStateFn s_setSamplerState = nullptr;
    DrawIndexedPrimitiveFn s_drawIndexed = nullptr;
    SetVertexDeclarationFn s_setVertexDeclaration = nullptr;
    SetFVFFn s_setFVF = nullptr;
    SetVertexShaderFn s_setVertexShader = nullptr;
    SetStreamSourceFn s_setStreamSource = nullptr;
    SetPixelShaderFn s_setPixelShader = nullptr;
    SetShaderConstantFFn s_setPsConstant = nullptr;

    struct Shadow
    {
        DWORD RenderStates[256] = {};
        bool Known[256] = {};
        D3DVIEWPORT9 Viewport = {};
        bool ViewportKnown = false;
        IDirect3DBaseTexture9* Texture0 = nullptr;
        DWORD Sampler0[SHADOW_SAMPLER_STATES] = {};
        bool SamplerKnown[SHADOW_SAMPLER_STATES] = {};
        IDirect3DVertexDeclaration9* Declaration = nullptr;
        DWORD FVF = 0;
        bool DeclarationLast = true;        // the last of SetVertexDeclaration / SetFVF
        IDirect3DVertexShader9* VertexShader = nullptr;
        IDirect3DVertexBuffer9* Stream0 = nullptr;
        UINT Stream0Offset = 0, Stream0Stride = 0;
        IDirect3DPixelShader9* PixelShader = nullptr;
        float PsConstants[SHADOW_PS_REGISTERS * 4] = {};
    } s_shadow;

    HRESULT __stdcall SetViewportDetour(IDirect3DDevice9* device, const D3DVIEWPORT9* viewport)
    {
        if (viewport)
        {
            s_shadow.Viewport = *viewport;
            s_shadow.ViewportKnown = true;
        }
        return s_setViewport(device, viewport);
    }

    HRESULT __stdcall SetRenderStateDetour(IDirect3DDevice9* device, D3DRENDERSTATETYPE state, DWORD value)
    {
        if (state < 256)
        {
            s_shadow.RenderStates[state] = value;
            s_shadow.Known[state] = true;
        }
        return s_setRenderState(device, state, value);
    }

    HRESULT __stdcall SetTextureDetour(IDirect3DDevice9* device, DWORD stage, IDirect3DBaseTexture9* texture)
    {
        if (stage == 0)
            s_shadow.Texture0 = texture;
        return s_setTexture(device, stage, texture);
    }

    HRESULT __stdcall SetSamplerStateDetour(IDirect3DDevice9* device, DWORD sampler, D3DSAMPLERSTATETYPE type, DWORD value)
    {
        if (sampler == 0 && type < SHADOW_SAMPLER_STATES)
        {
            s_shadow.Sampler0[type] = value;
            s_shadow.SamplerKnown[type] = true;
        }
        return s_setSamplerState(device, sampler, type, value);
    }

    HRESULT __stdcall SetVertexDeclarationDetour(IDirect3DDevice9* device, IDirect3DVertexDeclaration9* declaration)
    {
        s_shadow.Declaration = declaration;
        s_shadow.DeclarationLast = true;
        return s_setVertexDeclaration(device, declaration);
    }

    HRESULT __stdcall SetFVFDetour(IDirect3DDevice9* device, DWORD fvf)
    {
        s_shadow.FVF = fvf;
        s_shadow.DeclarationLast = false;
        return s_setFVF(device, fvf);
    }

    HRESULT __stdcall SetVertexShaderDetour(IDirect3DDevice9* device, IDirect3DVertexShader9* shader)
    {
        s_shadow.VertexShader = shader;
        return s_setVertexShader(device, shader);
    }

    HRESULT __stdcall SetStreamSourceDetour(IDirect3DDevice9* device, UINT stream, IDirect3DVertexBuffer9* buffer, UINT offset, UINT stride)
    {
        if (stream == 0)
        {
            s_shadow.Stream0 = buffer;
            s_shadow.Stream0Offset = offset;
            s_shadow.Stream0Stride = stride;
        }
        return s_setStreamSource(device, stream, buffer, offset, stride);
    }

    HRESULT __stdcall SetPixelShaderDetour(IDirect3DDevice9* device, IDirect3DPixelShader9* shader)
    {
        s_shadow.PixelShader = shader;
        return s_setPixelShader(device, shader);
    }

    HRESULT __stdcall SetPsConstantDetour(IDirect3DDevice9* device, UINT start, const float* data, UINT count)
    {
        if (data && start < SHADOW_PS_REGISTERS)
        {
            UINT copy = (start + count > SHADOW_PS_REGISTERS) ? SHADOW_PS_REGISTERS - start : count;
            memcpy(&s_shadow.PsConstants[start * 4], data, copy * 4 * sizeof(float));
        }
        return s_setPsConstant(device, start, data, count);
    }

    // ---------------------------------------------------------------- states we set, and Gx's back
    struct StateValue
    {
        D3DRENDERSTATETYPE State;
        DWORD Default;      // the device default, for a state Gx never set since the hooks went in
    };

    const StateValue TOUCHED_STATES[] = {
        { D3DRS_ZENABLE, D3DZB_TRUE }, { D3DRS_ZWRITEENABLE, TRUE }, { D3DRS_ZFUNC, D3DCMP_LESSEQUAL },
        { D3DRS_ALPHABLENDENABLE, FALSE }, { D3DRS_SRCBLEND, D3DBLEND_ONE }, { D3DRS_DESTBLEND, D3DBLEND_ZERO },
        { D3DRS_BLENDOP, D3DBLENDOP_ADD }, { D3DRS_SEPARATEALPHABLENDENABLE, FALSE },
        { D3DRS_ALPHATESTENABLE, FALSE }, { D3DRS_FOGENABLE, FALSE }, { D3DRS_COLORWRITEENABLE, 0xF },
        { D3DRS_STENCILENABLE, FALSE }, { D3DRS_SCISSORTESTENABLE, FALSE }, { D3DRS_CLIPPLANEENABLE, 0 },
        { D3DRS_CULLMODE, D3DCULL_CCW }, { D3DRS_SRGBWRITEENABLE, FALSE },
    };

    void SetState(IDirect3DDevice9* device, D3DRENDERSTATETYPE state, DWORD value)
    {
        s_setRenderState(device, state, value);
    }

    // no depth, no blend, nothing cut away: the silhouette into the mask / the stage 1 test
    void SetSilhouetteStates(IDirect3DDevice9* device)
    {
        SetState(device, D3DRS_ZENABLE, FALSE);
        SetState(device, D3DRS_ZWRITEENABLE, FALSE);
        SetState(device, D3DRS_ALPHABLENDENABLE, FALSE);
        SetState(device, D3DRS_SEPARATEALPHABLENDENABLE, FALSE);
        SetState(device, D3DRS_ALPHATESTENABLE, FALSE);
        SetState(device, D3DRS_FOGENABLE, FALSE);
        SetState(device, D3DRS_COLORWRITEENABLE, 0xF);
        SetState(device, D3DRS_STENCILENABLE, FALSE);
        SetState(device, D3DRS_SCISSORTESTENABLE, FALSE);
        SetState(device, D3DRS_CLIPPLANEENABLE, 0);
        SetState(device, D3DRS_CULLMODE, D3DCULL_NONE);
        SetState(device, D3DRS_SRGBWRITEENABLE, FALSE);
    }

    void RestoreStates(IDirect3DDevice9* device)
    {
        for (StateValue const& entry : TOUCHED_STATES)
            s_setRenderState(device, entry.State, s_shadow.Known[entry.State] ? s_shadow.RenderStates[entry.State] : entry.Default);
    }

    void RestorePixelShader(IDirect3DDevice9* device)
    {
        s_setPixelShader(device, s_shadow.PixelShader);
        s_setPsConstant(device, 0, s_shadow.PsConstants, SHADOW_PS_REGISTERS);
    }

    // after SetRenderTarget the viewport is the whole target: Gx's back
    void RestoreViewport(IDirect3DDevice9* device)
    {
        if (s_shadow.ViewportKnown)
            s_setViewport(device, &s_shadow.Viewport);
    }

    // ---------------------------------------------------------------- our device objects
    void ReleaseMask()
    {
        if (s_maskSurface)
            s_maskSurface->Release();
        if (s_mask)
            s_mask->Release();
        s_maskSurface = nullptr;
        s_mask = nullptr;
        s_maskWidth = s_maskHeight = 0;
        s_maskDirty = false;
    }

    HRESULT __stdcall ResetDetour(IDirect3DDevice9* device, D3DPRESENT_PARAMETERS* parameters)
    {
        ReleaseMask();      // a default pool resource: a reset fails while it exists
        return s_reset(device, parameters);
    }

    // 0, or the error code of what failed (OutlineDebug #8)
    uint32_t CreateShaders(IDirect3DDevice9* device)
    {
        using namespace OutlineShaders;
        if (!s_flatShader && FAILED(device->CreatePixelShader(SHADER_FLAT_PS, &s_flatShader)))
            return 2;
        if (!s_outlineShader && FAILED(device->CreatePixelShader(SHADER_OUTLINE_PS, &s_outlineShader)))
            return 5;
        if (!s_outlineLowShader && FAILED(device->CreatePixelShader(SHADER_OUTLINE_LOW_PS, &s_outlineLowShader)))
            return 6;
        if (!s_quadShader && FAILED(device->CreateVertexShader(SHADER_QUAD_VS, &s_quadShader)))
            return 7;
        if (!s_quadDeclaration)
        {
            const D3DVERTEXELEMENT9 elements[] = {
                { 0, 0, D3DDECLTYPE_FLOAT4, D3DDECLMETHOD_DEFAULT, D3DDECLUSAGE_POSITION, 0 },
                { 0, 16, D3DDECLTYPE_FLOAT2, D3DDECLMETHOD_DEFAULT, D3DDECLUSAGE_TEXCOORD, 0 },
                D3DDECL_END(),
            };
            if (FAILED(device->CreateVertexDeclaration(elements, &s_quadDeclaration)))
                return 8;
        }
        return 0;
    }

    // the mask: as big as the back buffer (made again when that changes, after a reset)
    bool EnsureMask(IDirect3DDevice9* device)
    {
        IDirect3DSurface9* backBuffer = nullptr;
        if (FAILED(device->GetBackBuffer(0, 0, D3DBACKBUFFER_TYPE_MONO, &backBuffer)) || !backBuffer)
            return false;
        D3DSURFACE_DESC desc = {};
        backBuffer->GetDesc(&desc);
        backBuffer->Release();

        if (s_mask && s_maskWidth == desc.Width && s_maskHeight == desc.Height)
            return true;
        ReleaseMask();
        if (FAILED(device->CreateTexture(desc.Width, desc.Height, 1, D3DUSAGE_RENDERTARGET, D3DFMT_A8R8G8B8,
            D3DPOOL_DEFAULT, &s_mask, nullptr)) || !s_mask)
        {
            s_mask = nullptr;
            s_stats.Error = 3;
            return false;
        }
        s_mask->GetSurfaceLevel(0, &s_maskSurface);
        s_maskWidth = desc.Width;
        s_maskHeight = desc.Height;
        s_maskDirty = true;     // cleared before the first use
        return s_maskSurface != nullptr;
    }

    bool EnsureQuadBuffer(IDirect3DDevice9* device)
    {
        if (s_quadBuffer)
            return true;
        if (FAILED(device->CreateVertexBuffer(4 * sizeof(QuadVertex), D3DUSAGE_WRITEONLY, 0, D3DPOOL_MANAGED, &s_quadBuffer, nullptr)))
        {
            s_quadBuffer = nullptr;
            s_stats.Error = 4;
            return false;
        }
        return true;
    }

    // the whole screen, a texel to a pixel (D3D9: positions half a pixel up-left)
    void FillQuad(UINT width, UINT height)
    {
        QuadVertex* vertices = nullptr;
        if (FAILED(s_quadBuffer->Lock(0, 0, reinterpret_cast<void**>(&vertices), 0)))
            return;
        float dx = 1.0f / width, dy = 1.0f / height;
        const QuadVertex quad[4] = {
            { -1.0f - dx,  1.0f + dy, 0.0f, 1.0f, 0.0f, 0.0f },
            {  1.0f - dx,  1.0f + dy, 0.0f, 1.0f, 1.0f, 0.0f },
            { -1.0f - dx, -1.0f + dy, 0.0f, 1.0f, 0.0f, 1.0f },
            {  1.0f - dx, -1.0f + dy, 0.0f, 1.0f, 1.0f, 1.0f },
        };
        memcpy(vertices, quad, sizeof(quad));
        s_quadBuffer->Unlock();
    }

    // the mask empty again (the render target switched to it and back)
    void ClearMask(IDirect3DDevice9* device)
    {
        if (!s_maskSurface || !s_maskDirty)
            return;
        IDirect3DSurface9* renderTarget = nullptr;
        IDirect3DSurface9* depthStencil = nullptr;
        device->GetRenderTarget(0, &renderTarget);
        device->GetDepthStencilSurface(&depthStencil);
        device->SetRenderTarget(0, s_maskSurface);
        device->SetDepthStencilSurface(nullptr);
        device->Clear(0, nullptr, D3DCLEAR_TARGET, 0x00000000, 1.0f, 0);
        device->SetRenderTarget(0, renderTarget);
        device->SetDepthStencilSurface(depthStencil);
        if (renderTarget)
            renderTarget->Release();
        if (depthStencil)
            depthStencil->Release();
        RestoreViewport(device);
        s_maskDirty = false;
    }

    // ---------------------------------------------------------------- 1. the silhouettes
    HRESULT __stdcall DrawIndexedPrimitiveDetour(IDirect3DDevice9* device, D3DPRIMITIVETYPE type, INT baseVertex,
        UINT minIndex, UINT numVertices, UINT startIndex, UINT primitiveCount)
    {
        HRESULT result = s_drawIndexed(device, type, baseVertex, minIndex, numVertices, startIndex, primitiveCount);
        if (!s_currentTarget || (s_mode & 1))
            return result;
        bool toScreen = (s_mode & 8) != 0;
        if (!toScreen && !s_maskSurface)
            return result;

        // the same draw once more: our shader, the color; into the mask (or the screen: stage 1 test)
        // (the depth buffer off too: with antialiasing it doesn't fit our plain texture and the draw would fail)
        IDirect3DSurface9* renderTarget = nullptr;
        IDirect3DSurface9* depthStencil = nullptr;
        if (!toScreen)
        {
            device->GetRenderTarget(0, &renderTarget);
            device->GetDepthStencilSurface(&depthStencil);
            device->SetRenderTarget(0, s_maskSurface);
            device->SetDepthStencilSurface(nullptr);
        }
        s_setPixelShader(device, s_flatShader);
        s_setPsConstant(device, 0, s_currentTarget->Color, 1);
        SetSilhouetteStates(device);

        s_drawIndexed(device, type, baseVertex, minIndex, numVertices, startIndex, primitiveCount);
        ++s_frameSilhouettes;
        s_maskDirty = true;

        if (!toScreen)
        {
            device->SetRenderTarget(0, renderTarget);
            device->SetDepthStencilSurface(depthStencil);
            if (renderTarget)
                renderTarget->Release();
            if (depthStencil)
                depthStencil->Release();
            RestoreViewport(device);
        }
        RestorePixelShader(device);
        RestoreStates(device);
        return result;
    }

    // ---------------------------------------------------------------- 2. the outline over the screen
    void Composite(IDirect3DDevice9* device)
    {
        if (!s_maskSurface || !s_frameSilhouettes || (s_mode & (2 | 8)))
            return;
        FillQuad(s_maskWidth, s_maskHeight);

        const float texel[4] = { 1.0f / s_maskWidth, 1.0f / s_maskHeight, 0.0f, 0.0f };
        const float look[4] = { (s_mode & 4) ? ALPHA_GAIN_LOW : ALPHA_GAIN_HIGH, STRENGTH, 0.0f, 0.0f };

        s_setVertexShader(device, s_quadShader);
        s_setPixelShader(device, (s_mode & 4) ? s_outlineLowShader : s_outlineShader);
        s_setPsConstant(device, 0, texel, 1);
        s_setPsConstant(device, 1, look, 1);
        s_setVertexDeclaration(device, s_quadDeclaration);
        s_setStreamSource(device, 0, s_quadBuffer, 0, sizeof(QuadVertex));
        s_setTexture(device, 0, s_mask);
        s_setSamplerState(device, 0, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
        s_setSamplerState(device, 0, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);
        s_setSamplerState(device, 0, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
        s_setSamplerState(device, 0, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);
        s_setSamplerState(device, 0, D3DSAMP_MIPFILTER, D3DTEXF_NONE);
        s_setSamplerState(device, 0, D3DSAMP_SRGBTEXTURE, FALSE);

        SetSilhouetteStates(device);
        SetState(device, D3DRS_ALPHABLENDENABLE, TRUE);
        SetState(device, D3DRS_SRCBLEND, D3DBLEND_SRCALPHA);
        SetState(device, D3DRS_DESTBLEND, D3DBLEND_INVSRCALPHA);
        SetState(device, D3DRS_BLENDOP, D3DBLENDOP_ADD);
        SetState(device, D3DRS_COLORWRITEENABLE, 0x7);     // the screen's alpha stays

        device->DrawPrimitive(D3DPT_TRIANGLESTRIP, 0, 2);
        ++s_stats.Composites;

        // Gx's back
        s_setVertexShader(device, s_shadow.VertexShader);
        RestorePixelShader(device);
        if (s_shadow.DeclarationLast)
            s_setVertexDeclaration(device, s_shadow.Declaration);
        else
            s_setFVF(device, s_shadow.FVF);
        s_setStreamSource(device, 0, s_shadow.Stream0, s_shadow.Stream0Offset, s_shadow.Stream0Stride);
        s_setTexture(device, 0, s_shadow.Texture0);
        const D3DSAMPLERSTATETYPE samplers[] = { D3DSAMP_ADDRESSU, D3DSAMP_ADDRESSV, D3DSAMP_MAGFILTER, D3DSAMP_MINFILTER, D3DSAMP_MIPFILTER, D3DSAMP_SRGBTEXTURE };
        const DWORD samplerDefaults[] = { D3DTADDRESS_WRAP, D3DTADDRESS_WRAP, D3DTEXF_POINT, D3DTEXF_POINT, D3DTEXF_NONE, FALSE };
        for (size_t i = 0; i < sizeof(samplers) / sizeof(samplers[0]); ++i)
            s_setSamplerState(device, 0, samplers[i], s_shadow.SamplerKnown[samplers[i]] ? s_shadow.Sampler0[samplers[i]] : samplerDefaults[i]);
        RestoreStates(device);
    }

    template <typename Fn>
    void HookVtable(void** vtable, uint32_t index, Fn& original, void* detour)
    {
        DWORD old = 0;
        if (!VirtualProtect(&vtable[index], sizeof(void*), PAGE_EXECUTE_READWRITE, &old))
            return;
        original = reinterpret_cast<Fn>(vtable[index]);
        vtable[index] = detour;
        VirtualProtect(&vtable[index], sizeof(void*), old, &old);
    }

    // the device's vtable (the device lives as long as the client: done once, as soon as it exists)
    void HookDevice()
    {
        if (s_stats.Installed & 4)
            return;
        IDirect3DDevice9* device = GetD3DDevice();
        if (!device)
        {
            s_stats.Error = 1;
            return;
        }
        if (uint32_t error = CreateShaders(device))
        {
            s_stats.Error = error;
            return;
        }
        s_stats.Error = 0;
        void** vtable = *reinterpret_cast<void***>(device);
        HookVtable(vtable, VT_RESET, s_reset, reinterpret_cast<void*>(&ResetDetour));
        HookVtable(vtable, VT_SET_VIEWPORT, s_setViewport, reinterpret_cast<void*>(&SetViewportDetour));
        HookVtable(vtable, VT_SET_RENDER_STATE, s_setRenderState, reinterpret_cast<void*>(&SetRenderStateDetour));
        HookVtable(vtable, VT_SET_TEXTURE, s_setTexture, reinterpret_cast<void*>(&SetTextureDetour));
        HookVtable(vtable, VT_SET_SAMPLER_STATE, s_setSamplerState, reinterpret_cast<void*>(&SetSamplerStateDetour));
        HookVtable(vtable, VT_SET_VERTEX_DECL, s_setVertexDeclaration, reinterpret_cast<void*>(&SetVertexDeclarationDetour));
        HookVtable(vtable, VT_SET_FVF, s_setFVF, reinterpret_cast<void*>(&SetFVFDetour));
        HookVtable(vtable, VT_SET_VERTEX_SHADER, s_setVertexShader, reinterpret_cast<void*>(&SetVertexShaderDetour));
        HookVtable(vtable, VT_SET_STREAM_SOURCE, s_setStreamSource, reinterpret_cast<void*>(&SetStreamSourceDetour));
        HookVtable(vtable, VT_SET_PIXEL_SHADER, s_setPixelShader, reinterpret_cast<void*>(&SetPixelShaderDetour));
        HookVtable(vtable, VT_SET_PS_CONSTANT_F, s_setPsConstant, reinterpret_cast<void*>(&SetPsConstantDetour));
        HookVtable(vtable, VT_DRAW_INDEXED, s_drawIndexed, reinterpret_cast<void*>(&DrawIndexedPrimitiveDetour));
        if (s_reset && s_setViewport && s_setRenderState && s_setTexture && s_setSamplerState && s_setVertexDeclaration
            && s_setFVF && s_setVertexShader && s_setStreamSource && s_setPixelShader && s_setPsConstant && s_drawIndexed)
            s_stats.Installed |= 4;
    }

    // ---------------------------------------------------------------- detours
    void __fastcall DrawBatchDetour(uint8_t* batch, void* /*edx*/)
    {
        ++s_stats.BatchDraws;
        Target const* target = (s_stats.Installed & 4) && !s_targets.empty() ? FindTarget(batch) : nullptr;
        if (target)
            ++s_frameBatches;

        s_currentTarget = target;
        s_hookDrawBatch.Unpatch();
        reinterpret_cast<void (__thiscall*)(void*)>(ADDR_M2_DRAW_BATCH)(batch);
        s_hookDrawBatch.Repatch();
        s_currentTarget = nullptr;
    }

    // once a frame, after the 3D scene: the outline, then the next frame gets ready
    void __cdecl OnWorldRender()
    {
        HookDevice();
        ++s_stats.WorldRenders;
        IDirect3DDevice9* device = GetD3DDevice();
        if (device && (s_stats.Installed & 4))
        {
            Composite(device);
            if (EnsureMask(device) && EnsureQuadBuffer(device))
                ClearMask(device);
        }
        s_stats.TargetBatches = s_frameBatches;
        s_stats.Silhouettes = s_frameSilhouettes;
        s_frameBatches = s_frameSilhouettes = 0;
        CollectTargets();
    }

    // ---------------------------------------------------------------- the mid-function hook at 0x4F9240
    // 0x4F9240 is a place inside the world render function: our code runs there, then the instructions we
    // overwrote (copied to a trampoline) and a jmp back right after them.

    // the length of one x86 instruction (the usual compiler output; 0 - not handled)
    size_t ModRmLength(const uint8_t* p, bool address16)
    {
        uint8_t modrm = p[0];
        uint8_t mod = modrm >> 6, rm = modrm & 7;
        size_t length = 1;
        if (address16)
            return 0;
        if (mod != 3 && rm == 4)
        {
            uint8_t sib = p[1];
            ++length;
            if (mod == 0 && (sib & 7) == 5)
                length += 4;
        }
        if (mod == 1)
            length += 1;
        else if (mod == 2 || (mod == 0 && rm == 5))
            length += 4;
        return length;
    }

    // relative: the instruction has a rel32 at its end (call / jmp / jcc) - fixed when copied
    size_t InstructionLength(const uint8_t* code, bool& relative32, bool& relative8)
    {
        relative32 = relative8 = false;
        const uint8_t* p = code;
        bool operand16 = false;
        while (*p == 0x66 || *p == 0x67 || *p == 0xF2 || *p == 0xF3 || *p == 0x2E || *p == 0x3E || *p == 0x26 || *p == 0x36 || *p == 0x64 || *p == 0x65)
        {
            if (*p == 0x66)
                operand16 = true;
            if (*p == 0x67)
                return 0;
            ++p;
        }
        size_t prefixes = p - code;
        uint8_t op = *p++;
        size_t imm = operand16 ? 2 : 4;

        if (op >= 0x50 && op <= 0x61) return prefixes + 1;                     // push / pop reg, pushad, popad
        if (op >= 0x40 && op <= 0x4F) return prefixes + 1;                     // inc / dec reg
        if (op >= 0x90 && op <= 0x99) return prefixes + 1;                     // nop, xchg, cwde, cdq
        if (op == 0x9C || op == 0x9D || op == 0xC3 || op == 0xCC) return prefixes + 1;
        if (op >= 0xB0 && op <= 0xB7) return prefixes + 2;                     // mov r8, imm8
        if (op >= 0xB8 && op <= 0xBF) return prefixes + 1 + imm;               // mov reg, imm
        if (op == 0x6A) return prefixes + 2;                                   // push imm8
        if (op == 0x68) return prefixes + 1 + imm;                             // push imm
        if (op == 0xA8) return prefixes + 2;                                   // test al, imm8
        if (op == 0xA9) return prefixes + 1 + imm;                             // test eax, imm
        if (op >= 0xA0 && op <= 0xA3) return prefixes + 5;                     // mov eax, [moffs]
        if (op == 0x04 || op == 0x0C || op == 0x14 || op == 0x1C || op == 0x24 || op == 0x2C || op == 0x34 || op == 0x3C)
            return prefixes + 2;                                               // op al, imm8
        if (op == 0x05 || op == 0x0D || op == 0x15 || op == 0x1D || op == 0x25 || op == 0x2D || op == 0x35 || op == 0x3D)
            return prefixes + 1 + imm;                                         // op eax, imm
        if (op == 0xC2) return prefixes + 3;                                   // ret imm16
        if (op == 0xE8 || op == 0xE9) { relative32 = true; return prefixes + 5; }
        if (op == 0xEB || (op >= 0x70 && op <= 0x7F)) { relative8 = true; return prefixes + 2; }

        // modrm forms: alu r/m, mov, lea, test, xchg, fpu, ...
        if ((op <= 0x3F && (op & 7) <= 3) || (op >= 0x84 && op <= 0x8F) || (op >= 0xD8 && op <= 0xDF) || op == 0xD0 || op == 0xD1 || op == 0xD2 || op == 0xD3 || op == 0xFE || op == 0xFF)
        {
            size_t m = ModRmLength(p, false);
            return m ? prefixes + 1 + m : 0;
        }
        if (op == 0x80 || op == 0x82 || op == 0x83 || op == 0xC0 || op == 0xC1 || op == 0xC6 || op == 0x6B)
        {
            size_t m = ModRmLength(p, false);
            return m ? prefixes + 1 + m + 1 : 0;
        }
        if (op == 0x81 || op == 0xC7 || op == 0x69)
        {
            size_t m = ModRmLength(p, false);
            return m ? prefixes + 1 + m + imm : 0;
        }
        if (op == 0xF6 || op == 0xF7)
        {
            size_t m = ModRmLength(p, false);
            if (!m)
                return 0;
            bool hasImm = ((p[0] >> 3) & 7) <= 1;                            // test r/m, imm
            return prefixes + 1 + m + (hasImm ? (op == 0xF6 ? 1 : imm) : 0);
        }
        if (op == 0x0F)
        {
            uint8_t op2 = *p++;
            if (op2 >= 0x80 && op2 <= 0x8F) { relative32 = true; return prefixes + 6; }   // jcc rel32
            if ((op2 >= 0x90 && op2 <= 0x9F) || op2 == 0xAF || op2 == 0xB6 || op2 == 0xB7 || op2 == 0xBE || op2 == 0xBF
                || (op2 >= 0x10 && op2 <= 0x17) || (op2 >= 0x28 && op2 <= 0x2F) || (op2 >= 0x40 && op2 <= 0x4F)
                || (op2 >= 0x51 && op2 <= 0x7F) || op2 == 0xD6 || op2 == 0xE6 || op2 == 0xEF || op2 == 0x18)
            {
                size_t m = ModRmLength(p, false);
                return m ? prefixes + 2 + m : 0;
            }
            if (op2 == 0xC6 || op2 == 0x70 || op2 == 0xC2)
            {
                size_t m = ModRmLength(p, false);
                return m ? prefixes + 2 + m + 1 : 0;
            }
            return 0;
        }
        return 0;
    }

    struct MidHook
    {
        uintptr_t Site = 0;
        size_t Length = 0;
        uint8_t* Trampoline = nullptr;
        uint8_t Bytes[16] = {};     // OutlineDebug: what was there

        // `detour` runs at `site` (it must end with `jmp [trampoline]`)
        bool Install(uintptr_t site, void* detour)
        {
            Site = site;
            memcpy(Bytes, reinterpret_cast<void*>(site), sizeof(Bytes));
            Trampoline = static_cast<uint8_t*>(VirtualAlloc(nullptr, 64, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
            if (!Trampoline)
                return false;

            // whole instructions covering the 5 bytes of our jmp, copied (rel32 fixed, rel8 not allowed)
            size_t length = 0;
            uint8_t* out = Trampoline;
            while (length < 5)
            {
                bool rel32 = false, rel8 = false;
                const uint8_t* instruction = reinterpret_cast<const uint8_t*>(site + length);
                size_t size = InstructionLength(instruction, rel32, rel8);
                if (!size || rel8 || length + size > 15)
                    return false;
                memcpy(out, instruction, size);
                if (rel32)
                {
                    int32_t& displacement = *reinterpret_cast<int32_t*>(out + size - 4);
                    uintptr_t destination = site + length + size + *reinterpret_cast<const int32_t*>(instruction + size - 4);
                    displacement = static_cast<int32_t>(destination - (reinterpret_cast<uintptr_t>(out) + size));
                }
                out += size;
                length += size;
            }
            // back to the rest of the original code
            out[0] = 0xE9;
            *reinterpret_cast<int32_t*>(out + 1) = static_cast<int32_t>((site + length) - (reinterpret_cast<uintptr_t>(out) + 5));
            Length = length;

            uint8_t patch[16];
            memset(patch, 0x90, sizeof(patch));
            patch[0] = 0xE9;
            *reinterpret_cast<int32_t*>(patch + 1) = static_cast<int32_t>(reinterpret_cast<uintptr_t>(detour) - (site + 5));
            return HookUtil::WriteCode(site, patch, length);
        }
    };

    MidHook s_hookWorldRender;
    uint8_t* s_worldRenderTrampoline = nullptr;

    // everything (registers, flags, FPU/SSE) kept for the code we interrupt
    __declspec(naked) void WorldRenderDetour()
    {
        __asm
        {
            pushad
            pushfd
            mov ebp, esp
            sub esp, 0x200
            and esp, 0xFFFFFFF0
            fxsave [esp]
            call OnWorldRender
            fxrstor [esp]
            mov esp, ebp
            popfd
            popad
            jmp dword ptr [s_worldRenderTrampoline]
        }
    }
}

void Outline::ApplyPatches()
{
    s_targets.reserve(4);
    if (s_hookDrawBatch.Install(ADDR_M2_DRAW_BATCH, reinterpret_cast<void*>(&DrawBatchDetour)))
        s_stats.Installed |= 1;
    if (s_hookWorldRender.Install(ADDR_WORLD_RENDER, reinterpret_cast<void*>(&WorldRenderDetour)))
    {
        s_worldRenderTrampoline = s_hookWorldRender.Trampoline;
        s_stats.Installed |= 2;
    }
}

// /run print(OutlineDebug())
// installed, world renders, batch draws, targets, target batches, silhouettes, gx api, error, mode, composites, mask w, h
int32_t Outline::OutlineDebug(lua_State* L)
{
    FrameScript::PushNumber(L, s_stats.Installed);
    FrameScript::PushNumber(L, s_stats.WorldRenders);
    FrameScript::PushNumber(L, s_stats.BatchDraws);
    FrameScript::PushNumber(L, s_stats.Targets);
    FrameScript::PushNumber(L, s_stats.TargetBatches);
    FrameScript::PushNumber(L, s_stats.Silhouettes);
    FrameScript::PushNumber(L, s_stats.GxApi);
    FrameScript::PushNumber(L, s_stats.Error);
    FrameScript::PushNumber(L, s_mode);
    FrameScript::PushNumber(L, s_stats.Composites);
    FrameScript::PushNumber(L, s_maskWidth);
    FrameScript::PushNumber(L, s_maskHeight);
    return 12;
}

// /run OutlineMode(n): 1 no silhouettes, 2 no full-screen pass, 4 low quality, 8 stage 1 (silhouettes on the screen)
int32_t Outline::OutlineMode(lua_State* L)
{
    s_mode = static_cast<uint32_t>(FrameScript::GetNumber(L, 1));
    return 0;
}
