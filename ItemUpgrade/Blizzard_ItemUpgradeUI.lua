-- Item upgrade (retail Blizzard_ItemUpgradeUI: ItemUpgradeMixin / ItemUpgradePreviewMixin / ItemUpgradeSlotMixin) for 3.3.5.
-- C_ItemUpgrade does not exist: the data comes from the server (server/item_upgrade.cpp) through AddonComm:
--   "IUPG_OPEN" / "IUPG_CLOSE"          window at the upgrade NPC
--   "IUPG_LIST" -> "IUPG_ITEMS" : "bag/slot/itemId/track/level/max,..." : "trackId/name,..."
--   "IUPG_SET" : bag : slot / "IUPG_CLEAR" -> "IUPG_INFO" : bag : slot : itemId : curr : max : track : minIlvl : maxIlvl
--                                               : costItem : costCount : costMoney : levels : error
--   "IUPG_UPGRADE" : levels -> "IUPG_RESULT" : ok : error
-- Client slots: bag 255 - equipment slot id, 0 - backpack, 1..4 - bags.

ITEM_UPGRADE = ITEM_UPGRADE or "Улучшение предметов";
ITEM_UPGRADE_DESCRIPTION = ITEM_UPGRADE_DESCRIPTION or "Поместите предмет в ячейку, чтобы улучшить его.";
UPGRADE_MISSING_ITEM = UPGRADE_MISSING_ITEM or "Предмет не выбран";
UPGRADE = UPGRADE or "Улучшить";
ITEM_UPGRADE_FRAME_UPGRADE_TO = ITEM_UPGRADE_FRAME_UPGRADE_TO or "Улучшить до:";
ITEM_UPGRADE_COST_LABEL = ITEM_UPGRADE_COST_LABEL or "Стоимость:";
ITEM_UPGRADE_CURRENT = ITEM_UPGRADE_CURRENT or "Текущий";
ITEM_UPGRADE_NEXT_UPGRADE = ITEM_UPGRADE_NEXT_UPGRADE or "Следующее улучшение";
ITEM_UPGRADE_NO_MORE_UPGRADES = ITEM_UPGRADE_NO_MORE_UPGRADES or "Этот предмет полностью улучшен.";
ITEM_UPGRADE_NO_TRACK = ITEM_UPGRADE_NO_TRACK or "Этот предмет нельзя улучшить.";
ITEM_UPGRADE_NOT_OWNED = ITEM_UPGRADE_NOT_OWNED or "Этот предмет вам не принадлежит.";
ERR_ITEM_UPGRADE_NEED_NPC = ERR_ITEM_UPGRADE_NEED_NPC or "Подойдите к мастеру улучшения.";
ITEM_UPGRADE_ERROR_NOT_ENOUGH_CURRENCY = ITEM_UPGRADE_ERROR_NOT_ENOUGH_CURRENCY or "Недостаточно: %s.";
ITEM_UPGRADE_ERROR_NOT_ENOUGH_CURRENCY_SHORT = ITEM_UPGRADE_ERROR_NOT_ENOUGH_CURRENCY_SHORT or "Недостаточно валюты для улучшения.";
ITEM_UPGRADE_ITEM_LEVEL_STAT_FORMAT = ITEM_UPGRADE_ITEM_LEVEL_STAT_FORMAT or "Уровень предмета %d";
ITEM_UPGRADE_ITEM_LEVEL_BONUS_STAT_FORMAT = ITEM_UPGRADE_ITEM_LEVEL_BONUS_STAT_FORMAT or "Уровень предмета %d |cff00ff00(+%d)|r";
ITEM_UPGRADE_FRAME_CURRENT_UPGRADE_FORMAT_STRING = ITEM_UPGRADE_FRAME_CURRENT_UPGRADE_FORMAT_STRING or "Улучшение: %s %d/%d";
ITEM_UPGRADE_PROGRESS_LEVEL_FORMAT_STRING = ITEM_UPGRADE_PROGRESS_LEVEL_FORMAT_STRING or "%s %d/%d (уровень предмета %d, %d-%d)";
ITEM_UPGRADE_DROPDOWN_LEVEL_FORMAT_STRING = ITEM_UPGRADE_DROPDOWN_LEVEL_FORMAT_STRING or "%s %d/%d";
ITEM_UPGRADE_TOOLTIP_FORMAT_STRING = ITEM_UPGRADE_TOOLTIP_FORMAT_STRING or "Уровень улучшения: %s %d/%d";
ITEM_UPGRADE_CONFIRM = ITEM_UPGRADE_CONFIRM or "Улучшить %s до %s %d/%d?\nСтоимость: %s";

UIPanelWindows["ItemUpgradeFrame"] = { area = "left", pushable = 0, whileDead = 1, xOffset = "15", yOffset = "-10" };

ItemUpgradeUI = { items = {}, trackNames = {} };
local items, trackNames = ItemUpgradeUI.items, ItemUpgradeUI.trackNames;   -- [bag][slot] = { itemId, track, level, max }

local function Send(...)
	if Comm_Send then
		Comm_Send(...);
	end
end

---------------------------------------------------------------------------
-- stats of a level: ITEM_MOD_* strings of the client (3.3.5 stat type ids)
---------------------------------------------------------------------------
local STAT_GLOBALS = {
	[0] = "MANA", [1] = "HEALTH", [3] = "AGILITY", [4] = "STRENGTH", [5] = "INTELLECT", [6] = "SPIRIT", [7] = "STAMINA",
	[12] = "DEFENSE_SKILL_RATING", [13] = "DODGE_RATING", [14] = "PARRY_RATING", [15] = "BLOCK_RATING",
	[16] = "HIT_MELEE_RATING", [17] = "HIT_RANGED_RATING", [18] = "HIT_SPELL_RATING",
	[19] = "CRIT_MELEE_RATING", [20] = "CRIT_RANGED_RATING", [21] = "CRIT_SPELL_RATING",
	[28] = "HASTE_MELEE_RATING", [29] = "HASTE_RANGED_RATING", [30] = "HASTE_SPELL_RATING",
	[31] = "HIT_RATING", [32] = "CRIT_RATING", [35] = "RESILIENCE_RATING", [36] = "HASTE_RATING", [37] = "EXPERTISE_RATING",
	[38] = "ATTACK_POWER", [39] = "RANGED_ATTACK_POWER", [43] = "MANA_REGENERATION", [44] = "ARMOR_PENETRATION_RATING",
	[45] = "SPELL_POWER", [46] = "HEALTH_REGEN", [47] = "SPELL_PENETRATION", [48] = "BLOCK_VALUE", [49] = "MASTERY_RATING",
};

local function FormatStat(statType, value)
	local key = STAT_GLOBALS[statType];
	local fmt = key and _G["ITEM_MOD_" .. key];
	if not fmt then
		return ("%+d (%d)"):format(value, statType);
	end
	if fmt:find("%%c") then
		return fmt:format(value >= 0 and 43 or 45, math.abs(value));   -- '+' / '-'
	end
	return fmt:format(value);
end

-- "level;itemLevel;type=v,...;armor;min-max;delay"
local function ParseLevel(text)
	local level, itemLevel, stats, armor, damage, delay = strsplit(";", text);
	local info = { upgradeLevel = tonumber(level) or 0, itemLevel = tonumber(itemLevel) or 0, stats = {}, armor = tonumber(armor) or 0, delay = tonumber(delay) or 0 };
	for statType, value in (stats or ""):gmatch("(%d+)=(%-?%d+)") do
		table.insert(info.stats, { type = tonumber(statType), value = tonumber(value) });
	end
	local minDamage, maxDamage = (damage or ""):match("(%d+)%-(%d+)");
	info.minDamage, info.maxDamage = tonumber(minDamage) or 0, tonumber(maxDamage) or 0;
	return info;
end

---------------------------------------------------------------------------
-- frame
---------------------------------------------------------------------------
function ItemUpgradeFrame_Show()
	ShowUIPanel(ItemUpgradeFrame);
end

function ItemUpgradeFrame_Hide()
	HideUIPanel(ItemUpgradeFrame);
end

function ItemUpgradeFrame_OnLoad(self)
	self:RegisterForDrag("LeftButton");
	if self.TitleContainer and self.TitleContainer.TitleText then
		self.TitleContainer.TitleText:SetText(ITEM_UPGRADE);
	end
	if self.PortraitContainer and self.PortraitContainer.portrait then
		local portrait = self.PortraitContainer.portrait;
		SetPortraitToTexture(portrait, "Interface\\Icons\\Trade_BlackSmithing");
	end
	if self.CloseButton then
		self.CloseButton:SetFrameLevel(self:GetFrameLevel() + 20);
	end
	ItemUpgradeFrame_SetupDropdown(self);
	self.Ring:SetPoint("CENTER", self.UpgradeButton, "CENTER", 0, 0);
	self.anim = { arrow = 0, glow = 0 };
end

function ItemUpgradeFrame_OnShow(self)
	PlaySound("igCharacterInfoOpen");
	self:RegisterEvent("BAG_UPDATE");
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED");
	self.info = nil;
	ItemUpgradeFrame_Update(self);
	Send("IUPG_LIST");
end

function ItemUpgradeFrame_OnHide(self)
	PlaySound("igCharacterInfoClose");
	self:UnregisterAllEvents();
	StaticPopup_Hide("CONFIRM_UPGRADE_ITEM");
	Send("IUPG_CLEAR");
	self.info, self.location = nil, nil;
end

function ItemUpgradeFrame_OnEvent(self, event)
	-- items moved or were equipped: ask again for the selected slot
	self.refreshDelay = 0.3;
end

-- retail animations: arrow slide, empty slot / button glow bounce, upgrade flash (3.3.5 AnimationGroup cannot do alpha from-to)
function ItemUpgradeFrame_OnUpdate(self, elapsed)
	if self.refreshDelay then
		self.refreshDelay = self.refreshDelay - elapsed;
		if self.refreshDelay <= 0 then
			self.refreshDelay = nil;
			Send("IUPG_LIST");
			if self.location then
				Send("IUPG_SET", self.location[1], self.location[2]);
			end
		end
	end

	local anim = self.anim;
	anim.glow = anim.glow + elapsed;
	local bounce = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(anim.glow * math.pi));   -- 0.4..1 over 2 s (looping BOUNCE)
	self.UpgradeItemButton.EmptySlotGlow:SetAlpha(bounce);
	self.UpgradeButton.Glow:SetAlpha(bounce);

	if self.Arrow:IsShown() then
		anim.arrow = (anim.arrow + elapsed) % 1.25;
		local t = math.min(anim.arrow, 1);
		local alpha = t < 0.5 and t * 2 or math.max(0, 1 - (t - 0.5) * 2);
		self.Arrow.arrow:SetAlpha(alpha);
		self.Arrow.arrow:SetPoint("CENTER", self.Arrow, "CENTER", 25 * t, 0);
	end

	if anim.flash then
		anim.flash = anim.flash + elapsed;
		local f = anim.flash;
		self.BottomPanel_Flash:SetAlpha(f < 0.15 and f / 0.15 * 0.75 or math.max(0, 0.75 - (f - 0.15) / 0.15));
		local ringScale = math.min(3, f / 0.75 * 3);
		self.Ring:SetAlpha(f < 0.5 and math.min(1, f / 0.15) or 0);
		self.Ring:SetWidth(self.ringWidth * math.max(0.01, ringScale));
		self.Ring:SetHeight(self.ringHeight * math.max(0.01, ringScale));
		local glow = f < 0.15 and f / 0.15 or (f < 1.08 and 1 or math.max(0, 1 - (f - 1.08) / 0.25));
		self.LeftItemPreviewFrame.Fog:SetAlpha(glow);
		self.LeftItemPreviewFrame.GoldFlake:SetAlpha(glow);
		if f > 2 then
			anim.flash = nil;
			self.Ring:SetAlpha(0);
			self.BottomPanel_Flash:SetAlpha(0);
		end
	end
end

local function PlayUpgradedCelebration(self)
	if not self.ringWidth then
		self.ringWidth, self.ringHeight = self.Ring:GetWidth(), self.Ring:GetHeight();
	end
	self.anim.flash = 0;
	PlaySound("LevelUp");
end

---------------------------------------------------------------------------
-- preview tooltips (retail ItemUpgradePreviewMixin:GeneratePreviewTooltip)
---------------------------------------------------------------------------
local function QualityColor(itemId)
	local _, _, quality = GetItemInfo(itemId);
	local color = ITEM_QUALITY_COLORS[quality or 1] or HIGHLIGHT_FONT_COLOR;
	return color.r, color.g, color.b, color.hex or "|cffffffff";
end

-- keep both previews in their half of the frame: same width, scaled down if a line is too long
local PREVIEW_WIDTH = 252;
local function FitPreviews(left, right)
	local width = math.max(left:GetWidth(), right:GetWidth());
	local scale = math.min(1, PREVIEW_WIDTH / width);
	for _, tooltip in ipairs({ left, right }) do
		tooltip:SetScale(scale);
		tooltip:SetWidth(width);
	end
end

local function GeneratePreview(tooltip, info, levelInfo, baseInfo, isUpgrade)
	tooltip:SetOwner(ItemUpgradeFrame, "ANCHOR_PRESERVE");
	tooltip:ClearLines();
	tooltip:AddLine(isUpgrade and ITEM_UPGRADE_NEXT_UPGRADE or ITEM_UPGRADE_CURRENT, 0.5, 0.5, 0.5);
	local name = GetItemInfo(info.itemId) or ("item:" .. info.itemId);
	local r, g, b = QualityColor(info.itemId);
	tooltip:AddLine(name, r, g, b);

	local increment = levelInfo.itemLevel - baseInfo.itemLevel;
	if isUpgrade and increment > 0 then
		tooltip:AddLine(ITEM_UPGRADE_ITEM_LEVEL_BONUS_STAT_FORMAT:format(levelInfo.itemLevel, increment), 1, 0.82, 0);
	else
		tooltip:AddLine(ITEM_UPGRADE_ITEM_LEVEL_STAT_FORMAT:format(levelInfo.itemLevel), 1, 0.82, 0);
	end
	tooltip:AddLine(ITEM_UPGRADE_FRAME_CURRENT_UPGRADE_FORMAT_STRING:format(info.track, levelInfo.upgradeLevel, info.max), 1, 0.82, 0);

	-- weapon damage, armor, stats; on the upgrade side the increase is shown in green
	local function Diff(new, old)
		if isUpgrade and new > old then
			return (" |cff00ff00(+%d)|r"):format(new - old);
		end
		return "";
	end
	if levelInfo.maxDamage > 0 then
		tooltip:AddLine((DAMAGE_TEMPLATE or "Урон: %d - %d"):format(levelInfo.minDamage, levelInfo.maxDamage) .. Diff(levelInfo.maxDamage, baseInfo.maxDamage), 1, 1, 1);
		if levelInfo.delay > 0 then
			local dps = (levelInfo.minDamage + levelInfo.maxDamage) / 2 / (levelInfo.delay / 1000);
			tooltip:AddLine((DPS_TEMPLATE or "(%.1f ед. урона в секунду)"):format(dps), 1, 1, 1);
		end
	end
	if levelInfo.armor > 0 then
		tooltip:AddLine((ARMOR_TEMPLATE or "Броня: %d"):format(levelInfo.armor) .. Diff(levelInfo.armor, baseInfo.armor), 1, 1, 1);
	end
	for index, stat in ipairs(levelInfo.stats) do
		local old = baseInfo.stats[index];
		tooltip:AddLine(FormatStat(stat.type, stat.value) .. Diff(stat.value, old and old.value or stat.value), 1, 1, 1);
	end
	tooltip:SetMinimumWidth(230);
	tooltip:Show();
end

---------------------------------------------------------------------------
-- update (retail ItemUpgradeMixin:UpdateUpgradeItemInfo / PopulatePreviewFrames)
---------------------------------------------------------------------------
local function ClearItem(self)
	self.UpgradeItemButton.Icon:SetTexture(nil);
	self.UpgradeItemButton:SetNormalTexture(self.UpgradeItemButton.NormalTex);
	self.UpgradeItemButton.NormalTex:SetAtlas("itemupgrade_greenplusicon");
	self.UpgradeItemButton.EmptySlotGlow:Show();
	self.UpgradeButton:Disable();
	self.MissingDescription:Show();
	self.LeftItemPreviewFrame:Hide();
	self.RightItemPreviewFrame:Hide();
	self.UpgradeCostFrame:Hide();
	self.PlayerCurrencies:Hide();
	self.FrameErrorText:Hide();
	self.Arrow:Hide();
	local itemInfo = self.ItemInfo;
	itemInfo.MissingItemText:Show();
	itemInfo.ItemName:Hide();
	itemInfo.UpgradeProgress:Hide();
	itemInfo.UpgradeTo:Hide();
	itemInfo.Dropdown:Hide();
end

function ItemUpgradeFrame_ApplyTargetLevel(self, level)
	local info = self.info;
	self.targetLevel = level;
	self.numUpgradeLevels = level - info.curr;
	local base = info.levels[1];
	local target = info.levels[self.numUpgradeLevels + 1];
	local maxed = info.curr >= info.max;
	local failure = info.error ~= "" and (_G[info.error] or info.error) or (maxed and ITEM_UPGRADE_NO_MORE_UPGRADES) or nil;
	local showRight = not failure and target ~= nil;

	self.LeftItemPreviewFrame:SetScale(1);
	self.RightItemPreviewFrame:SetScale(1);
	GeneratePreview(self.LeftItemPreviewFrame, info, base, base, false);
	if showRight then
		GeneratePreview(self.RightItemPreviewFrame, info, target, base, true);
		if self.RightItemPreviewFrame:GetHeight() > self.LeftItemPreviewFrame:GetHeight() then
			self.LeftItemPreviewFrame:SetHeight(self.RightItemPreviewFrame:GetHeight());
		end
		self.Arrow:Show();
		self.FrameErrorText:Hide();
		FitPreviews(self.LeftItemPreviewFrame, self.RightItemPreviewFrame);
	else
		self.RightItemPreviewFrame:Hide();
		self.Arrow:Hide();
		self.FrameErrorText:SetText(failure or "");
		self.FrameErrorText:SetShown(failure ~= nil);
	end

	-- cost: count x item + money, red if not enough (retail PopulatePreviewFrames)
	local enough = true;
	local cost = self.UpgradeCostFrame;
	local owned = self.PlayerCurrencies;
	if info.costItem > 0 then
		local icon = GetItemIcon(info.costItem);
		local need = info.costCount * math.max(1, self.numUpgradeLevels);
		local have = GetItemCount(info.costItem, true);
		cost.Quantity:SetText(need);
		cost.Quantity:SetTextColor(have >= need and 1 or 1, have >= need and 1 or 0.1, have >= need and 1 or 0.1);
		cost.CostIcon.Icon:SetTexture(icon);
		cost.CostIcon.itemId = info.costItem;
		cost.CostIcon:Show();
		owned.Quantity:SetText(have);
		owned.CostIcon.Icon:SetTexture(icon);
		owned.CostIcon.itemId = info.costItem;
		owned.CostIcon:Show();
		enough = have >= need;
		self.missingCostItem = not enough and info.costItem or nil;
	else
		cost.Quantity:SetText("");
		cost.CostIcon:Hide();
		owned.Quantity:SetText("");
		owned.CostIcon:Hide();
		self.missingCostItem = nil;
	end
	local money = info.costMoney * math.max(1, self.numUpgradeLevels);
	MoneyFrame_Update(cost.MoneyCostFrame:GetName(), money);
	cost.MoneyCostFrame:SetShown(money > 0);
	if money > GetMoney() then
		enough = false;
	end
	self.missingMoney = money > GetMoney();
	cost:SetShown(showRight);
	owned:Show();

	self.UpgradeButton:SetEnabled(showRight and enough);
	self.costString = (info.costItem > 0 and ("%d x %s"):format(info.costCount * math.max(1, self.numUpgradeLevels), GetItemInfo(info.costItem) or "?") or "")
		.. (money > 0 and ((info.costItem > 0 and " + " or "") .. (GetCoinTextureString and GetCoinTextureString(money) or money)) or "");

	-- item info (retail ItemUpgradeItemInfoMixin:Setup)
	local itemInfo = self.ItemInfo;
	local name = GetItemInfo(info.itemId) or ("item:" .. info.itemId);
	local _, _, _, hex = QualityColor(info.itemId);
	itemInfo.MissingItemText:Hide();
	itemInfo.ItemName:SetText(hex .. name .. "|r");
	itemInfo.ItemName:Show();
	itemInfo.UpgradeProgress:SetText(ITEM_UPGRADE_PROGRESS_LEVEL_FORMAT_STRING:format(info.track, info.curr, info.max, base.itemLevel, info.minItemLevel, info.maxItemLevel));
	itemInfo.UpgradeProgress:SetShown(info.track ~= "");
	itemInfo.UpgradeTo:SetShown(showRight);
	itemInfo.Dropdown:SetShown(showRight);
	if showRight and itemInfo.Dropdown.GenerateMenu then
		itemInfo.Dropdown:GenerateMenu();
	end
	if showRight and itemInfo.Dropdown.OverrideText then
		itemInfo.Dropdown:OverrideText(ITEM_UPGRADE_DROPDOWN_LEVEL_FORMAT_STRING:format(info.track, level, info.max));
	end
end

function ItemUpgradeFrame_Update(self)
	local info = self.info;
	if not info then
		ClearItem(self);
		return;
	end
	local button = self.UpgradeItemButton;
	button:SetNormalTexture(nil);
	button.Icon:SetTexture(GetItemIcon(info.itemId));
	button.EmptySlotGlow:Hide();
	self.MissingDescription:Hide();
	ItemUpgradeFrame_ApplyTargetLevel(self, math.min(info.curr + 1, math.max(info.max, info.curr)));
end

---------------------------------------------------------------------------
-- level dropdown (retail InitDropdown)
---------------------------------------------------------------------------
function ItemUpgradeFrame_SetupDropdown(self)
	local dropdown = self.ItemInfo.Dropdown;
	dropdown:SetupMenu(function(owner, rootDescription)
		local info = self.info;
		if not info then
			return;
		end
		for level = info.curr + 1, info.max do
			rootDescription:CreateRadio(ITEM_UPGRADE_DROPDOWN_LEVEL_FORMAT_STRING:format(info.track, level, info.max), function()
				return level == self.targetLevel;
			end, function()
				ItemUpgradeFrame_ApplyTargetLevel(self, level);
			end);
		end
	end);
end

---------------------------------------------------------------------------
-- item slot (retail ItemUpgradeSlotMixin): drop an item, click - list of upgradeable items, right click - clear
---------------------------------------------------------------------------
local lastPickup;   -- 3.3.5 GetCursorInfo has no location: remember where the item was picked up

hooksecurefunc("PickupContainerItem", function(bag, slot)
	lastPickup = { bag, slot };
end);
hooksecurefunc("PickupInventoryItem", function(slot)
	lastPickup = { 255, slot };
end);

local function SetItem(bag, slot)
	ItemUpgradeFrame.location = { bag, slot };
	Send("IUPG_SET", bag, slot);
end

local function SetCursorItem()
	local kind = GetCursorInfo();
	if kind == "item" and lastPickup then
		SetItem(lastPickup[1], lastPickup[2]);
		ClearCursor();
		return true;
	end
	return false;
end

function ItemUpgradeSlot_OnLoad(self)
	self:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	self:RegisterForDrag("LeftButton");
end

function ItemUpgradeSlot_OnReceiveDrag(self)
	SetCursorItem();
end

function ItemUpgradeSlot_OnClick(self, button)
	if button == "RightButton" then
		ItemUpgradeFrame.location = nil;
		Send("IUPG_CLEAR");
		return;
	end
	if SetCursorItem() then
		return;
	end
	-- retail: EquipmentFlyout with upgradeable items
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		return;
	end
	MenuUtil.CreateContextMenu(self, function(owner, rootDescription)
		rootDescription:CreateTitle(ITEM_UPGRADE);
		local any = false;
		for bag, slots in pairs(items) do
			for slot, data in pairs(slots) do
				if data.level < data.max then
					local name, _, quality = GetItemInfo(data.itemId);
					local color = ITEM_QUALITY_COLORS[quality or 1];
					local text = (color and color.hex or "") .. (name or ("item:" .. data.itemId)) .. "|r  "
						.. ITEM_UPGRADE_DROPDOWN_LEVEL_FORMAT_STRING:format(trackNames[data.track] or "", data.level, data.max);
					rootDescription:CreateButton(text, function()
						SetItem(bag, slot);
					end);
					any = true;
				end
			end
		end
		if not any then
			rootDescription:CreateTitle(ITEM_UPGRADE_NO_TRACK);
		end
	end);
end

function ItemUpgradeSlot_OnEnter(self)
	local location = ItemUpgradeFrame.location;
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	if ItemUpgradeFrame.info and location then
		if location[1] == 255 then
			GameTooltip:SetInventoryItem("player", location[2]);
		else
			GameTooltip:SetBagItem(location[1], location[2]);
		end
	else
		GameTooltip:SetText(ITEM_UPGRADE_DESCRIPTION, 1, 1, 1, 1, true);
	end
	GameTooltip:Show();
end

function ItemUpgradeCostIcon_OnEnter(self)
	if self.itemId then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetHyperlink("item:" .. self.itemId);
		GameTooltip:Show();
	end
end

function ItemUpgradePreview_OnEnter(self) end
function ItemUpgradePreview_OnLeave(self) end

---------------------------------------------------------------------------
-- upgrade button + confirm (retail ItemUpgradeButtonMixin, CONFIRM_UPGRADE_ITEM)
---------------------------------------------------------------------------
StaticPopupDialogs["CONFIRM_UPGRADE_ITEM"] = {
	text = "%s",
	button1 = YES,
	button2 = NO,
	OnAccept = function(self, data)
		PlayUpgradedCelebration(ItemUpgradeFrame);
		Send("IUPG_UPGRADE", data.levels);
	end,
	OnCancel = function()
		ItemUpgradeFrame_Update(ItemUpgradeFrame);
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
};

function ItemUpgradeButton_OnClick(self)
	local frame = ItemUpgradeFrame;
	local info = frame.info;
	if not info then
		return;
	end
	self:Disable();
	local name = GetItemInfo(info.itemId) or ("item:" .. info.itemId);
	local _, _, _, hex = QualityColor(info.itemId);
	local text = ITEM_UPGRADE_CONFIRM:format(hex .. name .. "|r", info.track, frame.targetLevel, info.max, frame.costString or "");
	StaticPopup_Show("CONFIRM_UPGRADE_ITEM", text, nil, { levels = frame.numUpgradeLevels });
end

function ItemUpgradeButton_OnEnter(self)
	local frame = ItemUpgradeFrame;
	if self:IsEnabled() == 1 or not frame.info then
		return;
	end
	local text;
	if frame.missingCostItem then
		text = ITEM_UPGRADE_ERROR_NOT_ENOUGH_CURRENCY:format(GetItemInfo(frame.missingCostItem) or "?");
	elseif frame.missingMoney then
		text = ERR_NOT_ENOUGH_MONEY;
	elseif frame.FrameErrorText:IsShown() then
		text = frame.FrameErrorText:GetText();
	end
	if text then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(text, 1, 0.1, 0.1, 1, true);
		GameTooltip:Show();
	end
end

---------------------------------------------------------------------------
-- tooltip line: "Уровень улучшения: Ветеран 3/8" (retail ITEM_UPGRADE_TOOLTIP_FORMAT_STRING)
---------------------------------------------------------------------------
local function AddUpgradeLine(tooltip, bag, slot)
	local data = items[bag] and items[bag][slot];
	if data then
		local text = ITEM_UPGRADE_TOOLTIP_FORMAT_STRING:format(trackNames[data.track] or "", data.level, data.max);
		-- append to the name line: shifting lines would break gem icons and the sell price frame
		local line = _G[tooltip:GetName() .. "TextLeft1"];
		local current = line and line:GetText();
		if current and not current:find("\n", 1, true) then
			line:SetText(current .. "\n|cffffd100" .. text .. "|r");
		end
		tooltip:Show();
	end
end

local tooltipInit = CreateFrame("Frame");
tooltipInit:RegisterEvent("PLAYER_LOGIN");
tooltipInit:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN");
	hooksecurefunc(GameTooltip, "SetInventoryItem", function(tooltip, unit, slot)
		if unit == "player" then
			AddUpgradeLine(tooltip, 255, slot);
		end
	end);
	hooksecurefunc(GameTooltip, "SetBagItem", function(tooltip, bag, slot)
		AddUpgradeLine(tooltip, bag, slot);
	end);
end);

---------------------------------------------------------------------------
-- server
---------------------------------------------------------------------------
if Comm_Register then
	Comm_Register("IUPG_OPEN", function()
		ItemUpgradeFrame_Show();
	end);

	Comm_Register("IUPG_CLOSE", function()
		ItemUpgradeFrame_Hide();
	end);

	Comm_Register("IUPG_ITEMS", function(list, names)
		wipe(items);
		for bag, slot, itemId, track, level, max in (list or ""):gmatch("(%d+)/(%d+)/(%d+)/(%d+)/(%d+)/(%d+)") do
			bag = tonumber(bag);
			items[bag] = items[bag] or {};
			items[bag][tonumber(slot)] = { itemId = tonumber(itemId), track = tonumber(track), level = tonumber(level), max = tonumber(max) };
		end
		for id, name in (names or ""):gmatch("(%d+)/([^,]+)") do
			trackNames[tonumber(id)] = name;
		end
	end);

	Comm_Register("IUPG_INFO", function(bag, slot, itemId, curr, max, track, minItemLevel, maxItemLevel, costItem, costCount, costMoney, levelsText, err)
		local frame = ItemUpgradeFrame;
		if not itemId or itemId == "" then
			frame.info = nil;
		else
			local info = {
				bag = tonumber(bag), slot = tonumber(slot), itemId = tonumber(itemId), curr = tonumber(curr) or 0, max = tonumber(max) or 0,
				track = track or "", minItemLevel = tonumber(minItemLevel) or 0, maxItemLevel = tonumber(maxItemLevel) or 0,
				costItem = tonumber(costItem) or 0, costCount = tonumber(costCount) or 0, costMoney = tonumber(costMoney) or 0,
				levels = {}, error = err or "",
			};
			for levelText in (levelsText or ""):gmatch("[^#]+") do
				table.insert(info.levels, ParseLevel(levelText));
			end
			if #info.levels == 0 then
				info.levels[1] = { upgradeLevel = info.curr, itemLevel = 0, stats = {}, armor = 0, minDamage = 0, maxDamage = 0, delay = 0 };
			end
			frame.info = info;
			frame.location = { info.bag, info.slot };
		end
		if frame:IsShown() then
			ItemUpgradeFrame_Update(frame);
		end
	end);

	Comm_Register("IUPG_RESULT", function(ok, err)
		if ok ~= "1" and err and err ~= "" then
			UIErrorsFrame:AddMessage(_G[err] or err, 1.0, 0.1, 0.1, 1.0);
			if ItemUpgradeFrame:IsShown() then
				ItemUpgradeFrame_Update(ItemUpgradeFrame);
			end
		end
	end);
end

-- items move between bags - the tooltip list is refreshed (BAG_UPDATE comes in bursts)
local watcher = CreateFrame("Frame");
watcher:RegisterEvent("BAG_UPDATE");
watcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED");
watcher:Hide();
watcher:SetScript("OnEvent", function(self)
	self.delay = 0.5;
	self:Show();
end);
watcher:SetScript("OnUpdate", function(self, elapsed)
	self.delay = self.delay - elapsed;
	if self.delay <= 0 then
		self:Hide();
		if not ItemUpgradeFrame:IsShown() then
			Send("IUPG_LIST");
		end
	end
end);
