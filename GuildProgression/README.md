# Guild progression (Cataclysm's guild levels on 3.3.5a)

Stage 1 of the guild system: guild level 1..25, guild experience, guild perks. Ported from TrinityCore 4.3.4
(`Guild::GiveXP`, `KillRewarder::_RewardGuildXP`, `Player::RewardQuest`, `Group::GetGuildXpRateForPlayer`),
built on script hooks: the core's `Guild` is not patched.

## Experience
* a quest rewarded: its XP * `Rate.XP.Quest` * 0.25
* a creature killed in a guild group (dungeon: 3+ of the guild, raid: 80% of its size), each member in reward
  range: the kill's XP * 4 * the group rate (dungeon 3: 0.5, 4: 1, 5: 1.25; raid 1) * 1.25 in a heroic dungeon
* below level 20 at most 7 807 500 a day (the day starts at 06:00)

The constants are at the top of `server/guild_progression.cpp`.

## Perks
`guild_perk_spells` (made from `GuildPerkSpells.dbc`): the members know the spells of their guild's level -
learnt at login, on joining and at a level up, unlearnt on leaving / disbanding. The spells have to be in
`Spell.dbc` (server and client); a spell missing there is skipped.

## Hooking it up
Server:
1. `server/guild_progression.cpp` into the custom scripts (`custom_script_loader.cpp` calls `AddSC_guild_progression`).
2. `server/sql/characters_guild_progression.sql` (characters), `server/sql/world_guild_progression.sql` (world).

Client: `GuildProgression.lua` into `Interface\FrameXML\` and `FrameXML.toc` (anywhere; it waits for `Server.lua`).

## Lua API (Cataclysm's / retail's)
| Function | Returns |
|---|---|
| `GetGuildLevel()` | level (0 without a guild), 25 |
| `UnitGetGuildXP("player")` | experience, to the next level, today's, today's cap (0: none) |
| `GetNumGuildPerks()` | the number of perks |
| `GetGuildPerkInfo(i)` | name, spellID, icon, description, guild level |
| `IsGuildPerkActive(i)` | the guild has it |
| `GuildProgression_RegisterCallback(func)` | `func("GUILD_XP_UPDATE")`, `func("GUILD_PERK_UPDATE")` |

## Next stages
2. The retail Communities guild UI (roster, info, perks, rewards, news).
3. Guild reputation, rewards, news.
4. Guild challenges, guild achievements.
