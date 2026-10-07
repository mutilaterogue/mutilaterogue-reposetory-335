# Outline (WotLKExtensions patch) — stage 2

Retail-like unit outline (Outline Mode) for 3.3.5a (12340): a soft rim around the target (red) and the
mouseover (yellow), over walls too. The method was taken from a client DLL that does it; the code and the shaders
are our own.

## Files
| File | Where |
|---|---|
| `Outline.hpp/.cpp`, `OutlineShaders.hpp` | `WotLKExtensions/src/Outline/` |
| `tools/sm3asm.py` | not built: the small shader model 3 assembler that made `OutlineShaders.hpp` |

## Hooking it up
1. `CMakeLists.txt`:
   ```cmake
   option(OUTLINE_EXTENSION "Retail-like unit outline (Outline Mode)" ON)
   ```
   `cmake/PatchConfig.hpp.in` (Lua functions block): `#cmakedefine01 OUTLINE_EXTENSION`
   (or `#define OUTLINE_EXTENSION 1` straight in `include/PatchConfig.hpp`).
2. `Main.hpp`: `#include <Outline/Outline.hpp>`
3. `Main.cpp`, `Main::Init()`, at the end:
   ```cpp
   #if OUTLINE_EXTENSION
       Outline::ApplyPatches();
   #endif
   ```
4. `CustomLua.cpp`, `RegisterFunctions()` (next to the `MASKTEXTURE_EXTENSION` block), and `#include <Outline/Outline.hpp>` there:
   ```cpp
   #if OUTLINE_EXTENSION
       AddToFunctionMap("OutlineDebug", &Outline::OutlineDebug);
       AddToFunctionMap("OutlineMode", &Outline::OutlineMode);
   #endif
   ```

Nothing to link: `d3d9.h` comes with the Windows SDK, only the device interface is used.

## How it works
| Hook | What it does |
|---|---|
| `0x8203B0` M2 batch draw (`__thiscall`) | a flag around the client's own draw of a batch of an outlined model (and its attachments, `model+0x48`; opaque / alpha key materials only) |
| device vtable `DrawIndexedPrimitive` | with the flag: the same draw call once more right after the client's, into our **mask** (a screen-sized texture), flat shader: the silhouette in its color |
| `0x4F9240` inside the world render function, after the 3D scene (mid-function hook, trampoline) | one full-screen pass: 16 mask samples on two rings (1.5 / 3 px; 8 on one ring in low quality) = the halo, minus the mask itself = the rim, alpha blended; the mask cleared; the models of the next frame picked |
| device vtable `SetRenderState`, `SetViewport`, `SetTexture`, `SetSamplerState`, `SetVertexDeclaration`, `SetFVF`, `SetVertexShader`, `SetStreamSource`, `SetPixelShader`, `SetPixelShaderConstantF` | a copy of what Gx sends; after our draws exactly that is put back (the client's device can't be read back with `Get*`) |
| device vtable `Reset` | the mask (a default pool texture) released first |

No M2 / Gx function is ever called a second time: re-running `0x8203B0` broke the world (sky, textures) through
their caches. The client's vertex shaders are `vs_3_0`, so the pixel shaders are `ps_3_0` (a `ps_2_0` with them
draws nothing).

## Debug: `/run print(OutlineDebug())`
| # | Value | Expected |
|---|---|---|
| 1 | hooks (bits: 1 batch, 2 world render, 4 device) | `7` |
| 2 | world render calls | grows |
| 3 | batch draws | grows a lot |
| 4 | models picked | `1`..`2` |
| 5 | their batches in the last frame | > 0 |
| 6 | silhouette draw calls in the last frame | = #5 |
| 7 | Gx API | `1` / `2` |
| 8 | error: 1 no D3D device, 2 flat shader, 3 mask texture, 4 quad buffer, 5 outline shader, 6 low outline shader, 7 quad vertex shader, 8 vertex declaration | `0` |
| 9 | `OutlineMode` | |
| 10 | full-screen passes done | grows |
| 11, 12 | mask size | the screen size |

`/run OutlineMode(n)`: `1` no silhouettes, `2` no full-screen pass, `4` low quality (8 samples),
`8` stage 1 (the silhouettes straight on the screen). Add them up.

## What to check
* Target an NPC / hover a unit: a red / yellow rim around the model (weapons too); the model itself as usual.
* `OutlineMode(4)`: a thinner, cheaper rim.
* Alt+Tab / a resolution change: no crash, the rim still there.
