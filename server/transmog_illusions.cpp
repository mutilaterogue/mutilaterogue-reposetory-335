/*
 * Weapon illusions (retail: TransmogIllusion, Enum.TransmogType.Illusion) for 3.3.5.
 *
 * An illusion is the look of a permanent weapon enchant (SpellItemEnchantment.ItemVisual). The server replaces
 * PLAYER_VISIBLE_ITEM_n_ENCHANTMENT through Player::s_visibleItemHook (transmog.cpp), the item enchant itself
 * does not change. Stored on the item: characters.character_transmog.illusion.
 *
 * Illusion list: weapon enchants of Enchanting (SkillLineAbility 333) and Runeforging (776) with effect ENCHANT_ITEM
 * and a visible effect, plus world.transmog_illusion_extra; enchants with the same ItemVisual are one illusion.
 * Account collection (characters.account_illusions), an illusion is unlocked when the character:
 *   - knows the recipe of the enchant;
 *   - wears (or carries in bags) a weapon with an enchant of the same look.
 *
 * AddonComm (client: Transmog\Blizzard_TransmogIllusions.lua):
 *   "TMOG_ILLUSIONS_GET" -> "TMOG_ILLUSIONS" : cost (copper) : "enchantId/spellId/collected,..." : "16/1,17/0" (allowed hands)
 *   applying - together with looks: "TMOG_APPLY" : looks : "slot/enchantId,..." (transmog.cpp)
 *   "TMOG_STATE" : looks : "slot/enchantId,..." - current illusions
 *
 * Weapons with their own model effect (ItemDisplayInfo.ItemVisual) cannot get an illusion - core/DBC_itemdisplayinfo.patch.
 *
 * Setup: sql/characters_transmog_illusions.sql, core/DBC_itemdisplayinfo.patch, AddSC_transmog_illusions() in custom_script_loader.cpp.
 */

#include "transmog.h"
#include "ScriptMgr.h"
#include "Custom\AddonComm\AddonComm.h"
#include "Bag.h"
#include "DatabaseEnv.h"
#include "DBCStores.h"
#include "Item.h"
#include "ItemTemplate.h"
#include "Log.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "StringFormat.h"
#include "WorldSession.h"

#include <map>
#include <sstream>
#include <unordered_map>
#include <unordered_set>

// transmog.cpp (also declared in transmog.h; here so it builds with an older header)
namespace Transmog
{
    uint32 GetFakeEntry(Player* player, Item* item);
}

namespace
{
    constexpr uint32 ILLUSION_COST = 10000;   // 1 gold per slot (removing an illusion is free)
    constexpr uint32 SKILL_ENCHANTING_ID = 333;
    constexpr uint32 SKILL_RUNEFORGING_ID = 776;   // death knight runeforging - illusions too

    struct Illusion
    {
        uint32 Enchant = 0;   // SpellItemEnchantment id put into the visible slot
        uint32 Spell = 0;     // enchant recipe (name and icon in the client)
    };

    std::map<uint32, Illusion> illusionsByVisual;            // ItemVisual -> illusion (ordered for the list)
    std::unordered_map<uint32, uint32> visualByEnchant;      // any enchant with a look -> ItemVisual
    std::unordered_map<uint32, uint32> visualBySpell;        // recipe -> ItemVisual

    uint32 GetVisual(uint32 enchantId)
    {
        SpellItemEnchantmentEntry const* enchant = sSpellItemEnchantmentStore.LookupEntry(enchantId);
        return enchant ? enchant->ItemVisual : 0;
    }

    void LoadIllusions()
    {
        illusionsByVisual.clear();
        visualByEnchant.clear();
        visualBySpell.clear();

        for (uint32 spellId = 0; spellId < sSpellMgr->GetSpellInfoStoreSize(); ++spellId)
        {
            SpellInfo const* spellInfo = sSpellMgr->GetSpellInfo(spellId);
            if (!spellInfo || spellInfo->EquippedItemClass != ITEM_CLASS_WEAPON)
                continue;

            bool enchanting = false;
            SkillLineAbilityMapBounds bounds = sSpellMgr->GetSkillLineAbilityMapBounds(spellId);
            for (auto itr = bounds.first; itr != bounds.second; ++itr)
                if (itr->second->SkillLine == SKILL_ENCHANTING_ID || itr->second->SkillLine == SKILL_RUNEFORGING_ID)
                    enchanting = true;
            if (!enchanting)
                continue;

            for (SpellEffectInfo const& effect : spellInfo->GetEffects())
            {
                if (effect.Effect != SPELL_EFFECT_ENCHANT_ITEM)
                    continue;
                uint32 enchantId = uint32(effect.MiscValue);
                uint32 visual = GetVisual(enchantId);
                if (!visual)
                    continue;
                visualBySpell[spellId] = visual;
                visualByEnchant[enchantId] = visual;
                Illusion& illusion = illusionsByVisual[visual];
                if (!illusion.Enchant)
                {
                    illusion.Enchant = enchantId;
                    illusion.Spell = spellId;
                }
            }
        }

        // custom illusions: world.transmog_illusion_extra (enchant_id - glowing enchant, spell_id - name and icon in the client)
        if (QueryResult result = WorldDatabase.Query("SELECT CAST(enchant_id AS SIGNED), CAST(spell_id AS SIGNED) FROM transmog_illusion_extra"))
        {
            do
            {
                Field* fields = result->Fetch();
                uint32 enchantId = uint32(fields[0].GetInt64());
                uint32 spellId = uint32(fields[1].GetInt64());
                uint32 visual = GetVisual(enchantId);
                if (!visual)
                {
                    TC_LOG_ERROR("sql.sql", "transmog_illusion_extra: enchant {} has no ItemVisual, skipped", enchantId);
                    continue;
                }
                visualByEnchant[enchantId] = visual;
                if (spellId)
                    visualBySpell[spellId] = visual;
                Illusion& illusion = illusionsByVisual[visual];
                if (!illusion.Enchant)
                {
                    illusion.Enchant = enchantId;
                    illusion.Spell = spellId;
                }
            } while (result->NextRow());
        }

        // any other enchants with the same look (e.g. from items) also unlock the illusion
        for (uint32 enchantId = 0; enchantId < sSpellItemEnchantmentStore.GetNumRows(); ++enchantId)
            if (uint32 visual = GetVisual(enchantId))
                if (illusionsByVisual.count(visual))
                    visualByEnchant.emplace(enchantId, visual);

        TC_LOG_INFO("server.loading", ">> transmog: {} illusions", uint32(illusionsByVisual.size()));
    }

    Illusion const* FindIllusion(uint32 enchantId)
    {
        auto itr = visualByEnchant.find(enchantId);
        if (itr == visualByEnchant.end())
            return nullptr;
        auto illusion = illusionsByVisual.find(itr->second);
        return illusion != illusionsByVisual.end() && illusion->second.Enchant == enchantId ? &illusion->second : nullptr;
    }

    std::unordered_set<uint32> LoadCollectedVisuals(Player* player)
    {
        std::unordered_set<uint32> visuals;
        if (QueryResult result = CharacterDatabase.PQuery("SELECT enchantId FROM account_illusions WHERE accountId = {}", player->GetSession()->GetAccountId()))
        {
            do
            {
                auto itr = visualByEnchant.find(result->Fetch()[0].GetUInt32());
                if (itr != visualByEnchant.end())
                    visuals.insert(itr->second);
            } while (result->NextRow());
        }
        return visuals;
    }

    // unlock illusions from recipes and enchants on the character's weapons; return all unlocked looks
    std::unordered_set<uint32> UpdateCollection(Player* player)
    {
        std::unordered_set<uint32> visuals = LoadCollectedVisuals(player);
        std::unordered_set<uint32> added;

        auto unlock = [&](uint32 visual)
        {
            if (visual && illusionsByVisual.count(visual) && visuals.insert(visual).second)
                added.insert(visual);
        };

        for (auto const& [spellId, visual] : visualBySpell)
            if (player->HasSpell(spellId))
                unlock(visual);

        auto checkItem = [&](Item* item)
        {
            if (!item || item->GetTemplate()->Class != ITEM_CLASS_WEAPON)
                return;
            auto itr = visualByEnchant.find(item->GetEnchantmentId(PERM_ENCHANTMENT_SLOT));
            if (itr != visualByEnchant.end())
                unlock(itr->second);
        };
        for (uint8 slot = EQUIPMENT_SLOT_START; slot < INVENTORY_SLOT_ITEM_END; ++slot)
            checkItem(player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot));
        for (uint8 bagSlot = INVENTORY_SLOT_BAG_START; bagSlot < INVENTORY_SLOT_BAG_END; ++bagSlot)
            if (Bag* bag = player->GetBagByPos(bagSlot))
                for (uint32 i = 0; i < bag->GetBagSize(); ++i)
                    checkItem(bag->GetItemByPos(uint8(i)));

        if (!added.empty())
        {
            CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
            for (uint32 visual : added)
                trans->Append(Trinity::StringFormat("INSERT IGNORE INTO account_illusions (accountId, enchantId) VALUES ({}, {})",
                    player->GetSession()->GetAccountId(), illusionsByVisual[visual].Enchant).c_str());
            CharacterDatabase.CommitTransaction(trans);
        }
        return visuals;
    }

    // retail: illusions only on melee weapons in main and off hand (no shields, off-hand frills, ranged)
    bool CanHaveIllusion(Player* player, Item* item)
    {
        if (!item)
            return false;
        ItemTemplate const* proto = item->GetTemplate();
        if (proto->Class != ITEM_CLASS_WEAPON)
            return false;
        // the shown look (a transmog look if transmogrified) with its own model effect - no illusion
        ItemTemplate const* look = proto;
        if (uint32 fake = Transmog::GetFakeEntry(player, item))
            if (ItemTemplate const* fakeProto = sObjectMgr->GetItemTemplate(fake))
                look = fakeProto;
        // ItemDisplayInfo.ItemVisual - effect built into the model (loaded by the core: core/DBC_itemdisplayinfo.patch)
        if (ItemDisplayInfoEntry const* display = sItemDisplayInfoStore.LookupEntry(look->DisplayInfoID))
            if (display->ItemVisual > 0)
                return false;
        switch (proto->InventoryType)
        {
            case INVTYPE_WEAPON: case INVTYPE_2HWEAPON: case INVTYPE_WEAPONMAINHAND: case INVTYPE_WEAPONOFFHAND:
                return true;
            default:
                return false;
        }
    }

    void HandleGetIllusions(Player* player, std::vector<std::string> const& /*args*/)
    {
        std::unordered_set<uint32> collected = UpdateCollection(player);
        std::ostringstream list;
        bool first = true;
        for (auto const& [visual, illusion] : illusionsByVisual)
        {
            if (!first)
                list << ',';
            list << illusion.Enchant << '/' << illusion.Spell << '/' << (collected.count(visual) ? 1 : 0);
            first = false;
        }
        sAddonComm->Send(player, "TMOG_ILLUSIONS", ILLUSION_COST, list.str(), Transmog::FormatIllusionAllowed(player));
    }
}

namespace Transmog
{
    ApplyResult CheckIllusions(Player* player, SlotList const& illusions, uint64& cost)
    {
        cost = 0;
        if (illusions.empty())
            return ApplyResult{ true };

        std::unordered_set<uint32> collected;
        bool collectedLoaded = false;
        std::unordered_set<uint8> seen;
        for (auto const& [slot, enchantId] : illusions)
        {
            ApplyResult fail;
            if ((slot != EQUIPMENT_SLOT_MAINHAND && slot != EQUIPMENT_SLOT_OFFHAND) || !seen.insert(slot).second)
            {
                fail.Error = "TRANSMOGRIFY_INVALID_DESTINATION";
                return fail;
            }
            Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
            if (!item)
            {
                fail.Error = "TRANSMOGRIFY_INVALID_NO_ITEM";
                return fail;
            }
            if (!enchantId)
                continue;   // remove the illusion
            if (!CanHaveIllusion(player, item))
            {
                fail.Error = "ERR_TRANSMOGRIFY_INVALID_DESTINATION";
                fail.ErrorItem = item->GetEntry();
                return fail;
            }
            Illusion const* illusion = FindIllusion(enchantId);
            if (!illusion)
            {
                fail.Error = "ERR_TRANSMOGRIFY_INVALID_SOURCE";
                return fail;
            }
            if (!collectedLoaded)
            {
                collected = UpdateCollection(player);
                collectedLoaded = true;
            }
            if (!collected.count(GetVisual(enchantId)))
            {
                fail.Error = "TRANSMOGRIFY_STYLE_UNCOLLECTED";
                return fail;
            }
            if (GetIllusion(player, slot) != enchantId)
                cost += ILLUSION_COST;
        }
        return ApplyResult{ true };
    }

    void ApplyIllusions(Player* player, SlotList const& illusions)
    {
        CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
        for (auto const& [slot, enchantId] : illusions)
            SetIllusion(player, slot, enchantId, trans);
        CharacterDatabase.CommitTransaction(trans);
    }

    std::string FormatIllusionAllowed(Player* player)
    {
        SlotList list;
        for (uint8 slot : { uint8(EQUIPMENT_SLOT_MAINHAND), uint8(EQUIPMENT_SLOT_OFFHAND) })
            list.emplace_back(slot, CanHaveIllusion(player, player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot)) ? 1 : 0);
        return FormatSlots(list);
    }

    std::string FormatIllusions(Player* player)
    {
        SlotList list;
        for (uint8 slot : { uint8(EQUIPMENT_SLOT_MAINHAND), uint8(EQUIPMENT_SLOT_OFFHAND) })
            if (uint32 enchantId = GetIllusion(player, slot))
                list.emplace_back(slot, enchantId);
        return FormatSlots(list);
    }
}

class transmog_illusions_world : public WorldScript
{
public:
    transmog_illusions_world() : WorldScript("transmog_illusions_world") { }

    void OnStartup() override
    {
        LoadIllusions();
    }
};

class transmog_illusions_player : public PlayerScript
{
public:
    transmog_illusions_player() : PlayerScript("transmog_illusions_player")
    {
        sAddonComm->Register(std::string("TMOG_ILLUSIONS_GET"), &HandleGetIllusions);
    }
};

void AddSC_transmog_illusions()
{
    new transmog_illusions_world();
    new transmog_illusions_player();
}
