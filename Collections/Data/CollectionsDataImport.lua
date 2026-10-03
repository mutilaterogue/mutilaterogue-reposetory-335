-- Converts WCollections.Mounts / WCollections.Pets into COLLECTIONS_COMPANION_DATA.
--
-- Mount row: { creatureID, mountType, flags, name, description, sourceType, sourceText, faction, isUsableFunc }
--   mountType: 1 flying, 2 ground, 3 aquatic, 6 flying with scripted ground version, 0 unused
--   rows without a name are not obtainable and are shown only when collected
-- Pet row:   { creatureID, petType, flags, name, description, sourceType, sourceText }
--   flags 0x20 = hidden
-- sourceType is 0-based BATTLE_PET_SOURCE (0 drop, 1 quest, 2 vendor ...), stored here as sourceType + 1.

COLLECTIONS_COMPANION_DATA = COLLECTIONS_COMPANION_DATA or {};

local MOUNT_TYPE_FLAGS = {
	[1] = 1,   -- flying
	[2] = 0,   -- ground
	[3] = 2,   -- aquatic
	[6] = 1,   -- flying (scripted ground version)
};

local function HasBit(value, mask)
	return (math.floor((value or 0) / mask) % 2) == 1;
end

local function ImportMounts()
	local result = {};
	for spellID, info in pairs(WCollections and WCollections.Mounts or {}) do
		local mountType = info[2] or 0;
		result[spellID] = {
			creatureID = info[1],
			flags = MOUNT_TYPE_FLAGS[mountType] or 0,
			name = info[4],
			lore = info[5],
			source = info[6] and info[6] >= 0 and (info[6] + 1) or nil,
			sourceText = info[7],
			faction = info[8],
			isUsableFunc = type(info[9]) == "function" and info[9] or nil,
			hidden = info[4] == nil or mountType == 0,
		};
	end
	return result;
end

local function ImportPets()
	local result = {};
	for spellID, info in pairs(WCollections and WCollections.Pets or {}) do
		result[spellID] = {
			creatureID = info[1],
			flags = 0,
			name = info[4],
			lore = info[5],
			source = info[6] and info[6] >= 0 and (info[6] + 1) or nil,
			sourceText = info[7],
			hidden = HasBit(info[3], 0x20),
		};
	end
	return result;
end

COLLECTIONS_COMPANION_DATA.MOUNT = ImportMounts();
COLLECTIONS_COMPANION_DATA.CRITTER = ImportPets();
