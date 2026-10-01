/*
 * Item scaling (retail: per-instance item level - ItemBonus) for 3.3.5.
 *
 * The item level bonus is stored on the item instance (characters.item_scaling), the item keeps it when
 * traded, banked etc. Stats are recalculated by the core through Player::s_itemScaleHook
 * (core/Player_itemscale.patch): template stats, armor and weapon damage are multiplied by the bonus multiplier.
 *   multiplier = STEP ^ bonus (retail: ~0.94% stats per item level)
 *
 * Tooltips - like Reforger (Rochet2): the client gets an item cache (SMSG_ITEM_QUERY_SINGLE_RESPONSE) with
 * recalculated values and item level, the native tooltip shows them. The client cache is per item entry,
 * so when hovering an instance with a different bonus the client asks for the cache of that instance.
 *
 * AddonComm (client: ItemScaling\ItemScaling.lua):
 *   "ISCALE_CONFIG" : statStep : armorStep : damageStep (x1000000)
 *   "ISCALE_ITEMS_GET" -> "ISCALE_ITEMS" : "bag/slot/bonus,..." (slots as in transmog: 255 - equipment and bank,
 *                                             0 - backpack, 1..4 - bags, 5..11 - bank bags)
 *   "ISCALE_SHOW" : bag : slot                -> item cache with the bonus of this instance
 *   S->C "ISCALE_CACHED" : itemId : bonus     (after every item cache sent: the bonus the client cache has now)
 * GM: .itemscale <slot 1..19> <bonus>  - bonus for an equipped item (0 - remove)
 *
 * Setup: sql/characters_item_scaling.sql, core/Player_itemscale.patch, AddSC_item_scaling().
 */

#include "item_scaling.h"
#include "ScriptMgr.h"
#include "Custom\AddonComm\AddonComm.h"
#include "Bag.h"
#include "Chat.h"
#include "ChatCommand.h"
#include "DatabaseEnv.h"
#include "EventProcessor.h"
#include "Item.h"
#include "ItemTemplate.h"
#include "Log.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "RBAC.h"
#include "StringFormat.h"
#include "WorldPacket.h"
#include "WorldSession.h"

#include <cmath>
#include <sstream>
#include <unordered_map>

using namespace Trinity::ChatCommands;

namespace
{
    // growth per item level (retail Legion+: 1.00936 for stats)
    constexpr double STAT_STEP = 1.00936;
    constexpr double ARMOR_STEP = 1.00936;
    constexpr double DAMAGE_STEP = 1.00936;
    constexpr int32 MAX_BONUS = 200;

    std::unordered_map<uint32, int32> bonuses;   // item guid -> bonus

    // client slot -> item (as in Transmog::SendItems)
    Item* GetClientItem(Player* player, uint32 bag, uint32 slot)
    {
        if (!slot)
            return nullptr;
        if (bag == 255)
            return player->GetItemByPos(INVENTORY_SLOT_BAG_0, uint8(slot - 1));
        if (bag == 0)
            return player->GetItemByPos(INVENTORY_SLOT_BAG_0, uint8(INVENTORY_SLOT_ITEM_START + slot - 1));
        if (bag >= 1 && bag <= 4)
            return player->GetItemByPos(uint8(INVENTORY_SLOT_BAG_START + bag - 1), uint8(slot - 1));
        if (bag >= 5 && bag <= 11)
            return player->GetItemByPos(uint8(BANK_SLOT_BAG_START + bag - 5), uint8(slot - 1));
        return nullptr;
    }

    void SendItems(Player* player)
    {
        std::ostringstream list;
        bool first = true;
        auto add = [&](uint32 bag, uint32 slot, Item* item)
        {
            if (!item)
                return;
            int32 bonus = ItemScaling::GetBonus(item);
            if (!bonus)
                return;
            if (!first)
                list << ',';
            list << bag << '/' << slot << '/' << bonus;
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
        for (uint8 slot = BANK_SLOT_ITEM_START; slot < BANK_SLOT_ITEM_END; ++slot)
            add(255, slot + 1, player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot));
        for (uint8 bagSlot = BANK_SLOT_BAG_START; bagSlot < BANK_SLOT_BAG_END; ++bagSlot)
            if (Bag* bag = player->GetBagByPos(bagSlot))
                for (uint32 i = 0; i < bag->GetBagSize(); ++i)
                    add(bagSlot - BANK_SLOT_BAG_START + 5, i + 1, bag->GetItemByPos(uint8(i)));
        sAddonComm->Send(player, "ISCALE_ITEMS", list.str());
    }

    void SendConfig(Player* player)
    {
        sAddonComm->Send(player, "ISCALE_CONFIG", uint32(STAT_STEP * 1000000.0), uint32(ARMOR_STEP * 1000000.0), uint32(DAMAGE_STEP * 1000000.0));
    }

    // Player::s_itemScaleHook
    float ScaleHook(Player const* /*player*/, Item const* item, Player::ItemScaleKind kind)
    {
        int32 bonus = ItemScaling::GetBonus(item);
        if (!bonus)
            return 1.0f;
        switch (kind)
        {
            case Player::ITEM_SCALE_STATS: return ItemScaling::StatScale(bonus);
            case Player::ITEM_SCALE_ARMOR: return ItemScaling::ArmorScale(bonus);
            case Player::ITEM_SCALE_DAMAGE: return ItemScaling::DamageScale(bonus);
            default: return 1.0f;
        }
    }

    void HandleItemsGet(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendConfig(player);
        SendItems(player);
    }

    void HandleShow(Player* player, std::vector<std::string> const& args)
    {
        if (args.size() < 2)
            return;
        Item* item = GetClientItem(player, CommToUInt32(args[0], 0), CommToUInt32(args[1], 0));
        if (item)
            ItemScaling::SendItemCache(player, item->GetTemplate(), ItemScaling::GetBonus(item));
    }
}

namespace ItemScaling
{
    float StatScale(int32 bonus)   { return float(std::pow(STAT_STEP, bonus)); }
    float ArmorScale(int32 bonus)  { return float(std::pow(ARMOR_STEP, bonus)); }
    float DamageScale(int32 bonus) { return float(std::pow(DAMAGE_STEP, bonus)); }

    int32 GetBonus(Item const* item)
    {
        if (!item)
            return 0;
        auto itr = bonuses.find(item->GetGUID().GetCounter());
        return itr != bonuses.end() ? itr->second : 0;
    }

    uint32 GetItemLevel(Item const* item)
    {
        return uint32(std::max<int32>(1, int32(item->GetTemplate()->ItemLevel) + GetBonus(item)));
    }

    void SendItemCache(Player* player, ItemTemplate const* proto, int32 bonus)
    {
        if (!proto)
            return;
        ItemTemplate copy = *proto;
        if (bonus)
        {
            float statScale = StatScale(bonus);
            for (uint32 i = 0; i < MAX_ITEM_PROTO_STATS; ++i)
                if (copy.ItemStat[i].ItemStatValue)
                    copy.ItemStat[i].ItemStatValue = int32(std::lround(copy.ItemStat[i].ItemStatValue * statScale));
            if (copy.Armor)
                copy.Armor = uint32(std::lround(copy.Armor * ArmorScale(bonus)));
            float damageScale = DamageScale(bonus);
            for (uint32 i = 0; i < MAX_ITEM_PROTO_DAMAGES; ++i)
            {
                copy.Damage[i].DamageMin *= damageScale;
                copy.Damage[i].DamageMax *= damageScale;
            }
            copy.ItemLevel = uint32(std::max<int32>(1, int32(copy.ItemLevel) + bonus));
        }
        WorldPacket packet = copy.BuildQueryData(player->GetSession()->GetSessionDbLocaleIndex());
        player->SendDirectMessage(&packet);
        // the client cache is per item entry: tell the client which bonus it holds now
        // (else another instance of the same item shows these stats until it is hovered twice)
        sAddonComm->Send(player, "ISCALE_CACHED", proto->ItemId, bonus);
    }

    void SetBonus(Player* player, Item* item, int32 bonus)
    {
        bonus = std::max(-MAX_BONUS, std::min(MAX_BONUS, bonus));
        uint32 guid = item->GetGUID().GetCounter();

        // stats of an equipped item: remove with the old bonus, apply with the new one
        bool equipped = item->IsEquipped() && item->GetOwnerGUID() == player->GetGUID();
        if (equipped)
            player->_ApplyItemMods(item, item->GetSlot(), false);
        if (bonus)
            bonuses[guid] = bonus;
        else
            bonuses.erase(guid);
        if (equipped)
            player->_ApplyItemMods(item, item->GetSlot(), true);

        if (bonus)
            CharacterDatabase.Execute(Trinity::StringFormat("REPLACE INTO item_scaling (item_guid, bonus) VALUES ({}, {})", guid, bonus).c_str());
        else
            CharacterDatabase.Execute(Trinity::StringFormat("DELETE FROM item_scaling WHERE item_guid = {}", guid).c_str());

        SendItemCache(player, item->GetTemplate(), bonus);
        SendItems(player);
    }
}

class item_scaling_world : public WorldScript
{
public:
    item_scaling_world() : WorldScript("item_scaling_world") { }

    void OnStartup() override
    {
        CharacterDatabase.Execute("DELETE FROM item_scaling WHERE item_guid NOT IN (SELECT guid FROM item_instance)");
        bonuses.clear();
        if (QueryResult result = CharacterDatabase.Query("SELECT CAST(item_guid AS SIGNED), CAST(bonus AS SIGNED) FROM item_scaling"))
        {
            do
            {
                Field* fields = result->Fetch();
                bonuses[uint32(fields[0].GetInt64())] = int32(fields[1].GetInt64());
            } while (result->NextRow());
        }
        TC_LOG_INFO("server.loading", ">> item scaling: {} items", uint32(bonuses.size()));
        Player::s_itemScaleHook = &ScaleHook;
    }
};

class item_scaling_player : public PlayerScript
{
public:
    item_scaling_player() : PlayerScript("item_scaling_player")
    {
        sAddonComm->Register(std::string("ISCALE_ITEMS_GET"), &HandleItemsGet);
        sAddonComm->Register(std::string("ISCALE_SHOW"), &HandleShow);
    }

    // like SendReforgePackets in Reforger: one second after login - caches of all items with a bonus,
    // so the character frame and GetItemInfo see the new values right away, not only after hovering
    class SendCachesEvent : public BasicEvent
    {
    public:
        explicit SendCachesEvent(Player* player) : _player(player) { }

        bool Execute(uint64, uint32) override
        {
            std::unordered_map<uint32, int32> sent;   // entry -> bonus (client cache is per item entry)
            auto send = [&](Item* item)
            {
                if (!item)
                    return;
                int32 bonus = ItemScaling::GetBonus(item);
                if (!bonus || sent.count(item->GetEntry()))
                    return;
                sent[item->GetEntry()] = bonus;
                ItemScaling::SendItemCache(_player, item->GetTemplate(), bonus);
            };
            // equipped items first: for identical items the cache gets the bonus of the equipped one
            for (uint8 slot = EQUIPMENT_SLOT_START; slot < INVENTORY_SLOT_ITEM_END; ++slot)
                send(_player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot));
            for (uint8 slot = BANK_SLOT_ITEM_START; slot < BANK_SLOT_ITEM_END; ++slot)
                send(_player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot));
            for (uint8 bagSlot : { uint8(INVENTORY_SLOT_BAG_START), uint8(INVENTORY_SLOT_BAG_START + 1), uint8(INVENTORY_SLOT_BAG_START + 2), uint8(INVENTORY_SLOT_BAG_START + 3) })
                if (Bag* bag = _player->GetBagByPos(bagSlot))
                    for (uint32 i = 0; i < bag->GetBagSize(); ++i)
                        send(bag->GetItemByPos(uint8(i)));
            for (uint8 bagSlot = BANK_SLOT_BAG_START; bagSlot < BANK_SLOT_BAG_END; ++bagSlot)
                if (Bag* bag = _player->GetBagByPos(bagSlot))
                    for (uint32 i = 0; i < bag->GetBagSize(); ++i)
                        send(bag->GetItemByPos(uint8(i)));
            return true;
        }

    private:
        Player* _player;
    };

    void OnLogin(Player* player, bool /*firstLogin*/) override
    {
        SendConfig(player);
        SendItems(player);
        player->m_Events.AddEvent(new SendCachesEvent(player), player->m_Events.CalculateTime(Milliseconds(1000)));
    }
};

class item_scaling_commands : public CommandScript
{
public:
    item_scaling_commands() : CommandScript("item_scaling_commands") { }

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable commandTable =
        {
            { "itemscale", HandleItemScale, rbac::RBAC_PERM_COMMAND_ADDITEM, Console::No },
        };
        return commandTable;
    }

    // .itemscale <slot 1..19> <bonus>
    static bool HandleItemScale(ChatHandler* handler, uint8 slot, int32 bonus)
    {
        Player* player = handler->GetSession()->GetPlayer();
        Item* item = (slot >= 1 && slot <= EQUIPMENT_SLOT_END) ? player->GetItemByPos(INVENTORY_SLOT_BAG_0, uint8(slot - 1)) : nullptr;
        if (!item)
        {
            handler->SendSysMessage("itemscale: no item in this slot (1..19)");
            return false;
        }
        ItemScaling::SetBonus(player, item, bonus);
        handler->SendSysMessage(Trinity::StringFormat("itemscale: item {} level {} (bonus {})", item->GetEntry(), ItemScaling::GetItemLevel(item), ItemScaling::GetBonus(item)));
        return true;
    }
};

void AddSC_item_scaling()
{
    new item_scaling_world();
    new item_scaling_player();
    new item_scaling_commands();
}
