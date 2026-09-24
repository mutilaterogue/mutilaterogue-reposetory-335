#include <Client/XMLExt.hpp>
#include <Client/FrameScript.hpp>
#include <Misc/Util.hpp>

#include <Windows.h>
#include <cstring>
#include <string>

// ---------------- адреса ----------------
static constexpr uint32_t ADDR_FRAME_LOADXML = 0x4932C0;
static constexpr uint32_t ADDR_TEXTURE_LOADXML = 0x485F40;
static constexpr uint32_t ADDR_FONTSTRING_LOADXML = 0x4873E0;
static constexpr uint32_t ADDR_XML_GETATTR = 0x814730;
static constexpr uint32_t ADDR_LUA_RAWGETI = 0x84E670;
static constexpr uint32_t ADDR_LUA_GETFIELD = 0x84E590;
static constexpr uint32_t ADDR_LUA_PCALL = 0x84EC50;
static constexpr uint32_t ADDR_SCRIPTOBJ_REGISTER = 0x819880;
static constexpr uint32_t ADDR_GET_LUA_CONTEXT = 0x817DB0;

// ---------------- смещения ----------------
static constexpr uint32_t LAYOUT_TO_OBJECT = 0x20;
static constexpr uint32_t OFF_LUA_CREATED = 0x04;
static constexpr uint32_t OFF_LUA_REF = 0x08;
static constexpr uint32_t VT_GET_PARENT = 20;

static constexpr uint32_t OFF_NODE_CHILD = 0x08;
static constexpr uint32_t OFF_NODE_NAME = 0x14;
static constexpr uint32_t OFF_NODE_NEXT = 0x34;

static constexpr int LUA_REGISTRYINDEX = -10000;
static constexpr int LUA_GLOBALSINDEX = -10002;

static constexpr char SEP_ENTRY = '\1';
static constexpr char SEP_FIELD = '\2';

using LoadXMLFn = int32_t(__thiscall*)(void*, XMLNode*, void*);
using GetFieldFn = void(__cdecl*)(lua_State*, int, const char*);
using PCallFn = int(__cdecl*)(lua_State*, int, int, int);
using RawGetIFn = void(__cdecl*)(lua_State*, int, int);
using GetCtxFn = lua_State * (__cdecl*)();

// ---------------- XMLNode ----------------
static XMLNode* NodeFirstChild(XMLNode* n)
{
    return *reinterpret_cast<XMLNode**>(reinterpret_cast<uint32_t>(n) + OFF_NODE_CHILD);
}

static XMLNode* NodeNext(XMLNode* n)
{
    return *reinterpret_cast<XMLNode**>(reinterpret_cast<uint32_t>(n) + OFF_NODE_NEXT);
}

static const char* NodeName(XMLNode* n)
{
    return *reinterpret_cast<const char**>(reinterpret_cast<uint32_t>(n) + OFF_NODE_NAME);
}

static XMLNode* FindChild(XMLNode* n, const char* name)
{
    for (XMLNode* c = NodeFirstChild(n); c; c = NodeNext(c))
    {
        const char* nm = NodeName(c);

        if (nm && !_stricmp(nm, name))
            return c;
    }

    return nullptr;
}

static void AppendField(std::string& out, const char* s)
{
    if (s)
        out += s;

    out += SEP_FIELD;
}

const char* XMLExt::GetAttr(XMLNode* node, const char* name)
{
    return reinterpret_cast<const char* (__thiscall*)(XMLNode*, const char*)>(ADDR_XML_GETATTR)(node, name);
}

// ---------------- Lua ----------------
void XMLExt::PushScriptObject(lua_State* L, void* obj)
{
    if (!obj)
    {
        FrameScript::PushNil(L);
        return;
    }

    uint32_t base = reinterpret_cast<uint32_t>(obj);

    if (!*reinterpret_cast<int32_t*>(base + OFF_LUA_CREATED))
        reinterpret_cast<void(__thiscall*)(void*, int32_t)>(ADDR_SCRIPTOBJ_REGISTER)(obj, 0);

    int32_t ref = *reinterpret_cast<int32_t*>(base + OFF_LUA_REF);

    if (ref)
        reinterpret_cast<RawGetIFn>(ADDR_LUA_RAWGETI)(L, LUA_REGISTRYINDEX, ref);
    else
        FrameScript::PushNil(L);
}

void XMLExt::Dispatch(void* layout, XMLNode* node, bool pre)
{
    if (!layout || !node)
        return;

    const char* mixin = GetAttr(node, "mixin");
    const char* secureMixin = GetAttr(node, "secureMixin");

    // <KeyValues>
    std::string kv;

    if (XMLNode* kvs = FindChild(node, "KeyValues"))
    {
        for (XMLNode* c = NodeFirstChild(kvs); c; c = NodeNext(c))
        {
            const char* key = GetAttr(c, "key");

            if (!key || !*key)
                continue;

            AppendField(kv, key);
            AppendField(kv, GetAttr(c, "value"));
            AppendField(kv, GetAttr(c, "type"));
            kv += SEP_ENTRY;
        }
    }

    const char* parentArray = nullptr;
    const char* useParentLevel = nullptr;
    const char* atlas = nullptr;
    const char* useAtlasSize = nullptr;
    const char* textureSubLevel = nullptr;
    std::string scripts;

    if (!pre)
    {
        parentArray = GetAttr(node, "parentArray");
        useParentLevel = GetAttr(node, "useParentLevel");
        atlas = GetAttr(node, "atlas");
        useAtlasSize = GetAttr(node, "useAtlasSize");
        textureSubLevel = GetAttr(node, "textureSubLevel");
        if (textureSubLevel && (!*textureSubLevel || !strcmp(textureSubLevel, "0")))
            textureSubLevel = nullptr;

        // file="atlas: name" -> обрабатываем как atlas="name"
        if (!atlas || !*atlas)
        {
            atlas = nullptr;

            const char* file = GetAttr(node, "file");

            if (file && !_strnicmp(file, "atlas:", 6))
            {
                const char* p = file + 6;

                while (*p == ' ' || *p == '\t')
                    ++p;

                if (*p)
                    atlas = p;
            }
        }

        // <Scripts>
        if (XMLNode* sc = FindChild(node, "Scripts"))
        {
            for (XMLNode* c = NodeFirstChild(sc); c; c = NodeNext(c))
            {
                const char* name = NodeName(c);

                if (!name || !*name)
                    continue;

                const char* method = GetAttr(c, "method");
                const char* function = GetAttr(c, "function");
                const char* inherit = GetAttr(c, "inherit");

                if (!method && !function && !inherit)
                    continue;

                AppendField(scripts, name);
                AppendField(scripts, method);
                AppendField(scripts, function);
                AppendField(scripts, inherit);
                scripts += SEP_ENTRY;
            }
        }
    }

    bool hasPre = mixin || secureMixin || !kv.empty();
    bool hasPost = hasPre || parentArray || useParentLevel || atlas || textureSubLevel || !scripts.empty();

    if (pre ? !hasPre : !hasPost)
        return;

    lua_State* L = reinterpret_cast<GetCtxFn>(ADDR_GET_LUA_CONTEXT)();

    if (!L)
        return;

    void* obj = reinterpret_cast<void*>(reinterpret_cast<uint32_t>(layout) - LAYOUT_TO_OBJECT);

    auto getfield = reinterpret_cast<GetFieldFn>(ADDR_LUA_GETFIELD);
    auto pcall = reinterpret_cast<PCallFn>(ADDR_LUA_PCALL);

    auto pushOpt = [L](const char* s)
        {
            if (s && *s)
                FrameScript::PushString(L, s);
            else
                FrameScript::PushNil(L);
        };

    int32_t top = FrameScript::GetTop(L, 0);

    if (pre)
    {
        getfield(L, LUA_GLOBALSINDEX, "__XMLExt_Pre");
        PushScriptObject(L, obj);
        pushOpt(mixin);
        pushOpt(secureMixin);
        pushOpt(kv.c_str());
        pcall(L, 4, 0, 0);
    }
    else
    {
        void** vt = *reinterpret_cast<void***>(obj);
        void* parent = reinterpret_cast<void* (__thiscall*)(void*)>(vt[VT_GET_PARENT / 4])(obj);

        getfield(L, LUA_GLOBALSINDEX, "__XMLExt_Post");
        PushScriptObject(L, obj);
        PushScriptObject(L, parent);
        FrameScript::PushNil(L);            // parentKey — нативный
        pushOpt(parentArray);
        pushOpt(mixin);
        pushOpt(secureMixin);
        pushOpt(kv.c_str());
        pushOpt(useParentLevel);
        pushOpt(atlas);
        pushOpt(useAtlasSize);
        pushOpt(scripts.c_str());
        pushOpt(textureSubLevel);
        pcall(L, 12, 0, 0);
    }

    FrameScript::SetTop(L, top);
}

// ---------------- хуки ----------------
int32_t __fastcall XMLExt::FrameLoadXMLEx(void* layout, int32_t, XMLNode* node, void* status)
{
    Dispatch(layout, node, true);
    int32_t r = reinterpret_cast<LoadXMLFn>(ADDR_FRAME_LOADXML)(layout, node, status);
    Dispatch(layout, node, false);
    return r;
}

int32_t __fastcall XMLExt::TextureLoadXMLEx(void* layout, int32_t, XMLNode* node, void* status)
{
    Dispatch(layout, node, true);
    int32_t r = reinterpret_cast<LoadXMLFn>(ADDR_TEXTURE_LOADXML)(layout, node, status);
    Dispatch(layout, node, false);
    return r;
}

int32_t __fastcall XMLExt::FontStringLoadXMLEx(void* layout, int32_t, XMLNode* node, void* status)
{
    Dispatch(layout, node, true);
    int32_t r = reinterpret_cast<LoadXMLFn>(ADDR_FONTSTRING_LOADXML)(layout, node, status);
    Dispatch(layout, node, false);
    return r;
}

// ---------------- патчинг ----------------
static IMAGE_SECTION_HEADER* FindSection(const char* name, uint32_t& base)
{
    HMODULE exe = GetModuleHandleA(nullptr);
    base = reinterpret_cast<uint32_t>(exe);

    auto dos = reinterpret_cast<IMAGE_DOS_HEADER*>(exe);
    auto nt = reinterpret_cast<IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
    auto sec = IMAGE_FIRST_SECTION(nt);
    size_t len = strlen(name);

    for (uint16_t i = 0; i < nt->FileHeader.NumberOfSections; i++, sec++)
        if (!memcmp(sec->Name, name, len))
            return sec;

    return nullptr;
}

// все E8 rel32 в .text, которые зовут original
void XMLExt::PatchCallSites(uint32_t original, uint32_t hook)
{
    uint32_t base = 0;
    IMAGE_SECTION_HEADER* sec = FindSection(".text", base);

    if (!sec)
        return;

    uint32_t start = base + sec->VirtualAddress;
    uint32_t end = start + sec->Misc.VirtualSize - 5;

    for (uint32_t p = start; p <= end; p++)
    {
        if (*reinterpret_cast<uint8_t*>(p) != 0xE8)
            continue;

        uint32_t next = p + 5;
        int32_t rel = *reinterpret_cast<int32_t*>(p + 1);

        if (next + rel == original)
            Util::OverwriteUInt32AtAddress(p + 1, hook - next);
    }
}

// все ячейки vtable в .rdata, равные original
void XMLExt::PatchVTableEntries(uint32_t original, uint32_t hook)
{
    uint32_t base = 0;
    IMAGE_SECTION_HEADER* sec = FindSection(".rdata", base);

    if (!sec)
        return;

    uint32_t start = base + sec->VirtualAddress;
    uint32_t end = start + sec->Misc.VirtualSize - 4;

    for (uint32_t p = start; p <= end; p += 4)
        if (*reinterpret_cast<uint32_t*>(p) == original)
            Util::OverwriteUInt32AtAddress(p, hook);
}

void XMLExt::ApplyPatches()
{
    uint32_t f = reinterpret_cast<uint32_t>(&FrameLoadXMLEx);
    uint32_t t = reinterpret_cast<uint32_t>(&TextureLoadXMLEx);
    uint32_t s = reinterpret_cast<uint32_t>(&FontStringLoadXMLEx);

    // сначала call-сайты, потом vtable
    PatchCallSites(ADDR_FRAME_LOADXML, f);
    PatchCallSites(ADDR_TEXTURE_LOADXML, t);
    PatchCallSites(ADDR_FONTSTRING_LOADXML, s);

    PatchVTableEntries(ADDR_FRAME_LOADXML, f);
    PatchVTableEntries(ADDR_TEXTURE_LOADXML, t);
    PatchVTableEntries(ADDR_FONTSTRING_LOADXML, s);
}