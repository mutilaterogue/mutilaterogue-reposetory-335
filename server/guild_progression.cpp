/*
 * Guild progression of Cataclysm on 3.3.5a, stage 1: guild level 1 .. 25, guild experience, guild perks.
 * The model is TrinityCore 4.3.4 (Guild::GiveXP, KillRewarder::_RewardGuildXP, Player::RewardQuest,
 * Group::IsGuildGroupFor / GetGuildXpRateForPlayer); built on script hooks, the core's Guild is untouched.
 *
 * Experience
 *   quest rewarded:  the quest's XP * Rate.XP.Quest * 0.25                 (Guild.XPQuestModifier)
 *   creature killed in a guild group (a dungeon: 3+ of the guild; a raid: 80% of its size; each member
 *   in reward range):  the kill's XP * 4 (Guild.XPBaseKillModifier) * the group rate (dungeon: 3 - 0.5,
 *   4 - 1, 5 - 1.25; raid 1) * 1.25 in a heroic dungeon
 *   below level 20 at most 7 807 500 a day (Guild.DailyXPCap); the day starts at 06:00 (Guild.ResetHour)
 * Levels: guild_xp_for_level (world): the experience from a level to the next.
 * Perks: guild_perk_spells (world, GuildPerkSpells.dbc): the members know the spells of the guild's level;
 *   learnt at login, on joining, at a level up; unlearnt on leaving / disbanding.
 *
 * Client (GuildProgression/GuildProgression.lua) by AddonComm:
 *   "GUILD_PROG_GET"   -> "GUILD_PROG"  : level : experience : to next level : today : daily cap
 *   "GUILD_PERKS_GET"  -> "GUILD_PERKS" : level : spell : level : spell ...
 * Saved: guild_progression (characters), every minute when changed and at shutdown.
 * Settings: worldserver.conf, GuildProgression.* (sql/worldserver_guild_progression.conf.dist).
 */

#include "ScriptMgr.h"
#include "guild_progression.h"
#include "Custom\AddonComm\AddonComm.h"
#include "Chat.h"
#include "Config.h"
#include "Creature.h"
#include "DatabaseEnv.h"
#include "Formulas.h"
#include "GameTime.h"
#include "Group.h"
#include "Guild.h"
#include "GuildMgr.h"
#include "Log.h"
#include "Map.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "QuestDef.h"
#include "SpellMgr.h"
#include "StringFormat.h"
#include "World.h"
#include <sstream>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace
{
    // worldserver.conf (GuildProgression.*), read at startup and on .reload config
    uint8  GUILD_MAX_LEVEL                  = 25;
    uint8  GUILD_EXPERIENCE_UNCAPPED_LEVEL  = 20;      // from here no daily cap (Cataclysm's client)
    uint64 GUILD_DAILY_XP_CAP               = 7807500;
    float  GUILD_XP_QUEST_MODIFIER          = 0.25f;
    float  GUILD_XP_KILL_MODIFIER           = 4.0f;
    float  GUILD_XP_HEROIC_DUNGEON          = 1.25f;
    uint32 GUILD_RESET_HOUR                 = 6;

    void LoadConfig()
    {
        GUILD_MAX_LEVEL                 = uint8(std::max(1, std::min(25, sConfigMgr->GetIntDefault("GuildProgression.MaxLevel", 25))));
        GUILD_EXPERIENCE_UNCAPPED_LEVEL = uint8(std::max(1, sConfigMgr->GetIntDefault("GuildProgression.UncappedLevel", 20)));
        GUILD_DAILY_XP_CAP              = uint64(std::max(0, sConfigMgr->GetIntDefault("GuildProgression.DailyXPCap", 7807500)));
        GUILD_XP_QUEST_MODIFIER         = sConfigMgr->GetFloatDefault("GuildProgression.XPQuestModifier", 0.25f);
        GUILD_XP_KILL_MODIFIER          = sConfigMgr->GetFloatDefault("GuildProgression.XPBaseKillModifier", 4.0f);
        GUILD_XP_HEROIC_DUNGEON         = sConfigMgr->GetFloatDefault("GuildProgression.XPHeroicDungeonModifier", 1.25f);
        GUILD_RESET_HOUR                = uint32(std::max(0, std::min(23, sConfigMgr->GetIntDefault("GuildProgression.ResetHour", 6))));
    }
    constexpr uint32 SAVE_INTERVAL_MS               = 60 * IN_MILLISECONDS;

    struct GuildProgress
    {
        uint8 level = 1;
        uint64 experience = 0;          // toward the next level
        uint64 today = 0;               // gained today (the daily cap)
        bool dirty = false;
    };

    std::unordered_map<uint32, GuildProgress> s_progress;            // guild id
    std::vector<uint64> s_xpForLevel;                                // [level]: to the next one
    std::vector<std::pair<uint8, uint32>> s_perks;                   // guild level, spell
    uint32 s_resetDay = 0;
    uint32 s_saveTimer = 0;

    GuildProgress& Progress(uint32 guildId)
    {
        return s_progress[guildId];
    }

    uint64 XpForLevel(uint8 level)
    {
        return level < s_xpForLevel.size() ? s_xpForLevel[level] : 0;
    }

    // the day of the daily cap: it starts at GUILD_RESET_HOUR
    uint32 ResetDay()
    {
        return uint32((GameTime::GetGameTime() - GUILD_RESET_HOUR * HOUR) / DAY);
    }

    void Save(uint32 guildId, GuildProgress& progress)
    {
        CharacterDatabase.Execute(Trinity::StringFormat("REPLACE INTO guild_progression (guildid, level, experience, today_experience, reset_day) "
            "VALUES ({}, {}, {}, {}, {})", guildId, uint32(progress.level), progress.experience, progress.today, s_resetDay).c_str());
        progress.dirty = false;
    }

    void SaveAll()
    {
        for (auto& entry : s_progress)
            if (entry.second.dirty)
                Save(entry.first, entry.second);
    }

    // ------------------------------------------------------------ the client
    void SendProgress(Player* player)
    {
        uint32 guildId = player->GetGuildId();
        if (!guildId)
        {
            sAddonComm->Send(player, std::string("GUILD_PROG"), 0, 0, 0, 0, 0);
            return;
        }
        GuildProgress& progress = Progress(guildId);
        uint64 cap = progress.level < GUILD_EXPERIENCE_UNCAPPED_LEVEL ? GUILD_DAILY_XP_CAP : 0;
        sAddonComm->Send(player, std::string("GUILD_PROG"), uint32(progress.level), progress.experience,
            XpForLevel(progress.level), progress.today, cap);
    }

    void SendPerks(Player* player)
    {
        std::ostringstream list;
        bool first = true;
        for (auto const& perk : s_perks)
        {
            list << (first ? "" : ":") << uint32(perk.first) << ':' << perk.second;
            first = false;
        }
        sAddonComm->Send(player, std::string("GUILD_PERKS"), list.str());
    }

    template <typename Fn>
    void ForEachOnlineMember(uint32 guildId, Fn&& fn)
    {
        std::vector<Player*> members;
        {
            std::shared_lock<std::shared_mutex> lock(*HashMapHolder<Player>::GetLock());
            for (auto const& entry : ObjectAccessor::GetPlayers())
                if (entry.second && entry.second->IsInWorld() && entry.second->GetGuildId() == guildId)
                    members.push_back(entry.second);
        }
        for (Player* member : members)
            fn(member);
    }

    // ------------------------------------------------------------ perks
    // the player knows exactly the perks of his guild's level (none without a guild)
    void UpdatePerks(Player* player, uint32 guildId)
    {
        uint8 level = guildId ? Progress(guildId).level : 0;
        for (auto const& perk : s_perks)
        {
            if (!sSpellMgr->GetSpellInfo(perk.second))
                continue;       // not in Spell.dbc yet
            bool should = guildId && perk.first <= level;
            if (should && !player->HasSpell(perk.second))
                player->LearnSpell(perk.second, false);
            else if (!should && player->HasSpell(perk.second))
                player->RemoveSpell(perk.second, false, false);
        }
    }

    // ------------------------------------------------------------ experience
    void LevelUp(uint32 guildId, uint8 level)
    {
        Guild* guild = sGuildMgr->GetGuildById(guildId);
        std::string name = guild ? guild->GetName() : std::string();
        ForEachOnlineMember(guildId, [&](Player* member)
        {
            UpdatePerks(member, guildId);
            SendProgress(member);
            ChatHandler(member->GetSession()).PSendSysMessage("|cff40c040\xd0\x93\xd0\xb8\xd0\xbb\xd1\x8c\xd0\xb4\xd0\xb8\xd1\x8f <%s> \xd0\xb4\xd0\xbe\xd1\x81\xd1\x82\xd0\xb8\xd0\xb3\xd0\xbb\xd0\xb0 %u-\xd0\xb3\xd0\xbe \xd1\x83\xd1\x80\xd0\xbe\xd0\xb2\xd0\xbd\xd1\x8f!|r", name.c_str(), uint32(level));
        });
    }

    void GiveXP(uint32 guildId, uint64 xp, Player* source, bool ignoreCap = false)
    {
        if (!guildId || !xp)
            return;
        GuildProgress& progress = Progress(guildId);
        if (progress.level >= GUILD_MAX_LEVEL)
            return;

        if (progress.level < GUILD_EXPERIENCE_UNCAPPED_LEVEL && !ignoreCap)
            xp = std::min<uint64>(xp, progress.today < GUILD_DAILY_XP_CAP ? GUILD_DAILY_XP_CAP - progress.today : 0);
        if (!xp)
            return;
        progress.today += xp;
        progress.experience += xp;
        progress.dirty = true;

        bool leveled = false;
        while (progress.level < GUILD_MAX_LEVEL && XpForLevel(progress.level) && progress.experience >= XpForLevel(progress.level))
        {
            progress.experience -= XpForLevel(progress.level);
            ++progress.level;
            leveled = true;
            LevelUp(guildId, progress.level);
        }
        if (progress.level >= GUILD_MAX_LEVEL)
            progress.experience = 0;
        if (leveled)
            Save(guildId, progress);
        else if (source)
            SendProgress(source);
    }

    // Cataclysm's guild group: a dungeon 3+ of the guild, a raid 80% of its size
    float GuildGroupRate(Player* player, Group* group)
    {
        Map* map = player->GetMap();
        if (!group || !map || !map->IsDungeon())
            return 0.0f;
        uint32 count = 0;
        for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
            if (Player* member = ref->GetSource())
                if (member->GetGuildId() == player->GetGuildId())
                    ++count;
        if (map->IsRaid())
        {
            InstanceMap* instance = map->ToInstanceMap();
            uint32 needed = std::max<uint32>(1, uint32((instance ? instance->GetMaxPlayers() : 10) * 0.8f));
            return count >= needed ? 1.0f : 0.0f;
        }
        switch (count)
        {
            case 3:  return 0.5f;
            case 4:  return 1.0f;
            case 5:  return 1.25f;
            default: return 0.0f;
        }
    }
}

// ------------------------------------------------------------ for the GM commands (guild_progression.h)
namespace GuildProgression
{
    Info GetInfo(uint32 guildId)
    {
        GuildProgress& progress = Progress(guildId);
        Info info;
        info.Level = progress.level;
        info.Experience = progress.experience;
        info.ToNextLevel = XpForLevel(progress.level);
        info.Today = progress.today;
        info.DailyCap = progress.level < GUILD_EXPERIENCE_UNCAPPED_LEVEL ? GUILD_DAILY_XP_CAP : 0;
        return info;
    }

    void SetLevel(uint32 guildId, uint8 level)
    {
        GuildProgress& progress = Progress(guildId);
        uint8 oldLevel = progress.level;
        progress.level = std::max<uint8>(1, std::min(level, GUILD_MAX_LEVEL));
        progress.experience = 0;
        Save(guildId, progress);
        if (progress.level > oldLevel)
            LevelUp(guildId, progress.level);
        else
            ForEachOnlineMember(guildId, [guildId](Player* member)
            {
                UpdatePerks(member, guildId);
                SendProgress(member);
            });
    }

    void AddExperience(uint32 guildId, uint64 experience, bool ignoreCap)
    {
        GiveXP(guildId, experience, nullptr, ignoreCap);
        Save(guildId, Progress(guildId));
        ForEachOnlineMember(guildId, [](Player* member) { SendProgress(member); });
    }

    void ResetToday(uint32 guildId)
    {
        GuildProgress& progress = Progress(guildId);
        progress.today = 0;
        Save(guildId, progress);
        ForEachOnlineMember(guildId, [](Player* member) { SendProgress(member); });
    }

    uint8 GetMaxLevel()
    {
        return GUILD_MAX_LEVEL;
    }
}

class guild_progression_player : public PlayerScript
{
public:
    guild_progression_player() : PlayerScript("guild_progression_player")
    {
        sAddonComm->Register(std::string("GUILD_PROG_GET"), [](Player* player, std::vector<std::string> const&)
        {
            SendProgress(player);
        });
        sAddonComm->Register(std::string("GUILD_PERKS_GET"), [](Player* player, std::vector<std::string> const&)
        {
            SendPerks(player);
        });
    }

    void OnLogin(Player* player, bool /*firstLogin*/) override
    {
        UpdatePerks(player, player->GetGuildId());
    }

    // a quest rewarded: its XP (Cataclysm's Player::RewardQuest)
    void OnQuestStatusChange(Player* player, uint32 questId) override
    {
        uint32 guildId = player->GetGuildId();
        if (!guildId || player->GetQuestStatus(questId) != QUEST_STATUS_REWARDED)
            return;
        // once per quest and character (the hook can come more than once for a reward)
        uint64 key = (uint64(player->GetGUID().GetCounter()) << 32) | questId;
        if (!_credited.insert(key).second)
            return;
        Quest const* quest = sObjectMgr->GetQuestTemplate(questId);
        if (!quest)
            return;
        uint32 xp = quest->GetXPReward(player) * sWorld->getRate(RATE_XP_QUEST);
        GiveXP(guildId, uint64(xp * GUILD_XP_QUEST_MODIFIER), player);
    }

    // a creature killed in a guild group: every member of the guild in reward range (KillRewarder)
    void OnCreatureKill(Player* killer, Creature* killed) override
    {
        Group* group = killer->GetGroup();
        if (!group || !killed)
            return;
        for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
        {
            Player* member = ref->GetSource();
            if (!member || !member->GetGuildId() || !member->IsAtGroupRewardDistance(killed))
                continue;
            float rate = GuildGroupRate(member, group);
            if (rate <= 0.0f)
                continue;
            float xp = float(Trinity::XP::Gain(member, killed)) * GUILD_XP_KILL_MODIFIER * rate;
            if (member->GetMap()->IsNonRaidDungeon() && member->GetMap()->IsHeroic())
                xp *= GUILD_XP_HEROIC_DUNGEON;
            GiveXP(member->GetGuildId(), uint64(xp), member);
        }
    }

private:
    std::unordered_set<uint64> _credited;
};

class guild_progression_guild : public GuildScript
{
public:
    guild_progression_guild() : GuildScript("guild_progression_guild") { }

    void OnAddMember(Guild* guild, Player* player, uint8& /*plRank*/) override
    {
        UpdatePerks(player, guild->GetId());
        SendProgress(player);
    }

    void OnRemoveMember(Guild* /*guild*/, Player* player, bool /*isDisbanding*/, bool /*isKicked*/) override
    {
        if (player)
        {
            UpdatePerks(player, 0);
            SendProgress(player);
        }
    }

    void OnDisband(Guild* guild) override
    {
        uint32 guildId = guild->GetId();
        ForEachOnlineMember(guildId, [](Player* member) { UpdatePerks(member, 0); });
        s_progress.erase(guildId);
        CharacterDatabase.Execute(Trinity::StringFormat("DELETE FROM guild_progression WHERE guildid = {}", guildId).c_str());
    }
};

class guild_progression_world : public WorldScript
{
public:
    guild_progression_world() : WorldScript("guild_progression_world") { }

    void OnConfigLoad(bool /*reload*/) override
    {
        LoadConfig();
    }

    void OnStartup() override
    {
        s_xpForLevel.assign(GUILD_MAX_LEVEL + 1, 0);
        if (QueryResult result = WorldDatabase.Query("SELECT lvl, xp_for_next_level FROM guild_xp_for_level"))
        {
            do
            {
                Field* fields = result->Fetch();
                uint8 level = fields[0].GetUInt8();
                if (level < s_xpForLevel.size())
                    s_xpForLevel[level] = fields[1].GetUInt64();
            } while (result->NextRow());
        }

        s_perks.clear();
        if (QueryResult result = WorldDatabase.Query("SELECT guild_level, spell FROM guild_perk_spells ORDER BY guild_level"))
        {
            do
            {
                Field* fields = result->Fetch();
                s_perks.emplace_back(fields[0].GetUInt8(), fields[1].GetUInt32());
            } while (result->NextRow());
        }

        s_resetDay = ResetDay();
        s_progress.clear();
        if (QueryResult result = CharacterDatabase.Query("SELECT guildid, level, experience, today_experience, reset_day FROM guild_progression"))
        {
            do
            {
                Field* fields = result->Fetch();
                GuildProgress& progress = Progress(fields[0].GetUInt32());
                progress.level = std::max<uint8>(1, std::min<uint8>(GUILD_MAX_LEVEL, fields[1].GetUInt8()));
                progress.experience = fields[2].GetUInt64();
                progress.today = fields[4].GetUInt32() == s_resetDay ? fields[3].GetUInt64() : 0;
            } while (result->NextRow());
        }
        TC_LOG_INFO("server.loading", ">> Guild progression: {} guilds, {} perks", s_progress.size(), s_perks.size());
    }

    void OnUpdate(uint32 diff) override
    {
        // the day changed: the daily cap is free again
        uint32 day = ResetDay();
        if (day != s_resetDay)
        {
            s_resetDay = day;
            for (auto& entry : s_progress)
            {
                entry.second.today = 0;
                entry.second.dirty = true;
            }
        }

        s_saveTimer += diff;
        if (s_saveTimer >= SAVE_INTERVAL_MS)
        {
            s_saveTimer = 0;
            SaveAll();
        }
    }

    void OnShutdown() override
    {
        SaveAll();
    }
};

void AddSC_guild_progression()
{
    new guild_progression_player();
    new guild_progression_guild();
    new guild_progression_world();
}
