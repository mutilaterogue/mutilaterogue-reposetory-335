#include <DrawDistance/DrawDistance.hpp>
#include <Misc/Util.hpp>

#include <Windows.h>
#include <cstdint>
#include <cstdlib>
#include <cstring>

namespace
{
    constexpr uint32_t ADDR_GROUND_EFFECT_DIST_MAX = 0x78DB2F;    // operand of fld [0x9E8CFC] (140.0)
    constexpr uint32_t ADDR_ENVIRONMENT_DETAIL_MAX = 0x78DC7F;    // operand of fld [0xA41B18] (1.5)

    // grass only grows on the loaded map chunks: far beyond ~500 yards there is nothing more to show
    float s_groundEffectDistMax = 500.0f;
    float s_environmentDetailMax = 5.0f;

    // ---------------------------------------------------------------- the fog
    constexpr uint32_t ADDR_WORLD_LIGHT_UPDATE = 0x7816F0;    // cdecl (int, void*), prologue 55 8B EC 83 EC 10
    constexpr uint32_t ADDR_M2_SET_FOG         = 0x834990;    // thiscall (color*, start, end, density), 55 8B EC D9 45 0C
    constexpr uint32_t PROLOGUE_SIZE           = 6;
    constexpr uint32_t ADDR_LIGHT_RESULT       = 0xD38B00;
    constexpr uint32_t LIGHT_FOG_START         = 0x90;
    constexpr uint32_t LIGHT_FOG_END           = 0x94;

    constexpr uint32_t ADDR_CVAR_REGISTER = 0x767FC0;
    constexpr uint32_t ADDR_CVAR_LOOKUP   = 0x767440;
    constexpr uint32_t CVAR_STRING_OFFSET = 0x28;

    enum FogMode { FOG_CLIENT, FOG_FAR, FOG_NONE };
    constexpr float FOG_FAR_SCALE = 3.0f;
    constexpr float FOG_NONE_START = 100000.0f;    // beyond anything drawn

    void* s_fogCVar = nullptr;

    // registered with the glue cvars (CVar::FillCustomGlueCVarVector) so Config.wtf keeps it; here otherwise
    int GetFogMode()
    {
        if (!s_fogCVar)
        {
            s_fogCVar = reinterpret_cast<void* (__cdecl*)(const char*)>(ADDR_CVAR_LOOKUP)("fogMode");
            if (!s_fogCVar)
            {
                reinterpret_cast<int32_t (__cdecl*)(const char*, const char*, uint32_t, const char*, void*, uint32_t, bool, int32_t, bool)>(
                    ADDR_CVAR_REGISTER)("fogMode", "Fog: 0 normal, 1 farther, 2 none", 1, "0", nullptr, 5, false, 0, false);
                s_fogCVar = reinterpret_cast<void* (__cdecl*)(const char*)>(ADDR_CVAR_LOOKUP)("fogMode");
                if (!s_fogCVar)
                    return FOG_CLIENT;
            }
        }
        const char* value = *reinterpret_cast<const char**>(static_cast<uint8_t*>(s_fogCVar) + CVAR_STRING_OFFSET);
        return value ? atoi(value) : FOG_CLIENT;
    }

    void ApplyFogMode(int mode, float& start, float& end)
    {
        if (mode == FOG_FAR)
        {
            start *= FOG_FAR_SCALE;
            end *= FOG_FAR_SCALE;
        }
        else if (mode == FOG_NONE)
        {
            start = FOG_NONE_START;
            end = FOG_NONE_START * 2.0f;
        }
    }

    // a jmp from the function's start to ours; the trampoline runs the moved prologue and jumps back
    void* MakeTrampoline(uint32_t address, void* detour)
    {
        uint8_t* trampoline = static_cast<uint8_t*>(VirtualAlloc(nullptr, 16, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
        memcpy(trampoline, reinterpret_cast<void*>(address), PROLOGUE_SIZE);
        trampoline[PROLOGUE_SIZE] = 0xE9;
        *reinterpret_cast<int32_t*>(trampoline + PROLOGUE_SIZE + 1) =
            static_cast<int32_t>(address + PROLOGUE_SIZE - reinterpret_cast<uint32_t>(trampoline + PROLOGUE_SIZE + 5));

        DWORD protection;
        VirtualProtect(reinterpret_cast<void*>(address), PROLOGUE_SIZE, PAGE_EXECUTE_READWRITE, &protection);
        uint8_t* site = reinterpret_cast<uint8_t*>(address);
        site[0] = 0xE9;
        *reinterpret_cast<int32_t*>(site + 1) = static_cast<int32_t>(reinterpret_cast<uint32_t>(detour) - (address + 5));
        site[5] = 0x90;
        VirtualProtect(reinterpret_cast<void*>(address), PROLOGUE_SIZE, protection, &protection);
        FlushInstructionCache(GetCurrentProcess(), reinterpret_cast<void*>(address), PROLOGUE_SIZE);
        return trampoline;
    }

    typedef int (__cdecl* WorldLightUpdateFn)(int, void*);
    typedef void (__thiscall* M2SetFogFn)(void*, void*, float, float, float);
    WorldLightUpdateFn s_worldLightUpdate = nullptr;
    M2SetFogFn s_m2SetFog = nullptr;

    bool s_lightOverridden = false;
    float s_clientFogStart = 0.0f;
    float s_clientFogEnd = 0.0f;

    float& LightField(uint32_t offset) { return *reinterpret_cast<float*>(ADDR_LIGHT_RESULT + offset); }

    int __cdecl WorldLightUpdateDetour(int a1, void* a2)
    {
        if (s_lightOverridden)
        {
            LightField(LIGHT_FOG_START) = s_clientFogStart;
            LightField(LIGHT_FOG_END) = s_clientFogEnd;
            s_lightOverridden = false;
        }
        int result = s_worldLightUpdate(a1, a2);
        int mode = GetFogMode();
        if (mode != FOG_CLIENT)
        {
            s_clientFogStart = LightField(LIGHT_FOG_START);
            s_clientFogEnd = LightField(LIGHT_FOG_END);
            ApplyFogMode(mode, LightField(LIGHT_FOG_START), LightField(LIGHT_FOG_END));
            s_lightOverridden = true;
        }
        return result;
    }

    // the light result already holds ours when it is the source; the map objects' own (interiors) not yet
    void __fastcall M2SetFogDetour(void* lighting, void* /*edx*/, void* color, float start, float end, float density)
    {
        bool fromLight = s_lightOverridden && start == LightField(LIGHT_FOG_START) && end == LightField(LIGHT_FOG_END);
        if (!fromLight)
            ApplyFogMode(GetFogMode(), start, end);
        s_m2SetFog(lighting, color, start, end, density);
    }
}

void DrawDistance::ApplyPatches()
{
    Util::OverwriteUInt32AtAddress(ADDR_GROUND_EFFECT_DIST_MAX, reinterpret_cast<uint32_t>(&s_groundEffectDistMax));
    Util::OverwriteUInt32AtAddress(ADDR_ENVIRONMENT_DETAIL_MAX, reinterpret_cast<uint32_t>(&s_environmentDetailMax));

    s_worldLightUpdate = reinterpret_cast<WorldLightUpdateFn>(MakeTrampoline(ADDR_WORLD_LIGHT_UPDATE, reinterpret_cast<void*>(&WorldLightUpdateDetour)));
    s_m2SetFog = reinterpret_cast<M2SetFogFn>(MakeTrampoline(ADDR_M2_SET_FOG, reinterpret_cast<void*>(&M2SetFogDetour)));
}
