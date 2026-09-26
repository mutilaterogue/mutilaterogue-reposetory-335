/*
 * Transmog item sets (retail TransmogSet / TransmogSetItem, "Sets" tab) for 3.3.5.
 *
 * 3.3.5 has no TransmogSet.db2: a set is item_template.itemset (ItemSet.dbc), only armor and weapons,
 * only items the character's class can use. The set name comes from the item tooltip on the client.
 *
 * AddonComm opcodes (client: Transmog\Blizzard_TransmogSets.lua):
 *   "TMOG_SETS_GET"                     -> "TMOG_SET" x N, "TMOG_SETS_END" : count
 *   "TMOG_SET"   S: setId : "itemId/collected,..."
 *
 * Register AddSC_transmog_sets() (after AddSC_transmog()).
 */

#include "transmog.h"
#include "ScriptMgr.h"
#include "AddonComm\AddonComm.h"
#include "Player.h"
#include "SharedDefines.h"

#include <algorithm>
#include <map>
#include <sstream>
#include <unordered_map>
#include <vector>

namespace
{
    std::map<uint32, std::vector<uint32>> itemsBySet;   // itemset -> items
    bool setsBuilt = false;

    void BuildSets()
    {
        itemsBySet.clear();
        for (auto const& [entry, data] : Transmog::GetAllItems())
            if (data.ItemSet)
                itemsBySet[data.ItemSet].push_back(entry);
        for (auto& [setId, entries] : itemsBySet)
            std::sort(entries.begin(), entries.end());
        setsBuilt = true;
    }

    void HandleSetsGet(Player* player, std::vector<std::string> const& /*args*/)
    {
        if (!setsBuilt)
            BuildSets();

        std::unordered_set<uint32> collected = Transmog::LoadCollected(player);
        // collected looks by displayid, so every set item is checked without scanning the whole collection
        std::unordered_multimap<uint32, uint32> collectedByDisplay;
        for (uint32 itemId : collected)
            if (Transmog::ItemData const* data = Transmog::GetItemData(itemId))
                collectedByDisplay.emplace(data->DisplayId, itemId);

        uint32 classMask = player->GetClassMask();
        uint32 count = 0;
        for (auto const& [setId, entries] : itemsBySet)
        {
            std::ostringstream list;
            uint32 usable = 0;
            for (uint32 itemId : entries)
            {
                Transmog::ItemData const* data = Transmog::GetItemData(itemId);
                if (!data || (data->AllowableClass != -1 && !(uint32(data->AllowableClass) & classMask)))
                    continue;

                bool isCollected = collected.count(itemId) != 0;
                auto range = collectedByDisplay.equal_range(data->DisplayId);
                for (auto itr = range.first; itr != range.second && !isCollected; ++itr)
                    if (Transmog::ItemData const* other = Transmog::GetItemData(itr->second))
                        isCollected = Transmog::CanTransmogrifyItemWithItem(*data, *other);

                if (usable)
                    list << ',';
                list << itemId << '/' << (isCollected ? 1 : 0);
                ++usable;
            }
            if (usable < 2)
                continue;   // not a set for this class
            sAddonComm->Send(player, "TMOG_SET", setId, list.str());
            ++count;
        }
        sAddonComm->Send(player, "TMOG_SETS_END", count);
    }
}

class transmog_sets_player : public PlayerScript
{
public:
    transmog_sets_player() : PlayerScript("transmog_sets_player")
    {
        sAddonComm->Register(std::string("TMOG_SETS_GET"), &HandleSetsGet);
    }
};

void AddSC_transmog_sets()
{
    new transmog_sets_player();
}
