#ifndef CIRCLE_GUILD_ACHIEVEMENTS_H
#define CIRCLE_GUILD_ACHIEVEMENTS_H

// Guild challenges and guild achievements (guild_achievements.cpp)
#include "Define.h"

class Map;

namespace GuildAchievements
{
    // world.guild_achievements.type: what the guild counts
    enum Criteria : uint8
    {
        CRITERIA_GUILD_LEVEL    = 1,    // value: the level
        CRITERIA_KILL_BOSS      = 2,    // value: a creature entry (0: any boss)
        CRITERIA_QUESTS         = 3,    // quests done by members
        CRITERIA_CHALLENGES     = 4,    // value: a challenge type (0: any)
        CRITERIA_MEMBERS        = 5,    // the guild's size
        CRITERIA_EPICS_LOOTED   = 6,
        CRITERIA_EPICS_CRAFTED  = 7,
        CRITERIA_BG_WINS        = 8,    // battlegrounds won by a guild group
    };

    // counted: (type, value) and (type, 0); the achievements are checked
    void AddProgress(uint32 guildId, uint8 type, uint32 value, uint32 amount);
    // the level / members achievements checked again
    void Evaluate(uint32 guildId);
    bool HasAchievement(uint32 guildId, uint32 achievementId);
    uint32 GetPoints(uint32 guildId);
    // a mythic+ dungeon finished in time (mythic_plus.cpp): the guild challenge for each guild group in it
    void OnMythicPlusCompleted(Map* map);
}

#endif
