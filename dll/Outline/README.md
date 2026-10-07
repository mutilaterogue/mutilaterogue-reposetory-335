# Outline (WotLKExtensions patch) — stage 1

Retail-like unit outline (Outline Mode) for 3.3.5a (12340). The method is taken from a client DLL that
already does it (its hooks and passes analysed), the code and the shaders are our own.

Stage 1 only checks the hard part: the target's and the mouseover's **silhouette in one color over everything**
(target red, mouseover yellow). No blur, no CVars yet.

## Files
| File | Where |
|---|---|
| `Outline.hpp/.cpp` | `WotLKExtensions/src/Outline/` |

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
| device vtable `DrawIndexedPrimitive` | with the flag: the same draw call once more right after the client's, with our pixel shader (`mov oC0, c0`; `ps_3_0` with a `vs_3_0` vertex shader, else `ps_2_0` - D3D9 doesn't mix 3.0 with older), no depth test |
| device vtable `SetRenderState`, `SetPixelShader`, `SetPixelShaderConstantF` | a copy of what Gx sends; after our draw call exactly that is put back (the client's device can't be read back with `Get*`) |
| `0x4F9240` inside the world render function, after the 3D scene (mid-function hook, trampoline) | once a frame: the models of the next frame (target red, mouseover yellow) |

No M2 / Gx function is ever called a second time: an earlier version re-ran `0x8203B0` and that broke the world
(sky, textures) through their caches.

## Debug: `/run print(OutlineDebug())`
| # | Value | Expected |
|---|---|---|
| 1 | hooks (bits: 1 batch, 2 world render, 4 device) | `7` |
| 2 | world render calls | grows |
| 3 | batch draws | grows a lot |
| 4 | models picked | `1`..`2` |
| 5 | their batches in the last frame | > 0 |
| 6 | silhouette draw calls in the last frame | = #5 or more |
| 7 | Gx API | `1` / `2` |
| 8 | error: 1 no D3D device, 2 shader | `0` |
| 9 | `OutlineMode` | |
| 10 | silhouette draw calls that went to the screen (back buffer) | = #6 |
| 11 | vertex shader model of the last silhouette (`3` -> our `ps_3_0` is used) | |
| 12 | 1: our `ps_3_0` exists | `1` |

`/run OutlineMode(n)`: `1` no extra draw (does the world stay fine without it?), `2` keep the depth test, `4` the silhouette writes depth and draws over everything (nothing drawn later can cover it).

## What to check
* Target an NPC / hover a unit: its model (with weapons) is filled red / yellow, over walls too; the rest of the world as usual.
* Crash: send the crash log.
