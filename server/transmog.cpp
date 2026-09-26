/*
 * Transmogrification (retail TransmogrificationHandler / TransmogMgr) for 3.3.5.
 *
 * Retail keeps the appearance on the item (ITEM_MODIFIER_TRANSMOG_APPEARANCE_*); 3.3.5 items have no
 * modifiers, so the appearance is stored per item guid in characters.character_transmog and applied
 * through Player::s_visibleItemHook (core patch: Player::SetVisibleItemSlot, see core/Player_transmog.patch).
 * The look follows the item (unequip / bank / re-equip) and is ignored once the item changes owner.
 *
 * Validation order is the retail one (HandleTransmogrifyItems): everything is checked first,
 * then money is taken, then all slots are applied - on any error nothing changes.
 *   - slot is a visible equipment slot and holds an item
 *   - no legendary items (retail ERR_TRANSMOGRIFY_LEGENDARY)
 *   - CanTransmogrifyItemWithItem: same class, armor subclass, weapon type, slot group
 *   - player->CanUseItem(appearance)                                 (retail: CanUseItem)
 *   - appearance collected on the account (account_appearances, same displayid + compatible type)
 *   - cost = sell price of the transmogrified item (min 1 silver), reset is free
 *
 * AddonComm opcodes (client: Transmog\Blizzard_Transmog.lua):
 *   "TMOG_GET_STATE"                         -> "TMOG_STATE"  : "slot/itemId,..."
 *   "TMOG_APPLY" : "slot/itemId,..." (0 = restore) -> "TMOG_RESULT" : ok(1/0) : error : errorItem, then "TMOG_STATE"
 *   "TMOG_OPEN" / "TMOG_CLOSE"               server opens / closes the window (npc_transmogrifier)
 *
 * Setup: sql/characters_transmog.sql, core/Player_transmog.patch, register AddSC_transmog().
 * NPC: creature_template.ScriptName = 'npc_transmogrifier', npcflag 1 (gossip).
 */

#include "transmog.h"
#include "ScriptMgr.h"
#include "Custom\AddonComm\AddonComm.h"
#include "Creature.h"
#include "DatabaseEnv.h"
#include "Item.h"
#include "Log.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "ScriptedCreature.h"
#include "ScriptedGossip.h"
#include "StringFormat.h"
#include "WorldSession.h"

#include <algorithm>
#include <sstream>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace
{
    // false: the window works anywhere (/transmog); true: only next to npc_transmogrifier (like retail)
    constexpr bool REQUIRE_NPC = false;
    constexpr uint32 MIN_COST = 100;   // 1 silver

    struct TransmogData
    {
        ObjectGuid::LowType Owner = 0;
        uint32 FakeEntry = 0;
        uint32 Illusion = 0;   // SpellItemEnchantment id (PLAYER_VISIBLE_ITEM_n_ENCHANTMENT), 0 = none
    };

    std::unordered_map<uint32, Transmog::ItemData> items;                  // item_template (armor, weapons)
    std::unordered_map<ObjectGuid::LowType, TransmogData> transmogs;      // item guid -> transmog
    std::unordered_map<ObjectGuid, ObjectGuid> openedAt;                  // player -> transmogrifier npc

    // retail IsValidTransmogOutfitSlotForItem: inventory types that share a slot
    uint8 SlotGroup(uint8 inventoryType)
    {
        switch (inventoryType)
        {
            case INVTYPE_ROBE:
                return INVTYPE_CHEST;
            case INVTYPE_WEAPONMAINHAND:
            case INVTYPE_WEAPONOFFHAND:
                return INVTYPE_WEAPON;
            case INVTYPE_RANGEDRIGHT:
            case INVTYPE_THROWN:
                return INVTYPE_RANGED;
            default:
                return inventoryType;
        }
    }

    bool IsBowGunCrossbow(uint8 subClass)
    {
        return subClass == ITEM_SUBCLASS_WEAPON_BOW || subClass == ITEM_SUBCLASS_WEAPON_GUN || subClass == ITEM_SUBCLASS_WEAPON_CROSSBOW;
    }

    // the transmogrified look of an equipped item (Player::s_visibleItemHook)
    void VisibleItemHook(Player const* player, Item const* item, uint32& entry, uint32& enchant)
    {
        auto itr = transmogs.find(item->GetGUID().GetCounter());
        if (itr == transmogs.end() || itr->second.Owner != player->GetGUID().GetCounter())
            return;
        if (itr->second.FakeEntry)
            entry = itr->second.FakeEntry;
        if (itr->second.Illusion)
            enchant = itr->second.Illusion;
    }

    void RefreshVisibleSlots(Player* player)
    {
        for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
            if (Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
                player->SetVisibleItemSlot(slot, item);
    }

    void LoadPlayer(Player* player)
    {
        ObjectGuid::LowType owner = player->GetGUID().GetCounter();
        if (QueryResult result = CharacterDatabase.PQuery("SELECT item_guid, fake_entry, illusion FROM character_transmog WHERE owner = {}", owner))
        {
            do
            {
                Field* fields = result->Fetch();
                TransmogData& data = transmogs[fields[0].GetUInt32()];
                data.Owner = owner;
                data.FakeEntry = fields[1].GetUInt32();
                data.Illusion = fields[2].GetUInt32();
            } while (result->NextRow());
        }
        RefreshVisibleSlots(player);
    }

    void UnloadPlayer(Player* player)
    {
        ObjectGuid::LowType owner = player->GetGUID().GetCounter();
        for (auto itr = transmogs.begin(); itr != transmogs.end();)
        {
            if (itr->second.Owner == owner)
                itr = transmogs.erase(itr);
            else
                ++itr;
        }
        openedAt.erase(player->GetGUID());
    }

    bool CanInteract(Player* player)
    {
        if (!REQUIRE_NPC)
            return true;
        auto itr = openedAt.find(player->GetGUID());
        return itr != openedAt.end() && player->GetNPCIfCanInteractWith(itr->second, UNIT_NPC_FLAG_GOSSIP);
    }

    Transmog::ApplyResult Fail(char const* error, uint32 item = 0)
    {
        Transmog::ApplyResult result;
        result.Error = error;
        result.ErrorItem = item;
        return result;
    }

    void HandleGetState(Player* player, std::vector<std::string> const& /*args*/)
    {
        Transmog::SendState(player);
    }

    void HandleApply(Player* player, std::vector<std::string> const& args)
    {
        if (!CanInteract(player))
        {
            Transmog::SendResult(player, Fail("TRANSMOG_ERR_NEED_NPC"));
            sAddonComm->Send(player, "TMOG_CLOSE");
            return;
        }

        Transmog::ApplyResult result = Transmog::ApplyLooks(player, Transmog::ParseSlots(args.empty() ? std::string() : args[0]), true, false);
        Transmog::SendResult(player, result);
        if (result.Ok)
            Transmog::SendState(player);
    }
}

namespace Transmog
{
    void Load()
    {
        items.clear();
        // CAST: every column comes as BIGINT, so the reading does not depend on the column types of the fork
        QueryResult result = WorldDatabase.Query("SELECT CAST(entry AS SIGNED), CAST(class AS SIGNED), CAST(subclass AS SIGNED), CAST(InventoryType AS SIGNED), "
            "CAST(displayid AS SIGNED), CAST(SellPrice AS SIGNED), CAST(Quality AS SIGNED), CAST(AllowableClass AS SIGNED), CAST(itemset AS SIGNED) "
            "FROM item_template WHERE class IN (2, 4)");
        if (!result)
            return;
        do
        {
            Field* fields = result->Fetch();
            ItemData& data = items[uint32(fields[0].GetInt64())];
            data.Class = uint8(fields[1].GetInt64());
            data.SubClass = uint8(fields[2].GetInt64());
            data.InventoryType = uint8(fields[3].GetInt64());
            data.DisplayId = uint32(fields[4].GetInt64());
            data.SellPrice = uint32(std::max<int64>(0, fields[5].GetInt64()));
            data.Quality = uint8(fields[6].GetInt64());
            data.AllowableClass = int32(fields[7].GetInt64());
            data.ItemSet = uint32(fields[8].GetInt64());
        } while (result->NextRow());
        TC_LOG_INFO("server.loading", ">> transmog: {} items", uint32(items.size()));
        if (ItemData const* sample = GetItemData(2105))   // пример: Thug Shirt, должен быть class 4 inv 4
            TC_LOG_INFO("server.loading", ">> transmog: item 2105 class {} sub {} inv {} display {}",
                uint32(sample->Class), uint32(sample->SubClass), uint32(sample->InventoryType), sample->DisplayId);
    }

    ItemData const* GetItemData(uint32 entry)
    {
        auto itr = items.find(entry);
        return itr != items.end() ? &itr->second : nullptr;
    }

    std::unordered_map<uint32, ItemData> const& GetAllItems()
    {
        return items;
    }

    // visible equipment slots (neck, rings, trinkets have no look)
    bool IsTransmogSlot(uint8 slot)
    {
        switch (slot)
        {
            case EQUIPMENT_SLOT_HEAD: case EQUIPMENT_SLOT_SHOULDERS: case EQUIPMENT_SLOT_BODY: case EQUIPMENT_SLOT_CHEST:
            case EQUIPMENT_SLOT_WAIST: case EQUIPMENT_SLOT_LEGS: case EQUIPMENT_SLOT_FEET: case EQUIPMENT_SLOT_WRISTS:
            case EQUIPMENT_SLOT_HANDS: case EQUIPMENT_SLOT_BACK: case EQUIPMENT_SLOT_MAINHAND: case EQUIPMENT_SLOT_OFFHAND:
            case EQUIPMENT_SLOT_RANGED: case EQUIPMENT_SLOT_TABARD:
                return true;
            default:
                return false;
        }
    }

    // retail Item::CanTransmogrifyItemWithItem, rules of 3.3.5 item types
    bool CanTransmogrifyItemWithItem(ItemData const& target, ItemData const& source)
    {
        if (target.Class != source.Class || SlotGroup(target.InventoryType) != SlotGroup(source.InventoryType))
            return false;

        if (target.Class == ITEM_CLASS_ARMOR)
        {
            switch (target.InventoryType)
            {
                case INVTYPE_CLOAK: case INVTYPE_BODY: case INVTYPE_TABARD:
                    return true;   // no armor type
                default:
                    return target.SubClass == source.SubClass;
            }
        }

        if (target.Class == ITEM_CLASS_WEAPON)
            return target.SubClass == source.SubClass || (IsBowGunCrossbow(target.SubClass) && IsBowGunCrossbow(source.SubClass));

        return false;
    }

    std::unordered_set<uint32> LoadCollected(Player* player)
    {
        std::unordered_set<uint32> collected;
        if (QueryResult result = CharacterDatabase.PQuery("SELECT itemId FROM account_appearances WHERE accountId = {}", player->GetSession()->GetAccountId()))
        {
            do
            {
                collected.insert(result->Fetch()[0].GetUInt32());
            } while (result->NextRow());
        }
        return collected;
    }

    bool IsAppearanceCollected(std::unordered_set<uint32> const& collected, ItemData const& target, uint32 itemId)
    {
        ItemData const* source = GetItemData(itemId);
        if (!source)
            return false;
        if (collected.count(itemId))
            return true;
        for (uint32 collectedId : collected)
        {
            ItemData const* other = GetItemData(collectedId);
            if (other && other->DisplayId == source->DisplayId && CanTransmogrifyItemWithItem(target, *other))
                return true;
        }
        return false;
    }

    bool IsAppearanceCollected(std::unordered_set<uint32> const& collected, uint32 itemId)
    {
        ItemData const* source = GetItemData(itemId);
        return source && IsAppearanceCollected(collected, *source, itemId);
    }

    SlotList ParseSlots(std::string const& text)
    {
        SlotList slots;
        std::istringstream stream(text);
        std::string token;
        while (std::getline(stream, token, ','))
        {
            size_t sep = token.find('/');
            if (sep == std::string::npos)
                continue;
            uint32 slot = CommToUInt32(token.substr(0, sep), EQUIPMENT_SLOT_END);
            uint32 itemId = CommToUInt32(token.substr(sep + 1), 0);
            if (slot < EQUIPMENT_SLOT_END)
                slots.emplace_back(uint8(slot), itemId);
        }
        return slots;
    }

    std::string FormatSlots(SlotList const& slots)
    {
        std::ostringstream text;
        bool first = true;
        for (auto const& [slot, itemId] : slots)
        {
            if (!first)
                text << ',';
            text << uint32(slot) << '/' << itemId;
            first = false;
        }
        return text.str();
    }

    uint64 GetCost(Player* player, SlotList const& looks)
    {
        uint64 cost = 0;
        for (auto const& [slot, itemId] : looks)
        {
            Item* target = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
            if (!target || !itemId || itemId == target->GetEntry())
                continue;
            auto itr = transmogs.find(target->GetGUID().GetCounter());
            if (itr != transmogs.end() && itr->second.Owner == player->GetGUID().GetCounter() && itr->second.FakeEntry == itemId)
                continue;   // already this look
            ItemData const* data = GetItemData(target->GetEntry());
            cost += std::max(data ? data->SellPrice : 0u, MIN_COST);
        }
        return cost;
    }

    ApplyResult ApplyLooks(Player* player, SlotList const& looks, bool charge, bool skipInvalid)
    {
        struct Change
        {
            uint8 Slot;
            Item* Target;
            uint32 FakeEntry;   // 0 = restore
        };
        std::vector<Change> changes;
        std::unordered_set<uint8> seen;
        std::unordered_set<uint32> collected;
        bool collectedLoaded = false;

        for (auto const& [slot, lookEntry] : looks)
        {
            // slot of the transmogrified item
            if (!IsTransmogSlot(slot) || !seen.insert(slot).second)
            {
                if (skipInvalid)
                    continue;
                return Fail("TRANSMOGRIFY_INVALID_DESTINATION");
            }

            // transmogrified item
            Item* target = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
            if (!target)
            {
                if (skipInvalid)
                    continue;
                return Fail("TRANSMOGRIFY_INVALID_NO_ITEM");
            }

            uint32 fakeEntry = lookEntry;
            if (fakeEntry == target->GetEntry())
                fakeEntry = 0;   // 0 cost if reverting look

            if (fakeEntry)
            {
                ItemData const* targetData = GetItemData(target->GetEntry());
                ItemData const* sourceData = GetItemData(fakeEntry);
                ItemTemplate const* sourceTemplate = sObjectMgr->GetItemTemplate(fakeEntry);
                char const* error = nullptr;
                uint32 errorItem = 0;

                if (!targetData)
                    error = "ERR_TRANSMOGRIFY_INVALID_DESTINATION", errorItem = target->GetEntry();
                else if (!sourceData || !sourceTemplate)
                    error = "ERR_TRANSMOGRIFY_INVALID_SOURCE";
                else if (targetData->Quality == ITEM_QUALITY_LEGENDARY || sourceData->Quality == ITEM_QUALITY_LEGENDARY)
                    error = "ERR_TRANSMOGRIFY_LEGENDARY";
                else if (!CanTransmogrifyItemWithItem(*targetData, *sourceData))
                    error = "ERR_TRANSMOGRIFY_MISMATCH";
                else if (player->CanUseItem(sourceTemplate) != EQUIP_ERR_OK)
                    error = "ERR_TRANSMOGRIFY_CANT_EQUIP";
                else
                {
                    if (!collectedLoaded)
                    {
                        collected = LoadCollected(player);
                        collectedLoaded = true;
                    }
                    if (!IsAppearanceCollected(collected, *targetData, fakeEntry))
                        error = "TRANSMOGRIFY_STYLE_UNCOLLECTED";
                }

                if (error)
                {
                    TC_LOG_INFO("scripts", "transmog: {} slot {} item {} (class {} sub {} inv {}) <- look {} (class {} sub {} inv {}): {}",
                        player->GetName(), uint32(slot), target->GetEntry(),
                        targetData ? uint32(targetData->Class) : 999, targetData ? uint32(targetData->SubClass) : 999, targetData ? uint32(targetData->InventoryType) : 999,
                        fakeEntry, sourceData ? uint32(sourceData->Class) : 999, sourceData ? uint32(sourceData->SubClass) : 999, sourceData ? uint32(sourceData->InventoryType) : 999,
                        error);
                    if (skipInvalid)
                        continue;
                    return Fail(error, errorItem);
                }
            }

            changes.push_back({ slot, target, fakeEntry });
        }

        if (changes.empty())
            return skipInvalid ? ApplyResult{ true } : Fail("TRANSMOG_NO_VALID_ITEMS_EQUIPPED");

        if (charge)
        {
            SlotList paid;
            for (Change const& change : changes)
                paid.emplace_back(change.Slot, change.FakeEntry);
            if (uint64 cost = GetCost(player, paid))
            {
                if (!player->HasEnoughMoney(cost))
                    return Fail("ERR_TRANSMOG_OUTFIT_SLOT_CANNOT_AFFORD");
                player->ModifyMoney(-int64(cost));
            }
        }

        // Everything is fine, proceed
        ObjectGuid::LowType owner = player->GetGUID().GetCounter();
        CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
        for (Change const& change : changes)
        {
            ObjectGuid::LowType itemGuid = change.Target->GetGUID().GetCounter();
            if (change.FakeEntry)
            {
                TransmogData& data = transmogs[itemGuid];
                if (data.Owner != owner)
                    data = TransmogData();
                data.Owner = owner;
                data.FakeEntry = change.FakeEntry;
                trans->Append(Trinity::StringFormat("REPLACE INTO character_transmog (item_guid, owner, fake_entry, illusion) VALUES ({}, {}, {}, {})",
                    itemGuid, owner, data.FakeEntry, data.Illusion).c_str());

                change.Target->SetNotRefundable(player);
                change.Target->ClearSoulboundTradeable(player);
            }
            else
            {
                transmogs.erase(itemGuid);
                trans->Append(Trinity::StringFormat("DELETE FROM character_transmog WHERE item_guid = {}", itemGuid).c_str());
            }
            change.Target->SetState(ITEM_CHANGED, player);
            player->SetVisibleItemSlot(change.Slot, change.Target);
        }
        CharacterDatabase.CommitTransaction(trans);

        return ApplyResult{ true };
    }

    SlotList GetCurrentLooks(Player* player)
    {
        SlotList looks;
        for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
        {
            Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
            if (!item)
                continue;
            auto itr = transmogs.find(item->GetGUID().GetCounter());
            if (itr == transmogs.end() || itr->second.Owner != player->GetGUID().GetCounter() || !itr->second.FakeEntry)
                continue;
            looks.emplace_back(slot, itr->second.FakeEntry);
        }
        return looks;
    }

    void SendState(Player* player)
    {
        sAddonComm->Send(player, "TMOG_STATE", FormatSlots(GetCurrentLooks(player)));
    }

    void SendResult(Player* player, ApplyResult const& result)
    {
        sAddonComm->Send(player, "TMOG_RESULT", result.Ok ? 1 : 0, result.Error, result.ErrorItem);
    }

    // names go through AddonComm (':' separates arguments) and chat links ('|')
    std::string SanitizeName(std::string name, size_t maxBytes)
    {
        name.erase(std::remove_if(name.begin(), name.end(), [](char c) { return c == ':' || c == '|' || c == ',' || c == '/' || c == '\\' || c == '\'' || c == '"' || c == '\n' || c == '\r'; }), name.end());
        if (name.size() > maxBytes)
        {
            name.resize(maxBytes);
            while (!name.empty() && (uint8(name.back()) & 0xC0) == 0x80)   // cut UTF-8 continuation bytes
                name.pop_back();
            if (!name.empty() && (uint8(name.back()) & 0x80))
                name.pop_back();
        }
        return name;
    }
}

class transmog_world : public WorldScript
{
public:
    transmog_world() : WorldScript("transmog_world") { }

    void OnStartup() override
    {
        Transmog::Load();
        // looks of deleted items
        CharacterDatabase.Execute("DELETE FROM character_transmog WHERE item_guid NOT IN (SELECT guid FROM item_instance)");
        Player::s_visibleItemHook = &VisibleItemHook;
    }
};

class transmog_player : public PlayerScript
{
public:
    transmog_player() : PlayerScript("transmog_player")
    {
        sAddonComm->Register(std::string("TMOG_GET_STATE"), &HandleGetState);
        sAddonComm->Register(std::string("TMOG_APPLY"), &HandleApply);
    }

    void OnLogin(Player* player, bool /*firstLogin*/) override
    {
        LoadPlayer(player);
    }

    void OnLogout(Player* player) override
    {
        UnloadPlayer(player);
    }
};

// retail: UNIT_NPC_FLAG_TRANSMOGRIFIER + SendOpenTransmogrifier
struct npc_transmogrifier : public ScriptedAI
{
    npc_transmogrifier(Creature* creature) : ScriptedAI(creature) { }

    bool OnGossipHello(Player* player) override
    {
        TC_LOG_INFO("scripts", "npc_transmogrifier: {} opens transmogrification", player->GetName());
        CloseGossipMenuFor(player);
        openedAt[player->GetGUID()] = me->GetGUID();
        sAddonComm->Send(player, "TMOG_OPEN");
        return true;
    }
};

void AddSC_transmog()
{
    TC_LOG_INFO("server.loading", ">> Loaded transmog scripts (npc_transmogrifier)");
    new transmog_world();
    new transmog_player();
    RegisterCreatureAI(npc_transmogrifier);
}
