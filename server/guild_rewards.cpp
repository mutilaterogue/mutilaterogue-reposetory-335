/*
 * Guild rewards (Cataclysm's GuildMgr::LoadGuildRewards, retail's GuildRewards) for 3.3.5 - stage 3.
 *
 * world.guild_rewards: an item, the guild reputation's standing it needs (4 Neutral .. 8 Exalted), the races
 * (a mask, 0: all), its price (copper) and the guild's level it needs (Cataclysm: an achievement; the guild
 * achievements: guild_achievements.cpp) and / or a guild achievement. Bought from the guild window (Cataclysm: the guild vendors).
 *
 * AddonComm (client: GuildUI\GuildRewards.lua):
 *  C->S "GUILD_REWARDS_GET"            -> "GUILD_REWARDS" : item;standing;price;guildLevel;achievement;achievement done,...   (for my race; "-": none)
 *       "GUILD_REWARD_BUY" : item      -> "GUILD_REWARD_RESULT" : 1 / 0 : message
 *
 * Setup: sql/world_guild_rewards.sql, AddSC_guild_rewards() in custom_script_loader.cpp.
 */

#include "ScriptMgr.h"
#include "Custom\AddonComm\AddonComm.h"
#include "guild_news.h"
#include "guild_progression.h"
#include "guild_achievements.h"
#include "Chat.h"
#include "DatabaseEnv.h"
#include "ItemTemplate.h"
#include "Log.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "StringFormat.h"
#include <sstream>
#include <vector>

namespace
{
    struct Reward
    {
        uint32 Item = 0;
        uint8 Standing = 4;
        uint32 RaceMask = 0;
        uint32 Price = 0;
        uint8 GuildLevel = 0;
        uint32 Achievement = 0;
    };

    std::vector<Reward> s_rewards;

    std::string Encode(std::string const& text)
    {
        static char const hex[] = "0123456789ABCDEF";
        std::string out;
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

    void Load()
    {
        s_rewards.clear();
        if (QueryResult result = WorldDatabase.Query("SELECT item, standing, race_mask, price, guild_level, achievement FROM guild_rewards ORDER BY standing, guild_level, item"))
        {
            do
            {
                Field* fields = result->Fetch();
                Reward reward;
                reward.Item = fields[0].GetUInt32();
                reward.Standing = fields[1].GetUInt8();
                reward.RaceMask = fields[2].GetUInt32();
                reward.Price = fields[3].GetUInt32();
                reward.GuildLevel = fields[4].GetUInt8();
                reward.Achievement = fields[5].GetUInt32();
                if (!sObjectMgr->GetItemTemplate(reward.Item))
                {
                    TC_LOG_ERROR("sql.sql", "guild_rewards: item {} does not exist, skipped", reward.Item);
                    continue;
                }
                s_rewards.push_back(reward);
            } while (result->NextRow());
        }
        TC_LOG_INFO("server.loading", ">> Guild rewards: {}", s_rewards.size());
    }

    bool ForRace(Reward const& reward, Player* player)
    {
        return !reward.RaceMask || (reward.RaceMask & player->GetRaceMask());
    }

    void HandleGet(Player* player, std::vector<std::string> const& /*args*/)
    {
        std::ostringstream list;
        bool first = true;
        for (Reward const& reward : s_rewards)
        {
            if (!ForRace(reward, player))
                continue;
            list << (first ? "" : ",") << reward.Item << ';' << uint32(reward.Standing) << ';' << reward.Price << ';' << uint32(reward.GuildLevel) << ';'
                 << reward.Achievement << ';' << (GuildAchievements::HasAchievement(player->GetGuildId(), reward.Achievement) ? 1 : 0);
            first = false;
        }
        sAddonComm->Send(player, std::string("GUILD_REWARDS"), first ? std::string("-") : list.str());
    }

    void Result(Player* player, bool ok, std::string const& text)
    {
        sAddonComm->Send(player, std::string("GUILD_REWARD_RESULT"), ok ? 1 : 0, Encode(text));
    }

    void HandleBuy(Player* player, std::vector<std::string> const& args)
    {
        uint32 item = args.empty() ? 0 : CommToUInt32(args[0]);
        Reward const* reward = nullptr;
        for (Reward const& r : s_rewards)
            if (r.Item == item && ForRace(r, player))
                reward = &r;
        uint32 guildId = player->GetGuildId();
        if (!reward || !guildId)
        {
            Result(player, false, "\xd0\x9d\xd0\xb0\xd0\xb3\xd1\x80\xd0\xb0\xd0\xb4\xd0\xb0 \xd0\xbd\xd0\xb5\xd0\xb4\xd0\xbe\xd1\x81\xd1\x82\xd1\x83\xd0\xbf\xd0\xbd\xd0\xb0.");
            return;
        }
        if (GuildProgression::GetStanding(player) < reward->Standing)
        {
            Result(player, false, "\xd0\x9d\xd0\xb5\xd0\xb4\xd0\xbe\xd1\x81\xd1\x82\xd0\xb0\xd1\x82\xd0\xbe\xd1\x87\xd0\xbd\xd0\xbe \xd1\x80\xd0\xb5\xd0\xbf\xd1\x83\xd1\x82\xd0\xb0\xd1\x86\xd0\xb8\xd0\xb8 \xd1\x81 \xd0\xb3\xd0\xb8\xd0\xbb\xd1\x8c\xd0\xb4\xd0\xb8\xd0\xb5\xd0\xb9.");
            return;
        }
        if (GuildProgression::GetInfo(guildId).Level < reward->GuildLevel)
        {
            Result(player, false, "\xd0\x9d\xd0\xb5\xd0\xb4\xd0\xbe\xd1\x81\xd1\x82\xd0\xb0\xd1\x82\xd0\xbe\xd1\x87\xd0\xbd\xd0\xbe \xd0\xb2\xd1\x8b\xd1\x81\xd0\xbe\xd0\xba\xd0\xb8\xd0\xb9 \xd1\x83\xd1\x80\xd0\xbe\xd0\xb2\xd0\xb5\xd0\xbd\xd1\x8c \xd0\xb3\xd0\xb8\xd0\xbb\xd1\x8c\xd0\xb4\xd0\xb8\xd0\xb8.");
            return;
        }
        if (reward->Achievement && !GuildAchievements::HasAchievement(guildId, reward->Achievement))
        {
            Result(player, false, "\xd0\x9d\xd1\x83\xd0\xb6\xd0\xbd\xd0\xbe \xd0\xb4\xd0\xbe\xd1\x81\xd1\x82\xd0\xb8\xd0\xb6\xd0\xb5\xd0\xbd\xd0\xb8\xd0\xb5 \xd0\xb3\xd0\xb8\xd0\xbb\xd1\x8c\xd0\xb4\xd0\xb8\xd0\xb8.");
            return;
        }
        if (!player->HasEnoughMoney(int64(reward->Price)))
        {
            Result(player, false, "\xd0\x9d\xd0\xb5\xd0\xb4\xd0\xbe\xd1\x81\xd1\x82\xd0\xb0\xd1\x82\xd0\xbe\xd1\x87\xd0\xbd\xd0\xbe \xd0\xb4\xd0\xb5\xd0\xbd\xd0\xb5\xd0\xb3.");
            return;
        }
        // the bags first: the item, then the money
        if (!player->AddItem(reward->Item, 1))
        {
            Result(player, false, "\xd0\x9d\xd0\xb5\xd1\x82 \xd0\xbc\xd0\xb5\xd1\x81\xd1\x82\xd0\xb0 \xd0\xb2 \xd1\x81\xd1\x83\xd0\xbc\xd0\xba\xd0\xb0\xd1\x85.");
            return;
        }
        player->ModifyMoney(-int64(reward->Price));
        Result(player, true, std::string());

        ItemTemplate const* proto = sObjectMgr->GetItemTemplate(reward->Item);
        if (proto && proto->GetQuality() >= ITEM_QUALITY_EPIC)
            GuildNews::Add(guildId, GuildNews::ITEM_PURCHASED, player->GetGUID().GetCounter(), proto->ItemId, proto->Name1);
    }
}

class guild_rewards_player : public PlayerScript
{
public:
    guild_rewards_player() : PlayerScript("guild_rewards_player")
    {
        sAddonComm->Register(std::string("GUILD_REWARDS_GET"), &HandleGet);
        sAddonComm->Register(std::string("GUILD_REWARD_BUY"), &HandleBuy);
    }
};

class guild_rewards_world : public WorldScript
{
public:
    guild_rewards_world() : WorldScript("guild_rewards_world") {}

    void OnStartup() override
    {
        Load();
    }
};

void AddSC_guild_rewards()
{
    new guild_rewards_player();
    new guild_rewards_world();
}
