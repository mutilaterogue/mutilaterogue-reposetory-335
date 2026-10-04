-- SharedUIPanelTemplates (Midnight) — подмножество, работающее в 3.3.5a
-- Порт: панели на NineSlice, ButtonFrameTemplate, MagicButton, перетаскивание за шапку.

PANEL_INSET_LEFT_OFFSET = 4;
PANEL_INSET_RIGHT_OFFSET = -6;
PANEL_INSET_BOTTOM_OFFSET = 4;
PANEL_INSET_BOTTOM_BUTTON_OFFSET = 26;
PANEL_INSET_TOP_OFFSET = -24;
PANEL_INSET_ATTIC_OFFSET = -60;

PANEL_BACKGROUND_COLOR = PANEL_BACKGROUND_COLOR or CreateColor(0.05, 0.05, 0.05, 0.94);

function MagicButton_OnLoad(self)
	for i = 1, self:GetNumPoints() do
		local point, relativeTo, relativePoint, offsetX, offsetY = self:GetPoint(i);
		if relativeTo and relativeTo.GetObjectType then
			local isButton = relativeTo:GetObjectType() == "Button";
			if isButton and (point == "TOPLEFT" or point == "LEFT") and offsetX == 0 and offsetY == 0 then
				self:SetPoint(point, relativeTo, relativePoint, 1, 0);
			elseif isButton and (point == "TOPRIGHT" or point == "RIGHT") and offsetX == 0 and offsetY == 0 then
				self:SetPoint(point, relativeTo, relativePoint, -1, 0);
			elseif point == "BOTTOMLEFT" and offsetX == 0 and offsetY == 0 then
				self:SetPoint(point, relativeTo, relativePoint, 4, 4);
			elseif point == "BOTTOMRIGHT" and offsetX == 0 and offsetY == 0 then
				self:SetPoint(point, relativeTo, relativePoint, -6, 4);
			elseif point == "BOTTOM" and offsetY == 0 then
				self:SetPoint(point, relativeTo, relativePoint, 0, 4);
			end
		end
	end
end

function FrameTemplate_SetAtticHeight(self, atticHeight)
	local inset = self.bottomInset or self.Inset;
	if inset then
		inset:SetPoint("TOPLEFT", self, "TOPLEFT", PANEL_INSET_LEFT_OFFSET, -atticHeight);
	end
end

function FrameTemplate_SetButtonBarHeight(self, buttonBarHeight)
	local inset = self.topInset or self.Inset;
	if inset then
		inset:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", PANEL_INSET_RIGHT_OFFSET, buttonBarHeight);
	end
end

function ButtonFrameTemplate_HideButtonBar(self)
	FrameTemplate_SetButtonBarHeight(self, PANEL_INSET_BOTTOM_OFFSET);
end

function ButtonFrameTemplate_ShowButtonBar(self)
	FrameTemplate_SetButtonBarHeight(self, PANEL_INSET_BOTTOM_BUTTON_OFFSET);
end

function ButtonFrameTemplate_HideAttic(self)
	FrameTemplate_SetAtticHeight(self, -PANEL_INSET_TOP_OFFSET);
	if self.TopTileStreaks then
		self.TopTileStreaks:Hide();
	end
end

function ButtonFrameTemplate_ShowAttic(self)
	FrameTemplate_SetAtticHeight(self, -PANEL_INSET_ATTIC_OFFSET);
	if self.TopTileStreaks then
		self.TopTileStreaks:Show();
	end
end

local function UpdateRegionAnchor(region, desiredOffsetX)
	if not region then
		return;
	end
	for i = 1, region:GetNumPoints() do
		local point, relativeTo, relativePoint, _, offsetY = region:GetPoint(i);
		if point == "TOPLEFT" then
			region:SetPoint(point, relativeTo, relativePoint, desiredOffsetX, offsetY);
			return;
		end
	end
end

local function UpdateAnchors(self, isPortraitMode)
	UpdateRegionAnchor(self.Bg, isPortraitMode and 2 or 7);
	UpdateRegionAnchor(self.Inset, isPortraitMode and 4 or 9);

	if self.TitleContainer then
		self.TitleContainer:SetPoint("TOPLEFT", self, "TOPLEFT", isPortraitMode and 58 or 0, -1);
		self.TitleContainer:SetPoint("TOPRIGHT", self, "TOPRIGHT", isPortraitMode and -24 or 0, -1);
	end
end

function ButtonFrameTemplate_HidePortrait(self)
	if self.SetBorder then
		self:SetBorder("ButtonFrameTemplateNoPortrait");
	end
	if self.SetPortraitShown then
		self:SetPortraitShown(false);
	end
	UpdateAnchors(self, false);
end

function ButtonFrameTemplate_ShowPortrait(self)
	if self.SetBorder then
		self:SetBorder("PortraitFrameTemplate");
	end
	if self.SetPortraitShown then
		self:SetPortraitShown(true);
	end
	UpdateAnchors(self, true);
end

-- панель без портрета
DefaultPanelMixin = {};

function DefaultPanelMixin:GetTitleText()
	return self.TitleContainer and self.TitleContainer.TitleText;
end

function DefaultPanelMixin:SetTitle(title)
	local text = self:GetTitleText();
	if text then
		text:SetText(title);
	end
end

function DefaultPanelMixin:SetTitleColor(color)
	local text = self:GetTitleText();
	if text and color then
		text:SetTextColor(color:GetRGBA());
	end
end

function DefaultPanelMixin:SetBorder(layoutName, textureKit)
	if self.NineSlice and NineSliceUtil then
		NineSliceUtil.ApplyLayoutByName(self.NineSlice, layoutName, textureKit);
	end
end

-- перетаскивание окна за шапку
PanelDragBarMixin = {};

function PanelDragBarMixin:OnLoad()
	self:RegisterForDrag("LeftButton");
	self:SetTarget(self:GetParent());
	self.suspendDrag = false;
end

function PanelDragBarMixin:SetDragSuspended(suspendDrag)
	self.suspendDrag = suspendDrag;
end

function PanelDragBarMixin:Init(target)
	self:SetTarget(target);
end

function PanelDragBarMixin:SetTarget(target)
	self.target = target;
	self.isMovingTarget = false;
end

function PanelDragBarMixin:OnDragStart()
	if self.suspendDrag or not self.target then
		return;
	end

	local continueDragStart = true;
	if self.target.onDragStartCallback then
		continueDragStart = self.target.onDragStartCallback(self);
	end
	if self.onDragStartCallback then
		continueDragStart = self.onDragStartCallback(self);
	end

	if continueDragStart then
		self.isMovingTarget = true;
		self.target:StartMoving();
	end
	self:UpdateCursor();
end

function PanelDragBarMixin:OnDragStop()
	if self.suspendDrag or not self.target then
		return;
	end

	local continueDragStop = true;
	if self.target.onDragStopCallback then
		continueDragStop = self.target.onDragStopCallback(self);
	end
	if self.onDragStopCallback then
		continueDragStop = self.onDragStopCallback(self);
	end

	if continueDragStop then
		self.isMovingTarget = false;
		self.target:StopMovingOrSizing();
	end
	self:UpdateCursor();
end

function PanelDragBarMixin:SetOnDragStartCallback(callback)
	self.onDragStartCallback = callback;
end

function PanelDragBarMixin:SetOnDragStopCallback(callback)
	self.onDragStopCallback = callback;
end

function PanelDragBarMixin:OnEnter()
	if self.showCursorOnHover then
		self:UpdateCursor();
	end
end

function PanelDragBarMixin:OnLeave()
	if self.showCursorOnHover then
		self:UpdateCursor();
	end
end

function PanelDragBarMixin:UpdateCursor()
	-- 3.3.5: SetCursor принимает только файлы, курсор перемещения пропускаем
end
