-- The retail settings of the core's frames (EditModeSettingDisplayInfo.lua) and the frames the stock code places
-- itself (UIParent_ManageFramePositions: durability, vehicle seats; the loot frame), in Edit Mode.
--   Bags (BackpackFrame):          orientation, direction        -> BagsBarRetail_Layout
--   Micro menu (MicroMenuFrame):   orientation, order            -> its buttons laid out after MicroMenu_PlaceBottomRight
--   Cast bar (CastingBarFrame):    lock to the player frame      -> PlayerFrame_AttachCastBar / DetachCastBar
--   Minimap (MinimapCluster):      rotate minimap                -> CVar rotateMinimap
--   Chat (ChatFrame1):             width, height
--   Objective tracker:             height
--   Loot frame:                    not editable while the loot opens at the cursor
-- Loaded by EditModeCore.xml after EditModeCore.lua.

local function Label(text, fallback)
	return text or fallback;
end

local function Percent(value)
	return string.format("%d%%", math.floor(value * 100 + 0.5));
end

local function Store(key, after)
	return function(frame, value)
		frame.editModeSettings = frame.editModeSettings or {};
		frame.editModeSettings[key] = value;
		if after then
			after(frame);
		end
	end
end

---------------------------------------------------------------------------
-- the micro menu: one row or one column, in the order or the other way round
---------------------------------------------------------------------------
local MICRO_ORDER = {
	"CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
	"AchievementMicroButton", "QuestLogMicroButton", "SocialsMicroButton",
	"PVPMicroButton", "LFDMicroButton", "CollectionsMicroButton", "EJMicroButton",
	"MainMenuMicroButton",
};
local MICRO_SPACING = -3;

local function LayoutMicroMenu()
	local frame = MicroMenuFrame;
	local settings = frame and frame.editModeSettings;
	-- the stock one-row layout (MainMenuBarMicroButtons.lua) as long as nothing else was ever chosen; once the buttons
	-- were laid out here they stay laid out here (the stock anchors are gone), the default as one row
	local custom = settings and ((settings.orientation or 0) ~= 0 or (settings.order or 0) ~= 0);
	if not custom and not frame.microLaidOut then
		return;
	end
	frame.microLaidOut = true;
	if InCombatLockdown() then
		return;
	end
	local buttons = {};
	for _, name in ipairs(MICRO_ORDER) do
		local button = _G[name];
		if button and button:IsShown() then
			table.insert(buttons, button);
		end
	end
	if settings.order == 1 then
		local reversed = {};
		for i = #buttons, 1, -1 do
			table.insert(reversed, buttons[i]);
		end
		buttons = reversed;
	end

	local vertical = settings.orientation == 1;
	local offset, thick = 0, 0;
	for _, button in ipairs(buttons) do
		button:ClearAllPoints();
		if vertical then
			button:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -offset);
			offset = offset + button:GetHeight() + MICRO_SPACING;
			thick = math.max(thick, button:GetWidth());
		else
			button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", offset, 0);
			offset = offset + button:GetWidth() + MICRO_SPACING;
			thick = math.max(thick, button:GetHeight());
		end
	end
	offset = offset - MICRO_SPACING;
	if vertical then
		frame:SetWidth(thick);
		frame:SetHeight(offset);
	else
		frame:SetWidth(offset);
		frame:SetHeight(thick);
	end
end

if MicroMenu_PlaceBottomRight then
	hooksecurefunc("MicroMenu_PlaceBottomRight", LayoutMicroMenu);
end

---------------------------------------------------------------------------
-- registration
---------------------------------------------------------------------------
local loader = CreateFrame("Frame");
loader:RegisterEvent("PLAYER_LOGIN");
loader:SetScript("OnEvent", function()
	-- bags: retail Enum.EditModeBagsSetting Orientation / Direction
	if BagsBarRetail_Layout then
		EditModeCore:AddSettings("BackpackFrame", {
			{
				key = "orientation", type = "dropdown", default = 0,
				label = Label(HUD_EDIT_MODE_SETTING_BAGS_ORIENTATION, "Расположение"),
				options = {
					{ 0, Label(HUD_EDIT_MODE_SETTING_BAGS_ORIENTATION_HORIZONTAL, "Горизонтально") },
					{ 1, Label(HUD_EDIT_MODE_SETTING_BAGS_ORIENTATION_VERTICAL, "Вертикально") },
				},
				apply = Store("orientation", BagsBarRetail_Layout),
			},
			{
				key = "direction", type = "dropdown", default = 0,
				label = Label(HUD_EDIT_MODE_SETTING_BAGS_DIRECTION, "Направление"),
				options = {
					{ 0, Label(HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_LEFT, "Влево") .. " / " .. Label(HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_UP, "Вверх") },
					{ 1, Label(HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_RIGHT, "Вправо") .. " / " .. Label(HUD_EDIT_MODE_SETTING_BAGS_DIRECTION_DOWN, "Вниз") },
				},
				apply = Store("direction", BagsBarRetail_Layout),
			},
		});
	end

	-- micro menu: retail Enum.EditModeMicroMenuSetting Orientation / Order
	EditModeCore:AddSettings("MicroMenuFrame", {
		{
			key = "orientation", type = "dropdown", default = 0,
			label = Label(HUD_EDIT_MODE_SETTING_MICRO_MENU_ORIENTATION, "Расположение"),
			options = {
				{ 0, Label(HUD_EDIT_MODE_SETTING_MICRO_MENU_ORIENTATION_HORIZONTAL, "Горизонтально") },
				{ 1, Label(HUD_EDIT_MODE_SETTING_MICRO_MENU_ORIENTATION_VERTICAL, "Вертикально") },
			},
			apply = Store("orientation", function()
				if MicroMenu_PlaceBottomRight then
					MicroMenu_PlaceBottomRight();
				end
			end),
		},
		{
			key = "order", type = "dropdown", default = 0,
			label = Label(HUD_EDIT_MODE_SETTING_MICRO_MENU_ORDER, "Порядок"),
			options = {
				{ 0, Label(HUD_EDIT_MODE_SETTING_MICRO_MENU_ORDER_DEFAULT, "По умолчанию") },
				{ 1, Label(HUD_EDIT_MODE_SETTING_MICRO_MENU_ORDER_REVERSE, "Перевернуть") },
			},
			apply = Store("order", function()
				if MicroMenu_PlaceBottomRight then
					MicroMenu_PlaceBottomRight();
				end
			end),
		},
	});

	-- cast bar: retail "Lock to player frame" (the 3.3.5 player frame menu option of the same thing)
	if PlayerFrame_AttachCastBar and PlayerFrame_DetachCastBar then
		EditModeCore:AddSettings("CastingBarFrame", {
			{
				key = "lockToPlayerFrame", type = "check", default = PLAYER_FRAME_CASTBARS_SHOWN and 1 or 0,
				label = Label(HUD_EDIT_MODE_SETTING_CAST_BAR_LOCK_TO_PLAYER_FRAME, "Прикрепить к рамке игрока"),
				apply = function(frame, value)
					local attached = PLAYER_FRAME_CASTBARS_SHOWN and 1 or 0;
					if value == attached then
						return;
					end
					PLAYER_FRAME_CASTBARS_SHOWN = value == 1;
					if value == 1 then
						PlayerFrame_AttachCastBar();
					else
						PlayerFrame_DetachCastBar();
					end
				end,
			},
		});
	end

	-- minimap: retail "Rotate minimap"
	EditModeCore:AddSettings("MinimapCluster", {
		{
			key = "rotateMinimap", type = "check", default = tonumber(GetCVar("rotateMinimap")) or 0,
			label = Label(HUD_EDIT_MODE_SETTING_MINIMAP_ROTATE_MINIMAP, "Поворот мини-карты"),
			apply = function(frame, value)
				if (tonumber(GetCVar("rotateMinimap")) or 0) ~= value then
					SetCVar("rotateMinimap", value);
					if Minimap_UpdateRotationSetting then
						Minimap_UpdateRotationSetting();
					end
				end
			end,
		},
	});

	-- objective tracker: retail height
	if ObjectiveTrackerFrame then
		EditModeCore:AddSettings("ObjectiveTrackerFrame", {
			{
				key = "height", type = "slider", min = 200, max = 1000, step = 10,
				default = math.floor(ObjectiveTrackerFrame:GetHeight() + 0.5),
				label = Label(HUD_EDIT_MODE_SETTING_OBJECTIVE_TRACKER_HEIGHT, "Высота"),
				apply = function(frame, value) frame:SetHeight(value); end,
			},
		});
	end

	-- chat: retail width / height
	EditModeCore:AddSettings("ChatFrame1", {
		{
			key = "width", type = "slider", min = 200, max = 800, step = 10, default = math.floor(ChatFrame1:GetWidth() + 0.5),
			label = Label(HUD_EDIT_MODE_SETTING_CHAT_FRAME_WIDTH, "Ширина"),
			apply = function(frame, value) frame:SetWidth(value); end,
		},
		{
			key = "height", type = "slider", min = 100, max = 500, step = 10, default = math.floor(ChatFrame1:GetHeight() + 0.5),
			label = Label(HUD_EDIT_MODE_SETTING_CHAT_FRAME_HEIGHT, "Высота"),
			apply = function(frame, value) frame:SetHeight(value); end,
		},
	});

	-- the frames the stock code places: the layout's place kept (keepPosition)
	if DurabilityFrame then
		EditModeCore:RegisterSystem("DurabilityFrame", DurabilityFrame, Label(HUD_EDIT_MODE_DURABILITY_FRAME_LABEL, "Прочность снаряжения"),
			nil, { category = "misc", keepPosition = true });
	end
	if VehicleSeatIndicator then
		EditModeCore:RegisterSystem("VehicleSeatIndicator", VehicleSeatIndicator, Label(HUD_EDIT_MODE_VEHICLE_SEAT_INDICATOR_LABEL, "Места"),
			nil, { category = "misc", keepPosition = true });
	end
	if LootFrame then
		-- retail: not editable while the loot opens at the cursor (CVar lootUnderMouse)
		EditModeCore:RegisterSystem("LootFrame", LootFrame, Label(HUD_EDIT_MODE_LOOT_FRAME_LABEL, "Окно добычи"),
			nil, { category = "misc", keepPosition = true, disabledReason = function()
				if GetCVar("lootUnderMouse") == "1" then
					return "Отключите \"Открывать окно добычи под курсором\" (Интерфейс > Управление), чтобы изменить положение окна добычи.";
				end
			end });
	end

	LayoutMicroMenu();
end);
