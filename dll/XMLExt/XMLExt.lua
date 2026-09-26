
-- where ... are the mixins to mixin
function Mixin(object, ...)
	for i = 1, select("#", ...) do
		local mixin = select(i, ...);
		for k, v in pairs(mixin) do
			object[k] = v;
		end
	end

	return object;
end

function CreateFromMixins(...)
    return Mixin({}, ...)
end

function CreateAndInitFromMixin(mixin, ...)
    local object = CreateFromMixins(mixin)
    object:Init(...)
    return object
end

-- XMLExt
local SEP_ENTRY, SEP_FIELD = "\1", "\2"

local function split(s, sep)
    local t = {}
    for part in (s .. sep):gmatch("(.-)" .. sep) do
        t[#t + 1] = part
    end
    return t
end

local function entries(s)
    local out = {}
    if not s then return out end
    for _, e in ipairs(split(s, SEP_ENTRY)) do
        if e ~= "" then
            out[#out + 1] = split(e, SEP_FIELD)
        end
    end
    return out
end

local function resolve(path)
    local t = _G
    for part in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end

local function applyMixins(obj, list)
    if not list then return end
    for name in list:gmatch("[^,%s]+") do
        local m = resolve(name)
        if type(m) == "table" then
            for k, v in pairs(m) do obj[k] = v end
        else
            geterrorhandler()(("XMLExt: mixin '%s' not found"):format(name))
        end
    end
end

local function convertValue(value, vtype)
    vtype = (vtype and vtype ~= "") and vtype:lower() or "string"
    if vtype == "number" then
        return tonumber(value)
    elseif vtype == "boolean" then
        return value == "true"
    elseif vtype == "nil" then
        return nil
    elseif vtype == "global" then
        return resolve(value)
    end
    return value
end

local function applyKeyValues(obj, kv)
    for _, f in ipairs(entries(kv)) do
        obj[f[1]] = convertValue(f[2], f[3])
    end
end

local function isTrue(v)
    return v and v:lower() == "true"
end

local function safeGetScript(obj, name)
    local ok, fn = pcall(obj.GetScript, obj, name)
    return ok and fn or nil
end

-- obj -> { scriptName = handler }, состояние после последнего применённого узла (шаблона)
local scriptSnapshot = setmetatable({}, { __mode = "k" })

local function applyScripts(obj, scripts)
    if not obj.SetScript then return end

    local snap = scriptSnapshot[obj]
    if not snap then
        snap = {}
        scriptSnapshot[obj] = snap
    end

    for _, f in ipairs(entries(scripts)) do
        local name, method, func, inherit = f[1], f[2], f[3], f[4]
        local current = safeGetScript(obj, name)
        local handler = current

        if method and method ~= "" then
            handler = function(self, ...)
                local m = self[method]
                if m then return m(self, ...) end
            end
        elseif func and func ~= "" then
            handler = resolve(func)
        end

        local prev = snap[name]
        inherit = inherit and inherit:lower()

        if handler and prev and prev ~= handler then
            local own = handler
            if inherit == "prepend" then
                handler = function(...) own(...) prev(...) end
            elseif inherit == "append" then
                handler = function(...) prev(...) own(...) end
            end
        end

        if handler ~= current then
            obj:SetScript(name, handler)
        end

        snap[name] = handler
    end
end

function __XMLExt_Pre(obj, mixins, secureMixins, kv)
    if type(obj) ~= "table" then return end
    applyMixins(obj, mixins)
    applyMixins(obj, secureMixins)
    applyKeyValues(obj, kv)
end

function __XMLExt_Post(obj, parent, parentKey, parentArray, mixins, secureMixins, kv, useParentLevel, atlas, useAtlasSize, scripts, textureSubLevel)
    if type(obj) ~= "table" then return end

    -- повторно, чтобы собственные значения перебили шаблонные
    applyMixins(obj, mixins)
    applyMixins(obj, secureMixins)
    applyKeyValues(obj, kv)

    if type(parent) == "table" then
        if parentKey then
            parent[parentKey] = obj
        end
        if parentArray then
            local arr = parent[parentArray]
            if not arr then
                arr = {}
                parent[parentArray] = arr
            end
            local found = false
            for i = 1, #arr do
                if arr[i] == obj then found = true break end
            end
            if not found then arr[#arr + 1] = obj end
        end

        if isTrue(useParentLevel) and obj.SetFrameLevel and parent.GetFrameLevel then
            obj:SetFrameLevel(parent:GetFrameLevel())
        end
    end

    if atlas then
        if obj.SetAtlas then
            obj:SetAtlas(atlas, isTrue(useAtlasSize))
        else
            geterrorhandler()(("XMLExt: SetAtlas missing for atlas '%s'"):format(atlas))
        end
    end

    if scripts then
        applyScripts(obj, scripts)
    end

    local subLevel = tonumber(textureSubLevel);
	if subLevel and subLevel ~= 0 and obj.GetDrawLayer then
		DrawLayerUtil.SetSubLevel(obj, subLevel);
	end
end

---------------------------------------------------------------------------
-- MaskTexture (WotLKExtensions MaskTexture patch): the retail mask texture API
--   frame:CreateMaskTexture([name, layer, inherits])  a Texture that is not drawn, only masks
--   texture:AddMaskTexture(mask) / RemoveMaskTexture(mask) / GetNumMaskTextures() / GetMaskTexture(index)
--   XML: <MaskTexture ...><MaskedTextures><MaskedTexture childKey="Icon"/></MaskedTextures></MaskTexture>
-- Up to 3 masks per texture are drawn. A mask must stay shown (a hidden region is not laid out);
-- it is never drawn anyway. Outside its rect a mask repeats its edge pixels (keep the edges transparent).
-- Here (not in a separate file) so it loads first, with the XML hooks; the DLL functions
-- (TextureAddMask & co) are looked up when used.
---------------------------------------------------------------------------
MASKTEXTURE_LUA_VERSION = 3;

do
	local helper = CreateFrame("Frame");
	helper:Hide();
	local textureMethods = getmetatable(helper:CreateTexture()).__index;

	function textureMethods:AddMaskTexture(mask)
		if not TextureAddMask then
			return;
		end
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
		if TextureRemoveMask then
			TextureRemoveMask(self, mask);
		end
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
		if TextureSetIsMask then
			TextureSetIsMask(mask, true);
		end
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

	-- masks loaded before the DLL functions were registered: applied at login
	local deferredMasks = {};	-- { {mask, frame or nil, "keys" or nil}, ... }

	local function ApplyMask(mask, frame, keys)
		TextureSetIsMask(mask, true);
		if not (frame and keys) then
			return;
		end
		for key in keys:gmatch("[^,%s]+") do
			local texture = FindChild(frame, key);
			if texture and texture.AddMaskTexture then
				texture:AddMaskTexture(mask);
			else
				geterrorhandler()(("MaskTexture: MaskedTexture childKey '%s' not found"):format(key));
			end
		end
	end

	-- the texture of a <MaskTexture> node: a mask; its masked textures are resolved after the frame's load
	function __XMLExt_Mask(mask, parent, keys)
		if type(mask) ~= "table" then
			return;
		end
		if type(parent) ~= "table" then
			parent, keys = nil, nil;
		end
		local list = parent and pendingMasks[parent];
		if parent and not list then
			list = {};
			pendingMasks[parent] = list;
		end
		if list then
			list[#list + 1] = { mask, keys };
		elseif TextureSetIsMask then
			TextureSetIsMask(mask, true);
		else
			deferredMasks[#deferredMasks + 1] = { mask };
		end
	end

	function __XMLExt_ResolveMasks(frame)
		local list = type(frame) == "table" and pendingMasks[frame];
		if not list then
			return;
		end
		pendingMasks[frame] = nil;
		for _, entry in ipairs(list) do
			if TextureSetIsMask and TextureAddMask then
				ApplyMask(entry[1], frame, entry[2]);
			else
				deferredMasks[#deferredMasks + 1] = { entry[1], frame, entry[2] };
			end
		end
	end

	helper:RegisterEvent("PLAYER_LOGIN");
	helper:SetScript("OnEvent", function(self)
		self:UnregisterAllEvents();
		if not (TextureSetIsMask and TextureAddMask) then
			return;
		end
		for _, entry in ipairs(deferredMasks) do
			ApplyMask(entry[1], entry[2], entry[3]);
		end
		wipe(deferredMasks);
	end);
end
