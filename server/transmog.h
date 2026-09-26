/*
 * Transmogrification shared part (retail TransmogMgr) for 3.3.5: item data, collection checks and
 * applying looks. Used by transmog.cpp (window, NPC), transmog_outfits.cpp (outfits, situations,
 * custom sets) and transmog_sets.cpp (item sets).
 *
 * Errors are sent to the client as retail global string names (ERR_TRANSMOGRIFY_*, TRANSMOG_*),
 * the client shows _G[name] (Transmog\Blizzard_TransmogStrings.lua).
 */

#ifndef CUSTOM_TRANSMOG_H
#define CUSTOM_TRANSMOG_H

#include "Define.h"
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

class Player;

namespace Transmog
{
    struct ItemData
    {
        uint8 Class = 0;
        uint8 SubClass = 0;
        uint8 InventoryType = 0;
        uint8 Quality = 0;
        uint32 DisplayId = 0;
        uint32 SellPrice = 0;
        int32 AllowableClass = -1;
        uint32 ItemSet = 0;
    };

    // slot -> itemId (0 = the item's own look)
    typedef std::vector<std::pair<uint8, uint32>> SlotList;

    struct ApplyResult
    {
        bool Ok = false;
        std::string Error;     // global string name
        uint32 ErrorItem = 0;  // item for "%s" in the error
    };

    void Load();
    ItemData const* GetItemData(uint32 entry);
    std::unordered_map<uint32, ItemData> const& GetAllItems();

    bool IsTransmogSlot(uint8 slot);
    bool CanTransmogrifyItemWithItem(ItemData const& target, ItemData const& source);

    // account appearances (characters.account_appearances), loaded per request
    std::unordered_set<uint32> LoadCollected(Player* player);
    // appearance of itemId collected: a collected item with the same look that fits the same slot type
    bool IsAppearanceCollected(std::unordered_set<uint32> const& collected, uint32 itemId);
    bool IsAppearanceCollected(std::unordered_set<uint32> const& collected, ItemData const& target, uint32 itemId);

    // "slot/itemId,slot/itemId" <-> SlotList
    SlotList ParseSlots(std::string const& text);
    std::string FormatSlots(SlotList const& slots);

    // cost of changing the equipped items to the looks (sell price, min 1 silver; restoring is free)
    uint64 GetCost(Player* player, SlotList const& looks);

    // retail HandleTransmogrifyItems. skipInvalid: drop slots that do not fit (outfits, situations)
    // instead of failing; charge: take GetCost() money
    ApplyResult ApplyLooks(Player* player, SlotList const& looks, bool charge, bool skipInvalid);

    // current transmogrified looks of the equipped items
    SlotList GetCurrentLooks(Player* player);

    void SendState(Player* player);
    void SendResult(Player* player, ApplyResult const& result);
    std::string SanitizeName(std::string name, size_t maxBytes);
}

#endif
