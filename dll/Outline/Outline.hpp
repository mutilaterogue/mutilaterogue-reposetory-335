#pragma once

// Retail-like unit outline (Outline Mode) for 3.3.5a (12340). Stage 1: the silhouette.
//
// How it works:
//  * 0x8203B0 - the client draws one M2 batch (__thiscall, the batch record). For a batch of an outlined model
//    (or of its attachments: model+0x48 parent chain) a flag is set around the original call.
//  * IDirect3DDevice9::DrawIndexedPrimitive (vtable) - with that flag set, the same draw call is issued once more
//    right after the client's, with our flat pixel shader: the unit's silhouette in its current pose. No M2 / Gx
//    function is called a second time (that changes their caches). Gx's states are put back from a copy of what
//    it sent (SetRenderState / SetPixelShader / SetPixelShaderConstantF hooked): the device can't be read back.
//  * 0x4F9240 - inside the world render function, after the 3D scene (mid-function hook): once a frame, the
//    models of the next frame are picked (target, mouseover).
// Stage 1 draws the silhouette straight on the screen in one color (target red, mouseover yellow).
// Stage 2: the silhouettes into a texture + blur (halo) + union -> a real outline. Stage 3: CVars, colors, Lua.

#include <cstdint>

struct lua_State;

class Outline
{
public:
    static void ApplyPatches();

    // Lua: OutlineDebug() - the counters of every step (README)
    static int32_t OutlineDebug(lua_State* L);
    // Lua: OutlineMode(bits) - test switches (Outline.cpp, s_mode)
    static int32_t OutlineMode(lua_State* L);

private:
    Outline() = delete;
    ~Outline() = delete;
};
