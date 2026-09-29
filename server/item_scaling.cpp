/*
 * Скейлинг предметов (ретейл: уровень предмета экземпляра - ItemBonus) для 3.3.5.
 *
 * Бонус к уровню хранится на экземпляре предмета (characters.item_scaling), предмет его не теряет при
 * передаче, в банке и т.д. Характеристики пересчитывает ядро через Player::s_itemScaleHook
 * (core/Player_itemscale.patch): статы, броня и урон оружия шаблона умножаются на множитель от бонуса.
 *   множитель = STEP ^ бонус (ретейл: ~0.94% характеристик на уровень предмета)
 *
 * Подсказки - как у Reforger (Rochet2): клиенту шлётся кэш предмета (SMSG_ITEM_QUERY_SINGLE_RESPONSE) с
 * пересчитанными значениями и уровнем, родная подсказка показывает их сама. Кэш клиента - по номеру
 * предмета, поэтому при наведении на экземпляр с другим бонусом клиент просит кэш именно для него.
 *
 * AddonComm (клиент: ItemScaling\ItemScaling.lua):
 *   "ISCALE_CONFIG" : statStep : armorStep : damageStep (x1000000)
 *   "ISCALE_ITEMS_GET" -> "ISCALE_ITEMS" : "bag/slot/bonus,..." (ячейки как у трансмога: 255 - экипировка и банк,
 *                                             0 - рюкзак, 1..4 - сумки, 5..11 - сумки банка)
 *   "ISCALE_SHOW" : bag : slot                -> кэш предмета с бонусом этого экземпляра
 * GM: .itemscale <ячейка 1..19> <бонус>  - бонус надетому предмету (0 - убрать)
 *
 * Установка: sql/characters_item_scaling.sql, core/Player_itemscale.patch, AddSC_item_scaling().
 */

#include "item_scaling.h"
#include "ScriptMgr.h"
#include "Custom\AddonComm\AddonComm.h"
#include "Bag.h"
#include "Chat.h"
#include "ChatCommand.h"
#include "DatabaseEnv.h"
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
    // рост за 1 уровень предмета (ретейл Legion+: 1.00936 на характеристики)
    constexpr double STAT_STEP = 1.00936;
    constexpr double ARMOR_STEP = 1.00936;
    constexpr double DAMAGE_STEP = 1.00936;
    constexpr int32 MAX_BONUS = 200;

    std::unordered_map<uint32, int32> bonuses;   // item guid -> бонус

    // ячейка клиента -> предмет (как в Transmog::SendItems)
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
    }

    void SetBonus(Player* player, Item* item, int32 bonus)
    {
        bonus = std::max(-MAX_BONUS, std::min(MAX_BONUS, bonus));
        uint32 guid = item->GetGUID().GetCounter();

        // характеристики надетого предмета: снять со старым бонусом, наложить с новым
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

    void OnLogin(Player* player, bool /*firstLogin*/) override
    {
        SendConfig(player);
        SendItems(player);
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

    // .itemscale <ячейка 1..19> <бонус>
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
        handler->PSendSysMessage("itemscale: item {} level {} (bonus {})", item->GetEntry(), ItemScaling::GetItemLevel(item), ItemScaling::GetBonus(item));
        return true;
    }
};

void AddSC_item_scaling()
{
    new item_scaling_world();
    new item_scaling_player();
    new item_scaling_commands();
}
