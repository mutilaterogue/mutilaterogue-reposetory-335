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
    constexpr uintptr_t ADDR_GX_MUTE_A      = 0x6A3620;    // CGxDeviceD3d, 2 stack args (ret 8)
    constexpr uintptr_t ADDR_GX_MUTE_B      = 0x6A77C0;    // CGxDeviceD3d, 2 stack args (ret 8)

    // the same addresses as variables for the inline asm (it can't call a constant)
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
    {
        s_worldRenderTrampoline = s_hookWorldRender.Trampoline;
        s_stats.Installed |= 2;
    }
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
    // the bytes at 0x4F9240 and how many were moved to the trampoline
    char bytes[64] = {};
    for (int i = 0; i < 12; ++i)
        sprintf_s(bytes + i * 3, sizeof(bytes) - i * 3, "%02X ", s_hookWorldRender.Bytes[i]);
    FrameScript::PushString(L, bytes);
    FrameScript::PushNumber(L, static_cast<double>(s_hookWorldRender.Length));
    return 11;
}
