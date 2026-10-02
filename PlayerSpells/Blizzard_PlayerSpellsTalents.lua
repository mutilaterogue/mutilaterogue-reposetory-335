-- Таланты 3.3.5 в стиле Midnight: все три ветки на одной вкладке.
-- Раскладка каждой ветки — родной TalentFrame_Update из TalentFrameBase.lua.

TALENT_SPEC_PRIMARY = TALENT_SPEC_PRIMARY;
TALENT_SPEC_SECONDARY = TALENT_SPEC_SECONDARY;
TALENT_SPEC_ACTIVATE = TALENT_SPEC_ACTIVATE;
PET = PET;

local TALENT_EVENTS = {
	"PLAYER_TALENT_UPDATE",
	"PET_TALENT_UPDATE",
	"PREVIEW_TALENT_POINTS_CHANGED",
	"PREVIEW_PET_TALENT_POINTS_CHANGED",
	"ACTIVE_TALENT_GROUP_CHANGED",
	"CHARACTER_POINTS_CHANGED",
	"PLAYER_LEVEL_UP",
	"UNIT_PET",
	"CVAR_UPDATE",
};

PlayerSpellsTalentsMixin = {};

function PlayerSpellsTalentsMixin:OnLoad()
	self.playerTrees = { self.Tree1, self.Tree2, self.Tree3 };
	self.allTrees = { self.Tree1, self.Tree2, self.Tree3, self.PetTree };
	for _, tree in ipairs(self.allTrees) do
		TalentFrame_Load(tree);
		tree.inspect = false;
	end

	self.talentGroup = GetActiveTalentGroup(false, false) or 1;
	self.showPet = false;

	local bar = self.Bar;
	bar.Spec1Button:SetText(TALENT_SPEC_PRIMARY);
	bar.Spec2Button:SetText(TALENT_SPEC_SECONDARY);
	bar.PetButton:SetText(PET);
	bar.ActivateButton:SetText(TALENT_SPEC_ACTIVATE);
	bar.LearnButton:SetText(LEARN);
	bar.ResetButton:SetText(RESET);

	bar.Spec1Button:SetScript("OnClick", function() self:SelectGroup(1, false); end);
	bar.Spec2Button:SetScript("OnClick", function() self:SelectGroup(2, false); end);
	bar.PetButton:SetScript("OnClick", function() self:SelectGroup(1, not self.showPet); end);
	bar.ActivateButton:SetScript("OnClick", function()
		SetActiveTalentGroup(self.talentGroup);
	end);
	bar.LearnButton:SetScript("OnClick", function()
		if PlayerTalentFrame then
			PlayerTalentFrame.pet = self.showPet;
		end
		StaticPopup_Show("CONFIRM_LEARN_PREVIEW_TALENTS");
	end);
	bar.ResetButton:SetScript("OnClick", function()
		ResetGroupPreviewTalentPoints(self.showPet, self:GetGroup());
	end);
	PlayerSpellsLoadouts.SetupDropdown(self, bar.LoadoutDropdown);

	-- retail layout: class tree (left), hero tree (middle), one 3.3.5 tree (right)
	for _, tree in ipairs(self.playerTrees) do
		tree:ClearAllPoints();
		tree:SetPoint("TOPRIGHT", self, "TOPRIGHT", -30, -14);
	end
	self.treeTabs = {};
	for i = 1, 3 do
		local tab = CreateFrame("Button", nil, self, "UIPanelButtonTemplate");
		tab:SetSize(110, 22);
		tab:SetPoint("BOTTOMRIGHT", self.Tree1, "TOPRIGHT", -(3 - i) * 112, 2);
		tab:SetScript("OnClick", function() self.selectedTab = i; self:Refresh(); end);
		self.treeTabs[i] = tab;
	end
	PlayerSpellsCustomTalents.Setup(self);
end

-- default: the tree with the most points
local function MostSpentTab(group)
	local best, bestPoints = 1, -1;
	for i = 1, GetNumTalentTabs(false, false) or 0 do
		local _, _, points = GetTalentTabInfo(i, false, false, group);
		if (points or 0) > bestPoints then
			best, bestPoints = i, points or 0;
		end
	end
	return best;
end

function PlayerSpellsTalentsMixin:OnShow()
	for _, event in ipairs(TALENT_EVENTS) do
		self:RegisterEvent(event);
	end
	if not self.selectedByUser then
		self.talentGroup = GetActiveTalentGroup(false, false) or 1;
	end
	self:Refresh();
	PlayerSpellsLoadouts.Request();
	SetButtonPulse(TalentMicroButton, 0, 1);
end

function PlayerSpellsTalentsMixin:OnHide()
	self:UnregisterAllEvents();
	self.selectedByUser = nil;
end

function PlayerSpellsTalentsMixin:OnEvent(event, ...)
	if event == "UNIT_PET" then
		if ... ~= "player" then return; end
		if self.showPet and not self:HasPetTalents() then
			self.showPet = false;
		end
	elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
		self.talentGroup = GetActiveTalentGroup(false, false) or 1;
	end
	self:Refresh();
end

function PlayerSpellsTalentsMixin:HasPetTalents()
	return HasPetUI() and (GetNumTalentTabs(false, true) or 0) > 0;
end

function PlayerSpellsTalentsMixin:GetGroup()
	if self.showPet then
		return GetActiveTalentGroup(false, true) or 1;
	end
	return self.talentGroup;
end

function PlayerSpellsTalentsMixin:SelectGroup(group, pet)
	self.selectedByUser = true;
	self.talentGroup = group;
	self.showPet = pet and self:HasPetTalents() or false;
	self:Refresh();
end

local function RefreshTree(tree, tab, pet, group)
	tree.selectedTab = tab;
	tree.pet = pet;
	tree.talentGroup = group;

	local name, icon, pointsSpent, background, previewPointsSpent = GetTalentTabInfo(tab, false, pet, group);
	tree.pointsSpent = pointsSpent or 0;
	tree.previewPointsSpent = previewPointsSpent or 0;

	tree.Name:SetText(name or "");
	tree.Icon:SetTexture(icon);
	local total = tree.pointsSpent + (GetCVarBool("previewTalents") and tree.previewPointsSpent or 0);
	tree.Points:SetText(total);

	TalentFrame_Update(tree);
	tree:Show();
	PlayerSpellsTalentsDF.SkinTree(tree);
end

function PlayerSpellsTalentsMixin:Refresh()
	if not self:IsShown() then
		return;
	end

	local pet = self.showPet;
	local group = self:GetGroup();
	local active = GetActiveTalentGroup(false, pet);

	-- для GlyphUI и CONFIRM_LEARN_PREVIEW_TALENTS
	if PlayerTalentFrame then
		PlayerTalentFrame.pet = pet;
		PlayerTalentFrame.talentGroup = group;
	end

	if pet then
		for _, tree in ipairs(self.playerTrees) do
			tree:Hide();
		end
		RefreshTree(self.PetTree, 1, true, group);
	else
		self.PetTree:Hide();
		local numTabs = GetNumTalentTabs(false, false) or 0;
		self.selectedTab = self.selectedTab or MostSpentTab(group);
		for i, tab in ipairs(self.treeTabs) do
			local name = GetTalentTabInfo(i, false, false, group);
			tab:SetShown(i <= numTabs);
			tab:SetText(name or "");
			tab:SetEnabled(i ~= self.selectedTab);
		end
		for i, tree in ipairs(self.playerTrees) do
			if i <= numTabs and i == self.selectedTab then
				RefreshTree(tree, i, false, group);
			else
				tree:Hide();
			end
		end
	end

	for _, tab in ipairs(self.treeTabs) do
		if pet then tab:Hide(); end
	end
	PlayerSpellsCustomTalents.Refresh(self);

	local bar = self.Bar;
	local unspent = GetUnspentTalentPoints(false, pet, group) - GetGroupPreviewTalentPointsSpent(pet, group);
	bar.PointsText:SetFormattedText(UNSPENT_TALENT_POINTS, HIGHLIGHT_FONT_COLOR_CODE .. unspent .. FONT_COLOR_CODE_CLOSE);

	local numGroups = GetNumTalentGroups(false, false) or 1;
	bar.Spec1Button:SetShown(numGroups > 1 or pet);
	bar.Spec2Button:SetShown(numGroups > 1);
	bar.Spec1Button:SetEnabled(pet or group ~= 1);
	bar.Spec2Button:SetEnabled(pet or group ~= 2);
	bar.PetButton:SetShown(self:HasPetTalents());
	bar.PetButton:SetEnabled(not pet);
	bar.ActivateButton:SetShown(not pet and group ~= active);

	-- подсказка под курсором должна показывать новый ранг
	local owner = GameTooltip:GetOwner();
	if owner and owner.tree and owner:IsShown() then
		PlayerSpellsTalentButton_OnEnter(owner);
	end

	local preview = GetCVarBool("previewTalents");
	local previewSpent = GetGroupPreviewTalentPointsSpent(pet, group) or 0;
	local canEdit = group == active;
	bar.LearnButton:SetShown(preview and canEdit);
	bar.ResetButton:SetShown(preview and canEdit);
	bar.LearnButton:SetEnabled(previewSpent > 0);
	bar.ResetButton:SetEnabled(previewSpent > 0);
	PlayerSpellsLoadouts.UpdateDropdown(self);
end

---------------------------------------------------------------------------
-- кнопки талантов
---------------------------------------------------------------------------
local function GetTree(button)
	return button.tree;
end

function PlayerSpellsTalentButton_OnLoad(self)
	self:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	-- кнопка → ScrollChildFrame → дерево
	self.tree = self:GetParent():GetParent();
end

function PlayerSpellsTalentButton_OnClick(self, button)
	local tree = GetTree(self);
	local tab, id, pet, group = tree.selectedTab, self:GetID(), tree.pet, tree.talentGroup;

	if IsModifiedClick("CHATLINK") then
		local link = GetTalentLink(tab, id, false, pet, group, GetCVarBool("previewTalents"));
		if link then
			ChatEdit_InsertLink(link);
		end
		return;
	end

	if group ~= GetActiveTalentGroup(false, pet) then
		return;
	end

	if GetCVarBool("previewTalents") then
		AddPreviewTalentPoints(tab, id, button == "RightButton" and -1 or 1, pet, group);
	elseif button == "LeftButton" then
		LearnTalent(tab, id, pet, group);
	end
end

function PlayerSpellsTalentButton_OnEnter(self)
	local tree = GetTree(self);
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetTalent(tree.selectedTab, self:GetID(), false, tree.pet, tree.talentGroup, GetCVarBool("previewTalents"));
end