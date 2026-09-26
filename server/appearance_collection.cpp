/*
 * Appearance collection (retail "Appearances" / Wardrobe) for 3.3.5.
 *
 * 3.3.5 has no appearance ids: an appearance = item_template.displayid inside one
 * category (slot or weapon type). Every item with the same displayid shows the same look.
 *
 * Collected items are stored account-wide in characters.account_appearances (itemId).
 * An item is collected when the character equips it, or holds it soulbound
 * (loot / quest reward / crafting / bags scan on login and on journal requests).
 *
 * Item data is read straight from item_template (+ item_template_locale ruRU names),
 * so it does not depend on ItemTemplate field names of the core fork.
 *
 * AddonComm opcodes (names, nothing to add to AddonComm.h / Server.lua):
 *   "APPEAR_PAGE"    C: category : classId(0 = all) : flags(1 collected, 2 not collected) : page : search
 *                    S: category : page : numPages : collectedCount : totalCount : "displayId/itemId/c,..."
 *   "APPEAR_SOURCES" C: category : displayId
 *                    S: category : displayId : "itemId/c,..."
 *   "APPEAR_ADDED"   S: itemId   (a new appearance was collected)
 *
 * Categories (same numbers in Collections\Wardrobe\Blizzard_Wardrobe.lua):
 *   1 head, 2 shoulder, 3 back, 4 chest, 5 shirt, 6 tabard, 7 wrist, 8 hands, 9 waist, 10 legs, 11 feet,
 *   20 + weapon subclass (axe 20, axe2 21, bow 22, gun 23, mace 24, mace2 25, polearm 26, sword 27,
 *   sword2 28, staff 30, fist 33, dagger 35, thrown 36, crossbow 38, wand 39), 40 shield, 41 held in off-hand.
 *
 * Setup: sql/characters_account_appearances.sql, register AddSC_appearance_collection().
 */

#include "ScriptMgr.h"
#include "AddonComm\AddonComm.h"
#include "Bag.h"
#include "DatabaseEnv.h"
#include "Item.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "Util.h"
#include "WorldSession.h"
#include "Timer.h"

#include <algorithm>
#include <map>
#include <set>
#include <sstream>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace
{
    constexpr uint32 PAGE_SIZE = 18;
    constexpr uint32 MAX_SOURCES = 30;
    constexpr uint32 SCAN_INTERVAL_MS = 5000;

    constexpr uint32 C_WARRIOR = 1 << 0, C_PALADIN = 1 << 1, C_HUNTER = 1 << 2, C_ROGUE = 1 << 3, C_PRIEST = 1 << 4,
        C_DEATH_KNIGHT = 1 << 5, C_SHAMAN = 1 << 6, C_MAGE = 1 << 7, C_WARLOCK = 1 << 8, C_DRUID = 1 << 10;
    constexpr uint32 C_ALL = C_WARRIOR | C_PALADIN | C_HUNTER | C_ROGUE | C_PRIEST | C_DEATH_KNIGHT | C_SHAMAN | C_MAGE | C_WARLOCK | C_DRUID;

    struct ItemData
    {
        uint32 itemId = 0;
        uint32 category = 0;
        uint32 displayId = 0;
        uint32 itemLevel = 0;
        std::wstring searchName;   // lower case, for search
    };

    struct Appearance
    {
        uint32 displayId = 0;
        uint32 classMask = 0;
        uint32 itemLevel = 0;      // lowest item level - sort order
        std::vector<uint32> items;
    };

    std::unordered_map<uint32, ItemData> itemData;                      // itemId -> data
    std::map<uint32, std::vector<Appearance>> categories;               // category -> appearances
    std::map<uint32, std::unordered_map<uint32, size_t>> appearanceIndex; // category -> displayId -> index

    std::map<uint32, std::unordered_set<uint32>> accountItems;          // accountId -> collected items
    std::map<ObjectGuid, uint32> lastScan;

    uint32 GetCategory(uint32 itemClass, uint32 subClass, uint32 inventoryType)
    {
        if (itemClass == 4) // armor
        {
            if (subClass == 6)  return 40;                    // shield
            switch (inventoryType)
            {
                case 1:  return 1;   // head
                case 3:  return 2;   // shoulder
                case 16: return 3;   // cloak
                case 5:
                case 20: return 4;   // chest / robe
                case 4:  return 5;   // shirt
                case 19: return 6;   // tabard
                case 9:  return 7;   // wrist
                case 10: return 8;   // hands
                case 6:  return 9;   // waist
                case 7:  return 10;  // legs
                case 8:  return 11;  // feet
                case 23: return 41;  // held in off-hand
                default: return 0;
            }
        }

        if (itemClass == 2) // weapon
        {
            switch (subClass)
            {
                case 0: case 1: case 2: case 3: case 4: case 5: case 6: case 7: case 8:
                case 10: case 13: case 15: case 16: case 18: case 19:
                    return 20 + subClass;
                default:
                    return 0; // misc, exotic, spears, fishing poles
            }
        }
        return 0;
    }

    // who can wear it: main armor type of the class (like retail), weapon skills
    uint32 GetClassMask(uint32 itemClass, uint32 subClass, uint32 category, uint32 allowableClass)
    {
        uint32 mask = C_ALL;
        if (itemClass == 4)
        {
            if (category == 3 || category == 5 || category == 6) // cloak, shirt, tabard
                mask = C_ALL;
            else if (category == 40)
                mask = C_WARRIOR | C_PALADIN | C_SHAMAN;
            else if (category == 41)
                mask = C_PRIEST | C_MAGE | C_WARLOCK | C_DRUID | C_SHAMAN | C_PALADIN;
            else
            {
                switch (subClass)
                {
                    case 1: mask = C_PRIEST | C_MAGE | C_WARLOCK; break;
                    case 2: mask = C_ROGUE | C_DRUID; break;
                    case 3: mask = C_HUNTER | C_SHAMAN; break;
                    case 4: mask = C_WARRIOR | C_PALADIN | C_DEATH_KNIGHT; break;
                    default: mask = C_ALL; break;
                }
            }
        }
        else if (itemClass == 2)
        {
            switch (subClass)
            {
                case 15: mask = C_WARRIOR | C_ROGUE | C_HUNTER | C_SHAMAN | C_PRIEST | C_MAGE | C_WARLOCK | C_DRUID; break;
                case 7:  mask = C_WARRIOR | C_PALADIN | C_ROGUE | C_HUNTER | C_MAGE | C_WARLOCK | C_DEATH_KNIGHT; break;
                case 8:  mask = C_WARRIOR | C_PALADIN | C_HUNTER | C_DEATH_KNIGHT; break;
                case 0:  mask = C_WARRIOR | C_PALADIN | C_ROGUE | C_HUNTER | C_SHAMAN | C_DEATH_KNIGHT; break;
                case 1:  mask = C_WARRIOR | C_PALADIN | C_HUNTER | C_SHAMAN | C_DEATH_KNIGHT; break;
                case 4:  mask = C_WARRIOR | C_PALADIN | C_ROGUE | C_SHAMAN | C_PRIEST | C_DRUID | C_DEATH_KNIGHT; break;
                case 5:  mask = C_WARRIOR | C_PALADIN | C_SHAMAN | C_DRUID | C_DEATH_KNIGHT; break;
                case 6:  mask = C_WARRIOR | C_PALADIN | C_HUNTER | C_DRUID | C_DEATH_KNIGHT; break;
                case 13: mask = C_WARRIOR | C_ROGUE | C_HUNTER | C_SHAMAN | C_DRUID; break;
                case 10: mask = C_WARRIOR | C_HUNTER | C_SHAMAN | C_PRIEST | C_MAGE | C_WARLOCK | C_DRUID; break;
                case 19: mask = C_PRIEST | C_MAGE | C_WARLOCK; break;
                case 2: case 3: case 18: case 16: mask = C_WARRIOR | C_ROGUE | C_HUNTER; break;
                default: mask = C_ALL; break;
            }
        }

        uint32 allowed = allowableClass & C_ALL;
        if (allowed && allowed != C_ALL)
            mask &= allowed;
        return mask;
    }

    void LoadAppearances()
    {
        itemData.clear();
        categories.clear();
        appearanceIndex.clear();

        std::unordered_map<uint32, std::string> localeNames;
        if (QueryResult result = WorldDatabase.Query("SELECT ID, Name FROM item_template_locale WHERE locale = 'ruRU'"))
        {
            do
            {
                Field* fields = result->Fetch();
                localeNames[fields[0].GetUInt32()] = fields[1].GetString();
            } while (result->NextRow());
        }

        QueryResult result = WorldDatabase.Query(
            "SELECT entry, class, subclass, displayid, Quality, InventoryType, AllowableClass, ItemLevel, name "
            "FROM item_template WHERE class IN (2, 4) AND displayid > 0 AND Quality > 0 ORDER BY ItemLevel, entry");
        if (!result)
        {
            TC_LOG_ERROR("server.loading", "appearance_collection: no items loaded");
            return;
        }

        uint32 count = 0;
        do
        {
            Field* fields = result->Fetch();
            uint32 entry = fields[0].GetUInt32();
            uint32 itemClass = fields[1].GetUInt32();
            uint32 subClass = fields[2].GetUInt32();
            uint32 displayId = fields[3].GetUInt32();
            uint32 inventoryType = fields[5].GetUInt32();
            uint32 allowableClass = uint32(fields[6].GetInt32());
            uint32 itemLevel = fields[7].GetUInt32();
            std::string name = fields[8].GetString();

            if (name.rfind("Test", 0) == 0 || name.rfind("OLD", 0) == 0 || name.rfind("Monster", 0) == 0
                || name.find("Deprecated") != std::string::npos || name.find("DEPRECATED") != std::string::npos)
                continue;

            uint32 category = GetCategory(itemClass, subClass, inventoryType);
            if (!category)
                continue;

            auto localeItr = localeNames.find(entry);
            if (localeItr != localeNames.end() && !localeItr->second.empty())
                name = localeItr->second;

            ItemData& data = itemData[entry];
            data.itemId = entry;
            data.category = category;
            data.displayId = displayId;
            data.itemLevel = itemLevel;
            if (Utf8toWStr(name, data.searchName))
                wstrToLower(data.searchName);

            auto& index = appearanceIndex[category];
            auto& list = categories[category];
            auto itr = index.find(displayId);
            if (itr == index.end())
            {
                index[displayId] = list.size();
                Appearance appearance;
                appearance.displayId = displayId;
                appearance.itemLevel = itemLevel;
                list.push_back(appearance);
                itr = index.find(displayId);
            }

            Appearance& appearance = list[itr->second];
            appearance.items.push_back(entry);
            appearance.classMask |= GetClassMask(itemClass, subClass, category, allowableClass);
            ++count;
        } while (result->NextRow());

        TC_LOG_INFO("server.loading", ">> appearance_collection: %u items in %u categories", count, uint32(categories.size()));
    }

    std::unordered_set<uint32>& GetAccountItems(Player* player)
    {
        return accountItems[player->GetSession()->GetAccountId()];
    }

    void LoadAccount(Player* player)
    {
        uint32 accountId = player->GetSession()->GetAccountId();
        std::unordered_set<uint32>& items = accountItems[accountId];
        items.clear();

        if (QueryResult result = CharacterDatabase.PQuery("SELECT itemId FROM account_appearances WHERE accountId = {}", accountId))
        {
            do
            {
                items.insert(result->Fetch()[0].GetUInt32());
            } while (result->NextRow());
        }
    }

    void CollectItem(Player* player, uint32 itemId, bool notify)
    {
        if (!itemData.count(itemId))
            return;

        if (!GetAccountItems(player).insert(itemId).second)
            return;

        CharacterDatabase.PExecute("INSERT IGNORE INTO account_appearances (accountId, itemId) VALUES ({}, {})",
            player->GetSession()->GetAccountId(), itemId);

        if (notify)
            sAddonComm->Send(player, "APPEAR_ADDED", itemId);
    }

    // equipped items always count; items in the bags - only soulbound ones
    void ScanInventory(Player* player, bool notify)
    {
        for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
            if (Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
                CollectItem(player, item->GetEntry(), notify);

        for (uint8 slot = INVENTORY_SLOT_ITEM_START; slot < INVENTORY_SLOT_ITEM_END; ++slot)
            if (Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
                if (item->IsSoulBound())
                    CollectItem(player, item->GetEntry(), notify);

        for (uint8 bagSlot = INVENTORY_SLOT_BAG_START; bagSlot < INVENTORY_SLOT_BAG_END; ++bagSlot)
            if (Bag* bag = player->GetBagByPos(bagSlot))
                for (uint32 i = 0; i < bag->GetBagSize(); ++i)
                    if (Item* item = bag->GetItemByPos(uint8(i)))
                        if (item->IsSoulBound())
                            CollectItem(player, item->GetEntry(), notify);
    }

    void ScanIfNeeded(Player* player)
    {
        uint32 now = getMSTime();
        uint32& last = lastScan[player->GetGUID()];
        if (!last || getMSTimeDiff(last, now) >= SCAN_INTERVAL_MS)
        {
            last = now;
            ScanInventory(player, true);
        }
    }

    bool IsAppearanceCollected(Appearance const& appearance, std::unordered_set<uint32> const& owned, uint32* collectedItem = nullptr)
    {
        for (uint32 itemId : appearance.items)
            if (owned.count(itemId))
            {
                if (collectedItem)
                    *collectedItem = itemId;
                return true;
            }
        return false;
    }

    bool MatchesSearch(Appearance const& appearance, std::wstring const& search)
    {
        if (search.empty())
            return true;
        for (uint32 itemId : appearance.items)
        {
            auto itr = itemData.find(itemId);
            if (itr != itemData.end() && itr->second.searchName.find(search) != std::wstring::npos)
                return true;
        }
        return false;
    }

    // C: category : classId : flags : page : search
    void HandlePage(Player* player, std::vector<std::string> const& args)
    {
        if (args.size() < 4)
            return;

        uint32 category = CommToUInt32(args[0]);
        uint32 classId = CommToUInt32(args[1]);
        uint32 flags = CommToUInt32(args[2], 3);
        uint32 page = std::max<uint32>(1, CommToUInt32(args[3], 1));
        std::wstring search;
        if (args.size() > 4 && !args[4].empty() && Utf8toWStr(args[4], search))
            wstrToLower(search);

        ScanIfNeeded(player);

        auto catItr = categories.find(category);
        std::unordered_set<uint32> const& owned = GetAccountItems(player);
        uint32 classBit = (classId >= 1 && classId <= 11) ? (1u << (classId - 1)) : 0;

        // collected first, then by item level (like retail's ui order)
        std::vector<std::pair<Appearance const*, uint32>> visible;   // appearance, collected item (0 = no)
        uint32 total = 0, collectedCount = 0;
        if (catItr != categories.end())
        {
            for (Appearance const& appearance : catItr->second)
            {
                if (classBit && !(appearance.classMask & classBit))
                    continue;

                uint32 collectedItem = 0;
                bool collected = IsAppearanceCollected(appearance, owned, &collectedItem);
                ++total;
                if (collected)
                    ++collectedCount;

                if ((collected && !(flags & 1)) || (!collected && !(flags & 2)))
                    continue;
                if (!MatchesSearch(appearance, search))
                    continue;

                visible.emplace_back(&appearance, collectedItem);
            }
        }

        std::stable_sort(visible.begin(), visible.end(), [](auto const& a, auto const& b)
        {
            if ((a.second != 0) != (b.second != 0))
                return a.second != 0;
            return a.first->itemLevel < b.first->itemLevel;
        });

        uint32 numPages = std::max<uint32>(1, uint32((visible.size() + PAGE_SIZE - 1) / PAGE_SIZE));
        page = std::min(page, numPages);

        std::ostringstream entries;
        for (size_t i = (page - 1) * PAGE_SIZE; i < visible.size() && i < page * PAGE_SIZE; ++i)
        {
            Appearance const* appearance = visible[i].first;
            uint32 itemId = visible[i].second ? visible[i].second : appearance->items.front();
            if (i != (page - 1) * PAGE_SIZE)
                entries << ',';
            entries << appearance->displayId << '/' << itemId << '/' << (visible[i].second ? 1 : 0);
        }

        sAddonComm->Send(player, "APPEAR_PAGE", category, page, numPages, collectedCount, total, entries.str());
    }

    // C: category : displayId
    void HandleSources(Player* player, std::vector<std::string> const& args)
    {
        if (args.size() < 2)
            return;

        uint32 category = CommToUInt32(args[0]);
        uint32 displayId = CommToUInt32(args[1]);

        auto indexItr = appearanceIndex.find(category);
        if (indexItr == appearanceIndex.end())
            return;
        auto itr = indexItr->second.find(displayId);
        if (itr == indexItr->second.end())
            return;

        Appearance const& appearance = categories[category][itr->second];
        std::unordered_set<uint32> const& owned = GetAccountItems(player);

        std::ostringstream list;
        uint32 n = 0;
        for (uint32 itemId : appearance.items)
        {
            if (n)
                list << ',';
            list << itemId << '/' << (owned.count(itemId) ? 1 : 0);
            if (++n >= MAX_SOURCES)
                break;
        }

        sAddonComm->Send(player, "APPEAR_SOURCES", category, displayId, list.str());
    }
}

class appearance_collection_world : public WorldScript
{
public:
    appearance_collection_world() : WorldScript("appearance_collection_world") {}

    void OnStartup() override
    {
        LoadAppearances();
    }
};

class appearance_collection_player : public PlayerScript
{
public:
    appearance_collection_player() : PlayerScript("appearance_collection_player")
    {
        sAddonComm->Register(std::string("APPEAR_PAGE"), &HandlePage);
        sAddonComm->Register(std::string("APPEAR_SOURCES"), &HandleSources);
    }

    void OnLogin(Player* player, bool /*firstLogin*/) override
    {
        LoadAccount(player);
        ScanInventory(player, false);
    }

    void OnLogout(Player* player) override
    {
        lastScan.erase(player->GetGUID());
    }

    void OnLootItem(Player* player, Item* item, uint32 /*count*/, ObjectGuid /*lootGuid*/) override
    {
        if (item && item->IsSoulBound())
            CollectItem(player, item->GetEntry(), true);
    }

    void OnCreateItem(Player* player, Item* item, uint32 /*count*/) override
    {
        if (item && item->IsSoulBound())
            CollectItem(player, item->GetEntry(), true);
    }

    void OnQuestRewardItem(Player* player, Item* item, uint32 /*count*/) override
    {
        if (item && item->IsSoulBound())
            CollectItem(player, item->GetEntry(), true);
    }
};

void AddSC_appearance_collection()
{
    new appearance_collection_world();
    new appearance_collection_player();
}
