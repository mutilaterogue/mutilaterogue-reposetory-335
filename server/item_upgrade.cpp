/*
 * Item upgrades (retail: ItemUpgradeFrame / C_ItemUpgrade, upgrade tracks) for 3.3.5.
 *
 * Every armor / weapon item of rare+ quality belongs to an upgrade track by its template item level
 * (world.item_upgrade_track: Veteran / Champion / Hero / Myth ...). One upgrade level adds
 * ilvl_per_level item levels through ItemScaling::SetBonus (item_scaling.cpp) and costs cost_count of
 * cost_item (3.3.5 currencies are items) plus cost_money. The level of an item is stored per instance:
 * characters.item_upgrade.
 *
 * AddonComm (client: ItemUpgrade\Blizzard_ItemUpgradeUI.lua), client slots as in transmog tooltips
 * (bag 255 - equipment slot id, 0 - backpack, 1..4 - bags):
 *   server -> "IUPG_OPEN" / "IUPG_CLOSE"                        window at npc_item_upgrade
 *   "IUPG_LIST"               -> "IUPG_ITEMS" : "bag/slot/itemId/track/level/max,..."   upgradeable items (also tooltips)
 *   "IUPG_SET" : bag : slot   -> "IUPG_INFO"  : see SendInfo (empty - no item)
 *   "IUPG_CLEAR"              -> "IUPG_INFO"  (empty)
 *   "IUPG_UPGRADE" : levels   -> "IUPG_RESULT" : ok(1/0) : error (client global string), then "IUPG_INFO", "IUPG_ITEMS"
 *
 * Setup: sql/world_item_upgrade.sql, sql/characters_item_upgrade.sql, AddSC_item_upgrade() in custom_script_loader.cpp.
 * NPC: creature_template.ScriptName = 'npc_item_upgrade', npcflag 1 (gossip).
 */

#include "item_scaling.h"
#include "ScriptMgr.h"
#include "Custom\AddonComm\AddonComm.h"
#include "Bag.h"
#include "Creature.h"
#include "DatabaseEnv.h"
#include "Item.h"
#include "ItemTemplate.h"
#include "Log.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "ScriptedCreature.h"
#include "ScriptedGossip.h"
#include "StringFormat.h"
#include "WorldSession.h"

#include <cmath>
#include <sstream>
#include <unordered_map>
#include <vector>

namespace
{
    // false: the window works anywhere (testing); true: only next to npc_item_upgrade (like retail)
    constexpr bool REQUIRE_NPC = true;

    struct Track
    {
        uint32 Id = 0;
        std::string Name;
        uint32 MinItemLevel = 0;
        uint32 MaxItemLevel = 0;
        uint32 MaxLevel = 0;
        uint32 ItemLevelPerLevel = 0;
        uint32 CostItem = 0;
        uint32 CostCount = 0;
        uint32 CostMoney = 0;
    };

    std::vector<Track> tracks;
    std::unordered_map<uint32, uint32> levels;                // item guid -> upgrade level
    std::unordered_map<ObjectGuid, ObjectGuid> openedAt;      // player -> npc
    std::unordered_map<ObjectGuid, std::pair<uint32, uint32>> selected;   // player -> client bag/slot

    Track const* GetTrack(Item const* item)
    {
        ItemTemplate const* proto = item->GetTemplate();
        if (proto->Class != ITEM_CLASS_ARMOR && proto->Class != ITEM_CLASS_WEAPON)
            return nullptr;
        if (proto->Quality < ITEM_QUALITY_RARE || proto->Quality == ITEM_QUALITY_HEIRLOOM)
            return nullptr;
        for (Track const& track : tracks)
            if (proto->ItemLevel >= track.MinItemLevel && proto->ItemLevel <= track.MaxItemLevel)
                return &track;
        return nullptr;
    }

    uint32 GetLevel(Item const* item)
    {
        auto itr = levels.find(item->GetGUID().GetCounter());
        return itr != levels.end() ? itr->second : 0;
    }

    Item* GetClientItem(Player* player, uint32 bag, uint32 slot)
    {
        if (!slot)
            return nullptr;
        if (bag == 255)
            return slot <= EQUIPMENT_SLOT_END ? player->GetItemByPos(INVENTORY_SLOT_BAG_0, uint8(slot - 1)) : nullptr;
        if (bag == 0)
            return player->GetItemByPos(INVENTORY_SLOT_BAG_0, uint8(INVENTORY_SLOT_ITEM_START + slot - 1));
        if (bag >= 1 && bag <= 4)
            return player->GetItemByPos(uint8(INVENTORY_SLOT_BAG_START + bag - 1), uint8(slot - 1));
        return nullptr;
    }

    bool CanInteract(Player* player)
    {
        if (!REQUIRE_NPC)
            return true;
        auto itr = openedAt.find(player->GetGUID());
        return itr != openedAt.end() && player->GetNPCIfCanInteractWith(itr->second, UNIT_NPC_FLAG_GOSSIP);
    }

    // stats of the item at an item level bonus: "type=value,..." ; armor ; minDamage-maxDamage ; delay
    std::string FormatLevel(ItemTemplate const* proto, uint32 level, uint32 itemLevel, int32 bonus)
    {
        std::ostringstream text;
        text << level << ';' << itemLevel << ';';
        float statScale = ItemScaling::StatScale(bonus);
        bool first = true;
        for (uint32 i = 0; i < proto->StatsCount && i < MAX_ITEM_PROTO_STATS; ++i)
        {
            if (!proto->ItemStat[i].ItemStatValue)
                continue;
            if (!first)
                text << ',';
            text << proto->ItemStat[i].ItemStatType << '=' << int32(std::lround(proto->ItemStat[i].ItemStatValue * statScale));
            first = false;
        }
        float damageScale = ItemScaling::DamageScale(bonus);
        text << ';' << uint32(std::lround(proto->Armor * ItemScaling::ArmorScale(bonus)))
             << ';' << uint32(std::lround(proto->Damage[0].DamageMin * damageScale)) << '-' << uint32(std::lround(proto->Damage[0].DamageMax * damageScale))
             << ';' << proto->Delay;
        return text.str();
    }

    // "IUPG_INFO" : bag : slot : itemId : curr : max : track : minIlvl : maxIlvl : costItem : costCount : costMoney : levels : error
    //   levels - curr..max separated by '#', each "level;itemLevel;stats;armor;damage;delay"
    void SendInfo(Player* player)
    {
        auto sel = selected.find(player->GetGUID());
        Item* item = sel != selected.end() ? GetClientItem(player, sel->second.first, sel->second.second) : nullptr;
        Track const* track = item ? GetTrack(item) : nullptr;
        if (!item)
        {
            selected.erase(player->GetGUID());
            sAddonComm->Send(player, "IUPG_INFO");
            return;
        }

        ItemTemplate const* proto = item->GetTemplate();
        uint32 curr = track ? std::min(GetLevel(item), track->MaxLevel) : 0;
        uint32 max = track ? track->MaxLevel : 0;
        uint32 step = track ? track->ItemLevelPerLevel : 0;
        int32 bonus = ItemScaling::GetBonus(item);
        uint32 itemLevel = ItemScaling::GetItemLevel(item);
        uint32 minItemLevel = itemLevel - curr * step;

        std::ostringstream levelsText;
        for (uint32 level = curr; level <= max || level == curr; ++level)
        {
            if (level != curr)
                levelsText << '#';
            int32 levelBonus = bonus + int32((level - curr) * step);
            levelsText << FormatLevel(proto, level, itemLevel + (level - curr) * step, levelBonus);
            if (level >= max)
                break;
        }

        char const* error = "";
        if (!track)
            error = "ITEM_UPGRADE_NO_TRACK";
        else if (item->GetOwnerGUID() != player->GetGUID())
            error = "ITEM_UPGRADE_NOT_OWNED";

        sAddonComm->Send(player, "IUPG_INFO", sel->second.first, sel->second.second, item->GetEntry(), curr, max,
            track ? track->Name : std::string(), minItemLevel, minItemLevel + max * step,
            track ? track->CostItem : 0, track ? track->CostCount : 0, track ? track->CostMoney : 0,
            levelsText.str(), error);
    }

    void SendItems(Player* player)
    {
        std::ostringstream list;
        bool first = true;
        auto add = [&](uint32 bag, uint32 slot, Item* item)
        {
            if (!item)
                return;
            Track const* track = GetTrack(item);
            if (!track)
                return;
            if (!first)
                list << ',';
            list << bag << '/' << slot << '/' << item->GetEntry() << '/' << track->Id << '/' << GetLevel(item) << '/' << track->MaxLevel;
            first = false;
        };
        for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
            add(255, slot + 1, player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot));
        for (uint8 slot = INVENTORY_SLOT_ITEM_START; slot < INVENTORY_SLOT_ITEM_END; ++slot)
            add(0, slot - INVENTORY_SLOT_ITEM_START + 1, player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot));
        for (uint8 bagSlot = INVENTORY_SLOT_BAG_START; bagSlot < INVENTORY_SLOT_BAG_END; ++bagSlot)
            if (Bag* bag = player->GetBagByPos(bagSlot))
                for (uint32 i = 0; i < bag->GetBagSize(); ++i)
                    add(bagSlot - INVENTORY_SLOT_BAG_START + 1, i + 1, bag->GetItemByPos(uint8(i)));

        // track names for tooltips: "id/name,..."
        std::ostringstream names;
        for (size_t i = 0; i < tracks.size(); ++i)
            names << (i ? "," : "") << tracks[i].Id << '/' << tracks[i].Name;
        sAddonComm->Send(player, "IUPG_ITEMS", list.str(), names.str());
    }

    void SendResult(Player* player, bool ok, char const* error)
    {
        sAddonComm->Send(player, "IUPG_RESULT", ok ? 1 : 0, error);
    }

    void HandleList(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendItems(player);
    }

    void HandleSet(Player* player, std::vector<std::string> const& args)
    {
        if (args.size() < 2)
            return;
        selected[player->GetGUID()] = { CommToUInt32(args[0], 0), CommToUInt32(args[1], 0) };
        SendInfo(player);
    }

    void HandleClear(Player* player, std::vector<std::string> const& /*args*/)
    {
        selected.erase(player->GetGUID());
        SendInfo(player);
    }

    void HandleUpgrade(Player* player, std::vector<std::string> const& args)
    {
        uint32 count = args.empty() ? 1 : std::max<uint32>(1, CommToUInt32(args[0], 1));
        if (!CanInteract(player))
        {
            SendResult(player, false, "ERR_ITEM_UPGRADE_NEED_NPC");
            sAddonComm->Send(player, "IUPG_CLOSE");
            return;
        }
        auto sel = selected.find(player->GetGUID());
        Item* item = sel != selected.end() ? GetClientItem(player, sel->second.first, sel->second.second) : nullptr;
        Track const* track = item ? GetTrack(item) : nullptr;
        if (!item || !track || item->GetOwnerGUID() != player->GetGUID())
            return SendResult(player, false, "ITEM_UPGRADE_NO_TRACK");

        uint32 curr = GetLevel(item);
        if (curr + count > track->MaxLevel)
            return SendResult(player, false, "ITEM_UPGRADE_NO_MORE_UPGRADES");

        uint32 items = track->CostCount * count;
        uint32 money = track->CostMoney * count;
        if (items && !player->HasItemCount(track->CostItem, items))
            return SendResult(player, false, "ITEM_UPGRADE_ERROR_NOT_ENOUGH_CURRENCY_SHORT");
        if (money && !player->HasEnoughMoney(uint64(money)))
            return SendResult(player, false, "ERR_NOT_ENOUGH_MONEY");

        if (items)
            player->DestroyItemCount(track->CostItem, items, true);
        if (money)
            player->ModifyMoney(-int64(money));

        uint32 guid = item->GetGUID().GetCounter();
        levels[guid] = curr + count;
        CharacterDatabase.Execute(Trinity::StringFormat("REPLACE INTO item_upgrade (item_guid, level) VALUES ({}, {})", guid, curr + count).c_str());
        ItemScaling::SetBonus(player, item, ItemScaling::GetBonus(item) + int32(track->ItemLevelPerLevel * count));

        SendResult(player, true, "");
        SendInfo(player);
        SendItems(player);
    }
}

class item_upgrade_world : public WorldScript
{
public:
    item_upgrade_world() : WorldScript("item_upgrade_world") { }

    void OnStartup() override
    {
        tracks.clear();
        if (QueryResult result = WorldDatabase.Query("SELECT CAST(id AS SIGNED), name, CAST(min_item_level AS SIGNED), CAST(max_item_level AS SIGNED), "
            "CAST(max_level AS SIGNED), CAST(ilvl_per_level AS SIGNED), CAST(cost_item AS SIGNED), CAST(cost_count AS SIGNED), CAST(cost_money AS SIGNED) "
            "FROM item_upgrade_track ORDER BY min_item_level"))
        {
            do
            {
                Field* fields = result->Fetch();
                Track& track = tracks.emplace_back();
                track.Id = uint32(fields[0].GetInt64());
                track.Name = fields[1].GetString();
                track.MinItemLevel = uint32(fields[2].GetInt64());
                track.MaxItemLevel = uint32(fields[3].GetInt64());
                track.MaxLevel = uint32(fields[4].GetInt64());
                track.ItemLevelPerLevel = uint32(fields[5].GetInt64());
                track.CostItem = uint32(fields[6].GetInt64());
                track.CostCount = uint32(fields[7].GetInt64());
                track.CostMoney = uint32(fields[8].GetInt64());
            } while (result->NextRow());
        }

        CharacterDatabase.Execute("DELETE FROM item_upgrade WHERE item_guid NOT IN (SELECT guid FROM item_instance)");
        levels.clear();
        if (QueryResult result = CharacterDatabase.Query("SELECT CAST(item_guid AS SIGNED), CAST(level AS SIGNED) FROM item_upgrade"))
        {
            do
            {
                Field* fields = result->Fetch();
                levels[uint32(fields[0].GetInt64())] = uint32(fields[1].GetInt64());
            } while (result->NextRow());
        }
        TC_LOG_INFO("server.loading", ">> item upgrade: {} tracks, {} upgraded items", uint32(tracks.size()), uint32(levels.size()));
    }
};

class item_upgrade_player : public PlayerScript
{
public:
    item_upgrade_player() : PlayerScript("item_upgrade_player")
    {
        sAddonComm->Register(std::string("IUPG_LIST"), &HandleList);
        sAddonComm->Register(std::string("IUPG_SET"), &HandleSet);
        sAddonComm->Register(std::string("IUPG_CLEAR"), &HandleClear);
        sAddonComm->Register(std::string("IUPG_UPGRADE"), &HandleUpgrade);
    }

    void OnLogin(Player* player, bool /*firstLogin*/) override
    {
        SendItems(player);
    }

    void OnLogout(Player* player) override
    {
        openedAt.erase(player->GetGUID());
        selected.erase(player->GetGUID());
    }
};

// retail: UNIT_NPC_FLAG2_ITEM_UPGRADE_MASTER + PlayerInteractionType.ItemUpgrade
struct npc_item_upgrade : public ScriptedAI
{
    npc_item_upgrade(Creature* creature) : ScriptedAI(creature) { }

    bool OnGossipHello(Player* player) override
    {
        CloseGossipMenuFor(player);
        openedAt[player->GetGUID()] = me->GetGUID();
        selected.erase(player->GetGUID());
        sAddonComm->Send(player, "IUPG_OPEN");
        SendItems(player);
        return true;
    }
};

void AddSC_item_upgrade()
{
    new item_upgrade_world();
    new item_upgrade_player();
    RegisterCreatureAI(npc_item_upgrade);
}
