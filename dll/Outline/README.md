# Outline (WotLKExtensions patch) — stage 3

Retail-like unit outline (Outline Mode) for 3.3.5a (12340): a soft rim around the target, the mouseover,
the bosses around and your own character, over walls too. The color is the unit's reaction, whatever made it
outlined: hostile red, neutral yellow, friendly green, friendly players blue. The method was taken from a client DLL that does it; the code and the shaders
are our own.

## Files
| File | Where |
|---|---|
| `Outline.hpp/.cpp`, `OutlineShaders.hpp` | `WotLKExtensions/src/Outline/` |
| `tools/sm3asm.py` | not built: the small shader model 3 assembler that made `OutlineShaders.hpp` (the fallback when Windows' `d3dcompiler_47.dll` isn't there: the HLSL in `Outline.cpp` is compiled at run time) |

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
       AddToFunctionMap("SetUnitOutline", &Outline::SetUnitOutline);
       AddToFunctionMap("ClearUnitOutline", &Outline::ClearUnitOutline);
   #endif
   ```

Nothing to link: `d3d9.h` comes with the Windows SDK, only the device interface is used.

## CVars (the options panel XML: `InterfaceOptionsDisplayPanelOutline*`)
| CVar | Default | |
|---|---|---|
| `OutlineQuality` | `1` | `0` off, `1` on, `2` on, low quality (8 samples) |
| `OutlineTarget` | `1` | the target |
| `OutlineMouseover` | `1` | the unit under the mouse |
| `OutlineQuestBoss` | `1` | the bosses around (world boss rank, within the nameplate distance). Quest units: not yet - the client has no simple "is a quest objective" |
| `OutlinePlayer` | `0` | your own character |
| `OutlineAll` | `0` | always outlined, within the nameplate distance: `1` every unit, `2` hostile, `3` friendly, `4` players, `5` creatures (up to 64 models a frame; a dropdown in the panel) |
| `OutlineThickness` | `1` | `0.5` .. `3` |
| `OutlineStrength` | `1` | opacity `0` .. `1` |

Add them to `CVar::FillCustomGlueCVarVector()` (`src/Client/CVar.cpp`), so they are registered before
`Config.wtf` is read and the saved values are kept:
```cpp
    AddToGlueCVarVector("OutlineQuality", "Outline: 0 off, 1 on, 2 low quality", 1, "1", nullptr, 5, false, 0, false);
    AddToGlueCVarVector("OutlinePlayer", "Outline your own character", 1, "0", nullptr, 5, false, 0, false);
    AddToGlueCVarVector("OutlineTarget", "Outline your target", 1, "1", nullptr, 5, false, 0, false);
    AddToGlueCVarVector("OutlineMouseover", "Outline the unit under the mouse", 1, "1", nullptr, 5, false, 0, false);
    AddToGlueCVarVector("OutlineQuestBoss", "Outline bosses around you", 1, "1", nullptr, 5, false, 0, false);
    AddToGlueCVarVector("OutlineThickness", "Outline thickness (0.5 .. 3)", 1, "1", nullptr, 5, false, 0, false);
    AddToGlueCVarVector("OutlineStrength", "Outline opacity (0 .. 1)", 1, "1", nullptr, 5, false, 0, false);
    AddToGlueCVarVector("OutlineAll", "Outline every unit around: 0 off, 1 all, 2 hostile, 3 friendly, 4 players, 5 creatures", 1, "0", nullptr, 5, false, 0, false);
```
Without them the DLL registers them in the world (the first frame), and the values are not kept across restarts.
Your XML's texts, if `GlobalStrings` lacks them:
```lua
OUTLINE_ENABLE = "Обводка моделей";
OUTLINE_PLAYER = "Свой персонаж";
OUTLINE_TARGET = "Цель";
OUTLINE_MOUSEOVER = "Под курсором";
OUTLINE_QUEST = "Боссы";
```

## Lua
* `SetUnitOutline(unit, r, g, b)` — an outline of its own color for any unit (`"target"`, `"party1"`, ...), until
* `ClearUnitOutline(unit)` / `ClearUnitOutline()` (every one).

## How it works
| Hook | What it does |
|---|---|
| `0x8203B0` M2 batch draw (`__thiscall`) | a flag around the client's own draw of a batch of an outlined model (and its attachments, `model+0x48`; opaque / alpha key materials only) |
| device vtable `DrawIndexedPrimitive` | with the flag: the same draw call once more right after the client's, into our **mask** (a screen-sized texture), flat shader: the silhouette in its color |
| `0x4F9240` inside the world render function, after the 3D scene (mid-function hook, trampoline) | one full-screen pass: 16 mask samples on two rings (1.5 / 3 px × `OutlineThickness`; 8 on one ring in low quality) = the halo, minus the mask itself = the rim, alpha blended; the mask cleared; the units of the next frame picked by the CVars, colored by reaction (`CGUnit_C::UnitReaction` `0x7251C0`, `CanAttack` `0x729A70`), bosses from `ClntObjMgrEnumVisibleObjects` `0x4D4B30` + `GetCreatureRank` `0x718A00` |
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
| 13 | 1: the shaders came from Windows' HLSL compiler (`d3dcompiler_47.dll`), 0: the bytecode of `OutlineShaders.hpp` | `1` |
| 14 | the compiler's error message, if any | `-` |

`/run OutlineMode(n)`: `1` no silhouettes, `2` no full-screen pass, `4` low quality (8 samples),
`8` stage 1 (the silhouettes straight on the screen). Add them up.

## What to check
* Target / hover a hostile mob: red; a neutral one: yellow; a friendly NPC: green; a friendly player: blue.
* `/console OutlineTarget 0` and the others; `/console OutlineThickness 2`; `/console OutlineQuality 0` (off).
* `/run SetUnitOutline("target", 0.6, 0.2, 1)`: purple, `/run ClearUnitOutline()`.
* `OutlineMode(4)`: a thinner, cheaper rim.
* Alt+Tab / a resolution change: no crash, the rim still there.
