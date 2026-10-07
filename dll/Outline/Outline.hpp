#pragma once

// Retail-like unit outline (Outline Mode) for 3.3.5a (12340). Stage 2: the outline.
//
//  * 0x8203B0 - the client draws one M2 batch (__thiscall). For a batch of an outlined model (or of its
//    attachments: model+0x48 parent chain) a flag is set around the original call.
//  * IDirect3DDevice9::DrawIndexedPrimitive (vtable) - with that flag set, the same draw call is issued once more
//    right after the client's, into our mask texture, with a flat pixel shader: the silhouette in its color.
//    No M2 / Gx function is called a second time (that changes their caches).
//  * 0x4F9240 - inside the world render function, after the 3D scene (mid-function hook): one full-screen pass,
//    the mask's halo minus the mask -> the rim, alpha blended over the screen; the mask cleared; the models of the
//    next frame picked (target, mouseover).
//  * the device states Gx sends are copied as they go (vtable hooks) and put back after our draws: Gx's cache and
//    the device never disagree (the client's device can't be read back with Get*).
// The shaders: OutlineShaders.hpp (tools/sm3asm.py). Stage 3: CVars, colors by reaction, Lua.

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
