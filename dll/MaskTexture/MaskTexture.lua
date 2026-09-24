-- Retail mask texture methods on top of the WotLKExtensions MaskTexture patch (TextureAddMask & co).
--   frame:CreateMaskTexture([name, layer, inherits])  a Texture that is not drawn, only masks
--   texture:AddMaskTexture(mask) / RemoveMaskTexture(mask) / GetNumMaskTextures() / GetMaskTexture(index)
-- One mask per texture. A mask must stay shown (a hidden region is not laid out), it is not drawn anyway.
if not TextureAddMask then
	return;
end

local textureMethods = getmetatable(WorldFrame:CreateTexture()).__index;

function textureMethods:AddMaskTexture(mask)
	TextureAddMask(self, mask);
	self.maskTexture = mask;
end

function textureMethods:RemoveMaskTexture(mask)
	TextureRemoveMask(self, mask);
	if not mask or self.maskTexture == mask then
		self.maskTexture = nil;
	end
end

function textureMethods:GetNumMaskTextures()
	return self.maskTexture and 1 or 0;
end

function textureMethods:GetMaskTexture(index)
	if index == 1 then
		return self.maskTexture;
	end
end

local function CreateMaskTexture(self, name, layer, inherits, subLevel)
	local mask = self:CreateTexture(name, layer or "ARTWORK", inherits);
	TextureSetIsMask(mask, true);
	return mask;
end

-- every frame type has its own method table
local frameTypes = {
	"Frame", "Button", "CheckButton", "StatusBar", "Slider", "ScrollFrame", "EditBox", "Cooldown",
	"Model", "PlayerModel", "DressUpModel", "TabardModel", "MessageFrame", "ScrollingMessageFrame",
	"SimpleHTML", "ColorSelect", "GameTooltip",
};
for _, frameType in ipairs(frameTypes) do
	local ok, frame = pcall(CreateFrame, frameType);
	if ok and frame then
		getmetatable(frame).__index.CreateMaskTexture = CreateMaskTexture;
		frame:Hide();
	end
end
