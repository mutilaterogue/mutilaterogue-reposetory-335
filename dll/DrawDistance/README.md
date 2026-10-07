# DrawDistance (WotLKExtensions patch)

Raises the client's limits on the grass and small objects draw distance, and sets the fog.

| CVar | Client max | Now |
|---|---|---|
| `groundEffectDist` | 140 | 500 |
| `environmentDetail` (doodad distance multiplier) | 1.5 | 5 |

## Fog: `fogMode`
`0` the client's, `1` three times farther, `2` none. `/console fogMode 2`.
For `Config.wtf` to keep it, in `CVar::FillCustomGlueCVarVector()`:
```cpp
    AddToGlueCVarVector("fogMode", "Fog: 0 normal, 1 farther, 2 none", 1, "0", nullptr, 5, false, 0, false);
```
Hooks: `0x7816F0` (once a frame, lights the world; the zone light's result `0xD38B00`: `+0x90` fog start,
`+0x94` fog end - ours after it, the client's back before its next run) and `0x834990`
`CM2Lighting::SetFog` (the map objects' own fog, interiors).

## Hooking it up
1. Copy `DrawDistance.hpp/.cpp` to `WotLKExtensions/src/DrawDistance/`.
2. `Main.hpp`: `#include <DrawDistance/DrawDistance.hpp>`
3. `CMakeLists.txt`: `option(DRAWDISTANCE_EXTENSION ...)`, `cmake/PatchConfig.hpp.in`: `#cmakedefine01 DRAWDISTANCE_EXTENSION`
4. `Main.cpp`, `Main::Init()`:
   ```cpp
   #if DRAWDISTANCE_EXTENSION
       DrawDistance::ApplyPatches();
   #endif
   ```

## Check
`/console groundEffectDist 300`, `/console environmentDetail 3` - the grass and the doodads reach farther.
The values are saved to `Config.wtf` (the client's own CVars).
