#include <Outline/Outline.hpp>

#include <Client/ClientServices.hpp>
#include <Client/FrameScript.hpp>
#include <Data/Enums.hpp>
#include <GameObjects/CGObject.hpp>
#include <Misc/InlineHook.hpp>

#include <Windows.h>
#include <d3d9.h>

#include <array>
#include <cstdio>
#include <cstring>
#include <vector>

namespace
{
    // ---------------------------------------------------------------- client addresses (12340)
    constexpr uintptr_t ADDR_M2_DRAW_BATCH  = 0x8203B0;    // void __thiscall (batch*)
    constexpr uintptr_t ADDR_WORLD_RENDER   = 0x4F9240;    // near the end of the world frame


    constexpr uintptr_t ADDR_GX_DEVICE      = 0xC5DF88;    // CGxDevice*
    constexpr uint32_t  GX_API_OFFSET       = 0x1B4;       // 1, 2 - Direct3D
    constexpr uint32_t  GX_D3DDEVICE_OFFSET = 0x397C;      // IDirect3DDevice9*

    constexpr uintptr_t ADDR_TARGET_GUID    = 0xBD07B0;
    constexpr uintptr_t ADDR_MOUSEOVER_GUID = 0xBD07A0;
    constexpr uintptr_t ADDR_OBJECT_PTR     = 0x4D4DB0;    // ClntObjMgrObjectPtr(guid, typeMask, file, line)
    // the M2 vertex shaders' view * projection: c2..c5; at 0x4F9240 the 3D scene is over and another
    // matrix is there - the one the batch was drawn with is put back for the replay's draw call
    constexpr uint32_t VIEWPROJ_REGISTER   = 2;
    constexpr uint32_t VIEWPROJ_COUNT      = 4;

    // the batch record
    constexpr size_t   BATCH_SIZE          = 0xBC;
    constexpr uint32_t BATCH_MATERIAL      = 0x50;         // -> [0] blend mode, [8] flags
    constexpr uint32_t BATCH_MODEL         = 0x60;         // CM2Model*
    constexpr uint32_t MODEL_PARENT        = 0x48;         // CM2Model* the model is attached to
    // the "previous batch" fields the draw compares with the current ones (0x58, 0x60, 0x68)
    constexpr uint32_t BATCH_PREVIOUS[]    = { 0x5C, 0x64, 0x6C };
    constexpr uint32_t MAX_BLEND_MODE      = 2;            // opaque / alpha key (no blended, additive...)

    constexpr size_t MAX_BATCHES = 4096;

    struct Target
    {
        void* Model = nullptr;
        float Color[4] = {};
    };

    struct Batch
    {
        std::array<uint8_t, BATCH_SIZE> Data;
        float Color[4];
        float ViewProj[VIEWPROJ_COUNT * 4];     // c2..c5 when it was drawn
    };

    // OutlineDebug(): where the chain breaks
    struct Stats
    {
        uint32_t Installed = 0;             // bit mask: 1 batch, 2 world render, 4 draw call (on the first replay)
        uint32_t WorldRenders = 0;          // the world render hook ran
        uint32_t BatchDraws = 0;            // the batch hook ran (all models)
        uint32_t Targets = 0;               // models picked for the last frame
        uint32_t TargetMatches = 0;         // batches of those models (before the material filter)
        uint32_t Recorded = 0;              // batches kept in the last frame
        uint32_t Replayed = 0;              // batches drawn again in the last frame
        uint32_t GxApi = 0;
        uint32_t Error = 0;                 // 1 no device, 2 shader, 3 draw call hook
        uint32_t DrawCalls = 0;             // draw calls inside the last replay (our shader went in)
        uint32_t OnBackBuffer = 0;          // 1: the render target at the replay was the back buffer
    } s_stats;

    // OutlineMode(bits), for finding the fault:
    //  1 - keep the batch's "previous" fields (no forced bones / material upload)
    //  2 - no replay at all (record only)
    //  4 - replay into the back buffer (whatever render target is set at that point)
    //  8 - leave c2..c5 as they are at the replay (no view-projection of the record)
    uint32_t s_mode = 0;

    // what Gx sent to the device (the device hooks below; the device can't be read back)
    constexpr uint32_t SHADOW_VS_REGISTERS = 32;
    struct Shadow
    {
        DWORD RenderStates[256] = {};
        bool Known[256] = {};
        IDirect3DPixelShader9* PixelShader = nullptr;
        float PsConstant0[4] = {};
        float VsConstants[SHADOW_VS_REGISTERS * 4] = {};
    } s_shadow;

    std::vector<Target> s_targets;          // the models outlined in this frame
    std::vector<Batch> s_batches;           // their batches drawn in this frame
    bool s_replaying = false;
    IDirect3DPixelShader9* s_flatShader = nullptr;

    // ps_2_0: mov oC0, c0 - the color in c0
    const DWORD FLAT_SHADER[] = { 0xFFFF0200, 0x02000001, 0x800F0800, 0xA0E40000, 0x0000FFFF };

    // ---------------------------------------------------------------- hooks
    // jmp over the first 5 bytes; the original is called with them put back (as FunctionHook)
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
        uint32_t api = *reinterpret_cast<uint32_t*>(gx + GX_API_OFFSET);
        if (api != 1 && api != 2)
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
    }

    // the outlined model the batch belongs to (itself or an attachment of it)
    Target const* FindTarget(void* model)
    {
        for (int depth = 0; model && depth < 8; ++depth)
        {
            for (Target const& target : s_targets)
                if (target.Model == model)
                    return &target;
            model = *reinterpret_cast<void**>(static_cast<uint8_t*>(model) + MODEL_PARENT);
        }
        return nullptr;
    }

    void RecordBatch(uint8_t* batch)
    {
        if (s_targets.empty() || s_batches.size() >= MAX_BATCHES || !(s_stats.Installed & 4))
            return;
        Target const* target = FindTarget(*reinterpret_cast<void**>(batch + BATCH_MODEL));
        if (!target)
            return;
        ++s_stats.TargetMatches;
        uint8_t* material = *reinterpret_cast<uint8_t**>(batch + BATCH_MATERIAL);
        if (!material || *reinterpret_cast<uint32_t*>(material) > MAX_BLEND_MODE || (material[8] & 1))
            return;
        Batch copy;
        memcpy(copy.Data.data(), batch, BATCH_SIZE);
        memcpy(copy.Color, target->Color, sizeof(copy.Color));
        memcpy(copy.ViewProj, &s_shadow.VsConstants[VIEWPROJ_REGISTER * 4], sizeof(copy.ViewProj));
        s_batches.push_back(copy);
    }

    void CallDrawBatch(void* batch)
    {
        s_hookDrawBatch.Unpatch();
        reinterpret_cast<void (__thiscall*)(void*)>(ADDR_M2_DRAW_BATCH)(batch);
        s_hookDrawBatch.Repatch();
    }

    // ---------------------------------------------------------------- the device
    // The client's device can't be read back (Get* gives nothing on it), so the states Gx sends are copied
    // here as they go (SetRenderState, SetPixelShader, Set*ShaderConstantF hooked in the device's vtable).
    // The replay's draw call sets ours and then puts exactly Gx's back from that copy: Gx's cache and the
    // device never disagree.
    enum VtableIndex : uint32_t
    {
        VT_SET_RENDER_STATE      = 57,
        VT_DRAW_INDEXED          = 82,
        VT_SET_VS_CONSTANT_F     = 94,
        VT_SET_PIXEL_SHADER      = 107,
        VT_SET_PS_CONSTANT_F     = 109,
    };

    typedef HRESULT (__stdcall* SetRenderStateFn)(IDirect3DDevice9*, D3DRENDERSTATETYPE, DWORD);
    typedef HRESULT (__stdcall* DrawIndexedPrimitiveFn)(IDirect3DDevice9*, D3DPRIMITIVETYPE, INT, UINT, UINT, UINT, UINT);
    typedef HRESULT (__stdcall* SetShaderConstantFFn)(IDirect3DDevice9*, UINT, const float*, UINT);
    typedef HRESULT (__stdcall* SetPixelShaderFn)(IDirect3DDevice9*, IDirect3DPixelShader9*);

    SetRenderStateFn s_setRenderState = nullptr;
    DrawIndexedPrimitiveFn s_dipOriginal = nullptr;
    SetShaderConstantFFn s_setVsConstant = nullptr;
    SetPixelShaderFn s_setPixelShader = nullptr;
    SetShaderConstantFFn s_setPsConstant = nullptr;


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

    HRESULT __stdcall SetVsConstantDetour(IDirect3DDevice9* device, UINT start, const float* data, UINT count)
    {
        if (data && start < SHADOW_VS_REGISTERS)
        {
            UINT copy = (start + count > SHADOW_VS_REGISTERS) ? SHADOW_VS_REGISTERS - start : count;
            memcpy(&s_shadow.VsConstants[start * 4], data, copy * 4 * sizeof(float));
        }
        return s_setVsConstant(device, start, data, count);
    }

    // the replay's draw call
    float s_replayColor[4] = {};
    const float* s_replayViewProj = nullptr;

    const D3DRENDERSTATETYPE REPLAY_STATES[] = {
        D3DRS_ZENABLE, D3DRS_ZWRITEENABLE, D3DRS_ALPHABLENDENABLE, D3DRS_ALPHATESTENABLE, D3DRS_CULLMODE, D3DRS_FOGENABLE,
    };
    const DWORD REPLAY_VALUES[] = { FALSE, FALSE, FALSE, FALSE, D3DCULL_NONE, FALSE };
    // the device defaults for states Gx never set since the hooks went in
    const DWORD STATE_DEFAULTS[] = { D3DZB_TRUE, TRUE, FALSE, FALSE, D3DCULL_CCW, FALSE };
    constexpr size_t REPLAY_STATE_COUNT = sizeof(REPLAY_STATES) / sizeof(REPLAY_STATES[0]);

    HRESULT __stdcall DrawIndexedPrimitiveDetour(IDirect3DDevice9* device, D3DPRIMITIVETYPE type, INT baseVertex,
        UINT minIndex, UINT numVertices, UINT startIndex, UINT primitiveCount)
    {
        if (!s_replaying || !s_flatShader)
            return s_dipOriginal(device, type, baseVertex, minIndex, numVertices, startIndex, primitiveCount);

        // ours, around Gx's copy (the original setters: the copy keeps Gx's values)
        s_setPixelShader(device, s_flatShader);
        s_setPsConstant(device, 0, s_replayColor, 1);
        if (s_replayViewProj)
            s_setVsConstant(device, VIEWPROJ_REGISTER, s_replayViewProj, VIEWPROJ_COUNT);
        for (size_t i = 0; i < REPLAY_STATE_COUNT; ++i)
            s_setRenderState(device, REPLAY_STATES[i], REPLAY_VALUES[i]);

        ++s_stats.DrawCalls;
        HRESULT result = s_dipOriginal(device, type, baseVertex, minIndex, numVertices, startIndex, primitiveCount);

        s_setPixelShader(device, s_shadow.PixelShader);
        s_setPsConstant(device, 0, s_shadow.PsConstant0, 1);
        if (s_replayViewProj)
            s_setVsConstant(device, VIEWPROJ_REGISTER, &s_shadow.VsConstants[VIEWPROJ_REGISTER * 4], VIEWPROJ_COUNT);
        for (size_t i = 0; i < REPLAY_STATE_COUNT; ++i)
        {
            D3DRENDERSTATETYPE state = REPLAY_STATES[i];
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
        if (s_dipOriginal)
            return;
        IDirect3DDevice9* device = GetD3DDevice();
        if (!device)
            return;
        void** vtable = *reinterpret_cast<void***>(device);
        HookVtable(vtable, VT_SET_RENDER_STATE, s_setRenderState, reinterpret_cast<void*>(&SetRenderStateDetour));
        HookVtable(vtable, VT_SET_VS_CONSTANT_F, s_setVsConstant, reinterpret_cast<void*>(&SetVsConstantDetour));
        HookVtable(vtable, VT_SET_PIXEL_SHADER, s_setPixelShader, reinterpret_cast<void*>(&SetPixelShaderDetour));
        HookVtable(vtable, VT_SET_PS_CONSTANT_F, s_setPsConstant, reinterpret_cast<void*>(&SetPsConstantDetour));
        HookVtable(vtable, VT_DRAW_INDEXED, s_dipOriginal, reinterpret_cast<void*>(&DrawIndexedPrimitiveDetour));
        if (s_setRenderState && s_setVsConstant && s_setPixelShader && s_setPsConstant && s_dipOriginal)
            s_stats.Installed |= 4;
    }

    // the recorded batches again, one color, over everything (stage 1)
    void ReplayBatches()
    {
        s_stats.Replayed = 0;
        if (uint8_t* gx = *reinterpret_cast<uint8_t**>(ADDR_GX_DEVICE))
            s_stats.GxApi = *reinterpret_cast<uint32_t*>(gx + GX_API_OFFSET);
        IDirect3DDevice9* device = GetD3DDevice();
        if (!device)
        {
            s_stats.Error = 1;
            return;
        }
        if (s_batches.empty())
            return;
        if (!s_flatShader && FAILED(device->CreatePixelShader(FLAT_SHADER, &s_flatShader)))
        {
            s_flatShader = nullptr;
            s_stats.Error = 2;
            return;
        }

        if (!(s_stats.Installed & 4))
        {
            s_stats.Error = 3;
            return;
        }

        s_stats.DrawCalls = 0;
        if (s_mode & 2)
            return;

        // where the replay draws: the back buffer, or some other render target at this point of the frame
        IDirect3DSurface9* renderTarget = nullptr;
        IDirect3DSurface9* backBuffer = nullptr;
        device->GetRenderTarget(0, &renderTarget);
        device->GetBackBuffer(0, 0, D3DBACKBUFFER_TYPE_MONO, &backBuffer);
        s_stats.OnBackBuffer = renderTarget && renderTarget == backBuffer ? 1 : 0;
        bool switched = (s_mode & 4) && backBuffer && renderTarget != backBuffer;
        if (switched)
            device->SetRenderTarget(0, backBuffer);

        // the batch draws itself through Gx as usual; our pixel shader goes in at the draw call
        // (DrawIndexedPrimitiveDetour), Gx's own states are put back right after it
        s_replaying = true;
        for (Batch& batch : s_batches)
        {
            memcpy(s_replayColor, batch.Color, sizeof(s_replayColor));
            s_replayViewProj = (s_mode & 8) ? nullptr : batch.ViewProj;
            alignas(16) uint8_t copy[BATCH_SIZE];        // the draw writes into its record: a copy
            memcpy(copy, batch.Data.data(), BATCH_SIZE);
            // "the same as the previous batch" -> the draw would skip the bones / material upload: never
            if (!(s_mode & 1))
                for (uint32_t offset : BATCH_PREVIOUS)
                    *reinterpret_cast<uint32_t*>(copy + offset) = 0;
            CallDrawBatch(copy);
            ++s_stats.Replayed;
        }
        s_replaying = false;

        if (switched)
            device->SetRenderTarget(0, renderTarget);
        if (renderTarget)
            renderTarget->Release();
        if (backBuffer)
            backBuffer->Release();
    }

    // ---------------------------------------------------------------- detours
    void __fastcall DrawBatchDetour(void* batch, void* /*edx*/)
    {
        ++s_stats.BatchDraws;
        CallDrawBatch(batch);
        if (!s_replaying)
            RecordBatch(static_cast<uint8_t*>(batch));
    }

    void __cdecl OnWorldRender()
    {
        HookDevice();
        ++s_stats.WorldRenders;
        s_stats.Recorded = static_cast<uint32_t>(s_batches.size());
        ReplayBatches();
        s_batches.clear();
        CollectTargets();
        s_stats.Targets = static_cast<uint32_t>(s_targets.size());
    }

    // ---------------------------------------------------------------- the mid-function hook at 0x4F9240
    // 0x4F9240 is a place inside the world render function, not a function: our code runs there, then the
    // instructions we overwrote (copied to a trampoline) and a jmp back right after them.

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
    s_batches.reserve(256);
    if (s_hookDrawBatch.Install(ADDR_M2_DRAW_BATCH, reinterpret_cast<void*>(&DrawBatchDetour)))
        s_stats.Installed |= 1;
    if (s_hookWorldRender.Install(ADDR_WORLD_RENDER, reinterpret_cast<void*>(&WorldRenderDetour)))
    {
        s_worldRenderTrampoline = s_hookWorldRender.Trampoline;
        s_stats.Installed |= 2;
    }
}

// /run print(OutlineDebug())
// installed, world renders, batch draws, targets, target batches, recorded, replayed, gx api, error
int32_t Outline::OutlineDebug(lua_State* L)
{
    FrameScript::PushNumber(L, s_stats.Installed);
    FrameScript::PushNumber(L, s_stats.WorldRenders);
    FrameScript::PushNumber(L, s_stats.BatchDraws);
    FrameScript::PushNumber(L, s_stats.Targets);
    FrameScript::PushNumber(L, s_stats.TargetMatches);
    FrameScript::PushNumber(L, s_stats.Recorded);
    FrameScript::PushNumber(L, s_stats.Replayed);
    FrameScript::PushNumber(L, s_stats.GxApi);
    FrameScript::PushNumber(L, s_stats.Error);
    // the bytes at 0x4F9240 and how many were moved to the trampoline
    char bytes[64] = {};
    for (int i = 0; i < 12; ++i)
        sprintf_s(bytes + i * 3, sizeof(bytes) - i * 3, "%02X ", s_hookWorldRender.Bytes[i]);
    FrameScript::PushString(L, bytes);
    FrameScript::PushNumber(L, static_cast<double>(s_hookWorldRender.Length));
    FrameScript::PushNumber(L, s_stats.DrawCalls);
    FrameScript::PushNumber(L, s_stats.OnBackBuffer);
    FrameScript::PushNumber(L, s_mode);
    return 14;
}

// /run OutlineMode(n) - see s_mode
int32_t Outline::OutlineMode(lua_State* L)
{
    s_mode = static_cast<uint32_t>(FrameScript::GetNumber(L, 1));
    return 0;
}
