-- Окно разбивки по заклинаниям выбранного участника.

DamageMeterSourceWindowMixin = {};

function DamageMeterSourceWindowMixin:OnLoad()
	self.entries = {};

	self:RegisterForDrag("LeftButton");

	self.ScrollBar:SetPoint("TOPLEFT", self.ScrollBox, "TOPRIGHT", 2, 0);
	self.ScrollBar:SetPoint("BOTTOMLEFT", self.ScrollBox, "BOTTOMRIGHT", 2, 0);

	local view = CreateScrollBoxListLinearView();
	view:SetElementExtent(DamageMeterSessionWindow and DamageMeterSessionWindow:GetBarHeight() or DAMAGE_METER_DEFAULT_BAR_HEIGHT);
	view:SetPadding(0, 0, 0, 0, DAMAGE_METER_DEFAULT_BAR_SPACING);
	view:SetElementInitializer("DamageMeterEntryTemplate", function(frame, index)
		frame:Init(self.entries[index]);
	end);
	ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view);
end

-- окно встаёт с той стороны, где больше места
function DamageMeterSourceWindowMixin:AnchorToSessionWindow()
	local sessionWindow = DamageMeterSessionWindow;
	local centerX = sessionWindow:GetCenter();
	local screenCenterX = UIParent:GetCenter();

	self:ClearAllPoints();
	self:SetHeight(sessionWindow:GetHeight());

	if centerX and screenCenterX and centerX < screenCenterX then
		self:SetPoint("TOPLEFT", sessionWindow, "TOPRIGHT", 4, 0);
	else
		self:SetPoint("TOPRIGHT", sessionWindow, "TOPLEFT", -4, 0);
	end
end

function DamageMeterSourceWindowMixin:SetSource(source)
	self.sourceGUID = source.sourceGUID;
	self.sourceCreatureID = source.sourceCreatureID;
	self.sourceName = source.name;
	self.sourceIndex = source.index;
	self.classFilename = source.classFilename;
end

function DamageMeterSourceWindowMixin:ClearSource()
	self.sourceGUID, self.sourceCreatureID, self.sourceName, self.classFilename = nil, nil, nil, nil;
end

function DamageMeterSourceWindowMixin:OnShow()
	self:AnchorToSessionWindow();
	self:Refresh();
end

function DamageMeterSourceWindowMixin:OnHide()
	self:ClearSource();
end

function DamageMeterSourceWindowMixin:Refresh()
	-- OnLoad by method="..." may not have run: set the list up now
	if not self.entries then
		self:OnLoad();
	end
	if not self.sourceGUID and not self.sourceCreatureID then
		return;
	end

	local info = C_DamageMeter.GetCombatSessionSourceFromType(DamageMeterSessionWindow:GetSessionType(),
		DamageMeterSessionWindow:GetDamageMeterType(), self.sourceGUID, self.sourceCreatureID);

	self.entries = info and info.combatSpells or {};

	for index, spell in ipairs(self.entries) do
		spell.index = index;
		spell.maxAmount = info.maxAmount;
		spell.showsValuePerSecondAsPrimary = info.showsValuePerSecondAsPrimary;
	end

	self.ScrollBox:SetDataProvider(CreateIndexRangeDataProvider(#self.entries));
	self.Title:SetText(format(DAMAGE_METER_SOURCE_NAME or "%d. %s", self.sourceIndex or 1, self.sourceName or UNKNOWN));
end
