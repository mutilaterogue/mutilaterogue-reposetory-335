#include <Client/WorldToScreen.hpp>

#include <Windows.h>
#include <cmath>
#include <cstdint>

// All addresses: 3.3.5a (12340).
namespace
{
    constexpr uint32_t ADDR_WORLD_FRAME = 0xB7436C;     // CGWorldFrame*
    constexpr uint32_t OFF_ACTIVE_CAMERA = 0x7E20;      // CameraInfo* in the world frame
    constexpr uint32_t CAM_POSITION = 0x08;             // float[3]
    constexpr uint32_t CAM_MATRIX = 0x14;               // float[9]: forward, left, up
    constexpr uint32_t CAM_FOV = 0x40;                  // float, radians

    constexpr uint32_t ADDR_TRACE_LINE = 0x7A3B70;      // world intersect (click to move, line of sight)
    constexpr uint32_t TRACE_FLAGS = 0x120171;          // terrain, WMO, liquid... (the flags of the client's ground click)

    constexpr uint32_t ADDR_LUA_TONUMBER = 0x84E030;    // double __cdecl lua_tonumber(lua_State*, int)
    constexpr uint32_t ADDR_LUA_PUSHNUMBER = 0x84E2A0;  // void __cdecl lua_pushnumber(lua_State*, double)
    constexpr uint32_t ADDR_LUA_PUSHNIL = 0x84E280;     // void __cdecl lua_pushnil(lua_State*)

    using ToNumberFn = double(__cdecl*)(lua_State*, int);
    using PushNumberFn = void(__cdecl*)(lua_State*, double);
    using PushNilFn = void(__cdecl*)(lua_State*);

    struct Vec3
    {
        float x, y, z;
    };
    using TraceLineFn = bool(__cdecl*)(Vec3* start, Vec3* end, Vec3* hit, float* fraction, uint32_t flags, int32_t optional);

    template <typename T>
    T Read(uint32_t address)
    {
        return *reinterpret_cast<T*>(address);
    }

    uint32_t ActiveCamera()
    {
        uint32_t worldFrame = Read<uint32_t>(ADDR_WORLD_FRAME);
        if (!worldFrame)
            return 0;
        return Read<uint32_t>(worldFrame + OFF_ACTIVE_CAMERA);
    }
}

int32_t WorldToScreen::WorldToCamera(lua_State* L)
{
    auto toNumber = reinterpret_cast<ToNumberFn>(ADDR_LUA_TONUMBER);
    auto pushNumber = reinterpret_cast<PushNumberFn>(ADDR_LUA_PUSHNUMBER);
    auto pushNil = reinterpret_cast<PushNilFn>(ADDR_LUA_PUSHNIL);

    uint32_t camera = ActiveCamera();
    if (!camera)
    {
        pushNil(L);
        return 1;
    }

    float const* pos = reinterpret_cast<float const*>(camera + CAM_POSITION);
    float const* m = reinterpret_cast<float const*>(camera + CAM_MATRIX);
    float dx = float(toNumber(L, 1)) - pos[0];
    float dy = float(toNumber(L, 2)) - pos[1];
    float dz = float(toNumber(L, 3)) - pos[2];

    float forward = dx * m[0] + dy * m[1] + dz * m[2];
    float left = dx * m[3] + dy * m[4] + dz * m[5];
    float up = dx * m[6] + dy * m[7] + dz * m[8];

    pushNumber(L, -left);
    pushNumber(L, up);
    pushNumber(L, forward);
    pushNumber(L, Read<float>(camera + CAM_FOV));
    return 4;
}

int32_t WorldToScreen::CameraTraceLine(lua_State* L)
{
    auto toNumber = reinterpret_cast<ToNumberFn>(ADDR_LUA_TONUMBER);
    auto pushNumber = reinterpret_cast<PushNumberFn>(ADDR_LUA_PUSHNUMBER);
    auto pushNil = reinterpret_cast<PushNilFn>(ADDR_LUA_PUSHNIL);

    uint32_t camera = ActiveCamera();
    if (!camera)
    {
        pushNil(L);
        return 1;
    }

    float const* pos = reinterpret_cast<float const*>(camera + CAM_POSITION);
    float const* m = reinterpret_cast<float const*>(camera + CAM_MATRIX);
    float right = float(toNumber(L, 1));
    float up = float(toNumber(L, 2));
    float forward = float(toNumber(L, 3));
    float maxDistance = float(toNumber(L, 4));
    if (maxDistance <= 0.0f)
        maxDistance = 200.0f;

    // camera space -> world: forward * row0 + left * row1 + up * row2 (left = -right)
    Vec3 dir = {
        forward * m[0] - right * m[3] + up * m[6],
        forward * m[1] - right * m[4] + up * m[7],
        forward * m[2] - right * m[5] + up * m[8],
    };
    float length = std::sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z);
    if (length < 0.0001f)
    {
        pushNil(L);
        return 1;
    }

    Vec3 start = { pos[0], pos[1], pos[2] };
    Vec3 end = {
        start.x + dir.x / length * maxDistance,
        start.y + dir.y / length * maxDistance,
        start.z + dir.z / length * maxDistance,
    };
    Vec3 hit = { 0.0f, 0.0f, 0.0f };
    float fraction = 1.0f;
    if (!reinterpret_cast<TraceLineFn>(ADDR_TRACE_LINE)(&start, &end, &hit, &fraction, TRACE_FLAGS, 0))
    {
        pushNil(L);
        return 1;
    }

    pushNumber(L, hit.x);
    pushNumber(L, hit.y);
    pushNumber(L, hit.z);
    return 3;
}
