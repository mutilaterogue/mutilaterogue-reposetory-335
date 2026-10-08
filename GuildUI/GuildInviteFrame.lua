-- ============================================================
--  The guild invitation (retail GuildInviteFrame) for 3.3.5a: GUILD_INVITE_REQUEST gives the inviter and
--  the guild's name only; the guild's level comes from the server (guild_finder.cpp, "GF_GUILD_INFO").
--  The stock StaticPopup "GUILD_INVITE" (UIParent_OnEvent) is not shown any more.
-- ============================================================

-- percent-encoded text, as guild_finder.cpp
local function Encode(text)
	return (tostring(text or ""):gsub("[%%:,;%./|%c]", function(c) return string.format("%%%02X", c:byte()); end));
end

local function Decode(text)
	return (tostring(text or ""):gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)); end));
end

function GuildInviteFrame_OnLoad(self)
	-- retail's translucent frame: a dark back, the gold dialog border
	self:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	});
	self:SetBackdropColor(0, 0, 0, 0.85);
	self:RegisterEvent("GUILD_INVITE_REQUEST");
	self:RegisterEvent("GUILD_INVITE_CANCEL");
	self:RegisterEvent("PLAYER_ENTERING_WORLD");
	tinsert(UISpecialFrames, self:GetName());
	-- this frame instead of the stock popup
	UIParent:UnregisterEvent("GUILD_INVITE_REQUEST");
	UIParent:UnregisterEvent("GUILD_INVITE_CANCEL");
end

local function OnGuildInfo(name, level, members)
	local frame = GuildInviteFrame;
	if ( frame:IsShown() and frame.guildName == name ) then
		frame.Points.Text:SetText(tonumber(level) or 0);
		frame.members = tonumber(members);
		frame.Points:Show();
	end
end

function GuildInviteFrame_OnEvent(self, event, ...)
	if ( event == "PLAYER_ENTERING_WORLD" ) then
		-- Server.lua may load after this file
		if ( not self.registered and Comm_Register ) then
			Comm_Register("GF_GUILD_INFO", function(name, ...)
				OnGuildInfo(Decode(name), ...);
			end);
			self.registered = true;
		end
	elseif ( event == "GUILD_INVITE_REQUEST" ) then
		local inviterName, guildName = ...;
		self.inviter = inviterName;
		self.guildName = guildName;
		self.members = nil;
		GuildInviteFrameInviterName:SetText(inviterName);
		GuildInviteFrameGuildName:SetText(guildName);
		self.Points.Text:SetText("");
		self.Points:Hide();
		self.accepted = nil;
		self.elapsed = 0;
		self:Show();
		PlaySound("igPlayerInvite");
		if ( Comm_Send ) then
			Comm_Send("GF_GUILD_INFO", Encode(guildName));
		end
	elseif ( event == "GUILD_INVITE_CANCEL" ) then
		self.accepted = true;		-- cancelled by the inviter: nothing to decline
		self:Hide();
	end
end

function GuildInviteFrame_OnHide(self)
	if ( not self.accepted ) then
		DeclineGuild();
	end
	self.accepted = nil;
	PlaySound("igMainMenuClose");
end

function GuildInviteFrame_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_CURSOR");
	GameTooltip:SetText(self.guildName or GUILD, 1, 0.82, 0);
	GameTooltip:AddLine(format("Приглашает: %s", self.inviter or ""), 1, 1, 1);
	if ( self.members ) then
		GameTooltip:AddLine(format("Участников: %d", self.members), 1, 1, 1);
	end
	GameTooltip:Show();
end
