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
 *   - appearance collected on the account (account_appearances, same displayid + compatible type)
 *   - player->CanUseItem(appearance)                                 (retail: CanUseItem)
 *   - CanTransmogrifyItemWithItem: same class, armor subclass, weapon type, slot group
 *   - cost = sell price of the transmogrified item (min 1 silver), reset is free
 *
 * AddonComm opcodes (client: Transmog\Blizzard_Transmog.lua):
 *   "TMOG_GET_STATE"                         -> "TMOG_STATE"  : "slot/itemId,..."
 *   "TMOG_APPLY" : "slot/itemId,..." (0 = restore) -> "TMOG_RESULT" : ok(1/0) : message, then "TMOG_STATE"
 *   "TMOG_OPEN" / "TMOG_CLOSE"               server opens / closes the window (npc_transmogrifier)
 *
 * Setup: sql/characters_transmog.sql, core/Player_transmog.patch, register AddSC_transmog().
 * NPC: creature_template.ScriptName = 'npc_transmogrifier', npcflag 1 (gossip).
 */

#include "ScriptMgr.h"
#include "AddonComm\AddonComm.h"
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

    struct ItemData
    {
        uint8 Class = 0;
        uint8 SubClass = 0;
        uint8 InventoryType = 0;
        uint32 DisplayId = 0;
        uint32 SellPrice = 0;
    };

    struct TransmogData
    {
        ObjectGuid::LowType Owner = 0;
        uint32 FakeEntry = 0;
        uint32 Illusion = 0;   // SpellItemEnchantment id (PLAYER_VISIBLE_ITEM_n_ENCHANTMENT), 0 = none
    };

    std::unordered_map<uint32, ItemData> items;                            // item_template
    std::unordered_map<ObjectGuid::LowType, TransmogData> transmogs;      // item guid -> transmog
    std::unordered_map<ObjectGuid, ObjectGuid> openedAt;                  // player -> transmogrifier npc

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

    ItemData const* GetItemData(uint32 entry)
    {
        auto itr = items.find(entry);
        return itr != items.end() ? &itr->second : nullptr;
    }

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

    void LoadItems()
    {
        items.clear();
        QueryResult result = WorldDatabase.Query("SELECT entry, class, subclass, InventoryType, displayid, SellPrice FROM item_template WHERE class IN (2, 4)");
        if (!result)
            return;
        do
        {
            Field* fields = result->Fetch();
            ItemData& data = items[fields[0].GetUInt32()];
            data.Class = fields[1].GetUInt8();
            data.SubClass = fields[2].GetUInt8();
            data.InventoryType = fields[3].GetUInt8();
            data.DisplayId = fields[4].GetUInt32();
            data.SellPrice = fields[5].GetUInt32();
        } while (result->NextRow());
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

    void SendState(Player* player)
    {
        std::ostringstream list;
        bool first = true;
        for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
        {
            Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
            if (!item)
                continue;
            auto itr = transmogs.find(item->GetGUID().GetCounter());
            if (itr == transmogs.end() || itr->second.Owner != player->GetGUID().GetCounter() || !itr->second.FakeEntry)
                continue;
            if (!first)
                list << ',';
            list << uint32(slot) << '/' << itr->second.FakeEntry;
            first = false;
        }
        sAddonComm->Send(player, "TMOG_STATE", list.str());
    }

    void SendResult(Player* player, bool ok, std::string const& message)
    {
        sAddonComm->Send(player, "TMOG_RESULT", ok ? 1 : 0, message);
    }

    bool CanInteract(Player* player)
    {
        if (!REQUIRE_NPC)
            return true;
        auto itr = openedAt.find(player->GetGUID());
        return itr != openedAt.end() && player->GetNPCIfCanInteractWith(itr->second, UNIT_NPC_FLAG_GOSSIP);
    }

    // appearance collected: any collected item with the same look and a compatible type
    bool HasAppearance(Player* player, ItemData const& target, ItemData const& source)
    {
        QueryResult result = CharacterDatabase.PQuery("SELECT itemId FROM account_appearances WHERE accountId = {}", player->GetSession()->GetAccountId());
        if (!result)
            return false;
        do
        {
            ItemData const* collected = GetItemData(result->Fetch()[0].GetUInt32());
            if (collected && collected->DisplayId == source.DisplayId && CanTransmogrifyItemWithItem(target, *collected))
                return true;
        } while (result->NextRow());
        return false;
    }

    void HandleGetState(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendState(player);
    }

    void HandleApply(Player* player, std::vector<std::string> const& args)
    {
        if (!CanInteract(player))
        {
            SendResult(player, false, "Подойдите к трансмогрификатору.");
            sAddonComm->Send(player, "TMOG_CLOSE");
            return;
        }

        struct Change
        {
            uint8 Slot;
            Item* Target;
            uint32 FakeEntry;   // 0 = restore
        };
        std::vector<Change> changes;
        std::unordered_set<uint8> seen;
        uint64 cost = 0;

        std::string const text = args.empty() ? std::string() : args[0];
        std::istringstream stream(text);
        std::string token;
        while (std::getline(stream, token, ','))
        {
            size_t sep = token.find('/');
            if (sep == std::string::npos)
                continue;
            uint32 slot = CommToUInt32(token.substr(0, sep), EQUIPMENT_SLOT_END);
            uint32 fakeEntry = CommToUInt32(token.substr(sep + 1), 0);

            // slot of the transmogrified item
            if (slot >= EQUIPMENT_SLOT_END || !IsTransmogSlot(uint8(slot)) || !seen.insert(uint8(slot)).second)
                return SendResult(player, false, "Неверный слот.");

            // transmogrified item
            Item* target = player->GetItemByPos(INVENTORY_SLOT_BAG_0, uint8(slot));
            if (!target)
                return SendResult(player, false, "В слоте нет предмета.");

            if (!fakeEntry || fakeEntry == target->GetEntry())
            {
                changes.push_back({ uint8(slot), target, 0 });   // 0 cost if reverting look
                continue;
            }

            ItemData const* targetData = GetItemData(target->GetEntry());
            ItemData const* sourceData = GetItemData(fakeEntry);
            ItemTemplate const* sourceTemplate = sObjectMgr->GetItemTemplate(fakeEntry);
            if (!targetData || !sourceData || !sourceTemplate)
                return SendResult(player, false, "Этот предмет нельзя трансмогрифицировать.");

            if (!CanTransmogrifyItemWithItem(*targetData, *sourceData))
                return SendResult(player, false, "Этот облик не подходит к предмету.");

            if (player->CanUseItem(sourceTemplate) != EQUIP_ERR_OK)
                return SendResult(player, false, "Вы не можете использовать этот облик.");

            if (!HasAppearance(player, *targetData, *sourceData))
                return SendResult(player, false, "Этот облик ещё не собран.");

            changes.push_back({ uint8(slot), target, fakeEntry });
            cost += std::max(targetData->SellPrice, MIN_COST);
        }

        if (changes.empty())
            return SendResult(player, false, "");

        if (cost)
        {
            if (!player->HasEnoughMoney(cost))
                return SendResult(player, false, "Недостаточно денег.");
            player->ModifyMoney(-int64(cost));
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

        SendResult(player, true, "");
        SendState(player);
    }
}

class transmog_world : public WorldScript
{
public:
    transmog_world() : WorldScript("transmog_world") { }

    void OnStartup() override
    {
        LoadItems();
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
