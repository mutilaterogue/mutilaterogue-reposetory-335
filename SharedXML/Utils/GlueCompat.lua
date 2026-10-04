-- GlueXML (login, character select / create): what the SharedXML code expects from the game UI.
-- Loaded by GlueXML.toc right after Compat.lua; does nothing in the game (FrameXML), where all of it exists.

-- XML of SharedXML anchors to UIParent: on the login screen a full screen frame of that name
if not UIParent then
	local parent = CreateFrame("Frame", "UIParent");
	parent:SetPoint("TOPLEFT", 0, 0);
	parent:SetPoint("BOTTOMRIGHT", 0, 0);
	parent:SetFrameStrata("BACKGROUND");
end

-- table helpers of FrameXML\Util.lua the early SharedXML files use before it may load
if not tInvert then
	function tInvert(tbl)
		local inverted = {};
		for k, v in pairs(tbl) do
			inverted[v] = k;
		end
		return inverted;
	end
end

if not tContains then
	function tContains(tbl, item)
		for _, v in pairs(tbl) do
			if v == item then
				return true;
			end
		end
		return false;
	end
end

-- TextureUtil.lua (role icons) indexes these at load
Enum = Enum or {};
Enum.LFGRole = Enum.LFGRole or { Tank = 0, Healer = 1, Damage = 2 };
Constants = Constants or {};
Constants.LFG_ROLEConstants = Constants.LFG_ROLEConstants or { LFG_ROLE_NO_ROLE = -1 };
