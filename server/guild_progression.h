#ifndef CIRCLE_GUILD_PROGRESSION_H
#define CIRCLE_GUILD_PROGRESSION_H

// Guild progression (guild_progression.cpp): for the GM commands (.guild level ...)
#include "Define.h"

namespace GuildProgression
{
    struct Info
    {
        uint8 Level = 1;
        uint64 Experience = 0;      // toward the next level
        uint64 ToNextLevel = 0;
        uint64 Today = 0;
        uint64 DailyCap = 0;        // 0: no cap at this level
    };

    Info GetInfo(uint32 guildId);
    // the level set, its experience 0; the online members' perks follow
    void SetLevel(uint32 guildId, uint8 level);
    // as earned (the daily cap too unless ignoreCap); levels up
    void AddExperience(uint32 guildId, uint64 experience, bool ignoreCap);
    // today's experience back to 0 (the daily cap free again)
    void ResetToday(uint32 guildId);
    uint8 GetMaxLevel();
}

#endif
