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
 * AddonComm opcodes (AddonComm.h):
 *   CMSG_CIRCLE_REQUEST_TOYS = 6       -> SMSG_CIRCLE_TOY_LIST
 *   CMSG_CIRCLE_USE_TOY      = 7 : itemId
 *   SMSG_CIRCLE_TOY_LIST     = 6 : "itemId,itemId,..." : "ownedId/remainingMs/durationMs,..."
 *   SMSG_CIRCLE_TOY_ADDED    = 7 : itemId
 *   SMSG_CIRCLE_TOY_COOLDOWN = 8 : itemId : remainingMs : durationMs
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

    bool GetUseSpell(ItemTemplate const& proto, ToyInfo& info)
    {
        for (uint8 i = 0; i < MAX_ITEM_PROTO_SPELLS; ++i)
        {
            auto const& spell = proto.Spells[i];
            if (spell.SpellId <= 0 || spell.SpellTrigger != ITEM_SPELLTRIGGER_ON_USE)
                continue;

            SpellInfo const* spellInfo = sSpellMgr->GetSpellInfo(uint32(spell.SpellId));
            if (!spellInfo)
                continue;

            int32 cooldown = spell.SpellCooldown > 0 ? spell.SpellCooldown : spell.SpellCategoryCooldown;
            if (cooldown <= 0)
                cooldown = int32(std::max(spellInfo->RecoveryTime, spellInfo->CategoryRecoveryTime));

            info.spellId = uint32(spell.SpellId);
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
        QueryResult result = WorldDatabase.Query("SELECT itemId FROM custom_toys ORDER BY itemId");
        if (!result)
        {
            TC_LOG_ERROR("server.loading", "toy_collection: world table custom_toys is empty or missing");
            toyListText.clear();
            return;
        }

        do
        {
            uint32 itemId = result->Fetch()[0].GetUInt32();
            ItemTemplate const* proto = sObjectMgr->GetItemTemplate(itemId);
            if (!proto)
            {
                TC_LOG_ERROR("server.loading", "toy_collection: item %u from custom_toys does not exist, skipped", itemId);
                continue;
            }

            ToyInfo info;
            if (!GetUseSpell(*proto, info))
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

        sAddonComm->Send(player, SMSG_CIRCLE_TOY_LIST, toyListText, owned.str());
    }

    void LearnToy(Player* player, uint32 itemId)
    {
        if (!IsToy(itemId))
            return;

        if (!GetAccountToys(player).insert(itemId).second)
            return;

        CharacterDatabase.PExecute("INSERT IGNORE INTO account_toys (accountId, itemId) VALUES ({}, {})",
            player->GetSession()->GetAccountId(), itemId);

        sAddonComm->Send(player, SMSG_CIRCLE_TOY_ADDED, itemId);
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
            sAddonComm->Send(player, SMSG_CIRCLE_TOY_COOLDOWN, itemId, remaining, duration);
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
        sAddonComm->Send(player, SMSG_CIRCLE_TOY_COOLDOWN, itemId, cd.duration, cd.duration);
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
        sAddonComm->Register(CMSG_CIRCLE_REQUEST_TOYS, &HandleRequestToys);
        sAddonComm->Register(CMSG_CIRCLE_USE_TOY, &HandleUseToy);
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
