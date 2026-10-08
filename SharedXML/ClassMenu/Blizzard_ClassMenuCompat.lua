-- 3.3.5: class API from retail used by ClassMenu (and the encounter journal / collections).

ALL_CLASSES = ALL_CLASSES or "Все классы";
ALL_SPECS = ALL_SPECS or "Все специализации";
HEIRLOOMS_CLASS_FILTER_FORMAT = HEIRLOOMS_CLASS_FILTER_FORMAT or "|c%s%s|r";

-- classID order of the 3.3.5 client (there is no class 10)
local CLASS_FILES = {
	[1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE", [5] = "PRIEST",
	[6] = "DEATHKNIGHT", [7] = "SHAMAN", [8] = "MAGE", [9] = "WARLOCK", [11] = "DRUID",
};
local CLASS_IDS_IN_ORDER = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 11 };

local function GetClassName(classFile)
	return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile] or classFile;
end

if not GetNumClasses then
	function GetNumClasses()
		return #CLASS_IDS_IN_ORDER;
	end
end

-- retail: GetClassInfo(index) -> className, classFile, classID
if not GetClassInfo then
	function GetClassInfo(index)
		local classID = CLASS_IDS_IN_ORDER[index] or index;
		local classFile = CLASS_FILES[classID];
		if not classFile then
			return nil;
		end
		return GetClassName(classFile), classFile, classID;
	end
end

C_CreatureInfo = C_CreatureInfo or {};
if not C_CreatureInfo.GetClassInfo then
	function C_CreatureInfo.GetClassInfo(classID)
		local classFile = CLASS_FILES[classID];
		if not classFile then
			return nil;
		end
		return { className = GetClassName(classFile), classFile = classFile, classID = classID };
	end
end

-- "ffRRGGBB" of a class (RAID_CLASS_COLORS in 3.3.5 has no colorStr)
function ClassMenu_GetClassColorStr(classFile)
	local color = RAID_CLASS_COLORS[classFile];
	if not color then
		return "ffffffff";
	end
	return color.colorStr or ("ff%02x%02x%02x"):format(color.r * 255, color.g * 255, color.b * 255);
end

GetClassicExpansionLevel = GetClassicExpansionLevel or function() return 2; end
LE_EXPANSION_CATACLYSM = LE_EXPANSION_CATACLYSM or 3;
