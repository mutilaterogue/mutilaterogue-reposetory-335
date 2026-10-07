#include <Outline/Outline.hpp>

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

// Stage 1. No M2 / Gx function is ever called a second time (that changes their caches - the world broke):
// when the client itself draws a batch of an outlined model, the same DrawIndexedPrimitive is issued once more
// right after it, with our pixel shader - every state (bones, buffers, camera) is the client's own at that moment.
// Then exactly the states Gx sent are put back (from a copy: the client's device can't be read back).

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
        uint32_t Silhouettes = 0;           // extra draw calls in the last frame
        uint32_t OnScreen = 0;              // of them, drawn into the back buffer
        uint32_t GxApi = 0;
        uint32_t Error = 0;                 // 1 no device, 2 shader
    } s_stats;
    uint32_t s_frameBatches = 0;
    uint32_t s_frameSilhouettes = 0;
    uint32_t s_frameOnScreen = 0;
    uint32_t s_lastVsMajor = 0;         // OutlineDebug: the vertex shader model of the last silhouette

    // OutlineMode(bits): 1 - no extra draw (find the batches only), 2 - keep the depth test,
    //  4 - the silhouette writes depth and draws over everything (nothing drawn later covers it)
    uint32_t s_mode = 0;

    std::vector<Target> s_targets;
    Target const* s_currentTarget = nullptr;    // set while the client draws a batch of an outlined model

    // mov oC0, c0 - the color in c0. Two versions: a vs_3_0 vertex shader needs a ps_3_0 pixel shader
    // (a ps_2_0 with it draws nothing), a vs_1/vs_2 one a ps_2_0.
    IDirect3DPixelShader9* s_flatShader = nullptr;      // ps_2_0
    IDirect3DPixelShader9* s_flatShader3 = nullptr;     // ps_3_0
    const DWORD FLAT_SHADER[] = { 0xFFFF0200, 0x02000001, 0x800F0800, 0xA0E40000, 0x0000FFFF };
    const DWORD FLAT_SHADER3[] = { 0xFFFF0300, 0x02000001, 0x800F0800, 0xA0E40000, 0x0000FFFF };

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

    // ---------------------------------------------------------------- helpers
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

    // the models of the next frame (stage 1: the target red, the mouseover yellow)
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

    // ---------------------------------------------------------------- the device
    // What Gx sends is copied as it goes (the device can't be read back): after our draw call exactly that
    // is put back, so Gx's cache and the device never disagree.
    enum VtableIndex : uint32_t
    {
        VT_SET_RENDER_STATE  = 57,
        VT_DRAW_INDEXED      = 82,
        VT_SET_VERTEX_SHADER = 92,
        VT_SET_PIXEL_SHADER  = 107,
        VT_SET_PS_CONSTANT_F = 109,
    };

    typedef HRESULT (__stdcall* SetRenderStateFn)(IDirect3DDevice9*, D3DRENDERSTATETYPE, DWORD);
    typedef HRESULT (__stdcall* DrawIndexedPrimitiveFn)(IDirect3DDevice9*, D3DPRIMITIVETYPE, INT, UINT, UINT, UINT, UINT);
    typedef HRESULT (__stdcall* SetShaderConstantFFn)(IDirect3DDevice9*, UINT, const float*, UINT);
    typedef HRESULT (__stdcall* SetPixelShaderFn)(IDirect3DDevice9*, IDirect3DPixelShader9*);
    typedef HRESULT (__stdcall* SetVertexShaderFn)(IDirect3DDevice9*, IDirect3DVertexShader9*);

    SetRenderStateFn s_setRenderState = nullptr;
    DrawIndexedPrimitiveFn s_drawIndexed = nullptr;
    SetPixelShaderFn s_setPixelShader = nullptr;
    SetShaderConstantFFn s_setPsConstant = nullptr;
    SetVertexShaderFn s_setVertexShader = nullptr;
    IDirect3DVertexShader9* s_vertexShader = nullptr;   // the current one (what Gx set)

    // the shader model of a vertex shader (its first token), cached
    struct VertexShaderVersion
    {
        IDirect3DVertexShader9* Shader;
        uint32_t Major;
    };
    std::vector<VertexShaderVersion> s_vsVersions;

    uint32_t VertexShaderMajor(IDirect3DVertexShader9* shader)
    {
        if (!shader)
            return 0;
        for (VertexShaderVersion const& entry : s_vsVersions)
            if (entry.Shader == shader)
                return entry.Major;
        uint32_t major = 0;
        UINT size = 0;
        if (SUCCEEDED(shader->GetFunction(nullptr, &size)) && size >= 4)
        {
            std::vector<DWORD> code(size / 4);
            if (SUCCEEDED(shader->GetFunction(code.data(), &size)))
                major = (code[0] >> 8) & 0xFF;
        }
        if (s_vsVersions.size() > 4096)
            s_vsVersions.clear();
        s_vsVersions.push_back({ shader, major });
        return major;
    }

    HRESULT __stdcall SetVertexShaderDetour(IDirect3DDevice9* device, IDirect3DVertexShader9* shader)
    {
        s_vertexShader = shader;
        return s_setVertexShader(device, shader);
    }

    struct Shadow
    {
        DWORD RenderStates[256] = {};
        bool Known[256] = {};
        IDirect3DPixelShader9* PixelShader = nullptr;
        float PsConstant0[4] = {};
    } s_shadow;

    HRESULT __stdcall SetRenderStateDetour(IDirect3DDevice9* device, D3DRENDERSTATETYPE state, DWORD value)
    {
        if (state < 256)
        {
            s_shadow.RenderStates[state] = value;
            s_shadow.Known[state] = true;
        }
        return s_setRenderState(device, state, value);
    }

    HRESULT __stdcall SetPixelShaderDetour(IDirect3DDevice9* device, IDirect3DPixelShader9* shader)
    {
        s_shadow.PixelShader = shader;
        return s_setPixelShader(device, shader);
    }

    HRESULT __stdcall SetPsConstantDetour(IDirect3DDevice9* device, UINT start, const float* data, UINT count)
    {
        if (start == 0 && count > 0 && data)
            memcpy(s_shadow.PsConstant0, data, sizeof(s_shadow.PsConstant0));
        return s_setPsConstant(device, start, data, count);
    }

    // our states for the silhouette; the device defaults for the ones Gx never set since the hooks went in
    const D3DRENDERSTATETYPE SILHOUETTE_STATES[] = {
        D3DRS_ZENABLE, D3DRS_ZWRITEENABLE, D3DRS_ZFUNC, D3DRS_ALPHABLENDENABLE, D3DRS_ALPHATESTENABLE, D3DRS_FOGENABLE,
        D3DRS_COLORWRITEENABLE, D3DRS_STENCILENABLE, D3DRS_SCISSORTESTENABLE, D3DRS_CLIPPLANEENABLE, D3DRS_CULLMODE,
        D3DRS_SRGBWRITEENABLE,
    };
    // mode 4: the silhouette writes depth and wins over everything drawn later at the same place
    const DWORD SILHOUETTE_VALUES[] = { FALSE, FALSE, D3DCMP_LESSEQUAL, FALSE, FALSE, FALSE, 0xF, FALSE, FALSE, 0, D3DCULL_NONE, FALSE };
    const DWORD SILHOUETTE_VALUES_TOP[] = { D3DZB_TRUE, TRUE, D3DCMP_ALWAYS, FALSE, FALSE, FALSE, 0xF, FALSE, FALSE, 0, D3DCULL_NONE, FALSE };
    const DWORD STATE_DEFAULTS[] = { D3DZB_TRUE, TRUE, D3DCMP_LESSEQUAL, FALSE, FALSE, FALSE, 0xF, FALSE, FALSE, 0, D3DCULL_CCW, FALSE };
    constexpr size_t SILHOUETTE_STATE_COUNT = sizeof(SILHOUETTE_STATES) / sizeof(SILHOUETTE_STATES[0]);

    HRESULT __stdcall DrawIndexedPrimitiveDetour(IDirect3DDevice9* device, D3DPRIMITIVETYPE type, INT baseVertex,
        UINT minIndex, UINT numVertices, UINT startIndex, UINT primitiveCount)
    {
        HRESULT result = s_drawIndexed(device, type, baseVertex, minIndex, numVertices, startIndex, primitiveCount);
        if (!s_currentTarget || !s_flatShader || (s_mode & 1))
            return result;

        // the same draw once more: our shader and color, no depth test (stage 1: over everything)
        uint32_t vsMajor = VertexShaderMajor(s_vertexShader);
        s_lastVsMajor = vsMajor;
        s_setPixelShader(device, vsMajor >= 3 && s_flatShader3 ? s_flatShader3 : s_flatShader);
        s_setPsConstant(device, 0, s_currentTarget->Color, 1);
        const DWORD* values = (s_mode & 4) ? SILHOUETTE_VALUES_TOP : SILHOUETTE_VALUES;
        for (size_t i = 0; i < SILHOUETTE_STATE_COUNT; ++i)
            if (!((s_mode & 2) && SILHOUETTE_STATES[i] == D3DRS_ZENABLE))
                s_setRenderState(device, SILHOUETTE_STATES[i], values[i]);

        // where it goes: the screen or some other render target (reflections, ...)
        IDirect3DSurface9* renderTarget = nullptr;
        IDirect3DSurface9* backBuffer = nullptr;
        device->GetRenderTarget(0, &renderTarget);
        device->GetBackBuffer(0, 0, D3DBACKBUFFER_TYPE_MONO, &backBuffer);
        if (renderTarget && renderTarget == backBuffer)
            ++s_frameOnScreen;
        if (renderTarget)
            renderTarget->Release();
        if (backBuffer)
            backBuffer->Release();

        s_drawIndexed(device, type, baseVertex, minIndex, numVertices, startIndex, primitiveCount);
        ++s_frameSilhouettes;

        // Gx's own back
        s_setPixelShader(device, s_shadow.PixelShader);
        s_setPsConstant(device, 0, s_shadow.PsConstant0, 1);
        for (size_t i = 0; i < SILHOUETTE_STATE_COUNT; ++i)
        {
            D3DRENDERSTATETYPE state = SILHOUETTE_STATES[i];
            s_setRenderState(device, state, s_shadow.Known[state] ? s_shadow.RenderStates[state] : STATE_DEFAULTS[i]);
        }
        return result;
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
        if (!s_flatShader && FAILED(device->CreatePixelShader(FLAT_SHADER, &s_flatShader)))
        {
            s_flatShader = nullptr;
            s_stats.Error = 2;
            return;
        }
        if (!s_flatShader3 && FAILED(device->CreatePixelShader(FLAT_SHADER3, &s_flatShader3)))
            s_flatShader3 = nullptr;    // no shader model 3: the vertex shaders aren't vs_3_0 either
        s_stats.Error = 0;
        void** vtable = *reinterpret_cast<void***>(device);
        HookVtable(vtable, VT_SET_RENDER_STATE, s_setRenderState, reinterpret_cast<void*>(&SetRenderStateDetour));
        HookVtable(vtable, VT_SET_PIXEL_SHADER, s_setPixelShader, reinterpret_cast<void*>(&SetPixelShaderDetour));
        HookVtable(vtable, VT_SET_PS_CONSTANT_F, s_setPsConstant, reinterpret_cast<void*>(&SetPsConstantDetour));
        HookVtable(vtable, VT_SET_VERTEX_SHADER, s_setVertexShader, reinterpret_cast<void*>(&SetVertexShaderDetour));
        HookVtable(vtable, VT_DRAW_INDEXED, s_drawIndexed, reinterpret_cast<void*>(&DrawIndexedPrimitiveDetour));
        if (s_setRenderState && s_setPixelShader && s_setPsConstant && s_setVertexShader && s_drawIndexed)
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

    // once a frame, after the 3D scene
    void __cdecl OnWorldRender()
    {
        HookDevice();
        ++s_stats.WorldRenders;
        s_stats.TargetBatches = s_frameBatches;
        s_stats.Silhouettes = s_frameSilhouettes;
        s_stats.OnScreen = s_frameOnScreen;
        s_frameBatches = s_frameSilhouettes = s_frameOnScreen = 0;
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
// installed, world renders, batch draws, targets, target batches, silhouettes, gx api, error, mode
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
    FrameScript::PushNumber(L, s_stats.OnScreen);
    FrameScript::PushNumber(L, s_lastVsMajor);
    FrameScript::PushNumber(L, s_flatShader3 ? 1 : 0);
    return 12;
}

// /run OutlineMode(n): 1 - no extra draw, 2 - keep the depth test, 4 - write depth, over everything
int32_t Outline::OutlineMode(lua_State* L)
{
    s_mode = static_cast<uint32_t>(FrameScript::GetNumber(L, 1));
    return 0;
}
