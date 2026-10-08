--[[
	SPELLBOOK NAMING NOTE:
	For consistency with 20+ years of existing code, we're continuing to maintain the SpellBook/spellBook (capital B) captialization in code.
	Technically "spellbook" is one word (ie Spellbook/spellbook) but to avoid subtle confusing bugs from mixing/matching, do NOT use that casing.
]]

local Templates = {
	["HEADER"] = { template = "SpellBookHeaderTemplate", initFunc = SpellBookHeaderMixin.Init },
	["SPELL"] = { template = "SpellBookItemTemplate", initFunc = SpellBookItemMixin.Init, resetFunc = SpellBookItemMixin.Reset },
};

-- Events that should always be listened to
local SpellBookLifetimeEvents = {
	"PLAYER_ENTERING_WORLD",
	"PLAYER_LEAVING_WORLD",
};
-- Events that should only be listened to while in the world (avoided while entering/exiting it)
local SpellBookInWorldEvents = {
	"LEARNED_SPELL_IN_TAB",
	"PET_BAR_UPDATE",
	"PLAYER_LEVEL_UP",
	"PLAYER_GUILD_UPDATE",
};
-- Events that should only be listened to while already visible
local SpellBookWhileVisibleEvents = {
	"SPELLS_CHANGED",
	"DISPLAY_SIZE_CHANGED",
	"UI_SCALE_CHANGED",
};
local SpellBookWhileVisibleUnitEvents = {
	"ACTIVE_TALENT_GROUP_CHANGED",
	"UNIT_PET",
};

SpellBookFrameMixin = CreateFromMixins(SpellBookFrameTutorialsMixin);

local inWorld = false;

function SpellBookFrameMixin:OnLoad()
	TabSystemOwnerMixin.OnLoad(self);
	self:SetTabSystem(self.CategoryTabSystem);
	self.categoryMixins = {
		CreateAndInitFromMixin(SpellBookClassCategoryMixin, self);
		CreateAndInitFromMixin(SpellBookGeneralCategoryMixin, self);
		CreateAndInitFromMixin(SpellBookPetCategoryMixin, self);
		CreateAndInitFromMixin(SpellBookGuildCategoryMixin, self);
	};

	for _, categoryMixin in ipairs(self.categoryMixins) do
		categoryMixin:SetTabID(self:AddNamedTab(categoryMixin:GetName()));
	end

	self.PagedSpellsFrame:SetElementTemplateData(Templates);
	self.PagedSpellsFrame:RegisterCallback(PagedContentFrameBaseMixin.Event.OnUpdate, self.OnPagedSpellsUpdate, self);

	self:SetupSettingsDropdown();

	FrameUtil.RegisterFrameForEvents(self, SpellBookLifetimeEvents);

	if inWorld then
		FrameUtil.RegisterFrameForEvents(self, SpellBookInWorldEvents);
	end

	local onPagingButtonEnter = GenerateClosure(self.OnPagingButtonEnter, self);
	local onPagingButtonLeave = GenerateClosure(self.OnPagingButtonLeave, self);
	self.PagedSpellsFrame.PagingControls:SetButtonHoverCallbacks(onPagingButtonEnter, onPagingButtonLeave);

	self:SetupCornerFlipbook();
	self:SetupArt();

	SpellBookFrameTutorialsMixin.OnLoad(self);
	self:InitializeSearch();
end

function SpellBookFrameMixin:OnPagedSpellsUpdate()
	self:CheckShowHelpTips();
	EventRegistry:TriggerEvent("PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged");
end

function SpellBookFrameMixin:OnShow()
	self:UpdateAttic();
	self:UpdateAllSpellData();

	if not self:GetTab() and not self:IsInSearchResultsMode() then
		self:ResetToFirstAvailableTab();
	end

	FrameUtil.RegisterFrameForEvents(self, SpellBookWhileVisibleEvents);
	FrameUtil.RegisterFrameForUnitEvents(self, SpellBookWhileVisibleUnitEvents, "player");

	EventRegistry:TriggerEvent("PlayerSpellsFrame.SpellBookFrame.Show");
	PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN);

	SpellBookFrameTutorialsMixin.OnShow(self);
end

function SpellBookFrameMixin:OnHide()
	FrameUtil.UnregisterFrameForEvents(self, SpellBookWhileVisibleEvents);
	FrameUtil.UnregisterFrameForEvents(self, SpellBookWhileVisibleUnitEvents);

	EventRegistry:TriggerEvent("PlayerSpellsFrame.SpellBookFrame.Hide");
	PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE);

	SpellBookFrameTutorialsMixin.OnHide(self);
end

function SpellBookFrameMixin:OnEvent(event, ...)
	if event == "PLAYER_ENTERING_WORLD" then
		inWorld = true;
		FrameUtil.RegisterFrameForEvents(self, SpellBookInWorldEvents);
	elseif event == "PLAYER_LEAVING_WORLD" then
		inWorld = false;
		FrameUtil.UnregisterFrameForEvents(self, SpellBookInWorldEvents);
	elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" or event == "PET_BAR_UPDATE" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_GUILD_UPDATE" then
		if self:IsVisible() then
			self:UpdateAllSpellData();
		else
			self.spellDataDirty = true;
		end
	elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
		self:UpdateAllSpellData(true);
	elseif event == "UNIT_PET" then
		local unit = ...;
		if unit == "player" then
			self:UpdateAllSpellData();
		end
	end
end

SPELLBOOK_HIDE_PASSIVES = SPELLBOOK_HIDE_PASSIVES or false;

function SpellBookFrameMixin:SetupSettingsDropdown()
	local check = self.HidePassivesCheck;
	check.text = check.text or _G[check:GetName() .. "Text"];
	check.text:SetText(SPELLBOOK_FILTER_PASSIVES);
	check:SetChecked(SPELLBOOK_HIDE_PASSIVES);
	check:SetScript("OnClick", function(button)
		SPELLBOOK_HIDE_PASSIVES = button:GetChecked() and true or false;
		self:UpdateDisplayedSpells(true, false);
	end);
	local function AddTooltip(button)
		button:SetScript("OnEnter", function(b)
			GameTooltip:SetOwner(b, "ANCHOR_BOTTOM");
			GameTooltip:SetText(b.text:GetText(), 1, 1, 1);
			GameTooltip:Show();
		end);
		button:SetScript("OnLeave", GameTooltip_Hide);
	end
	AddTooltip(check);

	local ranks = self.ShowAllRanksCheck;
	AddTooltip(ranks);
	ranks.text = ranks.text or _G[ranks:GetName() .. "Text"];
	ranks.text:SetText(SHOW_ALL_SPELL_RANKS or "Все уровни заклинаний");
	ranks:SetChecked(C_SpellBook.IsShowingAllRanks());
	ranks:SetScript("OnClick", function(button)
		C_SpellBook.SetShowAllRanks(button:GetChecked());
		self.spellDataDirty = true;
		for _, category in ipairs(self.categoryMixins) do
			category.spellGroups = nil;
		end
		self:UpdateAllSpellData(true);
	end);

	self.CategoryTabSystem:HookScript("OnSizeChanged", function() self:ResizeSearchBox(); end);
end

function SpellBookFrameMixin:UpdateAttic()
	self:LayoutSettingsRow();
end

function SpellBookFrameMixin:SetTab(tabID)
	if tabID == nil then
		self.internalTabTracker:SetTab(nil);
		self.CategoryTabSystem:SetTabVisuallySelected(nil);
		self:OnActiveCategoryChanged();
		return;
	end
	TabSystemOwnerMixin.SetTab(self, tabID);

	self:OnActiveCategoryChanged();
end

function SpellBookFrameMixin:SetMinimized(shouldBeMinimized)
	local minimizedChanged = self.isMinimized ~= shouldBeMinimized;
	if not self.isMinimized and shouldBeMinimized then
		self.isMinimized = true;
		self:SetWidth(self.minimizedWidth);

		-- Collapse down to one paged view (ie left half of book)
		self.PagedSpellsFrame:SetViewsPerPage(1, true);
		self.PagedSpellsFrame.ViewFrames[2]:Hide();

		-- Minimizing requires shortening TopBar and adjusting the right UV to prevent it from looking squished.
		self:SetTopBarWidth(self.minimizedWidth);
	elseif self.isMinimized and not shouldBeMinimized then
		self.isMinimized = false;
		self:SetWidth(self.maximizedWidth);

		-- Expand back up to two paged views (ie whole book)
		self.PagedSpellsFrame.ViewFrames[2]:Show();
		self.PagedSpellsFrame:SetViewsPerPage(2, true);

		-- Maximizing requires lenghtening TopBar and adjusting the right UV to prevent it from looking stretched.
		self:SetTopBarWidth(self.maximizedWidth);
	end

	if minimizedChanged then
		self:LayoutSettingsRow();
		for _, minimizedPiece in ipairs(self.minimizedArt) do
			minimizedPiece:SetShown(self.isMinimized);
		end
		for _, maximizedPiece in ipairs(self.maximizedArt) do
			maximizedPiece:SetShown(not self.isMinimized);
		end

		self:UpdateTutorialsForFrameSize();
	end
end

-- 3.3.5: SetTexCoord работает от всего файла, поэтому считаем внутри атласа
function SpellBookFrameMixin:SetTopBarWidth(width)
	local info = C_Texture.GetAtlasInfo("spellbook-background-evergreen-header");
	width = tonumber(width);
	local full = tonumber(self.topBarFullWidth) or width;
	if info then
		local right = info.left + (info.right - info.left) * math.min(1, width / full);
		self.TopBar:SetTexCoord(info.left, right, info.top, info.bottom);
	end
	self.TopBar:SetWidth(width);
end

local SEARCH_BOX_MAX_WIDTH = 300;
local SEARCH_BOX_MIN_WIDTH = 120;
local SETTINGS_RIGHT_MARGIN = 40;
local CHECK_TEXT_GAP = 14;
local SEARCH_BOX_LEFT_SPACING = 20;

local function CheckTextWidth(check)
	return check.text and check.text:IsShown() and (check.text:GetStringWidth() + CHECK_TEXT_GAP) or 4;
end

-- галочки справа в одну строку, поиск — слева от них;
-- в свёрнутом виде подписи прячутся (остаются подсказки при наведении)
function SpellBookFrameMixin:LayoutSettingsRow()
	local compact = self.isMinimized;
	local checks = { self.HidePassivesCheck, self.ShowAllRanksCheck };

	local anchor, anchorPoint, offset = self, "TOPRIGHT", -SETTINGS_RIGHT_MARGIN;
	for i, check in ipairs(checks) do
		check.text:SetShown(not compact);
		check:ClearAllPoints();
		local textWidth = CheckTextWidth(check);
		if i == 1 then
			check:SetPoint("TOPRIGHT", self, "TOPRIGHT", offset - textWidth, -14);
		else
			check:SetPoint("RIGHT", anchor, "LEFT", -textWidth - 6, 0);
		end
		anchor = check;
	end

	self.SearchBox:ClearAllPoints();
	self.SearchBox:SetPoint("RIGHT", anchor, "LEFT", -10, 0);

	self:ResizeSearchBox();
	-- ширина вкладок пересчитывается на следующем кадре (LayoutFrame)
	C_Timer.After(0, function() self:ResizeSearchBox(); end);
end

function SpellBookFrameMixin:ResizeSearchBox()
	local width = SEARCH_BOX_MAX_WIDTH;
	local leftEdge = self.CategoryTabSystem:GetRight();
	local rightEdge = self.SearchBox:GetRight();
	if leftEdge and rightEdge then
		local space = rightEdge - leftEdge - SEARCH_BOX_LEFT_SPACING;
		width = math.max(SEARCH_BOX_MIN_WIDTH, math.min(space, SEARCH_BOX_MAX_WIDTH));
	end
	self.SearchBox:SetWidth(width);
end

-- Expects a PlayerSpellsUtil.SpellBookCategories value
function SpellBookFrameMixin:TrySetCategory(categoryEnum)
	for _, categoryMixin in ipairs(self.categoryMixins) do
		if categoryMixin:GetCategoryEnum() == categoryEnum and categoryMixin:IsAvailable() then
			self:SetTab(categoryMixin:GetTabID());
			return true;
		end
	end
	return false;
end

-- Expects a PlayerSpellsUtil.SpellBookCategories value
function SpellBookFrameMixin:IsCategoryActive(categoryEnum)
	local activeCategoryMixin = self:GetActiveCategoryMixin();

	return activeCategoryMixin and activeCategoryMixin:GetCategoryEnum() == categoryEnum;
end

-- If found, navigates to the category and page containing the spell and returns its frame
-- If spell is inside a flyout, returns Flyout button and SpellBookItem frame; Otherwise, returns only SpellBookItem frame
function SpellBookFrameMixin:GoToSpell(spellID, knownSpellsOnly, toggleFlyout, flyoutReason)
	local includeHidden = false;
	local includeFlyouts = true;
	local includeFutureSpells = not knownSpellsOnly;
	local includeOffSpec = not knownSpellsOnly;

	local slotIndex, spellBank = C_SpellBook.FindSpellBookSlotForSpell(spellID, includeHidden, includeFlyouts, includeFutureSpells, includeOffSpec);

	if not slotIndex or not spellBank then
		return;
	end

	local activeTabID = self:GetTab();
	local categoryMixinForSpell = nil;
	-- Each category contains specific ranges of slot indices within a spell bank, find which one contains this index
	for _, categoryMixin in ipairs(self.categoryMixins) do
		if categoryMixin:ContainsSlot(slotIndex, spellBank) then
			categoryMixinForSpell = categoryMixin;
			break;
		end
	end

	if not categoryMixinForSpell or not categoryMixinForSpell:IsAvailable() then
		return;
	end

	-- Switch categories to the matching one
	if categoryMixinForSpell:GetTabID() ~= activeTabID then
		self:SetTab(categoryMixinForSpell:GetTabID());
	end

	-- Try to page to the matching SpellBookItem
	local spellBookItemFrame = self.PagedSpellsFrame:GoToElementByPredicate(function(elementData) return elementData.slotIndex == slotIndex; end);

	if not spellBookItemFrame then
		return;
	end

	return spellBookItemFrame;
end

-- Returns frame for spell only if it's currently being displayed; See GoToSpell to page to and get the specified spell
-- If spell is inside a flyout, returns Flyout button and SpellBookItem frame; Otherwise, returns only SpellBookItem frame
function SpellBookFrameMixin:GetSpellFrame(spellID, knownSpellsOnly, toggleFlyout, flyoutReason)
	local includeHidden = false;
	local includeFlyouts = true;
	local includeFutureSpells = not knownSpellsOnly;
	local includeOffSpec = not knownSpellsOnly;

	local slotIndex, spellBank = C_SpellBook.FindSpellBookSlotForSpell(spellID, includeHidden, includeFlyouts, includeFutureSpells, includeOffSpec);

	if not slotIndex or not spellBank then
		return;
	end

	-- Try to page to the matching SpellBookItem
	local spellBookItemFrame = self.PagedSpellsFrame:GetElementFrameByPredicate(function(elementData)
		return elementData.slotIndex == slotIndex and elementData.spellBank == spellBank;
	end);

	if not spellBookItemFrame then
		return;
	end

	return spellBookItemFrame;
end

function SpellBookFrameMixin:OnActiveCategoryChanged()
	local newActiveTabID = self:GetTab();
	if newActiveTabID == nil then
		self.PagedSpellsFrame:RemoveDataProvider();
		self.lastActiveTabID = nil;
		return;
	end

	if self:IsInSearchResultsMode() then
		local skipTabReset = true;
		self:ClearActiveSearchState(skipTabReset);
	end

	local wasCategoryActive = self.lastActiveTabID == newActiveTabID;
	self.lastActiveTabID = newActiveTabID;

	local forceUpdateSpellGroups = not wasCategoryActive;
	local resetCurrentPage = not wasCategoryActive;
	self:UpdateDisplayedSpells(forceUpdateSpellGroups, resetCurrentPage);
end

function SpellBookFrameMixin:MarkSpellDataDirty()
	self.spellDataDirty = true;
	if self:IsVisible() then
		self:UpdateAllSpellData();
	end
end

function SpellBookFrameMixin:UpdateAllSpellData(resetCurrentPage)
	self.isUpdatingAllSpellData = true;
	local activeTabID = self:GetTab();

	local isActiveCategoryUnavailable = false;
	local didActiveCategorySpellGroupsChange = false;

	-- Update all category spell groups
	for _, categoryMixin in ipairs(self.categoryMixins) do
		local tabID = categoryMixin:GetTabID();

		local isAvailable = categoryMixin:IsAvailable();
		local didSpellGroupsChange = categoryMixin:UpdateSpellGroups();

		self.CategoryTabSystem:SetTabShown(tabID, isAvailable);

		if activeTabID == tabID then
			isActiveCategoryUnavailable = not isAvailable;
			didActiveCategorySpellGroupsChange = didSpellGroupsChange;
		end
	end

	if isActiveCategoryUnavailable then
		self:ResetToFirstAvailableTab();
	else
		local forceUpdateSpellGroups = self.spellDataDirty or didActiveCategorySpellGroupsChange;
		self:UpdateDisplayedSpells(forceUpdateSpellGroups, resetCurrentPage);
	end

	self.isUpdatingAllSpellData = false;
	self.spellDataDirty = false;
end

function SpellBookFrameMixin:UpdateDisplayedSpells(forceUpdateSpellGroups, resetCurrentPage)
	local activeCategoryMixin = self:GetActiveCategoryMixin();
	if not activeCategoryMixin then
		if self:IsInSearchResultsMode() then
			self:UpdateFullSearchResults();
		end
		return;
	end

	local didSpellGroupsChange = false;
	-- Only update category's spell groups if that hasn't already been covered as part of updating all data
	if not self.isUpdatingAllSpellData then
		didSpellGroupsChange = activeCategoryMixin:UpdateSpellGroups();
	end

	if didSpellGroupsChange or forceUpdateSpellGroups then
		-- Spell groups updated, so recreate data provider for spell book items using them
		local byDataGroup = true;
		local categoryData = activeCategoryMixin:GetSpellBookItemData(byDataGroup, self:GetSpellBookItemFilterInstance());
		local categoryDataProvider = CreateDataProvider(categoryData);
		self.PagedSpellsFrame:SetDataProvider(categoryDataProvider, not resetCurrentPage);
	else
		-- No spell groups update, so just update the already-populated spell book item frames
		self:ForEachDisplayedSpell(function(spellBookItemFrame)
			spellBookItemFrame:UpdateSpellData();
		end);
	end
end

-- Creates an instance of ShouldDisplaySpellBookItem with injected state checks to prevent needlessly repeating expensive checks over every single SpellBookItem
function SpellBookFrameMixin:GetSpellBookItemFilterInstance()
	local isKioskEnabled = Kiosk.IsEnabled();
	local isHidingPassives = self:IsHidingPassives();
	return GenerateClosure(self.ShouldDisplaySpellBookItem, self, isKioskEnabled, isHidingPassives);
end

function SpellBookFrameMixin:IsHidingPassives()
	return not self:IsInSearchResultsMode() and SPELLBOOK_HIDE_PASSIVES;
end

function SpellBookFrameMixin:ShouldDisplaySpellBookItem(isKioskEnabled, isHidingPassives, slotIndex, spellBank)
	if isKioskEnabled then
		-- If in Kiosk mode, filter out any future spells
		local spellBookItemType = C_SpellBook.GetSpellBookItemType(slotIndex, self.spellBank);
		if not spellBookItemType or spellBookItemType == Enum.SpellBookItemType.FutureSpell then
			return false;
		end
	end
	if isHidingPassives then
		local isPassive = C_SpellBook.IsSpellBookItemPassive(slotIndex, spellBank);
		if isPassive then
			return false;
		end
	end
	
	return true;
end

function SpellBookFrameMixin:ForEachDisplayedSpell(func)
	for _, frame in self.PagedSpellsFrame:EnumerateFrames() do
		if frame.HasValidData and frame:HasValidData() then -- Avoid header or spacer frames
			func(frame);
		end
	end
end

function SpellBookFrameMixin:ResetToFirstAvailableTab()
	for _, categoryMixin in ipairs(self.categoryMixins) do
		local isAvailable = categoryMixin:IsAvailable();
		if isAvailable then
			self:SetTab(categoryMixin:GetTabID());
			return;
		end
	end
	self:SetTab(nil);
end

function SpellBookFrameMixin:GetActiveCategoryMixin()
	local currentTabID = self:GetTab();
	if not currentTabID then
		return nil;
	end

	for _, categoryMixin in ipairs(self.categoryMixins) do
		if categoryMixin:GetTabID() == currentTabID then
			return categoryMixin;
		end
	end

	return nil;
end

function SpellBookFrameMixin:OnClickBindingUpdate()
	self:ForEachDisplayedSpell(function(spellBookItemFrame)
		spellBookItemFrame:UpdateClickBindState();
	end);
end

local FLIPBOOK_ROWS, FLIPBOOK_COLS, FLIPBOOK_FRAMES, FLIPBOOK_DURATION = 2, 4, 8, 0.25;

function SpellBookFrameMixin:SetupCornerFlipbook()
	local tex = self.BookCornerFlipbook;
	local info = C_Texture.GetAtlasInfo("spellbook-corner-flipbook-evergreen");
	tex.flipInfo = info;
	tex.frame = 1;

	tex.SetFrame = function(texture, frame)
		local fi = texture.flipInfo;
		if not fi then return; end
		frame = math.max(1, math.min(FLIPBOOK_FRAMES, frame));
		texture.frame = frame;
		local col = (frame - 1) % FLIPBOOK_COLS;
		local row = math.floor((frame - 1) / FLIPBOOK_COLS);
		local w = (fi.right - fi.left) / FLIPBOOK_COLS;
		local h = (fi.bottom - fi.top) / FLIPBOOK_ROWS;
		local l = fi.left + col * w;
		local t = fi.top + row * h;
		texture:SetTexCoord(l, l + w, t, t + h);
	end;

	if info then
		tex:SetTexture(info.file);
	end
	tex:SetFrame(1);

	local driver = CreateFrame("Frame", nil, self);
	driver:Hide();
	driver:SetScript("OnUpdate", function(d, elapsed)
		d.elapsed = d.elapsed + elapsed;
		local step = FLIPBOOK_DURATION / FLIPBOOK_FRAMES;
		while d.elapsed >= step do
			d.elapsed = d.elapsed - step;
			local nextFrame = tex.frame + d.direction;
			tex:SetFrame(nextFrame);
			if nextFrame <= 1 or nextFrame >= FLIPBOOK_FRAMES then
				d:Hide();
				return;
			end
		end
	end);
	tex.Anim = {
		Play = function(_, reverse)
			driver.direction = reverse and -1 or 1;
			driver.elapsed = 0;
			driver:Show();
		end,
		Pause = function() driver:Hide(); end,
	};
end

function SpellBookFrameMixin:SetupArt()
	self.Bookmark:ClearAllPoints();
	self.Bookmark:SetPoint("TOPRIGHT", self.BookBGLeft, "TOPRIGHT", 62, 0);
	self:SetTopBarWidth(self.maximizedWidth or self:GetWidth());
	self:LayoutSettingsRow();

	local r, g, b = SPELLBOOK_FONT_COLOR:GetRGB();
	self.PagedSpellsFrame.PagingControls.PageText:SetTextColor(r, g, b);
end

function SpellBookFrameMixin:OnPagingButtonEnter()
	self.BookCornerFlipbook.Anim:Play();
end

function SpellBookFrameMixin:OnPagingButtonLeave()
	local reverse = true;
	self.BookCornerFlipbook.Anim:Play(reverse);
end