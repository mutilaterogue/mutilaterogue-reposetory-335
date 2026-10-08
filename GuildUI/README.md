# Guild UI (retail 12.1.5 Communities for 3.3.5a) + Guild Finder

`CommunitiesFrame`: the guild window in place of the Friends frame's guild tab (`ToggleFriendsFrame(3)`, the
TOGGLEGUILDTAB binding, the Friends frame's guild tab, `/guildui`, `ToggleGuildFrame()`).

Retail layout (814 x 426): the left list — the guild (banner, name, level) and «Поиск гильдии»; over the content
the guild's level and experience bar (`GuildProgression.lua`); the bottom bar — «Пригласить в гильдию» under the
list, «Набор в гильдию» and «Управление гильдией» on the right.

Side tabs (retail order):
1. **Состав** (retail columns: Ур., Класс, Имя, Зона, Звание, Заметка + a dropdown column — officer note /
   last online) — show offline (their zone column: how long ago), search, sortable columns, online first. Right click: whisper, invite to group, promote, demote, note, officer note, remove.
   Bottom: «Пригласить», «Управление гильдией» (the stock rank window).
2. **Преимущества** — the perks (`GetGuildPerkInfo`), inactive ones grey, the next one on top.
3. **Информация** (retail GuildInfo) — guild challenges (counts: a later stage), MOTD and guild info with
   «[Изменить]» (an editor window), news on the right (until the news stage: the MOTD and the event log by day),
   «Журнал» (the event log window). Leave / disband: right click on the guild in the left list.

**Поиск гильдии / Набор в гильдию** — `GuildFinder.lua` + `server/guild_finder.cpp`:
   * no guild: the window opens on the guild finder. Retail's top bar: «Интересы» and «Время и уровень»
     dropdowns, the role buttons, the search box (by name / description), «Найти»; guild cards with a green «+»
     (apply with a comment); «Мои заявки» → cancel. At most 10, they last 30 days.
   * in a guild: recruitment settings (listed, filters, comment; rank right "edit guild info" / leader),
     applicants (rank right "invite"): «Пригласить» (the normal guild invite, the player online) / «Отклонить».
     Joining a guild removes all the player's applications.

## Hooking it up
Server:
1. `server/guild_finder.cpp` into `scripts\Custom\Guild\` (next to `guild_progression.cpp`, it uses
   `guild_progression.h`); `custom_script_loader.cpp` calls `AddSC_guild_finder`.
2. `server/sql/characters_guild_finder.sql` into the characters database.

Client: `GuildUI.xml`, `GuildUI.lua`, `GuildFinder.lua`, `GuildInviteFrame.xml`, `GuildInviteFrame.lua` into
`Interface\FrameXML\`, and `GuildUI.xml`, `GuildInviteFrame.xml` into `FrameXML.toc` after `UIParent.xml`,
`FriendsFrame.xml`, `PortraitFrameTemplates.xml` and `GuildProgression.lua`.

## Guild invitation (`GuildInviteFrame.xml`)
Retail's frame in place of the stock popup: the inviter, the guild's name, its tabard ring, and (in retail's
achievement points place) the guild's level from the server (`GF_GUILD_INFO`); «Вступить» / «Отклонить
приглашение», 60 seconds. Textures: `Interface\GuildFrame\GuildExtra`, `GuildFrame`, `GuildEmblemsLG_01`
(Cataclysm / retail).

## Stage 3: guild reputation, rewards, news
**Reputation** (`server/guild_progression.cpp`, Cataclysm's `Guild::GiveReputation`): each member's own, from
Neutral (0) to Exalted (42000). A quest: max(1, its XP / 450); a kill in a guild group: max(1, its guild XP / 450);
+ the reputation gain auras; at most 4375 a week (from Wednesday, the reset hour). Lost on leaving the guild.
The bar is under the rewards (tooltip: this week's / the cap). Lua: `GetGuildFactionInfo()`, `GetGuildRepWeekly()`.

**Rewards** (`server/guild_rewards.cpp`, `world.guild_rewards`): an item, the reputation's standing (4..8), the
races, the price, the guild's level (in place of Cataclysm's achievement). «Преимущества»: perks on the left, the
rewards on the right — the requirements in red while not met, a click buys (confirmed; shift-click links).
Lua: `GetNumGuildRewards()`, `GetGuildRewardInfo(i)`, `BuyGuildReward(itemID)`.

**News** (`server/guild_news.cpp`, the last 250 of a guild): bosses killed by a guild group, epics (item level 200+,
`GuildNews.MinItemLevel`) and legendaries looted in a dungeon / raid, crafted, bought among the rewards, the guild's
level ups. «Информация» → «Новости гильдии» by day, «[Фильтры]» (retail's filters window); the event log stays
in «Журнал». Achievements (guild / members) come with stage 4.

### Hooking it up
Server:
1. `server/core/ScriptMgr_item_hooks.patch` (the loot / craft hooks are empty in your ScriptMgr: without it no
   looted / crafted news).
2. `guild_news.cpp`, `guild_news.h`, `guild_rewards.cpp` into `scripts\Custom\Guild\` (with the new
   `guild_progression.cpp` / `.h`); `custom_script_loader.cpp` calls `AddSC_guild_news`, `AddSC_guild_rewards`.
3. `sql/characters_guild_stage3.sql` (characters), `sql/world_guild_rewards.sql` (world; your items there).
4. `worldserver.conf`: the new lines of `sql/worldserver_guild_progression.conf.dist`.

Client: `GuildRewards.lua`, `GuildNews.lua` next to `GuildUI.lua` (`GuildUI.xml` loads them); the new
`GuildProgression.lua`.
