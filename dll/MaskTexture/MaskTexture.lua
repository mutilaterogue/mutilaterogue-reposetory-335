-- Retail mask texture API on top of the WotLKExtensions MaskTexture patch (TextureAddMask & co).
--   frame:CreateMaskTexture([name, layer, inherits])  a Texture that is not drawn, only masks
--   texture:AddMaskTexture(mask) / RemoveMaskTexture(mask) / GetNumMaskTextures() / GetMaskTexture(index)
--   XML: <MaskTexture ...><MaskedTextures><MaskedTexture childKey="Icon"/></MaskedTextures></MaskTexture>
-- Up to 3 masks per texture are drawn. A mask must stay shown (a hidden region is not laid out);
-- it is never drawn anyway. Outside its rect a mask repeats its edge pixels (keep the edges transparent).
-- Loaded early (FrameXML.toc snippets, after XMLExt.lua): no WorldFrame/UIParent yet.
if not TextureAddMask then
	return;
end

local helper = CreateFrame("Frame");
helper:Hide();
local textureMethods = getmetatable(helper:CreateTexture()).__index;

function textureMethods:AddMaskTexture(mask)
	TextureAddMask(self, mask);
	local masks = self.maskTextures;
	if not masks then
		masks = {};
		self.maskTextures = masks;
	end
	for i = 1, #masks do
		if masks[i] == mask then
			return;
		end
	end
	masks[#masks + 1] = mask;
end

function textureMethods:RemoveMaskTexture(mask)
	TextureRemoveMask(self, mask);
	local masks = self.maskTextures;
	if not masks then
		return;
	end
	for i = #masks, 1, -1 do
		if not mask or masks[i] == mask then
			table.remove(masks, i);
		end
	end
end

function textureMethods:GetNumMaskTextures()
	return self.maskTextures and #self.maskTextures or 0;
end

function textureMethods:GetMaskTexture(index)
	return self.maskTextures and self.maskTextures[index];
end

local function CreateMaskTexture(self, name, layer, inherits)
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

---------------------------------------------------------------------------
-- <MaskTexture> (XMLExt): the DLL loads it as a Texture, then calls these
---------------------------------------------------------------------------
local pendingMasks = setmetatable({}, { __mode = "k" });	-- [frame] = { {mask, "key1,key2"}, ... }

local function FindChild(frame, path)
	local object = frame;
	for part in path:gmatch("[^%.]+") do
		if part == "$parent" then
			object = object.GetParent and object:GetParent();
		elseif type(object) == "table" then
			object = object[part];
		else
			return nil;
		end
	end
	if object then
		return object;
	end
	-- 3.3.5 ignores parentKey next to name="...": the global name, also as $parent<key>
	local frameName = frame.GetName and frame:GetName();
	return _G[path] or (frameName and _G[frameName .. path]);
end

-- the texture of a <MaskTexture> node: a mask; its masked textures are resolved after the frame's load
function __XMLExt_Mask(mask, parent, keys)
	if type(mask) ~= "table" then
		return;
	end
	TextureSetIsMask(mask, true);
	if keys and type(parent) == "table" then
		local list = pendingMasks[parent];
		if not list then
			list = {};
			pendingMasks[parent] = list;
		end
		list[#list + 1] = { mask, keys };
	end
end

function __XMLExt_ResolveMasks(frame)
	local list = type(frame) == "table" and pendingMasks[frame];
	if not list then
		return;
	end
	pendingMasks[frame] = nil;
	for _, entry in ipairs(list) do
		local mask, keys = entry[1], entry[2];
		for key in keys:gmatch("[^,%s]+") do
			local texture = FindChild(frame, key);
			if texture and texture.AddMaskTexture then
				texture:AddMaskTexture(mask);
			else
				geterrorhandler()(("MaskTexture: MaskedTexture childKey '%s' not found"):format(key));
			end
		end
	end
end
