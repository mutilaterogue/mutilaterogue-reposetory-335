/*
 * Premade Groups (retail: LFGList) for 3.3.5 - ported from Legion TrinityCore's
 * LFGListMgr (GroupFinder/LFGList*.cpp) onto AddonComm.
 *
 * Activities: world.premade_category / premade_activity_group / premade_activity (sql/world_premade_groups.sql).
 *
 * Listing (LFGListEntry): one per group. A player with no group lists - a group of one is made for him
 * (core/Group_solo.patch keeps it), as Legion does. Only the leader (or a raid assistant) lists, updates, delists.
 * A listing lives GROUP_TIMEOUT without an update (retail: 30 minutes), then it is delisted.
 * Delisted: the group disbands, or the leader delists, or the group the module made for him is left with nobody else.
 *
 * Application (LFGListApplicationEntry): a player with no group applies with his roles and a note.
 * At most MAX_APPLICATIONS at a time. Applied: APPLY_TIMEOUT to be invited or declined; invited: INVITE_TIMEOUT
 * to answer. Accepted - he joins the group (with his roles as the group's LFG roles); the party becomes a raid
 * when the activity is for more than 5. Joining any group cancels his other applications.
 * Auto accept: an applicant is invited right away while the group has room.
 *
 * Statuses (retail LFGListApplicationStatus):
 *   0 none, 1 applied, 2 invited, 3 failed, 4 cancelled, 5 declined, 6 declined_full, 7 declined_delisted,
 *   8 timedout, 9 invitedeclined, 10 inviteaccepted
 * Roles: 1 tank, 2 healer, 4 damage (a bit mask).
 *
 * Free text (names, notes, the search filter) is percent-encoded both ways ("%3A" for ':' etc.):
 * the client encodes, the server decodes, the server encodes what it sends back.
 *
 * AddonComm (client: GroupFinder\LFGList*.lua, C_LFGList):
 *  C->S "LG_DATA"                          -> "LG_CATS" : id;name,...
 *                                             "LG_GROUPS" : id;categoryId;name,...
 *                                             "LG_ACTS" : id;categoryId;groupId;name;shortName;minLevel;maxPlayers;itemLevel;mapId;difficulty,...
 *       "LG_CREATE" : activityId : itemLevel : autoAccept : private : name : comment : voiceChat : minRating
 *       "LG_UPDATE" : activityId : itemLevel : autoAccept : private : name : comment : voiceChat : minRating
 *                     (mythic+ activity: the name may be empty - "+level dungeon" from the leader's keystone)
 *       "LG_DELIST"
 *       "LG_SEARCH" : categoryId : filter  -> "LG_RESULTS" : result,...  (below)
 *       "LG_APPLY" : listingId : roles : comment
 *       "LG_CANCEL" : listingId
 *       "LG_INVITE" : applicationId         (leader / assistant)
 *       "LG_DECLINE" : applicationId        (leader / assistant)
 *       "LG_ANSWER" : listingId : 1 / 0     (accept / decline the invite)
 *       "LG_STATUS"                         -> "LG_ENTRY", "LG_APPS", "LG_APPLICANTS"
 *  S->C "LG_ENTRY" : listingId : activityId : itemLevel : autoAccept : private : name : comment : seconds left
 *                    : voiceChat : minRating : keyLevel
 *                    ("LG_ENTRY" : 0 - not listed)
 *       "LG_APPS" : listingId;status;seconds left;roles,...      (my applications)
 *       "LG_APP" : listingId : status : seconds left : roles      (one of them changed)
 *       "LG_APPLICANTS" : applicationId;name;class;level;itemLevel;roles;status;comment;new;rating,...   (my group's)
 *       "LG_RESULTS" : listingId;activityId;leaderName;leaderClass;name;comment;itemLevel;age;autoAccept;
 *                      numMembers;tanks;healers;damage;myStatus;members;keyLevel;leaderRating;minRating;hasVoiceChat,...
 *                      members: class.role.isLeader/class.role.isLeader/...
 *       "LG_RESULT" : message
 *
 * GM: .lg list, .lg reload
 *
 * Setup: core/Group_solo.patch, sql/world_premade_groups.sql, AddSC_premade_groups() in custom_script_loader.cpp.
 */

#include "ScriptMgr.h"
#include "Custom\AddonComm\AddonComm.h"
#include "Chat.h"
#include "ChatCommand.h"
#include "DatabaseEnv.h"
#include "GameTime.h"
#include "Group.h"
#include "GroupMgr.h"
#include "Log.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "RBAC.h"
#include "StringFormat.h"
#include "World.h"
#include "WorldSession.h"

#include <algorithm>
#include <cctype>
#include <map>
#include <sstream>
#include <vector>

using namespace Trinity::ChatCommands;

// mythic_plus.cpp
bool MythicPlus_GetKeystone(ObjectGuid::LowType guid, uint32& mapId, uint32& level);
uint32 MythicPlus_GetRating(ObjectGuid::LowType guid);

namespace
{
    // ---------------------------------------------------------------- config
    constexpr uint32 UPDATE_INTERVAL  = 1 * IN_MILLISECONDS;
    constexpr uint32 GROUP_TIMEOUT    = 30 * MINUTE;    // a listing without an update
    constexpr uint32 APPLY_TIMEOUT    = 5 * MINUTE;     // an application not answered
    constexpr uint32 INVITE_TIMEOUT   = 1 * MINUTE;     // an invite not answered
    constexpr uint32 MAX_APPLICATIONS = 5;
    constexpr size_t MAX_NAME         = 31;             // bytes (retail: 31 characters)
    constexpr size_t MAX_COMMENT      = 255;
    constexpr uint32 MAX_RESULTS      = 100;
    constexpr uint32 DIFFICULTY_MYTHIC_PLUS = 3;        // premade_activity.difficulty of a keystone activity

    enum Role : uint8
    {
        ROLE_TANK   = 0x1,
        ROLE_HEALER = 0x2,
        ROLE_DAMAGE = 0x4,
        ROLE_ALL    = ROLE_TANK | ROLE_HEALER | ROLE_DAMAGE,
    };

    enum Status : uint8
    {
        STATUS_NONE              = 0,
        STATUS_APPLIED           = 1,
        STATUS_INVITED           = 2,
        STATUS_FAILED            = 3,
        STATUS_CANCELLED         = 4,
        STATUS_DECLINED          = 5,
        STATUS_DECLINED_FULL     = 6,
        STATUS_DECLINED_DELISTED = 7,
        STATUS_TIMEDOUT          = 8,
        STATUS_INVITE_DECLINED   = 9,
        STATUS_INVITE_ACCEPTED   = 10,
    };

    struct Category
    {
        uint32 Id = 0;
        std::string Name;
    };

    struct ActivityGroup
    {
        uint32 Id = 0;
        uint32 CategoryId = 0;
        std::string Name;
    };

    struct Activity
    {
        uint32 Id = 0;
        uint32 CategoryId = 0;
        uint32 GroupId = 0;
        std::string Name;
        std::string ShortName;
        uint32 MinLevel = 1;
        uint32 MaxPlayers = 5;
        uint32 ItemLevel = 0;
        uint32 MapId = 0;
        uint32 Difficulty = 0;
    };

    struct Listing
    {
        uint32 Id = 0;
        ObjectGuid GroupGuid;
        uint32 ActivityId = 0;
        uint32 ItemLevel = 0;
        bool AutoAccept = false;
        bool Private = false;
        std::string Name;
        std::string Comment;
        time_t Created = 0;
        time_t Expires = 0;
        bool MadeGroup = false;     // the module made the group of one for its leader
        std::string VoiceChat;
        uint32 MinRating = 0;       // mythic+ rating the applicants need (0 - any)
        uint32 KeyLevel = 0;        // mythic+: the leader's keystone level for this dungeon (0 - none)
        uint32 LeaderRating = 0;
    };

    struct Application
    {
        uint32 Id = 0;
        uint32 ListingId = 0;
        ObjectGuid PlayerGuid;
        uint8 Roles = 0;
        std::string Comment;
        uint8 Status = STATUS_APPLIED;
        time_t Expires = 0;
        bool New = true;            // not seen by the leader yet (retail: the "new" applicants)
        uint32 Rating = 0;          // mythic+ rating when he applied
    };

    std::vector<Category> s_categories;
    std::vector<ActivityGroup> s_groups;
    std::map<uint32, Activity> s_activities;
    std::vector<uint32> s_activityOrder;

    std::map<uint32, Listing> s_listings;
    std::map<ObjectGuid, uint32> s_listingByGroup;
    std::map<uint32, Application> s_applications;
    uint32 s_nextListing = 1;
    uint32 s_nextApplication = 1;

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

    std::string Lower(std::string text)
    {
        // ASCII and the Cyrillic of UTF-8 (capital -> small, YO too)
        std::string out;
        for (size_t i = 0; i < text.size(); ++i)
        {
            unsigned char c = text[i];
            if (c < 0x80)
                out += char(std::tolower(c));
            else if (c == 0xD0 && i + 1 < text.size())
            {
                unsigned char n = text[++i];
                if (n >= 0x90 && n <= 0x9F)         // D0 90..9F -> D0 B0..BF
                    out += char(0xD0), out += char(n + 0x20);
                else if (n >= 0xA0 && n <= 0xAF)    // D0 A0..AF -> D1 80..8F
                    out += char(0xD1), out += char(n - 0x20);
                else if (n == 0x81)                 // D0 81 -> D1 91
                    out += char(0xD1), out += char(0x91);
                else
                    out += char(c), out += char(n);
            }
            else
                out += char(c);
        }
        return out;
    }

    uint32 Arg(std::vector<std::string> const& args, size_t index)
    {
        if (index >= args.size() || args[index].empty())
            return 0;
        try { return uint32(std::stoul(args[index])); }
        catch (...) { return 0; }
    }

    std::string TextArg(std::vector<std::string> const& args, size_t index)
    {
        return index < args.size() ? Decode(args[index]) : std::string();
    }

    void Result(Player* player, std::string const& text)
    {
        sAddonComm->Send(player, "LG_RESULT", Encode(text));
    }

    // ---------------------------------------------------------------- data
    void LoadData()
    {
        s_categories.clear();
        s_groups.clear();
        s_activities.clear();
        s_activityOrder.clear();

        if (QueryResult result = WorldDatabase.Query("SELECT CAST(id AS SIGNED), name FROM premade_category ORDER BY `order`, id"))
        {
            do
            {
                Field* fields = result->Fetch();
                s_categories.push_back({ uint32(fields[0].GetInt64()), fields[1].GetString() });
            } while (result->NextRow());
        }

        if (QueryResult result = WorldDatabase.Query("SELECT CAST(id AS SIGNED), CAST(category_id AS SIGNED), name FROM premade_activity_group ORDER BY `order`, id"))
        {
            do
            {
                Field* fields = result->Fetch();
                s_groups.push_back({ uint32(fields[0].GetInt64()), uint32(fields[1].GetInt64()), fields[2].GetString() });
            } while (result->NextRow());
        }

        if (QueryResult result = WorldDatabase.Query("SELECT CAST(id AS SIGNED), CAST(category_id AS SIGNED), CAST(group_id AS SIGNED), name, short_name, "
            "CAST(min_level AS SIGNED), CAST(max_players AS SIGNED), CAST(min_item_level AS SIGNED), CAST(map_id AS SIGNED), CAST(difficulty AS SIGNED) "
            "FROM premade_activity ORDER BY `order`, id"))
        {
            do
            {
                Field* fields = result->Fetch();
                Activity activity;
                activity.Id = uint32(fields[0].GetInt64());
                activity.CategoryId = uint32(fields[1].GetInt64());
                activity.GroupId = uint32(fields[2].GetInt64());
                activity.Name = fields[3].GetString();
                activity.ShortName = fields[4].GetString();
                activity.MinLevel = uint32(fields[5].GetInt64());
                activity.MaxPlayers = std::max<uint32>(2, uint32(fields[6].GetInt64()));
                activity.ItemLevel = uint32(fields[7].GetInt64());
                activity.MapId = uint32(fields[8].GetInt64());
                activity.Difficulty = uint32(fields[9].GetInt64());
                s_activities[activity.Id] = activity;
                s_activityOrder.push_back(activity.Id);
            } while (result->NextRow());
        }

        TC_LOG_INFO("server.loading", ">> premade_groups: {} categories, {} activity groups, {} activities",
            s_categories.size(), s_groups.size(), s_activities.size());
    }

    Activity const* GetActivity(uint32 id)
    {
        auto itr = s_activities.find(id);
        return itr != s_activities.end() ? &itr->second : nullptr;
    }

    // ---------------------------------------------------------------- helpers
    Listing* GetListing(uint32 id)
    {
        auto itr = s_listings.find(id);
        return itr != s_listings.end() ? &itr->second : nullptr;
    }

    Listing* GetGroupListing(Group const* group)
    {
        if (!group)
            return nullptr;
        auto itr = s_listingByGroup.find(group->GetGUID());
        return itr != s_listingByGroup.end() ? GetListing(itr->second) : nullptr;
    }

    Group* GetListingGroup(Listing const& listing)
    {
        return sGroupMgr->GetGroupByGUID(listing.GroupGuid);
    }

    bool CanManage(Player* player, Group const* group)
    {
        return group && (group->IsLeader(player->GetGUID()) || (group->isRaidGroup() && group->IsAssistant(player->GetGUID())));
    }

    bool IsActive(Application const& application)
    {
        return application.Status == STATUS_APPLIED || application.Status == STATUS_INVITED;
    }

    Application* FindApplication(ObjectGuid player, uint32 listingId)
    {
        for (auto& pair : s_applications)
            if (pair.second.PlayerGuid == player && pair.second.ListingId == listingId && IsActive(pair.second))
                return &pair.second;
        return nullptr;
    }

    uint32 CountApplications(ObjectGuid player)
    {
        uint32 count = 0;
        for (auto const& pair : s_applications)
            if (pair.second.PlayerGuid == player && IsActive(pair.second))
                ++count;
        return count;
    }

    uint32 MaxPlayers(Listing const& listing)
    {
        Activity const* activity = GetActivity(listing.ActivityId);
        return activity ? activity->MaxPlayers : 5;
    }

    // retail role mask (1 tank, 2 healer, 4 damage) <-> the core's LFG roles (PLAYER_ROLE_TANK 0x02 ...)
    uint8 ToLfgRoles(uint8 roles)
    {
        return uint8((roles & ROLE_ALL) << 1);
    }

    uint8 FromLfgRoles(uint8 roles)
    {
        uint8 result = uint8((roles >> 1) & ROLE_ALL);
        return result ? result : uint8(ROLE_DAMAGE);
    }

    // one role for the member counts: tank before healer before damage
    uint8 MainRole(uint8 roles)
    {
        if (roles & ROLE_TANK)
            return ROLE_TANK;
        if (roles & ROLE_HEALER)
            return ROLE_HEALER;
        return ROLE_DAMAGE;
    }

    uint32 SecondsLeft(time_t expires)
    {
        time_t now = GameTime::GetGameTime();
        return expires > now ? uint32(expires - now) : 0;
    }

    // ---------------------------------------------------------------- send
    void SendData(Player* player)
    {
        std::ostringstream cats;
        for (size_t i = 0; i < s_categories.size(); ++i)
            cats << (i ? "," : "") << s_categories[i].Id << ';' << Encode(s_categories[i].Name);
        sAddonComm->Send(player, "LG_CATS", s_categories.empty() ? std::string("-") : cats.str());

        std::ostringstream groups;
        for (size_t i = 0; i < s_groups.size(); ++i)
            groups << (i ? "," : "") << s_groups[i].Id << ';' << s_groups[i].CategoryId << ';' << Encode(s_groups[i].Name);
        sAddonComm->Send(player, "LG_GROUPS", s_groups.empty() ? std::string("-") : groups.str());

        std::ostringstream acts;
        bool first = true;
        for (uint32 id : s_activityOrder)
        {
            Activity const& a = s_activities.at(id);
            acts << (first ? "" : ",") << a.Id << ';' << a.CategoryId << ';' << a.GroupId << ';' << Encode(a.Name) << ';'
                 << Encode(a.ShortName) << ';' << a.MinLevel << ';' << a.MaxPlayers << ';' << a.ItemLevel << ';'
                 << a.MapId << ';' << a.Difficulty;
            first = false;
        }
        sAddonComm->Send(player, "LG_ACTS", first ? std::string("-") : acts.str());
    }

    void SendEntry(Player* player)
    {
        Listing const* listing = GetGroupListing(player->GetGroup());
        if (!listing)
        {
            sAddonComm->Send(player, "LG_ENTRY", 0);
            return;
        }
        sAddonComm->Send(player, "LG_ENTRY", listing->Id, listing->ActivityId, listing->ItemLevel, listing->AutoAccept ? 1 : 0,
            listing->Private ? 1 : 0, Encode(listing->Name), Encode(listing->Comment), SecondsLeft(listing->Expires),
            Encode(listing->VoiceChat), listing->MinRating, listing->KeyLevel);
    }

    void SendApplications(Player* player)
    {
        std::ostringstream list;
        bool first = true;
        for (auto const& pair : s_applications)
        {
            Application const& app = pair.second;
            if (app.PlayerGuid != player->GetGUID() || !IsActive(app))
                continue;
            list << (first ? "" : ",") << app.ListingId << ';' << uint32(app.Status) << ';' << SecondsLeft(app.Expires) << ';' << uint32(app.Roles);
            first = false;
        }
        sAddonComm->Send(player, "LG_APPS", first ? std::string("-") : list.str());
    }

    void SendApplicationStatus(Application const& app)
    {
        if (Player* player = ObjectAccessor::FindConnectedPlayer(app.PlayerGuid))
            sAddonComm->Send(player, "LG_APP", app.ListingId, uint32(app.Status), SecondsLeft(app.Expires), uint32(app.Roles));
    }

    void SendApplicants(Player* player)
    {
        Group* group = player->GetGroup();
        Listing const* listing = GetGroupListing(group);
        std::ostringstream list;
        bool first = true;
        if (listing && CanManage(player, group))
        {
            for (auto const& pair : s_applications)
            {
                Application const& app = pair.second;
                if (app.ListingId != listing->Id || !IsActive(app))
                    continue;
                Player* applicant = ObjectAccessor::FindConnectedPlayer(app.PlayerGuid);
                if (!applicant)
                    continue;
                list << (first ? "" : ",") << app.Id << ';' << Encode(applicant->GetName()) << ';' << uint32(applicant->GetClass()) << ';'
                     << uint32(applicant->GetLevel()) << ';' << uint32(applicant->GetAverageItemLevel()) << ';' << uint32(app.Roles) << ';'
                     << uint32(app.Status) << ';' << Encode(app.Comment) << ';' << (app.New ? 1 : 0) << ';' << app.Rating;
                first = false;
            }
        }
        sAddonComm->Send(player, "LG_APPLICANTS", first ? std::string("-") : list.str());
    }

    // the leader and the assistants of a listed group
    void UpdateManagers(Listing const& listing)
    {
        Group* group = GetListingGroup(listing);
        if (!group)
            return;
        for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
            if (Player* member = ref->GetSource())
                if (CanManage(member, group))
                    SendApplicants(member);
    }

    // every member of a group: its listing changed
    void UpdateMembers(Group* group)
    {
        if (!group)
            return;
        for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
            if (Player* member = ref->GetSource())
            {
                SendEntry(member);
                SendApplicants(member);
            }
    }

    // ---------------------------------------------------------------- applications
    // an application finished: the applicant told, then forgotten
    void FinishApplication(uint32 id, uint8 status, bool updateManagers = true)
    {
        auto itr = s_applications.find(id);
        if (itr == s_applications.end())
            return;
        Application app = itr->second;
        s_applications.erase(itr);
        app.Status = status;
        app.Expires = 0;
        SendApplicationStatus(app);
        if (updateManagers)
            if (Listing const* listing = GetListing(app.ListingId))
                UpdateManagers(*listing);
    }

    void CancelPlayerApplications(ObjectGuid player, uint8 status, uint32 exceptListing = 0)
    {
        std::vector<uint32> ids;
        for (auto const& pair : s_applications)
            if (pair.second.PlayerGuid == player && pair.second.ListingId != exceptListing)
                ids.push_back(pair.first);
        for (uint32 id : ids)
            FinishApplication(id, status);
    }

    void Invite(Application& app)
    {
        app.Status = STATUS_INVITED;
        app.Expires = GameTime::GetGameTime() + INVITE_TIMEOUT;
        SendApplicationStatus(app);
        if (Listing const* listing = GetListing(app.ListingId))
            UpdateManagers(*listing);
    }

    // auto accept: invite the applicants while the group has room for them
    void AutoInvite(Listing const& listing)
    {
        if (!listing.AutoAccept)
            return;
        Group* group = GetListingGroup(listing);
        if (!group)
            return;
        uint32 taken = group->GetMembersCount();
        for (auto const& pair : s_applications)
            if (pair.second.ListingId == listing.Id && pair.second.Status == STATUS_INVITED)
                ++taken;
        for (auto& pair : s_applications)
        {
            if (taken >= MaxPlayers(listing))
                break;
            if (pair.second.ListingId == listing.Id && pair.second.Status == STATUS_APPLIED)
            {
                Invite(pair.second);
                ++taken;
            }
        }
    }

    // the group is full: nobody else gets in
    void DeclineIfFull(Listing const& listing)
    {
        Group* group = GetListingGroup(listing);
        if (!group || group->GetMembersCount() < MaxPlayers(listing))
            return;
        std::vector<uint32> ids;
        for (auto const& pair : s_applications)
            if (pair.second.ListingId == listing.Id)
                ids.push_back(pair.first);
        for (uint32 id : ids)
            FinishApplication(id, STATUS_DECLINED_FULL, false);
        UpdateManagers(listing);
    }

    // ---------------------------------------------------------------- listings
    void Delist(uint32 listingId, bool disbandMadeGroup)
    {
        auto itr = s_listings.find(listingId);
        if (itr == s_listings.end())
            return;
        Listing listing = itr->second;
        s_listings.erase(itr);
        s_listingByGroup.erase(listing.GroupGuid);

        std::vector<uint32> ids;
        for (auto const& pair : s_applications)
            if (pair.second.ListingId == listing.Id)
                ids.push_back(pair.first);
        for (uint32 id : ids)
            FinishApplication(id, STATUS_DECLINED_DELISTED, false);

        Group* group = GetListingGroup(listing);
        if (!group)
            return;
        // the group of one the module made for the listing: not needed any more
        if (disbandMadeGroup && listing.MadeGroup && group->GetMembersCount() <= 1)
        {
            group->Disband();
            return;
        }
        UpdateMembers(group);
    }

    // the listing's fields from the arguments: activityId : itemLevel : autoAccept : private : name : comment
    bool ReadListing(Player* player, std::vector<std::string> const& args, Listing& listing)
    {
        Activity const* activity = GetActivity(Arg(args, 0));
        if (!activity)
        {
            Result(player, "\xd0\x9d\xd0\xb5\xd0\xb8\xd0\xb7\xd0\xb2\xd0\xb5\xd1\x81\xd1\x82\xd0\xbd\xd0\xb0\xd1\x8f \xd0\xb0\xd0\xba\xd1\x82\xd0\xb8\xd0\xb2\xd0\xbd\xd0\xbe\xd1\x81\xd1\x82\xd1\x8c.");
            return false;
        }
        if (player->GetLevel() < activity->MinLevel)
        {
            Result(player, Trinity::StringFormat("\xd0\x94\xd0\xbb\xd1\x8f \xd1\x8d\xd1\x82\xd0\xbe\xd0\xb9 \xd0\xb0\xd0\xba\xd1\x82\xd0\xb8\xd0\xb2\xd0\xbd\xd0\xbe\xd1\x81\xd1\x82\xd0\xb8 \xd0\xbd\xd1\x83\xd0\xb6\xd0\xb5\xd0\xbd {} \xd1\x83\xd1\x80\xd0\xbe\xd0\xb2\xd0\xb5\xd0\xbd\xd1\x8c.", activity->MinLevel));
            return false;
        }
        uint32 itemLevel = Arg(args, 1);
        if (itemLevel && float(itemLevel) > player->GetAverageItemLevel())
        {
            Result(player, "\xd0\xa2\xd1\x80\xd0\xb5\xd0\xb1\xd1\x83\xd0\xb5\xd0\xbc\xd1\x8b\xd0\xb9 \xd1\x83\xd1\x80\xd0\xbe\xd0\xb2\xd0\xb5\xd0\xbd\xd1\x8c \xd0\xbf\xd1\x80\xd0\xb5\xd0\xb4\xd0\xbc\xd0\xb5\xd1\x82\xd0\xbe\xd0\xb2 \xd0\xb2\xd1\x8b\xd1\x88\xd0\xb5 \xd0\xb2\xd0\xb0\xd1\x88\xd0\xb5\xd0\xb3\xd0\xbe.");
            return false;
        }
        std::string name = Truncate(TextArg(args, 4), MAX_NAME);
        uint32 keyLevel = 0;
        if (activity->Difficulty == DIFFICULTY_MYTHIC_PLUS)
        {
            uint32 keyMap = 0, level = 0;
            if (MythicPlus_GetKeystone(player->GetGUID().GetCounter(), keyMap, level) && keyMap == activity->MapId)
                keyLevel = level;
            // retail: a keystone group is named after the key
            if (name.empty())
                name = Truncate(keyLevel ? Trinity::StringFormat("+{} {}", keyLevel, activity->Name) : activity->Name, MAX_NAME);
        }
        if (name.empty())
        {
            Result(player, "\xd0\x92\xd0\xb2\xd0\xb5\xd0\xb4\xd0\xb8\xd1\x82\xd0\xb5 \xd0\xbd\xd0\xb0\xd0\xb7\xd0\xb2\xd0\xb0\xd0\xbd\xd0\xb8\xd0\xb5 \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd1\x8b.");
            return false;
        }
        uint32 rating = MythicPlus_GetRating(player->GetGUID().GetCounter());
        uint32 minRating = Arg(args, 7);
        if (minRating && minRating > rating)
        {
            Result(player, "\xd0\xa2\xd1\x80\xd0\xb5\xd0\xb1\xd1\x83\xd0\xb5\xd0\xbc\xd1\x8b\xd0\xb9 \xd1\x80\xd0\xb5\xd0\xb9\xd1\x82\xd0\xb8\xd0\xbd\xd0\xb3 \xd0\xb2\xd1\x8b\xd1\x88\xd0\xb5 \xd0\xb2\xd0\xb0\xd1\x88\xd0\xb5\xd0\xb3\xd0\xbe.");
            return false;
        }
        Group* group = player->GetGroup();
        if (group && group->GetMembersCount() > activity->MaxPlayers)
        {
            Result(player, "\xd0\x92 \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd0\xb5 \xd0\xb1\xd0\xbe\xd0\xbb\xd1\x8c\xd1\x88\xd0\xb5 \xd0\xb8\xd0\xb3\xd1\x80\xd0\xbe\xd0\xba\xd0\xbe\xd0\xb2, \xd1\x87\xd0\xb5\xd0\xbc \xd0\xbd\xd1\x83\xd0\xb6\xd0\xbd\xd0\xbe \xd0\xb4\xd0\xbb\xd1\x8f \xd1\x8d\xd1\x82\xd0\xbe\xd0\xb9 \xd0\xb0\xd0\xba\xd1\x82\xd0\xb8\xd0\xb2\xd0\xbd\xd0\xbe\xd1\x81\xd1\x82\xd0\xb8.");
            return false;
        }
        listing.ActivityId = activity->Id;
        listing.ItemLevel = itemLevel;
        listing.AutoAccept = Arg(args, 2) != 0;
        listing.Private = Arg(args, 3) != 0;
        listing.Name = name;
        listing.Comment = Truncate(TextArg(args, 5), MAX_COMMENT);
        listing.VoiceChat = Truncate(TextArg(args, 6), MAX_NAME);
        listing.MinRating = minRating;
        listing.KeyLevel = keyLevel;
        listing.LeaderRating = rating;
        return true;
    }

    std::string ResultEntry(Listing const& listing, Player* viewer)
    {
        Group* group = GetListingGroup(listing);
        Player* leader = group ? ObjectAccessor::FindConnectedPlayer(group->GetLeaderGUID()) : nullptr;
        uint32 tanks = 0, healers = 0, damage = 0;
        std::ostringstream members;
        bool first = true;
        if (group)
        {
            for (Group::MemberSlot const& slot : group->GetMemberSlots())
            {
                uint8 role = MainRole(FromLfgRoles(slot.roles));
                ++(role == ROLE_TANK ? tanks : role == ROLE_HEALER ? healers : damage);
                Player* member = ObjectAccessor::FindConnectedPlayer(slot.guid);
                members << (first ? "" : "/") << uint32(member ? member->GetClass() : 0) << '.' << uint32(role) << '.'
                        << (slot.guid == group->GetLeaderGUID() ? 1 : 0);
                first = false;
            }
        }
        Application const* app = FindApplication(viewer->GetGUID(), listing.Id);
        std::ostringstream entry;
        entry << listing.Id << ';' << listing.ActivityId << ';' << Encode(leader ? leader->GetName() : std::string()) << ';'
              << uint32(leader ? leader->GetClass() : 0) << ';' << Encode(listing.Name) << ';' << Encode(listing.Comment) << ';'
              << listing.ItemLevel << ';' << uint32(GameTime::GetGameTime() - listing.Created) << ';' << (listing.AutoAccept ? 1 : 0) << ';'
              << (group ? group->GetMembersCount() : 0) << ';' << tanks << ';' << healers << ';' << damage << ';'
              << uint32(app ? app->Status : STATUS_NONE) << ';' << (first ? std::string("-") : members.str()) << ';'
              << listing.KeyLevel << ';' << listing.LeaderRating << ';' << listing.MinRating << ';' << (listing.VoiceChat.empty() ? 0 : 1);
        return entry.str();
    }

    // ---------------------------------------------------------------- handlers
    void HandleData(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendData(player);
    }

    void HandleStatus(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendEntry(player);
        SendApplications(player);
        SendApplicants(player);
    }

    void HandleCreate(Player* player, std::vector<std::string> const& args)
    {
        Group* group = player->GetGroup();
        if (GetGroupListing(group))
        {
            Result(player, "\xd0\x92\xd0\xb0\xd1\x88\xd0\xb0 \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd0\xb0 \xd1\x83\xd0\xb6\xd0\xb5 \xd0\xb2 \xd1\x81\xd0\xbf\xd0\xb8\xd1\x81\xd0\xba\xd0\xb5.");
            return;
        }
        if (group && !CanManage(player, group))
        {
            Result(player, "\xd0\xa2\xd0\xbe\xd0\xbb\xd1\x8c\xd0\xba\xd0\xbe \xd0\xbb\xd0\xb8\xd0\xb4\xd0\xb5\xd1\x80 \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd1\x8b \xd0\xbc\xd0\xbe\xd0\xb6\xd0\xb5\xd1\x82 \xd1\x81\xd0\xbe\xd0\xb7\xd0\xb4\xd0\xb0\xd1\x82\xd1\x8c \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd1\x83 \xd0\xb2 \xd1\x81\xd0\xbf\xd0\xb8\xd1\x81\xd0\xba\xd0\xb5.");
            return;
        }

        Listing listing;
        if (!ReadListing(player, args, listing))
            return;

        // a player with no group: a group of one (Legion: LFGListMgr::Insert -> Group::Create)
        if (!group)
        {
            group = new Group();
            if (!group->Create(player))
            {
                delete group;
                Result(player, "\xd0\x9d\xd0\xb5 \xd1\x83\xd0\xb4\xd0\xb0\xd0\xbb\xd0\xbe\xd1\x81\xd1\x8c \xd1\x81\xd0\xbe\xd0\xb7\xd0\xb4\xd0\xb0\xd1\x82\xd1\x8c \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd1\x83.");
                return;
            }
            sGroupMgr->AddGroup(group);
            group->SetAllowSolo(true);      // core/Group_solo.patch: a group of one stays a group
            listing.MadeGroup = true;
        }
        if (Activity const* activity = GetActivity(listing.ActivityId))
            if (activity->MaxPlayers > 5 && !group->isRaidGroup())
                group->ConvertToRaid();

        // the applications of a player who lists a group are of no use (Legion: he can't apply while listed)
        CancelPlayerApplications(player->GetGUID(), STATUS_CANCELLED);

        listing.Id = s_nextListing++;
        listing.GroupGuid = group->GetGUID();
        listing.Created = GameTime::GetGameTime();
        listing.Expires = listing.Created + GROUP_TIMEOUT;
        s_listings[listing.Id] = listing;
        s_listingByGroup[listing.GroupGuid] = listing.Id;
        UpdateMembers(group);
    }

    void HandleUpdate(Player* player, std::vector<std::string> const& args)
    {
        Group* group = player->GetGroup();
        Listing* listing = GetGroupListing(group);
        if (!listing || !CanManage(player, group))
            return;
        Listing updated = *listing;
        if (!ReadListing(player, args, updated))
            return;
        if (Activity const* activity = GetActivity(updated.ActivityId))
            if (activity->MaxPlayers > 5 && !group->isRaidGroup())
                group->ConvertToRaid();
        updated.Expires = GameTime::GetGameTime() + GROUP_TIMEOUT;
        *listing = updated;
        UpdateMembers(group);
        AutoInvite(*listing);
    }

    void HandleDelist(Player* player, std::vector<std::string> const& /*args*/)
    {
        Group* group = player->GetGroup();
        Listing const* listing = GetGroupListing(group);
        if (!listing || !CanManage(player, group))
            return;
        Delist(listing->Id, false);
    }

    void HandleSearch(Player* player, std::vector<std::string> const& args)
    {
        uint32 categoryId = Arg(args, 0);
        std::string filter = Lower(TextArg(args, 1));
        Listing const* own = GetGroupListing(player->GetGroup());

        std::vector<Listing const*> found;
        for (auto const& pair : s_listings)
        {
            Listing const& listing = pair.second;
            Activity const* activity = GetActivity(listing.ActivityId);
            if (!activity || (categoryId && activity->CategoryId != categoryId))
                continue;
            if (listing.Private && &listing != own)
                continue;
            if (!filter.empty() && Lower(listing.Name).find(filter) == std::string::npos
                && Lower(listing.Comment).find(filter) == std::string::npos
                && Lower(activity->Name).find(filter) == std::string::npos)
                continue;
            found.push_back(&listing);
        }
        // newest first (retail)
        std::sort(found.begin(), found.end(), [](Listing const* a, Listing const* b) { return a->Created > b->Created; });
        if (found.size() > MAX_RESULTS)
            found.resize(MAX_RESULTS);

        std::ostringstream list;
        for (size_t i = 0; i < found.size(); ++i)
            list << (i ? "," : "") << ResultEntry(*found[i], player);
        sAddonComm->Send(player, "LG_RESULTS", found.empty() ? std::string("-") : list.str());
    }

    void HandleApply(Player* player, std::vector<std::string> const& args)
    {
        Listing* listing = GetListing(Arg(args, 0));
        uint8 roles = uint8(Arg(args, 1) & ROLE_ALL);
        if (!listing)
        {
            Result(player, "\xd0\xad\xd1\x82\xd0\xb0 \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd0\xb0 \xd0\xb1\xd0\xbe\xd0\xbb\xd1\x8c\xd1\x88\xd0\xb5 \xd0\xbd\xd0\xb5 \xd0\xb2 \xd1\x81\xd0\xbf\xd0\xb8\xd1\x81\xd0\xba\xd0\xb5.");
            return;
        }
        if (!roles)
        {
            Result(player, "\xd0\x92\xd1\x8b\xd0\xb1\xd0\xb5\xd1\x80\xd0\xb8\xd1\x82\xd0\xb5 \xd1\x80\xd0\xbe\xd0\xbb\xd1\x8c.");
            return;
        }
        if (player->GetGroup())
        {
            Result(player, "\xd0\x92\xd1\x8b \xd1\x83\xd0\xb6\xd0\xb5 \xd0\xb2 \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd0\xb5.");
            return;
        }
        if (FindApplication(player->GetGUID(), listing->Id))
            return;
        if (CountApplications(player->GetGUID()) >= MAX_APPLICATIONS)
        {
            Result(player, Trinity::StringFormat("\xd0\x9c\xd0\xbe\xd0\xb6\xd0\xbd\xd0\xbe \xd0\xbf\xd0\xbe\xd0\xb4\xd0\xb0\xd1\x82\xd1\x8c \xd0\xbd\xd0\xb5 \xd0\xb1\xd0\xbe\xd0\xbb\xd1\x8c\xd1\x88\xd0\xb5 {} \xd0\xb7\xd0\xb0\xd1\x8f\xd0\xb2\xd0\xbe\xd0\xba \xd0\xbe\xd0\xb4\xd0\xbd\xd0\xbe\xd0\xb2\xd1\x80\xd0\xb5\xd0\xbc\xd0\xb5\xd0\xbd\xd0\xbd\xd0\xbe.", MAX_APPLICATIONS));
            return;
        }
        Activity const* activity = GetActivity(listing->ActivityId);
        if (activity && player->GetLevel() < activity->MinLevel)
        {
            Result(player, Trinity::StringFormat("\xd0\x94\xd0\xbb\xd1\x8f \xd1\x8d\xd1\x82\xd0\xbe\xd0\xb9 \xd0\xb0\xd0\xba\xd1\x82\xd0\xb8\xd0\xb2\xd0\xbd\xd0\xbe\xd1\x81\xd1\x82\xd0\xb8 \xd0\xbd\xd1\x83\xd0\xb6\xd0\xb5\xd0\xbd {} \xd1\x83\xd1\x80\xd0\xbe\xd0\xb2\xd0\xb5\xd0\xbd\xd1\x8c.", activity->MinLevel));
            return;
        }
        if (listing->ItemLevel && player->GetAverageItemLevel() < float(listing->ItemLevel))
        {
            Result(player, "\xd0\x92\xd0\xb0\xd1\x88 \xd1\x83\xd1\x80\xd0\xbe\xd0\xb2\xd0\xb5\xd0\xbd\xd1\x8c \xd0\xbf\xd1\x80\xd0\xb5\xd0\xb4\xd0\xbc\xd0\xb5\xd1\x82\xd0\xbe\xd0\xb2 \xd0\xbd\xd0\xb8\xd0\xb6\xd0\xb5 \xd1\x82\xd1\x80\xd0\xb5\xd0\xb1\xd1\x83\xd0\xb5\xd0\xbc\xd0\xbe\xd0\xb3\xd0\xbe.");
            return;
        }
        uint32 rating = MythicPlus_GetRating(player->GetGUID().GetCounter());
        if (listing->MinRating && rating < listing->MinRating)
        {
            Result(player, "\xd0\x92\xd0\xb0\xd1\x88 \xd1\x80\xd0\xb5\xd0\xb9\xd1\x82\xd0\xb8\xd0\xbd\xd0\xb3 \xd0\xbd\xd0\xb8\xd0\xb6\xd0\xb5 \xd1\x82\xd1\x80\xd0\xb5\xd0\xb1\xd1\x83\xd0\xb5\xd0\xbc\xd0\xbe\xd0\xb3\xd0\xbe.");
            return;
        }
        Group* group = GetListingGroup(*listing);
        if (!group || group->GetMembersCount() >= MaxPlayers(*listing))
        {
            Result(player, "\xd0\x93\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd0\xb0 \xd1\x83\xd0\xb6\xd0\xb5 \xd0\xb7\xd0\xb0\xd0\xbf\xd0\xbe\xd0\xbb\xd0\xbd\xd0\xb5\xd0\xbd\xd0\xb0.");
            return;
        }

        Application app;
        app.Rating = rating;
        app.Id = s_nextApplication++;
        app.ListingId = listing->Id;
        app.PlayerGuid = player->GetGUID();
        app.Roles = roles;
        app.Comment = Truncate(TextArg(args, 2), MAX_COMMENT);
        app.Expires = GameTime::GetGameTime() + APPLY_TIMEOUT;
        s_applications[app.Id] = app;

        SendApplicationStatus(app);
        UpdateManagers(*listing);
        AutoInvite(*listing);
    }

    void HandleCancel(Player* player, std::vector<std::string> const& args)
    {
        if (Application* app = FindApplication(player->GetGUID(), Arg(args, 0)))
            FinishApplication(app->Id, STATUS_CANCELLED);
    }

    // the leader's answer to an applicant
    Application* ManagedApplication(Player* player, uint32 id)
    {
        auto itr = s_applications.find(id);
        if (itr == s_applications.end())
            return nullptr;
        Group* group = player->GetGroup();
        Listing const* listing = GetGroupListing(group);
        if (!listing || itr->second.ListingId != listing->Id || !CanManage(player, group))
            return nullptr;
        return &itr->second;
    }

    void HandleInvite(Player* player, std::vector<std::string> const& args)
    {
        Application* app = ManagedApplication(player, Arg(args, 0));
        if (!app || app->Status != STATUS_APPLIED)
            return;
        Listing const* listing = GetListing(app->ListingId);
        Group* group = player->GetGroup();
        if (group->GetMembersCount() >= MaxPlayers(*listing))
        {
            Result(player, "\xd0\x93\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd0\xb0 \xd1\x83\xd0\xb6\xd0\xb5 \xd0\xb7\xd0\xb0\xd0\xbf\xd0\xbe\xd0\xbb\xd0\xbd\xd0\xb5\xd0\xbd\xd0\xb0.");
            return;
        }
        Invite(*app);
    }

    void HandleDecline(Player* player, std::vector<std::string> const& args)
    {
        if (Application* app = ManagedApplication(player, Arg(args, 0)))
            FinishApplication(app->Id, STATUS_DECLINED);
    }

    // the leader saw the applicants (retail: C_LFGList.RefreshApplicants / "new" marks)
    void HandleSeen(Player* player, std::vector<std::string> const& /*args*/)
    {
        Group* group = player->GetGroup();
        Listing const* listing = GetGroupListing(group);
        if (!listing || !CanManage(player, group))
            return;
        for (auto& pair : s_applications)
            if (pair.second.ListingId == listing->Id)
                pair.second.New = false;
        UpdateManagers(*listing);
    }

    void HandleAnswer(Player* player, std::vector<std::string> const& args)
    {
        Application* app = FindApplication(player->GetGUID(), Arg(args, 0));
        if (!app || app->Status != STATUS_INVITED)
            return;
        if (Arg(args, 1) == 0)
        {
            FinishApplication(app->Id, STATUS_INVITE_DECLINED);
            return;
        }

        Listing* listing = GetListing(app->ListingId);
        Group* group = listing ? GetListingGroup(*listing) : nullptr;
        if (!group || player->GetGroup() || group->GetMembersCount() >= MaxPlayers(*listing))
        {
            FinishApplication(app->Id, STATUS_FAILED);
            return;
        }

        uint32 id = app->Id;
        uint8 roles = app->Roles;
        uint32 listingId = listing->Id;
        // the other applications go first: joining the group cancels them anyway (OnAddMember)
        CancelPlayerApplications(player->GetGUID(), STATUS_CANCELLED, listingId);
        FinishApplication(id, STATUS_INVITE_ACCEPTED, false);

        if (group->GetMembersCount() >= 5 && !group->isRaidGroup())
            group->ConvertToRaid();
        if (!group->AddMember(player))
        {
            Result(player, "\xd0\x9d\xd0\xb5 \xd1\x83\xd0\xb4\xd0\xb0\xd0\xbb\xd0\xbe\xd1\x81\xd1\x8c \xd0\xb2\xd1\x81\xd1\x82\xd1\x83\xd0\xbf\xd0\xb8\xd1\x82\xd1\x8c \xd0\xb2 \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd1\x83.");
            return;
        }
        group->SetLfgRoles(player->GetGUID(), ToLfgRoles(roles));
        // the leader's group of one is a real group now: the core may break it up again as usual later
        listing = GetListing(listingId);
        if (!listing)
            return;
        listing->Expires = GameTime::GetGameTime() + GROUP_TIMEOUT;
        UpdateMembers(group);
        DeclineIfFull(*listing);
    }

    // ---------------------------------------------------------------- update
    void Update()
    {
        time_t now = GameTime::GetGameTime();

        std::vector<uint32> expired;
        for (auto const& pair : s_applications)
            if (pair.second.Expires && pair.second.Expires <= now)
                expired.push_back(pair.first);
        for (uint32 id : expired)
            FinishApplication(id, STATUS_TIMEDOUT);

        std::vector<uint32> delist;
        for (auto const& pair : s_listings)
            if (pair.second.Expires <= now || !GetListingGroup(pair.second))
                delist.push_back(pair.first);
        for (uint32 id : delist)
            Delist(id, true);
    }

    void OnGroupLeft(Group* group, ObjectGuid guid)
    {
        Listing const* listing = GetGroupListing(group);
        if (!listing)
            return;
        if (Player* player = ObjectAccessor::FindConnectedPlayer(guid))
        {
            sAddonComm->Send(player, "LG_ENTRY", 0);
            sAddonComm->Send(player, "LG_APPLICANTS", std::string("-"));
        }
        // the leader left his group of one: nothing to list
        if (group->GetMembersCount() == 0)
        {
            Delist(listing->Id, false);
            return;
        }
        UpdateMembers(group);
    }
}

class premade_groups_world : public WorldScript
{
    uint32 timer = 0;

public:
    premade_groups_world() : WorldScript("premade_groups_world") {}

    void OnStartup() override
    {
        LoadData();
    }

    void OnUpdate(uint32 diff) override
    {
        timer += diff;
        if (timer < UPDATE_INTERVAL)
            return;
        timer = 0;
        Update();
    }
};

class premade_groups_player : public PlayerScript
{
public:
    premade_groups_player() : PlayerScript("premade_groups_player")
    {
        sAddonComm->Register(std::string("LG_DATA"), &HandleData);
        sAddonComm->Register(std::string("LG_STATUS"), &HandleStatus);
        sAddonComm->Register(std::string("LG_CREATE"), &HandleCreate);
        sAddonComm->Register(std::string("LG_UPDATE"), &HandleUpdate);
        sAddonComm->Register(std::string("LG_DELIST"), &HandleDelist);
        sAddonComm->Register(std::string("LG_SEARCH"), &HandleSearch);
        sAddonComm->Register(std::string("LG_APPLY"), &HandleApply);
        sAddonComm->Register(std::string("LG_CANCEL"), &HandleCancel);
        sAddonComm->Register(std::string("LG_INVITE"), &HandleInvite);
        sAddonComm->Register(std::string("LG_DECLINE"), &HandleDecline);
        sAddonComm->Register(std::string("LG_SEEN"), &HandleSeen);
        sAddonComm->Register(std::string("LG_ANSWER"), &HandleAnswer);
    }

    void OnLogout(Player* player) override
    {
        CancelPlayerApplications(player->GetGUID(), STATUS_CANCELLED);
    }
};

class premade_groups_group : public GroupScript
{
public:
    premade_groups_group() : GroupScript("premade_groups_group") {}

    // in a group now: his applications are of no use (retail)
    void OnAddMember(Group* group, ObjectGuid guid) override
    {
        CancelPlayerApplications(guid, STATUS_CANCELLED);
        if (Listing const* listing = GetGroupListing(group))
        {
            UpdateMembers(group);
            DeclineIfFull(*listing);
        }
    }

    void OnRemoveMember(Group* group, ObjectGuid guid, RemoveMethod /*method*/, ObjectGuid /*kicker*/, char const* /*reason*/) override
    {
        OnGroupLeft(group, guid);
    }

    void OnChangeLeader(Group* group, ObjectGuid /*newLeaderGuid*/, ObjectGuid /*oldLeaderGuid*/) override
    {
        if (GetGroupListing(group))
            UpdateMembers(group);
    }

    void OnDisband(Group* group) override
    {
        Listing const* listing = GetGroupListing(group);
        if (!listing)
            return;
        uint32 id = listing->Id;
        for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
            if (Player* member = ref->GetSource())
            {
                sAddonComm->Send(member, "LG_ENTRY", 0);
                sAddonComm->Send(member, "LG_APPLICANTS", std::string("-"));
            }
        // the group is going away: no member updates, no disband from Delist
        auto itr = s_listings.find(id);
        Listing copy = itr->second;
        s_listings.erase(itr);
        s_listingByGroup.erase(copy.GroupGuid);
        std::vector<uint32> ids;
        for (auto const& pair : s_applications)
            if (pair.second.ListingId == id)
                ids.push_back(pair.first);
        for (uint32 appId : ids)
            FinishApplication(appId, STATUS_DECLINED_DELISTED, false);
    }
};

class premade_groups_commands : public CommandScript
{
public:
    premade_groups_commands() : CommandScript("premade_groups_commands") {}

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable lgTable =
        {
            { "list",   HandleListCommand,   rbac::RBAC_PERM_COMMAND_ADDITEM, Console::Yes },
            { "reload", HandleReloadCommand, rbac::RBAC_PERM_COMMAND_ADDITEM, Console::Yes },
        };
        static ChatCommandTable commandTable =
        {
            { "lg", lgTable },
        };
        return commandTable;
    }

    static bool HandleListCommand(ChatHandler* handler)
    {
        for (auto const& pair : s_listings)
        {
            Listing const& listing = pair.second;
            Group* group = GetListingGroup(listing);
            uint32 applicants = 0;
            for (auto const& app : s_applications)
                if (app.second.ListingId == listing.Id)
                    ++applicants;
            handler->SendSysMessage(Trinity::StringFormat("{} activity {} group {} members {}: applicants {}, expires in {} s",
                listing.Id, listing.ActivityId, listing.GroupGuid.ToString(), group ? group->GetMembersCount() : 0,
                applicants, SecondsLeft(listing.Expires)));
        }
        handler->SendSysMessage(Trinity::StringFormat("listings {}, applications {}", s_listings.size(), s_applications.size()));
        return true;
    }

    static bool HandleReloadCommand(ChatHandler* handler)
    {
        LoadData();
        handler->SendSysMessage(Trinity::StringFormat("premade_groups: {} categories, {} activity groups, {} activities loaded",
            s_categories.size(), s_groups.size(), s_activities.size()));
        return true;
    }
};

void AddSC_premade_groups()
{
    new premade_groups_world();
    new premade_groups_player();
    new premade_groups_group();
    new premade_groups_commands();
}
