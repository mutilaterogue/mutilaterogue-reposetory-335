#include <Client/WorldToScreen.hpp>

#include <Windows.h>
#include <cstdint>

// All addresses: 3.3.5a (12340).
namespace
{
    constexpr uint32_t ADDR_WORLD_FRAME = 0xB7436C;     // CGWorldFrame*
    constexpr uint32_t OFF_ACTIVE_CAMERA = 0x7E20;      // CameraInfo* in the world frame
    constexpr uint32_t CAM_POSITION = 0x08;             // float[3]
    constexpr uint32_t CAM_MATRIX = 0x14;               // float[9]: forward, left, up
    constexpr uint32_t CAM_FOV = 0x40;                  // float, radians

    constexpr uint32_t ADDR_LUA_TONUMBER = 0x84E030;    // double __cdecl lua_tonumber(lua_State*, int)
    constexpr uint32_t ADDR_LUA_PUSHNUMBER = 0x84E2A0;  // void __cdecl lua_pushnumber(lua_State*, double)
    constexpr uint32_t ADDR_LUA_PUSHNIL = 0x84E280;     // void __cdecl lua_pushnil(lua_State*)

    using ToNumberFn = double(__cdecl*)(lua_State*, int);
    using PushNumberFn = void(__cdecl*)(lua_State*, double);
    using PushNilFn = void(__cdecl*)(lua_State*);

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
