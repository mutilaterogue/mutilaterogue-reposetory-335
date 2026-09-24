#include <Client/MaskTexture.hpp>
#include <Client/FrameScript.hpp>
#include <Misc/Util.hpp>

#include <Windows.h>
#include <algorithm>
#include <cstdio>
#include <unordered_map>
#include <unordered_set>
#include <vector>

// All addresses: 3.3.5a (12340).
namespace
{
    // ---------------- client functions ----------------
    constexpr uint32_t ADDR_BATCH_RENDER = 0x484B00;		// int __cdecl CSimpleBatch_Render(CSimpleBatch*)
    constexpr uint32_t ADDR_GXRS_SET = 0x685F50;		// void __thiscall CGxDevice::RsSet(int state, void* value)
    constexpr uint32_t ADDR_TEXTURE_DRAW = 0x485140;		// int __thiscall CSimpleTexture::Draw(CSimpleBatch*)
    constexpr uint32_t ADDR_TEXTURE_VTABLE_DRAW = 0x9EA1D8 + 23 * 4;	// CSimpleTexture vtable slot 23
    constexpr uint32_t ADDR_TEX_GETGX = 0x4B6CB0;		// CGxTex* __cdecl (HTEXTURE, int, int)
    constexpr uint32_t ADDR_TEX_HASTRANSFORM = 0x4B5460;	// int __cdecl (HTEXTURE): texture packed in an atlas
    constexpr uint32_t ADDR_TEX_GETTRANSFORM = 0x4B5490;	// void __cdecl (HTEXTURE, float* offset2, float* scale)
    constexpr uint32_t ADDR_SHADERS = 0xB47934;			// CGxShader* [2]: "UI", "Desaturate"
    constexpr uint32_t ADDR_UI_SHADERS_CREATE = 0x483060;	// void __cdecl: creates them (UI init, device reset)
    constexpr uint32_t ADDR_SHADER_VALID = 0x689A50;		// bool __thiscall CGxShader::Valid() (reloads if needed)
    constexpr uint32_t ADDR_BATCHING = 0xB47948;			// int: merge batch items
    constexpr uint32_t ADDR_DEVICE = 0xC5DF88;			// CGxDevice*
    constexpr uint32_t ADDR_TEXTURE_CLASSID = 0xB4793C;	// CSimpleTexture script class id (0 until first use)
    constexpr uint32_t ADDR_CLASSID_COUNTER = 0xD3F778;

    constexpr uint32_t ADDR_LUA_TYPE = 0x84DEB0;
    constexpr uint32_t ADDR_LUA_RAWGETI = 0x84E670;
    constexpr uint32_t ADDR_LUA_TOUSERDATA = 0x84E1C0;
    constexpr uint32_t ADDR_LUA_SETTOP = 0x84DBF0;

    // device vtable
    constexpr uint32_t VT_SHADER_CREATE = 272;			// (CGxShader** out, int target, const char* path, const char* name, int permutations)
    constexpr uint32_t VT_SHADER_CONSTANTS = 280;			// (int target, int start, const float* data, int count)

    // GxRs states (sub_484B00: 21 texture 0, 78 pixel shader)
    constexpr int GXRS_TEXTURE0 = 21;
    constexpr int GXRS_PIXELSHADER = 78;
    constexpr int GXSH_PIXEL = 4;

    constexpr size_t MAX_MASKS = 3;			// shaders UIMask1..3 / UIMaskDesaturate1..3 (tools/blsmask.py)

    // ---------------- layouts ----------------
    constexpr uint32_t TEX_HANDLE = 0xD4;		// HTEXTURE
    constexpr uint32_t TEX_POSITIONS = 0xE0;		// 4 x {x, y, z}: top left, bottom left, top right, bottom right
    constexpr uint32_t TEX_TEXCOORDS = 0x140;	// 4 x {u, v}
    constexpr uint32_t BATCH_COUNT = 0x0C;
    constexpr uint32_t BATCH_ITEMS = 0x10;

    struct BatchItem
    {
        uint32_t hTexture;		// 0
        void* gxTex;			// 1
        int32_t blend;			// 2
        void* shader;			// 3
        uint32_t numVerts;		// 4
        float* positions;		// 5 = CSimpleTexture + 0xE0
        float* texcoords;		// 6
        void* colors;			// 7
        uint32_t numColors;		// 8
        void* indices;			// 9
        uint32_t numIndices;	// 10
        uint32_t hasTransform;	// 11
        float scale;			// 12
        float offsetU;			// 13
        float offsetV;			// 14
    };
    static_assert(sizeof(BatchItem) == 60 || sizeof(void*) != 4);

    using BatchRender_t = int(__cdecl*)(void*);
    using GxRsSet_t = void(__thiscall*)(void*, int, void*);
    using TextureDraw_t = int(__thiscall*)(void*, void*);
    using TexGetGx_t = void* (__cdecl*)(uint32_t, int, int);
    using TexHasTransform_t = int(__cdecl*)(uint32_t);
    using TexGetTransform_t = void(__cdecl*)(uint32_t, float*, float*);
    using ShaderValid_t = bool(__thiscall*)(void*);
    using ShaderCreate_t = void(__thiscall*)(void*, void**, int, const char*, const char*, int);
    using ShaderConstants_t = void(__thiscall*)(void*, int, int, const float*, int);
    using UiShaders_t = void(__cdecl*)();
    using IsA_t = bool(__thiscall*)(void*, int);
    using LuaType_t = int(__cdecl*)(lua_State*, int);
    using LuaRawGetI_t = void(__cdecl*)(lua_State*, int, int);
    using LuaToUserdata_t = void* (__cdecl*)(lua_State*, int);
    using LuaSetTop_t = void(__cdecl*)(lua_State*, int);

    // ---------------- state ----------------
    std::unordered_map<const float*, std::vector<void*>> s_masksOf;	// masked texture positions (+0xE0) -> masks
    std::unordered_set<void*> s_isMask;									// textures used as masks: not drawn

    void* s_maskShaders[MAX_MASKS] = {};
    void* s_maskDesatShaders[MAX_MASKS] = {};
    bool s_shadersLoaded = false;

    // the batch being rendered with masks: the item index follows the pixel shader sets (batching off)
    void* s_renderBatch = nullptr;
    uint32_t s_renderItem = 0;
    size_t s_boundMasks = 0;

    template <typename T> T* At(void* base, uint32_t offset)
    {
        return reinterpret_cast<T*>(reinterpret_cast<uint8_t*>(base) + offset);
    }

    void* Device()
    {
        return *reinterpret_cast<void**>(ADDR_DEVICE);
    }

    void* VFunc(void* object, uint32_t offset)
    {
        return *reinterpret_cast<void**>(*reinterpret_cast<uint8_t**>(object) + offset);
    }

    void GxRsSet(void* device, int state, void* value)
    {
        reinterpret_cast<GxRsSet_t>(ADDR_GXRS_SET)(device, state, value);
    }

    // Shaders are cached by name (sub_6897C0): creating again gives the same object back.
    // They have to be created with the client's UI shaders: one created in the middle of a frame is not drawn.
    void LoadShaders()
    {
        s_shadersLoaded = true;
        void* device = Device();
        auto create = reinterpret_cast<ShaderCreate_t>(VFunc(device, VT_SHADER_CREATE));
        char name[32];
        for (size_t i = 0; i < MAX_MASKS; i++)
        {
            snprintf(name, sizeof(name), "UIMask%u", static_cast<unsigned>(i + 1));
            create(device, &s_maskShaders[i], GXSH_PIXEL, "Shaders\\Pixel", name, 1);
            snprintf(name, sizeof(name), "UIMaskDesaturate%u", static_cast<unsigned>(i + 1));
            create(device, &s_maskDesatShaders[i], GXSH_PIXEL, "Shaders\\Pixel", name, 1);
        }
    }

    // CGxShader::Valid reloads the D3D shader when a device reset dropped it
    void* UsableShader(void* shader)
    {
        return shader && reinterpret_cast<ShaderValid_t>(ADDR_SHADER_VALID)(shader) ? shader : nullptr;
    }

    // the UV the shader gets for corner i of a texture (its own texcoords through its atlas transform)
    void TextureUV(uint32_t handle, const float* texcoords, int i, float& u, float& v)
    {
        u = texcoords[i * 2];
        v = texcoords[i * 2 + 1];
        if (reinterpret_cast<TexHasTransform_t>(ADDR_TEX_HASTRANSFORM)(handle))
        {
            float offset[2] = { 0.f, 0.f };
            float scale = 1.f;
            reinterpret_cast<TexGetTransform_t>(ADDR_TEX_GETTRANSFORM)(handle, offset, &scale);
            u = scale * u + offset[0];
            v = scale * v + offset[1];
        }
    }

    // a*u + b*v + c through 3 points (u_i, v_i) -> t_i
    bool SolveAffine(const float u[3], const float v[3], const float t[3], float out[3])
    {
        float det = u[0] * (v[1] - v[2]) - v[0] * (u[1] - u[2]) + (u[1] * v[2] - v[1] * u[2]);
        if (det > -1e-12f && det < 1e-12f)
            return false;
        out[0] = (t[0] * (v[1] - v[2]) - v[0] * (t[1] - t[2]) + (t[1] * v[2] - v[1] * t[2])) / det;
        out[1] = (u[0] * (t[1] - t[2]) - t[0] * (u[1] - u[2]) + (u[1] * t[2] - t[1] * u[2])) / det;
        out[2] = (u[0] * (v[1] * t[2] - t[1] * v[2]) - v[0] * (u[1] * t[2] - t[1] * u[2]) + t[0] * (u[1] * v[2] - v[1] * u[2])) / det;
        return true;
    }

    // 3 shader constants (12 floats) for one mask: maskUV = uv.x * A + uv.y * B + C.
    // The texture's UV is affine over its quad (texcoord rotation, flips, atlas, crop), so is the mask UV:
    // solved through 3 corners, mask UV = the corner's position in the mask rect through the mask's texcoords.
    bool MaskConstants(const BatchItem* item, void* mask, float out[12])
    {
        const float* p = item->positions;
        const float* m = At<float>(mask, TEX_POSITIONS);
        float mw = m[9] - m[0], mh = m[10] - m[1];
        if (mw == 0.f || mh == 0.f)
            return false;

        uint32_t maskHandle = *At<uint32_t>(mask, TEX_HANDLE);
        float mu0, mv0, mu3, mv3;
        TextureUV(maskHandle, At<float>(mask, TEX_TEXCOORDS), 0, mu0, mv0);
        TextureUV(maskHandle, At<float>(mask, TEX_TEXCOORDS), 3, mu3, mv3);

        float u[3], v[3], tu[3], tv[3];
        for (int i = 0; i < 3; i++)
        {
            u[i] = item->texcoords[i * 2];
            v[i] = item->texcoords[i * 2 + 1];
            if (item->hasTransform)
            {
                u[i] = item->scale * u[i] + item->offsetU;
                v[i] = item->scale * v[i] + item->offsetV;
            }
            const float* corner = p + i * 3;
            tu[i] = mu0 + (corner[0] - m[0]) / mw * (mu3 - mu0);
            tv[i] = mv0 + (corner[1] - m[1]) / mh * (mv3 - mv0);
        }

        float a[3], b[3];
        if (!SolveAffine(u, v, tu, a) || !SolveAffine(u, v, tv, b))
            return false;
        const float constants[12] = { a[0], b[0], 0.f, 0.f,  a[1], b[1], 0.f, 0.f,  a[2], b[2], 0.f, 0.f };
        std::copy(constants, constants + 12, out);
        return true;
    }

    // ---------------- hooks ----------------
    int __fastcall TextureDrawHook(void* texture, void* /*edx*/, void* batch)
    {
        if (s_isMask.count(texture))
            return 0;
        return reinterpret_cast<TextureDraw_t>(ADDR_TEXTURE_DRAW)(texture, batch);
    }

    void __cdecl UiShadersCreateHook()
    {
        reinterpret_cast<UiShaders_t>(ADDR_UI_SHADERS_CREATE)();
        LoadShaders();
    }

    bool BatchHasMask(void* batch)
    {
        uint32_t count = *At<uint32_t>(batch, BATCH_COUNT);
        auto* items = *At<BatchItem*>(batch, BATCH_ITEMS);
        for (uint32_t i = 0; i < count; i++)
            if (s_masksOf.count(items[i].positions))
                return true;
        return false;
    }

    int __cdecl BatchRenderHook(void* batch)
    {
        if (s_masksOf.empty() || !BatchHasMask(batch))
            return reinterpret_cast<BatchRender_t>(ADDR_BATCH_RENDER)(batch);

        // created with the client's shaders; lazily only if that happened before the patch
        if (!s_shadersLoaded)
            LoadShaders();

        // one draw per item: every item sets its pixel shader, in item order
        int32_t& batching = *reinterpret_cast<int32_t*>(ADDR_BATCHING);
        int32_t oldBatching = batching;
        batching = 0;
        s_renderBatch = batch;
        s_renderItem = 0;
        int result = reinterpret_cast<BatchRender_t>(ADDR_BATCH_RENDER)(batch);
        s_renderBatch = nullptr;
        batching = oldBatching;

        void* device = Device();
        for (size_t k = 1; k <= s_boundMasks; k++)
            GxRsSet(device, GXRS_TEXTURE0 + static_cast<int>(k), nullptr);
        s_boundMasks = 0;
        return result;
    }

    // replaces "call CGxDevice::RsSet" (thiscall): fastcall gets the device in ecx and pops the 2 args the same way
    void __fastcall PixelShaderSetHook(void* device, void* /*edx*/, int state, void* shader)
    {
        void* batch = s_renderBatch;
        if (!batch || state != GXRS_PIXELSHADER)
        {
            GxRsSet(device, state, shader);
            return;
        }

        uint32_t count = *At<uint32_t>(batch, BATCH_COUNT);
        auto* items = *At<BatchItem*>(batch, BATCH_ITEMS);
        BatchItem* item = s_renderItem < count ? &items[s_renderItem] : nullptr;
        s_renderItem++;

        auto it = item ? s_masksOf.find(item->positions) : s_masksOf.end();
        if (it == s_masksOf.end())
        {
            GxRsSet(device, state, shader);
            return;
        }

        void* maskTex[MAX_MASKS];
        float constants[MAX_MASKS * 12];
        size_t used = 0;
        for (void* mask : it->second)
        {
            if (used == MAX_MASKS)
                break;
            maskTex[used] = reinterpret_cast<TexGetGx_t>(ADDR_TEX_GETGX)(*At<uint32_t>(mask, TEX_HANDLE), 1, 0);
            if (maskTex[used] && MaskConstants(item, mask, constants + used * 12))
                used++;
        }

        bool desaturated = shader && shader == reinterpret_cast<void**>(ADDR_SHADERS)[1];
        void* maskShader = used ? UsableShader((desaturated ? s_maskDesatShaders : s_maskShaders)[used - 1]) : nullptr;
        if (!maskShader)
        {
            GxRsSet(device, state, shader);
            return;
        }

        GxRsSet(device, state, maskShader);
        for (size_t k = 0; k < used; k++)
            GxRsSet(device, GXRS_TEXTURE0 + 1 + static_cast<int>(k), maskTex[k]);
        if (used > s_boundMasks)
            s_boundMasks = used;
        reinterpret_cast<ShaderConstants_t>(VFunc(device, VT_SHADER_CONSTANTS))(
            device, GXSH_PIXEL, 1, constants, static_cast<int>(used * 3));
    }

    // ---------------- patching ----------------
    // replaces "call target" at site; checks the bytes first, a wrong address is skipped, not patched
    bool PatchCall(uint32_t site, uint32_t target, void* hook)
    {
        auto* code = reinterpret_cast<uint8_t*>(site);
        if (code[0] != 0xE8 || site + 5 + *reinterpret_cast<int32_t*>(site + 1) != target)
            return false;
        Util::OverwriteUInt32AtAddress(site + 1, reinterpret_cast<uint32_t>(hook) - (site + 5));
        return true;
    }

    // every "call target" in .text
    int PatchAllCalls(uint32_t target, void* hook)
    {
        int patched = 0;
        for (uint32_t site = 0x401000; site < 0x9E0000; site++)
            if (*reinterpret_cast<uint8_t*>(site) == 0xE8
                && site + 5 + *reinterpret_cast<int32_t*>(site + 1) == target
                && PatchCall(site, target, hook))
                patched++;
        return patched;
    }

    // "push 4Eh; call CGxDevice::RsSet" inside the render (the per-item pixel shader)
    bool PatchPixelShaderSet()
    {
        for (uint32_t site = ADDR_BATCH_RENDER; site < ADDR_BATCH_RENDER + 0x800; site++)
        {
            auto* code = reinterpret_cast<uint8_t*>(site);
            if (code[0] == 0x6A && code[1] == GXRS_PIXELSHADER
                && PatchCall(site + 2, ADDR_GXRS_SET, reinterpret_cast<void*>(&PixelShaderSetHook)))
                return true;
        }
        return false;
    }

    // ---------------- Lua ----------------
    void* TextureArg(lua_State* L, int index)
    {
        if (reinterpret_cast<LuaType_t>(ADDR_LUA_TYPE)(L, index) != 5)	// LUA_TTABLE
            return nullptr;
        reinterpret_cast<LuaRawGetI_t>(ADDR_LUA_RAWGETI)(L, index, 0);
        void* object = reinterpret_cast<LuaToUserdata_t>(ADDR_LUA_TOUSERDATA)(L, -1);
        reinterpret_cast<LuaSetTop_t>(ADDR_LUA_SETTOP)(L, -2);
        if (!object)
            return nullptr;
        // same class id init as the client's texture methods (sub_48C9A0)
        int32_t& classId = *reinterpret_cast<int32_t*>(ADDR_TEXTURE_CLASSID);
        if (!classId)
        {
            int32_t& counter = *reinterpret_cast<int32_t*>(ADDR_CLASSID_COUNTER);
            classId = ++counter;
        }
        return reinterpret_cast<IsA_t>(VFunc(object, 16))(object, classId) ? object : nullptr;
    }
}

void MaskTexture::ApplyPatches()
{
    // masks are not drawn: CSimpleTexture vtable slot 23
    if (*reinterpret_cast<uint32_t*>(ADDR_TEXTURE_VTABLE_DRAW) == ADDR_TEXTURE_DRAW)
        Util::OverwriteUInt32AtAddress(ADDR_TEXTURE_VTABLE_DRAW, reinterpret_cast<uint32_t>(&TextureDrawHook));

    // the pixel shader hook first: without it the render hook must not run
    if (PatchPixelShaderSet())
    {
        PatchAllCalls(ADDR_UI_SHADERS_CREATE, reinterpret_cast<void*>(&UiShadersCreateHook));
        PatchAllCalls(ADDR_BATCH_RENDER, reinterpret_cast<void*>(&BatchRenderHook));
    }
}

// TextureAddMask(texture, mask): up to 3 masks per texture (more are kept but not drawn)
int32_t MaskTexture::TextureAddMask(lua_State* L)
{
    void* texture = TextureArg(L, 1);
    void* mask = TextureArg(L, 2);
    if (!texture || !mask || texture == mask)
        FrameScript::DisplayError(L, "Usage: TextureAddMask(texture, maskTexture)");
    s_isMask.insert(mask);
    auto& masks = s_masksOf[At<float>(texture, TEX_POSITIONS)];
    if (std::find(masks.begin(), masks.end(), mask) == masks.end())
        masks.push_back(mask);
    return 0;
}

// TextureRemoveMask(texture [, mask]): without a mask, all of them
int32_t MaskTexture::TextureRemoveMask(lua_State* L)
{
    void* texture = TextureArg(L, 1);
    if (!texture)
        FrameScript::DisplayError(L, "Usage: TextureRemoveMask(texture [, maskTexture])");
    void* mask = TextureArg(L, 2);
    auto it = s_masksOf.find(At<float>(texture, TEX_POSITIONS));
    if (it == s_masksOf.end())
        return 0;
    if (mask)
        it->second.erase(std::remove(it->second.begin(), it->second.end(), mask), it->second.end());
    if (!mask || it->second.empty())
        s_masksOf.erase(it);
    return 0;
}

// TextureSetIsMask(texture, isMask): a mask is not drawn
int32_t MaskTexture::TextureSetIsMask(lua_State* L)
{
    void* texture = TextureArg(L, 1);
    if (!texture)
        FrameScript::DisplayError(L, "Usage: TextureSetIsMask(texture, isMask)");
    if (FrameScript::GetBoolean(L, 2))
        s_isMask.insert(texture);
    else
        s_isMask.erase(texture);
    return 0;
}
