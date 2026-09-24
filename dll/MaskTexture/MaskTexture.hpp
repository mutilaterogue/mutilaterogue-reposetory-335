#pragma once

#include <SharedDefines.hpp>

// Retail-like mask textures for UI textures (Texture:AddMaskTexture).
//
// A mask is an ordinary Texture (the frame's CreateTexture) marked as a mask: it is not drawn,
// only its image and rect are used. A masked texture is drawn with the UIMask pixel shader
// (Shaders\Pixel\<profile>\UIMask.bls): color * mask alpha, the mask UV comes from constant c1.
//
// Hooks (3.3.5a 12340):
//   CSimpleTexture vtable slot 23 (Draw)  -> masks are not drawn
//   CSimpleBatch render (sub_484B00)      -> batching off for batches with masked textures
//   GxRsSet(PixelShader) in the render    -> UIMask shader + mask texture on stage 1 + c1
class MaskTexture
{
public:
    static void ApplyPatches();

    // registered in CustomLua::RegisterFunctions (AddToFunctionMap)
    static int32_t TextureAddMask(lua_State* L);
    static int32_t TextureRemoveMask(lua_State* L);
    static int32_t TextureGetMask(lua_State* L);
    static int32_t TextureSetIsMask(lua_State* L);
    static int32_t TextureMaskDebug(lua_State* L);

private:
    MaskTexture() = delete;
    ~MaskTexture() = delete;
};
