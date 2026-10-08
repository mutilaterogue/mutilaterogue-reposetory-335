#include "ScriptMgr.h"
#include "AddonComm.h"
#include "Player.h"
#include "DBCStores.h"

// tree : spell1 : spell2
static void SendMasterySpells(Player* player, uint32 tree)
{
    TalentTabEntry const* tab = sTalentTabStore.LookupEntry(tree);
    if (!tab)
    {
        sAddonComm->Send(player, SMSG_CIRCLE_MASTERY_SPELL, tree, uint32(0), uint32(0));
        return;
    }

    uint32 spell1 = tab->MasterySpellID[0];
    uint32 spell2 = MAX_MASTERY_SPELLS > 1 ? tab->MasterySpellID[1] : 0;

    sAddonComm->Send(player, SMSG_CIRCLE_MASTERY_SPELL, tree, spell1, spell2);
}

// Push both talent groups plus the currently active one
static void SendTalentTrees(Player* player)
{
    if (!player)
        return;

    uint8 active = player->GetActiveSpec();

    for (uint8 spec = 0; spec < MAX_TALENT_GROUPS; ++spec)
    {
        uint32 tree = player->GetPrimaryTalentTree(spec);
        sAddonComm->Send(player, SMSG_CIRCLE_TALENT_TREE, uint32(spec), tree, uint32(active));
        SendMasterySpells(player, tree);
    }
}

class cs_talent_tree : public PlayerScript
{
public:
    cs_talent_tree() : PlayerScript("cs_talent_tree") {}

    void OnLogin(Player* player, bool /*firstLogin*/) override
    {
        SendTalentTrees(player);
    }

    void OnTalentsReset(Player* player, bool /*noCost*/) override
    {
        SendTalentTrees(player);
    }
};

// Addon message entry point - addon whispers reach OnChat
class cs_talent_tree_chat : public PlayerScript
{
public:
    cs_talent_tree_chat() : PlayerScript("cs_talent_tree_chat") {}

    void OnChat(Player* player, uint32 /*type*/, uint32 lang, std::string& msg, Player* /*receiver*/) override
    {
        if (lang != LANG_ADDON || msg.empty())
            return;

        size_t sep = msg.find('\t');
        if (sep == std::string::npos)
            return;

        sAddonComm->HandleIncoming(player, msg.substr(0, sep), msg.substr(sep + 1));
    }
};

static void RegisterTalentTreeHandlers()
{
    sAddonComm->Register(CMSG_CIRCLE_REQUEST_TALENT_TREE, [](Player* p, std::vector<std::string> const& args)
        {
            // Optional argument: a specific talent group
            if (!args.empty() && !args[0].empty())
            {
                uint32 spec = CommToUInt32(args[0], MAX_TALENT_GROUPS);
                if (spec < MAX_TALENT_GROUPS)
                {
                    uint32 tree = p->GetPrimaryTalentTree(uint8(spec));
                    sAddonComm->Send(p, SMSG_CIRCLE_TALENT_TREE,
                        spec, tree, uint32(p->GetActiveSpec()));
                    SendMasterySpells(p, tree);
                }
                return;
            }

            SendTalentTrees(p);
        });
}

void AddSC_cs_talent_tree()
{
    RegisterTalentTreeHandlers();
    new cs_talent_tree();
    new cs_talent_tree_chat();
}
