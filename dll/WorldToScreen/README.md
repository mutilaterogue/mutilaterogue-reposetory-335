# WorldToScreen (WotLKExtensions patch)

`WorldToCamera(x, y, z)` for Lua: a world point in the space of the active camera
(`right, up, forward, fov`). Used by the pings (`Pings\Blizzard_Ping.lua`) to draw the marker over the
pinged point in the world; the projection to the screen is in Lua (`Ping_WorldToScreen`).

## Hooking it up
1. `WorldToScreen.hpp/.cpp` -> `WotLKExtensions/src/Client/`.
2. `CustomLua.cpp`, `RegisterFunctions()`:
   ```cpp
   AddToFunctionMap("WorldToCamera", &WorldToScreen::WorldToCamera);
   ```
   (`#include <Client/WorldToScreen.hpp>` at the top.)

## Check
```
/run print(WorldToCamera(0, 0, 0))                           -- four numbers: the function is there
/ping                                                         -- the marker should stand on the point
```
If the marker is off to a side or too far from the center, tune in `Pings\Blizzard_Ping.lua`:
`PING_FOV_FACTOR` (vertical field of view = camera fov * this) and `PING_SWAP_AXES`.
