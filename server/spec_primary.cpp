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
#include "Player.h"

#include <cstdlib>

namespace
{
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

    void HandleGet(Player* player, std::vector<std::string> const& /*args*/)
    {
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
        ClearPrimary(player);
        player->LearnPrimaryTalentSpecialization(uint8(index - 1));
        SendState(player);
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

void AddSC_spec_primary()
{
    new spec_primary_player();
}
