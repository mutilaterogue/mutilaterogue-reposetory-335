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
   #endif
   ```

Nothing to link: `d3d9.h` comes with the Windows SDK, only the device interface is used.

## How it works
| Wow.exe | What we do |
|---|---|
| `0x8203B0` M2 batch draw (`__thiscall`, record 0xBC bytes) | after the normal draw: copy the batches of the outlined models (and their attachments, `model+0x48`) |
| `0x4F9240` near the end of the world frame | before it: draw the copies again with our pixel shader (`mov oC0, c0`), then pick the models of the next frame |
| `0x6A3620`, `0x6A77C0` (`CGxDeviceD3d`) | muted (`ret 8`) during that redraw, so the batch can't put its own shader back |

The D3D device: `[[0xC5DF88] + 0x397C]` (only when the Gx API `[+0x1B4]` is Direct3D).
All D3D states are restored after the redraw (state block).

## Debug: `/run print(OutlineDebug())`
Target a unit and hover another one, then run it. Nine numbers:

| # | Value | Expected |
|---|---|---|
| 1 | hooks installed (bits: 1 batch, 2 world render, 4 mute A, 8 mute B) | `15` |
| 2 | world render hook calls | grows every run |
| 3 | batch hook calls | grows a lot |
| 4 | models picked (target + mouseover) | `1` or `2` |
| 5 | batches of those models seen | grows |
| 6 | batches kept in the last frame | > 0 |
| 7 | batches drawn again in the last frame | = #6 |
| 8 | Gx API | `1` or `2` (Direct3D) |
| 9 | error: 1 no D3D device, 2 shader, 3 state block | `0` |

## What to check
* Target an NPC / hover a unit: its model (with weapons) is filled red / yellow, over walls too.
* Crash: send the crash log (address + stack). Nothing at all: tell me, there are a few switches to try.
