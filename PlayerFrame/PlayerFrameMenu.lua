-- Контекстное меню рамки игрока в стиле ретейла (Blizzard_UnitPopup: SELF) на MenuUtil.
-- Секции: имя, метка/фокус, группа или рейд (если в группе), подземелья, прочее, отмена.

local L = {
	INSTANCE = UNIT_FRAME_DROPDOWN_SUBSECTION_TITLE_INSTANCE or "Настройки подземелья",
	PARTY = UNIT_FRAME_DROPDOWN_SUBSECTION_TITLE_PARTY or "Настройки группы",
	RAID = UNIT_FRAME_DROPDOWN_SUBSECTION_TITLE_RAID or "Настройки рейда",
	LOOT = UNIT_FRAME_DROPDOWN_SUBSECTION_TITLE_LOOT or "Добыча",
	OTHER = UNIT_FRAME_DROPDOWN_SUBSECTION_TITLE_OTHER or "Другие настройки",
	OPT_OUT = OPT_OUT_LOOT_TITLE and OPT_OUT_LOOT_TITLE:gsub(":?%s*%%s", "") or "Отказ от добычи",
	CONVERT_TO_RAID = CONVERT_TO_RAID or "Преобразовать в рейд",
	CONVERT_TO_PARTY = CONVERT_TO_PARTY or "Преобразовать в группу",
};


local LOOT_METHODS = {
	{ "freeforall", LOOT_FREE_FOR_ALL },
	{ "roundrobin", LOOT_ROUND_ROBIN },
	{ "master", LOOT_MASTER_LOOTER },
	{ "group", LOOT_GROUP_LOOT },
	{ "needbeforegreed", LOOT_NEED_BEFORE_GREED },
};

local function InGroup()
	return GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0;
end

local function IsLeader()
	return IsRaidLeader() or IsPartyLeader();
end

local function CanChangeDifficulty()
	return not InGroup() or IsLeader();
end

local function RaidTargetText(index)
	local color = UnitPopupButtons and UnitPopupButtons["RAID_TARGET_" .. index] and UnitPopupButtons["RAID_TARGET_" .. index].color;
	local text = _G["RAID_TARGET_" .. index];
	if color then
		text = ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, text);
	end
	return ("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:14:14|t %s"):format(index, text);
end

local function AddRaidTargets(root, unit)
	local submenu = root:CreateSubmenu(RAID_TARGET_ICON);
	for index = 1, 8 do
		submenu:CreateRadio(RaidTargetText(index), function()
			return GetRaidTargetIndex(unit) == index;
		end, function()
			SetRaidTargetIcon(unit, index);
		end);
	end
	submenu:CreateRadio(RAID_TARGET_NONE, function()
		return not GetRaidTargetIndex(unit);
	end, function()
		SetRaidTargetIcon(unit, 0);
	end);
end

local function AddGroupSection(root)
	if not InGroup() then
		return;
	end
	local inRaid = GetNumRaidMembers() > 0;
	root:CreateTitle(inRaid and L.RAID or L.PARTY);

	if IsLeader() then
		local method = root:CreateSubmenu(LOOT_METHOD);
		for _, entry in ipairs(LOOT_METHODS) do
			method:CreateRadio(entry[2], function()
				return (GetLootMethod()) == entry[1];
			end, function()
				if entry[1] == "master" then
					SetLootMethod("master", UnitName("player"));
				else
					SetLootMethod(entry[1]);
				end
			end);
		end

		local threshold = root:CreateSubmenu(LOOT_THRESHOLD);
		for quality = 2, 4 do
			local color = ITEM_QUALITY_COLORS[quality];
			threshold:CreateRadio(color.hex .. _G["ITEM_QUALITY" .. quality .. "_DESC"] .. "|r", function()
				return GetLootThreshold() == quality;
			end, function()
				SetLootThreshold(quality);
			end);
		end
	end

	if (GetLootMethod()) ~= "freeforall" then
		root:CreateCheckbox(L.OPT_OUT, function()
			return GetOptOutOfLoot() and true or false;
		end, function()
			SetOptOutOfLoot(not GetOptOutOfLoot());
		end);
	end

	if IsLeader() then
		if inRaid then
			if GetNumRaidMembers() <= MEMBERS_PER_RAID_GROUP then
				root:CreateButton(L.CONVERT_TO_PARTY, function() ConvertToParty(); end);
			end
		else
			root:CreateButton(L.CONVERT_TO_RAID, function() ConvertToRaid(); end);
		end
	end

	root:CreateButton(PARTY_LEAVE, function() LeaveParty(); end);
end

local function AddInstanceSection(root)
	local lowLevel = UnitLevel("player") < 65;
	local canChange = CanChangeDifficulty();
	local _, instanceType = IsInInstance();
	local inInstance = instanceType == "party" or instanceType == "raid";
	local showDungeon = canChange and not (lowLevel and GetDungeonDifficulty() == 1);
	local showRaid = canChange and not (lowLevel and GetRaidDifficulty() == 1);
	local showReset = not inInstance and (not InGroup() or IsLeader());
	if not (showDungeon or showRaid or showReset) then
		return;
	end

	root:CreateTitle(L.INSTANCE);
	if showDungeon then
		local dungeon = root:CreateSubmenu(DUNGEON_DIFFICULTY);
		for index = 1, 3 do
			dungeon:CreateRadio(_G["DUNGEON_DIFFICULTY" .. index], function()
				return GetDungeonDifficulty() == index;
			end, function()
				SetDungeonDifficulty(index);
			end);
		end
	end
	if showRaid then
		local raid = root:CreateSubmenu(RAID_DIFFICULTY);
		for index = 1, 4 do
			raid:CreateRadio(_G["RAID_DIFFICULTY" .. index], function()
				return GetRaidDifficulty() == index;
			end, function()
				SetRaidDifficulty(index);
			end);
		end
	end
	if showReset then
		root:CreateButton(RESET_INSTANCES, function() StaticPopup_Show("CONFIRM_RESET_INSTANCES"); end);
	end
end

local function AddOtherSection(root, isVehicle)
	root:CreateTitle(L.OTHER);
	if isVehicle then
		root:CreateButton(VEHICLE_LEAVE, function() VehicleExit(); end);
	else
		local pvp = root:CreateSubmenu(PVP_FLAG);
		pvp:CreateRadio(ENABLE, function() return GetPVPDesired() and true or false; end, function() SetPVP(1); end);
		pvp:CreateRadio(DISABLE, function() return not GetPVPDesired(); end, function() SetPVP(nil); end);
	end

	local move = root:CreateSubmenu(MOVE_FRAME);
	if PLAYER_FRAME_UNLOCKED then
		move:CreateButton(LOCK_FRAME, function() PlayerFrame_SetLocked(true); end);
	else
		move:CreateButton(UNLOCK_FRAME, function() PlayerFrame_SetLocked(false); end);
	end
	move:CreateButton(RESET_POSITION, function() PlayerFrame_ResetUserPlacedPosition(); end);
	move:CreateCheckbox(PLAYER_FRAME_SHOW_CASTBARS, function()
		return PLAYER_FRAME_CASTBARS_SHOWN and true or false;
	end, function()
		PLAYER_FRAME_CASTBARS_SHOWN = not PLAYER_FRAME_CASTBARS_SHOWN;
		if PLAYER_FRAME_CASTBARS_SHOWN then
			PlayerFrame_AttachCastBar();
		else
			PlayerFrame_DetachCastBar();
		end
	end);
end

function PlayerFrameMenu_Generate(owner, root)
	local unit = PlayerFrame.unit or "player";
	local isVehicle = unit == "vehicle";

	root:CreateTitle(UnitName(unit) or UnitName("player"));
	AddRaidTargets(root, unit);
	root:CreateButton(SET_FOCUS, function() FocusUnit(unit); end);

	if not isVehicle then
		AddGroupSection(root);
		AddInstanceSection(root);
	end
	AddOtherSection(root, isVehicle);

	root:CreateButton(CANCEL, function() end);
end

function PlayerFrameMenu_Open(self)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(self, PlayerFrameMenu_Generate);
		return true;
	end
	return false;
end
