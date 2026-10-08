/*
 * Guild news (Cataclysm's GuildNewsLog, retail's Guild News) for 3.3.5 - stage 3 of the guild system.
 *
 * News, the last NEWS_MAX of a guild (Cataclysm: 250), saved in guild_news (characters):
 *   2 a boss killed by a guild group (a dungeon / world boss: CREATURE_FLAG_EXTRA_DUNGEON_BOSS or a world boss)
 *   3 an epic item of GuildNews.MinItemLevel+ (default 200, Cataclysm's MinNewsItemLevel for WotLK) or a legendary
 *     looted in a dungeon / raid (PlayerScript::OnLootItem: core/ScriptMgr_item_hooks.patch)
 *   4 such an item crafted (PlayerScript::OnCreateItem: the same patch)
 *   5 such an item bought among the guild rewards (guild_rewards.cpp)
 *   6 the guild's level up (guild_progression.cpp)
 *   (0 / 1, the achievements: the guild achievements stage)
 *
 * AddonComm (client: GuildUI\GuildNews.lua):
 *  C->S "GUILD_NEWS_GET"  -> "GUILD_NEWS" : type;seconds ago;player;value;text,...   (the newest first; "-": none)
 *  S->C "GUILD_NEWS_NEW"  (to the online members: something new, ask again)
 *  Text is percent-encoded (as guild_finder.cpp).
 *
 * Setup: sql/characters_guild_news.sql, core/ScriptMgr_item_hooks.patch, AddSC_guild_news() in custom_script_loader.cpp.
 */

#include "ScriptMgr.h"
#include "Custom\AddonComm\AddonComm.h"
#include "guild_news.h"
#include "guild_progression.h"
#include "guild_achievements.h"
#include "CharacterCache.h"
#include "Config.h"
#include "Creature.h"
#include "DatabaseEnv.h"
#include "GameTime.h"
#include "Group.h"
#include "Guild.h"
#include "GuildMgr.h"
#include "Item.h"
#include "ItemTemplate.h"
#include "Log.h"
#include "Map.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "StringFormat.h"
#include <deque>
#include <set>
#include <sstream>
#include <unordered_map>

namespace
{
    size_t const NEWS_MAX = 250;
    size_t const NEWS_SENT = 100;
    uint32 s_minItemLevel = 200;

    struct NewsEntry
    {
        uint32 id = 0;
        uint8 type = 0;
        time_t time = 0;
        uint32 player = 0;
        uint32 value = 0;
        std::string text;
    };

    std::unordered_map<uint32, std::deque<NewsEntry>> s_news;      // guild id: the newest first
    std::unordered_map<uint32, uint32> s_nextId;

    std::string Encode(std::string const& text)
    {
        static char const hex[] = "0123456789ABCDEF";
        std::string out;
        out.reserve(text.size());
        for (unsigned char c : text)
        {
            if (c < 0x20 || c == '%' || c == ':' || c == ',' || c == ';' || c == '.' || c == '/' || c == '|')
            {
                out += '%';
                out += hex[c >> 4];
                out += hex[c & 0xF];
            }
            else
                out += char(c);
        }
        return out;
    }

    std::string Escape(std::string text)
    {
        CharacterDatabase.EscapeString(text);
        return text;
    }

    void Load()
    {
        s_news.clear();
        s_nextId.clear();
        if (QueryResult result = CharacterDatabase.Query("SELECT guildid, id, type, timestamp, player, value, text FROM guild_news ORDER BY guildid, id DESC"))
        {
            do
            {
                Field* fields = result->Fetch();
                uint32 guildId = fields[0].GetUInt32();
                if (!sGuildMgr->GetGuildById(guildId))
                    continue;
                std::deque<NewsEntry>& news = s_news[guildId];
                NewsEntry entry;
                entry.id = fields[1].GetUInt32();
                entry.type = fields[2].GetUInt8();
                entry.time = time_t(fields[3].GetUInt32());
                entry.player = fields[4].GetUInt32();
                entry.value = fields[5].GetUInt32();
                entry.text = fields[6].GetString();
                s_nextId[guildId] = std::max(s_nextId[guildId], entry.id + 1);
                if (news.size() < NEWS_MAX)
                    news.push_back(entry);
            } while (result->NextRow());
        }
        TC_LOG_INFO("server.loading", ">> Guild news: {} guilds", s_news.size());
    }

    void Send(Player* player)
    {
        auto itr = s_news.find(player->GetGuildId());
        if (!player->GetGuildId() || itr == s_news.end() || itr->second.empty())
        {
            sAddonComm->Send(player, std::string("GUILD_NEWS"), std::string("-"));
            return;
        }
        time_t now = GameTime::GetGameTime();
        std::ostringstream list;
        size_t count = 0;
        for (NewsEntry const& entry : itr->second)
        {
            if (count >= NEWS_SENT)
                break;
            std::string name;
            if (entry.player)
                sCharacterCache->GetCharacterNameByGuid(ObjectGuid::Create<HighGuid::Player>(entry.player), name);
            list << (count ? "," : "") << uint32(entry.type) << ';' << uint32(now > entry.time ? now - entry.time : 0) << ';'
                 << Encode(name) << ';' << entry.value << ';' << Encode(entry.text);
            ++count;
        }
        sAddonComm->Send(player, std::string("GUILD_NEWS"), list.str());
    }

    // an epic of the news' item level, or better
    bool IsNewsItem(ItemTemplate const* proto)
    {
        return proto && (proto->GetQuality() > ITEM_QUALITY_EPIC
            || (proto->GetQuality() == ITEM_QUALITY_EPIC && proto->GetBaseItemLevel() >= s_minItemLevel));
    }

    void HandleGet(Player* player, std::vector<std::string> const& /*args*/)
    {
        Send(player);
    }
}

namespace GuildNews
{
    void Add(uint32 guildId, uint8 type, uint32 playerGuid, uint32 value, std::string const& text)
    {
        Guild* guild = sGuildMgr->GetGuildById(guildId);
        if (!guild)
            return;
        NewsEntry entry;
        entry.id = s_nextId[guildId]++;
        entry.type = type;
        entry.time = GameTime::GetGameTime();
        entry.player = playerGuid;
        entry.value = value;
        entry.text = text;
        std::deque<NewsEntry>& news = s_news[guildId];
        news.push_front(entry);
        if (news.size() > NEWS_MAX)
            news.pop_back();

        CharacterDatabase.Execute(Trinity::StringFormat("INSERT INTO guild_news (guildid, id, type, timestamp, player, value, text) "
            "VALUES ({}, {}, {}, {}, {}, {}, '{}')", guildId, entry.id, uint32(type), uint32(entry.time), playerGuid, value, Escape(text)).c_str());
        if (entry.id >= NEWS_MAX)
            CharacterDatabase.Execute(Trinity::StringFormat("DELETE FROM guild_news WHERE guildid = {} AND id <= {}", guildId, entry.id - NEWS_MAX).c_str());

        auto notify = [](Player* member) { sAddonComm->Send(member, std::string("GUILD_NEWS_NEW")); };
        guild->BroadcastWorker(notify);
    }
}

class guild_news_player : public PlayerScript
{
public:
    guild_news_player() : PlayerScript("guild_news_player")
    {
        sAddonComm->Register(std::string("GUILD_NEWS_GET"), &HandleGet);
    }

    // a boss killed by a guild group: once for each such guild of the group
    void OnCreatureKill(Player* killer, Creature* killed) override
    {
        if (!killed || !(killed->IsDungeonBoss() || killed->isWorldBoss()))
            return;
        std::set<uint32> guilds;
        auto credit = [&](Player* member)
        {
            if (member && member->GetMap() == killed->GetMap() && GuildProgression::IsGuildGroup(member))
                guilds.insert(member->GetGuildId());
        };
        if (Group* group = killer->GetGroup())
        {
            for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
                credit(ref->GetSource());
        }
        for (uint32 guildId : guilds)
            GuildNews::Add(guildId, GuildNews::DUNGEON_ENCOUNTER, 0, killed->GetEntry(), killed->GetName());
    }

    // StoreNewItem: the loot, but vendors and mail too - only in a dungeon / raid
    void OnLootItem(Player* player, Item* item, uint32 /*count*/, ObjectGuid /*lootGuid*/) override
    {
        if (!item || !player->GetGuildId() || !player->GetMap() || !player->GetMap()->IsDungeon())
            return;
        ItemTemplate const* proto = item->GetTemplate();
        if (IsNewsItem(proto))
        {
            GuildNews::Add(player->GetGuildId(), GuildNews::ITEM_LOOTED, player->GetGUID().GetCounter(), proto->ItemId, proto->Name1);
            GuildAchievements::AddProgress(player->GetGuildId(), GuildAchievements::CRITERIA_EPICS_LOOTED, 0, 1);
        }
    }

    void OnCreateItem(Player* player, Item* item, uint32 /*count*/) override
    {
        if (!item || !player->GetGuildId())
            return;
        ItemTemplate const* proto = item->GetTemplate();
        if (IsNewsItem(proto))
        {
            GuildNews::Add(player->GetGuildId(), GuildNews::ITEM_CRAFTED, player->GetGUID().GetCounter(), proto->ItemId, proto->Name1);
            GuildAchievements::AddProgress(player->GetGuildId(), GuildAchievements::CRITERIA_EPICS_CRAFTED, 0, 1);
        }
    }
};

class guild_news_world : public WorldScript
{
public:
    guild_news_world() : WorldScript("guild_news_world") {}

    void OnConfigLoad(bool /*reload*/) override
    {
        s_minItemLevel = uint32(std::max(0, sConfigMgr->GetIntDefault("GuildNews.MinItemLevel", 200)));
    }

    void OnStartup() override
    {
        Load();
    }
};

class guild_news_guild : public GuildScript
{
public:
    guild_news_guild() : GuildScript("guild_news_guild") {}

    void OnDisband(Guild* guild) override
    {
        s_news.erase(guild->GetId());
        s_nextId.erase(guild->GetId());
        CharacterDatabase.Execute(Trinity::StringFormat("DELETE FROM guild_news WHERE guildid = {}", guild->GetId()).c_str());
    }
};

void AddSC_guild_news()
{
    new guild_news_player();
    new guild_news_world();
    new guild_news_guild();
}
