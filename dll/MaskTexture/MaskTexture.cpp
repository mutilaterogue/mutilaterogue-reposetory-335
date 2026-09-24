#include <Client/MaskTexture.hpp>
#include <Client/FrameScript.hpp>
#include <Misc/Util.hpp>

#include <Windows.h>
#include <unordered_map>
#include <unordered_set>

// All addresses: 3.3.5a (12340), found in IDA (see the comments).
namespace
{
    // ---------------- client functions ----------------
    constexpr uint32_t ADDR_BATCH_RENDER = 0x484B00;		// int __cdecl CSimpleBatch_Render(CSimpleBatch*)
    constexpr uint32_t ADDR_GXRS_SET = 0x685F50;		// void __cdecl GxRsSet(int state, void* value)
    constexpr uint32_t ADDR_TEXTURE_DRAW = 0x485140;		// int __thiscall CSimpleTexture::Draw(CSimpleBatch*)
    constexpr uint32_t ADDR_TEXTURE_VTABLE_DRAW = 0x9EA1D8 + 23 * 4;	// slot 23 = 0x9EA234
    constexpr uint32_t ADDR_TEX_GETGX = 0x4B6CB0;		// CGxTex* __cdecl (HTEXTURE, int, int)
    constexpr uint32_t ADDR_TEX_HASTRANSFORM = 0x4B5460;	// int __cdecl (HTEXTURE)
    constexpr uint32_t ADDR_TEX_GETTRANSFORM = 0x4B5490;	// void __cdecl (HTEXTURE, float* offset2, float* scale)
    constexpr uint32_t ADDR_SHADERS = 0xB47934;			// CGxShader* [2]: "UI", "Desaturate"
    constexpr uint32_t ADDR_SHADER_VALID = 0x689A50;		// bool __thiscall CGxShader::Valid()
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

    // GxRs states (sub_484B00: 21 texture, 78 pixel shader)
    constexpr int GXRS_TEXTURE0 = 21;
    constexpr int GXRS_TEXTURE1 = 22;
    constexpr int GXRS_PIXELSHADER = 78;
    constexpr int GXSH_PIXEL = 4;

    // ---------------- layouts ----------------
    constexpr uint32_t TEX_HANDLE = 0xD4;		// HTEXTURE
    constexpr uint32_t TEX_POSITIONS = 0xE0;		// 4 x {x, y, z}: top left, bottom left, top right, bottom right
    constexpr uint32_t TEX_TEXCOORDS = 0x140;	// 4 x {u, v}
    constexpr uint32_t BATCH_COUNT = 0x0C;
    constexpr uint32_t BATCH_ITEMS = 0x10;
    constexpr uint32_t ITEM_SIZE = 60;

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
    static_assert(sizeof(BatchItem) == ITEM_SIZE);

    using BatchRender_t = int(__cdecl*)(void*);
    using GxRsSet_t = void(__cdecl*)(int, void*);
    using TextureDraw_t = int(__thiscall*)(void*, void*);
    using TexGetGx_t = void* (__cdecl*)(uint32_t, int, int);
    using TexHasTransform_t = int(__cdecl*)(uint32_t);
    using TexGetTransform_t = void(__cdecl*)(uint32_t, float*, float*);
    using ShaderValid_t = bool(__thiscall*)(void*);
    using ShaderCreate_t = void(__thiscall*)(void*, void**, int, const char*, const char*, int);
    using ShaderConstants_t = void(__thiscall*)(void*, int, int, const float*, int);
    using IsA_t = bool(__thiscall*)(void*, int);
    using LuaType_t = int(__cdecl*)(lua_State*, int);
    using LuaRawGetI_t = void(__cdecl*)(lua_State*, int, int);
    using LuaToUserdata_t = void* (__cdecl*)(lua_State*, int);
    using LuaSetTop_t = void(__cdecl*)(lua_State*, int);

    // ---------------- state ----------------
    std::unordered_map<const float*, void*> s_maskOf;	// masked texture positions (+0xE0) -> mask texture
    std::unordered_set<void*> s_isMask;					// textures used as masks: not drawn

    void* s_maskShader = nullptr;
    void* s_maskDesatShader = nullptr;
    bool s_shadersLoaded = false;

    // the batch being rendered with masks: the item index follows the PixelShader sets (batching off)
    void* s_renderBatch = nullptr;
    uint32_t s_renderItem = 0;
    bool s_texture1Bound = false;

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

    void LoadShaders()
    {
        if (s_shadersLoaded)
            return;
        s_shadersLoaded = true;
        void* device = Device();
        auto create = reinterpret_cast<ShaderCreate_t>(VFunc(device, VT_SHADER_CREATE));
        create(device, &s_maskShader, GXSH_PIXEL, "Shaders\\Pixel", "UIMask", 1);
        create(device, &s_maskDesatShader, GXSH_PIXEL, "Shaders\\Pixel", "UIMaskDesaturate", 1);
        auto valid = reinterpret_cast<ShaderValid_t>(ADDR_SHADER_VALID);
        if (s_maskShader && !valid(s_maskShader))
            s_maskShader = nullptr;
        if (s_maskDesatShader && !valid(s_maskDesatShader))
            s_maskDesatShader = nullptr;
    }

    // uv of corner i after the texture's own atlas transform (the UV the shader gets in t0)
    void CornerUV(const float* uv, int i, uint32_t handle, float& u, float& v)
    {
        u = uv[i * 2];
        v = uv[i * 2 + 1];
        if (reinterpret_cast<TexHasTransform_t>(ADDR_TEX_HASTRANSFORM)(handle))
        {
            float offset[2] = { 0.f, 0.f };
            float scale = 1.f;
            reinterpret_cast<TexGetTransform_t>(ADDR_TEX_GETTRANSFORM)(handle, offset, &scale);
            u = scale * u + offset[0];
            v = scale * v + offset[1];
        }
    }

    // c1: maskUV = t0 * c1.xy + c1.zw. The texture UV is linear over the quad, so is the mask UV.
    bool MaskConstants(const BatchItem* item, void* mask, float out[4])
    {
        const float* p = item->positions;
        const float* uv = item->texcoords;
        float tu0 = uv[0], tv0 = uv[1], tu3 = uv[6], tv3 = uv[7];
        if (item->hasTransform)
        {
            tu0 = item->scale * tu0 + item->offsetU; tv0 = item->scale * tv0 + item->offsetV;
            tu3 = item->scale * tu3 + item->offsetU; tv3 = item->scale * tv3 + item->offsetV;
        }

        const float* m = At<float>(mask, TEX_POSITIONS);
        uint32_t maskHandle = *At<uint32_t>(mask, TEX_HANDLE);
        float mu0, mv0, mu3, mv3;
        CornerUV(At<float>(mask, TEX_TEXCOORDS), 0, maskHandle, mu0, mv0);
        CornerUV(At<float>(mask, TEX_TEXCOORDS), 3, maskHandle, mu3, mv3);

        float du = tu3 - tu0, dv = tv3 - tv0;
        float mw = m[9] - m[0], mh = m[10] - m[1];
        if (du == 0.f || dv == 0.f || mw == 0.f || mh == 0.f)
            return false;

        // screen -> mask rect 0..1
        float ax = (p[9] - p[0]) / (du * mw);
        float bx = (p[0] - m[0]) / mw - tu0 * ax;
        float ay = (p[10] - p[1]) / (dv * mh);
        float by = (p[1] - m[1]) / mh - tv0 * ay;
        // mask rect 0..1 -> the mask's own texcoords
        out[0] = ax * (mu3 - mu0);
        out[1] = ay * (mv3 - mv0);
        out[2] = mu0 + bx * (mu3 - mu0);
        out[3] = mv0 + by * (mv3 - mv0);
        return true;
    }

    // ---------------- hooks ----------------
    int __fastcall TextureDrawHook(void* texture, void* /*edx*/, void* batch)
    {
        if (s_isMask.count(texture))
            return 0;
        return reinterpret_cast<TextureDraw_t>(ADDR_TEXTURE_DRAW)(texture, batch);
    }

    bool BatchHasMask(void* batch)
    {
        uint32_t count = *At<uint32_t>(batch, BATCH_COUNT);
        auto* items = *At<BatchItem*>(batch, BATCH_ITEMS);
        for (uint32_t i = 0; i < count; i++)
            if (s_maskOf.count(items[i].positions))
                return true;
        return false;
    }

    int __cdecl BatchRenderHook(void* batch)
    {
        if (s_maskOf.empty() || !BatchHasMask(batch))
            return reinterpret_cast<BatchRender_t>(ADDR_BATCH_RENDER)(batch);

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
        if (s_texture1Bound)
        {
            reinterpret_cast<GxRsSet_t>(ADDR_GXRS_SET)(GXRS_TEXTURE1, nullptr);
            s_texture1Bound = false;
        }
        return result;
    }

    void __cdecl PixelShaderSetHook(int state, void* shader)
    {
        auto gxRsSet = reinterpret_cast<GxRsSet_t>(ADDR_GXRS_SET);
        void* batch = s_renderBatch;
        if (!batch || state != GXRS_PIXELSHADER)
        {
            gxRsSet(state, shader);
            return;
        }

        uint32_t count = *At<uint32_t>(batch, BATCH_COUNT);
        auto* items = *At<BatchItem*>(batch, BATCH_ITEMS);
        BatchItem* item = s_renderItem < count ? &items[s_renderItem] : nullptr;
        s_renderItem++;

        auto it = item ? s_maskOf.find(item->positions) : s_maskOf.end();
        void* mask = it != s_maskOf.end() ? it->second : nullptr;
        void* maskTex = mask ? reinterpret_cast<TexGetGx_t>(ADDR_TEX_GETGX)(*At<uint32_t>(mask, TEX_HANDLE), 1, 0) : nullptr;
        float c1[4];
        bool desat = shader && shader == reinterpret_cast<void**>(ADDR_SHADERS)[1];
        void* maskShader = desat ? s_maskDesatShader : s_maskShader;

        if (!maskTex || !maskShader || !MaskConstants(item, mask, c1))
        {
            gxRsSet(state, shader);
            return;
        }

        gxRsSet(state, maskShader);
        gxRsSet(GXRS_TEXTURE1, maskTex);
        s_texture1Bound = true;
        void* device = Device();
        reinterpret_cast<ShaderConstants_t>(VFunc(device, VT_SHADER_CONSTANTS))(device, GXSH_PIXEL, 1, c1, 1);
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

    // every "call CSimpleBatch_Render" in .text
    int PatchRenderCalls()
    {
        int patched = 0;
        for (uint32_t site = 0x401000; site < 0x9E0000; site++)
            if (*reinterpret_cast<uint8_t*>(site) == 0xE8
                && site + 5 + *reinterpret_cast<int32_t*>(site + 1) == ADDR_BATCH_RENDER
                && PatchCall(site, ADDR_BATCH_RENDER, reinterpret_cast<void*>(&BatchRenderHook)))
                patched++;
        return patched;
    }

    // "push 4Eh; call GxRsSet" inside the render (the per-item pixel shader)
    bool PatchPixelShaderSet()
    {
        for (uint32_t site = ADDR_BATCH_RENDER; site < ADDR_BATCH_RENDER + 0x800; site++)
        {
            auto* code = reinterpret_cast<uint8_t*>(site);
            if (code[0] == 0x6A && code[1] == GXRS_PIXELSHADER && PatchCall(site + 2, ADDR_GXRS_SET, reinterpret_cast<void*>(&PixelShaderSetHook)))
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
        auto isA = reinterpret_cast<IsA_t>(VFunc(object, 16));
        return isA(object, classId) ? object : nullptr;
    }
}

void MaskTexture::ApplyPatches()
{
    // masks are not drawn: CSimpleTexture vtable slot 23
    if (*reinterpret_cast<uint32_t*>(ADDR_TEXTURE_VTABLE_DRAW) == ADDR_TEXTURE_DRAW)
        Util::OverwriteUInt32AtAddress(ADDR_TEXTURE_VTABLE_DRAW, reinterpret_cast<uint32_t>(&TextureDrawHook));

    // the pixel shader hook first: without it the render hook must not run
    if (PatchPixelShaderSet())
        PatchRenderCalls();
}

// TextureAddMask(texture, mask): one mask per texture (a new one replaces the old)
int32_t MaskTexture::TextureAddMask(lua_State* L)
{
    void* texture = TextureArg(L, 1);
    void* mask = TextureArg(L, 2);
    if (!texture || !mask || texture == mask)
        FrameScript::DisplayError(L, "Usage: TextureAddMask(texture, maskTexture)");
    s_isMask.insert(mask);
    s_maskOf[At<float>(texture, TEX_POSITIONS)] = mask;
    return 0;
}

// TextureRemoveMask(texture [, mask])
int32_t MaskTexture::TextureRemoveMask(lua_State* L)
{
    void* texture = TextureArg(L, 1);
    if (!texture)
        FrameScript::DisplayError(L, "Usage: TextureRemoveMask(texture [, maskTexture])");
    void* mask = TextureArg(L, 2);
    auto it = s_maskOf.find(At<float>(texture, TEX_POSITIONS));
    if (it != s_maskOf.end() && (!mask || it->second == mask))
        s_maskOf.erase(it);
    return 0;
}

// TextureGetMask(texture) -> true if the texture has a mask (the Lua side keeps the mask object)
int32_t MaskTexture::TextureGetMask(lua_State* L)
{
    void* texture = TextureArg(L, 1);
    FrameScript::PushBoolean(L, texture && s_maskOf.count(At<float>(texture, TEX_POSITIONS)) > 0);
    return 1;
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
