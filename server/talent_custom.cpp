/*
 * Retail style talents for 3.3.5: the class tree (left column) and the hero trees (middle column, one of 2-3)
 * next to the 3.3.5 spec tree. Data: world.custom_talent_tree / custom_talent_node; the character:
 * characters.character_custom_talent / character_hero_talent, per talent group (dual spec).
 *
 * Points: the 3.3.5 talent points. A rank takes one free point; Player::s_extraUsedTalentsHook
 * (core/Player_custom_talents.patch) counts them in InitTalentForLevel, so they stay spent.
 * A talent reset (trainer) also resets these trees of the active spec.
 *
 * AddonComm (client: PlayerSpells\Blizzard_PlayerSpellsCustomTalents.lua):
 *  C->S "CTAL_GET"            -> the trees of the class, the nodes, the state
 *       "CTAL_LEARN" : node   -> +1 rank
 *       "CTAL_HERO" : tree    -> pick a hero tree (another one: the old one is refunded)
 *       "CTAL_SPEC"           -> the active spec changed: the spells of its talents
 *  S->C "CTAL_TREE" : id : kind : name : icon : min level : description
 *       "CTAL_NODE" : id : tree : row : col : max rank : spells (a/b/c) : requires (a/b) : min points
 *       "CTAL_DONE"
 *       "CTAL_STATE" : spec : hero tree : node/rank,... : free points
 *
 * Setup: sql/world_custom_talents.sql, sql/characters_custom_talents.sql, core/Player_custom_talents.patch,
 * AddSC_talent_custom() in custom_script_loader.cpp.
 */

#include "ScriptMgr.h"
#include "Custom\AddonComm\AddonComm.h"
#include "DatabaseEnv.h"
#include "DBCStores.h"
#include "Log.h"
#include "Chat.h"
#include "ChatCommand.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "StringFormat.h"
#include "World.h"

#include <cstdlib>
#include <map>
#include <sstream>
#include <unordered_map>
#include <vector>

namespace
{
    struct Tree
    {
        uint32 Id = 0;
        uint32 ClassMask = 0;
        uint8 Kind = 0;             // 0 class, 1 hero
        std::string Name;
        std::string Icon;
        std::string Description;
        uint32 MinLevel = 10;
        uint32 Sort = 0;
        uint32 SpecMask = 0;        // hero trees: primary talent trees (1 << OrderIndex) they belong to, 0 = any
    };

    struct Node
    {
        uint32 Id = 0;
        uint32 TreeId = 0;
        uint32 Row = 0;
        uint32 Col = 0;
        std::vector<uint32> Spells;   // one per rank
        std::vector<uint32> Requires;
        uint32 MinPoints = 0;
        uint32 MaxRank() const { return uint32(Spells.size()); }
    };

    struct SpecState
    {
        std::map<uint32, uint32> Ranks;   // node -> rank
        uint32 Hero = 0;
    };

    std::map<uint32, Tree> s_trees;
    std::map<uint32, Node> s_nodes;
    std::unordered_map<ObjectGuid::LowType, SpecState[MAX_TALENT_GROUPS]> s_states;

    std::vector<uint32> SplitIds(std::string const& text)
    {
        std::vector<uint32> ids;
        std::string token;
        std::istringstream ss(text);
        while (std::getline(ss, token, ','))
            if (uint32 id = uint32(std::strtoul(token.c_str(), nullptr, 10)))
                ids.push_back(id);
        return ids;
    }

    std::string Join(std::vector<uint32> const& ids, char separator)
    {
        std::ostringstream ss;
        for (size_t i = 0; i < ids.size(); ++i)
            ss << (i ? std::string(1, separator) : "") << ids[i];
        return ss.str();
    }

    std::string Sanitize(std::string text)
    {
        for (char& c : text)
            if (c == ':' || c == ',')
                c = c == ':' ? ';' : ' ';
        return text;
    }

    void LoadData()
    {
        s_trees.clear();
        if (QueryResult result = WorldDatabase.Query("SELECT CAST(id AS SIGNED), CAST(class_mask AS SIGNED), CAST(kind AS SIGNED), name, icon, description, CAST(min_level AS SIGNED), CAST(sort AS SIGNED), CAST(spec_mask AS SIGNED) FROM custom_talent_tree"))
            do
            {
                Field* f = result->Fetch();
                Tree tree;
                tree.Id = uint32(f[0].GetInt64());
                tree.ClassMask = uint32(f[1].GetInt64());
                tree.Kind = uint8(f[2].GetInt64());
                tree.Name = f[3].GetString();
                tree.Icon = f[4].GetString();
                tree.Description = f[5].GetString();
                tree.MinLevel = uint32(f[6].GetInt64());
                tree.Sort = uint32(f[7].GetInt64());
                tree.SpecMask = uint32(f[8].GetInt64());
                s_trees[tree.Id] = tree;
            } while (result->NextRow());

        s_nodes.clear();
        if (QueryResult result = WorldDatabase.Query("SELECT CAST(id AS SIGNED), CAST(tree_id AS SIGNED), CAST(`row` AS SIGNED), CAST(`col` AS SIGNED), spells, requires, CAST(min_points AS SIGNED) FROM custom_talent_node"))
            do
            {
                Field* f = result->Fetch();
                Node node;
                node.Id = uint32(f[0].GetInt64());
                node.TreeId = uint32(f[1].GetInt64());
                node.Row = uint32(f[2].GetInt64());
                node.Col = uint32(f[3].GetInt64());
                node.Spells = SplitIds(f[4].GetString());
                node.Requires = SplitIds(f[5].GetString());
                node.MinPoints = uint32(f[6].GetInt64());
                if (!node.Spells.empty() && s_trees.count(node.TreeId))
                    s_nodes[node.Id] = node;
            } while (result->NextRow());

        TC_LOG_INFO("server.loading", ">> custom talents: {} trees, {} nodes", s_trees.size(), s_nodes.size());
    }

    // hero tree of the player's primary talent tree (spec_primary.cpp)? spec_mask 0 = any
    bool SpecTree(Player* player, Tree const& tree)
    {
        if (tree.Kind != 1 || !tree.SpecMask)
            return true;
        TalentTabEntry const* tab = sTalentTabStore.LookupEntry(player->GetPrimaryTalentTree(player->GetActiveSpec()));
        return tab && (tree.SpecMask & (1u << tab->OrderIndex));
    }

    bool ClassTree(Player const* player, Tree const& tree)
    {
        return (tree.ClassMask & player->GetClassMask()) != 0;
    }

    SpecState& State(Player const* player, uint8 spec)
    {
        return s_states[player->GetGUID().GetCounter()][spec < MAX_TALENT_GROUPS ? spec : 0];
    }

    uint32 SpentInTree(SpecState const& state, uint32 treeId)
    {
        uint32 spent = 0;
        for (auto const& pair : state.Ranks)
        {
            auto node = s_nodes.find(pair.first);
            if (node != s_nodes.end() && node->second.TreeId == treeId)
                spent += pair.second;
        }
        return spent;
    }

    uint32 SpentTotal(SpecState const& state)
    {
        uint32 spent = 0;
        for (auto const& pair : state.Ranks)
            spent += pair.second;
        return spent;
    }

    // Player::s_extraUsedTalentsHook: the points of the active spec
    uint32 ExtraUsedTalents(Player const* player)
    {
        auto itr = s_states.find(player->GetGUID().GetCounter());
        if (itr == s_states.end())
            return 0;
        uint8 spec = player->GetActiveSpec();
        return spec < MAX_TALENT_GROUPS ? SpentTotal(itr->second[spec]) : 0;
    }

    // the spells of the active spec learned, all the other ranks / nodes unlearned
    void ApplySpells(Player* player)
    {
        SpecState const& state = State(player, player->GetActiveSpec());
        for (auto const& pair : s_nodes)
        {
            Node const& node = pair.second;
            auto owned = state.Ranks.find(node.Id);
            uint32 rank = owned != state.Ranks.end() ? owned->second : 0;
            Tree const& tree = s_trees[node.TreeId];
            if (!ClassTree(player, tree) || (tree.Kind == 1 && (state.Hero != tree.Id || !SpecTree(player, tree))))
                rank = 0;
            for (uint32 i = 0; i < node.Spells.size(); ++i)
            {
                uint32 spell = node.Spells[i];
                if (rank && i + 1 == rank)
                {
                    if (!player->HasSpell(spell))
                        player->LearnSpell(spell, false);
                }
                else if (player->HasSpell(spell))
                    player->RemoveSpell(spell, false, false);
            }
        }
    }

    void Load(Player* player)
    {
        ObjectGuid::LowType guid = player->GetGUID().GetCounter();
        auto& states = s_states[guid];
        for (uint8 spec = 0; spec < MAX_TALENT_GROUPS; ++spec)
            states[spec] = SpecState();
        if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
            "SELECT CAST(spec AS SIGNED), CAST(node_id AS SIGNED), CAST(`rank` AS SIGNED) FROM character_custom_talent WHERE guid = {}", guid).c_str()))
            do
            {
                Field* f = result->Fetch();
                uint8 spec = uint8(f[0].GetInt64());
                uint32 node = uint32(f[1].GetInt64());
                if (spec < MAX_TALENT_GROUPS && s_nodes.count(node))
                    states[spec].Ranks[node] = std::min<uint32>(uint32(f[2].GetInt64()), s_nodes[node].MaxRank());
            } while (result->NextRow());
        if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
            "SELECT CAST(spec AS SIGNED), CAST(tree_id AS SIGNED) FROM character_hero_talent WHERE guid = {}", guid).c_str()))
            do
            {
                Field* f = result->Fetch();
                uint8 spec = uint8(f[0].GetInt64());
                if (spec < MAX_TALENT_GROUPS)
                    states[spec].Hero = uint32(f[1].GetInt64());
            } while (result->NextRow());
    }

    void SendDefinitions(Player* player)
    {
        sAddonComm->Send(player, "CTAL_RESET");
        for (auto const& pair : s_trees)
        {
            Tree const& tree = pair.second;
            if (!ClassTree(player, tree))
                continue;
            sAddonComm->Send(player, "CTAL_TREE", tree.Id, uint32(tree.Kind), Sanitize(tree.Name), Sanitize(tree.Icon), tree.MinLevel, Sanitize(tree.Description), tree.SpecMask);
            for (auto const& nodePair : s_nodes)
            {
                Node const& node = nodePair.second;
                if (node.TreeId == tree.Id)
                    sAddonComm->Send(player, "CTAL_NODE", node.Id, node.TreeId, node.Row, node.Col, node.MaxRank(),
                        Join(node.Spells, '/'), Join(node.Requires, '/'), node.MinPoints);
            }
        }
        sAddonComm->Send(player, "CTAL_DONE");
    }

    void SendState(Player* player)
    {
        uint8 spec = player->GetActiveSpec();
        SpecState const& state = State(player, spec);
        std::ostringstream list;
        bool first = true;
        for (auto const& pair : state.Ranks)
            if (pair.second)
            {
                list << (first ? "" : ",") << pair.first << '/' << pair.second;
                first = false;
            }
        sAddonComm->Send(player, "CTAL_STATE", uint32(spec), state.Hero, list.str(), player->GetFreeTalentPoints());
    }

    void SaveNode(Player* player, uint8 spec, uint32 node, uint32 rank)
    {
        ObjectGuid::LowType guid = player->GetGUID().GetCounter();
        if (rank)
            CharacterDatabase.Execute(Trinity::StringFormat(
                "REPLACE INTO character_custom_talent (guid, spec, node_id, `rank`) VALUES ({}, {}, {}, {})", guid, spec, node, rank).c_str());
        else
            CharacterDatabase.Execute(Trinity::StringFormat(
                "DELETE FROM character_custom_talent WHERE guid = {} AND spec = {} AND node_id = {}", guid, spec, node).c_str());
    }

    // the nodes of a tree back to 0, their points free again
    void RefundTree(Player* player, uint8 spec, uint32 treeId)
    {
        SpecState& state = State(player, spec);
        uint32 refund = 0;
        for (auto itr = state.Ranks.begin(); itr != state.Ranks.end();)
        {
            auto node = s_nodes.find(itr->first);
            if (node != s_nodes.end() && node->second.TreeId == treeId)
            {
                refund += itr->second;
                SaveNode(player, spec, itr->first, 0);
                itr = state.Ranks.erase(itr);
            }
            else
                ++itr;
        }
        if (spec == player->GetActiveSpec() && refund)
            player->SetFreeTalentPoints(player->GetFreeTalentPoints() + refund);
    }

    void HandleGet(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendDefinitions(player);
        SendState(player);
    }

    void HandleLearn(Player* player, std::vector<std::string> const& args)
    {
        uint32 nodeId = args.empty() ? 0 : CommToUInt32(args[0]);
        auto nodeItr = s_nodes.find(nodeId);
        if (nodeItr == s_nodes.end())
            return;
        Node const& node = nodeItr->second;
        Tree const& tree = s_trees[node.TreeId];
        uint8 spec = player->GetActiveSpec();
        SpecState& state = State(player, spec);

        bool ok = ClassTree(player, tree) && player->GetLevel() >= 10 && player->GetFreeTalentPoints() > 0;
        if (ok && tree.Kind == 1)
            ok = state.Hero == tree.Id && player->GetLevel() >= tree.MinLevel;
        uint32 rank = state.Ranks.count(node.Id) ? state.Ranks[node.Id] : 0;
        ok = ok && rank < node.MaxRank() && SpentInTree(state, node.TreeId) >= node.MinPoints;
        if (ok && !node.Requires.empty())
        {
            // retail: any connected node above at its max rank
            bool any = false;
            for (uint32 required : node.Requires)
            {
                auto req = s_nodes.find(required);
                auto owned = state.Ranks.find(required);
                if (req != s_nodes.end() && owned != state.Ranks.end() && owned->second >= req->second.MaxRank())
                    any = true;
            }
            ok = any;
        }
        if (!ok)
        {
            SendState(player);
            return;
        }

        state.Ranks[node.Id] = rank + 1;
        player->SetFreeTalentPoints(player->GetFreeTalentPoints() - 1);
        SaveNode(player, spec, node.Id, rank + 1);
        ApplySpells(player);
        SendState(player);
    }

    void HandleHero(Player* player, std::vector<std::string> const& args)
    {
        uint32 treeId = args.empty() ? 0 : CommToUInt32(args[0]);
        auto itr = s_trees.find(treeId);
        if (itr == s_trees.end() || itr->second.Kind != 1 || !ClassTree(player, itr->second) || !SpecTree(player, itr->second) || player->GetLevel() < itr->second.MinLevel)
            return;
        uint8 spec = player->GetActiveSpec();
        SpecState& state = State(player, spec);
        if (state.Hero == treeId)
            return;
        if (state.Hero)
            RefundTree(player, spec, state.Hero);
        state.Hero = treeId;
        CharacterDatabase.Execute(Trinity::StringFormat(
            "REPLACE INTO character_hero_talent (guid, spec, tree_id) VALUES ({}, {}, {})", player->GetGUID().GetCounter(), spec, treeId).c_str());
        ApplySpells(player);
        SendState(player);
    }

    void HandleSpec(Player* player, std::vector<std::string> const& /*args*/)
    {
        ApplySpells(player);
        SendState(player);
    }
}

// .reload custom_talents - re-reads custom_talent_tree / custom_talent_node and resends them to everyone online
class talent_custom_commands : public CommandScript
{
public:
    talent_custom_commands() : CommandScript("talent_custom_commands") { }

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable reloadTable =
        {
            { "custom_talents", HandleReload, rbac::RBAC_PERM_COMMAND_RELOAD, Console::Yes },
        };
        static ChatCommandTable commandTable =
        {
            { "reload", reloadTable },
        };
        return commandTable;
    }

    static bool HandleReload(ChatHandler* handler)
    {
        LoadData();
        uint32 count = 0;
        for (auto const& pair : ObjectAccessor::GetPlayers())
        {
            Player* player = pair.second;
            if (!player || !player->IsInWorld())
                continue;
            SendDefinitions(player);
            ApplySpells(player);
            player->InitTalentForLevel();
            SendState(player);
            ++count;
        }
        handler->SendSysMessage(Trinity::StringFormat("Custom talents reloaded: {} trees, {} nodes, {} players updated.",
            s_trees.size(), s_nodes.size(), count));
        return true;
    }
};

class talent_custom_world : public WorldScript
{
public:
    talent_custom_world() : WorldScript("talent_custom_world") { }

    void OnStartup() override
    {
        LoadData();
        Player::s_extraUsedTalentsHook = &ExtraUsedTalents;
    }
};

class talent_custom_player : public PlayerScript
{
public:
    talent_custom_player() : PlayerScript("talent_custom_player")
    {
        sAddonComm->Register(std::string("CTAL_GET"), &HandleGet);
        sAddonComm->Register(std::string("CTAL_LEARN"), &HandleLearn);
        sAddonComm->Register(std::string("CTAL_HERO"), &HandleHero);
        sAddonComm->Register(std::string("CTAL_SPEC"), &HandleSpec);
    }

    void OnLogin(Player* player, bool /*firstLogin*/) override
    {
        Load(player);
        // the free points were computed before the trees were loaded
        player->InitTalentForLevel();
        ApplySpells(player);
    }

    void OnLogout(Player* player) override
    {
        s_states.erase(player->GetGUID().GetCounter());
    }

    // a talent reset (trainer, GM): these trees of the active spec too
    void OnTalentsReset(Player* player, bool /*noCost*/) override
    {
        uint8 spec = player->GetActiveSpec();
        SpecState& state = State(player, spec);
        for (auto const& pair : state.Ranks)
            SaveNode(player, spec, pair.first, 0);
        state.Ranks.clear();
        ApplySpells(player);
        SendState(player);
    }
};

void AddSC_talent_custom()
{
    new talent_custom_world();
    new talent_custom_commands();
    new talent_custom_player();
}
