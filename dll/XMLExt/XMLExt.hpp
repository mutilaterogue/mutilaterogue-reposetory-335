#pragma once

#include <cstdint>

struct XMLNode;
struct lua_State;

class XMLExt
{
public:
    static void ApplyPatches();

private:
    XMLExt() = delete;
    ~XMLExt() = delete;

    static int32_t __fastcall FrameLoadXMLEx(void* layout, int32_t unused, XMLNode* node, void* status);
    static int32_t __fastcall TextureLoadXMLEx(void* layout, int32_t unused, XMLNode* node, void* status);
    static int32_t __fastcall FontStringLoadXMLEx(void* layout, int32_t unused, XMLNode* node, void* status);

    static const char* GetAttr(XMLNode* node, const char* name);
    static void PushScriptObject(lua_State* L, void* obj);
    static void Dispatch(void* layout, XMLNode* node, bool pre);
    static void DispatchMask(void* layout, XMLNode* node);
    static void DispatchResolveMasks(void* layout);

    static void PatchCallSites(uint32_t original, uint32_t hook);
    static void PatchVTableEntries(uint32_t original, uint32_t hook);
};