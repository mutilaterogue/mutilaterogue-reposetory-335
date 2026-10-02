-- PlayerSpellsFrame (Midnight) — адаптация под 3.3.5a
-- Вкладки: «Таланты» (открывает окно талантов 3.3.5) и «Книга заклинаний».
-- Специализации, осмотр чужих талантов через строку и загрузки убраны.

PlayerSpellsUtil = PlayerSpellsUtil or {};
PlayerSpellsUtil.FrameTabs = PlayerSpellsUtil.FrameTabs or {
	ClassSpecializations = 1,
	ClassTalents = 2,
	SpellBook = 3,
	Glyphs = 4,
};

spellBookMinimize = spellBookMinimize or false;

PlayerSpellsFrameMixin = {};

local PlayerSpellsFrameEvents = {
	"PLAYER_LEAVING_WORLD",
};

local PlayerSpellsFrameUnitEvents = {
	"ACTIVE_TALENT_GROUP_CHANGED",
	"CHARACTER_POINTS_CHANGED",
};

function PlayerSpellsFrameMixin:OnLoad()
	self:UpdateScale();
	TabSystemOwnerMixin.OnLoad(self);
	self:SetTabSystem(self.TabSystem);
	-- specialization tab: the primary 3.3.5 tree (Blizzard_PlayerSpellsSpecializations.lua)
	self.SpecContainer = CreateFrame("Frame", nil, self);
	self.SpecContainer:SetPoint("TOPLEFT", 4, -24);
	self.SpecContainer:SetPoint("BOTTOMRIGHT", -4, 4);
	self.SpecContainer:Hide();
	PlayerSpellsSpecializations.Create(self.SpecContainer);
	self.specTabID = self:AddNamedTab(SPECIALIZATION, self.SpecContainer);
	self.talentTabID = self:AddNamedTab(TALENT_FRAME_TAB_LABEL_TALENTS, self.TalentsContainer);
	self.glyphTabID = self:AddNamedTab(GLYPHS, self.GlyphContainer);
	self.spellBookTabID = self:AddNamedTab(TALENT_FRAME_TAB_LABEL_SPELLBOOK, self.SpellBookFrame);

	self.frameTabsToTabID = {
		[PlayerSpellsUtil.FrameTabs.ClassSpecializations] = self.specTabID,
		[PlayerSpellsUtil.FrameTabs.ClassTalents] = self.talentTabID,
		[PlayerSpellsUtil.FrameTabs.Glyphs] = self.glyphTabID,
		[PlayerSpellsUtil.FrameTabs.SpellBook] = self.spellBookTabID,
	};

	self.isMinimizingEnabled = true;
	self.manualMinimizeEnabled = spellBookMinimize;
	self.minimizedOnNextShow = false;

	self.MaximizeMinimizeButton:SetOnMaximizedCallback(function() self:OnManualMaximizeClicked(); end);
	self.MaximizeMinimizeButton:SetOnMinimizedCallback(function() self:OnManualMinimizeClicked(); end);
	self.MaximizeMinimizeButton:SetMinimizedCVar("spellBookMinimize");
	self.MaximizeMinimizeButton:SkipResetOnShow(true);

	self:SetFrameLevelsFromBaseLevel(self:GetFrameLevel());
	self.SpellBookFrame:SetFrameLevel(self:GetFrameLevel() + 2);
	self.SpecContainer:SetFrameLevel(self:GetFrameLevel() + 2);
	self.TalentsContainer:SetFrameLevel(self:GetFrameLevel() + 2);
	self.GlyphContainer:SetFrameLevel(self:GetFrameLevel() + 2);
	self.TabSystem:SetFrameLevel(self:GetFrameLevel() + 25);

	self.TabSystem:ClearAllPoints();
	self.TabSystem:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 22, 2);
	self.MaximizeMinimizeButton:ClearAllPoints();
	self.MaximizeMinimizeButton:SetPoint("RIGHT", self.CloseButton, "LEFT", 0, 0);
	self.MaximizeMinimizeButton:SetFrameLevel(self.CloseButton:GetFrameLevel());

	self:SetScale(PLAYER_SPELLS_FRAME_SCALE or 0.62);
	self:RegisterForDrag("LeftButton");
	tinsert(UISpecialFrames, self:GetName());

	self:UpdatePortrait();
	self:SetupEmbeddedTalents();
end

function PlayerSpellsFrameMixin:OnShow()
	FrameUtil.RegisterFrameForEvents(self, PlayerSpellsFrameEvents);
	FrameUtil.RegisterFrameForEvents(self, PlayerSpellsFrameUnitEvents);

	self:UpdateTabs();
	if self:ShouldAutoMinimize() and not self.isMinimized then
		self:SetMinimized(true);
	end

	EventRegistry:TriggerEvent("PlayerSpellsFrame.OpenFrame");
	--PlaySound(SOUNDKIT.UI_CLASS_TALENT_OPEN_WINDOW);
	self.minimizedOnNextShow = false;
end

function PlayerSpellsFrameMixin:OnHide()
	FrameUtil.UnregisterFrameForEvents(self, PlayerSpellsFrameEvents);
	FrameUtil.UnregisterFrameForEvents(self, PlayerSpellsFrameUnitEvents);
	--PlaySound(SOUNDKIT.UI_CLASS_TALENT_CLOSE_WINDOW);
	EventRegistry:TriggerEvent("PlayerSpellsFrame.CloseFrame");
end

function PlayerSpellsFrameMixin:OnEvent(event)
	if event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "CHARACTER_POINTS_CHANGED" then
		self:UpdatePortrait();
	elseif event == "PLAYER_LEAVING_WORLD" then
		HideUIPanel(self);
	end
end

function PlayerSpellsFrameMixin:GetTalentsTabButton()
	return self:GetTabButton(self.talentTabID);
end

function PlayerSpellsFrameMixin:UpdateTabs()
	self.TabSystem:SetTabShown(self.specTabID, self:IsTabAvailable(self.specTabID));
	self.TabSystem:SetTabShown(self.talentTabID, self:IsTabAvailable(self.talentTabID));
	self.TabSystem:SetTabShown(self.glyphTabID, self:IsTabAvailable(self.glyphTabID));
	self.TabSystem:SetTabShown(self.spellBookTabID, true);

	local currentTab = self:GetTab();
	if not currentTab or not self:IsTabAvailable(currentTab) then
		self:SetToDefaultAvailableTab();
	end
end

function PlayerSpellsFrameMixin:SetToDefaultAvailableTab()
	self:SetTab(self.spellBookTabID);
end

function PlayerSpellsFrameMixin:SetOpenToSpecTab(openToSpecTab)
	self.openToSpecTab = openToSpecTab;
end

function PlayerSpellsFrameMixin:ShouldOpenToSpecTab()
	return self.openToSpecTab;
end

function PlayerSpellsFrameMixin:UpdateFrameTitle()
	local tab = self:GetTab();
	if tab == self.specTabID then
		self:SetTitle(SPECIALIZATION);
	elseif tab == self.talentTabID then
		self:SetTitle(TALENTS or TALENT_FRAME_TAB_LABEL_TALENTS);
	elseif tab == self.glyphTabID then
		self:SetTitle(GLYPHS);
	else
		self:SetTitle(SPELLBOOK);
	end
end

function PlayerSpellsFrameMixin:SetTab(tabID)
	-- no primary tree yet: the talents open on the specialization choice
	if tabID == self.talentTabID and PlayerSpellsSpecializations.loaded and not PlayerSpellsSpecializations.GetPrimary() then
		tabID = self.specTabID;
		-- the tab button marks itself after this call: mark the specialization tab next frame
		C_Timer.After(0, function()
			if self.TabSystem.SetTabVisuallySelected then
				self.TabSystem:SetTabVisuallySelected(self.specTabID);
			end
		end);
	end
	TabSystemOwnerMixin.SetTab(self, tabID);

	if tabID == self.glyphTabID then
		self.minimizeBeforeGlyphs = self.manualMinimizeEnabled;
		self.manualMinimizeEnabled = true;
	elseif self.minimizeBeforeGlyphs ~= nil then
		self.manualMinimizeEnabled = self.minimizeBeforeGlyphs;
		self.minimizeBeforeGlyphs = nil;
	end

	if tabID == self.glyphTabID then
		self:ShowGlyphs();
	end

	local canNewTabBeMinimized = self:DoesTabSupportMinimizedMode(tabID);
	local shouldBeMinimized = canNewTabBeMinimized and (tabID == self.glyphTabID or self:ShouldManuallyMinimize(tabID));

	if self.isMinimized and not shouldBeMinimized then
		self:ForceMaximize();
	elseif not self.isMinimized and shouldBeMinimized then
		self:SetMinimized(true);
	else
		self:SetTabMinimized(tabID, self.isMinimized);
	end

	-- на символах окно всегда свёрнуто, кнопка разворота не нужна
	self.MaximizeMinimizeButton:SetShown(canNewTabBeMinimized and tabID ~= self.glyphTabID);

	self:UpdateFrameTitle();
	EventRegistry:TriggerEvent("PlayerSpellsFrame.TabSet", PlayerSpellsFrame, tabID);

	return false;
end

-- Expects a PlayerSpellsUtil.FrameTabs value
function PlayerSpellsFrameMixin:IsFrameTabActive(frameTab)
	local tabID = self.frameTabsToTabID[frameTab];
	if not tabID then
		return false;
	end
	return self:GetTab() == tabID;
end

-- Expects a PlayerSpellsUtil.FrameTabs value
function PlayerSpellsFrameMixin:TrySetTab(frameTab)
	local tabID = self.frameTabsToTabID[frameTab];
	if not tabID then
		return false;
	end

	local isTabAvailable = self:IsTabAvailable(tabID);
	if isTabAvailable then
		self:SetTab(tabID);
	end

	return isTabAvailable;
end

function PlayerSpellsFrameMixin:IsTabAvailable(tabID)
	if tabID == self.talentTabID or tabID == self.specTabID then
		return UnitLevel("player") >= (SHOW_TALENT_LEVEL or 10);
	elseif tabID == self.glyphTabID then
		return UnitLevel("player") >= (SHOW_INSCRIPTION_LEVEL or 15);
	elseif tabID == self.spellBookTabID then
		return true;
	end
	return false;
end

function PlayerSpellsFrameMixin:ClearInspectUnit() end

function PlayerSpellsFrameMixin:IsInspecting()
	return (self.inspectUnit ~= nil) or (self.inspectString ~= nil);
end

function PlayerSpellsFrameMixin:GetInspectUnit()
	return self.inspectUnit;
end







function PlayerSpellsFrameMixin:UpdatePortrait()
	self:SetPortraitToSpecIcon();
end


function PlayerSpellsFrameMixin:IsMinimized()
	return self.isMinimized;
end

function PlayerSpellsFrameMixin:IsMinimizingEnabled()
	return self.isMinimizingEnabled;
end

-- Setting this to true means the next time the player spells frame is shown it will be automatically
-- minimized and then minimizedOnNextShow will be set back to false.
function PlayerSpellsFrameMixin:SetMinimizedOnNextShow(minimizedOnNextShow)
	self.minimizedOnNextShow = minimizedOnNextShow;
end

function PlayerSpellsFrameMixin:ShouldAutoMinimize()
	-- Has the player previously minimized the frame.
	if self:ShouldManuallyMinimize() then
		return true;
	end

	-- Has external code requested the frame be minimized next time its opened.
	return self:IsMinimizingEnabled() and self.minimizedOnNextShow;
end

function PlayerSpellsFrameMixin:ShouldManuallyMinimize(tabID)
	return self:IsMinimizingEnabled() and self.manualMinimizeEnabled and self:DoesTabSupportMinimizedMode(tabID or self:GetTab());
end

function PlayerSpellsFrameMixin:OnManualMinimizeClicked()
	self.manualMinimizeEnabled = true;
	if not self.isMinimized and self:ShouldManuallyMinimize() then
		self:SetMinimized(true);
		EventRegistry:TriggerEvent("PlayerSpellsFrame.OnManualMinimize");
	end
end

function PlayerSpellsFrameMixin:CanMaximize()
	return self:GetTab() ~= self.glyphTabID;
end

function PlayerSpellsFrameMixin:OnManualMaximizeClicked()
	if not self:CanMaximize() then
		return;
	end

	self.manualMinimizeEnabled = false;
	if self.isMinimized then
		self:ForceMaximize();
		EventRegistry:TriggerEvent("PlayerSpellsFrame.OnManualMaximize");
	end
end

function PlayerSpellsFrameMixin:DoesTabSupportMinimizedMode(tabID)
	-- Check should be updated if/when support for minimized mode is added to additional tabs
	return tabID == self.spellBookTabID or tabID == self.glyphTabID;
end

function PlayerSpellsFrameMixin:GetDefaultMinimizableTab()
	-- Logic should be updated if/when support for minimized mode is added to additional tabs
	return self.spellBookTabID;
end

function PlayerSpellsFrameMixin:SetMinimized(shouldBeMinimized)
	if self.isMinimized == shouldBeMinimized then
		return;
	end

	-- Changing the UI panel "area" attribute requires running through all the area evaluation
	-- logic within ShowUIPanel and the panel needs to be hidden before changing the attribute.
	-- But this only needs to happen if the player spells frame is currently shown.
	local wasShown = false;

	local currentTab = self:GetTab();
	if not self.isMinimized and shouldBeMinimized then

		self.isMinimized = true;
		if not self:DoesTabSupportMinimizedMode(currentTab) then
			local minimizableTabID = self:GetDefaultMinimizableTab();
			self:SetTab(minimizableTabID); -- SetTab will call SetTabMaximized
		else
			self:SetTabMinimized(currentTab, true);
		end

		self:SetWidth(self.minimizedWidth);

		-- Update minimize button to reflect current state, but ensure it doesn't circle back to the click callback
		-- This ensures that auto-minimizes are reflected by the button state, and the click callback only occurs on manual minimizes
		local isAutomaticAction, skipCallback = true, true;
		self.MaximizeMinimizeButton:Minimize(isAutomaticAction, skipCallback);

		-- When using center alignment (e.g. when no other panels are visible on the screen) the minimized version
		-- of the frame should be offset such that it would be left aligned with the maximized version of the frame.

	elseif self.isMinimized and not shouldBeMinimized then
		self.isMinimized = false;
		self:SetWidth(self.maximizedWidth);
		self:SetTabMinimized(currentTab, false);

		local isAutomaticAction, skipCallback = true, true;
		self.MaximizeMinimizeButton:Maximize(isAutomaticAction, skipCallback);

		-- The maximized version of the frame should always be center aligned on the screen.

	end

	-- If the panel was previously shown and then hidden to change the "area" attribute, show it again now.
	if wasShown then
		ShowUIPanel(self);
	end
	if self:GetTab() == self.glyphTabID then
		C_Timer.After(0, function() self:LayoutGlyphFrame(); end);
	end
end

function PlayerSpellsFrameMixin:SetTabMinimized(tabID, shouldBeMinimized)
	if not tabID or not self:DoesTabSupportMinimizedMode(tabID) then
		return;
	end

	local tabPage = self:GetElementsForTab(tabID)[1];
	if tabPage and tabPage.SetMinimized then
		tabPage:SetMinimized(shouldBeMinimized);
	end
end

function PlayerSpellsFrameMixin:ForceMaximize()
	if not self:CanMaximize() then
		return;
	end

	-- Close and re-show with minimize attributes temporarily disabled to ensure this frame stays maximized and other frames get closed
	self:SetMinimizingEnabled(false);
	self:SetMinimized(false);
	-- Now re-enable minimizing so that, if another frame gets opened later, we can be re-minimized and pop back to a supporting tab as usual
	self:SetMinimizingEnabled(true);
end

function PlayerSpellsFrameMixin:SetMinimizingEnabled(enabled)
	self.isMinimizingEnabled = enabled;


end

---------------------------------------------------------------------------
-- открытие
---------------------------------------------------------------------------
function PlayerSpellsFrame_ToggleTab(tabID)
	local frame = PlayerSpellsFrame;
	local shownTab = frame:GetTab();
	if frame:IsShown() and (shownTab == tabID or (tabID == frame.talentTabID and shownTab == frame.specTabID)) then
		HideUIPanel(frame);
		return false;
	end
	if not frame:IsTabAvailable(tabID) then
		return false;
	end
	ShowUIPanel(frame);
	frame:SetTab(tabID);
	return true;
end

function PlayerSpellsFrame_Toggle(bookType)
	local frame = PlayerSpellsFrame;
	if not PlayerSpellsFrame_ToggleTab(frame.spellBookTabID) then
		return;
	end
	if bookType == BOOKTYPE_PET then
		frame.SpellBookFrame:TrySetCategory(PlayerSpellsUtil.SpellBookCategories.Pet);
	end
end

function PlayerSpellsUtil.OpenToSpellBookTab()
	PlayerSpellsFrame_Toggle(BOOKTYPE_SPELL);
end

SLASH_RETAILSPELLBOOK1 = "/sb";
SlashCmdList.RETAILSPELLBOOK = function()
	PlayerSpellsFrame_Toggle(BOOKTYPE_SPELL);
end

USE_RETAIL_SPELLBOOK = USE_RETAIL_SPELLBOOK ~= false;
if USE_RETAIL_SPELLBOOK then
	ToggleSpellBook = function(bookType)
		PlayerSpellsFrame_Toggle(bookType);
	end;
end

PLAYER_SPELLS_FRAME_HEIGHT_PERCENT = 0.80;

function PlayerSpellsFrameMixin:UpdateScale()
	if PLAYER_SPELLS_FRAME_SCALE then
		self:SetScale(PLAYER_SPELLS_FRAME_SCALE);
		return;
	end
	local available = UIParent:GetHeight() * PLAYER_SPELLS_FRAME_HEIGHT_PERCENT;
	local scale = available / self:GetHeight();
	self:SetScale(math.max(0.4, math.min(scale, 1.2)));
end

local scaleWatcher = CreateFrame("Frame");
scaleWatcher:RegisterEvent("UI_SCALE_CHANGED");
scaleWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED");
scaleWatcher:RegisterEvent("PLAYER_ENTERING_WORLD");
scaleWatcher:SetScript("OnEvent", function()
	if PlayerSpellsFrame then
		PlayerSpellsFrame:UpdateScale();
	end
end);

---------------------------------------------------------------------------
-- Таланты и символы 3.3.5 внутри окна
---------------------------------------------------------------------------
local GLYPH_FRAME_HEIGHT = 512;

-- таланты/символы загружены в FrameXML — старые загрузчики аддонов не нужны
local origTalentLoad, origGlyphLoad = TalentFrame_LoadUI, GlyphFrame_LoadUI;
function TalentFrame_LoadUI()
	if not PlayerTalentFrame and origTalentLoad then
		origTalentLoad();
	end
end
function GlyphFrame_LoadUI()
	if not GlyphFrame and origGlyphLoad then
		origGlyphLoad();
	end
end

function PlayerSpellsFrameMixin:SetupEmbeddedTalents()
	if self.talentsEmbedded then
		return;
	end
	self.talentsEmbedded = true;

	-- новая панель: все ветки на одной вкладке
	local talents = PlayerSpellsTalentsFrame;
	if talents then
		talents:SetParent(self.TalentsContainer);
		talents:ClearAllPoints();
		talents:SetAllPoints(self.TalentsContainer);
		talents:SetFrameLevel(self.TalentsContainer:GetFrameLevel() + 1);
		talents:Show();
	end

	-- старое окно талантов больше не показываем
	if PlayerTalentFrame then
		UIPanelWindows["PlayerTalentFrame"] = nil;
		PlayerTalentFrame:HookScript("OnShow", function(frame)
			frame:Hide();
		end);
	end

end

function PlayerSpellsFrameMixin:ShowGlyphs()
	self:SetupEmbeddedTalents();
	if not GlyphFrame then
		return;
	end

	if PlayerTalentFrame then
		PlayerTalentFrame.pet = false;
		PlayerTalentFrame.talentGroup = GetActiveTalentGroup(false, false);
	end

	GlyphFrame:SetParent(self.GlyphContainer);
	GlyphFrame:SetFrameLevel(self.GlyphContainer:GetFrameLevel() + 1);
	GlyphFrame_Update();
	GlyphFrame:Show();

	C_Timer.After(0, function()
		self:LayoutGlyphFrame();
		GlyphFrame:Show();
	end);
end

function PlayerSpellsFrameMixin:LayoutGlyphFrame()
	if not GlyphFrame or not GlyphFrame:IsShown() then
		return;
	end

	local container = self.GlyphContainer;
	local height = container:GetHeight();
	local width = container:GetWidth();

	if not height or height < 100 then
		height = self:GetHeight() - 28;
	end
	if not width or width < 100 then
		width = self:GetWidth() - 8;
	end

	local scale = math.min((height - 20) / GLYPH_FRAME_HEIGHT, (width - 20) / 384);
	scale = math.max(0.6, math.min(scale, 2));

	if GlyphFrame:GetParent() ~= container then
		GlyphFrame:SetParent(container);
		GlyphFrame:SetFrameLevel(container:GetFrameLevel() + 1);
	end

	GlyphFrame:SetScale(scale);
	GlyphFrame:ClearAllPoints();
	GlyphFrame:SetPoint("CENTER", container, "CENTER", 0, 0);
end

-- клавиши N / символы и все старые вызовы
function PlayerTalentFrame_Toggle(pet, suggestedTalentGroup)
	local frame = PlayerSpellsFrame;
	if PlayerSpellsFrame_ToggleTab(frame.talentTabID) and PlayerSpellsTalentsFrame then
		PlayerSpellsTalentsFrame:SelectGroup(suggestedTalentGroup or GetActiveTalentGroup(false, pet), pet);
	end
end

function PlayerTalentFrame_Open(pet, talentGroup)
	local frame = PlayerSpellsFrame;
	if not (frame:IsShown() and frame:GetTab() == frame.talentTabID) then
		PlayerSpellsFrame_ToggleTab(frame.talentTabID);
	end
	if PlayerSpellsTalentsFrame then
		PlayerSpellsTalentsFrame:SelectGroup(talentGroup or 1, pet);
	end
end

function PlayerTalentFrame_OpenGlyphFrame(talentGroup)
	local frame = PlayerSpellsFrame;
	if not (frame:IsShown() and frame:GetTab() == frame.glyphTabID) then
		PlayerSpellsFrame_ToggleTab(frame.glyphTabID);
	end
end

function PlayerTalentFrame_ToggleGlyphFrame(suggestedTalentGroup)
	PlayerSpellsFrame_ToggleTab(PlayerSpellsFrame.glyphTabID);
end

function ToggleTalentFrame()
	if UnitLevel("player") < (SHOW_TALENT_LEVEL or 10) then
		return;
	end
	PlayerTalentFrame_Toggle(false, GetActiveTalentGroup());
end

function ToggleGlyphFrame()
	PlayerTalentFrame_ToggleGlyphFrame(GetActiveTalentGroup());
end
GlyphFrame_Toggle = ToggleGlyphFrame;

local talentInit = CreateFrame("Frame");
talentInit:RegisterEvent("PLAYER_LOGIN");
talentInit:SetScript("OnEvent", function()
	if PlayerSpellsFrame then
		PlayerSpellsFrame:SetupEmbeddedTalents();
	end
end);