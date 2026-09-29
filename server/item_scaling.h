/*
 * Скейлинг предметов: у каждого экземпляра предмета - свой бонус к уровню (ретейл: ItemBonus / item level),
 * характеристики, броня и урон оружия пересчитываются от шаблона (item_scaling.cpp, core/Player_itemscale.patch).
 * Используется улучшением снаряжения и наградами (M+, треки) - всё через SetBonus.
 */

#ifndef CUSTOM_ITEM_SCALING_H
#define CUSTOM_ITEM_SCALING_H

#include "Define.h"

class Item;
class Player;
struct ItemTemplate;

namespace ItemScaling
{
    // бонус к уровню предмета (0 - как в item_template)
    int32 GetBonus(Item const* item);
    // уровень предмета с бонусом
    uint32 GetItemLevel(Item const* item);
    // поставить бонус: если предмет надет - характеристики пересчитываются сразу; клиенту - новая подсказка
    void SetBonus(Player* player, Item* item, int32 bonus);

    // множители от бонуса (одинаковые формулы у сервера и клиента - клиент получает их в "ISCALE_CONFIG")
    float StatScale(int32 bonus);
    float ArmorScale(int32 bonus);
    float DamageScale(int32 bonus);

    // подсказка клиента: кэш предмета (SMSG_ITEM_QUERY_SINGLE_RESPONSE) с пересчитанными значениями
    void SendItemCache(Player* player, ItemTemplate const* proto, int32 bonus);
}

#endif
