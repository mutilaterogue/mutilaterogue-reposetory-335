/*
 * Raid Finder (retail: LFR) for 3.3.5 - its own queue, not LFGMgr (TrinityCore's dungeon finder does not build raids).
 *
 * Raids: world.raid_finder_dungeon (sql/world_raid_finder.sql) - map, difficulty (0 10 normal, 1 25 normal,
 * 2 10 heroic, 3 25 heroic), the roles a raid needs, level / item level requirements.
 *
 * Queue: solo players only (the retail LFR queues groups too: later). A player picks the raid and the roles
 * (tank / healer / damage, any mix). Every UPDATE_INTERVAL each raid takes the earliest queued players:
 * tanks first, then healers, then damage, a player with several roles where he is needed most.
 * Not enough players for every role - nobody is taken, the queue waits.
 *
 * Proposal: the chosen players get "RF_PROPOSAL"; all accept within PROPOSAL_TIME -> a raid group is made
 * (the first tank leads), its raid difficulty set, everybody teleported to the raid's entrance.
 * A decline or a timeout: that player is out of the queue, the others are back in at their old place.
 * Saved to that raid (this difficulty), below the level / item level, in a group: cannot join.
 * Leaving the raid group (or its disband) inside the raid: back to where the player queued (retail).
 *
 * AddonComm (client: GroupFinder\RaidFinder.lua):
 *  C->S "RF_LIST"                      -> S->C "RF_LIST" : id;name;mapId;difficulty;size;minLevel;minItemLevel;saved,...
 *       "RF_JOIN" : raidId : roles      (roles: 1 tank, 2 healer, 4 damage - a bit mask)
 *       "RF_LEAVE"
 *       "RF_ANSWER" : 1 / 0             (accept / decline the proposal)
 *       "RF_STATUS"                     -> S->C "RF_STATUS" (below)
 *  S->C "RF_STATUS" : state : raidId : roles : seconds queued : tanks : healers : damage : tanks needed : healers needed : damage needed
 *              state 0 none, 1 queued, 2 proposal; the counts are the players queued for that raid by role
 *       "RF_PROPOSAL" : raidId : seconds left : accepted : total : my answer (0 none, 1 accepted)
 *       "RF_RESULT" : message
 *
 * GM: .rf list (the queues), .rf reload (the raid table)
 *
 * Setup: sql/world_raid_finder.sql, AddSC_raid_finder() in custom_script_loader.cpp.
 */

#include "ScriptMgr.h"
#include "Custom\AddonComm\AddonComm.h"
#include "Chat.h"
#include "ChatCommand.h"
#include "DatabaseEnv.h"
#include "GameTime.h"
#include "Group.h"
#include "GroupMgr.h"
#include "InstanceSaveMgr.h"
#include "Log.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "RBAC.h"
#include "StringFormat.h"
#include "World.h"
#include "WorldSession.h"

#include <algorithm>
#include <map>
#include <sstream>
#include <vector>

using namespace Trinity::ChatCommands;

namespace
{
    // ---------------------------------------------------------------- config
    constexpr uint32 UPDATE_INTERVAL = 3 * IN_MILLISECONDS;
    constexpr uint32 PROPOSAL_TIME   = 45;      // seconds

    enum Roles : uint8
    {
        ROLE_TANK   = 0x1,
        ROLE_HEALER = 0x2,
        ROLE_DAMAGE = 0x4,
        ROLE_ALL    = ROLE_TANK | ROLE_HEALER | ROLE_DAMAGE,
    };

    enum State : uint8
    {
        STATE_NONE     = 0,
        STATE_QUEUED   = 1,
        STATE_PROPOSAL = 2,
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

    struct Queued
    {
        ObjectGuid Guid;
        uint32 RaidId = 0;
        uint8 Roles = 0;
        time_t JoinTime = 0;
        State Status = STATE_QUEUED;
        uint32 ProposalId = 0;
    };

    struct Proposal
    {
        uint32 Id = 0;
        uint32 RaidId = 0;
        time_t Expires = 0;
        std::vector<std::pair<ObjectGuid, uint8>> Members;  // player, the role he got
        std::map<ObjectGuid, bool> Answers;                 // accepted
    };

    std::map<uint32, Raid> s_raids;
    std::map<ObjectGuid, Queued> s_queue;
    std::map<uint32, Proposal> s_proposals;
    uint32 s_nextProposal = 1;

    // where the raid finder took a player from: back there when he leaves its raid group (retail)
    struct Return
    {
        uint32 RaidMapId = 0;
        WorldLocation Pos;
    };
    std::map<ObjectGuid, Return> s_returns;
    std::vector<ObjectGuid> s_pendingReturn;   // left the group: teleported on the next world update

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
        QueryResult result = WorldDatabase.Query("SELECT CAST(id AS SIGNED), CAST(map_id AS SIGNED), CAST(difficulty AS SIGNED), name, "
            "CAST(tanks AS SIGNED), CAST(healers AS SIGNED), CAST(damage AS SIGNED), CAST(min_level AS SIGNED), CAST(min_item_level AS SIGNED) "
            "FROM raid_finder_dungeon ORDER BY id");
        if (!result)
            return;
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

    // why the player cannot queue for that raid (empty - he can)
    std::string JoinError(Player* player, Raid const& raid)
    {
        if (player->GetGroup())
            return "Поиск рейда пока только для одиночек: выйдите из группы.";
        if (player->InBattleground() || player->InBattlegroundQueue())
            return "Нельзя встать в очередь, находясь на поле боя или в его очереди.";
        if (player->GetLevel() < raid.MinLevel)
            return "Слишком низкий уровень для этого рейда.";
        if (raid.MinItemLevel && player->GetAverageItemLevel() < float(raid.MinItemLevel))
            return "Слишком низкий уровень предметов для этого рейда.";
        if (IsSaved(player, raid))
            return "Вы уже сохранены в этом рейде.";
        return std::string();
    }

    // ---------------------------------------------------------------- status
    void SendStatus(Player* player)
    {
        auto itr = s_queue.find(player->GetGUID());
        if (itr == s_queue.end())
        {
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

    void SendStatusToRaidQueue(uint32 raidId)
    {
        for (auto const& pair : s_queue)
            if (pair.second.RaidId == raidId)
                if (Player* player = ObjectAccessor::FindConnectedPlayer(pair.first))
                    SendStatus(player);
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
    void LeaveQueue(ObjectGuid guid, bool notify)
    {
        auto itr = s_queue.find(guid);
        if (itr == s_queue.end())
            return;
        uint32 raidId = itr->second.RaidId;
        s_queue.erase(itr);
        if (notify)
            if (Player* player = ObjectAccessor::FindConnectedPlayer(guid))
                SendStatus(player);
        SendStatusToRaidQueue(raidId);
    }

    // a proposal is over: the accepted ones back in the queue (decline / timeout), the rest out
    void CancelProposal(uint32 proposalId, std::string const& reason)
    {
        auto itr = s_proposals.find(proposalId);
        if (itr == s_proposals.end())
            return;
        Proposal proposal = itr->second;
        s_proposals.erase(itr);

        for (auto const& member : proposal.Members)
        {
            auto answer = proposal.Answers.find(member.first);
            bool accepted = answer != proposal.Answers.end() && answer->second;
            Player* player = ObjectAccessor::FindConnectedPlayer(member.first);
            auto entry = s_queue.find(member.first);
            if (accepted && player && entry != s_queue.end())
            {
                entry->second.Status = STATE_QUEUED;
                entry->second.ProposalId = 0;
                Result(player, reason);
            }
            else
            {
                s_queue.erase(member.first);
                if (player)
                    Result(player, "Вы покинули очередь в рейд.");
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
            if (!player || player->GetGroup() || !raid || !JoinError(player, *raid).empty())
            {
                // somebody is gone or no longer fits: the others back in the queue
                Proposal copy = proposal;
                copy.Answers[member.first] = false;
                s_proposals[copy.Id] = copy;
                CancelProposal(copy.Id, "Один из участников больше не может войти. Вы снова в очереди.");
                return;
            }
            players.push_back(player);
        }

        Group* group = new Group();
        if (!group->Create(players.front()))
        {
            delete group;
            CancelProposal(proposal.Id, "Не удалось создать рейд. Вы снова в очереди.");
            return;
        }
        sGroupMgr->AddGroup(group);
        group->ConvertToRaid();
        group->SetRaidDifficultyID(Difficulty(raid->Difficulty));
        for (size_t i = 1; i < players.size(); ++i)
            group->AddMember(players[i]);

        for (auto const& member : proposal.Members)
        {
            if (member.second == ROLE_TANK)
                group->SetGroupMemberFlag(member.first, true, MEMBER_FLAG_MAINTANK);
            s_queue.erase(member.first);
        }
        s_proposals.erase(proposal.Id);

        for (Player* player : players)
        {
            player->SetRaidDifficultyID(Difficulty(raid->Difficulty));
            Return& back = s_returns[player->GetGUID()];
            back.RaidMapId = raid->MapId;
            back.Pos.WorldRelocate(*player);
            Result(player, "Рейд собран: " + raid->Name + ".");
            SendStatus(player);
            TeleportToRaid(player, *raid);
        }
        SendStatusToRaidQueue(raid->Id);
    }

    // the earliest queued players for every role of a raid; false - not enough of them
    bool PickRaid(Raid const& raid, std::vector<std::pair<ObjectGuid, uint8>>& picked)
    {
        std::vector<Queued const*> queued;
        for (auto const& pair : s_queue)
            if (pair.second.RaidId == raid.Id && pair.second.Status == STATE_QUEUED)
                queued.push_back(&pair.second);
        if (queued.size() < raid.Size())
            return false;
        std::sort(queued.begin(), queued.end(), [](Queued const* a, Queued const* b) { return a->JoinTime < b->JoinTime; });

        std::vector<bool> used(queued.size(), false);
        // the scarce roles first; a player with only one role before the flexible ones
        auto take = [&](uint8 role, uint32 count) -> bool
        {
            for (int pass = 0; pass < 2 && count; ++pass)
                for (size_t i = 0; i < queued.size() && count; ++i)
                {
                    if (used[i] || !(queued[i]->Roles & role))
                        continue;
                    bool single = queued[i]->Roles == role;
                    if (pass == 0 && !single)
                        continue;
                    used[i] = true;
                    picked.emplace_back(queued[i]->Guid, role);
                    --count;
                }
            return count == 0;
        };
        return take(ROLE_TANK, raid.Tanks) && take(ROLE_HEALER, raid.Healers) && take(ROLE_DAMAGE, raid.Damage);
    }

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
            Result(player, "Вы покинули рейд.");
            player->TeleportTo(back.Pos);
        }
        s_pendingReturn.clear();
    }

    void UpdateQueues()
    {
        // offline players out of the queue
        for (auto itr = s_queue.begin(); itr != s_queue.end();)
        {
            if (!ObjectAccessor::FindConnectedPlayer(itr->first) && itr->second.Status == STATE_QUEUED)
                itr = s_queue.erase(itr);
            else
                ++itr;
        }

        // expired proposals
        time_t now = GameTime::GetGameTime();
        std::vector<uint32> expired;
        for (auto const& pair : s_proposals)
            if (pair.second.Expires <= now)
                expired.push_back(pair.first);
        for (uint32 id : expired)
            CancelProposal(id, "Не все участники подтвердили готовность. Вы снова в очереди.");

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
        if (s_queue.count(player->GetGUID()))
        {
            Result(player, "Вы уже в очереди.");
            return;
        }
        std::string error = JoinError(player, *raid);
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

    void HandleLeave(Player* player, std::vector<std::string> const& /*args*/)
    {
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
                CancelProposal(proposal->first, "Один из участников отказался. Вы снова в очереди.");
                return;
            }
        }
        LeaveQueue(player->GetGUID(), true);
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
            CancelProposal(proposal->first, "Один из участников отказался. Вы снова в очереди.");
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
        FormRaid(proposal->second);
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
        sAddonComm->Register(std::string("RF_LEAVE"), &HandleLeave);
        sAddonComm->Register(std::string("RF_ANSWER"), &HandleAnswer);
        sAddonComm->Register(std::string("RF_STATUS"), &HandleStatus);
    }

    void OnLogout(Player* player) override
    {
        auto itr = s_queue.find(player->GetGUID());
        if (itr == s_queue.end())
            return;
        if (itr->second.Status == STATE_PROPOSAL)
        {
            auto proposal = s_proposals.find(itr->second.ProposalId);
            if (proposal != s_proposals.end())
            {
                proposal->second.Answers[player->GetGUID()] = false;
                CancelProposal(proposal->first, "Один из участников вышел из игры. Вы снова в очереди.");
                return;
            }
        }
        LeaveQueue(player->GetGUID(), false);
    }
};

class raid_finder_group : public GroupScript
{
public:
    raid_finder_group() : GroupScript("raid_finder_group") {}

    void OnRemoveMember(Group* /*group*/, ObjectGuid guid, RemoveMethod /*method*/, ObjectGuid /*kicker*/, char const* /*reason*/) override
    {
        if (s_returns.count(guid))
            s_pendingReturn.push_back(guid);
    }

    void OnDisband(Group* group) override
    {
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
        return true;
    }

    static bool HandleReloadCommand(ChatHandler* handler)
    {
        LoadRaids();
        handler->SendSysMessage(Trinity::StringFormat("raid_finder: {} raids loaded", s_raids.size()));
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
