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
 *   - everybody is moved to the instance entrance, 10 s countdown behind the barrier (BARRIER_RADIUS,
 *     optional gameobject BARRIER_ENTRY as the visual), then the timer starts.
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
 *       "MPLUS_COMPLETE" : timed : upgrade : timeMs : level : newLevel : score
 *       "MPLUS_RESULT" : message
 *  C->S "MPLUS_GET", "MPLUS_INSERT", "MPLUS_REMOVE", "MPLUS_START", "MPLUS_CLOSE",
 *       "MPLUS_RELEASE" (release spirit: alive at the entrance or the last killed boss)
 *
 * GM: .mplus key <level> [mapId], .mplus info, .mplus complete, .mplus reset
 *
 * Setup: sql/world_mythic_plus.sql, sql/characters_mythic_plus.sql, AddSC_mythic_plus() in custom_script_loader.cpp.
 */

#include "ScriptMgr.h"
#include "Custom\AddonComm\AddonComm.h"
#include "Chat.h"
#include "ChatCommand.h"
#include "Creature.h"
#include "DatabaseEnv.h"
#include "GameObject.h"
#include "GameObjectAI.h"
#include "GameTime.h"
#include "Group.h"
#include "Item.h"
#include "Log.h"
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
    constexpr uint32 FONT_ENTRY = 700010;
    constexpr uint32 CHEST_ENTRY = 700011;
    constexpr uint32 BARRIER_ENTRY = 700012;        // countdown barrier at the entrance (optional template)
    constexpr float BARRIER_RADIUS = 12.0f;         // during the countdown players stay this close to the entrance

    constexpr uint32 MIN_KEY_LEVEL = 1;
    constexpr uint32 MAX_KEY_LEVEL = 30;
    constexpr uint32 FIRST_AFFIX_LEVEL = 2;
    constexpr uint32 SECOND_AFFIX_LEVEL = 4;
    constexpr uint32 THIRD_AFFIX_LEVEL = 7;

    constexpr float LEVEL_SCALE = 1.08f;            // health and damage per level above 1
    constexpr float FORCES_AUTO_PCT = 0.9f;         // required forces when the dungeon row has 0
    constexpr uint32 COUNTDOWN_MS = 10 * IN_MILLISECONDS;
    constexpr uint32 DEATH_PENALTY = 5;             // seconds
    constexpr uint32 DEFAULT_TIME_LIMIT = 30 * MINUTE;
    constexpr uint32 CHEST_DESPAWN = 10 * MINUTE;
    constexpr time_t WEEK_EPOCH = 1704265200;       // Wed 2024-01-03 07:00 UTC - weekly reset
    constexpr float BOLSTER_RANGE = 30.0f;
    constexpr float SANGUINE_RANGE = 5.0f;
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
        ObjectGuid BarrierGuid;
        Position LastBossPos;                   // where the last killed boss died
        bool HasLastBoss = false;
        uint32 SyncTimer = 0;
        uint32 TickTimer = 0;
        uint32 GrievousTimer = 0;
    };

    std::unordered_map<uint32, DungeonInfo> s_dungeons;
    std::map<uint32, AffixInfo> s_affixes;
    std::vector<std::vector<uint32>> s_rotation;
    std::unordered_map<uint32, uint32> s_forces;             // creature entry -> count
    std::unordered_map<ObjectGuid::LowType, Keystone> s_keys;
    std::unordered_map<uint32, Run> s_runs;                  // instanceId -> run
    std::unordered_map<ObjectGuid, ObjectGuid> s_fontUser;   // player -> font
    std::unordered_set<ObjectGuid> s_slotted;                // players with the key in the font

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
    char const* const MSG_GO = "\xd0\x98\xd1\x81\xd0\xbf\xd1\x8b\xd1\x82\xd0\xb0\xd0\xbd\xd0\xb8\xd0\xb5 \xd0\xbd\xd0\xb0\xd1\x87\xd0\xb0\xd0\xbb\xd0\xbe\xd1\x81\xd1\x8c!";
    char const* const MSG_TIME_UP = "\xd0\x92\xd1\x80\xd0\xb5\xd0\xbc\xd1\x8f \xd0\xb2\xd1\x8b\xd1\x88\xd0\xbb\xd0\xbe! \xd0\x9a\xd0\xbb\xd1\x8e\xd1\x87 \xd0\xbf\xd0\xbe\xd1\x82\xd0\xb5\xd1\x80\xd1\x8f\xd0\xbb \xd1\x83\xd1\x80\xd0\xbe\xd0\xb2\xd0\xb5\xd0\xbd\xd1\x8c.";
    char const* const MSG_NEW_KEY = "\xd0\x92\xd1\x8b \xd0\xbf\xd0\xbe\xd0\xbb\xd1\x83\xd1\x87\xd0\xb8\xd0\xbb\xd0\xb8 \xd1\x8d\xd0\xbf\xd0\xbe\xd1\x85\xd0\xb0\xd0\xbb\xd1\x8c\xd0\xbd\xd1\x8b\xd0\xb9 \xd0\xba\xd0\xbb\xd1\x8e\xd1\x87: %s (%u).";
    char const* const MSG_KEY_UPGRADED = "\xd0\x9a\xd0\xbb\xd1\x8e\xd1\x87 \xd1\x83\xd0\xbb\xd1\x83\xd1\x87\xd1\x88\xd0\xb5\xd0\xbd: %s (%u).";
    char const* const MSG_DONE_TIMED = "\xd0\xad\xd0\xbf\xd0\xbe\xd1\x85\xd0\xb0\xd0\xbb\xd1\x8c\xd0\xbd\xd1\x8b\xd0\xb9 \xd0\xba\xd0\xbb\xd1\x8e\xd1\x87 +%u \xd0\xbf\xd1\x80\xd0\xbe\xd0\xb9\xd0\xb4\xd0\xb5\xd0\xbd \xd0\xb2 \xd1\x81\xd1\x80\xd0\xbe\xd0\xba! \xd0\x92\xd1\x80\xd0\xb5\xd0\xbc\xd1\x8f: %s (+%u)";
    char const* const MSG_DONE_LATE = "\xd0\xad\xd0\xbf\xd0\xbe\xd1\x85\xd0\xb0\xd0\xbb\xd1\x8c\xd0\xbd\xd1\x8b\xd0\xb9 \xd0\xba\xd0\xbb\xd1\x8e\xd1\x87 +%u \xd0\xbf\xd1\x80\xd0\xbe\xd0\xb9\xd0\xb4\xd0\xb5\xd0\xbd. \xd0\x92\xd1\x80\xd0\xb5\xd0\xbc\xd1\x8f: %s (\xd0\xba\xd0\xbb\xd1\x8e\xd1\x87 \xd0\xbd\xd0\xb5 \xd1\x83\xd0\xbb\xd1\x83\xd1\x87\xd1\x88\xd0\xb5\xd0\xbd)";
    char const* const MSG_DONE_ZERO = "\xd0\xad\xd0\xbf\xd0\xbe\xd1\x85\xd0\xb0\xd0\xbb\xd1\x8c\xd0\xbd\xd0\xbe\xd0\xb5 \xd0\xbf\xd0\xbe\xd0\xb4\xd0\xb7\xd0\xb5\xd0\xbc\xd0\xb5\xd0\xbb\xd1\x8c\xd0\xb5 \xd0\xbf\xd1\x80\xd0\xbe\xd0\xb9\xd0\xb4\xd0\xb5\xd0\xbd\xd0\xbe!";
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
            && !creature->IsCivilian() && creature->IsHostileToPlayers();
    }

    bool IsBoss(Creature const* creature)
    {
        return creature && (creature->IsDungeonBoss() || creature->isWorldBoss());
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
            CharacterDatabase.Execute(Trinity::StringFormat("REPLACE INTO character_mythic_keystone (guid, map_id, level) VALUES ({}, {}, {})", guid, key.MapId, key.Level).c_str());
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
            return true;
        ItemPosCountVec dest;
        if (player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest, KEYSTONE_ITEM, 1) != EQUIP_ERR_OK)
            return false;
        if (Item* item = player->StoreNewItem(dest, KEYSTONE_ITEM, true))
        {
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
            return;
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
            "FROM character_mythic_plus_best WHERE guid = {}", player->GetGUID().GetCounter()).c_str()))
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

    void SaveBest(Player* player, Run const& run, bool timed, uint32 timeMs, uint32 score)
    {
        ObjectGuid::LowType guid = player->GetGUID().GetCounter();
        if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
            "SELECT CAST(score AS SIGNED) FROM character_mythic_plus_best WHERE guid = {} AND map_id = {}", guid, run.MapId).c_str()))
            if (uint32(result->Fetch()[0].GetInt64()) >= score)
                return;
        CharacterDatabase.DirectExecute(Trinity::StringFormat(
            "REPLACE INTO character_mythic_plus_best (guid, map_id, level, time_ms, timed, affixes, score, date) VALUES ({}, {}, {}, {}, {}, '{}', {}, UNIX_TIMESTAMP())",
            guid, run.MapId, run.Level, timeMs, timed ? 1 : 0, JoinIds(run.Affixes), score).c_str());
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
            itr = run.Scaled.emplace(creature->GetGUID(), CreatureScale{ creature->GetFlatModifierValue(UNIT_MOD_HEALTH, BASE_VALUE), 1.0f }).first;
        if (std::fabs(itr->second.Applied - mult) < 0.001f)
            return;
        // through the health modifier: UpdateMaxHealth (auras, evade) keeps the scaled value
        float pct = creature->GetHealthPct();
        creature->SetStatFlatModifier(UNIT_MOD_HEALTH, BASE_VALUE, itr->second.BaseHealth * mult);
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
            Message(player, text);
            SaveBest(player, run, timed, timeMs, score);
            sAddonComm->Send(player, "MPLUS_COMPLETE", timed ? 1 : 0, upgrade, timeMs, run.Level, newLevel, score);
            if (player->GetGUID().GetCounter() != run.KeyOwner)
                GrantNewKey(player, std::max(MIN_KEY_LEVEL, run.Level - 1));
            SendRating(player);
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
            if (!found && std::none_of(run.Bosses.begin(), run.Bosses.end(), [&](Boss const& b) { return b.Entry == creature->GetEntry(); }))
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
        if (!font || !player->IsWithinDistInMap(font, 10.0f))
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
        if (GameObject* barrier = SpawnGameObject(map, BARRIER_ENTRY, run.StartPos, COUNTDOWN_MS / IN_MILLISECONDS + 5))
            run.BarrierGuid = barrier->GetGUID();

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

    // ---------------------------------------------------------------- comm handlers
    void SendAll(Player* player)
    {
        for (auto const& pair : s_affixes)
            sAddonComm->Send(player, "MPLUS_AFFIX", pair.first, Sanitize(pair.second.Name), pair.second.Icon, Sanitize(pair.second.Description));
        sAddonComm->Send(player, "MPLUS_WEEK", JoinIds(WeekAffixes()));
        SendKey(player);
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

        TC_LOG_INFO("server.loading", ">> Mythic+: {} dungeons, {} affixes, {} rotation weeks, {} forces overrides",
            s_dungeons.size(), s_affixes.size(), s_rotation.size(), s_forces.size());
    }

    void LoadKey(Player* player)
    {
        ObjectGuid::LowType guid = player->GetGUID().GetCounter();
        s_keys.erase(guid);
        if (QueryResult result = CharacterDatabase.Query(Trinity::StringFormat(
            "SELECT CAST(map_id AS SIGNED), CAST(level AS SIGNED) FROM character_mythic_keystone WHERE guid = {}", guid).c_str()))
        {
            Field* f = result->Fetch();
            s_keys[guid] = { uint32(f[0].GetInt64()), uint32(f[1].GetInt64()) };
        }

        // item <-> row: the row is the truth
        bool hasRow = HasKey(player);
        bool hasItem = player->HasItemCount(KEYSTONE_ITEM, 1, true);
        if (hasRow && !hasItem)
            GiveKeyItem(player);
        else if (!hasRow && hasItem)
            player->DestroyItemCount(KEYSTONE_ITEM, 1, true);
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
                // the barrier: nobody leaves the entrance before the start
                ForEachPlayer(map, [&](Player* player)
                {
                    if (player->IsAlive() && !player->IsBeingTeleported() && player->GetExactDist2d(&run.StartPos) > BARRIER_RADIUS)
                        player->NearTeleportTo(run.StartPos.GetPositionX(), run.StartPos.GetPositionY(), run.StartPos.GetPositionZ(), player->GetOrientation());
                });
            }
            else
            {
                run.CountdownLeft = 0;
                run.State = RUN_ACTIVE;
                if (GameObject* barrier = map->GetGameObject(run.BarrierGuid))
                    barrier->DespawnOrUnsummon();
                run.BarrierGuid.Clear();
                ForEachPlayer(map, [&](Player* player) { Message(player, MSG_GO); });
                SyncRun(run);
            }
            return;
        }

        if (run.State != RUN_ACTIVE)
            return;

        run.ElapsedMs += diff;

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
                        AffixDamage(run, player, uint32(player->GetMaxHealth() * 0.015f * d.Grievous), DAMAGE_DROWNING);
                    }
                }
            });

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

// ---------------------------------------------------------------- Font of Power
struct go_mythic_plus_font : public GameObjectAI
{
    go_mythic_plus_font(GameObject* go) : GameObjectAI(go) { }

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
public:
    mythic_plus_world() : WorldScript("mythic_plus_world") { }

    void OnStartup() override
    {
        LoadData();
    }

    void OnUpdate(uint32 diff) override
    {
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
        sAddonComm->Register(std::string("MPLUS_INSERT"), &HandleInsert);
        sAddonComm->Register(std::string("MPLUS_REMOVE"), &HandleRemove);
        sAddonComm->Register(std::string("MPLUS_START"), &HandleStart);
        sAddonComm->Register(std::string("MPLUS_CLOSE"), &HandleClose);
        sAddonComm->Register(std::string("MPLUS_RELEASE"), &HandleRelease);
    }

    void OnLogin(Player* player, bool /*firstLogin*/) override
    {
        LoadKey(player);
        SendAll(player);
    }

    void OnLogout(Player* player) override
    {
        s_fontUser.erase(player->GetGUID());
        s_slotted.erase(player->GetGUID());
        s_keys.erase(player->GetGUID().GetCounter());
    }

    void OnMapChanged(Player* player) override
    {
        Map* map = player->GetMap();
        if (!IsMythicMap(map))
        {
            player->SetControlled(false, UNIT_STATE_ROOT);
            sAddonComm->Send(player, "MPLUS_RUN", 0, 0, 0, "", 0, 0, 0, DEATH_PENALTY, 0, 0, 0, 0);
            return;
        }
        Run& run = GetOrCreateRun(map);
        SendBosses(player, run);
        SendRun(player, run);
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
    mythic_plus_unit() : UnitScript("mythic_plus_unit") { }

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
            damage = T(damage * mult);
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
    }
};

// ---------------------------------------------------------------- commands
class mythic_plus_commands : public CommandScript
{
public:
    mythic_plus_commands() : CommandScript("mythic_plus_commands") { }

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
            handler->PSendSysMessage("mplus: map {} is not in mythic_plus_dungeon", map);
            return false;
        }
        SetKey(target->GetGUID().GetCounter(), level ? map : 0, level);
        handler->PSendSysMessage("mplus: {} key {} +{}", target->GetName(), level ? DungeonName(map) : "-", level);
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
        handler->PSendSysMessage("mplus: map {} instance {} state {} level {} affixes {} time {}/{}s deaths {} forces {}/{} bosses {}/{}",
            run->MapId, run->InstanceId, uint32(run->State), run->Level, JoinIds(run->Affixes), run->ElapsedMs / IN_MILLISECONDS, run->TimeLimit,
            run->Deaths, run->Forces, run->ForcesMax, std::count_if(run->Bosses.begin(), run->Bosses.end(), [](Boss const& b) { return b.Killed; }), run->Bosses.size());
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

void AddSC_mythic_plus()
{
    new mythic_plus_world();
    new mythic_plus_player();
    new mythic_plus_unit();
    new mythic_plus_commands();
    RegisterGameObjectAI(go_mythic_plus_font);
}
