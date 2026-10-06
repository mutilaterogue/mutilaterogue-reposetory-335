/*
 * Raid Finder (retail: LFR) for 3.3.5 - its own queue, not LFGMgr (TrinityCore's dungeon finder does not build raids).
 *
 * Raids: world.raid_finder_dungeon (sql/world_raid_finder.sql) - map, difficulty (0 10 normal, 1 25 normal,
 * 2 10 heroic, 3 25 heroic), the roles a raid needs, level / item level requirements.
 * Boss rewards: world.raid_finder_reward - money / an item to every raid member on the map when a boss dies.
 *
 * Queue: alone or as a group (a party, or a raid not bigger than the raid). A group is queued by its leader:
 * a role check goes to every member (ROLE_CHECK_TIME), each picks his roles; all answered - the group is queued
 * as one unit, a decline or a timeout - nobody is. The group's members stay together in every proposal.
 * Every UPDATE_INTERVAL each raid takes the earliest queued units: a unit fits when each of its members gets
 * one of his roles in the slots still free (tanks first, then healers, then damage).
 * Not enough players for every role - nobody is taken, the queue waits.
 * The group changes while queued (a member joins or leaves): the whole group is out of the queue (retail).
 *
 * Proposal: the chosen players get "RF_PROPOSAL"; all accept within PROPOSAL_TIME -> a raid group is made
 * (the first tank leads; queued groups are taken out of their old groups), its raid difficulty set,
 * everybody teleported to the raid's entrance.
 * A decline or a timeout: that player (and his queued group) is out of the queue, the others are back in at their place.
 * Saved to that raid (this difficulty), below the level / item level: cannot join.
 * Leaving the raid group (or its disband) inside the raid: back to where the player queued (retail).
 *
 * AddonComm (client: GroupFinder\RaidFinder.lua):
 *  C->S "RF_LIST"                      -> S->C "RF_LIST" : id;name;mapId;difficulty;size;minLevel;minItemLevel;saved,...
 *       "RF_JOIN" : raidId : roles      (roles: 1 tank, 2 healer, 4 damage - a bit mask; the group leader: his own roles)
 *       "RF_ROLES" : roles              (the answer to a role check; 0 - decline)
 *       "RF_LEAVE"                      (out of the queue: with the whole queued group)
 *       "RF_ANSWER" : 1 / 0             (accept / decline the proposal)
 *       "RF_STATUS"                     -> S->C "RF_STATUS" (below)
 *       "RF_LEAVE_RAID"                 (leave the raid finder's raid: out of the group, back to where he queued)
 *  S->C "RF_STATUS" : state : raidId : roles : seconds queued : tanks : healers : damage : tanks needed : healers needed : damage needed
 *              state 0 none, 1 queued, 2 proposal, 3 in the raid finder's raid, 4 role check;
 *              the counts are the players queued for that raid by role
 *       "RF_ROLE_CHECK" : raidId : leader name : seconds left   (pick the roles: answer "RF_ROLES")
 *       "RF_PROPOSAL" : raidId : seconds left : accepted : total : my answer (0 none, 1 accepted)
 *       "RF_RESULT" : message
 *
 * GM: .rf list (the queues), .rf reload (the raid and reward tables)
 *
 * Setup: core/Group_solo.patch (a raid of one stays a group), sql/world_raid_finder.sql,
 * AddSC_raid_finder() in custom_script_loader.cpp.
 */

#include "ScriptMgr.h"
#include "Custom\AddonComm\AddonComm.h"
#include "Chat.h"
#include "ChatCommand.h"
#include "Creature.h"
#include "DatabaseEnv.h"
#include "GameTime.h"
#include "Group.h"
#include "GroupMgr.h"
#include "InstanceSaveMgr.h"
#include "Item.h"
#include "Log.h"
#include "Mail.h"
#include "Map.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "RBAC.h"
#include "StringFormat.h"
#include "World.h"
#include "WorldSession.h"

#include <algorithm>
#include <map>
#include <set>
#include <sstream>
#include <vector>

using namespace Trinity::ChatCommands;

namespace
{
    // ---------------------------------------------------------------- config
    constexpr uint32 UPDATE_INTERVAL = 3 * IN_MILLISECONDS;
    constexpr uint32 PROPOSAL_TIME   = 45;      // seconds
    constexpr uint32 ROLE_CHECK_TIME = 60;      // seconds

    enum Roles : uint8
    {
        ROLE_TANK   = 0x1,
        ROLE_HEALER = 0x2,
        ROLE_DAMAGE = 0x4,
        ROLE_ALL    = ROLE_TANK | ROLE_HEALER | ROLE_DAMAGE,
    };

    enum State : uint8
    {
        STATE_NONE       = 0,
        STATE_QUEUED     = 1,
        STATE_PROPOSAL   = 2,
        STATE_IN_RAID    = 3,   // in a raid the raid finder made (the client offers "leave the raid")
        STATE_ROLE_CHECK = 4,   // the group's role check before it is queued
    };

    struct Raid
    {
        uint32 Id = 0;
        uint32 MapId = 0;
        uint8 Difficulty = 0;
        std::string Name;
        uint32 Tanks = 0, Healers = 0, Damage = 0;
        uint32 MinLevel = 0;
        uint32 MinItemLevel = 0;

        uint32 Size() const { return Tanks + Healers + Damage; }
    };

    struct Reward
    {
        uint32 BossEntry = 0;       // 0 - every boss of the raid
        uint32 Money = 0;           // copper
        uint32 ItemId = 0;
        uint32 ItemCount = 0;
    };

    struct Queued
    {
        ObjectGuid Guid;
        uint32 RaidId = 0;
        uint8 Roles = 0;
        time_t JoinTime = 0;
        State Status = STATE_QUEUED;
        uint32 ProposalId = 0;
        uint32 PartyId = 0;         // 0 - alone; else the queued group (its role check id), its members stay together
    };

    struct Proposal
    {
        uint32 Id = 0;
        uint32 RaidId = 0;
        time_t Expires = 0;
        std::vector<std::pair<ObjectGuid, uint8>> Members;  // player, the role he got
        std::map<ObjectGuid, bool> Answers;                 // accepted
    };

    struct RoleCheck
    {
        uint32 Id = 0;
        uint32 RaidId = 0;
        ObjectGuid Leader;
        ObjectGuid GroupGuid;
        time_t Expires = 0;
        std::map<ObjectGuid, uint8> Roles;                  // 0 - no answer yet
    };

    std::map<uint32, Raid> s_raids;
    std::map<uint32, std::vector<Reward>> s_rewards;        // by raid id
    std::map<ObjectGuid, Queued> s_queue;
    std::map<uint32, Proposal> s_proposals;
    std::map<uint32, RoleCheck> s_roleChecks;
    uint32 s_nextProposal = 1;
    uint32 s_nextRoleCheck = 1;

    // where the raid finder took a player from: back there when he leaves its raid group (retail)
    struct Return
    {
        uint32 RaidId = 0;
        uint32 RaidMapId = 0;
        WorldLocation Pos;
    };
    std::map<ObjectGuid, Return> s_returns;
    std::vector<ObjectGuid> s_pendingReturn;   // left the group: teleported on the next world update

    // bosses already rewarded: instance id -> creature spawn guids
    std::map<uint32, std::set<ObjectGuid>> s_rewardedBosses;

    std::string Sanitize(std::string text)
    {
        // ':' and ',' / ';' separate the AddonComm fields and list entries
        std::replace(text.begin(), text.end(), ':', ' ');
        std::replace(text.begin(), text.end(), ',', ' ');
        std::replace(text.begin(), text.end(), ';', ' ');
        return text;
    }

    void Result(Player* player, std::string const& text)
    {
        sAddonComm->Send(player, "RF_RESULT", Sanitize(text));
    }

    void LoadRaids()
    {
        s_raids.clear();
        if (QueryResult result = WorldDatabase.Query("SELECT CAST(id AS SIGNED), CAST(map_id AS SIGNED), CAST(difficulty AS SIGNED), name, "
            "CAST(tanks AS SIGNED), CAST(healers AS SIGNED), CAST(damage AS SIGNED), CAST(min_level AS SIGNED), CAST(min_item_level AS SIGNED) "
            "FROM raid_finder_dungeon ORDER BY id"))
        {
            do
            {
                Field* fields = result->Fetch();
                Raid raid;
                raid.Id = uint32(fields[0].GetInt64());
                raid.MapId = uint32(fields[1].GetInt64());
                raid.Difficulty = uint8(fields[2].GetInt64());
                raid.Name = fields[3].GetString();
                raid.Tanks = uint32(fields[4].GetInt64());
                raid.Healers = uint32(fields[5].GetInt64());
                raid.Damage = uint32(fields[6].GetInt64());
                raid.MinLevel = uint32(fields[7].GetInt64());
                raid.MinItemLevel = uint32(fields[8].GetInt64());
                if (raid.Difficulty >= MAX_RAID_DIFFICULTY || !raid.Size())
                {
                    TC_LOG_ERROR("scripts", "raid_finder: raid {} has a bad difficulty or no roles, skipped", raid.Id);
                    continue;
                }
                s_raids[raid.Id] = raid;
            } while (result->NextRow());
        }

        s_rewards.clear();
        if (QueryResult result = WorldDatabase.Query("SELECT CAST(raid_id AS SIGNED), CAST(boss_entry AS SIGNED), CAST(money AS SIGNED), "
            "CAST(item_id AS SIGNED), CAST(item_count AS SIGNED) FROM raid_finder_reward"))
        {
            do
            {
                Field* fields = result->Fetch();
                Reward reward;
                uint32 raidId = uint32(fields[0].GetInt64());
                reward.BossEntry = uint32(fields[1].GetInt64());
                reward.Money = uint32(fields[2].GetInt64());
                reward.ItemId = uint32(fields[3].GetInt64());
                reward.ItemCount = uint32(fields[4].GetInt64());
                if (reward.ItemId && !sObjectMgr->GetItemTemplate(reward.ItemId))
                {
                    TC_LOG_ERROR("scripts", "raid_finder: reward item {} of raid {} does not exist, skipped", reward.ItemId, raidId);
                    reward.ItemId = 0;
                }
                s_rewards[raidId].push_back(reward);
            } while (result->NextRow());
        }
    }

    Raid const* GetRaid(uint32 id)
    {
        auto itr = s_raids.find(id);
        return itr != s_raids.end() ? &itr->second : nullptr;
    }

    bool IsSaved(Player* player, Raid const& raid)
    {
        InstancePlayerBind* bind = player->GetBoundInstance(raid.MapId, Difficulty(raid.Difficulty));
        return bind && bind->perm;
    }

    bool IsBusy(ObjectGuid guid)
    {
        if (s_queue.count(guid))
            return true;
        for (auto const& pair : s_roleChecks)
            if (pair.second.Roles.count(guid))
                return true;
        return false;
    }

    // why the player cannot queue for that raid (empty - he can); inGroup - queued with his group
    std::string JoinError(Player* player, Raid const& raid, bool inGroup)
    {
        if (player->GetGroup() && !inGroup)
            return "\xd0\x92\xd1\x8b\xd0\xb9\xd0\xb4\xd0\xb8\xd1\x82\xd0\xb5 \xd0\xb8\xd0\xb7 \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd1\x8b \xd0\xb8\xd0\xbb\xd0\xb8 \xd0\xbf\xd0\xbe\xd0\xbf\xd1\x80\xd0\xbe\xd1\x81\xd0\xb8\xd1\x82\xd0\xb5 \xd0\xbb\xd0\xb8\xd0\xb4\xd0\xb5\xd1\x80\xd0\xb0 \xd0\xbf\xd0\xbe\xd1\x81\xd1\x82\xd0\xb0\xd0\xb2\xd0\xb8\xd1\x82\xd1\x8c \xd0\xb5\xd1\x91 \xd0\xb2 \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd1\x8c.";
        if (player->InBattleground() || player->InBattlegroundQueue())
            return "\xd0\x9d\xd0\xb5\xd0\xbb\xd1\x8c\xd0\xb7\xd1\x8f \xd0\xb2\xd1\x81\xd1\x82\xd0\xb0\xd1\x82\xd1\x8c \xd0\xb2 \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd1\x8c, \xd0\xbd\xd0\xb0\xd1\x85\xd0\xbe\xd0\xb4\xd1\x8f\xd1\x81\xd1\x8c \xd0\xbd\xd0\xb0 \xd0\xbf\xd0\xbe\xd0\xbb\xd0\xb5 \xd0\xb1\xd0\xbe\xd1\x8f \xd0\xb8\xd0\xbb\xd0\xb8 \xd0\xb2 \xd0\xb5\xd0\xb3\xd0\xbe \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd0\xb8.";
        if (player->GetLevel() < raid.MinLevel)
            return "\xd0\xa1\xd0\xbb\xd0\xb8\xd1\x88\xd0\xba\xd0\xbe\xd0\xbc \xd0\xbd\xd0\xb8\xd0\xb7\xd0\xba\xd0\xb8\xd0\xb9 \xd1\x83\xd1\x80\xd0\xbe\xd0\xb2\xd0\xb5\xd0\xbd\xd1\x8c \xd0\xb4\xd0\xbb\xd1\x8f \xd1\x8d\xd1\x82\xd0\xbe\xd0\xb3\xd0\xbe \xd1\x80\xd0\xb5\xd0\xb9\xd0\xb4\xd0\xb0.";
        if (raid.MinItemLevel && player->GetAverageItemLevel() < float(raid.MinItemLevel))
            return "\xd0\xa1\xd0\xbb\xd0\xb8\xd1\x88\xd0\xba\xd0\xbe\xd0\xbc \xd0\xbd\xd0\xb8\xd0\xb7\xd0\xba\xd0\xb8\xd0\xb9 \xd1\x83\xd1\x80\xd0\xbe\xd0\xb2\xd0\xb5\xd0\xbd\xd1\x8c \xd0\xbf\xd1\x80\xd0\xb5\xd0\xb4\xd0\xbc\xd0\xb5\xd1\x82\xd0\xbe\xd0\xb2 \xd0\xb4\xd0\xbb\xd1\x8f \xd1\x8d\xd1\x82\xd0\xbe\xd0\xb3\xd0\xbe \xd1\x80\xd0\xb5\xd0\xb9\xd0\xb4\xd0\xb0.";
        if (IsSaved(player, raid))
            return "\xd0\x92\xd1\x8b \xd1\x83\xd0\xb6\xd0\xb5 \xd1\x81\xd0\xbe\xd1\x85\xd1\x80\xd0\xb0\xd0\xbd\xd0\xb5\xd0\xbd\xd1\x8b \xd0\xb2 \xd1\x8d\xd1\x82\xd0\xbe\xd0\xbc \xd1\x80\xd0\xb5\xd0\xb9\xd0\xb4\xd0\xb5.";
        return std::string();
    }

    // ---------------------------------------------------------------- status
    RoleCheck const* FindRoleCheck(ObjectGuid guid)
    {
        for (auto const& pair : s_roleChecks)
            if (pair.second.Roles.count(guid))
                return &pair.second;
        return nullptr;
    }

    void SendStatus(Player* player)
    {
        auto itr = s_queue.find(player->GetGUID());
        if (itr == s_queue.end())
        {
            if (RoleCheck const* check = FindRoleCheck(player->GetGUID()))
            {
                sAddonComm->Send(player, "RF_STATUS", uint32(STATE_ROLE_CHECK), check->RaidId, uint32(check->Roles.at(player->GetGUID())), 0, 0, 0, 0, 0, 0, 0);
                return;
            }
            auto back = s_returns.find(player->GetGUID());
            if (back != s_returns.end() && player->GetGroup())
                sAddonComm->Send(player, "RF_STATUS", uint32(STATE_IN_RAID), back->second.RaidId, 0, 0, 0, 0, 0, 0, 0, 0);
            else
                sAddonComm->Send(player, "RF_STATUS", uint32(STATE_NONE), 0, 0, 0, 0, 0, 0, 0, 0, 0);
            return;
        }
        Queued const& entry = itr->second;
        Raid const* raid = GetRaid(entry.RaidId);
        uint32 tanks = 0, healers = 0, damage = 0;
        for (auto const& pair : s_queue)
        {
            if (pair.second.RaidId != entry.RaidId)
                continue;
            if (pair.second.Roles & ROLE_TANK)
                ++tanks;
            if (pair.second.Roles & ROLE_HEALER)
                ++healers;
            if (pair.second.Roles & ROLE_DAMAGE)
                ++damage;
        }
        sAddonComm->Send(player, "RF_STATUS", uint32(entry.Status), entry.RaidId, uint32(entry.Roles),
            uint32(GameTime::GetGameTime() - entry.JoinTime), tanks, healers, damage,
            raid ? raid->Tanks : 0, raid ? raid->Healers : 0, raid ? raid->Damage : 0);
    }

    void SendStatus(ObjectGuid guid)
    {
        if (Player* player = ObjectAccessor::FindConnectedPlayer(guid))
            SendStatus(player);
    }

    void SendStatusToRaidQueue(uint32 raidId)
    {
        for (auto const& pair : s_queue)
            if (pair.second.RaidId == raidId)
                SendStatus(pair.first);
    }

    void SendProposal(Proposal const& proposal)
    {
        uint32 accepted = 0;
        for (auto const& answer : proposal.Answers)
            if (answer.second)
                ++accepted;
        time_t now = GameTime::GetGameTime();
        uint32 left = proposal.Expires > now ? uint32(proposal.Expires - now) : 0;
        for (auto const& member : proposal.Members)
            if (Player* player = ObjectAccessor::FindConnectedPlayer(member.first))
            {
                auto answer = proposal.Answers.find(member.first);
                sAddonComm->Send(player, "RF_PROPOSAL", proposal.RaidId, left, accepted, uint32(proposal.Members.size()),
                    answer != proposal.Answers.end() && answer->second ? 1 : 0);
            }
    }

    void SendList(Player* player)
    {
        std::ostringstream list;
        bool first = true;
        for (auto const& pair : s_raids)
        {
            Raid const& raid = pair.second;
            if (!first)
                list << ',';
            first = false;
            list << raid.Id << ';' << Sanitize(raid.Name) << ';' << raid.MapId << ';' << uint32(raid.Difficulty) << ';'
                 << raid.Size() << ';' << raid.MinLevel << ';' << raid.MinItemLevel << ';' << (IsSaved(player, raid) ? 1 : 0);
        }
        sAddonComm->Send(player, "RF_LIST", first ? std::string("-") : list.str());
    }

    // ---------------------------------------------------------------- queue
    // the player and, if he is queued with a group, the whole group: out of the queue
    void LeaveQueue(ObjectGuid guid, std::string const& reason)
    {
        auto itr = s_queue.find(guid);
        if (itr == s_queue.end())
            return;
        uint32 raidId = itr->second.RaidId;
        uint32 partyId = itr->second.PartyId;
        std::vector<ObjectGuid> out;
        if (partyId)
        {
            for (auto const& pair : s_queue)
                if (pair.second.PartyId == partyId)
                    out.push_back(pair.first);
        }
        else
            out.push_back(guid);

        for (ObjectGuid const& member : out)
        {
            s_queue.erase(member);
            if (Player* player = ObjectAccessor::FindConnectedPlayer(member))
            {
                if (!reason.empty())
                    Result(player, reason);
                SendStatus(player);
            }
        }
        SendStatusToRaidQueue(raidId);
    }

    // a proposal is over: the accepted ones back in the queue (decline / timeout), the rest and their groups out
    void CancelProposal(uint32 proposalId, std::string const& reason)
    {
        auto itr = s_proposals.find(proposalId);
        if (itr == s_proposals.end())
            return;
        Proposal proposal = itr->second;
        s_proposals.erase(itr);

        // the groups of those who did not accept are out with them
        std::set<uint32> droppedParties;
        std::set<ObjectGuid> dropped;
        for (auto const& member : proposal.Members)
        {
            auto answer = proposal.Answers.find(member.first);
            bool accepted = answer != proposal.Answers.end() && answer->second;
            auto entry = s_queue.find(member.first);
            if (accepted && ObjectAccessor::FindConnectedPlayer(member.first) && entry != s_queue.end())
                continue;
            dropped.insert(member.first);
            if (entry != s_queue.end() && entry->second.PartyId)
                droppedParties.insert(entry->second.PartyId);
        }
        for (auto const& member : proposal.Members)
        {
            auto entry = s_queue.find(member.first);
            if (entry != s_queue.end() && entry->second.PartyId && droppedParties.count(entry->second.PartyId))
                dropped.insert(member.first);
        }

        for (auto const& member : proposal.Members)
        {
            Player* player = ObjectAccessor::FindConnectedPlayer(member.first);
            if (dropped.count(member.first))
            {
                s_queue.erase(member.first);
                if (player)
                    Result(player, "\xd0\x92\xd1\x8b \xd0\xbf\xd0\xbe\xd0\xba\xd0\xb8\xd0\xbd\xd1\x83\xd0\xbb\xd0\xb8 \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd1\x8c \xd0\xb2 \xd1\x80\xd0\xb5\xd0\xb9\xd0\xb4.");
            }
            else
            {
                Queued& entry = s_queue[member.first];
                entry.Status = STATE_QUEUED;
                entry.ProposalId = 0;
                if (player)
                    Result(player, reason);
            }
            if (player)
                SendStatus(player);
        }
        SendStatusToRaidQueue(proposal.RaidId);
    }

    void TeleportToRaid(Player* player, Raid const& raid)
    {
        if (AreaTriggerTeleport const* trigger = sObjectMgr->GetMapEntranceTrigger(raid.MapId))
            player->TeleportTo(trigger->target_mapId, trigger->target_X, trigger->target_Y, trigger->target_Z, trigger->target_Orientation);
        else
            TC_LOG_ERROR("scripts", "raid_finder: no entrance areatrigger for map {}", raid.MapId);
    }

    // everybody accepted: the raid group, its difficulty, the teleport
    void FormRaid(Proposal const& proposal)
    {
        Raid const* raid = GetRaid(proposal.RaidId);
        std::vector<Player*> players;
        for (auto const& member : proposal.Members)
        {
            Player* player = ObjectAccessor::FindConnectedPlayer(member.first);
            auto entry = s_queue.find(member.first);
            bool inGroup = entry != s_queue.end() && entry->second.PartyId;
            if (!player || !raid || !JoinError(player, *raid, inGroup).empty())
            {
                // somebody is gone or no longer fits: the others back in the queue
                Proposal copy = proposal;
                copy.Answers[member.first] = false;
                s_proposals[copy.Id] = copy;
                CancelProposal(copy.Id, "\xd0\x9e\xd0\xb4\xd0\xb8\xd0\xbd \xd0\xb8\xd0\xb7 \xd1\x83\xd1\x87\xd0\xb0\xd1\x81\xd1\x82\xd0\xbd\xd0\xb8\xd0\xba\xd0\xbe\xd0\xb2 \xd0\xb1\xd0\xbe\xd0\xbb\xd1\x8c\xd1\x88\xd0\xb5 \xd0\xbd\xd0\xb5 \xd0\xbc\xd0\xbe\xd0\xb6\xd0\xb5\xd1\x82 \xd0\xb2\xd0\xbe\xd0\xb9\xd1\x82\xd0\xb8. \xd0\x92\xd1\x8b \xd1\x81\xd0\xbd\xd0\xbe\xd0\xb2\xd0\xb0 \xd0\xb2 \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd0\xb8.");
                return;
            }
            players.push_back(player);
        }

        // out of the queue first: leaving the old groups below must not look like a queued group changing
        for (auto const& member : proposal.Members)
            s_queue.erase(member.first);
        s_proposals.erase(proposal.Id);

        // the queued groups' members out of their old groups
        for (Player* player : players)
            if (player->GetGroup())
                player->RemoveFromGroup(GROUP_REMOVEMETHOD_DEFAULT);

        Group* group = new Group();
        if (!group->Create(players.front()))
        {
            delete group;
            for (Player* player : players)
            {
                Result(player, "\xd0\x9d\xd0\xb5 \xd1\x83\xd0\xb4\xd0\xb0\xd0\xbb\xd0\xbe\xd1\x81\xd1\x8c \xd1\x81\xd0\xbe\xd0\xb7\xd0\xb4\xd0\xb0\xd1\x82\xd1\x8c \xd1\x80\xd0\xb5\xd0\xb9\xd0\xb4.");
                SendStatus(player);
            }
            return;
        }
        sGroupMgr->AddGroup(group);
        group->SetAllowSolo(true);      // core/Group_solo.patch: the raid stays a raid down to its last member
        group->ConvertToRaid();
        group->SetRaidDifficultyID(Difficulty(raid->Difficulty));
        for (size_t i = 1; i < players.size(); ++i)
            group->AddMember(players[i]);

        for (auto const& member : proposal.Members)
            if (member.second == ROLE_TANK)
                group->SetGroupMemberFlag(member.first, true, MEMBER_FLAG_MAINTANK);

        for (Player* player : players)
        {
            player->SetRaidDifficultyID(Difficulty(raid->Difficulty));
            Return& back = s_returns[player->GetGUID()];
            back.RaidId = raid->Id;
            back.RaidMapId = raid->MapId;
            back.Pos.WorldRelocate(*player);
            Result(player, "\xd0\xa0\xd0\xb5\xd0\xb9\xd0\xb4 \xd1\x81\xd0\xbe\xd0\xb1\xd1\x80\xd0\xb0\xd0\xbd: " + raid->Name + ".");
            SendStatus(player);
            TeleportToRaid(player, *raid);
        }
        SendStatusToRaidQueue(raid->Id);
    }

    // the earliest queued units (a player alone or a queued group) for every role of a raid; false - not enough of them
    bool PickRaid(Raid const& raid, std::vector<std::pair<ObjectGuid, uint8>>& picked)
    {
        // units by the time they joined
        std::map<uint64, std::vector<Queued const*>> units;     // key: party id, or (1 << 32 | guid) alone
        uint32 queuedCount = 0;
        for (auto const& pair : s_queue)
        {
            Queued const& entry = pair.second;
            if (entry.RaidId != raid.Id || entry.Status != STATE_QUEUED)
                continue;
            uint64 key = entry.PartyId ? uint64(entry.PartyId) : ((uint64(1) << 32) | entry.Guid.GetCounter());
            units[key].push_back(&entry);
            ++queuedCount;
        }
        if (queuedCount < raid.Size())
            return false;

        std::vector<std::vector<Queued const*>> ordered;
        for (auto& pair : units)
            ordered.push_back(pair.second);
        std::sort(ordered.begin(), ordered.end(), [](std::vector<Queued const*> const& a, std::vector<Queued const*> const& b)
        {
            return a.front()->JoinTime < b.front()->JoinTime;
        });

        uint32 free[3] = { raid.Tanks, raid.Healers, raid.Damage };
        uint8 const order[3] = { ROLE_TANK, ROLE_HEALER, ROLE_DAMAGE };
        for (std::vector<Queued const*> unit : ordered)
        {
            // the members with the fewest roles choose first
            std::sort(unit.begin(), unit.end(), [](Queued const* a, Queued const* b)
            {
                auto count = [](uint8 roles) { return (roles & 1) + ((roles >> 1) & 1) + ((roles >> 2) & 1); };
                return count(a->Roles) < count(b->Roles);
            });
            uint32 left[3] = { free[0], free[1], free[2] };
            std::vector<std::pair<ObjectGuid, uint8>> taken;
            for (Queued const* member : unit)
            {
                for (int i = 0; i < 3; ++i)
                    if ((member->Roles & order[i]) && left[i])
                    {
                        --left[i];
                        taken.emplace_back(member->Guid, order[i]);
                        break;
                    }
            }
            if (taken.size() != unit.size())
                continue;           // the unit does not fit the slots left: the next one
            std::copy(left, left + 3, free);
            picked.insert(picked.end(), taken.begin(), taken.end());
            if (!free[0] && !free[1] && !free[2])
                return true;
        }
        picked.clear();
        return false;
    }

    // ---------------------------------------------------------------- role check (a group queued by its leader)
    void EndRoleCheck(uint32 id, std::string const& reason)
    {
        auto itr = s_roleChecks.find(id);
        if (itr == s_roleChecks.end())
            return;
        RoleCheck check = itr->second;
        s_roleChecks.erase(itr);
        for (auto const& member : check.Roles)
            if (Player* player = ObjectAccessor::FindConnectedPlayer(member.first))
            {
                Result(player, reason);
                SendStatus(player);
            }
    }

    // everybody picked roles: the group is queued as one unit
    void FinishRoleCheck(RoleCheck const& check)
    {
        Raid const* raid = GetRaid(check.RaidId);
        Group* group = sGroupMgr->GetGroupByGUID(check.GroupGuid);
        if (!raid || !group || group->GetMembersCount() != check.Roles.size())
        {
            EndRoleCheck(check.Id, "\xd0\xa1\xd0\xbe\xd1\x81\xd1\x82\xd0\xb0\xd0\xb2 \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd1\x8b \xd0\xb8\xd0\xb7\xd0\xbc\xd0\xb5\xd0\xbd\xd0\xb8\xd0\xbb\xd1\x81\xd1\x8f. \xd0\x93\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd0\xb0 \xd0\xbd\xd0\xb5 \xd0\xbf\xd0\xbe\xd1\x81\xd1\x82\xd0\xb0\xd0\xb2\xd0\xbb\xd0\xb5\xd0\xbd\xd0\xb0 \xd0\xb2 \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd1\x8c.");
            return;
        }
        for (auto const& member : check.Roles)
        {
            Player* player = ObjectAccessor::FindConnectedPlayer(member.first);
            std::string error = player ? JoinError(player, *raid, true) : std::string("-");
            if (!error.empty())
            {
                EndRoleCheck(check.Id, player ? std::string(player->GetName()) + ": " + error : "\xd0\x9e\xd0\xb4\xd0\xb8\xd0\xbd \xd0\xb8\xd0\xb7 \xd1\x83\xd1\x87\xd0\xb0\xd1\x81\xd1\x82\xd0\xbd\xd0\xb8\xd0\xba\xd0\xbe\xd0\xb2 \xd0\xbd\xd0\xb5 \xd0\xb2 \xd1\x81\xd0\xb5\xd1\x82\xd0\xb8.");
                return;
            }
        }

        time_t now = GameTime::GetGameTime();
        for (auto const& member : check.Roles)
        {
            Queued entry;
            entry.Guid = member.first;
            entry.RaidId = check.RaidId;
            entry.Roles = member.second;
            entry.JoinTime = now;
            entry.PartyId = check.Id;
            s_queue[entry.Guid] = entry;
        }
        s_roleChecks.erase(check.Id);
        SendStatusToRaidQueue(check.RaidId);
    }

    void StartRoleCheck(Player* leader, Group* group, Raid const& raid, uint8 leaderRoles)
    {
        if (group->GetMembersCount() > raid.Size())
        {
            Result(leader, "\xd0\x92 \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd0\xb5 \xd0\xb1\xd0\xbe\xd0\xbb\xd1\x8c\xd1\x88\xd0\xb5 \xd0\xb8\xd0\xb3\xd1\x80\xd0\xbe\xd0\xba\xd0\xbe\xd0\xb2, \xd1\x87\xd0\xb5\xd0\xbc \xd0\xb2 \xd1\x8d\xd1\x82\xd0\xbe\xd0\xbc \xd1\x80\xd0\xb5\xd0\xb9\xd0\xb4\xd0\xb5.");
            return;
        }
        for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
        {
            Player* member = ref->GetSource();
            if (!member)
            {
                Result(leader, "\xd0\x92\xd1\x81\xd0\xb5 \xd1\x83\xd1\x87\xd0\xb0\xd1\x81\xd1\x82\xd0\xbd\xd0\xb8\xd0\xba\xd0\xb8 \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd1\x8b \xd0\xb4\xd0\xbe\xd0\xbb\xd0\xb6\xd0\xbd\xd1\x8b \xd0\xb1\xd1\x8b\xd1\x82\xd1\x8c \xd0\xb2 \xd1\x81\xd0\xb5\xd1\x82\xd0\xb8.");
                return;
            }
            if (IsBusy(member->GetGUID()))
            {
                Result(leader, std::string(member->GetName()) + " \xd1\x83\xd0\xb6\xd0\xb5 \xd0\xb2 \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd0\xb8.");
                return;
            }
            std::string error = JoinError(member, raid, true);
            if (!error.empty())
            {
                Result(leader, std::string(member->GetName()) + ": " + error);
                return;
            }
        }
        // offline members are not in the reference list: compare with the member count
        uint32 online = 0;
        for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
            if (ref->GetSource())
                ++online;
        if (online != group->GetMembersCount())
        {
            Result(leader, "\xd0\x92\xd1\x81\xd0\xb5 \xd1\x83\xd1\x87\xd0\xb0\xd1\x81\xd1\x82\xd0\xbd\xd0\xb8\xd0\xba\xd0\xb8 \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd1\x8b \xd0\xb4\xd0\xbe\xd0\xbb\xd0\xb6\xd0\xbd\xd1\x8b \xd0\xb1\xd1\x8b\xd1\x82\xd1\x8c \xd0\xb2 \xd1\x81\xd0\xb5\xd1\x82\xd0\xb8.");
            return;
        }

        RoleCheck check;
        check.Id = s_nextRoleCheck++;
        check.RaidId = raid.Id;
        check.Leader = leader->GetGUID();
        check.GroupGuid = group->GetGUID();
        check.Expires = GameTime::GetGameTime() + ROLE_CHECK_TIME;
        for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
            if (Player* member = ref->GetSource())
                check.Roles[member->GetGUID()] = member == leader ? leaderRoles : 0;
        s_roleChecks[check.Id] = check;

        if (check.Roles.size() == 1)
        {
            FinishRoleCheck(check);
            return;
        }
        for (auto const& member : check.Roles)
            if (Player* player = ObjectAccessor::FindConnectedPlayer(member.first))
            {
                if (member.first != leader->GetGUID())
                    sAddonComm->Send(player, "RF_ROLE_CHECK", raid.Id, Sanitize(leader->GetName()), ROLE_CHECK_TIME);
                SendStatus(player);
            }
    }

    // a queued group or a group in its role check changed: out (retail)
    void OnGroupChanged(Group* group, ObjectGuid changed)
    {
        std::set<ObjectGuid> members;
        for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
            if (Player* member = ref->GetSource())
                members.insert(member->GetGUID());
        if (!changed.IsEmpty())
            members.insert(changed);

        for (ObjectGuid const& guid : members)
        {
            auto itr = s_queue.find(guid);
            if (itr != s_queue.end() && itr->second.PartyId)
            {
                if (itr->second.Status == STATE_PROPOSAL)
                {
                    auto proposal = s_proposals.find(itr->second.ProposalId);
                    if (proposal != s_proposals.end())
                    {
                        proposal->second.Answers[guid] = false;
                        CancelProposal(proposal->first, "\xd0\xa1\xd0\xbe\xd1\x81\xd1\x82\xd0\xb0\xd0\xb2 \xd0\xbe\xd0\xb4\xd0\xbd\xd0\xbe\xd0\xb9 \xd0\xb8\xd0\xb7 \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf \xd0\xb8\xd0\xb7\xd0\xbc\xd0\xb5\xd0\xbd\xd0\xb8\xd0\xbb\xd1\x81\xd1\x8f. \xd0\x92\xd1\x8b \xd1\x81\xd0\xbd\xd0\xbe\xd0\xb2\xd0\xb0 \xd0\xb2 \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd0\xb8.");
                        continue;
                    }
                }
                LeaveQueue(guid, "\xd0\xa1\xd0\xbe\xd1\x81\xd1\x82\xd0\xb0\xd0\xb2 \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd1\x8b \xd0\xb8\xd0\xb7\xd0\xbc\xd0\xb5\xd0\xbd\xd0\xb8\xd0\xbb\xd1\x81\xd1\x8f. \xd0\x93\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd0\xb0 \xd0\xbf\xd0\xbe\xd0\xba\xd0\xb8\xd0\xbd\xd1\x83\xd0\xbb\xd0\xb0 \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd1\x8c.");
            }
        }
        std::vector<uint32> checks;
        for (auto const& pair : s_roleChecks)
            if (pair.second.GroupGuid == group->GetGUID())
                checks.push_back(pair.first);
        for (uint32 id : checks)
            EndRoleCheck(id, "\xd0\xa1\xd0\xbe\xd1\x81\xd1\x82\xd0\xb0\xd0\xb2 \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd1\x8b \xd0\xb8\xd0\xb7\xd0\xbc\xd0\xb5\xd0\xbd\xd0\xb8\xd0\xbb\xd1\x81\xd1\x8f. \xd0\x9f\xd1\x80\xd0\xbe\xd0\xb2\xd0\xb5\xd1\x80\xd0\xba\xd0\xb0 \xd1\x80\xd0\xbe\xd0\xbb\xd0\xb5\xd0\xb9 \xd0\xbe\xd1\x82\xd0\xbc\xd0\xb5\xd0\xbd\xd0\xb5\xd0\xbd\xd0\xb0.");
    }

    // ---------------------------------------------------------------- boss rewards
    void GiveItem(Player* player, uint32 itemId, uint32 count)
    {
        ItemPosCountVec dest;
        if (player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest, itemId, count) == EQUIP_ERR_OK)
        {
            if (Item* item = player->StoreNewItem(dest, itemId, true))
                player->SendNewItem(item, count, true, false);
            return;
        }
        // bags full: by mail
        CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
        MailDraft draft("\xd0\x9f\xd0\xbe\xd0\xb8\xd1\x81\xd0\xba \xd1\x80\xd0\xb5\xd0\xb9\xd0\xb4\xd0\xb0", "\xd0\x9d\xd0\xb0\xd0\xb3\xd1\x80\xd0\xb0\xd0\xb4\xd0\xb0 \xd0\xb7\xd0\xb0 \xd0\xbf\xd0\xbe\xd0\xb1\xd0\xb5\xd0\xb4\xd1\x83 \xd0\xbd\xd0\xb0\xd0\xb4 \xd0\xb1\xd0\xbe\xd1\x81\xd1\x81\xd0\xbe\xd0\xbc.");
        if (Item* item = Item::CreateItem(itemId, count, player))
        {
            item->SaveToDB(trans);
            draft.AddItem(item);
        }
        draft.SendMailTo(trans, MailReceiver(player), MailSender(MAIL_NORMAL, 0, MAIL_STATIONERY_GM));
        CharacterDatabase.CommitTransaction(trans);
        Result(player, "\xd0\xa1\xd1\x83\xd0\xbc\xd0\xba\xd0\xb8 \xd0\xb7\xd0\xb0\xd0\xbf\xd0\xbe\xd0\xbb\xd0\xbd\xd0\xb5\xd0\xbd\xd1\x8b: \xd0\xbd\xd0\xb0\xd0\xb3\xd1\x80\xd0\xb0\xd0\xb4\xd0\xb0 \xd0\xbe\xd1\x82\xd0\xbf\xd1\x80\xd0\xb0\xd0\xb2\xd0\xbb\xd0\xb5\xd0\xbd\xd0\xb0 \xd0\xbf\xd0\xbe\xd1\x87\xd1\x82\xd0\xbe\xd0\xb9.");
    }

    void RewardBoss(Creature* boss)
    {
        Map* map = boss->GetMap();
        if (!map || !map->IsRaid())
            return;
        if (!s_rewardedBosses[map->GetInstanceId()].insert(boss->GetGUID()).second)
            return;

        for (Map::PlayerList::const_iterator itr = map->GetPlayers().begin(); itr != map->GetPlayers().end(); ++itr)
        {
            Player* player = itr->GetSource();
            if (!player)
                continue;
            auto back = s_returns.find(player->GetGUID());
            if (back == s_returns.end() || back->second.RaidMapId != map->GetId() || !player->GetGroup())
                continue;
            auto rewards = s_rewards.find(back->second.RaidId);
            if (rewards == s_rewards.end())
                continue;
            for (Reward const& reward : rewards->second)
            {
                if (reward.BossEntry && reward.BossEntry != boss->GetEntry())
                    continue;
                if (reward.Money)
                    player->ModifyMoney(int64(reward.Money));
                if (reward.ItemId && reward.ItemCount)
                    GiveItem(player, reward.ItemId, reward.ItemCount);
            }
        }
    }

    // ---------------------------------------------------------------- updates
    // out of the raid finder's group: back to where he queued, if still in that raid
    void UpdateReturns()
    {
        for (ObjectGuid const& guid : s_pendingReturn)
        {
            auto itr = s_returns.find(guid);
            if (itr == s_returns.end())
                continue;
            Return back = itr->second;
            s_returns.erase(itr);
            Player* player = ObjectAccessor::FindConnectedPlayer(guid);
            if (!player || !player->IsInWorld() || player->GetGroup() || player->GetMapId() != back.RaidMapId)
                continue;
            Result(player, "\xd0\x92\xd1\x8b \xd0\xbf\xd0\xbe\xd0\xba\xd0\xb8\xd0\xbd\xd1\x83\xd0\xbb\xd0\xb8 \xd1\x80\xd0\xb5\xd0\xb9\xd0\xb4.");
            player->TeleportTo(back.Pos);
        }
        s_pendingReturn.clear();
    }

    void UpdateQueues()
    {
        // offline players out of the queue (with their queued groups)
        std::vector<ObjectGuid> offline;
        for (auto const& pair : s_queue)
            if (pair.second.Status == STATE_QUEUED && !ObjectAccessor::FindConnectedPlayer(pair.first))
                offline.push_back(pair.first);
        for (ObjectGuid const& guid : offline)
            LeaveQueue(guid, "\xd0\x9e\xd0\xb4\xd0\xb8\xd0\xbd \xd0\xb8\xd0\xb7 \xd1\x83\xd1\x87\xd0\xb0\xd1\x81\xd1\x82\xd0\xbd\xd0\xb8\xd0\xba\xd0\xbe\xd0\xb2 \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd1\x8b \xd0\xb2\xd1\x8b\xd1\x88\xd0\xb5\xd0\xbb \xd0\xb8\xd0\xb7 \xd0\xb8\xd0\xb3\xd1\x80\xd1\x8b. \xd0\x93\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd0\xb0 \xd0\xbf\xd0\xbe\xd0\xba\xd0\xb8\xd0\xbd\xd1\x83\xd0\xbb\xd0\xb0 \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd1\x8c.");

        time_t now = GameTime::GetGameTime();

        // expired role checks
        std::vector<uint32> expiredChecks;
        for (auto const& pair : s_roleChecks)
            if (pair.second.Expires <= now)
                expiredChecks.push_back(pair.first);
        for (uint32 id : expiredChecks)
            EndRoleCheck(id, "\xd0\x9d\xd0\xb5 \xd0\xb2\xd1\x81\xd0\xb5 \xd1\x83\xd1\x87\xd0\xb0\xd1\x81\xd1\x82\xd0\xbd\xd0\xb8\xd0\xba\xd0\xb8 \xd0\xb2\xd1\x8b\xd0\xb1\xd1\x80\xd0\xb0\xd0\xbb\xd0\xb8 \xd1\x80\xd0\xbe\xd0\xbb\xd0\xb8. \xd0\x93\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd0\xb0 \xd0\xbd\xd0\xb5 \xd0\xbf\xd0\xbe\xd1\x81\xd1\x82\xd0\xb0\xd0\xb2\xd0\xbb\xd0\xb5\xd0\xbd\xd0\xb0 \xd0\xb2 \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd1\x8c.");

        // expired proposals
        std::vector<uint32> expired;
        for (auto const& pair : s_proposals)
            if (pair.second.Expires <= now)
                expired.push_back(pair.first);
        for (uint32 id : expired)
            CancelProposal(id, "\xd0\x9d\xd0\xb5 \xd0\xb2\xd1\x81\xd0\xb5 \xd1\x83\xd1\x87\xd0\xb0\xd1\x81\xd1\x82\xd0\xbd\xd0\xb8\xd0\xba\xd0\xb8 \xd0\xbf\xd0\xbe\xd0\xb4\xd1\x82\xd0\xb2\xd0\xb5\xd1\x80\xd0\xb4\xd0\xb8\xd0\xbb\xd0\xb8 \xd0\xb3\xd0\xbe\xd1\x82\xd0\xbe\xd0\xb2\xd0\xbd\xd0\xbe\xd1\x81\xd1\x82\xd1\x8c. \xd0\x92\xd1\x8b \xd1\x81\xd0\xbd\xd0\xbe\xd0\xb2\xd0\xb0 \xd0\xb2 \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd0\xb8.");

        // new proposals
        for (auto const& pair : s_raids)
        {
            std::vector<std::pair<ObjectGuid, uint8>> picked;
            if (!PickRaid(pair.second, picked))
                continue;
            Proposal proposal;
            proposal.Id = s_nextProposal++;
            proposal.RaidId = pair.first;
            proposal.Expires = now + PROPOSAL_TIME;
            proposal.Members = picked;
            for (auto const& member : picked)
            {
                Queued& entry = s_queue[member.first];
                entry.Status = STATE_PROPOSAL;
                entry.ProposalId = proposal.Id;
            }
            s_proposals[proposal.Id] = proposal;
            SendProposal(proposal);
            SendStatusToRaidQueue(pair.first);
        }

        // finished instances: their rewarded bosses forgotten
        for (auto itr = s_rewardedBosses.begin(); itr != s_rewardedBosses.end();)
        {
            if (!sInstanceSaveMgr->GetInstanceSave(itr->first))
                itr = s_rewardedBosses.erase(itr);
            else
                ++itr;
        }
    }

    // ---------------------------------------------------------------- AddonComm
    void HandleList(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendList(player);
    }

    void HandleJoin(Player* player, std::vector<std::string> const& args)
    {
        if (args.size() < 2)
            return;
        Raid const* raid = GetRaid(CommToUInt32(args[0]));
        uint8 roles = uint8(CommToUInt32(args[1]) & ROLE_ALL);
        if (!raid || !roles)
            return;
        if (IsBusy(player->GetGUID()))
        {
            Result(player, "\xd0\x92\xd1\x8b \xd1\x83\xd0\xb6\xd0\xb5 \xd0\xb2 \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd0\xb8.");
            return;
        }

        Group* group = player->GetGroup();
        if (group)
        {
            if (group->IsSoloAllowed())
            {
                Result(player, "\xd0\xa1\xd0\xbd\xd0\xb0\xd1\x87\xd0\xb0\xd0\xbb\xd0\xb0 \xd0\xbf\xd0\xbe\xd0\xba\xd0\xb8\xd0\xbd\xd1\x8c\xd1\x82\xd0\xb5 \xd1\x82\xd0\xb5\xd0\xba\xd1\x83\xd1\x89\xd0\xb8\xd0\xb9 \xd1\x80\xd0\xb5\xd0\xb9\xd0\xb4 \xd0\xbf\xd0\xbe\xd0\xb8\xd1\x81\xd0\xba\xd0\xb0.");
                return;
            }
            if (!group->IsLeader(player->GetGUID()))
            {
                Result(player, "\xd0\x9f\xd0\xbe\xd1\x81\xd1\x82\xd0\xb0\xd0\xb2\xd0\xb8\xd1\x82\xd1\x8c \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd1\x83 \xd0\xb2 \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd1\x8c \xd0\xbc\xd0\xbe\xd0\xb6\xd0\xb5\xd1\x82 \xd1\x82\xd0\xbe\xd0\xbb\xd1\x8c\xd0\xba\xd0\xbe \xd0\xbb\xd0\xb8\xd0\xb4\xd0\xb5\xd1\x80.");
                return;
            }
            StartRoleCheck(player, group, *raid, roles);
            return;
        }

        std::string error = JoinError(player, *raid, false);
        if (!error.empty())
        {
            Result(player, error);
            return;
        }
        Queued entry;
        entry.Guid = player->GetGUID();
        entry.RaidId = raid->Id;
        entry.Roles = roles;
        entry.JoinTime = GameTime::GetGameTime();
        s_queue[entry.Guid] = entry;
        SendStatusToRaidQueue(raid->Id);
    }

    void HandleRoles(Player* player, std::vector<std::string> const& args)
    {
        if (args.empty())
            return;
        for (auto& pair : s_roleChecks)
        {
            auto member = pair.second.Roles.find(player->GetGUID());
            if (member == pair.second.Roles.end())
                continue;
            uint8 roles = uint8(CommToUInt32(args[0]) & ROLE_ALL);
            if (!roles)
            {
                EndRoleCheck(pair.first, std::string(player->GetName()) + " \xd0\xbe\xd1\x82\xd0\xba\xd0\xb0\xd0\xb7\xd1\x8b\xd0\xb2\xd0\xb0\xd0\xb5\xd1\x82\xd1\x81\xd1\x8f. \xd0\x93\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd0\xb0 \xd0\xbd\xd0\xb5 \xd0\xbf\xd0\xbe\xd1\x81\xd1\x82\xd0\xb0\xd0\xb2\xd0\xbb\xd0\xb5\xd0\xbd\xd0\xb0 \xd0\xb2 \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd1\x8c.");
                return;
            }
            member->second = roles;
            for (auto const& other : pair.second.Roles)
                if (!other.second)
                {
                    SendStatus(player);
                    return;
                }
            RoleCheck check = pair.second;
            FinishRoleCheck(check);
            return;
        }
    }

    void HandleLeave(Player* player, std::vector<std::string> const& /*args*/)
    {
        // a role check: declined
        for (auto const& pair : s_roleChecks)
            if (pair.second.Roles.count(player->GetGUID()))
            {
                EndRoleCheck(pair.first, std::string(player->GetName()) + " \xd0\xbe\xd1\x82\xd0\xba\xd0\xb0\xd0\xb7\xd1\x8b\xd0\xb2\xd0\xb0\xd0\xb5\xd1\x82\xd1\x81\xd1\x8f. \xd0\x93\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd0\xb0 \xd0\xbd\xd0\xb5 \xd0\xbf\xd0\xbe\xd1\x81\xd1\x82\xd0\xb0\xd0\xb2\xd0\xbb\xd0\xb5\xd0\xbd\xd0\xb0 \xd0\xb2 \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd1\x8c.");
                return;
            }

        auto itr = s_queue.find(player->GetGUID());
        if (itr == s_queue.end())
            return;
        if (itr->second.Status == STATE_PROPOSAL)
        {
            // leaving during a proposal is a decline
            auto proposal = s_proposals.find(itr->second.ProposalId);
            if (proposal != s_proposals.end())
            {
                proposal->second.Answers[player->GetGUID()] = false;
                CancelProposal(proposal->first, "\xd0\x9e\xd0\xb4\xd0\xb8\xd0\xbd \xd0\xb8\xd0\xb7 \xd1\x83\xd1\x87\xd0\xb0\xd1\x81\xd1\x82\xd0\xbd\xd0\xb8\xd0\xba\xd0\xbe\xd0\xb2 \xd0\xbe\xd1\x82\xd0\xba\xd0\xb0\xd0\xb7\xd0\xb0\xd0\xbb\xd1\x81\xd1\x8f. \xd0\x92\xd1\x8b \xd1\x81\xd0\xbd\xd0\xbe\xd0\xb2\xd0\xb0 \xd0\xb2 \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd0\xb8.");
                return;
            }
        }
        LeaveQueue(player->GetGUID(), itr->second.PartyId ? std::string(player->GetName()) + " \xd0\xb2\xd1\x8b\xd0\xb2\xd0\xbe\xd0\xb4\xd0\xb8\xd1\x82 \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd1\x83 \xd0\xb8\xd0\xb7 \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd0\xb8." : std::string());
    }

    void HandleAnswer(Player* player, std::vector<std::string> const& args)
    {
        auto itr = s_queue.find(player->GetGUID());
        if (itr == s_queue.end() || itr->second.Status != STATE_PROPOSAL || args.empty())
            return;
        auto proposal = s_proposals.find(itr->second.ProposalId);
        if (proposal == s_proposals.end())
            return;
        bool accept = CommToUInt32(args[0]) != 0;
        proposal->second.Answers[player->GetGUID()] = accept;
        if (!accept)
        {
            CancelProposal(proposal->first, "\xd0\x9e\xd0\xb4\xd0\xb8\xd0\xbd \xd0\xb8\xd0\xb7 \xd1\x83\xd1\x87\xd0\xb0\xd1\x81\xd1\x82\xd0\xbd\xd0\xb8\xd0\xba\xd0\xbe\xd0\xb2 \xd0\xbe\xd1\x82\xd0\xba\xd0\xb0\xd0\xb7\xd0\xb0\xd0\xbb\xd1\x81\xd1\x8f. \xd0\x92\xd1\x8b \xd1\x81\xd0\xbd\xd0\xbe\xd0\xb2\xd0\xb0 \xd0\xb2 \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd0\xb8.");
            return;
        }
        for (auto const& member : proposal->second.Members)
        {
            auto answer = proposal->second.Answers.find(member.first);
            if (answer == proposal->second.Answers.end() || !answer->second)
            {
                SendProposal(proposal->second);
                return;
            }
        }
        Proposal ready = proposal->second;
        FormRaid(ready);
    }

    // leave the raid finder's raid (the client's party menu does not see a group of one): out of the group and back
    void HandleLeaveRaid(Player* player, std::vector<std::string> const& /*args*/)
    {
        if (!s_returns.count(player->GetGUID()))
            return;
        s_pendingReturn.push_back(player->GetGUID());
        if (player->GetGroup())
            player->RemoveFromGroup(GROUP_REMOVEMETHOD_LEAVE);
        SendStatus(player);
    }

    void HandleStatus(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendStatus(player);
        auto itr = s_queue.find(player->GetGUID());
        if (itr != s_queue.end() && itr->second.Status == STATE_PROPOSAL)
        {
            auto proposal = s_proposals.find(itr->second.ProposalId);
            if (proposal != s_proposals.end())
                SendProposal(proposal->second);
        }
        if (RoleCheck const* check = FindRoleCheck(player->GetGUID()))
            if (!check->Roles.at(player->GetGUID()))
            {
                time_t now = GameTime::GetGameTime();
                Player* leader = ObjectAccessor::FindConnectedPlayer(check->Leader);
                sAddonComm->Send(player, "RF_ROLE_CHECK", check->RaidId, Sanitize(leader ? leader->GetName() : std::string("-")),
                    check->Expires > now ? uint32(check->Expires - now) : 0);
            }
    }
}

// ---------------------------------------------------------------- scripts
class raid_finder_world : public WorldScript
{
    uint32 timer = 0;

public:
    raid_finder_world() : WorldScript("raid_finder_world") {}

    void OnStartup() override
    {
        LoadRaids();
    }

    void OnUpdate(uint32 diff) override
    {
        if (!s_pendingReturn.empty())
            UpdateReturns();
        timer += diff;
        if (timer < UPDATE_INTERVAL)
            return;
        timer = 0;
        UpdateQueues();
    }
};

class raid_finder_player : public PlayerScript
{
public:
    raid_finder_player() : PlayerScript("raid_finder_player")
    {
        sAddonComm->Register(std::string("RF_LIST"), &HandleList);
        sAddonComm->Register(std::string("RF_JOIN"), &HandleJoin);
        sAddonComm->Register(std::string("RF_ROLES"), &HandleRoles);
        sAddonComm->Register(std::string("RF_LEAVE"), &HandleLeave);
        sAddonComm->Register(std::string("RF_ANSWER"), &HandleAnswer);
        sAddonComm->Register(std::string("RF_STATUS"), &HandleStatus);
        sAddonComm->Register(std::string("RF_LEAVE_RAID"), &HandleLeaveRaid);
    }

    void OnLogout(Player* player) override
    {
        for (auto const& pair : s_roleChecks)
            if (pair.second.Roles.count(player->GetGUID()))
            {
                EndRoleCheck(pair.first, std::string(player->GetName()) + " \xd0\xb2\xd1\x8b\xd1\x88\xd0\xb5\xd0\xbb \xd0\xb8\xd0\xb7 \xd0\xb8\xd0\xb3\xd1\x80\xd1\x8b. \xd0\x9f\xd1\x80\xd0\xbe\xd0\xb2\xd0\xb5\xd1\x80\xd0\xba\xd0\xb0 \xd1\x80\xd0\xbe\xd0\xbb\xd0\xb5\xd0\xb9 \xd0\xbe\xd1\x82\xd0\xbc\xd0\xb5\xd0\xbd\xd0\xb5\xd0\xbd\xd0\xb0.");
                break;
            }

        auto itr = s_queue.find(player->GetGUID());
        if (itr == s_queue.end())
            return;
        if (itr->second.Status == STATE_PROPOSAL)
        {
            auto proposal = s_proposals.find(itr->second.ProposalId);
            if (proposal != s_proposals.end())
            {
                proposal->second.Answers[player->GetGUID()] = false;
                CancelProposal(proposal->first, "\xd0\x9e\xd0\xb4\xd0\xb8\xd0\xbd \xd0\xb8\xd0\xb7 \xd1\x83\xd1\x87\xd0\xb0\xd1\x81\xd1\x82\xd0\xbd\xd0\xb8\xd0\xba\xd0\xbe\xd0\xb2 \xd0\xb2\xd1\x8b\xd1\x88\xd0\xb5\xd0\xbb \xd0\xb8\xd0\xb7 \xd0\xb8\xd0\xb3\xd1\x80\xd1\x8b. \xd0\x92\xd1\x8b \xd1\x81\xd0\xbd\xd0\xbe\xd0\xb2\xd0\xb0 \xd0\xb2 \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd0\xb8.");
                return;
            }
        }
        LeaveQueue(player->GetGUID(), "\xd0\x9e\xd0\xb4\xd0\xb8\xd0\xbd \xd0\xb8\xd0\xb7 \xd1\x83\xd1\x87\xd0\xb0\xd1\x81\xd1\x82\xd0\xbd\xd0\xb8\xd0\xba\xd0\xbe\xd0\xb2 \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd1\x8b \xd0\xb2\xd1\x8b\xd1\x88\xd0\xb5\xd0\xbb \xd0\xb8\xd0\xb7 \xd0\xb8\xd0\xb3\xd1\x80\xd1\x8b. \xd0\x93\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd0\xb0 \xd0\xbf\xd0\xbe\xd0\xba\xd0\xb8\xd0\xbd\xd1\x83\xd0\xbb\xd0\xb0 \xd0\xbe\xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb4\xd1\x8c.");
    }

    // a boss of the raid finder's raid: the rewards of world.raid_finder_reward to its members on the map
    void OnCreatureKill(Player* /*killer*/, Creature* killed) override
    {
        if (killed->IsDungeonBoss())
            RewardBoss(killed);
    }
};

class raid_finder_group : public GroupScript
{
public:
    raid_finder_group() : GroupScript("raid_finder_group") {}

    void OnAddMember(Group* group, ObjectGuid guid) override
    {
        OnGroupChanged(group, guid);
    }

    // only a real leave or kick sends him back: the core also removes members on its own (a group of one
    // is broken up), and that must not throw a player out of the raid he was just moved into
    void OnRemoveMember(Group* group, ObjectGuid guid, RemoveMethod method, ObjectGuid /*kicker*/, char const* /*reason*/) override
    {
        OnGroupChanged(group, guid);
        if (s_returns.count(guid))
            TC_LOG_ERROR("scripts", "raid_finder: {} removed from group {} (method {}, members {}, solo allowed {})",
                guid.ToString(), group->GetGUID().ToString(), uint32(method), group->GetMembersCount(), group->IsSoloAllowed());
        if (method != GROUP_REMOVEMETHOD_LEAVE && method != GROUP_REMOVEMETHOD_KICK)
            return;
        if (s_returns.count(guid))
            s_pendingReturn.push_back(guid);
    }

    void OnDisband(Group* group) override
    {
        OnGroupChanged(group, ObjectGuid::Empty);
        for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
            if (Player* member = ref->GetSource())
                if (s_returns.count(member->GetGUID()))
                    TC_LOG_ERROR("scripts", "raid_finder: group {} of {} disbanded (members {})",
                        group->GetGUID().ToString(), member->GetName(), group->GetMembersCount());
        // a raid of one (testing with tanks = healers = 0, damage = 1) is disbanded by the core: he stays
        if (group->GetMembersCount() <= 1)
            return;
        for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
            if (Player* member = ref->GetSource())
                if (s_returns.count(member->GetGUID()))
                    s_pendingReturn.push_back(member->GetGUID());
    }
};

class raid_finder_commands : public CommandScript
{
public:
    raid_finder_commands() : CommandScript("raid_finder_commands") {}

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable rfTable =
        {
            { "list",   HandleListCommand,   rbac::RBAC_PERM_COMMAND_ADDITEM, Console::Yes },
            { "reload", HandleReloadCommand, rbac::RBAC_PERM_COMMAND_ADDITEM, Console::Yes },
        };
        static ChatCommandTable commandTable =
        {
            { "rf", rfTable },
        };
        return commandTable;
    }

    static bool HandleListCommand(ChatHandler* handler)
    {
        for (auto const& pair : s_raids)
        {
            uint32 queued = 0, proposed = 0;
            for (auto const& entry : s_queue)
                if (entry.second.RaidId == pair.first)
                    ++(entry.second.Status == STATE_PROPOSAL ? proposed : queued);
            handler->SendSysMessage(Trinity::StringFormat("{} {} (map {}, difficulty {}, {}/{}/{}): queued {}, in a proposal {}",
                pair.first, pair.second.Name, pair.second.MapId, uint32(pair.second.Difficulty),
                pair.second.Tanks, pair.second.Healers, pair.second.Damage, queued, proposed));
        }
        handler->SendSysMessage(Trinity::StringFormat("role checks {}", s_roleChecks.size()));
        return true;
    }

    static bool HandleReloadCommand(ChatHandler* handler)
    {
        LoadRaids();
        handler->SendSysMessage(Trinity::StringFormat("raid_finder: {} raids, rewards for {} raids loaded", s_raids.size(), s_rewards.size()));
        return true;
    }
};

void AddSC_raid_finder()
{
    new raid_finder_world();
    new raid_finder_player();
    new raid_finder_group();
    new raid_finder_commands();
}
