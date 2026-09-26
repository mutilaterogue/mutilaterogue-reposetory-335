/*
 * Transmog outfits, situations and custom sets (retail TransmogOutfit* / TransmogSituation* / custom sets) for 3.3.5.
 *
 * Outfits (per character, characters.character_transmog_outfits):
 *   - FREE_OUTFITS slots, more are bought for gold (retail GetNextOutfitToUnlock / TransmogOutfitEntry.Cost)
 *   - saving costs like transmogrifying the changed slots, switching to a saved outfit is free (retail TRANSMOG_HELP_2)
 *   - situations: the outfit is equipped automatically when all chosen conditions match
 * Custom sets (per account, characters.account_transmog_custom_sets): saved looks, loaded into the preview.
 *
 * AddonComm opcodes (client: Transmog\Blizzard_TransmogOutfits.lua, _CustomSets.lua, _Situations.lua):
 *   "TMOG_OUTFITS_GET"                                   -> "TMOG_OUTFIT" x N, "TMOG_OUTFITS_END"
 *   "TMOG_OUTFIT"      S: id : name : iconItem : "slot/item,..." : situationsEnabled : location : movement : combat
 *   "TMOG_OUTFITS_END" S: unlocked : max : nextSlotCost : activeId
 *   "TMOG_OUTFIT_SAVE" C: id(0 = new) : name : iconItem : "slot/item,..."  -> TMOG_RESULT, list, state
 *   "TMOG_OUTFIT_EQUIP" C: id                            -> TMOG_RESULT, state, list
 *   "TMOG_OUTFIT_RENAME" C: id : name : iconItem
 *   "TMOG_OUTFIT_DEL"  C: id
 *   "TMOG_OUTFIT_BUY"  C:
 *   "TMOG_OUTFIT_SIT"  C: id : enabled : location : movement : combat
 *   "TMOG_CSETS_GET"                                     -> "TMOG_CSET" x N, "TMOG_CSETS_END" : count : max
 *   "TMOG_CSET"        S: id : name : "slot/item,..."
 *   "TMOG_CSET_SAVE"   C: id(0 = new) : name : "slot/item,..."
 *   "TMOG_CSET_DEL"    C: id
 *
 * Situations: location 0 any, 1 city / inn, 2 open world, 3 dungeon, 4 raid, 5 battleground / arena;
 *             movement 0 any, 1 mounted, 2 on foot; combat 0 any, 1 in combat, 2 out of combat.
 *
 * Setup: sql/characters_transmog_outfits.sql, register AddSC_transmog_outfits().
 */

#include "transmog.h"
#include "ScriptMgr.h"
#include "AddonComm\AddonComm.h"
#include "DatabaseEnv.h"
#include "Item.h"
#include "Map.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "World.h"
#include "WorldSession.h"

#include <algorithm>
#include <map>
#include <sstream>
#include <unordered_map>
#include <vector>

namespace
{
    constexpr uint32 FREE_OUTFITS = 5;
    constexpr uint32 MAX_OUTFITS = 30;
    constexpr uint64 OUTFIT_SLOT_BASE_COST = 10 * 10000;   // 10 gold, x2, x3... for every next slot
    constexpr uint32 MAX_CUSTOM_SETS = 50;
    constexpr size_t MAX_NAME_BYTES = 48;
    constexpr uint32 SITUATION_INTERVAL_MS = 2000;

    enum SituationLocation : uint8 { LOC_ANY, LOC_CITY, LOC_WORLD, LOC_DUNGEON, LOC_RAID, LOC_PVP, LOC_MAX };
    enum SituationMovement : uint8 { MOVE_ANY, MOVE_MOUNTED, MOVE_FOOT, MOVE_MAX };
    enum SituationCombat : uint8 { COMBAT_ANY, COMBAT_IN, COMBAT_OUT, COMBAT_MAX };

    struct Outfit
    {
        uint32 Id = 0;
        std::string Name;
        uint32 Icon = 0;
        Transmog::SlotList Slots;
        bool SituationsEnabled = false;
        uint8 Location = LOC_ANY;
        uint8 Movement = MOVE_ANY;
        uint8 Combat = COMBAT_ANY;

        uint32 SituationCount() const { return (Location != LOC_ANY) + (Movement != MOVE_ANY) + (Combat != COMBAT_ANY); }
    };

    struct PlayerOutfits
    {
        std::map<uint32, Outfit> Outfits;
        uint32 Unlocked = FREE_OUTFITS;
        uint32 Active = 0;
    };

    std::unordered_map<ObjectGuid::LowType, PlayerOutfits> outfitsByPlayer;
    uint32 situationTimer = SITUATION_INTERVAL_MS;

    std::string Arg(std::vector<std::string> const& args, size_t index)
    {
        return index < args.size() ? args[index] : std::string();
    }

    uint32 ArgUInt(std::vector<std::string> const& args, size_t index)
    {
        return CommToUInt32(Arg(args, index), 0);
    }

    void SendError(Player* player, char const* error, uint32 item = 0)
    {
        Transmog::ApplyResult result;
        result.Error = error;
        result.ErrorItem = item;
        Transmog::SendResult(player, result);
    }

    // keep only transmog slots with collected appearances the character can use (retail TRANSMOG_OUTFIT_SOME_INVALID_APPEARANCES)
    Transmog::SlotList FilterSlots(Player* player, Transmog::SlotList const& slots, bool& removed)
    {
        std::unordered_set<uint32> collected = Transmog::LoadCollected(player);
        std::unordered_set<uint8> seen;
        Transmog::SlotList result;
        removed = false;
        for (auto const& [slot, itemId] : slots)
        {
            ItemTemplate const* proto = itemId ? sObjectMgr->GetItemTemplate(itemId) : nullptr;
            if (!Transmog::IsTransmogSlot(slot) || !seen.insert(slot).second || !itemId || !proto
                || player->CanUseItem(proto) != EQUIP_ERR_OK || !Transmog::IsAppearanceCollected(collected, itemId))
            {
                removed = removed || itemId != 0;
                continue;
            }
            result.emplace_back(slot, itemId);
        }
        return result;
    }

    PlayerOutfits& GetOutfits(Player* player)
    {
        return outfitsByPlayer[player->GetGUID().GetCounter()];
    }

    void LoadOutfits(Player* player)
    {
        ObjectGuid::LowType guid = player->GetGUID().GetCounter();
        PlayerOutfits& data = outfitsByPlayer[guid];
        data = PlayerOutfits();

        if (QueryResult result = CharacterDatabase.PQuery("SELECT unlocked, active FROM character_transmog_outfit_slots WHERE guid = {}", guid))
        {
            data.Unlocked = std::max(FREE_OUTFITS, std::min(MAX_OUTFITS, result->Fetch()[0].GetUInt32()));
            data.Active = result->Fetch()[1].GetUInt32();
        }

        if (QueryResult result = CharacterDatabase.PQuery("SELECT id, name, icon, slots, CAST(sit_enabled AS SIGNED), CAST(sit_location AS SIGNED), CAST(sit_movement AS SIGNED), CAST(sit_combat AS SIGNED) FROM character_transmog_outfits WHERE guid = {}", guid))
        {
            do
            {
                Field* fields = result->Fetch();
                Outfit& outfit = data.Outfits[fields[0].GetUInt32()];
                outfit.Id = fields[0].GetUInt32();
                outfit.Name = fields[1].GetString();
                outfit.Icon = fields[2].GetUInt32();
                outfit.Slots = Transmog::ParseSlots(fields[3].GetString());
                outfit.SituationsEnabled = fields[4].GetInt64() != 0;
                outfit.Location = uint8(std::min<int64>(fields[5].GetInt64(), LOC_MAX - 1));
                outfit.Movement = uint8(std::min<int64>(fields[6].GetInt64(), MOVE_MAX - 1));
                outfit.Combat = uint8(std::min<int64>(fields[7].GetInt64(), COMBAT_MAX - 1));
            } while (result->NextRow());
        }
    }

    void SaveMeta(Player* player, PlayerOutfits const& data)
    {
        CharacterDatabase.PExecute("REPLACE INTO character_transmog_outfit_slots (guid, unlocked, active) VALUES ({}, {}, {})",
            player->GetGUID().GetCounter(), data.Unlocked, data.Active);
    }

    void SaveOutfit(Player* player, Outfit const& outfit)
    {
        std::string name = outfit.Name;
        CharacterDatabase.EscapeString(name);
        CharacterDatabase.PExecute("REPLACE INTO character_transmog_outfits (guid, id, name, icon, slots, sit_enabled, sit_location, sit_movement, sit_combat) "
            "VALUES ({}, {}, '{}', {}, '{}', {}, {}, {}, {})",
            player->GetGUID().GetCounter(), outfit.Id, name, outfit.Icon, Transmog::FormatSlots(outfit.Slots),
            outfit.SituationsEnabled ? 1 : 0, uint32(outfit.Location), uint32(outfit.Movement), uint32(outfit.Combat));
    }

    uint64 NextSlotCost(PlayerOutfits const& data)
    {
        if (data.Unlocked >= MAX_OUTFITS)
            return 0;
        return OUTFIT_SLOT_BASE_COST * (data.Unlocked - FREE_OUTFITS + 1);
    }

    void SendOutfits(Player* player)
    {
        PlayerOutfits& data = GetOutfits(player);
        for (auto const& [id, outfit] : data.Outfits)
            sAddonComm->Send(player, "TMOG_OUTFIT", outfit.Id, outfit.Name, outfit.Icon, Transmog::FormatSlots(outfit.Slots),
                outfit.SituationsEnabled ? 1 : 0, uint32(outfit.Location), uint32(outfit.Movement), uint32(outfit.Combat));
        sAddonComm->Send(player, "TMOG_OUTFITS_END", data.Unlocked, MAX_OUTFITS, NextSlotCost(data), data.Active);
    }

    // retail EquipTransmogOutfit: every slot of the outfit, slots without a look show the item itself
    Transmog::ApplyResult EquipOutfit(Player* player, Outfit const& outfit)
    {
        Transmog::SlotList looks;
        for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
        {
            if (!Transmog::IsTransmogSlot(slot) || !player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
                continue;
            uint32 itemId = 0;
            for (auto const& [outfitSlot, outfitItem] : outfit.Slots)
                if (outfitSlot == slot)
                    itemId = outfitItem;
            looks.emplace_back(slot, itemId);
        }
        Transmog::ApplyResult result = Transmog::ApplyLooks(player, looks, false, true);
        if (result.Ok)
        {
            PlayerOutfits& data = GetOutfits(player);
            data.Active = outfit.Id;
            SaveMeta(player, data);
        }
        return result;
    }

    void HandleOutfitsGet(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendOutfits(player);
    }

    // C: id(0 = new) : name : iconItem : slots
    void HandleOutfitSave(Player* player, std::vector<std::string> const& args)
    {
        PlayerOutfits& data = GetOutfits(player);
        uint32 id = ArgUInt(args, 0);
        std::string name = Transmog::SanitizeName(Arg(args, 1), MAX_NAME_BYTES);
        uint32 icon = ArgUInt(args, 2);

        bool removed = false;
        Transmog::SlotList slots = FilterSlots(player, Transmog::ParseSlots(Arg(args, 3)), removed);
        if (slots.empty() && removed)
            return SendError(player, "TRANSMOG_OUTFIT_ALL_INVALID_APPEARANCES");

        Outfit* outfit = nullptr;
        if (id)
        {
            auto itr = data.Outfits.find(id);
            if (itr == data.Outfits.end())
                return SendError(player, "ERR_TRANSMOG_PURCHASE_FAILURE");
            outfit = &itr->second;
        }
        else
        {
            if (data.Outfits.size() >= data.Unlocked)
                return SendError(player, "TRANSMOG_PURCHASE_OUTFIT_SLOT_TOOLTIP_DISABLED");
            for (auto const& [otherId, other] : data.Outfits)
                if (!name.empty() && other.Name == name)
                    return SendError(player, "TRANSMOG_OUTFIT_ALREADY_EXISTS");
        }
        if (name.empty() && !outfit)
            return SendError(player, "TRANSMOG_OUTFIT_INVALID_NAME");

        // retail HandleTransmogOutfitUpdateSlots: pay for the slots that change, then the outfit is equipped
        Transmog::SlotList changed;
        for (auto const& [slot, itemId] : slots)
        {
            bool same = false;
            if (outfit)
                for (auto const& [oldSlot, oldItem] : outfit->Slots)
                    same = same || (oldSlot == slot && oldItem == itemId);
            if (!same)
                changed.emplace_back(slot, itemId);
        }
        if (uint64 cost = Transmog::GetCost(player, changed))
        {
            if (!player->HasEnoughMoney(cost))
                return SendError(player, "ERR_TRANSMOG_OUTFIT_SLOT_CANNOT_AFFORD");
            player->ModifyMoney(-int64(cost));
        }

        if (!outfit)
        {
            uint32 newId = 1;
            while (data.Outfits.count(newId))
                ++newId;
            outfit = &data.Outfits[newId];
            outfit->Id = newId;
        }
        if (!name.empty())
            outfit->Name = name;
        if (icon)
            outfit->Icon = icon;
        else if (!outfit->Icon && !slots.empty())
            outfit->Icon = slots.front().second;
        outfit->Slots = slots;
        SaveOutfit(player, *outfit);

        Transmog::ApplyResult result = EquipOutfit(player, *outfit);
        if (removed)
            result.Error = "TRANSMOG_OUTFIT_SOME_INVALID_APPEARANCES";
        Transmog::SendResult(player, result);
        Transmog::SendState(player);
        SendOutfits(player);
    }

    void HandleOutfitEquip(Player* player, std::vector<std::string> const& args)
    {
        PlayerOutfits& data = GetOutfits(player);
        auto itr = data.Outfits.find(ArgUInt(args, 0));
        if (itr == data.Outfits.end())
            return;
        Transmog::SendResult(player, EquipOutfit(player, itr->second));
        Transmog::SendState(player);
        SendOutfits(player);
    }

    void HandleOutfitRename(Player* player, std::vector<std::string> const& args)
    {
        PlayerOutfits& data = GetOutfits(player);
        auto itr = data.Outfits.find(ArgUInt(args, 0));
        if (itr == data.Outfits.end())
            return;
        std::string name = Transmog::SanitizeName(Arg(args, 1), MAX_NAME_BYTES);
        if (!name.empty())
            itr->second.Name = name;
        if (uint32 icon = ArgUInt(args, 2))
            itr->second.Icon = icon;
        SaveOutfit(player, itr->second);
        SendOutfits(player);
    }

    void HandleOutfitDelete(Player* player, std::vector<std::string> const& args)
    {
        PlayerOutfits& data = GetOutfits(player);
        uint32 id = ArgUInt(args, 0);
        if (!data.Outfits.erase(id))
            return;
        CharacterDatabase.PExecute("DELETE FROM character_transmog_outfits WHERE guid = {} AND id = {}", player->GetGUID().GetCounter(), id);
        if (data.Active == id)
        {
            data.Active = 0;
            SaveMeta(player, data);
        }
        SendOutfits(player);
    }

    // retail HandleTransmogOutfitNew (PlayerPurchased)
    void HandleOutfitBuy(Player* player, std::vector<std::string> const& /*args*/)
    {
        PlayerOutfits& data = GetOutfits(player);
        uint64 cost = NextSlotCost(data);
        if (!cost)
            return SendError(player, "TRANSMOG_PURCHASE_OUTFIT_SLOT_TOOLTIP_DISABLED");
        if (!player->HasEnoughMoney(cost))
            return SendError(player, "ERR_TRANSMOG_OUTFIT_SLOT_CANNOT_AFFORD");
        player->ModifyMoney(-int64(cost));
        ++data.Unlocked;
        SaveMeta(player, data);
        SendOutfits(player);
    }

    // retail HandleTransmogOutfitUpdateSituations
    void HandleOutfitSituations(Player* player, std::vector<std::string> const& args)
    {
        PlayerOutfits& data = GetOutfits(player);
        auto itr = data.Outfits.find(ArgUInt(args, 0));
        if (itr == data.Outfits.end())
            return;
        Outfit& outfit = itr->second;
        outfit.SituationsEnabled = ArgUInt(args, 1) != 0;
        outfit.Location = uint8(std::min<uint32>(ArgUInt(args, 2), LOC_MAX - 1));
        outfit.Movement = uint8(std::min<uint32>(ArgUInt(args, 3), MOVE_MAX - 1));
        outfit.Combat = uint8(std::min<uint32>(ArgUInt(args, 4), COMBAT_MAX - 1));
        if (!outfit.SituationCount())
            outfit.SituationsEnabled = false;   // TRANSMOG_SITUATIONS_NO_VALID_OPTIONS
        SaveOutfit(player, outfit);
        SendOutfits(player);
    }

    uint8 GetLocation(Player* player)
    {
        Map* map = player->GetMap();
        if (map->IsBattlegroundOrArena())
            return LOC_PVP;
        if (map->IsRaid())
            return LOC_RAID;
        if (map->IsDungeon())
            return LOC_DUNGEON;
        if (player->HasRestFlag(REST_FLAG_IN_CITY) || player->HasRestFlag(REST_FLAG_IN_TAVERN))
            return LOC_CITY;
        return LOC_WORLD;
    }

    // retail TransmogSituationTrigger: the matching outfit with the most conditions is equipped
    void UpdateSituations(Player* player)
    {
        auto dataItr = outfitsByPlayer.find(player->GetGUID().GetCounter());
        if (dataItr == outfitsByPlayer.end())
            return;
        PlayerOutfits& data = dataItr->second;

        uint8 location = GetLocation(player);
        uint8 movement = player->IsMounted() ? MOVE_MOUNTED : MOVE_FOOT;
        uint8 combat = player->IsInCombat() ? COMBAT_IN : COMBAT_OUT;

        Outfit const* best = nullptr;
        for (auto const& [id, outfit] : data.Outfits)
        {
            if (!outfit.SituationsEnabled || !outfit.SituationCount())
                continue;
            if ((outfit.Location != LOC_ANY && outfit.Location != location)
                || (outfit.Movement != MOVE_ANY && outfit.Movement != movement)
                || (outfit.Combat != COMBAT_ANY && outfit.Combat != combat))
                continue;
            if (!best || outfit.SituationCount() > best->SituationCount())
                best = &outfit;
        }

        if (!best || best->Id == data.Active)
            return;
        if (EquipOutfit(player, *best).Ok)
        {
            Transmog::SendState(player);
            sAddonComm->Send(player, "TMOG_OUTFIT_ACTIVE", best->Id);
        }
    }

    // ------------------------------------------------------------------ custom sets (account)
    struct CustomSet
    {
        uint32 Id = 0;
        std::string Name;
        Transmog::SlotList Slots;
    };

    std::vector<CustomSet> LoadCustomSets(Player* player)
    {
        std::vector<CustomSet> sets;
        if (QueryResult result = CharacterDatabase.PQuery("SELECT id, name, slots FROM account_transmog_custom_sets WHERE accountId = {} ORDER BY id",
            player->GetSession()->GetAccountId()))
        {
            do
            {
                Field* fields = result->Fetch();
                CustomSet& set = sets.emplace_back();
                set.Id = fields[0].GetUInt32();
                set.Name = fields[1].GetString();
                set.Slots = Transmog::ParseSlots(fields[2].GetString());
            } while (result->NextRow());
        }
        return sets;
    }

    void SendCustomSets(Player* player)
    {
        std::vector<CustomSet> sets = LoadCustomSets(player);
        for (CustomSet const& set : sets)
            sAddonComm->Send(player, "TMOG_CSET", set.Id, set.Name, Transmog::FormatSlots(set.Slots));
        sAddonComm->Send(player, "TMOG_CSETS_END", uint32(sets.size()), MAX_CUSTOM_SETS);
    }

    void HandleCustomSetsGet(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendCustomSets(player);
    }

    // C: id(0 = new) : name : slots
    void HandleCustomSetSave(Player* player, std::vector<std::string> const& args)
    {
        uint32 id = ArgUInt(args, 0);
        std::string name = Transmog::SanitizeName(Arg(args, 1), MAX_NAME_BYTES);
        if (name.empty())
            return SendError(player, "TRANSMOG_OUTFIT_INVALID_NAME");

        bool removed = false;
        Transmog::SlotList slots = FilterSlots(player, Transmog::ParseSlots(Arg(args, 2)), removed);
        if (slots.empty())
            return SendError(player, removed ? "TRANSMOG_CUSTOM_SET_ALL_INVALID_APPEARANCES" : "TRANSMOG_CUSTOM_SET_NEW_TOOLTIP_DISABLED");

        std::vector<CustomSet> sets = LoadCustomSets(player);
        bool exists = false;
        for (CustomSet const& set : sets)
        {
            if (set.Id == id)
                exists = true;
            else if (set.Name == name)
                return SendError(player, "TRANSMOG_CUSTOM_SET_ALREADY_EXISTS");
        }
        if (!exists)
        {
            if (sets.size() >= MAX_CUSTOM_SETS)
                return SendError(player, "TRANSMOG_CUSTOM_SET_NEW_TOOLTIP_DISABLED_MAX_COUNT");
            id = 1;
            for (CustomSet const& set : sets)
                id = std::max(id, set.Id + 1);
        }

        std::string escaped = name;
        CharacterDatabase.EscapeString(escaped);
        CharacterDatabase.PExecute("REPLACE INTO account_transmog_custom_sets (accountId, id, name, slots) VALUES ({}, {}, '{}', '{}')",
            player->GetSession()->GetAccountId(), id, escaped, Transmog::FormatSlots(slots));

        Transmog::ApplyResult result;
        result.Ok = true;
        if (removed)
            result.Error = "TRANSMOG_CUSTOM_SET_SOME_INVALID_APPEARANCES";
        if (removed)
            Transmog::SendResult(player, result);
        SendCustomSets(player);
    }

    void HandleCustomSetDelete(Player* player, std::vector<std::string> const& args)
    {
        CharacterDatabase.PExecute("DELETE FROM account_transmog_custom_sets WHERE accountId = {} AND id = {}",
            player->GetSession()->GetAccountId(), ArgUInt(args, 0));
        SendCustomSets(player);
    }
}

class transmog_outfits_world : public WorldScript
{
public:
    transmog_outfits_world() : WorldScript("transmog_outfits_world") { }

    void OnUpdate(uint32 diff) override
    {
        if (situationTimer > diff)
        {
            situationTimer -= diff;
            return;
        }
        situationTimer = SITUATION_INTERVAL_MS;

        for (auto const& [accountId, session] : sWorld->GetAllSessions())
            if (Player* player = session->GetPlayer())
                if (player->IsInWorld() && player->IsAlive())
                    UpdateSituations(player);
    }
};

class transmog_outfits_player : public PlayerScript
{
public:
    transmog_outfits_player() : PlayerScript("transmog_outfits_player")
    {
        sAddonComm->Register(std::string("TMOG_OUTFITS_GET"), &HandleOutfitsGet);
        sAddonComm->Register(std::string("TMOG_OUTFIT_SAVE"), &HandleOutfitSave);
        sAddonComm->Register(std::string("TMOG_OUTFIT_EQUIP"), &HandleOutfitEquip);
        sAddonComm->Register(std::string("TMOG_OUTFIT_RENAME"), &HandleOutfitRename);
        sAddonComm->Register(std::string("TMOG_OUTFIT_DEL"), &HandleOutfitDelete);
        sAddonComm->Register(std::string("TMOG_OUTFIT_BUY"), &HandleOutfitBuy);
        sAddonComm->Register(std::string("TMOG_OUTFIT_SIT"), &HandleOutfitSituations);
        sAddonComm->Register(std::string("TMOG_CSETS_GET"), &HandleCustomSetsGet);
        sAddonComm->Register(std::string("TMOG_CSET_SAVE"), &HandleCustomSetSave);
        sAddonComm->Register(std::string("TMOG_CSET_DEL"), &HandleCustomSetDelete);
    }

    void OnLogin(Player* player, bool /*firstLogin*/) override
    {
        LoadOutfits(player);
    }

    void OnLogout(Player* player) override
    {
        outfitsByPlayer.erase(player->GetGUID().GetCounter());
    }
};

void AddSC_transmog_outfits()
{
    new transmog_outfits_world();
    new transmog_outfits_player();
}
