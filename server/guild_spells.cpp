/*
 * Гильдейские заклинания (Cataclysm: SkillLine 821 «Гильдия») для 3.3.5.
 *
 * Пока персонаж в гильдии, у него есть навык 821 и все заклинания SkillLineAbility.dbc с SkillLine = 821:
 * клиент показывает их отдельной вкладкой книги, книга (SpellBookRetail) - кнопкой «Гильдия» рядом с «Общие» / «Питомец».
 * Вне гильдии навык и заклинания снимаются. Проверка - при входе, вступлении, выходе, исключении и роспуске.
 *
 * DBC: SkillLine 821 (название = GUILD, «Гильдия»; категория как у классовых веток, чтобы клиент сделал вкладку),
 *      SkillRaceClassInfo 821 для всех рас/классов, SkillLineAbility - заклинания гильдии.
 * Регистрация: AddSC_guild_spells() в custom_script_loader.cpp.
 */

#include "ScriptMgr.h"
#include "DBCStores.h"
#include "Guild.h"
#include "Player.h"

#include <vector>

namespace
{
    constexpr uint32 SKILL_GUILD = 821;

    std::vector<uint32> const& GetGuildSpells()
    {
        static std::vector<uint32> spells;
        static bool loaded = false;
        if (!loaded)
        {
            loaded = true;
            for (SkillLineAbilityEntry const* ability : sSkillLineAbilityStore)
                if (ability->SkillLine == SKILL_GUILD)
                    spells.push_back(ability->Spell);
        }
        return spells;
    }

    void UpdateGuildSpells(Player* player, bool inGuild)
    {
        if (inGuild)
        {
            if (!player->HasSkill(SKILL_GUILD))
                player->SetSkill(SKILL_GUILD, 1, 1, 1);
            for (uint32 spellId : GetGuildSpells())
                if (!player->HasSpell(spellId))
                    player->LearnSpell(spellId, false);
        }
        else
        {
            for (uint32 spellId : GetGuildSpells())
                if (player->HasSpell(spellId))
                    player->RemoveSpell(spellId, false, false);
            if (player->HasSkill(SKILL_GUILD))
                player->SetSkill(SKILL_GUILD, 0, 0, 0);
        }
    }
}

class guild_spells_player : public PlayerScript
{
public:
    guild_spells_player() : PlayerScript("guild_spells_player") { }

    void OnLogin(Player* player, bool /*firstLogin*/) override
    {
        UpdateGuildSpells(player, player->GetGuildId() != 0);
    }
};

class guild_spells_guild : public GuildScript
{
public:
    guild_spells_guild() : GuildScript("guild_spells_guild") { }

    void OnAddMember(Guild* /*guild*/, Player* player, uint8 /*plRank*/) override
    {
        if (player)
            UpdateGuildSpells(player, true);
    }

    void OnRemoveMember(Guild* /*guild*/, Player* player, bool /*isDisbanding*/, bool /*isKicked*/) override
    {
        if (player)
            UpdateGuildSpells(player, false);
    }
};

void AddSC_guild_spells()
{
    new guild_spells_player();
    new guild_spells_guild();
}
