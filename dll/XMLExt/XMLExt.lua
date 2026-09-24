
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