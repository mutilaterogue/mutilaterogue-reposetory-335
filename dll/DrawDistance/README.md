# DrawDistance (WotLKExtensions patch)

Raises the client's limits on the grass and small objects draw distance.

| CVar | Client max | Now |
|---|---|---|
| `groundEffectDist` | 140 | 500 |
| `environmentDetail` (doodad distance multiplier) | 1.5 | 5 |

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
