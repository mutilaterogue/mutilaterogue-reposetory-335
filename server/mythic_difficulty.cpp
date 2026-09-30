/*
 * Mythic dungeon difficulty (retail: DifficultyID 23) for 3.3.5 - base.
 *
 * 3.3.5 has only normal / heroic for 5-man dungeons. Mythic is heroic + a flag:
 *  - the player (or the group leader) chooses mythic in the unit popup (PlayerFrameMenu.lua);
 *  - the first player entering a heroic 5-man instance decides the flag of that instance;
 *  - in a mythic instance creature damage is multiplied by DAMAGE_MULT and damage taken by
 *    creatures is divided by HEALTH_MULT (same as more health, no creature hooks needed).
 * Mythic shares the heroic lockout.
 *
 * AddonComm (client: PlayerFrame\PlayerFrameMenu.lua):
 *   "MYTHIC_GET"          -> "MYTHIC_STATE" : 0/1
 *   "MYTHIC_SET" : 0/1    -> "MYTHIC_STATE" to the player (or every group member), or "MYTHIC_RESULT" : error
 *
 * Setup: AddSC_mythic_difficulty() in custom_script_loader.cpp.
 */

#include "ScriptMgr.h"
#include "Custom\AddonComm\AddonComm.h"
#include "Chat.h"
#include "Group.h"
#include "Map.h"
#include "Player.h"
#include "WorldSession.h"

#include <algorithm>
#include <unordered_map>
#include <unordered_set>

namespace
{
    constexpr float DAMAGE_MULT = 1.3f;
    constexpr float HEALTH_MULT = 1.5f;

    std::unordered_set<ObjectGuid::LowType> s_wanted;       // players (or leaders) who chose mythic
    std::unordered_map<uint32, bool> s_instances;           // instanceId -> mythic

    ObjectGuid::LowType Owner(Player* player)
    {
        if (Group* group = player->GetGroup())
            return group->GetLeaderGUID().GetCounter();
        return player->GetGUID().GetCounter();
    }

    bool IsWanted(Player* player)
    {
        return s_wanted.count(Owner(player)) != 0;
    }

    bool IsMythicMap(Map const* map)
    {
        if (!map || !map->IsDungeon() || map->IsRaid())
            return false;
        auto itr = s_instances.find(map->GetInstanceId());
        return itr != s_instances.end() && itr->second;
    }

    void SendState(Player* player)
    {
        sAddonComm->Send(player, "MYTHIC_STATE", IsWanted(player) ? 1 : 0);
    }

    void SendStateToGroup(Player* player)
    {
        Group* group = player->GetGroup();
        if (!group)
        {
            SendState(player);
            return;
        }
        for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
            if (Player* member = ref->GetSource())
                SendState(member);
    }

    void HandleGet(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendState(player);
    }

    void HandleSet(Player* player, std::vector<std::string> const& args)
    {
        bool mythic = !args.empty() && args[0] == "1";

        Group* group = player->GetGroup();
        if (group && group->GetLeaderGUID() != player->GetGUID())
        {
            sAddonComm->Send(player, "MYTHIC_RESULT", "ERR_NOT_LEADER");
            SendState(player);
            return;
        }
        if (player->GetMap()->IsDungeon())
        {
            sAddonComm->Send(player, "MYTHIC_RESULT", "ERR_DIFFICULTY_CHANGE_IN_INSTANCE");
            SendState(player);
            return;
        }

        if (mythic)
            s_wanted.insert(player->GetGUID().GetCounter());
        else
            s_wanted.erase(player->GetGUID().GetCounter());

        SendStateToGroup(player);
    }

    bool IsCreature(Unit* unit)
    {
        return unit && unit->GetTypeId() == TYPEID_UNIT && !unit->IsControlledByPlayer();
    }

    template <typename T>
    void Modify(Unit* target, Unit* attacker, T& damage)
    {
        if (!target || !attacker || damage <= 0 || !IsMythicMap(target->GetMap()))
            return;
        if (IsCreature(attacker) && !IsCreature(target))
            damage = T(damage * DAMAGE_MULT);
        else if (IsCreature(target) && !IsCreature(attacker))
            damage = std::max<T>(1, T(damage / HEALTH_MULT));
    }
}

class mythic_difficulty_player : public PlayerScript
{
public:
    mythic_difficulty_player() : PlayerScript("mythic_difficulty_player")
    {
        sAddonComm->Register(std::string("MYTHIC_GET"), &HandleGet);
        sAddonComm->Register(std::string("MYTHIC_SET"), &HandleSet);
    }

    void OnLogin(Player* player, bool /*firstLogin*/) override
    {
        SendState(player);
    }

    void OnLogout(Player* player) override
    {
        if (!player->GetGroup())
            s_wanted.erase(player->GetGUID().GetCounter());
    }

    void OnMapChanged(Player* player) override
    {
        Map* map = player->GetMap();
        if (!map->IsDungeon() || map->IsRaid() || map->GetDifficulty() != DUNGEON_DIFFICULTY_HEROIC)
            return;

        uint32 instanceId = map->GetInstanceId();
        if (!s_instances.count(instanceId))
            s_instances[instanceId] = IsWanted(player);

        if (s_instances[instanceId])
            ChatHandler(player->GetSession()).SendSysMessage("|cffff8000\xD0\xAD\xD0\xBF\xD0\xBE\xD1\x85\xD0\xB0\xD0\xBB\xD1\x8C\xD0\xBD\xD1\x8B\xD0\xB9 \xD1\x80\xD0\xB5\xD0\xB6\xD0\xB8\xD0\xBC|r");
    }
};

class mythic_difficulty_unit : public UnitScript
{
public:
    mythic_difficulty_unit() : UnitScript("mythic_difficulty_unit") { }

    void ModifyMeleeDamage(Unit* target, Unit* attacker, uint32& damage) override
    {
        Modify(target, attacker, damage);
    }

    void ModifySpellDamageTaken(Unit* target, Unit* attacker, int32& damage) override
    {
        Modify(target, attacker, damage);
    }

    void ModifyPeriodicDamageAurasTick(Unit* target, Unit* attacker, uint32& damage) override
    {
        Modify(target, attacker, damage);
    }
};

void AddSC_mythic_difficulty()
{
    new mythic_difficulty_player();
    new mythic_difficulty_unit();
}
