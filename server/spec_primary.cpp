/*
 * Primary talent tree (Cataclysm specialization) for the 3.3.5 client: the specialization tab.
 * AddonComm:
 *   C->S "SPEC_GET"              -> S->C "SPEC_STATE" activeGroup, primary of group 1, primary of group 2 (tab index 1..3, 0 = none)
 *   C->S "SPEC_SET" index(1..3)  -> learns it (Player::LearnPrimaryTalentSpecialization), changing it resets the talents
 * AddSC_spec_primary() in custom_script_loader.cpp.
 */

#include "ScriptMgr.h"
#include "Custom\AddonComm\AddonComm.h"
#include "DBCStores.h"
#include "StringFormat.h"
#include "DatabaseEnv.h"
#include "Player.h"
#include "SpellMgr.h"
#include "SpellScript.h"
#include "Chat.h"

#include <cstdlib>
#include <unordered_map>
#include <string>
#include <vector>

bool MythicPlus_TalentsLocked(Player const* player);  // mythic_plus.cpp

namespace
{
    // the cast of a specialization change (retail: 2 s). 0 - the change is instant
    constexpr uint32 SPEC_CHANGE_SPELL = 0;

    char const* const MSG_TALENTS_LOCKED = "\xd0\x9d\xd0\xb5\xd0\xbb\xd1\x8c\xd0\xb7\xd1\x8f \xd0\xbc\xd0\xb5\xd0\xbd\xd1\x8f\xd1\x82\xd1\x8c \xd1\x82\xd0\xb0\xd0\xbb\xd0\xb0\xd0\xbd\xd1\x82\xd1\x8b \xd0\xb2\xd0\xbe \xd0\xb2\xd1\x80\xd0\xb5\xd0\xbc\xd1\x8f \xd1\x8d\xd0\xbf\xd0\xbe\xd1\x85\xd0\xb0\xd0\xbb\xd1\x8c\xd0\xbd\xd0\xbe\xd0\xb3\xd0\xbe \xd0\xba\xd0\xbb\xd1\x8e\xd1\x87\xd0\xb0.";

    std::unordered_map<ObjectGuid::LowType, uint32> s_pending;   // the tab index waiting for the end of the cast

    // the tab id of the primary tree -> its index in the class tabs (1..3) by TalentTab.dbc OrderIndex, 0 = none
    uint32 PrimaryIndex(Player* player, uint8 spec)
    {
        uint32 tree = player->GetPrimaryTalentTree(spec);
        if (!tree)
            return 0;
        TalentTabEntry const* tab = sTalentTabStore.LookupEntry(tree);
        if (!tab || !(tab->ClassMask & player->GetClassMask()))
            return 0;
        return tab->OrderIndex + 1;
    }

    std::string JoinSpells(std::vector<uint32> const& spells)
    {
        std::string text;
        for (uint32 spell : spells)
            text += (text.empty() ? "" : "/") + std::to_string(spell);
        return text;
    }

    // the specialization tab: "SPEC_SPELLS" index(1..3) : mastery spells a/b : primary spells c/d (retail sample abilities)
    void SendSpells(Player* player)
    {
        for (uint32 i = 0; i < sTalentTabStore.GetNumRows(); ++i)
        {
            TalentTabEntry const* tab = sTalentTabStore.LookupEntry(i);
            if (!tab || !(tab->ClassMask & player->GetClassMask()))
                continue;
            std::vector<uint32> mastery, primary;
            for (uint32 j = 0; j < MAX_MASTERY_SPELLS; ++j)
                if (tab->MasterySpellID[j])
                    mastery.push_back(tab->MasterySpellID[j]);
            if (std::vector<uint32> const* specSpells = GetTalentTreePrimarySpells(tab->ID))
                primary = *specSpells;
            sAddonComm->Send(player, "SPEC_SPELLS", uint32(tab->OrderIndex) + 1, JoinSpells(mastery), JoinSpells(primary));
        }

        // "SPEC_INFO" index : role : description (custom_spec_info; ':' travels as {c}, '\n' -> '|n')
        if (QueryResult result = WorldDatabase.Query(Trinity::StringFormat(
            "SELECT CAST(tab AS SIGNED), role, description FROM custom_spec_info WHERE class_mask & {} <> 0", player->GetClassMask()).c_str()))
            do
            {
                Field* f = result->Fetch();
                std::string description = f[2].GetString();
                std::string text;
                for (size_t i = 0; i < description.size(); ++i)
                {
                    if (description[i] == '\\' && i + 1 < description.size() && description[i + 1] == 'n')
                    {
                        text += "|n";
                        ++i;
                    }
                    else if (description[i] == '\n')
                        text += "|n";
                    else if (description[i] == ':')
                        text += "{c}"; // the client puts the colon back
                    else
                        text += description[i];
                }
                sAddonComm->Send(player, "SPEC_INFO", uint32(f[0].GetInt64()), f[1].GetString(), text);
            } while (result->NextRow());
    }

    void SendState(Player* player)
    {
        sAddonComm->Send(player, "SPEC_STATE", uint32(player->GetActiveSpec()) + 1, PrimaryIndex(player, 0),
            MAX_TALENT_GROUPS > 1 ? PrimaryIndex(player, 1) : 0u);
    }

    // drops the old primary tree: its spells, mastery and the spent points
    void ClearPrimary(Player* player)
    {
        uint8 spec = player->GetActiveSpec();
        uint32 tree = player->GetPrimaryTalentTree(spec);
        if (!tree)
            return;
        player->ResetTalents(true);
        if (std::vector<uint32> const* specSpells = GetTalentTreePrimarySpells(tree))
            for (uint32 spellId : *specSpells)
                player->RemoveSpell(spellId, true);
        if (TalentTabEntry const* tab = sTalentTabStore.LookupEntry(tree))
            for (uint32 i = 0; i < MAX_MASTERY_SPELLS; ++i)
                if (uint32 mastery = tab->MasterySpellID[i])
                {
                    player->RemoveAurasDueToSpell(mastery);
                    player->RemoveSpell(mastery, true);
                }
        player->SetPrimaryTalentTree(spec, 0);
        player->SendTalentsInfoData(false);
    }

    // LearnPrimaryTalentSpecialization only casts the mastery when CanUseMastery() (the class "Mastery" spell
    // is known) and never adds it to the spellbook: learn it as a spell (passive -> the aura is applied)
    void LearnMastery(Player* player)
    {
        TalentTabEntry const* tab = sTalentTabStore.LookupEntry(player->GetPrimaryTalentTree(player->GetActiveSpec()));
        if (!tab)
            return;
        for (uint32 i = 0; i < MAX_MASTERY_SPELLS; ++i)
            if (uint32 mastery = tab->MasterySpellID[i])
                if (sSpellMgr->GetSpellInfo(mastery) && !player->HasSpell(mastery))
                    player->LearnSpell(mastery, false);
    }

    void ApplySpec(Player* player, uint32 index)
    {
        ClearPrimary(player);
        if (player->LearnPrimaryTalentSpecialization(uint8(index - 1)))
            LearnMastery(player);
        SendState(player);
    }

    void HandleGet(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendSpells(player);
        SendState(player);
    }

    void HandleSet(Player* player, std::vector<std::string> const& args)
    {
        if (args.empty() || player->IsInCombat())
            return;
        uint32 index = uint32(std::strtoul(args[0].c_str(), nullptr, 10));
        if (index < 1 || index > MAX_TALENT_TABS)
            return;
        if (PrimaryIndex(player, player->GetActiveSpec()) == index)
        {
            SendState(player);
            return;
        }
        if (MythicPlus_TalentsLocked(player))
        {
            ChatHandler(player->GetSession()).SendSysMessage(MSG_TALENTS_LOCKED);
            SendState(player);
            return;
        }
        if (SPEC_CHANGE_SPELL)
        {
            // the change happens when the cast ends (spell_spec_change)
            s_pending[player->GetGUID().GetCounter()] = index;
            player->CastSpell(player, SPEC_CHANGE_SPELL, false);
            return;
        }
        ApplySpec(player, index);
    }
}

class spec_primary_player : public PlayerScript
{
public:
    spec_primary_player() : PlayerScript("spec_primary_player")
    {
        sAddonComm->Register(std::string("SPEC_GET"), &HandleGet);
        sAddonComm->Register(std::string("SPEC_SET"), &HandleSet);
    }

    void OnLogin(Player* player, bool /*firstLogin*/) override
    {
        SendState(player);
    }

    void OnTalentsReset(Player* player, bool /*noCost*/) override
    {
        SendState(player);
    }
};

// the specialization change cast (SPEC_CHANGE_SPELL, spell_script_names 'spell_spec_change'): the change at its end
class spell_spec_change : public SpellScript
{
    PrepareSpellScript(spell_spec_change);

    SpellCastResult CheckCast()
    {
        Player* player = GetCaster() ? GetCaster()->ToPlayer() : nullptr;
        if (player && MythicPlus_TalentsLocked(player))
        {
            ChatHandler(player->GetSession()).SendSysMessage(MSG_TALENTS_LOCKED);
            return SPELL_FAILED_DONT_REPORT;
        }
        return SPELL_CAST_OK;
    }

    void HandleAfterCast()
    {
        Player* player = GetCaster() ? GetCaster()->ToPlayer() : nullptr;
        if (!player)
            return;
        auto itr = s_pending.find(player->GetGUID().GetCounter());
        if (itr == s_pending.end())
            return;
        uint32 index = itr->second;
        s_pending.erase(itr);
        ApplySpec(player, index);
    }

    void Register() override
    {
        OnCheckCast += SpellCheckCastFn(spell_spec_change::CheckCast);
        AfterCast += SpellCastFn(spell_spec_change::HandleAfterCast);
    }
};

void AddSC_spec_primary()
{
    RegisterSpellScript(spell_spec_change);
    new spec_primary_player();
}
