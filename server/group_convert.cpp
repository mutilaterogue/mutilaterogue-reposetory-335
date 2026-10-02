/*
 * Raid -> party for the client (3.3.5 has no ConvertToParty).
 * AddonComm: C->S "GROUP_TO_PARTY" - the leader of a raid of up to 5 members.
 * Needs core/Group_convert_to_party.patch (Group::ConvertToParty). AddSC_group_convert() in custom_script_loader.cpp.
 */

#include "ScriptMgr.h"
#include "Custom\AddonComm\AddonComm.h"
#include "Group.h"
#include "Player.h"

namespace
{
    void HandleToParty(Player* player, std::vector<std::string> const& /*args*/)
    {
        Group* group = player->GetGroup();
        if (!group || !group->isRaidGroup() || group->isBGGroup() || !group->IsLeader(player->GetGUID()))
            return;
        if (group->GetMembersCount() > MAX_GROUP_SIZE)
            return;
        group->ConvertToParty();
    }
}

class group_convert_player : public PlayerScript
{
public:
    group_convert_player() : PlayerScript("group_convert_player")
    {
        sAddonComm->Register(std::string("GROUP_TO_PARTY"), &HandleToParty);
    }
};

void AddSC_group_convert()
{
    new group_convert_player();
}
