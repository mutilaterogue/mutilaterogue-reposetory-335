#pragma once

#include <SharedDefines.hpp>

// Retail-like mask textures for UI textures (Texture:AddMaskTexture, <MaskTexture> in XML).
//
// A mask is an ordinary Texture marked as a mask: it is not drawn, only its image and rect are used.
// A masked texture is drawn with the UIMask<n> pixel shader (Shaders\Pixel\<profile>\UIMask<n>.bls,
// tools/blsmask.py): color * the alpha of up to 3 masks, each mask UV an affine map of the texture UV
// (shader constants), so texcoord rotation, flips, atlases and crops work.
//
// Hooks (3.3.5a 12340):
//   CSimpleTexture vtable slot 23 (Draw)   -> masks are not drawn
//   sub_483060 (UI shaders create)         -> the mask shaders are created with the client's
//   CSimpleBatch render (sub_484B00)       -> batching off for batches with masked textures
//   CGxDevice::RsSet(PixelShader) in it    -> mask shader + masks on stages 1..3 + constants c1..c9
class MaskTexture
{
public:
    static void ApplyPatches();

    // registered in CustomLua::RegisterFunctions (AddToFunctionMap)
    static int32_t TextureAddMask(lua_State* L);
    static int32_t TextureRemoveMask(lua_State* L);
    static int32_t TextureSetIsMask(lua_State* L);

private:
    MaskTexture() = delete;
    ~MaskTexture() = delete;
};
