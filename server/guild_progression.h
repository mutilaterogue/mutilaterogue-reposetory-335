#ifndef CIRCLE_GUILD_PROGRESSION_H
#define CIRCLE_GUILD_PROGRESSION_H

// Guild progression (guild_progression.cpp): for the GM commands (.guild level ...), the guild finder,
// the guild rewards and news
#include "Define.h"

class Player;

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

    // the member's guild reputation (0 .. 42999) and its standing (4 Neutral .. 8 Exalted)
    uint32 GetReputation(Player* player);
    uint8 GetStanding(Player* player);
    // a guild group (a dungeon: 3+ of the player's guild, a raid: 80%)
    bool IsGuildGroup(Player* player);
}

#endif
