--------------------------------------------------------------------------------
--
--  ATLAS HELPER FOR WOTLK
--  Retail-like C_Texture Atlas API for WotLK 3.3.5a
--
--  Copyright (c) 2026 iThorgrim
--  https://github.com/iThorgrim
--
--------------------------------------------------------------------------------
--
--  This program is free software: you can redistribute it and/or modify
--  it under the terms of the GNU Affero General Public License as published
--  by the Free Software Foundation, either version 3 of the License, or
--  (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU Affero General Public License for more details.
--
--  You should have received a copy of the GNU Affero General Public License
--  along with this program.  If not, see <https://www.gnu.org/licenses/>.
--
--------------------------------------------------------------------------------
--
--  DESCRIPTION:
--    Provides a Retail WoW-compatible atlas system for WotLK 3.3.5a (build 12340).
--    Implements C_Texture. * API and SetAtlas() function for seamless atlas usage.
--
--  FEATURES:
--    • C_Texture.LoadAtlasData() - Load atlas coordinate data
--    • C_Texture. GetAtlasInfo()  - Retrieve atlas information
--    • SetAtlas()                - Apply atlas to texture objects
--    • Automatic SetTexture() hook for "atlas: name" syntax support
--
--  USAGE:
--    -- Load atlas data (typically done in AtlasInfo.lua)
--    C_Texture.LoadAtlasData(atlasTable)
--
--    -- Apply atlas to texture
--    SetAtlas(myTexture, "atlas-name", useAtlasSize)
--
--    -- Or use in XML
--    <Texture file="atlas: atlas-name" />
--
--  DEPENDENCIES:
--    • WotLK 3.3.5a (build 12340)
--    • AtlasInfo.lua (atlas coordinate data)
--
--  AUTHOR:
--    iThorgrim (https://github.com/iThorgrim)
--
--  VERSION:
--    1.0.0
--
--  DATE:
--    2026-01-14
--
--  REPOSITORY:
--    https://github.com/iThorgrim/WotLK-Atlas-System
--
--------------------------------------------------------------------------------

if not C_Texture then
    C_Texture = {};
end

local AtlasCache = {};

function C_Texture.LoadAtlasData(atlasInfo)
    if not atlasInfo then
        return 0;
    end

    local count = 0;

    for fileKey, atlasGroup in pairs(atlasInfo) do
        local texturePath;

        texturePath = fileKey;
        if texturePath then
            for atlasName, atlasData in pairs(atlasGroup) do
                local width = atlasData[1];
                local height = atlasData[2];
                local left = atlasData[3];
                local right = atlasData[4];
                local top = atlasData[5];
                local bottom = atlasData[6];

                local name = atlasName;
                AtlasCache[name] = {
                    width = width,
                    height = height,
                    left = left,
                    right = right,
                    top = top,
                    bottom = bottom,
                    file = texturePath
                };
                
				AtlasCache[strlower(name)] = AtlasCache[name];
                count = count + 1;
            end
        end
    end

    return count;
end

function C_Texture.GetAtlasInfo(atlasName)
    if not atlasName or atlasName == "" then
        return nil;
    end
    return AtlasCache[atlasName] or AtlasCache[strlower(atlasName)];
end

function SetAtlas(texture, atlasName, useAtlasSize)
    if not texture or not atlasName or atlasName == "" then
        return false;
    end

    local info = C_Texture.GetAtlasInfo(atlasName);

    if not info or not info.file then
        return false;
    end

    local success = pcall(function()
        texture:SetTexture(info.file);
        texture:SetTexCoord(info.left, info. right, info.top, info.bottom);

        if useAtlasSize then
            texture:SetWidth(info.width);
            texture:SetHeight(info.height);
        end
    end);

    return success;
end

C_Texture.SetAtlas = SetAtlas;

-- ========================================
-- Texture methods: SetAtlas / GetAtlas + "atlas:" в SetTexture
-- ========================================
local dummyFrame = CreateFrame("Frame")
local dummyTexture = dummyFrame:CreateTexture()
local textureMeta = getmetatable(dummyTexture).__index

local OriginalSetTexture = textureMeta.SetTexture
local atlasOf = setmetatable({}, { __mode = "k" })

textureMeta.SetTexture = function(self, texture, ...)
    if type(texture) == "string" then
        local atlasName = texture:match("^atlas:%s*(.-)%s*$")
        if atlasName and atlasName ~= "" then
            return self:SetAtlas(atlasName, false)
        end
    end

    atlasOf[self] = nil
    return OriginalSetTexture(self, texture, ...)
end

textureMeta.SetAtlas = function(self, atlasName, useAtlasSize)
    local info = C_Texture.GetAtlasInfo(atlasName)

    if not info or not info.file then
        geterrorhandler()(("SetAtlas: unknown atlas '%s'"):format(tostring(atlasName)))
        return false
    end

    OriginalSetTexture(self, info.file)
    self:SetTexCoord(info.left, info.right, info.top, info.bottom)

    if useAtlasSize then
        self:SetWidth(info.width)
        self:SetHeight(info.height)
    end

    atlasOf[self] = atlasName
    return true
end

textureMeta.GetAtlas = function(self)
    return atlasOf[self]
end

function SetAtlas(texture, atlasName, useAtlasSize)
    if not texture or not texture.SetAtlas then
        return false
    end
    return texture:SetAtlas(atlasName, useAtlasSize)
end

C_Texture.SetAtlas = SetAtlas

-- ========================================
-- Button methods: SetNormalAtlas / SetPushedAtlas / SetDisabledAtlas / SetHighlightAtlas
-- ========================================
local function MakeButtonAtlasSetter(setTexture, getTexture)
	return function(self, atlasName, useAtlasSize, blendMode)
		local info = C_Texture.GetAtlasInfo(atlasName)
		if not info or not info.file then
			geterrorhandler()(("%s: unknown atlas '%s'"):format(setTexture, tostring(atlasName)))
			return false
		end

		-- SetXTexture(file) создаёт текстуру состояния, если её ещё нет
		if blendMode then
			self[setTexture](self, info.file, blendMode)
		else
			self[setTexture](self, info.file)
		end

		local tex = self[getTexture](self)
		if tex then
			tex:SetTexCoord(info.left, info.right, info.top, info.bottom)
			atlasOf[tex] = atlasName
			if useAtlasSize then
				tex:SetWidth(info.width)
				tex:SetHeight(info.height)
			end
		end
		return true
	end
end

local buttonAtlasMethods = {
	SetNormalAtlas    = MakeButtonAtlasSetter("SetNormalTexture", "GetNormalTexture"),
	SetPushedAtlas    = MakeButtonAtlasSetter("SetPushedTexture", "GetPushedTexture"),
	SetDisabledAtlas  = MakeButtonAtlasSetter("SetDisabledTexture", "GetDisabledTexture"),
	SetHighlightAtlas = MakeButtonAtlasSetter("SetHighlightTexture", "GetHighlightTexture"),
}

-- в 3.3.5 у Button и CheckButton разные метатаблицы, патчим обе
for _, frameType in ipairs({ "Button", "CheckButton" }) do
	local meta = getmetatable(CreateFrame(frameType)).__index
	for name, fn in pairs(buttonAtlasMethods) do
		if not meta[name] then
			meta[name] = fn
		end
	end
end