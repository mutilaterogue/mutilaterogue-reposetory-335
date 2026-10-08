/*
 * Item scaling: every item instance has its own item level bonus (retail: ItemBonus / item level),
 * stats, armor and weapon damage are recalculated from the template (item_scaling.cpp, core/Player_itemscale.patch).
 * Used by gear upgrades and rewards (M+, tracks) - everything goes through SetBonus.
 */

#ifndef CUSTOM_ITEM_SCALING_H
#define CUSTOM_ITEM_SCALING_H

#include "Define.h"

class Item;
class Player;
struct ItemTemplate;

namespace ItemScaling
{
    // item level bonus (0 - as in item_template)
    int32 GetBonus(Item const* item);
    // item level including the bonus
    uint32 GetItemLevel(Item const* item);
    // set the bonus: stats of an equipped item are recalculated at once; the client gets a new tooltip
    void SetBonus(Player* player, Item* item, int32 bonus);

    // multipliers from the bonus (same formulas on server and client - the client gets them in "ISCALE_CONFIG")
    float StatScale(int32 bonus);
    float ArmorScale(int32 bonus);
    float DamageScale(int32 bonus);

    // client tooltip: item cache (SMSG_ITEM_QUERY_SINGLE_RESPONSE) with recalculated values
    void SendItemCache(Player* player, ItemTemplate const* proto, int32 bonus);
}

#endif
