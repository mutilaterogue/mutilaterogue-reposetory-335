#include <Outline/Outline.hpp>
#include <Outline/OutlineShaders.hpp>

#include <Client/ClientServices.hpp>
#include <Client/FrameScript.hpp>
#include <Data/Enums.hpp>
#include <GameObjects/CGObject.hpp>
#include <Misc/InlineHook.hpp>

#include <Windows.h>
#include <d3d9.h>
#include <d3dcommon.h>

#include <cstdio>
#include <cmath>
#include <cstdlib>
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
    constexpr uintptr_t ADDR_ACTIVE_PLAYER  = 0x4D3790;    // ClntObjMgrGetActivePlayer()
    constexpr uintptr_t ADDR_ENUM_VISIBLE   = 0x4D4B30;    // ClntObjMgrEnumVisibleObjects(int (*)(guid, param), param)
    constexpr uintptr_t ADDR_UNIT_REACTION  = 0x7251C0;    // CGUnit_C::UnitReaction(this, other): 0 hated .. 7 exalted
    constexpr uintptr_t ADDR_CAN_ATTACK     = 0x729A70;    // CGUnit_C::CanAttack(this, other)
    constexpr uintptr_t ADDR_CREATURE_RANK  = 0x718A00;    // CGUnit_C::GetCreatureRank(this): 3 world boss
    constexpr uintptr_t ADDR_GUID_BY_TOKEN  = 0x60C1C0;    // GetGuidByUnitID("target")
    constexpr uintptr_t ADDR_CVAR_REGISTER  = 0x767FC0;    // CVar::Register
    constexpr uintptr_t ADDR_CVAR_LOOKUP    = 0x767440;    // CVar::Lookup(name)
    constexpr uint32_t  CVAR_STRING_OFFSET  = 0x28;        // CVar: the value as a string
    constexpr uint32_t  CVAR_FLAGS_OFFSET   = 0x1C;        // CVar: uint16 flags, 1 - saved to Config.wtf
    constexpr uint32_t  RANK_WORLD_BOSS     = 3;
    constexpr size_t    MAX_BOSSES          = 8;
    constexpr size_t    MAX_OUTLINED        = 64;      // models in a frame (OutlineAll)
    constexpr uintptr_t ADDR_NAMEPLATE_DIST_SQ = 0xADAA7C; // the nameplate distance, squared (NamePlates.cpp sets it)
    constexpr uint32_t  VT_OBJECT_GET_POSITION = 11;    // CGObject_C::GetPosition(C3Vector&)

    // the batch record (this of 0x8203B0)
    constexpr uint32_t BATCH_MATERIAL      = 0x50;         // -> [0] blend mode, [8] flags
    constexpr uint32_t BATCH_MODEL         = 0x60;         // CM2Model*
    constexpr uint32_t MODEL_PARENT        = 0x48;         // CM2Model* the model is attached to
    constexpr uint32_t MAX_BLEND_MODE      = 2;            // opaque / alpha key (no blended, additive...)
    constexpr uint32_t MIN_ATTACHMENT_TRIANGLES = 24;      // fewer on an attachment: a spell effect's billboard

    // the look
    constexpr float ALPHA_GAIN_HIGH = 1.0f / 3.0f;         // 16 samples
    constexpr float ALPHA_GAIN_LOW  = 1.0f / 2.0f;         // 8 samples

    // the colors by reaction (retail: the same for the target, the mouseover, ...)
    const float COLOR_HOSTILE[3]         = { 1.00f, 0.15f, 0.10f };
    const float COLOR_NEUTRAL[3]         = { 1.00f, 0.85f, 0.10f };
    const float COLOR_FRIENDLY[3]        = { 0.20f, 1.00f, 0.20f };
    const float COLOR_FRIENDLY_PLAYER[3] = { 0.25f, 0.55f, 1.00f };

    // ---------------------------------------------------------------- CVars
    // Registered in the world (the first frame), not at the login screen: more custom glue cvars crash
    // the client. A value saved in Config.wtf is kept (the client holds unknown cvars until registered).
    struct CVarDefinition
    {
        const char* Name;
        const char* Description;
        const char* Default;
        void* Handle;
    };
    CVarDefinition s_cvars[] = {
        { "OutlineQuality",   "Unit outline: 0 off, 1 on, 2 on (low quality)", "1", nullptr },
        { "OutlinePlayer",    "Outline your own character", "0", nullptr },
        { "OutlineTarget",    "Outline your target", "1", nullptr },
        { "OutlineMouseover", "Outline the unit under the mouse", "1", nullptr },
        { "OutlineQuestBoss", "Outline bosses around you", "1", nullptr },
        { "OutlineThickness", "Outline thickness (0.5 .. 3)", "1", nullptr },
        { "OutlineStrength",  "Outline opacity (0 .. 1)", "1", nullptr },
        { "OutlineAll",       "Outline every unit around: 0 off, 1 all, 2 hostile, 3 friendly, 4 players, 5 creatures", "0", nullptr },
        { "ssao",             "Ambient occlusion (SSAO): 0 off, 1 on", "0", nullptr },
        { "ssaoStrength",     "SSAO darkness (0 .. 2)", "1", nullptr },
        { "ssaoRadius",       "SSAO radius in yards (0.3 .. 5)", "1.5", nullptr },
        { "colorContrast",    "Color grading: contrast (0.5 .. 1.5)", "1", nullptr },
        { "colorSaturation",  "Color grading: saturation (0 .. 2)", "1", nullptr },
        { "colorBrightness",  "Color grading: brightness (0.5 .. 1.5)", "1", nullptr },
        { "colorSharpen",     "Color grading: sharpening (0 .. 1)", "0", nullptr },
        { "bloom",            "Bloom: 0 off, 1 on", "0", nullptr },
        { "bloomStrength",    "Bloom strength (0 .. 2)", "0.6", nullptr },
        { "bloomThreshold",   "Bloom: brightness it starts at (0.3 .. 1)", "0.7", nullptr },
        { "godRays",          "Sun rays: 0 off, 1 on", "0", nullptr },
        { "godRaysStrength",  "Sun rays strength (0 .. 2)", "1", nullptr },
        { "godRaysFlip",      "Sun rays: 1 if they come from the wrong side", "0", nullptr },
        { "dof",              "Depth of field (far blur): 0 off, 1 on", "0", nullptr },
        { "dofStrength",      "Depth of field strength (0 .. 1)", "1", nullptr },
        { "dofDistance",      "Depth of field: yards beyond the focus where the blur is full (5 .. 300)", "60", nullptr },
        { "ssr",              "Water reflections: 0 off, 1 on", "0", nullptr },
        { "ssrStrength",      "Water reflections strength (0 .. 1)", "1", nullptr },
        { "ssrRipple",        "Water reflections: ripples (0 .. 1)", "0.5", nullptr },
        { "ssrSun",           "Water reflections: the sun's glint (0 .. 2)", "1", nullptr },
        { "vignette",         "Vignette: darker corners (0 .. 1)", "0", nullptr },
        { "filmGrain",        "Film grain (0 .. 1)", "0", nullptr },
        { "fxaa",             "FXAA (edges smoothed after the scene): 0 off, 1 on", "0", nullptr },
        { "tonemap",          "Filmic tone mapping (soft highlights): 0 off, 1 on", "0", nullptr },
        { "tonemapExposure",  "Tone mapping exposure (0.5 .. 3)", "1.4", nullptr },
        { "groundFog",        "Fog low on the ground (valleys, water): 0 off, 1 on", "0", nullptr },
        { "groundFogDensity", "Ground fog density (0 .. 1)", "0.5", nullptr },
        { "groundFogHeight",  "Ground fog: yards above your feet it reaches (0 .. 30)", "4", nullptr },
        { "depthNoMsaa",      "Depth effects without antialiasing (our depth buffer in place of the client's; experimental): 0 off, 1 on", "0", nullptr },
    };
    enum CVarIndex { CV_QUALITY, CV_PLAYER, CV_TARGET, CV_MOUSEOVER, CV_QUESTBOSS, CV_THICKNESS, CV_STRENGTH, CV_ALL,
        CV_SSAO, CV_SSAO_STRENGTH, CV_SSAO_RADIUS, CV_CONTRAST, CV_SATURATION, CV_BRIGHTNESS, CV_SHARPEN,
        CV_BLOOM, CV_BLOOM_STRENGTH, CV_BLOOM_THRESHOLD, CV_GODRAYS, CV_GODRAYS_STRENGTH, CV_GODRAYS_FLIP,
        CV_DOF, CV_DOF_STRENGTH, CV_DOF_DISTANCE, CV_SSR, CV_SSR_STRENGTH, CV_SSR_RIPPLE, CV_SSR_SUN, CV_VIGNETTE, CV_GRAIN,
        CV_FXAA, CV_TONEMAP, CV_TONEMAP_EXPOSURE, CV_GROUND_FOG, CV_GROUND_FOG_DENSITY, CV_GROUND_FOG_HEIGHT, CV_DEPTH_NO_MSAA, CV_COUNT };
    enum OutlineAllMode { ALL_OFF, ALL_EVERY, ALL_HOSTILE, ALL_FRIENDLY, ALL_PLAYERS, ALL_CREATURES };
    bool s_cvarsRegistered = false;

    void RegisterCVars()
    {
        if (s_cvarsRegistered)
            return;
        s_cvarsRegistered = true;
        for (CVarDefinition& cvar : s_cvars)
        {
            // registered with the glue cvars (CVar::FillCustomGlueCVarVector), before Config.wtf is read: saved
            // values are kept. Registered here only when that list lacks them (then not kept across restarts)
            cvar.Handle = reinterpret_cast<void* (__cdecl*)(const char*)>(ADDR_CVAR_LOOKUP)(cvar.Name);
            if (!cvar.Handle)
            {
                reinterpret_cast<int32_t (__cdecl*)(const char*, const char*, uint32_t, const char*, void*, uint32_t, bool, int32_t, bool)>(
                    ADDR_CVAR_REGISTER)(cvar.Name, cvar.Description, 1, cvar.Default, nullptr, 5, false, 0, false);
                cvar.Handle = reinterpret_cast<void* (__cdecl*)(const char*)>(ADDR_CVAR_LOOKUP)(cvar.Name);
            }
            if (cvar.Handle)
                *reinterpret_cast<uint16_t*>(static_cast<uint8_t*>(cvar.Handle) + CVAR_FLAGS_OFFSET) |= 1;
        }
    }

    const char* CVarString(CVarIndex index)
    {
        void* handle = s_cvars[index].Handle;
        const char* value = handle ? *reinterpret_cast<const char**>(static_cast<uint8_t*>(handle) + CVAR_STRING_OFFSET) : nullptr;
        return value ? value : s_cvars[index].Default;
    }

    int CVarInt(CVarIndex index) { return atoi(CVarString(index)); }
    float CVarFloat(CVarIndex index) { return static_cast<float>(atof(CVarString(index))); }

    struct Target
    {
        void* Model = nullptr;
        float Color[4] = {};
        bool OpaqueOnly = false;    // a mount: its alpha keyed batches (fire, feathers, glow) drawn flat are blocks
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
    // OutlineDebug: the last depth-tested silhouette - the render target, the depth buffer, our mask, the draw's result
    struct DepthInfo
    {
        UINT TargetWidth, TargetHeight, TargetSamples;
        UINT DepthWidth, DepthHeight, DepthSamples;
        UINT MaskSamples;
        UINT TargetQuality, DepthQuality, MaskQuality;
        UINT ZFunc;                     // the client's (1 never .. 8 always)
        UINT ZEnable;                   // the client's (0 off, 1 z-buffer, 2 w-buffer; 99 unknown)
        HRESULT Result;
    } s_depthInfo = {};
    uint32_t s_frameBatches = 0;
    uint32_t s_frameSilhouettes = 0;

    // OutlineMode(bits): 1 - no silhouettes, 2 - no full-screen pass, 4 - low quality (8 samples),
    //  8 - stage 1: the silhouettes straight on the screen, no depth test
    uint32_t s_mode = 0;

    std::vector<Target> s_targets;
    Target const* s_currentTarget = nullptr;    // set while the client draws a batch of an outlined model
    IDirect3DDevice9* s_hookedDevice = nullptr;         // the device our objects belong to
    bool s_currentOpaque = true;                // that batch is opaque (not alpha keyed, no glow flags)
    bool s_currentAttachment = false;           // that batch is of a model attached to it (weapon, spell effect)

    // our device objects
    IDirect3DPixelShader9* s_flatShader = nullptr;
    IDirect3DPixelShader9* s_flatAlphaShader = nullptr;   // the same, cut by the client's texture's alpha
    IDirect3DPixelShader9* s_outlineShader = nullptr;
    IDirect3DPixelShader9* s_outlineLowShader = nullptr;
    IDirect3DVertexShader9* s_quadShader = nullptr;
    IDirect3DVertexDeclaration9* s_quadDeclaration = nullptr;
    IDirect3DVertexBuffer9* s_quadBuffer = nullptr;     // managed: survives a device reset
    IDirect3DTexture9* s_mask = nullptr;                // default pool: released before a device reset
    IDirect3DSurface9* s_maskSurface = nullptr;
    // with antialiasing: the silhouettes go into a multisampled surface like the back buffer (the scene's depth
    // buffer fits only that), copied into the mask texture before the full-screen pass
    IDirect3DSurface9* s_maskMultisampled = nullptr;

    // SSAO: the scene's depth copied (RESZ, the drivers' multisampled depth resolve) into an INTZ texture, sampled
    IDirect3DTexture9* s_depthCopy = nullptr;           // default pool: released before a device reset
    UINT s_depthCopyWidth = 0, s_depthCopyHeight = 0;
    // without antialiasing: our INTZ texture IS the scene's depth buffer (put in place of the client's); either
    // way the passes read s_depthView
    IDirect3DTexture9* s_ownDepth = nullptr;            // default pool
    IDirect3DSurface9* s_ownDepthSurface = nullptr;
    IDirect3DSurface9* s_clientDepth = nullptr;         // the client's own (not held)
    IDirect3DTexture9* s_depthView = nullptr;           // not held: s_depthCopy or s_ownDepth
    UINT s_viewWidth = 0, s_viewHeight = 0;
    bool s_reszSupported = false;
    IDirect3DPixelShader9* s_ssaoShader = nullptr;
    IDirect3DPixelShader9* s_ssaoBlurShader = nullptr;
    IDirect3DTexture9* s_aoTexture = nullptr;           // the raw occlusion, blurred onto the screen (default pool)
    IDirect3DSurface9* s_aoSurface = nullptr;
    // color grading: the scene copied (resolved), then drawn back graded
    IDirect3DPixelShader9* s_gradeShader = nullptr;
    IDirect3DTexture9* s_sceneCopy = nullptr;           // default pool
    IDirect3DSurface9* s_sceneCopySurface = nullptr;
    UINT s_sceneCopyWidth = 0, s_sceneCopyHeight = 0;
    bool s_gradeChecked = false;
    // bloom / sun rays / depth of field: quarter screen render targets
    IDirect3DTexture9* s_small[3] = {};                 // default pool
    IDirect3DSurface9* s_smallSurface[3] = {};
    UINT s_smallWidth = 0, s_smallHeight = 0;
    IDirect3DPixelShader9* s_downShader = nullptr;
    IDirect3DPixelShader9* s_blurShader = nullptr;
    IDirect3DPixelShader9* s_radialShader = nullptr;
    IDirect3DPixelShader9* s_addShader = nullptr;
    IDirect3DPixelShader9* s_dofShader = nullptr;
    bool s_postChecked = false;
    bool s_depthReady = false;                          // this frame's depth copy is there
    float s_sunScreen[4] = {};
    // water reflections: the water's draws (the client's liquid pixel shaders, CGxShader* at these addresses:
    // psLiquidWater, psLiquidWaterNoSpec, psLiquidProcWater) drawn once more into a mask, writing depth (the
    // client's water doesn't: the reflection starts on the surface, not the bottom)
    const uintptr_t WATER_SHADER_SLOTS[] = { 0xD44C0C, 0xD44BF8, 0xD44C20 };
    bool s_waterBound = false;
    IDirect3DTexture9* s_waterMask = nullptr;           // default pool
    IDirect3DSurface9* s_waterMaskSurface = nullptr;
    IDirect3DSurface9* s_waterMaskMultisampled = nullptr;
    UINT s_waterMaskWidth = 0, s_waterMaskHeight = 0;
    bool s_waterDirty = false;
    uint32_t s_waterDraws = 0, s_frameWaterDraws = 0;
    IDirect3DPixelShader9* s_ssrShader = nullptr;
    bool s_ssrChecked = false;
    uint32_t s_frameCount = 0;                          // OutlineDebug: the sun's u, v, in front (1/0), visibility
    // 0 off, 1 drawn, 2 no INTZ, 3 no RESZ (the driver), 4 no antialiasing (needs it: RESZ copies a multisampled
    // depth buffer), 5 no shader (the compiler), 6 the depth texture failed
    uint32_t s_ssaoStatus = 0;
    bool s_ssaoChecked = false, s_ssaoSupported = false;
    D3DMULTISAMPLE_TYPE s_maskSamples = D3DMULTISAMPLE_NONE;
    DWORD s_maskQuality = 0;
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

    // Lua SetUnitOutline: units outlined in a color of their own (until ClearUnitOutline)
    struct CustomOutline
    {
        WoWGUID Guid;
        float Color[3];
    };
    std::vector<CustomOutline> s_custom;

    // the color of a unit for the player: its reaction (hostile, neutral, friendly; friendly players blue)
    void ReactionColor(CGObject* unit, float color[3])
    {
        WoWGUID playerGuid = reinterpret_cast<WoWGUID (__cdecl*)()>(ADDR_ACTIVE_PLAYER)();
        CGObject* player = FindUnit(playerGuid);
        const float* chosen = COLOR_NEUTRAL;
        if (player && player != unit)
        {
            int reaction = reinterpret_cast<int (__thiscall*)(CGObject*, CGObject*)>(ADDR_UNIT_REACTION)(player, unit);
            bool attackable = reinterpret_cast<bool (__thiscall*)(CGObject*, CGObject*)>(ADDR_CAN_ATTACK)(player, unit);
            bool isPlayer = (unit->m_objectData->m_type & TYPEMASK_PLAYER) != 0;
            if (reaction <= 3)
                chosen = COLOR_HOSTILE;
            else if (reaction == 4 && attackable)
                chosen = COLOR_NEUTRAL;
            else
                chosen = isPlayer ? COLOR_FRIENDLY_PLAYER : COLOR_FRIENDLY;
        }
        else if (player == unit)
            chosen = COLOR_FRIENDLY_PLAYER;
        memcpy(color, chosen, sizeof(float) * 3);
    }

    void AddTarget(CGObject* object, const float* color = nullptr)
    {
        if (!object || !object->m_model)
            return;
        for (Target& target : s_targets)
            if (target.Model == object->m_model)
                return;     // the first reason wins (custom, target, mouseover, boss, player)
        Target target;
        target.Model = object->m_model;
        if (color)
            memcpy(target.Color, color, sizeof(float) * 3);
        else
            ReactionColor(object, target.Color);
        target.Color[3] = 1.0f;
        s_targets.push_back(target);

        // on a mount the unit's model is the rider, attached to the mount's model: that one too (and so all
        // that hangs on the mount, through the parent chain in FindTarget)
        void* parent = *reinterpret_cast<void**>(static_cast<uint8_t*>(object->m_model) + MODEL_PARENT);
        for (int depth = 0; parent && depth < 3; ++depth)
        {
            bool known = false;
            for (Target const& existing : s_targets)
                known = known || existing.Model == parent;
            if (!known)
            {
                Target mount = target;
                mount.Model = parent;
                mount.OpaqueOnly = true;
                s_targets.push_back(mount);
            }
            parent = *reinterpret_cast<void**>(static_cast<uint8_t*>(parent) + MODEL_PARENT);
        }
    }

    struct Position
    {
        float X, Y, Z;
    };

    Position GetPosition(CGObject* object)
    {
        Position position = {};
        void** vtable = *reinterpret_cast<void***>(object);
        reinterpret_cast<Position& (__thiscall*)(CGObject*, Position&)>(vtable[VT_OBJECT_GET_POSITION])(object, position);
        return position;
    }

    // within the nameplates' distance of the player (the always-on outlines: every unit, the bosses)
    Position s_playerPosition = {};
    float s_maxDistanceSq = 41.0f * 41.0f;

    bool InRange(CGObject* object)
    {
        Position position = GetPosition(object);
        float dx = position.X - s_playerPosition.X, dy = position.Y - s_playerPosition.Y, dz = position.Z - s_playerPosition.Z;
        return dx * dx + dy * dy + dz * dz <= s_maxDistanceSq;
    }

    // the bosses around (OutlineQuestBoss)
    int __cdecl EnumBoss(WoWGUID guid, void* /*param*/)
    {
        if (s_targets.size() >= MAX_BOSSES)
            return 0;
        CGObject* object = FindUnit(guid);
        if (object && (object->m_objectData->m_type & TYPEMASK_UNIT) && !(object->m_objectData->m_type & TYPEMASK_PLAYER)
            && reinterpret_cast<uint32_t (__thiscall*)(CGObject*)>(ADDR_CREATURE_RANK)(object) == RANK_WORLD_BOSS && InRange(object))
            AddTarget(object);
        return 1;
    }

    // every unit around (OutlineAll, the mode in param), not the player himself (OutlinePlayer)
    int __cdecl EnumAll(WoWGUID guid, void* param)
    {
        if (s_targets.size() >= MAX_OUTLINED)
            return 0;
        CGObject* object = FindUnit(guid);
        if (!object || !(object->m_objectData->m_type & TYPEMASK_UNIT) || !object->m_model)
            return 1;
        if (guid == reinterpret_cast<WoWGUID (__cdecl*)()>(ADDR_ACTIVE_PLAYER)() || !InRange(object))
            return 1;
        float color[3];
        ReactionColor(object, color);
        bool hostile = memcmp(color, COLOR_HOSTILE, sizeof(color)) == 0;
        bool friendly = memcmp(color, COLOR_FRIENDLY, sizeof(color)) == 0 || memcmp(color, COLOR_FRIENDLY_PLAYER, sizeof(color)) == 0;
        bool isPlayer = (object->m_objectData->m_type & TYPEMASK_PLAYER) != 0;
        switch (static_cast<OutlineAllMode>(reinterpret_cast<intptr_t>(param)))
        {
            case ALL_HOSTILE:   if (!hostile) return 1; break;
            case ALL_FRIENDLY:  if (!friendly) return 1; break;
            case ALL_PLAYERS:   if (!isPlayer) return 1; break;
            case ALL_CREATURES: if (isPlayer) return 1; break;
            default: break;
        }
        AddTarget(object, color);
        return 1;
    }

    // the models of the next frame, by the CVars
    void CollectTargets()
    {
        s_targets.clear();
        if (CVarInt(CV_QUALITY) > 0)
        {
            if (CGObject* player = FindUnit(reinterpret_cast<WoWGUID (__cdecl*)()>(ADDR_ACTIVE_PLAYER)()))
                s_playerPosition = GetPosition(player);
            float distanceSq = *reinterpret_cast<float*>(ADDR_NAMEPLATE_DIST_SQ);
            s_maxDistanceSq = distanceSq > 1.0f ? distanceSq : 41.0f * 41.0f;
            for (CustomOutline const& custom : s_custom)
                AddTarget(FindUnit(custom.Guid), custom.Color);
            if (CVarInt(CV_TARGET))
                AddTarget(FindUnit(*reinterpret_cast<WoWGUID*>(ADDR_TARGET_GUID)));
            if (CVarInt(CV_MOUSEOVER))
                AddTarget(FindUnit(*reinterpret_cast<WoWGUID*>(ADDR_MOUSEOVER_GUID)));
            if (CVarInt(CV_QUESTBOSS))
                reinterpret_cast<int (__cdecl*)(int (__cdecl*)(WoWGUID, void*), void*)>(ADDR_ENUM_VISIBLE)(&EnumBoss, nullptr);
            if (CVarInt(CV_PLAYER))
                AddTarget(FindUnit(reinterpret_cast<WoWGUID (__cdecl*)()>(ADDR_ACTIVE_PLAYER)()));
            if (int all = CVarInt(CV_ALL))
                reinterpret_cast<int (__cdecl*)(int (__cdecl*)(WoWGUID, void*), void*)>(ADDR_ENUM_VISIBLE)(
                    &EnumAll, reinterpret_cast<void*>(static_cast<intptr_t>(all)));
        }
        s_stats.Targets = static_cast<uint32_t>(s_targets.size());
    }

    // the outlined model the batch belongs to (itself or an attachment of it)
    Target const* FindTarget(uint8_t* batch)
    {
        uint8_t* material = *reinterpret_cast<uint8_t**>(batch + BATCH_MATERIAL);
        if (!material || *reinterpret_cast<uint32_t*>(material) > MAX_BLEND_MODE || (material[8] & 1))
            return nullptr;
        // a mount's / an attachment's batch: opaque, lit and fogged, writing depth - glows and flames are unlit,
        // unfogged or don't write depth (M2 render flags 0x1 / 0x2 / 0x10), their shape only in the texture
        bool opaque = *reinterpret_cast<uint32_t*>(material) == 0 && !(material[8] & (0x2 | 0x10));
        s_currentOpaque = opaque;
        s_currentAttachment = false;
        void* model = *reinterpret_cast<void**>(batch + BATCH_MODEL);
        for (int depth = 0; model && depth < 8; ++depth)
        {
            for (Target const& target : s_targets)
                if (target.Model == model)
                {
                    // a mount's effects: the same small billboard rule as an attachment's
                    s_currentAttachment = s_currentAttachment || target.OpaqueOnly;
                    return target.OpaqueOnly && !opaque ? nullptr : &target;
                }
            // an attachment (weapon, spell effect): opaque batches only - an alpha keyed spell quad drawn flat
            // is a square
            if (!opaque)
                return nullptr;
            s_currentAttachment = true;
            model = *reinterpret_cast<void**>(static_cast<uint8_t*>(model) + MODEL_PARENT);
        }
        return nullptr;
    }

    // ---------------------------------------------------------------- the device: what Gx sends, copied
    enum VtableIndex : uint32_t
    {
        VT_RESET                = 16,
        VT_SET_DEPTH_STENCIL    = 39,
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
    constexpr uint32_t SHADOW_PS_REGISTERS = 8;     // c0 .. c7: the ones we use
    constexpr uint32_t SHADOW_SAMPLER_STATES = 14;
    constexpr uint32_t SHADOW_STAGES = 3;           // s0 .. s2: the ones we use

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
    typedef HRESULT (__stdcall* SetDepthStencilFn)(IDirect3DDevice9*, IDirect3DSurface9*);
    SetDepthStencilFn s_setDepthStencil = nullptr;
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
        IDirect3DBaseTexture9* Texture[SHADOW_STAGES] = {};
        DWORD Sampler[SHADOW_STAGES][SHADOW_SAMPLER_STATES] = {};
        bool SamplerKnown[SHADOW_STAGES][SHADOW_SAMPLER_STATES] = {};
        IDirect3DVertexDeclaration9* Declaration = nullptr;
        DWORD FVF = 0;
        bool DeclarationLast = true;        // the last of SetVertexDeclaration / SetFVF
        IDirect3DVertexShader9* VertexShader = nullptr;
        IDirect3DVertexBuffer9* Stream0 = nullptr;
        UINT Stream0Offset = 0, Stream0Stride = 0;
        IDirect3DPixelShader9* PixelShader = nullptr;
        float PsConstants[SHADOW_PS_REGISTERS * 4] = {};
    } s_shadow;

    // the client's depth buffer: ours instead while it is in use (no antialiasing, an effect needing depth)
    HRESULT __stdcall SetDepthStencilDetour(IDirect3DDevice9* device, IDirect3DSurface9* surface)
    {
        if (surface && surface != s_ownDepthSurface)
        {
            if (s_ownDepthSurface && surface == s_clientDepth)
                return s_setDepthStencil(device, s_ownDepthSurface);
        }
        return s_setDepthStencil(device, surface);
    }

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
        if (stage < SHADOW_STAGES)
            s_shadow.Texture[stage] = texture;
        return s_setTexture(device, stage, texture);
    }

    HRESULT __stdcall SetSamplerStateDetour(IDirect3DDevice9* device, DWORD sampler, D3DSAMPLERSTATETYPE type, DWORD value)
    {
        if (sampler < SHADOW_STAGES && type < SHADOW_SAMPLER_STATES)
        {
            s_shadow.Sampler[sampler][type] = value;
            s_shadow.SamplerKnown[sampler][type] = true;
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

    // one of the client's water shaders: its CGxShader holds the D3D shader somewhere in its first bytes
    bool IsWaterShader(IDirect3DPixelShader9* shader)
    {
        if (!shader)
            return false;
        for (uintptr_t slot : WATER_SHADER_SLOTS)
        {
            void** gxShader = *reinterpret_cast<void***>(slot);
            if (!gxShader)
                continue;
            for (int i = 0; i < 24; ++i)
                if (gxShader[i] == shader)
                    return true;
        }
        return false;
    }

    HRESULT __stdcall SetPixelShaderDetour(IDirect3DDevice9* device, IDirect3DPixelShader9* shader)
    {
        s_shadow.PixelShader = shader;
        s_waterBound = IsWaterShader(shader);
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
        { D3DRS_DEPTHBIAS, 0 }, { D3DRS_SLOPESCALEDEPTHBIAS, 0 }, { D3DRS_POINTSIZE, 0x3F800000 },
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
        if (s_maskMultisampled)
            s_maskMultisampled->Release();
        if (s_maskSurface)
            s_maskSurface->Release();
        if (s_mask)
            s_mask->Release();
        s_maskMultisampled = nullptr;
        s_maskSurface = nullptr;
        s_mask = nullptr;
        s_maskWidth = s_maskHeight = 0;
        s_maskDirty = false;
    }

    void ReleaseSmall()
    {
        for (int i = 0; i < 3; ++i)
        {
            if (s_smallSurface[i])
                s_smallSurface[i]->Release();
            if (s_small[i])
                s_small[i]->Release();
            s_smallSurface[i] = nullptr;
            s_small[i] = nullptr;
        }
        s_smallWidth = s_smallHeight = 0;
    }

    void ReleaseWaterMask()
    {
        if (s_waterMaskMultisampled)
            s_waterMaskMultisampled->Release();
        if (s_waterMaskSurface)
            s_waterMaskSurface->Release();
        if (s_waterMask)
            s_waterMask->Release();
        s_waterMaskMultisampled = nullptr;
        s_waterMaskSurface = nullptr;
        s_waterMask = nullptr;
        s_waterMaskWidth = s_waterMaskHeight = 0;
    }

    void ReleaseOwnDepth()
    {
        if (s_ownDepthSurface)
            s_ownDepthSurface->Release();
        if (s_ownDepth)
            s_ownDepth->Release();
        s_ownDepthSurface = nullptr;
        s_ownDepth = nullptr;
    }

    void ReleasePostTargets()
    {
        ReleaseWaterMask();
        ReleaseOwnDepth();
        s_depthView = nullptr;
        s_viewWidth = s_viewHeight = 0;
        if (s_depthCopy)
            s_depthCopy->Release();
        if (s_aoSurface)
            s_aoSurface->Release();
        if (s_aoTexture)
            s_aoTexture->Release();
        if (s_sceneCopySurface)
            s_sceneCopySurface->Release();
        if (s_sceneCopy)
            s_sceneCopy->Release();
        s_depthCopy = nullptr;
        s_aoSurface = nullptr;
        s_aoTexture = nullptr;
        s_sceneCopySurface = nullptr;
        s_sceneCopy = nullptr;
        s_depthCopyWidth = s_depthCopyHeight = 0;
        s_sceneCopyWidth = s_sceneCopyHeight = 0;
        ReleaseSmall();
    }

    HRESULT __stdcall ResetDetour(IDirect3DDevice9* device, D3DPRESENT_PARAMETERS* parameters)
    {
        if (s_ownDepthSurface && s_clientDepth && s_setDepthStencil)
            s_setDepthStencil(device, s_clientDepth);
        s_clientDepth = nullptr;
        ReleaseMask();      // a default pool resource: a reset fails while it exists
        ReleasePostTargets();
        HRESULT result = s_reset(device, parameters);
        // the device is back at its defaults: so is our copy of what Gx set (else our restore after a pass puts the
        // states of before the reset back - Gx doesn't know them: a dark, broken world)
        if (SUCCEEDED(result))
            s_shadow = Shadow();
        return result;
    }

    // ---------------------------------------------------------------- shaders
    // HLSL compiled at run time by Windows' own compiler (d3dcompiler_47.dll, in the system since Windows 8);
    // without it the hand-assembled bytecode of OutlineShaders.hpp. A compiler error is kept for OutlineDebug.
    const char HLSL_FLAT_PS[] =
        "float4 color : register(c0);\n"
        "float4 main() : COLOR { return color; }\n";

    // a mount's / an attachment's batch: flames, feathers, glows are quads whose shape is only in the texture's alpha.
    // The client's texture (stage 0) and its sampler are still bound; its vertex shader puts the uv in TEXCOORD0
    const char HLSL_FLAT_ALPHA_PS[] =
        "sampler2D diffuse : register(s0);\n"
        "float4 color : register(c0);\n"
        "float4 main(float2 uv : TEXCOORD0) : COLOR { clip(tex2D(diffuse, uv).a - 0.5); return color; }\n";

    const char HLSL_QUAD_VS[] =
        "struct V { float4 position : POSITION; float2 uv : TEXCOORD0; };\n"
        "V main(V v) { return v; }\n";

    // c0.xy one texel, c1.x alpha gain, c1.y strength, c1.z thickness. The mask's halo (samples around the pixel) minus the mask
    // at the pixel: the rim, in the silhouette's color.
    const char HLSL_OUTLINE_PS[] =
        "sampler2D mask : register(s0);\n"
        "float4 texel : register(c0);\n"
        "float4 look : register(c1);\n"
        "float4 main(float2 uv : TEXCOORD0) : COLOR\n"
        "{\n"
        "    float4 sum = 0;\n"
        "    [unroll] for (int ring = 1; ring <= RINGS; ++ring)\n"
        "        [unroll] for (int i = 0; i < 8; ++i)\n"
        "        {\n"
        "            float angle = 6.2831853 * (i + 0.5 * (ring - 1)) / 8;\n"
        "            float2 offset = float2(cos(angle), sin(angle)) * RADIUS * ring * look.z;\n"
        "            sum += tex2D(mask, uv + offset * texel.xy);\n"
        "        }\n"
        "    float4 center = tex2D(mask, uv);\n"
        "    float3 rgb = sum.rgb / max(sum.a, 0.0001);\n"
        "    float alpha = saturate(sum.a * look.x) * (1 - center.a) * look.y;\n"
        "    return float4(rgb, alpha);\n"
        "}\n";

    struct ShaderMacro
    {
        const char* Name;
        const char* Definition;
    };
    typedef HRESULT (WINAPI* D3DCompileFn)(const void*, SIZE_T, const char*, const ShaderMacro*, void*, const char*,
        const char*, UINT, UINT, ID3DBlob**, ID3DBlob**);

    char s_compileError[256] = "";
    bool s_compiled = false;            // OutlineDebug: the shaders came from the compiler (not the bytecode)

    D3DCompileFn GetCompiler()
    {
        static D3DCompileFn compile = nullptr;
        static bool tried = false;
        if (!tried)
        {
            tried = true;
            const char* names[] = { "d3dcompiler_47.dll", "d3dcompiler_46.dll", "d3dcompiler_43.dll" };
            for (const char* name : names)
                if (HMODULE module = LoadLibraryA(name))
                    if ((compile = reinterpret_cast<D3DCompileFn>(GetProcAddress(module, "D3DCompile"))))
                        break;
        }
        return compile;
    }

    // the bytecode of an HLSL source, or empty (s_compileError says why)
    std::vector<DWORD> Compile(const char* source, const char* target, const ShaderMacro* macros = nullptr)
    {
        std::vector<DWORD> code;
        D3DCompileFn compile = GetCompiler();
        if (!compile)
            return code;
        ID3DBlob* blob = nullptr;
        ID3DBlob* errors = nullptr;
        HRESULT result = compile(source, strlen(source), "Outline", macros, nullptr, "main", target, 0, 0, &blob, &errors);
        if (errors)
        {
            snprintf(s_compileError, sizeof(s_compileError), "%s", static_cast<const char*>(errors->GetBufferPointer()));
            errors->Release();
        }
        if (SUCCEEDED(result) && blob)
        {
            code.resize(blob->GetBufferSize() / 4);
            memcpy(code.data(), blob->GetBufferPointer(), code.size() * 4);
        }
        if (blob)
            blob->Release();
        return code;
    }

    bool CreatePixel(IDirect3DDevice9* device, const char* source, const ShaderMacro* macros, const DWORD* fallback, IDirect3DPixelShader9*& shader)
    {
        if (shader)
            return true;
        std::vector<DWORD> code = Compile(source, "ps_3_0", macros);
        if (!code.empty() && SUCCEEDED(device->CreatePixelShader(code.data(), &shader)))
        {
            s_compiled = true;
            return true;
        }
        shader = nullptr;
        return SUCCEEDED(device->CreatePixelShader(fallback, &shader));
    }

    bool CreateVertex(IDirect3DDevice9* device, const char* source, const DWORD* fallback, IDirect3DVertexShader9*& shader)
    {
        if (shader)
            return true;
        std::vector<DWORD> code = Compile(source, "vs_3_0");
        if (!code.empty() && SUCCEEDED(device->CreateVertexShader(code.data(), &shader)))
            return true;
        shader = nullptr;
        return SUCCEEDED(device->CreateVertexShader(fallback, &shader));
    }

    // the silhouette's shader: without it nothing works (OutlineDebug #8 = 2)
    bool CreateFlatShader(IDirect3DDevice9* device)
    {
        // no fallback bytecode for the alpha cut one: without the compiler those batches are drawn flat
        if (!s_flatAlphaShader)
        {
            std::vector<DWORD> code = Compile(HLSL_FLAT_ALPHA_PS, "ps_3_0");
            if (code.empty() || FAILED(device->CreatePixelShader(code.data(), &s_flatAlphaShader)))
                s_flatAlphaShader = nullptr;
        }
        return CreatePixel(device, HLSL_FLAT_PS, nullptr, OutlineShaders::SHADER_FLAT_PS, s_flatShader);
    }

    // the full-screen pass's: 0, or the error code of what failed (OutlineDebug #8); the silhouettes work anyway
    uint32_t CreateOutlineShaders(IDirect3DDevice9* device)
    {
        using namespace OutlineShaders;
        static const ShaderMacro HIGH[] = { { "RINGS", "2" }, { "RADIUS", "1.5" }, { nullptr, nullptr } };
        static const ShaderMacro LOW[] = { { "RINGS", "1" }, { "RADIUS", "2.0" }, { nullptr, nullptr } };
        if (!CreatePixel(device, HLSL_OUTLINE_PS, HIGH, SHADER_OUTLINE_PS, s_outlineShader))
            return 5;
        if (!CreatePixel(device, HLSL_OUTLINE_PS, LOW, SHADER_OUTLINE_LOW_PS, s_outlineLowShader))
            return 6;
        if (!CreateVertex(device, HLSL_QUAD_VS, SHADER_QUAD_VS, s_quadShader))
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

        // the multisampled surface must fit the scene's depth buffer exactly: its sample type AND quality
        // (a mismatch "succeeds" and draws nothing)
        D3DMULTISAMPLE_TYPE samples = desc.MultiSampleType;
        DWORD quality = desc.MultiSampleQuality;
        IDirect3DSurface9* depth = nullptr;
        if (SUCCEEDED(device->GetDepthStencilSurface(&depth)) && depth)
        {
            D3DSURFACE_DESC depthDesc = {};
            if (SUCCEEDED(depth->GetDesc(&depthDesc)) && depthDesc.Width >= desc.Width && depthDesc.Height >= desc.Height)
            {
                samples = depthDesc.MultiSampleType;
                quality = depthDesc.MultiSampleQuality;
            }
            depth->Release();
        }

        if (s_mask && s_maskWidth == desc.Width && s_maskHeight == desc.Height && s_maskSamples == samples && s_maskQuality == quality)
            return true;
        ReleaseMask();
        s_maskSamples = samples;
        s_maskQuality = quality;
        if (samples != D3DMULTISAMPLE_NONE && FAILED(device->CreateRenderTarget(desc.Width, desc.Height,
            D3DFMT_A8R8G8B8, samples, quality, FALSE, &s_maskMultisampled, nullptr)))
            s_maskMultisampled = nullptr;   // then no depth test (the depth buffer doesn't fit)
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

    // where the silhouettes are drawn
    IDirect3DSurface9* MaskTarget()
    {
        return s_maskMultisampled ? s_maskMultisampled : s_maskSurface;
    }

    // the depth test against the scene (no outline of what is behind a wall) works when our target fits the depth
    // buffer: the same antialiasing as the back buffer
    bool CanDepthTest()
    {
        return s_maskSamples == D3DMULTISAMPLE_NONE || s_maskMultisampled;
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
        device->SetRenderTarget(0, MaskTarget());
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

    // the water's draw once more: white into the water mask, its depth into the scene's depth buffer
    void DrawWater(IDirect3DDevice9* device, D3DPRIMITIVETYPE type, INT baseVertex, UINT minIndex, UINT numVertices,
        UINT startIndex, UINT primitiveCount)
    {
        IDirect3DSurface9* renderTarget = nullptr;
        device->GetRenderTarget(0, &renderTarget);
        if (FAILED(device->SetRenderTarget(0, s_waterMaskMultisampled ? s_waterMaskMultisampled : s_waterMaskSurface)))
        {
            if (renderTarget)
                renderTarget->Release();
            return;
        }
        RestoreViewport(device);
        const float white[4] = { 1.0f, 1.0f, 1.0f, 1.0f };
        s_setPixelShader(device, s_flatShader);
        s_setPsConstant(device, 0, white, 1);
        SetSilhouetteStates(device);
        SetState(device, D3DRS_ZENABLE, D3DZB_TRUE);
        SetState(device, D3DRS_ZWRITEENABLE, TRUE);
        SetState(device, D3DRS_ZFUNC, D3DCMP_LESSEQUAL);
        s_drawIndexed(device, type, baseVertex, minIndex, numVertices, startIndex, primitiveCount);
        device->SetRenderTarget(0, renderTarget);
        if (renderTarget)
            renderTarget->Release();
        RestoreViewport(device);
        RestorePixelShader(device);
        RestoreStates(device);
        ++s_frameWaterDraws;
        s_waterDirty = true;
    }

    // ---------------------------------------------------------------- 1. the silhouettes
    HRESULT __stdcall DrawIndexedPrimitiveDetour(IDirect3DDevice9* device, D3DPRIMITIVETYPE type, INT baseVertex,
        UINT minIndex, UINT numVertices, UINT startIndex, UINT primitiveCount)
    {
        HRESULT result = s_drawIndexed(device, type, baseVertex, minIndex, numVertices, startIndex, primitiveCount);
        if (device != s_hookedDevice)
            return result;      // a new device: our objects are made again at the end of the frame
        if (s_waterBound && s_waterMaskSurface)
            DrawWater(device, type, baseVertex, minIndex, numVertices, startIndex, primitiveCount);
        if (!s_currentTarget || (s_mode & 1))
            return result;
        // a billboard (an attachment's, or the unit's own glow / alpha keyed card: a few triangles, its shape only
        // in the texture): not a
        // silhouette. Weapons and armor pieces have far more
        if ((s_currentAttachment || !s_currentOpaque) && primitiveCount < MIN_ATTACHMENT_TRIANGLES)
            return result;
        bool toScreen = (s_mode & 8) != 0;
        if (!toScreen && !s_maskSurface)
            return result;

        // the same draw once more: our shader, the color; into the mask (or the screen: stage 1 test).
        // Depth tested against the scene (the parts behind walls left out); with no depth
        // test the depth buffer is unbound (it may not fit the mask)
        bool depthTest = CanDepthTest();
        IDirect3DSurface9* renderTarget = nullptr;
        IDirect3DSurface9* depthStencil = nullptr;
        if (!toScreen)
        {
            device->GetRenderTarget(0, &renderTarget);
            device->SetRenderTarget(0, MaskTarget());
            if (!depthTest)
            {
                device->GetDepthStencilSurface(&depthStencil);
                device->SetDepthStencilSurface(nullptr);
            }
            // SetRenderTarget resets the viewport to the whole target with depth 0..1: the client's back (its
            // MinZ / MaxZ), else the silhouette's depth doesn't match the scene's
            RestoreViewport(device);
        }
        // cut by the texture's alpha: attachments, mounts, and the unit's own alpha keyed / glowing batches (fur,
        // feathers, effects - flat they are blocks). 64: no alpha cut (a test switch)
        bool alphaCut = (s_currentAttachment || !s_currentOpaque) && s_flatAlphaShader && !(s_mode & 64);
        s_setPixelShader(device, alphaCut ? s_flatAlphaShader : s_flatShader);
        s_setPsConstant(device, 0, s_currentTarget->Color, 1);
        SetSilhouetteStates(device);
        if (depthTest)
        {
            // the client's own depth function for this model, made "or equal": the silhouette lies exactly on the
            // model's depth (a strict LESS / GREATER would reject all of it)
            DWORD zfunc = s_shadow.Known[D3DRS_ZFUNC] ? s_shadow.RenderStates[D3DRS_ZFUNC] : D3DCMP_LESSEQUAL;
            if (zfunc == D3DCMP_LESS || zfunc == D3DCMP_EQUAL || zfunc == D3DCMP_NEVER)
                zfunc = D3DCMP_LESSEQUAL;
            else if (zfunc == D3DCMP_GREATER)
                zfunc = D3DCMP_GREATEREQUAL;
            // the client's depth mode too (a W-buffer, 2, compares in another scale than a Z-buffer)
            DWORD zenable = s_shadow.Known[D3DRS_ZENABLE] ? s_shadow.RenderStates[D3DRS_ZENABLE] : D3DZB_TRUE;
            if (zenable == D3DZB_FALSE)
                zenable = D3DZB_TRUE;
            // test switches: 16 - depth buffer bound but no test (does a draw with it bound work at all?),
            // 32 - GREATEREQUAL
            if (s_mode & 16)
                zfunc = D3DCMP_ALWAYS;
            else if (s_mode & 32)
                zfunc = D3DCMP_GREATEREQUAL;
            s_depthInfo.ZFunc = s_shadow.Known[D3DRS_ZFUNC] ? s_shadow.RenderStates[D3DRS_ZFUNC] : 0;
            s_depthInfo.ZEnable = s_shadow.Known[D3DRS_ZENABLE] ? s_shadow.RenderStates[D3DRS_ZENABLE] : 99;
            SetState(device, D3DRS_ZENABLE, zenable);
            SetState(device, D3DRS_ZFUNC, zfunc);
            // the silhouette's depth comes out a hair behind the model's own: pulled toward the camera a little
            // (a wall in front is far more in front than this)
            const float bias = -0.0005f, slope = -2.0f;
            SetState(device, D3DRS_DEPTHBIAS, *reinterpret_cast<const DWORD*>(&bias));
            SetState(device, D3DRS_SLOPESCALEDEPTHBIAS, *reinterpret_cast<const DWORD*>(&slope));
        }

        if (depthTest)
        {
            D3DSURFACE_DESC desc = {};
            if (renderTarget && SUCCEEDED(renderTarget->GetDesc(&desc)))
            {
                s_depthInfo.TargetWidth = desc.Width;
                s_depthInfo.TargetHeight = desc.Height;
                s_depthInfo.TargetSamples = desc.MultiSampleType;
                s_depthInfo.TargetQuality = desc.MultiSampleQuality;
            }
            IDirect3DSurface9* depth = nullptr;
            if (SUCCEEDED(device->GetDepthStencilSurface(&depth)) && depth)
            {
                if (SUCCEEDED(depth->GetDesc(&desc)))
                {
                    s_depthInfo.DepthWidth = desc.Width;
                    s_depthInfo.DepthHeight = desc.Height;
                    s_depthInfo.DepthSamples = desc.MultiSampleType;
                    s_depthInfo.DepthQuality = desc.MultiSampleQuality;
                }
                depth->Release();
            }
            else
                s_depthInfo.DepthWidth = s_depthInfo.DepthHeight = 0;
            s_depthInfo.MaskSamples = s_maskSamples;
            s_depthInfo.MaskQuality = s_maskQuality;
        }
        HRESULT drawResult = s_drawIndexed(device, type, baseVertex, minIndex, numVertices, startIndex, primitiveCount);
        if (depthTest)
            s_depthInfo.Result = drawResult;
        ++s_frameSilhouettes;
        s_maskDirty = true;

        if (!toScreen)
        {
            device->SetRenderTarget(0, renderTarget);
            if (depthStencil)
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
    void RestoreGx(IDirect3DDevice9* device);

    void Composite(IDirect3DDevice9* device)
    {
        if (!s_maskSurface || !s_frameSilhouettes || (s_mode & (2 | 8)) || !s_outlineShader || !s_outlineLowShader
            || !s_quadShader || !s_quadDeclaration)
            return;
        if (s_maskMultisampled)
            device->StretchRect(s_maskMultisampled, nullptr, s_maskSurface, nullptr, D3DTEXF_NONE);
        FillQuad(s_maskWidth, s_maskHeight);

        const float texel[4] = { 1.0f / s_maskWidth, 1.0f / s_maskHeight, 0.0f, 0.0f };
        bool low = (s_mode & 4) || CVarInt(CV_QUALITY) == 2;
        float thickness = CVarFloat(CV_THICKNESS);
        float strength = CVarFloat(CV_STRENGTH);
        thickness = thickness < 0.5f ? 0.5f : (thickness > 3.0f ? 3.0f : thickness);
        strength = strength < 0.0f ? 0.0f : (strength > 1.0f ? 1.0f : strength);
        const float look[4] = { low ? ALPHA_GAIN_LOW : ALPHA_GAIN_HIGH, strength, thickness, 0.0f };

        s_setVertexShader(device, s_quadShader);
        s_setPixelShader(device, low ? s_outlineLowShader : s_outlineShader);
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

        RestoreGx(device);
    }

    // after a full-screen pass: exactly what Gx had set
    void RestoreGx(IDirect3DDevice9* device)
    {
        s_setVertexShader(device, s_shadow.VertexShader);
        RestorePixelShader(device);
        if (s_shadow.DeclarationLast)
            s_setVertexDeclaration(device, s_shadow.Declaration);
        else
            s_setFVF(device, s_shadow.FVF);
        s_setStreamSource(device, 0, s_shadow.Stream0, s_shadow.Stream0Offset, s_shadow.Stream0Stride);
        const D3DSAMPLERSTATETYPE samplers[] = { D3DSAMP_ADDRESSU, D3DSAMP_ADDRESSV, D3DSAMP_MAGFILTER, D3DSAMP_MINFILTER, D3DSAMP_MIPFILTER, D3DSAMP_SRGBTEXTURE };
        const DWORD samplerDefaults[] = { D3DTADDRESS_WRAP, D3DTADDRESS_WRAP, D3DTEXF_POINT, D3DTEXF_POINT, D3DTEXF_NONE, FALSE };
        for (DWORD stage = 0; stage < SHADOW_STAGES; ++stage)
        {
            s_setTexture(device, stage, s_shadow.Texture[stage]);
            for (size_t i = 0; i < sizeof(samplers) / sizeof(samplers[0]); ++i)
                s_setSamplerState(device, stage, samplers[i],
                    s_shadow.SamplerKnown[stage][samplers[i]] ? s_shadow.Sampler[stage][samplers[i]] : samplerDefaults[i]);
        }
        RestoreStates(device);
    }

    // ---------------------------------------------------------------- SSAO
    // Depth only (no normals): for a pair of samples on both sides of the pixel, the depth buffer's value is affine
    // in screen space on a plane, so their mean is the pixel's own depth on any flat surface (no darkening of
    // slopes); in a crease it is nearer - by how much, in yards, is the occlusion. c0 texel.xy, near, far;
    // c1 radius (yards), strength, pixels per yard at 1 yard
    const char HLSL_SSAO_PS[] =
        "sampler2D depthTex : register(s0);\n"
        "float4 screen : register(c0);\n"
        "float4 params : register(c1);\n"
        "float Linear(float d) { return screen.z * screen.w / (screen.w - d * (screen.w - screen.z)); }\n"
        "float4 main(float2 uv : TEXCOORD0, float2 vpos : VPOS) : COLOR\n"
        "{\n"
        "    float d = tex2Dlod(depthTex, float4(uv, 0, 0)).r;\n"
        "    clip(0.99999 - d);\n"
        "    float z = Linear(d);\n"
        "    float radius = clamp(params.x * params.z / z, 3.0, 80.0);\n"
        "    float angle = frac(sin(dot(vpos, float2(12.9898, 78.233))) * 43758.5453) * 6.2831853;\n"
        "    float occlusion = 0;\n"
        "    [unroll] for (int i = 0; i < 8; ++i)\n"
        "    {\n"
        "        float a = angle + i * 2.3999632;\n"
        "        float2 offset = float2(cos(a), sin(a)) * radius * sqrt((i + 0.5) / 8) * screen.xy;\n"
        "        float dA = tex2Dlod(depthTex, float4(uv + offset, 0, 0)).r;\n"
        "        float dB = tex2Dlod(depthTex, float4(uv - offset, 0, 0)).r;\n"
        "        if (dA < 0.99999 && dB < 0.99999)\n"
        "        {\n"
        "            float crease = z - Linear(0.5 * (dA + dB));\n"
        "            occlusion += saturate(crease / params.x) * saturate((3.0 * params.x - crease) / (2.0 * params.x));\n"
        "        }\n"
        "    }\n"
        "    return float4(saturate(occlusion / 8), 0, 0, 1);\n"
        "}\n";

    // the occlusion blurred (5 x 5 taps, 2 pixels apart) where the depth is about the same - not across an edge -
    // and darkening the screen. s0 the occlusion, s1 the depth; c0 texel.xy, near, far; c1.y strength
    const char HLSL_SSAO_BLUR_PS[] =
        "sampler2D aoTex : register(s0);\n"
        "sampler2D depthTex : register(s1);\n"
        "float4 screen : register(c0);\n"
        "float4 params : register(c1);\n"
        "float Linear(float d) { return screen.z * screen.w / (screen.w - d * (screen.w - screen.z)); }\n"
        "float4 main(float2 uv : TEXCOORD0) : COLOR\n"
        "{\n"
        "    float d = tex2Dlod(depthTex, float4(uv, 0, 0)).r;\n"
        "    clip(0.99999 - d);\n"
        "    float z = Linear(d);\n"
        "    float sum = 0, weights = 0;\n"
        "    [unroll] for (int y = -2; y <= 2; ++y)\n"
        "        [unroll] for (int x = -2; x <= 2; ++x)\n"
        "        {\n"
        "            float4 at = float4(uv + float2(x, y) * 2.0 * screen.xy, 0, 0);\n"
        "            float w = saturate(1.0 - abs(Linear(tex2Dlod(depthTex, at).r) - z) / (0.05 * z + 0.1));\n"
        "            sum += tex2Dlod(aoTex, at).r * w;\n"
        "            weights += w;\n"
        "        }\n"
        "    return float4(0, 0, 0, saturate(sum / max(weights, 0.0001) * params.y));\n"
        "}\n";

    // color grading: s0 the scene; c0 texel.xy; c1 contrast, saturation, sharpening, brightness; c2 vignette, grain,
    // a value changing every frame (the grain's seed), the tone mapping's exposure (0: none; ACES' curve)
    const char HLSL_GRADE_PS[] =
        "sampler2D scene : register(s0);\n"
        "float4 screen : register(c0);\n"
        "float4 params : register(c1);\n"
        "float4 look : register(c2);\n"
        "float3 At(float2 uv) { return tex2Dlod(scene, float4(uv, 0, 0)).rgb; }\n"
        "float4 main(float2 uv : TEXCOORD0) : COLOR\n"
        "{\n"
        "    float3 c = At(uv);\n"
        "    if (look.w > 0)\n"
        "    {\n"
        "        float3 x = c * look.w;\n"
        "        c = saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));\n"
        "    }\n"
        "    float3 around = At(uv + float2(screen.x, 0)) + At(uv - float2(screen.x, 0))\n"
        "        + At(uv + float2(0, screen.y)) + At(uv - float2(0, screen.y));\n"
        "    c += (c - around * 0.25) * params.z;\n"
        "    c *= params.w;\n"
        "    float luma = dot(c, float3(0.299, 0.587, 0.114));\n"
        "    c = lerp(luma.xxx, c, params.y);\n"
        "    c = (c - 0.5) * params.x + 0.5;\n"
        "    float2 fromCenter = uv - 0.5;\n"
        "    c *= 1.0 - look.x * saturate(dot(fromCenter, fromCenter) * 2.2);\n"
        "    c += (frac(sin(dot(uv * 1000.0 + look.z, float2(12.9898, 78.233))) * 43758.5453) - 0.5) * look.y * 0.15;\n"
        "    return float4(saturate(c), 1);\n"
        "}\n";

    constexpr D3DFORMAT FORMAT_INTZ = static_cast<D3DFORMAT>(MAKEFOURCC('I', 'N', 'T', 'Z'));
    constexpr D3DFORMAT FORMAT_RESZ = static_cast<D3DFORMAT>(MAKEFOURCC('R', 'E', 'S', 'Z'));
    constexpr DWORD RESZ_CODE = 0x7FA05000;
    constexpr uintptr_t ADDR_FARCLIP = 0xCD7748;        // the world's far clip, yards
    constexpr float SSAO_PROJECTION = 0.625f;           // pixels per yard at 1 yard, per pixel of screen height
                                                        // (1 / (2 tan(fov / 2)), the camera's ~77 degrees)

    bool CheckSsaoSupport(IDirect3DDevice9* device)
    {
        if (s_ssaoChecked)
            return s_ssaoSupported;
        s_ssaoChecked = true;
        IDirect3D9* d3d = nullptr;
        if (FAILED(device->GetDirect3D(&d3d)) || !d3d)
            return false;
        D3DDISPLAYMODE mode = {};
        device->GetDisplayMode(0, &mode);
        D3DDEVICE_CREATION_PARAMETERS creation = {};
        device->GetCreationParameters(&creation);
        bool intz = SUCCEEDED(d3d->CheckDeviceFormat(creation.AdapterOrdinal, creation.DeviceType, mode.Format,
            D3DUSAGE_DEPTHSTENCIL, D3DRTYPE_TEXTURE, FORMAT_INTZ));
        bool resz = SUCCEEDED(d3d->CheckDeviceFormat(creation.AdapterOrdinal, creation.DeviceType, mode.Format,
            D3DUSAGE_RENDERTARGET, D3DRTYPE_SURFACE, FORMAT_RESZ));
        d3d->Release();
        s_reszSupported = resz;
        s_ssaoStatus = !intz ? 2 : 0;
        if (intz)
        {
            std::vector<DWORD> code = Compile(HLSL_SSAO_PS, "ps_3_0");
            std::vector<DWORD> blur = Compile(HLSL_SSAO_BLUR_PS, "ps_3_0");
            if (code.empty() || blur.empty() || FAILED(device->CreatePixelShader(code.data(), &s_ssaoShader))
                || FAILED(device->CreatePixelShader(blur.data(), &s_ssaoBlurShader)))
            {
                s_ssaoShader = nullptr;
                s_ssaoBlurShader = nullptr;
                s_ssaoStatus = 5;
            }
        }
        s_ssaoSupported = intz && s_ssaoShader && s_ssaoBlurShader;
        return s_ssaoSupported;
    }

    void SetView(IDirect3DTexture9* texture, UINT width, UINT height);

    // the scene's depth buffer, multisampled, into our INTZ texture (the drivers' RESZ: a point drawn with the
    // texture bound, then a magic point size)
    bool ResolveDepth(IDirect3DDevice9* device)
    {
        IDirect3DSurface9* depth = nullptr;
        if (FAILED(device->GetDepthStencilSurface(&depth)) || !depth)
            return false;
        D3DSURFACE_DESC desc = {};
        depth->GetDesc(&desc);
        bool own = depth == s_ownDepthSurface;
        depth->Release();
        if (own)
        {
            SetView(s_ownDepth, desc.Width, desc.Height);
            return true;
        }
        if (desc.MultiSampleType == D3DMULTISAMPLE_NONE)
        {
            s_ssaoStatus = 4;       // ours goes in place of it at the end of this frame (UseOwnDepth)
            return false;
        }
        if (!s_reszSupported)
        {
            s_ssaoStatus = 3;
            return false;
        }
        if (!s_depthCopy || s_depthCopyWidth != desc.Width || s_depthCopyHeight != desc.Height)
        {
            if (s_depthCopy)
                s_depthCopy->Release();
            if (s_aoSurface)
                s_aoSurface->Release();
            if (s_aoTexture)
                s_aoTexture->Release();
            s_depthCopy = nullptr;
            s_aoSurface = nullptr;
            s_aoTexture = nullptr;     // made again at the new size
            if (FAILED(device->CreateTexture(desc.Width, desc.Height, 1, D3DUSAGE_DEPTHSTENCIL, FORMAT_INTZ,
                D3DPOOL_DEFAULT, &s_depthCopy, nullptr)) || !s_depthCopy)
            {
                s_depthCopy = nullptr;
                s_ssaoStatus = 6;
                return false;
            }
            s_depthCopyWidth = desc.Width;
            s_depthCopyHeight = desc.Height;
        }

        s_setVertexShader(device, nullptr);
        s_setPixelShader(device, nullptr);
        s_setFVF(device, D3DFVF_XYZ);
        SetState(device, D3DRS_ZENABLE, FALSE);
        SetState(device, D3DRS_ZWRITEENABLE, FALSE);
        SetState(device, D3DRS_COLORWRITEENABLE, 0);
        s_setTexture(device, 0, s_depthCopy);
        const float point[3] = { 0.0f, 0.0f, 0.0f };
        device->DrawPrimitiveUP(D3DPT_POINTLIST, 1, point, sizeof(point));
        SetState(device, D3DRS_ZWRITEENABLE, TRUE);
        SetState(device, D3DRS_ZENABLE, TRUE);
        SetState(device, D3DRS_COLORWRITEENABLE, 0xF);
        SetState(device, D3DRS_POINTSIZE, RESZ_CODE);
        SetState(device, D3DRS_POINTSIZE, 0x3F800000);
        s_setTexture(device, 0, nullptr);
        SetView(s_depthCopy, s_depthCopyWidth, s_depthCopyHeight);
        return true;
    }

    // a new size of the depth the passes read: the occlusion texture made again
    void SetView(IDirect3DTexture9* texture, UINT width, UINT height)
    {
        if (width != s_viewWidth || height != s_viewHeight)
        {
            if (s_aoSurface)
                s_aoSurface->Release();
            if (s_aoTexture)
                s_aoTexture->Release();
            s_aoSurface = nullptr;
            s_aoTexture = nullptr;
        }
        s_depthView = texture;
        s_viewWidth = width;
        s_viewHeight = height;
    }

    float CVarNumber(const char* name, float fallback)
    {
        void* cvar = reinterpret_cast<void* (__cdecl*)(const char*)>(ADDR_CVAR_LOOKUP)(name);
        const char* value = cvar ? *reinterpret_cast<const char**>(static_cast<uint8_t*>(cvar) + CVAR_STRING_OFFSET) : nullptr;
        return value ? static_cast<float>(atof(value)) : fallback;
    }

    // once a frame, after the 3D scene, before the outline: the creases darkened
    void Ssao(IDirect3DDevice9* device)
    {
        if (!CVarInt(CV_SSAO))
        {
            if (s_ssaoStatus == 1)
                s_ssaoStatus = 0;
            return;
        }
        if (!s_depthReady)
            return;

        float nearClip = CVarNumber("nearclip", 0.2f);
        float farClip = *reinterpret_cast<float*>(ADDR_FARCLIP);
        float radius = CVarFloat(CV_SSAO_RADIUS);
        float strength = CVarFloat(CV_SSAO_STRENGTH);
        radius = radius < 0.3f ? 0.3f : (radius > 5.0f ? 5.0f : radius);
        strength = strength < 0.0f ? 0.0f : (strength > 2.0f ? 2.0f : strength);
        const float screen[4] = { 1.0f / s_viewWidth, 1.0f / s_viewHeight, nearClip > 0.01f ? nearClip : 0.2f,
            farClip > 10.0f ? farClip : 1000.0f };
        const float params[4] = { radius, strength, SSAO_PROJECTION * s_viewHeight, 0.0f };

        if (!s_aoTexture)
        {
            if (FAILED(device->CreateTexture(s_viewWidth, s_viewHeight, 1, D3DUSAGE_RENDERTARGET, D3DFMT_A8R8G8B8,
                D3DPOOL_DEFAULT, &s_aoTexture, nullptr)) || !s_aoTexture)
            {
                s_aoTexture = nullptr;
                s_ssaoStatus = 6;
                RestoreGx(device);
                return;
            }
            s_aoTexture->GetSurfaceLevel(0, &s_aoSurface);
        }

        FillQuad(s_viewWidth, s_viewHeight);
        s_setVertexShader(device, s_quadShader);
        s_setVertexDeclaration(device, s_quadDeclaration);
        s_setStreamSource(device, 0, s_quadBuffer, 0, sizeof(QuadVertex));
        s_setPsConstant(device, 0, screen, 1);
        s_setPsConstant(device, 1, params, 1);
        for (DWORD stage = 0; stage < 2; ++stage)
        {
            s_setSamplerState(device, stage, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
            s_setSamplerState(device, stage, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);
            s_setSamplerState(device, stage, D3DSAMP_MAGFILTER, D3DTEXF_POINT);
            s_setSamplerState(device, stage, D3DSAMP_MINFILTER, D3DTEXF_POINT);
            s_setSamplerState(device, stage, D3DSAMP_MIPFILTER, D3DTEXF_NONE);
            s_setSamplerState(device, stage, D3DSAMP_SRGBTEXTURE, FALSE);
        }
        SetSilhouetteStates(device);

        // 1. the raw occlusion into our texture (no depth buffer: it doesn't fit, and isn't needed)
        IDirect3DSurface9* renderTarget = nullptr;
        IDirect3DSurface9* depthStencil = nullptr;
        device->GetRenderTarget(0, &renderTarget);
        device->GetDepthStencilSurface(&depthStencil);
        // the target not taken: nothing drawn (on the screen it would be the raw occlusion)
        if (!s_aoSurface || FAILED(device->SetRenderTarget(0, s_aoSurface)))
        {
            if (renderTarget)
                renderTarget->Release();
            if (depthStencil)
                depthStencil->Release();
            s_ssaoStatus = 7;
            RestoreGx(device);
            return;
        }
        device->SetDepthStencilSurface(nullptr);
        device->Clear(0, nullptr, D3DCLEAR_TARGET, 0x00000000, 1.0f, 0);
        s_setPixelShader(device, s_ssaoShader);
        s_setTexture(device, 0, s_depthView);
        device->DrawPrimitive(D3DPT_TRIANGLESTRIP, 0, 2);
        device->SetRenderTarget(0, renderTarget);
        device->SetDepthStencilSurface(depthStencil);
        if (renderTarget)
            renderTarget->Release();
        if (depthStencil)
            depthStencil->Release();
        RestoreViewport(device);

        // 2. blurred onto the screen
        s_setPixelShader(device, s_ssaoBlurShader);
        s_setTexture(device, 0, s_aoTexture);
        s_setTexture(device, 1, s_depthView);
        SetState(device, D3DRS_ALPHABLENDENABLE, TRUE);
        SetState(device, D3DRS_SRCBLEND, D3DBLEND_SRCALPHA);
        SetState(device, D3DRS_DESTBLEND, D3DBLEND_INVSRCALPHA);
        SetState(device, D3DRS_BLENDOP, D3DBLENDOP_ADD);
        SetState(device, D3DRS_COLORWRITEENABLE, 0x7);
        device->DrawPrimitive(D3DPT_TRIANGLESTRIP, 0, 2);
        s_setTexture(device, 0, nullptr);       // not bound while they are no textures of Gx's
        s_setTexture(device, 1, nullptr);
        s_ssaoStatus = 1;
        RestoreGx(device);
    }

    // once a frame: the scene's depth copied when an effect needs it (SSAO, sun rays, depth of field)
    void PrepareDepth(IDirect3DDevice9* device)
    {
        s_depthReady = false;
        if (!CVarInt(CV_SSAO) && !CVarInt(CV_GODRAYS) && !CVarInt(CV_DOF) && !CVarInt(CV_SSR) && !CVarInt(CV_GROUND_FOG))
            return;
        if (!s_quadShader || !s_quadDeclaration || !EnsureQuadBuffer(device) || !CheckSsaoSupport(device))
            return;
        s_depthReady = ResolveDepth(device);
        RestoreGx(device);
    }

    // the screen (resolved if multisampled) into s_sceneCopy
    bool CopyScene(IDirect3DDevice9* device)
    {
        IDirect3DSurface9* renderTarget = nullptr;
        if (FAILED(device->GetRenderTarget(0, &renderTarget)) || !renderTarget)
            return false;
        D3DSURFACE_DESC desc = {};
        renderTarget->GetDesc(&desc);
        if (!s_sceneCopy || s_sceneCopyWidth != desc.Width || s_sceneCopyHeight != desc.Height)
        {
            if (s_sceneCopySurface)
                s_sceneCopySurface->Release();
            if (s_sceneCopy)
                s_sceneCopy->Release();
            s_sceneCopySurface = nullptr;
            s_sceneCopy = nullptr;
            if (FAILED(device->CreateTexture(desc.Width, desc.Height, 1, D3DUSAGE_RENDERTARGET, D3DFMT_X8R8G8B8,
                D3DPOOL_DEFAULT, &s_sceneCopy, nullptr)) || !s_sceneCopy)
            {
                s_sceneCopy = nullptr;
                renderTarget->Release();
                return false;
            }
            s_sceneCopy->GetSurfaceLevel(0, &s_sceneCopySurface);
            s_sceneCopyWidth = desc.Width;
            s_sceneCopyHeight = desc.Height;
        }
        HRESULT copied = device->StretchRect(renderTarget, nullptr, s_sceneCopySurface, nullptr, D3DTEXF_NONE);
        renderTarget->Release();
        return SUCCEEDED(copied);
    }

    // ---------------------------------------------------------------- bloom, sun rays, depth of field
    // s0 the scene (linear, a quarter size target: four bilinear taps = 16 pixels); c1.x mode: 0 as is, 1 the bright
    // part (c1.y threshold), 2 the sky only (s1 the depth: 1 there); c1.z the sky's gain
    const char HLSL_DOWN_PS[] =
        "sampler2D scene : register(s0);\n"
        "sampler2D depthTex : register(s1);\n"
        "float4 screen : register(c0);\n"
        "float4 params : register(c1);\n"
        "float4 main(float2 uv : TEXCOORD0) : COLOR\n"
        "{\n"
        "    float2 o = screen.xy;\n"
        "    float3 c = (tex2Dlod(scene, float4(uv + float2(-o.x, -o.y), 0, 0)).rgb + tex2Dlod(scene, float4(uv + float2(o.x, -o.y), 0, 0)).rgb\n"
        "        + tex2Dlod(scene, float4(uv + float2(-o.x, o.y), 0, 0)).rgb + tex2Dlod(scene, float4(uv + float2(o.x, o.y), 0, 0)).rgb) * 0.25;\n"
        "    if (params.x == 1)\n"
        "    {\n"
        "        float luma = dot(c, float3(0.299, 0.587, 0.114));\n"
        "        c *= saturate((luma - params.y) / max(1.0 - params.y, 0.01));\n"
        "    }\n"
        "    else if (params.x == 2)\n"
        "        c *= step(0.99999, tex2Dlod(depthTex, float4(uv, 0, 0)).r) * params.z;\n"
        "    return float4(c, 1);\n"
        "}\n";

    // 9 taps along c1.xy (in texels of the target)
    const char HLSL_BLUR_PS[] =
        "sampler2D source : register(s0);\n"
        "float4 screen : register(c0);\n"
        "float4 params : register(c1);\n"
        "float4 main(float2 uv : TEXCOORD0) : COLOR\n"
        "{\n"
        "    const float w[5] = { 0.2270270, 0.1945946, 0.1216216, 0.0540541, 0.0162162 };\n"
        "    float2 dir = params.xy * screen.xy;\n"
        "    float3 c = tex2Dlod(source, float4(uv, 0, 0)).rgb * w[0];\n"
        "    [unroll] for (int i = 1; i < 5; ++i)\n"
        "        c += (tex2Dlod(source, float4(uv + dir * i, 0, 0)).rgb + tex2Dlod(source, float4(uv - dir * i, 0, 0)).rgb) * w[i];\n"
        "    return float4(c, 1);\n"
        "}\n";

    // the sky's light smeared toward the sun: c1.xy the sun's uv, c1.z the length (0..1 of the way)
    const char HLSL_RADIAL_PS[] =
        "sampler2D source : register(s0);\n"
        "float4 params : register(c1);\n"
        "float4 main(float2 uv : TEXCOORD0) : COLOR\n"
        "{\n"
        "    float2 delta = (params.xy - uv) * params.z / 32.0;\n"
        "    float3 c = 0;\n"
        "    float decay = 1.0;\n"
        "    float2 at = uv;\n"
        "    [unroll] for (int i = 0; i < 32; ++i)\n"
        "    {\n"
        "        c += tex2Dlod(source, float4(at, 0, 0)).rgb * decay;\n"
        "        decay *= 0.96;\n"
        "        at += delta;\n"
        "    }\n"
        "    return float4(c / 16.0, 1);\n"
        "}\n";

    // added onto the screen: s0 times c1.rgb
    const char HLSL_ADD_PS[] =
        "sampler2D source : register(s0);\n"
        "float4 params : register(c1);\n"
        "float4 main(float2 uv : TEXCOORD0) : COLOR { return float4(tex2Dlod(source, float4(uv, 0, 0)).rgb * params.rgb, 1); }\n";

    // the far blur: s0 the scene, s1 the blurred scene (a quarter size), s2 the depth. c0 texel.xy, near, far;
    // c1 focus (yards), the distance to full blur, strength
    const char HLSL_DOF_PS[] =
        "sampler2D scene : register(s0);\n"
        "sampler2D blurred : register(s1);\n"
        "sampler2D depthTex : register(s2);\n"
        "float4 screen : register(c0);\n"
        "float4 params : register(c1);\n"
        "float Linear(float d) { return screen.z * screen.w / (screen.w - d * (screen.w - screen.z)); }\n"
        "float4 main(float2 uv : TEXCOORD0) : COLOR\n"
        "{\n"
        "    float d = tex2Dlod(depthTex, float4(uv, 0, 0)).r;\n"
        "    float amount = d >= 0.99999 ? 1.0 : saturate((Linear(d) - params.x) / params.y);\n"
        "    float3 sharp = tex2Dlod(scene, float4(uv, 0, 0)).rgb;\n"
        "    float3 soft = tex2Dlod(blurred, float4(uv, 0, 0)).rgb;\n"
        "    return float4(lerp(sharp, soft, amount * params.z), 1);\n"
        "}\n";

    bool CreatePostShaders(IDirect3DDevice9* device)
    {
        if (s_postChecked)
            return s_downShader && s_blurShader && s_radialShader && s_addShader && s_dofShader;
        s_postChecked = true;
        const char* sources[] = { HLSL_DOWN_PS, HLSL_BLUR_PS, HLSL_RADIAL_PS, HLSL_ADD_PS, HLSL_DOF_PS };
        IDirect3DPixelShader9** shaders[] = { &s_downShader, &s_blurShader, &s_radialShader, &s_addShader, &s_dofShader };
        for (int i = 0; i < 5; ++i)
        {
            std::vector<DWORD> code = Compile(sources[i], "ps_3_0");
            if (code.empty() || FAILED(device->CreatePixelShader(code.data(), shaders[i])))
                *shaders[i] = nullptr;
        }
        return s_downShader && s_blurShader && s_radialShader && s_addShader && s_dofShader;
    }

    bool EnsureSmall(UINT width, UINT height, IDirect3DDevice9* device)
    {
        width = width / 4 > 1 ? width / 4 : 1;
        height = height / 4 > 1 ? height / 4 : 1;
        if (s_small[0] && s_smallWidth == width && s_smallHeight == height)
            return true;
        ReleaseSmall();
        for (int i = 0; i < 3; ++i)
        {
            if (FAILED(device->CreateTexture(width, height, 1, D3DUSAGE_RENDERTARGET, D3DFMT_A8R8G8B8, D3DPOOL_DEFAULT,
                &s_small[i], nullptr)) || !s_small[i])
            {
                s_small[i] = nullptr;
                ReleaseSmall();
                return false;
            }
            s_small[i]->GetSurfaceLevel(0, &s_smallSurface[i]);
        }
        s_smallWidth = width;
        s_smallHeight = height;
        return true;
    }

    void BindTexture(IDirect3DDevice9* device, DWORD stage, IDirect3DBaseTexture9* texture, bool linear)
    {
        s_setTexture(device, stage, texture);
        s_setSamplerState(device, stage, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
        s_setSamplerState(device, stage, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);
        s_setSamplerState(device, stage, D3DSAMP_MAGFILTER, linear ? D3DTEXF_LINEAR : D3DTEXF_POINT);
        s_setSamplerState(device, stage, D3DSAMP_MINFILTER, linear ? D3DTEXF_LINEAR : D3DTEXF_POINT);
        s_setSamplerState(device, stage, D3DSAMP_MIPFILTER, D3DTEXF_NONE);
        s_setSamplerState(device, stage, D3DSAMP_SRGBTEXTURE, FALSE);
    }

    // one full-screen pass of the shader into a target (nullptr: the screen, as it is set); c0 is the source's texel
    void Pass(IDirect3DDevice9* device, IDirect3DSurface9* target, UINT width, UINT height, IDirect3DPixelShader9* shader,
        const float source[4], const float params[4])
    {
        IDirect3DSurface9* renderTarget = nullptr;
        IDirect3DSurface9* depthStencil = nullptr;
        if (target)
        {
            device->GetRenderTarget(0, &renderTarget);
            device->GetDepthStencilSurface(&depthStencil);
            if (FAILED(device->SetRenderTarget(0, target)))
            {
                if (renderTarget)
                    renderTarget->Release();
                if (depthStencil)
                    depthStencil->Release();
                return;
            }
            device->SetDepthStencilSurface(nullptr);
        }
        FillQuad(width, height);
        s_setPixelShader(device, shader);
        s_setPsConstant(device, 0, source, 1);
        s_setPsConstant(device, 1, params, 1);
        device->DrawPrimitive(D3DPT_TRIANGLESTRIP, 0, 2);
        if (target)
        {
            device->SetRenderTarget(0, renderTarget);
            device->SetDepthStencilSurface(depthStencil);
            if (renderTarget)
                renderTarget->Release();
            if (depthStencil)
                depthStencil->Release();
            RestoreViewport(device);
        }
    }

    // a quarter size target blurred both ways (through s_small[2])
    void BlurSmall(IDirect3DDevice9* device, int index)
    {
        const float texel[4] = { 1.0f / s_smallWidth, 1.0f / s_smallHeight, 0.0f, 0.0f };
        const float horizontal[4] = { 1.0f, 0.0f, 0.0f, 0.0f };
        const float vertical[4] = { 0.0f, 1.0f, 0.0f, 0.0f };
        BindTexture(device, 0, s_small[index], true);
        Pass(device, s_smallSurface[2], s_smallWidth, s_smallHeight, s_blurShader, texel, horizontal);
        BindTexture(device, 0, s_small[2], true);
        Pass(device, s_smallSurface[index], s_smallWidth, s_smallHeight, s_blurShader, texel, vertical);
    }

    void AddOnto(IDirect3DDevice9* device, int index, float r, float g, float b)
    {
        const float none[4] = {};
        const float tint[4] = { r, g, b, 0.0f };
        BindTexture(device, 0, s_small[index], true);
        SetState(device, D3DRS_ALPHABLENDENABLE, TRUE);
        SetState(device, D3DRS_SRCBLEND, D3DBLEND_ONE);
        SetState(device, D3DRS_DESTBLEND, D3DBLEND_ONE);
        SetState(device, D3DRS_BLENDOP, D3DBLENDOP_ADD);
        Pass(device, nullptr, s_sceneCopyWidth, s_sceneCopyHeight, s_addShader, none, tint);
        SetState(device, D3DRS_ALPHABLENDENABLE, FALSE);
    }

    float Clamp(float value, float low, float high) { return value < low ? low : (value > high ? high : value); }

    // the sun on the screen: the zone light's direction (0xD38B00 + 0x18, the light's travel) seen by the camera
    // ([[0xB7436C] + 0x7E20]: +0x8 position, +0x14 3x3 facing - forward, left, up -, +0x40 fov, +0x44 aspect)
    bool SunOnScreen(float& u, float& v, float& visibility)
    {
        uint8_t* world = *reinterpret_cast<uint8_t**>(0xB7436C);
        uint8_t* camera = world ? *reinterpret_cast<uint8_t**>(world + 0x7E20) : nullptr;
        if (!camera)
            return false;
        const float* light = reinterpret_cast<const float*>(0xD38B00 + 0x18);
        float sign = CVarInt(CV_GODRAYS_FLIP) ? 1.0f : -1.0f;
        float sun[3] = { light[0] * sign, light[1] * sign, light[2] * sign };
        const float* facing = reinterpret_cast<const float*>(camera + 0x14);
        float forward = sun[0] * facing[0] + sun[1] * facing[1] + sun[2] * facing[2];
        float left = sun[0] * facing[3] + sun[1] * facing[4] + sun[2] * facing[5];
        float up = sun[0] * facing[6] + sun[1] * facing[7] + sun[2] * facing[8];
        float fov = *reinterpret_cast<const float*>(camera + 0x40);
        float aspect = *reinterpret_cast<const float*>(camera + 0x44);
        s_sunScreen[2] = forward > 0.0f ? 1.0f : 0.0f;
        if (forward <= 0.05f || fov <= 0.1f || aspect <= 0.1f)
            return false;
        float halfHeight = tanf(fov * 0.5f);
        float x = -left / forward / (halfHeight * aspect);
        float y = up / forward / halfHeight;
        u = 0.5f + 0.5f * x;
        v = 0.5f - 0.5f * y;
        // fading out as it leaves the screen
        float outside = (fabsf(x) > fabsf(y) ? fabsf(x) : fabsf(y)) - 1.0f;
        visibility = Clamp(1.0f - outside, 0.0f, 1.0f);
        return visibility > 0.0f;
    }

    // once a frame, after SSAO: depth of field, bloom, sun rays
    void PostEffects(IDirect3DDevice9* device)
    {
        bool dof = CVarInt(CV_DOF) && s_depthReady;
        bool bloom = CVarInt(CV_BLOOM) != 0;
        bool rays = CVarInt(CV_GODRAYS) && s_depthReady;
        if (!dof && !bloom && !rays)
            return;
        if (!s_quadShader || !s_quadDeclaration || !EnsureQuadBuffer(device) || !CreatePostShaders(device) || !CopyScene(device)
            || !EnsureSmall(s_sceneCopyWidth, s_sceneCopyHeight, device))
            return;

        s_setVertexShader(device, s_quadShader);
        s_setVertexDeclaration(device, s_quadDeclaration);
        s_setStreamSource(device, 0, s_quadBuffer, 0, sizeof(QuadVertex));
        SetSilhouetteStates(device);
        SetState(device, D3DRS_COLORWRITEENABLE, 0x7);

        const float sceneTexel[4] = { 1.0f / s_sceneCopyWidth, 1.0f / s_sceneCopyHeight, 0.0f, 0.0f };
        float nearClip = CVarNumber("nearclip", 0.2f);
        float farClip = *reinterpret_cast<float*>(ADDR_FARCLIP);
        const float depthScreen[4] = { 1.0f / s_sceneCopyWidth, 1.0f / s_sceneCopyHeight, nearClip > 0.01f ? nearClip : 0.2f,
            farClip > 10.0f ? farClip : 1000.0f };

        if (dof)
        {
            // the focus: the depth at the middle of the screen (the character, mostly) - read on the CPU would
            // stall; the camera's distance to the player instead
            float focus = 10.0f;
            uint8_t* world = *reinterpret_cast<uint8_t**>(0xB7436C);
            uint8_t* camera = world ? *reinterpret_cast<uint8_t**>(world + 0x7E20) : nullptr;
            CGObject* player = FindUnit(reinterpret_cast<WoWGUID (__cdecl*)()>(ADDR_ACTIVE_PLAYER)());
            if (camera && player)
            {
                Position at = GetPosition(player);
                const float* position = reinterpret_cast<const float*>(camera + 0x8);
                float dx = position[0] - at.X, dy = position[1] - at.Y, dz = position[2] - at.Z;
                focus = sqrtf(dx * dx + dy * dy + dz * dz) + 5.0f;
            }
            const float mode[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
            BindTexture(device, 0, s_sceneCopy, true);
            Pass(device, s_smallSurface[0], s_smallWidth, s_smallHeight, s_downShader, sceneTexel, mode);
            BlurSmall(device, 0);
            BlurSmall(device, 0);
            const float params[4] = { focus, Clamp(CVarFloat(CV_DOF_DISTANCE), 5.0f, 300.0f), Clamp(CVarFloat(CV_DOF_STRENGTH), 0.0f, 1.0f), 0.0f };
            BindTexture(device, 0, s_sceneCopy, false);
            BindTexture(device, 1, s_small[0], true);
            BindTexture(device, 2, s_depthView, false);
            Pass(device, nullptr, s_sceneCopyWidth, s_sceneCopyHeight, s_dofShader, depthScreen, params);
        }
        if (bloom)
        {
            const float mode[4] = { 1.0f, Clamp(CVarFloat(CV_BLOOM_THRESHOLD), 0.3f, 1.0f), 0.0f, 0.0f };
            BindTexture(device, 0, s_sceneCopy, true);
            Pass(device, s_smallSurface[1], s_smallWidth, s_smallHeight, s_downShader, sceneTexel, mode);
            BlurSmall(device, 1);
            BlurSmall(device, 1);
            float strength = Clamp(CVarFloat(CV_BLOOM_STRENGTH), 0.0f, 2.0f);
            AddOnto(device, 1, strength, strength, strength);
        }
        float u = 0.0f, v = 0.0f, visibility = 0.0f;
        if (rays && SunOnScreen(u, v, visibility))
        {
            const float mode[4] = { 2.0f, 0.0f, 1.0f, 0.0f };
            BindTexture(device, 0, s_sceneCopy, true);
            BindTexture(device, 1, s_depthView, false);
            Pass(device, s_smallSurface[1], s_smallWidth, s_smallHeight, s_downShader, sceneTexel, mode);
            const float radial[4] = { u, v, 0.9f, 0.0f };
            const float none[4] = {};
            BindTexture(device, 0, s_small[1], true);
            Pass(device, s_smallSurface[0], s_smallWidth, s_smallHeight, s_radialShader, none, radial);
            float strength = Clamp(CVarFloat(CV_GODRAYS_STRENGTH), 0.0f, 2.0f) * visibility * 0.5f;
            AddOnto(device, 0, strength, strength * 0.95f, strength * 0.85f);
        }
        s_sunScreen[0] = u;
        s_sunScreen[1] = v;
        s_sunScreen[3] = visibility;
        for (DWORD stage = 0; stage < SHADOW_STAGES; ++stage)
            s_setTexture(device, stage, nullptr);
        RestoreGx(device);
    }

    // ---------------------------------------------------------------- water reflections (SSR)
    // For a water pixel: its point (the camera, the view ray, the linear depth - the water's own, written by
    // DrawWater), the view ray mirrored by the flat surface, marched until it goes behind the scene's depth: the
    // color there; the sky if it only met sky. Fresnel: strong at grazing angles. s0 the scene, s1 the depth,
    // s2 the water mask; c0 texel.xy, near, far; c1 strength, the longest ray; c2..c4 the camera's forward, left,
    // up; c5 its position; c6 tan(fov / 2) * aspect, tan(fov / 2); c7 the sun's direction (toward it), the time.
    // c1.z the ripples, c1.w the glint
    const char HLSL_SSR_PS[] =
        "sampler2D scene : register(s0);\n"
        "sampler2D depthTex : register(s1);\n"
        "sampler2D water : register(s2);\n"
        "float4 screen : register(c0);\n"
        "float4 params : register(c1);\n"
        "float4 forward : register(c2);\n"
        "float4 left : register(c3);\n"
        "float4 up : register(c4);\n"
        "float4 eye : register(c5);\n"
        "float4 fov : register(c6);\n"
        "float4 sun : register(c7);\n"
        "float Linear(float d) { return screen.z * screen.w / (screen.w - d * (screen.w - screen.z)); }\n"
        "// the surface's slope: a few waves running over the world's x, y\n"
        "float2 Slope(float2 p, float t)\n"
        "{\n"
        "    float2 s = 0;\n"
        "    s += float2(0.8, 0.6) * cos(dot(p, float2(0.8, 0.6)) * 0.45 + t * 0.9) * 0.5;\n"
        "    s += float2(-0.5, 0.86) * cos(dot(p, float2(-0.5, 0.86)) * 0.7 + t * 1.2) * 0.3;\n"
        "    s += float2(0.2, -0.98) * cos(dot(p, float2(0.2, -0.98)) * 1.1 + t * 1.5) * 0.2;\n"
        "    return s;\n"
        "}\n"
        "float2 Project(float3 p, out float z)\n"
        "{\n"
        "    float3 rel = p - eye.xyz;\n"
        "    z = dot(rel, forward.xyz);\n"
        "    float x = -dot(rel, left.xyz) / (z * fov.x);\n"
        "    float y = dot(rel, up.xyz) / (z * fov.y);\n"
        "    return float2(0.5 + 0.5 * x, 0.5 - 0.5 * y);\n"
        "}\n"
        "float4 main(float2 uv : TEXCOORD0) : COLOR\n"
        "{\n"
        "    clip(tex2Dlod(water, float4(uv, 0, 0)).r - 0.5);\n"
        "    float z = Linear(tex2Dlod(depthTex, float4(uv, 0, 0)).r);\n"
        "    float2 ndc = float2(uv.x * 2 - 1, 1 - uv.y * 2);\n"
        "    float3 ray = forward.xyz - left.xyz * ndc.x * fov.x + up.xyz * ndc.y * fov.y;\n"
        "    float3 surface = eye.xyz + ray * z;\n"
        "    float3 view = normalize(ray);\n"
        "    // the ripples fade with the distance (far off they'd only be noise)\n"
        "    float ripple = params.z * saturate(1.0 - z / 80.0);\n"
        "    float3 normal = normalize(float3(-Slope(surface.xy, sun.w) * ripple, 1.0));\n"
        "    float3 mirrored = reflect(view, normal);\n"
        "    mirrored.z = abs(mirrored.z);\n"
        "    float3 color = 0;\n"
        "    float found = 0;\n"
        "    float t = 0.5;\n"
        "    [loop] for (int i = 0; i < 48; ++i)\n"
        "    {\n"
        "        float rayZ;\n"
        "        float2 at = Project(surface + mirrored * t, rayZ);\n"
        "        if (rayZ <= screen.z || at.x < 0 || at.x > 1 || at.y < 0 || at.y > 1)\n"
        "            break;\n"
        "        float d = tex2Dlod(depthTex, float4(at, 0, 0)).r;\n"
        "        if (d >= 0.99999)\n"
        "        {\n"
        "            color = tex2Dlod(scene, float4(at, 0, 0)).rgb;\n"
        "            found = 0.5;\n"
        "        }\n"
        "        else\n"
        "        {\n"
        "            float sceneZ = Linear(d);\n"
        "            if (sceneZ < rayZ && rayZ - sceneZ < t * 0.2 + 0.5)\n"
        "            {\n"
        "                color = tex2Dlod(scene, float4(at, 0, 0)).rgb;\n"
        "                found = 1;\n"
        "                break;\n"
        "            }\n"
        "        }\n"
        "        t *= 1.15;\n"
        "        if (t > params.y)\n"
        "            break;\n"
        "    }\n"
        "    float fresnel = 0.05 + 0.95 * pow(1.0 - abs(view.z), 5.0);\n"
        "    float glint = sun.z > 0.05 ? pow(saturate(dot(mirrored, sun.xyz)), 600.0) * params.w * saturate(1.0 - z / 150.0) : 0.0;\n"
        "    float alpha = min(found * fresnel * params.x, 0.6);\n"
        "    // the glint added on top: premultiplied into the blended color\n"
        "    float3 result = color + glint / max(alpha + glint, 0.001);\n"
        "    return float4(result, saturate(alpha + glint));\n"
        "}\n";

    // the water mask: the size and the antialiasing of the outline's (they fit the scene's depth buffer)
    bool EnsureWaterMask(IDirect3DDevice9* device)
    {
        if (!CVarInt(CV_SSR) || !s_mask || !CanDepthTest())
        {
            ReleaseWaterMask();
            return false;
        }
        if (s_waterMask && s_waterMaskWidth == s_maskWidth && s_waterMaskHeight == s_maskHeight
            && (s_waterMaskMultisampled != nullptr) == (s_maskSamples != D3DMULTISAMPLE_NONE))
            return true;
        ReleaseWaterMask();
        if (s_maskSamples != D3DMULTISAMPLE_NONE && FAILED(device->CreateRenderTarget(s_maskWidth, s_maskHeight,
            D3DFMT_A8R8G8B8, s_maskSamples, s_maskQuality, FALSE, &s_waterMaskMultisampled, nullptr)))
        {
            s_waterMaskMultisampled = nullptr;
            return false;
        }
        if (FAILED(device->CreateTexture(s_maskWidth, s_maskHeight, 1, D3DUSAGE_RENDERTARGET, D3DFMT_A8R8G8B8,
            D3DPOOL_DEFAULT, &s_waterMask, nullptr)) || !s_waterMask)
        {
            s_waterMask = nullptr;
            ReleaseWaterMask();
            return false;
        }
        s_waterMask->GetSurfaceLevel(0, &s_waterMaskSurface);
        s_waterMaskWidth = s_maskWidth;
        s_waterMaskHeight = s_maskHeight;
        s_waterDirty = true;
        return s_waterMaskSurface != nullptr;
    }

    void ClearWaterMask(IDirect3DDevice9* device)
    {
        if (!s_waterDirty || !s_waterMaskSurface)
            return;
        IDirect3DSurface9* renderTarget = nullptr;
        IDirect3DSurface9* depthStencil = nullptr;
        device->GetRenderTarget(0, &renderTarget);
        device->GetDepthStencilSurface(&depthStencil);
        device->SetDepthStencilSurface(nullptr);
        device->SetRenderTarget(0, s_waterMaskSurface);
        device->Clear(0, nullptr, D3DCLEAR_TARGET, 0, 1.0f, 0);
        if (s_waterMaskMultisampled)
        {
            device->SetRenderTarget(0, s_waterMaskMultisampled);
            device->Clear(0, nullptr, D3DCLEAR_TARGET, 0, 1.0f, 0);
        }
        device->SetRenderTarget(0, renderTarget);
        device->SetDepthStencilSurface(depthStencil);
        if (renderTarget)
            renderTarget->Release();
        if (depthStencil)
            depthStencil->Release();
        RestoreViewport(device);
        s_waterDirty = false;
    }

    // once a frame, after SSAO: the reflections drawn over the water
    void Reflections(IDirect3DDevice9* device)
    {
        s_waterDraws = s_frameWaterDraws;
        s_frameWaterDraws = 0;
        if (!CVarInt(CV_SSR) || !s_depthReady || !s_waterMaskSurface || !s_waterDraws)
            return;
        if (!s_ssrChecked)
        {
            s_ssrChecked = true;
            std::vector<DWORD> code = Compile(HLSL_SSR_PS, "ps_3_0");
            if (code.empty() || FAILED(device->CreatePixelShader(code.data(), &s_ssrShader)))
                s_ssrShader = nullptr;
        }
        uint8_t* world = *reinterpret_cast<uint8_t**>(0xB7436C);
        uint8_t* camera = world ? *reinterpret_cast<uint8_t**>(world + 0x7E20) : nullptr;
        if (!s_ssrShader || !camera || !CopyScene(device))
            return;
        if (s_waterMaskMultisampled)
            device->StretchRect(s_waterMaskMultisampled, nullptr, s_waterMaskSurface, nullptr, D3DTEXF_NONE);

        const float* position = reinterpret_cast<const float*>(camera + 0x8);
        const float* facing = reinterpret_cast<const float*>(camera + 0x14);
        float fov = *reinterpret_cast<const float*>(camera + 0x40);
        float aspect = *reinterpret_cast<const float*>(camera + 0x44);
        float halfHeight = tanf((fov > 0.1f ? fov : 1.0f) * 0.5f);
        float nearClip = CVarNumber("nearclip", 0.2f);
        float farClip = *reinterpret_cast<float*>(ADDR_FARCLIP);
        // the sun: toward it, as the sun rays take it (the light's travel reversed, godRaysFlip)
        const float* light = reinterpret_cast<const float*>(0xD38B00 + 0x18);
        float sign = CVarInt(CV_GODRAYS_FLIP) ? 1.0f : -1.0f;
        float sunLength = sqrtf(light[0] * light[0] + light[1] * light[1] + light[2] * light[2]);
        if (sunLength < 0.001f)
            sunLength = 1.0f;
        const float constants[8][4] = {
            { 1.0f / s_sceneCopyWidth, 1.0f / s_sceneCopyHeight, nearClip > 0.01f ? nearClip : 0.2f, farClip > 10.0f ? farClip : 1000.0f },
            { Clamp(CVarFloat(CV_SSR_STRENGTH), 0.0f, 1.0f), 400.0f, Clamp(CVarFloat(CV_SSR_RIPPLE), 0.0f, 1.0f) * 0.15f,
                Clamp(CVarFloat(CV_SSR_SUN), 0.0f, 2.0f) },
            { facing[0], facing[1], facing[2], 0.0f },
            { facing[3], facing[4], facing[5], 0.0f },
            { facing[6], facing[7], facing[8], 0.0f },
            { position[0], position[1], position[2], 0.0f },
            { halfHeight * (aspect > 0.1f ? aspect : 1.0f), halfHeight, 0.0f, 0.0f },
            { light[0] * sign / sunLength, light[1] * sign / sunLength, light[2] * sign / sunLength,
                static_cast<float>(GetTickCount() % 600000) / 1000.0f },
        };

        FillQuad(s_sceneCopyWidth, s_sceneCopyHeight);
        s_setVertexShader(device, s_quadShader);
        s_setVertexDeclaration(device, s_quadDeclaration);
        s_setStreamSource(device, 0, s_quadBuffer, 0, sizeof(QuadVertex));
        s_setPixelShader(device, s_ssrShader);
        s_setPsConstant(device, 0, &constants[0][0], 8);
        BindTexture(device, 0, s_sceneCopy, true);
        BindTexture(device, 1, s_depthView, false);
        BindTexture(device, 2, s_waterMask, false);
        SetSilhouetteStates(device);
        SetState(device, D3DRS_ALPHABLENDENABLE, TRUE);
        SetState(device, D3DRS_SRCBLEND, D3DBLEND_SRCALPHA);
        SetState(device, D3DRS_DESTBLEND, D3DBLEND_INVSRCALPHA);
        SetState(device, D3DRS_BLENDOP, D3DBLENDOP_ADD);
        SetState(device, D3DRS_COLORWRITEENABLE, 0x7);
        device->DrawPrimitive(D3DPT_TRIANGLESTRIP, 0, 2);
        for (DWORD stage = 0; stage < SHADOW_STAGES; ++stage)
            s_setTexture(device, stage, nullptr);
        RestoreGx(device);
    }

    // ---------------------------------------------------------------- ground fog, FXAA
    // fog low on the ground: the pixel's world point (as SSR), thicker with the distance and below the top (the
    // player's feet + the height). c0 texel.xy, near, far; c1 density, the top's z, the height; c2..c6 the camera
    // (as SSR); c7 the zone's fog color
    const char HLSL_GROUND_FOG_PS[] =
        "sampler2D depthTex : register(s0);\n"
        "float4 screen : register(c0);\n"
        "float4 params : register(c1);\n"
        "float4 forward : register(c2);\n"
        "float4 left : register(c3);\n"
        "float4 up : register(c4);\n"
        "float4 eye : register(c5);\n"
        "float4 fov : register(c6);\n"
        "float4 fogColor : register(c7);\n"
        "float Linear(float d) { return screen.z * screen.w / (screen.w - d * (screen.w - screen.z)); }\n"
        "float4 main(float2 uv : TEXCOORD0) : COLOR\n"
        "{\n"
        "    float d = tex2Dlod(depthTex, float4(uv, 0, 0)).r;\n"
        "    clip(0.99999 - d);\n"
        "    float z = Linear(d);\n"
        "    float2 ndc = float2(uv.x * 2 - 1, 1 - uv.y * 2);\n"
        "    float3 ray = forward.xyz - left.xyz * ndc.x * fov.x + up.xyz * ndc.y * fov.y;\n"
        "    float3 world = eye.xyz + ray * z;\n"
        "    float below = saturate((params.y - world.z) / max(params.z, 0.5));\n"
        "    float amount = (1.0 - exp(-length(ray * z) * params.x * 0.02)) * below;\n"
        "    return float4(fogColor.rgb, saturate(amount));\n"
        "}\n";

    // FXAA (the console variant): the edge's direction from the luma around, a blur along it
    const char HLSL_FXAA_PS[] =
        "sampler2D scene : register(s0);\n"
        "float4 screen : register(c0);\n"
        "float3 At(float2 uv) { return tex2Dlod(scene, float4(uv, 0, 0)).rgb; }\n"
        "float Luma(float3 c) { return dot(c, float3(0.299, 0.587, 0.114)); }\n"
        "float4 main(float2 uv : TEXCOORD0) : COLOR\n"
        "{\n"
        "    float2 t = screen.xy;\n"
        "    float nw = Luma(At(uv + float2(-1, -1) * t)), ne = Luma(At(uv + float2(1, -1) * t));\n"
        "    float sw = Luma(At(uv + float2(-1, 1) * t)), se = Luma(At(uv + float2(1, 1) * t));\n"
        "    float3 middle = At(uv);\n"
        "    float m = Luma(middle);\n"
        "    float lumaMin = min(m, min(min(nw, ne), min(sw, se)));\n"
        "    float lumaMax = max(m, max(max(nw, ne), max(sw, se)));\n"
        "    if (lumaMax - lumaMin < max(0.0312, lumaMax * 0.125))\n"
        "        return float4(middle, 1);\n"
        "    float2 dir = float2(-((nw + ne) - (sw + se)), (nw + sw) - (ne + se));\n"
        "    float reduce = max((nw + ne + sw + se) * 0.03125, 0.0078125);\n"
        "    dir = clamp(dir / (min(abs(dir.x), abs(dir.y)) + reduce), -8.0, 8.0) * t;\n"
        "    float3 a = 0.5 * (At(uv + dir * (1.0 / 3.0 - 0.5)) + At(uv + dir * (2.0 / 3.0 - 0.5)));\n"
        "    float3 b = a * 0.5 + 0.25 * (At(uv - dir * 0.5) + At(uv + dir * 0.5));\n"
        "    float lb = Luma(b);\n"
        "    return float4((lb < lumaMin || lb > lumaMax) ? a : b, 1);\n"
        "}\n";

    IDirect3DPixelShader9* s_groundFogShader = nullptr;
    IDirect3DPixelShader9* s_fxaaShader = nullptr;
    bool s_groundFogChecked = false, s_fxaaChecked = false;

    IDirect3DPixelShader9* CompileOnce(IDirect3DDevice9* device, const char* source, IDirect3DPixelShader9*& shader, bool& checked)
    {
        if (!checked)
        {
            checked = true;
            std::vector<DWORD> code = Compile(source, "ps_3_0");
            if (code.empty() || FAILED(device->CreatePixelShader(code.data(), &shader)))
                shader = nullptr;
        }
        return shader;
    }

    // the camera's constants c2 .. c6 (as SSR), false without a camera
    bool CameraConstants(float constants[5][4])
    {
        uint8_t* world = *reinterpret_cast<uint8_t**>(0xB7436C);
        uint8_t* camera = world ? *reinterpret_cast<uint8_t**>(world + 0x7E20) : nullptr;
        if (!camera)
            return false;
        const float* position = reinterpret_cast<const float*>(camera + 0x8);
        const float* facing = reinterpret_cast<const float*>(camera + 0x14);
        float fov = *reinterpret_cast<const float*>(camera + 0x40);
        float aspect = *reinterpret_cast<const float*>(camera + 0x44);
        float halfHeight = tanf((fov > 0.1f ? fov : 1.0f) * 0.5f);
        for (int row = 0; row < 3; ++row)
        {
            constants[row][0] = facing[row * 3];
            constants[row][1] = facing[row * 3 + 1];
            constants[row][2] = facing[row * 3 + 2];
            constants[row][3] = 0.0f;
        }
        constants[3][0] = position[0];
        constants[3][1] = position[1];
        constants[3][2] = position[2];
        constants[3][3] = 0.0f;
        constants[4][0] = halfHeight * (aspect > 0.1f ? aspect : 1.0f);
        constants[4][1] = halfHeight;
        constants[4][2] = constants[4][3] = 0.0f;
        return true;
    }

    // once a frame, after SSAO
    void GroundFog(IDirect3DDevice9* device)
    {
        if (!CVarInt(CV_GROUND_FOG) || !s_depthReady || !CompileOnce(device, HLSL_GROUND_FOG_PS, s_groundFogShader, s_groundFogChecked))
            return;
        CGObject* player = FindUnit(reinterpret_cast<WoWGUID (__cdecl*)()>(ADDR_ACTIVE_PLAYER)());
        float camera[5][4];
        if (!player || !CameraConstants(camera))
            return;
        float height = Clamp(CVarFloat(CV_GROUND_FOG_HEIGHT), 0.0f, 30.0f);
        float nearClip = CVarNumber("nearclip", 0.2f);
        float farClip = *reinterpret_cast<float*>(ADDR_FARCLIP);
        // the zone's fog color: the light's result, bytes b, g, r at +0x8C
        const uint8_t* fog = reinterpret_cast<const uint8_t*>(0xD38B00 + 0x8C);
        float constants[8][4] = {
            { 1.0f / s_viewWidth, 1.0f / s_viewHeight, nearClip > 0.01f ? nearClip : 0.2f, farClip > 10.0f ? farClip : 1000.0f },
            { Clamp(CVarFloat(CV_GROUND_FOG_DENSITY), 0.0f, 1.0f), GetPosition(player).Z + height, height > 0.5f ? height : 0.5f, 0.0f },
        };
        memcpy(constants[2], camera, sizeof(camera));
        constants[7][0] = fog[2] / 255.0f;
        constants[7][1] = fog[1] / 255.0f;
        constants[7][2] = fog[0] / 255.0f;
        constants[7][3] = 1.0f;

        FillQuad(s_viewWidth, s_viewHeight);
        s_setVertexShader(device, s_quadShader);
        s_setVertexDeclaration(device, s_quadDeclaration);
        s_setStreamSource(device, 0, s_quadBuffer, 0, sizeof(QuadVertex));
        s_setPixelShader(device, s_groundFogShader);
        s_setPsConstant(device, 0, &constants[0][0], 8);
        BindTexture(device, 0, s_depthView, false);
        SetSilhouetteStates(device);
        SetState(device, D3DRS_ALPHABLENDENABLE, TRUE);
        SetState(device, D3DRS_SRCBLEND, D3DBLEND_SRCALPHA);
        SetState(device, D3DRS_DESTBLEND, D3DBLEND_INVSRCALPHA);
        SetState(device, D3DRS_BLENDOP, D3DBLENDOP_ADD);
        SetState(device, D3DRS_COLORWRITEENABLE, 0x7);
        device->DrawPrimitive(D3DPT_TRIANGLESTRIP, 0, 2);
        s_setTexture(device, 0, nullptr);
        RestoreGx(device);
    }

    // once a frame, the last of the effects (before the outline)
    void Fxaa(IDirect3DDevice9* device)
    {
        if (!CVarInt(CV_FXAA) || !s_quadShader || !s_quadDeclaration || !EnsureQuadBuffer(device)
            || !CompileOnce(device, HLSL_FXAA_PS, s_fxaaShader, s_fxaaChecked) || !CopyScene(device))
            return;
        const float screen[4] = { 1.0f / s_sceneCopyWidth, 1.0f / s_sceneCopyHeight, 0.0f, 0.0f };
        FillQuad(s_sceneCopyWidth, s_sceneCopyHeight);
        s_setVertexShader(device, s_quadShader);
        s_setVertexDeclaration(device, s_quadDeclaration);
        s_setStreamSource(device, 0, s_quadBuffer, 0, sizeof(QuadVertex));
        s_setPixelShader(device, s_fxaaShader);
        s_setPsConstant(device, 0, screen, 1);
        BindTexture(device, 0, s_sceneCopy, true);
        SetSilhouetteStates(device);
        SetState(device, D3DRS_COLORWRITEENABLE, 0x7);
        device->DrawPrimitive(D3DPT_TRIANGLESTRIP, 0, 2);
        s_setTexture(device, 0, nullptr);
        RestoreGx(device);
    }

    // at the end of a frame: without antialiasing, our INTZ texture in place of the client's depth buffer (from
    // the next frame on) while an effect needs depth; the client's back when none does
    void UseOwnDepth(IDirect3DDevice9* device)
    {
        bool wanted = (CVarInt(CV_SSAO) || CVarInt(CV_GODRAYS) || CVarInt(CV_DOF) || CVarInt(CV_SSR) || CVarInt(CV_GROUND_FOG))
            && s_ssaoSupported && CVarInt(CV_DEPTH_NO_MSAA);
        IDirect3DSurface9* bound = nullptr;
        device->GetDepthStencilSurface(&bound);
        if (!wanted)
        {
            if (bound && bound == s_ownDepthSurface && s_clientDepth)
                s_setDepthStencil(device, s_clientDepth);
            if (bound != s_ownDepthSurface)
                ReleaseOwnDepth();
            s_clientDepth = nullptr;
        }
        else if (bound && bound != s_ownDepthSurface)
        {
            D3DSURFACE_DESC desc = {};
            bound->GetDesc(&desc);
            if (desc.MultiSampleType == D3DMULTISAMPLE_NONE)
            {
                D3DSURFACE_DESC ownDesc = {};
                if (s_ownDepthSurface)
                    s_ownDepthSurface->GetDesc(&ownDesc);
                if (!s_ownDepthSurface || ownDesc.Width != desc.Width || ownDesc.Height != desc.Height)
                {
                    ReleaseOwnDepth();
                    if (FAILED(device->CreateTexture(desc.Width, desc.Height, 1, D3DUSAGE_DEPTHSTENCIL, FORMAT_INTZ,
                        D3DPOOL_DEFAULT, &s_ownDepth, nullptr)) || !s_ownDepth)
                        s_ownDepth = nullptr;
                    else
                        s_ownDepth->GetSurfaceLevel(0, &s_ownDepthSurface);
                }
                if (s_ownDepthSurface)
                {
                    s_clientDepth = bound;
                    s_setDepthStencil(device, s_ownDepthSurface);
                }
            }
        }
        if (bound)
            bound->Release();
    }

    // once a frame, after SSAO, before the outline: contrast, saturation, brightness, sharpening
    void ColorGrade(IDirect3DDevice9* device)
    {
        float contrast = CVarFloat(CV_CONTRAST), saturation = CVarFloat(CV_SATURATION);
        float brightness = CVarFloat(CV_BRIGHTNESS), sharpen = CVarFloat(CV_SHARPEN);
        float vignette = CVarFloat(CV_VIGNETTE), grain = CVarFloat(CV_GRAIN);
        float exposure = CVarInt(CV_TONEMAP) ? Clamp(CVarFloat(CV_TONEMAP_EXPOSURE), 0.5f, 3.0f) : 0.0f;
        if (contrast == 1.0f && saturation == 1.0f && brightness == 1.0f && sharpen == 0.0f && vignette <= 0.0f && grain <= 0.0f
            && exposure == 0.0f)
            return;
        if (!s_gradeChecked)
        {
            s_gradeChecked = true;
            std::vector<DWORD> code = Compile(HLSL_GRADE_PS, "ps_3_0");
            if (code.empty() || FAILED(device->CreatePixelShader(code.data(), &s_gradeShader)))
                s_gradeShader = nullptr;
        }
        if (!s_gradeShader || !s_quadShader || !s_quadDeclaration || !EnsureQuadBuffer(device))
            return;

        if (!CopyScene(device))
            return;

        contrast = contrast < 0.5f ? 0.5f : (contrast > 1.5f ? 1.5f : contrast);
        saturation = saturation < 0.0f ? 0.0f : (saturation > 2.0f ? 2.0f : saturation);
        brightness = brightness < 0.5f ? 0.5f : (brightness > 1.5f ? 1.5f : brightness);
        sharpen = sharpen < 0.0f ? 0.0f : (sharpen > 1.0f ? 1.0f : sharpen);
        const float screen[4] = { 1.0f / s_sceneCopyWidth, 1.0f / s_sceneCopyHeight, 0.0f, 0.0f };
        const float params[4] = { contrast, saturation, sharpen, brightness };

        FillQuad(s_sceneCopyWidth, s_sceneCopyHeight);
        s_setVertexShader(device, s_quadShader);
        s_setPixelShader(device, s_gradeShader);
        s_setPsConstant(device, 0, screen, 1);
        s_setPsConstant(device, 1, params, 1);
        const float look[4] = { vignette < 0.0f ? 0.0f : (vignette > 1.0f ? 1.0f : vignette),
            grain < 0.0f ? 0.0f : (grain > 1.0f ? 1.0f : grain), static_cast<float>(s_frameCount % 997), exposure };
        s_setPsConstant(device, 2, look, 1);
        s_setVertexDeclaration(device, s_quadDeclaration);
        s_setStreamSource(device, 0, s_quadBuffer, 0, sizeof(QuadVertex));
        s_setTexture(device, 0, s_sceneCopy);
        s_setSamplerState(device, 0, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
        s_setSamplerState(device, 0, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);
        s_setSamplerState(device, 0, D3DSAMP_MAGFILTER, D3DTEXF_POINT);
        s_setSamplerState(device, 0, D3DSAMP_MINFILTER, D3DTEXF_POINT);
        s_setSamplerState(device, 0, D3DSAMP_MIPFILTER, D3DTEXF_NONE);
        s_setSamplerState(device, 0, D3DSAMP_SRGBTEXTURE, FALSE);
        SetSilhouetteStates(device);
        SetState(device, D3DRS_COLORWRITEENABLE, 0x7);
        device->DrawPrimitive(D3DPT_TRIANGLESTRIP, 0, 2);
        s_setTexture(device, 0, nullptr);
        RestoreGx(device);
    }

    template <typename Fn>
    void HookVtable(void** vtable, uint32_t index, Fn& original, void* detour)
    {
        DWORD old = 0;
        if (!VirtualProtect(&vtable[index], sizeof(void*), PAGE_EXECUTE_READWRITE, &old))
            return;
        // already ours (a new device of the same class shares the vtable): the original kept
        if (vtable[index] != detour)
        {
            original = reinterpret_cast<Fn>(vtable[index]);
            vtable[index] = detour;
        }
        VirtualProtect(&vtable[index], sizeof(void*), old, &old);
    }

    // a new device (the client makes one on an antialiasing change): everything of ours belonged to the old one

    template <typename T>
    void Drop(T*& object)
    {
        if (object)
            object->Release();
        object = nullptr;
    }

    void DropDeviceObjects()
    {
        ReleaseMask();
        ReleasePostTargets();
        Drop(s_flatShader); Drop(s_flatAlphaShader); Drop(s_outlineShader); Drop(s_outlineLowShader);
        Drop(s_quadShader); Drop(s_quadDeclaration); Drop(s_quadBuffer);
        Drop(s_ssaoShader); Drop(s_ssaoBlurShader); Drop(s_gradeShader);
        Drop(s_downShader); Drop(s_blurShader); Drop(s_radialShader); Drop(s_addShader); Drop(s_dofShader);
        Drop(s_ssrShader); Drop(s_groundFogShader); Drop(s_fxaaShader);
        s_ssaoChecked = s_ssaoSupported = s_reszSupported = false;
        s_gradeChecked = s_postChecked = s_ssrChecked = s_groundFogChecked = s_fxaaChecked = false;
        s_clientDepth = nullptr;
        s_depthReady = false;
        s_shadow = Shadow();
        s_stats.Installed &= ~4u;
    }

    // the device's vtable (hooked once per device class; the shaders made again for each new device)
    void HookDevice()
    {
        IDirect3DDevice9* current = GetD3DDevice();
        if (current && s_hookedDevice && current != s_hookedDevice)
            DropDeviceObjects();
        if (s_stats.Installed & 4)
            return;
        IDirect3DDevice9* device = GetD3DDevice();
        if (!device)
        {
            s_stats.Error = 1;
            return;
        }
        if (!CreateFlatShader(device))
        {
            s_stats.Error = 2;
            return;
        }
        // the full-screen pass may be missing: the silhouettes (OutlineMode 8) work anyway
        s_stats.Error = CreateOutlineShaders(device);
        void** vtable = *reinterpret_cast<void***>(device);
        HookVtable(vtable, VT_RESET, s_reset, reinterpret_cast<void*>(&ResetDetour));
        HookVtable(vtable, VT_SET_VIEWPORT, s_setViewport, reinterpret_cast<void*>(&SetViewportDetour));
        HookVtable(vtable, VT_SET_DEPTH_STENCIL, s_setDepthStencil, reinterpret_cast<void*>(&SetDepthStencilDetour));
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
        s_hookedDevice = device;
        if (s_reset && s_setViewport && s_setRenderState && s_setTexture && s_setSamplerState && s_setVertexDeclaration
            && s_setFVF && s_setDepthStencil && s_setVertexShader && s_setStreamSource && s_setPixelShader && s_setPsConstant && s_drawIndexed)
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
        RegisterCVars();
        HookDevice();
        ++s_stats.WorldRenders;
        IDirect3DDevice9* device = GetD3DDevice();
        // a lost / resetting device: nothing of ours made or drawn (default pool resources made then break the reset)
        if (device && (s_stats.Installed & 4) && device->TestCooperativeLevel() == D3D_OK)
        {
            ++s_frameCount;
            PrepareDepth(device);
            // our depth texture can't be read while it is the depth buffer: unbound for the passes
            IDirect3DSurface9* bound = nullptr;
            device->GetDepthStencilSurface(&bound);
            bool ownBound = bound && bound == s_ownDepthSurface;
            if (bound)
                bound->Release();
            if (ownBound)
                s_setDepthStencil(device, nullptr);
            Ssao(device);
            Reflections(device);
            GroundFog(device);
            PostEffects(device);
            ColorGrade(device);
            Fxaa(device);
            Composite(device);
            if (ownBound)
                s_setDepthStencil(device, s_ownDepthSurface);
            if (EnsureMask(device) && EnsureQuadBuffer(device))
                ClearMask(device);
            if (EnsureWaterMask(device))
                ClearWaterMask(device);
            UseOwnDepth(device);
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
    FrameScript::PushNumber(L, s_compiled ? 1 : 0);
    FrameScript::PushString(L, s_compileError[0] ? s_compileError : "-");
    // the depth test: "target WxH/samples depth WxH/samples mask samples result"
    char depth[128];
    snprintf(depth, sizeof(depth), "rt %ux%u/%u.%u ds %ux%u/%u.%u mask %u.%u zf %u ze %u hr %08X",
        s_depthInfo.TargetWidth, s_depthInfo.TargetHeight, s_depthInfo.TargetSamples, s_depthInfo.TargetQuality,
        s_depthInfo.DepthWidth, s_depthInfo.DepthHeight, s_depthInfo.DepthSamples, s_depthInfo.DepthQuality,
        s_depthInfo.MaskSamples, s_depthInfo.MaskQuality, s_depthInfo.ZFunc, s_depthInfo.ZEnable, static_cast<uint32_t>(s_depthInfo.Result));
    FrameScript::PushString(L, depth);
    FrameScript::PushNumber(L, s_ssaoStatus);
    char sun[96];
    snprintf(sun, sizeof(sun), "sun u %.2f v %.2f front %.0f vis %.2f", s_sunScreen[0], s_sunScreen[1], s_sunScreen[2], s_sunScreen[3]);
    FrameScript::PushString(L, sun);
    FrameScript::PushNumber(L, s_waterDraws);
    return 18;
}

// /run OutlineMode(n): 1 no silhouettes, 2 no full-screen pass, 4 low quality, 8 stage 1 (silhouettes on the screen)
int32_t Outline::OutlineMode(lua_State* L)
{
    s_mode = static_cast<uint32_t>(FrameScript::GetNumber(L, 1));
    return 0;
}

// /run SetUnitOutline("target", 0, 0.5, 1) - an outline of its own (any color) until ClearUnitOutline
int32_t Outline::SetUnitOutline(lua_State* L)
{
    const char* token = FrameScript::IsString(L, 1);
    WoWGUID guid = 0;
    if (!token || !FrameScript::GetGUIDFromToken(token, &guid, false) || !guid)
        return 0;
    CustomOutline custom;
    custom.Guid = guid;
    custom.Color[0] = static_cast<float>(FrameScript::GetNumber(L, 2));
    custom.Color[1] = static_cast<float>(FrameScript::GetNumber(L, 3));
    custom.Color[2] = static_cast<float>(FrameScript::GetNumber(L, 4));
    for (CustomOutline& existing : s_custom)
        if (existing.Guid == guid)
        {
            existing = custom;
            return 0;
        }
    if (s_custom.size() < 32)
        s_custom.push_back(custom);
    return 0;
}

// /run ClearUnitOutline("target") - or ClearUnitOutline() for every one
int32_t Outline::ClearUnitOutline(lua_State* L)
{
    const char* token = FrameScript::IsString(L, 1);
    if (!token)
    {
        s_custom.clear();
        return 0;
    }
    WoWGUID guid = 0;
    if (!FrameScript::GetGUIDFromToken(token, &guid, false))
        return 0;
    for (size_t i = 0; i < s_custom.size(); ++i)
        if (s_custom[i].Guid == guid)
        {
            s_custom.erase(s_custom.begin() + i);
            break;
        }
    return 0;
}
