#ifndef CIRCLE_GUILD_NEWS_H
#define CIRCLE_GUILD_NEWS_H

// Guild news (guild_news.cpp): Cataclysm's GuildNewsLog
#include "Define.h"
#include <string>

namespace GuildNews
{
    // Cataclysm's GuildNews types
    enum Type : uint8
    {
        GUILD_ACHIEVEMENT   = 0,
        PLAYER_ACHIEVEMENT  = 1,
        DUNGEON_ENCOUNTER   = 2,    // value: creature entry, text: its name
        ITEM_LOOTED         = 3,    // value: item entry, text: its name
        ITEM_CRAFTED        = 4,
        ITEM_PURCHASED      = 5,
        LEVEL_UP            = 6,    // value: the guild's level
    };

    // playerGuid: the member (0: the guild itself)
    void Add(uint32 guildId, uint8 type, uint32 playerGuid, uint32 value, std::string const& text);
}

#endif
