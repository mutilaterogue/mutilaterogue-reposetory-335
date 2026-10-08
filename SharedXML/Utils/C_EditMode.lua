local ipairs = ipairs
local tonumber = tonumber
local type = type
local mathfloor = math.floor
local strchar, strconcat, strformat = string.char, strconcat, string.format
local tconcat, tinsert, twipe = table.concat, table.insert, table.wipe

local GetCVar = GetCVar
local SetCVar = SetCVar

local CopyTable = CopyTable
local FireCustomClientEvent = FireCustomClientEvent

Enum.EditModeAccountSetting = {
	ShowGrid = 0,
	GridSpacing = 1,
	SettingsExpanded = 2,
	ShowTargetAndFocus = 3,
	ShowStanceBar = 4,
	ShowPetActionBar = 5,
	ShowPossessActionBar = 6,
	ShowCastBar = 7,
	ShowExtraAbilities = 8,
	ShowBuffsAndDebuffs = 9,
	DeprecatedShowDebuffFrame = 10,
	ShowPartyFrames = 11,
	ShowRaidFrames = 12,
	ShowVehicleLeaveButton = 13,
	ShowBossFrames = 14,
	ShowArenaFrames = 15,
	ShowHudTooltip = 16,
	ShowStatusTrackingBar2 = 17,
	ShowDurabilityFrame = 18,
	EnableSnap = 19,
	EnableAdvancedOptions = 20,
	ShowPetFrame = 21,
	ShowTimerBars = 22,
	ShowVehicleSeatIndicator = 23,
}

Enum.EditModeLayoutType = {
	Preset = 0,
	Account = 1,
	Character = 2,
	Override = 3,
}

Enum.EditModePresetLayouts = {
	Modern = 0,
	Classic = 1
}

Enum.EditModeSettingDisplayType = {
	Dropdown = 0,
	Checkbox = 1,
	Slider = 2,
}

Enum.EditModeSystem = {
	ActionBar = 0,
	CastBar = 1,
	Minimap = 2,
	UnitFrame = 3,
	ExtraAbilities = 4,
	AuraFrame = 5,
	ChatFrame = 6,
	VehicleLeaveButton = 7,
	HudTooltip = 8,
	ObjectiveTracker = 9,
	MicroMenu = 10,
	Bags = 11,
	StatusTrackingBar = 12,
	DurabilityFrame = 13,
	TimerBars = 14,
	VehicleSeatIndicator = 15,
}

-- ActionBar
Enum.EditModeActionBarSystemIndices =	{ MainBar = 1, Bar2 = 2, Bar3 = 3, RightBar1 = 4, RightBar2 = 5,
											ExtraBar1 = 6, ExtraBar2 = 7, ExtraBar3 = 8, StanceBar = 11, PetActionBar = 12, PossessActionBar = 13, MultiCastActionBar = 14 }
Enum.EditModeActionBarSetting = 		{ Orientation = 0, NumRows = 1, NumIcons = 2, IconSize = 3, IconPadding = 4, VisibleSetting = 5,
											HideBarArt = 6, DeprecatedSnapToSide = 7, HideBarScrolling = 8, AlwaysShowButtons = 9 }
Enum.ActionBarOrientation =				{ Horizontal = 0, Vertical = 1 }
Enum.ActionBarVisibleSetting =			{ Always = 0, InCombat = 1, OutOfCombat = 2, Hidden = 3 }
-- CastBar
Enum.EditModeCastBarSetting =			{ BarSize = 0, LockToPlayerFrame = 1, ShowCastTime = 2, ReverseCastTime = 3, ShowIcon = 4 }
-- Minimap
Enum.EditModeMinimapSetting =			{ HeaderUnderneath = 0, RotateMinimap = 1, Size = 2, IconScale = 3 }
-- UnitFrame
Enum.EditModeUnitFrameSystemIndices =	{ Player = 1, Target = 2, Focus = 3, Party = 4, Raid = 5, Boss = 6, Arena = 7, Pet = 8 }
Enum.EditModeUnitFrameSetting =			{ HidePortrait = 0, CastBarUnderneath = 1, BuffsOnTop = 2, UseLargerFrame = 3, UseRaidStylePartyFrames = 4, ShowPartyFrameBackground = 5,
											UseHorizontalGroups = 6, CastBarOnSide = 7, ShowCastTime = 8, ViewRaidSize = 9, FrameWidth = 10, FrameHeight = 11,
											DisplayBorder = 12, RaidGroupDisplayType = 13, SortPlayersBy = 14, RowSize = 15, FrameSize = 16, ViewArenaSize = 17,
											AuraOrganizationType = 18, IconSize = 19, Opacity = 20,
    DebuffIconSize = 21,
    BigDefensiveIconSize = 22,
    BuffIconSize = 23, }
Enum.RaidAuraOrganizationType = 		{ Legacy = 0, BuffsTopDebuffsBottom = 1, BuffsRightDebuffsLeft = 2}
-- ExtraAbilities
-- AuraFrame
Enum.EditModeAuraFrameSystemIndices =	{ BuffFrame = 1, DebuffFrame = 2 }
Enum.EditModeAuraFrameSetting =			{ Orientation = 0, IconWrap = 1, IconDirection = 2, IconLimitBuffFrame = 3, IconLimitDebuffFrame = 4,
											IconSize = 5, IconPadding = 6, DeprecatedShowFull = 7, VisibleSetting = 8, Opacity = 9, ShowDispelType = 10, }
Enum.AuraFrameOrientation =				{ Horizontal = 0, Vertical = 1 }
Enum.AuraFrameIconWrap =				{ Down = 0, Up = 1, Left = 0, Right = 1 }
Enum.AuraFrameIconDirection =			{ Down = 0, Up = 1, Left = 0, Right = 1 }
Enum.AuraFrameVisibleSetting =			{ Always = 0, InCombat = 1, Hidden = 2 }
-- ChatFrame
Enum.EditModeChatFrameSetting =			{ WidthHundreds = 0, WidthTensAndOnes = 1, HeightHundreds = 2, HeightTensAndOnes = 3 }
-- VehicleLeaveButton
-- HudTooltip
-- ObjectiveTracker
Enum.EditModeObjectiveTrackerSetting =	{ Height = 0, Opacity = 1, TextSize = 2, HeaderAlpha = 3, HeaderStyle = 4 }
-- MicroMenu
Enum.EditModeMicroMenuSetting =			{ Orientation = 0, Order = 1, Size = 2, EyeSize = 3 }
Enum.MicroMenuOrientation =				{ Horizontal = 0, Vertical = 1 }
Enum.MicroMenuOrder =					{ Default = 0, Reverse = 1 }
-- Bags
Enum.EditModeBagsSetting =				{ Orientation = 0, Direction = 1, Size = 2, BagSlotPadding = 3, CombinedBags = 4, CombinedBank = 5 }
Enum.BagsDirection =					{ Left = 0, Right = 1, Up = 0, Down = 1 }
Enum.BagsOrientation =					{ Horizontal = 0, Vertical = 1 }
-- StatusTrackingBar
Enum.EditModeStatusTrackingBarSystemIndices = { StatusTrackingBar1 = 1, StatusTrackingBar2 = 2 }
Enum.EditModeStatusTrackingBarSetting =	{ Height = 0, Width = 1, TextSize = 2, Size = 3 }
-- DurabilityFrame
Enum.EditModeDurabilityFrameSetting =	{ Size = 0 }
-- TimerBars
Enum.EditModeTimerBarsSetting =			{ Size = 0 }
-- VehicleSeatIndicator
Enum.EditModeVehicleSeatIndicatorSetting = { Size = 0 }
Enum.EditModeSystem.EncounterBar = { Size = 0 }
Enum.EditModeSystem.LootFrame = { Size = 0 }
Enum.EditModeSystem.TalkingHeadFrame = { Size = 0 }

Enum.EditModeAuraFrameSystemIndices.ExternalDefensivesFrame = {
	Orientation = 0,
	IconWrap = 1,
	IconDirection = 2,
	IconLimitBuffFrame = 3,
	IconSize = 4,
	IconPadding = 5,
	VisibleSetting = 6,
	Opacity = 7
}

Enum.RaidGroupDisplayType = {
	SeparateGroupsVertical = 0,
	SeparateGroupsHorizontal = 1,
	CombineGroupsVertical = 2,
	CombineGroupsHorizontal = 3,
}
Enum.SortPlayersBy = {
	Role = 0,
	Group = 1,
	Alphabetical = 2,
}
Enum.ViewArenaSize = {
	Two = 0,
	Three = 1,
	Five = 2,
}
Enum.ViewRaidSize = {
	Ten = 0,
	TwentyFive = 1,
	Forty = 2,
}

Constants.EditModeConsts = {
	EditModeDefaultGridSpacing = 100,
	EditModeMinGridSpacing = 20,
	EditModeMaxGridSpacing = 300,
	EditModeMaxLayoutsPerType = 5,
}

Constants.EditModeLayoutConsts = {
	EditModeDefaultLayout = Enum.EditModePresetLayouts.Classic,
}

RegisterForSave("EDIT_MODE")
RegisterForSave("EDIT_MODE_ACCOUNT_SETTINGS")
RegisterForSavePerCharacter("EDIT_MODE_CHARACTER")

EDIT_MODE = {}
EDIT_MODE_CHARACTER = {}
EDIT_MODE_ACCOUNT_SETTINGS = {
	[Enum.EditModeAccountSetting.SettingsExpanded] = 1,
	[Enum.EditModeAccountSetting.GridSpacing] = 80,
}

local POINT_MAP = {
	["TOPLEFT"] = 0,
	["TOP"] = 1,
	["TOPRIGHT"] = 2,
	["LEFT"] = 3,
	["CENTER"] = 4,
	["RIGHT"] = 5,
	["BOTTOMLEFT"] = 6,
	["BOTTOM"] = 7,
	["BOTTOMRIGHT"] = 8,
	[0] = "TOPLEFT",
	[1] = "TOP",
	[2] = "TOPRIGHT",
	[3] = "LEFT",
	[4] = "CENTER",
	[5] = "RIGHT",
	[6] = "BOTTOMLEFT",
	[7] = "BOTTOM",
	[8] = "BOTTOMRIGHT",
}

local ENCODE_CHAR_MAP = {}
local DECODE_REV_MAP = {}

local PRIVATE = PrivateNamespace.CreateNamespace("C_EditMode", {
	DEFAULT_LAYOUT_INDEX = 2,
})

PRIVATE.EventHandler = CreateFrame("Frame")
PRIVATE.EventHandler:RegisterEvent("VARIABLES_LOADED")
PRIVATE.EventHandler:SetScript("OnEvent", function(self, event, ...)
	if EDIT_MODE.layouts then
		local copy = CopyTable(EDIT_MODE.layouts)
		twipe(EDIT_MODE)
		EDIT_MODE = copy
	end
	if EDIT_MODE_CHARACTER.layouts then
		local copy = CopyTable(EDIT_MODE_CHARACTER.layouts)
		twipe(EDIT_MODE_CHARACTER)
		EDIT_MODE_CHARACTER = copy
	end

	FireCustomClientEvent("EDIT_MODE_LAYOUTS_UPDATED", PRIVATE.GetLayouts(), true)
end)

PRIVATE.Initialize = function()
	for i = 0, 89 do
		local char = strchar(35 + i)
		ENCODE_CHAR_MAP[i] = char
		DECODE_REV_MAP[char] = i
	end
end

PRIVATE.EncodeValue = function(value)
	if value < 0 then
		return "?"
	elseif value < 88 then
		return ENCODE_CHAR_MAP[value]
	else
		local b = mathfloor(value / 90)
		local a = value % 90
		return strconcat(ENCODE_CHAR_MAP[a], "(", ENCODE_CHAR_MAP[b])
	end
end

PRIVATE.DecodeValue = function(encoded, startPos, isValue)
	if startPos > #encoded then
		return nil, startPos
	end

	local char1 = encoded:sub(startPos, startPos)
	local val1 = DECODE_REV_MAP[char1]

	if val1 == nil then
		return 0, startPos + 1
	end

	if isValue and char1 ~= "(" and startPos + 2 <= #encoded then
		local char2 = encoded:sub(startPos + 1, startPos + 1)
		local char3 = encoded:sub(startPos + 2, startPos + 2)

		if char2 == "(" and DECODE_REV_MAP[char3] and char3 ~= "(" then
			local A = val1
			local B = DECODE_REV_MAP[char3]
			return B * 90 + A, startPos + 3
		end
	end

	return val1, startPos + 1
end

PRIVATE.ConvertSettingsToString = function(settings)
	if not settings or #settings == 0 then
		return "#"
	end
	local encoded = ""
	for _, setting in ipairs(settings) do
		encoded = strconcat(encoded, ENCODE_CHAR_MAP[setting.setting], PRIVATE.EncodeValue(setting.value))
	end
	return encoded
end

PRIVATE.ConvertStringToSettings = function(settingsString)
	if settingsString == "#" then
		return {}
	end
	local settings = {}
	local pos = 1
	while pos <= #settingsString do
		local setting = DECODE_REV_MAP[settingsString:sub(pos, pos)]
		pos = pos + 1
		local value, newPos = PRIVATE.DecodeValue(settingsString, pos, true)
		pos = newPos
		tinsert(settings, {
			setting = tonumber(setting),
			value = tonumber(value)
		})
	end
	return settings
end

PRIVATE.ConvertLayoutInfoToString = function(layoutData)
	local layoutType = 2
	local systems = layoutData.systems or {}

	local parts = {strformat("%d %d", layoutType, #systems)}

	for i, system in ipairs(systems) do
		local sysType = system.system or 0
		local sysIndex = (system.systemIndex or 0) - 1

		local anchor = system.anchorInfo
		local pointCode = POINT_MAP[anchor.point]
		local relativePointCode = POINT_MAP[anchor.relativePoint]
		local relativeTo = anchor.relativeTo
		local offsetX = anchor.offsetX or 0
		local offsetY = anchor.offsetY or 0
		local defaultPos = system.isInDefaultPosition and -1 or 0
		local settingsStr = PRIVATE.ConvertSettingsToString(system.settings)

		tinsert(parts, strformat("%d %d %d %d %d %s %.1f %.1f %d %s", sysType, sysIndex, 1, pointCode, relativePointCode, relativeTo, offsetX, offsetY, defaultPos, settingsStr))
	end

	return tconcat(parts, " ")
end

PRIVATE.ConvertStringToLayoutInfo = function(layoutInfoAsString)
	local parts = {}
	for part in layoutInfoAsString:gmatch("%S+") do
		tinsert(parts, part)
	end

	if #parts < 2 then
		return nil
	end

	local layoutType = tonumber(parts[1])
	local systemsCount = tonumber(parts[2])

	local layoutData = {
		layoutType = layoutType,
		systems = {}
	}

	local currentIndex = 3
	for i = 1, systemsCount do
		if currentIndex + 9 > #parts then
			break
		end

		local system = {}
		system.system = tonumber(parts[currentIndex])
		local systemIndex = tonumber(parts[currentIndex + 1])
		if systemIndex >= 0 then
			system.systemIndex = systemIndex + 1
		end
		currentIndex = currentIndex + 2

		local alwaysOne = tonumber(parts[currentIndex])
		currentIndex = currentIndex + 1

		local pointCode = tonumber(parts[currentIndex])
		local relativePointCode = tonumber(parts[currentIndex + 1])
		currentIndex = currentIndex + 2

		system.anchorInfo = {
			relativeTo = parts[currentIndex],
			point = POINT_MAP[pointCode],
			relativePoint = POINT_MAP[relativePointCode],
			offsetX = tonumber(parts[currentIndex + 1]),
			offsetY = tonumber(parts[currentIndex + 2])
		}
		currentIndex = currentIndex + 3

		local defaultPos = tonumber(parts[currentIndex])
		system.isInDefaultPosition = (defaultPos == -1)
		currentIndex = currentIndex + 1

		local settingsString = parts[currentIndex]
		system.settings = PRIVATE.ConvertStringToSettings(settingsString)
		currentIndex = currentIndex + 1

		tinsert(layoutData.systems, system)
	end

	return layoutData
end

PRIVATE.GetLayouts = function()
	local layoutInfo = {
		layouts = {}
	}

	local numLayouts = 2
	for index, layout in ipairs(EDIT_MODE) do
		numLayouts = numLayouts + 1
		tinsert(layoutInfo.layouts, CopyTable(layout))
	end
	for index, layout in ipairs(EDIT_MODE_CHARACTER) do
		numLayouts = numLayouts + 1
		tinsert(layoutInfo.layouts, CopyTable(layout))
	end
	local activeLayout = PRIVATE.GetActiveLayout()
	if activeLayout > numLayouts then
		activeLayout = PRIVATE.SetActiveLayout(PRIVATE.DEFAULT_LAYOUT_INDEX)
	end

	layoutInfo.activeLayout = activeLayout

	return layoutInfo
end

PRIVATE.SetActiveLayout = function(activeLayoutIndex)
	if type(activeLayoutIndex) ~= "number" then
		activeLayoutIndex = PRIVATE.DEFAULT_LAYOUT_INDEX
	end

	SetCVar("editModeActiveLayout", activeLayoutIndex)

	return activeLayoutIndex
end

PRIVATE.GetActiveLayout = function()
	return tonumber(GetCVar("editModeActiveLayout")) or PRIVATE.DEFAULT_LAYOUT_INDEX
end

PRIVATE.Initialize()

C_EditMode = {}

function C_EditMode.ConvertLayoutInfoToString(layoutInfo)
	local layoutInfoAsString = PRIVATE.ConvertLayoutInfoToString(layoutInfo)
	return layoutInfoAsString
end

function C_EditMode.ConvertStringToLayoutInfo(layoutInfoAsString)
	local layoutInfo = PRIVATE.ConvertStringToLayoutInfo(layoutInfoAsString)
	return layoutInfo
end

function C_EditMode.GetAccountSettings()
	local accountSettings = {}

	for i = Enum.EditModeAccountSetting.ShowGrid, Enum.EditModeAccountSetting.ShowVehicleSeatIndicator do
		local value = EDIT_MODE_ACCOUNT_SETTINGS[i]
		accountSettings[#accountSettings + 1] = {
			value = value or 0,
			setting = i,
		}
	end

	return accountSettings
end

function C_EditMode.GetLayouts()
	return PRIVATE.GetLayouts()
end

function C_EditMode.IsValidLayoutName(name)
	local isApproved = true
	return isApproved
end

function C_EditMode.OnEditModeExit()
end

function C_EditMode.OnLayoutAdded(addedLayoutIndex, activateNewLayout, isLayoutImported)
	if activateNewLayout then
		PRIVATE.SetActiveLayout(addedLayoutIndex)
	end

	FireCustomClientEvent("EDIT_MODE_LAYOUTS_UPDATED", PRIVATE.GetLayouts(), false)
end

function C_EditMode.OnLayoutDeleted(deletedLayoutIndex)
	PRIVATE.SetActiveLayout(PRIVATE.DEFAULT_LAYOUT_INDEX)

	FireCustomClientEvent("EDIT_MODE_LAYOUTS_UPDATED", PRIVATE.GetLayouts(), false)
end

function C_EditMode.SaveLayouts(saveInfo)
	twipe(EDIT_MODE)
	twipe(EDIT_MODE_CHARACTER)

	if saveInfo.layouts then
		for _, layout in ipairs(saveInfo.layouts) do
			if layout.layoutType ~= Enum.EditModeLayoutType.Preset then
				if layout.systems then
					for _, system in ipairs(layout.systems) do
						if system.settings then
							for _, setting in ipairs(system.settings) do
								if setting.value < 0 or setting.value > 8099 then
									setting.value = 1
								end
							end
						end
					end
				end

				if layout.layoutType == Enum.EditModeLayoutType.Character then
					tinsert(EDIT_MODE_CHARACTER, CopyTable(layout))
				else
					tinsert(EDIT_MODE, CopyTable(layout))
				end
			end
		end
	end
end

function C_EditMode.SetAccountSetting(setting, value)
	EDIT_MODE_ACCOUNT_SETTINGS[setting] = value
end

function C_EditMode.SetActiveLayout(activeLayoutIndex)
	PRIVATE.SetActiveLayout(activeLayoutIndex)

	FireCustomClientEvent("EDIT_MODE_LAYOUTS_UPDATED", PRIVATE.GetLayouts(), false)
end

Enum.GameMenuEscPriority = {
	-- Static popups
	Dialog = 1,

	-- Context menus, spell flyouts, popup lists
	Menu = 2,

	--[[
	Consumes ESC for active spell interactions before normal
	UI teardown begins. These occur prior to addons because
	the casting may be in support of the addon, such as
	casting a spell to create a profession item.
	]]--
	
	Casting = 4,

	--[[
	Framework-owned overlays or top-level mode handlers that
	must run before normal panel teardown, such as
	OpacityFrame, HelpFrame, and HouseEditor.
	]]--
	FrameworkPre = 5,

	--[[
	For foundational UI such as edit mode that would
	be expected to be closed before an addon behind it.
	]]--
	Framework = 6,

	-- Use only when a framework handler must run immediately after another framework handler.
	FrameworkPost = 7,

	--[[
	For addons whose handler order is generally unimportant.
	Do not rely on ordering within this bucket.
	Note, this should be replaced in the future with an approach
	that attempts to close these UIs in an order related to their
	display level.
	]]--
	AddOn = 8,

	--[[
	For generic post-addon cleanup that should occur after all
	addon handlers have had a chance to run.
	]]--
	AddOnPost = 9,

	--[[
	Reserved for ordered follow-up after AddOnPost cleanup,
	such as CloseAllWindows and LootFrame.
	]]--
	AddOnPost2 = 10,

	-- Final gameplay fallback after no UI handler claimed ESC.
	World = 11,
};