/*
 * Guild Finder (Cataclysm: GuildFinderMgr) for 3.3.5 - ported from TrinityCore 4.3.4 onto AddonComm.
 *
 * A guild lists itself (its officers: rank right GR_RIGHT_MODIFY_GUILD_INFO, or the leader) with its
 * availability, wanted roles, interests, level ("any" / "max level only") and a comment.
 * A player with no guild searches with his own availability / roles / interests and applies with a comment.
 * At most MAX_APPLICATIONS at a time; an application lives APPLICATION_TIMEOUT (Cataclysm: 30 days).
 * The guild's members with the invite right see the applications, decline them or invite the player
 * (the client's own GuildInvite: the player has to be online). Joining a guild removes all his applications.
 *
 * Flags (Cataclysm's):
 *   availability: 1 weekdays, 2 weekends
 *   roles: 1 tank, 2 healer, 4 damage
 *   interests: 1 questing, 2 dungeons, 4 raids, 8 pvp, 16 role playing
 *   level: 1 any level, 2 max level
 *
 * Free text is percent-encoded both ways (as premade_groups.cpp).
 *
 * AddonComm (client: GuildUI\GuildFinder.lua):
 *  C->S "GF_SEARCH" : availability : roles : interests : level       -> "GF_RESULTS"
 *       "GF_APPLY" : guildId : availability : roles : interests : comment
 *       "GF_CANCEL" : guildId
 *       "GF_MYAPPS"                                                  -> "GF_APPS"
 *       "GF_SETTINGS_GET"                                            -> "GF_SETTINGS"
 *       "GF_SETTINGS_SET" : listed : availability : roles : interests : level : comment
 *       "GF_REQUESTS"                                                -> "GF_REQUESTS"
 *       "GF_DECLINE" : playerGuid
 *       "GF_GUILD_INFO" : guildName                                  -> "GF_GUILD_INFO" (the guild invitation frame)
 *  S->C "GF_RESULTS" : guildId;name;level;members;comment;availability;roles;interests;level flag;applied,...
 *       "GF_APPS" : guildId;name;comment;seconds left,...
 *       "GF_SETTINGS" : canEdit : listed : availability : roles : interests : level : comment
 *       "GF_REQUESTS" : playerGuid;name;class;level;availability;roles;interests;comment;seconds left,...
 *       "GF_RESULT" : message
 *       "GF_NEW_REQUEST"                                             (to the guild's online inviters)
 *       "GF_GUILD_INFO" : guildName : level : members
 *  ("-" for an empty list)
 *
 * Setup: sql/characters_guild_finder.sql, AddSC_guild_finder() in custom_script_loader.cpp.
 */

#include "ScriptMgr.h"
#include "Custom\AddonComm\AddonComm.h"
#include "Custom\Guild\guild_progression.h"
#include "DatabaseEnv.h"
#include "GameTime.h"
#include "Guild.h"
#include "GuildMgr.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "StringFormat.h"
#include <algorithm>
#include <functional>
#include <sstream>

namespace
{
    uint32 const MAX_APPLICATIONS = 10;
    uint32 const APPLICATION_TIMEOUT = 30 * DAY;
    size_t const MAX_COMMENT = 255;

    uint8 const ALL_AVAILABILITY = 0x3;
    uint8 const ALL_ROLES = 0x7;
    uint8 const ALL_INTERESTS = 0x1F;
    uint8 const LEVEL_ANY = 0x1;
    uint8 const LEVEL_MAX = 0x2;

    struct Settings
    {
        bool Listed = false;
        uint8 Availability = 0;
        uint8 Roles = 0;
        uint8 Interests = 0;
        uint8 Level = LEVEL_ANY;
        uint32 Team = 0;
        std::string Comment;
    };

    struct Application
    {
        ObjectGuid::LowType Guild = 0;
        ObjectGuid::LowType Player = 0;
        std::string Name;
        uint8 Class = 0;
        uint8 Level = 0;
        uint8 Availability = 0;
        uint8 Roles = 0;
        uint8 Interests = 0;
        std::string Comment;
        time_t Submitted = 0;
    };

    std::map<ObjectGuid::LowType, Settings> s_settings;
    std::vector<Application> s_applications;

    // ---------------------------------------------------------------- text
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

    std::string Decode(std::string const& text)
    {
        std::string out;
        out.reserve(text.size());
        for (size_t i = 0; i < text.size(); ++i)
        {
            if (text[i] == '%' && i + 2 < text.size() && std::isxdigit((unsigned char)text[i + 1]) && std::isxdigit((unsigned char)text[i + 2]))
            {
                char c = char(std::stoi(text.substr(i + 1, 2), nullptr, 16));
                if ((unsigned char)c >= 0x20 && c != '|')
                    out += c;
                i += 2;
            }
            else if ((unsigned char)text[i] >= 0x20 && text[i] != '|')
                out += text[i];
        }
        return out;
    }

    // cut at a UTF-8 character boundary
    std::string Truncate(std::string text, size_t bytes)
    {
        if (text.size() <= bytes)
            return text;
        size_t end = bytes;
        while (end > 0 && (((unsigned char)text[end]) & 0xC0) == 0x80)
            --end;
        text.resize(end);
        return text;
    }

    uint32 UIntArg(std::vector<std::string> const& args, size_t index)
    {
        if (index >= args.size() || args[index].empty())
            return 0;
        try { return uint32(std::stoul(args[index])); }
        catch (...) { return 0; }
    }

    std::string TextArg(std::vector<std::string> const& args, size_t index)
    {
        return index < args.size() ? Truncate(Decode(args[index]), MAX_COMMENT) : std::string();
    }

    void Result(Player* player, std::string const& text)
    {
        sAddonComm->Send(player, std::string("GF_RESULT"), Encode(text));
    }

    std::string Escape(std::string text)
    {
        CharacterDatabase.EscapeString(text);
        return text;
    }

    uint32 SecondsLeft(Application const& app)
    {
        time_t end = app.Submitted + APPLICATION_TIMEOUT;
        time_t now = GameTime::GetGameTime();
        return end > now ? uint32(end - now) : 0;
    }

    // ---------------------------------------------------------------- rights
    // Guild::_GetRankRights is private: the rank's rights from the db (the leader has them all)
    bool HasRight(Player* player, uint32 right)
    {
        Guild* guild = player->GetGuild();
        if (!guild)
            return false;
        if (guild->GetLeaderGUID() == player->GetGUID())
            return true;
        QueryResult result = CharacterDatabase.Query(Trinity::StringFormat("SELECT rights FROM guild_rank WHERE guildid = {} AND rid = {}",
            guild->GetId(), uint32(player->GetGuildRank())).c_str());
        return result && ((*result)[0].GetUInt32() & right) != 0;
    }

    // ---------------------------------------------------------------- storage
    void Load()
    {
        s_settings.clear();
        s_applications.clear();

        if (QueryResult result = CharacterDatabase.Query("SELECT guildId, listed, availability, classRoles, interests, level, team, comment FROM guild_finder_guild_settings"))
        {
            do
            {
                Field* fields = result->Fetch();
                if (!sGuildMgr->GetGuildById(fields[0].GetUInt32()))
                    continue;
                Settings& s = s_settings[fields[0].GetUInt32()];
                s.Listed = fields[1].GetUInt8() != 0;
                s.Availability = fields[2].GetUInt8();
                s.Roles = fields[3].GetUInt8();
                s.Interests = fields[4].GetUInt8();
                s.Level = fields[5].GetUInt8();
                s.Team = fields[6].GetUInt32();
                s.Comment = fields[7].GetString();
            } while (result->NextRow());
        }

        time_t now = GameTime::GetGameTime();
        if (QueryResult result = CharacterDatabase.Query("SELECT a.guildId, a.playerGuid, c.name, c.class, c.level, a.availability, a.classRole, a.interests, a.comment, a.submitTime "
            "FROM guild_finder_applicant a JOIN characters c ON c.guid = a.playerGuid"))
        {
            do
            {
                Field* fields = result->Fetch();
                Application app;
                app.Guild = fields[0].GetUInt32();
                app.Player = fields[1].GetUInt32();
                app.Name = fields[2].GetString();
                app.Class = fields[3].GetUInt8();
                app.Level = fields[4].GetUInt8();
                app.Availability = fields[5].GetUInt8();
                app.Roles = fields[6].GetUInt8();
                app.Interests = fields[7].GetUInt8();
                app.Comment = fields[8].GetString();
                app.Submitted = time_t(fields[9].GetUInt32());
                if (app.Submitted + APPLICATION_TIMEOUT > now && sGuildMgr->GetGuildById(app.Guild))
                    s_applications.push_back(app);
            } while (result->NextRow());
        }
        CharacterDatabase.Execute(Trinity::StringFormat("DELETE FROM guild_finder_applicant WHERE submitTime + {} <= {}", APPLICATION_TIMEOUT, uint32(now)).c_str());
    }

    void SaveSettings(ObjectGuid::LowType guildId, Settings const& s)
    {
        CharacterDatabase.Execute(Trinity::StringFormat("REPLACE INTO guild_finder_guild_settings (guildId, listed, availability, classRoles, interests, level, team, comment) "
            "VALUES ({}, {}, {}, {}, {}, {}, {}, '{}')", guildId, s.Listed ? 1 : 0, uint32(s.Availability), uint32(s.Roles), uint32(s.Interests),
            uint32(s.Level), s.Team, Escape(s.Comment)).c_str());
    }

    void RemoveApplications(std::function<bool(Application const&)> match)
    {
        for (auto itr = s_applications.begin(); itr != s_applications.end();)
        {
            if (match(*itr))
            {
                CharacterDatabase.Execute(Trinity::StringFormat("DELETE FROM guild_finder_applicant WHERE guildId = {} AND playerGuid = {}", itr->Guild, itr->Player).c_str());
                itr = s_applications.erase(itr);
            }
            else
                ++itr;
        }
    }

    void RemoveExpired()
    {
        time_t now = GameTime::GetGameTime();
        RemoveApplications([now](Application const& app) { return app.Submitted + APPLICATION_TIMEOUT <= now; });
    }

    // the guild's online members who may invite
    void NotifyInviters(ObjectGuid::LowType guildId)
    {
        Guild* guild = sGuildMgr->GetGuildById(guildId);
        if (!guild)
            return;
        auto notify = [](Player* member)
        {
            if (HasRight(member, GR_RIGHT_INVITE))
                sAddonComm->Send(member, std::string("GF_NEW_REQUEST"));
        };
        guild->BroadcastWorker(notify);
    }

    // ---------------------------------------------------------------- player
    void SendApps(Player* player)
    {
        RemoveExpired();
        std::ostringstream list;
        bool first = true;
        for (Application const& app : s_applications)
        {
            if (app.Player != player->GetGUID().GetCounter())
                continue;
            Guild* guild = sGuildMgr->GetGuildById(app.Guild);
            if (!guild)
                continue;
            list << (first ? "" : ",") << app.Guild << ';' << Encode(guild->GetName()) << ';' << Encode(app.Comment) << ';' << SecondsLeft(app);
            first = false;
        }
        sAddonComm->Send(player, std::string("GF_APPS"), first ? std::string("-") : list.str());
    }

    void HandleSearch(Player* player, std::vector<std::string> const& args)
    {
        uint8 availability = uint8(UIntArg(args, 0)) & ALL_AVAILABILITY;
        uint8 roles = uint8(UIntArg(args, 1)) & ALL_ROLES;
        uint8 interests = uint8(UIntArg(args, 2)) & ALL_INTERESTS;
        uint8 level = uint8(UIntArg(args, 3)) & (LEVEL_ANY | LEVEL_MAX);
        // nothing ticked: no filter on it
        if (!availability) availability = ALL_AVAILABILITY;
        if (!roles) roles = ALL_ROLES;
        if (!interests) interests = ALL_INTERESTS;
        if (!level) level = LEVEL_ANY | LEVEL_MAX;

        ObjectGuid::LowType me = player->GetGUID().GetCounter();
        std::ostringstream list;
        bool first = true;
        for (auto const& [guildId, s] : s_settings)
        {
            if (!s.Listed || s.Team != player->GetTeam())
                continue;
            if (!(s.Availability & availability) || !(s.Roles & roles) || !(s.Interests & interests) || !(s.Level & level))
                continue;
            Guild* guild = sGuildMgr->GetGuildById(guildId);
            if (!guild || guild->GetId() == player->GetGuildId())
                continue;
            bool applied = std::any_of(s_applications.begin(), s_applications.end(),
                [&](Application const& app) { return app.Guild == guildId && app.Player == me; });
            uint32 guildLevel = GuildProgression::GetInfo(guildId).Level;
            list << (first ? "" : ",") << guildId << ';' << Encode(guild->GetName()) << ';' << guildLevel << ';' << guild->GetMemberCount() << ';'
                 << Encode(s.Comment) << ';' << uint32(s.Availability) << ';' << uint32(s.Roles) << ';' << uint32(s.Interests) << ';'
                 << uint32(s.Level) << ';' << (applied ? 1 : 0);
            first = false;
        }
        sAddonComm->Send(player, std::string("GF_RESULTS"), first ? std::string("-") : list.str());
    }

    void HandleApply(Player* player, std::vector<std::string> const& args)
    {
        if (player->GetGuildId())
        {
            Result(player, "\xd0\x92\xd1\x8b \xd1\x83\xd0\xb6\xd0\xb5 \xd1\x81\xd0\xbe\xd1\x81\xd1\x82\xd0\xbe\xd0\xb8\xd1\x82\xd0\xb5 \xd0\xb2 \xd0\xb3\xd0\xb8\xd0\xbb\xd1\x8c\xd0\xb4\xd0\xb8\xd0\xb8.");
            return;
        }
        RemoveExpired();
        ObjectGuid::LowType guildId = UIntArg(args, 0);
        auto settings = s_settings.find(guildId);
        Guild* guild = sGuildMgr->GetGuildById(guildId);
        if (!guild || settings == s_settings.end() || !settings->second.Listed || settings->second.Team != player->GetTeam())
        {
            Result(player, "\xd0\x93\xd0\xb8\xd0\xbb\xd1\x8c\xd0\xb4\xd0\xb8\xd1\x8f \xd0\xb1\xd0\xbe\xd0\xbb\xd1\x8c\xd1\x88\xd0\xb5 \xd0\xbd\xd0\xb5 \xd0\xb8\xd1\x89\xd0\xb5\xd1\x82 \xd0\xb8\xd0\xb3\xd1\x80\xd0\xbe\xd0\xba\xd0\xbe\xd0\xb2.");
            return;
        }
        ObjectGuid::LowType me = player->GetGUID().GetCounter();
        uint32 count = 0;
        for (Application const& app : s_applications)
        {
            if (app.Player != me)
                continue;
            if (app.Guild == guildId)
            {
                Result(player, "\xd0\x92\xd1\x8b \xd1\x83\xd0\xb6\xd0\xb5 \xd0\xbf\xd0\xbe\xd0\xb4\xd0\xb0\xd0\xbb\xd0\xb8 \xd0\xb7\xd0\xb0\xd1\x8f\xd0\xb2\xd0\xba\xd1\x83 \xd0\xb2 \xd1\x8d\xd1\x82\xd1\x83 \xd0\xb3\xd0\xb8\xd0\xbb\xd1\x8c\xd0\xb4\xd0\xb8\xd1\x8e.");
                return;
            }
            ++count;
        }
        if (count >= MAX_APPLICATIONS)
        {
            Result(player, Trinity::StringFormat("\xd0\x9c\xd0\xbe\xd0\xb6\xd0\xbd\xd0\xbe \xd0\xbf\xd0\xbe\xd0\xb4\xd0\xb0\xd1\x82\xd1\x8c \xd0\xbd\xd0\xb5 \xd0\xb1\xd0\xbe\xd0\xbb\xd0\xb5\xd0\xb5 {} \xd0\xb7\xd0\xb0\xd1\x8f\xd0\xb2\xd0\xbe\xd0\xba.", MAX_APPLICATIONS));
            return;
        }

        Application app;
        app.Guild = guildId;
        app.Player = me;
        app.Name = player->GetName();
        app.Class = player->GetClass();
        app.Level = uint8(player->GetLevel());
        app.Availability = uint8(UIntArg(args, 1)) & ALL_AVAILABILITY;
        app.Roles = uint8(UIntArg(args, 2)) & ALL_ROLES;
        app.Interests = uint8(UIntArg(args, 3)) & ALL_INTERESTS;
        app.Comment = TextArg(args, 4);
        app.Submitted = GameTime::GetGameTime();
        s_applications.push_back(app);
        CharacterDatabase.Execute(Trinity::StringFormat("REPLACE INTO guild_finder_applicant (guildId, playerGuid, availability, classRole, interests, comment, submitTime) "
            "VALUES ({}, {}, {}, {}, {}, '{}', {})", app.Guild, app.Player, uint32(app.Availability), uint32(app.Roles), uint32(app.Interests),
            Escape(app.Comment), uint32(app.Submitted)).c_str());

        Result(player, Trinity::StringFormat("\xd0\x97\xd0\xb0\xd1\x8f\xd0\xb2\xd0\xba\xd0\xb0 \xd0\xb2 \xd0\xb3\xd0\xb8\xd0\xbb\xd1\x8c\xd0\xb4\xd0\xb8\xd1\x8e <{}> \xd0\xbe\xd1\x82\xd0\xbf\xd1\x80\xd0\xb0\xd0\xb2\xd0\xbb\xd0\xb5\xd0\xbd\xd0\xb0.", guild->GetName()));
        SendApps(player);
        NotifyInviters(guildId);
    }

    void HandleCancel(Player* player, std::vector<std::string> const& args)
    {
        ObjectGuid::LowType guildId = UIntArg(args, 0);
        ObjectGuid::LowType me = player->GetGUID().GetCounter();
        RemoveApplications([&](Application const& app) { return app.Guild == guildId && app.Player == me; });
        SendApps(player);
        NotifyInviters(guildId);
    }

    void HandleMyApps(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendApps(player);
    }

    // ---------------------------------------------------------------- guild
    void SendSettings(Player* player)
    {
        ObjectGuid::LowType guildId = player->GetGuildId();
        if (!guildId)
            return;
        Settings s;
        auto itr = s_settings.find(guildId);
        if (itr != s_settings.end())
            s = itr->second;
        sAddonComm->Send(player, std::string("GF_SETTINGS"), HasRight(player, GR_RIGHT_MODIFY_GUILD_INFO) ? 1 : 0, s.Listed ? 1 : 0,
            uint32(s.Availability), uint32(s.Roles), uint32(s.Interests), uint32(s.Level), Encode(s.Comment));
    }

    void HandleSettingsGet(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendSettings(player);
    }

    void HandleSettingsSet(Player* player, std::vector<std::string> const& args)
    {
        ObjectGuid::LowType guildId = player->GetGuildId();
        if (!guildId || !HasRight(player, GR_RIGHT_MODIFY_GUILD_INFO))
        {
            Result(player, "\xd0\xa3 \xd0\xb2\xd0\xb0\xd1\x81 \xd0\xbd\xd0\xb5\xd1\x82 \xd0\xbf\xd1\x80\xd0\xb0\xd0\xb2 \xd0\xbc\xd0\xb5\xd0\xbd\xd1\x8f\xd1\x82\xd1\x8c \xd0\xbd\xd0\xb0\xd1\x81\xd1\x82\xd1\x80\xd0\xbe\xd0\xb9\xd0\xba\xd0\xb8 \xd0\xbf\xd0\xbe\xd0\xb8\xd1\x81\xd0\xba\xd0\xb0 \xd0\xb3\xd0\xb8\xd0\xbb\xd1\x8c\xd0\xb4\xd0\xb8\xd0\xb8.");
            return;
        }
        Settings& s = s_settings[guildId];
        s.Listed = UIntArg(args, 0) != 0;
        s.Availability = uint8(UIntArg(args, 1)) & ALL_AVAILABILITY;
        s.Roles = uint8(UIntArg(args, 2)) & ALL_ROLES;
        s.Interests = uint8(UIntArg(args, 3)) & ALL_INTERESTS;
        s.Level = uint8(UIntArg(args, 4)) & (LEVEL_ANY | LEVEL_MAX);
        if (!s.Level)
            s.Level = LEVEL_ANY;
        s.Team = player->GetTeam();
        s.Comment = TextArg(args, 5);
        SaveSettings(guildId, s);
        Result(player, s.Listed ? "\xd0\x93\xd0\xb8\xd0\xbb\xd1\x8c\xd0\xb4\xd0\xb8\xd1\x8f \xd0\xb2\xd0\xbd\xd0\xb5\xd1\x81\xd0\xb5\xd0\xbd\xd0\xb0 \xd0\xb2 \xd0\xbf\xd0\xbe\xd0\xb8\xd1\x81\xd0\xba." : "\xd0\x93\xd0\xb8\xd0\xbb\xd1\x8c\xd0\xb4\xd0\xb8\xd1\x8f \xd1\x83\xd0\xb1\xd1\x80\xd0\xb0\xd0\xbd\xd0\xb0 \xd0\xb8\xd0\xb7 \xd0\xbf\xd0\xbe\xd0\xb8\xd1\x81\xd0\xba\xd0\xb0.");
        SendSettings(player);
    }

    void SendRequests(Player* player)
    {
        ObjectGuid::LowType guildId = player->GetGuildId();
        if (!guildId || !HasRight(player, GR_RIGHT_INVITE))
        {
            sAddonComm->Send(player, std::string("GF_REQUESTS"), std::string("-"));
            return;
        }
        RemoveExpired();
        std::ostringstream list;
        bool first = true;
        for (Application const& app : s_applications)
        {
            if (app.Guild != guildId)
                continue;
            list << (first ? "" : ",") << app.Player << ';' << Encode(app.Name) << ';' << uint32(app.Class) << ';' << uint32(app.Level) << ';'
                 << uint32(app.Availability) << ';' << uint32(app.Roles) << ';' << uint32(app.Interests) << ';' << Encode(app.Comment) << ';'
                 << SecondsLeft(app);
            first = false;
        }
        sAddonComm->Send(player, std::string("GF_REQUESTS"), first ? std::string("-") : list.str());
    }

    void HandleRequests(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendRequests(player);
    }

    void HandleDecline(Player* player, std::vector<std::string> const& args)
    {
        ObjectGuid::LowType guildId = player->GetGuildId();
        if (!guildId || !HasRight(player, GR_RIGHT_INVITE))
            return;
        ObjectGuid::LowType target = UIntArg(args, 0);
        RemoveApplications([&](Application const& app) { return app.Guild == guildId && app.Player == target; });
        SendRequests(player);
        if (Player* applicant = ObjectAccessor::FindConnectedPlayer(ObjectGuid::Create<HighGuid::Player>(target)))
            SendApps(applicant);
    }

    // the guild invitation frame: the inviting guild's level and size
    void HandleGuildInfo(Player* player, std::vector<std::string> const& args)
    {
        std::string name = args.empty() ? std::string() : Decode(args[0]);
        Guild* guild = sGuildMgr->GetGuildByName(name);
        if (!guild)
            return;
        sAddonComm->Send(player, std::string("GF_GUILD_INFO"), Encode(guild->GetName()), uint32(GuildProgression::GetInfo(guild->GetId()).Level),
            guild->GetMemberCount());
    }
}

class guild_finder_world : public WorldScript
{
public:
    guild_finder_world() : WorldScript("guild_finder_world") {}

    void OnStartup() override
    {
        Load();
    }
};

class guild_finder_player : public PlayerScript
{
public:
    guild_finder_player() : PlayerScript("guild_finder_player")
    {
        sAddonComm->Register(std::string("GF_SEARCH"), &HandleSearch);
        sAddonComm->Register(std::string("GF_APPLY"), &HandleApply);
        sAddonComm->Register(std::string("GF_CANCEL"), &HandleCancel);
        sAddonComm->Register(std::string("GF_MYAPPS"), &HandleMyApps);
        sAddonComm->Register(std::string("GF_SETTINGS_GET"), &HandleSettingsGet);
        sAddonComm->Register(std::string("GF_SETTINGS_SET"), &HandleSettingsSet);
        sAddonComm->Register(std::string("GF_REQUESTS"), &HandleRequests);
        sAddonComm->Register(std::string("GF_DECLINE"), &HandleDecline);
        sAddonComm->Register(std::string("GF_GUILD_INFO"), &HandleGuildInfo);
    }
};

class guild_finder_guild : public GuildScript
{
public:
    guild_finder_guild() : GuildScript("guild_finder_guild") {}

    // joined a guild: his applications are done with
    void OnAddMember(Guild* guild, Player* player, uint8& /*plRank*/) override
    {
        ObjectGuid::LowType me = player->GetGUID().GetCounter();
        RemoveApplications([me](Application const& app) { return app.Player == me; });
        NotifyInviters(guild->GetId());
    }

    void OnDisband(Guild* guild) override
    {
        ObjectGuid::LowType guildId = guild->GetId();
        RemoveApplications([guildId](Application const& app) { return app.Guild == guildId; });
        s_settings.erase(guildId);
        CharacterDatabase.Execute(Trinity::StringFormat("DELETE FROM guild_finder_guild_settings WHERE guildId = {}", guildId).c_str());
    }
};

void AddSC_guild_finder()
{
    new guild_finder_world();
    new guild_finder_player();
    new guild_finder_guild();
}
