# WorldToScreen (WotLKExtensions patch)

`WorldToCamera(x, y, z)` for Lua: a world point in the space of the active camera
(`right, up, forward, fov`). Used by the pings (`Pings\Blizzard_Ping.lua`) to draw the marker over the
pinged point in the world; the projection to the screen is in Lua (`Ping_WorldToScreen`).

## Hooking it up
1. `WorldToScreen.hpp/.cpp` -> `WotLKExtensions/src/Client/`.
2. `CustomLua.cpp`, `RegisterFunctions()`:
   ```cpp
   AddToFunctionMap("WorldToCamera", &WorldToScreen::WorldToCamera);
   AddToFunctionMap("CameraTraceLine", &WorldToScreen::CameraTraceLine);
   ```
   (`#include <Client/WorldToScreen.hpp>` at the top.)

`CameraTraceLine(right, up, forward, maxDistance)`: a ray from the camera (camera space direction) through the
client's TraceLine -> the world point under the cursor (`Ping_CursorWorldPosition` in Blizzard_Ping.lua).

## Check
```
/run print(Ping_CursorWorldPosition())                        -- the point under the cursor (x, y, z)
```
```
/run print(WorldToCamera(0, 0, 0))                           -- four numbers: the function is there
/ping                                                         -- the marker should stand on the point
```
If the marker drifts from the point when the camera turns (too close to / too far from the center), tune
`PING_FOV_FACTOR` in `Pings\Blizzard_Ping.lua` (vertical field of view = camera fov * this, 0.6109 by default):
`/run PING_FOV_FACTOR = 0.7` and ping again.
