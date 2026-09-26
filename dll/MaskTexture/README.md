# MaskTexture (WotLKExtensions patch)

Retail-like `MaskTexture` for 3.3.5a (12340): a texture drawn through the alpha of up to 3 other textures.
Works with atlases, `SetTexCoord` crops and rotations (8 texcoords), `SetDesaturated`, and the retail
`<MaskTexture>` XML tag.

## Files
| File | Where |
|---|---|
| `MaskTexture.hpp/.cpp` | `WotLKExtensions/src/Client/` |
| `../XMLExt/XMLExt.hpp/.cpp` | `WotLKExtensions/src/Client/` (replaces yours: `<MaskTexture>` tag) |
| `../XMLExt/XMLExt.lua` | `Interface\FrameXML\XMLExt.lua` (replaces yours: the mask Lua API is at its end) |
| `Shaders/Pixel/ps_3_0/UIMask1..3.bls`, `UIMaskDesaturate1..3.bls` | patch MPQ `shaders\Pixel\ps_3_0\` |
| `Shaders/Pixel/ps_2_0/...` (same names) | patch MPQ `shaders\Pixel\ps_2_0\` (older cards, untested) |
| `MaskTextureTest.lua/.xml` | optional test page, see below |

The shaders come from `tools/blsmask.py` (it also rebuilds the client's `UI.bls` byte for byte as a check).
The old `UIMask.bls` / `UIMaskDesaturate.bls` / `UIMaskDebug*.bls` are not used any more.

## Hooking it up
1. `include/PatchConfig.hpp` / `cmake/PatchConfig.hpp.in` / `CMakeLists.txt`: `MASKTEXTURE_EXTENSION` like `XMLEXTENSION`.
2. `Main.cpp`, `Main::Init()` only (not `OnAttach`, `Init` is called from it):
   ```cpp
   #if MASKTEXTURE_EXTENSION
       MaskTexture::ApplyPatches();
   #endif
   ```
3. `CustomLua.cpp`, `RegisterFunctions()` (`OOBLUAFUNCTIONS_PATCH` on):
   ```cpp
   #if MASKTEXTURE_EXTENSION
       AddToFunctionMap("TextureAddMask", &MaskTexture::TextureAddMask);
       AddToFunctionMap("TextureRemoveMask", &MaskTexture::TextureRemoveMask);
       AddToFunctionMap("TextureSetIsMask", &MaskTexture::TextureSetIsMask);
   #endif
   ```

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
```xml
<Texture parentKey="Icon" file="Interface\Icons\INV_Misc_QuestionMark" setAllPoints="true"/>
<MaskTexture parentKey="CircleMask" file="Interface\CharacterFrame\TempPortraitAlphaMask" setAllPoints="true">
    <MaskedTextures>
        <MaskedTexture childKey="Icon"/>
    </MaskedTextures>
</MaskTexture>
```

## Test page
Add `MaskTextureTest.xml` and `MaskTextureTest.lua` to the toc (anywhere after `Utils\MaskTexture.lua`),
`/masktest`: circle, desaturated, rotated 45°, two masks (a lens), cropped texcoords, the XML tag.

## Limits
- up to 3 masks per texture (more are kept, not drawn); the mask itself is not rotated
- a mask must stay shown (it is never drawn); outside its rect it repeats its edge pixels
- D3D9 only (not OpenGL)

## How it works
- masks are not drawn: `CSimpleTexture` vtable slot 23 (`Draw`)
- the `UIMask<n>` shaders are created with the client's UI shaders (`sub_483060`); a shader created
  in the middle of a frame is not drawn
- a batch with a masked texture is rendered without merging (`dword_B47948`), and for the masked
  item the pixel shader (`RsSet(78)` in `sub_484B00`) becomes `UIMask<n>`, the masks go to texture
  stages 1..n and each mask's UV map (3 constants: `uv.x * A + uv.y * B + C`) to `c1..c9`
