# MaskTexture (WotLKExtensions patch)

Retail-like `MaskTexture` for 3.3.5a (12340): a texture drawn through the alpha of another texture.

## Files
- `MaskTexture.hpp/.cpp` -> `WotLKExtensions/src/Client/`
- `MaskTexture.lua` -> FrameXML (after the frame code, e.g. at the end of FrameXML.toc)
- `Shaders/Pixel/ps_3_0/UIMask.bls`, `UIMaskDesaturate.bls` (+ the ps_2_0 copies) -> patch MPQ
  (`tools/blsmask.py` builds them)

## Hooking it up
1. `include/PatchConfig.hpp` / `cmake/PatchConfig.hpp.in` / `CMakeLists.txt`: add `MASKTEXTURE_EXTENSION` like `XMLEXTENSION`.
2. `Main.cpp`, `Main::Init()`:
   ```cpp
   #if MASKTEXTURE_EXTENSION
       MaskTexture::ApplyPatches();
   #endif
   ```
3. `CustomLua.cpp`, `RegisterFunctions()`:
   ```cpp
   #if MASKTEXTURE_EXTENSION
       AddToFunctionMap("TextureAddMask", &MaskTexture::TextureAddMask);
       AddToFunctionMap("TextureRemoveMask", &MaskTexture::TextureRemoveMask);
       AddToFunctionMap("TextureGetMask", &MaskTexture::TextureGetMask);
       AddToFunctionMap("TextureSetIsMask", &MaskTexture::TextureSetIsMask);
       AddToFunctionMap("TextureMaskDebug", &MaskTexture::TextureMaskDebug);
       AddToFunctionMap("TextureMaskDebugFlags", &MaskTexture::TextureMaskDebugFlags);
       AddToFunctionMap("TextureMaskDumpShaders", &MaskTexture::TextureMaskDumpShaders);
   #endif
   ```
   (`OOBLUAFUNCTIONS_PATCH` must be on.)

## Usage
```lua
local icon = frame:CreateTexture(nil, "ARTWORK")
icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
icon:SetAllPoints()
local mask = frame:CreateMaskTexture()
mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
mask:SetAllPoints(icon)
icon:AddMaskTexture(mask)
```

## Limits
- one mask per texture; no SetRotation on masked textures
- the mask must stay shown (it is never drawn)
- D3D9 only (not OpenGL)
