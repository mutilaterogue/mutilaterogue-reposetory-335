-- ThreeSliceButtonTemplate (ретейл) для 3.3.5a.
-- Отличия от ретейла:
--  * у текстур в 3.3.5 нет SetScale - левая/правая части масштабируются через SetSize;
--  * SetTexCoord в 3.3.5 работает по всему файлу, а не по атласу - обрезка считается по координатам атласа;
--  * нет SetHighlightAtlas - подсветка отдельной текстурой HIGHLIGHT;
--  * нет relativeKey в XML - центральная часть привязывается в Lua;
--  * нет UIButtonMixin - подсказка (tooltip) сделана здесь же.

ThreeSliceButtonMixin = {};

function ThreeSliceButtonMixin:GetLeftAtlasName()
	return self.atlasName.."-Left";
end

function ThreeSliceButtonMixin:GetRightAtlasName()
	return self.atlasName.."-Right";
end

function ThreeSliceButtonMixin:GetCenterAtlasName()
	return "_"..self.atlasName.."-Center";
end

function ThreeSliceButtonMixin:GetHighlightAtlasName()
	return self.atlasName.."-Highlight";
end

local function GetAtlasCoords(info)
	return info.leftTexCoord or info.left, info.rightTexCoord or info.right,
		info.topTexCoord or info.top, info.bottomTexCoord or info.bottom;
end

function ThreeSliceButtonMixin:OnLoad()
	self.atlasName = self.atlasName or "128-RedButton";

	self.Center:ClearAllPoints();
	self.Center:SetPoint("TOPLEFT", self.Left, "TOPRIGHT");
	self.Center:SetPoint("BOTTOMRIGHT", self.Right, "BOTTOMLEFT");

	self:InitButton();
	self:UpdateButton();
end

function ThreeSliceButtonMixin:InitButton()
	-- Controller (ButtonControllerMixin) зовёт это раньше OnLoad кнопки
	self.atlasName = self.atlasName or "128-RedButton";
	self.leftAtlasInfo = C_Texture.GetAtlasInfo(self:GetLeftAtlasName());
	self.rightAtlasInfo = C_Texture.GetAtlasInfo(self:GetRightAtlasName());

	if not self.HighlightTex then
		self.HighlightTex = self:CreateTexture(nil, "HIGHLIGHT");
		self.HighlightTex:SetAllPoints();
		self.HighlightTex:SetBlendMode("ADD");
	end
	self.HighlightTex:SetAtlas(self:GetHighlightAtlasName());
end

-- обрезать часть атласа по горизонтали: fromLeft - оставить левую долю, иначе правую
local function CropAtlas(texture, atlasName, percentage, fromLeft)
	local info = C_Texture.GetAtlasInfo(atlasName);
	if not info then
		return;
	end
	local left, right, top, bottom = GetAtlasCoords(info);
	if not (left and right and top and bottom) then
		return;
	end
	local width = right - left;
	if fromLeft then
		texture:SetTexCoord(left, left + width * percentage, top, bottom);
	else
		texture:SetTexCoord(right - width * percentage, right, top, bottom);
	end
end

function ThreeSliceButtonMixin:UpdateScale()
	if not self.leftAtlasInfo or not self.rightAtlasInfo then
		return;
	end

	local buttonHeight = self:GetHeight();
	local buttonWidth = self:GetWidth();
	if buttonHeight <= 0 or buttonWidth <= 0 then
		return;
	end
	local scale = buttonHeight / self.leftAtlasInfo.height;

	local leftWidth = self.leftAtlasInfo.width * scale;
	local rightWidth = self.rightAtlasInfo.width * scale;
	local leftAndRightWidth = leftWidth + rightWidth;

	local newLeftWidth, newRightWidth = leftWidth, rightWidth;
	if leftAndRightWidth > buttonWidth then
		-- At the current buttonHeight, the left and right textures are too big to fit within the button width
		-- So slice some width off of the textures and adjust texture coords accordingly
		local extraWidth = leftAndRightWidth - buttonWidth;

		if (leftWidth - extraWidth) > rightWidth then
			newLeftWidth = leftWidth - extraWidth;
		elseif (rightWidth - extraWidth) > leftWidth then
			newRightWidth = rightWidth - extraWidth;
		else
			if leftWidth ~= rightWidth then
				local unevenAmount = math.abs(leftWidth - rightWidth);
				extraWidth = extraWidth - unevenAmount;
				newLeftWidth = math.min(leftWidth, rightWidth);
				newRightWidth = newLeftWidth;
			end
			local equallyDividedExtraWidth = extraWidth / 2;
			newLeftWidth = newLeftWidth - equallyDividedExtraWidth;
			newRightWidth = newRightWidth - equallyDividedExtraWidth;
		end
	end

	-- 3.3.5: вместо SetScale - размер текстуры сразу в пикселях кнопки
	CropAtlas(self.Left, self.currentLeftAtlas or self:GetLeftAtlasName(), newLeftWidth / leftWidth, true);
	self.Left:SetSize(newLeftWidth, buttonHeight);
	CropAtlas(self.Right, self.currentRightAtlas or self:GetRightAtlasName(), newRightWidth / rightWidth, false);
	self.Right:SetSize(newRightWidth, buttonHeight);
end

function ThreeSliceButtonMixin:UpdateButton(buttonState)
	if not self.leftAtlasInfo then
		self:InitButton();
	end
	buttonState = buttonState or self:GetButtonState();

	if not self:IsEnabled() then
		buttonState = "DISABLED";
	end

	local atlasNamePostfix = "";
	if buttonState == "DISABLED" then
		atlasNamePostfix = "-Disabled";
	elseif buttonState == "PUSHED" then
		atlasNamePostfix = "-Pressed";
	end

	self.currentLeftAtlas = self:GetLeftAtlasName()..atlasNamePostfix;
	self.currentRightAtlas = self:GetRightAtlasName()..atlasNamePostfix;
	self.Left:SetAtlas(self.currentLeftAtlas);
	self.Center:SetAtlas(self:GetCenterAtlasName()..atlasNamePostfix);
	self.Right:SetAtlas(self.currentRightAtlas);

	self:UpdateScale();
end

function ThreeSliceButtonMixin:OnMouseDown()
	if self:IsEnabled() then
		self:UpdateButton("PUSHED");
	end
end

function ThreeSliceButtonMixin:OnMouseUp()
	self:UpdateButton("NORMAL");
end

-- UIButtonMixin (ретейл): tooltip - строка или функция
function ThreeSliceButtonMixin:OnEnter()
	local tooltip = self.tooltip;
	if type(tooltip) == "function" then
		tooltip = tooltip(self);
	end
	if tooltip then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(tooltip, 1, 1, 1, 1, true);
		GameTooltip:Show();
	end
end

function ThreeSliceButtonMixin:OnLeave()
	if GameTooltip:GetOwner() == self then
		GameTooltip:Hide();
	end
end
