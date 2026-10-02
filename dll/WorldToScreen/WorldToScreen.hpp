#pragma once

#include <SharedDefines.hpp>

// WorldToCamera(x, y, z) for Lua (3.3.5a 12340): the point in the space of the active camera.
//   returns right, up, forward (yards), fov (radians, the camera's) - nil without a camera.
// The projection to the screen is done in Lua (Pings\Blizzard_Ping.lua, WorldToScreen), so the field of
// view constant can be tuned there without rebuilding the dll.
//
// Camera (known 3.3.5a addresses): CGWorldFrame* at 0xB7436C, its active CameraInfo* at +0x7E20;
// CameraInfo: +0x08 position (3 floats), +0x14 3x3 matrix (rows: forward, left, up), +0x40 fov.
// TraceLine (0x7A3B70): bool __cdecl (C3Vector* start, C3Vector* end, C3Vector* hit, float* fraction, uint flags, int).
class WorldToScreen
{
public:
    // registered in CustomLua::RegisterFunctions (AddToFunctionMap)
    static int32_t WorldToCamera(lua_State* L);
    // CameraTraceLine(right, up, forward, maxDistance): a ray from the camera along this direction (camera space)
    // against the terrain and the buildings -> x, y, z of the hit, nil when nothing is hit
    static int32_t CameraTraceLine(lua_State* L);

private:
    WorldToScreen() = delete;
    ~WorldToScreen() = delete;
};
