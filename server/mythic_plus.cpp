/*
 * Mythic+ (retail: Challenge Mode / Mythic Keystone) for 3.3.5.
 *
 * Dungeon difficulty 3 on the client = DUNGEON_DIFFICULTY_EPIC (2) on the server (client patch: SetDungeonDifficulty).
 * A run exists for every 5-man instance of that difficulty: without a keystone it is Mythic 0
 * (bosses only, no timer), with a keystone it is Mythic+ (level, affixes, timer, enemy forces, deaths).
 *
 * Keystone: one item (KEYSTONE_ITEM), the data of the character's key (dungeon, level) is in
 * characters.character_mythic_keystone. The item and the row are kept in sync on login.
 *
 * Font of Power: gameobject FONT_ENTRY (ScriptName go_mythic_plus_font) inside the dungeon.
 * Use -> the client opens the keystone frame; the key is slotted and the run is started from there:
 *   - the key must be for this dungeon, the instance untouched (no boss killed, no run started);
 *   - every group member must be inside and alive, nobody in combat;
 *   - everybody is moved to the instance entrance, 10 s countdown behind the walls of
 *     world.mythic_plus_barrier (their models block the way), then the timer starts.
 *
 * Run:
 *   - creatures: health and damage x LEVEL_SCALE ^ (level - 1), plus Fortified / Tyrannical;
 *     max health is raised on the creature itself (lazily for creatures spawned later);
 *   - enemy forces: every hostile non-boss creature counts (world.mythic_plus_forces overrides the count),
 *     required = world.mythic_plus_dungeon.forces_required or FORCES_AUTO_PCT of the counted creatures;
 *   - bosses: creatures with CREATURE_FLAG_EXTRA_DUNGEON_BOSS found in the instance;
 *   - deaths: DEATH_PENALTY seconds each;
 *   - complete = all bosses + forces. In time: key +1..+3 (60% / 80% of the timer), new random dungeon.
 *     Timer expired: the key goes -1 at once (retail). Group members without a key get one.
 *   - completion chest CHEST_ENTRY (loot: gameobject_loot_template): at chest_x..chest_o of the dungeon row,
 *     else where the last boss died; owned by the map, not by a player.
 *   - Mythic 0 completed: members without a key get a +1 key.
 *
 * Affixes (retail ids, world.mythic_plus_affix / mythic_plus_affix_rotation):
 *   10 Fortified, 9 Tyrannical, 6 Raging, 7 Bolstering, 8 Sanguine, 11 Bursting, 12 Grievous, 4 Necrotic.
 *
 * Score: best run per dungeon (characters.character_mythic_plus_best), rating = sum of best scores.
 *
 * AddonComm (client: ChallengesUI\Blizzard_ChallengeModeCompat.lua, ObjectiveTracker):
 *  S->C "MPLUS_AFFIX" : id : name : icon : description   (all affixes, on login)
 *       "MPLUS_WEEK" : a,b,c                              (this week's affixes)
 *       "MPLUS_KEY" : mapId : level : dungeon name : time limit   (mapId 0 - no key)
 *       "MPLUS_RATING" : rating : map;level;timeMs;timed;score,...
 *       "MPLUS_FONT_OPEN" : mapId / "MPLUS_FONT_CLOSE" / "MPLUS_SLOTTED" : 0/1
 *       "MPLUS_RUN" : state : mapId : level : affixes : timeLimit : timeMs : deaths : penalty : forces : forcesMax : bossMask : bossCount
 *              state 0 none, 1 countdown (timeMs = remaining), 2 running, 3 done in time, 4 done late
 *       "MPLUS_BOSSES" : name#name#...
 *       "MPLUS_COMPLETE" : timed : upgrade : timeMs : level : newLevel : score : oldRating : newRating : mapId : name
 *       "MPLUS_MAPS" : id;name;timeLimit,...
 *       "MPLUS_VAULT" : runs this week : their levels (best first) : last week options slot;item;level;claimed,...
 *                       : raid difficulties of this week's bosses (best first) : world levels (reserved)
 *                       option slots: 1..3 dungeons, 4..6 raid, 7..9 world
 *       "MPLUS_VAULT_OPEN" (Great Vault object used)
 *       "MPLUS_RESULT" : message
 *  C->S "MPLUS_GET", "MPLUS_INSERT", "MPLUS_REMOVE", "MPLUS_START", "MPLUS_CLOSE",
 *       "MPLUS_RELEASE" (release spirit: alive at the entrance or the last killed boss)
 *
 * Also (sql/world_mythic_plus_ext.sql, sql/characters_mythic_plus_ext.sql):
 *   - per-dungeon chest / vault loot (world.mythic_plus_dungeon_loot, 0 - CHEST_ENTRY / VAULT_LOOT);
 *   - seasons (world.mythic_plus_season): rating, best runs and leaderboard per season, seasonal affix,
 *     rewards by rating (world.mythic_plus_season_reward: title / item by mail / spell);
 *   - affixes 13 Explosive, 14 Quaking, 122 Inspiring, 124 Storming, 132 Thundering;
 *   - npc_mythic_plus_keystone: key reroll (once a week, REROLL_COST) and downgrade;
 *   - "MPLUS_SEASON" : id : name : seasonal affix : its level, "MPLUS_SCORE_GET" / "MPLUS_SCORE", "MPLUS_LEADERS";
 *   - pings: "PING" / "PING_POS" (see HandlePing);
 *   - mythic items: the keystone bonus is restored on login if it was lost.
 *
 * GM: .mplus key <level> [mapId], .mplus info, .mplus complete, .mplus reset
 *
 * Setup: sql/world_mythic_plus.sql, sql/characters_mythic_plus.sql, AddSC_mythic_plus() in custom_script_loader.cpp.
 */

#include "Custom\ItemScalling\item_scaling.h"
#include "ScriptMgr.h"
#include "Custom\AddonComm\AddonComm.h"
#include "Bag.h"
#include "CharacterCache.h"
#include "DBCStores.h"
#include "ScriptedCreature.h"
#include "ScriptedGossip.h"
#include "TemporarySummon.h"
#include "Chat.h"
#include "ChatCommand.h"
#include "Creature.h"
#include "DatabaseEnv.h"
#include "GameObject.h"
#include "GameObjectAI.h"
#include "GameTime.h"
#include "Group.h"
#include "SpellHistory.h"
#include "SpellScript.h"
#include "Item.h"
#include "Log.h"
#include "LootMgr.h"
#include "Mail.h"
#include "Map.h"
#include "ObjectMgr.h"
#include "MapManager.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "RBAC.h"
#include "StringFormat.h"
#include "World.h"
#include "WorldSession.h"

#include <algorithm>
#include <cmath>
#include <cstdarg>
#include <ctime>
#include <map>
#include <random>
#include <set>
#include <sstream>
#include <unordered_map>
#include <unordered_set>
#include <vector>

using namespace Trinity::ChatCommands;

namespace
{
    // ---------------------------------------------------------------- config
    constexpr uint32 KEYSTONE_ITEM = 138019;
    constexpr uint32 FONT_ENTRY = 246779;           // Font of Power (ScriptName go_mythic_plus_font)
    constexpr uint32 CHEST_ENTRY = 252665;          // Challenger's Cache, also its gameobject_loot_template entry
    constexpr float FONT_RANGE = 10.0f;
    constexpr uint32 VAULT_LOOT = 252665;           // Great Vault options: rolled from this gameobject_loot_template
    constexpr uint32 VAULT_THRESHOLDS[3] = { 1, 4, 8 };   // runs of the week for the 1st, 2nd, 3rd option
    constexpr uint32 VAULT_RAID_LOOT = 252665;      // raid row options: rolled from this gameobject_loot_template
    constexpr uint32 VAULT_RAID_THRESHOLDS[3] = { 2, 4, 6 };  // raid bosses of the week (slots 4..6)
    // slots 7..9 - world row (delves), no progress source yet
    constexpr uint32 BATTLE_RES_INTERVAL = 10 * MINUTE * IN_MILLISECONDS;   // +1 battle res charge
    constexpr int32 MYTHIC_ILVL_PER_LEVEL = 3;      // chest items: item level +3 per keystone level
    constexpr uint32 MYTHIC_ILVL_MAX_LEVEL = 0xFFFFFFF;   // no cap: every keystone level adds MYTHIC_ILVL_PER_LEVEL    // ... up to this keystone level             // the keystone frame closes farther away than this

    constexpr uint32 MIN_KEY_LEVEL = 1;
    constexpr uint32 MAX_KEY_LEVEL = 0xFFFFFFF;          // no real cap: the scaling makes high keys impossible
    constexpr uint32 FIRST_AFFIX_LEVEL = 2;
    constexpr uint32 SECOND_AFFIX_LEVEL = 4;
    constexpr uint32 THIRD_AFFIX_LEVEL = 7;

    constexpr float LEVEL_SCALE = 1.08f;            // health and damage per level above 1
    constexpr float FORCES_AUTO_PCT = 0.75f;         // required forces when the dungeon row has 0
    constexpr uint32 COUNTDOWN_MS = 10 * IN_MILLISECONDS;
    constexpr uint32 DEATH_PENALTY = 5;             // seconds
    constexpr uint32 DEFAULT_TIME_LIMIT = 30 * MINUTE;
    constexpr uint32 CHEST_DESPAWN = 10 * MINUTE;
    constexpr time_t WEEK_EPOCH = 1704265200;       // Wed 2024-01-03 07:00 UTC - weekly reset
    constexpr float BOLSTER_RANGE = 30.0f;
    constexpr float SANGUINE_RANGE = 5.0f;
    // affix creatures (sql/world_mythic_plus_ext.sql): they do not count as enemy forces and are not scaled
    constexpr uint32 EXPLOSIVE_ENTRY = 700020;      // Explosive orb
    constexpr uint32 STORM_ENTRY = 700021;          // Storming tornado
    constexpr uint32 KEYSTONE_NPC_ENTRY = 700022;   // npc_mythic_plus_keystone
    constexpr uint32 REROLL_COST = 100 * GOLD;      // key reroll: once a week for this price
    constexpr uint32 PING_INTERVAL = 1000;          // ms between two pings of one player
    constexpr uint32 PING_DURATION = 5000;          // ms a ping stays on the receivers' screens
    constexpr uint32 PING_UPDATE = 250;             // ms between position updates
    constexpr uint32 SANGUINE_DURATION = 20 * IN_MILLISECONDS;

    enum Affix : uint32
    {
        AFFIX_NECROTIC = 4,
        AFFIX_RAGING = 6,
        AFFIX_BOLSTERING = 7,
        AFFIX_SANGUINE = 8,
        AFFIX_TYRANNICAL = 9,
        AFFIX_FORTIFIED = 10,
        AFFIX_BURSTING = 11,
        AFFIX_GRIEVOUS = 12,
        AFFIX_EXPLOSIVE = 13,
        AFFIX_QUAKING = 14,
        AFFIX_INSPIRING = 122,
        AFFIX_STORMING = 124,
        AFFIX_THUNDERING = 132,
    };

    enum RunState : uint32
    {
        RUN_NONE = 0,
        RUN_COUNTDOWN = 1,
        RUN_ACTIVE = 2,
        RUN_DONE_TIMED = 3,
        RUN_DONE_LATE = 4,
    };

    // ---------------------------------------------------------------- data
    struct DungeonInfo
    {
        uint32 MapId = 0;
        std::string Name;
        uint32 TimeLimit = DEFAULT_TIME_LIMIT;  // seconds
        uint32 ForcesRequired = 0;              // 0 - auto
        bool HasChestPos = false;               // chest_x..chest_o set in the row
        Position ChestPos;
    };

    struct AffixInfo
    {
        uint32 Id = 0;
        std::string Name;
        std::string Icon;
        std::string Description;
    };

    struct Keystone
    {
        uint32 MapId = 0;
        uint32 Level = 0;
        uint32 Week = 0;            // CurrentWeek() it was given in: gone at the weekly reset
    };

    struct BestRun
    {
        uint32 Level = 0;
        uint32 TimeMs = 0;
        bool Timed = false;
        uint32 Score = 0;
    };

    struct CreatureScale
    {
        float BaseHealth = 0.0f;    // UNIT_MOD_HEALTH BASE_VALUE before scaling
        float Applied = 1.0f;
    };

    struct PlayerDebuffs
    {
        uint32 Necrotic = 0;        // stacks
        uint32 NecroticTimer = 0;   // ms left
        uint32 Grievous = 0;
        uint32 Bursting = 0;
        uint32 BurstingTimer = 0;
    };

    struct SanguinePool
    {
        Position Pos;
        uint32 TimeLeft = SANGUINE_DURATION;
    };

    struct Boss
    {
        uint32 Entry = 0;
        std::string Name;
        bool Killed = false;
    };

    struct Run
    {
        uint32 MapId = 0;
        uint32 InstanceId = 0;
        uint32 Level = 0;                       // 0 - Mythic 0
        std::vector<uint32> Affixes;
        ObjectGuid::LowType KeyOwner = 0;
        RunState State = RUN_NONE;
        uint32 CountdownLeft = 0;
        uint32 ElapsedMs = 0;
        uint32 TimeLimit = 0;                   // seconds
        uint32 Deaths = 0;
        uint32 Forces = 0;
        uint32 ForcesMax = 0;
        bool Depleted = false;
        bool Rewarded = false;
        std::unordered_set<ObjectGuid::LowType> ChestAllowed;   // in the dungeon at completion
        std::unordered_set<ObjectGuid::LowType> ChestLooted;
        bool Started = false;                   // a keystone run was started (or a boss died - no key any more)
        std::vector<Boss> Bosses;
        std::unordered_set<ObjectGuid> Counted; // dead creatures already counted
        std::unordered_map<ObjectGuid, CreatureScale> Scaled;
        std::unordered_map<ObjectGuid, uint32> Bolster;
        std::unordered_map<ObjectGuid, PlayerDebuffs> Debuffs;
        std::vector<SanguinePool> Pools;
        Position FontPos;
        bool HasFont = false;
        Position StartPos;                      // instance entrance: players are moved here on start
        std::vector<ObjectGuid> BarrierGuids;
        Position LastBossPos;                   // where the last killed boss died
        bool HasLastBoss = false;
        uint32 SyncTimer = 0;
        uint32 TickTimer = 0;
        uint32 GrievousTimer = 0;
        uint32 BattleRes = 0;                   // charges (keystone run)
        uint32 BattleResTimer = 0;
        // new affixes
        struct AffixSummon
        {
            ObjectGuid Guid;
            uint32 TimeLeft = 0;
        };
        std::vector<AffixSummon> Orbs;          // Explosive: explode when the time is up
        std::vector<AffixSummon> Storms;        // Storming: damage around while they live
        uint32 ExplosiveTimer = 0;
        uint32 StormTimer = 0;
        uint32 QuakeTimer = 0;
        uint32 QuakeWarn = 0;                   // ms left until the quake (0 - none)
        uint32 ThunderTimer = 0;
        ObjectGuid ThunderA, ThunderB;          // marked players
        uint32 ThunderLeft = 0;
        std::unordered_set<ObjectGuid> Inspiring;
        std::unordered_set<ObjectGuid> Inspired;
    };

    std::unordered_map<uint32, DungeonInfo> s_dungeons;
    std::map<uint32, AffixInfo> s_affixes;
    std::vector<std::vector<uint32>> s_rotation;
    std::unordered_map<uint32, uint32> s_forces;             // creature entry -> count
    struct BarrierSpawn
    {
        uint32 Entry = 0;
        Position Pos;
    };
    std::unordered_map<uint32, std::vector<BarrierSpawn>> s_barriers;   // map -> walls (world.mythic_plus_barrier)
    std::unordered_map<ObjectGuid::LowType, Keystone> s_keys;
    std::unordered_map<uint32, Run> s_runs;                  // instanceId -> run
    std::unordered_map<ObjectGuid, ObjectGuid> s_fontUser;   // player -> font
    std::unordered_set<ObjectGuid> s_slotted;                // players with the key in the font
    std::unordered_map<ObjectGuid, std::pair<uint32, uint32>> s_lastInstance;
    std::unordered_map<ObjectGuid::LowType, uint32> s_mythicItems;
    std::vector<ObjectGuid> s_pendingKick;

    // per-dungeon loot (world.mythic_plus_dungeon_loot), 0 - the common entry
    struct DungeonLoot
    {
        uint32 Chest = 0;
        uint32 Vault = 0;
    };
    std::unordered_map<uint32, DungeonLoot> s_dungeonLoot;

    // seasons (world.mythic_plus_season): rating, leaderboard and rewards are per season
    struct Season
    {
        uint32 Id = 0;
        time_t Start = 0;
        std::string Name;
        uint32 Affix = 0;           // seasonal affix, added from AffixLevel
        uint32 AffixLevel = 10;
    };
    std::vector<Season> s_seasons;  // by start
    struct SeasonReward
    {
        uint32 Season = 0;
        uint32 Rating = 0;
        uint32 TitleId = 0;
        uint32 ItemId = 0;
        uint32 SpellId = 0;
    };
    std::vector<SeasonReward> s_seasonRewards;

    // pings: every receiver gets the position relative to himself until the ping expires
    struct Ping
    {
        ObjectGuid Sender;
        ObjectGuid Target;          // unit (follows it) or empty - the fixed position
        Position Pos;
        uint32 MapId = 0;
        uint32 Id = 0;
        uint32 Type = 0;
        uint32 TimeLeft = PING_DURATION;
        float Height = 0.0f;        // the marker over the target's head
        std::vector<ObjectGuid> Receivers;
    };
    std::vector<Ping> s_pings;
    std::unordered_map<ObjectGuid, uint32> s_lastPing;  // player -> game ms
    uint32 s_pingId = 0;                    // joined a group in the middle of a run    // item guid -> keystone level it dropped from   // player -> mythic map, instance

    // ---------------------------------------------------------------- strings (UTF-8)
    char const* const MSG_NOT_IN_DUNGEON = "\xd0\x9a\xd1\x83\xd0\xbf\xd0\xb5\xd0\xbb\xd1\x8c \xd1\x81\xd0\xb8\xd0\xbb\xd1\x8b \xd1\x80\xd0\xb0\xd0\xb1\xd0\xbe\xd1\x82\xd0\xb0\xd0\xb5\xd1\x82 \xd1\x82\xd0\xbe\xd0\xbb\xd1\x8c\xd0\xba\xd0\xbe \xd0\xb2 \xd1\x8d\xd0\xbf\xd0\xbe\xd1\x85\xd0\xb0\xd0\xbb\xd1\x8c\xd0\xbd\xd0\xbe\xd0\xbc \xd0\xbf\xd0\xbe\xd0\xb4\xd0\xb7\xd0\xb5\xd0\xbc\xd0\xb5\xd0\xbb\xd1\x8c\xd0\xb5.";
    char const* const MSG_NO_KEY = "\xd0\xa3 \xd0\xb2\xd0\xb0\xd1\x81 \xd0\xbd\xd0\xb5\xd1\x82 \xd1\x8d\xd0\xbf\xd0\xbe\xd1\x85\xd0\xb0\xd0\xbb\xd1\x8c\xd0\xbd\xd0\xbe\xd0\xb3\xd0\xbe \xd0\xba\xd0\xbb\xd1\x8e\xd1\x87\xd0\xb0.";
    char const* const MSG_WRONG_DUNGEON = "\xd0\xad\xd1\x82\xd0\xbe\xd1\x82 \xd0\xba\xd0\xbb\xd1\x8e\xd1\x87 \xd0\xbf\xd1\x80\xd0\xb5\xd0\xb4\xd0\xbd\xd0\xb0\xd0\xb7\xd0\xbd\xd0\xb0\xd1\x87\xd0\xb5\xd0\xbd \xd0\xb4\xd0\xbb\xd1\x8f \xd0\xb4\xd1\x80\xd1\x83\xd0\xb3\xd0\xbe\xd0\xb3\xd0\xbe \xd0\xbf\xd0\xbe\xd0\xb4\xd0\xb7\xd0\xb5\xd0\xbc\xd0\xb5\xd0\xbb\xd1\x8c\xd1\x8f.";
    char const* const MSG_ALREADY_STARTED = "\xd0\x92 \xd1\x8d\xd1\x82\xd0\xbe\xd0\xbc \xd0\xbf\xd0\xbe\xd0\xb4\xd0\xb7\xd0\xb5\xd0\xbc\xd0\xb5\xd0\xbb\xd1\x8c\xd0\xb5 \xd1\x83\xd0\xb6\xd0\xb5 \xd0\xbd\xd0\xb0\xd1\x87\xd0\xb0\xd1\x82\xd0\xbe \xd0\xb8\xd1\x81\xd0\xbf\xd1\x8b\xd1\x82\xd0\xb0\xd0\xbd\xd0\xb8\xd0\xb5 \xd0\xb8\xd0\xbb\xd0\xb8 \xd0\xbf\xd0\xbe\xd0\xb1\xd0\xb5\xd0\xb6\xd0\xb4\xd0\xb5\xd0\xbd \xd0\xb1\xd0\xbe\xd1\x81\xd1\x81.";
    char const* const MSG_NOT_SLOTTED = "\xd0\xa1\xd0\xbd\xd0\xb0\xd1\x87\xd0\xb0\xd0\xbb\xd0\xb0 \xd0\xb2\xd1\x81\xd1\x82\xd0\xb0\xd0\xb2\xd1\x8c\xd1\x82\xd0\xb5 \xd0\xba\xd0\xbb\xd1\x8e\xd1\x87.";
    char const* const MSG_GROUP_OUTSIDE = "\xd0\x92\xd1\x81\xd0\xb5 \xd1\x83\xd1\x87\xd0\xb0\xd1\x81\xd1\x82\xd0\xbd\xd0\xb8\xd0\xba\xd0\xb8 \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd1\x8b \xd0\xb4\xd0\xbe\xd0\xbb\xd0\xb6\xd0\xbd\xd1\x8b \xd0\xbd\xd0\xb0\xd1\x85\xd0\xbe\xd0\xb4\xd0\xb8\xd1\x82\xd1\x8c\xd1\x81\xd1\x8f \xd0\xb2 \xd0\xbf\xd0\xbe\xd0\xb4\xd0\xb7\xd0\xb5\xd0\xbc\xd0\xb5\xd0\xbb\xd1\x8c\xd0\xb5.";
    char const* const MSG_GROUP_DEAD = "\xd0\x92\xd1\x81\xd0\xb5 \xd1\x83\xd1\x87\xd0\xb0\xd1\x81\xd1\x82\xd0\xbd\xd0\xb8\xd0\xba\xd0\xb8 \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd1\x8b \xd0\xb4\xd0\xbe\xd0\xbb\xd0\xb6\xd0\xbd\xd1\x8b \xd0\xb1\xd1\x8b\xd1\x82\xd1\x8c \xd0\xb6\xd0\xb8\xd0\xb2\xd1\x8b.";
    char const* const MSG_IN_COMBAT = "\xd0\x9d\xd0\xb5\xd0\xbb\xd1\x8c\xd0\xb7\xd1\x8f \xd0\xbd\xd0\xb0\xd1\x87\xd0\xb0\xd1\x82\xd1\x8c \xd0\xb8\xd1\x81\xd0\xbf\xd1\x8b\xd1\x82\xd0\xb0\xd0\xbd\xd0\xb8\xd0\xb5 \xd0\xb2\xd0\xbe \xd0\xb2\xd1\x80\xd0\xb5\xd0\xbc\xd1\x8f \xd0\xb1\xd0\xbe\xd1\x8f.";
    char const* const MSG_TOO_FAR = "\xd0\x92\xd1\x8b \xd1\x81\xd0\xbb\xd0\xb8\xd1\x88\xd0\xba\xd0\xbe\xd0\xbc \xd0\xb4\xd0\xb0\xd0\xbb\xd0\xb5\xd0\xba\xd0\xbe \xd0\xbe\xd1\x82 \xd0\xba\xd1\x83\xd0\xbf\xd0\xb5\xd0\xbb\xd0\xb8 \xd1\x81\xd0\xb8\xd0\xbb\xd1\x8b.";
    char const* const MSG_STARTED = "\xd0\x98\xd1\x81\xd0\xbf\xd1\x8b\xd1\x82\xd0\xb0\xd0\xbd\xd0\xb8\xd0\xb5 \xd0\xbd\xd0\xb0\xd1\x87\xd0\xbd\xd0\xb5\xd1\x82\xd1\x81\xd1\x8f \xd1\x87\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb7 10 \xd1\x81\xd0\xb5\xd0\xba\xd1\x83\xd0\xbd\xd0\xb4.";
    char const* const MSG_NO_LEAVE = "\xd0\x9d\xd0\xb5\xd0\xbb\xd1\x8c\xd0\xb7\xd1\x8f \xd0\xbf\xd0\xbe\xd0\xba\xd0\xb8\xd0\xbd\xd1\x83\xd1\x82\xd1\x8c \xd0\xbf\xd0\xbe\xd0\xb4\xd0\xb7\xd0\xb5\xd0\xbc\xd0\xb5\xd0\xbb\xd1\x8c\xd0\xb5 \xd0\xb2\xd0\xbe \xd0\xb2\xd1\x80\xd0\xb5\xd0\xbc\xd1\x8f \xd0\xb8\xd1\x81\xd0\xbf\xd1\x8b\xd1\x82\xd0\xb0\xd0\xbd\xd0\xb8\xd1\x8f.";
    char const* const MSG_KEY_EXPIRED = "\xd0\x95\xd0\xb6\xd0\xb5\xd0\xbd\xd0\xb5\xd0\xb4\xd0\xb5\xd0\xbb\xd1\x8c\xd0\xbd\xd1\x8b\xd0\xb9 \xd1\x81\xd0\xb1\xd1\x80\xd0\xbe\xd1\x81: \xd0\xb2\xd0\xb0\xd1\x88 \xd1\x8d\xd0\xbf\xd0\xbe\xd1\x85\xd0\xb0\xd0\xbb\xd1\x8c\xd0\xbd\xd1\x8b\xd0\xb9 \xd0\xba\xd0\xbb\xd1\x8e\xd1\x87 \xd0\xb8\xd1\x81\xd1\x87\xd0\xb5\xd0\xb7.";
    char const* const MSG_HAS_KEY = "\xd0\xa3 \xd0\xb2\xd0\xb0\xd1\x81 \xd1\x83\xd0\xb6\xd0\xb5 \xd0\xb5\xd1\x81\xd1\x82\xd1\x8c \xd1\x8d\xd0\xbf\xd0\xbe\xd1\x85\xd0\xb0\xd0\xbb\xd1\x8c\xd0\xbd\xd1\x8b\xd0\xb9 \xd0\xba\xd0\xbb\xd1\x8e\xd1\x87: %s (%u). \xd0\x9d\xd0\xbe\xd0\xb2\xd1\x8b\xd0\xb9 \xd0\xba\xd0\xbb\xd1\x8e\xd1\x87 \xd0\xbd\xd0\xb5 \xd0\xb2\xd1\x8b\xd0\xb4\xd0\xb0\xd0\xbd.";
    char const* const MSG_NO_BATTLE_RES = "\xd0\x9d\xd0\xb5\xd1\x82 \xd0\xb4\xd0\xbe\xd1\x81\xd1\x82\xd1\x83\xd0\xbf\xd0\xbd\xd1\x8b\xd1\x85 \xd0\xb1\xd0\xbe\xd0\xb5\xd0\xb2\xd1\x8b\xd1\x85 \xd0\xb2\xd0\xbe\xd1\x81\xd0\xba\xd1\x80\xd0\xb5\xd1\x88\xd0\xb5\xd0\xbd\xd0\xb8\xd0\xb9.";
    char const* const MSG_BATTLE_RES = "\xd0\x91\xd0\xbe\xd0\xb5\xd0\xb2\xd0\xbe\xd0\xb5 \xd0\xb2\xd0\xbe\xd1\x81\xd0\xba\xd1\x80\xd0\xb5\xd1\x88\xd0\xb5\xd0\xbd\xd0\xb8\xd0\xb5 \xd0\xb8\xd1\x81\xd0\xbf\xd0\xbe\xd0\xbb\xd1\x8c\xd0\xb7\xd0\xbe\xd0\xb2\xd0\xb0\xd0\xbd\xd0\xbe. \xd0\x9e\xd1\x81\xd1\x82\xd0\xb0\xd0\xbb\xd0\xbe\xd1\x81\xd1\x8c: %u.";
    char const* const MSG_BATTLE_RES_GAIN = "\xd0\x9f\xd0\xbe\xd0\xbb\xd1\x83\xd1\x87\xd0\xb5\xd0\xbd \xd0\xb7\xd0\xb0\xd1\x80\xd1\x8f\xd0\xb4 \xd0\xb1\xd0\xbe\xd0\xb5\xd0\xb2\xd0\xbe\xd0\xb3\xd0\xbe \xd0\xb2\xd0\xbe\xd1\x81\xd0\xba\xd1\x80\xd0\xb5\xd1\x88\xd0\xb5\xd0\xbd\xd0\xb8\xd1\x8f. \xd0\x94\xd0\xbe\xd1\x81\xd1\x82\xd1\x83\xd0\xbf\xd0\xbd\xd0\xbe: %u.";
    char const* const MSG_GROUP_LOCKED = "\xd0\x92\xd0\xbe \xd0\xb2\xd1\x80\xd0\xb5\xd0\xbc\xd1\x8f \xd0\xb8\xd1\x81\xd0\xbf\xd1\x8b\xd1\x82\xd0\xb0\xd0\xbd\xd0\xb8\xd1\x8f \xd0\xbd\xd0\xb5\xd0\xbb\xd1\x8c\xd0\xb7\xd1\x8f \xd0\xbf\xd1\x80\xd0\xb8\xd1\x81\xd0\xbe\xd0\xb5\xd0\xb4\xd0\xb8\xd0\xbd\xd0\xb8\xd1\x82\xd1\x8c\xd1\x81\xd1\x8f \xd0\xba \xd0\xb3\xd1\x80\xd1\x83\xd0\xbf\xd0\xbf\xd0\xb5.";
    char const* const MSG_VAULT_MAIL = "\xd0\x92\xd0\xb5\xd0\xbb\xd0\xb8\xd0\xba\xd0\xbe\xd0\xb5 \xd1\x85\xd1\x80\xd0\xb0\xd0\xbd\xd0\xb8\xd0\xbb\xd0\xb8\xd1\x89\xd0\xb5";
    char const* const MSG_GO = "\xd0\x98\xd1\x81\xd0\xbf\xd1\x8b\xd1\x82\xd0\xb0\xd0\xbd\xd0\xb8\xd0\xb5 \xd0\xbd\xd0\xb0\xd1\x87\xd0\xb0\xd0\xbb\xd0\xbe\xd1\x81\xd1\x8c!";
    char const* const MSG_TIME_UP = "\xd0\x92\xd1\x80\xd0\xb5\xd0\xbc\xd1\x8f \xd0\xb2\xd1\x8b\xd1\x88\xd0\xbb\xd0\xbe! \xd0\x9a\xd0\xbb\xd1\x8e\xd1\x87 \xd0\xbf\xd0\xbe\xd1\x82\xd0\xb5\xd1\x80\xd1\x8f\xd0\xbb \xd1\x83\xd1\x80\xd0\xbe\xd0\xb2\xd0\xb5\xd0\xbd\xd1\x8c.";
    char const* const MSG_NEW_KEY = "\xd0\x92\xd1\x8b \xd0\xbf\xd0\xbe\xd0\xbb\xd1\x83\xd1\x87\xd0\xb8\xd0\xbb\xd0\xb8 \xd1\x8d\xd0\xbf\xd0\xbe\xd1\x85\xd0\xb0\xd0\xbb\xd1\x8c\xd0\xbd\xd1\x8b\xd0\xb9 \xd0\xba\xd0\xbb\xd1\x8e\xd1\x87: %s (%u).";
    char const* const MSG_KEY_UPGRADED = "\xd0\x9a\xd0\xbb\xd1\x8e\xd1\x87 \xd1\x83\xd0\xbb\xd1\x83\xd1\x87\xd1\x88\xd0\xb5\xd0\xbd: %s (%u).";
    char const* const MSG_DONE_TIMED = "\xd0\xad\xd0\xbf\xd0\xbe\xd1\x85\xd0\xb0\xd0\xbb\xd1\x8c\xd0\xbd\xd1\x8b\xd0\xb9 \xd0\xba\xd0\xbb\xd1\x8e\xd1\x87 +%u \xd0\xbf\xd1\x80\xd0\xbe\xd0\xb9\xd0\xb4\xd0\xb5\xd0\xbd \xd0\xb2 \xd1\x81\xd1\x80\xd0\xbe\xd0\xba! \xd0\x92\xd1\x80\xd0\xb5\xd0\xbc\xd1\x8f: %s (+%u)";
    char const* const MSG_DONE_LATE = "\xd0\xad\xd0\xbf\xd0\xbe\xd1\x85\xd0\xb0\xd0\xbb\xd1\x8c\xd0\xbd\xd1\x8b\xd0\xb9 \xd0\xba\xd0\xbb\xd1\x8e\xd1\x87 +%u \xd0\xbf\xd1\x80\xd0\xbe\xd0\xb9\xd0\xb4\xd0\xb5\xd0\xbd. \xd0\x92\xd1\x80\xd0\xb5\xd0\xbc\xd1\x8f: %s (\xd0\xba\xd0\xbb\xd1\x8e\xd1\x87 \xd0\xbd\xd0\xb5 \xd1\x83\xd0\xbb\xd1\x83\xd1\x87\xd1\x88\xd0\xb5\xd0\xbd)";
    char const* const MSG_DONE_ZERO = "\xd0\xad\xd0\xbf\xd0\xbe\xd1\x85\xd0\xb0\xd0\xbb\xd1\x8c\xd0\xbd\xd0\xbe\xd0\xb5 \xd0\xbf\xd0\xbe\xd0\xb4\xd0\xb7\xd0\xb5\xd0\xbc\xd0\xb5\xd0\xbb\xd1\x8c\xd0\xb5 \xd0\xbf\xd1\x80\xd0\xbe\xd0\xb9\xd0\xb4\xd0\xb5\xd0\xbd\xd0\xbe!";
    char const* const MSG_CHEST_NOT_YOURS = "\xd0\xad\xd1\x82\xd0\xbe\xd1\x82 \xd1\x81\xd1\x83\xd0\xbd\xd0\xb4\xd1\x83\xd0\xba \xd0\xbd\xd0\xb5 \xd0\xb4\xd0\xbb\xd1\x8f \xd0\xb2\xd0\xb0\xd1\x81.";
    char const* const MSG_CHEST_LOOTED = "\xd0\x92\xd1\x8b \xd1\x83\xd0\xb6\xd0\xb5 \xd0\xb7\xd0\xb0\xd0\xb1\xd1\x80\xd0\xb0\xd0\xbb\xd0\xb8 \xd1\x81\xd0\xb2\xd0\xbe\xd1\x8e \xd0\xbd\xd0\xb0\xd0\xb3\xd1\x80\xd0\xb0\xd0\xb4\xd1\x83.";
    char const* const MSG_CHEST_MAIL = "\xd0\x9d\xd0\xb0\xd0\xb3\xd1\x80\xd0\xb0\xd0\xb4\xd0\xb0 \xd0\xbf\xd1\x80\xd0\xb5\xd1\x82\xd0\xb5\xd0\xbd\xd0\xb4\xd0\xb5\xd0\xbd\xd1\x82\xd0\xb0";
    char const* const MSG_SEASON_REWARD = "\xd0\x9d\xd0\xb0\xd0\xb3\xd1\x80\xd0\xb0\xd0\xb4\xd0\xb0 \xd1\x81\xd0\xb5\xd0\xb7\xd0\xbe\xd0\xbd\xd0\xb0 \xd0\xb7\xd0\xb0 \xd1\x80\xd0\xb5\xd0\xb9\xd1\x82\xd0\xb8\xd0\xbd\xd0\xb3 %u!";
    char const* const MSG_REROLL_OPTION = "\xd0\xa1\xd0\xbc\xd0\xb5\xd0\xbd\xd0\xb8\xd1\x82\xd1\x8c \xd0\xbf\xd0\xbe\xd0\xb4\xd0\xb7\xd0\xb5\xd0\xbc\xd0\xb5\xd0\xbb\xd1\x8c\xd0\xb5 \xd0\xba\xd0\xbb\xd1\x8e\xd1\x87\xd0\xb0 (\xd1\x80\xd0\xb0\xd0\xb7 \xd0\xb2 \xd0\xbd\xd0\xb5\xd0\xb4\xd0\xb5\xd0\xbb\xd1\x8e, 100 \xd0\xb7\xd0\xbe\xd0\xbb\xd0\xbe\xd1\x82\xd1\x8b\xd1\x85)";
    char const* const MSG_DOWNGRADE_OPTION = "\xd0\x9f\xd0\xbe\xd0\xbd\xd0\xb8\xd0\xb7\xd0\xb8\xd1\x82\xd1\x8c \xd1\x83\xd1\x80\xd0\xbe\xd0\xb2\xd0\xb5\xd0\xbd\xd1\x8c \xd0\xba\xd0\xbb\xd1\x8e\xd1\x87\xd0\xb0 \xd0\xbd\xd0\xb0 1";
    char const* const MSG_REROLL_DONE = "\xd0\x9a\xd0\xbb\xd1\x8e\xd1\x87 \xd0\xb8\xd0\xb7\xd0\xbc\xd0\xb5\xd0\xbd\xd0\xb5\xd0\xbd: %s (%u).";
    char const* const MSG_REROLL_USED = "\xd0\x92\xd1\x8b \xd1\x83\xd0\xb6\xd0\xb5 \xd0\xbc\xd0\xb5\xd0\xbd\xd1\x8f\xd0\xbb\xd0\xb8 \xd0\xba\xd0\xbb\xd1\x8e\xd1\x87 \xd0\xbd\xd0\xb0 \xd1\x8d\xd1\x82\xd0\xbe\xd0\xb9 \xd0\xbd\xd0\xb5\xd0\xb4\xd0\xb5\xd0\xbb\xd0\xb5.";
    char const* const MSG_REROLL_MONEY = "\xd0\x9d\xd0\xb5\xd0\xb4\xd0\xbe\xd1\x81\xd1\x82\xd0\xb0\xd1\x82\xd0\xbe\xd1\x87\xd0\xbd\xd0\xbe \xd0\xb7\xd0\xbe\xd0\xbb\xd0\xbe\xd1\x82\xd0\xb0.";
    char const* const MSG_DOWNGRADE_DONE = "\xd0\xa3\xd1\x80\xd0\xbe\xd0\xb2\xd0\xb5\xd0\xbd\xd1\x8c \xd0\xba\xd0\xbb\xd1\x8e\xd1\x87\xd0\xb0 \xd0\xbf\xd0\xbe\xd0\xbd\xd0\xb8\xd0\xb6\xd0\xb5\xd0\xbd: %s (%u).";
    char const* const MSG_DOWNGRADE_MIN = "\xd0\x9a\xd0\xbb\xd1\x8e\xd1\x87 \xd1\x83\xd0\xb6\xd0\xb5 \xd0\xbc\xd0\xb8\xd0\xbd\xd0\xb8\xd0\xbc\xd0\xb0\xd0\xbb\xd1\x8c\xd0\xbd\xd0\xbe\xd0\xb3\xd0\xbe \xd1\x83\xd1\x80\xd0\xbe\xd0\xb2\xd0\xbd\xd1\x8f.";
    char const* const MSG_KEY_BUSY = "\xd0\x9d\xd0\xb5\xd0\xbb\xd1\x8c\xd0\xb7\xd1\x8f \xd0\xbc\xd0\xb5\xd0\xbd\xd1\x8f\xd1\x82\xd1\x8c \xd0\xba\xd0\xbb\xd1\x8e\xd1\x87 \xd0\xb2\xd0\xbe \xd0\xb2\xd1\x80\xd0\xb5\xd0\xbc\xd1\x8f \xd0\xb8\xd1\x81\xd0\xbf\xd1\x8b\xd1\x82\xd0\xb0\xd0\xbd\xd0\xb8\xd1\x8f.";
    char const* const MSG_QUAKE = "\xd0\x97\xd0\xb5\xd0\xbc\xd0\xbb\xd1\x8f \xd0\xbd\xd0\xb0\xd1\x87\xd0\xb8\xd0\xbd\xd0\xb0\xd0\xb5\xd1\x82 \xd0\xb4\xd1\x80\xd0\xbe\xd0\xb6\xd0\xb0\xd1\x82\xd1\x8c! \xd0\x9e\xd1\x82\xd0\xbe\xd0\xb9\xd0\xb4\xd0\xb8\xd1\x82\xd0\xb5 \xd0\xbe\xd1\x82 \xd1\x81\xd0\xbe\xd1\x8e\xd0\xb7\xd0\xbd\xd0\xb8\xd0\xba\xd0\xbe\xd0\xb2.";
    char const* const MSG_THUNDER = "\xd0\x92\xd1\x8b \xd0\xbe\xd1\x82\xd0\xbc\xd0\xb5\xd1\x87\xd0\xb5\xd0\xbd\xd1\x8b \xd0\xb3\xd1\x80\xd0\xbe\xd0\xb7\xd0\xbe\xd0\xb9! \xd0\x9d\xd0\xb0\xd0\xb9\xd0\xb4\xd0\xb8\xd1\x82\xd0\xb5 \xd0\xb2\xd1\x82\xd0\xbe\xd1\x80\xd0\xbe\xd0\xb3\xd0\xbe \xd0\xbe\xd1\x82\xd0\xbc\xd0\xb5\xd1\x87\xd0\xb5\xd0\xbd\xd0\xbd\xd0\xbe\xd0\xb3\xd0\xbe \xd0\xb8\xd0\xb3\xd1\x80\xd0\xbe\xd0\xba\xd0\xb0.";
    char const* const FORCES_NAME = "\xd0\x92\xd1\x80\xd0\xb0\xd0\xb6\xd0\xb5\xd1\x81\xd0\xba\xd0\xb8\xd0\xb5 \xd1\x81\xd0\xb8\xd0\xbb\xd1\x8b";

    // ---------------------------------------------------------------- helpers
    std::string Fmt(char const* format, ...)
    {
        char buf[512];
        va_list ap;
        va_start(ap, format);
        vsnprintf(buf, sizeof(buf), format, ap);
        va_end(ap);
        return buf;
    }

    std::string TimeText(uint32 ms)
    {
        uint32 sec = ms / IN_MILLISECONDS;
        return Fmt("%u.%02u", sec / 60, sec % 60);   // ':' is the AddonComm separator
    }

    std::string Sanitize(std::string text)
    {
        std::replace(text.begin(), text.end(), ':', ';');
        std::replace(text.begin(), text.end(), '#', ' ');
        return text;
    }

    uint32 CurrentWeek()
    {
        time_t now = GameTime::GetGameTime();
        return now > WEEK_EPOCH ? uint32((now - WEEK_EPOCH) / WEEK) : 0;
    }

    // seconds to the next weekly reset
    uint32 SecondsToReset()
    {
        time_t next = WEEK_EPOCH + time_t(CurrentWeek() + 1) * WEEK;
        time_t now = GameTime::GetGameTime();
        return next > now ? uint32(next - now) : 1;
    }

    // the keystone item shows "Duration": the time to the reset (retail: the key is gone on Wednesday)
    void SetKeyDuration(Player* player, Item* item)
    {
        player->RemoveItemDurations(item);
        item->SetUInt32Value(ITEM_FIELD_DURATION, SecondsToReset());
        player->AddItemDurations(item);
    }

    void UpdateKeyDuration(Player* player)
    {
        if (Item* item = player->GetItemByEntry(KEYSTONE_ITEM))
            SetKeyDuration(player, item);
    }

    Season const* CurrentSeason()
    {
        time_t now = GameTime::GetGameTime();
        Season const* current = nullptr;
        for (Season const& season : s_seasons)
            if (season.Start <= now)
                current = &season;
        return current;
    }

    uint32 CurrentSeasonId()
    {
        Season const* season = CurrentSeason();
        return season ? season->Id : 0;
    }

    std::vector<uint32> WeekAffixes()
    {
        if (s_rotation.empty())
            return { AFFIX_FORTIFIED, AFFIX_RAGING, AFFIX_GRIEVOUS };
        return s_rotation[CurrentWeek() % s_rotation.size()];
    }

    std::vector<uint32> AffixesForLevel(uint32 level)
    {
        std::vector<uint32> week = WeekAffixes();
        std::vector<uint32> result;
        if (level >= FIRST_AFFIX_LEVEL && week.size() > 0)
            result.push_back(week[0]);
        if (level >= SECOND_AFFIX_LEVEL && week.size() > 1)
            result.push_back(week[1]);
        if (level >= THIRD_AFFIX_LEVEL && week.size() > 2)
            result.push_back(week[2]);
        // seasonal affix
        if (Season const* season = CurrentSeason())
            if (season->Affix && level >= season->AffixLevel
                && std::find(result.begin(), result.end(), season->Affix) == result.end())
                result.push_back(season->Affix);
        return result;
    }

    std::string JoinIds(std::vector<uint32> const& ids)
    {
        std::ostringstream ss;
        for (size_t i = 0; i < ids.size(); ++i)
            ss << (i ? "," : "") << ids[i];
        return ss.str();
    }

    bool HasAffix(Run const& run, uint32 affix)
    {
        return run.State == RUN_ACTIVE && std::find(run.Affixes.begin(), run.Affixes.end(), affix) != run.Affixes.end();
    }

    std::string DungeonName(uint32 mapId)
    {
        auto itr = s_dungeons.find(mapId);
        return itr != s_dungeons.end() ? itr->second.Name : std::to_string(mapId);
    }

    bool IsMythicMap(Map const* map)
    {
        return map && map->IsDungeon() && !map->IsRaid() && map->GetDifficultyID() == DUNGEON_DIFFICULTY_EPIC;
    }

    Run* FindRun(Map const* map)
    {
        if (!IsMythicMap(map))
            return nullptr;
        auto itr = s_runs.find(map->GetInstanceId());
        return itr != s_runs.end() ? &itr->second : nullptr;
    }

    Map* RunMap(Run const& run)
    {
        return sMapMgr->FindMap(run.MapId, run.InstanceId);
    }

    template <typename F>
    void ForEachPlayer(Map* map, F&& func)
    {
        if (!map)
            return;
        for (auto const& ref : map->GetPlayers())
            if (Player* player = ref.GetSource())
                func(player);
    }

    void Message(Player* player, std::string const& text)
    {
        ChatHandler(player->GetSession()).SendSysMessage(text);
    }

    void Result(Player* player, std::string const& text)
    {
        sAddonComm->Send(player, "MPLUS_RESULT", Sanitize(text));
    }

    bool IsEnemyCreature(Unit const* unit)
    {
        Creature const* creature = unit ? unit->ToCreature() : nullptr;
        return creature && !creature->IsControlledByPlayer() && !creature->IsCritter() && !creature->IsTrigger()
            && !creature->IsCivilian() && creature->IsHostileToPlayers()
            // invisible helpers and event dummies cannot be killed: they must not raise the forces total
            && !creature->HasUnitFlag(UNIT_FLAG_UNINTERACTIBLE) && creature->GetMaxHealth() > 1
            && creature->GetEntry() != EXPLOSIVE_ENTRY && creature->GetEntry() != STORM_ENTRY;
    }

    // kill credit creatures of the dungeon encounters (DungeonEncounter.dbc + instance_encounters) of a map,
    // normal and heroic: the boss flag is often missing on the difficulty templates (Skarvald, Ingvar in Utgarde Keep)
    std::set<uint32> const& EncounterEntries(uint32 mapId)
    {
        static std::unordered_map<uint32, std::set<uint32>> cache;
        auto itr = cache.find(mapId);
        if (itr != cache.end())
            return itr->second;
        std::set<uint32>& entries = cache[mapId];
        for (uint32 difficulty = 0; difficulty < 2; ++difficulty)
            if (DungeonEncounterList const* encounters = sObjectMgr->GetDungeonEncounterList(mapId, Difficulty(difficulty)))
                for (auto const& encounter : *encounters)
                    if (encounter->creditType == ENCOUNTER_CREDIT_KILL_CREATURE && encounter->creditEntry)
                        entries.insert(encounter->creditEntry);
        return entries;
    }

    bool IsBoss(Creature const* creature)
    {
        if (!creature)
            return false;
        if (creature->IsDungeonBoss() || creature->isWorldBoss())
            return true;
        // the base (normal) template of the creature
        if (CreatureTemplate const* base = sObjectMgr->GetCreatureTemplate(creature->GetEntry()))
            if (base->flags_extra & CREATURE_FLAG_EXTRA_DUNGEON_BOSS)
                return true;
        return EncounterEntries(creature->GetMapId()).count(creature->GetEntry()) != 0;
    }

    uint32 ForcesValue(Creature const* creature)
    {
        auto itr = s_forces.find(creature->GetEntry());
        return itr != s_forces.end() ? itr->second : 1;
    }

    // ---------------------------------------------------------------- keystone
    void SaveKey(ObjectGuid::LowType guid, Keystone const& key)
    {
        if (key.MapId)
            CharacterDatabase.Execute(Trinity::StringFormat("REPLACE INTO character_mythic_keystone (guid, map_id, level, week) VALUES ({}, {}, {}, {})", guid, key.MapId, key.Level, key.Week).c_str());
        else
            CharacterDatabase.Execute(Trinity::StringFormat("DELETE FROM character_mythic_keystone WHERE guid = {}", guid).c_str());
    }

    void SendKey(Player* player)
    {
        auto itr = s_keys.find(player->GetGUID().GetCounter());
        if (itr == s_keys.end() || !itr->second.MapId)
            sAddonComm->Send(player, "MPLUS_KEY", 0, 0, "", 0);
        else
        {
            auto dungeon = s_dungeons.find(itr->second.MapId);
            uint32 timeLimit = dungeon != s_dungeons.end() ? dungeon->second.TimeLimit : DEFAULT_TIME_LIMIT;
            sAddonComm->Send(player, "MPLUS_KEY", itr->second.MapId, itr->second.Level, Sanitize(DungeonName(itr->second.MapId)), timeLimit);
        }
    }

    uint32 RandomDungeon(uint32 except)
    {
        std::vector<uint32> maps;
        for (auto const& pair : s_dungeons)
            if (pair.first != except || s_dungeons.size() == 1)
                maps.push_back(pair.first);
        if (maps.empty())
            return 0;
        static std::mt19937 rng(std::random_device{}());
        return maps[std::uniform_int_distribution<size_t>(0, maps.size() - 1)(rng)];
    }

    bool GiveKeyItem(Player* player)
    {
        if (player->HasItemCount(KEYSTONE_ITEM, 1, true))
        {
            UpdateKeyDuration(player);
            return true;
        }
        ItemPosCountVec dest;
        if (player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest, KEYSTONE_ITEM, 1) != EQUIP_ERR_OK)
            return false;
        if (Item* item = player->StoreNewItem(dest, KEYSTONE_ITEM, true))
        {
            SetKeyDuration(player, item);
            player->SendNewItem(item, 1, true, false);
            return true;
        }
        return false;
    }

    // offline owners: only the database row changes
    void SetKey(ObjectGuid::LowType guid, uint32 mapId, uint32 level)
    {
        Keystone& key = s_keys[guid];
        key.MapId = mapId;
        key.Level = mapId ? std::clamp(level, MIN_KEY_LEVEL, MAX_KEY_LEVEL) : 0;
        key.Week = CurrentWeek();
        SaveKey(guid, key);

        if (Player* player = ObjectAccessor::FindConnectedPlayer(ObjectGuid::Create<HighGuid::Player>(guid)))
        {
            if (mapId)
                GiveKeyItem(player);
            else
                player->DestroyItemCount(KEYSTONE_ITEM, 1, true);
            SendKey(player);
        }
    }

    bool HasKey(Player* player)
    {
        auto itr = s_keys.find(player->GetGUID().GetCounter());
        return itr != s_keys.end() && itr->second.MapId != 0;
    }

    void GrantNewKey(Player* player, uint32 level)
    {
        if (HasKey(player))
        {
            auto itr = s_keys.find(player->GetGUID().GetCounter());
            Message(player, Fmt(MSG_HAS_KEY, DungeonName(itr->second.MapId).c_str(), itr->second.Level));
            GiveKeyItem(player);    // the row is there: make sure the item is too
            return;
        }
        uint32 mapId = RandomDungeon(0);
        if (!mapId)
            return;
        SetKey(player->GetGUID().GetCounter(), mapId, level);
        Message(player, Fmt(MSG_NEW_KEY, DungeonName(mapId).c_str(), std::clamp(level, MIN_KEY_LEVEL, MAX_KEY_LEVEL)));
    }

    // ---------------------------------------------------------------- score / rating
    uint32 CalcScore(uint32 level, uint32 affixCount, bool timed, uint32 timeMs, uint32 limitSec)
    {
        float score = 20.0f + level * 7.5f + affixCount * 5.0f;
        if (timed)
        {
            float left = limitSec ? 1.0f - float(timeMs) / float(limitSec * IN_MILLISECONDS) : 0.0f;
            score += 5.0f * std::clamp(left / 0.4f, 0.0f, 1.0f);
        }
        else
            score = score * 0.5f;
        return uint32(score + 0.5f);
    }

    void SendRating(Player* player)
    {
        uint32 rating = 0;
        std::ostringstream list;
        if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
            "SELECT CAST(map_id AS SIGNED), CAST(level AS SIGNED), CAST(time_ms AS SIGNED), CAST(timed AS SIGNED), CAST(score AS SIGNED) "
            "FROM character_mythic_plus_season_best WHERE guid = {} AND season = {}", player->GetGUID().GetCounter(), CurrentSeasonId()).c_str()))
        {
            bool first = true;
            do
            {
                Field* f = result->Fetch();
                uint32 score = uint32(f[4].GetInt64());
                rating += score;
                list << (first ? "" : ",") << f[0].GetInt64() << ";" << f[1].GetInt64() << ";" << f[2].GetInt64() << ";" << f[3].GetInt64() << ";" << score;
                first = false;
            } while (result->NextRow());
        }
        sAddonComm->Send(player, "MPLUS_RATING", rating, list.str());
    }

    uint32 GetRating(ObjectGuid::LowType guid)
    {
        if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
            "SELECT CAST(COALESCE(SUM(score), 0) AS SIGNED) FROM character_mythic_plus_season_best WHERE guid = {} AND season = {}", guid, CurrentSeasonId()).c_str()))
            return uint32(result->Fetch()[0].GetInt64());
        return 0;
    }

    void SaveBest(Player* player, Run const& run, bool timed, uint32 timeMs, uint32 score)
    {
        ObjectGuid::LowType guid = player->GetGUID().GetCounter();
        // this season (rating, leaderboard)
        uint32 season = CurrentSeasonId();
        bool better = true;
        if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
            "SELECT CAST(score AS SIGNED) FROM character_mythic_plus_season_best WHERE guid = {} AND season = {} AND map_id = {}", guid, season, run.MapId).c_str()))
            better = uint32(result->Fetch()[0].GetInt64()) < score;
        if (better)
            CharacterDatabase.DirectExecute(Trinity::StringFormat(
                "REPLACE INTO character_mythic_plus_season_best (guid, season, map_id, level, time_ms, timed, score, date) VALUES ({}, {}, {}, {}, {}, {}, {}, UNIX_TIMESTAMP())",
                guid, season, run.MapId, run.Level, timeMs, timed ? 1 : 0, score).c_str());
        // all time
        if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
            "SELECT CAST(score AS SIGNED) FROM character_mythic_plus_best WHERE guid = {} AND map_id = {}", guid, run.MapId).c_str()))
            if (uint32(result->Fetch()[0].GetInt64()) >= score)
                return;
        CharacterDatabase.DirectExecute(Trinity::StringFormat(
            "REPLACE INTO character_mythic_plus_best (guid, map_id, level, time_ms, timed, affixes, score, date) VALUES ({}, {}, {}, {}, {}, '{}', {}, UNIX_TIMESTAMP())",
            guid, run.MapId, run.Level, timeMs, timed ? 1 : 0, JoinIds(run.Affixes), score).c_str());
    }

    // ---------------------------------------------------------------- season rewards (world.mythic_plus_season_reward)
    void MailItem(Player* player, uint32 itemId, char const* subject)
    {
        CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
        MailDraft draft(subject, "");
        if (Item* item = Item::CreateItem(itemId, 1, player))
        {
            item->SaveToDB(trans);
            draft.AddItem(item);
        }
        draft.SendMailTo(trans, MailReceiver(player), MailSender(MAIL_NORMAL, 0, MAIL_STATIONERY_GM));
        CharacterDatabase.CommitTransaction(trans);
    }

    void CheckSeasonRewards(Player* player)
    {
        uint32 season = CurrentSeasonId();
        if (!season)
            return;
        ObjectGuid::LowType guid = player->GetGUID().GetCounter();
        uint32 rating = GetRating(guid);
        std::set<uint32> given;
        if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
            "SELECT CAST(rating AS SIGNED) FROM character_mythic_plus_season_reward WHERE guid = {} AND season = {}", guid, season).c_str()))
            do
                given.insert(uint32(result->Fetch()[0].GetInt64()));
        while (result->NextRow());

        for (SeasonReward const& reward : s_seasonRewards)
        {
            if (reward.Season != season || reward.Rating > rating || given.count(reward.Rating))
                continue;
            CharacterDatabase.Execute(Trinity::StringFormat(
                "INSERT IGNORE INTO character_mythic_plus_season_reward (guid, season, rating) VALUES ({}, {}, {})", guid, season, reward.Rating).c_str());
            if (reward.TitleId)
                if (CharTitlesEntry const* title = sCharTitlesStore.LookupEntry(reward.TitleId))
                    player->SetTitle(title);
            if (reward.SpellId && !player->HasSpell(reward.SpellId))
                player->LearnSpell(reward.SpellId, false);
            if (reward.ItemId)
                MailItem(player, reward.ItemId, MSG_VAULT_MAIL);
            Message(player, Fmt(MSG_SEASON_REWARD, reward.Rating));
        }
    }

    // ---------------------------------------------------------------- run sync
    uint32 BossMask(Run const& run)
    {
        uint32 mask = 0;
        for (size_t i = 0; i < run.Bosses.size() && i < 32; ++i)
            if (run.Bosses[i].Killed)
                mask |= 1u << i;
        return mask;
    }

    void SendRun(Player* player, Run const& run)
    {
        uint32 time = run.State == RUN_COUNTDOWN ? run.CountdownLeft : run.ElapsedMs;
        sAddonComm->Send(player, "MPLUS_RUN", uint32(run.State), run.MapId, run.Level, JoinIds(run.Affixes), run.TimeLimit,
            time, run.Deaths, DEATH_PENALTY, run.Forces, run.ForcesMax, BossMask(run), uint32(run.Bosses.size()));
    }

    void SendBosses(Player* player, Run const& run)
    {
        std::ostringstream ss;
        LocaleConstant locale = player->GetSession()->GetSessionDbLocaleIndex();
        for (size_t i = 0; i < run.Bosses.size(); ++i)
        {
            // creature_template_locale in the player's language
            std::string name = run.Bosses[i].Name;
            if (CreatureLocale const* creatureLocale = sObjectMgr->GetCreatureLocale(run.Bosses[i].Entry))
                ObjectMgr::GetLocaleString(creatureLocale->Name, locale, name);
            ss << (i ? "#" : "") << Sanitize(name);
        }
        std::string text = ss.str();
        sAddonComm->Send(player, "MPLUS_BOSSES", text.empty() ? std::string("-") : text);
        if (run.Level)
            sAddonComm->Send(player, "MPLUS_FORCES_NAME", FORCES_NAME);
    }

    void SyncRun(Run const& run, bool withBosses = false)
    {
        ForEachPlayer(RunMap(run), [&](Player* player)
            {
                if (withBosses)
                    SendBosses(player, run);
                SendRun(player, run);
            });
    }

    // ---------------------------------------------------------------- creature scaling
    float CreatureMult(Run const& run, Creature const* creature, bool health)
    {
        if (!run.Level || run.State == RUN_NONE)
            return 1.0f;
        float mult = std::pow(LEVEL_SCALE, float(run.Level - 1));
        bool boss = IsBoss(creature);
        for (uint32 affix : run.Affixes)
        {
            if (affix == AFFIX_FORTIFIED && !boss)
                mult *= health ? 1.2f : 1.3f;
            else if (affix == AFFIX_TYRANNICAL && boss)
                mult *= health ? 1.3f : 1.15f;
        }
        auto bolster = run.Bolster.find(creature->GetGUID());
        if (bolster != run.Bolster.end())
            mult *= 1.0f + 0.2f * bolster->second;
        return mult;
    }

    void ScaleCreature(Run& run, Creature* creature)
    {
        if (!creature || !creature->IsAlive() || !IsEnemyCreature(creature))
            return;
        float mult = CreatureMult(run, creature, true);
        auto itr = run.Scaled.find(creature->GetGUID());
        if (itr == run.Scaled.end())
        {
            itr = run.Scaled.emplace(creature->GetGUID(), CreatureScale{ creature->GetFlatModifierValue(UNIT_MOD_HEALTH, BASE_VALUE), 1.0f }).first;
            // Inspiring: some non-boss enemies (20%) make themselves and the allies near them immune to crowd control
            if (std::find(run.Affixes.begin(), run.Affixes.end(), uint32(AFFIX_INSPIRING)) != run.Affixes.end()
                && !IsBoss(creature) && urand(0, 99) < 20)
                run.Inspiring.insert(creature->GetGUID());
        }
        if (std::fabs(itr->second.Applied - mult) < 0.001f)
            return;
        // through the health modifier: UpdateMaxHealth (auras, evade) keeps the scaled value
        float pct = creature->GetHealthPct();
        // keys have no cap: the health stays within uint32 (about 2 billion)
        creature->SetStatFlatModifier(UNIT_MOD_HEALTH, BASE_VALUE, std::min(itr->second.BaseHealth * mult, 2000000000.0f));
        creature->UpdateMaxHealth();
        creature->SetHealth(std::max<uint32>(1, uint32(creature->GetMaxHealth() * pct / 100.0f)));
        itr->second.Applied = mult;
    }

    // ---------------------------------------------------------------- run setup
    Run& GetOrCreateRun(Map* map)
    {
        auto itr = s_runs.find(map->GetInstanceId());
        if (itr != s_runs.end())
            return itr->second;

        Run& run = s_runs[map->GetInstanceId()];
        run.MapId = map->GetId();
        run.InstanceId = map->GetInstanceId();

        // every grid: bosses and enemy forces of the whole dungeon
        map->LoadAllCells();

        std::set<uint32> bossEntries;
        for (uint32 entry : EncounterEntries(map->GetId()))
            if (CreatureTemplate const* info = sObjectMgr->GetCreatureTemplate(entry))
                if (bossEntries.insert(entry).second)
                    run.Bosses.push_back({ entry, info->Name, false });
        // no encounter data for this map: the creatures with the boss flag
        if (bossEntries.empty())
            for (auto const& pair : map->GetCreatureBySpawnIdStore())
            {
                Creature* creature = pair.second;
                if (IsBoss(creature) && bossEntries.insert(creature->GetEntry()).second)
                    run.Bosses.push_back({ creature->GetEntry(), creature->GetName(), !creature->IsAlive() });
            }
        return run;
    }

    void CountForcesMax(Run& run, Map* map)
    {
        uint32 total = 0;
        for (auto const& pair : map->GetCreatureBySpawnIdStore())
        {
            Creature* creature = pair.second;
            if (creature->IsAlive() && IsEnemyCreature(creature) && !IsBoss(creature))
                total += ForcesValue(creature);
        }
        auto itr = s_dungeons.find(run.MapId);
        uint32 fixed = itr != s_dungeons.end() ? itr->second.ForcesRequired : 0;
        run.ForcesMax = fixed ? fixed : std::max<uint32>(1, uint32(total * FORCES_AUTO_PCT));
    }

    // ---------------------------------------------------------------- completion
    // the chest belongs to the map, not to a player: it stays when anybody leaves
    // ---------------------------------------------------------------- mythic items (chest loot)
    // weapons and armor from the chest: item level by the keystone level (ItemScaling), tooltip "\xd0\xad\xd0\xbf\xd0\xbe\xd1\x85\xd0\xb0\xd0\xbb\xd1\x8c\xd0\xbd\xd1\x8b\xd0\xb9 +N"
    void SendMythicItems(Player* player)
    {
        std::ostringstream list;
        bool first = true;
        auto add = [&](uint32 bag, uint32 slot, Item* item)
            {
                if (!item)
                    return;
                auto itr = s_mythicItems.find(item->GetGUID().GetCounter());
                if (itr == s_mythicItems.end())
                    return;
                list << (first ? "" : ",") << bag << '/' << slot << '/' << itr->second;
                first = false;
            };
        for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
            add(255, slot + 1, player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot));
        for (uint8 slot = INVENTORY_SLOT_ITEM_START; slot < INVENTORY_SLOT_ITEM_END; ++slot)
            add(0, slot - INVENTORY_SLOT_ITEM_START + 1, player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot));
        for (uint8 bagSlot = INVENTORY_SLOT_BAG_START; bagSlot < INVENTORY_SLOT_BAG_END; ++bagSlot)
            if (Bag* bag = player->GetBagByPos(bagSlot))
                for (uint32 i = 0; i < bag->GetBagSize(); ++i)
                    add(bagSlot - INVENTORY_SLOT_BAG_START + 1, i + 1, bag->GetItemByPos(uint8(i)));
        for (uint8 slot = BANK_SLOT_ITEM_START; slot < BANK_SLOT_ITEM_END; ++slot)
            add(255, slot + 1, player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot));
        for (uint8 bagSlot = BANK_SLOT_BAG_START; bagSlot < BANK_SLOT_BAG_END; ++bagSlot)
            if (Bag* bag = player->GetBagByPos(bagSlot))
                for (uint32 i = 0; i < bag->GetBagSize(); ++i)
                    add(bagSlot - BANK_SLOT_BAG_START + 5, i + 1, bag->GetItemByPos(uint8(i)));
        sAddonComm->Send(player, "MPLUS_ITEMS", list.str());
    }

    void MarkMythicItem(Player* player, Item* item, uint32 level)
    {
        ItemTemplate const* proto = item ? item->GetTemplate() : nullptr;
        if (!proto || !level || (proto->Class != ITEM_CLASS_WEAPON && proto->Class != ITEM_CLASS_ARMOR))
            return;
        ObjectGuid::LowType guid = item->GetGUID().GetCounter();
        s_mythicItems[guid] = level;
        CharacterDatabase.Execute(Trinity::StringFormat("REPLACE INTO item_mythic (item_guid, level) VALUES ({}, {})", guid, level).c_str());
        ItemScaling::SetBonus(player, item, int32(std::min(level, MYTHIC_ILVL_MAX_LEVEL)) * MYTHIC_ILVL_PER_LEVEL);
    }

    void LoadMythicItems(Player* player)
    {
        if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
            "SELECT CAST(m.item_guid AS SIGNED), CAST(m.level AS SIGNED) FROM item_mythic m JOIN item_instance i ON i.guid = m.item_guid WHERE i.owner_guid = {}",
            player->GetGUID().GetCounter()).c_str()))
            do
            {
                Field* f = result->Fetch();
                s_mythicItems[ObjectGuid::LowType(f[0].GetInt64())] = uint32(f[1].GetInt64());
            } while (result->NextRow());
    }

    // every item of the character, bank included
    template <typename F>
    void ForEachPlayerItem(Player* player, F&& func)
    {
        for (uint8 slot = EQUIPMENT_SLOT_START; slot < INVENTORY_SLOT_ITEM_END; ++slot)
            if (Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
                func(item);
        for (uint8 slot = BANK_SLOT_ITEM_START; slot < BANK_SLOT_ITEM_END; ++slot)
            if (Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
                func(item);
        auto bags = [&](uint8 first, uint8 last)
            {
                for (uint8 bagSlot = first; bagSlot < last; ++bagSlot)
                    if (Bag* bag = player->GetBagByPos(bagSlot))
                        for (uint32 i = 0; i < bag->GetBagSize(); ++i)
                            if (Item* item = bag->GetItemByPos(uint8(i)))
                                func(item);
            };
        bags(INVENTORY_SLOT_BAG_START, INVENTORY_SLOT_BAG_END);
        bags(BANK_SLOT_BAG_START, BANK_SLOT_BAG_END);
    }

    // a mythic item must have at least the item level of its keystone (the bonus may have been lost:
    // written before the item itself, server stopped without a save); upgrades only add to it
    void ReconcileMythicItems(Player* player)
    {
        ForEachPlayerItem(player, [&](Item* item)
            {
                auto itr = s_mythicItems.find(item->GetGUID().GetCounter());
                if (itr == s_mythicItems.end())
                    return;
                int32 bonus = int32(std::min(itr->second, MYTHIC_ILVL_MAX_LEVEL)) * MYTHIC_ILVL_PER_LEVEL;
                if (ItemScaling::GetBonus(item) < bonus)
                    ItemScaling::SetBonus(player, item, bonus);
            });
    }

    void HandleItemsGet(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendMythicItems(player);
    }

    GameObject* SpawnGameObject(Map* map, uint32 entry, Position const& pos, uint32 despawnSec)
    {
        if (!sObjectMgr->GetGameObjectTemplate(entry))
            return nullptr;
        GameObject* go = new GameObject();
        QuaternionData rot = QuaternionData::fromEulerAnglesZYX(pos.GetOrientation(), 0.0f, 0.0f);
        if (!go->Create(map->GenerateLowGuid<HighGuid::GameObject>(), entry, map, PHASEMASK_NORMAL, pos, rot, 255, GO_STATE_READY))
        {
            delete go;
            return nullptr;
        }
        go->SetRespawnTime(despawnSec);
        go->SetSpawnedByDefault(false);
        map->AddToMap(go);
        return go;
    }

    void SpawnChest(Map* map, Position const& pos)
    {
        SpawnGameObject(map, CHEST_ENTRY, pos, CHEST_DESPAWN);
    }

    void CompleteRun(Run& run)
    {
        if (run.Rewarded)
            return;
        run.Rewarded = true;
        Map* map = RunMap(run);

        if (!run.Level)
        {
            run.State = RUN_DONE_TIMED;
            ForEachPlayer(map, [&](Player* player)
                {
                    Message(player, MSG_DONE_ZERO);
                    GrantNewKey(player, MIN_KEY_LEVEL);
                });
            SyncRun(run);
            return;
        }

        uint32 timeMs = run.ElapsedMs + run.Deaths * DEATH_PENALTY * IN_MILLISECONDS;
        uint32 limitMs = run.TimeLimit * IN_MILLISECONDS;
        bool timed = timeMs <= limitMs;
        uint32 upgrade = !timed ? 0 : timeMs <= limitMs * 6 / 10 ? 3 : timeMs <= limitMs * 8 / 10 ? 2 : 1;
        run.State = timed ? RUN_DONE_TIMED : RUN_DONE_LATE;

        // the owner's key: in time - up and a new dungeon, late - already lowered when the time ran out
        uint32 newLevel = run.Level;
        if (run.KeyOwner)
        {
            auto itr = s_keys.find(run.KeyOwner);
            if (timed)
                newLevel = std::min(MAX_KEY_LEVEL, run.Level + upgrade);
            else
                newLevel = itr != s_keys.end() && itr->second.Level ? itr->second.Level : std::max(MIN_KEY_LEVEL, run.Level - 1);
            SetKey(run.KeyOwner, RandomDungeon(run.MapId), newLevel);
            if (Player* owner = ObjectAccessor::FindConnectedPlayer(ObjectGuid::Create<HighGuid::Player>(run.KeyOwner)))
                Message(owner, Fmt(MSG_KEY_UPGRADED, DungeonName(s_keys[run.KeyOwner].MapId).c_str(), newLevel));
        }

        uint32 score = CalcScore(run.Level, uint32(run.Affixes.size()), timed, timeMs, run.TimeLimit);
        std::string text = timed ? Fmt(MSG_DONE_TIMED, run.Level, TimeText(timeMs).c_str(), upgrade)
            : Fmt(MSG_DONE_LATE, run.Level, TimeText(timeMs).c_str());

        ForEachPlayer(map, [&](Player* player)
            {
                run.ChestAllowed.insert(player->GetGUID().GetCounter());
                Message(player, text);
                ObjectGuid::LowType guid = player->GetGUID().GetCounter();
                uint32 oldRating = GetRating(guid);
                SaveBest(player, run, timed, timeMs, score);
                uint32 newRating = GetRating(guid);
                // Great Vault: every completed keystone of the week counts
                CharacterDatabase.Execute(Trinity::StringFormat(
                    "INSERT INTO character_mythic_plus_weekly (guid, week, map_id, level) VALUES ({}, {}, {}, {})",
                    guid, CurrentWeek(), run.MapId, run.Level).c_str());
                sAddonComm->Send(player, "MPLUS_COMPLETE", timed ? 1 : 0, upgrade, timeMs, run.Level, newLevel, score,
                    oldRating, newRating, run.MapId, Sanitize(DungeonName(run.MapId)));
                if (player->GetGUID().GetCounter() != run.KeyOwner)
                    GrantNewKey(player, std::max(MIN_KEY_LEVEL, run.Level - 1));
                SendRating(player);
                CheckSeasonRewards(player);
            });

        // chest: the dungeon row position, else where the last boss died, else the Font of Power
        if (map)
        {
            auto dungeon = s_dungeons.find(run.MapId);
            if (dungeon != s_dungeons.end() && dungeon->second.HasChestPos)
                SpawnChest(map, dungeon->second.ChestPos);
            else if (run.HasLastBoss)
                SpawnChest(map, run.LastBossPos);
            else if (run.HasFont)
                SpawnChest(map, run.FontPos);
        }

        SyncRun(run);
    }

    void CheckComplete(Run& run)
    {
        if (run.Rewarded || run.Bosses.empty())
            return;
        if (run.Level && run.State != RUN_ACTIVE)
            return;
        for (Boss const& boss : run.Bosses)
            if (!boss.Killed)
                return;
        if (run.Level && run.Forces < run.ForcesMax)
            return;
        CompleteRun(run);
    }

    // ---------------------------------------------------------------- deaths
    void OnCreatureDeath(Run& run, Creature* creature)
    {
        if (!run.Counted.insert(creature->GetGUID()).second)
            return;

        if (IsBoss(creature))
        {
            run.LastBossPos = creature->GetPosition();
            run.HasLastBoss = true;
            bool found = false;
            for (Boss& boss : run.Bosses)
                if (boss.Entry == creature->GetEntry() && !boss.Killed)
                {
                    boss.Killed = true;
                    found = true;
                    break;
                }
            // a boss not in the list: added only when the map has no encounter data (else it is a helper of an encounter)
            if (!found && EncounterEntries(run.MapId).empty()
                && std::none_of(run.Bosses.begin(), run.Bosses.end(), [&](Boss const& b) { return b.Entry == creature->GetEntry(); }))
            {
                run.Bosses.push_back({ creature->GetEntry(), creature->GetName(), true });
                SyncRun(run, true);
            }
            // a boss killed before the keystone - the instance cannot take one any more
            if (run.State == RUN_NONE)
                run.Started = true;
            SyncRun(run);
            CheckComplete(run);
            return;
        }

        if (!IsEnemyCreature(creature) || run.State != RUN_ACTIVE)
            return;

        run.Forces = std::min(run.ForcesMax, run.Forces + ForcesValue(creature));

        Map* map = creature->GetMap();
        if (HasAffix(run, AFFIX_BOLSTERING))
        {
            for (auto const& pair : map->GetCreatureBySpawnIdStore())
            {
                Creature* other = pair.second;
                if (other != creature && other->IsAlive() && IsEnemyCreature(other) && !IsBoss(other)
                    && other->IsWithinDist(creature, BOLSTER_RANGE))
                {
                    ++run.Bolster[other->GetGUID()];
                    ScaleCreature(run, other);
                }
            }
        }
        if (HasAffix(run, AFFIX_SANGUINE))
            run.Pools.push_back({ creature->GetPosition(), SANGUINE_DURATION });
        if (HasAffix(run, AFFIX_BURSTING))
            ForEachPlayer(map, [&](Player* player)
                {
                    PlayerDebuffs& d = run.Debuffs[player->GetGUID()];
                    ++d.Bursting;
                    d.BurstingTimer = 4 * IN_MILLISECONDS;
                });

        SyncRun(run);
        CheckComplete(run);
    }

    void AffixDamage(Run& run, Player* player, uint32 damage, EnviromentalDamage type)
    {
        if (!player->IsAlive() || !damage)
            return;
        if (damage >= player->GetHealth())
            ++run.Deaths;
        player->EnvironmentalDamage(type, damage);
    }

    // ---------------------------------------------------------------- start
    Run* PlayerRun(Player* player, std::string& error)
    {
        Map* map = player->GetMap();
        if (!IsMythicMap(map))
        {
            error = MSG_NOT_IN_DUNGEON;
            return nullptr;
        }
        return &GetOrCreateRun(map);
    }

    bool CanStart(Player* player, Run& run, std::string& error)
    {
        auto key = s_keys.find(player->GetGUID().GetCounter());
        if (key == s_keys.end() || !key->second.MapId || !player->HasItemCount(KEYSTONE_ITEM, 1, false))
            error = MSG_NO_KEY;
        else if (key->second.MapId != run.MapId)
            error = MSG_WRONG_DUNGEON;
        else if (run.State != RUN_NONE || run.Started || std::any_of(run.Bosses.begin(), run.Bosses.end(), [](Boss const& b) { return b.Killed; }))
            error = MSG_ALREADY_STARTED;
        else if (player->IsInCombat())
            error = MSG_IN_COMBAT;
        else if (Group* group = player->GetGroup())
        {
            for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
            {
                Player* member = ref->GetSource();
                if (!member || member->GetMap() != player->GetMap())
                {
                    error = MSG_GROUP_OUTSIDE;
                    break;
                }
                if (!member->IsAlive())
                {
                    error = MSG_GROUP_DEAD;
                    break;
                }
                if (member->IsInCombat())
                {
                    error = MSG_IN_COMBAT;
                    break;
                }
            }
        }
        return error.empty();
    }

    GameObject* UsedFont(Player* player)
    {
        auto itr = s_fontUser.find(player->GetGUID());
        if (itr == s_fontUser.end())
            return nullptr;
        GameObject* font = player->GetMap()->GetGameObject(itr->second);
        if (!font || !player->IsWithinDistInMap(font, FONT_RANGE))
            return nullptr;
        return font;
    }

    void StartRun(Player* player, Run& run, GameObject* font)
    {
        Keystone const& key = s_keys[player->GetGUID().GetCounter()];
        auto dungeon = s_dungeons.find(run.MapId);

        run.Level = key.Level;
        run.Affixes = AffixesForLevel(key.Level);
        run.KeyOwner = player->GetGUID().GetCounter();
        run.TimeLimit = dungeon != s_dungeons.end() ? dungeon->second.TimeLimit : DEFAULT_TIME_LIMIT;
        run.State = RUN_COUNTDOWN;
        run.CountdownLeft = COUNTDOWN_MS;
        run.ElapsedMs = 0;
        run.Deaths = 0;
        run.Forces = 0;
        run.Started = true;
        run.FontPos = font->GetPosition();
        run.HasFont = true;

        Map* map = player->GetMap();
        CountForcesMax(run, map);
        for (auto const& pair : map->GetCreatureBySpawnIdStore())
            ScaleCreature(run, pair.second);

        // retail: everybody goes to the entrance and waits behind the barrier until the countdown ends
        run.StartPos = run.FontPos;
        if (AreaTriggerTeleport const* entrance = sObjectMgr->GetMapEntranceTrigger(run.MapId))
            run.StartPos.Relocate(entrance->target_X, entrance->target_Y, entrance->target_Z, entrance->target_Orientation);
        // walls of this dungeon (world.mythic_plus_barrier), up while the countdown runs
        auto barriers = s_barriers.find(run.MapId);
        if (barriers != s_barriers.end())
            for (BarrierSpawn const& spawn : barriers->second)
                if (GameObject* barrier = SpawnGameObject(map, spawn.Entry, spawn.Pos, COUNTDOWN_MS / IN_MILLISECONDS + 5))
                    run.BarrierGuids.push_back(barrier->GetGUID());

        ForEachPlayer(map, [&](Player* member)
            {
                member->NearTeleportTo(run.StartPos.GetPositionX(), run.StartPos.GetPositionY(), run.StartPos.GetPositionZ(), run.StartPos.GetOrientation());
                Message(member, MSG_STARTED);
                sAddonComm->Send(member, "MPLUS_FONT_CLOSE");
                s_slotted.erase(member->GetGUID());
                s_fontUser.erase(member->GetGUID());
            });
        SyncRun(run, true);
    }

    // ---------------------------------------------------------------- Great Vault
    // runs of a week (character_mythic_plus_weekly) -> up to 3 options for the next week:
    // 1 run - the best level, 4 runs - the 4th best, 8 runs - the 8th best; one option is taken
    std::vector<uint32> WeekLevels(ObjectGuid::LowType guid, uint32 week)
    {
        std::vector<uint32> levels;
        if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
            "SELECT CAST(level AS SIGNED) FROM character_mythic_plus_weekly WHERE guid = {} AND week = {} ORDER BY level DESC", guid, week).c_str()))
            do
                levels.push_back(uint32(result->Fetch()[0].GetInt64()));
        while (result->NextRow());
        return levels;
    }

    // difficulties (0 10N, 1 25N, 2 10H, 3 25H) of the raid bosses killed in a week, best first
    std::vector<uint32> WeekRaidLevels(ObjectGuid::LowType guid, uint32 week)
    {
        std::vector<uint32> levels;
        if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
            "SELECT CAST(difficulty AS SIGNED) FROM character_vault_raid WHERE guid = {} AND week = {} ORDER BY difficulty DESC", guid, week).c_str()))
            do
                levels.push_back(uint32(result->Fetch()[0].GetInt64()));
        while (result->NextRow());
        return levels;
    }

    void RecordRaidBoss(Creature* boss)
    {
        Map* map = boss->GetMap();
        if (!map || !map->IsRaid() || !(boss->IsDungeonBoss() || boss->isWorldBoss()))
            return;
        uint32 week = CurrentWeek();
        uint32 difficulty = uint32(map->GetDifficultyID());
        ForEachPlayer(map, [&](Player* member)
            {
                // one row per boss and week; a kill on a higher difficulty replaces the lower one
                CharacterDatabase.Execute(Trinity::StringFormat(
                    "INSERT INTO character_vault_raid (guid, week, entry, map_id, difficulty) VALUES ({}, {}, {}, {}, {}) "
                    "ON DUPLICATE KEY UPDATE difficulty = GREATEST(difficulty, VALUES(difficulty))",
                    member->GetGUID().GetCounter(), week, boss->GetEntry(), map->GetId(), difficulty).c_str());
            });
    }

    uint32 ChestLoot(uint32 mapId)
    {
        auto itr = s_dungeonLoot.find(mapId);
        return itr != s_dungeonLoot.end() && itr->second.Chest ? itr->second.Chest : CHEST_ENTRY;
    }

    uint32 VaultLoot(uint32 mapId)
    {
        auto itr = s_dungeonLoot.find(mapId);
        return itr != s_dungeonLoot.end() && itr->second.Vault ? itr->second.Vault : VAULT_LOOT;
    }

    // maps of the runs of a week, in the order of WeekLevels (best first)
    std::vector<uint32> WeekMaps(ObjectGuid::LowType guid, uint32 week)
    {
        std::vector<uint32> maps;
        if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
            "SELECT CAST(map_id AS SIGNED) FROM character_mythic_plus_weekly WHERE guid = {} AND week = {} ORDER BY level DESC", guid, week).c_str()))
            do
                maps.push_back(uint32(result->Fetch()[0].GetInt64()));
        while (result->NextRow());
        return maps;
    }

    uint32 RollVaultItem(Player* player, uint32 lootId = VAULT_LOOT)
    {
        Loot loot;
        loot.FillLoot(lootId, LootTemplates_Gameobject, player, true, true);
        for (LootItem const& lootItem : loot.items)
            if (ItemTemplate const* proto = sObjectMgr->GetItemTemplate(lootItem.itemid))
                if (proto->Class == ITEM_CLASS_WEAPON || proto->Class == ITEM_CLASS_ARMOR)
                    return lootItem.itemid;
        return loot.items.empty() ? 0 : loot.items.front().itemid;
    }

    void SendVault(Player* player)
    {
        ObjectGuid::LowType guid = player->GetGUID().GetCounter();
        uint32 week = CurrentWeek();
        uint32 last = week ? week - 1 : 0;

        // the options of last week's runs are rolled once
        bool hasOptions = false;
        if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
            "SELECT 1 FROM character_mythic_plus_vault WHERE guid = {} AND week = {} LIMIT 1", guid, last).c_str()))
            hasOptions = true;
        if (!hasOptions && week)
        {
            std::vector<uint32> levels = WeekLevels(guid, last);
            std::vector<uint32> maps = WeekMaps(guid, last);
            for (uint32 slot = 0; slot < 3; ++slot)
                if (levels.size() >= VAULT_THRESHOLDS[slot])
                    if (uint32 itemId = RollVaultItem(player, maps.size() >= VAULT_THRESHOLDS[slot] ? VaultLoot(maps[VAULT_THRESHOLDS[slot] - 1]) : VAULT_LOOT))
                        CharacterDatabase.DirectExecute(Trinity::StringFormat(
                            "INSERT INTO character_mythic_plus_vault (guid, week, slot, item_id, level, claimed) VALUES ({}, {}, {}, {}, {}, 0)",
                            guid, last, slot + 1, itemId, levels[VAULT_THRESHOLDS[slot] - 1]).c_str());

            std::vector<uint32> raid = WeekRaidLevels(guid, last);
            for (uint32 slot = 0; slot < 3; ++slot)
                if (raid.size() >= VAULT_RAID_THRESHOLDS[slot])
                    if (uint32 itemId = RollVaultItem(player, VAULT_RAID_LOOT))
                        CharacterDatabase.DirectExecute(Trinity::StringFormat(
                            "INSERT INTO character_mythic_plus_vault (guid, week, slot, item_id, level, claimed) VALUES ({}, {}, {}, {}, {}, 0)",
                            guid, last, slot + 4, itemId, raid[VAULT_RAID_THRESHOLDS[slot] - 1]).c_str());
        }

        std::ostringstream options;
        if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
            "SELECT CAST(slot AS SIGNED), CAST(item_id AS SIGNED), CAST(level AS SIGNED), CAST(claimed AS SIGNED) FROM character_mythic_plus_vault WHERE guid = {} AND week = {} ORDER BY slot",
            guid, last).c_str()))
        {
            bool first = true;
            do
            {
                Field* f = result->Fetch();
                options << (first ? "" : ",") << f[0].GetInt64() << ";" << f[1].GetInt64() << ";" << f[2].GetInt64() << ";" << f[3].GetInt64();
                first = false;
            } while (result->NextRow());
        }

        // this week's progress: levels of the runs, best first
        std::vector<uint32> levels = WeekLevels(guid, week);
        // raid difficulty is sent +1 (1 10N .. 4 25H): the client list skips zeros
        std::vector<uint32> raid = WeekRaidLevels(guid, week);
        for (uint32& difficulty : raid)
            ++difficulty;
        std::vector<uint32> world;
        sAddonComm->Send(player, "MPLUS_VAULT", uint32(levels.size()), JoinIds(levels), options.str(), JoinIds(raid), JoinIds(world));
    }

    void HandleVaultGet(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendVault(player);
    }

    void HandleVaultChoose(Player* player, std::vector<std::string> const& args)
    {
        uint32 slot = args.empty() ? 0 : CommToUInt32(args[0]);
        ObjectGuid::LowType guid = player->GetGUID().GetCounter();
        uint32 week = CurrentWeek();
        uint32 last = week ? week - 1 : 0;

        uint32 itemId = 0, level = 0;
        bool claimed = false;
        if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
            "SELECT CAST(slot AS SIGNED), CAST(item_id AS SIGNED), CAST(level AS SIGNED), CAST(claimed AS SIGNED) FROM character_mythic_plus_vault WHERE guid = {} AND week = {}",
            guid, last).c_str()))
            do
            {
                Field* f = result->Fetch();
                if (f[3].GetInt64())
                    claimed = true;
                if (uint32(f[0].GetInt64()) == slot)
                {
                    itemId = uint32(f[1].GetInt64());
                    level = uint32(f[2].GetInt64());
                }
            } while (result->NextRow());
        if (claimed || !itemId)
        {
            SendVault(player);
            return;
        }

        CharacterDatabase.DirectExecute(Trinity::StringFormat(
            "UPDATE character_mythic_plus_vault SET claimed = 1 WHERE guid = {} AND week = {} AND slot = {}", guid, last, slot).c_str());

        ItemPosCountVec dest;
        if (player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest, itemId, 1) == EQUIP_ERR_OK)
        {
            if (Item* item = player->StoreNewItem(dest, itemId, true))
            {
                player->SendNewItem(item, 1, true, false);
                if (slot <= 3)
                    MarkMythicItem(player, item, level);
            }
        }
        else if (Item* item = Item::CreateItem(itemId, 1, player))
        {
            CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
            if (slot <= 3)
                MarkMythicItem(player, item, level);
            item->SaveToDB(trans);
            MailDraft draft(MSG_VAULT_MAIL, "");
            draft.AddItem(item);
            draft.SendMailTo(trans, MailReceiver(player), MailSender(MAIL_NORMAL, 0, MAIL_STATIONERY_GM));
            CharacterDatabase.CommitTransaction(trans);
        }
        SendVault(player);
        SendMythicItems(player);
    }

    // ---------------------------------------------------------------- battle res (retail: 1 charge, +1 every 10 min)
    Run* ActiveKeystoneRun(Unit* unit)
    {
        Run* run = unit ? FindRun(unit->GetMap()) : nullptr;
        return run && run->Level && run->State == RUN_ACTIVE ? run : nullptr;
    }

    // ---------------------------------------------------------------- comm handlers
    void SendSeason(Player* player);    // below, with the leaderboard

    void SendAll(Player* player)
    {
        for (auto const& pair : s_affixes)
            sAddonComm->Send(player, "MPLUS_AFFIX", pair.first, Sanitize(pair.second.Name), pair.second.Icon, Sanitize(pair.second.Description));
        sAddonComm->Send(player, "MPLUS_WEEK", JoinIds(WeekAffixes()));
        {
            std::ostringstream maps;
            bool first = true;
            for (auto const& pair : s_dungeons)
            {
                std::string name = Sanitize(pair.second.Name);
                std::replace(name.begin(), name.end(), ';', ' ');
                std::replace(name.begin(), name.end(), ',', ' ');
                maps << (first ? "" : ",") << pair.first << ";" << name << ";" << pair.second.TimeLimit;
                first = false;
            }
            sAddonComm->Send(player, "MPLUS_MAPS", maps.str());
        }
        SendKey(player);
        SendSeason(player);
        SendRating(player);
        if (Run* run = FindRun(player->GetMap()))
        {
            SendBosses(player, *run);
            SendRun(player, *run);
        }
        else
            sAddonComm->Send(player, "MPLUS_RUN", 0, 0, 0, "", 0, 0, 0, DEATH_PENALTY, 0, 0, 0, 0);
    }

    void HandleGet(Player* player, std::vector<std::string> const& /*args*/)
    {
        SendAll(player);
    }

    void HandleInsert(Player* player, std::vector<std::string> const& /*args*/)
    {
        std::string error;
        Run* run = PlayerRun(player, error);
        if (run && !UsedFont(player))
            error = MSG_TOO_FAR;
        if (run && error.empty())
            CanStart(player, *run, error);
        if (!error.empty())
        {
            Result(player, error);
            sAddonComm->Send(player, "MPLUS_SLOTTED", 0);
            return;
        }
        s_slotted.insert(player->GetGUID());
        sAddonComm->Send(player, "MPLUS_SLOTTED", 1);
    }

    void HandleRemove(Player* player, std::vector<std::string> const& /*args*/)
    {
        s_slotted.erase(player->GetGUID());
        sAddonComm->Send(player, "MPLUS_SLOTTED", 0);
    }

    // retail: releasing the spirit in a mythic dungeon brings you back alive at the last checkpoint -
    // the entrance, or the room of the last killed boss (the client sends this instead of RepopMe)
    void HandleRelease(Player* player, std::vector<std::string> const& /*args*/)
    {
        if (player->IsAlive())
            return;
        Run* run = FindRun(player->GetMap());
        if (!run)
        {
            player->BuildPlayerRepop();
            player->RepopAtGraveyard();
            return;
        }

        Position checkpoint = run->StartPos;
        if (run->HasLastBoss)
            checkpoint = run->LastBossPos;
        else if (run->StartPos.GetPositionX() == 0.0f && run->StartPos.GetPositionY() == 0.0f)
        {
            if (AreaTriggerTeleport const* entrance = sObjectMgr->GetMapEntranceTrigger(run->MapId))
                checkpoint.Relocate(entrance->target_X, entrance->target_Y, entrance->target_Z, entrance->target_Orientation);
            else
                checkpoint = player->GetPosition();
        }

        player->ResurrectPlayer(1.0f);
        player->SpawnCorpseBones();
        player->NearTeleportTo(checkpoint.GetPositionX(), checkpoint.GetPositionY(), checkpoint.GetPositionZ(), checkpoint.GetOrientation());
    }

    void HandleClose(Player* player, std::vector<std::string> const& /*args*/)
    {
        s_slotted.erase(player->GetGUID());
        s_fontUser.erase(player->GetGUID());
    }

    void HandleStart(Player* player, std::vector<std::string> const& /*args*/)
    {
        std::string error;
        Run* run = PlayerRun(player, error);
        GameObject* font = run ? UsedFont(player) : nullptr;
        if (run && !font)
            error = MSG_TOO_FAR;
        else if (run && !s_slotted.count(player->GetGUID()))
            error = MSG_NOT_SLOTTED;
        if (run && error.empty())
            CanStart(player, *run, error);
        if (!error.empty())
        {
            Result(player, error);
            return;
        }
        StartRun(player, *run, font);
    }

    // ---------------------------------------------------------------- load
    void LoadData()
    {
        s_dungeons.clear();
        if (QueryResult result = WorldDatabase.Query("SELECT CAST(map_id AS SIGNED), name, CAST(time_limit AS SIGNED), CAST(forces_required AS SIGNED), chest_x, chest_y, chest_z, chest_o FROM mythic_plus_dungeon"))
            do
            {
                Field* f = result->Fetch();
                DungeonInfo info;
                info.MapId = uint32(f[0].GetInt64());
                info.Name = f[1].GetString();
                info.TimeLimit = uint32(f[2].GetInt64());
                info.ForcesRequired = uint32(f[3].GetInt64());
                if (!f[4].IsNull() && !f[5].IsNull() && !f[6].IsNull())
                {
                    info.HasChestPos = true;
                    info.ChestPos.Relocate(f[4].GetFloat(), f[5].GetFloat(), f[6].GetFloat(), f[7].IsNull() ? 0.0f : f[7].GetFloat());
                }
                s_dungeons[info.MapId] = info;
            } while (result->NextRow());

        s_affixes.clear();
        if (QueryResult result = WorldDatabase.Query("SELECT CAST(id AS SIGNED), name, icon, description FROM mythic_plus_affix"))
            do
            {
                Field* f = result->Fetch();
                AffixInfo info;
                info.Id = uint32(f[0].GetInt64());
                info.Name = f[1].GetString();
                info.Icon = f[2].GetString();
                info.Description = f[3].GetString();
                s_affixes[info.Id] = info;
            } while (result->NextRow());

        s_rotation.clear();
        if (QueryResult result = WorldDatabase.Query("SELECT CAST(affix1 AS SIGNED), CAST(affix2 AS SIGNED), CAST(affix3 AS SIGNED) FROM mythic_plus_affix_rotation ORDER BY week"))
            do
            {
                Field* f = result->Fetch();
                s_rotation.push_back({ uint32(f[0].GetInt64()), uint32(f[1].GetInt64()), uint32(f[2].GetInt64()) });
            } while (result->NextRow());

        s_forces.clear();
        if (QueryResult result = WorldDatabase.Query("SELECT CAST(entry AS SIGNED), CAST(count AS SIGNED) FROM mythic_plus_forces"))
            do
            {
                Field* f = result->Fetch();
                s_forces[uint32(f[0].GetInt64())] = uint32(f[1].GetInt64());
            } while (result->NextRow());

        s_barriers.clear();
        if (QueryResult result = WorldDatabase.Query("SELECT CAST(map_id AS SIGNED), CAST(entry AS SIGNED), x, y, z, o FROM mythic_plus_barrier"))
            do
            {
                Field* f = result->Fetch();
                BarrierSpawn spawn;
                spawn.Entry = uint32(f[1].GetInt64());
                spawn.Pos.Relocate(f[2].GetFloat(), f[3].GetFloat(), f[4].GetFloat(), f[5].GetFloat());
                s_barriers[uint32(f[0].GetInt64())].push_back(spawn);
            } while (result->NextRow());

        s_dungeonLoot.clear();
        if (QueryResult result = WorldDatabase.Query("SELECT CAST(map_id AS SIGNED), CAST(chest_loot AS SIGNED), CAST(vault_loot AS SIGNED) FROM mythic_plus_dungeon_loot"))
            do
            {
                Field* f = result->Fetch();
                s_dungeonLoot[uint32(f[0].GetInt64())] = { uint32(f[1].GetInt64()), uint32(f[2].GetInt64()) };
            } while (result->NextRow());

        s_seasons.clear();
        if (QueryResult result = WorldDatabase.Query("SELECT CAST(id AS SIGNED), CAST(start_time AS SIGNED), name, CAST(seasonal_affix AS SIGNED), CAST(seasonal_affix_level AS SIGNED) FROM mythic_plus_season ORDER BY start_time"))
            do
            {
                Field* f = result->Fetch();
                Season season;
                season.Id = uint32(f[0].GetInt64());
                season.Start = time_t(f[1].GetInt64());
                season.Name = f[2].GetString();
                season.Affix = uint32(f[3].GetInt64());
                season.AffixLevel = uint32(f[4].GetInt64());
                s_seasons.push_back(season);
            } while (result->NextRow());

        s_seasonRewards.clear();
        if (QueryResult result = WorldDatabase.Query("SELECT CAST(season AS SIGNED), CAST(rating AS SIGNED), CAST(title_id AS SIGNED), CAST(item_id AS SIGNED), CAST(spell_id AS SIGNED) FROM mythic_plus_season_reward"))
            do
            {
                Field* f = result->Fetch();
                s_seasonRewards.push_back({ uint32(f[0].GetInt64()), uint32(f[1].GetInt64()), uint32(f[2].GetInt64()), uint32(f[3].GetInt64()), uint32(f[4].GetInt64()) });
            } while (result->NextRow());

        TC_LOG_INFO("server.loading", ">> Mythic+: {} dungeon loot rows, {} seasons (current {}), {} season rewards",
            s_dungeonLoot.size(), s_seasons.size(), CurrentSeasonId(), s_seasonRewards.size());
        TC_LOG_INFO("server.loading", ">> Mythic+: {} dungeons, {} affixes, {} rotation weeks, {} forces overrides, {} dungeons with barriers",
            s_dungeons.size(), s_affixes.size(), s_rotation.size(), s_forces.size(), s_barriers.size());
    }

    void LoadKey(Player* player)
    {
        ObjectGuid::LowType guid = player->GetGUID().GetCounter();
        s_keys.erase(guid);
        if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
            "SELECT CAST(map_id AS SIGNED), CAST(level AS SIGNED), CAST(week AS SIGNED) FROM character_mythic_keystone WHERE guid = {}", guid).c_str()))
        {
            Field* f = result->Fetch();
            Keystone key = { uint32(f[0].GetInt64()), uint32(f[1].GetInt64()), uint32(f[2].GetInt64()) };
            // rows from before the week column: this week's
            if (!key.Week)
            {
                key.Week = CurrentWeek();
                SaveKey(guid, key);
            }
            // given before the last weekly reset: gone
            if (key.Week != CurrentWeek())
            {
                CharacterDatabase.Execute(Trinity::StringFormat("DELETE FROM character_mythic_keystone WHERE guid = {}", guid).c_str());
                Message(player, MSG_KEY_EXPIRED);
            }
            else
                s_keys[guid] = key;
        }

        // item <-> row: the row is the truth
        bool hasRow = HasKey(player);
        bool hasItem = player->HasItemCount(KEYSTONE_ITEM, 1, true);
        if (hasRow && !hasItem)
            GiveKeyItem(player);
        else if (!hasRow && hasItem)
            player->DestroyItemCount(KEYSTONE_ITEM, 1, true);
    }

    // ---------------------------------------------------------------- new affixes (once a second)
    // a random living non-boss enemy in combat (Explosive, Storming spawn next to it)
    Creature* RandomFightingEnemy(Map* map)
    {
        std::vector<Creature*> list;
        for (auto const& pair : map->GetCreatureBySpawnIdStore())
        {
            Creature* creature = pair.second;
            if (creature->IsAlive() && creature->IsInCombat() && IsEnemyCreature(creature) && !IsBoss(creature))
                list.push_back(creature);
        }
        return list.empty() ? nullptr : list[urand(0, uint32(list.size() - 1))];
    }

    Creature* SummonAffixCreature(Creature* near, uint32 entry, uint32 lifeMs)
    {
        if (!sObjectMgr->GetCreatureTemplate(entry))
            return nullptr;
        Position pos = near->GetRandomNearPosition(5.0f);
        return near->SummonCreature(entry, pos, TEMPSUMMON_TIMED_DESPAWN, Milliseconds(lifeMs));
    }

    void UpdateNewAffixes(Run& run, Map* map)
    {
        uint32 const tick = IN_MILLISECONDS;

        // Explosive: an orb appears near fighting enemies every 8 s and explodes after 6 s unless killed
        if (HasAffix(run, AFFIX_EXPLOSIVE))
        {
            run.ExplosiveTimer += tick;
            if (run.ExplosiveTimer >= 8 * IN_MILLISECONDS)
            {
                run.ExplosiveTimer = 0;
                if (Creature* near = RandomFightingEnemy(map))
                    if (Creature* orb = SummonAffixCreature(near, EXPLOSIVE_ENTRY, 7 * IN_MILLISECONDS))
                    {
                        uint32 health = 3000 + run.Level * 300;
                        orb->SetMaxHealth(health);
                        orb->SetHealth(health);
                        orb->SetReactState(REACT_PASSIVE);
                        orb->SetControlled(true, UNIT_STATE_ROOT);
                        run.Orbs.push_back({ orb->GetGUID(), 6 * IN_MILLISECONDS });
                    }
            }
        }
        for (auto itr = run.Orbs.begin(); itr != run.Orbs.end();)
        {
            Creature* orb = map->GetCreature(itr->Guid);
            if (!orb || !orb->IsAlive())
            {
                itr = run.Orbs.erase(itr);
                continue;
            }
            if (itr->TimeLeft > tick)
            {
                itr->TimeLeft -= tick;
                ++itr;
                continue;
            }
            ForEachPlayer(map, [&](Player* player) { AffixDamage(run, player, player->CountPctFromMaxHealth(10), DAMAGE_FIRE); });
            orb->DespawnOrUnsummon();
            itr = run.Orbs.erase(itr);
        }

        // Storming: a tornado near fighting enemies every 12 s for 8 s, 8% per second to players within 4 yd
        if (HasAffix(run, AFFIX_STORMING))
        {
            run.StormTimer += tick;
            if (run.StormTimer >= 12 * IN_MILLISECONDS)
            {
                run.StormTimer = 0;
                if (Creature* near = RandomFightingEnemy(map))
                    if (Creature* storm = SummonAffixCreature(near, STORM_ENTRY, 8 * IN_MILLISECONDS))
                    {
                        storm->SetReactState(REACT_PASSIVE);
                        storm->GetMotionMaster()->MoveRandom(8.0f);
                        run.Storms.push_back({ storm->GetGUID(), 8 * IN_MILLISECONDS });
                    }
            }
        }
        for (auto itr = run.Storms.begin(); itr != run.Storms.end();)
        {
            Creature* storm = map->GetCreature(itr->Guid);
            if (!storm || itr->TimeLeft <= tick)
            {
                itr = run.Storms.erase(itr);
                continue;
            }
            itr->TimeLeft -= tick;
            ForEachPlayer(map, [&](Player* player)
                {
                    if (player->IsWithinDist(storm, 4.0f))
                        AffixDamage(run, player, player->CountPctFromMaxHealth(8), DAMAGE_FALL);
                });
            ++itr;
        }

        // Quaking: every 20 s a warning, 2.5 s later 15% to every player plus 15% per ally within 8 yd, casts interrupted
        if (HasAffix(run, AFFIX_QUAKING))
        {
            if (run.QuakeWarn)
            {
                run.QuakeWarn = run.QuakeWarn > tick ? run.QuakeWarn - tick : 0;
                if (!run.QuakeWarn)
                    ForEachPlayer(map, [&](Player* player)
                        {
                            if (!player->IsAlive())
                                return;
                            uint32 near = 0;
                            ForEachPlayer(map, [&](Player* other)
                                {
                                    if (other != player && other->IsAlive() && player->IsWithinDist(other, 8.0f))
                                        ++near;
                                });
                            player->InterruptNonMeleeSpells(false);
                            AffixDamage(run, player, player->CountPctFromMaxHealth(15) * (1 + near), DAMAGE_FALL);
                        });
            }
            run.QuakeTimer += tick;
            if (run.QuakeTimer >= 20 * IN_MILLISECONDS)
            {
                run.QuakeTimer = 0;
                run.QuakeWarn = 2 * IN_MILLISECONDS;
                ForEachPlayer(map, [&](Player* player) { Result(player, MSG_QUAKE); });
            }
        }

        // Thundering: every 70 s two players are marked for 15 s; they clear it by meeting (8 yd), else 50% each
        if (HasAffix(run, AFFIX_THUNDERING))
        {
            if (run.ThunderLeft)
            {
                Player* a = ObjectAccessor::GetPlayer(map, run.ThunderA);
                Player* b = ObjectAccessor::GetPlayer(map, run.ThunderB);
                if (!a || !b || a->IsWithinDist(b, 8.0f))
                    run.ThunderLeft = 0;
                else if (run.ThunderLeft <= tick)
                {
                    run.ThunderLeft = 0;
                    AffixDamage(run, a, a->CountPctFromMaxHealth(50), DAMAGE_FIRE);
                    AffixDamage(run, b, b->CountPctFromMaxHealth(50), DAMAGE_FIRE);
                }
                else
                    run.ThunderLeft -= tick;
            }
            run.ThunderTimer += tick;
            if (run.ThunderTimer >= 70 * IN_MILLISECONDS)
            {
                run.ThunderTimer = 0;
                std::vector<Player*> alive;
                ForEachPlayer(map, [&](Player* player) { if (player->IsAlive() && player->IsInCombat()) alive.push_back(player); });
                if (alive.size() >= 2)
                {
                    std::shuffle(alive.begin(), alive.end(), std::mt19937(urand(0, 0xFFFFFF)));
                    run.ThunderA = alive[0]->GetGUID();
                    run.ThunderB = alive[1]->GetGUID();
                    run.ThunderLeft = 15 * IN_MILLISECONDS;
                    Result(alive[0], MSG_THUNDER);
                    Result(alive[1], MSG_THUNDER);
                }
            }
        }

        // Inspiring: the inspiring enemies and their allies within 10 yd are immune to crowd control
        if (!run.Inspiring.empty())
            for (auto const& pair : map->GetCreatureBySpawnIdStore())
            {
                Creature* creature = pair.second;
                if (!creature->IsAlive() || !IsEnemyCreature(creature) || run.Inspired.count(creature->GetGUID()))
                    continue;
                bool near = run.Inspiring.count(creature->GetGUID()) != 0;
                for (ObjectGuid const& guid : run.Inspiring)
                    if (!near)
                        if (Creature* source = map->GetCreature(guid))
                            near = source->IsAlive() && source->IsInCombat() && creature->IsWithinDist(source, 10.0f);
                if (!near)
                    continue;
                run.Inspired.insert(creature->GetGUID());
                for (Mechanics mechanic : { MECHANIC_STUN, MECHANIC_FEAR, MECHANIC_ROOT, MECHANIC_SILENCE, MECHANIC_SLEEP,
                    MECHANIC_CHARM, MECHANIC_POLYMORPH, MECHANIC_HORROR, MECHANIC_DISORIENTED, MECHANIC_KNOCKOUT,
                    MECHANIC_SNARE, MECHANIC_FREEZE, MECHANIC_BANISH, MECHANIC_SAPPED })
                    creature->ApplySpellImmune(0, IMMUNITY_MECHANIC, mechanic, true);
            }
    }

    // ---------------------------------------------------------------- pings (group, AddonComm)
    // C->S "PING" : type : "T" (at the selected target) / "0" (the sender's position) / "P" : x : y : z (the cursor point, tenths)
    // S->C "PING" : id : type : sender name : target name : dx : dy (yards, world, from the receiver) : x : y : z (tenths)
    //      "PING_POS" : id : dx : dy : x : y : z
    void SendPingPos(Player* receiver, Ping const& ping, bool first, std::string const& senderName, std::string const& targetName)
    {
        float dx = ping.Pos.GetPositionX() - receiver->GetPositionX();
        float dy = ping.Pos.GetPositionY() - receiver->GetPositionY();
        // + the world position in tenths of a yard (WorldToCamera in the client dll: the marker in the world)
        int32 wx = int32(ping.Pos.GetPositionX() * 10.0f);
        int32 wy = int32(ping.Pos.GetPositionY() * 10.0f);
        int32 wz = int32((ping.Pos.GetPositionZ() + ping.Height) * 10.0f);
        if (first)
            sAddonComm->Send(receiver, "PING", ping.Id, ping.Type, Sanitize(senderName), Sanitize(targetName), int32(dx), int32(dy), wx, wy, wz);
        else
            sAddonComm->Send(receiver, "PING_POS", ping.Id, int32(dx), int32(dy), wx, wy, wz);
    }

    void HandlePing(Player* player, std::vector<std::string> const& args)
    {
        uint32 type = args.empty() ? 0 : CommToUInt32(args[0]);
        if (type < 1 || type > 4)
            return;
        uint32 now = GameTime::GetGameTimeMS();
        auto last = s_lastPing.find(player->GetGUID());
        if (last != s_lastPing.end() && now - last->second < PING_INTERVAL)
            return;
        s_lastPing[player->GetGUID()] = now;

        Ping ping;
        ping.Sender = player->GetGUID();
        ping.Type = type;
        ping.Id = ++s_pingId;
        ping.MapId = player->GetMapId();
        ping.Pos = player->GetPosition();
        std::string targetName;
        // "P" : x : y : z (tenths): the point under the client's cursor (CameraTraceLine of the client dll)
        if (args.size() >= 5 && args[1] == "P")
        {
            float x = float(std::atoi(args[2].c_str())) / 10.0f;
            float y = float(std::atoi(args[3].c_str())) / 10.0f;
            float z = float(std::atoi(args[4].c_str())) / 10.0f;
            Position point(x, y, z);
            if (player->GetExactDist2d(x, y) <= 150.0f && std::fabs(z - player->GetPositionZ()) <= 100.0f)
                ping.Pos = point;
        }
        else if (args.size() > 1 && !args[1].empty() && args[1] != "0")
        {
            // the client only says "at my target": the server knows the selection
            if (Unit* target = ObjectAccessor::GetUnit(*player, player->GetTarget()))
                if (target->IsInWorld() && target->GetMap() == player->GetMap() && player->IsWithinDist(target, 200.0f))
                {
                    ping.Target = target->GetGUID();
                    ping.Pos = target->GetPosition();
                    ping.Height = target->GetCollisionHeight() + 0.5f;
                    targetName = target->GetName();
                    if (Creature* creature = target->ToCreature())
                        if (CreatureLocale const* locale = sObjectMgr->GetCreatureLocale(creature->GetEntry()))
                            ObjectMgr::GetLocaleString(locale->Name, player->GetSession()->GetSessionDbLocaleIndex(), targetName);
                }
        }

        // the group on this map, or only the sender
        std::vector<Player*> receivers;
        if (Group* group = player->GetGroup())
        {
            for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
                if (Player* member = ref->GetSource())
                    if (member->IsInWorld() && member->GetMap() == player->GetMap())
                        receivers.push_back(member);
        }
        else
            receivers.push_back(player);

        for (Player* receiver : receivers)
        {
            ping.Receivers.push_back(receiver->GetGUID());
            SendPingPos(receiver, ping, true, player->GetName(), targetName);
        }
        s_pings.push_back(ping);
    }

    void UpdatePings(uint32 diff)
    {
        static uint32 timer = 0;
        timer += diff;
        if (timer < PING_UPDATE)
            return;
        uint32 elapsed = timer;
        timer = 0;
        for (auto itr = s_pings.begin(); itr != s_pings.end();)
        {
            Ping& ping = *itr;
            if (ping.TimeLeft <= elapsed)
            {
                itr = s_pings.erase(itr);
                continue;
            }
            ping.TimeLeft -= elapsed;
            for (ObjectGuid const& guid : ping.Receivers)
            {
                Player* receiver = ObjectAccessor::FindConnectedPlayer(guid);
                if (!receiver || !receiver->IsInWorld() || receiver->GetMapId() != ping.MapId)
                    continue;
                if (!ping.Target.IsEmpty())
                    if (Unit* target = ObjectAccessor::GetUnit(*receiver, ping.Target))
                        ping.Pos = target->GetPosition();
                SendPingPos(receiver, ping, false, "", "");
            }
            ++itr;
        }
    }

    // ---------------------------------------------------------------- scores of other players, leaderboard
    // C->S "MPLUS_SCORE_GET" : name -> S->C "MPLUS_SCORE" : name : rating : best level
    // a keystone linked in chat by <name>: its dungeon and level (3.3.5 links can't carry them)
    // C->S "MPLUS_KEY_OF" name -> S->C "MPLUS_KEY_INFO" name : mapId : level : dungeon (mapId 0 = no key)
    void HandleKeyOf(Player* player, std::vector<std::string> const& args)
    {
        if (args.empty() || args[0].empty())
            return;
        std::string const& name = args[0];
        ObjectGuid guid = sCharacterCache->GetCharacterGuidByName(name);
        uint32 mapId = 0, level = 0;
        if (!guid.IsEmpty())
        {
            auto itr = s_keys.find(guid.GetCounter());
            if (itr != s_keys.end())
            {
                mapId = itr->second.MapId;
                level = itr->second.Level;
            }
            else if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
                "SELECT CAST(map_id AS SIGNED), CAST(level AS SIGNED) FROM character_mythic_keystone WHERE guid = {}", guid.GetCounter()).c_str()))
            {
                mapId = uint32((*result)[0].GetInt64());
                level = uint32((*result)[1].GetInt64());
            }
        }
        sAddonComm->Send(player, "MPLUS_KEY_INFO", Sanitize(name), mapId, level, Sanitize(mapId ? DungeonName(mapId) : std::string()));
    }

    void HandleScoreGet(Player* player, std::vector<std::string> const& args)
    {
        if (args.empty() || args[0].empty())
            return;
        ObjectGuid guid = sCharacterCache->GetCharacterGuidByName(args[0]);
        if (guid.IsEmpty())
            return;
        uint32 rating = GetRating(guid.GetCounter());
        uint32 best = 0;
        if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
            "SELECT CAST(COALESCE(MAX(level), 0) AS SIGNED) FROM character_mythic_plus_season_best WHERE guid = {} AND season = {} AND timed = 1",
            guid.GetCounter(), CurrentSeasonId()).c_str()))
            best = uint32(result->Fetch()[0].GetInt64());
        sAddonComm->Send(player, "MPLUS_SCORE", Sanitize(args[0]), rating, best);
    }

    // C->S "MPLUS_LEADERS" : mapId -> S->C "MPLUS_LEADERS" : mapId : name;level;timeMs;timed;score;class,... (top 10 of the season)
    void HandleLeaders(Player* player, std::vector<std::string> const& args)
    {
        uint32 mapId = args.empty() ? 0 : CommToUInt32(args[0]);
        std::ostringstream list;
        if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
            "SELECT c.name, CAST(b.level AS SIGNED), CAST(b.time_ms AS SIGNED), CAST(b.timed AS SIGNED), CAST(b.score AS SIGNED), CAST(c.class AS SIGNED) "
            "FROM character_mythic_plus_season_best b JOIN characters c ON c.guid = b.guid "
            "WHERE b.season = {} AND b.map_id = {} ORDER BY b.score DESC, b.time_ms ASC LIMIT 10", CurrentSeasonId(), mapId).c_str()))
        {
            bool first = true;
            do
            {
                Field* f = result->Fetch();
                list << (first ? "" : ",") << f[0].GetString() << ";" << f[1].GetInt64() << ";" << f[2].GetInt64() << ";"
                    << f[3].GetInt64() << ";" << f[4].GetInt64() << ";" << f[5].GetInt64();
                first = false;
            } while (result->NextRow());
        }
        sAddonComm->Send(player, "MPLUS_LEADERS", mapId, list.str());
    }

    void SendSeason(Player* player)
    {
        Season const* season = CurrentSeason();
        sAddonComm->Send(player, "MPLUS_SEASON", season ? season->Id : 0, Sanitize(season ? season->Name : std::string()),
            season ? season->Affix : 0, season ? season->AffixLevel : 0);
    }

    // ---------------------------------------------------------------- key reroll / downgrade (npc_mythic_plus_keystone)
    bool KeyBusy(Player* player)
    {
        for (auto const& pair : s_runs)
            if (pair.second.KeyOwner == player->GetGUID().GetCounter() && pair.second.Level
                && (pair.second.State == RUN_COUNTDOWN || pair.second.State == RUN_ACTIVE))
                return true;
        return false;
    }

    // ---------------------------------------------------------------- update
    void UpdateRun(Run& run, uint32 diff)
    {
        Map* map = RunMap(run);
        if (!map)
            return;

        if (run.State == RUN_COUNTDOWN)
        {
            if (run.CountdownLeft > diff)
            {
                run.CountdownLeft -= diff;
                // the walls (mythic_plus_barrier) keep everybody at the entrance
            }
            else
            {
                run.CountdownLeft = 0;
                run.State = RUN_ACTIVE;
                run.BattleRes = 1;
                run.BattleResTimer = 0;
                // retail: everybody starts fresh - cooldowns, health and power
                ForEachPlayer(map, [&](Player* player)
                    {
                        player->GetSpellHistory()->ResetAllCooldowns();
                        if (player->IsAlive())
                        {
                            player->SetFullHealth();
                            player->SetPower(player->GetPowerType(), player->GetMaxPower(player->GetPowerType()));
                        }
                    });
                for (ObjectGuid const& guid : run.BarrierGuids)
                    if (GameObject* barrier = map->GetGameObject(guid))
                        barrier->DespawnOrUnsummon();
                run.BarrierGuids.clear();
                ForEachPlayer(map, [&](Player* player) { Message(player, MSG_GO); });
                SyncRun(run);
            }
            return;
        }

        // keystone runs: no loot from creatures, the reward is the chest (retail)
        if (run.Level && run.State != RUN_NONE)
            for (auto const& pair : map->GetCreatureBySpawnIdStore())
            {
                Creature* creature = pair.second;
                if (!creature->IsAlive() && !creature->loot.empty())
                {
                    creature->loot.clear();
                    creature->RemoveDynamicFlag(UNIT_DYNFLAG_LOOTABLE);
                }
            }

        if (run.State != RUN_ACTIVE)
            return;

        run.ElapsedMs += diff;

        run.BattleResTimer += diff;
        if (run.BattleResTimer >= BATTLE_RES_INTERVAL)
        {
            run.BattleResTimer -= BATTLE_RES_INTERVAL;
            ++run.BattleRes;
            ForEachPlayer(map, [&](Player* player) { Message(player, Fmt(MSG_BATTLE_RES_GAIN, run.BattleRes)); });
        }

        // timer expired: the key goes down now (retail), the run can still be finished
        if (!run.Depleted && run.ElapsedMs + run.Deaths * DEATH_PENALTY * IN_MILLISECONDS > run.TimeLimit * IN_MILLISECONDS)
        {
            run.Depleted = true;
            if (run.KeyOwner)
            {
                auto itr = s_keys.find(run.KeyOwner);
                if (itr != s_keys.end() && itr->second.MapId)
                    SetKey(run.KeyOwner, itr->second.MapId, std::max(MIN_KEY_LEVEL, itr->second.Level - 1));
            }
            ForEachPlayer(map, [&](Player* player) { Message(player, MSG_TIME_UP); });
            SyncRun(run);
        }

        // debuff timers
        for (auto& pair : run.Debuffs)
        {
            PlayerDebuffs& d = pair.second;
            if (d.Necrotic)
            {
                if (d.NecroticTimer > diff)
                    d.NecroticTimer -= diff;
                else
                    d.Necrotic = d.NecroticTimer = 0;
            }
            if (d.Bursting)
            {
                if (d.BurstingTimer > diff)
                    d.BurstingTimer -= diff;
                else
                    d.Bursting = d.BurstingTimer = 0;
            }
        }

        // once a second: pools, grievous, bursting, bosses despawned by scripts
        run.TickTimer += diff;
        if (run.TickTimer >= IN_MILLISECONDS)
        {
            run.TickTimer -= IN_MILLISECONDS;

            for (auto itr = run.Pools.begin(); itr != run.Pools.end();)
            {
                SanguinePool& pool = *itr;
                ForEachPlayer(map, [&](Player* player)
                    {
                        if (player->GetExactDist(&pool.Pos) <= SANGUINE_RANGE)
                            AffixDamage(run, player, player->CountPctFromMaxHealth(3), DAMAGE_SLIME);
                    });
                for (auto const& pair : map->GetCreatureBySpawnIdStore())
                {
                    Creature* creature = pair.second;
                    if (creature->IsAlive() && IsEnemyCreature(creature) && creature->GetExactDist(&pool.Pos) <= SANGUINE_RANGE)
                        creature->ModifyHealth(int32(creature->CountPctFromMaxHealth(5)));
                }
                if (pool.TimeLeft > IN_MILLISECONDS)
                {
                    pool.TimeLeft -= IN_MILLISECONDS;
                    ++itr;
                }
                else
                    itr = run.Pools.erase(itr);
            }

            bool grievous = HasAffix(run, AFFIX_GRIEVOUS);
            run.GrievousTimer += IN_MILLISECONDS;
            bool grievousTick = run.GrievousTimer >= 3 * IN_MILLISECONDS;
            if (grievousTick)
                run.GrievousTimer = 0;

            ForEachPlayer(map, [&](Player* player)
                {
                    PlayerDebuffs& d = run.Debuffs[player->GetGUID()];
                    if (d.Bursting)
                        AffixDamage(run, player, player->CountPctFromMaxHealth(2) * d.Bursting, DAMAGE_FIRE);

                    if (grievous && player->IsAlive())
                    {
                        if (player->GetHealthPct() >= 90.0f)
                            d.Grievous = 0;
                        else if (grievousTick)
                        {
                            d.Grievous = std::min<uint32>(d.Grievous + 1, 10);
                            AffixDamage(run, player, uint32(player->GetMaxHealth() * 0.005f * d.Grievous), DAMAGE_DROWNING);
                        }
                    }
                });

            UpdateNewAffixes(run, map);

            // bosses killed without DealDamage (scripted kills, instakills): found and dead
            // (not found = grid unloaded or corpse gone - OnDamage already counted it)
            for (Boss& boss : run.Bosses)
                if (!boss.Killed)
                {
                    bool found = false, alive = false;
                    for (auto const& pair : map->GetCreatureBySpawnIdStore())
                        if (pair.second->GetEntry() == boss.Entry)
                        {
                            found = true;
                            alive = alive || pair.second->IsAlive();
                        }
                    if (found && !alive)
                    {
                        boss.Killed = true;
                        SyncRun(run);
                    }
                }
            CheckComplete(run);
        }

        // periodic resync of the timer
        run.SyncTimer += diff;
        if (run.SyncTimer >= 5 * IN_MILLISECONDS)
        {
            run.SyncTimer = 0;
            SyncRun(run);
        }
    }
}

// talents can't change once a keystone run started (countdown or running): spec_primary.cpp, talent_custom.cpp,
// Player::s_talentsLockedHook (core/Player_talents_lock.patch)
bool MythicPlus_TalentsLocked(Player const* player)
{
    Run* run = player ? FindRun(player->GetMap()) : nullptr;
    return run && run->Level && (run->State == RUN_COUNTDOWN || run->State == RUN_ACTIVE);
}

// premade groups (premade_groups.cpp): the keystone and the season rating of a character
bool MythicPlus_GetKeystone(ObjectGuid::LowType guid, uint32& mapId, uint32& level)
{
    auto itr = s_keys.find(guid);
    if (itr == s_keys.end() || !itr->second.MapId)
        return false;
    mapId = itr->second.MapId;
    level = itr->second.Level;
    return true;
}

uint32 MythicPlus_GetRating(ObjectGuid::LowType guid)
{
    return GetRating(guid);
}

// ---------------------------------------------------------------- Font of Power
// ---------------------------------------------------------------- completion chest: personal loot
// every player of the run opens it once and gets their own roll of gameobject_loot_template CHEST_ENTRY
// (items straight into the bags, by mail when the bags are full)
struct go_mythic_plus_chest : public GameObjectAI
{
    go_mythic_plus_chest(GameObject* go) : GameObjectAI(go) {}

    bool OnGossipHello(Player* player) override
    {
        Run* run = FindRun(player->GetMap());
        ObjectGuid::LowType guid = player->GetGUID().GetCounter();
        if (!run || !run->ChestAllowed.count(guid))
        {
            Result(player, MSG_CHEST_NOT_YOURS);
            return true;
        }
        if (!run->ChestLooted.insert(guid).second)
        {
            Result(player, MSG_CHEST_LOOTED);
            return true;
        }

        Loot loot;
        loot.FillLoot(ChestLoot(run->MapId), LootTemplates_Gameobject, player, true);

        std::vector<std::pair<uint32, uint32>> mailItems;
        for (LootItem const& lootItem : loot.items)
        {
            ItemPosCountVec dest;
            if (player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest, lootItem.itemid, lootItem.count) == EQUIP_ERR_OK)
            {
                if (Item* item = player->StoreNewItem(dest, lootItem.itemid, true, lootItem.randomPropertyId))
                {
                    player->SendNewItem(item, lootItem.count, true, false);
                    MarkMythicItem(player, item, run->Level);
                }
            }
            else
                mailItems.emplace_back(lootItem.itemid, lootItem.count);
        }
        if (loot.gold)
            player->ModifyMoney(int64(loot.gold));

        if (!mailItems.empty())
        {
            CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
            MailDraft draft(MSG_CHEST_MAIL, "");
            for (auto const& entry : mailItems)
                if (Item* item = Item::CreateItem(entry.first, entry.second, player))
                {
                    MarkMythicItem(player, item, run->Level);
                    item->SaveToDB(trans);
                    draft.AddItem(item);
                }
            draft.SendMailTo(trans, MailReceiver(player), MailSender(MAIL_NORMAL, 0, MAIL_STATIONERY_GM));
            CharacterDatabase.CommitTransaction(trans);
        }
        return true;
    }
};

struct go_mythic_plus_font : public GameObjectAI
{
    go_mythic_plus_font(GameObject* go) : GameObjectAI(go) {}

    bool OnGossipHello(Player* player) override
    {
        std::string error;
        Run* run = PlayerRun(player, error);
        if (!run)
        {
            Result(player, error);
            return true;
        }
        run->FontPos = me->GetPosition();
        run->HasFont = true;
        s_fontUser[player->GetGUID()] = me->GetGUID();
        s_slotted.erase(player->GetGUID());
        SendKey(player);
        sAddonComm->Send(player, "MPLUS_FONT_OPEN", run->MapId);
        return true;
    }
};

// ---------------------------------------------------------------- scripts
class mythic_plus_world : public WorldScript
{
    uint32 fontTimer = 0;
    uint32 resetTimer = 0;
    uint32 lastWeek = 0;

public:
    mythic_plus_world() : WorldScript("mythic_plus_world") {}

    void OnStartup() override
    {
        LoadData();
        Player::s_talentsLockedHook = &MythicPlus_TalentsLocked;  // core/Player_talents_lock.patch
        CharacterDatabase.Execute("DELETE FROM item_mythic WHERE item_guid NOT IN (SELECT guid FROM item_instance)");
    }

    void OnUpdate(uint32 diff) override
    {
        // joined a group in the middle of a run: out again (retail: the group is locked)
        for (ObjectGuid const& guid : s_pendingKick)
            if (Player* player = ObjectAccessor::FindConnectedPlayer(guid))
                if (Group* group = player->GetGroup())
                {
                    Message(player, MSG_GROUP_LOCKED);
                    group->RemoveMember(guid, GROUP_REMOVEMETHOD_KICK);
                }
        s_pendingKick.clear();

        // walked away from the Font of Power: close the keystone frame
        fontTimer += diff;
        if (fontTimer >= 500)
        {
            fontTimer = 0;
            for (auto itr = s_fontUser.begin(); itr != s_fontUser.end();)
            {
                Player* player = ObjectAccessor::FindConnectedPlayer(itr->first);
                GameObject* font = player && player->IsInWorld() ? player->GetMap()->GetGameObject(itr->second) : nullptr;
                if (player && font && player->IsWithinDistInMap(font, FONT_RANGE))
                {
                    ++itr;
                    continue;
                }
                if (player)
                    sAddonComm->Send(player, "MPLUS_FONT_CLOSE");
                s_slotted.erase(itr->first);
                itr = s_fontUser.erase(itr);
            }
        }

        UpdatePings(diff);

        // weekly reset: the keys of the past week are gone (offline owners: at login, LoadKey)
        resetTimer += diff;
        if (resetTimer >= 10 * IN_MILLISECONDS)
        {
            resetTimer = 0;
            uint32 week = CurrentWeek();
            if (lastWeek && week != lastWeek)
            {
                std::vector<ObjectGuid::LowType> expired;
                for (auto const& pair : s_keys)
                    if (pair.second.MapId && pair.second.Week != week)
                        expired.push_back(pair.first);
                for (ObjectGuid::LowType guid : expired)
                {
                    SetKey(guid, 0, 0);
                    if (Player* player = ObjectAccessor::FindConnectedPlayer(ObjectGuid::Create<HighGuid::Player>(guid)))
                        Message(player, MSG_KEY_EXPIRED);
                }
                CharacterDatabase.Execute(Trinity::StringFormat("DELETE FROM character_mythic_keystone WHERE week <> {}", week).c_str());
            }
            lastWeek = week;
        }

        for (auto itr = s_runs.begin(); itr != s_runs.end();)
        {
            if (!sMapMgr->FindMap(itr->second.MapId, itr->second.InstanceId))
            {
                itr = s_runs.erase(itr);
                continue;
            }
            UpdateRun(itr->second, diff);
            ++itr;
        }
    }
};

class mythic_plus_player : public PlayerScript
{
public:
    mythic_plus_player() : PlayerScript("mythic_plus_player")
    {
        sAddonComm->Register(std::string("MPLUS_GET"), &HandleGet);
        sAddonComm->Register(std::string("MPLUS_KEY_OF"), &HandleKeyOf);
        sAddonComm->Register(std::string("MPLUS_INSERT"), &HandleInsert);
        sAddonComm->Register(std::string("MPLUS_REMOVE"), &HandleRemove);
        sAddonComm->Register(std::string("MPLUS_START"), &HandleStart);
        sAddonComm->Register(std::string("MPLUS_CLOSE"), &HandleClose);
        sAddonComm->Register(std::string("MPLUS_RELEASE"), &HandleRelease);
        sAddonComm->Register(std::string("MPLUS_ITEMS_GET"), &HandleItemsGet);
        sAddonComm->Register(std::string("MPLUS_VAULT_GET"), &HandleVaultGet);
        sAddonComm->Register(std::string("MPLUS_VAULT_CHOOSE"), &HandleVaultChoose);
        sAddonComm->Register(std::string("MPLUS_SCORE_GET"), &HandleScoreGet);
        sAddonComm->Register(std::string("MPLUS_LEADERS"), &HandleLeaders);
        sAddonComm->Register(std::string("PING"), &HandlePing);
    }

    void OnLogin(Player* player, bool /*firstLogin*/) override
    {
        LoadKey(player);
        LoadMythicItems(player);
        ReconcileMythicItems(player);
        SendAll(player);
        SendMythicItems(player);
        CheckSeasonRewards(player);
    }

    void OnLogout(Player* player) override
    {
        s_fontUser.erase(player->GetGUID());
        s_slotted.erase(player->GetGUID());
        s_lastInstance.erase(player->GetGUID());
        s_keys.erase(player->GetGUID().GetCounter());
        s_lastPing.erase(player->GetGUID());
    }

    void OnMapChanged(Player* player) override
    {
        Map* map = player->GetMap();
        if (!IsMythicMap(map))
        {
            player->SetControlled(false, UNIT_STATE_ROOT);
            if (LeftMythicInstance(player))
                return;
            sAddonComm->Send(player, "MPLUS_RUN", 0, 0, 0, "", 0, 0, 0, DEATH_PENALTY, 0, 0, 0, 0);
            return;
        }
        s_lastInstance[player->GetGUID()] = { map->GetId(), map->GetInstanceId() };
        Run& run = GetOrCreateRun(map);
        SendBosses(player, run);
        SendRun(player, run);
    }

    // left a mythic instance:
    //  - keystone run in progress: back inside (no leaving, no hearthstone / portals out) - returns true;
    //  - otherwise the instance is not kept: the next entry is a new, full instance (retail: every run is fresh)
    static bool LeftMythicInstance(Player* player)
    {
        auto last = s_lastInstance.find(player->GetGUID());
        if (last == s_lastInstance.end())
            return false;
        uint32 mapId = last->second.first;
        uint32 instanceId = last->second.second;

        auto run = s_runs.find(instanceId);
        Map* instance = sMapMgr->FindMap(mapId, instanceId);
        if (run != s_runs.end() && instance && player->IsAlive()
            && (run->second.State == RUN_COUNTDOWN || run->second.State == RUN_ACTIVE))
        {
            Position const& back = run->second.HasLastBoss ? run->second.LastBossPos : run->second.StartPos;
            Message(player, MSG_NO_LEAVE);
            player->TeleportTo(mapId, back.GetPositionX(), back.GetPositionY(), back.GetPositionZ(), back.GetOrientation());
            return true;
        }

        s_lastInstance.erase(last);
        player->UnbindInstance(mapId, DUNGEON_DIFFICULTY_EPIC);

        // the group bind goes when nobody of the group is inside any more
        if (Group* group = player->GetGroup())
        {
            bool inside = false;
            for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
                if (Player* member = ref->GetSource())
                    if (member->GetMapId() == mapId && member->GetInstanceId() == instanceId)
                        inside = true;
            if (!inside)
                group->UnbindInstance(mapId, DUNGEON_DIFFICULTY_EPIC);
        }
        return false;
    }

    void OnPlayerKilledByCreature(Creature* killer, Player* killed) override
    {
        if (Run* run = FindRun(killed->GetMap()))
            if (run->State == RUN_ACTIVE && killer)
            {
                ++run->Deaths;
                SyncRun(*run);
            }
    }
};

class mythic_plus_unit : public UnitScript
{
public:
    mythic_plus_unit() : UnitScript("mythic_plus_unit") {}

    template <typename T>
    static void Modify(Unit* target, Unit* attacker, T& damage)
    {
        if (!target || !attacker || damage <= 0)
            return;
        Run* run = FindRun(target->GetMap());
        if (!run || !run->Level || run->State != RUN_ACTIVE)
            return;

        if (IsEnemyCreature(attacker) && target->GetTypeId() == TYPEID_PLAYER)
        {
            Creature* creature = attacker->ToCreature();
            ScaleCreature(*run, creature);
            float mult = CreatureMult(*run, creature, false);
            if (HasAffix(*run, AFFIX_RAGING) && !IsBoss(creature) && creature->GetHealthPct() < 30.0f)
                mult *= 1.5f;
            damage = T(std::min(float(damage) * mult, 2000000000.0f));   // no overflow on very high keys
        }
        else if (IsEnemyCreature(target))
            ScaleCreature(*run, target->ToCreature());
    }

    void ModifyMeleeDamage(Unit* target, Unit* attacker, uint32& damage) override
    {
        Modify(target, attacker, damage);
        // necrotic: melee hits of creatures
        if (target && attacker && target->GetTypeId() == TYPEID_PLAYER && IsEnemyCreature(attacker))
            if (Run* run = FindRun(target->GetMap()))
                if (HasAffix(*run, AFFIX_NECROTIC))
                {
                    PlayerDebuffs& d = run->Debuffs[target->GetGUID()];
                    d.Necrotic = std::min<uint32>(d.Necrotic + 1, 49);
                    d.NecroticTimer = 8 * IN_MILLISECONDS;
                }
    }

    void ModifySpellDamageTaken(Unit* target, Unit* attacker, int32& damage) override
    {
        Modify(target, attacker, damage);
    }

    void ModifyPeriodicDamageAurasTick(Unit* target, Unit* attacker, uint32& damage) override
    {
        Modify(target, attacker, damage);
    }

    void OnHeal(Unit* /*healer*/, Unit* receiver, uint32& gain) override
    {
        if (!receiver || receiver->GetTypeId() != TYPEID_PLAYER)
            return;
        if (Run* run = FindRun(receiver->GetMap()))
        {
            auto itr = run->Debuffs.find(receiver->GetGUID());
            if (itr != run->Debuffs.end() && itr->second.Necrotic)
                gain = uint32(gain * std::max(0.0f, 1.0f - 0.02f * itr->second.Necrotic));
        }
    }

    void OnDamage(Unit* /*attacker*/, Unit* victim, uint32& damage) override
    {
        if (!victim || victim->GetTypeId() != TYPEID_UNIT || damage < victim->GetHealth())
            return;
        if (Run* run = FindRun(victim->GetMap()))
            OnCreatureDeath(*run, victim->ToCreature());
        else
            RecordRaidBoss(victim->ToCreature());
    }
};

// ---------------------------------------------------------------- commands
class mythic_plus_commands : public CommandScript
{
public:
    mythic_plus_commands() : CommandScript("mythic_plus_commands") {}

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable mplusTable =
        {
            { "key",      HandleKey,      rbac::RBAC_PERM_COMMAND_ADDITEM, Console::No },
            { "info",     HandleInfo,     rbac::RBAC_PERM_COMMAND_ADDITEM, Console::No },
            { "complete", HandleComplete, rbac::RBAC_PERM_COMMAND_ADDITEM, Console::No },
            { "reset",    HandleReset,    rbac::RBAC_PERM_COMMAND_ADDITEM, Console::No },
            { "reload",   HandleReload,   rbac::RBAC_PERM_COMMAND_ADDITEM, Console::Yes },
        };
        static ChatCommandTable commandTable =
        {
            { "mplus", mplusTable },
        };
        return commandTable;
    }

    // .mplus key <level> [mapId] - to the selected player or yourself; level 0 removes the key
    static bool HandleKey(ChatHandler* handler, uint32 level, Optional<uint32> mapId)
    {
        Player* target = handler->getSelectedPlayerOrSelf();
        if (!target)
            return false;
        uint32 map = mapId ? *mapId : RandomDungeon(0);
        if (level && !s_dungeons.count(map))
        {
            handler->SendSysMessage(Trinity::StringFormat("mplus: map {} is not in mythic_plus_dungeon", map));
            return false;
        }
        SetKey(target->GetGUID().GetCounter(), level ? map : 0, level);
        handler->SendSysMessage(Trinity::StringFormat("mplus: {} key {} +{}", target->GetName(), level ? DungeonName(map) : "-", level));
        return true;
    }

    static bool HandleInfo(ChatHandler* handler)
    {
        Player* player = handler->GetSession()->GetPlayer();
        Run* run = FindRun(player->GetMap());
        if (!run)
        {
            handler->SendSysMessage("mplus: not in a mythic instance");
            return true;
        }
        handler->SendSysMessage(Trinity::StringFormat("mplus: map {} instance {} state {} level {} affixes {} time {}/{}s deaths {} forces {}/{} bosses {}/{}",
            run->MapId, run->InstanceId, uint32(run->State), run->Level, JoinIds(run->Affixes), run->ElapsedMs / IN_MILLISECONDS, run->TimeLimit,
            run->Deaths, run->Forces, run->ForcesMax, std::count_if(run->Bosses.begin(), run->Bosses.end(), [](Boss const& b) { return b.Killed; }), run->Bosses.size()));
        return true;
    }

    static bool HandleComplete(ChatHandler* handler)
    {
        Player* player = handler->GetSession()->GetPlayer();
        Run* run = FindRun(player->GetMap());
        if (!run)
            return false;
        for (Boss& boss : run->Bosses)
            boss.Killed = true;
        run->Forces = run->ForcesMax;
        if (run->Level && run->State == RUN_COUNTDOWN)
            run->State = RUN_ACTIVE;
        CompleteRun(*run);
        return true;
    }

    static bool HandleReset(ChatHandler* handler)
    {
        Player* player = handler->GetSession()->GetPlayer();
        Map* map = player->GetMap();
        if (!IsMythicMap(map))
            return false;
        s_runs.erase(map->GetInstanceId());
        ForEachPlayer(map, [](Player* p) { p->SetControlled(false, UNIT_STATE_ROOT); });
        Run& run = GetOrCreateRun(map);
        SyncRun(run, true);
        handler->SendSysMessage("mplus: run reset");
        return true;
    }

    static bool HandleReload(ChatHandler* handler)
    {
        LoadData();
        handler->SendSysMessage("mplus: tables reloaded");
        return true;
    }
};

// battle res spells (sql/world_mythic_plus_battle_res.sql): charges of the keystone run
class spell_mythic_plus_battle_res : public SpellScript
{
    PrepareSpellScript(spell_mythic_plus_battle_res);

    SpellCastResult CheckCast()
    {
        if (Run* run = ActiveKeystoneRun(GetCaster()))
            if (!run->BattleRes)
            {
                if (Player* player = GetCaster()->ToPlayer())
                    Result(player, MSG_NO_BATTLE_RES);
                return SPELL_FAILED_DONT_REPORT;
            }
        return SPELL_CAST_OK;
    }

    void HandleAfterCast()
    {
        if (Run* run = ActiveKeystoneRun(GetCaster()))
            if (run->BattleRes)
            {
                --run->BattleRes;
                uint32 left = run->BattleRes;
                ForEachPlayer(GetCaster()->GetMap(), [&](Player* player) { Message(player, Fmt(MSG_BATTLE_RES, left)); });
            }
    }

    void Register() override
    {
        OnCheckCast += SpellCheckCastFn(spell_mythic_plus_battle_res::CheckCast);
        AfterCast += SpellCastFn(spell_mythic_plus_battle_res::HandleAfterCast);
    }
};

class mythic_plus_group : public GroupScript
{
public:
    mythic_plus_group() : GroupScript("mythic_plus_group") {}

    void OnAddMember(Group* group, ObjectGuid guid) override
    {
        for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
            if (Player* member = ref->GetSource())
                if (member->GetGUID() != guid)
                    if (Run* run = FindRun(member->GetMap()))
                        if (run->Level && (run->State == RUN_COUNTDOWN || run->State == RUN_ACTIVE))
                        {
                            s_pendingKick.push_back(guid);
                            return;
                        }
    }
};

// Great Vault object (ScriptName go_mythic_plus_vault)
struct go_mythic_plus_vault : public GameObjectAI
{
    go_mythic_plus_vault(GameObject* go) : GameObjectAI(go) {}

    bool OnGossipHello(Player* player) override
    {
        sAddonComm->Send(player, "MPLUS_VAULT_OPEN");
        SendVault(player);
        return true;
    }
};

// keystone NPC: another dungeon for the key once a week (gold), or the key one level lower
struct npc_mythic_plus_keystone : public ScriptedAI
{
    npc_mythic_plus_keystone(Creature* creature) : ScriptedAI(creature) {}

    enum
    {
        ACTION_REROLL = GOSSIP_ACTION_INFO_DEF + 1,
        ACTION_DOWNGRADE = GOSSIP_ACTION_INFO_DEF + 2,
    };

    bool OnGossipHello(Player* player) override
    {
        ClearGossipMenuFor(player);
        if (HasKey(player))
        {
            AddGossipItemFor(player, GOSSIP_ICON_CHAT, MSG_REROLL_OPTION, GOSSIP_SENDER_MAIN, ACTION_REROLL);
            AddGossipItemFor(player, GOSSIP_ICON_CHAT, MSG_DOWNGRADE_OPTION, GOSSIP_SENDER_MAIN, ACTION_DOWNGRADE);
        }
        SendGossipMenuFor(player, player->GetGossipTextId(me), me->GetGUID());
        return true;
    }

    bool OnGossipSelect(Player* player, uint32 /*menuId*/, uint32 gossipListId) override
    {
        uint32 action = player->PlayerTalkClass->GetGossipOptionAction(gossipListId);
        CloseGossipMenuFor(player);
        ObjectGuid::LowType guid = player->GetGUID().GetCounter();
        auto key = s_keys.find(guid);
        if (key == s_keys.end() || !key->second.MapId)
            return true;
        if (KeyBusy(player))
        {
            Message(player, MSG_KEY_BUSY);
            return true;
        }

        if (action == ACTION_REROLL)
        {
            uint32 week = CurrentWeek();
            if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
                "SELECT 1 FROM character_mythic_plus_reroll WHERE guid = {} AND week = {}", guid, week).c_str()))
            {
                Message(player, MSG_REROLL_USED);
                return true;
            }
            if (!player->HasEnoughMoney(REROLL_COST))
            {
                Message(player, MSG_REROLL_MONEY);
                return true;
            }
            player->ModifyMoney(-int32(REROLL_COST));
            CharacterDatabase.Execute(Trinity::StringFormat("REPLACE INTO character_mythic_plus_reroll (guid, week) VALUES ({}, {})", guid, week).c_str());
            uint32 level = key->second.Level;
            SetKey(guid, RandomDungeon(key->second.MapId), level);
            Message(player, Fmt(MSG_REROLL_DONE, DungeonName(s_keys[guid].MapId).c_str(), level));
        }
        else if (action == ACTION_DOWNGRADE)
        {
            if (key->second.Level <= MIN_KEY_LEVEL)
            {
                Message(player, MSG_DOWNGRADE_MIN);
                return true;
            }
            uint32 mapId = key->second.MapId;
            uint32 level = key->second.Level - 1;
            SetKey(guid, mapId, level);
            Message(player, Fmt(MSG_DOWNGRADE_DONE, DungeonName(mapId).c_str(), level));
        }
        return true;
    }
};

void AddSC_mythic_plus()
{
    RegisterCreatureAI(npc_mythic_plus_keystone);
    new mythic_plus_group();
    RegisterSpellScript(spell_mythic_plus_battle_res);
    RegisterGameObjectAI(go_mythic_plus_vault);
    new mythic_plus_world();
    new mythic_plus_player();
    new mythic_plus_unit();
    new mythic_plus_commands();
    RegisterGameObjectAI(go_mythic_plus_font);
    RegisterGameObjectAI(go_mythic_plus_chest);
}
