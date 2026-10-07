#include <Outline/Outline.hpp>

#include <Client/ClientServices.hpp>
#include <Client/FrameScript.hpp>
#include <Data/Enums.hpp>
#include <GameObjects/CGObject.hpp>
#include <Misc/InlineHook.hpp>

#include <Windows.h>
#include <d3d9.h>

#include <array>
#include <cstring>
#include <vector>

namespace
{
    // ---------------------------------------------------------------- client addresses (12340)
    constexpr uintptr_t ADDR_M2_DRAW_BATCH  = 0x8203B0;    // void __thiscall (batch*)
    constexpr uintptr_t ADDR_WORLD_RENDER   = 0x4F9240;    // near the end of the world frame
    constexpr uintptr_t ADDR_GX_MUTE_A      = 0x6A3620;    // CGxDeviceD3d, 2 stack args (ret 8)
    constexpr uintptr_t ADDR_GX_MUTE_B      = 0x6A77C0;    // CGxDeviceD3d, 2 stack args (ret 8)

    // the same addresses as variables for the inline asm (it can't call a constant)
    uintptr_t ADDR_WORLD_RENDER_PTR = ADDR_WORLD_RENDER;
    uintptr_t ADDR_GX_MUTE_A_PTR    = ADDR_GX_MUTE_A;
    uintptr_t ADDR_GX_MUTE_B_PTR    = ADDR_GX_MUTE_B;

    constexpr uintptr_t ADDR_GX_DEVICE      = 0xC5DF88;    // CGxDevice*
    constexpr uint32_t  GX_API_OFFSET       = 0x1B4;       // 1, 2 - Direct3D
    constexpr uint32_t  GX_D3DDEVICE_OFFSET = 0x397C;      // IDirect3DDevice9*

    constexpr uintptr_t ADDR_TARGET_GUID    = 0xBD07B0;
    constexpr uintptr_t ADDR_MOUSEOVER_GUID = 0xBD07A0;
    constexpr uintptr_t ADDR_OBJECT_PTR     = 0x4D4DB0;    // ClntObjMgrObjectPtr(guid, typeMask, file, line)

    // the batch record
    constexpr size_t   BATCH_SIZE          = 0xBC;
    constexpr uint32_t BATCH_MATERIAL      = 0x50;         // -> [0] blend mode, [8] flags
    constexpr uint32_t BATCH_MODEL         = 0x60;         // CM2Model*
    constexpr uint32_t MODEL_PARENT        = 0x48;         // CM2Model* the model is attached to
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
    };

    // OutlineDebug(): where the chain breaks
    struct Stats
    {
        uint32_t Installed = 0;             // bit mask: 1 batch, 2 world render, 4 mute A, 8 mute B
        uint32_t WorldRenders = 0;          // the world render hook ran
        uint32_t BatchDraws = 0;            // the batch hook ran (all models)
        uint32_t Targets = 0;               // models picked for the last frame
        uint32_t TargetMatches = 0;         // batches of those models (before the material filter)
        uint32_t Recorded = 0;              // batches kept in the last frame
        uint32_t Replayed = 0;              // batches drawn again in the last frame
        uint32_t GxApi = 0;
        uint32_t Error = 0;                 // 1 no device, 2 shader, 3 state block
    } s_stats;

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
    RawHook s_hookWorldRender;
    RawHook s_hookMuteA;
    RawHook s_hookMuteB;

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
        if (s_targets.empty() || s_batches.size() >= MAX_BATCHES)
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
        s_batches.push_back(copy);
    }

    void CallDrawBatch(void* batch)
    {
        s_hookDrawBatch.Unpatch();
        reinterpret_cast<void (__thiscall*)(void*)>(ADDR_M2_DRAW_BATCH)(batch);
        s_hookDrawBatch.Repatch();
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

        IDirect3DStateBlock9* state = nullptr;
        if (FAILED(device->CreateStateBlock(D3DSBT_ALL, &state)))
        {
            s_stats.Error = 3;
            return;
        }

        s_replaying = true;
        for (Batch& batch : s_batches)
        {
            device->SetPixelShader(s_flatShader);
            device->SetPixelShaderConstantF(0, batch.Color, 1);
            device->SetRenderState(D3DRS_ZENABLE, FALSE);
            device->SetRenderState(D3DRS_ZWRITEENABLE, FALSE);
            device->SetRenderState(D3DRS_ALPHABLENDENABLE, FALSE);
            device->SetRenderState(D3DRS_ALPHATESTENABLE, FALSE);
            device->SetRenderState(D3DRS_CULLMODE, D3DCULL_NONE);
            device->SetRenderState(D3DRS_FOGENABLE, FALSE);

            // the draw may write into its record: a copy
            alignas(16) uint8_t copy[BATCH_SIZE];
            memcpy(copy, batch.Data.data(), BATCH_SIZE);
            CallDrawBatch(copy);
            ++s_stats.Replayed;
        }
        s_replaying = false;

        state->Apply();
        state->Release();
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
        ++s_stats.WorldRenders;
        s_stats.Recorded = static_cast<uint32_t>(s_batches.size());
        ReplayBatches();
        s_batches.clear();
        CollectTargets();
        s_stats.Targets = static_cast<uint32_t>(s_targets.size());
    }

    // the world render hook: everything (registers, FPU/SSE) kept for the original
    uint32_t s_worldRenderReturn = 0;
    void __cdecl UnpatchWorldRender() { s_hookWorldRender.Unpatch(); }
    void __cdecl RepatchWorldRender() { s_hookWorldRender.Repatch(); }

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
            call UnpatchWorldRender
            fxrstor [esp]
            mov esp, ebp
            popfd
            popad
            // the original with the caller's arguments; back here, then to the caller
            pop dword ptr [s_worldRenderReturn]
            call dword ptr [ADDR_WORLD_RENDER_PTR]
            pushad
            pushfd
            call RepatchWorldRender
            popfd
            popad
            jmp dword ptr [s_worldRenderReturn]
        }
    }

    // muted while replaying: returns at once (ret 8), else the original with every register intact
    uint32_t s_muteAReturn = 0;
    uint32_t s_muteBReturn = 0;
    void __cdecl UnpatchMuteA() { s_hookMuteA.Unpatch(); }
    void __cdecl RepatchMuteA() { s_hookMuteA.Repatch(); }
    void __cdecl UnpatchMuteB() { s_hookMuteB.Unpatch(); }
    void __cdecl RepatchMuteB() { s_hookMuteB.Repatch(); }

    __declspec(naked) void MuteADetour()
    {
        __asm
        {
            cmp byte ptr [s_replaying], 0
            je call_original
            ret 8
        call_original:
            pushad
            pushfd
            call UnpatchMuteA
            popfd
            popad
            pop dword ptr [s_muteAReturn]
            call dword ptr [ADDR_GX_MUTE_A_PTR]
            pushad
            pushfd
            call RepatchMuteA
            popfd
            popad
            jmp dword ptr [s_muteAReturn]
        }
    }

    __declspec(naked) void MuteBDetour()
    {
        __asm
        {
            cmp byte ptr [s_replaying], 0
            je call_original
            ret 8
        call_original:
            pushad
            pushfd
            call UnpatchMuteB
            popfd
            popad
            pop dword ptr [s_muteBReturn]
            call dword ptr [ADDR_GX_MUTE_B_PTR]
            pushad
            pushfd
            call RepatchMuteB
            popfd
            popad
            jmp dword ptr [s_muteBReturn]
        }
    }
}

void Outline::ApplyPatches()
{
    s_batches.reserve(256);
    if (s_hookDrawBatch.Install(ADDR_M2_DRAW_BATCH, reinterpret_cast<void*>(&DrawBatchDetour)))
        s_stats.Installed |= 1;
    if (s_hookWorldRender.Install(ADDR_WORLD_RENDER, reinterpret_cast<void*>(&WorldRenderDetour)))
        s_stats.Installed |= 2;
    if (s_hookMuteA.Install(ADDR_GX_MUTE_A, reinterpret_cast<void*>(&MuteADetour)))
        s_stats.Installed |= 4;
    if (s_hookMuteB.Install(ADDR_GX_MUTE_B, reinterpret_cast<void*>(&MuteBDetour)))
        s_stats.Installed |= 8;
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
    return 9;
}
