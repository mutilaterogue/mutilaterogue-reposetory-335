/*
 * Toy collection for 3.3.5 (modeled after retail ToyBox).
 *
 * World DB custom_toys: which items are toys (see sql/world_custom_toys.sql).
 * Characters DB account_toys: account-wide learned toys (see sql/characters_account_toys.sql).
 *
 * A toy is learned when the player gets the item (loot, quest reward, crafting, vendor -
 * vendor purchases are picked up by the inventory scan on login and on journal request).
 * The item itself stays in the bags. From the journal a learned toy is used without the item:
 * the server casts the item's "on use" spell and keeps the cooldown (per character).
 *
 * AddonComm opcodes - names, nothing to add to AddonComm.h / Server.lua:
 *   "TOYS_REQUEST"       -> "TOYS_LIST"
 *   "TOYS_USE" : itemId
 *   "TOYS_LIST" : "itemId,itemId,..." : "ownedId/remainingMs/durationMs,..."
 *   "TOYS_ADDED" : itemId
 *   "TOYS_COOLDOWN" : itemId : remainingMs : durationMs
 *
 * Setup: both SQL files, register AddSC_toy_collection() in custom_script_loader.cpp.
 */

#include "ScriptMgr.h"
#include "AddonComm\AddonComm.h"
#include "Chat.h"
#include "DatabaseEnv.h"
#include "Item.h"
#include "ItemTemplate.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "WorldSession.h"
#include "Timer.h"

#include <map>
#include <set>
#include <sstream>
#include <vector>

namespace
{
    struct ToyInfo
    {
        uint32 spellId = 0;
        uint32 cooldownMs = 0;
    };

    std::vector<uint32> toyItems;
    std::map<uint32, ToyInfo> toyInfo;
    std::string toyListText;        // "itemId,itemId,..." - built once

    // accountId -> learned toys
    std::map<uint32, std::set<uint32>> accountToys;

    struct Cooldown
    {
        uint32 start = 0;
        uint32 duration = 0;
    };
    // character -> itemId -> cooldown
    std::map<ObjectGuid, std::map<uint32, Cooldown>> toyCooldowns;

    constexpr uint32 MIN_COOLDOWN_MS = 1500;   // like a global cooldown, anti-spam

    constexpr uint32 ITEM_SPELLS = 5;            // spellid_1..5 in item_template
    constexpr uint32 SPELLTRIGGER_ON_USE = 0;    // ITEM_SPELLTRIGGER_ON_USE

    // fields: [base] spellid, spelltrigger, spellcooldown, spellcategorycooldown for 1..5
    bool GetUseSpell(Field* fields, uint32 base, ToyInfo& info)
    {
        for (uint32 i = 0; i < ITEM_SPELLS; ++i)
        {
            int32 spellId = fields[base + i * 4 + 0].GetInt32();
            uint32 trigger = fields[base + i * 4 + 1].GetUInt32();
            int32 itemCooldown = fields[base + i * 4 + 2].GetInt32();
            int32 categoryCooldown = fields[base + i * 4 + 3].GetInt32();
            if (spellId <= 0 || trigger != SPELLTRIGGER_ON_USE)
                continue;

            SpellInfo const* spellInfo = sSpellMgr->GetSpellInfo(uint32(spellId));
            if (!spellInfo)
                continue;

            int32 cooldown = itemCooldown > 0 ? itemCooldown : categoryCooldown;
            if (cooldown <= 0)
                cooldown = int32(std::max(spellInfo->RecoveryTime, spellInfo->CategoryRecoveryTime));

            info.spellId = uint32(spellId);
            info.cooldownMs = std::max(uint32(cooldown > 0 ? cooldown : 0), MIN_COOLDOWN_MS);
            return true;
        }
        return false;
    }

    void LoadToyItems()
    {
        toyItems.clear();
        toyInfo.clear();

        std::ostringstream list;
        // заклинания берём прямо из item_template: поля ItemTemplate в разных форках называются по-разному
        std::ostringstream query;
        query << "SELECT t.itemId, i.entry";
        for (uint32 n = 1; n <= ITEM_SPELLS; ++n)
            query << ", i.spellid_" << n << ", i.spelltrigger_" << n << ", i.spellcooldown_" << n << ", i.spellcategorycooldown_" << n;
        query << " FROM custom_toys t LEFT JOIN item_template i ON i.entry = t.itemId ORDER BY t.itemId";
        QueryResult result = WorldDatabase.Query(query.str().c_str());
        if (!result)
        {
            TC_LOG_ERROR("server.loading", "toy_collection: world table custom_toys is empty or missing");
            toyListText.clear();
            return;
        }

        do
        {
            Field* fields = result->Fetch();
            uint32 itemId = fields[0].GetUInt32();
            if (fields[1].IsNull() || !sObjectMgr->GetItemTemplate(itemId))
            {
                TC_LOG_ERROR("server.loading", "toy_collection: item %u from custom_toys does not exist, skipped", itemId);
                continue;
            }

            ToyInfo info;
            if (!GetUseSpell(fields, 2, info))
            {
                TC_LOG_ERROR("server.loading", "toy_collection: item %u has no \"on use\" spell, skipped", itemId);
                continue;
            }

            if (!toyItems.empty())
                list << ',';
            list << itemId;

            toyItems.push_back(itemId);
            toyInfo[itemId] = info;
        } while (result->NextRow());

        toyListText = list.str();
        TC_LOG_INFO("server.loading", ">> Loaded %u toys", uint32(toyItems.size()));
    }

    bool IsToy(uint32 itemId)
    {
        return toyInfo.count(itemId) != 0;
    }

    std::set<uint32>& GetAccountToys(Player* player)
    {
        return accountToys[player->GetSession()->GetAccountId()];
    }

    void LoadAccount(Player* player)
    {
        uint32 accountId = player->GetSession()->GetAccountId();
        std::set<uint32>& learned = accountToys[accountId];
        learned.clear();

        if (QueryResult result = CharacterDatabase.PQuery("SELECT itemId FROM account_toys WHERE accountId = {}", accountId))
        {
            do
            {
                uint32 itemId = result->Fetch()[0].GetUInt32();
                if (IsToy(itemId))
                    learned.insert(itemId);
            } while (result->NextRow());
        }
    }

    uint32 GetRemaining(Player* player, uint32 itemId, uint32& duration)
    {
        duration = 0;
        auto charItr = toyCooldowns.find(player->GetGUID());
        if (charItr == toyCooldowns.end())
            return 0;
        auto itr = charItr->second.find(itemId);
        if (itr == charItr->second.end())
            return 0;

        uint32 passed = getMSTimeDiff(itr->second.start, getMSTime());
        if (passed >= itr->second.duration)
        {
            charItr->second.erase(itr);
            return 0;
        }
        duration = itr->second.duration;
        return itr->second.duration - passed;
    }

    void SendToyList(Player* player)
    {
        std::ostringstream owned;
        bool first = true;
        for (uint32 itemId : GetAccountToys(player))
        {
            uint32 duration;
            uint32 remaining = GetRemaining(player, itemId, duration);
            if (!first)
                owned << ',';
            first = false;
            owned << itemId << '/' << remaining << '/' << duration;
        }

        sAddonComm->Send(player, "TOYS_LIST", toyListText, owned.str());
    }

    void LearnToy(Player* player, uint32 itemId)
    {
        if (!IsToy(itemId))
            return;

        if (!GetAccountToys(player).insert(itemId).second)
            return;

        CharacterDatabase.PExecute("INSERT IGNORE INTO account_toys (accountId, itemId) VALUES ({}, {})",
            player->GetSession()->GetAccountId(), itemId);

        sAddonComm->Send(player, "TOYS_ADDED", itemId);
    }

    // Learns every toy the character currently has (bags, equipment, bank).
    void ScanInventory(Player* player)
    {
        for (uint32 itemId : toyItems)
            if (player->HasItemCount(itemId, 1, true))
                LearnToy(player, itemId);
    }

    void HandleRequestToys(Player* player, std::vector<std::string> const& /*args*/)
    {
        ScanInventory(player);
        SendToyList(player);
    }

    void HandleUseToy(Player* player, std::vector<std::string> const& args)
    {
        if (args.empty() || !player->IsAlive())
            return;

        uint32 itemId = CommToUInt32(args[0]);
        auto infoItr = toyInfo.find(itemId);
        if (infoItr == toyInfo.end() || !GetAccountToys(player).count(itemId))
            return;

        uint32 duration;
        if (uint32 remaining = GetRemaining(player, itemId, duration))
        {
            // the client shows "not ready yet" itself
            sAddonComm->Send(player, "TOYS_COOLDOWN", itemId, remaining, duration);
            return;
        }

        SpellInfo const* spellInfo = sSpellMgr->GetSpellInfo(infoItr->second.spellId);
        if (!spellInfo)
            return;

        // spells that need a unit target go to the current target, everything else - to the player
        Unit* target = player;
        if (spellInfo->NeedsExplicitUnitTarget())
        {
            target = player->GetSelectedUnit();
            if (!target)
            {
                ChatHandler(player->GetSession()).SendSysMessage("Нужна цель.");
                return;
            }
        }

        player->CastSpell(target, spellInfo->Id, true);

        Cooldown& cd = toyCooldowns[player->GetGUID()][itemId];
        cd.start = getMSTime();
        cd.duration = infoItr->second.cooldownMs;
        sAddonComm->Send(player, "TOYS_COOLDOWN", itemId, cd.duration, cd.duration);
    }
}

class toy_collection_world : public WorldScript
{
public:
    toy_collection_world() : WorldScript("toy_collection_world") {}

    void OnStartup() override
    {
        LoadToyItems();
    }
};

class toy_collection_player : public PlayerScript
{
public:
    toy_collection_player() : PlayerScript("toy_collection_player")
    {
        sAddonComm->Register("TOYS_REQUEST", &HandleRequestToys);
        sAddonComm->Register("TOYS_USE", &HandleUseToy);
    }

    void OnLogin(Player* player, bool /*firstLogin*/) override
    {
        LoadAccount(player);
        ScanInventory(player);
    }

    void OnLootItem(Player* player, Item* item, uint32 /*count*/, ObjectGuid /*lootGuid*/) override
    {
        if (item)
            LearnToy(player, item->GetEntry());
    }

    void OnCreateItem(Player* player, Item* item, uint32 /*count*/) override
    {
        if (item)
            LearnToy(player, item->GetEntry());
    }

    void OnQuestRewardItem(Player* player, Item* item, uint32 /*count*/) override
    {
        if (item)
            LearnToy(player, item->GetEntry());
    }
};

void AddSC_toy_collection()
{
    new toy_collection_world();
    new toy_collection_player();
}
