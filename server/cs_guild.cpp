/*
 * This file is part of the TrinityCore Project. See AUTHORS file for Copyright information
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

/* ScriptData
Name: guild_commandscript
%Complete: 100
Comment: All guild related commands
Category: commandscripts
EndScriptData */

#include "ScriptMgr.h"
#include "CharacterCache.h"
#include "Chat.h"
#include "Guild.h"
#include "GuildMgr.h"
#include "Language.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "RBAC.h"
#include "StringFormat.h"
#include "Custom\Guild\guild_progression.h"

#if TRINITY_COMPILER == TRINITY_COMPILER_GNU
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#endif

using namespace Trinity::ChatCommands;
class guild_commandscript : public CommandScript
{
public:
    guild_commandscript() : CommandScript("guild_commandscript") { }

    std::vector<ChatCommand> GetCommands() const override
    {
        // .guild level ... - the guild's level, experience and perks (Custom\Guild\guild_progression.cpp)
        static std::vector<ChatCommand> guildLevelCommandTable =
        {
            { "set",      rbac::RBAC_PERM_COMMAND_GUILD_CREATE,   true, &HandleGuildLevelSetCommand,         "" },
            { "xp",       rbac::RBAC_PERM_COMMAND_GUILD_CREATE,   true, &HandleGuildLevelXpCommand,          "" },
            { "reset",    rbac::RBAC_PERM_COMMAND_GUILD_CREATE,   true, &HandleGuildLevelResetCommand,       "" },
            { "info",     rbac::RBAC_PERM_COMMAND_GUILD_INFO,     true, &HandleGuildLevelInfoCommand,        "" },
        };
        static std::vector<ChatCommand> guildCommandTable =
        {
            { "create",   rbac::RBAC_PERM_COMMAND_GUILD_CREATE,   true, &HandleGuildCreateCommand,           "" },
            { "delete",   rbac::RBAC_PERM_COMMAND_GUILD_DELETE,   true, &HandleGuildDeleteCommand,           "" },
            { "invite",   rbac::RBAC_PERM_COMMAND_GUILD_INVITE,   true, &HandleGuildInviteCommand,           "" },
            { "uninvite", rbac::RBAC_PERM_COMMAND_GUILD_UNINVITE, true, &HandleGuildUninviteCommand,         "" },
            { "rank",     rbac::RBAC_PERM_COMMAND_GUILD_RANK,     true, &HandleGuildRankCommand,             "" },
            { "rename",   rbac::RBAC_PERM_COMMAND_GUILD_RENAME,   true, &HandleGuildRenameCommand,           "" },
            { "info",     rbac::RBAC_PERM_COMMAND_GUILD_INFO,     true, &HandleGuildInfoCommand,             "" },
            { "level",    rbac::RBAC_PERM_COMMAND_GUILD_INFO,     true, nullptr, "", guildLevelCommandTable },
        };
        static std::vector<ChatCommand> commandTable =
        {
            { "guild", rbac::RBAC_PERM_COMMAND_GUILD,  true, nullptr, "", guildCommandTable },
        };
        return commandTable;
    }

    /** \brief GM command level 3 - Create a guild.
     *
     * This command allows a GM (level 3) to create a guild.
     *
     * The "args" parameter contains the name of the guild leader
     * and then the name of the guild.
     *
     */
    static bool HandleGuildCreateCommand(ChatHandler* handler, char const* args)
    {
        if (!*args)
            return false;

        // if not guild name only (in "") then player name
        Player* target;
        if (!handler->extractPlayerTarget(*args != '"' ? (char*)args : nullptr, &target))
            return false;

        char* tailStr = *args != '"' ? strtok(nullptr, "") : (char*)args;
        if (!tailStr)
            return false;

        char* guildStr = handler->extractQuotedArg(tailStr);
        if (!guildStr)
            return false;

        std::string guildName = guildStr;

        if (target->GetGuildId())
        {
            handler->SendSysMessage(LANG_PLAYER_IN_GUILD);
            handler->SetSentErrorMessage(true);
            return false;
        }

        if (sGuildMgr->GetGuildByName(guildName))
        {
            handler->SendSysMessage(LANG_GUILD_RENAME_ALREADY_EXISTS);
            handler->SetSentErrorMessage(true);
            return false;
        }

        if (sObjectMgr->IsReservedName(guildName) || !sObjectMgr->IsValidCharterName(guildName))
        {
            handler->SendSysMessage(LANG_BAD_VALUE);
            handler->SetSentErrorMessage(true);
            return false;
        }

        Guild* guild = new Guild;
        if (!guild->Create(target, guildName))
        {
            delete guild;
            handler->SendSysMessage(LANG_GUILD_NOT_CREATED);
            handler->SetSentErrorMessage(true);
            return false;
        }

        sGuildMgr->AddGuild(guild);

        return true;
    }

    static bool HandleGuildDeleteCommand(ChatHandler* handler, char const* args)
    {
        if (!*args)
            return false;

        char* guildStr = handler->extractQuotedArg((char*)args);
        if (!guildStr)
            return false;

        std::string guildName = guildStr;

        Guild* targetGuild = sGuildMgr->GetGuildByName(guildName);
        if (!targetGuild)
            return false;

        targetGuild->Disband();
        return true;
    }

    static bool HandleGuildInviteCommand(ChatHandler* handler, char const* args)
    {
        if (!*args)
            return false;

        // if not guild name only (in "") then player name
        ObjectGuid targetGuid;
        if (!handler->extractPlayerTarget(*args != '"' ? (char*)args : nullptr, nullptr, &targetGuid))
            return false;

        char* tailStr = *args != '"' ? strtok(nullptr, "") : (char*)args;
        if (!tailStr)
            return false;

        char* guildStr = handler->extractQuotedArg(tailStr);
        if (!guildStr)
            return false;

        std::string guildName = guildStr;
        Guild* targetGuild = sGuildMgr->GetGuildByName(guildName);
        if (!targetGuild)
            return false;

        // player's guild membership checked in AddMember before add
        CharacterDatabaseTransaction trans(nullptr);
        return targetGuild->AddMember(trans, targetGuid);
    }

    static bool HandleGuildUninviteCommand(ChatHandler* handler, char const* args)
    {
        Player* target;
        ObjectGuid targetGuid;
        if (!handler->extractPlayerTarget((char*)args, &target, &targetGuid))
            return false;

        ObjectGuid::LowType guildId = target ? target->GetGuildId() : sCharacterCache->GetCharacterGuildIdByGuid(targetGuid);
        if (!guildId)
            return false;

        Guild* targetGuild = sGuildMgr->GetGuildById(guildId);
        if (!targetGuild)
            return false;

        CharacterDatabaseTransaction trans(nullptr);
        targetGuild->DeleteMember(trans, targetGuid, false, true);
        return true;
    }

    static bool HandleGuildRankCommand(ChatHandler* handler, Optional<PlayerIdentifier> player, uint8 rank)
    {
        if (!player)
            player = PlayerIdentifier::FromTargetOrSelf(handler);
        if (!player)
            return false;

        ObjectGuid::LowType guildId = player->IsConnected() ? player->GetConnectedPlayer()->GetGuildId() : sCharacterCache->GetCharacterGuildIdByGuid(*player);
        if (!guildId)
            return false;

        Guild* targetGuild = sGuildMgr->GetGuildById(guildId);
        if (!targetGuild)
            return false;

        return targetGuild->ChangeMemberRank(nullptr, *player, rank);
    }

    static bool HandleGuildRenameCommand(ChatHandler* handler, char const* _args)
    {
        if (!*_args)
            return false;

        char *args = (char *)_args;

        char const* oldGuildStr = handler->extractQuotedArg(args);
        if (!oldGuildStr)
        {
            handler->SendSysMessage(LANG_BAD_VALUE);
            handler->SetSentErrorMessage(true);
            return false;
        }

        char const* newGuildStr = handler->extractQuotedArg(strtok(nullptr, ""));
        if (!newGuildStr)
        {
            handler->SendSysMessage(LANG_INSERT_GUILD_NAME);
            handler->SetSentErrorMessage(true);
            return false;
        }

        Guild* guild = sGuildMgr->GetGuildByName(oldGuildStr);
        if (!guild)
        {
            handler->PSendSysMessage(LANG_COMMAND_COULDNOTFIND, oldGuildStr);
            handler->SetSentErrorMessage(true);
            return false;
        }

        if (sGuildMgr->GetGuildByName(newGuildStr))
        {
            handler->PSendSysMessage(LANG_GUILD_RENAME_ALREADY_EXISTS, newGuildStr);
            handler->SetSentErrorMessage(true);
            return false;
        }

        if (!guild->SetName(newGuildStr))
        {
            handler->SendSysMessage(LANG_BAD_VALUE);
            handler->SetSentErrorMessage(true);
            return false;
        }

        handler->PSendSysMessage(LANG_GUILD_RENAME_DONE, oldGuildStr, newGuildStr);
        return true;
    }

    static bool HandleGuildInfoCommand(ChatHandler* handler, Optional<Variant<ObjectGuid::LowType, std::string_view>> const& guildIdentifier)
    {
        Guild* guild = nullptr;

        if (guildIdentifier)
        {
            if (ObjectGuid::LowType const* guid = std::get_if<ObjectGuid::LowType>(&*guildIdentifier))
                guild = sGuildMgr->GetGuildById(*guid);
            else
                guild = sGuildMgr->GetGuildByName(guildIdentifier->get<std::string_view>());
        }
        else if (Optional<PlayerIdentifier> target = PlayerIdentifier::FromTargetOrSelf(handler); target && target->IsConnected())
            guild = target->GetConnectedPlayer()->GetGuild();

        if (!guild)
            return false;

        // Display Guild Information
        handler->PSendSysMessage(LANG_GUILD_INFO_NAME, guild->GetName().c_str(), guild->GetId()); // Guild Id + Name

        std::string guildMasterName;
        if (sCharacterCache->GetCharacterNameByGuid(guild->GetLeaderGUID(), guildMasterName))
            handler->PSendSysMessage(LANG_GUILD_INFO_GUILD_MASTER, guildMasterName.c_str(), guild->GetLeaderGUID().ToString().c_str()); // Guild Master

        // Format creation date
        char createdDateStr[20];
        time_t createdDate = guild->GetCreatedDate();
        tm localTm;
        strftime(createdDateStr, 20, "%Y-%m-%d %H:%M:%S", localtime_r(&createdDate, &localTm));

        handler->PSendSysMessage(LANG_GUILD_INFO_CREATION_DATE, createdDateStr); // Creation Date
        handler->PSendSysMessage(LANG_GUILD_INFO_MEMBER_COUNT, guild->GetMemberCount()); // Number of Members
        handler->PSendSysMessage(LANG_GUILD_INFO_BANK_GOLD, guild->GetBankMoney() / 100 / 100); // Bank Gold (in gold coins)
        handler->PSendSysMessage(LANG_GUILD_INFO_MOTD, guild->GetMOTD().c_str()); // Message of the Day
        handler->PSendSysMessage(LANG_GUILD_INFO_EXTRA_INFO, guild->GetInfo().c_str()); // Extra Information
        return true;
    }

    // ------------------------------------------------------------ .guild level ...
    // the guild: "Guild Name" in quotes, else the selected player's (or your own)
    static Guild* ExtractLevelGuild(ChatHandler* handler, char* rest)
    {
        if (rest && *rest)
        {
            if (char* name = handler->extractQuotedArg(rest))
                return sGuildMgr->GetGuildByName(name);
            return nullptr;
        }
        Player* target = handler->getSelectedPlayerOrSelf();
        return target ? target->GetGuild() : nullptr;
    }

    static Guild* GuildOrError(ChatHandler* handler, char* rest)
    {
        Guild* guild = ExtractLevelGuild(handler, rest);
        if (!guild)
        {
            handler->SendSysMessage("Гильдия не найдена: укажите \"Название гильдии\" или выберите её участника.");
            handler->SetSentErrorMessage(true);
        }
        return guild;
    }

    static void PrintLevel(ChatHandler* handler, Guild* guild)
    {
        GuildProgression::Info info = GuildProgression::GetInfo(guild->GetId());
        handler->PSendSysMessage("Гильдия <%s>: уровень %u/%u, опыт %llu / %llu, сегодня %llu%s",
            guild->GetName().c_str(), uint32(info.Level), uint32(GuildProgression::GetMaxLevel()),
            (unsigned long long)info.Experience, (unsigned long long)info.ToNextLevel, (unsigned long long)info.Today,
            info.DailyCap ? Trinity::StringFormat(" / {}", info.DailyCap).c_str() : " (без лимита)");
    }

    // .guild level set <level> ["Guild Name"]
    static bool HandleGuildLevelSetCommand(ChatHandler* handler, char const* args)
    {
        if (!*args)
            return false;
        char* levelStr = strtok((char*)args, " ");
        char* rest = strtok(nullptr, "");
        int32 level = levelStr ? atoi(levelStr) : 0;
        if (level < 1 || level > GuildProgression::GetMaxLevel())
        {
            handler->PSendSysMessage("Уровень гильдии: 1 .. %u", uint32(GuildProgression::GetMaxLevel()));
            handler->SetSentErrorMessage(true);
            return false;
        }
        Guild* guild = GuildOrError(handler, rest);
        if (!guild)
            return false;
        GuildProgression::SetLevel(guild->GetId(), uint8(level));
        PrintLevel(handler, guild);
        return true;
    }

    // .guild level xp <amount> ["Guild Name"] - as earned, the daily cap ignored
    static bool HandleGuildLevelXpCommand(ChatHandler* handler, char const* args)
    {
        if (!*args)
            return false;
        char* amountStr = strtok((char*)args, " ");
        char* rest = strtok(nullptr, "");
        long long amount = amountStr ? atoll(amountStr) : 0;
        if (amount <= 0)
        {
            handler->SendSysMessage("Укажите опыт больше 0.");
            handler->SetSentErrorMessage(true);
            return false;
        }
        Guild* guild = GuildOrError(handler, rest);
        if (!guild)
            return false;
        GuildProgression::AddExperience(guild->GetId(), uint64(amount), true);
        PrintLevel(handler, guild);
        return true;
    }

    // .guild level reset ["Guild Name"] - today's experience back to 0
    static bool HandleGuildLevelResetCommand(ChatHandler* handler, char const* args)
    {
        Guild* guild = GuildOrError(handler, (char*)args);
        if (!guild)
            return false;
        GuildProgression::ResetToday(guild->GetId());
        PrintLevel(handler, guild);
        return true;
    }

    // .guild level info ["Guild Name"]
    static bool HandleGuildLevelInfoCommand(ChatHandler* handler, char const* args)
    {
        Guild* guild = GuildOrError(handler, (char*)args);
        if (!guild)
            return false;
        PrintLevel(handler, guild);
        return true;
    }
};

void AddSC_guild_commandscript()
{
    new guild_commandscript();
}
