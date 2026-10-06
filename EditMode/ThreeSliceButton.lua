-- The retail ThreeSliceButtonTemplate (Blizzard_SharedXML\Button\ThreeSliceButtonTemplate.lua) for 3.3.5:
-- a button drawn from three atlases, atlasName-Left / _atlasName-Center / atlasName-Right (-Pressed / -Disabled),
-- the ends scaled to the button's height, cut down when the button is too narrow for them.
-- UIPanelButtonRetailTemplate: the retail red panel button (128-RedButton), as retail UIPanelButtonTemplate.

ThreeSliceButtonMixin = {};

local function AtlasRect(texture)
	local ulx, uly, llx, lly, urx = texture:GetTexCoord();
	return ulx, urx, uly, lly;
end

function ThreeSliceButtonMixin:OnLoad()
	self.atlasName = self.atlasName or "128-RedButton";
	self:UpdateButton();
end

-- the ends at the button's height; too wide for the button together: cut from the bigger one (retail UpdateScale)
function ThreeSliceButtonMixin:UpdateScale()
	local leftInfo = C_Texture.GetAtlasInfo(self.atlasName .. "-Left");
	local rightInfo = C_Texture.GetAtlasInfo(self.atlasName .. "-Right");
	if not leftInfo or not rightInfo then
		return;
	end
	local height = self:GetHeight();
	local width = self:GetWidth();
	if height <= 0 or not self.leftRect then
		return;
	end
	local scale = height / leftInfo.height;
	local leftWidth = leftInfo.width * scale;
	local rightWidth = rightInfo.width * scale;
	local newLeft, newRight = leftWidth, rightWidth;

	if leftWidth + rightWidth > width then
		local extra = leftWidth + rightWidth - width;
		if leftWidth - extra > rightWidth then
			newLeft = leftWidth - extra;
		elseif rightWidth - extra > leftWidth then
			newRight = rightWidth - extra;
		else
			if leftWidth ~= rightWidth then
				extra = extra - math.abs(leftWidth - rightWidth);
				newLeft = math.min(leftWidth, rightWidth);
				newRight = newLeft;
			end
			newLeft = newLeft - extra / 2;
			newRight = newRight - extra / 2;
		end
	end

	-- the cut on the atlas' own coords: the left end keeps its left part, the right end its right part
	local l, r, t, b = unpack(self.leftRect);
	self.Left:SetTexCoord(l, l + (r - l) * (newLeft / leftWidth), t, b);
	self.Left:SetWidth(math.max(newLeft, 0.01));
	self.Left:SetHeight(height);
	l, r, t, b = unpack(self.rightRect);
	self.Right:SetTexCoord(r - (r - l) * (newRight / rightWidth), r, t, b);
	self.Right:SetWidth(math.max(newRight, 0.01));
	self.Right:SetHeight(height);
end

function ThreeSliceButtonMixin:UpdateButton(state)
	state = state or self:GetButtonState();
	if not self:IsEnabled() then
		state = "DISABLED";
	end
	local postfix = state == "DISABLED" and "-Disabled" or state == "PUSHED" and "-Pressed" or "";
	self.Left:SetAtlas(self.atlasName .. "-Left" .. postfix);
	self.Center:SetAtlas("_" .. self.atlasName .. "-Center" .. postfix);
	self.Right:SetAtlas(self.atlasName .. "-Right" .. postfix);
	self.leftRect = { AtlasRect(self.Left) };
	self.rightRect = { AtlasRect(self.Right) };
	self:UpdateScale();
end

function ThreeSliceButton_OnLoad(self)
	for key, value in pairs(ThreeSliceButtonMixin) do
		self[key] = value;
	end
	self:OnLoad();
end

function ThreeSliceButton_OnMouseDown(self)
	if self:IsEnabled() == 1 or self:IsEnabled() == true then
		self:UpdateButton("PUSHED");
	end
end

function ThreeSliceButton_OnMouseUp(self)
	self:UpdateButton("NORMAL");
end

-- (3.3.5 has no OnEnable / OnDisable scripts on every client build: Enable / Disable redraw the art)
function ThreeSliceButton_HookState(self)
	hooksecurefunc(self, "Enable", function(button) button:UpdateButton(); end);
	hooksecurefunc(self, "Disable", function(button) button:UpdateButton(); end);
end
