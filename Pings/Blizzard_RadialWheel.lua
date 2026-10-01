-- retail Blizzard_RadialWheel (RadialWheelFrameMixin / RadialWheelButtonMixin) for 3.3.5.
-- 3.3.5: no Texture:SetRotation / SetScale, no alpha AnimationGroups, no CreateFramePool, no Cooldown swipe atlases:
--   rotation - RadialWheel_SetRotatedAtlas (texcoords of the atlas region turned around its center),
--   scale - the atlas size, intro / outro - OnUpdate; the cooldown ring is not used (pings have no shared cooldown).

local RADIAL_FORMAT_SMALL = "%s_Small";
local RADIAL_FORMAT_DISABLED = "%s_Disabled";
local RADIAL_FORMAT_COOLDOWN = "%s_CoolDown";
local RADIAL_FORMAT_COUNT = "%s_Count_%d";
local RADIAL_FORMAT_GLOW = "%s_Glow";
local TWO_PI = 2 * math.pi;
local INTRO_TIME, OUTRO_TIME = 0.2, 0.13;

local function FormatStringForSize(string, isSmall)
	return isSmall and RADIAL_FORMAT_SMALL:format(string) or string;
end

local function InOutCubic(t)
	if t < 0.5 then
		return 4 * t * t * t;
	end
	local f = 2 * t - 2;
	return 0.5 * f * f * f + 1;
end

-- the atlas turned by angle (radians, counter-clockwise) around its center, the size of the atlas
function RadialWheel_SetRotatedAtlas(texture, atlas, angle)
	local info = C_Texture.GetAtlasInfo(atlas);
	if not info then
		texture:SetAtlas(atlas, true);
		return;
	end
	texture:SetTexture(info.file or info.filename);
	texture:SetWidth(info.width);
	texture:SetHeight(info.height);
	-- this client's GetAtlasInfo: left / right / top / bottom (retail: leftTexCoord ...)
	local left, right = info.left or info.leftTexCoord, info.right or info.rightTexCoord;
	local top, bottom = info.top or info.topTexCoord, info.bottom or info.bottomTexCoord;
	local cu, cv = (left + right) / 2, (top + bottom) / 2;
	local du, dv = (right - left) / 2, (bottom - top) / 2;
	-- corner of the quad (x, y in -1..1, y up) -> the texture point it shows: the corner turned by -angle
	local c, s = math.cos(angle), math.sin(angle);
	local function Corner(x, y)
		local rx = x * c + y * s;
		local ry = -x * s + y * c;
		return cu + rx * du, cv - ry * dv;
	end
	local ulx, uly = Corner(-1, 1);
	local llx, lly = Corner(-1, -1);
	local urx, ury = Corner(1, 1);
	local lrx, lry = Corner(1, -1);
	texture:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry);
end

-- retail SetAtlas quietly ignores a missing atlas (e.g. Radial_Wheel_Icon_Close_Glow), the 3.3.5 one raises an error
local function SetAtlasSized(texture, atlas, scale)
	local info = C_Texture.GetAtlasInfo(atlas);
	if not info then
		texture:SetTexture(nil);
		return;
	end
	texture:SetAtlas(atlas, true);
	if scale then
		texture:SetWidth(info.width * scale);
		texture:SetHeight(info.height * scale);
	end
end

-- fades of a list of regions (retail IntroAnim / OutroAnim)
local function StartFade(owner, regions, from, to, duration, onDone)
	owner.fade = { regions = regions, from = from, to = to, start = GetTime(), duration = duration, onDone = onDone };
	for _, region in ipairs(regions) do
		region:SetAlpha(from);
	end
end

local function UpdateFade(owner)
	local fade = owner.fade;
	if not fade then
		return;
	end
	local t = math.min(1, (GetTime() - fade.start) / fade.duration);
	for _, region in ipairs(fade.regions) do
		region:SetAlpha(fade.from + (fade.to - fade.from) * t);
	end
	if t >= 1 then
		owner.fade = nil;
		if fade.onDone then
			fade.onDone();
		end
	end
end

---------------------------------------------------------------------------
-- RadialWheelFrameMixin
---------------------------------------------------------------------------
RadialWheelFrameMixin = {
	MinimumWedgeDistanceSquared = 500;
	MinimumWedgeDistanceSquaredSmall = 150;
};

function RadialWheelFrameMixin:OnLoad()
	self.wedgeAngleOffsetInitial = (.5 * math.pi);	-- a wedge on top of the wheel
	self.wedgePool = {};
	self.radialParent = self;
	Mixin(self.CancelButton, RadialWheelButtonMixin);
	self.CancelButton:OnLoad();
	self.CancelButton.ignoreScaleChangesOnSelect = true;
	self.CancelButton.enabledOverride = true;
end

function RadialWheelFrameMixin:OnUpdate()
	UpdateFade(self);
	if not self.isWheelClosing then
		self:UpdateSelection();
	end
end

local function GetScaledCursorPosition()
	local x, y = GetCursorPosition();
	local scale = UIParent:GetEffectiveScale();
	return x / scale, y / scale;
end

function RadialWheelFrameMixin:UpdateSelection(forceUpdate)
	local x, y = GetScaledCursorPosition();
	if not forceUpdate and x == self.lastX and y == self.lastY then
		return;
	end
	self.lastX, self.lastY = x, y;

	local centerX, centerY = self.radialParent:GetCenter();
	local scale = self.radialParent:GetEffectiveScale() / UIParent:GetEffectiveScale();
	centerX, centerY = centerX * scale, centerY * scale;

	-- minimum distance for a selection: the middle (cancel) button
	local dx, dy = x - centerX, y - centerY;
	local distance = dx * dx + dy * dy;
	local minDistance = self.isSmall and self.MinimumWedgeDistanceSquaredSmall or self.MinimumWedgeDistanceSquared;
	if distance <= minDistance then
		if self.currentSelected then
			self.currentSelected:SetSelected(false);
		end
		self.currentSelected = self.CancelButton;
		self.CancelButton:SetSelected(true);
		self.Pointer:Hide();
		return;
	end

	self.CancelButton:SetSelected(false);

	local angle = math.atan2(dy, dx);
	if angle < 0 then
		angle = angle + TWO_PI;
	end

	self.Pointer:Show();
	RadialWheel_SetRotatedAtlas(self.Pointer, FormatStringForSize("Radial_Wheel_Select_Pointer", self.isSmall), angle);

	angle = angle - self.wedgeAngleOffsetInitial + self.wedgeAngleIntervalRadiansHalf;
	if angle < 0 then
		angle = angle + TWO_PI;
	end

	local targetWedgeIndex = 1;
	while angle >= self.wedgeAngleIntervalRadians do
		targetWedgeIndex = targetWedgeIndex + 1;
		angle = angle - self.wedgeAngleIntervalRadians;
	end

	local targetWedge = self.radialWheelWedgeButtons[targetWedgeIndex];
	if targetWedge and targetWedge ~= self.currentSelected then
		if self.currentSelected then
			self.currentSelected:SetSelected(false);
		end
		self.currentSelected = targetWedge;
		self.currentSelected:SetSelected(true);
	end
end

function RadialWheelFrameMixin:SelectionStart(wedges, isSmall)
	self.isSmall = isSmall;
	self.numWedges = #wedges;

	if self.currentSelected then
		self.currentSelected:SetSelected(false);
	end
	self.currentSelected = nil;
	self.wedgeAngleIntervalRadians = TWO_PI / #wedges;
	self.wedgeAngleIntervalRadiansHalf = self.wedgeAngleIntervalRadians * .5;
	self.lastX, self.lastY = nil, nil;

	self:UpdateFrameTexture();
	self.Background:SetAtlas(FormatStringForSize("Radial_Wheel_BG", self.isSmall), true);
	self.Pointer:Hide();

	self.CancelButton.SelectedTexture:SetAtlas(FormatStringForSize("Radial_Wheel_Select_Close", self.isSmall), true);
	self.CancelButton.iconAtlasName = "Radial_Wheel_Icon_Close";
	self.CancelButton:SetIsSmall(self.isSmall);
	self.CancelButton.Text:SetText(nil);
	self.CancelButton:AnimateIntro();

	self:SetupRadialWedgeButtons(wedges);
	StartFade(self, { self.Background, self.Frame, self.Pointer }, 0, 1, INTRO_TIME);
	self:Show();

	self:SetScript("OnUpdate", self.OnUpdate);
end

function RadialWheelFrameMixin:SelectionEnd()
	if self.currentSelected and self.currentSelected ~= self.CancelButton then
		return self.currentSelected;
	end
	return nil;
end

function RadialWheelFrameMixin:AnimateOutro()
	self.isWheelClosing = true;
	self.lastX, self.lastY = nil, nil;
	self.Pointer:Hide();

	StartFade(self, { self.Background, self.Frame }, 1, 0, OUTRO_TIME, function()
		self:SetScript("OnUpdate", nil);
		self:Hide();
	end);
	self.CancelButton:SetSelected(false);
	self.CancelButton:AnimateOutro();

	for _, wedgeFrame in ipairs(self.radialWheelWedgeButtons) do
		wedgeFrame:SetSelected(false);
		wedgeFrame:AnimateOutro();
	end
end

function RadialWheelFrameMixin:AcquireWedge(index)
	local wedge = self.wedgePool[index];
	if not wedge then
		wedge = CreateFrame("Frame", nil, self, "RadialWheelWedgeButtonTemplate");
		Mixin(wedge, RadialWheelButtonMixin);
		wedge:OnLoad();
		self.wedgePool[index] = wedge;
	end
	return wedge;
end

function RadialWheelFrameMixin:SetupRadialWedgeButtons(wedges)
	self.isWheelClosing = false;

	for _, wedge in ipairs(self.wedgePool) do
		wedge:Hide();
	end
	self.radialWheelWedgeButtons = {};
	local angle = self.wedgeAngleOffsetInitial;
	local selectedTexture = ("Radial_Wheel_Select_Wedge_Count_%d"):format(self.numWedges);

	-- distances out from the center
	local wedgeSpacing = self.isSmall and 40 or 80;
	local wedgeSelectedSpacing = self.isSmall and 10 or 20;
	for i = 1, #wedges do
		local wedgeFrame = self:AcquireWedge(i);
		local wedgeInfo = wedges[i];

		wedgeFrame.type = wedgeInfo.type;
		wedgeFrame:ClearAllPoints();
		wedgeFrame:SetPoint("CENTER", self, "CENTER", math.cos(angle) * wedgeSpacing, math.sin(angle) * wedgeSpacing);

		RadialWheel_SetRotatedAtlas(wedgeFrame.SelectedTexture, FormatStringForSize(selectedTexture, self.isSmall), angle);
		wedgeFrame.SelectedTexture:ClearAllPoints();
		wedgeFrame.SelectedTexture:SetPoint("CENTER", wedgeFrame, "CENTER", math.cos(angle) * wedgeSelectedSpacing, math.sin(angle) * wedgeSelectedSpacing);

		wedgeFrame.angle = angle;
		wedgeFrame:SetEnabled(true);
		wedgeFrame:SetIsSmall(self.isSmall);
		wedgeFrame:SetIcon(wedgeInfo.icon);
		wedgeFrame:SetText(wedgeInfo.text);
		wedgeFrame:SetSelected(false);

		-- text on the outside of the wedge
		local quarterPi = .25 * math.pi;
		wedgeFrame.Text:ClearAllPoints();
		if (angle > quarterPi) and (angle <= math.pi - quarterPi) then
			wedgeFrame.Text:SetPoint("BOTTOM", wedgeFrame.Icon, "TOP", 0, 10);
		elseif (angle > math.pi - quarterPi) and (angle <= math.pi + quarterPi) then
			wedgeFrame.Text:SetPoint("RIGHT", wedgeFrame.Icon, "LEFT");
		elseif (angle > math.pi + quarterPi) and (angle <= TWO_PI - quarterPi) then
			wedgeFrame.Text:SetPoint("TOP", wedgeFrame.Icon, "BOTTOM", 0, -10);
		else
			wedgeFrame.Text:SetPoint("LEFT", wedgeFrame.Icon, "RIGHT");
		end

		self.radialWheelWedgeButtons[i] = wedgeFrame;
		wedgeFrame:Show();
		wedgeFrame:AnimateIntro();

		angle = angle + self.wedgeAngleIntervalRadians;
	end
end

function RadialWheelFrameMixin:IsOnCooldown()
	return false;
end

function RadialWheelFrameMixin:UpdateFrameTexture()
	local frameAtlasName = RADIAL_FORMAT_COUNT:format("Radial_Wheel_Frame", self.numWedges);
	frameAtlasName = FormatStringForSize(frameAtlasName, self.isSmall);
	self.Frame:SetAtlas(frameAtlasName, true);
end

---------------------------------------------------------------------------
-- RadialWheelButtonMixin
---------------------------------------------------------------------------
RadialWheelButtonMixin = {};

local buttonAnimValues = {
	Intro = { duration = INTRO_TIME, distanceLarge = -20, distanceSmall = -10 },
	Outro = { duration = OUTRO_TIME, distanceLarge = -20, distanceSmall = -10 },
};

function RadialWheelButtonMixin:OnLoad()
	self.angle = self.angle or 0;
	self:SetScript("OnHide", function() self:CleanupAnimations(); end);
end

function RadialWheelButtonMixin:OnUpdate()
	UpdateFade(self);
	if not self.animStartTime then
		return;
	end
	local percent = math.min(1, math.max(0, (GetTime() - self.animStartTime) / (self.animEndTime - self.animStartTime)));
	local eased = InOutCubic(percent);
	self:SetIconOffset(self.animStartX + (self.animEndX - self.animStartX) * eased, self.animStartY + (self.animEndY - self.animStartY) * eased);
	if percent >= 1 then
		self.animStartTime = nil;
		self:SetIconOffset(0, 0);
	end
end

function RadialWheelButtonMixin:SetIconOffset(x, y)
	self.Icon:ClearAllPoints();
	self.Icon:SetPoint("CENTER", self, "CENTER", x, y);
	self.IconGlow:ClearAllPoints();
	self.IconGlow:SetPoint("CENTER", self.Icon, "CENTER");
end

function RadialWheelButtonMixin:SetupForAnimation(key, isAnimatingOutward)
	local values = buttonAnimValues[key];
	local distance = self.isSmall and values.distanceSmall or values.distanceLarge;
	local ax, ay = math.cos(self.angle or 0) * distance, math.sin(self.angle or 0) * distance;
	if isAnimatingOutward then
		self.animStartX, self.animStartY, self.animEndX, self.animEndY = ax, ay, 0, 0;
	else
		self.animStartX, self.animStartY, self.animEndX, self.animEndY = 0, 0, ax, ay;
	end
	self.animStartTime = GetTime();
	self.animEndTime = self.animStartTime + values.duration;
	self:SetScript("OnUpdate", self.OnUpdate);
end

function RadialWheelButtonMixin:AnimateIntro()
	self:CleanupAnimations();
	self:SetupForAnimation("Intro", true);
	StartFade(self, { self.SelectedTexture, self.Icon, self.Text }, 0, 1, INTRO_TIME);
end

function RadialWheelButtonMixin:AnimateOutro()
	self:CleanupAnimations();
	self:SetupForAnimation("Outro", false);
	StartFade(self, { self.Icon, self.Text }, 1, 0, OUTRO_TIME);
end

function RadialWheelButtonMixin:CleanupAnimations()
	self.fade = nil;
	self.animStartTime = nil;
	self.IconGlow:Hide();
	self:SetIconOffset(0, 0);
end

function RadialWheelButtonMixin:SetSelected(state)
	self.isSelected = state;
	self:UpdateSelectedState();
end

function RadialWheelButtonMixin:UpdateSelectedState()
	local isSelectedAndEnabled = self.isSelected and self:GetEnabled();
	if isSelectedAndEnabled then
		self.SelectedTexture:Show();
	else
		self.SelectedTexture:Hide();
	end
	if not self.ignoreScaleChangesOnSelect then
		self.iconScale = isSelectedAndEnabled and 1 or 0.9;
		self:UpdateIcon();
		local font, size = self.Text:GetFont();
		if font then
			self.baseFontSize = self.baseFontSize or size;
			self.Text:SetFont(font, self.baseFontSize * self.iconScale);
		end
	end
end

function RadialWheelButtonMixin:SetEnabled(enabled)
	self.enabled = enabled;
	self:UpdateSelectedState();
	self:UpdateIcon();
	self:UpdateTextShownState();
end

function RadialWheelButtonMixin:GetEnabled()
	if self.enabledOverride ~= nil then
		return self.enabledOverride;
	end
	return self.enabled;
end

function RadialWheelButtonMixin:SetIsSmall(isSmall)
	self.isSmall = isSmall;
	self:UpdateIcon();
	self:UpdateTextShownState();
end

function RadialWheelButtonMixin:SetIcon(iconAtlasName)
	self.iconAtlasName = iconAtlasName;
	self:UpdateIcon();
end

function RadialWheelButtonMixin:UpdateIcon()
	if not self.iconAtlasName then
		return;
	end
	local name = self:GetEnabled() and self.iconAtlasName or RADIAL_FORMAT_DISABLED:format(self.iconAtlasName);
	SetAtlasSized(self.Icon, FormatStringForSize(name, self.isSmall), self.iconScale or 1);
	SetAtlasSized(self.IconGlow, FormatStringForSize(RADIAL_FORMAT_GLOW:format(self.iconAtlasName), self.isSmall), self.iconScale or 1);
end

function RadialWheelButtonMixin:SetText(text)
	self.Text:SetText(text);
end

function RadialWheelButtonMixin:UpdateTextShownState()
	if not self.isSmall and self:GetEnabled() then
		self.Text:Show();
	else
		self.Text:Hide();
	end
end
