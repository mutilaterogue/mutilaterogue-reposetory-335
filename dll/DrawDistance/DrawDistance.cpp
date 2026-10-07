#include <DrawDistance/DrawDistance.hpp>
#include <Misc/Util.hpp>

#include <cstdint>

namespace
{
    constexpr uint32_t ADDR_GROUND_EFFECT_DIST_MAX = 0x78DB2F;    // operand of fld [0x9E8CFC] (140.0)
    constexpr uint32_t ADDR_ENVIRONMENT_DETAIL_MAX = 0x78DC7F;    // operand of fld [0xA41B18] (1.5)

    // grass only grows on the loaded map chunks: far beyond ~500 yards there is nothing more to show
    float s_groundEffectDistMax = 500.0f;
    float s_environmentDetailMax = 5.0f;
}

void DrawDistance::ApplyPatches()
{
    Util::OverwriteUInt32AtAddress(ADDR_GROUND_EFFECT_DIST_MAX, reinterpret_cast<uint32_t>(&s_groundEffectDistMax));
    Util::OverwriteUInt32AtAddress(ADDR_ENVIRONMENT_DETAIL_MAX, reinterpret_cast<uint32_t>(&s_environmentDetailMax));
}
