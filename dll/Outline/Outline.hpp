#pragma once

// Retail-like unit outline (Outline Mode) for 3.3.5a (12340). Stage 1: the silhouette.
//
// How it works (the same points the retail-style Client.dll uses):
//  * 0x8203B0 - draws one M2 batch (__thiscall, the batch record is 0xBC bytes). After the normal draw,
//    the batches of the outlined models (and their attachments: model+0x48 parent chain) are copied.
//  * 0x4F9240 - near the end of the world frame. Before it runs, the copied batches are drawn again
//    with our flat pixel shader: the unit's silhouette in its current pose.
//  * 0x6A3620, 0x6A77C0 - CGxDeviceD3d functions muted during that replay, so the batch can't put
//    its own shader / states back over ours.
// Stage 1 draws the silhouette straight on the screen in one color (target, mouseover).
// Stage 2: render target + blur (halo) + union -> a real outline. Stage 3: CVars, colors, Lua.

#include <cstdint>

struct lua_State;

class Outline
{
public:
    static void ApplyPatches();

    // Lua: OutlineDebug() - the counters of every step (README)
    static int32_t OutlineDebug(lua_State* L);

private:
    Outline() = delete;
    ~Outline() = delete;
};
