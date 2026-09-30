/*
 * Наборы талантов (ретейл: ClassTalents loadouts, C_ClassTalents.SaveConfig / LoadConfig) для 3.3.5.
 *
 * Набор - сохранённая раскладка талантов для специализации (talent group 0/1). Применение: бесплатный
 * сброс талантов активной специализации и изучение сохранённых рангов по рядам (Player::LearnTalent
 * сам проверяет очки, ряды и требования). Только вне боя. Наборов на специализацию - MAX_LOADOUTS.
 *
 * AddonComm (клиент: PlayerSpells\Blizzard_PlayerSpellsLoadouts.lua):
 *   "TLOAD_GET"                          -> "TLOAD" : id : name (xN), "TLOAD_END" : activeId : max
 *   "TLOAD_SAVE" : id (0 - новый) : name -> сохранить текущие таланты активной специализации, затем список
 *   "TLOAD_RENAME" : id : name, "TLOAD_DEL" : id  -> список
 *   "TLOAD_APPLY" : id                   -> "TLOAD_RESULT" : ok(1/0) : код ошибки (глобальная строка клиента), затем список
 *
 * Установка: sql/characters_talent_loadouts.sql, AddSC_talent_loadouts() в custom_script_loader.cpp.
 */

#include "ScriptMgr.h"
#include "Custom\AddonComm\AddonComm.h"
#include "DatabaseEnv.h"
#include "DBCStores.h"
#include "Player.h"
#include "StringFormat.h"
#include "WorldSession.h"

#include <algorithm>
#include <sstream>
#include <vector>

namespace
{
    constexpr uint32 MAX_LOADOUTS = 10;
    constexpr size_t MAX_NAME_BYTES = 48;

    struct TalentRank
    {
        uint32 TalentId;
        uint32 Rank;   // 1..5
        uint32 Tier;
    };

    std::string CleanName(std::string name)
    {
        name.erase(std::remove_if(name.begin(), name.end(), [](char c) { return c == ':' || c == '|' || c == '\\' || c == '\'' || c == '"' || c == '\n' || c == '\r'; }), name.end());
        if (name.size() > MAX_NAME_BYTES)
        {
            name.resize(MAX_NAME_BYTES);
            while (!name.empty() && (uint8(name.back()) & 0xC0) == 0x80)
                name.pop_back();
            if (!name.empty() && (uint8(name.back()) & 0x80))
                name.pop_back();
        }
        return name;
    }

    bool IsPlayerTalent(Player* player, TalentEntry const* talent)
    {
        TalentTabEntry const* tab = sTalentTabStore.LookupEntry(talent->TabID);
        return tab && (tab->ClassMask & player->GetClassMask()) != 0;
    }

    // текущие таланты специализации: "talentId/rank,..."
    std::string CurrentTalents(Player* player, uint8 spec)
    {
        std::ostringstream text;
        bool first = true;
        for (uint32 i = 0; i < sTalentStore.GetNumRows(); ++i)
        {
            TalentEntry const* talent = sTalentStore.LookupEntry(i);
            if (!talent || !IsPlayerTalent(player, talent))
                continue;
            for (int8 rank = MAX_TALENT_RANK - 1; rank >= 0; --rank)
            {
                if (talent->SpellRank[rank] && player->HasTalent(talent->SpellRank[rank], spec))
                {
                    if (!first)
                        text << ',';
                    text << talent->ID << '/' << uint32(rank + 1);
                    first = false;
                    break;
                }
            }
        }
        return text.str();
    }

    std::vector<TalentRank> ParseTalents(Player* player, std::string const& text)
    {
        std::vector<TalentRank> list;
        std::istringstream stream(text);
        std::string token;
        while (std::getline(stream, token, ','))
        {
            size_t sep = token.find('/');
            if (sep == std::string::npos)
                continue;
            uint32 talentId = CommToUInt32(token.substr(0, sep), 0);
            uint32 rank = CommToUInt32(token.substr(sep + 1), 0);
            TalentEntry const* talent = sTalentStore.LookupEntry(talentId);
            if (!talent || !rank || rank > MAX_TALENT_RANK || !IsPlayerTalent(player, talent))
                continue;
            list.push_back({ talentId, rank, talent->TierID });
        }
        // сначала верхние ряды: нижним нужны очки в ветке и требования
        std::stable_sort(list.begin(), list.end(), [](TalentRank const& a, TalentRank const& b) { return a.Tier < b.Tier; });
        return list;
    }

    uint32 Guid(Player* player)
    {
        return player->GetGUID().GetCounter();
    }

    void SendList(Player* player)
    {
        uint8 spec = player->GetActiveSpec();
        uint32 activeId = 0;
        if (QueryResult result = CharacterDatabase.PQuery("SELECT CAST(id AS SIGNED), name, CAST(active AS SIGNED) FROM character_talent_loadouts WHERE guid = {} AND spec = {} ORDER BY id", Guid(player), uint32(spec)))
        {
            do
            {
                Field* fields = result->Fetch();
                uint32 id = uint32(fields[0].GetInt64());
                sAddonComm->Send(player, "TLOAD", id, fields[1].GetString());
                if (fields[2].GetInt64())
                    activeId = id;
            } while (result->NextRow());
        }
        sAddonComm->Send(player, "TLOAD_END", activeId, MAX_LOADOUTS);
    }

    void SetActive(Player* player, uint8 spec, uint32 id)
    {
        CharacterDatabase.Execute(Trinity::StringFormat("UPDATE character_talent_loadouts SET active = (id = {}) WHERE guid = {} AND spec = {}", id, Guid(player), uint32(spec)).c_str());
    }

    void HandleGet(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendList(player);
    }

    void HandleSave(Player* player, std::vector<std::string> const& args)
    {
        uint32 id = args.size() > 0 ? CommToUInt32(args[0], 0) : 0;
        std::string name = CleanName(args.size() > 1 ? args[1] : std::string());
        uint8 spec = player->GetActiveSpec();
        std::string talents = CurrentTalents(player, spec);

        if (!id)
        {
            QueryResult count = CharacterDatabase.PQuery("SELECT CAST(COUNT(*) AS SIGNED), CAST(COALESCE(MAX(id), 0) AS SIGNED) FROM character_talent_loadouts WHERE guid = {} AND spec = {}", Guid(player), uint32(spec));
            if (count && uint64(count->Fetch()[0].GetInt64()) >= MAX_LOADOUTS)
            {
                sAddonComm->Send(player, "TLOAD_RESULT", 0, "TALENT_LOADOUT_ERR_MAX");
                return;
            }
            id = count ? uint32(count->Fetch()[1].GetInt64()) + 1 : 1;
            if (name.empty())
                name = Trinity::StringFormat("{}", id);
            CharacterDatabase.Execute(Trinity::StringFormat("INSERT INTO character_talent_loadouts (guid, spec, id, name, talents, active) VALUES ({}, {}, {}, '{}', '{}', 0)",
                Guid(player), uint32(spec), id, name, talents).c_str());
        }
        else
        {
            CharacterDatabase.Execute(Trinity::StringFormat("UPDATE character_talent_loadouts SET talents = '{}' WHERE guid = {} AND spec = {} AND id = {}",
                talents, Guid(player), uint32(spec), id).c_str());
        }
        SetActive(player, spec, id);
        sAddonComm->Send(player, "TLOAD_RESULT", 1, "TALENT_LOADOUT_SAVED");
        SendList(player);
    }

    void HandleRename(Player* player, std::vector<std::string> const& args)
    {
        uint32 id = args.size() > 0 ? CommToUInt32(args[0], 0) : 0;
        std::string name = CleanName(args.size() > 1 ? args[1] : std::string());
        if (id && !name.empty())
            CharacterDatabase.Execute(Trinity::StringFormat("UPDATE character_talent_loadouts SET name = '{}' WHERE guid = {} AND spec = {} AND id = {}",
                name, Guid(player), uint32(player->GetActiveSpec()), id).c_str());
        SendList(player);
    }

    void HandleDelete(Player* player, std::vector<std::string> const& args)
    {
        uint32 id = args.size() > 0 ? CommToUInt32(args[0], 0) : 0;
        CharacterDatabase.Execute(Trinity::StringFormat("DELETE FROM character_talent_loadouts WHERE guid = {} AND spec = {} AND id = {}",
            Guid(player), uint32(player->GetActiveSpec()), id).c_str());
        SendList(player);
    }

    void HandleApply(Player* player, std::vector<std::string> const& args)
    {
        uint32 id = args.size() > 0 ? CommToUInt32(args[0], 0) : 0;
        uint8 spec = player->GetActiveSpec();
        if (player->IsInCombat())
        {
            sAddonComm->Send(player, "TLOAD_RESULT", 0, "TALENT_LOADOUT_ERR_COMBAT");
            return;
        }
        QueryResult result = CharacterDatabase.PQuery("SELECT talents FROM character_talent_loadouts WHERE guid = {} AND spec = {} AND id = {}", Guid(player), uint32(spec), id);
        if (!result)
        {
            sAddonComm->Send(player, "TLOAD_RESULT", 0, "TALENT_LOADOUT_ERR_NOT_FOUND");
            return;
        }

        std::vector<TalentRank> talents = ParseTalents(player, result->Fetch()[0].GetString());
        player->ResetTalents(true);
        for (TalentRank const& talent : talents)
            player->LearnTalent(talent.TalentId, talent.Rank - 1);
        player->SendTalentsInfoData(false);

        // что не выучилось (не хватило очков на этом уровне) - не ошибка: ретейл тоже учит, что может
        SetActive(player, spec, id);
        sAddonComm->Send(player, "TLOAD_RESULT", 1, "TALENT_LOADOUT_APPLIED");
        SendList(player);
    }
}

class talent_loadouts_player : public PlayerScript
{
public:
    talent_loadouts_player() : PlayerScript("talent_loadouts_player")
    {
        sAddonComm->Register(std::string("TLOAD_GET"), &HandleGet);
        sAddonComm->Register(std::string("TLOAD_SAVE"), &HandleSave);
        sAddonComm->Register(std::string("TLOAD_RENAME"), &HandleRename);
        sAddonComm->Register(std::string("TLOAD_DEL"), &HandleDelete);
        sAddonComm->Register(std::string("TLOAD_APPLY"), &HandleApply);
    }
};

void AddSC_talent_loadouts()
{
    new talent_loadouts_player();
}
