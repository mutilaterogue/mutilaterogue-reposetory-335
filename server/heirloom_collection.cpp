/*
 * Heirloom collection for 3.3.5 (modeled after retail CollectionMgr heirlooms).
 *
 * Account-wide list of learned heirlooms in characters.account_heirlooms.
 * An heirloom is learned when the player gets it (loot, quest reward, crafting, vendor -
 * vendor purchases are picked up by the inventory scan on login and on journal request).
 * From the journal the player can create a learned heirloom in the bags.
 *
 * AddonComm opcodes (add to AddonComm.h):
 *   CircleCMSG: CMSG_CIRCLE_REQUEST_HEIRLOOMS = 3, CMSG_CIRCLE_CREATE_HEIRLOOM = 4
 *   CircleSMSG: SMSG_CIRCLE_HEIRLOOM_LIST = 3,     SMSG_CIRCLE_HEIRLOOM_ADDED = 4
 *
 * SMSG_CIRCLE_HEIRLOOM_LIST : "itemId/classMask,itemId/classMask,..." : "ownedItemId,ownedItemId,..."
 *   classMask = item_template.AllowableClass (0 = all classes)
 * SMSG_CIRCLE_HEIRLOOM_ADDED: itemId
 *
 * Setup: characters DB -> account_heirlooms.sql, register AddSC_heirloom_collection().
 */

#include "ScriptMgr.h"
#include "AddonComm\AddonComm.h"
#include "DatabaseEnv.h"
#include "Item.h"
#include "ItemTemplate.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "WorldSession.h"
#include "Timer.h"

#include <map>
#include <set>
#include <sstream>
#include <vector>

namespace
{
    // All heirlooms: weapons and armor with heirloom quality from item_template.
    std::vector<uint32> heirloomItems;
    std::set<uint32> heirloomSet;
    std::string heirloomListText;   // "itemId/classMask,..." - built once

    // player -> time of the last created heirloom (anti-spam, matches the client "cast")
    constexpr uint32 CREATE_COOLDOWN_MS = 1500;
    std::map<ObjectGuid, uint32> lastCreate;

    // accountId -> learned heirlooms (itemId -> flags)
    std::map<uint32, std::map<uint32, uint32>> accountHeirlooms;

    constexpr uint32 C_WARRIOR = 1 << (CLASS_WARRIOR - 1);
    constexpr uint32 C_PALADIN = 1 << (CLASS_PALADIN - 1);
    constexpr uint32 C_HUNTER = 1 << (CLASS_HUNTER - 1);
    constexpr uint32 C_ROGUE = 1 << (CLASS_ROGUE - 1);
    constexpr uint32 C_PRIEST = 1 << (CLASS_PRIEST - 1);
    constexpr uint32 C_DEATH_KNIGHT = 1 << (CLASS_DEATH_KNIGHT - 1);
    constexpr uint32 C_SHAMAN = 1 << (CLASS_SHAMAN - 1);
    constexpr uint32 C_MAGE = 1 << (CLASS_MAGE - 1);
    constexpr uint32 C_WARLOCK = 1 << (CLASS_WARLOCK - 1);
    constexpr uint32 C_DRUID = 1 << (CLASS_DRUID - 1);

    // Who can use an item by its armor / weapon type (heirloom rules of the journal).
    // 0 = every class (cloaks, rings, necks, trinkets, unknown types).
    uint32 GetClassMaskByType(ItemTemplate const& proto)
    {
        if (proto.Class == ITEM_CLASS_ARMOR)
        {
            if (proto.InventoryType == INVTYPE_CLOAK)
                return 0;

            switch (proto.SubClass)
            {
            case ITEM_SUBCLASS_ARMOR_PLATE:   return C_WARRIOR | C_PALADIN | C_DEATH_KNIGHT;
            case ITEM_SUBCLASS_ARMOR_MAIL:    return C_WARRIOR | C_PALADIN | C_DEATH_KNIGHT | C_HUNTER | C_SHAMAN;
            case ITEM_SUBCLASS_ARMOR_LEATHER: return C_HUNTER | C_ROGUE | C_SHAMAN | C_DRUID;
            case ITEM_SUBCLASS_ARMOR_CLOTH:   return C_PRIEST | C_MAGE | C_WARLOCK;
            case ITEM_SUBCLASS_ARMOR_SHIELD:  return C_WARRIOR | C_PALADIN | C_SHAMAN;
            default:                          return 0;
            }
        }

        if (proto.Class == ITEM_CLASS_WEAPON)
        {
            switch (proto.SubClass)
            {
            case ITEM_SUBCLASS_WEAPON_DAGGER:   return C_WARRIOR | C_ROGUE | C_HUNTER | C_SHAMAN | C_PRIEST | C_MAGE | C_WARLOCK | C_DRUID;
            case ITEM_SUBCLASS_WEAPON_SWORD:    return C_WARRIOR | C_PALADIN | C_ROGUE | C_HUNTER | C_MAGE | C_WARLOCK | C_DEATH_KNIGHT;
            case ITEM_SUBCLASS_WEAPON_SWORD2:   return C_WARRIOR | C_PALADIN | C_HUNTER | C_DEATH_KNIGHT;
            case ITEM_SUBCLASS_WEAPON_AXE:      return C_WARRIOR | C_PALADIN | C_ROGUE | C_HUNTER | C_SHAMAN | C_DEATH_KNIGHT;
            case ITEM_SUBCLASS_WEAPON_AXE2:     return C_WARRIOR | C_PALADIN | C_HUNTER | C_SHAMAN | C_DEATH_KNIGHT;
            case ITEM_SUBCLASS_WEAPON_MACE:     return C_WARRIOR | C_PALADIN | C_ROGUE | C_SHAMAN | C_PRIEST | C_DRUID | C_DEATH_KNIGHT;
            case ITEM_SUBCLASS_WEAPON_MACE2:    return C_WARRIOR | C_PALADIN | C_HUNTER | C_SHAMAN | C_DRUID | C_DEATH_KNIGHT;
            case ITEM_SUBCLASS_WEAPON_POLEARM:  return C_WARRIOR | C_PALADIN | C_HUNTER | C_DRUID | C_DEATH_KNIGHT;
            case ITEM_SUBCLASS_WEAPON_FIST_WEAPON:     return C_WARRIOR | C_ROGUE | C_HUNTER | C_SHAMAN;
            case ITEM_SUBCLASS_WEAPON_STAFF:    return C_SHAMAN | C_PRIEST | C_MAGE | C_WARLOCK | C_DRUID;
            case ITEM_SUBCLASS_WEAPON_WAND:     return C_PRIEST | C_MAGE | C_WARLOCK;
            case ITEM_SUBCLASS_WEAPON_BOW:
            case ITEM_SUBCLASS_WEAPON_GUN:
            case ITEM_SUBCLASS_WEAPON_CROSSBOW:
            case ITEM_SUBCLASS_WEAPON_THROWN:   return C_WARRIOR | C_ROGUE | C_HUNTER;
            default:                            return 0;
            }
        }

        return 0;
    }

    void LoadHeirloomItems()
    {
        heirloomItems.clear();
        heirloomSet.clear();

        std::ostringstream list;
        for (auto const& [entry, proto] : sObjectMgr->GetItemTemplateStore())
        {
            if (proto.Quality != ITEM_QUALITY_HEIRLOOM)
                continue;

            // skip glyphs, consumables and other non-equipment heirloom-quality items
            if (proto.Class != ITEM_CLASS_WEAPON && proto.Class != ITEM_CLASS_ARMOR)
                continue;

            // skip test / deprecated items
            if (proto.Name1.rfind("Test", 0) == 0 || proto.Name1.rfind("OLD", 0) == 0 || proto.Name1.find("Deprecated") != std::string::npos)
                continue;

            // explicit AllowableClass wins; otherwise by armor / weapon type
            uint32 classMask = proto.AllowableClass > 0 ? uint32(proto.AllowableClass) & CLASSMASK_ALL_PLAYABLE : 0;
            if (classMask == CLASSMASK_ALL_PLAYABLE)
                classMask = 0;
            if (!classMask)
                classMask = GetClassMaskByType(proto);

            if (!heirloomItems.empty())
                list << ',';
            list << entry << '/' << classMask;

            heirloomItems.push_back(entry);
            heirloomSet.insert(entry);
        }
        heirloomListText = list.str();
    }

    bool IsHeirloom(uint32 itemId)
    {
        return heirloomSet.count(itemId) != 0;
    }

    std::map<uint32, uint32>& GetAccountHeirlooms(Player* player)
    {
        return accountHeirlooms[player->GetSession()->GetAccountId()];
    }

    void LoadAccount(Player* player)
    {
        uint32 accountId = player->GetSession()->GetAccountId();
        std::map<uint32, uint32>& learned = accountHeirlooms[accountId];
        learned.clear();

        if (QueryResult result = CharacterDatabase.PQuery("SELECT itemId, flags FROM account_heirlooms WHERE accountId = {}", accountId))
        {
            do
            {
                Field* fields = result->Fetch();
                uint32 itemId = fields[0].GetUInt32();
                if (IsHeirloom(itemId))
                    learned[itemId] = fields[1].GetUInt32();
            } while (result->NextRow());
        }
    }

    std::string JoinIds(std::vector<uint32> const& ids)
    {
        std::ostringstream ss;
        for (size_t i = 0; i < ids.size(); ++i)
        {
            if (i)
                ss << ',';
            ss << ids[i];
        }
        return ss.str();
    }

    void SendHeirloomList(Player* player)
    {
        std::vector<uint32> owned;
        for (auto const& [itemId, flags] : GetAccountHeirlooms(player))
            owned.push_back(itemId);

        sAddonComm->Send(player, SMSG_CIRCLE_HEIRLOOM_LIST, heirloomListText, JoinIds(owned));
    }

    void LearnHeirloom(Player* player, uint32 itemId)
    {
        if (!IsHeirloom(itemId))
            return;

        std::map<uint32, uint32>& learned = GetAccountHeirlooms(player);
        if (!learned.emplace(itemId, 0).second)
            return;

        CharacterDatabase.PExecute("INSERT IGNORE INTO account_heirlooms (accountId, itemId, flags) VALUES ({}, {}, 0)",
            player->GetSession()->GetAccountId(), itemId);

        sAddonComm->Send(player, SMSG_CIRCLE_HEIRLOOM_ADDED, itemId);
    }

    // Learns every heirloom the character currently has (bags, equipment, bank).
    void ScanInventory(Player* player)
    {
        for (uint32 itemId : heirloomItems)
            if (player->HasItemCount(itemId, 1, true))
                LearnHeirloom(player, itemId);
    }

    void HandleRequestHeirlooms(Player* player, std::vector<std::string> const& /*args*/)
    {
        ScanInventory(player);
        SendHeirloomList(player);
    }

    void HandleCreateHeirloom(Player* player, std::vector<std::string> const& args)
    {
        if (args.empty())
            return;

        uint32 itemId = CommToUInt32(args[0]);
        if (!IsHeirloom(itemId) || !GetAccountHeirlooms(player).count(itemId))
            return;

        uint32 now = getMSTime();
        uint32& last = lastCreate[player->GetGUID()];
        if (last && getMSTimeDiff(last, now) < CREATE_COOLDOWN_MS)
            return;
        last = now;

        ItemPosCountVec dest;
        InventoryResult msg = player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest, itemId, 1);
        if (msg != EQUIP_ERR_OK)
        {
            player->SendEquipError(msg, nullptr, nullptr, itemId);
            return;
        }

        if (Item* item = player->StoreNewItem(dest, itemId, true))
            player->SendNewItem(item, 1, true, false);
    }
}

class heirloom_collection_world : public WorldScript
{
public:
    heirloom_collection_world() : WorldScript("heirloom_collection_world") {}

    void OnStartup() override
    {
        LoadHeirloomItems();
    }
};

class heirloom_collection_player : public PlayerScript
{
public:
    heirloom_collection_player() : PlayerScript("heirloom_collection_player")
    {
        sAddonComm->Register(CMSG_CIRCLE_REQUEST_HEIRLOOMS, &HandleRequestHeirlooms);
        sAddonComm->Register(CMSG_CIRCLE_CREATE_HEIRLOOM, &HandleCreateHeirloom);
    }

    void OnLogin(Player* player, bool /*firstLogin*/) override
    {
        LoadAccount(player);
        ScanInventory(player);
    }

    void OnLogout(Player* player) override
    {
        lastCreate.erase(player->GetGUID());
    }

    void OnLootItem(Player* player, Item* item, uint32 /*count*/, ObjectGuid /*lootGuid*/) override
    {
        if (item)
            LearnHeirloom(player, item->GetEntry());
    }

    void OnCreateItem(Player* player, Item* item, uint32 /*count*/) override
    {
        if (item)
            LearnHeirloom(player, item->GetEntry());
    }

    void OnQuestRewardItem(Player* player, Item* item, uint32 /*count*/) override
    {
        if (item)
            LearnHeirloom(player, item->GetEntry());
    }
};

void AddSC_heirloom_collection()
{
    new heirloom_collection_world();
    new heirloom_collection_player();
}
