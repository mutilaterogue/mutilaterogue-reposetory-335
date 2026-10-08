# Class powers of Cataclysm: Soul Shards, Eclipse, Holy Power

The 3.3.5a unit has seven power fields (mana .. runic power) and all are taken, so the server keeps the new
powers and sends them by AddonComm; the client answers `UnitPower` / `UnitPowerMax` with them.

| Type | `SPELL_POWER_*` | Class | Bar |
|---|---|---|---|
| 7 | `SOUL_SHARDS` | warlock | `ShardBar` (yours) |
| 8 | `ECLIPSE` | balance druid (Moonkin Form known) | `EclipseBarFrame` (yours) |
| 9 | `HOLY_POWER` | paladin | `PaladinPowerBar` (here) |

## Mechanics (server/class_powers.cpp)
* **Holy Power** 0..5: +1 from Crusader Strike, Holy Shock, Hammer of the Righteous (a cast). Shield of the
  Righteous and Divine Storm cost 3.
* **Eclipse** -100..+100: Wrath -13 while heading to the moon, Starfire +20 while heading to the sun (either way
  at the start). At -100 Lunar Eclipse (48518), then toward the sun; at +100 Solar Eclipse (48517), then toward
  the moon. Out of combat it drifts back to 0 (10 a second).
* **Soul Shards** 0..3: +1 when a target dies under your Drain Soul; out of combat +1 every 5 s. Soul Fire,
  Shadowburn, Death Coil cost 1.

A spell costing a power is not cast without it: the server refuses it (`OnCheckCast`) and sends
`CLASS_POWER_ERROR` (the client shows "Недостаточно силы Света" / "Недостаточно осколков души"). On the client
the action button is unusable (blue, `IsUsableAction`), and the tooltip has the cost line (red without it).
The costs are in `CLASS_POWER_COSTS` (ClassPower.lua) and the constants of class_powers.cpp: keep them alike.

The numbers are constants at the top of `class_powers.cpp`.

Note: the WotLK talent Eclipse (48516 ranks) still procs 48517 / 48518 on crits by itself.

## Hooking it up
Server:
1. `server/class_powers.cpp` into the custom scripts (`custom_script_loader.cpp` already calls `AddSC_class_powers`).
2. `server/sql/world_class_powers.sql` into the world database.

Client (FrameXML):
1. `ClassPower.lua`, `PaladinPowerBar.lua`, `PaladinPowerBar.xml` into `Interface\FrameXML\`.
2. `FrameXML.toc`, after `EclipseBarFrame.xml` (and after `Server.lua`, which it uses):
   ```
   PaladinPowerBar.xml
   ClassPower.lua
   ```
3. The texture `Interface\PlayerFrame\PaladinPowerTextures.blp` (Cataclysm's) in your patch, as
   `UI-WarlockShard` / `UI-DruidEclipse` are.

`GetSpecName()` (used by the eclipse bar) is defined here when nothing else defines it: the primary talent tree
(`GetPrimaryTalentTree`), else the tree with the most points.
