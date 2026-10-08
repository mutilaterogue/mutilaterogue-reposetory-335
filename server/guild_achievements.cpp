/*
 * Guild challenges and guild achievements (Cataclysm's GuildChallenges / guild AchievementMgr) for 3.3.5 - stage 4.
 *
 * Challenges (world.guild_challenges: type, count a week, guild XP and gold (to the guild bank) for each one):
 *   1 dungeon     - a dungeon boss killed by a guild group (once for each dungeon instance)
 *   2 mythic+     - a mythic+ dungeon finished in time by a guild group (mythic_plus.cpp)
 *   3 raid        - a raid boss killed by a guild group (once for each raid instance)
 *   4 battleground - a battleground won with GuildChallenges.BattlegroundMembers+ of the guild in the team
 *                    (PlayerScript::OnBattlegroundEnd: core/ScriptMgr_guild_hooks.patch)
 *   The week starts on Wednesday at the reset hour (guild_progression.cpp). characters.guild_challenge_progress.
 *
 * Achievements (world.guild_achievements: id, name, description, points, icon, criteria type / value / count):
 *   criteria in guild_achievements.h; the counters in characters.guild_achievement_criteria, the done ones in
 *   characters.guild_achievement_done. Done: guild news, a chat line to the members. The guild rewards may need one
 *   (world.guild_rewards.achievement).
 * A member's achievement (PlayerScript::OnAchievementComplete, the same patch): guild news (type 1).
 * The guild's emblem for the client (GuildUI\GuildEmblem.lua).
 *
 * AddonComm:
 *  C->S "GUILD_CHALLENGES_GET"   -> "GUILD_CHALLENGES" : type;done;count;xp;gold,...
 *       "GUILD_ACH_GET"          -> "GUILD_ACH" : points : id;points;done;seconds ago;progress;needed;name;description;icon,...
 *       "GUILD_EMBLEM_GET"       -> "GUILD_EMBLEM" : style : color : borderStyle : borderColor : background  (no guild: all -1)
 *  S->C "GUILD_ACH_NEW"          (to the online members: an achievement done / a challenge counted)
 *
 * Setup: core/ScriptMgr_guild_hooks.patch, sql/world_guild_stage4.sql, sql/characters_guild_stage4.sql,
 *        AddSC_guild_achievements() in custom_script_loader.cpp.
 */

#include "ScriptMgr.h"
#include "Custom\AddonComm\AddonComm.h"
#include "guild_achievements.h"
#include "guild_news.h"
#include "guild_progression.h"
#include "Battleground.h"
#include "Chat.h"
#include "Config.h"
#include "Creature.h"
#include "DatabaseEnv.h"
#include "DBCStores.h"
#include "GameTime.h"
#include "Group.h"
#include "Guild.h"
#include "GuildMgr.h"
#include "Log.h"
#include "Map.h"
#include "MapManager.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "StringFormat.h"
#include <map>
#include <set>
#include <sstream>
#include <unordered_map>

namespace
{
    enum ChallengeType : uint8
    {
        CHALLENGE_DUNGEON       = 1,
        CHALLENGE_MYTHIC_PLUS   = 2,
        CHALLENGE_RAID          = 3,
        CHALLENGE_BATTLEGROUND  = 4,
        MAX_CHALLENGE           = 5,
    };

    struct Challenge
    {
        std::string Name;
        uint32 Count = 0;
        uint32 Xp = 0;
        uint32 Gold = 0;        // copper
    };

    struct GuildChallengeState
    {
        uint32 Week = 0;
        uint32 Done[MAX_CHALLENGE] = {};
    };

    struct Achievement
    {
        uint32 Id = 0;
        std::string Name;
        std::string Description;
        uint32 Points = 0;
        std::string Icon;
        uint8 Type = 0;
        uint32 Value = 0;
        uint32 Count = 1;
    };

    struct GuildAchievementState
    {
        std::map<std::pair<uint8, uint32>, uint32> Counters;    // (type, value): counter
        std::map<uint32, time_t> Done;                          // achievement: when
    };

    Challenge s_challenges[MAX_CHALLENGE];
    std::vector<Achievement> s_achievements;
    std::unordered_map<uint32, GuildChallengeState> s_challengeState;
    std::unordered_map<uint32, GuildAchievementState> s_achievementState;
    std::set<std::pair<uint32, uint32>> s_creditedInstances;    // (instance id, guild id): this week's dungeon / raid
    uint32 s_bgMembers = 5;

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

    template <typename Fn>
    void ForEachOnlineMember(uint32 guildId, Fn fn)
    {
        if (Guild* guild = sGuildMgr->GetGuildById(guildId))
            guild->BroadcastWorker(fn);
    }

    void Notify(uint32 guildId)
    {
        ForEachOnlineMember(guildId, [](Player* member) { sAddonComm->Send(member, std::string("GUILD_ACH_NEW")); });
    }

    // ------------------------------------------------------------ achievements
    GuildAchievementState& AchievementState(uint32 guildId)
    {
        return s_achievementState[guildId];
    }

    uint32 Progress(uint32 guildId, Achievement const& achievement)
    {
        switch (achievement.Type)
        {
            case GuildAchievements::CRITERIA_GUILD_LEVEL:
                return GuildProgression::GetInfo(guildId).Level;
            case GuildAchievements::CRITERIA_MEMBERS:
                if (Guild* guild = sGuildMgr->GetGuildById(guildId))
                    return guild->GetMemberCount();
                return 0;
            default:
            {
                GuildAchievementState& state = AchievementState(guildId);
                auto itr = state.Counters.find({ achievement.Type, achievement.Value });
                return itr != state.Counters.end() ? itr->second : 0;
            }
        }
    }

    uint32 Needed(Achievement const& achievement)
    {
        return achievement.Type == GuildAchievements::CRITERIA_GUILD_LEVEL ? achievement.Value : achievement.Count;
    }

    void Complete(uint32 guildId, Achievement const& achievement)
    {
        GuildAchievementState& state = AchievementState(guildId);
        time_t now = GameTime::GetGameTime();
        state.Done[achievement.Id] = now;
        CharacterDatabase.Execute(Trinity::StringFormat("REPLACE INTO guild_achievement_done (guildid, achievement, date) VALUES ({}, {}, {})",
            guildId, achievement.Id, uint32(now)).c_str());
        GuildNews::Add(guildId, GuildNews::GUILD_ACHIEVEMENT, 0, achievement.Id, achievement.Name);
        std::string name = achievement.Name;
        ForEachOnlineMember(guildId, [&name](Player* member)
        {
            ChatHandler(member->GetSession()).PSendSysMessage("|cffffd200\xd0\x93\xd0\xb8\xd0\xbb\xd1\x8c\xd0\xb4\xd0\xb8\xd1\x8f \xd0\xbf\xd0\xbe\xd0\xbb\xd1\x83\xd1\x87\xd0\xb0\xd0\xb5\xd1\x82 \xd0\xb4\xd0\xbe\xd1\x81\xd1\x82\xd0\xb8\xd0\xb6\xd0\xb5\xd0\xbd\xd0\xb8\xd0\xb5 [%s]!|r", name.c_str());
        });
        Notify(guildId);
    }

    void Check(uint32 guildId)
    {
        GuildAchievementState& state = AchievementState(guildId);
        for (Achievement const& achievement : s_achievements)
            if (!state.Done.count(achievement.Id) && Progress(guildId, achievement) >= Needed(achievement))
                Complete(guildId, achievement);
    }

    void SaveCounter(uint32 guildId, uint8 type, uint32 value, uint32 counter)
    {
        CharacterDatabase.Execute(Trinity::StringFormat("REPLACE INTO guild_achievement_criteria (guildid, type, value, counter) VALUES ({}, {}, {}, {})",
            guildId, uint32(type), value, counter).c_str());
    }

    void SendAchievements(Player* player)
    {
        uint32 guildId = player->GetGuildId();
        std::ostringstream list;
        uint32 points = 0;
        time_t now = GameTime::GetGameTime();
        GuildAchievementState& state = AchievementState(guildId);
        bool first = true;
        for (Achievement const& achievement : s_achievements)
        {
            auto done = state.Done.find(achievement.Id);
            bool isDone = guildId && done != state.Done.end();
            if (isDone)
                points += achievement.Points;
            list << (first ? "" : ",") << achievement.Id << ';' << achievement.Points << ';' << (isDone ? 1 : 0) << ';'
                 << (isDone && now > done->second ? uint32(now - done->second) : 0) << ';'
                 << (guildId ? std::min(Progress(guildId, achievement), Needed(achievement)) : 0) << ';' << Needed(achievement) << ';'
                 << Encode(achievement.Name) << ';' << Encode(achievement.Description) << ';' << Encode(achievement.Icon);
            first = false;
        }
        sAddonComm->Send(player, std::string("GUILD_ACH"), points, first ? std::string("-") : list.str());
    }

    // ------------------------------------------------------------ challenges
    GuildChallengeState& ChallengeState(uint32 guildId)
    {
        GuildChallengeState& state = s_challengeState[guildId];
        uint32 week = GuildProgression::GetWeek();
        if (state.Week != week)
        {
            state = GuildChallengeState();
            state.Week = week;
        }
        return state;
    }

    // one challenge done: the guild's XP, the gold into the guild bank (through a member there: a bank deposit)
    void CompleteChallenge(uint32 guildId, uint8 type, Player* member)
    {
        Challenge const& challenge = s_challenges[type];
        GuildChallengeState& state = ChallengeState(guildId);
        if (!challenge.Count || state.Done[type] >= challenge.Count)
            return;
        ++state.Done[type];
        CharacterDatabase.Execute(Trinity::StringFormat("REPLACE INTO guild_challenge_progress (guildid, type, done, week) VALUES ({}, {}, {}, {})",
            guildId, uint32(type), state.Done[type], state.Week).c_str());

        if (challenge.Xp)
            GuildProgression::AddExperience(guildId, challenge.Xp, true);
        Guild* guild = sGuildMgr->GetGuildById(guildId);
        if (challenge.Gold && guild && member && member->GetGuildId() == guildId)
        {
            member->ModifyMoney(int64(challenge.Gold));
            guild->HandleMemberDepositMoney(member->GetSession(), challenge.Gold);
        }

        std::string text = Trinity::StringFormat("|cff40c040\xd0\x98\xd1\x81\xd0\xbf\xd1\x8b\xd1\x82\xd0\xb0\xd0\xbd\xd0\xb8\xd0\xb5 \xd0\xb3\xd0\xb8\xd0\xbb\xd1\x8c\xd0\xb4\xd0\xb8\xd0\xb8 \xc2\xab{}\xc2\xbb: {} / {}.|r", challenge.Name, state.Done[type], challenge.Count);
        ForEachOnlineMember(guildId, [&text](Player* m) { ChatHandler(m->GetSession()).SendSysMessage(text.c_str()); });

        GuildAchievements::AddProgress(guildId, GuildAchievements::CRITERIA_CHALLENGES, type, 1);
        Notify(guildId);
    }

    void SendChallenges(Player* player)
    {
        uint32 guildId = player->GetGuildId();
        std::ostringstream list;
        for (uint8 type = 1; type < MAX_CHALLENGE; ++type)
        {
            Challenge const& challenge = s_challenges[type];
            list << (type > 1 ? "," : "") << uint32(type) << ';' << (guildId ? ChallengeState(guildId).Done[type] : 0) << ';'
                 << challenge.Count << ';' << challenge.Xp << ';' << challenge.Gold;
        }
        sAddonComm->Send(player, std::string("GUILD_CHALLENGES"), list.str());
    }

    void SendEmblem(Player* player)
    {
        Guild* guild = player->GetGuild();
        if (!guild)
        {
            sAddonComm->Send(player, std::string("GUILD_EMBLEM"), -1, -1, -1, -1, -1);
            return;
        }
        EmblemInfo const& emblem = guild->GetEmblemInfo();
        sAddonComm->Send(player, std::string("GUILD_EMBLEM"), int32(emblem.GetStyle()), int32(emblem.GetColor()),
            int32(emblem.GetBorderStyle()), int32(emblem.GetBorderColor()), int32(emblem.GetBackgroundColor()));
    }

    // ------------------------------------------------------------ storage
    void Load()
    {
        for (Challenge& challenge : s_challenges)
            challenge = Challenge();
        if (QueryResult result = WorldDatabase.Query("SELECT type, name, count, xp, gold FROM guild_challenges"))
        {
            do
            {
                Field* fields = result->Fetch();
                uint8 type = fields[0].GetUInt8();
                if (type == 0 || type >= MAX_CHALLENGE)
                    continue;
                s_challenges[type].Name = fields[1].GetString();
                s_challenges[type].Count = fields[2].GetUInt32();
                s_challenges[type].Xp = fields[3].GetUInt32();
                s_challenges[type].Gold = fields[4].GetUInt32();
            } while (result->NextRow());
        }

        s_achievements.clear();
        if (QueryResult result = WorldDatabase.Query("SELECT id, name, description, points, icon, type, value, count FROM guild_achievements ORDER BY sort, id"))
        {
            do
            {
                Field* fields = result->Fetch();
                Achievement achievement;
                achievement.Id = fields[0].GetUInt32();
                achievement.Name = fields[1].GetString();
                achievement.Description = fields[2].GetString();
                achievement.Points = fields[3].GetUInt32();
                achievement.Icon = fields[4].GetString();
                achievement.Type = fields[5].GetUInt8();
                achievement.Value = fields[6].GetUInt32();
                achievement.Count = std::max<uint32>(1, fields[7].GetUInt32());
                s_achievements.push_back(achievement);
            } while (result->NextRow());
        }

        s_challengeState.clear();
        uint32 week = GuildProgression::GetWeek();
        if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat("SELECT guildid, type, done FROM guild_challenge_progress WHERE week = {}", week).c_str()))
        {
            do
            {
                Field* fields = result->Fetch();
                uint8 type = fields[1].GetUInt8();
                if (type == 0 || type >= MAX_CHALLENGE)
                    continue;
                GuildChallengeState& state = s_challengeState[fields[0].GetUInt32()];
                state.Week = week;
                state.Done[type] = fields[2].GetUInt32();
            } while (result->NextRow());
        }

        s_achievementState.clear();
        if (QueryResult result = CharacterDatabase.Query("SELECT guildid, type, value, counter FROM guild_achievement_criteria"))
        {
            do
            {
                Field* fields = result->Fetch();
                AchievementState(fields[0].GetUInt32()).Counters[{ fields[1].GetUInt8(), fields[2].GetUInt32() }] = fields[3].GetUInt32();
            } while (result->NextRow());
        }
        if (QueryResult result = CharacterDatabase.Query("SELECT guildid, achievement, date FROM guild_achievement_done"))
        {
            do
            {
                Field* fields = result->Fetch();
                AchievementState(fields[0].GetUInt32()).Done[fields[1].GetUInt32()] = time_t(fields[2].GetUInt32());
            } while (result->NextRow());
        }
        TC_LOG_INFO("server.loading", ">> Guild achievements: {}, challenges loaded", s_achievements.size());
    }

    // the guild groups of a map: guild id -> a member there
    std::map<uint32, Player*> GuildGroupsIn(Map* map)
    {
        std::map<uint32, Player*> guilds;
        if (!map)
            return guilds;
        for (auto const& ref : map->GetPlayers())
            if (Player* player = ref.GetSource())
                if (GuildProgression::IsGuildGroup(player))
                    guilds.emplace(player->GetGuildId(), player);
        return guilds;
    }
}

namespace GuildAchievements
{
    void AddProgress(uint32 guildId, uint8 type, uint32 value, uint32 amount)
    {
        if (!guildId || !amount)
            return;
        GuildAchievementState& state = AchievementState(guildId);
        uint32& counter = state.Counters[{ type, value }];
        counter += amount;
        SaveCounter(guildId, type, value, counter);
        if (value)
        {
            uint32& any = state.Counters[{ type, 0 }];
            any += amount;
            SaveCounter(guildId, type, 0, any);
        }
        Check(guildId);
    }

    void Evaluate(uint32 guildId)
    {
        if (guildId)
            Check(guildId);
    }

    bool HasAchievement(uint32 guildId, uint32 achievementId)
    {
        return guildId && AchievementState(guildId).Done.count(achievementId);
    }

    uint32 GetPoints(uint32 guildId)
    {
        uint32 points = 0;
        GuildAchievementState& state = AchievementState(guildId);
        for (Achievement const& achievement : s_achievements)
            if (state.Done.count(achievement.Id))
                points += achievement.Points;
        return points;
    }

    void OnMythicPlusCompleted(Map* map)
    {
        for (auto const& [guildId, member] : GuildGroupsIn(map))
            CompleteChallenge(guildId, CHALLENGE_MYTHIC_PLUS, member);
    }
}

class guild_achievements_player : public PlayerScript
{
public:
    guild_achievements_player() : PlayerScript("guild_achievements_player")
    {
        sAddonComm->Register(std::string("GUILD_CHALLENGES_GET"), [](Player* player, std::vector<std::string> const&) { SendChallenges(player); });
        sAddonComm->Register(std::string("GUILD_ACH_GET"), [](Player* player, std::vector<std::string> const&) { SendAchievements(player); });
        sAddonComm->Register(std::string("GUILD_EMBLEM_GET"), [](Player* player, std::vector<std::string> const&) { SendEmblem(player); });
    }

    // a boss: the guild achievements; the first boss of a dungeon / raid instance: its guild challenge
    void OnCreatureKill(Player* killer, Creature* killed) override
    {
        if (!killed || !(killed->IsDungeonBoss() || killed->isWorldBoss()))
            return;
        Map* map = killed->GetMap();
        for (auto const& [guildId, member] : GuildGroupsIn(map))
        {
            GuildAchievements::AddProgress(guildId, GuildAchievements::CRITERIA_KILL_BOSS, killed->GetEntry(), 1);
            if (!map->IsDungeon())
                continue;
            if (!s_creditedInstances.insert({ map->GetInstanceId(), guildId }).second)
                continue;
            CompleteChallenge(guildId, map->IsRaid() ? CHALLENGE_RAID : CHALLENGE_DUNGEON, member);
        }
        (void)killer;
    }

    void OnAchievementComplete(Player* player, AchievementEntry const* achievement) override
    {
        if (!player->GetGuildId() || !achievement || (achievement->Flags & ACHIEVEMENT_FLAG_COUNTER))
            return;
        GuildNews::Add(player->GetGuildId(), GuildNews::PLAYER_ACHIEVEMENT, player->GetGUID().GetCounter(), achievement->ID, std::string());
    }

    // a battleground won with enough of a guild in the team: its challenge, once for each guild of the team
    void OnBattlegroundEnd(Player* player, Battleground* bg, bool won) override
    {
        if (!won || !bg || !bg->isBattleground() || !player->GetGuildId())
            return;
        uint32 guildId = player->GetGuildId();
        if (!s_creditedInstances.insert({ bg->GetInstanceID() | 0x80000000, guildId }).second)
            return;
        uint32 count = 0;
        for (auto const& [guid, info] : bg->GetPlayers())
            if (info.Team == player->GetBGTeam())
                if (Player* other = ObjectAccessor::FindConnectedPlayer(guid))
                    if (other->GetGuildId() == guildId)
                        ++count;
        if (count < s_bgMembers)
            return;
        GuildAchievements::AddProgress(guildId, GuildAchievements::CRITERIA_BG_WINS, 0, 1);
        CompleteChallenge(guildId, CHALLENGE_BATTLEGROUND, player);
    }
};

class guild_achievements_guild : public GuildScript
{
public:
    guild_achievements_guild() : GuildScript("guild_achievements_guild") {}

    void OnAddMember(Guild* guild, Player* /*player*/, uint8& /*plRank*/) override
    {
        // the new member is counted after this hook: checked at the next world tick
        _pending.insert(guild->GetId());
    }

    void OnDisband(Guild* guild) override
    {
        uint32 guildId = guild->GetId();
        s_challengeState.erase(guildId);
        s_achievementState.erase(guildId);
        CharacterDatabase.Execute(Trinity::StringFormat("DELETE FROM guild_challenge_progress WHERE guildid = {}", guildId).c_str());
        CharacterDatabase.Execute(Trinity::StringFormat("DELETE FROM guild_achievement_criteria WHERE guildid = {}", guildId).c_str());
        CharacterDatabase.Execute(Trinity::StringFormat("DELETE FROM guild_achievement_done WHERE guildid = {}", guildId).c_str());
    }

    static std::set<uint32> _pending;
};

std::set<uint32> guild_achievements_guild::_pending;

class guild_achievements_world : public WorldScript
{
public:
    guild_achievements_world() : WorldScript("guild_achievements_world") {}

    void OnConfigLoad(bool /*reload*/) override
    {
        s_bgMembers = uint32(std::max(1, sConfigMgr->GetIntDefault("GuildChallenges.BattlegroundMembers", 5)));
    }

    void OnStartup() override
    {
        Load();
    }

    void OnUpdate(uint32 /*diff*/) override
    {
        if (!guild_achievements_guild::_pending.empty())
        {
            std::set<uint32> pending;
            pending.swap(guild_achievements_guild::_pending);
            for (uint32 guildId : pending)
                GuildAchievements::Evaluate(guildId);
        }
        // a new week: the instances may count again
        uint32 week = GuildProgression::GetWeek();
        if (week != _week)
        {
            _week = week;
            s_creditedInstances.clear();
        }
    }

private:
    uint32 _week = 0;
};

void AddSC_guild_achievements()
{
    new guild_achievements_player();
    new guild_achievements_guild();
    new guild_achievements_world();
}
