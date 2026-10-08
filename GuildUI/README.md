# Guild UI (retail 12.1.5 Communities for 3.3.5a) + Guild Finder

`CommunitiesFrame`: the guild window in place of the Friends frame's guild tab (`ToggleFriendsFrame(3)`, the
TOGGLEGUILDTAB binding, the Friends frame's guild tab, `/guildui`, `ToggleGuildFrame()`).

Retail layout (814 x 426): the left list — the guild (banner, name, level) and «Поиск гильдии»; over the content
the guild's level and experience bar (`GuildProgression.lua`); the bottom bar — «Пригласить в гильдию» under the
list, «Набор в гильдию» and «Управление гильдией» on the right.

Side tabs (retail order):
1. **Состав** — search (name / zone / rank / note / class), show offline, sortable columns, class icons,
   online first. Right click: whisper, invite to group, promote, demote, note, officer note, remove.
   Bottom: «Пригласить», «Управление гильдией» (the stock rank window).
2. **Преимущества** — the perks (`GetGuildPerkInfo`), inactive ones grey, the next one on top.
3. **Информация** — MOTD and guild info (editable with the rights, «Сохранить»), event log, leave / disband.

**Поиск гильдии / Набор в гильдию** — `GuildFinder.lua` + `server/guild_finder.cpp`:
   * no guild: the window opens on the guild finder. Filters (time, roles, interests, level) → «Найти»;
     a guild → «Подать заявку» with a comment; «Мои заявки» → cancel. At most 10, they last 30 days.
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
