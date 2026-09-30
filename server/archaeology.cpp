/*
 * Archaeology (Cataclysm 4.3.4) for 3.3.5.
 *
 * Data - world: archaeology_branch / archaeology_project / archaeology_site / archaeology_site_point
 * (tools/archaeology/convert_research_dbc.py from Research*.dbc and QuestPOIPoint.dbc).
 * Character - characters: character_archaeology (fragments and current project per race), character_archaeology_history,
 * character_archaeology_digsite (4 active dig sites per continent).
 *
 * Digging: Survey (80451, button on the dig site bar or /cast) inside a dig site
 * places a telescope towards the find: red > 80 yards, yellow > 40, green closer. Within 8 yards the find appears;
 * using it gives fragments of the site race and skill. After FINDS_PER_SITE finds the site is replaced on the same continent.
 *
 * Solving (ARCH_SOLVE): fragments + 12 per keystone >= project cost; keystones are taken,
 * the project goes into history, reward_item is given, a new project is picked for the race.
 *
 * AddonComm (client: Interface\FrameXML\Archaeology\Blizzard_ArchaeologyAPI.lua):
 *   "ARCH_GET"                     -> "ARCH_STATE" : "branch/fragments/project,..."  + "ARCH_HISTORY" : "project/count/firstTime,..."
 *   "ARCH_SOLVE" : branch : keystones -> "ARCH_COMPLETE" : project, "ARCH_STATE", "ARCH_HISTORY"   (error: "ARCH_ERROR" : text)
 *   "ARCH_SITES_GET"               -> "ARCH_SITE" : site : zoneName : x : y : finds (x, y - 0..10000 on the zone map) x N, "ARCH_SITES_END"
 *   Survey (80451, spell_archaeology_survey) -> telescope / find, "ARCH_DIGSITE" : site : finds : max
 *   server pushes: "ARCH_ENTER" : site : finds : max / "ARCH_LEAVE" - entering and leaving a dig site
 *
 * Setup: AddSC_archaeology(); SQL: sql/characters_archaeology.sql, sql/world_archaeology_gameobjects.sql,
 * tools/archaeology/world_archaeology.sql.
 */

// Russian strings in quotes are written as UTF-8 bytes (\xNN): otherwise the compiler converts them to the system code page ("?????" in game).
#include "ScriptMgr.h"
#include "Creature.h"
#include "SpellScript.h"
#include "ScriptedGossip.h"
#include "ScriptedCreature.h"
#include "Custom\AddonComm\AddonComm.h"
#include "DatabaseEnv.h"
#include "DBCStores.h"
#include "GameObject.h"
#include "GameObjectAI.h"
#include "Item.h"
#include "Containers.h"
#include "Log.h"
#include "Map.h"
#include "MapManager.h"
#include "Player.h"
#include "Random.h"
#include "StringFormat.h"
#include "World.h"
#include "WorldSession.h"

#include <algorithm>
#include <cmath>
#include <ctime>
#include <map>
#include <sstream>
#include <unordered_map>
#include <vector>

namespace
{
    constexpr uint32 SKILL_ARCHAEOLOGY = 794;
    constexpr uint32 SPELL_SURVEY = 80451;                        // Survey
    constexpr uint32 SITES_PER_CONTINENT = 4;
    constexpr uint32 FINDS_PER_SITE = 6;                        // Cata 4.3: 6 finds per site
    constexpr uint32 KEYSTONE_FRAGMENTS = 12;
    constexpr uint32 FRAGMENTS_MIN = 5, FRAGMENTS_MAX = 9;        // per find
    constexpr uint32 RARE_CHANCE = 10;                            // % rare project
    constexpr float FIND_DISTANCE = 8.0f;
    constexpr float FAR_DISTANCE = 80.0f, MID_DISTANCE = 40.0f;
    constexpr uint32 ZONE_CHECK_MS = 1000;

    // gameobject entries (sql/world_archaeology_gameobjects.sql)
    constexpr uint32 GO_SURVEY_RED = 207000, GO_SURVEY_YELLOW = 207001, GO_SURVEY_GREEN = 207002, GO_FIND = 207003;

    constexpr uint32 BRANCH_FOSSIL = 3;
    // continent races for sites without their own race (as in Cata: by continent)
    std::map<uint32, std::vector<uint32>> const CONTINENT_BRANCHES =
    {
        { 0,   { 1, 4, 8, 3 } },      // Eastern Kingdoms: dwarf, night elf, troll, fossil
        { 1,   { 1, 4, 8, 3 } },      // Kalimdor
        { 530, { 2, 6 } },            // Outland: draenei, orc
        { 571, { 5, 7, 4, 8 } },      // Northrend: nerubian, vrykul, night elf, troll
    };

    struct Branch { uint32 Id = 0; uint32 Keystone = 0; };
    struct Project { uint32 Id = 0; uint32 Branch = 0; bool Rare = false; uint32 Fragments = 0; uint32 Sockets = 0; uint32 RewardItem = 0; };
    struct Point { float X = 0.0f, Y = 0.0f; };
    struct Site { uint32 Id = 0; uint32 Map = 0; uint32 Branch = 0; std::vector<Point> Points; float MinX = 0, MinY = 0, MaxX = 0, MaxY = 0; };

    std::map<uint32, Branch> branches;
    std::map<uint32, Project> projects;
    std::map<uint32, std::vector<uint32>> projectsByBranch;
    std::map<uint32, Site> sites;
    std::map<uint32, std::vector<uint32>> sitesByMap;

    struct BranchState { uint32 Fragments = 0; uint32 Project = 0; };
    struct HistoryEntry { uint32 Count = 0; uint32 FirstTime = 0; };
    struct DigSite { uint32 Site = 0; uint32 Finds = 0; bool HasTarget = false; Point Target; };

    struct PlayerData
    {
        std::map<uint32, BranchState> Branches;
        std::map<uint32, HistoryEntry> History;
        std::map<uint32, std::vector<DigSite>> Digsites;   // map -> sites
        uint32 CurrentSite = 0;
        ObjectGuid FindGuid;
    };

    std::unordered_map<ObjectGuid::LowType, PlayerData> players;
    uint32 zoneTimer = ZONE_CHECK_MS;

    // ------------------------------------------------------------------ data
    void LoadData()
    {
        branches.clear(); projects.clear(); projectsByBranch.clear(); sites.clear(); sitesByMap.clear();

        if (QueryResult result = WorldDatabase.Query("SELECT CAST(id AS SIGNED), CAST(keystone_item AS SIGNED) FROM archaeology_branch"))
            do
            {
                Field* f = result->Fetch();
                Branch& b = branches[uint32(f[0].GetInt64())];
                b.Id = uint32(f[0].GetInt64());
                b.Keystone = uint32(f[1].GetInt64());
            } while (result->NextRow());

        if (QueryResult result = WorldDatabase.Query("SELECT CAST(id AS SIGNED), CAST(branch AS SIGNED), CAST(rare AS SIGNED), CAST(fragments AS SIGNED), "
            "CAST(sockets AS SIGNED), CAST(reward_item AS SIGNED) FROM archaeology_project"))
            do
            {
                Field* f = result->Fetch();
                Project& p = projects[uint32(f[0].GetInt64())];
                p.Id = uint32(f[0].GetInt64());
                p.Branch = uint32(f[1].GetInt64());
                p.Rare = f[2].GetInt64() != 0;
                p.Fragments = uint32(f[3].GetInt64());
                p.Sockets = uint32(f[4].GetInt64());
                p.RewardItem = uint32(f[5].GetInt64());
                projectsByBranch[p.Branch].push_back(p.Id);
            } while (result->NextRow());

        if (QueryResult result = WorldDatabase.Query("SELECT CAST(id AS SIGNED), CAST(map AS SIGNED), CAST(branch AS SIGNED) FROM archaeology_site WHERE enabled = 1"))
            do
            {
                Field* f = result->Fetch();
                Site& s = sites[uint32(f[0].GetInt64())];
                s.Id = uint32(f[0].GetInt64());
                s.Map = uint32(f[1].GetInt64());
                s.Branch = uint32(f[2].GetInt64());
            } while (result->NextRow());

        if (QueryResult result = WorldDatabase.Query("SELECT CAST(site AS SIGNED), x, y FROM archaeology_site_point ORDER BY site, idx"))
            do
            {
                Field* f = result->Fetch();
                auto itr = sites.find(uint32(f[0].GetInt64()));
                if (itr != sites.end())
                    itr->second.Points.push_back({ f[1].GetFloat(), f[2].GetFloat() });
            } while (result->NextRow());

        // only sites with an outline can be dug
        for (auto itr = sites.begin(); itr != sites.end();)
        {
            Site& s = itr->second;
            if (s.Points.size() < 3)
            {
                itr = sites.erase(itr);
                continue;
            }
            s.MinX = s.MaxX = s.Points[0].X;
            s.MinY = s.MaxY = s.Points[0].Y;
            for (Point const& p : s.Points)
            {
                s.MinX = std::min(s.MinX, p.X); s.MaxX = std::max(s.MaxX, p.X);
                s.MinY = std::min(s.MinY, p.Y); s.MaxY = std::max(s.MaxY, p.Y);
            }
            sitesByMap[s.Map].push_back(s.Id);
            ++itr;
        }

        TC_LOG_INFO("server.loading", ">> archaeology: {} branches, {} projects, {} dig sites with points",
            uint32(branches.size()), uint32(projects.size()), uint32(sites.size()));
    }

    bool InPolygon(std::vector<Point> const& poly, float x, float y)
    {
        bool inside = false;
        for (size_t i = 0, j = poly.size() - 1; i < poly.size(); j = i++)
            if (((poly[i].Y > y) != (poly[j].Y > y)) && (x < (poly[j].X - poly[i].X) * (y - poly[i].Y) / (poly[j].Y - poly[i].Y) + poly[i].X))
                inside = !inside;
        return inside;
    }

    Point RandomPointInSite(Site const& site)
    {
        for (int attempt = 0; attempt < 50; ++attempt)
        {
            Point p { frand(site.MinX, site.MaxX), frand(site.MinY, site.MaxY) };
            if (InPolygon(site.Points, p.X, p.Y))
                return p;
        }
        return site.Points[0];
    }

    uint32 PickProject(PlayerData const& data, uint32 branch)
    {
        auto itr = projectsByBranch.find(branch);
        if (itr == projectsByBranch.end() || itr->second.empty())
            return 0;
        std::vector<uint32> common, rare;
        for (uint32 id : itr->second)
        {
            Project const& p = projects.at(id);
            if (!p.Rare)
                common.push_back(id);
            else if (!data.History.count(id))   // rare - only once
                rare.push_back(id);
        }
        if (!rare.empty() && (common.empty() || urand(1, 100) <= RARE_CHANCE))
            return Trinity::Containers::SelectRandomContainerElement(rare);
        return common.empty() ? 0 : Trinity::Containers::SelectRandomContainerElement(common);
    }

    // ------------------------------------------------------------------ player data
    PlayerData& Data(Player* player)
    {
        return players[player->GetGUID().GetCounter()];
    }

    void SaveBranch(Player* player, uint32 branch, BranchState const& state)
    {
        CharacterDatabase.PExecute("REPLACE INTO character_archaeology (guid, branch, fragments, project) VALUES ({}, {}, {}, {})",
            player->GetGUID().GetCounter(), branch, state.Fragments, state.Project);
    }

    void SaveDigsites(Player* player, PlayerData const& data)
    {
        ObjectGuid::LowType guid = player->GetGUID().GetCounter();
        CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
        trans->Append(Trinity::StringFormat("DELETE FROM character_archaeology_digsite WHERE guid = {}", guid).c_str());
        for (auto const& [map, list] : data.Digsites)
            for (DigSite const& d : list)
                trans->Append(Trinity::StringFormat("INSERT INTO character_archaeology_digsite (guid, map, site, finds) VALUES ({}, {}, {}, {})",
                    guid, map, d.Site, d.Finds).c_str());
        CharacterDatabase.CommitTransaction(trans);
    }

    // 4 active sites on every continent (new ones are picked from free sites)
    void FillDigsites(Player* player, PlayerData& data)
    {
        bool changed = false;
        for (auto const& [map, siteIds] : sitesByMap)
        {
            std::vector<DigSite>& active = data.Digsites[map];
            std::vector<uint32> free;
            for (uint32 id : siteIds)
                if (std::none_of(active.begin(), active.end(), [id](DigSite const& d) { return d.Site == id; }))
                    free.push_back(id);
            while (active.size() < SITES_PER_CONTINENT && !free.empty())
            {
                size_t index = urand(0, uint32(free.size() - 1));
                active.push_back({ free[index], 0, false, {} });
                free.erase(free.begin() + index);
                changed = true;
            }
        }
        if (changed)
            SaveDigsites(player, data);
    }

    void LoadPlayer(Player* player)
    {
        ObjectGuid::LowType guid = player->GetGUID().GetCounter();
        PlayerData& data = players[guid];
        data = PlayerData();

        if (QueryResult result = CharacterDatabase.PQuery("SELECT CAST(branch AS SIGNED), CAST(fragments AS SIGNED), CAST(project AS SIGNED) FROM character_archaeology WHERE guid = {}", guid))
            do
            {
                Field* f = result->Fetch();
                BranchState& s = data.Branches[uint32(f[0].GetInt64())];
                s.Fragments = uint32(f[1].GetInt64());
                s.Project = uint32(f[2].GetInt64());
            } while (result->NextRow());

        if (QueryResult result = CharacterDatabase.PQuery("SELECT CAST(project AS SIGNED), CAST(count AS SIGNED), CAST(first_time AS SIGNED) FROM character_archaeology_history WHERE guid = {}", guid))
            do
            {
                Field* f = result->Fetch();
                HistoryEntry& h = data.History[uint32(f[0].GetInt64())];
                h.Count = uint32(f[1].GetInt64());
                h.FirstTime = uint32(f[2].GetInt64());
            } while (result->NextRow());

        if (QueryResult result = CharacterDatabase.PQuery("SELECT CAST(map AS SIGNED), CAST(site AS SIGNED), CAST(finds AS SIGNED) FROM character_archaeology_digsite WHERE guid = {}", guid))
            do
            {
                Field* f = result->Fetch();
                uint32 siteId = uint32(f[1].GetInt64());
                if (sites.count(siteId))
                    data.Digsites[uint32(f[0].GetInt64())].push_back({ siteId, uint32(f[2].GetInt64()), false, {} });
            } while (result->NextRow());

        // every race with projects has a current project
        for (auto const& [branchId, list] : projectsByBranch)
        {
            BranchState& s = data.Branches[branchId];
            if (!s.Project || !projects.count(s.Project))
            {
                s.Project = PickProject(data, branchId);
                SaveBranch(player, branchId, s);
            }
        }
        FillDigsites(player, data);
    }

    // ------------------------------------------------------------------ messages
    void SendState(Player* player)
    {
        PlayerData& data = Data(player);
        std::ostringstream state;
        bool first = true;
        for (auto const& [branch, s] : data.Branches)
        {
            if (!first)
                state << ',';
            state << branch << '/' << s.Fragments << '/' << s.Project;
            first = false;
        }
        sAddonComm->Send(player, "ARCH_STATE", state.str());

        std::ostringstream history;
        first = true;
        for (auto const& [project, h] : data.History)
        {
            if (!first)
                history << ',';
            history << project << '/' << h.Count << '/' << h.FirstTime;
            first = false;
        }
        sAddonComm->Send(player, "ARCH_HISTORY", history.str());
    }

    // dig sites for the world map: one message per site (zone name + coordinates 0..100 on the zone map)
    void SendSites(Player* player)
    {
        PlayerData& data = Data(player);
        LocaleConstant locale = player->GetSession()->GetSessionDbcLocale();
        for (auto const& [map, active] : data.Digsites)
        {
            Map* baseMap = sMapMgr->CreateBaseMap(map);
            for (DigSite const& d : active)
            {
                Site const& site = sites.at(d.Site);
                float cx = 0.0f, cy = 0.0f;
                for (Point const& p : site.Points)
                    cx += p.X, cy += p.Y;
                cx /= site.Points.size();
                cy /= site.Points.size();

                float z = baseMap ? baseMap->GetHeight(PHASEMASK_NORMAL, cx, cy, MAX_HEIGHT) : 0.0f;
                uint32 zone = baseMap ? baseMap->GetZoneId(PHASEMASK_NORMAL, cx, cy, z) : 0;
                AreaTableEntry const* area = sAreaTableStore.LookupEntry(zone);
                if (!area)
                    continue;
                float x = cx, y = cy;
                Map2ZoneCoordinates(x, y, zone);   // zone map percent
                sAddonComm->Send(player, "ARCH_SITE", d.Site, std::string(area->AreaName[locale]), uint32(x * 100), uint32(y * 100), d.Finds);
            }
        }
        sAddonComm->Send(player, "ARCH_SITES_END");
    }

    void SendError(Player* player, std::string const& text)
    {
        sAddonComm->Send(player, "ARCH_ERROR", text);
    }

    DigSite* CurrentDigsite(Player* player, PlayerData& data)
    {
        auto itr = data.Digsites.find(player->GetMapId());
        if (itr == data.Digsites.end())
            return nullptr;
        for (DigSite& d : itr->second)
            if (InPolygon(sites.at(d.Site).Points, player->GetPositionX(), player->GetPositionY()))
                return &d;
        return nullptr;
    }

    void AdvanceSkill(Player* player)
    {
        if (!player->HasSkill(SKILL_ARCHAEOLOGY))
            return;
        uint16 value = player->GetSkillValue(SKILL_ARCHAEOLOGY);
        uint16 max = player->GetMaxSkillValue(SKILL_ARCHAEOLOGY);
        if (value < max)
            player->SetSkill(SKILL_ARCHAEOLOGY, player->GetSkillStep(SKILL_ARCHAEOLOGY), value + 1, max);
    }

    // ------------------------------------------------------------------ handlers
    void HandleGet(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendState(player);
    }

    void HandleSitesGet(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendSites(player);
    }

    // C: branch : keystones
    void HandleSolve(Player* player, std::vector<std::string> const& args)
    {
        PlayerData& data = Data(player);
        uint32 branchId = args.size() > 0 ? CommToUInt32(args[0]) : 0;
        uint32 keystones = args.size() > 1 ? CommToUInt32(args[1]) : 0;

        auto stateItr = data.Branches.find(branchId);
        if (stateItr == data.Branches.end() || !projects.count(stateItr->second.Project))
            return;
        BranchState& state = stateItr->second;
        Project const& project = projects.at(state.Project);
        Branch const& branch = branches[branchId];

        keystones = std::min(keystones, project.Sockets);
        if (keystones && (!branch.Keystone || !player->HasItemCount(branch.Keystone, keystones)))
            return SendError(player, "\xd0\x9d\xd0\xb5\xd0\xb4\xd0\xbe\xd1\x81\xd1\x82\xd0\xb0\xd1\x82\xd0\xbe\xd1\x87\xd0\xbd\xd0\xbe \xd0\xba\xd1\x80\xd0\xb0\xd0\xb5\xd1\x83\xd0\xb3\xd0\xbe\xd0\xbb\xd1\x8c\xd0\xbd\xd1\x8b\xd1\x85 \xd0\xba\xd0\xb0\xd0\xbc\xd0\xbd\xd0\xb5\xd0\xb9.");

        uint32 fromKeystones = keystones * KEYSTONE_FRAGMENTS;
        uint32 fromFragments = project.Fragments > fromKeystones ? project.Fragments - fromKeystones : 0;
        if (state.Fragments < fromFragments)
            return SendError(player, "\xd0\x9d\xd0\xb5\xd0\xb4\xd0\xbe\xd1\x81\xd1\x82\xd0\xb0\xd1\x82\xd0\xbe\xd1\x87\xd0\xbd\xd0\xbe \xd1\x84\xd1\x80\xd0\xb0\xd0\xb3\xd0\xbc\xd0\xb5\xd0\xbd\xd1\x82\xd0\xbe\xd0\xb2.");

        if (project.RewardItem)
        {
            ItemPosCountVec dest;
            if (player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest, project.RewardItem, 1) != EQUIP_ERR_OK)
                return SendError(player, "\xd0\x9d\xd0\xb5\xd1\x82 \xd0\xbc\xd0\xb5\xd1\x81\xd1\x82\xd0\xb0 \xd0\xb2 \xd1\x81\xd1\x83\xd0\xbc\xd0\xba\xd0\xb0\xd1\x85.");
            if (Item* item = player->StoreNewItem(dest, project.RewardItem, true))
                player->SendNewItem(item, 1, true, false);
        }
        if (keystones)
            player->DestroyItemCount(branch.Keystone, keystones, true);

        state.Fragments -= fromFragments;
        HistoryEntry& history = data.History[project.Id];
        if (!history.Count)
            history.FirstTime = uint32(time(nullptr));
        ++history.Count;
        CharacterDatabase.PExecute("REPLACE INTO character_archaeology_history (guid, project, count, first_time) VALUES ({}, {}, {}, {})",
            player->GetGUID().GetCounter(), project.Id, history.Count, history.FirstTime);

        state.Project = PickProject(data, branchId);
        SaveBranch(player, branchId, state);

        sAddonComm->Send(player, "ARCH_COMPLETE", project.Id);
        SendState(player);
    }

    // can survey now (for CheckCast of spell 80451)
    bool CanSurvey(Player* player)
    {
        auto itr = players.find(player->GetGUID().GetCounter());
        return itr != players.end() && CurrentDigsite(player, itr->second) != nullptr;
    }

    void HandleSurvey(Player* player, std::vector<std::string> const& /*args*/)
    {
        PlayerData& data = Data(player);
        DigSite* dig = CurrentDigsite(player, data);
        if (!dig)
            return SendError(player, "\xd0\x97\xd0\xb4\xd0\xb5\xd1\x81\xd1\x8c \xd0\xbd\xd0\xb5\xd1\x82 \xd0\xbc\xd0\xb5\xd1\x81\xd1\x82\xd0\xb0 \xd1\x80\xd0\xb0\xd1\x81\xd0\xba\xd0\xbe\xd0\xbf\xd0\xbe\xd0\xba.");
        if (player->IsMounted() || player->IsInCombat())
            return SendError(player, "\xd0\xa1\xd0\xb5\xd0\xb9\xd1\x87\xd0\xb0\xd1\x81 \xd0\xbd\xd0\xb5\xd0\xbb\xd1\x8c\xd0\xb7\xd1\x8f \xd0\xbf\xd1\x80\xd0\xbe\xd0\xb2\xd0\xbe\xd0\xb4\xd0\xb8\xd1\x82\xd1\x8c \xd0\xb8\xd1\x81\xd1\x81\xd0\xbb\xd0\xb5\xd0\xb4\xd0\xbe\xd0\xb2\xd0\xb0\xd0\xbd\xd0\xb8\xd0\xb5.");
        if (!data.FindGuid.IsEmpty())
            if (GameObject* old = player->GetMap()->GetGameObject(data.FindGuid))
                if (old->isSpawned())
                    return SendError(player, "\xd0\x9d\xd0\xb0\xd1\x85\xd0\xbe\xd0\xb4\xd0\xba\xd0\xb0 \xd1\x83\xd0\xb6\xd0\xb5 \xd1\x80\xd1\x8f\xd0\xb4\xd0\xbe\xd0\xbc - \xd0\xb7\xd0\xb0\xd0\xb1\xd0\xb5\xd1\x80\xd0\xb8\xd1\x82\xd0\xb5 \xd0\xb5\xd1\x91.");

        Site const& site = sites.at(dig->Site);
        if (!dig->HasTarget)
        {
            dig->Target = RandomPointInSite(site);
            dig->HasTarget = true;
        }

        float px = player->GetPositionX(), py = player->GetPositionY(), pz = player->GetPositionZ();
        float dx = dig->Target.X - px, dy = dig->Target.Y - py;
        float distance = std::sqrt(dx * dx + dy * dy);

        if (distance <= FIND_DISTANCE)
        {
            float z = player->GetMapHeight(dig->Target.X, dig->Target.Y, pz + 10.0f);
            if (z <= INVALID_HEIGHT)
                z = pz;
            Position pos(dig->Target.X, dig->Target.Y, z, frand(0.0f, 2 * float(M_PI)));
            if (GameObject* go = player->SummonGameObject(GO_FIND, pos, QuaternionData::fromEulerAnglesZYX(pos.GetOrientation(), 0.0f, 0.0f), Seconds(300)))
                data.FindGuid = go->GetGUID();
            return;
        }

        uint32 entry = distance > FAR_DISTANCE ? GO_SURVEY_RED : distance > MID_DISTANCE ? GO_SURVEY_YELLOW : GO_SURVEY_GREEN;
        float angle = std::atan2(dy, dx);
        Position pos(px + std::cos(angle) * 1.5f, py + std::sin(angle) * 1.5f, pz, angle);
        player->SummonGameObject(entry, pos, QuaternionData::fromEulerAnglesZYX(angle, 0.0f, 0.0f), Seconds(8));
        // direction to the find on the dig site bar: 1 - far, 2 - closer, 3 - near; world angle in milliradians
        sAddonComm->Send(player, "ARCH_SURVEY", entry == GO_SURVEY_RED ? 1 : entry == GO_SURVEY_YELLOW ? 2 : 3, int32(angle * 1000.0f));
        sAddonComm->Send(player, "ARCH_DIGSITE", dig->Site, dig->Finds, FINDS_PER_SITE);
    }

    // find used: fragments of the site race, skill, site counter
    void CollectFind(Player* player, GameObject* go)
    {
        PlayerData& data = Data(player);
        if (data.FindGuid != go->GetGUID())
            return;
        data.FindGuid.Clear();
        go->Delete();

        DigSite* dig = CurrentDigsite(player, data);
        if (!dig)
            return;
        Site const& site = sites.at(dig->Site);

        uint32 branchId = site.Branch;
        if (!branchId)
        {
            auto itr = CONTINENT_BRANCHES.find(site.Map);
            branchId = itr != CONTINENT_BRANCHES.end() ? Trinity::Containers::SelectRandomContainerElement(itr->second) : BRANCH_FOSSIL;
        }
        BranchState& state = data.Branches[branchId];
        if (!state.Project)
            state.Project = PickProject(data, branchId);
        state.Fragments += urand(FRAGMENTS_MIN, FRAGMENTS_MAX);
        SaveBranch(player, branchId, state);
        AdvanceSkill(player);

        ++dig->Finds;
        dig->HasTarget = false;
        uint32 finds = dig->Finds;
        uint32 siteId = dig->Site;
        if (finds >= FINDS_PER_SITE)
        {
            // site exhausted - another one appears on the continent
            std::vector<DigSite>& list = data.Digsites[site.Map];
            list.erase(std::remove_if(list.begin(), list.end(), [siteId](DigSite const& d) { return d.Site == siteId; }), list.end());
            FillDigsites(player, data);
            data.CurrentSite = 0;
            sAddonComm->Send(player, "ARCH_LEAVE");
            SendSites(player);
        }
        SaveDigsites(player, data);
        sAddonComm->Send(player, "ARCH_DIGSITE", siteId, finds, FINDS_PER_SITE);
        SendState(player);
    }

    void UpdateZone(Player* player)
    {
        auto itr = players.find(player->GetGUID().GetCounter());
        if (itr == players.end())
            return;
        PlayerData& data = itr->second;
        DigSite* dig = CurrentDigsite(player, data);
        uint32 siteId = dig ? dig->Site : 0;
        if (siteId == data.CurrentSite)
            return;
        data.CurrentSite = siteId;
        if (dig)
            sAddonComm->Send(player, "ARCH_ENTER", dig->Site, dig->Finds, FINDS_PER_SITE);
        else
            sAddonComm->Send(player, "ARCH_LEAVE");
    }
}

// find (sql/world_archaeology_gameobjects.sql: ScriptName go_archaeology_find)
struct go_archaeology_find : public GameObjectAI
{
    go_archaeology_find(GameObject* go) : GameObjectAI(go) { }

    bool OnGossipHello(Player* player) override
    {
        CollectFind(player, me);
        return true;
    }
};

class archaeology_world : public WorldScript
{
public:
    archaeology_world() : WorldScript("archaeology_world") { }

    void OnStartup() override
    {
        LoadData();
    }

    void OnUpdate(uint32 diff) override
    {
        if (zoneTimer > diff)
        {
            zoneTimer -= diff;
            return;
        }
        zoneTimer = ZONE_CHECK_MS;
        for (auto const& [accountId, session] : sWorld->GetAllSessions())
            if (Player* player = session->GetPlayer())
                if (player->IsInWorld())
                    UpdateZone(player);
    }
};

class archaeology_player : public PlayerScript
{
public:
    archaeology_player() : PlayerScript("archaeology_player")
    {
        sAddonComm->Register(std::string("ARCH_GET"), &HandleGet);
        sAddonComm->Register(std::string("ARCH_SITES_GET"), &HandleSitesGet);
        sAddonComm->Register(std::string("ARCH_SOLVE"), &HandleSolve);
    }

    void OnLogin(Player* player, bool /*firstLogin*/) override
    {
        LoadPlayer(player);
    }

    void OnLogout(Player* player) override
    {
        players.erase(player->GetGUID().GetCounter());
    }
};

// 80451 - Survey: cannot be cast outside a dig site, after casting - telescope / find
class spell_archaeology_survey : public SpellScript
{
    PrepareSpellScript(spell_archaeology_survey);

    SpellCastResult CheckCast()
    {
        Player* player = GetCaster()->ToPlayer();
        if (!player || !CanSurvey(player))
            return SPELL_FAILED_NOT_HERE;
        return SPELL_CAST_OK;
    }

    void HandleAfterCast()
    {
        if (Player* player = GetCaster()->ToPlayer())
            HandleSurvey(player, {});
    }

    // Spell.dbc effects (e.g. summoning an object with MiscValue 1 -> "Gameobject Entry: 1 not created") are not needed:
    // the survey is done entirely by HandleSurvey
    void PreventEffects(SpellEffIndex effIndex)
    {
        PreventHitDefaultEffect(effIndex);
    }

    void Register() override
    {
        OnEffectLaunch += SpellEffectFn(spell_archaeology_survey::PreventEffects, EFFECT_ALL, SPELL_EFFECT_ANY);
        OnEffectHit += SpellEffectFn(spell_archaeology_survey::PreventEffects, EFFECT_ALL, SPELL_EFFECT_ANY);
        OnCheckCast += SpellCheckCastFn(spell_archaeology_survey::CheckCast);
        AfterCast += SpellCastFn(spell_archaeology_survey::HandleAfterCast);
    }
};

// Archaeology trainer (sql/world_archaeology_trainer.sql): ranks of skill 794 through gossip, no rank spells in Spell.dbc.
// Learning a rank: skill with the rank cap + Survey (80451). As in Cata: next rank by level and skill.
namespace
{
    struct ArchaeologyRank { char const* Name; uint8 Level; uint16 RequiredSkill; uint16 MaxSkill; uint32 Cost; };
    ArchaeologyRank const ARCHAEOLOGY_RANKS[] =
    {
        { "\xd0\xa3\xd1\x87\xd0\xb5\xd0\xbd\xd0\xb8\xd0\xba",          5,   0,  75,     100 },   //  1 silver
        { "\xd0\x9f\xd0\xbe\xd0\xb4\xd0\xbc\xd0\xb0\xd1\x81\xd1\x82\xd0\xb5\xd1\x80\xd1\x8c\xd0\xb5",    10,  50, 150,     500 },
        { "\xd0\xa3\xd0\xbc\xd0\xb5\xd0\xbb\xd0\xb5\xd1\x86",         20, 125, 225,   10000 },   //  1 gold
        { "\xd0\x98\xd1\x81\xd0\xba\xd1\x83\xd1\x81\xd0\xbd\xd0\xb8\xd0\xba",       35, 200, 300,   50000 },
        { "\xd0\x9c\xd0\xb0\xd1\x81\xd1\x82\xd0\xb5\xd1\x80",         50, 275, 375,  100000 },
        { "\xd0\x92\xd0\xb5\xd0\xbb\xd0\xb8\xd0\xba\xd0\xb8\xd0\xb9 \xd0\xbc\xd0\xb0\xd1\x81\xd1\x82\xd0\xb5\xd1\x80", 65, 350, 450,  250000 },
        { "\xd0\x97\xd0\xbd\xd0\xb0\xd1\x82\xd0\xbe\xd0\xba",         75, 425, 525,  500000 },
    };
    constexpr uint32 GOSSIP_ACTION_LEARN = 1000;

    std::string MoneyText(uint32 copper)
    {
        std::ostringstream text;
        if (copper >= 10000)
            text << copper / 10000 << " \xd0\xb7 ";
        if (copper % 10000 >= 100)
            text << (copper % 10000) / 100 << " \xd1\x81";
        return text.str();
    }

    // next rank that can be learned now (or nullptr)
    int NextRank(Player* player)
    {
        uint16 max = player->HasSkill(SKILL_ARCHAEOLOGY) ? player->GetMaxSkillValue(SKILL_ARCHAEOLOGY) : 0;
        for (int i = 0; i < int(std::size(ARCHAEOLOGY_RANKS)); ++i)
            if (ARCHAEOLOGY_RANKS[i].MaxSkill > max)
                return i;
        return -1;
    }
}

struct npc_archaeology_trainer : public ScriptedAI
{
    npc_archaeology_trainer(Creature* creature) : ScriptedAI(creature) { }

    bool OnGossipHello(Player* player) override
    {
        ClearGossipMenuFor(player);
        int rank = NextRank(player);
        if (rank >= 0)
        {
            ArchaeologyRank const& r = ARCHAEOLOGY_RANKS[rank];
            std::ostringstream text;
            text << "\xd0\x90\xd1\x80\xd1\x85\xd0\xb5\xd0\xbe\xd0\xbb\xd0\xbe\xd0\xb3\xd0\xb8\xd1\x8f: " << r.Name << " (\xd0\xb4\xd0\xbe " << r.MaxSkill << ") - " << MoneyText(r.Cost);
            AddGossipItemFor(player, GOSSIP_ICON_TRAINER, text.str(), GOSSIP_SENDER_MAIN, GOSSIP_ACTION_LEARN + rank);
        }
        SendGossipMenuFor(player, player->GetGossipTextId(me), me->GetGUID());
        return true;
    }

    bool OnGossipSelect(Player* player, uint32 /*menuId*/, uint32 gossipListId) override
    {
        uint32 action = player->PlayerTalkClass->GetGossipOptionAction(gossipListId);
        CloseGossipMenuFor(player);
        int rank = int(action) - int(GOSSIP_ACTION_LEARN);
        if (rank < 0 || rank >= int(std::size(ARCHAEOLOGY_RANKS)) || rank != NextRank(player))
            return true;

        ArchaeologyRank const& r = ARCHAEOLOGY_RANKS[rank];
        uint16 value = player->HasSkill(SKILL_ARCHAEOLOGY) ? player->GetSkillValue(SKILL_ARCHAEOLOGY) : 1;
        if (player->GetLevel() < r.Level)
        {
            me->Whisper(Trinity::StringFormat("\xd0\x9f\xd1\x80\xd0\xb8\xd1\x85\xd0\xbe\xd0\xb4\xd0\xb8, \xd0\xba\xd0\xbe\xd0\xb3\xd0\xb4\xd0\xb0 \xd0\xb4\xd0\xbe\xd1\x81\xd1\x82\xd0\xb8\xd0\xb3\xd0\xbd\xd0\xb5\xd1\x88\xd1\x8c {} \xd1\x83\xd1\x80\xd0\xbe\xd0\xb2\xd0\xbd\xd1\x8f.", r.Level), LANG_UNIVERSAL, player);
            return true;
        }
        if (rank > 0 && value < r.RequiredSkill)
        {
            me->Whisper(Trinity::StringFormat("\xd0\x9d\xd1\x83\xd0\xb6\xd0\xb5\xd0\xbd \xd0\xbd\xd0\xb0\xd0\xb2\xd1\x8b\xd0\xba \xd0\xb0\xd1\x80\xd1\x85\xd0\xb5\xd0\xbe\xd0\xbb\xd0\xbe\xd0\xb3\xd0\xb8\xd0\xb8 {}.", r.RequiredSkill), LANG_UNIVERSAL, player);
            return true;
        }
        if (!player->HasEnoughMoney(uint64(r.Cost)))
        {
            player->SendBuyError(BUY_ERR_NOT_ENOUGHT_MONEY, me, 0, 0);
            return true;
        }

        player->ModifyMoney(-int64(r.Cost));
        player->SetSkill(SKILL_ARCHAEOLOGY, uint16(rank + 1), std::max<uint16>(value, 1), r.MaxSkill);
        if (!player->HasSpell(SPELL_SURVEY))
            player->LearnSpell(SPELL_SURVEY, false);
        me->CastSpell(player, 483, true);   // learning visual (Learning)
        return true;
    }
};

void AddSC_archaeology()
{
    RegisterSpellScript(spell_archaeology_survey);
    RegisterCreatureAI(npc_archaeology_trainer);
    new archaeology_world();
    new archaeology_player();
    RegisterGameObjectAI(go_archaeology_find);
}
