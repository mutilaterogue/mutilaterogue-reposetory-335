
TitledPanelMixin = {};

function TitledPanelMixin:GetTitleText()
	return self.TitleContainer.TitleText;
end

function TitledPanelMixin:SetTitleColor(color)
	self:GetTitleText():SetTextColor(color:GetRGBA());
end

function TitledPanelMixin:SetTitle(title)
	self:GetTitleText():SetText(title);
end

function TitledPanelMixin:SetTitleFormatted(fmt, ...)
	self:GetTitleText():SetFormattedText(fmt, ...);
end

function TitledPanelMixin:SetTitleMaxLinesAndHeight(maxLines, height)
	if self:GetTitleText().SetMaxLines then
		self:GetTitleText():SetMaxLines(maxLines);
	end
	self:GetTitleText():SetHeight(height);
end

function TitledPanelMixin:SetTitleOffsets(leftOffset, rightOffset)
	self.TitleContainer:SetPoint("TOPLEFT", self, "TOPLEFT", leftOffset or 58, -1);
	self.TitleContainer:SetPoint("TOPRIGHT", self, "TOPRIGHT", rightOffset or -24, -1);
end

DefaultPanelMixin = CreateFromMixins(TitledPanelMixin);

PortraitFrameMixin = CreateFromMixins(TitledPanelMixin);

function PortraitFrameMixin:GetPortrait()
	return self.PortraitContainer.portrait;
end

function PortraitFrameMixin:HasPortraitTexture()
	return self.PortraitContainer.portrait:GetTexture();
end

function PortraitFrameMixin:SetBorder(layoutName)
	local layout = NineSliceUtil.GetLayout(layoutName);
	NineSliceUtil.ApplyLayout(self.NineSlice, layout);
end

function PortraitFrameMixin:SetPortraitToAsset(texture)
	self:GetPortrait():SetTexCoord(0, 1, 0, 1);
	SetPortraitToTexture(self:GetPortrait(), texture);
end

function PortraitFrameMixin:SetPortraitToUnit(unit)
	SetPortraitTexture(self:GetPortrait(), unit);
end

function PortraitFrameMixin:SetPortraitToBag(bagID)
	SetBagPortraitTexture(self:GetPortrait(), bagID);
end

function PortraitFrameMixin:SetPortraitTextureRaw(texture)
	self:GetPortrait():SetTexture(texture);
end

function PortraitFrameMixin:SetPortraitAtlasRaw(atlas, ...)
	self:GetPortrait():SetAtlas(atlas, ...);
end

function PortraitFrameMixin:SetPortraitToClassIcon(classFilename)
	self:SetPortraitTextureRaw("Interface/TargetingFrame/UI-Classes-Circles");
	local left, right, bottom, top = unpack(CLASS_ICON_TCOORDS[string.upper(classFilename)]);
	self:SetPortraitTexCoord(left, right, bottom, top);
end

function PortraitFrameMixin:SetPortraitToSpecIcon()
	local group = GetActiveTalentGroup and GetActiveTalentGroup() or 1;
	local best, bestIcon = 0, nil;
	for tab = 1, GetNumTalentTabs() do
		local _, icon, points = GetTalentTabInfo(tab, false, false, group);
		if points and points > best then
			best, bestIcon = points, icon;
		end
	end
	if bestIcon then
		self:SetPortraitToAsset(bestIcon);
		return;
	end

	local fileName = select(2, UnitClass("player"));
	self:SetPortraitToClassIcon(fileName);
end

function PortraitFrameMixin:SetPortraitTexCoord(...)
	self:GetPortrait():SetTexCoord(...);
end

function PortraitFrameMixin:SetPortraitShown(shown)
	self:GetPortrait():SetShown(shown);
end

function PortraitFrameMixin:SetPortraitTextureSizeAndOffset(size, offsetX, offsetY)
	local portrait = self:GetPortrait();
	portrait:SetSize(size, size);
	portrait:SetPoint("TOPLEFT", self, "TOPLEFT", offsetX, offsetY);
end

do
	local function SetFrameLevelInternal(frame, level)
		if frame then
			frame:SetFrameLevel(level);
		end
	end

	function PortraitFrameMixin:SetFrameLevelsFromBaseLevel(baseLevel)
		SetFrameLevelInternal(self.NineSlice, baseLevel + 20);
		SetFrameLevelInternal(self.PortraitContainer, baseLevel + 19);
		SetFrameLevelInternal(self.TitleContainer, baseLevel + 21);
		SetFrameLevelInternal(self.CloseButton, baseLevel + 22);
	end
end

-- 3.3.5: keep the border parts above the content of any frame that inherits RetailPortraitFrameTemplate
function PortraitFrame_RaiseBorder(frame)
	if frame.SetFrameLevelsFromBaseLevel then
		frame:SetFrameLevelsFromBaseLevel(frame:GetFrameLevel());
	else
		PortraitFrameMixin.SetFrameLevelsFromBaseLevel(frame, frame:GetFrameLevel());
	end
end

PortraitFrameFlatBaseMixin = {};

function PortraitFrameFlatBaseMixin:SetBackgroundColor(color)
	if self.Bg then
		local bg = self.Bg;
		color = color or PANEL_BACKGROUND_COLOR;
		local r, g, b, a = color:GetRGBA();
		bg.BottomLeft:SetVertexColor(r, g, b, a);
		bg.BottomRight:SetVertexColor(r, g, b, a);
		if bg.BottomEdge then bg.BottomEdge:SetTexture(r, g, b, a); end
		if bg.TopSection then bg.TopSection:SetTexture(r, g, b, a); end
	end
end
